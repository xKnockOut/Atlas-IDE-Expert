unit Atlas.Core.Settings.Tests;

// Tests für die Einstellungen des Plugins (#227, Teil Vervollständigung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPluginSettingsTests = class
  public
    [Test]
    procedure EmptyStoreGivesDefaults;
    [Test]
    procedure SaveAndLoadRoundTrip;
    [Test]
    procedure ClampsOutOfRangeValues;
    [Test]
    procedure IndexOptionsGoToGlobalFile;
    [Test]
    procedure XmlDocOptionsGoToGlobalFile;
    [Test]
    procedure AcceptOptionsRoundTrip;
    [Test]
    procedure OneActionAfterSaving;
    [Test]
    procedure UnitSearchOptions;
    /// <summary>Erzeugen-Menü (#719): Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure GenerateMenuOptions;
  end;

  [TestFixture]
  TAtlasSettingsScopesTests = class
  public
    [Test]
    procedure RoutesServerSettingsToGlobalFile;
    [Test]
    procedure KeepsCommentsAndOtherKeys;
    [Test]
    procedure MigratesRegistryValuesOnce;
    [Test]
    procedure LeavesBrokenFileAlone;
    [Test]
    procedure SplitsSchemaByScope;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Scopes;

type
  TMemoryStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TMemoryStore }

constructor TMemoryStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TMemoryStore.Destroy;
begin
  FStrings.Free;
  FValues.Free;
  inherited Destroy;
end;

function TMemoryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

{ TAtlasPluginSettingsTests }

