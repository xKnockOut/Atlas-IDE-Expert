unit Shell.Linter.Tests;

// Tests für den Linter-Modus ohne Editor (#95) (#415): TLinterShell.Run mit
// Optionen aus TCommandLineOptions.Parse auf Dateien in einem Temp-Ordner.
// Exit-Codes (0 sauber, 1 Treffer, 3 Aufruf- oder Lesefehler), Formate,
// Metriken (#66), TODOs (#68), Unterdrückungen (#147) und Baseline (#97),
// dazu der Lauf mit und ohne Symbolindex (#1112). Index-Caches liegen neben
// dem Testprogramm (--index-cache), nie bei denen des Benutzers. Der Ordner
// bleibt zwischen den Läufen: Der Index der erreichbaren RTL (rund 1500 Units)
// kostete in einem leeren Cache je Aufbau gut drei Minuten, im Testlauf zweimal
// (Aufwärmen und Test). Ein neues Cache-Format verwirft er selbst.
// Jede Ausgabe geht in eine Datei (--output), nie auf stdout.
// TLinterShell.ClearCache bleibt ungetestet: Es löscht die echten Index-Caches
// des Benutzers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellLinterTests = class
  private
    FFolder: string;
    FOutput: string;
    function Path(const AName: string): string;
    function Run(const AArgs: TArray<string>): Integer;
    function OutputText: string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MissingTargetFails;
    [Test]
    procedure ExclusiveModesFail;
    [Test]
    procedure MissingSourceRootFails;
    [Test]
    procedure MissingBaselineFails;
    [Test]
    procedure CleanFileGivesZero;
    [Test]
    procedure SyntaxErrorGivesOne;
    [Test]
    procedure FailOnNeverGivesZero;
    [Test]
    procedure FolderAsSarif;
    [Test]
    procedure TextFormatNamesFile;
    [Test]
    procedure TodosAsJson;
    [Test]
    procedure MetricsAsMarkdownAndJson;
    [Test]
    procedure ArchitectureAsMarkdownAndHtml;
    [Test]
    procedure ArchitectureCompareFailsOnNewCycle;
    /// <summary>--hotspots (#1354): ohne Versionsverwaltung Exit-Code 3, mit Git-Repository der Bericht.</summary>
    [Test]
    procedure HotspotsNeedVersionControl;
    [Test]
    procedure SuppressionStatsGiveZero;
    [Test]
    procedure UpdatedBaselineHidesFindings;
    [Test]
    procedure DefaultBaselineBesideConfiguration;
    /// <summary>Mit Index kennt legacy-stack-queue TObjectStack aus einer anderen Unit, mit --no-index nicht.
    /// </summary>
    [Test]
    procedure IndexKnowsTypesOfOtherUnits;
    /// <summary>#1321 (Minimalfall F14): {$IF CompilerVersion} in einer Zeile ergibt keinen Syntaxfehler, auch
    /// ohne installiertes Delphi (Version aus ProjectVersion) und ohne .dproj.</summary>
    [Test]
    procedure InlineCompilerVersionWithoutInstallation;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Core.Vcs.Contract,
  Shell.Platform,
  Shell.VcsChanges,
  Shell.CommandLine,
  Shell.Linter,
  Shell.Workspace;

const
  CleanUnit = 'unit Gut;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10;
  BrokenUnit = 'unit Kaputt;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10 +
    '  if then;'#13#10'end;'#13#10'end.'#13#10;
  TodoUnit = 'unit Offen;'#13#10'interface'#13#10'implementation'#13#10'// TODO: Aufräumen'#13#10'end.'#13#10;

{ TShellLinterTests }

procedure TShellLinterTests.WarmUpFirstUse;
begin
  Setup;
  try
    MissingTargetFails;
  finally
    TearDown;
  end;
  // Der erste Symbolindex im Prozess legt bleibende Strukturen und einen Thread des Pools an (#1112).
  Setup;
  try
    IndexKnowsTypesOfOtherUnits;
  finally
    TearDown;
  end;
