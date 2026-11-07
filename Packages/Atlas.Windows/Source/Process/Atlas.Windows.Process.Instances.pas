unit Atlas.Windows.Process.Instances;

// Laufende Prozesse nach Programmname (#261): Vor dem Start einer eigenen
// Scratch-IDE über cc.ps1 merkt sich der Server alle laufenden bds.exe; die
// gestartete IDE darf keine davon sein, damit die IDE des Benutzers nie
// angesprochen wird. Running prüft vor dem Wiederverwenden, ob die eigene
// Instanz noch läuft.

interface

uses
  System.SysUtils;

type
  TProcessInstances = class
  public
    /// <summary>Nummern aller laufenden Prozesse mit dem Programmnamen AExeName (z. B. "bds.exe",
    /// Groß- und Kleinschreibung egal).</summary>
    class function IdsOf(const AExeName: string): TArray<Cardinal>; static;
    /// <summary>True, solange der Prozess APid läuft.</summary>
    class function Running(APid: Cardinal): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32;

class function TProcessInstances.IdsOf(const AExeName: string): TArray<Cardinal>;
var
  mSnapshot: THandle;
  mEntry: TProcessEntry32;
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
      if SameText(string(mEntry.szExeFile), AExeName) then
      begin
        Result := Result + [mEntry.th32ProcessID];
      end;
    until not Process32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

class function TProcessInstances.Running(APid: Cardinal): Boolean;
const
  cQueryLimitedInformation = $1000;
var
  mProcess: THandle;
  mCode: Cardinal;
begin
  if APid = 0 then
  begin
    Exit(False);
  end;
  mProcess := OpenProcess(cQueryLimitedInformation, False, APid);
  if mProcess = 0 then
  begin
    Exit(False);
  end;
  try
    Result := GetExitCodeProcess(mProcess, mCode) and (mCode = STILL_ACTIVE);
  finally
    CloseHandle(mProcess);
  end;
end;

end.
