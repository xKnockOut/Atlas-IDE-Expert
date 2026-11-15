unit Atlas.IDE.Tests.Lens;

// Code Lens „Test ausführen“ und „Debuggen“ an [TestFixture], [Test] und
// [TestCase] (#69, #585).
// - Erkennen: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause
//   liest er Fixtures und Tests der Unit mit Atlas.Text.DUnitX (lokal, ohne
//   Server; dieselbe Erkennung wie das MCP-Werkzeug run_tests und #154).
// - Zeichnen: hinter dem Ende der Attributzeile ([TestFixture], [Test];
//   ohne Attribut hinter der Deklaration) eine Marke „Test ausführen“ bzw.
//   „Tests der Klasse ausführen“, nach einem Lauf mit dem Stand (bestanden
//   grün, fehlgeschlagen in der Fehlerfarbe). Eine Marke über mehrere Tests
//   (Fixture, alle Fälle einer [TestCase]-Methode) gilt erst als bestanden,
//   wenn jeder ihrer Tests ein Ergebnis hat; lief erst ein Teil, steht dort
//   „1/4 bestanden“ in der Warnfarbe (gelb, TAtlasTestTally); während eines Laufs (auch im
//   Debugger) „Tests laufen …“. Wurde ein Test seit dem Lauf geändert
//   (tests.stale, #1770), zeigt die Marke den alten Stand grau und kursiv mit
//   „(veraltet)“; die Zählung nimmt veraltete Ergebnisse nicht als bestanden.
//   Mit tests.showDuration (#1772) folgt nach einem Lauf die Dauer („· 12 ms“,
//   an der Klassenmarke die Summe); liegt der langsamste Test der Marke über
//   tests.slowMs, steht „· langsam“ dahinter und die Marke ist gelb, auch wenn
//   er bestand (fehlgeschlagen bleibt rot, veraltet grau).
//   Bestanden mit Leck (tests.leaks, #1774): „· Leck: 40 Bytes“ und gelb wie
//   langsam (Atlas.Core.Tests.Leaks).
//   Nach „N-mal ausführen“ bzw. „In zufälliger Reihenfolge ausführen“
//   (#1782, Atlas.IDE.Tests.Series) steht an der Marke der Serie ihr Ergebnis
//   („20× ausgeführt · 18 bestanden, 2 rot“, gemischt gelb), während der Serie
//   „Tests laufen … 7/20“, bis zum nächsten Lauf.
//   Wackelt ein Test bei unverändertem Rumpf (tests.flaky, #1773),
//   folgt „· wackelt (3 von 10 rot)“ und die Marke ist gelb; die
//   Klassenmarke nennt die Zahl ihrer wackelnden Tests.
//   Hat eine [TestCase]-Methode je Fall eine
//   eigene Zeile, steht an jedem [TestCase] „Fall ausführen“ und die Marke
//   der Methode (alle Fälle) an der Deklaration. Mit „Test debuggen“
//   (TestDebug, #585) folgt je Marke eine zweite: „Debuggen“. Ist der Test
//   mit erwartetem und erhaltenem Wert fehlgeschlagen (tests.compare, #1779),
//   folgt „Vergleichen“. Die Rechtecke werden je Zeile gemerkt.
// - Klick: Linksklick in „Test ausführen“ startet den Test, den Fall bzw. alle
//   Tests der Fixture im Testprojekt der Unit (--run mit den Namen aus
//   Atlas.Text.DUnitX, [TestCase] je Fall); „Debuggen“ startet ihn im
//   Debugger (Atlas.IDE.Tests.Debug); „Vergleichen“ zeigt erwartet und
//   erhalten (Atlas.IDE.Tests.Compare über TAtlasTestCompareHooks), bei
//   Vergleichsdateien als „Abweichung · Vergleich“ (#1881).
// - Ändert sich der Stand der Läufe (TAtlasIdeTests.Version), zeichnet der
//   Zeitgeber den Editor neu.
// Abschaltbar über „Code Lens „Test ausführen““ (codeLens.tests, Schlüssel
// gemeinsam mit #585) und über „Tests ausführen“ (TestRun); ohne sie
// zeichnet die Lens nichts und nimmt keinen Klick an. Die Marke „Debuggen“
// zusätzlich über „Test debuggen“ (TestDebug). An einer Methode mit [TestCase]
// folgt „4 Fälle · 1 rot · Tabelle“ (#1879, tests.testCaseTable); der Klick ruft
// OnTable (TestCase-Tabelle, Atlas.IDE.Tests.CaseTable). Ausblenden am Element (#628):
// je Test über .atlas (Anker Fixture.Methode[.Fall]) oder je Datei.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Tests.Debug,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Lens,
  Atlas.Text.DUnitX,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug;

