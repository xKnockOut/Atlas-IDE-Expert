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
    procedure ShowsAndReenablesTrippedFeatures;
    [Test]
    procedure IndexSectionRoundTripsAndRunsCommands;
    [Test]
    procedure StatusFieldRoundTrips;
    [Test]
    procedure ShortcutTipsRoundTrip;
    /// <summary>Benachrichtigungszentrale (#601): Schalter, Höchstzahl und Verhalten je Quelle auf dem Reiter
    /// Allgemein, Taste auf dem Reiter Befehle.</summary>
    [Test]
    procedure NotificationsRoundTrip;
    [Test]
    procedure SafeModeRoundTrips;
    [Test]
    procedure UndoSettingsRoundTrip;
    /// <summary>Favoriten (#458): Schalter, Liste, „Entfernen“ und „Alle entfernen“.</summary>
    [Test]
    procedure FavoritesListAndRemove;
    [Test]
    procedure AcceptOptionsRoundTrip;
    [Test]
    procedure PageHeaderShowsSymbol;
    /// <summary>Filter im Baum und „Seite zurücksetzen“ je Knoten (#890).</summary>
    [Test]
    procedure FilterAndResetPerNode;
    /// <summary>„Wächter testen“ nur im Diagnosemodus.</summary>
    [Test]
    procedure HangTestOnlyInDiagnosticMode;
    /// <summary>#909: Bereich Prüfregeln mit Prüffenster, Knoten je Gruppe, Hauptschalter, Reveal einer Regel
    /// und den Änderungen für settings.json.</summary>
    [Test]
    procedure RulesAreaWindowSettings;
    /// <summary>#1108: offene Units zuerst auf dem Knoten „Prüffenster“; der Schalter sperrt seine Unterpunkte.
    /// </summary>
    [Test]
    procedure ProblemsWindowOpenFirstLocksItsOptions;
    /// <summary>Reiter „Projektdatei“ (#486): jeder Wert mit „aus .atlas“, Hinweise, Öffnen.</summary>
    [Test]
    procedure TeamFileTabShowsValuesFromAtlas;
    /// <summary>Hauptschalter für experimentelle Funktionen (#834): Vorgabe aus, Rundweg, Filterzeile.</summary>
    [Test]
    procedure ExperimentalSwitchRoundTrips;
    /// <summary>Filter „Nur experimentelle“ und „Geändert“ (#834): Kennzeichen, Ausblenden, Zusammenrücken,
    /// Wiederherstellen.</summary>
    [Test]
    procedure FilterHidesAndRestoresRows;
  end;

implementation

uses
  Atlas.UI.Settings.Page.Tree,
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Settings.Page,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Style.Symbol,
  System.StrUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Menus,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Index,
  Atlas.UI.Settings.Page.Robustness,
  Atlas.UI.Settings.Page.Rules,
  Atlas.UI.Settings.Page.Startup,
  Atlas.UI.Settings.Page.TeamFile;

procedure TAtlasSettingsPageTests.WarmUp;
begin
  WarmUpSettingsPage;
  FilterAndResetPerNode;
  // Erste Fehler legen die Listen der Sicherung an.
  TAtlasGuard.ReportProvider('Testquelle', 'Fehler');
  TAtlasGuard.Fuse.Failed(TAtlasFeature.Pairs);
  TAtlasGuard.Fuse.ResetAll;
end;
procedure TAtlasSettingsPageTests.FilterAndResetPerNode;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mMinimap: TTabSheet;
begin
  // #890: Der Filter blendet Knoten ohne Treffer aus; „Seite zurücksetzen“ wirkt auf den gewählten Knoten.
  TAtlasSettingsPageTree.ForgetTreeState;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.ExperimentalEnabled := True;
    mSettings.Minimap := True;
    mPage.LoadFrom(mSettings);
    mMinimap := mPage.NodeSheet('editor.minimap');
    mPage.Filter.Choice := 2;
    mPage.Filter.OnChange(mPage.Filter);
    Assert.IsTrue(Length(TopLevelNodes(mPage)) < 14, 'Bereiche ohne experimentelle Einstellung fehlen');
    Assert.IsNotNull(TreeNodeOf(mPage, mMinimap), 'Minikarte ist experimentell');
    mPage.Filter.Choice := 0;
    mPage.Filter.OnChange(mPage.Filter);
    // Bereiche von Base ohne Module (#1456), darunter „Prüfregeln“ (#909); ohne Versionsverwaltung (#1905).
    Assert.AreEqual(14, Integer(Length(TopLevelNodes(mPage))));
    // Zurücksetzen auf dem Unterpunkt: nur die Minikarte.
    EditOf(mPage, 'MinimapWidth').Text := '90';
    EditOf(mPage, 'StickyScrollMaxLines').Text := '7';
    mPage.Navigation.OnChange(mPage.Navigation, TreeNodeOf(mPage, mMinimap));
    mPage.ResetPage;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual(TAtlasPluginSettings.Defaults.MinimapWidth, mSaved.MinimapWidth, 'zurückgesetzt');
    Assert.AreEqual(7, mSaved.StickyScrollMaxLines, 'anderer Unterpunkt bleibt');
    Assert.IsTrue(mSaved.ExperimentalEnabled);
  finally
    mHost.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;
