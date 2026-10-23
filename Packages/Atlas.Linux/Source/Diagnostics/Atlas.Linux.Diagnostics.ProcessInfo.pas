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
    /// <summary>Rechenzeit (Kernel und Benutzer) des aufrufenden Threads in ms; -1, wenn die Abfrage scheitert.</summary>
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
  Lines: TStringList;
  Line: string;
begin
  Result := -1;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile('/proc/self/status', TEncoding.UTF8);
    except
      on EStreamError do
        Exit;
    end;
    for Line in Lines do
      if Line.StartsWith('Threads:') then
        Exit(StrToIntDef(Trim(Copy(Line, Length('Threads:') + 1, MaxInt)), -1));
  finally
    Lines.Free;
  end;
end;

class function TProcessInfo.ThreadCpuMs: Int64;
var
  Time: timespec;
begin
  if clock_gettime(CLOCK_THREAD_CPUTIME_ID, @Time) <> 0 then
    Exit(-1);
  Result := Int64(Time.tv_sec) * 1000 + Int64(Time.tv_nsec) div 1000000;
end;

class function TProcessInfo.IdentityNames: TArray<string>;
var
  Name: string;
  Host: UtsName;
  HostName: string;
begin
  Result := nil;
  HostName := '';
  if FpUname(Host) = 0 then
    HostName := string(PAnsiChar(@Host.Nodename[0]));
  for Name in TArray<string>.Create(GetEnvironmentVariable('USER'), GetEnvironmentVariable('LOGNAME'), HostName) do
    if (Name <> '') and (IndexStr(Name, Result) < 0) then
      Result := Result + [Name];
end;

end.
