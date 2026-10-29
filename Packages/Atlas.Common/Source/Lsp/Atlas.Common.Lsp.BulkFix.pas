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
// Regeln, Einstellungen, Projekt und Symbole je Datei kommen von außen
// (Komposition des Servers; Tests ohne Platte und Server).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Checker;

type
  /// <summary>Was die Sammelkorrektur für eine Datei braucht.</summary>
  TLspBulkFixInput = record
    Rules: TArray<IRule>;
    Settings: TServerSettings;
    /// <summary>Pfad relativ zum Ordner der Konfiguration (Ausschlüsse, Baseline).</summary>
    RelativePath: string;
    /// <summary>Aktueller Text (Editor vor Platte).</summary>
    Text: string;
    Project: TCheckProject;
    Source: TCheckSource;
    /// <summary>nil = keine Baseline.</summary>
    Baseline: IRuleBaseline;
  end;

  /// <summary>Eingaben für AFileName; False = Datei nicht lesbar, sie fehlt in der Antwort.</summary>
  TLspBulkFixInputFunc = reference to function(const AFileName: string; out AInput: TLspBulkFixInput): Boolean;

  TLspBulkFix = class
  public const
    Command = 'atlas.server.fixFindings';
  private
    FInputFor: TLspBulkFixInputFunc;
  public
    constructor Create(const AInputFor: TLspBulkFixInputFunc);
    /// <summary>Befehl atlas.server.fixFindings; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.BulkFix,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.ApplyEdit;

function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
    Result := TDocumentUris.ToPath(AText)
  else
    Result := AText;
end;

function StringsOf(const AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for mItem in TJSONArray(AValue) do
    if (mItem is TJSONString) and (Trim(mItem.Value) <> '') then
      Result := Result + [Trim(mItem.Value)];
end;

constructor TLspBulkFix.Create(const AInputFor: TLspBulkFixInputFunc);
begin
  inherited Create;
  FInputFor := AInputFor;
end;

function TLspBulkFix.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mArguments: TJSONObject;
  mFixRules, mFiles: TArray<string>;
  mRequested, mError, mFileName, mName: string;
  mInput: TLspBulkFixInput;
  mConfidence: TRuleConfidence;
  mOptions: TBulkFixOptions;
  mResult: TBulkFixFile;
  mResults: TArray<TBulkFixFile>;
  mCount: TBulkFixRuleCount;
  mAnswer, mItem, mRule: TJSONObject;
  mItems, mRules: TJSONArray;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Argumente: [{"rules": [...], "files": [...], "minConfidence": "high"}]');
  mArguments := TJSONObject(AArguments.Items[0]);
  mFixRules := StringsOf(mArguments.GetValue('rules'));
  if mFixRules = nil then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"rules" fehlt: Regelkennungen oder "all"');
  mFiles := StringsOf(mArguments.GetValue('files'));
  mRequested := '';
  if mArguments.GetValue('minConfidence') is TJSONString then
    mRequested := mArguments.GetValue('minConfidence').Value;
  mResults := nil;
  for mName in mFiles do
  begin
    mFileName := PathOf(mName);
    if not Assigned(FInputFor) or not FInputFor(mFileName, mInput) then
      Continue;
    if not TBulkFix.MinConfidenceOf(mInput.Settings.FixMinConfidence, mRequested, mConfidence, mError) then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, mError);
    mOptions := TBulkFixOptions.Create(mFixRules, mConfidence, TRuleCatalog.Shared.Entries);
    mResult := TBulkFix.Run(mFileName, mInput.Text, mOptions, TBulkFix.CheckWith(TBulkFix.RulesFor(mInput.Rules,
      mFixRules), mInput.Settings, mInput.RelativePath, mInput.Project, mInput.Source, mInput.Baseline),
      TBulkFix.SyntaxErrorsWith(mInput.Source));
    mResults := mResults + [mResult];
  end;
  mAnswer := TJSONObject.Create;
  try
    mAnswer.AddPair('summary', TBulkFix.Summary(mResults, True, sLineBreak));
    mItems := TJSONArray.Create;
    mAnswer.AddPair('files', mItems);
    for mResult in mResults do
    begin
      if not mResult.Changed and not mResult.Rejected then
        Continue;
      mItem := TJSONObject.Create;
      mItems.AddElement(mItem);
      mItem.AddPair('file', mResult.FileName);
      mItem.AddPair('fixes', TJSONNumber.Create(mResult.FixCount));
      mItem.AddPair('rejected', TJSONBool.Create(mResult.Rejected));
      mRules := TJSONArray.Create;
      mItem.AddPair('rules', mRules);
      for mCount in mResult.Applied do
      begin
        mRule := TJSONObject.Create;
        mRule.AddPair('rule', mCount.RuleId);
        mRule.AddPair('count', TJSONNumber.Create(mCount.Count));
        mRules.AddElement(mRule);
      end;
      if not mResult.Changed then
        Continue;
      mItem.AddPair('diff', TBulkFix.Diff(ExtractFileName(mResult.FileName), mResult));
      mItem.AddPair('edit', TLspApplyEdit.TextEdits(mResult.FileName, TTextChanges.Diff(mResult.OldText,
        mResult.NewText)));
    end;
  except
    mAnswer.Free;
    raise;
  end;
  Result := mAnswer;
end;

end.
