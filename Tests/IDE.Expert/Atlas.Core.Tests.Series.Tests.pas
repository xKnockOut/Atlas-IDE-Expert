unit Atlas.Core.Tests.Series.Tests;

// Tests der Serien von Testläufen (#1782): Mischen mit Startwert (gleich auf
// allen Systemen, jede Reihenfolge eine Vertauschung), Anzahl aus der Eingabe,
// Namen je Test für die zufällige Reihenfolge, Ablauf und Auswertung einer
// Serie samt Beschriftung der Marke.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestSeriesTests = class
  public
    [Test]
    procedure ShuffleSameSeedSameOrder;
    [Test]
    procedure ShuffleKeepsAllNames;
    [Test]
    procedure ShuffleFixedOrderForSeed;
    [Test]
    procedure ShuffleOtherSeedOtherOrder;
    [Test]
    procedure SeedWithinLimit;
    [Test]
    procedure CountOnlyWithinLimits;
    [Test]
    procedure SingleNamesPerTestAndCase;
    [Test]
    procedure RepeatingRunsSameNames;
    [Test]
    procedure ShufflingOneTestPerStep;
    [Test]
    procedure AddCountsStepsAndTests;
    [Test]
    procedure FailingMostFirst;
    [Test]
    procedure StoppedOrCancelledFinishes;
    [Test]
    procedure CaptionOfMark;
    [Test]
    procedure SubjectMatchesIgnoringCase;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Series;

function Names(ACount: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := 'Demo.Tests.TDemo.Test' + IntToStr(mIndex + 1);
  end;
end;

function Joined(const ANames: TArray<string>): string;
begin
  Result := string.Join(',', ANames);
end;

function CaseOf(const AName: string; AOutcome: TTestOutcome; const AMessage: string): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.FullName := AName;
  Result.Outcome := AOutcome;
  Result.Message := AMessage;
end;

function RunOf(const ACases: TArray<TTestCaseResult>): TTestRunResult;
begin
  Result := Default(TTestRunResult);
  Result.Valid := True;
  Result.Cases := ACases;
end;

function Subject: TAtlasTestSeriesSubject;
begin
  Result := TAtlasTestSeriesSubject.Make('Demo.Tests', 'TDemo', 'Test1', '');
end;

procedure TAtlasTestSeriesTests.ShuffleSameSeedSameOrder;
begin
  Assert.AreEqual(Joined(TAtlasTestShuffle.Shuffled(Names(12), 48213)),
    Joined(TAtlasTestShuffle.Shuffled(Names(12), 48213)), 'derselbe Startwert, dieselbe Reihenfolge');
end;

procedure TAtlasTestSeriesTests.ShuffleKeepsAllNames;
var
  mShuffled: TArray<string>;
  mName: string;
  mFound: Integer;
  mOther: string;
begin
  mShuffled := TAtlasTestShuffle.Shuffled(Names(9), 7);
  Assert.AreEqual(9, Integer(Length(mShuffled)));
  for mName in Names(9) do
  begin
    mFound := 0;
    for mOther in mShuffled do
    begin
      if mOther = mName then
      begin
        Inc(mFound);
      end;
    end;
    Assert.AreEqual(1, mFound, mName);
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasTestShuffle.Shuffled(nil, 7))), 'leer bleibt leer');
  Assert.AreEqual('A', Joined(TAtlasTestShuffle.Shuffled(TArray<string>.Create('A'), 7)), 'ein Name');
end;

procedure TAtlasTestSeriesTests.ShuffleFixedOrderForSeed;
begin
  // Festgeschrieben: Delphi und FPC müssen dieselbe Reihenfolge liefern („Mit dieser Reihenfolge erneut“).
  // minstd ab 1: 48271, 182605794, 1291394886, 1914720637; i = 4..1 → j = 1, 2, 0, 1.
  Assert.AreEqual('D,E,A,C,B', Joined(TAtlasTestShuffle.Shuffled(TArray<string>.Create('A', 'B', 'C', 'D', 'E'),
    1)));
  Assert.AreEqual('D,E,A,C,B', Joined(TAtlasTestShuffle.Shuffled(TArray<string>.Create('A', 'B', 'C', 'D', 'E'),
    0)), 'Startwert 0 wie 1');
