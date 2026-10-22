unit Atlas.Core.Editor.Elements.Tests;

// Wächtertest der gezeichneten Elemente (#628, #265): Jedes Element, das Atlas
// im Editor zeichnet, liefert einen Schlüssel, der im Einstellungskatalog
// steht, eine Zeichnung ist und sich über den Namen schalten lässt. Ebenso
// kennt jeder Bereich der Willkommensseite seine Einstellung (#767).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDrawnElementsTests = class
  public
    [Test]
    procedure EveryElementHasCatalogKey;
    [Test]
    procedure KeysAreUniqueAndFindable;
    [Test]
    procedure ScopesFitTheElements;
    [Test]
    procedure WelcomeSectionsKnowTheirSetting;
    [Test]
    procedure AnchorIsNormalizedAndShort;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Welcome.Sections;

procedure TAtlasDrawnElementsTests.EveryElementHasCatalogKey;
var
  Catalog, Properties, Entry: TJSONValue;
  Element: TAtlasDrawnElement;
  Key: string;
  Value: Boolean;
  Toggles: TArray<TAtlasQuickToggle>;
  Toggle: TAtlasQuickToggle;
begin
  Catalog := TJSONObject.ParseJSONValue(TAtlasQuickToggles.PluginCatalog);
  try
    Assert.IsTrue(Catalog is TJSONObject);
    Properties := TJSONObject(Catalog).GetValue('properties');
    Assert.IsTrue(Properties is TJSONObject);
    for Element in TAtlasDrawnElements.All do
    begin
      Key := TAtlasDrawnElements.SettingKey(Element);
      Assert.IsTrue(Key <> '', 'Element ohne Schlüssel');
      Entry := TJSONObject(Properties).GetValue(Key);
      Assert.IsTrue(Entry is TJSONObject, 'nicht im Katalog: ' + Key);
      // Auswahl mit "off" (Fehlertext am Zeilenende #509): „Überall“ setzt "off"; „Alles aus“ erfasst sie über
      // die Problem-Markierungen, von denen sie abhängt.
      if TJSONObject(Entry).GetValue<string>('type', '') = 'string' then
      begin
        Assert.IsTrue(Pos('"off"', TJSONObject(Entry).GetValue('enum').ToJSON) > 0, 'Auswahl ohne off: ' + Key);
        Assert.IsTrue(TAtlasHide.IsOn(TAtlasPluginSettings.Defaults, Key), 'standardmäßig aus: ' + Key);
        Continue;
      end;
      Assert.IsTrue(TJSONObject(Entry).GetValue('x-drawing') is TJSONBool, 'ohne x-drawing: ' + Key);
      Assert.IsTrue(TJSONBool(TJSONObject(Entry).GetValue('x-drawing')).AsBoolean, 'keine Zeichnung: ' + Key);
      // Über den Namen schaltbar: „Überall ausblenden“ setzt genau diesen Wert.
      Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, Key, Value), 'keine Einstellung: ' + Key);
    end;
  finally
    Catalog.Free;
  end;
  // Umgekehrt: jede Zeichnung im Katalog ist ein bekanntes Element.
  Toggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, '');
  for Toggle in Toggles do
    if Toggle.Drawing then
      Assert.IsTrue(TAtlasDrawnElements.ForSetting(Toggle.Key, Element), 'Zeichnung ohne Element: ' + Toggle.Key);
end;

procedure TAtlasDrawnElementsTests.KeysAreUniqueAndFindable;
var
  Element, Found: TAtlasDrawnElement;
  Seen: TList<string>;
  Key: string;
