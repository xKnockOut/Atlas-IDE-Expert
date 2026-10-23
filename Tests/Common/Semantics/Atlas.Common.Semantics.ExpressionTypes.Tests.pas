unit Atlas.Common.Semantics.ExpressionTypes.Tests;

// Typ des markierten Ausdrucks (#689): Arithmetik mit gemischten Typen,
// Generics, Aliase, Überladungen, konstante Ausdrücke, Fehler, Mengen,
// Zeiger, anonyme Methoden und die Erweiterung auf den umschließenden
// Ausdruck.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.ExpressionTypes;

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
  LB = #13#10;
  MainFile = 'C:\P\Haupt.pas';
  TypesFile = 'C:\P\Typen.pas';

  UnitTypes =
    'unit Typen;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TFarbe = (Rot, Gruen, Blau);' + LB +
    '  TFarben = set of TFarbe;' + LB +
    '  TKunde = class' + LB +
    '    Name: string;' + LB +
    '  end;' + LB +
    '  PKunde = ^TKunde;' + LB +
    '  TListe<T> = class' + LB +
    '  private' + LB +
    '    function GetItem(I: Integer): T;' + LB +
    '  public' + LB +
    '    function First: T;' + LB +
    '    property Items[I: Integer]: T read GetItem; default;' + LB +
    '  end;' + LB +
    'implementation' + LB +
    'function TListe<T>.GetItem(I: Integer): T;' + LB +
    'begin' + LB +
    'end;' + LB +
    'function TListe<T>.First: T;' + LB +
    'begin' + LB +
    'end;' + LB +
    'end.';

  UnitMain =
    'unit Haupt;' + LB +
    'interface' + LB +
    'uses Typen;' + LB +
    'type' + LB +
    '  TRec = record' + LB +
    '    A: Integer;' + LB +
    '    B: Byte;' + LB +
    '    C: Int64;' + LB +
    '  end;' + LB +
    '  TPacked = packed record' + LB +
    '    A: Byte;' + LB +
    '    B: Integer;' + LB +
    '  end;' + LB +
    '  TZahl = Integer;' + LB +
    '  TGruppen = TListe<TKunde>;' + LB +
    'implementation' + LB +
    'function Max(A, B: Integer): Integer; overload;' + LB +
    'begin' + LB +
    '  Result := A;' + LB +
    'end;' + LB +
    'function Max(A, B: Double): Double; overload;' + LB +
    'begin' + LB +
    '  Result := A;' + LB +
    'end;' + LB +
    'procedure Leer;' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure Run;' + LB +
    'const' + LB +
    '  Faktor = 3;' + LB +
    'var' + LB +
    '  Price, Shipping: Currency;' + LB +
    '  Count: Integer;' + LB +
    '  Big: Int64;' + LB +
    '  Card: Cardinal;' + LB +
    '  B: Byte;' + LB +
    '  D: Double;' + LB +
    '  S: string;' + LB +
    '  C: Char;' + LB +
    '  V: Variant;' + LB +
    '  L: TListe<TKunde>;' + LB +
    '  G: TGruppen;' + LB +
    '  K: TKunde;' + LB +
    '  Z: TZahl;' + LB +
    '  Arr: array of TKunde;' + LB +
    '  Farben: TFarben;' + LB +
    '  P: PKunde;' + LB +
    '  F: TProc;' + LB +
    'begin' + LB +
    '  Price := Price * Count + Shipping;' + LB +
    '  Big := Count + Big;' + LB +
    '  Big := Card + Count;' + LB +
    '  Card := Card + Card;' + LB +
    '  Count := B + B;' + LB +
    '  D := D * Count;' + LB +
    '  D := Count / 2;' + LB +
    '  Count := Count div 2;' + LB +
    '  S := S + C;' + LB +
    '  S := V;' + LB +
    '  K := L.First;' + LB +
    '  K := L[0];' + LB +
    '  K := G.First;' + LB +
    '  G := G;' + LB +
    '  D := Z + D;' + LB +
    '  Count := Max(Count, Count);' + LB +
    '  D := Max(D, Count);' + LB +
    '  Count := SizeOf(TRec) * 2;' + LB +
    '  Count := SizeOf(TPacked);' + LB +
    '  Count := Faktor * 4;' + LB +
    '  Count := Count + S;' + LB +
    '  Count := Unbekannt + 1;' + LB +
    '  Leer;' + LB +
    '  Farben := Farben + [Blau];' + LB +
    '  Farben := [Rot, Gruen];' + LB +
    '  S := K.Name;' + LB +
    '  K := Arr[0];' + LB +
    '  K := P^;' + LB +
    '  S := P^.Name;' + LB +
    '  if not (Count > 0) then' + LB +
    '    K := TKunde(K);' + LB +
    '  K := TKunde.Create;' + LB +
    '  F := procedure(A: Integer) begin end;' + LB +
    '  Count := Length(S) + Ord(C);' + LB +
    'end;' + LB +
    'end.';

