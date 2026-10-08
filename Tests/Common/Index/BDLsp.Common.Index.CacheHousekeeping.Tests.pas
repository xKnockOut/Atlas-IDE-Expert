unit BDLsp.Common.Index.CacheHousekeeping.Tests;

// Tests für das Aufräumen des Cache-Ordners (#184).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexCacheHousekeepingTests = class
  public
    [Test]
    procedure KeepsEverythingBelowLimit;
    [Test]
    procedure RemovesOldestFirstUntilBelowLimit;
    [Test]
    procedure NeverRemovesOwnCache;
    [Test]
    procedure NeverRemovesLockedCache;
  end;

  [TestFixture]
  TIndexCacheDirectoryTests = class
  private
    FRoot: string;
    function CreateCache(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SecondLockFails;
    [Test]
    procedure ClearSkipsLockedCaches;
    [Test]
    procedure CleanupKeepsOwnCache;
    [Test]
    procedure FileNameDependsOnlyOnSignature;
    [Test]
    procedure ConcurrentWritersLeaveReadableCache;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.CacheHousekeeping,
  BDLsp.Common.Index.Adapters.DiskFileSystem,
  BDLsp.Common.Index.Adapters.CacheDirectory;

function Info(const AName: string; ASize: Int64; AAgeDays: Integer; ALocked: Boolean = False): TCacheFileInfo;
begin
  Result.FileName := AName;
  Result.Size := ASize;
  Result.LastWrite := EncodeDate(2026, 1, 1) - AAgeDays;
  Result.Locked := ALocked;
end;

{ TIndexCacheHousekeepingTests }

procedure TIndexCacheHousekeepingTests.KeepsEverythingBelowLimit;
begin
  Assert.AreEqual<NativeInt>(0, Length(TIndexCacheHousekeeping.SelectForRemoval(
    [Info('a', 10, 5), Info('b', 10, 1)], 20, '')));
end;

procedure TIndexCacheHousekeepingTests.RemovesOldestFirstUntilBelowLimit;
var
  Removed: TArray<string>;
begin
  Removed := TIndexCacheHousekeeping.SelectForRemoval(
    [Info('neu', 10, 1), Info('alt', 10, 9), Info('mittel', 10, 5)], 15, '');
  Assert.AreEqual<NativeInt>(2, Length(Removed));
  Assert.AreEqual('alt', Removed[0]);
  Assert.AreEqual('mittel', Removed[1]);
end;

procedure TIndexCacheHousekeepingTests.NeverRemovesOwnCache;
var
  Removed: TArray<string>;
begin
  Removed := TIndexCacheHousekeeping.SelectForRemoval([Info('Eigen', 10, 9), Info('b', 10, 1)], 10, 'eigen');
  Assert.AreEqual<NativeInt>(1, Length(Removed));
  Assert.AreEqual('b', Removed[0]);
end;

procedure TIndexCacheHousekeepingTests.NeverRemovesLockedCache;
var
  Removed: TArray<string>;
begin
  Removed := TIndexCacheHousekeeping.SelectForRemoval([Info('a', 10, 9, True), Info('b', 10, 1, True)], 0, '');
  Assert.AreEqual<NativeInt>(0, Length(Removed));
end;

{ TIndexCacheDirectoryTests }

procedure TIndexCacheDirectoryTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'BDLspCacheTest' + IntToStr(TThread.GetTickCount64));
  ForceDirectories(FRoot);
end;

procedure TIndexCacheDirectoryTests.TearDown;
begin
  TDirectory.Delete(FRoot, True);
end;

function TIndexCacheDirectoryTests.CreateCache(const AName: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, '{}');
end;

procedure TIndexCacheDirectoryTests.SecondLockFails;
var
  First, Second: TStream;
  Cache: string;
