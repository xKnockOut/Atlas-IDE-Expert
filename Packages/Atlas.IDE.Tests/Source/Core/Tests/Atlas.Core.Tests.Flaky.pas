unit Atlas.Core.Tests.Flaky;

// Wackelnde Tests (#1773, tests.flaky), ohne VCL und Open Tools API, auch
// unter FPC prüfbar:
// - Verlauf: Je Test (Schlüssel Unit.Fixture.Methode klein, wie
//   TAtlasTestStamps.KeyOf) merkt sich das Modul die letzten
//   tests.flaky.runs Ergebnisse (bestanden oder fehlgeschlagen) mit der
//   Prüfsumme des Methodenrumpfs (#1770) und der ersten Fehlermeldung. Ein
//   Test mit [TestCase] gilt in einem Lauf als fehlgeschlagen, wenn einer
//   seiner Fälle fehlschlug; nur übersprungen zählt nicht.
// - Wackelt: Unter den Ergebnissen mit der Prüfsumme des Rumpfs von jetzt
//   gibt es grün, danach rot, danach wieder grün (Wobbles). Ein Test, der rot
//   war und nach einer Änderung am Rumpf grün ist, wackelt also nicht.
// - Ablage: je Testprojekt eine JSON-Datei (Format 1, UTF-8 ohne BOM, Zeiten
//   in UTC wie die Projekt-Zusammenfassung):
//     {"format": 1, "project": "C:\\Projekte\\Demo.Tests.dproj",
//      "tests": [{"test": "demo.tests.trechner.summe",
//                 "runs": [{"at": "…", "body": "…", "passed": false,
//                           "message": "…"}, …]}, …]}
//   Die Runden stehen älteste zuerst; die Meldung nur bei rot.

interface

uses
  System.Generics.Collections,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Stale;

