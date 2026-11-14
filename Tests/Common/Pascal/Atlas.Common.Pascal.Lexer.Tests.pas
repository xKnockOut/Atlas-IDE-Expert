unit Atlas.Common.Pascal.Lexer.Tests;

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
    /// <summary>Sprungmarken wie @@End im asm-Block: das reservierte Wort hinter @ ist ein Bezeichner (#861).</summary>
    [Test]
    procedure ReservedWordAfterAtIsIdentifier;
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
    [Test]
    procedure NamesDirectives;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

const
  cKindNames: array[TPascalTokenKind] of string = (
    'Identifier', 'Keyword', 'Number', 'String', 'Char', 'Comment', 'Directive', 'Symbol', 'Unknown');

// Kurzform aller Token, z. B. "Keyword:begin|Identifier:x".
function Describe(const AText: string): string;
var
  mToken: TPascalToken;
begin
  Result := '';
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + cKindNames[mToken.Kind] + ':' + mToken.Text;
  end;
end;

{ TPascalLexerTests }

procedure TPascalLexerTests.SkipsWhitespaceAndLineBreaks;
begin
  Assert.AreEqual('', Describe('  '#9#13#10'  '));
  Assert.AreEqual('Identifier:a|Identifier:b', Describe(' a'#13#10#9'b '));
end;

procedure TPascalLexerTests.RecognizesKeywordsCaseInsensitive;
var
  mTokens: TArray<TPascalToken>;
begin
  Assert.AreEqual('Keyword:BEGIN|Keyword:End|Symbol:;', Describe('BEGIN End;'));
  mTokens := TPascalLexer.Tokenize('Begin');
  Assert.IsTrue(mTokens[0].IsKeyword('begin'));
  Assert.IsFalse(mTokens[0].IsKeyword('end'));
end;

procedure TPascalLexerTests.TreatsDirectivesAsIdentifiers;
begin
  Assert.AreEqual('Identifier:override|Identifier:virtual|Identifier:out', Describe('override virtual out'));
end;

procedure TPascalLexerTests.EscapedReservedWordIsIdentifier;
begin
  Assert.AreEqual('Identifier:&begin|Symbol:.|Identifier:Name', Describe('&begin.Name'));
  // #1137: && vor einem Bezeichner gehört zum Bezeichner.
  Assert.AreEqual('Identifier:TValue|Symbol:.|Identifier:&&op_Equality|Symbol:(', Describe('TValue.&&op_Equality('));
end;

procedure TPascalLexerTests.ReservedWordAfterAtIsIdentifier;
begin
  Assert.AreEqual('Identifier:JNZ|Symbol:@|Symbol:@|Identifier:End|Symbol:;|Symbol:@|Symbol:@|Identifier:end|' +
    'Symbol::|Keyword:end', Describe('JNZ @@End; @@end: end'));
  // Mit Abstand hinter @ bleibt es ein Schlüsselwort.
  Assert.AreEqual('Symbol:@|Keyword:end', Describe('@ end'));
end;

procedure TPascalLexerTests.ReadsNumbers;
begin
  Assert.AreEqual('Number:42|Number:3.14|Number:1e10|Number:2.5E-3|Number:1_000',
    Describe('42 3.14 1e10 2.5E-3 1_000'));
  Assert.AreEqual('Number:$FF|Number:$00_ff|Number:%1010|Number:&17', Describe('$FF $00_ff %1010 &17'));
  // #1142: führender Trenner wie bei $_FF.
  Assert.AreEqual('Number:%_0101|Number:$_FF', Describe('%_0101 $_FF'));
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
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('S := '''''''#13#10'  zeile ''eins'''#13#10'  zwei'#13#10'  '''''';');
  Assert.AreEqual<NativeInt>(4, Length(mTokens));
  Assert.AreEqual<TPascalTokenKind>(TPascalTokenKind.StringLiteral, mTokens[2].Kind);
  Assert.IsTrue(mTokens[2].Terminated);
  Assert.AreEqual(0, mTokens[2].StartPos.Line);
  Assert.AreEqual(5, mTokens[2].StartPos.Character);
  Assert.AreEqual(3, mTokens[2].EndPos.Line);
  Assert.AreEqual(5, mTokens[2].EndPos.Character);
  Assert.IsTrue(mTokens[3].IsSymbol(';'));
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
  mTokens: TArray<TPascalToken>;
begin
  // U+1F600 belegt zwei UTF-16-Codeeinheiten.
  mTokens := TPascalLexer.Tokenize('''a'#$D83D#$DE00''' x');
  Assert.AreEqual<NativeInt>(2, Length(mTokens));
  Assert.AreEqual(0, mTokens[0].StartPos.Line);
  Assert.AreEqual(0, mTokens[0].StartPos.Character);
  Assert.AreEqual(0, mTokens[0].EndPos.Line);
  Assert.AreEqual(5, mTokens[0].EndPos.Character);
  Assert.AreEqual(0, mTokens[1].StartPos.Line);
  Assert.AreEqual(6, mTokens[1].StartPos.Character);
  Assert.AreEqual(6, mTokens[1].Offset);
end;

procedure TPascalLexerTests.ReportsPositionsAcrossCrLf;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('unit A;'#13#10#13#10'  end.'#10'x'#13'y');
  Assert.AreEqual<NativeInt>(7, Length(mTokens));
  Assert.AreEqual(2, mTokens[3].StartPos.Line);
  Assert.AreEqual(2, mTokens[3].StartPos.Character);
  Assert.AreEqual(2, mTokens[3].EndPos.Line);
  Assert.AreEqual(5, mTokens[3].EndPos.Character);
  Assert.AreEqual(3, mTokens[5].StartPos.Line);
  Assert.AreEqual(0, mTokens[5].StartPos.Character);
  Assert.AreEqual(4, mTokens[6].StartPos.Line);
  Assert.AreEqual(0, mTokens[6].StartPos.Character);
end;

procedure TPascalLexerTests.MarksUnterminatedTokens;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('''offen'#10'x { ohne Ende');
  Assert.AreEqual<NativeInt>(3, Length(mTokens));
  Assert.AreEqual('''offen', mTokens[0].Text);
  Assert.IsFalse(mTokens[0].Terminated);
  Assert.AreEqual('x', mTokens[1].Text);
  Assert.AreEqual<TPascalTokenKind>(TPascalTokenKind.Comment, mTokens[2].Kind);
  Assert.IsFalse(mTokens[2].Terminated);

  mTokens := TPascalLexer.Tokenize('''''''' + #10'nie geschlossen');
  Assert.AreEqual<NativeInt>(1, Length(mTokens));
  Assert.IsFalse(mTokens[0].Terminated);
end;

procedure TPascalLexerTests.ReportsUnknownCharacters;
begin
  Assert.AreEqual('Identifier:a|Unknown:?|Unknown:"|Identifier:b', Describe('a ? " b'));
end;

procedure TPascalLexerTests.NamesDirectives;
begin
  Assert.AreEqual('IFDEF', TPascalLexer.DirectiveName('{$ifdef DEBUG}'));
  Assert.AreEqual('ENDREGION', TPascalLexer.DirectiveName('(*$EndRegion*)'));
  Assert.AreEqual('ELSE', TPascalLexer.DirectiveName('{$ELSE}'));
  Assert.AreEqual('', TPascalLexer.DirectiveName('{ kein $IFDEF }'));
  Assert.AreEqual('', TPascalLexer.DirectiveName('// {$IFDEF}'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalLexerTests);

end.
