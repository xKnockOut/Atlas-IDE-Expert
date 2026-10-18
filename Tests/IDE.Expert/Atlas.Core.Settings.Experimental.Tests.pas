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
  PluginSchema =
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
  ServerSchema =
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
  Catalog: TAtlasSettingsCatalog;
  Keys: TArray<string>;
begin
  Catalog := TAtlasSettingsCatalog.Create(PluginSchema, ServerSchema);
  try
    Assert.IsTrue(TAtlasExperimental.IsExperimental(Catalog, 'highlight.pairGuides'));
    Assert.IsTrue(TAtlasExperimental.IsExperimental(Catalog, 'PairGuides'), 'auch über den Plugin-Namen');
    Assert.IsTrue(TAtlasExperimental.IsExperimental(Catalog, 'refactoring.liveRename'));
    Assert.IsFalse(TAtlasExperimental.IsExperimental(Catalog, 'refactoring.preview'));
    Assert.IsFalse(TAtlasExperimental.IsExperimental(Catalog, 'experimental.enabled'));
    Assert.IsFalse(TAtlasExperimental.IsExperimental(Catalog, 'unbekannt'));
    Keys := TAtlasExperimental.Keys(Catalog);
    Assert.AreEqual(3, Integer(Length(Keys)));
    Assert.AreEqual('highlight.pairGuides', Keys[0]);
    Assert.AreEqual('completion.rows', Keys[1]);
    Assert.AreEqual('refactoring.liveRename', Keys[2]);
    Assert.AreEqual(2, Integer(Length(TAtlasExperimental.PluginNames(Catalog))), 'nur Plugin-Einstellungen');
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.MasterSwitchOffUsesDefaults;
var
  Catalog: TAtlasSettingsCatalog;
  Stored, Effective: TAtlasPluginSettings;
  None: TArray<TAtlasCatalogEntry>;
begin
  Catalog := TAtlasSettingsCatalog.Create(PluginSchema, ServerSchema);
  try
    // Hauptschalter aus: experimentelle Werte auf die Vorgabe, auch wenn ihr Schalter an ist.
    Stored := Settings(False);
    Effective := TAtlasExperimental.Apply(Stored, Catalog);
    Assert.IsFalse(Effective.PairGuides, 'Schalter an, aber ohne Hauptschalter wirkungslos');
    Assert.AreEqual(9, Effective.VisibleRows, 'Zahl auf die Vorgabe');
    Assert.IsFalse(Effective.PairColors, 'nicht experimentell: unverändert');
    // Die gespeicherten Werte bleiben (Apply liefert eine Kopie).
    Assert.IsTrue(Stored.PairGuides);
    Assert.AreEqual(12, Stored.VisibleRows);
    // Hauptschalter an: es gelten die Einzelschalter.
    Effective := TAtlasExperimental.Apply(Settings(True), Catalog);
    Assert.IsTrue(Effective.PairGuides);
    Assert.AreEqual(12, Effective.VisibleRows);
    // Ohne experimentelle Einträge ändert sich nichts.
    None := nil;
    Effective := TAtlasExperimental.Apply(Settings(False), None);
    Assert.IsTrue(Effective.PairGuides);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.ActiveNamesOnlyWorkingSwitches;
var
  Catalog: TAtlasSettingsCatalog;
  Active: TArray<string>;
  Current: TAtlasPluginSettings;
begin
  Catalog := TAtlasSettingsCatalog.Create(PluginSchema, ServerSchema);
  try
    Assert.AreEqual(0, Integer(Length(TAtlasExperimental.Active(Settings(False),
      '{"refactoring":{"liveRename":true}}', Catalog))), 'ohne Hauptschalter wirkt nichts');
    Active := TAtlasExperimental.Active(Settings(True), '{"refactoring":{"liveRename":true}}', Catalog);
    Assert.AreEqual(3, Integer(Length(Active)));
    Assert.AreEqual('highlight.pairGuides', Active[0]);
    Assert.AreEqual('completion.rows', Active[1]);
    Assert.AreEqual('refactoring.liveRename', Active[2]);
    // Auf der Vorgabe oder nicht gesetzt: nicht wirksam.
    Current := TAtlasPluginSettings.Defaults;
    Current.ExperimentalEnabled := True;
    Current.VisibleRows := 9;
    Current.PairGuides := False;
    Assert.AreEqual(0, Integer(Length(TAtlasExperimental.Active(Current, '{"refactoring":{"liveRename":false}}',
      Catalog))));
    Assert.AreEqual(0, Integer(Length(TAtlasExperimental.Active(Current, 'kein JSON', Catalog))));
    Assert.AreEqual('Experimentell an: a, b', TAtlasExperimental.Summary(['a', 'b'], False));
    Assert.AreEqual('Experimental on: a', TAtlasExperimental.Summary(['a'], True));
    Assert.AreEqual('', TAtlasExperimental.Summary(nil, False));
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.RealCatalogHasMasterSwitch;
var
  Catalog: TAtlasSettingsCatalog;
  Index: Integer;
