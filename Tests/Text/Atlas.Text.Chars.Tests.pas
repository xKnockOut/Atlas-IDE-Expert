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

initialization
  TDUnitX.RegisterTestFixture(TTextCharsTests);

end.
