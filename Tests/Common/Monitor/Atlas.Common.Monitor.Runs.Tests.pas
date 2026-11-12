unit Atlas.Common.Monitor.Runs.Tests;

// Tests für die Läufe des Prüffensters von AtlasMonitor (#1900): ein Lauf je Ziel nacheinander, Abbrechen,
// Fehler nach Exit-Code je Befehl, Stand und Zusammenfassung in beiden Sprachen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorRunsTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RunsOneTargetAfterAnother;
    [Test]
    procedure ReplayHasOneRun;
    [Test]
    procedure CancelStopsWaitingAndRunning;
    [Test]
    procedure FailureDependsOnCommand;
    [Test]
    procedure StateTexts;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Commands,
  Atlas.Common.Monitor.Runs;

procedure TMonitorRunsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorRunsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorRunsTests.RunsOneTargetAfterAnother;
var
  mQueue: TMonitorRunQueue;
  mFinding: TMonitorFinding;
begin
  mQueue := TMonitorRunQueue.Create(TMonitorCommand.Check, TArray<string>.Create('A', 'B'));
  Assert.AreEqual(2, Integer(Length(mQueue.Runs)));
  Assert.IsTrue(mQueue.Busy);
  Assert.AreEqual(0, mQueue.NextIndex);
  mQueue.Runs[0].State := TMonitorRunState.Running;
  Assert.AreEqual(-1, mQueue.NextIndex, 'einer läuft');
  Assert.AreEqual(0, mQueue.RunningIndex);
  mFinding := Default(TMonitorFinding);
  mQueue.Runs[0].Findings := TArray<TMonitorFinding>.Create(mFinding, mFinding);
  mQueue.Finish(0, 0);
  Assert.IsTrue(mQueue.Runs[0].State = TMonitorRunState.Done);
  Assert.AreEqual(1, mQueue.NextIndex);
  Assert.AreEqual('1 von 2 Zielen fertig, 2 Befunde', mQueue.Summary);
  mQueue.Finish(1, 3);
  Assert.IsTrue(mQueue.Runs[1].State = TMonitorRunState.Failed);
  Assert.IsFalse(mQueue.Busy);
  Assert.AreEqual(2, Integer(Length(mQueue.AllFindings)));
  mQueue.Finish(7, 0);
  mQueue := Default(TMonitorRunQueue);
end;

procedure TMonitorRunsTests.ReplayHasOneRun;
var
  mQueue: TMonitorRunQueue;
begin
  mQueue := TMonitorRunQueue.Create(TMonitorCommand.Replay, TArray<string>.Create('A', 'B'));
  Assert.AreEqual(1, Integer(Length(mQueue.Runs)));
  Assert.AreEqual('', mQueue.Runs[0].Target);
  Assert.AreEqual('0 von 1 Zielen fertig', mQueue.Summary);
  mQueue := Default(TMonitorRunQueue);
end;

procedure TMonitorRunsTests.CancelStopsWaitingAndRunning;
var
  mQueue: TMonitorRunQueue;
begin
  mQueue := TMonitorRunQueue.Create(TMonitorCommand.Metrics, TArray<string>.Create('A', 'B', 'C'));
  mQueue.Finish(0, 0);
  mQueue.Runs[1].State := TMonitorRunState.Running;
  mQueue.CancelAll;
  Assert.IsTrue(mQueue.Runs[0].State = TMonitorRunState.Done);
  Assert.IsTrue(mQueue.Runs[1].State = TMonitorRunState.Cancelled);
  Assert.IsTrue(mQueue.Runs[2].State = TMonitorRunState.Cancelled);
  Assert.AreEqual(-1, mQueue.NextIndex);
  mQueue := Default(TMonitorRunQueue);
end;

procedure TMonitorRunsTests.FailureDependsOnCommand;
begin
  Assert.IsTrue(TMonitorRunQueue.IsFailure(TMonitorCommand.Check, 1), 'Prüfen mit --fail-on never');
  Assert.IsFalse(TMonitorRunQueue.IsFailure(TMonitorCommand.FormatCheck, 1), 'Abweichungen');
  Assert.IsFalse(TMonitorRunQueue.IsFailure(TMonitorCommand.AffectedTests, 2), 'alle Tests nötig');
  Assert.IsTrue(TMonitorRunQueue.IsFailure(TMonitorCommand.Query, 3));
  Assert.IsFalse(TMonitorRunQueue.IsFailure(TMonitorCommand.Replay, 1), 'nachgestellt');
  Assert.IsTrue(TMonitorRunQueue.IsFailure(TMonitorCommand.Replay, 2), 'Fall nicht lesbar');
  Assert.IsTrue(TMonitorRunQueue.IsFailure(TMonitorCommand.Metrics, -1));
end;

procedure TMonitorRunsTests.StateTexts;
var
  mRun: TMonitorRun;
begin
  mRun := Default(TMonitorRun);
  Assert.AreEqual('wartet', TMonitorRunQueue.StateText(TMonitorCommand.Check, mRun));
  mRun.State := TMonitorRunState.Running;
  Assert.AreEqual('läuft', TMonitorRunQueue.StateText(TMonitorCommand.Check, mRun));
  mRun.Done := 3;
  mRun.Total := 10;
  Assert.AreEqual('läuft (3 von 10)', TMonitorRunQueue.StateText(TMonitorCommand.Check, mRun));
  mRun.State := TMonitorRunState.Done;
  Assert.AreEqual('fertig: 0 Befunde', TMonitorRunQueue.StateText(TMonitorCommand.Check, mRun));
  Assert.AreEqual('fertig', TMonitorRunQueue.StateText(TMonitorCommand.Hotspots, mRun));
  mRun.ExitCode := 1;
  Assert.AreEqual('fertig: nachgestellt', TMonitorRunQueue.StateText(TMonitorCommand.Replay, mRun));
  mRun.State := TMonitorRunState.Failed;
  mRun.ExitCode := 3;
  Assert.AreEqual('Fehler (Exit-Code 3)', TMonitorRunQueue.StateText(TMonitorCommand.Check, mRun));
  mRun.State := TMonitorRunState.Cancelled;
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('cancelled', TMonitorRunQueue.StateText(TMonitorCommand.Check, mRun));
  mRun := Default(TMonitorRun);
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorRunsTests);

end.
