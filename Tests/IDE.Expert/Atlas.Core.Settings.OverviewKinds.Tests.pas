unit Atlas.Core.Settings.OverviewKinds.Tests;

// Tests für die Arten der Übersichtsleiste (#519, #415): Namen, Lesen mit
// Trennzeichen und Groß-/Kleinschreibung, Text in fester Reihenfolge, Normalize.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOverviewKindNamesTests = class
  public
    [Test]
    procedure NamesOfAllKinds;
    [Test]
    procedure ParsesSeparatorsAndCase;
    [Test]
    procedure DropsUnknownNames;
    [Test]
    procedure TextKeepsFixedOrder;
    [Test]
    procedure NormalizeRemovesDuplicatesAndUnknown;
  end;

implementation

uses
  Atlas.Core.Settings.OverviewKinds;

{ TAtlasOverviewKindNamesTests }

procedure TAtlasOverviewKindNamesTests.NamesOfAllKinds;
begin
  Assert.AreEqual('diagnostics', TAtlasOverviewKindNames.Name(TAtlasOverviewKind.Diagnostics));
  Assert.AreEqual('search', TAtlasOverviewKindNames.Name(TAtlasOverviewKind.Search));
  Assert.AreEqual('changes', TAtlasOverviewKindNames.Name(TAtlasOverviewKind.Changes));
  Assert.AreEqual('breakpoints', TAtlasOverviewKindNames.Name(TAtlasOverviewKind.Breakpoints));
  Assert.AreEqual('bookmarks', TAtlasOverviewKindNames.Name(TAtlasOverviewKind.Bookmarks));
  Assert.AreEqual('cursor', TAtlasOverviewKindNames.Name(TAtlasOverviewKind.Cursor));
end;

procedure TAtlasOverviewKindNamesTests.ParsesSeparatorsAndCase;
var
  Kinds: TAtlasOverviewKinds;
begin
  Kinds := TAtlasOverviewKindNames.Parse('Diagnostics, SEARCH;cursor bookmarks');
  Assert.IsTrue(Kinds = [TAtlasOverviewKind.Diagnostics, TAtlasOverviewKind.Search, TAtlasOverviewKind.Cursor,
    TAtlasOverviewKind.Bookmarks]);
  Assert.IsTrue(TAtlasOverviewKindNames.Parse('') = []);
  Assert.IsTrue(TAtlasOverviewKindNames.Parse(
    'diagnostics,search,changes,breakpoints,bookmarks,cursor') = TAtlasOverviewKindNames.All);
end;

procedure TAtlasOverviewKindNamesTests.DropsUnknownNames;
begin
  Assert.IsTrue(TAtlasOverviewKindNames.Parse('fehler,changes,,') = [TAtlasOverviewKind.Changes]);
  Assert.IsTrue(TAtlasOverviewKindNames.Parse('diag') = []);
end;

procedure TAtlasOverviewKindNamesTests.TextKeepsFixedOrder;
begin
  Assert.AreEqual('search,cursor', TAtlasOverviewKindNames.Text([TAtlasOverviewKind.Cursor,
    TAtlasOverviewKind.Search]));
  Assert.AreEqual('', TAtlasOverviewKindNames.Text([]));
  Assert.AreEqual('diagnostics,search,changes,breakpoints,bookmarks,cursor',
    TAtlasOverviewKindNames.Text(TAtlasOverviewKindNames.All));
end;

procedure TAtlasOverviewKindNamesTests.NormalizeRemovesDuplicatesAndUnknown;
begin
  Assert.AreEqual('diagnostics,changes,cursor',
    TAtlasOverviewKindNames.Normalize('cursor; CHANGES, unbekannt, diagnostics, cursor'));
  Assert.AreEqual('', TAtlasOverviewKindNames.Normalize('nichts'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOverviewKindNamesTests);

end.
