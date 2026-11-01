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
  Atlas.Common.JsonRpc.CurrentRequest;

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
    raise EMcpToolError.Create('Architekturübersicht ist ausgeschaltet (architecture.enabled)');
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
    raise EMcpToolError.Create('Kein Projekt geladen');
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
  Result := TArchitectureComparer.Text(mComparison, mFailOn, TArchitectureReport.TextLimit);
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
        Result := TArchitectureReport.Text(mOverview, ASection, TArchitectureReport.TextLimit);
      end;
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
      Result := TSymbolPathSearch.Text(TSymbolPathSearch.Run(AIndex, AGraphs, ALocator,
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := ReadSourceText(AFileName, AText);
        end,
        function(const AUnitName: string): Boolean
        begin
          Result := Assigned(AEnsure) and AEnsure(AUnitName);
        end, Namespaces, Request,
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
    raise EMcpToolError.Create('"section" ist overview, central, subsystems, cycles oder crossLinks');
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
      raise EMcpToolError.Create('"resolution" ist eine Zahl von 0,2 bis 5,0');
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
  AContext.Server.AddTool('get_architecture',
    'Architekturübersicht (#1118) aus dem uses-Graphen: Teilsysteme (Gruppen eng verbundener Units), zentrale ' +
    'Units, Zyklen und Querverbindungen zwischen Teilsystemen, je mit Datei:Zeile der uses-Einträge. Mit "unit" ' +
    'der Steckbrief einer Unit (Teilsystem, Abhängigkeiten, Zyklen, Ausreißer). Mit "compareWith" der Vergleich ' +
    'mit einem gespeicherten Stand (#1121): neue und entfernte Zyklen, Querverbindungen und uses-Kanten zwischen ' +
    'Teilsystemen, Teilsystemwechsel, gewachsene zentrale Units, neue und entfernte Units. Umfang und ' +
    'Bibliotheks-Units aus architecture.* in atlas.json. "resolution" (0,2–5,0) stellt die Feinheit der ' +
    'Teilsysteme für diesen Aufruf ein (#1366): größer = mehr und kleinere Teilsysteme.',
    '{"type":"object","properties":{' +
      '"section":{"type":"string","enum":["overview","central","subsystems","cycles","crossLinks"],' +
        '"description":"Abschnitt; Vorgabe overview"},' +
      '"unit":{"type":"string","description":"Steckbrief dieser Unit statt eines Abschnitts"},' +
      '"compareWith":{"type":"string","description":"Gespeicherter Stand (JSON aus AtlasServer --architecture ' +
        '<Datei.json>), Pfad relativ zum Projekt: liefert die Abschnitte des Vergleichs"},' +
      '"resolution":{"type":"number","minimum":0.2,"maximum":5,"description":"Feinheit der Teilsysteme ' +
        '(Louvain-Auflösung γ); Vorgabe architecture.grouping.resolution, 1 = klassisch"}}}',
    ContextTool(AContext, ToolGetArchitecture));
end;

function ToolFindPath(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AContext.FindPath(FindPathRequest(AArguments));
end;

procedure AddFindPath(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('find_path',
    'Kürzester Weg zwischen zwei Symbolen oder Units (#1117), z. B. „Wie hängt TKundenForm mit TDatenbank ' +
    'zusammen?“, in einem Aufruf statt vieler find_references/get_call_hierarchy. Kanten: uses, inherits, ' +
    'implements (auch Interface → Umsetzung), hasField, parameter, result, calls, contains. Liefert die Kette ' +
    'mit Kantenart und Datei:Zeile je Schritt; erschlossene Kanten (mehrere Umsetzungen) tragen [erschlossen]. ' +
    '„Kein Weg“ ist eine verlässliche Antwort; bei mehrdeutigem Namen kommt die Trefferliste.',
    '{"type":"object","properties":{' +
      '"from":{"type":"string","description":"Start: Typ, Methode (TFoo.Bar), Routine, Feld, Property oder Unit"},' +
      '"to":{"type":"string","description":"Ziel, Angabe wie bei from; ein Typ zählt samt seinen Mitgliedern"},' +
      '"via":{"type":"array","items":{"type":"string","enum":["uses","inherits","implements","hasField",' +
        '"parameter","result","calls","contains","library"]},' +
        '"description":"Erlaubte Kantenarten (Vorgabe alle); library erlaubt RTL/VCL als Durchgang"},' +
      '"maxSteps":{"type":"integer","minimum":1,"maximum":16,"description":"Höchstens so viele Schritte, ' +
        'Vorgabe 8"},' +
      '"all":{"type":"boolean","description":"Alle gleich kurzen Wege (höchstens 5) statt nur des ersten"}},' +
      '"required":["from","to"]}',
    ContextTool(AContext, ToolFindPath));
end;

procedure RegisterArchitectureTools(const AContext: TMcpToolContext);
begin
  AddGetArchitecture(AContext);
  AddFindPath(AContext);
end;

end.
