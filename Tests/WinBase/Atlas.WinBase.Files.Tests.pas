unit Atlas.WinBase.Files.Tests;

// Tests für TAtlasSharedRead: lesen, ohne einen Schreiber oder das atomare
// Ersetzen durch einen anderen Prozess zu blockieren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSharedReadTests = class
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
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.WinBase.Files;

{ TAtlasSharedReadTests }

function TAtlasSharedReadTests.OpenFor(AAccess: Cardinal): THandle;
begin
  Result := CreateFile(PChar(FFile), AAccess, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, Result, SysErrorMessage(GetLastError));
end;

procedure TAtlasSharedReadTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasGeteiltLesen' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FFile := TPath.Combine(FDir, 'settings.json');
  TFile.WriteAllBytes(FFile, TBytes.Create($7B, $7D));
end;

procedure TAtlasSharedReadTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
  begin
    TDirectory.Delete(FDir, True);
  end;
  FDir := '';
  FFile := '';
end;

procedure TAtlasSharedReadTests.ReadsWholeFile;
var
  mBytes: TBytes;
begin
  mBytes := TAtlasSharedRead.ReadAllBytes(FFile);
  Assert.AreEqual(2, Integer(Length(mBytes)));
  Assert.AreEqual(Integer($7B), Integer(mBytes[0]));
  Assert.AreEqual(Integer($7D), Integer(mBytes[1]));
end;

procedure TAtlasSharedReadTests.ReadsEmptyFile;
begin
  TFile.WriteAllBytes(FFile, nil);
  Assert.AreEqual(0, Integer(Length(TAtlasSharedRead.ReadAllBytes(FFile))));
end;

procedure TAtlasSharedReadTests.MissingFileRaisesOpenError;
begin
  Assert.WillRaise(
    procedure
    begin
      TAtlasSharedRead.ReadAllBytes(TPath.Combine(FDir, 'fehlt.json'));
    end, EFOpenError);
end;

procedure TAtlasSharedReadTests.ReadsWhileSomeoneWrites;
var
  mHandle: THandle;
begin
  mHandle := OpenFor(GENERIC_READ or GENERIC_WRITE);
  try
    Assert.AreEqual(2, Integer(Length(TAtlasSharedRead.ReadAllBytes(FFile))));
  finally
    CloseHandle(mHandle);
  end;
end;

procedure TAtlasSharedReadTests.ReadsWhileSomeoneReplaces;
var
  mHandle: THandle;
begin
  mHandle := OpenFor(_DELETE or SYNCHRONIZE);
  try
    Assert.AreEqual(2, Integer(Length(TAtlasSharedRead.ReadAllBytes(FFile))));
    // Gegenprobe: So liest die RTL. Delphi meldet EInOutError, FPC EFOpenError.
    Assert.WillRaiseAny(
      procedure
      begin
        TFile.ReadAllBytes(FFile);
      end);
  finally
    CloseHandle(mHandle);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSharedReadTests);

end.
