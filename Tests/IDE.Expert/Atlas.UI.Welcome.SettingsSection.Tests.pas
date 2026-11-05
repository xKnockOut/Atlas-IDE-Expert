unit Atlas.UI.Welcome.SettingsSection.Tests;

// Abschnitt der Willkommensseite im Optionsdialog (#1456): Die Optionsseite
// holt ihn vom Anbieter des Moduls und baut ihn in den Reiter
// Willkommensseite samt Modulschalter. Geprüft werden
// Laden und Speichern aller Werte über die Seite (vorher in den Tests der
// Seite), die benannten Layouts (#767), die Knöpfe der Zählung (#757) und der
// Weg von „Meine Issues“ zur Seite Issue-Tracker.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Welcome.SettingsSection;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TWelcomeSettingsSectionTests = class
  private
    FSection: TAtlasWelcomeSettingsSection;
    FSectionRef: IAtlasSettingsSection;
    FRegistration: IAtlasRegistration;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>#753 und folgende: alle Werte der Seite mit ihren Vorgaben laden, ändern und begrenzt speichern.
    /// </summary>
    [Test]
    procedure SettingsRoundTrip;
    /// <summary>Freies Layout (#767): Schalter, Spalten, Layouts anlegen, wechseln, umbenennen, löschen; je
    /// Layout eigene Sichtbarkeit; Reveal der Einstellungen.</summary>
    [Test]
    procedure LayoutsOnPage;
    /// <summary>#757: „Zählung zurücksetzen“ und „Gesperrte Tipps wieder zeigen“ rufen die Haken je einmal.
    /// </summary>
    [Test]
    procedure UsageButtonsCallBack;
    /// <summary>Lage im Reiter Willkommensseite, Sprint-Kachel auf eigenem Knoten, ohne Modul Tracker kein Weg
    /// von „Meine Issues“ zur Seite Issue-Tracker; der Filter „experimentell“ blendet den Kopf aus.</summary>
    [Test]
    procedure SectionOnWelcomeSheet;
  end;

implementation

uses
  Atlas.UI.Settings.Page.Tree,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.Menus,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Welcome.Layouts,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Welcome.SettingsLayouts,
  Atlas.UI.Welcome.Strings;

type
  /// <summary>Anbieter der Tests: liefert den vorbereiteten Abschnitt.</summary>
  TFixedProvider = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  private
    FSection: IAtlasSettingsSection;
  public
    constructor Create(const ASection: IAtlasSettingsSection);
    function CreateSection: IAtlasSettingsSection;
  end;

constructor TFixedProvider.Create(const ASection: IAtlasSettingsSection);
begin
  inherited Create;
  FSection := ASection;
end;

function TFixedProvider.CreateSection: IAtlasSettingsSection;
begin
  Result := FSection;
end;

/// <summary>Reiter, auf dem AControl liegt; nil ohne.</summary>
function SheetOf(AControl: TControl): TTabSheet;
begin
  while (AControl <> nil) and not (AControl is TTabSheet) do
  begin
    AControl := AControl.Parent;
  end;
  Result := TTabSheet(AControl);
end;

procedure TWelcomeSettingsSectionTests.WarmUpFirstUse;
begin
  Setup;
  try
    SettingsRoundTrip;
  finally
    TearDown;
  end;
end;

procedure TWelcomeSettingsSectionTests.Setup;
begin
  FSection := TAtlasWelcomeSettingsSection.Create;
  FSectionRef := FSection;
  FRegistration := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
    TFixedProvider.Create(FSectionRef) as IAtlasSettingsSectionProvider);
end;

procedure TWelcomeSettingsSectionTests.TearDown;
begin
  FRegistration.Revoke;
  FRegistration := nil;
  FSection := nil;
  FSectionRef := nil;
end;

