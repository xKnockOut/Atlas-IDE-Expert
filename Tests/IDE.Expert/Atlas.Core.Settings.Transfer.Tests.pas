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
    procedure ImportMigratesProblemsLive;
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
  Atlas.Core.Settings.ProfileData,
  Atlas.Core.Settings.Transfer;

const
  cTestPlugin =
    '{"x-version":2,"x-areas":{"editor":{"caption":"Editor"},"keys":{"caption":"Tasten"}},' +
    '"properties":{' +
    '"PairColors":{"type":"boolean","default":true,"x-key":"highlight.pairColors","x-area":"editor",' +
      '"x-page":"Editor","x-formerKeys":["editor.pairColors"]},' +
    '"ServerPath":{"type":"string","default":"","x-key":"server.path","x-area":"editor","x-page":"Editor",' +
      '"x-machine":true},' +
    '"WelcomePageHelpReportUrl":{"type":"string","default":"","x-key":"tracker.token","x-area":"editor",' +
      '"x-page":"Editor","x-secret":true},' +
    '"PaletteKey":{"type":"integer","default":0,"x-key":"keys.palette","x-area":"keys","x-page":"Befehle"}}}';
  cTestServer =
    '{"properties":{"logLevel":{"type":"string","enum":["error","info"],"x-scope":"global","x-area":"editor"},' +
    '"rules":{"type":"object","x-scope":"project"}}}';

function Macros: TAtlasSettingsEnvironment;
begin
  Result :=
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'LOCALAPPDATA') then
      begin
        Result := 'C:\Users\max\AppData\Local';
      end
      else if SameText(AName, 'APPDATA') then
      begin
        Result := 'C:\Users\max\AppData\Roaming';
      end
      else if SameText(AName, 'USERPROFILE') then
      begin
        Result := 'C:\Users\max';
      end
      else if SameText(AName, 'USERNAME') then
      begin
        Result := 'max';
      end;
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
  mItem: TAtlasImportItem;
begin
  for mItem in APreview.Items do
  begin
    if mItem.Key = AKey then
    begin
      Exit(mItem);
    end;
  end;
  Result := Default(TAtlasImportItem);
  Assert.IsTrue(False, 'Eintrag fehlt: ' + AKey);
end;

function HasItem(const APreview: TAtlasImportPreview; const AKey: string): Boolean;
var
  mItem: TAtlasImportItem;
begin
  Result := False;
  for mItem in APreview.Items do
  begin
    if mItem.Key = AKey then
    begin
      Exit(True);
    end;
  end;
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
  mStore: IAtlasMemorySettingsStore;
  mName: string;
  mPlugin, mIndex: Integer;
begin
  // Jede Einstellung aus Save steht im Katalog (der Wächter in Update-ConfigDoc prüft dasselbe am Text).
  mStore := TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults);
  for mName in mStore.Names do
  begin
    Assert.IsTrue(FCatalog.IndexOfName(mName) >= 0, 'fehlt im Plugin-Katalog: ' + mName);
  end;
  mPlugin := 0;
  for mIndex := 0 to FCatalog.Count - 1 do
  begin
    if FCatalog[mIndex].Source = asPlugin then
    begin
      Inc(mPlugin);
    end;
  end;
  Assert.AreEqual(Integer(Length(mStore.Names)), mPlugin, 'Katalog hat Einträge ohne Save');
  Assert.IsTrue(FCatalog.IndexOfKey('settings.exportImport') >= 0);
  Assert.IsTrue(FCatalog.IndexOfKey('settings.exportSecrets') >= 0);
end;

procedure TAtlasSettingsCatalogTests.PluginDefaultsMatchSettingsDefaults;
var
  mIndex: Integer;
  mEntry: TAtlasCatalogEntry;
begin
  for mIndex := 0 to FCatalog.Count - 1 do
  begin
    mEntry := FCatalog[mIndex];
    if mEntry.Source <> asPlugin then
    begin
      Continue;
    end;
    Assert.IsTrue(TAtlasJsonValues.Same(mEntry.DefaultJson, TAtlasSettingsTransfer.DefaultJson(FCatalog, mIndex)),
      mEntry.Name + ': Schema ' + mEntry.DefaultJson + ', Defaults ' + TAtlasSettingsTransfer.DefaultJson(FCatalog, mIndex));
  end;
end;

procedure TAtlasSettingsCatalogTests.RoutedKeysArePathsInSettingsJson;
var
  mRouted: TAtlasRoutedSetting;
  mIndex: Integer;
  mMigrated: Boolean;
begin
  for mRouted in TAtlasSettingsScopes.Routed do
  begin
    // Frühere Schlüssel (#770): nur über den neuen Eintrag, nicht als eigener.
    if mRouted.Legacy then
    begin
      mIndex := FCatalog.Resolve(mRouted.Path, mMigrated);
      Assert.IsTrue(mMigrated, mRouted.Name);
      Assert.AreEqual('hints.xmlDocExpand', FCatalog[mIndex].Key, mRouted.Name);
      Assert.AreEqual(-1, FCatalog.IndexOfKey(mRouted.Path), mRouted.Name);
      Continue;
    end;
    mIndex := FCatalog.IndexOfName(mRouted.Name);
    Assert.IsTrue(mIndex >= 0, mRouted.Name);
    Assert.AreEqual(mRouted.Path, FCatalog[mIndex].Key, mRouted.Name);
    // Nur einmal im Katalog: als Plugin-Einstellung.
    Assert.AreEqual(mIndex, FCatalog.IndexOfKey(mRouted.Path));
  end;
end;

