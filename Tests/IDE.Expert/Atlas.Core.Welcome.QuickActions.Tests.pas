unit Atlas.Core.Welcome.QuickActions.Tests;

// Tests der Schnellaktionen je Projekt ohne VCL und IDE (#764):
// Einstellung welcomePage.quickActions.items, Knöpfe und ihre Reihenfolge,
// Sperrlogik von „Pull“ (lokale Änderungen, keine Arbeitskopie, laufende
// Aktion; das Holen selbst testet Atlas.Core.VersionControl.Pull.Tests), Zuordnung Projekt →
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
    /// <summary>#1967: Phase, Detail und Text der IDE nach einem Pull je Ergebnis.</summary>
    [Test]
    procedure AfterPullDecidesPhaseAndNote;
    [Test]
    procedure TestEndedWhenStoppedOrGraceOver;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Pull,
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
  cDUnitXProgram = 'program App.Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  App.Tests.Core;'#10'begin'#10'end.';
  cPlainProgram = 'program App;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.';

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
  mName: string;
begin
  Result := False;
  for mName in Names do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
end;

function TFakeFiles.Read(const AName: string; out ALines: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  ALines := nil;
  Result := False;
  for mIndex := 0 to High(Names) do
  begin
    if SameText(Names[mIndex], AName) then
    begin
      ALines := Texts[mIndex].Split([#10]);
      Exit(True);
    end;
  end;
end;

{ TAtlasWelcomeQuickActionsTests }

procedure TAtlasWelcomeQuickActionsTests.ItemsParseAndNormalize;
var
  mItems: TAtlasQuickActions;
begin
  mItems := TAtlasWelcomeQuickActions.ParseItems(TAtlasWelcomeQuickActions.cDefaultItems);
  Assert.IsTrue(mItems = [TAtlasQuickAction.Build, TAtlasQuickAction.Tests, TAtlasQuickAction.Run,
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
  mButtons: TAtlasQuickActionButtons;
begin
  mButtons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems('build,tests,run,pull,folder'),
    Vcs(True, 'git', 0), False);
  Assert.AreEqual(5, Integer(Length(mButtons)));
  Assert.IsTrue(mButtons[0].Action = TAtlasQuickAction.Build);
  Assert.IsTrue(mButtons[1].Action = TAtlasQuickAction.Tests);
  Assert.IsTrue(mButtons[2].Action = TAtlasQuickAction.Run);
  Assert.IsTrue(mButtons[3].Action = TAtlasQuickAction.Pull);
  Assert.IsTrue(mButtons[4].Action = TAtlasQuickAction.Folder);
  Assert.AreEqual(-1, TAtlasWelcomeQuickActions.IndexOf(mButtons, TAtlasQuickAction.Console));
  Assert.IsTrue(mButtons[0].HasMenu and mButtons[2].HasMenu, 'Konfiguration bzw. Startprofil wählbar');
  Assert.IsFalse(mButtons[1].HasMenu);
  Assert.IsTrue(mButtons[0].Enabled and mButtons[1].Enabled and mButtons[3].Enabled);
  // „Aufgaben ▾“ (#900): Auswahl der Aufgabe; braucht die IDE nicht, geht also auch, wenn sie beschäftigt ist.
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Tasks], Vcs(True, 'git', 0), False, True);
  Assert.AreEqual(1, Integer(Length(mButtons)));
  Assert.IsTrue(mButtons[0].HasMenu and mButtons[0].Enabled);
  Assert.IsFalse(TAtlasWelcomeQuickActions.UsesIde(TAtlasQuickAction.Tasks));
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Tasks], Vcs(True, 'git', 0), True);
  Assert.IsFalse(mButtons[0].Enabled, 'auf dem Projekt läuft schon eine Aktion');
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeQuickActions.Buttons([], Vcs(True, 'git', 0), False))));
end;

