unit Atlas.Core.Lsp.Framing.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFrameReaderTests = class
  public
    [Test]
    procedure FrameWritesContentLengthInBytes;
    [Test]
    procedure TakesMessageFromPieces;
    [Test]
    procedure TakesTwoMessagesFromOneChunk;
    [Test]
    procedure DropsHeaderWithoutContentLength;
    [Test]
    procedure RejectsHeaderWithoutEnd;
    [Test]
    procedure RejectsOversizedContent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Framing;

/// <summary>Hängt AText (UTF-8) an den Leser.</summary>
procedure AppendText(AReader: TLspFrameReader; const AText: string);
var
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes(AText);
  AReader.Append(mBytes, Length(mBytes));
end;

procedure TLspFrameReaderTests.FrameWritesContentLengthInBytes;
begin
  // „ä“ sind zwei Bytes in UTF-8: Die Länge zählt Bytes, nicht Zeichen.
  Assert.AreEqual('Content-Length: 5'#13#10#13#10'{"ä}',
    TEncoding.UTF8.GetString(TLspFrameReader.Frame('{"ä}')));
end;

procedure TLspFrameReaderTests.TakesMessageFromPieces;
var
  mReader: TLspFrameReader;
  mText: string;
begin
  mReader := TLspFrameReader.Create;
  try
    AppendText(mReader, 'Content-Len');
    Assert.IsFalse(mReader.TakeMessage(mText));
    AppendText(mReader, 'gth: 7'#13#10#13#10'{"a"');
    Assert.IsFalse(mReader.TakeMessage(mText));
    AppendText(mReader, ':1}');
    Assert.IsTrue(mReader.TakeMessage(mText));
    Assert.AreEqual('{"a":1}', mText);
    Assert.IsFalse(mReader.TakeMessage(mText));
  finally
    mReader.Free;
  end;
end;

procedure TLspFrameReaderTests.TakesTwoMessagesFromOneChunk;
var
  mReader: TLspFrameReader;
  mBytes: TBytes;
  mText: string;
begin
  mReader := TLspFrameReader.Create;
  try
    mBytes := TLspFrameReader.Frame('[1]') + TLspFrameReader.Frame('[22]');
    mReader.Append(mBytes, Length(mBytes));
    Assert.IsTrue(mReader.TakeMessage(mText));
    Assert.AreEqual('[1]', mText);
    Assert.IsTrue(mReader.TakeMessage(mText));
    Assert.AreEqual('[22]', mText);
    Assert.IsFalse(mReader.TakeMessage(mText));
  finally
    mReader.Free;
  end;
end;

procedure TLspFrameReaderTests.DropsHeaderWithoutContentLength;
var
  mReader: TLspFrameReader;
  mText: string;
begin
  mReader := TLspFrameReader.Create;
  try
    AppendText(mReader, 'X-Kaputt: ja'#13#10#13#10);
    mReader.Append(TLspFrameReader.Frame('{}'), Length(TLspFrameReader.Frame('{}')));
    // Erst der kaputte Kopf (verworfen, ohne Text), dann die Nachricht dahinter.
    Assert.IsTrue(mReader.TakeMessage(mText));
    Assert.AreEqual('', mText);
    Assert.IsTrue(mReader.TakeMessage(mText));
    Assert.AreEqual('{}', mText);
  finally
    mReader.Free;
  end;
end;

procedure TLspFrameReaderTests.RejectsHeaderWithoutEnd;
var
  mReader: TLspFrameReader;
  mText: string;
begin
  mReader := TLspFrameReader.Create;
  try
    AppendText(mReader, StringOfChar('x', TLspFrameReader.cMaxHeaderLength + 4));
    Assert.WillRaise(
      procedure
      begin
        mReader.TakeMessage(mText);
      end, ELspClientError);
    // Der Puffer ist danach leer: Neue Nachrichten gehen wieder.
    mReader.Append(TLspFrameReader.Frame('{}'), Length(TLspFrameReader.Frame('{}')));
    Assert.IsTrue(mReader.TakeMessage(mText));
    Assert.AreEqual('{}', mText);
  finally
    mReader.Free;
  end;
end;

procedure TLspFrameReaderTests.RejectsOversizedContent;
var
  mReader: TLspFrameReader;
  mText: string;
begin
  mReader := TLspFrameReader.Create;
  try
    AppendText(mReader, Format('Content-Length: %d'#13#10#13#10'{', [TLspFrameReader.cMaxContentLength + 1]));
    Assert.WillRaise(
      procedure
      begin
        mReader.TakeMessage(mText);
      end, ELspClientError);
  finally
    mReader.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFrameReaderTests);

end.
