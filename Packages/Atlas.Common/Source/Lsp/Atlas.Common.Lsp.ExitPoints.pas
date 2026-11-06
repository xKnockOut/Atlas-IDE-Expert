unit Atlas.Common.Lsp.ExitPoints;

// Befehl atlas.server.exitPoints (#698): Austrittspunkte am Cursor für die
// Hervorhebung im IDE-Plugin.
// Argumente: [uri, {line, character}, {exceptions, loops}]
//   - exceptions: auf except bzw. on die auslösenden Aufrufe zeigen
//     (highlight.exitPoints.exceptions), loops: auf Break/Continue die Schleife
//     (highlight.exitPoints.loops); fehlen sie, gilt true.
//   - Was als Austritt zählt, steht in highlight.exitKeywords der Konfiguration
//     zur Datei (dieselbe Liste wie für documentHighlight).
// Antwort (Zeilen und Zeichen ab 0 wie im Protokoll):
//   {"query": "routine" | "result" | "exceptions" | "loop" | "",
//    "routine": {"name": "TFoo.Bar", "line": 12, "character": 15, "endCharacter": 18},
//    "function": true, "exits": 3, "resultMissing": false,
//    "points": [{"kind": "exit", "line": 14, "character": 4, "endCharacter": 8,
//                "resultMissing": true, "detail": "", "exception": ""}, …]}
// Die Analyse steht in Atlas.Common.Semantics.ExitPoints. Was eine Routine
// laut XMLDoc auslöst, kommt zuerst aus der Unit selbst, sonst über die
// Namensauflösung aus der deklarierenden Unit (auch mit <inheritdoc/>); die
// Vererbung der Exception-Klassen ebenso.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.DocumentHighlights,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExitPoints,
  Atlas.Common.Lsp.Documentation;

type
  /// <summary>Woher der Befehl Texte anderer Dateien und die Einstellungen zur Datei bekommt.</summary>
  TExitPointsReaders = record
    /// <summary>Text anderer Units für die XMLDoc der aufgerufenen Routinen (nil = keine).</summary>
    ReadText: TDocReadText;
    /// <summary>highlight.exitKeywords zur Datei (nil = Standard).</summary>
    SettingsFor: THighlightSettingsProvider;
    class function Create(const AReadText: TDocReadText; const ASettingsFor: THighlightSettingsProvider):
      TExitPointsReaders; static;
  end;

  TLspExitPoints = class
  public const
    cCommand = 'atlas.server.exitPoints';
  public
    /// <summary>Antwort für ASet (siehe Kopf der Unit).</summary>
    class function Json(const ASet: TExitPointSet): TJSONObject; static;
    /// <summary>Name einer Art in der Antwort (exit, raise, halt, call, end, result, source, handler, loop,
    /// jump).</summary>
    class function KindName(AKind: TExitPointKind): string; static;
    /// <summary>Exceptions laut XMLDoc: erst der Baum, dann über AResolver die deklarierende Unit.</summary>
    class function ExceptionLookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ALines: TArray<string>; const AReadText: TDocReadText): TExitPointExceptionLookup; static;
    /// <summary>Vererbung über AResolver, sonst wie TExitPoints.TreeClassTest.</summary>
    class function ClassTest(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string):
      TExitPointClassTest; static;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReaders: TExitPointsReaders;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TExitPointsText = (URIAndPositionExpected, DocumentIsNotOpen);

const
  cTexts: array[TExitPointsText] of TAtlasText = (
    (De: 'Erwartet werden URI und Position'; En: 'URI and position expected'),
    (De: 'Dokument ist nicht geöffnet: '; En: 'Document is not open: '));

{$SCOPEDENUMS OFF}

const
  cKindNames: array[TExitPointKind] of string = ('exit', 'raise', 'halt', 'call', 'end', 'result', 'source',
    'handler', 'loop', 'jump');
  cQueryNames: array[TExitPointQuery] of string = ('', 'routine', 'result', 'exceptions', 'loop');

{ TExitPointsReaders }

class function TExitPointsReaders.Create(const AReadText: TDocReadText;
  const ASettingsFor: THighlightSettingsProvider): TExitPointsReaders;
begin
  Result.ReadText := AReadText;
  Result.SettingsFor := ASettingsFor;
end;

{ TLspExitPoints }

class function TLspExitPoints.KindName(AKind: TExitPointKind): string;
begin
  Result := cKindNames[AKind];
end;

function RangeJson(const ARange: TTextRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(ARange.StartPos.Line));
  Result.AddPair('character', TJSONNumber.Create(ARange.StartPos.Character));
  Result.AddPair('endCharacter', TJSONNumber.Create(ARange.EndPos.Character));
end;

class function TLspExitPoints.Json(const ASet: TExitPointSet): TJSONObject;
var
  mPoints: TJSONArray;
  mItem, mRoutine: TJSONObject;
  mPoint: TExitPoint;
