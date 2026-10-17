unit Shell.VcsChanges.Tests;

// Tests für geänderte Dateien und Zeilen aus Git (#157) und SVN (#276) nach
// vcs.provider (#571) (#415): Detect mit Ordnern, die .git bzw. .svn enthalten,
// und Load mit nachgestelltem Prozess, der feste git- bzw. svn-Ausgaben liefert.
// Es läuft nie ein echtes git oder svn.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellVcsChangesTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DetectOffRaises;
    [Test]
    procedure DetectFindsGitInParentFolder;
    [Test]
    procedure DetectAcceptsGitFile;
    [Test]
    procedure DetectPrefersGitInSameFolder;
    [Test]
    procedure DetectNearestWorkingCopyWins;
    [Test]
    procedure DetectProviderRestrictsKind;
    [Test]
    procedure DetectWithoutWorkingCopyRaises;
    [Test]
    procedure DetectSvnWithoutSvnRaises;
    [Test]
    procedure GitComparesWithHead;
    [Test]
    procedure GitUsesMergeBase;
    [Test]
    procedure GitWithUncommittedAndLines;
    [Test]
    procedure GitWithoutRepositoryRaises;
    [Test]
    procedure GitFailingCommandRaises;
    [Test]
    procedure GitWithoutMergeBaseRaises;
    [Test]
    procedure SvnComparesWithRevision;
    [Test]
    procedure SvnUsesDetectedPath;
    [Test]
    procedure FindProgramKeepsUnknownName;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Shell.VcsChanges;

type
  /// <summary>Prozess mit festen Antworten je Argumentliste (ohne Programm, durch Leerzeichen getrennt);
  /// unbekannte Aufrufe enden mit 0 ohne Ausgabe.</summary>
  TFakeProcess = class(TInterfacedObject, ICompilerProcess)
  private
    FOutputs: TDictionary<string, TArray<string>>;
    FExitCodes: TDictionary<string, Integer>;
    FCalls: TList<string>;
    FWorkingDirs: TList<string>;
    FExecutables: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Answer(const AArguments: string; const AOutput: TArray<string>);
    procedure Fail(const AArguments: string; AExitCode: Integer);
    function Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
    procedure Cancel;
    /// <summary>"git -c core.quotepath=on rev-parse --show-toplevel" usw.; Programm ohne Pfad und .exe.</summary>
    property Calls: TList<string> read FCalls;
    property WorkingDirs: TList<string> read FWorkingDirs;
    /// <summary>Programm genau wie übergeben, mit Pfad.</summary>
    property Executables: TList<string> read FExecutables;
  end;

const
  GitPrefix = '-c core.quotepath=on ';

constructor TFakeProcess.Create;
begin
  inherited Create;
  FOutputs := TDictionary<string, TArray<string>>.Create;
  FExitCodes := TDictionary<string, Integer>.Create;
  FCalls := TList<string>.Create;
  FWorkingDirs := TList<string>.Create;
  FExecutables := TList<string>.Create;
end;

destructor TFakeProcess.Destroy;
begin
  FExecutables.Free;
  FWorkingDirs.Free;
  FCalls.Free;
  FExitCodes.Free;
  FOutputs.Free;
  inherited;
end;

procedure TFakeProcess.Answer(const AArguments: string; const AOutput: TArray<string>);
begin
  FOutputs.AddOrSetValue(AArguments, AOutput);
end;

procedure TFakeProcess.Fail(const AArguments: string; AExitCode: Integer);
begin
  FExitCodes.AddOrSetValue(AArguments, AExitCode);
end;

function TFakeProcess.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  Arguments: string;
  Output: TArray<string>;
  Line: string;
begin
  Arguments := string.Join(' ', ARequest.Arguments);
  FCalls.Add(ChangeFileExt(ExtractFileName(ARequest.Executable), '') + ' ' + Arguments);
  FWorkingDirs.Add(ARequest.WorkingDir);
  FExecutables.Add(ARequest.Executable);
  Result := 0;
  if FExitCodes.ContainsKey(Arguments) then
    Result := FExitCodes[Arguments];
  Output := nil;
  if FOutputs.ContainsKey(Arguments) then
    Output := FOutputs[Arguments];
  for Line in Output do
    AOnLine(Line);
end;

procedure TFakeProcess.Cancel;
begin
end;

/// <summary>Als Funktionsergebnis: nie ein frisches Objekt an einen const-Interface-Parameter.</summary>
function NoProcess: ICompilerProcess;
begin
  Result := TFakeProcess.Create;
end;

