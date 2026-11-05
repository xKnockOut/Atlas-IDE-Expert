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
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TInlineValuesText = (FieldsTextDocumentUriRangeAnd);

const
  cTexts: array[TInlineValuesText] of TAtlasText = (
    (De: 'Felder "textDocument.uri", "range" und "context.stoppedLocation" fehlen in ';
     En: 'Fields "textDocument.uri", "range" and "context.stoppedLocation" missing in '));

{$SCOPEDENUMS OFF}

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
        begin
          Result := Node;
        end;
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
  begin
    if (Token.StartPos.Line >= ALine) and not (Token.Kind in [TPascalTokenKind.Comment,
      TPascalTokenKind.Directive]) then
    begin
      Exit(Token.Offset);
    end;
  end;
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
  begin
    if (Range.StartOffset <= AOffset) and (AOffset < Range.EndOffset) then
    begin
      Exit(True);
    end;
  end;
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

/// <summary>Zeilen von AFirstLine bis ALastLine, in denen ARoutine Werte zeigt: ab ihrem Anfang bzw. ARange bis
/// zum Halt bzw. zum Ende von ARange. False, wenn nichts bleibt.</summary>
function LineSpan(ARoutine: TSyntaxNode; const ARange: TTextRange; AStoppedLine: Integer;
  out AFirstLine, ALastLine: Integer): Boolean;
begin
  AFirstLine := ARoutine.StartPos.Line;
  if ARange.StartPos.Line > AFirstLine then
  begin
    AFirstLine := ARange.StartPos.Line;
  end;
  ALastLine := AStoppedLine;
  if ARange.EndPos.Line < ALastLine then
  begin
    ALastLine := ARange.EndPos.Line;
  end;
  Result := AFirstLine <= ALastLine;
end;

