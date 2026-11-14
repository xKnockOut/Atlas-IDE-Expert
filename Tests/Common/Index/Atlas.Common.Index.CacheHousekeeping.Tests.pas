unit Atlas.Common.Index.CacheHousekeeping.Tests;

// Tests für das Aufräumen des Cache-Ordners (#184), verwaiste und ungenutzte Caches (#905).

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
    [Test]
    procedure OrphanWhenNoOriginExists;
    [Test]
    procedure OrphanNeedsKnownOrigin;
    [Test]
    procedure OrphanNeverLockedOrKept;
    [Test]
    procedure UnusedOlderThanMaxAge;
    [Test]
    procedure UnusedOffWithZeroDays;
    [Test]
    procedure MaxBytesOfZeroIsUnlimited;
  end;

  [TestFixture]
  TIndexCacheDirectoryTests = class
  private
    FRoot: string;
    function CreateCache(const AName: string): string;
    function CreateFile(const AFileName: string; ASize: Integer): string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen. Genau ein [SetupFixture] je Fixture: DUnitX führt nur
    /// eine solche Methode aus, eine zweite fiel still weg (so blieb die Sperrliste ungewärmt, SecondLockFails).
    /// </summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SecondLockFails;
    /// <summary>Eigene Sperren kennt der Prozess (#1479): auch über einen anderen Pfad zur selben Datei, und nach
    /// dem Freigeben ist die Datei wieder frei.</summary>
    [Test]
    procedure OwnLockKnownInProcess;
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
    procedure FileNameCarriesFormatVersion;
    [Test]
    procedure RemoveKeepsOriginOfOtherFormat;
    [Test]
    procedure ClearRemovesNewLayoutAndEmptyFolders;
    [Test]
    procedure RemoveAndSizeOfNamedCaches;
    [Test]
    procedure ConcurrentWritersLeaveReadableCache;
    [Test]
    procedure FailedReplaceLeavesNoRemains;
    /// <summary>Ein Schreiber je Cache: TryLockWrite ist exklusiv und nutzt die Sperrdatei, die
    /// auch Aufräumen und Leeren beachten.</summary>
    [Test]
    procedure DiskWriteLockIsExclusive;
    [Test]
    procedure RemoveOrphansDeletesCacheOfDeletedProject;
    [Test]
    procedure RemoveOrphansKeepsOwnLockedAndLibrary;
    [Test]
    procedure RemoveOrphansReadsUnitsOfOldCaches;
    [Test]
    procedure RemoveOrphansDeletesLegacyAndBuildFiles;
    [Test]
    procedure OriginExistsWithMissingDrive;
    [Test]
    procedure TouchUseRenewsLastUse;
    /// <summary>Ohne Bibliotheks- oder Suchpfad-Cache ('') legt TouchUse keine Marke im aktuellen Ordner an.</summary>
    [Test]
    procedure TouchUseIgnoresEmptyName;
    [Test]
    procedure RemoveUnusedDeletesOldCaches;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.CacheHousekeeping,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Index.Adapters.DiskFileSystem;

function Info(const AName: string; ASize: Int64; AAgeDays: Integer; ALocked: Boolean): TCacheFileInfo; overload;
begin
  Result.FileName := AName;
  Result.Size := ASize;
  Result.LastWrite := EncodeDate(2026, 1, 1) - AAgeDays;
  Result.Locked := ALocked;
  Result.Origins := nil;
end;

function Info(const AName: string; ASize: Int64; AAgeDays: Integer): TCacheFileInfo; overload;
begin
  Result := Info(AName, ASize, AAgeDays, False);
end;

function WithOrigins(const AInfo: TCacheFileInfo; const AOrigins: TArray<string>): TCacheFileInfo;
begin
  Result := AInfo;
  Result.Origins := AOrigins;
end;

