unit Shell.Composition.AnalysisArea;

// Teilwurzel Analyse der Komposition: Analysen (Signaturhilfe, Hierarchien, Auswirkungen, Metriken …), Übersichten
// (Architektur, Code-Abfragen, Hotspots …), Baselines und betroffene Tests. Sie bekommt den Kern und die wenigen
// Dienste, die nur die Komposition kennt.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.Impact,
  Shell.Composition.Core,
  Shell.Composition.Analysis,
  Shell.Composition.Overviews,
  Shell.Composition.Baselines,
  Shell.Composition.AffectedTests;

type
  /// <summary>Zeitlimit einer Anfrage in Millisekunden; kann sich mit den Einstellungen ändern.</summary>
  TShellAnalysisTimeoutFunc = reference to function: Cardinal;

  /// <summary>Was die Analyse außer dem Kern von der Komposition braucht.</summary>
  TShellAnalysisAreaServices = record
    Logger: ILogger;
    Dispatcher: TJsonRpcDispatcher;
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    FormatRoutinesFor: TFormatRoutinesFunc;
    UsesContextFor: TUsesContextProvider;
    RefreshLater: TShellRefreshProc;
    TestUnitContext: TShellAffectedTestUnitFunc;
    RequestTimeout: TShellAnalysisTimeoutFunc;
  end;

  /// <summary>Hält Analysen, Übersichten und Baselines; meldet sie und die betroffenen Tests am Verteiler an.</summary>
  TShellAnalysisArea = class
  private
    FCore: TShellCore;
    FServices: TShellAnalysisAreaServices;
    FAnalysis: TShellAnalysis;
    FOverviews: TShellOverviews;
    FBaselines: TShellBaselines;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ProjectFiles: TArray<string>;
    function Namespaces: TArray<string>;
    function AnalysisServices: TShellAnalysisServices;
    function OverviewServices: TShellOverviewServices;
    function BaselineServices: TShellBaselineServices;
    function AffectedTestsServices: TShellAffectedTestsServices;
  public
    /// <summary>Legt die drei Teile an und meldet sie an AServices.Dispatcher an; ACore muss bestehen.</summary>
    constructor Create(ACore: TShellCore; const AServices: TShellAnalysisAreaServices);
    /// <summary>Gibt Analysen, Übersichten und Baselines in dieser Reihenfolge frei.</summary>
    destructor Destroy; override;
    /// <summary>Optionen der Auswirkungsanalyse: Tiefe und Verweise aus den Einstellungen, vier Fünftel des
    /// Zeitlimits, Testunits aus dem Testprogramm.</summary>
    function ImpactOptionsFor(const AUri: string): TImpactOptions;
    property Analysis: TShellAnalysis read FAnalysis;
    property Overviews: TShellOverviews read FOverviews;
    property Baselines: TShellBaselines read FBaselines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.TestUnits;

constructor TShellAnalysisArea.Create(ACore: TShellCore; const AServices: TShellAnalysisAreaServices);
begin
  inherited Create;
  FCore := ACore;
  FServices := AServices;
  FAnalysis := TShellAnalysis.Create(AnalysisServices);
  FAnalysis.Attach(FServices.Dispatcher);
  TShellAffectedTestsRequest.Attach(FServices.Dispatcher, AffectedTestsServices);
  FOverviews := TShellOverviews.Create(OverviewServices);
  FOverviews.Attach(FServices.Dispatcher);
  FBaselines := TShellBaselines.Create(BaselineServices);
end;

destructor TShellAnalysisArea.Destroy;
begin
  FreeAndNil(FAnalysis);
  FreeAndNil(FOverviews);
  FreeAndNil(FBaselines);
  inherited;
end;

function TShellAnalysisArea.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FCore.ReadText(AFileName, AText);
end;

function TShellAnalysisArea.ProjectFiles: TArray<string>;
begin
  Result := FCore.ProjectFiles;
end;

function TShellAnalysisArea.Namespaces: TArray<string>;
begin
  Result := FAnalysis.Namespaces;
end;

