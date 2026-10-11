unit Atlas.Common.JsonRpc.StreamTransport.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcStreamTransportTests = class
  public
    [Test]
    procedure ReadsSingleMessage;
    [Test]
    procedure ReadsConsecutiveMessages;
    [Test]
    procedure IgnoresAdditionalHeaders;
    [Test]
    procedure AcceptsLineFeedWithoutCarriageReturn;
    [Test]
    procedure CountsContentLengthInUtf8Bytes;
    [Test]
    procedure ReadsMessageLargerThanBuffer;
    [Test]
    procedure RaisesClosedOnEmptyInput;
    [Test]
    procedure RaisesTransportErrorWithoutContentLength;
    [Test]
    procedure RaisesTransportErrorOnInvalidContentLength;
    [Test]
    procedure RaisesTransportErrorOnTruncatedBody;
    [Test]
    procedure RaisesParseErrorOnInvalidJsonAndContinues;
    [Test]
    procedure RaisesInvalidRequestOnJsonArray;
    [Test]
    procedure WritesHeaderWithUtf8ByteLength;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.JsonRpc.TestSupport;

function TransportOn(AInput: TStream): IJsonRpcTransport;
begin
  // Der Transport übernimmt den Eingabestream; geschrieben wird hier nicht.
  Result := TJsonRpcStreamTransport.Create(AInput, nil, False);
end;

function ErrorCodeOf(const ATransport: IJsonRpcTransport): Integer;
var
  Message: TJSONObject;
begin
  Result := 0;
  try
    Message := ATransport.ReadMessage;
    Message.Free;
  except
    on E: EJsonRpcError do
      Result := E.Code;
  end;
end;

{ TJsonRpcStreamTransportTests }

procedure TJsonRpcStreamTransportTests.ReadsSingleMessage;
var
  Input: TBytesStream;
  Message: TJSONObject;
begin
  Input := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"initialize"}']);
  try
    Message := TransportOn(Input).ReadMessage;
    try
      Assert.AreEqual('initialize', Message.GetValue<string>('method'));
      Assert.AreEqual(1, Message.GetValue<Integer>('id'));
    finally
      Message.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.ReadsConsecutiveMessages;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
  First, Second: TJSONObject;
begin
  Input := TJsonRpcTestSupport.InputOf([
    '{"jsonrpc":"2.0","id":1,"method":"a"}',
    '{"jsonrpc":"2.0","method":"b"}']);
  try
    Transport := TransportOn(Input);
    First := Transport.ReadMessage;
    Second := Transport.ReadMessage;
    try
      Assert.AreEqual('a', First.GetValue<string>('method'));
      Assert.AreEqual('b', Second.GetValue<string>('method'));
    finally
      First.Free;
      Second.Free;
    end;
    Assert.WillRaise(
      procedure
      begin
        Transport.ReadMessage.Free;
      end, EJsonRpcTransportClosed);
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.IgnoresAdditionalHeaders;
var
  Input: TBytesStream;
  Message: TJSONObject;
begin
  Input := TJsonRpcTestSupport.RawInput(
    'Content-Type: application/vscode-jsonrpc; charset=utf-8'#13#10 +
    'Content-Length: 14'#13#10#13#10 +
    '{"method":"x"}');
  try
    Message := TransportOn(Input).ReadMessage;
    try
      Assert.AreEqual('x', Message.GetValue<string>('method'));
    finally
      Message.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.AcceptsLineFeedWithoutCarriageReturn;
var
  Input: TBytesStream;
  Message: TJSONObject;
