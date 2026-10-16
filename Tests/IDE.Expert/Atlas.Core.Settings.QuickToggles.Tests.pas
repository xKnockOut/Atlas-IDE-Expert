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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.QuickToggles;

const
  Catalog =
    '{"properties":{' +
    '"PairColors":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Klammerfarben","x-captionEn":"Bracket colors"},' +
    '"HoverTooltip":{"type":"boolean","x-page":"Hints","x-quickToggle":true,"x-caption":"Hover"},' +
    '"FixCase":{"type":"boolean","x-page":"Editor","x-caption":"ohne Schnellschalter"},' +
    '"VisibleRows":{"type":"integer","x-page":"Editor","x-quickToggle":true},' +
    '"PairGuides":{"type":"boolean","x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"description":"Blocklinien"}' +
    '}}';
  Project =
    '{"properties":{' +
    '"hints":{"type":"object","x-page":"Hints","properties":{' +
      '"xmlDocFull":{"type":"boolean","x-quickToggle":true,"x-plugin":"XmlDocFull","x-caption":"XMLDoc"},' +
      '"xmlDocMaxLines":{"type":"integer"}}},' +
    '"highlight":{"type":"object","x-page":"Editor","properties":{' +
      '"blockPairs":{"type":"boolean","x-quickToggle":true}}},' +
    '"colors":{"type":"object","x-page":"Editor","properties":{' +
      '"pairs":{"type":"boolean","x-quickToggle":true,"x-plugin":"PairColors"}}}' +
    '}}';

procedure TAtlasQuickTogglesTests.BuildsListFromCatalog;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Groups: TArray<TAtlasQuickToggleGroup>;
begin
  Toggles := TAtlasQuickToggles.Build(Catalog, Project);
  // Nur boolesche Einstellungen mit x-quickToggle; ohne x-plugin kein globaler Wert (blockPairs).
  Assert.AreEqual(4, Integer(Length(Toggles)));
  // Nach Seiten gruppiert, Seiten in der Reihenfolge ihres ersten Schalters.
  Assert.AreEqual('PairColors', Toggles[0].Key);
  Assert.AreEqual('PairGuides', Toggles[1].Key);
  Assert.AreEqual('HoverTooltip', Toggles[2].Key);
  Assert.AreEqual('XmlDocFull', Toggles[3].Key);
  Assert.AreEqual('Klammerfarben', Toggles[0].Caption);
  Assert.AreEqual('Blocklinien', Toggles[1].Caption, 'ohne x-caption die Beschreibung');
  Assert.IsTrue(Toggles[0].Drawing);
  Assert.IsFalse(Toggles[2].Drawing);
  // Eintrag aus atlas.schema.json: Pfad im Projekt; schon im Plugin-Katalog: nur der Pfad kommt dazu.
  Assert.AreEqual('hints.xmlDocFull', Toggles[3].ProjectPath);
  Assert.AreEqual('Hints', Toggles[3].Page);
  Assert.AreEqual('colors.pairs', Toggles[0].ProjectPath);
  Assert.AreEqual('', Toggles[2].ProjectPath);
  Groups := TAtlasQuickToggles.Groups(Toggles);
  Assert.AreEqual(2, Integer(Length(Groups)));
  Assert.AreEqual('Editor', Groups[0].Page);
  Assert.AreEqual(2, Integer(Length(Groups[0].Toggles)));
  Assert.AreEqual('Hints', Groups[1].Page);
  // Englische Beschriftung, wo es eine gibt.
  Toggles := TAtlasQuickToggles.Build(Catalog, '', True);
  Assert.AreEqual('Bracket colors', Toggles[0].Caption);
  Assert.AreEqual('Hover', Toggles[2].Caption);
  Assert.AreEqual(0, Integer(Length(TAtlasQuickToggles.Build('kein JSON', ''))));
end;

procedure TAtlasQuickTogglesTests.RealCatalogsContainAcceptanceSwitches;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Toggle: TAtlasQuickToggle;
  Value: Boolean;
