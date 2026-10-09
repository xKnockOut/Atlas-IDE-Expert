unit Argus.Common.Lsp.DocumentHighlights;

// Vorkommen hervorheben (textDocument/documentHighlight): alle Stellen der
// aktuellen Datei, die zur selben Deklaration auflösen wie der Bezeichner
// unter dem Cursor.
//
// Art je Stelle: Write bei Zuweisung (Name := ...), Text bei der
// Deklaration selbst, sonst Read. Geprüft werden nur Bezeichner mit
// gleichem Namen; jeder wird einzeln aufgelöst, damit gleichnamige
// Symbole aus anderen Gültigkeitsbereichen nicht mitmarkiert werden.

interface

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver;

type
  {$SCOPEDENUMS ON}
  /// <summary>Werte wie DocumentHighlightKind des LSP.</summary>
  THighlightKind = (Text = 1, Read = 2, Write = 3);
  {$SCOPEDENUMS OFF}

  TDocumentHighlight = record
    Range: TTextRange;
    Kind: THighlightKind;
  end;

  TLspDocumentHighlights = class
  public const
    Method = 'textDocument/documentHighlight';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function HandleHighlight(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Vorkommen des Symbols an APosition in ATree, in Textreihenfolge.</summary>
    class function Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TDocumentHighlight>; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  Argus.Common.Documents.Uris,
  Argus.Common.Lsp.Positions,
  Argus.Common.Lsp.Definition,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.TreeCache,
  Argus.Common.Lsp.Internals.Cancellation;

function CleanName(const AText: string): string;
begin
  // &Begin → Begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if (Token.StartPos.Line > APosition.Line) or
      ((Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character > APosition.Character)) then
      Break;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
      Exit(Index);
  end;
  Result := -1;
end;

function SameTarget(const A, B: TDefinitionTarget): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and (A.SelectionRange.StartPos = B.SelectionRange.StartPos);
end;

{ TLspDocumentHighlights }

constructor TLspDocumentHighlights.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspDocumentHighlights.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleHighlight);
end;

class function TLspDocumentHighlights.Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  const ACancellation: IJsonRpcCancellationToken): TArray<TDocumentHighlight>;
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  Name: string;
  Wanted, Candidate: TArray<TDefinitionTarget>;
  Highlight: TDocumentHighlight;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  Index := TokenAt(Tokens, APosition);
  if Index < 0 then
    Exit;
  Wanted := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Wanted) = 0 then
    Exit;
  Name := CleanName(Tokens[Index].Text);
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(CleanName(Tokens[Index].Text), Name) then
      Continue;
    if ACancellation <> nil then
      ACancellation.ThrowIfCancellationRequested;
    Candidate := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, Tokens[Index].StartPos, True);
    if (Length(Candidate) = 0) or not SameTarget(Candidate[0], Wanted[0]) then
      Continue;
    Highlight.Range := TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos);
    if SameText(Wanted[0].FileName, AFileName) and (Wanted[0].SelectionRange.StartPos = Tokens[Index].StartPos) then
      Highlight.Kind := THighlightKind.Text
    else
    begin
      Highlight.Kind := THighlightKind.Read;
      Next := Index + 1;
      while (Next <= High(Tokens)) and (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Inc(Next);
      if (Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Symbol) and (Tokens[Next].Text = ':=') then
        Highlight.Kind := THighlightKind.Write;
    end;
    Result := Result + [Highlight];
  end;
end;

function TLspDocumentHighlights.HandleHighlight(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Found: TArray<TDocumentHighlight>;
  Highlight: TDocumentHighlight;
  Item: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := FNamespaces;
    Found := Highlights(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue), ACancellation);
  finally
    Resolver.Free;
  end;
  Result := TJSONArray.Create;
  for Highlight in Found do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Highlight.Range));
    Item.AddPair('kind', TJSONNumber.Create(Ord(Highlight.Kind)));
    TJSONArray(Result).AddElement(Item);
  end;
end;

end.