procedure TAtlasSettingsCatalogTests.EveryEntryHasKnownAreaAndPage;
const
  cIssueAreas: array[0..8] of string = ('editor', 'completion', 'highlighting', 'keys', 'codeActions', 'build', 'debug',
    'snippets', 'bookmarks');
var
  mIndex: Integer;
  mArea: string;
begin
  for mIndex := 0 to FCatalog.Count - 1 do
  begin
    Assert.IsTrue(FCatalog.HasArea(FCatalog[mIndex].Area), FCatalog[mIndex].Key + ': Bereich ' + FCatalog[mIndex].Area);
    if FCatalog[mIndex].Source = asPlugin then
    begin
      Assert.AreNotEqual('', FCatalog[mIndex].Page, FCatalog[mIndex].Key + ' ohne Seite');
    end;
  end;
  // Die Bereiche aus dem Issue.
  for mArea in cIssueAreas do
  begin
    Assert.IsTrue(FCatalog.HasArea(mArea), mArea);
  end;
  Assert.AreEqual('Lesezeichen', FCatalog.AreaCaption('bookmarks', False));
  Assert.AreEqual('Bookmarks', FCatalog.AreaCaption('bookmarks', True));
end;

procedure TAtlasSettingsCatalogTests.KeysAreUniqueAndNoProjectPaths;
var
  mIndex, mOther: Integer;
begin
  for mIndex := 0 to FCatalog.Count - 1 do
  begin
    mOther := FCatalog.IndexOfKey(FCatalog[mIndex].Key);
    Assert.AreEqual(mIndex, mOther, 'doppelter Schlüssel ' + FCatalog[mIndex].Key);
    // Nur Schlüssel mit x-scope "both" (rules) sind zugleich Projektpfad; atlas.json überdeckt sie.
    if FCatalog[mIndex].ProjectPath <> FCatalog[mIndex].Key then
    begin
      Assert.IsFalse(FCatalog.IsProjectPath(FCatalog[mIndex].Key), 'Projektschlüssel im Katalog: ' + FCatalog[mIndex].Key);
    end;
  end;
end;

procedure TAtlasSettingsCatalogTests.GlobalKeysComeFromSchema;
var
  mIndex: Integer;
begin
  mIndex := FCatalog.IndexOfKey('completion.postfixTemplates');
  Assert.IsTrue(mIndex >= 0);
  Assert.AreEqual('snippets', FCatalog[mIndex].Area, 'x-area des Glieds');
  Assert.AreEqual<TAtlasSettingSource>(asGlobal, FCatalog[mIndex].Source);
  mIndex := FCatalog.IndexOfKey('highlight.blockPairs');
  Assert.AreEqual('highlighting', FCatalog[mIndex].Area, 'x-area des Objekts');
  mIndex := FCatalog.IndexOfKey('logLevel');
  Assert.AreEqual('general', FCatalog[mIndex].Area);
  Assert.IsTrue(FCatalog[FCatalog.IndexOfKey('delphiVersion')].Machine);
  Assert.IsFalse(FCatalog[FCatalog.IndexOfKey('delphiVersion')].Transferable);
  Assert.IsTrue(FCatalog[FCatalog.IndexOfKey('logFile')].IsPath);
  // Projektwerte (atlas.json) gehören nicht dazu, auch nicht die Projekt-Glieder gemischter Objekte.
  Assert.AreEqual(-1, FCatalog.IndexOfKey('format.indentSize'));
  // x-scope "both": der globale Wert gehört dazu, atlas.json überdeckt ihn.
  mIndex := FCatalog.IndexOfKey('rules');
  Assert.IsTrue(mIndex >= 0, 'rules global (both)');
  Assert.AreEqual('rules', FCatalog[mIndex].Area);
  Assert.AreEqual('rules', FCatalog[mIndex].ProjectPath);
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
  mCatalog: TAtlasSettingsCatalog;
  mMigrated: Boolean;
  mIndex: Integer;
begin
  mIndex := FCatalog.Resolve('highlight.pairColors', mMigrated);
  Assert.AreEqual('PairColors', FCatalog[mIndex].Name);
  Assert.IsFalse(mMigrated);
  mIndex := FCatalog.Resolve('PairColors', mMigrated);
  Assert.AreEqual('highlight.pairColors', FCatalog[mIndex].Key);
  Assert.IsTrue(mMigrated, 'Registry-Name');
  Assert.AreEqual(-1, FCatalog.Resolve('gibt.es.nicht', mMigrated));
  Assert.IsFalse(mMigrated);
  mCatalog := TAtlasSettingsCatalog.Create(cTestPlugin, cTestServer);
  try
    Assert.AreEqual(2, mCatalog.Version);
    mIndex := mCatalog.Resolve('editor.pairColors', mMigrated);
    Assert.AreEqual('highlight.pairColors', mCatalog[mIndex].Key);
    Assert.IsTrue(mMigrated, 'x-formerKeys');
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsCatalogTests.ChecksValuesAgainstSchema;
var
  mIssues: TArray<string>;
