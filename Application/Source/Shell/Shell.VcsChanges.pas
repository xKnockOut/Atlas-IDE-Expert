unit Shell.VcsChanges;

// Host-Rolle Shell: geänderte Dateien und Zeilen aus der Versionsverwaltung für
// --changed und --diff. Startet git bzw. svn über ICompilerProcess und wertet
// die Ausgabe mit TChangedFiles aus. TVcsChanges.Detect wählt wie das Plugin
// über die gemeinsame Schnittstelle der Versionsverwaltung (#571,
// Atlas.Core.Vcs.*): die nächstliegende Arbeitskopie (.git oder .svn, bei
// Gleichstand Git) nach vcs.provider (auto/git/svn/off).
// vcs.git.path und vcs.svn.path (#1285): derselbe eigene Pfad wie im Plugin
// (TAtlasVcsTools.Probe); fehlt die Datei dort, bricht --changed mit dieser
// Ursache ab, statt ein anderes Programm zu nehmen. vcs.timeoutSeconds gilt
// für die Abfragen über die gemeinsame Umsetzung (SVN-Status), mal vier wie
// bisher, weil die Kommandozeile warten darf.
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
    /// <summary>Wie oben mit eigenen Programmpfaden (vcs.git.path, vcs.svn.path; '' = automatisch suchen) und
    /// Zeitlimit je Aufruf in Sekunden (vcs.timeoutSeconds, #1285).</summary>
    class function Detect(const AProcess: ICompilerProcess; const AWorkingDir, AProvider, AGitPath,
      ASvnPath: string; ATimeoutSeconds: Integer): TVcsChanges; overload; static;
    /// <summary>Programm für AKind nach dem eigenen Pfad AConfigured ('' = PATH und bekannte Ordner); Ausnahme,
    /// wenn ein eigener Pfad gesetzt ist und die Datei fehlt. '' ohne Fund.</summary>
    class function ToolFor(AKind: TAtlasVcsKind; const AConfigured: string): string; static;
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
    FGit: string;
    function Git(const AArguments: TArray<string>): TArray<string>;
  public
    /// <summary>AGit: vollständiger Pfad von git; '' = git aus PATH.</summary>
    constructor Create(const AProcess: ICompilerProcess; const AWorkingDir, AGit: string);
    procedure Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean); override;
    function Name: string; override;
  end;

  TSvnChanges = class(TVcsChanges)
  private
    FVcs: IAtlasVersionControl;
    FSvn: string;
    function Svn(const AArguments: TArray<string>): TArray<string>;
  public
    /// <summary>AWorkingCopy: gefundene SVN-Arbeitskopie; ASvn: vollständiger Pfad von svn; ATimeoutMs: Zeitlimit
    /// je Aufruf über die gemeinsame Umsetzung.</summary>
    constructor Create(const AProcess: ICompilerProcess; const AWorkingDir: string;
      const AWorkingCopy: TAtlasVcsWorkingCopy; const ASvn: string; ATimeoutMs: Cardinal);
    procedure Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean); override;
    function Name: string; override;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Detection,
  Atlas.Core.Vcs.Composition,
  Shell.Platform,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TVcsChangesText = (Failed, NotFound, NoSvn, NoWorkingCopy, NoProviderCopy, NoGit, NoMergeBase, SvnStatus);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TVcsChangesText] of TAtlasText = (
    (De: '%s %s ist fehlgeschlagen (Exit-Code %d): %s'; En: '%s %s failed (exit code %d): %s'),
    (De: '%s nicht gefunden unter %s (vcs.%s.path)'; En: '%s not found at %s (vcs.%s.path)'),
    (De: '%s liegt in einer SVN-Arbeitskopie, aber svn ist nicht installiert (TortoiseSVN mit ' +
    'Kommandozeilenwerkzeugen genügt)';
    En: '%s is in an SVN working copy, but svn is not installed (TortoiseSVN with command-line tools is enough)'),
    (De: '%s liegt weder in einem Git-Repository noch in einer SVN-Arbeitskopie';
    En: '%s is neither in a Git repository nor in an SVN working copy'),
    (De: '%s liegt in keiner Arbeitskopie für vcs.provider = %s';
    En: '%s is in no working copy for vcs.provider = %s'),
    (De: 'Kein Git-Repository'; En: 'No Git repository'),
    (De: 'Keine Merge-Base mit %s'; En: 'No merge base with %s'),
    (De: 'svn status ist fehlgeschlagen (%s)'; En: 'svn status failed (%s)'));

