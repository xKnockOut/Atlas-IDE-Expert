unit Atlas.Core.Settings.Transfer.Tests;

// Einstellungen exportieren, importieren und zurücksetzen (#723): Katalog aus
// beiden Schemata, Export nur geänderter Werte ohne Zugangsdaten und
// Benutzerpfade, Import mit Zusammenführen und Ersetzen, unbekannte und alte
// Schlüssel, Sicherung, Zurücksetzen je Schlüssel, Bereich und komplett,
// Projektwerte unberührt, eingebaute Profile gültig gegen das Schema.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Settings.Catalog;

type
  [TestFixture]
  TAtlasSettingsCatalogTests = class
  private
    FCatalog: TAtlasSettingsCatalog;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CoversEveryPluginSetting;
    [Test]
    procedure PluginDefaultsMatchSettingsDefaults;
    [Test]
    procedure RoutedKeysArePathsInSettingsJson;
    [Test]
    procedure EveryEntryHasKnownAreaAndPage;
    [Test]
    procedure KeysAreUniqueAndNoProjectPaths;
    [Test]
    procedure GlobalKeysComeFromSchema;
    [Test]
    procedure ResolvesRegistryNamesAndFormerKeys;
    [Test]
    procedure ChecksValuesAgainstSchema;
  end;

  [TestFixture]
  TAtlasSettingsTransferTests = class
  private
    FCatalog: TAtlasSettingsCatalog;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ExportWritesOnlyModifiedValues;
    [Test]
    procedure ExportByArea;
    [Test]
    procedure ExportSkipsStateAndMachineValues;
    [Test]
    procedure ExportOmitsOrMasksSecrets;
    [Test]
    procedure ExportReplacesUserFolders;
    [Test]
    procedure ImportMergeTakesSelectedValues;
    [Test]
    procedure ImportReplaceResetsWholeArea;
    [Test]
    procedure ImportReportsAndSkipsUnknownKeys;
    [Test]
    procedure ImportMigratesOldKeys;
    [Test]
    procedure ImportRejectsInvalidValuesAndPlaceholders;
    [Test]
    procedure ImportExpandsPathMacros;
    [Test]
    procedure ProjectValuesStayUntouched;
    [Test]
    procedure BackupRestoresEverything;
    [Test]
    procedure BackupNamesAndCleanup;
    [Test]
    procedure ResetPerKey;
    [Test]
    procedure ResetPerAreaAndAll;
    [Test]
    procedure ResetNamesAndModifiedNamesForPage;
    [Test]
    procedure BuiltInProfilesAreValid;
    [Test]
    procedure ProfilesSwitchFeatures;
    [Test]
    procedure WelcomeLayoutsTravel;
    /// <summary>#1260: issues.connections geht als JSON-Liste (nicht als Text) in die Datei und zurück.</summary>
    [Test]
    procedure TrackerConnectionsTravel;
    /// <summary>#1261: issues.projects geht ebenso als JSON-Liste hin und zurück.</summary>
    [Test]
    procedure TrackerProjectsTravel;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Scopes,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.ProfileData,
  Atlas.Core.Settings.Transfer;

const
  TestPlugin =
    '{"x-version":2,"x-areas":{"editor":{"caption":"Editor"},"keys":{"caption":"Tasten"}},' +
    '"properties":{' +
    '"PairColors":{"type":"boolean","default":true,"x-key":"highlight.pairColors","x-area":"editor",' +
      '"x-page":"Editor","x-formerKeys":["editor.pairColors"]},' +
    '"ServerPath":{"type":"string","default":"","x-key":"server.path","x-area":"editor","x-page":"Editor",' +
      '"x-machine":true},' +
    '"WelcomePageHelpReportUrl":{"type":"string","default":"","x-key":"tracker.token","x-area":"editor",' +
      '"x-page":"Editor","x-secret":true},' +
    '"PaletteKey":{"type":"integer","default":0,"x-key":"keys.palette","x-area":"keys","x-page":"Befehle"}}}';
  TestServer =
    '{"properties":{"logLevel":{"type":"string","enum":["error","info"],"x-scope":"global","x-area":"editor"},' +
    '"rules":{"type":"object","x-scope":"project"}}}';

function Macros: TAtlasSettingsEnvironment;
begin
  Result :=
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'LOCALAPPDATA') then
        Result := 'C:\Users\max\AppData\Local'
      else if SameText(AName, 'APPDATA') then
        Result := 'C:\Users\max\AppData\Roaming'
      else if SameText(AName, 'USERPROFILE') then
        Result := 'C:\Users\max'
      else if SameText(AName, 'USERNAME') then
        Result := 'max';
    end;
end;

function State(const ASettings: TAtlasPluginSettings; const AGlobal: string): TAtlasSettingsState;
begin
  Result := TAtlasSettingsState.Create(ASettings, AGlobal);
end;

function FileOf(const ASettings: string): TAtlasSettingsFile;
begin
  Result := TAtlasSettingsTransfer.ParseFile('{"format":"atlas-settings","formatVersion":1,"schemaVersion":1,' +
    '"settings":{' + ASettings + '}}');
end;

function ItemOf(const APreview: TAtlasImportPreview; const AKey: string): TAtlasImportItem;
var
  Item: TAtlasImportItem;
begin
  for Item in APreview.Items do
    if Item.Key = AKey then
      Exit(Item);
  Result := Default(TAtlasImportItem);
  Assert.IsTrue(False, 'Eintrag fehlt: ' + AKey);
end;

function HasItem(const APreview: TAtlasImportPreview; const AKey: string): Boolean;
var
  Item: TAtlasImportItem;
begin
  Result := False;
  for Item in APreview.Items do
    if Item.Key = AKey then
      Exit(True);
end;

{ TAtlasSettingsCatalogTests }