begin
  Assert.IsTrue(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('settings.exportSecrets')], '"placeholder"', mIssues));
  Assert.IsFalse(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('settings.exportSecrets')], '"alles"', mIssues));
  Assert.IsFalse(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('highlight.pairColors')], '"ja"', mIssues));
  Assert.IsTrue(Length(mIssues) > 0);
  Assert.IsFalse(FCatalog.ValidValue(FCatalog[FCatalog.IndexOfKey('highlight.pairColors')], 'kaputt', mIssues));
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
  mResult_: TAtlasExportResult;
  mSource: TAtlasSettingsFile;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"logLevel": "debug"}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  mSource := TAtlasSettingsTransfer.ParseFile(mResult_.Text);
  Assert.IsTrue(mSource.Valid, mSource.Error);
  Assert.AreEqual(3, Integer(mResult_.Count));
  Assert.AreEqual(3, Integer(Length(mSource.Keys)));
  Assert.Contains(mResult_.Text, '"highlight.pairColors": false');
  Assert.Contains(mResult_.Text, '"completion.visibleRows": 12');
  Assert.Contains(mResult_.Text, '"logLevel": "debug"');
  // Kopf: Format, Schema- und Atlas-Version.
  Assert.AreEqual(1, mSource.FormatVersion);
  Assert.AreEqual(FCatalog.Version, mSource.SchemaVersion);
  Assert.AreNotEqual('', mSource.AtlasVersion);
  Assert.AreEqual(Integer(Length(FCatalog.AreaIds)), Integer(Length(mSource.Areas)));
  // Ohne Änderungen: leere Liste.
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.AreEqual(0, Integer(mResult_.Count));
  Assert.IsTrue(TAtlasSettingsTransfer.ParseFile(mResult_.Text).Valid);
end;

procedure TAtlasSettingsTransferTests.ExportByArea;
var
  S: TAtlasPluginSettings;
  mResult_: TAtlasExportResult;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  S.BookmarksNamed := False;
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''),
    TAtlasExportOptions.Create(['highlighting', 'bookmarks'], smOmit), Macros());
  Assert.AreEqual(2, Integer(mResult_.Count));
  Assert.Contains(mResult_.Text, 'highlight.pairColors');
  Assert.Contains(mResult_.Text, 'bookmarks.named');
  Assert.DoesNotContain(mResult_.Text, 'completion.visibleRows');
  Assert.Contains(mResult_.Text, '"areas": ["highlighting", "bookmarks"]');
end;

procedure TAtlasSettingsTransferTests.ExportSkipsStateAndMachineValues;
var
  S: TAtlasPluginSettings;
  mResult_: TAtlasExportResult;
begin
  S := TAtlasPluginSettings.Defaults;
  S.ListWidth := 500;
  S.ServerPath := 'D:\Atlas\AtlasServer.exe';
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"delphiVersion": "12"}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.AreEqual(0, Integer(mResult_.Count));
  Assert.DoesNotContain(mResult_.Text, 'AtlasServer');
  Assert.DoesNotContain(mResult_.Text, 'delphiVersion');
end;

procedure TAtlasSettingsTransferTests.ExportOmitsOrMasksSecrets;
var
  mCatalog: TAtlasSettingsCatalog;
  S: TAtlasPluginSettings;
  mResult_: TAtlasExportResult;
begin
  // Eintrag mit x-secret.
  mCatalog := TAtlasSettingsCatalog.Create(cTestPlugin, cTestServer);
  try
    S := TAtlasPluginSettings.Defaults;
    // Normalize lässt nur Webadressen zu.
    S.WelcomePageHelpReportUrl := 'https://tracker.example/geheim123';
    mResult_ := TAtlasSettingsTransfer.ExportSettings(mCatalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
      Macros());
    Assert.AreEqual(0, Integer(mResult_.Count));
    Assert.DoesNotContain(mResult_.Text, 'geheim123');
    Assert.AreEqual(1, Integer(Length(mResult_.Omitted)), 'x-secret');
    Assert.AreEqual('tracker.token', mResult_.Omitted[0].Key);
    Assert.AreEqual<TAtlasOmitReason>(orSecret, mResult_.Omitted[0].Reason);
    mResult_ := TAtlasSettingsTransfer.ExportSettings(mCatalog, State(S, ''),
      TAtlasExportOptions.Create(nil, smPlaceholder), Macros());
    Assert.DoesNotContain(mResult_.Text, 'geheim123');
    Assert.Contains(mResult_.Text, '"tracker.token": "<secret>"');
    Assert.AreEqual(1, Integer(Length(mResult_.Placeholders)), 'Platzhalter');
  finally
    mCatalog.Free;
  end;
  // Adresse mit Zugangsdaten im echten Katalog.
  S := TAtlasPluginSettings.Defaults;
  S.WelcomePageHelpReportUrl := 'https://max:pw@tracker.example/new';
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
    Macros());
  Assert.DoesNotContain(mResult_.Text, 'max:pw');
  Assert.AreEqual(1, Integer(Length(mResult_.Omitted)), 'Adresse mit Zugangsdaten');
  // Wahrheitswert unter einem Namen wie „login“ ist kein Geheimnis.
  S := TAtlasPluginSettings.Defaults;
  S.CiLogin := False;
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
    Macros());
  Assert.Contains(mResult_.Text, '"welcomePage.tests.ci.login": false');
end;

procedure TAtlasSettingsTransferTests.ExportReplacesUserFolders;
var
  S: TAtlasPluginSettings;
  mResult_: TAtlasExportResult;