/// <summary>Vorgaben nach dem Laden (#753, #755, #758, #763, #764, #757, #766).</summary>
procedure AssertDefaults(ASection: TAtlasWelcomeSettingsSection);
begin
  Assert.IsTrue(ASection.Start.IdePage.Checked, 'wieder auf der Willkommensseite der IDE (#761)');
  Assert.IsFalse(ASection.Start.Layout.Checked, 'Layout der IDE bleibt, bis man es anwendet');
  Assert.IsFalse(ASection.Start.OpenOnStart.Checked, 'Atlas-Start nur auf Wunsch (#1114)');
  Assert.IsTrue(ASection.Start.OpenWhenNoProject.Checked, 'Atlas-Start ohne Projekt (#1114)');
  Assert.IsTrue(ASection.Start.Header.Checked);
  Assert.IsTrue(ASection.Start.Greeting.Checked);
  Assert.IsTrue(ASection.Start.Search.Checked);
  Assert.IsTrue(ASection.Start.SearchSymbols.Checked);
  Assert.AreEqual(ShortCutToText($4045), ASection.Start.SearchKey.Text);
  Assert.AreEqual(1, ASection.Start.WhatsNew.Choice, 'afterUpdate');
  Assert.IsTrue(ASection.Tiles.Continue.Checked);
  Assert.AreEqual('5', ASection.Tiles.ContinueCount.Text);
  Assert.IsTrue(ASection.Tiles.ContinueIncoming.Checked);
  Assert.IsFalse(ASection.Tiles.ContinueFetch.Checked);
  Assert.IsTrue(ASection.Tiles.Saved.Checked);
  Assert.IsTrue(ASection.Tiles.Projects.Checked);
  Assert.AreEqual('8', ASection.Tiles.MaxProjects.Text);
  Assert.IsTrue(ASection.Tiles.RefreshVcs.Checked);
  Assert.IsTrue(ASection.Tiles.Trends.Checked);
  Assert.AreEqual('30', ASection.Tiles.TrendsPoints.Text);
  Assert.IsTrue(ASection.Tiles.TrendsSeries[TAtlasTrendSeries.Warnings].Checked);
  Assert.IsTrue(ASection.Tiles.TrendsSeries[TAtlasTrendSeries.MethodLength].Checked);
  Assert.IsTrue(ASection.Tiles.Tests.Checked);
  Assert.AreEqual('5', ASection.Tiles.TestsMaxFailures.Text);
  Assert.IsFalse(ASection.Tiles.TestsCi.Checked);
  Assert.AreEqual(0, ASection.Tiles.TestsCiProvider.Choice);
  Assert.AreEqual('10', ASection.Tiles.TestsCiInterval.Text);
  Assert.IsTrue(ASection.Tiles.TestsCiNotify.Checked);
  Assert.IsTrue(ASection.Tiles.CiLogin.Checked);
  Assert.IsFalse(ASection.Tiles.Issues.Checked);
  Assert.IsTrue(ASection.Tiles.Sprint.Checked);
end;

/// <summary>Vorgaben der Schnellaktionen und der übrigen Bereiche.</summary>
procedure AssertMoreDefaults(ASection: TAtlasWelcomeSettingsSection);
begin
  Assert.IsTrue(ASection.More.QuickActions.Checked);
  Assert.IsTrue(ASection.More.QuickActionsItems[TAtlasQuickAction.Build].Checked);
  Assert.IsTrue(ASection.More.QuickActionsItems[TAtlasQuickAction.Console].Checked);
  Assert.IsTrue(ASection.More.QuickActionsItems[TAtlasQuickAction.Tasks].Checked, 'Aufgaben (#900)');
  Assert.AreEqual('wt.exe', ASection.More.QuickActionsConsole.Text);
  Assert.AreEqual(ShortCutToText($4042), ASection.More.QuickActionsBuildKey.Text);
  Assert.AreEqual(ShortCutToText($4054), ASection.More.QuickActionsTestKey.Text);
  Assert.IsTrue(ASection.More.Unsaved.Checked);
  Assert.AreEqual('0', ASection.More.UnsavedMinAge.Text);
  Assert.AreEqual('24', ASection.More.UnsavedWarn.Text);
  Assert.AreEqual('72', ASection.More.UnsavedAlert.Text);
  Assert.IsFalse(ASection.More.UnsavedHideClean.Checked);
  Assert.IsTrue(ASection.More.StatusTile.Checked);
  Assert.IsFalse(ASection.More.StatusTileOnlyProblems.Checked);
  Assert.IsTrue(ASection.More.Discover.Checked);
  Assert.IsTrue(ASection.More.TipsUsageTracking.Checked);
  Assert.IsTrue(ASection.More.Help.Checked);
  Assert.AreEqual(TAtlasPluginSettings.DefaultHelpReportUrl, ASection.More.HelpReportUrl.Text);
  Assert.AreEqual('', ASection.More.HelpReportFolder.Text);
  Assert.IsTrue(ASection.More.ProjectSetup.Checked, 'Vorgabe an (#759)');
  Assert.IsTrue(ASection.More.NewFromTemplate.Checked, 'Vorgabe an (#759)');
