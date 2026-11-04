unit Shell.Composition.IndexArea.Tests;

// Teilwurzel Index auf einem Kern ohne Ordner und ohne Diagnosen: Index und Uses-Graph bestehen, ein geladenes
// Projekt verteilt Namespaces und Bibliotheksordner, eine fertige Stufe prüft die Konfigurationen in der
// Nachrichtenschleife neu.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.Core,
  Shell.Composition.IndexArea;

type
  [TestFixture]
  TShellIndexAreaTests = class
  private
    FDocuments: IDocumentStore;
    FCore: TShellCore;
    FDispatcher: TJsonRpcDispatcher;
    FArea: TShellIndexArea;
    FProjectStarts: Integer;
    FNamespaceCalls: Integer;
    FRootCalls: Integer;
    FQueued: Integer;
    function NewServices: TShellIndexAreaServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Index und Uses-Graph bestehen ab dem Anlegen.</summary>
    [Test]
    procedure CreatesIndexAndUsesGraph;
    /// <summary>Ein geladenes Projekt startet den Compiler neu und verteilt Namespaces und Bibliotheksordner.</summary>
    [Test]
    procedure ProjectLoadedNotifiesListeners;
    /// <summary>Eine fertige Stufe reiht die neue Prüfung der Konfigurationen in die Nachrichtenschleife ein.</summary>
    [Test]
    procedure IndexStageDoneQueuesRevalidation;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Pascal.Preprocessor,
  Shell.Composition.DiagnosticsArea;

function NoIndex: ISymbolIndex;
begin
  Result := nil;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

procedure TShellIndexAreaTests.Setup;
var
  mCoreServices: TShellCoreServices;
begin
  FDocuments := TDocumentStore.Create;
  mCoreServices := Default(TShellCoreServices);
  mCoreServices.Logger := TLogger.Create;
  mCoreServices.Documents := FDocuments;
  mCoreServices.Index := NoIndex;
  mCoreServices.SelectedProject := NoSelection;
  mCoreServices.ActiveProject := NoActive;
  FCore := TShellCore.Create(mCoreServices);
  FDispatcher := TJsonRpcDispatcher.Create;
  FProjectStarts := 0;
  FNamespaceCalls := 0;
  FRootCalls := 0;
  FQueued := 0;
  FArea := TShellIndexArea.Create(NewServices);
end;

procedure TShellIndexAreaTests.TearDown;
begin
  // Declared(X) hält den Index; ohne Abmelden lebte er bis zum Programmende.
  TPascalPreprocessor.SetDeclaredProvider(nil);
  FreeAndNil(FArea);
  FreeAndNil(FDispatcher);
  FDocuments := nil;
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
end;

function TShellIndexAreaTests.NewServices: TShellIndexAreaServices;
begin
  Result := Default(TShellIndexAreaServices);
  Result.Dispatcher := FDispatcher;
  Result.Core :=
    function: TShellCore
    begin
      Result := FCore;
    end;
  Result.Diagnostics :=
    function: TShellDiagnosticsArea
    begin
      Result := nil;
    end;
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := nil;
    end;
  Result.ProjectStarted :=
    procedure
    begin
      Inc(FProjectStarts);
    end;
  Result.NamespacesChanged :=
    procedure(const ANames: TArray<string>)
    begin
      Inc(FNamespaceCalls);
    end;
  Result.LibraryRootsChanged :=
    procedure(const ANames: TArray<string>)
    begin
      Inc(FRootCalls);
    end;
  Result.Queue :=
    function(const AWork: TProc): Boolean
    begin
      Inc(FQueued);
      Result := True;
    end;
end;

procedure TShellIndexAreaTests.CreatesIndexAndUsesGraph;
begin
  Assert.IsNotNull(FArea.Index);
  Assert.IsNotNull(FArea.UsesGraph);
end;

procedure TShellIndexAreaTests.ProjectLoadedNotifiesListeners;
begin
  FArea.ProjectLoaded;
  Assert.AreEqual(1, FProjectStarts);
  Assert.AreEqual(1, FNamespaceCalls);
  Assert.AreEqual(1, FRootCalls);
end;

procedure TShellIndexAreaTests.IndexStageDoneQueuesRevalidation;
begin
  FArea.IndexStageDone(True);
  Assert.AreEqual(1, FQueued);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellIndexAreaTests);

end.
