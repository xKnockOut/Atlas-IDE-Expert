unit Atlas.Common.Lsp.Rename;

// Umbenennen im ganzen Projekt (textDocument/prepareRename und
// textDocument/rename, #30). Grundlage ist die Referenzsuche samt .dfm.
// Umbenannt werden nur Symbole, die im Projekt oder in geöffneten Dokumenten
// deklariert sind; RTL, VCL und andere Bibliotheken bleiben unangetastet.
// Bei Komponenten eines Formulars werden automatisch benannte Ereignis-Handler
// (Button1Click) mit umbenannt (#45).
// Betrifft das Umbenennen ein binär gespeichertes Formular, bricht es ab (#121):
// Die Positionen stammen aus der umgewandelten Textform und passen nicht zur Datei.

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
  Atlas.Common.Lsp.References;

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
    /// <summary>'' oder der Grund, warum ANewName die Bedeutung ändern würde: Eine lokale Variable, ein
    /// Parameter oder ein Feld mit dem neuen Namen verdeckt danach eine umbenannte Stelle, oder das
    /// umbenannte Symbol verdeckt eine vorhandene Verwendung von ANewName. ALocations sind die Stellen aus
    /// TLspReferences.Find samt Deklaration.</summary>
    class function Conflict(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const ANewName: string; const ALocations: TArray<TReferenceLocation>;
      const AReadText: TReferenceReadText): string; static;
    /// <summary>True für einen gültigen Bezeichner, der kein reserviertes Wort ist.</summary>
    class function IsValidName(const AName: string): Boolean; static;
    /// <summary>Alle zu ersetzenden Stellen; EJsonRpcError, wenn nicht umbenennbar oder ein betroffenes
    /// Formular binär gespeichert ist.</summary>
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
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Dfm.ComponentRename;

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

/// <summary>Gültigkeitsbereich eines unqualifiziert aufgelösten Namens: 1 lokal oder Parameter,
/// 2 Mitglied (Self oder with), 3 global; 0 = nicht aufgelöst.</summary>
function ScopeRank(const ASymbol: TResolvedSymbol): Integer;
begin
  case ASymbol.Kind of
    TResolvedKind.Local:
      Result := 1;
    TResolvedKind.Symbol:
      if ASymbol.Container <> '' then
        Result := 2
      else
        Result := 3;
  else
    Result := 0;
  end;
end;

function SameSymbol(const A, B: TResolvedSymbol): Boolean;
begin
  Result := (A.Kind = B.Kind) and (A.Kind <> TResolvedKind.None) and SameText(A.Name, B.Name) and
    SameText(A.Container, B.Container) and SameText(A.FileName, B.FileName) and (A.SymbolKind = B.SymbolKind);
  // Routinen haben Deklaration und Rumpf; sonst entscheidet die Stelle.
  if Result and not (A.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine]) then
    Result := A.SelectionRange.StartPos = B.SelectionRange.StartPos;
end;

/// <summary>Gewinnt AWinner an derselben Stelle gegen ALoser? Gleicher Bereich zählt als Konflikt, außer
/// bei globalen Namen aus verschiedenen Units (dort entscheidet die uses-Reihenfolge wie bisher).</summary>
function Hides(const AWinner, ALoser: TResolvedSymbol): Boolean;
var
  Winner, Loser: Integer;
begin
  Winner := ScopeRank(AWinner);
  Loser := ScopeRank(ALoser);
  if (Winner = 0) or (Loser = 0) then
    Exit(False);
  if Winner <> Loser then
    Exit(Winner < Loser);
  Result := (Winner <> 3) or SameText(AWinner.FileName, ALoser.FileName);
end;

