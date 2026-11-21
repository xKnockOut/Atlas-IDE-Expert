unit Atlas.Text.Files.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextFilesTests = class
  private
    FDir: string;
    function PathOf(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DeleteQuietlyRemovesFile;
    [Test]
    procedure DeleteQuietlyIgnoresMissingFile;
    [Test]
    procedure DeleteFolderRemovesContent;
    [Test]
    procedure DeleteFolderIgnoresMissingFolder;
    [Test]
    procedure LastWriteUtcOfFileAndFolder;
    [Test]
    procedure OpenExclusiveCreatesAndReopens;
    [Test]
    procedure OpenExclusiveWithoutCreateReportsMissing;
    [Test]
    procedure OpenExclusiveHeldByOtherIsLocked;
    [Test]
    procedure OpenExclusiveWaitsOnlyWhileLocked;
    [Test]
    procedure OpenExclusiveFolderFailsAtOnce;
    [Test]
    procedure OpenExclusiveMissingFolderFails;
    [Test]
    procedure IsFileErrorOnlyForFileSystem;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Text.Files;

{ TTextFilesTests }

function TTextFilesTests.PathOf(const AName: string): string;
begin
  Result := TPath.Combine(FDir, AName);
end;

procedure TTextFilesTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'atlas-text-files-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TTextFilesTests.TearDown;
begin
  TTextFiles.DeleteFolder(FDir);
  FDir := '';
end;

procedure TTextFilesTests.DeleteQuietlyRemovesFile;
var
  mFile: string;
begin
  mFile := TPath.Combine(TPath.GetTempPath, 'atlas-text-files-' + IntToStr(Random(1000000)) + '.tmp');
  TFile.WriteAllText(mFile, 'x');
  TTextFiles.DeleteQuietly(mFile);
  Assert.IsFalse(TFile.Exists(mFile));
  mFile := '';
end;

procedure TTextFilesTests.DeleteQuietlyIgnoresMissingFile;
var
  mFile: string;
begin
  mFile := TPath.Combine(TPath.GetTempPath, 'atlas-text-files-fehlt.tmp');
  TTextFiles.DeleteQuietly(mFile);
  Assert.IsFalse(TFile.Exists(mFile));
  mFile := '';
end;

procedure TTextFilesTests.DeleteFolderRemovesContent;
var
  mFolder: string;
begin
  mFolder := PathOf('unter');
  TDirectory.CreateDirectory(TPath.Combine(mFolder, 'tief'));
  TFile.WriteAllText(TPath.Combine(TPath.Combine(mFolder, 'tief'), 'x.txt'), 'x');
  Assert.IsTrue(TTextFiles.DeleteFolder(mFolder));
  Assert.IsFalse(TDirectory.Exists(mFolder));
  mFolder := '';
end;

procedure TTextFilesTests.DeleteFolderIgnoresMissingFolder;
begin
  Assert.IsTrue(TTextFiles.DeleteFolder(PathOf('fehlt')), 'nichts zu löschen ist kein Fehler');
end;

procedure TTextFilesTests.LastWriteUtcOfFileAndFolder;
var
  mUtc: TDateTime;
begin
  TFile.WriteAllText(PathOf('z.txt'), 'x');
  Assert.IsTrue(TTextFiles.LastWriteUtc(PathOf('z.txt'), mUtc));
  Assert.IsTrue(mUtc > 0, 'Datei hat einen Zeitpunkt');
  Assert.IsTrue(TTextFiles.LastWriteUtc(FDir, mUtc));
  Assert.IsTrue(mUtc > 0, 'Ordner hat einen Zeitpunkt');
  Assert.IsFalse(TTextFiles.LastWriteUtc(PathOf('fehlt'), mUtc));
  Assert.AreEqual(Double(0), Double(mUtc));
end;

procedure TTextFilesTests.OpenExclusiveCreatesAndReopens;
var
  mStream: TStream;
  mError: string;
  mByte: Byte;
begin
  mByte := 1;
  Assert.AreEqual(Ord(TTextExclusiveOpen.Opened), Ord(TTextFiles.OpenExclusive(PathOf('a.lock'), True, mStream,
    mError)));
  try
    Assert.IsTrue(TFile.Exists(PathOf('a.lock')));
    mStream.WriteBuffer(mByte, SizeOf(mByte));
  finally
    mStream.Free;
  end;
  Assert.AreEqual(Ord(TTextExclusiveOpen.Opened), Ord(TTextFiles.OpenExclusive(PathOf('a.lock'), False, mStream,
    mError)));
  try
    Assert.AreEqual(Int64(SizeOf(mByte)), mStream.Size, 'vorhandene Datei bleibt beim Öffnen erhalten');
  finally
    mStream.Free;
  end;
  Assert.AreEqual('', mError);
  mError := '';
end;

procedure TTextFilesTests.OpenExclusiveWithoutCreateReportsMissing;
var
  mStream: TStream;
  mError: string;
begin
  Assert.AreEqual(Ord(TTextExclusiveOpen.Missing), Ord(TTextFiles.OpenExclusive(PathOf('fehlt.lock'), False, mStream,
    mError)));
  Assert.IsNull(mStream);
  Assert.IsFalse(TFile.Exists(PathOf('fehlt.lock')));
  mError := '';
end;

procedure TTextFilesTests.OpenExclusiveHeldByOtherIsLocked;
var
  mFirst, mSecond: TStream;
  mError: string;
begin
  Assert.AreEqual(Ord(TTextExclusiveOpen.Opened), Ord(TTextFiles.OpenExclusive(PathOf('b.lock'), True, mFirst,
    mError)));
  try
    Assert.AreEqual(Ord(TTextExclusiveOpen.Locked), Ord(TTextFiles.OpenExclusive(PathOf('b.lock'), True, mSecond,
      mError)));
    Assert.IsNull(mSecond);
    Assert.AreEqual('', mError, 'gesperrt ist kein Fehler');
  finally
    mFirst.Free;
  end;
  mError := '';
end;

procedure TTextFilesTests.OpenExclusiveWaitsOnlyWhileLocked;
const
  cWaitMs = 200;
var
  mFirst, mSecond: TStream;
  mError: string;
  mWatch: TStopwatch;
begin
  Assert.AreEqual(Ord(TTextExclusiveOpen.Opened), Ord(TTextFiles.OpenExclusive(PathOf('c.lock'), True, mFirst,
    mError)));
  try
    mWatch := TStopwatch.StartNew;
    Assert.AreEqual(Ord(TTextExclusiveOpen.Locked), Ord(TTextFiles.OpenExclusive(PathOf('c.lock'), True, cWaitMs, 20,
      mSecond, mError)));
    Assert.IsTrue(mWatch.ElapsedMilliseconds >= cWaitMs div 2, 'wartet, solange ein anderer die Datei hält');
  finally
    mFirst.Free;
  end;
  Assert.AreEqual(Ord(TTextExclusiveOpen.Opened), Ord(TTextFiles.OpenExclusive(PathOf('c.lock'), True, cWaitMs, 20,
    mSecond, mError)), 'nach der Freigabe wieder frei');
  mSecond.Free;
  mError := '';
end;

procedure TTextFilesTests.OpenExclusiveFolderFailsAtOnce;
const
  cWaitMs = 3000;
var
  mStream: TStream;
  mError: string;
  mWatch: TStopwatch;
begin
  // Ein Ordner unter dem Namen lässt sich nie als Datei öffnen (wie fehlendes Schreibrecht): kein Warten.
  TDirectory.CreateDirectory(PathOf('d.lock'));
  mWatch := TStopwatch.StartNew;
  Assert.AreEqual(Ord(TTextExclusiveOpen.Failed), Ord(TTextFiles.OpenExclusive(PathOf('d.lock'), True, cWaitMs, 20,
    mStream, mError)));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < cWaitMs div 2, 'keine Wartezeit, wenn das Öffnen nie gelingt');
  Assert.IsNull(mStream);
  Assert.AreNotEqual('', mError, 'Grund des Betriebssystems');
  mError := '';
