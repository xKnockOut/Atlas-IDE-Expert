unit Atlas.Core.Assistants.LinkFrames.Tests;

// Assistenten-Kopplung (#2377): Handschlag (Schlüssel nach RFC 6455, Token, Origin) und Rahmen (maskiert,
// geteilt, stückweise geliefert, Steuerrahmen, Längenformen, Grenzen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasLinkFramesTests = class
  public
    [Test]
    procedure AcceptKeyMatchesRfc;
    [Test]
    procedure HeaderEndsAtBlankLine;
    [Test]
    procedure HandshakeNeedsToken;
    [Test]
    procedure HandshakeRefusesBrowsers;
    [Test]
    procedure HandshakeNeedsUpgrade;
    [Test]
    procedure ResponseCarriesAccept;
    [Test]
    procedure ReadsMaskedText;
    [Test]
    procedure ReadsFragmentsAndBytewise;
    [Test]
    procedure RefusesUnmaskedFrames;
    [Test]
    procedure PingAndClose;
    [Test]
    procedure RefusesHugeMessages;
    [Test]
    procedure WriterUsesLengthForms;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Assistants.LinkFrames;

const
  cHeader = 'x-test-token';
  cMask: array[0..3] of Byte = ($37, $FA, $21, $3D);

/// <summary>Rahmen des Clients (maskiert) mit AOpcode und AText.</summary>
function ClientFrame(AOpcode: Byte; const AText: string; AFin: Boolean): TBytes;
var
  mPayload: TBytes;
  mIndex: Integer;
  mHead: Integer;
begin
  mPayload := TEncoding.UTF8.GetBytes(AText);
  mHead := 2;
  if Length(mPayload) >= 126 then
  begin
    mHead := 4;
  end;
  Result := nil;
  SetLength(Result, mHead + 4 + Length(mPayload));
  Result[0] := AOpcode;
  if AFin then
  begin
    Result[0] := Result[0] or $80;
  end;
  if mHead = 2 then
  begin
    Result[1] := $80 or Length(mPayload);
  end
  else
  begin
    Result[1] := $80 or 126;
    Result[2] := Byte(Length(mPayload) shr 8);
    Result[3] := Byte(Length(mPayload));
  end;
  for mIndex := 0 to 3 do
  begin
    Result[mHead + mIndex] := cMask[mIndex];
  end;
  for mIndex := 0 to High(mPayload) do
  begin
    Result[mHead + 4 + mIndex] := mPayload[mIndex] xor cMask[mIndex mod 4];
  end;
end;

function Request(const AExtra: string): string;
begin
  Result := 'GET / HTTP/1.1'#13#10'Host: 127.0.0.1:12345'#13#10'Upgrade: websocket'#13#10 +
    'Connection: Upgrade'#13#10'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=='#13#10 +
    'Sec-WebSocket-Version: 13'#13#10 + AExtra + #13#10;
end;

procedure TAtlasLinkFramesTests.AcceptKeyMatchesRfc;
begin
  Assert.AreEqual('s3pPLMBiTxaQ9kYGzzhZRbK+xOo=', TAtlasLinkHandshake.AcceptOf('dGhlIHNhbXBsZSBub25jZQ=='));
end;

procedure TAtlasLinkFramesTests.HeaderEndsAtBlankLine;
var
  mBytes: TBytes;
