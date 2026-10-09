unit Argus.Common.Pascal.Lexer.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalLexerTests = class
  public
    [Test]
    procedure SkipsWhitespaceAndLineBreaks;
    [Test]
    procedure RecognizesKeywordsCaseInsensitive;
    [Test]
    procedure TreatsDirectivesAsIdentifiers;
    [Test]
    procedure EscapedReservedWordIsIdentifier;
    [Test]
    procedure ReadsNumbers;
    [Test]
    procedure KeepsRangeOperatorAfterNumber;
    [Test]
    procedure ReadsStringsWithEscapedQuotes;
    [Test]
    procedure ReadsCharLiterals;
    [Test]
    procedure ReadsMultilineString;
    [Test]
    procedure ReadsCommentsAndDirectives;
    [Test]
    procedure ReadsSymbols;
    [Test]
    procedure ReportsPositionsInUtf16;
    [Test]
    procedure ReportsPositionsAcrossCrLf;
    [Test]
    procedure MarksUnterminatedTokens;
    [Test]
    procedure ReportsUnknownCharacters;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer;

const
  KindNames: array[TPascalTokenKind] of string = (
    'Identifier', 'Keyword', 'Number', 'String', 'Char', 'Comment', 'Directive', 'Symbol', 'Unknown');

// Kurzform aller Token, z. B. "Keyword:begin|Identifier:x".
function Describe(const AText: string): string;
var
  Token: TPascalToken;
begin
  Result := '';
  for Token in TPascalLexer.Tokenize(AText) do
  begin
    if Result <> '' then
      Result := Result + '|';
    Result := Result + KindNames[Token.Kind] + ':' + Token.Text;
  end;
end;