procedure TAtlasSettingsCatalogTests.Setup;
begin
  FCatalog := TAtlasSettingsCatalog.CreateDefault;
end;

procedure TAtlasSettingsCatalogTests.TearDown;
begin
  FreeAndNil(FCatalog);
end;

procedure TAtlasSettingsCatalogTests.CoversEveryPluginSetting;
var
  Store: IAtlasMemorySettingsStore;
  Name: string;
  Plugin, Index: Integer;
begin
  // Jede Einstellung aus Save steht im Katalog (der Wächter in Update-ConfigDoc prüft dasselbe am Text).
  Store := TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults);
  for Name in Store.Names do
    Assert.IsTrue(FCatalog.IndexOfName(Name) >= 0, 'fehlt im Plugin-Katalog: ' + Name);
  Plugin := 0;
  for Index := 0 to FCatalog.Count - 1 do
    if FCatalog[Index].Source = asPlugin then
      Inc(Plugin);
  Assert.AreEqual(Integer(Length(Store.Names)), Plugin, 'Katalog hat Einträge ohne Save');
  Assert.IsTrue(FCatalog.IndexOfKey('settings.exportImport') >= 0);
  Assert.IsTrue(FCatalog.IndexOfKey('settings.exportSecrets') >= 0);
end;

procedure TAtlasSettingsCatalogTests.PluginDefaultsMatchSettingsDefaults;
var
  Index: Integer;
  Entry: TAtlasCatalogEntry;
begin
  for Index := 0 to FCatalog.Count - 1 do
  begin
    Entry := FCatalog[Index];
    if Entry.Source <> asPlugin then
      Continue;
    Assert.IsTrue(TAtlasJsonValues.Same(Entry.DefaultJson, TAtlasSettingsTransfer.DefaultJson(FCatalog, Index)),
      Entry.Name + ': Schema ' + Entry.DefaultJson + ', Defaults ' + TAtlasSettingsTransfer.DefaultJson(FCatalog, Index));
  end;
end;

procedure TAtlasSettingsCatalogTests.RoutedKeysArePathsInSettingsJson;
var
  Routed: TAtlasRoutedSetting;
  Index: Integer;
  Migrated: Boolean;
begin
  for Routed in TAtlasSettingsScopes.Routed do
  begin
    // Frühere Schlüssel (#770): nur über den neuen Eintrag, nicht als eigener.
    if Routed.Legacy then
    begin
      Index := FCatalog.Resolve(Routed.Path, Migrated);
      Assert.IsTrue(Migrated, Routed.Name);
      Assert.AreEqual('hints.xmlDocExpand', FCatalog[Index].Key, Routed.Name);
      Assert.AreEqual(-1, FCatalog.IndexOfKey(Routed.Path), Routed.Name);
      Continue;
    end;
    Index := FCatalog.IndexOfName(Routed.Name);
    Assert.IsTrue(Index >= 0, Routed.Name);
    Assert.AreEqual(Routed.Path, FCatalog[Index].Key, Routed.Name);
    // Nur einmal im Katalog: als Plugin-Einstellung.
    Assert.AreEqual(Index, FCatalog.IndexOfKey(Routed.Path));
  end;
end;

procedure TAtlasSettingsCatalogTests.EveryEntryHasKnownAreaAndPage;
const
  IssueAreas: array[0..8] of string = ('editor', 'completion', 'highlighting', 'keys', 'codeActions', 'build', 'debug',
    'snippets', 'bookmarks');
var
  Index: Integer;
  Area: string;
begin
  for Index := 0 to FCatalog.Count - 1 do
  begin
    Assert.IsTrue(FCatalog.HasArea(FCatalog[Index].Area), FCatalog[Index].Key + ': Bereich ' + FCatalog[Index].Area);
    if FCatalog[Index].Source = asPlugin then
      Assert.IsTrue(FCatalog[Index].Page <> '', FCatalog[Index].Key + ' ohne Seite');
  end;
  // Die Bereiche aus dem Issue.
  for Area in IssueAreas do
    Assert.IsTrue(FCatalog.HasArea(Area), Area);
  Assert.AreEqual('Lesezeichen', FCatalog.AreaCaption('bookmarks', False));
  Assert.AreEqual('Bookmarks', FCatalog.AreaCaption('bookmarks', True));
end;

procedure TAtlasSettingsCatalogTests.KeysAreUniqueAndNoProjectPaths;
var
  Index, Other: Integer;
begin
  for Index := 0 to FCatalog.Count - 1 do
  begin
    Other := FCatalog.IndexOfKey(FCatalog[Index].Key);
    Assert.AreEqual(Index, Other, 'doppelter Schlüssel ' + FCatalog[Index].Key);
    // Nur Schlüssel mit x-scope "both" (rules) sind zugleich Projektpfad; atlas.json überdeckt sie.
    if FCatalog[Index].ProjectPath <> FCatalog[Index].Key then
      Assert.IsFalse(FCatalog.IsProjectPath(FCatalog[Index].Key), 'Projektschlüssel im Katalog: ' + FCatalog[Index].Key);
  end;
end;

procedure TAtlasSettingsCatalogTests.GlobalKeysComeFromSchema;
var
  Index: Integer;
