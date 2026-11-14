unit Atlas.Common.Semantics.ExpressionTypes.Tests;

// Typ des markierten Ausdrucks (#689): Arithmetik mit gemischten Typen,
// Generics, Aliase, Überladungen, konstante Ausdrücke, Fehler, Mengen,
// Zeiger, anonyme Methoden und die Erweiterung auf den umschließenden
// Ausdruck.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Semantics.ExpressionTypes.Contract;

type
  [TestFixture]
  TExpressionTypesTests = class
  private
    FIndex: ISymbolIndex;
    /// <summary>Typ des ersten Vorkommens von AExpression im Rumpf von Run.</summary>
    function TypeOf(const AExpression: string): TExpressionTypeInfo; overload;
    function TypeOf(const AExpression: string; const AOptions: TExpressionTypeOptions): TExpressionTypeInfo;
      overload;
    /// <summary>Typ von AInner im ersten Vorkommen von AContext.</summary>
    function TypeIn(const AContext, AInner: string): TExpressionTypeInfo;
    /// <summary>Ausdruck nach ASteps Erweiterungen, ausgehend von AInner im ersten Vorkommen von AContext.</summary>
    function Expanded(const AContext, AInner: string; ASteps: Integer): string;
    function ConversionsText(const AInfo: TExpressionTypeInfo): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MixedArithmetic;
    [Test]
    procedure IntegerWidths;
    [Test]
    procedure StringsVariantsAndConversions;
    [Test]
    procedure GenericsAndAliases;
    [Test]
    procedure OverloadsAndArguments;
    [Test]
    procedure ConstantValues;
    [Test]
    procedure Errors;
    [Test]
    procedure SetsPointersAndCasts;
    [Test]
    procedure AnonymousMethodsAndComparisons;
    [Test]
    procedure ExpandsToEnclosingExpression;
    [Test]
    procedure OptionsSwitchOffExtras;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver;

const
  cLB = #13#10;
  cMainFile = 'C:\P\Haupt.pas';
  cTypesFile = 'C:\P\Typen.pas';

  cUnitTypes =
    'unit Typen;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TFarbe = (Rot, Gruen, Blau);' + cLB +
    '  TFarben = set of TFarbe;' + cLB +
    '  TKunde = class' + cLB +
    '    Name: string;' + cLB +
    '  end;' + cLB +
    '  PKunde = ^TKunde;' + cLB +
    '  TListe<T> = class' + cLB +
    '  private' + cLB +
    '    function GetItem(I: Integer): T;' + cLB +
    '  public' + cLB +
    '    function First: T;' + cLB +
    '    property Items[I: Integer]: T read GetItem; default;' + cLB +
    '  end;' + cLB +
    'implementation' + cLB +
    'function TListe<T>.GetItem(I: Integer): T;' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'function TListe<T>.First: T;' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'end.';

  cUnitMain =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'uses Typen;' + cLB +
    'type' + cLB +
    '  TRec = record' + cLB +
    '    A: Integer;' + cLB +
    '    B: Byte;' + cLB +
    '    C: Int64;' + cLB +
    '  end;' + cLB +
    '  TPacked = packed record' + cLB +
    '    A: Byte;' + cLB +
    '    B: Integer;' + cLB +
    '  end;' + cLB +
    '  TZahl = Integer;' + cLB +
    '  TGruppen = TListe<TKunde>;' + cLB +
    'implementation' + cLB +
    'function Max(A, B: Integer): Integer; overload;' + cLB +
    'begin' + cLB +
    '  Result := A;' + cLB +
    'end;' + cLB +
    'function Max(A, B: Double): Double; overload;' + cLB +
    'begin' + cLB +
    '  Result := A;' + cLB +
    'end;' + cLB +
    'procedure Leer;' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'procedure Run;' + cLB +
    'const' + cLB +
    '  Faktor = 3;' + cLB +
    'var' + cLB +
    '  Price, Shipping: Currency;' + cLB +
    '  Count: Integer;' + cLB +
    '  Big: Int64;' + cLB +
    '  Card: Cardinal;' + cLB +
    '  B: Byte;' + cLB +
    '  D: Double;' + cLB +
    '  S: string;' + cLB +
    '  C: Char;' + cLB +
    '  V: Variant;' + cLB +
    '  L: TListe<TKunde>;' + cLB +
    '  G: TGruppen;' + cLB +
    '  K: TKunde;' + cLB +
    '  Z: TZahl;' + cLB +
    '  Arr: array of TKunde;' + cLB +
    '  Farben: TFarben;' + cLB +
    '  P: PKunde;' + cLB +
    '  F: TProc;' + cLB +
    'begin' + cLB +
    '  Price := Price * Count + Shipping;' + cLB +
    '  Big := Count + Big;' + cLB +
    '  Big := Card + Count;' + cLB +
    '  Card := Card + Card;' + cLB +
    '  Count := B + B;' + cLB +
    '  D := D * Count;' + cLB +
    '  D := Count / 2;' + cLB +
    '  Count := Count div 2;' + cLB +
    '  S := S + C;' + cLB +
    '  S := V;' + cLB +
    '  K := L.First;' + cLB +
    '  K := L[0];' + cLB +
    '  K := G.First;' + cLB +
    '  G := G;' + cLB +
    '  D := Z + D;' + cLB +
    '  Count := Max(Count, Count);' + cLB +
    '  D := Max(D, Count);' + cLB +
    '  Count := SizeOf(TRec) * 2;' + cLB +
    '  Count := SizeOf(TPacked);' + cLB +
    '  Count := Faktor * 4;' + cLB +
    '  Count := Count + S;' + cLB +
    '  Count := Unbekannt + 1;' + cLB +
    '  Leer;' + cLB +
    '  Farben := Farben + [Blau];' + cLB +
    '  Farben := [Rot, Gruen];' + cLB +
    '  S := K.Name;' + cLB +
    '  K := Arr[0];' + cLB +
    '  K := P^;' + cLB +
    '  S := P^.Name;' + cLB +
    '  if not (Count > 0) then' + cLB +
    '    K := TKunde(K);' + cLB +
    '  K := TKunde.Create;' + cLB +
    '  F := procedure(A: Integer) begin end;' + cLB +
    '  Count := Length(S) + Ord(C);' + cLB +
    'end;' + cLB +
    'end.';