end;

/// <summary>Werte außerhalb der Grenzen und mit Leerraum eintragen.</summary>
procedure ChangeStart(ASection: TAtlasWelcomeSettingsSection);
begin
  ASection.Start.IdePage.Checked := False;
  ASection.Start.Layout.Checked := True;
  ASection.Start.OpenOnStart.Checked := True;
  ASection.Start.OpenWhenNoProject.Checked := False;
  ASection.Start.Header.Checked := False;
  ASection.Start.Greeting.Checked := False;
  ASection.Start.Search.Checked := False;
  ASection.Start.SearchSymbols.Checked := False;
  ASection.Start.SearchKey.Text := ShortCutToText($6046);
  ASection.Start.WhatsNew.Choice := 2;
  ASection.Tiles.Continue.Checked := False;
  ASection.Tiles.ContinueCount.Text := '50';
  ASection.Tiles.ContinueIncoming.Checked := False;
  ASection.Tiles.ContinueFetch.Checked := True;
  ASection.Tiles.Saved.Checked := False;
  ASection.Tiles.Projects.Checked := False;
  ASection.Tiles.MaxProjects.Text := '99';
  ASection.Tiles.RefreshVcs.Checked := False;
  ASection.Tiles.Trends.Checked := False;
  ASection.Tiles.TrendsPoints.Text := '500';
  ASection.Tiles.TrendsSeries[TAtlasTrendSeries.RuleHits].Checked := False;
  ASection.Tiles.TrendsSeries[TAtlasTrendSeries.Duration].Checked := False;
  ASection.Tiles.Tests.Checked := False;
  ASection.Tiles.TestsMaxFailures.Text := '99';
  ASection.Tiles.TestsCi.Checked := True;
  ASection.Tiles.TestsCiInterval.Text := '0';
  ASection.Tiles.TestsCiNotify.Checked := False;
  ASection.Tiles.CiLogin.Checked := False;
  ASection.Tiles.Issues.Checked := True;
  ASection.Tiles.Sprint.Checked := False;
end;

procedure ChangeMore(ASection: TAtlasWelcomeSettingsSection);
begin
  ASection.More.QuickActions.Checked := False;
  ASection.More.QuickActionsItems[TAtlasQuickAction.Console].Checked := False;
  ASection.More.QuickActionsItems[TAtlasQuickAction.Run].Checked := False;
  ASection.More.QuickActionsConsole.Text := '  pwsh.exe ';
  ASection.More.QuickActionsBuildKey.Text := '';
  ASection.More.QuickActionsTestKey.Text := ShortCutToText($C054);
  ASection.More.Unsaved.Checked := False;
  ASection.More.UnsavedMinAge.Text := '2';
  ASection.More.UnsavedWarn.Text := '48';
  ASection.More.UnsavedAlert.Text := '12';
  ASection.More.UnsavedHideClean.Checked := True;
  ASection.More.StatusTile.Checked := False;
  ASection.More.StatusTileOnlyProblems.Checked := True;
  ASection.More.Discover.Checked := False;
  ASection.More.TipsUsageTracking.Checked := False;
  ASection.More.Help.Checked := False;
  ASection.More.HelpReportUrl.Text := ' https://example.org/issues/new ';
  ASection.More.HelpReportFolder.Text := ' D:\Diagnose ';
  ASection.More.ProjectSetup.Checked := False;
  ASection.More.NewFromTemplate.Checked := False;
end;