procedure TAtlasSettingsPageTests.TeamFileTabShowsValuesFromAtlas;
var
  mPage: TAtlasSettingsPage;
  mTeam: TAtlasTeamSettings;
  mOpened: Integer;
  mSettings: TAtlasPluginSettings;
begin
  mTeam := TAtlasTeamFile.Parse('{"version": 1, "naming": {"field": "F"}, "snippets": "Vorlagen", "token": "x"}',
    'C:\Repo\.atlas', 'C:\Repo');
  mTeam.Project := 'C:\Repo\Kasse.dproj';
  mOpened := 0;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mPage.LoadFrom(mSettings);
    Assert.Contains(mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption,
      TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileNoProject));
    Assert.IsFalse(mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileOpenButton.Enabled, 'ohne Projekt');
    mPage.Part<TAtlasSettingsTeamFilePart>.OnTeamFile :=
      function: TAtlasTeamSettings
      begin
        Result := mTeam; // lsp-ignore: captured-loop-variable -- Absicht: liest den jeweils aktuellen Wert
      end;
    mPage.Part<TAtlasSettingsTeamFilePart>.OnOpenTeamFile :=
      procedure
      begin
        Inc(mOpened);
      end;
    Assert.Contains(mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption,
      TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileValue,
      ['naming.field', '"F"']));
    Assert.Contains(mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption,
      TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileIssues, [1]),
      'Zugangsdaten ignoriert');
    Assert.Contains(mPage.Part<TAtlasSettingsTeamFilePart>.TeamSnippetsLabel.Caption, 'Vorlagen');
    Assert.IsTrue(mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileOpenButton.Enabled);
    mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileOpenButton.Click;
    Assert.AreEqual(1, mOpened);
    // Ausgeschaltet: keine Werte, kein Hinweis bei den Vorlagen, gespeichert als TeamFile = False.
    mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileCheck.Checked := False;
    Assert.AreEqual(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsTeamFileOff),
      mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption);
    Assert.AreEqual('', mPage.Part<TAtlasSettingsTeamFilePart>.TeamSnippetsLabel.Caption);
    mPage.SaveTo(mSettings);
    Assert.IsFalse(mSettings.TeamFile);
    // Fehlerhafte Datei: Hinweis statt Werte.
    mTeam := TAtlasTeamFile.Parse('{', 'C:\Repo\.atlas', 'C:\Repo');
    mTeam.Project := 'C:\Repo\Kasse.dproj';
    mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileCheck.Checked := True;
    // Mit Lage des Fehlers in der Datei (Zeile 1, Spalte 2 für "{").
    Assert.Contains(mPage.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption,
      TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsTeamFileInvalidAt, [1, 2]));
  finally
    mPage.Free;
  end;
end;
/// <summary>Werte von der Vorgabe abweichend setzen.</summary>
procedure SetPageRoundTrip(var ASettings: TAtlasPluginSettings);
begin
  ASettings.Enabled := False;
  ASettings.VisibleRows := 12;
  ASettings.Preview := True;
  ASettings.HoverTooltip := False;
  ASettings.XmlDocExpand := 'collapsed';
  ASettings.XmlDocMaxLines := 7;
  ASettings.ListWidth := 333;
  ASettings.ActionsKey := 0;
  ASettings.ExpandKey := $C057;
  ASettings.EditorKeysPriority := True;
  ASettings.SlashCommands := False;
  ASettings.Snippets := False;
  ASettings.ImportIdeTemplates := False;
  ASettings.ProviderTimeLimitMs := 400;
  ASettings.PairOwners := False;
  ASettings.PairGuideWidth := 3;
  ASettings.PairGuideOpacity := 70;
  ASettings.PairColorsLight := '#0071E3,#007C8A,#C000E0,#008700,#4040FF';
  ASettings.NestedRoutines := 'outer';
  ASettings.NestedRoutineBand := True;
  ASettings.NestedRoutineColorDark := '#123456';
  ASettings.TodoList := False;
  ASettings.MetricsReport := False;
  ASettings.TeamFile := False;
  ASettings.StartProfiles := False;
end;
/// <summary>Über die Seite gespeicherte Werte.</summary>
procedure AssertPageRoundTrip(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.Enabled);
  Assert.AreEqual(12, ASaved.VisibleRows);
  Assert.IsTrue(ASaved.Preview);
  Assert.IsFalse(ASaved.HoverTooltip);
  Assert.AreEqual('collapsed', ASaved.XmlDocExpand);
  Assert.AreEqual(7, ASaved.XmlDocMaxLines);
  Assert.AreEqual(333, ASaved.ListWidth);
  Assert.AreEqual(0, ASaved.ActionsKey);
  Assert.AreEqual($C057, ASaved.ExpandKey);
  Assert.AreEqual($6057, ASaved.ShrinkKey);
  Assert.IsTrue(ASaved.EditorKeysPriority);
  Assert.IsFalse(ASaved.SlashCommands);
  Assert.IsFalse(ASaved.Snippets);
  Assert.IsFalse(ASaved.ImportIdeTemplates);
  Assert.AreEqual(400, ASaved.ProviderTimeLimitMs);
  Assert.IsFalse(ASaved.PairOwners);
  Assert.AreEqual(3, ASaved.PairGuideWidth);
  Assert.AreEqual(70, ASaved.PairGuideOpacity);
  Assert.AreEqual('#0071E3,#007C8A,#C000E0,#008700,#4040FF', ASaved.PairColorsLight);
  Assert.AreEqual('', ASaved.PairColorsDark, 'Standardfarben bleiben leer');
  Assert.AreEqual('outer', ASaved.NestedRoutines, 'Färbung lokaler Routinen (#1788)');
  Assert.IsTrue(ASaved.NestedRoutineBand, 'Band lokaler Routinen (#1788)');
  Assert.AreEqual('#123456', ASaved.NestedRoutineColorDark, 'eigene Farbe lokaler Routinen (#1788)');
  Assert.AreEqual('', ASaved.NestedRoutineColorLight, 'Standardfarbe bleibt leer (#1788)');
  Assert.IsFalse(ASaved.TodoList, 'Befehl (#68)');
  Assert.IsFalse(ASaved.MetricsReport, 'Befehl (#66)');
  Assert.IsFalse(ASaved.TeamFile, 'Projektdatei (#486)');
