unit Atlas.Common.Lsp.BulkFix;

// Sammelkorrektur für das IDE-Plugin (#1352), Fenster Atlas-Prüfung „Alle
// sicheren Treffer korrigieren …“.
//
// Befehl atlas.server.fixFindings über workspace/executeCommand:
//   Argumente [{"rules": ["unused-uses"] oder ["all"], "files": [Pfad oder
//   URI, …], "minConfidence": "high" | "medium" (optional; nie unter
//   fix.minConfidence der Datei)}].
//   Korrigiert jede Datei wie AtlasServer --check --fix (TBulkFix: Konfidenz,
//   Katalogfeld safeFix, bis zu drei Durchgänge, keine neuen Syntaxfehler)
//   mit dem Text des Editors (offene Dokumente vor der Platte) und schreibt
//   nichts. Treffer der Baseline (#97) bleiben, wie im Editor ausgeblendet.
//   Antwort {"summary": Text wie auf stderr des Linters, "files": [{"file":
//   Pfad, "fixes": n, "rules": [{"rule", "count"}], "rejected": false,
//   "diff": vereinigter Diff, "edit": WorkspaceEdit}]} nur mit Dateien, die
//   sich ändern oder verworfen wurden (dann ohne "diff" und "edit"). Das
//   Plugin zeigt die Vorschau und wendet die gewählten Edits an, ein
//   Rückgängig-Schritt je Datei (#397).
// Die Korrektur selbst rechnen die Prüfregeln über ILspBulkFix (der Host verbindet die Sammelkorrektur der Regeln,
// Text, Regeln, Einstellungen, Projekt und Baseline je Datei wie im Editor); Tests ohne Platte und Server.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Contract;

type
  TLspBulkFix = class
  public const
    cCommand = 'atlas.server.fixFindings';
  private
    FBulkFix: ILspBulkFix;
  public
    /// <summary>ABulkFix korrigiert die Dateien; nil = keine Dateien in der Antwort.</summary>
    constructor Create(const ABulkFix: ILspBulkFix);
    /// <summary>Befehl atlas.server.fixFindings; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.TextChanges,
  Atlas.Common.JsonRpc.ApplyEdit,
  System.Generics.Collections,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBulkFixText = (RulesMissingRuleIdsOr, ArgumentsRulesFilesMinConfidenceHigh);

const
  cTexts: array[TBulkFixText] of TAtlasText = (
    (De: '"rules" fehlt: Regelkennungen oder "all"'; En: '"rules" missing: rule ids or "all"'),
    (De: 'Argumente: [{"rules": [...], "files": [...], "minConfidence": "high"}]';
     En: 'Arguments: [{"rules": [...], "files": [...], "minConfidence": "high"}]'));

{$SCOPEDENUMS OFF}

{ TLspBulkFix }

constructor TLspBulkFix.Create(const ABulkFix: ILspBulkFix);
begin
  inherited Create;
  FBulkFix := ABulkFix;
end;

/// <summary>Eintrag einer geänderten oder abgelehnten Datei für die Antwort.</summary>
function FileJson(const AFile: TLspBulkFixFile): TJSONObject;
var
  mCount: TLspBulkFixCount;
  mRule: TJSONObject;
  mRules: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AFile.FileName);
  Result.AddPair('fixes', TJSONNumber.Create(AFile.FixCount));
  Result.AddPair('rejected', TJSONBool.Create(AFile.Rejected));
  mRules := TJSONArray.Create;
  Result.AddPair('rules', mRules);
  for mCount in AFile.Applied do
  begin
    mRule := TJSONObject.Create;
    mRule.AddPair('rule', mCount.RuleId);
    mRule.AddPair('count', TJSONNumber.Create(mCount.Count));
    mRules.AddElement(mRule);
  end;
  if AFile.Changed then
  begin
    Result.AddPair('diff', AFile.Diff);
    Result.AddPair('edit', TApplyEdit.TextEdits(AFile.FileName, TTextChanges.Diff(AFile.OldText,
      AFile.NewText)));
  end;
end;

/// <summary>Antwort mit Zusammenfassung und den geänderten oder abgelehnten Dateien.</summary>
function AnswerJson(const ARun: TLspBulkFixRun): TJSONObject;
var
  mFile: TLspBulkFixFile;
  mItems: TJSONArray;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('summary', ARun.Summary);
    mItems := TJSONArray.Create;
    Result.AddPair('files', mItems);
    for mFile in ARun.Files do
    begin
      if mFile.Changed or mFile.Rejected then
      begin
        mItems.AddElement(FileJson(mFile));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspBulkFix.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mArguments: TJSONObject;
  mFixRules, mFiles: TArray<string>;
  mRequested, mName, mError: string;
  mRun: TLspBulkFixRun;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TBulkFixText.ArgumentsRulesFilesMinConfidenceHigh].Text);
  end;
  mArguments := TJSONObject(AArguments.Items[0]);
  mFixRules := TJsonRead.TrimmedStrings(mArguments.GetValue('rules'));
  if mFixRules = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TBulkFixText.RulesMissingRuleIdsOr].Text);
  end;
  mRequested := '';
  if mArguments.GetValue('minConfidence') is TJSONString then
  begin
    mRequested := mArguments.GetValue('minConfidence').Value;
  end;
  mFiles := nil;
  for mName in TJsonRead.TrimmedStrings(mArguments.GetValue('files')) do
  begin
    mFiles := mFiles + [TDocumentUris.PathOrSelf(mName)];
  end;
  mRun := Default(TLspBulkFixRun);
  if (FBulkFix <> nil) and not FBulkFix.Run(mFiles, mFixRules, mRequested, mRun, mError) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mError);
  end;
  Result := AnswerJson(mRun);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.BulkFix', cTexts);

end.
