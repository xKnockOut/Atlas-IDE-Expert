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
  mLines: TStringList;
begin
  Result := ExtractFileName(string(FpReadLink(RawByteString(AProcDir + '/exe'))));
  if Result <> '' then
  begin
    Exit;
  end;
  mLines := TStringList.Create;
  try
    try
      mLines.LoadFromFile(AProcDir + '/comm', TEncoding.UTF8);
    except
      on EStreamError do
        Exit('');
    end;
    if mLines.Count > 0 then
    begin
      Result := Trim(mLines[0]);
    end;
  finally
    mLines.Free;
  end;
end;

{ TProcessInstances }

class function TProcessInstances.IdsOf(const AExeName: string): TArray<Cardinal>;
var
  mSearch: TSearchRec;
  mPid: Integer;
begin
  Result := nil;
  if FindFirst('/proc/*', faDirectory, mSearch) <> 0 then
  begin
    Exit;
  end;
  try
    repeat
      if TryStrToInt(mSearch.Name, mPid) and (mPid > 0) and
        SameText(ProgramNameOf('/proc/' + mSearch.Name), AExeName) then
      begin
        Result := Result + [Cardinal(mPid)];
      end;
    until FindNext(mSearch) <> 0;
  finally
    FindClose(mSearch);
  end;
end;

class function TProcessInstances.Running(APid: Cardinal): Boolean;
begin
  Result := TParentWatcher.Running(APid);
end;

end.
