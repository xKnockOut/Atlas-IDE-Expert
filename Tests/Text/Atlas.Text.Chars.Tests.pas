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
  end;

implementation

uses
  Atlas.Text.Chars;

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

initialization
  TDUnitX.RegisterTestFixture(TTextCharsTests);

end.
