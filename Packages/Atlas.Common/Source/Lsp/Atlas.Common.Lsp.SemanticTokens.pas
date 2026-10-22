unit Atlas.Common.Lsp.SemanticTokens;

// Semantische Hervorhebung (textDocument/semanticTokens/full und …/range):
// Jeder Bezeichner wird über die Namensauflösung eingeordnet: Unit, Klasse, Record,
// Interface, Aufzählung, Typ, Parameter, Variable, Feld, Property, Ereignis,
// Aufzählungswert, Funktion, Methode. Modifier: declaration (Name einer Deklaration),
// readonly (Konstanten), defaultLibrary (RTL, VCL, FMX, Winapi).
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
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Reihenfolge = Index in der Legende.</summary>
  TSemanticTokenType = (Namespace, Class_, Enum, Interface_, Struct, Type_, Parameter, Variable, Field, Property_,
    Event, EnumMember, Function_, Method);

  TSemanticTokenModifier = (Declaration, Readonly, DefaultLibrary);
  TSemanticTokenModifiers = set of TSemanticTokenModifier;

  TSemanticToken = record
    Position: TTextPosition;
    Length: Integer;
    TokenType: TSemanticTokenType;
    Modifiers: TSemanticTokenModifiers;
  end;

  TLspSemanticTokens = class
  public const
    FullMethod = 'textDocument/semanticTokens/full';
    RangeMethod = 'textDocument/semanticTokens/range';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
      AWithRange: Boolean): TJSONValue;
    function HandleFull(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleRange(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>semanticTokensProvider mit Legende, full und range.</summary>
    class function Capability: TJSONObject; static;
    class function TypeName(AType: TSemanticTokenType): string; static;
    /// <summary>Eingeordnete Bezeichner in ARange (alle, wenn AWithRange False), nach Position.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange; AWithRange: Boolean;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TSemanticToken>; static;
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
  Atlas.Common.Lsp.Internals.Cancellation;

const
  TypeNames: array[TSemanticTokenType] of string = ('namespace', 'class', 'enum', 'interface', 'struct', 'type',
    'parameter', 'variable', 'field', 'property', 'event', 'enumMember', 'function', 'method');
  ModifierNames: array[TSemanticTokenModifier] of string = ('declaration', 'readonly', 'defaultLibrary');

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function InRange(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) < 0);
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function Classify(const ASymbol: TResolvedSymbol; out AType: TSemanticTokenType;
  out AModifiers: TSemanticTokenModifiers): Boolean;
begin
  Result := True;
  AModifiers := [];
  case ASymbol.Kind of
    TResolvedKind.UnitName:
      begin
        AType := TSemanticTokenType.Namespace;
        if TLibraryUnits.IsLibraryUnit(ASymbol.UnitName) then
          Include(AModifiers, TSemanticTokenModifier.DefaultLibrary);
        Exit;
      end;
    TResolvedKind.Symbol:
      if TLibraryUnits.IsLibraryUnit(ASymbol.UnitName) then
        Include(AModifiers, TSemanticTokenModifier.DefaultLibrary);
    TResolvedKind.Local:
      ;
  else
    Exit(False);
  end;
  case ASymbol.SymbolKind of
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
    TIndexSymbolKind.EnumMember:
      AType := TSemanticTokenType.EnumMember;
    TIndexSymbolKind.Constant:
      begin
        AType := TSemanticTokenType.Variable;
        Include(AModifiers, TSemanticTokenModifier.Readonly);
      end;
    TIndexSymbolKind.Field:
      AType := TSemanticTokenType.Field;
    TIndexSymbolKind.Property_:
      // Ereignisse: Properties mit Methodentyp wie TNotifyEvent.
      if EndsText('Event', ASymbol.TypeName) or EndsText('EventHandler', ASymbol.TypeName) then
        AType := TSemanticTokenType.Event
      else
        AType := TSemanticTokenType.Property_;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_:
      AType := TSemanticTokenType.Method;
    TIndexSymbolKind.Routine:
      AType := TSemanticTokenType.Function_;
  else
    if ASymbol.IsParameter then
      AType := TSemanticTokenType.Parameter
    else
      AType := TSemanticTokenType.Variable;
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
  ADispatcher.RegisterConcurrentRequest(FullMethod, HandleFull);
  ADispatcher.RegisterConcurrentRequest(RangeMethod, HandleRange);
end;

class function TLspSemanticTokens.TypeName(AType: TSemanticTokenType): string;
begin
  Result := TypeNames[AType];
end;

class function TLspSemanticTokens.Capability: TJSONObject;
var
  Legend: TJSONObject;
  Types, Modifiers: TJSONArray;
  TokenType: TSemanticTokenType;
  Modifier: TSemanticTokenModifier;
begin
  Types := TJSONArray.Create;
  for TokenType := Low(TSemanticTokenType) to High(TSemanticTokenType) do
    Types.Add(TypeNames[TokenType]);
  Modifiers := TJSONArray.Create;
  for Modifier := Low(TSemanticTokenModifier) to High(TSemanticTokenModifier) do
    Modifiers.Add(ModifierNames[Modifier]);
  Legend := TJSONObject.Create;
  Legend.AddPair('tokenTypes', Types);
  Legend.AddPair('tokenModifiers', Modifiers);
  Result := TJSONObject.Create;
  Result.AddPair('legend', Legend);
  Result.AddPair('full', TJSONBool.Create(True));
  Result.AddPair('range', TJSONBool.Create(True));
end;

class function TLspSemanticTokens.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string;
  const ARange: TTextRange; AWithRange: Boolean;
  const ACancellation: IJsonRpcCancellationToken): TArray<TSemanticToken>;
