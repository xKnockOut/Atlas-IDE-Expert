unit BDLsp.Common.Lsp.Adapters.LogMessageSink.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspLogMessageSinkTests = class
  public
    [Test]
    procedure SendsWindowLogMessage;
    [Test]
    procedure MapsLevelsToMessageTypes;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.StreamTransport,
  BDLsp.Common.Lsp.Adapters.LogMessageSink,
  BDLsp.Common.JsonRpc.TestSupport;

{ TLspLogMessageSinkTests }

procedure TLspLogMessageSinkTests.SendsWindowLogMessage;
var
  Output: TBytesStream;
  Sink: ILogSink;
  Messages: TObjectList<TJSONObject>;
begin
  Output := TBytesStream.Create;
  try
    Sink := TLspLogMessageSink.Create(TJsonRpcStreamTransport.Create(nil, Output, False));
    Sink.Write(TLogEntry.Create(Now, TLogLevel.Warning, 'Achtung'));
    Sink := nil;

    Messages := TJsonRpcTestSupport.ReadMessages(Output);
    try
      Assert.AreEqual<NativeInt>(1, Messages.Count);
      Assert.AreEqual('window/logMessage', Messages[0].GetValue<string>('method'));
      Assert.IsNull(Messages[0].GetValue('id'));
      Assert.AreEqual(2, Messages[0].GetValue<Integer>('params.type'));
      Assert.AreEqual('Achtung', Messages[0].GetValue<string>('params.message'));
    finally
      Messages.Free;
    end;
  finally
    Output.Free;
  end;
end;

procedure TLspLogMessageSinkTests.MapsLevelsToMessageTypes;
begin
  Assert.AreEqual(1, TLspLogMessageSink.MessageTypeOf(TLogLevel.Error));
  Assert.AreEqual(2, TLspLogMessageSink.MessageTypeOf(TLogLevel.Warning));
  Assert.AreEqual(3, TLspLogMessageSink.MessageTypeOf(TLogLevel.Info));
  Assert.AreEqual(4, TLspLogMessageSink.MessageTypeOf(TLogLevel.Debug));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspLogMessageSinkTests);

end.
