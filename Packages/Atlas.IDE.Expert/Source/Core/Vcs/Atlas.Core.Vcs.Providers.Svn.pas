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
//   BranchExists info ^/branches/<Name>@
//   CreateBranch copy ^/<Basis>@ ^/branches/<Name>@ --parents -m <Nachricht>, dann SwitchBranch
//   SwitchBranch switch ^/branches/<Name>@ .
//   HookFolders  ohne Prozess Ok mit '' (SVN hat keine Hooks auf dem Rechner)
// Issues der Zeilenhistorie (IAtlasVcsLineHistory, #1275), mit dem Server:
//   Messages     log --xml -c <r1,r2,…> <Pfad>@        (je 100 Revisionen ein Aufruf)
//   LineHistory  log --xml -l N <Pfad>@ und log --diff -l N <Pfad>@, dann
//                rückwärts verfolgt (Atlas.Core.Vcs.Internals.LineTrace). Statt
//                je Revision „svn blame -r“ reichen so zwei Aufrufe für N
//                Revisionen; 200 Revisionen bleiben weit unter 5 s.
// ChangeMarker: Zeitstempel und Größe von .svn/wc.db; svn update und
// svn switch schreiben die Datenbank.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools;

type
  TAtlasSvnVersionControl = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork, IAtlasVcsIncoming,
    IAtlasVcsUpdate, IAtlasVcsBranching, IAtlasVcsLineHistory)
  public const
    /// <summary>Höchstens so viele Revisionen je Aufruf von Messages.</summary>
    MessageBatch = 100;
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
    { IAtlasVcsBranching }
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    function CreateBranch(const AName, ABase, AMessage: string): TAtlasVcsOutcome;
    function SwitchBranch(const AName: string): TAtlasVcsOutcome;
    function HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
    { IAtlasVcsLineHistory }
    function Messages(const AFileName: string; const ARevisions: TArray<string>;
      out AMessages: TArray<TAtlasVcsRevisionMessage>): TAtlasVcsOutcome;
    function LineHistory(const AFileName: string; AFirstLine, ALastLine, AMaxRevisions: Integer;
      out ACommits: TArray<TAtlasVcsLineCommit>): TAtlasVcsOutcome;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.SvnParser,
  Atlas.Core.Vcs.Internals.LineTrace;

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
var
  Output: TBytes;
begin
  Result := Svn(['update', '.'], Output);
end;

