unit Atlas.Text.Fuzzy.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextFuzzyTests = class
  public
    [Test]
    [TestCase('Erstes Zeichen', 'TStringList,1,true')]
    [TestCase('CamelCase vor Kleinbuchstaben', 'TStringList,2,true')]
    [TestCase('Kleinbuchstabe im Wort', 'TStringList,3,false')]
    [TestCase('CamelCase nach Kleinbuchstaben', 'TStringList,8,true')]
    [TestCase('Akronym vor Wort', 'HTMLParser,4,false')]
    [TestCase('Akronym Ende vor Wort', 'HTMLParser,5,true')]
    [TestCase('Großbuchstabe in Großschreibung', 'ERROR_TOO_MANY_LINKS,2,false')]
    [TestCase('Nach Unterstrich', 'ERROR_TOO_MANY_LINKS,7,true')]
    [TestCase('Unterstrich nach Unterstrich', 'a__b,3,false')]
    [TestCase('Nach Punkt', 'a.b,3,true')]
    [TestCase('Ziffer nach Buchstabe', 'x2y,2,true')]
    [TestCase('Kleinbuchstabe nach Ziffer', 'x2y,3,true')]
    [TestCase('Ziffer nach Ziffer', 'x22,3,false')]
    procedure WordStart(const AName: string; AIndex: Integer; AExpected: Boolean);
    [Test]
    procedure WordStartsCamelCase;
    [Test]
    procedure BoundedSubsequenceAcceptsWordParts;
    [Test]
    procedure BoundedSubsequenceRejectsScattered;
    [Test]
    procedure EmptyPatternMatches;
    [Test]
    procedure EditDistanceWithLimit;
    [Test]
    procedure ClosestFindsTypos;
  end;

implementation

uses
  Atlas.Text.Fuzzy;

procedure TTextFuzzyTests.WordStart(const AName: string; AIndex: Integer; AExpected: Boolean);
begin
  Assert.AreEqual(AExpected, TTextFuzzy.IsWordStart(AName, AIndex));
end;

procedure TTextFuzzyTests.WordStartsCamelCase;
begin
  Assert.IsTrue(TTextFuzzy.MatchesWordStarts('TSL', 'TStringList'));
  Assert.IsTrue(TTextFuzzy.MatchesWordStarts('tsl', 'TStringList'));
  Assert.IsTrue(TTextFuzzy.MatchesWordStarts('gth', 'GetTypeHierarchy'));
  Assert.IsTrue(TTextFuzzy.MatchesWordStarts('ab', 'a.b'));
  Assert.IsFalse(TTextFuzzy.MatchesWordStarts('tst', 'TStringList'));
end;

procedure TTextFuzzyTests.BoundedSubsequenceAcceptsWordParts;
begin
  Assert.IsTrue(TTextFuzzy.MatchesBoundedSubsequence('stl', 'TStringList'));
  Assert.IsTrue(TTextFuzzy.MatchesBoundedSubsequence('strlis', 'TStringList'));
  Assert.IsTrue(TTextFuzzy.MatchesBoundedSubsequence('mln', 'my_long_name'));
  Assert.IsTrue(TTextFuzzy.MatchesBoundedSubsequence('x2y', 'x2y'));
end;

procedure TTextFuzzyTests.BoundedSubsequenceRejectsScattered;
begin
  Assert.IsFalse(TTextFuzzy.MatchesBoundedSubsequence('myLis', 'ERROR_TOO_MANY_LINKS'));
  Assert.IsFalse(TTextFuzzy.MatchesBoundedSubsequence('rg', 'TStringList'));
  Assert.IsFalse(TTextFuzzy.MatchesBoundedSubsequence('xyz', 'TStringList'));
end;

procedure TTextFuzzyTests.EmptyPatternMatches;
begin
  Assert.IsTrue(TTextFuzzy.MatchesBoundedSubsequence('', 'TStringList'));
  Assert.IsTrue(TTextFuzzy.MatchesWordStarts('', 'TStringList'));
end;

procedure TTextFuzzyTests.EditDistanceWithLimit;
begin
  Assert.AreEqual(0, TTextFuzzy.EditDistance('Destroy', 'DESTROY', 2));
  Assert.AreEqual(2, TTextFuzzy.EditDistance('Destory', 'Destroy', 2));
  Assert.AreEqual(1, TTextFuzzy.EditDistance('Lauf', 'Laufe', 2));
  // Über der Grenze: Grenze + 1.
  Assert.AreEqual(3, TTextFuzzy.EditDistance('Abc', 'Xyzuvw', 2));
end;

procedure TTextFuzzyTests.ClosestFindsTypos;
begin
  Assert.AreEqual('Destroy', TTextFuzzy.Closest('Destory', ['Create', 'Destroy', 'Free']));
  Assert.AreEqual('Laden', TTextFuzzy.Closest('Lade', ['Laden', 'Lader']));
  Assert.AreEqual('', TTextFuzzy.Closest('Ganzanders', ['Destroy']));
  // Kurze Namen: höchstens die Hälfte darf abweichen; der Name selbst ist kein Tippfehler.
  Assert.AreEqual('', TTextFuzzy.Closest('IX', ['IF']));
  Assert.AreEqual('', TTextFuzzy.Closest('Destroy', ['Destroy', 'Destroyed']));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextFuzzyTests);

end.
