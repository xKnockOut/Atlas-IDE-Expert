unit Atlas.Core.Debug.StepFilter.Tests;

// Tests für den Kern der Schrittfilter (#850) ohne IDE: Antworten lesen,
// Urteil aus Arten und Mustern, Ablauf F7 → „Bis zur Rückkehr“ → erneut
// hineinspringen, Haltepunkt in der gefilterten Routine, Zwischenspeicher.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.StepFilter;

type
  [TestFixture]
  TAtlasStepFilterTests = class
  private
    function Routine(const AName: string; const AKinds: string): TAtlasStepRoutine;
  public
    [Test]
    procedure ReadsRoutineAnswer;
    [Test]
    procedure ReadsMissingRoutineAndForeignFormat;
    [Test]
    procedure ReadsCountsWithMissingPatterns;
    [Test]
    procedure ArgumentsAsJson;
    [Test]
    procedure VerdictKindBeforePattern;
    [Test]
    procedure VerdictPatternWhenKindOff;
    [Test]
    procedure VerdictOffOrNotFound;
    [Test]
    procedure AcceptanceTrivialGetterSkippedThenStepsOn;
    [Test]
    procedure SameDepthIsNoNewRoutine;
    [Test]
    procedure BreakpointInsideSkippedRoutineKeepsStop;
    [Test]
    procedure RoutineEndsDuringReturn;
    [Test]
    procedure NotFilteredKeepsStop;
    [Test]
    procedure StopsAfterMaxSkips;
    [Test]
    procedure CacheByFileAndLine;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.StepFilter;

{ TAtlasStepFilterTests }

function TAtlasStepFilterTests.Routine(const AName: string; const AKinds: string): TAtlasStepRoutine;
begin
  Result := Default(TAtlasStepRoutine);
  Result.Found := True;
  Result.Name := AName;
  Result.Kinds := TStepFilterNames.ParseKinds(AKinds);
end;

procedure TAtlasStepFilterTests.ReadsRoutineAnswer;
var
  mJson: TJSONValue;
  mRoutine: TAtlasStepRoutine;
begin
  mJson := TJSONObject.ParseJSONValue('{"format": 1, "found": true, "name": "Kunden.TKunde.GetName", ' +
    '"container": "TKunde", "routine": "GetName", "startLine": 30, "endLine": 33, ' +
    '"kinds": ["getters", "unbekannt", "trivial"]}');
  try
    Assert.IsTrue(TAtlasStepFilter.ReadRoutine(mJson, mRoutine));
    Assert.IsTrue(mRoutine.Found);
    Assert.AreEqual('Kunden.TKunde.GetName', mRoutine.Name);
    Assert.AreEqual('TKunde', mRoutine.Container);
    Assert.AreEqual('GetName', mRoutine.Routine);
    Assert.AreEqual(30, mRoutine.StartLine);
    Assert.AreEqual(33, mRoutine.EndLine);
    Assert.AreEqual('getters,trivial', TStepFilterNames.KindsText(mRoutine.Kinds));
  finally
    mJson.Free;
  end;
end;

procedure TAtlasStepFilterTests.ReadsMissingRoutineAndForeignFormat;
var
  mJson: TJSONValue;
  mRoutine: TAtlasStepRoutine;
begin
  mJson := TJSONObject.ParseJSONValue('{"format": 1, "found": false}');
  try
    Assert.IsTrue(TAtlasStepFilter.ReadRoutine(mJson, mRoutine));
    Assert.IsFalse(mRoutine.Found);
    Assert.AreEqual(-1, mRoutine.StartLine);
  finally
    mJson.Free;
  end;
  mJson := TJSONObject.ParseJSONValue('{"format": 2, "found": true, "name": "A.B"}');
  try
    Assert.IsFalse(TAtlasStepFilter.ReadRoutine(mJson, mRoutine));
  finally
    mJson.Free;
  end;
  Assert.IsFalse(TAtlasStepFilter.ReadRoutine(nil, mRoutine));
end;

procedure TAtlasStepFilterTests.ReadsCountsWithMissingPatterns;
var
  mJson: TJSONValue;
  mCounts: TAtlasStepCounts;
