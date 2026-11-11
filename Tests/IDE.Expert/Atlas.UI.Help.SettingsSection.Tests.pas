unit Atlas.UI.Help.SettingsSection.Tests;

// Abschnitt des Moduls Hilfe (#1886): Modulschalter help.enabled und Quelle help.source; Laden und Speichern über die
// Seite.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Help')]
  THelpSettingsSectionTests = class
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
    procedure SwitchAndSourceRoundTrip;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Help.SettingsSection;

procedure THelpSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure THelpSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasHelpSettingsSection]);
end;

procedure THelpSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure THelpSettingsSectionTests.SwitchAndSourceRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'HelpEnabled').Checked, 'Modulschalter an');
    Assert.AreEqual(0, ChoiceOf(mPage, 'HelpSource').Choice, 'online');
    CheckOf(mPage, 'HelpEnabled').Checked := False;
    ChoiceOf(mPage, 'HelpSource').Choice := 1;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.HelpEnabled, 'abschaltbar');
    Assert.AreEqual(TAtlasPluginSettings.cHelpSourceLocal, mSaved.HelpSource);
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'HelpEnabled').Checked);
    Assert.AreEqual(1, ChoiceOf(mPage, 'HelpSource').Choice);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THelpSettingsSectionTests);

end.
