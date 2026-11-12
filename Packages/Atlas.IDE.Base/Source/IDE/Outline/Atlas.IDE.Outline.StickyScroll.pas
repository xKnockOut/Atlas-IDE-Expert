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
// - Hover: HeaderAt nennt dem Tooltip die Kopfzeile unter der Maus. Er zeigt
//   dann den Bezeichner im Kopf (TAtlasStickyScroll.SourceIndex) und nie den
//   der verdeckten Zeile darunter.
// - Die oberste Zeile ist View.TopRow; zugeklappte Bereiche darunter zählt
//   der Kopf wie offene.
// - Thema (Hell/Dunkel): Die IDE schreibt beim Wechsel das Farbschema des
//   Editors neu. ThemeChanged liest es beim nächsten Takt neu, vergisst den
//   abgetasteten Hintergrund und zeichnet den Kopf neu; sonst bliebe er in den
//   Farben des alten Themas, bis sich der Stand der Gliederung ändert.
// editor.stickyScroll aus: nichts wird gezeichnet, kein Klick abgefangen.
// Nur im Hauptthread.

interface

uses
  Atlas.Core.Outline.StickyScroll;

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
    /// <summary>IDE-Thema gewechselt: Farbschema und Hintergrund neu bestimmen, Editor neu zeichnen.</summary>
    class procedure ThemeChanged; static;
    class function Enabled: Boolean; static;
    /// <summary>Zeilen, die der Kopf oben im Editor zu AFileName verdeckt; 0 ohne Kopf. Die Blocklinien des
    /// Editors bleiben dort weg, der Kopf zeichnet sie selbst.</summary>
    class function CoveredRows(const AFileName: string): Integer; static;
    /// <summary>True, wenn die Blocklinie in Spalte AColumn in der ersten Zeile unter dem Kopf spitz beginnen soll:
    /// Ihr Element ist hinter dem Kopf verschwunden, und ihre Spitze läge im Text der letzten Kopfzeile.</summary>
    class function TaperBelow(const AFileName: string; AColumn: Integer): Boolean; static;
    /// <summary>True, wenn am Mauspunkt AX, AY (Editorkoordinaten) der Kopf steht, wie er zu AFileName mit oberster
    /// Zeile ATopRow (1-basiert, IOTAEditView.TopRow) gezeichnet ist; ARow ist dann die Kopfzeile dort.</summary>
    class function HeaderAt(const AFileName: string; ATopRow, AX, AY: Integer; out ARow: TAtlasStickyRow): Boolean;
      static;
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
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.Guides,
  Atlas.Core.Editor.RoutineNesting,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Foundation.EditorRefresh;

