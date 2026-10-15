unit Atlas.UI.Settings.Page.Tests;

// Tests für die Optionsseite (#227): Die IDE erzeugt sie über die Klasse,
// TCustomFrame.Create braucht dafür die DFM-Ressource.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPageTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure CreatesAndRoundTripsSettings;
    [Test]
    procedure SnippetsPageShowsCatalogAndValidates;
    [Test]
    procedure ShowsAndReenablesTrippedFeatures;
    [Test]
    procedure IndexSectionRoundTripsAndRunsCommands;
    [Test]
    procedure StatusFieldRoundTrips;
    [Test]
    procedure ShortcutTipsRoundTrip;
    [Test]
    procedure SafeModeRoundTrips;
    [Test]
    procedure UndoSettingsRoundTrip;
    [Test]
    procedure MethodToggleRoundTrip;
    [Test]
    procedure WelcomeSettingsRoundTrip;
    [Test]
    procedure UsageButtonsCallBack;
    [Test]
    procedure AcceptOptionsRoundTrip;
    [Test]
    procedure ServerPageRunsActions;
    [Test]
    procedure DialogShowsOriginAndResetsToGlobal;
    [Test]
    procedure DialogRuleTableChangesOnlyThatRule;
    [Test]
    procedure DialogValidatesBeforeSaving;
    [Test]
    procedure SymbolResourcesInAllSizes;
    [Test]
    procedure PageHeaderShowsSymbol;
    /// <summary>Die Einstellungen stehen auf Reitern je Bereich statt auf einer langen Seite (#227).</summary>
    [Test]
    procedure GroupsSettingsOnTabs;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.SnippetsPage,
  Atlas.UI.Settings.ServerPage,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Validation,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Vcl.Graphics,
  Vcl.ImageCollection,
  System.JSON,
  Vcl.Menus,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.UI.Strings;

procedure TAtlasSettingsPageTests.WarmUp;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
begin
  TAtlasSettingsPage.Create(nil).Free;
  // Auch mit Fenster (Reiter, PageControl): einmalige VCL-Daten nicht dem ersten Test anrechnen.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
  finally
    Host.Free;
  end;
  SnippetsPageShowsCatalogAndValidates;
end;

procedure TAtlasSettingsPageTests.GroupsSettingsOnTabs;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Sheet: TTabSheet;
  Index: Integer;
begin
  // Wie in der IDE: Die Reiter hängen erst am PageControl, wenn die Seite ein Fenster hat.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Assert.AreEqual(12, Page.Pages.PageCount);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabGeneral), Page.Pages.Pages[0].Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabUndo), Page.Pages.Pages[10].Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabWelcome), Page.Pages.Pages[11].Caption);
    for Index := 0 to Page.Pages.PageCount - 1 do
    begin
      Sheet := Page.Pages.Pages[Index];
      Assert.IsTrue(Sheet.ControlCount > 0, Sheet.Caption);
    end;
    Assert.AreEqual(0, Page.Pages.ActivePageIndex);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSettingsPageTests.CreatesAndRoundTripsSettings;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 12;
  Settings.Preview := True;
  Settings.HoverTooltip := False;
  Settings.XmlDocFull := False;
  Settings.XmlDocMaxLines := 7;
  Settings.ListWidth := 333;
  Settings.ActionsKey := 0;
  Settings.ExpandKey := $C057;
  Settings.EditorKeysPriority := True;
  Settings.SlashCommands := False;
  Settings.Snippets := False;
  Settings.ImportIdeTemplates := False;
  Settings.ProviderTimeLimitMs := 400;
  Settings.PairOwners := False;
  Settings.PairGuideWidth := 3;
  Settings.PairGuideOpacity := 70;
  Settings.PairColorsLight := '#0071E3,#007C8A,#C000E0,#008700,#4040FF';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.Enabled);
  Assert.AreEqual(12, Saved.VisibleRows);
  Assert.IsTrue(Saved.Preview);
  Assert.IsFalse(Saved.HoverTooltip);
  Assert.IsFalse(Saved.XmlDocFull);
  Assert.AreEqual(7, Saved.XmlDocMaxLines);
  Assert.AreEqual(333, Saved.ListWidth);
  Assert.AreEqual(0, Saved.ActionsKey);
  Assert.AreEqual($C057, Saved.ExpandKey);
  Assert.AreEqual($6057, Saved.ShrinkKey);
  Assert.IsTrue(Saved.EditorKeysPriority);
  Assert.IsFalse(Saved.SlashCommands);
  Assert.IsFalse(Saved.Snippets);
  Assert.IsFalse(Saved.ImportIdeTemplates);
  Assert.AreEqual(400, Saved.ProviderTimeLimitMs);
  Assert.IsFalse(Saved.PairOwners);
  Assert.AreEqual(3, Saved.PairGuideWidth);
  Assert.AreEqual(70, Saved.PairGuideOpacity);
  Assert.AreEqual('#0071E3,#007C8A,#C000E0,#008700,#4040FF', Saved.PairColorsLight);
  Assert.AreEqual('', Saved.PairColorsDark, 'Standardfarben bleiben leer');
