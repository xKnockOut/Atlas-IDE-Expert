unit Atlas.Common.Lsp.SemanticTokens;

// Semantische Hervorhebung (textDocument/semanticTokens/full und …/range):
// Jeder Bezeichner wird über die Namensauflösung eingeordnet: Unit, Klasse, Record,
// Interface, Aufzählung, Typ, Parameter, Variable, Feld, Property, Ereignis,
// Aufzählungswert, Funktion, Methode. Modifier: declaration (Name einer Deklaration),
// readonly (Konstanten), defaultLibrary (RTL, VCL, FMX, Winapi), reassigned (#712:
// lokale Variablen und Wertparameter, die neu zugewiesen werden, siehe
// Atlas.Common.Semantics.Reassigned).
// "field" ist ein eigener Typ; die VS-Code-Erweiterung meldet ihn mit Obertyp "property".

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.Reassigned;

type
  /// <summary>Reihenfolge = Index in der Legende.</summary>
  TSemanticTokenType = (Namespace, Class_, Enum, Interface_, Struct, Type_, Parameter, Variable, Field, Property_,
    Event, EnumMember, Function_, Method);

  TSemanticTokenModifier = (Declaration, Readonly, DefaultLibrary, Reassigned);
  TSemanticTokenModifiers = set of TSemanticTokenModifier;

  TSemanticToken = record
    Position: TTextPosition;
    Length: Integer;
    TokenType: TSemanticTokenType;
    Modifiers: TSemanticTokenModifiers;
  end;

  TLspSemanticTokens = class
  public const
    cFullMethod = 'textDocument/semanticTokens/full';
    cRangeMethod = 'textDocument/semanticTokens/range';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
      AWithRange: Boolean): TJSONValue;
    function HandleFull(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleRange(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Wie Collect mit FIndex und Abbruch.</summary>
    function CollectFor(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange; AWithRange: Boolean;
      const ACancellation: IJsonRpcCancellationToken): TArray<TSemanticToken>;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>semanticTokensProvider mit Legende, full und range.</summary>
    class function Capability: TJSONObject; static;
    class function TypeName(AType: TSemanticTokenType): string; static;
    /// <summary>Eingeordnete Bezeichner in ARange (alle, wenn AWithRange False), nach Position.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const ARange: TTextRange; AWithRange: Boolean): TArray<TSemanticToken>; static;
    /// <summary>Modifier reassigned an jedem Token, das eine Stelle der Namen ASymbols ist (#712).</summary>
    class procedure MarkReassigned(var ATokens: TArray<TSemanticToken>;
      const ASymbols: TArray<TReassignedSymbol>); static;
    /// <summary>Relative Kodierung des LSP (je Token fünf Zahlen).</summary>
    class function Encode(const ATokens: TArray<TSemanticToken>): TArray<Integer>; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.LibraryUnits,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.Reassigned,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSemanticTokensText = (FieldTextDocumentUriMissing, FieldRangeMissing);

const
  cTexts: array[TSemanticTokensText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt'; En: 'Field "textDocument.uri" missing'),
    (De: 'Feld "range" fehlt'; En: 'Field "range" missing'));

const
  cTypeNames: array[TSemanticTokenType] of string = ('namespace', 'class', 'enum', 'interface', 'struct', 'type',
    'parameter', 'variable', 'field', 'property', 'event', 'enumMember', 'function', 'method');
  cModifierNames: array[TSemanticTokenModifier] of string = ('declaration', 'readonly', 'defaultLibrary',
    'reassigned');

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

function InRange(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) < 0);
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

/// <summary>Art eines Typs in AType; False für Symbole, die keine Typen sind.</summary>
function TypeKindOf(AKind: TIndexSymbolKind; out AType: TSemanticTokenType): Boolean;
begin
  Result := True;
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType:
      AType := TSemanticTokenType.Class_;
    TIndexSymbolKind.RecordType:
      AType := TSemanticTokenType.Struct;
    TIndexSymbolKind.InterfaceType:
      AType := TSemanticTokenType.Interface_;
    TIndexSymbolKind.EnumType:
      AType := TSemanticTokenType.Enum;
    TIndexSymbolKind.TypeAlias:
      AType := TSemanticTokenType.Type_;
  else
    AType := TSemanticTokenType.Variable;
    Result := False;
  end;
end;

/// <summary>Art eines Symbols, das kein Typ ist.</summary>
function MemberType(const ASymbol: TResolvedSymbol): TSemanticTokenType;
begin
  case ASymbol.SymbolKind of
    TIndexSymbolKind.EnumMember:
      Result := TSemanticTokenType.EnumMember;
    TIndexSymbolKind.Field:
      Result := TSemanticTokenType.Field;
    TIndexSymbolKind.Property_:
      // Ereignisse: Properties mit Methodentyp wie TNotifyEvent.
      if EndsText('Event', ASymbol.TypeName) or EndsText('EventHandler', ASymbol.TypeName) then
      begin
        Result := TSemanticTokenType.Event;
      end
      else
      begin
        Result := TSemanticTokenType.Property_;
      end;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_:
      Result := TSemanticTokenType.Method;
    TIndexSymbolKind.Routine:
      Result := TSemanticTokenType.Function_;
  else
    // Konstanten, Variablen und Parameter.
    if ASymbol.IsParameter and (ASymbol.SymbolKind <> TIndexSymbolKind.Constant) then
    begin
      Result := TSemanticTokenType.Parameter;
    end
    else
    begin
      Result := TSemanticTokenType.Variable;
    end;
  end;
end;

function Classify(const ASymbol: TResolvedSymbol; out AType: TSemanticTokenType;
  out AModifiers: TSemanticTokenModifiers): Boolean;
begin
  AModifiers := [];
  AType := TSemanticTokenType.Variable;
  if not (ASymbol.Kind in [TResolvedKind.UnitName, TResolvedKind.Symbol, TResolvedKind.Local]) then
  begin
    Exit(False);
  end;
  Result := True;
  if (ASymbol.Kind <> TResolvedKind.Local) and TLibraryUnits.IsLibraryUnit(ASymbol.UnitName) then
  begin
    Include(AModifiers, TSemanticTokenModifier.DefaultLibrary);
  end;
  if ASymbol.Kind = TResolvedKind.UnitName then
  begin
    AType := TSemanticTokenType.Namespace;
    Exit;
  end;
  if not TypeKindOf(ASymbol.SymbolKind, AType) then
  begin
    AType := MemberType(ASymbol);
  end;
  if ASymbol.SymbolKind = TIndexSymbolKind.Constant then
  begin
    Include(AModifiers, TSemanticTokenModifier.Readonly);
  end;
end;

function PositionKey(const APosition: TTextPosition): string;
begin
  Result := IntToStr(APosition.Line) + ':' + IntToStr(APosition.Character);
end;

type
  /// <summary>Ein Durchlauf über die Bezeichner eines Baums.</summary>
  TSemanticCollect = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    FTokens: TArray<TPascalToken>;
    FDeclarations: TDictionary<string, TIndexSymbol>;
    FUnitNames: TDictionary<string, Boolean>;
    FList: TList<TSemanticToken>;
    procedure AddUnitNames(const AIndex: ISymbolIndex);
    function PreviousCode(AIndex: Integer): Integer;
    function AddDeclaration(var AItem: TSemanticToken; AIndex: Integer): Boolean;
    function ChainAt(AIndex: Integer; out APrevious: Integer): TArray<string>;
    procedure AddUnitPart(var AItem: TSemanticToken; const ANames: TArray<string>);
    procedure AddToken(AIndex: Integer);
  public
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string);
    destructor Destroy; override;
    function Run(const ARange: TTextRange; AWithRange: Boolean;
      const ACancellation: IJsonRpcCancellationToken): TArray<TSemanticToken>;
  end;

