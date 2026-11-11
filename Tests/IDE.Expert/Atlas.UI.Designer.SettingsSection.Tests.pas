unit Atlas.UI.Designer.SettingsSection.Tests;

// Abschnitt des Moduls Designer (#1456): Designer-Leiste mit Suche, Tab-Reihenfolge, Ausrichten und Gleiche
// auswählen (#738); Laden und Speichern über die Seite.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TDesignerSettingsSectionTests = class
  private
    FRegistrations: TArray<IAtlasRegistration>;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DesignerBarRoundTrip;
    [Test]
    procedure SelectSimilarRoundTrip;
    [Test]
    procedure SelectionSetsRoundTrip;
    [Test]
    procedure SpatialNavigationRoundTrip;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Designer.SettingsSection;

procedure TDesignerSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TDesignerSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasDesignerSettingsSection]);
end;

procedure TDesignerSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure TDesignerSettingsSectionTests.DesignerBarRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'EditorDesignerBar').Checked);
    Assert.AreEqual(0, ChoiceOf(mPage, 'DesignerSearchStyle').Choice, 'Fenster');
    Assert.IsFalse(CheckOf(mPage, 'DesignerTabOrderClick').Checked);
    Assert.IsFalse(CheckOf(mPage, 'DesignerAlign').Checked);
    CheckOf(mPage, 'EditorDesignerBar').Checked := False;
    ChoiceOf(mPage, 'DesignerSearchStyle').Choice := 1;
    EditOf(mPage, 'DesignerSearchKey').Text := '';
    CheckOf(mPage, 'DesignerTabOrderClick').Checked := True;
    CheckOf(mPage, 'DesignerAlign').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.EditorDesignerBar, 'abschaltbar');
    Assert.AreEqual(TAtlasPluginSettings.cDesignerSearchPopup, mSaved.DesignerSearchStyle);
    Assert.AreEqual(0, mSaved.DesignerSearchKey, 'leer = keine Taste');
    Assert.IsTrue(mSaved.DesignerTabOrderClick);
    Assert.IsTrue(mSaved.DesignerAlign);
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'EditorDesignerBar').Checked);
    Assert.AreEqual(1, ChoiceOf(mPage, 'DesignerSearchStyle').Choice);
    Assert.AreEqual('', EditOf(mPage, 'DesignerSearchKey').Text);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.SelectSimilarRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerSelectSimilar').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerSelectDescendants').Checked);
    Assert.AreEqual(0, ChoiceOf(mPage, 'DesignerSelectScope').Choice, 'ganzes Formular');
    CheckOf(mPage, 'DesignerSelectSimilar').Checked := False;
    CheckOf(mPage, 'DesignerSelectDescendants').Checked := False;
    ChoiceOf(mPage, 'DesignerSelectScope').Choice := 1;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerSelectSimilar, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerSelectDescendants);
    Assert.AreEqual(TAtlasPluginSettings.cDesignerScopeParent, mSaved.DesignerSelectScope);
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'DesignerSelectSimilar').Checked);
    Assert.AreEqual(1, ChoiceOf(mPage, 'DesignerSelectScope').Choice);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.SelectionSetsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerSelectionSets').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerSelectionSetsShortcuts').Checked);
    Assert.AreEqual(0, ChoiceOf(mPage, 'DesignerSelectionSetsStorage').Choice, 'lokal');
    CheckOf(mPage, 'DesignerSelectionSets').Checked := False;
    CheckOf(mPage, 'DesignerSelectionSetsShortcuts').Checked := False;
    ChoiceOf(mPage, 'DesignerSelectionSetsStorage').Choice := 1;
    EditOf(mPage, 'DesignerSelectionSetsSaveKey').Text := '';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerSelectionSets, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerSelectionSetsShortcuts);
    Assert.AreEqual(TAtlasPluginSettings.cDesignerSetsShared, mSaved.DesignerSelectionSetsStorage);
    Assert.AreEqual(0, mSaved.DesignerSelectionSetsSaveKey, 'leer = keine Taste');
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'DesignerSelectionSets').Checked);
    Assert.AreEqual(1, ChoiceOf(mPage, 'DesignerSelectionSetsStorage').Choice);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.SpatialNavigationRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerSpatialNavigation').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerSpatialCrossContainers').Checked);
    CheckOf(mPage, 'DesignerSpatialNavigation').Checked := False;
    CheckOf(mPage, 'DesignerSpatialCrossContainers').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerSpatialNavigation, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerSpatialCrossContainers);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'DesignerSpatialNavigation').Checked);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDesignerSettingsSectionTests);

end.
