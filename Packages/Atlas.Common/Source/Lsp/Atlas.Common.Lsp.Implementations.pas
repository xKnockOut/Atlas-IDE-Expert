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
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Sprungziele für das Symbol bzw. das inherited an APosition.</summary>
    class function Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
    /// <summary>Alle Nachfahren von ATypeName über alle Stufen, Kreise erkannt (auch für die Zeilenleiste #768).
    /// </summary>
    class function AllDescendantsOf(const AIndex: ISymbolIndex; const ATypeName: string): TArray<TSymbolLocation>;
      static;
    /// <summary>Ist ATypeName (qualifiziert oder kurz) im Index ein Interface?</summary>
    class function IsInterfaceType(const AIndex: ISymbolIndex; const ATypeName: string): Boolean; static;
    /// <summary>Umsetzungen der Methode AName von AContainer, die ein Aufruf erreichen kann (#1122): bei einem
    /// Interface die Klassen, die es umsetzen (auch über Vorfahren), sonst die Methode selbst und jede
    /// Nachfahrenklasse, die sie neu deklariert. 0 ohne Index.</summary>
    class function ImplementationCount(const AIndex: ISymbolIndex; const AContainer, AName: string;
      AInterface: Boolean): Integer; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TImplementationsText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TImplementationsText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'));

{$SCOPEDENUMS OFF}

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  MaxDepth = 32;

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
  begin
    if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName) then
    begin
      ABody := Symbol;
      Inc(Count);
    end;
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
      begin
        Continue;
      end;
      for Location in AIndex.Descendants(Current.Key) do
      begin
        if not (Location.Symbol.Kind in TypeKinds) then
        begin
          Continue;
        end;
        Key := UpperCase(Location.FileName + '|' + Location.Symbol.QualifiedName);
        if Seen.ContainsKey(Key) then
        begin
          Continue;
        end;
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
    begin
      Break;
    end;
    if ComparePositions(APosition, ATokens[Index].EndPos) <= 0 then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function EnclosingRoutineName(ANode: TSyntaxNode; AOffset: Integer): string;
var
  Index: Integer;
  Node, Child: TSyntaxNode;
begin
  // Äußerste Routine: bei verschachtelten Routinen gilt die Methode. Schleife statt Rekursion (Bericht M1):
  // dem ersten Kind folgen, das AOffset enthält.
  Node := ANode;
  while Node <> nil do
  begin
    Child := nil;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if (Node[Index].StartOffset <= AOffset) and (AOffset <= Node[Index].EndOffset) then
      begin
        Child := Node[Index];
        Break;
      end;
    end;
    if (Child <> nil) and (Child.Kind = TSyntaxKind.RoutineDecl) then
    begin
      Exit(Child.Name);
    end;
    Node := Child;
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
  begin
    Inc(Next);
  end;
  if (Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Identifier) then
  begin
    // inherited Create(...): wie Gehe zu Definition auf dem Namen.
    Exit(TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, Tokens[Next].StartPos, False));
  end;
  // inherited; → gleichnamige Methode im Vorfahren.
  Name := EnclosingRoutineName(ATree.Root, Tokens[ATokenIndex].Offset);
  if Name = '' then
  begin
    Exit;
  end;
  Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Resolved := AResolver.ResolveChain(ATree, AFileName, [Name], Tokens[ATokenIndex].Offset, True);
  if not Resolved.Found then
  begin
    Exit;
  end;
  Result := [Target(Resolved.FileName, Resolved.Range, Resolved.SelectionRange)];
  if OwnerUnitOf(AIndex, ATree, AFileName, Resolved.FileName, OwnerUnit) and
    FindBody(OwnerUnit, Resolved.Container, Resolved.Name, Body) then
  begin
    Result := [Target(OwnerUnit.FileName, Body.Range, Body.SelectionRange)];
  end;
end;

{ TLspImplementations }

function TLspImplementations.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspImplementations.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspImplementations.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspImplementations.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

class function TLspImplementations.AllDescendantsOf(const AIndex: ISymbolIndex;
  const ATypeName: string): TArray<TSymbolLocation>;
begin
  Result := AllDescendants(AIndex, ATypeName);
end;

class function TLspImplementations.IsInterfaceType(const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
var
  Location: TSymbolLocation;
  Short: string;
begin
  Result := False;
  if AIndex = nil then
  begin
    Exit;
  end;
  Short := ATypeName;
  if Short.LastIndexOf('.') >= 0 then
  begin
    Short := Copy(Short, Short.LastIndexOf('.') + 2, MaxInt);
  end;
  for Location in AIndex.FindSymbols(Short) do
  begin
    if (Location.Symbol.Kind = TIndexSymbolKind.InterfaceType) and
      (SameText(Location.Symbol.QualifiedName, ATypeName) or SameText(Location.Symbol.Name, ATypeName)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TLspImplementations.ImplementationCount(const AIndex: ISymbolIndex; const AContainer, AName: string;
  AInterface: Boolean): Integer;
var
  Location: TSymbolLocation;
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  Result := 0;
  if AIndex = nil then
  begin
    Exit;
  end;
  // Eine virtuelle Methode ist selbst ein mögliches Ziel; ein Interface hat keinen Rumpf.
  if not AInterface then
  begin
    Result := 1;
  end;
  for Location in AllDescendants(AIndex, AContainer) do
  begin
    if not (Location.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType]) then
    begin
      Continue;
    end;
    if AInterface then
    begin
      Inc(Result);
      Continue;
    end;
    if not AIndex.FindFile(Location.FileName, Owner) then
    begin
      Continue;
    end;
    for Symbol in Owner.Symbols do
    begin
      if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, Location.Symbol.QualifiedName) and
        SameText(Symbol.Name, AName) then
      begin
        Inc(Result);
        Break;
      end;
    end;
  end;
