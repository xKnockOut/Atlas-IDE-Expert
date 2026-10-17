unit Atlas.Common.Lsp.LinkedEditing;

// Gleichzeitiges Bearbeiten (textDocument/linkedEditingRange, #39): Steht der
// Cursor auf dem Namen einer Methode oder Routine, ändern sich Deklaration und
// Implementierung in derselben Datei gemeinsam.
//
// Verknüpft werden genau zwei Stellen mit gleichem Typ, Namen und Art. Bei
// Überladungen ist die Zuordnung nicht eindeutig; dann liefert der Server nichts.
//
// Lokale Bezeichner (#658): Steht der Cursor auf einer lokalen Variable, einem
// Parameter, einer lokalen Konstante, einer Inline- oder Schleifenvariable,
// sind alle Vorkommen in der deklarierenden Routine verknüpft, die zur selben
// Deklaration auflösen (gleichnamige Felder, Strings und Kommentare nicht).
// Dazu "atlasConflicts": Namen, die an der Deklaration oder einem Vorkommen
// schon sichtbar sind (lokale Namen, Mitglieder der eigenen Klasse, eigene
// Unit), mit kurzer Beschreibung. Mit "atlasLocals": true in der Anfrage
// (Plugin) gelten nur lokale Bezeichner, Methoden und Routinen also nicht.

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
  /// <summary>Name, der beim Umbenennen eines lokalen Bezeichners mit einer sichtbaren Deklaration
  /// zusammenstieße (#658).</summary>
  TLinkedConflict = record
    Name: string;
    /// <summary>Wie TNameResolver.ShadowText, z. B. "Feld TKunde.Total".</summary>
    Detail: string;
  end;

  TLspLinkedEditing = class
  public const
    Method = 'textDocument/linkedEditingRange';
    /// <summary>Gültige Bezeichner, damit der Client die Verknüpfung bei anderen Zeichen löst.</summary>
    WordPattern = '[A-Za-z_][A-Za-z0-9_]*';
    /// <summary>So viele Stellen (Deklaration und Vorkommen) prüft LocalRanges auf sichtbare Namen.</summary>
    ConflictProbes = 6;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function HandleLinkedEditing(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Unter TLspNamespaces gelesen und ersetzt wie bei den übrigen Anfragen (Code-Review A-03).</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    /// <summary>Nur Methoden und Routinen (#39), ohne Namensauflösung.</summary>
    constructor Create(const AStore: IDocumentStore); overload;
    /// <summary>Auch lokale Bezeichner (#658).</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Vorkommen des lokalen Bezeichners an APosition in der deklarierenden Routine, in
    /// Textreihenfolge, und die Namen, die dort schon sichtbar sind; leer, wenn an APosition kein lokaler
    /// Bezeichner (Variable, Parameter, Konstante, Inline- oder Schleifenvariable) steht.</summary>
    class function LocalRanges(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      out AConflicts: TArray<TLinkedConflict>): TArray<TTextRange>; static;
    /// <summary>Namensbereiche von Deklaration und Implementierung zum Namen an APosition; sonst leer.</summary>
    class function Ranges(ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TTextRange>; static;
    /// <summary>Antwort im Format des LSP; null ohne Bereiche.</summary>
    class function ToJson(const ARanges: TArray<TTextRange>): TJSONValue; overload; static;
    /// <summary>Wie ToJson, mit "atlasConflicts" (#658).</summary>
    class function ToJson(const ARanges: TArray<TTextRange>;
      const AConflicts: TArray<TLinkedConflict>): TJSONValue; overload; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.DocumentHighlights,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

function Contains(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (APosition.Line = ARange.StartPos.Line) and (APosition.Line = ARange.EndPos.Line) and
    (APosition.Character >= ARange.StartPos.Character) and (APosition.Character <= ARange.EndPos.Character);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

/// <summary>Bezeichner, auf oder direkt hinter dem APosition steht; -1 ohne.</summary>
function IdentifierAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if Before(APosition, Token.StartPos) then
      Break;
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      not Before(Token.EndPos, APosition) then
      Exit(Index);
  end;
  Result := -1;
end;

/// <summary>Token, das an APosition beginnt; -1 ohne.</summary>
function TokenStartingAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].StartPos = APosition then
      Exit(Index);
    if Before(APosition, ATokens[Index].StartPos) then
      Break;
  end;
  Result := -1;
end;

/// <summary>Innerste benannte oder anonyme Routine, die AOffset enthält; nil außerhalb.</summary>
function InnermostRoutine(ARoot: TSyntaxNode; AOffset: Integer): TSyntaxNode;
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
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          Result := Node;
        Descended := True;
        Break;
      end;
    end;
  until not Descended;
end;

{ TLspLinkedEditing }

constructor TLspLinkedEditing.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

constructor TLspLinkedEditing.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  Create(AStore);
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

function TLspLinkedEditing.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspLinkedEditing.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

procedure TLspLinkedEditing.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleLinkedEditing);
end;

class function TLspLinkedEditing.Ranges(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TTextRange>;
var
  UnitIndex: TUnitIndex;
  Symbol, Target: TIndexSymbol;
begin
  Result := nil;
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  Target := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in RoutineKinds) and Contains(Symbol.SelectionRange, APosition) then
    begin
      Target := Symbol;
      Break;
    end;
  if Target.Name = '' then
    Exit;
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = Target.Kind) and SameText(Symbol.Name, Target.Name) and
      SameText(Symbol.Container, Target.Container) then
      Result := Result + [Symbol.SelectionRange];
  if Length(Result) <> 2 then
    Result := nil;
