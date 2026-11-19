unit Atlas.Core.Tests.LastRun.Tests;

// Tests der Ablage des letzten Testlaufs (#2409) ohne IDE: Fundstelle 1-basiert, Protokollauszug nur roter Tests,
// wackelnde Tests, neu rot gegenüber der Datei davor (nur desselben Projekts), Units je einmal.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestLastRunTests = class
  public
    [Test]
    procedure BuildsCasesWithPlaceFlakyAndLog;
    [Test]
    procedure MarksChangesOnlyAgainstSameProject;
    [Test]
    procedure LogExcerptKeepsLastLines;
    [Test]
    procedure UnitNamesOnce;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Text.TestResults,
  Atlas.Text.TestRunFile,
  Atlas.Core.Tests.Log,
  Atlas.Core.Tests.LastRun;

const
  cProject = 'C:\P\Demo.Tests.dproj';

function NewTest(const AMethod: string; AOutcome: TTestOutcome): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.FullName := 'Demo.Tests.TRechner.' + AMethod;
  Result.UnitName := 'Demo.Tests';
  Result.Fixture := 'TRechner';
  Result.Method := AMethod;
  Result.Outcome := AOutcome;
  Result.DurationMs := 7;
end;

function LogLine(AOrigin: TAtlasTestLogOrigin; const AText: string): TAtlasTestLogLine;
begin
  Result := Default(TAtlasTestLogLine);
  Result.Origin := AOrigin;
  Result.Text := AText;
end;

function Parts: TAtlasTestLastRunParts;
var
  mEntry: TAtlasTestLogEntry;
begin
  Result := Default(TAtlasTestLastRunParts);
  Result.Project := cProject;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.Filter := ['Demo.Tests.TRechner'];
  Result.FinishedAtUtc := EncodeDateTime(2026, 11, 16, 10, 0, 0, 0);
  Result.Run.Valid := True;
  Result.Run.DurationMs := 900;
  Result.Run.Cases := [NewTest('Summe', TTestOutcome.Failed), NewTest('Leer', TTestOutcome.Passed)];
  Result.Run.Cases[0].StackTrace := 'Demo.Tests.pas:40';
  Result.Places := [TAtlasTestPlace.Make('demo.tests.trechner.summe', 'C:\P\Demo.Tests.pas', 39)];
  mEntry := Default(TAtlasTestLogEntry);
  mEntry.Name := 'Demo.Tests.TRechner.Summe';
  mEntry.Lines := [LogLine(TAtlasTestLogOrigin.Start, 'Start'), LogLine(TAtlasTestLogOrigin.Log, 'Verbunden'),
    LogLine(TAtlasTestLogOrigin.Console, 'Ausgabe'), LogLine(TAtlasTestLogOrigin.Finish, 'Ende')];
  Result.Log.HasLogger := True;
  Result.Log.Entries := [mEntry];
  Result.Flaky :=
    function(const ACase: TTestCaseResult; out AFailed, ARuns: Integer): Boolean
    begin
      Result := ACase.Method = 'Leer';
      AFailed := 2;
      ARuns := 6;
    end;
end;

procedure TAtlasTestLastRunTests.BuildsCasesWithPlaceFlakyAndLog;
var
  mRun: TTestRunFile;
