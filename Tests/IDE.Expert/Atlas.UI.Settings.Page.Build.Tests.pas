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
  Atlas.UI.Settings.Page.TestSupport;

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
    Assert.IsTrue(Page.CodeLensTestsCheck.Checked, 'Code Lens standardmäßig an');
    Assert.IsTrue(Page.TestRunCheck.Checked);
    Assert.IsTrue(Page.TestsBuildFirstCheck.Checked);
    Assert.IsFalse(Page.TestsAfterBuildCheck.Checked);
    Assert.IsFalse(Page.BuildZeroHintsCheck.Checked);
    Assert.IsTrue(Page.ShowInterfaceCostCheck.Checked, 'Kosten einer interface-Änderung standardmäßig an (#554)');
    Assert.IsTrue(Page.BuildCompilerSwitchesCheck.Checked);
    Assert.IsFalse(Page.BuildSwitchesInStatusBarCheck.Checked);
    Page.CodeLensTestsCheck.Checked := False;
    Page.TestRunCheck.Checked := False;
    Page.TestsBuildFirstCheck.Checked := False;
    Page.TestsAfterBuildCheck.Checked := True;
    Page.BuildZeroHintsCheck.Checked := True;
    Page.ShowInterfaceCostCheck.Checked := False;
    Page.BuildCompilerSwitchesCheck.Checked := False;
    Page.BuildSwitchesInStatusBarCheck.Checked := True;
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
    Assert.IsFalse(Page.CodeLensTestsCheck.Checked);
    Assert.IsFalse(Page.ShowInterfaceCostCheck.Checked);
    Assert.IsTrue(Page.TestsAfterBuildCheck.Checked);
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
    Assert.IsTrue(Page.ReleaseGuardCheck.Checked, 'Wächter standardmäßig an');
    Assert.AreEqual(0, Page.BuildGateChoice.Choice, 'build.gate off');
    Assert.AreEqual('300', Page.BuildGateTimeoutEdit.Text, 'build.gateTimeoutMs (#529)');
    Assert.IsTrue(Page.BuildSummaryCheck.Checked, 'build.summary (#530)');
    Assert.AreEqual('', Page.BuildWarningsAsErrorsEdit.Text, 'build.warningsAsErrors (#530)');
    Assert.AreEqual('Release', Page.ReleaseConfigsEdit.Text);
    Assert.IsTrue(Page.ReleaseCheckBox(TAtlasReleaseCheck.DebugDefine).Checked);
    Assert.IsNull(Page.ReleaseCheckChoice(TAtlasReleaseCheck.DebugDefine));
    Assert.IsNull(Page.ReleaseCheckBox(TAtlasReleaseCheck.RangeChecks));
    Assert.AreEqual(1, Page.ReleaseCheckChoice(TAtlasReleaseCheck.RangeChecks).Choice, 'prüfen, Soll aus');
    Page.ReleaseGuardCheck.Checked := False;
    Page.BuildGateChoice.Choice := 2;
    Page.BuildGateTimeoutEdit.Text := '20';
    Page.BuildSummaryCheck.Checked := False;
    Page.BuildWarningsAsErrorsEdit.Text := 'w1035 h2164';
    Page.ReleaseConfigsEdit.Text := 'Release; Ship ,ship';
    Page.ReleaseCheckBox(TAtlasReleaseCheck.OutputFolder).Checked := False;
    Page.ReleaseCheckChoice(TAtlasReleaseCheck.Assertions).Choice := 0;
    Page.ReleaseCheckChoice(TAtlasReleaseCheck.StackFrames).Choice := 2;
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
    Assert.IsFalse(Page.ReleaseGuardCheck.Checked);
    Assert.AreEqual(2, Page.BuildGateChoice.Choice);
    Assert.AreEqual(0, Page.ReleaseCheckChoice(TAtlasReleaseCheck.Assertions).Choice);
    Assert.AreEqual(2, Page.ReleaseCheckChoice(TAtlasReleaseCheck.StackFrames).Choice);
    Assert.IsFalse(Page.ReleaseCheckBox(TAtlasReleaseCheck.OutputFolder).Checked);
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
    Assert.IsTrue(Page.StartProfilesCheck.Checked, 'Startprofile standardmäßig an');
    Assert.IsTrue(Page.StartProfilesStatusFieldCheck.Checked, 'Statusfeld standardmäßig an');
    Page.StartProfilesCheck.Checked := False;
    Page.StartProfilesStatusFieldCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.StartProfiles);
    Assert.IsFalse(Saved.StartProfilesStatusField);
    Saved.StartProfilesStatusField := True;
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.StartProfilesCheck.Checked);
    Assert.IsTrue(Page.StartProfilesStatusFieldCheck.Checked);
  finally
    Page.Free;
  end;
