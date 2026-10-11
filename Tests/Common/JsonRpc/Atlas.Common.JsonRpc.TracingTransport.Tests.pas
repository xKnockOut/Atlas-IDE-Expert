unit Atlas.Common.JsonRpc.TracingTransport.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcTracingTransportTests = class
  public
    [Test]
    procedure RecordsIncomingAndOutgoingMessages;
    [Test]
    procedure PassesClosedInputThroughWithoutTrace;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.JsonRpc.TestSupport;

{ TJsonRpcTracingTransportTests }

procedure TJsonRpcTracingTransportTests.RecordsIncomingAndOutgoingMessages;
var
  Input, Output, Trace: TBytesStream;
  Transport: IJsonRpcTransport;
  Incoming, Outgoing: TJSONObject;
  Lines: TArray<string>;
  Written: TObjectList<TJSONObject>;
begin
  Input := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"initialize"}']);
  Output := TBytesStream.Create;
  Trace := TBytesStream.Create;
  try
    Transport := TJsonRpcTracingTransport.Create(
      TJsonRpcStreamTransport.Create(Input, Output, False), Trace, False);

    Incoming := Transport.ReadMessage;
    try
      Assert.AreEqual('initialize', Incoming.GetValue<string>('method'));
    finally
      Incoming.Free;
    end;

    Outgoing := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":1,"result":null}');
    try
      Transport.WriteMessage(Outgoing);
    finally
      Outgoing.Free;
    end;
    Transport := nil;

    Lines := TEncoding.UTF8.GetString(Trace.Bytes, 0, Integer(Trace.Size)).Split([sLineBreak],
      TStringSplitOptions.ExcludeEmpty);
    Assert.AreEqual<NativeInt>(2, Length(Lines));
    Assert.Contains(Lines[0], TJsonRpcTracingTransport.IncomingMarker + ' {');
    Assert.Contains(Lines[0], '"initialize"');
    Assert.Contains(Lines[1], TJsonRpcTracingTransport.OutgoingMarker + ' {');

    // Die Nachricht muss trotzdem beim Client ankommen.
    Written := TJsonRpcTestSupport.ReadMessages(Output);
    try
      Assert.AreEqual<NativeInt>(1, Written.Count);
    finally
      Written.Free;
    end;
  finally
    Trace.Free;
    Output.Free;
    Input.Free;
  end;
end;

procedure TJsonRpcTracingTransportTests.PassesClosedInputThroughWithoutTrace;
var
  Input, Trace: TBytesStream;
  Transport: IJsonRpcTransport;
begin
  Input := TJsonRpcTestSupport.RawInput('');
  Trace := TBytesStream.Create;
  try
    Transport := TJsonRpcTracingTransport.Create(
      TJsonRpcStreamTransport.Create(Input, nil, False), Trace, False);
    Assert.WillRaise(
      procedure
      begin
        Transport.ReadMessage.Free;
      end, EJsonRpcTransportClosed);
    Transport := nil;
    Assert.AreEqual<Int64>(0, Trace.Size);
  finally
    Trace.Free;
    Input.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcTracingTransportTests);

end.
