unit Atlas.Core.Tests.Flaky.Tests;

// Tests der wackelnden Tests (#1773) ohne IDE: grün → rot → grün mit
// gleichem Rumpf wackelt, nach einer Änderung am Rumpf nicht; Fälle eines
// [TestCase], Grenze der gemerkten Läufe, „bestanden, wackelt aber“ und die
// Ablage als JSON.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestHistoryTests = class
  private
    FSource: TArray<string>;
    FChanged: TArray<string>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WobblesNeedsGreenRedGreen;
    [Test]
    procedure RandomResultIsFlaky;
    [Test]
    procedure FixedBodyIsNotFlaky;
    [Test]
    procedure FailedCaseFailsTheTest;
    [Test]
    procedure SkippedDoesNotCount;
    [Test]
    procedure KeepsOnlyMaxRuns;
    [Test]
    procedure PassedButFlakyAfterRed;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure JsonRejectsOtherFormat;
    [Test]
    procedure DotsOldestFirst;
    [Test]
    procedure UnitStateCountsFlaky;
    [Test]
    procedure StateOfWithoutQueriesIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tests.Flaky,
  Atlas.Core.Tests.Stale,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults;

const
  cAddiert = 'rechner.tests.trechnertests.addiert';
  cSumme = 'rechner.tests.trechnertests.summe';

function Source: TArray<string>;
begin
  Result := TArray<string>.Create(
    'unit Rechner.Tests;',
    'interface',
    'uses DUnitX.TestFramework, Rechner;',
    'type',
    '  [TestFixture]',
    '  TRechnerTests = class',
    '  public',
    '    [Test]',
    '    procedure Addiert;',
    '    [TestCase(''Klein'', ''1,2,3'')]',
    '    [TestCase(''Gross'', ''10,20,30'')]',
    '    procedure Summe(A, B, C: Integer);',
    '  end;',
    'implementation',
    'procedure TRechnerTests.Addiert;',
    'begin',
    '  Assert.AreEqual(4, Add(2, 2));',
    'end;',
    'procedure TRechnerTests.Summe(A, B, C: Integer);',
    'begin',
    '  Assert.AreEqual(C, Add(A, B));',
    'end;',
    'end.');
end;

/// <summary>Bericht eines Laufs: je Eintrag "Name=Ergebnis" (Success, Failure, Ignored).</summary>
function Cases(const AResults: array of string): TArray<TTestCaseResult>;
var
  mXml, mItem, mName, mResult: string;
begin
  mXml := '<test-results><test-suite type="Assembly" name="R.exe"><results>' +
    '<test-suite type="TestFixture" name="TRechnerTests"><results>';
  for mItem in AResults do
  begin
    mName := Copy(mItem, 1, Pos('=', mItem) - 1);
    mResult := Copy(mItem, Pos('=', mItem) + 1, MaxInt);
    mXml := mXml + '<test-case name="Rechner.Tests.TRechnerTests.' + mName + '" executed="True" result="' +
      mResult + '" time="0.01">';
    if mResult = 'Failure' then
    begin
      mXml := mXml + '<failure><message>Expected 4 but got 5</message></failure>';
    end;
    mXml := mXml + '</test-case>';
  end;
  mXml := mXml + '</results></test-suite></results></test-suite></test-results>';
  Result := TTestResults.Parse(mXml).Cases;
end;

function At(AMinute: Integer): TDateTime;
begin
  Result := IncMinute(EncodeDate(2026, 11, 13) + EncodeTime(9, 0, 0, 0), AMinute);
end;

/// <summary>Läufe von Addiert über ALines, je Eintrag True = grün.</summary>
procedure RunAddiert(AHistory: TAtlasTestHistory; const ALines: TArray<string>; const AResults: array of Boolean;
  AFirstMinute: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AResults) do
  begin
    if AResults[mIndex] then
    begin
      AHistory.Remember(TDUnitXSource.Scan(ALines), ALines, Cases(['Addiert=Success']), At(AFirstMinute + mIndex));
    end
    else
    begin
      AHistory.Remember(TDUnitXSource.Scan(ALines), ALines, Cases(['Addiert=Failure']), At(AFirstMinute + mIndex));
    end;
  end;