var
  Tokens: TArray<TPascalToken>;
  Declarations: TDictionary<string, TIndexSymbol>;
  Symbol: TIndexSymbol;
  Names: TList<string>;
  List: TList<TSemanticToken>;
  Index, First, Previous: Integer;
  Resolved: TResolvedSymbol;
  Item: TSemanticToken;
  Inherited_: Boolean;
  UnitNames: TDictionary<string, Boolean>;
  UnitInfo: TUnitIndex;
  Parts: TArray<string>;
  Count: Integer;
  Chain: string;

  function Key(const APosition: TTextPosition): string;
  begin
    Result := IntToStr(APosition.Line) + ':' + IntToStr(APosition.Character);
  end;

  function PreviousCode(AIndex: Integer): Integer;
  begin
    Result := AIndex - 1;
    while (Result >= 0) and (Tokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Dec(Result);
  end;

begin
  Result := nil;
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  Declarations := TDictionary<string, TIndexSymbol>.Create;
  UnitNames := TDictionary<string, Boolean>.Create;
  Names := TList<string>.Create;
  List := TList<TSemanticToken>.Create;
  AResolver.PinTree(ATree, AFileName);
  try
    // Namen von Deklarationen (auch Methoden in Klassen, die Resolve nicht als Verwendung kennt).
    for Symbol in TIndexExtractor.Extract(ATree, AFileName).Symbols do
      Declarations.AddOrSetValue(Key(Symbol.SelectionRange.StartPos), Symbol);
    // Unit-Namen und ihre Präfixe (System, System.SysUtils): Teile einer gepunkteten Unit.
    if AIndex <> nil then
      for UnitInfo in AIndex.Units do
      begin
        Parts := UnitInfo.UnitName.Split(['.']);
        for Count := 1 to Length(Parts) do
          UnitNames.AddOrSetValue(UpperCase(string.Join('.', Copy(Parts, 0, Count))), True);
      end;
    for Index := 0 to High(Tokens) do
    begin
      // C in ^C ist ein Steuerzeichen, kein Name (#862).
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or ATree.IsControlCharPart(Index) then
        Continue;
      if AWithRange and not InRange(ARange, Tokens[Index].StartPos) then
        Continue;
      if Assigned(ACancellation) and ((Index and 255) = 0) then
        ACancellation.ThrowIfCancellationRequested;
      Item := Default(TSemanticToken);
      Item.Position := Tokens[Index].StartPos;
      Item.Length := Length(Tokens[Index].Text);
      if Declarations.TryGetValue(Key(Tokens[Index].StartPos), Symbol) then
      begin
        Resolved := Default(TResolvedSymbol);
        Resolved.Kind := TResolvedKind.Symbol;
        Resolved.Name := Symbol.Name;
        Resolved.SymbolKind := Symbol.Kind;
        Resolved.TypeName := Symbol.TypeName;
        if Classify(Resolved, Item.TokenType, Item.Modifiers) then
        begin
          Include(Item.Modifiers, TSemanticTokenModifier.Declaration);
          List.Add(Item);
        end;
        Continue;
      end;
      // Kette A.B.C bis zu diesem Bezeichner, wie Resolve sie bildet.
      Names.Clear;
      Names.Add(CleanName(Tokens[Index].Text));
      First := Index;
      Previous := PreviousCode(First);
      while (Previous >= 1) and Tokens[Previous].IsSymbol('.') and (PreviousCode(Previous) >= 0) and
        (Tokens[PreviousCode(Previous)].Kind = TPascalTokenKind.Identifier) do
      begin
        First := PreviousCode(Previous);
        Names.Insert(0, CleanName(Tokens[First].Text));
        Previous := PreviousCode(First);
      end;
      // Foo(1).Bar: Ergebnis eines Ausdrucks, nicht auflösbar.
      if (Previous >= 0) and Tokens[Previous].IsSymbol('.') then
        Continue;
      if (Names.Count = 1) and SameText(Names[0], 'Self') then
      begin
        Item.TokenType := TSemanticTokenType.Variable;
        Item.Modifiers := [TSemanticTokenModifier.Readonly];
        List.Add(Item);
        Continue;
      end;
      Inherited_ := (Previous >= 0) and Tokens[Previous].IsKeyword('inherited');
      Resolved := AResolver.ResolveChain(ATree, AFileName, Names.ToArray, Tokens[Index].Offset, Inherited_);
      if Classify(Resolved, Item.TokenType, Item.Modifiers) then
      begin
        List.Add(Item);
        Continue;
      end;
      // Teil eines gepunkteten Unit-Namens (System in System.SysUtils); Variablen gehen vor.
      Chain := string.Join('.', Names.ToArray);
      if UnitNames.ContainsKey(UpperCase(Chain)) then
      begin
        Item.TokenType := TSemanticTokenType.Namespace;
        Item.Modifiers := [];
        if TLibraryUnits.IsLibraryUnit(Chain) then
          Include(Item.Modifiers, TSemanticTokenModifier.DefaultLibrary);
        List.Add(Item);
      end;
    end;
    Result := List.ToArray;
  finally
    AResolver.UnpinTree;
    List.Free;
    Names.Free;
    UnitNames.Free;
    Declarations.Free;
  end;
end;

class function TLspSemanticTokens.Encode(const ATokens: TArray<TSemanticToken>): TArray<Integer>;
var
  Index, Line, Character, Bits: Integer;
  Modifier: TSemanticTokenModifier;
begin
  SetLength(Result, Length(ATokens) * 5);
  Line := 0;
  Character := 0;
  for Index := 0 to High(ATokens) do
  begin
    Result[Index * 5] := ATokens[Index].Position.Line - Line;
    if ATokens[Index].Position.Line = Line then
      Result[Index * 5 + 1] := ATokens[Index].Position.Character - Character
    else
      Result[Index * 5 + 1] := ATokens[Index].Position.Character;
    Result[Index * 5 + 2] := ATokens[Index].Length;
    Result[Index * 5 + 3] := Ord(ATokens[Index].TokenType);
    Bits := 0;
    for Modifier in ATokens[Index].Modifiers do
      Bits := Bits or (1 shl Ord(Modifier));
    Result[Index * 5 + 4] := Bits;
    Line := ATokens[Index].Position.Line;
    Character := ATokens[Index].Position.Character;
  end;
end;

function TLspSemanticTokens.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
  AWithRange: Boolean): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  RangeValue: TJSONValue;
  Range: TTextRange;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Values: TArray<Integer>;
  Data: TJSONArray;
  Value: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt');
  Range := Default(TTextRange);
  if AWithRange then
  begin
    if not TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue) then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "range" fehlt');
    Range := TLspPositions.ReadRange(RangeValue);
  end;
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Values := Encode(Collect(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), Range, AWithRange, ACancellation));
  finally
    Resolver.Free;
  end;
  Data := TJSONArray.Create;
  for Value in Values do
    Data.Add(Value);
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('data', Data);
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

end.
