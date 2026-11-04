unit Shell.Composition.ProtocolWiring.Tests;

// Verdrahtung von Protokoll und Dokumenten ohne Kern und Index: Teile bestehen, initialize liefert die
// Capabilities.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Parts;

type
  [TestFixture]
  TShellProtocolWiringTests = class
  private
    FParts: TShellParts;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Dokumentspeicher, Synchronisation, Absturzfälle, Compilerläufe und Diagnosen bestehen.</summary>
    [Test]
    procedure DocumentsCreatesParts;
    /// <summary>initialize liefert die Capabilities des Servers.</summary>
    [Test]
    procedure InitializeAnswersWithCapabilities;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  System.JSON,
  Shell.Composition.ProtocolWiring;

function NewParts: TShellParts;
begin
  Result := TShellParts.Create;
  Result.Channel.Logger := TLogger.Create;
  Result.Channel.Transport := TJsonRpcStreamTransport.Create(TMemoryStream.Create, TMemoryStream.Create, True);
end;

procedure TShellProtocolWiringTests.Setup;
begin
  FParts := NewParts;
  TShellProtocolWiring.Protocol(FParts);
  TShellProtocolWiring.Documents(FParts);
end;

procedure TShellProtocolWiringTests.TearDown;
begin
  FreeAndNil(FParts);
end;

procedure TShellProtocolWiringTests.DocumentsCreatesParts;
begin
  Assert.IsNotNull(FParts.Protocol);
  Assert.IsNotNull(FParts.Documents);
  Assert.IsNotNull(FParts.TextDocumentSync);
  Assert.IsNotNull(FParts.Protocol.CrashCases);
  Assert.IsNotNull(FParts.Compile);
  Assert.IsNotNull(FParts.CompilerProcess);
  Assert.IsNotNull(FParts.DiagnosticsArea);
end;

procedure TShellProtocolWiringTests.InitializeAnswersWithCapabilities;
var
  mMessage: TJSONObject;
  mAnswer: TJSONObject;
begin
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    mMessage.AddPair('id', TJSONNumber.Create(1));
    mMessage.AddPair('method', 'initialize');
    mMessage.AddPair('params', TJSONObject.Create);
    mAnswer := FParts.Protocol.Dispatcher.DispatchMessage(mMessage);
    try
      Assert.IsNotNull(mAnswer);
      Assert.IsNotNull(mAnswer.FindValue('result.capabilities'));
    finally
      mAnswer.Free;
    end;
  finally
    mMessage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellProtocolWiringTests);

end.
