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
    /// <summary>Nach dem ersten Schreibfehler kein weiterer Versuch.</summary>
    [Test]
    procedure StopsTracingAfterWriteFailure;
    [Test]
    procedure ReportsWriteFailureOnce;
    /// <summary>#1356: die letzten Zeilen im Speicher für das Diagnosepaket.</summary>
    [Test]
    procedure KeepsRecentLines;
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

type
  /// <summary>Mitschnitt, dessen Schreiben immer scheitert (z. B. Datenträger entfernt).</summary>
  TFailingStream = class(TMemoryStream)
  private
    FWrites: Integer;
  public
    function Write(const Buffer; Count: Longint): Longint; overload; override;
    // Delphi: WriteBuffer(TBytes) läuft über diese Überladungen, nicht über Write(const Buffer; Count).
    {$IFNDEF FPC}
    function Write(const Buffer: TBytes; Offset, Count: Longint): Longint; overload; override;
    function Write64(const Buffer: TBytes; Offset, Count: Int64): Int64; override;
    {$ENDIF}
    property Writes: Integer read FWrites;
  end;

function TFailingStream.Write(const Buffer; Count: Longint): Longint;
begin
  Inc(FWrites);
  raise EWriteError.Create('simuliert');
end;

{$IFNDEF FPC}
function TFailingStream.Write(const Buffer: TBytes; Offset, Count: Longint): Longint;
begin
  Inc(FWrites);
  raise EWriteError.Create('simuliert');
end;

function TFailingStream.Write64(const Buffer: TBytes; Offset, Count: Int64): Int64;
begin
  Inc(FWrites);
  raise EWriteError.Create('simuliert');
end;
{$ENDIF}

/// <summary>Schreibt drei Nachrichten über einen Mitschnitt in AFailing; liefert die beim Client
/// angekommenen Nachrichten.</summary>
function WriteThree(AFailing: TFailingStream; const AOnFailed: TJsonRpcTraceFailedEvent): Integer;
var
  mOutput: TBytesStream;
  mTracing: TJsonRpcTracingTransport;
  mTransport: IJsonRpcTransport;
  mOutgoing: TJSONObject;
  mWritten: TObjectList<TJSONObject>;
  mIndex: Integer;
begin
  mOutput := TBytesStream.Create;
  try
    mTracing := TJsonRpcTracingTransport.Create(TJsonRpcStreamTransport.Create(nil, mOutput, False), AFailing, False);
    mTransport := mTracing;
    mTracing.OnFailed := AOnFailed;
    for mIndex := 1 to 3 do
    begin
      mOutgoing := TJsonRpcTestSupport.Parse(Format('{"jsonrpc":"2.0","id":%d,"result":null}', [mIndex]));
      try
        mTransport.WriteMessage(mOutgoing);
      finally
        mOutgoing.Free;
      end;
    end;
    mTransport := nil;
    mWritten := TJsonRpcTestSupport.ReadMessages(mOutput);
    try
      Result := mWritten.Count;
    finally
      mWritten.Free;
    end;
  finally
    mOutput.Free;
  end;
end;

{ TJsonRpcTracingTransportTests }

procedure TJsonRpcTracingTransportTests.RecordsIncomingAndOutgoingMessages;
var
  mInput, mOutput, mTrace: TBytesStream;
  mTransport: IJsonRpcTransport;
  mIncoming, mOutgoing: TJSONObject;
  mLines: TArray<string>;
  mWritten: TObjectList<TJSONObject>;
