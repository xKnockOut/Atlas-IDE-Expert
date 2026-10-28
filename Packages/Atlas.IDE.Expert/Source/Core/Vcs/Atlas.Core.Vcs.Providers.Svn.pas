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
// ChangeMarker: Zeitstempel und Größe von .svn/wc.db; svn update und
// svn switch schreiben die Datenbank.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools;

type
  TAtlasSvnVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork, IAtlasVcsIncoming,
    IAtlasVcsUpdate, IAtlasVcsBranching, IAtlasVcsSvnWorkingCopy, IAtlasVcsSvnExternals)
  private
    FRoot: string;
    FRunner: IAtlasVcsRunner;
    FCommand: TAtlasVcsCommand;
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

implementation

uses
  System.IOUtils,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.SvnLayout,
  Atlas.Core.Vcs.Internals.SvnParser;

{ TAtlasSvnVersionControl }

constructor TAtlasSvnVersionControl.Create(const ARoot: string; const ARunner: IAtlasVcsRunner;
  const AExecutable: string; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FRoot := VcsNormalizeDir(ARoot);
  FRunner := ARunner;
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
  Result := FloatToStr(Age, TFormatSettings.Invariant);
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
begin
  // svn update holt die Externals mit (#1292: Update(True) ohne).
  Result := Update(False);
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
    Exit(TAtlasVcsOutcome.Failed);
  mUrl := '';
  // Die Projektwurzel nur, wenn das Muster sie braucht (ein fester Ort wie ^/branches/{name} ohne Aufruf).
  if TAtlasSvnLayout.NeedsRoot(AOptions.Location) then
  begin
    Result := RepositoryPath(mUrl);
    if Result <> TAtlasVcsOutcome.Ok then
      Exit;
  end;
  if TAtlasSvnLayout.Resolve(AOptions, mUrl, AName, APath) then
    Result := TAtlasVcsOutcome.Ok
  else
    Result := TAtlasVcsOutcome.Failed;
end;

function TAtlasSvnVersionControl.BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out AExists: Boolean): TAtlasVcsOutcome;
var
  Output: TBytes;
  mPath: string;