/// <summary>Bezeichner ohne Punkt davor (Self.Name, Liste.Name bleiben unberührt).</summary>
function IsUnqualified(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Before: Integer;
begin
  Before := AIndex - 1;
  while (Before >= 0) and (ATokens[Before].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Before);
  Result := (Before < 0) or not ATokens[Before].IsSymbol('.');
end;

function ConflictText(const AFileName: string; const AToken: TPascalToken; const ANewName: string;
  const AAfter, ABefore: TResolvedSymbol): string;
begin
  Result := Format('Umbenennen in "%s" würde die Bedeutung ändern: In %s, Zeile %d, meinte "%s" danach %s ' +
    'statt %s. Bitte einen anderen Namen wählen oder dort "Self." ergänzen.',
    [ANewName, ExtractFileName(AFileName), AToken.StartPos.Line + 1, ANewName,
    TNameResolver.ShadowText(AAfter), TNameResolver.ShadowText(ABefore)]);
end;

class function TLspRename.Conflict(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; const ANewName: string; const ALocations: TArray<TReferenceLocation>;
  const AReadText: TReferenceReadText): string;

  function CheckTree(ATree: TSyntaxTree; const AFile: string; const ARenamed: TResolvedSymbol;
    const AOldName: string): string;
  var
    Index: Integer;
    Token: TPascalToken;
    Location: TReferenceLocation;
    Renamed, Before, After: TResolvedSymbol;
    IsLocation: Boolean;
  begin
    Result := '';
    Renamed := ARenamed;
    Renamed.Name := ANewName;
    for Index := 0 to High(ATree.Tokens) do
    begin
      Token := ATree.Tokens[Index];
      if (Token.Kind <> TPascalTokenKind.Identifier) or not IsUnqualified(ATree.Tokens, Index) then
        Continue;
      IsLocation := False;
      for Location in ALocations do
        if SameText(Location.FileName, AFile) and (Location.Range.StartPos = Token.StartPos) then
          IsLocation := True;
      if IsLocation then
      begin
        // Umbenannte Stelle: Verdeckt dort ein anderer Name ANewName das umbenannte Symbol?
        After := AResolver.ResolveChain(ATree, AFile, [ANewName], Token.Offset, False);
        if Hides(After, ARenamed) then
          Exit(ConflictText(AFile, Token, ANewName, After, ARenamed));
      end
      else if SameText(Token.Text, ANewName) or SameText(Token.Text, '&' + ANewName) then
      begin
        // Vorhandene Verwendung von ANewName: Sieht sie das umbenannte Symbol und läge es näher?
        Before := AResolver.ResolveChain(ATree, AFile, [ANewName], Token.Offset, False);
        After := AResolver.ResolveChain(ATree, AFile, [AOldName], Token.Offset, False);
        if SameSymbol(After, ARenamed) and Hides(ARenamed, Before) then
          Exit(ConflictText(AFile, Token, ANewName, Renamed, Before));
      end;
    end;
  end;

var
  Renamed: TResolvedSymbol;
  OldName, FileName, Text: string;
  Location: TReferenceLocation;
  Checked: TArray<string>;
  Tree: TSyntaxTree;
  Index: Integer;
begin
  Result := '';
  Index := TokenAt(ATree.Tokens, APosition);
  if Index < 0 then
    Exit;
  OldName := ATree.Tokens[Index].Text;
  if StartsStr('&', OldName) then
    OldName := Copy(OldName, 2, MaxInt);
  // Nur die Schreibweise ändert sich: Delphi unterscheidet keine Groß- und Kleinschreibung.
  if SameText(OldName, ANewName) then
    Exit;
  // Auf dem Namen einer Deklaration (Feld in der Klasse) löst Resolve nicht auf: dann eine Verwendung nehmen.
  Renamed := AResolver.Resolve(ATree, AFileName, APosition);
  for Location in ALocations do
    if (Renamed.Kind = TResolvedKind.None) and SameText(Location.FileName, AFileName) then
      Renamed := AResolver.Resolve(ATree, AFileName, Location.Range.StartPos);
  if Renamed.Kind in [TResolvedKind.None, TResolvedKind.UnitName] then
    Exit;

  Result := CheckTree(ATree, AFileName, Renamed, OldName);
  Checked := [AFileName];
  for Location in ALocations do
  begin
    FileName := Location.FileName;
    if (Result <> '') or not SameText(ExtractFileExt(FileName), '.pas') or (IndexText(FileName, Checked) >= 0) then
      Continue;
    Checked := Checked + [FileName];
    if not (Assigned(AReadText) and AReadText(FileName, Text)) then
      Continue;
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      Result := CheckTree(Tree, FileName, Renamed, OldName);
    finally
      Tree.Free;
    end;
  end;
end;

function HasHandler(const ARenames: TArray<THandlerRename>; const AOldName: string): Boolean;
var
  Rename: THandlerRename;
begin
  for Rename in ARenames do
    if SameText(Rename.OldName, AOldName) then
      Exit(True);
  Result := False;
end;

function HandlerEdits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AChecked: TRenameCheck; const ANewName: string; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TArray<TRenameEdit>;
var
  FormText, UnitText, FormFile: string;
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
  if not AReadText(AChecked.DeclarationFile, UnitText) then
    Exit;
  // .dfm, .fmx und FMX-Plattformansichten (#87); jeder Handler nur einmal.
  Renames := nil;
  for FormFile in TFormFiles.FormFiles(AChecked.DeclarationFile, UnitText) do
    if AReadText(FormFile, FormText) then
      for Rename in TDfmComponentRename.Handlers(FormText, AChecked.Name, ANewName) do
        if not HasHandler(Renames, Rename.OldName) then
          Renames := Renames + [Rename];
  if Length(Renames) = 0 then
    Exit;
  // Die Handler stehen in der Unit des Formulars.
  if SameText(AChecked.DeclarationFile, AFileName) then
    Tree := ATree
  else
    Tree := TSyntaxTreeCache.Parse(UnitText);
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
  Locations: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Edit: TRenameEdit;
  Reason: string;
begin
  if not IsValidName(ANewName) then

    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('"%s" ist kein gültiger Bezeichner.', [ANewName]));
  Checked := Check(AResolver, AIndex, ATree, AFileName, APosition, AFiles);
  if Checked.Error <> '' then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, Checked.Error);
  Result := nil;
  Locations := TLspReferences.Find(AResolver, AIndex, ATree, AFileName, APosition, True, AFiles, AReadText,
    ACancellation);
  Reason := Conflict(AResolver, ATree, AFileName, APosition, ANewName, Locations, AReadText);
  if Reason <> '' then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, Reason);
  for Location in Locations do
  begin
    Edit.FileName := Location.FileName;
    Edit.Range := Location.Range;
    Edit.NewText := ANewName;
    Result := Result + [Edit];
  end;
  if ARenameHandlers and Assigned(AReadText) then
    Result := Result + HandlerEdits(AResolver, AIndex, ATree, AFileName, Checked, ANewName, AFiles, AReadText,
      ACancellation);
  for Edit in Result do
    if not SameText(ExtractFileExt(Edit.FileName), '.pas') and TFileEncoding.IsBinaryFormFile(Edit.FileName) then
      raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, Format('%s ist ein binär gespeichertes Formular. ' +
        'Bitte zuerst in Textform umwandeln, dann erneut umbenennen.', [ExtractFileName(Edit.FileName)]));
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
