unit Atlas.Core.Search.History.Tests;

// Tests für den Such- und Ersetzen-Verlauf der Atlas-Suchleiste (#893): Länge,
// Doppelte nach vorn, Blättern mit Pfeil hoch/runter, 0 = aus, Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSearchHistoryTests = class
  public
    [Test]
    procedure RememberPutsNewestFirstAndMovesDuplicatesUp;
    [Test]
    procedure CapacityLimitsAndZeroTurnsHistoryOff;
    [Test]
    procedure StepGoesOlderAndBackToTheTypedText;
    [Test]
    procedure StepSkipsTheEntryAlreadyInTheField;
    [Test]
    procedure TextRoundTripKeepsBothHistories;
    [Test]
    procedure BrokenTextIsRejected;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Search.History;

function Joined(AHistory: TAtlasSearchHistory): string;
begin
  Result := string.Join('|', AHistory.Items);
end;

procedure TAtlasSearchHistoryTests.RememberPutsNewestFirstAndMovesDuplicatesUp;
var
  History: TAtlasSearchHistory;
begin
  History := TAtlasSearchHistory.Create(20);
  try
    History.Remember('a');
    History.Remember('b');
    History.Remember('c');
    History.Remember('a');
    History.Remember('');
    Assert.AreEqual('a|c|b', Joined(History));
    History.Remember('A');
    Assert.AreEqual('A|a|c|b', Joined(History), 'Groß-/Kleinschreibung zählt');
  finally
    History.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.CapacityLimitsAndZeroTurnsHistoryOff;
var
  History: TAtlasSearchHistory;
begin
  History := TAtlasSearchHistory.Create(2);
  try
    History.Remember('a');
    History.Remember('b');
    History.Remember('c');
    Assert.AreEqual('c|b', Joined(History));
    History.Capacity := 1;
    Assert.AreEqual('c', Joined(History), 'kürzt sofort');
    History.Capacity := 0;
    Assert.AreEqual('', Joined(History));
    History.Remember('d');
    Assert.AreEqual('', Joined(History), 'search.history = 0: kein Verlauf');
    Assert.AreEqual('x', History.Step('x', True));
  finally
    History.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.StepGoesOlderAndBackToTheTypedText;
var
  History: TAtlasSearchHistory;
  Text: string;
begin
  History := TAtlasSearchHistory.Create(20);
  try
    History.Remember('alt');
    History.Remember('mittel');
    History.Remember('neu');
    Text := History.Step('getippt', True);
    Assert.AreEqual('neu', Text);
    Text := History.Step(Text, True);
    Assert.AreEqual('mittel', Text);
    Text := History.Step(Text, True);
    Assert.AreEqual('alt', Text);
    Text := History.Step(Text, True);
    Assert.AreEqual('alt', Text, 'am ältesten Eintrag bleibt es');
    Text := History.Step(Text, False);
    Assert.AreEqual('mittel', Text);
    Text := History.Step(Text, False);
    Text := History.Step(Text, False);
    Assert.AreEqual('getippt', Text, 'unter den neuesten hinab kommt der getippte Text zurück');
    Assert.AreEqual('getippt', History.Step(Text, False));
    // Nach Remember beginnt das Blättern von vorn.
    History.Step('x', True);
    History.Remember('x');
    Assert.AreEqual('neu', History.Step('x', True));
  finally
    History.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.StepSkipsTheEntryAlreadyInTheField;
var
  History: TAtlasSearchHistory;
begin
  History := TAtlasSearchHistory.Create(20);
  try
    History.Remember('vorige');
    History.Remember('letzte');
    // Akzeptanzkriterium: Pfeil hoch holt die vorige Suche, auch wenn die letzte noch im Feld steht.
    Assert.AreEqual('vorige', History.Step('letzte', True));
  finally
    History.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.TextRoundTripKeepsBothHistories;
var
  Search, Replace, SearchBack, ReplaceBack: TAtlasSearchHistory;
  Text: string;
begin
  Search := TAtlasSearchHistory.Create(20);
  Replace := TAtlasSearchHistory.Create(20);
  SearchBack := TAtlasSearchHistory.Create(20);
  ReplaceBack := TAtlasSearchHistory.Create(2);
  try
    Search.Remember('IntToStr\((\w+)\)');
    Search.Remember('Größe "x"');
    Replace.Remember('$1.ToString');
    Replace.Remember('a');
    Replace.Remember('b');
    Text := TAtlasSearchHistories.ToText(Search, Replace);
    Assert.IsTrue(TAtlasSearchHistories.FromText(Text, SearchBack, ReplaceBack));
    Assert.AreEqual(Joined(Search), Joined(SearchBack));
    Assert.AreEqual('b|a', Joined(ReplaceBack), 'die Länge der Einstellung gilt auch beim Laden');
  finally
    Search.Free;
    Replace.Free;
    SearchBack.Free;
    ReplaceBack.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.BrokenTextIsRejected;
var
  Search, Replace: TAtlasSearchHistory;
begin
  Search := TAtlasSearchHistory.Create(20);
  Replace := TAtlasSearchHistory.Create(20);
  try
    Search.Remember('a');
    Assert.IsFalse(TAtlasSearchHistories.FromText('[1, 2', Search, Replace));
    Assert.AreEqual('', Joined(Search));
    Assert.IsTrue(TAtlasSearchHistories.FromText('{"search": ["x", 3, ""], "replace": 7}', Search, Replace));
    Assert.AreEqual('x', Joined(Search), 'nur Texte zählen');
    Assert.AreEqual('', Joined(Replace));
  finally
    Search.Free;
    Replace.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchHistoryTests);

end.
