unit Atlas.IDE.Build.RunningProcesses;

// Laufendes Programm vor dem Build beenden (#551), Adapter zu Windows:
// - Programs: alle laufenden Prozesse mit vollständigem Pfad (Toolhelp und
//   QueryFullProcessImageName; Prozesse ohne Zugriff fehlen).
// - LoadingModule: Prozesse, die eine Datei (BPL) geladen haben (Modulliste,
//   32- und 64-Bit-Module).
// - Stop: erst freundlich (WM_CLOSE an die Hauptfenster), nach der Wartezeit
//   hart (TerminateProcess), dann warten, bis Windows die Datei freigibt.
// Nur im Hauptthread (Stop wartet höchstens Wartezeit plus Abschluss).

interface

uses
  Atlas.Core.Build.RunningProgram;

type
  TAtlasIdeRunningProcesses = record
  public const
    /// <summary>So lange wartet Stop nach TerminateProcess auf das Ende.</summary>
    cTerminateWaitMs = 3000;
  public
    /// <summary>Laufende Prozesse mit Pfad des Programms.</summary>
    class function Programs: TArray<TAtlasRunningProcess>; static;
    /// <summary>Prozesse, die AFileName geladen haben; Path ist dann der Pfad des Moduls.</summary>
    class function LoadingModule(const AFileName: string): TArray<TAtlasRunningProcess>; static;
    /// <summary>Prozess beenden (WM_CLOSE, nach AGraceMs TerminateProcess); True, wenn er nicht mehr läuft.</summary>
    class function Stop(APid: Cardinal; AGraceMs: Integer): Boolean; static;
    /// <summary>Kennung der IDE.</summary>
    class function OwnPid: Cardinal; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.TlHelp32,
  System.SysUtils;

const
  // Fehlt in Delphis Winapi.Windows bzw. Winapi.TlHelp32.
  cProcessQueryLimitedInformation = $1000;
  cTH32CS_SNAPMODULE32 = $00000010;
  cPollMs = 50;

function QueryFullProcessImageNameW(AProcess: THandle; AFlags: DWORD; AExeName: PWideChar;
  var ASize: DWORD): BOOL; stdcall; external kernel32 name 'QueryFullProcessImageNameW';

function ImagePath(APid: DWORD): string;
var
  mProcess: THandle;
  mBuffer: array[0..MAX_PATH * 2] of WideChar;
  mSize: DWORD;
begin
  Result := '';
  mProcess := OpenProcess(cProcessQueryLimitedInformation, False, APid);
  if mProcess = 0 then
  begin
    Exit;
  end;
  try
    mSize := Length(mBuffer);
    if QueryFullProcessImageNameW(mProcess, 0, @mBuffer[0], mSize) then
    begin
      SetString(Result, PWideChar(@mBuffer[0]), mSize);
    end;
  finally
    CloseHandle(mProcess);
  end;
end;

class function TAtlasIdeRunningProcesses.Programs: TArray<TAtlasRunningProcess>;
var
  mSnapshot: THandle;
  mEntry: TProcessEntry32;
  mPath: string;
begin
  Result := nil;
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    mEntry := Default(TProcessEntry32);
    mEntry.dwSize := SizeOf(mEntry);
    if not Process32First(mSnapshot, mEntry) then
    begin
      Exit;
    end;
    repeat
      mPath := ImagePath(mEntry.th32ProcessID);
      if mPath <> '' then
      begin
        Result := Result + [TAtlasRunningProcess.Create(mEntry.th32ProcessID, mPath, string(mEntry.szExeFile))];
      end;
    until not Process32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

/// <summary>Pfad des Moduls AFileName in APid; '' ohne Zugriff oder ohne Modul.</summary>
function LoadedModule(APid: DWORD; const AFileName: string): string;
var
  mSnapshot: THandle;
  mEntry: TModuleEntry32;
begin
  Result := '';
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPMODULE or cTH32CS_SNAPMODULE32, APid);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    mEntry := Default(TModuleEntry32);
    mEntry.dwSize := SizeOf(mEntry);
    if not Module32First(mSnapshot, mEntry) then
    begin
      Exit;
    end;
    repeat
      if TAtlasRunningProgram.SamePath(string(mEntry.szExePath), AFileName) then
      begin
        Exit(string(mEntry.szExePath));
      end;
    until not Module32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

class function TAtlasIdeRunningProcesses.LoadingModule(const AFileName: string): TArray<TAtlasRunningProcess>;
var
  mProcess: TAtlasRunningProcess;
  mModule: string;
begin
  Result := nil;
  for mProcess in Programs do
  begin
    // Die IDE hat ihre Packages selbst geladen; sie entlädt sie vor dem Compile.
    if mProcess.Pid = OwnPid then
    begin
      Continue;
    end;
    mModule := LoadedModule(mProcess.Pid, AFileName);
    if mModule <> '' then
    begin
      Result := Result + [TAtlasRunningProcess.Create(mProcess.Pid, mModule, mProcess.Name)];
    end;
  end;
end;

function CloseWindow(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
var
  mPid: DWORD;
begin
  mPid := 0;
  GetWindowThreadProcessId(AWindow, @mPid);
  if (mPid = DWORD(AParam)) and IsWindowVisible(AWindow) and (GetWindow(AWindow, GW_OWNER) = 0) then
  begin
    PostMessage(AWindow, WM_CLOSE, 0, 0);
  end;
  Result := True;
end;

/// <summary>Wartet bis zu AMs auf das Ende von AProcess; True, wenn er beendet ist.</summary>
function Ended(AProcess: THandle; AMs: Integer): Boolean;
begin
  Result := WaitForSingleObject(AProcess, DWORD(AMs)) = WAIT_OBJECT_0;
end;

class function TAtlasIdeRunningProcesses.Stop(APid: Cardinal; AGraceMs: Integer): Boolean;
var
  mProcess: THandle;
  mWaited: Integer;
begin
  mProcess := OpenProcess(SYNCHRONIZE or PROCESS_TERMINATE, False, APid);
  if mProcess = 0 then
  begin
    Exit(False);
  end;
  try
    EnumWindows(@CloseWindow, LPARAM(APid));
    mWaited := 0;
    while mWaited < AGraceMs do
    begin
      if Ended(mProcess, cPollMs) then
      begin
        Exit(True);
      end;
      Inc(mWaited, cPollMs);
    end;
    Result := TerminateProcess(mProcess, 1) and Ended(mProcess, cTerminateWaitMs);
  finally
    CloseHandle(mProcess);
  end;
end;

class function TAtlasIdeRunningProcesses.OwnPid: Cardinal;
begin
  Result := GetCurrentProcessId;
end;

end.
