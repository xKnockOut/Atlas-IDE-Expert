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

initialization
  TDUnitX.RegisterTestFixture(TTextFilesTests);

end.
