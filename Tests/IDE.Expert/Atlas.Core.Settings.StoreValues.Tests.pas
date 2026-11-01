unit Atlas.Core.Settings.StoreValues.Tests;

// Werte der Plugin-Einstellungen nach Schlüssel (#1455): Lesen, Schreiben und
// Zurücksetzen über x-key, Wahrheitswerte als 0/1, falsche Art und fremde
// Schlüssel, gespeicherte Schlüssel.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Settings.Catalog;

type
  [TestFixture]
  TSettingsStoreValuesTests = class
  private
    FCatalog: TAtlasSettingsCatalog;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsValuesOfSettings;
    [Test]
    procedure WritesThroughToSettings;
    [Test]
    procedure ResetRestoresDefault;
    [Test]
    procedure WrongKindAndUnknownKeyRaise;
    [Test]
    procedure StoredKeysAreKeysNotNames;
    /// <summary>Listen (x-key mit JSON, z. B. issues.connections) lesen und schreiben sich als Text.</summary>
    [Test]
    procedure JsonKeysAsText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.StoreValues;

function ValuesOf(ACatalog: TAtlasSettingsCatalog; const ASettings: TAtlasPluginSettings;
  out AStore: IAtlasMemorySettingsStore): IAtlasSettingsValues;
begin
  AStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Result := TAtlasSettingsStoreValues.Create(ACatalog, AStore,
    TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults));
end;

procedure TSettingsStoreValuesTests.Setup;
begin
  FCatalog := TAtlasSettingsCatalog.CreateDefault;
end;

procedure TSettingsStoreValuesTests.TearDown;
begin
  FreeAndNil(FCatalog);
end;

procedure TSettingsStoreValuesTests.ReadsValuesOfSettings;
var
  mSettings: TAtlasPluginSettings;
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.IssuesBoardOnlyMine := False;
  mSettings.IssuesBlameMaxRevisions := 77;
  mSettings.IssuesTracker := 'youtrack';
  mValues := ValuesOf(FCatalog, mSettings, mStore);
  Assert.IsFalse(mValues.ReadBoolean('issues.board.onlyMine'));
  Assert.AreEqual(77, mValues.ReadInteger('issues.blameLinks.maxRevisions'));
  Assert.AreEqual('youtrack', mValues.ReadString('issues.tracker'));
  Assert.IsTrue(mValues.Contains('issues.board.onlyMine'));
end;

procedure TSettingsStoreValuesTests.WritesThroughToSettings;
var
  mSettings: TAtlasPluginSettings;
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mValues := ValuesOf(FCatalog, mSettings, mStore);
  mValues.WriteBoolean('issues.board.onlyMine', False);
  mValues.WriteInteger('issues.blameLinks.maxRevisions', 12);
  mValues.WriteString('issues.tracker', 'github');
  Assert.AreEqual(0, mStore.ReadInteger('IssuesBoardOnlyMine', 1));
  mSettings.Load(mStore);
  Assert.IsFalse(mSettings.IssuesBoardOnlyMine);
  Assert.AreEqual(12, mSettings.IssuesBlameMaxRevisions);
  Assert.AreEqual('github', mSettings.IssuesTracker);
end;

procedure TSettingsStoreValuesTests.ResetRestoresDefault;
var
  mSettings: TAtlasPluginSettings;
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.IssuesBoardOnlyMine := not TAtlasPluginSettings.Defaults.IssuesBoardOnlyMine;
  mSettings.IssuesTracker := 'github';
  mValues := ValuesOf(FCatalog, mSettings, mStore);
  mValues.Reset('issues.board.onlyMine');
  mValues.Reset('issues.tracker');
  Assert.AreEqual(TAtlasPluginSettings.Defaults.IssuesBoardOnlyMine, mValues.ReadBoolean('issues.board.onlyMine'));
  Assert.AreEqual(TAtlasPluginSettings.Defaults.IssuesTracker, mValues.ReadString('issues.tracker'));
end;

procedure TSettingsStoreValuesTests.WrongKindAndUnknownKeyRaise;
var
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
begin
  mValues := ValuesOf(FCatalog, TAtlasPluginSettings.Defaults, mStore);
  Assert.WillRaise(
    procedure
    begin
      mValues.ReadInteger('issues.board.onlyMine');
    end, EAtlasSettingsKey);
  Assert.WillRaise(
    procedure
    begin
      mValues.ReadBoolean('gibt.es.nicht');
    end, EAtlasSettingsKey);
  Assert.IsFalse(mValues.Contains('gibt.es.nicht'));
  Assert.AreEqual('', TAtlasSettingsStoreValues.PluginName(FCatalog, 'gibt.es.nicht'));
  Assert.AreEqual('IssuesBoardOnlyMine', TAtlasSettingsStoreValues.PluginName(FCatalog, 'issues.board.onlyMine'));
end;

procedure TSettingsStoreValuesTests.JsonKeysAsText;
var
  mSettings: TAtlasPluginSettings;
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
  mJson: string;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mValues := ValuesOf(FCatalog, mSettings, mStore);
  Assert.AreEqual('[]', mValues.ReadString('issues.connections'));
  mJson := '[{"name":"Firma","provider":"youtrack","url":"https://youtrack.example.com"}]';
  mValues.WriteString('issues.connections', mJson);
  mSettings.Load(mStore);
  Assert.AreEqual(mJson, mSettings.IssuesConnections);
  Assert.WillRaise(
    procedure
    begin
      mValues.ReadInteger('issues.connections');
    end, EAtlasSettingsKey);
end;

procedure TSettingsStoreValuesTests.StoredKeysAreKeysNotNames;
var
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
  mKeys: TArray<string>;
  mKey: string;
  mFound: Boolean;
begin
  mValues := ValuesOf(FCatalog, TAtlasPluginSettings.Defaults, mStore);
  mKeys := mValues.StoredKeys;
  mFound := False;
  for mKey in mKeys do
  begin
    Assert.AreNotEqual('IssuesBoardOnlyMine', mKey);
    if mKey = 'issues.board.onlyMine' then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, 'issues.board.onlyMine fehlt');
end;

initialization
  TDUnitX.RegisterTestFixture(TSettingsStoreValuesTests);

end.
