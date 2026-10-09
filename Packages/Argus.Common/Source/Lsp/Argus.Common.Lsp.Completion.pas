unit Argus.Common.Lsp.Completion;

// Code-Vervollständigung (textDocument/completion), Grundstufe:
//   - nach "A.B." die Mitglieder des Typs von A.B samt geerbter, bei Units deren interface-Symbole,
//   - in uses die bekannten Units,
//   - sonst alle sichtbaren Namen (lokal, eigene Klasse, eigene Unit, Units aus uses).
// Gefiltert wird nach dem schon getippten Anfang; der Editor filtert unscharf nach.
// Noch nicht: Sichtbarkeit (private/protected), Generics, Class Helper, Typinferenz bei var X := ….

interface

{$SCOPEDENUMS ON}

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
  TCompletionContextKind = (None, Scope, Member, UsesClause);

  TCompletionContext = record
    Kind: TCompletionContextKind;
    /// <summary>Schon getippter Anfang des Namens.</summary>
    Prefix: string;
    /// <summary>Kette vor dem Punkt bei Member, z. B. ['Self', 'Liste'].</summary>
    Names: TArray<string>;
    /// <summary>Offset, an dem die Namen gelten.</summary>
    Offset: Integer;
  end;

  TCompletionItem = record
    Name: string;
    Detail: string;
    /// <summary>CompletionItemKind des LSP.</summary>
    Kind: Integer;
  end;

  TCompletionItems = record
    Items: TArray<TCompletionItem>;
    /// <summary>Liste wurde gekürzt; der Editor fragt beim Weitertippen neu.</summary>
    Incomplete: Boolean;
  end;

  TLspCompletion = class
  public const
    Method = 'textDocument/completion';
    MaxItems = 1000;
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
    /// <summary>completionProvider mit Punkt als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Was an APosition vervollständigt wird.</summary>
    class function Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext; static;
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TCompletionItems; static;
    class function KindOf(AKind: TIndexSymbolKind): Integer; static;
    /// <summary>CompletionList des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AItems: TCompletionItems): TJSONObject; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.Generics.Collections,
  Argus.Common.Documents.Uris,
  Argus.Common.Lsp.Positions,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Parser,
  Argus.Common.Lsp.Internals.Cancellation;

const
  // CompletionItemKind
  KindMethod = 2;
  KindFunction = 3;
  KindConstructor = 4;
  KindField = 5;
  KindVariable = 6;
  KindClass = 7;
  KindInterface = 8;
  KindModule = 9;
  KindProperty = 10;
  KindEnum = 13;
  KindEnumMember = 20;
  KindConstant = 21;
  KindStruct = 22;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function InUsesClause(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Token: TPascalToken;
begin
  // Rückwärts über Unit-Namen, Punkte, Kommas und "in 'Datei'" bis zum uses.
  while AIndex >= 0 do
  begin
    Token := ATokens[AIndex];
    if Token.IsKeyword('uses') or Token.IsKeyword('contains') or Token.IsKeyword('requires') then
      Exit(True);
    if not ((Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.StringLiteral]) or
      Token.IsSymbol('.') or Token.IsSymbol(',') or Token.IsKeyword('in') or IsTrivia(Token)) then
      Exit(False);
    Dec(AIndex);
  end;
  Result := False;
end;

{ TLspCompletion }

constructor TLspCompletion.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspCompletion.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspCompletion.Capability: TJSONObject;
var
  Triggers: TJSONArray;
begin
  Triggers := TJSONArray.Create;
  Triggers.Add('.');
  Result := TJSONObject.Create;
  Result.AddPair('triggerCharacters', Triggers);
  Result.AddPair('resolveProvider', TJSONBool.Create(False));
end;

class function TLspCompletion.Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext;
var
  Tokens: TArray<TPascalToken>;
  Index, Last: Integer;
  Token: TPascalToken;
  Names: TList<string>;
begin
  Result := Default(TCompletionContext);
  Result.Kind := TCompletionContextKind.None;
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  // Letztes Token, das vor dem Cursor beginnt.
  Last := -1;
  for Index := 0 to High(Tokens) do
  begin
    if ComparePositions(Tokens[Index].StartPos, APosition) >= 0 then
      Break;
    Last := Index;
  end;
  Result.Offset := 0;
  if Last >= 0 then
  begin
    Token := Tokens[Last];
    Result.Offset := Token.Offset + Length(Token.Text);
    if ComparePositions(APosition, Token.EndPos) < 0 then
    begin
      // Cursor mitten in einem Token: in Kommentaren, Strings und Zahlen nichts anbieten.
      if Token.Kind <> TPascalTokenKind.Identifier then
        Exit;
    end;
    if (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      (ComparePositions(APosition, Token.EndPos) <= 0) then
    begin
      // Angefangener Name; auch ein halbes Schlüsselwort wie "beg" gilt als Anfang.
      if Token.Kind = TPascalTokenKind.Identifier then
        Result.Prefix := CleanName(Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character))
      else
        Result.Prefix := Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character);
      Result.Offset := Token.Offset;
      Last := PreviousIndex(Tokens, Last);
    end
    else if IsTrivia(Token) and (ComparePositions(APosition, Token.EndPos) <= 0) and
      Token.Text.StartsWith('//') then
      // Zeilenkommentar reicht bis zum Zeilenende.
      Exit
    else if IsTrivia(Token) then
      Last := PreviousIndex(Tokens, Last + 1);
  end;

  if (Last >= 0) and Tokens[Last].IsSymbol('.') then
  begin
    Names := TList<string>.Create;
    try
      Index := PreviousIndex(Tokens, Last);
      while (Index >= 0) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) do
      begin
        Names.Insert(0, CleanName(Tokens[Index].Text));
        Index := PreviousIndex(Tokens, Index);
        if (Index >= 0) and Tokens[Index].IsSymbol('.') then
          Index := PreviousIndex(Tokens, Index)
        else
          Break;
      end;
      // Foo(1). oder 1.: nicht auflösbar.
      if (Names.Count = 0) or (Index >= 0) and Tokens[Index].IsSymbol('.') then
        Exit;
      if InUsesClause(Tokens, Last) then
      begin
        // uses System.Sys…: der Anfang gehört zum Unit-Namen.
        Result.Kind := TCompletionContextKind.UsesClause;
        Result.Prefix := string.Join('.', Names.ToArray) + '.' + Result.Prefix;
        Exit;
      end;
      Result.Kind := TCompletionContextKind.Member;
      Result.Names := Names.ToArray;
      Result.Offset := Tokens[Last].Offset;
    finally
      Names.Free;
    end;
    Exit;
  end;
  if (Last >= 0) and InUsesClause(Tokens, Last) then
    Result.Kind := TCompletionContextKind.UsesClause
  else
    Result.Kind := TCompletionContextKind.Scope;
