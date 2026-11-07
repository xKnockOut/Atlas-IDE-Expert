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
  Atlas.Common.Mcp.CheckTools,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpCheckText = (GetDiagnosticsTool, GetDiagnosticsFile, HookCheckTool, HookCheckFile, HookCheckSeverity,
    GetMetricsTool, GetMetricsFile, GetMetricsFormat, GetTodosTool, GetTodosFile, GetTodosUnit, GetTodosCategory,
    GetTodosOwner, GetTodosKeyword, GetTodosIncludeDone, GetTodosFormat, CheckCodeTool, CheckCodeFile, CheckCodeText,
    CheckCodeStartLine, CheckCodeEndLine, GetDfmInfoTool, GetDfmInfoFile, ExplainFindingTool, ExplainFindingFile,
    ExplainFindingLine, ExplainFindingRule, IndexLoading, FormNotFound, Unreadable, NoFinding);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpCheckText] of TAtlasText = (
    (De: 'Syntaxfehler und Befunde der Prüfregeln (wie --check) für eine Datei oder das ganze Projekt.';
    En: 'Syntax errors and rule findings (like --check) for one file or the whole project.'),
    (De: 'Pfad einer .pas-Datei; leer = alle Projektdateien'; En: 'Path of a .pas file; empty = all project files'),
    (De: 'Für Hooks von Claude Code (PostToolUse nach Edit/Write, siehe Plugin atlas): Befunde ab severity ' +
    '(Vorgabe warning) der gerade bearbeiteten Datei als Hook-Ausgabe mit additionalContext. Leer bei ' +
    'Dateien, die kein Pascal-Quelltext sind, außerhalb des Arbeitsbereichs liegen oder keine Befunde haben. ' +
    'Abschalten über mcp.disabledTools.';
    En: 'For Claude Code hooks (PostToolUse after Edit/Write, see plugin atlas): findings from severity on ' +
    '(default warning) of the file just edited as hook output with additionalContext. Empty for files that ' +
    'are not Pascal source, lie outside the workspace or have no findings. Turn off via mcp.disabledTools.'),
    (De: 'Pfad der bearbeiteten Datei (tool_input.file_path)'; En: 'Path of the edited file (tool_input.file_path)'),
    (De: 'error, warning (Vorgabe), information oder hint'; En: 'error, warning (default), information or hint'),
    (De: 'Code-Metriken (#66) je Methode: Länge in Codezeilen, Verschachtelungstiefe, zyklomatische und kognitive ' +
    'Komplexität, Parameteranzahl; Grenzwerte aus atlas.json (Regeln metric-*, Option "max"). Als ' +
    'Markdown-Bericht mit den Methoden über einem Grenzwert oder als JSON-Daten.';
    En: 'Code metrics (#66) per method: length in lines of code, nesting depth, cyclomatic and cognitive ' +
    'complexity, parameter count; thresholds from atlas.json (rules metric-*, option "max"). As a Markdown ' +
    'report with the methods above a threshold or as JSON data.'),
    (De: 'Pfad einer .pas-Datei; leer = alle Projektdateien'; En: 'Path of a .pas file; empty = all project files'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'TODO-Übersicht (#68): Kommentare // TODO, // FIXME und das Format der IDE-To-Do-Liste { TODO 1 -oPerson ' +
    '-cKategorie : Text } aus allen Dateien des Projekts, mit Priorität, Person und Kategorie. Erledigte ' +
    'Einträge ({ DONE … }) nur mit includeDone. Weitere Marken über die Option "keywords" der Regel ' +
    'todo-comment in atlas.json. Als Markdown-Übersicht oder als JSON-Daten.';
    En: 'TODO overview (#68): comments // TODO, // FIXME and the format of the IDE to-do list { TODO 1 -oPerson ' +
    '-cCategory : Text } from all files of the project, with priority, person and category. Done entries ({ ' +
    'DONE … }) only with includeDone. More markers via the option "keywords" of the rule todo-comment in ' +
    'atlas.json. As a Markdown overview or as JSON data.'),
    (De: 'Pfad einer .pas-Datei; leer = alle Projektdateien'; En: 'Path of a .pas file; empty = all project files'),
    (De: 'Nur diese Unit (Name oder Pfad relativ zum Projekt)';
    En: 'Only this unit (name or path relative to the project)'),
    (De: 'Nur diese Kategorie (-c)'; En: 'Only this category (-c)'),
    (De: 'Nur diese Person (-o)'; En: 'Only this person (-o)'),
    (De: 'Nur diese Marke, z. B. FIXME'; En: 'Only this marker, e.g. FIXME'),
    (De: 'Auch erledigte Einträge (DONE); Vorgabe false'; En: 'Also done entries (DONE); default false'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'Prüft geplanten Code ohne zu schreiben (#178): Syntaxfehler, Regeltreffer und nicht auflösbare ' +
    'Bezeichner. Entweder den ganzen neuen Text der Unit angeben oder mit startLine/endLine nur einen ' +
    'Zeilenbereich ersetzen.';
    En: 'Checks planned code without writing (#178): syntax errors, rule findings and unresolvable identifiers. ' +
    'Either give the whole new text of the unit or replace only a line range with startLine/endLine.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Neuer Text: die ganze Unit oder der Ersatz für startLine..endLine';
    En: 'New text: the whole unit or the replacement for startLine..endLine'),
    (De: 'Erste ersetzte Zeile (ab 1); ohne Angabe ist text die ganze Unit';
    En: 'First replaced line (from 1); without it, text is the whole unit'),
    (De: 'Letzte ersetzte Zeile; startLine - 1 fügt nur ein'; En: 'Last replaced line; startLine - 1 only inserts'),
    (De: 'Komponenten eines Formulars (.dfm/.fmx in Textform) mit Typen, Eigenschaften und Ereignisbehandlern.';
    En: 'Components of a form (.dfm/.fmx in text form) with types, properties and event handlers.'),
    (De: 'Pfad der .dfm/.fmx-Datei oder der zugehörigen .pas-Datei';
    En: 'Path of the .dfm/.fmx file or of the matching .pas file'),
    (De: 'Erklärt Befunde der Prüfregeln in einer Zeile (#158): Regel, Beschreibung, Codeausschnitt mit ' +
    'markierter Zeile und Vorher/Nachher-Beispiel als Markdown.';
    En: 'Explains the rule findings in one line (#158): rule, description, code excerpt with the line marked and ' +
    'a before/after example as Markdown.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Zeile des Befunds (ab 1)'; En: 'Line of the finding (from 1)'),
    (De: 'Optional: nur diese Regel'; En: 'Optional: only this rule'),
    (De: 'Hinweis: %s; Befunde, die den Symbolindex brauchen, können noch fehlen.';
    En: 'Note: %s; findings that need the symbol index may still be missing.'),
    (De: 'Formulardatei "%s" nicht gefunden'; En: 'Form file "%s" not found'),
    (De: '%s ist nicht lesbar'; En: '%s is not readable'),
    (De: 'Kein Befund in Zeile %d von %s.'; En: 'No finding in line %d of %s.'));

