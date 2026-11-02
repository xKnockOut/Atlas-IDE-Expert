unit Shell.Composition.Analysis;

// Internals-Rolle Shell: Analysen am Quelltext. Signaturhilfe, Hierarchien, Auswirkungen, Datenfluss (#690),
// Zugriffsketten (#865), Implementierungen, Inlay-Hinweise, Code-Linsen, Code-Metriken (#66), TODO-Übersicht
// (#68) und semantische Hervorhebung. Die Komposition reicht Dokumente, Index, Quelltext, Projektdateien und
// die Einstellungen der Arbeitsbereiche als Dienste herein.

interface

uses
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.DataFlow,
  Atlas.Common.Lsp.AccessChains,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Todos,
  Atlas.Common.Lsp.SemanticTokens;

type
  TShellAnalysisReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Was die Analysen von der Komposition brauchen.</summary>
  TShellAnalysisServices = record
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    ReadText: TShellAnalysisReadText;
    ProjectFiles: TReferenceFilesProvider;
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Platzhalter von Format und eigenen Formatroutinen (#451).</summary>
    FormatRoutinesFor: TFormatRoutinesFunc;
    ReferenceSettingsFor: TReferenceSettingsProvider;
    ImpactOptionsFor: TImpactOptionsProvider;
    InlayHintSettingsFor: TInlayHintSettingsProvider;
    CodeLensMetricsFor: TCodeLensMetricsFunc;
    /// <summary>Einstellungen, Wurzel und Dateien des Projektmodells für Metriken und TODOs (#14).</summary>
    MetricsSourceFor: TLspMetricsSourceFunc;
  end;

  /// <summary>Analysen mit ihren Anfragen und den Befehlen der Metriken und TODOs.</summary>
  TShellAnalysis = class
  private
    FServices: TShellAnalysisServices;
    FSignatureHelp: TLspSignatureHelp;
    FHierarchies: TLspHierarchies;
    FImpact: TImpactAnalysis;
    // Datenfluss „Woher/Wohin geht der Wert?“ (#690).
    FDataFlow: TLspDataFlow;
    // Zugriffsketten am Ausführungspunkt (#865).
    FAccessChains: TLspAccessChains;
    FImplementations: TLspImplementations;
    FInlayHints: TLspInlayHints;
    FCodeLens: TLspCodeLens;
    /// <summary>Code-Metriken (#66): Befehl atlas.server.metrics mit Zwischenspeicher je Datei.</summary>
    FMetrics: TLspMetrics;
    /// <summary>TODO-Übersicht (#68): Befehl atlas.server.todos.</summary>
    FTodos: TLspTodos;
    FSemanticTokens: TLspSemanticTokens;
    /// <summary>Quelltext über den Dienst; als eigene Methode an alle Leser mit ihren eigenen Typen.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function GetNamespaces: TArray<string>;
    procedure CreateReferenceViews;
    procedure CreateEditorViews;
  public
    constructor Create(const AServices: TShellAnalysisServices);
    destructor Destroy; override;
    /// <summary>Anfragen der Analysen am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Befehle atlas.server.metrics und atlas.server.todos.</summary>
    procedure RegisterReportCommands(ACommands: TLspCommands);
    /// <summary>Namensräume des Projekts an alle Analysen, die Namen auflösen.</summary>
    procedure SetNamespaces(const ANamespaces: TArray<string>);
    /// <summary>Zuletzt gesetzte Namensräume.</summary>
    property Namespaces: TArray<string> read GetNamespaces;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

constructor TShellAnalysis.Create(const AServices: TShellAnalysisServices);
begin
  inherited Create;
  FServices := AServices;
  CreateReferenceViews;
  CreateEditorViews;
end;

procedure TShellAnalysis.CreateReferenceViews;
begin
  FSignatureHelp := TLspSignatureHelp.Create(FServices.Documents, FServices.Index, ReadText, FServices.EnsureUnit);
  FSignatureHelp.FormatRoutinesFor := FServices.FormatRoutinesFor;
  FHierarchies := TLspHierarchies.Create(FServices.Documents, FServices.Index, ReadText, FServices.ProjectFiles,
    FServices.EnsureUnit);
  FHierarchies.SettingsFor := FServices.ReferenceSettingsFor;
  FImpact := TImpactAnalysis.Create(FServices.Documents, FServices.Index, ReadText, FServices.ProjectFiles,
    FServices.EnsureUnit);
  FImpact.OptionsFor := FServices.ImpactOptionsFor;
  FDataFlow := TLspDataFlow.Create(FServices.Documents, FServices.Index, ReadText, FServices.ProjectFiles,
    FServices.EnsureUnit);
  FAccessChains := TLspAccessChains.Create(FServices.Documents, FServices.Index, ReadText, FServices.EnsureUnit);
  FImplementations := TLspImplementations.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit);
