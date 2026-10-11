unit Atlas.Common.Lsp.CodeLens;

// Code Lens über Klassen und Methoden (textDocument/codeLens, codeLens/resolve):
//   - "5 Referenzen" (erst bei codeLens/resolve gezählt, weil die Suche das Projekt liest),
//   - "überschreibt TControl.Paint" bei Methoden, die ein Vorfahr schon deklariert,
//   - "3 Nachfahren" bei Klassen und Interfaces,
//   - "behandelt WM_PAINT (… auch in TWinControl)" bei Klassen mit Message-Handlern.
// Ein Klick ruft atlas.showLocations im Editor auf (Argumente: URI, Position, Locations).

interface

{$SCOPEDENUMS ON}

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
  TCodeLensKind = (References, Overrides, Descendants, Messages);

  TCodeLensLocation = record
    FileName: string;
    Range: TTextRange;
  end;

  TCodeLensEntry = record
    Kind: TCodeLensKind;
    /// <summary>Name des Symbols; die Linse steht über dieser Zeile.</summary>
    Range: TTextRange;
    /// <summary>'' bis codeLens/resolve (nur References).</summary>
    Title: string;
    Targets: TArray<TCodeLensLocation>;
  end;

  TLspCodeLens = class
  public const
    LensMethod = 'textDocument/codeLens';
    ResolveMethod = 'codeLens/resolve';
    ShowLocationsCommand = 'atlas.showLocations';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    function NewResolver: TNameResolver;
    function HandleLens(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function Capability: TJSONObject; static;
    /// <summary>Alle Linsen der Datei; Referenzen noch ohne Titel.</summary>
    class function Lenses(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const AReadText: TReferenceReadText): TArray<TCodeLensEntry>; static;
    /// <summary>Zählt die Referenzen auf das Symbol der Linse.</summary>
    class function ResolveReferences(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const AEntry: TCodeLensEntry; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken = nil): TCodeLensEntry; static;
    /// <summary>CodeLens des LSP; ohne Titel mit data für codeLens/resolve. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AEntry: TCodeLensEntry; const AFileName: string): TJSONObject; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.MessageHandlers,
  Atlas.Common.Lsp.Internals.Cancellation;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  LensTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType];
  MaxDepth = 32;

function PositionKey(const APosition: TTextPosition): string;
begin
  Result := IntToStr(APosition.Line) + ':' + IntToStr(APosition.Character);
end;

function Location(const AFileName: string; const ARange: TTextRange): TCodeLensLocation;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
end;

function Plural(ACount: Integer; const AOne, AMany: string): string;
begin
  if ACount = 1 then
    Result := '1 ' + AOne
  else
    Result := IntToStr(ACount) + ' ' + AMany;
end;

function UnitOf(const AIndex: ISymbolIndex; const ACurrent: TUnitIndex; const AFileName: string;
  out AUnit: TUnitIndex): Boolean;
begin
  if SameText(AFileName, ACurrent.FileName) then
  begin
    AUnit := ACurrent;
    Exit(True);
  end;
  Result := AIndex.FindFile(AFileName, AUnit);
end;

/// <summary>Nächster Vorfahr, der AName deklariert; False, wenn keiner im Index steht.</summary>
function FindOverridden(AResolver: TNameResolver; const AIndex: ISymbolIndex; const ACurrent: TUnitIndex;
  const AType: TIndexSymbol; const AName: string; out AOwner: string; out ATarget: TCodeLensLocation): Boolean;
var
  Ancestors: TArray<string>;
  FromUnit, OwnerUnit: TUnitIndex;
  Ancestor: TResolvedSymbol;
  Symbol: TIndexSymbol;
  Depth: Integer;
  Name: string;
begin
  Result := False;
  FromUnit := ACurrent;
  Ancestors := AType.Ancestors;
  for Depth := 1 to MaxDepth do
  begin
    if Length(Ancestors) = 0 then
      Exit;
    Name := Ancestors[0];
    if (Pos('<', Name) > 0) or not AResolver.ResolveTypeFrom(FromUnit, Name, Ancestor) or
      not UnitOf(AIndex, ACurrent, Ancestor.FileName, OwnerUnit) then
      Exit;
    for Symbol in OwnerUnit.Symbols do
      if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, Ancestor.QualifiedName) and
        SameText(Symbol.Name, AName) then
      begin
        AOwner := Ancestor.Name;
        ATarget := Location(OwnerUnit.FileName, Symbol.SelectionRange);
        Exit(True);
      end;
    FromUnit := OwnerUnit;
    Ancestors := Ancestor.Ancestors;
  end;
end;