end;

procedure TShellLinterTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-ShellLinter-' + IntToStr(Random(MaxInt)));
  ForceDirectories(TPath.Combine(FFolder, 'Src'));
  FOutput := TPath.Combine(FFolder, 'ergebnis.txt');
  TFile.WriteAllText(Path('Src/Gut.pas'), CleanUnit);
  TFile.WriteAllText(Path('Src/Kaputt.pas'), BrokenUnit);
end;

procedure TShellLinterTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  // Der Leckmonitor misst den Saldo von Setup und TearDown; Run merkt sich den Ordner in den Encoding-Vorgaben.
  TFileEncodingDefaults.Clear;
  // Ebenso die Ordnerlisten der .pas-/.dcu-Dateien: je Testordner ein Eintrag (IndexKnowsTypesOfOtherUnits).
  TShellWorkspace.ClearSharedListings;
  FFolder := '';
  FOutput := '';
end;

function TShellLinterTests.Path(const AName: string): string;
begin
  Result := TPath.Combine(FFolder, StringReplace(AName, '/', PathDelim, [rfReplaceAll]));
end;

function TShellLinterTests.Run(const AArgs: TArray<string>): Integer;
begin
  if TFile.Exists(FOutput) then
    TFile.Delete(FOutput);
  Result := TLinterShell.Run(TCommandLineOptions.Parse(AArgs + ['--output', FOutput, '--index-cache',
    TPath.Combine(ExtractFilePath(ParamStr(0)), 'TestIndexCache')]));
end;

function TShellLinterTests.OutputText: string;
begin
  Result := '';
  if TFile.Exists(FOutput) then
    Result := TFile.ReadAllText(FOutput, TEncoding.UTF8);
end;

procedure TShellLinterTests.MissingTargetFails;
begin
  Assert.AreEqual(3, Run(['--check', Path('Src/Fehlt.pas')]));
  Assert.IsFalse(TFile.Exists(FOutput));
end;

procedure TShellLinterTests.ExclusiveModesFail;
begin
  Assert.AreEqual(3, Run(['--check', Path('Src/Gut.pas'), '--metrics', '--format', 'sarif']));
  Assert.AreEqual(3, Run(['--check', Path('Src/Gut.pas'), '--todos', '--format', 'sarif']));
  Assert.AreEqual(3, Run(['--check', Path('Src/Gut.pas'), '--todos', '--metrics']));
  Assert.IsFalse(TFile.Exists(FOutput));
end;

procedure TShellLinterTests.MissingSourceRootFails;
begin
  Assert.AreEqual(3, Run(['--check', Path('Src/Gut.pas'), '--source-root', Path('Fehlt')]));
  Assert.IsFalse(TFile.Exists(FOutput));
end;

procedure TShellLinterTests.MissingBaselineFails;
begin
  Assert.AreEqual(3, Run(['--check', Path('Src/Gut.pas'), '--baseline', Path('fehlt.json')]));
  Assert.IsFalse(TFile.Exists(FOutput));
end;

procedure TShellLinterTests.CleanFileGivesZero;
begin
  Assert.AreEqual(0, Run(['--check', Path('Src/Gut.pas'), '--format', 'json']));
  Assert.IsTrue(TFile.Exists(FOutput));
  Assert.DoesNotContain(OutputText, 'Kaputt.pas');
end;

procedure TShellLinterTests.SyntaxErrorGivesOne;
begin
  Assert.AreEqual(1, Run(['--check', Path('Src/Kaputt.pas'), '--format=json']));
  Assert.Contains(OutputText, 'Kaputt.pas');
end;

procedure TShellLinterTests.FailOnNeverGivesZero;
begin
  Assert.AreEqual(0, Run(['--check', Path('Src/Kaputt.pas'), '--format', 'json', '--fail-on', 'never']));
  Assert.Contains(OutputText, 'Kaputt.pas');
