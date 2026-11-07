unit Shell.Composition.EditingArea.Tests;

// Teilwurzel Bearbeiten auf einem Kern ohne Ordner: Teile bestehen, und Bearbeiten hängt am Verteiler.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.Core,
  Shell.Composition.EditingArea;

type
  [TestFixture]
  TShellEditingAreaTests = class
  private
    FDocuments: IDocumentStore;
    FCore: TShellCore;
    FDispatcher: TJsonRpcDispatcher;
    FArea: TShellEditingArea;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Bearbeiten und Host der Schnellbefehle bestehen ab dem Anlegen.</summary>
    [Test]
    procedure CreatesParts;
    /// <summary>Bearbeiten beantwortet textDocument/documentSymbol am Verteiler.</summary>
    [Test]
    procedure AttachesDocumentSymbols;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger;

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

procedure TShellEditingAreaTests.Setup;
var
  mCoreServices: TShellCoreServices;
  mServices: TShellEditingAreaServices;
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
  mServices := Default(TShellEditingAreaServices);
  mServices.Core :=
    function: TShellCore
    begin
      Result := FCore;
    end;
  mServices.Editing.Documents := FDocuments;
  mServices.Slash.Logger := mCoreServices.Logger;
  mServices.Slash.Dispatcher := FDispatcher;
  FArea := TShellEditingArea.Create(mServices);
end;

procedure TShellEditingAreaTests.TearDown;
begin
  FreeAndNil(FArea);
  FreeAndNil(FDispatcher);
  FDocuments := nil;
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
end;

procedure TShellEditingAreaTests.CreatesParts;
begin
  Assert.IsNotNull(FArea.Editing);
  Assert.IsNotNull(FArea.Slash);
  Assert.IsNotNull(FArea.Slash.Host);
end;

procedure TShellEditingAreaTests.AttachesDocumentSymbols;
var
  mMethod: string;
  mFound: Boolean;
begin
  mFound := False;
  for mMethod in FDispatcher.Methods do
  begin
    mFound := mFound or (mMethod = TLspDocumentSymbols.cMethod);
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellEditingAreaTests);

end.