procedure AssertSavedStart(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.WelcomePageIdePage);
  Assert.AreEqual('atlas', ASaved.WelcomePageLayout);
  Assert.IsTrue(ASaved.WelcomePageOpenOnStart);
  Assert.IsFalse(ASaved.WelcomePageOpenWhenNoProject);
  Assert.IsFalse(ASaved.WelcomePageHeader);
  Assert.IsFalse(ASaved.WelcomePageGreeting);
  Assert.IsFalse(ASaved.WelcomePageSearch);
  Assert.IsFalse(ASaved.WelcomePageSearchSymbols);
  Assert.AreEqual($6046, ASaved.WelcomePageSearchKey);
  Assert.AreEqual('always', ASaved.WelcomePageWhatsNew);
  Assert.IsFalse(ASaved.WelcomePageContinue);
  Assert.AreEqual(20, ASaved.WelcomePageContinueCount, 'auf 1–20 begrenzt');
  Assert.IsFalse(ASaved.WelcomePageContinueIncoming);
  Assert.IsTrue(ASaved.WelcomePageContinueFetch);
  Assert.IsFalse(ASaved.WelcomePageSaved);
  Assert.IsFalse(ASaved.WelcomePageProjectStatus);
  Assert.AreEqual(30, ASaved.WelcomePageMaxProjects, 'auf 1–30 begrenzt');
  Assert.IsFalse(ASaved.WelcomePageRefreshVcs);
  Assert.IsFalse(ASaved.WelcomePageTrends);
  Assert.AreEqual(100, ASaved.WelcomePageTrendsPoints, 'auf 2–100 begrenzt');
  Assert.AreEqual('warnings,todos,methodLength', ASaved.WelcomePageTrendsSeries);
  Assert.IsFalse(ASaved.WelcomePageTests);
  Assert.AreEqual(50, ASaved.WelcomePageTestsMaxFailures, 'auf 1–50 begrenzt');
  Assert.IsTrue(ASaved.WelcomePageTestsCi);
  Assert.AreEqual('jenkins', ASaved.WelcomePageTestsCiProvider);
  Assert.AreEqual(1, ASaved.WelcomePageTestsCiIntervalMinutes, 'auf 1–1440 begrenzt');
  Assert.IsFalse(ASaved.WelcomePageTestsCiNotify);
  Assert.IsFalse(ASaved.CiLogin);
  Assert.IsTrue(ASaved.WelcomePageIssues);
  Assert.IsFalse(ASaved.WelcomePageSprint);
end;

procedure AssertSavedMore(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.WelcomePageQuickActions);
  Assert.AreEqual('build,tests,pull,folder,tasks', ASaved.WelcomePageQuickActionsItems, 'ohne run und console');
  Assert.AreEqual('pwsh.exe', ASaved.WelcomePageQuickActionsConsole);
  Assert.AreEqual(0, ASaved.WelcomePageQuickActionsBuildKey, 'leer = keine Taste');
  Assert.AreEqual($C054, ASaved.WelcomePageQuickActionsTestKey);
  Assert.IsFalse(ASaved.WelcomePageUnsaved);
  Assert.AreEqual(2, ASaved.WelcomePageUnsavedMinAgeHours);
  Assert.AreEqual(48, ASaved.WelcomePageUnsavedWarnHours);
  Assert.AreEqual(48, ASaved.WelcomePageUnsavedAlertHours, 'rot nie vor gelb');
  Assert.IsTrue(ASaved.WelcomePageUnsavedHideWhenClean);
  Assert.IsFalse(ASaved.WelcomePageStatusTile);
  Assert.IsTrue(ASaved.WelcomePageStatusTileOnlyProblems);
  Assert.IsFalse(ASaved.WelcomePageDiscover);
  Assert.IsFalse(ASaved.TipsUsageTracking);
  Assert.IsFalse(ASaved.WelcomePageHelp);
  Assert.AreEqual('https://example.org/issues/new', ASaved.WelcomePageHelpReportUrl);
  Assert.AreEqual('D:\Diagnose', ASaved.WelcomePageHelpReportFolder);
  Assert.IsFalse(ASaved.WelcomePageProjectSetup);
  Assert.IsFalse(ASaved.WelcomePageNewFromTemplate);
end;