const
  cTickMs = 100;

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
    /// <summary>Färbung lokaler Routinen wie im Editor (#1788).</summary>
    Nesting: TAtlasRoutineNesting;
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
    function RowAt(AX, AY: Integer; out ARow: Integer): Boolean;
    /// <summary>Paarfarben-Stücke der Kopfzeile ARow; leer ohne PairColors oder in dieser Datei ausgeblendet.</summary>
    function RowSpans(const ARow: TAtlasStickyRow): TArray<TAtlasPairSpan>;
    /// <summary>Linie AGuide in Kopfzeile ARowIndex, wenn ihr Element hier oder darüber eine Kopfzeile hat.</summary>
    procedure DrawGuide(const APaint: TGuidePaint; const AGuide: TAtlasGuide; ARowIndex: Integer);
    procedure PaintRow(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext);
    /// <summary>Blocklinien im Kopf: Jede beginnt mit Haken in der Kopfzeile ihres Elements; ohne Kopfzeile blendet
    /// sie in der letzten Kopfzeile ein.</summary>
    procedure DrawGuides(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext;
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
    procedure ThemeChanged;
  end;

procedure InvalidateEditor;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
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
  mServices: INTACodeEditorServices;
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
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  ApplySettings;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TStickyState.Destroy;
var
  mServices: INTACodeEditorServices;
  mShown: Boolean;
begin
  FTimer.Free;
  mShown := FPaintedRows > 0;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEvents.OnEditorScrolled := nil;
  FEventsRef := nil;
  StickyShown := False;
  if mShown then
  begin
    InvalidateEditor;
  end;
  inherited Destroy;
end;

procedure TStickyState.ApplySettings;
var
  mSettings: TAtlasPluginSettings;
  mWas: Boolean;
begin
  mSettings := TAtlasIdeSettings.Current;
  mWas := FOn;
  FOn := mSettings.Enabled and mSettings.StickyScroll and not TAtlasGuard.Disabled(TAtlasFeature.StickyScroll);
  FMaxLines := TAtlasStickyScroll.ClampLines(mSettings.StickyScrollMaxLines);
  StickyShown := FOn;
  // Paarfarben an oder aus: beim nächsten Takt neu analysieren.
  FStamp := 0;
  FRowsTop := -1;
  if not FOn then
  begin
    Clear;
  end;
  if mWas or FOn then
  begin
    InvalidateEditor;
  end;
end;

procedure TStickyState.ThemeChanged;
begin
  // Farbschema (Hintergrund, Syntaxfarben) beim nächsten Takt neu lesen: Die IDE schreibt es mit dem Wechsel.
  FStamp := 0;
  FRowsTop := -1;
  // Der abgetastete Hintergrund ist der des alten Themas; bis zum nächsten Abtasten die eigene Zeile nehmen.
  FBackKnown := False;
  FSchemeBackKnown := False;
  if FOn then
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
  mView: IOTAEditView;
  mSnapshot: TAtlasOutlineSnapshot;
  mShown: Boolean;
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
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(mView);
  case mSnapshot.Status of
    TAtlasOutlineStatus.Waiting:
      Exit;
    TAtlasOutlineStatus.NoFile, TAtlasOutlineStatus.NoServer:
      begin
        mShown := FPaintedRows > 0;
        Clear;
        if mShown then
        begin
          InvalidateEditor;
        end;
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  if not SameText(mSnapshot.FileName, FFileName) or (mSnapshot.Stamp <> FStamp) then
  begin
    FFileName := mSnapshot.FileName;
    FStamp := mSnapshot.Stamp;
    FNodes := mSnapshot.Nodes;
    FLines := TTextLines.SplitLines(mSnapshot.Text);
    AnalyzePairs(mSnapshot.Text);
    ReadSyntax;
    FRowsTop := -1;
    InvalidateEditor;
  end
  else if (mView.TopRow - 1 <> FPaintedTop) and ((FPaintedRows > 0) or (Length(FNodes) > 0)) then
  begin
    // Bildlauf ohne Malen der oberen Zeilen (z. B. per Rollrad): ganz neu zeichnen.
    InvalidateEditor;
  end;
end;

/// <summary>Wort ab AIndex (0-basiert) in ALine, klein.</summary>
function WordAt(const ALine: string; AIndex: Integer): string;
var
  mStop: Integer;
begin
  mStop := AIndex + 1;
  while (mStop <= Length(ALine)) and CharInSet(ALine[mStop], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(mStop);
  end;
  Result := LowerCase(Copy(ALine, AIndex + 1, mStop - AIndex - 1));
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
  mToken: TAtlasPairToken;
begin
  SetLength(Result, ALineCount);
  for mToken in ATokens do
  begin
    if (mToken.Line >= 0) and (mToken.Line <= High(Result)) then
    begin
      Result[mToken.Line] := Result[mToken.Line] + [mToken];
    end;
  end;
end;

/// <summary>Blöcke, deren erstes Besitzerwort zu einer der Arten AKinds gehört (#1230).</summary>
function BranchesOf(const ABlocks: TArray<TAtlasPairBlock>; const ALines: TArray<string>;
  AKinds: TAtlasStickyKinds): TArray<TAtlasStickyBlock>;
var
  mBlock: TAtlasPairBlock;
  mKind: TAtlasStickyKind;
begin
  Result := nil;
  for mBlock in ABlocks do
  begin
    if (mBlock.OwnerLine < 0) or (mBlock.OwnerLine > High(ALines)) then
    begin
      Continue;
    end;
    if TAtlasStickyScroll.OwnerKind(WordAt(ALines[mBlock.OwnerLine], mBlock.OwnerCharacter), mKind) and
      (mKind in AKinds) then
    begin
      Result := Result + [TAtlasStickyBlock.Create(mBlock.OwnerLine, mBlock.OwnerCharacter, mBlock.CloseLine)];
    end;
  end;
end;

procedure TStickyData.AnalyzePairs(const AText: string);
var
  mSettings: TAtlasPluginSettings;
  mTokens: TArray<TAtlasPairToken>;
  mBlocks: TArray<TAtlasPairBlock>;
  mKinds: TAtlasStickyKinds;
begin
  FPairs := nil;
  FBranches := nil;
  FBlocks := nil;
  FGuidesKey := '';
  mSettings := TAtlasIdeSettings.Current;
  mKinds := StickyKinds(mSettings) - TAtlasStickyScroll.cOutlineKinds;
  if not mSettings.PairColors and (mKinds = []) then
  begin
    Exit;
  end;
  mTokens := TAtlasPairs.Analyze(AText, mBlocks);
  FBlocks := mBlocks;
  if mSettings.PairColors then
  begin
    FPairs := PairsPerLine(mTokens, Length(FLines));
  end;
  // Routinen und Klassen liefert die Gliederung.
  FBranches := BranchesOf(mBlocks, FLines, mKinds);
end;

procedure TStickyData.EnsureGuides(ATabWidth: Integer; AOwners: Boolean);
var
  mKey: string;
begin
  mKey := IntToStr(ATabWidth) + BoolToStr(AOwners, True);
  if mKey <> FGuidesKey then
  begin
    FGuides := TAtlasGuides.FromBlocks(FLines, FBlocks, ATabWidth, AOwners);
    FGuidesKey := mKey;
  end;
end;

/// <summary>Anweisungsblöcke ab AMinLines Zeilen (vom Kopf bis zum end bzw. until).</summary>
function LongBranches(const ABranches: TArray<TAtlasStickyBlock>; AMinLines: Integer): TArray<TAtlasStickyBlock>;
var
  mBlock: TAtlasStickyBlock;
begin
  Result := nil;
  for mBlock in ABranches do
  begin
    if mBlock.EndLine - mBlock.Line + 1 >= AMinLines then
    begin
      Result := Result + [mBlock];
    end;
  end;
end;

procedure TStickyPainter.UpdateRows(const AView: IOTAEditView; ATop: Integer);
var
  mSettings: TAtlasPluginSettings;
  mBranches: TArray<TAtlasStickyBlock>;
begin
  if (ATop = FRowsTop) and (FMaxLines = FRowsMax) then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  mBranches := LongBranches(FBranches, mSettings.StickyScrollBlockMinLines);
  FRows := TAtlasStickyScroll.Rows(TAtlasStickySource.Create(FNodes, FLines, mBranches,
    StickyKinds(mSettings) * TAtlasStickyScroll.cOutlineKinds), ATop, FMaxLines,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  FRowsTop := ATop;
  FRowsMax := FMaxLines;
end;

procedure TStickyPainter.SampleBack(const ARect: TRect; const AContext: INTACodeEditorPaintContext);
var
  mSample: COLORREF;
begin
  mSample := GetPixel(AContext.Canvas.Handle, ARect.Right - 2, ARect.Top + 1);
  if not FSchemeBackKnown and (mSample <> CLR_INVALID) then
  begin
    FBack := TAtlasColor(mSample);
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

function TStickyPainter.RowAt(AX, AY: Integer; out ARow: Integer): Boolean;
begin
  ARow := -1;
  Result := (FPaintedRows > 0) and (FRowHeight > 0) and (AY >= 0) and (AX >= FCodeLeft);
  if Result then
  begin
    ARow := AY div FRowHeight;
    Result := (ARow < FPaintedRows) and (ARow <= High(FRows));
  end;
end;

procedure TStickyState.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mView: IOTAEditView;
  mTop, mRow, mHeight: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FOn or (FFileName = '') then
  begin
    Exit;
  end;
  try
    mView := Context.EditView;
    mHeight := Rect.Bottom - Rect.Top;
    if (mView = nil) or (mView.Buffer = nil) or not SameText(Context.FileName, FFileName) or (mHeight <= 0) then
    begin
      Exit;
    end;
    mTop := mView.TopRow - 1;
    UpdateRows(mView, mTop);
    if Painted(mTop, mHeight) then
    begin
      QueueInvalidate;
    end;
    mRow := (Rect.Top + mHeight div 2) div mHeight;
    if mRow >= Length(FRows) then
    begin
      // Nicht übermalte Zeile: deren Hintergrund ist der des Editors.
      SampleBack(Rect, Context);
    end
    else
    begin
      // Mit jedem neu gezeichneten Kopf neu sammeln (DrawGuides).
      if mRow = 0 then
      begin
        FTaperColumns := nil;
      end;
      PaintRow(Rect, mRow, Context);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

function HasColumn(const AColumns: TArray<Integer>; AColumn: Integer): Boolean;
var
  mColumn: Integer;
begin
  Result := False;
  for mColumn in AColumns do
  begin
    if mColumn = AColumn then
    begin
      Exit(True);
    end;
  end;
end;

const
  // Wie die Blocklinien des Editors (Atlas.IDE.Editor.Pairs).
  cGuideMargin = 4;

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
  Result.Colors := TAtlasRoutineNesting.PairPalette(Result.Colors, ASettings);
  Result.Nesting := TAtlasRoutineNesting.FromSettings(ASettings);
end;

/// <summary>Spalte der Linie in Pixeln vor der Zelle ACell; nicht links aus dem Codebereich.</summary>
function GuideX(const APaint: TGuidePaint; const ACell: TRect): Integer;
begin
  Result := ACell.Left - Max(2, ACell.Width div 3) - (APaint.Width - 1) div 2;
  if (APaint.Code.Right > APaint.Code.Left) and (Result < APaint.Code.Left - cGuideMargin + APaint.Width div 2) then
  begin
    Result := APaint.Code.Left - cGuideMargin + APaint.Width div 2;
  end;
end;

function GuideColor(const APaint: TGuidePaint; const AGuide: TAtlasGuide): TAtlasColor;
begin
  Result := APaint.Nesting.Color(APaint.Colors, AGuide.Depth, AGuide.Routine);
  if APaint.Opacity < 100 then
  begin
    Result := TAtlasColorMath.Mix(Result, APaint.Back, APaint.Opacity / 100);
  end;
end;

/// <summary>Spitz nach oben: je Pixelzeile ein Streifen, der von 1 Pixel auf die Stiftbreite wächst und von der
/// Kopffarbe zur Linienfarbe übergeht; bei 1–2 Pixel Stiftbreite sieht man die Spitze sonst nicht.</summary>
procedure DrawFade(const APaint: TGuidePaint; AX: Integer; AColor: TAtlasColor);
var
  mFadeHeight, mOffset, mThick: Integer;
  mStep: TRect;
  mBrush: HBRUSH;
begin
  mFadeHeight := APaint.Rect.Height - 2;
  for mOffset := 0 to mFadeHeight - 1 do
  begin
    mThick := Max(1, MulDiv(APaint.Width, mOffset + 1, mFadeHeight));
    mStep := TRect.Create(AX - (mThick - 1) div 2, APaint.Rect.Bottom - mFadeHeight + mOffset,
      AX - (mThick - 1) div 2 + mThick, APaint.Rect.Bottom - mFadeHeight + mOffset + 1);
    mBrush := CreateSolidBrush(ColorToRGB(TColor(TAtlasColorMath.Mix(AColor, APaint.HeadBack,
      TAtlasStickyScroll.FadeWeight(mOffset, mFadeHeight)))));
    try
      FillRect(APaint.DC, mStep, mBrush);
    finally
      DeleteObject(mBrush);
    end;
  end;
end;

/// <summary>Senkrechter Strich bei AX durch die Zeile; mit AHook > 0 beginnt er oben mit einem Haken dieser
/// Länge (Kopfzeile des Elements).</summary>
procedure DrawStroke(const APaint: TGuidePaint; AX, AHook: Integer; AColor: TAtlasColor);
var
  mPen, mOld: HGDIOBJ;
  mTop: Integer;
begin
  mPen := CreatePen(PS_SOLID, APaint.Width, ColorToRGB(TColor(AColor)));
  mOld := SelectObject(APaint.DC, mPen);
  try
    mTop := APaint.Rect.Top;
    if AHook > 0 then
    begin
      mTop := mTop + 2;
    end;
    MoveToEx(APaint.DC, AX, mTop, nil);
    LineTo(APaint.DC, AX, APaint.Rect.Bottom);
    if AHook > 0 then
    begin
      MoveToEx(APaint.DC, AX, mTop, nil);
      LineTo(APaint.DC, AX + AHook, mTop);
    end;
  finally
    SelectObject(APaint.DC, mOld);
    DeleteObject(mPen);
  end;
end;

procedure TStickyPainter.DrawGuide(const APaint: TGuidePaint; const AGuide: TAtlasGuide; ARowIndex: Integer);
var
  mStart: TAtlasStickyGuideStart;
  mCell: TRect;
  X: Integer;
  mLineColor: TAtlasColor;
begin
  // Das Element der Linie: die Kopfzeile, deren Zeile die erste der Linie ist (Anweisung bzw. Öffner). Ohne
  // Kopfzeile blendet die Linie in der letzten Kopfzeile ein, sonst käme sie ohne Anfang darunter hervor.
  mStart := TAtlasStickyScroll.GuideStart(FRows, AGuide.FirstLine);
  if (mStart.Row < 0) or (ARowIndex < mStart.Row) then
  begin
    Exit;
  end;
  mCell := APaint.Context.EditorState.GetCharacterPosPx(AGuide.Column, APaint.Context.EditorLineNum);
  X := GuideX(APaint, mCell);
  mLineColor := GuideColor(APaint, AGuide);
  if not mStart.FadeIn then
  begin
    if ARowIndex = mStart.Row then
    begin
      DrawStroke(APaint, X, Max(3, mCell.Width div 2), mLineColor);
    end
    else
    begin
      DrawStroke(APaint, X, 0, mLineColor);
    end;
  end
  // Oben spitz zulaufend, ab der Oberkante der letzten Kopfzeile wie die Linie eines Elements
  // mit eigener Kopfzeile. Läge die Spitze im Text dieser Zeile (z. B. procedure), zeichnen sie die Blocklinien
  // des Editors in der Zeile darunter (TaperBelow). In Pixeln, denn der Strich wird an den Rand geschoben (GuideX).
  else if X + APaint.Width > APaint.Context.EditorState.GetCharacterPosPx(FRows[mStart.Row].Indent,
    APaint.Context.EditorLineNum).Left then
  begin
    if not HasColumn(FTaperColumns, AGuide.Column) then
    begin
      FTaperColumns := FTaperColumns + [AGuide.Column];
    end;
  end
  else
  begin
    DrawFade(APaint, X, mLineColor);
  end;
end;

procedure TStickyPainter.DrawGuides(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext;
  ABack: TAtlasColor);
var
  mSettings: TAtlasPluginSettings;
  mPaint: TGuidePaint;
  mGuide: TAtlasGuide;
  mBelow, mSaved: Integer;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not (mSettings.PairColors and mSettings.PairGuides) or (Length(FBlocks) = 0) or NoEditor(AContext) or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairGuides, FFileName) then
  begin
    Exit;
  end;
  EnsureGuides(TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer),
    mSettings.PairOwners and not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, FFileName));
  mPaint := GuidePaintOf(AContext, ARect, ABack, mSettings);
  // Erste Zeile unter dem Kopf: Nur Linien, die dort weiterlaufen, reichen in den Kopf.
  mBelow := FRowsTop + Length(FRows);
  mSaved := SaveDC(mPaint.DC);
  try
    if mPaint.Code.Right > mPaint.Code.Left then
    begin
      IntersectClipRect(mPaint.DC, mPaint.Code.Left - cGuideMargin, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mGuide in FGuides do
    begin
      if (mGuide.FirstLine < mBelow) and (mGuide.LastLine >= mBelow) then
      begin
        DrawGuide(mPaint, mGuide, ARowIndex);
      end;
    end;
  finally
    RestoreDC(mPaint.DC, mSaved);
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
  cElements: array[TAtlasStickySyntax] of string = ('Whitespace', 'Reserved word', 'Identifier', 'Number', 'String',
    'Character', 'Comment', 'Symbol', 'Preprocessor');
var
  mServices: IOTAServices;
  mRegistry: TRegistry;
  mKind: TAtlasStickySyntax;
  mBase: string;
  mBack: TAtlasColor;
begin
  for mKind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
  begin
    FSyntax[mKind] := Default(TSyntaxStyle);
  end;
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  mBase := mServices.GetBaseRegistryKey + '\Editor\Highlight\';
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    for mKind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
    begin
      FSyntax[mKind] := ReadStyle(mRegistry, mBase + cElements[mKind]);
    end;
    FSchemeBackKnown := ReadSchemeBack(mRegistry, mBase + 'Plain text', mBack);
    if FSchemeBackKnown then
    begin
      FSchemeBack := mBack;
    end;
  finally
    mRegistry.Free;
  end;
end;

/// <summary>Farbschema des Editors (Farbe, fett, kursiv) je Zeichen von AText.</summary>
procedure ApplySyntax(const AText: string; const ASyntax: TSyntaxStyles; var AColors: TArray<TColor>;
  var AStyles: TArray<TFontStyles>);
var
  mToken: TAtlasStickyToken;
  mStyle: TSyntaxStyle;
  mIndex: Integer;
begin
  for mToken in TAtlasStickyScroll.Syntax(AText) do
  begin
    mStyle := ASyntax[mToken.Kind];
    for mIndex := mToken.Start - 1 to Min(High(AColors), mToken.Start + mToken.Length - 2) do
    begin
      if mStyle.HasColor then
      begin
        AColors[mIndex] := mStyle.Color;
      end;
      AStyles[mIndex] := mStyle.Style;
    end;
  end;
end;

function SpanColor(const ASpan: TAtlasPairSpan; const APairs: TAtlasColors;
  const ANesting: TAtlasRoutineNesting): TColor;
begin
  if ASpan.Unpaired then
  begin
    Result := TColor(APairs.Error);
  end
  else
  begin
    Result := TColor(ANesting.Color(APairs, ASpan.Depth, ASpan.Routine));
  end;
end;

/// <summary>Paarfarben ersetzen die Farbe des Farbschemas; fett und kursiv bleiben.</summary>
procedure ApplySpans(const ASpans: TArray<TAtlasPairSpan>; const APairs: TAtlasColors; var AColors: TArray<TColor>);
var
  mSpan: TAtlasPairSpan;
  mIndex: Integer;
  mNesting: TAtlasRoutineNesting;
begin
  mNesting := TAtlasRoutineNesting.FromSettings(TAtlasIdeSettings.Current);
  for mSpan in ASpans do
  begin
    for mIndex := mSpan.Start - 1 to Min(High(AColors), mSpan.Start + mSpan.Length - 2) do
    begin
      AColors[mIndex] := SpanColor(mSpan, APairs, mNesting);
    end;
  end;
end;

/// <summary>AText ab AX in Läufen gleicher Farbe und Schrift am Stück.</summary>
procedure DrawRuns(ACanvas: TCanvas; AX, ATop: Integer; const AText: string; const AColors: TArray<TColor>;
  const AStyles: TArray<TFontStyles>);
var
  mIndex, mStop: Integer;
  mPart: string;
begin
  mIndex := 0;
  while mIndex <= High(AColors) do
  begin
    mStop := mIndex;
    while (mStop < High(AColors)) and (AColors[mStop + 1] = AColors[mIndex]) and
      (AStyles[mStop + 1] = AStyles[mIndex]) do
    begin
      Inc(mStop);
    end;
    mPart := Copy(AText, mIndex + 1, mStop - mIndex + 1);
    ACanvas.Font.Color := AColors[mIndex];
    ACanvas.Font.Style := AStyles[mIndex];
    ACanvas.TextOut(AX, ATop, mPart);
    Inc(AX, ACanvas.TextWidth(mPart));
    mIndex := mStop + 1;
  end;
end;

function TStickyPainter.RowSpans(const ARow: TAtlasStickyRow): TArray<TAtlasPairSpan>;
var
  mSettings: TAtlasPluginSettings;
begin
  Result := nil;
  mSettings := TAtlasIdeSettings.Current;
  if (ARow.Line < 0) or (ARow.Line > High(FPairs)) or (ARow.Line > High(FLines)) or not mSettings.PairColors or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairColors, FFileName) then
  begin
    Exit;
  end;
  Result := TAtlasPairs.Spans(ARow.Text, FLines[ARow.Line], FPairs[ARow.Line],
    mSettings.PairOwners and not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, FFileName));
