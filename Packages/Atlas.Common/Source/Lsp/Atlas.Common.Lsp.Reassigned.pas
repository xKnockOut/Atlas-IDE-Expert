unit Atlas.Common.Lsp.Reassigned;

// Befehl atlas.server.reassigned (#712): neu zugewiesene Variablen einer Datei
// für die Unterstreichung im IDE-Plugin.
// Argumente: [uri, {targets: ["locals", "valueParams", …]}]
//   - targets wie highlight.reassigned.targets im Plugin (locals, loopVars,
//     valueParams, varParams, fields); fehlt die Angabe, gelten locals und
//     valueParams.
// Antwort (Zeilen und Zeichen ab 0 wie im Protokoll):
//   {"symbols": [{"name": "Total", "kind": "local", "writes": 3,
//                 "routine": "TFoo.Sum", "writeLines": [12, 14, 17],
//                 "uses": [{"line": 10, "character": 2, "endCharacter": 7,
//                           "write": false}, …]}, …]}
// "uses" enthält die Deklaration und jede Verwendung; "write" steht an den
// sicheren Schreibstellen und an der Steuerung einer for-Schleife.
// Die Analyse steht in Atlas.Common.Semantics.Reassigned; die Übergabeart von
// Argumenten kommt aus der Datei, den Standardroutinen und über die
// Namensauflösung (Atlas.Common.Semantics.ResolvedSignatures).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.Reassigned;

type
  TLspReassigned = class
  public const
    Command = 'atlas.server.reassigned';
  public
    /// <summary>Alle Namen der Datei mit ihren Stellen; Argumente über AResolver (nil: nur die Datei). Heftet den
    /// Baum für die Dauer an den Auflöser.</summary>
    class function Analyze(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
      AText: string): TArray<TReassignedSymbol>; static;
    /// <summary>Antwort für ASymbols (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const ASymbols: TArray<TReassignedSymbol>): TJSONObject; static;
    /// <summary>Ziele aus dem zweiten Argument; ohne Angabe die Vorgabe.</summary>
    class function ReadTargets(const AArguments: TJSONArray): TReassignedTargets; static;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.ResolvedSignatures;

{ TLspReassigned }

class function TLspReassigned.Analyze(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string): TArray<TReassignedSymbol>;
begin
  Result := nil;
  if ATree = nil then
    Exit;
  if AResolver = nil then
    Exit(TReassigned.Analyze(AText, ATree, TResolvedSignatures.Lookup(nil, ATree, AFileName)));
  AResolver.PinTree(ATree, AFileName);
  try
    Result := TReassigned.Analyze(AText, ATree, TResolvedSignatures.Lookup(AResolver, ATree, AFileName));
  finally
    AResolver.UnpinTree;
  end;
end;

class function TLspReassigned.Json(const ASymbols: TArray<TReassignedSymbol>): TJSONObject;
var
  Symbols, Uses_, Lines: TJSONArray;
  Item, Use: TJSONObject;
  Symbol: TReassignedSymbol;
  Occurrence: TReassignedOccurrence;
  Line: Integer;
begin
  Result := TJSONObject.Create;
  Symbols := TJSONArray.Create;
  Result.AddPair('symbols', Symbols);
  for Symbol in ASymbols do
  begin
    Item := TJSONObject.Create;
    Symbols.AddElement(Item);
    Item.AddPair('name', Symbol.Name);
    Item.AddPair('kind', TReassigned.KindNames[Symbol.Kind]);
    Item.AddPair('writes', TJSONNumber.Create(Symbol.WriteCount));
    Item.AddPair('routine', Symbol.RoutineName);
    Lines := TJSONArray.Create;
    Item.AddPair('writeLines', Lines);
    for Line in Symbol.WriteLines do
      Lines.Add(Line);
    Uses_ := TJSONArray.Create;
    Item.AddPair('uses', Uses_);
    for Occurrence in Symbol.Occurrences do
    begin
      Use := TJSONObject.Create;
      Uses_.AddElement(Use);
      Use.AddPair('line', TJSONNumber.Create(Occurrence.Range.StartPos.Line));
      Use.AddPair('character', TJSONNumber.Create(Occurrence.Range.StartPos.Character));
      Use.AddPair('endCharacter', TJSONNumber.Create(Occurrence.Range.EndPos.Character));
      Use.AddPair('write', TJSONBool.Create(Occurrence.Write in [TReassignedWrite.Write,
        TReassignedWrite.LoopWrite]));
    end;
  end;
end;

class function TLspReassigned.ReadTargets(const AArguments: TJSONArray): TReassignedTargets;
var
  Settings: TJSONObject;
  Value, Item: TJSONValue;
  Names: TArray<string>;
begin
  Result := TReassigned.DefaultTargets;
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONObject) then
    Exit;
  Settings := TJSONObject(AArguments.Items[1]);
  Value := Settings.GetValue('targets');
  if not (Value is TJSONArray) then
    Exit;
  Names := nil;
  for Item in TJSONArray(Value) do
    if Item is TJSONString then
      Names := Names + [Item.Value];
  Result := TReassigned.TargetsOf(Names);
end;

class function TLspReassigned.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Targets: TReassignedTargets;
  Symbols: TArray<TReassignedSymbol>;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet wird die URI');
  Uri := AArguments.Items[0].Value;
  if not AStore.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Dokument ist nicht geöffnet: ' + Uri);
  Targets := ReadTargets(AArguments);
  Symbols := nil;
  if Targets <> [] then
  begin
    Shared := TSyntaxTreeCache.Get(Document);
    Resolver := nil;
    if AIndex <> nil then
    begin
      Resolver := TNameResolver.Create(AIndex, AEnsureUnit);
      Resolver.Namespaces := ANamespaces;
    end;
    try
      Symbols := TReassigned.Filter(Analyze(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text),
        Targets);
    finally
      Resolver.Free;
    end;
  end;
  Result := Json(Symbols);
end;

end.