end;

procedure TShellLinterTests.FolderAsSarif;
var
  Text: string;
begin
  Assert.AreEqual(1, Run(['--check', FFolder, '--format', 'sarif', '--source-root', FFolder]));
  Text := OutputText;
  Assert.Contains(Text, '"version"');
  Assert.Contains(Text, '2.1.0');
  // Pfade relativ zur Quellwurzel.
  Assert.Contains(Text, 'Src/Kaputt.pas');
  Assert.Contains(Text, 'partialFingerprints');
end;

procedure TShellLinterTests.TextFormatNamesFile;
begin
  Assert.AreEqual(1, Run(['--check', TPath.Combine(FFolder, 'Src'), '--format', 'text']));
  Assert.Contains(OutputText, 'Kaputt.pas');
  Assert.DoesNotContain(OutputText, 'Gut.pas');
end;

procedure TShellLinterTests.TodosAsJson;
begin
  TFile.WriteAllText(Path('Src/Offen.pas'), TodoUnit, TEncoding.UTF8);
  Assert.AreEqual(0, Run(['--check', TPath.Combine(FFolder, 'Src'), '--todos', '--format', 'json']));
  Assert.Contains(OutputText, 'Aufräumen');
  Assert.Contains(OutputText, 'Offen.pas');
end;

procedure TShellLinterTests.MetricsAsMarkdownAndJson;
begin
  Assert.AreEqual(0, Run(['--check', TPath.Combine(FFolder, 'Src'), '--metrics']));
  Assert.IsTrue(Trim(OutputText) <> '');
  Assert.AreEqual(0, Run(['--check', TPath.Combine(FFolder, 'Src'), '--metrics', '--format', 'json']));
  Assert.Contains(OutputText, 'Gut.pas');
end;

procedure TShellLinterTests.ArchitectureAsMarkdownAndHtml;
var
  Report: string;
begin
  // Architekturbericht (#1118): Gut verwendet Kaputt nicht; ein eigener Zyklus A ↔ B über implementation.
  TFile.WriteAllText(Path('Src/A.pas'), 'unit A;'#13#10'interface'#13#10'uses B;'#13#10'implementation'#13#10'end.');
  TFile.WriteAllText(Path('Src/B.pas'), 'unit B;'#13#10'interface'#13#10'implementation'#13#10'uses A;'#13#10'end.');
  Report := Path('Bericht/architektur.md');
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', TPath.Combine(FFolder, 'Src'),
    '--architecture', Report])));
  Assert.Contains(TFile.ReadAllText(Report, TEncoding.UTF8), '# Architektur: Src');
  Assert.Contains(TFile.ReadAllText(Report, TEncoding.UTF8), 'A → B → A');
  Report := Path('architektur.html');
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', TPath.Combine(FFolder, 'Src'),
    '--architecture', Report])));
  Assert.Contains(TFile.ReadAllText(Report, TEncoding.UTF8), '"name":"Gut"');
  Assert.AreEqual(3, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', TPath.Combine(FFolder, 'Src'),
    '--architecture', Path('architektur.pdf')])));
  Assert.AreEqual(3, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Path('Fehlt'),
    '--architecture', Report])));
  // architecture gilt nur global (settings.json): in atlas.json am falschen Ort, gemeldet und ohne Wirkung.
  TFile.WriteAllText(Path('Src/atlas.json'), '{"architecture": {"enabled": false}}');
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', TPath.Combine(FFolder, 'Src'),
    '--architecture', Report])), 'atlas.json schaltet nicht ab');
end;

procedure TShellLinterTests.HotspotsNeedVersionControl;
var
  mReport, mGit, mText: string;
  mRunner: IAtlasVcsRunner;
  mCommands: TArray<string>;
  mCommand: string;
