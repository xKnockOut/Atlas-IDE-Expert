unit Atlas.Common.Lsp.InlineValues;

// Werte beim Debuggen am Zeilenende (textDocument/inlineValue, LSP 3.17, #508).
// Der Client nennt den sichtbaren Bereich und die Stelle, an der der Debugger
// steht (context.stoppedLocation). Der Server liefert aus dem Syntaxbaum die
// Bezeichner, deren Wert der Client beim Debugger erfragen darf:
//   - nur in der Routine mit dem Haltepunkt, von ihrem Anfang bis zur Zeile
//     des Haltepunkts (weiter unten hat sich noch nichts geändert);
//   - lokale Variablen, Parameter, Result, Inline- und Schleifenvariablen;
//     Felder der eigenen Klasse (Self) in Kurzform, nicht in with-Anweisungen
//     (dort gehört der Name vielleicht zu einem anderen Objekt);
//   - keine Konstanten, Eigenschaften (Getter könnten etwas ausführen),
//     Routinen, Typen und globalen Variablen; kein Bezeichner hinter einem
//     Punkt und keiner vor „(“ (Aufruf, Typumwandlung). So wertet der Client
//     nie einen Ausdruck mit Funktionsaufruf aus.
//   - Je Zeile jeder Name einmal, höchstens MaxValues Einträge.
// Antwort: InlineValueVariableLookup (range, variableName,
// caseSensitiveLookup = false), sortiert nach Position; dazu "atlasType" mit
// dem deklarierten Typ, damit der Client etwa TDateTime als Datum zeigt.

interface

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
  {$SCOPEDENUMS ON}
  TInlineValueKind = (Local, Field);
  {$SCOPEDENUMS OFF}

  TInlineValue = record
    /// <summary>Stelle des Bezeichners in der Zeile.</summary>
    Range: TTextRange;
    /// <summary>Ausdruck für den Debugger, wie im Quelltext geschrieben.</summary>
    Name: string;
    Kind: TInlineValueKind;
    /// <summary>Deklarierter Typ wie im Quelltext; '' wenn unbekannt.</summary>
    TypeName: string;
  end;

  TLspInlineValues = class
  public const
    Method = 'textDocument/inlineValue';
    MaxValues = 500;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Bezeichner mit Wert in ARange (Zeilen) für einen Halt in Zeile AStoppedLine (0-basiert); leer
    /// außerhalb einer Routine.</summary>
    class function Collect(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange; AStoppedLine: Integer): TArray<TInlineValue>; static;
    /// <summary>InlineValue[] des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AValues: TArray<TInlineValue>): TJSONArray; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache;

type
  TOffsetRange = record
    StartOffset: Integer;
    EndOffset: Integer;
  end;

