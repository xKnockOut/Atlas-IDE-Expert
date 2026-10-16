unit Setup.Adapters.WindowsSystem;

// Installer (#495): ISetupSystem für Windows. Registry über TRegistry,
// HKEY_LOCAL_MACHINE nur lesend und in der 64-Bit-Ansicht (KEY_WOW64_64KEY),
// damit ein 32-Bit-Installer auch Software\WOW6432Node getrennt sieht.
// Laufende Programme über einen Prozess-Schnappschuss und den vollen Pfad
// (QueryFullProcessImageName, ohne erhöhte Rechte lesbar).

interface

uses
  System.SysUtils,
  Setup.Core.Contract;

type
  TSetupWindowsSystem = class(TInterfacedObject, ISetupSystem)
  public
    function SubKeys(const AKey: string): TArray<string>;
    function MachineSubKeys(const AKey: string): TArray<string>;
    function ReadString(const AKey, AName: string): string;
    function MachineReadString(const AKey, AName: string): string;
    function ReadInteger(const AKey, AName: string; ADefault: Integer): Integer;
    function ValueNames(const AKey: string): TArray<string>;
    procedure WriteString(const AKey, AName, AValue: string);
    procedure WriteInteger(const AKey, AName: string; AValue: Integer);
    procedure DeleteValue(const AKey, AName: string);
    procedure DeleteKey(const AKey: string);
    function FileExists(const AFileName: string): Boolean;
    function DirectoryExists(const ADirectory: string): Boolean;
    procedure CopyFile(const ASource, ATarget: string);
    procedure DeleteFile(const AFileName: string);
    procedure DeleteDirectory(const ADirectory: string);
    procedure DeleteDirectoryLater(const ADirectory: string);
    function FileSize(const AFileName: string): Int64;
    function ReadText(const AFileName: string): string;
    procedure WriteText(const AFileName, AText: string);
    function FilesIn(const ADirectory: string): TArray<string>;
    function RunningExecutables: TArray<string>;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  Winapi.ShellAPI,
  System.Classes,
  System.IOUtils,
  System.Win.Registry;

// Eigene Deklaration: die Signatur in Winapi.Windows unterscheidet sich zwischen Delphi-Versionen.
function QueryImageName(AProcess: THandle; AFlags: DWORD; AName: PWideChar; ASize: PDWORD): BOOL; stdcall;
  external kernel32 name 'QueryFullProcessImageNameW';

function OpenRead(ARoot: HKEY; AAccess: LongWord; const AKey: string): TRegistry;
begin
  Result := TRegistry.Create(AAccess);
  try
    Result.RootKey := ARoot;
    if not Result.OpenKeyReadOnly(AKey) then
      FreeAndNil(Result);
  except
    Result.Free;
    raise;
  end;
end;

function ReadSubKeys(ARoot: HKEY; AAccess: LongWord; const AKey: string): TArray<string>;
var
  Reg: TRegistry;
  Names: TStringList;
begin
  Result := nil;
  Reg := OpenRead(ARoot, AAccess, AKey);
  if Reg = nil then
    Exit;
  Names := TStringList.Create;
  try
    Reg.GetKeyNames(Names);
    Result := Names.ToStringArray;
  finally
    Names.Free;
    Reg.Free;
  end;
end;

function ReadValue(ARoot: HKEY; AAccess: LongWord; const AKey, AName: string): string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := OpenRead(ARoot, AAccess, AKey);
  if Reg = nil then
    Exit;
  try
    if Reg.ValueExists(AName) and (Reg.GetDataType(AName) in [rdString, rdExpandString]) then
      Result := Reg.ReadString(AName);
  finally
    Reg.Free;
  end;
end;

const
  UserAccess = KEY_READ;
  ProcessQueryLimited = $1000;
  // Maschinenzweig in der 64-Bit-Ansicht; WOW6432Node fragt der Kern selbst ab.
  MachineAccess = KEY_READ or KEY_WOW64_64KEY;

{ TSetupWindowsSystem }

function TSetupWindowsSystem.SubKeys(const AKey: string): TArray<string>;
begin
  Result := ReadSubKeys(HKEY_CURRENT_USER, UserAccess, AKey);
end;

function TSetupWindowsSystem.MachineSubKeys(const AKey: string): TArray<string>;
begin
  Result := ReadSubKeys(HKEY_LOCAL_MACHINE, MachineAccess, AKey);
end;

function TSetupWindowsSystem.ReadString(const AKey, AName: string): string;
begin
  Result := ReadValue(HKEY_CURRENT_USER, UserAccess, AKey, AName);
end;

function TSetupWindowsSystem.MachineReadString(const AKey, AName: string): string;
begin
  Result := ReadValue(HKEY_LOCAL_MACHINE, MachineAccess, AKey, AName);
end;

function TSetupWindowsSystem.ReadInteger(const AKey, AName: string; ADefault: Integer): Integer;
var
  Reg: TRegistry;
begin
  Result := ADefault;
  Reg := OpenRead(HKEY_CURRENT_USER, UserAccess, AKey);
  if Reg = nil then
    Exit;
  try
    if Reg.ValueExists(AName) and (Reg.GetDataType(AName) = rdInteger) then
      Result := Reg.ReadInteger(AName);
  finally
    Reg.Free;
  end;
end;

function TSetupWindowsSystem.ValueNames(const AKey: string): TArray<string>;
var
  Reg: TRegistry;
  Names: TStringList;
