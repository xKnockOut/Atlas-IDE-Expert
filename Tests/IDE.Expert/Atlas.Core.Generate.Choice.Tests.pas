unit Atlas.Core.Generate.Choice.Tests;

// Tests der Auswahl mit Suchfeld (#1821): Wörter, Groß- und Kleinschreibung,
// leere Suche, Stelle der Vorauswahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasChoiceFilterTests = class
  public
    [Test]
    procedure EmptySearchMatchesAll;
    [Test]
    procedure EveryWordMustMatch;
    [Test]
    procedure PositionOfPreselection;
  end;

implementation

uses
  Atlas.Core.Generate.Choice;

procedure TAtlasChoiceFilterTests.EmptySearchMatchesAll;
begin
  Assert.AreEqual(3, Integer(Length(TAtlasChoiceFilter.Matches(['A', 'B', 'C'], '  '))));
  Assert.AreEqual(0, Integer(Length(TAtlasChoiceFilter.Matches(nil, ''))));
end;

procedure TAtlasChoiceFilterTests.EveryWordMustMatch;
var
  mHits: TArray<Integer>;
begin
  mHits := TAtlasChoiceFilter.Matches(['Kunden.Logik', 'Kunden.Daten', 'Rechner'], 'kunden  LOG');
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual(0, mHits[0]);
  mHits := TAtlasChoiceFilter.Matches(['Kunden.Logik', 'Kunden.Daten', 'Rechner'], 'N');
  Assert.AreEqual(3, Integer(Length(mHits)));
  Assert.AreEqual(0, Integer(Length(TAtlasChoiceFilter.Matches(['Rechner'], 'x'))));
end;

procedure TAtlasChoiceFilterTests.PositionOfPreselection;
begin
  Assert.AreEqual(1, TAtlasChoiceFilter.PositionOf([2, 5, 7], 5));
  Assert.AreEqual(0, TAtlasChoiceFilter.PositionOf([2, 5, 7], 3), 'fehlt: erster Treffer');
  Assert.AreEqual(-1, TAtlasChoiceFilter.PositionOf(nil, 3));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasChoiceFilterTests);

end.