procedure TExpressionTypesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitTypes, cTypesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TExpressionTypesTests.TearDown;
begin
  FIndex := nil;
end;

function Describe(const AIndex: ISymbolIndex; AStart, AEnd: Integer;
  const AOptions: TExpressionTypeOptions): TExpressionTypeInfo;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mTypes: TExpressionTypes;
begin
  mTree := TPascalParser.Parse(cUnitMain);
  mResolver := TNameResolver.Create(AIndex, nil);
  try
    mResolver.PinTree(mTree, cMainFile);
    mTypes := TExpressionTypes.Create(mResolver, mTree, cMainFile, cUnitMain, AIndex, AOptions);
    try
      Result := mTypes.DescribeAt(AStart, AEnd, False);
    finally
      mTypes.Free;
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

/// <summary>Anfang (0-basiert) von AText im Rumpf von Run.</summary>
function BodyPos(const AText: string): Integer;
begin
  Result := Pos(AText, cUnitMain, Pos('begin' + cLB + '  Price', cUnitMain)) - 1;
end;

function TExpressionTypesTests.TypeIn(const AContext, AInner: string): TExpressionTypeInfo;
var
  mStart: Integer;
begin
  mStart := BodyPos(AContext);
  Assert.IsTrue(mStart >= 0, AContext);
  mStart := mStart + Pos(AInner, AContext) - 1;
  Result := Describe(FIndex, mStart, mStart + Length(AInner), TExpressionTypeOptions.Default);
end;

function TExpressionTypesTests.TypeOf(const AExpression: string;
  const AOptions: TExpressionTypeOptions): TExpressionTypeInfo;
var
  mStart: Integer;
begin
  mStart := BodyPos(AExpression);
  Assert.IsTrue(mStart >= 0, AExpression);
  Result := Describe(FIndex, mStart, mStart + Length(AExpression), AOptions);
end;

function TExpressionTypesTests.TypeOf(const AExpression: string): TExpressionTypeInfo;
begin
  Result := TypeOf(AExpression, TExpressionTypeOptions.Default);
end;

function TExpressionTypesTests.Expanded(const AContext, AInner: string; ASteps: Integer): string;
var
  mTree: TSyntaxTree;
  mNode: TSyntaxNode;
  mStart, mStep: Integer;
