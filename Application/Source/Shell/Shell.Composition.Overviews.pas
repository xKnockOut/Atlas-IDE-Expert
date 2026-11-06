unit Shell.Composition.Overviews;

// Internals-Rolle Shell: Übersichten des Servers. Architektur (#1118), Code-Abfragen (#1351), Hotspots (#1354),
// Unit-Beziehungen (#593), Weg zwischen Symbolen (#1117), Wertdarstellungen (#854), Ereignisbehandlungen und
// Rekursionssymbole (#623). Die Komposition reicht Index, Quelltext, Defines und die Datenquellen der
// Arbeitsbereiche als Dienste herein.

interface

uses
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Service,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.Architecture,
  Atlas.Common.Lsp.Query,
  Atlas.Common.Lsp.Hotspots,
  Atlas.Common.Lsp.UnitRelations,
  Atlas.Common.Lsp.SymbolPath,
  Atlas.Common.Lsp.DebugDisplay,
  Atlas.Common.Lsp.EventHandlers,
  Atlas.Common.Lsp.Recursion;

type
  /// <summary>Was die Übersichten von der Komposition brauchen.</summary>
  TShellOverviewServices = record
    Index: ISymbolIndex;
    ReadText: TMetricsReadText;
    DefinesOf: TUsesDefinesFunc;
    EnsureUnit: TEnsureUnitFunc;
    MetricsSourceFor: TLspMetricsSourceFunc;
    UsesContextFor: TUsesContextProvider;
    ArchitectureSourceFor: TLspArchitectureSourceFunc;
    QuerySource: TQuerySourceFunc;
    QuerySettingsFor: TLspQuerySettingsFunc;
    HotspotSourceFor: TLspHotspotSourceFunc;
    UnitRelationsOptionsFor: TLspUnitRelationsOptionsFunc;
    SymbolPathSourceFor: TLspSymbolPathSourceFunc;
  end;

  /// <summary>Dienste, Anfragen und Befehle der Übersichten.</summary>
  TShellOverviews = class
  private
    FServices: TShellOverviewServices;
    /// <summary>Architekturübersicht (#1118): Dienst mit Zwischenspeicher je Index-Generation, Anfrage
    /// atlas/architecture und Befehl atlas.architecture.saveReport.</summary>
    FArchitectureService: TArchitectureService;
    FArchitecture: TLspArchitecture;
    /// <summary>Code-Abfragen (#1351): Dienst mit Zwischenspeicher je Index-Stand für atlas/query, das Fenster
    /// „Atlas-Abfrage“ und die Regeln query:&lt;name&gt;.</summary>
    FQueries: ICodeQueries;
    FQuery: TLspQuery;
    /// <summary>Hotspots (#1354): Dienst mit Zwischenspeicher je Stand der Versionsverwaltung und Index-Generation,
    /// Anfrage atlas/hotspots und Befehle atlas.hotspots und atlas.hotspots.saveReport.</summary>
    FHotspotService: THotspotService;
    FHotspots: TLspHotspots;
    /// <summary>Unit-Beziehungen (#593): eigener Uses-Graph mit Bibliotheks-Units, Anfrage atlas/unitRelations
    /// und Befehle zum Verschieben und Entfernen von uses-Einträgen.</summary>
    FUnitRelationsGraph: TUsesGraphService;
    FUnitRelations: TLspUnitRelations;
    FSymbolPath: TLspSymbolPath;
    /// <summary>Eigene Wertdarstellungen beim Debuggen (#854): Befehl atlas.server.debugDisplayRules.</summary>
    FDebugDisplay: TLspDebugDisplay;
    FEventHandlers: TLspEventHandlers;
    FRecursion: TLspRecursion;
    /// <summary>Quelltext über den Dienst; als eigene Methode an alle Leser mit ihren eigenen Typen.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    procedure CreateArchitecture;
    procedure CreateUnitViews;
  public
    constructor Create(const AServices: TShellOverviewServices);
    destructor Destroy; override;
    /// <summary>Anfragen atlas/architecture, atlas/query, atlas/hotspots, atlas/unitRelations und
    /// atlas/symbolPath.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Befehle der Architektur, der Abfragen und der Hotspots.</summary>
    procedure RegisterReportCommands(ACommands: TLspCommands);
    /// <summary>Befehle der Unit-Beziehungen, des Wegs zwischen Symbolen, der Wertdarstellungen, der
    /// Ereignisbehandlungen und der Rekursion.</summary>
    procedure RegisterUnitCommands(ACommands: TLspCommands);
    /// <summary>Gespeicherte Abfragen für die Regeln query:&lt;name&gt; (#1351).</summary>
    property Queries: ICodeQueries read FQueries;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Architecture.UsesGraph;

constructor TShellOverviews.Create(const AServices: TShellOverviewServices);
begin
  inherited Create;
  FServices := AServices;
  CreateArchitecture;
  CreateUnitViews;
end;

