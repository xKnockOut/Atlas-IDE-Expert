unit Atlas.Core.Settings.ContextMenuGroups.Tests;

// Tests für die Untermenüs von Atlas im Kontextmenü des Editors (#2102):
// Namen, Lesen mit Trennzeichen, feste Reihenfolge, Normalize, Shown.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasContextMenuGroupNamesTests = class
  public
    [Test]
    procedure NamesOfAllGroups;
    [Test]
    procedure ParsesSeparatorsAndCase;
    [Test]
    procedure NormalizeKeepsFixedOrder;
    /// <summary>Abgewählte Gruppen fehlen; '' und unbekannte Kennungen (neuere Module) bleiben sichtbar.</summary>
    [Test]
    procedure ShownFollowsSetting;
  end;

implementation

uses
  Atlas.Core.Settings.ContextMenuGroups;

{ TAtlasContextMenuGroupNamesTests }

procedure TAtlasContextMenuGroupNamesTests.NamesOfAllGroups;
begin
  Assert.AreEqual('navigation,edit,analysis,findings,debug,tests,notes',
    TAtlasContextMenuGroupNames.Text(TAtlasContextMenuGroupNames.cAll));
  Assert.AreEqual('debug', TAtlasContextMenuGroupNames.Name(TAtlasContextMenuGroup.Debug));
end;

procedure TAtlasContextMenuGroupNamesTests.ParsesSeparatorsAndCase;
begin
  Assert.IsTrue(TAtlasContextMenuGroupNames.Parse('Debug; NOTES,edit') = [TAtlasContextMenuGroup.Edit,
    TAtlasContextMenuGroup.Debug, TAtlasContextMenuGroup.Notes]);
  Assert.IsTrue(TAtlasContextMenuGroupNames.Parse('') = []);
end;

procedure TAtlasContextMenuGroupNamesTests.NormalizeKeepsFixedOrder;
begin
  Assert.AreEqual('navigation,tests', TAtlasContextMenuGroupNames.Normalize('tests, quatsch, navigation, tests'));
  Assert.AreEqual('', TAtlasContextMenuGroupNames.Normalize('nichts'));
end;

procedure TAtlasContextMenuGroupNamesTests.ShownFollowsSetting;
begin
  Assert.IsTrue(TAtlasContextMenuGroupNames.Shown('navigation,debug', 'debug'));
  Assert.IsFalse(TAtlasContextMenuGroupNames.Shown('navigation,debug', 'tests'));
  Assert.IsFalse(TAtlasContextMenuGroupNames.Shown('', 'notes'), 'leer = keine Gruppe');
  Assert.IsTrue(TAtlasContextMenuGroupNames.Shown('', ''), 'ohne Kennung immer');
  Assert.IsTrue(TAtlasContextMenuGroupNames.Shown('', 'profiling'), 'unbekannte Kennung immer');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasContextMenuGroupNamesTests);

end.
