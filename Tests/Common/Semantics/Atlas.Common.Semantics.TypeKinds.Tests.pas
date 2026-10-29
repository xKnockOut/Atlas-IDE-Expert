unit Atlas.Common.Semantics.TypeKinds.Tests;

// Tests von TResolvedTypeKinds (#1370): eingebaute Namen, Typtexte von Aliasen,
// aufgelöste Typen aus der Namensauflösung, einfache Werte, Beschreibungen und
// der Typtext hinter "=" eines Kopfs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TResolvedTypeKindsTests = class
  public
    [Test]
    procedure BuiltinNames;
    [Test]
    procedure TypeTexts;
    [Test]
    procedure ResolvedTypes;
    [Test]
    procedure SimpleValuesAndDescriptions;
    [Test]
    procedure DeclaredTextOfSignature;
  end;

implementation

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeKinds;

function Kind(AKind: TResolvedTypeKind): Integer;
begin
  Result := Ord(AKind);
end;

procedure TResolvedTypeKindsTests.BuiltinNames;
begin
  Assert.AreEqual(Kind(TResolvedTypeKind.Integer_), Kind(TResolvedTypeKinds.OfBuiltin('Integer')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Integer_), Kind(TResolvedTypeKinds.OfBuiltin('System.NativeUInt')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Float), Kind(TResolvedTypeKinds.OfBuiltin('Double')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Currency_), Kind(TResolvedTypeKinds.OfBuiltin('Currency')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Boolean_), Kind(TResolvedTypeKinds.OfBuiltin('LongBool')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Char_), Kind(TResolvedTypeKinds.OfBuiltin('AnsiChar')));
  Assert.AreEqual(Kind(TResolvedTypeKind.String_), Kind(TResolvedTypeKinds.OfBuiltin('string')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Variant_), Kind(TResolvedTypeKinds.OfBuiltin('OleVariant')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Pointer_), Kind(TResolvedTypeKinds.OfBuiltin('PChar')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Unknown), Kind(TResolvedTypeKinds.OfBuiltin('TKunde')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Unknown), Kind(TResolvedTypeKinds.OfBuiltin('')));
end;

procedure TResolvedTypeKindsTests.TypeTexts;
begin
  Assert.AreEqual(Kind(TResolvedTypeKind.Pointer_), Kind(TResolvedTypeKinds.OfText('^Integer')));
  Assert.AreEqual(Kind(TResolvedTypeKind.ClassReference), Kind(TResolvedTypeKinds.OfText('class of TObject')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Set_), Kind(TResolvedTypeKinds.OfText('set of TFarbe')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Array_), Kind(TResolvedTypeKinds.OfText('array of Byte')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Array_), Kind(TResolvedTypeKinds.OfText('packed array[0..3] of Byte')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Procedure_), Kind(TResolvedTypeKinds.OfText('procedure(A: Integer)')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Procedure_), Kind(TResolvedTypeKinds.OfText('reference to function: Integer')));
  Assert.AreEqual(Kind(TResolvedTypeKind.File_), Kind(TResolvedTypeKinds.OfText('file of TPunkt')));
  Assert.AreEqual(Kind(TResolvedTypeKind.File_), Kind(TResolvedTypeKinds.OfText('Text')));
  Assert.AreEqual(Kind(TResolvedTypeKind.String_), Kind(TResolvedTypeKinds.OfText('string[20]')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Enumeration), Kind(TResolvedTypeKinds.OfText('(Rot, Gruen)')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Integer_), Kind(TResolvedTypeKinds.OfText('type Integer')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Unknown), Kind(TResolvedTypeKinds.OfText('1..10')));
  Assert.AreEqual(Kind(TResolvedTypeKind.Unknown), Kind(TResolvedTypeKinds.OfText('TFremd')));
end;

procedure TResolvedTypeKindsTests.ResolvedTypes;
var
  mType: TResolvedSymbol;