/// <summary>Namen in Köpfen von Implementierungen (procedure TFoo.Bar): keine Verwendungen.</summary>
function HeaderNames(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  Tokens: TArray<TPascalToken>;
  Index, Back: Integer;
begin
  Result := TDictionary<string, Boolean>.Create;
  Tokens := ATree.Tokens;
  for Index := 2 to High(Tokens) do
  begin
    if not (Tokens[Index - 1].IsSymbol('.') and (Tokens[Index].Kind = TPascalTokenKind.Identifier)) then
      Continue;
    Back := Index - 2;
    while (Back >= 2) and (Tokens[Back].Kind = TPascalTokenKind.Identifier) and Tokens[Back - 1].IsSymbol('.') do
      Dec(Back, 2);
    if (Back >= 1) and (Tokens[Back].Kind = TPascalTokenKind.Identifier) and
      (Tokens[Back - 1].IsKeyword('procedure') or Tokens[Back - 1].IsKeyword('function') or
      Tokens[Back - 1].IsKeyword('constructor') or Tokens[Back - 1].IsKeyword('destructor') or
      Tokens[Back - 1].IsKeyword('operator')) then
      Result.AddOrSetValue(PositionKey(Tokens[Index].StartPos), True);
  end;
end;

{ TLspCodeLens }

constructor TLspCodeLens.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspCodeLens.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(LensMethod, HandleLens);
  ADispatcher.RegisterConcurrentRequest(ResolveMethod, HandleResolve);
end;

class function TLspCodeLens.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('resolveProvider', TJSONBool.Create(True));
end;

class function TLspCodeLens.Lenses(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AReadText: TReferenceReadText): TArray<TCodeLensEntry>;
var
  Current: TUnitIndex;
  Symbol, TypeSymbol: TIndexSymbol;
  Types: TDictionary<string, TIndexSymbol>;
  Headers: TDictionary<string, Boolean>;
  List: TList<TCodeLensEntry>;
  Entry: TCodeLensEntry;
  Descendants: TArray<TSymbolLocation>;
  Descendant: TSymbolLocation;
  Owner: string;
  Target: TCodeLensLocation;
  Overview: TMessageOverview;
  Handler: TMessageHandler;
begin
  Current := TIndexExtractor.Extract(ATree, AFileName);
  List := TList<TCodeLensEntry>.Create;
  Types := TDictionary<string, TIndexSymbol>.Create;
  // Rümpfe (procedure TFoo.Bar) bekommen keine eigene Linse.
  Headers := HeaderNames(ATree);
  try
    for Symbol in Current.Symbols do
      if Symbol.Kind in LensTypeKinds then
        Types.AddOrSetValue(UpperCase(Symbol.QualifiedName), Symbol);

    for Symbol in Current.Symbols do
    begin
      if Headers.ContainsKey(PositionKey(Symbol.SelectionRange.StartPos)) then
        Continue;
      if Symbol.Kind in LensTypeKinds then
      begin
        Entry := Default(TCodeLensEntry);
        Entry.Kind := TCodeLensKind.References;
        Entry.Range := Symbol.SelectionRange;
        List.Add(Entry);
        if Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType] then
        begin
          Descendants := AIndex.Descendants(Symbol.QualifiedName);
          if Length(Descendants) > 0 then
          begin
            Entry := Default(TCodeLensEntry);
            Entry.Kind := TCodeLensKind.Descendants;
            Entry.Range := Symbol.SelectionRange;
            Entry.Title := Plural(Length(Descendants), 'Nachfahre', 'Nachfahren');
            for Descendant in Descendants do
              Entry.Targets := Entry.Targets + [Location(Descendant.FileName, Descendant.Symbol.SelectionRange)];
            List.Add(Entry);
          end;
        end;
        if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') then
        begin
          Overview := TMessageHandlers.Overview(AResolver, AIndex, ATree, AFileName, Symbol.Name,
            function(const AName: string; out AText: string): Boolean
            begin
              Result := Assigned(AReadText) and AReadText(AName, AText);
            end);
          if Overview.Found then
          begin
            Entry := Default(TCodeLensEntry);
            Entry.Kind := TCodeLensKind.Messages;
            Entry.Range := Symbol.SelectionRange;
            Entry.Title := Overview.Title;
            for Handler in Overview.Own do
              Entry.Targets := Entry.Targets + [Location(Handler.FileName, Handler.SelectionRange)];
            List.Add(Entry);
          end;
        end;
      end
      else if (Symbol.Kind in RoutineKinds) and (Symbol.Container <> '') and
        Types.TryGetValue(UpperCase(Symbol.Container), TypeSymbol) then
      begin
        Entry := Default(TCodeLensEntry);
        Entry.Kind := TCodeLensKind.References;
        Entry.Range := Symbol.SelectionRange;
        List.Add(Entry);
        if FindOverridden(AResolver, AIndex, Current, TypeSymbol, Symbol.Name, Owner, Target) then
        begin
          Entry := Default(TCodeLensEntry);
          Entry.Kind := TCodeLensKind.Overrides;
          Entry.Range := Symbol.SelectionRange;
          Entry.Title := 'überschreibt ' + Owner + '.' + Symbol.Name;
          Entry.Targets := [Target];
          List.Add(Entry);
        end;
      end;
    end;
    Result := List.ToArray;
  finally
    Headers.Free;
    Types.Free;
    List.Free;
  end;