end;
procedure TAtlasSettingsPageTests.CreatesAndRoundTripsSettings;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  SetPageRoundTrip(mSettings);
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
  finally
    mPage.Free;
  end;
  AssertPageRoundTrip(mSaved);
end;
procedure TAtlasSettingsPageTests.ShowsAndReenablesTrippedFeatures;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mIndex: Integer;
begin
  TAtlasGuard.Fuse.ResetAll;
  try
    for mIndex := 1 to 3 do
    begin
      TAtlasGuard.ReportProvider('Testquelle', 'Fehler');
      TAtlasGuard.Fuse.Failed(TAtlasFeature.Pairs);
    end;
    // Die Liste der Sicherung braucht ein Fenster, wie in der IDE.
    mHost := TForm.CreateNew(nil);
    try
      mPage := TAtlasSettingsPage.Create(mHost);
      mPage.Parent := mHost;
      mPage.HandleNeeded;
      mPage.LoadFrom(TAtlasPluginSettings.Defaults);
      Assert.AreEqual(2, Integer(mPage.Part<TAtlasSettingsRobustnessPart>.FuseList.Items.Count));
      Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Pairs),
        mPage.Part<TAtlasSettingsRobustnessPart>.FuseList.Items[0]);
      Assert.AreEqual('Testquelle', mPage.Part<TAtlasSettingsRobustnessPart>.FuseList.Items[1]);
      Assert.IsTrue(mPage.Part<TAtlasSettingsRobustnessPart>.FuseEnableAll.Enabled);
      // Nur die Quelle wieder einschalten.
      mPage.Part<TAtlasSettingsRobustnessPart>.FuseList.Selected[1] := True;
      mPage.Part<TAtlasSettingsRobustnessPart>.FuseEnableSelected.Click;
      Assert.IsFalse(TAtlasGuard.ProviderDisabled('Testquelle'));
      Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      mPage.Part<TAtlasSettingsRobustnessPart>.FuseEnableAll.Click;
      Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Assert.AreEqual(1, Integer(mPage.Part<TAtlasSettingsRobustnessPart>.FuseList.Items.Count), 'nur der Hinweis „keine“');
      Assert.IsFalse(mPage.Part<TAtlasSettingsRobustnessPart>.FuseEnableAll.Enabled);
    finally
      mHost.Free;
    end;
  finally
    TAtlasGuard.Fuse.ResetAll;
  end;
end;
/// <summary>Antwort noch während des Ereignisses, wie ohne Server.</summary>
procedure AnswerIndexMetricsAtOnce(APage: TAtlasSettingsPage);
begin
  // Antwort noch während des Ereignisses, wie ohne Server.
  APage.Part<TAtlasSettingsIndexPart>.OnIndexMetrics :=
    procedure
    begin
      APage.Part<TAtlasSettingsIndexPart>.IndexAnswered('Units: 3');
    end;
