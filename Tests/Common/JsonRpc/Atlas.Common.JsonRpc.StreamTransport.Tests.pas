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
  mMessage: TJSONObject;
begin
  Result := 0;
  try
    mMessage := ATransport.ReadMessage;
    mMessage.Free;
  except
    on E: EJsonRpcError do
      Result := E.Code;
  end;
end;

{ TJsonRpcStreamTransportTests }

procedure TJsonRpcStreamTransportTests.ReadsSingleMessage;
var
  mInput: TBytesStream;
  mMessage: TJSONObject;
begin
  mInput := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"initialize"}']);
  try
    mMessage := TransportOn(mInput).ReadMessage;
    try
      Assert.AreEqual('initialize', mMessage.GetValue<string>('method'));
      Assert.AreEqual(1, mMessage.GetValue<Integer>('id'));
    finally
      mMessage.Free;
    end;
  finally
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.ReadsConsecutiveMessages;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
  mFirst, mSecond: TJSONObject;
begin
  mInput := TJsonRpcTestSupport.InputOf([
    '{"jsonrpc":"2.0","id":1,"method":"a"}',
    '{"jsonrpc":"2.0","method":"b"}']);
  try
    mTransport := TransportOn(mInput);
    mFirst := mTransport.ReadMessage;
    mSecond := mTransport.ReadMessage;
    try
      Assert.AreEqual('a', mFirst.GetValue<string>('method'));
      Assert.AreEqual('b', mSecond.GetValue<string>('method'));
    finally
      mFirst.Free;
      mSecond.Free;
    end;
    Assert.WillRaise(
      procedure
      begin
        mTransport.ReadMessage.Free;
      end, EJsonRpcTransportClosed);
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.IgnoresAdditionalHeaders;
var
  mInput: TBytesStream;
  mMessage: TJSONObject;
begin
  mInput := TJsonRpcTestSupport.RawInput(
    'Content-Type: application/vscode-jsonrpc; charset=utf-8'#13#10 +
    'Content-Length: 14'#13#10#13#10 +
    '{"method":"x"}');
  try
    mMessage := TransportOn(mInput).ReadMessage;
    try
      Assert.AreEqual('x', mMessage.GetValue<string>('method'));
    finally
      mMessage.Free;
    end;
  finally
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.AcceptsLineFeedWithoutCarriageReturn;
var
  mInput: TBytesStream;
  mMessage: TJSONObject;
