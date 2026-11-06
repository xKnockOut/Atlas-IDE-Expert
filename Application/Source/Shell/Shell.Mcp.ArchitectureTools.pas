unit Shell.Mcp.ArchitectureTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Architekturübersicht (get_architecture, #1118) und
// Pfadsuche zwischen Symbolen (find_path, #1117).

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Service,
  Shell.Workspace,
  Shell.Mcp.Context;

/// <summary>find_path über einen eigenen Uses-Graphen samt Bibliotheks-Units. In eigener Routine, damit die
/// anonyme Methode nicht den Rahmen von Run einfängt (Leck unter Delphi).</summary>
function FindPathOf(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService; ALocator: TUsesLocator;
  AWorkspace: TShellWorkspace; const AEnsure: TFunc<string, Boolean>; const ARoot: string): TMcpFindPathFunc;
/// <summary>get_architecture über AArchitecture für den Ordner von AWorkspace.</summary>
function ArchitectureOf(AWorkspace: TShellWorkspace; AArchitecture: TArchitectureService;
  const AAllFiles: TFunc<TArray<string>>; const ARoot: string): TMcpArchitectureFunc;
/// <summary>Meldet get_architecture und find_path an.</summary>
procedure RegisterArchitectureTools(const AContext: TMcpToolContext);

implementation

uses
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.SymbolPath,
  Atlas.Common.Lsp.SymbolPath,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpArchitectureText = (GetArchitectureTool, GetArchitectureSection, GetArchitectureUnit,
    GetArchitectureCompareWith, GetArchitectureResolution, FindPathTool, FindPathFrom, FindPathTo, FindPathVia,
    FindPathMaxSteps, FindPathAll, ArchitectureOff, ResolutionRange);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpArchitectureText] of TAtlasText = (
    (De: 'Architekturübersicht (#1118) aus dem uses-Graphen: Teilsysteme (Gruppen eng verbundener Units), ' +
    'zentrale Units, Zyklen und Querverbindungen zwischen Teilsystemen, je mit Datei:Zeile der ' +
    'uses-Einträge. Mit "unit" der Steckbrief einer Unit (Teilsystem, Abhängigkeiten, Zyklen, Ausreißer). ' +
    'Mit "compareWith" der Vergleich mit einem gespeicherten Stand (#1121): neue und entfernte Zyklen, ' +
    'Querverbindungen und uses-Kanten zwischen Teilsystemen, Teilsystemwechsel, gewachsene zentrale Units, ' +
    'neue und entfernte Units. Umfang und Bibliotheks-Units aus architecture.* in atlas.json. "resolution" ' +
    '(0,2–5,0) stellt die Feinheit der Teilsysteme für diesen Aufruf ein (#1366): größer = mehr und kleinere ' +
    'Teilsysteme.';
    En: 'Architecture overview (#1118) from the uses graph: subsystems (groups of closely connected units), ' +
    'central units, cycles and cross links between subsystems, each with file:line of the uses entries. With ' +
    '"unit" the profile of one unit (subsystem, dependencies, cycles, outliers). With "compareWith" the ' +
    'comparison with a saved state (#1121): new and removed cycles, cross links and uses edges between ' +
    'subsystems, subsystem changes, grown central units, new and removed units. Scope and library units from ' +
    'architecture.* in atlas.json. "resolution" (0.2–5.0) sets the granularity of the subsystems for this ' +
    'call (#1366): larger = more and smaller subsystems.'),
    (De: 'Abschnitt; Vorgabe overview'; En: 'Section; default overview'),
    (De: 'Steckbrief dieser Unit statt eines Abschnitts'; En: 'Profile of this unit instead of a section'),
    (De: 'Gespeicherter Stand (JSON aus AtlasServer --architecture <Datei.json>), Pfad relativ zum Projekt: ' +
    'liefert die Abschnitte des Vergleichs';
    En: 'Saved state (JSON from AtlasServer --architecture <file.json>), path relative to the project: returns ' +
    'the sections of the comparison'),
    (De: 'Feinheit der Teilsysteme (Louvain-Auflösung γ); Vorgabe architecture.grouping.resolution, 1 = klassisch';
    En: 'Granularity of the subsystems (Louvain resolution γ); default architecture.grouping.resolution, 1 = ' +
    'classic'),
    (De: 'Kürzester Weg zwischen zwei Symbolen oder Units (#1117), z. B. „Wie hängt TKundenForm mit TDatenbank ' +
    'zusammen?“, in einem Aufruf statt vieler find_references/get_call_hierarchy. Kanten: uses, inherits, ' +
    'implements (auch Interface → Umsetzung), hasField, parameter, result, calls, contains. Liefert die ' +
    'Kette mit Kantenart und Datei:Zeile je Schritt; erschlossene Kanten (mehrere Umsetzungen) tragen ' +
    '[erschlossen]. „Kein Weg“ ist eine verlässliche Antwort; bei mehrdeutigem Namen kommt die Trefferliste.';
    En: 'Shortest path between two symbols or units (#1117), e.g. "How is TCustomerForm connected to ' +
    'TDatabase?", in one call instead of many find_references/get_call_hierarchy calls. Edges: uses, ' +
    'inherits, implements (also interface → implementation), hasField, parameter, result, calls, contains. ' +
    'Returns the chain with edge kind and file:line for each step; inferred edges (several implementations) ' +
    'are marked as inferred. "No path" is a reliable answer; for an ambiguous name the list of matches is ' +
    'returned.'),
    (De: 'Start: Typ, Methode (TFoo.Bar), Routine, Feld, Property oder Unit';
    En: 'Start: type, method (TFoo.Bar), routine, field, property or unit'),
    (De: 'Ziel, Angabe wie bei from; ein Typ zählt samt seinen Mitgliedern';
    En: 'Target, given like from; a type counts together with its members'),
    (De: 'Erlaubte Kantenarten (Vorgabe alle); library erlaubt RTL/VCL als Durchgang';
    En: 'Allowed edge kinds (default all); library allows RTL/VCL as a passage'),
    (De: 'Höchstens so viele Schritte, Vorgabe 8'; En: 'At most this many steps, default 8'),
    (De: 'Alle gleich kurzen Wege (höchstens 5) statt nur des ersten';
    En: 'All equally short paths (at most 5) instead of only the first'),
    (De: 'Architekturübersicht ist ausgeschaltet (architecture.enabled)';
    En: 'Architecture overview is turned off (architecture.enabled)'),
    (De: '"resolution" ist eine Zahl von 0,2 bis 5,0'; En: '"resolution" is a number from 0.2 to 5.0'));