begin
  S := TAtlasPluginSettings.Defaults;
  S.WelcomePageQuickActionsConsole := 'C:\Users\Max\AppData\Local\Microsoft\WindowsApps\wt.exe';
  S.WelcomePageHelpReportFolder := 'C:\Users\max\Documents\Berichte';
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"logFile": "D:\\max\\atlas.log"}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.Contains(mResult_.Text, '"$(LOCALAPPDATA)\\Microsoft\\WindowsApps\\wt.exe"');
  Assert.Contains(mResult_.Text, '"$(USERPROFILE)\\Documents\\Berichte"');
  // Benutzername ohne passenden Ordner: Wert bleibt weg.
  Assert.DoesNotContain(mResult_.Text, 'atlas.log');
  Assert.AreEqual(1, Integer(Length(mResult_.Omitted)));
  Assert.AreEqual('logFile', mResult_.Omitted[0].Key);
  Assert.AreEqual<TAtlasOmitReason>(orUserPath, mResult_.Omitted[0].Reason);
  // Ein Ordner, der nur mit dem Benutzerordner beginnt, ist keiner.
  S.WelcomePageHelpReportFolder := 'C:\Users\maxi\Berichte';
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''), TAtlasExportOptions.Create(nil, smOmit),
    Macros());
  Assert.Contains(mResult_.Text, 'C:\\Users\\maxi\\Berichte');
end;

procedure TAtlasSettingsTransferTests.ImportMergeTakesSelectedValues;
var
  S: TAtlasPluginSettings;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
  mIndex: Integer;
begin
  S := TAtlasPluginSettings.Defaults;
  S.VisibleRows := 7;
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, ''),
    FileOf('"highlight.pairColors": false, "completion.visibleRows": 7, "keys.palette": 0, "logLevel": "debug"'),
      TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.AreEqual<TAtlasImportStatus>(isChange, ItemOf(mPreview, 'highlight.pairColors').Status);
  Assert.AreEqual('true', ItemOf(mPreview, 'highlight.pairColors').CurrentJson);
  Assert.AreEqual('false', ItemOf(mPreview, 'highlight.pairColors').NewJson);
  Assert.AreEqual<TAtlasImportStatus>(isSame, ItemOf(mPreview, 'completion.visibleRows').Status);
  Assert.IsFalse(ItemOf(mPreview, 'completion.visibleRows').Selected);
  Assert.AreEqual<TAtlasImportStatus>(isChange, ItemOf(mPreview, 'logLevel').Status);
  Assert.AreEqual('', ItemOf(mPreview, 'logLevel').CurrentJson, 'nicht gesetzt');
  Assert.AreEqual(3, mPreview.SelectedCount);
  // Nur die gewählten Werte: keys.palette abwählen.
  for mIndex := 0 to High(mPreview.Items) do
  begin
    if mPreview.Items[mIndex].Key = 'keys.palette' then
    begin
      mPreview.Items[mIndex].Selected := False;
    end;
  end;
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(S, '{"language": "de"}'), mPreview);
  Assert.IsFalse(mAfter.Plugin.PairColors);
  Assert.AreEqual(TAtlasPluginSettings.Defaults.PaletteKey, mAfter.Plugin.PaletteKey);
  Assert.Contains(mAfter.GlobalText, '"logLevel": "debug"');
  Assert.Contains(mAfter.GlobalText, '"language": "de"', 'übrige Schlüssel bleiben');
  // Zusammenführen lässt alles andere, wie es ist.
  Assert.AreEqual(7, mAfter.Plugin.VisibleRows);
end;

procedure TAtlasSettingsTransferTests.ImportReplaceResetsWholeArea;
var
  S: TAtlasPluginSettings;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairGuides := False;
  S.PairColors := False;
  S.VisibleRows := 12;
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog,
    State(S, '{"highlight": {"blockPairs": false}, "logLevel": "debug"}'),
    FileOf('"highlight.pairColors": false'), TAtlasImportOptions.Create(imReplace, ['highlighting'], Macros()));
  Assert.AreEqual<TAtlasImportStatus>(isSame, ItemOf(mPreview, 'highlight.pairColors').Status);
  Assert.AreEqual<TAtlasImportStatus>(isReset, ItemOf(mPreview, 'highlight.pairGuides').Status);
  Assert.AreEqual('true', ItemOf(mPreview, 'highlight.pairGuides').NewJson);
  Assert.AreEqual<TAtlasImportStatus>(isReset, ItemOf(mPreview, 'highlight.blockPairs').Status);
  Assert.IsFalse(HasItem(mPreview, 'completion.visibleRows'), 'anderer Bereich');
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog,
    State(S, '{"highlight": {"blockPairs": false}, "logLevel": "debug"}'), mPreview);
  Assert.IsTrue(mAfter.Plugin.PairGuides);
  Assert.IsFalse(mAfter.Plugin.PairColors);
  Assert.DoesNotContain(mAfter.GlobalText, 'blockPairs');
  Assert.Contains(mAfter.GlobalText, '"logLevel": "debug"', 'anderer Bereich bleibt');
  Assert.AreEqual(12, mAfter.Plugin.VisibleRows);
  // Mit Zusammenführen bleibt pairGuides.
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, ''), FileOf('"highlight.pairColors": false'),
    TAtlasImportOptions.Create(imMerge, ['highlighting'], Macros()));
  Assert.IsFalse(HasItem(mPreview, 'highlight.pairGuides'));
end;

procedure TAtlasSettingsTransferTests.ImportReportsAndSkipsUnknownKeys;
var
  mSource: TAtlasSettingsFile;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  mSource := TAtlasSettingsTransfer.ParseFile('{"format":"atlas-settings","formatVersion":1,"schemaVersion":99,' +
    '"settings":{"welcomePage.zukunft": [1, 2], "highlight.pairColors": false}}');
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mSource,
    TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.IsTrue(mPreview.Newer, 'neuere Version');
  Assert.AreEqual<TAtlasImportStatus>(isUnknown, ItemOf(mPreview, 'welcomePage.zukunft').Status);
  Assert.IsFalse(ItemOf(mPreview, 'welcomePage.zukunft').Selected);
  Assert.AreEqual(1, mPreview.CountOf(isUnknown));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.IsFalse(mAfter.Plugin.PairColors, 'der Rest gilt');
  Assert.DoesNotContain(mAfter.GlobalText, 'zukunft');
