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
//   Loslassen der Maustaste zum Namen im Kopf und verwirft die Markierung, die
//   der Editor ab der verdeckten Zeile begonnen hat (ein Sprung bei noch
//   gedrückter Taste markierte den ganzen Bereich dazwischen).
// - Strg+Klick auf einen Bezeichner im Kopf springt über SetDefinitionJump zu
//   dessen Definition; wo der Kopf keinen Quelltext zeigt, wie ein Klick zum
//   Namen im Kopf. Gehe zu Definition der IDE, die der Klick ebenfalls
//   auslöst, bricht danach ab (TakeCtrlClick), sonst spränge sie zum
//   verdeckten Bezeichner.
// - Hover und Tooltip der IDE: SourceAt bzw. MouseSourceAt nennen den
//   Quelltext im Kopf unter der Maus (TAtlasStickyScroll.SourceIndex); der
//   Tooltip gilt ihm und nie der verdeckten Zeile darunter.
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
  ToolsAPI;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was am Mauspunkt im Editor liegt: kein Kopf; Kopf mit Quelltext an dieser Stelle; Kopf ohne
  /// Quelltext (Zusammenfassung, Einrückung, gekürzte Parameterliste „(…)“).</summary>
  TAtlasStickyHit = (None, Source, Covered);
  {$SCOPEDENUMS OFF}

  /// <summary>Sprung zur Definition des Bezeichners in AFileName an ALine, ACharacter (0-basiert).</summary>
  TAtlasStickyJump = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);

  TAtlasIdeStickyScroll = class
  private class var
    FState: TObject;
    FDefinitionJump: TAtlasStickyJump;
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
    /// <summary>Was der Kopf von AView am Mauspunkt AX, AY (Editorkoordinaten) in Spalte AColumn (1-basiert) zeigt;
    /// bei Source die Stelle im Quelltext: Zeile ALine (1-basiert), Zeichen AIndex (0-basiert).</summary>
    class function SourceAt(const AView: IOTAEditView; AX, AY, AColumn: Integer; out ALine,
      AIndex: Integer): TAtlasStickyHit; static;
    /// <summary>Wie SourceAt am letzten Mauspunkt im Editor; für den Tooltip der IDE, der nur Zeile und Spalte nennt.
    /// </summary>
    class function MouseSourceAt(const AView: IOTAEditView; AColumn: Integer; out ALine,
      AIndex: Integer): TAtlasStickyHit; static;
    /// <summary>Sprung für Strg+Klick auf einen Bezeichner im Kopf; nil meldet ab.</summary>
    class procedure SetDefinitionJump(const AJump: TAtlasStickyJump); static;
    /// <summary>True, wenn eben ein Strg+Klick auf den Kopf von AFileName lag: Den Sprung übernimmt der Kopf, Gehe zu
    /// Definition der IDE bricht ab. Gilt einmal je Klick.</summary>
    class function TakeCtrlClick(const AFileName: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.StickyScroll,
  Atlas.Core.Editor.StickyPlan,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.Guides,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Outline.StickyPaint,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.Core.Editor.GuideStroke;

const
  cTickMs = 100;
  /// <summary>Mindestlänge des Hakens, mit dem eine Blocklinie in der Kopfzeile ihres Elements beginnt (Pixel).
  /// </summary>
  cHookMin = 3;

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
    FSyntax: TAtlasStickySyntaxStyles;
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
    procedure DrawGuide(const APaint: TAtlasStickyGuidePaint; const AGuide: TAtlasGuide; ARowIndex: Integer);
    procedure PaintRow(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext);
    /// <summary>Blocklinien im Kopf: Jede beginnt mit Haken in der Kopfzeile ihres Elements; ohne Kopfzeile blendet
    /// sie in der letzten Kopfzeile ein.</summary>
    procedure DrawGuides(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext;
      ABack: TAtlasColor);
    /// <summary>Kopftext ab ALeft; Klammern und Blockwörter in der Farbe ihrer Tiefe (#1229).</summary>
    procedure DrawHeader(ACanvas: TCanvas; ALeft, ATop: Integer; const ARow: TAtlasStickyRow;
      const AColors: TAtlasColors; ATextColor: TColor);
  end;

  /// <summary>Maus über dem Editor: letzter Mauspunkt und zuletzt Strg+Klick auf den Kopf (Datei, Zeitpunkt).</summary>
  TStickyPointer = record
    X: Integer;
    Y: Integer;
    Known: Boolean;
    CtrlFile: string;
    CtrlTick: UInt64;
    /// <summary>Sprung nach einem Klick auf den Kopf, ausgeführt erst nach dem Loslassen der Maustaste: Solange sie
    /// gedrückt ist, zieht der Editor ab der verdeckten Zeile eine Markierung bis zur Sprungstelle auf.</summary>
    JumpPending: Boolean;
    JumpFile: string;
    JumpLine: Integer;
    JumpCharacter: Integer;
  end;

  TStickyState = class(TStickyPainter)
  private
    FTimer: TTimer;
    FPointer: TStickyPointer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FOn: Boolean;
    procedure Tick(Sender: TObject);
    /// <summary>Gemerkten Sprung ausführen, sobald die linke Maustaste oben ist.</summary>
    procedure RunPendingJump;
    procedure Clear;
    procedure Update;
    procedure QueueInvalidate;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    /// <summary>Kopfzeile ARow am Mauspunkt AX, AY, wie sie zu AFileName mit oberster Zeile ATopRow (1-basiert)
    /// gezeichnet steht.</summary>
    function HeaderAt(const AFileName: string; ATopRow, AX, AY: Integer; out ARow: TAtlasStickyRow): Boolean;
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
  FEvents.OnEditorMouseMove := EditorMouseMove;
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
  FEvents.OnEditorMouseMove := nil;
  FEvents.OnEditorScrolled := nil;
  FEventsRef := nil;
  StickyShown := False;
  if mShown then
  begin
    InvalidateEditor;
  end;
  inherited Destroy;
end;

procedure TStickyState.RunPendingJump;
begin
  if not FPointer.JumpPending or (GetAsyncKeyState(VK_LBUTTON) < 0) then
  begin
    Exit;
  end;
  FPointer.JumpPending := False;
  TAtlasGuard.Run(TAtlasFeature.StickyScroll,
    procedure
    var
      mView: IOTAEditView;
    begin
      TAtlasIdeNavigation.GoToLocation(FPointer.JumpFile, FPointer.JumpLine, FPointer.JumpCharacter);
      // Was der Editor beim Klick auf die verdeckte Zeile als Markierung begonnen hat, verwerfen.
      mView := TAtlasEditorBuffer.ActiveView;
      if (mView <> nil) and (mView.Block <> nil) then
      begin
        mView.Block.Reset;
      end;
    end);
end;

procedure TStickyState.Tick(Sender: TObject);
begin
  try
    RunPendingJump;
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
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
  case TAtlasStickyPlan.Refresh(mSnapshot.Status in [TAtlasOutlineStatus.NoFile, TAtlasOutlineStatus.NoServer],
    mSnapshot.Status = TAtlasOutlineStatus.Waiting,
    not SameText(mSnapshot.FileName, FFileName) or (mSnapshot.Stamp <> FStamp), mView.TopRow - 1 <> FPaintedTop,
    (FPaintedRows > 0) or (Length(FNodes) > 0)) of
    TAtlasStickyRefresh.Clear:
      begin
        mShown := FPaintedRows > 0;
        Clear;
        if mShown then
        begin
          InvalidateEditor;
        end;
      end;
    TAtlasStickyRefresh.Reload:
      begin
        FFileName := mSnapshot.FileName;
        FStamp := mSnapshot.Stamp;
        FNodes := mSnapshot.Nodes;
        FLines := TTextLines.SplitLines(mSnapshot.Text);
        AnalyzePairs(mSnapshot.Text);
        ReadSyntax;
        FRowsTop := -1;
        InvalidateEditor;
      end;
    TAtlasStickyRefresh.Repaint:
      // Bildlauf ohne Malen der oberen Zeilen (z. B. per Rollrad): ganz neu zeichnen.
      InvalidateEditor;
  else
    // Keep: warten bzw. nichts geändert.
  end;
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
    mRow := TAtlasGuideStroke.RowIndex(Rect.Top, mHeight);
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

procedure TStickyState.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
begin
  FPointer.X := X;
  FPointer.Y := Y;
  FPointer.Known := True;
end;

{ TStickyData }

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
  mKinds := TAtlasStickyPlan.Kinds(mSettings) - TAtlasStickyScroll.cOutlineKinds;
  if not mSettings.PairColors and (mKinds = []) then
  begin
    Exit;
  end;
  mTokens := TAtlasPairs.Analyze(AText, mBlocks);
  FBlocks := mBlocks;
  if mSettings.PairColors then
  begin
    FPairs := TAtlasStickyPlan.PairsPerLine(mTokens, Length(FLines));
  end;
  // Routinen und Klassen liefert die Gliederung.
  FBranches := TAtlasStickyPlan.BranchesOf(mBlocks, FLines, mKinds);
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

{ TStickyPainter }

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
  mBranches := TAtlasStickyPlan.LongBranches(FBranches, mSettings.StickyScrollBlockMinLines);
  FRows := TAtlasStickyScroll.Rows(TAtlasStickySource.Create(FNodes, FLines, mBranches,
    TAtlasStickyPlan.Kinds(mSettings) * TAtlasStickyScroll.cOutlineKinds), ATop, FMaxLines,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  FRowsTop := ATop;
  FRowsMax := FMaxLines;
end;

function TStickyPainter.Painted(ATop, AHeight: Integer): Boolean;
begin
  Result := TAtlasStickyPlan.Scrolled(FPaintedTop, ATop, FPaintedRows, Length(FRows));
  FPaintedTop := ATop;
  FPaintedRows := Length(FRows);
  FRowHeight := AHeight;
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

function TStickyState.HeaderAt(const AFileName: string; ATopRow, AX, AY: Integer; out ARow: TAtlasStickyRow): Boolean;
var
  mRow: Integer;
begin
  ARow := Default(TAtlasStickyRow);
  // Nur der Kopf, der so gezeichnet steht: gleiche Datei, nicht gescrollt (wie beim Klick).
  Result := FOn and SameText(FFileName, AFileName) and (ATopRow - 1 = FPaintedTop) and RowAt(AX, AY, mRow);
  if Result then
  begin
    ARow := FRows[mRow];
  end;
end;

function TStickyPainter.RowAt(AX, AY: Integer; out ARow: Integer): Boolean;
begin
  Result := TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(FPaintedRows, Length(FRows), FRowHeight, FCodeLeft), AX,
    AY, ARow);
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

procedure TStickyData.ReadSyntax;
begin
  TAtlasStickyPaint.ReadSyntax(FSyntax, FSchemeBack, FSchemeBackKnown);
end;

procedure TStickyPainter.DrawGuide(const APaint: TAtlasStickyGuidePaint; const AGuide: TAtlasGuide;
  ARowIndex: Integer);
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
  X := TAtlasStickyPlan.GuideX(mCell.Left, mCell.Width, APaint.Width, APaint.Code.Left, APaint.Code.Right);
  mLineColor := TAtlasStickyPaint.GuideColor(APaint, AGuide);
  if not mStart.FadeIn then
  begin
    if ARowIndex = mStart.Row then
    begin
      TAtlasStickyPaint.DrawStroke(APaint, X, Max(cHookMin, mCell.Width div 2), mLineColor);
    end
    else
    begin
      TAtlasStickyPaint.DrawStroke(APaint, X, 0, mLineColor);
    end;
  end
  // Oben spitz zulaufend, ab der Oberkante der letzten Kopfzeile wie die Linie eines Elements
  // mit eigener Kopfzeile. Läge die Spitze im Text dieser Zeile (z. B. procedure), zeichnen sie die Blocklinien
  // des Editors in der Zeile darunter (TaperBelow). In Pixeln, denn der Strich wird an den Rand geschoben (GuideX).
  else if X + APaint.Width > APaint.Context.EditorState.GetCharacterPosPx(FRows[mStart.Row].Indent,
    APaint.Context.EditorLineNum).Left then
  begin
    if not TAtlasStickyPlan.HasColumn(FTaperColumns, AGuide.Column) then
    begin
      FTaperColumns := FTaperColumns + [AGuide.Column];
    end;
  end
  else
  begin
    TAtlasStickyPaint.DrawFade(APaint, X, mLineColor);
  end;
end;

procedure TStickyPainter.DrawGuides(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext;
  ABack: TAtlasColor);
var
  mSettings: TAtlasPluginSettings;
  mPaint: TAtlasStickyGuidePaint;
  mGuide: TAtlasGuide;
  mBelow, mSaved: Integer;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not (mSettings.PairColors and mSettings.PairGuides) or (Length(FBlocks) = 0) or
    TAtlasStickyPaint.NoEditor(AContext) or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairGuides, FFileName) then
  begin
    Exit;
  end;
  EnsureGuides(TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer),
    mSettings.PairOwners and not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, FFileName));
  mPaint := TAtlasStickyPaint.GuidePaintOf(AContext, ARect, ABack, mSettings);
  // Erste Zeile unter dem Kopf: Nur Linien, die dort weiterlaufen, reichen in den Kopf.
  mBelow := FRowsTop + Length(FRows);
  mSaved := SaveDC(mPaint.DC);
  try
    if mPaint.Code.Right > mPaint.Code.Left then
    begin
      IntersectClipRect(mPaint.DC, mPaint.Code.Left - TAtlasStickyPlan.cGuideMargin, ARect.Top, ARect.Right,
        ARect.Bottom);
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

