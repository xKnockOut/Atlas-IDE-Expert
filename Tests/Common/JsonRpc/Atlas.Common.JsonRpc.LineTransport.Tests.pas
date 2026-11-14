unit Atlas.Common.JsonRpc.LineTransport.Tests;

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
  System.Generics.Collections,
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.LineTransport,
  Atlas.Common.JsonRpc.TestSupport;

function TransportOn(const AText: string): IJsonRpcTransport;
begin
  // Der Transport gibt den Eingabestream frei (Ausgabe ist nil).
  Result := TJsonRpcLineTransport.Create(TJsonRpcTestSupport.RawInput(AText), nil, True);
end;

function ReadId(const ATransport: IJsonRpcTransport): Integer;
var
  mMessage: TJSONObject;
begin
  mMessage := ATransport.ReadMessage;
  try
    Result := mMessage.GetValue<Integer>('id');
  finally
    mMessage.Free;
  end;
end;

procedure TJsonRpcLineTransportTests.ReadsOneMessagePerLine;
var
  mTransport: IJsonRpcTransport;
begin
  mTransport := TransportOn('{"jsonrpc":"2.0","id":1,"method":"a"}'#10'{"jsonrpc":"2.0","id":2,"method":"b"}'#10);
  Assert.AreEqual(1, ReadId(mTransport));
  Assert.AreEqual(2, ReadId(mTransport));
end;

procedure TJsonRpcLineTransportTests.SkipsBlankLinesAndCarriageReturns;
var
  mTransport: IJsonRpcTransport;
begin
  mTransport := TransportOn(#13#10#10'  {"id":7}'#13#10);
  Assert.AreEqual(7, ReadId(mTransport));
end;

procedure TJsonRpcLineTransportTests.ReadsLastLineWithoutLineFeed;
var
  mTransport: IJsonRpcTransport;
begin
  mTransport := TransportOn('{"id":3}');
  Assert.AreEqual(3, ReadId(mTransport));
end;

procedure TJsonRpcLineTransportTests.RaisesClosedAtEnd;
var
  mTransport: IJsonRpcTransport;
begin
  mTransport := TransportOn('{"id":1}'#10#10);
  ReadId(mTransport);
  Assert.WillRaise(
    procedure
    begin
      mTransport.ReadMessage.Free;
    end, EJsonRpcTransportClosed);
end;

procedure TJsonRpcLineTransportTests.RaisesParseErrorOnInvalidLine;
var
  mTransport: IJsonRpcTransport;
  mCode: Integer;
begin
  mTransport := TransportOn('kein json'#10'{"id":5}'#10);
  mCode := 0;
  try
    mTransport.ReadMessage.Free;
  except
    on E: EJsonRpcError do
      mCode := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.cParseError, mCode);
  Assert.AreEqual(5, ReadId(mTransport), 'nach dem Fehler geht es mit der nächsten Zeile weiter');
end;

procedure TJsonRpcLineTransportTests.WritesSingleLineWithEscapedLineBreaks;
var
  mOutput: TBytesStream;
  mTransport: IJsonRpcTransport;
  mMessage, mDecoded: TJSONObject;
  mText, mValue: string;
begin
  mOutput := TBytesStream.Create;
  try
    mTransport := TJsonRpcLineTransport.Create(nil, mOutput, False);
    mMessage := TJSONObject.Create;
    try
      mMessage.AddPair('text', 'a'#10'ä');
      mTransport.WriteMessage(mMessage);
    finally
      mMessage.Free;
    end;
    mText := TEncoding.UTF8.GetString(mOutput.Bytes, 0, mOutput.Size);
    // Eine Zeile mit LF am Ende; der Umbruch im Wert ist maskiert. Nicht-ASCII-Zeichen
    // maskiert ToJSON als \uXXXX, wie beim LSP-Transport.
    Assert.IsTrue(mText.EndsWith(#10));
    Assert.AreEqual(mText.Length - 1, mText.IndexOf(#10), 'nur das abschließende LF');
    Assert.IsTrue(mText.Contains('a\n'), mText);
    mDecoded := TJSONObject.ParseJSONValue(mText.TrimRight) as TJSONObject;
    try
      mValue := mDecoded.GetValue<string>('text');
      Assert.AreEqual('a'#10'ä', mValue);
    finally
      mDecoded.Free;
    end;
  finally
    mTransport := nil;
    mOutput.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcLineTransportTests);

end.
