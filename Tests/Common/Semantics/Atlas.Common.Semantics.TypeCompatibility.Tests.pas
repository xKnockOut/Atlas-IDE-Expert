unit Atlas.Common.Semantics.TypeCompatibility.Tests;

// Tests der Verträglichkeit sicher bekannter Typen (#1369): Zuweisung je Art
// (eingebaut, Klasse, Aufzählung, statisches Array, offen), Operatoren (nicht
// anwendbar, unverträglich, passend, offen), einstellige Operatoren,
// var-Parameter samt Aliasen und Plattformtypen, Hilfsfunktionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeCompatibilityTests = class
  public
    [Test]
    procedure AssignBuiltinTypes;
    [Test]
    procedure AssignClassesEnumsAndArrays;
    [Test]
    procedure UnknownAndOpenKindsStayOpen;
    [Test]
    procedure BinaryOperators;
    [Test]
    procedure UnaryOperators;
    [Test]
    procedure VarParameters;
    [Test]
    procedure Helpers;
  end;

implementation

uses
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Semantics.TypeCompatibility;

function B(const AName: string): TValueType;
begin
  Result := TValueType.FromBuiltin(AName);
end;

function Incompatible(const ATarget, ASource: TValueType): Boolean;
begin
  Result := TTypeCompatibility.AssignIncompatible(ATarget, ASource);
end;

{ TTypeCompatibilityTests }

procedure TTypeCompatibilityTests.AssignBuiltinTypes;
var
  mConstant: TValueType;
begin
  Assert.IsTrue(Incompatible(B('Integer'), B('string')));
  Assert.IsTrue(Incompatible(B('Integer'), B('Double')));
  Assert.IsTrue(Incompatible(B('Integer'), B('Currency')));
  Assert.IsTrue(Incompatible(B('Integer'), B('Boolean')));
  Assert.IsTrue(Incompatible(B('Integer'), B('Char')));
  Assert.IsTrue(Incompatible(B('Integer'), B('nil')));
  Assert.IsTrue(Incompatible(B('Integer'), B('Pointer')));
  Assert.IsTrue(Incompatible(B('string'), B('Integer')));
  Assert.IsTrue(Incompatible(B('Boolean'), B('Integer')));
  Assert.IsTrue(Incompatible(B('Char'), B('string')));
  Assert.IsTrue(Incompatible(B('Double'), B('string')));
  // Erlaubt: Erweitern, Zeichen in String, PChar in String, Variant, gleiche Kategorie.
  Assert.IsFalse(Incompatible(B('Double'), B('Integer')));
  Assert.IsFalse(Incompatible(B('Currency'), B('Double')));
  Assert.IsFalse(Incompatible(B('Byte'), B('Int64')));
  Assert.IsFalse(Incompatible(B('string'), B('Char')));
  Assert.IsFalse(Incompatible(B('string'), B('PChar')));
  Assert.IsFalse(Incompatible(B('string'), B('nil')));
  Assert.IsFalse(Incompatible(B('Integer'), B('Variant')));
  Assert.IsFalse(Incompatible(B('Variant'), B('string')));
  Assert.IsFalse(Incompatible(B('PChar'), B('string')));
  Assert.IsFalse(Incompatible(B('AnsiString'), B('WideString')));
  // Untypisierte Konstante ',' ist auch ein Zeichen.
  mConstant := B('string');
  mConstant.UntypedText := True;
  Assert.IsFalse(Incompatible(B('Char'), mConstant));
  Assert.IsTrue(Incompatible(B('Integer'), mConstant));
end;

procedure TTypeCompatibilityTests.AssignClassesEnumsAndArrays;
var
  mClass, mEnum, mArray: TValueType;
