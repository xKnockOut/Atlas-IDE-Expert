unit Atlas.Common.Lsp.Implementations;

// Gehe zu Implementierung (textDocument/implementation):
//   - bei virtuellen, abstrakten und Interface-Methoden alle Rümpfe in den Nachfahren
//     (bei Klassenmethoden mit Rumpf auch den eigenen),
//   - bei Klassen und Interfaces alle Nachfahren bzw. implementierenden Klassen,
//   - auf "inherited" den Rumpf der aufgerufenen Methode im Vorfahren
//     (bei "inherited;" ohne Namen die gleichnamige Methode).

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
  Atlas.Common.Lsp.Definition;

type
  TLspImplementations = class
  public const
    cMethod = 'textDocument/implementation';
    cMaxTargets = 500;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Sprungziele für das Symbol bzw. das inherited an APosition.</summary>
    class function Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
    /// <summary>Alle Nachfahren von ATypeName über alle Stufen, Kreise erkannt (auch für die Zeilenleiste #768).
    /// </summary>
    class function AllDescendantsOf(const AIndex: ISymbolIndex; const ATypeName: string): TArray<TSymbolLocation>;
      static;
    /// <summary>Ist ATypeName (qualifiziert oder kurz) im Index ein Interface?</summary>
    class function IsInterfaceType(const AIndex: ISymbolIndex; const ATypeName: string): Boolean; static;
    /// <summary>Umsetzungen der Methode AName von AContainer, die ein Aufruf erreichen kann (#1122): bei einem
    /// Interface die Klassen, die es umsetzen (auch über Vorfahren), sonst die Methode selbst und jede
    /// Nachfahrenklasse, die sie neu deklariert. 0 ohne Index.</summary>
    class function ImplementationCount(const AIndex: ISymbolIndex; const AContainer, AName: string;
      AInterface: Boolean): Integer; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TImplementationsText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TImplementationsText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'));

{$SCOPEDENUMS OFF}

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  cMaxDepth = 32;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

function Within(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) <= 0);
end;

function Target(const AFileName: string; const ARange, ASelection: TTextRange): TDefinitionTarget;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.SelectionRange := ASelection;
end;

function OwnerUnitOf(const AIndex: ISymbolIndex; ATree: TSyntaxTree; const ACurrentFile, AFileName: string;
  out AUnit: TUnitIndex): Boolean;
begin
  // Die eigene Datei aus dem Editor, nicht aus dem Index.
  if SameText(AFileName, ACurrentFile) then
  begin
    AUnit := TIndexExtractor.Extract(ATree, ACurrentFile);
    Exit(True);
  end;
  Result := AIndex.FindFile(AFileName, AUnit);
end;

/// <summary>Rumpf der Routine AName in AContainer: die letzte Fundstelle, wenn es mehr als eine gibt.</summary>
function FindBody(const AUnit: TUnitIndex; const AContainer, AName: string; out ABody: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
  mCount: Integer;
begin
  mCount := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AContainer) and
      SameText(mSymbol.Name, AName) then
    begin
      ABody := mSymbol;
      Inc(mCount);
    end;
  end;
  Result := mCount >= 2;
end;

/// <summary>Alle Nachfahren von ATypeName, auch über mehrere Stufen; Kreise werden erkannt.</summary>
function AllDescendants(const AIndex: ISymbolIndex; const ATypeName: string): TArray<TSymbolLocation>;
var
  mPending: TQueue<TPair<string, Integer>>;
  mSeen: TDictionary<string, Boolean>;
  mCurrent: TPair<string, Integer>;
  mLocation: TSymbolLocation;
  mKey: string;
begin
  Result := nil;
  mPending := TQueue<TPair<string, Integer>>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mPending.Enqueue(TPair<string, Integer>.Create(ATypeName, 0));
    while mPending.Count > 0 do
    begin
      mCurrent := mPending.Dequeue;
      if mCurrent.Value >= cMaxDepth then
      begin
        Continue;
      end;
      for mLocation in AIndex.Descendants(mCurrent.Key) do
      begin
        if not (mLocation.Symbol.Kind in cTypeKinds) then
        begin
          Continue;
        end;
        mKey := UpperCase(mLocation.FileName + '|' + mLocation.Symbol.QualifiedName);
        if mSeen.ContainsKey(mKey) then
        begin
          Continue;
        end;
        mSeen.Add(mKey, True);
        Result := Result + [mLocation];
        mPending.Enqueue(TPair<string, Integer>.Create(mLocation.Symbol.QualifiedName, mCurrent.Value + 1));
      end;
    end;
  finally
    mSeen.Free;
    mPending.Free;
  end;
end;

function TokenIndexAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if ComparePositions(ATokens[mIndex].StartPos, APosition) > 0 then
    begin
      Break;
    end;
    if ComparePositions(APosition, ATokens[mIndex].EndPos) <= 0 then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function EnclosingRoutineName(ANode: TSyntaxNode; AOffset: Integer): string;