begin
  AExists := False;
  Result := BranchLocation(AName, AOptions, mPath);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  // "@" am Ende: ein "@" im Namen ist dann keine Revision.
  Result := Svn(['info', '^/' + mPath + '@'], Output);
  AExists := Result = TAtlasVcsOutcome.Ok;
  // Fehlt der Branch, endet svn mit Fehler; das ist die Antwort, kein Fehler.
  if Result = TAtlasVcsOutcome.Failed then
    Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  // SVN hält keinen lokalen Stand des Servers.
  AExists := False;
  Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  ARevision := '';
  if not VcsSafeBranchName(APath) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := FCommand.RunRemote(TAtlasVcsKind.Svn, ['info', '--show-item', 'revision', '--non-interactive',
    '^/' + APath + '@'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  ARevision := Trim(VcsUtf8(Output));
  if (ARevision = '') or (StrToIntDef(ARevision, -1) < 0) then
  begin
    ARevision := '';
    Result := TAtlasVcsOutcome.Failed;
  end;
end;

function TAtlasSvnVersionControl.HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AHas := False;
  Result := Svn(['propget', 'svn:externals', '-R', '.'], Output);
  if Result = TAtlasVcsOutcome.Ok then
    AHas := Trim(VcsUtf8(Output)) <> '';
end;

function TAtlasSvnVersionControl.RepositoryPath(out APath: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  APath := '';
  Result := Svn(['info', '--show-item', 'relative-url', '.'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  APath := Trim(VcsUtf8(Output));
  if Copy(APath, 1, 2) = '^/' then
    Delete(APath, 1, 2);
  if APath = '' then
    Result := TAtlasVcsOutcome.Failed;
end;

function TAtlasSvnVersionControl.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
var
  Output: TBytes;
  mCommand: TAtlasVcsCommand;
begin
  if Length(AStep.Arguments) = 0 then
    Exit(TAtlasVcsOutcome.Failed);
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
  if AStep.Long and (FCommand.TimeoutMs < TAtlasVcsBranchStep.LongTimeoutMs) then
    mCommand := TAtlasVcsCommand.Create(FRunner, FCommand.Executable, FRoot, TAtlasVcsBranchStep.LongTimeoutMs);
  try
    // Wie Svn: nie nachfragen (--non-interactive hängt die Umsetzung an, der Plan zeigt es nicht).
    if AStep.Remote then
      Result := mCommand.RunRemote(TAtlasVcsKind.Svn, AStep.Arguments + ['--non-interactive'], Output)
    else
      Result := mCommand.Run(AStep.Arguments + ['--non-interactive'], Output);
  finally
    if mCommand <> FCommand then
      mCommand.Free;
  end;
end;

function TAtlasSvnVersionControl.SwitchBranch(const AName: string): TAtlasVcsOutcome;
begin
  Result := SwitchBranch(AName, TAtlasVcsSvnBranchOptions.Legacy);
end;

function TAtlasSvnVersionControl.SwitchBranch(const AName: string;
  const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
var
  Output: TBytes;
  mPath: string;
begin
  Result := BranchLocation(AName, AOptions, mPath);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  Result := RunStep(TAtlasVcsBranchStep.Make(TArray<string>.Create('switch', '^/' + mPath + '@', '.'), True, False,
    True));
end;

function TAtlasSvnVersionControl.WorkingRevisions(out AText: string): TAtlasVcsOutcome;
begin
  Result := WorkingRevisions('.', AText);
end;

function TAtlasSvnVersionControl.WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome;
var
  Output: TBytes;
  mCommand: TAtlasVcsCommand;
  mExecutable: string;
begin
  AText := '';
  if FCommand.Executable = '' then
    Exit(TAtlasVcsOutcome.ToolMissing);
  // svnversion liegt bei allen üblichen Paketen (TortoiseSVN, SlikSVN, CollabNet) neben svn.
  // Fehlt es, meldet der Prozessläufer ToolMissing.
  mExecutable := ExtractFilePath(FCommand.Executable) + 'svnversion' + ExtractFileExt(FCommand.Executable);
  mCommand := TAtlasVcsCommand.Create(FRunner, mExecutable, FRoot, FCommand.TimeoutMs);
  try
    Result := mCommand.Run([AFolder], Output);
  finally
    mCommand.Free;
  end;
  if Result = TAtlasVcsOutcome.Ok then
    AText := Trim(VcsUtf8(Output));
end;

function TAtlasSvnVersionControl.ExternalsXml(out AText: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AText := '';
  Result := Svn(['propget', 'svn:externals', '--xml', '-R', '.'], Output);
  if Result = TAtlasVcsOutcome.Ok then
    AText := VcsUtf8(Output);
end;

function TAtlasSvnVersionControl.RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AUrl := '';
  Result := Svn(['info', '--show-item', 'repos-root-url', '.'], Output);
  if Result = TAtlasVcsOutcome.Ok then
    AUrl := Trim(VcsUtf8(Output));
  if (Result = TAtlasVcsOutcome.Ok) and (AUrl = '') then
    Result := TAtlasVcsOutcome.Failed;
end;

function TAtlasSvnVersionControl.ToolVersion(out AVersion: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AVersion := '';
  Result := FCommand.Run(['--version', '--quiet'], Output);
  if Result = TAtlasVcsOutcome.Ok then
    AVersion := Trim(VcsUtf8(Output));
end;

{ IAtlasVcsSvnExternals (#1292) }

function TAtlasSvnVersionControl.StatusXml(out AText: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AText := '';
  Result := Svn(['status', '--xml', '.'], Output);
  if Result = TAtlasVcsOutcome.Ok then
    AText := VcsUtf8(Output);
end;

function TAtlasSvnVersionControl.Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
var
  mArguments: TArray<string>;
  Output: TBytes;
begin
  mArguments := TArray<string>.Create('update', '.');
  if AIgnoreExternals then
    mArguments := mArguments + ['--ignore-externals'];
  // Mit dem Server (#1287): fehlt die Anmeldung, LoginNeeded statt Failed. Das Zeitlimit legt der Aufrufer
  // fest (Pull der Schnellaktionen: PullTimeoutMs).
  Result := FCommand.RunRemote(TAtlasVcsKind.Svn, mArguments + ['--non-interactive'], Output);
end;

function TAtlasSvnVersionControl.CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
var
  Output: TBytes;
  mReader: TAtlasVcsXmlReader;
  mBase: Integer;
begin
  ACount := 0;
  mBase := StrToIntDef(ARevision, -1);
  if (mBase < 0) or not VcsSafeBranchName(APath) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := FCommand.RunRemote(TAtlasVcsKind.Svn, ['log', '-q', '--xml', '-r', 'HEAD:' + ARevision,
    '^/' + APath + '@HEAD', '--non-interactive'], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  // Die Revision selbst steht mit drin, wenn sie den Pfad geändert hat; gezählt wird nur, was danach kam.
  mReader := TAtlasVcsXmlReader.Create(VcsUtf8(Output));
  try
    try
      while mReader.Next do
        if (mReader.Node = TAtlasVcsXmlNode.StartTag) and (mReader.Name = 'logentry') and
          (StrToIntDef(mReader.Attr('revision'), -1) > mBase) then
          Inc(ACount);
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

function TAtlasSvnVersionControl.SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
var
  mStep: TAtlasVcsBranchStep;
  mTarget: string;
begin
  mTarget := Trim(AOwner);
  if mTarget = '' then
    mTarget := '.';
  mStep := TAtlasVcsBranchStep.Make(nil, False, False);
  mStep.InputFile := TPath.Combine(TPath.GetTempPath, 'Atlas-Externals-' + TGUID.NewGuid.ToString + '.txt');
  mStep.InputText := AText;
  mStep.Arguments := TArray<string>.Create('propset', 'svn:externals', '-F', mStep.InputFile, mTarget);
  Result := RunStep(mStep);
  try
    if TFile.Exists(mStep.InputFile) then
      TFile.Delete(mStep.InputFile);
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

end.
