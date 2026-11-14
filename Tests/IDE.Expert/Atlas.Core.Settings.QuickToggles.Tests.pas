unit Atlas.Core.Settings.QuickToggles.Tests;

// Schnellschalter (#604): Liste aus dem Katalog (x-quickToggle, Seiten,
// Projektpfad aus atlas.schema.json), Werte über den Namen der Einstellung,
// Sitzungswerte und „Alles aus“ ohne Änderung der gespeicherten Werte,
// Projektmarkierung und Ziel des Umschaltens.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasQuickTogglesTests = class
  public
    [Test]
    procedure BuildsListFromCatalog;
    [Test]
    procedure RealCatalogsContainAcceptanceSwitches;
    [Test]
    procedure FlagsByName;
    [Test]
    procedure SessionAndAllOffKeepStoredValues;
    [Test]
    procedure ItemsShowProjectAndSession;
    [Test]
    procedure ToggleTargets;
    /// <summary>x-feature nennt eine Sicherung aus TAtlasFeature, sonst findet der Vorschlag nach einem Absturz
    /// (#722) den Schalter nie.</summary>
    [Test]
    procedure FeaturesNameGuardFeatures;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.TypInfo,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.QuickToggles;

const
  cCatalog =
    '{"properties":{' +
    '"PairColors":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Klammerfarben","x-captionEn":"Bracket colors"},' +
    '"HoverTooltip":{"type":"boolean","x-page":"Hints","x-quickToggle":true,"x-caption":"Hover"},' +
    '"FixCase":{"type":"boolean","x-page":"Editor","x-caption":"ohne Schnellschalter"},' +
    '"VisibleRows":{"type":"integer","x-page":"Editor","x-quickToggle":true},' +
    '"PairGuides":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"description":"Blocklinien","x-description-en":"Block guides"}' +
    '}}';
  cProject =
    '{"properties":{' +
    '"hints":{"type":"object","x-page":"Hints","properties":{' +
      '"slash":{"type":"boolean","x-quickToggle":true,"x-plugin":"SlashCommands","x-caption":"Schnellbefehle"},' +
      '"xmlDocMaxLines":{"type":"integer"}}},' +
    '"highlight":{"type":"object","x-page":"Editor","properties":{' +
      '"blockPairs":{"type":"boolean","x-quickToggle":true}}},' +
    '"colors":{"type":"object","x-page":"Editor","properties":{' +
      '"pairs":{"type":"boolean","x-quickToggle":true,"x-plugin":"PairColors"}}}' +
    '}}';

procedure TAtlasQuickTogglesTests.BuildsListFromCatalog;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mGroups: TArray<TAtlasQuickToggleGroup>;
begin
  mToggles := TAtlasQuickToggles.Build(cCatalog, cProject);
  // Nur boolesche Einstellungen mit x-quickToggle; ohne x-plugin kein globaler Wert (blockPairs).
  Assert.AreEqual(4, Integer(Length(mToggles)));
  // Nach Seiten gruppiert, Seiten in der Reihenfolge ihres ersten Schalters.
  Assert.AreEqual('PairColors', mToggles[0].Key);
  Assert.AreEqual('PairGuides', mToggles[1].Key);
  Assert.AreEqual('HoverTooltip', mToggles[2].Key);
  Assert.AreEqual('SlashCommands', mToggles[3].Key);
  Assert.AreEqual('Klammerfarben', mToggles[0].Caption);
  Assert.AreEqual('Blocklinien', mToggles[1].Caption, 'ohne x-caption die Beschreibung');
  Assert.IsTrue(mToggles[0].Drawing);
  Assert.IsFalse(mToggles[2].Drawing);
  // Eintrag aus atlas.schema.json: Pfad im Projekt; schon im Plugin-Katalog: nur der Pfad kommt dazu.
  Assert.AreEqual('hints.slash', mToggles[3].ProjectPath);
  Assert.AreEqual('Hints', mToggles[3].Page);
  Assert.AreEqual('colors.pairs', mToggles[0].ProjectPath);
  Assert.AreEqual('', mToggles[2].ProjectPath);
  mGroups := TAtlasQuickToggles.Groups(mToggles);
  Assert.AreEqual(2, Integer(Length(mGroups)));
  Assert.AreEqual('Editor', mGroups[0].Page);
  Assert.AreEqual(2, Integer(Length(mGroups[0].Toggles)));
  Assert.AreEqual('Hints', mGroups[1].Page);
  // Englische Beschriftung, wo es eine gibt.
  mToggles := TAtlasQuickToggles.Build(cCatalog, '', True);
  Assert.AreEqual('Bracket colors', mToggles[0].Caption);
  Assert.AreEqual('Hover', mToggles[2].Caption);
  // Ohne x-captionEn die englische Beschreibung (#1458).
  Assert.AreEqual('Block guides', mToggles[1].Caption);
  Assert.AreEqual(0, Integer(Length(TAtlasQuickToggles.Build('kein JSON', ''))));
