unit BDLsp.Common.Lsp.Definition;

// Gehe zu Definition und Gehe zu Deklaration (textDocument/definition,
// textDocument/declaration) über die Namensauflösung.
//
// Bei Routinen und Methoden mit getrennter Deklaration und Implementierung:
//   - declaration springt immer zur Deklaration (interface bzw. Klasse),
//   - definition springt zur Implementierung; steht der Cursor bereits auf
//     dem Namen der Implementierung, zurück zur Deklaration. So wechselt
//     dieselbe Taste zwischen beiden.
// Unit-Namen (z. B. in uses) führen an den Anfang der Unit-Datei.
// textDocument/typeDefinition springt von Variablen, Feldern, Parametern,
// Properties und Funktionen zur Deklaration ihres Typs.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver;

type
  TDefinitionTarget = record
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
  end;

  TDefinitionRequestKind = (Definition, Declaration, TypeDefinition);

  TLspDefinition = class
  public const
    DefinitionMethod = 'textDocument/definition';
    DeclarationMethod = 'textDocument/declaration';
    TypeDefinitionMethod = 'textDocument/typeDefinition';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
      AKind: TDefinitionRequestKind): TJSONValue;
    function HandleDefinition(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleDeclaration(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleTypeDefinition(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    /// <summary>Registriert beide Anfragen am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Sprungziele für den Bezeichner an APosition; leer, wenn er nicht auflösbar ist.</summary>
    class function Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>; static;
    /// <summary>Deklaration des Typs des Bezeichners an APosition; leer, wenn er keinen bekannten Typ hat.</summary>
    class function TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
    /// <summary>LocationLink[] des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ATargets: TArray<TDefinitionTarget>): TJSONArray; static;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace).</summary>
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Lsp.Internals.Cancellation;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

function Within(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result :=
    ((APosition.Line > ARange.StartPos.Line) or
     ((APosition.Line = ARange.StartPos.Line) and (APosition.Character >= ARange.StartPos.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
     ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

function Target(const AFileName: string; const ARange, ASelectionRange: TTextRange): TDefinitionTarget;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.SelectionRange := ASelectionRange;
end;

{ TLspDefinition }

constructor TLspDefinition.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspDefinition.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(DefinitionMethod, HandleDefinition);
  ADispatcher.RegisterConcurrentRequest(DeclarationMethod, HandleDeclaration);
  ADispatcher.RegisterConcurrentRequest(TypeDefinitionMethod, HandleTypeDefinition);
end;

class function TLspDefinition.Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  Resolved: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Symbol, First, Last: TIndexSymbol;
  Count: Integer;
  Empty: TTextRange;
begin
  Result := nil;
  Resolved := AResolver.Resolve(ATree, AFileName, APosition);
  // Namen in Deklarationen (z. B. Methoden in der Klasse) sind keine Verwendungen:
  // dann gilt die Deklaration unter dem Cursor selbst.
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
  case Resolved.Kind of
    TResolvedKind.None:
      Exit;
    TResolvedKind.UnitName:
      begin
        Empty := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 0));
        Exit([Target(Resolved.FileName, Empty, Empty)]);
      end;
    TResolvedKind.Local:
      Exit([Target(AFileName, Resolved.Range, Resolved.SelectionRange)]);
  end;

  Result := [Target(Resolved.FileName, Resolved.Range, Resolved.SelectionRange)];
  if not (Resolved.SymbolKind in RoutineKinds) then
    Exit;
  // Deklaration und Implementierung derselben Routine: erste und letzte Fundstelle.
  if SameText(Resolved.FileName, AFileName) then
    OwnerUnit := TIndexExtractor.Extract(ATree, AFileName)
  else if not AIndex.FindFile(Resolved.FileName, OwnerUnit) then
    Exit;
  Count := 0;
  for Symbol in OwnerUnit.Symbols do
    if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, Resolved.Container) and
      SameText(Symbol.Name, Resolved.Name) then
    begin
      if Count = 0 then
        First := Symbol;
      Last := Symbol;
      Inc(Count);
    end;
  if Count < 2 then
    Exit;
  if ADeclaration or (SameText(OwnerUnit.FileName, AFileName) and Within(APosition, Last.SelectionRange)) then
    Result := [Target(OwnerUnit.FileName, First.Range, First.SelectionRange)]
  else
    Result := [Target(OwnerUnit.FileName, Last.Range, Last.SelectionRange)];
end;

class function TLspDefinition.TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  TypeInfo: TResolvedSymbol;
begin
  TypeInfo := AResolver.ResolveType(ATree, AFileName, APosition);
  if TypeInfo.Kind = TResolvedKind.Symbol then
    Result := [Target(TypeInfo.FileName, TypeInfo.Range, TypeInfo.SelectionRange)]
  else
    Result := nil;
end;

class function TLspDefinition.ToJson(const ATargets: TArray<TDefinitionTarget>): TJSONArray;
var
  Item: TDefinitionTarget;
  Location: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Item in ATargets do
  begin
    Location := TJSONObject.Create;
    Location.AddPair('uri', TDocumentUris.FromPath(Item.FileName));
    Location.AddPair('range', TLspPositions.RangeToJson(Item.SelectionRange));
    Result.AddElement(Location);
  end;
end;

function TLspDefinition.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
  AKind: TDefinitionRequestKind): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Tree := TPascalParser.Parse(Document.Text, Cancellation);
  try
    ACancellation.ThrowIfCancellationRequested;
    // Je Anfrage ein eigener Resolver: er hält Zustand pro Aufruf.
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      if AKind = TDefinitionRequestKind.TypeDefinition then
        Result := ToJson(TypeTargets(Resolver, Tree, TDocumentUris.ToPath(Uri),
          TLspPositions.ReadPosition(PositionValue)))
      else
        Result := ToJson(Targets(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
          TLspPositions.ReadPosition(PositionValue), AKind = TDefinitionRequestKind.Declaration));
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
end;

function TLspDefinition.HandleDefinition(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.Definition);
end;

function TLspDefinition.HandleDeclaration(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.Declaration);
end;

function TLspDefinition.HandleTypeDefinition(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.TypeDefinition);
end;

end.
