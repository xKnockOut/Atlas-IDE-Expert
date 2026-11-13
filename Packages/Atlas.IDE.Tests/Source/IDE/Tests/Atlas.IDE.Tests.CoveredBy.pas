unit Atlas.IDE.Tests.CoveredBy;

// Marke „getestet von“ (#1778) hinter dem Kopf jeder Methode einer normalen
// Unit: „3 Tests · bestanden“.
// - Fragen: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause
//   fragt er den laufenden Server im Hintergrund (atlas/coveredBy mit dem
//   Text des Editors, Tiefe tests.coveredBy.depth, private Methoden nach
//   tests.coveredBy.private). Testunits (DUnitX-Fixtures, lokal erkannt)
//   fragt er nicht. Ohne laufenden Server versucht er es später erneut.
// - Zeichnen: hinter dem Ende der Kopfzeile der Stand wie bei der Test-Lens
//   (#69, #1762): grün erst, wenn jeder Test bestand, gelb bei Teilstand,
//   rot bei einem Fehlschlag; ohne Test grau „kein Test · Test anlegen“.
//   Stößt der Server an eine Grenze, steht „(unvollständig)“ dabei.
// - Klick: Linksklick führt genau diese Tests aus (--run); ohne Test öffnet
//   bzw. legt er die Testunit an („Zur Testunit wechseln“ von Base).
//   Strg+Klick zeigt die Tests als Liste; ein Eintrag springt zum Test.
// Abschaltbar über codeLens.coveredBy und „Tests ausführen“ (TestRun);
// ausblenden am Element (#628) je Methode (Anker ist ihr Name) oder je Datei.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.CoveredBy,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.CoveredByList;

type
  /// <summary>Scope des Moduls für Serveranfragen; nil, solange es nicht angemeldet ist.</summary>
  TAtlasCoveredByScopeFunc = reference to function: IAtlasModuleScope;

  TAtlasIdeCoveredByLens = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Lebt, solange die Lens lebt; Antwort und eingereihter Klick prüfen es. Generation zählt jede
    /// Anfrage: eine ältere Antwort zählt nicht mehr.</summary>
    TState = class(TInterfacedObject)
    public
      Alive: Boolean;
      Generation: Integer;
    end;

    /// <summary>Zuletzt gefragter Stand: Datei, Text, Tiefe und private Methoden; At für den neuen Versuch ohne
    /// Server (FileName leer).</summary>
    TAsked = record
      FileName: string;
      Text: string;
      Key: string;
      At: UInt64;
    end;
  private
    FTests: TAtlasIdeTests;
    FScopeOf: TAtlasCoveredByScopeFunc;
    FState: TState;
    FStateRef: IInterface;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FList: TAtlasIdeCoveredByList;
    FFileName: string;
    FText: string;
    FChangedAt: UInt64;
    FAsked: TAsked;
    /// <summary>Stand, zu dem FUnit gehört.</summary>
    FShownFile: string;
    FUnit: TAtlasCoveredUnit;
    /// <summary>Gezeichnete Rechtecke je Methode (Koordinaten des Editors) und oberste Zeile dabei.</summary>
    FRects: TArray<TRect>;
    FTopRows: TArray<Integer>;
    FVersion: Integer;
    FShowing: Boolean;
    procedure Tick(Sender: TObject);
    /// <summary>Server fragen, wenn sich Datei, Text oder Einstellungen geändert haben.</summary>
    procedure AskIfChanged(const ASettings: TAtlasPluginSettings);
    procedure Ask(const ASettings: TAtlasPluginSettings);
    procedure Answered(AGeneration: Integer; const AFileName, AJson: string);
    procedure Clear;
    procedure Show(const AFileName: string; const AUnit: TAtlasCoveredUnit);
    function Caption(const AMethod: TAtlasCoveredMethod; out ATone: TAtlasColor; const AColors: TAtlasColors): string;
    function TallyOf(const ATests: TArray<TAtlasCoveredTest>): TAtlasTestTally;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Methode der Zeile von AContext, -1 ohne (Marke aus, andere Datei, Kopf verschoben, ausgeblendet).
    /// </summary>
    function LineMethod(const AContext: INTACodeEditorPaintContext; out ALine: string): Integer;
    procedure PaintAt(AIndex: Integer; const ARow: TRect; const AContext: INTACodeEditorPaintContext;
      const ALine: string);
    procedure PaintMark(AIndex: Integer; const ARow: TRect; const AContext: INTACodeEditorPaintContext;
      ALeft: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    function HitAt(AX, AY: Integer): Integer;
    function StillShown(AIndex: Integer): Boolean;
    procedure QueueClick(AIndex: Integer; AList: Boolean; const AAt: TPoint);
    /// <summary>Klick auf die Marke AMethod (eingereiht, nach dem Mausereignis).</summary>
    procedure Clicked(const AMethod: TAtlasCoveredMethod; AList: Boolean; const AAt: TPoint);
    class procedure Invalidate; static;
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger als die Lens; AScopeOf liefert den Scope des Moduls.
    /// </summary>
    constructor Create(ATests: TAtlasIdeTests; const AScopeOf: TAtlasCoveredByScopeFunc);
    destructor Destroy; override;
    /// <summary>Marken zeichnen? codeLens.coveredBy, TestRun und Code Lens nicht gesperrt.</summary>
    class function Wanted(const ASettings: TAtlasPluginSettings): Boolean; static;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Lsp.Session.Json,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Tests.Lens;

const
  cQuietMs = 800;
  cRetryMs = 5000;
  cTimeoutMs = 20000;
  cTickMs = 250;

{ TAtlasIdeCoveredByLens.TEvents }

function TAtlasIdeCoveredByLens.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeCoveredByLens.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ Hilfen }