end;

procedure TShellAnalysis.CreateEditorViews;
begin
  FInlayHints := TLspInlayHints.Create(FServices.Documents, FServices.Index, ReadText,
    FServices.InlayHintSettingsFor, FServices.EnsureUnit);
  FCodeLens := TLspCodeLens.Create(FServices.Documents, FServices.Index, ReadText, FServices.ProjectFiles,
    FServices.EnsureUnit);
  FCodeLens.MetricsFor := FServices.CodeLensMetricsFor;
  FMetrics := TLspMetrics.Create(FServices.MetricsSourceFor, ReadText);
  // Vererbungstiefe in der Metrik-Linse des Plugins (#980).
  FMetrics.Index := FServices.Index;
  FTodos := TLspTodos.Create(FServices.MetricsSourceFor, ReadText);
  FSemanticTokens := TLspSemanticTokens.Create(FServices.Documents, FServices.Index, FServices.EnsureUnit);
end;

destructor TShellAnalysis.Destroy;
begin
  FreeAndNil(FSemanticTokens);
  FreeAndNil(FCodeLens);
  FreeAndNil(FMetrics);
  FreeAndNil(FTodos);
  FreeAndNil(FInlayHints);
  FreeAndNil(FImplementations);
  FreeAndNil(FImpact);
  FreeAndNil(FAccessChains);
  FreeAndNil(FDataFlow);
  FreeAndNil(FHierarchies);
  FreeAndNil(FSignatureHelp);
  inherited Destroy;
end;

function TShellAnalysis.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FServices.ReadText(AFileName, AText);
end;

function TShellAnalysis.GetNamespaces: TArray<string>;
begin
  Result := FImpact.Namespaces;
end;

procedure TShellAnalysis.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FSignatureHelp.Attach(ADispatcher);
  FHierarchies.Attach(ADispatcher);
  FImpact.Attach(ADispatcher);
  FDataFlow.Attach(ADispatcher);
  FAccessChains.Attach(ADispatcher);
  FImplementations.Attach(ADispatcher);
  FInlayHints.Attach(ADispatcher);
  FCodeLens.Attach(ADispatcher);
  FSemanticTokens.Attach(ADispatcher);
end;

procedure TShellAnalysis.RegisterReportCommands(ACommands: TLspCommands);
begin
  ACommands.Register(TLspMetrics.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FMetrics.Execute(AArguments);
    end);
  ACommands.Register(TLspTodos.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FTodos.Execute(AArguments);
    end);
end;

procedure TShellAnalysis.SetNamespaces(const ANamespaces: TArray<string>);
begin
  FSignatureHelp.Namespaces := ANamespaces;
  FHierarchies.Namespaces := ANamespaces;
  FImpact.Namespaces := ANamespaces;
  FDataFlow.Namespaces := ANamespaces;
  FAccessChains.Namespaces := ANamespaces;
  FImplementations.Namespaces := ANamespaces;
  FInlayHints.Namespaces := ANamespaces;
  FCodeLens.Namespaces := ANamespaces;
  FSemanticTokens.Namespaces := ANamespaces;
end;

end.
