unit Atlas.Common.Lsp.MethodOrder;

// Befehl atlas.server.methodOrder (#660): Methodenrümpfe im
// implementation-Teil in Deklarationsreihenfolge.
// Argumente: [uri, {mode: "declaration"|"alphabetical"|"off",
//                   scope: "all"|"new", before: "…"}]
//   - scope "all" ordnet alle Rümpfe der Unit (Befehl im Plugin),
//   - scope "new" setzt nur die gegenüber "before" neuen Rümpfe an ihre
//     Stelle (nach der Klassenvervollständigung der IDE oder einer
//     Atlas-Aktion).
// Antwort (Zeilen und Zeichen ab 0 wie im Protokoll):
//   {"edits": [{"range": …, "newText": "…"}],
//    "moves": [{"type": "TKunde", "name": "Speichern", "line": 40,
//               "newLine": 22, "size": 4, "delta": -3, "fixed": false,
//               "reason": ""}, …]}
// "line"/"newLine" ist die Kopfzeile vorher/nachher (-1 bei stehen
// bleibenden), "size" die Zahl der Zeilen bis zum end; "delta" zählt Rümpfe
// (negativ = nach oben); "fixed" mit "reason" region, ifdef oder line
// markiert Rümpfe, die stehen bleiben.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.MethodOrder;

type
  TLspMethodOrder = class
  public const
    Command = 'atlas.server.methodOrder';
  public
    /// <summary>Antwort für AResult (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const AResult: TMethodOrderResult): TJSONObject; static;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMethodOrderText = (TheURIIsExpected, DocumentIsNotOpen);

const
  cTexts: array[TMethodOrderText] of TAtlasText = (
    (De: 'Erwartet wird die URI'; En: 'The URI is expected'),
    (De: 'Dokument ist nicht geöffnet: '; En: 'Document is not open: '));

{$SCOPEDENUMS OFF}

{ TLspMethodOrder }

class function TLspMethodOrder.Json(const AResult: TMethodOrderResult): TJSONObject;
var
  Edits, Moves: TJSONArray;
  Edit: TTextEdit;
  Move: TMethodMove;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Edits := TJSONArray.Create;
  Result.AddPair('edits', Edits);
  for Edit in AResult.Edits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Edits.AddElement(Item);
  end;
  Moves := TJSONArray.Create;
  Result.AddPair('moves', Moves);
  for Move in AResult.Moves do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('type', Move.TypeName);
    Item.AddPair('name', Move.Name);
    Item.AddPair('line', TJSONNumber.Create(Move.Line));
    Item.AddPair('newLine', TJSONNumber.Create(Move.NewLine));
    Item.AddPair('size', TJSONNumber.Create(Move.Size));
    Item.AddPair('delta', TJSONNumber.Create(Move.Delta));
    Item.AddPair('fixed', TJSONBool.Create(Move.Fixed));
    Item.AddPair('reason', TMethodOrder.ReasonName(Move.Reason));
    Moves.AddElement(Item);
  end;
end;

class function TLspMethodOrder.Execute(const AStore: IDocumentStore; const AArguments: TJSONArray): TJSONValue;
var
  Uri, Mode, Scope, Before: string;
  Placement: TMethodPlacement;
  Options: TJSONObject;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Answer: TMethodOrderResult;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TMethodOrderText.TheURIIsExpected].Text);
  end;
  Uri := AArguments.Items[0].Value;
  if not AStore.TryGet(Uri, Document) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TMethodOrderText.DocumentIsNotOpen].Text + Uri);
  end;
  Placement := TMethodPlacement.Declaration;
  Scope := 'all';
  Before := '';
  if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
  begin
    Options := TJSONObject(AArguments.Items[1]);
    if Options.TryGetValue<string>('mode', Mode) then
    begin
      Placement := TMethodOrder.PlacementOf(Mode);
    end;
    if not Options.TryGetValue<string>('scope', Scope) then
    begin
      Scope := 'all';
    end;
    if not Options.TryGetValue<string>('before', Before) then
    begin
      Before := '';
    end;
  end;
  Answer := Default(TMethodOrderResult);
  if Placement <> TMethodPlacement.Off then
  begin
    Shared := TSyntaxTreeCache.Get(Document);
    if SameText(Scope, 'new') then
    begin
      Answer := TMethodOrder.PlaceNew(Shared.Tree, Document.Text, Before, Placement);
    end
    else
    begin
      Answer := TMethodOrder.Arrange(Shared.Tree, Document.Text, Placement);
    end;
  end;
  Result := Json(Answer);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MethodOrder', cTexts);

end.