procedure TExpressionTypesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitTypes, TypesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TExpressionTypesTests.TearDown;
begin
  FIndex := nil;
end;

function Describe(const AIndex: ISymbolIndex; AStart, AEnd: Integer;
  const AOptions: TExpressionTypeOptions): TExpressionTypeInfo;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Types: TExpressionTypes;
begin
  Tree := TPascalParser.Parse(UnitMain);
  Resolver := TNameResolver.Create(AIndex, nil);
  try
    Resolver.PinTree(Tree, MainFile);
    Types := TExpressionTypes.Create(Resolver, Tree, MainFile, UnitMain, AIndex, AOptions);
    try
      Result := Types.DescribeAt(AStart, AEnd, False);
    finally
      Types.Free;
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

/// <summary>Anfang (0-basiert) von AText im Rumpf von Run.</summary>
function BodyPos(const AText: string): Integer;
begin
  Result := Pos(AText, UnitMain, Pos('begin' + LB + '  Price', UnitMain)) - 1;
end;

function TExpressionTypesTests.TypeIn(const AContext, AInner: string): TExpressionTypeInfo;
var
  Start: Integer;
begin
  Start := BodyPos(AContext);
  Assert.IsTrue(Start >= 0, AContext);
  Start := Start + Pos(AInner, AContext) - 1;
  Result := Describe(FIndex, Start, Start + Length(AInner), TExpressionTypeOptions.Default);
end;

function TExpressionTypesTests.TypeOf(const AExpression: string;
  const AOptions: TExpressionTypeOptions): TExpressionTypeInfo;
var
  Start: Integer;
begin
  Start := BodyPos(AExpression);
  Assert.IsTrue(Start >= 0, AExpression);
  Result := Describe(FIndex, Start, Start + Length(AExpression), AOptions);
end;

function TExpressionTypesTests.TypeOf(const AExpression: string): TExpressionTypeInfo;
begin
  Result := TypeOf(AExpression, TExpressionTypeOptions.Default);
end;

function TExpressionTypesTests.Expanded(const AContext, AInner: string; ASteps: Integer): string;
var
  Tree: TSyntaxTree;
  Node: TSyntaxNode;
  Start, Step: Integer;
begin
  Start := BodyPos(AContext) + Pos(AInner, AContext) - 1;
  Tree := TPascalParser.Parse(UnitMain);
  try
    Node := TExpressionTypes.FindExpression(Tree, Start, Start + Length(AInner), False);
    for Step := 1 to ASteps do
      if Node <> nil then
        Node := TExpressionTypes.FindExpression(Tree, Node.StartOffset, Node.EndOffset, True);
    Result := '';
    if Node <> nil then
      Result := Copy(UnitMain, Node.StartOffset + 1, Node.EndOffset - Node.StartOffset);
  finally
    Tree.Free;
  end;
end;

function TExpressionTypesTests.ConversionsText(const AInfo: TExpressionTypeInfo): string;
var
  Conversion: TExpressionConversion;
begin
  Result := '';
  for Conversion in AInfo.Conversions do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Conversion.Expression + ':' + Conversion.FromType + '>' + Conversion.ToType;
    if Conversion.Kind = TExpressionConversionKind.Convert then
      Result := Result + '!';
  end;
end;

procedure TExpressionTypesTests.MixedArithmetic;
var
  Info: TExpressionTypeInfo;
begin
  Info := TypeOf('Price * Count + Shipping');
  Assert.AreEqual('Currency', Info.TypeName);
  Assert.AreEqual('Count:Integer>Currency', ConversionsText(Info));
  Assert.AreEqual('Price * Count + Shipping', Info.Expression);
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
  Info: TExpressionTypeInfo;
begin
  Info := TypeOf('S + C');
  Assert.AreEqual('string', Info.TypeName);
  Assert.AreEqual('C:Char>string!', ConversionsText(Info));
  Info := TypeIn('S := V;', 'V');
  Assert.AreEqual('Variant', Info.TypeName);
  Assert.AreEqual('V:Variant>string!', ConversionsText(Info), 'Zuweisung wandelt um');
