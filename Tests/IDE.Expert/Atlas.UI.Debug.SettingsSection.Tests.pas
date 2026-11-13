unit Atlas.UI.Debug.SettingsSection.Tests;

// Abschnitt „Debuggen“ des Moduls Debugger (#1456): Die Optionsseite holt ihn vom Anbieter des Moduls; ohne das
// Modul fehlt der Reiter. Geprüft werden Laden und Speichern aller Werte über die Seite (vorher in den Tests der
// Seite von Base), die Arten als Haken und die einheitliche Form der Listen beim Speichern.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Debug.SettingsSection;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TDebugSettingsSectionTests = class
  private
    FSection: TAtlasDebugSettingsSection;
    FSectionRef: IAtlasSettingsSection;
    FRegistration: IAtlasRegistration;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Eigener Reiter „Debuggen“ mit dem Modulschalter, beschriftet wie die Seite im Katalog.</summary>
    [Test]
    procedure OwnSheetWithModuleSwitch;
    [Test]
    procedure DebugRoundTrip;
    /// <summary>#854: Schalter und Aufrufe in Vorlagen.</summary>
    [Test]
    procedure DisplayRulesRoundTrip;
    /// <summary>#836: Schalter und Taste.</summary>
    [Test]
    procedure StepIntoTargetRoundTrip;
    /// <summary>#856: Schalter und ausgenommene Ereignisse; die Liste wird beim Speichern bereinigt.</summary>
    [Test]
    procedure BreakOnNextEventRoundTrip;
    /// <summary>#850: Schalter, Haken je Art und Muster.</summary>
    [Test]
    procedure StepFiltersRoundTrip;
    /// <summary>#835: Hauptschalter, Haken je Art, Namensfelder, Grenzen, Auswertung als Auswahl.</summary>
    [Test]
    procedure VisualizersRoundTrip;
  end;

implementation

uses
  System.Classes,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Settings.PageNames,
  Atlas.Text.StepFilter,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport;

procedure TDebugSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TDebugSettingsSectionTests.Setup;
begin
  FSection := TAtlasDebugSettingsSection.Create;
  FSectionRef := FSection;
  FRegistration := ProvideSection(FSectionRef);
end;

procedure TDebugSettingsSectionTests.TearDown;
begin
  FRegistration.Revoke;
  FRegistration := nil;
  FSection := nil;
  FSectionRef := nil;
end;

procedure TDebugSettingsSectionTests.OwnSheetWithModuleSwitch;
var
  mPage: TAtlasSettingsPage;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsNotNull(CheckOf(mPage, 'DebugEnabled'), 'Modulschalter im Abschnitt');
    Assert.AreEqual(TAtlasSettingsPageNames.Caption('Debuggen', TAtlasStrings.Language = TAtlasLanguage.English),
      SheetOf(CheckOf(mPage, 'DebugHoverValues')).Caption);
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'DebugEnabled')) = SheetOf(CheckOf(mPage, 'DebugInlineValues')));
  finally
    mPage.Free;
  end;
end;