{ TAtlasStickySavedTools }

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
  TAtlasStickyPaint.ApplySyntax(ARow.Text, FSyntax, mCharColors, mCharStyles);
  // Paarfarben wie im Editor (#1229).
  mSpans := RowSpans(ARow);
  if Length(mSpans) > 0 then
  begin
    TAtlasStickyPaint.ApplyPairSpans(mSpans, AColors, mCharColors);
  end;
  TAtlasStickyPaint.DrawRuns(ACanvas, ALeft, ATop, ARow.Text, mCharColors, mCharStyles);
end;

procedure TStickyPainter.PaintRow(const ARect: TRect; ARowIndex: Integer; const AContext: INTACodeEditorPaintContext);
var
  mRow: TAtlasStickyRow;
  mCanvas: TCanvas;
  mArea, mCell: TRect;
  mColors: TAtlasColors;
  mBack: TAtlasColor;
  mSaved, mTextTop: Integer;
  mTools: TAtlasStickySavedTools;
begin
  mRow := FRows[ARowIndex];
  mCanvas := AContext.Canvas;
  FCodeLeft := TAtlasStickyPaint.CodeLeftOf(AContext, ARect);
  mArea := TRect.Create(FCodeLeft, ARect.Top, ARect.Right, ARect.Bottom);
  mBack := RowBack(mCanvas, ARect);
  mColors := TAtlasColors.ForBackground(mBack);
  mTools := TAtlasStickySavedTools.Save(mCanvas);
  mSaved := SaveDC(mCanvas.Handle);
  try
    IntersectClipRect(mCanvas.Handle, mArea.Left, mArea.Top, mArea.Right, mArea.Bottom);
    TAtlasStickyPaint.FillRow(mCanvas, mArea, mColors, mBack, mRow.Summary);
    mCell := AContext.EditorState.GetCharacterPosPx(mRow.Indent + 1, AContext.EditorLineNum);
    mTextTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mCanvas.TextHeight('Xg')) div 2);
    DrawHeader(mCanvas, Max(FCodeLeft, mCell.Left), mTextTop, mRow, mColors, mCanvas.Font.Color);
    if ARowIndex = High(FRows) then
    begin
      TAtlasStickyPaint.DrawSeparator(mCanvas, mArea, mColors);
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

