unit Atlas.Common.Lsp.References;

// Referenzsuche (textDocument/references, #29): alle Stellen im Projekt, die
// zur selben Deklaration auflösen wie der Bezeichner unter dem Cursor.
//
// Durchsucht werden die Projektdateien und die geöffneten Dokumente; Dateien,
// in denen der Name nicht einmal als Text vorkommt, werden nicht geparst.
// Steht die Deklaration in einer Unit mit Formular, zählen auch Verweise aus
// der .dfm daneben: Ereignis-Handler (OnClick = Button1Click) und
// Komponentennamen (object Button1: TButton).

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
  TReferenceLocation = record
    FileName: string;
    Range: TTextRange;
  end;

  /// <summary>Text einer Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
  TReferenceReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Dateien des Projekts, die nach Verweisen durchsucht werden.</summary>
  TReferenceFilesProvider = reference to function: TArray<string>;

  TLspReferences = class
  public const
    Method = 'textDocument/references';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    function HandleReferences(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Stellen in ATree, die zu AWanted auflösen; AName ohne &amp;.</summary>
    class function InTree(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AName: string; const AWanted: TDefinitionTarget;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TTextRange>; static;
    /// <summary>Alle Verweise auf das Symbol an APosition; mit ADeclaration auch die Deklaration selbst.</summary>
    class function Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TReferenceLocation>; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Lsp.Internals.Cancellation;

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

/// <summary>Andere Schreibweise eines Attributnamens: Foo zu FooAttribute und umgekehrt.</summary>
function AlternativeName(const AName: string): string;
begin
  if EndsText('Attribute', AName) and (Length(AName) > Length('Attribute')) then
    Result := Copy(AName, 1, Length(AName) - Length('Attribute'))
  else
    Result := AName + 'Attribute';
end;

function SameTarget(const A, B: TDefinitionTarget): Boolean;
begin
  Result := SameText(A.FileName, B.FileName) and (A.SelectionRange.StartPos = B.SelectionRange.StartPos);
end;

/// <summary>Ereignis-Handler und Komponentennamen AName in einer Formulardatei, über das
/// Formularmodell (#267).</summary>
function InForm(const AFormText, AName: string): TArray<TTextRange>;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create(AFormText);
  try
    Result := Model.Occurrences(AName);
  finally
    Model.Free;
  end;
end;

{ TLspReferences }

function TLspReferences.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspReferences.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspReferences.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspReferences.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleReferences);
end;

class function TLspReferences.InTree(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AName: string; const AWanted: TDefinitionTarget;
  const ACancellation: IJsonRpcCancellationToken): TArray<TTextRange>;
var
  Token: TPascalToken;
  Candidate: TArray<TDefinitionTarget>;
begin
  Result := nil;
  for Token in ATree.Tokens do
  begin
    // Attribute (#119): [TestFixture] verwendet TestFixtureAttribute.
    if (Token.Kind <> TPascalTokenKind.Identifier) or not (SameText(CleanName(Token.Text), AName) or
      SameText(CleanName(Token.Text), AlternativeName(AName))) then
      Continue;
    if ACancellation <> nil then
      ACancellation.ThrowIfCancellationRequested;
    Candidate := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, Token.StartPos, True);
    if (Length(Candidate) > 0) and SameTarget(Candidate[0], AWanted) then
      Result := Result + [TTextRange.Create(Token.StartPos, Token.EndPos)];
  end;
end;

class function TLspReferences.Find(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TArray<TReferenceLocation>;

  procedure Add(const AFile: string; const ARanges: TArray<TTextRange>);
  var
    Range: TTextRange;
    Location: TReferenceLocation;
  begin
    for Range in ARanges do
    begin
      Location.FileName := AFile;
      Location.Range := Range;
      Result := Result + [Location];
    end;
  end;

var
  Index: Integer;
  Name, FileName, Text, DfmName: string;
  Wanted: TArray<TDefinitionTarget>;
  Searched: TArray<string>;
  Tree: TSyntaxTree;
  Filtered: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
begin
  Result := nil;
  Index := TokenAt(ATree.Tokens, APosition);
  if Index < 0 then
    Exit;
  Wanted := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Wanted) = 0 then
    Exit;
  Name := CleanName(ATree.Tokens[Index].Text);
  Add(AFileName, InTree(AResolver, AIndex, ATree, AFileName, Name, Wanted[0], ACancellation));
  Searched := [AFileName];
  for FileName in AFiles do
  begin
    if IndexText(FileName, Searched) >= 0 then
      Continue;
    Searched := Searched + [FileName];
    // Die kürzere Schreibweise ist in der längeren enthalten.
    if not (Assigned(AReadText) and AReadText(FileName, Text)) or not (ContainsText(Text, Name) or
      ContainsText(Text, AlternativeName(Name))) then
      Continue;
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      Add(FileName, InTree(AResolver, AIndex, Tree, FileName, Name, Wanted[0], ACancellation));
    finally
      Tree.Free;
    end;
  end;
  // Formulare zur Unit der Deklaration, bei FMX samt Plattformansichten (#87).
  if Assigned(AReadText) then
  begin
    if not AReadText(Wanted[0].FileName, Text) then
      Text := '';
    for DfmName in TFormFiles.FormFiles(Wanted[0].FileName, Text) do
      if AReadText(DfmName, Text) then
        Add(DfmName, InForm(Text, Name));
  end;
  if ADeclaration then
    Exit;
  Filtered := nil;
  for Location in Result do
    if not (SameText(Location.FileName, Wanted[0].FileName) and
      (Location.Range.StartPos = Wanted[0].SelectionRange.StartPos)) then
      Filtered := Filtered + [Location];
  Result := Filtered;
end;

function TLspReferences.HandleReferences(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  IncludeDeclaration: Boolean;
  Document: ITextDocument;
  Tree, OwnTree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Text: string;
  Files: TArray<string>;
  Found: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Item: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not TJSONObject(AParams).TryGetValue<Boolean>('context.includeDeclaration', IncludeDeclaration) then
    IncludeDeclaration := True;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  OwnTree := nil;
  if FStore.TryGet(Uri, Document) then
  begin
    Shared := TSyntaxTreeCache.Get(Document, Cancellation);
    Tree := Shared.Tree;
  end
  // Nicht geöffnete Datei (Verwendungen eines Typs aus dem Atlas-Tooltip, #588): selbst lesen.
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(Uri), Text) then
  begin
    OwnTree := TSyntaxTreeCache.Parse(Text, Cancellation);
    Tree := OwnTree;
  end
  else
    Exit(TJSONNull.Create);
  try
    Files := nil;
    if Assigned(FFiles) then
      Files := FFiles();
    ACancellation.ThrowIfCancellationRequested;
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := Namespaces;
      Found := Find(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
        IncludeDeclaration, Files, FReadText, ACancellation);
    finally
      Resolver.Free;
    end;
  finally
    OwnTree.Free;
  end;
  Result := TJSONArray.Create;
  for Location in Found do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('uri', TDocumentUris.FromPath(Location.FileName));
    Item.AddPair('range', TLspPositions.RangeToJson(Location.Range));
    TJSONArray(Result).AddElement(Item);
  end;
end;

end.
