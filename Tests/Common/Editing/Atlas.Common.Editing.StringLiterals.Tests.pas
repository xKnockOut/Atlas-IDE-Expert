unit Atlas.Common.Editing.StringLiterals.Tests;

// Tests für Klartext und String-Literal (#312): Sonderzeichen, leere Zeilen,
// jede Einstellung und der Round-Trip Literal → Klartext → Literal.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStringLiteralsTests = class
  public
    [Test]
    procedure QuoteSpecialCharacters;
    [Test]
    procedure ConcatRoundTrip;
    [Test]
    procedure AutoStyleDependsOnVersion;
    [Test]
    procedure PlainTextOfConcatenation;
    [Test]
    procedure EachLineBreak;
    [Test]
    procedure MultilineString;
    [Test]
    procedure MaxLineLengthWraps;
    [Test]
    procedure EmptyLinesAndPlaceholders;
    [Test]
    procedure LiteralAtFindsConcatenation;
    [Test]
    procedure CodeActions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.StringLiterals;

/// <summary>StringLiteralActions mit den Token von AText.</summary>
function LiteralActions(const AText: string; const ARange: TTextRange): TArray<TCodeAction>;
begin
  Result := TCodeActions.StringLiteralActions(AText, TPascalLexer.Tokenize(AText), ARange,
    TStringLiteralSettings.Default, False);
end;

const
  cSql = 'select *'#13#10'from Kunde'#13#10'where Name = ''O''''Brien''';

function Concat(const AText: string; ABreak: TStringLiteralBreak; AMaxLineLength: Integer): string;
var
  mSettings: TStringLiteralSettings;