{ TVcsChanges }

constructor TVcsChanges.Create(const AProcess: ICompilerProcess; const AWorkingDir: string);
begin
  inherited Create;
  FProcess := AProcess;
  FWorkingDir := AWorkingDir;
end;

class function TVcsChanges.FindProgram(const AName: string): string;
var
  mDir: string;
begin
  // Der Prozessläufer übergibt den Programmnamen direkt an CreateProcess, das PATH nicht durchsucht.
  for mDir in GetEnvironmentVariable('PATH').Split([PathSep]) do
  begin
    if (mDir <> '') and TFile.Exists(TPath.Combine(mDir.Trim(['"']), AName + '.exe')) then
    begin
      Exit(TPath.Combine(mDir.Trim(['"']), AName + '.exe'));
    end;
  end;
  Result := AName;
end;

function TVcsChanges.Run(const AExecutable: string; const AArguments: TArray<string>; ACheck: Boolean;
  out AExitCode: Integer): TArray<string>;
var
  mRequest: TCompilerRequest;
  mOutput: TArray<string>;
begin
  mRequest.Executable := FindProgram(AExecutable);
  mRequest.Arguments := AArguments;
  mRequest.WorkingDir := FWorkingDir;
  mOutput := nil;
  AExitCode := FProcess.Run(mRequest,
    procedure(const ALine: string)
    begin
      mOutput := mOutput + [ALine];
    end);
  if ACheck and (AExitCode <> 0) then
  begin
    raise EVcsChanges.Create(cTexts[TVcsChangesText.Failed].Fmt([AExecutable, string.Join(' ', AArguments),
      AExitCode, string.Join(' ', mOutput)]));
  end;
  Result := mOutput;
end;

procedure TVcsChanges.AddWholeFile(const APath: string);
var
  mWhole: TLineSpan;
  mItem: TChangedLines;
begin
  FFiles := FFiles + [TChangedFiles.FullPath(FRepoRoot, APath)];
  mWhole.First := 0;
  mWhole.Last := MaxInt;
  mItem.Path := APath;
  mItem.Spans := [mWhole];
  FLines := FLines + [mItem];
end;

class function TVcsChanges.ToolFor(AKind: TAtlasVcsKind; const AConfigured: string): string;
var
  mLocation: TAtlasVcsToolLocation;
begin
  // Ohne eigenen Pfad der gemerkte Fund (auch TAtlasVcsTools.Preset), sonst neu suchen.
  if AConfigured = '' then
  begin
    mLocation := TAtlasVcsTools.Where(AKind);
  end
  else
  begin
    mLocation := TAtlasVcsTools.Probe(AKind, AConfigured);
  end;
  if mLocation.Source = TAtlasVcsToolSource.ConfiguredMissing then
  begin
    raise EVcsChanges.Create(cTexts[TVcsChangesText.NotFound].Fmt([TAtlasVcsTools.ProgramName(AKind),
      mLocation.Configured,
      TAtlasVcsTools.ProgramName(AKind)]));
  end;
  Result := mLocation.Executable;
end;

class function TVcsChanges.Detect(const AProcess: ICompilerProcess; const AWorkingDir, AProvider: string): TVcsChanges;
begin
  Result := Detect(AProcess, AWorkingDir, AProvider, '', '', TAtlasVcsCommand.cDefaultTimeoutMs div 1000);
end;

class function TVcsChanges.Detect(const AProcess: ICompilerProcess; const AWorkingDir, AProvider, AGitPath,
  ASvnPath: string; ATimeoutSeconds: Integer): TVcsChanges;
var
  mProvider: TAtlasVcsProvider;
  mWorkingCopy: TAtlasVcsWorkingCopy;
  mSvnExe: string;
  mTimeoutMs: Cardinal;
