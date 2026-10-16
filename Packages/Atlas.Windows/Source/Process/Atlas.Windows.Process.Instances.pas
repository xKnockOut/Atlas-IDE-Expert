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
  Snapshot: THandle;
  Entry: TProcessEntry32;
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
      if SameText(string(Entry.szExeFile), AExeName) then
        Result := Result + [Entry.th32ProcessID];
    until not Process32Next(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

class function TProcessInstances.Running(APid: Cardinal): Boolean;
const
  QueryLimitedInformation = $1000;
var
  Process: THandle;
  Code: Cardinal;
begin
  if APid = 0 then
    Exit(False);
  Process := OpenProcess(QueryLimitedInformation, False, APid);
  if Process = 0 then
    Exit(False);
  try
    Result := GetExitCodeProcess(Process, Code) and (Code = STILL_ACTIVE);
  finally
    CloseHandle(Process);
  end;
end;

end.
