unit BDLsp.Common.Lsp.Rename;

// Umbenennen im ganzen Projekt (textDocument/prepareRename und
// textDocument/rename, #30). Grundlage ist die Referenzsuche samt .dfm.
// Umbenannt werden nur Symbole, die im Projekt oder in geöffneten Dokumenten
// deklariert sind; RTL, VCL und andere Bibliotheken bleiben unangetastet.
// Bei Komponenten eines Formulars werden automatisch benannte Ereignis-Handler
// (Button1Click) mit umbenannt (#45).

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver,
  BDLsp.Common.Lsp.References;

type
  TRenameEdit = record
    FileName: string;
    Range: TTextRange;
    NewText: string;
  end;

  TRenameCheck = record
    /// <summary>'' = umbenennbar; sonst der Grund.</summary>
    Error: string;
    /// <summary>Bereich des Namens unter dem Cursor.</summary>
    Range: TTextRange;
    Name: string;
    /// <summary>Datei mit der Deklaration.</summary>
    DeclarationFile: string;
  end;

  TLspRename = class
  public const
    PrepareMethod = 'textDocument/prepareRename';
    RenameMethod = 'textDocument/rename';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    FRenameHandlers: Boolean;
    function ProjectFiles: TArray<string>;
    function HandlePrepare(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleRename(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function Capability: TJSONObject; static;
    /// <summary>Prüft, ob das Symbol an APosition umbenannt werden darf; AFiles sind die eigenen Dateien.</summary>
    class function Check(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; const AFiles: TArray<string>): TRenameCheck; static;
    /// <summary>True für einen gültigen Bezeichner, der kein reserviertes Wort ist.</summary>
    class function IsValidName(const AName: string): Boolean; static;
    /// <summary>Alle zu ersetzenden Stellen; EJsonRpcError, wenn nicht umbenennbar.</summary>
    class function Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; const ANewName: string;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken = nil; ARenameHandlers: Boolean = True): TArray<TRenameEdit>; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Handler wie Button1Click beim Umbenennen von Button1 anpassen (Standard True).</summary>
    property RenameHandlers: Boolean read FRenameHandlers write FRenameHandlers;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.Contract,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Lsp.Definition,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Pascal.TreeCache,
  BDLsp.Common.Lsp.Internals.Cancellation,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Dfm.ComponentRename;

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
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
      Exit(Index);
  end;
  Result := -1;
end;

{ TLspRename }

constructor TLspRename.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
  FRenameHandlers := True;
end;

procedure TLspRename.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(PrepareMethod, HandlePrepare);
  ADispatcher.RegisterConcurrentRequest(RenameMethod, HandleRename);
end;

class function TLspRename.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('prepareProvider', TJSONBool.Create(True));
end;

class function TLspRename.IsValidName(const AName: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize(AName);
  // Genau ein Bezeichner ohne &-Escape; reservierte Wörter liefert der Lexer als Keyword.
  Result := (Length(Tokens) = 1) and (Tokens[0].Kind = TPascalTokenKind.Identifier) and
    (Tokens[0].Text = AName) and (AName[1] <> '&');
end;

class function TLspRename.Check(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const AFiles: TArray<string>): TRenameCheck;
var
  Index: Integer;
  Targets: TArray<TDefinitionTarget>;
begin
  Result := Default(TRenameCheck);
  Index := TokenAt(ATree.Tokens, APosition);
  if Index < 0 then
  begin
    Result.Error := 'Hier steht kein Bezeichner.';
    Exit;
  end;
  Result.Range := TTextRange.Create(ATree.Tokens[Index].StartPos, ATree.Tokens[Index].EndPos);
  Result.Name := ATree.Tokens[Index].Text;
  if StartsStr('&', Result.Name) then
    Result.Name := Copy(Result.Name, 2, MaxInt);
  Targets := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Targets) > 0 then
    Result.DeclarationFile := Targets[0].FileName;
  if Length(Targets) = 0 then
    Result.Error := Format('"%s" ist nicht bekannt.', [Result.Name])
  else if not SameText(Targets[0].FileName, AFileName) and (IndexText(Targets[0].FileName, AFiles) < 0) then
    Result.Error := Format('"%s" ist außerhalb des Projekts deklariert (%s).',
      [Result.Name, ExtractFileName(Targets[0].FileName)])
  else if (Targets[0].Range.StartPos.Line = 0) and (Targets[0].Range.StartPos.Character = 0) and
    (Targets[0].Range.EndPos = Targets[0].Range.StartPos) then
    // Unit-Namen hängen am Dateinamen; das ist eine Dateioperation.
    Result.Error := 'Units werden über den Dateinamen umbenannt.';
end;

function HandlerEdits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AChecked: TRenameCheck; const ANewName: string; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TArray<TRenameEdit>;
var
  FormText, UnitText: string;
  Renames: TArray<THandlerRename>;
  Rename: THandlerRename;
  Tree: TSyntaxTree;
  Symbols: TArray<TIndexSymbol>;
  Symbol, Handler: TIndexSymbol;
  Found, Taken: Boolean;
  Location: TReferenceLocation;
  Edit: TRenameEdit;
begin
  Result := nil;
  if AChecked.DeclarationFile = '' then
    Exit;
  if not AReadText(ChangeFileExt(AChecked.DeclarationFile, '.dfm'), FormText) and
    not AReadText(ChangeFileExt(AChecked.DeclarationFile, '.fmx'), FormText) then
    Exit;
  Renames := TDfmComponentRename.Handlers(FormText, AChecked.Name, ANewName);
  if Length(Renames) = 0 then
    Exit;
  // Die Handler stehen in der Unit des Formulars.
  if SameText(AChecked.DeclarationFile, AFileName) then
    Tree := ATree
  else
  begin
    if not AReadText(AChecked.DeclarationFile, UnitText) then
      Exit;
    Tree := TSyntaxTreeCache.Parse(UnitText);
  end;
  try
    Symbols := TIndexExtractor.Extract(Tree, AChecked.DeclarationFile).Symbols;
    for Rename in Renames do
    begin
      Found := False;
      Taken := False;
      Handler := Default(TIndexSymbol);
      for Symbol in Symbols do
        if Symbol.Kind = TIndexSymbolKind.Method then
          if SameText(Symbol.Name, Rename.OldName) and not Found then
          begin
            Handler := Symbol;
            Found := True;
          end
          else if SameText(Symbol.Name, Rename.NewName) then
            Taken := True;
      // Ein vorhandener Handler mit dem neuen Namen würde doppelt deklariert.
      if not Found or Taken then
        Continue;
      for Location in TLspReferences.Find(AResolver, AIndex, Tree, AChecked.DeclarationFile,
        Handler.SelectionRange.StartPos, True, AFiles, AReadText, ACancellation) do
      begin
        Edit.FileName := Location.FileName;
        Edit.Range := Location.Range;
        Edit.NewText := Rename.NewName;
        Result := Result + [Edit];
      end;
    end;
  finally
    if Tree <> ATree then
      Tree.Free;
  end;
end;

class function TLspRename.Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const ANewName: string;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken; ARenameHandlers: Boolean): TArray<TRenameEdit>;
var
  Checked: TRenameCheck;
  Location: TReferenceLocation;
  Edit: TRenameEdit;
