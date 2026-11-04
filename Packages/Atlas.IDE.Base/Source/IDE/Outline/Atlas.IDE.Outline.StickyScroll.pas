unit Atlas.IDE.Outline.StickyScroll;

// Mitlaufender Kopf (#506, experimentell) im Editor. Welche Kopfzeilen oben
// stehen, rechnet Atlas.Core.Outline.StickyScroll; hier bleiben Gliederung,
// Zeichnen und Klick.
// - Ein Zeitgeber (100 ms) holt für die aktive Ansicht den Stand von
//   TAtlasIdeOutlineCache (gemeinsam mit Gliederungsfenster und
//   Brotkrumenleiste, keine eigene Serveranfrage). Ändern sich Datei oder
//   Stand, zeichnet der Editor neu.
// - Zeichnen per PaintLine (plsEndPaint): Die ersten Bildschirmzeilen des
//   Codebereichs werden mit der Hintergrundfarbe des Editors übermalt, darauf
//   die Köpfe in seiner Schrift mit ihrer Einrückung; unter der letzten Zeile
//   eine Trennlinie.
// - Farben (#1229): Klammern und Blockwörter des Kopfs wie im Editor in der
//   Farbe ihrer Tiefe (PairColors, eigene Paarfarben je Hell/Dunkel), Besitzer
//   wie procedure/function nur mit PairOwners; unpaarige in der Fehlerfarbe.
//   Die Paaranalyse läuft je neuem Stand der Gliederung einmal.
// - Blocklinien: Jede beginnt mit ihrem Haken in der Kopfzeile ihres
//   Elements. Hat das Element keine Kopfzeile (Art aus, zu kurz,
//   zusammengefasst), blendet die Linie in der letzten Kopfzeile von oben ein
//   (TAtlasStickyScroll.GuideStart, FadeWeight), statt ohne Anfang unter der
//   Trennlinie aufzutauchen.
// - Was der Kopf zeigt, ist je Art einstellbar: Klassen/Records
//   (editor.stickyScrollTypes) und Routinen (editor.stickyScrollRoutines) aus
//   der Gliederung; Anweisungsblöcke der Paaranalyse ab
//   editor.stickyScrollBlockMinLines Zeilen nach ihrem ersten Besitzerwort:
//   if/else (#1230, editor.stickyScrollBlocks), for/while/repeat
//   (editor.stickyScrollLoops), try, case, with (editor.stickyScrollTry,
//   …Case, …With). Jeder steht als eigene Zeile im Kopf.
// - Bildlauf (#1228): Der Editor verschiebt beim Bildlauf die schon gemalten
//   Pixel (ScrollDC) und malt nur die neuen Zeilen; der alte Kopf wanderte so
//   als Rest mit. Solange der Kopf an ist, schaltet UIOptions das Verschieben
//   ab (ceoDisableScrollDC), und EditorScrolled zeichnet sofort ganz neu.
//   Zeitgeber und PaintLine fangen Bildläufe ohne Ereignis weiter ab.
// - Klick (links, ohne Umschalttasten) auf eine Kopfzeile springt nach dem
//   Mausereignis zum Namen im Kopf.
// - Die oberste Zeile ist View.TopRow; zugeklappte Bereiche darunter zählt
//   der Kopf wie offene.
// editor.stickyScroll aus: nichts wird gezeichnet, kein Klick abgefangen.
// Nur im Hauptthread.

interface

type
  TAtlasIdeStickyScroll = class
  private class var
    FState: TObject;
  public
    /// <summary>Den Server fragt TAtlasIdeOutlineCache (vorher installieren).</summary>
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>Einstellung geändert: Editor neu zeichnen.</summary>
    class procedure ApplySettings; static;
    class function Enabled: Boolean; static;
    /// <summary>Zeilen, die der Kopf oben im Editor zu AFileName verdeckt; 0 ohne Kopf. Die Blocklinien des
    /// Editors bleiben dort weg, der Kopf zeichnet sie selbst.</summary>
    class function CoveredRows(const AFileName: string): Integer; static;
    /// <summary>True, wenn die Blocklinie in Spalte AColumn in der ersten Zeile unter dem Kopf spitz beginnen soll:
    /// Ihr Element ist hinter dem Kopf verschwunden, und ihre Spitze läge im Text der letzten Kopfzeile.</summary>
    class function TaperBelow(const AFileName: string; AColumn: Integer): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  System.Win.Registry,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.StickyScroll,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.Guides,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Foundation.EditorRefresh;

const
  TickMs = 100;

var
  /// <summary>Neuzeichnen eingereiht; außerhalb des Zustands, weil der Eintrag ihn nicht kennen soll.</summary>
  InvalidatePending: Boolean;
  /// <summary>Kopf an: Der Editor soll beim Bildlauf nicht verschieben (UIOptions, #1228).</summary>
  StickyShown: Boolean;