begin
  mTimeoutMs := TAtlasVcsCommand.cDefaultTimeoutMs;
  if (ATimeoutSeconds >= 1) and (ATimeoutSeconds <= 300) then
  begin
    mTimeoutMs := Cardinal(ATimeoutSeconds) * 1000;
  end;
  mProvider := AtlasVcsProviderOf(AProvider);
  if mProvider = TAtlasVcsProvider.Off then
  begin
    raise EVcsChanges.Create('Versionsverwaltung abgeschaltet (vcs.provider = off)');
  end;
  mWorkingCopy := TAtlasVcsDetection.Find(AWorkingDir, mProvider);
  case mWorkingCopy.Kind of
    TAtlasVcsKind.Git:
      Result := TGitChanges.Create(AProcess, AWorkingDir, ToolFor(TAtlasVcsKind.Git, AGitPath));
    TAtlasVcsKind.Svn:
      begin
        mSvnExe := ToolFor(TAtlasVcsKind.Svn, ASvnPath);
        if mSvnExe = '' then
        begin
          raise EVcsChanges.Create(cTexts[TVcsChangesText.NoSvn].Fmt([AWorkingDir]));
        end;
        Result := TSvnChanges.Create(AProcess, AWorkingDir, mWorkingCopy, mSvnExe, mTimeoutMs * 4);
      end;
  else
    if mProvider = TAtlasVcsProvider.Auto then
    begin
      raise EVcsChanges.Create(cTexts[TVcsChangesText.NoWorkingCopy].Fmt([AWorkingDir]));
    end
    else
    begin
      raise EVcsChanges.Create(cTexts[TVcsChangesText.NoProviderCopy].Fmt([AWorkingDir,
        AtlasVcsProviderText(mProvider)]));
    end;
  end;
end;

class function TVcsChanges.Detect(const AProcess: ICompilerProcess; const AWorkingDir: string): TVcsChanges;
begin
  Result := Detect(AProcess, AWorkingDir, 'auto');
end;

{ TGitChanges }

constructor TGitChanges.Create(const AProcess: ICompilerProcess; const AWorkingDir, AGit: string);
begin
  inherited Create(AProcess, AWorkingDir);
  FGit := AGit;
end;

function TGitChanges.Name: string;
begin
  Result := 'Git';
end;

function TGitChanges.Git(const AArguments: TArray<string>): TArray<string>;
var
  mExitCode: Integer;
begin
  // Pfade mit Sonderzeichen kommen als Oktalfolgen (core.quotepath) und damit
  // unabhängig von der Codepage, in der der Prozessläufer liest.
  if FGit <> '' then
  begin
    Result := Run(FGit, ['-c', 'core.quotepath=on'] + AArguments, True, mExitCode);
  end
  else
  begin
    Result := Run('git', ['-c', 'core.quotepath=on'] + AArguments, True, mExitCode);
  end;
end;

procedure TGitChanges.Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean);
var
  mOutput, mRange: TArray<string>;
  mRef, mPath: string;
begin
  mOutput := Git(['rev-parse', '--show-toplevel']);
  if Length(mOutput) = 0 then
  begin
    raise EVcsChanges.Create(cTexts[TVcsChangesText.NoGit].Text);
  end;
  FRepoRoot := ExcludeTrailingPathDelimiter(StringReplace(Trim(mOutput[0]), '/', PathDelim, [rfReplaceAll]));
  mRef := ARef;
  if AMergeBase then
  begin
    mOutput := Git(['merge-base', ARef, 'HEAD']);
    if Length(mOutput) = 0 then
    begin
      raise EVcsChanges.Create(cTexts[TVcsChangesText.NoMergeBase].Fmt([ARef]));
    end;
    mRef := Trim(mOutput[0]);
  end;
  // Ohne HEAD vergleicht git diff mit dem Arbeitsverzeichnis, Index eingeschlossen.
  if AIncludeUncommitted then
  begin
    mRange := [mRef];
  end
  else
  begin
    mRange := [mRef, 'HEAD'];
  end;
  FFiles := nil;
  for mPath in TChangedFiles.ParseNameStatus(Git(['diff', '--name-status', '-M', '--no-color'] + mRange)) do
  begin
    FFiles := FFiles + [TChangedFiles.FullPath(FRepoRoot, mPath)];
  end;
  FLines := nil;
  if AWithLines then
  begin
    FLines := TChangedFiles.ParseHunks(Git(['diff', '-U0', '-M', '--no-color', '--no-ext-diff'] + mRange));
  end;
  if AIncludeUncommitted then
  begin
    for mPath in Git(['ls-files', '--others', '--exclude-standard', '--full-name', ':/']) do
    begin
      if Trim(mPath) <> '' then
      begin
        AddWholeFile(TChangedFiles.UnquotePath(Trim(mPath)));
      end;
    end;
  end;