begin
  mJson := TJSONObject.ParseJSONValue('{"format": 1, "files": 12, "routines": 340, "truncated": true, ' +
    '"kinds": {"getters": 41, "trivial": 7}, "patterns": [3]}');
  try
    Assert.IsTrue(TAtlasStepFilter.ReadCounts(mJson, 2, mCounts));
    Assert.AreEqual(12, mCounts.Files);
    Assert.AreEqual(340, mCounts.Routines);
    Assert.IsTrue(mCounts.Truncated);
    Assert.AreEqual(41, mCounts.Kinds[TStepFilterKind.Getters]);
    Assert.AreEqual(0, mCounts.Kinds[TStepFilterKind.Setters]);
    Assert.AreEqual(7, mCounts.Kinds[TStepFilterKind.Trivial]);
    Assert.AreEqual(2, Integer(Length(mCounts.Patterns)));
    Assert.AreEqual(3, mCounts.Patterns[0]);
    Assert.AreEqual(0, mCounts.Patterns[1]);
  finally
    mJson.Free;
  end;
end;

procedure TAtlasStepFilterTests.ArgumentsAsJson;
begin
  Assert.AreEqual('["file:///C:/P/Kunden.pas",30]', TAtlasStepFilter.Arguments('file:///C:/P/Kunden.pas', 30));
  Assert.AreEqual('[["*.Log*","TBasisForm.*"]]',
    TAtlasStepFilter.CountsArguments(TArray<string>.Create('*.Log*', 'TBasisForm.*')));
  Assert.AreEqual('[[]]', TAtlasStepFilter.CountsArguments(nil));
end;

procedure TAtlasStepFilterTests.VerdictKindBeforePattern;
var
  mOptions: TAtlasStepFilterOptions;
  mVerdict: TAtlasStepVerdict;
begin
  mOptions := TAtlasStepFilterOptions.Create(True, 'getters,trivial', '*.Get*');
  mVerdict := TAtlasStepFilter.Verdict(mOptions, Routine('Kunden.TKunde.GetName', 'trivial,getters'));
  Assert.IsTrue(mVerdict.Filtered);
  Assert.AreEqual(Ord(TAtlasStepVerdictKind.Kind), Ord(mVerdict.Kind));
  Assert.AreEqual(Ord(TStepFilterKind.Getters), Ord(mVerdict.FilterKind), 'feste Reihenfolge');
end;

procedure TAtlasStepFilterTests.VerdictPatternWhenKindOff;
var
  mOptions: TAtlasStepFilterOptions;
  mVerdict: TAtlasStepVerdict;
begin
  mOptions := TAtlasStepFilterOptions.Create(True, 'operators', 'TBasisForm.*;*.Log*');
  mVerdict := TAtlasStepFilter.Verdict(mOptions, Routine('Protokoll.TProtokoll.LogInfo', ''));
  Assert.AreEqual(Ord(TAtlasStepVerdictKind.Pattern), Ord(mVerdict.Kind));
  Assert.AreEqual('*.Log*', mVerdict.Pattern);
  mVerdict := TAtlasStepFilter.Verdict(mOptions, Routine('Kunden.TKunde.GetTitel', 'getters'));
  Assert.IsFalse(mVerdict.Filtered, 'Getter ist nicht gewählt');
end;

procedure TAtlasStepFilterTests.VerdictOffOrNotFound;
var
  mOptions: TAtlasStepFilterOptions;
  mRoutine: TAtlasStepRoutine;
begin
  mOptions := TAtlasStepFilterOptions.Create(False, 'getters,trivial', '*');
  Assert.IsFalse(TAtlasStepFilter.Verdict(mOptions, Routine('Kunden.TKunde.GetName', 'getters')).Filtered);
  mOptions := TAtlasStepFilterOptions.Create(True, 'getters,trivial', 'Kunden.*');
  mRoutine := Routine('Kunden.TKunde.GetName', 'getters');
  mRoutine.Found := False;
  Assert.IsFalse(TAtlasStepFilter.Verdict(mOptions, mRoutine).Filtered);
end;

procedure TAtlasStepFilterTests.AcceptanceTrivialGetterSkippedThenStepsOn;
var
  mRun: TAtlasStepFilterRun;