/// <summary>True, wenn der Bezeichner an AIndex weder Mitglied eines anderen Ausdrucks (X.Name, @Name, ^Name) noch
/// Aufruf bzw. Umwandlung (Name(…)) ist.</summary>
function IsPlainName(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mBefore, mAfter: Integer;
begin
  mBefore := AIndex - 1;
  while (mBefore >= 0) and not Significant(ATokens[mBefore]) do
  begin
    Dec(mBefore);
  end;
  if (mBefore >= 0) and (ATokens[mBefore].IsSymbol('.') or ATokens[mBefore].IsSymbol('@') or
    ATokens[mBefore].IsSymbol('^')) then
  begin
    Exit(False);
  end;
  mAfter := AIndex + 1;
  while (mAfter <= High(ATokens)) and not Significant(ATokens[mAfter]) do
  begin
    Inc(mAfter);
  end;
  Result := not ((mAfter <= High(ATokens)) and ATokens[mAfter].IsSymbol('('));
end;

type
  /// <summary>Was Collect über die Routine mit dem Haltepunkt weiß.</summary>
  TCollectScope = record
    Resolver: TNameResolver;
    Tree: TSyntaxTree;
    FileName: string;
    Routine: TSyntaxNode;
    /// <summary>Felder nur in Methoden („TKlasse.Name“), dort gehören sie Self.</summary>
    IsMethod: Boolean;
    Withs: TArray<TOffsetRange>;
  end;

/// <summary>Art des Werts für ASymbol an AOffset; False, wenn der Name keinen Wert zeigt.</summary>
function ValueKind(const AScope: TCollectScope; const ASymbol: TResolvedSymbol; AOffset: Integer;
  out AKind: TInlineValueKind): Boolean;
begin
  AKind := TInlineValueKind.Local;
  if (ASymbol.Kind = TResolvedKind.Local) and (ASymbol.SymbolKind = TIndexSymbolKind.Variable) then
  begin
    Exit(True);
  end;
  AKind := TInlineValueKind.Field;
  Result := AScope.IsMethod and (ASymbol.Kind = TResolvedKind.Symbol) and
    (ASymbol.SymbolKind = TIndexSymbolKind.Field) and (ASymbol.Container <> '') and not InAny(AScope.Withs, AOffset);
end;

/// <summary>Wert für den Bezeichner AToken; False, wenn er keinen zeigt.</summary>
function TryValue(const AScope: TCollectScope; const AToken: TPascalToken; out AValue: TInlineValue): Boolean;
var
  mSymbol: TResolvedSymbol;
begin
  AValue := Default(TInlineValue);
  mSymbol := AScope.Resolver.Resolve(AScope.Tree, AScope.FileName, AToken.StartPos);
  Result := ValueKind(AScope, mSymbol, AToken.Offset, AValue.Kind);
  AValue.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  AValue.Name := AToken.Text;
  AValue.TypeName := mSymbol.TypeName;
end;

/// <summary>True, wenn das Token an AIndex ein schlichter Bezeichner der Routine ab Zeile AFirstLine ist.</summary>
function IsCandidate(const AScope: TCollectScope; AIndex, AFirstLine: Integer): Boolean;
var
  mToken: TPascalToken;
begin
  mToken := AScope.Tree.Tokens[AIndex];
  Result := (mToken.StartPos.Line >= AFirstLine) and (mToken.Offset >= AScope.Routine.StartOffset) and
    (mToken.Kind = TPascalTokenKind.Identifier) and not AScope.Tree.IsControlCharPart(AIndex) and
    IsPlainName(AScope.Tree.Tokens, AIndex);
end;

/// <summary>Werte der Bezeichner in den Zeilen AFirstLine bis ALastLine, je Zeile jeder Name einmal.</summary>
function ScanValues(const AScope: TCollectScope; AFirstLine, ALastLine: Integer): TArray<TInlineValue>;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mToken: TPascalToken;
  mFound: TList<TInlineValue>;
  mSeen: TDictionary<string, Boolean>;
  mValue: TInlineValue;
  mKey: string;
begin
  mTokens := AScope.Tree.Tokens;
  mFound := TList<TInlineValue>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mIndex := 0;
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].StartPos.Line <= ALastLine) and
      (mFound.Count < TLspInlineValues.MaxValues) do
    begin
      mToken := mTokens[mIndex];
      mKey := IntToStr(mToken.StartPos.Line) + ':' + LowerCase(mToken.Text);
      if IsCandidate(AScope, mIndex, AFirstLine) and not mSeen.ContainsKey(mKey) and
        TryValue(AScope, mToken, mValue) then
      begin
        mSeen.Add(mKey, True);
        mFound.Add(mValue);
      end;
      Inc(mIndex);
    end;
    Result := mFound.ToArray;
  finally
    mSeen.Free;
    mFound.Free;
  end;
end;

class function TLspInlineValues.Collect(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange; AStoppedLine: Integer): TArray<TInlineValue>;
var
  mOffset, mFirstLine, mLastLine: Integer;
  mScope: TCollectScope;
begin
  Result := nil;
  mOffset := LineOffset(ATree.Tokens, AStoppedLine);
  if mOffset < 0 then
  begin
    Exit;
  end;
  mScope := Default(TCollectScope);
  mScope.Routine := RoutineAt(ATree.Root, mOffset);
  if (mScope.Routine = nil) or not LineSpan(mScope.Routine, ARange, AStoppedLine, mFirstLine, mLastLine) then
  begin
    Exit;
  end;
  mScope.Resolver := AResolver;
  mScope.Tree := ATree;
  mScope.FileName := AFileName;
  mScope.IsMethod := Pos('.', mScope.Routine.Name) > 0;
  mScope.Withs := WithRanges(mScope.Routine);
  AResolver.PinTree(ATree, AFileName);
  try
    Result := ScanValues(mScope, mFirstLine, mLastLine);
  finally
    AResolver.UnpinTree;
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
    begin
      Item.AddPair('atlasType', Value.TypeName);
    end;
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
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TInlineValuesText.FieldsTextDocumentUriRangeAnd].Text + Method);
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.InlineValues', cTexts);

end.