begin
  mReport := Path('hotspots.md');
  // Der Temp-Ordner liegt in keiner Arbeitskopie: Grund auf stderr, Exit-Code 3.
  Assert.AreEqual(3, TLinterShell.Hotspots(TCommandLineOptions.Parse(['--check', TPath.Combine(FFolder, 'Src'),
    '--hotspots', mReport])));
  Assert.IsFalse(TFile.Exists(mReport));
  Assert.AreEqual(3, TLinterShell.Hotspots(TCommandLineOptions.Parse(['--check', TPath.Combine(FFolder, 'Src'),
    '--hotspots', Path('hotspots.pdf')])));
  mGit := TVcsChanges.ToolFor(TAtlasVcsKind.Git, '');
  if mGit = '' then
    Exit;
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mCommands := TArray<string>.Create('init -q', 'config user.name Atlas', 'config user.email test@example.org',
    'config commit.gpgsign false', 'add Src', 'commit -q -m Start');
  for mCommand in mCommands do
    Assert.AreEqual(0, mRunner.Run(mGit, mCommand.Split([' ']), FFolder, 60000).ExitCode, mCommand);
  Assert.AreEqual(0, TLinterShell.Hotspots(TCommandLineOptions.Parse(['--check', TPath.Combine(FFolder, 'Src'),
    '--hotspots', mReport])));
  mText := TFile.ReadAllText(mReport, TEncoding.UTF8);
  Assert.IsTrue(mText.StartsWith('# Hotspots'), mText);
  Assert.IsTrue(mText.Contains('1 Commits'), mText);
  Assert.IsTrue(mText.Contains('Kaputt'), 'geänderte Unit im Bericht');
end;

procedure TShellLinterTests.ArchitectureCompareFailsOnNewCycle;
var
  Source, Older, Newer, Second: string;
begin
  // Architekturvergleich (#1121): Stand ohne Zyklus speichern, dann kommt A ↔ B dazu.
  Source := TPath.Combine(FFolder, 'Src');
  TFile.WriteAllText(Path('Src/A.pas'), 'unit A;'#13#10'interface'#13#10'uses B;'#13#10'implementation'#13#10'end.');
  TFile.WriteAllText(Path('Src/B.pas'), 'unit B;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Older := Path('Stand/alt.json');
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Older])));
  Assert.Contains(TFile.ReadAllText(Older, TEncoding.UTF8), '"format": 2');
  // Gleicher Stand: byteweise gleiche Datei, kein Fehler.
  Second := Path('Stand/zweiter.json');
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Second, '--compare', Older, '--output', FOutput])));
  Assert.AreEqual(TFile.ReadAllText(Older, TEncoding.UTF8), TFile.ReadAllText(Second, TEncoding.UTF8));
  Assert.Contains(OutputText, 'Neue Zyklen: 0');
  TFile.WriteAllText(Path('Src/B.pas'), 'unit B;'#13#10'interface'#13#10'implementation'#13#10'uses A;'#13#10'end.');
  Newer := Path('Stand/neu.json');
  Assert.AreEqual(1, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Newer, '--compare', Older, '--output', FOutput])), 'newCycle ist die Vorgabe');
  Assert.Contains(OutputText, 'Neue Zyklen: 1');
  Assert.Contains(OutputText, 'Ergebnis: Abweichung newCycle');
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Newer, '--compare', Older, '--fail-on', 'centralGrowth,subsystemChange', '--output', FOutput])));
  Assert.AreEqual(3, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Newer, '--compare', Older, '--fail-on', 'error'])), 'unbekannte Abweichung');
  Assert.AreEqual(3, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Newer, '--compare', Path('fehlt.json')])), 'Stand fehlt');
  // architecture.failOn aus atlas.json; Bericht mit architecture.baseline bekommt den Abschnitt „Vergleich“.
  TFile.WriteAllText(Path('Src/atlas.json'), '{"architecture": {"failOn": ["newCrossLink"], "baseline": "' +
    StringReplace(Older, '\', '/', [rfReplaceAll]) + '"}}');
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Newer, '--compare', Older, '--output', FOutput])));
  Assert.AreEqual(0, TLinterShell.Architecture(TCommandLineOptions.Parse(['--check', Source, '--architecture',
    Path('bericht.md')])));
  Assert.Contains(TFile.ReadAllText(Path('bericht.md'), TEncoding.UTF8), '### Neue Zyklen (1)');
