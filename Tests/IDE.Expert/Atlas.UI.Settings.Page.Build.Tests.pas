unit Atlas.UI.Settings.Page.Build.Tests;

// Tests der Einstellungsseite: Seiten für Build, Tests und Debugger.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Seiten für Build, Tests und Debugger.</summary>
  [TestFixture]
  TAtlasSettingsPageBuildTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>#261: Schalter „Builds für Claude Code“ auf dem Reiter Compiler.</summary>
    [Test]
    procedure McpBuildRoundTrip;
    /// <summary>Beim Öffnen bauen: Auswahl, Umfang, Wartezeit und Ausschluss hin und zurück; standardmäßig aus.
    /// </summary>
    [Test]
    procedure OpenBuildRoundTrip;
    /// <summary>#900: Projektaufgaben auf dem Reiter Compiler hin und zurück, Vorgaben wie im Issue.</summary>
    [Test]
    procedure TasksRoundTrip;
    [Test]
    procedure ListModeRoundTrip;
    /// <summary>#69: Code Lens auf dem Reiter Editor, Tests ausführen, vorher bauen, nach dem Build und
    /// build.zeroHints (#530) auf dem Reiter Compiler.</summary>
    [Test]
    procedure TestRunRoundTrip;
    /// <summary>#575: Startprofile und ihr Feld in der Statusleiste auf dem Reiter Compiler.</summary>
    [Test]
    procedure StartProfilesRoundTrip;
    /// <summary>Reiter „Release-Build“ (#533): Schalter, build.gate, Konfigurationen und Prüfungen samt Sollwert.
    /// </summary>
    [Test]
    procedure ReleaseGuardRoundTrip;
    /// <summary>#585: Test debuggen und Haltepunkt am Anfang auf dem Reiter Debuggen.</summary>
    [Test]
    procedure TestDebugRoundTrip;
    /// <summary>#786: Alt+F11 und Umschalt+F12 auf der Seite „Units suchen“.</summary>
    [Test]
    procedure UseUnitAndFormsDialogsRoundTrip;
    [Test]
    procedure DebugVisualizersRoundTrip;
    [Test]
    procedure DebugDisplayRulesRoundTrip;
    [Test]
    procedure DebugStepIntoTargetRoundTrip;
    [Test]
    procedure DebugBreakOnNextEventRoundTrip;
    [Test]
    procedure DebugStepFiltersRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Text.StepFilter,
  Atlas.Core.Build.PipelineSettings,
  Atlas.UI.Settings.Page,
  Vcl.Menus,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Settings.Page.Build,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.Debug,
  Atlas.UI.Settings.Page.Release,
  Atlas.UI.Settings.Page.Tasks;

procedure TAtlasSettingsPageBuildTests.WarmUp;
begin
  WarmUpSettingsPage;
