unit Atlas.Core.Settings.Plugin.Assistants.Tests;

// Einstellungen des KI-Anbieters (#1922): Vorgaben (aus, kein Anbieter, kleines Modell), Grenzen, unbekannter
// Anbieter, leeres Modell und Lesen/Schreiben unter den Namen des Schemas.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPluginAssistantsSettingsTests = class
  public
    [Test]
    procedure DefaultsSendNothing;
    [Test]
    procedure NormalizeClampsNumbers;
    [Test]
    procedure UnknownProviderBecomesNone;
    [Test]
    procedure EmptyModelFallsBackToDefault;
    [Test]
    procedure PluginSettingsCarryTheValues;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Plugin.Assistants;

{ TAtlasPluginAssistantsSettingsTests }

procedure TAtlasPluginAssistantsSettingsTests.DefaultsSendNothing;
var
  mSettings: TAtlasPluginAssistantsSettings;
begin
  mSettings := TAtlasPluginAssistantsSettings.Defaults;
  Assert.IsFalse(mSettings.AssistantsInlineSuggestions, 'Standard aus');
  Assert.AreEqual('none', mSettings.AssistantsProvider);
  Assert.AreEqual(cDefaultAssistantsModel, mSettings.AssistantsModel);
  Assert.AreEqual(40, mSettings.AssistantsContextLines);
  Assert.AreEqual(300, mSettings.AssistantsDailyLimit);
  Assert.AreEqual('', mSettings.AssistantsExclude);
end;

procedure TAtlasPluginAssistantsSettingsTests.NormalizeClampsNumbers;
var
  mSettings: TAtlasPluginAssistantsSettings;
begin
  mSettings := TAtlasPluginAssistantsSettings.Defaults;
  mSettings.AssistantsContextLines := 5;
  mSettings.AssistantsDailyLimit := 0;
  mSettings.Normalize;
  Assert.AreEqual(cMinAssistantsContextLines, mSettings.AssistantsContextLines);
  Assert.AreEqual(cMinAssistantsDailyLimit, mSettings.AssistantsDailyLimit);
  mSettings.AssistantsContextLines := 5000;
  mSettings.AssistantsDailyLimit := MaxInt;
  mSettings.Normalize;
  Assert.AreEqual(cMaxAssistantsContextLines, mSettings.AssistantsContextLines);
  Assert.AreEqual(cMaxAssistantsDailyLimit, mSettings.AssistantsDailyLimit);
end;

procedure TAtlasPluginAssistantsSettingsTests.UnknownProviderBecomesNone;
var
  mSettings: TAtlasPluginAssistantsSettings;
begin
  mSettings := TAtlasPluginAssistantsSettings.Defaults;
  mSettings.AssistantsProvider := ' Anthropic ';
  mSettings.Normalize;
  Assert.AreEqual('anthropic', mSettings.AssistantsProvider);
  mSettings.AssistantsProvider := 'gibtsnicht';
  mSettings.Normalize;
  Assert.AreEqual('none', mSettings.AssistantsProvider);
end;

procedure TAtlasPluginAssistantsSettingsTests.EmptyModelFallsBackToDefault;
var
  mSettings: TAtlasPluginAssistantsSettings;
begin
  mSettings := TAtlasPluginAssistantsSettings.Defaults;
  mSettings.AssistantsModel := '   ';
  mSettings.AssistantsExclude := '  *\Geheim\*  ';
  mSettings.Normalize;
  Assert.AreEqual(cDefaultAssistantsModel, mSettings.AssistantsModel);
  Assert.AreEqual('*\Geheim\*', mSettings.AssistantsExclude);
end;

procedure TAtlasPluginAssistantsSettingsTests.PluginSettingsCarryTheValues;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.AssistantsInlineSuggestions);
  Assert.AreEqual('none', mSettings.AssistantsProvider);
  mSettings.AssistantsProvider := 'anthropic';
  mSettings.AssistantsInlineSuggestions := True;
  mSettings.Normalize;
  Assert.AreEqual('anthropic', mSettings.AssistantsProvider);
  Assert.IsTrue(mSettings.AssistantsInlineSuggestions);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginAssistantsSettingsTests);

end.
