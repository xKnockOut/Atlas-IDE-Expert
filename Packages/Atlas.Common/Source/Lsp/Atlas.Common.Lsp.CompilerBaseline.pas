unit Atlas.Common.Lsp.CompilerBaseline;

// Compilermeldungen in der Baseline (#530) über workspace/executeCommand.
// Bekannte Warnungen und Hinweise eines Altprojekts kommen in dieselbe
// atlas-baseline.json wie die Regeltreffer (#97); danach zählt das Plugin nur
// neue Meldungen. Zuordnung wie bei den Regeln: Datei, Code, umgebende
// Routine und Fingerabdrücke der Zeile und ihres Kontexts, nicht die
// Zeilennummer (TRuleBaseline, "rule" = Code in Kleinbuchstaben).
//
// atlas.baselineCompilerMessages [uri, meldungen]
//   Übernimmt die Meldungen in die Baseline. Je Datei unter den Meldungen
//   ersetzen sie deren bisherige Compiler-Einträge; Regeltreffer und Einträge
//   anderer Dateien bleiben (ein Make meldet nur neu übersetzte Units).
//   Antwort: {"format": 1, "file": "<voller Pfad>", "previous": "none|valid|invalid",
//     "total": 5, "files": 2, "added": 1, "removed": 0, "unchanged": 4, "skipped": 0}
//   "total" zählt alle Compiler-Einträge der neuen Datei, "skipped" Meldungen,
//   deren Datei nicht lesbar ist oder außerhalb des Arbeitsbereichs liegt.
// atlas.classifyCompilerMessages [uri, meldungen]
//   Antwort: {"format": 1, "baseline": "none|valid|invalid", "baselined": [0, 3]}
//   mit den Positionen der Meldungen, die in der Baseline stehen.
//
// uri: Projekt (.dproj, .dpr, .dpk), Ordner, Datei oder null wie bei
// atlas.updateBaseline. meldungen: [{"file": "<voller Pfad>", "line": 12,
// "code": "W1035"}], Zeile 1-basiert wie in der IDE. Nur Warnungen und
// Hinweise (W…, H…) kommen in die Baseline; Fehler lassen den Build ohnehin
// scheitern. Dateizugriffe kommen von außen (Tests ohne Platte und Server).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Baseline;