type
  /// <summary>Ergebnis eines Tests in einem Lauf.</summary>
  TAtlasTestRunMark = record
    AtUtc: TDateTime;
    /// <summary>Prüfsumme des Methodenrumpfs beim Lauf (TAtlasTestStamps.BodyOf); '' ohne Rumpf.</summary>
    Body: string;
    Passed: Boolean;
    /// <summary>Erste Fehlermeldung eines roten Laufs; '' bei grün.</summary>
    Message: string;
  end;

  /// <summary>Ein Test und seine Ergebnisse mit der Prüfsumme von jetzt.</summary>
  TAtlasFlakyTest = record
    /// <summary>Schlüssel des Tests (TAtlasTestStamps.KeyOf).</summary>
    Key: string;
    /// <summary>Ergebnisse mit gleicher Prüfsumme, älteste zuerst (True = grün).</summary>
    Results: TArray<Boolean>;
    /// <summary>Davon rot.</summary>
    Failed: Integer;
    /// <summary>Erster gemerkter Lauf mit dieser Prüfsumme: seitdem ist der Rumpf unverändert.</summary>
    SinceUtc: TDateTime;
    /// <summary>Meldung des letzten roten Laufs.</summary>
    LastMessage: string;
    function Runs: Integer;
  end;

  /// <summary>Wackelnde Tests der Unit AUnit mit den Rümpfen aus ALines (Abfrage der Testlinse und des Fensters
  /// „Atlas-Tests“).</summary>
  TAtlasTestFlakyFunc = reference to function(const AUnit: TDUnitXUnit;
    const ALines: TArray<string>): TArray<TAtlasFlakyTest>;

  /// <summary>Stand der Tests einer Unit für Testlinse und Fenster: Schlüssel der Tests mit veraltetem Ergebnis
  /// (#1770) und wackelnde Tests (#1773).</summary>
  TAtlasTestUnitState = record
    StaleKeys: TArray<string>;
    Flaky: TArray<TAtlasFlakyTest>;
    /// <summary>Wackelnde Tests einer Marke: Test AMethod der Fixture AFixture, bei AMethod '' alle Tests der
    /// Fixture. Bei einem Test stehen seine roten und alle Läufe in AFailed und ARuns.</summary>
    function FlakyCount(const AUnitName, AFixture, AMethod: string; out AFailed, ARuns: Integer): Integer;
  end;

  /// <summary>Abfragen des Stands; nil = keine.</summary>
  TAtlasTestStateQueries = record
    StaleKeys: TAtlasTestStaleKeys;
    Flaky: TAtlasTestFlakyFunc;
    /// <summary>Stand der Unit AUnit mit dem Text ALines.</summary>
    function StateOf(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TAtlasTestUnitState;
  end;

  TAtlasTestHistory = class
  public const
    cFormat = 1;
    /// <summary>Grenzen und Vorgabe wie tests.flaky.runs (Atlas.Core.Settings.Plugin.Build).</summary>
    cMinRuns = 3;
    cMaxRuns = 50;
    cDefaultRuns = 10;
  private
    FMarks: TDictionary<string, TArray<TAtlasTestRunMark>>;
    FMaxRuns: Integer;
    procedure SetMaxRuns(AValue: Integer);
    function Trimmed(const AMarks: TArray<TAtlasTestRunMark>): TArray<TAtlasTestRunMark>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Wechselt AResults (älteste zuerst) grün → rot → grün?</summary>
    class function Wobbles(const AResults: TArray<Boolean>): Boolean; static;
    /// <summary>Ergebnisse als Punktreihe, älteste zuerst: APassed je grünem, AFailed je rotem Lauf.</summary>
    class function Dots(const AResults: TArray<Boolean>; APassed, AFailed: Char): string; static;
    /// <summary>Ein Ergebnis anhängen; ältere über MaxRuns fallen weg.</summary>
    procedure Add(const AKey: string; const AMark: TAtlasTestRunMark);
    /// <summary>Ergebnisse des Laufs ACases zu den Tests der Unit AUnit (Text ALines) merken; liefert die
    /// Schlüssel der gemerkten Tests.</summary>
    function Remember(const AUnit: TDUnitXUnit; const ALines: TArray<string>; const ACases: TArray<TTestCaseResult>;
      AAtUtc: TDateTime): TArray<string>;
    /// <summary>Ergebnisse von AKey mit der Prüfsumme ABody; False ohne.</summary>
    function Check(const AKey, ABody: string; out ATest: TAtlasFlakyTest): Boolean;
    /// <summary>Wackelt AKey mit der Prüfsumme ABody?</summary>
    function IsFlaky(const AKey, ABody: string; out ATest: TAtlasFlakyTest): Boolean;
    /// <summary>Wackelnde Tests der Unit AUnit mit den Rümpfen aus ALines.</summary>
    function FlakyIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<TAtlasFlakyTest>;
    /// <summary>Bestand AKey zuletzt, war davor mit derselben Prüfsumme rot und wackelt („bestanden, wackelt
    /// aber“)?</summary>
    function PassedButFlaky(const AKey: string; out ATest: TAtlasFlakyTest): Boolean;
    /// <summary>Gemerkte Ergebnisse von AKey, älteste zuerst.</summary>
    function MarksOf(const AKey: string): TArray<TAtlasTestRunMark>;
    function Count: Integer;
    procedure Clear;
    /// <summary>Verlauf als JSON (Format oben) für das Testprojekt AProject, Tests nach Schlüssel sortiert.
    /// </summary>
    function ToJson(const AProject: string): string;
    /// <summary>Liest AJson und ersetzt den Verlauf. False bei ungültigem Inhalt oder höherem Format; der Verlauf
    /// bleibt dann leer. Unbrauchbare Einträge fallen weg.</summary>
    function LoadJson(const AJson: string): Boolean;
    /// <summary>Höchstens so viele Ergebnisse je Test (cMinRuns bis cMaxRuns).</summary>
    property MaxRuns: Integer read FMaxRuns write SetMaxRuns;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Core.Projects.Summary.Json;

{ TAtlasFlakyTest }

function TAtlasFlakyTest.Runs: Integer;
begin
  Result := Length(Results);
end;

{ TAtlasTestUnitState }

function TAtlasTestUnitState.FlakyCount(const AUnitName, AFixture, AMethod: string; out AFailed,
  ARuns: Integer): Integer;
var
  mKey: string;
  mFlaky: TAtlasFlakyTest;
begin
  // Schlüssel des Tests bzw. bei der Fixture der gemeinsame Anfang „unit.fixture.“ ihrer Tests.
  mKey := TAtlasTestStamps.KeyOf(AUnitName, AFixture, AMethod);
  Result := 0;
  AFailed := 0;
  ARuns := 0;
  for mFlaky in Flaky do
  begin
    if (mFlaky.Key = mKey) or ((AMethod = '') and (Copy(mFlaky.Key, 1, Length(mKey)) = mKey)) then
    begin
      Inc(Result);
      AFailed := mFlaky.Failed;
      ARuns := mFlaky.Runs;
    end;
  end;
end;

{ TAtlasTestStateQueries }

function TAtlasTestStateQueries.StateOf(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TAtlasTestUnitState;
begin
  Result := Default(TAtlasTestUnitState);
  if Assigned(StaleKeys) then
  begin
    Result.StaleKeys := StaleKeys(AUnit, ALines);
  end;
  if Assigned(Flaky) then
  begin
    Result.Flaky := Flaky(AUnit, ALines);
  end;
end;

/// <summary>Ergebnis des Tests AKey in ACases: grün, wenn ein Fall bestand und keiner fehlschlug; rot mit der
/// ersten Meldung, wenn einer fehlschlug. False, wenn der Lauf ihn nicht (oder nur übersprungen) enthielt.</summary>
function OutcomeOf(const ACases: TArray<TTestCaseResult>; const AKey: string; out APassed: Boolean;
  out AMessage: string): Boolean;
var
  mCase: TTestCaseResult;
  mFailed, mPassed: Boolean;
begin
  mFailed := False;
  mPassed := False;
  AMessage := '';
  for mCase in ACases do
  begin
    if TAtlasTestStamps.KeyOf(mCase.UnitName, mCase.Fixture, mCase.Method) <> AKey then
    begin
      Continue;
    end;
    if mCase.IsFailure and not mFailed then
    begin
      mFailed := True;
      AMessage := mCase.Message;
    end;
    mPassed := mPassed or (mCase.Outcome = TTestOutcome.Passed);
  end;
  APassed := mPassed and not mFailed;
  Result := mPassed or mFailed;
end;

{ TAtlasTestHistory }

constructor TAtlasTestHistory.Create;
begin
  inherited Create;
  FMarks := TDictionary<string, TArray<TAtlasTestRunMark>>.Create;
  FMaxRuns := cDefaultRuns;
end;

destructor TAtlasTestHistory.Destroy;
begin
  FMarks.Free;
  inherited Destroy;
end;

procedure TAtlasTestHistory.SetMaxRuns(AValue: Integer);
var
  mKeys: TArray<string>;
  mKey: string;
begin
  FMaxRuns := EnsureRange(AValue, cMinRuns, cMaxRuns);
  mKeys := FMarks.Keys.ToArray;
  for mKey in mKeys do
  begin
    FMarks[mKey] := Trimmed(FMarks[mKey]);
  end;
end;

function TAtlasTestHistory.Trimmed(const AMarks: TArray<TAtlasTestRunMark>): TArray<TAtlasTestRunMark>;
begin
  Result := AMarks;
  if Length(Result) > FMaxRuns then
  begin
    Result := Copy(AMarks, Length(AMarks) - FMaxRuns, FMaxRuns);
  end;
end;

class function TAtlasTestHistory.Wobbles(const AResults: TArray<Boolean>): Boolean;
var
  mStep: Integer;
  mResult: Boolean;
begin
  // Gesucht: grün, irgendwann danach rot, irgendwann danach wieder grün.
  mStep := 0;
  for mResult in AResults do
  begin
    if (mStep = 0) and mResult then
    begin
      mStep := 1;
    end
    else if (mStep = 1) and not mResult then
    begin
      mStep := 2;
    end
    else if (mStep = 2) and mResult then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTestHistory.Dots(const AResults: TArray<Boolean>; APassed, AFailed: Char): string;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AResults));
  for mIndex := 0 to High(AResults) do
  begin
    Result[mIndex + 1] := AFailed;
    if AResults[mIndex] then
    begin
      Result[mIndex + 1] := APassed;
    end;
  end;
