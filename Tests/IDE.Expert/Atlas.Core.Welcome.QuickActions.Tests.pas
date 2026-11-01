unit Atlas.Core.Welcome.QuickActions.Tests;

// Tests der Schnellaktionen je Projekt ohne VCL und IDE (#764):
// Einstellung welcomePage.quickActions.items, Knöpfe und ihre Reihenfolge,
// Sperrlogik von „Pull“ (lokale Änderungen, keine Arbeitskopie, laufende
// Aktion; das Holen selbst testet Atlas.Core.Vcs.Pull.Tests), Zuordnung Projekt →
// Testprojekt (Namensmuster, eigenes DUnitX-Programm, Projektgruppe),
// Konfigurationen und Plattformen einer .dproj, Projekte einer .groupproj,
// Kommandozeile der Konsole, Tasten Strg+B/Strg+T und die Bewegung mit den
// Pfeiltasten.
// Akzeptanzkriterien: Pull ist bei lokalen Änderungen gesperrt, sonst holt es
// (Git) bzw. aktualisiert (SVN); items ohne console lässt nur diesen Knopf weg;
// Zuordnung Projekt → Testprojekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeQuickActionsTests = class
  public
    [Test]
    procedure ItemsParseAndNormalize;
    [Test]
    procedure ItemsWithoutConsoleDropOnlyThatButton;
    [Test]
    procedure PullBlockedByLocalChanges;
    [Test]
    procedure PullBlockedWithoutWorkingCopyOrWhileBusy;
    [Test]
    procedure SvnButtonIsUpdate;
    [Test]
    procedure BusyKeepsFolderAndConsole;
    /// <summary>#1292: Auswahl „mit/ohne Externals“ am Knopf nur unter SVN.</summary>
    [Test]
    procedure UpdateAsksForExternalsOnlyUnderSvn;
    [Test]
    procedure TestProjectByNamePattern;
    [Test]
    procedure TestProjectIsProjectItself;
    [Test]
    procedure TestProjectNeedsDUnitX;
    [Test]
    procedure TestProjectOfGroup;
    [Test]
    procedure TestCandidatesOrder;
    [Test]
    procedure TargetsFromDproj;
    [Test]
    procedure ChooseTargetPrefersLastUsed;
    [Test]
    procedure GroupProjectsResolvePaths;
    [Test]
    procedure CombinePathResolvesDots;
    [Test]
    procedure ConsoleCommandPerProgram;
    [Test]
    procedure KeysBuildAndTest;
    [Test]
    procedure ArrowsMoveRowAndButton;
    [Test]
    procedure StateElapsedSeconds;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.QuickActions;

type
  /// <summary>Dateien im Speicher für die Zuordnung Projekt → Testprojekt.</summary>
  TFakeFiles = class
  public
    Names: TArray<string>;
    Texts: TArray<string>;
    procedure Add(const AName, AText: string);
    function Exists(const AName: string): Boolean;
    function Read(const AName: string; out ALines: TArray<string>): Boolean;
  end;

const
  DUnitXProgram = 'program App.Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  App.Tests.Core;'#10'begin'#10'end.';
  PlainProgram = 'program App;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.';

function Vcs(AKnown: Boolean; const AKind: string; AChanged: Integer): TAtlasProjectVcs;
begin
  Result := TAtlasProjectVcs.Empty;
  Result.Known := AKnown;
  Result.Kind := AKind;
  Result.Changed := AChanged;
end;

function TestFor(AFiles: TFakeFiles; const AProject: string; out ACandidates: TArray<string>): string;
begin
  Result := TAtlasWelcomeQuickActions.TestProjectFor(AProject,
    function(const AName: string): Boolean
    begin
      Result := AFiles.Exists(AName);
    end,
    function(const AName: string; out ALines: TArray<string>): Boolean
    begin
      Result := AFiles.Read(AName, ALines);
    end, ACandidates);
end;

{ TFakeFiles }

