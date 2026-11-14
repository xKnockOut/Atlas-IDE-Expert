unit Atlas.UI.Assistants.SettingsSection.Tests;

// Seite „KI-Assistenten“ (#1906): Modulschalter, Schreiben in offene Dateien und Builds für KI-Assistenten auf
// einer eigenen Seite des Moduls; die Werte bleiben unter ihren Schlüsseln.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAssistantsSettingsSectionTests = class
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
    procedure OwnPageRoundTrips;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Assistants.SettingsSection;

procedure TAssistantsSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TAssistantsSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasAssistantsSettingsSection]);
end;

procedure TAssistantsSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure TAssistantsSettingsSectionTests.OwnPageRoundTrips;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'McpBuild').Checked, 'Builds für KI-Assistenten standardmäßig an');
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'McpBuild')),
      'alle Schalter auf der Seite des Moduls');
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsEdit')));
    CheckOf(mPage, 'McpBuild').Checked := False;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.McpBuild, 'abschaltbar, Schlüssel unverändert');
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'McpBuild').Checked);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAssistantsSettingsSectionTests);

end.