/// <summary>Nach erneutem Laden der gespeicherten Werte.</summary>
procedure AssertReloaded(ASection: TAtlasWelcomeSettingsSection);
begin
  Assert.IsFalse(ASection.Tiles.Trends.Checked);
  Assert.AreEqual('100', ASection.Tiles.TrendsPoints.Text);
  Assert.IsFalse(ASection.Tiles.TrendsSeries[TAtlasTrendSeries.RuleHits].Checked);
  Assert.IsTrue(ASection.Tiles.TrendsSeries[TAtlasTrendSeries.Todos].Checked);
  Assert.IsFalse(ASection.Tiles.Tests.Checked);
  Assert.AreEqual('50', ASection.Tiles.TestsMaxFailures.Text);
  Assert.IsTrue(ASection.Tiles.TestsCi.Checked);
  Assert.AreEqual('1', ASection.Tiles.TestsCiInterval.Text);
  Assert.IsFalse(ASection.Tiles.TestsCiNotify.Checked);
  Assert.IsFalse(ASection.Tiles.CiLogin.Checked);
  Assert.IsTrue(ASection.Tiles.Issues.Checked);
  Assert.IsFalse(ASection.Tiles.Sprint.Checked);
  Assert.IsFalse(ASection.More.QuickActions.Checked);
  Assert.IsFalse(ASection.More.QuickActionsItems[TAtlasQuickAction.Console].Checked);
  Assert.IsTrue(ASection.More.QuickActionsItems[TAtlasQuickAction.Pull].Checked);
  Assert.AreEqual('pwsh.exe', ASection.More.QuickActionsConsole.Text);
  Assert.AreEqual('', ASection.More.QuickActionsBuildKey.Text);
  Assert.IsFalse(ASection.More.Help.Checked);
  Assert.AreEqual('https://example.org/issues/new', ASection.More.HelpReportUrl.Text);
  Assert.AreEqual('D:\Diagnose', ASection.More.HelpReportFolder.Text);
  Assert.IsFalse(ASection.More.Discover.Checked);
  Assert.IsFalse(ASection.More.TipsUsageTracking.Checked);
  Assert.IsFalse(ASection.Start.IdePage.Checked);
  Assert.IsTrue(ASection.Start.Layout.Checked);
  Assert.IsTrue(ASection.Start.OpenOnStart.Checked);
  Assert.AreEqual(2, ASection.Start.WhatsNew.Choice);
end;

procedure TWelcomeSettingsSectionTests.SettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    AssertDefaults(FSection);
    AssertMoreDefaults(FSection);
    ChangeStart(FSection);
    ChangeMore(FSection);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    AssertSavedStart(mSaved);
    AssertSavedMore(mSaved);
    mPage.LoadFrom(mSaved);
    AssertReloaded(FSection);
    FSection.Start.WhatsNew.Choice := 0;
    // Keine Webadresse als Ziel: die Vorgabe.
    FSection.More.HelpReportUrl.Text := 'cmd.exe';
    mPage.SaveTo(mSaved);
    Assert.AreEqual('off', mSaved.WelcomePageWhatsNew);
    Assert.AreEqual(TAtlasPluginSettings.DefaultHelpReportUrl, mSaved.WelcomePageHelpReportUrl);
  finally
    mPage.Free;
  end;
end;

/// <summary>Namensabfrage der Tests: liefert AAnswer^; '' = Abbruch.</summary>
function FixedName(AAnswer: PString): TAtlasWelcomeAskName;
begin
  Result :=
    function(const APrompt: string; var AName: string): Boolean
    begin
      AName := AAnswer^;
      Result := AAnswer^ <> '';
    end;
end;

/// <summary>Rückfrage der Tests: merkt den Text in ATold^, antwortet Ja.</summary>
function RememberConfirm(ATold: PString): TAtlasWelcomeConfirm;
begin
  Result :=
    function(const AText: string; AQuestion: Boolean): Boolean
    begin
      ATold^ := AText;
      Result := True;
    end;
end;