end;
procedure TAtlasSettingsPageBuildTests.TestRunRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'CodeLensTests').Checked, 'Code Lens standardmäßig an');
    Assert.IsTrue(CheckOf(Page, 'TestRun').Checked);
    Assert.IsTrue(CheckOf(Page, 'TestsBuildFirst').Checked);
    Assert.IsFalse(CheckOf(Page, 'TestsAfterBuild').Checked);
    Assert.IsFalse(CheckOf(Page, 'BuildZeroHints').Checked);
    Assert.IsTrue(CheckOf(Page, 'ShowInterfaceCost').Checked, 'Kosten einer interface-Änderung standardmäßig an (#554)');
    Assert.IsTrue(CheckOf(Page, 'BuildCompilerSwitches').Checked);
    Assert.IsFalse(CheckOf(Page, 'BuildSwitchesInStatusBar').Checked);
    CheckOf(Page, 'CodeLensTests').Checked := False;
    CheckOf(Page, 'TestRun').Checked := False;
    CheckOf(Page, 'TestsBuildFirst').Checked := False;
    CheckOf(Page, 'TestsAfterBuild').Checked := True;
    CheckOf(Page, 'BuildZeroHints').Checked := True;
    CheckOf(Page, 'ShowInterfaceCost').Checked := False;
    CheckOf(Page, 'BuildCompilerSwitches').Checked := False;
    CheckOf(Page, 'BuildSwitchesInStatusBar').Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.CodeLensTests);
    Assert.IsFalse(Saved.TestRun);
    Assert.IsFalse(Saved.TestsBuildFirst);
    Assert.IsTrue(Saved.TestsAfterBuild);
    Assert.IsTrue(Saved.BuildZeroHints);
    Assert.IsFalse(Saved.ShowInterfaceCost);
    Assert.IsFalse(Saved.BuildCompilerSwitches);
    Assert.IsTrue(Saved.BuildSwitchesInStatusBar);
    Page.LoadFrom(Saved);
    Assert.IsFalse(CheckOf(Page, 'CodeLensTests').Checked);
    Assert.IsFalse(CheckOf(Page, 'ShowInterfaceCost').Checked);
    Assert.IsTrue(CheckOf(Page, 'TestsAfterBuild').Checked);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.ReleaseGuardRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
  Checks: TAtlasReleaseChecks;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.Part<TAtlasSettingsReleasePart>.ReleaseGuardCheck.Checked, 'Wächter standardmäßig an');
    Assert.AreEqual(0, Page.Part<TAtlasSettingsBuildPart>.BuildGateChoice.Choice, 'build.gate off');
    Assert.AreEqual('300', Page.Part<TAtlasSettingsBuildPart>.BuildGateTimeoutEdit.Text, 'build.gateTimeoutMs (#529)');
    Assert.IsTrue(CheckOf(Page, 'BuildSummary').Checked, 'build.summary (#530)');
    Assert.AreEqual('', Page.Part<TAtlasSettingsBuildPart>.BuildWarningsAsErrorsEdit.Text, 'build.warningsAsErrors (#530)');
    Assert.AreEqual('Release', Page.Part<TAtlasSettingsReleasePart>.ReleaseConfigsEdit.Text);
    Assert.IsTrue(Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckBox(TAtlasReleaseCheck.DebugDefine).Checked);
    Assert.IsNull(Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckChoice(TAtlasReleaseCheck.DebugDefine));
    Assert.IsNull(Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckBox(TAtlasReleaseCheck.RangeChecks));
    Assert.AreEqual(1, Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckChoice(TAtlasReleaseCheck.RangeChecks).Choice, 'prüfen, Soll aus');
    Page.Part<TAtlasSettingsReleasePart>.ReleaseGuardCheck.Checked := False;
    Page.Part<TAtlasSettingsBuildPart>.BuildGateChoice.Choice := 2;
    Page.Part<TAtlasSettingsBuildPart>.BuildGateTimeoutEdit.Text := '20';
    CheckOf(Page, 'BuildSummary').Checked := False;
    Page.Part<TAtlasSettingsBuildPart>.BuildWarningsAsErrorsEdit.Text := 'w1035 h2164';
    Page.Part<TAtlasSettingsReleasePart>.ReleaseConfigsEdit.Text := 'Release; Ship ,ship';
    Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckBox(TAtlasReleaseCheck.OutputFolder).Checked := False;
    Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckChoice(TAtlasReleaseCheck.Assertions).Choice := 0;
    Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckChoice(TAtlasReleaseCheck.StackFrames).Choice := 2;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ReleaseGuard);
    Assert.AreEqual('block', Saved.BuildGate);
    Assert.AreEqual(50, Saved.BuildGateTimeoutMs, 'auf die untere Grenze gehoben');
    Assert.IsFalse(Saved.BuildSummary);
    Assert.AreEqual('W1035, H2164', Saved.BuildWarningsAsErrors);
    Assert.AreEqual('Release, Ship', Saved.ReleaseConfigs);
    Checks := TAtlasReleaseChecks.Parse(Saved.ReleaseChecks);
    Assert.IsFalse(Checks.Items[TAtlasReleaseCheck.OutputFolder].Enabled);
    Assert.IsFalse(Checks.Items[TAtlasReleaseCheck.Assertions].Enabled);
    Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.StackFrames].Enabled);
    Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.StackFrames].Expected);
    Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.DebugDefine].Enabled);
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.Part<TAtlasSettingsReleasePart>.ReleaseGuardCheck.Checked);
    Assert.AreEqual(2, Page.Part<TAtlasSettingsBuildPart>.BuildGateChoice.Choice);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckChoice(TAtlasReleaseCheck.Assertions).Choice);
    Assert.AreEqual(2, Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckChoice(TAtlasReleaseCheck.StackFrames).Choice);
    Assert.IsFalse(Page.Part<TAtlasSettingsReleasePart>.ReleaseCheckBox(TAtlasReleaseCheck.OutputFolder).Checked);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.StartProfilesRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'StartProfiles').Checked, 'Startprofile standardmäßig an');
    Assert.IsTrue(CheckOf(Page, 'StartProfilesStatusField').Checked, 'Statusfeld standardmäßig an');
    CheckOf(Page, 'StartProfiles').Checked := False;
    CheckOf(Page, 'StartProfilesStatusField').Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.StartProfiles);
    Assert.IsFalse(Saved.StartProfilesStatusField);
    Saved.StartProfilesStatusField := True;
    Page.LoadFrom(Saved);
    Assert.IsFalse(CheckOf(Page, 'StartProfiles').Checked);
    Assert.IsTrue(CheckOf(Page, 'StartProfilesStatusField').Checked);
  finally
    Page.Free;
  end;
