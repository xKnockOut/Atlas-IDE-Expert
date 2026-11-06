unit Atlas.Windows.Updates.Adapters.Files;

// Platform-Feature "Updates" (#1519), Adapter: IUpdateFiles über Windows.
// Jeder Fehler beim Schreiben, Umbenennen oder Löschen wird EInOutError mit
// der Meldung des Systems (gesperrt, keine Rechte): Der Tausch legt dann eine
// laufende EXE beiseite oder nimmt alles zurück.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsFiles = class(TInterfacedObject, IUpdateFiles)
  public
    function FileExists(const AFileName: string): Boolean;
    function DirectoryExists(const ADirectory: string): Boolean;
    function FilesIn(const ADirectory: string): TArray<string>;
    procedure CopyFile(const ASource, ATarget: string);
    procedure MoveFile(const ASource, ATarget: string);
    procedure DeleteFile(const AFileName: string);
    procedure DeleteDirectory(const ADirectory: string);
    procedure ForceDirectories(const ADirectory: string);
    function ReadText(const AFileName: string): string;
    procedure WriteText(const AFileName, AText: string);
    procedure AppendText(const AFileName, AText: string);
    function CanWrite(const ADirectory: string): Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils;

procedure RaiseFileError(const AFileName: string);
begin
  raise EInOutError.Create(ExtractFileName(AFileName) + ': ' + SysErrorMessage(GetLastError));
end;

procedure MakeDirectory(const ADirectory: string);
begin
  if (ADirectory <> '') and not System.SysUtils.ForceDirectories(ADirectory) then
  begin
    RaiseFileError(ADirectory);
  end;
end;

{ TUpdateWindowsFiles }

function TUpdateWindowsFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := System.SysUtils.FileExists(AFileName);
end;

function TUpdateWindowsFiles.DirectoryExists(const ADirectory: string): Boolean;
begin
  Result := System.SysUtils.DirectoryExists(ADirectory);
end;

function TUpdateWindowsFiles.FilesIn(const ADirectory: string): TArray<string>;
var
  mBase, mPath: string;
begin
  Result := nil;
  if not System.SysUtils.DirectoryExists(ADirectory) then
  begin
    Exit;
  end;
  mBase := IncludeTrailingPathDelimiter(ADirectory);
  for mPath in TDirectory.GetFiles(ADirectory, '*', TSearchOption.soAllDirectories) do
  begin
    Result := Result + [mPath.Substring(Length(mBase))];
  end;
end;

procedure TUpdateWindowsFiles.CopyFile(const ASource, ATarget: string);
begin
  MakeDirectory(ExtractFileDir(ATarget));
  if not Winapi.Windows.CopyFile(PChar(ASource), PChar(ATarget), False) then
  begin
    RaiseFileError(ATarget);
  end;
end;

procedure TUpdateWindowsFiles.MoveFile(const ASource, ATarget: string);
begin
  MakeDirectory(ExtractFileDir(ATarget));
  if not MoveFileEx(PChar(ASource), PChar(ATarget), MOVEFILE_REPLACE_EXISTING) then
  begin
    RaiseFileError(ASource);
  end;
end;

procedure TUpdateWindowsFiles.DeleteFile(const AFileName: string);
begin
  if System.SysUtils.FileExists(AFileName) and not System.SysUtils.DeleteFile(AFileName) then
  begin
    RaiseFileError(AFileName);
  end;
end;

procedure TUpdateWindowsFiles.DeleteDirectory(const ADirectory: string);
begin
  if System.SysUtils.DirectoryExists(ADirectory) then
  begin
    TDirectory.Delete(ADirectory, True);
  end;
end;

procedure TUpdateWindowsFiles.ForceDirectories(const ADirectory: string);
begin
  MakeDirectory(ADirectory);
end;

function TUpdateWindowsFiles.ReadText(const AFileName: string): string;
begin
  Result := '';
  if System.SysUtils.FileExists(AFileName) then
  begin
    Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  end;
end;

procedure TUpdateWindowsFiles.WriteText(const AFileName, AText: string);
var
  mEncoding: TEncoding;
  mTemp: string;
begin
  MakeDirectory(ExtractFileDir(AFileName));
  // Erst daneben schreiben, dann ersetzen: Das Plugin liest state.json, während sie entsteht.
  mTemp := AFileName + '.tmp';
  mEncoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(mTemp, AText, mEncoding);
  finally
    mEncoding.Free;
  end;
  MoveFile(mTemp, AFileName);
end;

procedure TUpdateWindowsFiles.AppendText(const AFileName, AText: string);
var
  mEncoding: TEncoding;
begin
  MakeDirectory(ExtractFileDir(AFileName));
  mEncoding := TUTF8Encoding.Create(False);
  try
    TFile.AppendAllText(AFileName, AText, mEncoding);
  finally
    mEncoding.Free;
  end;
end;

function TUpdateWindowsFiles.CanWrite(const ADirectory: string): Boolean;
var
  mProbe: string;
  mHandle: THandle;
begin
  if not System.SysUtils.ForceDirectories(ADirectory) then
  begin
    Exit(False);
  end;
  mProbe := IncludeTrailingPathDelimiter(ADirectory) + 'atlas-write-test.tmp';
  mHandle := CreateFile(PChar(mProbe), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_FLAG_DELETE_ON_CLOSE, 0);
  Result := mHandle <> INVALID_HANDLE_VALUE;
  if Result then
  begin
    CloseHandle(mHandle);
  end;
end;

end.