/// <summary>Innerste benannte Routine, die AOffset enthält; nil außerhalb. Anonyme Methoden gehören zu ihr:
/// Sie sehen deren Variablen.</summary>
function RoutineAt(ARoot: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Node, Child: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  Result := nil;
  Node := ARoot;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      Child := Node[Index];
      if (Child.StartOffset <= AOffset) and (AOffset < Child.EndOffset) then
      begin
        Node := Child;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Result := Node;
        Descended := True;
        Break;
      end;
    end;
  until not Descended;
end;

/// <summary>Offset des ersten Tokens in ALine bzw. danach; -1 ohne.</summary>
function LineOffset(const ATokens: TArray<TPascalToken>; ALine: Integer): Integer;
var
  Token: TPascalToken;
begin
  for Token in ATokens do
    if (Token.StartPos.Line >= ALine) and not (Token.Kind in [TPascalTokenKind.Comment,
      TPascalTokenKind.Directive]) then
      Exit(Token.Offset);
  Result := -1;
end;

function Significant(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Bereiche der with-Anweisungen in ARoutine.</summary>
function WithRanges(ARoutine: TSyntaxNode): TArray<TOffsetRange>;
var
  Found: TList<TOffsetRange>;
begin
  Found := TList<TOffsetRange>.Create;
  try
    ARoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Range: TOffsetRange;
      begin
        if ANode.Kind = TSyntaxKind.WithStatement then
        begin
          Range.StartOffset := ANode.StartOffset;
          Range.EndOffset := ANode.EndOffset;
          Found.Add(Range);
        end;
        Result := True;
      end);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function InAny(const ARanges: TArray<TOffsetRange>; AOffset: Integer): Boolean;
var
  Range: TOffsetRange;
begin
  for Range in ARanges do
    if (Range.StartOffset <= AOffset) and (AOffset < Range.EndOffset) then
      Exit(True);
  Result := False;
end;

{ TLspInlineValues }

constructor TLspInlineValues.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

function TLspInlineValues.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspInlineValues.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

procedure TLspInlineValues.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspInlineValues.Collect(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange; AStoppedLine: Integer): TArray<TInlineValue>;
var
  Tokens: TArray<TPascalToken>;
  Offset, FirstLine, LastLine, Index, Before, After: Integer;
  Routine: TSyntaxNode;
  Withs: TArray<TOffsetRange>;
  Token: TPascalToken;
  Symbol: TResolvedSymbol;
  Found: TList<TInlineValue>;
  Seen: TDictionary<string, Boolean>;
  Value: TInlineValue;
  Key: string;
  IsMethod: Boolean;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  Offset := LineOffset(Tokens, AStoppedLine);
  if Offset < 0 then
    Exit;
  Routine := RoutineAt(ATree.Root, Offset);
  if Routine = nil then
    Exit;
  FirstLine := Routine.StartPos.Line;
  if ARange.StartPos.Line > FirstLine then
    FirstLine := ARange.StartPos.Line;
  LastLine := AStoppedLine;
  if ARange.EndPos.Line < LastLine then
    LastLine := ARange.EndPos.Line;
  if FirstLine > LastLine then
    Exit;
  // Felder nur in Methoden („TKlasse.Name“), dort gehören sie Self.
  IsMethod := Pos('.', Routine.Name) > 0;
  Withs := WithRanges(Routine);
  Found := TList<TInlineValue>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  AResolver.PinTree(ATree, AFileName);
  try
    for Index := 0 to High(Tokens) do
    begin
      Token := Tokens[Index];
      if Token.StartPos.Line > LastLine then
        Break;
      if (Token.StartPos.Line < FirstLine) or (Token.Offset < Routine.StartOffset) or
        (Token.Kind <> TPascalTokenKind.Identifier) or ATree.IsControlCharPart(Index) then
        Continue;
      // Kein Mitglied eines anderen Ausdrucks (X.Name) und kein Aufruf bzw. keine Umwandlung (Name(…)).
      Before := Index - 1;
      while (Before >= 0) and not Significant(Tokens[Before]) do
        Dec(Before);
      if (Before >= 0) and (Tokens[Before].IsSymbol('.') or Tokens[Before].IsSymbol('@') or
        Tokens[Before].IsSymbol('^')) then
        Continue;
      After := Index + 1;
      while (After <= High(Tokens)) and not Significant(Tokens[After]) do
        Inc(After);
      if (After <= High(Tokens)) and Tokens[After].IsSymbol('(') then
        Continue;
      Key := IntToStr(Token.StartPos.Line) + ':' + LowerCase(Token.Text);
      if Seen.ContainsKey(Key) then
        Continue;
      Symbol := AResolver.Resolve(ATree, AFileName, Token.StartPos);
      if (Symbol.Kind = TResolvedKind.Local) and (Symbol.SymbolKind = TIndexSymbolKind.Variable) then
        Value.Kind := TInlineValueKind.Local
      else if IsMethod and (Symbol.Kind = TResolvedKind.Symbol) and (Symbol.SymbolKind = TIndexSymbolKind.Field) and
        (Symbol.Container <> '') and not InAny(Withs, Token.Offset) then
        Value.Kind := TInlineValueKind.Field
      else
        Continue;
      Seen.Add(Key, True);
      Value.Range := TTextRange.Create(Token.StartPos, Token.EndPos);
      Value.Name := Token.Text;
      Value.TypeName := Symbol.TypeName;
      Found.Add(Value);
      if Found.Count >= MaxValues then
        Break;
    end;
    Result := Found.ToArray;
  finally
    AResolver.UnpinTree;
    Seen.Free;
    Found.Free;
  end;
end;

class function TLspInlineValues.ToJson(const AValues: TArray<TInlineValue>): TJSONArray;
var
  Value: TInlineValue;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Value.Range));
    Item.AddPair('variableName', Value.Name);
    Item.AddPair('caseSensitiveLookup', TJSONBool.Create(False));
    if Value.TypeName <> '' then
      Item.AddPair('atlasType', Value.TypeName);
    Result.AddElement(Item);
  end;
end;

function TLspInlineValues.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  RangeValue, StoppedValue: TJSONValue;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Stopped: TTextRange;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('context.stoppedLocation', StoppedValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri", "range" und "context.stoppedLocation" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  ACancellation.ThrowIfCancellationRequested;
  Stopped := TLspPositions.ReadRange(StoppedValue);
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Result := ToJson(Collect(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadRange(RangeValue),
      Stopped.StartPos.Line));
  finally
    Resolver.Free;
  end;
end;

end.
