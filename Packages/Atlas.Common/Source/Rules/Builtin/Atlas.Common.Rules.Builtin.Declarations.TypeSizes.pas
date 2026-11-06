unit Atlas.Common.Rules.Builtin.Declarations.TypeSizes;

// Regel type-too-large aus Atlas.Common.Rules.Builtin.Declarations (#1083): statisches Array oder Record ab
// 2 GB (wie E2100), Instanz eines generischen Typs der Datei ab 2 GB (wie E2543). Die Größe ist eine untere
// Grenze aus den Deklarationen; Unbekanntes zählt 0. Gemeldet wird nur der innerste Typ über der Grenze.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TTypeTooLargeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsTypeSizesText = (Title, OverPB, TheType, TooLarge, AtLeast);

const
  cTexts: array[TDeclarationsTypeSizesText] of TAtlasText = (
    (De: 'Typ überschreitet eine Größengrenze'; En: 'Type exceeds a size limit'),
    (De: 'über 1 PB'; En: 'over 1 PB'),
    (De: 'Der Typ'; En: 'The type'),
    (De: '%s ist %s groß; erlaubt sind 2 GB (wie %s).'; En: '%s is %s in size; 2 GB are allowed (like %s).'),
    (De: 'mindestens %s'; En: 'at least %s'));

{$SCOPEDENUMS OFF}

{ TTypeTooLargeRule }

function TTypeTooLargeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('type-too-large', TRuleSeverity.Error,
    cTexts[TDeclarationsTypeSizesText.Title].Text);
end;

const
  // Ab 2 GB meldet Delphi E2100 bzw. E2543.
  TypeSizeLimit = Int64(1) shl 31;
  // Obergrenze der Rechnung, damit Produkte nicht überlaufen.
  TypeSizeCap = Int64(1) shl 50;
  TypeKindsForSize = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
    TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType,
    TSyntaxKind.ClassOfType, TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType,
    TSyntaxKind.SubrangeType, TSyntaxKind.FileType, TSyntaxKind.HelperType];
  // Eingebaute Typen: Größe als untere Grenze; Exakt = auf allen Windows-Plattformen gleich.
  SizeNames: array[0..47] of string = ('Byte', 'ShortInt', 'Boolean', 'ByteBool', 'AnsiChar', 'Int8', 'UInt8',
    'Word', 'SmallInt', 'Char', 'WideChar', 'WordBool', 'Int16', 'UInt16', 'Integer', 'Cardinal', 'LongInt',
    'LongWord', 'Single', 'LongBool', 'FixedInt', 'FixedUInt', 'Int32', 'UInt32', 'Int64', 'UInt64', 'Double',
    'Currency', 'Comp', 'TDateTime', 'TDate', 'TTime', 'Real', 'ShortString', 'TGUID', 'Extended', 'Pointer',
    'PChar', 'PAnsiChar', 'PWideChar', 'string', 'UnicodeString', 'AnsiString', 'WideString', 'NativeInt',
    'NativeUInt', 'Variant', 'OleVariant');
  SizeBytes: array[0..47] of Integer = (1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 256, 16, 8, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 16, 16);
  // Ab diesem Eintrag hängt die Größe von der Plattform ab.
  FirstInexactSize = 35;
  // Elementzahl eingebauter Indextypen.
  CountNames: array[0..11] of string = ('Byte', 'AnsiChar', 'ShortInt', 'Boolean', 'Word', 'Char', 'WideChar',
    'SmallInt', 'Integer', 'Cardinal', 'LongInt', 'LongWord');
  CountValues: array[0..11] of Int64 = (256, 256, 256, 2, 65536, 65536, 65536, 65536, 4294967296, 4294967296,
    4294967296, 4294967296);