type
  TEvents = class(TNTACodeEditorNotifier)
  protected
    function AllowedEvents: TCodeEditorEvents; override;
    function AllowedLineStages: TPaintLineStages; override;
    // ceoDisableScrollDC ist für Delphi 13 belegt; unter Delphi 12 bleiben EditorScrolled und Zeitgeber.
    {$IF CompilerVersion >= 37.0}
    function UIOptions: TCodeEditorUIOptions; override;
    {$IFEND}
  end;

  /// <summary>Darstellung eines Elements aus dem Farbschema des Editors.</summary>
  TSyntaxStyle = record
    Color: TColor;
    /// <summary>False: Vorgabefarbe des Editors (Default Foreground), dann die Textfarbe des Kopfs.</summary>
    HasColor: Boolean;
    Style: TFontStyles;
  end;

  /// <summary>Was alle Blocklinien einer Kopfzeile teilen: Gerät, Zeile, Codebereich, Stiftbreite, Farben.</summary>
  TGuidePaint = record
    Context: INTACodeEditorPaintContext;
    DC: HDC;
    Rect: TRect;
    Code: TRect;
    Width: Integer;
    Opacity: Integer;
    Colors: TAtlasColors;
    Back: TAtlasColor;
    /// <summary>Hintergrund des Kopfs: Dort beginnt die Spitze eingeblendeter Linien.</summary>
    HeadBack: TAtlasColor;
  end;

  /// <summary>Werkzeuge der Leinwand, vor dem Zeichnen gesichert und danach zurückgesetzt.</summary>
  TSavedTools = record
    Font: TFont;
    Brush: TBrush;
    Pen: TPen;
    class function Save(ACanvas: TCanvas): TSavedTools; static;
    /// <summary>Zurücksetzen und die Sicherung freigeben.</summary>
    procedure Restore(ACanvas: TCanvas);
  end;

  TSyntaxStyles = array[TAtlasStickySyntax] of TSyntaxStyle;

  /// <summary>Stand des Kopfs: Gliederung, Zeilen, Paaranalyse und Farbschema der Datei FFileName.</summary>
  TStickyData = class
  private
    FFileName: string;
    FStamp: Cardinal;
    FNodes: TAtlasOutlineNodes;
    FLines: TArray<string>;
    /// <summary>Paar-Token je Zeile von FLines (#1229).</summary>
    FPairs: TArray<TArray<TAtlasPairToken>>;
    /// <summary>Anweisungsblöcke der eingestellten Arten (#1230), alle Längen; nach Länge gefiltert wird beim
    /// Zeichnen.</summary>
    FBranches: TArray<TAtlasStickyBlock>;
    /// <summary>Blöcke der Paaranalyse und daraus die Blocklinien (je Tabulatorbreite und Besitzer-Schalter).</summary>
    FBlocks: TArray<TAtlasPairBlock>;
    FGuides: TArray<TAtlasGuide>;
    FGuidesKey: string;
    /// <summary>Farbschema des Editors je Art (Editor\Highlight), gelesen mit jedem neuen Stand.</summary>
    FSyntax: TSyntaxStyles;
    /// <summary>Hintergrund aus dem Farbschema (Plain text); vor dem Abtasten, das bei markierten oder
    /// hervorgehobenen Zeilen deren Farbe träfe (#1245).</summary>
    FSchemeBack: TAtlasColor;
    FSchemeBackKnown: Boolean;
    procedure AnalyzePairs(const AText: string);
    procedure ReadSyntax;
    /// <summary>Blocklinien zur Tabulatorbreite ATabWidth und zum Besitzer-Schalter AOwners, nur bei Änderung neu.
    /// </summary>
    procedure EnsureGuides(ATabWidth: Integer; AOwners: Boolean);
  end;

  /// <summary>Zeichnen des Kopfs: Kopfzeilen zur obersten Zeile und was zuletzt gezeichnet wurde.</summary>
  TStickyPainter = class(TStickyData)
  private
    FMaxLines: Integer;
    /// <summary>Köpfe für die oberste Zeile FRowsTop (0-basiert, -1 = neu rechnen).</summary>
    FRows: TAtlasStickyRows;
    FRowsTop: Integer;
    FRowsMax: Integer;
    /// <summary>Zuletzt gezeichnet: Zeilenhöhe, linker Rand des Codebereichs, oberste Zeile.</summary>
    FRowHeight: Integer;
    FCodeLeft: Integer;
    FPaintedTop: Integer;
    FPaintedRows: Integer;
    /// <summary>Spalten der Linien ohne Kopfzeile, deren Spitze im Text der letzten Kopfzeile läge: Die
    /// Blocklinien des Editors zeichnen sie spitz in der ersten Zeile unter dem Kopf (TaperBelow).</summary>
    FTaperColumns: TArray<Integer>;
    /// <summary>Hintergrund des Editors aus einer nicht übermalten Zeile.</summary>
    FBack: TAtlasColor;
    FBackKnown: Boolean;
    /// <summary>Köpfe zur obersten Zeile ATop neu rechnen, wenn sie oder die Zeilenzahl sich geändert haben.</summary>
    procedure UpdateRows(const AView: IOTAEditView; ATop: Integer);
    /// <summary>Gezeichnet ab oberster Zeile ATop mit Zeilenhöhe AHeight merken; True, wenn der Editor beim
    /// Bildlauf nur einen Teil gemalt hat und alte Köpfe verschoben stehen (dann ganz neu zeichnen).</summary>
    function Painted(ATop, AHeight: Integer): Boolean;
    /// <summary>Hintergrund des Editors an einer nicht übermalten Zeile abtasten.</summary>
    procedure SampleBack(const ARect: TRect; const AContext: INTACodeEditorPaintContext);
    /// <summary>Hintergrund unter dem Kopf: Farbschema, abgetastet oder an ARect.</summary>
    function RowBack(ACanvas: TCanvas; const ARect: TRect): TAtlasColor;
    /// <summary>Kopfzeile unter dem Mauspunkt X, Y (Editorkoordinaten); False außerhalb des Kopfs.</summary>
    function RowAt(X, Y: Integer; out ARow: Integer): Boolean;
    /// <summary>Paarfarben-Stücke der Kopfzeile ARow; leer ohne PairColors oder in dieser Datei ausgeblendet.</summary>
    function RowSpans(const ARow: TAtlasStickyRow): TArray<TAtlasPairSpan>;
    /// <summary>Linie AGuide in Kopfzeile ARowIndex, wenn ihr Element hier oder darüber eine Kopfzeile hat.</summary>
    procedure DrawGuide(const APaint: TGuidePaint; const AGuide: TAtlasGuide; ARowIndex: Integer);
    procedure PaintRow(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext);
    /// <summary>Blocklinien im Kopf: Jede beginnt mit Haken in der Kopfzeile ihres Elements; ohne Kopfzeile blendet
    /// sie in der letzten Kopfzeile ein.</summary>
    procedure DrawGuides(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext;
      ABack: TAtlasColor);
    /// <summary>Kopftext ab ALeft; Klammern und Blockwörter in der Farbe ihrer Tiefe (#1229).</summary>
    procedure DrawHeader(ACanvas: TCanvas; ALeft, ATop: Integer; const ARow: TAtlasStickyRow;
      const AColors: TAtlasColors; ATextColor: TColor);
  end;

  TStickyState = class(TStickyPainter)
  private
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FOn: Boolean;
    procedure Tick(Sender: TObject);
    procedure Clear;
    procedure Update;
    procedure QueueInvalidate;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ApplySettings;
  end;

