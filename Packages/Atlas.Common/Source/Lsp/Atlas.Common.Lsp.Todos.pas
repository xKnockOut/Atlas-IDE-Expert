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
    cCommand = 'atlas.server.todos';
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
    /// <summary>Filter aus einem Objekt {"category", "owner", "unit", "keyword", "includeDone"}; nil =
    /// Vorgabe.</summary>
    class function FilterOf(const AValue: TJSONValue): TTodoFilter; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Todos.Report,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTodosText = (TODODataIsNotValid, UnknownModeAllowedSummaryJson);

const
  cTexts: array[TTodosText] of TAtlasText = (
    (De: 'TODO-Daten sind kein gültiges JSON'; En: 'TODO data is not valid JSON'),
    (De: 'Unbekannter Modus "%s"; erlaubt: summary, json, markdown';
     En: 'Unknown mode "%s"; allowed: summary, json, markdown'));

{$SCOPEDENUMS OFF}

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
    begin
      AMode := TLspTodosMode.Summary;
    end
    else
    begin
      AMode := TLspTodosMode.Json;
    end;
  end
  else if SameText(AText, 'summary') then
  begin
    AMode := TLspTodosMode.Summary;
  end
  else if SameText(AText, 'json') then
  begin
    AMode := TLspTodosMode.Json;
  end
  else if SameText(AText, 'markdown') then
  begin
    AMode := TLspTodosMode.Markdown;
  end
  else
  begin
    AMode := TLspTodosMode.Summary;
    Result := False;
  end;
end;

class function TLspTodos.FilterOf(const AValue: TJSONValue): TTodoFilter;
var
  mItem: TJSONObject;
  mFlag: TJSONValue;

  function Text(const AName: string): string;
  var
    mValue: TJSONValue;
  begin
    mValue := mItem.GetValue(AName);
    if mValue is TJSONString then
    begin
      Result := Trim(mValue.Value);
    end
    else
    begin
      Result := '';
    end;
  end;

begin
  Result := TTodoFilter.Default;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  Result.Category := Text('category');
  Result.Owner := Text('owner');
  Result.UnitName := Text('unit');
  Result.Keyword := Text('keyword');
  mFlag := mItem.GetValue('includeDone');
  Result.IncludeDone := (mFlag is TJSONBool) and TJSONBool(mFlag).AsBoolean;
end;

function TLspTodos.Answer(const ASource: TLspMetricsSource; AMode: TLspTodosMode; const AFilter: TTodoFilter): string;
var
  mFiles: TArray<TFileTodos>;
begin
  mFiles := TTodoScanner.Collect(ASource.Files, ASource.Root, FReadText, TTodoRules.Keywords(ASource.Settings));
  case AMode of
    TLspTodosMode.Json:
      Result := TTodoReport.Json(TTodoScanner.Filter(mFiles, AFilter), ASource.Root);
    TLspTodosMode.Markdown:
      Result := TMetricsReport.JsonString(TTodoReport.Markdown(TTodoScanner.Filter(mFiles, AFilter), ASource.Title));
  else
    Result := '{"format": ' + IntToStr(TTodoReport.cFormat) + ', "summary": ' +
      TTodoReport.SummaryJson(TTodoReport.Summarize(mFiles)) + '}';
  end;
end;

function TLspTodos.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mFileName, mModeText, mText: string;
  mMode: TLspTodosMode;
  mSource: TLspMetricsSource;
  mFilter: TTodoFilter;
  mProject: Boolean;
begin
  mFileName := '';
  mModeText := '';
  mFilter := TTodoFilter.Default;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mFileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
  begin
    mModeText := AArguments.Items[1].Value;
  end;
  if (AArguments <> nil) and (AArguments.Count > 2) then
  begin
    mFilter := FilterOf(AArguments.Items[2]);
  end;
  mProject := TLspMetrics.IsProject(mFileName);
  if not TryParseMode(mModeText, mProject, mMode) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TTodosText.UnknownModeAllowedSummaryJson].Fmt([mModeText]));
  end;
  if not (Assigned(FSourceFor) and FSourceFor(mFileName, mProject, mSource)) then
  begin
    mSource := Default(TLspMetricsSource);
    mSource.Settings := TServerSettings.Default;
  end;
  // Eine Quelltextdatei: nur sie, mit den Einstellungen ihres Arbeitsbereichs.
  if not mProject then
  begin
    mSource.Files := [mFileName];
  end;
  mText := Answer(mSource, mMode, mFilter);
  Result := TJSONObject.ParseJSONValue(mText);
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInternalError, cTexts[TTodosText.TODODataIsNotValid].Text);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Todos', cTexts);

end.