function UriToPath(AUri: string): string;
begin
  Result := TLspSessionJson.UriToPath(AUri);
end;

/// <summary>Kurzname der Methode (Bar aus TFoo.Bar): Er muss in der Kopfzeile stehen.</summary>
function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Abbruch der Anfrage: Lens weg oder eine neuere Anfrage gestellt; eigene Routine, damit die Referenz nur
/// AState und AGeneration einfängt.</summary>
function CancelledFor(const AState: IInterface; AGeneration: Integer): TFunc<Boolean>;
var
  mState: IInterface;
  mGeneration: Integer;
begin
  mState := AState;
  mGeneration := AGeneration;
  Result :=
    function: Boolean
    var
      mObject: TObject;
    begin
      mObject := mState as TObject;
      Result := not TAtlasIdeCoveredByLens.TState(mObject).Alive or
        (TAtlasIdeCoveredByLens.TState(mObject).Generation <> mGeneration);
    end;
end;

{ TAtlasIdeCoveredByLens }

constructor TAtlasIdeCoveredByLens.Create(ATests: TAtlasIdeTests; const AScopeOf: TAtlasCoveredByScopeFunc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FTests := ATests;
  FScopeOf := AScopeOf;
  FState := TState.Create;
  FState.Alive := True;
  FStateRef := FState;
  FIndex := -1;
  FVersion := -1;
  FList := TAtlasIdeCoveredByList.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeCoveredByLens.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  FState.Alive := False;
  FStateRef := nil;
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FList.Free;
  if FShowing then
  begin
    Invalidate;
  end;
  inherited Destroy;
end;

class procedure TAtlasIdeCoveredByLens.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class function TAtlasIdeCoveredByLens.Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := TAtlasCoveredBy.Wanted(ASettings) and not TAtlasGuard.Disabled(TAtlasFeature.CodeLens);
end;

procedure TAtlasIdeCoveredByLens.Clear;
begin
  FUnit := Default(TAtlasCoveredUnit);
  FRects := nil;
  FTopRows := nil;
  FShownFile := '';
  if FShowing then
  begin
    FShowing := False;
    Invalidate;
  end;
end;

procedure TAtlasIdeCoveredByLens.Tick(Sender: TObject);
var
  mSettings: TAtlasPluginSettings;
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mText: string;
begin
  try
    mSettings := TAtlasIdeSettings.Current;
    if not Wanted(mSettings) then
    begin
      Inc(FState.Generation);
      FAsked.FileName := '';
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
    else if TAtlasTicks.Since(FChangedAt) >= cQuietMs then
    begin
      AskIfChanged(mSettings);
    end;
    // Lauf begonnen oder beendet: Stand neu zeichnen.
    if FShowing and (FTests.Version <> FVersion) then
    begin
      FVersion := FTests.Version;
      Invalidate;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasIdeCoveredByLens.AskIfChanged(const ASettings: TAtlasPluginSettings);
var
  mKey: string;
begin
  mKey := Format('%d|%s', [ASettings.TestsCoveredByDepth, BoolToStr(ASettings.TestsCoveredByPrivate, True)]);
  if SameText(FAsked.FileName, FFileName) and (FAsked.Text = FText) and (FAsked.Key = mKey) then
  begin
    Exit;
  end;
  // Ohne laufenden Server (FAsked.FileName leer) erst nach einer Pause erneut.
  if (FAsked.FileName = '') and (FAsked.At <> 0) and (TAtlasTicks.Since(FAsked.At) < cRetryMs) then
  begin
    Exit;
  end;
  FAsked.At := TAtlasTicks.Now;
  // Testunits bekommen keine Marken (dort zeigt die Test-Lens den Stand): ohne Anfrage.
  if TAtlasCoveredBy.IsTestUnit(FText) then
  begin
    FAsked.FileName := FFileName;
    FAsked.Text := FText;
    FAsked.Key := mKey;
    Inc(FState.Generation);
    Clear;
    Exit;
  end;
  Ask(ASettings);
  if FAsked.FileName <> '' then
  begin
    FAsked.Key := mKey;
  end;
end;

procedure TAtlasIdeCoveredByLens.Ask(const ASettings: TAtlasPluginSettings);
var
  mGeneration: Integer;
  mFileName: string;
  mSelf: TAtlasIdeCoveredByLens;
  mState: IInterface;
begin
  FAsked.FileName := '';
  if not Assigned(FScopeOf) then
  begin
    Exit;
  end;
  Inc(FState.Generation);
  mGeneration := FState.Generation;
  mFileName := FFileName;
  mSelf := Self;
  mState := FStateRef;
  if TAtlasIdeHost.RunRequestAsync(FScopeOf(), TAtlasFeature.CodeLens,
    TAtlasServerRequest.Create(TAtlasCoveredBy.cMethod,
    TAtlasCoveredBy.Params(TLspSessionJson.PathToUri(mFileName), FText, ASettings.TestsCoveredByDepth,
    ASettings.TestsCoveredByPrivate), cTimeoutMs, CancelledFor(mState, mGeneration)),
    procedure(AJson: string)
    begin
      // Die Lens kann vor der Antwort gehen (Tests ausführen aus): dann nichts mehr anfassen (Regel 3).
      if TState(mState as TObject).Alive then
      begin
        mSelf.Answered(mGeneration, mFileName, AJson);
      end;
    end) then
  begin
    FAsked.FileName := FFileName;
    FAsked.Text := FText;
  end;
end;

procedure TAtlasIdeCoveredByLens.Answered(AGeneration: Integer; const AFileName, AJson: string);
var
  mUnit: TAtlasCoveredUnit;
begin
  if AGeneration <> FState.Generation then
  begin
    Exit;
  end;
  // Keine Antwort (Zeitgrenze, Fehler): lieber keine Marke als eine falsche; der nächste Text fragt neu.
  if (AJson = '') or not TAtlasCoveredBy.FromJson(AJson, UriToPath, mUnit) or mUnit.IsTestUnit then
  begin
    Clear;
    Exit;
  end;
  Show(AFileName, mUnit);
end;

procedure TAtlasIdeCoveredByLens.Show(const AFileName: string; const AUnit: TAtlasCoveredUnit);
begin
  FShownFile := AFileName;
  FUnit := AUnit;
  SetLength(FRects, Length(AUnit.Methods));
  SetLength(FTopRows, Length(AUnit.Methods));
  FShowing := Length(AUnit.Methods) > 0;
  FVersion := FTests.Version;
  Invalidate;
end;

function TAtlasIdeCoveredByLens.TallyOf(const ATests: TArray<TAtlasCoveredTest>): TAtlasTestTally;
var
  mTests: TAtlasIdeTests;
begin
  mTests := FTests;
  Result := TAtlasCoveredBy.TallyOf(ATests,
    function(const AUnitName, AFixture, AMethod: string): TAtlasTestTally
    var
      mKey: TAtlasTestKey;
    begin
      mKey := Default(TAtlasTestKey);
      mKey.Method := AMethod;
      Result := mTests.TallyOf(AUnitName, AFixture, TArray<TAtlasTestKey>.Create(mKey), nil);
    end);
end;

/// <summary>Beschriftung ACount mit dem Stand ATally; ATone wird grün, rot oder gelb, ohne Ergebnis bleibt sie.
/// </summary>
function WithStatus(const ACount: string; const ATally: TAtlasTestTally; var ATone: TAtlasColor;
  const AColors: TAtlasColors): string;
begin
  Result := ACount;
  if ATally.Shown = TAtlasTestStatus.Failed then
  begin
    ATone := AColors.Error;
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoveredByFailed, [ACount]);
  end
  else if ATally.Shown = TAtlasTestStatus.Passed then
  begin
    ATone := AColors.Add;
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoveredByPassed, [ACount]);
  end
  else if ATally.Shown = TAtlasTestStatus.Partial then
  begin
    // Erst ein Teil der Tests lief (#1762): gelb, nicht grün.
    ATone := AColors.Warn;
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoveredByPartial, [ACount, ATally.FreshPassed, ATally.Total]);
  end;