end;

procedure TAtlasTestHistory.Add(const AKey: string; const AMark: TAtlasTestRunMark);
var
  mMarks: TArray<TAtlasTestRunMark>;
begin
  if not FMarks.TryGetValue(AKey, mMarks) then
  begin
    mMarks := nil;
  end;
  SetLength(mMarks, Length(mMarks) + 1);
  mMarks[High(mMarks)] := AMark;
  FMarks.AddOrSetValue(AKey, Trimmed(mMarks));
end;

function TAtlasTestHistory.Remember(const AUnit: TDUnitXUnit; const ALines: TArray<string>;
  const ACases: TArray<TTestCaseResult>; AAtUtc: TDateTime): TArray<string>;
var
  mFixture, mTest: Integer;
  mKey: string;
  mMark: TAtlasTestRunMark;
begin
  Result := nil;
  for mFixture := 0 to High(AUnit.Fixtures) do
  begin
    for mTest := 0 to High(AUnit.Fixtures[mFixture].Tests) do
    begin
      mKey := TAtlasTestStamps.KeyOf(AUnit.UnitName, AUnit.Fixtures[mFixture].Name,
        AUnit.Fixtures[mFixture].Tests[mTest].Method);
      mMark := Default(TAtlasTestRunMark);
      if not OutcomeOf(ACases, mKey, mMark.Passed, mMark.Message) then
      begin
        Continue;
      end;
      mMark.AtUtc := AAtUtc;
      mMark.Body := TAtlasTestStamps.BodyOf(AUnit, ALines, mFixture, mTest);
      Add(mKey, mMark);
      Result := Result + [mKey];
    end;
  end;
