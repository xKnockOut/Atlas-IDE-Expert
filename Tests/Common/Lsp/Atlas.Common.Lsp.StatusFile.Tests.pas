unit Atlas.Common.Lsp.StatusFile.Tests;

// Tests für die Statusdatei des Servers (#1356, #1901), aus der get_server_status die
// Zahlen des Fensters „Atlas-Server“ und AtlasMonitor alle Server liest: Schreiben,
// Finden je Ordner, Alter, Auswahl der jüngsten Datei, Aufräumen, Liste aller Server.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TServerStatusFileTests = class
  private
    FRoot: string;
    procedure WriteStatus(APid: Cardinal; const ARoot: string; AUnits: Integer; AWritten: TDateTime);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsStatusForFolderUnderRoot;
    [Test]
    procedure IgnoresOtherFolders;
    [Test]
    procedure IgnoresStaleStatus;
    [Test]
    procedure PicksNewestServer;
    [Test]
    procedure DeleteRemovesOwnFile;
    [Test]
    procedure WriteCleansUpOrphans;
    [Test]
    procedure MatchesParentAndChildFolders;
    [Test]
    procedure EntryKeepsAllFields;
    [Test]
    procedure FindIgnoresOtherKinds;
    [Test]
    procedure ListOrdersByStart;
    [Test]
    procedure ListDeletesDeadAndOrphans;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Common.Lsp.StatusFile;

const
  cBase: TDateTime = 46324.5;

procedure TServerStatusFileTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atlas-StatusFile-' + IntToStr(Random(MaxInt)));
end;

procedure TServerStatusFileTests.TearDown;
begin
  if TDirectory.Exists(FRoot) then
  begin
    TDirectory.Delete(FRoot, True);
  end;
  FRoot := '';
end;

procedure TServerStatusFileTests.WriteStatus(APid: Cardinal; const ARoot: string; AUnits: Integer;
  AWritten: TDateTime);
var
  mStatus: TJSONObject;
begin
  mStatus := TJSONObject.Create;
  try
    mStatus.AddPair('units', TJSONNumber.Create(AUnits));
    TServerStatusFile.Write(FRoot, APid, [ARoot], mStatus, AWritten);
  finally
    mStatus.Free;
  end;
end;

procedure TServerStatusFileTests.FindsStatusForFolderUnderRoot;
var
  mStatus: string;
  mPid: Cardinal;
  mWritten: TDateTime;
begin
  WriteStatus(11, TPath.Combine(FRoot, 'Projekt'), 42, cBase);
  Assert.IsTrue(TServerStatusFile.Find(FRoot, TPath.Combine(FRoot, 'Projekt'), cBase + 5 * OneSecond, mStatus,
    mPid, mWritten));
  Assert.AreEqual<Cardinal>(11, mPid);
  Assert.IsTrue(mStatus.Contains('"units":42'), mStatus);
  Assert.IsTrue(Abs(mWritten - cBase) < OneSecond);
end;

procedure TServerStatusFileTests.IgnoresOtherFolders;
var
  mStatus: string;
  mPid: Cardinal;
  mWritten: TDateTime;
begin
  WriteStatus(11, TPath.Combine(FRoot, 'Projekt'), 42, cBase);
  Assert.IsFalse(TServerStatusFile.Find(FRoot, TPath.Combine(FRoot, 'Anderes'), cBase, mStatus, mPid, mWritten));
end;

procedure TServerStatusFileTests.IgnoresStaleStatus;
var
  mStatus: string;
  mPid: Cardinal;
  mWritten: TDateTime;
begin
  WriteStatus(11, TPath.Combine(FRoot, 'Projekt'), 42, cBase);
  Assert.IsFalse(TServerStatusFile.Find(FRoot, TPath.Combine(FRoot, 'Projekt'),
    cBase + (TServerStatusFile.cMaxAgeSeconds + 5) * OneSecond, mStatus, mPid, mWritten));
end;

procedure TServerStatusFileTests.PicksNewestServer;
var
  mStatus: string;
  mPid: Cardinal;
  mWritten: TDateTime;