end;

procedure TAtlasTestSeriesTests.ShuffleOtherSeedOtherOrder;
var
  mSeed: Cardinal;
  mDiffers: Boolean;
begin
  mDiffers := False;
  for mSeed := 2 to 20 do
  begin
    mDiffers := mDiffers or (Joined(TAtlasTestShuffle.Shuffled(Names(10), mSeed)) <>
      Joined(TAtlasTestShuffle.Shuffled(Names(10), 1)));
  end;
  Assert.IsTrue(mDiffers, 'andere Startwerte mischen anders');
end;

procedure TAtlasTestSeriesTests.SeedWithinLimit;
begin
  Assert.AreEqual(1, Integer(TAtlasTestShuffle.SeedOf(0)));
  Assert.AreEqual(TAtlasTestShuffle.cSeedLimit, Integer(TAtlasTestShuffle.SeedOf(TAtlasTestShuffle.cSeedLimit - 1)));
  Assert.AreEqual(1, Integer(TAtlasTestShuffle.SeedOf(TAtlasTestShuffle.cSeedLimit)));
  Assert.IsTrue(TAtlasTestShuffle.SeedOf(High(UInt64)) <= TAtlasTestShuffle.cSeedLimit);
end;

procedure TAtlasTestSeriesTests.CountOnlyWithinLimits;
var
  mCount: Integer;
begin
  Assert.IsTrue(TAtlasTestShuffle.CountOf(' 20 ', 2, 1000, mCount));
  Assert.AreEqual(20, mCount);
  Assert.IsTrue(TAtlasTestShuffle.CountOf('1000', 2, 1000, mCount));
  Assert.IsFalse(TAtlasTestShuffle.CountOf('1', 2, 1000, mCount), 'unter der Grenze');
  Assert.IsFalse(TAtlasTestShuffle.CountOf('1001', 2, 1000, mCount), 'über der Grenze');
  Assert.IsFalse(TAtlasTestShuffle.CountOf('zwanzig', 2, 1000, mCount), 'keine Zahl');
  Assert.IsFalse(TAtlasTestShuffle.CountOf('', 2, 1000, mCount), 'leer');
end;

procedure TAtlasTestSeriesTests.SingleNamesPerTestAndCase;
var
  mUnit: TDUnitXUnit;
begin
  mUnit := TDUnitXSource.Scan(TArray<string>.Create(
    'unit Demo.Tests;',
    'interface',
    'uses DUnitX.TestFramework;',
    'type',
    '  [TestFixture]',
    '  TDemo = class',
    '  public',
    '    [Test]',
    '    procedure Eins;',
    '    [Test]',
    '    [TestCase(''Klein'', ''1'')]',
    '    [TestCase(''Gross'', ''9'')]',
    '    procedure Zwei(A: Integer);',
    '    [Test]',
    '    [Ignore(''kaputt'')]',
    '    procedure Drei;',
    '  end;',
    'implementation',
    'procedure TDemo.Eins; begin end;',
    'procedure TDemo.Zwei(A: Integer); begin end;',
    'procedure TDemo.Drei; begin end;',
    'end.'));
  Assert.AreEqual('Demo.Tests.TDemo.Eins,Demo.Tests.TDemo.Zwei.Klein,Demo.Tests.TDemo.Zwei.Gross',
    Joined(TAtlasTestShuffle.SingleNames(mUnit, 0, -1, -1)), 'Fixture: je Test bzw. Fall, ohne [Ignore]');
  Assert.AreEqual(Joined(TAtlasTestShuffle.SingleNames(mUnit, 0, -1, -1)),
    Joined(TAtlasTestShuffle.SingleNames(mUnit, -1, -1, -1)), 'ganze Unit');
  Assert.AreEqual('Demo.Tests.TDemo.Zwei.Gross', Joined(TAtlasTestShuffle.SingleNames(mUnit, 0, 1, 1)), 'ein Fall');
  Assert.AreEqual(0, Integer(Length(TAtlasTestShuffle.SingleNames(mUnit, 5, -1, -1))), 'ungültige Fixture');
