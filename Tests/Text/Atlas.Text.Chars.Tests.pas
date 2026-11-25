unit Atlas.Text.Chars.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextCharsTests = class
  public
    [Test]
    procedure IdentCharUnicode;
    [Test]
    procedure AsciiIdentCharRejectsUmlaut;
    [Test]
    procedure IdentStartRejectsDigit;
    [Test]
    procedure CharAtOutsideIsNull;
    [Test]
    procedure IsDigitsNeedsOneDigit;
    [Test]
    procedure PastNextBehindChar;
    [Test]
    procedure RunEndStopsAtOtherChar;
    [Test]
    procedure IdentEndCountsUnicode;
    [Test]
    procedure AsciiIdentEndStopsAtUmlaut;
    [Test]
    procedure HexDigitValueBothCases;
    [Test]
    procedure StringBytesAndBom;
  end;

implementation

uses
  Atlas.Text.Chars;

{ TTextCharsTests }

procedure TTextCharsTests.IdentCharUnicode;
begin
  Assert.IsTrue(TTextChars.IsIdentChar('a'));
  Assert.IsTrue(TTextChars.IsIdentChar('Z'));
  Assert.IsTrue(TTextChars.IsIdentChar('_'));
  Assert.IsTrue(TTextChars.IsIdentChar('7'));
  Assert.IsTrue(TTextChars.IsIdentChar(#$00C4));
  Assert.IsTrue(TTextChars.IsIdentChar(#128));
  Assert.IsFalse(TTextChars.IsIdentChar('.'));
  Assert.IsFalse(TTextChars.IsIdentChar(' '));
  Assert.IsFalse(TTextChars.IsIdentChar('$'));
end;

procedure TTextCharsTests.AsciiIdentCharRejectsUmlaut;
begin
  Assert.IsTrue(TTextChars.IsAsciiIdentChar('a'));
  Assert.IsTrue(TTextChars.IsAsciiIdentChar('9'));
  Assert.IsTrue(TTextChars.IsAsciiIdentChar('_'));
  Assert.IsFalse(TTextChars.IsAsciiIdentChar(#$00E4));
  Assert.IsFalse(TTextChars.IsAsciiIdentChar('-'));
end;

procedure TTextCharsTests.IdentStartRejectsDigit;
begin
  Assert.IsFalse(TTextChars.IsIdentStart('1'));
  Assert.IsTrue(TTextChars.IsIdentStart('_'));
  Assert.IsTrue(TTextChars.IsIdentStart(#$00DC));
end;

procedure TTextCharsTests.CharAtOutsideIsNull;
begin
  Assert.AreEqual<Char>('b', TTextChars.CharAt('abc', 2));
  Assert.AreEqual<Char>(#0, TTextChars.CharAt('abc', 0));
  Assert.AreEqual<Char>(#0, TTextChars.CharAt('abc', 4));
  Assert.AreEqual<Char>(#0, TTextChars.CharAt('', 1));
end;

procedure TTextCharsTests.IsDigitsNeedsOneDigit;
begin
  Assert.IsTrue(TTextChars.IsDigits('0123456789'));
  Assert.IsFalse(TTextChars.IsDigits(''));
  Assert.IsFalse(TTextChars.IsDigits('12a'));
  Assert.IsFalse(TTextChars.IsDigits(' 1'));
  Assert.IsFalse(TTextChars.IsDigits('-1'));
end;

procedure TTextCharsTests.PastNextBehindChar;
begin
  Assert.AreEqual(5, TTextChars.PastNext('{ab} c', 1, '}'));
  Assert.AreEqual(5, TTextChars.PastNext('''ab'' c', 2, ''''));
  Assert.AreEqual(2, TTextChars.PastNext('}', 1, '}'));
  // Ohne Abschluss: Length + 2, wie hinter einem gedachten Zeichen hinter dem Text.
  Assert.AreEqual(6, TTextChars.PastNext('{abc', 1, '}'));
end;

procedure TTextCharsTests.RunEndStopsAtOtherChar;
begin
  Assert.AreEqual(3, TTextChars.RunEnd('12a', 1, ['0'..'9']));
  Assert.AreEqual(2, TTextChars.RunEnd('a  b', 2, ['x']));
  Assert.AreEqual(4, TTextChars.RunEnd('a  b', 2, [' ']));
  Assert.AreEqual(5, TTextChars.RunEnd('a  b', 5, [' ']));
end;

procedure TTextCharsTests.IdentEndCountsUnicode;
begin
  Assert.AreEqual(6, TTextChars.IdentEnd('ab'#$00E4'_1.x', 1));
  Assert.AreEqual(1, TTextChars.IdentEnd('.x', 1));
  Assert.AreEqual(5, TTextChars.IdentEnd('x.ab', 3));
end;

procedure TTextCharsTests.AsciiIdentEndStopsAtUmlaut;
begin
  Assert.AreEqual(3, TTextChars.AsciiIdentEnd('ab'#$00E4, 1));
  Assert.AreEqual(5, TTextChars.AsciiIdentEnd('$1_a', 2));
end;

procedure TTextCharsTests.HexDigitValueBothCases;
begin
  Assert.AreEqual(0, TTextChars.HexDigitValue('0'));
  Assert.AreEqual(9, TTextChars.HexDigitValue('9'));
  Assert.AreEqual(10, TTextChars.HexDigitValue('a'));
  Assert.AreEqual(15, TTextChars.HexDigitValue('F'));
  Assert.AreEqual(-1, TTextChars.HexDigitValue('g'));
end;

procedure TTextCharsTests.StringBytesAndBom;
begin
  Assert.AreEqual(Int64(0), TTextChars.StringBytes(''));
  Assert.AreEqual(Int64(12 + 4 * SizeOf(Char)), TTextChars.StringBytes('abc'));
  Assert.AreEqual(1, TTextChars.StartAfterBom('unit'));
  Assert.AreEqual(1, TTextChars.StartAfterBom(''));
  Assert.AreEqual(2, TTextChars.StartAfterBom(#$FEFF'unit'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextCharsTests);

end.