end;
/// <summary>Debugger-Schalter der Seite mit den Vorgaben.</summary>
procedure AssertDebugPageDefaults(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(CheckOf(APage, 'TestDebug').Checked, 'Test debuggen standardmäßig an');
  Assert.IsTrue(CheckOf(APage, 'TestBreakAtStart').Checked, 'Haltepunkt am Anfang standardmäßig an');
  Assert.IsTrue(CheckOf(APage, 'DebugHoverValues').Checked, 'Werte im Hover standardmäßig an (#891)');
  Assert.IsTrue(CheckOf(APage, 'DebugExplainUnavailable').Checked, 'debug.explainUnavailable (#840)');
  Assert.IsTrue(CheckOf(APage, 'DebugCompletionInDialogs').Checked, 'debug.completionInDialogs (#538)');
  Assert.IsTrue(CheckOf(APage, 'DebugEvaluateWindow').Checked, 'debug.evaluateWindow (#784)');
  Assert.IsTrue(CheckOf(APage, 'DebugEvaluateReplaceCtrlF7').Checked, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsTrue(CheckOf(APage, 'DebugExplainAccessViolation').Checked, 'debug.explainAccessViolation (#865)');
  Assert.IsFalse(APage.Part<TAtlasSettingsDebugPart>.DebugExplainAccessViolationAllowCallsCheck.Checked,
    'debug.explainAccessViolation.allowCalls (#865)');
  Assert.IsTrue(CheckOf(APage, 'DebugExceptionHistory').Checked, 'debug.exceptionHistory (#517)');
  Assert.IsTrue(CheckOf(APage, 'DebugJustMyCode').Checked, 'debug.justMyCode (#578)');
  Assert.IsFalse(CheckOf(APage, 'DebugExceptionBanner').Checked, 'debug.exceptionBanner (#783)');
  Assert.IsTrue(APage.Part<TAtlasSettingsDebugPart>.DebugExceptionBannerIgnoreAtLocationCheck.Checked,
    'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsTrue(CheckOf(APage, 'DebugInlineValues').Checked, 'debug.inlineValues (#508)');
  Assert.AreEqual('5', EditOf(APage, 'DebugInlineValuesPerLine').Text, 'debug.inlineValuesPerLine (#508)');
end;
/// <summary>Alle Debugger-Schalter der Seite umstellen.</summary>
procedure EditDebugPage(APage: TAtlasSettingsPage);
begin
  CheckOf(APage, 'TestDebug').Checked := False;
  CheckOf(APage, 'TestBreakAtStart').Checked := False;
  CheckOf(APage, 'DebugHoverValues').Checked := False;
  CheckOf(APage, 'DebugExplainUnavailable').Checked := False;
  CheckOf(APage, 'DebugCompletionInDialogs').Checked := False;
  CheckOf(APage, 'DebugEvaluateWindow').Checked := False;
  CheckOf(APage, 'DebugEvaluateReplaceCtrlF7').Checked := False;
  CheckOf(APage, 'DebugExplainAccessViolation').Checked := False;
  APage.Part<TAtlasSettingsDebugPart>.DebugExplainAccessViolationAllowCallsCheck.Checked := True;
  CheckOf(APage, 'DebugExceptionHistory').Checked := False;
  CheckOf(APage, 'DebugJustMyCode').Checked := False;
  CheckOf(APage, 'DebugExceptionBanner').Checked := True;
  APage.Part<TAtlasSettingsDebugPart>.DebugExceptionBannerIgnoreAtLocationCheck.Checked := False;
  CheckOf(APage, 'DebugInlineValues').Checked := False;
  EditOf(APage, 'DebugInlineValuesPerLine').Text := '3';
  APage.Part<TAtlasSettingsDebugPart>.DebugOwnCodeFoldersEdit.Text := 'C:\Komponenten\; ;c:\komponenten';
end;
/// <summary>Umgestellte Debugger-Schalter gespeichert.</summary>
procedure AssertDebugSaved(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.TestDebug);
  Assert.IsFalse(ASaved.TestBreakAtStart);
  Assert.IsFalse(ASaved.DebugHoverValues);
  Assert.IsFalse(ASaved.DebugExplainUnavailable);
  Assert.IsFalse(ASaved.DebugCompletionInDialogs);
  Assert.IsFalse(ASaved.DebugEvaluateWindow);
  Assert.IsFalse(ASaved.DebugEvaluateReplaceCtrlF7);
  Assert.IsFalse(ASaved.DebugExplainAccessViolation);
  Assert.IsTrue(ASaved.DebugExplainAccessViolationAllowCalls);
  Assert.IsFalse(ASaved.DebugExceptionHistory);
  Assert.IsFalse(ASaved.DebugJustMyCode);
  Assert.IsTrue(ASaved.DebugExceptionBanner);
  Assert.IsFalse(ASaved.DebugExceptionBannerIgnoreAtLocation);
  Assert.IsFalse(ASaved.DebugInlineValues);
  Assert.AreEqual(3, ASaved.DebugInlineValuesPerLine);
  Assert.AreEqual('C:\Komponenten', ASaved.DebugOwnCodeFolders, 'bereinigt (#578)');
end;
/// <summary>Debugger-Werte für das erneute Laden zurückstellen.</summary>
procedure SetDebugSaved(var ASaved: TAtlasPluginSettings);
begin
  ASaved.TestBreakAtStart := True;
  ASaved.DebugHoverValues := True;
  ASaved.DebugExplainUnavailable := True;
  ASaved.DebugCompletionInDialogs := True;
  ASaved.DebugEvaluateWindow := True;
  ASaved.DebugEvaluateReplaceCtrlF7 := True;
  ASaved.DebugExplainAccessViolation := True;
  ASaved.DebugExplainAccessViolationAllowCalls := False;
  ASaved.DebugExceptionHistory := True;
  ASaved.DebugJustMyCode := True;
  ASaved.DebugExceptionBanner := False;
  ASaved.DebugExceptionBannerIgnoreAtLocation := True;
  ASaved.DebugInlineValues := True;
end;
/// <summary>Debugger-Schalter der Seite nach erneutem Laden.</summary>
procedure AssertDebugReloaded(APage: TAtlasSettingsPage);
begin
  Assert.IsFalse(CheckOf(APage, 'TestDebug').Checked);
  Assert.IsTrue(CheckOf(APage, 'TestBreakAtStart').Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugHoverValues').Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugExplainUnavailable').Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugCompletionInDialogs').Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugEvaluateWindow').Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugEvaluateReplaceCtrlF7').Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugExplainAccessViolation').Checked);
  Assert.IsFalse(APage.Part<TAtlasSettingsDebugPart>.DebugExplainAccessViolationAllowCallsCheck.Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugExceptionHistory').Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugJustMyCode').Checked);
  Assert.IsFalse(CheckOf(APage, 'DebugExceptionBanner').Checked);
  Assert.IsTrue(APage.Part<TAtlasSettingsDebugPart>.DebugExceptionBannerIgnoreAtLocationCheck.Checked);
  Assert.IsTrue(CheckOf(APage, 'DebugInlineValues').Checked);
