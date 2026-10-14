unit Atlas.Windows.Diagnostics.ProcessInfo;

// Platform-Feature "Diagnostics": Angaben zum eigenen Prozess für die Start-
// und Endzeile des Diagnoselogs (#647), z. B. die Zahl der Threads.

interface

type
  TProcessInfo = record
  public
    /// <summary>Threads des eigenen Prozesses; -1, wenn die Abfrage scheitert.</summary>
    class function ThreadCount: Integer; static;
    /// <summary>Benutzer- und Rechnername; der Filter des Diagnoselogs verwirft Zeilen, die sie enthalten.</summary>
    class function IdentityNames: TArray<string>; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  System.SysUtils;

class function TProcessInfo.ThreadCount: Integer;
var
  Snapshot: THandle;
  Entry: TThreadEntry32;
  ProcessId: DWORD;
begin
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if Snapshot = INVALID_HANDLE_VALUE then
    Exit(-1);
  try
    ProcessId := GetCurrentProcessId;
    Result := 0;
    Entry.dwSize := SizeOf(Entry);
    if Thread32First(Snapshot, Entry) then
      repeat
        if Entry.th32OwnerProcessID = ProcessId then
          Inc(Result);
      until not Thread32Next(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

class function TProcessInfo.IdentityNames: TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in TArray<string>.Create(GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')) do
    if Name <> '' then
      Result := Result + [Name];
end;

end.