procedure TFakeFiles.Add(const AName, AText: string);
begin
  Names := Names + [AName];
  Texts := Texts + [AText];
end;

function TFakeFiles.Exists(const AName: string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in Names do
    if SameText(Name, AName) then
      Exit(True);
end;

function TFakeFiles.Read(const AName: string; out ALines: TArray<string>): Boolean;
var
  Index: Integer;
begin
  ALines := nil;
  Result := False;
  for Index := 0 to High(Names) do
    if SameText(Names[Index], AName) then
    begin
      ALines := Texts[Index].Split([#10]);
      Exit(True);
    end;
end;

{ TAtlasWelcomeQuickActionsTests }

procedure TAtlasWelcomeQuickActionsTests.ItemsParseAndNormalize;
var
  Items: TAtlasQuickActions;
begin
  Items := TAtlasWelcomeQuickActions.ParseItems(TAtlasWelcomeQuickActions.DefaultItems);
  Assert.IsTrue(Items = [TAtlasQuickAction.Build, TAtlasQuickAction.Tests, TAtlasQuickAction.Run,
    TAtlasQuickAction.Pull, TAtlasQuickAction.Folder, TAtlasQuickAction.Console, TAtlasQuickAction.Tasks],
    'Vorgabe: alle');
  Assert.AreEqual('tests,tasks', TAtlasWelcomeQuickActions.NormalizedItems('Tasks tests'));
  Assert.AreEqual('build,pull,console', TAtlasWelcomeQuickActions.NormalizedItems(' Console; PULL build build x'),
    'feste Reihenfolge, jeder einmal, Unbekanntes fällt weg');
  Assert.AreEqual('', TAtlasWelcomeQuickActions.NormalizedItems(''), 'leer = keiner');
  Assert.AreEqual('wt.exe', TAtlasWelcomeQuickActions.NormalizedConsole('  '));
  Assert.AreEqual('pwsh.exe', TAtlasWelcomeQuickActions.NormalizedConsole(' pwsh.exe '));
end;

procedure TAtlasWelcomeQuickActionsTests.ItemsWithoutConsoleDropOnlyThatButton;
var
  Buttons: TAtlasQuickActionButtons;
begin
  Buttons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems('build,tests,run,pull,folder'),
    Vcs(True, 'git', 0), False);
  Assert.AreEqual(5, Integer(Length(Buttons)));
  Assert.IsTrue(Buttons[0].Action = TAtlasQuickAction.Build);
  Assert.IsTrue(Buttons[1].Action = TAtlasQuickAction.Tests);
  Assert.IsTrue(Buttons[2].Action = TAtlasQuickAction.Run);
  Assert.IsTrue(Buttons[3].Action = TAtlasQuickAction.Pull);
  Assert.IsTrue(Buttons[4].Action = TAtlasQuickAction.Folder);
  Assert.AreEqual(-1, TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Console));
  Assert.IsTrue(Buttons[0].HasMenu and Buttons[2].HasMenu, 'Konfiguration bzw. Startprofil wählbar');
  Assert.IsFalse(Buttons[1].HasMenu);
  Assert.IsTrue(Buttons[0].Enabled and Buttons[1].Enabled and Buttons[3].Enabled);
  // „Aufgaben ▾“ (#900): Auswahl der Aufgabe; braucht die IDE nicht, geht also auch, wenn sie beschäftigt ist.
  Buttons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Tasks], Vcs(True, 'git', 0), False, True);
  Assert.AreEqual(1, Integer(Length(Buttons)));
  Assert.IsTrue(Buttons[0].HasMenu and Buttons[0].Enabled);
  Assert.IsFalse(TAtlasWelcomeQuickActions.UsesIde(TAtlasQuickAction.Tasks));
  Buttons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Tasks], Vcs(True, 'git', 0), True);
  Assert.IsFalse(Buttons[0].Enabled, 'auf dem Projekt läuft schon eine Aktion');
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeQuickActions.Buttons([], Vcs(True, 'git', 0), False))));
end;