type
  /// <summary>Untere Grenze der Größe eines Typs. Exact: genau diese Größe auf allen Windows-Plattformen;
  /// Nested: ein Bestandteil überschreitet die Grenze schon selbst (dort gemeldet).</summary>
  TTypeSize = record
    Bytes: Int64;
    Exact: Boolean;
    Nested: Boolean;
  end;

  /// <summary>Zwischenstand der Felder eines Records: Bytes, Zahl der Felder, Größe des letzten Felds und ob alle
  /// gleich groß sind.</summary>
  TFieldSum = record
    Bytes: Int64;
    Fields: Integer;
    FieldSize: Int64;
    Uniform: Boolean;
  end;

  /// <summary>Rechnet Typgrößen aus den Deklarationen der Datei und dem Index (#1083).</summary>
  TTypeSizes = class
  private
    FText: string;
    FTokens: TArray<TPascalToken>;
    FIndex: ISymbolIndex;
    FTypes: TDictionary<string, TSyntaxNode>;
    FConstants: TDictionary<string, TSyntaxNode>;
    FEnumValues: TDictionary<string, Int64>;
    FDepth: Integer;
    procedure Collect(ARoot: TSyntaxNode);
    procedure AddDeclaration(ANode: TSyntaxNode);
    procedure AddEnumValues(AEnum: TSyntaxNode);
    function Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
    function Count(AIndexType: TSyntaxNode; out AExact: Boolean): Int64;
    function CountOfName(const AName: string; out AExact: Boolean): Int64;
    function Multiply(A, B: Int64): Int64;
    function FieldsOf(ARecord: TSyntaxNode; const AParams, AArgs: TArray<string>; var ASize: TTypeSize): Int64;
    procedure AddField(var ASum: TFieldSum; AField: TSyntaxNode; const AParams, AArgs: TArray<string>;
      var ASize: TTypeSize);
    procedure AddVariant(var ASum: TFieldSum; AVariant: TSyntaxNode; const AParams, AArgs: TArray<string>;
      var ASize: TTypeSize);
    function IndexSize(const AName: string): TTypeSize;
    function RecordIndexSize(const AFileName, AName: string): TTypeSize;
    function SymbolSize(const ALocation: TSymbolLocation; const AName: string): TTypeSize;
    function ReferenceSize(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
    function GenericSize(ANode, AArgs: TSyntaxNode): TTypeSize;
    function ArraySize(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
    destructor Destroy; override;
    /// <summary>Typknoten der Deklaration ANode (TypeDecl, Field, VarDecl); nil ohne.</summary>
    class function TypeNodeOf(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Größe des Typknotens ANode; Typparameter AParams stehen für AArgs.</summary>
    function OfNode(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
    /// <summary>Größe des Typs AName.</summary>
    function OfName(const AName: string; const AParams, AArgs: TArray<string>): TTypeSize;
    /// <summary>Generische Deklaration der Datei zu AName mit ihren Typparametern; nil ohne.</summary>
    function GenericDecl(const AName: string; out AParams: TArray<string>): TSyntaxNode;
  end;

constructor TTypeSizes.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FText := AText;
  FTokens := ATree.Tokens;
  FIndex := AIndex;
  FTypes := TDictionary<string, TSyntaxNode>.Create;
  FConstants := TDictionary<string, TSyntaxNode>.Create;
  FEnumValues := TDictionary<string, Int64>.Create;
  Collect(ATree.Root);
end;

destructor TTypeSizes.Destroy;
begin
  FEnumValues.Free;
  FConstants.Free;
  FTypes.Free;
  inherited;
end;

procedure TTypeSizes.AddEnumValues(AEnum: TSyntaxNode);
var
  Index, Value: Integer;
begin
  // Werte nur ohne explizite Zuweisung (a = 5) sicher.
  for Index := 0 to AEnum.ChildCount - 1 do
  begin
    if AEnum[Index].Kind <> TSyntaxKind.Identifier then
    begin
      Exit;
    end;
  end;
  for Value := 0 to AEnum.ChildCount - 1 do
  begin
    if not FEnumValues.ContainsKey(LowerCase(AEnum[Value].Name)) then
    begin
      FEnumValues.Add(LowerCase(AEnum[Value].Name), Value);
    end;
  end;
end;

procedure TTypeSizes.AddDeclaration(ANode: TSyntaxNode);
begin
  // Bei gleichen Namen gilt die erste Deklaration.
  if (ANode.Kind = TSyntaxKind.TypeDecl) and not FTypes.ContainsKey(LowerCase(ANode.Name)) then
  begin
    FTypes.Add(LowerCase(ANode.Name), ANode);
  end
  else if (ANode.Kind = TSyntaxKind.ConstDecl) and not FConstants.ContainsKey(LowerCase(ANode.Name)) then
  begin
    FConstants.Add(LowerCase(ANode.Name), ANode);
  end
  else if ANode.Kind = TSyntaxKind.EnumType then
  begin
    AddEnumValues(ANode);
  end;
end;

procedure TTypeSizes.Collect(ARoot: TSyntaxNode);
var
  Stack: TArray<TSyntaxNode>;
  Count, Index: Integer;
  Node: TSyntaxNode;
begin
  // Ohne Rekursion (#1094).
  SetLength(Stack, 64);
  Stack[0] := ARoot;
  Count := 1;
  while Count > 0 do
  begin
    Dec(Count);
    Node := Stack[Count];
    AddDeclaration(Node);
    if Count + Node.ChildCount > Length(Stack) then
    begin
      SetLength(Stack, 2 * (Count + Node.ChildCount));
    end;
    for Index := Node.ChildCount - 1 downto 0 do
    begin
      Stack[Count] := Node[Index];
      Inc(Count);
    end;
  end;
end;

class function TTypeSizes.TypeNodeOf(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind in TypeKindsForSize then
    begin
      Exit(ANode[Index]);
    end;
  end;
  Result := nil;
end;

function TTypeSizes.Multiply(A, B: Int64): Int64;
begin
  if (A <= 0) or (B <= 0) then
  begin
    Exit(0);
  end;
  if A > TypeSizeCap div B then
  begin
    Exit(TypeSizeCap);
  end;
  Result := A * B;
end;

function TTypeSizes.Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
var
  First, Last: Integer;
  Lookup: TOrdinalNameLookup;
begin
  AValue := 0;
  if FDepth > 32 then
  begin
    Exit(False);
  end;
  First := TokenAtOffset(FTokens, ANode.StartOffset);
  Last := TokenAtOffset(FTokens, ANode.EndOffset) - 1;
  if Last < First then
  begin
    Exit(False);
  end;
  Lookup :=
    function(const ANames: TArray<string>; ATokenIndex: Integer; out AResult: Int64): Boolean
    var
      Decl: TSyntaxNode;
      Key: string;
    begin
      Result := False;
      AResult := 0;
      if Length(ANames) <> 1 then
      begin
        Exit;
      end;
      Key := LowerCase(ANames[0]);
      if FEnumValues.TryGetValue(Key, AResult) then
      begin
        Exit(True);
      end;
      // Nur untypisierte Konstanten sind echte Konstanten in Typgrenzen.
      if not FConstants.TryGetValue(Key, Decl) or (Decl.ChildCount <> 1) or (TypeNodeOf(Decl) <> nil) then
      begin
        Exit;
      end;
      Inc(FDepth);
      try
        Result := Evaluate(Decl[0], AResult);
      finally
        Dec(FDepth);
      end;
    end;
  Result := TOrdinalConstants.Evaluate(FTokens, First, Last, Lookup, AValue);
end;

function TTypeSizes.CountOfName(const AName: string; out AExact: Boolean): Int64;
var
  Index: Integer;
  Decl, Body: TSyntaxNode;
begin
  AExact := True;
  Index := IndexText(AName, CountNames);
  if Index >= 0 then
  begin
    Exit(CountValues[Index]);
  end;
  AExact := False;
  Result := 0;
  if (FDepth > 32) or not FTypes.TryGetValue(LowerCase(AName), Decl) then
  begin
    Exit;
  end;
  Body := TypeNodeOf(Decl);
  if Body = nil then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    Result := Count(Body, AExact);
  finally
    Dec(FDepth);
  end;
end;

function TTypeSizes.Count(AIndexType: TSyntaxNode; out AExact: Boolean): Int64;
var
  Low, High: Int64;
  Index: Integer;
begin
  AExact := False;
  Result := 0;
  case AIndexType.Kind of
    TSyntaxKind.SubrangeType:
      if (AIndexType.ChildCount = 2) and Evaluate(AIndexType[0], Low) and Evaluate(AIndexType[1], High) then
      begin
        AExact := True;
        if High >= Low then
        begin
          Result := High - Low + 1;
        end;
      end;
    TSyntaxKind.TypeReference:
      Result := CountOfName(AIndexType.Name, AExact);
    TSyntaxKind.EnumType:
      begin
        // Mit explizit zugewiesenen Werten (a = 5) mindestens so viele Elemente wie Namen.
        AExact := True;
        for Index := 0 to AIndexType.ChildCount - 1 do
        begin
          if AIndexType[Index].Kind = TSyntaxKind.Identifier then
          begin
            Inc(Result);
          end
          else
          begin
            AExact := False;
          end;
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TTypeSizes.AddField(var ASum: TFieldSum; AField: TSyntaxNode; const AParams, AArgs: TArray<string>;
  var ASize: TTypeSize);
var
  Names: Integer;
  Part: TTypeSize;
begin
  if TypeNodeOf(AField) = nil then
  begin
    Exit;
  end;
  Part := OfNode(TypeNodeOf(AField), AParams, AArgs);
  Names := Length(AField.Name.Split([',']));
  Inc(ASum.Fields, Names);
  if (ASum.FieldSize <> 0) and (ASum.FieldSize <> Part.Bytes) then
  begin
    ASum.Uniform := False;
  end;
  ASum.FieldSize := Part.Bytes;
  ASum.Bytes := ASum.Bytes + Multiply(Part.Bytes, Names);
  ASize.Exact := ASize.Exact and Part.Exact;
  ASize.Nested := ASize.Nested or Part.Nested or (Part.Bytes >= TypeSizeLimit);
end;

procedure TTypeSizes.AddVariant(var ASum: TFieldSum; AVariant: TSyntaxNode; const AParams, AArgs: TArray<string>;
  var ASize: TTypeSize);
var
  Inner: Integer;
  Item: TSyntaxNode;
  Largest, Branch: Int64;
begin
  // Ein Selektorfeld (case Art: TArt of) belegt Platz, ein bloßer Selektortyp nicht.
  Largest := 0;
  for Inner := 0 to AVariant.ChildCount - 1 do
  begin
    Item := AVariant[Inner];
    if Item.Kind = TSyntaxKind.Field then
    begin
      ASum.Bytes := ASum.Bytes + OfNode(TypeNodeOf(Item), AParams, AArgs).Bytes;
      Inc(ASum.Fields);
    end
    else if Item.Kind = TSyntaxKind.CaseItem then
    begin
      Branch := FieldsOf(Item, AParams, AArgs, ASize);
      if Branch > Largest then
      begin
        Largest := Branch;
      end;
    end;
  end;
  ASum.Bytes := ASum.Bytes + Largest;
  ASize.Exact := False;
end;

/// <summary>Alle Felder gleich groß mit 1, 2, 4 oder 8 Byte: Die Ausrichtung fügt keine Lücken ein.</summary>
function WithoutGaps(const ASum: TFieldSum): Boolean;
begin
  Result := False;
  if ASum.Uniform then
  begin
    case ASum.FieldSize of
      1, 2, 4, 8:
        Result := True;
    else
      // Andere Größen können Lücken haben.
    end;
  end;
end;

function TTypeSizes.FieldsOf(ARecord: TSyntaxNode; const AParams, AArgs: TArray<string>;
  var ASize: TTypeSize): Int64;
var
  Index: Integer;
  Child: TSyntaxNode;
  Sum: TFieldSum;
begin
  // Summe der Felder; varianter Teil: Selektor plus größter Zweig.
  Sum := Default(TFieldSum);
  Sum.Uniform := True;
  for Index := 0 to ARecord.ChildCount - 1 do
  begin
    Child := ARecord[Index];
    case Child.Kind of
      TSyntaxKind.Field:
        AddField(Sum, Child, AParams, AArgs, ASize);
      TSyntaxKind.Visibility:
        Sum.Bytes := Sum.Bytes + FieldsOf(Child, AParams, AArgs, ASize);
      TSyntaxKind.VariantPart:
        AddVariant(Sum, Child, AParams, AArgs, ASize);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    if Sum.Bytes > TypeSizeCap then
    begin
      Sum.Bytes := TypeSizeCap;
    end;
  end;
  // Mehrere Felder: Ausrichtung kann Lücken einfügen, außer alle sind gleich groß (1, 2, 4 oder 8 Byte).
  if (Sum.Fields > 1) and not WithoutGaps(Sum) then
  begin
    ASize.Exact := False;
  end;
  Result := Sum.Bytes;
end;

function TTypeSizes.RecordIndexSize(const AFileName, AName: string): TTypeSize;
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Part: TTypeSize;
begin
  Result := Default(TTypeSize);
  if not FIndex.FindFile(AFileName, UnitIndex) then
  begin
    Exit;
  end;
  for Symbol in UnitIndex.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, AName) then
    begin
      Part := OfName(Symbol.TypeName, nil, nil);
      Result.Bytes := Result.Bytes + Part.Bytes;
      Result.Nested := Result.Nested or Part.Nested or (Part.Bytes >= TypeSizeLimit);
    end;
  end;
end;

function TTypeSizes.SymbolSize(const ALocation: TSymbolLocation; const AName: string): TTypeSize;
begin
  Result := Default(TTypeSize);
  case ALocation.Symbol.Kind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
      Result.Bytes := 4;
    TIndexSymbolKind.EnumType:
      Result.Bytes := 1;
    TIndexSymbolKind.TypeAlias:
      Result := OfName(ALocation.Symbol.TypeName, nil, nil);
    TIndexSymbolKind.RecordType:
      Result := RecordIndexSize(ALocation.FileName, AName);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Result.Exact := False;
end;

function TTypeSizes.IndexSize(const AName: string): TTypeSize;
var
  Location: TSymbolLocation;
begin
  Result := Default(TTypeSize);
  if (FIndex = nil) or (FDepth > 32) then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    for Location in FIndex.FindSymbols(AName) do
    begin
      if Location.Symbol.Container = '' then
      begin
        Exit(SymbolSize(Location, AName));
      end;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TTypeSizes.GenericDecl(const AName: string; out AParams: TArray<string>): TSyntaxNode;
var
  Params: TSyntaxNode;
  Index: Integer;
begin
  AParams := nil;
  if not FTypes.TryGetValue(LowerCase(AName), Result) then
  begin
    Exit(nil);
  end;
  Params := Result.FindChild(TSyntaxKind.GenericParams);
  if Params = nil then
  begin
    Exit(nil);
  end;
  for Index := 0 to Params.ChildCount - 1 do
  begin
    AParams := AParams + [Params[Index].Name];
  end;
end;

function TTypeSizes.OfName(const AName: string; const AParams, AArgs: TArray<string>): TTypeSize;
var
  Index: Integer;
  Decl: TSyntaxNode;
begin
  Result := Default(TTypeSize);
  Index := IndexText(AName, AParams);
  if (Index >= 0) and (Index < Length(AArgs)) then
  begin
    Exit(OfName(AArgs[Index], nil, nil));
  end;
  Index := IndexText(AName, SizeNames);
  if Index >= 0 then
  begin
    Result.Bytes := SizeBytes[Index];
    Result.Exact := Index < FirstInexactSize;
    Exit;
  end;
  if (FDepth > 32) then
  begin
    Exit;
  end;
  if FTypes.TryGetValue(LowerCase(AName), Decl) and (Decl.FindChild(TSyntaxKind.GenericParams) = nil) and
    (TypeNodeOf(Decl) <> nil) then
  begin
    Inc(FDepth);
    try
      Result := OfNode(TypeNodeOf(Decl), nil, nil);
    finally
      Dec(FDepth);
    end;
    // Ein benannter Typ über der Grenze wird an seiner Deklaration gemeldet.
    if Result.Bytes >= TypeSizeLimit then
    begin
      Result.Nested := True;
    end;
    Exit;
  end;
  Result := IndexSize(AName);
end;

function TTypeSizes.GenericSize(ANode, AArgs: TSyntaxNode): TTypeSize;
var
  Index: Integer;
  Decl: TSyntaxNode;
  Params, Values: TArray<string>;
begin
  Result := Default(TTypeSize);
  Decl := GenericDecl(ANode.Name, Params);
  if Decl = nil then
  begin
    // TArray<T>, TList<T> …: Zeiger.
    Result.Bytes := 4;
    Exit;
  end;
  Values := nil;
  for Index := 0 to AArgs.ChildCount - 1 do
  begin
    Values := Values + [Trim(Copy(FText, AArgs[Index].StartOffset + 1,
      AArgs[Index].EndOffset - AArgs[Index].StartOffset))];
  end;
  Result := OfNode(TypeNodeOf(Decl), Params, Values);
end;

/// <summary>Längenangabe N von string[N]: letztes Kind von ANode, das keine Typargumente sind; nil ohne.</summary>
function ShortLength(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind <> TSyntaxKind.GenericArgs then
    begin
      Result := ANode[Index];
    end;
  end;
end;

function TTypeSizes.ReferenceSize(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
var
  Args, Size: TSyntaxNode;
  Value: Int64;
begin
  Result := Default(TTypeSize);
  Args := ANode.FindChild(TSyntaxKind.GenericArgs);
  Size := ShortLength(ANode);
  if SameText(ANode.Name, 'string') and (Size <> nil) then
  begin
    // string[N]: ShortString mit N Zeichen und Längenbyte.
    if Evaluate(Size, Value) then
    begin
      Result.Bytes := Value + 1;
      Result.Exact := True;
    end;
  end
  else if Args <> nil then
  begin
    Result := GenericSize(ANode, Args);
  end
  else
  begin
    Result := OfName(ANode.Name, AParams, AArgs);
  end;
end;

function TTypeSizes.ArraySize(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
var
  Index, Last: Integer;
  Element: TTypeSize;
  CountExact: Boolean;
begin
  Result := Default(TTypeSize);
  if ANode.ChildCount < 2 then
  begin
    // Dynamisches Array: ein Zeiger.
    Result.Bytes := 4;
    Exit;
  end;
  Last := ANode.ChildCount - 1;
  Element := OfNode(ANode[Last], AParams, AArgs);
  Result.Bytes := Element.Bytes;
  Result.Exact := Element.Exact;
  Result.Nested := Element.Nested or (Element.Bytes >= TypeSizeLimit);
  for Index := 0 to Last - 1 do
  begin
    Result.Bytes := Multiply(Result.Bytes, Count(ANode[Index], CountExact));
    Result.Exact := Result.Exact and CountExact;
  end;
end;

function TTypeSizes.OfNode(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
begin
  Result := Default(TTypeSize);
  if (ANode = nil) or (FDepth > 32) then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    case ANode.Kind of
      TSyntaxKind.TypeReference:
        Result := ReferenceSize(ANode, AParams, AArgs);
      TSyntaxKind.ArrayType:
        Result := ArraySize(ANode, AParams, AArgs);
      TSyntaxKind.RecordType, TSyntaxKind.ObjectType:
        begin
          Result.Exact := ANode.Kind = TSyntaxKind.RecordType;
          Result.Bytes := FieldsOf(ANode, AParams, AArgs, Result);
        end;
      TSyntaxKind.ClassType, TSyntaxKind.InterfaceType, TSyntaxKind.ClassOfType, TSyntaxKind.PointerType,
      TSyntaxKind.ProcedureType:
        Result.Bytes := 4;
      TSyntaxKind.EnumType, TSyntaxKind.SetType, TSyntaxKind.SubrangeType:
        Result.Bytes := 1;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  finally
    Dec(FDepth);
  end;
end;

procedure TTypeTooLargeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Sizes: TTypeSizes;
  Tokens: TArray<TPascalToken>;

  function SizeText(const ASize: TTypeSize): string;
  var
    Gigabytes: Int64;
    Settings: TFormatSettings;
  begin
    Gigabytes := ASize.Bytes shr 30;
    if ASize.Bytes >= TypeSizeCap then
    begin
      Result := cTexts[TDeclarationsTypeSizesText.OverPB].Text;
    end
    else if ASize.Bytes and ((Int64(1) shl 30) - 1) = 0 then
    begin
      Result := Format('%d GB', [Gigabytes]);
    end
    else
    begin
      Settings := TFormatSettings.Invariant;
      Settings.DecimalSeparator := ',';
      Result := FormatFloat('0.#', ASize.Bytes / (Int64(1) shl 30), Settings) + ' GB';
    end;
    if not ASize.Exact and (ASize.Bytes < TypeSizeCap) then
    begin
      Result := cTexts[TDeclarationsTypeSizesText.AtLeast].Fmt([Result]);
    end;
  end;

  // Name der Deklaration, zu der der Typknoten gehört; '' bei verschachtelten Typen.
  function OwnerName(ANode: TSyntaxNode): string;
  begin
    Result := '';
    if (ANode.Parent <> nil) and (ANode.Parent.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.Field,
      TSyntaxKind.VarDecl]) and (TTypeSizes.TypeNodeOf(ANode.Parent) = ANode) then
    begin
      Result := ANode.Parent.Name.Replace(',', ', ');
    end;
  end;

  function NameRange(ANode: TSyntaxNode): TTextRange;
  var
    Index: Integer;
  begin
    // Bei Typdeklarationen der Name, sonst der Typ selbst.
    if ANode.Parent.Kind = TSyntaxKind.TypeDecl then
    begin
      for Index := TokenAtOffset(Tokens, ANode.Parent.StartOffset) to High(Tokens) do
      begin
        if SameText(Tokens[Index].Text, ANode.Parent.Name) then
        begin
          Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
        end;
      end;
    end;
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  procedure CheckNode(ANode: TSyntaxNode);
  var
    Size: TTypeSize;
    Name, Code: string;
    Params: TArray<string>;
  begin
    Code := 'E2100';
    if ANode.Kind = TSyntaxKind.TypeReference then
    begin
      // Instanz eines generischen Typs der Datei: TFeld<Int64>.
      if (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) or (Sizes.GenericDecl(ANode.Name, Params) = nil) then
      begin
        Exit;
      end;
      Code := 'E2543';
    end;
    Size := Sizes.OfNode(ANode, nil, nil);
    if (Size.Bytes < TypeSizeLimit) or Size.Nested then
    begin
      Exit;
    end;
    if Code = 'E2543' then
    begin
      Name := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
    end
    else
    begin
      Name := OwnerName(ANode);
      if Name = '' then
      begin
        Name := cTexts[TDeclarationsTypeSizesText.TheType].Text;
      end;
    end;
    AReport.Add(NameRange(ANode), cTexts[TDeclarationsTypeSizesText.TooLarge].Fmt([Name, SizeText(Size),
      Code]), TRuleConfidence.High);
  end;

var
  Stack: TArray<TSyntaxNode>;
  Count, Index: Integer;
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Sizes := TTypeSizes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    // Ohne Rekursion durch den Baum (#1094); Rümpfe generischer Typen erst bei ihrer Instanz.
    SetLength(Stack, 64);
    Stack[0] := AContext.Tree.Root;
    Count := 1;
    while Count > 0 do
    begin
      Dec(Count);
      Node := Stack[Count];
      if (Node.Kind = TSyntaxKind.TypeDecl) and (Node.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Continue;
      end;
      if Node.Kind in [TSyntaxKind.ArrayType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType,
        TSyntaxKind.TypeReference] then
      begin
        CheckNode(Node);
      end;
      if Count + Node.ChildCount > Length(Stack) then
      begin
        SetLength(Stack, 2 * (Count + Node.ChildCount));
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Stack[Count] := Node[Index];
        Inc(Count);
      end;
    end;
  finally
    Sizes.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.TypeSizes', cTexts);

end.
