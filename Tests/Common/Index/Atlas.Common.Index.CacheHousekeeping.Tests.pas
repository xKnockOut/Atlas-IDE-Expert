unit Atlas.Common.Index.CacheHousekeeping.Tests;

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
    [Test]
    procedure KeepsProjectAndLibraryCache;
  end;

  [TestFixture]
  TIndexCacheDirectoryTests = class
  private
    FRoot: string;
    function CreateCache(const AName: string): string;
    function CreateFile(const AFileName: string; ASize: Integer): string;
  public
    [SetupFixture]
    procedure SetupFixture;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    // Die RTL legt bei der ersten fehlgeschlagenen Dateisperre (EFCreateError) Daten an, die bis Programmende bleiben; kein Leck des Testcodes.
    [IgnoreMemoryLeaks]
    procedure SecondLockFails;
    [Test]
    procedure ClearSkipsLockedCaches;
    [Test]
    procedure CleanupKeepsOwnCache;
    [Test]
    procedure DiskFileSystemOverwritesExistingFile;
    [Test]
    procedure DiskFileSystemRoundTripsBytes;
    [Test]
    procedure FileNameDependsOnlyOnSignature;
    [Test]
    procedure ProjectAndLibraryLiveUnderIdeVersion;
    [Test]
    procedure ClearRemovesNewLayoutAndEmptyFolders;
    [Test]
    procedure RemoveAndSizeOfNamedCaches;
    [Test]
    procedure ConcurrentWritersLeaveReadableCache;
    [Test]
    procedure FailedReplaceLeavesNoRemains;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.CacheHousekeeping,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Index.Adapters.DiskFileSystem;

function Info(const AName: string; ASize: Int64; AAgeDays: Integer; ALocked: Boolean = False): TCacheFileInfo;
begin
  Result.FileName := AName;
  Result.Size := ASize;
  Result.LastWrite := EncodeDate(2026, 1, 1) - AAgeDays;
  Result.Locked := ALocked;
end;

function StartWriter(const AFile, AContent: string; ARounds: Integer): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      Round: Integer;
      Disk: IIndexFileSystem;
    begin
      Disk := TDiskIndexFileSystem.Create;
      for Round := 1 to ARounds do
        Disk.WriteText(AFile, AContent);
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

/// <summary>Zwei Schreiber ersetzen AFile gleichzeitig ARounds-mal ('a…' gegen 'b…').</summary>
procedure WriteConcurrently(const AFile: string; ARounds: Integer);
var
  Writers: array[0..1] of TThread;
  Index: Integer;
begin
  Writers[0] := StartWriter(AFile, StringOfChar('a', 100000), ARounds);
  Writers[1] := StartWriter(AFile, StringOfChar('b', 100000), ARounds);
  for Index := 0 to High(Writers) do
  begin
    Writers[Index].WaitFor;
    Writers[Index].Free;
  end;
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

procedure TIndexCacheHousekeepingTests.KeepsProjectAndLibraryCache;
var
  Removed: TArray<string>;
begin
  // Der gemeinsame Bibliotheks-Cache ist nicht gesperrt und älter als der Projekt-Cache; er wurde sonst bei
  // jedem Start gelöscht (#616).
  Removed := TIndexCacheHousekeeping.SelectForRemoval([Info('bibliothek', 300, 1), Info('projekt', 10, 9),
    Info('fremd', 10, 5)], 100, TArray<string>.Create('Projekt', 'Bibliothek'));
  Assert.AreEqual<NativeInt>(1, Length(Removed));
  Assert.AreEqual('fremd', Removed[0]);
end;

{ TIndexCacheDirectoryTests }

procedure WarmUpFailures(const ARoot: string);
var
  Target: string;
  Lock, BackupLock: TFileStream;
  Disk: IIndexFileSystem;
  Missing: string;
begin
  Disk := TDiskIndexFileSystem.Create;
  Target := TPath.Combine(ARoot, 'index-00000001.json');
  Disk.WriteText(Target, 'x');
  Lock := TFileStream.Create(Target, fmOpenRead or fmShareExclusive);
  try
    Disk.WriteText(Target, 'y');
  finally
    Lock.Free;
  end;
  Disk.WriteText(Target, 'z');
  BackupLock := TFileStream.Create(Format('%s.%d.bak', [Target, TThread.CurrentThread.ThreadID]), fmCreate or
    fmShareExclusive);
  try
    Disk.WriteText(Target, 'w');
  finally
    BackupLock.Free;
  end;
  // TFile.Replace prüft, ob Quelle und Ziel existieren; im Wettlauf fehlt das Ziel kurz (EFileNotFoundException
  // mit Ressourcentext). Beide Fälle einmal auslösen.
  for Missing in [TPath.Combine(ARoot, 'fehlt-ziel.json'), TPath.Combine(ARoot, 'fehlt-quelle.json')] do
    try
      if Missing.Contains('ziel') then
        TFile.Replace(Target, Missing, Target + '.bak')
      else
        TFile.Replace(Missing, Target, Target + '.bak');
    except
      on Exception do
        ;
    end;
  // Dasselbe in einem anderen Thread: Thread-lokale Daten der RTL legt jeder Thread selbst an.
  with TThread.CreateAnonymousThread(
    procedure
    var
      ThreadLock: TFileStream;
    begin
      ThreadLock := TFileStream.Create(Target, fmOpenRead or fmShareExclusive);
      try
        Disk.WriteText(Target, 'v');
      finally
        ThreadLock.Free;
      end;
    end) do
  begin
    FreeOnTerminate := False;
    Start;
    WaitFor;
    Free;
  end;