type
  /// <summary>Tabelle der Testmethode an ALine (0-basiert) von AFileName öffnen (#1879).</summary>
  TAtlasTestsLensTableProc = reference to procedure(const AFileName: string; ALine: Integer);

  /// <summary>Zeichnen der Marken hinter dem Zeilenende (Test-Lens und „getestet von“, #1778).</summary>
  TAtlasIdeLensPill = class
  private const
    /// <summary>Abstand der Marke vom Zeilenende in Zeichen.</summary>
    cGapColumns = 3;
    /// <summary>Anteil der Farbe des Stands an Schrift, Rahmen und Fläche der Marke.</summary>
    cTextMix = 0.85;
    cPenMix = 0.35;
    cBrushMix = 0.12;
    /// <summary>Rundung der Ecken in Punkten.</summary>
    cCorner = 6;
  public
    /// <summary>Schrift der Marke: einen Punkt kleiner, unterstrichen; AItalic für einen veralteten Stand.</summary>
    class procedure Prepare(ACanvas: TCanvas; AItalic: Boolean); static;
    /// <summary>Eine Marke ab ALeft in der Farbe ATone auf dem Hintergrund ABack; liefert ihr Rechteck.</summary>
    class function Draw(ACanvas: TCanvas; const ARow: TRect; const ACaption: string; ATone, ABack: TAtlasColor;
      ALeft: Integer): TRect; static;
    /// <summary>Hintergrundfarbe des Editors an (AX, AY).</summary>
    class function BackgroundAt(ACanvas: TCanvas; AX, AY: Integer): TAtlasColor; static;
    /// <summary>Linker Rand der Marke hinter dem Text der Zeile ALine (Pixel des Editors).</summary>
    class function LeftOf(const AContext: INTACodeEditorPaintContext; const ALine: string): Integer; static;
    /// <summary>APaint mit gesichertem Stift, Pinsel und Schrift der Leinwand; Ausnahmen meldet die Sicherung
    /// (Zeichnen darf die IDE nie stören).</summary>
    class procedure Guarded(ACanvas: TCanvas; const APaint: TProc); static;
  end;

  TAtlasIdeTestsLens = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Eine Marke (Atlas.Core.Tests.Lens), die gezeichneten Rechtecke ihrer Knöpfe und die oberste
    /// sichtbare Zeile dabei.</summary>
    TItem = record
      Mark: TAtlasTestLensMark;
      Rects: TAtlasTestLensRects;
      TopRow: Integer;
    end;
    /// <summary>Lebt, solange die Lens lebt; ein eingereihter Klick prüft es.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private const
    cQuietMs = 400;
    /// <summary>Abstand zwischen zwei Knöpfen einer Marke (Pixel).</summary>
    cPillGap = 6;
  private
    FTests: TAtlasIdeTests;
    FDebugger: TAtlasIdeTestDebugger;
    FCompare: TAtlasTestCompareHooks;
    FAlive: TAlive;
    FAliveRef: IInterface;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FChangedAt: UInt64;
    /// <summary>Stand, zu dem FItems gehört.</summary>
    FScannedFile: string;
    FScannedText: string;
    FUnitName: string;
    /// <summary>Fixtures und Tests des gelesenen Stands, Abfragen und Stand der Tests: veraltet (#1770), wackelt
    /// (#1773).</summary>
    FFound: TDUnitXUnit;
    FQueries: TAtlasTestStateQueries;
    FState: TAtlasTestUnitState;
    FItems: TArray<TItem>;
    FVersion: Integer;
    FShowing: Boolean;
    FOnTable: TAtlasTestsLensTableProc;
    procedure Tick(Sender: TObject);
    procedure Scan;
    /// <summary>Veraltete (#1770) und wackelnde Tests (#1773) des gelesenen Stands neu bestimmen.</summary>
    procedure UpdateStale;
    procedure Clear;
    function ItemAt(ALine: Integer): Integer;
    /// <summary>Beschriftung der Marke und Stand ihrer Tests (Farbe); AWarn: gelb (langsam oder Leck).</summary>
    function Caption(const AMark: TAtlasTestLensMark; out AStatus: TAtlasTestStatus; out AStale,
      AWarn: Boolean): string;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Marke der Zeile von AContext, -1 ohne (Lens aus, andere Datei, Leerzeile, ausgeblendet).</summary>
    function LineItem(const AContext: INTACodeEditorPaintContext; out ALine: string): Integer;
    procedure PaintMarks(AIndex: Integer; const ARow: TRect; const AContext: INTACodeEditorPaintContext;
      ALeft: Integer; ABack: TAtlasColor);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    /// <summary>Marke unter (X, Y) und ihr Knopf AButton. -1 ohne.</summary>
    function HitAt(AX, AY: Integer; out AButton: TAtlasTestLensButton): Integer;
    /// <summary>„Debuggen“ (#585), an einer fehlgeschlagenen Marke (AFailed) „Vergleichen“ (#1779) und an einer
    /// Methode mit [TestCase] „Tabelle“ (#1879) rechts von ALeft.</summary>
    procedure PaintButtons(AIndex: Integer; const ARow: TRect; const AContext: INTACodeEditorPaintContext;
      ALeft: Integer; ABack: TAtlasColor; AFailed: Boolean);
    /// <summary>Gezeichnetes Rechteck ARect der Marke AIndex für das Ausblenden am Element (#628) melden.</summary>
    procedure Painted(AIndex: Integer; const AContext: INTACodeEditorPaintContext; const ARect: TRect;
      ARowHeight: Integer);
    procedure QueueClick(AIndex: Integer; AButton: TAtlasTestLensButton);
  public
    /// <summary>ATests und ADebugger gehören dem Aufrufer und leben länger als die Lens; AQueries nennt die Tests
    /// mit veraltetem Ergebnis (#1770) und die wackelnden (#1773, je nil = keine), ACompare den Knopf
    /// „Vergleichen“ (#1779, leer = keiner).</summary>
    constructor Create(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger; const AQueries: TAtlasTestStateQueries;
      const ACompare: TAtlasTestCompareHooks);
    destructor Destroy; override;
    /// <summary>Lens zeichnen? Einstellungen codeLens.tests und TestRun.</summary>
    class function Wanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Klick auf „Tabelle“ (#1879): Datei und Zeile der Marke; nil = keine Marke „Tabelle“.</summary>
    property OnTable: TAtlasTestsLensTableProc read FOnTable write FOnTable;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.UI.Tests.Strings,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.Text.Lines,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.Core.Diagnostics.Deadline;

/// <summary>Oberen Editor neu zeichnen.</summary>
procedure InvalidateEditor;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

{ TAtlasIdeTestsLens.TEvents }

function TAtlasIdeTestsLens.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeTestsLens.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeTestsLens }

