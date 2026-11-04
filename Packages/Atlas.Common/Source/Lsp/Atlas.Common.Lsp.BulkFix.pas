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
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.BulkFix;

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
    /// <summary>Korrigiert AFileName; False, wenn die Datei nicht lesbar ist.</summary>
    function RunFile(const AFileName: string; const AFixRules: TArray<string>; const ARequested: string;
      out AResult: TBulkFixFile): Boolean;
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
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.ApplyEdit;

function PathOf(const AText: string): string;
begin
  if StartsText('file:', AText) then
  begin
    Result := TDocumentUris.ToPath(AText);
  end
  else
  begin
    Result := AText;
  end;
end;

function StringsOf(const AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if (mItem is TJSONString) and (Trim(mItem.Value) <> '') then
    begin
      Result := Result + [Trim(mItem.Value)];
    end;
  end;
end;

constructor TLspBulkFix.Create(const AInputFor: TLspBulkFixInputFunc);
begin
  inherited Create;
  FInputFor := AInputFor;
end;

/// <summary>Eintrag einer geänderten oder abgelehnten Datei für die Antwort.</summary>
function FileJson(const AResult: TBulkFixFile): TJSONObject;
var
  mCount: TBulkFixRuleCount;
  mRule: TJSONObject;
  mRules: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AResult.FileName);
  Result.AddPair('fixes', TJSONNumber.Create(AResult.FixCount));
  Result.AddPair('rejected', TJSONBool.Create(AResult.Rejected));
  mRules := TJSONArray.Create;
  Result.AddPair('rules', mRules);
  for mCount in AResult.Applied do
  begin
    mRule := TJSONObject.Create;
    mRule.AddPair('rule', mCount.RuleId);
    mRule.AddPair('count', TJSONNumber.Create(mCount.Count));
    mRules.AddElement(mRule);
  end;
  if AResult.Changed then
  begin
    Result.AddPair('diff', TBulkFix.Diff(ExtractFileName(AResult.FileName), AResult));
    Result.AddPair('edit', TLspApplyEdit.TextEdits(AResult.FileName, TTextChanges.Diff(AResult.OldText,
      AResult.NewText)));
  end;
end;

/// <summary>Antwort mit Zusammenfassung und den geänderten oder abgelehnten Dateien.</summary>
function AnswerJson(const AResults: TArray<TBulkFixFile>): TJSONObject;
var
  mResult: TBulkFixFile;
  mItems: TJSONArray;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('summary', TBulkFix.Summary(AResults, True, sLineBreak));
    mItems := TJSONArray.Create;
    Result.AddPair('files', mItems);
    for mResult in AResults do
    begin
      if mResult.Changed or mResult.Rejected then
      begin
        mItems.AddElement(FileJson(mResult));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspBulkFix.RunFile(const AFileName: string; const AFixRules: TArray<string>; const ARequested: string;
  out AResult: TBulkFixFile): Boolean;
var
  mInput: TLspBulkFixInput;
  mConfidence: TRuleConfidence;
  mError: string;
  mOptions: TBulkFixOptions;
begin
  Result := Assigned(FInputFor) and FInputFor(AFileName, mInput);
  if not Result then
  begin
    Exit;
  end;
  if not TBulkFix.MinConfidenceOf(mInput.Settings.FixMinConfidence, ARequested, mConfidence, mError) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, mError);
  end;
  mOptions := TBulkFixOptions.Create(AFixRules, mConfidence, TRuleCatalog.Shared.Entries);
  AResult := TBulkFix.Run(AFileName, mInput.Text, mOptions, TBulkFix.CheckWith(TBulkFix.RulesFor(mInput.Rules,
    AFixRules), mInput.Settings, mInput.RelativePath, mInput.Project, mInput.Source, mInput.Baseline),
    TBulkFix.SyntaxErrorsWith(mInput.Source));
end;

function TLspBulkFix.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mArguments: TJSONObject;
  mFixRules: TArray<string>;
  mRequested, mName: string;
  mResult: TBulkFixFile;
  mResults: TArray<TBulkFixFile>;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Argumente: [{"rules": [...], "files": [...], "minConfidence": "high"}]');
  end;
  mArguments := TJSONObject(AArguments.Items[0]);
  mFixRules := StringsOf(mArguments.GetValue('rules'));
  if mFixRules = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, '"rules" fehlt: Regelkennungen oder "all"');
  end;
  mRequested := '';
  if mArguments.GetValue('minConfidence') is TJSONString then
  begin
    mRequested := mArguments.GetValue('minConfidence').Value;
  end;
  mResults := nil;
  for mName in StringsOf(mArguments.GetValue('files')) do
  begin
    if RunFile(PathOf(mName), mFixRules, mRequested, mResult) then
    begin
      mResults := mResults + [mResult];
    end;
  end;
  Result := AnswerJson(mResults);
end;

end.
