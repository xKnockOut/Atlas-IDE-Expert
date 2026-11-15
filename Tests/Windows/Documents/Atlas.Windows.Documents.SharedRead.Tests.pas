unit Atlas.Windows.Documents.SharedRead.Tests;

// Tests für TWindowsSharedRead: TFileEncoding liest nach Install so, dass
// ein anderer Prozess die Datei atomar ersetzen kann. Die Lesart selbst
// prüft Atlas.WinBase.Files.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWindowsSharedReadTests = class
  private
    FDir: string;
    FFile: string;
    function OpenFor(AAccess: Cardinal): THandle;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Nach Install liest TFileEncoding über TAtlasSharedRead und teilt Löschen.</summary>
    [Test]
    procedure InstallRoutesFileEncoding;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Windows.Documents.SharedRead;

{ TWindowsSharedReadTests }

function TWindowsSharedReadTests.OpenFor(AAccess: Cardinal): THandle;
begin
  Result := CreateFile(PChar(FFile), AAccess, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, Result, SysErrorMessage(GetLastError));
end;

procedure TWindowsSharedReadTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasGeteilt' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FFile := TPath.Combine(FDir, 'settings.json');
  TFile.WriteAllBytes(FFile, TBytes.Create($7B, $7D));
end;

procedure TWindowsSharedReadTests.TearDown;
begin
  TWindowsSharedRead.Uninstall;
  if TDirectory.Exists(FDir) then
  begin
    TDirectory.Delete(FDir, True);
  end;
  FDir := '';
  FFile := '';
end;

procedure TWindowsSharedReadTests.InstallRoutesFileEncoding;
var
  mHandle: THandle;
  mReader: TFileBytesReader;
begin
  TWindowsSharedRead.Install;
  mReader := TFileEncoding.Reader;
  Assert.IsTrue(Assigned(mReader));
  mHandle := OpenFor(_DELETE or SYNCHRONIZE);
  try
    Assert.AreEqual(2, Integer(Length(TFileEncoding.ReadAllBytes(FFile))));
  finally
    CloseHandle(mHandle);
  end;
  TWindowsSharedRead.Uninstall;
  mReader := TFileEncoding.Reader;
  Assert.IsFalse(Assigned(mReader));
end;

initialization
  TDUnitX.RegisterTestFixture(TWindowsSharedReadTests);

end.