end;

procedure TExpressionTypesTests.GenericsAndAliases;
var
  Info: TExpressionTypeInfo;
begin
  Info := TypeOf('L.First');
  Assert.AreEqual('TKunde', Info.TypeName, 'T eingesetzt');
  Assert.AreEqual(TypesFile, Info.TypeFile);
  Assert.AreEqual(5, Info.TypeLine, 'Zeile von TKunde');
  Assert.AreEqual('TKunde', TypeOf('L[0]').TypeName, 'Standard-Property');
  Assert.AreEqual('TKunde', TypeOf('G.First').TypeName, 'ueber den Alias');
  Info := TypeIn('G := G;', 'G');
  Assert.AreEqual('TGruppen', Info.TypeName);
  Assert.AreEqual('TListe<TKunde>', Info.BaseName, 'Grundtyp des Alias');
  Assert.AreEqual(MainFile, Info.TypeFile, 'Sprung zum Alias');
  Info := TypeOf('G := G');
  Assert.IsTrue(Info.Error = TExpressionErrorKind.NoExpression, 'Zuweisung ist kein Ausdruck');
  Info := TypeOf('Z + D');
  Assert.AreEqual('Double', Info.TypeName, 'Alias auf Integer rechnet wie Integer');
end;

procedure TExpressionTypesTests.OverloadsAndArguments;
var
  Info: TExpressionTypeInfo;
begin
  Info := TypeOf('Max(Count, Count)');
  Assert.AreEqual('Integer', Info.TypeName);
  Assert.IsTrue(Pos('Integer', Info.Overload) > 0, Info.Overload);
  Info := TypeOf('Max(D, Count)');
  Assert.AreEqual('Double', Info.TypeName);
  Assert.IsTrue(Pos('Double', Info.Overload) > 0, Info.Overload);
  Assert.AreEqual('Count:Integer>Double', ConversionsText(Info));
end;

procedure TExpressionTypesTests.ConstantValues;
var
  Info: TExpressionTypeInfo;
begin
  Info := TypeOf('SizeOf(TRec) * 2');
  Assert.AreEqual('Integer', Info.TypeName);
  Assert.IsTrue(Info.HasValue);
  Assert.AreEqual(Int64(32), Info.Value, '4 + 1 + 3 Fuellbytes + 8 = 16');
  Info := TypeOf('SizeOf(TPacked)');
  Assert.IsTrue(Info.HasValue);
  Assert.AreEqual(Int64(5), Info.Value, 'packed');
  Info := TypeOf('Faktor * 4');
  Assert.IsTrue(Info.HasValue);
  Assert.AreEqual(Int64(12), Info.Value);
  Assert.IsFalse(TypeOf('Count + Big').HasValue, 'Variablen haben keinen Wert');
end;

procedure TExpressionTypesTests.Errors;
var
  Info: TExpressionTypeInfo;
begin
  Info := TypeIn('Count := Count + S;', 'Count + S');
  Assert.IsFalse(Info.Found, Info.TypeName + ' ' + Info.Expression);
  Assert.IsTrue(Info.Error = TExpressionErrorKind.OperatorMismatch);
  Assert.AreEqual('+|Integer|string', Info.ErrorDetail);
  Info := TypeOf('Unbekannt + 1');
  Assert.IsTrue(Info.Error = TExpressionErrorKind.UnknownName);
  Assert.AreEqual('Unbekannt', Info.ErrorDetail);
  Info := TypeOf('Leer');
  Assert.IsTrue(Info.Error = TExpressionErrorKind.NoResult);
  Info := TypeIn('Price := Price *', 'ric');
  Assert.AreEqual('Currency', Info.TypeName, 'kleinster umfassender Ausdruck: Price ganz');
  Assert.AreEqual('Price', Info.Expression);
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
  Options: TExpressionTypeOptions;
  Info: TExpressionTypeInfo;
begin
  Options := TExpressionTypeOptions.Default;
  Options.Conversions := False;
  Options.ConstValue := False;
  Info := TypeOf('Price * Count + Shipping', Options);
  Assert.AreEqual(0, Integer(Length(Info.Conversions)));
  Info := TypeOf('Faktor * 4', Options);
  Assert.IsFalse(Info.HasValue);
  Assert.AreEqual('Integer', Info.TypeName);
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionTypesTests);

end.