begin
  if not IsValidName(ANewName) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('"%s" ist kein gültiger Bezeichner.', [ANewName]));
  Checked := Check(AResolver, AIndex, ATree, AFileName, APosition, AFiles);
  if Checked.Error <> '' then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, Checked.Error);
  Result := nil;
  for Location in TLspReferences.Find(AResolver, AIndex, ATree, AFileName, APosition, True, AFiles, AReadText,
    ACancellation) do
  begin
    Edit.FileName := Location.FileName;
    Edit.Range := Location.Range;
    Edit.NewText := ANewName;
    Result := Result + [Edit];
  end;
  if ARenameHandlers and Assigned(AReadText) then
    Result := Result + HandlerEdits(AResolver, AIndex, ATree, AFileName, Checked, ANewName, AFiles, AReadText,
      ACancellation);
end;

function TLspRename.ProjectFiles: TArray<string>;
begin
  if Assigned(FFiles) then
    Result := FFiles()
  else
    Result := nil;
end;

function TLspRename.HandlePrepare(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Checked: TRenameCheck;
  Files: TArray<string>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + PrepareMethod);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Files := ProjectFiles;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := FNamespaces;
    Checked := Check(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
      Files);
  finally
    Resolver.Free;
  end;
  // Der Editor zeigt die Fehlermeldung an.
  if Checked.Error <> '' then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, Checked.Error);
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('range', TLspPositions.RangeToJson(Checked.Range));
  TJSONObject(Result).AddPair('placeholder', Checked.Name);
end;

function TLspRename.HandleRename(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri, NewName, EditUri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Found: TArray<TRenameEdit>;
  Edit: TRenameEdit;
  Changes: TJSONObject;
  List: TJSONArray;
  Item: TJSONObject;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue) and
    TJSONObject(AParams).TryGetValue<string>('newName', NewName)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri", "position" und "newName" fehlen in ' + RenameMethod);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := FNamespaces;
    Found := Edits(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
      Trim(NewName), ProjectFiles, FReadText, ACancellation, FRenameHandlers);
  finally
    Resolver.Free;
  end;
  Changes := TJSONObject.Create;
  try
    for Edit in Found do
    begin
      EditUri := TDocumentUris.FromPath(Edit.FileName);
      List := Changes.GetValue(EditUri) as TJSONArray;
      if List = nil then
      begin
        List := TJSONArray.Create;
        Changes.AddPair(EditUri, List);
      end;
      Item := TJSONObject.Create;
      Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
      Item.AddPair('newText', Edit.NewText);
      List.AddElement(Item);
    end;
    Result := TJSONObject.Create;
  except
    Changes.Free;
    raise;
  end;
  TJSONObject(Result).AddPair('changes', Changes);
end;

end.
