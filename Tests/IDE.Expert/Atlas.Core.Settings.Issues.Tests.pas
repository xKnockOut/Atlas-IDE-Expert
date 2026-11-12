unit Atlas.Core.Settings.Issues.Tests;

// Tests der Einstellungen für Tracker, Versionsverwaltung und Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einstellungen von Tracker, Versionsverwaltung und Willkommensseite.</summary>
  [TestFixture]
  TAtlasIssueSettingsTests = class
  public
    /// <summary>#1260: issues.connections als JSON-Liste in settings.json, nie in der Registry; leere Liste
    /// ohne Eintrag, kaputter Text nie in die Datei.</summary>
    [Test]
    procedure IssuesConnectionsGoToGlobalFile;
    /// <summary>#1261: issues.projects wie die Verbindungen als JSON-Liste in settings.json.</summary>
    [Test]
    procedure IssuesProjectsGoToGlobalFile;
    /// <summary>#1262: issues.queries wie die Verbindungen als JSON-Liste in settings.json; issues.queryPicker
    /// bleibt in der Registry.</summary>
    [Test]
    procedure IssuesQueriesGoToGlobalFile;
    /// <summary>#1285: vcs.provider, vcs.git.path, vcs.svn.path und vcs.timeoutSeconds in settings.json (der
    /// Server liest dieselben Werte), nie in der Registry; ungültige Werte werden zur Vorgabe. #1288:
    /// vcs.branch.confirm nur im Plugin (Registry).</summary>
    [Test]
    procedure VcsSettingsGoToGlobalFile;
    /// <summary>Schnellaktionen der Willkommensseite (#764): Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure WelcomeQuickActionOptions;
    /// <summary>Meine Issues (#765): Vorgaben, Normalisieren (Leerzeichen am Ende des Commit-Musters bleibt),
    /// Speichern und Laden.</summary>
    [Test]
    procedure WelcomeIssuesOptions;
    /// <summary>Tracker nachführen (#1266): Vorgaben, Normalisieren und Speichern.</summary>
    [Test]
    procedure IssuesSyncOptions;
    /// <summary>Zeiterfassung (#1267): ab Werk aus, Leerlauf 10, Rundung 5, Grenzen, Speichern und Laden.</summary>
    [Test]
    procedure IssuesTimeOptions;
    /// <summary>Kommentar-Editor (#1278): Schalter und Textbausteine mit Vorgaben, Normalisieren und Speichern.</summary>
    [Test]
    procedure IssuesCommentOptions;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Scopes,
  Atlas.Core.Settings.TestSupport;