/// <summary>Meldung von EVcsChanges aus Detect; '' ohne Ausnahme.</summary>
function DetectError(const AFolder, AProvider: string): string;
var
  Changes: TVcsChanges;
begin
  Result := '';
  try
    Changes := TVcsChanges.Detect(NoProcess, AFolder, AProvider);
    Changes.Free;
  except
    on E: EVcsChanges do
      Result := E.Message;
  end;
end;

/// <summary>Name der erkannten Versionsverwaltung ("Git", "SVN") und ihre Klasse; '' bei Ausnahme.</summary>
function DetectedName(const AFolder, AProvider: string): string;
var
  Changes: TVcsChanges;
begin
  Result := '';
  try
    Changes := TVcsChanges.Detect(NoProcess, AFolder, AProvider);
    try
      Result := Changes.Name + ':' + Changes.ClassName;
    finally
      Changes.Free;
    end;
  except
    on E: EVcsChanges do
      Result := '';
  end;
end;

/// <summary>Meldung von EVcsChanges aus Load; '' ohne Ausnahme.</summary>
function LoadError(const AChanges: TVcsChanges; const ARef: string; AMergeBase: Boolean): string;
begin
  Result := '';
  try
    AChanges.Load(ARef, AMergeBase, False, False, False);
  except
    on E: EVcsChanges do
      Result := E.Message;
  end;
end;

function InFolder(const ARoot, ARelative: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ARoot) + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
end;

{ TShellVcsChangesTests }

procedure TShellVcsChangesTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-ShellVcs-' + IntToStr(Random(MaxInt)));
  ForceDirectories(TPath.Combine(FFolder, 'Sub'));
end;

procedure TShellVcsChangesTests.TearDown;
begin
  TAtlasVcsTools.Forget;
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

procedure TShellVcsChangesTests.DetectOffRaises;
begin
  ForceDirectories(TPath.Combine(FFolder, '.git'));
  Assert.AreEqual('Versionsverwaltung abgeschaltet (vcs.provider = off)', DetectError(FFolder, 'off'));
end;

procedure TShellVcsChangesTests.DetectFindsGitInParentFolder;
var
  Changes: TVcsChanges;
begin
  ForceDirectories(TPath.Combine(FFolder, '.git'));
  Assert.AreEqual('Git:TGitChanges', DetectedName(TPath.Combine(FFolder, 'Sub'), 'auto'));
  Assert.AreEqual('Git:TGitChanges', DetectedName(TPath.Combine(FFolder, 'Sub'), 'git'));
  // Ohne vcs.provider wie auto.
  Changes := TVcsChanges.Detect(NoProcess, TPath.Combine(FFolder, 'Sub'));
  try
    Assert.IsTrue(Changes is TGitChanges);
  finally
    Changes.Free;
  end;
end;

procedure TShellVcsChangesTests.DetectAcceptsGitFile;
begin
  // In Worktrees und Submodulen ist .git eine Datei.
  TFile.WriteAllText(TPath.Combine(FFolder, '.git'), 'gitdir: ../haupt/.git/worktrees/x');
  Assert.AreEqual('Git:TGitChanges', DetectedName(TPath.Combine(FFolder, 'Sub'), 'auto'));
end;

procedure TShellVcsChangesTests.DetectPrefersGitInSameFolder;
begin
  TAtlasVcsTools.Preset(TAtlasVcsKind.Svn, TPath.Combine(FFolder, 'svn.exe'));
  ForceDirectories(TPath.Combine(FFolder, '.git'));
  ForceDirectories(TPath.Combine(FFolder, '.svn'));
  Assert.AreEqual('Git:TGitChanges', DetectedName(FFolder, 'auto'));
end;

procedure TShellVcsChangesTests.DetectNearestWorkingCopyWins;
begin
  TAtlasVcsTools.Preset(TAtlasVcsKind.Svn, TPath.Combine(FFolder, 'svn.exe'));
  ForceDirectories(TPath.Combine(FFolder, '.git'));
  ForceDirectories(TPath.Combine(FFolder, TPath.Combine('Sub', '.svn')));
  Assert.AreEqual('SVN:TSvnChanges', DetectedName(TPath.Combine(FFolder, 'Sub'), 'auto'));
  Assert.AreEqual('Git:TGitChanges', DetectedName(FFolder, 'auto'));
end;