begin
  mBytes := TEncoding.ASCII.GetBytes('GET / HTTP/1.1'#13#10'A: b'#13#10#13#10'xyz');
  Assert.AreEqual(Integer(Length(mBytes) - 3), Integer(TAtlasLinkHandshake.HeaderLength(mBytes, Length(mBytes))));
  Assert.AreEqual(0, TAtlasLinkHandshake.HeaderLength(mBytes, 10), 'unvollständig');
end;

procedure TAtlasLinkFramesTests.HandshakeNeedsToken;
var
  mHandshake: TAtlasLinkHandshake;
  mReason: string;
begin
  mHandshake := TAtlasLinkHandshake.Parse(Request('X-Test-Token: geheim'#13#10), cHeader);
  Assert.AreEqual('geheim', mHandshake.Token, 'Kopfname ohne Groß-/Kleinschreibung');
  Assert.IsTrue(mHandshake.Admits('geheim', mReason), mReason);
  Assert.IsFalse(mHandshake.Admits('anders', mReason));
  Assert.AreEqual('invalid token', mReason);
  mHandshake := TAtlasLinkHandshake.Parse(Request(''), cHeader);
  Assert.IsFalse(mHandshake.Admits('geheim', mReason), 'ohne Token');
  Assert.IsFalse(mHandshake.Admits('', mReason), 'leeres Token gilt nie');
end;

procedure TAtlasLinkFramesTests.HandshakeRefusesBrowsers;
var
  mHandshake: TAtlasLinkHandshake;
  mReason: string;
begin
  mHandshake := TAtlasLinkHandshake.Parse(Request('x-test-token: geheim'#13#10'Origin: https://example.com'#13#10),
    cHeader);
  Assert.IsFalse(mHandshake.Admits('geheim', mReason));
  Assert.AreEqual('origin not allowed', mReason);
end;

procedure TAtlasLinkFramesTests.HandshakeNeedsUpgrade;
var
  mHandshake: TAtlasLinkHandshake;
  mReason: string;
begin
  mHandshake := TAtlasLinkHandshake.Parse('GET / HTTP/1.1'#13#10'x-test-token: geheim'#13#10#13#10, cHeader);
  Assert.IsFalse(mHandshake.Admits('geheim', mReason));
  Assert.AreEqual('no websocket upgrade', mReason);
end;

procedure TAtlasLinkFramesTests.ResponseCarriesAccept;
var
  mHandshake: TAtlasLinkHandshake;
begin
  mHandshake := TAtlasLinkHandshake.Parse(Request(''), cHeader);
  Assert.StartsWith('HTTP/1.1 101 ', mHandshake.Response);
  Assert.IsTrue(Pos('Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo='#13#10, mHandshake.Response) > 0);
  Assert.StartsWith('HTTP/1.1 401 Unauthorized', TAtlasLinkHandshake.Refusal(401, 'invalid token'));
end;

procedure TAtlasLinkFramesTests.ReadsMaskedText;
var
  mReader: TAtlasLinkReader;
  mFrame: TBytes;
  mEvent: TAtlasLinkEvent;
begin
  mReader := TAtlasLinkReader.Create;
  try
    mFrame := ClientFrame(TAtlasLinkReader.cOpText, 'Hello', True);
    Assert.AreEqual(11, Integer(Length(mFrame)));
    Assert.AreEqual($7F, Integer(mFrame[6]), 'Beispiel aus RFC 6455');
    mReader.Feed(mFrame, Length(mFrame));
    mEvent := mReader.Next;
    Assert.AreEqual(Ord(TAtlasLinkEventKind.Text), Ord(mEvent.Kind));
    Assert.AreEqual('Hello', mEvent.Text);
    Assert.AreEqual(Ord(TAtlasLinkEventKind.None), Ord(mReader.Next.Kind));
  finally
    mReader.Free;
  end;
end;

procedure TAtlasLinkFramesTests.ReadsFragmentsAndBytewise;
var
  mReader: TAtlasLinkReader;
  mBytes: TBytes;
  mIndex: Integer;
  mEvent: TAtlasLinkEvent;
  mLong: string;
begin
  // Char(...): sonst nimmt Delphi die AnsiChar-Fassung (W1057).
  mLong := StringOfChar(Char('ä'), 200);
  mReader := TAtlasLinkReader.Create;
  try
    mBytes := ClientFrame(TAtlasLinkReader.cOpText, '{"a":', False) +
      ClientFrame(TAtlasLinkReader.cOpPing, '', True) +
      ClientFrame(TAtlasLinkReader.cOpContinuation, '"' + mLong + '"}', True);
    mEvent := Default(TAtlasLinkEvent);
    for mIndex := 0 to High(mBytes) do
    begin
      mReader.Feed(Copy(mBytes, mIndex, 1), 1);
      mEvent := mReader.Next;
      if mEvent.Kind = TAtlasLinkEventKind.Ping then
      begin
        mEvent := mReader.Next;
      end;
      if mEvent.Kind <> TAtlasLinkEventKind.None then
      begin
        Assert.AreEqual(Integer(High(mBytes)), mIndex, 'erst mit dem letzten Byte');
      end;
    end;
    Assert.AreEqual(Ord(TAtlasLinkEventKind.Text), Ord(mEvent.Kind));
    Assert.AreEqual('{"a":"' + mLong + '"}', mEvent.Text);
  finally
    mReader.Free;
  end;
end;

procedure TAtlasLinkFramesTests.RefusesUnmaskedFrames;
var
  mReader: TAtlasLinkReader;
  mFrame: TBytes;
begin
  mReader := TAtlasLinkReader.Create;
  try
    mFrame := TAtlasLinkWriter.Text('Hello');
    mReader.Feed(mFrame, Length(mFrame));
    Assert.AreEqual(Ord(TAtlasLinkEventKind.Error), Ord(mReader.Next.Kind));
    Assert.IsTrue(mReader.Done);
  finally
    mReader.Free;
  end;
end;

procedure TAtlasLinkFramesTests.PingAndClose;
var
  mReader: TAtlasLinkReader;
  mBytes: TBytes;
  mEvent: TAtlasLinkEvent;
begin
  mReader := TAtlasLinkReader.Create;
  try
    mBytes := ClientFrame(TAtlasLinkReader.cOpPing, 'hi', True) + ClientFrame(TAtlasLinkReader.cOpClose, '', True) +
      ClientFrame(TAtlasLinkReader.cOpText, 'danach', True);
    mReader.Feed(mBytes, Length(mBytes));
    mEvent := mReader.Next;
    Assert.AreEqual(Ord(TAtlasLinkEventKind.Ping), Ord(mEvent.Kind));
    Assert.AreEqual('hi', TEncoding.UTF8.GetString(mEvent.Payload));
    Assert.AreEqual(Ord(TAtlasLinkEventKind.Close), Ord(mReader.Next.Kind));
    Assert.AreEqual(Ord(TAtlasLinkEventKind.None), Ord(mReader.Next.Kind), 'nach Close nichts mehr');
  finally
    mReader.Free;
  end;
end;

procedure TAtlasLinkFramesTests.RefusesHugeMessages;
var
  mReader: TAtlasLinkReader;
  mFrame: TBytes;
  mEvent: TAtlasLinkEvent;
begin
  mReader := TAtlasLinkReader.Create;
  try
    mFrame := TBytes.Create($81, $80 or 127, 0, 0, 0, 1, 0, 0, 0, 0);
    mReader.Feed(mFrame, Length(mFrame));
    mEvent := mReader.Next;
    Assert.AreEqual(Ord(TAtlasLinkEventKind.Error), Ord(mEvent.Kind));
    Assert.AreEqual('message too big', mEvent.Text);
  finally
    mReader.Free;
  end;
end;

procedure TAtlasLinkFramesTests.WriterUsesLengthForms;
var
  mFrame: TBytes;
begin
  mFrame := TAtlasLinkWriter.Text('Hello');
  Assert.AreEqual(7, Integer(Length(mFrame)));
  Assert.AreEqual($81, Integer(mFrame[0]));
  Assert.AreEqual(5, Integer(mFrame[1]));
  mFrame := TAtlasLinkWriter.Text(StringOfChar('x', 200));
  Assert.AreEqual(126, Integer(mFrame[1]));
  Assert.AreEqual(204, Integer(Length(mFrame)));
  mFrame := TAtlasLinkWriter.Text(StringOfChar('x', 70000));
  Assert.AreEqual(127, Integer(mFrame[1]));
  Assert.AreEqual(70010, Integer(Length(mFrame)));
  mFrame := TAtlasLinkWriter.Close(TAtlasLinkWriter.cCloseNormal);
  Assert.AreEqual($88, Integer(mFrame[0]));
  Assert.AreEqual($03, Integer(mFrame[2]));
  Assert.AreEqual($E8, Integer(mFrame[3]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkFramesTests);

end.
