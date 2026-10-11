unit Atlas.Common.Lsp.FuzzyMatch.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.FuzzyMatch;

type
  [TestFixture]
  TLspFuzzyMatchTests = class
  public
    [Test]
    procedure FindsAbbreviations;
    [Test]
    procedure FindsSubsequences;
    [Test]
    procedure RejectsNonMatches;
    [Test]
    procedure IgnoresCase;
    [Test]
    procedure RanksExactPrefixSubstringSubsequence;
    [Test]
    procedure PrefersWordStarts;
  end;

implementation

{ TLspFuzzyMatchTests }

procedure TLspFuzzyMatchTests.FindsAbbreviations;
begin
  Assert.IsTrue(TFuzzyMatch.Score('TBButton', 'TBB') > TFuzzyMatch.NoMatch);
  Assert.IsTrue(TFuzzyMatch.Score('GetTypeHierarchy', 'GTH') > TFuzzyMatch.NoMatch);
  Assert.IsTrue(TFuzzyMatch.Score('my_long_name', 'mln') > TFuzzyMatch.NoMatch);
end;

procedure TLspFuzzyMatchTests.FindsSubsequences;
begin
  Assert.IsTrue(TFuzzyMatch.Score('TStringList', 'strlst') > TFuzzyMatch.NoMatch);
  Assert.IsTrue(TFuzzyMatch.Score('TStringList.Create', 'stlcr') > TFuzzyMatch.NoMatch);
end;

procedure TLspFuzzyMatchTests.RejectsNonMatches;
begin
  Assert.AreEqual(TFuzzyMatch.NoMatch, TFuzzyMatch.Score('TStringList', 'xyz'));
  Assert.AreEqual(TFuzzyMatch.NoMatch, TFuzzyMatch.Score('TStringList', 'tsx'));
  Assert.AreEqual(TFuzzyMatch.NoMatch, TFuzzyMatch.Score('TStringList', ''));
  // Reihenfolge zählt.
  Assert.AreEqual(TFuzzyMatch.NoMatch, TFuzzyMatch.Score('TStringList', 'gr'));
end;

procedure TLspFuzzyMatchTests.IgnoresCase;
begin
  Assert.AreEqual(TFuzzyMatch.Score('TBButton', 'TBB'), TFuzzyMatch.Score('TBButton', 'tbb'));
  Assert.AreEqual(TFuzzyMatch.Score('Foo', 'foo'), TFuzzyMatch.Score('Foo', 'FOO'));
end;

procedure TLspFuzzyMatchTests.RanksExactPrefixSubstringSubsequence;
var
  Exact, Prefix, Substring, Subsequence: Integer;
begin
  Exact := TFuzzyMatch.Score('Liste', 'liste');
  Prefix := TFuzzyMatch.Score('ListeLeeren', 'liste');
  Substring := TFuzzyMatch.Score('TListe', 'liste');
  Subsequence := TFuzzyMatch.Score('LinkSetter', 'liste');
  Assert.IsTrue(Exact > Prefix);
  Assert.IsTrue(Prefix > Substring);
  Assert.IsTrue(Substring > Subsequence);
  Assert.IsTrue(Subsequence > TFuzzyMatch.NoMatch);
  // Kürzerer Name bei gleichem Präfix zuerst.
  Assert.IsTrue(TFuzzyMatch.Score('ListeA', 'liste') > TFuzzyMatch.Score('ListeAB', 'liste'));
end;

procedure TLspFuzzyMatchTests.PrefersWordStarts;
begin
  // G, T und H als Wortanfänge schlagen verstreute Kleinbuchstaben.
  Assert.IsTrue(TFuzzyMatch.Score('GetTypeHierarchy', 'gth') > TFuzzyMatch.Score('GothicHall', 'gth'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFuzzyMatchTests);

end.