{ TSemanticCollect }

constructor TSemanticCollect.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string);
var
  mSymbol: TIndexSymbol;
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FTokens := ATree.Tokens;
  FList := TList<TSemanticToken>.Create;
  // Namen von Deklarationen (auch Methoden in Klassen, die Resolve nicht als Verwendung kennt).
  FDeclarations := TDictionary<string, TIndexSymbol>.Create;
  for mSymbol in TIndexExtractor.Extract(ATree, AFileName).Symbols do
  begin
    FDeclarations.AddOrSetValue(PositionKey(mSymbol.SelectionRange.StartPos), mSymbol);
  end;
  FUnitNames := TDictionary<string, Boolean>.Create;
  AddUnitNames(AIndex);
end;

destructor TSemanticCollect.Destroy;
begin
  FList.Free;
  FUnitNames.Free;
  FDeclarations.Free;
  inherited;
end;

procedure TSemanticCollect.AddUnitNames(const AIndex: ISymbolIndex);
var
  mUnit: TUnitIndex;
  mParts: TArray<string>;
  mCount: Integer;
begin
  // Unit-Namen und ihre Präfixe (System, System.SysUtils): Teile einer gepunkteten Unit.
  if AIndex = nil then
  begin
    Exit;
  end;
  for mUnit in AIndex.Units do
  begin
    mParts := mUnit.UnitName.Split(['.']);
    for mCount := 1 to Length(mParts) do
    begin
      FUnitNames.AddOrSetValue(UpperCase(string.Join('.', Copy(mParts, 0, mCount))), True);
    end;
  end;