begin
  Toggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, AtlasSchemaJson);
  // Abnahme: mindestens Klammerfarben (#514) und Blocklinien.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'PairColors', Toggle));
  Assert.IsTrue(Toggle.Drawing);
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'PairGuides', Toggle));
  Assert.IsTrue(Toggle.Drawing);
  // hints ist global (x-scope, #227): Der Schalter schreibt nur die Plugin-Einstellung, nie atlas.json.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'XmlDocFull', Toggle));
  Assert.AreEqual('', Toggle.ProjectPath);
  for Toggle in Toggles do
    Assert.IsFalse(Toggle.ProjectPath.StartsWith('hints.') or Toggle.ProjectPath.StartsWith('index.'), Toggle.Key);
  Assert.IsFalse(TAtlasQuickToggles.Find(Toggles, 'StatusFieldSummary', Toggle), 'ohne x-quickToggle');
  // Diagnosemodus (#479): Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'DiagnosticMode', Toggle));
  Assert.AreEqual('Allgemein', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  // Tastenkürzel-Tipps (#600): Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'ShortcutTips', Toggle));
  Assert.AreEqual('Allgemein', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  // Benachrichtigungszentrale (#601): Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'Notifications', Toggle));
  Assert.AreEqual('Allgemein', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Notifications', Toggle.Feature);
  // Persönliche Notizen (#545): Schalter auf der Seite Editor, Symbol in der Rinne.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'Notes', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsTrue(Toggle.Drawing);
  Assert.AreEqual('Notes', Toggle.Feature);
  // Benannte Lesezeichen (#622): Schalter auf der Seite Editor, Symbol in der Rinne.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'BookmarksNamed', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsTrue(Toggle.Drawing);
  Assert.AreEqual('Bookmarks', Toggle.Feature);
  // Erzeugen-Menü (#719): Befehl, keine Zeichnung; „Alles aus“ lässt ihn stehen.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'GenerateMenu', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('EditorCommands', Toggle.Feature);
  // Code Lens mit Code-Metriken (#66): Zeichnung im Editor, „Alles aus“ schaltet sie ab.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'CodeLensMetrics', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsTrue(Toggle.Drawing);
  Assert.AreEqual('EditorCommands', Toggle.Feature);
  // Befehl (#66): Schalter auf der Seite Editor; keine Zeichnung, „Alles aus“ lässt ihn stehen.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'MetricsReport', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Palette', Toggle.Feature);
  // Projektdatei .atlas (#486): eigener Schalter auf der Seite Allgemein, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'TeamFile', Toggle));
  Assert.AreEqual('Allgemein', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Settings', Toggle.Feature);
  // Builds für Claude Code (#261): Schalter auf der Seite Compiler, keine Zeichnung.
  // Tests ausführen (#69): Code Lens zeichnet im Editor, Befehle und Lauf nach dem Build nicht.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'CodeLensTests', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsTrue(Toggle.Drawing);
  Assert.AreEqual('Build', Toggle.Feature);
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'TestRun', Toggle));
  Assert.AreEqual('Compiler', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'TestsAfterBuild', Toggle));
  Assert.IsFalse(TAtlasQuickToggles.Find(Toggles, 'BuildZeroHints', Toggle), 'ohne x-quickToggle');
  // Startprofile (#575): Befehl und Statusfeld je ein Schalter auf der Seite Compiler, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'StartProfiles', Toggle));
  Assert.AreEqual('Compiler', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Build', Toggle.Feature);
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'StartProfilesStatusField', Toggle));
  Assert.AreEqual('Compiler', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  // Test debuggen (#585): eigener Schalter für Befehl, Kontextmenü und Marke auf der Seite Debuggen; der
  // Haltepunkt am Anfang ist kein Schnellschalter.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'TestDebug', Toggle));
  Assert.AreEqual('Debuggen', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Build', Toggle.Feature);
  Assert.IsFalse(TAtlasQuickToggles.Find(Toggles, 'TestBreakAtStart', Toggle), 'ohne x-quickToggle');
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'McpBuild', Toggle));
  Assert.AreEqual('Compiler', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Build', Toggle.Feature);
  // Befehl (#68): Schalter auf der Seite Editor; keine Zeichnung, „Alles aus“ lässt ihn stehen.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'TodoList', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Palette', Toggle.Feature);
  // Befehl (#97): eigener Schalter je Palettenbefehl, keine Zeichnung.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'BaselineUpdate', Toggle));
  Assert.AreEqual('Editor', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('Palette', Toggle.Feature);
  // Einrichtungskarte und Befehl Atlas.ProjectSetup (#759): eigener Schalter auf der Seite Willkommensseite.
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'WelcomePageProjectSetup', Toggle));
  Assert.AreEqual('Willkommensseite', Toggle.Page);
  Assert.IsFalse(Toggle.Drawing);
  Assert.AreEqual('WelcomePage', Toggle.Feature);
  // Jeder Schalter ist eine Einstellung des Plugins.
  for Toggle in Toggles do
  begin
    Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, Toggle.Key, Value), Toggle.Key);
    Assert.IsTrue(Toggle.Caption <> '', Toggle.Key);
    Assert.IsTrue(Toggle.Page <> '', Toggle.Key);
  end;