end;
/// <summary>Antwort auf den Neuaufbau gibt die Befehle wieder frei.</summary>
procedure AnswerIndexRebuild(APage: TAtlasSettingsPage);
begin
  APage.Part<TAtlasSettingsIndexPart>.IndexAnswered('wird neu aufgebaut');
  Assert.IsFalse(APage.Part<TAtlasSettingsIndexPart>.IndexBusy);
  Assert.AreEqual('wird neu aufgebaut', APage.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
  Assert.IsTrue(APage.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled and
    APage.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled);
end;
procedure TAtlasSettingsPageTests.IndexSectionRoundTripsAndRunsCommands;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mConfirm: Boolean;
  mCleared: Integer;
  mRebuilds: Integer;
begin
  // #492: Verwendungen und Speicherbudget, Kennzahlen, Neuaufbau und Löschen mit Rückfrage.
  // #874: Die Befehle laufen im Hintergrund; die Antwort kommt über IndexAnswered.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.IndexUsages := False;
  mSettings.MemoryBudgetMb := 512;
  mConfirm := False;
  mCleared := 0;
  mRebuilds := 0;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsFalse(mPage.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled or
      mPage.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled, 'ohne Server keine Befehle');
    AnswerIndexMetricsAtOnce(mPage);
    // Antwort erst später, wie bei einem Server, der gerade indexiert.
    mPage.Part<TAtlasSettingsIndexPart>.OnIndexRebuild :=
      procedure
      begin
        Inc(mRebuilds);
      end;
    mPage.Part<TAtlasSettingsIndexPart>.OnIndexClear :=
      procedure
      begin
        Inc(mCleared);
        mPage.Part<TAtlasSettingsIndexPart>.IndexAnswered('gelöscht');
      end;
    mPage.Part<TAtlasSettingsIndexPart>.ConfirmClear :=
      function: Boolean
      begin
        Result := mConfirm;
      end;
    mPage.LoadFrom(mSettings);
    Assert.AreEqual('Units: 3', mPage.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
    Assert.IsTrue(mPage.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled and
      mPage.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled);
    mPage.Part<TAtlasSettingsIndexPart>.IndexRebuild.Click;
    Assert.AreEqual(1, mRebuilds);
    Assert.IsTrue(mPage.Part<TAtlasSettingsIndexPart>.IndexBusy);
    Assert.AreEqual(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexAsking),
      mPage.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
    Assert.IsFalse(mPage.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled or
      mPage.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled, 'gesperrt bis zur Antwort');
    mPage.Part<TAtlasSettingsIndexPart>.IndexRebuild.Click;
    Assert.AreEqual(1, mRebuilds, 'kein zweiter Befehl, solange einer läuft');
    AnswerIndexRebuild(mPage);
    mPage.Part<TAtlasSettingsIndexPart>.IndexClear.Click;
    Assert.AreEqual(0, mCleared, 'abgelehnt: nichts löschen');
    mConfirm := True;
    mPage.Part<TAtlasSettingsIndexPart>.IndexClear.Click;
    Assert.AreEqual(1, mCleared);
    Assert.AreEqual('gelöscht', mPage.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
  finally
    mPage.Free;
  end;
  Assert.IsFalse(mSaved.IndexUsages);
  Assert.AreEqual(512, mSaved.MemoryBudgetMb);
end;
procedure TAtlasSettingsPageTests.StatusFieldRoundTrips;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #591: Feld an/aus, Kurztext, ausgeblendete Zeilen; #479: Diagnosemodus, #625: Prüfliste auf derselben Seite.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.StatusField := False;
  mSettings.StatusFieldSummary := False;
  mSettings.StatusFieldToggles := 'rightClick';
  mSettings.IndexProgressPlace := 'off';
  mSettings.StatusFieldHidden := 'atlas.file';
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(CheckOf(mPage, 'StatusField').Checked);
    Assert.IsFalse(CheckOf(mPage, 'StatusFieldSummary').Checked);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsGeneralPart>.StatusToggles.Choice, 'nur Rechtsklick');
    Assert.AreEqual(2, mPage.Part<TAtlasSettingsGeneralPart>.IndexProgress.Choice, 'Fortschritt aus');
    Assert.AreEqual('atlas.file', mPage.Part<TAtlasSettingsGeneralPart>.StatusHidden.Text);
    Assert.IsFalse(mPage.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.Checked, 'Diagnosemodus standardmäßig aus');
    Assert.IsTrue(CheckOf(mPage, 'SetupChecklist').Checked, 'Prüfliste beim Start standardmäßig an (#625)');
    mPage.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.Checked := True;
    CheckOf(mPage, 'SetupChecklist').Checked := False;
    CheckOf(mPage, 'StatusField').Checked := True;
    mPage.Part<TAtlasSettingsGeneralPart>.StatusToggles.Choice := 2;
    mPage.Part<TAtlasSettingsGeneralPart>.IndexProgress.Choice := 1;
    mPage.Part<TAtlasSettingsGeneralPart>.StatusHidden.Text := ' atlas.file, atlas.index ';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.StatusField);
    Assert.IsTrue(mSaved.DiagnosticMode);
    Assert.IsFalse(mSaved.SetupChecklist);
    Assert.IsFalse(mSaved.StatusFieldSummary);
    Assert.AreEqual('doubleClick', mSaved.StatusFieldToggles);
    Assert.AreEqual('menu', mSaved.IndexProgressPlace);
    Assert.AreEqual('atlas.file, atlas.index', mSaved.StatusFieldHidden);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTests.ShortcutTipsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #600: shortcutTips.enabled und shortcutTips.scope auf der Seite Allgemein.
  mSettings := TAtlasPluginSettings.Defaults;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'ShortcutTips').Checked, 'Tipps standardmäßig an');
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsGeneralPart>.ShortcutTipsScope.Choice, 'Vorgabe all');
    CheckOf(mPage, 'ShortcutTips').Checked := False;
    mPage.Part<TAtlasSettingsGeneralPart>.ShortcutTipsScope.Choice := 0;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.ShortcutTips);
    Assert.AreEqual('atlas', mSaved.ShortcutTipsScope);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'ShortcutTips').Checked);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsGeneralPart>.ShortcutTipsScope.Choice);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTests.NotificationsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mPart: TAtlasSettingsNotificationsPart;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.NotificationsSources := 'server=off, buildServer=collect, tracker=off';
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    mPart := mPage.Part<TAtlasSettingsNotificationsPart>;
    Assert.IsTrue(CheckOf(mPage, 'Notifications').Checked, 'standardmäßig an');
    Assert.AreEqual('200', mPart.NotificationsMax.Text);
    Assert.AreEqual(ShortCutToText($E04E), EditOf(mPage, 'NotificationsKey').Text, 'Strg+Umschalt+Alt+N');
    // Erste Quelle (build) ohne Angabe: einblenden.
    Assert.AreEqual(0, mPart.NotificationSource.Choice);
    Assert.AreEqual(0, mPart.NotificationMode.Choice);
    // Quelle server (vierte) zeigt „aus“.
    mPart.NotificationSource.Choice := 3;
    mPart.NotificationSource.OnChange(mPart.NotificationSource);
    Assert.AreEqual(2, mPart.NotificationMode.Choice);
    // Build-Server (sechste, #763) zeigt „nur sammeln“.
    mPart.NotificationSource.Choice := 5;
    mPart.NotificationSource.OnChange(mPart.NotificationSource);
    Assert.AreEqual(1, mPart.NotificationMode.Choice);
    // Tastenkürzel-Tipps (fünfte) auf „nur sammeln“.
    mPart.NotificationSource.Choice := 4;
    mPart.NotificationSource.OnChange(mPart.NotificationSource);
    mPart.NotificationMode.Choice := 1;
    mPart.NotificationMode.OnChange(mPart.NotificationMode);
    CheckOf(mPage, 'Notifications').Checked := False;
    mPart.NotificationsMax.Text := '50';
    EditOf(mPage, 'NotificationsKey').Text := '';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
  finally
    mPage.Free;
  end;
  Assert.IsFalse(mSaved.Notifications);
  Assert.AreEqual(50, mSaved.NotificationsMaxEntries);
  Assert.AreEqual(0, mSaved.NotificationsKey, 'leer = keine Taste');
  // Build-Server (#763, sechste Quelle) behält sein Verhalten; unbekannte Quellen bleiben erhalten.
  Assert.AreEqual('server=off, buildServer=collect, tracker=off, shortcutTips=collect', mSaved.NotificationsSources);
