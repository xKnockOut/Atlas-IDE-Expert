unit Shell.Mcp.ProjectTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge über das ganze Projekt: Status (#1356), Code-Abfragen
// (#1351), toter Code, betroffene Tests (#1353), Hotspots (#1354) siehe Shell.Mcp.ChangeTools.

interface

uses
  Shell.Mcp.Context;

/// <summary>get_server_status (#1356): Status des Servers der IDE aus der Statusdatei, sonst dieses Prozesses.
/// </summary>
procedure RegisterStatusTools(const AContext: TMcpToolContext);
/// <summary>query_code (#1351): Code-Abfragen über den Index der Gruppe; nur lesend.</summary>
procedure RegisterQueryTools(const AContext: TMcpToolContext);
/// <summary>Werkzeuge für toten Code und Unit-Abhängigkeiten (#64): Projekte, Index und Uses-Graph der Gruppe wie bei den Prüfregeln (#1112).</summary>
procedure RegisterDeadCodeTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Index.Contract,
  Shell.WorkspaceGroup,
  System.DateUtils,
  System.JSON,
  Atlas.Common.Product.Version,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Mcp.DeadCodeTools,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Mcp.StatusTools,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Catalog,
  Atlas.Common.Query.Output,
  Shell.Platform,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpProjectText = (StatusTool, StatusFormat, QueryCodeTool, QueryCodeQuery, QueryCodeFormat, QueryCodeLimit,
    FindUnusedCodeTool, FindUnusedCodeFile, FindUnusedCodeFormat, GetUnitDependenciesTool, GetUnitDependenciesUnit,
    GetUnitDependenciesDirection, GetUnitDependenciesTransitive, GetUnitDependenciesFormat, NoSavedQuery, QueriesOff);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpProjectText] of TAtlasText = (
    (De: 'Status des Atlas-Servers (#1356) wie im Fenster „Atlas-Server“ der IDE: Speicher je Bereich gegen das ' +
    'Budget, die langsamsten Units und Regeln des letzten Prüflaufs, Warteschlange, Cache-Treffer und die ' +
    'langsamsten Anfragen. Läuft für den Projektordner kein Server der IDE, der Status dieses MCP-Prozesses. ' +
    'Nur lesend; hilfreich, wenn Atlas oder die IDE langsam ist oder viel Speicher braucht.';
    En: 'Status of the Atlas server (#1356) as in the “Atlas server” window of the IDE: memory per area against ' +
    'the budget, the slowest units and rules of the last check run, queue, cache hits and the slowest ' +
    'requests. If no IDE server runs for the project folder, the status of this MCP process. Read-only; ' +
    'helpful when Atlas or the IDE is slow or uses a lot of memory.'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'Code-Abfragen über den Index (#1351) in einer kleinen Sprache: <Menge> where <Bedingung> [order by ' +
    '<Feld> [asc|desc]] [limit n]. Mengen: units, classes, records, interfaces, methods, routines, fields, ' +
    'properties, forms. Felder z. B. name, unit, visibility, methods, lines, complexity, cognitive, params, ' +
    'callers, callees, uses, usedBy, ancestor, components; Prädikate inherits, implements, uses, calls, has ' +
    'attribute; and, or, not, Klammern, like mit * und ?. Beispiel: classes where inherits TForm and methods ' +
    '> 40 order by methods desc. Zahlen wie get_metrics und find_unused_code; erschlossene Aufrufe (#1119) ' +
    'sind als „erschlossen“ markiert. Ohne query die Kurzhilfe mit allen Feldern. Gespeicherte Abfragen aus ' +
    'atlas.json über @name.';
    En: 'Code queries over the index (#1351) in a small language: <set> where <condition> [order by <field> ' +
    '[asc|desc]] [limit n]. Sets: units, classes, records, interfaces, methods, routines, fields, ' +
    'properties, forms. Fields e.g. name, unit, visibility, methods, lines, complexity, cognitive, params, ' +
    'callers, callees, uses, usedBy, ancestor, components; predicates inherits, implements, uses, calls, has ' +
    'attribute; and, or, not, parentheses, like with * and ?. Example: classes where inherits TForm and ' +
    'methods > 40 order by methods desc. Numbers as in get_metrics and find_unused_code; inferred calls ' +
    '(#1119) are marked as inferred. Without query the short help with all fields. Saved queries from ' +
    'atlas.json via @name.'),
    (De: 'Abfrage oder @name einer gespeicherten Abfrage; leer = Kurzhilfe';
    En: 'Query or @name of a saved query; empty = short help'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'Höchstzahl der Zeilen; Vorgabe 200'; En: 'Maximum number of rows; default 200'),
    (De: 'Ungenutzter Code (#64): private und öffentliche Member, Deklarationen nur im implementation-Teil und ' +
    'Units, die nur das Programm nennt, mit dem Index aller Projekte der Gruppe wie im Editor. Schweregrad, ' +
    'Optionen und deadCode.keepAttributes/keepPatterns aus atlas.json gelten. Als Markdown-Bericht oder als ' +
    'JSON-Daten.';
    En: 'Unused code (#64): private and public members, declarations only in the implementation section and ' +
    'units only the program names, with the index of all projects of the group as in the editor. Severity, ' +
    'options and deadCode.keepAttributes/keepPatterns from atlas.json apply. As a Markdown report or as JSON ' +
    'data.'),
    (De: 'Pfad einer .pas-Datei; leer = alle Projektdateien'; En: 'Path of a .pas file; empty = all project files'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'Abhängigkeiten einer Unit (#64): direkte uses und die Units, die sie verwenden, je mit Abschnitt ' +
    '(interface/implementation), auf Wunsch die transitiven Hüllen, dazu die Zyklen durch die Unit mit ' +
    'vollständigem Pfad. Nur Units der Projekte, ohne RTL/VCL. Als Markdown oder als JSON-Daten.';
    En: 'Dependencies of a unit (#64): direct uses and the units that use it, each with its section ' +
    '(interface/implementation), on request the transitive closures, plus the cycles through the unit with ' +
    'the complete path. Only units of the projects, without RTL/VCL. As Markdown or as JSON data.'),
    (De: 'Unit-Name (Ref.Daten) oder Pfad der .pas-Datei'; En: 'Unit name (Ref.Data) or path of the .pas file'),
    (De: 'Richtung; Vorgabe both'; En: 'Direction; default both'),
    (De: 'Auch die transitiven Hüllen; Vorgabe false'; En: 'Also the transitive closures; default false'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'Keine gespeicherte Abfrage "%s" in atlas.json (queries)';
    En: 'No saved query "%s" in atlas.json (queries)'),
    (De: 'Code-Abfragen sind ausgeschaltet (query.enabled)'; En: 'Code queries are turned off (query.enabled)'));