begin
  mSettings := TStringLiteralSettings.Default;
  mSettings.LineBreak := ABreak;
  mSettings.MaxLineLength := AMaxLineLength;
  Result := TStringLiterals.ToLiteral(AText, '  ', False, False, mSettings, #10);
end;

function Plain(const AExpression: string): string;
begin
  Assert.IsTrue(TStringLiterals.PlainText(AExpression, Result), AExpression);
end;

procedure TStringLiteralsTests.QuoteSpecialCharacters;
begin
  Assert.AreEqual('''Kunde''''s''', TStringLiterals.Quote('Kunde''s'));
  Assert.AreEqual('''a''#9''b''', TStringLiterals.Quote('a'#9'b'));
  Assert.AreEqual('#9''x''', TStringLiterals.Quote(#9'x'));
  Assert.AreEqual('''Größe äöü''', TStringLiterals.Quote('Größe äöü'));
  Assert.AreEqual('''''', TStringLiterals.Quote(''));
  Assert.AreEqual('a'#9'b', Plain('''a''#9''b'''));
  Assert.AreEqual('Größe', Plain('''Größe'''));
end;

procedure TStringLiteralsTests.ConcatRoundTrip;
var
  mLiteral: string;
begin
  mLiteral := Concat(cSql, TStringLiteralBreak.SLineBreak, 0);
  Assert.AreEqual('''select *'' + sLineBreak +'#10'  ''from Kunde'' + sLineBreak +'#10 +
    '  ''where Name = ''''O''''''''Brien''''''', mLiteral);
  Assert.AreEqual(cSql, Plain(mLiteral));
  Assert.AreEqual(mLiteral, Concat(Plain(mLiteral), TStringLiteralBreak.SLineBreak, 0));
end;

procedure TStringLiteralsTests.AutoStyleDependsOnVersion;
begin
  Assert.IsFalse(TStringLiterals.UseMultiline(TStringLiteralStyle.Auto, '22.0'));
  Assert.IsTrue(TStringLiterals.UseMultiline(TStringLiteralStyle.Auto, '23.0'));
  Assert.IsFalse(TStringLiterals.UseMultiline(TStringLiteralStyle.Auto, ''));
  Assert.IsTrue(TStringLiterals.UseMultiline(TStringLiteralStyle.Multiline, '22.0'));
  Assert.IsFalse(TStringLiterals.UseMultiline(TStringLiteralStyle.Concat, '37.0'));
end;

procedure TStringLiteralsTests.PlainTextOfConcatenation;
var
  mText: string;
begin
  Assert.AreEqual('select *'#13#10'from Kunde', Plain('''select *'' + sLineBreak + ''from Kunde'''));
  Assert.AreEqual('a'#13#10'b', Plain('''a''#13#10 +'#10'  { Kommentar } ''b'''));
  Assert.AreEqual('a'#13#10'b', Plain('''a''#$0D#$0A''b'''));
  Assert.IsFalse(TStringLiterals.PlainText('''a'' + Name', mText));
  Assert.IsFalse(TStringLiterals.PlainText('sLineBreak', mText));
end;

procedure TStringLiteralsTests.EachLineBreak;
const
  cText = 'select *'#10'from Kunde';
begin
  Assert.AreEqual('''select *''#13#10 +'#10'  ''from Kunde''', Concat(cText, TStringLiteralBreak.CrLf, 0));
  Assert.AreEqual('''select *''#10 +'#10'  ''from Kunde''', Concat(cText, TStringLiteralBreak.Lf, 0));
  Assert.AreEqual('''select * '' +'#10'  ''from Kunde''', Concat(cText, TStringLiteralBreak.Space, 0));
  Assert.AreEqual('''select *'' +'#10'  ''from Kunde''', Concat(cText, TStringLiteralBreak.None, 0));
  Assert.AreEqual('select *'#10'from Kunde', Plain(Concat(cText, TStringLiteralBreak.Lf, 0)));
end;

procedure TStringLiteralsTests.MultilineString;
var
  mLiteral: string;
begin
  mLiteral := TStringLiterals.ToLiteral('select *'#10'from Kunde', '  ', False, True, TStringLiteralSettings.Default,
    #10);
  Assert.AreEqual('''''''' + #10'    select *'#10'    from Kunde'#10'    ''''''', mLiteral);
  Assert.AreEqual('select *'#13#10'from Kunde', Plain(mLiteral));
  // Mit ''' im Text oder Steuerzeichen geht es nur verkettet.
  mLiteral := TStringLiterals.ToLiteral('a'''''''#10'b', '', False, True, TStringLiteralSettings.Default, #10);
  Assert.AreEqual('''a'''''''''''''' + sLineBreak +'#10'''b''', mLiteral);
end;

procedure TStringLiteralsTests.MaxLineLengthWraps;
const
  cLong = 'select Kunde.Name, Kunde.Ort, Kunde.Strasse, Kunde.Telefon from Kunde';
var
  mLiteral, mLine: string;
begin
  mLiteral := Concat(cLong, TStringLiteralBreak.SLineBreak, 40);
  Assert.IsTrue(Length(mLiteral.Split([#10])) > 1, mLiteral);
  for mLine in mLiteral.Split([#10]) do
  begin
    Assert.IsTrue(Length(mLine) <= 40, mLine);
  end;
  Assert.AreEqual(cLong, Plain(mLiteral));
end;

procedure TStringLiteralsTests.EmptyLinesAndPlaceholders;
const
  cText = 'select * from Kunde'#13#10#13#10'where Nr = :Nr and Name like %s';
begin
  Assert.AreEqual(cText, Plain(Concat(cText, TStringLiteralBreak.SLineBreak, 0)));
  Assert.IsTrue(Pos(''''' + sLineBreak +', Concat(cText, TStringLiteralBreak.SLineBreak, 0)) > 0);
  Assert.IsTrue(Pos(':Nr and Name like %s', Concat(cText, TStringLiteralBreak.SLineBreak, 0)) > 0);
end;

procedure TStringLiteralsTests.LiteralAtFindsConcatenation;
const
  cSource = 'begin'#10'  Q.SQL.Text := ''select *'' + sLineBreak +'#10'    ''from Kunde'';'#10'end.';
var
  mRange: TTextRange;
begin
  Assert.IsTrue(TStringLiterals.LiteralAt(cSource, TTextPosition.Create(2, 7), mRange));
  Assert.AreEqual(1, mRange.StartPos.Line);
  Assert.AreEqual(16, mRange.StartPos.Character);
  Assert.AreEqual(2, mRange.EndPos.Line);
  Assert.AreEqual(16, mRange.EndPos.Character);
  Assert.AreEqual('select *'#13#10'from Kunde', Plain(TStringLiterals.TextOf(cSource, mRange)));
  Assert.IsFalse(TStringLiterals.LiteralAt(cSource, TTextPosition.Create(1, 4), mRange));
end;

procedure TStringLiteralsTests.CodeActions;
var
  mActions: TArray<TCodeAction>;
begin
  mActions := LiteralActions('    select *'#10'      from Kunde'#10'x', TTextRange.Create(0, 0, 2, 0));
  Assert.AreEqual(1, Integer(Length(mActions)));
  Assert.AreEqual('Als String-Literal', mActions[0].Title);
  Assert.AreEqual('    ''select *'' + sLineBreak +'#10'    ''  from Kunde''', mActions[0].Edits[0].NewText);
  Assert.AreEqual(1, mActions[0].Edits[0].Range.EndPos.Line);
  mActions := LiteralActions('  S := ''a'' + sLineBreak + ''b'';', TTextRange.Create(0, 9, 0, 9));
  Assert.AreEqual(1, Integer(Length(mActions)));
  Assert.AreEqual(cCopyTextCommand, mActions[0].Command);
  Assert.AreEqual('a'#13#10'b', mActions[0].CommandArguments[0]);
  // Ohne Markierung und ohne Literal keine Aktion.
  Assert.AreEqual(0, Integer(Length(LiteralActions('  Save;', TTextRange.Create(0, 2, 0, 2)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TStringLiteralsTests);

end.