end;

procedure TAtlasSettingsTransferTests.ImportMigratesOldKeys;
var
  mCatalog: TAtlasSettingsCatalog;
  mSource: TAtlasSettingsFile;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  // Ältere Datei: flache Registry-Namen mit 0/1 (wie TAtlasMemorySettingsStore.ToJson).
  mSource := TAtlasSettingsTransfer.ParseFile('{"PairColors": 0, "VisibleRows": 12, "SettingsExportSecrets": "placeholder"}');
  Assert.IsTrue(mSource.Valid);
  Assert.AreEqual(0, mSource.SchemaVersion);
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mSource,
    TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.IsTrue(ItemOf(mPreview, 'highlight.pairColors').Migrated);
  Assert.AreEqual('PairColors', ItemOf(mPreview, 'highlight.pairColors').SourceKey);
  Assert.AreEqual('false', ItemOf(mPreview, 'highlight.pairColors').NewJson, '0 wird false');
  Assert.AreEqual<TAtlasImportStatus>(isChange, ItemOf(mPreview, 'completion.visibleRows').Status);
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.IsFalse(mAfter.Plugin.PairColors);
  Assert.AreEqual(12, mAfter.Plugin.VisibleRows);
  Assert.AreEqual('placeholder', mAfter.Plugin.SettingsExportSecrets);
  // #770: xmlDocFull (Wahrheitswert bzw. 0/1) wird zur Auswahl xmlDocExpand.
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    FileOf('"hints.xmlDocFull": true'), TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.IsTrue(ItemOf(mPreview, 'hints.xmlDocExpand').Migrated);
  Assert.AreEqual('"expanded"', ItemOf(mPreview, 'hints.xmlDocExpand').NewJson);
  mSource := TAtlasSettingsTransfer.ParseFile('{"XmlDocFull": 0}');
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mSource,
    TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.AreEqual('"collapsed"', ItemOf(mPreview, 'hints.xmlDocExpand').NewJson);
  // Frühere Schlüssel (x-formerKeys).
  mCatalog := TAtlasSettingsCatalog.Create(cTestPlugin, cTestServer);
  try
    mPreview := TAtlasSettingsTransfer.Preview(mCatalog, State(TAtlasPluginSettings.Defaults, ''),
      FileOf('"editor.pairColors": false'), TAtlasImportOptions.Create(imMerge, nil, Macros()));
    Assert.IsTrue(ItemOf(mPreview, 'highlight.pairColors').Migrated);
    Assert.AreEqual<TAtlasImportStatus>(isChange, ItemOf(mPreview, 'highlight.pairColors').Status);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsTransferTests.ImportMigratesProblemsLive;
var
  mSource: TAtlasSettingsFile;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  // problems.live (#909, Wahrheitswert bzw. 0/1) wird zur Auswahl problems.update: an = live, aus = save.
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    FileOf('"problems.live": false'), TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.IsTrue(ItemOf(mPreview, 'problems.update').Migrated);
  Assert.AreEqual('"save"', ItemOf(mPreview, 'problems.update').NewJson);
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.AreEqual('save', mAfter.Plugin.ProblemsUpdate);
  mSource := TAtlasSettingsTransfer.ParseFile('{"ProblemsLive": 1}');
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mSource,
    TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.AreEqual('"live"', ItemOf(mPreview, 'problems.update').NewJson);
end;

procedure TAtlasSettingsTransferTests.ImportRejectsInvalidValuesAndPlaceholders;
var
  mPreview: TAtlasImportPreview;
begin
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    FileOf('"settings.exportSecrets": "alles", "highlight.pairColors": "ja", "welcomePage.help.reportUrl": "<secret>",' +
    '"server.path": "D:\\Atlas"'), TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.AreEqual<TAtlasImportStatus>(isInvalid, ItemOf(mPreview, 'settings.exportSecrets').Status);
  Assert.IsTrue(Length(ItemOf(mPreview, 'settings.exportSecrets').Issues) > 0);
  Assert.AreEqual<TAtlasImportStatus>(isInvalid, ItemOf(mPreview, 'highlight.pairColors').Status);
  Assert.AreEqual<TAtlasImportStatus>(isSecret, ItemOf(mPreview, 'welcomePage.help.reportUrl').Status);
  Assert.AreEqual<TAtlasImportStatus>(isSkipped, ItemOf(mPreview, 'server.path').Status, 'Rechnerwert');
  Assert.AreEqual(0, mPreview.SelectedCount);
end;

procedure TAtlasSettingsTransferTests.ImportExpandsPathMacros;
var
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    FileOf('"welcomePage.quickActions.console": "$(LOCALAPPDATA)\\Microsoft\\WindowsApps\\wt.exe"'),
      TAtlasImportOptions.Create(imMerge, nil, Macros()));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.AreEqual('C:\Users\max\AppData\Local\Microsoft\WindowsApps\wt.exe',
    mAfter.Plugin.WelcomePageQuickActionsConsole);
end;

procedure TAtlasSettingsTransferTests.ProjectValuesStayUntouched;
const
  cProjectText = '{"format": {"indentSize": 4}}';
  cTeamText = '{"version": 1, "ci": {"provider": "jenkins", "url": "https://ci"}}';
var
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
  S: TAtlasPluginSettings;
  mResult_: TAtlasExportResult;