/// <summary>Neues Layout „Präsentation“ als Kopie, dort Testergebnisse und „Neu in Atlas“ aus, eine Spalte; dann
/// zwischen beiden wechseln.</summary>
procedure NewAndSwitch(ASection: TAtlasWelcomeSettingsSection; var AAnswer: string);
begin
  AAnswer := 'Präsentation';
  ASection.Layouts.NewButton.Click;
  Assert.AreEqual(1, ASection.Layouts.Choice.Choice);
  Assert.AreEqual('Präsentation', ASection.Layouts.Layouts.ActiveName);
  Assert.IsTrue(ASection.Layouts.DeleteButton.Enabled);
  ASection.Tiles.Tests.Checked := False;
  ASection.Start.WhatsNew.Choice := 0;
  ASection.Start.Columns.Text := '1';
  // Zurück zu „Standard“: dessen Sichtbarkeit und Spalten.
  ASection.Layouts.Select(0);
  Assert.IsTrue(ASection.Tiles.Tests.Checked);
  Assert.AreEqual(1, ASection.Start.WhatsNew.Choice, '„Neu in Atlas“ wieder nach einem Update');
  Assert.AreEqual('2', ASection.Start.Columns.Text);
  ASection.Layouts.Select(1);
  Assert.IsFalse(ASection.Tiles.Tests.Checked);
  Assert.AreEqual(0, ASection.Start.WhatsNew.Choice);
  Assert.AreEqual('1', ASection.Start.Columns.Text);
end;

/// <summary>Umbenennen: vergebener Name nur mit Hinweis, Abbrechen ändert nichts.</summary>
procedure RenameAndCancel(ASection: TAtlasWelcomeSettingsSection; var AAnswer, ATold: string);
begin
  AAnswer := 'standard';
  ASection.Layouts.RenameButton.Click;
  Assert.IsTrue(Pos('standard', ATold) > 0);
  Assert.AreEqual('Präsentation', ASection.Layouts.Layouts.ActiveName);
  AAnswer := 'Vortrag';
  ASection.Layouts.RenameButton.Click;
  Assert.AreEqual('Vortrag', ASection.Layouts.Layouts.ActiveName);
  AAnswer := '';
  ASection.Layouts.NewButton.Click;
  Assert.AreEqual(2, Integer(Length(ASection.Layouts.Layouts.Items)));
end;

procedure TWelcomeSettingsSectionTests.LayoutsOnPage;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
  mAnswer, mTold: string;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    FSection.Layouts.OnAskName := FixedName(@mAnswer);
    FSection.Layouts.OnConfirm := RememberConfirm(@mTold);
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(FSection.Start.CustomLayout.Checked);
    Assert.AreEqual('2', FSection.Start.Columns.Text);
    Assert.AreEqual(0, FSection.Layouts.Choice.Choice);
    Assert.AreEqual(1, Integer(Length(FSection.Layouts.Layouts.Items)));
    Assert.IsFalse(FSection.Layouts.DeleteButton.Enabled, 'das letzte Layout bleibt');
    NewAndSwitch(FSection, mAnswer);
    RenameAndCancel(FSection, mAnswer, mTold);
    FSection.Start.CustomLayout.Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.WelcomePageCustomLayout);
    Assert.AreEqual('Vortrag', mSaved.WelcomePageActiveLayout);
    Assert.AreEqual(1, mSaved.WelcomePageColumns);
    Assert.IsFalse(mSaved.WelcomePageTests);
    Assert.AreEqual('off', mSaved.WelcomePageWhatsNew);
    mLayouts := TAtlasWelcomeCustomizing.Load(mSaved);
    Assert.AreEqual(2, Integer(Length(mLayouts.Items)));
    Assert.AreEqual('Standard', mLayouts.Items[0].Name);
    Assert.AreEqual(2, mLayouts.Items[0].Columns);
    // Wieder laden und löschen: „Standard“ bleibt mit seiner Sichtbarkeit.
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(FSection.Start.CustomLayout.Checked);
    Assert.AreEqual(1, FSection.Layouts.Choice.Choice);
    FSection.Layouts.DeleteButton.Click;
    Assert.IsTrue(Pos('Vortrag', mTold) > 0, 'Rückfrage nennt das Layout');
    Assert.AreEqual(0, FSection.Layouts.Choice.Choice);
    Assert.IsTrue(FSection.Tiles.Tests.Checked);
    Assert.AreEqual('2', FSection.Start.Columns.Text);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('', mSaved.WelcomePageLayouts, 'nur noch die Vorgabe');
    Assert.AreEqual('Standard', mSaved.WelcomePageActiveLayout);
    // „Einstellungen dazu …“ (#628) findet die Einstellungen des Moduls.
    Assert.IsTrue(mPage.Reveal('WelcomePageCustomLayout'));
    Assert.IsTrue(mPage.Reveal('WelcomePageColumns'));
    Assert.IsTrue(mPage.Reveal('WelcomePageActiveLayout'));
    Assert.IsTrue(mPage.Reveal('WelcomePageIssues'));
  finally
    mPage.Free;
  end;
  mLayouts := Default(TAtlasWelcomeLayouts);
  mAnswer := '';
  mTold := '';
