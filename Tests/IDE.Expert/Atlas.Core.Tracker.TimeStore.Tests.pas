unit Atlas.Core.Tracker.TimeStore.Tests;

// Ablage der erfassten Zeit (#1267) ohne IDE: Spannen der Uhr in time.json,
// noch nicht geschriebene Spannen bei gesperrter Datei, Meldung nur beim ersten
// Fehlschlag einer Reihe, Summe des aktuellen Issues, Abziehen und Setzen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Tracker.TimeClock,
  Atlas.Core.Tracker.TimeStore;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTimeStoreTests = class
  private
    FFolder: string;
    FNow: TDateTime;
    FFailures: Integer;
    FClock: TAtlasTimeClock;
    FStore: TAtlasTimeStore;
    function Path: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FlushWritesClockSpans;
    /// <summary>Gesperrte Datei: Die Spannen bleiben im Speicher und zählen weiter; gemeldet wird nur der erste
    /// Fehlschlag, nach einem Erfolg wieder.</summary>
    [Test]
    procedure LockedFileKeepsSpansAndReportsOnce;
    [Test]
    procedure SubtractAndSetTotal;
    /// <summary>Wechsel auf ein Issue mit Zeit aus einer früheren Sitzung: Die Summe kommt aus der Datei.</summary>
    [Test]
    procedure SelectReadsSavedTotal;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.Adapters.LocalFiles,
  Atlas.Core.Tracker.TimeLog;

function Issue(const AKey: string): TAtlasTimeIssue;
begin
  Result := TAtlasTimeIssue.Create('youtrack', 'https://yt.beispiel.de/', 'ATL', AKey);
end;

function At(AHour, AMinute: Word): TDateTime;
begin
  Result := EncodeDateTime(2026, 10, 28, AHour, AMinute, 0, 0);
end;

{ TAtlasTimeStoreTests }

function TAtlasTimeStoreTests.Path: string;
begin
  Result := TPath.Combine(FFolder, TAtlasTimeFile.cFileName);
end;

procedure TAtlasTimeStoreTests.Setup;
begin
  TAtlasTrackerFiles.Install(TAtlasTrackerLocalFiles.Create, nil);
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-timestore-' + TGUID.NewGuid.ToString);
  ForceDirectories(FFolder);
  FNow := At(10, 0);
  FFailures := 0;
  FClock := TAtlasTimeClock.Create(
    function: TDateTime
    begin
      Result := FNow;
    end, 10);
  FStore := TAtlasTimeStore.Create(Path, FClock,
    procedure
    begin
      Inc(FFailures);
    end);
end;

procedure TAtlasTimeStoreTests.TearDown;
begin
  FreeAndNil(FStore);
  FreeAndNil(FClock);
  TAtlasTrackerFiles.Uninstall;
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TAtlasTimeStoreTests.FlushWritesClockSpans;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 30));
  FNow := At(10, 30);
  Assert.AreEqual(30 * 60, Integer(FStore.CurrentTotal), 'vor dem Schreiben aus der Uhr');
  FStore.Flush;
  Assert.AreEqual(30 * 60, Integer(FStore.SavedTotal(Issue('ATL-1'))), 'in der Datei');
  Assert.AreEqual(30 * 60, Integer(FStore.CurrentTotal), 'nach dem Schreiben nicht doppelt');
  Assert.AreEqual(0, FFailures);
end;

procedure TAtlasTimeStoreTests.LockedFileKeepsSpansAndReportsOnce;
var
  mLock: TStream;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 20));
  FNow := At(10, 20);
  mLock := TFileStream.Create(Path + TAtlasTimeFile.cLockExtension, fmCreate or fmShareExclusive);
  try
    Assert.IsFalse(FStore.Change(nil));
    FClock.Activity(At(10, 30));
    FNow := At(10, 30);
    FStore.Flush;
    Assert.AreEqual(1, FFailures, 'nur der erste Fehlschlag');
    Assert.AreEqual(30 * 60, Integer(FStore.CurrentTotal), 'ungeschriebene Spannen zählen mit');
  finally
    mLock.Free;
  end;
  Assert.IsTrue(FStore.Change(nil));
  Assert.AreEqual(30 * 60, Integer(FStore.SavedTotal(Issue('ATL-1'))), 'beim nächsten Mal mitgeschrieben');
  mLock := TFileStream.Create(Path + TAtlasTimeFile.cLockExtension, fmCreate or fmShareExclusive);
  try
    FStore.Flush;
  finally
    mLock.Free;
  end;
  Assert.AreEqual(2, FFailures, 'nach einem Erfolg wieder gemeldet');
end;

procedure TAtlasTimeStoreTests.SubtractAndSetTotal;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 40));
  FNow := At(10, 40);
  FStore.Flush;
  FStore.Subtract(Issue('ATL-1'), 25 * 60);
  Assert.AreEqual(15 * 60, Integer(FStore.SavedTotal(Issue('ATL-1'))));
  Assert.AreEqual(15 * 60, Integer(FStore.CurrentTotal));
  FStore.SetTotal(Issue('ATL-1'), 90 * 60, At(11, 0));
  Assert.AreEqual(90 * 60, Integer(FStore.SavedTotal(Issue('ATL-1'))));
  Assert.AreEqual(90 * 60, Integer(FStore.CurrentTotal));
end;

procedure TAtlasTimeStoreTests.SelectReadsSavedTotal;
var
  mLog: TAtlasTimeLog;
begin
  Assert.IsTrue(TAtlasTimeFile.Update(Path,
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.Add(TAtlasTimeSpan.Create(Issue('ATL-2'), At(8, 0), At(8, 45)));
    end, mLog));
  FClock.SetIssue(Issue('ATL-2'));
  FStore.Select(Issue('ATL-2'));
  Assert.AreEqual(45 * 60, Integer(FStore.CurrentTotal));
  FStore.Select(TAtlasTimeIssue.None);
  Assert.AreEqual(45 * 60, Integer(FStore.CurrentTotal), 'ohne Issue bleibt die Summe');
  Assert.IsTrue(FStore.Read(mLog));
  Assert.AreEqual(45 * 60, Integer(mLog.Total(Issue('ATL-2'))));
end;

end.
