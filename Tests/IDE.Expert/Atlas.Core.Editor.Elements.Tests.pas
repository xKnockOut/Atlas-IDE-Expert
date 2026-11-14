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
  mCatalog, mProperties, mEntry: TJSONValue;
  mElement: TAtlasDrawnElement;
  mKey: string;
  mValue: Boolean;
  mToggles: TArray<TAtlasQuickToggle>;
  mToggle: TAtlasQuickToggle;
begin
  mCatalog := TJSONObject.ParseJSONValue(TAtlasQuickToggles.PluginCatalog);
  try
    Assert.IsTrue(mCatalog is TJSONObject);
    mProperties := TJSONObject(mCatalog).GetValue('properties');
    Assert.IsTrue(mProperties is TJSONObject);
    for mElement in TAtlasDrawnElements.All do
    begin
      mKey := TAtlasDrawnElements.SettingKey(mElement);
      Assert.AreNotEqual('', mKey, 'Element ohne Schlüssel');
      mEntry := TJSONObject(mProperties).GetValue(mKey);
      Assert.IsTrue(mEntry is TJSONObject, 'nicht im Katalog: ' + mKey);
      // Auswahl mit "off" (Fehlertext am Zeilenende #509): „Überall“ setzt "off"; „Alles aus“ erfasst sie über
      // die Problem-Markierungen, von denen sie abhängt.
      if TJSONObject(mEntry).GetValue<string>('type', '') = 'string' then
      begin
        Assert.IsTrue(Pos('"off"', TJSONObject(mEntry).GetValue('enum').ToJSON) > 0, 'Auswahl ohne off: ' + mKey);
        Assert.IsTrue(TAtlasHide.IsOn(TAtlasPluginSettings.Defaults, mKey), 'standardmäßig aus: ' + mKey);
        Continue;
      end;
      Assert.IsTrue(TJSONObject(mEntry).GetValue('x-drawing') is TJSONBool, 'ohne x-drawing: ' + mKey);
      Assert.IsTrue(TJSONBool(TJSONObject(mEntry).GetValue('x-drawing')).AsBoolean, 'keine Zeichnung: ' + mKey);
      // Über den Namen schaltbar: „Überall ausblenden“ setzt genau diesen Wert.
      Assert.IsTrue(TAtlasQuickToggles.GetFlag(TAtlasPluginSettings.Defaults, mKey, mValue), 'keine Einstellung: ' + mKey);
    end;
  finally
    mCatalog.Free;
  end;
  // Umgekehrt: jede Zeichnung im Katalog ist ein bekanntes Element.
  mToggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, '');
  for mToggle in mToggles do
  begin
    if mToggle.Drawing then
    begin
      Assert.IsTrue(TAtlasDrawnElements.ForSetting(mToggle.Key, mElement), 'Zeichnung ohne Element: ' + mToggle.Key);
    end;
  end;
end;

procedure TAtlasDrawnElementsTests.KeysAreUniqueAndFindable;
var
  mElement, mFound: TAtlasDrawnElement;
  mSeen: TList<string>;
  mKey: string;
begin
  mSeen := TList<string>.Create;
  try
    for mElement in TAtlasDrawnElements.All do
    begin
      mKey := LowerCase(TAtlasDrawnElements.SettingKey(mElement));
      Assert.IsFalse(mSeen.Contains(mKey), 'doppelt: ' + mKey);
      mSeen.Add(mKey);
      Assert.IsTrue(TAtlasDrawnElements.ForSetting(UpperCase(mKey), mFound));
      Assert.AreEqual<TAtlasDrawnElement>(mElement, mFound, mKey);
    end;
  finally
    mSeen.Free;
  end;
  Assert.IsFalse(TAtlasDrawnElements.ForSetting('GibtEsNicht', mFound));
  // Abnahme: die Blockende-Beschriftung hat den Schlüssel editor.blockEndLabels (Registry BlockEndLabels).
  Assert.AreEqual('BlockEndLabels', TAtlasDrawnElements.SettingKey(TAtlasDrawnElement.BlockEndLabels));
