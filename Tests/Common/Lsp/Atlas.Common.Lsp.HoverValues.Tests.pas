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
    procedure ReadsSetConstants;
    [Test]
    procedure ReadsStringConstants;
    [Test]
    procedure ReadsSetTypes;
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
  Assert.AreEqual('''Text''', THoverValues.ConstantValue('Name = ''Text'';'));
  Assert.AreEqual('', THoverValues.ConstantValue('Value: Integer;'));
  Assert.AreEqual('', THoverValues.ConstantValue('Max = High(Integer);'));
end;

procedure TLspHoverValuesTests.ReadsSetConstants;
begin
  Assert.AreEqual('[fsBold, fsItalic] · 2 Elemente',
    THoverValues.ConstantValue('Stile: TFontStyles = [fsBold, fsItalic];'));
  Assert.AreEqual('[fsBold, fsItalic] · 2 Elemente',
    THoverValues.ConstantValue('Stile = [fsBold,fsItalic] deprecated ''Neu'';'));
  Assert.AreEqual('[1..5, 9] · 6 Elemente', THoverValues.ConstantValue('Ziffern = [1..5, 9];'));
  Assert.AreEqual('[''a''..''z''] · 26 Elemente', THoverValues.ConstantValue('Klein = [''a''..''z''];'));
  Assert.AreEqual('[Rot..Blau]', THoverValues.ConstantValue('Farben = [Rot..Blau];'));
  Assert.AreEqual('[] · leer', THoverValues.ConstantValue('Keine: TFontStyles = [];'));
end;

procedure TLspHoverValuesTests.ReadsStringConstants;
begin
  Assert.AreEqual('''Datei nicht gefunden''', THoverValues.ConstantValue('SNotFound = ''Datei nicht gefunden'';'));
  Assert.AreEqual('''Zeile 1⏎Zeile 2: Peter''s''',
    THoverValues.ConstantValue('SZwei = ''Zeile 1'' + #13#10 + ''Zeile 2: Peter''''s'';'));
  Assert.AreEqual('''AB''', THoverValues.ConstantValue('S = #$41''B'';'));
  Assert.AreEqual('', THoverValues.ConstantValue('S = ''A'' + Name;'));
end;

procedure TLspHoverValuesTests.ReadsSetTypes;
var
  BaseType: string;
begin
  Assert.IsTrue(THoverValues.SetBaseType('TFontStyles = set of TFontStyle;', BaseType));
  Assert.AreEqual('TFontStyle', BaseType);
  Assert.AreEqual(-1, THoverValues.BaseTypeCount(BaseType));
  Assert.IsTrue(THoverValues.SetBaseType('TOpts = set of (oA, oB, oC);', BaseType));
  Assert.AreEqual(3, THoverValues.BaseTypeCount(BaseType));
  Assert.IsTrue(THoverValues.SetBaseType('TBits = set of 0..31;', BaseType));
  Assert.AreEqual(32, THoverValues.BaseTypeCount(BaseType));
  Assert.AreEqual(256, THoverValues.BaseTypeCount('Byte'));
  Assert.IsFalse(THoverValues.SetBaseType('TFoo = class', BaseType));
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