procedure TAtlasWelcomeQuickActionsTests.PullBlockedByLocalChanges;
var
  Buttons: TAtlasQuickActionButtons;
  Index: Integer;
begin
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'git', 2)) = TAtlasPullBlock.LocalChanges);
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'svn', 1)) = TAtlasPullBlock.LocalChanges);
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'git', 0)) = TAtlasPullBlock.None);
  // Unbekannter Stand sperrt nicht: Pull prüft selbst.
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'git', -1)) = TAtlasPullBlock.None);
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(False, '', 0)) = TAtlasPullBlock.None);
  Buttons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems('pull,folder'),
    Vcs(True, 'git', 3), False);
  Index := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Pull);
  Assert.AreEqual(0, Index);
  Assert.IsFalse(Buttons[Index].Enabled, 'gesperrt bei lokalen Änderungen');
  Assert.IsTrue(Buttons[Index].Block = TAtlasPullBlock.LocalChanges);
  Assert.IsTrue(Buttons[1].Enabled, 'Ordner bleibt nutzbar');
end;

procedure TAtlasWelcomeQuickActionsTests.PullBlockedWithoutWorkingCopyOrWhileBusy;
var
  Buttons: TAtlasQuickActionButtons;
begin
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'none', 0)) = TAtlasPullBlock.NoWorkingCopy);
  Buttons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'git', 0), True);
  Assert.IsFalse(Buttons[0].Enabled);
  Assert.IsTrue(Buttons[0].Block = TAtlasPullBlock.Busy);
  // Lokale Änderungen gehen als Grund vor.
  Buttons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'git', 1), True);
  Assert.IsTrue(Buttons[0].Block = TAtlasPullBlock.LocalChanges);
end;

procedure TAtlasWelcomeQuickActionsTests.SvnButtonIsUpdate;
var
  Buttons: TAtlasQuickActionButtons;
begin
  Buttons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'svn', 0), False);
  Assert.IsTrue(Buttons[0].Update, 'SVN: „Aktualisieren“');
  Assert.IsTrue(Buttons[0].Enabled);
  Buttons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'git', 0), False);
  Assert.IsFalse(Buttons[0].Update, 'Git: „Pull“');
  Assert.IsFalse(TAtlasWelcomeQuickActions.IsUpdate(Vcs(False, 'svn', 0)), 'unbekannt: „Pull“');
end;

procedure TAtlasWelcomeQuickActionsTests.BusyKeepsFolderAndConsole;
var
  Buttons: TAtlasQuickActionButtons;
  Button: TAtlasQuickActionButton;
begin
  Buttons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems(
    TAtlasWelcomeQuickActions.DefaultItems), Vcs(True, 'git', 0), True);
  for Button in Buttons do
    Assert.IsTrue(((Button.Action = TAtlasQuickAction.Folder) or (Button.Action = TAtlasQuickAction.Console)) =
      Button.Enabled, TAtlasWelcomeQuickActions.Names[Button.Action]);
  // Aktion eines anderen Projekts in der IDE: nur die Knöpfe, die die IDE brauchen, sind gesperrt.
  Buttons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems(
    TAtlasWelcomeQuickActions.DefaultItems), Vcs(True, 'git', 0), False, True);
  for Button in Buttons do
    Assert.IsTrue(TAtlasWelcomeQuickActions.UsesIde(Button.Action) <> Button.Enabled,
      TAtlasWelcomeQuickActions.Names[Button.Action]);
  Assert.IsTrue(Buttons[TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Pull)].Block =
    TAtlasPullBlock.None);
end;

procedure TAtlasWelcomeQuickActionsTests.UpdateAsksForExternalsOnlyUnderSvn;
var
  mButtons: TAtlasQuickActionButtons;
