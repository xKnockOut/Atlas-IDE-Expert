unit Atlas.Common.Pascal.RoutineSignatures.Tests;

// Tests der gemeinsamen Normalisierung von Routinenköpfen (#1325): Kopf mit
// Constraints, "()" ohne Parameter, Standardwerte und Gruppen, Ergebnistyp,
// Kurzform, generischer Qualifizierer, class constructor, Implementierung aus begin, asm und external,
// Typknoten offener Arrays.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRoutineSignaturesTests = class
  public
    [Test]
    procedure HeadKeepsConstraints;
    [Test]
    procedure ParameterKeys;
    [Test]
    procedure ResultKeys;
    [Test]
    procedure TreeForms;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.RoutineSignatures;

/// <summary>Köpfe (RoutineHeader) des Baums in Quelltextreihenfolge.</summary>
function Headers(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineHeader then
        mFound := mFound + [ANode];
      Result := True;
    end);
  Result := mFound;
end;

procedure TRoutineSignaturesTests.HeadKeepsConstraints;
var
  mRest: string;
begin
  Assert.AreEqual('procedure Reg<TI: IInterface; TC: class>(const N: string)', TRoutineSignatures.Head(
    'procedure Reg<TI: IInterface; TC: class>(const N: string); overload;', mRest));
  Assert.AreEqual(' overload;', mRest);
  Assert.AreEqual('function Foo(A: Integer; B: string): TList<Integer>', TRoutineSignatures.Head(
    'function Foo(A: Integer;  B: string): TList<Integer>; stdcall;', mRest));
  Assert.AreEqual(' stdcall;', mRest);
  // Ein "<" im Standardwert steht in Klammern und zählt nicht.
  Assert.AreEqual('procedure P(A: Boolean = 1 < 2)', TRoutineSignatures.Head('procedure P(A: Boolean = 1 < 2); begin',
    mRest));
end;

