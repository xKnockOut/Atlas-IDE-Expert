unit Atlas.Core.Settings.Experimental.Tests;

// Experimentelle Funktionen (#834): Kennzeichen aus beiden Katalogen,
// Hauptschalter in den wirksamen Werten (gespeicherte Werte bleiben),
// wirksame Schalter für Statusfeld und Fehlerbericht, Schnellschalter und die
// eingebauten Profile „Alles an“ und „Alles an, auch experimentell“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasExperimentalTests = class
  public
    [Test]
    procedure CatalogMarksExperimentalEntries;
    [Test]
    procedure MasterSwitchOffUsesDefaults;
    [Test]
    procedure ActiveNamesOnlyWorkingSwitches;
    [Test]
    procedure RealCatalogHasMasterSwitch;
    [Test]
    procedure QuickTogglesCarryMark;
    [Test]
    procedure ProfilesKeepExperimentalApart;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Settings.ProfileData,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Experimental;

const
  cPluginSchema =
    '{"x-areas":{"editor":{"caption":"Editor"}},"properties":{' +
    '"PairGuides":{"type":"boolean","default":false,"x-key":"highlight.pairGuides","x-area":"editor",' +
      '"x-page":"Editor","x-quickToggle":true,"x-experimental":true,"x-caption":"Blocklinien"},' +
    '"VisibleRows":{"type":"integer","default":9,"x-key":"completion.rows","x-area":"editor","x-page":"Editor",' +
      '"x-experimental":true},' +
    '"PairColors":{"type":"boolean","default":true,"x-key":"highlight.pairColors","x-area":"editor",' +
      '"x-page":"Editor","x-quickToggle":true},' +
    '"ExperimentalEnabled":{"type":"boolean","default":false,"x-key":"experimental.enabled","x-area":"editor",' +
      '"x-page":"Editor","x-quickToggle":true}' +
    '}}';
  cServerSchema =
    '{"properties":{' +
    '"refactoring":{"type":"object","x-scope":"global","x-area":"editor","x-page":"Editor","properties":{' +
      '"liveRename":{"type":"boolean","default":false,"x-experimental":true},' +
      '"preview":{"type":"boolean","default":true}}}' +
    '}}';

function Settings(AMaster: Boolean): TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.ExperimentalEnabled := AMaster;
  Result.PairGuides := True;
  Result.VisibleRows := 12;
  Result.PairColors := False;
end;

procedure TAtlasExperimentalTests.CatalogMarksExperimentalEntries;
var
  mCatalog: TAtlasSettingsCatalog;
  mKeys: TArray<string>;
begin
  mCatalog := TAtlasSettingsCatalog.Create(cPluginSchema, cServerSchema);
  try
    Assert.IsTrue(TAtlasExperimental.IsExperimental(mCatalog, 'highlight.pairGuides'));
    Assert.IsTrue(TAtlasExperimental.IsExperimental(mCatalog, 'PairGuides'), 'auch über den Plugin-Namen');
    Assert.IsTrue(TAtlasExperimental.IsExperimental(mCatalog, 'refactoring.liveRename'));
    Assert.IsFalse(TAtlasExperimental.IsExperimental(mCatalog, 'refactoring.preview'));
    Assert.IsFalse(TAtlasExperimental.IsExperimental(mCatalog, 'experimental.enabled'));
    Assert.IsFalse(TAtlasExperimental.IsExperimental(mCatalog, 'unbekannt'));
    mKeys := TAtlasExperimental.Keys(mCatalog);
    Assert.AreEqual(3, Integer(Length(mKeys)));
    Assert.AreEqual('highlight.pairGuides', mKeys[0]);
    Assert.AreEqual('completion.rows', mKeys[1]);
    Assert.AreEqual('refactoring.liveRename', mKeys[2]);
    Assert.AreEqual(2, Integer(Length(TAtlasExperimental.PluginNames(mCatalog))), 'nur Plugin-Einstellungen');
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.MasterSwitchOffUsesDefaults;
var
  mCatalog: TAtlasSettingsCatalog;
  mStored, mEffective: TAtlasPluginSettings;
  mNone: TArray<TAtlasCatalogEntry>;
begin
  mCatalog := TAtlasSettingsCatalog.Create(cPluginSchema, cServerSchema);
  try
    // Hauptschalter aus: experimentelle Werte auf die Vorgabe, auch wenn ihr Schalter an ist.
    mStored := Settings(False);
    mEffective := TAtlasExperimental.Apply(mStored, mCatalog);
    Assert.IsFalse(mEffective.PairGuides, 'Schalter an, aber ohne Hauptschalter wirkungslos');
    Assert.AreEqual(9, mEffective.VisibleRows, 'Zahl auf die Vorgabe');
    Assert.IsFalse(mEffective.PairColors, 'nicht experimentell: unverändert');
    // Die gespeicherten Werte bleiben (Apply liefert eine Kopie).
    Assert.IsTrue(mStored.PairGuides);
    Assert.AreEqual(12, mStored.VisibleRows);
    // Hauptschalter an: es gelten die Einzelschalter.
    mEffective := TAtlasExperimental.Apply(Settings(True), mCatalog);
    Assert.IsTrue(mEffective.PairGuides);
    Assert.AreEqual(12, mEffective.VisibleRows);
    // Ohne experimentelle Einträge ändert sich nichts.
    mNone := nil;
    mEffective := TAtlasExperimental.Apply(Settings(False), mNone);
    Assert.IsTrue(mEffective.PairGuides);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.ActiveNamesOnlyWorkingSwitches;