begin
  WriteStatus(11, TPath.Combine(FRoot, 'Projekt'), 1, cBase);
  WriteStatus(22, TPath.Combine(FRoot, 'Projekt'), 2, cBase + 2 * OneSecond);
  Assert.IsTrue(TServerStatusFile.Find(FRoot, TPath.Combine(FRoot, 'Projekt'), cBase + 3 * OneSecond, mStatus,
    mPid, mWritten));
  Assert.AreEqual<Cardinal>(22, mPid);
  Assert.IsTrue(mStatus.Contains('"units":2'), mStatus);
end;

procedure TServerStatusFileTests.DeleteRemovesOwnFile;
begin
  WriteStatus(11, TPath.Combine(FRoot, 'Projekt'), 1, cBase);
  Assert.IsTrue(TFile.Exists(TServerStatusFile.FileFor(FRoot, 11)));
  TServerStatusFile.Delete(FRoot, 11);
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, 11)));
  // Ohne Datei still.
  TServerStatusFile.Delete(FRoot, 11);
end;

procedure TServerStatusFileTests.WriteCleansUpOrphans;
begin
  WriteStatus(11, TPath.Combine(FRoot, 'Projekt'), 1, cBase);
  TFile.WriteAllText(TPath.Combine(TServerStatusFile.FolderOf(FRoot), 'server-99.json'), 'kaputt');
  // Weit später schreibt ein anderer Server: die alte und die unlesbare Datei verschwinden.
  WriteStatus(22, TPath.Combine(FRoot, 'Projekt'), 2, cBase + 1);
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, 11)));
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, 99)));
  Assert.IsTrue(TFile.Exists(TServerStatusFile.FileFor(FRoot, 22)));
end;

procedure TServerStatusFileTests.MatchesParentAndChildFolders;
begin
  Assert.IsTrue(TServerStatusFile.Matches(['C:\Projekte\App'], 'c:\projekte\app\'));
  Assert.IsTrue(TServerStatusFile.Matches(['C:\Projekte\App'], 'C:\Projekte\App\Source'));
  Assert.IsTrue(TServerStatusFile.Matches(['C:\Projekte\App\Source'], 'C:\Projekte\App'));
  Assert.IsFalse(TServerStatusFile.Matches(['C:\Projekte\App'], 'C:\Projekte\Application'));
  Assert.IsFalse(TServerStatusFile.Matches([], 'C:\Projekte\App'));
end;

/// <summary>Eintrag mit allen Feldern für AKind und APid.</summary>
function SampleEntry(const AKind: string; APid: Cardinal; AStarted: TDateTime): TServerStatusEntry;
begin
  Result := Default(TServerStatusEntry);
  Result.Pid := APid;
  Result.Roots := TArray<string>.Create('C:\Projekte\App');
  Result.Kind := AKind;
  Result.Command := 'check';
  Result.Target := 'C:\Projekte\App\App.dproj';
  Result.LogFile := 'C:\Logs\server.log';
  Result.Version := '2.1.0';
  Result.Started := AStarted;
  Result.MemoryBytes := 123456789;
  Result.State := TServerStatusEntry.cStateWorking;
  Result.Running := 2;
  Result.RunningMethod := 'textDocument/hover';
  Result.RunningMs := 4200;
  Result.Done := 3;
  Result.Total := 10;
  Result.Timeouts := 1;
  Result.Errors := 5;
end;

procedure TServerStatusFileTests.EntryKeepsAllFields;
var
  mEntries: TArray<TServerStatusEntry>;
  mEntry: TServerStatusEntry;
begin
  TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindCli, 7, cBase - 1), nil, cBase);
  mEntries := TServerStatusFile.List(FRoot, cBase + OneSecond, nil);
  Assert.AreEqual(1, Integer(Length(mEntries)));
  mEntry := mEntries[0];
  Assert.AreEqual<Cardinal>(7, mEntry.Pid);
  Assert.AreEqual('cli', mEntry.Kind);
  Assert.AreEqual('check', mEntry.Command);
  Assert.AreEqual('C:\Projekte\App\App.dproj', mEntry.Target);
  Assert.AreEqual('C:\Logs\server.log', mEntry.LogFile);
  Assert.AreEqual('2.1.0', mEntry.Version);
  Assert.IsTrue(Abs(mEntry.Started - (cBase - 1)) < OneSecond);
  Assert.IsTrue(Abs(mEntry.Written - cBase) < OneSecond);
  Assert.AreEqual<Int64>(123456789, mEntry.MemoryBytes);
  Assert.AreEqual('working', mEntry.State);
  Assert.AreEqual(2, mEntry.Running);
  Assert.AreEqual('textDocument/hover', mEntry.RunningMethod);
  Assert.AreEqual<Int64>(4200, mEntry.RunningMs);
  Assert.AreEqual(3, mEntry.Done);
  Assert.AreEqual(10, mEntry.Total);
  Assert.AreEqual(1, mEntry.Timeouts);
  Assert.AreEqual(5, mEntry.Errors);
  Assert.AreEqual(1, Integer(Length(mEntry.Roots)));
  Assert.AreEqual('', mEntry.Status, 'ohne ausführlichen Status');
  Assert.AreEqual(TServerStatusFile.FileFor(FRoot, 7), mEntry.FileName);
  mEntries := nil;