procedure TAtlasWelcomeQuickActionsTests.PullBlockedByLocalChanges;
var
  mButtons: TAtlasQuickActionButtons;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'git', 2)) = TAtlasPullBlock.LocalChanges);
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'svn', 1)) = TAtlasPullBlock.LocalChanges);
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'git', 0)) = TAtlasPullBlock.None);
  // Unbekannter Stand sperrt nicht: Pull prüft selbst.
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'git', -1)) = TAtlasPullBlock.None);
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(False, '', 0)) = TAtlasPullBlock.None);
  mButtons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems('pull,folder'),
    Vcs(True, 'git', 3), False);
  mIndex := TAtlasWelcomeQuickActions.IndexOf(mButtons, TAtlasQuickAction.Pull);
  Assert.AreEqual(0, mIndex);
  Assert.IsFalse(mButtons[mIndex].Enabled, 'gesperrt bei lokalen Änderungen');
  Assert.IsTrue(mButtons[mIndex].Block = TAtlasPullBlock.LocalChanges);
  Assert.IsTrue(mButtons[1].Enabled, 'Ordner bleibt nutzbar');
end;

procedure TAtlasWelcomeQuickActionsTests.PullBlockedWithoutWorkingCopyOrWhileBusy;
var
  mButtons: TAtlasQuickActionButtons;
begin
  Assert.IsTrue(TAtlasWelcomeQuickActions.PullBlock(Vcs(True, 'none', 0)) = TAtlasPullBlock.NoWorkingCopy);
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'git', 0), True);
  Assert.IsFalse(mButtons[0].Enabled);
  Assert.IsTrue(mButtons[0].Block = TAtlasPullBlock.Busy);
  // Lokale Änderungen gehen als Grund vor.
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'git', 1), True);
  Assert.IsTrue(mButtons[0].Block = TAtlasPullBlock.LocalChanges);
end;

procedure TAtlasWelcomeQuickActionsTests.SvnButtonIsUpdate;
var
  mButtons: TAtlasQuickActionButtons;
begin
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'svn', 0), False);
  Assert.IsTrue(mButtons[0].Update, 'SVN: „Aktualisieren“');
  Assert.IsTrue(mButtons[0].Enabled);
  mButtons := TAtlasWelcomeQuickActions.Buttons([TAtlasQuickAction.Pull], Vcs(True, 'git', 0), False);
  Assert.IsFalse(mButtons[0].Update, 'Git: „Pull“');
  Assert.IsFalse(TAtlasWelcomeQuickActions.IsUpdate(Vcs(False, 'svn', 0)), 'unbekannt: „Pull“');
end;

procedure TAtlasWelcomeQuickActionsTests.BusyKeepsFolderAndConsole;
var
  mButtons: TAtlasQuickActionButtons;
  mButton: TAtlasQuickActionButton;
