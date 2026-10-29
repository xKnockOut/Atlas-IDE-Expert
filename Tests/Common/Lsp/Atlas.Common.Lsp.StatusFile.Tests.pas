unit Atlas.Common.Lsp.StatusFile.Tests;

// Tests für die Statusdatei des Servers (#1356), aus der get_server_status die
// Zahlen des Fensters „Atlas-Server“ liest: Schreiben, Finden je Ordner,
// Alter, Auswahl der jüngsten Datei und Aufräumen.

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
    TDirectory.Delete(FRoot, True);
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
    cBase + (TServerStatusFile.MaxAgeSeconds + 5) * OneSecond, mStatus, mPid, mWritten));
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

initialization
  TDUnitX.RegisterTestFixture(TServerStatusFileTests);

end.
