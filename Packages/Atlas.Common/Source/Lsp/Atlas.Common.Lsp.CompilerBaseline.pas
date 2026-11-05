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
    AddCommand = 'atlas.baselineCompilerMessages';
    ClassifyCommand = 'atlas.classifyCompilerMessages';
    FormatVersion = 1;
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
  Root, Name: string;
begin
  Root := TRuleBaseline.NormalizePath(ARoot);
  if (Root <> '') and (Root[Length(Root)] <> '/') then
  begin
    Root := Root + '/';
  end;
  Name := TRuleBaseline.NormalizePath(AFileName);
  if (Root <> '/') and (Length(Name) > Length(Root)) and SameText(Copy(Name, 1, Length(Root)), Root) then
  begin
    Result := Copy(Name, Length(Root) + 1, MaxInt);
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
  Item: TJSONValue;
  Field: TJSONValue;
  Message: TLspCompilerMessage;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for Item in TJSONArray(AValue) do
  begin
    Message := Default(TLspCompilerMessage);
    if Item is TJSONObject then
    begin
      Field := TJSONObject(Item).GetValue('file');
      if Field is TJSONString then
      begin
        Message.FileName := Field.Value;
      end;
      Field := TJSONObject(Item).GetValue('line');
      if Field is TJSONNumber then
      begin
        Message.Line := TJSONNumber(Field).AsInt;
      end;
      Field := TJSONObject(Item).GetValue('code');
      if Field is TJSONString then
      begin
        Message.Code := UpperCase(Field.Value);
      end;
    end;
    // Ungültige Einträge bleiben als leere Meldung stehen: Die Positionen der Antwort gelten für die Eingabe.
    Result := Result + [Message];
  end;
end;

function TLspCompilerBaseline.Load(const ARoot: string; out APrevious: string): IRuleBaseline;
var
  FileName, Text: string;
begin
  Result := nil;
  APrevious := 'none';
  // Neuer Name, sonst der frühere (#403) wie atlas.updateBaseline.
  FileName := FileIn(ARoot, BaselineFileName);
  if not FFiles.Exists(FileName) and FFiles.Exists(FileIn(ARoot, LegacyBaselineFileName)) then
  begin
    FileName := FileIn(ARoot, LegacyBaselineFileName);
  end;
  if not (FFiles.Exists(FileName) and FFiles.Read(FileName, Text)) then
  begin
    Exit;
  end;
  try
    Result := TRuleBaseline.FromJson(Text);
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
  ByPath: TDictionary<string, Integer>;
  Unreadable: TDictionary<string, Boolean>;
  Index, Owner: Integer;
  Relative, Key, Text: string;
  Source: TBaselineSource;
begin
  Result := nil;
  SetLength(AOwner, Length(AMessages));
  SetLength(ASlot, Length(AMessages));
  ByPath := TDictionary<string, Integer>.Create;
  Unreadable := TDictionary<string, Boolean>.Create;
  try
    for Index := 0 to High(AMessages) do
    begin
      AOwner[Index] := -1;
      ASlot[Index] := -1;
      if not Accepts(AMessages[Index]) then
      begin
        Continue;
      end;
      Relative := RelativeTo(ARoot, AMessages[Index].FileName);
      Key := LowerCase(Relative);
      if (Relative = '') or Unreadable.ContainsKey(Key) then
      begin
        Continue;
      end;
      if not ByPath.TryGetValue(Key, Owner) then
      begin
        if not (Assigned(FReadText) and FReadText(AMessages[Index].FileName, Text)) then
        begin
          Unreadable.Add(Key, True);
          Continue;
        end;
        Source := Default(TBaselineSource);
        Source.Path := Relative;
        Source.Text := Text;
        Owner := Length(Result);
        Result := Result + [Source];
        ByPath.Add(Key, Owner);
      end;
      AOwner[Index] := Owner;
      ASlot[Index] := Length(Result[Owner].Findings);
      Result[Owner].Findings := Result[Owner].Findings + [FindingOf(AMessages[Index])];
    end;
  finally
    Unreadable.Free;
    ByPath.Free;
  end;
end;

function TLspCompilerBaseline.Add(const ASource: TLspMetricsSource;
  const AMessages: TArray<TLspCompilerMessage>): string;