end;

procedure TAtlasQuickTogglesTests.FlagsByName;
var
  Settings: TAtlasPluginSettings;
  Value: Boolean;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(TAtlasQuickToggles.SetFlag(Settings, 'PairColors', False));
  Assert.IsFalse(Settings.PairColors);
  Assert.IsTrue(Settings.PairGuides, 'andere Werte bleiben');
  Assert.AreEqual(TAtlasPluginSettings.Defaults.VisibleRows, Settings.VisibleRows);
  Assert.IsTrue(TAtlasQuickToggles.GetFlag(Settings, 'PairColors', Value));
  Assert.IsFalse(Value);
  Assert.IsTrue(TAtlasQuickToggles.SetFlag(Settings, 'Preview', True));
  Assert.IsTrue(Settings.Preview);
  Assert.IsFalse(TAtlasQuickToggles.SetFlag(Settings, 'GibtEsNicht', True));
  Assert.IsFalse(TAtlasQuickToggles.GetFlag(Settings, 'GibtEsNicht', Value));
end;

procedure TAtlasQuickTogglesTests.SessionAndAllOffKeepStoredValues;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Stored, Effective: TAtlasPluginSettings;
  Session: TAtlasToggleSession;
  Value: Boolean;
begin
  Toggles := TAtlasQuickToggles.Build(Catalog, Project);
  Stored := TAtlasPluginSettings.Defaults;
  Session := Default(TAtlasToggleSession);
  Session.Put('HoverTooltip', False);
  Session.Put('hovertooltip', False);
  Assert.AreEqual(1, Integer(Length(Session.Overrides)), 'ein Wert je Name');
  Effective := Session.Apply(Stored, Toggles);
  Assert.IsFalse(Effective.HoverTooltip);
  Assert.IsTrue(Effective.PairColors);
  // Alles aus: nur Zeichnungen, gespeicherte Werte unverändert.
  Session.AllOff := True;
  Effective := Session.Apply(Stored, Toggles);
  Assert.IsFalse(Effective.PairColors);
  Assert.IsFalse(Effective.PairGuides);
  Assert.IsTrue(Effective.Preview = Stored.Preview);
  Assert.IsTrue(Effective.GenerateMenu, 'Befehl (#719) ist keine Zeichnung');
  Assert.IsTrue(Effective.TodoList, 'Befehl (#68) ist keine Zeichnung');
  Assert.IsTrue(Effective.MetricsReport, 'Befehl (#66) ist keine Zeichnung');
  Assert.IsTrue(Effective.TeamFile, 'Projektdatei (#486) ist keine Zeichnung');
  Assert.IsTrue(Effective.StartProfiles, 'Startprofile (#575) sind keine Zeichnung');
  Assert.IsTrue(Effective.TestDebug, 'Test debuggen (#585) ist keine Zeichnung');
  Assert.IsTrue(Effective.BaselineUpdate, 'Befehl (#97) ist keine Zeichnung');
  Assert.IsTrue(Stored.PairColors);
  Assert.IsTrue(Stored.PairGuides);
  Assert.IsTrue(Stored.HoverTooltip);
  // Nächster Klick: alles wieder wie gespeichert.
  Session.AllOff := False;
  Session.Drop('HoverTooltip');
  Assert.IsFalse(Session.TryGet('HoverTooltip', Value));
  Effective := Session.Apply(Stored, Toggles);
  Assert.IsTrue(Effective.PairColors);
  Assert.IsTrue(Effective.HoverTooltip);