begin
  Index := FCatalog.IndexOfKey('completion.postfixTemplates');
  Assert.IsTrue(Index >= 0);
  Assert.AreEqual('snippets', FCatalog[Index].Area, 'x-area des Glieds');
  Assert.IsTrue(FCatalog[Index].Source = asGlobal);
  Index := FCatalog.IndexOfKey('highlight.blockPairs');
  Assert.AreEqual('highlighting', FCatalog[Index].Area, 'x-area des Objekts');
  Index := FCatalog.IndexOfKey('logLevel');
  Assert.AreEqual('general', FCatalog[Index].Area);
  Assert.IsTrue(FCatalog[FCatalog.IndexOfKey('delphiVersion')].Machine);
  Assert.IsFalse(FCatalog[FCatalog.IndexOfKey('delphiVersion')].Transferable);
  Assert.IsTrue(FCatalog[FCatalog.IndexOfKey('logFile')].IsPath);
  // Projektwerte (atlas.json) gehören nicht dazu, auch nicht die Projekt-Glieder gemischter Objekte.
  Assert.AreEqual(-1, FCatalog.IndexOfKey('format.indentSize'));
  // x-scope "both": der globale Wert gehört dazu, atlas.json überdeckt ihn.
  Index := FCatalog.IndexOfKey('rules');
  Assert.IsTrue(Index >= 0, 'rules global (both)');
  Assert.AreEqual('rules', FCatalog[Index].Area);
  Assert.AreEqual('rules', FCatalog[Index].ProjectPath);
  Assert.IsTrue(FCatalog.IsProjectPath('rules'));
  Assert.AreEqual(-1, FCatalog.IndexOfKey('completion.interfaceSection'));
  Assert.IsTrue(FCatalog.IsProjectPath('format.indentSize'));
  Assert.IsTrue(FCatalog.IsProjectPath('rules.empty-except'));
  Assert.IsTrue(FCatalog.IsProjectPath('completion.interfaceSection'));
  // Zustände und Rechnerwerte des Plugins.
  Assert.IsTrue(FCatalog[FCatalog.IndexOfName('ListWidth')].State);
  Assert.IsTrue(FCatalog[FCatalog.IndexOfName('ServerPath')].Machine);
  Assert.AreEqual('ci.provider', FCatalog[FCatalog.IndexOfName('WelcomePageTestsCiProvider')].TeamPath);
  Assert.AreEqual('shortcut', FCatalog[FCatalog.IndexOfName('PaletteKey')].Format);
end;

procedure TAtlasSettingsCatalogTests.ResolvesRegistryNamesAndFormerKeys;
var
  Catalog: TAtlasSettingsCatalog;
  Migrated: Boolean;
  Index: Integer;
begin
  Index := FCatalog.Resolve('highlight.pairColors', Migrated);
  Assert.AreEqual('PairColors', FCatalog[Index].Name);
  Assert.IsFalse(Migrated);
  Index := FCatalog.Resolve('PairColors', Migrated);
  Assert.AreEqual('highlight.pairColors', FCatalog[Index].Key);
  Assert.IsTrue(Migrated, 'Registry-Name');
  Assert.AreEqual(-1, FCatalog.Resolve('gibt.es.nicht', Migrated));
  Assert.IsFalse(Migrated);
  Catalog := TAtlasSettingsCatalog.Create(TestPlugin, TestServer);
  try
    Assert.AreEqual(2, Catalog.Version);
    Index := Catalog.Resolve('editor.pairColors', Migrated);
    Assert.AreEqual('highlight.pairColors', Catalog[Index].Key);
    Assert.IsTrue(Migrated, 'x-formerKeys');
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsCatalogTests.ChecksValuesAgainstSchema;
var
  Issues: TArray<string>;
begin
  Assert.IsTrue(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('settings.exportSecrets')], '"placeholder"', Issues));
  Assert.IsFalse(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('settings.exportSecrets')], '"alles"', Issues));
  Assert.IsFalse(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('highlight.pairColors')], '"ja"', Issues));
  Assert.IsTrue(Length(Issues) > 0);
  Assert.IsFalse(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('highlight.pairColors')], 'kaputt', Issues));
end;

{ TAtlasSettingsTransferTests }

procedure TAtlasSettingsTransferTests.Setup;
begin
  FCatalog := TAtlasSettingsCatalog.CreateDefault;
end;

procedure TAtlasSettingsTransferTests.TearDown;
begin
  FreeAndNil(FCatalog);
end;

procedure TAtlasSettingsTransferTests.ExportWritesOnlyModifiedValues;
var
  S: TAtlasPluginSettings;
  Result_: TAtlasExportResult;
  Source: TAtlasSettingsFile;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"logLevel": "debug"}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Source := TAtlasSettingsTransfer.ParseFile(Result_.Text);
  Assert.IsTrue(Source.Valid, Source.Error);
  Assert.AreEqual(3, Integer(Result_.Count));
  Assert.AreEqual(3, Integer(Length(Source.Keys)));
  Assert.Contains(Result_.Text, '"highlight.pairColors": false');
  Assert.Contains(Result_.Text, '"completion.visibleRows": 12');
  Assert.Contains(Result_.Text, '"logLevel": "debug"');
  // Kopf: Format, Schema- und Atlas-Version.
  Assert.AreEqual(1, Source.FormatVersion);
  Assert.AreEqual(FCatalog.Version, Source.SchemaVersion);
  Assert.IsTrue(Source.AtlasVersion <> '');
  Assert.AreEqual(Integer(Length(FCatalog.AreaIds)), Integer(Length(Source.Areas)));
  // Ohne Änderungen: leere Liste.
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.AreEqual(0, Integer(Result_.Count));
  Assert.IsTrue(TAtlasSettingsTransfer.ParseFile(Result_.Text).Valid);
end;

procedure TAtlasSettingsTransferTests.ExportByArea;
var
  S: TAtlasPluginSettings;
  Result_: TAtlasExportResult;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  S.BookmarksNamed := False;
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''),
    TAtlasExportOptions.Create(['highlighting', 'bookmarks'], smOmit), Macros());
  Assert.AreEqual(2, Integer(Result_.Count));
  Assert.Contains(Result_.Text, 'highlight.pairColors');
  Assert.Contains(Result_.Text, 'bookmarks.named');
  Assert.DoesNotContain(Result_.Text, 'completion.visibleRows');
  Assert.Contains(Result_.Text, '"areas": ["highlighting", "bookmarks"]');
