unit Shell.Linter.Tests;

// Tests für den Linter-Modus ohne Editor (#95) (#415): TLinterShell.Run mit
// Optionen aus TCommandLineOptions.Parse auf Dateien in einem Temp-Ordner.
// Exit-Codes (0 sauber, 1 Treffer, 3 Aufruf- oder Lesefehler), Formate,
// Metriken (#66), TODOs (#68), Unterdrückungen (#147) und Baseline (#97),
// dazu der Lauf mit und ohne Symbolindex (#1112). Index-Caches liegen im
// Temp-Ordner (--index-cache), nie bei denen des Benutzers.
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
    procedure SuppressionStatsGiveZero;
    [Test]
    procedure UpdatedBaselineHidesFindings;
    [Test]
    procedure DefaultBaselineBesideConfiguration;
    /// <summary>Mit Index kennt legacy-stack-queue TObjectStack aus einer anderen Unit, mit --no-index nicht.
    /// </summary>
    [Test]
    procedure IndexKnowsTypesOfOtherUnits;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Shell.CommandLine,
  Shell.Linter;

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
    Path('IndexCache')]));
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

initialization
  TDUnitX.RegisterTestFixture(TShellLinterTests);

end.
