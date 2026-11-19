unit Atlas.Text.TestRunFile.Tests;

// Tests für die Ablage des letzten Testlaufs (#2409): Hin- und Rückweg, kaputte und neuere Dateien, Vergleich mit
// dem Lauf davor (neu rot, wieder grün).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRunFileTests = class
  public
    [Test]
    procedure RoundTripKeepsEverything;
    [Test]
    procedure OptionalFieldsStayAway;
    [Test]
    procedure RejectsBrokenAndNewerFiles;
    [Test]
    procedure MarksNewFailuresAndFixedTests;
    [Test]
    procedure FolderBelowBase;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Text.TestResults,
  Atlas.Text.TestRunFile;

function NewCase(const AName: string; AOutcome: TTestOutcome): TTestRunFileCase;
begin
  Result := Default(TTestRunFileCase);
  Result.Test.FullName := AName;
  Result.Test.UnitName := 'Demo.Tests';
  Result.Test.Outcome := AOutcome;
  Result.Test.DurationMs := 12;
end;

function Sample: TTestRunFile;
var
  mCase: TTestRunFileCase;
  mUnit: TTestRunUnit;
begin
  Result := Default(TTestRunFile);
  Result.Project := 'C:\P\Demo.Tests.dproj';
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
  Result.FinishedAtUtc := EncodeDateTime(2026, 11, 16, 10, 42, 5, 0);
  Result.DurationMs := 138000;
  Result.Filter := ['Demo.Tests.TRechner'];
  mUnit.Name := 'Demo.Tests';
  mUnit.FileName := 'C:\P\Demo.Tests.pas';
  Result.Units := [mUnit];
  mCase := NewCase('Demo.Tests.TRechner.Summe', TTestOutcome.Failed);
  mCase.Test.Message := 'Expected 1 but got 2';
  mCase.Test.Expected := '1';
  mCase.Test.Actual := '2';
  mCase.Test.HasValues := True;
  mCase.FileName := 'C:\P\Demo.Tests.pas';
  mCase.Line := 318;
  mCase.FlakyFailed := 3;
  mCase.FlakyRuns := 10;
  mCase.Change := TTestRunChange.NewFailure;
  mCase.Log := ['Trunk doppelt', 'Ende'];
  Result.Cases := [mCase, NewCase('Demo.Tests.TRechner.Leer', TTestOutcome.Passed)];
  Result.Cases[1].Test.LeakBytes := 72;
end;

procedure TTestRunFileTests.RoundTripKeepsEverything;
var
  mRun: TTestRunFile;
begin
  Assert.IsTrue(TTestRunFiles.Parse(TTestRunFiles.ToJson(Sample), mRun));
  Assert.AreEqual('C:\P\Demo.Tests.dproj', mRun.Project);
  Assert.AreEqual('Debug', mRun.Configuration);
  Assert.AreEqual('Win64', mRun.Platform);
  Assert.IsTrue(Abs(EncodeDateTime(2026, 11, 16, 10, 42, 5, 0) - mRun.FinishedAtUtc) < 1 / SecsPerDay);
  Assert.IsTrue(mRun.FinishedAtLocal > 0);
  Assert.AreEqual(Int64(138000), mRun.DurationMs);
  Assert.AreEqual(1, Integer(Length(mRun.Filter)));
  Assert.AreEqual('C:\P\Demo.Tests.pas', mRun.UnitFileOf('demo.tests'));
  Assert.AreEqual(2, mRun.Total);
  Assert.AreEqual(1, mRun.Failed);
  Assert.AreEqual(1, mRun.IndexOf('DEMO.TESTS.TRECHNER.LEER'));
  Assert.AreEqual('Expected 1 but got 2', mRun.Cases[0].Test.Message);
  Assert.IsTrue(mRun.Cases[0].Test.HasValues);
  Assert.AreEqual('2', mRun.Cases[0].Test.Actual);
  Assert.AreEqual(318, mRun.Cases[0].Line);
  Assert.IsTrue(mRun.Cases[0].IsFlaky);
  Assert.AreEqual(3, mRun.Cases[0].FlakyFailed);
  Assert.AreEqual(Ord(TTestRunChange.NewFailure), Ord(mRun.Cases[0].Change));
  Assert.AreEqual(2, Integer(Length(mRun.Cases[0].Log)));
  Assert.AreEqual(Int64(72), mRun.Cases[1].Test.LeakBytes);
  Assert.AreEqual(Ord(TTestOutcome.Passed), Ord(mRun.Cases[1].Test.Outcome));
