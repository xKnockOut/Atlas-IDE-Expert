unit Atlas.Windows.Documents.SharedRead.Tests;

// Tests für TWindowsSharedRead: lesen, ohne einen Schreiber oder
// das atomare Ersetzen durch einen anderen Prozess zu blockieren.

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
    [Test]
    procedure ReadsWholeFile;
    [Test]
    procedure ReadsEmptyFile;
    [Test]
    procedure MissingFileRaisesOpenError;
    /// <summary>Ein anderer hat die Datei zum Schreiben offen (die IDE beim Speichern).</summary>
    [Test]
    procedure ReadsWhileSomeoneWrites;
    /// <summary>Ein anderer hat die Datei zum Löschen offen, wie beim Ersetzen; TFile.ReadAllBytes scheitert
    /// daran, weil es Löschen nicht teilt.</summary>
    [Test]
    procedure ReadsWhileSomeoneReplaces;
    [Test]
    procedure InstallRoutesFileEncoding;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Windows.Documents.SharedRead;

{ TWindowsSharedReadTests }

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

function TWindowsSharedReadTests.OpenFor(AAccess: Cardinal): THandle;
begin
  Result := CreateFile(PChar(FFile), AAccess, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, Result, SysErrorMessage(GetLastError));
end;

procedure TWindowsSharedReadTests.ReadsWholeFile;
var
  mBytes: TBytes;
begin
  mBytes := TWindowsSharedRead.ReadAllBytes(FFile);
  Assert.AreEqual(2, Integer(Length(mBytes)));
  Assert.AreEqual(Integer($7B), Integer(mBytes[0]));
  Assert.AreEqual(Integer($7D), Integer(mBytes[1]));
end;

procedure TWindowsSharedReadTests.ReadsEmptyFile;
begin
  TFile.WriteAllBytes(FFile, nil);
  Assert.AreEqual(0, Integer(Length(TWindowsSharedRead.ReadAllBytes(FFile))));
end;

procedure TWindowsSharedReadTests.MissingFileRaisesOpenError;
begin
  Assert.WillRaise(
    procedure
    begin
      TWindowsSharedRead.ReadAllBytes(TPath.Combine(FDir, 'fehlt.json'));
    end, EFOpenError);
end;

procedure TWindowsSharedReadTests.ReadsWhileSomeoneWrites;
var
  mHandle: THandle;
begin
  mHandle := OpenFor(GENERIC_READ or GENERIC_WRITE);
  try
    Assert.AreEqual(2, Integer(Length(TWindowsSharedRead.ReadAllBytes(FFile))));
  finally
    CloseHandle(mHandle);
  end;
end;

procedure TWindowsSharedReadTests.ReadsWhileSomeoneReplaces;
var
  mHandle: THandle;
begin
  mHandle := OpenFor(_DELETE or SYNCHRONIZE);
  try
    Assert.AreEqual(2, Integer(Length(TWindowsSharedRead.ReadAllBytes(FFile))));
    // Gegenprobe: So las der Server bisher. Delphi meldet EInOutError, FPC EFOpenError.
    Assert.WillRaiseAny(
      procedure
      begin
        TFile.ReadAllBytes(FFile);
      end);
  finally
    CloseHandle(mHandle);
  end;
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