end;

procedure TIndexCacheDirectoryTests.SetupFixture;
var
  Root: string;
begin
  // Gleichzeitiges Ersetzen löst Fehler aus, deren Meldungstexte die RTL beim ersten Mal
  // bis Programmende zwischenspeichert. Einmal vorab durchlaufen, damit der Leck-Monitor
  // in ConcurrentWritersLeaveReadableCache nur den Speicher des Tests sieht.
  Root := TPath.Combine(TPath.GetTempPath, 'AtlasCacheWarmup' + IntToStr(TThread.GetTickCount64));
  ForceDirectories(Root);
  try
    WriteConcurrently(TPath.Combine(Root, 'index-00000000.json'), 50);
    // Die Fehlerpfade gezielt, nicht nur zufällig: Ziel gesperrt (Replace scheitert), Ziel und
    // Sicherung gesperrt, Ziel fehlt.
    WarmUpFailures(Root);
  finally
    TDirectory.Delete(Root, True);
  end;
end;

procedure TIndexCacheDirectoryTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'AtlasCacheTest' + IntToStr(TThread.GetTickCount64));
  ForceDirectories(FRoot);
end;

procedure TIndexCacheDirectoryTests.TearDown;
begin
  TDirectory.Delete(FRoot, True);
  // Sonst gibt erst das nächste Setup den Pfad frei (Leck-Monitor).
  FRoot := '';
end;

procedure TIndexCacheDirectoryTests.DiskFileSystemOverwritesExistingFile;
var
  FileSystem: TDiskIndexFileSystem;
  Cache, Text: string;
begin
  // Der zweite Start schreibt über einen vorhandenen Cache (TFile.Replace); das scheiterte
  // an der leeren Sicherungsdatei ("Pfad ist leer").
  Cache := CreateCache('index-00000002.json');
  FileSystem := TDiskIndexFileSystem.Create;
  try
    Assert.IsTrue(FileSystem.WriteText(Cache, '{"version":2}'));
    Assert.IsTrue(FileSystem.ReadText(Cache, Text));
    Assert.AreEqual('{"version":2}', Text);
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FRoot))), 'keine .tmp- oder .bak-Reste');
  finally
    FileSystem.Free;
  end;
end;

procedure TIndexCacheDirectoryTests.DiskFileSystemRoundTripsBytes;
var
  FileSystem: TDiskIndexFileSystem;
  Cache: string;
  Data: TBytes;
begin
  // Binärer Cache (#617): Bytes kommen unverändert zurück, auch Nullbytes; fehlende Datei = False.
  Cache := CreateCache('index-00000003.json');
  FileSystem := TDiskIndexFileSystem.Create;
  try
    Assert.IsTrue(FileSystem.WriteBytes(Cache, TBytes.Create(0, 1, 255, 0, 13, 10)));
    Assert.IsTrue(FileSystem.ReadBytes(Cache, Data));
    Assert.AreEqual<NativeInt>(6, Length(Data));
    Assert.AreEqual<Byte>(255, Data[2]);
    Assert.AreEqual<Byte>(0, Data[3]);
    Assert.IsFalse(FileSystem.ReadBytes(TPath.Combine(FRoot, 'fehlt.json'), Data));
    Assert.AreEqual<NativeInt>(0, Length(Data));
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FRoot))), 'keine .tmp- oder .bak-Reste');
  finally
    FileSystem.Free;
  end;
end;

function TIndexCacheDirectoryTests.CreateCache(const AName: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, '{}');
end;

function TIndexCacheDirectoryTests.CreateFile(const AFileName: string; ASize: Integer): string;
var
  Data: TBytes;
begin
  Result := AFileName;
  ForceDirectories(ExtractFileDir(Result));
  SetLength(Data, ASize);
  TFile.WriteAllBytes(Result, Data);
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
  Assert.AreEqual(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'C:\P\App.dproj|Debug|Win64'),
    TIndexCacheDirectory.FileFor(FRoot, '37.0', 'c:\p\app.dproj|Debug|Win64'));
  Assert.AreNotEqual(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'C:\P\App.dproj|Debug|Win64'),
    TIndexCacheDirectory.FileFor(FRoot, '37.0', 'C:\P\App.dproj|Release|Win64'));
  Assert.AreEqual(16, Integer(Length(TIndexCacheDirectory.KeyHash('x'))));
end;

procedure TIndexCacheDirectoryTests.ProjectAndLibraryLiveUnderIdeVersion;
var
  Version: string;
