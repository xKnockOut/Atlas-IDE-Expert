unit Shell.Composition.ClientStart.Tests;

// Start nach initialized auf allen Teilen: Clientname aus initialize, ohne gemeldete Ordner werden Arbeitsbereiche
// aus den geöffneten Dateien abgeleitet.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Parts;

type
  [TestFixture]
  TShellClientStartTests = class
  private
    FParts: TShellParts;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Der Name aus clientInfo gilt für die Sitzung.</summary>
    [Test]
    procedure TakesClientName;
    /// <summary>Ohne gemeldete Ordner leitet der Server Arbeitsbereiche aus den Dateien ab.</summary>
    [Test]
    procedure NoFoldersDerivesWorkspaces;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  System.JSON,
  Shell.Composition.ProtocolWiring,
  Shell.Composition.FeatureWiring,
  Shell.Composition.CoreWiring,
  Shell.Composition.CommandWiring,
  Shell.Composition.ClientStart;

function NewParts: TShellParts;
begin
  Result := TShellParts.Create;
  Result.Channel.Logger := TLogger.Create;
  Result.Channel.Transport := TJsonRpcStreamTransport.Create(TMemoryStream.Create, TMemoryStream.Create, True);
end;

/// <summary>Alle Teile in der Reihenfolge von TServerComposition.Create.</summary>
procedure WireAll(AParts: TShellParts);
begin
  TShellProtocolWiring.Protocol(AParts);
  TShellProtocolWiring.Documents(AParts);
  TShellFeatureWiring.Editing(AParts);
  TShellCoreWiring.Workspaces(AParts);
  TShellCoreWiring.Index(AParts);
  TShellFeatureWiring.Code(AParts);
  TShellFeatureWiring.Analysis(AParts);
  TShellCommandWiring.Commands(AParts);
  TShellFeatureWiring.Ide(AParts);
end;

/// <summary>Schickt initialize mit Clientname an den Verteiler.</summary>
procedure Initialize(AParts: TShellParts; const AClient: string);
var
  mMessage: TJSONObject;
  mParams: TJSONObject;
  mInfo: TJSONObject;
  mAnswer: TJSONObject;
begin
  mInfo := TJSONObject.Create;
  mInfo.AddPair('name', AClient);
  mParams := TJSONObject.Create;
  mParams.AddPair('clientInfo', mInfo);
  mParams.AddPair('capabilities', TJSONObject.Create);
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    mMessage.AddPair('id', TJSONNumber.Create(1));
    mMessage.AddPair('method', 'initialize');
    mMessage.AddPair('params', mParams);
    mAnswer := AParts.Protocol.Dispatcher.DispatchMessage(mMessage);
    mAnswer.Free;
  finally
    mMessage.Free;
  end;
end;

procedure TShellClientStartTests.WarmUpFirstUse;
begin
  Setup;
  try
    TakesClientName;
  finally
    TearDown;
  end;
end;

procedure TShellClientStartTests.Setup;
begin
  FParts := NewParts;
  WireAll(FParts);
end;

procedure TShellClientStartTests.TearDown;
begin
  FreeAndNil(FParts);
end;

procedure TShellClientStartTests.TakesClientName;
begin
  Initialize(FParts, 'Testclient');
  TShellClientStart.Initialized(FParts);
  Assert.AreEqual('Testclient', FParts.Session.ClientName);
end;

procedure TShellClientStartTests.NoFoldersDerivesWorkspaces;
begin
  Initialize(FParts, 'Testclient');
  TShellClientStart.Initialized(FParts);
  Assert.IsTrue(FParts.DeriveWorkspaces);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellClientStartTests);

end.
