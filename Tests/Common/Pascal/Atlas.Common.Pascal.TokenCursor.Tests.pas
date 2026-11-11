unit Atlas.Common.Pascal.TokenCursor.Tests;

// Tests des Token-Cursors der Prüfregeln: Ränder des Token-Arrays (Index -1, Length, leeres Array), Suche nach
// Offset, Code-Token über Kommentare und Direktiven hinweg, passende Klammern (unpaarig, in Strings, eckig).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTokenCursorTests = class
  public
    [Test]
    procedure AtOutsideGivesEmptyToken;
    [Test]
    procedure IsComparesKeywordsIdentifiersAndSymbols;
    [Test]
    procedure FromFindsFirstTokenAtOrAfterOffset;
    [Test]
    procedure ExactlyFindsOnlyTokenStartingAtOffset;
    [Test]
    procedure NextCodeSkipsCommentsAndDirectives;
    [Test]
    procedure PreviousCodeSkipsCommentsAndDirectives;
    [Test]
    procedure MatchingParenPairsNestedBrackets;
    [Test]
    procedure MatchingParenIgnoresParensInStrings;
    [Test]
    procedure MatchingParenWithoutPartnerGivesMinusOne;
    [Test]
    procedure MatchingParenStopsBeforeStop;
    [Test]
    procedure EmptyArrayIsNeverAnError;
    [Test]
    procedure IsKeywordInChecksKind;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor;

function CursorOf(const AText: string): TTokenCursor;
begin
  Result := TTokenCursor.Create(TPascalLexer.Tokenize(AText));
end;

function IndexOfText(const ACursor: TTokenCursor; const AText: string; ASkip: Integer = 0): Integer;
var
  mIndex, mSeen: Integer;
begin
  mSeen := 0;
  for mIndex := 0 to ACursor.Count - 1 do
  begin
    if ACursor.At(mIndex).Text = AText then
    begin
      if mSeen = ASkip then
      begin
        Exit(mIndex);
      end;
      Inc(mSeen);
    end;
  end;
  Result := -1;
end;

procedure TTokenCursorTests.AtOutsideGivesEmptyToken;
var
  mCursor: TTokenCursor;
begin
  mCursor := CursorOf('a := b;');
  Assert.AreEqual('a', mCursor.At(0).Text);
  Assert.IsTrue(mCursor.At(-1).Kind = TPascalTokenKind.Unknown);
  Assert.AreEqual('', mCursor.At(-1).Text);
  Assert.AreEqual(-1, mCursor.At(-1).Offset);
  Assert.IsTrue(mCursor.At(mCursor.Count).Kind = TPascalTokenKind.Unknown);
  Assert.AreEqual('', mCursor.At(mCursor.Count).Text);
  Assert.IsFalse(mCursor.InRange(-1));
  Assert.IsFalse(mCursor.InRange(mCursor.Count));
  Assert.IsTrue(mCursor.InRange(mCursor.Count - 1));
end;

procedure TTokenCursorTests.IsComparesKeywordsIdentifiersAndSymbols;
var
  mCursor: TTokenCursor;
begin
  mCursor := CursorOf('Begin Foo(. x .) ''end'' {end} end');
  Assert.IsTrue(mCursor.Is_(0, 'begin'));
  Assert.IsTrue(mCursor.Is_(1, 'foo'));
  Assert.IsTrue(mCursor.Is_(2, '['));
  Assert.IsTrue(mCursor.Is_(4, ']'));
  Assert.IsFalse(mCursor.Is_(IndexOfText(mCursor, '''end'''), 'end'), 'String ist kein Schlüsselwort');
  Assert.IsFalse(mCursor.Is_(IndexOfText(mCursor, '{end}'), 'end'), 'Kommentar ist kein Schlüsselwort');
  Assert.IsTrue(mCursor.Is_(mCursor.Count - 1, 'END'));
  Assert.IsFalse(mCursor.Is_(-1, 'begin'));
  Assert.IsFalse(mCursor.Is_(mCursor.Count, 'end'));
end;

procedure TTokenCursorTests.FromFindsFirstTokenAtOrAfterOffset;
var
  mCursor: TTokenCursor;
begin
  // Offsets: a=0, :==2, b=5, ;=6
  mCursor := CursorOf('a := b;');
  Assert.AreEqual(0, mCursor.From(-5));
  Assert.AreEqual(0, mCursor.From(0));
  Assert.AreEqual(1, mCursor.From(1));
  Assert.AreEqual(1, mCursor.From(2));
  Assert.AreEqual(2, mCursor.From(5));
  Assert.AreEqual(3, mCursor.From(6));
  Assert.AreEqual(mCursor.Count, mCursor.From(7));
  Assert.AreEqual(mCursor.Count, mCursor.From(MaxInt));
end;

procedure TTokenCursorTests.ExactlyFindsOnlyTokenStartingAtOffset;
var
  mCursor: TTokenCursor;
begin
  mCursor := CursorOf('a := b;');
  Assert.AreEqual(0, mCursor.Exactly(0));
  Assert.AreEqual(-1, mCursor.Exactly(1));
  Assert.AreEqual(1, mCursor.Exactly(2));
  Assert.AreEqual(-1, mCursor.Exactly(3));
  Assert.AreEqual(3, mCursor.Exactly(6));
  Assert.AreEqual(-1, mCursor.Exactly(7));
  Assert.AreEqual(-1, mCursor.Exactly(-1));
end;