end;

/// <summary>Projektdatei .atlas (#486) und folgende Schalter.</summary>
procedure AssertTeamFileAndGenerateToggles(const AToggles: TArray<TAtlasQuickToggle>);
var
  mToggle: TAtlasQuickToggle;
begin
  // Projektdatei .atlas (#486): eigener Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'TeamFile', mToggle));
  Assert.AreEqual('Allgemein', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Settings', mToggle.Feature);
  // Builds für Claude Code (#261): Schalter auf der Seite Compiler, keine Zeichnung.
  // Tests ausführen (#69): Code Lens zeichnet im Editor, Befehle und Lauf nach dem Build nicht.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'CodeLensTests', mToggle));
  Assert.AreEqual('Editor', mToggle.Page);
  Assert.IsTrue(mToggle.Drawing);
  Assert.AreEqual('Build', mToggle.Feature);
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'TestRun', mToggle));
  Assert.AreEqual('Compiler', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'TestsAfterBuild', mToggle));
  Assert.IsFalse(TAtlasQuickToggles.Find(AToggles, 'BuildZeroHints', mToggle), 'ohne x-quickToggle');
  // Startprofile (#575): Befehl und Statusfeld je ein Schalter auf der Seite Compiler, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'StartProfiles', mToggle));
  Assert.AreEqual('Compiler', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Build', mToggle.Feature);
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'StartProfilesStatusField', mToggle));
  Assert.AreEqual('Compiler', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  // Test debuggen (#585): eigener Schalter für Befehl, Kontextmenü und Marke auf der Seite Debuggen; der
  // Haltepunkt am Anfang ist kein Schnellschalter.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'TestDebug', mToggle));
  Assert.AreEqual('Debuggen', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Build', mToggle.Feature);
  Assert.IsFalse(TAtlasQuickToggles.Find(AToggles, 'TestBreakAtStart', mToggle), 'ohne x-quickToggle');
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'McpBuild', mToggle));
  // Seit #1906 auf der Seite des Moduls KI-Assistenten.
  Assert.AreEqual('KI-Assistenten', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Build', mToggle.Feature);
  // Beim Öffnen einmal bauen (build.onOpen): Schalter auf der Seite Compiler, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'BuildOnOpen', mToggle));
  Assert.AreEqual('Compiler', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Build', mToggle.Feature);
  // Befehl (#68): Schalter auf der Seite Editor; keine Zeichnung, „Alles aus“ lässt ihn stehen.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'TodoList', mToggle));
  Assert.AreEqual('Editor', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Palette', mToggle.Feature);
  // Befehl (#97): eigener Schalter je Palettenbefehl, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'BaselineUpdate', mToggle));
  Assert.AreEqual('Editor', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Palette', mToggle.Feature);
  // Release-Build-Wächter samt Befehl (#533): eigener Schalter auf der Seite Release-Build, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'ReleaseGuard', mToggle));
  Assert.AreEqual('Release-Build', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Build', mToggle.Feature);
end;

/// <summary>Einrichtungskarte (#759), Atlas.CiLogin (#763) und folgende Schalter.</summary>
procedure AssertSetupAndLoginToggles(const AToggles: TArray<TAtlasQuickToggle>);
var
  mToggle: TAtlasQuickToggle;
  mValue: Boolean;
begin
  // Einrichtungskarte und Befehl Atlas.ProjectSetup (#759): eigener Schalter auf der Seite Willkommensseite.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'WelcomePageProjectSetup', mToggle));
  Assert.AreEqual('Willkommensseite', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('WelcomePage', mToggle.Feature);
  // Befehl Atlas.CiLogin (#763): eigener Schalter auf der Seite Willkommensseite, Vorgabe an.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'CiLogin', mToggle));
  Assert.AreEqual('Willkommensseite', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('WelcomePage', mToggle.Feature);
  Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, 'CiLogin', mValue));
  Assert.IsTrue(mValue);
  // Schnellaktionen der Willkommensseite (#764): eigener Schalter, Vorgabe an.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'WelcomePageQuickActions', mToggle));
  Assert.AreEqual('Willkommensseite', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('WelcomePage', mToggle.Feature);
  Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, 'WelcomePageQuickActions', mValue));
  Assert.IsTrue(mValue);
  // Issue-Tracker (#765): Bereich standardmäßig aus, Befehl für den Zugang an.
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'WelcomePageIssues', mToggle));
  Assert.AreEqual('Willkommensseite', mToggle.Page);
  Assert.AreEqual('WelcomePage', mToggle.Feature);
  Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, 'WelcomePageIssues', mValue));
  Assert.IsFalse(mValue);
  Assert.IsTrue(TAtlasQuickToggles.Find(AToggles, 'TrackerLogin', mToggle));
  // Seit #1280 auf der eigenen Seite Issue-Tracker (issues.login).
  Assert.AreEqual('Issue-Tracker', mToggle.Page);
  Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, 'TrackerLogin', mValue));
  Assert.IsTrue(mValue);
  // Jeder Schalter ist eine Einstellung des Plugins.
  for mToggle in AToggles do
  begin
    Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, mToggle.Key, mValue), mToggle.Key);
    Assert.AreNotEqual('', mToggle.Caption, mToggle.Key);
    Assert.AreNotEqual('', mToggle.Page, mToggle.Key);
  end;
