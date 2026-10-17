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
  Atlas.Common.Lsp.Completion;

type
  TEnumValueCommands = class
  public const
    Command = 'atlas.server.enumValues';
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
  Atlas.Common.Lsp.Positions;

class function TEnumValueCommands.Execute(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>; const AReadText: TCompletionReadText;
  const AArguments: TJSONArray): TJSONValue;
var
  Uri, Value: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Values: TArray<string>;
  Answer: TJSONArray;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Erwartet werden URI und Position');
  Uri := AArguments.Items[0].Value;
  if not AStore.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Dokument ist nicht geöffnet: ' + Uri);
  Shared := TSyntaxTreeCache.Get(Document);
  Values := nil;
  Resolver := TNameResolver.Create(AIndex, AEnsureUnit);
  try
    Resolver.Namespaces := ANamespaces;
    TLspCompletion.EnumValuesAt(Resolver, AIndex, Shared.Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(AArguments.Items[1]), AReadText, Values);
  finally
    Resolver.Free;
  end;
  Answer := TJSONArray.Create;
  for Value in Values do
    Answer.Add(Value);
  Result := Answer;
end;

end.
