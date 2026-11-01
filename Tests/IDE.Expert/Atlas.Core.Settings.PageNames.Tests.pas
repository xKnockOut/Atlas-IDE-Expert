unit Atlas.Core.Settings.PageNames.Tests;

// Englische Seitennamen (#1458): Übersetzung, unbekannte Seiten und ein
// Wächter über beide Schemas (jede x-page hat einen Eintrag).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPageNamesTests = class
  public
    [Test]
    procedure TranslatesForEnglish;
    [Test]
    procedure KeepsGermanAndUnknown;
    [Test]
    procedure EverySchemaPageKnown;
  end;

implementation

uses
  System.RegularExpressions,
  Atlas.Core.Settings.PageNames,
  Atlas.Core.Settings.PluginSchemaData,
  Atlas.Core.Settings.SchemaData;

procedure TAtlasSettingsPageNamesTests.TranslatesForEnglish;
begin
  Assert.AreEqual('General', TAtlasSettingsPageNames.Caption('Allgemein', True));
  Assert.AreEqual('Completion', TAtlasSettingsPageNames.Caption('vervollständigung', True));
end;

procedure TAtlasSettingsPageNamesTests.KeepsGermanAndUnknown;
begin
  Assert.AreEqual('Allgemein', TAtlasSettingsPageNames.Caption('Allgemein', False));
  Assert.AreEqual('Neue Seite', TAtlasSettingsPageNames.Caption('Neue Seite', True));
  Assert.IsFalse(TAtlasSettingsPageNames.Known('Neue Seite'));
end;

procedure TAtlasSettingsPageNamesTests.EverySchemaPageKnown;
var
  Missing: string;
  Match: TMatch;
begin
  Missing := '';
  for Match in TRegEx.Matches(AtlasSchemaJson + AtlasPluginSchemaJson, '"x-page"\s*:\s*"([^"]+)"') do
    if not TAtlasSettingsPageNames.Known(Match.Groups[1].Value) and (Pos('|' + Match.Groups[1].Value + '|',
      Missing + '|') = 0) then
      Missing := Missing + '|' + Match.Groups[1].Value;
  Assert.AreEqual('', Missing, 'x-page ohne englischen Namen in Atlas.Core.Settings.PageNames');
end;

end.
