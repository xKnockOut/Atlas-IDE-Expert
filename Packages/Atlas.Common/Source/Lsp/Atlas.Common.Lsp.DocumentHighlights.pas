unit Atlas.Common.Lsp.DocumentHighlights;

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
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  {$SCOPEDENUMS ON}
  /// <summary>Werte wie DocumentHighlightKind des LSP.</summary>
  THighlightKind = (Text = 1, Read = 2, Write = 3);
  {$SCOPEDENUMS OFF}

  TDocumentHighlight = record
    Range: TTextRange;
    Kind: THighlightKind;
  end;

  /// <summary>Einstellungen zur Schlüsselworthervorhebung (#307) für eine Datei-URI.</summary>
  THighlightSettingsProvider = reference to function(const AUri: string): THighlightSettings;

  TLspDocumentHighlights = class
  public const
    Method = 'textDocument/documentHighlight';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FSettingsFor: THighlightSettingsProvider;
    function HandleHighlight(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
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
    /// <summary>Vorkommen des Symbols an APosition in ATree, in Textreihenfolge.</summary>
    class function Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken): TArray<TDocumentHighlight>; overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function Highlights(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TArray<TDocumentHighlight>; overload; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Ohne Zuweisung gelten die Vorgaben.</summary>
    property SettingsFor: THighlightSettingsProvider read FSettingsFor write FSettingsFor;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.KeywordHighlights;

function CleanName(const AText: string): string;
begin
  // &Begin → Begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
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
    begin
      Break;
    end;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function SameTarget(const A, B: TDefinitionTarget): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and (A.SelectionRange.StartPos = B.SelectionRange.StartPos);
end;

{ TLspDocumentHighlights }

function TLspDocumentHighlights.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDocumentHighlights.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspDocumentHighlights.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

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
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TDocumentHighlight>;
begin
  Result := Highlights(AResolver, AIndex, ATree, AFileName, APosition, nil);
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
  Found: TList<TDocumentHighlight>;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  Index := TokenAt(Tokens, APosition);
  if Index < 0 then
  begin
    Exit;
  end;
  Found := TList<TDocumentHighlight>.Create;
  // Den Baum einmal auswerten statt je Vorkommen (Code-Review P-01).
  AResolver.PinTree(ATree, AFileName);
  try
    Wanted := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
    if Length(Wanted) = 0 then
    begin
      Exit;
    end;
    Name := CleanName(Tokens[Index].Text);
    for Index := 0 to High(Tokens) do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(CleanName(Tokens[Index].Text), Name) then
      begin
        Continue;
      end;
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      Candidate := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, Tokens[Index].StartPos, True);
      if (Length(Candidate) = 0) or not SameTarget(Candidate[0], Wanted[0]) then
      begin
        Continue;
      end;
      Highlight.Range := TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos);
      if SameText(Wanted[0].FileName, AFileName) and (Wanted[0].SelectionRange.StartPos = Tokens[Index].StartPos) then
      begin
        Highlight.Kind := THighlightKind.Text;
      end
      else
      begin
        Highlight.Kind := THighlightKind.Read;
        Next := Index + 1;
        while (Next <= High(Tokens)) and (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        begin
          Inc(Next);
        end;
        if (Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Symbol) and (Tokens[Next].Text = ':=') then
        begin
          Highlight.Kind := THighlightKind.Write;
        end;
      end;
      // Liste statt Result := Result + [...] (Code-Review P-08).
      Found.Add(Highlight);
    end;
    Result := Found.ToArray;
  finally
    AResolver.UnpinTree;
    Found.Free;
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
  Settings: THighlightSettings;
  Ranges: TArray<TTextRange>;
  Index: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  // Zuerst zusammengehörige Schlüsselwörter (#307), sonst Bezeichner.
  if Assigned(FSettingsFor) then
  begin
    Settings := FSettingsFor(Uri);
  end
  else
  begin
    Settings := THighlightSettings.Default;
  end;
  if TKeywordHighlights.Find(Tree, TLspPositions.ReadPosition(PositionValue), Settings, Ranges) then
  begin
    SetLength(Found, Length(Ranges));
    for Index := 0 to High(Ranges) do
    begin
      Found[Index].Range := Ranges[Index];
      Found[Index].Kind := THighlightKind.Text;
    end;
  end
  else
  begin
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := Namespaces;
      Found := Highlights(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue), ACancellation);
    finally
      Resolver.Free;
    end;
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
