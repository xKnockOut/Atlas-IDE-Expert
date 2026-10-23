unit Atlas.Common.Lsp.Definition;

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
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Dfm.Navigation;

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
    FReadText: TDfmReadText;
    function FormTargets(const AText, AUri: string; const APosition: TTextPosition): TJSONValue;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
      AKind: TDefinitionRequestKind): TJSONValue;
    function HandleDefinition(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleDeclaration(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleTypeDefinition(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
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
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Liest die Unit neben einer Formulardatei (#44); ohne sie gibt es dort keine Sprünge.</summary>
    property ReadText: TDfmReadText read FReadText write FReadText;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Index.Files,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Dfm.Parser;

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

function TLspDefinition.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDefinition.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

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
  // Das Extrakt erst in einer Variablen halten und unten Result zuweisen statt
  // Exit([...]): In der früheren Form brach dcc64 (Delphi 13) ohne Meldung ab.
  if Resolved.Kind = TResolvedKind.None then
  begin
    // Über den Resolver: bei gepinntem Baum ohne neue Auswertung (Code-Review P-01).
    OwnerUnit := AResolver.ExtractedUnit(ATree, AFileName);
    for Symbol in OwnerUnit.Symbols do
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
  end;
  case Resolved.Kind of
    TResolvedKind.None:
      Exit;
    TResolvedKind.UnitName:
      begin
        Empty := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 0));
        Result := [Target(Resolved.FileName, Empty, Empty)];
        Exit;
      end;
    TResolvedKind.Local:
      begin
        Result := [Target(AFileName, Resolved.Range, Resolved.SelectionRange)];
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;

  Result := [Target(Resolved.FileName, Resolved.Range, Resolved.SelectionRange)];
  if not (Resolved.SymbolKind in RoutineKinds) then
    Exit;
  // Deklaration und Implementierung derselben Routine: erste und letzte Fundstelle.
  if SameText(Resolved.FileName, AFileName) then
    OwnerUnit := AResolver.ExtractedUnit(ATree, AFileName)
  else if not TIndexFiles.UnitOf(AIndex, Resolved.FileName, OwnerUnit) then
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
  // Mit Include-Dateien (#500) kann jede Fundstelle in einer anderen Datei stehen.
  if ADeclaration or (SameText(OwnerUnit.SymbolFile(Last), AFileName) and Within(APosition, Last.SelectionRange)) then
    Result := [Target(OwnerUnit.SymbolFile(First), First.Range, First.SelectionRange)]
  else
    Result := [Target(OwnerUnit.SymbolFile(Last), Last.Range, Last.SelectionRange)];
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
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  if TDfmParser.IsFormFile(Uri) then
    Exit(FormTargets(Document.Text, Uri, TLspPositions.ReadPosition(PositionValue)));
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  // Je Anfrage ein eigener Resolver: er hält Zustand pro Aufruf.
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    if AKind = TDefinitionRequestKind.TypeDefinition then
      Result := ToJson(TypeTargets(Resolver, Tree, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue)))
    else
      Result := ToJson(Targets(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue), AKind = TDefinitionRequestKind.Declaration));
  finally
    Resolver.Free;
  end;
end;

function TLspDefinition.FormTargets(const AText, AUri: string; const APosition: TTextPosition): TJSONValue;
var
  Found: TArray<TDfmTarget>;
  Targets: TArray<TDefinitionTarget>;
  Index: Integer;
begin
  if not Assigned(FReadText) then
    Exit(TJSONNull.Create);
  Found := TDfmNavigation.Targets(AText, TDocumentUris.ToPath(AUri), APosition, FReadText);
  SetLength(Targets, Length(Found));
  for Index := 0 to High(Found) do
    Targets[Index] := Target(Found[Index].FileName, Found[Index].Range, Found[Index].SelectionRange);
  Result := ToJson(Targets);
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