end;
procedure TAtlasSettingsPageBuildTests.TestDebugRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    AssertDebugPageDefaults(Page);
    EditDebugPage(Page);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    AssertDebugSaved(Saved);
    SetDebugSaved(Saved);
    Page.LoadFrom(Saved);
    AssertDebugReloaded(Page);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.UseUnitAndFormsDialogsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'UnitSearchReplaceUseUnitDialog').Checked, 'Alt+F11 standardmäßig übernommen');
    Assert.IsTrue(CheckOf(Page, 'UnitSearchReplaceFormsDialog').Checked, 'Umschalt+F12 standardmäßig übernommen');
    CheckOf(Page, 'UnitSearchReplaceUseUnitDialog').Checked := False;
    CheckOf(Page, 'UnitSearchReplaceFormsDialog').Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.UnitSearchReplaceUseUnitDialog);
    Assert.IsFalse(Saved.UnitSearchReplaceFormsDialog);
    Assert.IsTrue(Saved.UnitSearchReplaceIdeDialog, 'Strg+F12 bleibt');
    Saved.UnitSearchReplaceFormsDialog := True;
    Page.LoadFrom(Saved);
    Assert.IsFalse(CheckOf(Page, 'UnitSearchReplaceUseUnitDialog').Checked);
    Assert.IsTrue(CheckOf(Page, 'UnitSearchReplaceFormsDialog').Checked);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.DebugDisplayRulesRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #854: Schalter und Aufrufe in Vorlagen.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'DebugDisplayRules').Checked);
    Assert.IsFalse(CheckOf(Page, 'DebugDisplayRulesAllowCalls').Checked);
    CheckOf(Page, 'DebugDisplayRules').Checked := False;
    CheckOf(Page, 'DebugDisplayRulesAllowCalls').Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugDisplayRules);
    Assert.IsTrue(Saved.DebugDisplayRulesAllowCalls);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.DebugStepIntoTargetRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #836: Schalter und Taste auf dem Reiter Debuggen.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'DebugStepIntoTarget').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($C076)), EditOf(Page, 'DebugStepIntoTargetKey').Text);
    CheckOf(Page, 'DebugStepIntoTarget').Checked := False;
    EditOf(Page, 'DebugStepIntoTargetKey').Text := ShortCutToText(TShortCut($6076));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugStepIntoTarget);
    Assert.AreEqual($6076, Saved.DebugStepIntoTargetKey);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.DebugBreakOnNextEventRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #856: Schalter und ausgenommene Ereignisse auf dem Reiter Debuggen; die Liste wird beim Speichern bereinigt.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'DebugBreakOnNextEvent').Checked);
    Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate', Page.Part<TAtlasSettingsDebugPart>.DebugBreakOnNextEventExcludedEdit.Text);
    CheckOf(Page, 'DebugBreakOnNextEvent').Checked := False;
    Page.Part<TAtlasSettingsDebugPart>.DebugBreakOnNextEventExcludedEdit.Text := 'OnPaint;OnResize';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugBreakOnNextEvent);
    Assert.AreEqual('OnPaint, OnResize', Saved.DebugBreakOnNextEventExcluded);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.DebugStepFiltersRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #850: Schalter, Kontrollkästchen je Art und Muster auf dem Reiter Debuggen.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'DebugStepFilters').Checked);
    Assert.IsTrue(Page.Part<TAtlasSettingsDebugPart>.DebugStepFilterKindCheck(TStepFilterKind.Getters).Checked);
    Assert.IsFalse(Page.Part<TAtlasSettingsDebugPart>.DebugStepFilterKindCheck(TStepFilterKind.Setters).Checked);
    Assert.IsTrue(Page.Part<TAtlasSettingsDebugPart>.DebugStepFilterKindCheck(TStepFilterKind.Trivial).Checked);
    Assert.AreEqual('', Page.Part<TAtlasSettingsDebugPart>.DebugStepFilterPatternsEdit.Text);
    CheckOf(Page, 'DebugStepFilters').Checked := False;
    Page.Part<TAtlasSettingsDebugPart>.DebugStepFilterKindCheck(TStepFilterKind.Getters).Checked := False;
    Page.Part<TAtlasSettingsDebugPart>.DebugStepFilterKindCheck(TStepFilterKind.EmptyConstructors).Checked := True;
    Page.Part<TAtlasSettingsDebugPart>.DebugStepFilterPatternsEdit.Text := ' *.Log* ; ;TBasisForm.*';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugStepFilters);
    Assert.AreEqual('trivial,emptyConstructors', Saved.DebugStepFilterKinds);
    Assert.AreEqual('*.Log*;TBasisForm.*', Saved.DebugStepFilterPatterns, 'bereinigt');
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.DebugVisualizersRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
  Kind: TAtlasVisualizerKind;