end;

{ TSvnChanges }

constructor TSvnChanges.Create(const AProcess: ICompilerProcess; const AWorkingDir: string;
  const AWorkingCopy: TAtlasVcsWorkingCopy; const ASvn: string; ATimeoutMs: Cardinal);
var
  mRunner: IAtlasVcsRunner;
begin
  inherited Create(AProcess, AWorkingDir);
  FSvn := ASvn;
  if FSvn = '' then
  begin
    FSvn := 'svn';
  end;
  // Kommandozeile: kein Fenster, der Hauptthread darf warten.
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  FVcs := TAtlasVersionControl.ForWorkingCopy(AWorkingCopy, mRunner, ASvn, ATimeoutMs);
end;

function TSvnChanges.Name: string;
begin
  Result := 'SVN';
end;

function TSvnChanges.Svn(const AArguments: TArray<string>): TArray<string>;
var
  mExitCode: Integer;
begin
  // Der von Detect gefundene Pfad, auch wenn svn nicht in PATH liegt (z. B. TortoiseSVN).
  Result := Run(FSvn, ['--non-interactive'] + AArguments, True, mExitCode);
end;

// Geänderte Dateien zum Prüfen: A, M und R; gelöschte und fehlende Dateien gibt es nicht zu prüfen.
function CheckedPaths(const AChanges: TArray<TAtlasVcsChange>): TArray<string>;
var
  mChange: TAtlasVcsChange;
begin
  Result := nil;
  for mChange in AChanges do
  begin
    if mChange.Kind in [TAtlasVcsChangeKind.Modified, TAtlasVcsChangeKind.Added, TAtlasVcsChangeKind.Replaced] then
    begin
      Result := Result + [mChange.Path];
    end;
  end;
end;

// Unversionierte Dateien relativ zu ARoot.
function UntrackedPaths(const ARoot: string; const AChanges: TArray<TAtlasVcsChange>): TArray<string>;
var
  mChange: TAtlasVcsChange;
  mRelative: string;
begin
  Result := nil;
  for mChange in AChanges do
  begin
    if (mChange.Kind = TAtlasVcsChangeKind.Untracked) and
      TAtlasVcsDetection.RelativePath(ARoot, mChange.Path, mRelative) then
    begin
      Result := Result + [mRelative];
    end;
  end;
end;

procedure TSvnChanges.Load(const ARef: string; AMergeBase, ADefaultBase, AIncludeUncommitted, AWithLines: Boolean);
var
  mRange: TArray<string>;
  mChanges: TArray<TAtlasVcsChange>;
  mPath: string;
  mOutcome: TAtlasVcsOutcome;
begin
  FRepoRoot := FVcs.WorkingCopy.Root;
  // Pfade relativ zur Wurzel: svn läuft dort.
  FWorkingDir := FRepoRoot;
  FFiles := nil;
  FLines := nil;
  mChanges := nil;
  if ADefaultBase or AIncludeUncommitted then
  begin
    mOutcome := FVcs.Changes(mChanges);
    if mOutcome <> TAtlasVcsOutcome.Ok then
    begin
      raise EVcsChanges.Create(cTexts[TVcsChangesText.SvnStatus].Fmt([AtlasVcsOutcomeName(mOutcome)]));
    end;
  end;
  // SVN kennt keine Merge-Base: --changed ohne eigene Basis vergleicht mit BASE.
  mRange := nil;
  if ADefaultBase then
  begin
    FFiles := CheckedPaths(mChanges);
  end
  else
  begin
    mRange := TArray<string>.Create('-r', ARef);
    for mPath in TChangedFiles.ParseSvnSummarize(Svn(TArray<string>.Create('diff', '--summarize') + mRange)) do
    begin
      FFiles := FFiles + [TChangedFiles.FullPath(FRepoRoot, mPath)];
    end;
  end;
  if AWithLines then
  begin
    FLines := TChangedFiles.ParseSvnDiff(Svn(TArray<string>.Create('diff', '--internal-diff') + mRange));
  end;
  if AIncludeUncommitted then
  begin
    for mPath in UntrackedPaths(FRepoRoot, mChanges) do
    begin
      AddWholeFile(mPath);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.VcsChanges', cTexts);

end.