/// <summary>Inhalt einer Build-Datei (#556) mit AProject.</summary>
function BuildFileText(const AProject: string): string;
begin
  Result := '{"project":"' + AProject.Replace('\', '\\') + '"}';
end;

/// <summary>Nur Dateien, die mit "da" beginnen, existieren.</summary>
function ExistsWhenNamedDa: TFunc<string, Boolean>;
begin
  Result :=
    function(APath: string): Boolean
    begin
      Result := APath.StartsWith('da');
    end;
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
      begin
        Disk.WriteText(AFile, AContent);
      end;
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

/// <summary>Zwei Schreiber ersetzen AFile gleichzeitig ARounds-mal ('a…' gegen 'b…').</summary>
procedure WriteConcurrently(const AFile: string; ARounds: Integer);
var
  mWriters: array[0..1] of TThread;
  mIndex: Integer;
begin
  mWriters[0] := StartWriter(AFile, StringOfChar('a', 100000), ARounds);
  mWriters[1] := StartWriter(AFile, StringOfChar('b', 100000), ARounds);
  for mIndex := 0 to High(mWriters) do
  begin
    mWriters[mIndex].WaitFor;
    mWriters[mIndex].Free;
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
  mRemoved: TArray<string>;
begin
  mRemoved := TIndexCacheHousekeeping.SelectForRemoval(
    [Info('neu', 10, 1), Info('alt', 10, 9), Info('mittel', 10, 5)], 15, '');
  Assert.AreEqual<NativeInt>(2, Length(mRemoved));
  Assert.AreEqual('alt', mRemoved[0]);
  Assert.AreEqual('mittel', mRemoved[1]);
end;

procedure TIndexCacheHousekeepingTests.NeverRemovesOwnCache;
var
  mRemoved: TArray<string>;
begin
  mRemoved := TIndexCacheHousekeeping.SelectForRemoval([Info('Eigen', 10, 9), Info('b', 10, 1)], 10, 'eigen');
  Assert.AreEqual<NativeInt>(1, Length(mRemoved));
  Assert.AreEqual('b', mRemoved[0]);
end;

procedure TIndexCacheHousekeepingTests.NeverRemovesLockedCache;
var
  mRemoved: TArray<string>;
begin
  mRemoved := TIndexCacheHousekeeping.SelectForRemoval([Info('a', 10, 9, True), Info('b', 10, 1, True)], 0, '');
  Assert.AreEqual<NativeInt>(0, Length(mRemoved));
end;

procedure TIndexCacheHousekeepingTests.KeepsProjectAndLibraryCache;
var
  mRemoved: TArray<string>;
begin
  // Der gemeinsame Bibliotheks-Cache ist nicht gesperrt und älter als der Projekt-Cache; er wurde sonst bei
  // jedem Start gelöscht (#616).
  mRemoved := TIndexCacheHousekeeping.SelectForRemoval([Info('bibliothek', 300, 1), Info('projekt', 10, 9),
    Info('fremd', 10, 5)], 100, TArray<string>.Create('Projekt', 'Bibliothek'));
  Assert.AreEqual<NativeInt>(1, Length(mRemoved));
  Assert.AreEqual('fremd', mRemoved[0]);
end;

procedure TIndexCacheHousekeepingTests.OrphanWhenNoOriginExists;
var
  mRemoved: TArray<string>;
begin
  // Ein Cache lebt, solange irgendeine seiner Herkunftsdateien existiert.
  mRemoved := TIndexCacheHousekeeping.SelectOrphans([WithOrigins(Info('weg', 10, 1), ['fehlt.dproj']),
    WithOrigins(Info('teils', 10, 1), ['fehlt.pas', 'da.pas']), WithOrigins(Info('ganz', 10, 1), ['da.dproj'])],
    nil, ExistsWhenNamedDa());
  Assert.AreEqual<NativeInt>(1, Length(mRemoved));
  Assert.AreEqual('weg', mRemoved[0]);
end;

procedure TIndexCacheHousekeepingTests.OrphanNeedsKnownOrigin;
begin
  // Ohne Herkunft (Bibliothek, unlesbarer Cache) wird nichts entschieden.
  Assert.AreEqual<NativeInt>(0, Length(TIndexCacheHousekeeping.SelectOrphans([Info('unbekannt', 10, 1),
    WithOrigins(Info('leer', 10, 1), [''])], nil, ExistsWhenNamedDa())));
end;

procedure TIndexCacheHousekeepingTests.OrphanNeverLockedOrKept;
begin
  Assert.AreEqual<NativeInt>(0, Length(TIndexCacheHousekeeping.SelectOrphans([
    WithOrigins(Info('gesperrt', 10, 1, True), ['fehlt']), WithOrigins(Info('Eigen', 10, 1), ['fehlt'])],
    TArray<string>.Create('eigen'), ExistsWhenNamedDa())));
end;

procedure TIndexCacheHousekeepingTests.UnusedOlderThanMaxAge;
var
  mRemoved: TArray<string>;
begin
  // Info: LastWrite = 1.1.2026 minus Alter in Tagen.
  mRemoved := TIndexCacheHousekeeping.SelectUnused([Info('alt', 10, 20), Info('neu', 10, 3),
    Info('alt-gesperrt', 10, 30, True), Info('alt-eigen', 10, 30)], TArray<string>.Create('alt-eigen'),
    EncodeDate(2026, 1, 1), 14);
  Assert.AreEqual<NativeInt>(1, Length(mRemoved));
  Assert.AreEqual('alt', mRemoved[0]);
end;

procedure TIndexCacheHousekeepingTests.UnusedOffWithZeroDays;
begin
  Assert.AreEqual<NativeInt>(0, Length(TIndexCacheHousekeeping.SelectUnused([Info('uralt', 10, 3000)], nil,
    EncodeDate(2026, 1, 1), 0)));
end;

procedure TIndexCacheHousekeepingTests.MaxBytesOfZeroIsUnlimited;
begin
  Assert.AreEqual<Int64>(Int64(256) * 1024 * 1024, TIndexCacheHousekeeping.MaxBytesOf(256));
  Assert.AreEqual<Int64>(High(Int64), TIndexCacheHousekeeping.MaxBytesOf(0));
  Assert.AreEqual<NativeInt>(0, Length(TIndexCacheHousekeeping.SelectForRemoval([Info('a', 1000, 1)],
    TIndexCacheHousekeeping.MaxBytesOf(0), '')));
end;

{ TIndexCacheDirectoryTests }

/// <summary>TFile.Replace prüft, ob Quelle und Ziel existieren; im Wettlauf fehlt das Ziel kurz
/// (EFileNotFoundException mit Ressourcentext). Beide Fälle einmal auslösen.</summary>
procedure WarmUpReplaceFailures(const ARoot, ATarget: string);
var
  mMissing: string;
begin
  for mMissing in [TPath.Combine(ARoot, 'fehlt-ziel.json'), TPath.Combine(ARoot, 'fehlt-quelle.json')] do
    try
      if mMissing.Contains('ziel') then
      begin
        TFile.Replace(ATarget, mMissing, ATarget + '.bak');
      end
      else
      begin
        TFile.Replace(mMissing, ATarget, ATarget + '.bak');
      end;
    except
      on Exception do
        ;
    end;
end;

/// <summary>Schreibt ATarget in einem eigenen Thread, während es gesperrt ist.</summary>
procedure WarmUpLockInOtherThread(const ADisk: IIndexFileSystem; const ATarget: string);
var
  mDisk: IIndexFileSystem;
  mTarget: string;
  mWorker: TThread;
begin
  mDisk := ADisk;
  mTarget := ATarget;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mThreadLock: TFileStream;
    begin
      mThreadLock := TFileStream.Create(mTarget, fmOpenRead or fmShareExclusive);
      try
        mDisk.WriteText(mTarget, 'v');
      finally
        mThreadLock.Free;
      end;
    end);
  try
    mWorker.FreeOnTerminate := False;
    mWorker.Start;
    mWorker.WaitFor;
  finally
    mWorker.Free;
  end;
