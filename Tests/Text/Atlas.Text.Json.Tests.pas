unit Atlas.Text.Json.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonTextTests = class
  public
    [Test]
    procedure QuotesPlainText;
    [Test]
    procedure EscapesQuotesAndBackslash;
    [Test]
    procedure EscapesControlCharacters;
    [Test]
    procedure KeepsUmlauts;
  end;

implementation

uses
  Atlas.Text.Json;

procedure TJsonTextTests.QuotesPlainText;
begin
  Assert.AreEqual('""', TJsonText.Quote(''));
  Assert.AreEqual('"abc"', TJsonText.Quote('abc'));
end;

procedure TJsonTextTests.EscapesQuotesAndBackslash;
begin
  Assert.AreEqual('"a\"b\\c"', TJsonText.Quote('a"b\c'));
end;

procedure TJsonTextTests.EscapesControlCharacters;
begin
  Assert.AreEqual('"\b\t\n\f\r\u0001\u001F"', TJsonText.Quote(#8#9#10#12#13#1#31));
end;

procedure TJsonTextTests.KeepsUmlauts;
begin
  Assert.AreEqual('"Größe"', TJsonText.Quote('Größe'));
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonTextTests);

end.