procedure InvalidateEditor;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

{ TEvents }

function TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents, cevWindowEvents];
end;

function TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{$IF CompilerVersion >= 37.0}
function TEvents.UIOptions: TCodeEditorUIOptions;
begin
  // Ohne Kopf verschiebt der Editor wie gewohnt (schneller).
  if StickyShown then
  begin
    Result := [ceoDisableScrollDC];
  end
  else
  begin
    Result := [];
  end;
end;
{$IFEND}

{ TStickyState }

constructor TStickyState.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FRowsTop := -1;
  FPaintedTop := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  FEvents.OnEditorScrolled := EditorScrolled;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
  ApplySettings;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TStickyState.Destroy;
var
  Services: INTACodeEditorServices;
  Shown: Boolean;
begin
  FTimer.Free;
  Shown := FPaintedRows > 0;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEvents.OnEditorScrolled := nil;
  FEventsRef := nil;
  StickyShown := False;
  if Shown then
  begin
    InvalidateEditor;
  end;
  inherited Destroy;
end;

procedure TStickyState.ApplySettings;
var
  Settings: TAtlasPluginSettings;
  Was: Boolean;
begin
  Settings := TAtlasIdeSettings.Current;
  Was := FOn;
  FOn := Settings.Enabled and Settings.StickyScroll and not TAtlasGuard.Disabled(TAtlasFeature.StickyScroll);
  FMaxLines := TAtlasStickyScroll.ClampLines(Settings.StickyScrollMaxLines);
  StickyShown := FOn;
  // Paarfarben an oder aus: beim nächsten Takt neu analysieren.
  FStamp := 0;
  FRowsTop := -1;
  if not FOn then
  begin
    Clear;
  end;
  if Was or FOn then
  begin
    InvalidateEditor;
  end;
end;

procedure TStickyState.Clear;
begin
  FFileName := '';
  FStamp := 0;
  FNodes := nil;
  FLines := nil;
  FPairs := nil;
  FBranches := nil;
  FRows := nil;
  FRowsTop := -1;
  FPaintedRows := 0;
end;

procedure TStickyState.QueueInvalidate;
begin
  if InvalidatePending then
  begin
    Exit;
  end;
  InvalidatePending := True;
  // Nicht während des Malens: nach dem laufenden Ereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.StickyScroll,
    procedure
    begin
      InvalidatePending := False;
      InvalidateEditor;
    end);
end;

procedure TStickyState.Tick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

procedure TStickyState.Update;
var
  View: IOTAEditView;
  Snapshot: TAtlasOutlineSnapshot;
  Shown: Boolean;
begin
  // Schnellschalter und Schutzschalter wirken ohne eigenes Ereignis.
  if (TAtlasIdeStickyScroll.Enabled and not TAtlasGuard.Disabled(TAtlasFeature.StickyScroll)) <> FOn then
  begin
    ApplySettings;
  end;
  if not FOn then
  begin
    Exit;
  end;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
  begin
    Exit;
  end;
  Snapshot := TAtlasIdeOutlineCache.Refresh(View);
  case Snapshot.Status of
    TAtlasOutlineStatus.Waiting:
      Exit;
    TAtlasOutlineStatus.NoFile, TAtlasOutlineStatus.NoServer:
      begin
        Shown := FPaintedRows > 0;
        Clear;
        if Shown then
        begin
          InvalidateEditor;
        end;
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  if not SameText(Snapshot.FileName, FFileName) or (Snapshot.Stamp <> FStamp) then
  begin
    FFileName := Snapshot.FileName;
    FStamp := Snapshot.Stamp;
    FNodes := Snapshot.Nodes;
    FLines := TTextLines.SplitLines(Snapshot.Text);
    AnalyzePairs(Snapshot.Text);
    ReadSyntax;
    FRowsTop := -1;
    InvalidateEditor;
  end
  else if (View.TopRow - 1 <> FPaintedTop) and ((FPaintedRows > 0) or (Length(FNodes) > 0)) then
  begin
    // Bildlauf ohne Malen der oberen Zeilen (z. B. per Rollrad): ganz neu zeichnen.
    InvalidateEditor;
  end;
end;

/// <summary>Wort ab AIndex (0-basiert) in ALine, klein.</summary>
function WordAt(const ALine: string; AIndex: Integer): string;
var
  Stop: Integer;
