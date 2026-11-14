unit Atlas.Common.Lsp.Adapters.LogMessageSink.Tests;

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
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.Lsp.Adapters.LogMessageSink,
  Atlas.Common.JsonRpc.TestSupport;

{ TLspLogMessageSinkTests }

procedure TLspLogMessageSinkTests.SendsWindowLogMessage;
var
  mOutput: TBytesStream;
  mSink: ILogSink;
  mMessages: TObjectList<TJSONObject>;
begin
  mOutput := TBytesStream.Create;
  try
    mSink := TLspLogMessageSink.Create(TJsonRpcStreamTransport.Create(nil, mOutput, False));
    mSink.Write(TLogEntry.Create(Now, TLogLevel.Warning, 'Achtung'));
    mSink := nil;

    mMessages := TJsonRpcTestSupport.ReadMessages(mOutput);
    try
      Assert.AreEqual<NativeInt>(1, mMessages.Count);
      Assert.AreEqual('window/logMessage', mMessages[0].GetValue<string>('method'));
      Assert.IsNull(mMessages[0].GetValue('id'));
      Assert.AreEqual(2, mMessages[0].GetValue<Integer>('params.type'));
      Assert.AreEqual('Achtung', mMessages[0].GetValue<string>('params.message'));
    finally
      mMessages.Free;
    end;
  finally
    mOutput.Free;
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