/// <summary>Schalter des Abschnitts mit den Vorgaben.</summary>
procedure AssertDefaults(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(CheckOf(APage, 'DebugHoverValues').Checked, 'Werte im Hover standardmäßig an (#891)');
  Assert.IsTrue(CheckOf(APage, 'DebugExplainUnavailable').Checked, 'debug.explainUnavailable (#840)');
  Assert.IsTrue(CheckOf(APage, 'DebugCompletionInDialogs').Checked, 'debug.completionInDialogs (#538)');
  Assert.IsTrue(CheckOf(APage, 'DebugEvaluateWindow').Checked, 'debug.evaluateWindow (#784)');
  Assert.IsTrue(CheckOf(APage, 'DebugEvaluateReplaceCtrlF7').Checked, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsTrue(CheckOf(APage, 'DebugExplainAccessViolation').Checked, 'debug.explainAccessViolation (#865)');
  Assert.IsFalse(CheckOf(APage, 'DebugExplainAccessViolationAllowCalls').Checked, 'allowCalls (#865)');
  Assert.AreEqual('64', EditOf(APage, 'DebugParallelStacksMaxThreads').Text, 'debug.parallelStacks.maxThreads (#837)');
  Assert.IsFalse(CheckOf(APage, 'DebugThreadFreeze').Checked, 'debug.threadFreeze (#852)');
  Assert.IsTrue(CheckOf(APage, 'DebugThreadsInSource').Checked, 'debug.threadsInSource (#852)');
  Assert.IsTrue(CheckOf(APage, 'DebugParallelStacks').Checked, 'debug.parallelStacks (#837)');
  Assert.IsTrue(CheckOf(APage, 'DebugDeadlocks').Checked, 'debug.deadlocks (#587)');
  Assert.IsTrue(CheckOf(APage, 'DebugModuleOfAddress').Checked, 'debug.moduleOfAddress (#1820)');
  Assert.IsTrue(CheckOf(APage, 'DebugExceptionHistory').Checked, 'debug.exceptionHistory (#517)');
  Assert.IsTrue(CheckOf(APage, 'DebugJustMyCode').Checked, 'debug.justMyCode (#578)');
  Assert.IsFalse(CheckOf(APage, 'DebugExceptionBanner').Checked, 'debug.exceptionBanner (#783)');
  Assert.IsTrue(CheckOf(APage, 'DebugExceptionBannerIgnoreAtLocation').Checked, 'ignoreAtLocation (#783)');
  Assert.IsTrue(CheckOf(APage, 'DebugInlineValues').Checked, 'debug.inlineValues (#508)');
  Assert.AreEqual('5', EditOf(APage, 'DebugInlineValuesPerLine').Text, 'debug.inlineValuesPerLine (#508)');
end;

/// <summary>Alle Schalter des Abschnitts umstellen.</summary>
procedure EditPage(APage: TAtlasSettingsPage; ASection: TAtlasDebugSettingsSection);
begin
  CheckOf(APage, 'DebugHoverValues').Checked := False;
  CheckOf(APage, 'DebugExplainUnavailable').Checked := False;
  CheckOf(APage, 'DebugCompletionInDialogs').Checked := False;
  CheckOf(APage, 'DebugEvaluateWindow').Checked := False;
  CheckOf(APage, 'DebugEvaluateReplaceCtrlF7').Checked := False;
  CheckOf(APage, 'DebugExplainAccessViolation').Checked := False;
  CheckOf(APage, 'DebugExplainAccessViolationAllowCalls').Checked := True;
  CheckOf(APage, 'DebugModuleOfAddress').Checked := False;
  CheckOf(APage, 'DebugDeadlocks').Checked := False;
  CheckOf(APage, 'DebugParallelStacks').Checked := False;
  CheckOf(APage, 'DebugThreadsInSource').Checked := False;
  CheckOf(APage, 'DebugThreadFreeze').Checked := True;
  EditOf(APage, 'DebugParallelStacksMaxThreads').Text := '32';
  CheckOf(APage, 'DebugExceptionHistory').Checked := False;
  CheckOf(APage, 'DebugJustMyCode').Checked := False;
  CheckOf(APage, 'DebugExceptionBanner').Checked := True;
  CheckOf(APage, 'DebugExceptionBannerIgnoreAtLocation').Checked := False;
  CheckOf(APage, 'DebugInlineValues').Checked := False;
  EditOf(APage, 'DebugInlineValuesPerLine').Text := '3';
  ASection.OwnCodeFoldersEdit.Text := 'C:\Komponenten\; ;c:\komponenten';
end;

/// <summary>Umgestellte Schalter gespeichert.</summary>
procedure AssertSaved(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.DebugHoverValues);
  Assert.IsFalse(ASaved.DebugExplainUnavailable);
  Assert.IsFalse(ASaved.DebugCompletionInDialogs);
  Assert.IsFalse(ASaved.DebugEvaluateWindow);
  Assert.IsFalse(ASaved.DebugEvaluateReplaceCtrlF7);
  Assert.IsFalse(ASaved.DebugExplainAccessViolation);
  Assert.IsTrue(ASaved.DebugExplainAccessViolationAllowCalls);
  Assert.IsFalse(ASaved.DebugModuleOfAddress);
  Assert.IsFalse(ASaved.DebugDeadlocks);
  Assert.IsFalse(ASaved.DebugParallelStacks);
  Assert.IsFalse(ASaved.DebugThreadsInSource);
  Assert.IsTrue(ASaved.DebugThreadFreeze);
  Assert.AreEqual(32, ASaved.DebugParallelStacksMaxThreads);

  Assert.IsFalse(ASaved.DebugExceptionHistory);
  Assert.IsFalse(ASaved.DebugJustMyCode);
  Assert.IsTrue(ASaved.DebugExceptionBanner);
  Assert.IsFalse(ASaved.DebugExceptionBannerIgnoreAtLocation);
  Assert.IsFalse(ASaved.DebugInlineValues);
  Assert.AreEqual(3, ASaved.DebugInlineValuesPerLine);
  Assert.AreEqual('C:\Komponenten', ASaved.DebugOwnCodeFolders, 'bereinigt (#578)');
end;

procedure TDebugSettingsSectionTests.DebugRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    AssertDefaults(mPage);
    EditPage(mPage, FSection);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    AssertSaved(mSaved);
    mSaved.DebugExplainAccessViolationAllowCalls := False;
    mSaved.DebugExceptionBannerIgnoreAtLocation := True;
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'DebugHoverValues').Checked);
    Assert.IsFalse(CheckOf(mPage, 'DebugExplainAccessViolationAllowCalls').Checked);
    Assert.IsTrue(CheckOf(mPage, 'DebugExceptionBannerIgnoreAtLocation').Checked);
    Assert.AreEqual('C:\Komponenten', FSection.OwnCodeFoldersEdit.Text);
  finally
    mPage.Free;
  end;