begin
  Result := nil;
  Reg := OpenRead(HKEY_CURRENT_USER, UserAccess, AKey);
  if Reg = nil then
    Exit;
  Names := TStringList.Create;
  try
    Reg.GetValueNames(Names);
    Result := Names.ToStringArray;
  finally
    Names.Free;
    Reg.Free;
  end;
end;

procedure TSetupWindowsSystem.WriteString(const AKey, AName, AValue: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(AKey, True) then
      raise ERegistryException.Create(AKey);
    Reg.WriteString(AName, AValue);
  finally
    Reg.Free;
  end;
end;

procedure TSetupWindowsSystem.WriteInteger(const AKey, AName: string; AValue: Integer);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey(AKey, True) then
      raise ERegistryException.Create(AKey);
    Reg.WriteInteger(AName, AValue);
  finally
    Reg.Free;
  end;
end;

procedure TSetupWindowsSystem.DeleteValue(const AKey, AName: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(AKey, False) and Reg.ValueExists(AName) and not Reg.DeleteValue(AName) then
      raise ERegistryException.Create(AKey + '\' + AName);
  finally
    Reg.Free;
  end;
end;

procedure TSetupWindowsSystem.DeleteKey(const AKey: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_ALL_ACCESS);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    // TRegistry.DeleteKey löscht die Unterschlüssel mit.
    if Reg.KeyExists(AKey) and not Reg.DeleteKey(AKey) then
      raise ERegistryException.Create(AKey);
  finally
    Reg.Free;
  end;
end;

function TSetupWindowsSystem.FileExists(const AFileName: string): Boolean;
begin
  Result := System.SysUtils.FileExists(AFileName);
end;

function TSetupWindowsSystem.DirectoryExists(const ADirectory: string): Boolean;
begin
  Result := System.SysUtils.DirectoryExists(ADirectory);
end;

procedure TSetupWindowsSystem.CopyFile(const ASource, ATarget: string);
begin
  ForceDirectories(ExtractFileDir(ATarget));
  // Eine geladene BPL ist gesperrt: dann scheitert das Kopieren mit einer Meldung, statt halb zu ersetzen.
  if not Winapi.Windows.CopyFile(PChar(ASource), PChar(ATarget), False) then
    RaiseLastOSError;
end;

procedure TSetupWindowsSystem.DeleteFile(const AFileName: string);
begin
  if System.SysUtils.FileExists(AFileName) and not System.SysUtils.DeleteFile(AFileName) then
    RaiseLastOSError;
end;

procedure TSetupWindowsSystem.DeleteDirectory(const ADirectory: string);
begin
  if System.SysUtils.DirectoryExists(ADirectory) then
    TDirectory.Delete(ADirectory, True);
end;

function TSetupWindowsSystem.FilesIn(const ADirectory: string): TArray<string>;
var
  Path: string;
begin
  Result := nil;
  if not System.SysUtils.DirectoryExists(ADirectory) then
    Exit;
  for Path in TDirectory.GetFiles(ADirectory) do
    Result := Result + [ExtractFileName(Path)];
end;

procedure TSetupWindowsSystem.DeleteDirectoryLater(const ADirectory: string);
var
  Command: string;
begin
  // Der Installer liegt selbst im Ordner: eine unsichtbare Eingabeaufforderung wartet,
  // bis er beendet ist, und löscht dann den Ordner.
  Command := Format('/c ping -n 3 127.0.0.1 >nul & rmdir /s /q "%s"', [ExcludeTrailingPathDelimiter(ADirectory)]);
  if ShellExecute(0, 'open', 'cmd.exe', PChar(Command), nil, SW_HIDE) <= 32 then
    RaiseLastOSError;
end;

function TSetupWindowsSystem.FileSize(const AFileName: string): Int64;
begin
  Result := TFile.GetSize(AFileName);
end;

function TSetupWindowsSystem.ReadText(const AFileName: string): string;
begin
  Result := '';
  if System.SysUtils.FileExists(AFileName) then
    Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
end;

procedure TSetupWindowsSystem.WriteText(const AFileName, AText: string);
var
  Encoding: TEncoding;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  // UTF-8 ohne BOM wie settings.json und die Exportdatei des Plugins.
  Encoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(AFileName, AText, Encoding);
  finally
    Encoding.Free;
  end;
end;

function TSetupWindowsSystem.RunningExecutables: TArray<string>;
var
  Snapshot, Process: THandle;
  Entry: TProcessEntry32;
  Buffer: array[0..MAX_PATH * 2] of Char;
  Size: DWORD;
begin
  Result := nil;
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snapshot = INVALID_HANDLE_VALUE then
    Exit;
  try
    Entry := Default(TProcessEntry32);
    Entry.dwSize := SizeOf(Entry);
    if not Process32First(Snapshot, Entry) then
      Exit;
    repeat
      // Nur bds.exe interessiert; das spart das Öffnen aller anderen Prozesse.
      if SameText(string(Entry.szExeFile), 'bds.exe') then
      begin
        Process := OpenProcess(ProcessQueryLimited, False, Entry.th32ProcessID);
        if Process <> 0 then
          try
            Size := Length(Buffer);
            if QueryImageName(Process, 0, @Buffer[0], @Size) then
              Result := Result + [string(PChar(@Buffer[0]))];
          finally
            CloseHandle(Process);
          end;
      end;
    until not Process32Next(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

end.