begin
  // #835: Hauptschalter, Haken je Art, Namensfelder, Grenzen, Auswertung als Auswahl.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'DebugVisualizers').Checked);
    for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    begin
      Assert.IsTrue(Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerKindCheck(Kind).Checked);
    end;
    Assert.AreEqual('Name,Caption,Text', Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerNameFieldsEdit.Text);
    Assert.AreEqual('120', Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerMaxLengthEdit.Text);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties), Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerEvaluationBox.Choice);
    CheckOf(Page, 'DebugVisualizers').Checked := False;
    Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerKindCheck(TAtlasVisualizerKind.Json).Checked := False;
    Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerKindCheck(TAtlasVisualizerKind.Graphics).Checked := False;
    Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerNameFieldsEdit.Text := 'Bezeichnung, Name';
    Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerMaxLengthEdit.Text := '99999';
    Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerEvaluationBox.Choice := Ord(TAtlasVisualizerEvaluation.Calls);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugVisualizers);
    Assert.AreEqual('lists,dictionaries,dataSets,bytes,colors,guid,geometry', Saved.DebugVisualizerTypes);
    Assert.AreEqual('Bezeichnung,Name', Saved.DebugVisualizerNameFields);
    Assert.AreEqual(TAtlasVisualizerSettings.MaxMaxLength, Saved.DebugVisualizerMaxLength);
    Assert.AreEqual('calls', Saved.DebugVisualizerEvaluation);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerKindCheck(TAtlasVisualizerKind.Json).Checked);
    Assert.IsTrue(Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerKindCheck(TAtlasVisualizerKind.Lists).Checked);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Calls), Page.Part<TAtlasSettingsDebugPart>.DebugVisualizerEvaluationBox.Choice);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.McpBuildRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(Page, 'McpBuild').Checked, 'standardmäßig an');
    CheckOf(Page, 'McpBuild').Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.McpBuild, 'abschaltbar');
    Page.LoadFrom(Saved);
    Assert.IsFalse(CheckOf(Page, 'McpBuild').Checked);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.ListModeRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // Listenmodus der Vervollständigung (#497).
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice, 'nur Treffer');
    Assert.AreEqual(0, Page.Part<TAtlasSettingsCompletionPart>.ListScopeChoice.Choice, 'Mitgliederlisten');
    Page.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice := 2;
    Page.Part<TAtlasSettingsCompletionPart>.ListScopeChoice.Choice := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('rest', Saved.CompletionListMode);
    Assert.AreEqual('everywhere', Saved.CompletionListScope);
    Page.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('all', Saved.CompletionListMode);
    Page.LoadFrom(Saved);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsCompletionPart>.ListScopeChoice.Choice);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.OpenBuildRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsTasksPart>.OpenBuildChoice.Choice, 'standardmäßig nicht bauen');
    Assert.AreEqual(0, Page.Part<TAtlasSettingsTasksPart>.OpenBuildScopeChoice.Choice, 'alle Projekte');
    Assert.AreEqual('3000', Page.Part<TAtlasSettingsTasksPart>.OpenBuildDelayEdit.Text);
    Assert.AreEqual('', Page.Part<TAtlasSettingsTasksPart>.OpenBuildExcludeEdit.Text);
    Assert.AreEqual('', Page.Part<TAtlasSettingsTasksPart>.OpenBuildConfigEdit.Text);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsTasksPart>.OpenBuildPlatformChoice.Choice, 'wie im Projekt');
    // Erzeugen, nur das aktive Projekt, 5 s, ein Package ausgeschlossen.
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildChoice.Choice := 3;
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildScopeChoice.Choice := 1;
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildDelayEdit.Text := '5000';
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildExcludeEdit.Text := 'Atlas.IDE.Expert.dproj';
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildConfigEdit.Text := ' Debug ';
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildPlatformChoice.Choice := 2;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.BuildOnOpen);
    Assert.AreEqual('build', Saved.BuildOnOpenKind);
    Assert.AreEqual('active', Saved.BuildOnOpenScope);
    Assert.AreEqual(5000, Saved.BuildOnOpenDelayMs);
    Assert.AreEqual('Atlas.IDE.Expert', Saved.BuildOnOpenExclude);
    Assert.AreEqual('Debug', Saved.BuildOnOpenConfig);
    Assert.AreEqual('Win64', Saved.BuildOnOpenPlatform);
    Page.LoadFrom(Saved);
    Assert.AreEqual('Debug', Page.Part<TAtlasSettingsTasksPart>.OpenBuildConfigEdit.Text);
    Assert.AreEqual(3, Page.Part<TAtlasSettingsTasksPart>.OpenBuildChoice.Choice);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsTasksPart>.OpenBuildScopeChoice.Choice);
    // Syntaxprüfung; „nicht bauen“ schaltet ab und behält die Art.
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('check', Saved.BuildOnOpenKind);
    Page.Part<TAtlasSettingsTasksPart>.OpenBuildChoice.Choice := 0;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.BuildOnOpen, 'abschaltbar');
    Assert.AreEqual('check', Saved.BuildOnOpenKind);
    Page.LoadFrom(Saved);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsTasksPart>.OpenBuildChoice.Choice);
  finally
    Page.Free;
  end;