end;

procedure TDebugSettingsSectionTests.DisplayRulesRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DebugDisplayRules').Checked);
    Assert.IsFalse(CheckOf(mPage, 'DebugDisplayRulesAllowCalls').Checked);
    CheckOf(mPage, 'DebugDisplayRules').Checked := False;
    CheckOf(mPage, 'DebugDisplayRulesAllowCalls').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DebugDisplayRules);
    Assert.IsTrue(mSaved.DebugDisplayRulesAllowCalls);
  finally
    mPage.Free;
  end;
end;

procedure TDebugSettingsSectionTests.StepIntoTargetRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DebugStepIntoTarget').Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($C076)), EditOf(mPage, 'DebugStepIntoTargetKey').Text);
    CheckOf(mPage, 'DebugStepIntoTarget').Checked := False;
    EditOf(mPage, 'DebugStepIntoTargetKey').Text := ShortCutToText(TShortCut($6076));
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DebugStepIntoTarget);
    Assert.AreEqual($6076, mSaved.DebugStepIntoTargetKey);
  finally
    mPage.Free;
  end;
end;

procedure TDebugSettingsSectionTests.BreakOnNextEventRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DebugBreakOnNextEvent').Checked);
    Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate', FSection.BreakOnNextEventExcludedEdit.Text);
    CheckOf(mPage, 'DebugBreakOnNextEvent').Checked := False;
    FSection.BreakOnNextEventExcludedEdit.Text := 'OnPaint;OnResize';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DebugBreakOnNextEvent);
    Assert.AreEqual('OnPaint, OnResize', mSaved.DebugBreakOnNextEventExcluded);
  finally
    mPage.Free;
  end;
end;

procedure TDebugSettingsSectionTests.StepFiltersRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DebugStepFilters').Checked);
    Assert.IsTrue(FSection.StepFilterKindCheck(TStepFilterKind.Getters).Checked);
    Assert.IsFalse(FSection.StepFilterKindCheck(TStepFilterKind.Setters).Checked);
    Assert.IsTrue(FSection.StepFilterKindCheck(TStepFilterKind.Trivial).Checked);
    Assert.AreEqual('', FSection.StepFilterPatternsEdit.Text);
    CheckOf(mPage, 'DebugStepFilters').Checked := False;
    FSection.StepFilterKindCheck(TStepFilterKind.Getters).Checked := False;
    FSection.StepFilterKindCheck(TStepFilterKind.EmptyConstructors).Checked := True;
    FSection.StepFilterPatternsEdit.Text := ' *.Log* ; ;TBasisForm.*';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DebugStepFilters);
    Assert.AreEqual('trivial,emptyConstructors', mSaved.DebugStepFilterKinds);
    Assert.AreEqual('*.Log*;TBasisForm.*', mSaved.DebugStepFilterPatterns, 'bereinigt');
  finally
    mPage.Free;
  end;
end;

procedure TDebugSettingsSectionTests.VisualizersRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
  mKind: TAtlasVisualizerKind;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DebugVisualizers').Checked);
    for mKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    begin
      Assert.IsTrue(FSection.VisualizerKindCheck(mKind).Checked);
    end;
    Assert.AreEqual('Name,Caption,Text', FSection.VisualizerNameFieldsEdit.Text);
    Assert.AreEqual('120', EditOf(mPage, 'DebugVisualizerMaxLength').Text);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties), ChoiceOf(mPage, 'DebugVisualizerEvaluation').Choice);
    CheckOf(mPage, 'DebugVisualizers').Checked := False;
    FSection.VisualizerKindCheck(TAtlasVisualizerKind.Json).Checked := False;
    FSection.VisualizerKindCheck(TAtlasVisualizerKind.Graphics).Checked := False;
    FSection.VisualizerNameFieldsEdit.Text := 'Bezeichnung, Name';
    EditOf(mPage, 'DebugVisualizerMaxLength').Text := '99999';
    ChoiceOf(mPage, 'DebugVisualizerEvaluation').Choice := Ord(TAtlasVisualizerEvaluation.Calls);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DebugVisualizers);
    Assert.AreEqual('lists,dictionaries,dataSets,bytes,colors,guid,geometry', mSaved.DebugVisualizerTypes);
    Assert.AreEqual('Bezeichnung,Name', mSaved.DebugVisualizerNameFields);
    Assert.AreEqual(TAtlasVisualizerSettings.cMaxMaxLength, mSaved.DebugVisualizerMaxLength);
    Assert.AreEqual('calls', mSaved.DebugVisualizerEvaluation);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(FSection.VisualizerKindCheck(TAtlasVisualizerKind.Json).Checked);
    Assert.IsTrue(FSection.VisualizerKindCheck(TAtlasVisualizerKind.Lists).Checked);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Calls), ChoiceOf(mPage, 'DebugVisualizerEvaluation').Choice);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDebugSettingsSectionTests);

end.