type
  /// <summary>Eine Compilermeldung der IDE.</summary>
  TLspCompilerMessage = record
    FileName: string;
    /// <summary>1-basiert; 0 ohne Zeile.</summary>
    Line: Integer;
    Code: string;
  end;

  TLspCompilerBaseline = class
  public const
    cAddCommand = 'atlas.baselineCompilerMessages';
    cClassifyCommand = 'atlas.classifyCompilerMessages';
    cFormatVersion = 1;
  private
    FSourceFor: TLspMetricsSourceFunc;
    FReadText: TLspBaselineRead;
    FFiles: TLspBaselineFiles;
    FOnWritten: TProc<string>;
    function FileIn(const ARoot, AName: string): string;
    function Load(const ARoot: string; out APrevious: string): IRuleBaseline;
    /// <summary>Meldungen je Datei als Baseline-Quellen; AOwner[i] = Quelle der Meldung i bzw. -1, ASlot[i] =
    /// Position unter deren Treffern.</summary>
    function SourcesOf(const ARoot: string; const AMessages: TArray<TLspCompilerMessage>;
      out AOwner, ASlot: TArray<Integer>): TArray<TBaselineSource>;
    function SourceOf(const AArguments: TJSONArray): TLspMetricsSource;
  public
    /// <summary>AReadText liest eine Quelltextdatei (offenes Dokument vor Platte).</summary>
    constructor Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TLspBaselineRead;
      const AFiles: TLspBaselineFiles);
    /// <summary>Meldungen aus dem zweiten Argument; ungültige Einträge fallen weg.</summary>
    class function MessagesOf(const AValue: TJSONValue): TArray<TLspCompilerMessage>; static;
    /// <summary>Kann die Meldung in die Baseline (Warnung oder Hinweis mit Code)?</summary>
    class function Accepts(const AMessage: TLspCompilerMessage): Boolean; static;
    /// <summary>Übernimmt AMessages in die Baseline von ASource.Root; Antwort als JSON-Text.</summary>
    function Add(const ASource: TLspMetricsSource; const AMessages: TArray<TLspCompilerMessage>): string;
    /// <summary>Je Meldung: steht sie in der Baseline? APrevious wie bei Add.</summary>
    function Classify(const ASource: TLspMetricsSource; const AMessages: TArray<TLspCompilerMessage>;
      out APrevious: string): TArray<Boolean>;
    /// <summary>Befehle; der Aufrufer übernimmt das Ergebnis.</summary>
    function ExecuteAdd(const AArguments: TJSONArray): TJSONValue;
    function ExecuteClassify(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Nach dem Schreiben mit dem vollen Pfad der Datei.</summary>
    property OnWritten: TProc<string> read FOnWritten write FOnWritten;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Output,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCompilerBaselineText = (BaselineNotReadableWriteIt, NoWorkspaceFoundForThe, AnswerOfTheBaselineIs);

const
  cTexts: array[TCompilerBaselineText] of TAtlasText = (
    (De: 'Baseline nicht lesbar: erst mit atlas.updateBaseline neu schreiben';
     En: 'Baseline not readable: write it again with atlas.updateBaseline first'),
    (De: 'Kein Arbeitsbereich für die Baseline gefunden'; En: 'No workspace found for the baseline'),
    (De: 'Antwort der Baseline ist kein gültiges JSON'; En: 'Answer of the baseline is not valid JSON'));

{$SCOPEDENUMS OFF}

/// Pfad relativ zu ARoot mit "/", '' außerhalb; Trenner und Groß-/Kleinschreibung zählen nicht.
function RelativeTo(const ARoot, AFileName: string): string;
var
  mRoot, mName: string;
begin
  mRoot := TRuleBaseline.NormalizePath(ARoot);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
  begin
    mRoot := mRoot + '/';
  end;
  mName := TRuleBaseline.NormalizePath(AFileName);
  if (mRoot <> '/') and (Length(mName) > Length(mRoot)) and SameText(Copy(mName, 1, Length(mRoot)), mRoot) then
  begin
    Result := Copy(mName, Length(mRoot) + 1, MaxInt);
  end
  else
  begin
    Result := '';
  end;
end;

{ TLspCompilerBaseline }

constructor TLspCompilerBaseline.Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TLspBaselineRead;
  const AFiles: TLspBaselineFiles);
begin
  inherited Create;
  FSourceFor := ASourceFor;
  FReadText := AReadText;
  FFiles := AFiles;
end;

function TLspCompilerBaseline.FileIn(const ARoot, AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ARoot) + AName;
end;

class function TLspCompilerBaseline.Accepts(const AMessage: TLspCompilerMessage): Boolean;
begin
  Result := (AMessage.FileName <> '') and TRuleBaseline.IsCompilerCode(AMessage.Code) and
    CharInSet(UpCase(AMessage.Code[1]), ['W', 'H']);
end;

class function TLspCompilerBaseline.MessagesOf(const AValue: TJSONValue): TArray<TLspCompilerMessage>;
var
  mItem: TJSONValue;
  mField: TJSONValue;
  mMessage: TLspCompilerMessage;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    mMessage := Default(TLspCompilerMessage);
    if mItem is TJSONObject then
    begin
      mField := TJSONObject(mItem).GetValue('file');
      if mField is TJSONString then
      begin
        mMessage.FileName := mField.Value;
      end;
      mField := TJSONObject(mItem).GetValue('line');
      if mField is TJSONNumber then
      begin
        mMessage.Line := TJSONNumber(mField).AsInt;
      end;
      mField := TJSONObject(mItem).GetValue('code');
      if mField is TJSONString then
      begin
        mMessage.Code := UpperCase(mField.Value);
      end;
    end;
    // Ungültige Einträge bleiben als leere Meldung stehen: Die Positionen der Antwort gelten für die Eingabe.
    Result := Result + [mMessage];
  end;
end;

function TLspCompilerBaseline.Load(const ARoot: string; out APrevious: string): IRuleBaseline;
var
  mFileName, mText: string;
