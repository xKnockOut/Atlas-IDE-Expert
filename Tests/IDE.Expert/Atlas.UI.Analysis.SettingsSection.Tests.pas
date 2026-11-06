unit Atlas.UI.Analysis.SettingsSection.Tests;

// Abschnitt des Moduls Analyse (#1456): Architekturübersicht (#1118) und Hotspots (#1354); Laden und Speichern
// über die Seite und der Platz unter den Unterpunkten von „Allgemein“; Code Lens mit Code-Metriken (#66, #1756) auf
// der Seite „Editor“.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAnalysisSettingsSectionTests = class
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
    procedure AnalysisRoundTrip;
    /// <summary>Die Zeilen stehen auf den Unterpunkten (x-node) von „Allgemein“.</summary>
    [Test]
    procedure RowsOnTheirNodes;
    /// <summary>codeLens.metrics baut das Modul, nicht mehr Base; Unterpunkt Editor › Code Lens.</summary>
    [Test]
    procedure MetricsLensRoundTrip;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Analysis.SettingsSection;

procedure TAnalysisSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TAnalysisSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasAnalysisSettingsSection, TAtlasAnalysisEditorSection]);
end;

procedure TAnalysisSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure TAnalysisSettingsSectionTests.AnalysisRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'AnalysisEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'ArchitectureEnabled').Checked);
    Assert.AreEqual(0, ChoiceOf(mPage, 'ArchitectureScope').Choice, 'Projektgruppe');
    Assert.AreEqual('15', EditOf(mPage, 'ArchitectureCentralUnits').Text);
    Assert.IsTrue(CheckOf(mPage, 'HotspotsEnabled').Checked);
    Assert.AreEqual('12', EditOf(mPage, 'HotspotsMonths').Text);
    Assert.AreEqual('5', EditOf(mPage, 'HotspotsCouplingMinCommits').Text);
    CheckOf(mPage, 'ArchitectureEnabled').Checked := False;
    ChoiceOf(mPage, 'ArchitectureScope').Choice := 1;
    EditOf(mPage, 'ArchitectureCentralUnits').Text := '30';
    CheckOf(mPage, 'HotspotsEnabled').Checked := False;
    EditOf(mPage, 'HotspotsMonths').Text := '6';
    EditOf(mPage, 'HotspotsCouplingMinCommits').Text := '9';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.ArchitectureEnabled, 'abschaltbar');
    Assert.AreEqual('project', mSaved.ArchitectureScope);
    Assert.AreEqual(30, mSaved.ArchitectureCentralUnits);
    Assert.IsFalse(mSaved.HotspotsEnabled, 'abschaltbar');
    Assert.AreEqual(6, mSaved.HotspotsMonths);
    Assert.AreEqual(9, mSaved.HotspotsCouplingMinCommits);
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'ArchitectureEnabled').Checked);
    Assert.AreEqual(1, ChoiceOf(mPage, 'ArchitectureScope').Choice);
    Assert.AreEqual('6', EditOf(mPage, 'HotspotsMonths').Text);
  finally
    mPage.Free;
  end;
end;

procedure TAnalysisSettingsSectionTests.RowsOnTheirNodes;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'ArchitectureEnabled')) = mPage.NodeSheet('general.architecture'));
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'HotspotsEnabled')) = mPage.NodeSheet('general.hotspots'));
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'CodeLensMetrics')) = mPage.NodeSheet('editor.codeLens'), 'Editor › Code Lens');
  finally
    mHost.Free;
  end;
end;

procedure TAnalysisSettingsSectionTests.MetricsLensRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'CodeLensMetrics').Checked, 'Vorgabe an (#66)');
    CheckOf(mPage, 'CodeLensMetrics').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.CodeLensMetrics, 'abschaltbar');
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'CodeLensMetrics').Checked);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalysisSettingsSectionTests);

end.