end;

procedure TAtlasSettingsPageTests.ShowsAndReenablesTrippedFeatures;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Index: Integer;
begin
  TAtlasGuard.Fuse.ResetAll;
  try
    for Index := 1 to 3 do
    begin
      TAtlasGuard.ReportProvider('Testquelle', 'Fehler');
      TAtlasGuard.Fuse.Failed(TAtlasFeature.Pairs);
    end;
    // Die Liste der Sicherung braucht ein Fenster, wie in der IDE.
    Host := TForm.CreateNew(nil);
    try
      Page := TAtlasSettingsPage.Create(Host);
      Page.Parent := Host;
      Page.HandleNeeded;
      Page.LoadFrom(TAtlasPluginSettings.Defaults);
      Assert.AreEqual(2, Page.FuseList.Items.Count);
      Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Pairs), Page.FuseList.Items[0]);
      Assert.AreEqual('Testquelle', Page.FuseList.Items[1]);
      Assert.IsTrue(Page.FuseEnableAll.Enabled);
      // Nur die Quelle wieder einschalten.
      Page.FuseList.Selected[1] := True;
      Page.FuseEnableSelected.Click;
      Assert.IsFalse(TAtlasGuard.ProviderDisabled('Testquelle'));
      Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Page.FuseEnableAll.Click;
      Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Assert.AreEqual(1, Page.FuseList.Items.Count, 'nur der Hinweis „keine“');
      Assert.IsFalse(Page.FuseEnableAll.Enabled);
    finally
      Host.Free;
    end;
  finally
    TAtlasGuard.Fuse.ResetAll;
  end;
end;

procedure TAtlasSettingsPageTests.IndexSectionRoundTripsAndRunsCommands;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
  Confirm: Boolean;
  Cleared: Integer;
begin
  // #492: Verwendungen und Speicherbudget, Kennzahlen, Neuaufbau und Löschen mit Rückfrage.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.IndexUsages := False;
  Settings.MemoryBudgetMb := 512;
  Confirm := False;
  Cleared := 0;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsFalse(Page.IndexRebuild.Enabled or Page.IndexClear.Enabled, 'ohne Server keine Befehle');
    Page.OnIndexMetrics :=
      function: string
      begin
        Result := 'Units: 3';
      end;
    Page.OnIndexRebuild :=
      function: string
      begin
        Result := 'wird neu aufgebaut';
      end;
    Page.OnIndexClear :=
      function: string
      begin
        Inc(Cleared);
        Result := 'gelöscht';
      end;
    Page.ConfirmClear :=
      function: Boolean
      begin
        Result := Confirm;
      end;
    Page.LoadFrom(Settings);
    Assert.AreEqual('Units: 3', Page.IndexInfo.Caption);
    Assert.IsTrue(Page.IndexRebuild.Enabled and Page.IndexClear.Enabled);
    Page.IndexRebuild.Click;
    Assert.AreEqual('wird neu aufgebaut', Page.IndexInfo.Caption);
    Page.IndexClear.Click;
    Assert.AreEqual(0, Cleared, 'abgelehnt: nichts löschen');
    Confirm := True;
    Page.IndexClear.Click;
    Assert.AreEqual(1, Cleared);
    Assert.AreEqual('gelöscht', Page.IndexInfo.Caption);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.IndexUsages);
  Assert.AreEqual(512, Saved.MemoryBudgetMb);