begin
  mStart := BodyPos(AContext) + Pos(AInner, AContext) - 1;
  mTree := TPascalParser.Parse(cUnitMain);
  try
    mNode := TExpressionTypes.FindExpression(mTree, mStart, mStart + Length(AInner), False);
    for mStep := 1 to ASteps do
    begin
      if mNode <> nil then
      begin
        mNode := TExpressionTypes.FindExpression(mTree, mNode.StartOffset, mNode.EndOffset, True);
      end;
    end;
    Result := '';
    if mNode <> nil then
    begin
      Result := Copy(cUnitMain, mNode.StartOffset + 1, mNode.EndOffset - mNode.StartOffset);
    end;
  finally
    mTree.Free;
  end;
end;

function TExpressionTypesTests.ConversionsText(const AInfo: TExpressionTypeInfo): string;
var
  mConversion: TExpressionConversion;
begin
  Result := '';
  for mConversion in AInfo.Conversions do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mConversion.Expression + ':' + mConversion.FromType + '>' + mConversion.ToType;
    if mConversion.Kind = TExpressionConversionKind.Convert then
    begin
      Result := Result + '!';
    end;
  end;
end;

procedure TExpressionTypesTests.MixedArithmetic;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := TypeOf('Price * Count + Shipping');
  Assert.AreEqual('Currency', mInfo.TypeName);
  Assert.AreEqual('Count:Integer>Currency', ConversionsText(mInfo));
  Assert.AreEqual('Price * Count + Shipping', mInfo.Expression);
  Assert.AreEqual('Double', TypeOf('D * Count').TypeName);
  Assert.AreEqual('Extended', TypeOf('Count / 2').TypeName);
  Assert.AreEqual('Integer', TypeOf('Count div 2').TypeName);
  Assert.AreEqual('Integer', TypeOf('Length(S) + Ord(C)').TypeName);
end;

procedure TExpressionTypesTests.IntegerWidths;
begin
  Assert.AreEqual('Int64', TypeOf('Count + Big').TypeName);
  Assert.AreEqual('Int64', TypeOf('Card + Count').TypeName, 'Cardinal mit Vorzeichen');
  Assert.AreEqual('Cardinal', TypeOf('Card + Card').TypeName);
  Assert.AreEqual('Integer', TypeOf('B + B').TypeName, 'Byte rechnet als Integer');
end;

procedure TExpressionTypesTests.StringsVariantsAndConversions;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := TypeOf('S + C');
  Assert.AreEqual('string', mInfo.TypeName);
  Assert.AreEqual('C:Char>string!', ConversionsText(mInfo));
  mInfo := TypeIn('S := V;', 'V');
  Assert.AreEqual('Variant', mInfo.TypeName);
  Assert.AreEqual('V:Variant>string!', ConversionsText(mInfo), 'Zuweisung wandelt um');
end;

procedure TExpressionTypesTests.GenericsAndAliases;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := TypeOf('L.First');
  Assert.AreEqual('TKunde', mInfo.TypeName, 'T eingesetzt');
  Assert.AreEqual(cTypesFile, mInfo.TypeFile);
  Assert.AreEqual(5, mInfo.TypeLine, 'Zeile von TKunde');
  Assert.AreEqual('TKunde', TypeOf('L[0]').TypeName, 'Standard-Property');
  Assert.AreEqual('TKunde', TypeOf('G.First').TypeName, 'ueber den Alias');
  mInfo := TypeIn('G := G;', 'G');
  Assert.AreEqual('TGruppen', mInfo.TypeName);
  Assert.AreEqual('TListe<TKunde>', mInfo.BaseName, 'Grundtyp des Alias');
  Assert.AreEqual(cMainFile, mInfo.TypeFile, 'Sprung zum Alias');
  mInfo := TypeOf('G := G');
  Assert.AreEqual<TExpressionErrorKind>(TExpressionErrorKind.NoExpression, mInfo.Error, 'Zuweisung ist kein Ausdruck');
  mInfo := TypeOf('Z + D');
  Assert.AreEqual('Double', mInfo.TypeName, 'Alias auf Integer rechnet wie Integer');
end;

procedure TExpressionTypesTests.OverloadsAndArguments;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := TypeOf('Max(Count, Count)');
  Assert.AreEqual('Integer', mInfo.TypeName);
  Assert.IsTrue(Pos('Integer', mInfo.Overload) > 0, mInfo.Overload);
  mInfo := TypeOf('Max(D, Count)');
  Assert.AreEqual('Double', mInfo.TypeName);
  Assert.IsTrue(Pos('Double', mInfo.Overload) > 0, mInfo.Overload);
  Assert.AreEqual('Count:Integer>Double', ConversionsText(mInfo));
end;

