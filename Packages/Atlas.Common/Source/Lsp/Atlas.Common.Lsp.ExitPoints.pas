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
    Command = 'atlas.server.exitPoints';
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
  KindNames: array[TExitPointKind] of string = ('exit', 'raise', 'halt', 'call', 'end', 'result', 'source',
    'handler', 'loop', 'jump');
  QueryNames: array[TExitPointQuery] of string = ('', 'routine', 'result', 'exceptions', 'loop');

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
  Result := KindNames[AKind];
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
  Points: TJSONArray;
  Item, Routine: TJSONObject;
  Point: TExitPoint;
begin
  Result := TJSONObject.Create;
  Result.AddPair('query', QueryNames[ASet.Query]);
  if ASet.HasRoutine then
  begin
    Routine := RangeJson(ASet.RoutineRange);
    Routine.AddPair('name', ASet.RoutineName);
    Result.AddPair('routine', Routine);
  end;
  Result.AddPair('function', TJSONBool.Create(ASet.IsFunction));
  Result.AddPair('exits', TJSONNumber.Create(ASet.ExitCount));
  Result.AddPair('resultMissing', TJSONBool.Create(ASet.ResultMissing));
  Points := TJSONArray.Create;
  Result.AddPair('points', Points);
  for Point in ASet.Points do
  begin
    Item := RangeJson(Point.Range);
    Item.AddPair('kind', KindNames[Point.Kind]);
    Item.AddPair('resultMissing', TJSONBool.Create(Point.ResultMissing));
    Item.AddPair('detail', Point.Detail);
    Item.AddPair('exception', Point.ExceptionClass);
    Points.AddElement(Item);
  end;
end;

class function TLspExitPoints.ExceptionLookup(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const ALines: TArray<string>; const AReadText: TDocReadText): TExitPointExceptionLookup;
var
  Own: TExitPointExceptionLookup;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  FileName: string;
  Reader: TDocReadText;
begin
  Own := TExitPoints.TreeExceptions(ATree, ALines);
  Resolver := AResolver;
  Tree := ATree;
  FileName := AFileName;
  Reader := AReadText;
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
      Result := Own(ACallee);
      if (Result <> nil) or (Resolver = nil) or (ACallee = nil) then
      begin
        Exit;
      end;
      // Name am Ende des Ziels (Bar in Obj.Bar) über die Namensauflösung.
      Tokens := Tree.Tokens;
      Symbol := Default(TResolvedSymbol);
      for Index := High(Tokens) downto 0 do
      begin
        if (Tokens[Index].Offset < ACallee.EndOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
        begin
          Symbol := Resolver.Resolve(Tree, FileName, Tokens[Index].StartPos);
          Break;
        end;
      end;
      if not Symbol.Found or (Symbol.FileName = '') or not Assigned(Reader) or
        not Reader(Symbol.FileName, Text) then
      begin
        Exit;
      end;
      Lines := TTextLines.SplitLines(Text);
      Doc := TLspDocumentation.Load(Resolver, Symbol, Lines, Symbol.Range.StartPos.Line, Reader);
      for Entry in Doc.Exceptions do
      begin
        Result := Result + [TXmlDoc.NormalizeCref(Entry.Name)];
      end;
    end;
end;

class function TLspExitPoints.ClassTest(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TExitPointClassTest;
var
  Own: TExitPointClassTest;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  FileName: string;
begin
  Own := TExitPoints.TreeClassTest(ATree);
  Resolver := AResolver;
  Tree := ATree;
  FileName := AFileName;
  Result :=
    function(const AClass, AHandler: string; AOffset: Integer): Boolean
    begin
      Result := Own(AClass, AHandler, AOffset) or
        ((Resolver <> nil) and Resolver.Queries.TypeDescendsFrom(Tree, FileName, AOffset, AClass, AHandler));
    end;
end;

class function TLspExitPoints.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReaders: TExitPointsReaders;
  const AArguments: TJSONArray): TJSONValue;
var
  Uri, FileName: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Options: TExitPointOptions;
  Settings: TJSONObject;
  Lines: TArray<string>;
  Flag: TJSONValue;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TExitPointsText.URIAndPositionExpected].Text);
  end;
  Uri := AArguments.Items[0].Value;
  if not AStore.TryGet(Uri, Document) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TExitPointsText.DocumentIsNotOpen].Text + Uri);
  end;
  Options := TExitPointOptions.Default;
  if Assigned(AReaders.SettingsFor) then
  begin
    Options.Keywords := AReaders.SettingsFor(Uri).ExitKeywords;
  end
  else
  begin
    Options.Keywords := THighlightSettings.Default.ExitKeywords;
  end;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
  begin
    Settings := TJSONObject(AArguments.Items[2]);
    Flag := Settings.GetValue('exceptions');
    if Flag is TJSONBool then
    begin
      Options.Exceptions := TJSONBool(Flag).AsBoolean;
    end;
    Flag := Settings.GetValue('loops');
    if Flag is TJSONBool then
    begin
      Options.Loops := TJSONBool(Flag).AsBoolean;
    end;
  end;
  FileName := TDocumentUris.ToPath(Uri);
  Shared := TSyntaxTreeCache.Get(Document);
  Lines := TTextLines.SplitLines(Document.Text);
  Resolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    Resolver.Namespaces := ANamespaces;
    Result := Json(TExitPoints.Find(Shared.Tree, TLspPositions.ReadPosition(AArguments.Items[1]), Options,
      ExceptionLookup(Resolver, Shared.Tree, FileName, Lines, TLspDocumentation.Reader(FileName, Document.Text,
      AReaders.ReadText)), ClassTest(Resolver, Shared.Tree, FileName)));
  finally
    Resolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ExitPoints', cTexts);

end.