begin
  // F7 auf Speichere(Kunde.Name) in einer Routine mit 5 Rahmen: erst GetName (6), zurück (5), dann Speichere (6).
  mRun.Cancel;
  mRun.Start(5);
  Assert.IsTrue(mRun.Entered(6));
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Return), Ord(mRun.AfterStep(6, True)));
  Assert.AreEqual(Ord(TAtlasStepFilterPhase.Returning), Ord(mRun.Phase));
  Assert.AreEqual(Ord(TAtlasStepFilterAction.StepInto), Ord(mRun.AfterReturn(5)));
  Assert.IsTrue(mRun.Entered(6));
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterStep(6, False)), 'Speichere ist nicht gefiltert');
  Assert.AreEqual(Ord(TAtlasStepFilterPhase.Idle), Ord(mRun.Phase));
  Assert.AreEqual(0, mRun.Skips);
end;

procedure TAtlasStepFilterTests.SameDepthIsNoNewRoutine;
var
  mRun: TAtlasStepFilterRun;
begin
  mRun.Cancel;
  mRun.Start(5);
  Assert.IsFalse(mRun.Entered(5), 'nächste Zeile derselben Routine');
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterStep(5, True)));
  Assert.AreEqual(Ord(TAtlasStepFilterPhase.Idle), Ord(mRun.Phase));
  mRun.Start(5);
  Assert.IsFalse(mRun.Entered(4), 'Routine zu Ende, zurück beim Aufrufer');
end;

procedure TAtlasStepFilterTests.BreakpointInsideSkippedRoutineKeepsStop;
var
  mRun: TAtlasStepFilterRun;
begin
  mRun.Cancel;
  mRun.Start(5);
  mRun.AfterStep(6, True);
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterReturn(7)), 'Haltepunkt in LogInfo greift');
  Assert.AreEqual(Ord(TAtlasStepFilterPhase.Idle), Ord(mRun.Phase));
  mRun.Start(5);
  mRun.AfterStep(6, True);
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterReturn(6)), 'Haltepunkt im Rumpf derselben Tiefe');
end;

procedure TAtlasStepFilterTests.RoutineEndsDuringReturn;
var
  mRun: TAtlasStepFilterRun;
begin
  mRun.Cancel;
  mRun.Start(5);
  mRun.AfterStep(6, True);
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterReturn(4)));
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterReturn(5)), 'nach Cancel nichts mehr');
end;

procedure TAtlasStepFilterTests.NotFilteredKeepsStop;
var
  mRun: TAtlasStepFilterRun;
begin
  mRun.Cancel;
  mRun.Start(3);
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterStep(4, False)));
  Assert.IsFalse(mRun.Entered(4));
end;

procedure TAtlasStepFilterTests.StopsAfterMaxSkips;
var
  mRun: TAtlasStepFilterRun;
  mIndex: Integer;
begin
  mRun.Cancel;
  mRun.Start(2);
  for mIndex := 1 to TAtlasStepFilter.MaxSkips do
  begin
    Assert.AreEqual(Ord(TAtlasStepFilterAction.Return), Ord(mRun.AfterStep(3, True)));
    Assert.AreEqual(Ord(TAtlasStepFilterAction.StepInto), Ord(mRun.AfterReturn(2)));
  end;
  Assert.AreEqual(Ord(TAtlasStepFilterAction.Keep), Ord(mRun.AfterStep(3, True)), 'höchstens MaxSkips');
end;

procedure TAtlasStepFilterTests.CacheByFileAndLine;
var
  mCache: TAtlasStepRoutineCache;
  mRoutine: TAtlasStepRoutine;
begin
  mCache := TAtlasStepRoutineCache.Create;
  try
    mCache.Add('C:\P\Kunden.pas', 31, Routine('Kunden.TKunde.GetName', 'getters'));
    Assert.IsTrue(mCache.TryGet('c:/p/kunden.pas', 31, mRoutine), 'Trenner und Groß/klein egal');
    Assert.AreEqual('Kunden.TKunde.GetName', mRoutine.Name);
    Assert.IsFalse(mCache.TryGet('C:\P\Kunden.pas', 32, mRoutine));
    mCache.Add('C:\P\Kunden.pas', 31, Routine('Kunden.TKunde.Neu', ''));
    Assert.AreEqual(1, mCache.Count);
    mCache.Clear;
    Assert.AreEqual(0, mCache.Count);
  finally
    mCache.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStepFilterTests);

end.
