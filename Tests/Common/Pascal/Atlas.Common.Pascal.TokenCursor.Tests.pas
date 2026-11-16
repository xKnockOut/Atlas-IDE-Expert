unit Atlas.Common.Pascal.TokenCursor.Tests;

// Tests des Token-Cursors der Prüfregeln: Ränder des Token-Arrays (Index -1, Length, leeres Array), Suche nach
// Offset und nach Position, Token und Bezeichner unter dem Cursor, Code-Token über Kommentare und Direktiven
// hinweg, passende Klammern (unpaarig, in Strings, eckig, im Text).

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
    [Test]
    procedure TokenFromPositionFindsFirstTokenAtOrAfter;
    [Test]
    procedure TokenUpToPositionFindsLastTokenAtOrBefore;
    [Test]
    procedure IdentifierAtFindsWordUnderOrBeforeCursor;
    [Test]
    procedure TokenTouchingPrefersFrontTokenAndKeepsLine;
    [Test]
    procedure IdentifierAtMatchesLinearSearch;
    [Test]
    procedure MatchingParenInText;
    [Test]
    procedure CodeIndexesFindOffsetAndClosingParen;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor;

function CursorOf(const AText: string): TTokenCursor;
begin
  Result := TTokenCursor.Create(TPascalLexer.Tokenize(AText));
end;

function IndexOfText(const ACursor: TTokenCursor; const AText: string; ASkip: Integer): Integer; overload;
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

function IndexOfText(const ACursor: TTokenCursor; const AText: string): Integer; overload;
begin
  Result := IndexOfText(ACursor, AText, 0);
end;

{ TTokenCursorTests }

procedure TTokenCursorTests.AtOutsideGivesEmptyToken;
var
  mCursor: TTokenCursor;
begin
  mCursor := CursorOf('a := b;');
  Assert.AreEqual('a', mCursor.At(0).Text);
  Assert.AreEqual<TPascalTokenKind>(TPascalTokenKind.Unknown, mCursor.At(-1).Kind);
  Assert.AreEqual('', mCursor.At(-1).Text);
  Assert.AreEqual(-1, mCursor.At(-1).Offset);
  Assert.AreEqual<TPascalTokenKind>(TPascalTokenKind.Unknown, mCursor.At(mCursor.Count).Kind);
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