constructor TAtlasIdeTestsLens.Create(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger;
  const AQueries: TAtlasTestStateQueries; const ACompare: TAtlasTestCompareHooks);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FTests := ATests;
  FDebugger := ADebugger;
  FQueries := AQueries;
  FCompare := ACompare;
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FIndex := -1;
  FVersion := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeTestsLens.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  FAlive.Alive := False;
  FAliveRef := nil;
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  FCompare := Default(TAtlasTestCompareHooks);
  FQueries := Default(TAtlasTestStateQueries);
  if FShowing then
  begin
    InvalidateEditor;
  end;
  inherited Destroy;
end;

procedure TAtlasIdeTestsLens.Tick(Sender: TObject);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mText: string;
begin
  try
    if not Wanted(TAtlasIdeSettings.Current) then
    begin
      Clear;
      Exit;
    end;
    mView := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
    begin
      mView := mEditors.TopView;
    end;
    if (mView = nil) or (mView.Buffer = nil) or not SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') then
    begin
      Exit;
    end;
    mText := TAtlasEditorSnapshots.Get(mView).Text;
    if not SameText(FFileName, mView.Buffer.FileName) or (FText <> mText) then
    begin
      FFileName := mView.Buffer.FileName;
      FText := mText;
      FChangedAt := TAtlasTicks.Now;
    end
    else if (TAtlasTicks.Since(FChangedAt) >= cQuietMs) and
      (not SameText(FScannedFile, FFileName) or (FScannedText <> FText)) then
    begin
      Scan;
    end;
    // Lauf begonnen oder beendet: Stand neu zeichnen.
    if FShowing and (FTests.Version <> FVersion) then
    begin
      FVersion := FTests.Version;
      UpdateStale;
      InvalidateEditor;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasIdeTestsLens.UpdateStale;
