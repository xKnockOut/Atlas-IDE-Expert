unit Shell.Composition.AnalysisArea.Tests;

// Teilwurzel Analyse auf einem Kern ohne Ordner: Die Teile bestehen ab dem Anlegen, die betroffenen Tests sind am
// Verteiler, und die Optionen der Auswirkungsanalyse folgen Einstellungen und Zeitlimit.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Shell.Composition.Core,
  Shell.Composition.AnalysisArea;

type
  [TestFixture]
  TShellAnalysisAreaTests = class
  private
    FDocuments: IDocumentStore;
    FDispatcher: TJsonRpcDispatcher;
    FCore: TShellCore;
    FArea: TShellAnalysisArea;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Analysen, Übersichten und Baselines bestehen ab dem Anlegen.</summary>
    [Test]
    procedure PartsExist;
    /// <summary>Die betroffenen Tests sind am Verteiler angemeldet.</summary>
    [Test]
    procedure AffectedTestsAttached;
    /// <summary>Tiefe aus den Einstellungen, vier Fünftel des Zeitlimits, ohne Testunit keine Tests.</summary>
    [Test]
    procedure ImpactOptionsFollowSettings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.AffectedTests;

const
  cTimeout = 10000;

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

function NoTestUnit(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  Result := False;
end;

function FixedTimeout: Cardinal;
begin
  Result := cTimeout;
end;

procedure TShellAnalysisAreaTests.Setup;
var
  mCoreServices: TShellCoreServices;
  mServices: TShellAnalysisAreaServices;
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
  mServices := Default(TShellAnalysisAreaServices);
  mServices.Logger := mCoreServices.Logger;
  mServices.Dispatcher := FDispatcher;
  mServices.Documents := FDocuments;
  mServices.TestUnitContext := NoTestUnit;
  mServices.RequestTimeout := FixedTimeout;
  FArea := TShellAnalysisArea.Create(FCore, mServices);
end;

procedure TShellAnalysisAreaTests.TearDown;
begin
  FreeAndNil(FArea);
  FCore.FreeWorkspaces;
  FreeAndNil(FCore);
  FreeAndNil(FDispatcher);
  FDocuments := nil;
end;

procedure TShellAnalysisAreaTests.PartsExist;
begin
  Assert.IsNotNull(FArea.Analysis);
  Assert.IsNotNull(FArea.Overviews);
  Assert.IsNotNull(FArea.Baselines);
end;

procedure TShellAnalysisAreaTests.AffectedTestsAttached;
var
  mMethod: string;
  mFound: Boolean;
begin
  mFound := False;
  for mMethod in FDispatcher.Methods do
  begin
    if mMethod = TAffectedTests.Method then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, TAffectedTests.Method);
end;

procedure TShellAnalysisAreaTests.ImpactOptionsFollowSettings;
var
  mOptions: TImpactOptions;
begin
  mOptions := FArea.ImpactOptionsFor('file:///C:/Projekt/Offen.pas');
  Assert.AreEqual(FCore.Settings.SettingsFor('file:///C:/Projekt/Offen.pas').Navigation.ImpactDepth, mOptions.Depth);
  Assert.AreEqual(cTimeout div 5 * 4, mOptions.TimeoutMs);
  Assert.AreEqual(0, Integer(Length(mOptions.Tests.Units)));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellAnalysisAreaTests);

end.
