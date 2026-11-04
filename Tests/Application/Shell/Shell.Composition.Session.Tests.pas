unit Shell.Composition.Session.Tests;

// Teilwurzel Sitzung ohne Verbindung: Diagnoselog am Verteiler, Endgrund, Zeitlimit und Fehlertext.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.Session;

type
  [TestFixture]
  TShellSessionTests = class
  private
    FDispatcher: TJsonRpcDispatcher;
    FSession: TShellSession;
    FStops: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Das Diagnoselog beobachtet den Verteiler ab dem Anlegen.</summary>
    [Test]
    procedure ObservesDispatcher;
    /// <summary>Ohne Meldung endet die Sitzung mit inputClosed und der Vorgabe als Zeitlimit.</summary>
    [Test]
    procedure StartsWithInputClosedAndDefaultTimeout;
    /// <summary>Die Servereinstellungen setzen das Zeitlimit.</summary>
    [Test]
    procedure SettingsSetRequestTimeout;
    /// <summary>Der Fehlertext nennt Klasse und Meldung.</summary>
    [Test]
    procedure DescribeFailureNamesClassAndMessage;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Logging.Providers.Logger;

const
  cTimeoutMs = 4321;

function NoIndexLoading: Integer;
begin
  Result := 0;
end;

procedure TShellSessionTests.Setup;
var
  mServices: TShellSessionServices;
begin
  FDispatcher := TJsonRpcDispatcher.Create;
  mServices := Default(TShellSessionServices);
  mServices.Logger := TLogger.Create;
  mServices.Documents := TDocumentStore.Create;
  mServices.Dispatcher := FDispatcher;
  mServices.IndexLoading := NoIndexLoading;
  FStops := 0;
  mServices.Stop :=
    procedure
    begin
      Inc(FStops);
    end;
  FSession := TShellSession.Create(mServices, cTimeoutMs);
end;

procedure TShellSessionTests.TearDown;
begin
  FreeAndNil(FSession);
  FreeAndNil(FDispatcher);
end;

procedure TShellSessionTests.ObservesDispatcher;
begin
  Assert.IsNotNull(FDispatcher.Observer);
  Assert.IsNotNull(FSession.Diagnostics);
end;

procedure TShellSessionTests.StartsWithInputClosedAndDefaultTimeout;
begin
  Assert.IsTrue(FSession.EndReason = TDiagnosticEndReason.InputClosed);
  Assert.AreEqual(Cardinal(cTimeoutMs), FSession.RequestTimeout);
  Assert.AreEqual(0, FStops);
end;

procedure TShellSessionTests.SettingsSetRequestTimeout;
var
  mSettings: TServerSettings;
begin
  mSettings := Default(TServerSettings);
  mSettings.RequestTimeoutMs := 2500;
  FSession.ApplySettings(mSettings);
  Assert.AreEqual(Cardinal(2500), FSession.RequestTimeout);
end;

procedure TShellSessionTests.DescribeFailureNamesClassAndMessage;
var
  mError: Exception;
  mText: string;
begin
  mError := EArgumentException.Create('Kaputt');
  try
    mText := FSession.DescribeFailure(mError);
  finally
    mError.Free;
  end;
  Assert.IsTrue(mText.StartsWith('EArgumentException: Kaputt'), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSessionTests);

end.