begin
  FState := Default(TAtlasTestUnitState);
  if (Length(FItems) > 0) and not FTests.Busy then
  begin
    FState := FQueries.StateOf(FFound, TTextLines.SplitLines(FScannedText));
  end;
end;

procedure TAtlasIdeTestsLens.Clear;
begin
  FItems := nil;
  FUnitName := '';
  FFound := Default(TDUnitXUnit);
  FState := Default(TAtlasTestUnitState);
  FScannedFile := '';
  FScannedText := '';
  if FShowing then
  begin
    FShowing := False;
    InvalidateEditor;
  end;
end;

procedure TAtlasIdeTestsLens.Scan;
var
  mFound: TDUnitXUnit;
  mMarks: TArray<TAtlasTestLensMark>;
  mItems: TArray<TItem>;
  mIndex: Integer;
begin
  mFound := TDUnitXSource.Scan(TTextLines.SplitLines(FText));
  mMarks := TAtlasTestLens.Marks(mFound);
  SetLength(mItems, Length(mMarks));
  for mIndex := 0 to High(mMarks) do
  begin
    mItems[mIndex] := Default(TItem);
    mItems[mIndex].Mark := mMarks[mIndex];
  end;
  FScannedFile := FFileName;
  FScannedText := FText;
  FUnitName := mFound.UnitName;
  FFound := mFound;
  if (Length(mItems) = 0) and (Length(FItems) = 0) then
  begin
    Exit;
  end;
  FItems := mItems;
  UpdateStale;
  FShowing := Length(mItems) > 0;
  FVersion := FTests.Version;
  InvalidateEditor;
end;

function TAtlasIdeTestsLens.ItemAt(ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex].Mark.Line = ALine then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasIdeTestsLens.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine: string;
  mIndex: Integer;
  mRow: TRect;
  mContext: INTACodeEditorPaintContext;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FShowing then
  begin
    Exit;
  end;
  mIndex := LineItem(Context, mLine);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mRow := Rect;
  mContext := Context;
  // Auch die Lage der Marke unter der Sicherung: Zeichnen darf die IDE nie stören.
  TAtlasIdeLensPill.Guarded(Context.Canvas,
    procedure
    var
      mLeft: Integer;
    begin
      mLeft := TAtlasIdeLensPill.LeftOf(mContext, mLine);
      PaintMarks(mIndex, mRow, mContext, mLeft, TAtlasIdeLensPill.BackgroundAt(mContext.Canvas, mLeft, mRow.Top + 1));
    end);
end;

/// <summary>Dauer und „langsam“ an der Beschriftung ACaption (#1772, tests.showDuration, tests.slowMs);
/// fehlgeschlagen und veraltet ist nie langsam.</summary>
function DurationCaption(const ACaption: string; const ATally: TAtlasTestTally; AStatus: TAtlasTestStatus;
  out ASlow: Boolean): string;
var
  mTexts: TAtlasTestDurationTexts;
  mSlowMs: Integer;
begin
  ASlow := False;
  if not TAtlasIdeSettings.Current.TestsShowDuration or (AStatus = TAtlasTestStatus.Unknown) then
  begin
    Exit(ACaption);
  end;
  mTexts := Default(TAtlasTestDurationTexts);
  mTexts.Duration := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensDuration);
  mTexts.Slow := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensSlow);
  mTexts.DecimalSeparator := FormatSettings.DecimalSeparator;
  mSlowMs := TAtlasTestLens.SlowLimit(AStatus, ATally.IsStale, TAtlasIdeSettings.Current.TestsSlowMs);
  Result := ATally.WithDuration(ACaption, mSlowMs, mTexts, ASlow);
end;

/// <summary>Ergebnis einer Serie an der Marke (#1782, Haken Series): Beschriftung und Stand (gemischt gelb wie
/// Partial); False ohne Serie für diese Marke.</summary>
function SeriesCaption(const AHooks: TAtlasTestCompareHooks; const ASelection: TAtlasTestSelection;
  out ACaption: string; out AStatus: TAtlasTestStatus): Boolean;
var
  mMark: TAtlasTestSeriesMark;
begin
  AStatus := TAtlasTestStatus.Unknown;
  mMark := Default(TAtlasTestSeriesMark);
  Result := Assigned(AHooks.Series) and AHooks.Series(ASelection, mMark);
  ACaption := mMark.Caption;
  if Result then
  begin
    AStatus := TAtlasTestLens.SeriesStatus(mMark);
  end;
end;

