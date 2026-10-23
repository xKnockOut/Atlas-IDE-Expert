unit Atlas.Core.Vcs.Providers.Git;

// Git über die Kommandozeile (#571). Jeder Aufruf läuft in der Wurzel des
// Repositorys mit
//   --no-optional-locks   status schreibt den Index nicht zurück und stört so
//                         nie ein gleichzeitiges git im Terminal oder Client
//   -c core.quotepath=off Pfade als UTF-8 statt Oktalfolgen
//   -c color.ui=false     keine Farbcodes
// Befehle:
//   Head      status --porcelain=v2 --branch -z --untracked-files=no
//   Changes   status --porcelain=v2 --branch -z --untracked-files=all
//   FileAt    show <Revision>:<Pfad>        (Revision '' = HEAD)
//   Blame     blame --porcelain -- <Pfad>
// Nicht gesicherte Arbeit (IAtlasVcsLocalWork, #762), ohne fetch:
//   Branches  for-each-ref --format=… refs/heads
//   Stashes   stash list --format=…
//   Remotes   remote
//   Outgoing  log --format=… --max-count=N refs/heads/<Branch> --not <Upstream>|--remotes
//   ChangesIn diff --name-status -z --no-renames <Revision>^1 <Revision>
//   Push      push --porcelain [--set-upstream] <Remote> refs/heads/<Branch>:<Ref>
// Eingehende Commits (IAtlasVcsIncoming, #755):
//   Resolve   rev-parse --verify --quiet <Ref>^{commit}
//   Incoming  log --format=… --name-only -z --no-renames --max-count=N <Upstream> --not <Stände>
//   Fetch     -c credential.interactive=never -c core.askPass= fetch --quiet --no-tags [<Remote>]
//             (Git Credential Manager fragt nicht, git selbst ruft kein
//             Kennwortfenster; ohne Konsole und mit stdin NUL fragt git auch
//             im Terminal nicht nach. Das Zeitlimit setzt der Aufrufer.)
// Holen (IAtlasVcsUpdate, #764):
//   Pull      -c credential.interactive=never -c core.askPass= pull --ff-only --no-rebase --quiet
// Branch für ein Issue (IAtlasVcsBranching, #765), ohne Netz:
//   BranchExists for-each-ref --format=%(refname) refs/heads/<Name>
//   CreateBranch checkout --quiet --no-track -b <Name> <Basis> --
//                (Basis: refs/heads/<Basis>, sonst refs/remotes/origin/<Basis>, '' = HEAD)
//   SwitchBranch checkout --quiet <Name> --
//   HookFolders  rev-parse --git-path hooks --git-dir
// ChangeMarker liest nur Dateien: .git/HEAD (Inhalt und Zeitstempel), die
// Datei des Branchs unter refs/heads und packed-refs. In Worktrees und
// Submodulen ist .git eine Datei mit "gitdir: …".

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools;

