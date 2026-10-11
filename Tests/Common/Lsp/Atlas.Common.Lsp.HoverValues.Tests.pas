unit Atlas.Common.Lsp.HoverValues.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.HoverValues;

type
  [TestFixture]
  TLspHoverValuesTests = class
  public
    [Test]
    procedure ParsesNumberNotations;
    [Test]
    procedure RejectsNonNumbers;
    [Test]
    procedure FormatsNumbers;
    [Test]
    procedure ReadsConstantValues;
    [Test]
    procedure FindsDeprecationDirectives;
  end;

implementation

{ TLspHoverValuesTests }

procedure TLspHoverValuesTests.ParsesNumberNotations;
var
  Value: Int64;
begin
  Assert.IsTrue(THoverValues.TryParseNumber('15', Value));
  Assert.AreEqual(Int64(15), Value);
  Assert.IsTrue(THoverValues.TryParseNumber('$FF', Value));
  Assert.AreEqual(Int64(255), Value);
  Assert.IsTrue(THoverValues.TryParseNumber('%1010', Value));
  Assert.AreEqual(Int64(10), Value);
  Assert.IsTrue(THoverValues.TryParseNumber('&17', Value));
  Assert.AreEqual(Int64(15), Value);
  Assert.IsTrue(THoverValues.TryParseNumber('1_000', Value));
  Assert.AreEqual(Int64(1000), Value);
  Assert.IsTrue(THoverValues.TryParseNumber('-3', Value));
  Assert.AreEqual(Int64(-3), Value);
end;

procedure TLspHoverValuesTests.RejectsNonNumbers;
var
  Value: Int64;
begin
  Assert.IsFalse(THoverValues.TryParseNumber('', Value));
  Assert.IsFalse(THoverValues.TryParseNumber('Foo', Value));
  Assert.IsFalse(THoverValues.TryParseNumber('1.5', Value));
  Assert.IsFalse(THoverValues.TryParseNumber('$', Value));
end;

procedure TLspHoverValuesTests.FormatsNumbers;
begin
  Assert.AreEqual('15 · $0F · %1111', THoverValues.FormatNumber(15));
  Assert.AreEqual('256 · $0100 · %100000000', THoverValues.FormatNumber(256));
  Assert.AreEqual('65536 · $00010000 · %10000000000000000', THoverValues.FormatNumber(65536));
end;

procedure TLspHoverValuesTests.ReadsConstantValues;
begin
  Assert.AreEqual('15 · $0F · %1111', THoverValues.ConstantValue('MaxCount = $F;'));
  Assert.AreEqual('3 · $03 · %11', THoverValues.ConstantValue('Limit: Integer = 3;'));
  Assert.AreEqual('7 · $07 · %111', THoverValues.ConstantValue('Old = 7 deprecated;'));
  Assert.AreEqual('', THoverValues.ConstantValue('Name = ''Text'';'));
  Assert.AreEqual('', THoverValues.ConstantValue('Value: Integer;'));
end;

procedure TLspHoverValuesTests.FindsDeprecationDirectives;
begin
  Assert.AreEqual('**Veraltet**', THoverValues.Deprecation('procedure Foo; deprecated;'));
  Assert.AreEqual('**Veraltet**: Bar verwenden',
    THoverValues.Deprecation('procedure Foo; deprecated ''Bar verwenden'';'));
  Assert.AreEqual('**Plattformspezifisch**', THoverValues.Deprecation('procedure Foo; platform;'));
  Assert.AreEqual('**Experimentell**', THoverValues.Deprecation('TFoo = class end experimental;'));
  Assert.AreEqual('', THoverValues.Deprecation('procedure Foo(Platform: string);'));
  Assert.AreEqual('', THoverValues.Deprecation('Text = ''deprecated'';'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverValuesTests);

end.
