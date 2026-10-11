unit Atlas.Common.Lsp.Implementations;

// Gehe zu Implementierung (textDocument/implementation):
//   - bei virtuellen, abstrakten und Interface-Methoden alle Rümpfe in den Nachfahren
//     (bei Klassenmethoden mit Rumpf auch den eigenen),
//   - bei Klassen und Interfaces alle Nachfahren bzw. implementierenden Klassen,
//   - auf "inherited" den Rumpf der aufgerufenen Methode im Vorfahren
//     (bei "inherited;" ohne Namen die gleichnamige Methode).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Definition;

type
  TLspImplementations = class
  public const
    Method = 'textDocument/implementation';
    MaxTargets = 500;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Sprungziele für das Symbol bzw. das inherited an APosition.</summary>
    class function Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Internals.Cancellation;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  MaxDepth = 32;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function Within(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) <= 0);
end;

function Target(const AFileName: string; const ARange, ASelection: TTextRange): TDefinitionTarget;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.SelectionRange := ASelection;
end;

function OwnerUnitOf(const AIndex: ISymbolIndex; ATree: TSyntaxTree; const ACurrentFile, AFileName: string;
  out AUnit: TUnitIndex): Boolean;
begin
  // Die eigene Datei aus dem Editor, nicht aus dem Index.
  if SameText(AFileName, ACurrentFile) then
  begin
    AUnit := TIndexExtractor.Extract(ATree, ACurrentFile);
    Exit(True);
  end;
  Result := AIndex.FindFile(AFileName, AUnit);
end;

/// <summary>Rumpf der Routine AName in AContainer: die letzte Fundstelle, wenn es mehr als eine gibt.</summary>
function FindBody(const AUnit: TUnitIndex; const AContainer, AName: string; out ABody: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
  Count: Integer;
begin
  Count := 0;
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName) then
    begin
      ABody := Symbol;
      Inc(Count);
    end;
  Result := Count >= 2;
end;

/// <summary>Alle Nachfahren von ATypeName, auch über mehrere Stufen; Kreise werden erkannt.</summary>
function AllDescendants(const AIndex: ISymbolIndex; const ATypeName: string): TArray<TSymbolLocation>;
var
  Pending: TQueue<TPair<string, Integer>>;
  Seen: TDictionary<string, Boolean>;
  Current: TPair<string, Integer>;
  Location: TSymbolLocation;
  Key: string;
begin
  Result := nil;
  Pending := TQueue<TPair<string, Integer>>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Pending.Enqueue(TPair<string, Integer>.Create(ATypeName, 0));
    while Pending.Count > 0 do
    begin
      Current := Pending.Dequeue;
      if Current.Value >= MaxDepth then
        Continue;
      for Location in AIndex.Descendants(Current.Key) do
      begin
        if not (Location.Symbol.Kind in TypeKinds) then
          Continue;
        Key := UpperCase(Location.FileName + '|' + Location.Symbol.QualifiedName);
        if Seen.ContainsKey(Key) then
          Continue;
        Seen.Add(Key, True);
        Result := Result + [Location];
        Pending.Enqueue(TPair<string, Integer>.Create(Location.Symbol.QualifiedName, Current.Value + 1));
      end;
    end;
  finally
    Seen.Free;
    Pending.Free;
  end;
end;

function TokenIndexAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if ComparePositions(ATokens[Index].StartPos, APosition) > 0 then
      Break;
    if ComparePositions(APosition, ATokens[Index].EndPos) <= 0 then
      Exit(Index);
  end;
  Result := -1;
end;

function EnclosingRoutineName(ANode: TSyntaxNode; AOffset: Integer): string;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  // Äußerste Routine: bei verschachtelten Routinen gilt die Methode.
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if (Child.StartOffset > AOffset) or (AOffset > Child.EndOffset) then
      Continue;
    if Child.Kind = TSyntaxKind.RoutineDecl then
      Exit(Child.Name);
    Exit(EnclosingRoutineName(Child, AOffset));
  end;
  Result := '';
end;