procedure TShellOverviews.CreateArchitecture;
begin
  // Architekturübersicht (#1118): Fundstellen der uses-Einträge mit den Defines des Projekts der Datei.
  FArchitectureService := TArchitectureService.Create(FServices.Index, ReadText, FServices.DefinesOf);
  FArchitecture := TLspArchitecture.Create(FArchitectureService, FServices.ArchitectureSourceFor);
  // Code-Abfragen (#1351): ein Dienst für Fenster, Befehl und die Regeln query:<name>.
  FQueries := TCodeQueryService.Create(FServices.QuerySource);
  FQuery := TLspQuery.Create(FQueries, FServices.QuerySettingsFor);
  // Hotspots (#1354): Komplexität aus geöffneten Dokumenten bzw. der Platte.
  FHotspotService := THotspotService.Create(FServices.Index, ReadText);
  FHotspots := TLspHotspots.Create(FHotspotService, FServices.HotspotSourceFor);
end;

procedure TShellOverviews.CreateUnitViews;
begin
  // Unit-Beziehungen (#593): Wurzel und Namensräume wie die Architektur; die uses-Analyse der Code-Aktionen
  // entsteht in der Komposition erst später, daher über UsesContextFor.
  FUnitRelationsGraph := TUsesGraphService.Create(FServices.Index, TUsesGraphOptions.Default);
  FUnitRelations := TLspUnitRelations.Create(FUnitRelationsGraph, ReadText, FServices.DefinesOf,
    FServices.UsesContextFor, FServices.UnitRelationsOptionsFor);
  // Weg zwischen Symbolen (#1117): eigener Uses-Graph samt Bibliotheks-Units, Fundstellen wie oben.
  FSymbolPath := TLspSymbolPath.Create(FServices.Index, ReadText, FServices.DefinesOf, FServices.EnsureUnit,
    FServices.SymbolPathSourceFor);
  // Wertdarstellungen (#854): Dateien wie die TODO-Übersicht, Typen und Vorfahren aus dem Index.
  FDebugDisplay := TLspDebugDisplay.Create(FServices.MetricsSourceFor, ReadText);
  FDebugDisplay.Index := FServices.Index;
  FEventHandlers := TLspEventHandlers.Create(FServices.MetricsSourceFor, ReadText);
  FEventHandlers.Index := FServices.Index;
  // Rekursionssymbole im Editorrand (#623).
  FRecursion := TLspRecursion.Create(ReadText);
end;

destructor TShellOverviews.Destroy;
begin
  FreeAndNil(FSymbolPath);
  FreeAndNil(FArchitecture);
  FreeAndNil(FArchitectureService);
  FreeAndNil(FQuery);
  FQueries := nil;
  FreeAndNil(FHotspots);
  FreeAndNil(FHotspotService);
  FreeAndNil(FUnitRelations);
  FreeAndNil(FUnitRelationsGraph);
  FreeAndNil(FDebugDisplay);
  FreeAndNil(FEventHandlers);
  FreeAndNil(FRecursion);
  inherited Destroy;
end;

function TShellOverviews.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FServices.ReadText(AFileName, AText);
end;

procedure TShellOverviews.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FArchitecture.Attach(ADispatcher);
  FQuery.Attach(ADispatcher);
  FHotspots.Attach(ADispatcher);
  FUnitRelations.Attach(ADispatcher);
  FSymbolPath.Attach(ADispatcher);
end;

procedure TShellOverviews.RegisterReportCommands(ACommands: TLspCommands);
begin
  ACommands.Register(TLspArchitecture.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FArchitecture.Execute(AArguments);
    end);
  ACommands.Register(TLspArchitecture.cSaveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FArchitecture.SaveReport(AArguments);
    end);
  ACommands.Register(TLspQuery.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FQuery.Execute(AArguments);
    end);
  // Hotspots (#1354): nebenläufig; gerechnet wird im Hintergrund, die Antwort kommt sofort (sonst "pending").
  ACommands.RegisterConcurrent(TLspHotspots.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FHotspots.Execute(AArguments);
    end);
  ACommands.RegisterConcurrent(TLspHotspots.cSaveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FHotspots.SaveReport(AArguments);
    end);
end;

procedure TShellOverviews.RegisterUnitCommands(ACommands: TLspCommands);
begin
  ACommands.Register(TLspUnitRelations.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Execute(AArguments);
    end);
  ACommands.Register(TLspUnitRelations.cMoveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Move(AArguments);
    end);
  ACommands.Register(TLspUnitRelations.cRemoveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Remove(AArguments);
    end);
  ACommands.Register(TLspUnitRelations.cCostCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Cost(AArguments);
    end);
  ACommands.Register(TLspUnitRelations.cUseUnitCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.UseUnitInfo(AArguments);
    end);
  ACommands.Register(TLspSymbolPath.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSymbolPath.Execute(AArguments);
    end);
  ACommands.Register(TLspDebugDisplay.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FDebugDisplay.Execute(AArguments);
    end);
  ACommands.Register(TLspEventHandlers.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FEventHandlers.Execute(AArguments);
    end);
  ACommands.Register(TLspRecursion.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FRecursion.Execute(AArguments);
    end);
end;

end.