end;

procedure TShellLinterTests.SuppressionStatsGiveZero;
begin
  Assert.AreEqual(0, Run(['--check', Path('Src/Kaputt.pas'), '--suppression-stats', '--format', 'json']));
  Assert.IsTrue(Trim(OutputText) <> '');
end;

procedure TShellLinterTests.UpdatedBaselineHidesFindings;
var
  Baseline: string;
begin
  Baseline := Path('baseline.json');
  Assert.AreEqual(0, Run(['--check', Path('Src/Kaputt.pas'), '--update-baseline', '--baseline=' + Baseline]));
  Assert.IsTrue(TFile.Exists(Baseline));
  // Nur Zähler auf stderr, keine Ausgabedatei.
  Assert.IsFalse(TFile.Exists(FOutput));
  Assert.AreEqual(0, Run(['--check', Path('Src/Kaputt.pas'), '--format', 'json', '--baseline', Baseline]));
  // Neue Treffer zählen weiter.
  TFile.WriteAllText(Path('Src/Kaputt.pas'), StringReplace(BrokenUnit, 'end.',
    'procedure Q;'#13#10'begin'#13#10'  while do;'#13#10'end;'#13#10'end.', []));
  Assert.AreEqual(1, Run(['--check', Path('Src/Kaputt.pas'), '--format', 'json', '--baseline', Baseline]));
end;

procedure TShellLinterTests.DefaultBaselineBesideConfiguration;
begin
  Assert.AreEqual(0, Run(['--check', TPath.Combine(FFolder, 'Src'), '--update-baseline']));
  Assert.IsTrue(TFile.Exists(Path('Src/atlas-baseline.json')));
  Assert.AreEqual(0, Run(['--check', TPath.Combine(FFolder, 'Src'), '--format', 'json']));
end;

procedure TShellLinterTests.IndexKnowsTypesOfOtherUnits;
const
  Dproj = '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup>'#13#10'    <MainSource>Lauf.dpr</MainSource>'#13#10 +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10'  </PropertyGroup>'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <DelphiCompile Include="$(MainSource)"><MainSource>MainSource</MainSource></DelphiCompile>'#13#10 +
    '    <DCCReference Include="Contnrs.pas"/>'#13#10'    <DCCReference Include="Suche.pas"/>'#13#10 +
    '  </ItemGroup>'#13#10'</Project>'#13#10;
  // RTL-Stub ohne Namespace wie in den Quellen von Free Pascal.
  Stub = 'unit Contnrs;'#13#10'interface'#13#10'type'#13#10'  TOrderedList = class(TObject)'#13#10 +
    '  public'#13#10'    function Push(AItem: Pointer): Pointer;'#13#10'    function Pop: Pointer;'#13#10 +
    '  end;'#13#10'  TStack = class(TOrderedList)'#13#10'  end;'#13#10'  TObjectStack = class(TStack)'#13#10 +
    '  public'#13#10'    function Pop: TObject;'#13#10'  end;'#13#10'implementation'#13#10 +
    'function TOrderedList.Push(AItem: Pointer): Pointer;'#13#10'begin'#13#10'  Result := AItem;'#13#10'end;'#13#10 +
    'function TOrderedList.Pop: Pointer;'#13#10'begin'#13#10'  Result := nil;'#13#10'end;'#13#10 +
    'function TObjectStack.Pop: TObject;'#13#10'begin'#13#10'  Result := nil;'#13#10'end;'#13#10'end.'#13#10;
  Suche = 'unit Suche;'#13#10'interface'#13#10'uses'#13#10'  Contnrs;'#13#10'type'#13#10'  TKnoten = class'#13#10 +
    '  end;'#13#10'  TSuche = class'#13#10'  private'#13#10'    FOffen: TObjectStack;'#13#10'  public'#13#10 +
    '    procedure Lauf;'#13#10'  end;'#13#10'implementation'#13#10'procedure TSuche.Lauf;'#13#10'var'#13#10 +
    '  Knoten: TKnoten;'#13#10'begin'#13#10'  Knoten := TKnoten(FOffen.Pop);'#13#10'end;'#13#10'end.'#13#10;
  Programm = 'program Lauf;'#13#10'uses'#13#10'  Suche in ''Suche.pas'';'#13#10'begin'#13#10'end.'#13#10;
begin
  ForceDirectories(Path('Idx'));
  TFile.WriteAllText(Path('Idx/Lauf.dproj'), Dproj);
  TFile.WriteAllText(Path('Idx/Lauf.dpr'), Programm);
  TFile.WriteAllText(Path('Idx/Contnrs.pas'), Stub);
  TFile.WriteAllText(Path('Idx/Suche.pas'), Suche);
  TFile.WriteAllText(Path('Idx/atlas.json'), '{"rules": {"legacy-stack-queue": "info"}}');
  Assert.AreEqual(0, Run(['--check', Path('Idx/Lauf.dproj'), '--format', 'json', '--fail-on', 'never',
    '--units', 'Suche']));
  Assert.IsTrue(Pos('"legacy-stack-queue"', OutputText) > 0, OutputText);
  Assert.AreEqual(0, Run(['--check', Path('Idx/Lauf.dproj'), '--format', 'json', '--fail-on', 'never',
    '--units', 'Suche', '--no-index']));
  Assert.IsFalse(Pos('"legacy-stack-queue"', OutputText) > 0, OutputText);
end;

procedure TShellLinterTests.InlineCompilerVersionWithoutInstallation;
const
  Dproj = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup><ProjectVersion>20.3</ProjectVersion>' +
    '<Config Condition="''$(Config)''==''''">Release</Config>' +
    '<Platform Condition="''$(Platform)''==''''">Win32</Platform></PropertyGroup>'#13#10 +
    '  <ItemGroup><DCCReference Include="T1.pas"/></ItemGroup>'#13#10'</Project>'#13#10;
  UnitText = 'unit T1;'#13#10'interface'#13#10'type'#13#10'  TA = class'#13#10 +
    '    F: {$IF CompilerVersion >= 36}Int64{$ELSE}Integer{$ENDIF};'#13#10'  end;'#13#10'implementation'#13#10 +
    '{$IF CompilerVersion >= 36}'#13#10'const A = 1;'#13#10'{$ELSE}'#13#10'const A = 2;'#13#10'{$IFEND}'#13#10 +
    'end.'#13#10;
begin
  ForceDirectories(Path('Cv'));
  TFile.WriteAllText(Path('Cv/T.dproj'), Dproj);
  TFile.WriteAllText(Path('Cv/T1.pas'), UnitText);
  Assert.AreEqual(0, Run(['--check', Path('Cv/T.dproj'), '--format', 'json', '--fail-on', 'never', '--no-index']));
  Assert.Contains(OutputText, 'T1.pas');
  Assert.IsFalse(Pos('"syntax"', OutputText) > 0, OutputText);
  // Ohne .dproj gilt die neueste bekannte Version.
  Assert.AreEqual(0, Run(['--check', Path('Cv/T1.pas'), '--format', 'json', '--fail-on', 'never', '--no-index']));
  Assert.IsFalse(Pos('"syntax"', OutputText) > 0, OutputText);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellLinterTests);

end.