end;

function TSemanticCollect.PreviousCode(AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (FTokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

function TSemanticCollect.AddDeclaration(var AItem: TSemanticToken; AIndex: Integer): Boolean;
var
  mSymbol: TIndexSymbol;
  mResolved: TResolvedSymbol;
begin
  Result := FDeclarations.TryGetValue(PositionKey(FTokens[AIndex].StartPos), mSymbol);
  if not Result then
  begin
    Exit;
  end;
  mResolved := Default(TResolvedSymbol);
  mResolved.Kind := TResolvedKind.Symbol;
  mResolved.Name := mSymbol.Name;
  mResolved.SymbolKind := mSymbol.Kind;
  mResolved.TypeName := mSymbol.TypeName;
  if Classify(mResolved, AItem.TokenType, AItem.Modifiers) then
  begin
    Include(AItem.Modifiers, TSemanticTokenModifier.Declaration);
    FList.Add(AItem);
  end;
end;

function TSemanticCollect.ChainAt(AIndex: Integer; out APrevious: Integer): TArray<string>;
var
  mFirst: Integer;
begin
  // Kette A.B.C bis zu diesem Bezeichner, wie Resolve sie bildet.
  Result := TArray<string>.Create(CleanName(FTokens[AIndex].Text));
  mFirst := AIndex;
  APrevious := PreviousCode(mFirst);
  while (APrevious >= 1) and FTokens[APrevious].IsSymbol('.') and (PreviousCode(APrevious) >= 0) and
    (FTokens[PreviousCode(APrevious)].Kind = TPascalTokenKind.Identifier) do
  begin
    mFirst := PreviousCode(APrevious);
    Result := TArray<string>.Create(CleanName(FTokens[mFirst].Text)) + Result;
    APrevious := PreviousCode(mFirst);
  end;
end;

procedure TSemanticCollect.AddUnitPart(var AItem: TSemanticToken; const ANames: TArray<string>);
var
  mChain: string;
begin
  // Teil eines gepunkteten Unit-Namens (System in System.SysUtils); Variablen gehen vor.
  mChain := string.Join('.', ANames);
  if not FUnitNames.ContainsKey(UpperCase(mChain)) then
  begin
    Exit;
  end;
  AItem.TokenType := TSemanticTokenType.Namespace;
  AItem.Modifiers := [];
  if TLibraryUnits.IsLibraryUnit(mChain) then
  begin
    Include(AItem.Modifiers, TSemanticTokenModifier.DefaultLibrary);
  end;
  FList.Add(AItem);
end;

procedure TSemanticCollect.AddToken(AIndex: Integer);
var
  mItem: TSemanticToken;
  mNames: TArray<string>;
  mPrevious: Integer;
  mResolved: TResolvedSymbol;
begin
  mItem := Default(TSemanticToken);
  mItem.Position := FTokens[AIndex].StartPos;
  mItem.Length := Length(FTokens[AIndex].Text);
  if AddDeclaration(mItem, AIndex) then
  begin
    Exit;
  end;
  mNames := ChainAt(AIndex, mPrevious);
  // Foo(1).Bar: Ergebnis eines Ausdrucks, nicht auflösbar.
  if (mPrevious >= 0) and FTokens[mPrevious].IsSymbol('.') then
  begin
    Exit;
  end;
  if (Length(mNames) = 1) and SameText(mNames[0], 'Self') then
  begin
    mItem.TokenType := TSemanticTokenType.Variable;
    mItem.Modifiers := [TSemanticTokenModifier.Readonly];
    FList.Add(mItem);
    Exit;
  end;
  mResolved := FResolver.ResolveChain(FTree, FFileName, mNames, FTokens[AIndex].Offset,
    (mPrevious >= 0) and FTokens[mPrevious].IsKeyword('inherited'));
  if Classify(mResolved, mItem.TokenType, mItem.Modifiers) then
  begin
    FList.Add(mItem);
  end
  else
  begin
    AddUnitPart(mItem, mNames);
  end;
end;

function TSemanticCollect.Run(const ARange: TTextRange; AWithRange: Boolean;
  const ACancellation: IJsonRpcCancellationToken): TArray<TSemanticToken>;
var
  mIndex: Integer;
begin
  FResolver.PinTree(FTree, FFileName);
  try
    for mIndex := 0 to High(FTokens) do
    begin
      // C in ^C ist ein Steuerzeichen, kein Name (#862).
      if (FTokens[mIndex].Kind <> TPascalTokenKind.Identifier) or FTree.IsControlCharPart(mIndex) or
        (AWithRange and not InRange(ARange, FTokens[mIndex].StartPos)) then
      begin
        Continue;
      end;
      if Assigned(ACancellation) and ((mIndex and 255) = 0) then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      AddToken(mIndex);
    end;
    Result := FList.ToArray;
  finally
    FResolver.UnpinTree;
  end;
end;

{ TLspSemanticTokens }

function TLspSemanticTokens.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspSemanticTokens.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspSemanticTokens.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspSemanticTokens.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspSemanticTokens.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cFullMethod, HandleFull);
  ADispatcher.RegisterConcurrentRequest(cRangeMethod, HandleRange);
end;

class function TLspSemanticTokens.TypeName(AType: TSemanticTokenType): string;
begin
  Result := cTypeNames[AType];
end;

class function TLspSemanticTokens.Capability: TJSONObject;
var
  mLegend: TJSONObject;
  mTypes, mModifiers: TJSONArray;
  mTokenType: TSemanticTokenType;
  mModifier: TSemanticTokenModifier;
begin
  mTypes := TJSONArray.Create;
  for mTokenType := Low(TSemanticTokenType) to High(TSemanticTokenType) do
  begin
    mTypes.Add(cTypeNames[mTokenType]);
  end;
  mModifiers := TJSONArray.Create;
  for mModifier := Low(TSemanticTokenModifier) to High(TSemanticTokenModifier) do
  begin
    mModifiers.Add(cModifierNames[mModifier]);
  end;
  mLegend := TJSONObject.Create;
  mLegend.AddPair('tokenTypes', mTypes);
  mLegend.AddPair('tokenModifiers', mModifiers);
  Result := TJSONObject.Create;
  Result.AddPair('legend', mLegend);
  Result.AddPair('full', TJSONBool.Create(True));
  Result.AddPair('range', TJSONBool.Create(True));
end;

class function TLspSemanticTokens.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const ARange: TTextRange; AWithRange: Boolean): TArray<TSemanticToken>;
var
  mCollect: TSemanticCollect;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mCollect := TSemanticCollect.Create(AResolver, AIndex, ATree, AFileName);
  try
    Result := mCollect.Run(ARange, AWithRange, nil);
  finally
    mCollect.Free;
  end;