end;

procedure TAtlasDrawnElementsTests.ScopesFitTheElements;
var
  mElement: TAtlasDrawnElement;
  mInfo: TAtlasDrawnElementInfo;
begin
  for mElement in TAtlasDrawnElements.All do
  begin
    mInfo := TAtlasDrawnElements.Info(mElement);
    Assert.AreEqual<TAtlasDrawnElement>(mElement, mInfo.Element);
    // „Überall“ gibt es immer: es setzt die Einstellung aus.
    Assert.IsTrue(TAtlasHideScope.Everywhere in mInfo.Scopes, mInfo.SettingKey);
    Assert.IsFalse(mInfo.Overlay and mInfo.Gutter, mInfo.SettingKey);
  end;
  mInfo := TAtlasDrawnElements.Info(TAtlasDrawnElement.BlockEndLabels);
  Assert.IsTrue(mInfo.Overlay);
  Assert.AreEqual<TAtlasHideScopes>([TAtlasHideScope.Here, TAtlasHideScope.InFile, TAtlasHideScope.Everywhere],
    mInfo.Scopes);
  mInfo := TAtlasDrawnElements.Info(TAtlasDrawnElement.Problems);
  Assert.IsFalse(mInfo.Overlay);
  Assert.IsTrue(TAtlasHideScope.Here in mInfo.Scopes);
  Assert.IsTrue(TAtlasDrawnElements.Info(TAtlasDrawnElement.Notes).Gutter);
  Assert.IsTrue(TAtlasDrawnElements.Info(TAtlasDrawnElement.Bookmarks).Gutter);
  // Spalte der schnellen Lesezeichen (#1104).
  Assert.IsTrue(TAtlasDrawnElements.Info(TAtlasDrawnElement.QuickBookmarks).Gutter);
  Assert.AreEqual('QuickBookmarksGutter', TAtlasDrawnElements.SettingKey(TAtlasDrawnElement.QuickBookmarks));
  Assert.IsFalse(TAtlasHideScope.Here in TAtlasDrawnElements.Info(TAtlasDrawnElement.PairColors).Scopes);
end;

procedure TAtlasDrawnElementsTests.WelcomeSectionsKnowTheirSetting;
var
  mId, mKey: string;
  mStore: IAtlasMemorySettingsStore;
  mNames: TArray<string>;
  mName: string;
  mFound: Boolean;
begin
  mStore := TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults);
  mNames := mStore.Names;
  for mId in TAtlasDrawnElements.KnownSections do
  begin
    mKey := TAtlasDrawnElements.SectionSetting(mId);
    Assert.AreNotEqual('', mKey, mId);
    mFound := False;
    for mName in mNames do
    begin
      mFound := mFound or SameText(mName, mKey);
    end;
    Assert.IsTrue(mFound, 'keine Einstellung: ' + mKey);
  end;
  Assert.AreEqual('WelcomePageStatusTile', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.cState));
  Assert.AreEqual('WelcomePageProjectStatus', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.cProjects));
  // Meine Issues (#765): „Ausblenden“ am Bereich im Bearbeitungsmodus (#767).
  Assert.AreEqual('WelcomePageIssues', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.cIssues));
  Assert.AreEqual('', TAtlasDrawnElements.SectionSetting(TAtlasWelcomeIds.cBoard), 'kein eigener Schalter');
end;

procedure TAtlasDrawnElementsTests.AnchorIsNormalizedAndShort;
begin
  Assert.AreEqual('if A then B := 1;', TAtlasDrawnElements.Anchor('    if  A then'#9'B := 1;   '));
  Assert.AreEqual(TAtlasDrawnElements.cMaxAnchorLength, Integer(Length(TAtlasDrawnElements.Anchor(
    StringOfChar('a', 300)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDrawnElementsTests);

end.
