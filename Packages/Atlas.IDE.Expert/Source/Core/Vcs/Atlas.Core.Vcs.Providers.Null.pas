unit Atlas.Core.Vcs.Providers.Null;

// Leere Umsetzung (#571): ohne Arbeitskopie, mit vcs.provider = off oder wenn
// git bzw. svn fehlt. Alle Aufrufe kehren sofort ohne Prozess zurück und
// liefern keine Versionsangaben, nie einen Fehler; Outcome sagt, warum. Das
// gilt auch für IAtlasVcsLocalWork (#762).

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasNullVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork)
  private
    FOutcome: TAtlasVcsOutcome;
  public
    /// <summary>AOutcome: NoWorkingCopy, Disabled oder ToolMissing.</summary>
    constructor Create(AOutcome: TAtlasVcsOutcome); overload;
    constructor Create; overload;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    { IAtlasVcsLocalWork }
    function Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
    function Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
    function Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
    function Outgoing(const ABranch, AUpstream: string; AMax: Integer;
      out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
    function ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
    property Outcome: TAtlasVcsOutcome read FOutcome;
  end;

implementation

{ TAtlasNullVersionControl }

constructor TAtlasNullVersionControl.Create(AOutcome: TAtlasVcsOutcome);
begin
  inherited Create;
  FOutcome := AOutcome;
end;

constructor TAtlasNullVersionControl.Create;
begin
  Create(TAtlasVcsOutcome.NoWorkingCopy);
end;

function TAtlasNullVersionControl.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.None;
end;

function TAtlasNullVersionControl.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
end;

function TAtlasNullVersionControl.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Blame(const AFileName: string;
  out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.ChangeMarker: string;
begin
  Result := '';
end;

function TAtlasNullVersionControl.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
begin
  ABranches := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
begin
  AStashes := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
begin
  ANames := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.ChangesIn(const ARevision: string;
  out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Push(const ABranch, ARemote, ARemoteRef: string;
  ASetUpstream: Boolean): TAtlasVcsOutcome;
begin
  Result := FOutcome;
end;

end.