begin
  Stop := AIndex + 1;
  while (Stop <= Length(ALine)) and CharInSet(ALine[Stop], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(Stop);
  end;
  Result := LowerCase(Copy(ALine, AIndex + 1, Stop - AIndex - 1));
end;

/// <summary>Hintergrund des Kopfs: der des Editors, eine Spur zur Schrift hin (leichte Abgrenzung).</summary>
function HeaderBack(const AColors: TAtlasColors; ABack: TAtlasColor): TAtlasColor;
begin
  Result := TAtlasColorMath.Mix(AColors.Text, ABack, 0.04);
end;

/// <summary>Arten mit eigener Kopfzeile nach den Einstellungen.</summary>
function StickyKinds(const ASettings: TAtlasPluginSettings): TAtlasStickyKinds;
begin
  Result := [];
  if ASettings.StickyScrollTypes then
  begin
    Include(Result, TAtlasStickyKind.Types);
  end;
  if ASettings.StickyScrollRoutines then
  begin
    Include(Result, TAtlasStickyKind.Routines);
  end;
  if ASettings.StickyScrollBlocks then
  begin
    Include(Result, TAtlasStickyKind.Branches);
  end;
  if ASettings.StickyScrollLoops then
  begin
    Include(Result, TAtlasStickyKind.Loops);
  end;
  if ASettings.StickyScrollTry then
  begin
    Include(Result, TAtlasStickyKind.TryBlocks);
  end;
  if ASettings.StickyScrollCase then
  begin
    Include(Result, TAtlasStickyKind.CaseBlocks);
  end;
  if ASettings.StickyScrollWith then
  begin
    Include(Result, TAtlasStickyKind.WithBlocks);
  end;
end;

/// <summary>Paar-Token je Zeile (ALineCount Zeilen).</summary>
function PairsPerLine(const ATokens: TArray<TAtlasPairToken>; ALineCount: Integer): TArray<TArray<TAtlasPairToken>>;
var
  Token: TAtlasPairToken;
begin
  SetLength(Result, ALineCount);
  for Token in ATokens do
  begin
    if (Token.Line >= 0) and (Token.Line <= High(Result)) then
    begin
      Result[Token.Line] := Result[Token.Line] + [Token];
    end;
  end;
end;

/// <summary>Blöcke, deren erstes Besitzerwort zu einer der Arten AKinds gehört (#1230).</summary>
function BranchesOf(const ABlocks: TArray<TAtlasPairBlock>; const ALines: TArray<string>;
  AKinds: TAtlasStickyKinds): TArray<TAtlasStickyBlock>;
var
  Block: TAtlasPairBlock;
  Kind: TAtlasStickyKind;
begin
  Result := nil;
  for Block in ABlocks do
  begin
    if (Block.OwnerLine < 0) or (Block.OwnerLine > High(ALines)) then
    begin
      Continue;
    end;
    if TAtlasStickyScroll.OwnerKind(WordAt(ALines[Block.OwnerLine], Block.OwnerCharacter), Kind) and
      (Kind in AKinds) then
    begin
      Result := Result + [TAtlasStickyBlock.Create(Block.OwnerLine, Block.OwnerCharacter, Block.CloseLine)];
    end;
  end;
end;

procedure TStickyData.AnalyzePairs(const AText: string);
var
  Settings: TAtlasPluginSettings;
  Tokens: TArray<TAtlasPairToken>;
  Blocks: TArray<TAtlasPairBlock>;
  Kinds: TAtlasStickyKinds;
begin
  FPairs := nil;
  FBranches := nil;
  FBlocks := nil;
  FGuidesKey := '';
  Settings := TAtlasIdeSettings.Current;
  Kinds := StickyKinds(Settings) - TAtlasStickyScroll.OutlineKinds;
  if not Settings.PairColors and (Kinds = []) then
  begin
    Exit;
  end;
  Tokens := TAtlasPairs.Analyze(AText, Blocks);
  FBlocks := Blocks;
  if Settings.PairColors then
  begin
    FPairs := PairsPerLine(Tokens, Length(FLines));
  end;
  // Routinen und Klassen liefert die Gliederung.
  FBranches := BranchesOf(Blocks, FLines, Kinds);
end;

procedure TStickyData.EnsureGuides(ATabWidth: Integer; AOwners: Boolean);
var
  Key: string;
begin
  Key := IntToStr(ATabWidth) + BoolToStr(AOwners, True);
  if Key <> FGuidesKey then
  begin
    FGuides := TAtlasGuides.FromBlocks(FLines, FBlocks, ATabWidth, AOwners);
    FGuidesKey := Key;
  end;
end;

/// <summary>Anweisungsblöcke ab AMinLines Zeilen (vom Kopf bis zum end bzw. until).</summary>
function LongBranches(const ABranches: TArray<TAtlasStickyBlock>; AMinLines: Integer): TArray<TAtlasStickyBlock>;
var
  Block: TAtlasStickyBlock;
begin
  Result := nil;
  for Block in ABranches do
  begin
    if Block.EndLine - Block.Line + 1 >= AMinLines then
    begin
      Result := Result + [Block];
    end;
  end;
end;

procedure TStickyPainter.UpdateRows(const AView: IOTAEditView; ATop: Integer);
var
  Settings: TAtlasPluginSettings;
  Branches: TArray<TAtlasStickyBlock>;
begin
  if (ATop = FRowsTop) and (FMaxLines = FRowsMax) then
  begin
    Exit;
  end;
  Settings := TAtlasIdeSettings.Current;
  Branches := LongBranches(FBranches, Settings.StickyScrollBlockMinLines);
  FRows := TAtlasStickyScroll.Rows(TAtlasStickySource.Create(FNodes, FLines, Branches,
    StickyKinds(Settings) * TAtlasStickyScroll.OutlineKinds), ATop, FMaxLines,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  FRowsTop := ATop;
  FRowsMax := FMaxLines;
end;

procedure TStickyPainter.SampleBack(const ARect: TRect; const AContext: INTACodeEditorPaintContext);
var
  Sample: COLORREF;
begin
  Sample := GetPixel(AContext.Canvas.Handle, ARect.Right - 2, ARect.Top + 1);
  if not FSchemeBackKnown and (Sample <> CLR_INVALID) then
  begin
    FBack := TAtlasColor(Sample);
    FBackKnown := True;
  end;
end;

function TStickyPainter.Painted(ATop, AHeight: Integer): Boolean;
begin
  Result := (FPaintedTop >= 0) and (ATop <> FPaintedTop) and ((FPaintedRows > 0) or (Length(FRows) > 0));
  FPaintedTop := ATop;
  FPaintedRows := Length(FRows);
  FRowHeight := AHeight;
end;

function TStickyPainter.RowAt(X, Y: Integer; out ARow: Integer): Boolean;
begin
  ARow := -1;
  Result := (FPaintedRows > 0) and (FRowHeight > 0) and (Y >= 0) and (X >= FCodeLeft);
  if Result then
  begin
    ARow := Y div FRowHeight;
    Result := (ARow < FPaintedRows) and (ARow <= High(FRows));
  end;
end;

procedure TStickyState.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Top, Row, Height: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FOn or (FFileName = '') then
  begin
    Exit;
  end;
  try
    View := Context.EditView;
    Height := Rect.Bottom - Rect.Top;
    if (View = nil) or (View.Buffer = nil) or not SameText(Context.FileName, FFileName) or (Height <= 0) then
    begin
      Exit;
    end;
    Top := View.TopRow - 1;
    UpdateRows(View, Top);
    if Painted(Top, Height) then
    begin
      QueueInvalidate;
    end;
    Row := (Rect.Top + Height div 2) div Height;
    if Row >= Length(FRows) then
    begin
      // Nicht übermalte Zeile: deren Hintergrund ist der des Editors.
      SampleBack(Rect, Context);
    end
    else
    begin
      // Mit jedem neu gezeichneten Kopf neu sammeln (DrawGuides).
      if Row = 0 then
      begin
        FTaperColumns := nil;
      end;
      PaintRow(Rect, Row, Context);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

function HasColumn(const AColumns: TArray<Integer>; AColumn: Integer): Boolean;
var
  Column: Integer;
begin
  Result := False;
  for Column in AColumns do
  begin
    if Column = AColumn then
    begin
      Exit(True);
    end;
  end;
end;

const
  // Wie die Blocklinien des Editors (Atlas.IDE.Editor.Pairs).
  GuideMargin = 4;

/// <summary>Paarfarben zu AColors (hell oder dunkel) aus den Einstellungen.</summary>
function PairPalette(const AColors: TAtlasColors; const ASettings: TAtlasPluginSettings): TAtlasColors;
begin
  if AColors.IsDark then
  begin
    Result := AColors.WithPairs(ASettings.PairColorsDark);
  end
  else
  begin
    Result := AColors.WithPairs(ASettings.PairColorsLight);
  end;
end;

/// <summary>Ohne Zeilenzustand, Ansicht oder Puffer gibt es keine Blocklinien.</summary>
function NoEditor(const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := (AContext.LineState = nil) or (AContext.EditView = nil) or (AContext.EditView.Buffer = nil);
end;

function GuidePaintOf(const AContext: INTACodeEditorPaintContext; const ARect: TRect; ABack: TAtlasColor;
  const ASettings: TAtlasPluginSettings): TGuidePaint;
begin
  Result.Context := AContext;
  Result.DC := AContext.Canvas.Handle;
  Result.Rect := ARect;
  Result.Code := AContext.LineState.CodeRect;
  Result.Width := TAtlasGuides.PenWidth(ASettings.PairGuideWidth, AContext.CellSize.cy,
    TAtlasIdeStyle.BaseTextHeight);
  Result.Opacity := ASettings.PairGuideOpacity;
  Result.Back := ABack;
  Result.Colors := TAtlasColors.ForBackground(ABack);
  // Die Spitze eingeblendeter Linien beginnt in der Farbe des Kopfs.
  Result.HeadBack := HeaderBack(Result.Colors, ABack);
  Result.Colors := PairPalette(Result.Colors, ASettings);
end;

/// <summary>Spalte der Linie in Pixeln vor der Zelle ACell; nicht links aus dem Codebereich.</summary>
function GuideX(const APaint: TGuidePaint; const ACell: TRect): Integer;
begin
  Result := ACell.Left - Max(2, ACell.Width div 3) - (APaint.Width - 1) div 2;
  if (APaint.Code.Right > APaint.Code.Left) and (Result < APaint.Code.Left - GuideMargin + APaint.Width div 2) then
  begin
    Result := APaint.Code.Left - GuideMargin + APaint.Width div 2;
  end;
end;

function GuideColor(const APaint: TGuidePaint; ADepth: Integer): TAtlasColor;
begin
  Result := APaint.Colors.Pairs[ADepth mod Length(APaint.Colors.Pairs)];
  if APaint.Opacity < 100 then
  begin
    Result := TAtlasColorMath.Mix(Result, APaint.Back, APaint.Opacity / 100);
  end;
end;

/// <summary>Spitz nach oben: je Pixelzeile ein Streifen, der von 1 Pixel auf die Stiftbreite wächst und von der
/// Kopffarbe zur Linienfarbe übergeht; bei 1–2 Pixel Stiftbreite sieht man die Spitze sonst nicht.</summary>
procedure DrawFade(const APaint: TGuidePaint; AX: Integer; AColor: TAtlasColor);
var
  FadeHeight, Offset, Thick: Integer;
  Step: TRect;
  Brush: HBRUSH;
begin
  FadeHeight := APaint.Rect.Height - 2;
  for Offset := 0 to FadeHeight - 1 do
  begin
    Thick := Max(1, MulDiv(APaint.Width, Offset + 1, FadeHeight));
    Step := TRect.Create(AX - (Thick - 1) div 2, APaint.Rect.Bottom - FadeHeight + Offset,
      AX - (Thick - 1) div 2 + Thick, APaint.Rect.Bottom - FadeHeight + Offset + 1);
    Brush := CreateSolidBrush(ColorToRGB(TColor(TAtlasColorMath.Mix(AColor, APaint.HeadBack,
      TAtlasStickyScroll.FadeWeight(Offset, FadeHeight)))));
    try
      FillRect(APaint.DC, Step, Brush);
    finally
      DeleteObject(Brush);
    end;
  end;
end;

/// <summary>Senkrechter Strich bei AX durch die Zeile; mit AHook > 0 beginnt er oben mit einem Haken dieser
/// Länge (Kopfzeile des Elements).</summary>
procedure DrawStroke(const APaint: TGuidePaint; AX, AHook: Integer; AColor: TAtlasColor);
var
  Pen, Old: HGDIOBJ;
  Top: Integer;
begin
  Pen := CreatePen(PS_SOLID, APaint.Width, ColorToRGB(TColor(AColor)));
  Old := SelectObject(APaint.DC, Pen);
  try
    Top := APaint.Rect.Top;
    if AHook > 0 then
    begin
      Top := Top + 2;
    end;
    MoveToEx(APaint.DC, AX, Top, nil);
    LineTo(APaint.DC, AX, APaint.Rect.Bottom);
    if AHook > 0 then
    begin
      MoveToEx(APaint.DC, AX, Top, nil);
      LineTo(APaint.DC, AX + AHook, Top);
    end;
  finally
    SelectObject(APaint.DC, Old);
    DeleteObject(Pen);
  end;
end;

procedure TStickyPainter.DrawGuide(const APaint: TGuidePaint; const AGuide: TAtlasGuide; ARowIndex: Integer);
var
  Start: TAtlasStickyGuideStart;
  Cell: TRect;
  X: Integer;
  LineColor: TAtlasColor;
begin
  // Das Element der Linie: die Kopfzeile, deren Zeile die erste der Linie ist (Anweisung bzw. Öffner). Ohne
  // Kopfzeile blendet die Linie in der letzten Kopfzeile ein, sonst käme sie ohne Anfang darunter hervor.
  Start := TAtlasStickyScroll.GuideStart(FRows, AGuide.FirstLine);
  if (Start.Row < 0) or (ARowIndex < Start.Row) then
  begin
    Exit;
  end;
  Cell := APaint.Context.EditorState.GetCharacterPosPx(AGuide.Column, APaint.Context.EditorLineNum);
  X := GuideX(APaint, Cell);
  LineColor := GuideColor(APaint, AGuide.Depth);
  if not Start.FadeIn then
  begin
    if ARowIndex = Start.Row then
    begin
      DrawStroke(APaint, X, Max(3, Cell.Width div 2), LineColor);
    end
    else
    begin
      DrawStroke(APaint, X, 0, LineColor);
    end;
  end
  // Oben spitz zulaufend (Marco 28.10.2026), ab der Oberkante der letzten Kopfzeile wie die Linie eines Elements
  // mit eigener Kopfzeile. Läge die Spitze im Text dieser Zeile (z. B. procedure), zeichnen sie die Blocklinien
  // des Editors in der Zeile darunter (TaperBelow). In Pixeln, denn der Strich wird an den Rand geschoben (GuideX).
  else if X + APaint.Width > APaint.Context.EditorState.GetCharacterPosPx(FRows[Start.Row].Indent,
    APaint.Context.EditorLineNum).Left then
  begin
    if not HasColumn(FTaperColumns, AGuide.Column) then
    begin
      FTaperColumns := FTaperColumns + [AGuide.Column];
    end;
  end
  else
  begin
    DrawFade(APaint, X, LineColor);
  end;
end;

procedure TStickyPainter.DrawGuides(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext;
  ABack: TAtlasColor);
var
  Settings: TAtlasPluginSettings;
  Paint: TGuidePaint;
  Guide: TAtlasGuide;
  Below, Saved: Integer;
begin
  Settings := TAtlasIdeSettings.Current;
  if not (Settings.PairColors and Settings.PairGuides) or (Length(FBlocks) = 0) or NoEditor(Context) or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairGuides, FFileName) then
  begin
    Exit;
  end;
  EnsureGuides(TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer),
    Settings.PairOwners and not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, FFileName));
  Paint := GuidePaintOf(Context, ARect, ABack, Settings);
  // Erste Zeile unter dem Kopf: Nur Linien, die dort weiterlaufen, reichen in den Kopf.
  Below := FRowsTop + Length(FRows);
  Saved := SaveDC(Paint.DC);
  try
    if Paint.Code.Right > Paint.Code.Left then
    begin
      IntersectClipRect(Paint.DC, Paint.Code.Left - GuideMargin, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for Guide in FGuides do
    begin
      if (Guide.FirstLine < Below) and (Guide.LastLine >= Below) then
      begin
        DrawGuide(Paint, Guide, ARowIndex);
      end;
    end;
  finally
    RestoreDC(Paint.DC, Saved);
  end;
end;

function RegistryTrue(ARegistry: TRegistry; const AName: string): Boolean;
begin
  Result := ARegistry.ValueExists(AName) and SameText(ARegistry.ReadString(AName), 'True');
end;

/// <summary>Darstellung aus dem Schlüssel AKey (Editor\Highlight\…); unlesbar: ohne Hervorhebung.</summary>
function ReadStyle(ARegistry: TRegistry; const AKey: string): TSyntaxStyle;
begin
  Result := Default(TSyntaxStyle);
  try
    if not ARegistry.OpenKeyReadOnly(AKey) then
    begin
      Exit;
    end;
    if RegistryTrue(ARegistry, 'Bold') then
    begin
      Include(Result.Style, fsBold);
    end;
    if RegistryTrue(ARegistry, 'Italic') then
    begin
      Include(Result.Style, fsItalic);
    end;
    // „$00BCE0FF“ oder „clMaroon“; mit Default Foreground die Vorgabefarbe des Editors.
    if ARegistry.ValueExists('Foreground Color New') and not RegistryTrue(ARegistry, 'Default Foreground') then
    begin
      Result.Color := StringToColor(ARegistry.ReadString('Foreground Color New'));
      Result.HasColor := True;
    end;
    ARegistry.CloseKey;
  except
    // Unlesbarer Eintrag: diese Art ohne Hervorhebung.
    on Exception do
      Result := Default(TSyntaxStyle);
  end;
end;

/// <summary>Hintergrund des Editors aus AKey (Plain text, #1245); False mit Default Background (dann bleibt das
/// Abtasten) oder unlesbar.</summary>
function ReadSchemeBack(ARegistry: TRegistry; const AKey: string; out ABack: TAtlasColor): Boolean;
begin
  Result := False;
  ABack := Default(TAtlasColor);
  try
    if not ARegistry.OpenKeyReadOnly(AKey) then
    begin
      Exit;
    end;
    if ARegistry.ValueExists('Background Color New') and not RegistryTrue(ARegistry, 'Default Background') then
    begin
      ABack := TAtlasColor(ColorToRGB(StringToColor(ARegistry.ReadString('Background Color New'))));
      Result := True;
    end;
    ARegistry.CloseKey;
  except
    on Exception do
      Result := False;
  end;
end;

procedure TStickyData.ReadSyntax;
const
  Elements: array[TAtlasStickySyntax] of string = ('Whitespace', 'Reserved word', 'Identifier', 'Number', 'String',
    'Character', 'Comment', 'Symbol', 'Preprocessor');
var
  Services: IOTAServices;
  Registry: TRegistry;
  Kind: TAtlasStickySyntax;
  Base: string;
  Back: TAtlasColor;
begin
  for Kind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
  begin
    FSyntax[Kind] := Default(TSyntaxStyle);
  end;
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Exit;
  end;
  Base := Services.GetBaseRegistryKey + '\Editor\Highlight\';
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    for Kind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
    begin
      FSyntax[Kind] := ReadStyle(Registry, Base + Elements[Kind]);
    end;
    FSchemeBackKnown := ReadSchemeBack(Registry, Base + 'Plain text', Back);
    if FSchemeBackKnown then
    begin
      FSchemeBack := Back;
    end;
  finally
    Registry.Free;
  end;
end;

/// <summary>Farbschema des Editors (Farbe, fett, kursiv) je Zeichen von AText.</summary>
procedure ApplySyntax(const AText: string; const ASyntax: TSyntaxStyles; var AColors: TArray<TColor>;
  var AStyles: TArray<TFontStyles>);
var
  Token: TAtlasStickyToken;
  Style: TSyntaxStyle;
  Index: Integer;
begin
  for Token in TAtlasStickyScroll.Syntax(AText) do
  begin
    Style := ASyntax[Token.Kind];
    for Index := Token.Start - 1 to Min(High(AColors), Token.Start + Token.Length - 2) do
    begin
      if Style.HasColor then
      begin
        AColors[Index] := Style.Color;
      end;
      AStyles[Index] := Style.Style;
    end;
  end;
end;

function SpanColor(const ASpan: TAtlasPairSpan; const APairs: TAtlasColors): TColor;
begin
  if ASpan.Unpaired then
  begin
    Result := TColor(APairs.Error);
  end
  else
  begin
    Result := TColor(APairs.Pairs[ASpan.Depth mod Length(APairs.Pairs)]);
  end;
end;

/// <summary>Paarfarben ersetzen die Farbe des Farbschemas; fett und kursiv bleiben.</summary>
procedure ApplySpans(const ASpans: TArray<TAtlasPairSpan>; const APairs: TAtlasColors; var AColors: TArray<TColor>);
var
  Span: TAtlasPairSpan;
  Index: Integer;
begin
  for Span in ASpans do
  begin
    for Index := Span.Start - 1 to Min(High(AColors), Span.Start + Span.Length - 2) do
    begin
      AColors[Index] := SpanColor(Span, APairs);
    end;
  end;
end;

/// <summary>AText ab AX in Läufen gleicher Farbe und Schrift am Stück.</summary>
procedure DrawRuns(ACanvas: TCanvas; AX, ATop: Integer; const AText: string; const AColors: TArray<TColor>;
  const AStyles: TArray<TFontStyles>);
var
  Index, Stop: Integer;
  Part: string;
begin
  Index := 0;
  while Index <= High(AColors) do
  begin
    Stop := Index;
    while (Stop < High(AColors)) and (AColors[Stop + 1] = AColors[Index]) and (AStyles[Stop + 1] = AStyles[Index]) do
    begin
      Inc(Stop);
    end;
    Part := Copy(AText, Index + 1, Stop - Index + 1);
    ACanvas.Font.Color := AColors[Index];
    ACanvas.Font.Style := AStyles[Index];
    ACanvas.TextOut(AX, ATop, Part);
    Inc(AX, ACanvas.TextWidth(Part));
    Index := Stop + 1;
  end;
end;

function TStickyPainter.RowSpans(const ARow: TAtlasStickyRow): TArray<TAtlasPairSpan>;
var
  Settings: TAtlasPluginSettings;
begin
  Result := nil;
  Settings := TAtlasIdeSettings.Current;
  if (ARow.Line < 0) or (ARow.Line > High(FPairs)) or (ARow.Line > High(FLines)) or not Settings.PairColors or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairColors, FFileName) then
  begin
    Exit;
  end;
  Result := TAtlasPairs.Spans(ARow.Text, FLines[ARow.Line], FPairs[ARow.Line],
    Settings.PairOwners and not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, FFileName));