procedure TShellVcsChangesTests.DetectProviderRestrictsKind;
begin
  TAtlasVcsTools.Preset(TAtlasVcsKind.Svn, TPath.Combine(FFolder, 'svn.exe'));
  ForceDirectories(TPath.Combine(FFolder, '.svn'));
  ForceDirectories(TPath.Combine(FFolder, TPath.Combine('Sub', '.git')));
  // Mit vcs.provider = svn zählt die nähere Git-Arbeitskopie nicht.
  Assert.AreEqual('SVN:TSvnChanges', DetectedName(TPath.Combine(FFolder, 'Sub'), 'svn'));
  Assert.AreEqual('Git:TGitChanges', DetectedName(TPath.Combine(FFolder, 'Sub'), 'git'));
  // .svn als Datei zählt nicht.
  TDirectory.Delete(TPath.Combine(FFolder, '.svn'), True);
  TFile.WriteAllText(TPath.Combine(FFolder, '.svn'), 'keine Arbeitskopie');
  Assert.Contains(DetectError(TPath.Combine(FFolder, 'Sub'), 'svn'), 'vcs.provider = svn');
end;

procedure TShellVcsChangesTests.DetectWithoutWorkingCopyRaises;
begin
  // Setzt voraus, dass der Temp-Ordner selbst in keiner Arbeitskopie liegt.
  Assert.Contains(DetectError(FFolder, 'auto'), 'weder in einem Git-Repository noch in einer SVN-Arbeitskopie');
  Assert.Contains(DetectError(FFolder, 'git'), 'in keiner Arbeitskopie für vcs.provider = git');
  Assert.Contains(DetectError(FFolder, 'svn'), 'in keiner Arbeitskopie für vcs.provider = svn');
end;

procedure TShellVcsChangesTests.DetectSvnWithoutSvnRaises;
begin
  TAtlasVcsTools.Preset(TAtlasVcsKind.Svn, '');
  ForceDirectories(TPath.Combine(FFolder, '.svn'));
  Assert.Contains(DetectError(FFolder, 'auto'), 'svn ist nicht installiert');
  Assert.Contains(DetectError(FFolder, 'auto'), FFolder);
end;

