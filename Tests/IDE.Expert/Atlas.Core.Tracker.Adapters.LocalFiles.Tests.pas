unit Atlas.Core.Tracker.Adapters.LocalFiles.Tests;

// Dateizugriff des Trackers auf der Platte (#1455 Paket 2d): Text mit BOM
// schreiben und ohne lesen, Ersetzen ohne Zwischendatei, Anfang und Ende
// einer Datei, Ordner auflisten und löschen, Sperrdatei, keine Ausnahme bei
// fehlenden Dateien.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Tracker.Contract.Files;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerLocalFilesTests = class
  private
    FDir: string;
    FFiles: IAtlasTrackerFiles;
    function PathOf(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TextRoundTripWithBom;
    [Test]
    procedure ReplaceLeavesNoTemporaryFile;
    [Test]
    procedure HeadAndTail;
    [Test]
    procedure MissingFilesWithoutException;
    [Test]
    procedure ListAndDeleteFolders;
    [Test]
    procedure LockIsExclusive;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Tracker.Adapters.LocalFiles;

const
  cUtf8Bom: array[0..2] of Byte = ($EF, $BB, $BF);

{ TAtlasTrackerLocalFilesTests }

procedure TAtlasTrackerLocalFilesTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasTrackerFiles-' + TGUID.NewGuid.ToString);
  FFiles := TAtlasTrackerLocalFiles.Create;
end;

procedure TAtlasTrackerLocalFilesTests.TearDown;
begin
  FFiles := nil;
  if TDirectory.Exists(FDir) then
  begin
    TDirectory.Delete(FDir, True);
  end;
  FDir := '';
end;

function TAtlasTrackerLocalFilesTests.PathOf(const AName: string): string;
begin
  Result := TPath.Combine(FDir, AName);
end;

procedure TAtlasTrackerLocalFilesTests.TextRoundTripWithBom;
var
  mText: string;
  mBytes: TBytes;
begin
  // Der Ordner fehlt noch: WriteText legt ihn an.
  Assert.IsTrue(FFiles.WriteText(PathOf('sub' + PathDelim + 'a.json'), 'Grüße'));
  mBytes := TFile.ReadAllBytes(PathOf('sub' + PathDelim + 'a.json'));
  Assert.IsTrue(Length(mBytes) > 3);
  Assert.AreEqual(Integer(cUtf8Bom[0]), Integer(mBytes[0]), 'BOM wie bisher');
  Assert.IsTrue(FFiles.ReadText(PathOf('sub' + PathDelim + 'a.json'), mText));
  Assert.AreEqual('Grüße', mText, 'BOM übergangen');
  Assert.IsTrue(FFiles.FileExists(PathOf('sub' + PathDelim + 'a.json')));
  Assert.IsTrue(FFiles.FolderExists(PathOf('sub')));
end;

procedure TAtlasTrackerLocalFilesTests.ReplaceLeavesNoTemporaryFile;
var
  mText: string;
begin
  Assert.IsTrue(FFiles.ReplaceText(PathOf('n.json'), 'eins'));
  Assert.IsTrue(FFiles.ReplaceText(PathOf('n.json'), 'zwei'));
  Assert.IsTrue(FFiles.ReadText(PathOf('n.json'), mText));
  Assert.AreEqual('zwei', mText);
  Assert.AreEqual(Integer(1), Integer(Length(FFiles.Files(FDir, '*'))), 'nur die Datei selbst');
end;

procedure TAtlasTrackerLocalFilesTests.HeadAndTail;
var
  mData: TBytes;
  mCut: Boolean;
begin
  Assert.IsTrue(FFiles.WriteBytes(PathOf('log.txt'), TEncoding.ASCII.GetBytes('0123456789')));
  Assert.IsTrue(FFiles.ReadHead(PathOf('log.txt'), 4, mData));
  Assert.AreEqual('0123', TEncoding.ASCII.GetString(mData));
  Assert.IsTrue(FFiles.ReadTail(PathOf('log.txt'), 3, mData, mCut));
  Assert.AreEqual('789', TEncoding.ASCII.GetString(mData));
  Assert.IsTrue(mCut);
  Assert.IsTrue(FFiles.ReadTail(PathOf('log.txt'), 0, mData, mCut));
  Assert.AreEqual('0123456789', TEncoding.ASCII.GetString(mData));
  Assert.IsFalse(mCut);
end;

procedure TAtlasTrackerLocalFilesTests.MissingFilesWithoutException;
var
  mText: string;
  mData: TBytes;
  mCut: Boolean;
begin
  Assert.IsFalse(FFiles.FileExists(PathOf('fehlt.json')));
  Assert.IsFalse(FFiles.ReadText(PathOf('fehlt.json'), mText));
  Assert.IsFalse(FFiles.ReadHead(PathOf('fehlt.json'), 10, mData));
  Assert.IsFalse(FFiles.ReadTail(PathOf('fehlt.json'), 10, mData, mCut));
  Assert.IsTrue(FFiles.DeleteFile(PathOf('fehlt.json')), 'fehlt danach');
  Assert.IsTrue(FFiles.DeleteFolder(PathOf('fehlt')), 'fehlt danach');
  Assert.IsFalse(FFiles.RemoveEmptyFolder(PathOf('fehlt')));
  Assert.AreEqual(Integer(0), Integer(Length(FFiles.Files(PathOf('fehlt'), '*.json'))));
  Assert.AreEqual(Integer(0), Integer(Length(FFiles.Folders(PathOf('fehlt')))));
  Assert.AreEqual(Double(0), Double(FFiles.WriteTime(PathOf('fehlt.json'))));
  Assert.IsFalse(FFiles.WriteText('', 'x'));
end;

procedure TAtlasTrackerLocalFilesTests.ListAndDeleteFolders;
begin
  Assert.IsTrue(FFiles.WriteText(PathOf('a' + PathDelim + '1.json'), '{}'));
  Assert.IsTrue(FFiles.WriteText(PathOf('a' + PathDelim + '2.txt'), 'x'));
  Assert.IsTrue(FFiles.ForceFolder(PathOf('b')));
  Assert.AreEqual(Integer(2), Integer(Length(FFiles.Folders(FDir))));
  Assert.AreEqual(Integer(1), Integer(Length(FFiles.Files(PathOf('a'), '*.json'))));
  Assert.IsTrue(FFiles.WriteTime(PathOf('a')) > 0);
  Assert.IsFalse(FFiles.RemoveEmptyFolder(PathOf('a')), 'nicht leer');
  Assert.IsTrue(FFiles.RemoveEmptyFolder(PathOf('b')));
  Assert.IsTrue(FFiles.DeleteFolder(PathOf('a')));
  Assert.AreEqual(Integer(0), Integer(Length(FFiles.Folders(FDir))));
end;

procedure TAtlasTrackerLocalFilesTests.LockIsExclusive;
var
  mFirst: IInterface;
begin
  mFirst := FFiles.Lock(PathOf('t.lock'), 0);
  Assert.IsNotNull(mFirst);
  Assert.IsNull(FFiles.Lock(PathOf('t.lock'), 50), 'zweite Sperre wartet und gibt auf');
  mFirst := nil;
  Assert.IsNotNull(FFiles.Lock(PathOf('t.lock'), 0), 'nach der Freigabe wieder frei');
end;

end.
