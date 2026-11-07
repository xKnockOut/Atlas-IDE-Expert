unit Shell.Composition.IdeArea.Tests;

// Teilwurzel IDE auf einem Kern ohne Ordner: Teile bestehen und hängen am Verteiler.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.Core,
  Shell.Composition.IdeArea;

type
  [TestFixture]
  TShellIdeAreaTests = class
  private
    FDocuments: IDocumentStore;
    FCore: TShellCore;
    FDispatcher: TJsonRpcDispatcher;
    FArea: TShellIdeArea;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Dateiänderungen, IDE und Projektwahl bestehen ab dem Anlegen.</summary>
    [Test]
    procedure CreatesParts;
    /// <summary>Die IDE hört am Verteiler auf atlas/projectContext.</summary>
    [Test]
    procedure ProjectContextReachesIde;
    /// <summary>Ohne Ordner und Projekt gelten die vorgegebenen Formatfunktionen.</summary>
    [Test]
    procedure FormatRoutinesWithoutWorkspaceAreDefaults;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  System.JSON,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger,
  Shell.Composition.Compile,
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

function NoDiagnostics: TShellDiagnosticsArea;
begin
  Result := nil;
end;

function NoCompile: TShellCompileHost;
begin
  Result := nil;
end;

procedure TShellIdeAreaTests.Setup;
var
  mCoreServices: TShellCoreServices;
  mServices: TShellIdeAreaServices;
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
  mServices := Default(TShellIdeAreaServices);
  mServices.Logger := mCoreServices.Logger;
  mServices.Dispatcher := FDispatcher;
  mServices.Diagnostics := NoDiagnostics;
  mServices.Compile := NoCompile;
  FArea := TShellIdeArea.Create(FCore, mServices);
end;

procedure TShellIdeAreaTests.TearDown;
begin
  FreeAndNil(FArea);
  FreeAndNil(FDispatcher);
  FDocuments := nil;
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
end;

procedure TShellIdeAreaTests.CreatesParts;
begin
  Assert.IsNotNull(FArea.FileChanges);
  Assert.IsNotNull(FArea.Ide);
  Assert.IsNotNull(FArea.Selection);
end;

procedure TShellIdeAreaTests.ProjectContextReachesIde;
const
  cProject = 'C:\Projekt\Haupt.dproj';
var
  mMessage: TJSONObject;
  mParams: TJSONObject;
  mAnswer: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('project', cProject);
  mParams.AddPair('active', TJSONBool.Create(True));
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    mMessage.AddPair('method', TLspIdeProject.cMethod);
    mMessage.AddPair('params', mParams);
    mAnswer := FDispatcher.DispatchMessage(mMessage);
    mAnswer.Free;
  finally
    mMessage.Free;
  end;
  Assert.AreEqual(cProject, FArea.Ide.Project.ActiveProject);
end;

procedure TShellIdeAreaTests.FormatRoutinesWithoutWorkspaceAreDefaults;
begin
  Assert.AreEqual(Integer(Length(TFormatRoutines.Defaults)),
    Integer(Length(FArea.FormatRoutinesFor(TDocumentUris.FromPath('C:\Projekt\Lose.pas')))));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellIdeAreaTests);

end.