end;

procedure TStickyPainter.DrawHeader(ACanvas: TCanvas; ALeft, ATop: Integer; const ARow: TAtlasStickyRow;
  const AColors: TAtlasColors; ATextColor: TColor);
var
  Spans: TArray<TAtlasPairSpan>;
  CharColors: TArray<TColor>;
  CharStyles: TArray<TFontStyles>;
  Index: Integer;
begin
  if ARow.Summary or (ARow.Text = '') then
  begin
    // Zusammenfassung „A › B“: gedämpft wie bisher, ohne Hervorhebung.
    ACanvas.Font.Color := ATextColor;
    ACanvas.TextOut(ALeft, ATop, ARow.Text);
    Exit;
  end;
  // Hervorhebung wie im Editor (Farbschema, fett, kursiv), je Zeichen.
  SetLength(CharColors, Length(ARow.Text));
  SetLength(CharStyles, Length(ARow.Text));
  for Index := 0 to High(CharColors) do
  begin
    CharColors[Index] := ATextColor;
    CharStyles[Index] := [];
  end;
  ApplySyntax(ARow.Text, FSyntax, CharColors, CharStyles);
  // Paarfarben wie im Editor (#1229).
  Spans := RowSpans(ARow);
  if Length(Spans) > 0 then
  begin
    ApplySpans(Spans, PairPalette(AColors, TAtlasIdeSettings.Current), CharColors);
  end;
  DrawRuns(ACanvas, ALeft, ATop, ARow.Text, CharColors, CharStyles);
