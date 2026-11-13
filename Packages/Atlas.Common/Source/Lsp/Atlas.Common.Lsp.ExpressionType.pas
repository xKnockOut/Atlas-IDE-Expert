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
//   detail: unknownName der Name, noResult die Routine, unknown der Ausdruck;
//   operator "Operator|links|rechts" (binär) bzw. "Operator||Operand" (unär).
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
  Atlas.Common.Semantics.ExpressionTypes.Contract;

type
  /// <summary>Gefragter Bereich samt Schaltern einer Typabfrage.</summary>
  TExpressionTypeQuery = record
    /// <summary>Markierter Bereich; ohne Markierung sind Anfang und Ende gleich.</summary>
    Range: TTextRange;
    /// <summary>Den kleinsten Ausdruck nehmen, der den Bereich echt umschließt.</summary>
    Expand: Boolean;
    /// <summary>Was die Antwort enthalten soll (Umwandlungen, Wert).</summary>
    Options: TExpressionTypeOptions;
    /// <summary>Abfrage für ARange mit den Standardoptionen.</summary>
    class function Create(const ARange: TTextRange; AExpand: Boolean): TExpressionTypeQuery; static;
  end;

  TLspExpressionType = class
  public const
    cCommand = 'atlas.server.expressionType';
    cErrorNames: array[TExpressionErrorKind] of string = ('', 'noExpression', 'unknownName', 'operator', 'noResult',
      'unknown');
  public
    /// <summary>Antwort für AInfo (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const AInfo: TExpressionTypeInfo): TJSONObject; static;
    /// <summary>Typ des Ausdrucks an AQuery.Range von ATree (Text AText); heftet den Baum für die Dauer an AResolver.
    /// </summary>
    class function Describe(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AIndex: ISymbolIndex; const AQuery: TExpressionTypeQuery): TExpressionTypeInfo; static;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  Atlas.Common.Semantics.ExpressionTypes,
  System.Generics.Collections,
  Atlas.Text.Json,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TExpressionTypeText = (URIAndRangeExpected, DocumentIsNotOpen);

const
  cTexts: array[TExpressionTypeText] of TAtlasText = (
    (De: 'Erwartet werden URI und Bereich'; En: 'URI and range expected'),
    (De: 'Dokument ist nicht geöffnet: '; En: 'Document is not open: '));

{$SCOPEDENUMS OFF}

{ TExpressionTypeQuery }

class function TExpressionTypeQuery.Create(const ARange: TTextRange; AExpand: Boolean): TExpressionTypeQuery;
begin
  Result.Range := ARange;
  Result.Expand := AExpand;
  Result.Options := TExpressionTypeOptions.Default;
end;

{ TLspExpressionType }

class function TLspExpressionType.Json(const AInfo: TExpressionTypeInfo): TJSONObject;
var
  mConversions: TJSONArray;
  mItem, mLocation, mError: TJSONObject;
  mConversion: TExpressionConversion;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AInfo.Range));
  Result.AddPair('expression', AInfo.Expression);
  Result.AddPair('type', AInfo.TypeName);
  Result.AddPair('base', AInfo.BaseName);
  if AInfo.TypeFile <> '' then
  begin
    mLocation := TJSONObject.Create;
    mLocation.AddPair('file', AInfo.TypeFile);
    mLocation.AddPair('line', TJSONNumber.Create(AInfo.TypeLine));
    mLocation.AddPair('character', TJSONNumber.Create(AInfo.TypeCharacter));
    Result.AddPair('location', mLocation);
  end;
  mConversions := TJSONArray.Create;
  Result.AddPair('conversions', mConversions);
  for mConversion in AInfo.Conversions do
  begin
    mItem := TJSONObject.Create;
    mConversions.AddElement(mItem);
    mItem.AddPair('expression', mConversion.Expression);
    mItem.AddPair('from', mConversion.FromType);
    mItem.AddPair('to', mConversion.ToType);
    if mConversion.Kind = TExpressionConversionKind.Convert then
    begin
      mItem.AddPair('kind', 'convert');
    end
    else
    begin
      mItem.AddPair('kind', 'widen');
    end;
  end;
  Result.AddPair('overload', AInfo.Overload);
  if AInfo.HasValue then
  begin
    Result.AddPair('value', TJSONNumber.Create(AInfo.Value));
  end;
  if AInfo.Error <> TExpressionErrorKind.None then
  begin
    mError := TJSONObject.Create;
    mError.AddPair('kind', cErrorNames[AInfo.Error]);
    mError.AddPair('detail', AInfo.ErrorDetail);
    Result.AddPair('error', mError);
  end;
end;

class function TLspExpressionType.Describe(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const AIndex: ISymbolIndex; const AQuery: TExpressionTypeQuery): TExpressionTypeInfo;
var
  mTable: TLineTable;
  mTypes: TExpressionTypes;
begin
  mTable := TLineTable.Build(AText);
  AResolver.PinTree(ATree, AFileName);
  try
    mTypes := TExpressionTypes.Create(AResolver, ATree, AFileName, AText, AIndex, AQuery.Options);
    try
      Result := mTypes.DescribeAt(mTable.OffsetAt(AQuery.Range.StartPos), mTable.OffsetAt(AQuery.Range.EndPos),
        AQuery.Expand);
    finally
      mTypes.Free;
    end;
  finally
    AResolver.UnpinTree;
  end;
end;

/// <summary>Bereich und Schalter aus den Argumenten des Befehls.</summary>
function QueryOf(const AArguments: TJSONArray): TExpressionTypeQuery;
var
  mSettings: TJSONObject;
begin
  Result := TExpressionTypeQuery.Create(TLspPositions.ReadRange(AArguments.Items[1]), False);
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
  begin
    mSettings := TJSONObject(AArguments.Items[2]);
    Result.Expand := TJsonRead.FlagOr(mSettings, 'expand', Result.Expand);
    Result.Options.Conversions := TJsonRead.FlagOr(mSettings, 'conversions', Result.Options.Conversions);
    Result.Options.ConstValue := TJsonRead.FlagOr(mSettings, 'constValue', Result.Options.ConstValue);
  end;
end;

class function TLspExpressionType.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TExpressionTypeText.URIAndRangeExpected].Text);
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TExpressionTypeText.DocumentIsNotOpen].Text +
      mUri);
  end;
  mShared := TSyntaxTreeCache.Get(mDocument);
  mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    mResolver.Namespaces := ANamespaces;
    Result := Json(Describe(mResolver, mShared.Tree, TDocumentUris.ToPath(mUri), mDocument.Text, AIndex,
      QueryOf(AArguments)));
  finally
    mResolver.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ExpressionType', cTexts);

end.