end;

procedure TAtlasSettingsPageTests.StatusFieldRoundTrips;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #591: Feld an/aus, Kurztext, ausgeblendete Zeilen; #479: Diagnosemodus, #625: Prüfliste auf derselben Seite.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.StatusField := False;
  Settings.StatusFieldSummary := False;
  Settings.StatusFieldToggles := 'rightClick';
  Settings.IndexProgressPlace := 'off';
  Settings.StatusFieldHidden := 'atlas.file';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.StatusField.Checked);
    Assert.IsFalse(Page.StatusSummary.Checked);
    Assert.AreEqual(1, Page.StatusToggles.Choice, 'nur Rechtsklick');
    Assert.AreEqual(2, Page.IndexProgress.Choice, 'Fortschritt aus');
    Assert.AreEqual('atlas.file', Page.StatusHidden.Text);
    Assert.IsFalse(Page.DiagnosticMode.Checked, 'Diagnosemodus standardmäßig aus');
    Assert.IsTrue(Page.SetupChecklist.Checked, 'Prüfliste beim Start standardmäßig an (#625)');
    Page.DiagnosticMode.Checked := True;
    Page.SetupChecklist.Checked := False;
    Page.StatusField.Checked := True;
    Page.StatusToggles.Choice := 2;
    Page.IndexProgress.Choice := 1;
    Page.StatusHidden.Text := ' atlas.file, atlas.index ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StatusField);
    Assert.IsTrue(Saved.DiagnosticMode);
    Assert.IsFalse(Saved.SetupChecklist);
    Assert.IsFalse(Saved.StatusFieldSummary);
    Assert.AreEqual('doubleClick', Saved.StatusFieldToggles);
    Assert.AreEqual('menu', Saved.IndexProgressPlace);
    Assert.AreEqual('atlas.file, atlas.index', Saved.StatusFieldHidden);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ShortcutTipsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #600: shortcutTips.enabled und shortcutTips.scope auf der Seite Allgemein.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.ShortcutTips.Checked, 'Tipps standardmäßig an');
    Assert.AreEqual(1, Page.ShortcutTipsScope.Choice, 'Vorgabe all');
    Page.ShortcutTips.Checked := False;
    Page.ShortcutTipsScope.Choice := 0;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ShortcutTips);
    Assert.AreEqual('atlas', Saved.ShortcutTipsScope);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.ShortcutTips.Checked);
    Assert.AreEqual(0, Page.ShortcutTipsScope.Choice);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SafeModeRoundTrips;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #722: Rückfrage, ohne Rückfrage nach zwei Abstürzen, Taste, Zeitlimit, gemerkte Stände.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.SafeAskAfterCrash := False;
  Settings.SafeStartupKey := 'ctrl';
  Settings.SafeStartupTimeoutMs := 20000;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.SafeAsk.Checked);
    Assert.IsTrue(Page.SafeAuto.Checked);
    Assert.AreEqual(1, Page.SafeKey.Choice);
    Assert.AreEqual('20000', Page.SafeTimeout.Text);
    Assert.AreEqual('5', Page.SafeHistory.Text);
    Page.SafeAuto.Checked := False;
    Page.SafeKey.Choice := 2;
    Page.SafeHistory.Text := '500';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.SafeAskAfterCrash);
    Assert.IsFalse(Saved.SafeAutoAfterRepeatedCrash);
    Assert.AreEqual('none', Saved.SafeStartupKey);
    Assert.AreEqual(20000, Saved.SafeStartupTimeoutMs);
    // Begrenzt auf die Höchstzahl.
    Assert.AreEqual(TAtlasPluginSettings.MaxSafeSettingsHistory, Saved.SafeKeepSettingsHistory);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.WelcomeSettingsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #753: Ein/Aus, Ort (Willkommensseite oder Fenster „Atlas-Start“), Atlas-Layout, Kopf und Grußzeile;
  // #760: Suchfeld, Gruppe „Symbole“ und Taste; #756: Karte „Neu in Atlas“; #592: Bereich „Projekte“;
  // #762: Bereich „Nicht gesichert“; #754: Zustandskachel „Atlas“; #757: Karte „Atlas entdecken“, Zählung und
  // ihre Knöpfe.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.WelcomeEnabled.Checked);
    Assert.AreEqual(0, Page.WelcomeHost.Choice);
    Assert.IsFalse(Page.WelcomeLayout.Checked);
    Assert.IsTrue(Page.WelcomeHeader.Checked);
    Assert.IsTrue(Page.WelcomeGreeting.Checked);
    Assert.IsTrue(Page.WelcomeSearch.Checked);
    Assert.IsTrue(Page.WelcomeSearchSymbols.Checked);
    Assert.AreEqual(ShortCutToText($4045), Page.WelcomeSearchKey.Text);
    Assert.AreEqual(1, Page.WelcomeWhatsNew.Choice, 'afterUpdate');
    Assert.IsTrue(Page.WelcomeProjects.Checked);
    Assert.AreEqual('8', Page.WelcomeMaxProjects.Text);
    Assert.IsTrue(Page.WelcomeRefreshVcs.Checked);
    Assert.IsTrue(Page.WelcomeUnsaved.Checked);
    Assert.AreEqual('0', Page.WelcomeUnsavedMinAge.Text);
    Assert.AreEqual('24', Page.WelcomeUnsavedWarn.Text);
    Assert.AreEqual('72', Page.WelcomeUnsavedAlert.Text);
    Assert.IsFalse(Page.WelcomeUnsavedHideClean.Checked);
    Assert.IsTrue(Page.WelcomeStatusTile.Checked);
    Assert.IsFalse(Page.WelcomeStatusTileOnlyProblems.Checked);
    Assert.IsTrue(Page.WelcomeDiscover.Checked);
    Assert.IsTrue(Page.TipsUsageTracking.Checked);
    Page.WelcomeEnabled.Checked := False;
    Page.WelcomeHost.Choice := 1;
    Page.WelcomeLayout.Checked := True;
    Page.WelcomeHeader.Checked := False;
    Page.WelcomeGreeting.Checked := False;
    Page.WelcomeSearch.Checked := False;
    Page.WelcomeSearchSymbols.Checked := False;
    Page.WelcomeSearchKey.Text := ShortCutToText($6046);
    Page.WelcomeWhatsNew.Choice := 2;
    Page.WelcomeProjects.Checked := False;
    Page.WelcomeMaxProjects.Text := '99';
    Page.WelcomeRefreshVcs.Checked := False;
    Page.WelcomeUnsaved.Checked := False;
    Page.WelcomeUnsavedMinAge.Text := '2';
    Page.WelcomeUnsavedWarn.Text := '48';
    Page.WelcomeUnsavedAlert.Text := '12';
    Page.WelcomeUnsavedHideClean.Checked := True;
    Page.WelcomeStatusTile.Checked := False;
    Page.WelcomeStatusTileOnlyProblems.Checked := True;
    Page.WelcomeDiscover.Checked := False;
    Page.TipsUsageTracking.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.WelcomePage);
    Assert.AreEqual('dockWindow', Saved.WelcomePageHost);
    Assert.AreEqual('atlas', Saved.WelcomePageLayout);
    Assert.IsFalse(Saved.WelcomePageHeader);
    Assert.IsFalse(Saved.WelcomePageGreeting);
    Assert.IsFalse(Saved.WelcomePageSearch);
    Assert.IsFalse(Saved.WelcomePageSearchSymbols);
    Assert.AreEqual($6046, Saved.WelcomePageSearchKey);
    Assert.AreEqual('always', Saved.WelcomePageWhatsNew);
    Assert.IsFalse(Saved.WelcomePageProjectStatus);
    Assert.AreEqual(30, Saved.WelcomePageMaxProjects, 'auf 1–30 begrenzt');
    Assert.IsFalse(Saved.WelcomePageRefreshVcs);
    Assert.IsFalse(Saved.WelcomePageUnsaved);
    Assert.AreEqual(2, Saved.WelcomePageUnsavedMinAgeHours);
    Assert.AreEqual(48, Saved.WelcomePageUnsavedWarnHours);
    Assert.AreEqual(48, Saved.WelcomePageUnsavedAlertHours, 'rot nie vor gelb');
    Assert.IsTrue(Saved.WelcomePageUnsavedHideWhenClean);
    Assert.IsFalse(Saved.WelcomePageStatusTile);
    Assert.IsTrue(Saved.WelcomePageStatusTileOnlyProblems);
    Assert.IsFalse(Saved.WelcomePageDiscover);
    Assert.IsFalse(Saved.TipsUsageTracking);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.WelcomeDiscover.Checked);
    Assert.IsFalse(Page.TipsUsageTracking.Checked);
    Assert.AreEqual(1, Page.WelcomeHost.Choice);
    Assert.IsTrue(Page.WelcomeLayout.Checked);
    Assert.AreEqual(2, Page.WelcomeWhatsNew.Choice);
    Page.WelcomeWhatsNew.Choice := 0;
    Page.SaveTo(Saved);
    Assert.AreEqual('off', Saved.WelcomePageWhatsNew);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.UsageButtonsCallBack;