begin
  Cache := CreateCache('index-00000001.json');
  First := TIndexCacheDirectory.TryLock(Cache);
  try
    Assert.IsTrue(First <> nil);
    Second := TIndexCacheDirectory.TryLock(Cache);
    Assert.IsTrue(Second = nil);
    Assert.IsTrue(TIndexCacheDirectory.IsLocked(Cache));
  finally
    First.Free;
  end;
  Assert.IsFalse(TIndexCacheDirectory.IsLocked(Cache));
end;

procedure TIndexCacheDirectoryTests.ClearSkipsLockedCaches;
var
  Lock: TStream;
  Locked: string;
begin
  CreateCache('index-00000001.json');
  Locked := CreateCache('index-00000002.json');
  CreateCache('anderes.json');
  Lock := TIndexCacheDirectory.TryLock(Locked);
  try
    Assert.AreEqual(1, TIndexCacheDirectory.Clear(FRoot));
    Assert.IsTrue(FileExists(Locked));
    Assert.IsTrue(FileExists(TPath.Combine(FRoot, 'anderes.json')));
  finally
    Lock.Free;
  end;
end;

procedure TIndexCacheDirectoryTests.CleanupKeepsOwnCache;
var
  Own: string;
begin
  Own := CreateCache('index-00000001.json');
  CreateCache('index-00000002.json');
  Assert.AreEqual(1, TIndexCacheDirectory.Cleanup(FRoot, 0, Own));
  Assert.IsTrue(FileExists(Own));
end;

procedure TIndexCacheDirectoryTests.FileNameDependsOnlyOnSignature;
begin
  // LSP- und MCP-Prozess bilden denselben Namen (#62).
  Assert.AreEqual(TIndexCacheDirectory.FileFor(FRoot, 'C:\P\App.dproj|Debug|Win64'),
    TIndexCacheDirectory.FileFor(FRoot, 'C:\P\App.dproj|Debug|Win64'));
  Assert.AreNotEqual(TIndexCacheDirectory.FileFor(FRoot, 'C:\P\App.dproj|Debug|Win64'),
    TIndexCacheDirectory.FileFor(FRoot, 'C:\P\App.dproj|Release|Win64'));
  Assert.StartsWith(TPath.Combine(FRoot, 'index-'), TIndexCacheDirectory.FileFor(FRoot, 'x'));
end;

procedure TIndexCacheDirectoryTests.ConcurrentWritersLeaveReadableCache;
const
  Rounds = 50;
var
  Cache: string;
  Writers: array[0..1] of TThread;
  Index: Integer;
  Text: string;
  FileSystem: IIndexFileSystem;

  function StartWriter(const AFile, AContent: string): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        Round: Integer;
        Disk: IIndexFileSystem;
      begin
        Disk := TDiskIndexFileSystem.Create;
        for Round := 1 to Rounds do
          Disk.WriteText(AFile, AContent);
      end);
    Result.FreeOnTerminate := False;
    Result.Start;
  end;

begin
  // Zwei Schreiber, die gleichzeitig ersetzen (#62): Am Ende steht einer der beiden
  // Stände vollständig in der Datei, nie ein halber.
  Cache := TPath.Combine(FRoot, 'index-00000003.json');
  Writers[0] := StartWriter(Cache, StringOfChar('a', 100000));
  Writers[1] := StartWriter(Cache, StringOfChar('b', 100000));
  for Index := 0 to High(Writers) do
  begin
    Writers[Index].WaitFor;
    Writers[Index].Free;
  end;
  FileSystem := TDiskIndexFileSystem.Create;
  Assert.IsTrue(FileSystem.ReadText(Cache, Text));
  Assert.IsTrue((Text = StringOfChar('a', 100000)) or (Text = StringOfChar('b', 100000)));
  // Keine temporären Dateien zurückgelassen.
  Assert.AreEqual<NativeInt>(1, Length(TDirectory.GetFiles(FRoot)));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexCacheHousekeepingTests);
  TDUnitX.RegisterTestFixture(TIndexCacheDirectoryTests);

end.
