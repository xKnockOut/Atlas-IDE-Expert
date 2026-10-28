unit Atlas.Core.Vcs.Providers.Null;

// Leere Umsetzung (#571): ohne Arbeitskopie, mit vcs.provider = off oder wenn
// git bzw. svn fehlt. Alle Aufrufe kehren sofort ohne Prozess zurück und
// liefern keine Versionsangaben, nie einen Fehler; Outcome sagt, warum. Das
// gilt auch für IAtlasVcsLocalWork (#762), IAtlasVcsIncoming (#755) und
// IAtlasVcsUpdate (#764), IAtlasVcsBranching (#765), IAtlasVcsLineHistory (#1275) und
// IAtlasVcsHistory (#1269).

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasNullVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork, IAtlasVcsIncoming,
    IAtlasVcsUpdate, IAtlasVcsBranching, IAtlasVcsLineHistory, IAtlasVcsHistory)
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
    { IAtlasVcsIncoming }
    function Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
    function Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
      out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
    function Fetch(const ARemote: string): TAtlasVcsOutcome;
    { IAtlasVcsUpdate }
    function Pull: TAtlasVcsOutcome;
    { IAtlasVcsBranching }
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome; overload;
    /// <summary>SVN-Optionen (#1290) gelten hier nicht: wie oben.</summary>
    function BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
      out AExists: Boolean): TAtlasVcsOutcome; overload;
    function RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    function ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
    function HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
    function RepositoryPath(out APath: string): TAtlasVcsOutcome;
    function RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
    function SwitchBranch(const AName: string): TAtlasVcsOutcome; overload;
    function SwitchBranch(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
      overload;
    function HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
    { IAtlasVcsLineHistory }
    function Messages(const AFileName: string; const ARevisions: TArray<string>;
      out AMessages: TArray<TAtlasVcsRevisionMessage>): TAtlasVcsOutcome;
    function LineHistory(const AFileName: string; AFirstLine, ALastLine, AMaxRevisions: Integer;
      out ACommits: TArray<TAtlasVcsLineCommit>): TAtlasVcsOutcome;
    { IAtlasVcsHistory }
    function SearchLog(const AText: string; AMax: Integer; out AEntries: TArray<TAtlasVcsLogEntry>): TAtlasVcsOutcome;
    function AllBranches(out ABranches: TArray<TAtlasVcsRef>): TAtlasVcsOutcome;
    function Distance(const ABranch, ABase: string; out AAhead, ABehind: Integer): TAtlasVcsOutcome;
    function ContentOf(const ARevision: string; const AFile: TAtlasVcsLogFile; ABefore: Boolean;
      out AContent: TBytes): TAtlasVcsOutcome;
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

{ IAtlasVcsIncoming (#755) }

function TAtlasNullVersionControl.Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
begin
  ARevision := '';
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
  out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Fetch(const ARemote: string): TAtlasVcsOutcome;
begin
  Result := FOutcome;
end;

{ IAtlasVcsUpdate (#764) }

function TAtlasNullVersionControl.Pull: TAtlasVcsOutcome;
begin
  Result := FOutcome;
end;

{ IAtlasVcsBranching (#765) }

function TAtlasNullVersionControl.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  AExists := False;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out AExists: Boolean): TAtlasVcsOutcome;
begin
  Result := BranchExists(AName, AExists);
end;

function TAtlasNullVersionControl.RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  AExists := False;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
begin
  ARevision := '';
  Result := FOutcome;
end;

function TAtlasNullVersionControl.HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
begin
  AHas := False;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.RepositoryPath(out APath: string): TAtlasVcsOutcome;
begin
  APath := '';
  Result := FOutcome;
end;

function TAtlasNullVersionControl.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
begin
  Result := FOutcome;
end;

function TAtlasNullVersionControl.SwitchBranch(const AName: string): TAtlasVcsOutcome;
begin
  Result := FOutcome;
end;

function TAtlasNullVersionControl.SwitchBranch(const AName: string;
  const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
begin
  Result := SwitchBranch(AName);
end;

function TAtlasNullVersionControl.HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
begin
  AHooks := '';
  AGitDir := '';
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Messages(const AFileName: string; const ARevisions: TArray<string>;
  out AMessages: TArray<TAtlasVcsRevisionMessage>): TAtlasVcsOutcome;
begin
  AMessages := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.LineHistory(const AFileName: string; AFirstLine, ALastLine,
  AMaxRevisions: Integer; out ACommits: TArray<TAtlasVcsLineCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := FOutcome;
end;

{ IAtlasVcsHistory (#1269) }

function TAtlasNullVersionControl.SearchLog(const AText: string; AMax: Integer;
  out AEntries: TArray<TAtlasVcsLogEntry>): TAtlasVcsOutcome;
begin
  AEntries := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.AllBranches(out ABranches: TArray<TAtlasVcsRef>): TAtlasVcsOutcome;
begin
  ABranches := nil;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.Distance(const ABranch, ABase: string; out AAhead,
  ABehind: Integer): TAtlasVcsOutcome;
begin
  AAhead := -1;
  ABehind := -1;
  Result := FOutcome;
end;

function TAtlasNullVersionControl.ContentOf(const ARevision: string; const AFile: TAtlasVcsLogFile;
  ABefore: Boolean; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := FOutcome;
end;

end.
