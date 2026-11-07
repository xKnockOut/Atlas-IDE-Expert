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
// Branch für ein Issue (IAtlasVcsBranching, #765), alle mit dem Server:
//   BranchExists   info ^/branches/<Name>@
//   ServerRevision info --show-item revision --non-interactive ^/<Pfad>@
//   RunStep        Schritte aus Atlas.Core.Vcs.BranchPlan (#1288), z. B.
//                  copy ^/<Basis>@<Revision> ^/branches/<Name>@ --parents -m <Nachricht>
//                  und switch ^/branches/<Name>@ .
//   SwitchBranch   switch ^/branches/<Name>@ .
// Seit #1290 mit Optionen (vcs.branch.svn.*): BranchExists und SwitchBranch
// suchen am selben Ort, an dem der Plan anlegt (TAtlasSvnLayout, Vorgabe
// {projektwurzel}/branches/<Name>); die Projektwurzel kommt aus
// info --show-item relative-url (ohne Server). Schritte mit Long (switch,
// checkout) laufen mit dem langen Zeitlimit.
// IAtlasVcsSvnWorkingCopy: WorkingRevisions = svnversion . bzw. svnversion
// <Ordner> (Programm neben svn, ohne Server); seit #1291 ExternalsXml =
// propget svn:externals --xml -R ., RepositoryRoot = info --show-item
// repos-root-url ., ToolVersion = --version --quiet. RunStep schreibt vor
// einem Schritt mit InputFile dessen Inhalt (UTF-8 ohne BOM, LF), etwa für
// propset svn:externals -F.
// IAtlasVcsSvnExternals (#1292): StatusXml = status --xml . (samt Externals),
// Update = update . [--ignore-externals] (Pull = Update(False)),
// CommitsSince = log -q --xml -r HEAD:<Rev> ^/<Pfad>@HEAD (Server; gezählt
// werden Einträge nach <Rev>), SetExternals = propset svn:externals -F
// <Temp-Datei> <Ordner> (nur Arbeitskopie).
// Ohne Server: HasExternals propget svn:externals -R . (nicht leer = ja),
// RepositoryPath info --show-item relative-url . (ohne "^/"),
// RemoteBranchExists und HookFolders ohne Prozess (Ok mit False bzw. '').
// Issues der Zeilenhistorie (IAtlasVcsLineHistory, #1275), mit dem Server:
//   Messages     log --xml -c <r1,r2,…> <Pfad>@        (je 100 Revisionen ein Aufruf)
//   LineHistory  log --xml -l N <Pfad>@ und log --diff -l N <Pfad>@, dann
//                rückwärts verfolgt (Atlas.Core.Vcs.Internals.LineTrace). Statt
//                je Revision „svn blame -r“ reichen so zwei Aufrufe für N
//                Revisionen; 200 Revisionen bleiben weit unter 5 s.
// Entwicklung zu einem Issue (IAtlasVcsHistory, #1269), alle mit dem Server:
//   SearchLog    info --xml . (Pfad der Arbeitskopie), dann
//                log --xml -v --search <Text> -l N ^/ (ganzes Repository,
//                damit auch Commits in Branches gefunden werden)
//   AllBranches  info --xml . (aktueller Branch), list --xml ^/branches
//   Distance     ohne Prozess Ok mit -1 (SVN kennt keinen Vorsprung)
//   ContentOf    cat ^/<Pfad>@<Revision> bzw. @<Revision − 1>
// ChangeMarker: Zeitstempel und Größe von .svn/wc.db; svn update und
// svn switch schreiben die Datenbank.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.SvnParser,
  Atlas.Core.Vcs.Tools;

