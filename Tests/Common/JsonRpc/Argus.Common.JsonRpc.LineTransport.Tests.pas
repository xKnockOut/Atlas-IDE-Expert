unit Argus.Common.JsonRpc.LineTransport.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcLineTransportTests = class
  public
    [Test]
    procedure ReadsOneMessagePerLine;
    [Test]
    procedure SkipsBlankLinesAndCarriageReturns;
    [Test]
    procedure ReadsLastLineWithoutLineFeed;
    [Test]
    procedure RaisesClosedAtEnd;
    [Test]
    procedure RaisesParseErrorOnInvalidLine;
    [Test]
    procedure WritesSingleLineWithEscapedLineBreaks;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.JsonRpc.LineTransport,
  Argus.Common.JsonRpc.TestSupport;

function TransportOn(const AText: string): IJsonRpcTransport;
begin
  Result := TJsonRpcLineTransport.Create(TJsonRpcTestSupport.RawInput(AText), nil, False);
end;

function ReadId(const ATransport: IJsonRpcTransport): Integer;
var
  Message: TJSONObject;
begin
  Message := ATransport.ReadMessage;
  try
    Result := Message.GetValue<Integer>('id');
  finally
    Message.Free;
  end;
end;

procedure TJsonRpcLineTransportTests.ReadsOneMessagePerLine;
var
  Transport: IJsonRpcTransport;
begin
  Transport := TransportOn('{"jsonrpc":"2.0","id":1,"method":"a"}'#10'{"jsonrpc":"2.0","id":2,"method":"b"}'#10);
  Assert.AreEqual(1, ReadId(Transport));
  Assert.AreEqual(2, ReadId(Transport));
end;

procedure TJsonRpcLineTransportTests.SkipsBlankLinesAndCarriageReturns;
var
  Transport: IJsonRpcTransport;
begin
  Transport := TransportOn(#13#10#10'  {"id":7}'#13#10);
  Assert.AreEqual(7, ReadId(Transport));
end;

procedure TJsonRpcLineTransportTests.ReadsLastLineWithoutLineFeed;
var
  Transport: IJsonRpcTransport;
begin
  Transport := TransportOn('{"id":3}');
  Assert.AreEqual(3, ReadId(Transport));
end;

procedure TJsonRpcLineTransportTests.RaisesClosedAtEnd;
var
  Transport: IJsonRpcTransport;
begin
  Transport := TransportOn('{"id":1}'#10#10);
  ReadId(Transport);
  Assert.WillRaise(
    procedure
    begin
      Transport.ReadMessage.Free;
    end, EJsonRpcTransportClosed);
end;

procedure TJsonRpcLineTransportTests.RaisesParseErrorOnInvalidLine;
var
  Transport: IJsonRpcTransport;
  Code: Integer;
begin
  Transport := TransportOn('kein json'#10'{"id":5}'#10);
  Code := 0;
  try
    Transport.ReadMessage.Free;
  except
    on E: EJsonRpcError do
      Code := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.ParseError, Code);
  Assert.AreEqual(5, ReadId(Transport), 'nach dem Fehler geht es mit der nächsten Zeile weiter');
end;

procedure TJsonRpcLineTransportTests.WritesSingleLineWithEscapedLineBreaks;
var
  Output: TBytesStream;
  Transport: IJsonRpcTransport;
  Message: TJSONObject;
  Text: string;
begin
  Output := TBytesStream.Create;
  try
    Transport := TJsonRpcLineTransport.Create(nil, Output, False);
    Message := TJSONObject.Create;
    try
      Message.AddPair('text', 'a'#10'ä');
      Transport.WriteMessage(Message);
    finally
      Message.Free;
    end;
    Text := TEncoding.UTF8.GetString(Output.Bytes, 0, Output.Size);
    Assert.AreEqual('{"text":"a\nä"}'#10, Text);
  finally
    Transport := nil;
    Output.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcLineTransportTests);

end.