var
  mCatalog: TAtlasSettingsCatalog;
  mActive: TArray<string>;
  mCurrent: TAtlasPluginSettings;
begin
  mCatalog := TAtlasSettingsCatalog.Create(cPluginSchema, cServerSchema);
  try
    Assert.AreEqual(0, Integer(Length(TAtlasExperimental.Active(Settings(False),
      '{"refactoring":{"liveRename":true}}', mCatalog))), 'ohne Hauptschalter wirkt nichts');
    mActive := TAtlasExperimental.Active(Settings(True), '{"refactoring":{"liveRename":true}}', mCatalog);
    Assert.AreEqual(3, Integer(Length(mActive)));
    Assert.AreEqual('highlight.pairGuides', mActive[0]);
    Assert.AreEqual('completion.rows', mActive[1]);
    Assert.AreEqual('refactoring.liveRename', mActive[2]);
    // Auf der Vorgabe oder nicht gesetzt: nicht wirksam.
    mCurrent := TAtlasPluginSettings.Defaults;
    mCurrent.ExperimentalEnabled := True;
    mCurrent.VisibleRows := 9;
    mCurrent.PairGuides := False;
    Assert.AreEqual(0, Integer(Length(TAtlasExperimental.Active(mCurrent, '{"refactoring":{"liveRename":false}}',
      mCatalog))));
    Assert.AreEqual(0, Integer(Length(TAtlasExperimental.Active(mCurrent, 'kein JSON', mCatalog))));
    Assert.AreEqual('Experimentell an: a, b', TAtlasExperimental.Summary(['a', 'b'], False));
    Assert.AreEqual('Experimental on: a', TAtlasExperimental.Summary(['a'], True));
    Assert.AreEqual('', TAtlasExperimental.Summary(nil, False));
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.RealCatalogHasMasterSwitch;
var
  mCatalog: TAtlasSettingsCatalog;
  mIndex: Integer;
begin
  Assert.IsFalse(TAtlasPluginSettings.Defaults.ExperimentalEnabled, 'Vorgabe aus');
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    mIndex := mCatalog.IndexOfKey(TAtlasExperimental.cMasterKey);
    Assert.IsTrue(mIndex >= 0, 'experimental.enabled im Katalog');
    Assert.AreEqual(TAtlasExperimental.cMasterName, mCatalog[mIndex].Name);
    Assert.AreEqual('false', mCatalog[mIndex].DefaultJson);
    Assert.IsFalse(mCatalog[mIndex].Experimental, 'der Hauptschalter ist selbst nicht experimentell');
    // Jede experimentelle Einstellung hat aus als Vorgabe (wie der Wächter in Update-ConfigDoc.ps1).
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if mCatalog[mIndex].Experimental and (mCatalog[mIndex].Kind = akBoolean) then
      begin
        Assert.AreEqual('false', mCatalog[mIndex].DefaultJson, mCatalog[mIndex].Key);
      end;
    end;
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.QuickTogglesCarryMark;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mToggle: TAtlasQuickToggle;
begin
  mToggles := TAtlasQuickToggles.Build(cPluginSchema, cServerSchema);
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'PairGuides', mToggle));
  Assert.IsTrue(mToggle.Experimental);
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, 'PairColors', mToggle));
  Assert.IsFalse(mToggle.Experimental);
  // Eintrag für den Hauptschalter im echten Katalog.
  mToggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, AtlasSchemaJson);
  Assert.IsTrue(TAtlasQuickToggles.Find(mToggles, TAtlasExperimental.cMasterName, mToggle));
  Assert.AreEqual('Allgemein', mToggle.Page);
  Assert.IsFalse(mToggle.Experimental);
end;

procedure TAtlasExperimentalTests.ProfilesKeepExperimentalApart;
var
  mCatalog: TAtlasSettingsCatalog;
  mAllOn, mAllOnExperimental: TJSONObject;
  mValues: TJSONObject;
  mKey: string;
  mKeys: TArray<string>;
  mValue: TJSONValue;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  mAllOn := TJSONObject.ParseJSONValue(AtlasProfileJson('alles-an.json')) as TJSONObject;
  mAllOnExperimental := TJSONObject.ParseJSONValue(AtlasProfileJson('alles-an-experimentell.json')) as TJSONObject;
  try
    Assert.IsNotNull(mAllOn);
    Assert.IsNotNull(mAllOnExperimental, 'Profil „Alles an, auch experimentell“ ist eingebaut');
    mKeys := TAtlasExperimental.Keys(mCatalog);
    mKeys := mKeys + [TAtlasExperimental.cMasterKey];
    // „Alles an“ schaltet weder den Hauptschalter noch eine experimentelle Funktion ein.
    mValues := mAllOn.GetValue('settings') as TJSONObject;
    for mKey in mKeys do
    begin
      mValue := mValues.GetValue(mKey);
      Assert.IsFalse((mValue is TJSONBool) and TJSONBool(mValue).AsBoolean, mKey);
    end;
    // „Alles an, auch experimentell“ schaltet alle ein; Auswahlwerte (editor.smartPaste) mit einem Wert außer „off“.
    mValues := mAllOnExperimental.GetValue('settings') as TJSONObject;
    for mKey in mKeys do
    begin
      mValue := mValues.GetValue(mKey);
      Assert.IsNotNull(mValue, mKey);
      if mValue is TJSONBool then
      begin
        Assert.IsTrue(TJSONBool(mValue).AsBoolean, mKey);
      end
      else
      begin
        Assert.AreNotEqual('off', mValue.Value, mKey);
      end;
    end;
  finally
    mAllOnExperimental.Free;
    mAllOn.Free;
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExperimentalTests);

end.