procedure TAtlasPluginSettingsTests.EmptyStoreGivesDefaults;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.IsTrue(Settings.Enabled);
  Assert.AreEqual(9, Settings.VisibleRows);
  Assert.AreEqual(0, Settings.ListWidth, 'Liste automatisch');
  Assert.AreEqual(320, Settings.PanelWidth);
  Assert.IsTrue(Settings.AutoParentheses);
  Assert.IsFalse(Settings.Preview, 'Vorschau standardmäßig aus (#434)');
  Assert.IsTrue(Settings.OpenForEdits, 'Nicht geöffnete Dateien öffnen (#397)');
  Assert.IsFalse(Settings.InlayHints, 'Inlay-Hints standardmäßig aus (#401)');
  Assert.AreEqual($800D, Settings.ActionsKey, 'Code-Aktionen: Alt+Enter (#399)');
  Assert.AreEqual(0, Settings.TypeDefinitionKey, 'Typdefinition ohne Kürzel');
  Assert.IsTrue(Settings.MethodToggle, 'Deklaration/Implementierung wechseln standardmäßig an (#775)');
  Assert.AreEqual($6026, Settings.MethodToggleUpKey, 'Strg+Umschalt+Hoch (#775)');
  Assert.AreEqual($6028, Settings.MethodToggleDownKey, 'Strg+Umschalt+Runter (#775)');
  Assert.AreEqual(0, Settings.TestUnitKey, 'Testunit-Wechsel ohne Kürzel (#189)');
  Assert.IsTrue(Settings.CodeLensTestUnit, 'Code Lens Testunit standardmäßig an (#189)');
  Assert.IsTrue(Settings.CodeLensMetrics, 'Code Lens Metriken standardmäßig an (#66)');
  Assert.IsTrue(Settings.CodeLensTests, 'Code Lens „Test ausführen“ standardmäßig an (#69)');
  Assert.IsTrue(Settings.TestRun, 'Tests ausführen standardmäßig da (#69)');
  Assert.IsFalse(Settings.TestsAfterBuild, 'Tests nach dem Build standardmäßig aus (#69)');
  Assert.IsTrue(Settings.TestsBuildFirst, 'vor den Tests bauen standardmäßig an (#69)');
  Assert.IsFalse(Settings.BuildZeroHints, 'build.zeroHints standardmäßig aus (#530)');
  Assert.IsTrue(Settings.TodoList, 'Befehl standardmäßig da (#68)');
  Assert.IsTrue(Settings.MetricsReport, 'Befehl standardmäßig da (#66)');
  Assert.IsTrue(Settings.TeamFile, 'Projektdatei standardmäßig an (#486)');
  Assert.IsTrue(Settings.McpBuild, 'Builds für Claude Code standardmäßig erlaubt (#261)');
  Assert.IsTrue(Settings.BaselineUpdate, 'Befehl standardmäßig da (#97)');
  Assert.IsTrue(Settings.SlashCommands, 'Schnellbefehle standardmäßig an (#399)');
  Assert.IsTrue(Settings.Snippets, 'Code-Vorlagen standardmäßig an (#51)');
  Assert.IsTrue(Settings.ImportIdeTemplates, 'Live Templates der IDE standardmäßig an (#51)');
  // Vervollständigung und Parameter-Hint über die Tasten der IDE, ohne eigene Belegung (#494).
  Assert.AreEqual(0, Settings.CompletionKey);
  Assert.AreEqual(0, Settings.SignatureKey);
  Assert.IsFalse(Settings.SignatureKeyPriority);
  Assert.AreEqual(200, Settings.ProviderTimeLimitMs, 'Zeitlimit für Quellen (#493)');
  Assert.AreEqual($E041, Settings.QuickToggleKey, 'Schnellschalter: Strg+Umschalt+Alt+A (#604)');
  Assert.IsFalse(Settings.QuickToggleKeyPriority);
  // Diagnosemodus (#479): aus; Taste Strg+Umschalt+Alt+D, weil A den Schnellschaltern gehört.
  Assert.IsFalse(Settings.DiagnosticMode);
  Assert.AreEqual($E044, Settings.DiagnosticModeKey);
  Assert.IsFalse(Settings.DiagnosticModeKeyPriority);
  // Einrichtung mit Prüfliste (#625): beim Start zeigen, solange nicht alles grün ist; noch nie gesehen.
  Assert.IsTrue(Settings.SetupChecklist);
  Assert.IsFalse(Settings.SetupChecklistSeen);
  // Tastenkürzel-Übersicht (#520): Menüeintrag und Startprüfung an.
  Assert.IsTrue(Settings.KeyOverview);
  Assert.IsTrue(Settings.KeyStartupCheck);
  // Tastenkürzel-Tipps (#600): an, für Atlas und IDE.
  Assert.IsTrue(Settings.ShortcutTips);
  Assert.AreEqual('all', Settings.ShortcutTipsScope);
  // Abgesicherter Start (#722).
  Assert.IsTrue(Settings.SafeAskAfterCrash);
  Assert.IsTrue(Settings.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('shift', Settings.SafeStartupKey);
  Assert.AreEqual(10000, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(5, Settings.SafeKeepSettingsHistory);
  // Dateiübergreifendes Zurücknehmen (#721).
  Assert.IsTrue(Settings.UndoMultiFile);
  Assert.AreEqual(20, Settings.UndoMultiFileDepth);
  Assert.IsTrue(Settings.UndoMultiFilePersist);
  Assert.AreEqual(50, Settings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('partial', Settings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', Settings.UndoMultiFileNewFiles);
  Assert.AreEqual($C05A, Settings.UndoKey, 'Strg+Alt+Z');
  Assert.AreEqual($E05A, Settings.RedoKey, 'Strg+Alt+Umschalt+Z');
  Assert.IsFalse(Settings.UpdatesCheck, 'Update-Prüfung nur nach Zustimmung');
  Assert.IsTrue(Settings.BugReportAnonymize, 'Fehlerbericht anonymisiert');
  Assert.IsTrue(Settings.PairOwners, 'Anweisungen mitfärben standardmäßig an (#653)');
  Assert.AreEqual(1, Settings.PairGuideWidth, 'Blocklinien 1 px');
  Assert.AreEqual(75, Settings.PairGuideOpacity, 'Blocklinien 75 % Deckkraft');
  Assert.IsTrue(Settings.ProblemsList, 'Liste „Atlas-Probleme“ standardmäßig an');
  Assert.IsTrue(Settings.Favorites, 'Favoriten anheften standardmäßig an (#458)');
  Assert.IsTrue(Settings.Notes, 'Notizen standardmäßig an (#545)');
  Assert.IsTrue(Settings.BookmarksNamed, 'Benannte Lesezeichen standardmäßig an (#622)');
  Assert.IsFalse(Settings.BookmarksShared, 'Lesezeichen standardmäßig lokal, nicht im Repository (#622)');
  Assert.AreEqual($C04B, Settings.BookmarkKey, 'Strg+Alt+K (#622)');
end;

procedure TAtlasPluginSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 14;
  Settings.ListWidth := 500;
  Settings.PanelWidth := 400;
  Settings.PanelCollapsed := True;
  Settings.Learning := False;
  Settings.Favorites := False;
  Settings.Notes := False;
  Settings.BookmarksNamed := False;
  Settings.BookmarksShared := True;
  Settings.BookmarkKey := $C04C;
  Settings.Preview := True;
  Settings.OpenForEdits := False;
  Settings.InlayHints := True;
  Settings.ActionsKey := 0;
  Settings.ExpandKey := $4041;
  Settings.TypeDefinitionKey := $C054;
  Settings.MethodToggle := False;
  Settings.MethodToggleUpKey := 0;
  Settings.MethodToggleDownKey := $C044; // Strg+Alt+D
  Settings.TestUnitKey := $6054;
  Settings.CodeLensTestUnit := False;
  Settings.CodeLensMetrics := False;
  Settings.CodeLensTests := False;
  Settings.TestRun := False;
  Settings.TestsAfterBuild := True;
  Settings.TestsBuildFirst := False;
  Settings.BuildZeroHints := True;
  Settings.TodoList := False;
  Settings.MetricsReport := False;
  Settings.TeamFile := False;
  Settings.McpBuild := False;
  Settings.BaselineUpdate := False;
  Settings.EditorKeysPriority := True;
  Settings.SlashCommands := False;
  Settings.Snippets := False;
  Settings.ImportIdeTemplates := False;
  Settings.ServerPath := '  D:\Atlas\AtlasServer.exe ';
  Settings.SignatureKey := $6048; // Strg+Umschalt+H
  Settings.SignatureKeyPriority := True;
  Settings.CompletionKey := $4020; // Strg+Leer
  Settings.ProviderTimeLimitMs := 350;
  Settings.QuickToggleKey := $6051;
  Settings.QuickToggleKeyPriority := True;
  Settings.DiagnosticMode := True;
  Settings.DiagnosticModeKey := $6044;
  Settings.DiagnosticModeKeyPriority := True;
  Settings.SetupChecklist := False;
  Settings.SetupChecklistSeen := True;
  Settings.KeyOverview := False;
  Settings.KeyStartupCheck := False;
  Settings.ShortcutTips := False;
  Settings.ShortcutTipsScope := 'atlas';
  Settings.SafeAskAfterCrash := False;
  Settings.SafeAutoAfterRepeatedCrash := False;
  Settings.SafeStartupKey := 'none';
  Settings.SafeStartupTimeoutMs := 30000;
  Settings.SafeKeepSettingsHistory := 0;
  Settings.UndoMultiFile := False;
  Settings.UndoMultiFileDepth := 7;
  Settings.UndoMultiFilePersist := False;
  Settings.UndoMultiFileMaxSizeMb := 3;
  Settings.UndoMultiFileOnConflict := 'abort';
  Settings.UndoMultiFileNewFiles := 'keep';
  Settings.UndoKey := 0;
  Settings.RedoKey := $C059;
  Settings.UpdatesCheck := True;
  Settings.BugReportAnonymize := False;
  Settings.ProblemsList := False;
  Settings.PairOwners := False;
  Settings.PairGuideWidth := 3;
  Settings.PairGuideOpacity := 80;
  Settings.PairColorsDark := '#112233, #445566,#778899,#aabbcc,#DDEEFF';
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Enabled);
  Assert.AreEqual(14, Loaded.VisibleRows);
  Assert.AreEqual(500, Loaded.ListWidth);
  Assert.AreEqual(400, Loaded.PanelWidth);
  Assert.IsTrue(Loaded.PanelCollapsed);
  Assert.IsFalse(Loaded.Learning);
  Assert.IsFalse(Loaded.Favorites, 'Favoriten abschaltbar (#458)');
  Assert.IsFalse(Loaded.Notes, 'Notizen abschaltbar (#545)');
  Assert.IsFalse(Loaded.BookmarksNamed, 'Benannte Lesezeichen abschaltbar (#622)');
  Assert.IsTrue(Loaded.BookmarksShared, 'Lesezeichen für das Team (#622)');
  Assert.AreEqual($C04C, Loaded.BookmarkKey);
  Assert.IsTrue(Loaded.Preview);
  Assert.IsFalse(Loaded.OpenForEdits);
  Assert.IsTrue(Loaded.InlayHints);
  Assert.AreEqual(0, Loaded.ActionsKey, '0 = keine Taste');
  Assert.AreEqual($4041, Loaded.ExpandKey);
  Assert.AreEqual($6057, Loaded.ShrinkKey);
  Assert.AreEqual($C054, Loaded.TypeDefinitionKey);
  Assert.IsFalse(Loaded.MethodToggle);
  Assert.AreEqual(0, Loaded.MethodToggleUpKey, '0 = keine Taste');
  Assert.AreEqual($C044, Loaded.MethodToggleDownKey);
  Assert.AreEqual($6054, Loaded.TestUnitKey);
  Assert.IsFalse(Loaded.CodeLensTestUnit);
  Assert.IsFalse(Loaded.CodeLensMetrics);
  Assert.IsFalse(Loaded.CodeLensTests);
  Assert.IsFalse(Loaded.TestRun);
  Assert.IsTrue(Loaded.TestsAfterBuild);
  Assert.IsFalse(Loaded.TestsBuildFirst);
  Assert.IsTrue(Loaded.BuildZeroHints);
  Assert.IsFalse(Loaded.TodoList);
  Assert.IsFalse(Loaded.MetricsReport);
  Assert.IsFalse(Loaded.TeamFile);
  Assert.IsFalse(Loaded.McpBuild);
  Assert.IsFalse(Loaded.BaselineUpdate);
  Assert.IsTrue(Loaded.EditorKeysPriority);
  Assert.IsFalse(Loaded.SlashCommands);
  Assert.IsFalse(Loaded.Snippets);
  Assert.IsFalse(Loaded.ImportIdeTemplates);
  Assert.IsFalse(Loaded.PairOwners);
  Assert.AreEqual(3, Loaded.PairGuideWidth);
  Assert.AreEqual(80, Loaded.PairGuideOpacity);
  Assert.AreEqual('#112233,#445566,#778899,#AABBCC,#DDEEFF', Loaded.PairColorsDark, 'einheitlich geschrieben');
  Assert.IsFalse(Loaded.ProblemsList, 'Liste „Atlas-Probleme“ abgeschaltet');
  Assert.IsTrue(Loaded.Problems, 'Wellenlinien bleiben an');
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', Loaded.ServerPath, 'Serverpfad ohne Leerraum');
  Assert.AreEqual($6048, Loaded.SignatureKey);
  Assert.IsTrue(Loaded.SignatureKeyPriority);
  Assert.AreEqual($4020, Loaded.CompletionKey);
  Assert.IsFalse(Loaded.CompletionKeyPriority);
  Assert.AreEqual(350, Loaded.ProviderTimeLimitMs);
  Assert.AreEqual($6051, Loaded.QuickToggleKey);
  Assert.IsTrue(Loaded.QuickToggleKeyPriority);
  Assert.IsTrue(Loaded.DiagnosticMode);
  Assert.AreEqual($6044, Loaded.DiagnosticModeKey);
  Assert.IsTrue(Loaded.DiagnosticModeKeyPriority);
  Assert.IsFalse(Loaded.SetupChecklist);
  Assert.IsTrue(Loaded.SetupChecklistSeen);
  Assert.IsFalse(Loaded.KeyOverview);
  Assert.IsFalse(Loaded.KeyStartupCheck);
  Assert.IsFalse(Loaded.ShortcutTips);
  Assert.AreEqual('atlas', Loaded.ShortcutTipsScope);
  Assert.IsFalse(Loaded.SafeAskAfterCrash);
  Assert.IsFalse(Loaded.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('none', Loaded.SafeStartupKey);
  Assert.AreEqual(30000, Loaded.SafeStartupTimeoutMs);
  Assert.AreEqual(0, Loaded.SafeKeepSettingsHistory);
  Assert.IsFalse(Loaded.UndoMultiFile);
  Assert.AreEqual(7, Loaded.UndoMultiFileDepth);
  Assert.IsFalse(Loaded.UndoMultiFilePersist);
  Assert.AreEqual(3, Loaded.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', Loaded.UndoMultiFileOnConflict);
  Assert.AreEqual('keep', Loaded.UndoMultiFileNewFiles);
  Assert.AreEqual(0, Loaded.UndoKey);
  Assert.AreEqual($C059, Loaded.RedoKey);
  Assert.IsTrue(Loaded.UpdatesCheck);
  Assert.IsFalse(Loaded.BugReportAnonymize);
  Assert.AreEqual('', TAtlasPluginSettings.Defaults.ServerPath, 'Standard: leer');
end;

procedure TAtlasPluginSettingsTests.IndexOptionsGoToGlobalFile;
var
  Registry: IAtlasSettingsStore;
  Store: TAtlasRoutedSettingsStore;
  Keep: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // Index und Speicher gelten für alle Projekte und stehen in settings.json (#652), nicht in der Registry.
  Registry := TMemoryStore.Create;
  Store := TAtlasRoutedSettingsStore.Create(Registry, '');
  Keep := Store;
  Settings := TAtlasPluginSettings.Defaults;
  Settings.IndexSearchPaths := False;
  Settings.IndexLibraryPaths := True;
  Settings.IndexUsages := False;
  Settings.MemoryBudgetMb := 512;
  Settings.Save(Store);
  Assert.AreEqual(-1, Registry.ReadInteger('IndexSearchPaths', -1), 'nicht in der Registry');
  Assert.Contains(Store.Text, '"searchPaths": false');
  Assert.Contains(Store.Text, '"libraryPaths": true');
  Assert.Contains(Store.Text, '"memoryBudgetMb": 512');
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.IndexProjectGroup);
  Assert.IsFalse(Loaded.IndexSearchPaths);
  Assert.IsTrue(Loaded.IndexLibraryPaths);
  Assert.IsFalse(Loaded.IndexUsages);
  Assert.AreEqual(512, Loaded.MemoryBudgetMb);
  // Speichergrenze (#492): 0 = unbegrenzt, nicht negativ, höchstens 64 GB.
  Store.WriteInteger('MemoryBudgetMb', -5);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.MemoryBudgetMb);
  Store.WriteInteger('MemoryBudgetMb', 999999);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxMemoryBudgetMb, Loaded.MemoryBudgetMb);
end;

procedure TAtlasPluginSettingsTests.XmlDocOptionsGoToGlobalFile;
var
  Store: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // #654: XmlDocFull/XmlDocMaxLines als hints in settings.json.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.XmlDocFull);
  Assert.AreEqual(0, Settings.XmlDocMaxLines);
  Routed := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '');
  Store := Routed;
  Settings.XmlDocFull := False;
  Settings.XmlDocMaxLines := 12;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('XmlDocFull', 1));
  Assert.AreEqual(12, Store.ReadInteger('XmlDocMaxLines', 0));
  Assert.Contains(Routed.Text, '"xmlDocFull": false');
  Assert.Contains(Routed.Text, '"xmlDocMaxLines": 12');
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.XmlDocFull);
  Assert.AreEqual(12, Loaded.XmlDocMaxLines);
  // Grenzen 0..50.
  Store.WriteInteger('XmlDocMaxLines', 99);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxXmlDocLines, Loaded.XmlDocMaxLines);
  Store.WriteInteger('XmlDocMaxLines', -3);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.XmlDocMaxLines);
