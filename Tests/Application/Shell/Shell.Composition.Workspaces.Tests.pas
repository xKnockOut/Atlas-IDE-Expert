unit Shell.Composition.Workspaces.Tests;

// Register der Arbeitsbereiche: Aufnehmen und Herausnehmen nach Herkunft, Projekte der Gruppen, Ordner der
// Packages, Zuordnung einer Datei zum Ordner, Nutzer außerhalb der Sperre und leere Prüfprojekte.

interface

uses
  DUnitX.TestFramework,
  Shell.Workspace,
  Shell.Composition.Workspaces;

type
  [TestFixture]
  TShellWorkspaceRegistryTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FVisited: Integer;
    function NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string): TShellWorkspace;
    procedure CountVisited(const AWorkspaces: TArray<TShellWorkspace>);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich: kein Treffer, kein Aufbau, Prüfprojekte vollständig und leer.</summary>
    [Test]
    procedure EmptyRegistry;
    /// <summary>Gruppenprojekte stehen vor den Projekten der Arbeitsbereiche; Packages kommen aus deren Ordnern.
    /// </summary>
    [Test]
    procedure GroupProjectsAndPackageFolders;
    /// <summary>Eine Datei gehört zum Ordner, der sie enthält; ohne Treffer wählt Pick den einzigen.</summary>
    [Test]
    procedure WorkspaceOfFolder;
    /// <summary>Extract nimmt nur die Arbeitsbereiche der Herkunft heraus, die übrigen bleiben.</summary>
    [Test]
    procedure ExtractByOrigin;
    /// <summary>Nach Hold und Release gibt FreeWhenUnused sofort frei; Visit sieht alle.</summary>
    [Test]
    procedure HoldReleaseAndVisit;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
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

procedure TShellWorkspaceRegistryTests.Setup;
var
  mServices: TShellWorkspaceRegistryServices;
begin
  mServices := Default(TShellWorkspaceRegistryServices);
  mServices.Logger := TLogger.Create;
  mServices.SelectedProject := NoSelection;
  mServices.ActiveProject := NoActive;
  mServices.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mServices);
  FVisited := 0;
end;

procedure TShellWorkspaceRegistryTests.TearDown;
begin
  FreeAndNil(FRegistry);
end;

function TShellWorkspaceRegistryTests.NewWorkspace(const ARoot, AName, AProjectFile,
  AOrigin: string): TShellWorkspace;
begin
  Result := TShellWorkspace.Create(ARoot, AName, TShellWorkspaceServices.Create(TDocumentStore.Create,
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create, TSymbolIndex.Create,
    'atlas-test-index'));
  Result.Setup.ProjectFile := AProjectFile;
  Result.Setup.Origin := AOrigin;
end;

procedure TShellWorkspaceRegistryTests.CountVisited(const AWorkspaces: TArray<TShellWorkspace>);
begin
  FVisited := Length(AWorkspaces);
end;

procedure TShellWorkspaceRegistryTests.EmptyRegistry;
var
  mReason: string;
  mRemaining: TArray<TShellWorkspace>;
begin
  Assert.IsNull(FRegistry.WorkspaceOf(TPath.Combine('ordner', 'a.pas')));
  Assert.IsNull(FRegistry.Pick('a.pas'));
  Assert.IsFalse(FRegistry.HasProject('a.dproj'));
  Assert.AreEqual(-1, FRegistry.IndexLoading);
  Assert.IsFalse(FRegistry.ProjectIndexPending);
  Assert.IsTrue(FRegistry.RuleProjectsComplete(mReason));
  Assert.AreEqual('', mReason);
  Assert.AreEqual(0, Integer(Length(FRegistry.RuleProjects)));
  Assert.AreEqual(0, Integer(Length(FRegistry.Extract('x', mRemaining))));
  Assert.AreEqual(0, Integer(Length(mRemaining)));
end;

procedure TShellWorkspaceRegistryTests.GroupProjectsAndPackageFolders;
var
  mProject: string;
begin
  Assert.IsFalse(FRegistry.AddGroupProjects(TArray<string>.Create('g.dproj')));
  mProject := TPath.Combine('pkg', 'p.dproj');
  FRegistry.Add(NewWorkspace('pkg', 'p', mProject, 'o'));
  Assert.IsTrue(FRegistry.AddGroupProjects(TArray<string>.Create('h.dproj')));
  Assert.IsTrue(FRegistry.HasProject(mProject));
  Assert.AreEqual('g.dproj,h.dproj,' + mProject, string.Join(',', FRegistry.GroupProjectFiles));
  Assert.AreEqual('pkg', string.Join(',', FRegistry.PackageFolders));
end;

procedure TShellWorkspaceRegistryTests.WorkspaceOfFolder;
var
  mFirst, mSecond: TShellWorkspace;
  mRoot: string;
begin
  mRoot := TPath.Combine(TPath.GetTempPath, 'atlas-registry');
  mFirst := NewWorkspace(TPath.Combine(mRoot, 'eins'), 'eins', '', 'o');
  FRegistry.Add(mFirst);
  Assert.AreSame(mFirst, FRegistry.Pick(TPath.Combine(mRoot, 'fremd.pas')));
  mSecond := NewWorkspace(TPath.Combine(mRoot, 'zwei'), 'zwei', '', 'o');
  FRegistry.Add(mSecond);
  Assert.AreSame(mSecond, FRegistry.WorkspaceOf(TPath.Combine(TPath.Combine(mRoot, 'zwei'), 'a.pas')));
  Assert.IsNull(FRegistry.Pick(TPath.Combine(mRoot, 'fremd.pas')));
end;

procedure TShellWorkspaceRegistryTests.ExtractByOrigin;
var
  mRemoved, mRemaining: TArray<TShellWorkspace>;
  mKept: TShellWorkspace;
  mWorkspace: TShellWorkspace;
begin
  FRegistry.Add(NewWorkspace('a', 'a', '', 'weg'));
  mKept := NewWorkspace('b', 'b', '', 'bleibt');
  FRegistry.Add(mKept);
  mRemoved := FRegistry.Extract('WEG', mRemaining);
  try
    Assert.AreEqual(1, Integer(Length(mRemoved)));
    Assert.AreEqual(1, Integer(Length(mRemaining)));
    Assert.AreSame(mKept, mRemaining[0]);
    Assert.AreEqual(1, FRegistry.Items.Count);
  finally
    for mWorkspace in mRemoved do
    begin
      FRegistry.FreeWhenUnused(mWorkspace);
    end;
  end;
end;

procedure TShellWorkspaceRegistryTests.HoldReleaseAndVisit;
var
  mWorkspace: TShellWorkspace;
  mRemaining: TArray<TShellWorkspace>;
begin
  mWorkspace := NewWorkspace('a', 'a', '', 'o');
  FRegistry.Add(mWorkspace);
  FRegistry.Add(NewWorkspace('b', 'b', '', 'p'));
  FRegistry.Visit(CountVisited);
  Assert.AreEqual(2, FVisited);
  System.TMonitor.Enter(FRegistry.Lock);
  try
    FRegistry.Hold(TArray<TShellWorkspace>.Create(mWorkspace));
  finally
    System.TMonitor.Exit(FRegistry.Lock);
  end;
  FRegistry.Release(TArray<TShellWorkspace>.Create(mWorkspace));
  Assert.AreEqual(1, Integer(Length(FRegistry.Extract('o', mRemaining))));
  FRegistry.FreeWhenUnused(mWorkspace);
  Assert.AreEqual(1, Integer(Length(mRemaining)));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellWorkspaceRegistryTests);

end.
