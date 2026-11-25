unit Shell.Composition.CommandWiring.Tests;

// Verdrahtung von workspace/executeCommand auf allen Teilen.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Parts;

type
  [TestFixture]
  TShellCommandWiringTests = class
  private
    FParts: TShellParts;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Die Teilwurzel Befehle besteht.</summary>
    [Test]
    procedure CreatesCommandArea;
    /// <summary>workspace/executeCommand ist am Verteiler angemeldet.</summary>
    [Test]
    procedure ExecuteCommandReachesDispatcher;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  System.StrUtils,
  Shell.Composition.CommandWiring,
  Shell.Composition.TestSupport;

function NewParts: TShellParts;
begin
  Result := TShellParts.Create;
  Result.Channel.Logger := TLogger.Create;
  Result.Channel.Transport := TJsonRpcStreamTransport.Create(TMemoryStream.Create, TMemoryStream.Create, True);
end;

{ TShellCommandWiringTests }

procedure TShellCommandWiringTests.Setup;
begin
  FParts := NewParts;
  TShellTest.WireAll(FParts);
end;

procedure TShellCommandWiringTests.TearDown;
begin
  FreeAndNil(FParts);
end;

procedure TShellCommandWiringTests.CreatesCommandArea;
begin
  Assert.IsNotNull(FParts.CommandArea);
end;

procedure TShellCommandWiringTests.ExecuteCommandReachesDispatcher;
begin
  Assert.IsTrue(IndexStr('workspace/executeCommand', FParts.Protocol.Dispatcher.Methods) >= 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCommandWiringTests);

end.
