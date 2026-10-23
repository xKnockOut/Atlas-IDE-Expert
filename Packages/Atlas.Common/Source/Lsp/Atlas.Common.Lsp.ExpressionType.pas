unit Atlas.Common.Lsp.ExpressionType;

// Befehl atlas.server.expressionType (#689): Typ des markierten Ausdrucks für
// das Tastenkürzel „Typ des Ausdrucks“ im IDE-Plugin.
// Argumente: [uri, {start: {line, character}, end: {line, character}},
//             {expand, conversions, constValue}]
//   - Ohne Markierung sind start und end gleich (Cursor); dann gilt der
//     kleinste vollständige Ausdruck dort.
//   - expand: der kleinste Ausdruck, der den Bereich echt umschließt (erneutes
//     Drücken im Plugin); conversions und constValue wie
//     hints.expressionType.conversions bzw. .constValue (fehlen sie: true).
// Antwort (Zeilen und Zeichen ab 0 wie im Protokoll):
//   {"range": {...}, "expression": "Price * Count + Shipping",
//    "type": "Currency", "base": "", "location": {"file", "line", "character"},
//    "conversions": [{"expression": "Count", "from": "Integer", "to": "Currency",
//                     "kind": "widen" | "convert"}],
//    "overload": "function Max(A, B: Double): Double;", "value": 48,
//    "error": {"kind": "noExpression" | "unknownName" | "operator" |
//              "noResult" | "unknown", "detail": "…"}}
// "location", "value" und "error" fehlen ohne Angabe. Die Analyse steht in
// Atlas.Common.Semantics.ExpressionTypes.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpressionTypes;

type
  TLspExpressionType = class
  public const
    Command = 'atlas.server.expressionType';
    ErrorNames: array[TExpressionErrorKind] of string = ('', 'noExpression', 'unknownName', 'operator', 'noResult',
      'unknown');
  public
    /// <summary>Antwort für AInfo (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const AInfo: TExpressionTypeInfo): TJSONObject; static;
    /// <summary>Typ des Ausdrucks an ARange von ATree (Text AText); heftet den Baum für die Dauer an AResolver.
    /// </summary>
    class function Describe(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AIndex: ISymbolIndex; const ARange: TTextRange; AExpand: Boolean;
      const AOptions: TExpressionTypeOptions): TExpressionTypeInfo; static;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Positions;

{ TLspExpressionType }

class function TLspExpressionType.Json(const AInfo: TExpressionTypeInfo): TJSONObject;
var
  Conversions: TJSONArray;
  Item, Location, Error: TJSONObject;
  Conversion: TExpressionConversion;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AInfo.Range));
  Result.AddPair('expression', AInfo.Expression);
  Result.AddPair('type', AInfo.TypeName);
  Result.AddPair('base', AInfo.BaseName);
  if AInfo.TypeFile <> '' then
  begin
    Location := TJSONObject.Create;
    Location.AddPair('file', AInfo.TypeFile);
    Location.AddPair('line', TJSONNumber.Create(AInfo.TypeLine));
    Location.AddPair('character', TJSONNumber.Create(AInfo.TypeCharacter));
    Result.AddPair('location', Location);
  end;
  Conversions := TJSONArray.Create;
  Result.AddPair('conversions', Conversions);
  for Conversion in AInfo.Conversions do
  begin
    Item := TJSONObject.Create;
    Conversions.AddElement(Item);
    Item.AddPair('expression', Conversion.Expression);
    Item.AddPair('from', Conversion.FromType);
    Item.AddPair('to', Conversion.ToType);
    if Conversion.Kind = TExpressionConversionKind.Convert then
      Item.AddPair('kind', 'convert')
    else
      Item.AddPair('kind', 'widen');
  end;
  Result.AddPair('overload', AInfo.Overload);
  if AInfo.HasValue then
    Result.AddPair('value', TJSONNumber.Create(AInfo.Value));
  if AInfo.Error <> TExpressionErrorKind.None then
  begin
    Error := TJSONObject.Create;
    Error.AddPair('kind', ErrorNames[AInfo.Error]);
    Error.AddPair('detail', AInfo.ErrorDetail);
    Result.AddPair('error', Error);
  end;
end;

class function TLspExpressionType.Describe(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const AIndex: ISymbolIndex; const ARange: TTextRange; AExpand: Boolean;
  const AOptions: TExpressionTypeOptions): TExpressionTypeInfo;
var
  Table: TLineTable;
  Types: TExpressionTypes;
begin
  Table := TLineTable.Build(AText);
  AResolver.PinTree(ATree, AFileName);
  try
    Types := TExpressionTypes.Create(AResolver, ATree, AFileName, AText, AIndex, AOptions);
    try
      Result := Types.DescribeAt(Table.OffsetAt(ARange.StartPos), Table.OffsetAt(ARange.EndPos), AExpand);
    finally
      Types.Free;
    end;
  finally
    AResolver.UnpinTree;
  end;
end;

class function TLspExpressionType.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Options: TExpressionTypeOptions;
  Settings: TJSONObject;
  Flag: TJSONValue;
  Expand: Boolean;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet werden URI und Bereich');
  Uri := AArguments.Items[0].Value;
  if not AStore.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Dokument ist nicht geöffnet: ' + Uri);
  Options := TExpressionTypeOptions.Default;
  Expand := False;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
  begin
    Settings := TJSONObject(AArguments.Items[2]);
    Flag := Settings.GetValue('expand');
    if Flag is TJSONBool then
      Expand := TJSONBool(Flag).AsBoolean;
    Flag := Settings.GetValue('conversions');
    if Flag is TJSONBool then
      Options.Conversions := TJSONBool(Flag).AsBoolean;
    Flag := Settings.GetValue('constValue');
    if Flag is TJSONBool then
      Options.ConstValue := TJSONBool(Flag).AsBoolean;
  end;
  Shared := TSyntaxTreeCache.Get(Document);
  Resolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    Resolver.Namespaces := ANamespaces;
    Result := Json(Describe(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, AIndex,
      TLspPositions.ReadRange(AArguments.Items[1]), Expand, Options));
  finally
    Resolver.Free;
  end;
end;

end.