end;

class function TSavedTools.Save(ACanvas: TCanvas): TSavedTools;
begin
  Result.Font := TFont.Create;
  Result.Brush := TBrush.Create;
  Result.Pen := TPen.Create;
  Result.Font.Assign(ACanvas.Font);
  Result.Brush.Assign(ACanvas.Brush);
  Result.Pen.Assign(ACanvas.Pen);
end;

procedure TSavedTools.Restore(ACanvas: TCanvas);
begin
  ACanvas.Font.Assign(Font);
  ACanvas.Brush.Assign(Brush);
  ACanvas.Pen.Assign(Pen);
  Pen.Free;
  Brush.Free;
  Font.Free;
end;

/// <summary>Linker Rand des Codebereichs, sonst der der Zeile.</summary>
function CodeLeftOf(const AContext: INTACodeEditorPaintContext; const ARect: TRect): Integer;
var
  Code: TRect;
begin
  Result := ARect.Left;
  if AContext.LineState = nil then
  begin
    Exit;
  end;
  Code := AContext.LineState.CodeRect;
  if Code.Right > Code.Left then
  begin
    Result := Code.Left;
  end;
end;

function TStickyPainter.RowBack(ACanvas: TCanvas; const ARect: TRect): TAtlasColor;
var
  Sample: COLORREF;
