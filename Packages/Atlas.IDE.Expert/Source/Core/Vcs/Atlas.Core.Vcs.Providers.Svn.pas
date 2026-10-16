unit Atlas.Core.Vcs.Providers.Svn;

// SVN über die Kommandozeile svn (#571; TortoiseSVN mit
// Kommandozeilenwerkzeugen genügt). Dieselbe Umsetzung nutzt der Server für
// --changed mit SVN (#276, Shell.VcsChanges). Jeder Aufruf läuft in der Wurzel
// der Arbeitskopie mit --non-interactive (nie eine Rückfrage nach Kennwort
// oder Zertifikat) und, wo möglich, --xml (UTF-8 unabhängig von der Konsole).
// Befehle; alle lesen nur die Arbeitskopie, keiner spricht mit dem Server:
//   Head      info --xml
//   Changes   status --xml
//   FileAt    cat -r <Revision> <Pfad>      (Revision '' = BASE)
//   Blame     blame --xml <Pfad>            (Blame spricht mit dem Server)
// Nicht gesicherte Arbeit (IAtlasVcsLocalWork, #762): SVN kennt weder lokale
// Commits noch Stashes oder lokale Branches; was nicht übertragen ist, sind
// die geänderten Dateien (Changes). Branches, Stashes, Remotes und Outgoing
// liefern deshalb ohne Prozess Ok mit leerer Liste, ChangesIn und Push Failed.
// Eingehende Commits (IAtlasVcsIncoming, #755): SVN hält keinen lokalen
// Stand des Servers; Resolve liefert '', Incoming eine leere Liste, Fetch tut
// nichts (alle Ok ohne Prozess).
// Holen (IAtlasVcsUpdate, #764): Pull = update . (spricht mit dem Server).
// ChangeMarker: Zeitstempel und Größe von .svn/wc.db; svn update und
// svn switch schreiben die Datenbank.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools;

type
  TAtlasSvnVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork, IAtlasVcsIncoming,
    IAtlasVcsUpdate)
  private
    FRoot: string;
    FCommand: TAtlasVcsCommand;
    function Svn(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
  public
    /// <summary>ARoot: Ordner mit .svn. AExecutable: vollständiger Pfad von svn ('' = nicht installiert).</summary>
    constructor Create(const ARoot: string; const ARunner: IAtlasVcsRunner; const AExecutable: string;
      ATimeoutMs: Cardinal); overload;
    constructor Create(const ARoot: string; const ARunner: IAtlasVcsRunner; const AExecutable: string); overload;
    destructor Destroy; override;
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
  end;

implementation

uses
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.SvnParser;

{ TAtlasSvnVersionControl }

constructor TAtlasSvnVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FRoot := VcsNormalizeDir(ARoot);
  FCommand := TAtlasVcsCommand.Create(ARunner, AExecutable, FRoot, ATimeoutMs);
end;

constructor TAtlasSvnVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string);
begin
  Create(ARoot, ARunner, AExecutable, TAtlasVcsCommand.DefaultTimeoutMs);
end;

destructor TAtlasSvnVersionControl.Destroy;
begin
  FCommand.Free;
  inherited;
end;

function TAtlasSvnVersionControl.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Svn;
end;

function TAtlasSvnVersionControl.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result.Kind := TAtlasVcsKind.Svn;
  Result.Root := FRoot;
end;

function TAtlasSvnVersionControl.Svn(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
begin
  Result := FCommand.Run(AArguments + ['--non-interactive'], AOutput);
end;

function TAtlasSvnVersionControl.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
var
  Output: TBytes;
  Info: TAtlasSvnInfo;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := Svn(['info', '--xml', '.'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    Info := TAtlasSvnParser.ParseInfo(VcsUtf8(Output));
    AHead.Branch := TAtlasSvnParser.BranchOf(Info.RelativeUrl);
    AHead.Revision := Info.Revision;
  except
    on EAtlasVcsParse do
    begin
      AHead := TAtlasVcsHead.Empty;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasSvnVersionControl.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AChanges := nil;
  Result := Svn(['status', '--xml', '.'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    AChanges := TAtlasSvnParser.ParseStatus(VcsUtf8(Output), FRoot);
  except
    on EAtlasVcsParse do
    begin
      AChanges := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasSvnVersionControl.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
var
  Relative, Revision: string;
begin
  AContent := nil;
  if not VcsRelativePath(FRoot, AFileName, Relative) then
    Exit(TAtlasVcsOutcome.Failed);
  Revision := Trim(ARevision);
  if Revision = '' then
    Revision := 'BASE';
  if Revision[1] = '-' then
    Exit(TAtlasVcsOutcome.Failed);
  // "@" am Ende: ein "@" im Dateinamen wäre sonst eine Peg-Revision.
  Result := Svn(['cat', '-r', Revision, Relative + '@'], AContent);
end;

function TAtlasSvnVersionControl.Blame(const AFileName: string;
  out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
var
  Relative: string;
  Output: TBytes;
begin
  ALines := nil;
  if not VcsRelativePath(FRoot, AFileName, Relative) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := Svn(['blame', '--xml', Relative + '@'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    ALines := TAtlasSvnParser.ParseBlame(VcsUtf8(Output));
  except
    on EAtlasVcsParse do
    begin
      ALines := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasSvnVersionControl.ChangeMarker: string;
var
  Database: string;
  Age: TDateTime;
  Info: TSearchRec;
begin
  Database := IncludeTrailingPathDelimiter(FRoot) + '.svn' + PathDelim + 'wc.db';
  if not FileAge(Database, Age) then
    Exit('');
  Result := FloatToStr(Age);
  if FindFirst(Database, faAnyFile, Info) = 0 then
  try
    Result := Result + '|' + IntToStr(Info.Size);
  finally
    FindClose(Info);
  end;
end;

{ IAtlasVcsLocalWork: in SVN gibt es nichts davon }

function TAtlasSvnVersionControl.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
begin
  ABranches := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
begin
  AStashes := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
begin
  ANames := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.ChangesIn(const ARevision: string;
  out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TAtlasSvnVersionControl.Push(const ABranch, ARemote, ARemoteRef: string;
  ASetUpstream: Boolean): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Failed;
end;

{ IAtlasVcsIncoming (#755) }

function TAtlasSvnVersionControl.Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
begin
  ARevision := '';
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
  out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.Fetch(const ARemote: string): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Ok;
end;

{ IAtlasVcsUpdate (#764) }

function TAtlasSvnVersionControl.Pull: TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  Result := Svn(['update', '.'], Output);
end;

end.