begin
  Result := nil;
  APrevious := 'none';
  // Neuer Name, sonst der frühere (#403) wie atlas.updateBaseline.
  mFileName := FileIn(ARoot, cBaselineFileName);
  if not FFiles.Exists(mFileName) and FFiles.Exists(FileIn(ARoot, cLegacyBaselineFileName)) then
  begin
    mFileName := FileIn(ARoot, cLegacyBaselineFileName);
  end;
  if not (FFiles.Exists(mFileName) and FFiles.Read(mFileName, mText)) then
  begin
    Exit;
  end;
  try
    Result := TRuleBaseline.FromJson(mText);
    APrevious := 'valid';
  except
    on ERuleBaseline do
      APrevious := 'invalid';
    on EJSONException do
      APrevious := 'invalid';
  end;
end;

/// <summary>Treffer zur Meldung AMessage am Anfang ihrer Zeile.</summary>
function FindingOf(const AMessage: TLspCompilerMessage): TRuleFinding;
var
  mLine: Integer;
begin
  mLine := Max(AMessage.Line - 1, 0);
  Result := Default(TRuleFinding);
  Result.RuleId := LowerCase(AMessage.Code);
  Result.Range := TTextRange.Create(TTextPosition.Create(mLine, 0), TTextPosition.Create(mLine, 0));
end;

function TLspCompilerBaseline.SourcesOf(const ARoot: string; const AMessages: TArray<TLspCompilerMessage>;
  out AOwner, ASlot: TArray<Integer>): TArray<TBaselineSource>;
var
  mByPath: TDictionary<string, Integer>;
  mUnreadable: TDictionary<string, Boolean>;
  mIndex, mOwner: Integer;
  mRelative, mKey, mText: string;
  mSource: TBaselineSource;
begin
  Result := nil;
  SetLength(AOwner, Length(AMessages));
  SetLength(ASlot, Length(AMessages));
  mByPath := TDictionary<string, Integer>.Create;
  mUnreadable := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to High(AMessages) do
    begin
      AOwner[mIndex] := -1;
      ASlot[mIndex] := -1;
      if not Accepts(AMessages[mIndex]) then
      begin
        Continue;
      end;
      mRelative := RelativeTo(ARoot, AMessages[mIndex].FileName);
      mKey := LowerCase(mRelative);
      if (mRelative = '') or mUnreadable.ContainsKey(mKey) then
      begin
        Continue;
      end;
      if not mByPath.TryGetValue(mKey, mOwner) then
      begin
        if not (Assigned(FReadText) and FReadText(AMessages[mIndex].FileName, mText)) then
        begin
          mUnreadable.Add(mKey, True);
          Continue;
        end;
        mSource := Default(TBaselineSource);
        mSource.Path := mRelative;
        mSource.Text := mText;
        mOwner := Length(Result);
        Result := Result + [mSource];
        mByPath.Add(mKey, mOwner);
      end;
      AOwner[mIndex] := mOwner;
      ASlot[mIndex] := Length(Result[mOwner].Findings);
      Result[mOwner].Findings := Result[mOwner].Findings + [FindingOf(AMessages[mIndex])];
    end;
  finally
    mUnreadable.Free;
    mByPath.Free;
  end;
end;

function TLspCompilerBaseline.Add(const ASource: TLspMetricsSource;
  const AMessages: TArray<TLspCompilerMessage>): string;
var
  mOld: IRuleBaseline;
  mPrevious, mFileName: string;
  mSources: TArray<TBaselineSource>;
  mOwner, mSlot: TArray<Integer>;
  mOutcome: TBaselineUpdate;
  mIndex, mSkipped: Integer;