end;

procedure TAtlasQuickTogglesTests.RealCatalogsContainAcceptanceSwitches;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mToggle: TAtlasQuickToggle;
begin
  mToggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, AtlasSchemaJson);
  // Abnahme: mindestens Klammerfarben (#514) und Blocklinien.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'PairColors', mToggle));
  Assert.IsTrue(mToggle.Drawing);
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'PairGuides', mToggle));
  Assert.IsTrue(mToggle.Drawing);
  // hints ist global (x-scope, #227): Ein Schalter schreibt nur die Plugin-Einstellung, nie atlas.json.
  // hints.xmlDocExpand (#770) ist eine Auswahl und hat keinen Schalter.
  Assert.IsFalse(TAtlasQuickToggles.Find(mToggles, 'XmlDocExpand', mToggle));
  Assert.IsFalse(TAtlasQuickToggles.Find(mToggles, 'XmlDocFull', mToggle));
  for mToggle in mToggles do
  begin
    Assert.IsFalse(mToggle.ProjectPath.StartsWith('hints.') or mToggle.ProjectPath.StartsWith('index.'), mToggle.Key);
  end;
  Assert.IsFalse(TAtlasQuickToggles.Find(mToggles, 'StatusFieldSummary', mToggle), 'ohne x-quickToggle');
  // Diagnosemodus (#479): Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'DiagnosticMode', mToggle));
  Assert.AreEqual('Allgemein', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  // Tastenkürzel-Tipps (#600): Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'ShortcutTips', mToggle));
  Assert.AreEqual('Allgemein', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  // Benachrichtigungszentrale (#601): Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'Notifications', mToggle));
  Assert.AreEqual('Allgemein', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Notifications', mToggle.Feature);
  // Persönliche Notizen (#545): Schalter auf der Seite Editor, Symbol in der Rinne.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'Notes', mToggle));
  Assert.AreEqual('Editor', mToggle.Page);
  Assert.IsTrue(mToggle.Drawing);
  Assert.AreEqual('Notes', mToggle.Feature);
  // Benannte Lesezeichen (#622): Schalter auf der Seite Editor, Symbol in der Rinne.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'BookmarksNamed', mToggle));
  Assert.AreEqual('Editor', mToggle.Page);
  Assert.IsTrue(mToggle.Drawing);
  Assert.AreEqual('Bookmarks', mToggle.Feature);
  // Erzeugen-Menü (#719): Befehl, keine Zeichnung; „Alles aus“ lässt ihn stehen.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'GenerateMenu', mToggle));
  Assert.AreEqual('Befehle', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Generate', mToggle.Feature);
  // Code Lens mit Code-Metriken (#66): Zeichnung im Editor, „Alles aus“ schaltet sie ab.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'CodeLensMetrics', mToggle));
  Assert.AreEqual('Editor', mToggle.Page);
  Assert.IsTrue(mToggle.Drawing);
  Assert.AreEqual('CodeLens', mToggle.Feature);
  // Befehl (#66): Schalter auf der Seite Editor; keine Zeichnung, „Alles aus“ lässt ihn stehen.
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'MetricsReport', mToggle));
  Assert.AreEqual('Editor', mToggle.Page);
  Assert.IsFalse(mToggle.Drawing);
  Assert.AreEqual('Palette', mToggle.Feature);
  AssertTeamFileAndGenerateToggles(mToggles);
  AssertSetupAndLoginToggles(mToggles);
end;

procedure TAtlasQuickTogglesTests.FlagsByName;
var
  mSettings: TAtlasPluginSettings;
  mValue: Boolean;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(TAtlasQuickToggles.SetFlag(mSettings, 'PairColors', False));
  Assert.IsFalse(mSettings.PairColors);
  Assert.IsTrue(mSettings.PairGuides, 'andere Werte bleiben');
  Assert.AreEqual(TAtlasPluginSettings.Defaults.VisibleRows, mSettings.VisibleRows);
  Assert.IsTrue(TAtlasQuickToggles.GetFlag(mSettings, 'PairColors', mValue));
  Assert.IsFalse(mValue);
  Assert.IsTrue(TAtlasQuickToggles.SetFlag(mSettings, 'Preview', True));
  Assert.IsTrue(mSettings.Preview);
  Assert.IsFalse(TAtlasQuickToggles.SetFlag(mSettings, 'GibtEsNicht', True));
  Assert.IsFalse(TAtlasQuickToggles.GetFlag(mSettings, 'GibtEsNicht', mValue));
end;

procedure TAtlasQuickTogglesTests.SessionAndAllOffKeepStoredValues;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mStored, mEffective: TAtlasPluginSettings;
  mSession: TAtlasToggleSession;
  mValue: Boolean;
begin
  mToggles := TAtlasQuickToggles.Build(cCatalog, cProject);
  mStored := TAtlasPluginSettings.Defaults;
  mSession := Default(TAtlasToggleSession);
  mSession.Put('HoverTooltip', False);
  mSession.Put('hovertooltip', False);
  Assert.AreEqual(1, Integer(Length(mSession.Overrides)), 'ein Wert je Name');
  mEffective := mSession.Apply(mStored, mToggles);
  Assert.IsFalse(mEffective.HoverTooltip);
  Assert.IsTrue(mEffective.PairColors);
  // Alles aus: nur Zeichnungen, gespeicherte Werte unverändert.
  mSession.AllOff := True;
  mEffective := mSession.Apply(mStored, mToggles);
  Assert.IsFalse(mEffective.PairColors);
  Assert.IsFalse(mEffective.PairGuides);
  Assert.AreEqual<Boolean>(mStored.Preview, mEffective.Preview);
  Assert.IsTrue(mEffective.GenerateMenu, 'Befehl (#719) ist keine Zeichnung');
  Assert.IsTrue(mEffective.TodoList, 'Befehl (#68) ist keine Zeichnung');
  Assert.IsTrue(mEffective.MetricsReport, 'Befehl (#66) ist keine Zeichnung');
  Assert.IsTrue(mEffective.TeamFile, 'Projektdatei (#486) ist keine Zeichnung');
  Assert.IsTrue(mEffective.StartProfiles, 'Startprofile (#575) sind keine Zeichnung');
  Assert.IsTrue(mEffective.TestDebug, 'Test debuggen (#585) ist keine Zeichnung');
  Assert.IsTrue(mEffective.BaselineUpdate, 'Befehl (#97) ist keine Zeichnung');
  Assert.IsTrue(mEffective.ReleaseGuard, 'Release-Wächter (#533) ist keine Zeichnung');
  Assert.IsTrue(mStored.PairColors);
  Assert.IsTrue(mStored.PairGuides);
  Assert.IsTrue(mStored.HoverTooltip);
  // Nächster Klick: alles wieder wie gespeichert.
  mSession.AllOff := False;
  mSession.Drop('HoverTooltip');
  Assert.IsFalse(mSession.TryGet('HoverTooltip', mValue));
  mEffective := mSession.Apply(mStored, mToggles);
  Assert.IsTrue(mEffective.PairColors);
  Assert.IsTrue(mEffective.HoverTooltip);
end;

procedure TAtlasQuickTogglesTests.ItemsShowProjectAndSession;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mItems: TArray<TAtlasQuickToggleItem>;
  mStored: TAtlasPluginSettings;
  mSession: TAtlasToggleSession;
  mRoot: TJSONObject;
begin
  mToggles := TAtlasQuickToggles.Build(cCatalog, cProject);
  mStored := TAtlasPluginSettings.Defaults;
  mStored.HoverTooltip := False;
  mSession := Default(TAtlasToggleSession);
  mRoot := TJSONObject.ParseJSONValue('{"hints":{"slash":false},"colors":{"pairs":"kein Wahrheitswert"}}')
    as TJSONObject;
  try
    mItems := TAtlasQuickToggles.Items(mToggles, mStored, mSession, mRoot);
    Assert.AreEqual(4, Integer(Length(mItems)));
    // PairColors: Wert im Projekt ist kein Wahrheitswert, also keine Markierung.
    Assert.IsFalse(mItems[0].Project);
    Assert.IsTrue(mItems[0].Checked);
    Assert.IsFalse(mItems[2].Checked, 'gespeicherter Wert');
    Assert.IsFalse(mItems[2].Project);
    // SlashCommands: atlas.json setzt false, gespeichert ist true.
    Assert.IsTrue(mItems[3].Project, 'Projekt-Markierung');
    Assert.IsFalse(mItems[3].Checked);
    mSession.Put('SlashCommands', True);
    mItems := TAtlasQuickToggles.Items(mToggles, mStored, mSession, mRoot);
    Assert.IsTrue(mItems[3].Session);
    Assert.IsTrue(mItems[3].Checked, 'Sitzungswert über dem Projekt');
    // Ohne Projekt keine Markierung.
    mItems := TAtlasQuickToggles.Items(mToggles, mStored, Default(TAtlasToggleSession), nil);
    Assert.IsFalse(mItems[3].Project);
    Assert.IsTrue(mItems[3].Checked);
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasQuickTogglesTests.ToggleTargets;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mItems: TArray<TAtlasQuickToggleItem>;
  mStored: TAtlasPluginSettings;
  mSession: TAtlasToggleSession;
  mValue: Boolean;
begin
  mToggles := TAtlasQuickToggles.Build(cCatalog, cProject);
  mStored := TAtlasPluginSettings.Defaults;
  mSession := Default(TAtlasToggleSession);
  mSession.Put('PairColors', True);
  mItems := TAtlasQuickToggles.Items(mToggles, mStored, mSession, nil);
  // Global: gespeicherter Wert, der Sitzungswert fällt weg.
  Assert.AreEqual('', TAtlasQuickToggles.Toggle(mItems[0], TAtlasToggleTarget.Global, mStored, mSession));
  Assert.IsFalse(mStored.PairColors);
  Assert.IsFalse(mSession.TryGet('PairColors', mValue));
  // Sitzung: gespeicherter Wert bleibt.
  Assert.AreEqual('', TAtlasQuickToggles.Toggle(mItems[2], TAtlasToggleTarget.Session, mStored, mSession));
  Assert.IsTrue(mStored.HoverTooltip);
  Assert.IsTrue(mSession.TryGet('HoverTooltip', mValue));
  Assert.IsFalse(mValue);
  // Projekt: neuer Wert für atlas.json, sonst nichts.
  Assert.AreEqual('false', TAtlasQuickToggles.Toggle(mItems[3], TAtlasToggleTarget.Project, mStored, mSession));
  Assert.IsTrue(mStored.SlashCommands);
  Assert.IsFalse(mSession.TryGet('SlashCommands', mValue));
end;

procedure TAtlasQuickTogglesTests.FeaturesNameGuardFeatures;
var
  mToggle: TAtlasQuickToggle;
  mOrdinal: Integer;
begin
  for mToggle in TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, AtlasSchemaJson) do
  begin
    if mToggle.Feature <> '' then
    begin
      mOrdinal := GetEnumValue(TypeInfo(TAtlasFeature), mToggle.Feature);
      Assert.IsTrue(mOrdinal >= 0, mToggle.Key + ': ' + mToggle.Feature);
      Assert.AreEqual(mToggle.Feature, GetEnumName(TypeInfo(TAtlasFeature), mOrdinal), mToggle.Key);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickTogglesTests);

end.