end;

function TAtlasTestHistory.MarksOf(const AKey: string): TArray<TAtlasTestRunMark>;
begin
  if not FMarks.TryGetValue(AKey, Result) then
  begin
    Result := nil;
  end;
end;

function TAtlasTestHistory.Check(const AKey, ABody: string; out ATest: TAtlasFlakyTest): Boolean;
var
  mMark: TAtlasTestRunMark;
begin
  ATest := Default(TAtlasFlakyTest);
  ATest.Key := AKey;
  for mMark in MarksOf(AKey) do
  begin
    if mMark.Body <> ABody then
    begin
      Continue;
    end;
    if Length(ATest.Results) = 0 then
    begin
      ATest.SinceUtc := mMark.AtUtc;
    end;
    ATest.Results := ATest.Results + [mMark.Passed];
    if not mMark.Passed then
    begin
      Inc(ATest.Failed);
      ATest.LastMessage := mMark.Message;
    end;
  end;
  Result := Length(ATest.Results) > 0;
end;

function TAtlasTestHistory.IsFlaky(const AKey, ABody: string; out ATest: TAtlasFlakyTest): Boolean;
begin
  Result := Check(AKey, ABody, ATest) and Wobbles(ATest.Results);
end;

function TAtlasTestHistory.FlakyIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<TAtlasFlakyTest>;
var
  mFixture, mTest: Integer;
  mKey: string;
  mFlaky: TAtlasFlakyTest;
begin
  Result := nil;
  if FMarks.Count = 0 then
  begin
    Exit;
  end;
  for mFixture := 0 to High(AUnit.Fixtures) do
  begin
    for mTest := 0 to High(AUnit.Fixtures[mFixture].Tests) do
    begin
      mKey := TAtlasTestStamps.KeyOf(AUnit.UnitName, AUnit.Fixtures[mFixture].Name,
        AUnit.Fixtures[mFixture].Tests[mTest].Method);
      if FMarks.ContainsKey(mKey) and IsFlaky(mKey, TAtlasTestStamps.BodyOf(AUnit, ALines, mFixture, mTest),
        mFlaky) then
      begin
        Result := Result + [mFlaky];
      end;
    end;
  end;
end;

function TAtlasTestHistory.PassedButFlaky(const AKey: string; out ATest: TAtlasFlakyTest): Boolean;
var
  mMarks: TArray<TAtlasTestRunMark>;
  mLast: TAtlasTestRunMark;
  mIndex: Integer;