begin
  Result := TJSONObject.Create;
  Result.AddPair('query', cQueryNames[ASet.Query]);
  if ASet.HasRoutine then
  begin
    mRoutine := RangeJson(ASet.RoutineRange);
    mRoutine.AddPair('name', ASet.RoutineName);
    Result.AddPair('routine', mRoutine);
  end;
  Result.AddPair('function', TJSONBool.Create(ASet.IsFunction));
  Result.AddPair('exits', TJSONNumber.Create(ASet.ExitCount));
  Result.AddPair('resultMissing', TJSONBool.Create(ASet.ResultMissing));
  mPoints := TJSONArray.Create;
  Result.AddPair('points', mPoints);
  for mPoint in ASet.Points do
  begin
    mItem := RangeJson(mPoint.Range);
    mItem.AddPair('kind', cKindNames[mPoint.Kind]);
    mItem.AddPair('resultMissing', TJSONBool.Create(mPoint.ResultMissing));
    mItem.AddPair('detail', mPoint.Detail);
    mItem.AddPair('exception', mPoint.ExceptionClass);
    mPoints.AddElement(mItem);
  end;
end;

class function TLspExitPoints.ExceptionLookup(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const ALines: TArray<string>; const AReadText: TDocReadText): TExitPointExceptionLookup;
var
  mOwn: TExitPointExceptionLookup;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mFileName: string;
  mReader: TDocReadText;
begin
  mOwn := TExitPoints.TreeExceptions(ATree, ALines);
  mResolver := AResolver;
  mTree := ATree;
  mFileName := AFileName;
  mReader := AReadText;
  Result :=
    function(ACallee: TSyntaxNode): TArray<string>
    var
      Tokens: TArray<TPascalToken>;
      Index: Integer;
      Symbol: TResolvedSymbol;
      Text: string;
      Lines: TArray<string>;
      Doc: TXmlDoc;
      Entry: TXmlDocEntry;
    begin
      Result := mOwn(ACallee);
      if (Result <> nil) or (mResolver = nil) or (ACallee = nil) then
      begin
        Exit;
      end;
      // Name am Ende des Ziels (Bar in Obj.Bar) über die Namensauflösung.
      Tokens := mTree.Tokens;
      Symbol := Default(TResolvedSymbol);
      for Index := High(Tokens) downto 0 do
      begin
        if (Tokens[Index].Offset < ACallee.EndOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
        begin
          Symbol := mResolver.Resolve(mTree, mFileName, Tokens[Index].StartPos);
          Break;
        end;
      end;
      if not Symbol.Found or (Symbol.FileName = '') or not Assigned(mReader) or
        not mReader(Symbol.FileName, Text) then
      begin
        Exit;
      end;
      Lines := TTextLines.SplitLines(Text);
      Doc := TLspDocumentation.Load(mResolver, Symbol, Lines, Symbol.Range.StartPos.Line, mReader);
      for Entry in Doc.Exceptions do
      begin
        Result := Result + [TXmlDoc.NormalizeCref(Entry.Name)];
      end;
    end;
end;

class function TLspExitPoints.ClassTest(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TExitPointClassTest;
var
  mOwn: TExitPointClassTest;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mFileName: string;
begin
  mOwn := TExitPoints.TreeClassTest(ATree);
  mResolver := AResolver;
  mTree := ATree;
  mFileName := AFileName;
  Result :=
    function(const AClass, AHandler: string; AOffset: Integer): Boolean
    begin
      Result := mOwn(AClass, AHandler, AOffset) or
        ((mResolver <> nil) and mResolver.Queries.TypeDescendsFrom(mTree, mFileName, AOffset, AClass, AHandler));
    end;
end;

class function TLspExitPoints.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReaders: TExitPointsReaders;
  const AArguments: TJSONArray): TJSONValue;
var
  mUri, mFileName: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mOptions: TExitPointOptions;
  mSettings: TJSONObject;
  mLines: TArray<string>;
  mFlag: TJSONValue;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TExitPointsText.URIAndPositionExpected].Text);
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TExitPointsText.DocumentIsNotOpen].Text + mUri);
  end;
  mOptions := TExitPointOptions.Default;
  if Assigned(AReaders.SettingsFor) then
  begin
    mOptions.Keywords := AReaders.SettingsFor(mUri).ExitKeywords;
  end
  else
  begin
    mOptions.Keywords := THighlightSettings.Default.ExitKeywords;
  end;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
  begin
    mSettings := TJSONObject(AArguments.Items[2]);
    mFlag := mSettings.GetValue('exceptions');
    if mFlag is TJSONBool then
    begin
      mOptions.Exceptions := TJSONBool(mFlag).AsBoolean;
    end;
    mFlag := mSettings.GetValue('loops');
    if mFlag is TJSONBool then
    begin
      mOptions.Loops := TJSONBool(mFlag).AsBoolean;
    end;
  end;
  mFileName := TDocumentUris.ToPath(mUri);
  mShared := TSyntaxTreeCache.Get(mDocument);
  mLines := TTextLines.SplitLines(mDocument.Text);
  mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    mResolver.Namespaces := ANamespaces;
    Result := Json(TExitPoints.Find(mShared.Tree, TLspPositions.ReadPosition(AArguments.Items[1]), mOptions,
      ExceptionLookup(mResolver, mShared.Tree, mFileName, mLines, TLspDocumentation.Reader(mFileName, mDocument.Text,
      AReaders.ReadText)), ClassTest(mResolver, mShared.Tree, mFileName)));
  finally
    mResolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ExitPoints', cTexts);

end.