end;

procedure TAtlasSettingsTransferTests.ExportSkipsStateAndMachineValues;
var
  S: TAtlasPluginSettings;
  Result_: TAtlasExportResult;
begin
  S := TAtlasPluginSettings.Defaults;
  S.ListWidth := 500;
  S.ServerPath := 'D:\Atlas\AtlasServer.exe';
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"delphiVersion": "12"}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.AreEqual(0, Integer(Result_.Count));
  Assert.DoesNotContain(Result_.Text, 'AtlasServer');
  Assert.DoesNotContain(Result_.Text, 'delphiVersion');
end;

procedure TAtlasSettingsTransferTests.ExportOmitsOrMasksSecrets;
var
  Catalog: TAtlasSettingsCatalog;
  S: TAtlasPluginSettings;
  Result_: TAtlasExportResult;
begin
  // Eintrag mit x-secret.
  Catalog := TAtlasSettingsCatalog.Create(TestPlugin, TestServer);
  try
    S := TAtlasPluginSettings.Defaults;
    // Normalize lässt nur Webadressen zu.
    S.WelcomePageHelpReportUrl := 'https://tracker.example/geheim123';
    Result_ := TAtlasSettingsTransfer.ExportSettings(Catalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
      Macros());
    Assert.AreEqual(0, Integer(Result_.Count));
    Assert.DoesNotContain(Result_.Text, 'geheim123');
    Assert.AreEqual(1, Integer(Length(Result_.Omitted)), 'x-secret');
    Assert.AreEqual('tracker.token', Result_.Omitted[0].Key);
    Assert.IsTrue(Result_.Omitted[0].Reason = orSecret);
    Result_ := TAtlasSettingsTransfer.ExportSettings(Catalog, State(S, ''),
      TAtlasExportOptions.Create(nil, smPlaceholder), Macros());
    Assert.DoesNotContain(Result_.Text, 'geheim123');
    Assert.Contains(Result_.Text, '"tracker.token": "<secret>"');
    Assert.AreEqual(1, Integer(Length(Result_.Placeholders)), 'Platzhalter');
  finally
    Catalog.Free;
  end;
  // Adresse mit Zugangsdaten im echten Katalog.
  S := TAtlasPluginSettings.Defaults;
  S.WelcomePageHelpReportUrl := 'https://max:pw@tracker.example/new';
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
    Macros());
  Assert.DoesNotContain(Result_.Text, 'max:pw');
  Assert.AreEqual(1, Integer(Length(Result_.Omitted)), 'Adresse mit Zugangsdaten');
  // Wahrheitswert unter einem Namen wie „login“ ist kein Geheimnis.
  S := TAtlasPluginSettings.Defaults;
  S.CiLogin := False;
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
    Macros());
  Assert.Contains(Result_.Text, '"welcomePage.tests.ci.login": false');
end;

procedure TAtlasSettingsTransferTests.ExportReplacesUserFolders;
var
  S: TAtlasPluginSettings;
  Result_: TAtlasExportResult;
begin
  S := TAtlasPluginSettings.Defaults;
  S.WelcomePageQuickActionsConsole := 'C:\Users\Max\AppData\Local\Microsoft\WindowsApps\wt.exe';
  S.WelcomePageHelpReportFolder := 'C:\Users\max\Documents\Berichte';
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"logFile": "D:\\max\\atlas.log"}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.Contains(Result_.Text, '"$(LOCALAPPDATA)\\Microsoft\\WindowsApps\\wt.exe"');
  Assert.Contains(Result_.Text, '"$(USERPROFILE)\\Documents\\Berichte"');
  // Benutzername ohne passenden Ordner: Wert bleibt weg.
  Assert.DoesNotContain(Result_.Text, 'atlas.log');
  Assert.AreEqual(1, Integer(Length(Result_.Omitted)));
  Assert.AreEqual('logFile', Result_.Omitted[0].Key);
  Assert.IsTrue(Result_.Omitted[0].Reason = orUserPath);
  // Ein Ordner, der nur mit dem Benutzerordner beginnt, ist keiner.
  S.WelcomePageHelpReportFolder := 'C:\Users\maxi\Berichte';
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
    Macros());
  Assert.Contains(Result_.Text, 'C:\\Users\\maxi\\Berichte');
end;

procedure TAtlasSettingsTransferTests.ImportMergeTakesSelectedValues;
var
  S: TAtlasPluginSettings;
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
  Index: Integer;
begin
  S := TAtlasPluginSettings.Defaults;
  S.VisibleRows := 7;
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, ''),
    FileOf('"highlight.pairColors": false, "completion.visibleRows": 7, "keys.palette": 0, "logLevel": "debug"'),
    imMerge, nil, Macros(), '', '');
  Assert.IsTrue(ItemOf(Preview, 'highlight.pairColors').Status = isChange);
  Assert.AreEqual('true', ItemOf(Preview, 'highlight.pairColors').CurrentJson);
  Assert.AreEqual('false', ItemOf(Preview, 'highlight.pairColors').NewJson);
  Assert.IsTrue(ItemOf(Preview, 'completion.visibleRows').Status = isSame);
  Assert.IsFalse(ItemOf(Preview, 'completion.visibleRows').Selected);
  Assert.IsTrue(ItemOf(Preview, 'logLevel').Status = isChange);
  Assert.AreEqual('', ItemOf(Preview, 'logLevel').CurrentJson, 'nicht gesetzt');
  Assert.AreEqual(3, Preview.SelectedCount);
  // Nur die gewählten Werte: keys.palette abwählen.
  for Index := 0 to High(Preview.Items) do
    if Preview.Items[Index].Key = 'keys.palette' then
      Preview.Items[Index].Selected := False;
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(S, '{"language": "de"}'), Preview);
  Assert.IsFalse(After.Plugin.PairColors);
  Assert.AreEqual(TAtlasPluginSettings.Defaults.PaletteKey, After.Plugin.PaletteKey);
  Assert.Contains(After.GlobalText, '"logLevel": "debug"');
  Assert.Contains(After.GlobalText, '"language": "de"', 'übrige Schlüssel bleiben');
  // Zusammenführen lässt alles andere, wie es ist.
  Assert.AreEqual(7, After.Plugin.VisibleRows);