begin
  ATest := Default(TAtlasFlakyTest);
  mMarks := MarksOf(AKey);
  if (Length(mMarks) < 2) or not mMarks[High(mMarks)].Passed then
  begin
    Exit(False);
  end;
  mLast := mMarks[High(mMarks)];
  // Der Lauf davor mit demselben Rumpf muss rot gewesen sein: sonst ist „bestanden“ nichts Neues.
  Result := False;
  for mIndex := High(mMarks) - 1 downto 0 do
  begin
    if mMarks[mIndex].Body = mLast.Body then
    begin
      Result := not mMarks[mIndex].Passed;
      Break;
    end;
  end;
  Result := Result and IsFlaky(AKey, mLast.Body, ATest);
end;

function TAtlasTestHistory.Count: Integer;
begin
  Result := FMarks.Count;
end;

procedure TAtlasTestHistory.Clear;
begin
  FMarks.Clear;
end;

/// <summary>Ein Ergebnis als JSON-Objekt.</summary>
function MarkJson(const AMark: TAtlasTestRunMark): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', AMark.AtUtc);
  Result.AddPair('body', AMark.Body);
  Result.AddPair('passed', TJSONBool.Create(AMark.Passed));
  if AMark.Message <> '' then
  begin
    Result.AddPair('message', AMark.Message);
  end;
end;

function TAtlasTestHistory.ToJson(const AProject: string): string;
var
  mRoot, mTest: TJSONObject;
  mTests, mRuns: TJSONArray;
  mKeys: TArray<string>;
  mKey: string;
  mMark: TAtlasTestRunMark;
begin
  mKeys := FMarks.Keys.ToArray;
  // Schlüssel sind eindeutig: Die Reihenfolge ist auch ohne stabile Sortierung fest.
  TArray.Sort<string>(mKeys);
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('project', AProject);
    mTests := TJSONArray.Create;
    mRoot.AddPair('tests', mTests);
    for mKey in mKeys do
    begin
      mTest := TJSONObject.Create;
      mTests.AddElement(mTest);
      mTest.AddPair('test', mKey);
      mRuns := TJSONArray.Create;
      mTest.AddPair('runs', mRuns);
      for mMark in FMarks[mKey] do
      begin
        mRuns.AddElement(MarkJson(mMark));
      end;
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

/// <summary>Ergebnisse eines Tests aus dem Feld "runs"; Einträge ohne "passed" fallen weg.</summary>
function MarksJson(ARuns: TJSONArray): TArray<TAtlasTestRunMark>;
var
  mItem: TJSONValue;
  mRun: TJSONObject;
  mMark: TAtlasTestRunMark;
begin
  Result := nil;
  if ARuns = nil then
  begin
    Exit;
  end;
  for mItem in ARuns do
  begin
    mRun := TJsonRead.AsObject(mItem);
    if (mRun = nil) or (TJsonRead.Value(mRun, 'passed') = nil) then
    begin
      Continue;
    end;
    mMark := Default(TAtlasTestRunMark);
    mMark.AtUtc := SummaryTimeOf(TJsonRead.Text(mRun, 'at'));
    mMark.Body := TJsonRead.Text(mRun, 'body');
    mMark.Passed := TJsonRead.Flag(mRun, 'passed');
    mMark.Message := TJsonRead.Text(mRun, 'message');
    Result := Result + [mMark];
  end;
end;

function TAtlasTestHistory.LoadJson(const AJson: string): Boolean;
var
  mRoot, mTest: TJSONObject;
  mTests: TJSONArray;
  mItem: TJSONValue;
  mKey: string;
  mMarks: TArray<TAtlasTestRunMark>;
begin
  FMarks.Clear;
  mRoot := TJsonRead.ParseObject(AJson);
  if mRoot = nil then
  begin
    Exit(False);
  end;
  try
    if TJsonRead.IntOr(mRoot, 'format', 0) <> cFormat then
    begin
      Exit(False);
    end;
    mTests := TJsonRead.Items(mRoot, 'tests');
    if mTests <> nil then
    begin
      for mItem in mTests do
      begin
        mTest := TJsonRead.AsObject(mItem);
        mKey := AnsiLowerCase(TJsonRead.Text(mTest, 'test'));
        mMarks := Trimmed(MarksJson(TJsonRead.Items(mTest, 'runs')));
        if (mKey <> '') and (Length(mMarks) > 0) then
        begin
          FMarks.AddOrSetValue(mKey, mMarks);
        end;
      end;
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

end.