end;

procedure WarmUpFailures(const ARoot: string);
var
  mTarget: string;
  mLock, mBackupLock: TFileStream;
  mDisk: IIndexFileSystem;
  mCacheLock: TStream;
begin
  mDisk := TDiskIndexFileSystem.Create;
  mTarget := TPath.Combine(ARoot, 'index-00000001.json');
  mDisk.WriteText(mTarget, 'x');
  // Die RTL legt bei der ersten gescheiterten Sperre (EFCreateError) Daten an, die bis Programmende bleiben:
  // hier statt [IgnoreMemoryLeaks] an SecondLockFails.
  mCacheLock := TIndexCacheDirectory.TryLock(mTarget);
  try
    TIndexCacheDirectory.TryLock(mTarget).Free;
  finally
    mCacheLock.Free;
  end;
  mLock := TFileStream.Create(mTarget, fmOpenRead or fmShareExclusive);
  try
    mDisk.WriteText(mTarget, 'y');
  finally
    mLock.Free;
  end;
  mDisk.WriteText(mTarget, 'z');
  mBackupLock := TFileStream.Create(Format('%s.%d.bak', [mTarget, TThread.CurrentThread.ThreadID]), fmCreate or
    fmShareExclusive);
  try
    mDisk.WriteText(mTarget, 'w');
  finally
    mBackupLock.Free;
  end;
  WarmUpReplaceFailures(ARoot, mTarget);
  // Dasselbe in einem anderen Thread: Thread-lokale Daten der RTL legt jeder Thread selbst an.
  WarmUpLockInOtherThread(mDisk, mTarget);
end;

procedure TIndexCacheDirectoryTests.WarmUpFirstUse;
var
  mRoot: string;
