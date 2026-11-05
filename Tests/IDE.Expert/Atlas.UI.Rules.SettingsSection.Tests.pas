unit Atlas.UI.Rules.SettingsSection.Tests;

// Abschnitte des Moduls Prüfregeln (#1456) auf den Seiten „Prüfregeln“ und „Editor“: Sammelkorrektur (#1352),
// Basislinie und DFM-Eigenschaftsregeln; Laden und Speichern über die Seite und der Platz auf den Unterpunkten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TRulesSettingsSectionTests = class
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
    procedure RulesRoundTrip;
    /// <summary>Sammelkorrektur beim Prüffenster von Base, Basislinie und DFM-Regeln bei Code Lens.</summary>
    [Test]
    procedure RowsOnTheirNodes;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Rules.SettingsSection;

procedure TRulesSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TRulesSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasRulesChecksSection, TAtlasRulesEditorSection]);
end;

procedure TRulesSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure TRulesSettingsSectionTests.RulesRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'RuleChecksEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'FixBulk').Checked, 'Sammelkorrektur standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'BaselineUpdate').Checked);
    Assert.IsTrue(CheckOf(mPage, 'DfmPropertyRules').Checked);
    CheckOf(mPage, 'FixBulk').Checked := False;
    CheckOf(mPage, 'BaselineUpdate').Checked := False;
    CheckOf(mPage, 'DfmPropertyRules').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.FixBulk, 'Sammelkorrektur gespeichert');
    Assert.IsFalse(mSaved.BaselineUpdate);
    Assert.IsFalse(mSaved.DfmPropertyRules);
    mSaved.DfmPropertyRules := True;
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'FixBulk').Checked, 'Sammelkorrektur geladen');
    Assert.IsFalse(CheckOf(mPage, 'BaselineUpdate').Checked);
    Assert.IsTrue(CheckOf(mPage, 'DfmPropertyRules').Checked);
  finally
    mPage.Free;
  end;
end;

procedure TRulesSettingsSectionTests.RowsOnTheirNodes;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'FixBulk')) = mPage.NodeSheet('rules.window'));
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'BaselineUpdate')) = mPage.NodeSheet('editor.codeLens'));
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'DfmPropertyRules')) = mPage.NodeSheet('editor.codeLens'));
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRulesSettingsSectionTests);

end.
