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
// ChangeMarker liest nur Dateien: .git/HEAD (Inhalt und Zeitstempel), die
// Datei des Branchs unter refs/heads und packed-refs. In Worktrees und
// Submodulen ist .git eine Datei mit "gitdir: …".

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools;

type
  TAtlasGitVersionControl = class(TInterfacedObject, IAtlasVersionControl)
  private
    FRoot: string;
    FCommand: TAtlasVcsCommand;
    function Git(const AArguments: TArray<string>; out AOutput: TBytes): TAtlasVcsOutcome;
    function Status(AUntracked: Boolean; out AHead: TAtlasVcsHead;
      out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
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
    Result := FloatToStr(Age)
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
  if (Pos(':', Content) = 2) or (Copy(Content, 1, 1) = '/') or (Copy(Content, 1, 2) = '\\') then
    Result := VcsNormalizeDir(Content)
  else
    Result := VcsFullPath(ARoot, Content);
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