end;

/// <summary>Haken der Tests: hängt AText an ACalls^.</summary>
function Recorder(ACalls: PString; const AText: string): TProc;
var
  mText: string;
begin
  mText := AText;
  Result :=
    procedure
    begin
      ACalls^ := ACalls^ + mText;
    end;
end;

procedure TWelcomeSettingsSectionTests.UsageButtonsCallBack;
var
  mPage: TAtlasSettingsPage;
  mCalls: string;
begin
  mCalls := '';
  mPage := TAtlasSettingsPage.Create(nil);
  try
    // Die Knöpfe gehören zu „Atlas entdecken“ und sind nur mit dessen Schalter frei (#890).
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    FSection.Hooks.OnResetUsage := Recorder(@mCalls, 'reset;');
    FSection.Hooks.OnUnblockTips := Recorder(@mCalls, 'unblock;');
    Assert.IsTrue(FSection.More.ResetUsage.Enabled);
    FSection.More.ResetUsage.Click;
    FSection.More.UnblockTips.Click;
    Assert.AreEqual('reset;unblock;', mCalls);
    Assert.IsFalse(FSection.More.ResetUsage.Enabled, 'erledigt');
    Assert.IsFalse(FSection.More.UnblockTips.Enabled, 'erledigt');
  finally
    mPage.Free;
  end;
  mCalls := '';
end;

procedure TWelcomeSettingsSectionTests.SectionOnWelcomeSheet;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mWelcome: TTabSheet;
begin
  TAtlasSettingsPageTree.ForgetTreeState;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    // Modulschalter und Einstellungen des Moduls auf dem Reiter Willkommensseite.
    mWelcome := SheetOf(mPage.ControlOfSetting('WelcomePage'));
    Assert.IsNotNull(mWelcome);
    Assert.IsTrue(SheetOf(FSection.Start.IdePage) = mWelcome);
    Assert.IsTrue(SheetOf(FSection.Layouts.Choice) = SheetOf(FSection.Start.Columns), 'Layouts stehen bei den Spalten');
    // Sprint-Kachel (#1277): eigener Knoten welcome.sprint (Schema).
    Assert.IsTrue(SheetOf(FSection.Tiles.Sprint) = mPage.NodeSheet('welcome.sprint'));
    // „Meine Issues“: nur der Schalter, daneben der Weg zur Seite Issue-Tracker; ohne Modul Tracker gibt es die
    // Seite nicht und der Knopf ist verborgen (#1456).
    Assert.IsTrue(SheetOf(FSection.Tiles.IssuesLink) = SheetOf(FSection.Tiles.Issues));
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeIssuesLink),
      FSection.Tiles.IssuesLink.Caption);
    Assert.IsNull(mPage.ControlOfSetting('IssuesEnabled'), 'ohne Modul Tracker');
    Assert.IsFalse(FSection.Tiles.IssuesLink.Visible, 'kein Weg ins Leere');
    mPage.Pages.ActivePage := SheetOf(FSection.Tiles.Issues);
    FSection.Tiles.IssuesLink.Click;
    Assert.IsTrue(mPage.Pages.ActivePage = SheetOf(FSection.Tiles.Issues), 'Klick bleibt auf der Seite');
    // Der Kopf der Willkommensseite hat keine experimentelle Einstellung: Der Filter blendet ihn aus (#890).
    Assert.IsNotNull(mPage.NodeSheet('welcome.header'));
    mPage.Filter.Choice := 2;
    mPage.Filter.OnChange(mPage.Filter);
    Assert.IsNull(TreeNodeOf(mPage, mPage.NodeSheet('welcome.header')), 'Kopf der Willkommensseite ohne Treffer');
  finally
    mHost.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;

end.
