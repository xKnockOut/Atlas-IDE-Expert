unit Atlas.Common.JsonRpc.LineTransport;

// JSON-RPC-Transport mit Zeilenrahmung, wie ihn das Model Context Protocol
// über stdio verwendet (#48): je Nachricht eine Zeile UTF-8-JSON, abgeschlossen
// mit LF. Ein CR vor dem LF wird toleriert, Leerzeilen werden übersprungen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  Atlas.Common.JsonRpc.Contract;

type
  TJsonRpcLineTransport = class(TInterfacedObject, IJsonRpcTransport)
  private const
    cBufferSize = 64 * 1024;
    cMaxLineLength = 256 * 1024 * 1024;
  private
    FInput: TStream;
    FOutput: TStream;
    FOwnsStreams: Boolean;
    FBuffer: TBytes;
    FBufferPos: Integer;
    FBufferLen: Integer;
    FWriteLock: TCriticalSection;
    function FillBuffer: Boolean;
    /// <summary>Nächstes Byte der Eingabe; False am Ende.</summary>
    function NextByte(out AValue: Byte): Boolean;
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

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLineTransportText = (MessageExceedsTheMaximumLength, MessageIsNotValidJSON, MessageIsNotAJSON, InputClosed);

const
  cTexts: array[TLineTransportText] of TAtlasText = (
    (De: 'Nachricht überschreitet die Höchstlänge'; En: 'Message exceeds the maximum length'),
    (De: 'Nachricht ist kein gültiges JSON'; En: 'Message is not valid JSON'),
    (De: 'Nachricht ist kein JSON-Objekt'; En: 'Message is not a JSON object'),
    (De: 'Eingabe geschlossen'; En: 'Input closed'));

{$SCOPEDENUMS OFF}

{ TJsonRpcLineTransport }

constructor TJsonRpcLineTransport.Create(AInput, AOutput: TStream; AOwnsStreams: Boolean);
begin
  inherited Create;
  FInput := AInput;
  FOutput := AOutput;
  FOwnsStreams := AOwnsStreams;
  SetLength(FBuffer, cBufferSize);
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
  FBufferLen := FInput.Read(FBuffer[0], cBufferSize);
  Result := FBufferLen > 0;
end;

function TJsonRpcLineTransport.NextByte(out AValue: Byte): Boolean;
begin
  Result := (FBufferPos < FBufferLen) or FillBuffer;
  if Result then
  begin
    AValue := FBuffer[FBufferPos];
    Inc(FBufferPos);
  end;
end;

/// <summary>AValue gehört nicht in die Zeile: CR immer, Tabulator und Leerzeichen am Anfang.</summary>
function SkipsByte(AValue: Byte; ALineSize: Int64): Boolean;
begin
  Result := (AValue = 13) or ((ALineSize = 0) and (AValue in [9, 32]));
end;

function TJsonRpcLineTransport.ReadLine(out ALine: TBytes): Boolean;
var
  mLine: TBytesStream;
  mValue: Byte;
  mDone: Boolean;
begin
  mLine := TBytesStream.Create;
  try
    mDone := False;
    // Leere Zeilen zählen nicht; die letzte Zeile ohne LF gilt noch als Nachricht.
    while not mDone and NextByte(mValue) do
    begin
      if mValue = 10 then
      begin
        mDone := mLine.Size > 0;
      end
      else if not SkipsByte(mValue, mLine.Size) then
      begin
        if mLine.Size >= cMaxLineLength then
        begin
          raise EJsonRpcTransportError.Create(cTexts[TLineTransportText.MessageExceedsTheMaximumLength].Text);
        end;
        mLine.WriteBuffer(mValue, 1);
      end;
    end;
    Result := mLine.Size > 0;
    if Result then
    begin
      ALine := Copy(mLine.Bytes, 0, mLine.Size);
    end;
  finally
    mLine.Free;
  end;
end;

function TJsonRpcLineTransport.ReadMessage: TJSONObject;
var
  mLine: TBytes;
  mValue: TJSONValue;
begin
  if not ReadLine(mLine) then
  begin
    raise EJsonRpcTransportClosed.Create(cTexts[TLineTransportText.InputClosed].Text);
  end;
  mValue := TJSONObject.ParseJSONValue(mLine, 0, True);
  if mValue = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cParseError, cTexts[TLineTransportText.MessageIsNotValidJSON].Text);
  end;
  if not (mValue is TJSONObject) then
  begin
    mValue.Free;
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidRequest, cTexts[TLineTransportText.MessageIsNotAJSON].Text);
  end;
  Result := TJSONObject(mValue);
end;

procedure TJsonRpcLineTransport.WriteMessage(const AMessage: TJSONObject);
var
  mData: TBytes;
begin
  // ToJSON maskiert Zeilenumbrüche in Strings, die Nachricht bleibt einzeilig.
  mData := TEncoding.UTF8.GetBytes(AMessage.ToJSON + #10);
  FWriteLock.Enter;
  try
    FOutput.WriteBuffer(mData, Length(mData));
  finally
    FWriteLock.Leave;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.JsonRpc.LineTransport', cTexts);

end.