begin
  // Auswahl am Knopf nur für „Aktualisieren“ (SVN).
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull, TAtlasQuickAction.Folder],
    Vcs(True, 'svn', 0), False);
  TAtlasWelcomeQuickActions.AskExternals(mButtons);
  Assert.IsTrue(mButtons[0].AskExternals);
  Assert.IsTrue(mButtons[0].HasMenu);
  Assert.IsFalse(mButtons[1].AskExternals);
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'git', 0), False);
  TAtlasWelcomeQuickActions.AskExternals(mButtons);
  Assert.IsFalse(mButtons[0].AskExternals);
  mButtons := nil;
end;

procedure TAtlasWelcomeQuickActionsTests.TestProjectByNamePattern;
var
  Files: TFakeFiles;
  Candidates: TArray<string>;
begin
  Files := TFakeFiles.Create;
  try
    Files.Add('C:\Src\App\App.dproj', '');
    Files.Add('C:\Src\App\App.dpr', PlainProgram);
    Files.Add('C:\Src\Tests\App.Tests.dproj', '');
    Files.Add('C:\Src\Tests\App.Tests.dpr', DUnitXProgram);
    Assert.AreEqual('C:\Src\Tests\App.Tests.dproj', TestFor(Files, 'C:\Src\App\App.dproj', Candidates),
      '..\Tests\App.Tests.dproj');
    Assert.AreEqual(1, Integer(Length(Candidates)));
    // Näher liegendes Muster gewinnt.
    Files.Add('C:\Src\App\Tests\AppTests.dproj', '');
    Files.Add('C:\Src\App\Tests\AppTests.dpr', DUnitXProgram);
    Assert.AreEqual('C:\Src\App\Tests\AppTests.dproj', TestFor(Files, 'C:\Src\App\App.dproj', Candidates));
    Assert.AreEqual(2, Integer(Length(Candidates)));
  finally
    Files.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestProjectIsProjectItself;
var
  Files: TFakeFiles;
  Candidates: TArray<string>;
begin
  Files := TFakeFiles.Create;
  try
    Files.Add('C:\Src\App.Tests.dpr', DUnitXProgram);
    Assert.AreEqual('C:\Src\App.Tests.dproj', TestFor(Files, 'C:\Src\App.Tests.dproj', Candidates),
      'ein DUnitX-Programm ist sein eigenes Testprojekt');
  finally
    Files.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestProjectNeedsDUnitX;
var
  Files: TFakeFiles;
  Candidates: TArray<string>;
begin
  Files := TFakeFiles.Create;
  try
    Files.Add('C:\Src\App.dpr', PlainProgram);
    // Passender Name, aber kein DUnitX (z. B. DUnit oder ein Werkzeug).
    Files.Add('C:\Src\App.Test.dproj', '');
    Files.Add('C:\Src\App.Test.dpr', PlainProgram);
    Assert.AreEqual('', TestFor(Files, 'C:\Src\App.dproj', Candidates));
    Assert.AreEqual(0, Integer(Length(Candidates)));
    // .dproj ohne .dpr zählt nicht.
    Files.Add('C:\Src\AppTests.dproj', '');
    Assert.AreEqual('', TestFor(Files, 'C:\Src\App.dproj', Candidates));
    Assert.AreEqual('', TestFor(Files, '', Candidates));
  finally
    Files.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestProjectOfGroup;
var
  Files: TFakeFiles;
  Candidates: TArray<string>;