procedure TRoutineSignaturesTests.ParameterKeys;
begin
  Assert.AreEqual('', TRoutineSignatures.ParameterKey('procedure TW.Execute()'));
  Assert.AreEqual('', TRoutineSignatures.ParameterKey('procedure TW.Execute'));
  Assert.AreEqual('(consta:string;constb:string)', TRoutineSignatures.ParameterKey(
    'procedure P(const A, B: string)'));
  Assert.AreEqual('(consta:string;constb:string)', TRoutineSignatures.ParameterKey(
    'procedure P(const A: string; const B: string = '''')'));
  Assert.AreEqual('(constt:arrayofptypeinfo)', TRoutineSignatures.ParameterKey(
    'function Inject(const T: array of PTypeInfo): Integer'));
  Assert.AreEqual('(constn:string)', TRoutineSignatures.ParameterKey(
    'procedure TA.Reg<TI, TC>(const N: string)'));
end;

procedure TRoutineSignaturesTests.ResultKeys;
begin
  Assert.AreEqual('|integer', TRoutineSignatures.ResultKey('function Foo(A: Integer): Integer'));
  Assert.AreEqual('|t', TRoutineSignatures.ResultKey('function Foo<T: class>: T'));
  Assert.AreEqual('', TRoutineSignatures.ResultKey('procedure Foo(A: Integer)'));
  Assert.AreEqual('arrayofptypeinfo', TRoutineSignatures.TypeKey('array of  PTypeInfo'));
  // Rumpf eines generischen Typs neben einem gleichnamigen nicht generischen.
  Assert.AreEqual('1', TRoutineSignatures.QualifierMask('constructor TProperty<T>.Create(const A: string)', 'Create'));
  Assert.AreEqual('0', TRoutineSignatures.QualifierMask('constructor TProperty.Create(const A: string)', 'Create'));
  Assert.AreEqual('0', TRoutineSignatures.QualifierMask('procedure TA.Reg<TI, TC>(const N: string)', 'Reg'));
  Assert.AreEqual('10', TRoutineSignatures.QualifierMask('function TDict<TKey, TValue>.TEnumerator.MoveNext: Boolean',
    'MoveNext'));
  Assert.AreEqual('', TRoutineSignatures.QualifierMask('procedure Frei', 'Frei'));
  // Bedingte Direktiven im Qualifizierer: der aktive Zweig ist im Text nicht zu sehen (Indy); Kommentare zählen nicht.
  Assert.AreEqual('?', TRoutineSignatures.QualifierMask('procedure TList{$IFDEF G}<T>{$ENDIF}.Add', 'Add'));
  Assert.AreEqual('0', TRoutineSignatures.QualifierMask('procedure TList{ <T> }.Add', 'Add'));
  // Escapte Namen, Kommentar und Zeilenumbruch hinter dem Punkt (Horse, mORMot2).
  Assert.AreEqual('0', TRoutineSignatures.QualifierMask('function EHorseException.&Type: TMessageType', 'Type'));
  Assert.AreEqual('0', TRoutineSignatures.QualifierMask('function TRttiCustom.{%H-}ValueCompare(Data: Pointer)',
    'ValueCompare'));
  Assert.AreEqual('0', TRoutineSignatures.QualifierMask('function TSynThread. AcquireThread: TStep', 'AcquireThread'));
  Assert.AreEqual('1', TRoutineSignatures.QualifierMask('class function TValueHelper<T>.&&op_Equality(A: T)',
    '&op_Equality'));
end;

procedure TRoutineSignaturesTests.TreeForms;
var
  mTree: TSyntaxTree;
  mHeaders: TArray<TSyntaxNode>;
  mParameters, mParameter: TSyntaxNode;
begin
  mTree := TPascalParser.Parse('unit U;'#10'interface'#10'type'#10'  TA = class'#10'    class constructor Create;'#10 +
    '    constructor Create;'#10'    class procedure Neu;'#10'  end;'#10'function Foo(A: Integer): Integer;'#10 +
    'function Lies(const T: array of Byte): Integer; stdcall;'#10'implementation'#10'function Foo;'#10'asm'#10 +
    'end;'#10'function Lies; external ''a.dll'';'#10'procedure Leer;'#10'begin'#10'end;'#10'procedure Vorab; forward;'#10 +
    'end.');
  try
    mHeaders := Headers(mTree);
    Assert.AreEqual(9, Integer(Length(mHeaders)));
    Assert.IsTrue(TRoutineSignatures.IsClassConstructor(mTree.Tokens, mHeaders[0]));
    Assert.IsFalse(TRoutineSignatures.IsClassConstructor(mTree.Tokens, mHeaders[1]));
    Assert.IsFalse(TRoutineSignatures.IsClassConstructor(mTree.Tokens, mHeaders[2]));
    // Kurzform: weder Parameterliste noch Ergebnistyp.
    Assert.IsFalse(TRoutineSignatures.IsShortForm(mHeaders[3]));
    Assert.IsTrue(TRoutineSignatures.IsShortForm(mHeaders[5]));
    // Implementierung: interface-Deklaration nein, asm, external und begin ja, forward nein.
    Assert.IsFalse(TRoutineSignatures.HasImplementation(mHeaders[3].Parent));
    Assert.IsTrue(TRoutineSignatures.HasImplementation(mHeaders[5].Parent));
    Assert.IsTrue(TRoutineSignatures.HasImplementation(mHeaders[6].Parent));
    Assert.IsTrue(TRoutineSignatures.HasImplementation(mHeaders[7].Parent));
    Assert.IsFalse(TRoutineSignatures.HasImplementation(mHeaders[8].Parent));
    Assert.IsFalse(TRoutineSignatures.HasImplementation(mHeaders[0].Parent));
    // Typknoten eines offenen Arrays.
    mParameters := mHeaders[4].FindChild(TSyntaxKind.Parameters);
    mParameter := mParameters[0];
    Assert.AreEqual(Ord(TSyntaxKind.ArrayType), Ord(TRoutineSignatures.ParameterType(mParameter).Kind));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRoutineSignaturesTests);

end.