end;
procedure TAtlasSettingsPageTests.ExperimentalSwitchRoundTrips;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.ExperimentalEnabled);
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(mPage.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked);
    Assert.IsNotNull(mPage.Filter);
    Assert.AreEqual(0, mPage.Filter.Choice);
    // Ohne experimentelle Einstellung im Katalog kein Hinweis.
    Assert.AreEqual(mPage.Marks.HasExperimental, mPage.ExperimentalBanner.Visible);
    mPage.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.ExperimentalEnabled);
    mPage.LoadFrom(mSaved);
    Assert.IsTrue(mPage.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked);
    Assert.IsFalse(mPage.ExperimentalBanner.Visible);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTests.FilterHidesAndRestoresRows;
var
  mOwner: TComponent;
  mBox: TScrollBox;
  mMarks: TAtlasSettingsMarks;
  mFirst, mSecond, mThird: TCheckBox;

  function Check(const ACaption: string; ATop: Integer): TCheckBox;
  begin
    Result := TCheckBox.Create(mOwner);
    Result.Parent := mBox;
    Result.Caption := ACaption;
    Result.Top := ATop;
  end;

begin
  mOwner := TComponent.Create(nil);
  try
    mBox := TScrollBox.Create(mOwner);
    mMarks := TAtlasSettingsMarks.Create(mOwner);
    mFirst := Check('Erste', 10);
    mSecond := Check('Zweite', 40);
    mThird := Check('Dritte', 70);
    mMarks.Bind(mFirst, ['First']);
    mMarks.Bind(mSecond, ['Second']);
    mMarks.Bind(mThird, ['Third']);
    mMarks.MarkExperimental(['third']);
    Assert.IsTrue(mMarks.HasExperimental);
    Assert.IsTrue(mMarks.IsExperimental(mThird));
    Assert.IsFalse(mMarks.IsExperimental(mFirst));
    Assert.AreEqual('Dritte  [' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExperimentalTag) + ']',
      string(mThird.Caption));
    mMarks.ApplyFilter(sfExperimental);
    Assert.IsFalse(mFirst.Visible);
    Assert.IsFalse(mSecond.Visible);
    Assert.IsTrue(mThird.Visible);
    // Rückt an den Platz der ersten Zeile.
    Assert.AreEqual(10, mThird.Top);
    mMarks.Show(['Second'], True);
    mMarks.ApplyFilter(sfModified);
    Assert.IsFalse(mFirst.Visible);
    Assert.IsTrue(mSecond.Visible);
    Assert.IsFalse(mThird.Visible);
    Assert.AreEqual(10, mSecond.Top);
    mMarks.ApplyFilter(sfAll);
    Assert.IsTrue(mFirst.Visible and mSecond.Visible and mThird.Visible);
    Assert.AreEqual(10, mFirst.Top);
    Assert.AreEqual(40, mSecond.Top);
    Assert.AreEqual(70, mThird.Top);
    Assert.AreEqual<TAtlasSettingsFilter>(sfAll, mMarks.Filter);
  finally
    mOwner.Free;
  end;