/// <summary>Spalte (1-basiert) am Mauspunkt AX, AY in AEditor; 0, wenn der Editor sie nicht nennt.</summary>
function ColumnAt(const AEditor: TWinControl; AX, AY: Integer): Integer;
var
  mServices: INTACodeEditorServices;
  mState: INTACodeEditorState;
  mVisibleLine: Integer;
begin
  Result := 0;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    Exit;
  end;
  mState := mServices.EditorState[AEditor];
  if (mState = nil) or not mState.PointToCharacterPos(Point(AX, AY), Result, mVisibleLine) then
  begin
    Result := 0;
  end;
end;

/// <summary>Nach dem Mausereignis zur Definition des Bezeichners an ALine, ACharacter (0-basiert) springen.</summary>
procedure QueueDefinition(const AFileName: string; ALine, ACharacter: Integer);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.StickyScroll,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.StickyScroll,
        procedure
        var
          mJump: TAtlasStickyJump;
        begin
          mJump := TAtlasIdeStickyScroll.FDefinitionJump;
          if Assigned(mJump) then
          begin
            mJump(AFileName, ALine, ACharacter);
          end;
        end);
    end);
end;

procedure TStickyState.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mView: IOTAEditView;
  mRow, mLine, mIndex: Integer;
  mClick: TAtlasStickyClick;
