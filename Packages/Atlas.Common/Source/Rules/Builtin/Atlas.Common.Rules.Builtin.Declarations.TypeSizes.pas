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
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
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
  cTypeSizeLimit = Int64(1) shl 31;
  // Obergrenze der Rechnung, damit Produkte nicht überlaufen.
  cTypeSizeCap = Int64(1) shl 50;
  cTypeKindsForSize = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.PointerType,
    TSyntaxKind.RecordType, TSyntaxKind.ObjectType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType,
    TSyntaxKind.ClassOfType, TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.ProcedureType,
    TSyntaxKind.SubrangeType, TSyntaxKind.FileType, TSyntaxKind.HelperType];
  // Eingebaute Typen: Größe als untere Grenze; Exakt = auf allen Windows-Plattformen gleich.
  cSizeNames: array[0..47] of string = ('Byte', 'ShortInt', 'Boolean', 'ByteBool', 'AnsiChar', 'Int8', 'UInt8',
    'Word', 'SmallInt', 'Char', 'WideChar', 'WordBool', 'Int16', 'UInt16', 'Integer', 'Cardinal', 'LongInt',
    'LongWord', 'Single', 'LongBool', 'FixedInt', 'FixedUInt', 'Int32', 'UInt32', 'Int64', 'UInt64', 'Double',
    'Currency', 'Comp', 'TDateTime', 'TDate', 'TTime', 'Real', 'ShortString', 'TGUID', 'Extended', 'Pointer',
    'PChar', 'PAnsiChar', 'PWideChar', 'string', 'UnicodeString', 'AnsiString', 'WideString', 'NativeInt',
    'NativeUInt', 'Variant', 'OleVariant');
  cSizeBytes: array[0..47] of Integer = (1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 256, 16, 8, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 16, 16);
  // Ab diesem Eintrag hängt die Größe von der Plattform ab.
  cFirstInexactSize = 35;
  // Elementzahl eingebauter Indextypen.
  cCountNames: array[0..11] of string = ('Byte', 'AnsiChar', 'ShortInt', 'Boolean', 'Word', 'Char', 'WideChar',
    'SmallInt', 'Integer', 'Cardinal', 'LongInt', 'LongWord');
  cCountValues: array[0..11] of Int64 = (256, 256, 256, 2, 65536, 65536, 65536, 65536, 4294967296, 4294967296,
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
  mIndex, mValue: Integer;
begin
  // Werte nur ohne explizite Zuweisung (a = 5) sicher.
  for mIndex := 0 to AEnum.ChildCount - 1 do
  begin
    if AEnum[mIndex].Kind <> TSyntaxKind.Identifier then
    begin
      Exit;
    end;
  end;
  for mValue := 0 to AEnum.ChildCount - 1 do
  begin
    if not FEnumValues.ContainsKey(LowerCase(AEnum[mValue].Name)) then
    begin
      FEnumValues.Add(LowerCase(AEnum[mValue].Name), mValue);
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
  mStack: TArray<TSyntaxNode>;
  mCount, mIndex: Integer;
  mNode: TSyntaxNode;
begin
  // Ohne Rekursion (#1094).
  SetLength(mStack, 64);
  mStack[0] := ARoot;
  mCount := 1;
  while mCount > 0 do
  begin
    Dec(mCount);
    mNode := mStack[mCount];
    AddDeclaration(mNode);
    if mCount + mNode.ChildCount > Length(mStack) then
    begin
      SetLength(mStack, 2 * (mCount + mNode.ChildCount));
    end;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      mStack[mCount] := mNode[mIndex];
      Inc(mCount);
    end;
  end;
end;

class function TTypeSizes.TypeNodeOf(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind in cTypeKindsForSize then
    begin
      Exit(ANode[mIndex]);
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
  if A > cTypeSizeCap div B then
  begin
    Exit(cTypeSizeCap);
  end;
  Result := A * B;
end;

function TTypeSizes.Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
var
  mFirst, mLast: Integer;
  mLookup: TOrdinalNameLookup;
begin
  AValue := 0;
  if FDepth > 32 then
  begin
    Exit(False);
  end;
  mFirst := TokenFrom(FTokens, ANode.StartOffset);
  mLast := TokenFrom(FTokens, ANode.EndOffset) - 1;
  if mLast < mFirst then
  begin
    Exit(False);
  end;
  mLookup :=
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
  Result := TOrdinalConstants.Evaluate(FTokens, mFirst, mLast, mLookup, AValue);
end;

function TTypeSizes.CountOfName(const AName: string; out AExact: Boolean): Int64;
var
  mIndex: Integer;
  mDecl, mBody: TSyntaxNode;
begin
  AExact := True;
  mIndex := IndexText(AName, cCountNames);
  if mIndex >= 0 then
  begin
    Exit(cCountValues[mIndex]);
  end;
  AExact := False;
  Result := 0;
  if (FDepth > 32) or not FTypes.TryGetValue(LowerCase(AName), mDecl) then
  begin
    Exit;
  end;
  mBody := TypeNodeOf(mDecl);
  if mBody = nil then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    Result := Count(mBody, AExact);
  finally
    Dec(FDepth);
  end;
end;

function TTypeSizes.Count(AIndexType: TSyntaxNode; out AExact: Boolean): Int64;
var
  mLow, mHigh: Int64;
  mIndex: Integer;
begin
  AExact := False;
  Result := 0;
  case AIndexType.Kind of
    TSyntaxKind.SubrangeType:
      if (AIndexType.ChildCount = 2) and Evaluate(AIndexType[0], mLow) and Evaluate(AIndexType[1], mHigh) then
      begin
        AExact := True;
        if mHigh >= mLow then
        begin
          Result := mHigh - mLow + 1;
        end;
      end;
    TSyntaxKind.TypeReference:
      Result := CountOfName(AIndexType.Name, AExact);
    TSyntaxKind.EnumType:
      begin
        // Mit explizit zugewiesenen Werten (a = 5) mindestens so viele Elemente wie Namen.
        AExact := True;
        for mIndex := 0 to AIndexType.ChildCount - 1 do
        begin
          if AIndexType[mIndex].Kind = TSyntaxKind.Identifier then
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
  mNames: Integer;
  mPart: TTypeSize;
begin
  if TypeNodeOf(AField) = nil then
  begin
    Exit;
  end;
  mPart := OfNode(TypeNodeOf(AField), AParams, AArgs);
  mNames := Length(AField.Name.Split([',']));
  Inc(ASum.Fields, mNames);
  if (ASum.FieldSize <> 0) and (ASum.FieldSize <> mPart.Bytes) then
  begin
    ASum.Uniform := False;
  end;
  ASum.FieldSize := mPart.Bytes;
  ASum.Bytes := ASum.Bytes + Multiply(mPart.Bytes, mNames);
  ASize.Exact := ASize.Exact and mPart.Exact;
  ASize.Nested := ASize.Nested or mPart.Nested or (mPart.Bytes >= cTypeSizeLimit);
end;

procedure TTypeSizes.AddVariant(var ASum: TFieldSum; AVariant: TSyntaxNode; const AParams, AArgs: TArray<string>;
  var ASize: TTypeSize);
var
  mInner: Integer;
  mItem: TSyntaxNode;
  mLargest, mBranch: Int64;
begin
  // Ein Selektorfeld (case Art: TArt of) belegt Platz, ein bloßer Selektortyp nicht.
  mLargest := 0;
  for mInner := 0 to AVariant.ChildCount - 1 do
  begin
    mItem := AVariant[mInner];
    if mItem.Kind = TSyntaxKind.Field then
    begin
      ASum.Bytes := ASum.Bytes + OfNode(TypeNodeOf(mItem), AParams, AArgs).Bytes;
      Inc(ASum.Fields);
    end
    else if mItem.Kind = TSyntaxKind.CaseItem then
    begin
      mBranch := FieldsOf(mItem, AParams, AArgs, ASize);
      if mBranch > mLargest then
      begin
        mLargest := mBranch;
      end;
    end;
  end;
  ASum.Bytes := ASum.Bytes + mLargest;
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
  mIndex: Integer;
  mChild: TSyntaxNode;
  mSum: TFieldSum;
begin
  // Summe der Felder; varianter Teil: Selektor plus größter Zweig.
  mSum := Default(TFieldSum);
  mSum.Uniform := True;
  for mIndex := 0 to ARecord.ChildCount - 1 do
  begin
    mChild := ARecord[mIndex];
    case mChild.Kind of
      TSyntaxKind.Field:
        AddField(mSum, mChild, AParams, AArgs, ASize);
      TSyntaxKind.Visibility:
        mSum.Bytes := mSum.Bytes + FieldsOf(mChild, AParams, AArgs, ASize);
      TSyntaxKind.VariantPart:
        AddVariant(mSum, mChild, AParams, AArgs, ASize);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    if mSum.Bytes > cTypeSizeCap then
    begin
      mSum.Bytes := cTypeSizeCap;
    end;
  end;
  // Mehrere Felder: Ausrichtung kann Lücken einfügen, außer alle sind gleich groß (1, 2, 4 oder 8 Byte).
  if (mSum.Fields > 1) and not WithoutGaps(mSum) then
  begin
    ASize.Exact := False;
  end;
  Result := mSum.Bytes;
end;

function TTypeSizes.RecordIndexSize(const AFileName, AName: string): TTypeSize;
var
  mUnitIndex: TUnitIndex;
  mSymbol: TIndexSymbol;
  mPart: TTypeSize;
begin
  Result := Default(TTypeSize);
  if not FIndex.FindFile(AFileName, mUnitIndex) then
  begin
    Exit;
  end;
  for mSymbol in mUnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, AName) then
    begin
      mPart := OfName(mSymbol.TypeName, nil, nil);
      Result.Bytes := Result.Bytes + mPart.Bytes;
      Result.Nested := Result.Nested or mPart.Nested or (mPart.Bytes >= cTypeSizeLimit);
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
  mLocation: TSymbolLocation;
begin
  Result := Default(TTypeSize);
  if (FIndex = nil) or (FDepth > 32) then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    for mLocation in FIndex.FindSymbols(AName) do
    begin
      if mLocation.Symbol.Container = '' then
      begin
        Exit(SymbolSize(mLocation, AName));
      end;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TTypeSizes.GenericDecl(const AName: string; out AParams: TArray<string>): TSyntaxNode;
var
  mParams: TSyntaxNode;
  mIndex: Integer;
begin
  AParams := nil;
  if not FTypes.TryGetValue(LowerCase(AName), Result) then
  begin
    Exit(nil);
  end;
  mParams := Result.FindChild(TSyntaxKind.GenericParams);
  if mParams = nil then
  begin
    Exit(nil);
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    AParams := AParams + [mParams[mIndex].Name];
  end;
end;

function TTypeSizes.OfName(const AName: string; const AParams, AArgs: TArray<string>): TTypeSize;
var
  mIndex: Integer;
  mDecl: TSyntaxNode;
begin
  Result := Default(TTypeSize);
  mIndex := IndexText(AName, AParams);
  if (mIndex >= 0) and (mIndex < Length(AArgs)) then
  begin
    Exit(OfName(AArgs[mIndex], nil, nil));
  end;
  mIndex := IndexText(AName, cSizeNames);
  if mIndex >= 0 then
  begin
    Result.Bytes := cSizeBytes[mIndex];
    Result.Exact := mIndex < cFirstInexactSize;
    Exit;
  end;
  if FDepth > 32 then
  begin
    Exit;
  end;
  if FTypes.TryGetValue(LowerCase(AName), mDecl) and (mDecl.FindChild(TSyntaxKind.GenericParams) = nil) and
    (TypeNodeOf(mDecl) <> nil) then
  begin
    Inc(FDepth);
    try
      Result := OfNode(TypeNodeOf(mDecl), nil, nil);
    finally
      Dec(FDepth);
    end;
    // Ein benannter Typ über der Grenze wird an seiner Deklaration gemeldet.
    if Result.Bytes >= cTypeSizeLimit then
    begin
      Result.Nested := True;
    end;
    Exit;
  end;
  Result := IndexSize(AName);
end;

function TTypeSizes.GenericSize(ANode, AArgs: TSyntaxNode): TTypeSize;
var
  mIndex: Integer;
  mDecl: TSyntaxNode;
  mParams, mValues: TArray<string>;
begin
  Result := Default(TTypeSize);
  mDecl := GenericDecl(ANode.Name, mParams);
  if mDecl = nil then
  begin
    // TArray<T>, TList<T> …: Zeiger.
    Result.Bytes := 4;
    Exit;
  end;
  mValues := nil;
  for mIndex := 0 to AArgs.ChildCount - 1 do
  begin
    mValues := mValues + [Trim(Copy(FText, AArgs[mIndex].StartOffset + 1,
      AArgs[mIndex].EndOffset - AArgs[mIndex].StartOffset))];
  end;
  Result := OfNode(TypeNodeOf(mDecl), mParams, mValues);
end;

/// <summary>Längenangabe N von string[N]: letztes Kind von ANode, das keine Typargumente sind; nil ohne.</summary>
function ShortLength(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind <> TSyntaxKind.GenericArgs then
    begin
      Result := ANode[mIndex];
    end;
  end;
end;

function TTypeSizes.ReferenceSize(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
var
  mArgs, mSize: TSyntaxNode;
  mValue: Int64;
begin
  Result := Default(TTypeSize);
  mArgs := ANode.FindChild(TSyntaxKind.GenericArgs);
  mSize := ShortLength(ANode);
  if SameText(ANode.Name, 'string') and (mSize <> nil) then
  begin
    // string[N]: ShortString mit N Zeichen und Längenbyte.
    if Evaluate(mSize, mValue) then
    begin
      Result.Bytes := mValue + 1;
      Result.Exact := True;
    end;
  end
  else if mArgs <> nil then
  begin
    Result := GenericSize(ANode, mArgs);
  end
  else
  begin
    Result := OfName(ANode.Name, AParams, AArgs);
  end;
end;

function TTypeSizes.ArraySize(ANode: TSyntaxNode; const AParams, AArgs: TArray<string>): TTypeSize;
var
  mIndex, mLast: Integer;
  mElement: TTypeSize;
  mCountExact: Boolean;
begin
  Result := Default(TTypeSize);
  if ANode.ChildCount < 2 then
  begin
    // Dynamisches Array: ein Zeiger.
    Result.Bytes := 4;
    Exit;
  end;
  mLast := ANode.ChildCount - 1;
  mElement := OfNode(ANode[mLast], AParams, AArgs);
  Result.Bytes := mElement.Bytes;
  Result.Exact := mElement.Exact;
  Result.Nested := mElement.Nested or (mElement.Bytes >= cTypeSizeLimit);
  for mIndex := 0 to mLast - 1 do
  begin
    Result.Bytes := Multiply(Result.Bytes, Count(ANode[mIndex], mCountExact));
    Result.Exact := Result.Exact and mCountExact;
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
  mSizes: TTypeSizes;
  mTokens: TArray<TPascalToken>;

  function SizeText(const ASize: TTypeSize): string;
  var
    mGigabytes: Int64;
    mSettings: TFormatSettings;
  begin
    mGigabytes := ASize.Bytes shr 30;
    if ASize.Bytes >= cTypeSizeCap then
    begin
      Result := cTexts[TDeclarationsTypeSizesText.OverPB].Text;
    end
    else if ASize.Bytes and ((Int64(1) shl 30) - 1) = 0 then
    begin
      Result := Format('%d GB', [mGigabytes]);
    end
    else
    begin
      mSettings := TFormatSettings.Invariant;
      mSettings.DecimalSeparator := ',';
      Result := FormatFloat('0.#', ASize.Bytes / (Int64(1) shl 30), mSettings) + ' GB';
    end;
    if not ASize.Exact and (ASize.Bytes < cTypeSizeCap) then
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
    mIndex: Integer;
  begin
    // Bei Typdeklarationen der Name, sonst der Typ selbst.
    if ANode.Parent.Kind = TSyntaxKind.TypeDecl then
    begin
      for mIndex := TokenFrom(mTokens, ANode.Parent.StartOffset) to High(mTokens) do
      begin
        if SameText(mTokens[mIndex].Text, ANode.Parent.Name) then
        begin
          Exit(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos));
        end;
      end;
    end;
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  procedure CheckNode(ANode: TSyntaxNode);
  var
    mSize: TTypeSize;
    mName, mCode: string;
    mParams: TArray<string>;
  begin
    mCode := 'E2100';
    if ANode.Kind = TSyntaxKind.TypeReference then
    begin
      // Instanz eines generischen Typs der Datei: TFeld<Int64>.
      if (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) or (mSizes.GenericDecl(ANode.Name, mParams) = nil) then
      begin
        Exit;
      end;
      mCode := 'E2543';
    end;
    mSize := mSizes.OfNode(ANode, nil, nil);
    if (mSize.Bytes < cTypeSizeLimit) or mSize.Nested then
    begin
      Exit;
    end;
    if mCode = 'E2543' then
    begin
      mName := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
    end
    else
    begin
      mName := OwnerName(ANode);
      if mName = '' then
      begin
        mName := cTexts[TDeclarationsTypeSizesText.TheType].Text;
      end;
    end;
    AReport.Add(NameRange(ANode), cTexts[TDeclarationsTypeSizesText.TooLarge].Fmt([mName, SizeText(mSize),
      mCode]), TRuleConfidence.High);
  end;

var
  mStack: TArray<TSyntaxNode>;
  mCount, mIndex: Integer;
  mNode: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mSizes := TTypeSizes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    // Ohne Rekursion durch den Baum (#1094); Rümpfe generischer Typen erst bei ihrer Instanz.
    SetLength(mStack, 64);
    mStack[0] := AContext.Tree.Root;
    mCount := 1;
    while mCount > 0 do
    begin
      Dec(mCount);
      mNode := mStack[mCount];
      if (mNode.Kind = TSyntaxKind.TypeDecl) and (mNode.FindChild(TSyntaxKind.GenericParams) <> nil) then
      begin
        Continue;
      end;
      if mNode.Kind in [TSyntaxKind.ArrayType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType,
        TSyntaxKind.TypeReference] then
      begin
        CheckNode(mNode);
      end;
      if mCount + mNode.ChildCount > Length(mStack) then
      begin
        SetLength(mStack, 2 * (mCount + mNode.ChildCount));
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mStack[mCount] := mNode[mIndex];
        Inc(mCount);
      end;
    end;
  finally
    mSizes.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.TypeSizes', cTexts);

end.
