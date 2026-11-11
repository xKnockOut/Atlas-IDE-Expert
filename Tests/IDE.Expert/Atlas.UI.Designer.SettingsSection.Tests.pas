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
    procedure DefaultSizesRoundTrip;
    [Test]
    procedure ZOrderRoundTrip;
    [Test]
    procedure PropertyPainterRoundTrip;
    [Test]
    procedure SuggestAnchorsRoundTrip;
    [Test]
    procedure TextTableRoundTrip;
    [Test]
    procedure LabelPairsRoundTrip;
    [Test]
    procedure ArrangeFormRoundTrip;
    [Test]
    procedure WrapRoundTrip;
    [Test]
    procedure FontsColorsRoundTrip;
    [Test]
    procedure GroupsRoundTrip;
    [Test]
    procedure GapHandlesRoundTrip;
    [Test]
    procedure MultiResizeRoundTrip;
    [Test]
    procedure SelectionBarRoundTrip;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.Core.Designer.SelectionBar,
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

procedure TDesignerSettingsSectionTests.DefaultSizesRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerDefaultSizes').Checked, 'Vorgabe an');
    Assert.AreEqual('', EditOf(mPage, 'DesignerDefaultSizesTable').Text);
    Assert.IsTrue(CheckOf(mPage, 'DesignerDefaultSizesApplyOnInsert').Checked);
    Assert.IsFalse(CheckOf(mPage, 'DesignerDefaultSizesMarkDeviations').Checked);
    CheckOf(mPage, 'DesignerDefaultSizes').Checked := False;
    EditOf(mPage, 'DesignerDefaultSizesTable').Text := 'TButton=88,25';
    CheckOf(mPage, 'DesignerDefaultSizesApplyOnInsert').Checked := False;
    CheckOf(mPage, 'DesignerDefaultSizesMarkDeviations').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerDefaultSizes, 'abschaltbar');
    Assert.AreEqual('TButton=88,25', mSaved.DesignerDefaultSizesTable);
    Assert.IsFalse(mSaved.DesignerDefaultSizesApplyOnInsert);
    Assert.IsTrue(mSaved.DesignerDefaultSizesMarkDeviations);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.ZOrderRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerZOrder').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerZOrderShortcuts').Checked);
    Assert.IsFalse(CheckOf(mPage, 'DesignerZOrderIncludeParents').Checked);
    CheckOf(mPage, 'DesignerZOrder').Checked := False;
    CheckOf(mPage, 'DesignerZOrderShortcuts').Checked := False;
    CheckOf(mPage, 'DesignerZOrderIncludeParents').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerZOrder, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerZOrderShortcuts);
    Assert.IsTrue(mSaved.DesignerZOrderIncludeParents);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.PropertyPainterRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerPropertyPainter').Checked, 'Vorgabe an');
    Assert.AreEqual('font, colors, size, layout', EditOf(mPage, 'DesignerPropertyPainterDefaultGroups').Text);
    Assert.IsTrue(CheckOf(mPage, 'DesignerPropertyPainterRememberPerClass').Checked);
    CheckOf(mPage, 'DesignerPropertyPainter').Checked := False;
    EditOf(mPage, 'DesignerPropertyPainterDefaultGroups').Text := 'font';
    CheckOf(mPage, 'DesignerPropertyPainterRememberPerClass').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerPropertyPainter, 'abschaltbar');
    Assert.AreEqual('font', mSaved.DesignerPropertyPainterDefaultGroups);
    Assert.IsFalse(mSaved.DesignerPropertyPainterRememberPerClass);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.SuggestAnchorsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerSuggestAnchors').Checked, 'Vorgabe an');
    Assert.AreEqual('16', EditOf(mPage, 'DesignerSuggestAnchorsEdgeDistance').Text);
    Assert.IsTrue(CheckOf(mPage, 'DesignerSuggestAnchorsKeepExisting').Checked);
    Assert.AreEqual('TMemo, TDBGrid, TStringGrid, TListView, TTreeView, TPageControl, TRichEdit', EditOf(mPage, 'DesignerSuggestAnchorsFillClasses').Text);
    CheckOf(mPage, 'DesignerSuggestAnchors').Checked := False;
    EditOf(mPage, 'DesignerSuggestAnchorsEdgeDistance').Text := '24';
    CheckOf(mPage, 'DesignerSuggestAnchorsKeepExisting').Checked := False;
    EditOf(mPage, 'DesignerSuggestAnchorsFillClasses').Text := 'TMemo';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerSuggestAnchors, 'abschaltbar');
    Assert.AreEqual(24, mSaved.DesignerSuggestAnchorsEdgeDistance);
    Assert.IsFalse(mSaved.DesignerSuggestAnchorsKeepExisting);
    Assert.AreEqual('TMemo', mSaved.DesignerSuggestAnchorsFillClasses);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.TextTableRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerTextTable').Checked, 'Vorgabe an');
    Assert.AreEqual('accelerators, variants, truncated, whitespace', EditOf(mPage, 'DesignerTextTableChecks').Text);
    Assert.AreEqual('', EditOf(mPage, 'DesignerTextTableSynonyms').Text);
    Assert.AreEqual('SQL, CommandText', EditOf(mPage, 'DesignerTextTableExcludeProperties').Text);
    CheckOf(mPage, 'DesignerTextTable').Checked := False;
    EditOf(mPage, 'DesignerTextTableChecks').Text := 'labelColon';
    EditOf(mPage, 'DesignerTextTableSynonyms').Text := 'Lieferant, Lieferer';
    EditOf(mPage, 'DesignerTextTableExcludeProperties').Text := 'Hint';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerTextTable, 'abschaltbar');
    Assert.AreEqual('labelColon', mSaved.DesignerTextTableChecks);
    Assert.AreEqual('Lieferant, Lieferer', mSaved.DesignerTextTableSynonyms);
    Assert.AreEqual('Hint', mSaved.DesignerTextTableExcludeProperties);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.LabelPairsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerLabelPairs').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerLabelPairsMoveTogether').Checked);
    Assert.AreEqual('16', EditOf(mPage, 'DesignerLabelPairsPairDistance').Text);
    Assert.AreEqual('PLZ, IBAN, BIC, USt, ID', EditOf(mPage, 'DesignerLabelPairsAbbreviations').Text);
    CheckOf(mPage, 'DesignerLabelPairs').Checked := False;
    CheckOf(mPage, 'DesignerLabelPairsBaseline').Checked := False;
    CheckOf(mPage, 'DesignerLabelPairsFocusControl').Checked := False;
    CheckOf(mPage, 'DesignerLabelPairsMoveTogether').Checked := False;
    EditOf(mPage, 'DesignerLabelPairsPairDistance').Text := '24';
    EditOf(mPage, 'DesignerLabelPairsAbbreviations').Text := 'PLZ';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerLabelPairs, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerLabelPairsBaseline);
    Assert.IsFalse(mSaved.DesignerLabelPairsFocusControl);
    Assert.IsFalse(mSaved.DesignerLabelPairsMoveTogether);
    Assert.AreEqual(24, mSaved.DesignerLabelPairsPairDistance);
    Assert.AreEqual('PLZ', mSaved.DesignerLabelPairsAbbreviations);
    Assert.AreEqual(TAtlasPluginSettings.cLabelLeft, mSaved.DesignerLabelPairsNewLabelPosition);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.ArrangeFormRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerArrangeForm').Checked, 'Vorgabe an');
    Assert.AreEqual('8', EditOf(mPage, 'DesignerArrangeFormRowGap').Text);
    Assert.IsFalse(CheckOf(mPage, 'DesignerArrangeFormEqualFieldWidth').Checked);
    Assert.IsTrue(CheckOf(mPage, 'DesignerArrangeFormSetTabOrder').Checked);
    CheckOf(mPage, 'DesignerArrangeForm').Checked := False;
    EditOf(mPage, 'DesignerArrangeFormRowGap').Text := '12';
    EditOf(mPage, 'DesignerArrangeFormLabelGap').Text := '6';
    CheckOf(mPage, 'DesignerArrangeFormEqualFieldWidth').Checked := True;
    CheckOf(mPage, 'DesignerArrangeFormTwoPerRow').Checked := True;
    CheckOf(mPage, 'DesignerArrangeFormSetTabOrder').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerArrangeForm, 'abschaltbar');
    Assert.AreEqual(12, mSaved.DesignerArrangeFormRowGap);
    Assert.AreEqual(6, mSaved.DesignerArrangeFormLabelGap);
    Assert.IsTrue(mSaved.DesignerArrangeFormEqualFieldWidth);
    Assert.IsTrue(mSaved.DesignerArrangeFormTwoPerRow);
    Assert.IsFalse(mSaved.DesignerArrangeFormSetTabOrder);
    Assert.AreEqual(TAtlasPluginSettings.cGridLabelLeft, mSaved.DesignerArrangeFormLabelAlign);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.WrapRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerWrapInContainer').Checked, 'Vorgabe an');
    Assert.AreEqual('8', EditOf(mPage, 'DesignerWrapInContainerPadding').Text);
    Assert.AreEqual('TPanel', EditOf(mPage, 'DesignerWrapInContainerDefaultClass').Text);
    CheckOf(mPage, 'DesignerWrapInContainer').Checked := False;
    EditOf(mPage, 'DesignerWrapInContainerPadding').Text := '4';
    EditOf(mPage, 'DesignerWrapInContainerDefaultClass').Text := 'TGroupBox';
    EditOf(mPage, 'DesignerWrapInContainerClasses').Text := 'TCardPanel';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerWrapInContainer, 'abschaltbar');
    Assert.AreEqual(4, mSaved.DesignerWrapInContainerPadding);
    Assert.AreEqual('TGroupBox', mSaved.DesignerWrapInContainerDefaultClass);
    Assert.AreEqual('TCardPanel', mSaved.DesignerWrapInContainerClasses);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.GapHandlesRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerGapHandles').Checked, 'Vorgabe an');
    Assert.AreEqual('4, 8, 12, 16', EditOf(mPage, 'DesignerGapHandlesSnapValues').Text);
    Assert.AreEqual(0, ChoiceOf(mPage, 'DesignerGapHandlesAnchor').Choice, 'Mitte');
    CheckOf(mPage, 'DesignerGapHandles').Checked := False;
    EditOf(mPage, 'DesignerGapHandlesSnapValues').Text := '6, 10';
    ChoiceOf(mPage, 'DesignerGapHandlesAnchor').Choice := 2;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerGapHandles, 'abschaltbar');
    Assert.AreEqual('6, 10', mSaved.DesignerGapHandlesSnapValues);
    Assert.AreEqual(TAtlasPluginSettings.cGapAnchorLast, mSaved.DesignerGapHandlesAnchor);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.FontsColorsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerFontsColors').Checked, 'Vorgabe an');
    Assert.IsTrue(CheckOf(mPage, 'DesignerFontsColorsRestoreParent').Checked);
    CheckOf(mPage, 'DesignerFontsColors').Checked := False;
    CheckOf(mPage, 'DesignerFontsColorsRestoreParent').Checked := False;
    EditOf(mPage, 'DesignerFontsColorsIgnoreColors').Text := 'clWindow';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerFontsColors, 'abschaltbar');
    Assert.IsFalse(mSaved.DesignerFontsColorsRestoreParent);
    Assert.AreEqual('clWindow', mSaved.DesignerFontsColorsIgnoreColors);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.MultiResizeRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerMultiResize').Checked, 'Vorgabe an');
    Assert.AreEqual(0, ChoiceOf(mPage, 'DesignerMultiResizeMode').Choice, 'delta');
    Assert.IsFalse(CheckOf(mPage, 'DesignerMultiResizeLeftTopHandles').Checked);
    CheckOf(mPage, 'DesignerMultiResize').Checked := False;
    ChoiceOf(mPage, 'DesignerMultiResizeMode').Choice := 1;
    CheckOf(mPage, 'DesignerMultiResizeLeftTopHandles').Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerMultiResize, 'abschaltbar');
    Assert.AreEqual(TAtlasPluginSettings.cResizeModeAlign, mSaved.DesignerMultiResizeMode);
    Assert.IsTrue(mSaved.DesignerMultiResizeLeftTopHandles);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.SelectionBarRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  // Vorgabe der Knöpfe in Base und Kern gleich: alle außer den optionalen.
  Assert.AreEqual(TAtlasSelectionBar.DefaultItems, TAtlasPluginSettings.Defaults.DesignerSelectionBarItems);
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerSelectionBar').Checked, 'Vorgabe an');
    Assert.AreEqual(0, ChoiceOf(mPage, 'DesignerSelectionBarMode').Choice, 'auto');
    Assert.AreEqual('400', EditOf(mPage, 'DesignerSelectionBarDelayMs').Text);
    CheckOf(mPage, 'DesignerSelectionBar').Checked := False;
    ChoiceOf(mPage, 'DesignerSelectionBarMode').Choice := 1;
    EditOf(mPage, 'DesignerSelectionBarDelayMs').Text := '250';
    EditOf(mPage, 'DesignerSelectionBarItems').Text := 'bold, italic';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerSelectionBar, 'abschaltbar');
    Assert.AreEqual(TAtlasPluginSettings.cSelectionBarShortcut, mSaved.DesignerSelectionBarMode);
    Assert.AreEqual(250, mSaved.DesignerSelectionBarDelayMs);
    Assert.AreEqual('bold, italic', mSaved.DesignerSelectionBarItems);
  finally
    mPage.Free;
  end;
end;

procedure TDesignerSettingsSectionTests.GroupsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'DesignerGroups').Checked, 'Vorgabe an');
    CheckOf(mPage, 'DesignerGroups').Checked := False;
    ComboOf(mPage, 'DesignerGroupsMemberClick').ItemIndex := 1;
    ComboOf(mPage, 'DesignerGroupsStorage').ItemIndex := 1;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.DesignerGroups, 'abschaltbar');
    Assert.AreEqual(TAtlasPluginSettings.cDesignerGroupsDoubleClick, mSaved.DesignerGroupsMemberClick);
    Assert.AreEqual(TAtlasPluginSettings.cDesignerSetsShared, mSaved.DesignerGroupsStorage);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDesignerSettingsSectionTests);

end.
