unit Shell.VcsChanges;

// Host-Rolle Shell: geänderte Dateien und Zeilen aus der Versionsverwaltung für
// --changed und --diff. Startet git bzw. svn über ICompilerProcess und wertet
// die Ausgabe mit TChangedFiles aus. TVcsChanges.Detect wählt wie das Plugin
// über die gemeinsame Schnittstelle der Versionsverwaltung (#571,
// Atlas.Core.Vcs.*): die nächstliegende Arbeitskopie (.git oder .svn, bei
// Gleichstand Git) nach vcs.provider (auto/git/svn/off).
//
// Git (#157):
//   git rev-parse --show-toplevel              Wurzel des Repositorys
//   git merge-base <Basis> HEAD                bei --changed
//   git diff --name-status -M <Ref> [HEAD]     geänderte Dateien; ohne HEAD mit
//                                              Index und Arbeitsverzeichnis
//   git ls-files --others --exclude-standard   neue Dateien bei --include-uncommitted
//   git diff -U0 <Ref> [HEAD]                  geänderte Zeilen
//
// SVN (#276): Änderungen liegen immer in der Arbeitskopie. Wurzel, geänderte
// und neue Dateien kommen aus derselben Umsetzung wie im Plugin
// (TAtlasSvnVersionControl: svn status --xml); nur die Vergleiche mit einer
// Revision laufen hier:
//   svn diff --summarize -r <Rev>              --diff <Rev> bzw. --changed <Rev>
//   svn diff [-r <Rev>]                        geänderte Zeilen
// --include-uncommitted nimmt bei SVN die unversionierten Dateien ("?") dazu.

interface

uses
  System.SysUtils,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Core.Vcs.Contract;

type
  EVcsChanges = class(Exception);

  TVcsChanges = class
  private
    FProcess: ICompilerProcess;
    FWorkingDir: string;
  protected
    FRepoRoot: string;
    FFiles: TArray<string>;
    FLines: TArray<TChangedLines>;
    /// <summary>Startet AExecutable; mit ACheck Ausnahme bei Exit-Code &lt;&gt; 0.</summary>
    function Run(const AExecutable: string; const AArguments: TArray<string>; ACheck: Boolean;
      out AExitCode: Integer): TArray<string>;
    /// <summary>Neue Dateien gelten als vollständig geändert.</summary>
    procedure AddWholeFile(const APath: string);
  public
    constructor Create(const AProcess: ICompilerProcess; const AWorkingDir: string);
    /// <summary>Git oder SVN für AWorkingDir nach vcs.provider (AProvider: auto, git, svn, off); Ausnahme,
    /// wenn keins passt, die Versionsverwaltung abgeschaltet ist oder svn fehlt.</summary>
    class function Detect(const AProcess: ICompilerProcess; const AWorkingDir, AProvider: string): TVcsChanges;
      overload; static;
    /// <summary>Wie oben mit vcs.provider = auto.</summary>
    class function Detect(const AProcess: ICompilerProcess; const AWorkingDir: string): TVcsChanges; overload;
      static;
    /// <summary>Programm aus PATH, z. B. git.exe; AName, wenn nicht gefunden.</summary>
    class function FindProgram(const AName: string): string; static;
    /// <summary>Ermittelt die Änderungen. ADefaultBase: --changed ohne eigene Basis.</summary>
    procedure Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean);
      virtual; abstract;
    /// <summary>Name für Meldungen, z. B. "Git".</summary>
    function Name: string; virtual; abstract;
    property RepoRoot: string read FRepoRoot;
    /// <summary>Geänderte Dateien als vollständige Pfade.</summary>
    property Files: TArray<string> read FFiles;
    property Lines: TArray<TChangedLines> read FLines;
  end;

  TGitChanges = class(TVcsChanges)
  private
    function Git(const AArguments: TArray<string>): TArray<string>;
  public
    procedure Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean); override;
    function Name: string; override;
  end;

  TSvnChanges = class(TVcsChanges)
  private
    FVcs: IAtlasVersionControl;
    function Svn(const AArguments: TArray<string>): TArray<string>;
  public
    /// <summary>AWorkingCopy: gefundene SVN-Arbeitskopie; ASvn: vollständiger Pfad von svn.</summary>
    constructor Create(const AProcess: ICompilerProcess; const AWorkingDir: string;
      const AWorkingCopy: TAtlasVcsWorkingCopy; const ASvn: string);
    procedure Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean); override;
    function Name: string; override;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Detection,
  Atlas.Core.Vcs.Composition,
  Atlas.Core.Vcs.Adapters.ProcessRunner;

{ TVcsChanges }