/// <summary>„wackelt (3 von 10 rot)“ bzw. an der Klassenmarke „2 wackeln“ an ACaption (#1773); AWarn wird gelb.
/// Ohne wackelnden Test bleibt ACaption.</summary>
function FlakyCaption(const ACaption: string; const AState: TAtlasTestUnitState; const AUnitName: string;
  const ASelection: TAtlasTestSelection; var AWarn: Boolean): string;
var
  mCount, mFailed, mRuns: Integer;
begin
  Result := ACaption;
  mCount := AState.FlakyCount(AUnitName, ASelection.Fixture, ASelection.Method, mFailed, mRuns);
  if mCount = 0 then
  begin
    Exit;
  end;
  AWarn := True;
  if ASelection.Method <> '' then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensFlaky, [ACaption, mFailed, mRuns]);
  end
  else
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensFlakyFixture, [ACaption, mCount]);
  end;
end;

function TAtlasIdeTestsLens.Caption(const AMark: TAtlasTestLensMark; out AStatus: TAtlasTestStatus;
  out AStale, AWarn: Boolean): string;
const
  cRunTexts: array[TAtlasTestLensKind] of TAtlasTestsTextId = (TAtlasTestsTextId.TestsLensRunFixture,
    TAtlasTestsTextId.TestsLensRunCase, TAtlasTestsTextId.TestsLensRun);
var
  mTally: TAtlasTestTally;
begin
  AStatus := TAtlasTestStatus.Unknown;
  AStale := False;
  AWarn := False;
  // Serie (#1782): während und nach ihr steht ihr Ergebnis an der Marke, bis zum nächsten Lauf.
  if SeriesCaption(FCompare, AMark.Selection, Result, AStatus) then
  begin
    Exit;
  end;
  if FTests.Busy then
  begin
    Exit(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensRunning));
  end;
  Result := TAtlasTestsStrings.Text(cRunTexts[TAtlasTestLens.KindOf(AMark.Selection)]);
  // Nur der Stand der Tests dieser Marke: Ein einzelner Test macht die Fixture nicht „bestanden“.
  // Veraltete Ergebnisse (#1770) zählen nicht als bestanden; der alte Stand bleibt mit „(veraltet)“ sichtbar.
  mTally := FTests.TallyOf(FUnitName, AMark.Selection.Fixture, AMark.Expected,
    TAtlasTestRun.StaleOf(FState.StaleKeys, FUnitName, AMark.Selection.Fixture));
  AStatus := mTally.Shown;
  AStale := mTally.IsStale;
  if AStatus = TAtlasTestStatus.Failed then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensFailed, [Result]);
  end
  else if AStatus = TAtlasTestStatus.Passed then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensPassed, [Result]);
  end
  else if AStatus = TAtlasTestStatus.Partial then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensPartial, [Result, mTally.FreshPassed, mTally.Total]);
  end;
  Result := DurationCaption(Result, mTally, AStatus, AWarn);
  if TAtlasTestLens.ShowsLeak(mTally.Leaked, AStatus) then
  begin
    // Bestanden mit Leck (#1774): gelb wie langsam.
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensLeak, [Result, mTally.LeakBytes]);
    AWarn := True;
  end;
  // Wackelt (#1773): gelb, auch wenn der letzte Lauf rot oder grün war.
  Result := FlakyCaption(Result, FState, FUnitName, AMark.Selection, AWarn);
  if AStale then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensStale, [Result]);
  end;
end;

{ TAtlasIdeLensPill }

class procedure TAtlasIdeLensPill.Prepare(ACanvas: TCanvas; AItalic: Boolean);
begin
  ACanvas.Font.Size := TAtlasTestLens.PillFontSize(ACanvas.Font.Size);
  ACanvas.Font.Style := [fsUnderline];
  if AItalic then
  begin
    ACanvas.Font.Style := [fsUnderline, fsItalic];
  end;
end;

class function TAtlasIdeLensPill.Draw(ACanvas: TCanvas; const ARow: TRect; const ACaption: string; ATone,
  ABack: TAtlasColor; ALeft: Integer): TRect;
begin
  ACanvas.Font.Color := TColor(TAtlasColorMath.Mix(ATone, ABack, cTextMix));
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(ATone, ABack, cPenMix));
  ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(ATone, ABack, cBrushMix));
  Result := TAtlasTestLens.PillRect(ARow, ALeft, ACanvas.TextWidth(ACaption), ACanvas.TextHeight('Xg'));
  ACanvas.Brush.Style := bsSolid;
  ACanvas.RoundRect(Result.Left, Result.Top, Result.Right, Result.Bottom, cCorner, cCorner);
  ACanvas.Brush.Style := bsClear;
  ACanvas.TextOut(Result.Left + TAtlasTestLens.cPillPadding, Result.Top + 1, ACaption);
