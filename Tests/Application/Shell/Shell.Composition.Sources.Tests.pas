unit Shell.Composition.Sources.Tests;

// Datenquellen der Übersichten: ohne Arbeitsbereich keine Quelle, mit einem Arbeitsbereich Wurzel und Titel des
// Ordners für Metriken, Architektur, Abfragen und Unit-Beziehungen.

interface

uses
  DUnitX.TestFramework,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Sources;

type
  [TestFixture]
  TShellSourcesTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FSources: TShellSources;
    FRoot: string;
    procedure AddWorkspace;
  public
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich liefert keine Quelle etwas; Unit-Beziehungen zeigen trotzdem die Bibliothek.
    /// </summary>
    [Test]
    procedure NoWorkspaceNoSource;
    /// <summary>Ein Arbeitsbereich ohne geladenes Projekt: Wurzel und Name des Ordners.</summary>
    [Test]
    procedure SingleWorkspaceMetrics;
    /// <summary>Architektur im Umfang „project“ übernimmt Wurzel, Titel und Umfang.</summary>
    [Test]
    procedure SingleWorkspaceArchitecture;
    /// <summary>Abfragen und Unit-Beziehungen nehmen den einzigen Arbeitsbereich.</summary>
    [Test]
    procedure SingleWorkspaceQueryAndRelations;
    /// <summary>Begründungen und Code Lens ohne Arbeitsbereich: Einstellungen ohne Ordner bzw. Vorgaben.</summary>
    [Test]
    procedure DefaultsWithoutWorkspace;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Query.Contract,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  Shell.Workspace.Setup;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

function NoLanguageLevel(const AUri: string): string;
begin
  Result := '';
end;

function NoUnit(const AUnitName: string): Boolean;
begin
  Result := False;
end;

procedure TShellSourcesTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
  mServices: TShellSourcesServices;
  mIndex: ISymbolIndex;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguageLevel);
  mIndex := TSymbolIndex.Create;
  mServices := Default(TShellSourcesServices);
  mServices.Workspaces := FRegistry;
  mServices.Settings := FSettings;
  mServices.Index :=
    function: ISymbolIndex
    begin
      Result := mIndex;
    end;
  mServices.EnsureUnit := NoUnit;
  mServices.ReadText := NoText;
  mServices.ActiveProject := NoActive;
  FSources := TShellSources.Create(mServices);
  FRoot := TPath.Combine(TPath.GetTempPath, 'AtlasSources');
end;

procedure TShellSourcesTests.WarmUpFirstUse;
var
  mMetrics: TLspMetricsSource;
begin
  // Erste Benutzung (Einstellungen des Arbeitsbereichs, Monitor-Datensätze) nicht dem ersten Test anrechnen.
  Setup;
  try
    AddWorkspace;
    FSources.MetricsSource()('', False, mMetrics);
  finally
    TearDown;
  end;
end;

procedure TShellSourcesTests.TearDown;
begin
  FreeAndNil(FSources);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
  FRoot := '';
end;

procedure TShellSourcesTests.AddWorkspace;
begin
  FRegistry.Add(TShellWorkspace.Create(FRoot, 'Ordner', TShellWorkspaceServices.Create(TDocumentStore.Create,
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create, TSymbolIndex.Create,
    'atlas-test-index')));
end;

procedure TShellSourcesTests.NoWorkspaceNoSource;
var
  mMetrics: TLspMetricsSource;
  mArchitecture: TArchitectureRequest;
  mHotspots: THotspotRequest;
  mQuery: TQuerySource;
  mSettings: TServerSettings;
  mVcs: IHotspotVcs;
  mError, mRoot: string;
  mNamespaces: TArray<string>;
  mRelations: TUsesGraphOptions;
begin
  Assert.IsFalse(FSources.MetricsSource()('', True, mMetrics));
  Assert.IsFalse(FSources.ArchitectureSource()('', '', mArchitecture, mSettings));
  Assert.IsFalse(FSources.HotspotSource()('', mHotspots, mSettings, mVcs, mError));
  Assert.IsNull(mVcs);
  Assert.AreEqual('', mError);
  Assert.IsFalse(FSources.QuerySource()(mQuery));
  Assert.IsFalse(FSources.QuerySettings()('', mSettings, mRoot));
  Assert.IsFalse(FSources.SymbolPathSource()('', mSettings, mNamespaces));
  Assert.AreEqual(0, Integer(Length(mNamespaces)));
  mRelations := FSources.UnitRelationsOptions()('');
  Assert.IsTrue(mRelations.IncludeLibrary);
  Assert.AreEqual('', mRelations.Root);
end;

procedure TShellSourcesTests.SingleWorkspaceMetrics;
var
  mMetrics: TLspMetricsSource;
  mSettings: TServerSettings;
  mRoot: string;
begin
  AddWorkspace;
  Assert.IsTrue(FSources.MetricsSource()('', False, mMetrics));
  Assert.AreEqual(FRoot, mMetrics.Root);
  Assert.AreEqual('Ordner', mMetrics.Title);
  Assert.IsTrue(FSources.QuerySettings()('', mSettings, mRoot));
  Assert.AreEqual(FRoot, mRoot);
end;

procedure TShellSourcesTests.SingleWorkspaceArchitecture;
var
  mArchitecture: TArchitectureRequest;
  mSettings: TServerSettings;
begin
  AddWorkspace;
  Assert.IsTrue(FSources.ArchitectureSource()('', 'project', mArchitecture, mSettings));
  Assert.AreEqual('project', mArchitecture.Scope);
  Assert.AreEqual(FRoot, mArchitecture.Root);
  Assert.AreEqual('Ordner', mArchitecture.Title);
end;

procedure TShellSourcesTests.SingleWorkspaceQueryAndRelations;
var
  mQuery: TQuerySource;
  mRelations: TUsesGraphOptions;
begin
  AddWorkspace;
  Assert.IsTrue(FSources.QuerySource()(mQuery));
  mRelations := FSources.UnitRelationsOptions()(TPath.Combine(FRoot, 'A.pas'));
  Assert.AreEqual(FRoot, mRelations.Root);
end;

procedure TShellSourcesTests.DefaultsWithoutWorkspace;
var
  mLimits: TMetricLimits;
  mDefault: TServerSettings;
  mRationale: TRationaleOptions;
begin
  mDefault := TServerSettings.Default;
  Assert.AreEqual(mDefault.Metrics and mDefault.CodeLens.Metrics,
    FSources.CodeLensMetrics()('file:///C:/A.pas', mLimits));
  mRationale := FSources.RationaleOptions()('file:///C:/A.pas');
  Assert.AreEqual(TRationaleOptions.FromSettings(FSettings.Loose, '').Enabled, mRationale.Enabled);
  Assert.AreEqual('', mRationale.AdrFolder);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSourcesTests);

end.