end;

class function TLspLinkedEditing.LocalRanges(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AConflicts: TArray<TLinkedConflict>): TArray<TTextRange>;
var
  Tokens: TArray<TPascalToken>;
  Index, Declaration, Probe: Integer;
  Symbol, Candidate: TResolvedSymbol;
  Routine: TSyntaxNode;
  Highlight: TDocumentHighlight;
  Found: TList<TTextRange>;
  Offsets: TList<Integer>;
  Conflicts: TList<TLinkedConflict>;
  Seen: TDictionary<string, Boolean>;
  Conflict: TLinkedConflict;
begin
  Result := nil;
  AConflicts := nil;
  Tokens := ATree.Tokens;
  Index := IdentifierAt(Tokens, APosition);
  if Index < 0 then
    Exit;
  Found := TList<TTextRange>.Create;
  Offsets := TList<Integer>.Create;
  Conflicts := TList<TLinkedConflict>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  AResolver.PinTree(ATree, AFileName);
  try
    Symbol := AResolver.Resolve(ATree, AFileName, Tokens[Index].StartPos);
    // Result gehört zur Funktion, lokale Typen und Routinen bleiben beim Umbenennen über den Server (#30).
    if (Symbol.Kind <> TResolvedKind.Local) or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Constant]) or
      SameText(Symbol.Name, 'Result') or not SameText(Symbol.FileName, AFileName) then
      Exit;
    Declaration := TokenStartingAt(Tokens, Symbol.SelectionRange.StartPos);
    if Declaration < 0 then
      Exit;
    Routine := InnermostRoutine(ATree.Root, Tokens[Declaration].Offset);
    if Routine = nil then
      Exit;
    Offsets.Add(Tokens[Declaration].Offset);
    for Highlight in TLspDocumentHighlights.Highlights(AResolver, AIndex, ATree, AFileName, Tokens[Index].StartPos) do
      if not Before(Highlight.Range.StartPos, Routine.StartPos) and not Before(Routine.EndPos, Highlight.Range.EndPos)
      then
      begin
        Found.Add(Highlight.Range);
        Probe := TokenStartingAt(Tokens, Highlight.Range.StartPos);
        if (Probe >= 0) and (Offsets.Count < ConflictProbes) and (Probe <> Declaration) then
          Offsets.Add(Tokens[Probe].Offset);
      end;
    if Found.Count = 0 then
      Exit;
    Result := Found.ToArray;
    // Gleichnamige zählen nicht: Ohne neuen Namen gibt es keinen Konflikt.
    Seen.Add(LowerCase(Symbol.Name), True);
    for Probe in Offsets do
      for Candidate in AResolver.OwnScopeCandidates(ATree, AFileName, Probe) do
        if not Seen.ContainsKey(LowerCase(Candidate.Name)) then
        begin
          Seen.Add(LowerCase(Candidate.Name), True);
          Conflict.Name := Candidate.Name;
          Conflict.Detail := TNameResolver.ShadowText(Candidate);
          Conflicts.Add(Conflict);
        end;
    AConflicts := Conflicts.ToArray;
  finally
    AResolver.UnpinTree;
    Seen.Free;
    Conflicts.Free;
    Offsets.Free;
    Found.Free;
  end;
end;

class function TLspLinkedEditing.ToJson(const ARanges: TArray<TTextRange>): TJSONValue;
var
  Items: TJSONArray;
  Range: TTextRange;
  Answer: TJSONObject;
begin
  if Length(ARanges) = 0 then
    Exit(TJSONNull.Create);
  Answer := TJSONObject.Create;
  Items := TJSONArray.Create;
  Answer.AddPair('ranges', Items);
  for Range in ARanges do
    Items.AddElement(TLspPositions.RangeToJson(Range));
  Answer.AddPair('wordPattern', WordPattern);
  Result := Answer;
end;

class function TLspLinkedEditing.ToJson(const ARanges: TArray<TTextRange>;
  const AConflicts: TArray<TLinkedConflict>): TJSONValue;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Conflict: TLinkedConflict;
begin
  Result := ToJson(ARanges);
  if not (Result is TJSONObject) then
    Exit;
  Items := TJSONArray.Create;
  TJSONObject(Result).AddPair('atlasConflicts', Items);
  for Conflict in AConflicts do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Conflict.Name);
    Item.AddPair('detail', Conflict.Detail);
    Items.AddElement(Item);
  end;
end;

function TLspLinkedEditing.HandleLinkedEditing(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Found: TArray<TTextRange>;
  Conflicts: TArray<TLinkedConflict>;
  Resolver: TNameResolver;
  LocalsOnly: Boolean;
  Position: TTextPosition;
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
  Position := TLspPositions.ReadPosition(PositionValue);
  if not TJSONObject(AParams).TryGetValue<Boolean>('atlasLocals', LocalsOnly) then
    LocalsOnly := False;
  // Erst lokale Bezeichner (#658), dann Methoden und Routinen (#39).
  if FIndex <> nil then
  begin
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := Namespaces;
      Found := LocalRanges(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), Position, Conflicts);
    finally
      Resolver.Free;
    end;
    if Length(Found) > 0 then
      Exit(ToJson(Found, Conflicts));
  end;
  if LocalsOnly then
    Exit(TJSONNull.Create);
  Found := Ranges(Tree, TDocumentUris.ToPath(Uri), Position);
  Result := ToJson(Found);
end;

end.