end;

procedure TStickyPainter.DrawHeader(ACanvas: TCanvas; ALeft, ATop: Integer; const ARow: TAtlasStickyRow;
  const AColors: TAtlasColors; ATextColor: TColor);
var
  mSpans: TArray<TAtlasPairSpan>;
  mCharColors: TArray<TColor>;
  mCharStyles: TArray<TFontStyles>;
  mIndex: Integer;
begin
  if ARow.Summary or (ARow.Text = '') then
  begin
    // Zusammenfassung „A › B“: gedämpft wie bisher, ohne Hervorhebung.
    ACanvas.Font.Color := ATextColor;
    ACanvas.TextOut(ALeft, ATop, ARow.Text);
    Exit;
  end;
  // Hervorhebung wie im Editor (Farbschema, fett, kursiv), je Zeichen.
  SetLength(mCharColors, Length(ARow.Text));
  SetLength(mCharStyles, Length(ARow.Text));
  for mIndex := 0 to High(mCharColors) do
  begin
    mCharColors[mIndex] := ATextColor;
    mCharStyles[mIndex] := [];
  end;
  ApplySyntax(ARow.Text, FSyntax, mCharColors, mCharStyles);
  // Paarfarben wie im Editor (#1229).
  mSpans := RowSpans(ARow);
  if Length(mSpans) > 0 then
  begin
    ApplySpans(mSpans, TAtlasRoutineNesting.PairPalette(AColors, TAtlasIdeSettings.Current), mCharColors);
  end;
  DrawRuns(ACanvas, ALeft, ATop, ARow.Text, mCharColors, mCharStyles);
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
  mCode: TRect;