begin
  Setup;
  try
    DiskFileSystemOverwritesExistingFile;
  finally
    TearDown;
  end;
  // Gleichzeitiges Ersetzen löst Fehler aus, deren Meldungstexte die RTL beim ersten Mal
  // bis Programmende zwischenspeichert. Einmal vorab durchlaufen, damit der Leck-Monitor
  // in ConcurrentWritersLeaveReadableCache nur den Speicher des Tests sieht.
  mRoot := TPath.Combine(TPath.GetTempPath, 'AtlasCacheWarmup' + IntToStr(TThread.GetTickCount64));
  ForceDirectories(mRoot);
  try
    WriteConcurrently(TPath.Combine(mRoot, 'index-00000000.json'), 50);
    // Die Fehlerpfade gezielt, nicht nur zufällig: Ziel gesperrt (Replace scheitert), Ziel und
    // Sicherung gesperrt, Ziel fehlt. Dabei auch die Liste der eigenen Sperren (#1479): Ihr TMonitor und
    // ihre Tabelle entstehen beim ersten TryLock und bleiben bis Programmende.
    WarmUpFailures(mRoot);
  finally
    TDirectory.Delete(mRoot, True);
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
  mFileSystem: TDiskIndexFileSystem;
  mCache, mText: string;
begin
  // Der zweite Start schreibt über einen vorhandenen Cache (TFile.Replace); das scheiterte
  // an der leeren Sicherungsdatei ("Pfad ist leer").
  mCache := CreateCache('index-00000002.json');
  mFileSystem := TDiskIndexFileSystem.Create;
  try
    Assert.IsTrue(mFileSystem.WriteText(mCache, '{"version":2}'));
    Assert.IsTrue(mFileSystem.ReadText(mCache, mText));
    Assert.AreEqual('{"version":2}', mText);
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FRoot))), 'keine .tmp- oder .bak-Reste');
  finally
    mFileSystem.Free;
  end;
end;

procedure TIndexCacheDirectoryTests.DiskFileSystemRoundTripsBytes;
var
  mFileSystem: TDiskIndexFileSystem;
  mCache, mError: string;
  mData: TBytes;
begin
  // Binärer Cache (#617): Bytes kommen unverändert zurück, auch Nullbytes; fehlende Datei = False.
  mCache := CreateCache('index-00000003.json');
  mFileSystem := TDiskIndexFileSystem.Create;
  try
    Assert.IsTrue(mFileSystem.WriteBytes(mCache, TBytes.Create(0, 1, 255, 0, 13, 10), mError));
    Assert.AreEqual('', mError);
    Assert.IsTrue(mFileSystem.ReadBytes(mCache, mData));
    Assert.AreEqual<NativeInt>(6, Length(mData));
    Assert.AreEqual<Byte>(255, mData[2]);
    Assert.AreEqual<Byte>(0, mData[3]);
    Assert.IsFalse(mFileSystem.ReadBytes(TPath.Combine(FRoot, 'fehlt.json'), mData));
    Assert.AreEqual<NativeInt>(0, Length(mData));
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FRoot))), 'keine .tmp- oder .bak-Reste');
  finally
    mFileSystem.Free;
  end;
end;

function TIndexCacheDirectoryTests.CreateCache(const AName: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, '{}');
end;

function TIndexCacheDirectoryTests.CreateFile(const AFileName: string; ASize: Integer): string;
var
  mData: TBytes;
begin
  Result := AFileName;
  ForceDirectories(ExtractFileDir(Result));
  SetLength(mData, ASize);
  TFile.WriteAllBytes(Result, mData);
end;

procedure TIndexCacheDirectoryTests.SecondLockFails;
var
  mFirst, mSecond: TStream;
  mCache: string;
begin
  mCache := CreateCache('index-00000001.json');
  mFirst := TIndexCacheDirectory.TryLock(mCache);
  try
    Assert.IsNotNull(mFirst);
    mSecond := TIndexCacheDirectory.TryLock(mCache);
    Assert.IsNull(mSecond);
    Assert.IsTrue(TIndexCacheDirectory.IsLocked(mCache));
  finally
    mFirst.Free;
  end;
  Assert.IsFalse(TIndexCacheDirectory.IsLocked(mCache));
end;

procedure TIndexCacheDirectoryTests.OwnLockKnownInProcess;
var
  mLock, mSecond: TStream;
  mCache, mDetour: string;
begin
  mCache := CreateCache('index-00000001.atlasidx');
  mDetour := TPath.Combine(TPath.Combine(FRoot, '..'), TPath.Combine(ExtractFileName(FRoot),
    'index-00000001.atlasidx'));
  mLock := TIndexCacheDirectory.TryLock(mCache);
  try
    Assert.IsNotNull(mLock);
    Assert.IsTrue(TIndexCacheDirectory.IsLocked(mDetour));
    Assert.IsNull(TIndexCacheDirectory.TryLock(mDetour));
  finally
    mLock.Free;
  end;
  Assert.IsFalse(TIndexCacheDirectory.IsLocked(mDetour));
  mSecond := TIndexCacheDirectory.TryLock(mDetour);
  try
    Assert.IsNotNull(mSecond);
    Assert.IsTrue(TIndexCacheDirectory.IsLocked(mCache));
  finally
    mSecond.Free;
  end;
  Assert.IsFalse(TIndexCacheDirectory.IsLocked(mCache));