begin
  mOld := Load(ASource.Root, mPrevious);
  // Eine unbrauchbare Datei nicht still ersetzen: Sie enthält womöglich Regeltreffer.
  if mPrevious = 'invalid' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TCompilerBaselineText.BaselineNotReadableWriteIt].Text);
  end;
  mSources := SourcesOf(ASource.Root, AMessages, mOwner, mSlot);
  mSkipped := 0;
  for mIndex := 0 to High(AMessages) do
  begin
    if Accepts(AMessages[mIndex]) and (mOwner[mIndex] < 0) then
    begin
      Inc(mSkipped);
    end;
  end;
  mOutcome := TRuleBaseline.ReplaceCompiler(mOld, mSources);
  mFileName := FileIn(ASource.Root, cBaselineFileName);
  FFiles.Write(mFileName, mOutcome.Json);
  if Assigned(FOnWritten) then
  begin
    FOnWritten(mFileName);
  end;
  Result := Format('{"format": %d, "file": %s, "previous": %s, "total": %d, "files": %d, ' +
    '"added": %d, "removed": %d, "unchanged": %d, "skipped": %d}', [cFormatVersion,
    TFindingsOutput.JsonString(mFileName), TFindingsOutput.JsonString(mPrevious), mOutcome.Total, mOutcome.Files,
    mOutcome.Added, mOutcome.Removed, mOutcome.Unchanged, mSkipped]);
end;

function TLspCompilerBaseline.Classify(const ASource: TLspMetricsSource;
  const AMessages: TArray<TLspCompilerMessage>; out APrevious: string): TArray<Boolean>;
var
  mBaseline: IRuleBaseline;
  mSources: TArray<TBaselineSource>;
  mOwner, mSlot: TArray<Integer>;
  mMarks: TArray<TArray<TBaselineMark>>;
  mIndex: Integer;
begin
  SetLength(Result, Length(AMessages));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := False;
  end;
  mBaseline := Load(ASource.Root, APrevious);
  if mBaseline = nil then
  begin
    Exit;
  end;
  mSources := SourcesOf(ASource.Root, AMessages, mOwner, mSlot);
  SetLength(mMarks, Length(mSources));
  for mIndex := 0 to High(mSources) do
  begin
    mMarks[mIndex] := mBaseline.Classify(mSources[mIndex].Path, mSources[mIndex].Text,
      TFindingScopes.FromText(mSources[mIndex].Text), mSources[mIndex].Findings);
  end;
  for mIndex := 0 to High(AMessages) do
  begin
    if mOwner[mIndex] >= 0 then
    begin
      Result[mIndex] := mMarks[mOwner[mIndex]][mSlot[mIndex]].State = TBaselineState.Unchanged;
    end;
  end;
end;

function TLspCompilerBaseline.SourceOf(const AArguments: TJSONArray): TLspMetricsSource;
var
  mFileName: string;
begin
  mFileName := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mFileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if not (Assigned(FSourceFor) and FSourceFor(mFileName, False, Result)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TCompilerBaselineText.NoWorkspaceFoundForThe].Text);
  end;
end;

function MessagesArgument(const AArguments: TJSONArray): TArray<TLspCompilerMessage>;
begin
  Result := nil;
  if (AArguments <> nil) and (AArguments.Count > 1) then
  begin
    Result := TLspCompilerBaseline.MessagesOf(AArguments.Items[1]);
  end;
end;

function TLspCompilerBaseline.ExecuteAdd(const AArguments: TJSONArray): TJSONValue;
var
  mText: string;
begin
  mText := Add(SourceOf(AArguments), MessagesArgument(AArguments));
  Result := TJSONObject.ParseJSONValue(mText);
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInternalError,
      cTexts[TCompilerBaselineText.AnswerOfTheBaselineIs].Text);
  end;
end;

function TLspCompilerBaseline.ExecuteClassify(const AArguments: TJSONArray): TJSONValue;
var
  mBaselined: TArray<Boolean>;
  mPrevious: string;
  mAnswer: TJSONObject;
  mIndexes: TJSONArray;
  mIndex: Integer;
begin
  mBaselined := Classify(SourceOf(AArguments), MessagesArgument(AArguments), mPrevious);
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('format', TJSONNumber.Create(cFormatVersion));
  mAnswer.AddPair('baseline', mPrevious);
  mIndexes := TJSONArray.Create;
  mAnswer.AddPair('baselined', mIndexes);
  for mIndex := 0 to High(mBaselined) do
  begin
    if mBaselined[mIndex] then
    begin
      mIndexes.Add(mIndex);
    end;
  end;
  Result := mAnswer;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.CompilerBaseline', cTexts);

end.