end;

procedure TAtlasSettingsTransferTests.ImportReplaceResetsWholeArea;
var
  S: TAtlasPluginSettings;
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairGuides := False;
  S.PairColors := False;
  S.VisibleRows := 12;
  Preview := TAtlasSettingsTransfer.Preview(FCatalog,
    State(S, '{"highlight": {"blockPairs": false}, "logLevel": "debug"}'),
    FileOf('"highlight.pairColors": false'), imReplace, ['highlighting'], Macros(), '', '');
  Assert.IsTrue(ItemOf(Preview, 'highlight.pairColors').Status = isSame);
  Assert.IsTrue(ItemOf(Preview, 'highlight.pairGuides').Status = isReset);
  Assert.AreEqual('true', ItemOf(Preview, 'highlight.pairGuides').NewJson);
  Assert.IsTrue(ItemOf(Preview, 'highlight.blockPairs').Status = isReset);
  Assert.IsFalse(HasItem(Preview, 'completion.visibleRows'), 'anderer Bereich');
  After := TAtlasSettingsTransfer.Apply(FCatalog,
    State(S, '{"highlight": {"blockPairs": false}, "logLevel": "debug"}'), Preview);
  Assert.IsTrue(After.Plugin.PairGuides);
  Assert.IsFalse(After.Plugin.PairColors);
  Assert.DoesNotContain(After.GlobalText, 'blockPairs');
  Assert.Contains(After.GlobalText, '"logLevel": "debug"', 'anderer Bereich bleibt');
  Assert.AreEqual(12, After.Plugin.VisibleRows);
  // Mit Zusammenführen bleibt pairGuides.
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, ''), FileOf('"highlight.pairColors": false'),
    imMerge, ['highlighting'], Macros(), '', '');
  Assert.IsFalse(HasItem(Preview, 'highlight.pairGuides'));
end;

procedure TAtlasSettingsTransferTests.ImportReportsAndSkipsUnknownKeys;
var
  Source: TAtlasSettingsFile;
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
begin
  Source := TAtlasSettingsTransfer.ParseFile('{"format":"atlas-settings","formatVersion":1,"schemaVersion":99,' +
    '"settings":{"welcomePage.zukunft": [1, 2], "highlight.pairColors": false}}');
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Source, imMerge, nil,
    Macros(), '', '');
  Assert.IsTrue(Preview.Newer, 'neuere Version');
  Assert.IsTrue(ItemOf(Preview, 'welcomePage.zukunft').Status = isUnknown);
  Assert.IsFalse(ItemOf(Preview, 'welcomePage.zukunft').Selected);
  Assert.AreEqual(1, Preview.CountOf(isUnknown));
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Preview);
  Assert.IsFalse(After.Plugin.PairColors, 'der Rest gilt');
  Assert.DoesNotContain(After.GlobalText, 'zukunft');
end;

procedure TAtlasSettingsTransferTests.ImportMigratesOldKeys;
var
  Catalog: TAtlasSettingsCatalog;
  Source: TAtlasSettingsFile;
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
begin
  // Ältere Datei: flache Registry-Namen mit 0/1 (wie TAtlasMemorySettingsStore.ToJson).
  Source := TAtlasSettingsTransfer.ParseFile('{"PairColors": 0, "VisibleRows": 12, "SettingsExportSecrets": "placeholder"}');
  Assert.IsTrue(Source.Valid);
  Assert.AreEqual(0, Source.SchemaVersion);
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Source, imMerge, nil,
    Macros(), '', '');
  Assert.IsTrue(ItemOf(Preview, 'highlight.pairColors').Migrated);
  Assert.AreEqual('PairColors', ItemOf(Preview, 'highlight.pairColors').SourceKey);
  Assert.AreEqual('false', ItemOf(Preview, 'highlight.pairColors').NewJson, '0 wird false');
  Assert.IsTrue(ItemOf(Preview, 'completion.visibleRows').Status = isChange);
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Preview);
  Assert.IsFalse(After.Plugin.PairColors);
  Assert.AreEqual(12, After.Plugin.VisibleRows);
  Assert.AreEqual('placeholder', After.Plugin.SettingsExportSecrets);
  // #770: xmlDocFull (Wahrheitswert bzw. 0/1) wird zur Auswahl xmlDocExpand.
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    FileOf('"hints.xmlDocFull": true'), imMerge, nil, Macros(), '', '');
  Assert.IsTrue(ItemOf(Preview, 'hints.xmlDocExpand').Migrated);
  Assert.AreEqual('"expanded"', ItemOf(Preview, 'hints.xmlDocExpand').NewJson);
  Source := TAtlasSettingsTransfer.ParseFile('{"XmlDocFull": 0}');
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Source, imMerge, nil,
    Macros(), '', '');
  Assert.AreEqual('"collapsed"', ItemOf(Preview, 'hints.xmlDocExpand').NewJson);
  // Frühere Schlüssel (x-formerKeys).
  Catalog := TAtlasSettingsCatalog.Create(TestPlugin, TestServer);
  try
    Preview := TAtlasSettingsTransfer.Preview(Catalog, State(TAtlasPluginSettings.Defaults, ''),
      FileOf('"editor.pairColors": false'), imMerge, nil, Macros(), '', '');
    Assert.IsTrue(ItemOf(Preview, 'highlight.pairColors').Migrated);
    Assert.IsTrue(ItemOf(Preview, 'highlight.pairColors').Status = isChange);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsTransferTests.ImportRejectsInvalidValuesAndPlaceholders;