end;

class function TAtlasIdeLensPill.BackgroundAt(ACanvas: TCanvas; AX, AY: Integer): TAtlasColor;
var
  mSample: COLORREF;
begin
  mSample := GetPixel(ACanvas.Handle, AX, AY);
  if mSample = CLR_INVALID then
  begin
    Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end
  else
  begin
    Result := TAtlasColor(mSample);
  end;
end;

class function TAtlasIdeLensPill.LeftOf(const AContext: INTACodeEditorPaintContext; const ALine: string): Integer;
var
  mColumn: Integer;
begin
  mColumn := Length(TrimRight(TAtlasPairs.DisplayLine(ALine, TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer)))) +
    1;
  Result := AContext.EditorState.GetCharacterPosPx(mColumn + cGapColumns, AContext.EditorLineNum).Left;
end;

class procedure TAtlasIdeLensPill.Guarded(ACanvas: TCanvas; const APaint: TProc);
var
  mOldFont: TFont;
  mOldBrush: TBrush;
  mOldPen: TPen;
begin
  try
    mOldFont := TFont.Create;
    mOldBrush := TBrush.Create;
    mOldPen := TPen.Create;
    try
      mOldFont.Assign(ACanvas.Font);
      mOldBrush.Assign(ACanvas.Brush);
      mOldPen.Assign(ACanvas.Pen);
      APaint();
    finally
      ACanvas.Font.Assign(mOldFont);
      ACanvas.Brush.Assign(mOldBrush);
      ACanvas.Pen.Assign(mOldPen);
      mOldPen.Free;
      mOldBrush.Free;
      mOldFont.Free;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

function TAtlasIdeTestsLens.LineItem(const AContext: INTACodeEditorPaintContext; out ALine: string): Integer;
var
  mLineState: INTACodeEditorLineState;
begin
  ALine := '';
  Result := -1;
  mLineState := AContext.LineState;
  if not Wanted(TAtlasIdeSettings.Current) or not SameText(AContext.FileName, FScannedFile) or
    (mLineState = nil) or (AContext.EditView = nil) or (AContext.EditView.Buffer = nil) then
  begin
    Exit;
  end;
  ALine := mLineState.Text;
  // Text seit dem Lesen verschoben: keine Marke an einer Leerzeile.
  if Trim(ALine) = '' then
  begin
    Exit;
  end;
  Result := ItemAt(AContext.LogicalLineNum - 1);
  // Ausgeblendet am Element (#628): Anker ist Fixture.Methode[.Fall].
  if (Result >= 0) and TAtlasIdeElements.Hidden(TAtlasDrawnElement.CodeLensTests, AContext.FileName,
    FItems[Result].Mark.Selection.Caption) then
  begin
    FItems[Result].Rects := Default(TAtlasTestLensRects);
    Result := -1;
  end;
end;

/// <summary>Beschriftung „4 Fälle · 1 rot · Tabelle“ der Marke einer Methode mit [TestCase] (#1879); '' an
/// Fixture, Fall oder Methode ohne Fälle.</summary>
function CasesCaption(ATests: TAtlasIdeTests; const AUnitName: string; const ASelection: TAtlasTestSelection;
  const AExpected: TArray<TAtlasTestKey>): string;
var
  mCases, mFailed: Integer;
begin
  Result := '';
  mCases := TAtlasTestLens.CaseCount(ASelection, AExpected);
  if mCases = 0 then
  begin
    Exit;
  end;
  Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensCases, [mCases]);
  mFailed := ATests.TallyOf(AUnitName, ASelection.Fixture, AExpected, nil).Failed;
  if mFailed > 0 then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensCasesFailed, [Result, mFailed]);
  end;
  Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLensTable, [Result]);
end;

/// <summary>Text des Knopfs „Vergleichen“ zu ASelection (Vergleichsdateien #1881 mit eigenem Text).</summary>
function CompareCaption(const AHooks: TAtlasTestCompareHooks; const ASelection: TAtlasTestSelection): string;
begin
  if Assigned(AHooks.Caption) then
  begin
    Result := AHooks.Caption(ASelection);
  end
  else
  begin
    Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensCompare);
  end;
end;

