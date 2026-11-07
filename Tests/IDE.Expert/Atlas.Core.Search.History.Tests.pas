unit Atlas.Core.Search.History.Tests;

// Tests für den Such- und Ersetzen-Verlauf der Atlas-Suchleiste (#893): Länge,
// Doppelte nach vorn, Blättern mit Pfeil hoch/runter, 0 = aus, Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
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
  mHistory: TAtlasSearchHistory;
begin
  mHistory := TAtlasSearchHistory.Create(20);
  try
    mHistory.Remember('a');
    mHistory.Remember('b');
    mHistory.Remember('c');
    mHistory.Remember('a');
    mHistory.Remember('');
    Assert.AreEqual('a|c|b', Joined(mHistory));
    mHistory.Remember('A');
    Assert.AreEqual('A|a|c|b', Joined(mHistory), 'Groß-/Kleinschreibung zählt');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.CapacityLimitsAndZeroTurnsHistoryOff;
var
  mHistory: TAtlasSearchHistory;
begin
  mHistory := TAtlasSearchHistory.Create(2);
  try
    mHistory.Remember('a');
    mHistory.Remember('b');
    mHistory.Remember('c');
    Assert.AreEqual('c|b', Joined(mHistory));
    mHistory.Capacity := 1;
    Assert.AreEqual('c', Joined(mHistory), 'kürzt sofort');
    mHistory.Capacity := 0;
    Assert.AreEqual('', Joined(mHistory));
    mHistory.Remember('d');
    Assert.AreEqual('', Joined(mHistory), 'search.history = 0: kein Verlauf');
    Assert.AreEqual('x', mHistory.Step('x', True));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.StepGoesOlderAndBackToTheTypedText;
var
  mHistory: TAtlasSearchHistory;
  mText: string;
begin
  mHistory := TAtlasSearchHistory.Create(20);
  try
    mHistory.Remember('alt');
    mHistory.Remember('mittel');
    mHistory.Remember('neu');
    mText := mHistory.Step('getippt', True);
    Assert.AreEqual('neu', mText);
    mText := mHistory.Step(mText, True);
    Assert.AreEqual('mittel', mText);
    mText := mHistory.Step(mText, True);
    Assert.AreEqual('alt', mText);
    mText := mHistory.Step(mText, True);
    Assert.AreEqual('alt', mText, 'am ältesten Eintrag bleibt es');
    mText := mHistory.Step(mText, False);
    Assert.AreEqual('mittel', mText);
    mText := mHistory.Step(mText, False);
    mText := mHistory.Step(mText, False);
    Assert.AreEqual('getippt', mText, 'unter den neuesten hinab kommt der getippte Text zurück');
    Assert.AreEqual('getippt', mHistory.Step(mText, False));
    // Nach Remember beginnt das Blättern von vorn.
    mHistory.Step('x', True);
    mHistory.Remember('x');
    Assert.AreEqual('neu', mHistory.Step('x', True));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.StepSkipsTheEntryAlreadyInTheField;
var
  mHistory: TAtlasSearchHistory;
begin
  mHistory := TAtlasSearchHistory.Create(20);
  try
    mHistory.Remember('vorige');
    mHistory.Remember('letzte');
    // Akzeptanzkriterium: Pfeil hoch holt die vorige Suche, auch wenn die letzte noch im Feld steht.
    Assert.AreEqual('vorige', mHistory.Step('letzte', True));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.TextRoundTripKeepsBothHistories;
var
  mSearch, mReplace, mSearchBack, mReplaceBack: TAtlasSearchHistory;
  mText: string;
begin
  mSearch := TAtlasSearchHistory.Create(20);
  mReplace := TAtlasSearchHistory.Create(20);
  mSearchBack := TAtlasSearchHistory.Create(20);
  mReplaceBack := TAtlasSearchHistory.Create(2);
  try
    mSearch.Remember('IntToStr\((\w+)\)');
    mSearch.Remember('Größe "x"');
    mReplace.Remember('$1.ToString');
    mReplace.Remember('a');
    mReplace.Remember('b');
    mText := TAtlasSearchHistories.ToText(mSearch, mReplace);
    Assert.IsTrue(TAtlasSearchHistories.FromText(mText, mSearchBack, mReplaceBack));
    Assert.AreEqual(Joined(mSearch), Joined(mSearchBack));
    Assert.AreEqual('b|a', Joined(mReplaceBack), 'die Länge der Einstellung gilt auch beim Laden');
  finally
    mSearch.Free;
    mReplace.Free;
    mSearchBack.Free;
    mReplaceBack.Free;
  end;
end;

procedure TAtlasSearchHistoryTests.BrokenTextIsRejected;
var
  mSearch, mReplace: TAtlasSearchHistory;
begin
  mSearch := TAtlasSearchHistory.Create(20);
  mReplace := TAtlasSearchHistory.Create(20);
  try
    mSearch.Remember('a');
    Assert.IsFalse(TAtlasSearchHistories.FromText('[1, 2', mSearch, mReplace));
    Assert.AreEqual('', Joined(mSearch));
    Assert.IsTrue(TAtlasSearchHistories.FromText('{"search": ["x", 3, ""], "replace": 7}', mSearch, mReplace));
    Assert.AreEqual('x', Joined(mSearch), 'nur Texte zählen');
    Assert.AreEqual('', Joined(mReplace));
  finally
    mSearch.Free;
    mReplace.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchHistoryTests);

end.
