unit Shell.Composition.DiagnosticsArea.Tests;

// Teilwurzel Diagnosen ohne Kern und Index: Die Teile bestehen ab dem Anlegen, die Pull-Diagnosen sind am
// Verteiler, und diagnosticProvider kommt nur für Clients, die Pull-Diagnosen können.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.DiagnosticsArea;

type
  [TestFixture]
  TShellDiagnosticsAreaTests = class
  private
    FDispatcher: TJsonRpcDispatcher;
    FArea: TShellDiagnosticsArea;
    function CapabilitiesFor(const AInitializeParams: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Syntaxprüfung, Pull-Diagnosen und Tor bestehen ab dem Anlegen.</summary>
    [Test]
    procedure PartsExist;
    /// <summary>textDocument/diagnostic ist am Verteiler angemeldet.</summary>
    [Test]
    procedure PullAttached;
    /// <summary>diagnosticProvider nur mit capabilities.textDocument.diagnostic.</summary>
    [Test]
    procedure ProviderOnlyForPullClients;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Lsp.PullDiagnostics;

function NoTimeout: Cardinal;
begin
  Result := 0;
end;

function PlainLabel(const AFileName: string): string;
begin
  Result := 'unit';
end;

procedure TShellDiagnosticsAreaTests.Setup;
var
  mServices: TShellDiagnosticsAreaServices;
begin
  FDispatcher := TJsonRpcDispatcher.Create;
  mServices := Default(TShellDiagnosticsAreaServices);
  mServices.Logger := TLogger.Create;
  mServices.Dispatcher := FDispatcher;
  mServices.Documents := TDocumentStore.Create;
  mServices.FileLabel := PlainLabel;
  mServices.RequestTimeout := NoTimeout;
  FArea := TShellDiagnosticsArea.Create(mServices);
end;

procedure TShellDiagnosticsAreaTests.TearDown;
begin
  FArea.FreeChecks;
  FreeAndNil(FArea);
  FreeAndNil(FDispatcher);
end;

function TShellDiagnosticsAreaTests.CapabilitiesFor(const AInitializeParams: string): string;
var
  mParams: TJSONObject;
  mCapabilities: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue(AInitializeParams) as TJSONObject;
  mCapabilities := TJSONObject.Create;
  try
    FArea.ApplyClientCapabilities(mParams, mCapabilities);
    Result := mCapabilities.ToJSON;
  finally
    mCapabilities.Free;
    mParams.Free;
  end;
end;

procedure TShellDiagnosticsAreaTests.PartsExist;
begin
  Assert.IsNotNull(FArea.Syntax);
  Assert.IsNotNull(FArea.Pull);
  Assert.IsNotNull(FArea.IndexRecheck);
end;

procedure TShellDiagnosticsAreaTests.PullAttached;
var
  mMethod: string;
  mFound: Boolean;
begin
  mFound := False;
  for mMethod in FDispatcher.Methods do
  begin
    if mMethod = TLspPullDiagnostics.DocumentMethod then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, TLspPullDiagnostics.DocumentMethod);
end;

procedure TShellDiagnosticsAreaTests.ProviderOnlyForPullClients;
begin
  Assert.IsTrue(Pos('diagnosticProvider', CapabilitiesFor('{"capabilities":{"textDocument":{"diagnostic":{}}}}')) > 0);
  Assert.IsTrue(FArea.Syntax.PullMode);
  Assert.AreEqual('{}', CapabilitiesFor('{"capabilities":{}}'));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellDiagnosticsAreaTests);

end.