begin
  try
    mClick := TAtlasStickyPlan.Click(Button = mbLeft, ssShift in Shift, ssCtrl in Shift, ssAlt in Shift);
    if not FOn or (mClick = TAtlasStickyClick.Ignore) or not RowAt(X, Y, mRow) then
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
    if mClick = TAtlasStickyClick.Definition then
    begin
      // Gehe zu Definition der IDE meint die verdeckte Zeile: Sie bricht ab, den Sprung macht der Kopf.
      FPointer.CtrlFile := FFileName;
      FPointer.CtrlTick := GetTickCount64;
      if TAtlasIdeStickyScroll.SourceAt(mView, X, Y, ColumnAt(Editor, X, Y), mLine, mIndex) =
        TAtlasStickyHit.Source then
      begin
        QueueDefinition(FFileName, mLine - 1, mIndex);
        Exit;
      end;
    end;
    FPointer.JumpPending := True;
    FPointer.JumpFile := FFileName;
    FPointer.JumpLine := FRows[mRow].Line;
    FPointer.JumpCharacter := FRows[mRow].Character;
    // Gleich prüfen, falls die Taste schon wieder oben ist; sonst übernimmt der Takt.
    TAtlasMainThread.ForceQueue(TAtlasFeature.StickyScroll, RunPendingJump);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
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