var
  mIndex: Integer;
  mNode, mChild: TSyntaxNode;
begin
  // Äußerste Routine: bei verschachtelten Routinen gilt die Methode. Schleife statt Rekursion:
  // dem ersten Kind folgen, das AOffset enthält.
  mNode := ANode;
  while mNode <> nil do
  begin
    mChild := nil;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if (mNode[mIndex].StartOffset <= AOffset) and (AOffset <= mNode[mIndex].EndOffset) then
      begin
        mChild := mNode[mIndex];
        Break;
      end;
    end;
    if (mChild <> nil) and (mChild.Kind = TSyntaxKind.RoutineDecl) then
    begin
      Exit(mChild.Name);
    end;
    mNode := mChild;
  end;
  Result := '';
end;

function InheritedTargets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; ATokenIndex: Integer): TArray<TDefinitionTarget>;
var
  mTokens: TArray<TPascalToken>;
  mNext: Integer;
  mName: string;
  mResolved: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mBody: TIndexSymbol;
begin
  Result := nil;
  mTokens := ATree.Tokens;
  mNext := ATokenIndex + 1;
  while (mNext <= High(mTokens)) and (mTokens[mNext].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(mNext);
  end;
  if (mNext <= High(mTokens)) and (mTokens[mNext].Kind = TPascalTokenKind.Identifier) then
  begin
    // inherited Create(...): wie Gehe zu Definition auf dem Namen.
    Exit(TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, mTokens[mNext].StartPos, False));
  end;
  // inherited; → gleichnamige Methode im Vorfahren.
  mName := EnclosingRoutineName(ATree.Root, mTokens[ATokenIndex].Offset);
  if mName = '' then
  begin
    Exit;
  end;
  mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  mResolved := AResolver.ResolveChain(ATree, AFileName, [mName], mTokens[ATokenIndex].Offset, True);
  if not mResolved.Found then
  begin
    Exit;
  end;
  Result := [Target(mResolved.FileName, mResolved.Range, mResolved.SelectionRange)];
  if OwnerUnitOf(AIndex, ATree, AFileName, mResolved.FileName, mOwnerUnit) and
    FindBody(mOwnerUnit, mResolved.Container, mResolved.Name, mBody) then
  begin
    Result := [Target(mOwnerUnit.FileName, mBody.Range, mBody.SelectionRange)];
  end;
end;

{ TLspImplementations }

function TLspImplementations.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspImplementations.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspImplementations.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspImplementations.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

class function TLspImplementations.AllDescendantsOf(const AIndex: ISymbolIndex;
  const ATypeName: string): TArray<TSymbolLocation>;
begin
  Result := AllDescendants(AIndex, ATypeName);
end;

class function TLspImplementations.IsInterfaceType(const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
var
  mLocation: TSymbolLocation;
  mShort: string;
begin
  Result := False;
  if AIndex = nil then
  begin
    Exit;
  end;
  mShort := ATypeName;
  if mShort.LastIndexOf('.') >= 0 then
  begin
    mShort := Copy(mShort, mShort.LastIndexOf('.') + 2, MaxInt);
  end;
  for mLocation in AIndex.FindSymbols(mShort) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.InterfaceType) and
      (SameText(mLocation.Symbol.QualifiedName, ATypeName) or SameText(mLocation.Symbol.Name, ATypeName)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TLspImplementations.ImplementationCount(const AIndex: ISymbolIndex; const AContainer, AName: string;
  AInterface: Boolean): Integer;
var
  mLocation: TSymbolLocation;
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := 0;
  if AIndex = nil then
  begin
    Exit;
  end;
  // Eine virtuelle Methode ist selbst ein mögliches Ziel; ein Interface hat keinen Rumpf.
  if not AInterface then
  begin
    Result := 1;
  end;
  for mLocation in AllDescendants(AIndex, AContainer) do
  begin
    if not (mLocation.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType]) then
    begin
      Continue;
    end;
    if AInterface then
    begin
      Inc(Result);
      Continue;
    end;
    if not AIndex.FindFile(mLocation.FileName, mOwner) then
    begin
      Continue;
    end;
    for mSymbol in mOwner.Symbols do
    begin
      if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, mLocation.Symbol.QualifiedName) and
        SameText(mSymbol.Name, AName) then
      begin
        Inc(Result);
        Break;
      end;
    end;
  end;
end;

procedure TLspImplementations.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, Handle);
end;

/// <summary>Ist AResolved nicht aufgelöst und steht APosition auf dem Namen einer Deklaration (Methode in der
/// Klasse, Typname), wird AResolved zu dieser Deklaration.</summary>
procedure ResolveDeclaration(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  var AResolved: TResolvedSymbol);
var
  mSymbol: TIndexSymbol;
