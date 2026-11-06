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
    cCommand = 'atlas.server.reassigned';
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
  Atlas.Common.Semantics.ResolvedSignatures,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TReassignedText = (TheURIIsExpected, DocumentIsNotOpen);

const
  cTexts: array[TReassignedText] of TAtlasText = (
    (De: 'Erwartet wird die URI'; En: 'The URI is expected'),
    (De: 'Dokument ist nicht geöffnet: '; En: 'Document is not open: '));

{$SCOPEDENUMS OFF}

{ TLspReassigned }

class function TLspReassigned.Analyze(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string): TArray<TReassignedSymbol>;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  if AResolver = nil then
  begin
    Exit(TReassigned.Analyze(AText, ATree, TResolvedSignatures.Lookup(nil, ATree, AFileName)));
  end;
  AResolver.PinTree(ATree, AFileName);
  try
    Result := TReassigned.Analyze(AText, ATree, TResolvedSignatures.Lookup(AResolver, ATree, AFileName));
  finally
    AResolver.UnpinTree;
  end;
end;

class function TLspReassigned.Json(const ASymbols: TArray<TReassignedSymbol>): TJSONObject;
var
  mSymbols, mUses_, mLines: TJSONArray;
  mItem, mUse: TJSONObject;
  mSymbol: TReassignedSymbol;
  mOccurrence: TReassignedOccurrence;
  mLine: Integer;
begin
  Result := TJSONObject.Create;
  mSymbols := TJSONArray.Create;
  Result.AddPair('symbols', mSymbols);
  for mSymbol in ASymbols do
  begin
    mItem := TJSONObject.Create;
    mSymbols.AddElement(mItem);
    mItem.AddPair('name', mSymbol.Name);
    mItem.AddPair('kind', TReassigned.cKindNames[mSymbol.Kind]);
    mItem.AddPair('writes', TJSONNumber.Create(mSymbol.WriteCount));
    mItem.AddPair('routine', mSymbol.RoutineName);
    mLines := TJSONArray.Create;
    mItem.AddPair('writeLines', mLines);
    for mLine in mSymbol.WriteLines do
    begin
      mLines.Add(mLine);
    end;
    mUses_ := TJSONArray.Create;
    mItem.AddPair('uses', mUses_);
    for mOccurrence in mSymbol.Occurrences do
    begin
      mUse := TJSONObject.Create;
      mUses_.AddElement(mUse);
      mUse.AddPair('line', TJSONNumber.Create(mOccurrence.Range.StartPos.Line));
      mUse.AddPair('character', TJSONNumber.Create(mOccurrence.Range.StartPos.Character));
      mUse.AddPair('endCharacter', TJSONNumber.Create(mOccurrence.Range.EndPos.Character));
      mUse.AddPair('write', TJSONBool.Create(mOccurrence.Write in [TReassignedWrite.Write,
        TReassignedWrite.LoopWrite]));
    end;
  end;
end;

class function TLspReassigned.ReadTargets(const AArguments: TJSONArray): TReassignedTargets;
var
  mSettings: TJSONObject;
  mValue, mItem: TJSONValue;
  mNames: TArray<string>;
begin
  Result := TReassigned.cDefaultTargets;
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONObject) then
  begin
    Exit;
  end;
  mSettings := TJSONObject(AArguments.Items[1]);
  mValue := mSettings.GetValue('targets');
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  mNames := nil;
  for mItem in TJSONArray(mValue) do
  begin
    if mItem is TJSONString then
    begin
      mNames := mNames + [mItem.Value];
    end;
  end;
  Result := TReassigned.TargetsOf(mNames);
end;

class function TLspReassigned.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mTargets: TReassignedTargets;
  mSymbols: TArray<TReassignedSymbol>;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TReassignedText.TheURIIsExpected].Text);
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TReassignedText.DocumentIsNotOpen].Text + mUri);
  end;
  mTargets := ReadTargets(AArguments);
  mSymbols := nil;
  if mTargets <> [] then
  begin
    mShared := TSyntaxTreeCache.Get(mDocument);
    mResolver := nil;
    if AIndex <> nil then
    begin
      mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
      mResolver.Namespaces := ANamespaces;
    end;
    try
      mSymbols := TReassigned.Filter(Analyze(mResolver, mShared.Tree, TDocumentUris.ToPath(mUri), mDocument.Text),
        mTargets);
    finally
      mResolver.Free;
    end;
  end;
  Result := Json(mSymbols);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Reassigned', cTexts);

end.