begin
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, '{"language": "de"}'),
    FileOf('"format.indentSize": 2, "completion.interfaceSection": "x", "welcomePage.tests.ci.provider": "jenkins",' +
    '"welcomePage.tests.ci.intervalMinutes": 30'), TAtlasImportOptions.Create(imReplace, nil, Macros(), cProjectText,
      cTeamText));
  // Projektwerte in der Datei werden übersprungen.
  Assert.AreEqual<TAtlasImportStatus>(isSkipped, ItemOf(mPreview, 'format.indentSize').Status);
  Assert.AreEqual<TAtlasImportStatus>(isSkipped, ItemOf(mPreview, 'completion.interfaceSection').Status);
  // Die Vorschau zeigt, was .atlas überdeckt.
  Assert.Contains(ItemOf(mPreview, 'welcomePage.tests.ci.provider').Covered, '.atlas: ci.provider = jenkins');
  Assert.AreEqual('', ItemOf(mPreview, 'welcomePage.tests.ci.intervalMinutes').Covered);
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, '{"language": "de"}'), mPreview);
  Assert.DoesNotContain(mAfter.GlobalText, 'indentSize', 'nicht nach settings.json');
  Assert.DoesNotContain(mAfter.GlobalText, 'interfaceSection');
  // Export: nie Projektwerte (atlas.json-Schlüssel in settings.json werden ignoriert).
  S := TAtlasPluginSettings.Defaults;
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"format": {"useTabs": true}}'),
    TAtlasExportOptions.Create(nil, smOmit), Macros());
  Assert.AreEqual(0, Integer(mResult_.Count));
  // x-scope "both" (rules): der globale Wert wandert mit, die Vorschau nennt den Projektwert, der ihn überdeckt.
  mResult_ := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"rules": {"empty-except": "off"}}'),
    TAtlasExportOptions.Create(['rules'], smOmit), Macros());
  Assert.AreEqual(1, Integer(mResult_.Count));
  Assert.Contains(mResult_.Text, '"empty-except"');
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, ''), TAtlasSettingsTransfer.ParseFile(mResult_.Text),
    TAtlasImportOptions.Create(imMerge, nil, Macros(), '{"rules": {"empty-except": "error"}}', ''));
  Assert.AreEqual<TAtlasImportStatus>(isChange, ItemOf(mPreview, 'rules').Status);
  Assert.Contains(ItemOf(mPreview, 'rules').Covered, 'atlas.json: rules');
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(S, ''), mPreview);
  Assert.Contains(mAfter.GlobalText, '"empty-except"', 'nach settings.json');
end;

procedure TAtlasSettingsTransferTests.BackupRestoresEverything;
var
  S, mChanged: TAtlasPluginSettings;
  mBackup: TAtlasExportResult;
  mSource: TAtlasSettingsFile;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.ListWidth := 500;
  S.ServerPath := 'C:\Users\max\Atlas\AtlasServer.exe';
  S.PairColors := False;
  mBackup := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, '{"logLevel": "debug"}'),
    TAtlasExportOptions.ForBackup, Macros());
  // Sicherung: alles unverändert, auch Zustand, Rechnerwert und Benutzerpfad.
  Assert.Contains(mBackup.Text, '"backup": true');
  Assert.Contains(mBackup.Text, 'C:\\Users\\max\\Atlas');
  mSource := TAtlasSettingsTransfer.ParseFile(mBackup.Text);
  Assert.IsTrue(mSource.Backup);
  mChanged := TAtlasPluginSettings.Defaults;
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(mChanged, ''), mSource,
    TAtlasImportOptions.Create(imReplace, nil, Macros()));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(mChanged, ''), mPreview);
  Assert.AreEqual(500, mAfter.Plugin.ListWidth);
  Assert.AreEqual('C:\Users\max\Atlas\AtlasServer.exe', mAfter.Plugin.ServerPath);
  Assert.IsFalse(mAfter.Plugin.PairColors);
  Assert.Contains(mAfter.GlobalText, '"logLevel": "debug"');
end;

procedure TAtlasSettingsTransferTests.BackupNamesAndCleanup;
var
  mDelete: TArray<string>;
begin
  Assert.AreEqual('atlas-settings-20261016-142503.json',
    TAtlasSettingsTransfer.BackupFileName(EncodeDateTime(2026, 10, 16, 14, 25, 3, 0)));
  mDelete := TAtlasSettingsTransfer.BackupsToDelete(['atlas-settings-20261016-142503.json', 'andere.json',
    'atlas-settings-20250101-000000.json', 'atlas-settings-20260101-000000.json'], 2);
  Assert.AreEqual(1, Integer(Length(mDelete)));
  Assert.AreEqual('atlas-settings-20250101-000000.json', mDelete[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.BackupsToDelete(['atlas-settings-1.json'], 10))));
end;

procedure TAtlasSettingsTransferTests.ResetPerKey;
var
  S: TAtlasPluginSettings;
  mAfter: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  mAfter := TAtlasSettingsTransfer.ResetKeys(FCatalog, State(S, '{"logLevel": "debug", "language": "de"}'),
    ['highlight.pairColors', 'logLevel']);
  Assert.IsTrue(mAfter.Plugin.PairColors);
  Assert.AreEqual(12, mAfter.Plugin.VisibleRows);
  Assert.DoesNotContain(mAfter.GlobalText, 'logLevel');
  Assert.Contains(mAfter.GlobalText, '"language": "de"');
  Assert.IsFalse(TAtlasSettingsTransfer.IsModified(FCatalog, mAfter, FCatalog.IndexOfKey('highlight.pairColors')));
  Assert.IsTrue(TAtlasSettingsTransfer.IsModified(FCatalog, mAfter, FCatalog.IndexOfKey('completion.visibleRows')));
