unit Atlas.UI.Build.SettingsSection.Tests;

// Abschnitt „Compiler“ des Moduls Build-Werkzeuge (#1456): Compiler-Schalter (#558), Startprofile (#575), Bauen
// beim Öffnen (#1293) und Projektaufgaben (#900); Laden und Speichern über die Seite (vorher in den Tests der
// Seite von Base).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Build.SettingsSection;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TBuildSettingsSectionTests = class
  private
    FSection: TAtlasBuildSettingsSection;
    FSectionRef: IAtlasSettingsSection;
    FRegistration: IAtlasRegistration;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SwitchesAndStartProfilesRoundTrip;
    /// <summary>„Bauen beim Öffnen“ fasst build.onOpen und build.onOpenKind zusammen; „nicht bauen“ behält die
    /// Art.</summary>
    [Test]
    procedure OpenBuildRoundTrip;
    [Test]
    procedure TasksRoundTrip;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport;

procedure TBuildSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TBuildSettingsSectionTests.Setup;
begin
  FSection := TAtlasBuildSettingsSection.Create;
  FSectionRef := FSection;
  FRegistration := ProvideSection(FSectionRef);
end;

procedure TBuildSettingsSectionTests.TearDown;
begin
  FRegistration.Revoke;
  FRegistration := nil;
  FSection := nil;
  FSectionRef := nil;
end;

procedure TBuildSettingsSectionTests.SwitchesAndStartProfilesRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'BuildToolsEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'BuildCompilerSwitches').Checked);
    Assert.IsFalse(CheckOf(mPage, 'BuildSwitchesInStatusBar').Checked);
    Assert.IsTrue(CheckOf(mPage, 'StartProfiles').Checked, 'Startprofile standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'StartProfilesStatusField').Checked, 'Statusfeld standardmäßig an');
    CheckOf(mPage, 'BuildCompilerSwitches').Checked := False;
    CheckOf(mPage, 'BuildSwitchesInStatusBar').Checked := True;
    CheckOf(mPage, 'StartProfiles').Checked := False;
    CheckOf(mPage, 'StartProfilesStatusField').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.BuildCompilerSwitches);
    Assert.IsTrue(mSaved.BuildSwitchesInStatusBar);
    Assert.IsFalse(mSaved.StartProfiles);
    Assert.IsFalse(mSaved.StartProfilesStatusField);
    mSaved.StartProfilesStatusField := True;
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'StartProfiles').Checked);
    Assert.IsTrue(CheckOf(mPage, 'StartProfilesStatusField').Checked);
  finally
    mPage.Free;
  end;
end;

procedure TBuildSettingsSectionTests.OpenBuildRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, FSection.OpenBuildChoice.Choice, 'standardmäßig nicht bauen');
    Assert.AreEqual(0, ChoiceOf(mPage, 'BuildOnOpenScope').Choice, 'alle Projekte');
    Assert.AreEqual('3000', EditOf(mPage, 'BuildOnOpenDelayMs').Text);
    Assert.AreEqual('', FSection.OpenBuildExcludeEdit.Text);
    Assert.AreEqual('', EditOf(mPage, 'BuildOnOpenConfig').Text);
    Assert.AreEqual(0, ChoiceOf(mPage, 'BuildOnOpenPlatform').Choice, 'wie im Projekt');
    // Erzeugen, nur das aktive Projekt, 5 s, ein Package ausgeschlossen.
    FSection.OpenBuildChoice.Choice := 3;
    ChoiceOf(mPage, 'BuildOnOpenScope').Choice := 1;
    EditOf(mPage, 'BuildOnOpenDelayMs').Text := '5000';
    FSection.OpenBuildExcludeEdit.Text := 'Atlas.IDE.Expert.dproj';
    EditOf(mPage, 'BuildOnOpenConfig').Text := ' Debug ';
    ChoiceOf(mPage, 'BuildOnOpenPlatform').Choice := 2;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.BuildOnOpen);
    Assert.AreEqual('build', mSaved.BuildOnOpenKind);
    Assert.AreEqual('active', mSaved.BuildOnOpenScope);
    Assert.AreEqual(5000, mSaved.BuildOnOpenDelayMs);
    Assert.AreEqual('Atlas.IDE.Expert', mSaved.BuildOnOpenExclude);
    Assert.AreEqual('Debug', mSaved.BuildOnOpenConfig);
    Assert.AreEqual('Win64', mSaved.BuildOnOpenPlatform);
    mPage.LoadFrom(mSaved);
    Assert.AreEqual('Debug', EditOf(mPage, 'BuildOnOpenConfig').Text);
    Assert.AreEqual(3, FSection.OpenBuildChoice.Choice);
    Assert.AreEqual(1, ChoiceOf(mPage, 'BuildOnOpenScope').Choice);
    // Syntaxprüfung; „nicht bauen“ schaltet ab und behält die Art.
    FSection.OpenBuildChoice.Choice := 1;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('check', mSaved.BuildOnOpenKind);
    FSection.OpenBuildChoice.Choice := 0;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.BuildOnOpen, 'abschaltbar');
    Assert.AreEqual('check', mSaved.BuildOnOpenKind);
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(0, FSection.OpenBuildChoice.Choice);
  finally
    mPage.Free;
  end;
end;

procedure TBuildSettingsSectionTests.TasksRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'TasksEnabled').Checked, 'standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'TasksProblemsFromOutput').Checked);
    Assert.AreEqual(0, ChoiceOf(mPage, 'TasksBeforeBuild').Choice, 'vor dem Build: aus');
    Assert.IsTrue(CheckOf(mPage, 'TasksSaveBeforeRun').Checked);
    Assert.IsFalse(CheckOf(mPage, 'TasksRunChecksParallel').Checked);
    Assert.IsFalse(CheckOf(mPage, 'TasksOnlyFindings').Checked);
    CheckOf(mPage, 'TasksEnabled').Checked := False;
    CheckOf(mPage, 'TasksProblemsFromOutput').Checked := False;
    ChoiceOf(mPage, 'TasksBeforeBuild').Choice := 2;
    CheckOf(mPage, 'TasksSaveBeforeRun').Checked := False;
    CheckOf(mPage, 'TasksRunChecksParallel').Checked := True;
    CheckOf(mPage, 'TasksOnlyFindings').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.TasksEnabled, 'abschaltbar');
    Assert.IsFalse(mSaved.TasksProblemsFromOutput);
    Assert.AreEqual('block', mSaved.TasksBeforeBuild);
    Assert.IsFalse(mSaved.TasksSaveBeforeRun);
    Assert.IsTrue(mSaved.TasksRunChecksParallel);
    Assert.IsTrue(mSaved.TasksOnlyFindings);
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(2, ChoiceOf(mPage, 'TasksBeforeBuild').Choice);
    Assert.IsFalse(CheckOf(mPage, 'TasksEnabled').Checked);
    ChoiceOf(mPage, 'TasksBeforeBuild').Choice := 1;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('warn', mSaved.TasksBeforeBuild);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildSettingsSectionTests);

end.
