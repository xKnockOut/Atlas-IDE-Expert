unit Atlas.Common.Lsp.Recursion;

// Befehl atlas.server.recursion (#623): Rekursionssymbole im Editorrand des
// IDE-Plugins.
// Argumente: [uri, depth]
//   - depth: höchstens so viele Routinen auf einem Kreis
//     (editor.recursionMarkers.depth, Vorgabe 4, begrenzt auf 1..16).
// Antwort (Zeilen und Zeichen ab 0 wie im Protokoll):
//   {"calls": [{"line": 12, "character": 4, "endCharacter": 11,
//               "text": "Speichern → Pruefen → Speichern",
//               "chain": [{"name": "TFoo.Speichern", "line": 30, "character": 15}, …]}]}
// Die Analyse steht in Atlas.Common.Semantics.Recursion; der Text kommt aus
// dem offenen Dokument oder von der Platte.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.Recursion;

type
  /// <summary>Text einer Datei (offenes Dokument oder Platte); False, wenn sie fehlt.</summary>
  TLspRecursionReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TLspRecursion = class
  public const
    Command = 'atlas.server.recursion';
  private
    FReadText: TLspRecursionReadText;
  public
    constructor Create(const AReadText: TLspRecursionReadText);
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Antwort für ATree (siehe Kopf der Unit).</summary>
    class function Json(ATree: TSyntaxTree; ADepth: Integer): TJSONObject; static;
  end;

implementation

uses
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache;

{ TLspRecursion }

constructor TLspRecursion.Create(const AReadText: TLspRecursionReadText);
begin
  inherited Create;
  FReadText := AReadText;
end;

class function TLspRecursion.Json(ATree: TSyntaxTree; ADepth: Integer): TJSONObject;
var
  Calls, Chain: TJSONArray;
  Item, Step: TJSONObject;
  Call: TRecursiveCall;
  Link: TRecursionStep;
begin
  Result := TJSONObject.Create;
  Calls := TJSONArray.Create;
  Result.AddPair('calls', Calls);
  for Call in TRecursionAnalysis.Calls(ATree, ADepth) do
  begin
    Item := TJSONObject.Create;
    Calls.AddElement(Item);
    Item.AddPair('line', TJSONNumber.Create(Call.Range.StartPos.Line));
    Item.AddPair('character', TJSONNumber.Create(Call.Range.StartPos.Character));
    Item.AddPair('endCharacter', TJSONNumber.Create(Call.Range.EndPos.Character));
    Item.AddPair('text', TRecursionAnalysis.ChainText(Call));
    Chain := TJSONArray.Create;
    Item.AddPair('chain', Chain);
    for Link in Call.Chain do
    begin
      Step := TJSONObject.Create;
      Chain.AddElement(Step);
      Step.AddPair('name', Link.Name);
      Step.AddPair('line', TJSONNumber.Create(Link.Range.StartPos.Line));
      Step.AddPair('character', TJSONNumber.Create(Link.Range.StartPos.Character));
    end;
  end;
end;

function TLspRecursion.Execute(const AArguments: TJSONArray): TJSONValue;
var
  FileName, Text: string;
  Depth: Integer;
  Tree: TSyntaxTree;
begin
  FileName := '';
  Depth := TRecursionAnalysis.DefaultDepth;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONNumber) then
    Depth := TJSONNumber(AArguments.Items[1]).AsInt;
  if (FileName = '') or not Assigned(FReadText) or not FReadText(FileName, Text) then
  begin
    Result := TJSONObject.Create(TJSONPair.Create('calls', TJSONArray.Create));
    Exit;
  end;
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Result := Json(Tree, Depth);
  finally
    Tree.Free;
  end;
end;

end.
