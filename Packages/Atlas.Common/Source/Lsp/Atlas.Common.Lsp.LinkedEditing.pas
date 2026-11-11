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
    cMethod = 'textDocument/linkedEditingRange';
    /// <summary>Gültige Bezeichner, damit der Client die Verknüpfung bei anderen Zeichen löst.</summary>
    cWordPattern = '[A-Za-z_][A-Za-z0-9_]*';
    /// <summary>So viele Stellen (Deklaration und Vorkommen) prüft LocalRanges auf sichtbare Namen.</summary>
    cConflictProbes = 6;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function HandleLinkedEditing(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Unter TLspNamespaces gelesen und ersetzt wie bei den übrigen Anfragen.</summary>
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
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLinkedEditingText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TLinkedEditingText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '));

{$SCOPEDENUMS OFF}

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

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
  mIndex: Integer;
  mToken: TPascalToken;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if Before(APosition, mToken.StartPos) then
    begin
      Break;
    end;
    if (mToken.Kind = TPascalTokenKind.Identifier) and (mToken.EndPos.Line = APosition.Line) and
      not Before(mToken.EndPos, APosition) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Token, das an APosition beginnt; -1 ohne.</summary>
function TokenStartingAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].StartPos = APosition then
    begin
      Exit(mIndex);
    end;
    if Before(APosition, ATokens[mIndex].StartPos) then
    begin
      Break;
    end;
  end;
  Result := -1;
end;

/// <summary>Innerste benannte oder anonyme Routine, die AOffset enthält; nil außerhalb.</summary>
function InnermostRoutine(ARoot: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mNode, mChild: TSyntaxNode;
  mIndex: Integer;
  mDescended: Boolean;
begin
  Result := nil;
  mNode := ARoot;
  repeat
    mDescended := False;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      mChild := mNode[mIndex];
      if (mChild.StartOffset <= AOffset) and (AOffset < mChild.EndOffset) then
      begin
        mNode := mChild;
        if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Result := mNode;
        end;
        mDescended := True;
        Break;
      end;
    end;
  until not mDescended;
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
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleLinkedEditing);
end;