type
  /// <summary>Gemeinsames der Teile von TAtlasSvnVersionControl, die eigene Schnittstellen umsetzen: Wurzel,
  /// Aufrufer und Befehl gehören dem Ganzen, das auch die Referenzen zählt.</summary>
  TAtlasSvnPart = class(TAggregatedObject)
  protected
    FRoot: string;
    FRunner: IAtlasVcsRunner;
    FCommand: TAtlasVcsCommand;
    function Svn(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
  public
    constructor Create(const AController: IInterface; const ARoot: string; const ARunner: IAtlasVcsRunner;
      ACommand: TAtlasVcsCommand);
    /// <summary>Schritt eines Plans ausführen (IAtlasVcsBranching.RunStep).</summary>
    function RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
  end;

  /// <summary>Arbeitskopie und Externals von SVN.</summary>
  TAtlasSvnWorkingCopyPart = class(TAtlasSvnPart, IAtlasVcsSvnWorkingCopy, IAtlasVcsSvnExternals)
  public
    { IAtlasVcsSvnWorkingCopy }
    function WorkingRevisions(out AText: string): TAtlasVcsOutcome; overload;
    function WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome; overload;
    function ExternalsXml(out AText: string): TAtlasVcsOutcome;
    function RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
    function ToolVersion(out AVersion: string): TAtlasVcsOutcome;
    { IAtlasVcsSvnExternals }
    function StatusXml(out AText: string): TAtlasVcsOutcome;
    function Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
    function CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
    function SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
  end;

  /// <summary>Zeilen- und Projektgeschichte von SVN.</summary>
  TAtlasSvnHistoryPart = class(TAtlasSvnPart, IAtlasVcsLineHistory, IAtlasVcsHistory)
  public const
    /// <summary>Höchstens so viele Revisionen je Aufruf von Messages.</summary>
    cMessageBatch = 100;
  private
    function Info(out ARelativeUrl: string): TAtlasVcsOutcome;
    /// <summary>svn log --xml und svn log --diff für den Zeilenverlauf.</summary>
    function ReadLineLog(const ARelative, ALimit: string; out ALog: TArray<TAtlasVcsLineCommit>;
      out ADiffs: TArray<TAtlasSvnLogDiff>): TAtlasVcsOutcome;
  public
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

  TAtlasSvnVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork, IAtlasVcsIncoming,
    IAtlasVcsUpdate, IAtlasVcsBranching, IAtlasVcsSvnWorkingCopy, IAtlasVcsSvnExternals,
    IAtlasVcsLineHistory,
    IAtlasVcsHistory)
  public const
    /// <summary>Höchstens so viele Revisionen je Aufruf von Messages.</summary>
    cMessageBatch = TAtlasSvnHistoryPart.cMessageBatch;
  private
    FRoot: string;
    FRunner: IAtlasVcsRunner;
    FCommand: TAtlasVcsCommand;
    FWorkingCopyPart: TAtlasSvnWorkingCopyPart;
    FHistoryPart: TAtlasSvnHistoryPart;
    function Svn(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
    /// <summary>Ort für AName nach AOptions (#1290); Failed ohne auflösbaren Ort.</summary>
    function BranchLocation(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
      out APath: string): TAtlasVcsOutcome;
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
    { IAtlasVcsBranching }
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome; overload;
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
    /// <summary>IAtlasVcsSvnWorkingCopy und IAtlasVcsSvnExternals.</summary>
    property WorkingCopyPart: TAtlasSvnWorkingCopyPart read FWorkingCopyPart
      implements IAtlasVcsSvnWorkingCopy, IAtlasVcsSvnExternals;
    /// <summary>IAtlasVcsLineHistory und IAtlasVcsHistory.</summary>
    property HistoryPart: TAtlasSvnHistoryPart read FHistoryPart implements IAtlasVcsLineHistory, IAtlasVcsHistory;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.SvnLayout,
  Atlas.Core.Vcs.Internals.LineTrace;

{ TAtlasSvnPart }

constructor TAtlasSvnPart.Create(const AController: IInterface; const ARoot: string; const ARunner: IAtlasVcsRunner;
  ACommand: TAtlasVcsCommand);
begin
  inherited Create(AController);
  FRoot := ARoot;
  FRunner := ARunner;
  FCommand := ACommand;
end;

function TAtlasSvnPart.Svn(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
begin
  Result := FCommand.Run(AArguments + ['--non-interactive'], AOutput);
end;

{ TAtlasSvnVersionControl }

constructor TAtlasSvnVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FRoot := VcsNormalizeDir(ARoot);
  FRunner := ARunner;
  FCommand := TAtlasVcsCommand.Create(ARunner, AExecutable, FRoot, ATimeoutMs);
  FWorkingCopyPart := TAtlasSvnWorkingCopyPart.Create(Self, FRoot, FRunner, FCommand);
  FHistoryPart := TAtlasSvnHistoryPart.Create(Self, FRoot, FRunner, FCommand);
end;

constructor TAtlasSvnVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string);
begin
  Create(ARoot, ARunner, AExecutable, TAtlasVcsCommand.cDefaultTimeoutMs);
end;

destructor TAtlasSvnVersionControl.Destroy;
begin
  FreeAndNil(FHistoryPart);
  FreeAndNil(FWorkingCopyPart);
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
  mOutput: TBytes;
  mInfo: TAtlasSvnInfo;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := Svn(['info', '--xml', '.'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    mInfo := TAtlasSvnParser.ParseInfo(VcsUtf8(mOutput));
    AHead.Branch := TAtlasSvnParser.BranchOf(mInfo.RelativeUrl);
    AHead.Revision := mInfo.Revision;
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
  mOutput: TBytes;
begin
  AChanges := nil;
  Result := Svn(['status', '--xml', '.'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    AChanges := TAtlasSvnParser.ParseStatus(VcsUtf8(mOutput), FRoot);
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
    mRevision := 'BASE';
  end;
  if mRevision[1] = '-' then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  // "@" am Ende: ein "@" im Dateinamen wäre sonst eine Peg-Revision.
  Result := Svn(['cat', '-r', mRevision, mRelative + '@'], AContent);
end;

function TAtlasSvnVersionControl.Blame(const AFileName: string;
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
  Result := Svn(['blame', '--xml', mRelative + '@'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ALines := TAtlasSvnParser.ParseBlame(VcsUtf8(mOutput));
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
  mDatabase: string;
  mAge: TDateTime;
  mInfo: TSearchRec;
begin
  mDatabase := IncludeTrailingPathDelimiter(FRoot) + '.svn' + PathDelim + 'wc.db';
  if not FileAge(mDatabase, mAge) then
  begin
    Exit('');
  end;
  Result := FloatToStr(mAge, TFormatSettings.Invariant);
  if FindFirst(mDatabase, faAnyFile, mInfo) = 0 then
  try
    Result := Result + '|' + IntToStr(mInfo.Size);
  finally
    FindClose(mInfo);
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
begin
  // svn update holt die Externals mit (#1292: Update(True) ohne).
  Result := FWorkingCopyPart.Update(False);
end;

{ IAtlasVcsBranching (#765) }

function TAtlasSvnVersionControl.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  Result := BranchExists(AName, TAtlasVcsSvnBranchOptions.Legacy, AExists);
end;

function TAtlasSvnVersionControl.BranchLocation(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out APath: string): TAtlasVcsOutcome;
var
  mUrl: string;
begin
  APath := '';
  if not VcsSafeBranchName(AName) or not TAtlasSvnLayout.ValidPattern(AOptions.Location) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  mUrl := '';
  // Die Projektwurzel nur, wenn das Muster sie braucht (ein fester Ort wie ^/branches/{name} ohne Aufruf).
  if TAtlasSvnLayout.NeedsRoot(AOptions.Location) then
  begin
    Result := RepositoryPath(mUrl);
    if Result <> TAtlasVcsOutcome.Ok then
    begin
      Exit;
    end;
  end;
  if TAtlasSvnLayout.Resolve(AOptions, mUrl, AName, APath) then
  begin
    Result := TAtlasVcsOutcome.Ok;
  end
  else
  begin
    Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasSvnVersionControl.BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out AExists: Boolean): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mPath: string;
begin
  AExists := False;
  Result := BranchLocation(AName, AOptions, mPath);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  // "@" am Ende: ein "@" im Namen ist dann keine Revision.
  Result := Svn(['info', '^/' + mPath + '@'], mOutput);
  AExists := Result = TAtlasVcsOutcome.Ok;
  // Fehlt der Branch, endet svn mit Fehler; das ist die Antwort, kein Fehler.
  if Result = TAtlasVcsOutcome.Failed then
  begin
    Result := TAtlasVcsOutcome.Ok;
  end;
end;

function TAtlasSvnVersionControl.RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  // SVN hält keinen lokalen Stand des Servers.
  AExists := False;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  ARevision := '';
  if not VcsSafeBranchName(APath) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := FCommand.RunRemote(TAtlasVcsKind.Svn, ['info', '--show-item', 'revision', '--non-interactive',
    '^/' + APath + '@'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  ARevision := Trim(VcsUtf8(mOutput));
  if (ARevision = '') or (StrToIntDef(ARevision, -1) < 0) then
  begin
    ARevision := '';
    Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasSvnVersionControl.HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  AHas := False;
  Result := Svn(['propget', 'svn:externals', '-R', '.'], mOutput);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    AHas := Trim(VcsUtf8(mOutput)) <> '';
  end;
end;

function TAtlasSvnVersionControl.RepositoryPath(out APath: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  APath := '';
  Result := Svn(['info', '--show-item', 'relative-url', '.'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  APath := Trim(VcsUtf8(mOutput));
  if Copy(APath, 1, 2) = '^/' then
  begin
    Delete(APath, 1, 2);
  end;
  if APath = '' then
  begin
    Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasSvnVersionControl.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
begin
  Result := FWorkingCopyPart.RunStep(AStep);
end;

function TAtlasSvnPart.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mCommand: TAtlasVcsCommand;
begin
  if Length(AStep.Arguments) = 0 then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  // Eingabe für den Schritt (#1291, propset -F): svn:*-Eigenschaften sind UTF-8 mit LF.
  if AStep.InputFile <> '' then
    try
      ForceDirectories(ExtractFileDir(AStep.InputFile));
      TFile.WriteAllBytes(AStep.InputFile, TEncoding.UTF8.GetBytes(StringReplace(AStep.InputText, #13#10, #10,
        [rfReplaceAll])));
    except
      on EInOutError do
        Exit(TAtlasVcsOutcome.Failed);
      on EOSError do
        Exit(TAtlasVcsOutcome.Failed);
    end;
  mCommand := FCommand;
  // switch und checkout holen die ganze Arbeitskopie samt Externals: eigenes, langes Zeitlimit (#1290).
  if AStep.Long and (FCommand.TimeoutMs < TAtlasVcsBranchStep.cLongTimeoutMs) then
  begin
    mCommand := TAtlasVcsCommand.Create(FRunner, FCommand.Executable, FRoot, TAtlasVcsBranchStep.cLongTimeoutMs);
  end;
  try
    // Wie Svn: nie nachfragen (--non-interactive hängt die Umsetzung an, der Plan zeigt es nicht).
    if AStep.Remote then
    begin
      Result := mCommand.RunRemote(TAtlasVcsKind.Svn, AStep.Arguments + ['--non-interactive'], mOutput);
    end
    else
    begin
      Result := mCommand.Run(AStep.Arguments + ['--non-interactive'], mOutput);
    end;
  finally
    if mCommand <> FCommand then
    begin
      mCommand.Free;
    end;
  end;
end;

function TAtlasSvnVersionControl.SwitchBranch(const AName: string): TAtlasVcsOutcome;
begin
  Result := SwitchBranch(AName, TAtlasVcsSvnBranchOptions.Legacy);
end;

function TAtlasSvnVersionControl.SwitchBranch(const AName: string;
  const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
var
  mPath: string;
begin
  Result := BranchLocation(AName, AOptions, mPath);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  Result := RunStep(TAtlasVcsBranchStep.Make(TArray<string>.Create('switch', '^/' + mPath + '@', '.'), True, False,
    True));
end;

function TAtlasSvnWorkingCopyPart.WorkingRevisions(out AText: string): TAtlasVcsOutcome;
begin
  Result := WorkingRevisions('.', AText);
end;

function TAtlasSvnWorkingCopyPart.WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mCommand: TAtlasVcsCommand;
  mExecutable: string;
begin
  AText := '';
  if FCommand.Executable = '' then
  begin
    Exit(TAtlasVcsOutcome.ToolMissing);
  end;
  // svnversion liegt bei allen üblichen Paketen (TortoiseSVN, SlikSVN, CollabNet) neben svn.
  // Fehlt es, meldet der Prozessläufer ToolMissing.
  mExecutable := ExtractFilePath(FCommand.Executable) + 'svnversion' + ExtractFileExt(FCommand.Executable);
  mCommand := TAtlasVcsCommand.Create(FRunner, mExecutable, FRoot, FCommand.TimeoutMs);
  try
    Result := mCommand.Run([AFolder], mOutput);
  finally
    mCommand.Free;
  end;
  if Result = TAtlasVcsOutcome.Ok then
  begin
    AText := Trim(VcsUtf8(mOutput));
  end;
end;

function TAtlasSvnWorkingCopyPart.ExternalsXml(out AText: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  AText := '';
  Result := Svn(['propget', 'svn:externals', '--xml', '-R', '.'], mOutput);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    AText := VcsUtf8(mOutput);
  end;
end;

function TAtlasSvnWorkingCopyPart.RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  AUrl := '';
  Result := Svn(['info', '--show-item', 'repos-root-url', '.'], mOutput);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    AUrl := Trim(VcsUtf8(mOutput));
  end;
  if (Result = TAtlasVcsOutcome.Ok) and (AUrl = '') then
  begin
    Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasSvnWorkingCopyPart.ToolVersion(out AVersion: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  AVersion := '';
  Result := FCommand.Run(['--version', '--quiet'], mOutput);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    AVersion := Trim(VcsUtf8(mOutput));
  end;
end;

{ IAtlasVcsSvnExternals (#1292) }

function TAtlasSvnWorkingCopyPart.StatusXml(out AText: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  AText := '';
  Result := Svn(['status', '--xml', '.'], mOutput);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    AText := VcsUtf8(mOutput);
  end;
end;

function TAtlasSvnWorkingCopyPart.Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
var
  mArguments: TArray<string>;
  mOutput: TBytes;
begin
  mArguments := TArray<string>.Create('update', '.');
  if AIgnoreExternals then
  begin
    mArguments := mArguments + ['--ignore-externals'];
  end;
  // Mit dem Server (#1287): fehlt die Anmeldung, LoginNeeded statt Failed. Das Zeitlimit legt der Aufrufer
  // fest (Pull der Schnellaktionen: PullTimeoutMs).
  Result := FCommand.RunRemote(TAtlasVcsKind.Svn, mArguments + ['--non-interactive'], mOutput);
end;

function TAtlasSvnWorkingCopyPart.CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mReader: TAtlasVcsXmlReader;
  mBase: Integer;
begin
  ACount := 0;
  mBase := StrToIntDef(ARevision, -1);
  if (mBase < 0) or not VcsSafeBranchName(APath) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := FCommand.RunRemote(TAtlasVcsKind.Svn, ['log', '-q', '--xml', '-r', 'HEAD:' + ARevision,
    '^/' + APath + '@HEAD', '--non-interactive'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  // Die Revision selbst steht mit drin, wenn sie den Pfad geändert hat; gezählt wird nur, was danach kam.
  mReader := TAtlasVcsXmlReader.Create(VcsUtf8(mOutput));
  try
    try
      while mReader.Next do
      begin
        if (mReader.Node = TAtlasVcsXmlNode.StartTag) and (mReader.Name = 'logentry') and
          (StrToIntDef(mReader.Attr('revision'), -1) > mBase) then
        begin
          Inc(ACount);
        end;
      end;
    except
      on EAtlasVcsParse do
      begin
        ACount := 0;
        Result := TAtlasVcsOutcome.Failed;
      end;
    end;
  finally
    mReader.Free;
  end;
end;

function TAtlasSvnWorkingCopyPart.SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
var
  mStep: TAtlasVcsBranchStep;
  mTarget: string;
begin
  mTarget := Trim(AOwner);
  if mTarget = '' then
  begin
    mTarget := '.';
  end;
  mStep := TAtlasVcsBranchStep.Make(nil, False, False);
  mStep.InputFile := TPath.Combine(TPath.GetTempPath, 'Atlas-Externals-' + TGUID.NewGuid.ToString + '.txt');
  mStep.InputText := AText;
  mStep.Arguments := TArray<string>.Create('propset', 'svn:externals', '-F', mStep.InputFile, mTarget);
  Result := RunStep(mStep);
  try
    if TFile.Exists(mStep.InputFile) then
    begin
      TFile.Delete(mStep.InputFile);
    end;
  except
    // Ein Rest im Temp-Ordner stört nicht.
    on EInOutError do
      ;
    on EOSError do
      ;
  end;
end;

function TAtlasSvnVersionControl.HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
begin
  AHooks := '';
  AGitDir := '';
  Result := TAtlasVcsOutcome.Ok;
end;

{ IAtlasVcsLineHistory (#1275) }

/// <summary>Revisionsnummer: nur Ziffern, höchstens neun.</summary>
function IsRevision(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AText <> '') and (Length(AText) <= 9);
  if Result then
  begin
    for mIndex := 1 to Length(AText) do
    begin
      if not CharInSet(AText[mIndex], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Taugt jede Revision für svn log -c?</summary>
function AllRevisions(const ARevisions: TArray<string>): Boolean;
var
  mRevision: string;
begin
  for mRevision in ARevisions do
  begin
    if not IsRevision(mRevision) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Höchstens ACount Revisionen ab AStart, mit Komma getrennt.</summary>
function RevisionList(const ARevisions: TArray<string>; AStart, ACount: Integer): string;
begin
  Result := string.Join(',', Copy(ARevisions, AStart, ACount));
end;

function TAtlasSvnHistoryPart.Messages(const AFileName: string; const ARevisions: TArray<string>;
  out AMessages: TArray<TAtlasVcsRevisionMessage>): TAtlasVcsOutcome;
var
  mRelative: string;
  mOutput: TBytes;
  mStart: Integer;
  mCommit: TAtlasVcsLineCommit;
  mMessage: TAtlasVcsRevisionMessage;
begin
  AMessages := nil;
  if not VcsRelativePath(FRoot, AFileName, mRelative) or not AllRevisions(ARevisions) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := TAtlasVcsOutcome.Ok;
  mStart := 0;
  while (Result = TAtlasVcsOutcome.Ok) and (mStart < Length(ARevisions)) do
  begin
    Result := Svn(['log', '--xml', '-c', RevisionList(ARevisions, mStart, cMessageBatch), mRelative + '@'], mOutput);
    Inc(mStart, cMessageBatch);
    if Result <> TAtlasVcsOutcome.Ok then
    begin
      Break;
    end;
    try
      for mCommit in TAtlasSvnParser.ParseLog(VcsUtf8(mOutput)) do
      begin
        mMessage.Revision := mCommit.Revision;
        mMessage.Message := mCommit.Message;
        AMessages := AMessages + [mMessage];
      end;
    except
      on EAtlasVcsParse do
        Result := TAtlasVcsOutcome.Failed;
    end;
  end;
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    AMessages := nil;
  end;
end;

/// <summary>Commits aus ALog zu den Revisionen der Unterschiede, die den Bereich berühren, mit ihrem Unterschied;
/// beide Aufrufe liefern dieselben Revisionen in derselben Reihenfolge, neueste zuerst.</summary>
function TracedCommits(const ALog: TArray<TAtlasVcsLineCommit>; const ADiffs: TArray<TAtlasSvnLogDiff>;
  AFirstLine, ALastLine: Integer): TArray<TAtlasVcsLineCommit>;
var
  mPatches: TArray<TArray<string>>;
  mIndex, mLogIndex: Integer;
begin
  Result := nil;
  SetLength(mPatches, Length(ADiffs));
  for mIndex := 0 to High(ADiffs) do
  begin
    mPatches[mIndex] := ADiffs[mIndex].Patch;
  end;
  for mIndex in TAtlasVcsLineTrace.Trace(mPatches, AFirstLine, ALastLine) do
  begin
    for mLogIndex := 0 to High(ALog) do
    begin
      if ALog[mLogIndex].Revision = ADiffs[mIndex].Revision then
      begin
        Result := Result + [ALog[mLogIndex]];
        Result[High(Result)].Patch := ADiffs[mIndex].Patch;
        Break;
      end;
    end;
  end;
end;

function TAtlasSvnHistoryPart.ReadLineLog(const ARelative, ALimit: string; out ALog: TArray<TAtlasVcsLineCommit>;
  out ADiffs: TArray<TAtlasSvnLogDiff>): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  ALog := nil;
  ADiffs := nil;
  Result := Svn(['log', '--xml', '-l', ALimit, ARelative + '@'], mOutput);
  try
    if Result = TAtlasVcsOutcome.Ok then
    begin
      ALog := TAtlasSvnParser.ParseLog(VcsUtf8(mOutput));
      Result := Svn(['log', '--diff', '-l', ALimit, ARelative + '@'], mOutput);
    end;
    if Result = TAtlasVcsOutcome.Ok then
    begin
      ADiffs := TAtlasSvnParser.ParseLogDiff(VcsConsoleText(mOutput));
    end;
  except
    on EAtlasVcsParse do
      Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasSvnHistoryPart.LineHistory(const AFileName: string; AFirstLine, ALastLine,
  AMaxRevisions: Integer; out ACommits: TArray<TAtlasVcsLineCommit>): TAtlasVcsOutcome;
var
  mRelative: string;
  mLog: TArray<TAtlasVcsLineCommit>;
  mDiffs: TArray<TAtlasSvnLogDiff>;
begin
  ACommits := nil;
  if not VcsRelativePath(FRoot, AFileName, mRelative) or (AFirstLine < 1) or (ALastLine < AFirstLine) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := ReadLineLog(mRelative, IntToStr(Max(1, AMaxRevisions)), mLog, mDiffs);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    ACommits := TracedCommits(mLog, mDiffs, AFirstLine, ALastLine);
  end;
end;

{ IAtlasVcsHistory (#1269) }

function TAtlasSvnHistoryPart.Info(out ARelativeUrl: string): TAtlasVcsOutcome;
var
  mOutput: TBytes;
begin
  ARelativeUrl := '';
  Result := Svn(['info', '--xml', '.'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ARelativeUrl := TAtlasSvnParser.ParseInfo(VcsUtf8(mOutput)).RelativeUrl;
  except
    on EAtlasVcsParse do
      Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasSvnHistoryPart.SearchLog(const AText: string; AMax: Integer;
  out AEntries: TArray<TAtlasVcsLogEntry>): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mRelativeUrl: string;
  mLimit, mIndex: Integer;
begin
  AEntries := nil;
  if Trim(AText) = '' then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  // Glob-Zeichen hätten in --search eine Bedeutung; Kennungen haben keine.
  for mIndex := 1 to Length(AText) do
  begin
    if (Ord(AText[mIndex]) < 32) or CharInSet(AText[mIndex], ['*', '?', '[', ']', '\']) then
    begin
      Exit(TAtlasVcsOutcome.Failed);
    end;
  end;
  Result := Info(mRelativeUrl);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  mLimit := AMax;
  if mLimit < 1 then
  begin
    mLimit := 1;
  end;
  Result := Svn(['log', '--xml', '-v', '--search', AText, '-l', IntToStr(mLimit), '^/'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    AEntries := TAtlasSvnParser.ParseLog(VcsUtf8(mOutput), FRoot, mRelativeUrl);
  except
    on EAtlasVcsParse do
    begin
      AEntries := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasSvnHistoryPart.AllBranches(out ABranches: TArray<TAtlasVcsRef>): TAtlasVcsOutcome;
var
  mOutput: TBytes;
  mRelativeUrl: string;
begin
  ABranches := nil;
  Result := Info(mRelativeUrl);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  // Dieselbe Ablage wie beim Beginnen (#765): ^/branches/<Name>.
  Result := Svn(['list', '--xml', '^/branches'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  try
    ABranches := TAtlasSvnParser.ParseList(VcsUtf8(mOutput), TAtlasSvnParser.BranchOf(mRelativeUrl));
  except
    on EAtlasVcsParse do
    begin
      ABranches := nil;
      Result := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

function TAtlasSvnHistoryPart.Distance(const ABranch, ABase: string; out AAhead, ABehind: Integer): TAtlasVcsOutcome;
begin
  AAhead := -1;
  ABehind := -1;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnHistoryPart.ContentOf(const ARevision: string; const AFile: TAtlasVcsLogFile;
  ABefore: Boolean; out AContent: TBytes): TAtlasVcsOutcome;
var
  mRevision: Integer;
begin
  AContent := nil;
  if not TryStrToInt(ARevision, mRevision) or (mRevision <= 0) or (Copy(AFile.RepositoryPath, 1, 1) <> '/') then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  if (ABefore and (AFile.Kind = TAtlasVcsChangeKind.Added)) or
    (not ABefore and (AFile.Kind = TAtlasVcsChangeKind.Deleted)) then
  begin
    Exit(TAtlasVcsOutcome.Ok);
  end;
  if ABefore then
  begin
    Dec(mRevision);
  end;
  if mRevision <= 0 then
  begin
    Exit(TAtlasVcsOutcome.Ok);
  end;
  // Peg-Revision: der Pfad, wie er in dieser Revision hieß.
  Result := Svn(['cat', '^' + AFile.RepositoryPath + '@' + IntToStr(mRevision)], AContent);
end;

end.