var
  Preview: TAtlasImportPreview;
begin
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    FileOf('"settings.exportSecrets": "alles", "highlight.pairColors": "ja", "welcomePage.help.reportUrl": "<secret>",' +
    '"server.path": "D:\\Atlas"'), imMerge, nil, Macros(), '', '');
  Assert.IsTrue(ItemOf(Preview, 'settings.exportSecrets').Status = isInvalid);
  Assert.IsTrue(Length(ItemOf(Preview, 'settings.exportSecrets').Issues) > 0);
  Assert.IsTrue(ItemOf(Preview, 'highlight.pairColors').Status = isInvalid);
  Assert.IsTrue(ItemOf(Preview, 'welcomePage.help.reportUrl').Status = isSecret);
  Assert.IsTrue(ItemOf(Preview, 'server.path').Status = isSkipped, 'Rechnerwert');
  Assert.AreEqual(0, Preview.SelectedCount);
end;

procedure TAtlasSettingsTransferTests.ImportExpandsPathMacros;
var
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
begin
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    FileOf('"welcomePage.quickActions.console": "$(LOCALAPPDATA)\\Microsoft\\WindowsApps\\wt.exe"'), imMerge, nil,
    Macros(), '', '');
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Preview);
  Assert.AreEqual('C:\Users\max\AppData\Local\Microsoft\WindowsApps\wt.exe',
    After.Plugin.WelcomePageQuickActionsConsole);
end;

procedure TAtlasSettingsTransferTests.ProjectValuesStayUntouched;
const
  ProjectText = '{"format": {"indentSize": 4}}';
  TeamText = '{"version": 1, "ci": {"provider": "jenkins", "url": "https://ci"}}';
var
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
  S: TAtlasPluginSettings;
  Result_: TAtlasExportResult;
begin
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, '{"language": "de"}'),
    FileOf('"format.indentSize": 2, "completion.interfaceSection": "x", "welcomePage.tests.ci.provider": "jenkins",' +
    '"welcomePage.tests.ci.intervalMinutes": 30'), imReplace, nil, Macros(), ProjectText, TeamText);
  // Projektwerte in der Datei werden übersprungen.
  Assert.IsTrue(ItemOf(Preview, 'format.indentSize').Status = isSkipped);
  Assert.IsTrue(ItemOf(Preview, 'completion.interfaceSection').Status = isSkipped);
  // Die Vorschau zeigt, was .atlas überdeckt.
  Assert.Contains(ItemOf(Preview, 'welcomePage.tests.ci.provider').Covered, '.atlas: ci.provider = jenkins');
  Assert.AreEqual('', ItemOf(Preview, 'welcomePage.tests.ci.intervalMinutes').Covered);
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, '{"language": "de"}'), Preview);
  Assert.DoesNotContain(After.GlobalText, 'indentSize', 'nicht nach settings.json');
  Assert.DoesNotContain(After.GlobalText, 'interfaceSection');
  // Export: nie Projektwerte (atlas.json-Schlüssel in settings.json werden ignoriert).
  S := TAtlasPluginSettings.Defaults;
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"format": {"useTabs": true}}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.AreEqual(0, Integer(Result_.Count));
  // x-scope "both" (rules): der globale Wert wandert mit, die Vorschau nennt den Projektwert, der ihn überdeckt.
  Result_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"rules": {"empty-except": "off"}}'),
    TAtlasExportOptions.Create(['rules'], smOmit), Macros());
  Assert.AreEqual(1, Integer(Result_.Count));
  Assert.Contains(Result_.Text, '"empty-except"');
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, ''), TAtlasSettingsTransfer.ParseFile(Result_.Text),
    imMerge, nil, Macros(), '{"rules": {"empty-except": "error"}}', '');
  Assert.IsTrue(ItemOf(Preview, 'rules').Status = isChange);
  Assert.Contains(ItemOf(Preview, 'rules').Covered, 'atlas.json: rules');
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(S, ''), Preview);
  Assert.Contains(After.GlobalText, '"empty-except"', 'nach settings.json');
end;

procedure TAtlasSettingsTransferTests.BackupRestoresEverything;
var
  S, Changed: TAtlasPluginSettings;
  Backup: TAtlasExportResult;
  Source: TAtlasSettingsFile;
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.ListWidth := 500;
  S.ServerPath := 'C:\Users\max\Atlas\AtlasServer.exe';
  S.PairColors := False;
  Backup := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"logLevel": "debug"}'),
    TAtlasExportOptions.ForBackup, Macros());
  // Sicherung: alles unverändert, auch Zustand, Rechnerwert und Benutzerpfad.
  Assert.Contains(Backup.Text, '"backup": true');
  Assert.Contains(Backup.Text, 'C:\\Users\\max\\Atlas');
  Source := TAtlasSettingsTransfer.ParseFile(Backup.Text);
  Assert.IsTrue(Source.Backup);
  Changed := TAtlasPluginSettings.Defaults;
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(Changed, ''), Source, imReplace, nil, Macros(), '', '');
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(Changed, ''), Preview);
  Assert.AreEqual(500, After.Plugin.ListWidth);
  Assert.AreEqual('C:\Users\max\Atlas\AtlasServer.exe', After.Plugin.ServerPath);
  Assert.IsFalse(After.Plugin.PairColors);
  Assert.Contains(After.GlobalText, '"logLevel": "debug"');
