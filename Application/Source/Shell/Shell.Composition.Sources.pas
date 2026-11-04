unit Shell.Composition.Sources;

// Internals-Rolle Shell: Datenquellen der Übersichten und Analysen aus den Arbeitsbereichen. Metriken (#66),
// Architektur (#1118), Hotspots (#1354), Code-Abfragen (#1351), Unit-Beziehungen (#593), Weg zwischen Symbolen
// (#1117), Begründungen (#1123) und die Grenzwerte der Code Lens. Die Teile bekommen die Quellen als
// Funktionen; der Umfang Projekt oder Projektgruppe (#648) entscheidet sich hier.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Service,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Architecture,
  Atlas.Common.Lsp.Hotspots,
  Atlas.Common.Lsp.Query,
  Atlas.Common.Lsp.UnitRelations,
  Atlas.Common.Lsp.SymbolPath,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Lsp.References,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  TShellSourcesIndexFunc = reference to function: ISymbolIndex;
  TShellSourcesActiveProjectFunc = reference to function: string;

  /// <summary>Was die Datenquellen von der Komposition brauchen.</summary>
  TShellSourcesServices = record
    Workspaces: TShellWorkspaceRegistry;
    Settings: TShellSettings;
    /// <summary>Symbolindex; entsteht nach den Quellen.</summary>
    Index: TShellSourcesIndexFunc;
    EnsureUnit: TEnsureUnitFunc;
    ReadText: TReferenceReadText;
    /// <summary>In der IDE aktives Projekt ('' ohne).</summary>
    ActiveProject: TShellSourcesActiveProjectFunc;
  end;

  /// <summary>Datenquellen der Übersichten und Analysen je Datei bzw. Projekt.</summary>
  TShellSources = class
  private
    FServices: TShellSourcesServices;
    /// <summary>Einstellungen, Wurzel und Dateien für die Code-Metriken: Datei, Projekt (.dproj/.dpr/.dpk),
    /// Ordner oder '' (einziger Arbeitsbereich).</summary>
    function MetricsSourceFor(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean;
    /// <summary>Arbeitsbereich für Metriken: Projekt der Projektdatei, sonst der der Datei bzw. der einzige.
    /// Aufrufer hält die Sperre.</summary>
    function MetricsWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Arbeitsbereich, dessen Projekt AFileName ist (.dproj, .dpr, .dpk). Aufrufer hält die Sperre.
    /// </summary>
    function ProjectWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Arbeitsbereich zu AFileName bzw. der einzige. Aufrufer hält die Sperre.</summary>
    function WorkspaceNear(const AFileName: string): TShellWorkspace;
    /// <summary>Architekturübersicht: Einstellungen, Wurzel, Titel, Namensräume und Dateien des Projekts
    /// (AScope "project") bzw. aller Projekte (sonst; leer = architecture.scope).</summary>
    function ArchitectureSourceFor(const AFileName, AScope: string; out ARequest: TArchitectureRequest;
      out ASettings: TServerSettings): Boolean;
    /// <summary>Projektdateien aller Arbeitsbereiche. Aufrufer hält die Sperre.</summary>
    function AllProjectFiles: TArray<string>;
    /// <summary>Code-Abfragen: alle Projekte der Gruppe, Wurzel und Namensräume des gewählten Arbeitsbereichs.
    /// </summary>
    function QuerySourceOf(out ASource: TQuerySource): Boolean;
    /// <summary>Arbeitsbereich der Abfragen: aktiv in der IDE, sonst ausgewählt, sonst der erste. Aufrufer hält
    /// die Sperre.</summary>
    function QueryWorkspace: TShellWorkspace;
    function QuerySettingsFor(const AFileName: string; out ASettings: TServerSettings; out ARoot: string): Boolean;
    /// <summary>Hotspots: Umfang wie die Architekturübersicht mit architecture.scope.</summary>
    function HotspotSourceFor(const AFileName: string; out ARequest: THotspotRequest; out ASettings: TServerSettings;
      out AVcs: IHotspotVcs; out AError: string): Boolean;
    /// <summary>Wurzel und Namensräume des Projekts der Datei, ohne Ausschlüsse der Architektur, damit „Wird
    /// verwendet von“ vollständig bleibt.</summary>
    function UnitRelationsOptionsFor(const AFileName: string): TUsesGraphOptions;
    function SymbolPathSourceFor(const AFileName: string; out ASettings: TServerSettings;
      out ANamespaces: TArray<string>): Boolean;
    /// <summary>hints.rationale, Marken, TODO-Marken und ADR-Ordner des Arbeitsbereichs.</summary>
    function RationaleOptionsFor(const AUri: string): TRationaleOptions;
    /// <summary>Grenzwerte der Metriken und ob die Code Lens sie zeigt.</summary>
    function CodeLensMetricsFor(const AUri: string; out ALimits: TMetricLimits): Boolean;
  public
    constructor Create(const AServices: TShellSourcesServices);
    function MetricsSource: TLspMetricsSourceFunc;
    function ArchitectureSource: TLspArchitectureSourceFunc;
    function QuerySource: TQuerySourceFunc;
    function QuerySettings: TLspQuerySettingsFunc;
    function HotspotSource: TLspHotspotSourceFunc;
    function UnitRelationsOptions: TLspUnitRelationsOptionsFunc;
    function SymbolPathSource: TLspSymbolPathSourceFunc;
    function RationaleOptions: THoverRationaleProvider;
    function CodeLensMetrics: TCodeLensMetricsFunc;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Rules.Builtin.Metrics,
  Shell.Hotspots;

constructor TShellSources.Create(const AServices: TShellSourcesServices);
begin
  inherited Create;
  FServices := AServices;
end;

function TShellSources.MetricsSource: TLspMetricsSourceFunc;
begin
  Result := MetricsSourceFor;
end;

function TShellSources.ArchitectureSource: TLspArchitectureSourceFunc;
begin
  Result := ArchitectureSourceFor;
end;

function TShellSources.QuerySource: TQuerySourceFunc;
begin
  Result := QuerySourceOf;
end;

function TShellSources.QuerySettings: TLspQuerySettingsFunc;
begin
  Result := QuerySettingsFor;
end;

function TShellSources.HotspotSource: TLspHotspotSourceFunc;
begin
  Result := HotspotSourceFor;
end;

function TShellSources.UnitRelationsOptions: TLspUnitRelationsOptionsFunc;
begin
  Result := UnitRelationsOptionsFor;
end;

function TShellSources.SymbolPathSource: TLspSymbolPathSourceFunc;
begin
  Result := SymbolPathSourceFor;
end;

function TShellSources.RationaleOptions: THoverRationaleProvider;
begin
  Result := RationaleOptionsFor;
end;

function TShellSources.CodeLensMetrics: TCodeLensMetricsFunc;
begin
  Result := CodeLensMetricsFor;
end;

function TShellSources.MetricsSourceFor(const AFileName: string; AProject: Boolean;
  out ASource: TLspMetricsSource): Boolean;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
begin
  ASource := Default(TLspMetricsSource);
  ASource.Settings := TServerSettings.Default;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := MetricsWorkspaceOf(AFileName);
    if mWorkspace = nil then
    begin
      Exit(False);
    end;
    ASource.Settings := mWorkspace.Configuration.Settings;
    ASource.Root := mWorkspace.Root;
    if mWorkspace.State.Project(mProject) then
    begin
      ASource.Title := ChangeFileExt(ExtractFileName(mProject.FileName), '');
    end
    else
    begin
      ASource.Title := mWorkspace.Name;
    end;
    if AProject then
    begin
      ASource.Files := mWorkspace.State.ProjectFiles;
    end;
    Result := True;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

function TShellSources.MetricsWorkspaceOf(const AFileName: string): TShellWorkspace;
begin
  Result := nil;
  // Projektdatei: der Arbeitsbereich dieses Projekts (Projektgruppe, #648).
  if MatchText(ExtractFileExt(AFileName), ['.dproj', '.dpr', '.dpk']) then
  begin
    Result := ProjectWorkspaceOf(AFileName);
  end;
  if (Result = nil) and (AFileName <> '') then
  begin
    Result := FServices.Workspaces.WorkspaceOf(AFileName);
  end;
  Result := TShellWorkspaces.Choose(Result, FServices.Workspaces.Items);
end;

function TShellSources.ProjectWorkspaceOf(const AFileName: string): TShellWorkspace;
var
  mCandidate: TShellWorkspace;
  mProject: TProjectInfo;
begin
  for mCandidate in FServices.Workspaces.Items do
  begin
    if (mCandidate.State.Project(mProject) and (SameText(mProject.FileName, AFileName) or
      SameText(mProject.MainSource, AFileName) or SameText(ChangeFileExt(mProject.FileName, '.dproj'),
      ChangeFileExt(AFileName, '.dproj')))) or SameText(mCandidate.Setup.ProjectFile, AFileName) then
    begin
      Exit(mCandidate);
    end;
  end;
  Result := nil;
end;

function TShellSources.WorkspaceNear(const AFileName: string): TShellWorkspace;
begin
  Result := nil;
  if AFileName <> '' then
  begin
    Result := FServices.Workspaces.WorkspaceOf(AFileName);
  end;
  Result := TShellWorkspaces.Choose(Result, FServices.Workspaces.Items);
end;

function TShellSources.SymbolPathSourceFor(const AFileName: string; out ASettings: TServerSettings;
  out ANamespaces: TArray<string>): Boolean;
var
  mSource: TLspMetricsSource;
  mWorkspace: TShellWorkspace;
begin
  ASettings := TServerSettings.Default;
  ANamespaces := nil;
  Result := MetricsSourceFor(AFileName, True, mSource);
  if not Result then
  begin
    Exit;
  end;
  ASettings := mSource.Settings;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := WorkspaceNear(AFileName);
    if mWorkspace <> nil then
    begin
      ANamespaces := mWorkspace.State.Namespaces;
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

function TShellSources.ArchitectureSourceFor(const AFileName, AScope: string;
  out ARequest: TArchitectureRequest; out ASettings: TServerSettings): Boolean;
var
  mSource: TLspMetricsSource;
  mWorkspace: TShellWorkspace;
begin
  ARequest := Default(TArchitectureRequest);
  ASettings := TServerSettings.Default;
  Result := MetricsSourceFor(AFileName, True, mSource);
  if not Result then
  begin
    Exit;
  end;
  ASettings := mSource.Settings;
  ARequest := TArchitectureRequest.FromSettings(ASettings);
  ARequest.Scope := AScope;
  if ARequest.Scope = '' then
  begin
    ARequest.Scope := ASettings.ArchitectureScope;
  end;
  ARequest.Root := mSource.Root;
  ARequest.Title := mSource.Title;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    if ARequest.Scope = 'project' then
    begin
      ARequest.Files := mSource.Files;
    end
    else
    begin
      // Projektgruppe (#648): die Dateien aller geladenen Projekte.
      ARequest.Files := AllProjectFiles;
    end;
    ARequest.Namespaces := nil;
    mWorkspace := WorkspaceNear(AFileName);
    if mWorkspace <> nil then
    begin
      ARequest.Namespaces := mWorkspace.State.Namespaces;
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  // Zuletzt berechneter Stand je Projekt bzw. Projektgruppe für die Angleichung (#1367).
  ARequest.PreviousFile := TIndexCacheDirectory.ArchitectureFileFor(TIndexCacheDirectory.DefaultRoot,
    ARequest.ScopeKey);
end;

function TShellSources.AllProjectFiles: TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  for mWorkspace in FServices.Workspaces.Items do
  begin
    Result := Result + mWorkspace.State.ProjectFiles;
  end;
end;

function TShellSources.HotspotSourceFor(const AFileName: string; out ARequest: THotspotRequest;
  out ASettings: TServerSettings; out AVcs: IHotspotVcs; out AError: string): Boolean;
var
  mArchitecture: TArchitectureRequest;
begin
  ARequest := Default(THotspotRequest);
  AVcs := nil;
  AError := '';
  Result := ArchitectureSourceFor(AFileName, '', mArchitecture, ASettings);
  if not Result then
  begin
    Exit;
  end;
  ARequest := THotspotRequest.FromSettings(ASettings);
  ARequest.Title := mArchitecture.Title;
  ARequest.Root := mArchitecture.Root;
  ARequest.Namespaces := mArchitecture.Namespaces;
  ARequest.Files := mArchitecture.Files;
  // Ohne Hotspots kein Prozess; ohne Arbeitskopie meldet die Antwort den Grund statt einer leeren Liste.
  if ASettings.HotspotsEnabled then
  begin
    TShellHotspotVcs.Detect(mArchitecture.Root, ASettings, AVcs, AError);
  end;
end;

/// <summary>Eingaben der Abfrage-Datenquelle aus den einzelnen Teilen.</summary>
function QueryInput(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ARoot: string;
  const AFiles, ANamespaces: TArray<string>; const AReadText: TReferenceReadText): TLspQueryInput;
begin
  Result.Index := AIndex;
  Result.EnsureUnit := AEnsureUnit;
  Result.Root := ARoot;
  Result.Files := AFiles;
  Result.Namespaces := ANamespaces;
  Result.ReadText := AReadText;
end;

function TShellSources.QuerySourceOf(out ASource: TQuerySource): Boolean;
var
  mWorkspace, mCandidate: TShellWorkspace;
  mFiles, mNamespaces: TArray<string>;
  mRoot: string;
  mReferences: TReferenceSettings;
begin
  ASource := Default(TQuerySource);
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := QueryWorkspace;
    if mWorkspace = nil then
    begin
      Exit(False);
    end;
    mNamespaces := mWorkspace.State.Namespaces;
    // Wurzel für die Spalte "Datei": gemeinsamer Ordner aller Projekte der Gruppe (bei Atlas der Stamm des
    // Repositorys). Mit der Wurzel des aktiven Projekts stand für jede Unit der anderen Projekte der volle Pfad da.
    mRoot := mWorkspace.Root;
    for mCandidate in FServices.Workspaces.Items do
    begin
      mRoot := TProjectPaths.CommonFolder(mRoot, mCandidate.Root);
    end;
    mReferences := mWorkspace.Configuration.Settings.References;
    // Projektgruppe (#648): die Dateien aller geladenen Projekte.
    mFiles := AllProjectFiles;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  ASource := TLspQuery.Source(QueryInput(FServices.Index(), FServices.EnsureUnit, mRoot, mFiles, mNamespaces,
    FServices.ReadText), mReferences);
  Result := True;
end;

function TShellSources.QueryWorkspace: TShellWorkspace;
var
  mCandidate: TShellWorkspace;
  mActive: string;
begin
  // Projektgruppe: Choose liefert nur bei genau einem Arbeitsbereich etwas; sonst hieß es "Kein Projekt
  // geladen". Wurzel, Namensräume und Einstellungen vom in der IDE aktiven Projekt, sonst vom ausgewählten,
  // sonst vom ersten.
  Result := nil;
  mActive := FServices.ActiveProject();
  for mCandidate in FServices.Workspaces.Items do
  begin
    if (mCandidate.State.ProjectFileName <> '') and SameText(mCandidate.State.ProjectFileName, mActive) then
    begin
      Result := mCandidate;
    end;
  end;
  if Result <> nil then
  begin
    Exit;
  end;
  for mCandidate in FServices.Workspaces.Items do
  begin
    if FServices.Workspaces.IsSelected(mCandidate) then
    begin
      Exit(mCandidate);
    end;
  end;
  if FServices.Workspaces.Items.Count > 0 then
  begin
    Result := FServices.Workspaces.Items[0];
  end;
end;

function TShellSources.QuerySettingsFor(const AFileName: string; out ASettings: TServerSettings;
  out ARoot: string): Boolean;
var
  mSource: TLspMetricsSource;
begin
  Result := MetricsSourceFor(AFileName, False, mSource);
  ASettings := mSource.Settings;
  ARoot := mSource.Root;
end;

function TShellSources.UnitRelationsOptionsFor(const AFileName: string): TUsesGraphOptions;
var
  mWorkspace: TShellWorkspace;
begin
  Result := TUsesGraphOptions.Default;
  Result.IncludeLibrary := True;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := WorkspaceNear(AFileName);
    if mWorkspace <> nil then
    begin
      Result.Root := mWorkspace.Root;
      Result.Namespaces := mWorkspace.State.Namespaces;
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

function TShellSources.RationaleOptionsFor(const AUri: string): TRationaleOptions;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := FServices.Workspaces.Pick(TDocumentUris.ToPath(AUri));
    // ADR-Ordner relativ zum Arbeitsbereich; ohne Arbeitsbereich nur ein absoluter.
    if mWorkspace = nil then
    begin
      Result := TRationaleOptions.FromSettings(FServices.Settings.Loose, '');
    end
    else
    begin
      Result := TRationaleOptions.FromSettings(mWorkspace.Configuration.Settings, mWorkspace.Root);
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

function TShellSources.CodeLensMetricsFor(const AUri: string; out ALimits: TMetricLimits): Boolean;
var
  mSource: TLspMetricsSource;
begin
  if not MetricsSourceFor(TDocumentUris.ToPath(AUri), False, mSource) then
  begin
    mSource.Settings := TServerSettings.Default;
  end;
  ALimits := TMetricRules.Limits(mSource.Settings);
  Result := mSource.Settings.Metrics and mSource.Settings.CodeLens.Metrics;
end;

end.
