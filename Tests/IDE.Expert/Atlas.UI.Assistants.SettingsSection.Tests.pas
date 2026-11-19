unit Atlas.UI.Assistants.SettingsSection.Tests;

// Seite „KI-Assistenten“ (#1906): Modulschalter, Schreiben in offene Dateien und Builds für KI-Assistenten auf
// einer eigenen Seite des Moduls; die Werte bleiben unter ihren Schlüsseln. KI-Schattentext (#1922): Schalter
// standardmäßig aus, Anbieter und Modell bleiben, der Schlüssel geht nur über die Haken der Komposition.

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
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OwnPageRoundTrips;
    [Test]
    procedure AiGhostSettingsRoundTrip;
    [Test]
    procedure KeyButtonsUseTheHooks;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Assistants.SettingsSection;

{ TAssistantsSettingsSectionTests }

procedure TAssistantsSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasAssistantsSettingsSection]);
end;

procedure TAssistantsSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
  TAtlasAssistantsSettingsSection.KeyHooks := Default(TAtlasAssistantsKeyHooks);
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
    // IDE-Zustand für get_ide_context (#2050) auf derselben Seite, standardmäßig an.
    Assert.AreSame(SheetOf(CheckOf(mPage, 'AssistantsEnabled')), SheetOf(CheckOf(mPage, 'AssistantsContext')));
    Assert.IsTrue(CheckOf(mPage, 'AssistantsContextSelection').Checked);
    CheckOf(mPage, 'AssistantsContext').Checked := False;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.AssistantsContext);
  finally
    mPage.Free;
  end;
end;

procedure TAssistantsSettingsSectionTests.AiGhostSettingsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsFalse(CheckOf(mPage, 'AssistantsInlineSuggestions').Checked, 'KI-Schattentext standardmäßig aus');
    Assert.AreEqual(0, ChoiceOf(mPage, 'AssistantsProvider').Choice, 'kein Anbieter');
    CheckOf(mPage, 'AssistantsInlineSuggestions').Checked := True;
    ChoiceOf(mPage, 'AssistantsProvider').Choice := 1;
    EditOf(mPage, 'AssistantsModel').Text := 'modell-x';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.AssistantsInlineSuggestions);
    Assert.AreEqual('anthropic', mSaved.AssistantsProvider);
    Assert.AreEqual('modell-x', mSaved.AssistantsModel);
  finally
    mPage.Free;
  end;
end;

procedure TAssistantsSettingsSectionTests.KeyButtonsUseTheHooks;
var
  mSection: TAtlasAssistantsSettingsSection;
  mProvided: IAtlasSettingsSection;
  mPage: TAtlasSettingsPage;
  mHooks: TAtlasAssistantsKeyHooks;
  mStored, mDeleted: string;
begin
  // Eigene Registrierung mit einer Instanz, deren Knöpfe der Test erreicht.
  RevokeAll(FRegistrations);
  mStored := '';
  mDeleted := '';
  mHooks := Default(TAtlasAssistantsKeyHooks);
  mHooks.Has :=
    function(AId: string): Boolean
    begin
      Result := mStored <> '';
    end;
  mHooks.Store :=
    function(AId, AKey: string): Boolean
    begin
      mStored := AId + '=' + AKey;
      Result := True;
    end;
  mHooks.Delete :=
    procedure(AId: string)
    begin
      mDeleted := AId;
      mStored := '';
    end;
  mHooks.Ask :=
    function(const ATitle, ALabel: string; var AKey: string): Boolean
    begin
      AKey := ' k1 ';
      Result := True;
    end;
  TAtlasAssistantsSettingsSection.KeyHooks := mHooks;
  mSection := TAtlasAssistantsSettingsSection.Create;
  mProvided := mSection;
  FRegistrations := [ProvideSection(mProvided)];
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsFalse(mSection.KeyStoreButton.Enabled, 'ohne Anbieter gesperrt');
    mSection.ProviderBox.Choice := 1;
    mSection.KeyStoreButton.Click;
    Assert.AreEqual('anthropic=k1', mStored, 'Schlüssel ohne Leerzeichen an den Haken');
    Assert.IsTrue(Pos('anthropic', mSection.KeyStateLabel.Caption) > 0, 'Stand zeigt den Anbieter');
    Assert.IsFalse(Pos('k1', mSection.KeyStateLabel.Caption) > 0, 'nie den Schlüssel');
    mSection.KeyDeleteButton.Click;
    Assert.AreEqual('anthropic', mDeleted);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAssistantsSettingsSectionTests);

end.