begin
  Seen := TList<string>.Create;
  try
    for Element in TAtlasDrawnElements.All do
    begin
      Key := LowerCase(TAtlasDrawnElements.SettingKey(Element));
      Assert.IsFalse(Seen.Contains(Key), 'doppelt: ' + Key);
      Seen.Add(Key);
      Assert.IsTrue(TAtlasDrawnElements.ForSetting(UpperCase(Key), Found));
      Assert.IsTrue(Found = Element, Key);
    end;
  finally
    Seen.Free;
  end;
  Assert.IsFalse(TAtlasDrawnElements.ForSetting('GibtEsNicht', Found));
  // Abnahme: die Blockende-Beschriftung hat den Schlüssel editor.blockEndLabels (Registry BlockEndLabels).
  Assert.AreEqual('BlockEndLabels', TAtlasDrawnElements.SettingKey(TAtlasDrawnElement.BlockEndLabels));
end;

procedure TAtlasDrawnElementsTests.ScopesFitTheElements;
var
  Element: TAtlasDrawnElement;
  Info: TAtlasDrawnElementInfo;
begin
  for Element in TAtlasDrawnElements.All do
  begin
    Info := TAtlasDrawnElements.Info(Element);
    Assert.IsTrue(Info.Element = Element);
    // „Überall“ gibt es immer: es setzt die Einstellung aus.
    Assert.IsTrue(TAtlasHideScope.Everywhere in Info.Scopes, Info.SettingKey);
    Assert.IsFalse(Info.Overlay and Info.Gutter, Info.SettingKey);
  end;
  Info := TAtlasDrawnElements.Info(TAtlasDrawnElement.BlockEndLabels);
  Assert.IsTrue(Info.Overlay);
  Assert.IsTrue(Info.Scopes = [TAtlasHideScope.Here, TAtlasHideScope.InFile, TAtlasHideScope.Everywhere]);
  Info := TAtlasDrawnElements.Info(TAtlasDrawnElement.Problems);
  Assert.IsFalse(Info.Overlay);
  Assert.IsTrue(TAtlasHideScope.Here in Info.Scopes);
  Assert.IsTrue(TAtlasDrawnElements.Info(TAtlasDrawnElement.Notes).Gutter);
  Assert.IsTrue(TAtlasDrawnElements.Info(TAtlasDrawnElement.Bookmarks).Gutter);
  // Spalte der schnellen Lesezeichen (#1104).
  Assert.IsTrue(TAtlasDrawnElements.Info(TAtlasDrawnElement.QuickBookmarks).Gutter);
  Assert.AreEqual('QuickBookmarksGutter', TAtlasDrawnElements.SettingKey(TAtlasDrawnElement.QuickBookmarks));
  Assert.IsFalse(TAtlasHideScope.Here in TAtlasDrawnElements.Info(TAtlasDrawnElement.PairColors).Scopes);
end;

procedure TAtlasDrawnElementsTests.WelcomeSectionsKnowTheirSetting;
var
  Id, Key: string;
  Store: IAtlasMemorySettingsStore;
  Names: TArray<string>;
  Name: string;
  Found: Boolean;
begin
  Store := TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults);
  Names := Store.Names;
  for Id in TAtlasDrawnElements.KnownSections do
  begin
    Key := TAtlasDrawnElements.SectionSetting(Id);
    Assert.IsTrue(Key <> '', Id);
    Found := False;
    for Name in Names do
      Found := Found or SameText(Name, Key);
    Assert.IsTrue(Found, 'keine Einstellung: ' + Key);
  end;
  Assert.AreEqual('WelcomePageStatusTile', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.State));
  Assert.AreEqual('WelcomePageProjectStatus', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.Projects));
  // Meine Issues (#765): „Ausblenden“ am Bereich im Bearbeitungsmodus (#767).
  Assert.AreEqual('WelcomePageIssues', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.Issues));
  Assert.AreEqual('', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.Board), 'kein eigener Schalter');
end;

procedure TAtlasDrawnElementsTests.AnchorIsNormalizedAndShort;
begin
  Assert.AreEqual('if A then B := 1;', TAtlasDrawnElements.Anchor('    if  A then'#9'B := 1;   '));
  Assert.AreEqual(TAtlasDrawnElements.MaxAnchorLength, Integer(Length(TAtlasDrawnElements.Anchor(
    StringOfChar('a', 300)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDrawnElementsTests);

end.