end;

{ TAtlasTestHistoryTests }

procedure TAtlasTestHistoryTests.Setup;
begin
  FSource := Source;
  FChanged := Source;
  FChanged[16] := '  Assert.AreEqual(4, Add(3, 1));';
end;

procedure TAtlasTestHistoryTests.TearDown;
begin
  FSource := nil;
  FChanged := nil;
end;

procedure TAtlasTestHistoryTests.WobblesNeedsGreenRedGreen;
begin
  Assert.IsTrue(TAtlasTestHistory.Wobbles([True, False, True]));
  Assert.IsTrue(TAtlasTestHistory.Wobbles([False, True, True, False, False, True]), 'mit Wiederholungen');
  Assert.IsFalse(TAtlasTestHistory.Wobbles([False, True, False]), 'rot → grün → rot: repariert und wieder kaputt');
  Assert.IsFalse(TAtlasTestHistory.Wobbles([False, False, True, True]), 'rot, dann repariert');
  Assert.IsFalse(TAtlasTestHistory.Wobbles([True, True, False]), 'grün, dann kaputt');
  Assert.IsFalse(TAtlasTestHistory.Wobbles(nil));
end;

procedure TAtlasTestHistoryTests.RandomResultIsFlaky;
var
  mHistory: TAtlasTestHistory;
  mFlaky: TArray<TAtlasFlakyTest>;
begin
  mHistory := TAtlasTestHistory.Create;
  try
    RunAddiert(mHistory, FSource, [True, False, True, True, False, True, True, True, True, False], 0);
    mFlaky := mHistory.FlakyIn(TDUnitXSource.Scan(FSource), FSource);
    Assert.AreEqual(1, Integer(Length(mFlaky)));
    Assert.AreEqual(cAddiert, mFlaky[0].Key);
    Assert.AreEqual(3, mFlaky[0].Failed, '3 von 10 rot');
    Assert.AreEqual(10, mFlaky[0].Runs);
    Assert.AreEqual(At(0), mFlaky[0].SinceUtc, 'Rumpf unverändert seit dem ersten Lauf');
    Assert.AreEqual('Expected 4 but got 5', mFlaky[0].LastMessage);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.FixedBodyIsNotFlaky;
var
  mHistory: TAtlasTestHistory;
  mTest: TAtlasFlakyTest;
begin
  mHistory := TAtlasTestHistory.Create;
  try
    // Grün, rot, dann repariert (Rumpf geändert) und grün: kein Wackeln.
    RunAddiert(mHistory, FSource, [True, False], 0);
    RunAddiert(mHistory, FChanged, [True, True], 2);
    Assert.AreEqual(0, Integer(Length(mHistory.FlakyIn(TDUnitXSource.Scan(FChanged), FChanged))));
    Assert.IsTrue(mHistory.Check(cAddiert, TAtlasTestStamps.BodyOf(TDUnitXSource.Scan(FChanged), FChanged, 0, 0),
      mTest));
    Assert.AreEqual(2, mTest.Runs, 'nur die Läufe mit dem neuen Rumpf');
    Assert.AreEqual(At(2), mTest.SinceUtc);
    // Mit dem alten Rumpf (zurückgeändert) gilt dessen Verlauf: grün, rot – noch kein Wackeln.
    Assert.AreEqual(0, Integer(Length(mHistory.FlakyIn(TDUnitXSource.Scan(FSource), FSource))));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.FailedCaseFailsTheTest;
var
  mHistory: TAtlasTestHistory;
  mMarks: TArray<TAtlasTestRunMark>;