end;

procedure TIndexCacheDirectoryTests.ClearSkipsLockedCaches;
var
  mLock: TStream;
  mLocked: string;
begin
  CreateCache('index-00000001.json');
  mLocked := CreateCache('index-00000002.json');
  CreateCache('anderes.json');
  mLock := TIndexCacheDirectory.TryLock(mLocked);
  try
    Assert.AreEqual(1, TIndexCacheDirectory.Clear(FRoot));
    Assert.IsTrue(FileExists(mLocked));
    Assert.IsTrue(FileExists(TPath.Combine(FRoot, 'anderes.json')));
  finally
    mLock.Free;
  end;
end;

procedure TIndexCacheDirectoryTests.CleanupKeepsOwnCache;
var
  mOwn: string;
begin
  mOwn := CreateCache('index-00000001.json');
  CreateCache('index-00000002.json');
  Assert.AreEqual(1, TIndexCacheDirectory.Cleanup(FRoot, 0, mOwn));
  Assert.IsTrue(FileExists(mOwn));
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
  mVersion: string;
begin
  // Je IDE-Version ein Ordner, darin je Projekt einer; die Bibliothek getrennt (#492).
  mVersion := TPath.Combine(TPath.Combine(FRoot, 'Index'), '37.0');
  Assert.AreEqual(TPath.Combine(TPath.Combine(mVersion, TIndexCacheDirectory.KeyHash('Projekt')),
    TIndexCacheDirectory.CacheFileName), TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'));
  Assert.AreEqual(TPath.Combine(TPath.Combine(TPath.Combine(mVersion, 'Bibliothek'),
    TIndexCacheDirectory.KeyHash('Win64')), TIndexCacheDirectory.CacheFileName),
    TIndexCacheDirectory.LibraryFileFor(FRoot, '37.0', 'Win64'));
  Assert.AreNotEqual(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'),
    TIndexCacheDirectory.FileFor(FRoot, '23.0', 'Projekt'));
  Assert.AreEqual(TPath.Combine(TPath.Combine(FRoot, 'Index'), 'ohne-Delphi'),
    TIndexCacheDirectory.VersionFolder(FRoot, ''));
end;

procedure TIndexCacheDirectoryTests.ClearRemovesNewLayoutAndEmptyFolders;
var
  mProject, mLibrary_, mLegacy: string;
begin
  mProject := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'), 100);
  mLibrary_ := CreateFile(TIndexCacheDirectory.LibraryFileFor(FRoot, '37.0', 'Win64'), 200);
  mLegacy := CreateCache('index-00000001.json');
  CreateCache('anderes.json');
  Assert.AreEqual<Int64>(300 + 2, TIndexCacheDirectory.TotalSize(FRoot));
  Assert.AreEqual(3, TIndexCacheDirectory.Clear(FRoot));
  Assert.IsFalse(FileExists(mProject));
  Assert.IsFalse(FileExists(mLibrary_));
  Assert.IsFalse(FileExists(mLegacy));
  // Leere Projektordner gehen mit, fremde Dateien bleiben.
  Assert.IsFalse(TDirectory.Exists(ExtractFileDir(mProject)));
  Assert.IsTrue(FileExists(TPath.Combine(FRoot, 'anderes.json')));
  Assert.AreEqual<Int64>(0, TIndexCacheDirectory.TotalSize(FRoot));
end;

procedure TIndexCacheDirectoryTests.FileNameCarriesFormatVersion;
begin
  // Server verschiedener Atlas-Versionen (installiert und neu) teilen sich sonst eine Datei und verwerfen
  // gegenseitig ihre Caches („Formatversion 27 statt 29“).
  Assert.AreEqual(Format('index-%d.atlasidx', [TIndexCache.cFormatVersion]), TIndexCacheDirectory.CacheFileName);
  Assert.AreEqual(TIndexCacheDirectory.CacheFileName,
    ExtractFileName(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt')));
  Assert.AreEqual(TIndexCacheDirectory.CacheFileName,
    ExtractFileName(TIndexCacheDirectory.LibraryFileFor(FRoot, '37.0', 'Win64')));
end;

procedure TIndexCacheDirectoryTests.RemoveKeepsOriginOfOtherFormat;
var
  mCurrent, mOlder, mFolder: string;
begin
  // Ein Cache älteren Formats im selben Projektordner behält Herkunft und Benutzungsmarke.
  mCurrent := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'), 10);
  mFolder := ExtractFileDir(mCurrent);
  mOlder := CreateFile(TPath.Combine(mFolder, 'index.atlasidx'), 10);
  TIndexCacheDirectory.WriteOrigin(mCurrent, 'C:\Projekte\App.dproj');
  TIndexCacheDirectory.TouchUse(mCurrent);
  Assert.AreEqual(1, TIndexCacheDirectory.Remove([mCurrent]));
  Assert.IsTrue(FileExists(TPath.Combine(mFolder, TIndexCacheDirectory.cOriginFileName)));
  Assert.IsTrue(FileExists(TPath.Combine(mFolder, TIndexCacheDirectory.cUseMarkerFileName)));
  Assert.AreEqual(1, TIndexCacheDirectory.Remove([mOlder]));
  Assert.IsFalse(TDirectory.Exists(mFolder));
end;

procedure TIndexCacheDirectoryTests.RemoveAndSizeOfNamedCaches;
var
  mFirst, mSecond: string;
  mLock: TStream;
begin
  mFirst := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Eins'), 10);
  mSecond := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Zwei'), 20);
  Assert.AreEqual<Int64>(30, TIndexCacheDirectory.SizeOf([mFirst, mSecond, '', mFirst + '.fehlt']));
  mLock := TIndexCacheDirectory.TryLock(mSecond);
  try
    // Die gesperrte Datei hält eine andere Instanz: bleibt.
    Assert.AreEqual(1, TIndexCacheDirectory.Remove([mFirst, mSecond, '']));
  finally
    mLock.Free;
  end;
  Assert.IsFalse(FileExists(mFirst));
  Assert.IsTrue(FileExists(mSecond));
end;

procedure TIndexCacheDirectoryTests.ConcurrentWritersLeaveReadableCache;
var
  mCache: string;
  mText: string;
  mFileSystem: IIndexFileSystem;
begin
  // Zwei Schreiber, die gleichzeitig ersetzen (#62): Am Ende steht einer der beiden
  // Stände vollständig in der Datei, nie ein halber.
  mCache := TPath.Combine(FRoot, 'index-00000003.json');
  WriteConcurrently(mCache, 50);
  mFileSystem := TDiskIndexFileSystem.Create;
  Assert.IsTrue(mFileSystem.ReadText(mCache, mText));
  Assert.IsTrue((mText = StringOfChar('a', 100000)) or (mText = StringOfChar('b', 100000)));
  // Keine temporären Dateien zurückgelassen.
  Assert.AreEqual<NativeInt>(1, Length(TDirectory.GetFiles(FRoot)));
end;

procedure TIndexCacheDirectoryTests.DiskWriteLockIsExclusive;
var
  mCache: string;
  mFileSystem: IIndexFileSystem;
  mFirst, mSecond: IInterface;
begin
  mCache := CreateCache('index-00000005.json');
  mFileSystem := TDiskIndexFileSystem.Create;
  mFirst := mFileSystem.TryLockWrite(mCache);
  Assert.IsNotNull(mFirst);
  mSecond := mFileSystem.TryLockWrite(mCache);
  Assert.IsNull(mSecond, 'nur ein Schreiber');
  Assert.IsTrue(TIndexCacheDirectory.IsLocked(mCache));
  mFirst := nil;
  Assert.IsFalse(TIndexCacheDirectory.IsLocked(mCache));
  mSecond := mFileSystem.TryLockWrite(mCache);
  Assert.IsNotNull(mSecond, 'nach dem Freigeben wieder frei');
  mSecond := nil;
end;

procedure TIndexCacheDirectoryTests.FailedReplaceLeavesNoRemains;
var
  mCache, mText, mError: string;
  mLock: TFileStream;
  mFileSystem: IIndexFileSystem;
begin
  // Der Fehlerpfad aus ConcurrentWritersLeaveReadableCache, aber deterministisch: Ist das Ziel
  // gesperrt, scheitert ReplaceFile, ohne dass TFile.Replace eine Ausnahme wirft. Früher meldete
  // WriteText dann Erfolg und ließ die temporäre Datei liegen.
  mCache := CreateCache('index-00000004.json');
  mFileSystem := TDiskIndexFileSystem.Create;
  mLock := TFileStream.Create(mCache, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(mFileSystem.WriteText(mCache, '{"version":2}'));
    // Der Grund kommt mit, ohne Pfad (anonymes Log).
    Assert.IsFalse(mFileSystem.WriteBytes(mCache, TEncoding.UTF8.GetBytes('{"version":2}'), mError));
    Assert.AreNotEqual('', mError);
    Assert.IsFalse(mError.Contains(FRoot), mError);
  finally
    mLock.Free;
  end;
  Assert.IsTrue(mFileSystem.ReadText(mCache, mText));
  Assert.AreEqual('{}', mText, 'alter Stand vollständig erhalten');
  Assert.AreEqual<NativeInt>(1, Length(TDirectory.GetFiles(FRoot)), 'keine .tmp- oder .bak-Reste');
end;

procedure TIndexCacheDirectoryTests.RemoveOrphansDeletesCacheOfDeletedProject;
var
  mAlive, mGone, mAliveProject, mGoneProject: string;
begin
  mAliveProject := CreateFile(TPath.Combine(TPath.Combine(FRoot, 'main'), 'App.dproj'), 1);
  mGoneProject := CreateFile(TPath.Combine(TPath.Combine(FRoot, 'feature'), 'App.dproj'), 1);
  mAlive := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', mAliveProject), 10);
  mGone := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', mGoneProject), 10);
  TIndexCacheDirectory.WriteOrigin(mAlive, mAliveProject);
  TIndexCacheDirectory.WriteOrigin(mGone, mGoneProject);
  Assert.AreEqual(mGoneProject, TIndexCacheDirectory.ReadOrigin(mGone));
  // Der Branch-Ordner wird gelöscht.
  TDirectory.Delete(ExtractFileDir(mGoneProject), True);
  Assert.AreEqual(1, TIndexCacheDirectory.RemoveOrphans(FRoot, nil));
  Assert.IsTrue(FileExists(mAlive));
  Assert.IsFalse(FileExists(mGone));
  // Samt projekt.txt und leerem Ordner.
  Assert.IsFalse(TDirectory.Exists(ExtractFileDir(mGone)));
  Assert.AreEqual(0, TIndexCacheDirectory.RemoveOrphans(FRoot, nil));
end;

procedure TIndexCacheDirectoryTests.RemoveOrphansKeepsOwnLockedAndLibrary;
var
  mOwn, mLocked, mLibrary_, mMissing: string;
  mLock: TStream;
begin
  mMissing := TPath.Combine(FRoot, 'fehlt.dproj');
  mOwn := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Eigen'), 10);
  mLocked := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Gesperrt'), 10);
  mLibrary_ := CreateFile(TIndexCacheDirectory.LibraryFileFor(FRoot, '37.0', 'Win64'), 10);
  TIndexCacheDirectory.WriteOrigin(mOwn, mMissing);
  TIndexCacheDirectory.WriteOrigin(mLocked, mMissing);
  mLock := TIndexCacheDirectory.TryLock(mLocked);
  try
    Assert.AreEqual(0, TIndexCacheDirectory.RemoveOrphans(FRoot, TArray<string>.Create(mOwn)));
  finally
    mLock.Free;
  end;
  Assert.IsTrue(FileExists(mOwn) and FileExists(mLocked) and FileExists(mLibrary_));
end;

procedure TIndexCacheDirectoryTests.RemoveOrphansReadsUnitsOfOldCaches;
var
  mAlive, mGone, mAliveUnit: string;
  mUnitIndex: TUnitIndex;
begin
  // Caches von vor #905 haben keine projekt.txt: Die Projekt-Units im Cache entscheiden.
  mAliveUnit := CreateFile(TPath.Combine(TPath.Combine(FRoot, 'Quelle'), 'Haupt.pas'), 1);
  mUnitIndex := Default(TUnitIndex);
  mUnitIndex.UnitName := 'Haupt';
  mUnitIndex.FileName := mAliveUnit;
  mAlive := TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Lebt');
  ForceDirectories(ExtractFileDir(mAlive));
  TFile.WriteAllBytes(mAlive, TIndexCache.Serialize([mUnitIndex]));
  mUnitIndex.FileName := TPath.Combine(TPath.Combine(FRoot, 'Geloescht'), 'Haupt.pas');
  mGone := TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Weg');
  ForceDirectories(ExtractFileDir(mGone));
  TFile.WriteAllBytes(mGone, TIndexCache.Serialize([mUnitIndex]));
  Assert.AreEqual(1, TIndexCacheDirectory.RemoveOrphans(FRoot, nil));
  Assert.IsTrue(FileExists(mAlive));
  Assert.IsFalse(FileExists(mGone));
  // Die gefundene Unit steht jetzt als Herkunft da; der Cache wird nicht wieder gelesen.
  Assert.AreEqual(mAliveUnit, TIndexCacheDirectory.ReadOrigin(mAlive));
  mUnitIndex := Default(TUnitIndex);
end;

procedure TIndexCacheDirectoryTests.RemoveOrphansDeletesLegacyAndBuildFiles;
var
  mLegacy, mBuildGone, mBuildAlive, mProject, mOther: string;
begin
  mLegacy := CreateCache('index-00000001.json');
  mOther := CreateCache('anderes.json');
  mProject := CreateFile(TPath.Combine(TPath.Combine(FRoot, 'main'), 'App.dproj'), 1);
  mBuildAlive := TPath.Combine(FRoot, 'build-00000001.json');
  TFile.WriteAllText(mBuildAlive, BuildFileText(mProject), TEncoding.UTF8);
  mBuildGone := TPath.Combine(FRoot, 'build-00000002.json');
  TFile.WriteAllText(mBuildGone, BuildFileText(TPath.Combine(FRoot, 'fehlt.dproj')), TEncoding.UTF8);
  Assert.AreEqual(2, TIndexCacheDirectory.RemoveOrphans(FRoot, nil));
  Assert.IsFalse(FileExists(mLegacy));
  Assert.IsFalse(FileExists(mBuildGone));
  Assert.IsTrue(FileExists(mBuildAlive));
  Assert.IsTrue(FileExists(mOther));
end;

procedure TIndexCacheDirectoryTests.OriginExistsWithMissingDrive;
var
  mDrive: Char;
begin
  Assert.IsTrue(TIndexCacheDirectory.OriginExists(FRoot));
  Assert.IsFalse(TIndexCacheDirectory.OriginExists(TPath.Combine(FRoot, 'fehlt.dproj')));
  {$IFDEF MSWINDOWS}
  // Laufwerk nicht verbunden (USB, Netz): nicht als gelöscht werten.
  for mDrive := 'Z' downto 'D' do
  begin
    if not DirectoryExists(mDrive + ':\') then
    begin
      Assert.IsTrue(TIndexCacheDirectory.OriginExists(mDrive + ':\Projekte\App.dproj'));
      Break;
    end;
  end;
  {$ENDIF}
end;

procedure TIndexCacheDirectoryTests.TouchUseRenewsLastUse;
var
  mCache: string;
begin
  mCache := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Projekt'), 10);
  TFile.SetLastWriteTime(mCache, Now - 100);
  Assert.IsTrue(TIndexCacheDirectory.LastUse(mCache) < Now - 99);
  // Laden ohne Änderung schreibt den Cache nicht, zählt aber als Benutzung.
  TIndexCacheDirectory.TouchUse(mCache);
  Assert.IsTrue(TIndexCacheDirectory.LastUse(mCache) > Now - 1);
  Assert.IsTrue(TFile.GetLastWriteTime(mCache) < Now - 99, 'der Cache selbst bleibt unverändert');
end;

procedure TIndexCacheDirectoryTests.TouchUseIgnoresEmptyName;
var
  mPrevious: string;
begin
  mPrevious := GetCurrentDir;
  SetCurrentDir(FRoot);
  try
    TIndexCacheDirectory.TouchUse('');
  finally
    SetCurrentDir(mPrevious);
  end;
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FRoot))));
end;

procedure TIndexCacheDirectoryTests.RemoveUnusedDeletesOldCaches;
var
  mOld, mUsed, mOwn, mLibrary_: string;
begin
  mOld := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Alt'), 10);
  mUsed := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Benutzt'), 10);
  mOwn := CreateFile(TIndexCacheDirectory.FileFor(FRoot, '37.0', 'Eigen'), 10);
  mLibrary_ := CreateFile(TIndexCacheDirectory.LibraryFileFor(FRoot, '23.0', 'Win32'), 10);
  TFile.SetLastWriteTime(mOld, Now - 30);
  TFile.SetLastWriteTime(mUsed, Now - 30);
  TFile.SetLastWriteTime(mOwn, Now - 30);
  TFile.SetLastWriteTime(mLibrary_, Now - 30);
  TIndexCacheDirectory.TouchUse(mUsed);
  Assert.AreEqual(0, TIndexCacheDirectory.RemoveUnused(FRoot, 0, nil), '0 = aus');
  // Auch der Bibliotheks-Cache einer nicht mehr benutzten Delphi-Version geht.
  Assert.AreEqual(2, TIndexCacheDirectory.RemoveUnused(FRoot, 14, TArray<string>.Create(mOwn)));
  Assert.IsFalse(FileExists(mOld));
  Assert.IsFalse(FileExists(mLibrary_));
  Assert.IsTrue(FileExists(mUsed) and FileExists(mOwn));
  // Samt Marke und leerem Ordner.
  Assert.IsFalse(TDirectory.Exists(ExtractFileDir(mOld)));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexCacheHousekeepingTests);
  TDUnitX.RegisterTestFixture(TIndexCacheDirectoryTests);

end.