begin
  // Je IDE-Version ein Ordner, darin je Projekt einer; die Bibliothek getrennt (#492).
  Version := TPath.Combine(TPath.Combine(FRoot, 'Index'), '37.0');
  Assert.AreEqual(TPath.Combine(TPath.Combine(Version, TIndexCacheDirectory.KeyHash('Projekt')), 'index.atlasidx'),
    TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'));
  Assert.AreEqual(TPath.Combine(TPath.Combine(TPath.Combine(Version, 'Bibliothek'),
    TIndexCacheDirectory.KeyHash('Win64')), 'index.atlasidx'),
    TIndexCacheDirectory.LibraryFileFor(FRoot, '37.0', 'Win64'));
  Assert.AreNotEqual(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'),
    TIndexCacheDirectory.FileFor(FRoot, '23.0', 'Projekt'));
  Assert.AreEqual(TPath.Combine(TPath.Combine(FRoot, 'Index'), 'ohne-Delphi'),
    TIndexCacheDirectory.VersionFolder(FRoot, ''));
end;

procedure TIndexCacheDirectoryTests.ClearRemovesNewLayoutAndEmptyFolders;
var
  Project, Library_, Legacy: string;
begin
  Project := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'), 100);
  Library_ := CreateFile(TIndexCacheDirectory.LibraryFileFor(FRoot, '37.0', 'Win64'), 200);
  Legacy := CreateCache('index-00000001.json');
  CreateCache('anderes.json');
  Assert.AreEqual<Int64>(300 + 2, TIndexCacheDirectory.TotalSize(FRoot));
  Assert.AreEqual(3, TIndexCacheDirectory.Clear(FRoot));
  Assert.IsFalse(FileExists(Project));
  Assert.IsFalse(FileExists(Library_));
  Assert.IsFalse(FileExists(Legacy));
  // Leere Projektordner gehen mit, fremde Dateien bleiben.
  Assert.IsFalse(TDirectory.Exists(ExtractFileDir(Project)));
  Assert.IsTrue(FileExists(TPath.Combine(FRoot, 'anderes.json')));
  Assert.AreEqual<Int64>(0, TIndexCacheDirectory.TotalSize(FRoot));
end;

procedure TIndexCacheDirectoryTests.RemoveAndSizeOfNamedCaches;
var
  First, Second: string;
  Lock: TStream;
begin
  First := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Eins'), 10);
  Second := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Zwei'), 20);
  Assert.AreEqual<Int64>(30, TIndexCacheDirectory.SizeOf([First, Second, '', First + '.fehlt']));
  Lock := TIndexCacheDirectory.TryLock(Second);
  try
    // Die gesperrte Datei hält eine andere Instanz: bleibt.
    Assert.AreEqual(1, TIndexCacheDirectory.Remove([First, Second, '']));
  finally
    Lock.Free;
  end;
  Assert.IsFalse(FileExists(First));
  Assert.IsTrue(FileExists(Second));
end;

procedure TIndexCacheDirectoryTests.ConcurrentWritersLeaveReadableCache;
var
  Cache: string;
  Text: string;
  FileSystem: IIndexFileSystem;
begin
  // Zwei Schreiber, die gleichzeitig ersetzen (#62): Am Ende steht einer der beiden
  // Stände vollständig in der Datei, nie ein halber.
  Cache := TPath.Combine(FRoot, 'index-00000003.json');
  WriteConcurrently(Cache, 50);
  FileSystem := TDiskIndexFileSystem.Create;
  Assert.IsTrue(FileSystem.ReadText(Cache, Text));
  Assert.IsTrue((Text = StringOfChar('a', 100000)) or (Text = StringOfChar('b', 100000)));
  // Keine temporären Dateien zurückgelassen.
  Assert.AreEqual<NativeInt>(1, Length(TDirectory.GetFiles(FRoot)));
end;

procedure TIndexCacheDirectoryTests.FailedReplaceLeavesNoRemains;
var
  Cache, Text: string;
  Lock: TFileStream;
  FileSystem: IIndexFileSystem;
begin
  // Der Fehlerpfad aus ConcurrentWritersLeaveReadableCache, aber deterministisch: Ist das Ziel
  // gesperrt, scheitert ReplaceFile, ohne dass TFile.Replace eine Ausnahme wirft. Früher meldete
  // WriteText dann Erfolg und ließ die temporäre Datei liegen.
  Cache := CreateCache('index-00000004.json');
  FileSystem := TDiskIndexFileSystem.Create;
  Lock := TFileStream.Create(Cache, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(FileSystem.WriteText(Cache, '{"version":2}'));
  finally
    Lock.Free;
  end;
  Assert.IsTrue(FileSystem.ReadText(Cache, Text));
  Assert.AreEqual('{}', Text, 'alter Stand vollständig erhalten');
  Assert.AreEqual<NativeInt>(1, Length(TDirectory.GetFiles(FRoot)), 'keine .tmp- oder .bak-Reste');
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexCacheHousekeepingTests);
  TDUnitX.RegisterTestFixture(TIndexCacheDirectoryTests);

end.