begin
  mHistory := TAtlasTestHistory.Create;
  try
    mHistory.Remember(TDUnitXSource.Scan(FSource), FSource, Cases(['Summe.Klein=Success', 'Summe.Gross=Failure']),
      At(0));
    mHistory.Remember(TDUnitXSource.Scan(FSource), FSource, Cases(['Summe.Klein=Success', 'Summe.Gross=Success']),
      At(1));
    mMarks := mHistory.MarksOf(cSumme);
    Assert.AreEqual(2, Integer(Length(mMarks)), 'ein Ergebnis je Lauf, nicht je Fall');
    Assert.IsFalse(mMarks[0].Passed, 'ein roter Fall macht den Test rot');
    Assert.AreEqual('Expected 4 but got 5', mMarks[0].Message);
    Assert.IsTrue(mMarks[1].Passed);
    Assert.AreEqual('', mMarks[1].Message, 'Meldung nur bei rot');
    Assert.AreEqual(0, Integer(Length(mHistory.MarksOf(cAddiert))), 'Addiert lief nicht');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.SkippedDoesNotCount;
var
  mHistory: TAtlasTestHistory;
begin
  mHistory := TAtlasTestHistory.Create;
  try
    Assert.AreEqual(0, Integer(Length(mHistory.Remember(TDUnitXSource.Scan(FSource), FSource,
      Cases(['Addiert=Ignored']), At(0)))));
    Assert.AreEqual(0, mHistory.Count);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.KeepsOnlyMaxRuns;
var
  mHistory: TAtlasTestHistory;
  mMarks: TArray<TAtlasTestRunMark>;
begin
  mHistory := TAtlasTestHistory.Create;
  try
    mHistory.MaxRuns := 1;
    Assert.AreEqual(TAtlasTestHistory.cMinRuns, mHistory.MaxRuns, 'untere Grenze');
    mHistory.MaxRuns := 1000;
    Assert.AreEqual(TAtlasTestHistory.cMaxRuns, mHistory.MaxRuns, 'obere Grenze');
    mHistory.MaxRuns := 4;
    // Grün, rot, grün fällt bei vier gemerkten Läufen nach hinten heraus.
    RunAddiert(mHistory, FSource, [True, False, True, False, False, False], 0);
    mMarks := mHistory.MarksOf(cAddiert);
    Assert.AreEqual(4, Integer(Length(mMarks)));
    Assert.AreEqual(At(2), mMarks[0].AtUtc, 'die ältesten fallen weg');
    Assert.AreEqual(0, Integer(Length(mHistory.FlakyIn(TDUnitXSource.Scan(FSource), FSource))));
    mHistory.MaxRuns := 3;
    Assert.AreEqual(3, Integer(Length(mHistory.MarksOf(cAddiert))), 'kleinere Grenze kürzt sofort');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.PassedButFlakyAfterRed;
var
  mHistory: TAtlasTestHistory;
  mTest: TAtlasFlakyTest;
begin
  mHistory := TAtlasTestHistory.Create;
  try
    RunAddiert(mHistory, FSource, [True, False], 0);
    Assert.IsFalse(mHistory.PassedButFlaky(cAddiert, mTest), 'zuletzt rot');
    RunAddiert(mHistory, FSource, [True], 2);
    Assert.IsTrue(mHistory.PassedButFlaky(cAddiert, mTest), 'erneut ausgeführt: grün, wackelt aber');
    Assert.AreEqual(1, mTest.Failed);
    Assert.AreEqual(3, mTest.Runs);
    RunAddiert(mHistory, FSource, [True], 3);
    Assert.IsFalse(mHistory.PassedButFlaky(cAddiert, mTest), 'davor schon grün: nichts Neues');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.JsonRoundTrip;
var
  mHistory, mLoaded: TAtlasTestHistory;
  mJson: string;
  mMarks: TArray<TAtlasTestRunMark>;