procedure TTokenCursorTests.NextCodeSkipsCommentsAndDirectives;
var
  mCursor: TTokenCursor;
begin
  mCursor := CursorOf('a {x} {$IFDEF D} // y'#10'b {z}');
  Assert.AreEqual(0, mCursor.NextCode(0));
  Assert.AreEqual(IndexOfText(mCursor, 'b'), mCursor.NextCode(1));
  Assert.AreEqual(mCursor.Count, mCursor.NextCode(IndexOfText(mCursor, 'b') + 1), 'nur Kommentar dahinter');
  Assert.AreEqual(mCursor.Count, mCursor.NextCode(mCursor.Count));
  Assert.AreEqual(mCursor.Count, mCursor.NextCode(MaxInt));
  Assert.AreEqual(0, mCursor.NextCode(-1), 'negativ zählt wie 0');
end;

procedure TTokenCursorTests.PreviousCodeSkipsCommentsAndDirectives;
var
  mCursor: TTokenCursor;
  mB: Integer;
begin
  mCursor := CursorOf('{c} a {x} {$IFDEF D} b {z}');
  mB := IndexOfText(mCursor, 'b');
  Assert.AreEqual(IndexOfText(mCursor, 'a'), mCursor.PreviousCode(mB));
  Assert.AreEqual(-1, mCursor.PreviousCode(IndexOfText(mCursor, 'a')), 'nur Kommentar davor');
  Assert.AreEqual(mB, mCursor.PreviousCode(mCursor.Count));
  Assert.AreEqual(mB, mCursor.PreviousCode(MaxInt), 'über Length zählt wie Length');
  Assert.AreEqual(-1, mCursor.PreviousCode(0));
  Assert.AreEqual(-1, mCursor.PreviousCode(-1));
  Assert.AreEqual(-1, mCursor.PreviousCode(-100));
end;

procedure TTokenCursorTests.MatchingParenPairsNestedBrackets;
var
  mCursor: TTokenCursor;
begin
  // F ( a [ 1 ] , ( b ) ) ;
  // 0 1 2 3 4 5 6 7 8 9 10 11
  mCursor := CursorOf('F(a[1], (b));');
  Assert.AreEqual(10, mCursor.MatchingParen(1));
  Assert.AreEqual(5, mCursor.MatchingParen(3));
  Assert.AreEqual(9, mCursor.MatchingParen(7));
  Assert.AreEqual(-1, mCursor.MatchingParen(0), 'keine öffnende Klammer');
  Assert.AreEqual(-1, mCursor.MatchingParen(10), 'schließende Klammer');
end;

procedure TTokenCursorTests.MatchingParenIgnoresParensInStrings;
var
  mCursor: TTokenCursor;
begin
  mCursor := CursorOf('F('')'', ''('', {)} x);');
  Assert.AreEqual(IndexOfText(mCursor, ')'), mCursor.MatchingParen(1));
  Assert.AreEqual(mCursor.Count - 2, mCursor.MatchingParen(1));
end;

procedure TTokenCursorTests.MatchingParenWithoutPartnerGivesMinusOne;
var
  mCursor: TTokenCursor;
begin
  mCursor := CursorOf('F((a)');
  Assert.AreEqual(-1, mCursor.MatchingParen(1));
  Assert.AreEqual(4, mCursor.MatchingParen(2));
  Assert.AreEqual(-1, mCursor.MatchingParen(-1));
  Assert.AreEqual(-1, mCursor.MatchingParen(mCursor.Count));
end;

procedure TTokenCursorTests.MatchingParenStopsBeforeStop;
var
  mTokens: TArray<TPascalToken>;
begin
  // F ( a ) ;
  mTokens := TPascalLexer.Tokenize('F(a);');
  Assert.AreEqual(3, MatchingParen(mTokens, 1, 4));
  Assert.AreEqual(-1, MatchingParen(mTokens, 1, 3), 'Stop schließt den Index aus');
  Assert.AreEqual(-1, MatchingParen(mTokens, 1, 1));
  Assert.AreEqual(3, MatchingParen(mTokens, 1, MaxInt));
end;

procedure TTokenCursorTests.EmptyArrayIsNeverAnError;
var
  mCursor: TTokenCursor;
begin
  mCursor := TTokenCursor.Create(nil);
  Assert.AreEqual(0, mCursor.Count);
  Assert.AreEqual('', mCursor.At(0).Text);
  Assert.IsFalse(mCursor.Is_(0, 'begin'));
  Assert.AreEqual(0, mCursor.From(0));
  Assert.AreEqual(-1, mCursor.Exactly(0));
  Assert.AreEqual(0, mCursor.NextCode(0));
  Assert.AreEqual(-1, mCursor.PreviousCode(0));
  Assert.AreEqual(-1, mCursor.MatchingParen(0));
end;

procedure TTokenCursorTests.IsKeywordInChecksKind;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('Begin x ''end''');
  Assert.IsTrue(IsKeywordIn(mTokens[0], ['end', 'begin']));
  Assert.IsFalse(IsKeywordIn(mTokens[0], ['end']));
  Assert.IsFalse(IsKeywordIn(mTokens[1], ['x']), 'Bezeichner ist kein Schlüsselwort');
  Assert.IsFalse(IsKeywordIn(mTokens[2], ['end']), 'String ist kein Schlüsselwort');
  Assert.IsFalse(IsKeywordIn(mTokens[0], []));
end;

initialization
  TDUnitX.RegisterTestFixture(TTokenCursorTests);

end.
