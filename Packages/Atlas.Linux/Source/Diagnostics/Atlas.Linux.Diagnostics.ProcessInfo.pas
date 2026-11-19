unit Atlas.Linux.Diagnostics.ProcessInfo;

// Platform-Feature "Diagnostics" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Diagnostics.ProcessInfo (#647). Die Zahl der Threads steht in
// /proc/self/status, die Rechenzeit des Threads liefert clock_gettime mit
// CLOCK_THREAD_CPUTIME_ID. Den belegten Speicher des Prozesses (#1480) liefert
// VmRSS in /proc/self/status: Der Heap von Free Pascal zählt je Thread.

interface

type
  TProcessInfo = record
  public
    /// <summary>Threads des eigenen Prozesses; -1, wenn die Abfrage scheitert.</summary>
    class function ThreadCount: Integer; static;
    /// <summary>Belegter Speicher des Prozesses im RAM in Byte (VmRSS); -1, wenn die Abfrage scheitert.</summary>
    class function ResidentBytes: Int64; static;
    /// <summary>Benutzer- und Rechnername; der Filter des Diagnoselogs verwirft Zeilen, die sie enthalten.</summary>
    class function IdentityNames: TArray<string>; static;
    /// <summary>Rechenzeit (Kernel und Benutzer) des aufrufenden Threads in ms;
    /// -1, wenn die Abfrage scheitert.</summary>
    class function ThreadCpuMs: Int64; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  BaseUnix,
  Linux;

/// <summary>Wert hinter AKey (etwa 'Threads:') in /proc/self/status ohne Einheit; '' ohne.</summary>
function StatusValue(const AKey: string): string;
var
  mLines: TStringList;
  mLine: string;
begin
  Result := '';
  mLines := TStringList.Create;
  try
    try
      mLines.LoadFromFile('/proc/self/status', TEncoding.UTF8);
    except
      on EStreamError do
        Exit;
    end;
    for mLine in mLines do
    begin
      if mLine.StartsWith(AKey) then
      begin
        Exit(Trim(Copy(mLine, Length(AKey) + 1, MaxInt)).Replace(' kB', ''));
      end;
    end;
  finally
    mLines.Free;
  end;
end;

{ TProcessInfo }

class function TProcessInfo.ThreadCount: Integer;
begin
  Result := StrToIntDef(StatusValue('Threads:'), -1);
end;

class function TProcessInfo.ResidentBytes: Int64;
begin
  Result := StrToInt64Def(StatusValue('VmRSS:'), -1);
  if Result > 0 then
  begin
    Result := Result * 1024;
  end;
end;

class function TProcessInfo.IdentityNames: TArray<string>;
var
  mName: string;
  mHost: UtsName;
  mHostName: string;
begin
  Result := nil;
  mHostName := '';
  if FpUname(mHost) = 0 then
  begin
    mHostName := string(PAnsiChar(@mHost.Nodename[0]));
  end;
  for mName in TArray<string>.Create(GetEnvironmentVariable('USER'), GetEnvironmentVariable('LOGNAME'), mHostName) do
  begin
    if (mName <> '') and (IndexStr(mName, Result) < 0) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TProcessInfo.ThreadCpuMs: Int64;
var
  mTime: timespec;
begin
  if clock_gettime(CLOCK_THREAD_CPUTIME_ID, @mTime) <> 0 then
  begin
    Exit(-1);
  end;
  Result := Int64(mTime.tv_sec) * 1000 + Int64(mTime.tv_nsec) div 1000000;
end;

end.