begin
  mInput := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"initialize"}']);
  mOutput := TBytesStream.Create;
  mTrace := TBytesStream.Create;
  try
    mTransport := TJsonRpcTracingTransport.Create(
      TJsonRpcStreamTransport.Create(mInput, mOutput, False), mTrace, False);

    mIncoming := mTransport.ReadMessage;
    try
      Assert.AreEqual('initialize', mIncoming.GetValue<string>('method'));
    finally
      mIncoming.Free;
    end;

    mOutgoing := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":1,"result":null}');
    try
      mTransport.WriteMessage(mOutgoing);
    finally
      mOutgoing.Free;
    end;
    mTransport := nil;

    mLines := TEncoding.UTF8.GetString(mTrace.Bytes, 0, Integer(mTrace.Size)).Split([sLineBreak],
      TStringSplitOptions.ExcludeEmpty);
    Assert.AreEqual<NativeInt>(2, Length(mLines));
    Assert.Contains(mLines[0], TJsonRpcTracingTransport.cIncomingMarker + ' {');
    Assert.Contains(mLines[0], '"initialize"');
    Assert.Contains(mLines[1], TJsonRpcTracingTransport.cOutgoingMarker + ' {');

    // Die Nachricht muss trotzdem beim Client ankommen.
    mWritten := TJsonRpcTestSupport.ReadMessages(mOutput);
    try
      Assert.AreEqual<NativeInt>(1, mWritten.Count);
    finally
      mWritten.Free;
    end;
  finally
    mTrace.Free;
    mOutput.Free;
    mInput.Free;
  end;
end;

procedure TJsonRpcTracingTransportTests.PassesClosedInputThroughWithoutTrace;
var
  mInput, mTrace: TBytesStream;
  mTransport: IJsonRpcTransport;
begin
  mInput := TJsonRpcTestSupport.RawInput('');
  mTrace := TBytesStream.Create;
  try
    mTransport := TJsonRpcTracingTransport.Create(
      TJsonRpcStreamTransport.Create(mInput, nil, False), mTrace, False);
    Assert.WillRaise(
      procedure
      begin
        mTransport.ReadMessage.Free;
      end, EJsonRpcTransportClosed);
    mTransport := nil;
    Assert.AreEqual<Int64>(0, mTrace.Size);
  finally
    mTrace.Free;
    mInput.Free;
  end;
end;

procedure TJsonRpcTracingTransportTests.StopsTracingAfterWriteFailure;
var
  mFailing: TFailingStream;
begin
  mFailing := TFailingStream.Create;
  try
    // Der Client bekommt alle Nachrichten, der Mitschnitt wird nur einmal versucht.
    Assert.AreEqual(3, WriteThree(mFailing, nil));
    Assert.AreEqual(1, mFailing.Writes);
  finally
    mFailing.Free;
  end;
end;

procedure TJsonRpcTracingTransportTests.ReportsWriteFailureOnce;
var
  mFailing: TFailingStream;
  mCalls: Integer;
  mReason: string;
begin
  mCalls := 0;
  mReason := '';
  mFailing := TFailingStream.Create;
  try
    WriteThree(mFailing,
      procedure(const AReason: string)
      begin
        Inc(mCalls);
        mReason := AReason;
      end);
    Assert.AreEqual(1, mCalls);
    Assert.Contains(mReason, 'EWriteError');
  finally
    mFailing.Free;
  end;
end;

procedure TJsonRpcTracingTransportTests.KeepsRecentLines;
var
  mInput, mOutput, mTrace: TBytesStream;
  mTracing: TJsonRpcTracingTransport;
  mTransport: IJsonRpcTransport;
  mMessage: TJSONObject;
  mLines: TArray<string>;
begin
  mInput := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"initialize"}']);
  mOutput := TBytesStream.Create;
  mTrace := TBytesStream.Create;
  try
    mTracing := TJsonRpcTracingTransport.Create(TJsonRpcStreamTransport.Create(mInput, mOutput, False), mTrace,
      False);
    mTransport := mTracing;
    mMessage := mTransport.ReadMessage;
    mMessage.Free;
    mMessage := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":1,"result":null}');
    try
      mTransport.WriteMessage(mMessage);
    finally
      mMessage.Free;
    end;
    mLines := mTracing.RecentLines(5, Now);
    Assert.AreEqual(2, Integer(Length(mLines)));
    Assert.IsTrue(mLines[0].Contains(TJsonRpcTracingTransport.cIncomingMarker + ' {'), mLines[0]);
    Assert.IsTrue(mLines[0].Contains('"initialize"'), mLines[0]);
    Assert.IsFalse(mLines[1].EndsWith(sLineBreak), 'ohne Zeilenende');
    // Älter als die Frage: nichts.
    Assert.AreEqual(0, Integer(Length(mTracing.RecentLines(1, Now + 2 / MinsPerDay))));
    mLines := nil;
    mTransport := nil;
  finally
    mTrace.Free;
    mOutput.Free;
    mInput.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcTracingTransportTests);

end.
