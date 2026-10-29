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
  Atlas.Common.Rules.Output;

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

function TLspBaseline.Update(const ASource: TLspMetricsSource): string;
var
  FileName, Text, Previous, SetAsideFile: string;
  Old: IRuleBaseline;
  Sources: TArray<TBaselineSource>;
  Source: TBaselineSource;
  Check: TLspBaselineCheck;
  Skipped: Integer;
  Outcome: TBaselineUpdate;
  Root: string;
begin
  if Length(ASource.Files) = 0 then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Keine Projektdateien: Baseline nicht geschrieben (Projekt noch nicht geladen?)');
  Root := ASource.Root;
  // Bisherige Baseline: neuer Name, sonst der frühere (#403); nur für die Zähler.
  FileName := FileIn(Root, BaselineFileName);
  if not FFiles.Exists(FileName) and FFiles.Exists(FileIn(Root, LegacyBaselineFileName)) then
    FileName := FileIn(Root, LegacyBaselineFileName);
  Old := nil;
  Previous := 'none';
  SetAsideFile := '';
  if FFiles.Exists(FileName) and FFiles.Read(FileName, Text) then
    try
      Old := TRuleBaseline.FromJson(Text);
      Previous := 'valid';
    except
      // Unbrauchbar: Die Zähler gelten wie ohne Baseline; die Datei kommt unten beiseite.
      on ERuleBaseline do
        Previous := 'invalid';
      on EJSONException do
        Previous := 'invalid';
    end;
  // Nicht still ersetzen (Bericht N3): Die alte Datei bleibt als .defekt zum Nachsehen, die Antwort nennt sie.
  if (Previous = 'invalid') and Assigned(FFiles.SetAside) then
    if not FFiles.SetAside(FileName, SetAsideFile) then
      SetAsideFile := '';
  Sources := nil;
  Skipped := 0;
  for FileName in ASource.Files do
  begin
    if not FCheck(FileName, Check) then
    begin
      Inc(Skipped);
      Continue;
    end;
    Source.Path := Check.RelativePath;
    Source.Text := Check.Text;
    Source.Findings := Check.Findings;
    Sources := Sources + [Source];
  end;
  Outcome := TRuleBaseline.Update(Old, Sources,
    function(const APath: string): Boolean
    begin
      Result := FFiles.Exists(FileIn(Root, StringReplace(APath, '/', PathDelim, [rfReplaceAll])));
    end);
  FileName := FileIn(Root, BaselineFileName);
  FFiles.Write(FileName, Outcome.Json);
  if Assigned(FOnWritten) then
    FOnWritten(FileName);
  // Die Zähler stehen in CountersJson als eigenes Objekt; hier mit Kopf zusammengesetzt.
  Text := Outcome.CountersJson;
  Result := '{"format": ' + IntToStr(Format) + ', "file": ' + TFindingsOutput.JsonString(FileName) +
    ', "previous": ' + TFindingsOutput.JsonString(Previous) + ', ';
  if SetAsideFile <> '' then
    Result := Result + '"setAside": ' + TFindingsOutput.JsonString(SetAsideFile) + ', ';
  Result := Result + '"skipped": ' + IntToStr(Skipped) + ', ' + Copy(Text, 2, MaxInt);
end;

function TLspBaseline.Execute(const AArguments: TJSONArray): TJSONValue;
var
  FileName, Text: string;
  Source: TLspMetricsSource;
begin
  FileName := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  // Auch für eine Quelltextdatei die Dateien ihres Arbeitsbereichs: Die Baseline gilt immer für alle.
  if not (Assigned(FSourceFor) and FSourceFor(FileName, True, Source)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Kein Arbeitsbereich für die Baseline gefunden');
  Text := Update(Source);
  Result := TJSONObject.ParseJSONValue(Text);
  if Result = nil then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Antwort der Baseline ist kein gültiges JSON');
end;

end.