class function TLspLinkedEditing.Ranges(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TTextRange>;
var
  mUnitIndex: TUnitIndex;
  mSymbol, mTarget: TIndexSymbol;
begin
  Result := nil;
  mUnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  mTarget := Default(TIndexSymbol);
  for mSymbol in mUnitIndex.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and Contains(mSymbol.SelectionRange, APosition) then
    begin
      mTarget := mSymbol;
      Break;
    end;
  end;
  if mTarget.Name = '' then
  begin
    Exit;
  end;
  for mSymbol in mUnitIndex.Symbols do
  begin
    if (mSymbol.Kind = mTarget.Kind) and SameText(mSymbol.Name, mTarget.Name) and
      SameText(mSymbol.Container, mTarget.Container) then
    begin
      Result := Result + [mSymbol.SelectionRange];
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
  mHighlight: TDocumentHighlight;
begin
  Result := nil;
  for mHighlight in AHighlights do
  begin
    if not Before(mHighlight.Range.StartPos, ARoutine.StartPos) and not Before(ARoutine.EndPos, mHighlight.Range.EndPos)
    then
    begin
      Result := Result + [mHighlight.Range];
    end;
  end;
end;

/// <summary>Offsets, an denen sichtbare Namen geprüft werden: die Deklaration ADeclaration, dann Vorkommen aus
/// ARanges bis ConflictProbes.</summary>
function ProbeOffsets(const ATokens: TArray<TPascalToken>; const ARanges: TArray<TTextRange>;
  ADeclaration: Integer): TArray<Integer>;
var
  mRange: TTextRange;
  mProbe: Integer;
begin
  Result := [ATokens[ADeclaration].Offset];
  for mRange in ARanges do
  begin
    mProbe := TokenStartingAt(ATokens, mRange.StartPos);
    if (mProbe >= 0) and (Length(Result) < TLspLinkedEditing.cConflictProbes) and (mProbe <> ADeclaration) then
    begin
      Result := Result + [ATokens[mProbe].Offset];
    end;
  end;
end;

/// <summary>Namen, die an AOffsets sichtbar sind, ohne AName selbst: Ohne neuen Namen gibt es keinen Konflikt.
/// </summary>
function ScopeConflicts(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AName: string;
  const AOffsets: TArray<Integer>): TArray<TLinkedConflict>;
var
  mSeen: TDictionary<string, Boolean>;
  mCandidate: TResolvedSymbol;
  mConflict: TLinkedConflict;
  mProbe: Integer;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mSeen.Add(LowerCase(AName), True);
    for mProbe in AOffsets do
    begin
      for mCandidate in AResolver.Candidates.OwnScopeCandidates(ATree, AFileName, mProbe) do
      begin
        if not mSeen.ContainsKey(LowerCase(mCandidate.Name)) then
        begin
          mSeen.Add(LowerCase(mCandidate.Name), True);
          mConflict.Name := mCandidate.Name;
          mConflict.Detail := mCandidate.ShadowText;
          Result := Result + [mConflict];
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

class function TLspLinkedEditing.LocalRanges(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AConflicts: TArray<TLinkedConflict>): TArray<TTextRange>;
var
  mIndex, mDeclaration: Integer;
  mSymbol: TResolvedSymbol;
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  AConflicts := nil;
  mIndex := IdentifierAt(ATree.Tokens, APosition);
  if mIndex < 0 then
  begin
    Exit;
  end;
  AResolver.PinTree(ATree, AFileName);
  try
    mSymbol := AResolver.Resolve(ATree, AFileName, ATree.Tokens[mIndex].StartPos);
    if IsLinkableLocal(mSymbol, AFileName) and DeclarationRoutine(ATree, mSymbol, mDeclaration, mRoutine) then
    begin
      Result := RangesIn(TLspDocumentHighlights.Highlights(AResolver, AIndex, ATree, AFileName,
        ATree.Tokens[mIndex].StartPos), mRoutine);
    end;
    if Result <> nil then
    begin
      AConflicts := ScopeConflicts(AResolver, ATree, AFileName, mSymbol.Name, ProbeOffsets(ATree.Tokens, Result,
        mDeclaration));
    end;
  finally
    AResolver.UnpinTree;
  end;
end;

class function TLspLinkedEditing.ToJson(const ARanges: TArray<TTextRange>): TJSONValue;
var
  mItems: TJSONArray;
  mRange: TTextRange;
  mAnswer: TJSONObject;
begin
  if Length(ARanges) = 0 then
  begin
    Exit(TJSONNull.Create);
  end;
  mAnswer := TJSONObject.Create;
  mItems := TJSONArray.Create;
  mAnswer.AddPair('ranges', mItems);
  for mRange in ARanges do
  begin
    mItems.AddElement(TLspPositions.RangeToJson(mRange));
  end;
  mAnswer.AddPair('wordPattern', cWordPattern);
  Result := mAnswer;
end;

class function TLspLinkedEditing.ToJson(const ARanges: TArray<TTextRange>;
  const AConflicts: TArray<TLinkedConflict>): TJSONValue;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mConflict: TLinkedConflict;
begin
  Result := ToJson(ARanges);
  if not (Result is TJSONObject) then
  begin
    Exit;
  end;
  mItems := TJSONArray.Create;
  TJSONObject(Result).AddPair('atlasConflicts', mItems);
  for mConflict in AConflicts do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mConflict.Name);
    mItem.AddPair('detail', mConflict.Detail);
    mItems.AddElement(mItem);
  end;
end;

function TLspLinkedEditing.HandleLinkedEditing(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mFound: TArray<TTextRange>;
  mConflicts: TArray<TLinkedConflict>;
  mResolver: TNameResolver;
  mLocalsOnly: Boolean;
  mPosition: TTextPosition;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLinkedEditingText.FieldsTextDocumentUriAndPosition].Text + cMethod);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  mPosition := TLspPositions.ReadPosition(mPositionValue);
  if not TJSONObject(AParams).TryGetValue<Boolean>('atlasLocals', mLocalsOnly) then
  begin
    mLocalsOnly := False;
  end;
  // Erst lokale Bezeichner (#658), dann Methoden und Routinen (#39).
  if FIndex <> nil then
  begin
    mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      mResolver.Namespaces := Namespaces;
      mFound := LocalRanges(mResolver, FIndex, mTree, TDocumentUris.ToPath(mUri), mPosition, mConflicts);
    finally
      mResolver.Free;
    end;
    if Length(mFound) > 0 then
    begin
      Exit(ToJson(mFound, mConflicts));
    end;
  end;
  if mLocalsOnly then
  begin
    Exit(TJSONNull.Create);
  end;
  mFound := Ranges(mTree, TDocumentUris.ToPath(mUri), mPosition);
  Result := ToJson(mFound);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.LinkedEditing', cTexts);

end.
