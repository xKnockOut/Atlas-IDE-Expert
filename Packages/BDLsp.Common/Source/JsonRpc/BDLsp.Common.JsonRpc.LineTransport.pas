unit BDLsp.Common.JsonRpc.LineTransport;

// JSON-RPC-Transport mit Zeilenrahmung, wie ihn das Model Context Protocol
// über stdio verwendet (#48): je Nachricht eine Zeile UTF-8-JSON, abgeschlossen
// mit LF. Ein CR vor dem LF wird toleriert, Leerzeilen werden übersprungen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract;

type
  TJsonRpcLineTransport = class(TInterfacedObject, IJsonRpcTransport)
  private const
    BufferSize = 64 * 1024;
    MaxLineLength = 256 * 1024 * 1024;
  private
    FInput: TStream;
    FOutput: TStream;
    FOwnsStreams: Boolean;
    FBuffer: TBytes;
    FBufferPos: Integer;
    FBufferLen: Integer;
    FWriteLock: TCriticalSection;
    function FillBuffer: Boolean;
    /// <summary>Nächste nicht leere Zeile ohne Zeilenende; False am Ende der Eingabe.</summary>
    function ReadLine(out ALine: TBytes): Boolean;
  public
    /// <summary>Bei AOwnsStreams gibt der Transport beide Streams frei.</summary>
    constructor Create(AInput, AOutput: TStream; AOwnsStreams: Boolean);
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

implementation

{ TJsonRpcLineTransport }

constructor TJsonRpcLineTransport.Create(AInput, AOutput: TStream; AOwnsStreams: Boolean);
begin
  inherited Create;
  FInput := AInput;
  FOutput := AOutput;
  FOwnsStreams := AOwnsStreams;
  SetLength(FBuffer, BufferSize);
  FWriteLock := TCriticalSection.Create;
end;

destructor TJsonRpcLineTransport.Destroy;
begin
  FWriteLock.Free;
  if FOwnsStreams then
  begin
    FInput.Free;
    FOutput.Free;
  end;
  inherited;
end;

function TJsonRpcLineTransport.FillBuffer: Boolean;
begin
  FBufferPos := 0;
  FBufferLen := FInput.Read(FBuffer[0], BufferSize);
  Result := FBufferLen > 0;
end;

function TJsonRpcLineTransport.ReadLine(out ALine: TBytes): Boolean;
var
  Line: TBytesStream;
  Value: Byte;
  Bytes: TBytes;
begin
  Line := TBytesStream.Create;
  try
    while True do
    begin
      if (FBufferPos >= FBufferLen) and not FillBuffer then
      begin
        // Letzte Zeile ohne LF gilt noch als Nachricht.
        if Line.Size = 0 then
          Exit(False);
        Break;
      end;
      Value := FBuffer[FBufferPos];
      Inc(FBufferPos);
      if Value = 10 then
      begin
        if Line.Size > 0 then
          Break;
        Continue;
      end;
      if (Value = 13) or ((Line.Size = 0) and (Value in [9, 32])) then
        Continue;
      if Line.Size >= MaxLineLength then
        raise EJsonRpcTransportError.Create('Nachricht überschreitet die Höchstlänge');
      Line.WriteBuffer(Value, 1);
    end;
    Bytes := Line.Bytes;
    ALine := Copy(Bytes, 0, Line.Size);
    Result := True;
  finally
    Line.Free;
  end;
end;

function TJsonRpcLineTransport.ReadMessage: TJSONObject;
var
  Line: TBytes;
  Value: TJSONValue;
begin
  if not ReadLine(Line) then
    raise EJsonRpcTransportClosed.Create('Eingabe geschlossen');
  Value := TJSONObject.ParseJSONValue(Line, 0, True);
  if Value = nil then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.ParseError, 'Nachricht ist kein gültiges JSON');
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidRequest, 'Nachricht ist kein JSON-Objekt');
  end;
  Result := TJSONObject(Value);
end;

procedure TJsonRpcLineTransport.WriteMessage(const AMessage: TJSONObject);
var
  Data: TBytes;
begin
  // ToJSON maskiert Zeilenumbrüche in Strings, die Nachricht bleibt einzeilig.
  Data := TEncoding.UTF8.GetBytes(AMessage.ToJSON + #10);
  FWriteLock.Enter;
  try
    FOutput.WriteBuffer(Data, Length(Data));
  finally
    FWriteLock.Leave;
  end;
end;

end.
