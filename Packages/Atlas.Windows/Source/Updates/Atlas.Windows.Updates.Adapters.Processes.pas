unit Atlas.Windows.Updates.Adapters.Processes;

// Platform-Feature "Updates" (#1519), Adapter: laufende Prozesse und Abbruch.
// - Wer eine BPL aus dem Atlas-Ordner geladen hat, steht in der Modulliste
//   des Prozesses (Toolhelp, 32- und 64-Bit-Module). Prozesse anderer
//   Benutzer lassen sich nicht öffnen; deren IDE lädt ihre eigene Kopie.
// - Strg+C, Strg+Pause und das Schließen des Konsolenfensters setzen den
//   Abbruch; die Logik fragt ihn ab, solange noch nichts getauscht ist.
//   Danach läuft der Tausch zu Ende (Windows wartet beim Schließen einige
//   Sekunden).

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsProcesses = class(TInterfacedObject, IUpdateProcesses)
  public
    constructor Create;
    function UsingPackages(const AFolder: string): TArray<TUpdateProcess>;
    function IsRunning(APid: Cardinal): Boolean;
    procedure Sleep(AMilliseconds: Integer);
    function CancelRequested: Boolean;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32;

const
  // Fehlt in Winapi.TlHelp32.
  cTH32CS_SNAPMODULE32 = $00000010;

var
  GCancelled: Integer;

function ConsoleHandler(ACtrlType: DWORD): BOOL; stdcall;
begin
  InterlockedExchange(GCancelled, 1);
  // Strg+C und Schließen nicht sofort beenden: die Logik entscheidet, ob noch abgebrochen werden darf.
  Result := True;
end;

function LoadsFrom(APid: DWORD; const AFolder: string): Boolean;
var
  mSnapshot: THandle;
  mEntry: TModuleEntry32;
  mPath: string;
begin
  Result := False;
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
      mPath := string(mEntry.szExePath);
      if mPath.EndsWith('.bpl', True) and SameText(Copy(mPath, 1, Length(AFolder)), AFolder) then
      begin
        Exit(True);
      end;
    until not Module32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

{ TUpdateWindowsProcesses }

constructor TUpdateWindowsProcesses.Create;
begin
  inherited Create;
  SetConsoleCtrlHandler(@ConsoleHandler, True);
end;

function TUpdateWindowsProcesses.UsingPackages(const AFolder: string): TArray<TUpdateProcess>;
var
  mSnapshot: THandle;
  mEntry: TProcessEntry32;
  mProcess: TUpdateProcess;
  mFolder: string;
begin
  Result := nil;
  mFolder := IncludeTrailingPathDelimiter(AFolder);
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
      if (mEntry.th32ProcessID <> GetCurrentProcessId) and (mEntry.th32ProcessID <> 0) and
        LoadsFrom(mEntry.th32ProcessID, mFolder) then
      begin
        mProcess.Pid := mEntry.th32ProcessID;
        mProcess.Name := string(mEntry.szExeFile);
        Result := Result + [mProcess];
      end;
    until not Process32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

function TUpdateWindowsProcesses.IsRunning(APid: Cardinal): Boolean;
var
  mHandle: THandle;
begin
  mHandle := OpenProcess(SYNCHRONIZE, False, APid);
  Result := mHandle <> 0;
  if Result then
  begin
    Result := WaitForSingleObject(mHandle, 0) = WAIT_TIMEOUT;
    CloseHandle(mHandle);
  end;
end;

procedure TUpdateWindowsProcesses.Sleep(AMilliseconds: Integer);
begin
  Winapi.Windows.Sleep(AMilliseconds);
end;

function TUpdateWindowsProcesses.CancelRequested: Boolean;
begin
  Result := InterlockedCompareExchange(GCancelled, 0, 0) <> 0;
end;

end.
