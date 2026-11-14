unit Atlas.Common.Semantics.ExpressionTypes.Operators.Tests;

// Operatorregeln der Ausdruckstypen ohne Syntaxbaum: Kategorien eingebauter Typen, Ergebnis zwei- und einstelliger
// Operatoren nach Delphis Regeln und die Art impliziter Umwandlungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExpressionOperatorsTests = class
  public
    [Test]
    procedure CategoriesOfBuiltinTypes;
    [Test]
    procedure IntegerArithmeticWidens;
    [Test]
    procedure RealCurrencyAndText;
    [Test]
    procedure MismatchCarriesOperands;
    [Test]
    procedure UnaryOperators;
    [Test]
    procedure ConversionKinds;
  end;

implementation

uses
  Atlas.Common.Semantics.ExpressionTypes.Contract,
  Atlas.Common.Semantics.ExpressionTypes.Operators;

function Result2(const AOperator, ALeft, ARight: string): string;
var
  mNoted: Boolean;
begin
  Result := TExpressionOperators.OperationResult(AOperator, TExpressionOperators.Typed(ALeft),
    TExpressionOperators.Typed(ARight), False, mNoted).Name;
end;

procedure TExpressionOperatorsTests.CategoriesOfBuiltinTypes;
var
  mWidth: Integer;
  mSigned: Boolean;
begin
  Assert.AreEqual<TExpressionCategory>(TExpressionCategory.Integer_,
    TExpressionOperators.CategoryOf('System.Cardinal', mWidth, mSigned));
  Assert.AreEqual(4, mWidth);
  Assert.IsFalse(mSigned);
  Assert.AreEqual<TExpressionCategory>(TExpressionCategory.Pointer_,
    TExpressionOperators.CategoryOf('^TKunde', mWidth, mSigned));
  Assert.AreEqual<TExpressionCategory>(TExpressionCategory.Set_,
    TExpressionOperators.CategoryOf('set of Byte', mWidth, mSigned));
  Assert.AreEqual<TExpressionCategory>(TExpressionCategory.Unknown,
    TExpressionOperators.CategoryOf('', mWidth, mSigned));
  Assert.AreEqual<TExpressionCategory>(TExpressionCategory.Other,
    TExpressionOperators.CategoryOf('TKunde', mWidth, mSigned));
end;

procedure TExpressionOperatorsTests.IntegerArithmeticWidens;
begin
  Assert.AreEqual('Integer', Result2('+', 'Byte', 'Word'));
  Assert.AreEqual('Cardinal', Result2('*', 'Cardinal', 'Cardinal'));
  Assert.AreEqual('Int64', Result2('-', 'Cardinal', 'Integer'));
  Assert.AreEqual('UInt64', Result2('+', 'UInt64', 'Integer'));
  Assert.AreEqual('Int64', Result2('shl', 'Int64', 'Integer'));
  Assert.AreEqual('Integer', Result2('div', 'SmallInt', 'Byte'));
end;

procedure TExpressionOperatorsTests.RealCurrencyAndText;
begin
  Assert.AreEqual('Extended', Result2('/', 'Integer', 'Integer'));
  Assert.AreEqual('Currency', Result2('*', 'Currency', 'Integer'));
  Assert.AreEqual('Extended', Result2('+', 'Currency', 'Double'));
  Assert.AreEqual('Double', Result2('+', 'Single', 'Double'));
  Assert.AreEqual('string', Result2('+', 'Char', 'Char'));
  Assert.AreEqual('Variant', Result2('+', 'Variant', 'Integer'));
  Assert.AreEqual('Boolean', Result2('and', 'Boolean', 'Boolean'));
end;

procedure TExpressionOperatorsTests.MismatchCarriesOperands;
var
  mFound: TExpressionTyped;
  mNoted: Boolean;
begin
  mFound := TExpressionOperators.OperationResult('/', TExpressionOperators.Typed('string'),
    TExpressionOperators.Typed('Integer'), False, mNoted);
  Assert.IsFalse(mFound.Known);
  Assert.AreEqual<TExpressionErrorKind>(TExpressionErrorKind.OperatorMismatch, mFound.Error);
  Assert.AreEqual('/|string|Integer', mFound.ErrorDetail);
end;

procedure TExpressionOperatorsTests.UnaryOperators;
begin
  Assert.AreEqual('Integer', TExpressionOperators.UnaryResult('-', TExpressionOperators.Typed('Byte')).Name);
  Assert.AreEqual('Int64', TExpressionOperators.UnaryResult('-', TExpressionOperators.Typed('Int64')).Name);
  Assert.AreEqual('Pointer', TExpressionOperators.UnaryResult('@', TExpressionOperators.Typed('TKunde')).Name);
  Assert.AreEqual('Boolean', TExpressionOperators.UnaryResult('not', TExpressionOperators.Typed('Boolean')).Name);
  Assert.IsFalse(TExpressionOperators.UnaryResult('not', TExpressionOperators.Typed('string')).Known);
end;

procedure TExpressionOperatorsTests.ConversionKinds;
var
  mKind: TExpressionConversionKind;
begin
  Assert.IsTrue(TExpressionOperators.ConversionKind(TExpressionOperators.Typed('Integer'),
    TExpressionOperators.Typed('Currency'), mKind));
  Assert.AreEqual<TExpressionConversionKind>(TExpressionConversionKind.Widen, mKind);
  Assert.IsTrue(TExpressionOperators.ConversionKind(TExpressionOperators.Typed('Char'),
    TExpressionOperators.Typed('string'), mKind));
  Assert.AreEqual<TExpressionConversionKind>(TExpressionConversionKind.Convert, mKind);
  Assert.IsFalse(TExpressionOperators.ConversionKind(TExpressionOperators.Typed('TKunde'),
    TExpressionOperators.Typed('string'), mKind));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionOperatorsTests);

end.