class function TAtlasIdeStickyScroll.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.StickyScroll;
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
    TAtlasStickyPlan.HasColumn(mState.FTaperColumns, AColumn);
end;

class function TAtlasIdeStickyScroll.SourceAt(const AView: IOTAEditView; AX, AY, AColumn: Integer; out ALine,
  AIndex: Integer): TAtlasStickyHit;
var
  mHeader: TAtlasStickyRow;
begin
  ALine := 0;
  AIndex := -1;
  Result := TAtlasStickyHit.None;
  if (FState = nil) or (AView = nil) or (AView.Buffer = nil) or
    not TStickyState(FState).HeaderAt(AView.Buffer.FileName, AView.TopRow, AX, AY, mHeader) then
  begin
    Exit;
  end;
  Result := TAtlasStickyHit.Covered;
  // Der Kopf zeigt die Zeile ab ihrer Einrückung in Spalte Indent + 1, Zeichen für Zeichen wie im Editor; verglichen
  // wird mit dem Puffer, nicht mit dem Stand der Gliederung.
  if (mHeader.Line >= 0) and TAtlasStickyScroll.SourceIndex(mHeader, TAtlasEditorBuffer.LineText(AView,
    mHeader.Line + 1), AColumn - mHeader.Indent - 1, AIndex) then
  begin
    ALine := mHeader.Line + 1;
    Result := TAtlasStickyHit.Source;
  end;
end;

class function TAtlasIdeStickyScroll.MouseSourceAt(const AView: IOTAEditView; AColumn: Integer; out ALine,
  AIndex: Integer): TAtlasStickyHit;
var
  mPointer: TStickyPointer;
begin
  ALine := 0;
  AIndex := -1;
  Result := TAtlasStickyHit.None;
  if FState = nil then
  begin
    Exit;
  end;
  mPointer := TStickyState(FState).FPointer;
  if mPointer.Known then
  begin
    Result := SourceAt(AView, mPointer.X, mPointer.Y, AColumn, ALine, AIndex);
  end;
end;

class procedure TAtlasIdeStickyScroll.SetDefinitionJump(const AJump: TAtlasStickyJump);
begin
  FDefinitionJump := AJump;
end;

class function TAtlasIdeStickyScroll.TakeCtrlClick(const AFileName: string): Boolean;
var
  mState: TStickyState;
begin
  Result := False;
  if FState = nil then
  begin
    Exit;
  end;
  mState := TStickyState(FState);
  Result := TAtlasStickyPlan.CtrlClickFresh(mState.FPointer.CtrlFile, AFileName, mState.FPointer.CtrlTick,
    GetTickCount64);
  mState.FPointer.CtrlFile := '';
end;

end.