end;

function TAtlasIdeCoveredByLens.Caption(const AMethod: TAtlasCoveredMethod; out ATone: TAtlasColor;
  const AColors: TAtlasColors): string;
begin
  if Length(AMethod.Tests) = 0 then
  begin
    ATone := AColors.Muted;
    Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.CoveredByNone);
  end
  else
  begin
    ATone := AColors.Accent;
    if Length(AMethod.Tests) = 1 then
    begin
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.CoveredByOne);
    end
    else
    begin
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoveredByMany, [Length(AMethod.Tests)]);
    end;
    // Während eines Laufs nur die Zahl: der Stand kommt danach.
    if not FTests.Busy then
    begin
      Result := WithStatus(Result, TallyOf(AMethod.Tests), ATone, AColors);
    end;
  end;
  if FUnit.Incomplete then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoveredByIncomplete, [Result]);
  end;
end;

function TAtlasIdeCoveredByLens.LineMethod(const AContext: INTACodeEditorPaintContext; out ALine: string): Integer;
var
  mLineState: INTACodeEditorLineState;
begin
  ALine := '';
  Result := -1;
  mLineState := AContext.LineState;
  if not Wanted(TAtlasIdeSettings.Current) or not SameText(AContext.FileName, FShownFile) or
    (mLineState = nil) or (AContext.EditView = nil) or (AContext.EditView.Buffer = nil) then
  begin
    Exit;
  end;
  ALine := mLineState.Text;
  Result := FUnit.MethodAt(AContext.LogicalLineNum - 1);
  // Text seit der Antwort verschoben: keine Marke an einer Zeile ohne den Namen der Methode.
  if (Result >= 0) and (Pos(LowerCase(ShortName(FUnit.Methods[Result].Name)), LowerCase(ALine)) = 0) then
  begin
    Result := -1;
  end;
  // Ausgeblendet am Element (#628): Anker ist der Name der Methode.
  if (Result >= 0) and TAtlasIdeElements.Hidden(TAtlasDrawnElement.CodeLensCoveredBy, AContext.FileName,
    FUnit.Methods[Result].Name) then
  begin
    FRects[Result] := TRect.Empty;
    Result := -1;
  end;
