unit Shell.Composition.Protocol.Tests;

// Teilwurzel Protokoll ohne Verbindung: Verteiler mit Lebenszyklus, Statistik und Absturzfällen erst auf Anfrage.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Protocol;

type
  [TestFixture]
  TShellProtocolTests = class
  private
    FProtocol: TShellProtocol;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Verteiler, Statistik und Lebenszyklus bestehen ab dem Anlegen.</summary>
    [Test]
    procedure CreatesDispatcherStatisticsAndLifecycle;
    /// <summary>Der Lebenszyklus meldet initialize und shutdown am Verteiler an.</summary>
    [Test]
    procedure LifecycleAttachesToDispatcher;
    /// <summary>Absturzfälle gibt es erst mit CreateCrashCases.</summary>
    [Test]
    procedure CrashCasesOnlyAfterCreate;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger;

function NoCapabilities: TJSONObject;
begin
  Result := TJSONObject.Create;
end;

function NoSettingsFiles(const AUri: string): TArray<string>;
begin
  Result := nil;
end;

procedure NoNotify(const AMethod: string; AParams: TJSONObject);
begin
  AParams.Free;
end;

procedure TShellProtocolTests.Setup;
var
  mServices: TShellProtocolServices;
begin
  mServices := Default(TShellProtocolServices);
  mServices.Logger := TLogger.Create;
  mServices.TimeoutMs := 60000;
  mServices.Capabilities := NoCapabilities;
  FProtocol := TShellProtocol.Create(mServices);
end;

procedure TShellProtocolTests.TearDown;
begin
  FreeAndNil(FProtocol);
end;

procedure TShellProtocolTests.CreatesDispatcherStatisticsAndLifecycle;
begin
  Assert.IsNotNull(FProtocol.Dispatcher);
  Assert.IsNotNull(FProtocol.Statistics);
  Assert.IsNotNull(FProtocol.Lifecycle);
  Assert.IsNotNull(FProtocol.Dispatcher.Watchdog);
end;

procedure TShellProtocolTests.LifecycleAttachesToDispatcher;
var
  mMethods: TArray<string>;
  mMethod: string;
  mInitialize: Boolean;
  mShutdown: Boolean;
begin
  mMethods := FProtocol.Dispatcher.Methods;
  mInitialize := False;
  mShutdown := False;
  for mMethod in mMethods do
  begin
    mInitialize := mInitialize or (mMethod = 'initialize');
    mShutdown := mShutdown or (mMethod = 'shutdown');
  end;
  Assert.IsTrue(mInitialize, 'initialize');
  Assert.IsTrue(mShutdown, 'shutdown');
end;

procedure TShellProtocolTests.CrashCasesOnlyAfterCreate;
var
  mDocuments: IDocumentStore;
begin
  Assert.IsNull(FProtocol.CrashCases);
  mDocuments := TDocumentStore.Create;
  FProtocol.CreateCrashCases(mDocuments, NoSettingsFiles, NoNotify);
  Assert.IsNotNull(FProtocol.CrashCases);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellProtocolTests);

end.