end;

procedure TTestRunFileTests.OptionalFieldsStayAway;
var
  mText: string;
  mRun: TTestRunFile;
begin
  mRun := Default(TTestRunFile);
  mRun.Project := 'C:\P\Demo.Tests.dproj';
  mRun.Cases := [NewCase('Demo.Tests.TRechner.Leer', TTestOutcome.Passed)];
  mText := TTestRunFiles.ToJson(mRun);
  Assert.IsFalse(mText.Contains('"expected"'));
  Assert.IsFalse(mText.Contains('"flakyRuns"'));
  Assert.IsFalse(mText.Contains('"change"'));
  Assert.IsFalse(mText.Contains('"log"'));
  Assert.IsTrue(TTestRunFiles.Parse(mText, mRun));
  Assert.IsFalse(mRun.Cases[0].Test.HasValues);
  Assert.IsFalse(mRun.Cases[0].IsFlaky);
end;

procedure TTestRunFileTests.RejectsBrokenAndNewerFiles;
var
  mRun: TTestRunFile;
begin
  Assert.IsFalse(TTestRunFiles.Parse('', mRun));
  Assert.IsFalse(TTestRunFiles.Parse('[1]', mRun));
  Assert.IsFalse(TTestRunFiles.Parse('{"format": 1}', mRun));
  Assert.IsFalse(TTestRunFiles.Parse('{"format": 2, "project": "C:\\P\\A.dproj"}', mRun));
  Assert.IsTrue(TTestRunFiles.Parse('{"format": 1, "project": "C:\\P\\A.dproj", "tests": [1, {"name": "A.T.M", ' +
    '"outcome": "error"}]}', mRun));
  Assert.AreEqual(1, mRun.Total);
  Assert.AreEqual(Ord(TTestOutcome.Error), Ord(mRun.Cases[0].Test.Outcome));
end;

procedure TTestRunFileTests.MarksNewFailuresAndFixedTests;
var
  mBefore, mNow: TTestRunFile;
begin
  mBefore := Default(TTestRunFile);
  mBefore.Cases := [NewCase('A.T.Rot', TTestOutcome.Passed), NewCase('A.T.Gruen', TTestOutcome.Failed),
    NewCase('A.T.Bleibt', TTestOutcome.Failed), NewCase('A.T.Aus', TTestOutcome.Skipped)];
  mNow := Default(TTestRunFile);
  mNow.Cases := [NewCase('A.T.Rot', TTestOutcome.Error), NewCase('A.T.Gruen', TTestOutcome.Passed),
    NewCase('A.T.Bleibt', TTestOutcome.Failed), NewCase('A.T.Aus', TTestOutcome.Failed),
    NewCase('A.T.Neu', TTestOutcome.Failed)];
  mNow.Cases[2].Change := TTestRunChange.Fixed;
  TTestRunFiles.MarkChanges(mBefore, mNow);
  Assert.AreEqual(Ord(TTestRunChange.NewFailure), Ord(mNow.Cases[0].Change));
  Assert.AreEqual(Ord(TTestRunChange.Fixed), Ord(mNow.Cases[1].Change));
  // Unverändert rot, vorher übersprungen oder neu: keine Marke.
  Assert.AreEqual(Ord(TTestRunChange.None), Ord(mNow.Cases[2].Change));
  Assert.AreEqual(Ord(TTestRunChange.None), Ord(mNow.Cases[3].Change));
  Assert.AreEqual(Ord(TTestRunChange.None), Ord(mNow.Cases[4].Change));
end;

procedure TTestRunFileTests.FolderBelowBase;
begin
  Assert.AreEqual(IncludeTrailingPathDelimiter('Basis') + 'last-tests', TTestRunFiles.Folder('Basis'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRunFileTests);

end.