end;
procedure TAtlasSettingsPageTests.SafeModeRoundTrips;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #722: Rückfrage, ohne Rückfrage nach zwei Abstürzen, Taste, Zeitlimit, gemerkte Stände.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.SafeAskAfterCrash := False;
  mSettings.SafeStartupKey := 'ctrl';
  mSettings.SafeStartupTimeoutMs := 20000;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(CheckOf(mPage, 'SafeAskAfterCrash').Checked);
    Assert.IsTrue(CheckOf(mPage, 'SafeAutoAfterRepeatedCrash').Checked);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsStartupPart>.SafeKey.Choice);
    Assert.AreEqual('20000', EditOf(mPage, 'SafeStartupTimeoutMs').Text);
    Assert.AreEqual('5', EditOf(mPage, 'SafeKeepSettingsHistory').Text);
    CheckOf(mPage, 'SafeAutoAfterRepeatedCrash').Checked := False;
    mPage.Part<TAtlasSettingsStartupPart>.SafeKey.Choice := 2;
    EditOf(mPage, 'SafeKeepSettingsHistory').Text := '500';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.SafeAskAfterCrash);
    Assert.IsFalse(mSaved.SafeAutoAfterRepeatedCrash);
    Assert.AreEqual('none', mSaved.SafeStartupKey);
    Assert.AreEqual(20000, mSaved.SafeStartupTimeoutMs);
    // Begrenzt auf die Höchstzahl.
    Assert.AreEqual(TAtlasPluginSettings.cMaxSafeSettingsHistory, mSaved.SafeKeepSettingsHistory);
  finally
    mPage.Free;
  end;
end;
/// <summary>Die Seite liest und löst Favoriten über AFavorites.</summary>
procedure WireFavorites(APage: TAtlasSettingsPage; AFavorites: TAtlasFavorites);
begin
  APage.Part<TAtlasSettingsFavoritesPart>.OnRemoveFavorites :=
    procedure(AKeys: TArray<string>)
    var
      Key: string;
    begin
      for Key in AKeys do
      begin
        AFavorites.Remove(Key);
      end;
    end;
  APage.Part<TAtlasSettingsFavoritesPart>.OnFavorites :=
    function: TArray<TAtlasFavorite>
    begin
      Result := AFavorites.Items;
    end;
end;
procedure TAtlasSettingsPageTests.FavoritesListAndRemove;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mFavorites: TAtlasFavorites;
  mSettings, mSaved: TAtlasPluginSettings;
  mItem: TAtlasCompletionItem;
  mNames: TArray<string>;
  mName: string;
begin
  mNames := ['Open', 'Close', 'ParamByName'];
  mFavorites := TAtlasFavorites.Create;
  mHost := TForm.CreateNew(nil);
  try
    for mName in mNames do
    begin
      mItem := Default(TAtlasCompletionItem);
      mItem.Name := mName;
      mItem.DeclaringClass := 'TDataSet';
      mFavorites.Toggle(mItem);
    end;
    // Die Liste braucht ein Fenster, wie in der IDE.
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireFavorites(mPage, mFavorites);
    mSettings := TAtlasPluginSettings.Defaults;
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(mPage.Part<TAtlasSettingsCompletionPart>.FavoritesCheck.Checked);
    mPage.Part<TAtlasSettingsCompletionPart>.FavoritesCheck.Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.Favorites, 'abschaltbar');
    Assert.IsFalse(mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesRemove.Enabled, 'Liste gehört zum Schalter (#890)');
    mPage.Part<TAtlasSettingsCompletionPart>.FavoritesCheck.Checked := True;
    Assert.AreEqual(3, Integer(mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items.Count));
    Assert.AreEqual('TDataSet.Open', mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items[0]);
    mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Selected[1] := True;
    mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesRemove.Click;
    Assert.AreEqual(2, Integer(mFavorites.Count), 'Close gelöst');
    Assert.AreEqual('TDataSet.ParamByName', mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items[1]);
    mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesRemoveAll.Click;
    Assert.AreEqual(0, Integer(mFavorites.Count));
    Assert.AreEqual(1, Integer(mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items.Count), 'nur der Hinweis „keine“');
    Assert.IsFalse(mPage.Part<TAtlasSettingsFavoritesPart>.FavoritesRemoveAll.Enabled);
  finally
    mHost.Free;
    mFavorites.Free;
  end;