procedure TAtlasIdeTestsLens.PaintMarks(AIndex: Integer; const ARow: TRect;
  const AContext: INTACodeEditorPaintContext; ALeft: Integer; ABack: TAtlasColor);
var
  mCanvas: TCanvas;
  mColors: TAtlasColors;
  mTone: TAtlasColor;
  mText: string;
  mStatus: TAtlasTestStatus;
  mStale, mWarn: Boolean;
  mPill: TRect;
begin
  mCanvas := AContext.Canvas;
  mText := Caption(FItems[AIndex].Mark, mStatus, mStale, mWarn);
  mColors := TAtlasColors.ForBackground(ABack);
  // Langsam (#1772) oder Leck (#1774) gelb, auch wenn bestanden; Caption meldet es nie für Fehlschläge.
  mTone := TAtlasTestLens.Tone(mColors, mColors.Accent, mStatus, mWarn, mStale);
  // Veraltet (#1770): alter Stand grau und kursiv.
  TAtlasIdeLensPill.Prepare(mCanvas, mStale);
  mPill := TAtlasIdeLensPill.Draw(mCanvas, ARow, mText, mTone, ABack, ALeft);
  FItems[AIndex].Rects[TAtlasTestLensButton.Run] := mPill;
  // „Debuggen“ (#585) und „Vergleichen“ (#1779, nur fehlgeschlagen und nicht veraltet) rechts daneben.
  PaintButtons(AIndex, ARow, AContext, mPill.Right + cPillGap, ABack, TAtlasTestLens.Comparable(mStatus, mStale));
  FItems[AIndex].TopRow := AContext.EditView.TopRow;
  Painted(AIndex, AContext, mPill, ARow.Height);
  Painted(AIndex, AContext, FItems[AIndex].Rects[TAtlasTestLensButton.Debug], ARow.Height);
  Painted(AIndex, AContext, FItems[AIndex].Rects[TAtlasTestLensButton.Compare], ARow.Height);
  Painted(AIndex, AContext, FItems[AIndex].Rects[TAtlasTestLensButton.Table], ARow.Height);
end;

function TAtlasIdeTestsLens.HitAt(AX, AY: Integer; out AButton: TAtlasTestLensButton): Integer;
var
  mIndex: Integer;
  mButton: TAtlasTestLensButton;
begin
  Result := -1;
  AButton := TAtlasTestLensButton.Run;
  for mIndex := 0 to High(FItems) do
  begin
    if TAtlasTestLens.Hit(FItems[mIndex].Rects, Point(AX, AY), mButton) then
    begin
      Result := mIndex;
      AButton := mButton;
    end;
  end;
end;

procedure TAtlasIdeTestsLens.PaintButtons(AIndex: Integer; const ARow: TRect;
  const AContext: INTACodeEditorPaintContext; ALeft: Integer; ABack: TAtlasColor; AFailed: Boolean);
var
  mAccent: TAtlasColor;
  mLeft: Integer;
  mText: string;
begin
  FItems[AIndex].Rects[TAtlasTestLensButton.Debug] := TRect.Empty;
  FItems[AIndex].Rects[TAtlasTestLensButton.Compare] := TRect.Empty;
  FItems[AIndex].Rects[TAtlasTestLensButton.Table] := TRect.Empty;
  // Nicht während eines Laufs.
  if FTests.Busy then
  begin
    Exit;
  end;
  mAccent := TAtlasColors.ForBackground(ABack).Accent;
  mLeft := ALeft;
  if TAtlasTestDebug.LensDebugWanted(TAtlasIdeSettings.Current) then
  begin
    FItems[AIndex].Rects[TAtlasTestLensButton.Debug] := TAtlasIdeLensPill.Draw(AContext.Canvas, ARow,
      TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensDebug), mAccent, ABack, mLeft);
    mLeft := FItems[AIndex].Rects[TAtlasTestLensButton.Debug].Right + cPillGap;
  end;
  // „Vergleichen“ nur, wenn der Test der Marke erwartet und erhalten hat.
  if AFailed and Assigned(FCompare.CanCompare) and FCompare.CanCompare(FItems[AIndex].Mark.Selection) then
  begin
    FItems[AIndex].Rects[TAtlasTestLensButton.Compare] := TAtlasIdeLensPill.Draw(AContext.Canvas, ARow,
      CompareCaption(FCompare, FItems[AIndex].Mark.Selection), mAccent, ABack, mLeft);
    mLeft := FItems[AIndex].Rects[TAtlasTestLensButton.Compare].Right + cPillGap;
  end;
  // „Tabelle“ (#1879) an einer Methode mit [TestCase].
  mText := '';
  if Assigned(FOnTable) and TAtlasIdeSettings.Current.TestsCaseTable then
  begin
    mText := CasesCaption(FTests, FUnitName, FItems[AIndex].Mark.Selection, FItems[AIndex].Mark.Expected);
  end;
  if mText <> '' then
  begin
    FItems[AIndex].Rects[TAtlasTestLensButton.Table] := TAtlasIdeLensPill.Draw(AContext.Canvas, ARow, mText,
      mAccent, ABack, mLeft);
  end;
