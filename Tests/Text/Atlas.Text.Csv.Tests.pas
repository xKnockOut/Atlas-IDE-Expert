unit Atlas.Text.Csv.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextCsvTests = class
  public
    [Test]
    procedure PlainCellUnchanged;
    [Test]
    procedure QuotesSeparatorQuoteAndBreak;
  end;

implementation

uses
  Atlas.Text.Csv;

{ TTextCsvTests }

procedure TTextCsvTests.PlainCellUnchanged;
begin
  Assert.AreEqual('TKunde, TAuftrag', TTextCsv.Cell('TKunde, TAuftrag'));
  Assert.AreEqual('', TTextCsv.Cell(''));
end;

procedure TTextCsvTests.QuotesSeparatorQuoteAndBreak;
begin
  Assert.AreEqual('"a;b"', TTextCsv.Cell('a;b'));
  Assert.AreEqual('"sagt ""ja"""', TTextCsv.Cell('sagt "ja"'));
  Assert.AreEqual('"a'#13#10'b"', TTextCsv.Cell('a'#13#10'b'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextCsvTests);

end.