{ IAtlasVcsBranching (#765) }

function TAtlasSvnVersionControl.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  AExists := False;
  if not VcsSafeBranchName(AName) then
    Exit(TAtlasVcsOutcome.Failed);
  // "@" am Ende: ein "@" im Namen ist dann keine Revision.
  Result := Svn(['info', '^/branches/' + AName + '@'], Output);
  AExists := Result = TAtlasVcsOutcome.Ok;
  // Fehlt der Branch, endet svn mit Fehler; das ist die Antwort, kein Fehler.
  if Result = TAtlasVcsOutcome.Failed then
    Result := TAtlasVcsOutcome.Ok;
end;

function TAtlasSvnVersionControl.CreateBranch(const AName, ABase, AMessage: string): TAtlasVcsOutcome;
var
  Output: TBytes;
  Base, Message: string;
begin
  Base := ABase;
  if Base = '' then
    Base := 'trunk';
  if not VcsSafeBranchName(AName) or not VcsSafeBranchName(Base) then
    Exit(TAtlasVcsOutcome.Failed);
  Message := Trim(AMessage);
  if Message = '' then
    Message := 'Branch ' + AName;
  Result := Svn(['copy', '^/' + Base + '@', '^/branches/' + AName + '@', '--parents', '-m', Message], Output);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  Result := SwitchBranch(AName);
end;

function TAtlasSvnVersionControl.SwitchBranch(const AName: string): TAtlasVcsOutcome;
var
  Output: TBytes;
begin
  if not VcsSafeBranchName(AName) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := Svn(['switch', '^/branches/' + AName + '@', '.'], Output);
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
    for mIndex := 1 to Length(AText) do
      if not CharInSet(AText[mIndex], ['0'..'9']) then
        Exit(False);
end;

function TAtlasSvnVersionControl.Messages(const AFileName: string; const ARevisions: TArray<string>;
  out AMessages: TArray<TAtlasVcsRevisionMessage>): TAtlasVcsOutcome;
var
  mRelative, mRevision, mList: string;
  mOutput: TBytes;
  mStart, mIndex: Integer;
  mCommit: TAtlasVcsLineCommit;
  mMessage: TAtlasVcsRevisionMessage;
begin
  AMessages := nil;
  if not VcsRelativePath(FRoot, AFileName, mRelative) then
    Exit(TAtlasVcsOutcome.Failed);
  for mRevision in ARevisions do
    if not IsRevision(mRevision) then
      Exit(TAtlasVcsOutcome.Failed);
  Result := TAtlasVcsOutcome.Ok;
  mStart := 0;
  while mStart < Length(ARevisions) do
  begin
    mList := '';
    for mIndex := mStart to Min(mStart + MessageBatch, Length(ARevisions)) - 1 do
    begin
      if mList <> '' then
        mList := mList + ',';
      mList := mList + ARevisions[mIndex];
    end;
    Inc(mStart, MessageBatch);
    Result := Svn(['log', '--xml', '-c', mList, mRelative + '@'], mOutput);
    if Result <> TAtlasVcsOutcome.Ok then
      Break;
    try
      for mCommit in TAtlasSvnParser.ParseLog(VcsUtf8(mOutput)) do
      begin
        mMessage.Revision := mCommit.Revision;
        mMessage.Message := mCommit.Message;
        AMessages := AMessages + [mMessage];
      end;
    except
      on EAtlasVcsParse do
      begin
        Result := TAtlasVcsOutcome.Failed;
        Break;
      end;
    end;
  end;
  if Result <> TAtlasVcsOutcome.Ok then
    AMessages := nil;
end;

function TAtlasSvnVersionControl.LineHistory(const AFileName: string; AFirstLine, ALastLine,
  AMaxRevisions: Integer; out ACommits: TArray<TAtlasVcsLineCommit>): TAtlasVcsOutcome;
var
  mRelative, mLimit: string;
  mOutput: TBytes;
  mLog: TArray<TAtlasVcsLineCommit>;
  mDiffs: TArray<TAtlasSvnLogDiff>;
  mPatches: TArray<TArray<string>>;
  mIndex, mLogIndex: Integer;
begin
  ACommits := nil;
  if not VcsRelativePath(FRoot, AFileName, mRelative) or (AFirstLine < 1) or (ALastLine < AFirstLine) then
    Exit(TAtlasVcsOutcome.Failed);
  mLimit := IntToStr(Max(1, AMaxRevisions));
  Result := Svn(['log', '--xml', '-l', mLimit, mRelative + '@'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    mLog := TAtlasSvnParser.ParseLog(VcsUtf8(mOutput));
  except
    on EAtlasVcsParse do
      Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := Svn(['log', '--diff', '-l', mLimit, mRelative + '@'], mOutput);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  try
    mDiffs := TAtlasSvnParser.ParseLogDiff(VcsConsoleText(mOutput));
  except
    on EAtlasVcsParse do
      Exit(TAtlasVcsOutcome.Failed);
  end;
  SetLength(mPatches, Length(mDiffs));
  for mIndex := 0 to High(mDiffs) do
    mPatches[mIndex] := mDiffs[mIndex].Patch;
  // Beide Aufrufe liefern dieselben Revisionen in derselben Reihenfolge, neueste zuerst.
  for mIndex in TAtlasVcsLineTrace.Trace(mPatches, AFirstLine, ALastLine) do
    for mLogIndex := 0 to High(mLog) do
      if mLog[mLogIndex].Revision = mDiffs[mIndex].Revision then
      begin
        mLog[mLogIndex].Patch := mDiffs[mIndex].Patch;
        ACommits := ACommits + [mLog[mLogIndex]];
        Break;
      end;
end;

end.