end;
procedure TAtlasSettingsPageBuildTests.TasksRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.Part<TAtlasSettingsTasksPart>.TasksEnabledCheck.Checked, 'standardmäßig an');
    Assert.IsTrue(Page.Part<TAtlasSettingsTasksPart>.TasksProblemsFromOutputCheck.Checked);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsTasksPart>.TasksBeforeBuildChoice.Choice, 'vor dem Build: aus');
    Assert.IsTrue(Page.Part<TAtlasSettingsTasksPart>.TasksSaveBeforeRunCheck.Checked);
    Assert.IsFalse(Page.Part<TAtlasSettingsTasksPart>.TasksRunChecksParallelCheck.Checked);
    Assert.IsFalse(Page.Part<TAtlasSettingsTasksPart>.TasksOnlyFindingsCheck.Checked);
    Page.Part<TAtlasSettingsTasksPart>.TasksEnabledCheck.Checked := False;
    Page.Part<TAtlasSettingsTasksPart>.TasksProblemsFromOutputCheck.Checked := False;
    Page.Part<TAtlasSettingsTasksPart>.TasksBeforeBuildChoice.Choice := 2;
    Page.Part<TAtlasSettingsTasksPart>.TasksSaveBeforeRunCheck.Checked := False;
    Page.Part<TAtlasSettingsTasksPart>.TasksRunChecksParallelCheck.Checked := True;
    Page.Part<TAtlasSettingsTasksPart>.TasksOnlyFindingsCheck.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.TasksEnabled, 'abschaltbar');
    Assert.IsFalse(Saved.TasksProblemsFromOutput);
    Assert.AreEqual('block', Saved.TasksBeforeBuild);
    Assert.IsFalse(Saved.TasksSaveBeforeRun);
    Assert.IsTrue(Saved.TasksRunChecksParallel);
    Assert.IsTrue(Saved.TasksOnlyFindings);
    Page.LoadFrom(Saved);
    Assert.AreEqual(2, Page.Part<TAtlasSettingsTasksPart>.TasksBeforeBuildChoice.Choice);
    Assert.IsFalse(Page.Part<TAtlasSettingsTasksPart>.TasksEnabledCheck.Checked);
    Page.Part<TAtlasSettingsTasksPart>.TasksBeforeBuildChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('warn', Saved.TasksBeforeBuild);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageBuildTests);

end.