function InheritedTargets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; ATokenIndex: Integer): TArray<TDefinitionTarget>;
var
  Tokens: TArray<TPascalToken>;
  Next: Integer;
  Name: string;
  Resolved: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Body: TIndexSymbol;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  Next := ATokenIndex + 1;
  while (Next <= High(Tokens)) and (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Next);
  if (Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Identifier) then
    // inherited Create(...): wie Gehe zu Definition auf dem Namen.
    Exit(TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, Tokens[Next].StartPos, False));
  // inherited; → gleichnamige Methode im Vorfahren.
  Name := EnclosingRoutineName(ATree.Root, Tokens[ATokenIndex].Offset);
  if Name = '' then
    Exit;
  Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Resolved := AResolver.ResolveChain(ATree, AFileName, [Name], Tokens[ATokenIndex].Offset, True);
  if not Resolved.Found then
    Exit;
  Result := [Target(Resolved.FileName, Resolved.Range, Resolved.SelectionRange)];
  if OwnerUnitOf(AIndex, ATree, AFileName, Resolved.FileName, OwnerUnit) and
    FindBody(OwnerUnit, Resolved.Container, Resolved.Name, Body) then
    Result := [Target(OwnerUnit.FileName, Body.Range, Body.SelectionRange)];
end;

{ TLspImplementations }

constructor TLspImplementations.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspImplementations.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspImplementations.Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  TokenIndex: Integer;
  Resolved: TResolvedSymbol;
  Symbol, Body: TIndexSymbol;
  OwnerUnit, DescendantUnit: TUnitIndex;
  Location: TSymbolLocation;
  TypeName: string;
  List: TList<TDefinitionTarget>;
begin
  Result := nil;
  if ATree = nil then
    Exit;
  TokenIndex := TokenIndexAt(ATree.Tokens, APosition);
  if (TokenIndex >= 0) and ATree.Tokens[TokenIndex].IsKeyword('inherited') then
    Exit(InheritedTargets(AResolver, AIndex, ATree, AFileName, TokenIndex));

  Resolved := AResolver.Resolve(ATree, AFileName, APosition);
  // Name einer Deklaration (Methode in der Klasse, Typname): die Deklaration selbst.
  if Resolved.Kind = TResolvedKind.None then
    for Symbol in TIndexExtractor.Extract(ATree, AFileName).Symbols do
      if Within(APosition, Symbol.SelectionRange) then
      begin
        Resolved.Kind := TResolvedKind.Symbol;
        Resolved.Name := Symbol.Name;
        Resolved.Container := Symbol.Container;
        Resolved.SymbolKind := Symbol.Kind;
        Resolved.FileName := AFileName;
        Resolved.Range := Symbol.Range;
        Resolved.SelectionRange := Symbol.SelectionRange;
        Break;
      end;
  if Resolved.Kind <> TResolvedKind.Symbol then
    Exit;

  List := TList<TDefinitionTarget>.Create;
  try
    if Resolved.SymbolKind in TypeKinds then
    begin
      for Location in AllDescendants(AIndex, Resolved.QualifiedName) do
        List.Add(Target(Location.FileName, Location.Symbol.Range, Location.Symbol.SelectionRange));
    end
    else if (Resolved.SymbolKind in RoutineKinds) and (Resolved.Container <> '') then
    begin
      // Eigener Rumpf (fehlt bei abstrakten und Interface-Methoden).
      if OwnerUnitOf(AIndex, ATree, AFileName, Resolved.FileName, OwnerUnit) and
        FindBody(OwnerUnit, Resolved.Container, Resolved.Name, Body) then
        List.Add(Target(OwnerUnit.FileName, Body.Range, Body.SelectionRange));
      for Location in AllDescendants(AIndex, Resolved.Container) do
      begin
        if List.Count >= MaxTargets then
          Break;
        if not OwnerUnitOf(AIndex, ATree, AFileName, Location.FileName, DescendantUnit) then
          Continue;
        TypeName := Location.Symbol.QualifiedName;
        if FindBody(DescendantUnit, TypeName, Resolved.Name, Body) then
          List.Add(Target(DescendantUnit.FileName, Body.Range, Body.SelectionRange))
        else
          // Nur deklariert (z. B. abstrakt wiederholt): die Deklaration.
          for Symbol in DescendantUnit.Symbols do
            if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, TypeName) and
              SameText(Symbol.Name, Resolved.Name) then
            begin
              List.Add(Target(DescendantUnit.FileName, Symbol.Range, Symbol.SelectionRange));
              Break;
            end;
      end;
    end;
    if List.Count > MaxTargets then
      List.Count := MaxTargets;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TLspImplementations.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := FNamespaces;
    Result := TLspDefinition.ToJson(Targets(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue)));
  finally
    Resolver.Free;
  end;
end;

end.