end;

function TLspSemanticTokens.CollectFor(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange; AWithRange: Boolean; const ACancellation: IJsonRpcCancellationToken):
  TArray<TSemanticToken>;
var
  mCollect: TSemanticCollect;
begin
  mCollect := TSemanticCollect.Create(AResolver, FIndex, ATree, AFileName);
  try
    Result := mCollect.Run(ARange, AWithRange, ACancellation);
  finally
    mCollect.Free;
  end;
end;

class procedure TLspSemanticTokens.MarkReassigned(var ATokens: TArray<TSemanticToken>;
  const ASymbols: TArray<TReassignedSymbol>);
var
  mPlaces: TDictionary<string, Boolean>;
  mSymbol: TReassignedSymbol;
  mOccurrence: TReassignedOccurrence;
  mIndex: Integer;
begin
  if ASymbols = nil then
  begin
    Exit;
  end;
  mPlaces := TDictionary<string, Boolean>.Create;
  try
    for mSymbol in ASymbols do
    begin
      for mOccurrence in mSymbol.Occurrences do
      begin
        mPlaces.AddOrSetValue(IntToStr(mOccurrence.Range.StartPos.Line) + ':' +
          IntToStr(mOccurrence.Range.StartPos.Character), True);
      end;
    end;
    for mIndex := 0 to High(ATokens) do
    begin
      if mPlaces.ContainsKey(IntToStr(ATokens[mIndex].Position.Line) + ':' +
        IntToStr(ATokens[mIndex].Position.Character)) then
      begin
        Include(ATokens[mIndex].Modifiers, TSemanticTokenModifier.Reassigned);
      end;
    end;
  finally
    mPlaces.Free;
  end;