end;

procedure TAtlasPluginSettingsTests.AcceptOptionsRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung bis zum Öffnen.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CommitCharacters);
  Assert.IsTrue(Settings.AutoUses);
  Assert.IsTrue(Settings.ParameterHints);
  Assert.AreEqual(150, Settings.OpenDelayMs);
  Store := TMemoryStore.Create;
  Settings.CommitCharacters := False;
  Settings.AutoUses := False;
  Settings.ParameterHints := False;
  Settings.OpenDelayMs := 400;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CommitCharacters);
  Assert.IsFalse(Loaded.AutoUses);
  Assert.IsFalse(Loaded.ParameterHints);
  Assert.AreEqual(400, Loaded.OpenDelayMs);
  Store.WriteInteger('OpenDelayMs', 99999);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxOpenDelay, Loaded.OpenDelayMs);
  Store.WriteInteger('OpenDelayMs', -1);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.OpenDelayMs);
end;

procedure TAtlasPluginSettingsTests.ClampsOutOfRangeValues;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Store.WriteInteger('VisibleRows', 99);
  Store.WriteInteger('ListWidth', 50);
  Store.WriteInteger('PanelWidth', 5000);
  Store.WriteInteger('SignatureKey', -3);
  Store.WriteInteger('ProviderTimeLimitMs', 10);
  Store.WriteInteger('SafeStartupTimeoutMs', 5);
  Store.WriteInteger('SafeKeepSettingsHistory', 1000);
  Store.WriteString('SafeStartupKey', ' Alt ');
  Store.WriteInteger('UndoMultiFileDepth', 0);
  Store.WriteInteger('UndoMultiFileMaxSizeMb', 100000);
  Store.WriteString('UndoMultiFileOnConflict', ' ABORT ');
  Store.WriteString('UndoMultiFileNewFiles', 'irgendwas');
  Store.WriteString('ShortcutTipsScope', ' ATLAS ');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MinProviderTimeLimit, Settings.ProviderTimeLimitMs);
  Assert.AreEqual(0, Settings.SignatureKey, 'kein gültiges Kürzel');
  Store.WriteInteger('PairGuideWidth', 7);
  Store.WriteInteger('PairGuideOpacity', 0);
  Store.WriteString('PairColorsLight', '#123456,blau');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxPairGuideWidth, Settings.PairGuideWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinPairGuideOpacity, Settings.PairGuideOpacity);
  Assert.AreEqual('', Settings.PairColorsLight, 'ungültige Farben = Standard');
  Assert.AreEqual(TAtlasPluginSettings.MaxVisibleRows, Settings.VisibleRows);
  Assert.AreEqual(TAtlasPluginSettings.MinListWidth, Settings.ListWidth);
  Assert.AreEqual(TAtlasPluginSettings.MaxPanelWidth, Settings.PanelWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinSafeStartupTimeout, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(TAtlasPluginSettings.MaxSafeSettingsHistory, Settings.SafeKeepSettingsHistory);
  Assert.AreEqual('shift', Settings.SafeStartupKey, 'unbekannte Taste: Umschalt');
  Assert.AreEqual(TAtlasPluginSettings.MinUndoDepth, Settings.UndoMultiFileDepth);
  Assert.AreEqual(TAtlasPluginSettings.MaxUndoMaxSizeMb, Settings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', Settings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', Settings.UndoMultiFileNewFiles, 'unbekannt: Papierkorb');
  // shortcutTips.scope (#600): nur atlas oder all.
  Assert.AreEqual('atlas', Settings.ShortcutTipsScope);
  Settings.ShortcutTipsScope := 'ide';
  Settings.Normalize;
  Assert.AreEqual('all', Settings.ShortcutTipsScope, 'unbekannt: all');
end;

procedure TAtlasPluginSettingsTests.OneActionAfterSaving;
var
  Settings: TAtlasPluginSettings;
begin
  // Eine Auswahl „Nach dem Speichern“: Syntaxprüfung der IDE oder Kompilieren im Server, nie beides.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.CheckOnSave);
  Assert.IsFalse(Settings.CompileOnSave);
  Settings.CompileOnSave := True;
  Settings.Normalize;
  Assert.IsTrue(Settings.CompileOnSave);
  Settings.CheckOnSave := True;
  Settings.Normalize;
  Assert.IsTrue(Settings.CheckOnSave);
  Assert.IsFalse(Settings.CompileOnSave);
end;

procedure TAtlasPluginSettingsTests.GenerateMenuOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GenerateMenu, 'standardmäßig an');
  Assert.AreEqual($802D, Settings.GenerateMenuKey, 'Alt+Einfg');
  Assert.AreEqual('generate,surround,templates', Settings.GenerateMenuGroups);
  Assert.AreEqual('', Settings.GenerateMenuHidden);
  Assert.IsTrue(Settings.GenerateMenuRecentFirst);
  Assert.IsTrue(Settings.GenerateMenuShowCommandNames);
  // Unbekannte Gruppen entfallen, Reihenfolge bleibt; Ausgeblendete ohne Leere und Doppelte.
  Settings.GenerateMenuGroups := ' Templates; quatsch, generate ';
  Settings.GenerateMenuHidden := '/json, , /json,tryf';
  Settings.Normalize;
  Assert.AreEqual('templates,generate', Settings.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', Settings.GenerateMenuHidden);
  Settings.GenerateMenuGroups := 'nichts';
  Settings.Normalize;
  Assert.AreEqual('generate,surround,templates', Settings.GenerateMenuGroups, 'ohne bekannte Gruppe: Vorgabe');
  // Speichern und Laden.
  Settings.GenerateMenu := False;
  Settings.GenerateMenuKey := 0;
  Settings.GenerateMenuGroups := 'surround,generate';
  Settings.GenerateMenuRecentFirst := False;
  Settings.GenerateMenuShowCommandNames := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GenerateMenu, 'abschaltbar');
  Assert.AreEqual(0, Loaded.GenerateMenuKey, '0 = keine Taste');
  Assert.AreEqual('surround,generate', Loaded.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', Loaded.GenerateMenuHidden);
  Assert.IsFalse(Loaded.GenerateMenuRecentFirst);
  Assert.IsFalse(Loaded.GenerateMenuShowCommandNames);
end;

procedure TAtlasPluginSettingsTests.UnitSearchOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Units suchen (#777): alles an, Strg+F12 übernommen, Gruppen nach Projekt, Herkunft Projektgruppe.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.UnitSearchEnabled);
  Assert.IsTrue(Settings.UnitSearchReplaceIdeDialog, 'überschreibt Strg+F12 standardmäßig');
  Assert.IsTrue(Settings.UnitSearchRememberCollapsed);
  Assert.IsTrue(Settings.UnitSearchFilters);
  Assert.IsTrue(Settings.UnitSearchFilterSyntax);
  Assert.IsTrue(Settings.UnitSearchPreview);
  Assert.IsTrue(Settings.UnitSearchPreviewForm);
  Assert.IsTrue(Settings.UnitSearchPreviewUsedBy);
  Assert.IsTrue(Settings.UnitSearchMultiSelect);
  Assert.IsTrue(Settings.UnitSearchActions);
  Assert.IsTrue(Settings.UnitSearchActionsAddUses);
  Assert.AreEqual('relative', Settings.UnitSearchPathStyle);
  Assert.AreEqual('project', Settings.UnitSearchGroupBy);
  Assert.AreEqual('group', Settings.UnitSearchDefaultScope);
  Assert.AreEqual(0, Settings.UnitSearchKey);
  // Unbekannte Werte fallen auf die Vorgabe zurück, Groß-/Kleinschrift wird vereinheitlicht.
  Settings.UnitSearchPathStyle := 'irgendwie';
  Settings.UnitSearchGroupBy := 'FOLDER';
  Settings.UnitSearchDefaultScope := 'searchpath';
  Settings.Normalize;
  Assert.AreEqual('relative', Settings.UnitSearchPathStyle);
  Assert.AreEqual('folder', Settings.UnitSearchGroupBy);
  Assert.AreEqual('searchPath', Settings.UnitSearchDefaultScope);
  // Speichern und Laden.
  Settings.UnitSearchEnabled := False;
  Settings.UnitSearchReplaceIdeDialog := False;
  Settings.UnitSearchRememberCollapsed := False;
  Settings.UnitSearchFilters := False;
  Settings.UnitSearchFilterSyntax := False;
  Settings.UnitSearchPreview := False;
  Settings.UnitSearchPreviewForm := False;
  Settings.UnitSearchPreviewUsedBy := False;
  Settings.UnitSearchMultiSelect := False;
  Settings.UnitSearchActions := False;
  Settings.UnitSearchActionsAddUses := False;
  Settings.UnitSearchPathStyle := 'compact';
  Settings.UnitSearchDefaultScope := 'library';
  Settings.UnitSearchKey := $6055;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.UnitSearchEnabled);
  Assert.IsFalse(Loaded.UnitSearchReplaceIdeDialog);
  Assert.IsFalse(Loaded.UnitSearchRememberCollapsed);
  Assert.IsFalse(Loaded.UnitSearchFilters);
  Assert.IsFalse(Loaded.UnitSearchFilterSyntax);
  Assert.IsFalse(Loaded.UnitSearchPreview);
  Assert.IsFalse(Loaded.UnitSearchPreviewForm);
  Assert.IsFalse(Loaded.UnitSearchPreviewUsedBy);
  Assert.IsFalse(Loaded.UnitSearchMultiSelect);
  Assert.IsFalse(Loaded.UnitSearchActions);
  Assert.IsFalse(Loaded.UnitSearchActionsAddUses);
  Assert.AreEqual('compact', Loaded.UnitSearchPathStyle);
  Assert.AreEqual('folder', Loaded.UnitSearchGroupBy);
  Assert.AreEqual('library', Loaded.UnitSearchDefaultScope);
  Assert.AreEqual($6055, Loaded.UnitSearchKey);
end;

{ TAtlasSettingsScopesTests }

procedure TAtlasSettingsScopesTests.RoutesServerSettingsToGlobalFile;
var
  Registry: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
  Setting: TAtlasRoutedSetting;
begin
  Registry := TMemoryStore.Create;
  Routed := TAtlasRoutedSettingsStore.Create(Registry, '');
  Store := Routed;
  Store.WriteInteger('SlashCommands', 0);
  Store.WriteInteger('InlayHints', 1);
  Store.WriteInteger('CompileOnSave', 1);
  Store.WriteInteger('CodeLensMetrics', 0);
  Store.WriteInteger('PairColors', 0);
  Store.WriteString('ServerPath', 'C:\Atlas\AtlasServer.exe');
  Assert.Contains(Routed.Text, '"slashCommands": {');
  Assert.Contains(Routed.Text, '"enabled": false');
  Assert.Contains(Routed.Text, '"parameterNames": true');
  Assert.Contains(Routed.Text, '"onSave": true');
  Assert.Contains(Routed.Text, '"metrics": false', 'codeLens.metrics in settings.json (#66)');
  // Reine Plugin-Werte bleiben in der Registry.
  Assert.DoesNotContain(Routed.Text, 'PairColors');
  Assert.AreEqual(0, Registry.ReadInteger('PairColors', 1));
  Assert.AreEqual('C:\Atlas\AtlasServer.exe', Registry.ReadString('ServerPath', ''));
  Assert.AreEqual(-1, Registry.ReadInteger('SlashCommands', -1));
  Assert.IsTrue(TAtlasSettingsScopes.TryRouted('indexusages', Setting));
  Assert.AreEqual('index.usages', Setting.Path);
  Assert.IsFalse(TAtlasSettingsScopes.TryRouted('PairColors', Setting));
  Assert.AreEqual(Length(TAtlasSettingsScopes.Routed) + 1, Length(TAtlasSettingsScopes.IdeManagedPaths));
  Assert.AreEqual('delphiVersion', TAtlasSettingsScopes.IdeManagedPaths[0]);
end;

procedure TAtlasSettingsScopesTests.KeepsCommentsAndOtherKeys;
const
  Original = '{'#13#10'  // eigene Notiz'#13#10'  "language": "en",'#13#10'  "index": {"usages": true}'#13#10'}'#13#10;
var
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
begin
  Routed := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, Original);
  Store := Routed;
  // Gleicher Wert: Der Text bleibt genau gleich.
  Store.WriteInteger('IndexUsages', 1);
  Assert.AreEqual(Original, Routed.Text);
  Store.WriteInteger('IndexUsages', 0);
  Assert.Contains(Routed.Text, '// eigene Notiz');
  Assert.Contains(Routed.Text, '"language": "en"');
  Assert.Contains(Routed.Text, '"usages": false');
  Assert.AreEqual(0, Store.ReadInteger('IndexUsages', 1));
