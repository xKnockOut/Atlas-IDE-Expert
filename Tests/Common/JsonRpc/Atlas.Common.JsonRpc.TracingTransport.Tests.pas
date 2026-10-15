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
    /// <summary>Code-Review S-07: nach dem ersten Schreibfehler kein weiterer Versuch.</summary>
    [Test]
    procedure StopsTracingAfterWriteFailure;
    [Test]
    procedure ReportsWriteFailureOnce;
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
  Output: TBytesStream;
  Tracing: TJsonRpcTracingTransport;
  Transport: IJsonRpcTransport;
  Outgoing: TJSONObject;
  Written: TObjectList<TJSONObject>;
  Index: Integer;
begin
  Output := TBytesStream.Create;
  try
    Tracing := TJsonRpcTracingTransport.Create(TJsonRpcStreamTransport.Create(nil, Output, False), AFailing, False);
    Transport := Tracing;
    Tracing.OnFailed := AOnFailed;
    for Index := 1 to 3 do
    begin
      Outgoing := TJsonRpcTestSupport.Parse(Format('{"jsonrpc":"2.0","id":%d,"result":null}', [Index]));
      try
        Transport.WriteMessage(Outgoing);
      finally
        Outgoing.Free;
      end;
    end;
    Transport := nil;
    Written := TJsonRpcTestSupport.ReadMessages(Output);
    try
      Result := Written.Count;
    finally
      Written.Free;
    end;
  finally
    Output.Free;
  end;
end;

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

procedure TJsonRpcTracingTransportTests.StopsTracingAfterWriteFailure;
var
  Failing: TFailingStream;
begin
  Failing := TFailingStream.Create;
  try
    // Der Client bekommt alle Nachrichten, der Mitschnitt wird nur einmal versucht.
    Assert.AreEqual(3, WriteThree(Failing, nil));
    Assert.AreEqual(1, Failing.Writes);
  finally
    Failing.Free;
  end;
end;

procedure TJsonRpcTracingTransportTests.ReportsWriteFailureOnce;
var
  Failing: TFailingStream;
  Calls: Integer;
  Reason: string;
begin
  Calls := 0;
  Reason := '';
  Failing := TFailingStream.Create;
  try
    WriteThree(Failing,
      procedure(const AReason: string)
      begin
        Inc(Calls);
        Reason := AReason;
      end);
    Assert.AreEqual(1, Calls);
    Assert.Contains(Reason, 'EWriteError');
  finally
    Failing.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcTracingTransportTests);

end.