procedure TAtlasIssueSettingsTests.IssuesConnectionsGoToGlobalFile;
const
  cList = '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"}]';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('[]', mSettings.IssuesConnections);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.Save(mStore);
  Assert.IsFalse(mRouted.Text.Contains('issues'), 'leere Liste ohne Eintrag: ' + mRouted.Text);
  mSettings.IssuesConnections := cList;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"connections": [{"name": "Firma"');
  Assert.AreEqual('', mRegistry.ReadString('IssuesConnections', ''), 'nicht in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesConnections.Contains('"Firma"'), mLoaded.IssuesConnections);
  // Kaputter Text kommt nie in die Datei; der gespeicherte Stand bleibt.
  mStore.WriteString('IssuesConnections', '[{"name": ');
  Assert.Contains(mRouted.Text, '"Firma"');
  // Falsche Art in der Datei (der Server meldet sie): Vorgabe.
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '{"issues": {"connections": "Firma"}}');
  mStore := mRouted;
  mLoaded.Load(mStore);
  Assert.AreEqual('[]', mLoaded.IssuesConnections);
  Assert.IsTrue(MatchText('issues.connections', TAtlasSettingsScopes.IdeManagedPaths), 'nicht im Dialog');
end;
procedure TAtlasIssueSettingsTests.IssuesProjectsGoToGlobalFile;
const
  cList = '[{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", "connection": "Firma", "project": "KASSE"}]';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('[]', mSettings.IssuesProjects);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.Save(mStore);
  Assert.IsFalse(mRouted.Text.Contains('projects'), 'leere Liste ohne Eintrag: ' + mRouted.Text);
  mSettings.IssuesProjects := cList;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"projects": [{"match": ');
  Assert.AreEqual('', mRegistry.ReadString('IssuesProjects', ''), 'nicht in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesProjects.Contains('"KASSE"'), mLoaded.IssuesProjects);
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '{"issues": {"projects": 3}}');
  mStore := mRouted;
  mLoaded.Load(mStore);
  Assert.AreEqual('[]', mLoaded.IssuesProjects, 'falsche Art: Vorgabe');
  Assert.IsTrue(MatchText('issues.projects', TAtlasSettingsScopes.IdeManagedPaths), 'nicht im Dialog');
end;
procedure TAtlasIssueSettingsTests.IssuesQueriesGoToGlobalFile;
const
  cList = '[{"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma"}]';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.Save(mStore);
  Assert.IsFalse(mRouted.Text.Contains('queries'), 'leere Liste ohne Eintrag: ' + mRouted.Text);
  mSettings.IssuesQueries := cList;
  mSettings.IssuesQueryPicker := False;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"queries": [{"name": ');
  Assert.AreEqual('', mRegistry.ReadString('IssuesQueries', ''), 'nicht in der Registry');
  Assert.AreEqual(0, mRegistry.ReadInteger('IssuesQueryPicker', 1), 'Klappliste in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesQueries.Contains('"Sprint"'), mLoaded.IssuesQueries);
  Assert.IsFalse(mLoaded.IssuesQueryPicker);
  Assert.IsTrue(MatchText('issues.queries', TAtlasSettingsScopes.IdeManagedPaths), 'nicht im Dialog');
end;
/// <summary>#1285: Art, Werkzeugpfade und Zeitlimit in settings.json, ungültige Werte zur Vorgabe.</summary>
procedure VcsToolSettingsGoToGlobalFile;
const
  cGit = 'D:\Portable\Git\cmd\git.exe';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('auto', mSettings.VcsProvider);
  Assert.AreEqual('', mSettings.VcsGitPath, 'leer = automatisch suchen');
  Assert.AreEqual('', mSettings.VcsSvnPath);
  Assert.AreEqual(15, mSettings.VcsTimeoutSeconds);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.VcsProvider := 'svn';
  mSettings.VcsGitPath := cGit;
  mSettings.VcsTimeoutSeconds := 60;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"provider": "svn"');
  Assert.Contains(mRouted.Text, '"timeoutSeconds": 60');
  Assert.Contains(mRouted.Text, '"git": {');
  Assert.AreEqual('', mRegistry.ReadString('VcsGitPath', ''), 'nicht in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.AreEqual('svn', mLoaded.VcsProvider);
  Assert.AreEqual(cGit, mLoaded.VcsGitPath);
  Assert.AreEqual('', mLoaded.VcsSvnPath);
  Assert.AreEqual(60, mLoaded.VcsTimeoutSeconds);
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create,
    '{"vcs": {"provider": "cvs", "svn": {"path": "  s.exe "}, "timeoutSeconds": 0}}');
  mStore := mRouted;
  mLoaded.Load(mStore);
  Assert.AreEqual('auto', mLoaded.VcsProvider, 'unbekannte Art: Vorgabe');
  Assert.AreEqual('s.exe', mLoaded.VcsSvnPath, 'ohne Leerzeichen');
  Assert.AreEqual(15, mLoaded.VcsTimeoutSeconds, 'außerhalb 1 bis 300: Vorgabe');
end;
/// <summary>#1286 vcs.projects in settings.json, #1288 vcs.branch.confirm in der Registry.</summary>
procedure VcsProjectsAndBranchConfirm;
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1286: vcs.projects als JSON-Liste wie issues.projects.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('[]', mSettings.VcsProjects);
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '');
  mStore := mRouted;
  mSettings.VcsProjects := '[{"match": "C:\\Kasse", "provider": "svn", "mainBranch": "trunk"}]';
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"projects": [{"match": ');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.VcsProjects.Contains('"trunk"'), mLoaded.VcsProjects);
  // #1288: vcs.branch.confirm betrifft nur das Plugin und bleibt in der Registry; Vorgabe: Dialog zeigen.
  Assert.IsTrue(mSettings.VcsBranchConfirm);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.VcsBranchConfirm := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mRegistry.ReadInteger('VcsBranchConfirm', 1));
  Assert.IsFalse(mRouted.Text.Contains('confirm'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.VcsBranchConfirm);
end;
/// <summary>#1290: vcs.branch.svn.* in der Registry, Vorgaben und Normalisierung.</summary>
procedure VcsBranchSvnOptions(const ARegistry, AStore: IAtlasSettingsStore; ARouted: TAtlasRoutedSettingsStore);
var
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1290: vcs.branch.svn.* ebenfalls persönlich (Registry), mit Vorgaben und Normalisierung.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('{projektwurzel}/branches/{name}', mSettings.VcsBranchSvnLocation);
  Assert.AreEqual('head', mSettings.VcsBranchSvnSource);
  Assert.AreEqual('switch', mSettings.VcsBranchSvnAfter);
  Assert.AreEqual('..\{projekt}-{kennung}', mSettings.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('{kennung} Branch für {titel}', mSettings.VcsBranchSvnMessage);
  mSettings.VcsBranchSvnLocation := '^/branches/{kennung}';
  mSettings.VcsBranchSvnSource := 'workingCopy';
  mSettings.VcsBranchSvnAfter := 'checkout';
  mSettings.VcsBranchSvnCheckoutFolder := 'D:\Branches\{name}';
  mSettings.VcsBranchSvnMessage := 'Neu: {kennung}';
  mSettings.Save(AStore);
  Assert.AreEqual('checkout', ARegistry.ReadString('VcsBranchSvnAfter', ''));
  Assert.IsFalse(ARouted.Text.Contains('svn": {"location'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(AStore);
  Assert.AreEqual('^/branches/{kennung}', mLoaded.VcsBranchSvnLocation);
  Assert.AreEqual('workingCopy', mLoaded.VcsBranchSvnSource);
  Assert.AreEqual('checkout', mLoaded.VcsBranchSvnAfter);
  Assert.AreEqual('D:\Branches\{name}', mLoaded.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('Neu: {kennung}', mLoaded.VcsBranchSvnMessage);
  ARegistry.WriteString('VcsBranchSvnLocation', 'branches/{name}');
  ARegistry.WriteString('VcsBranchSvnSource', 'gestern');
  ARegistry.WriteString('VcsBranchSvnAfter', '');
  ARegistry.WriteString('VcsBranchSvnCheckoutFolder', '  ');
  ARegistry.WriteString('VcsBranchSvnMessage', '');
  mLoaded.Load(AStore);
  Assert.AreEqual('{projektwurzel}/branches/{name}', mLoaded.VcsBranchSvnLocation, 'ohne {projektwurzel} oder ^/');
  Assert.AreEqual('head', mLoaded.VcsBranchSvnSource);
  Assert.AreEqual('switch', mLoaded.VcsBranchSvnAfter);
  Assert.AreEqual('..\{projekt}-{kennung}', mLoaded.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('{kennung} Branch für {titel}', mLoaded.VcsBranchSvnMessage);
end;
/// <summary>#1291: vcs.externals.* in der Registry, Vorgaben und Normalisierung.</summary>
procedure VcsExternalsBranchOptions(const ARegistry, AStore: IAtlasSettingsStore; ARouted: TAtlasRoutedSettingsStore);
var
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1291: vcs.externals.* persönlich (Registry), mit Vorgaben und Normalisierung.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('pin', mSettings.VcsExternalsOnBranch);
  Assert.AreEqual('modified', mSettings.VcsExternalsSuggestBranch);
  Assert.AreEqual('[]', mSettings.VcsExternalsRules);
  mSettings.VcsExternalsOnBranch := 'ask';
  mSettings.VcsExternalsSuggestBranch := 'always';
  mSettings.VcsExternalsRules := '[{"source": "^/Packages/Basis", "onBranch": "keep"}]';
  mSettings.Save(AStore);
  Assert.AreEqual('ask', ARegistry.ReadString('VcsExternalsOnBranch', ''));
  Assert.IsFalse(ARouted.Text.Contains('externals'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(AStore);
  Assert.AreEqual('ask', mLoaded.VcsExternalsOnBranch);
  Assert.AreEqual('always', mLoaded.VcsExternalsSuggestBranch);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}]', mLoaded.VcsExternalsRules);
  ARegistry.WriteString('VcsExternalsOnBranch', 'branch');
  ARegistry.WriteString('VcsExternalsSuggestBranch', 'KEEP');
  ARegistry.WriteString('VcsExternalsRules', ' ');
  mLoaded.Load(AStore);
  Assert.AreEqual('pin', mLoaded.VcsExternalsOnBranch, 'branch ist keine Vorgabe für alle');
  Assert.AreEqual('modified', mLoaded.VcsExternalsSuggestBranch);
  Assert.AreEqual('[]', mLoaded.VcsExternalsRules);
end;
/// <summary>#1292: vcs.externals.show und .update in der Registry.</summary>
procedure VcsExternalsShowOptions(const ARegistry, AStore: IAtlasSettingsStore; ARouted: TAtlasRoutedSettingsStore);
var
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1292: vcs.externals.show und .update ebenfalls persönlich.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.VcsExternalsShow);
  Assert.AreEqual('with', mSettings.VcsExternalsUpdate);
  mSettings.VcsExternalsShow := False;
  mSettings.VcsExternalsUpdate := 'ask';
  mSettings.Save(AStore);
  Assert.AreEqual(0, ARegistry.ReadInteger('VcsExternalsShow', 1));
  Assert.AreEqual('ask', ARegistry.ReadString('VcsExternalsUpdate', ''));
  Assert.IsFalse(ARouted.Text.Contains('externals'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(AStore);
  Assert.IsFalse(mLoaded.VcsExternalsShow);
  Assert.AreEqual('ask', mLoaded.VcsExternalsUpdate);
  ARegistry.WriteString('VcsExternalsUpdate', 'immer');
  mLoaded.Load(AStore);
  Assert.AreEqual('with', mLoaded.VcsExternalsUpdate);
end;
procedure TAtlasIssueSettingsTests.VcsSettingsGoToGlobalFile;
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
begin
  VcsToolSettingsGoToGlobalFile;
  VcsProjectsAndBranchConfirm;
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  VcsBranchSvnOptions(mRegistry, mStore, mRouted);
  VcsExternalsBranchOptions(mRegistry, mStore, mRouted);
  VcsExternalsShowOptions(mRegistry, mStore, mRouted);
end;
/// <summary>Meine Issues (#765): Vorgaben.</summary>
procedure AssertIssuesDefaults(const ASettings: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASettings.WelcomePageIssues, 'standardmäßig aus: kein Netzzugriff');
  Assert.AreEqual('', ASettings.IssuesTracker, 'aus der .atlas');
  Assert.AreEqual('[]', ASettings.IssuesQueries, 'je Anbieter „Mir zugewiesen“ (#1262)');
  Assert.IsTrue(ASettings.IssuesQueryPicker);
  Assert.IsTrue(ASettings.IssuesProjectPicker, 'Klappliste „Tracker-Projekt“ (#1927) an');
  Assert.AreEqual('', ASettings.IssuesWelcomeProject, 'automatisch');
  Assert.IsTrue(ASettings.IssuesAllProjects, '„Alle Tracker-Projekte“ (#1928) an');
  Assert.AreEqual(5, ASettings.IssuesAllProjectsPerGroup);
  Assert.IsTrue(ASettings.IssuesSuggestPaths, '„Vorschlagen …“ (#1929) an');
  Assert.IsTrue(ASettings.IssuesCreate, '„Issue anlegen …“ an (#1268)');
  Assert.IsTrue(ASettings.IssuesCreateIncludeCode, 'Codeausschnitt vorgeschlagen (#1268)');
  Assert.AreEqual(0, ASettings.CreateIssueKey, 'frei belegbar, ohne Vorgabe');
  Assert.AreEqual('branch', ASettings.IssuesStart);
  Assert.AreEqual('', ASettings.IssuesBranchPattern, 'je Versionsverwaltung');
  Assert.AreEqual('', ASettings.IssuesBranchBase);
  Assert.AreEqual('{kennung} ', ASettings.IssuesCommitPattern);
  Assert.IsTrue(ASettings.TrackerLogin);
  Assert.IsTrue(ASettings.IssuesPreview, 'Vorschau (#1264) an');
  Assert.IsTrue(ASettings.IssuesPreviewComments);
  Assert.IsTrue(ASettings.IssuesCodeLinks);
  Assert.IsTrue(ASettings.IssuesBlameLinks);
  Assert.AreEqual(200, ASettings.IssuesBlameMaxRevisions);
  Assert.IsTrue(ASettings.IssuesPreviewChecklists);
  Assert.IsTrue(ASettings.IssuesChecklistStatus);
  Assert.IsTrue(ASettings.IssuesPreviewLinks, 'Verknüpfungen als Baum (#1279) an');
  Assert.IsTrue(ASettings.IssuesWarnBlocked, 'Warnung beim Beginnen (#1279) an');
  Assert.IsTrue(ASettings.IssuesBoard, 'Board (#1272) an');
  Assert.IsTrue(ASettings.IssuesBoardConfirmMove, 'Rückfrage beim Ziehen an');
  Assert.IsTrue(ASettings.IssuesBoardOnlyMine, 'Board öffnet mit „Nur meine“');
  Assert.IsTrue(ASettings.IssuesIdeColors, 'Farben des IDE-Themas');
  Assert.IsTrue(ASettings.WelcomePageSprint, 'Sprint-Kachel (#1277) an');
  Assert.IsTrue(ASettings.IssuesSprintBurndown, 'Burndown an');
  Assert.IsTrue(ASettings.IssuesSprintCompare, 'Vergleich mit dem Vorsprint an');
  Assert.IsTrue(ASettings.IssuesPaletteSearch, 'Palettensuche (#1270) an');
  Assert.IsTrue(ASettings.IssuesPreviewDevelopment, 'Reiter „Entwicklung“ (#1269)');
  Assert.IsFalse(ASettings.IssuesNotify, 'Meldungen (#1271) aus');
  Assert.AreEqual(10, ASettings.IssuesNotifyIntervalMinutes);
  Assert.AreEqual('assignedOrCreated', ASettings.IssuesNotifyScope);
  Assert.IsTrue(ASettings.IssuesAttach, 'Anhängen (#1276) an');
  Assert.AreEqual('', ASettings.IssuesAttachLogFiles);
  Assert.AreEqual(1920, ASettings.IssuesAttachMaxImageWidth);
  Assert.IsTrue(ASettings.IssuesAttachRaiseProgram, 'Programm nach vorn holen an');
  // Die Einstellungen kennen den Bereich nicht: dieselben Werte wie dort.
  Assert.AreEqual(TAtlasTrackerNaming.cCommitPattern, ASettings.IssuesCommitPattern);
  Assert.AreEqual(TAtlasMyIssues.StartName(TAtlasIssueStart.Branch), TAtlasPluginSettings.cIssuesStartBranch);
  Assert.AreEqual(TAtlasMyIssues.StartName(TAtlasIssueStart.Remember),
    TAtlasPluginSettings.cIssuesStartRemember);
end;
/// <summary>Meine Issues (#765, #1271): Normalisieren.</summary>
procedure NormalizeIssuesOptions(var ASettings: TAtlasPluginSettings);
begin
  // Normalisieren.
  ASettings.IssuesTracker := ' YouTrack ';
  ASettings.IssuesQueries := '  ';
  ASettings.IssuesStart := 'REMEMBER';
  ASettings.IssuesBranchPattern := ' bugfix/{kennung} ';
  ASettings.IssuesBranchBase := ' develop ';
  ASettings.IssuesCommitPattern := '[{kennung}] ';
  ASettings.Normalize;
  Assert.AreEqual('youtrack', ASettings.IssuesTracker);
  Assert.AreEqual('[]', ASettings.IssuesQueries, 'leer = keine');
  Assert.AreEqual('remember', ASettings.IssuesStart);
  Assert.AreEqual('bugfix/{kennung}', ASettings.IssuesBranchPattern);
  Assert.AreEqual('develop', ASettings.IssuesBranchBase);
  Assert.AreEqual('[{kennung}] ', ASettings.IssuesCommitPattern, 'Leerzeichen am Ende bleibt');
  ASettings.IssuesTracker := 'jira';
  ASettings.IssuesStart := 'egal';
  ASettings.IssuesCommitPattern := '';
  ASettings.IssuesBlameMaxRevisions := 0;
  ASettings.Normalize;
  Assert.AreEqual(1, ASettings.IssuesBlameMaxRevisions, 'unter 1: 1');
  ASettings.IssuesBlameMaxRevisions := 100000;
  ASettings.Normalize;
  Assert.AreEqual(5000, ASettings.IssuesBlameMaxRevisions, 'über 5000: 5000');
  Assert.AreEqual('', ASettings.IssuesTracker);
  Assert.AreEqual('branch', ASettings.IssuesStart);
  Assert.AreEqual('', ASettings.IssuesCommitPattern, 'leer = aus');
  // #1271: Abstand begrenzt, unbekannter Umfang fällt auf den Standard.
  ASettings.IssuesNotifyIntervalMinutes := 1;
  ASettings.IssuesNotifyScope := ' WATCHED ';
  ASettings.Normalize;
  Assert.AreEqual(2, ASettings.IssuesNotifyIntervalMinutes, 'mindestens 2 Minuten');
  Assert.AreEqual('watched', ASettings.IssuesNotifyScope);
  ASettings.IssuesNotifyIntervalMinutes := 100000;
  ASettings.IssuesNotifyScope := 'alles';
  ASettings.Normalize;
  Assert.AreEqual(1440, ASettings.IssuesNotifyIntervalMinutes, 'höchstens ein Tag');
  Assert.AreEqual('assignedOrCreated', ASettings.IssuesNotifyScope);
  // #1927, #1928: Wahl getrimmt, Zeilen je Gruppe 1–20.
  ASettings.IssuesWelcomeProject := ' KASSE@Firma ';
  ASettings.IssuesAllProjectsPerGroup := 0;
  ASettings.Normalize;
  Assert.AreEqual('KASSE@Firma', ASettings.IssuesWelcomeProject);
  Assert.AreEqual(1, ASettings.IssuesAllProjectsPerGroup, 'mindestens 1');
  ASettings.IssuesAllProjectsPerGroup := 99;
  ASettings.Normalize;
  Assert.AreEqual(20, ASettings.IssuesAllProjectsPerGroup, 'höchstens 20');
end;
/// <summary>Meine Issues: alle Werte von der Vorgabe abweichend setzen.</summary>
procedure SetIssuesOptions(var ASettings: TAtlasPluginSettings);
begin
  // Speichern und Laden.
  ASettings.WelcomePageIssues := True;
  ASettings.IssuesTracker := 'github';
  ASettings.IssuesQueries := '[{"name": "Bugs", "query": "label:bug"}]';
  ASettings.IssuesQueryPicker := False;
  ASettings.IssuesProjectPicker := False;
  ASettings.IssuesWelcomeProject := '*';
  ASettings.IssuesAllProjects := False;
  ASettings.IssuesAllProjectsPerGroup := 8;
  ASettings.IssuesSuggestPaths := False;
  ASettings.IssuesCreate := False;
  ASettings.IssuesCreateIncludeCode := False;
  ASettings.CreateIssueKey := $4049;
  ASettings.IssuesStart := 'remember';
  ASettings.IssuesBranchPattern := 'issue/{nummer}';
  ASettings.IssuesBranchBase := 'trunk';
  ASettings.IssuesCommitPattern := '{kennung}: ';
  ASettings.TrackerLogin := False;
  ASettings.IssuesPreview := False;
  ASettings.IssuesPreviewComments := False;
  ASettings.IssuesCodeLinks := False;
  ASettings.IssuesBlameLinks := False;
  ASettings.IssuesBlameMaxRevisions := 75;
  ASettings.IssuesPreviewChecklists := False;
  ASettings.IssuesChecklistStatus := False;
  ASettings.IssuesPreviewLinks := False;
  ASettings.IssuesWarnBlocked := False;
  ASettings.IssuesBoard := False;
  ASettings.IssuesBoardConfirmMove := False;
  ASettings.IssuesBoardOnlyMine := False;
  ASettings.IssuesIdeColors := False;
  ASettings.WelcomePageSprint := False;
  ASettings.IssuesSprintBurndown := False;
  ASettings.IssuesSprintCompare := False;
  ASettings.IssuesPaletteSearch := False;
  ASettings.IssuesPreviewDevelopment := False;
  ASettings.IssuesNotify := True;
  ASettings.IssuesNotifyIntervalMinutes := 5;
  ASettings.IssuesNotifyScope := 'assigned';
  ASettings.IssuesAttach := False;
  ASettings.IssuesAttachLogFiles := '$(ProjectDir)\logs\*.log;C:\Temp\app.log';
  ASettings.IssuesAttachMaxImageWidth := 1280;
  ASettings.IssuesAttachRaiseProgram := False;
end;
/// <summary>Meine Issues: gespeicherte Werte gelesen.</summary>
procedure AssertIssuesLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsTrue(ALoaded.WelcomePageIssues);
  Assert.AreEqual('github', ALoaded.IssuesTracker);
  Assert.AreEqual('[{"name": "Bugs", "query": "label:bug"}]', ALoaded.IssuesQueries);
  Assert.IsFalse(ALoaded.IssuesQueryPicker);
  Assert.IsFalse(ALoaded.IssuesProjectPicker);
  Assert.AreEqual('*', ALoaded.IssuesWelcomeProject);
  Assert.IsFalse(ALoaded.IssuesAllProjects);
  Assert.AreEqual(8, ALoaded.IssuesAllProjectsPerGroup);
  Assert.IsFalse(ALoaded.IssuesSuggestPaths);
  Assert.IsFalse(ALoaded.IssuesCreate);
  Assert.IsFalse(ALoaded.IssuesCreateIncludeCode);
  Assert.AreEqual($4049, ALoaded.CreateIssueKey, 'Strg+I');
  Assert.AreEqual('remember', ALoaded.IssuesStart);
  Assert.AreEqual('issue/{nummer}', ALoaded.IssuesBranchPattern);
  Assert.AreEqual('trunk', ALoaded.IssuesBranchBase);
  Assert.AreEqual('{kennung}: ', ALoaded.IssuesCommitPattern);
  Assert.IsFalse(ALoaded.TrackerLogin);
  Assert.IsFalse(ALoaded.IssuesPreview);
  Assert.IsFalse(ALoaded.IssuesPreviewComments);
  Assert.IsFalse(ALoaded.IssuesCodeLinks);
  Assert.IsFalse(ALoaded.IssuesBlameLinks);
  Assert.AreEqual(75, ALoaded.IssuesBlameMaxRevisions);
  Assert.IsFalse(ALoaded.IssuesPaletteSearch);
  Assert.IsFalse(ALoaded.IssuesPreviewChecklists);
  Assert.IsFalse(ALoaded.IssuesChecklistStatus);
  Assert.IsFalse(ALoaded.IssuesPreviewLinks);
  Assert.IsFalse(ALoaded.IssuesWarnBlocked);
  Assert.IsFalse(ALoaded.IssuesBoard);
  Assert.IsFalse(ALoaded.IssuesBoardConfirmMove);
  Assert.IsFalse(ALoaded.IssuesBoardOnlyMine);
  Assert.IsFalse(ALoaded.IssuesIdeColors);
  Assert.IsFalse(ALoaded.WelcomePageSprint);
  Assert.IsFalse(ALoaded.IssuesSprintBurndown);
  Assert.IsFalse(ALoaded.IssuesSprintCompare);
  Assert.IsFalse(ALoaded.IssuesPreviewDevelopment);
  Assert.IsTrue(ALoaded.IssuesNotify);
  Assert.AreEqual(5, ALoaded.IssuesNotifyIntervalMinutes);
  Assert.AreEqual('assigned', ALoaded.IssuesNotifyScope);
  Assert.IsFalse(ALoaded.IssuesAttach);
  Assert.AreEqual('$(ProjectDir)\logs\*.log;C:\Temp\app.log', ALoaded.IssuesAttachLogFiles);
  Assert.AreEqual(1280, ALoaded.IssuesAttachMaxImageWidth);
  Assert.IsFalse(ALoaded.IssuesAttachRaiseProgram);
end;
procedure TAtlasIssueSettingsTests.WelcomeIssuesOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  AssertIssuesDefaults(Settings);
  NormalizeIssuesOptions(Settings);
  SetIssuesOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  AssertIssuesLoaded(Loaded);
  // Bildbreite außerhalb 320–7680 wird begrenzt.
  Settings.IssuesAttachMaxImageWidth := 50;
  Settings.Normalize;
  Assert.AreEqual(320, Settings.IssuesAttachMaxImageWidth);
  Settings.IssuesAttachMaxImageWidth := 100000;
  Settings.Normalize;
  Assert.AreEqual(7680, Settings.IssuesAttachMaxImageWidth);
end;
procedure TAtlasIssueSettingsTests.IssuesSyncOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.IssuesSyncState, 'an: geschrieben wird trotzdem nur nach Senden bzw. Beginnen');
  Assert.AreEqual('State', mSettings.IssuesStateField);
  Assert.AreEqual('Assignee', mSettings.IssuesAssigneeField);
  Assert.AreEqual('', mSettings.IssuesStartState, 'Zustand beim Beginnen nicht ändern');
  Assert.IsFalse(mSettings.IssuesAssignOnStart);
  Assert.AreEqual('', mSettings.IssuesStartComment);
  Assert.AreEqual('', mSettings.IssuesEndStates);
  Assert.AreEqual('', mSettings.IssuesReviewStates);
  Assert.IsTrue(mSettings.IssuesReopened, '#2127: Vorgabe an');
  Assert.IsTrue(mSettings.IssuesReviewBuild, '#2126: Vorgabe an');
  Assert.AreEqual('Geprüft: {build}, {tests}.', mSettings.IssuesReviewComment);
  Assert.AreEqual('Erledigt in {branch}.\n{commits}', mSettings.IssuesEndComment);
  Assert.AreEqual('', mSettings.IssuesEndFields, 'ab Werk keine Felder beim Beenden');
  Assert.IsTrue(mSettings.IssuesEndTime, 'erfasste Zeit beim Beenden anbieten');
  // Normalisieren: Felder ohne Leerraum außen, leer = Vorgabe; Vorlagen einzeilig mit \n.
  mSettings.IssuesStateField := '  Status ';
  mSettings.IssuesAssigneeField := '';
  mSettings.IssuesStartState := ' In Arbeit ';
  mSettings.IssuesStartComment := 'Beginne {kennung}'#13#10'in {branch}';
  mSettings.IssuesEndStates := ' Zur Prüfung, Erledigt ';
  mSettings.IssuesReviewStates := ' Zur Prüfung ';
  mSettings.IssuesEndComment := StringOfChar('x', TAtlasPluginSettings.cMaxIssuesTemplate + 10);
  mSettings.IssuesReviewComment := 'Geprüft'#13#10'{build}';
  mSettings.Normalize;
  Assert.AreEqual('Geprüft\n{build}', mSettings.IssuesReviewComment, 'einzeilig mit \n');
  mSettings.IssuesEndFields := ' Behoben in Version, Ursache ';
  mSettings.Normalize;
  Assert.AreEqual('Behoben in Version, Ursache', mSettings.IssuesEndFields);
  Assert.AreEqual('Status', mSettings.IssuesStateField);
  Assert.AreEqual('Assignee', mSettings.IssuesAssigneeField, 'leer = Vorgabe');
  Assert.AreEqual('In Arbeit', mSettings.IssuesStartState);
  Assert.AreEqual('Beginne {kennung}\nin {branch}', mSettings.IssuesStartComment);
  Assert.AreEqual('Zur Prüfung, Erledigt', mSettings.IssuesEndStates);
  Assert.AreEqual('Zur Prüfung', mSettings.IssuesReviewStates);
  Assert.AreEqual(TAtlasPluginSettings.cMaxIssuesTemplate, Integer(Length(mSettings.IssuesEndComment)));
  // Speichern und Laden.
  mSettings.IssuesSyncState := False;
  mSettings.IssuesAssignOnStart := True;
  mSettings.IssuesEndComment := 'Fertig: {pr}';
  mSettings.IssuesEndTime := False;
  mSettings.IssuesReopened := False;
  mSettings.IssuesReviewBuild := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.IssuesSyncState);
  Assert.AreEqual('Status', mLoaded.IssuesStateField);
  Assert.AreEqual('Assignee', mLoaded.IssuesAssigneeField);
  Assert.AreEqual('In Arbeit', mLoaded.IssuesStartState);
  Assert.IsTrue(mLoaded.IssuesAssignOnStart);
  Assert.AreEqual('Beginne {kennung}\nin {branch}', mLoaded.IssuesStartComment);
  Assert.AreEqual('Zur Prüfung, Erledigt', mLoaded.IssuesEndStates);
  Assert.AreEqual('Zur Prüfung', mLoaded.IssuesReviewStates);
  Assert.IsFalse(mLoaded.IssuesReopened);
  Assert.IsFalse(mLoaded.IssuesReviewBuild);
  Assert.AreEqual('Geprüft\n{build}', mLoaded.IssuesReviewComment);
  Assert.AreEqual('Fertig: {pr}', mLoaded.IssuesEndComment);
  Assert.AreEqual('Behoben in Version, Ursache', mLoaded.IssuesEndFields);
  Assert.IsFalse(mLoaded.IssuesEndTime);
end;
procedure TAtlasIssueSettingsTests.IssuesTimeOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.IssuesTimeTracking, 'ab Werk aus');
  Assert.AreEqual(10, mSettings.IssuesIdleMinutes);
  Assert.AreEqual(5, mSettings.IssuesTimeRounding);
  mSettings.IssuesIdleMinutes := 0;
  mSettings.IssuesTimeRounding := 500;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinIssuesIdleMinutes, mSettings.IssuesIdleMinutes);
  Assert.AreEqual(TAtlasPluginSettings.cMaxIssuesTimeRounding, mSettings.IssuesTimeRounding);
  mSettings.IssuesTimeTracking := True;
  mSettings.IssuesIdleMinutes := 15;
  mSettings.IssuesTimeRounding := 15;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesTimeTracking);
  Assert.AreEqual(15, mLoaded.IssuesIdleMinutes);
  Assert.AreEqual(15, mLoaded.IssuesTimeRounding);
end;
procedure TAtlasIssueSettingsTests.IssuesCommentOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.IssuesCommentEditor, 'Kommentar-Editor ist vorgegeben an');
  Assert.AreEqual(TAtlasPluginSettings.cDefaultIssuesCommentSnippets, mSettings.IssuesCommentSnippets, 'zwei Vorgabe-Bausteine');
  // Normalisieren: leer = keine Bausteine, nicht die Vorgabe.
  mSettings.IssuesCommentSnippets := '   ';
  mSettings.Normalize;
  Assert.AreEqual('[]', mSettings.IssuesCommentSnippets);
  // Speichern und Laden.
  mSettings.IssuesCommentEditor := False;
  mSettings.IssuesCommentSnippets := '[{"name":"Danke","text":"Danke!"}]';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.IssuesCommentEditor);
  Assert.AreEqual('[{"name":"Danke","text":"Danke!"}]', mLoaded.IssuesCommentSnippets);
end;
procedure TAtlasIssueSettingsTests.WelcomeQuickActionOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WelcomePageQuickActions, 'standardmäßig an');
  Assert.AreEqual('build,tests,run,pull,folder,console,tasks', Settings.WelcomePageQuickActionsItems);
  Assert.AreEqual('wt.exe', Settings.WelcomePageQuickActionsConsole);
  Assert.AreEqual($4042, Settings.WelcomePageQuickActionsBuildKey, 'Strg+B');
  Assert.AreEqual($4054, Settings.WelcomePageQuickActionsTestKey, 'Strg+T');
  // Die Einstellungen kennen die Willkommensseite nicht: dieselben Vorgaben und Namen wie dort.
  Assert.AreEqual(TAtlasWelcomeQuickActions.cDefaultItems, Settings.WelcomePageQuickActionsItems);
  Assert.AreEqual(TAtlasWelcomeQuickActions.cDefaultConsole, Settings.WelcomePageQuickActionsConsole);
  Assert.AreEqual(TAtlasWelcomeQuickActions.cDefaultBuildKey, Settings.WelcomePageQuickActionsBuildKey);
  Assert.AreEqual(TAtlasWelcomeQuickActions.cDefaultTestKey, Settings.WelcomePageQuickActionsTestKey);
  Settings.WelcomePageQuickActionsItems := 'folder,unbekannt;RUN tests console pull build';
  Settings.Normalize;
  Assert.AreEqual(TAtlasWelcomeQuickActions.NormalizedItems('folder,unbekannt;RUN tests console pull build'),
    Settings.WelcomePageQuickActionsItems);
  // Normalisieren: bekannte Namen in fester Reihenfolge, leeres Programm = wt.exe, Tasten als Word.
  Settings.WelcomePageQuickActionsItems := ' Console; BUILD pull, unbekannt, build ';
  Settings.WelcomePageQuickActionsConsole := '   ';
  Settings.WelcomePageQuickActionsBuildKey := -5;
  Settings.WelcomePageQuickActionsTestKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual('build,pull,console', Settings.WelcomePageQuickActionsItems);
  Assert.AreEqual(TAtlasWelcomeQuickActions.cDefaultConsole, Settings.WelcomePageQuickActionsConsole);
  Assert.AreEqual(0, Settings.WelcomePageQuickActionsBuildKey);
  Assert.AreEqual($FFFF, Settings.WelcomePageQuickActionsTestKey);
  // Leere Liste bleibt leer (kein Knopf).
  Settings.WelcomePageQuickActionsItems := '';
  Settings.Normalize;
  Assert.AreEqual('', Settings.WelcomePageQuickActionsItems);
  // Speichern und Laden.
  Settings.WelcomePageQuickActions := False;
  Settings.WelcomePageQuickActionsItems := 'tests,folder';
  Settings.WelcomePageQuickActionsConsole := 'pwsh.exe';
  Settings.WelcomePageQuickActionsBuildKey := $C042;
  Settings.WelcomePageQuickActionsTestKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.WelcomePageQuickActions);
  Assert.AreEqual('tests,folder', Loaded.WelcomePageQuickActionsItems);
  Assert.AreEqual('pwsh.exe', Loaded.WelcomePageQuickActionsConsole);
  Assert.AreEqual($C042, Loaded.WelcomePageQuickActionsBuildKey);
  Assert.AreEqual(0, Loaded.WelcomePageQuickActionsTestKey);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueSettingsTests);

end.
