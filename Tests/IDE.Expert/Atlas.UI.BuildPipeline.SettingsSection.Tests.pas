unit Atlas.UI.BuildPipeline.SettingsSection.Tests;

// Abschnitte des Moduls Build-Pipeline (#1456): Compiler (#261, #529, #530) und Reiter „Release-Build“ (#533);
// Laden und Speichern über die Seite (vorher in den Tests der Seite von Base).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.BuildPipeline.SettingsSection;

type
  [TestFixture]
  [Category('Atlas.IDE.BuildPipeline')]
  TBuildPipelineSettingsSectionTests = class
  private
    FRelease: TAtlasBuildPipelineReleaseSection;
    FReleaseRef: IAtlasSettingsSection;
    FRegistrations: TArray<IAtlasRegistration>;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Builds für Claude Code, 0 Hinweise, Zusammenfassung, build.gate samt Zeitlimit (untere Grenze) und
    /// Warnungen als Fehler in einheitlicher Form.</summary>
    [Test]
    procedure CompilerRoundTrip;
    /// <summary>Wächter, Konfigurationen und Prüfungen samt Sollwert; alle Prüfungen teilen build.releaseChecks.
    /// </summary>
    [Test]
    procedure ReleaseRoundTrip;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Build.PipelineSettings,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport;

procedure TBuildPipelineSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TBuildPipelineSettingsSectionTests.Setup;
begin
  FRelease := TAtlasBuildPipelineReleaseSection.Create;
  FReleaseRef := FRelease;
  FRegistrations := ProvideSections([TAtlasBuildPipelineCompilerSection]) + [ProvideSection(FReleaseRef)];
end;

procedure TBuildPipelineSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
  FRelease := nil;
  FReleaseRef := nil;
end;

procedure TBuildPipelineSettingsSectionTests.CompilerRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'BuildPipelineEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'McpBuild').Checked, 'Builds für Claude Code standardmäßig an');
    Assert.IsFalse(CheckOf(mPage, 'BuildZeroHints').Checked);
    Assert.IsTrue(CheckOf(mPage, 'BuildSummary').Checked);
    Assert.AreEqual(0, ChoiceOf(mPage, 'BuildGate').Choice, 'build.gate off');
    Assert.AreEqual('300', EditOf(mPage, 'BuildGateTimeoutMs').Text);
    Assert.AreEqual('', EditOf(mPage, 'BuildWarningsAsErrors').Text);
    CheckOf(mPage, 'McpBuild').Checked := False;
    CheckOf(mPage, 'BuildZeroHints').Checked := True;
    CheckOf(mPage, 'BuildSummary').Checked := False;
    ChoiceOf(mPage, 'BuildGate').Choice := 2;
    EditOf(mPage, 'BuildGateTimeoutMs').Text := '20';
    EditOf(mPage, 'BuildWarningsAsErrors').Text := 'w1035 h2164';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.McpBuild, 'abschaltbar');
    Assert.IsTrue(mSaved.BuildZeroHints);
    Assert.IsFalse(mSaved.BuildSummary);
    Assert.AreEqual('block', mSaved.BuildGate);
    Assert.AreEqual(50, mSaved.BuildGateTimeoutMs, 'auf die untere Grenze gehoben');
    Assert.AreEqual('W1035, H2164', mSaved.BuildWarningsAsErrors);
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'McpBuild').Checked);
    Assert.AreEqual(2, ChoiceOf(mPage, 'BuildGate').Choice);
    Assert.AreEqual('W1035, H2164', EditOf(mPage, 'BuildWarningsAsErrors').Text);
  finally
    mPage.Free;
  end;
end;

procedure TBuildPipelineSettingsSectionTests.ReleaseRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
  mChecks: TAtlasReleaseChecks;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'ReleaseGuard').Checked, 'Wächter standardmäßig an');
    Assert.AreEqual('Release', FRelease.ConfigsEdit.Text);
    Assert.IsTrue(FRelease.CheckBox(TAtlasReleaseCheck.DebugDefine).Checked);
    Assert.IsNull(FRelease.CheckChoice(TAtlasReleaseCheck.DebugDefine));
    Assert.IsNull(FRelease.CheckBox(TAtlasReleaseCheck.RangeChecks));
    Assert.AreEqual(1, FRelease.CheckChoice(TAtlasReleaseCheck.RangeChecks).Choice, 'prüfen, Soll aus');
    CheckOf(mPage, 'ReleaseGuard').Checked := False;
    FRelease.ConfigsEdit.Text := 'Release; Ship ,ship';
    FRelease.CheckBox(TAtlasReleaseCheck.OutputFolder).Checked := False;
    FRelease.CheckChoice(TAtlasReleaseCheck.Assertions).Choice := 0;
    FRelease.CheckChoice(TAtlasReleaseCheck.StackFrames).Choice := 2;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.ReleaseGuard);
    Assert.AreEqual('Release, Ship', mSaved.ReleaseConfigs);
    mChecks := TAtlasReleaseChecks.Parse(mSaved.ReleaseChecks);
    Assert.IsFalse(mChecks.Items[TAtlasReleaseCheck.OutputFolder].Enabled);
    Assert.IsFalse(mChecks.Items[TAtlasReleaseCheck.Assertions].Enabled);
    Assert.IsTrue(mChecks.Items[TAtlasReleaseCheck.StackFrames].Enabled);
    Assert.IsTrue(mChecks.Items[TAtlasReleaseCheck.StackFrames].Expected);
    Assert.IsTrue(mChecks.Items[TAtlasReleaseCheck.DebugDefine].Enabled);
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'ReleaseGuard').Checked);
    Assert.AreEqual('Release, Ship', FRelease.ConfigsEdit.Text);
    Assert.AreEqual(0, FRelease.CheckChoice(TAtlasReleaseCheck.Assertions).Choice);
    Assert.AreEqual(2, FRelease.CheckChoice(TAtlasReleaseCheck.StackFrames).Choice);
    Assert.IsFalse(FRelease.CheckBox(TAtlasReleaseCheck.OutputFolder).Checked);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildPipelineSettingsSectionTests);

end.