end;

procedure TAtlasSettingsScopesTests.MigratesRegistryValuesOnce;
var
  Registry: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
begin
  // Bis hierher lagen Index und XMLDoc in der Registry; settings.json übernimmt sie einmal.
  Registry := TMemoryStore.Create;
  Registry.WriteInteger('IndexLibraryPaths', 1);
  Registry.WriteInteger('XmlDocMaxLines', 7);
  Routed := TAtlasRoutedSettingsStore.Create(Registry, '{"index": {"libraryPaths": false}}');
  Store := Routed;
  // Ohne Wert in settings.json gilt bis zur Übernahme der alte Wert.
  Assert.AreEqual(7, Store.ReadInteger('XmlDocMaxLines', 0));
  Assert.AreEqual(0, Store.ReadInteger('IndexLibraryPaths', 1), 'settings.json gewinnt');
  Assert.IsTrue(Routed.Migrate);
  Assert.Contains(Routed.Text, '"xmlDocMaxLines": 7');
  Assert.Contains(Routed.Text, '"libraryPaths": false');
  Assert.IsFalse(Routed.Migrate, 'nur einmal');
end;

procedure TAtlasSettingsScopesTests.LeavesBrokenFileAlone;
var
  Registry: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
begin
  Registry := TMemoryStore.Create;
  Registry.WriteInteger('IndexUsages', 0);
  Routed := TAtlasRoutedSettingsStore.Create(Registry, '{"index": ');
  Store := Routed;
  Assert.IsFalse(Routed.Migrate);
  Store.WriteInteger('IndexSearchPaths', 0);
  Assert.AreEqual('{"index": ', Routed.Text);
  Assert.AreEqual(0, Store.ReadInteger('IndexUsages', 1));