end;

procedure TAtlasTestSeriesTests.RepeatingRunsSameNames;
var
  mSeries: TAtlasTestSeries;
begin
  mSeries := TAtlasTestSeries.Repeating(Subject, TArray<string>.Create('Demo.Tests.TDemo.Test1'), 3);
  Assert.AreEqual(3, mSeries.Total);
  Assert.AreEqual('Demo.Tests.TDemo.Test1', Joined(mSeries.NextNames));
  Assert.IsFalse(mSeries.Finished);
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('Demo.Tests.TDemo.Test1', TTestOutcome.Passed, ''))));
  Assert.AreEqual('Demo.Tests.TDemo.Test1', Joined(mSeries.NextNames), 'zweiter Start, dieselben Namen');
  Assert.AreEqual(0, TAtlasTestSeries.Repeating(Subject, nil, 3).Total, 'ohne Namen keine Starts');
end;

procedure TAtlasTestSeriesTests.ShufflingOneTestPerStep;
var
  mSeries: TAtlasTestSeries;
  mIndex: Integer;
  mOrder: TArray<string>;
begin
  mSeries := TAtlasTestSeries.Shuffling(Subject, Names(5), 48213);
  Assert.AreEqual(5, mSeries.Total);
  Assert.AreEqual(48213, Integer(mSeries.Seed));
  Assert.AreEqual(Joined(Names(5)), Joined(mSeries.Names), 'Namen ungemischt für „erneut“');
  mOrder := nil;
  for mIndex := 0 to mSeries.Total - 1 do
  begin
    Assert.AreEqual(1, Integer(Length(mSeries.Steps[mIndex])), 'ein Test je Start');
    mOrder := mOrder + mSeries.Steps[mIndex];
  end;
  Assert.AreEqual(Joined(TAtlasTestShuffle.Shuffled(Names(5), 48213)), Joined(mOrder));
end;

procedure TAtlasTestSeriesTests.AddCountsStepsAndTests;
var
  mSeries: TAtlasTestSeries;
begin
  mSeries := TAtlasTestSeries.Repeating(Subject, TArray<string>.Create('Demo.Tests.TDemo'), 3);
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('A', TTestOutcome.Passed, ''),
    CaseOf('B', TTestOutcome.Passed, ''))));
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('A', TTestOutcome.Passed, ''),
    CaseOf('B', TTestOutcome.Failed, 'Expected 1 but got 2'))));
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('A', TTestOutcome.Error, 'Zugriffsverletzung'),
    CaseOf('B', TTestOutcome.Skipped, ''))));
  Assert.IsTrue(mSeries.Finished);
  Assert.AreEqual(3, mSeries.Done);
  Assert.AreEqual(1, mSeries.PassedSteps, 'ein Start ganz grün');
  Assert.AreEqual(2, mSeries.FailedSteps);
  Assert.AreEqual(2, Integer(Length(mSeries.Tests)));
  Assert.AreEqual(2, mSeries.Tests[0].Passed, 'A');
  Assert.AreEqual(1, mSeries.Tests[0].Failed, 'A');
  Assert.AreEqual('Zugriffsverletzung', mSeries.Tests[0].Message);
  Assert.AreEqual(1, mSeries.Tests[1].Passed, 'B: übersprungen zählt nicht');
  Assert.AreEqual(1, mSeries.Tests[1].Failed, 'B');
  Assert.AreEqual(Ord(TAtlasTestSeriesState.Mixed), Ord(mSeries.State));
  // Nach dem letzten Start zählt nichts mehr.
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('A', TTestOutcome.Passed, ''))));
  Assert.AreEqual(3, mSeries.Done);
end;

procedure TAtlasTestSeriesTests.FailingMostFirst;
var
  mSeries: TAtlasTestSeries;
  mFailing: TArray<TAtlasTestSeriesTally>;