end;
procedure TAtlasSettingsPageTests.UndoSettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // #721: Ein/Aus, Tiefe, Sicherung, Größe, Konflikte, neue Dateien und die beiden Tasten.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.UndoMultiFileDepth := 7;
  mSettings.UndoMultiFileOnConflict := 'abort';
  mSettings.UndoMultiFileNewFiles := 'keep';
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'UndoMultiFile').Checked);
    Assert.AreEqual('7', EditOf(mPage, 'UndoMultiFileDepth').Text);
    Assert.IsTrue(CheckOf(mPage, 'UndoMultiFilePersist').Checked);
    Assert.AreEqual('50', EditOf(mPage, 'UndoMultiFileMaxSizeMb').Text);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsStartupPart>.UndoOnConflict.Choice);
    Assert.AreEqual(2, mPage.Part<TAtlasSettingsStartupPart>.UndoNewFiles.Choice);
    Assert.AreNotEqual('', EditOf(mPage, 'UndoKey').Text);
    Assert.AreNotEqual('', EditOf(mPage, 'RedoKey').Text);
    CheckOf(mPage, 'UndoMultiFile').Checked := False;
    CheckOf(mPage, 'UndoMultiFilePersist').Checked := False;
    EditOf(mPage, 'UndoMultiFileDepth').Text := '999';
    EditOf(mPage, 'UndoMultiFileMaxSizeMb').Text := '0';
    mPage.Part<TAtlasSettingsStartupPart>.UndoOnConflict.Choice := 0;
    mPage.Part<TAtlasSettingsStartupPart>.UndoNewFiles.Choice := 1;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.UndoMultiFile);
    Assert.IsFalse(mSaved.UndoMultiFilePersist);
    // Begrenzt auf den erlaubten Bereich.
    Assert.AreEqual(TAtlasPluginSettings.cMaxUndoDepth, mSaved.UndoMultiFileDepth);
    Assert.AreEqual(TAtlasPluginSettings.cMinUndoMaxSizeMb, mSaved.UndoMultiFileMaxSizeMb);
    Assert.AreEqual('partial', mSaved.UndoMultiFileOnConflict);
    Assert.AreEqual('delete', mSaved.UndoMultiFileNewFiles);
    Assert.AreEqual(mSettings.UndoKey, mSaved.UndoKey);
    Assert.AreEqual(mSettings.RedoKey, mSaved.RedoKey);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTests.AcceptOptionsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung und automatische Breite.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.CommitCharacters := False;
  mSettings.AutoUses := False;
  mSettings.ParameterHints := False;
  mSettings.FormatPlaceholders := False;
  mSettings.OpenDelayMs := 300;
  mSettings.ListWidth := 400;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(CheckOf(mPage, 'CommitCharacters').Checked);
    Assert.IsFalse(CheckOf(mPage, 'AutoUses').Checked);
    Assert.IsFalse(CheckOf(mPage, 'ParameterHints').Checked);
    Assert.IsFalse(CheckOf(mPage, 'FormatPlaceholders').Checked);
    Assert.AreEqual('300', EditOf(mPage, 'OpenDelayMs').Text);
    Assert.IsFalse(mPage.Part<TAtlasSettingsCompletionPart>.AutoWidth.Checked);
    CheckOf(mPage, 'CommitCharacters').Checked := True;
    CheckOf(mPage, 'FormatPlaceholders').Checked := True;
    EditOf(mPage, 'OpenDelayMs').Text := '0';
    mPage.Part<TAtlasSettingsCompletionPart>.AutoWidth.Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.CommitCharacters);
    Assert.IsFalse(mSaved.AutoUses);
    Assert.IsFalse(mSaved.ParameterHints);
    Assert.IsTrue(mSaved.FormatPlaceholders);
    Assert.AreEqual(0, mSaved.OpenDelayMs);
    Assert.AreEqual(0, mSaved.ListWidth, 'automatische Breite');
    // Version des Servers neben dem Pfad.
    mPage.Part<TAtlasSettingsGeneralPart>.OnServerVersion :=
      function(APath: string): string
      begin
        Result := '1.2.3.4';
      end;
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTests.PageHeaderShowsSymbol;
var
  mPage: TAtlasSettingsPage;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsNotNull(mPage.Symbol);
    Assert.AreEqual(TAtlasSymbol.cHeaderSize, mPage.Symbol.LogicalSize);
    Assert.AreEqual(TAtlasSymbol.PixelSize(TAtlasSymbol.cHeaderSize, mPage.Symbol.CurrentPPI), mPage.Symbol.Width);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTests.HangTestOnlyInDiagnosticMode;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.DiagnosticMode := False;
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(mPage.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'ohne Diagnosemodus verborgen');
    mPage.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.Checked := True;
    Assert.IsTrue(mPage.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'sofort sichtbar, wenn der Diagnosemodus eingeschaltet wird');
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(mPage.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'nach dem Laden ohne Diagnosemodus wieder verborgen');
    mSettings.DiagnosticMode := True;
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(mPage.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'mit Diagnosemodus geladen');
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTests.ProblemsWindowOpenFirstLocksItsOptions;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(CheckOf(mPage, 'ProblemsWindowOpenFirst').Checked);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Choice);
    Assert.IsTrue(CheckOf(mPage, 'ProblemsWindowShowCleanActive').Checked);
    Assert.AreSame(mPage.NodeSheet('rules.window'), SheetOf(CheckOf(mPage, 'ProblemsWindowOpenFirst')));
    Assert.AreSame(mPage.NodeSheet('rules.window'),
      SheetOf(mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice));
    Assert.IsTrue(mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Enabled and
      CheckOf(mPage, 'ProblemsWindowShowCleanActive').Enabled);
    CheckOf(mPage, 'ProblemsWindowOpenFirst').Checked := False;
    Assert.IsFalse(mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Enabled, 'Auswahl gesperrt');
    Assert.IsFalse(CheckOf(mPage, 'ProblemsWindowShowCleanActive').Enabled, 'Schalter gesperrt');
    mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Choice := 2;
    CheckOf(mPage, 'ProblemsWindowShowCleanActive').Checked := False;
    mSettings := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSettings);
    Assert.IsFalse(mSettings.ProblemsWindowOpenFirst);
    Assert.AreEqual('hidden', mSettings.ProblemsWindowClosedUnits);
    Assert.IsFalse(mSettings.ProblemsWindowShowCleanActive);
    CheckOf(mPage, 'ProblemsWindowOpenFirst').Checked := True;
    Assert.IsTrue(mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Enabled, 'wieder frei');
  finally
    mPage.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;
