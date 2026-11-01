unit Atlas.Common.JsonRpc.StreamTransport;

// JSON-RPC-Transport über zwei Streams mit der Rahmung des Language Server
// Protocol: Header "Content-Length: <Bytes>", Leerzeile, UTF-8-JSON.
// Plattformunabhängig; die Anwendung reicht stdin/stdout als Streams herein.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  Atlas.Common.JsonRpc.Contract;

type
  TJsonRpcStreamTransport = class(TInterfacedObject, IJsonRpcTransport)
  private const
    BufferSize = 64 * 1024;
    MaxHeaderLineLength = 8 * 1024;
    MaxContentLength = 256 * 1024 * 1024;
    ContentLengthHeader = 'Content-Length:';
  private
    FInput: TStream;
    FOutput: TStream;
    FOwnsStreams: Boolean;
    FBuffer: TBytes;
    FBufferPos: Integer;
    FBufferLen: Integer;
    FWriteLock: TCriticalSection;
    function FillBuffer: Boolean;
    function TryReadByte(out AByte: Byte): Boolean;
    function ReadHeaderLine(AAtMessageStart: Boolean): string;
    function ReadBody(ACount: Integer): TBytes;
    function ReadContentLength: Integer;
  public
    /// <summary>
    /// AInput liefert die Nachrichten der Gegenseite, AOutput nimmt die eigenen auf.
    /// Bei AOwnsStreams gibt der Transport beide Streams frei.
    /// </summary>
    constructor Create(AInput, AOutput: TStream; AOwnsStreams: Boolean);
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

implementation

uses
  System.Math;

{ TJsonRpcStreamTransport }

constructor TJsonRpcStreamTransport.Create(AInput, AOutput: TStream; AOwnsStreams: Boolean);
begin
  inherited Create;
  FInput := AInput;
  FOutput := AOutput;
  FOwnsStreams := AOwnsStreams;
  SetLength(FBuffer, BufferSize);
  FWriteLock := TCriticalSection.Create;
end;

destructor TJsonRpcStreamTransport.Destroy;
begin
  FWriteLock.Free;
  if FOwnsStreams then
  begin
    FInput.Free;
    FOutput.Free;
  end;
  inherited;
end;

function TJsonRpcStreamTransport.FillBuffer: Boolean;
var
  Count: Integer;
begin
  // Bei Pipes liefert Read, sobald Daten anliegen, auch weniger als angefordert.
  Count := FInput.Read(FBuffer[0], BufferSize);
  FBufferPos := 0;
  FBufferLen := Max(Count, 0);
  Result := FBufferLen > 0;
end;

function TJsonRpcStreamTransport.TryReadByte(out AByte: Byte): Boolean;
begin
  if (FBufferPos >= FBufferLen) and not FillBuffer then
  begin
    Exit(False);
  end;
  AByte := FBuffer[FBufferPos];
  Inc(FBufferPos);
  Result := True;
end;

function TJsonRpcStreamTransport.ReadHeaderLine(AAtMessageStart: Boolean): string;
var
  Line: TBytes;
  Len: Integer;
  B: Byte;
begin
  SetLength(Line, 64);
  Len := 0;
  while True do
  begin
    if not TryReadByte(B) then
    begin
      if AAtMessageStart and (Len = 0) then
      begin
        raise EJsonRpcTransportClosed.Create('Eingabe geschlossen');
      end;
      raise EJsonRpcTransportError.Create('Eingabe innerhalb eines Headers geschlossen');
    end;
    if B = 10 then
    begin
      Break;
    end;
    if B = 13 then
    begin
      Continue;
    end;
    if Len >= MaxHeaderLineLength then
    begin
      raise EJsonRpcTransportError.Create('Headerzeile zu lang');
    end;
    if Len = Length(Line) then
    begin
      SetLength(Line, Len * 2);
    end;
    Line[Len] := B;
    Inc(Len);
  end;
  Result := TEncoding.ASCII.GetString(Line, 0, Len);
end;

function TJsonRpcStreamTransport.ReadContentLength: Integer;
var
  Line: string;
  HeaderSeen: Boolean;
begin
  Result := -1;
  HeaderSeen := False;
  while True do
  begin
    Line := ReadHeaderLine(not HeaderSeen);
    if Line = '' then
    begin
      // Leerzeilen vor dem ersten Header werden übersprungen.
      if HeaderSeen then
      begin
        Break;
      end;
      Continue;
    end;
    HeaderSeen := True;
    if Line.StartsWith(ContentLengthHeader, True) then
    begin
      if not TryStrToInt(Line.Substring(Length(ContentLengthHeader)).Trim, Result)
        or (Result < 0) or (Result > MaxContentLength) then
      begin
        raise EJsonRpcTransportError.CreateFmt('Ungültiger Header "%s"', [Line]);
      end;
    end;
    // Weitere Header (z. B. Content-Type) werden ignoriert.
  end;
  if Result < 0 then
  begin
    raise EJsonRpcTransportError.Create('Header Content-Length fehlt');
  end;
end;

function TJsonRpcStreamTransport.ReadBody(ACount: Integer): TBytes;
var
  Offset: Integer;
  Count: Integer;
begin
  SetLength(Result, ACount);
  Offset := 0;
  while Offset < ACount do
  begin
    if (FBufferPos >= FBufferLen) and not FillBuffer then
    begin
      raise EJsonRpcTransportError.Create('Eingabe innerhalb einer Nachricht geschlossen');
    end;
    Count := Min(ACount - Offset, FBufferLen - FBufferPos);
    Move(FBuffer[FBufferPos], Result[Offset], Count);
    Inc(FBufferPos, Count);
    Inc(Offset, Count);
  end;
end;

function TJsonRpcStreamTransport.ReadMessage: TJSONObject;
var
  Body: TBytes;
  Value: TJSONValue;
begin
  Body := ReadBody(ReadContentLength);
  if Length(Body) = 0 then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.ParseError, 'Leere Nachricht');
  end;

  Value := TJSONObject.ParseJSONValue(Body, 0, True);
  if Value = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.ParseError, 'Nachricht ist kein gültiges JSON');
  end;
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Nachricht ist kein JSON-Objekt');
  end;
  Result := TJSONObject(Value);
end;

procedure TJsonRpcStreamTransport.WriteMessage(const AMessage: TJSONObject);
var
  Body: TBytes;
  Data: TBytes;
begin
  Body := TEncoding.UTF8.GetBytes(AMessage.ToJSON);
  Data := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(Body)])) + Body;
  // Header und Inhalt in einem Stück, damit sich Nachrichten mehrerer Threads nicht mischen.
  FWriteLock.Enter;
  try
    FOutput.WriteBuffer(Data, Length(Data));
  finally
    FWriteLock.Leave;
  end;
end;

end.