constructor TVcsChanges.Create(const AProcess: ICompilerProcess; const AWorkingDir: string);
begin
  inherited Create;
  FProcess := AProcess;
  FWorkingDir := AWorkingDir;
end;

class function TVcsChanges.FindProgram(const AName: string): string;
var
  Dir: string;
begin
  // Der Prozessläufer übergibt den Programmnamen direkt an CreateProcess, das PATH nicht durchsucht.
  for Dir in GetEnvironmentVariable('PATH').Split([PathSep]) do
    if (Dir <> '') and TFile.Exists(TPath.Combine(Dir.Trim(['"']), AName + '.exe')) then
      Exit(TPath.Combine(Dir.Trim(['"']), AName + '.exe'));
  Result := AName;
end;

function TVcsChanges.Run(const AExecutable: string; const AArguments: TArray<string>; ACheck: Boolean;
  out AExitCode: Integer): TArray<string>;
var
  Request: TCompilerRequest;
  Output: TArray<string>;
begin
  Request.Executable := FindProgram(AExecutable);
  Request.Arguments := AArguments;
  Request.WorkingDir := FWorkingDir;
  Output := nil;
  AExitCode := FProcess.Run(Request,
    procedure(const ALine: string)
    begin
      Output := Output + [ALine];
    end);
  if ACheck and (AExitCode <> 0) then
    raise EVcsChanges.CreateFmt('%s %s ist fehlgeschlagen (Exit-Code %d): %s',
      [AExecutable, string.Join(' ', AArguments), AExitCode, string.Join(' ', Output)]);
  Result := Output;
end;

procedure TVcsChanges.AddWholeFile(const APath: string);
var
  Whole: TLineSpan;
  Item: TChangedLines;
begin
  FFiles := FFiles + [TChangedFiles.FullPath(FRepoRoot, APath)];
  Whole.First := 0;
  Whole.Last := MaxInt;
  Item.Path := APath;
  Item.Spans := [Whole];
  FLines := FLines + [Item];
end;

class function TVcsChanges.Detect(const AProcess: ICompilerProcess; const AWorkingDir, AProvider: string): TVcsChanges;
var
  Provider: TAtlasVcsProvider;
  WorkingCopy: TAtlasVcsWorkingCopy;
  SvnExe: string;
begin
  Provider := AtlasVcsProviderOf(AProvider);
  if Provider = TAtlasVcsProvider.Off then
    raise EVcsChanges.Create('Versionsverwaltung abgeschaltet (vcs.provider = off)');
  WorkingCopy := TAtlasVcsDetection.Find(AWorkingDir, Provider);
  case WorkingCopy.Kind of
    TAtlasVcsKind.Git:
      Result := TGitChanges.Create(AProcess, AWorkingDir);
    TAtlasVcsKind.Svn:
      begin
        SvnExe := TAtlasVcsTools.Find(TAtlasVcsKind.Svn);
        if SvnExe = '' then
          raise EVcsChanges.CreateFmt('%s liegt in einer SVN-Arbeitskopie, aber svn ist nicht installiert ' +
            '(TortoiseSVN mit Kommandozeilenwerkzeugen genügt)', [AWorkingDir]);
        Result := TSvnChanges.Create(AProcess, AWorkingDir, WorkingCopy, SvnExe);
      end;
  else
    if Provider = TAtlasVcsProvider.Auto then
      raise EVcsChanges.CreateFmt('%s liegt weder in einem Git-Repository noch in einer SVN-Arbeitskopie',
        [AWorkingDir])
    else
      raise EVcsChanges.CreateFmt('%s liegt in keiner Arbeitskopie für vcs.provider = %s',
        [AWorkingDir, AtlasVcsProviderText(Provider)]);
  end;
end;

class function TVcsChanges.Detect(const AProcess: ICompilerProcess; const AWorkingDir: string): TVcsChanges;
begin
  Result := Detect(AProcess, AWorkingDir, 'auto');
end;

{ TGitChanges }

function TGitChanges.Name: string;
begin
  Result := 'Git';
end;

function TGitChanges.Git(const AArguments: TArray<string>): TArray<string>;
var
  ExitCode: Integer;
begin
  // Pfade mit Sonderzeichen kommen als Oktalfolgen (core.quotepath) und damit
  // unabhängig von der Codepage, in der der Prozessläufer liest.
  Result := Run('git', ['-c', 'core.quotepath=on'] + AArguments, True, ExitCode);
end;

procedure TGitChanges.Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean);
var
  Output, Range: TArray<string>;
  Ref, Path: string;