end;

procedure TAtlasSettingsTransferTests.ResetPerAreaAndAll;
var
  S: TAtlasPluginSettings;
  mAfter: TAtlasSettingsState;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.VisibleRows := 12;
  S.ListWidth := 500;
  S.ServerPath := 'D:\Atlas\AtlasServer.exe';
  mAfter := TAtlasSettingsTransfer.ResetAreas(FCatalog, State(S, ''), ['highlighting']);
  Assert.IsTrue(mAfter.Plugin.PairColors);
  Assert.AreEqual(12, mAfter.Plugin.VisibleRows);
  Assert.AreEqual(3, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, State(S, '{"logLevel": "debug"}')))),
    'drei geänderte Werte, Zustand und Rechnerwert zählen nicht');
  mAfter := TAtlasSettingsTransfer.ResetAll(FCatalog, State(S, '{"logLevel": "debug", "delphiVersion": "12"}'));
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, mAfter))));
  Assert.AreEqual(TAtlasPluginSettings.Defaults.VisibleRows, mAfter.Plugin.VisibleRows);
  // Zustand und Rechnerwert bleiben.
  Assert.AreEqual(500, mAfter.Plugin.ListWidth);
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', mAfter.Plugin.ServerPath);
  Assert.Contains(mAfter.GlobalText, 'delphiVersion');
  Assert.DoesNotContain(mAfter.GlobalText, 'logLevel');
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
    TAtlasSettingsTransfer.ParseFile(mExported.Text), TAtlasImportOptions.Create(imMerge, nil, Macros()));
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
    TAtlasSettingsTransfer.ParseFile(mExported.Text), TAtlasImportOptions.Create(imMerge, nil, Macros()));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.AreEqual(cList, mAfter.Plugin.IssuesProjects);
  mAfter := TAtlasSettingsTransfer.ResetAreas(FCatalog, State(mSettings, ''), ['issues']);
  Assert.AreEqual('[]', mAfter.Plugin.IssuesProjects);
end;

procedure TAtlasSettingsTransferTests.WelcomeLayoutsTravel;
const
  cLayoutsJson = '[{"name":"Arbeit","columns":3,"slots":[{"id":"atlas.state","column":0}]}]';
var
  S: TAtlasPluginSettings;
  mExported: TAtlasExportResult;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
  mNames: TArray<string>;
begin
  // #767: Layouts, aktives Layout, Spalten und der Schalter gehören zum Bereich „Willkommensseite“.
  S := TAtlasPluginSettings.Defaults;
  S.WelcomePageCustomLayout := False;
  S.WelcomePageColumns := 3;
  S.WelcomePageLayouts := cLayoutsJson;
  S.WelcomePageActiveLayout := 'Arbeit';
  mExported := TAtlasSettingsTransfer.ExportSettings(FCatalog, State(S, ''),
    TAtlasExportOptions.Create(['welcome'], smOmit), Macros());
  Assert.AreEqual(4, Integer(mExported.Count));
  Assert.Contains(mExported.Text, '"welcomePage.customLayout": false');
  Assert.Contains(mExported.Text, '"welcomePage.columns": 3');
  Assert.Contains(mExported.Text, '"welcomePage.layouts"');
  Assert.Contains(mExported.Text, '"welcomePage.activeLayout": "Arbeit"');
  // Import auf einem frischen Rechner.
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''),
    TAtlasSettingsTransfer.ParseFile(mExported.Text), TAtlasImportOptions.Create(imMerge, nil, Macros()));
  Assert.AreEqual(4, mPreview.SelectedCount);
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.IsFalse(mAfter.Plugin.WelcomePageCustomLayout);
  Assert.AreEqual(3, mAfter.Plugin.WelcomePageColumns);
  Assert.AreEqual(cLayoutsJson, mAfter.Plugin.WelcomePageLayouts);
  Assert.AreEqual('Arbeit', mAfter.Plugin.WelcomePageActiveLayout);
  // Geändert-Markierung und Zurücksetzen.
  mNames := TAtlasSettingsTransfer.ModifiedNames(FCatalog, S);
  Assert.AreEqual(4, Integer(Length(mNames)));
  mAfter := TAtlasSettingsTransfer.ResetAreas(FCatalog, State(S, ''), ['welcome']);
  Assert.IsTrue(mAfter.Plugin.WelcomePageCustomLayout);
  Assert.AreEqual(2, mAfter.Plugin.WelcomePageColumns);
  Assert.AreEqual('', mAfter.Plugin.WelcomePageLayouts);
  Assert.AreEqual('Standard', mAfter.Plugin.WelcomePageActiveLayout);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, mAfter))));
end;

procedure TAtlasSettingsTransferTests.ResetNamesAndModifiedNamesForPage;
var
  S, mAfter: TAtlasPluginSettings;
  mNames: TArray<string>;
begin
  S := TAtlasPluginSettings.Defaults;
  S.PairColors := False;
  S.FixCase := not S.FixCase;
  S.ListWidth := 500;
  mNames := TAtlasSettingsTransfer.ModifiedNames(FCatalog, S);
  Assert.AreEqual(2, Integer(Length(mNames)), 'ListWidth ist Zustand');
  mAfter := TAtlasSettingsTransfer.ResetNames(FCatalog, S, ['PairColors', 'ListWidth']);
  Assert.IsTrue(mAfter.PairColors);
  Assert.AreEqual(500, mAfter.ListWidth, 'Zustand wird nicht zurückgesetzt');
  Assert.AreNotEqual<Boolean>(TAtlasPluginSettings.Defaults.FixCase, mAfter.FixCase);
  Assert.AreEqual(1, Integer(Length(TAtlasSettingsTransfer.ModifiedNames(FCatalog, mAfter))));