function Position(ALine, ACharacter: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(ALine, ACharacter);
end;

{ TPascalLexerTests }

procedure TPascalLexerTests.SkipsWhitespaceAndLineBreaks;
begin
  Assert.AreEqual('', Describe('  '#9#13#10'  '));
  Assert.AreEqual('Identifier:a|Identifier:b', Describe(' a'#13#10#9'b '));
end;

procedure TPascalLexerTests.RecognizesKeywordsCaseInsensitive;
var
  Tokens: TArray<TPascalToken>;
begin
  Assert.AreEqual('Keyword:BEGIN|Keyword:End|Symbol:;', Describe('BEGIN End;'));
  Tokens := TPascalLexer.Tokenize('Begin');
  Assert.IsTrue(Tokens[0].IsKeyword('begin'));
  Assert.IsFalse(Tokens[0].IsKeyword('end'));
end;

procedure TPascalLexerTests.TreatsDirectivesAsIdentifiers;
begin
  Assert.AreEqual('Identifier:override|Identifier:virtual|Identifier:out', Describe('override virtual out'));
end;

procedure TPascalLexerTests.EscapedReservedWordIsIdentifier;
begin
  Assert.AreEqual('Identifier:&begin|Symbol:.|Identifier:Name', Describe('&begin.Name'));
end;

procedure TPascalLexerTests.ReadsNumbers;
begin
  Assert.AreEqual('Number:42|Number:3.14|Number:1e10|Number:2.5E-3|Number:1_000',
    Describe('42 3.14 1e10 2.5E-3 1_000'));
  Assert.AreEqual('Number:$FF|Number:$00_ff|Number:%1010|Number:&17', Describe('$FF $00_ff %1010 &17'));
end;

procedure TPascalLexerTests.KeepsRangeOperatorAfterNumber;
begin
  Assert.AreEqual('Number:1|Symbol:..|Number:10', Describe('1..10'));
  Assert.AreEqual('Identifier:x|Symbol:.|Identifier:e', Describe('x.e'));
end;

procedure TPascalLexerTests.ReadsStringsWithEscapedQuotes;
begin
  Assert.AreEqual('String:''it''''s''|Symbol:+|String:''''', Describe('''it''''s'' + '''''));
end;

procedure TPascalLexerTests.ReadsCharLiterals;
begin
  Assert.AreEqual('String:''a''|Char:#13|Char:#$0A|String:''b''', Describe('''a''#13#$0A''b'''));
end;

procedure TPascalLexerTests.ReadsMultilineString;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize('S := '''''''#13#10'  zeile ''eins'''#13#10'  zwei'#13#10'  '''''';');
  Assert.AreEqual<NativeInt>(4, Length(Tokens));
  Assert.AreEqual(TPascalTokenKind.StringLiteral, Tokens[2].Kind);
  Assert.IsTrue(Tokens[2].Terminated);
  Assert.IsTrue(Position(0, 5) = Tokens[2].StartPos);
  Assert.IsTrue(Position(3, 5) = Tokens[2].EndPos);
  Assert.IsTrue(Tokens[3].IsSymbol(';'));
end;

procedure TPascalLexerTests.ReadsCommentsAndDirectives;
begin
  Assert.AreEqual('Comment:// Zeile|Identifier:x', Describe('// Zeile'#13#10'x'));
  Assert.AreEqual('Comment:{ Block'#10' }|Directive:{$IFDEF DEBUG}|Comment:(* alt *)|Directive:(*$R+*)',
    Describe('{ Block'#10' } {$IFDEF DEBUG} (* alt *) (*$R+*)'));
  // Kommentare sind nicht verschachtelt: (* endet am ersten *).
  Assert.AreEqual('Comment:(* { *)|Unknown:}', Describe('(* { *)}'));
end;

procedure TPascalLexerTests.ReadsSymbols;
begin
  Assert.AreEqual('Identifier:a|Symbol::=|Identifier:b|Symbol:<>|Identifier:c|Symbol:;',
    Describe('a:=b<>c;'));
  Assert.AreEqual('Symbol:<=|Symbol:>=|Symbol:^|Symbol:@|Symbol:[|Symbol:]|Symbol:(.|Symbol:.)',
    Describe('<= >= ^ @ [ ] (. .)'));
end;

procedure TPascalLexerTests.ReportsPositionsInUtf16;
var
  Tokens: TArray<TPascalToken>;
begin
  // U+1F600 belegt zwei UTF-16-Codeeinheiten.
  Tokens := TPascalLexer.Tokenize('''a'#$D83D#$DE00''' x');
  Assert.AreEqual<NativeInt>(2, Length(Tokens));
  Assert.IsTrue(Position(0, 0) = Tokens[0].StartPos);
  Assert.IsTrue(Position(0, 5) = Tokens[0].EndPos);
  Assert.IsTrue(Position(0, 6) = Tokens[1].StartPos);
  Assert.AreEqual(6, Tokens[1].Offset);
end;

procedure TPascalLexerTests.ReportsPositionsAcrossCrLf;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize('unit A;'#13#10#13#10'  end.'#10'x'#13'y');
  Assert.AreEqual<NativeInt>(7, Length(Tokens));
  Assert.IsTrue(Position(2, 2) = Tokens[3].StartPos);
  Assert.IsTrue(Position(2, 5) = Tokens[3].EndPos);
  Assert.IsTrue(Position(3, 0) = Tokens[5].StartPos);
  Assert.IsTrue(Position(4, 0) = Tokens[6].StartPos);
end;

procedure TPascalLexerTests.MarksUnterminatedTokens;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize('''offen'#10'x { ohne Ende');
  Assert.AreEqual<NativeInt>(3, Length(Tokens));
  Assert.AreEqual('''offen', Tokens[0].Text);
  Assert.IsFalse(Tokens[0].Terminated);
  Assert.AreEqual('x', Tokens[1].Text);
  Assert.AreEqual(TPascalTokenKind.Comment, Tokens[2].Kind);
  Assert.IsFalse(Tokens[2].Terminated);

  Tokens := TPascalLexer.Tokenize('''''''' + #10'nie geschlossen');
  Assert.AreEqual<NativeInt>(1, Length(Tokens));
  Assert.IsFalse(Tokens[0].Terminated);
end;

procedure TPascalLexerTests.ReportsUnknownCharacters;
begin
  Assert.AreEqual('Identifier:a|Unknown:?|Unknown:"|Identifier:b', Describe('a ? " b'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalLexerTests);

end.