end;

class function TLspSemanticTokens.Encode(const ATokens: TArray<TSemanticToken>): TArray<Integer>;
var
  mIndex, mLine, mCharacter, mBits: Integer;
  mModifier: TSemanticTokenModifier;
begin
  SetLength(Result, Length(ATokens) * 5);
  mLine := 0;
  mCharacter := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    Result[mIndex * 5] := ATokens[mIndex].Position.Line - mLine;
    if ATokens[mIndex].Position.Line = mLine then
    begin
      Result[mIndex * 5 + 1] := ATokens[mIndex].Position.Character - mCharacter;
    end
    else
    begin
      Result[mIndex * 5 + 1] := ATokens[mIndex].Position.Character;
    end;
    Result[mIndex * 5 + 2] := ATokens[mIndex].Length;
    Result[mIndex * 5 + 3] := Ord(ATokens[mIndex].TokenType);
    mBits := 0;
    for mModifier in ATokens[mIndex].Modifiers do
    begin
      mBits := mBits or (1 shl Ord(mModifier));
    end;
    Result[mIndex * 5 + 4] := mBits;
    mLine := ATokens[mIndex].Position.Line;
    mCharacter := ATokens[mIndex].Position.Character;
  end;
end;

function TLspSemanticTokens.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
  AWithRange: Boolean): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mRangeValue: TJSONValue;
  mRange: TTextRange;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mValues: TArray<Integer>;
  mTokens: TArray<TSemanticToken>;
  mData: TJSONArray;
  mValue: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TSemanticTokensText.FieldTextDocumentUriMissing].Text);
  end;
  mRange := Default(TTextRange);
  if AWithRange then
  begin
    if not TJSONObject(AParams).TryGetValue<TJSONValue>('range', mRangeValue) then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TSemanticTokensText.FieldRangeMissing].Text);
    end;
    mRange := TLspPositions.ReadRange(mRangeValue);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    mTokens := CollectFor(mResolver, mTree, TDocumentUris.ToPath(mUri), mRange, AWithRange, ACancellation);
    ACancellation.ThrowIfCancellationRequested;
    // Andere Clients kennen die Ziele des Plugins nicht: Es gilt die Vorgabe (lokale Variablen, Wertparameter).
    MarkReassigned(mTokens, TReassigned.Filter(TLspReassigned.Analyze(mResolver, mTree, TDocumentUris.ToPath(mUri),
      mDocument.Text), TReassigned.cDefaultTargets));
    mValues := Encode(mTokens);
  finally
    mResolver.Free;
  end;
  mData := TJSONArray.Create;
  for mValue in mValues do
  begin
    mData.Add(mValue);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('data', mData);
end;

function TLspSemanticTokens.HandleFull(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, False);
end;

function TLspSemanticTokens.HandleRange(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, True);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SemanticTokens', cTexts);

end.
