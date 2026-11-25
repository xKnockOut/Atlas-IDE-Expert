unit Atlas.Common.Index.Processes.TestSupport;

// Gemeinsame Hilfen der Tests zu Indexprozessen.

interface

uses
  Atlas.Common.Index.Processes;

/// <summary>Angaben eines Prozesses APid der Art AKind im Arbeitsbereich Kasse.</summary>
function Info(APid: Cardinal; const AKind: string): TIndexProcessInfo;

implementation

function Info(APid: Cardinal; const AKind: string): TIndexProcessInfo;
begin
  Result := Default(TIndexProcessInfo);
  Result.Pid := APid;
  Result.Kind := AKind;
  Result.Client := 'Claude Code';
  Result.Workspace := 'Kasse';
end;

end.
