unit Adapters.Mcp.Process.Tests;

// Tests für den Host-Adapter zwischen Mcp und der Plattform: eigene Prozessnummer, laufende Prozesse und der
// Warteschritt auf einen Ordner kommen aus Platform.Server.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpProcessAdapterTests = class
  public
    [Test]
    procedure OwnProcessRuns;
    [Test]
    procedure FolderWaitReturns;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Mcp.Contract.Process,
  Adapters.Mcp.Process,
  Platform.Server;

procedure TMcpProcessAdapterTests.OwnProcessRuns;
var
  mHost: IMcpProcessHost;
begin
  mHost := TMcpProcessAdapter.New;
  Assert.AreEqual(TServerPlatform.CurrentProcessId, mHost.CurrentProcessId);
  Assert.IsTrue(mHost.Running(mHost.CurrentProcessId), 'eigener Prozess läuft');
end;

procedure TMcpProcessAdapterTests.FolderWaitReturns;
var
  mHost: IMcpProcessHost;
  mWait: TProc;
begin
  mHost := TMcpProcessAdapter.New;
  mWait := mHost.FolderWait(TPath.GetTempPath, 1, 1);
  Assert.IsTrue(Assigned(mWait), 'Warteschritt');
  mWait();
  mWait := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpProcessAdapterTests);

end.