begin
  Result := ARect.Left;
  if AContext.LineState = nil then
  begin
    Exit;
  end;
  mCode := AContext.LineState.CodeRect;
  if mCode.Right > mCode.Left then
  begin
    Result := mCode.Left;
  end;
end;

function TStickyPainter.RowBack(ACanvas: TCanvas; const ARect: TRect): TAtlasColor;
var
  mSample: COLORREF;
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
    mSample := GetPixel(ACanvas.Handle, ARect.Right - 2, ARect.Top + 1);
    if mSample = CLR_INVALID then
    begin
      Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
    end
    else
    begin
      Result := TAtlasColor(mSample);
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

procedure TStickyPainter.PaintRow(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext);
var
  mRow: TAtlasStickyRow;
  mCanvas: TCanvas;
  mArea, mCell: TRect;
  mColors: TAtlasColors;
  mBack: TAtlasColor;
  mSaved, mTextTop: Integer;
  mTools: TSavedTools;
begin
  mRow := FRows[ARowIndex];
  mCanvas := AContext.Canvas;
  FCodeLeft := CodeLeftOf(AContext, ARect);
  mArea := TRect.Create(FCodeLeft, ARect.Top, ARect.Right, ARect.Bottom);
  mBack := RowBack(mCanvas, ARect);
  mColors := TAtlasColors.ForBackground(mBack);
  mTools := TSavedTools.Save(mCanvas);
  mSaved := SaveDC(mCanvas.Handle);
  try
    IntersectClipRect(mCanvas.Handle, mArea.Left, mArea.Top, mArea.Right, mArea.Bottom);
    FillRow(mCanvas, mArea, mColors, mBack, mRow.Summary);
    mCell := AContext.EditorState.GetCharacterPosPx(mRow.Indent + 1, AContext.EditorLineNum);
    mTextTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mCanvas.TextHeight('Xg')) div 2);
    DrawHeader(mCanvas, Max(FCodeLeft, mCell.Left), mTextTop, mRow, mColors, mCanvas.Font.Color);
    if ARowIndex = High(FRows) then
    begin
      DrawSeparator(mCanvas, mArea, mColors);
    end;
  finally
    RestoreDC(mCanvas.Handle, mSaved);
    DrawGuides(ARect, ARowIndex, AContext, mBack);
    mTools.Restore(mCanvas);
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
  mView: IOTAEditView;
  mRow: Integer;
  mTarget: TAtlasStickyRow;
  mFileName: string;
