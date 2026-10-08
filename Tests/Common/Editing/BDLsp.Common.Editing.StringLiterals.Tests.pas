unit BDLsp.Common.Editing.StringLiterals.Tests;

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
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Editing.CodeActions,
  BDLsp.Common.Editing.StringLiterals;

const
  Sql = 'select *'#13#10'from Kunde'#13#10'where Name = ''O''''Brien''';

function Concat(const AText: string; ABreak: TStringLiteralBreak; AMaxLineLength: Integer = 0): string;
begin
  Result := TStringLiterals.ToLiteral(AText, '  ', False, False, ABreak, AMaxLineLength, #10);
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
  Literal: string;
begin
  Literal := Concat(Sql, TStringLiteralBreak.SLineBreak);
  Assert.AreEqual('''select *'' + sLineBreak +'#10'  ''from Kunde'' + sLineBreak +'#10 +
    '  ''where Name = ''''O''''''''Brien''''''', Literal);
  Assert.AreEqual(Sql, Plain(Literal));
  Assert.AreEqual(Literal, Concat(Plain(Literal), TStringLiteralBreak.SLineBreak));
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
  Text: string;
begin
  Assert.AreEqual('select *'#13#10'from Kunde', Plain('''select *'' + sLineBreak + ''from Kunde'''));
  Assert.AreEqual('a'#13#10'b', Plain('''a''#13#10 +'#10'  { Kommentar } ''b'''));
  Assert.AreEqual('a'#13#10'b', Plain('''a''#$0D#$0A''b'''));
  Assert.IsFalse(TStringLiterals.PlainText('''a'' + Name', Text));
  Assert.IsFalse(TStringLiterals.PlainText('sLineBreak', Text));
end;

procedure TStringLiteralsTests.EachLineBreak;
const
  Text = 'select *'#10'from Kunde';
begin
  Assert.AreEqual('''select *''#13#10 +'#10'  ''from Kunde''', Concat(Text, TStringLiteralBreak.CrLf));
  Assert.AreEqual('''select *''#10 +'#10'  ''from Kunde''', Concat(Text, TStringLiteralBreak.Lf));
  Assert.AreEqual('''select * '' +'#10'  ''from Kunde''', Concat(Text, TStringLiteralBreak.Space));
  Assert.AreEqual('''select *'' +'#10'  ''from Kunde''', Concat(Text, TStringLiteralBreak.None));
  Assert.AreEqual('select *'#10'from Kunde', Plain(Concat(Text, TStringLiteralBreak.Lf)));
end;

procedure TStringLiteralsTests.MultilineString;
var
  Literal: string;
begin
  Literal := TStringLiterals.ToLiteral('select *'#10'from Kunde', '  ', False, True, TStringLiteralBreak.SLineBreak, 0,
    #10);
  Assert.AreEqual('''''''' + #10'    select *'#10'    from Kunde'#10'    ''''''', Literal);
  Assert.AreEqual('select *'#13#10'from Kunde', Plain(Literal));
  // Mit ''' im Text oder Steuerzeichen geht es nur verkettet.
  Literal := TStringLiterals.ToLiteral('a'''''''#10'b', '', False, True, TStringLiteralBreak.SLineBreak, 0, #10);
  Assert.AreEqual('''a'''''''''''''' + sLineBreak +'#10'''b''', Literal);
end;

procedure TStringLiteralsTests.MaxLineLengthWraps;
const
  Long = 'select Kunde.Name, Kunde.Ort, Kunde.Strasse, Kunde.Telefon from Kunde';
var
  Literal, Line: string;
begin
  Literal := Concat(Long, TStringLiteralBreak.SLineBreak, 40);
  Assert.IsTrue(Length(Literal.Split([#10])) > 1, Literal);
  for Line in Literal.Split([#10]) do
    Assert.IsTrue(Length(Line) <= 40, Line);
  Assert.AreEqual(Long, Plain(Literal));
end;

procedure TStringLiteralsTests.EmptyLinesAndPlaceholders;
const
  Text = 'select * from Kunde'#13#10#13#10'where Nr = :Nr and Name like %s';
begin
  Assert.AreEqual(Text, Plain(Concat(Text, TStringLiteralBreak.SLineBreak)));
  Assert.IsTrue(Pos(''''' + sLineBreak +', Concat(Text, TStringLiteralBreak.SLineBreak)) > 0);
  Assert.IsTrue(Pos(':Nr and Name like %s', Concat(Text, TStringLiteralBreak.SLineBreak)) > 0);
end;

procedure TStringLiteralsTests.LiteralAtFindsConcatenation;
const
  Source = 'begin'#10'  Q.SQL.Text := ''select *'' + sLineBreak +'#10'    ''from Kunde'';'#10'end.';
var
  Range: TTextRange;
begin
  Assert.IsTrue(TStringLiterals.LiteralAt(Source, TTextPosition.Create(2, 7), Range));
  Assert.AreEqual(1, Range.StartPos.Line);
  Assert.AreEqual(16, Range.StartPos.Character);
  Assert.AreEqual(2, Range.EndPos.Line);
  Assert.AreEqual(16, Range.EndPos.Character);
  Assert.AreEqual('select *'#13#10'from Kunde', Plain(TStringLiterals.TextOf(Source, Range)));
  Assert.IsFalse(TStringLiterals.LiteralAt(Source, TTextPosition.Create(1, 4), Range));
end;

procedure TStringLiteralsTests.CodeActions;
var
  Actions: TArray<TCodeAction>;
begin
  Actions := TCodeActions.StringLiteralActions('    select *'#10'      from Kunde'#10'x',
    TTextRange.Create(0, 0, 2, 0), TStringLiteralSettings.Default, False);
  Assert.AreEqual(1, Integer(Length(Actions)));
  Assert.AreEqual('Als String-Literal', Actions[0].Title);
  Assert.AreEqual('    ''select *'' + sLineBreak +'#10'    ''  from Kunde''', Actions[0].Edits[0].NewText);
  Assert.AreEqual(1, Actions[0].Edits[0].Range.EndPos.Line);
  Actions := TCodeActions.StringLiteralActions('  S := ''a'' + sLineBreak + ''b'';', TTextRange.Create(0, 9, 0, 9),
    TStringLiteralSettings.Default, False);
  Assert.AreEqual(1, Integer(Length(Actions)));
  Assert.AreEqual(CopyTextCommand, Actions[0].Command);
  Assert.AreEqual('a'#13#10'b', Actions[0].CommandArguments[0]);
  // Ohne Markierung und ohne Literal keine Aktion.
  Assert.AreEqual(0, Integer(Length(TCodeActions.StringLiteralActions('  Save;', TTextRange.Create(0, 2, 0, 2),
    TStringLiteralSettings.Default, False))));
end;

initialization
  TDUnitX.RegisterTestFixture(TStringLiteralsTests);

end.
