unit Atlas.Common.Lsp.Baseline;

// Befehl atlas.updateBaseline (#97) über workspace/executeCommand: prüft alle
// Dateien des Projekts mit denselben Regeln wie der Editor, schreibt
// atlas-baseline.json in den Ordner des Arbeitsbereichs neu (immer unter dem
// neuen Namen, gelesen wird auch delphi-lsp-baseline.json) und antwortet mit
// den Zählern.
//
// Argumente: [uri] – Projekt (.dproj, .dpr, .dpk), Ordner, null (einziger
// Arbeitsbereich) oder eine Datei (steht für ihren Arbeitsbereich).
// Antwort:
//   {"format": 1, "file": "<voller Pfad>", "previous": "none|valid|invalid",
//    "setAside": "<voller Pfad>.defekt" (nur nach "invalid"),
//    "total": 120, "files": 40, "skipped": 0, "added": 3, "removed": 5,
//    "unchanged": 117, "completed": 0,
//    "orphaned": {"count": 2, "entries": [{"path": "Alt/U.pas", "count": 2}]}}
// "added", "removed" und "unchanged" zählen Treffer gegenüber der bisherigen
// Baseline, "completed" die davon aus Einträgen ohne Routine (ältere Datei).
// "orphaned" sind Einträge, deren Datei nicht geprüft wurde und nicht mehr
// existiert (umbenannt, verschoben, gelöscht); sie fallen heraus und zählen
// zu "removed". "skipped" sind Projektdateien, die nicht lesbar waren.
// War die bisherige Baseline unbrauchbar ("previous": "invalid"), legt der
// Befehl sie vor dem Schreiben als <Name>.defekt beiseite und nennt den
// vollen Pfad in "setAside" (Bericht N3); früher ersetzte er sie still.
//
// Ohne Projektdateien (Projekt noch nicht geladen) schreibt der Befehl nichts
// und antwortet mit einem Fehler, damit keine leere Baseline entsteht.
// Der Arbeitsbereich liest die neue Datei beim nächsten Prüfen selbst
// (Zeitstempel); OnWritten stößt die Neuprüfung der offenen Dokumente an.
// Dateizugriffe und Prüfung kommen von außen (Tests ohne Platte und Server).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Lsp.Metrics;

