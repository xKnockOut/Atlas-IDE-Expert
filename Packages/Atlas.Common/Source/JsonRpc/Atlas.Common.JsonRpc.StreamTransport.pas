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
    cBufferSize = 64 * 1024;
    cMaxHeaderLineLength = 8 * 1024;
    cMaxContentLength = 256 * 1024 * 1024;
    cContentLengthHeader = 'Content-Length:';
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
  System.Math,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TStreamTransportText = (InvalidHeader, HeaderContentLengthMissing, InputClosedWithinAMessage, MessageIsNotValidJSON,
    MessageIsNotAJSON, InputClosedWithinAHeader, HeaderLineTooLong, InputClosed, EmptyMessage);

const
  cTexts: array[TStreamTransportText] of TAtlasText = (
    (De: 'Ungültiger Header "%s"'; En: 'Invalid header "%s"'),
    (De: 'Header Content-Length fehlt'; En: 'Header Content-Length missing'),
    (De: 'Eingabe innerhalb einer Nachricht geschlossen'; En: 'Input closed within a message'),
    (De: 'Nachricht ist kein gültiges JSON'; En: 'Message is not valid JSON'),
    (De: 'Nachricht ist kein JSON-Objekt'; En: 'Message is not a JSON object'),
    (De: 'Eingabe innerhalb eines Headers geschlossen'; En: 'Input closed within a header'),
    (De: 'Headerzeile zu lang'; En: 'Header line too long'),
    (De: 'Eingabe geschlossen'; En: 'Input closed'),
    (De: 'Leere Nachricht'; En: 'Empty message'));

{$SCOPEDENUMS OFF}

{ TJsonRpcStreamTransport }

constructor TJsonRpcStreamTransport.Create(AInput, AOutput: TStream; AOwnsStreams: Boolean);
begin
  inherited Create;
  FInput := AInput;
  FOutput := AOutput;
  FOwnsStreams := AOwnsStreams;
  SetLength(FBuffer, cBufferSize);
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
  mCount: Integer;
begin
  // Bei Pipes liefert Read, sobald Daten anliegen, auch weniger als angefordert.
  mCount := FInput.Read(FBuffer[0], cBufferSize);
  FBufferPos := 0;
  FBufferLen := Max(mCount, 0);
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
  mLine: TBytes;
  mLen: Integer;
  B: Byte;
begin
  SetLength(mLine, 64);
  mLen := 0;
  while True do
  begin
    if not TryReadByte(B) then
    begin
      if AAtMessageStart and (mLen = 0) then
      begin
        raise EJsonRpcTransportClosed.Create(cTexts[TStreamTransportText.InputClosed].Text);
      end;
      raise EJsonRpcTransportError.Create(cTexts[TStreamTransportText.InputClosedWithinAHeader].Text);
    end;
    if B = 10 then
    begin
      Break;
    end;
    if B = 13 then
    begin
      Continue;
    end;
    if mLen >= cMaxHeaderLineLength then
    begin
      raise EJsonRpcTransportError.Create(cTexts[TStreamTransportText.HeaderLineTooLong].Text);
    end;
    if mLen = Length(mLine) then
    begin
      SetLength(mLine, mLen * 2);
    end;
    mLine[mLen] := B;
    Inc(mLen);
  end;
  Result := TEncoding.ASCII.GetString(mLine, 0, mLen);
end;

function TJsonRpcStreamTransport.ReadContentLength: Integer;
var
  mLine: string;
  mHeaderSeen: Boolean;
begin
  Result := -1;
  mHeaderSeen := False;
  while True do
  begin
    mLine := ReadHeaderLine(not mHeaderSeen);
    if mLine = '' then
    begin
      // Leerzeilen vor dem ersten Header werden übersprungen.
      if mHeaderSeen then
      begin
        Break;
      end;
      Continue;
    end;
    mHeaderSeen := True;
    if mLine.StartsWith(cContentLengthHeader, True) then
    begin
      if not TryStrToInt(mLine.Substring(Length(cContentLengthHeader)).Trim, Result)
        or (Result < 0) or (Result > cMaxContentLength) then
      begin
        raise EJsonRpcTransportError.CreateFmt(cTexts[TStreamTransportText.InvalidHeader].Text, [mLine]);
      end;
    end;
    // Weitere Header (z. B. Content-Type) werden ignoriert.
  end;
  if Result < 0 then
  begin
    raise EJsonRpcTransportError.Create(cTexts[TStreamTransportText.HeaderContentLengthMissing].Text);
  end;
end;

function TJsonRpcStreamTransport.ReadBody(ACount: Integer): TBytes;
var
  mOffset: Integer;
  mCount: Integer;
begin
  SetLength(Result, ACount);
  mOffset := 0;
  while mOffset < ACount do
  begin
    if (FBufferPos >= FBufferLen) and not FillBuffer then
    begin
      raise EJsonRpcTransportError.Create(cTexts[TStreamTransportText.InputClosedWithinAMessage].Text);
    end;
    mCount := Min(ACount - mOffset, FBufferLen - FBufferPos);
    Move(FBuffer[FBufferPos], Result[mOffset], mCount);
    Inc(FBufferPos, mCount);
    Inc(mOffset, mCount);
  end;
end;

function TJsonRpcStreamTransport.ReadMessage: TJSONObject;
var
  mBody: TBytes;
  mValue: TJSONValue;
begin
  mBody := ReadBody(ReadContentLength);
  if Length(mBody) = 0 then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cParseError, cTexts[TStreamTransportText.EmptyMessage].Text);
  end;

  mValue := TJSONObject.ParseJSONValue(mBody, 0, True);
  if mValue = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cParseError, cTexts[TStreamTransportText.MessageIsNotValidJSON].Text);
  end;
  if not (mValue is TJSONObject) then
  begin
    mValue.Free;
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidRequest, cTexts[TStreamTransportText.MessageIsNotAJSON].Text);
  end;
  Result := TJSONObject(mValue);
end;

procedure TJsonRpcStreamTransport.WriteMessage(const AMessage: TJSONObject);
var
  mBody: TBytes;
  mData: TBytes;
begin
  mBody := TEncoding.UTF8.GetBytes(AMessage.ToJSON);
  mData := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(mBody)])) + mBody;
  // Header und Inhalt in einem Stück, damit sich Nachrichten mehrerer Threads nicht mischen.
  FWriteLock.Enter;
  try
    FOutput.WriteBuffer(mData, Length(mData));
  finally
    FWriteLock.Leave;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.JsonRpc.StreamTransport', cTexts);

end.