begin
  Files := TFakeFiles.Create;
  try
    Files.Add('C:\Src\Suite.groupproj',
      '<Project>'#10'  <ItemGroup>'#10'    <Projects Include="App\App.dproj">'#10'    </Projects>'#10 +
      '    <Projects Include="Tests\Core.Tests.dproj"/>'#10'  </ItemGroup>'#10'</Project>');
    Files.Add('C:\Src\App\App.dpr', PlainProgram);
    Files.Add('C:\Src\Tests\Core.Tests.dpr', DUnitXProgram);
    Assert.AreEqual('C:\Src\Tests\Core.Tests.dproj', TestFor(Files, 'C:\Src\Suite.groupproj', Candidates),
      'einziges DUnitX-Projekt der Gruppe');
    // Zwei Testprojekte: das nach der Gruppe benannte.
    Files.Names[0] := 'C:\Src\Old.groupproj';
    Files.Add('C:\Src\Suite.groupproj',
      '<Projects Include="Tests\Core.Tests.dproj"/>'#10'<Projects Include="Tests\Suite.Tests.dproj"/>');
    Files.Add('C:\Src\Tests\Suite.Tests.dpr', DUnitXProgram);
    Assert.AreEqual('C:\Src\Tests\Suite.Tests.dproj', TestFor(Files, 'C:\Src\Suite.groupproj', Candidates));
    Assert.AreEqual(2, Integer(Length(Candidates)));
    // Zwei ohne passenden Namen: die IDE fragt.
    Files.Add('C:\Src\Other.groupproj',
      '<Projects Include="Tests\Core.Tests.dproj"/>'#10'<Projects Include="Tests\Suite.Tests.dproj"/>');
    Assert.AreEqual('', TestFor(Files, 'C:\Src\Other.groupproj', Candidates));
    Assert.AreEqual(2, Integer(Length(Candidates)), 'Kandidaten für die Auswahl');
  finally
    Files.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestCandidatesOrder;
var
  Candidates: TArray<string>;
begin
  Candidates := TAtlasWelcomeQuickActions.TestCandidates('C:\Src\App\App.dproj');
  Assert.AreEqual(20, Integer(Length(Candidates)), '4 Muster in 5 Ordnern');
  Assert.AreEqual('C:\Src\App\App.Tests.dproj', Candidates[0]);
  Assert.AreEqual('C:\Src\App\AppTests.dproj', Candidates[1]);
  Assert.AreEqual('C:\Src\App\Tests\App.Tests.dproj', Candidates[4]);
  Assert.AreEqual('C:\Src\Tests\App.Tests.dproj', Candidates[12]);
  Assert.AreEqual('C:\Src\Test\AppTest.dproj', Candidates[19]);
end;

procedure TAtlasWelcomeQuickActionsTests.TargetsFromDproj;
const
  Dproj =
    '<Project>'#10 +
    '  <PropertyGroup>'#10 +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>'#10 +
    '  </PropertyGroup>'#10 +
    '  <ItemGroup>'#10 +
    '    <BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>'#10 +
    '    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>'#10 +
    '    <BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration>'#10 +
    '    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>'#10 +
    '  </ItemGroup>'#10 +
    '  <ProjectExtensions><BorlandProject><Platforms>'#10 +
    '    <Platform value="Win32">True</Platform>'#10 +
    '    <Platform value="Win64">True</Platform>'#10 +
    '    <Platform value="Linux64">False</Platform>'#10 +
    '  </Platforms></BorlandProject></ProjectExtensions>'#10 +
    '</Project>';
var
  Targets: TAtlasProjectTargets;
begin
  Targets := TAtlasWelcomeQuickActions.ReadTargets(Dproj);
  Assert.AreEqual(2, Integer(Length(Targets.Configurations)), 'ohne Base, jede einmal');
  Assert.AreEqual('Debug', Targets.Configurations[0]);
  Assert.AreEqual('Release', Targets.Configurations[1]);
  Assert.AreEqual(2, Integer(Length(Targets.Platforms)), 'nur eingeschaltete Plattformen');
  Assert.AreEqual('Win32', Targets.Platforms[0]);
  Assert.AreEqual('Win64', Targets.Platforms[1]);
  Assert.IsTrue(Targets.HasConfiguration('release'));
  Assert.IsFalse(Targets.HasPlatform('Linux64'));
  Targets := TAtlasWelcomeQuickActions.ReadTargets('');
  Assert.AreEqual(0, Integer(Length(Targets.Configurations)));
  Assert.AreEqual(0, Integer(Length(Targets.Platforms)));
end;

procedure TAtlasWelcomeQuickActionsTests.ChooseTargetPrefersLastUsed;
var
  Targets: TAtlasProjectTargets;
  Configuration, Platform: string;
begin
  Targets.Configurations := ['Debug', 'Release'];
  Targets.Platforms := ['Win32', 'Win64'];
  TAtlasWelcomeQuickActions.ChooseTarget(Targets, 'debug', 'WIN64', Configuration, Platform);
  Assert.AreEqual('Debug', Configuration, 'Schreibweise der Datei');
  Assert.AreEqual('Win64', Platform);
  TAtlasWelcomeQuickActions.ChooseTarget(Targets, 'Profiling', '', Configuration, Platform);
  Assert.AreEqual('', Configuration, 'unbekannt: aktive der IDE');
  Assert.AreEqual('', Platform);
end;

procedure TAtlasWelcomeQuickActionsTests.GroupProjectsResolvePaths;
var
  Projects: TArray<string>;
begin
  Projects := TAtlasWelcomeQuickActions.GroupProjects(
    '<Projects Include="App\App.dproj"/>'#10'<Projects Include="..\Lib\Lib.dproj"/>'#10 +
    '<Projects Include="D:\Other\X.dproj"/>'#10'<Projects Include="App\App.dproj"/>', 'C:\Src\Group');
  Assert.AreEqual(3, Integer(Length(Projects)));
  Assert.AreEqual('C:\Src\Group\App\App.dproj', Projects[0]);
  Assert.AreEqual('C:\Src\Lib\Lib.dproj', Projects[1]);
  Assert.AreEqual('D:\Other\X.dproj', Projects[2]);
  Assert.IsTrue(TAtlasWelcomeQuickActions.IsGroup('C:\A\B.GroupProj'));
  Assert.IsFalse(TAtlasWelcomeQuickActions.IsGroup('C:\A\B.dproj'));
end;

procedure TAtlasWelcomeQuickActionsTests.CombinePathResolvesDots;
begin
  Assert.AreEqual('C:\A\C\d.dproj', TAtlasWelcomeQuickActions.CombinePath('C:\A\B', '..\C\.\d.dproj'));
  Assert.AreEqual('C:\A\B\x.dproj', TAtlasWelcomeQuickActions.CombinePath('C:\A\B\', 'x.dproj'));
  Assert.AreEqual('\\srv\share\x.dproj', TAtlasWelcomeQuickActions.CombinePath('C:\A', '\\srv\share\x.dproj'));
  Assert.AreEqual('C:\A\x.dproj', TAtlasWelcomeQuickActions.CombinePath('C:/A', 'x.dproj'));
end;

procedure TAtlasWelcomeQuickActionsTests.ConsoleCommandPerProgram;
var
  FileName, Parameters: string;
begin
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('', 'C:\Src\App', FileName, Parameters));
  Assert.AreEqual('wt.exe', FileName, 'Vorgabe Windows-Terminal');
  Assert.AreEqual('-d "C:\Src\App"', Parameters);
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('cmd.exe', 'C:\', FileName, Parameters));
  Assert.AreEqual('/K cd /d "C:\."', Parameters, 'Backslash vor dem Anführungszeichen');
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('C:\Tools\pwsh.exe', 'C:\O''Neil', FileName, Parameters));
  Assert.AreEqual('C:\Tools\pwsh.exe', FileName);
  Assert.AreEqual('-NoExit -Command Set-Location -LiteralPath ''C:\O''''Neil''', Parameters);
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('ConEmu64.exe', 'C:\Src', FileName, Parameters));
  Assert.AreEqual('', Parameters, 'anderes Programm: nur Arbeitsordner');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ConsoleCommand('wt.exe', '', FileName, Parameters));
end;

procedure TAtlasWelcomeQuickActionsTests.KeysBuildAndTest;
var
  Action: TAtlasQuickAction;
  All: TAtlasQuickActions;
begin
  All := TAtlasWelcomeQuickActions.ParseItems(TAtlasWelcomeQuickActions.DefaultItems);
  Assert.IsTrue(TAtlasWelcomeQuickActions.ActionForKey($4042, $4042, $4054, All, Action));
  Assert.IsTrue(Action = TAtlasQuickAction.Build, 'Strg+B');
  Assert.IsTrue(TAtlasWelcomeQuickActions.ActionForKey($4054, $4042, $4054, All, Action));
  Assert.IsTrue(Action = TAtlasQuickAction.Tests, 'Strg+T');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ActionForKey($4054, $4042, $4054, [TAtlasQuickAction.Build], Action),
    'Knopf nicht eingestellt');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ActionForKey($4042, 0, $4054, All, Action), 'Taste abgeschaltet');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ActionForKey(0, 0, 0, All, Action));
  // Geänderte Taste (#399).
  Assert.IsTrue(TAtlasWelcomeQuickActions.ActionForKey($6042, $6042, $4054, All, Action));
  Assert.IsTrue(Action = TAtlasQuickAction.Build);