end;

class function TLspCompletion.KindOf(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias:
      Result := KindClass;
    TIndexSymbolKind.RecordType:
      Result := KindStruct;
    TIndexSymbolKind.InterfaceType:
      Result := KindInterface;
    TIndexSymbolKind.EnumType:
      Result := KindEnum;
    TIndexSymbolKind.EnumMember:
      Result := KindEnumMember;
    TIndexSymbolKind.Constant:
      Result := KindConstant;
    TIndexSymbolKind.Field:
      Result := KindField;
    TIndexSymbolKind.Property_:
      Result := KindProperty;
    TIndexSymbolKind.Method:
      Result := KindMethod;
    TIndexSymbolKind.Constructor_:
      Result := KindConstructor;
    TIndexSymbolKind.Routine:
      Result := KindFunction;
  else
    Result := KindVariable;
  end;
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition): TCompletionItems;
var
  Context: TCompletionContext;
  Candidates: TArray<TResolvedSymbol>;
  Candidate: TResolvedSymbol;
  Units: TArray<TUnitIndex>;
  UnitInfo: TUnitIndex;
  List: TList<TCompletionItem>;
  Item: TCompletionItem;
begin
  Result := Default(TCompletionItems);
  Context := Analyze(ATree, APosition);
  List := TList<TCompletionItem>.Create;
  try
    case Context.Kind of
      TCompletionContextKind.UsesClause:
        begin
          Units := AIndex.Units;
          for UnitInfo in Units do
            if UnitInfo.UnitName.StartsWith(Context.Prefix, True) then
            begin
              Item.Name := UnitInfo.UnitName;
              Item.Detail := UnitInfo.FileName;
              Item.Kind := KindModule;
              List.Add(Item);
            end;
        end;
      TCompletionContextKind.Member, TCompletionContextKind.Scope:
        begin
          if Context.Kind = TCompletionContextKind.Member then
            Candidates := AResolver.MemberCandidates(ATree, AFileName, Context.Names, Context.Offset)
          else
            Candidates := AResolver.ScopeCandidates(ATree, AFileName, Context.Offset);
          for Candidate in Candidates do
            if Candidate.Name.StartsWith(Context.Prefix, True) then
            begin
              Item.Name := Candidate.Name;
              if Candidate.TypeName <> '' then
                Item.Detail := Candidate.TypeName
              else if Candidate.Container <> '' then
                Item.Detail := Candidate.Container
              else
                Item.Detail := Candidate.UnitName;
              Item.Kind := KindOf(Candidate.SymbolKind);
              List.Add(Item);
            end;
        end;
    end;
    Result.Incomplete := List.Count > MaxItems;
    if Result.Incomplete then
      List.Count := MaxItems;
    Result.Items := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TLspCompletion.ToJson(const AItems: TCompletionItems): TJSONObject;
var
  Items: TJSONArray;
  Entry: TJSONObject;
  Index: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('isIncomplete', TJSONBool.Create(AItems.Incomplete));
  Items := TJSONArray.Create;
  Result.AddPair('items', Items);
  for Index := 0 to High(AItems.Items) do
  begin
    Entry := TJSONObject.Create;
    Items.AddElement(Entry);
    Entry.AddPair('label', AItems.Items[Index].Name);
    Entry.AddPair('kind', TJSONNumber.Create(AItems.Items[Index].Kind));
    if AItems.Items[Index].Detail <> '' then
      Entry.AddPair('detail', AItems.Items[Index].Detail);
    // Reihenfolge der Gültigkeitsbereiche erhalten: nächster zuerst.
    Entry.AddPair('sortText', Format('%.5d', [Index]));
  end;
end;

function TLspCompletion.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
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
  Cancellation := TRequestCancellation.Create(ACancellation);
  Tree := TPascalParser.Parse(Document.Text, Cancellation);
  try
    ACancellation.ThrowIfCancellationRequested;
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      Result := ToJson(Collect(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue)));
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
end;

end.