begin
  mClass := TValueType.Create('TObject', TExpressionCategory.Other, TValueKind.ClassLike);
  mEnum := TValueType.Create('TFarbe', TExpressionCategory.Other, TValueKind.Enum);
  mArray := TValueType.Create('array[0..2] of Integer', TExpressionCategory.Other, TValueKind.StaticArray);
  Assert.IsTrue(Incompatible(mClass, B('Integer')));
  Assert.IsTrue(Incompatible(mClass, B('string')));
  Assert.IsTrue(Incompatible(mClass, mEnum));
  Assert.IsFalse(Incompatible(mClass, B('nil')));
  Assert.IsFalse(Incompatible(mClass, B('Pointer')));
  Assert.IsFalse(Incompatible(mClass, B('Variant')));
  Assert.IsTrue(Incompatible(B('Integer'), mClass));
  Assert.IsTrue(Incompatible(B('string'), mEnum));
  Assert.IsTrue(Incompatible(mEnum, B('Integer')));
  Assert.IsTrue(Incompatible(mEnum, B('nil')));
  Assert.IsTrue(Incompatible(mArray, B('nil')));
  Assert.IsTrue(Incompatible(mArray, B('Integer')));
  // array[0..2] of Char := 'abc' übersetzt dcc.
  Assert.IsFalse(Incompatible(mArray, B('string')));
  Assert.IsFalse(Incompatible(mArray, B('Char')));
end;

procedure TTypeCompatibilityTests.UnknownAndOpenKindsStayOpen;
var
  mRecord, mUnknown: TValueType;
begin
  mRecord := TValueType.Create('TBetrag', TExpressionCategory.Other, TValueKind.Other);
  mUnknown := Default(TValueType);
  Assert.IsFalse(Incompatible(mRecord, B('Integer')));
  Assert.IsFalse(Incompatible(B('Integer'), mRecord));
  Assert.IsFalse(Incompatible(mUnknown, B('Integer')));
  Assert.IsFalse(Incompatible(B('Integer'), mUnknown));
  Assert.AreEqual(Ord(TValueKind.Other), Ord(B('TKunde').Kind));
  Assert.IsFalse(mUnknown.Known);
end;