end;

procedure TAtlasWelcomeQuickActionsTests.ArrowsMoveRowAndButton;
var
  Buttons: TAtlasQuickActionButtons;
begin
  Assert.AreEqual(-1, TAtlasWelcomeQuickActions.MoveRow(0, 1, 0));
  Assert.AreEqual(0, TAtlasWelcomeQuickActions.MoveRow(-1, 1, 3), 'ohne Auswahl: erste Zeile');
  Assert.AreEqual(2, TAtlasWelcomeQuickActions.MoveRow(1, 1, 3));
  Assert.AreEqual(2, TAtlasWelcomeQuickActions.MoveRow(2, 1, 3), 'bleibt am Ende');
  Assert.AreEqual(0, TAtlasWelcomeQuickActions.MoveRow(0, -1, 3));
  // Alle Knöpfe, Pull (Index 3) wegen lokaler Änderungen gesperrt.
  Buttons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems(
    TAtlasWelcomeQuickActions.DefaultItems), Vcs(True, 'git', 1), False);
  Assert.AreEqual(7, Integer(Length(Buttons)));
  Assert.AreEqual(0, TAtlasWelcomeQuickActions.MoveButton(Buttons, -1, 1), 'rechts: erster Knopf');
  Assert.AreEqual(6, TAtlasWelcomeQuickActions.MoveButton(Buttons, -1, -1), 'links: letzter Knopf');
  Assert.AreEqual(4, TAtlasWelcomeQuickActions.MoveButton(Buttons, 2, 1), 'überspringt gesperrten Pull');
  Assert.AreEqual(2, TAtlasWelcomeQuickActions.MoveButton(Buttons, 4, -1));
  Assert.AreEqual(6, TAtlasWelcomeQuickActions.MoveButton(Buttons, 6, 1), 'bleibt am Ende');
  Assert.AreEqual(-1, TAtlasWelcomeQuickActions.MoveButton(nil, -1, 1));
end;

procedure TAtlasWelcomeQuickActionsTests.StateElapsedSeconds;
var
  State: TAtlasQuickActionState;
begin
  State := TAtlasQuickActionState.Idle;
  Assert.IsFalse(State.Running);
  Assert.AreEqual(0, State.ElapsedSeconds(5000));
  State := TAtlasQuickActionState.Started(TAtlasQuickAction.Build, 1000);
  Assert.IsTrue(State.Running);
  Assert.IsTrue(State.Action = TAtlasQuickAction.Build);
  Assert.AreEqual(12, State.ElapsedSeconds(13500), '„baut … 12 s“');
  Assert.AreEqual(0, State.ElapsedSeconds(500));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeQuickActionsTests);

end.
