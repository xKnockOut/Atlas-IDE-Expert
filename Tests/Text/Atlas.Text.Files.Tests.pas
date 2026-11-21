unit Atlas.Text.Files.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextFilesTests = class
  public
    [Test]
    procedure DeleteQuietlyRemovesFile;
    [Test]
    procedure DeleteQuietlyIgnoresMissingFile;
    [Test]
    procedure DeleteFolderQuietlyRemovesFolderWithContent;
    [Test]
    procedure DeleteFolderQuietlyIgnoresMissingFolder;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Text.Files;

{ TTextFilesTests }

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

procedure TTextFilesTests.DeleteFolderQuietlyRemovesFolderWithContent;
var
  mFolder: string;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-text-folder-' + IntToStr(Random(1000000)));
  TDirectory.CreateDirectory(TPath.Combine(mFolder, 'innen'));
  TFile.WriteAllText(TPath.Combine(mFolder, 'a.txt'), 'x');
  TFile.WriteAllText(TPath.Combine(TPath.Combine(mFolder, 'innen'), 'b.txt'), 'y');
  TTextFiles.DeleteFolderQuietly(mFolder);
  Assert.IsFalse(TDirectory.Exists(mFolder));
  mFolder := '';
end;

procedure TTextFilesTests.DeleteFolderQuietlyIgnoresMissingFolder;
var
  mFolder: string;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-text-folder-fehlt');
  TTextFiles.DeleteFolderQuietly(mFolder);
  Assert.IsFalse(TDirectory.Exists(mFolder));
  mFolder := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TTextFilesTests);

end.