end;

procedure TAtlasIdeTestsLens.Painted(AIndex: Integer; const AContext: INTACodeEditorPaintContext;
  const ARect: TRect; ARowHeight: Integer);
begin
  if not ARect.IsEmpty then
  begin
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.CodeLensTests, AContext.FileName,
      FItems[AIndex].Mark.Line, FItems[AIndex].Mark.Selection.Caption), ARect, FItems[AIndex].TopRow, ARowHeight);
  end;
end;

class function TAtlasIdeTestsLens.Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := TAtlasTestDebug.LensWanted(ASettings) and not TAtlasGuard.Disabled(TAtlasFeature.CodeLens);
end;

/// <summary>Zeigt der obere Editor noch AFileName ab der obersten Zeile ATopRow (Marke nicht verschoben)?</summary>
function ShownAt(const AFileName: string; ATopRow: Integer): Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, AFileName) and
    (mView.TopRow = ATopRow);
end;

/// <summary>Handlung des Knopfs AButton an der Marke AMark: ausführen, debuggen, vergleichen oder Tabelle öffnen.
/// </summary>
function ClickAction(AButton: TAtlasTestLensButton; ADebugger: TAtlasIdeTestDebugger;
  const AShow: TAtlasTestSelectionAction; const AOnTable: TAtlasTestsLensTableProc; const AFileName: string;
  const AMark: TAtlasTestLensMark): TProc;
var
  mSelection: TAtlasTestSelection;
  mLine: Integer;
  mFileName: string;
  mDebugger: TAtlasIdeTestDebugger;
  mShow: TAtlasTestSelectionAction;
  mOnTable: TAtlasTestsLensTableProc;
begin
  // Nur Kopien einfangen, keine Parameter.
  mSelection := AMark.Selection;
  mLine := AMark.Line;
  mFileName := AFileName;
  mDebugger := ADebugger;
  mShow := AShow;
  mOnTable := AOnTable;
  case AButton of
    TAtlasTestLensButton.Debug:
      Result :=
        procedure
        begin
          mDebugger.Debug(mFileName, mSelection);
        end;
    TAtlasTestLensButton.Compare:
      Result :=
        procedure
        begin
          if Assigned(mShow) then
          begin
            mShow(mSelection);
          end;
        end;
    TAtlasTestLensButton.Table:
      Result :=
        procedure
        begin
          if Assigned(mOnTable) then
          begin
            mOnTable(mFileName, mLine);
          end;
        end;
  else
    Result :=
      procedure
      begin
        mDebugger.Run(mFileName, mSelection);
      end;
  end;
end;

procedure TAtlasIdeTestsLens.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  mHit: Integer;
  mButton: TAtlasTestLensButton;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FShowing or (FUnitName = '') or
    not Wanted(TAtlasIdeSettings.Current) then
  begin
    Exit;
  end;
  mHit := HitAt(X, Y, mButton);
  // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
  if (mHit >= 0) and ShownAt(FScannedFile, FItems[mHit].TopRow) then
  begin
    QueueClick(mHit, mButton);
  end;
end;

procedure TAtlasIdeTestsLens.QueueClick(AIndex: Integer; AButton: TAtlasTestLensButton);
var
  mAction: TProc;
  mAlive: TAlive;
  mKeep: IInterface;
begin
  mAction := ClickAction(AButton, FDebugger, FCompare.Show, FOnTable, FScannedFile, FItems[AIndex].Mark);
  mAlive := FAlive;
  mKeep := FAliveRef;
  // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor danach; die Tabelle ist modal. Die Lens lebt
  // kürzer als Läufer, Debugger-Teil, Vergleich und Tabelle: Lebt sie noch, leben auch sie.
  TAtlasMainThread.ForceQueue(TAtlasFeature.CodeLens,
    procedure
    begin
      if (mKeep = nil) or not mAlive.Alive then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.Build, mAction);
    end);
end;

end.
