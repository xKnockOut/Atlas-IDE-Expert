unit Atlas.Common.Lsp.Reassigned;

// Befehl atlas.server.reassigned (#712): neu zugewiesene Variablen einer Datei
// für die Unterstreichung im IDE-Plugin.
// Argumente: [uri, {targets: ["locals", "valueParams", …],
//                   range: {"start": 120, "end": 220}}]
//   - targets wie highlight.reassigned.targets im Plugin (locals, loopVars,
//     valueParams, varParams, fields); fehlt die Angabe, gelten locals und
//     valueParams.
//   - range: Zeilen ab 0 (beide eingeschlossen), etwa der sichtbare Teil mit
//     Rand. Lokale Namen und Parameter kommen dann nur aus Routinen, die in
//     den Bereich reichen (TReassignedScope); ohne Angabe die ganze Datei.
//     In großen Units lief die ganze Datei mit Namensauflösung je Aufruf
//     regelmäßig ins Zeitlimit des Plugins (2 s).
// Abbruch: Zeitlimit und $/cancelRequest beenden Parsen, Analyse und
// Namensauflösung; die Anfrage endet mit RequestCancelled.
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
  Atlas.Common.JsonRpc.Contract,
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
      AText: string): TArray<TReassignedSymbol>; overload; static;
    /// <summary>Wie oben für den Ausschnitt AScope; ACancellation bricht auch die Namensauflösung ab
    /// (EJsonRpcRequestCancelled).</summary>
    class function Analyze(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AScope: TReassignedScope; const ACancellation: IJsonRpcCancellationToken): TArray<TReassignedSymbol>;
      overload; static;
    /// <summary>Antwort für ASymbols (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const ASymbols: TArray<TReassignedSymbol>): TJSONObject; static;
    /// <summary>Ziele aus dem zweiten Argument; ohne Angabe die Vorgabe.</summary>
    class function ReadTargets(const AArguments: TJSONArray): TReassignedTargets; static;
    /// <summary>Ziele und Zeilenbereich aus dem zweiten Argument; ohne range die ganze Datei.</summary>
    class function ReadScope(const AArguments: TJSONArray): TReassignedScope; static;
    /// <summary>Führt den Befehl aus; ACancellation (nil: nie) bricht ab. Der Aufrufer übernimmt das Ergebnis.
    /// </summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.ControlFlow.Signatures,
  Atlas.Common.Lsp.Internals.Cancellation,
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
  Result := Analyze(AResolver, ATree, AFileName, AText, TReassignedScope.Whole, nil);
end;

/// <summary>ALookup mit Abbruch: Vor jeder Frage (Namensauflösung je Aufruf) wird ACancellation geprüft.</summary>
function CancellableLookup(const ALookup: TFlowSignatureLookup;
  const ACancellation: IJsonRpcCancellationToken): TFlowSignatureLookup;
var
  mLookup: TFlowSignatureLookup;
  mCancellation: IJsonRpcCancellationToken;
begin
  if ACancellation = nil then
  begin
    // Nicht Exit(ALookup): Delphi ruft die Methodenreferenz dort auf (E2035).
    Result := ALookup;
    Exit;
  end;
  mLookup := ALookup;
  mCancellation := ACancellation;
  Result :=
    function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode
    begin
      mCancellation.ThrowIfCancellationRequested;
      Result := mLookup(ACall, AArgument);
    end;
end;

class function TLspReassigned.Analyze(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const AScope: TReassignedScope;
  const ACancellation: IJsonRpcCancellationToken): TArray<TReassignedSymbol>;
var
  mScope: TReassignedScope;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mScope := AScope;
  if ACancellation <> nil then
  begin
    mScope.Cancellation := TRequestCancellation.Create(ACancellation);
  end;
  try
    if AResolver = nil then
    begin
      Exit(TReassigned.Analyze(AText, ATree, CancellableLookup(TResolvedSignatures.Lookup(nil, ATree, AFileName),
        ACancellation), mScope));
    end;
    AResolver.PinTree(ATree, AFileName);
    try
      Result := TReassigned.Analyze(AText, ATree, CancellableLookup(TResolvedSignatures.Lookup(AResolver, ATree,
        AFileName), ACancellation), mScope);
    finally
      AResolver.UnpinTree;
    end;
  except
    on EReassignedCancelled do
    begin
      // Als RequestCancelled bzw. ContentModified wie jede abgebrochene Anfrage.
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      raise;
    end;
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

class function TLspReassigned.ReadScope(const AArguments: TJSONArray): TReassignedScope;
var
  mRange: TJSONValue;
  mFirst, mLast: Integer;
begin
  Result := TReassignedScope.Whole;
  Result.Targets := ReadTargets(AArguments);
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONObject) then
  begin
    Exit;
  end;
  mRange := TJSONObject(AArguments.Items[1]).GetValue('range');
  if (mRange is TJSONObject) and TJSONObject(mRange).TryGetValue<Integer>('start', mFirst) and
    TJSONObject(mRange).TryGetValue<Integer>('end', mLast) and (mFirst >= 0) and (mLast >= mFirst) then
  begin
    Result.FirstLine := mFirst;
    Result.LastLine := mLast;
  end;
end;

class function TLspReassigned.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mScope: TReassignedScope;
  mSymbols: TArray<TReassignedSymbol>;
  mParse: IPascalCancellation;
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
  mScope := ReadScope(AArguments);
  mSymbols := nil;
  if mScope.Targets <> [] then
  begin
    mParse := nil;
    if ACancellation <> nil then
    begin
      mParse := TRequestCancellation.Create(ACancellation);
    end;
    mShared := TSyntaxTreeCache.Get(mDocument, mParse);
    if mShared = nil then
    begin
      // Parsen abgebrochen.
      ACancellation.ThrowIfCancellationRequested;
      Exit(Json(nil));
    end;
    mResolver := nil;
    if AIndex <> nil then
    begin
      mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
      mResolver.Namespaces := ANamespaces;
    end;
    try
      mSymbols := TReassigned.Filter(Analyze(mResolver, mShared.Tree, TDocumentUris.ToPath(mUri), mDocument.Text,
        mScope, ACancellation), mScope.Targets);
    finally
      mResolver.Free;
    end;
  end;
  Result := Json(mSymbols);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Reassigned', cTexts);

end.