/// <summary>Argumente von find_path; EMcpToolError bei ungültigen Werten.</summary>
function FindPathRequest(const AArguments: TJSONObject): TSymbolPathRequest;
begin
  try
    Result := TLspSymbolPath.ReadRequest(AArguments);
  except
    on E: EJsonRpcError do
      raise EMcpToolError.Create(E.Message);
  end;
end;

/// <summary>Anfrage für die Architekturübersicht des Ordners; AResolution > 0 gilt nur für diesen Aufruf (#1366).
/// </summary>
function ArchitectureRequestOf(AWorkspace: TShellWorkspace; const AAllFiles: TFunc<TArray<string>>;
  const ARoot: string; AResolution: Double): TArchitectureRequest;
var
  mSettings: TServerSettings;
begin
  mSettings := AWorkspace.Configuration.Settings;
  if not mSettings.ArchitectureEnabled then
  begin
    raise EMcpToolError.Create(cTexts[TMcpArchitectureText.ArchitectureOff].Text);
  end;
  Result := TArchitectureRequest.FromSettings(mSettings);
  if AResolution > 0 then
  begin
    Result.Grouping.Resolution := AResolution;
  end;
  Result.Title := ExtractFileName(ARoot);
  Result.Root := ARoot;
  Result.Namespaces := AWorkspace.State.Namespaces;
  // Projektgruppe (#648): die Dateien aller geladenen Projekte, sonst nur die des Hauptprojekts.
  if Result.Scope = 'project' then
  begin
    Result.Files := AWorkspace.State.ProjectFiles;
  end
  else
  begin
    Result.Files := AAllFiles();
  end;
  if Length(Result.Files) = 0 then
  begin
    raise EMcpToolError.Create(TShellTexts.NoProject);
  end;
  // Derselbe zuletzt berechnete Stand wie im LSP-Prozess (#1367).
  Result.PreviousFile := TIndexCacheDirectory.ArchitectureFileFor(TIndexCacheDirectory.DefaultRoot, Result.ScopeKey);