var
  Page: TAtlasSettingsPage;
  Calls: string;
begin
  // #757: „Zählung zurücksetzen“ und „Gesperrte Tipps wieder zeigen“ rufen die IDE-Schicht, je einmal.
  Calls := '';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.OnResetUsage :=
      procedure
      begin
        Calls := Calls + 'reset;';
      end;
    Page.OnUnblockTips :=
      procedure
      begin
        Calls := Calls + 'unblock;';
      end;
    Assert.IsTrue(Page.ResetUsageButton.Enabled);
    Page.ResetUsageButton.Click;
    Page.UnblockTipsButton.Click;
    Assert.AreEqual('reset;unblock;', Calls);
    Assert.IsFalse(Page.ResetUsageButton.Enabled, 'erledigt');
    Assert.IsFalse(Page.UnblockTipsButton.Enabled, 'erledigt');
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.UndoSettingsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #721: Ein/Aus, Tiefe, Sicherung, Größe, Konflikte, neue Dateien und die beiden Tasten.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.UndoMultiFileDepth := 7;
  Settings.UndoMultiFileOnConflict := 'abort';
  Settings.UndoMultiFileNewFiles := 'keep';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.UndoEnabled.Checked);
    Assert.AreEqual('7', Page.UndoDepth.Text);
    Assert.IsTrue(Page.UndoPersist.Checked);
    Assert.AreEqual('50', Page.UndoMaxSize.Text);
    Assert.AreEqual(1, Page.UndoOnConflict.Choice);
    Assert.AreEqual(2, Page.UndoNewFiles.Choice);
    Assert.IsTrue(Page.UndoKey.Text <> '');
    Assert.IsTrue(Page.RedoKey.Text <> '');
    Page.UndoEnabled.Checked := False;
    Page.UndoPersist.Checked := False;
    Page.UndoDepth.Text := '999';
    Page.UndoMaxSize.Text := '0';
    Page.UndoOnConflict.Choice := 0;
    Page.UndoNewFiles.Choice := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.UndoMultiFile);
    Assert.IsFalse(Saved.UndoMultiFilePersist);
    // Begrenzt auf den erlaubten Bereich.
    Assert.AreEqual(TAtlasPluginSettings.MaxUndoDepth, Saved.UndoMultiFileDepth);
    Assert.AreEqual(TAtlasPluginSettings.MinUndoMaxSizeMb, Saved.UndoMultiFileMaxSizeMb);
    Assert.AreEqual('partial', Saved.UndoMultiFileOnConflict);
    Assert.AreEqual('delete', Saved.UndoMultiFileNewFiles);
    Assert.AreEqual(Settings.UndoKey, Saved.UndoKey);
    Assert.AreEqual(Settings.RedoKey, Saved.RedoKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.MethodToggleRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #775: Schalter und beide Tasten; leeres Feld = keine Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.MethodToggle.Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($6026)), Page.MethodToggleUpKey.Text);
    Assert.AreEqual(ShortCutToText(TShortCut($6028)), Page.MethodToggleDownKey.Text);
    Page.MethodToggle.Checked := False;
    Page.MethodToggleUpKey.Text := '';
    Page.MethodToggleDownKey.Text := ShortCutToText(TShortCut($C044));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.MethodToggle);
    Assert.AreEqual(0, Saved.MethodToggleUpKey);
    Assert.AreEqual($C044, Saved.MethodToggleDownKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SnippetsPageShowsCatalogAndValidates;
var
  Host: TForm;
  Page: TAtlasSnippetsPage;
  Own: TAtlasSnippet;
begin
  Own := Default(TAtlasSnippet);
  Own.Prefix := 'eigen';
  Own.Body := 'X;';
  Own.Origin := TAtlasSnippetOrigin.User;
  // Listen brauchen ein Fenster, wie in der IDE.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSnippetsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Page.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, [Own]));
    Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)) + 1, Page.Catalog.Count);
    Assert.AreEqual('', Page.Validate);
    // Zweite eigene mit demselben Kürzel: Meldung nennt das Kürzel.
    Page.Catalog.Update(Page.Catalog.AddNew, Own);
    Assert.IsTrue(Pos('eigen', Page.Validate) > 0);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSettingsPageTests.AcceptOptionsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung und automatische Breite.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.CommitCharacters := False;
  Settings.AutoUses := False;
  Settings.ParameterHints := False;
  Settings.OpenDelayMs := 300;
  Settings.ListWidth := 400;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.CommitChars.Checked);
    Assert.IsFalse(Page.AutoUses.Checked);
    Assert.IsFalse(Page.ParameterHints.Checked);
    Assert.AreEqual('300', Page.OpenDelay.Text);
    Assert.IsFalse(Page.AutoWidth.Checked);
    Page.CommitChars.Checked := True;
    Page.OpenDelay.Text := '0';
    Page.AutoWidth.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.CommitCharacters);
    Assert.IsFalse(Saved.AutoUses);
    Assert.IsFalse(Saved.ParameterHints);
    Assert.AreEqual(0, Saved.OpenDelayMs);
    Assert.AreEqual(0, Saved.ListWidth, 'automatische Breite');
    // Version des Servers neben dem Pfad.
    Page.OnServerVersion :=
      function(APath: string): string
      begin
        Result := '1.2.3.4';
      end;
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ServerPageRunsActions;
var
  Host: TForm;
  Page: TAtlasServerPage;
  Global, Deleted: Boolean;
