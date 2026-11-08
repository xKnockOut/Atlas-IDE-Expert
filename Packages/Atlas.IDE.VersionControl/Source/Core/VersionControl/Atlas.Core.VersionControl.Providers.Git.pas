unit Atlas.Core.VersionControl.Providers.Git;

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
//   SubmoduleStatus submodule status --recursive (#1292, ohne Server)
//   Blame     blame --porcelain -- <Pfad>
// Nicht gesicherte Arbeit (IAtlasVcsLocalWork, #762), ohne fetch:
//   Branches  for-each-ref --format=… refs/heads
//   Stashes   stash list --format=…
//   Remotes   remote
//   Outgoing  log --format=… --max-count=N refs/heads/<Branch> --not <Upstream>|--remotes
//   ChangesIn diff --name-status -z --no-renames <Revision>^1 <Revision>
//   Push      push --porcelain [--set-upstream] <Remote> refs/heads/<Branch>:<Ref>
//             (wie Fetch und Pull ohne Rückfrage; fehlt die Anmeldung,
//             LoginNeeded, #1287)
// Eingehende Commits (IAtlasVcsIncoming, #755):
//   Resolve   rev-parse --verify --quiet <Ref>^{commit}
//   Incoming  log --format=… --name-only -z --no-renames --max-count=N <Upstream> --not <Stände>
//   Fetch     -c credential.interactive=never -c core.askPass= fetch --quiet --no-tags [<Remote>]
//             (Git Credential Manager fragt nicht, git selbst ruft kein
//             Kennwortfenster; dazu setzt der Prozessläufer
//             GIT_TERMINAL_PROMPT=0 und GCM_INTERACTIVE=never. Fehlt die
//             Anmeldung, LoginNeeded statt Failed (#1287). Das Zeitlimit setzt
//             der Aufrufer.)
// Holen (IAtlasVcsUpdate, #764):
//   Pull      -c credential.interactive=never -c core.askPass= pull --ff-only --no-rebase --quiet
// Branch für ein Issue (IAtlasVcsBranching, #765), ohne Netz:
//   BranchExists       for-each-ref --format=%(refname) refs/heads/<Name>
//   RemoteBranchExists for-each-ref --format=%(refname) refs/remotes/origin/<Name>
//   RunStep            Schritte aus Atlas.Core.VersionControl.BranchPlan (#1288), z. B.
//                      checkout --quiet --no-track -b <Name> <Basis> --;
//                      mit Remote wie Fetch ohne Rückfrage
//   SwitchBranch       checkout --quiet <Name> --
//   HookFolders  rev-parse --git-path hooks --git-dir
// Issues der Zeilenhistorie (IAtlasVcsLineHistory, #1275), ohne Netz:
//   Messages     log --no-walk=unsorted --format=… <Commits> --   (je 100 Commits ein Aufruf)
//   LineHistory  log --format=… --max-count=N --no-ext-diff -L<a>,<b>:<Pfad>
// Entwicklung zu einem Issue (IAtlasVcsHistory, #1269), ohne Netz:
//   SearchLog    log --all --fixed-strings --regexp-ignore-case --grep=<Text>
//                --format=… --name-status -z --no-renames --max-count=N
//   AllBranches  for-each-ref --format=… refs/heads refs/remotes
//   Distance     rev-list --left-right --count <Basis>...<Branch>
//   ContentOf    show <Revision>:<Pfad> bzw. show <Revision>^1:<Pfad>
//                (neue Datei davor bzw. gelöschte danach: leer ohne Prozess)
// ChangeMarker liest nur Dateien: .git/HEAD (Inhalt und Zeitstempel), die
// Datei des Branchs unter refs/heads und packed-refs. In Worktrees und
// Submodulen ist .git eine Datei mit "gitdir: …".

interface

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools;