end;

/// <summary>Vergleich von AOverview mit dem gespeicherten Stand ACompareWith (#1121) als Text.</summary>
function ComparisonText(const AOverview: TArchitectureOverview; const ACompareWith: string;
  const AFailOnSetting: TArray<string>): string;
var
  mComparison: TArchitectureComparison;
  mFailOn: TArchitectureFailKinds;
  mError: string;
begin
  if not TArchitectureComparer.CompareWithFile(ACompareWith, AOverview, mComparison, mError) then
  begin
    raise EMcpToolError.Create(mError);
  end;
  if not TArchitectureComparer.ParseKinds(AFailOnSetting, mFailOn, mError) then
  begin
    mFailOn := TArchitectureComparer.DefaultFailOn;
  end;
  Result := TArchitectureComparer.Text(mComparison, mFailOn, TArchitectureReport.cTextLimit);
end;

/// <summary>Text der Architekturübersicht für get_architecture über AArchitecture; in eigener Routine, damit die
/// anonyme Methode nicht den Rahmen von Run einfängt.</summary>
function ArchitectureOf(AWorkspace: TShellWorkspace; AArchitecture: TArchitectureService;
  const AAllFiles: TFunc<TArray<string>>; const ARoot: string): TMcpArchitectureFunc;
var
  mRoot: string;
  mAllFiles: TFunc<TArray<string>>;
begin
  mRoot := ARoot;
  mAllFiles := AAllFiles;
  Result :=
    function(ASection: TArchitectureSection; const AUnit, ACompareWith: string; AResolution: Double): string
    var
      mOverview: TArchitectureOverview;
    begin
      mOverview := AArchitecture.Overview(ArchitectureRequestOf(AWorkspace, mAllFiles, mRoot, AResolution));
      if ACompareWith <> '' then
      begin
        Result := ComparisonText(mOverview, ACompareWith, AWorkspace.Configuration.Settings.ArchitectureFailOn);
      end
      else if AUnit <> '' then
      begin
        Result := TArchitectureReport.UnitText(mOverview, AUnit);
      end
      else
      begin
        Result := TArchitectureReport.Text(mOverview, ASection, TArchitectureReport.cTextLimit);
      end;
    end;
end;

/// <summary>Quellen für find_path ohne Namensräume; Dateien über ReadSourceText, Units über AEnsure.</summary>
function SymbolPathSourcesOf(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService; ALocator: TUsesLocator;
  const AEnsure: TFunc<string, Boolean>): TSymbolPathSources;
begin
  Result := Default(TSymbolPathSources);
  Result.Index := AIndex;
  Result.Graphs := AGraphs;
  Result.Locator := ALocator;
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end;
  Result.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := Assigned(AEnsure) and AEnsure(AUnitName);
    end;
end;

/// <summary>find_path über einen eigenen Uses-Graphen samt Bibliotheks-Units. In eigener Routine, damit die
/// anonyme Methode nicht den Rahmen von Run einfängt (Leck unter Delphi).</summary>
function FindPathOf(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService; ALocator: TUsesLocator;
  AWorkspace: TShellWorkspace; const AEnsure: TFunc<string, Boolean>; const ARoot: string): TMcpFindPathFunc;