end;

class function TLspCodeLens.ResolveReferences(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AFileName: string; const AEntry: TCodeLensEntry; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TCodeLensEntry;
var
  Found: TReferenceLocation;
  Headers: TDictionary<string, Boolean>;
begin
  Result := AEntry;
  Result.Targets := nil;
  Headers := HeaderNames(ATree);
  try
    for Found in TLspReferences.Find(AResolver, AIndex, ATree, AFileName, AEntry.Range.StartPos, False, AFiles,
      AReadText, ACancellation) do
      if not (SameText(Found.FileName, AFileName) and Headers.ContainsKey(PositionKey(Found.Range.StartPos))) then
        Result.Targets := Result.Targets + [Location(Found.FileName, Found.Range)];
  finally
    Headers.Free;
  end;
  Result.Title := Plural(Length(Result.Targets), 'Referenz', 'Referenzen');
end;

class function TLspCodeLens.ToJson(const AEntry: TCodeLensEntry; const AFileName: string): TJSONObject;
var
  Command, Data: TJSONObject;
  Arguments, Locations: TJSONArray;
  Target: TCodeLensLocation;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AEntry.Range));
  if AEntry.Title = '' then
  begin
    Data := TJSONObject.Create;
    Data.AddPair('uri', TDocumentUris.FromPath(AFileName));
    Data.AddPair('line', TJSONNumber.Create(AEntry.Range.StartPos.Line));
    Data.AddPair('character', TJSONNumber.Create(AEntry.Range.StartPos.Character));
    Data.AddPair('endLine', TJSONNumber.Create(AEntry.Range.EndPos.Line));
    Data.AddPair('endCharacter', TJSONNumber.Create(AEntry.Range.EndPos.Character));
    Result.AddPair('data', Data);
    Exit;
  end;
  Locations := TJSONArray.Create;
  for Target in AEntry.Targets do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('uri', TDocumentUris.FromPath(Target.FileName));
    Item.AddPair('range', TLspPositions.RangeToJson(Target.Range));
    Locations.AddElement(Item);
  end;
  Arguments := TJSONArray.Create;
  Arguments.Add(TDocumentUris.FromPath(AFileName));
  Arguments.AddElement(TLspPositions.PositionToJson(AEntry.Range.StartPos));
  Arguments.AddElement(Locations);
  Command := TJSONObject.Create;
  Command.AddPair('title', AEntry.Title);
  Command.AddPair('command', ShowLocationsCommand);
  Command.AddPair('arguments', Arguments);
  Result.AddPair('command', Command);
end;

function TLspCodeLens.NewResolver: TNameResolver;
begin
  Result := TNameResolver.Create(FIndex, FEnsureUnit);
  Result.Namespaces := FNamespaces;
end;

function TLspCodeLens.HandleLens(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri, FileName: string;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Entry: TCodeLensEntry;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  FileName := TDocumentUris.ToPath(Uri);
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := NewResolver;
  try
    Result := TJSONArray.Create;
    for Entry in Lenses(Resolver, FIndex, Tree, FileName, FReadText) do
      TJSONArray(Result).AddElement(ToJson(Entry, FileName));
  finally
    Resolver.Free;
  end;
end;

function TLspCodeLens.HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri, FileName: string;
  Line, Character, EndLine, EndCharacter: Integer;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Entry: TCodeLensEntry;
  Files: TArray<string>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('data.uri', Uri) and
    TJSONObject(AParams).TryGetValue<Integer>('data.line', Line) and
    TJSONObject(AParams).TryGetValue<Integer>('data.character', Character) and
    TJSONObject(AParams).TryGetValue<Integer>('data.endLine', EndLine) and
    TJSONObject(AParams).TryGetValue<Integer>('data.endCharacter', EndCharacter)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "data" der Linse fehlt oder ist unvollständig');
  Entry := Default(TCodeLensEntry);
  Entry.Kind := TCodeLensKind.References;
  Entry.Range := TTextRange.Create(TTextPosition.Create(Line, Character), TTextPosition.Create(EndLine, EndCharacter));
  FileName := TDocumentUris.ToPath(Uri);
  if Assigned(FFiles) then
    Files := FFiles()
  else
    Files := nil;
  if FStore.TryGet(Uri, Document) then
  begin
    Cancellation := TRequestCancellation.Create(ACancellation);
    Shared := TSyntaxTreeCache.Get(Document, Cancellation);
    Tree := Shared.Tree;
    Resolver := NewResolver;
    try
      Entry := ResolveReferences(Resolver, FIndex, Tree, FileName, Entry, Files, FReadText, ACancellation);
    finally
      Resolver.Free;
    end;
  end
  else
    Entry.Title := Plural(0, 'Referenz', 'Referenzen');
  Result := ToJson(Entry, FileName);
end;

end.