type
  /// <summary>Zeilen- und Projektgeschichte von Git, Teil von TAtlasGitVersionControl: Wurzel und Befehl gehören
  /// dem Ganzen, das auch die Referenzen zählt.</summary>
  TAtlasGitHistoryPart = class(TAggregatedObject, IAtlasVcsLineHistory, IAtlasVcsHistory)
  public const
    /// <summary>Höchstens so viele Commits je Aufruf von Messages (Länge der Befehlszeile).</summary>
    cMessageBatch = 100;
  private
    FRoot: string;
    FCommand: TAtlasVcsCommand;
    function Git(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
  public
    constructor Create(const AController: IInterface; const ARoot: string; ACommand: TAtlasVcsCommand);
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
  end;

  TAtlasGitVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork, IAtlasVcsIncoming,
    IAtlasVcsUpdate, IAtlasVcsBranching, IAtlasVcsSubmodules,
    IAtlasVcsLineHistory,
    IAtlasVcsHistory)
  public const
    /// <summary>Höchstens so viele Commits je Aufruf von Messages (Länge der Befehlszeile).</summary>
    cMessageBatch = TAtlasGitHistoryPart.cMessageBatch;
  private
    FRoot: string;
    FCommand: TAtlasVcsCommand;
    FHistoryPart: TAtlasGitHistoryPart;
    function Git(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
    function GitRemote(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
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
    { IAtlasVcsSubmodules }
    function SubmoduleStatus(out AText: string): TAtlasVcsOutcome;
    /// <summary>Ordner mit den Verwaltungsdaten: ARoot\.git oder das Ziel von "gitdir:"; '' ohne.</summary>
    class function GitDir(const ARoot: string): string; static;
    /// <summary>IAtlasVcsLineHistory und IAtlasVcsHistory.</summary>
    property HistoryPart: TAtlasGitHistoryPart read FHistoryPart implements IAtlasVcsLineHistory, IAtlasVcsHistory;
  end;

implementation

uses
  System.Classes,
  System.Math,
  Atlas.Core.VersionControl.Internals.Text,
  Atlas.Core.VersionControl.Internals.GitParser;

function ReadSmallFile(const AFileName: string): string;
var
  mStream: TFileStream;
  mBytes: TBytes;
begin
  Result := '';
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if mStream.Size > 4096 then
      begin
        Exit;
      end;
      SetLength(mBytes, mStream.Size);
      if Length(mBytes) > 0 then
      begin
        mStream.ReadBuffer(mBytes[0], Length(mBytes));
      end;
    finally
      mStream.Free;
    end;
    Result := Trim(VcsUtf8(mBytes));
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
  mAge: TDateTime;
begin
  if FileAge(AFileName, mAge) then
  begin
    Result := FloatToStr(mAge, TFormatSettings.Invariant);
  end
  else
  begin
    Result := '-';
  end;
end;

{ TAtlasGitVersionControl }

constructor TAtlasGitVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FRoot := VcsNormalizeDir(ARoot);
  FCommand := TAtlasVcsCommand.Create(ARunner, AExecutable, FRoot, ATimeoutMs);
  FHistoryPart := TAtlasGitHistoryPart.Create(Self, FRoot, FCommand);
end;

constructor TAtlasGitVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string);
begin
  Create(ARoot, ARunner, AExecutable, TAtlasVcsCommand.cDefaultTimeoutMs);
end;

destructor TAtlasGitVersionControl.Destroy;
begin
  FreeAndNil(FHistoryPart);
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

/// <summary>git ohne Netz mit den festen Optionen (Kopf der Unit).</summary>
function RunGit(ACommand: TAtlasVcsCommand; const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
begin
  Result := ACommand.Run(['--no-optional-locks', '-c', 'core.quotepath=off', '-c', 'color.ui=false'] + AArguments,
    AOutput);
end;

function TAtlasGitVersionControl.Git(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
begin
  Result := RunGit(FCommand, AArguments, AOutput);
end;

{ TAtlasGitHistoryPart }

constructor TAtlasGitHistoryPart.Create(const AController: IInterface; const ARoot: string;
  ACommand: TAtlasVcsCommand);
begin
  inherited Create(AController);
  FRoot := ARoot;
  FCommand := ACommand;
end;

function TAtlasGitHistoryPart.Git(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
begin
  Result := RunGit(FCommand, AArguments, AOutput);
end;

{ TAtlasGitVersionControl }

function TAtlasGitVersionControl.GitRemote(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
begin
  // Mit dem Server (#1287): fehlt die Anmeldung, LoginNeeded statt Failed. Nie nachfragen: kein Fenster des
  // Credential Managers, kein Kennwortprogramm (dazu die Umgebung des Prozessläufers).
  Result := FCommand.RunRemote(TAtlasVcsKind.Git, ['--no-optional-locks', '-c', 'core.quotepath=off', '-c',
    'color.ui=false', '-c', 'credential.interactive=never', '-c', 'core.askPass='] + AArguments, AOutput);
end;

function TAtlasGitVersionControl.Status(AUntracked: Boolean; out AHead: TAtlasVcsHead;
  out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mUntracked: string;
begin
  AHead := TAtlasVcsHead.Empty;
  AChanges := nil;
  if AUntracked then
  begin
    mUntracked := '--untracked-files=all';
  end
  else
  begin
    mUntracked := '--untracked-files=no';
  end;
  Result := Git(['status', '--porcelain=v2', '--branch', '-z', mUntracked], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    TAtlasGitParser.ParseStatus(VcsUtf8(mOutput), FRoot, AHead, AChanges);
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
  mIgnored: TArray<TAtlasVcsChange>;
begin
  Result := Status(False, AHead, mIgnored);
end;

function TAtlasGitVersionControl.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
var
  mIgnored: TAtlasVcsHead;
begin
  Result := Status(True, mIgnored, AChanges);
end;

function TAtlasGitVersionControl.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
var
  mRelative, mRevision: string;
begin
  AContent := nil;
  if not VcsRelativePath(FRoot, AFileName, mRelative) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mRevision := Trim(ARevision);
  if mRevision = '' then
  begin
    mRevision := 'HEAD';
  end;
  // Eine Revision, die mit "-" beginnt, wäre eine Option.
  if mRevision[1] = '-' then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := Git(['show', mRevision + ':' + mRelative], AContent);
end;

function TAtlasGitVersionControl.Blame(const AFileName: string;
  out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
var
  mRelative: string;
  mOutput: TBytes;
begin
  ALines := nil;
  if not VcsRelativePath(FRoot, AFileName, mRelative) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := Git(['blame', '--porcelain', '--', mRelative], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ALines := TAtlasGitParser.ParseBlame(VcsUtf8(mOutput));
  except
    on EAtlasVcsParse do
    begin
      ALines := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

/// <summary>Hash aus blame: 7 bis 64 Hexziffern.</summary>
function IsHash(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (Length(AText) >= 7) and (Length(AText) <= 64);
  if Result then
  begin
    for mIndex := 1 to Length(AText) do
    begin
      if not CharInSet(AText[mIndex], ['0'..'9', 'a'..'f', 'A'..'F']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function TAtlasGitHistoryPart.Messages(const AFileName: string; const ARevisions: TArray<string>;
  out AMessages: TArray<TAtlasVcsRevisionMessage>): TAtlasVcsOutcome;
var
  mRevision: string;
  mArguments: TArray<string>;
  mOutput: TBytes;
  mStart, mIndex: Integer;
begin
  AMessages := nil;
  for mRevision in ARevisions do
  begin
    if not IsHash(mRevision) then
    begin
      Exit(TAtlasVcsOutcome.Failed);
    end;
  end;
  Result := TAtlasVcsOutcome.Ok;
  mStart := 0;
  while mStart < Length(ARevisions) do
  begin
    mArguments := ['log', '--no-walk=unsorted', '--format=' + TAtlasGitParser.cMessageFormat];
    for mIndex := mStart to Min(mStart + cMessageBatch, Length(ARevisions)) - 1 do
    begin
      mArguments := mArguments + [ARevisions[mIndex]];
    end;
    Inc(mStart, cMessageBatch);
    Result := Git(mArguments + ['--'], mOutput);
    if Result <> TAtlasVcsOutcome.Ok then
    begin
      Break;
    end;
    try
      AMessages := AMessages + TAtlasGitParser.ParseMessages(VcsUtf8(mOutput));
    except
      on EAtlasVcsParse do
      begin
        Result := TAtlasVcsOutcome.Failed;
        Break;
      end;
    end;
  end;
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    AMessages := nil;
  end;
end;

function TAtlasGitHistoryPart.LineHistory(const AFileName: string; AFirstLine, ALastLine,
  AMaxRevisions: Integer; out ACommits: TArray<TAtlasVcsLineCommit>): TAtlasVcsOutcome;
var
  mRelative: string;
  mOutput: TBytes;
begin
  ACommits := nil;
  if not VcsRelativePath(FRoot, AFileName, mRelative) or (AFirstLine < 1) or (ALastLine < AFirstLine) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := Git(['log', '--format=' + TAtlasGitParser.cLineLogFormat, '--max-count=' + IntToStr(Max(1, AMaxRevisions)),
    '--no-ext-diff', '-L' + IntToStr(AFirstLine) + ',' + IntToStr(ALastLine) + ':' + mRelative], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ACommits := TAtlasGitParser.ParseLineLog(VcsUtf8(mOutput));
  except
    on EAtlasVcsParse do
    begin
      ACommits := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

/// <summary>Name, der nicht als Option missverstanden werden kann und keine Leer- oder Steuerzeichen hat.</summary>
function SafeName(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AName <> '') and (AName[1] <> '-');
  if Result then
  begin
    for mIndex := 1 to Length(AName) do
    begin
      if Ord(AName[mIndex]) <= 32 then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function TAtlasGitVersionControl.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  ABranches := nil;
  Result := Git(['for-each-ref', '--format=' + TAtlasGitParser.cBranchFormat, 'refs/heads'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ABranches := TAtlasGitParser.ParseBranches(VcsUtf8(mOutput));
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
  mOutput: TBytes;
begin
  AStashes := nil;
  Result := Git(['stash', 'list', '--format=' + TAtlasGitParser.cStashFormat], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    AStashes := TAtlasGitParser.ParseStashes(VcsUtf8(mOutput));
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
  mOutput: TBytes;
begin
  ANames := nil;
  Result := Git(['remote'], mOutput);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    ANames := TAtlasGitParser.ParseLines(VcsUtf8(mOutput));
  end;
end;

function TAtlasGitVersionControl.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
var
  mArguments: TArray<string>;
  mOutput: TBytes;
  mLimit: Integer;
begin
  ACommits := nil;
  if not SafeName(ABranch) or ((AUpstream <> '') and not SafeName(AUpstream)) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mLimit := AMax;
  if mLimit < 1 then
  begin
    mLimit := 1;
  end;
  mArguments := ['log', '--format=' + TAtlasGitParser.cLogFormat, '--max-count=' + IntToStr(mLimit),
    'refs/heads/' + ABranch, '--not'];
  // Ohne Upstream: Commits, die auf keinem Remote liegen.
  if AUpstream = '' then
  begin
    mArguments := mArguments + ['--remotes'];
  end
  else
  begin
    mArguments := mArguments + [AUpstream];
  end;
  Result := Git(mArguments, mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ACommits := TAtlasGitParser.ParseLog(VcsUtf8(mOutput));
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
  mOutput: TBytes;
begin
  AChanges := nil;
  if not SafeName(ARevision) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  // Stash: erster Vorgänger ist der Stand beim Anlegen; der Unterschied ist die gesicherte Arbeit.
  Result := Git(['diff', '--name-status', '-z', '--no-renames', ARevision + '^1', ARevision], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    AChanges := TAtlasGitParser.ParseNameStatus(VcsUtf8(mOutput), FRoot);
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
  mArguments: TArray<string>;
  mOutput: TBytes;
begin
  if not SafeName(ABranch) or not SafeName(ARemote) or not SafeName(ARemoteRef) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mArguments := ['push', '--porcelain'];
  if ASetUpstream then
  begin
    mArguments := mArguments + ['--set-upstream'];
  end;
  mArguments := mArguments + [ARemote, 'refs/heads/' + ABranch + ':' + ARemoteRef];
  Result := GitRemote(mArguments, mOutput);
end;

function TAtlasGitVersionControl.Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  ARevision := '';
  if not SafeName(ARef) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := Git(['rev-parse', '--verify', '--quiet', ARef + '^{commit}'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  ARevision := Trim(VcsUtf8(mOutput));
  if ARevision = '' then
  begin
    Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasGitVersionControl.Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
  out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
var
  mArguments: TArray<string>;
  mOutput: TBytes;
  mLimit: Integer;
  mRevision: string;
  mExcluded: Boolean;
begin
  ACommits := nil;
  if not SafeName(AUpstream) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mLimit := AMax;
  if mLimit < 1 then
  begin
    mLimit := 1;
  end;
  mArguments := ['log', '--format=' + TAtlasGitParser.cIncomingFormat, '--name-only', '-z', '--no-renames',
    '--max-count=' + IntToStr(mLimit), AUpstream];
  mExcluded := False;
  for mRevision in AExclude do
  begin
    if mRevision = '' then
    begin
      Continue;
    end;
    if not SafeName(mRevision) then
    begin
      Exit(TAtlasVcsOutcome.Failed);
    end;
    if not mExcluded then
    begin
      mArguments := mArguments + ['--not'];
    end;
    mExcluded := True;
    mArguments := mArguments + [mRevision];
  end;
  Result := Git(mArguments, mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ACommits := TAtlasGitParser.ParseIncoming(VcsUtf8(mOutput), FRoot);
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
  mArguments: TArray<string>;
  mOutput: TBytes;
begin
  if (ARemote <> '') and not SafeName(ARemote) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mArguments := ['fetch', '--quiet', '--no-tags'];
  if ARemote <> '' then
  begin
    mArguments := mArguments + [ARemote];
  end;
  Result := GitRemote(mArguments, mOutput);
end;

function TAtlasGitVersionControl.Pull: TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  // Nur vorwärts: kein Merge-Commit, kein Rebase; weicht der Branch ab, endet git mit Fehler.
  Result := GitRemote(['pull', '--ff-only', '--no-rebase', '--quiet'], mOutput);
end;

{ IAtlasVcsBranching (#765) }

function TAtlasGitVersionControl.RefExists(const ARef: string; out AExists: Boolean): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mLine: string;
begin
  AExists := False;
  // for-each-ref mit vollem Namen: genau dieser Ref oder nichts; nie ein Fehler, wenn er fehlt.
  Result := Git(['for-each-ref', '--format=%(refname)', ARef], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  for mLine in TAtlasGitParser.ParseLines(VcsUtf8(mOutput)) do
  begin
    if mLine = ARef then
    begin
      AExists := True;
    end;
  end;
end;

function TAtlasGitVersionControl.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  AExists := False;
  if not VcsSafeBranchName(AName) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := RefExists('refs/heads/' + AName, AExists);
end;

function TAtlasGitVersionControl.BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out AExists: Boolean): TAtlasVcsOutcome;
begin
  Result := BranchExists(AName, AExists);
end;

function TAtlasGitVersionControl.RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  AExists := False;
  if not VcsSafeBranchName(AName) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := RefExists('refs/remotes/origin/' + AName, AExists);
end;

function TAtlasGitVersionControl.ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
begin
  // Git braucht für die Basis keinen Server: Der Stand von origin/<Branch> ist der des letzten Abrufs.
  ARevision := '';
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasGitVersionControl.HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
begin
  AHas := False;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasGitVersionControl.RepositoryPath(out APath: string): TAtlasVcsOutcome;
begin
  APath := '';
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasGitVersionControl.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  if Length(AStep.Arguments) = 0 then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  if AStep.Remote then
  begin
    Result := GitRemote(AStep.Arguments, mOutput);
  end
  else
  begin
    Result := Git(AStep.Arguments, mOutput);
  end;
end;

function TAtlasGitVersionControl.SwitchBranch(const AName: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  if not VcsSafeBranchName(AName) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := Git(['checkout', '--quiet', AName, '--'], mOutput);
end;

/// <summary>APath vollständig: absolut (Laufwerk, "/" oder UNC) unverändert, sonst relativ zu ARoot.</summary>
function AbsoluteGitPath(const ARoot, APath: string): string;
begin
  if (Pos(':', APath) = 2) or (Copy(APath, 1, 1) = '/') or (Copy(APath, 1, 2) = '\\') then
  begin
    Result := VcsNormalizeDir(APath);
  end
  else
  begin
    Result := VcsFullPath(ARoot, APath);
  end;
end;

function TAtlasGitVersionControl.SwitchBranch(const AName: string;
  const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
begin
  Result := SwitchBranch(AName);
end;

function TAtlasGitVersionControl.SubmoduleStatus(out AText: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  AText := '';
  Result := Git(['submodule', 'status', '--recursive'], mOutput);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    AText := VcsUtf8(mOutput);
  end;
end;

function TAtlasGitVersionControl.HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mLines: TArray<string>;
begin
  AHooks := '';
  AGitDir := '';
  // Zwei Zeilen, relativ zur Wurzel oder vollständig: Hooks (mit core.hooksPath und commondir) und der eigene
  // Verwaltungsordner.
  Result := Git(['rev-parse', '--git-path', 'hooks', '--git-dir'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  mLines := TAtlasGitParser.ParseLines(VcsUtf8(mOutput));
  if (Length(mLines) < 2) or (Trim(mLines[0]) = '') or (Trim(mLines[1]) = '') then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  AHooks := AbsoluteGitPath(FRoot, Trim(mLines[0]));
  AGitDir := AbsoluteGitPath(FRoot, Trim(mLines[1]));
end;

{ IAtlasVcsHistory (#1269) }

function TAtlasGitHistoryPart.SearchLog(const AText: string; AMax: Integer;
  out AEntries: TArray<TAtlasVcsLogEntry>): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mLimit: Integer;
  mIndex: Integer;
begin
  AEntries := nil;
  // Ein Zeilenende im Suchtext wäre ein zweites Muster; leer fände alles.
  if Trim(AText) = '' then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  for mIndex := 1 to Length(AText) do
  begin
    if Ord(AText[mIndex]) < 32 then
    begin
      Exit(TAtlasVcsOutcome.Failed);
    end;
  end;
  mLimit := AMax;
  if mLimit < 1 then
  begin
    mLimit := 1;
  end;
  // --grep=<Text> in einem Argument: Der Text kann nie als Option gelesen werden.
  Result := Git(['log', '--all', '--fixed-strings', '--regexp-ignore-case', '--grep=' + AText,
    '--format=' + TAtlasGitParser.cHistoryFormat, '--name-status', '-z', '--no-renames',
    '--max-count=' + IntToStr(mLimit)], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    AEntries := TAtlasGitParser.ParseHistory(VcsUtf8(mOutput), FRoot);
  except
    on EAtlasVcsParse do
    begin
      AEntries := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitHistoryPart.AllBranches(out ABranches: TArray<TAtlasVcsRef>): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  ABranches := nil;
  Result := Git(['for-each-ref', '--format=' + TAtlasGitParser.cRefFormat, 'refs/heads', 'refs/remotes'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ABranches := TAtlasGitParser.ParseRefs(VcsUtf8(mOutput));
  except
    on EAtlasVcsParse do
    begin
      ABranches := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitHistoryPart.Distance(const ABranch, ABase: string; out AAhead, ABehind: Integer): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  AAhead := -1;
  ABehind := -1;
  if not SafeName(ABranch) or not SafeName(ABase) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := Git(['rev-list', '--left-right', '--count', ABase + '...' + ABranch, '--'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    TAtlasGitParser.ParseDistance(VcsUtf8(mOutput), AAhead, ABehind);
  except
    on EAtlasVcsParse do
    begin
      AAhead := -1;
      ABehind := -1;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasGitHistoryPart.ContentOf(const ARevision: string; const AFile: TAtlasVcsLogFile;
  ABefore: Boolean; out AContent: TBytes): TAtlasVcsOutcome;
var
  mRevision: string;
begin
  AContent := nil;
  if not SafeName(ARevision) or (AFile.RepositoryPath = '') then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  // Was es auf der Seite nicht gibt, ist leer.
  if (ABefore and (AFile.Kind = TAtlasVcsChangeKind.Added)) or
    (not ABefore and (AFile.Kind = TAtlasVcsChangeKind.Deleted)) then
  begin
    Exit(TAtlasVcsOutcome.Ok);
  end;
  mRevision := ARevision;
  if ABefore then
  begin
    mRevision := mRevision + '^1';
  end;
  Result := Git(['show', mRevision + ':' + AFile.RepositoryPath], AContent);
end;

class function TAtlasGitVersionControl.GitDir(const ARoot: string): string;
var
  mDotGit, mContent: string;
begin
  mDotGit := IncludeTrailingPathDelimiter(VcsNormalizeDir(ARoot)) + '.git';
  if DirectoryExists(mDotGit) then
  begin
    Exit(mDotGit);
  end;
  Result := '';
  if not FileExists(mDotGit) then
  begin
    Exit;
  end;
  mContent := ReadSmallFile(mDotGit);
  if Copy(mContent, 1, 7) <> 'gitdir:' then
  begin
    Exit;
  end;
  mContent := Trim(Copy(mContent, 8, MaxInt));
  if mContent = '' then
  begin
    Exit;
  end;
  // Relativ zum Ordner der Datei .git, sonst absolut.
  Result := AbsoluteGitPath(ARoot, mContent);
end;

function TAtlasGitVersionControl.ChangeMarker: string;
var
  mDir, mHeadText, mRef: string;
begin
  mDir := GitDir(FRoot);
  if mDir = '' then
  begin
    Exit('');
  end;
  mDir := IncludeTrailingPathDelimiter(mDir);
  mHeadText := ReadSmallFile(mDir + 'HEAD');
  Result := mHeadText + '|' + Stamp(mDir + 'HEAD');
  if Copy(mHeadText, 1, 5) = 'ref: ' then
  begin
    mRef := Trim(Copy(mHeadText, 6, MaxInt));
    Result := Result + '|' + ReadSmallFile(mDir + StringReplace(mRef, '/', PathDelim, [rfReplaceAll]));
    // Worktrees: Branches liegen im gemeinsamen Ordner (commondir).
    if FileExists(mDir + 'commondir') then
    begin
      Result := Result + '|' + ReadSmallFile(VcsFullPath(mDir, ReadSmallFile(mDir + 'commondir')) + PathDelim +
        StringReplace(mRef, '/', PathDelim, [rfReplaceAll]));
    end;
  end;
  Result := Result + '|' + Stamp(mDir + 'packed-refs');
end;

end.