end;

procedure TAtlasSettingsScopesTests.SplitsSchemaByScope;
var
  Fields, Project, Global: TArray<TAtlasSettingField>;
  Field: TAtlasSettingField;
  Paths: string;
begin
  Fields := TAtlasSettingsSchema.Fields(AtlasSchemaJson);
  Project := TAtlasSettingsSchema.ForScope(Fields, False, nil);
  Global := TAtlasSettingsSchema.ForScope(Fields, True, TAtlasSettingsScopes.IdeManagedPaths);
  Paths := '|';
  for Field in Project do
    Paths := Paths + Field.Path + '|';
  Assert.Contains(Paths, '|rules|');
  Assert.Contains(Paths, '|index.exclude|');
  Assert.Contains(Paths, '|completion.senderCast|');
  Assert.DoesNotContain(Paths, '|index.projectGroup|');
  Assert.DoesNotContain(Paths, '|language|');
  Paths := '|';
  for Field in Global do
    Paths := Paths + Field.Path + '|';
  Assert.Contains(Paths, '|language|');
  Assert.Contains(Paths, '|completion.matching|');
  // Versionsverwaltung (#571): im Dialog der globalen Einstellungen, Seite Allgemein, als Auswahl.
  Assert.Contains(Paths, '|vcs.provider|');
  for Field in Global do
    if Field.Path = 'vcs.provider' then
    begin
      Assert.AreEqual('Allgemein', Field.Page);
      Assert.AreEqual('"auto"', Field.DefaultJson);
      Assert.AreEqual(4, Integer(Length(Field.Choices)));
      Assert.AreEqual('"off"', Field.Choices[3]);
    end;
  // Auf den Reitern der Optionsseite bzw. von der IDE gesetzt: nicht noch einmal im Dialog.
  Assert.DoesNotContain(Paths, '|index.projectGroup|');
  Assert.DoesNotContain(Paths, '|hints.xmlDocFull|');
  Assert.DoesNotContain(Paths, '|delphiVersion|');
  Assert.DoesNotContain(Paths, '|rules|');
  // Jedes umgeleitete Feld ist im Schema global.
  for Field in Fields do
    if Pos('|' + Field.Path + '|', '|index.projectGroup|memoryBudgetMb|compiler.onSave|slashCommands.enabled|') > 0 then
      Assert.IsTrue(Field.Global, Field.Path);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsScopesTests);

end.
