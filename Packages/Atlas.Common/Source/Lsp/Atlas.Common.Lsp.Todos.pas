unit Atlas.Common.Lsp.Todos;

// Befehl atlas.server.todos (#68): TODO-Übersicht für die Liste des
// IDE-Plugins und die Projekt-Zusammenfassung der Willkommensseite (#592,
// Projektverlauf #758).
// Argumente: [uri, mode, filter]
//   - uri: Projekt (.dproj, .dpr, .dpk), Ordner, null (einziger
//     Arbeitsbereich) oder eine Quelltextdatei (nur diese Datei)
//   - mode:
//       "summary"  → {"format": 1, "summary": {"files", "open", "done", "keywords"}}
//                    über alle Einträge samt erledigten (ohne Filter);
//                    Vorgabe für ein Projekt
//       "json"     → vollständige Daten (TTodoReport.Json) mit "root";
//                    Vorgabe für eine Quelltextdatei
//       "markdown" → Übersicht als Markdown (JSON-String)
//   - filter (freiwillig, nicht bei summary): {"category", "owner", "unit",
//     "keyword", "includeDone"}; ohne Angabe sind erledigte Einträge
//     ausgeblendet.
// Welche Dateien zum Projekt gehören, bestimmt das Projektmodell (#14) über
// die Quelle des Arbeitsbereichs (TLspMetricsSource, wie atlas.server.metrics).
// Die Marken stammen aus der Option "keywords" der Regel todo-comment.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Lsp.Metrics;

type
  TLspTodosMode = (Summary, Json, Markdown);

  TLspTodos = class
  public const
    Command = 'atlas.server.todos';
  private
    FSourceFor: TLspMetricsSourceFunc;
    FReadText: TTodoReadText;
  public
    constructor Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TTodoReadText);
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Antwort über ASource.Files als JSON-Text.</summary>
    function Answer(const ASource: TLspMetricsSource; AMode: TLspTodosMode; const AFilter: TTodoFilter): string;
    /// <summary>Modus aus dem Argument; leer = AProject: Summary, sonst Json. False bei unbekanntem Modus.</summary>
    class function TryParseMode(const AText: string; AProject: Boolean; out AMode: TLspTodosMode): Boolean; static;
    /// <summary>Filter aus einem Objekt {"category", "owner", "unit", "keyword", "includeDone"}; nil = Vorgabe.</summary>
    class function FilterOf(const AValue: TJSONValue): TTodoFilter; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Builtin.Todos;

{ TLspTodos }

constructor TLspTodos.Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TTodoReadText);
begin
  inherited Create;
  FSourceFor := ASourceFor;
  FReadText := AReadText;
end;

class function TLspTodos.TryParseMode(const AText: string; AProject: Boolean; out AMode: TLspTodosMode): Boolean;
begin
  Result := True;
  if AText = '' then
  begin
    if AProject then
      AMode := TLspTodosMode.Summary
    else
      AMode := TLspTodosMode.Json;
  end
  else if SameText(AText, 'summary') then
    AMode := TLspTodosMode.Summary
  else if SameText(AText, 'json') then
    AMode := TLspTodosMode.Json
  else if SameText(AText, 'markdown') then
    AMode := TLspTodosMode.Markdown
  else
  begin
    AMode := TLspTodosMode.Summary;
    Result := False;
  end;
end;

class function TLspTodos.FilterOf(const AValue: TJSONValue): TTodoFilter;
var
  Item: TJSONObject;
  Flag: TJSONValue;

  function Text(const AName: string): string;
  var
    Value: TJSONValue;
  begin
    Value := Item.GetValue(AName);
    if Value is TJSONString then
      Result := Trim(Value.Value)
    else
      Result := '';
  end;

begin
  Result := TTodoFilter.Default;
  if not (AValue is TJSONObject) then
    Exit;
  Item := TJSONObject(AValue);
  Result.Category := Text('category');
  Result.Owner := Text('owner');
  Result.UnitName := Text('unit');
  Result.Keyword := Text('keyword');
  Flag := Item.GetValue('includeDone');
  Result.IncludeDone := (Flag is TJSONBool) and TJSONBool(Flag).AsBoolean;
end;

function TLspTodos.Answer(const ASource: TLspMetricsSource; AMode: TLspTodosMode; const AFilter: TTodoFilter): string;
var
  Files: TArray<TFileTodos>;
begin
  Files := TTodoScanner.Collect(ASource.Files, ASource.Root, FReadText, TTodoRules.Keywords(ASource.Settings));
  case AMode of
    TLspTodosMode.Json:
      Result := TTodoReport.Json(TTodoScanner.Filter(Files, AFilter), ASource.Root);
    TLspTodosMode.Markdown:
      Result := TMetricsReport.JsonString(TTodoReport.Markdown(TTodoScanner.Filter(Files, AFilter), ASource.Title));
  else
    Result := '{"format": ' + IntToStr(TTodoReport.Format) + ', "summary": ' +
      TTodoReport.SummaryJson(TTodoReport.Summarize(Files)) + '}';
  end;
end;

function TLspTodos.Execute(const AArguments: TJSONArray): TJSONValue;
var
  FileName, ModeText, Text: string;
  Mode: TLspTodosMode;
  Source: TLspMetricsSource;
  Filter: TTodoFilter;
  Project: Boolean;
begin
  FileName := '';
  ModeText := '';
  Filter := TTodoFilter.Default;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
    ModeText := AArguments.Items[1].Value;
  if (AArguments <> nil) and (AArguments.Count > 2) then
    Filter := FilterOf(AArguments.Items[2]);
  Project := TLspMetrics.IsProject(FileName);
  if not TryParseMode(ModeText, Project, Mode) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      Format('Unbekannter Modus "%s"; erlaubt: summary, json, markdown', [ModeText]));
  if not (Assigned(FSourceFor) and FSourceFor(FileName, Project, Source)) then
  begin
    Source := Default(TLspMetricsSource);
    Source.Settings := TServerSettings.Default;
  end;
  // Eine Quelltextdatei: nur sie, mit den Einstellungen ihres Arbeitsbereichs.
  if not Project then
    Source.Files := [FileName];
  Text := Answer(Source, Mode, Filter);
  Result := TJSONObject.ParseJSONValue(Text);
  if Result = nil then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'TODO-Daten sind kein gültiges JSON');
end;

end.