begin
  if AResolved.Kind <> TResolvedKind.None then
  begin
    Exit;
  end;
  for mSymbol in TIndexExtractor.Extract(ATree, AFileName).Symbols do
  begin
    if Within(APosition, mSymbol.SelectionRange) then
    begin
      AResolved.Kind := TResolvedKind.Symbol;
      AResolved.Name := mSymbol.Name;
      AResolved.Container := mSymbol.Container;
      AResolved.SymbolKind := mSymbol.Kind;
      AResolved.FileName := AFileName;
      AResolved.Range := mSymbol.Range;
      AResolved.SelectionRange := mSymbol.SelectionRange;
      Exit;
    end;
  end;
end;

/// <summary>Erste Deklaration der Routine AName in AContainer.</summary>
function FindDeclaration(const AUnit: TUnitIndex; const AContainer, AName: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AContainer) and
      SameText(mSymbol.Name, AName) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Rumpf der Routine AName im Nachfahren ATypeName, sonst ihre Deklaration (z. B. abstrakt wiederholt).
/// </summary>
procedure AddDescendantTarget(AList: TList<TDefinitionTarget>; const AUnit: TUnitIndex;
  const ATypeName, AName: string);
var
  mSymbol: TIndexSymbol;
begin
  if FindBody(AUnit, ATypeName, AName, mSymbol) or FindDeclaration(AUnit, ATypeName, AName, mSymbol) then
  begin
    AList.Add(Target(AUnit.FileName, mSymbol.Range, mSymbol.SelectionRange));
  end;
end;

/// <summary>Ziele der Methode AResolved: ihr eigener Rumpf und die Überschreibungen in den Nachfahren.</summary>
procedure AddMethodTargets(AList: TList<TDefinitionTarget>; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AResolved: TResolvedSymbol);
var
  mBody: TIndexSymbol;
  mOwnerUnit, mDescendantUnit: TUnitIndex;
  mLocation: TSymbolLocation;
begin
  // Eigener Rumpf (fehlt bei abstrakten und Interface-Methoden).
  if OwnerUnitOf(AIndex, ATree, AFileName, AResolved.FileName, mOwnerUnit) and
    FindBody(mOwnerUnit, AResolved.Container, AResolved.Name, mBody) then
  begin
    AList.Add(Target(mOwnerUnit.FileName, mBody.Range, mBody.SelectionRange));
  end;
  for mLocation in AllDescendants(AIndex, AResolved.Container) do
  begin
    if AList.Count >= TLspImplementations.cMaxTargets then
    begin
      Break;
    end;
    if OwnerUnitOf(AIndex, ATree, AFileName, mLocation.FileName, mDescendantUnit) then
    begin
      AddDescendantTarget(AList, mDescendantUnit, mLocation.Symbol.QualifiedName, AResolved.Name);
    end;
  end;
end;

/// <summary>Ziele zu AResolved: Nachfahren eines Typs bzw. Rümpfe einer Methode.</summary>
procedure AddTargets(AList: TList<TDefinitionTarget>; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AResolved: TResolvedSymbol);
var
  mLocation: TSymbolLocation;
begin
  if AResolved.SymbolKind in cTypeKinds then
  begin
    for mLocation in AllDescendants(AIndex, AResolved.QualifiedName) do
    begin
      AList.Add(Target(mLocation.FileName, mLocation.Symbol.Range, mLocation.Symbol.SelectionRange));
    end;
  end
  else if (AResolved.SymbolKind in cRoutineKinds) and (AResolved.Container <> '') then
  begin
    AddMethodTargets(AList, AIndex, ATree, AFileName, AResolved);
  end;
end;

class function TLspImplementations.Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  mTokenIndex: Integer;
  mResolved: TResolvedSymbol;
  mList: TList<TDefinitionTarget>;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mTokenIndex := TokenIndexAt(ATree.Tokens, APosition);
  if (mTokenIndex >= 0) and ATree.Tokens[mTokenIndex].IsKeyword('inherited') then
  begin
    Exit(InheritedTargets(AResolver, AIndex, ATree, AFileName, mTokenIndex));
  end;
  mResolved := AResolver.Resolve(ATree, AFileName, APosition);
  ResolveDeclaration(ATree, AFileName, APosition, mResolved);
  if mResolved.Kind <> TResolvedKind.Symbol then
  begin
    Exit;
  end;
  mList := TList<TDefinitionTarget>.Create;
  try
    AddTargets(mList, AIndex, ATree, AFileName, mResolved);
    if mList.Count > cMaxTargets then
    begin
      mList.Count := cMaxTargets;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TLspImplementations.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TImplementationsText.FieldsTextDocumentUriAndPosition].Text);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    Result := TLspDefinition.ToJson(Targets(mResolver, FIndex, mTree, TDocumentUris.ToPath(mUri),
      TLspPositions.ReadPosition(mPositionValue)));
  finally
    mResolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Implementations', cTexts);

end.