begin
  Input := TJsonRpcTestSupport.RawInput('Content-Length: 14'#10#10'{"method":"x"}');
  try
    Message := TransportOn(Input).ReadMessage;
    try
      Assert.AreEqual('x', Message.GetValue<string>('method'));
    finally
      Message.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.CountsContentLengthInUtf8Bytes;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
  First, Second: TJSONObject;
begin
  // Umlaute belegen in UTF-8 zwei Bytes; die nächste Nachricht muss trotzdem passen.
  Input := TJsonRpcTestSupport.InputOf([
    '{"method":"Größe"}',
    '{"method":"Übersicht"}']);
  try
    Transport := TransportOn(Input);
    First := Transport.ReadMessage;
    Second := Transport.ReadMessage;
    try
      Assert.AreEqual('Größe', First.GetValue<string>('method'));
      Assert.AreEqual('Übersicht', Second.GetValue<string>('method'));
    finally
      First.Free;
      Second.Free;
    end;
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.ReadsMessageLargerThanBuffer;
var
  Input: TBytesStream;
  Text: string;
  Message: TJSONObject;
begin
  Text := StringOfChar('a', 200000);
  Input := TJsonRpcTestSupport.InputOf(['{"method":"x","params":"' + Text + '"}']);
  try
    Message := TransportOn(Input).ReadMessage;
    try
      Assert.AreEqual(Text, Message.GetValue<string>('params'));
    finally
      Message.Free;
    end;
  finally
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesClosedOnEmptyInput;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
begin
  Input := TJsonRpcTestSupport.RawInput('');
  try
    Transport := TransportOn(Input);
    Assert.WillRaise(
      procedure
      begin
        Transport.ReadMessage.Free;
      end, EJsonRpcTransportClosed);
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesTransportErrorWithoutContentLength;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
begin
  Input := TJsonRpcTestSupport.RawInput('Content-Type: text/plain'#13#10#13#10'{}');
  try
    Transport := TransportOn(Input);
    Assert.WillRaise(
      procedure
      begin
        Transport.ReadMessage.Free;
      end, EJsonRpcTransportError);
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesTransportErrorOnInvalidContentLength;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
begin
  Input := TJsonRpcTestSupport.RawInput('Content-Length: abc'#13#10#13#10'{}');
  try
    Transport := TransportOn(Input);
    Assert.WillRaise(
      procedure
      begin
        Transport.ReadMessage.Free;
      end, EJsonRpcTransportError);
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesTransportErrorOnTruncatedBody;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
begin
  Input := TJsonRpcTestSupport.RawInput('Content-Length: 100'#13#10#13#10'{"method":"x"}');
  try
    Transport := TransportOn(Input);
    Assert.WillRaise(
      procedure
      begin
        Transport.ReadMessage.Free;
      end, EJsonRpcTransportError);
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesParseErrorOnInvalidJsonAndContinues;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
  Message: TJSONObject;
begin
  Input := TJsonRpcTestSupport.InputOf(['{kein json', '{"method":"x"}']);
  try
    Transport := TransportOn(Input);
    Assert.AreEqual(TJsonRpcErrorCode.ParseError, ErrorCodeOf(Transport));
    Message := Transport.ReadMessage;
    try
      Assert.AreEqual('x', Message.GetValue<string>('method'));
    finally
      Message.Free;
    end;
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesInvalidRequestOnJsonArray;
var
  Input: TBytesStream;
  Transport: IJsonRpcTransport;
begin
  Input := TJsonRpcTestSupport.InputOf(['[1,2,3]']);
  try
    Transport := TransportOn(Input);
    Assert.AreEqual(TJsonRpcErrorCode.InvalidRequest, ErrorCodeOf(Transport));
  finally
    Transport := nil;
    Input.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.WritesHeaderWithUtf8ByteLength;
var
  Output: TBytesStream;
  Transport: IJsonRpcTransport;
  Message: TJSONObject;
  Written: string;
  HeaderEnd: Integer;
  Body: TBytes;
  Messages: TObjectList<TJSONObject>;
begin
  Output := TBytesStream.Create;
  try
    Transport := TJsonRpcStreamTransport.Create(nil, Output, False);
    Message := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","method":"Größe"}');
    try
      Transport.WriteMessage(Message);
    finally
      Message.Free;
    end;
    Transport := nil;

    Written := TEncoding.UTF8.GetString(Output.Bytes, 0, Integer(Output.Size));
    HeaderEnd := Written.IndexOf(#13#10#13#10);
    Assert.IsTrue(HeaderEnd > 0, 'Header muss mit Leerzeile enden');
    Body := TEncoding.UTF8.GetBytes(Written.Substring(HeaderEnd + 4));
    Assert.AreEqual(Format('Content-Length: %d', [Length(Body)]), Written.Substring(0, HeaderEnd));

    Messages := TJsonRpcTestSupport.ReadMessages(Output);
    try
      Assert.AreEqual<NativeInt>(1, Messages.Count);
      Assert.AreEqual('Größe', Messages[0].GetValue<string>('method'));
    finally
      Messages.Free;
    end;
  finally
    Output.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcStreamTransportTests);

end.