function TShellAnalysisArea.AnalysisServices: TShellAnalysisServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := Default(TShellAnalysisServices);
  Result.Documents := FServices.Documents;
  Result.Index := FServices.Index;
  Result.ReadText := ReadText;
  Result.ProjectFiles := ProjectFiles;
  Result.EnsureUnit := mCore.Folders.EnsureUnitFunc();
  Result.FormatRoutinesFor := FServices.FormatRoutinesFor;
  Result.ReferenceSettingsFor :=
    function(const AUri: string): TReferenceSettings
    begin
      Result := mCore.Settings.References(AUri);
    end;
  Result.ImpactOptionsFor := ImpactOptionsFor;
  Result.InlayHintSettingsFor :=
    function(const AUri: string): TInlayHintSettings
    begin
      Result := mCore.Settings.InlayHints(AUri);
    end;
  Result.CodeLensMetricsFor := mCore.Sources.CodeLensMetrics();
  Result.MetricsSourceFor := mCore.Sources.MetricsSource();
end;

function TShellAnalysisArea.OverviewServices: TShellOverviewServices;
begin
  Result := Default(TShellOverviewServices);
  Result.Index := FServices.Index;
  Result.ReadText := ReadText;
  Result.DefinesOf := FCore.Directives.UsesDefines();
  Result.EnsureUnit := FCore.Folders.EnsureUnitFunc();
  Result.MetricsSourceFor := FCore.Sources.MetricsSource();
  Result.UsesContextFor := FServices.UsesContextFor;
  Result.ArchitectureSourceFor := FCore.Sources.ArchitectureSource();
  Result.QuerySource := FCore.Sources.QuerySource();
  Result.QuerySettingsFor := FCore.Sources.QuerySettings();
  Result.HotspotSourceFor := FCore.Sources.HotspotSource();
  Result.UnitRelationsOptionsFor := FCore.Sources.UnitRelationsOptions();
  Result.SymbolPathSourceFor := FCore.Sources.SymbolPathSource();
end;

function TShellAnalysisArea.BaselineServices: TShellBaselineServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := Default(TShellBaselineServices);
  Result.MetricsSourceFor := mCore.Sources.MetricsSource();
  Result.ReadText := ReadText;
  Result.RuleContextFor :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      Result := mCore.RuleContext.RuleContextFor(AUri, AContext);
    end;
  Result.DefinesFor := mCore.Directives.Defines();
  Result.IncludeResolverFor :=
    function(const AUri: string): TIncludeResolver
    begin
      Result := mCore.Directives.IncludeResolver(AUri);
    end;
  Result.RefreshLater := FServices.RefreshLater;
  Result.Logger := FServices.Logger;
end;

function TShellAnalysisArea.AffectedTestsServices: TShellAffectedTestsServices;
begin
  Result := Default(TShellAffectedTestsServices);
  Result.Workspaces := FCore.Workspaces;
  Result.Settings := FCore.Settings;
  Result.Index := FServices.Index;
  Result.EnsureUnit := FCore.Folders.EnsureUnitFunc();
  Result.Namespaces := Namespaces;
  Result.ReadText := ReadText;
  Result.ProjectFiles := ProjectFiles;
  Result.TestUnitContext := FServices.TestUnitContext;
  Result.ImpactOptions := ImpactOptionsFor;
end;

function TShellAnalysisArea.ImpactOptionsFor(const AUri: string): TImpactOptions;
var
  mContext: TTestUnitContext;
  mText: string;
begin
  Result := TImpactOptions.Default;
  Result.Depth := FCore.Settings.SettingsFor(AUri).Navigation.ImpactDepth;
  Result.References := FCore.Settings.References(AUri);
  // Vier Fünftel des Zeitlimits der Anfrage: Danach bräche der Watchdog sie ohne Ergebnis ab.
  Result.TimeoutMs := Integer(FServices.RequestTimeout() div 5 * 4);
  if FServices.TestUnitContext(AUri, mContext) then
  begin
    mText := '';
    if (mContext.TestProgram <> '') and not ReadText(mContext.TestProgram, mText) then
    begin
      mText := '';
    end;
    Result.Tests := TImpactTestScope.FromProgram(mContext.Settings.Pattern, mText);
  end;
end;

end.