end;

procedure TAtlasIdeCoveredByLens.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine: string;
  mIndex: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FShowing then
  begin
    Exit;
  end;
  try
    mIndex := LineMethod(Context, mLine);
    if mIndex >= 0 then
    begin
      PaintAt(mIndex, Rect, Context, mLine);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasIdeCoveredByLens.PaintAt(AIndex: Integer; const ARow: TRect;
  const AContext: INTACodeEditorPaintContext; const ALine: string);
var
  mIndex, mLeft: Integer;
  mRow: TRect;
  mContext: INTACodeEditorPaintContext;
begin
  mIndex := AIndex;
  mRow := ARow;
  mContext := AContext;
  mLeft := TAtlasIdeLensPill.LeftOf(AContext, ALine);
  TAtlasIdeLensPill.Guarded(AContext.Canvas,
    procedure
    begin
      PaintMark(mIndex, mRow, mContext, mLeft);
    end);
end;

procedure TAtlasIdeCoveredByLens.PaintMark(AIndex: Integer; const ARow: TRect;
  const AContext: INTACodeEditorPaintContext; ALeft: Integer);
var
  mCanvas: TCanvas;
  mBack, mTone: TAtlasColor;
  mText: string;
begin
  mCanvas := AContext.Canvas;
  mBack := TAtlasIdeLensPill.BackgroundAt(mCanvas, ALeft, ARow.Top + 1);
  mText := Caption(FUnit.Methods[AIndex], mTone, TAtlasColors.ForBackground(mBack));
  TAtlasIdeLensPill.Prepare(mCanvas, False);
  FRects[AIndex] := TAtlasIdeLensPill.Draw(mCanvas, ARow, mText, mTone, mBack, ALeft);
  FTopRows[AIndex] := AContext.EditView.TopRow;
  TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.CodeLensCoveredBy, AContext.FileName,
    FUnit.Methods[AIndex].Line, FUnit.Methods[AIndex].Name), FRects[AIndex], FTopRows[AIndex], ARow.Height);
