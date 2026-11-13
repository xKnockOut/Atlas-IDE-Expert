unit Atlas.Common.Rules.Builtin.Properties.Shapes.Tests;

// Gelesene Property-Deklarationen (Rules.Builtin.Properties.Shapes): Zugriffe hinter read und write mit
// Feldselektoren, Typtext, Übergabeart der Parameter einer Signatur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPropertyShapesTests = class
  public
    [Test]
    procedure ReadsAccessorsAndType;
    [Test]
    procedure ReadsFieldSelectors;
    [Test]
    procedure ParamModifiersPerName;
    [Test]
    procedure ClauseNamesReadAndWrite;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Builtin.Properties.Shapes;

function Shape(const AText: string): TPropertyShape;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  Assert.IsTrue(ParseProperty(AText, mTokens, 0, Result), AText);
end;

procedure TPropertyShapesTests.ReadsAccessorsAndType;
var
  mShape: TPropertyShape;
begin
  mShape := Shape('property Name: string read FName write SetName;');
  Assert.AreEqual('string', mShape.TypeText);
  Assert.AreEqual(2, Integer(Length(mShape.Accessors)));
  Assert.IsFalse(mShape.Accessors[0].IsWrite);
  Assert.AreEqual('FName', mShape.Accessors[0].Name);
  Assert.IsTrue(mShape.Accessors[1].IsWrite);
  Assert.AreEqual('SetName', mShape.Accessors[1].Name);
end;

procedure TPropertyShapesTests.ReadsFieldSelectors;
var
  mShape: TPropertyShape;
begin
  mShape := Shape('property X: Integer read FPoint.X;');
  Assert.AreEqual(1, Integer(Length(mShape.Accessors)));
  Assert.AreEqual('FPoint', mShape.Accessors[0].Name);
  Assert.AreEqual('X', string.Join('.', mShape.Accessors[0].Selectors));
end;

procedure TPropertyShapesTests.ParamModifiersPerName;
begin
  Assert.AreEqual('const|const|var|', string.Join('|',
    ParamModifiers('procedure P(const A, B: string; var C: Integer; D: Byte)')));
  Assert.AreEqual(0, Integer(Length(ParamModifiers('procedure Ohne'))));
end;

procedure TPropertyShapesTests.ClauseNamesReadAndWrite;
var
  mAccessor: TPropertyAccessor;
begin
  mAccessor := Default(TPropertyAccessor);
  Assert.AreEqual('read', ClauseOf(mAccessor));
  mAccessor.IsWrite := True;
  Assert.AreEqual('write', ClauseOf(mAccessor));
end;

initialization
  TDUnitX.RegisterTestFixture(TPropertyShapesTests);

end.