begin
  if FSchemeBackKnown then
  begin
    Result := FSchemeBack;
  end
  else if FBackKnown then
  begin
    Result := FBack;
  end
  else
  begin
    Sample := GetPixel(ACanvas.Handle, ARect.Right - 2, ARect.Top + 1);
    if Sample = CLR_INVALID then
    begin
      Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
    end
    else
    begin
      Result := TAtlasColor(Sample);
    end;
  end;
end;

/// <summary>Hintergrund der Kopfzeile in AArea, Schrift für Text oder (ASummary) Zusammenfassung.</summary>
procedure FillRow(ACanvas: TCanvas; const AArea: TRect; const AColors: TAtlasColors; ABack: TAtlasColor;
  ASummary: Boolean);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(HeaderBack(AColors, ABack));
  ACanvas.FillRect(AArea);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Style := [];
  if ASummary then
  begin
    ACanvas.Font.Color := TColor(AColors.Muted);
  end
  else
  begin
    ACanvas.Font.Color := TColor(AColors.Text);
  end;
end;

/// <summary>Trennlinie unter der letzten Kopfzeile.</summary>
procedure DrawSeparator(ACanvas: TCanvas; const AArea: TRect; const AColors: TAtlasColors);
begin
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := TColor(AColors.Line);
  ACanvas.MoveTo(AArea.Left, AArea.Bottom - 1);
  ACanvas.LineTo(AArea.Right, AArea.Bottom - 1);