end;

procedure TLspImplementations.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

/// <summary>Ist AResolved nicht aufgelöst und steht APosition auf dem Namen einer Deklaration (Methode in der
/// Klasse, Typname), wird AResolved zu dieser Deklaration.</summary>
procedure ResolveDeclaration(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  var AResolved: TResolvedSymbol);
var
  mSymbol: TIndexSymbol;
begin
  if AResolved.Kind <> TResolvedKind.None then
  begin
    Exit;
  end;
  for mSymbol in TIndexExtractor.Extract(ATree, AFileName).Symbols do
  begin
    if Within(APosition, mSymbol.SelectionRange) then
    begin
      AResolved.Kind := TResolvedKind.Symbol;
      AResolved.Name := mSymbol.Name;
      AResolved.Container := mSymbol.Container;
      AResolved.SymbolKind := mSymbol.Kind;
      AResolved.FileName := AFileName;
      AResolved.Range := mSymbol.Range;
      AResolved.SelectionRange := mSymbol.SelectionRange;
      Exit;
    end;
  end;
end;

/// <summary>Erste Deklaration der Routine AName in AContainer.</summary>
function FindDeclaration(const AUnit: TUnitIndex; const AContainer, AName: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in RoutineKinds) and SameText(mSymbol.Container, AContainer) and SameText(mSymbol.Name, AName) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Rumpf der Routine AName im Nachfahren ATypeName, sonst ihre Deklaration (z. B. abstrakt wiederholt).
/// </summary>
procedure AddDescendantTarget(AList: TList<TDefinitionTarget>; const AUnit: TUnitIndex;
  const ATypeName, AName: string);
var
  mSymbol: TIndexSymbol;
begin
  if FindBody(AUnit, ATypeName, AName, mSymbol) or FindDeclaration(AUnit, ATypeName, AName, mSymbol) then
  begin
    AList.Add(Target(AUnit.FileName, mSymbol.Range, mSymbol.SelectionRange));
  end;
end;

/// <summary>Ziele der Methode AResolved: ihr eigener Rumpf und die Überschreibungen in den Nachfahren.</summary>
procedure AddMethodTargets(AList: TList<TDefinitionTarget>; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AResolved: TResolvedSymbol);
var
  mBody: TIndexSymbol;
  mOwnerUnit, mDescendantUnit: TUnitIndex;
  mLocation: TSymbolLocation;
begin
  // Eigener Rumpf (fehlt bei abstrakten und Interface-Methoden).
  if OwnerUnitOf(AIndex, ATree, AFileName, AResolved.FileName, mOwnerUnit) and
    FindBody(mOwnerUnit, AResolved.Container, AResolved.Name, mBody) then
  begin
    AList.Add(Target(mOwnerUnit.FileName, mBody.Range, mBody.SelectionRange));
  end;
  for mLocation in AllDescendants(AIndex, AResolved.Container) do
  begin
    if AList.Count >= TLspImplementations.MaxTargets then
    begin
      Break;
    end;
    if OwnerUnitOf(AIndex, ATree, AFileName, mLocation.FileName, mDescendantUnit) then
    begin
      AddDescendantTarget(AList, mDescendantUnit, mLocation.Symbol.QualifiedName, AResolved.Name);
    end;
  end;
end;

/// <summary>Ziele zu AResolved: Nachfahren eines Typs bzw. Rümpfe einer Methode.</summary>
procedure AddTargets(AList: TList<TDefinitionTarget>; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AResolved: TResolvedSymbol);
var
  mLocation: TSymbolLocation;
begin
  if AResolved.SymbolKind in TypeKinds then
  begin
    for mLocation in AllDescendants(AIndex, AResolved.QualifiedName) do
    begin
      AList.Add(Target(mLocation.FileName, mLocation.Symbol.Range, mLocation.Symbol.SelectionRange));
    end;
  end
  else if (AResolved.SymbolKind in RoutineKinds) and (AResolved.Container <> '') then
  begin
    AddMethodTargets(AList, AIndex, ATree, AFileName, AResolved);
  end;
end;

class function TLspImplementations.Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  mTokenIndex: Integer;
  mResolved: TResolvedSymbol;
  mList: TList<TDefinitionTarget>;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mTokenIndex := TokenIndexAt(ATree.Tokens, APosition);
  if (mTokenIndex >= 0) and ATree.Tokens[mTokenIndex].IsKeyword('inherited') then
  begin
    Exit(InheritedTargets(AResolver, AIndex, ATree, AFileName, mTokenIndex));
  end;
  mResolved := AResolver.Resolve(ATree, AFileName, APosition);
  ResolveDeclaration(ATree, AFileName, APosition, mResolved);
  if mResolved.Kind <> TResolvedKind.Symbol then
  begin
    Exit;
  end;
  mList := TList<TDefinitionTarget>.Create;
  try
    AddTargets(mList, AIndex, ATree, AFileName, mResolved);
    if mList.Count > MaxTargets then
    begin
      mList.Count := MaxTargets;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
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
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TImplementationsText.FieldsTextDocumentUriAndPosition].Text);
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Result := TLspDefinition.ToJson(Targets(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue)));
  finally
    Resolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Implementations', cTexts);

end.