end;

procedure TServerStatusFileTests.FindIgnoresOtherKinds;
var
  mStatus: string;
  mPid: Cardinal;
  mWritten: TDateTime;
  mJson: TJSONObject;
begin
  mJson := TJSONObject.Create;
  try
    mJson.AddPair('units', TJSONNumber.Create(3));
    // Ein MCP-Server mit Status gilt nicht als Server der IDE.
    TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindMcp, 8, cBase), mJson, cBase);
  finally
    mJson.Free;
  end;
  Assert.IsFalse(TServerStatusFile.Find(FRoot, 'C:\Projekte\App', cBase, mStatus, mPid, mWritten));
  WriteStatus(9, 'C:\Projekte\App', 4, cBase);
  Assert.IsTrue(TServerStatusFile.Find(FRoot, 'C:\Projekte\App', cBase, mStatus, mPid, mWritten));
  Assert.AreEqual<Cardinal>(9, mPid);
end;

procedure TServerStatusFileTests.ListOrdersByStart;
var
  mEntries: TArray<TServerStatusEntry>;
begin
  TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindLsp, 30, cBase - 2 * OneHour), nil, cBase);
  TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindMcp, 20, cBase - 3 * OneHour), nil, cBase);
  TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindCli, 10, cBase - 2 * OneHour), nil, cBase);
  mEntries := TServerStatusFile.List(FRoot, cBase, nil);
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual<Cardinal>(20, mEntries[0].Pid, 'zuerst gestartet');
  Assert.AreEqual<Cardinal>(10, mEntries[1].Pid, 'gleicher Start: kleinere pid');
  Assert.AreEqual<Cardinal>(30, mEntries[2].Pid);
  mEntries := nil;
end;

procedure TServerStatusFileTests.ListDeletesDeadAndOrphans;
var
  mEntries: TArray<TServerStatusEntry>;
begin
  TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindLsp, 41, cBase), nil, cBase);
  TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindLsp, 42, cBase), nil, cBase);
  // Weit später geschrieben, damit 41 und 42 beim Schreiben noch nicht als verwaist gelten.
  TServerStatusFile.Write(FRoot, SampleEntry(TServerStatusEntry.cKindLsp, 43, cBase), nil,
    cBase + (TServerStatusFile.cOrphanSeconds - 10) * OneSecond);
  mEntries := TServerStatusFile.List(FRoot, cBase + (TServerStatusFile.cOrphanSeconds + 5) * OneSecond,
    function(APid: Cardinal): Boolean
    begin
      Result := APid <> 42;
    end);
  // 41 und 42 sind verwaist (zu alt), 43 lebt.
  Assert.AreEqual(1, Integer(Length(mEntries)));
  Assert.AreEqual<Cardinal>(43, mEntries[0].Pid);
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, 41)));
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, 42)));
  // Ein beendeter Prozess verschwindet sofort.
  mEntries := TServerStatusFile.List(FRoot, cBase + (TServerStatusFile.cOrphanSeconds + 5) * OneSecond,
    function(APid: Cardinal): Boolean
    begin
      Result := False;
    end);
  Assert.AreEqual(0, Integer(Length(mEntries)));
  Assert.IsFalse(TFile.Exists(TServerStatusFile.FileFor(FRoot, 43)));
end;

initialization
  TDUnitX.RegisterTestFixture(TServerStatusFileTests);

end.
