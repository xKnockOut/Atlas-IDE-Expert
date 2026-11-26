unit Atlas.Common.Diagnostics.ServerActivity.Tests;

// Tests für die Aktivität des Servers (#1901): laufende Anfragen mit Dauer, Fehler, Zeitüberschreitungen,
// Fortschritt und Zustand und ausführlicher Status über SetDetails.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Diagnostics.ServerActivity;

type
  [TestFixture]
  TServerActivityTests = class
  private
    FActivity: TServerActivity;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DescribesProcess;
    [Test]
    procedure TracksLongestRunningRequest;
    [Test]
    procedure CountsErrorsAndTimeouts;
    [Test]
    procedure ProgressMeansWorking;
    [Test]
    procedure ReportsProfiledProcess;
    [Test]
    procedure DetailsFallBackToTarget;
    [Test]
    procedure DetailsComeFromFunction;
    [Test]
    procedure SharedIsEnabledByDefault;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.Diagnostics.StatusFile;

{ TServerActivityTests }

procedure TServerActivityTests.Setup;
begin
  FActivity := TServerActivity.Create;
end;

procedure TServerActivityTests.TearDown;
begin
  FreeAndNil(FActivity);
end;

procedure TServerActivityTests.DescribesProcess;
var
  mEntry: TServerStatusEntry;
begin
  FActivity.Describe(TServerStatusEntry.cKindCli, 'check', 'App.dproj');
  FActivity.SetLogFile('server.log');
  mEntry := FActivity.Snapshot(1000);
  Assert.AreEqual('cli', mEntry.Kind);
  Assert.AreEqual('check', mEntry.Command);
  Assert.AreEqual('App.dproj', mEntry.Target);
  Assert.AreEqual('server.log', mEntry.LogFile);
  Assert.IsTrue(mEntry.Started > 0);
  Assert.AreEqual('ready', mEntry.State);
  Assert.AreEqual(0, mEntry.Running);
end;

procedure TServerActivityTests.TracksLongestRunningRequest;
var
  mEntry: TServerStatusEntry;
  mThread: TThread;
  mActivity: TServerActivity;
begin
  mActivity := FActivity;
  FActivity.RequestStarted('textDocument/hover', 1000);
  // Eine zweite Anfrage in einem anderen Thread, früher begonnen.
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      mActivity.RequestStarted('workspace/symbol', 400);
    end);
  mThread.FreeOnTerminate := False;
  try
    mThread.Start;
    mThread.WaitFor;
  finally
    mThread.Free;
  end;
  mEntry := FActivity.Snapshot(1500);
  Assert.AreEqual(2, mEntry.Running);
  Assert.AreEqual('workspace/symbol', mEntry.RunningMethod);
  Assert.AreEqual<Int64>(1100, mEntry.RunningMs);
  Assert.AreEqual('working', mEntry.State);
  FActivity.RequestFinished(False);
  mEntry := FActivity.Snapshot(1500);
  Assert.AreEqual(1, mEntry.Running, 'nur die Anfrage dieses Threads ist fertig');
  Assert.AreEqual(0, mEntry.Errors);
end;

procedure TServerActivityTests.CountsErrorsAndTimeouts;
var
  mEntry: TServerStatusEntry;
begin
  FActivity.RequestStarted('textDocument/hover', 10);
  FActivity.RequestFinished(True);
  FActivity.CountTimeout;
  FActivity.CountTimeout;
  mEntry := FActivity.Snapshot(20);
  Assert.AreEqual(1, mEntry.Errors);
  Assert.AreEqual(2, mEntry.Timeouts);
  Assert.AreEqual(0, mEntry.Running);
end;

procedure TServerActivityTests.ProgressMeansWorking;
var
  mEntry: TServerStatusEntry;
begin
  FActivity.SetProgress(3, 10);
  mEntry := FActivity.Snapshot(0);
  Assert.AreEqual(3, mEntry.Done);
  Assert.AreEqual(10, mEntry.Total);
  Assert.AreEqual('working', mEntry.State);
  FActivity.SetProgress(10, 10);
  Assert.AreEqual('ready', FActivity.Snapshot(0).State);
end;

procedure TServerActivityTests.ReportsProfiledProcess;
begin
  Assert.AreEqual<Cardinal>(0, FActivity.Snapshot(0).ProfiledProcess, 'ohne Profil-Lauf');
  FActivity.SetProfiledProcess(4711);
  Assert.AreEqual<Cardinal>(4711, FActivity.Snapshot(0).ProfiledProcess);
  FActivity.SetProfiledProcess(0);
  Assert.AreEqual<Cardinal>(0, FActivity.Snapshot(0).ProfiledProcess);
end;

procedure TServerActivityTests.DetailsFallBackToTarget;
var
  mDetails: TServerDetails;
begin
  Assert.AreEqual(0, Integer(Length(FActivity.Details.Roots)), 'ohne Ziel keine Wurzel');
  FActivity.Describe(TServerStatusEntry.cKindMcp, '', 'C:\Projekte\App');
  mDetails := FActivity.Details;
  Assert.IsNull(mDetails.Status);
  Assert.AreEqual(1, Integer(Length(mDetails.Roots)));
  Assert.AreEqual('C:\Projekte\App', mDetails.Roots[0]);
  mDetails := Default(TServerDetails);
end;

procedure TServerActivityTests.DetailsComeFromFunction;
var
  mDetails: TServerDetails;
begin
  FActivity.SetDetails(
    function: TServerDetails
    begin
      Result := Default(TServerDetails);
      Result.Roots := TArray<string>.Create('C:\A', 'C:\B');
      Result.State := 'loading';
      Result.Status := TJSONObject.Create;
    end);
  mDetails := FActivity.Details;
  try
    Assert.AreEqual(2, Integer(Length(mDetails.Roots)));
    Assert.AreEqual('loading', mDetails.State);
    Assert.IsNotNull(mDetails.Status);
  finally
    mDetails.Status.Free;
  end;
  // Abgemeldet: wieder ohne Status.
  FActivity.SetDetails(nil);
  Assert.IsNull(FActivity.Details.Status);
  mDetails := Default(TServerDetails);
end;

procedure TServerActivityTests.SharedIsEnabledByDefault;
begin
  Assert.IsNotNull(TServerActivity.Shared);
  Assert.IsTrue(TServerActivity.Shared.Enabled);
  FActivity.Enabled := False;
  Assert.IsFalse(FActivity.Enabled);
end;

initialization
  TDUnitX.RegisterTestFixture(TServerActivityTests);

end.