end;
/// <summary>Debugger-Schalter der Seite mit den Vorgaben.</summary>
procedure AssertDebugPageDefaults(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(APage.TestDebugCheck.Checked, 'Test debuggen standardmäßig an');
  Assert.IsTrue(APage.TestBreakAtStartCheck.Checked, 'Haltepunkt am Anfang standardmäßig an');
  Assert.IsTrue(APage.DebugHoverValuesCheck.Checked, 'Werte im Hover standardmäßig an (#891)');
  Assert.IsTrue(APage.DebugExplainUnavailableCheck.Checked, 'debug.explainUnavailable (#840)');
  Assert.IsTrue(APage.DebugCompletionInDialogsCheck.Checked, 'debug.completionInDialogs (#538)');
  Assert.IsTrue(APage.DebugEvaluateWindowCheck.Checked, 'debug.evaluateWindow (#784)');
  Assert.IsTrue(APage.DebugEvaluateReplaceCtrlF7Check.Checked, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsTrue(APage.DebugExplainAccessViolationCheck.Checked, 'debug.explainAccessViolation (#865)');
  Assert.IsFalse(APage.DebugExplainAccessViolationAllowCallsCheck.Checked,
    'debug.explainAccessViolation.allowCalls (#865)');
  Assert.IsTrue(APage.DebugExceptionHistoryCheck.Checked, 'debug.exceptionHistory (#517)');
  Assert.IsTrue(APage.DebugJustMyCodeCheck.Checked, 'debug.justMyCode (#578)');
  Assert.IsFalse(APage.DebugExceptionBannerCheck.Checked, 'debug.exceptionBanner (#783)');
  Assert.IsTrue(APage.DebugExceptionBannerIgnoreAtLocationCheck.Checked,
    'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsTrue(APage.DebugInlineValuesCheck.Checked, 'debug.inlineValues (#508)');
  Assert.AreEqual('5', APage.DebugInlineValuesPerLineEdit.Text, 'debug.inlineValuesPerLine (#508)');
end;
/// <summary>Alle Debugger-Schalter der Seite umstellen.</summary>
procedure EditDebugPage(APage: TAtlasSettingsPage);
begin
  APage.TestDebugCheck.Checked := False;
  APage.TestBreakAtStartCheck.Checked := False;
  APage.DebugHoverValuesCheck.Checked := False;
  APage.DebugExplainUnavailableCheck.Checked := False;
  APage.DebugCompletionInDialogsCheck.Checked := False;
  APage.DebugEvaluateWindowCheck.Checked := False;
  APage.DebugEvaluateReplaceCtrlF7Check.Checked := False;
  APage.DebugExplainAccessViolationCheck.Checked := False;
  APage.DebugExplainAccessViolationAllowCallsCheck.Checked := True;
  APage.DebugExceptionHistoryCheck.Checked := False;
  APage.DebugJustMyCodeCheck.Checked := False;
  APage.DebugExceptionBannerCheck.Checked := True;
  APage.DebugExceptionBannerIgnoreAtLocationCheck.Checked := False;
  APage.DebugInlineValuesCheck.Checked := False;
  APage.DebugInlineValuesPerLineEdit.Text := '3';
  APage.DebugOwnCodeFoldersEdit.Text := 'C:\Komponenten\; ;c:\komponenten';
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
  Assert.IsFalse(APage.TestDebugCheck.Checked);
  Assert.IsTrue(APage.TestBreakAtStartCheck.Checked);
  Assert.IsTrue(APage.DebugHoverValuesCheck.Checked);
  Assert.IsTrue(APage.DebugExplainUnavailableCheck.Checked);
  Assert.IsTrue(APage.DebugCompletionInDialogsCheck.Checked);
  Assert.IsTrue(APage.DebugEvaluateWindowCheck.Checked);
  Assert.IsTrue(APage.DebugEvaluateReplaceCtrlF7Check.Checked);
  Assert.IsTrue(APage.DebugExplainAccessViolationCheck.Checked);
  Assert.IsFalse(APage.DebugExplainAccessViolationAllowCallsCheck.Checked);
  Assert.IsTrue(APage.DebugExceptionHistoryCheck.Checked);
  Assert.IsTrue(APage.DebugJustMyCodeCheck.Checked);
  Assert.IsFalse(APage.DebugExceptionBannerCheck.Checked);
  Assert.IsTrue(APage.DebugExceptionBannerIgnoreAtLocationCheck.Checked);
  Assert.IsTrue(APage.DebugInlineValuesCheck.Checked);
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
    Assert.IsTrue(Page.UnitSearchReplaceUseUnitCheck.Checked, 'Alt+F11 standardmäßig übernommen');
    Assert.IsTrue(Page.UnitSearchReplaceFormsCheck.Checked, 'Umschalt+F12 standardmäßig übernommen');
    Page.UnitSearchReplaceUseUnitCheck.Checked := False;
    Page.UnitSearchReplaceFormsCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.UnitSearchReplaceUseUnitDialog);
    Assert.IsFalse(Saved.UnitSearchReplaceFormsDialog);
    Assert.IsTrue(Saved.UnitSearchReplaceIdeDialog, 'Strg+F12 bleibt');
    Saved.UnitSearchReplaceFormsDialog := True;
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.UnitSearchReplaceUseUnitCheck.Checked);
    Assert.IsTrue(Page.UnitSearchReplaceFormsCheck.Checked);
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
    Assert.IsTrue(Page.DebugDisplayRulesCheck.Checked);
    Assert.IsFalse(Page.DebugDisplayRulesAllowCallsCheck.Checked);
    Page.DebugDisplayRulesCheck.Checked := False;
    Page.DebugDisplayRulesAllowCallsCheck.Checked := True;
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
    Assert.IsTrue(Page.DebugStepIntoTargetCheck.Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($C076)), Page.DebugStepIntoTargetKeyEdit.Text);
    Page.DebugStepIntoTargetCheck.Checked := False;
    Page.DebugStepIntoTargetKeyEdit.Text := ShortCutToText(TShortCut($6076));
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
    Assert.IsTrue(Page.DebugBreakOnNextEventCheck.Checked);
    Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate', Page.DebugBreakOnNextEventExcludedEdit.Text);
    Page.DebugBreakOnNextEventCheck.Checked := False;
    Page.DebugBreakOnNextEventExcludedEdit.Text := 'OnPaint;OnResize';
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
    Assert.IsTrue(Page.DebugStepFiltersCheck.Checked);
    Assert.IsTrue(Page.DebugStepFilterKindCheck(TStepFilterKind.Getters).Checked);
    Assert.IsFalse(Page.DebugStepFilterKindCheck(TStepFilterKind.Setters).Checked);
    Assert.IsTrue(Page.DebugStepFilterKindCheck(TStepFilterKind.Trivial).Checked);
    Assert.AreEqual('', Page.DebugStepFilterPatternsEdit.Text);
    Page.DebugStepFiltersCheck.Checked := False;
    Page.DebugStepFilterKindCheck(TStepFilterKind.Getters).Checked := False;
    Page.DebugStepFilterKindCheck(TStepFilterKind.EmptyConstructors).Checked := True;
    Page.DebugStepFilterPatternsEdit.Text := ' *.Log* ; ;TBasisForm.*';
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
    Assert.IsTrue(Page.DebugVisualizersCheck.Checked);
    for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    begin
      Assert.IsTrue(Page.DebugVisualizerKindCheck(Kind).Checked);
    end;
    Assert.AreEqual('Name,Caption,Text', Page.DebugVisualizerNameFieldsEdit.Text);
    Assert.AreEqual('120', Page.DebugVisualizerMaxLengthEdit.Text);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties), Page.DebugVisualizerEvaluationBox.Choice);
    Page.DebugVisualizersCheck.Checked := False;
    Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Json).Checked := False;
    Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Graphics).Checked := False;
    Page.DebugVisualizerNameFieldsEdit.Text := 'Bezeichnung, Name';
    Page.DebugVisualizerMaxLengthEdit.Text := '99999';
    Page.DebugVisualizerEvaluationBox.Choice := Ord(TAtlasVisualizerEvaluation.Calls);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugVisualizers);
    Assert.AreEqual('lists,dictionaries,dataSets,bytes,colors,guid,geometry', Saved.DebugVisualizerTypes);
    Assert.AreEqual('Bezeichnung,Name', Saved.DebugVisualizerNameFields);
    Assert.AreEqual(TAtlasVisualizerSettings.MaxMaxLength, Saved.DebugVisualizerMaxLength);
    Assert.AreEqual('calls', Saved.DebugVisualizerEvaluation);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Json).Checked);
    Assert.IsTrue(Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Lists).Checked);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Calls), Page.DebugVisualizerEvaluationBox.Choice);
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
    Assert.IsTrue(Page.McpBuildCheck.Checked, 'standardmäßig an');
    Page.McpBuildCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.McpBuild, 'abschaltbar');
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.McpBuildCheck.Checked);
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
    Assert.AreEqual(0, Page.ListModeChoice.Choice, 'nur Treffer');
    Assert.AreEqual(0, Page.ListScopeChoice.Choice, 'Mitgliederlisten');
    Page.ListModeChoice.Choice := 2;
    Page.ListScopeChoice.Choice := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('rest', Saved.CompletionListMode);
    Assert.AreEqual('everywhere', Saved.CompletionListScope);
    Page.ListModeChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('all', Saved.CompletionListMode);
    Page.LoadFrom(Saved);
    Assert.AreEqual(1, Page.ListModeChoice.Choice);
    Assert.AreEqual(1, Page.ListScopeChoice.Choice);
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
    Assert.AreEqual(0, Page.OpenBuildChoice.Choice, 'standardmäßig nicht bauen');
    Assert.AreEqual(0, Page.OpenBuildScopeChoice.Choice, 'alle Projekte');
    Assert.AreEqual('3000', Page.OpenBuildDelayEdit.Text);
    Assert.AreEqual('', Page.OpenBuildExcludeEdit.Text);
    Assert.AreEqual('', Page.OpenBuildConfigEdit.Text);
    Assert.AreEqual(0, Page.OpenBuildPlatformChoice.Choice, 'wie im Projekt');
    // Erzeugen, nur das aktive Projekt, 5 s, ein Package ausgeschlossen.
    Page.OpenBuildChoice.Choice := 3;
    Page.OpenBuildScopeChoice.Choice := 1;
    Page.OpenBuildDelayEdit.Text := '5000';
    Page.OpenBuildExcludeEdit.Text := 'Atlas.IDE.Expert.dproj';
    Page.OpenBuildConfigEdit.Text := ' Debug ';
    Page.OpenBuildPlatformChoice.Choice := 2;
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
    Assert.AreEqual('Debug', Page.OpenBuildConfigEdit.Text);
    Assert.AreEqual(3, Page.OpenBuildChoice.Choice);
    Assert.AreEqual(1, Page.OpenBuildScopeChoice.Choice);
    // Syntaxprüfung; „nicht bauen“ schaltet ab und behält die Art.
    Page.OpenBuildChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('check', Saved.BuildOnOpenKind);
    Page.OpenBuildChoice.Choice := 0;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.BuildOnOpen, 'abschaltbar');
    Assert.AreEqual('check', Saved.BuildOnOpenKind);
    Page.LoadFrom(Saved);
    Assert.AreEqual(0, Page.OpenBuildChoice.Choice);
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
    Assert.IsTrue(Page.TasksEnabledCheck.Checked, 'standardmäßig an');
    Assert.IsTrue(Page.TasksProblemsFromOutputCheck.Checked);
    Assert.AreEqual(0, Page.TasksBeforeBuildChoice.Choice, 'vor dem Build: aus');
    Assert.IsTrue(Page.TasksSaveBeforeRunCheck.Checked);
    Assert.IsFalse(Page.TasksRunChecksParallelCheck.Checked);
    Assert.IsFalse(Page.TasksOnlyFindingsCheck.Checked);
    Page.TasksEnabledCheck.Checked := False;
    Page.TasksProblemsFromOutputCheck.Checked := False;
    Page.TasksBeforeBuildChoice.Choice := 2;
    Page.TasksSaveBeforeRunCheck.Checked := False;
    Page.TasksRunChecksParallelCheck.Checked := True;
    Page.TasksOnlyFindingsCheck.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.TasksEnabled, 'abschaltbar');
    Assert.IsFalse(Saved.TasksProblemsFromOutput);
    Assert.AreEqual('block', Saved.TasksBeforeBuild);
    Assert.IsFalse(Saved.TasksSaveBeforeRun);
    Assert.IsTrue(Saved.TasksRunChecksParallel);
    Assert.IsTrue(Saved.TasksOnlyFindings);
    Page.LoadFrom(Saved);
    Assert.AreEqual(2, Page.TasksBeforeBuildChoice.Choice);
    Assert.IsFalse(Page.TasksEnabledCheck.Checked);
    Page.TasksBeforeBuildChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('warn', Saved.TasksBeforeBuild);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageBuildTests);

end.