/// <summary>Knoten des Bereichs Regeln: Prüffenster; „Profile und Baseline“ und die Regelgruppen kommen vom
/// Modul Prüfregeln (#1755).</summary>
procedure AssertRulesNodes(APage: TAtlasSettingsPage);
begin
  Assert.AreSame(APage.NodeSheet('rules.window'), SheetOf(CheckOf(APage, 'ProblemsWindow')));
  Assert.AreSame(APage.NodeSheet('rules.window'), SheetOf(APage.Part<TAtlasSettingsRulesPart>.ProblemsUpdateChoice));
  Assert.AreSame(APage.NodeSheet('rules.window'), SheetOf(APage.Part<TAtlasSettingsRulesPart>.ProblemsLiveDelayEdit));
  Assert.IsNull(APage.NodeSheet('rules.profiles'), 'Profile und Baseline im Abschnitt des Moduls');
  Assert.IsNull(APage.NodeSheet('rules.group.threads'), 'keine Regelgruppen in Tools › Optionen');
end;
/// <summary>Gespeicherte Einstellungen des Prüffensters und der Gruppe „Compiler vorab“.</summary>
procedure AssertRulesAreaSaved(const ASettings: TAtlasPluginSettings);
begin
  Assert.AreEqual('both', ASettings.ProblemsCompilerMerge);
  Assert.IsFalse(ASettings.ProblemsShowCompilerCode);
  Assert.AreEqual('file', ASettings.ProblemsWindowScope);
  Assert.IsFalse(ASettings.ProblemsWindowScopeProjects, 'Einzelprojekte (#1843) gespeichert');
  Assert.AreEqual('rule', ASettings.ProblemsWindowGroupBy);
  Assert.IsTrue(ASettings.ProblemsWindowCompiler);
  Assert.AreEqual('save', ASettings.ProblemsUpdate, 'Aktualisierung gespeichert');
  Assert.AreEqual(800, ASettings.ProblemsLiveDelayMs, 'Verzögerung gespeichert');
  Assert.IsFalse(ASettings.HoverProblemActions, 'Hover-Aktionen gespeichert');
end;
procedure TAtlasSettingsPageTests.RulesAreaWindowSettings;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
begin
  TAtlasSettingsPageTree.ForgetTreeState;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    // Knoten: Prüffenster und Compiler vorab; die Wege zu den Regeln, Baseline und Unterdrückungen bringt das
    // Modul Prüfregeln als Abschnitt mit (#1755, Atlas.UI.Rules.SettingsSection.Tests).
    AssertRulesNodes(mPage);
    // Einstellungen des Prüffensters im Rundweg.
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.ProblemsWindowScope := 'project';
    mSettings.ProblemsWindowGroupBy := 'rule';
    mSettings.ProblemsUpdate := 'manual';
    mSettings.ProblemsLiveDelayMs := 1200;
    mSettings.HoverProblemActions := False;
    mPage.LoadFrom(mSettings);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowScopeChoice.Choice);
    Assert.AreEqual(2, mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowGroupByChoice.Choice);
    Assert.AreEqual(2, mPage.Part<TAtlasSettingsRulesPart>.ProblemsUpdateChoice.Choice, 'Aktualisierung geladen');
    Assert.AreEqual('1200', mPage.Part<TAtlasSettingsRulesPart>.ProblemsLiveDelayEdit.Text, 'Verzögerung geladen');
    mPage.Part<TAtlasSettingsRulesPart>.ProblemsUpdateChoice.Choice := 1;
    mPage.Part<TAtlasSettingsRulesPart>.ProblemsLiveDelayEdit.Text := '800';
    Assert.IsFalse(CheckOf(mPage, 'HoverProblemActions').Checked, 'Hover-Aktionen geladen');
    mPage.Part<TAtlasSettingsRulesPart>.ProblemsWindowScopeChoice.Choice := 0;
    Assert.IsTrue(CheckOf(mPage, 'ProblemsWindowScopeProjects').Checked, 'Einzelprojekte (#1843) geladen');
    CheckOf(mPage, 'ProblemsWindowScopeProjects').Checked := False;
    CheckOf(mPage, 'ProblemsWindowCompiler').Checked := True;
    // Gruppe „Compiler vorab“ (#1024): eigener Knoten mit den Plugin-Einstellungen der Gruppe.
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsRulesPart>.ProblemsCompilerMergeChoice.Choice);
    Assert.IsTrue(CheckOf(mPage, 'ProblemsShowCompilerCode').Checked);
    Assert.AreSame(mPage.NodeSheet('rules.group.compiler'), SheetOf(CheckOf(mPage, 'ProblemsShowCompilerCode')));
    mPage.Part<TAtlasSettingsRulesPart>.ProblemsCompilerMergeChoice.Choice := 1;
    CheckOf(mPage, 'ProblemsShowCompilerCode').Checked := False;
    mSettings := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSettings);
    AssertRulesAreaSaved(mSettings);
  finally
    mHost.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.
