unit Shell.Mcp.CheckTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge der Prüfregeln, Metriken und TODOs
// (get_diagnostics, hook_check, get_metrics, get_todos, check_code, get_dfm_info, explain_finding).

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet die Werkzeuge der Prüfregeln, Metriken, TODOs und Formulare an.</summary>
procedure RegisterCheckTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Builtin;

function ToolGetDiagnostics(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName, Reason: string;
  Files: TArray<string>;
begin
  FileName := TMcpServer.OptionalString(AArguments, 'file');
  if FileName <> '' then
  begin
    Files := [AContext.Guard.Resolve(FileName)];
  end
  else
  begin
    Files := AContext.Group.Main.State.ProjectFiles;
  end;
  if Length(Files) = 0 then
  begin
    raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
  end;
  Result := TMcpCodeTools.Diagnostics(BuiltinRules, AContext.Group.Main.Configuration.Settings, AContext.Root, Files,
    ReadSourceText, AContext.CheckSource, AContext.CheckProject);
  // Solange der Index lädt, sehen Regeln, die Typen anderer Units brauchen, noch nicht alles (#1112).
  if not AContext.Group.Ready(Reason) then
  begin
    Result := Format('Hinweis: %s; Befunde, die den Symbolindex brauchen, können noch fehlen.',
      [Reason]) + sLineBreak + Result;
  end;
end;

procedure AddGetDiagnostics(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_diagnostics',
    'Syntaxfehler und Befunde der Prüfregeln (wie --check) für eine Datei oder das ganze Projekt.',
    TMcpServer.StringSchema(['file'], ['Pfad einer .pas-Datei; leer = alle Projektdateien'], 0),
    ContextTool(AContext, ToolGetDiagnostics));
end;

function ToolHookCheck(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName: string;
  Severity: TRuleSeverity;
begin
  Severity := TMcpCodeTools.ParseHookSeverity(TMcpServer.OptionalString(AArguments, 'severity'));
  try
    FileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  except
    // Dateien außerhalb des Projekts gehen Atlas nichts an; eine Fehlermeldung je Bearbeitung wäre Rauschen.
    on EMcpToolError do
      Exit('');
  end;
  Result := TMcpCodeTools.HookDiagnostics(BuiltinRules, AContext.Group.Main.Configuration.Settings, AContext.Root, FileName,
    ReadSourceText, AContext.CheckSource, AContext.CheckProject, Severity);
end;

procedure AddHookCheck(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('hook_check',
    'Für Hooks von Claude Code (PostToolUse nach Edit/Write, siehe Plugin atlas): Befunde ab severity ' +
    '(Vorgabe warning) der gerade bearbeiteten Datei als Hook-Ausgabe mit additionalContext. Leer bei Dateien, ' +
    'die kein Pascal-Quelltext sind, außerhalb des Arbeitsbereichs liegen oder keine Befunde haben. Abschalten ' +
    'über mcp.disabledTools.',
    TMcpServer.StringSchema(['file', 'severity'],
      ['Pfad der bearbeiteten Datei (tool_input.file_path)', 'error, warning (Vorgabe), information oder hint'], 1),
    ContextTool(AContext, ToolHookCheck));
end;

function ToolGetMetrics(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName, Format: string;
  Files: TArray<string>;
begin
  FileName := TMcpServer.OptionalString(AArguments, 'file');
  Format := TMcpServer.OptionalString(AArguments, 'format');
  if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
  begin
    raise EMcpToolError.Create('"format" ist markdown oder json');
  end;
  if FileName <> '' then
  begin
    Files := [AContext.Guard.Resolve(FileName)];
  end
  else
  begin
    Files := AContext.Group.Main.State.ProjectFiles;
  end;
  if Length(Files) = 0 then
  begin
    raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
  end;
  Result := TMcpCodeTools.Metrics(AContext.Group.Main.Configuration.Settings, AContext.Root, Files, ReadSourceText,
    SameText(Format, 'json'));
end;

procedure AddGetMetrics(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_metrics',
    'Code-Metriken (#66) je Methode: Länge in Codezeilen, Verschachtelungstiefe, zyklomatische und kognitive ' +
    'Komplexität, Parameteranzahl; Grenzwerte aus atlas.json (Regeln metric-*, Option "max"). Als Markdown-Bericht ' +
    'mit den Methoden über einem Grenzwert oder als JSON-Daten.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad einer .pas-Datei; leer = alle Projektdateien"},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":"markdown (Vorgabe) oder json"}}}',
    ContextTool(AContext, ToolGetMetrics));
end;

function ToolGetTodos(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName, Format: string;
  Files: TArray<string>;
  Filter: TTodoFilter;
  IncludeDone: Boolean;
begin
  FileName := TMcpServer.OptionalString(AArguments, 'file');
  Format := TMcpServer.OptionalString(AArguments, 'format');
  if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
  begin
    raise EMcpToolError.Create('"format" ist markdown oder json');
  end;
  Filter := TTodoFilter.Default;
  Filter.UnitName := TMcpServer.OptionalString(AArguments, 'unit');
  Filter.Category := TMcpServer.OptionalString(AArguments, 'category');
  Filter.Owner := TMcpServer.OptionalString(AArguments, 'owner');
  Filter.Keyword := TMcpServer.OptionalString(AArguments, 'keyword');
  if (AArguments <> nil) and AArguments.TryGetValue<Boolean>('includeDone', IncludeDone) then
  begin
    Filter.IncludeDone := IncludeDone;
  end;
  // Projektweit heißt: die Dateien, die das Projektmodell (#14) dem Projekt zuordnet.
  if FileName <> '' then
  begin
    Files := [AContext.Guard.Resolve(FileName)];
  end
  else
  begin
    Files := AContext.Group.Main.State.ProjectFiles;
  end;
  if Length(Files) = 0 then
  begin
    raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
  end;
  Result := TMcpCodeTools.Todos(AContext.Group.Main.Configuration.Settings, AContext.Root, Files, ReadSourceText, Filter,
    SameText(Format, 'json'));
end;

procedure AddGetTodos(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_todos',
    'TODO-Übersicht (#68): Kommentare // TODO, // FIXME und das Format der IDE-To-Do-Liste ' +
    '{ TODO 1 -oPerson -cKategorie : Text } aus allen Dateien des Projekts, mit Priorität, Person und Kategorie. ' +
    'Erledigte Einträge ({ DONE … }) nur mit includeDone. Weitere Marken über die Option "keywords" der Regel ' +
    'todo-comment in atlas.json. Als Markdown-Übersicht oder als JSON-Daten.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad einer .pas-Datei; leer = alle Projektdateien"},' +
      '"unit":{"type":"string","description":"Nur diese Unit (Name oder Pfad relativ zum Projekt)"},' +
      '"category":{"type":"string","description":"Nur diese Kategorie (-c)"},' +
      '"owner":{"type":"string","description":"Nur diese Person (-o)"},' +
      '"keyword":{"type":"string","description":"Nur diese Marke, z. B. FIXME"},' +
      '"includeDone":{"type":"boolean","description":"Auch erledigte Einträge (DONE); Vorgabe false"},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":"markdown (Vorgabe) oder json"}}}',
    ContextTool(AContext, ToolGetTodos));
end;

function ToolCheckCode(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName, Text: string;
  StartLine, EndLine: Integer;
begin
  FileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<string>('text', Text) then
  begin
    raise EMcpToolError.Create('Argument "text" fehlt');
  end;
  if not AArguments.TryGetValue<Integer>('startLine', StartLine) then
  begin
    StartLine := 0;
  end;
  if not AArguments.TryGetValue<Integer>('endLine', EndLine) then
  begin
    EndLine := StartLine;
  end;
  Result := AContext.Code.CheckCode(BuiltinRules, AContext.Group.Main.Configuration.Settings, AContext.Root, FileName, Text,
    StartLine, EndLine);
end;

procedure AddCheckCode(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('check_code',
    'Prüft geplanten Code ohne zu schreiben (#178): Syntaxfehler, Regeltreffer und nicht auflösbare Bezeichner. ' +
    'Entweder den ganzen neuen Text der Unit angeben oder mit startLine/endLine nur einen Zeilenbereich ersetzen.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"text":{"type":"string","description":"Neuer Text: die ganze Unit oder der Ersatz für startLine..endLine"},' +
      '"startLine":{"type":"integer","minimum":1,"description":"Erste ersetzte Zeile (ab 1); ohne Angabe ist text die ganze Unit"},' +
      '"endLine":{"type":"integer","minimum":0,"description":"Letzte ersetzte Zeile; startLine - 1 fügt nur ein"}},' +
      '"required":["file","text"]}',
    ContextTool(AContext, ToolCheckCode));
end;

function ToolGetDfmInfo(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName, Text: string;
begin
  FileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if SameText(ExtractFileExt(FileName), '.pas') then
  begin
    if FileExists(ChangeFileExt(FileName, '.dfm')) then
    begin
      FileName := ChangeFileExt(FileName, '.dfm');
    end
    else
    begin
      FileName := ChangeFileExt(FileName, '.fmx');
    end;
  end;
  if not TDfmParser.IsFormFile(FileName) or not ReadSourceText(FileName, Text) then
  begin
    raise EMcpToolError.CreateFmt('Formulardatei "%s" nicht gefunden', [FileName]);
  end;
  Result := TMcpIndexTools.DfmInfo(Text);
end;

procedure AddGetDfmInfo(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_dfm_info',
    'Komponenten eines Formulars (.dfm/.fmx in Textform) mit Typen, Eigenschaften und Ereignisbehandlern.',
    TMcpServer.StringSchema(['file'], ['Pfad der .dfm/.fmx-Datei oder der zugehörigen .pas-Datei']),
    ContextTool(AContext, ToolGetDfmInfo));
end;

function ToolExplainFinding(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName, Text, RuleId, RelativePath: string;
  Line: Integer;
  Finding: TRuleFinding;
  Catalog: TRuleCatalog;
  Scopes: TFindingScopes;
begin
  FileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<Integer>('line', Line) then
  begin
    raise EMcpToolError.Create('Argument "line" fehlt');
  end;
  RuleId := TMcpServer.OptionalString(AArguments, 'rule');
  if not ReadSourceText(FileName, Text) then
  begin
    raise EMcpToolError.CreateFmt('%s ist nicht lesbar', [FileName]);
  end;
  RelativePath := FileName;
  if StartsText(IncludeTrailingPathDelimiter(AContext.Root), FileName) then
  begin
    RelativePath := Copy(FileName, Length(IncludeTrailingPathDelimiter(AContext.Root)) + 1, MaxInt);
  end;
  Result := '';
  Catalog := TFindingPrompt.GermanCatalog;
  try
    for Finding in TFileChecker.CheckText(BuiltinRules, AContext.Group.Main.Configuration.Settings, RelativePath, Text,
      AContext.CheckProject(FileName), AContext.Group.Main.State.CheckSource(FileName), Scopes) do
    begin
      if (Finding.Range.StartPos.Line = Line - 1) and ((RuleId = '') or SameText(RuleId, Finding.RuleId)) then
      begin
        if Result <> '' then
        begin
          Result := Result + sLineBreak + sLineBreak;
        end;
        Result := Result + TFindingPrompt.Markdown(Finding, FileName, Text, Catalog);
      end;
    end;
  finally
    Catalog.Free;
  end;
  if Result = '' then
  begin
    raise EMcpToolError.CreateFmt('Kein Befund in Zeile %d von %s.', [Line, ExtractFileName(FileName)]);
  end;
end;

procedure AddExplainFinding(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('explain_finding',
    'Erklärt Befunde der Prüfregeln in einer Zeile (#158): Regel, Beschreibung, Codeausschnitt mit markierter Zeile ' +
    'und Vorher/Nachher-Beispiel als Markdown.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile des Befunds (ab 1)"},' +
      '"rule":{"type":"string","description":"Optional: nur diese Regel"}},' +
      '"required":["file","line"]}',
    ContextTool(AContext, ToolExplainFinding));
end;

procedure RegisterCheckTools(const AContext: TMcpToolContext);
begin
  AddGetDiagnostics(AContext);
  AddHookCheck(AContext);
  AddGetMetrics(AContext);
  AddGetTodos(AContext);
  AddCheckCode(AContext);
  AddGetDfmInfo(AContext);
  AddExplainFinding(AContext);
end;

end.