end;

procedure TAtlasQuickTogglesTests.ItemsShowProjectAndSession;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Items: TArray<TAtlasQuickToggleItem>;
  Stored: TAtlasPluginSettings;
  Session: TAtlasToggleSession;
  Root: TJSONObject;
begin
  Toggles := TAtlasQuickToggles.Build(Catalog, Project);
  Stored := TAtlasPluginSettings.Defaults;
  Stored.HoverTooltip := False;
  Session := Default(TAtlasToggleSession);
  Root := TJSONObject.ParseJSONValue('{"hints":{"xmlDocFull":false},"colors":{"pairs":"kein Wahrheitswert"}}')
    as TJSONObject;
  try
    Items := TAtlasQuickToggles.Items(Toggles, Stored, Session, Root);
    Assert.AreEqual(4, Integer(Length(Items)));
    // PairColors: Wert im Projekt ist kein Wahrheitswert, also keine Markierung.
    Assert.IsFalse(Items[0].Project);
    Assert.IsTrue(Items[0].Checked);
    Assert.IsFalse(Items[2].Checked, 'gespeicherter Wert');
    Assert.IsFalse(Items[2].Project);
    // XmlDocFull: atlas.json setzt false, gespeichert ist true.
    Assert.IsTrue(Items[3].Project, 'Projekt-Markierung');
    Assert.IsFalse(Items[3].Checked);
    Session.Put('XmlDocFull', True);
    Items := TAtlasQuickToggles.Items(Toggles, Stored, Session, Root);
    Assert.IsTrue(Items[3].Session);
    Assert.IsTrue(Items[3].Checked, 'Sitzungswert über dem Projekt');
    // Ohne Projekt keine Markierung.
    Items := TAtlasQuickToggles.Items(Toggles, Stored, Default(TAtlasToggleSession), nil);
    Assert.IsFalse(Items[3].Project);
    Assert.IsTrue(Items[3].Checked);
  finally
    Root.Free;
  end;
end;

procedure TAtlasQuickTogglesTests.ToggleTargets;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Items: TArray<TAtlasQuickToggleItem>;
  Stored: TAtlasPluginSettings;
  Session: TAtlasToggleSession;
  Value: Boolean;
begin
  Toggles := TAtlasQuickToggles.Build(Catalog, Project);
  Stored := TAtlasPluginSettings.Defaults;
  Session := Default(TAtlasToggleSession);
  Session.Put('PairColors', True);
  Items := TAtlasQuickToggles.Items(Toggles, Stored, Session, nil);
  // Global: gespeicherter Wert, der Sitzungswert fällt weg.
  Assert.AreEqual('', TAtlasQuickToggles.Toggle(Items[0], TAtlasToggleTarget.Global, Stored, Session));
  Assert.IsFalse(Stored.PairColors);
  Assert.IsFalse(Session.TryGet('PairColors', Value));
  // Sitzung: gespeicherter Wert bleibt.
  Assert.AreEqual('', TAtlasQuickToggles.Toggle(Items[2], TAtlasToggleTarget.Session, Stored, Session));
  Assert.IsTrue(Stored.HoverTooltip);
  Assert.IsTrue(Session.TryGet('HoverTooltip', Value));
  Assert.IsFalse(Value);
  // Projekt: neuer Wert für atlas.json, sonst nichts.
  Assert.AreEqual('false', TAtlasQuickToggles.Toggle(Items[3], TAtlasToggleTarget.Project, Stored, Session));
  Assert.IsTrue(Stored.XmlDocFull);
  Assert.IsFalse(Session.TryGet('XmlDocFull', Value));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickTogglesTests);

end.