/// <summary>Status dieses MCP-Prozesses für get_server_status, wenn kein Server der IDE läuft (#1356).</summary>
function OwnStatus(const AIndex: ISymbolIndex; AStarted: TDateTime): TServerStatus;
var
  mParts: TIndexMemoryParts;
  mTrees: TSyntaxTreeCacheStats;
begin
  Result := Default(TServerStatus);
  Result.ProcessId := TShellPlatform.CurrentProcessId;
  Result.Version := TProductVersion.cVersion;
  Result.Started := AStarted;
  Result.UptimeMs := MilliSecondsBetween(Now, AStarted);
  Result.State := TServerStatus.cStateReady;
  Result.MemoryBytes := TShutdownLeaks.AllocatedBytes;
  Result.IndexCacheHitPercent := -1;
  mTrees := TSyntaxTreeCache.Stats;
  Result.TreeCacheHitPercent := mTrees.HitPercent;
  Result.TreeCacheTrees := mTrees.Trees;
  Result.Memory.TreeCache := mTrees.Bytes;
  Result.Memory.Packages := TPackageCompiledFiles.Bytes;
  Result.Memory.Total := Result.MemoryBytes;
  if AIndex = nil then
  begin
    Exit;
  end;
  Result.Units := AIndex.UnitCount;
  Result.Symbols := AIndex.SymbolCount;
  Result.IndexBytes := AIndex.MemoryBytes;
  Result.CompactUnits := AIndex.CompactCount;
  Result.OffloadedUnits := AIndex.OffloadedCount;
  Result.BudgetBytes := AIndex.Budget;
  mParts := AIndex.MemoryParts;
  Result.Memory.Symbols := mParts.ProjectBytes;
  Result.Memory.LibraryUnits := mParts.LibraryBytes;
  Result.Memory.Usages := mParts.UsageBytes;
  Result.Memory.Budget := Result.BudgetBytes;
