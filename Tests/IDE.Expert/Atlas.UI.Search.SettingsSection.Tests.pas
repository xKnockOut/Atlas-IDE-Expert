unit Atlas.UI.Search.SettingsSection.Tests;

// Abschnitte des Moduls Suche (#1456): Units suchen (#786), Suchleiste (#878, #893) und Code-Abfragen (#1351);
// Laden und Speichern über die Seite (vorher in den Tests der Seite von Base).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TSearchSettingsSectionTests = class
  private
    FRegistrations: TArray<IAtlasRegistration>;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>#786: Alt+F11 und Umschalt+F12 auf der Seite „Units suchen“; Strg+F12 bleibt.</summary>
    [Test]
    procedure UseUnitAndFormsDialogsRoundTrip;
    /// <summary>Auswahllisten in der Reihenfolge der Werte; Verlauf der Suchleiste; Code-Abfragen.</summary>
    [Test]
    procedure ChoicesAndSearchBarRoundTrip;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Search.SettingsSection;

procedure TSearchSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TSearchSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasSearchUnitSearchSection, TAtlasSearchQuerySection]);
end;

procedure TSearchSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure TSearchSettingsSectionTests.UseUnitAndFormsDialogsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'SearchEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'UnitSearchReplaceUseUnitDialog').Checked, 'Alt+F11 standardmäßig übernommen');
    Assert.IsTrue(CheckOf(mPage, 'UnitSearchReplaceFormsDialog').Checked, 'Umschalt+F12 standardmäßig übernommen');
    CheckOf(mPage, 'UnitSearchReplaceUseUnitDialog').Checked := False;
    CheckOf(mPage, 'UnitSearchReplaceFormsDialog').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.UnitSearchReplaceUseUnitDialog);
    Assert.IsFalse(mSaved.UnitSearchReplaceFormsDialog);
    Assert.IsTrue(mSaved.UnitSearchReplaceIdeDialog, 'Strg+F12 bleibt');
    mSaved.UnitSearchReplaceFormsDialog := True;
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'UnitSearchReplaceUseUnitDialog').Checked);
    Assert.IsTrue(CheckOf(mPage, 'UnitSearchReplaceFormsDialog').Checked);
  finally
    mPage.Free;
  end;
end;

procedure TSearchSettingsSectionTests.ChoicesAndSearchBarRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, ChoiceOf(mPage, 'UnitSearchPathStyle').Choice, 'relativ');
    Assert.AreEqual(0, ChoiceOf(mPage, 'UnitSearchGroupBy').Choice, 'nach Projekt');
    Assert.AreEqual(0, ChoiceOf(mPage, 'UnitSearchDefaultScope').Choice, 'Projektgruppe');
    Assert.AreEqual('20', EditOf(mPage, 'SearchHistory').Text);
    Assert.IsTrue(CheckOf(mPage, 'QueryEnabled').Checked, 'Code-Abfragen standardmäßig an');
    ChoiceOf(mPage, 'UnitSearchPathStyle').Choice := 2;
    ChoiceOf(mPage, 'UnitSearchGroupBy').Choice := 1;
    ChoiceOf(mPage, 'UnitSearchDefaultScope').Choice := 3;
    EditOf(mPage, 'SearchHistory').Text := '7';
    CheckOf(mPage, 'SearchRegex').Checked := False;
    CheckOf(mPage, 'QueryEnabled').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('absolute', mSaved.UnitSearchPathStyle);
    Assert.AreEqual('folder', mSaved.UnitSearchGroupBy);
    Assert.AreEqual('library', mSaved.UnitSearchDefaultScope);
    Assert.AreEqual(7, mSaved.SearchHistory);
    Assert.IsFalse(mSaved.SearchRegex);
    Assert.IsFalse(mSaved.QueryEnabled, 'abschaltbar');
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(2, ChoiceOf(mPage, 'UnitSearchPathStyle').Choice);
    Assert.AreEqual(3, ChoiceOf(mPage, 'UnitSearchDefaultScope').Choice);
    Assert.IsFalse(CheckOf(mPage, 'QueryEnabled').Checked);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSearchSettingsSectionTests);

end.