begin
  mHistory := TAtlasTestHistory.Create;
  mLoaded := TAtlasTestHistory.Create;
  try
    RunAddiert(mHistory, FSource, [True, False, True], 0);
    mJson := mHistory.ToJson('C:\Projekt\Tests\RechnerTests.dproj');
    Assert.IsTrue(Pos('"format":1', mJson) > 0, mJson);
    Assert.IsTrue(Pos('"test":"' + cAddiert + '"', mJson) > 0, mJson);
    Assert.IsTrue(Pos('"at":"2026-11-13T09:01:00Z"', mJson) > 0, 'Zeit in UTC wie die Projekt-Zusammenfassung');
    Assert.IsTrue(mLoaded.LoadJson(mJson));
    mMarks := mLoaded.MarksOf(cAddiert);
    Assert.AreEqual(3, Integer(Length(mMarks)));
    Assert.IsFalse(mMarks[1].Passed);
    Assert.AreEqual('Expected 4 but got 5', mMarks[1].Message);
    Assert.AreEqual(At(1), mMarks[1].AtUtc);
    Assert.AreEqual(1, Integer(Length(mLoaded.FlakyIn(TDUnitXSource.Scan(FSource), FSource))),
      'Verlauf übersteht einen Neustart');
  finally
    mLoaded.Free;
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.JsonRejectsOtherFormat;
var
  mHistory: TAtlasTestHistory;
begin
  mHistory := TAtlasTestHistory.Create;
  try
    Assert.IsFalse(mHistory.LoadJson('{"format":2,"tests":[]}'), 'neueres Format');
    Assert.IsFalse(mHistory.LoadJson('kein JSON'));
    Assert.IsTrue(mHistory.LoadJson('{"format":1,"tests":[{"test":"a.b.c","runs":[{"at":"x"}]},{"runs":[]}]}'));
    Assert.AreEqual(0, mHistory.Count, 'Einträge ohne Ergebnis bzw. ohne Namen fallen weg');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasTestHistoryTests.DotsOldestFirst;
begin
  Assert.AreEqual('+-+', TAtlasTestHistory.Dots([True, False, True], '+', '-'));
  Assert.AreEqual('', TAtlasTestHistory.Dots(nil, '+', '-'));
end;

function FlakyTest(const AFixture, AMethod: string; const AResults: TArray<Boolean>): TAtlasFlakyTest;
var
  mResult: Boolean;
begin
  Result := Default(TAtlasFlakyTest);
  Result.Key := TAtlasTestStamps.KeyOf('Rechner.Tests', AFixture, AMethod);
  Result.Results := AResults;
  for mResult in AResults do
  begin
    if not mResult then
    begin
      Inc(Result.Failed);
    end;
  end;
end;

procedure TAtlasTestHistoryTests.UnitStateCountsFlaky;
var
  mState: TAtlasTestUnitState;
  mFailed, mRuns: Integer;
begin
  mState := Default(TAtlasTestUnitState);
  mState.Flaky := [FlakyTest('TRechnerTests', 'Addiert', [True, False, True]),
    FlakyTest('TRechnerTests', 'Summe', [True, False, False, True]),
    FlakyTest('TRechnerTestsMehr', 'Teilt', [True, False, True])];
  Assert.AreEqual(1, mState.FlakyCount('Rechner.Tests', 'TRechnerTests', 'Summe', mFailed, mRuns));
  Assert.AreEqual(2, mFailed);
  Assert.AreEqual(4, mRuns);
  // Die Fixture zählt nur ihre eigenen Tests, nicht die einer Fixture mit gleichem Namensanfang.
  Assert.AreEqual(2, mState.FlakyCount('Rechner.Tests', 'TRechnerTests', '', mFailed, mRuns));
  Assert.AreEqual(0, mState.FlakyCount('Rechner.Tests', 'TRechnerTests', 'Fehlt', mFailed, mRuns));
  Assert.AreEqual(0, mFailed);
  Assert.AreEqual(0, mRuns);
  mState.Flaky := nil;
end;

procedure TAtlasTestHistoryTests.StateOfWithoutQueriesIsEmpty;
var
  mQueries: TAtlasTestStateQueries;
  mState: TAtlasTestUnitState;
begin
  mQueries := Default(TAtlasTestStateQueries);
  mState := mQueries.StateOf(TDUnitXSource.Scan(FSource), FSource);
  Assert.AreEqual(0, Integer(Length(mState.StaleKeys)));
  Assert.AreEqual(0, Integer(Length(mState.Flaky)));
end;

end.
