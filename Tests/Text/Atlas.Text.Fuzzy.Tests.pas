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

initialization
  TDUnitX.RegisterTestFixture(TTextFuzzyTests);

end.