begin
  mRun := TAtlasTestLastRun.Build(Parts, '');
  Assert.AreEqual(cProject, mRun.Project);
  Assert.AreEqual('Win64', mRun.Platform);
  Assert.AreEqual(Int64(900), mRun.DurationMs);
  Assert.AreEqual(1, Integer(Length(mRun.Filter)));
  Assert.AreEqual(2, mRun.Total);
  Assert.AreEqual('C:\P\Demo.Tests.pas', mRun.Cases[0].FileName);
  Assert.AreEqual(40, mRun.Cases[0].Line);
  Assert.AreEqual('', mRun.Cases[0].Test.StackTrace);
  Assert.AreEqual(2, Integer(Length(mRun.Cases[0].Log)));
  Assert.AreEqual('Verbunden', mRun.Cases[0].Log[0]);
  Assert.IsFalse(mRun.Cases[0].IsFlaky);
  Assert.IsTrue(mRun.Cases[1].IsFlaky);
  Assert.AreEqual(2, mRun.Cases[1].FlakyFailed);
  Assert.AreEqual(6, mRun.Cases[1].FlakyRuns);
  Assert.AreEqual(0, mRun.Cases[1].Line);
  Assert.AreEqual(0, Integer(Length(mRun.Cases[1].Log)));
  Assert.AreEqual(Ord(TTestRunChange.None), Ord(mRun.Cases[0].Change));
end;

procedure TAtlasTestLastRunTests.MarksChangesOnlyAgainstSameProject;
var
  mBefore: TTestRunFile;
  mRun: TTestRunFile;
begin
  mBefore := Default(TTestRunFile);
  mBefore.Project := cProject;
  mBefore.Cases := [Default(TTestRunFileCase), Default(TTestRunFileCase)];
  mBefore.Cases[0].Test := NewTest('Summe', TTestOutcome.Passed);
  mBefore.Cases[1].Test := NewTest('Leer', TTestOutcome.Failed);
  mRun := TAtlasTestLastRun.Build(Parts, TTestRunFiles.ToJson(mBefore));
  Assert.AreEqual(Ord(TTestRunChange.NewFailure), Ord(mRun.Cases[0].Change));
  Assert.AreEqual(Ord(TTestRunChange.Fixed), Ord(mRun.Cases[1].Change));
  mBefore.Project := 'C:\P\Andere.Tests.dproj';
  mRun := TAtlasTestLastRun.Build(Parts, TTestRunFiles.ToJson(mBefore));
  Assert.AreEqual(Ord(TTestRunChange.None), Ord(mRun.Cases[0].Change));
  mRun := TAtlasTestLastRun.Build(Parts, 'kaputt');
  Assert.AreEqual(Ord(TTestRunChange.None), Ord(mRun.Cases[0].Change));
end;

procedure TAtlasTestLastRunTests.LogExcerptKeepsLastLines;
var
  mLog: TAtlasTestLogRun;
  mEntry: TAtlasTestLogEntry;
  mLines: TArray<string>;
begin
  mEntry := Default(TAtlasTestLogEntry);
  mEntry.Name := 'A.T.M';
  mEntry.Lines := [LogLine(TAtlasTestLogOrigin.Log, '1'), LogLine(TAtlasTestLogOrigin.Log, '2'),
    LogLine(TAtlasTestLogOrigin.Console, '3'), LogLine(TAtlasTestLogOrigin.Finish, 'Ende')];
  mLog := Default(TAtlasTestLogRun);
  mLog.Entries := [mEntry];
  mLines := TAtlasTestLastRun.LogExcerpt(mLog, 'a.t.m', 2);
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual('2', mLines[0]);
  Assert.AreEqual('3', mLines[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasTestLastRun.LogExcerpt(mLog, 'X.Y.Z', 2))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestLastRun.LogExcerpt(mLog, 'A.T.M', 0))));
  mLines := nil;
end;

procedure TAtlasTestLastRunTests.UnitNamesOnce;
var
  mCases: TArray<TTestCaseResult>;
  mNames: TArray<string>;
begin
  mCases := [NewTest('A', TTestOutcome.Passed), NewTest('B', TTestOutcome.Passed),
    NewTest('C', TTestOutcome.Passed)];
  mCases[2].UnitName := 'Zweite.Tests';
  mCases[1].UnitName := 'DEMO.TESTS';
  mNames := TAtlasTestLastRun.UnitNames(mCases);
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('Demo.Tests', mNames[0]);
  Assert.AreEqual('Zweite.Tests', mNames[1]);
  mCases := nil;
  mNames := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestLastRunTests);

end.