end;

procedure TTextFilesTests.OpenExclusiveMissingFolderFails;
var
  mStream: TStream;
  mError: string;
begin
  Assert.AreEqual(Ord(TTextExclusiveOpen.Failed), Ord(TTextFiles.OpenExclusive(TPath.Combine(PathOf('fehlt'),
    'e.lock'), True, mStream, mError)));
  Assert.IsNull(mStream);
  mError := '';
end;

procedure TTextFilesTests.IsFileErrorOnlyForFileSystem;

  procedure Check(AE: Exception; AExpected: Boolean);
  begin
    try
      Assert.AreEqual(AExpected, TTextFiles.IsFileError(AE), AE.ClassName);
    finally
      AE.Free;
    end;
  end;

begin
  Check(EInOutError.Create('x'), True);
  Check(EFOpenError.Create('x'), True);
  Check(EFCreateError.Create('x'), True);
  Check(EOSError.Create('x'), True);
  Check(EEncodingError.Create('x'), True);
  Check(EArgumentException.Create('x'), True);
  Check(EArgumentOutOfRangeException.Create('x'), False);
  Check(EAccessViolation.Create('x'), False);
  Check(EConvertError.Create('x'), False);
end;

initialization
  TDUnitX.RegisterTestFixture(TTextFilesTests);

end.