begin
  Output := Git(['rev-parse', '--show-toplevel']);
  if Length(Output) = 0 then
    raise EVcsChanges.Create('Kein Git-Repository');
  FRepoRoot := ExcludeTrailingPathDelimiter(StringReplace(Trim(Output[0]), '/', PathDelim, [rfReplaceAll]));
  Ref := ARef;
  if AMergeBase then
  begin
    Output := Git(['merge-base', ARef, 'HEAD']);
    if Length(Output) = 0 then
      raise EVcsChanges.CreateFmt('Keine Merge-Base mit %s', [ARef]);
    Ref := Trim(Output[0]);
  end;
  // Ohne HEAD vergleicht git diff mit dem Arbeitsverzeichnis, Index eingeschlossen.
  if AIncludeUncommitted then
    Range := [Ref]
  else
    Range := [Ref, 'HEAD'];
  FFiles := nil;
  for Path in TChangedFiles.ParseNameStatus(Git(['diff', '--name-status', '-M', '--no-color'] + Range)) do
    FFiles := FFiles + [TChangedFiles.FullPath(FRepoRoot, Path)];
  FLines := nil;
  if AWithLines then
    FLines := TChangedFiles.ParseHunks(Git(['diff', '-U0', '-M', '--no-color', '--no-ext-diff'] + Range));
  if AIncludeUncommitted then
    for Path in Git(['ls-files', '--others', '--exclude-standard', '--full-name', ':/']) do
      if Trim(Path) <> '' then
        AddWholeFile(TChangedFiles.UnquotePath(Trim(Path)));
end;

{ TSvnChanges }

constructor TSvnChanges.Create(const AProcess: ICompilerProcess; const AWorkingDir: string;
  const AWorkingCopy: TAtlasVcsWorkingCopy; const ASvn: string);
var
  Runner: IAtlasVcsRunner;
begin
  inherited Create(AProcess, AWorkingDir);
  // Kommandozeile: kein Fenster, der Hauptthread darf warten.
  Runner := TAtlasVcsProcessRunner.Create(True, nil);
  FVcs := TAtlasVersionControl.ForWorkingCopy(AWorkingCopy, Runner, ASvn, TAtlasVcsCommand.DefaultTimeoutMs * 4);
end;

function TSvnChanges.Name: string;
begin
  Result := 'SVN';
end;

function TSvnChanges.Svn(const AArguments: TArray<string>): TArray<string>;
var
  ExitCode: Integer;
begin
  Result := Run('svn', ['--non-interactive'] + AArguments, True, ExitCode);
end;

procedure TSvnChanges.Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean);
var
  Range: TArray<string>;
  Changes: TArray<TAtlasVcsChange>;
  Change: TAtlasVcsChange;
  Path, Relative: string;
  Outcome: TAtlasVcsOutcome;
begin
  FRepoRoot := FVcs.WorkingCopy.Root;
  // Pfade relativ zur Wurzel: svn läuft dort.
  FWorkingDir := FRepoRoot;
  FFiles := nil;
  FLines := nil;
  Changes := nil;
  if ADefaultBase or AIncludeUncommitted then
  begin
    Outcome := FVcs.Changes(Changes);
    if Outcome <> TAtlasVcsOutcome.Ok then
      raise EVcsChanges.CreateFmt('svn status ist fehlgeschlagen (%s)',
        [AtlasVcsOutcomeName(Outcome)]);
  end;
  // SVN kennt keine Merge-Base: --changed ohne eigene Basis vergleicht mit BASE.
  if ADefaultBase then
  begin
    Range := nil;
    // Wie bisher A, M und R; gelöschte und fehlende Dateien gibt es nicht zu prüfen.
    for Change in Changes do
      if (Change.Kind = TAtlasVcsChangeKind.Modified) or (Change.Kind = TAtlasVcsChangeKind.Added) or
        (Change.Kind = TAtlasVcsChangeKind.Replaced) then
        FFiles := FFiles + [Change.Path];
  end
  else
  begin
    Range := ['-r', ARef];
    for Path in TChangedFiles.ParseSvnSummarize(Svn(['diff', '--summarize'] + Range)) do
      FFiles := FFiles + [TChangedFiles.FullPath(FRepoRoot, Path)];
  end;
  if AWithLines then
    FLines := TChangedFiles.ParseSvnDiff(Svn(['diff', '--internal-diff'] + Range));
  if AIncludeUncommitted then
    for Change in Changes do
      if (Change.Kind = TAtlasVcsChangeKind.Untracked) and
        TAtlasVcsDetection.RelativePath(FRepoRoot, Change.Path, Relative) then
        AddWholeFile(Relative);
end;

end.