begin
  // Listen brauchen ein Fenster, wie in der IDE.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasServerPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    // Ohne Ereignisse ist alles aus.
    Assert.IsFalse(Page.BaselineUpdate.Enabled);
    Assert.IsFalse(Page.CacheClear.Enabled);
    Global := False;
    Deleted := False;
    Page.OnEditGlobal :=
      procedure
      begin
        Global := True;
      end;
    Page.OnBaselineInfo :=
      function: string
      begin
        Result := '5 Treffer in 2 Einträgen';
      end;
    Page.OnBaselineDelete :=
      function: string
      begin
        Deleted := True;
        Result := 'gelöscht';
      end;
    Page.OnSuppressions :=
      function: TArray<string>
      begin
        Result := ['no-with: 3 (ungenutzt 1, in 2 Dateien)'];
      end;
    Page.OnClearCache :=
      function: string
      begin
        Result := 'Cache leer';
      end;
    Page.Confirm :=
      function(AQuestion: string): Boolean
      begin
        Result := True;
      end;
    Page.Refresh;
    Assert.AreEqual('5 Treffer in 2 Einträgen', Page.BaselineInfo.Caption);
    Page.EditGlobal.Click;
    Assert.IsTrue(Global);
    Page.BaselineDelete.Click;
    Assert.IsTrue(Deleted);
    Assert.AreEqual('gelöscht', Page.BaselineInfo.Caption);
    Page.SuppressionsRefresh.Click;
    Assert.AreEqual(1, Page.Suppressions.Items.Count);
    Page.CacheClear.Click;
    Assert.AreEqual('Cache leer', Page.CacheInfo.Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DialogShowsOriginAndResetsToGlobal;
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
begin
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{"language": "en"}',
    '{"language": "de", "encoding": "windows-1252"}', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Ptlas.json');
    try
      Assert.IsTrue(Dialog.SelectPage('Allgemein'));
      Assert.IsTrue(Pos('Projekt', Dialog.StateText('language')) > 0);
      Assert.IsTrue(Pos('windows-1252', Dialog.StateText('encoding')) > 0, 'global geerbt');
      Model.Reset(Model.IndexOf('language'));
      Assert.AreEqual('{}', Model.ResultText);
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DialogRuleTableChangesOnlyThatRule;
const
  Text = '{' + #13#10 + '  "rules": {' + #13#10 + '    "no-with": "error" // streng' + #13#10 + '  }' + #13#10 + '}';
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
begin
  Catalog := TJSONObject.ParseJSONValue('{"rules": [{"id": "no-with", "name": "Kein with", "category": "code-smell",' +
    ' "severity": "warning"}, {"id": "empty-except", "name": "Leeres except", "category": "bug",' +
    ' "severity": "error"}]}');
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), Text, '', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Ptlas.json');
    try
      Dialog.Catalog := Catalog;
      Assert.IsTrue(Dialog.SelectPage(Model.Fields[Model.IndexOf('rules')].Page));
      Assert.AreEqual(2, Dialog.RuleList.Items.Count);
      Assert.IsTrue(Dialog.SetRuleSeverity('no-with', 'off'));
      Assert.AreEqual(StringReplace(Text, '"error"', '"off"', []), Model.ResultText);
      Assert.IsFalse(Dialog.SetRuleSeverity('unbekannt', 'off'));
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DialogValidatesBeforeSaving;
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Checked: Integer;
begin
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', True);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Users\X\settings.json');
    try
      Checked := 0;
      Dialog.OnValidate :=
        function(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>
        begin
          Inc(Checked);
          AChecked := True;
          Result := nil;
        end;
      // Unverändert: nichts zu prüfen.
      Assert.IsTrue(Dialog.Validate);
      Assert.AreEqual(0, Checked);
      Model.SetValue(Model.IndexOf('memoryBudgetMb'), '256');
      Assert.IsTrue(Dialog.Validate);
      Assert.AreEqual(1, Checked);
      Dialog.ServerChecks := False;
      Assert.IsTrue(Dialog.HintLabel.Visible, 'Hinweis: nur Syntax');
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SymbolResourcesInAllSizes;
var
  Variant_: TAtlasSymbolVariant;
  Index: Integer;
  Image: TWICImage;
  Icon: TIcon;
  Collection: TImageCollection;
begin
  // #751: jede Größe beider Varianten ist als PNG eingebunden und hat genau diese Größe.
  for Variant_ := Low(TAtlasSymbolVariant) to High(TAtlasSymbolVariant) do
  begin
    for Index := 0 to TAtlasSymbol.SizeCount - 1 do
    begin
      Image := TAtlasSymbolImages.Load(Variant_, TAtlasSymbol.Size(Index));
      try
        Assert.IsNotNull(Image, TAtlasSymbol.ResourceName(Variant_, TAtlasSymbol.Size(Index)));
        Assert.AreEqual(TAtlasSymbol.Size(Index), Image.Width);
      finally
        Image.Free;
      end;
    end;
    Icon := TAtlasSymbolImages.Icon(Variant_);
    try
      Assert.IsFalse(Icon.Empty, TAtlasSymbol.IconName(Variant_));
    finally
      Icon.Free;
    end;
  end;
  Collection := TAtlasSymbolImages.Collection(nil);
  try
    Assert.AreEqual(2, Collection.Images.Count);
    Assert.AreEqual(TAtlasSymbol.SizeCount, Collection.Images[1].SourceImages.Count);
  finally
    Collection.Free;
  end;
end;

procedure TAtlasSettingsPageTests.PageHeaderShowsSymbol;
var
  Page: TAtlasSettingsPage;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsNotNull(Page.Symbol);
    Assert.AreEqual(TAtlasSymbol.HeaderSize, Page.Symbol.LogicalSize);
    Assert.AreEqual(TAtlasSymbol.PixelSize(TAtlasSymbol.HeaderSize, Page.Symbol.CurrentPPI), Page.Symbol.Width);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.