procedure TTypeCompatibilityTests.BinaryOperators;
begin
  Assert.AreEqual(Ord(TOperatorFit.NotApplicable), Ord(TTypeCompatibility.OperatorFit('-', B('string'), B('Char'))));
  Assert.AreEqual(Ord(TOperatorFit.NotApplicable), Ord(TTypeCompatibility.OperatorFit('div', B('Double'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.NotApplicable), Ord(TTypeCompatibility.OperatorFit('and', B('Double'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.NotApplicable), Ord(TTypeCompatibility.OperatorFit('+', B('Boolean'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.NotApplicable), Ord(TTypeCompatibility.OperatorFit('*', B('string'), B('string'))));
  Assert.AreEqual(Ord(TOperatorFit.Incompatible), Ord(TTypeCompatibility.OperatorFit('+', B('string'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.Incompatible), Ord(TTypeCompatibility.OperatorFit('+', B('Double'), B('string'))));
  Assert.AreEqual(Ord(TOperatorFit.Incompatible), Ord(TTypeCompatibility.OperatorFit('+', B('set of Byte'),
    B('set of Char'))));
  Assert.AreEqual(Ord(TOperatorFit.Fits), Ord(TTypeCompatibility.OperatorFit('+', B('Integer'), B('Double'))));
  Assert.AreEqual(Ord(TOperatorFit.Fits), Ord(TTypeCompatibility.OperatorFit('+', B('string'), B('Char'))));
  Assert.AreEqual(Ord(TOperatorFit.Fits), Ord(TTypeCompatibility.OperatorFit('and', B('Boolean'), B('Boolean'))));
  Assert.AreEqual(Ord(TOperatorFit.Fits), Ord(TTypeCompatibility.OperatorFit('shl', B('Integer'), B('Byte'))));
  Assert.AreEqual(Ord(TOperatorFit.Fits), Ord(TTypeCompatibility.OperatorFit('-', B('set of Byte'), B('set of Byte'))));
  // Offen: Zeiger, Variant, Mischungen, Vergleiche, Char + Zahl.
  Assert.AreEqual(Ord(TOperatorFit.Unknown), Ord(TTypeCompatibility.OperatorFit('+', B('PChar'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.Unknown), Ord(TTypeCompatibility.OperatorFit('+', B('Variant'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.Unknown), Ord(TTypeCompatibility.OperatorFit('and', B('Integer'), B('Boolean'))));
  Assert.AreEqual(Ord(TOperatorFit.Unknown), Ord(TTypeCompatibility.OperatorFit('=', B('string'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.Unknown), Ord(TTypeCompatibility.OperatorFit('+', B('Char'), B('Integer'))));
  Assert.AreEqual(Ord(TOperatorFit.Unknown), Ord(TTypeCompatibility.OperatorFit('+', B('TBetrag'), B('Integer'))));
end;

procedure TTypeCompatibilityTests.UnaryOperators;
begin
  Assert.IsTrue(TTypeCompatibility.UnaryNotApplicable('not', B('string')));
  Assert.IsTrue(TTypeCompatibility.UnaryNotApplicable('not', B('Double')));
  Assert.IsTrue(TTypeCompatibility.UnaryNotApplicable('-', B('Boolean')));
  Assert.IsTrue(TTypeCompatibility.UnaryNotApplicable('-', B('string')));
  Assert.IsFalse(TTypeCompatibility.UnaryNotApplicable('not', B('Integer')));
  Assert.IsFalse(TTypeCompatibility.UnaryNotApplicable('not', B('Boolean')));
  Assert.IsFalse(TTypeCompatibility.UnaryNotApplicable('-', B('Double')));
  Assert.IsFalse(TTypeCompatibility.UnaryNotApplicable('-', B('Variant')));
  Assert.IsFalse(TTypeCompatibility.UnaryNotApplicable('-', B('TBetrag')));
end;

procedure TTypeCompatibilityTests.VarParameters;
begin
  Assert.IsTrue(TTypeCompatibility.VarParamDiffers(B('Integer'), B('Byte')));
  Assert.IsTrue(TTypeCompatibility.VarParamDiffers(B('string'), B('AnsiString')));
  Assert.IsTrue(TTypeCompatibility.VarParamDiffers(B('Double'), B('Single')));
  // Aliase der Unit System sind derselbe Typ; Plattformtypen bleiben offen.
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('Integer'), B('LongInt')));
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('Integer'), B('Int32')));
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('string'), B('UnicodeString')));
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('Char'), B('WideChar')));
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('NativeInt'), B('Integer')));
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('Extended'), B('Double')));
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('Pointer'), B('PChar')));
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(B('TKunde'), B('Integer')));
  // Ein Alias TFloat = Single trägt die Kategorie von Single, ist aber kein eingebauter Name: offen.
  Assert.IsFalse(TTypeCompatibility.VarParamDiffers(TValueType.Create('TFloat', TExpressionCategory.Float,
    TValueKind.Builtin), B('Single')));
end;

procedure TTypeCompatibilityTests.Helpers;
begin
  Assert.IsTrue(TTypeCompatibility.PlatformDependent('NativeInt'));
  Assert.IsTrue(TTypeCompatibility.PlatformDependent('System.Extended'));
  Assert.IsFalse(TTypeCompatibility.PlatformDependent('Integer'));
  Assert.IsTrue(TTypeCompatibility.IsLongString('AnsiString'));
  Assert.IsFalse(TTypeCompatibility.IsLongString('ShortString'));
  Assert.AreEqual('Byte', TTypeCompatibility.SetElement('set of Byte'));
  Assert.AreEqual('', TTypeCompatibility.SetElement('TFarben'));
  Assert.AreEqual(Ord(TValueKind.Builtin), Ord(B('Integer').Kind));
  Assert.AreEqual(Ord(TExpressionCategory.Nil_), Ord(B('nil').Category));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeCompatibilityTests);

end.