begin
  mInput := TJsonRpcTestSupport.RawInput('Content-Length: 14'#10#10'{"method":"x"}');
  try
    mMessage := TransportOn(mInput).ReadMessage;
    try
      Assert.AreEqual('x', mMessage.GetValue<string>('method'));
    finally
      mMessage.Free;
    end;
  finally
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.CountsContentLengthInUtf8Bytes;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
  mFirst, mSecond: TJSONObject;
begin
  // Umlaute belegen in UTF-8 zwei Bytes; die nächste Nachricht muss trotzdem passen.
  mInput := TJsonRpcTestSupport.InputOf([
    '{"method":"Größe"}',
    '{"method":"Übersicht"}']);
  try
    mTransport := TransportOn(mInput);
    mFirst := mTransport.ReadMessage;
    mSecond := mTransport.ReadMessage;
    try
      Assert.AreEqual('Größe', mFirst.GetValue<string>('method'));
      Assert.AreEqual('Übersicht', mSecond.GetValue<string>('method'));
    finally
      mFirst.Free;
      mSecond.Free;
    end;
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.ReadsMessageLargerThanBuffer;
var
  mInput: TBytesStream;
  mText: string;
  mMessage: TJSONObject;
begin
  mText := StringOfChar('a', 200000);
  mInput := TJsonRpcTestSupport.InputOf(['{"method":"x","params":"' + mText + '"}']);
  try
    mMessage := TransportOn(mInput).ReadMessage;
    try
      Assert.AreEqual(mText, mMessage.GetValue<string>('params'));
    finally
      mMessage.Free;
    end;
  finally
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesClosedOnEmptyInput;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
begin
  mInput := TJsonRpcTestSupport.RawInput('');
  try
    mTransport := TransportOn(mInput);
    Assert.WillRaise(
      procedure
      begin
        mTransport.ReadMessage.Free;
      end, EJsonRpcTransportClosed);
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesTransportErrorWithoutContentLength;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
begin
  mInput := TJsonRpcTestSupport.RawInput('Content-Type: text/plain'#13#10#13#10'{}');
  try
    mTransport := TransportOn(mInput);
    Assert.WillRaise(
      procedure
      begin
        mTransport.ReadMessage.Free;
      end, EJsonRpcTransportError);
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesTransportErrorOnInvalidContentLength;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
begin
  mInput := TJsonRpcTestSupport.RawInput('Content-Length: abc'#13#10#13#10'{}');
  try
    mTransport := TransportOn(mInput);
    Assert.WillRaise(
      procedure
      begin
        mTransport.ReadMessage.Free;
      end, EJsonRpcTransportError);
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesTransportErrorOnTruncatedBody;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
begin
  mInput := TJsonRpcTestSupport.RawInput('Content-Length: 100'#13#10#13#10'{"method":"x"}');
  try
    mTransport := TransportOn(mInput);
    Assert.WillRaise(
      procedure
      begin
        mTransport.ReadMessage.Free;
      end, EJsonRpcTransportError);
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesParseErrorOnInvalidJsonAndContinues;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
  mMessage: TJSONObject;
begin
  mInput := TJsonRpcTestSupport.InputOf(['{kein json', '{"method":"x"}']);
  try
    mTransport := TransportOn(mInput);
    Assert.AreEqual(TJsonRpcErrorCode.cParseError, ErrorCodeOf(mTransport));
    mMessage := mTransport.ReadMessage;
    try
      Assert.AreEqual('x', mMessage.GetValue<string>('method'));
    finally
      mMessage.Free;
    end;
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.RaisesInvalidRequestOnJsonArray;
var
  mInput: TBytesStream;
  mTransport: IJsonRpcTransport;
begin
  mInput := TJsonRpcTestSupport.InputOf(['[1,2,3]']);
  try
    mTransport := TransportOn(mInput);
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidRequest, ErrorCodeOf(mTransport));
  finally
    mTransport := nil;
    mInput.Free;
  end;
end;

procedure TJsonRpcStreamTransportTests.WritesHeaderWithUtf8ByteLength;
var
  mOutput: TBytesStream;
  mTransport: IJsonRpcTransport;
  mMessage: TJSONObject;
  mWritten: string;
  mHeaderEnd: Integer;
  mBody: TBytes;
  mMessages: TObjectList<TJSONObject>;
begin
  mOutput := TBytesStream.Create;
  try
    mTransport := TJsonRpcStreamTransport.Create(nil, mOutput, False);
    mMessage := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","method":"Größe"}');
    try
      mTransport.WriteMessage(mMessage);
    finally
      mMessage.Free;
    end;
    mTransport := nil;

    mWritten := TEncoding.UTF8.GetString(mOutput.Bytes, 0, Integer(mOutput.Size));
    mHeaderEnd := mWritten.IndexOf(#13#10#13#10);
    Assert.IsTrue(mHeaderEnd > 0, 'Header muss mit Leerzeile enden');
    mBody := TEncoding.UTF8.GetBytes(mWritten.Substring(mHeaderEnd + 4));
    Assert.AreEqual(Format('Content-Length: %d', [Length(mBody)]), mWritten.Substring(0, mHeaderEnd));

    mMessages := TJsonRpcTestSupport.ReadMessages(mOutput);
    try
      Assert.AreEqual<NativeInt>(1, mMessages.Count);
      Assert.AreEqual('Größe', mMessages[0].GetValue<string>('method'));
    finally
      mMessages.Free;
    end;
  finally
    mOutput.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcStreamTransportTests);

end.