begin
  try
    if not FOn or (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not RowAt(X, Y, mRow) then
    begin
      Exit;
    end;
    // Nur, wenn die Köpfe noch so stehen: gleiche Datei, nicht gescrollt.
    mView := TAtlasEditorBuffer.ActiveView;
    if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, FFileName) or
      (mView.TopRow - 1 <> FPaintedTop) then
    begin
      Exit;
    end;
    mTarget := FRows[mRow];
    mFileName := FFileName;
    // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor auf die angeklickte Stelle.
    TAtlasMainThread.ForceQueue(TAtlasFeature.StickyScroll,
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.StickyScroll,
          procedure
          begin
            TAtlasIdeNavigation.GoToLocation(mFileName, mTarget.Line, mTarget.Character);
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

class procedure TAtlasIdeStickyScroll.ThemeChanged;
begin
  if FState <> nil then
  begin
    TStickyState(FState).ThemeChanged;
  end;
end;

class function TAtlasIdeStickyScroll.CoveredRows(const AFileName: string): Integer;
var
  mState: TStickyState;
begin
  Result := 0;
  if FState = nil then
  begin
    Exit;
  end;
  mState := TStickyState(FState);
  if mState.FOn and SameText(mState.FFileName, AFileName) then
  begin
    Result := mState.FPaintedRows;
  end;
end;

class function TAtlasIdeStickyScroll.TaperBelow(const AFileName: string; AColumn: Integer): Boolean;
var
  mState: TStickyState;
begin
  Result := False;
  if FState = nil then
  begin
    Exit;
  end;
  mState := TStickyState(FState);
  Result := mState.FOn and (mState.FPaintedRows > 0) and SameText(mState.FFileName, AFileName) and
    HasColumn(mState.FTaperColumns, AColumn);
end;

class function TAtlasIdeStickyScroll.HeaderAt(const AFileName: string; ATopRow, AX, AY: Integer;
  out ARow: TAtlasStickyRow): Boolean;
var
  mState: TStickyState;
  mRow: Integer;
begin
  ARow := Default(TAtlasStickyRow);
  Result := False;
  if FState = nil then
  begin
    Exit;
  end;
  mState := TStickyState(FState);
  // Nur der Kopf, der so gezeichnet steht: gleiche Datei, nicht gescrollt (wie beim Klick).
  Result := mState.FOn and SameText(mState.FFileName, AFileName) and (ATopRow - 1 = mState.FPaintedTop) and
    mState.RowAt(AX, AY, mRow);
  if Result then
  begin
    ARow := mState.FRows[mRow];
  end;
end;

class function TAtlasIdeStickyScroll.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.StickyScroll;
end;

end.