type
  TAtlasGitVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork, IAtlasVcsIncoming,
    IAtlasVcsUpdate, IAtlasVcsBranching)
  private
    FRoot: string;
    FCommand: TAtlasVcsCommand;
    function Git(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
    function Status(AUntracked: Boolean; out AHead: TAtlasVcsHead;
      out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function RefExists(const ARef: string; out AExists: Boolean): TAtlasVcsOutcome;
  public
    /// <summary>ARoot: Ordner mit .git. AExecutable: vollständiger Pfad von git ('' = nicht installiert).</summary>
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
    { IAtlasVcsBranching }
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    function CreateBranch(const AName, ABase, AMessage: string): TAtlasVcsOutcome;
    function SwitchBranch(const AName: string): TAtlasVcsOutcome;
    function HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
    /// <summary>Ordner mit den Verwaltungsdaten: ARoot\.git oder das Ziel von "gitdir:"; '' ohne.</summary>
    class function GitDir(const ARoot: string): string; static;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.GitParser;

function ReadSmallFile(const AFileName: string): string;
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Result := '';
  if not FileExists(AFileName) then
    Exit;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size > 4096 then
        Exit;
      SetLength(Bytes, Stream.Size);
      if Length(Bytes) > 0 then
        Stream.ReadBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;
    Result := Trim(VcsUtf8(Bytes));
  except
    // Gerade von git geschrieben oder gesperrt: dann eben ohne.
    on EStreamError do
      Result := '';
    on EOSError do
      Result := '';
  end;
end;

function Stamp(const AFileName: string): string;
var
  Age: TDateTime;
begin
  if FileAge(AFileName, Age) then
    Result := FloatToStr(Age, TFormatSettings.Invariant)
  else
    Result := '-';
end;

{ TAtlasGitVersionControl }

constructor TAtlasGitVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FRoot := VcsNormalizeDir(ARoot);
  FCommand := TAtlasVcsCommand.Create(ARunner, AExecutable, FRoot, ATimeoutMs);
end;

constructor TAtlasGitVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string);
begin
  Create(ARoot, ARunner, AExecutable, TAtlasVcsCommand.DefaultTimeoutMs);
end;

destructor TAtlasGitVersionControl.Destroy;
begin
  FCommand.Free;
  inherited;
end;

function TAtlasGitVersionControl.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Git;
end;

function TAtlasGitVersionControl.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result.Kind := TAtlasVcsKind.Git;
  Result.Root := FRoot;
end;

function TAtlasGitVersionControl.Git(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
begin
  Result := FCommand.Run(['--no-optional-locks', '-c', 'core.quotepath=off', '-c', 'color.ui=false'] + AArguments,
    AOutput);
end;

function TAtlasGitVersionControl.Status(AUntracked: Boolean; out AHead: TAtlasVcsHead;
  out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
var
  Output: TBytes;
  Untracked: string;
begin
  AHead := TAtlasVcsHead.Empty;
  AChanges := nil;
  if AUntracked then
    Untracked := '--untracked-files=all'
  else
    Untracked := '--untracked-files=no';
  Result := Git(['status', '--porcelain=v2', '--branch', '-z', Untracked], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    TAtlasGitParser.ParseStatus(VcsUtf8(Output), FRoot, AHead, AChanges);
  except
    on EAtlasVcsParse do
    begin
      AHead := TAtlasVcsHead.Empty;
      AChanges := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitVersionControl.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
var
  Ignored: TArray<TAtlasVcsChange>;
begin
  Result := Status(False, AHead, Ignored);
end;

function TAtlasGitVersionControl.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
var
  Ignored: TAtlasVcsHead;
begin
  Result := Status(True, Ignored, AChanges);
end;

function TAtlasGitVersionControl.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
var
  Relative, Revision: string;
begin
  AContent := nil;
  if not VcsRelativePath(FRoot, AFileName, Relative) then
    Exit(TAtlasVcsOutcome.Failed);
  Revision := Trim(ARevision);
  if Revision = '' then
    Revision := 'HEAD';
  // Eine Revision, die mit "-" beginnt, wäre eine Option.
  if Revision[1] = '-' then
    Exit(TAtlasVcsOutcome.Failed);
  Result := Git(['show', Revision + ':' + Relative], AContent);
end;

function TAtlasGitVersionControl.Blame(const AFileName: string;
  out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
var
  Relative: string;
  Output: TBytes;
begin
  ALines := nil;
  if not VcsRelativePath(FRoot, AFileName, Relative) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := Git(['blame', '--porcelain', '--', Relative], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    ALines := TAtlasGitParser.ParseBlame(VcsUtf8(Output));
  except
    on EAtlasVcsParse do
    begin
      ALines := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

/// <summary>Name, der nicht als Option missverstanden werden kann und keine Leer- oder Steuerzeichen hat.</summary>
function SafeName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := (AName <> '') and (AName[1] <> '-');
  if Result then
    for Index := 1 to Length(AName) do
      if Ord(AName[Index]) <= 32 then
        Exit(False);
end;

function TAtlasGitVersionControl.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  ABranches := nil;
  Result := Git(['for-each-ref', '--format=' + TAtlasGitParser.BranchFormat, 'refs/heads'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    ABranches := TAtlasGitParser.ParseBranches(VcsUtf8(Output));
  except
    on EAtlasVcsParse do
    begin
      ABranches := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitVersionControl.Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AStashes := nil;
  Result := Git(['stash', 'list', '--format=' + TAtlasGitParser.StashFormat], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    AStashes := TAtlasGitParser.ParseStashes(VcsUtf8(Output));
  except
    on EAtlasVcsParse do
    begin
      AStashes := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitVersionControl.Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  ANames := nil;
  Result := Git(['remote'], Output);
  if Result = TAtlasVcsOutcome.Ok then
    ANames := TAtlasGitParser.ParseLines(VcsUtf8(Output));
end;

function TAtlasGitVersionControl.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
var
  Arguments: TArray<string>;
  Output: TBytes;
  Limit: Integer;
begin
  ACommits := nil;
  if not SafeName(ABranch) or ((AUpstream <> '') and not SafeName(AUpstream)) then
    Exit(TAtlasVcsOutcome.Failed);
  Limit := AMax;
  if Limit < 1 then
    Limit := 1;
  Arguments := ['log', '--format=' + TAtlasGitParser.LogFormat, '--max-count=' + IntToStr(Limit),
    'refs/heads/' + ABranch, '--not'];
  // Ohne Upstream: Commits, die auf keinem Remote liegen.
  if AUpstream = '' then
    Arguments := Arguments + ['--remotes']
  else
    Arguments := Arguments + [AUpstream];
  Result := Git(Arguments, Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    ACommits := TAtlasGitParser.ParseLog(VcsUtf8(Output));
  except
    on EAtlasVcsParse do
    begin
      ACommits := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitVersionControl.ChangesIn(const ARevision: string;
  out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AChanges := nil;
  if not SafeName(ARevision) then
    Exit(TAtlasVcsOutcome.Failed);
  // Stash: erster Vorgänger ist der Stand beim Anlegen; der Unterschied ist die gesicherte Arbeit.
  Result := Git(['diff', '--name-status', '-z', '--no-renames', ARevision + '^1', ARevision], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    AChanges := TAtlasGitParser.ParseNameStatus(VcsUtf8(Output), FRoot);
  except
    on EAtlasVcsParse do
    begin
      AChanges := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitVersionControl.Push(const ABranch, ARemote, ARemoteRef: string;
  ASetUpstream: Boolean): TAtlasVcsOutcome;
var
  Arguments: TArray<string>;
  Output: TBytes;
begin
  if not SafeName(ABranch) or not SafeName(ARemote) or not SafeName(ARemoteRef) then
    Exit(TAtlasVcsOutcome.Failed);
  Arguments := ['push', '--porcelain'];
  if ASetUpstream then
    Arguments := Arguments + ['--set-upstream'];
  Arguments := Arguments + [ARemote, 'refs/heads/' + ABranch + ':' + ARemoteRef];
  Result := Git(Arguments, Output);
end;

function TAtlasGitVersionControl.Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  ARevision := '';
  if not SafeName(ARef) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := Git(['rev-parse', '--verify', '--quiet', ARef + '^{commit}'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  ARevision := Trim(VcsUtf8(Output));
  if ARevision = '' then
    Result := TAtlasVcsOutcome.Failed;
end;

function TAtlasGitVersionControl.Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
  out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
var
  Arguments: TArray<string>;
  Output: TBytes;
  Limit: Integer;
  Revision: string;
  Excluded: Boolean;
begin
  ACommits := nil;
  if not SafeName(AUpstream) then
    Exit(TAtlasVcsOutcome.Failed);
  Limit := AMax;
  if Limit < 1 then
    Limit := 1;
  Arguments := ['log', '--format=' + TAtlasGitParser.IncomingFormat, '--name-only', '-z', '--no-renames',
    '--max-count=' + IntToStr(Limit), AUpstream];
  Excluded := False;
  for Revision in AExclude do
  begin
    if Revision = '' then
      Continue;
    if not SafeName(Revision) then
      Exit(TAtlasVcsOutcome.Failed);
    if not Excluded then
      Arguments := Arguments + ['--not'];
    Excluded := True;
    Arguments := Arguments + [Revision];
  end;
  Result := Git(Arguments, Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    ACommits := TAtlasGitParser.ParseIncoming(VcsUtf8(Output), FRoot);
  except
    on EAtlasVcsParse do
    begin
      ACommits := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitVersionControl.Fetch(const ARemote: string): TAtlasVcsOutcome;
var
  Arguments: TArray<string>;
  Output: TBytes;
begin
  if (ARemote <> '') and not SafeName(ARemote) then
    Exit(TAtlasVcsOutcome.Failed);
  // Nie nach Zugangsdaten fragen: kein Fenster des Credential Managers, kein Kennwortprogramm.
  Arguments := ['-c', 'credential.interactive=never', '-c', 'core.askPass=', 'fetch', '--quiet', '--no-tags'];
  if ARemote <> '' then
    Arguments := Arguments + [ARemote];
  Result := Git(Arguments, Output);
end;

function TAtlasGitVersionControl.Pull: TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  // Nur vorwärts: kein Merge-Commit, kein Rebase; weicht der Branch ab, endet git mit Fehler.
  Result := Git(['-c', 'credential.interactive=never', '-c', 'core.askPass=', 'pull', '--ff-only', '--no-rebase',
    '--quiet'], Output);
end;

{ IAtlasVcsBranching (#765) }

function TAtlasGitVersionControl.RefExists(const ARef: string; out AExists: Boolean): TAtlasVcsOutcome;
var
  Output: TBytes;
  Line: string;
begin
  AExists := False;
  // for-each-ref mit vollem Namen: genau dieser Ref oder nichts; nie ein Fehler, wenn er fehlt.
  Result := Git(['for-each-ref', '--format=%(refname)', ARef], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  for Line in TAtlasGitParser.ParseLines(VcsUtf8(Output)) do
    if Line = ARef then
      AExists := True;
end;

function TAtlasGitVersionControl.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  AExists := False;
  if not VcsSafeBranchName(AName) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := RefExists('refs/heads/' + AName, AExists);
end;

function TAtlasGitVersionControl.CreateBranch(const AName, ABase, AMessage: string): TAtlasVcsOutcome;
var
  Output: TBytes;
  StartPoint: string;
  Exists: Boolean;
begin
  // AMessage braucht nur SVN; ein Git-Branch hat keine Nachricht.
  if not VcsSafeBranchName(AName) then
    Exit(TAtlasVcsOutcome.Failed);
  StartPoint := 'HEAD';
  if ABase <> '' then
  begin
    if not VcsSafeBranchName(ABase) then
      Exit(TAtlasVcsOutcome.Failed);
    Result := RefExists('refs/heads/' + ABase, Exists);
    if Result <> TAtlasVcsOutcome.Ok then
      Exit;
    if Exists then
      StartPoint := 'refs/heads/' + ABase
    else
    begin
      Result := RefExists('refs/remotes/origin/' + ABase, Exists);
      if Result <> TAtlasVcsOutcome.Ok then
        Exit;
      if not Exists then
        Exit(TAtlasVcsOutcome.Failed);
      StartPoint := 'refs/remotes/origin/' + ABase;
    end;
  end;
  // --no-track: der neue Branch verfolgt nicht die Basis; den Upstream setzt erst der erste Push.
  // "--" am Ende: StartPoint ist eine Revision, nie ein Dateiname.
  Result := Git(['checkout', '--quiet', '--no-track', '-b', AName, StartPoint, '--'], Output);
end;

function TAtlasGitVersionControl.SwitchBranch(const AName: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  if not VcsSafeBranchName(AName) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := Git(['checkout', '--quiet', AName, '--'], Output);
end;

/// <summary>APath vollständig: absolut (Laufwerk, "/" oder UNC) unverändert, sonst relativ zu ARoot.</summary>
function AbsoluteGitPath(const ARoot, APath: string): string;
begin
  if (Pos(':', APath) = 2) or (Copy(APath, 1, 1) = '/') or (Copy(APath, 1, 2) = '\\') then
    Result := VcsNormalizeDir(APath)
  else
    Result := VcsFullPath(ARoot, APath);
end;

function TAtlasGitVersionControl.HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
var
  Output: TBytes;
  Lines: TArray<string>;
begin
  AHooks := '';
  AGitDir := '';
  // Zwei Zeilen, relativ zur Wurzel oder vollständig: Hooks (mit core.hooksPath und commondir) und der eigene
  // Verwaltungsordner.
  Result := Git(['rev-parse', '--git-path', 'hooks', '--git-dir'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  Lines := TAtlasGitParser.ParseLines(VcsUtf8(Output));
  if (Length(Lines) < 2) or (Trim(Lines[0]) = '') or (Trim(Lines[1]) = '') then
    Exit(TAtlasVcsOutcome.Failed);
  AHooks := AbsoluteGitPath(FRoot, Trim(Lines[0]));
  AGitDir := AbsoluteGitPath(FRoot, Trim(Lines[1]));
end;

class function TAtlasGitVersionControl.GitDir(const ARoot: string): string;
var
  DotGit, Content: string;
begin
  DotGit := IncludeTrailingPathDelimiter(VcsNormalizeDir(ARoot)) + '.git';
  if DirectoryExists(DotGit) then
    Exit(DotGit);
  Result := '';
  if not FileExists(DotGit) then
    Exit;
  Content := ReadSmallFile(DotGit);
  if Copy(Content, 1, 7) <> 'gitdir:' then
    Exit;
  Content := Trim(Copy(Content, 8, MaxInt));
  if Content = '' then
    Exit;
  // Relativ zum Ordner der Datei .git, sonst absolut.
  Result := AbsoluteGitPath(ARoot, Content);
end;

function TAtlasGitVersionControl.ChangeMarker: string;
var
  Dir, HeadText, Ref: string;
begin
  Dir := GitDir(FRoot);
  if Dir = '' then
    Exit('');
  Dir := IncludeTrailingPathDelimiter(Dir);
  HeadText := ReadSmallFile(Dir + 'HEAD');
  Result := HeadText + '|' + Stamp(Dir + 'HEAD');
  if Copy(HeadText, 1, 5) = 'ref: ' then
  begin
    Ref := Trim(Copy(HeadText, 6, MaxInt));
    Result := Result + '|' + ReadSmallFile(Dir + StringReplace(Ref, '/', PathDelim, [rfReplaceAll]));
    // Worktrees: Branches liegen im gemeinsamen Ordner (commondir).
    if FileExists(Dir + 'commondir') then
      Result := Result + '|' + ReadSmallFile(VcsFullPath(Dir, ReadSmallFile(Dir + 'commondir')) + PathDelim +
        StringReplace(Ref, '/', PathDelim, [rfReplaceAll]));
  end;
  Result := Result + '|' + Stamp(Dir + 'packed-refs');
end;

end.
