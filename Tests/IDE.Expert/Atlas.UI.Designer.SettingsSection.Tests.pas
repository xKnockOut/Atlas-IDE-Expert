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
    [Test]
    procedure FitToTextRoundTrip;
    [Test]
    procedure ButtonBarRoundTrip;
    [Test]
    procedure DuplicateRowRoundTrip;
    [Test]
    procedure InsertSpaceRoundTrip;
    [Test]
    procedure FitContainerRoundTrip;
    [Test]
    procedure NearAlignmentRoundTrip;
    [Test]
    procedure MeasureRoundTrip;
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

procedure TDesignerSettingsSectionTests.FitToTextRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerFitToText').Checked, 'Vorgabe an');
    Assert.AreEqual('75', EditOf(mPage, 'DesignerFitToTextMinWidth').Text);
    Assert.AreEqual('caption', EditOf(mPage, 'DesignerFitToTextSources').Text);
    CheckOf(mPage, 'DesignerFitToText').Checked := False;
    EditOf(mPage, 'DesignerFitToTextPadding').Text := '20';
    EditOf(mPage, 'DesignerFitToTextSources').Text := 'caption,items';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerFitToText, 'abschaltbar');
    Assert.AreEqual(20, mSaved.DesignerFitToTextPadding);
    Assert.AreEqual('caption,items', mSaved.DesignerFitToTextSources);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.ButtonBarRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerButtonBar').Checked, 'Vorgabe an');
    Assert.AreEqual(0, ChoiceOf(mPage, 'DesignerButtonBarPosition').Choice, 'unten rechts');
    Assert.AreEqual('8', EditOf(mPage, 'DesignerButtonBarGap').Text);
    CheckOf(mPage, 'DesignerButtonBar').Checked := False;
    ChoiceOf(mPage, 'DesignerButtonBarPosition').Choice := 2;
    CheckOf(mPage, 'DesignerButtonBarSetModalResult').Checked := False;
    EditOf(mPage, 'DesignerButtonBarRoles').Text := 'ok=Weiter';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerButtonBar, 'abschaltbar');
    Assert.AreEqual(TAtlasPluginSettings.cButtonBarRightTop, mSaved.DesignerButtonBarPosition);
    Assert.IsFalse(mSaved.DesignerButtonBarSetModalResult);
    Assert.AreEqual('ok=Weiter', mSaved.DesignerButtonBarRoles);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.DuplicateRowRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerDuplicateRow').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerDuplicateRowShareEvents').Checked);
    Assert.AreEqual('8', EditOf(mPage, 'DesignerDuplicateRowDefaultGap').Text);
    CheckOf(mPage, 'DesignerDuplicateRow').Checked := False;
    CheckOf(mPage, 'DesignerDuplicateRowShareEvents').Checked := False;
    EditOf(mPage, 'DesignerDuplicateRowDefaultGap').Text := '12';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerDuplicateRow, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerDuplicateRowShareEvents);
    Assert.AreEqual(12, mSaved.DesignerDuplicateRowDefaultGap);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.InsertSpaceRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerInsertSpace').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerInsertSpaceGrowParent').Checked);
    CheckOf(mPage, 'DesignerInsertSpace').Checked := False;
    CheckOf(mPage, 'DesignerInsertSpaceGrowParent').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerInsertSpace, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerInsertSpaceGrowParent);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.FitContainerRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerFitContainer').Checked, 'Vorgabe an');
    Assert.AreEqual('8', EditOf(mPage, 'DesignerFitContainerPadding').Text);
    Assert.IsFalse(CheckOf(mPage, 'DesignerFitContainerAlignTopLeft').Checked);
    CheckOf(mPage, 'DesignerFitContainer').Checked := False;
    EditOf(mPage, 'DesignerFitContainerPadding').Text := '12';
    CheckOf(mPage, 'DesignerFitContainerAlignTopLeft').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerFitContainer, 'abschaltbar');
    Assert.AreEqual(12, mSaved.DesignerFitContainerPadding);
    Assert.IsTrue(mSaved.DesignerFitContainerAlignTopLeft);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.NearAlignmentRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerNearAlignment').Checked, 'Vorgabe an');
    Assert.AreEqual('3', EditOf(mPage, 'DesignerNearAlignmentTolerance').Text);
    Assert.IsTrue(CheckOf(mPage, 'DesignerNearAlignmentBaseline').Checked);
    Assert.AreEqual('TBevel,TShape', EditOf(mPage, 'DesignerNearAlignmentIgnoreClasses').Text);
    CheckOf(mPage, 'DesignerNearAlignment').Checked := False;
    EditOf(mPage, 'DesignerNearAlignmentTolerance').Text := '5';
    CheckOf(mPage, 'DesignerNearAlignmentBaseline').Checked := False;
    EditOf(mPage, 'DesignerNearAlignmentIgnoreClasses').Text := 'TImage';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerNearAlignment, 'abschaltbar');
    Assert.AreEqual(5, mSaved.DesignerNearAlignmentTolerance);
    Assert.IsFalse(mSaved.DesignerNearAlignmentBaseline);
    Assert.AreEqual('TImage', mSaved.DesignerNearAlignmentIgnoreClasses);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.MeasureRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerMeasureDistances').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerMeasureAltKey').Checked, 'Vorgabe an');
    CheckOf(mPage, 'DesignerMeasureDistances').Checked := False;
    CheckOf(mPage, 'DesignerMeasureAltKey').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerMeasureDistances, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerMeasureAltKey, 'abschaltbar');
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDesignerSettingsSectionTests);

end.