end;

function TAtlasIdeCoveredByLens.HitAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRects) do
  begin
    if not FRects[mIndex].IsEmpty and PtInRect(FRects[mIndex], Point(AX, AY)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasIdeCoveredByLens.StillShown(AIndex: Integer): Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, FShownFile) and
    (mView.TopRow = FTopRows[AIndex]);
end;

procedure TAtlasIdeCoveredByLens.QueueClick(AIndex: Integer; AList: Boolean; const AAt: TPoint);
var
  mMethod: TAtlasCoveredMethod;
  mSelf: TAtlasIdeCoveredByLens;
  mState: IInterface;
  mList: Boolean;
  mAt: TPoint;
begin
  mMethod := FUnit.Methods[AIndex];
  mSelf := Self;
  mState := FStateRef;
  mList := AList;
  mAt := AAt;
  // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor danach.
  TAtlasMainThread.ForceQueue(TAtlasFeature.CodeLens,
    procedure
    begin
      if TState(mState as TObject).Alive then
      begin
        mSelf.Clicked(mMethod, mList, mAt);
      end;
    end);
end;

procedure TAtlasIdeCoveredByLens.Clicked(const AMethod: TAtlasCoveredMethod; AList: Boolean; const AAt: TPoint);
var
  mTests: TAtlasIdeTests;
  mFileName: string;
  mNames: TArray<string>;
begin
  if Length(AMethod.Tests) = 0 then
  begin
    // Kein Test: Testunit öffnen bzw. anlegen wie „Zur Testunit wechseln“.
    TAtlasIdeHost.ExecuteCommand('Atlas.SwitchTestUnit');
  end
  else if AList then
  begin
    FList.Show(AMethod.Tests, AAt);
  end
  else
  begin
    mTests := FTests;
    mFileName := AMethod.Tests[0].FileName;
    mNames := TAtlasCoveredBy.RunNames(AMethod.Tests);
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        mTests.RunTests(mFileName, mNames);
      end);
  end;
end;

procedure TAtlasIdeCoveredByLens.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  mHit: Integer;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssAlt] <> []) or not FShowing or
    not Wanted(TAtlasIdeSettings.Current) then
  begin
    Exit;
  end;
  mHit := HitAt(X, Y);
  // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
  if (mHit >= 0) and StillShown(mHit) then
  begin
    QueueClick(mHit, ssCtrl in Shift, Editor.ClientToScreen(Point(X, Y)));
  end;
end;

end.
