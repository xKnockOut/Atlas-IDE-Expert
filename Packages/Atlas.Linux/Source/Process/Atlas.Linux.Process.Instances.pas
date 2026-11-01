unit Atlas.Linux.Process.Instances;

// Platform-Feature "Process" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Process.Instances. Die Prozessliste steht unter /proc; der
// Programmname eines Prozesses ist der Dateiname von /proc/<pid>/exe bzw.,
// ohne Leserecht darauf, /proc/<pid>/comm.

interface

uses
  System.SysUtils;

type
  TProcessInstances = class
  public
    /// <summary>Nummern aller laufenden Prozesse mit dem Programmnamen AExeName (Groß- und
    /// Kleinschreibung egal).</summary>
    class function IdsOf(const AExeName: string): TArray<Cardinal>; static;
    /// <summary>True, solange der Prozess APid läuft.</summary>
    class function Running(APid: Cardinal): Boolean; static;
  end;

implementation

uses
  System.Classes,
  BaseUnix,
  Atlas.Linux.Process.ParentWatcher;

function ProgramNameOf(const AProcDir: string): string;
var
  Lines: TStringList;
begin
  Result := ExtractFileName(string(FpReadLink(RawByteString(AProcDir + '/exe'))));
  if Result <> '' then
  begin
    Exit;
  end;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AProcDir + '/comm', TEncoding.UTF8);
    except
      on EStreamError do
        Exit('');
    end;
    if Lines.Count > 0 then
    begin
      Result := Trim(Lines[0]);
    end;
  finally
    Lines.Free;
  end;
end;

{ TProcessInstances }

class function TProcessInstances.IdsOf(const AExeName: string): TArray<Cardinal>;
var
  Search: TSearchRec;
  Pid: Integer;
begin
  Result := nil;
  if FindFirst('/proc/*', faDirectory, Search) <> 0 then
  begin
    Exit;
  end;
  try
    repeat
      if TryStrToInt(Search.Name, Pid) and (Pid > 0) and
        SameText(ProgramNameOf('/proc/' + Search.Name), AExeName) then
      begin
        Result := Result + [Cardinal(Pid)];
      end;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

class function TProcessInstances.Running(APid: Cardinal): Boolean;
begin
  Result := TParentWatcher.Running(APid);
end;

end.
