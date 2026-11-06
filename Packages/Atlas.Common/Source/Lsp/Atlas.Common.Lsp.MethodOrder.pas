unit Atlas.Common.Lsp.MethodOrder;

// Befehl atlas.server.methodOrder (#660): Methodenrümpfe im
// implementation-Teil in Deklarationsreihenfolge.
// Argumente: [uri, {mode: "grouped"|"declaration"|"alphabetical"|"off",
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
// Lebenszyklus zuerst und Form des Typkommentars (classCompletion.*, #1834)
// liefert die Komposition je Datei.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.MethodOrder;

type
  /// <summary>Einstellungen zum Ordnen je Datei (#1834); die Ordnung selbst kommt aus "mode".</summary>
  TMethodOrderOptionsFunc = reference to function(const AUri: string): TMethodOrderOptions;

  TLspMethodOrder = class
  public const
    Command = 'atlas.server.methodOrder';
  public
    /// <summary>Antwort für AResult (siehe Kopf der Unit); der Aufrufer übernimmt das Objekt.</summary>
    class function Json(const AResult: TMethodOrderResult): TJSONObject; static;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    class function Execute(const AStore: IDocumentStore; const AArguments: TJSONArray): TJSONValue; overload;
      static;
    /// <summary>Wie oben mit den Einstellungen AOptionsFor der Datei; nil = ohne Vorziehen und neuen Kommentar.
    /// </summary>
    class function Execute(const AStore: IDocumentStore; const AOptionsFor: TMethodOrderOptionsFunc;
      const AArguments: TJSONArray): TJSONValue; overload; static;
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

type
  /// <summary>Argumente hinter der URI.</summary>
  TMethodOrderArguments = record
    Mode, Scope, Before: string;
    class function Read(const AArguments: TJSONArray): TMethodOrderArguments; static;
  end;

class function TMethodOrderArguments.Read(const AArguments: TJSONArray): TMethodOrderArguments;
var
  mOptions: TJSONObject;
begin
  Result.Mode := '';
  Result.Scope := 'all';
  Result.Before := '';
  if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
  begin
    mOptions := TJSONObject(AArguments.Items[1]);
    if not mOptions.TryGetValue<string>('mode', Result.Mode) then
    begin
      Result.Mode := '';
    end;
    if not mOptions.TryGetValue<string>('scope', Result.Scope) then
    begin
      Result.Scope := 'all';
    end;
    if not mOptions.TryGetValue<string>('before', Result.Before) then
    begin
      Result.Before := '';
    end;
  end;
end;

class function TLspMethodOrder.Execute(const AStore: IDocumentStore; const AArguments: TJSONArray): TJSONValue;
begin
  Result := Execute(AStore, nil, AArguments);
end;

class function TLspMethodOrder.Execute(const AStore: IDocumentStore; const AOptionsFor: TMethodOrderOptionsFunc;
  const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mArguments: TMethodOrderArguments;
  mOptions: TMethodOrderOptions;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mAnswer: TMethodOrderResult;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TMethodOrderText.TheURIIsExpected].Text);
  end;
  mUri := AArguments.Items[0].Value;
  if not AStore.TryGet(mUri, mDocument) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TMethodOrderText.DocumentIsNotOpen].Text + mUri);
  end;
  mArguments := TMethodOrderArguments.Read(AArguments);
  mOptions := TMethodOrderOptions.Create(TMethodOrder.PlacementOf(mArguments.Mode));
  if Assigned(AOptionsFor) then
  begin
    mOptions := AOptionsFor(mUri);
    mOptions.Placement := TMethodOrder.PlacementOf(mArguments.Mode);
  end;
  mAnswer := Default(TMethodOrderResult);
  if mOptions.Placement <> TMethodPlacement.Off then
  begin
    mShared := TSyntaxTreeCache.Get(mDocument);
    if SameText(mArguments.Scope, 'new') then
    begin
      mAnswer := TMethodOrder.PlaceNew(mShared.Tree, mDocument.Text, mArguments.Before, mOptions);
    end
    else
    begin
      mAnswer := TMethodOrder.Arrange(mShared.Tree, mDocument.Text, mOptions);
    end;
  end;
  Result := Json(mAnswer);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MethodOrder', cTexts);

end.