end;
function ToolGetServerStatus(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFormat: string;
begin
  mFormat := TMcpServer.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'markdown') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
  Result := TMcpStatusTools.ServerStatus(TIndexCacheDirectory.DefaultRoot, AContext.Root, SameText(mFormat, 'json'), Now,
    function: TServerStatus
    begin
      Result := OwnStatus(AContext.Index, AContext.Started);
    end);
end;

procedure AddGetServerStatus(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool(TMcpStatusTools.cToolName, cTexts[TMcpProjectText.StatusTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}}}',
      [cTexts[TMcpProjectText.StatusFormat].Text]),
    ContextTool(AContext, ToolGetServerStatus));
end;


/// <summary>get_server_status (#1356): Status des Servers der IDE aus der Statusdatei, sonst dieses Prozesses.
/// </summary>
procedure RegisterStatusTools(const AContext: TMcpToolContext);
begin
  AddGetServerStatus(AContext);
end;
/// <summary>Text der Abfrage; "@name" wird zur gespeicherten Abfrage aus atlas.json (queries).</summary>
function QueryTextOf(const ASettings: TServerSettings; const AText: string): string;
var
  mSaved: TSavedQuery;
begin
  Result := AText;
  if not Result.StartsWith('@') then
  begin
    Exit;
  end;
  for mSaved in ASettings.Queries do
  begin
    if SameText(mSaved.Name, Copy(AText, 2, MaxInt)) then
    begin
      Exit(mSaved.Query);
    end;
  end;
  raise EMcpToolError.Create(cTexts[TMcpProjectText.NoSavedQuery].Fmt([Copy(AText, 2, MaxInt)]));
end;

