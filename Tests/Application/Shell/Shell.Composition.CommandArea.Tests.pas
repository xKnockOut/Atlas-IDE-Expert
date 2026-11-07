unit Shell.Composition.CommandArea.Tests;

// Teilwurzel Befehle auf Kern, Editor und den Teilwurzeln Code und Analyse ohne Ordner: Die Teile bestehen ab dem
// Anlegen, workspace/executeCommand ist am Verteiler, und die Befehle der Teile stehen in der Befehlsliste.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Shell.Composition.Core,
  Shell.Composition.Editing,
  Shell.Composition.CodeArea,
  Shell.Composition.AnalysisArea,
  Shell.Composition.CommandArea;

type
  [TestFixture]
  TShellCommandAreaTests = class
  private
    FDocuments: IDocumentStore;
    FDispatcher: TJsonRpcDispatcher;
    FCore: TShellCore;
    FEditing: TShellEditing;
    FCode: TShellCodeArea;
    FAnalysis: TShellAnalysisArea;
    FArea: TShellCommandArea;
    procedure CreateAreas;
    function CommandList: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Befehlsliste, Status, Befehle am Server und am Editor und die Unit-Suche bestehen ab dem
    /// Anlegen.</summary>
    [Test]
    procedure PartsExist;
    /// <summary>workspace/executeCommand ist am Verteiler angemeldet.</summary>
    [Test]
    procedure ExecuteCommandAttached;
    /// <summary>Befehle am Server und die Berichte der Analysen stehen in der Befehlsliste.</summary>
    [Test]
    procedure CommandsOfPartsListed;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Metrics,
  Shell.Composition.ServerCommands;

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

procedure TShellCommandAreaTests.Setup;
var
  mCoreServices: TShellCoreServices;
  mEditing: TShellEditingServices;
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
  CreateAreas;
end;

procedure TShellCommandAreaTests.CreateAreas;
var
  mLogger: ILogger;
  mCode: TShellCodeAreaServices;
  mAnalysis: TShellAnalysisAreaServices;
  mServices: TShellCommandAreaServices;
begin
  mLogger := TLogger.Create;
  mCode := Default(TShellCodeAreaServices);
  mCode.Logger := mLogger;
  mCode.Dispatcher := FDispatcher;
  mCode.Documents := FDocuments;
  mCode.Editing := FEditing;
  FCode := TShellCodeArea.Create(FCore, mCode);
  mAnalysis := Default(TShellAnalysisAreaServices);
  mAnalysis.Logger := mLogger;
  mAnalysis.Dispatcher := FDispatcher;
  mAnalysis.Documents := FDocuments;
  FAnalysis := TShellAnalysisArea.Create(FCore, mAnalysis);
  mServices := Default(TShellCommandAreaServices);
  mServices.Logger := mLogger;
  mServices.Dispatcher := FDispatcher;
  mServices.Editor.Documents := FDocuments;
  FArea := TShellCommandArea.Create(FCore, FCode, FAnalysis, FEditing, mServices);
end;

procedure TShellCommandAreaTests.TearDown;
begin
  FreeAndNil(FArea);
  FreeAndNil(FAnalysis);
  FreeAndNil(FCode);
  FreeAndNil(FEditing);
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
  FreeAndNil(FDispatcher);
  FDocuments := nil;
end;

function TShellCommandAreaTests.CommandList: string;
var
  mCapability: TJSONObject;
begin
  mCapability := FArea.Commands.Capability;
  try
    Result := mCapability.ToJSON;
  finally
    mCapability.Free;
  end;
end;

procedure TShellCommandAreaTests.PartsExist;
begin
  Assert.IsNotNull(FArea.Commands);
  Assert.IsNotNull(FArea.StatusReports);
  Assert.IsNotNull(FArea.ServerCommands);
  Assert.IsNotNull(FArea.EditorCommands);
  Assert.IsNotNull(FArea.UnitSearch);
end;

procedure TShellCommandAreaTests.ExecuteCommandAttached;
var
  mMethod: string;
  mFound: Boolean;
begin
  mFound := False;
  for mMethod in FDispatcher.Methods do
  begin
    if mMethod = TLspCommands.cMethod then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, TLspCommands.cMethod);
end;

procedure TShellCommandAreaTests.CommandsOfPartsListed;
var
  mText: string;
begin
  mText := CommandList;
  Assert.IsTrue(Pos('"' + TShellServerCommands.cCompileCommand + '"', mText) > 0, TShellServerCommands.cCompileCommand);
  Assert.IsTrue(Pos('"' + TLspMetrics.cCommand + '"', mText) > 0, TLspMetrics.cCommand);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCommandAreaTests);

end.