function ToolGetDiagnostics(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mReason: string;
  mFiles: TArray<string>;
begin
  mFileName := TMcpServer.OptionalString(AArguments, 'file');
  if mFileName <> '' then
  begin
    mFiles := [AContext.Guard.Resolve(mFileName)];
  end
  else
  begin
    mFiles := AContext.Group.Main.State.ProjectFiles;
  end;
  if Length(mFiles) = 0 then
  begin
    raise EMcpToolError.Create(TShellTexts.NoProjectGiveFile);
  end;
  Result := TMcpCheckTools.Diagnostics(TMcpRuleScope.Create(BuiltinRules,
    AContext.Group.Main.Configuration.Settings, AContext.Root), mFiles, ReadSourceText,
    AContext.CheckSource, AContext.CheckProject);
  // Solange der Index lädt, sehen Regeln, die Typen anderer Units brauchen, noch nicht alles (#1112).
  if not AContext.Group.Ready(mReason) then
  begin
    Result := cTexts[TMcpCheckText.IndexLoading].Fmt([mReason]) + sLineBreak + Result;
  end;
end;

procedure AddGetDiagnostics(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_diagnostics', cTexts[TMcpCheckText.GetDiagnosticsTool].Text,
    TMcpServer.StringSchema(['file'],
      [cTexts[TMcpCheckText.GetDiagnosticsFile].Text], 0),
    ContextTool(AContext, ToolGetDiagnostics));
end;

function ToolHookCheck(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName: string;
  mSeverity: TRuleSeverity;
begin
  mSeverity := TMcpCheckTools.ParseHookSeverity(TMcpServer.OptionalString(AArguments, 'severity'));
  try
    mFileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  except
    // Dateien außerhalb des Projekts gehen Atlas nichts an; eine Fehlermeldung je Bearbeitung wäre Rauschen.
    on EMcpToolError do
      Exit('');
  end;
  Result := TMcpCheckTools.HookDiagnostics(TMcpRuleScope.Create(BuiltinRules,
    AContext.Group.Main.Configuration.Settings, AContext.Root), mFileName, ReadSourceText,
    AContext.CheckSource, AContext.CheckProject, mSeverity);
end;

procedure AddHookCheck(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('hook_check', cTexts[TMcpCheckText.HookCheckTool].Text,
    TMcpServer.StringSchema(['file', 'severity'],
      [cTexts[TMcpCheckText.HookCheckFile].Text,
      cTexts[TMcpCheckText.HookCheckSeverity].Text], 1),
    ContextTool(AContext, ToolHookCheck));
end;

function ToolGetMetrics(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mFormat: string;
  mFiles: TArray<string>;
begin
  mFileName := TMcpServer.OptionalString(AArguments, 'file');
  mFormat := TMcpServer.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'markdown') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
  if mFileName <> '' then
  begin
    mFiles := [AContext.Guard.Resolve(mFileName)];
  end
  else
  begin
    mFiles := AContext.Group.Main.State.ProjectFiles;
  end;
  if Length(mFiles) = 0 then
  begin
    raise EMcpToolError.Create(TShellTexts.NoProjectGiveFile);
  end;
  Result := TMcpCheckTools.Metrics(AContext.Group.Main.Configuration.Settings, AContext.Root, mFiles, ReadSourceText,
    SameText(mFormat, 'json'));
end;

procedure AddGetMetrics(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_metrics', cTexts[TMcpCheckText.GetMetricsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}}}',
      [cTexts[TMcpCheckText.GetMetricsFile].Text,
      cTexts[TMcpCheckText.GetMetricsFormat].Text]),
    ContextTool(AContext, ToolGetMetrics));
end;

function ToolGetTodos(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mFormat: string;
  mFiles: TArray<string>;
  mFilter: TTodoFilter;
  mIncludeDone: Boolean;
begin
  mFileName := TMcpServer.OptionalString(AArguments, 'file');
  mFormat := TMcpServer.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'markdown') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
  mFilter := TTodoFilter.Default;
  mFilter.UnitName := TMcpServer.OptionalString(AArguments, 'unit');
  mFilter.Category := TMcpServer.OptionalString(AArguments, 'category');
  mFilter.Owner := TMcpServer.OptionalString(AArguments, 'owner');
  mFilter.Keyword := TMcpServer.OptionalString(AArguments, 'keyword');
  if (AArguments <> nil) and AArguments.TryGetValue<Boolean>('includeDone', mIncludeDone) then
  begin
    mFilter.IncludeDone := mIncludeDone;
  end;
  // Projektweit heißt: die Dateien, die das Projektmodell (#14) dem Projekt zuordnet.
  if mFileName <> '' then
  begin
    mFiles := [AContext.Guard.Resolve(mFileName)];
  end
  else
  begin
    mFiles := AContext.Group.Main.State.ProjectFiles;
  end;
  if Length(mFiles) = 0 then
  begin
    raise EMcpToolError.Create(TShellTexts.NoProjectGiveFile);
  end;
  Result := TMcpCheckTools.Todos(AContext.Group.Main.Configuration.Settings, AContext.Root, mFiles, ReadSourceText,
    mFilter,
    SameText(mFormat, 'json'));
end;

procedure AddGetTodos(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_todos', cTexts[TMcpCheckText.GetTodosTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"unit":{"type":"string","description":%s},' +
      '"category":{"type":"string","description":%s},' +
      '"owner":{"type":"string","description":%s},' +
      '"keyword":{"type":"string","description":%s},' +
      '"includeDone":{"type":"boolean","description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}}}',
      [cTexts[TMcpCheckText.GetTodosFile].Text,
      cTexts[TMcpCheckText.GetTodosUnit].Text,
      cTexts[TMcpCheckText.GetTodosCategory].Text,
      cTexts[TMcpCheckText.GetTodosOwner].Text,
      cTexts[TMcpCheckText.GetTodosKeyword].Text,
      cTexts[TMcpCheckText.GetTodosIncludeDone].Text,
      cTexts[TMcpCheckText.GetTodosFormat].Text]),
    ContextTool(AContext, ToolGetTodos));
end;

function ToolCheckCode(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText: string;
  mStartLine, mEndLine: Integer;
begin
  mFileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<string>('text', mText) then
  begin
    raise EMcpToolError.Create(TShellTexts.Missing(['text']));
  end;
  if not AArguments.TryGetValue<Integer>('startLine', mStartLine) then
  begin
    mStartLine := 0;
  end;
  if not AArguments.TryGetValue<Integer>('endLine', mEndLine) then
  begin
    mEndLine := mStartLine;
  end;
  Result := AContext.Code.CheckCode(TMcpRuleScope.Create(BuiltinRules, AContext.Group.Main.Configuration.Settings,
    AContext.Root), mFileName, mText,
    mStartLine, mEndLine);
end;

procedure AddCheckCode(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('check_code', cTexts[TMcpCheckText.CheckCodeTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"text":{"type":"string","description":%s},' +
      '"startLine":{"type":"integer","minimum":1,"description":%s},' +
      '"endLine":{"type":"integer","minimum":0,"description":%s}},' +
      '"required":["file","text"]}',
      [cTexts[TMcpCheckText.CheckCodeFile].Text,
      cTexts[TMcpCheckText.CheckCodeText].Text,
      cTexts[TMcpCheckText.CheckCodeStartLine].Text,
      cTexts[TMcpCheckText.CheckCodeEndLine].Text]),
    ContextTool(AContext, ToolCheckCode));
end;

function ToolGetDfmInfo(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText: string;
begin
  mFileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if SameText(ExtractFileExt(mFileName), '.pas') then
  begin
    if FileExists(ChangeFileExt(mFileName, '.dfm')) then
    begin
      mFileName := ChangeFileExt(mFileName, '.dfm');
    end
    else
    begin
      mFileName := ChangeFileExt(mFileName, '.fmx');
    end;
  end;
  if not TDfmParser.IsFormFile(mFileName) or not ReadSourceText(mFileName, mText) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpCheckText.FormNotFound].Fmt([mFileName]));
  end;
  Result := TMcpIndexTools.DfmInfo(mText);
end;

procedure AddGetDfmInfo(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_dfm_info', cTexts[TMcpCheckText.GetDfmInfoTool].Text,
    TMcpServer.StringSchema(['file'],
      [cTexts[TMcpCheckText.GetDfmInfoFile].Text]),
    ContextTool(AContext, ToolGetDfmInfo));
end;

function ToolExplainFinding(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText, mRuleId, mRelativePath: string;
  mLine: Integer;
  mFinding: TRuleFinding;
  mCatalog: TRuleCatalog;
  mScopes: TFindingScopes;
begin
  mFileName := AContext.Guard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
  if not AArguments.TryGetValue<Integer>('line', mLine) then
  begin
    raise EMcpToolError.Create(TShellTexts.Missing(['line']));
  end;
  mRuleId := TMcpServer.OptionalString(AArguments, 'rule');
  if not ReadSourceText(mFileName, mText) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpCheckText.Unreadable].Fmt([mFileName]));
  end;
  mRelativePath := mFileName;
  if StartsText(IncludeTrailingPathDelimiter(AContext.Root), mFileName) then
  begin
    mRelativePath := Copy(mFileName, Length(IncludeTrailingPathDelimiter(AContext.Root)) + 1, MaxInt);
  end;
  Result := '';
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    for mFinding in TFileChecker.CheckText(BuiltinRules, AContext.Group.Main.Configuration.Settings, mRelativePath,
      mText,
      TCheckOrigin.Make(AContext.CheckProject(mFileName), AContext.Group.Main.State.CheckSource(mFileName)), mScopes) do
    begin
      if (mFinding.Range.StartPos.Line = mLine - 1) and ((mRuleId = '') or SameText(mRuleId, mFinding.RuleId)) then
      begin
        if Result <> '' then
        begin
          Result := Result + sLineBreak + sLineBreak;
        end;
        Result := Result + TFindingPrompt.Markdown(mFinding, mFileName, mText, mCatalog);
      end;
    end;
  finally
    mCatalog.Free;
  end;
  if Result = '' then
  begin
    raise EMcpToolError.Create(cTexts[TMcpCheckText.NoFinding].Fmt([mLine, ExtractFileName(mFileName)]));
  end;
end;

procedure AddExplainFinding(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('explain_finding', cTexts[TMcpCheckText.ExplainFindingTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"rule":{"type":"string","description":%s}},' +
      '"required":["file","line"]}',
      [cTexts[TMcpCheckText.ExplainFindingFile].Text,
      cTexts[TMcpCheckText.ExplainFindingLine].Text,
      cTexts[TMcpCheckText.ExplainFindingRule].Text]),
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

initialization
  TAtlasTextTables.Add('Shell.Mcp.CheckTools', cTexts);

end.