begin
  mButtons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems(
    TAtlasWelcomeQuickActions.cDefaultItems), Vcs(True, 'git', 0), True);
  for mButton in mButtons do
  begin
    Assert.IsTrue(((mButton.Action = TAtlasQuickAction.Folder) or (mButton.Action = TAtlasQuickAction.Console)) =
      mButton.Enabled, TAtlasWelcomeQuickActions.cNames[mButton.Action]);
  end;
  // Aktion eines anderen Projekts in der IDE: nur die Knöpfe, die die IDE brauchen, sind gesperrt.
  mButtons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems(
    TAtlasWelcomeQuickActions.cDefaultItems), Vcs(True, 'git', 0), False, True);
  for mButton in mButtons do
  begin
    Assert.IsTrue(TAtlasWelcomeQuickActions.UsesIde(mButton.Action) <> mButton.Enabled,
      TAtlasWelcomeQuickActions.cNames[mButton.Action]);
  end;
  Assert.IsTrue(mButtons[TAtlasWelcomeQuickActions.IndexOf(mButtons, TAtlasQuickAction.Pull)].Block =
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
  mFiles: TFakeFiles;
  mCandidates: TArray<string>;
begin
  mFiles := TFakeFiles.Create;
  try
    mFiles.Add('C:\Src\App\App.dproj', '');
    mFiles.Add('C:\Src\App\App.dpr', cPlainProgram);
    mFiles.Add('C:\Src\Tests\App.Tests.dproj', '');
    mFiles.Add('C:\Src\Tests\App.Tests.dpr', cDUnitXProgram);
    Assert.AreEqual('C:\Src\Tests\App.Tests.dproj', TestFor(mFiles, 'C:\Src\App\App.dproj', mCandidates),
      '..\Tests\App.Tests.dproj');
    Assert.AreEqual(1, Integer(Length(mCandidates)));
    // Näher liegendes Muster gewinnt.
    mFiles.Add('C:\Src\App\Tests\AppTests.dproj', '');
    mFiles.Add('C:\Src\App\Tests\AppTests.dpr', cDUnitXProgram);
    Assert.AreEqual('C:\Src\App\Tests\AppTests.dproj', TestFor(mFiles, 'C:\Src\App\App.dproj', mCandidates));
    Assert.AreEqual(2, Integer(Length(mCandidates)));
  finally
    mFiles.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestProjectIsProjectItself;
var
  mFiles: TFakeFiles;
  mCandidates: TArray<string>;
begin
  mFiles := TFakeFiles.Create;
  try
    mFiles.Add('C:\Src\App.Tests.dpr', cDUnitXProgram);
    Assert.AreEqual('C:\Src\App.Tests.dproj', TestFor(mFiles, 'C:\Src\App.Tests.dproj', mCandidates),
      'ein DUnitX-Programm ist sein eigenes Testprojekt');
  finally
    mFiles.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestProjectNeedsDUnitX;
var
  mFiles: TFakeFiles;
  mCandidates: TArray<string>;
begin
  mFiles := TFakeFiles.Create;
  try
    mFiles.Add('C:\Src\App.dpr', cPlainProgram);
    // Passender Name, aber kein DUnitX (z. B. DUnit oder ein Werkzeug).
    mFiles.Add('C:\Src\App.Test.dproj', '');
    mFiles.Add('C:\Src\App.Test.dpr', cPlainProgram);
    Assert.AreEqual('', TestFor(mFiles, 'C:\Src\App.dproj', mCandidates));
    Assert.AreEqual(0, Integer(Length(mCandidates)));
    // .dproj ohne .dpr zählt nicht.
    mFiles.Add('C:\Src\AppTests.dproj', '');
    Assert.AreEqual('', TestFor(mFiles, 'C:\Src\App.dproj', mCandidates));
    Assert.AreEqual('', TestFor(mFiles, '', mCandidates));
  finally
    mFiles.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestProjectOfGroup;
var
  mFiles: TFakeFiles;
  mCandidates: TArray<string>;
begin
  mFiles := TFakeFiles.Create;
  try
    mFiles.Add('C:\Src\Suite.groupproj',
      '<Project>'#10'  <ItemGroup>'#10'    <Projects Include="App\App.dproj">'#10'    </Projects>'#10 +
      '    <Projects Include="Tests\Core.Tests.dproj"/>'#10'  </ItemGroup>'#10'</Project>');
    mFiles.Add('C:\Src\App\App.dpr', cPlainProgram);
    mFiles.Add('C:\Src\Tests\Core.Tests.dpr', cDUnitXProgram);
    Assert.AreEqual('C:\Src\Tests\Core.Tests.dproj', TestFor(mFiles, 'C:\Src\Suite.groupproj', mCandidates),
      'einziges DUnitX-Projekt der Gruppe');
    // Zwei Testprojekte: das nach der Gruppe benannte.
    mFiles.Names[0] := 'C:\Src\Old.groupproj';
    mFiles.Add('C:\Src\Suite.groupproj',
      '<Projects Include="Tests\Core.Tests.dproj"/>'#10'<Projects Include="Tests\Suite.Tests.dproj"/>');
    mFiles.Add('C:\Src\Tests\Suite.Tests.dpr', cDUnitXProgram);
    Assert.AreEqual('C:\Src\Tests\Suite.Tests.dproj', TestFor(mFiles, 'C:\Src\Suite.groupproj', mCandidates));
    Assert.AreEqual(2, Integer(Length(mCandidates)));
    // Zwei ohne passenden Namen: die IDE fragt.
    mFiles.Add('C:\Src\Other.groupproj',
      '<Projects Include="Tests\Core.Tests.dproj"/>'#10'<Projects Include="Tests\Suite.Tests.dproj"/>');
    Assert.AreEqual('', TestFor(mFiles, 'C:\Src\Other.groupproj', mCandidates));
    Assert.AreEqual(2, Integer(Length(mCandidates)), 'Kandidaten für die Auswahl');
  finally
    mFiles.Free;
  end;
end;

procedure TAtlasWelcomeQuickActionsTests.TestCandidatesOrder;
var
  mCandidates: TArray<string>;
begin
  mCandidates := TAtlasWelcomeQuickActions.TestCandidates('C:\Src\App\App.dproj');
  Assert.AreEqual(20, Integer(Length(mCandidates)), '4 Muster in 5 Ordnern');
  Assert.AreEqual('C:\Src\App\App.Tests.dproj', mCandidates[0]);
  Assert.AreEqual('C:\Src\App\AppTests.dproj', mCandidates[1]);
  Assert.AreEqual('C:\Src\App\Tests\App.Tests.dproj', mCandidates[4]);
  Assert.AreEqual('C:\Src\Tests\App.Tests.dproj', mCandidates[12]);
  Assert.AreEqual('C:\Src\Test\AppTest.dproj', mCandidates[19]);
end;

procedure TAtlasWelcomeQuickActionsTests.TargetsFromDproj;
const
  cDproj =
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
  mTargets: TAtlasProjectTargets;
begin
  mTargets := TAtlasWelcomeQuickActions.ReadTargets(cDproj);
  Assert.AreEqual(2, Integer(Length(mTargets.Configurations)), 'ohne Base, jede einmal');
  Assert.AreEqual('Debug', mTargets.Configurations[0]);
  Assert.AreEqual('Release', mTargets.Configurations[1]);
  Assert.AreEqual(2, Integer(Length(mTargets.Platforms)), 'nur eingeschaltete Plattformen');
  Assert.AreEqual('Win32', mTargets.Platforms[0]);
  Assert.AreEqual('Win64', mTargets.Platforms[1]);
  Assert.IsTrue(mTargets.HasConfiguration('release'));
  Assert.IsFalse(mTargets.HasPlatform('Linux64'));
  mTargets := TAtlasWelcomeQuickActions.ReadTargets('');
  Assert.AreEqual(0, Integer(Length(mTargets.Configurations)));
  Assert.AreEqual(0, Integer(Length(mTargets.Platforms)));
end;

procedure TAtlasWelcomeQuickActionsTests.ChooseTargetPrefersLastUsed;
var
  mTargets: TAtlasProjectTargets;
  mConfiguration, mPlatform: string;
begin
  mTargets.Configurations := ['Debug', 'Release'];
  mTargets.Platforms := ['Win32', 'Win64'];
  TAtlasWelcomeQuickActions.ChooseTarget(mTargets, 'debug', 'WIN64', mConfiguration, mPlatform);
  Assert.AreEqual('Debug', mConfiguration, 'Schreibweise der Datei');
  Assert.AreEqual('Win64', mPlatform);
  TAtlasWelcomeQuickActions.ChooseTarget(mTargets, 'Profiling', '', mConfiguration, mPlatform);
  Assert.AreEqual('', mConfiguration, 'unbekannt: aktive der IDE');
  Assert.AreEqual('', mPlatform);
end;

procedure TAtlasWelcomeQuickActionsTests.GroupProjectsResolvePaths;
var
  mProjects: TArray<string>;
begin
  mProjects := TAtlasWelcomeQuickActions.GroupProjects(
    '<Projects Include="App\App.dproj"/>'#10'<Projects Include="..\Lib\Lib.dproj"/>'#10 +
    '<Projects Include="D:\Other\X.dproj"/>'#10'<Projects Include="App\App.dproj"/>', 'C:\Src\Group');
  Assert.AreEqual(3, Integer(Length(mProjects)));
  Assert.AreEqual('C:\Src\Group\App\App.dproj', mProjects[0]);
  Assert.AreEqual('C:\Src\Lib\Lib.dproj', mProjects[1]);
  Assert.AreEqual('D:\Other\X.dproj', mProjects[2]);
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
  mFileName, mParameters: string;
begin
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('', 'C:\Src\App', mFileName, mParameters));
  Assert.AreEqual('wt.exe', mFileName, 'Vorgabe Windows-Terminal');
  Assert.AreEqual('-d "C:\Src\App"', mParameters);
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('cmd.exe', 'C:\', mFileName, mParameters));
  Assert.AreEqual('/K cd /d "C:\."', mParameters, 'Backslash vor dem Anführungszeichen');
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('C:\Tools\pwsh.exe', 'C:\O''Neil', mFileName, mParameters));
  Assert.AreEqual('C:\Tools\pwsh.exe', mFileName);
  Assert.AreEqual('-NoExit -Command Set-Location -LiteralPath ''C:\O''''Neil''', mParameters);
  Assert.IsTrue(TAtlasWelcomeQuickActions.ConsoleCommand('ConEmu64.exe', 'C:\Src', mFileName, mParameters));
  Assert.AreEqual('', mParameters, 'anderes Programm: nur Arbeitsordner');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ConsoleCommand('wt.exe', '', mFileName, mParameters));
end;

procedure TAtlasWelcomeQuickActionsTests.KeysBuildAndTest;
var
  mAction: TAtlasQuickAction;
  mAll: TAtlasQuickActions;
begin
  mAll := TAtlasWelcomeQuickActions.ParseItems(TAtlasWelcomeQuickActions.cDefaultItems);
  Assert.IsTrue(TAtlasWelcomeQuickActions.ActionForKey($4042, $4042, $4054, mAll, mAction));
  Assert.IsTrue(mAction = TAtlasQuickAction.Build, 'Strg+B');
  Assert.IsTrue(TAtlasWelcomeQuickActions.ActionForKey($4054, $4042, $4054, mAll, mAction));
  Assert.IsTrue(mAction = TAtlasQuickAction.Tests, 'Strg+T');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ActionForKey($4054, $4042, $4054, [TAtlasQuickAction.Build], mAction),
    'Knopf nicht eingestellt');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ActionForKey($4042, 0, $4054, mAll, mAction), 'Taste abgeschaltet');
  Assert.IsFalse(TAtlasWelcomeQuickActions.ActionForKey(0, 0, 0, mAll, mAction));
  // Geänderte Taste (#399).
  Assert.IsTrue(TAtlasWelcomeQuickActions.ActionForKey($6042, $6042, $4054, mAll, mAction));
  Assert.IsTrue(mAction = TAtlasQuickAction.Build);
end;

procedure TAtlasWelcomeQuickActionsTests.ArrowsMoveRowAndButton;
var
  mButtons: TAtlasQuickActionButtons;
begin
  Assert.AreEqual(-1, TAtlasWelcomeQuickActions.MoveRow(0, 1, 0));
  Assert.AreEqual(0, TAtlasWelcomeQuickActions.MoveRow(-1, 1, 3), 'ohne Auswahl: erste Zeile');
  Assert.AreEqual(2, TAtlasWelcomeQuickActions.MoveRow(1, 1, 3));
  Assert.AreEqual(2, TAtlasWelcomeQuickActions.MoveRow(2, 1, 3), 'bleibt am Ende');
  Assert.AreEqual(0, TAtlasWelcomeQuickActions.MoveRow(0, -1, 3));
  // Alle Knöpfe, Pull (Index 3) wegen lokaler Änderungen gesperrt.
  mButtons := TAtlasWelcomeQuickActions.Buttons(TAtlasWelcomeQuickActions.ParseItems(
    TAtlasWelcomeQuickActions.cDefaultItems), Vcs(True, 'git', 1), False);
  Assert.AreEqual(7, Integer(Length(mButtons)));
  Assert.AreEqual(0, TAtlasWelcomeQuickActions.MoveButton(mButtons, -1, 1), 'rechts: erster Knopf');
  Assert.AreEqual(6, TAtlasWelcomeQuickActions.MoveButton(mButtons, -1, -1), 'links: letzter Knopf');
  Assert.AreEqual(4, TAtlasWelcomeQuickActions.MoveButton(mButtons, 2, 1), 'überspringt gesperrten Pull');
  Assert.AreEqual(2, TAtlasWelcomeQuickActions.MoveButton(mButtons, 4, -1));
  Assert.AreEqual(6, TAtlasWelcomeQuickActions.MoveButton(mButtons, 6, 1), 'bleibt am Ende');
  Assert.AreEqual(-1, TAtlasWelcomeQuickActions.MoveButton(nil, -1, 1));
end;

procedure TAtlasWelcomeQuickActionsTests.StateElapsedSeconds;
var
  mState: TAtlasQuickActionState;
begin
  mState := TAtlasQuickActionState.Idle;
  Assert.IsFalse(mState.Running);
  Assert.AreEqual(0, mState.ElapsedSeconds(5000));
  mState := TAtlasQuickActionState.Started(TAtlasQuickAction.Build, 1000);
  Assert.IsTrue(mState.Running);
  Assert.IsTrue(mState.Action = TAtlasQuickAction.Build);
  Assert.AreEqual(12, mState.ElapsedSeconds(13500), '„baut … 12 s“');
  Assert.AreEqual(0, mState.ElapsedSeconds(500));
end;

procedure TAtlasWelcomeQuickActionsTests.AfterPullDecidesPhaseAndNote;
var
  mStart, mState: TAtlasQuickActionState;
  mNote: TAtlasPullNote;
begin
  mStart := TAtlasQuickActionState.Started(TAtlasQuickAction.Pull, 1000);
  mStart.Detail := 'alt';
  mState := mStart.AfterPull(TAtlasPullOutcome.Updated, TAtlasVcsOutcome.Ok, mNote);
  Assert.IsTrue(mState.Phase = TAtlasQuickActionPhase.Succeeded);
  Assert.IsTrue(mState.Pull = TAtlasPullOutcome.Updated);
  Assert.IsTrue(mNote = TAtlasPullNote.None);
  Assert.AreEqual('', mState.Detail, 'altes Detail weg');
  Assert.AreEqual(UInt64(1000), mState.StartedMs, 'Beginn bleibt');
  mState := mStart.AfterPull(TAtlasPullOutcome.UpToDate, TAtlasVcsOutcome.Ok, mNote);
  Assert.IsTrue(mState.Phase = TAtlasQuickActionPhase.Succeeded);
  mState := mStart.AfterPull(TAtlasPullOutcome.Blocked, TAtlasVcsOutcome.Ok, mNote);
  Assert.IsTrue(mState.Phase = TAtlasQuickActionPhase.Failed);
  Assert.IsTrue(mNote = TAtlasPullNote.LocalChanges);
  mState := mStart.AfterPull(TAtlasPullOutcome.NoWorkingCopy, TAtlasVcsOutcome.NoWorkingCopy, mNote);
  Assert.IsTrue(mNote = TAtlasPullNote.NoWorkingCopy);
  mState := mStart.AfterPull(TAtlasPullOutcome.Failed, TAtlasVcsOutcome.LoginNeeded, mNote);
  Assert.IsTrue(mNote = TAtlasPullNote.Login);
  Assert.AreEqual('', mState.Detail, 'Text der Anmeldung setzt die IDE');
  mState := mStart.AfterPull(TAtlasPullOutcome.Failed, TAtlasVcsOutcome.TimedOut, mNote);
  Assert.IsTrue(mState.Phase = TAtlasQuickActionPhase.Failed);
  Assert.IsTrue(mNote = TAtlasPullNote.Failed);
  Assert.AreEqual(AtlasVcsOutcomeName(TAtlasVcsOutcome.TimedOut), mState.Detail);
end;

procedure TAtlasWelcomeQuickActionsTests.TestEndedWhenStoppedOrGraceOver;
var
  mState: TAtlasQuickActionState;
begin
  mState := TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, 1000);
  Assert.IsFalse(mState.TestEnded(1500, 1000), 'läuft, Schonzeit nicht um');
  Assert.IsTrue(mState.TestEnded(2000, 1000), 'Schonzeit um');
  mState.Phase := TAtlasQuickActionPhase.Succeeded;
  Assert.IsTrue(mState.TestEnded(1500, 1000), 'läuft nicht mehr');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeQuickActionsTests);

end.