begin
  mSeries := TAtlasTestSeries.Repeating(Subject, TArray<string>.Create('Demo.Tests.TDemo'), 2);
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('C', TTestOutcome.Failed, 'x'),
    CaseOf('B', TTestOutcome.Failed, 'y'), CaseOf('A', TTestOutcome.Passed, ''))));
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('C', TTestOutcome.Passed, ''),
    CaseOf('B', TTestOutcome.Failed, 'z'), CaseOf('A', TTestOutcome.Passed, ''))));
  mFailing := mSeries.Failing;
  Assert.AreEqual(2, Integer(Length(mFailing)), 'A bestand immer');
  Assert.AreEqual('B', mFailing[0].FullName, 'zweimal rot zuerst');
  Assert.AreEqual('z', mFailing[0].Message, 'letzte Meldung');
  Assert.AreEqual('C', mFailing[1].FullName);
  Assert.AreEqual(Ord(TAtlasTestSeriesState.Failed), Ord(mSeries.State), 'kein Start ganz grün');
end;

procedure TAtlasTestSeriesTests.StoppedOrCancelledFinishes;
var
  mSeries: TAtlasTestSeries;
begin
  mSeries := TAtlasTestSeries.Repeating(Subject, TArray<string>.Create('Demo.Tests.TDemo'), 5);
  mSeries.Cancelled := True;
  Assert.IsTrue(mSeries.Finished);
  Assert.AreEqual(0, Integer(Length(mSeries.NextNames)), 'abgebrochen: kein weiterer Start');
  mSeries := TAtlasTestSeries.Repeating(Subject, TArray<string>.Create('Demo.Tests.TDemo'), 5);
  mSeries.Stopped := 'Build fehlgeschlagen';
  Assert.IsTrue(mSeries.Finished);
end;

procedure TAtlasTestSeriesTests.CaptionOfMark;
var
  mTexts: TAtlasTestSeriesTexts;
  mSeries: TAtlasTestSeries;
  mIndex: Integer;
begin
  mTexts := Default(TAtlasTestSeriesTexts);
  mTexts.Repeated := '%d× ausgeführt · %d bestanden, %d rot';
  mTexts.Shuffled := 'Reihenfolge %d · %d bestanden, %d rot';
  mTexts.Running := 'Tests laufen … %d/%d';
  mSeries := TAtlasTestSeries.Repeating(Subject, TArray<string>.Create('Demo.Tests.TDemo.Test1'), 20);
  Assert.AreEqual('Tests laufen … 1/20', mSeries.Caption(mTexts, True), 'der laufende Start zählt mit');
  for mIndex := 1 to 20 do
  begin
    if mIndex in [4, 17] then
    begin
      mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('T', TTestOutcome.Failed, 'x'))));
    end
    else
    begin
      mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('T', TTestOutcome.Passed, ''))));
    end;
  end;
  Assert.AreEqual('20× ausgeführt · 18 bestanden, 2 rot', mSeries.Caption(mTexts, False));
  Assert.AreEqual(Ord(TAtlasTestSeriesState.Mixed), Ord(mSeries.State), 'gemischt: gelb');
  mSeries := TAtlasTestSeries.Shuffling(Subject, Names(2), 48213);
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('T', TTestOutcome.Passed, ''))));
  mSeries.Add(RunOf(TArray<TTestCaseResult>.Create(CaseOf('U', TTestOutcome.Passed, ''))));
  Assert.AreEqual('Reihenfolge 48213 · 2 bestanden, 0 rot', mSeries.Caption(mTexts, False));
  Assert.AreEqual(Ord(TAtlasTestSeriesState.Passed), Ord(mSeries.State));
end;

procedure TAtlasTestSeriesTests.SubjectMatchesIgnoringCase;
begin
  Assert.IsTrue(Subject.Matches(TAtlasTestSeriesSubject.Make('demo.tests', 'tdemo', 'test1', '')));
  Assert.IsFalse(Subject.Matches(TAtlasTestSeriesSubject.Make('Demo.Tests', 'TDemo', '', '')), 'Fixture statt Test');
  Assert.AreEqual('TDemo.Test1', Subject.Caption);
  Assert.AreEqual('TDemo.Zwei.Klein', TAtlasTestSeriesSubject.Make('Demo.Tests', 'TDemo', 'Zwei', 'Klein').Caption);
end;

end.
