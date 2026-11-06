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
    cCommand = 'atlas.server.recursion';
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
  System.Generics.Collections,
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
  mCalls, mChain: TJSONArray;
  mItem, mStep: TJSONObject;
  mCall: TRecursiveCall;
  mLink: TRecursionStep;
begin
  Result := TJSONObject.Create;
  mCalls := TJSONArray.Create;
  Result.AddPair('calls', mCalls);
  for mCall in TRecursionAnalysis.Calls(ATree, ADepth) do
  begin
    mItem := TJSONObject.Create;
    mCalls.AddElement(mItem);
    mItem.AddPair('line', TJSONNumber.Create(mCall.Range.StartPos.Line));
    mItem.AddPair('character', TJSONNumber.Create(mCall.Range.StartPos.Character));
    mItem.AddPair('endCharacter', TJSONNumber.Create(mCall.Range.EndPos.Character));
    mItem.AddPair('text', TRecursionAnalysis.ChainText(mCall));
    mChain := TJSONArray.Create;
    mItem.AddPair('chain', mChain);
    for mLink in mCall.Chain do
    begin
      mStep := TJSONObject.Create;
      mChain.AddElement(mStep);
      mStep.AddPair('name', mLink.Name);
      mStep.AddPair('line', TJSONNumber.Create(mLink.Range.StartPos.Line));
      mStep.AddPair('character', TJSONNumber.Create(mLink.Range.StartPos.Character));
    end;
  end;
end;

function TLspRecursion.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mFileName, mText: string;
  mDepth: Integer;
  mTree: TSyntaxTree;
begin
  mFileName := '';
  mDepth := TRecursionAnalysis.cDefaultDepth;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mFileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONNumber) then
  begin
    mDepth := TJSONNumber(AArguments.Items[1]).AsInt;
  end;
  if (mFileName = '') or not Assigned(FReadText) or not FReadText(mFileName, mText) then
  begin
    Result := TJSONObject.Create(TJSONPair.Create('calls', TJSONArray.Create));
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := Json(mTree, mDepth);
  finally
    mTree.Free;
  end;
end;

end.
