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
    /// <summary>Rechenzeit (Kernel und Benutzer) des aufrufenden Threads in ms; -1, wenn die Abfrage scheitert.
    /// Liegt sie weit unter der Laufzeit einer Anfrage, hat der Thread gewartet (#647).</summary>
    class function ThreadCpuMs: Int64; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  System.SysUtils;

class function TProcessInfo.ThreadCount: Integer;
var
  mSnapshot: THandle;
  mEntry: TThreadEntry32;
  mProcessId: DWORD;
begin
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit(-1);
  end;
  try
    mProcessId := GetCurrentProcessId;
    Result := 0;
    mEntry.dwSize := SizeOf(mEntry);
    if Thread32First(mSnapshot, mEntry) then
      repeat
        if mEntry.th32OwnerProcessID = mProcessId then
        begin
          Inc(Result);
        end;
      until not Thread32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

class function TProcessInfo.ThreadCpuMs: Int64;
var
  mCreation, mExited, mKernel, mUser: TFileTime;
begin
  if not GetThreadTimes(GetCurrentThread, mCreation, mExited, mKernel, mUser) then
  begin
    Exit(-1);
  end;
  // FILETIME zählt in 100 ns.
  Result := (Int64(mKernel.dwHighDateTime) shl 32 + mKernel.dwLowDateTime +
    Int64(mUser.dwHighDateTime) shl 32 + mUser.dwLowDateTime) div 10000;
end;

class function TProcessInfo.IdentityNames: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in TArray<string>.Create(GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')) do
  begin
    if mName <> '' then
    begin
      Result := Result + [mName];
    end;
  end;
end;

end.