/// <summary>Format von query_code: markdown oder json ('' = markdown).</summary>
function QueryFormatOf(const AArguments: TJSONObject): string;
begin
  Result := TMcpServer.OptionalString(AArguments, 'format');
  if (Result <> '') and not SameText(Result, 'markdown') and not SameText(Result, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
end;

/// <summary>Führt die Abfrage AText mit höchstens limit Zeilen (Vorgabe 200) aus.</summary>
function RunQuery(AGroup: TShellWorkspaceGroup; const AText: string; const AArguments: TJSONObject): TQueryResult;
var
  mLimit: Integer;
begin
  if not AArguments.TryGetValue<Integer>('limit', mLimit) or (mLimit < 1) then
  begin
    mLimit := 200;
  end;
  Result := AGroup.Queries.Execute(TQueryRequest.Create(AText, mLimit));
  if Result.Failed then
  begin
    raise EMcpToolError.Create(TQueryOutput.ErrorText(Result));
  end;
end;

function ToolQueryCode(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mText, mFormat: string;
  mSettings: TServerSettings;
  mResult: TQueryResult;
begin
  mSettings := AContext.Group.Main.Configuration.Settings;
  if not mSettings.QueryEnabled then
  begin
    raise EMcpToolError.Create(cTexts[TMcpProjectText.QueriesOff].Text);
  end;
  mFormat := QueryFormatOf(AArguments);
  mText := Trim(TMcpServer.OptionalString(AArguments, 'query'));
  if mText = '' then
  begin
    Exit(TQueryCatalog.Help);
  end;
  mResult := RunQuery(AContext.Group, QueryTextOf(mSettings, mText), AArguments);
  if SameText(mFormat, 'json') then
  begin
    Result := TQueryOutput.Json(mResult);
  end
  else
  begin
    Result := TQueryOutput.Markdown(mResult);
  end;
end;

procedure AddQueryCode(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('query_code', cTexts[TMcpProjectText.QueryCodeTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"query":{"type":"string","description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s},' +
      '"limit":{"type":"integer","minimum":1,"default":200,"description":%s}}}',
      [cTexts[TMcpProjectText.QueryCodeQuery].Text,
      cTexts[TMcpProjectText.QueryCodeFormat].Text,
      cTexts[TMcpProjectText.QueryCodeLimit].Text]),
    ContextTool(AContext, ToolQueryCode));
end;


/// <summary>query_code (#1351): Code-Abfragen über den Index der Gruppe; nur lesend.</summary>
procedure RegisterQueryTools(const AContext: TMcpToolContext);
begin
  AddQueryCode(AContext);
end;
function ToolFindUnusedCode(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName, Format: string;
  Files: TArray<string>;
begin
  FileName := TMcpServer.OptionalString(AArguments, 'file');
  Format := TMcpServer.OptionalString(AArguments, 'format');
  if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
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
    raise EMcpToolError.Create(TShellTexts.NoProjectGiveFile);
  end;
  Result := TMcpDeadCodeTools.FindUnused(TMcpRuleScope.Create(BuiltinRules,
    AContext.Group.Main.Configuration.Settings, AContext.Root), Files, AContext.Index, AContext.Group.RuleProjectFiles, AContext.Group.Main.State.Namespaces, SameText(Format, 'json'));
end;

procedure AddFindUnusedCode(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_unused_code', cTexts[TMcpProjectText.FindUnusedCodeTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}}}',
      [cTexts[TMcpProjectText.FindUnusedCodeFile].Text,
      cTexts[TMcpProjectText.FindUnusedCodeFormat].Text]),
    ContextTool(AContext, ToolFindUnusedCode));
end;

function ToolGetUnitDependencies(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  UnitName, Format, Text: string;
  Direction: TMcpUsesDirection;
  Transitive: Boolean;
begin
  UnitName := TMcpServer.RequiredString(AArguments, 'unit');
  if (Pos('\', UnitName) > 0) or (Pos('/', UnitName) > 0) or SameText(ExtractFileExt(UnitName), '.pas') then
  begin
    UnitName := AContext.Guard.Resolve(UnitName);
  end;
  if not TMcpDeadCodeTools.ParseDirection(TMcpServer.OptionalString(AArguments, 'direction'), Direction) then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('direction', ['uses', 'usedBy', 'both']));
  end;
  if not AArguments.TryGetValue<Boolean>('transitive', Transitive) then
  begin
    Transitive := False;
  end;
  Format := TMcpServer.OptionalString(AArguments, 'format');
  if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
  Text := '';
  AContext.Group.UsesGraph.Read(
    procedure(const AUses: TUsesGraph)
    begin
      Text := TMcpDeadCodeTools.UnitDependencies(AUses, UnitName, AContext.Root, Direction, Transitive,
        SameText(Format, 'json'));
    end);
  Result := Text;
end;

procedure AddGetUnitDependencies(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_unit_dependencies', cTexts[TMcpProjectText.GetUnitDependenciesTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"unit":{"type":"string","description":%s},' +
      '"direction":{"type":"string","enum":["uses","usedBy","both"],"description":%s},' +
      '"transitive":{"type":"boolean","description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}},' +
      '"required":["unit"]}',
      [cTexts[TMcpProjectText.GetUnitDependenciesUnit].Text,
      cTexts[TMcpProjectText.GetUnitDependenciesDirection].Text,
      cTexts[TMcpProjectText.GetUnitDependenciesTransitive].Text,
      cTexts[TMcpProjectText.GetUnitDependenciesFormat].Text]),
    ContextTool(AContext, ToolGetUnitDependencies));
end;


/// <summary>Werkzeuge für toten Code und Unit-Abhängigkeiten (#64): Projekte, Index und Uses-Graph der Gruppe wie bei den Prüfregeln (#1112).</summary>
procedure RegisterDeadCodeTools(const AContext: TMcpToolContext);
begin
  AddFindUnusedCode(AContext);
  AddGetUnitDependencies(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.ProjectTools', cTexts);

end.
