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
    /// <summary>Wie TResolvedSymbol.ShadowText, z. B. "Feld TKunde.Total".</summary>
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
    begin
      Break;
    end;
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      not Before(Token.EndPos, APosition) then
    begin
      Exit(Index);
    end;
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
    begin
      Exit(Index);
    end;
    if Before(APosition, ATokens[Index].StartPos) then
    begin
      Break;
    end;
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
        begin
          Result := Node;
        end;
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
  begin
    if (Symbol.Kind in RoutineKinds) and Contains(Symbol.SelectionRange, APosition) then
    begin
      Target := Symbol;
      Break;
    end;
  end;
  if Target.Name = '' then
  begin
    Exit;
  end;
  for Symbol in UnitIndex.Symbols do
  begin
    if (Symbol.Kind = Target.Kind) and SameText(Symbol.Name, Target.Name) and
      SameText(Symbol.Container, Target.Container) then
    begin
      Result := Result + [Symbol.SelectionRange];
    end;
  end;
  if Length(Result) <> 2 then
  begin
    Result := nil;
  end;
end;

/// <summary>Lokale Variable oder Konstante der Datei AFileName, die man verknüpft umbenennen kann. Result gehört
/// zur Funktion, lokale Typen und Routinen bleiben beim Umbenennen über den Server (#30).</summary>
function IsLinkableLocal(const ASymbol: TResolvedSymbol; const AFileName: string): Boolean;
begin
  Result := (ASymbol.Kind = TResolvedKind.Local) and
    (ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Constant]) and
    not SameText(ASymbol.Name, 'Result') and SameText(ASymbol.FileName, AFileName);
end;

/// <summary>Token der Deklaration von ASymbol und die innerste Routine darum; False ohne eine.</summary>
function DeclarationRoutine(ATree: TSyntaxTree; const ASymbol: TResolvedSymbol; out ADeclaration: Integer;
  out ARoutine: TSyntaxNode): Boolean;
begin
  ARoutine := nil;
  ADeclaration := TokenStartingAt(ATree.Tokens, ASymbol.SelectionRange.StartPos);
  if ADeclaration >= 0 then
  begin
    ARoutine := InnermostRoutine(ATree.Root, ATree.Tokens[ADeclaration].Offset);
  end;
  Result := ARoutine <> nil;
end;

/// <summary>Stellen aus AHighlights innerhalb von ARoutine.</summary>
function RangesIn(const AHighlights: TArray<TDocumentHighlight>; ARoutine: TSyntaxNode): TArray<TTextRange>;
var
  Highlight: TDocumentHighlight;
begin
  Result := nil;
  for Highlight in AHighlights do
  begin
    if not Before(Highlight.Range.StartPos, ARoutine.StartPos) and not Before(ARoutine.EndPos, Highlight.Range.EndPos)
    then
    begin
      Result := Result + [Highlight.Range];
    end;
  end;
end;

/// <summary>Offsets, an denen sichtbare Namen geprüft werden: die Deklaration ADeclaration, dann Vorkommen aus
/// ARanges bis ConflictProbes.</summary>
function ProbeOffsets(const ATokens: TArray<TPascalToken>; const ARanges: TArray<TTextRange>;
  ADeclaration: Integer): TArray<Integer>;
var
  Range: TTextRange;
  Probe: Integer;
begin
  Result := [ATokens[ADeclaration].Offset];
  for Range in ARanges do
  begin
    Probe := TokenStartingAt(ATokens, Range.StartPos);
    if (Probe >= 0) and (Length(Result) < TLspLinkedEditing.ConflictProbes) and (Probe <> ADeclaration) then
    begin
      Result := Result + [ATokens[Probe].Offset];
    end;
  end;
end;

/// <summary>Namen, die an AOffsets sichtbar sind, ohne AName selbst: Ohne neuen Namen gibt es keinen Konflikt.
/// </summary>
function ScopeConflicts(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AName: string;
  const AOffsets: TArray<Integer>): TArray<TLinkedConflict>;
var
  Seen: TDictionary<string, Boolean>;
  Candidate: TResolvedSymbol;
  Conflict: TLinkedConflict;
  Probe: Integer;
begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Seen.Add(LowerCase(AName), True);
    for Probe in AOffsets do
    begin
      for Candidate in AResolver.Candidates.OwnScopeCandidates(ATree, AFileName, Probe) do
      begin
        if not Seen.ContainsKey(LowerCase(Candidate.Name)) then
        begin
          Seen.Add(LowerCase(Candidate.Name), True);
          Conflict.Name := Candidate.Name;
          Conflict.Detail := Candidate.ShadowText;
          Result := Result + [Conflict];
        end;
      end;
    end;
  finally
    Seen.Free;
  end;
end;

class function TLspLinkedEditing.LocalRanges(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AConflicts: TArray<TLinkedConflict>): TArray<TTextRange>;
var
  Index, Declaration: Integer;
  Symbol: TResolvedSymbol;
  Routine: TSyntaxNode;
begin
  Result := nil;
  AConflicts := nil;
  Index := IdentifierAt(ATree.Tokens, APosition);
  if Index < 0 then
  begin
    Exit;
  end;
  AResolver.PinTree(ATree, AFileName);
  try
    Symbol := AResolver.Resolve(ATree, AFileName, ATree.Tokens[Index].StartPos);
    if IsLinkableLocal(Symbol, AFileName) and DeclarationRoutine(ATree, Symbol, Declaration, Routine) then
    begin
      Result := RangesIn(TLspDocumentHighlights.Highlights(AResolver, AIndex, ATree, AFileName,
        ATree.Tokens[Index].StartPos), Routine);
    end;
    if Result <> nil then
    begin
      AConflicts := ScopeConflicts(AResolver, ATree, AFileName, Symbol.Name, ProbeOffsets(ATree.Tokens, Result,
        Declaration));
    end;
  finally
    AResolver.UnpinTree;
  end;
end;

class function TLspLinkedEditing.ToJson(const ARanges: TArray<TTextRange>): TJSONValue;
var
  Items: TJSONArray;
  Range: TTextRange;
  Answer: TJSONObject;
begin
  if Length(ARanges) = 0 then
  begin
    Exit(TJSONNull.Create);
  end;
  Answer := TJSONObject.Create;
  Items := TJSONArray.Create;
  Answer.AddPair('ranges', Items);
  for Range in ARanges do
  begin
    Items.AddElement(TLspPositions.RangeToJson(Range));
  end;
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
  begin
    Exit;
  end;
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
  Position := TLspPositions.ReadPosition(PositionValue);
  if not TJSONObject(AParams).TryGetValue<Boolean>('atlasLocals', LocalsOnly) then
  begin
    LocalsOnly := False;
  end;
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
    begin
      Exit(ToJson(Found, Conflicts));
    end;
  end;
  if LocalsOnly then
  begin
    Exit(TJSONNull.Create);
  end;
  Found := Ranges(Tree, TDocumentUris.ToPath(Uri), Position);
  Result := ToJson(Found);
end;

end.
