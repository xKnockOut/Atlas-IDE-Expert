unit Atlas.Linux.Diagnostics.ProcessInfo;

// Platform-Feature "Diagnostics" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Diagnostics.ProcessInfo (#647). Die Zahl der Threads steht in
// /proc/self/status, die Rechenzeit des Threads liefert clock_gettime mit
// CLOCK_THREAD_CPUTIME_ID.

interface

type
  TProcessInfo = record
  public
    /// <summary>Threads des eigenen Prozesses; -1, wenn die Abfrage scheitert.</summary>
    class function ThreadCount: Integer; static;
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

class function TProcessInfo.ThreadCount: Integer;
var
  mLines: TStringList;
  mLine: string;
begin
  Result := -1;
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
      if mLine.StartsWith('Threads:') then
      begin
        Exit(StrToIntDef(Trim(Copy(mLine, Length('Threads:') + 1, MaxInt)), -1));
      end;
    end;
  finally
    mLines.Free;
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

end.