end;

procedure TStickyPainter.PaintRow(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext);
var
  Row: TAtlasStickyRow;
  Canvas: TCanvas;
  Area, Cell: TRect;
  Colors: TAtlasColors;
  Back: TAtlasColor;
  Saved, TextTop: Integer;
  Tools: TSavedTools;
begin
  Row := FRows[ARowIndex];
  Canvas := Context.Canvas;
  FCodeLeft := CodeLeftOf(Context, ARect);
  Area := TRect.Create(FCodeLeft, ARect.Top, ARect.Right, ARect.Bottom);
  Back := RowBack(Canvas, ARect);
  Colors := TAtlasColors.ForBackground(Back);
  Tools := TSavedTools.Save(Canvas);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle, Area.Left, Area.Top, Area.Right, Area.Bottom);
    FillRow(Canvas, Area, Colors, Back, Row.Summary);
    Cell := Context.EditorState.GetCharacterPosPx(Row.Indent + 1, Context.EditorLineNum);
    TextTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - Canvas.TextHeight('Xg')) div 2);
    DrawHeader(Canvas, Max(FCodeLeft, Cell.Left), TextTop, Row, Colors, Canvas.Font.Color);
    if ARowIndex = High(FRows) then
    begin
      DrawSeparator(Canvas, Area, Colors);
    end;
  finally
    RestoreDC(Canvas.Handle, Saved);
    DrawGuides(ARect, ARowIndex, Context, Back);
    Tools.Restore(Canvas);
  end;
end;

procedure TStickyState.EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
begin
  try
    // Senkrecht verschiebt sich der Kopf; waagerecht seine Einrückung. Beides sofort ganz neu, nicht erst im Takt.
    if not FOn or ((FPaintedRows = 0) and (Length(FNodes) = 0)) then
    begin
      Exit;
    end;
    if Editor <> nil then
    begin
      Editor.Invalidate;
    end
    else
    begin
      InvalidateEditor;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

procedure TStickyState.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  View: IOTAEditView;
  Row: Integer;
  Target: TAtlasStickyRow;
  FileName: string;
begin
  try
    if not FOn or (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not RowAt(X, Y, Row) then
    begin
      Exit;
    end;
    // Nur, wenn die Köpfe noch so stehen: gleiche Datei, nicht gescrollt.
    View := TAtlasEditorBuffer.ActiveView;
    if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFileName) or
      (View.TopRow - 1 <> FPaintedTop) then
    begin
      Exit;
    end;
    Target := FRows[Row];
    FileName := FFileName;
    // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor auf die angeklickte Stelle.
    TAtlasMainThread.ForceQueue(TAtlasFeature.StickyScroll,
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.StickyScroll,
          procedure
          begin
            TAtlasIdeNavigation.GoToLocation(FileName, Target.Line, Target.Character);
          end);
      end);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

{ TAtlasIdeStickyScroll }

class procedure TAtlasIdeStickyScroll.Install;
begin
  if FState = nil then
  begin
    FState := TStickyState.Create;
  end;
end;

class procedure TAtlasIdeStickyScroll.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeStickyScroll.ApplySettings;
begin
  if FState <> nil then
  begin
    TStickyState(FState).ApplySettings;
  end;
end;

class function TAtlasIdeStickyScroll.CoveredRows(const AFileName: string): Integer;
var
  State: TStickyState;
begin
  Result := 0;
  if FState = nil then
  begin
    Exit;
  end;
  State := TStickyState(FState);
  if State.FOn and SameText(State.FFileName, AFileName) then
  begin
    Result := State.FPaintedRows;
  end;
end;

class function TAtlasIdeStickyScroll.TaperBelow(const AFileName: string; AColumn: Integer): Boolean;
var
  State: TStickyState;
begin
  Result := False;
  if FState = nil then
  begin
    Exit;
  end;
  State := TStickyState(FState);
  Result := State.FOn and (State.FPaintedRows > 0) and SameText(State.FFileName, AFileName) and
    HasColumn(State.FTaperColumns, AColumn);
end;

class function TAtlasIdeStickyScroll.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.StickyScroll;
end;

end.