procedure TExpressionTypesTests.ConstantValues;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := TypeOf('SizeOf(TRec) * 2');
  Assert.AreEqual('Integer', mInfo.TypeName);
  Assert.IsTrue(mInfo.HasValue);
  Assert.AreEqual(Int64(32), mInfo.Value, '4 + 1 + 3 Fuellbytes + 8 = 16');
  mInfo := TypeOf('SizeOf(TPacked)');
  Assert.IsTrue(mInfo.HasValue);
  Assert.AreEqual(Int64(5), mInfo.Value, 'packed');
  mInfo := TypeOf('Faktor * 4');
  Assert.IsTrue(mInfo.HasValue);
  Assert.AreEqual(Int64(12), mInfo.Value);
  Assert.IsFalse(TypeOf('Count + Big').HasValue, 'Variablen haben keinen Wert');
end;

procedure TExpressionTypesTests.Errors;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := TypeIn('Count := Count + S;', 'Count + S');
  Assert.IsFalse(mInfo.Found, mInfo.TypeName + ' ' + mInfo.Expression);
  Assert.AreEqual<TExpressionErrorKind>(TExpressionErrorKind.OperatorMismatch, mInfo.Error);
  Assert.AreEqual('+|Integer|string', mInfo.ErrorDetail);
  mInfo := TypeOf('Unbekannt + 1');
  Assert.AreEqual<TExpressionErrorKind>(TExpressionErrorKind.UnknownName, mInfo.Error);
  Assert.AreEqual('Unbekannt', mInfo.ErrorDetail);
  mInfo := TypeOf('Leer');
  Assert.AreEqual<TExpressionErrorKind>(TExpressionErrorKind.NoResult, mInfo.Error);
  mInfo := TypeIn('Price := Price *', 'ric');
  Assert.AreEqual('Currency', mInfo.TypeName, 'kleinster umfassender Ausdruck: Price ganz');
  Assert.AreEqual('Price', mInfo.Expression);
end;

procedure TExpressionTypesTests.SetsPointersAndCasts;
begin
  Assert.AreEqual('TFarben', TypeOf('Farben + [Blau]').TypeName);
  Assert.AreEqual('set of TFarbe', TypeOf('[Rot, Gruen]').TypeName);
  Assert.AreEqual('string', TypeOf('K.Name').TypeName);
  Assert.AreEqual('TKunde', TypeOf('Arr[0]').TypeName, 'array of');
  Assert.AreEqual('TKunde', TypeIn('K := P^;', 'P^').TypeName);
  Assert.AreEqual('string', TypeOf('P^.Name').TypeName);
  Assert.AreEqual('TKunde', TypeOf('TKunde(K)').TypeName, 'Typumwandlung');
  Assert.AreEqual('TKunde', TypeOf('TKunde.Create').TypeName, 'Konstruktor');
end;

procedure TExpressionTypesTests.AnonymousMethodsAndComparisons;
begin
  Assert.AreEqual('Boolean', TypeOf('Count > 0').TypeName);
  Assert.AreEqual('Boolean', TypeOf('not (Count > 0)').TypeName);
  Assert.AreEqual('reference to procedure(A: Integer)', TypeOf('procedure(A: Integer) begin end').TypeName);
end;

procedure TExpressionTypesTests.ExpandsToEnclosingExpression;
begin
  Assert.AreEqual('Count', Expanded('Price * Count', 'Count', 0));
  Assert.AreEqual('Price * Count', Expanded('Price * Count', 'Count', 1));
  Assert.AreEqual('Price * Count + Shipping', Expanded('Price * Count', 'Count', 2));
  // Weiter geht es nicht: die Zuweisung ist kein Ausdruck.
  Assert.AreEqual('', Expanded('Price * Count', 'Count', 3));
  // Cursor ohne Markierung mitten im Namen.
  Assert.AreEqual('Shipping', Expanded('Shipping;', 'ipp', 0));
end;

procedure TExpressionTypesTests.OptionsSwitchOffExtras;
var
  mOptions: TExpressionTypeOptions;
  mInfo: TExpressionTypeInfo;
begin
  mOptions := TExpressionTypeOptions.Default;
  mOptions.Conversions := False;
  mOptions.ConstValue := False;
  mInfo := TypeOf('Price * Count + Shipping', mOptions);
  Assert.AreEqual(0, Integer(Length(mInfo.Conversions)));
  mInfo := TypeOf('Faktor * 4', mOptions);
  Assert.IsFalse(mInfo.HasValue);
  Assert.AreEqual('Integer', mInfo.TypeName);
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionTypesTests);

end.