end;

procedure TAtlasSettingsTransferTests.BackupNamesAndCleanup;
var
  Delete: TArray<string>;
begin
  Assert.AreEqual('atlas-settings-20261016-142503.json',
    TAtlasSettingsTransfer.BackupFileName(EncodeDateTime(2026, 10, 16, 14, 25, 3, 0)));
  Delete := TAtlasSettingsTransfer.BackupsToDelete(['atlas-settings-20261016-142503.json', 'andere.json',
    'atlas-settings-20250101-000000.json', 'atlas-settings-20260101-000000.json'], 2);
  Assert.AreEqual(1, Integer(Length(Delete)));
  Assert.AreEqual('atlas-settings-20250101-000000.json', Delete[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.BackupsToDelete(['atlas-settings-1.json'], 10))));
end;

procedure TAtlasSettingsTransferTests.ResetPerKey;
var
  S: TAtlasPluginSettings;
  After: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  After := TAtlasSettingsTransfer.ResetKeys(FCatalog, State(S, '{"logLevel": "debug", "language": "de"}'),
    ['highlight.pairColors', 'logLevel']);
  Assert.IsTrue(After.Plugin.PairColors);
  Assert.AreEqual(12, After.Plugin.VisibleRows);
  Assert.DoesNotContain(After.GlobalText, 'logLevel');
  Assert.Contains(After.GlobalText, '"language": "de"');
  Assert.IsFalse(TAtlasSettingsTransfer.IsModified(FCatalog, After, FCatalog.IndexOfKey('highlight.pairColors')));
  Assert.IsTrue(TAtlasSettingsTransfer.IsModified(FCatalog, After, FCatalog.IndexOfKey('completion.visibleRows')));
end;

procedure TAtlasSettingsTransferTests.ResetPerAreaAndAll;
var
  S: TAtlasPluginSettings;
  After: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  S.ListWidth := 500;
  S.ServerPath := 'D:\Atlas\AtlasServer.exe';
  After := TAtlasSettingsTransfer.ResetAreas(FCatalog, State(S, ''), ['highlighting']);
  Assert.IsTrue(After.Plugin.PairColors);
  Assert.AreEqual(12, After.Plugin.VisibleRows);
  Assert.AreEqual(3, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, State(S, '{"logLevel": "debug"}')))),
    'drei geänderte Werte, Zustand und Rechnerwert zählen nicht');
  After := TAtlasSettingsTransfer.ResetAll(FCatalog, State(S, '{"logLevel": "debug", "delphiVersion": "12"}'));
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, After))));
  Assert.AreEqual(TAtlasPluginSettings.Defaults.VisibleRows, After.Plugin.VisibleRows);
  // Zustand und Rechnerwert bleiben.
  Assert.AreEqual(500, After.Plugin.ListWidth);
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', After.Plugin.ServerPath);
  Assert.Contains(After.GlobalText, 'delphiVersion');
  Assert.DoesNotContain(After.GlobalText, 'logLevel');
end;

procedure TAtlasSettingsTransferTests.TrackerConnectionsTravel;
const
  cList = '[{"name":"Firma","provider":"youtrack","url":"https://youtrack.firma.local"}]';
var
  mSettings: TAtlasPluginSettings;
  mExported: TAtlasExportResult;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.IssuesConnections := cList;
  mExported := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(mSettings, ''),
    TAtlasExportOptions.Create(['issues'], smOmit), Macros());
  Assert.AreEqual(1, Integer(mExported.Count), mExported.Text);
  Assert.Contains(mExported.Text, '"issues.connections": [');
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    TAtlasSettingsTransfer.ParseFile(mExported.Text), imMerge, nil, Macros(), '', '');
  Assert.AreEqual(1, mPreview.SelectedCount);
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.AreEqual(cList, mAfter.Plugin.IssuesConnections);
  // Zurücksetzen: leere Liste.
  mAfter := TAtlasSettingsTransfer.ResetAreas(FCatalog, State(mSettings, ''), ['issues']);
  Assert.AreEqual('[]', mAfter.Plugin.IssuesConnections);
end;

procedure TAtlasSettingsTransferTests.TrackerProjectsTravel;
const
  cList = '[{"match":"C:\\Projekte\\Kasse","connection":"Firma","project":"KASSE"}]';
var
  mSettings: TAtlasPluginSettings;
  mExported: TAtlasExportResult;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.IssuesProjects := cList;
  mExported := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(mSettings, ''),
    TAtlasExportOptions.Create(['issues'], smOmit), Macros());
  Assert.AreEqual(1, Integer(mExported.Count), mExported.Text);
  Assert.Contains(mExported.Text, '"issues.projects": [');
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    TAtlasSettingsTransfer.ParseFile(mExported.Text), imMerge, nil, Macros(), '', '');
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.AreEqual(cList, mAfter.Plugin.IssuesProjects);
  mAfter := TAtlasSettingsTransfer.ResetAreas(FCatalog, State(mSettings, ''), ['issues']);
  Assert.AreEqual('[]', mAfter.Plugin.IssuesProjects);
end;

procedure TAtlasSettingsTransferTests.WelcomeLayoutsTravel;
const
  LayoutsJson = '[{"name":"Arbeit","columns":3,"slots":[{"id":"atlas.state","column":0}]}]';
var
  S: TAtlasPluginSettings;
  Exported: TAtlasExportResult;
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
  Names: TArray<string>;