type
  /// <summary>Eine geprüfte Datei: Pfad relativ zum Arbeitsbereich wie im Editor, Text und Regeltreffer ohne
  /// Baseline.</summary>
  TLspBaselineCheck = record
    RelativePath: string;
    Text: string;
    Findings: TArray<TRuleFinding>;
  end;

  /// <summary>Prüft AFileName wie der Editor; False, wenn die Datei nicht lesbar ist.</summary>
  TLspBaselineCheckFunc = reference to function(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean;

  TLspBaselineExists = reference to function(const AFileName: string): Boolean;
  TLspBaselineRead = reference to function(const AFileName: string; out AText: string): Boolean;
  TLspBaselineWrite = reference to procedure(const AFileName, AText: string);
  /// <summary>Benennt AFileName in AFileName + '.defekt' um (eine ältere wird ersetzt); ATarget = neuer Name.
  /// False, wenn es nicht ging.</summary>
  TLspBaselineSetAside = reference to function(const AFileName: string; out ATarget: string): Boolean;

  /// <summary>Dateizugriffe des Befehls; volle Pfade.</summary>
  TLspBaselineFiles = record
    Exists: TLspBaselineExists;
    Read: TLspBaselineRead;
    /// <summary>Soll atomar ersetzen: Der Arbeitsbereich liest die Datei, sobald sich ihr Zeitstempel ändert.
    /// </summary>
    Write: TLspBaselineWrite;
    /// <summary>Unbrauchbare bisherige Baseline beiseitelegen (Bericht N3). nil: Sie wird ersetzt.</summary>
    SetAside: TLspBaselineSetAside;
  end;

  TLspBaseline = class
  public const
    Command = 'atlas.updateBaseline';
    Format = 1;
  private
    FSourceFor: TLspMetricsSourceFunc;
    FCheck: TLspBaselineCheckFunc;
    FFiles: TLspBaselineFiles;
    FOnWritten: TProc<string>;
    function FileIn(const ARoot, AName: string): string;
    /// <summary>Zustand der bisherigen Baseline in ARoot: 'none', 'valid' oder 'invalid'. AOld: gelesene Baseline
    /// oder nil; ASetAsideFile: wohin eine unbrauchbare kam, sonst ''.</summary>
    function ReadPrevious(const ARoot: string; out AOld: IRuleBaseline; out ASetAsideFile: string): string;
    /// <summary>Prüft AFiles; ASkipped zählt die nicht lesbaren.</summary>
    function CheckedSources(const AFiles: TArray<string>; out ASkipped: Integer): TArray<TBaselineSource>;
  public
    constructor Create(const ASourceFor: TLspMetricsSourceFunc; const ACheck: TLspBaselineCheckFunc;
      const AFiles: TLspBaselineFiles);
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Prüft ASource.Files, schreibt die Baseline in ASource.Root und liefert die Antwort als JSON-Text.
    /// Löst EJsonRpcError aus, wenn es keine Dateien gibt.</summary>
    function Update(const ASource: TLspMetricsSource): string;
    /// <summary>Nach dem Schreiben mit dem vollen Pfad der Datei.</summary>
    property OnWritten: TProc<string> read FOnWritten write FOnWritten;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Output,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBaselineText = (NoProjectFilesBaselineNot, NoWorkspaceFoundForThe, AnswerOfTheBaselineIs);

const
  cTexts: array[TBaselineText] of TAtlasText = (
    (De: 'Keine Projektdateien: Baseline nicht geschrieben (Projekt noch nicht geladen?)';
     En: 'No project files: baseline not written (project not loaded yet?)'),
    (De: 'Kein Arbeitsbereich für die Baseline gefunden'; En: 'No workspace found for the baseline'),
    (De: 'Antwort der Baseline ist kein gültiges JSON'; En: 'Answer of the baseline is not valid JSON'));

{$SCOPEDENUMS OFF}

{ TLspBaseline }

constructor TLspBaseline.Create(const ASourceFor: TLspMetricsSourceFunc; const ACheck: TLspBaselineCheckFunc;
  const AFiles: TLspBaselineFiles);
begin
  inherited Create;
  FSourceFor := ASourceFor;
  FCheck := ACheck;
  FFiles := AFiles;
end;

function TLspBaseline.FileIn(const ARoot, AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ARoot) + AName;
end;

function TLspBaseline.ReadPrevious(const ARoot: string; out AOld: IRuleBaseline; out ASetAsideFile: string): string;
var
  mFileName, mText: string;
begin
  AOld := nil;
  ASetAsideFile := '';
  Result := 'none';
  // Bisherige Baseline: neuer Name, sonst der frühere (#403); nur für die Zähler.
  mFileName := FileIn(ARoot, BaselineFileName);
  if not FFiles.Exists(mFileName) and FFiles.Exists(FileIn(ARoot, LegacyBaselineFileName)) then
  begin
    mFileName := FileIn(ARoot, LegacyBaselineFileName);
  end;
  if not (FFiles.Exists(mFileName) and FFiles.Read(mFileName, mText)) then
  begin
    Exit;
  end;
  try
    AOld := TRuleBaseline.FromJson(mText);
    Result := 'valid';
  except
    // Unbrauchbar: Die Zähler gelten wie ohne Baseline.
    on ERuleBaseline do
      Result := 'invalid';
    on EJSONException do
      Result := 'invalid';
  end;
  // Nicht still ersetzen (Bericht N3): Die alte Datei bleibt als .defekt zum Nachsehen, die Antwort nennt sie.
  if (Result = 'invalid') and Assigned(FFiles.SetAside) and not FFiles.SetAside(mFileName, ASetAsideFile) then
  begin
    ASetAsideFile := '';
  end;
end;

function TLspBaseline.CheckedSources(const AFiles: TArray<string>; out ASkipped: Integer): TArray<TBaselineSource>;
var
  mFileName: string;
  mCheck: TLspBaselineCheck;
  mSource: TBaselineSource;
begin
  Result := nil;
  ASkipped := 0;
  for mFileName in AFiles do
  begin
    if not FCheck(mFileName, mCheck) then
    begin
      Inc(ASkipped);
      Continue;
    end;
    mSource.Path := mCheck.RelativePath;
    mSource.Text := mCheck.Text;
    mSource.Findings := mCheck.Findings;
    Result := Result + [mSource];
  end;
end;

function TLspBaseline.Update(const ASource: TLspMetricsSource): string;
var
  mFileName, mPrevious, mSetAsideFile, mRoot: string;
  mOld: IRuleBaseline;
  mSources: TArray<TBaselineSource>;
  mSkipped: Integer;
  mOutcome: TBaselineUpdate;
begin
  if Length(ASource.Files) = 0 then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TBaselineText.NoProjectFilesBaselineNot].Text);
  end;
  mRoot := ASource.Root;
  mPrevious := ReadPrevious(mRoot, mOld, mSetAsideFile);
  mSources := CheckedSources(ASource.Files, mSkipped);
  mOutcome := TRuleBaseline.Update(mOld, mSources,
    function(const APath: string): Boolean
    begin
      Result := FFiles.Exists(FileIn(mRoot, StringReplace(APath, '/', PathDelim, [rfReplaceAll])));
    end);
  mFileName := FileIn(mRoot, BaselineFileName);
  FFiles.Write(mFileName, mOutcome.Json);
  if Assigned(FOnWritten) then
  begin
    FOnWritten(mFileName);
  end;
  // Die Zähler stehen in CountersJson als eigenes Objekt; hier mit Kopf zusammengesetzt.
  Result := '{"format": ' + IntToStr(Format) + ', "file": ' + TFindingsOutput.JsonString(mFileName) +
    ', "previous": ' + TFindingsOutput.JsonString(mPrevious) + ', ';
  if mSetAsideFile <> '' then
  begin
    Result := Result + '"setAside": ' + TFindingsOutput.JsonString(mSetAsideFile) + ', ';
  end;
  Result := Result + '"skipped": ' + IntToStr(mSkipped) + ', ' + Copy(mOutcome.CountersJson, 2, MaxInt);
end;

function TLspBaseline.Execute(const AArguments: TJSONArray): TJSONValue;
var
  FileName, Text: string;
  Source: TLspMetricsSource;
begin
  FileName := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  // Auch für eine Quelltextdatei die Dateien ihres Arbeitsbereichs: Die Baseline gilt immer für alle.
  if not (Assigned(FSourceFor) and FSourceFor(FileName, True, Source)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TBaselineText.NoWorkspaceFoundForThe].Text);
  end;
  Text := Update(Source);
  Result := TJSONObject.ParseJSONValue(Text);
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, cTexts[TBaselineText.AnswerOfTheBaselineIs].Text);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Baseline', cTexts);

end.
