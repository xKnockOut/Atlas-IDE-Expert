unit Atlas.Core.Settings.KeyCodes.Tests;

// Tastencodes der Vorgaben (Atlas.Core.Settings.KeyCodes): Die aus Umschalttasten und virtuellen Tasten
// zusammengesetzten Vorgaben ergeben dieselben TShortCut-Werte wie die früheren Zahlen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsKeyCodesTests = class
  public
    [Test]
    procedure ModifiersLikeVcl;
    [Test]
    procedure DefaultsKeepTheirShortcuts;
  end;

implementation

uses
  Atlas.Core.Settings.KeyCodes,
  Atlas.Core.Settings.Plugin;

{ TAtlasSettingsKeyCodesTests }

procedure TAtlasSettingsKeyCodesTests.ModifiersLikeVcl;
begin
  // scShift, scCtrl, scAlt aus System.Classes.
  Assert.AreEqual($2000, Integer(cKeyShift));
  Assert.AreEqual($4000, Integer(cKeyCtrl));
  Assert.AreEqual($8000, Integer(cKeyAlt));
end;

procedure TAtlasSettingsKeyCodesTests.DefaultsKeepTheirShortcuts;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual($6050, mSettings.PaletteKey, 'Strg+Umschalt+P');
  Assert.AreEqual($C078, mSettings.CheckKey, 'Strg+Alt+F9');
  Assert.AreEqual($800D, mSettings.ActionsKey, 'Alt+Enter');
  Assert.AreEqual($602E, mSettings.UnwrapKey, 'Strg+Umschalt+Entf');
  Assert.AreEqual($A028, mSettings.DuplicateLinesDownKey, 'Umschalt+Alt+↓');
  Assert.AreEqual($40BE, mSettings.HideElementKey, 'Strg+.');
  Assert.AreEqual($72, mSettings.SearchNextKey, 'F3');
  Assert.AreEqual($C022, mSettings.NextChangeKey, 'Strg+Alt+Bild↓');
  Assert.AreEqual($40BA, mSettings.JumpToMatchKey, 'Strg+Ü');
  Assert.AreEqual($6031, mSettings.QuickBookmarkSetKey, 'Strg+Umschalt+1');
  Assert.AreEqual($604B, mSettings.QuickBookmarkKey, 'Strg+Umschalt+K');
  Assert.AreEqual($C076, mSettings.DebugStepIntoTargetKey, 'Strg+Alt+F7');
  Assert.AreEqual($80DC, mSettings.DesignerSearchKey, 'Alt+^');
  Assert.AreEqual($6020, mSettings.DesignerSelectionBarKey, 'Strg+Umschalt+Leer');
  Assert.AreEqual($C04C, mSettings.DesignerMagnifierKey, 'Strg+Alt+L');
end;

end.