procedure TShellVcsChangesTests.GitComparesWithHead;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Changes: TGitChanges;
begin
  Process := TFakeProcess.Create;
  Keep := Process;
  Process.Answer(GitPrefix + 'rev-parse --show-toplevel', [StringReplace(FFolder, '\', '/', [rfReplaceAll]) + '/']);
  Process.Answer(GitPrefix + 'diff --name-status -M --no-color main HEAD',
    ['M'#9'Src/A.pas', 'D'#9'Src/Alt.pas', 'R087'#9'Src/B.pas'#9'Src/C.pas', 'A'#9'Neu.pas', 'T'#9'Typ.pas']);
  Changes := TGitChanges.Create(Keep, TPath.Combine(FFolder, 'Sub'));
  try
    Changes.Load('main', False, False, False, False);
    Assert.AreEqual('Git', Changes.Name);
    Assert.AreEqual(FFolder, Changes.RepoRoot);
    Assert.AreEqual(4, Integer(Length(Changes.Files)));
    Assert.AreEqual(InFolder(FFolder, 'Src/A.pas'), Changes.Files[0]);
    // Umbenannt: der neue Name; gelöscht: nicht dabei.
    Assert.AreEqual(InFolder(FFolder, 'Src/C.pas'), Changes.Files[1]);
    Assert.AreEqual(InFolder(FFolder, 'Neu.pas'), Changes.Files[2]);
    Assert.AreEqual(InFolder(FFolder, 'Typ.pas'), Changes.Files[3]);
    Assert.AreEqual(0, Integer(Length(Changes.Lines)));
    Assert.AreEqual(2, Process.Calls.Count);
    Assert.AreEqual('git ' + GitPrefix + 'rev-parse --show-toplevel', Process.Calls[0]);
    Assert.AreEqual('git ' + GitPrefix + 'diff --name-status -M --no-color main HEAD', Process.Calls[1]);
    // git läuft im übergebenen Ordner, nicht in der Wurzel.
    Assert.AreEqual(TPath.Combine(FFolder, 'Sub'), Process.WorkingDirs[1]);
  finally
    Changes.Free;
  end;
end;

procedure TShellVcsChangesTests.GitUsesMergeBase;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Changes: TGitChanges;
begin
  Process := TFakeProcess.Create;
  Keep := Process;
  Process.Answer(GitPrefix + 'rev-parse --show-toplevel', [FFolder]);
  Process.Answer(GitPrefix + 'merge-base main HEAD', ['  abc123  ']);
  Process.Answer(GitPrefix + 'diff --name-status -M --no-color abc123 HEAD', ['M'#9'A.pas']);
  Changes := TGitChanges.Create(Keep, FFolder);
  try
    Changes.Load('main', True, True, False, False);
    Assert.AreEqual(3, Process.Calls.Count);
    Assert.AreEqual('git ' + GitPrefix + 'merge-base main HEAD', Process.Calls[1]);
    Assert.AreEqual('git ' + GitPrefix + 'diff --name-status -M --no-color abc123 HEAD', Process.Calls[2]);
    Assert.AreEqual(1, Integer(Length(Changes.Files)));
    Assert.AreEqual(InFolder(FFolder, 'A.pas'), Changes.Files[0]);
  finally
    Changes.Free;
  end;
end;

procedure TShellVcsChangesTests.GitWithUncommittedAndLines;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Changes: TGitChanges;
  Lines: TChangedLines;
begin
  Process := TFakeProcess.Create;
  Keep := Process;
  Process.Answer(GitPrefix + 'rev-parse --show-toplevel', [FFolder]);
  Process.Answer(GitPrefix + 'diff --name-status -M --no-color HEAD', ['M'#9'Src/A.pas', 'D'#9'Weg.pas']);
  Process.Answer(GitPrefix + 'diff -U0 -M --no-color --no-ext-diff HEAD',
    ['diff --git a/Src/A.pas b/Src/A.pas', '--- a/Src/A.pas', '+++ b/Src/A.pas', '@@ -3,0 +4,2 @@', '+x', '+y',
    '@@ -10 +12 @@', '-alt', '+neu', '@@ -20,2 +21,0 @@', '-weg', '-weg',
    '--- a/Weg.pas', '+++ /dev/null', '@@ -1 +0,0 @@', '-weg']);
  Process.Answer(GitPrefix + 'ls-files --others --exclude-standard --full-name :/', ['Neu/X.pas', '', '  ']);
  Changes := TGitChanges.Create(Keep, FFolder);
  try
    Changes.Load('HEAD', False, False, True, True);
    Assert.AreEqual(4, Process.Calls.Count);
    // Ohne HEAD am Ende: Index und Arbeitsverzeichnis gehören dazu.
    Assert.AreEqual('git ' + GitPrefix + 'diff --name-status -M --no-color HEAD', Process.Calls[1]);
    Assert.AreEqual(2, Integer(Length(Changes.Files)));
    Assert.AreEqual(InFolder(FFolder, 'Src/A.pas'), Changes.Files[0]);
    Assert.AreEqual(InFolder(FFolder, 'Neu/X.pas'), Changes.Files[1]);
    Assert.AreEqual(2, Integer(Length(Changes.Lines)));
    Lines := Changes.Lines[0];
    Assert.AreEqual('Src/A.pas', Lines.Path);
    // Nullbasiert; reine Löschungen ergeben keinen Bereich.
    Assert.AreEqual(2, Integer(Length(Lines.Spans)));
    Assert.AreEqual(3, Lines.Spans[0].First);
    Assert.AreEqual(4, Lines.Spans[0].Last);
    Assert.AreEqual(11, Lines.Spans[1].First);
    Assert.AreEqual(11, Lines.Spans[1].Last);
    // Neue Dateien gelten als vollständig geändert.
    Lines := Changes.Lines[1];
    Assert.AreEqual('Neu/X.pas', Lines.Path);
    Assert.AreEqual(1, Integer(Length(Lines.Spans)));
    Assert.AreEqual(0, Lines.Spans[0].First);
    Assert.AreEqual(MaxInt, Lines.Spans[0].Last);
  finally
    Changes.Free;
  end;
  Lines := Default(TChangedLines);
end;

procedure TShellVcsChangesTests.GitWithoutRepositoryRaises;
var
  Changes: TGitChanges;
begin
  Changes := TGitChanges.Create(NoProcess, FFolder);
  try
    Assert.AreEqual('Kein Git-Repository', LoadError(Changes, 'main', False));
  finally
    Changes.Free;
  end;
end;

procedure TShellVcsChangesTests.GitFailingCommandRaises;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Changes: TGitChanges;
  Message: string;
begin
  Process := TFakeProcess.Create;
  Keep := Process;
  Process.Answer(GitPrefix + 'rev-parse --show-toplevel', ['fatal: not a git repository']);
  Process.Fail(GitPrefix + 'rev-parse --show-toplevel', 128);
  Changes := TGitChanges.Create(Keep, FFolder);
  try
    Message := LoadError(Changes, 'main', False);
    Assert.Contains(Message, 'Exit-Code 128');
    Assert.Contains(Message, 'fatal: not a git repository');
    Assert.AreEqual(1, Process.Calls.Count);
  finally
    Changes.Free;
  end;
end;

procedure TShellVcsChangesTests.GitWithoutMergeBaseRaises;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Changes: TGitChanges;
begin
  Process := TFakeProcess.Create;
  Keep := Process;
  Process.Answer(GitPrefix + 'rev-parse --show-toplevel', [FFolder]);
  Changes := TGitChanges.Create(Keep, FFolder);
  try
    Assert.AreEqual('Keine Merge-Base mit fremd', LoadError(Changes, 'fremd', True));
  finally
    Changes.Free;
  end;
end;

procedure TShellVcsChangesTests.SvnComparesWithRevision;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Changes: TSvnChanges;
  WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Process := TFakeProcess.Create;
  Keep := Process;
  Process.Answer('--non-interactive diff --summarize -r 123',
    ['M       Src/A.pas', 'D       Src/Alt.pas', 'A       Neu.pas', ' M      Eigenschaft.pas']);
  Process.Answer('--non-interactive diff --internal-diff -r 123',
    ['Index: Src/A.pas', '===================================================================',
    '--- Src/A.pas'#9'(revision 123)', '+++ Src/A.pas'#9'(working copy)', '@@ -1,3 +1,4 @@', ' a', '+b', '+c', ' d']);
  WorkingCopy.Kind := TAtlasVcsKind.Svn;
  WorkingCopy.Root := FFolder;
  Changes := TSvnChanges.Create(Keep, TPath.Combine(FFolder, 'Sub'), WorkingCopy, 'svn');
  try
    Changes.Load('123', False, False, False, True);
    Assert.AreEqual('SVN', Changes.Name);
    Assert.AreEqual(FFolder, Changes.RepoRoot);
    Assert.AreEqual(2, Process.Calls.Count);
    Assert.AreEqual('svn --non-interactive diff --summarize -r 123', Process.Calls[0]);
    Assert.AreEqual('svn --non-interactive diff --internal-diff -r 123', Process.Calls[1]);
    // svn läuft in der Wurzel der Arbeitskopie: Pfade sind relativ dazu.
    Assert.AreEqual(FFolder, Process.WorkingDirs[0]);
    Assert.AreEqual(2, Integer(Length(Changes.Files)));
    Assert.AreEqual(InFolder(FFolder, 'Src/A.pas'), Changes.Files[0]);
    Assert.AreEqual(InFolder(FFolder, 'Neu.pas'), Changes.Files[1]);
    Assert.AreEqual(1, Integer(Length(Changes.Lines)));
    Assert.AreEqual('Src/A.pas', Changes.Lines[0].Path);
    Assert.AreEqual(1, Integer(Length(Changes.Lines[0].Spans)));
    Assert.AreEqual(1, Changes.Lines[0].Spans[0].First);
    Assert.AreEqual(2, Changes.Lines[0].Spans[0].Last);
  finally
    Changes.Free;
  end;
  WorkingCopy := Default(TAtlasVcsWorkingCopy);
end;

procedure TShellVcsChangesTests.SvnUsesDetectedPath;
var
  Process: TFakeProcess;
  Keep: ICompilerProcess;
  Changes: TSvnChanges;
  WorkingCopy: TAtlasVcsWorkingCopy;
  Svn: string;
begin
  // svn liegt nicht in PATH, Detect hat es z. B. bei TortoiseSVN gefunden.
  Svn := TPath.Combine(FFolder, 'atlas-svn-4711.exe');
  Process := TFakeProcess.Create;
  Keep := Process;
  Process.Answer('--non-interactive diff --summarize -r 7', ['M       A.pas']);
  WorkingCopy.Kind := TAtlasVcsKind.Svn;
  WorkingCopy.Root := FFolder;
  Changes := TSvnChanges.Create(Keep, FFolder, WorkingCopy, Svn);
  try
    Changes.Load('7', False, False, False, False);
    Assert.AreEqual(1, Process.Calls.Count);
    Assert.AreEqual(Svn, Process.Executables[0]);
    Assert.AreEqual('atlas-svn-4711 --non-interactive diff --summarize -r 7', Process.Calls[0]);
  finally
    Changes.Free;
  end;
  WorkingCopy := Default(TAtlasVcsWorkingCopy);
end;

procedure TShellVcsChangesTests.FindProgramKeepsUnknownName;
begin
  Assert.AreEqual('atlas-gibt-es-nicht-4711', TVcsChanges.FindProgram('atlas-gibt-es-nicht-4711'));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellVcsChangesTests);

end.