var
  Old: IRuleBaseline;
  Previous, FileName: string;
  Sources: TArray<TBaselineSource>;
  Owner, Slot: TArray<Integer>;
  Outcome: TBaselineUpdate;
  Index, Skipped: Integer;
begin
  Old := Load(ASource.Root, Previous);
  // Eine unbrauchbare Datei nicht still ersetzen: Sie enthält womöglich Regeltreffer (Bericht N3).
  if Previous = 'invalid' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TCompilerBaselineText.BaselineNotReadableWriteIt].Text);
  end;
  Sources := SourcesOf(ASource.Root, AMessages, Owner, Slot);
  Skipped := 0;
  for Index := 0 to High(AMessages) do
  begin
    if Accepts(AMessages[Index]) and (Owner[Index] < 0) then
    begin
      Inc(Skipped);
    end;
  end;
  Outcome := TRuleBaseline.ReplaceCompiler(Old, Sources);
  FileName := FileIn(ASource.Root, BaselineFileName);
  FFiles.Write(FileName, Outcome.Json);
  if Assigned(FOnWritten) then
  begin
    FOnWritten(FileName);
  end;
  Result := Format('{"format": %d, "file": %s, "previous": %s, "total": %d, "files": %d, ' +
    '"added": %d, "removed": %d, "unchanged": %d, "skipped": %d}', [FormatVersion,
    TFindingsOutput.JsonString(FileName), TFindingsOutput.JsonString(Previous), Outcome.Total, Outcome.Files,
    Outcome.Added, Outcome.Removed, Outcome.Unchanged, Skipped]);
end;

function TLspCompilerBaseline.Classify(const ASource: TLspMetricsSource;
  const AMessages: TArray<TLspCompilerMessage>; out APrevious: string): TArray<Boolean>;
var
  Baseline: IRuleBaseline;
  Sources: TArray<TBaselineSource>;
  Owner, Slot: TArray<Integer>;
  Marks: TArray<TArray<TBaselineMark>>;
  Index: Integer;
begin
  SetLength(Result, Length(AMessages));
  for Index := 0 to High(Result) do
  begin
    Result[Index] := False;
  end;
  Baseline := Load(ASource.Root, APrevious);
  if Baseline = nil then
  begin
    Exit;
  end;
  Sources := SourcesOf(ASource.Root, AMessages, Owner, Slot);
  SetLength(Marks, Length(Sources));
  for Index := 0 to High(Sources) do
  begin
    Marks[Index] := Baseline.Classify(Sources[Index].Path, Sources[Index].Text,
      TFindingScopes.FromText(Sources[Index].Text), Sources[Index].Findings);
  end;
  for Index := 0 to High(AMessages) do
  begin
    if Owner[Index] >= 0 then
    begin
      Result[Index] := Marks[Owner[Index]][Slot[Index]].State = TBaselineState.Unchanged;
    end;
  end;
end;

function TLspCompilerBaseline.SourceOf(const AArguments: TJSONArray): TLspMetricsSource;
var
  FileName: string;
begin
  FileName := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if not (Assigned(FSourceFor) and FSourceFor(FileName, False, Result)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
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
  Text: string;
begin
  Text := Add(SourceOf(AArguments), MessagesArgument(AArguments));
  Result := TJSONObject.ParseJSONValue(Text);
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError,
      cTexts[TCompilerBaselineText.AnswerOfTheBaselineIs].Text);
  end;
end;

function TLspCompilerBaseline.ExecuteClassify(const AArguments: TJSONArray): TJSONValue;
var
  Baselined: TArray<Boolean>;
  Previous: string;
  Answer: TJSONObject;
  Indexes: TJSONArray;
  Index: Integer;
begin
  Baselined := Classify(SourceOf(AArguments), MessagesArgument(AArguments), Previous);
  Answer := TJSONObject.Create;
  Answer.AddPair('format', TJSONNumber.Create(FormatVersion));
  Answer.AddPair('baseline', Previous);
  Indexes := TJSONArray.Create;
  Answer.AddPair('baselined', Indexes);
  for Index := 0 to High(Baselined) do
  begin
    if Baselined[Index] then
    begin
      Indexes.Add(Index);
    end;
  end;
  Result := Answer;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.CompilerBaseline', cTexts);

end.