begin
  Result :=
    function(const ARequest: TSymbolPathRequest): string
    var
      Request: TSymbolPathRequest;
      Options: TUsesGraphOptions;
      Namespaces: TArray<string>;
      Token: IJsonRpcCancellationToken;
      Sources: TSymbolPathSources;
    begin
      Request := ARequest;
      // Grenze requestTimeoutMs; Abbruch über notifications/cancelled des MCP-Clients.
      Request.TimeoutMs := AWorkspace.Configuration.Settings.RequestTimeoutMs;
      Namespaces := AWorkspace.State.Namespaces;
      if string.Join(',', AGraphs.Options.Namespaces) <> string.Join(',', Namespaces) then
      begin
        Options := AGraphs.Options;
        Options.Namespaces := Namespaces;
        AGraphs.SetOptions(Options);
      end;
      Token := TJsonRpcCurrentRequest.Token;
      Sources := SymbolPathSourcesOf(AIndex, AGraphs, ALocator, AEnsure);
      Sources.Namespaces := Namespaces;
      Result := TSymbolPathSearch.Text(TSymbolPathSearch.Run(Sources, Request,
        function: Boolean
        begin
          Result := (Token <> nil) and Token.IsCancellationRequested;
        end), ARoot);
    end;
end;

function ToolGetArchitecture(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  Section: TArchitectureSection;
  CompareWith: string;
  mValue: TJSONValue;
  mResolution: Double;
begin
  if not TArchitectureReport.ParseSection(TMcpServer.OptionalString(AArguments, 'section'), Section) then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('section',
      ['overview', 'central', 'subsystems', 'cycles', 'crossLinks']));
  end;
  mResolution := 0;
  mValue := nil;
  if AArguments <> nil then
  begin
    mValue := AArguments.GetValue('resolution');
  end;
  if mValue <> nil then
  begin
    if not (mValue is TJSONNumber) or not TArchitectureGrouping.ValidResolution(TJSONNumber(mValue).AsDouble) then
    begin
      raise EMcpToolError.Create(cTexts[TMcpArchitectureText.ResolutionRange].Text);
    end;
    mResolution := TJSONNumber(mValue).AsDouble;
  end;
  CompareWith := TMcpServer.OptionalString(AArguments, 'compareWith');
  if CompareWith <> '' then
  begin
    CompareWith := AContext.Guard.Resolve(CompareWith);
  end;
  Result := AContext.Architecture(Section, TMcpServer.OptionalString(AArguments, 'unit'), CompareWith, mResolution);
end;

procedure AddGetArchitecture(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_architecture', cTexts[TMcpArchitectureText.GetArchitectureTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"section":{"type":"string","enum":["overview","central","subsystems","cycles","crossLinks"],' +
      '"description":%s},' +
      '"unit":{"type":"string","description":%s},' +
      '"compareWith":{"type":"string","description":%s},' +
      '"resolution":{"type":"number","minimum":0.2,"maximum":5,"description":%s}}}',
      [cTexts[TMcpArchitectureText.GetArchitectureSection].Text,
      cTexts[TMcpArchitectureText.GetArchitectureUnit].Text,
      cTexts[TMcpArchitectureText.GetArchitectureCompareWith].Text,
      cTexts[TMcpArchitectureText.GetArchitectureResolution].Text]),
    ContextTool(AContext, ToolGetArchitecture));
end;

function ToolFindPath(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.FindPath(FindPathRequest(AArguments));
end;

procedure AddFindPath(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_path', cTexts[TMcpArchitectureText.FindPathTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"from":{"type":"string","description":%s},' +
      '"to":{"type":"string","description":%s},' +
      '"via":{"type":"array","items":{"type":"string","enum":["uses","inherits","implements","hasField",' +
      '"parameter","result","calls","contains","library"]},' +
      '"description":%s},' +
      '"maxSteps":{"type":"integer","minimum":1,"maximum":16,"description":%s},' +
      '"all":{"type":"boolean","description":%s}},' +
      '"required":["from","to"]}',
      [cTexts[TMcpArchitectureText.FindPathFrom].Text,
      cTexts[TMcpArchitectureText.FindPathTo].Text,
      cTexts[TMcpArchitectureText.FindPathVia].Text,
      cTexts[TMcpArchitectureText.FindPathMaxSteps].Text,
      cTexts[TMcpArchitectureText.FindPathAll].Text]),
    ContextTool(AContext, ToolFindPath));
end;

procedure RegisterArchitectureTools(const AContext: TMcpToolContext);
begin
  AddGetArchitecture(AContext);
  AddFindPath(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.ArchitectureTools', cTexts);

end.
