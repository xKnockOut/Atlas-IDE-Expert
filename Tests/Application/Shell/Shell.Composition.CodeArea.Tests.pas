unit Shell.Composition.CodeArea.Tests;

// Teilwurzel Code auf einem Kern ohne Ordner: Die Teile bestehen ab dem Anlegen, Vervollständigung und
// Code-Aktionen sind am Verteiler, und der uses-Kontext steht ab dem Anlegen bereit.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Shell.Composition.Core,
  Shell.Composition.Editing,
  Shell.Composition.CodeArea;

type
  [TestFixture]
  TShellCodeAreaTests = class
  private
    FDocuments: IDocumentStore;
    FDispatcher: TJsonRpcDispatcher;
    FCore: TShellCore;
    FEditing: TShellEditing;
    FArea: TShellCodeArea;
    function HasMethod(const AMethod: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Testunits, Navigation, Refactorings, Vervollständigung und Code-Aktionen bestehen ab dem
    /// Anlegen.</summary>
    [Test]
    procedure PartsExist;
    /// <summary>Vervollständigung und Code-Aktionen sind am Verteiler angemeldet.</summary>
    [Test]
    procedure RequestsAttached;
    /// <summary>Der uses-Kontext steht ab dem Anlegen bereit; ohne Arbeitsbereich ohne Namensräume.</summary>
    [Test]
    procedure UsesContextWithoutWorkspace;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.CodeActions;

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

procedure TShellCodeAreaTests.Setup;
var
  mCoreServices: TShellCoreServices;
  mEditing: TShellEditingServices;
  mServices: TShellCodeAreaServices;
begin
  FDocuments := TDocumentStore.Create;
  FDispatcher := TJsonRpcDispatcher.Create;
  mCoreServices := Default(TShellCoreServices);
  mCoreServices.Logger := TLogger.Create;
  mCoreServices.Documents := FDocuments;
  mCoreServices.Index := NoIndex;
  mCoreServices.SelectedProject := NoSelection;
  mCoreServices.ActiveProject := NoActive;
  FCore := TShellCore.Create(mCoreServices);
  mEditing := Default(TShellEditingServices);
  mEditing.Documents := FDocuments;
  FEditing := TShellEditing.Create(mEditing);
  mServices := Default(TShellCodeAreaServices);
  mServices.Logger := mCoreServices.Logger;
  mServices.Dispatcher := FDispatcher;
  mServices.Documents := FDocuments;
  mServices.Editing := FEditing;
  FArea := TShellCodeArea.Create(FCore, mServices);
end;

procedure TShellCodeAreaTests.TearDown;
begin
  FreeAndNil(FArea);
  FreeAndNil(FEditing);
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
  FreeAndNil(FDispatcher);
  FDocuments := nil;
end;

function TShellCodeAreaTests.HasMethod(const AMethod: string): Boolean;
var
  mMethod: string;
begin
  Result := False;
  for mMethod in FDispatcher.Methods do
  begin
    if mMethod = AMethod then
    begin
      Result := True;
    end;
  end;
end;

procedure TShellCodeAreaTests.PartsExist;
begin
  Assert.IsNotNull(FArea.TestUnits);
  Assert.IsNotNull(FArea.Navigation);
  Assert.IsNotNull(FArea.Refactorings);
  Assert.IsNotNull(FArea.Completion);
  Assert.IsNotNull(FArea.CodeActions);
end;

procedure TShellCodeAreaTests.RequestsAttached;
begin
  Assert.IsTrue(HasMethod(TLspCompletion.Method), TLspCompletion.Method);
  Assert.IsTrue(HasMethod(TLspCodeActions.Method), TLspCodeActions.Method);
end;

procedure TShellCodeAreaTests.UsesContextWithoutWorkspace;
var
  mContext: TUsesContext;
begin
  Assert.IsTrue(FArea.UsesContextFor('file:///C:/Projekt/Offen.pas', mContext));
  Assert.AreEqual(0, Integer(Length(mContext.Namespaces)));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCodeAreaTests);

end.
