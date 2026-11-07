unit Atlas.Common.Lsp.EnumValueCommands;

// Befehl zu „Muster fortsetzen“ (#671) für workspace/executeCommand:
//   atlas.server.enumValues [uri, position]: alle Werte des Aufzählungstyps,
//     zu dem der Wert an der Stelle gehört, in Deklarationsreihenfolge, als
//     Array von Strings; leer, wenn dort kein Aufzählungswert steht. Das Plugin
//     fragt so nach Typen, die nicht in der offenen Datei deklariert sind
//     (TAlign aus Vcl.Controls).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  TEnumValueCommands = class
  public const
    cCommand = 'atlas.server.enumValues';
  public
    /// <summary>Befehl atlas.server.enumValues mit den Argumenten URI und Position {line, character}.</summary>
    class function Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReadText: TCompletionReadText;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Completion.Values,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEnumValueCommandsText = (URIAndPositionExpected, DocumentIsNotOpen);

const
  cTexts: array[TEnumValueCommandsText] of TAtlasText = (
    (De: 'Erwartet werden URI und Position'; En: 'URI and position expected'),
    (De: 'Dokument ist nicht geöffnet: '; En: 'Document is not open: '));

{$SCOPEDENUMS OFF}

class function TEnumValueCommands.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReadText: TCompletionReadText;
  const AArguments: TJSONArray): TJSONValue;
var
  mUri, mValue: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mValues: TArray<string>;
  mAnswer: TJSONArray;
  mLookup: TEnumLookup;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TEnumValueCommandsText.URIAndPositionExpected].Text);
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TEnumValueCommandsText.DocumentIsNotOpen].Text +
      mUri);
  end;
  mShared := TSyntaxTreeCache.Get(mDocument);
  mValues := nil;
  mResolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    mResolver.Namespaces := ANamespaces;
    mLookup.Resolver := mResolver;
    mLookup.Index := AIndex;
    mLookup.Tree := mShared.Tree;
    mLookup.Text := mDocument.Text;
    mLookup.FileName := TDocumentUris.ToPath(mUri);
    mLookup.ReadText := AReadText;
    TCompletionValues.EnumValuesAt(mLookup, TLspPositions.ReadPosition(AArguments.Items[1]), mValues);
  finally
    mResolver.Free;
  end;
  mAnswer := TJSONArray.Create;
  for mValue in mValues do
  begin
    mAnswer.Add(mValue);
  end;
  Result := mAnswer;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.EnumValueCommands', cTexts);

end.
