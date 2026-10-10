unit Shell.GitChanges;

// Host-Rolle Shell: geänderte Dateien und Zeilen aus Git für --changed und
// --diff (#157). Startet git über ICompilerProcess und wertet die Ausgabe mit
// TChangedFiles aus. Nur Git; SVN folgt in #276.
//
//   git rev-parse --show-toplevel              Wurzel des Repositorys
//   git merge-base <Basis> HEAD                bei --changed
//   git diff --name-status -M <Ref> [HEAD]     geänderte Dateien; ohne HEAD mit
//                                              Index und Arbeitsverzeichnis
//   git ls-files --others --exclude-standard   neue Dateien bei --include-uncommitted
//   git diff -U0 <Ref> [HEAD]                  geänderte Zeilen

interface

uses
  System.SysUtils,
  Argus.Common.Compiler.Contract,
  Argus.Common.Rules.ChangedFiles;

type
  EGitChanges = class(Exception);

  TGitChanges = class
  private
    FProcess: ICompilerProcess;
    FWorkingDir: string;
    FRepoRoot: string;
    FFiles: TArray<string>;
    FLines: TArray<TChangedLines>;
    function Git(const AArguments: TArray<string>): TArray<string>;
  public
    /// <summary>git.exe aus PATH; 'git', wenn nicht gefunden.</summary>
    class function FindGit: string; static;
    constructor Create(const AProcess: ICompilerProcess; const AWorkingDir: string);
    /// <summary>Ermittelt die Änderungen gegenüber ARef bzw. der Merge-Base von ARef und HEAD.</summary>
    procedure Load(const ARef: string; AMergeBase, AIncludeUncommitted, AWithLines: Boolean);
    property RepoRoot: string read FRepoRoot;
    /// <summary>Geänderte Dateien als vollständige Pfade.</summary>
    property Files: TArray<string> read FFiles;
    property Lines: TArray<TChangedLines> read FLines;
  end;

implementation

uses
  System.IOUtils;

{ TGitChanges }

constructor TGitChanges.Create(const AProcess: ICompilerProcess; const AWorkingDir: string);
begin
  inherited Create;
  FProcess := AProcess;
  FWorkingDir := AWorkingDir;
end;

class function TGitChanges.FindGit: string;
var
  Dir: string;
begin
  // Der Prozessläufer übergibt den Programmnamen direkt an CreateProcess, das PATH nicht durchsucht.
  for Dir in GetEnvironmentVariable('PATH').Split([PathSep]) do
    if (Dir <> '') and TFile.Exists(TPath.Combine(Dir.Trim(['"']), 'git.exe')) then
      Exit(TPath.Combine(Dir.Trim(['"']), 'git.exe'));
  Result := 'git';
end;

function TGitChanges.Git(const AArguments: TArray<string>): TArray<string>;
var
  Request: TCompilerRequest;
  Output: TArray<string>;
  ExitCode: Integer;
begin
  Request.Executable := FindGit;
  // Pfade mit Sonderzeichen kommen als Oktalfolgen (core.quotepath) und damit
  // unabhängig von der Codepage, in der der Prozessläufer liest.
  Request.Arguments := ['-c', 'core.quotepath=on'] + AArguments;
  Request.WorkingDir := FWorkingDir;
  Output := nil;
  ExitCode := FProcess.Run(Request,
    procedure(const ALine: string)
    begin
      Output := Output + [ALine];
    end);
  if ExitCode <> 0 then
    raise EGitChanges.CreateFmt('git %s ist fehlgeschlagen (Exit-Code %d): %s',
      [string.Join(' ', AArguments), ExitCode, string.Join(' ', Output)]);
  Result := Output;
end;

procedure TGitChanges.Load(const ARef: string; AMergeBase, AIncludeUncommitted, AWithLines: Boolean);
var
  Output, Range: TArray<string>;
  Ref, Path: string;
  Untracked: TChangedLines;
  Whole: TLineSpan;
begin
  Output := Git(['rev-parse', '--show-toplevel']);
  if Length(Output) = 0 then
    raise EGitChanges.Create('Kein Git-Repository');
  FRepoRoot := ExcludeTrailingPathDelimiter(StringReplace(Trim(Output[0]), '/', PathDelim, [rfReplaceAll]));
  Ref := ARef;
  if AMergeBase then
  begin
    Output := Git(['merge-base', ARef, 'HEAD']);
    if Length(Output) = 0 then
      raise EGitChanges.CreateFmt('Keine Merge-Base mit %s', [ARef]);
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
  begin
    // Neue, noch nicht versionierte Dateien gelten als vollständig geändert.
    Whole.First := 0;
    Whole.Last := MaxInt;
    for Path in Git(['ls-files', '--others', '--exclude-standard', '--full-name', ':/']) do
      if Trim(Path) <> '' then
      begin
        FFiles := FFiles + [TChangedFiles.FullPath(FRepoRoot, TChangedFiles.UnquotePath(Trim(Path)))];
        Untracked.Path := TChangedFiles.UnquotePath(Trim(Path));
        Untracked.Spans := [Whole];
        FLines := FLines + [Untracked];
      end;
  end;
end;

end.