end;

procedure TAtlasSettingsTransferTests.BuiltInProfilesAreValid;
var
  mName: string;
  mIssues: TArray<string>;
begin
  Assert.AreEqual(5, Integer(Length(AtlasProfileFiles)));
  for mName in AtlasProfileFiles do
  begin
    Assert.AreNotEqual('', AtlasProfileJson(mName), mName);
    Assert.IsTrue(TAtlasSettingsTransfer.Validate(FCatalog, AtlasProfileJson(mName), mIssues),
      mName + ': ' + string.Join('; ', mIssues));
    Assert.AreNotEqual('', TAtlasSettingsTransfer.ParseFile(AtlasProfileJson(mName)).Name, mName + ' ohne Namen');
  end;
  // Validate findet Fehler.
  Assert.IsFalse(TAtlasSettingsTransfer.Validate(FCatalog, '{"format":"atlas-settings","formatVersion":1,' +
    '"schemaVersion":1,"mode":"alles","areas":["mond"],"settings":{"PairColors":true,"x.y":1,' +
    '"highlight.pairGuides":"ja","completion.listWidth":300}}', mIssues));
  Assert.IsTrue(Length(mIssues) >= 6, string.Join('; ', mIssues));
end;

procedure TAtlasSettingsTransferTests.ProfilesSwitchFeatures;
var
  S: TAtlasPluginSettings;
  mSource: TAtlasSettingsFile;
  mPreview: TAtlasImportPreview;
  mAfter: TAtlasSettingsState;
begin
  // Minimal: Zusatzfunktionen aus, Vervollständigung bleibt.
  mSource := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson('minimal.json'));
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mSource,
    TAtlasImportOptions.Create(TAtlasSettingsTransfer.ModeOf(mSource), nil, Macros()));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(TAtlasPluginSettings.Defaults, ''), mPreview);
  Assert.IsTrue(mAfter.Plugin.Enabled);
  Assert.IsTrue(mAfter.Plugin.SettingsExportImport, 'Knöpfe bleiben');
  Assert.IsFalse(mAfter.Plugin.PairColors);
  Assert.IsFalse(mAfter.Plugin.WelcomePage);
  // Alles an.
  mSource := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson('alles-an.json'));
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, mAfter, mSource,
    TAtlasImportOptions.Create(TAtlasSettingsTransfer.ModeOf(mSource), nil, Macros()));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, mAfter, mPreview);
  Assert.IsTrue(mAfter.Plugin.PairColors);
  Assert.IsTrue(mAfter.Plugin.BuildOnOpen);
  Assert.IsTrue(mAfter.Plugin.InlayHints);
  // Atlas-Standard ersetzt alles durch die Vorgaben.
  S := mAfter.Plugin;
  S.VisibleRows := 12;
  mSource := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson('atlas-standard.json'));
  Assert.AreEqual<TAtlasImportMode>(imReplace, TAtlasSettingsTransfer.ModeOf(mSource));
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, '{"logLevel": "debug"}'), mSource,
    TAtlasImportOptions.Create(imReplace, nil, Macros()));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(S, '{"logLevel": "debug"}'), mPreview);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, mAfter))));
  // Nur Code Insight (#1454): alle Module aus, der Kern wie Atlas-Standard.
  S := mAfter.Plugin;
  S.PairColors := False;
  mSource := TAtlasSettingsTransfer.ParseFile(AtlasProfileJson('nur-code-insight.json'));
  Assert.AreEqual<TAtlasImportMode>(imReplace, TAtlasSettingsTransfer.ModeOf(mSource));
  mPreview := TAtlasSettingsTransfer.Preview(FCatalog, State(S, ''), mSource, TAtlasImportOptions.Create(imReplace, nil,
    Macros()));
  mAfter := TAtlasSettingsTransfer.Apply(FCatalog, State(S, ''), mPreview);
  Assert.IsTrue(mAfter.Plugin.Enabled);
  Assert.IsTrue(mAfter.Plugin.PairColors, 'Kern auf Vorgabe');
  Assert.IsFalse(mAfter.Plugin.DebugEnabled);
  Assert.IsFalse(mAfter.Plugin.IssuesEnabled);
  Assert.IsFalse(mAfter.Plugin.AnalysisEnabled);
  Assert.IsFalse(mAfter.Plugin.TestsEnabled);
  Assert.IsFalse(mAfter.Plugin.BuildToolsEnabled);
  Assert.IsFalse(mAfter.Plugin.BookmarksEnabled);
  Assert.IsFalse(mAfter.Plugin.DesignerEnabled);
  Assert.IsFalse(mAfter.Plugin.RuleChecksEnabled);
  Assert.IsFalse(mAfter.Plugin.SearchEnabled);
  Assert.IsFalse(mAfter.Plugin.WelcomePage);
  Assert.IsFalse(mAfter.Plugin.VcsEnabled);
  Assert.IsFalse(mAfter.Plugin.AssistantsEnabled);
  Assert.IsFalse(mAfter.Plugin.HelpEnabled);
  Assert.IsTrue(mAfter.Plugin.DebugInlineValues, 'Einzelschalter auf Vorgabe, nur das Modul ist aus');
  Assert.AreEqual(14, Integer(Length(TAtlasSettingsTransfer.ModifiedKeys(FCatalog, mAfter))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsCatalogTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsTransferTests);

end.