begin
  // #767: Layouts, aktives Layout, Spalten und der Schalter gehören zum Bereich „Willkommensseite“.
  S := TAtlasPluginSettings.Defaults;
  S.WelcomePageCustomLayout := False;
  S.WelcomePageColumns := 3;
  S.WelcomePageLayouts := LayoutsJson;
  S.WelcomePageActiveLayout := 'Arbeit';
  Exported := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''),
    TAtlasExportOptions.Create(['welcome'], smOmit), Macros());
  Assert.AreEqual(4, Integer(Exported.Count));
  Assert.Contains(Exported.Text, '"welcomePage.customLayout": false');
  Assert.Contains(Exported.Text, '"welcomePage.columns": 3');
  Assert.Contains(Exported.Text, '"welcomePage.layouts"');
  Assert.Contains(Exported.Text, '"welcomePage.activeLayout": "Arbeit"');
  // Import auf einem frischen Rechner.
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    TAtlasSettingsTransfer.ParseFile(Exported.Text), imMerge, nil, Macros(), '', '');
  Assert.AreEqual(4, Preview.SelectedCount);
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Preview);
  Assert.IsFalse(After.Plugin.WelcomePageCustomLayout);
  Assert.AreEqual(3, After.Plugin.WelcomePageColumns);
  Assert.AreEqual(LayoutsJson, After.Plugin.WelcomePageLayouts);
  Assert.AreEqual('Arbeit', After.Plugin.WelcomePageActiveLayout);
  // Geändert-Markierung und Zurücksetzen.
  Names := TAtlasSettingsTransfer.ModifiedNames(FCatalog, S);
  Assert.AreEqual(4, Integer(Length(Names)));
  After := TAtlasSettingsTransfer.ResetAreas(FCatalog, State(S, ''), ['welcome']);
  Assert.IsTrue(After.Plugin.WelcomePageCustomLayout);
  Assert.AreEqual(2, After.Plugin.WelcomePageColumns);
  Assert.AreEqual('', After.Plugin.WelcomePageLayouts);
  Assert.AreEqual('Standard', After.Plugin.WelcomePageActiveLayout);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, After))));
end;

procedure TAtlasSettingsTransferTests.ResetNamesAndModifiedNamesForPage;
var
  S, After: TAtlasPluginSettings;
  Names: TArray<string>;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.FixCase := not S.FixCase;
  S.ListWidth := 500;
  Names := TAtlasSettingsTransfer.ModifiedNames(FCatalog, S);
  Assert.AreEqual(2, Integer(Length(Names)), 'ListWidth ist Zustand');
  After := TAtlasSettingsTransfer.ResetNames(FCatalog, S, ['PairColors', 'ListWidth']);
  Assert.IsTrue(After.PairColors);
  Assert.AreEqual(500, After.ListWidth, 'Zustand wird nicht zurückgesetzt');
  Assert.IsTrue(After.FixCase <> TAtlasPluginSettings.Defaults.FixCase);
  Assert.AreEqual(1, Integer(Length(TAtlasSettingsTransfer.ModifiedNames(FCatalog, After))));
end;

procedure TAtlasSettingsTransferTests.BuiltInProfilesAreValid;
var
  Name: string;
  Issues: TArray<string>;
begin
  Assert.AreEqual(4, Integer(Length(AtlasProfileFiles)));
  for Name in AtlasProfileFiles do
  begin
    Assert.IsTrue(AtlasProfileJson(Name) <> '', Name);
    Assert.IsTrue(TAtlasSettingsTransfer.Validate(FCatalog, AtlasProfileJson(Name), Issues),
      Name + ': ' + string.Join('; ', Issues));
    Assert.IsTrue(TAtlasSettingsTransfer.ParseFile(AtlasProfileJson(Name)).Name <> '', Name + ' ohne Namen');
  end;
  // Validate findet Fehler.
  Assert.IsFalse(TAtlasSettingsTransfer.Validate(FCatalog, '{"format":"atlas-settings","formatVersion":1,' +
    '"schemaVersion":1,"mode":"alles","areas":["mond"],"settings":{"PairColors":true,"x.y":1,' +
    '"highlight.pairGuides":"ja","completion.listWidth":300}}', Issues));
  Assert.IsTrue(Length(Issues) >= 6, string.Join('; ', Issues));
end;

procedure TAtlasSettingsTransferTests.ProfilesSwitchFeatures;
var
  S: TAtlasPluginSettings;
  Source: TAtlasSettingsFile;
  Preview: TAtlasImportPreview;
  After: TAtlasSettingsState;
begin
  // Minimal: Zusatzfunktionen aus, Vervollständigung bleibt.
  Source := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson('minimal.json'));
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Source,
    TAtlasSettingsTransfer.ModeOf(Source), nil, Macros(), '', '');
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), Preview);
  Assert.IsTrue(After.Plugin.Enabled);
  Assert.IsTrue(After.Plugin.SettingsExportImport, 'Knöpfe bleiben');
  Assert.IsFalse(After.Plugin.PairColors);
  Assert.IsFalse(After.Plugin.WelcomePage);
  // Alles an.
  Source := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson('alles-an.json'));
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, After, Source, TAtlasSettingsTransfer.ModeOf(Source), nil,
    Macros(), '', '');
  After := TAtlasSettingsTransfer.Apply(FCatalog, After, Preview);
  Assert.IsTrue(After.Plugin.PairColors);
  Assert.IsTrue(After.Plugin.BuildOnOpen);
  Assert.IsTrue(After.Plugin.InlayHints);
  // Atlas-Standard ersetzt alles durch die Vorgaben.
  S := After.Plugin;
  S.VisibleRows := 12;
  Source := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson('atlas-standard.json'));
  Assert.IsTrue(TAtlasSettingsTransfer.ModeOf(Source) = imReplace);
  Preview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, '{"logLevel": "debug"}'), Source, imReplace, nil,
    Macros(), '', '');
  After := TAtlasSettingsTransfer.Apply(FCatalog, State(S, '{"logLevel": "debug"}'), Preview);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, After))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsCatalogTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsTransferTests);

end.