function At(ALine, ACharacter: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(ALine, ACharacter);
end;

procedure TTokenCursorTests.TokenFromPositionFindsFirstTokenAtOrAfter;
var
  mTokens: TArray<TPascalToken>;
begin
  // a := b  (a 0–1, := 2–4, b 5–6)
  mTokens := TPascalLexer.Tokenize('a := b');
  Assert.AreEqual(0, TokenFromPosition(mTokens, At(0, 0)));
  Assert.AreEqual(1, TokenFromPosition(mTokens, At(0, 1)));
  Assert.AreEqual(1, TokenFromPosition(mTokens, At(0, 2)));
  Assert.AreEqual(2, TokenFromPosition(mTokens, At(0, 3)));
  Assert.AreEqual(3, TokenFromPosition(mTokens, At(0, 6)), 'dahinter: Length');
  Assert.AreEqual(3, TokenFromPosition(mTokens, At(1, 0)));
  Assert.AreEqual(0, TokenFromPosition(nil, At(0, 0)));
end;

procedure TTokenCursorTests.TokenUpToPositionFindsLastTokenAtOrBefore;
var
  mTokens: TArray<TPascalToken>;
begin
  // _a := b  (a 1–2, := 3–5, b 6–7)
  mTokens := TPascalLexer.Tokenize(' a := b');
  Assert.AreEqual(-1, TokenUpToPosition(mTokens, At(0, 0)), 'vor dem ersten Token');
  Assert.AreEqual(0, TokenUpToPosition(mTokens, At(0, 1)));
  Assert.AreEqual(0, TokenUpToPosition(mTokens, At(0, 2)));
  Assert.AreEqual(1, TokenUpToPosition(mTokens, At(0, 3)));
  Assert.AreEqual(2, TokenUpToPosition(mTokens, At(0, 9)));
  Assert.AreEqual(2, TokenUpToPosition(mTokens, At(3, 0)));
  Assert.AreEqual(-1, TokenUpToPosition(nil, At(0, 0)));
end;

procedure TTokenCursorTests.IdentifierAtFindsWordUnderOrBeforeCursor;
var
  mTokens: TArray<TPascalToken>;
begin
  // a.bc := x  (a 0–1, . 1–2, bc 2–4, := 5–7, x 8–9)
  mTokens := TPascalLexer.Tokenize('a.bc := x');
  Assert.AreEqual(0, IdentifierAt(mTokens, At(0, 0)));
  Assert.AreEqual(0, IdentifierAt(mTokens, At(0, 1)), 'direkt hinter a gilt das vordere Token');
  Assert.AreEqual(2, IdentifierAt(mTokens, At(0, 2)));
  Assert.AreEqual(2, IdentifierAt(mTokens, At(0, 3)));
  Assert.AreEqual(2, IdentifierAt(mTokens, At(0, 4)), 'direkt hinter dem Wort');
  Assert.AreEqual(-1, IdentifierAt(mTokens, At(0, 5)), 'auf dem Symbol');
  Assert.AreEqual(4, IdentifierAt(mTokens, At(0, 9)));
  Assert.AreEqual(-1, IdentifierAt(mTokens, At(1, 0)));
  Assert.AreEqual(-1, IdentifierAt(nil, At(0, 0)));
end;

procedure TTokenCursorTests.TokenTouchingPrefersFrontTokenAndKeepsLine;
var
  mTokens: TArray<TPascalToken>;
  mAll: TPascalTokenKinds;
begin
  mAll := [Low(TPascalTokenKind)..High(TPascalTokenKind)];
  // F(b)  (F 0–1, ( 1–2, b 2–3, ) 3–4)
  mTokens := TPascalLexer.Tokenize('F(b)');
  Assert.AreEqual(0, TokenTouching(mTokens, At(0, 1), mAll), 'F und ( grenzen aneinander: das vordere');
  Assert.AreEqual(1, TokenTouching(mTokens, At(0, 1), mAll - [TPascalTokenKind.Identifier]));
  // Kommentar über zwei Zeilen: { x LF y } z  (Kommentar (0,0)–(1,3), z (1,4)–(1,5))
  mTokens := TPascalLexer.Tokenize('{ x'#10'y } z');
  Assert.AreEqual(-1, TokenTouching(mTokens, At(0, 1), mAll), 'endet nicht in der Zeile des Cursors');
  Assert.AreEqual(0, TokenTouching(mTokens, At(1, 2), mAll));
  Assert.AreEqual(1, TokenTouching(mTokens, At(1, 4), mAll));
  Assert.AreEqual(-1, TokenTouching(mTokens, At(1, 4), [TPascalTokenKind.Comment]));
end;

/// <summary>Die frühere lineare Suche der LSP-Funktionen (References, Rename, Dokument-Hervorhebung,
/// Signatur ändern), als Vergleich für IdentifierAt.</summary>
function LinearIdentifierAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if (mToken.StartPos.Line > APosition.Line) or
      ((mToken.StartPos.Line = APosition.Line) and (mToken.StartPos.Character > APosition.Character)) then
    begin
      Break;
    end;
    if (mToken.Kind = TPascalTokenKind.Identifier) and (mToken.EndPos.Line = APosition.Line) and
      (APosition.Character <= mToken.EndPos.Character) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TTokenCursorTests.IdentifierAtMatchesLinearSearch;
const
  cText = 'unit U;'#13#10'{ Kommentar'#13#10'  über Zeilen } procedure A.Bc(x: Integer);'#10 +
    'begin'#13#10'  Foo(x,y);  // Ende'#13#10'  s := ''a''#13+Bar;'#13#10'end.';
var
  mTokens: TArray<TPascalToken>;
  mLine, mCharacter: Integer;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  for mLine := 0 to 7 do
  begin
    for mCharacter := 0 to 50 do
    begin
      Assert.AreEqual(LinearIdentifierAt(mTokens, At(mLine, mCharacter)), IdentifierAt(mTokens,
        At(mLine, mCharacter)), Format('Zeile %d, Spalte %d', [mLine, mCharacter]));
    end;
  end;
end;

procedure TTokenCursorTests.MatchingParenInText;
begin
  // F(a(b), c) x: ( an 2 und 4, ) an 6 und 10
  Assert.AreEqual(10, MatchingParen('F(a(b), c) x', 2));
  Assert.AreEqual(6, MatchingParen('F(a(b), c) x', 4));
  Assert.AreEqual(0, MatchingParen('F(a(b), c) x', 1), 'keine öffnende Klammer');
  Assert.AreEqual(0, MatchingParen('(a', 1), 'ohne Gegenstück');
  Assert.AreEqual(0, MatchingParen('(a)', 0));
  Assert.AreEqual(0, MatchingParen('(a)', 4));
  Assert.AreEqual(0, MatchingParen('', 1));
end;

procedure TTokenCursorTests.CodeIndexesFindOffsetAndClosingParen;
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mIndex: Integer;
begin
  // Code-Token ohne Kommentar: F ( a [ 1 ] , ( b ) ) ;
  //                             0 1 2 3 4 5 6 7 8 9 10 11
  mTokens := TPascalLexer.Tokenize('F({c}a[1], (b));');
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsTrivia(mTokens[mIndex]) then
    begin
      SetLength(mCode, Length(mCode) + 1);
      mCode[High(mCode)] := mIndex;
    end;
  end;
  Assert.AreEqual(12, Integer(Length(mCode)));
  Assert.AreEqual(2, CodeIndexAt(mTokens, mCode, 5), 'a beginnt bei 5');
  Assert.AreEqual(2, CodeIndexAt(mTokens, mCode, 3), 'im Kommentar: nächstes Code-Token');
  Assert.AreEqual(0, CodeIndexAt(mTokens, mCode, 0));
  Assert.AreEqual(12, CodeIndexAt(mTokens, mCode, 100), 'hinter dem Ende');
  Assert.AreEqual(10, CodeClosingParen(mTokens, mCode, 1));
  Assert.AreEqual(5, CodeClosingParen(mTokens, mCode, 3));
  Assert.AreEqual(9, CodeClosingParen(mTokens, mCode, 7));
  Assert.AreEqual(-1, CodeClosingParen(mTokens, mCode, 8), 'nach b schließt nichts mehr auf');
end;

initialization
  TDUnitX.RegisterTestFixture(TTokenCursorTests);

end.