begin
  mType := Default(TResolvedSymbol);
  Assert.AreEqual(Kind(TResolvedTypeKind.Unknown), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.Kind := TResolvedKind.Symbol;
  mType.Name := 'Integer';
  mType.SymbolKind := TIndexSymbolKind.RecordType;
  mType.Builtin := True;
  // Eingebaute Typen tragen RecordType, zählen aber nach ihrem Namen.
  Assert.AreEqual(Kind(TResolvedTypeKind.Integer_), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.Builtin := False;
  mType.Name := 'TPunkt';
  Assert.AreEqual(Kind(TResolvedTypeKind.Record_), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.SymbolKind := TIndexSymbolKind.ClassType;
  Assert.AreEqual(Kind(TResolvedTypeKind.Class_), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.SymbolKind := TIndexSymbolKind.ObjectType;
  Assert.AreEqual(Kind(TResolvedTypeKind.Object_), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.SymbolKind := TIndexSymbolKind.InterfaceType;
  Assert.AreEqual(Kind(TResolvedTypeKind.Interface_), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.SymbolKind := TIndexSymbolKind.HelperType;
  Assert.AreEqual(Kind(TResolvedTypeKind.Helper), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.SymbolKind := TIndexSymbolKind.EnumType;
  Assert.AreEqual(Kind(TResolvedTypeKind.Enumeration), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.SymbolKind := TIndexSymbolKind.TypeAlias;
  mType.Signature := 'PZahl = ^Integer;';
  Assert.AreEqual(Kind(TResolvedTypeKind.Pointer_), Kind(TResolvedTypeKinds.OfType(mType)));
  mType.Signature := '';
  Assert.AreEqual(Kind(TResolvedTypeKind.Unknown), Kind(TResolvedTypeKinds.OfType(mType)));
  Assert.AreEqual(Kind(TResolvedTypeKind.ClassReference), Kind(TResolvedTypeKinds.OfType(mType,
    'class of TKunde')));
  // Variablen sind keine Typen.
  mType.SymbolKind := TIndexSymbolKind.Variable;
  Assert.AreEqual(Kind(TResolvedTypeKind.Unknown), Kind(TResolvedTypeKinds.OfType(mType)));
end;

procedure TResolvedTypeKindsTests.SimpleValuesAndDescriptions;
begin
  Assert.IsTrue(TResolvedTypeKinds.IsSimpleValue(TResolvedTypeKind.Integer_));
  Assert.IsTrue(TResolvedTypeKinds.IsSimpleValue(TResolvedTypeKind.Enumeration));
  Assert.IsTrue(TResolvedTypeKinds.IsSimpleValue(TResolvedTypeKind.Char_));
  Assert.IsFalse(TResolvedTypeKinds.IsSimpleValue(TResolvedTypeKind.String_));
  Assert.IsFalse(TResolvedTypeKinds.IsSimpleValue(TResolvedTypeKind.Pointer_));
  Assert.IsFalse(TResolvedTypeKinds.IsSimpleValue(TResolvedTypeKind.Variant_));
  Assert.IsFalse(TResolvedTypeKinds.IsSimpleValue(TResolvedTypeKind.Unknown));
  Assert.AreEqual('eine Klasse', TResolvedTypeKinds.Describe(TResolvedTypeKind.Class_));
  Assert.AreEqual('ein Record', TResolvedTypeKinds.Describe(TResolvedTypeKind.Record_));
  Assert.AreEqual('eine Klassenreferenz', TResolvedTypeKinds.Describe(TResolvedTypeKind.ClassReference));
end;

procedure TResolvedTypeKindsTests.DeclaredTextOfSignature;
begin
  Assert.AreEqual('^Integer', TResolvedTypeKinds.DeclaredText('PZahl = ^Integer;'));
  Assert.AreEqual('array of T', TResolvedTypeKinds.DeclaredText('TArray<T> = array of T;'));
  Assert.AreEqual('Integer', TResolvedTypeKinds.DeclaredText('Wert: Integer'));
  Assert.AreEqual('', TResolvedTypeKinds.DeclaredText('TKunde'));
end;

initialization
  TDUnitX.RegisterTestFixture(TResolvedTypeKindsTests);

end.
