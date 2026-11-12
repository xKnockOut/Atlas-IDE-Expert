unit Atlas.Common.Lsp.StatusHeartbeat.Tests;

// Tests für den Takt der Statusdatei (#1901): Schreiben mit Version, Speicher und Aktivität, ausführlicher Status
// des LSP-Servers, Abschalten über server.statusFile, Löschen beim Freigeben und Schreiben im eigenen Thread.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.ServerActivity;

type
  [TestFixture]
  TServerStatusHeartbeatTests = class
  private
    FRoot: string;
    FActivity: TServerActivity;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BeatWritesActivity;
    [Test]
    procedure BeatWritesDetails;
    [Test]
    procedure DisabledDeletesFile;
    [Test]
    procedure FreeDeletesFile;
    [Test]
    procedure ThreadWritesWithoutBeat;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.Product.Version,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Lsp.StatusHeartbeat;

const
  cPid = 4711;

procedure TServerStatusHeartbeatTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atlas-Heartbeat-' + IntToStr(Random(MaxInt)));
  FActivity := TServerActivity.Create;
end;

procedure TServerStatusHeartbeatTests.TearDown;
begin
  FreeAndNil(FActivity);
  if TDirectory.Exists(FRoot) then
  begin
    TDirectory.Delete(FRoot, True);
  end;
  FRoot := '';
end;

/// <summary>Der einzige Eintrag unter ARoot; schlägt fehl, wenn es keinen oder mehrere gibt.</summary>
function OnlyEntry(const ARoot: string): TServerStatusEntry;
var
  mEntries: TArray<TServerStatusEntry>;
begin
  mEntries := TServerStatusFile.List(ARoot, Now, nil);
  Assert.AreEqual(1, Integer(Length(mEntries)));
  Result := mEntries[0];
end;

procedure TServerStatusHeartbeatTests.BeatWritesActivity;
var
  mHeartbeat: TServerStatusHeartbeat;
  mEntry: TServerStatusEntry;
begin
  FActivity.Describe(TServerStatusEntry.cKindMcp, '', 'C:\Projekte\App');
  FActivity.SetProgress(1, 4);
  mHeartbeat := TServerStatusHeartbeat.Create(FRoot, cPid, FActivity, 0);
  try
    mHeartbeat.Beat;
    mEntry := OnlyEntry(FRoot);
    Assert.AreEqual<Cardinal>(cPid, mEntry.Pid);
    Assert.AreEqual('mcp', mEntry.Kind);
    Assert.AreEqual(TProductVersion.cVersion, mEntry.Version);
    Assert.IsTrue(mEntry.MemoryBytes >= 0);
    Assert.AreEqual('working', mEntry.State);
    Assert.AreEqual(4, mEntry.Total);
    Assert.AreEqual(1, Integer(Length(mEntry.Roots)), 'Ziel als Wurzel');
    Assert.AreEqual('', mEntry.Status);
  finally
    mHeartbeat.Free;
  end;
end;

procedure TServerStatusHeartbeatTests.BeatWritesDetails;
var
  mHeartbeat: TServerStatusHeartbeat;
  mEntry: TServerStatusEntry;
  mStatus: string;
  mPid: Cardinal;
  mWritten: TDateTime;
begin
  FActivity.Describe(TServerStatusEntry.cKindLsp, '', '');
  FActivity.SetDetails(
    function: TServerDetails
    var
      mJson: TJSONObject;
    begin
      Result := Default(TServerDetails);
      Result.Roots := TArray<string>.Create('C:\Projekte\App');
      Result.State := 'loading';
      mJson := TJSONObject.Create;
      mJson.AddPair('units', TJSONNumber.Create(12));
      Result.Status := mJson;
    end);
  mHeartbeat := TServerStatusHeartbeat.Create(FRoot, cPid, FActivity, 0);
  try
    mHeartbeat.Beat;
    mEntry := OnlyEntry(FRoot);
    Assert.AreEqual('loading', mEntry.State);
    Assert.IsTrue(mEntry.Status.Contains('"units":12'), mEntry.Status);
    // get_server_status findet den Status über den Ordner.
    Assert.IsTrue(TServerStatusFile.Find(FRoot, 'C:\Projekte\App\Source', Now, mStatus, mPid, mWritten));
    Assert.AreEqual<Cardinal>(cPid, mPid);
  finally
    mHeartbeat.Free;
  end;
  FActivity.SetDetails(nil);
end;

procedure TServerStatusHeartbeatTests.DisabledDeletesFile;
var
  mHeartbeat: TServerStatusHeartbeat;
begin
  mHeartbeat := TServerStatusHeartbeat.Create(FRoot, cPid, FActivity, 0);
  try
    mHeartbeat.Beat;
    Assert.IsTrue(TFile.Exists(TServerStatusFile.FileFor(FRoot, cPid)));
    FActivity.Enabled := False;
    mHeartbeat.Beat;
    Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, cPid)));
  finally
    mHeartbeat.Free;
  end;
end;

procedure TServerStatusHeartbeatTests.FreeDeletesFile;
var
  mHeartbeat: TServerStatusHeartbeat;
begin
  mHeartbeat := TServerStatusHeartbeat.Create(FRoot, cPid, FActivity, 0);
  mHeartbeat.Beat;
  Assert.IsTrue(TFile.Exists(TServerStatusFile.FileFor(FRoot, cPid)));
  mHeartbeat.Free;
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, cPid)));
end;

procedure TServerStatusHeartbeatTests.ThreadWritesWithoutBeat;
var
  mHeartbeat: TServerStatusHeartbeat;
  mWaited: Integer;
begin
  mHeartbeat := TServerStatusHeartbeat.Create(FRoot, cPid, FActivity, 50);
  try
    // Der Thread schreibt sofort; höchstens 5 s warten.
    mWaited := 0;
    while not TFile.Exists(TServerStatusFile.FileFor(FRoot, cPid)) and (mWaited < 5000) do
    begin
      TThread.Sleep(20);
      Inc(mWaited, 20);
    end;
    Assert.IsTrue(TFile.Exists(TServerStatusFile.FileFor(FRoot, cPid)));
  finally
    mHeartbeat.Free;
  end;
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, cPid)));
end;

initialization
  TDUnitX.RegisterTestFixture(TServerStatusHeartbeatTests);

end.