begin
  Assert.IsFalse(TAtlasPluginSettings.Defaults.ExperimentalEnabled, 'Vorgabe aus');
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    Index := Catalog.IndexOfKey(TAtlasExperimental.MasterKey);
    Assert.IsTrue(Index >= 0, 'experimental.enabled im Katalog');
    Assert.AreEqual(TAtlasExperimental.MasterName, Catalog[Index].Name);
    Assert.AreEqual('false', Catalog[Index].DefaultJson);
    Assert.IsFalse(Catalog[Index].Experimental, 'der Hauptschalter ist selbst nicht experimentell');
    // Jede experimentelle Einstellung hat aus als Vorgabe (wie der Wächter in Update-ConfigDoc.ps1).
    for Index := 0 to Catalog.Count - 1 do
      if Catalog[Index].Experimental and (Catalog[Index].Kind = akBoolean) then
        Assert.AreEqual('false', Catalog[Index].DefaultJson, Catalog[Index].Key);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasExperimentalTests.QuickTogglesCarryMark;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Toggle: TAtlasQuickToggle;
begin
  Toggles := TAtlasQuickToggles.Build(PluginSchema, ServerSchema);
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'PairGuides', Toggle));
  Assert.IsTrue(Toggle.Experimental);
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, 'PairColors', Toggle));
  Assert.IsFalse(Toggle.Experimental);
  // Eintrag für den Hauptschalter im echten Katalog.
  Toggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, AtlasSchemaJson);
  Assert.IsTrue(TAtlasQuickToggles.Find(Toggles, TAtlasExperimental.MasterName, Toggle));
  Assert.AreEqual('Allgemein', Toggle.Page);
  Assert.IsFalse(Toggle.Experimental);
end;

procedure TAtlasExperimentalTests.ProfilesKeepExperimentalApart;
var
  Catalog: TAtlasSettingsCatalog;
  AllOn, AllOnExperimental: TJSONObject;
  Values: TJSONObject;
  Key: string;
  Keys: TArray<string>;
  Value: TJSONValue;
begin
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  AllOn := TJSONObject.ParseJSONValue(AtlasProfileJson('alles-an.json')) as TJSONObject;
  AllOnExperimental := TJSONObject.ParseJSONValue(AtlasProfileJson('alles-an-experimentell.json')) as TJSONObject;
  try
    Assert.IsNotNull(AllOn);
    Assert.IsNotNull(AllOnExperimental, 'Profil „Alles an, auch experimentell“ ist eingebaut');
    Keys := TAtlasExperimental.Keys(Catalog);
    Keys := Keys + [TAtlasExperimental.MasterKey];
    // „Alles an“ schaltet weder den Hauptschalter noch eine experimentelle Funktion ein.
    Values := AllOn.GetValue('settings') as TJSONObject;
    for Key in Keys do
    begin
      Value := Values.GetValue(Key);
      Assert.IsFalse((Value is TJSONBool) and TJSONBool(Value).AsBoolean, Key);
    end;
    // „Alles an, auch experimentell“ schaltet alle ein.
    Values := AllOnExperimental.GetValue('settings') as TJSONObject;
    for Key in Keys do
    begin
      Value := Values.GetValue(Key);
      Assert.IsTrue((Value is TJSONBool) and TJSONBool(Value).AsBoolean, Key);
    end;
  finally
    AllOnExperimental.Free;
    AllOn.Free;
    Catalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExperimentalTests);

end.
