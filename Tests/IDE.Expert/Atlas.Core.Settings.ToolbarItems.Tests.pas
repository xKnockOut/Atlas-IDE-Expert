unit Atlas.Core.Settings.ToolbarItems.Tests;

// Atlas-Editorleiste (#1101): Belegung editor.toolbar.items lesen und
// schreiben, Vorgabe, Bereinigen, Schritte des Dialogs „Leiste anpassen“,
// angeheftete Abschnittssymbole.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasToolbarItemsTests = class
  public
    [Test]
    procedure ParseAndFormat;
    [Test]
    procedure DefaultStartsWithSections;
    [Test]
    procedure NormalizeCleansSeparatorsAndDuplicates;
    [Test]
    procedure AddRemoveMove;
    [Test]
    procedure PinnedCountOnlyLeadingSections;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.ToolbarItems;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(' ', AItems);
end;

procedure TAtlasToolbarItemsTests.ParseAndFormat;
var
  Items: TArray<string>;
begin
  Items := TAtlasToolbarItems.Parse(' Atlas.GotoInterface , | ,,Atlas.NavBack ');
  Assert.AreEqual('Atlas.GotoInterface | Atlas.NavBack', Joined(Items));
  Assert.AreEqual('Atlas.GotoInterface,|,Atlas.NavBack', TAtlasToolbarItems.Format(Items));
  Assert.AreEqual(0, Integer(Length(TAtlasToolbarItems.Parse(''))));
  Assert.AreEqual('', TAtlasToolbarItems.Format(nil));
  Assert.IsTrue(TAtlasToolbarItems.IsSeparator('|'));
  Assert.IsFalse(TAtlasToolbarItems.IsSeparator('Atlas.NavBack'));
end;

procedure TAtlasToolbarItemsTests.DefaultStartsWithSections;
var
  Items: TArray<string>;
begin
  Items := TAtlasToolbarItems.Default;
  Assert.AreEqual('Atlas.GotoInterface Atlas.GotoImplementation | Atlas.NavBack Atlas.NavForward ' +
    'Atlas.ToggleMethod Atlas.SwitchTestUnit | Atlas.UnitSearch Atlas.FindMethod | Atlas.CodeActions ' +
    'Atlas.FormatCode Atlas.ProblemsWindow Atlas.CommandPalette', Joined(Items));
  Assert.AreEqual(TAtlasToolbarItems.Format(Items), TAtlasToolbarItems.DefaultText);
  // Die Vorgabe ist schon bereinigt.
  Assert.AreEqual(TAtlasToolbarItems.DefaultText, TAtlasToolbarItems.Normalize(TAtlasToolbarItems.DefaultText));
end;

procedure TAtlasToolbarItemsTests.NormalizeCleansSeparatorsAndDuplicates;
begin
  Assert.AreEqual('A,|,B', TAtlasToolbarItems.Normalize('|,A,|,|,B,|'));
  Assert.AreEqual('A,B', TAtlasToolbarItems.Normalize('A,B,a'), 'jeder Knopf nur einmal');
  Assert.AreEqual('', TAtlasToolbarItems.Normalize('|,|'), 'nur Trennstriche');
  Assert.AreEqual('', TAtlasToolbarItems.Normalize(''), 'leer bleibt leer');
end;

procedure TAtlasToolbarItemsTests.AddRemoveMove;
var
  Items: TArray<string>;
begin
  Items := ['A', 'B'];
  Assert.AreEqual(2, TAtlasToolbarItems.Add(Items, 'C', -1), 'hinten');
  Assert.AreEqual(1, TAtlasToolbarItems.Add(Items, '|', 1), 'Trennstrich');
  Assert.AreEqual(4, TAtlasToolbarItems.Add(Items, '|', 99));
  Assert.AreEqual(-1, TAtlasToolbarItems.Add(Items, 'b', 0), 'schon da');
  Assert.AreEqual(-1, TAtlasToolbarItems.Add(Items, ' ', 0), 'leer');
  Assert.AreEqual('A | B C |', Joined(Items));
  Assert.AreEqual(1, TAtlasToolbarItems.Move(Items, 2, -1));
  Assert.AreEqual('A B | C |', Joined(Items));
  Assert.AreEqual(0, TAtlasToolbarItems.Move(Items, 0, -1), 'oben bleibt oben');
  Assert.AreEqual(4, TAtlasToolbarItems.Move(Items, 4, 1), 'unten bleibt unten');
  Assert.AreEqual(9, TAtlasToolbarItems.Move(Items, 9, 1), 'außerhalb');
  Assert.IsTrue(TAtlasToolbarItems.Remove(Items, 4));
  Assert.IsFalse(TAtlasToolbarItems.Remove(Items, 4));
  Assert.IsFalse(TAtlasToolbarItems.Remove(Items, -1));
  Assert.AreEqual('A B | C', Joined(Items));
end;

procedure TAtlasToolbarItemsTests.PinnedCountOnlyLeadingSections;
begin
  Assert.AreEqual(2, TAtlasToolbarItems.PinnedCount(TAtlasToolbarItems.Default));
  Assert.AreEqual(4, TAtlasToolbarItems.PinnedCount([TAtlasToolbarItems.GotoUses, TAtlasToolbarItems.GotoInterface,
    TAtlasToolbarItems.GotoImplementation, TAtlasToolbarItems.GotoInitialization, 'Atlas.NavBack',
    TAtlasToolbarItems.GotoUses]));
  Assert.AreEqual(0, TAtlasToolbarItems.PinnedCount(['Atlas.NavBack', TAtlasToolbarItems.GotoInterface]));
  Assert.AreEqual(0, TAtlasToolbarItems.PinnedCount(nil));
  Assert.IsTrue(TAtlasToolbarItems.IsSection('atlas.gotointerface'));
  Assert.IsFalse(TAtlasToolbarItems.IsSection(TAtlasToolbarItems.ReturnFromSection));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarItemsTests);

end.
