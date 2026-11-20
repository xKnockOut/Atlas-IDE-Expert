unit Atlas.Core.Assistants.LinkFrames;

// Assistenten-Kopplung (#2377), Transport ohne Sockets: Handschlag und Rahmen von WebSocket (RFC 6455), wie sie
// ein verbundener Kommandozeilen-Assistent spricht. Die IDE liest Bytes vom Socket und gibt sie hier hinein;
// heraus kommen fertige Textnachrichten, Antworten auf Ping und das Ende der Verbindung. Ohne Threads, Sockets und
// Open Tools API, damit alles ohne IDE testbar ist (Atlas.IDE.Assistants.LinkServer ist der Adapter).
// - TAtlasLinkHandshake: GET-Anfrage mit Upgrade lesen, Token im Kopf prüfen, Antwort 101 bzw. Ablehnung bauen.
// - TAtlasLinkReader: Rahmen des Clients (immer maskiert) zerlegen, Fortsetzungen zusammensetzen, Ping, Close.
// - TAtlasLinkWriter: Rahmen des Servers (nie maskiert) für Text, Pong und Close.

interface

uses
  System.SysUtils;

type
  /// <summary>Kopf einer Upgrade-Anfrage, wie Parse ihn liest.</summary>
  TAtlasLinkHandshake = record
  public const
    /// <summary>Feste Kennung aus RFC 6455 für Sec-WebSocket-Accept.</summary>
    cAcceptGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
    /// <summary>Antworten auf einen abgelehnten Handschlag.</summary>
    cStatusBadRequest = 400;
    cStatusUnauthorized = 401;
    cStatusForbidden = 403;
    /// <summary>Längster Kopf, den der Server annimmt; danach bricht er ab.</summary>
    cMaxHeaderBytes = 16384;
  public
    Method: string;
    Path: string;
    Key: string;
    Upgrade: string;
    Connection: string;
    Version: string;
    /// <summary>Wert des Kopfs mit dem Token (Name aus TAtlasLinkLock.cTokenHeader).</summary>
    Token: string;
    /// <summary>Origin eines Browsers; ein Kommandozeilen-Client schickt keinen.</summary>
    Origin: string;
    /// <summary>Länge des Kopfs in Bytes bis einschließlich der Leerzeile; 0, solange er unvollständig ist.
    /// </summary>
    class function HeaderLength(const ABuffer: TBytes; ACount: Integer): Integer; static;
    /// <summary>Kopf aus ARequest (ASCII bis zur Leerzeile); ATokenHeader ist der Name des Token-Kopfs.</summary>
    class function Parse(const ARequest, ATokenHeader: string): TAtlasLinkHandshake; static;
    /// <summary>Ist es ein gültiges Upgrade auf WebSocket mit dem Token AToken? AReason nennt sonst den Grund.
    /// </summary>
    function Admits(const AToken: string; out AReason: string): Boolean;
    /// <summary>Sec-WebSocket-Accept zu AKey.</summary>
    class function AcceptOf(const AKey: string): string; static;
    /// <summary>Antwort 101 auf diesen Kopf.</summary>
    function Response: string;
    /// <summary>Ablehnung mit AStatus (400, 401, 403) und kurzem Grund; danach schließt der Server.</summary>
    class function Refusal(AStatus: Integer; const AReason: string): string; static;
    /// <summary>Vergleich in fester Zeit (das Token soll sich nicht über die Laufzeit erraten lassen).</summary>
    class function SameToken(const AExpected, AGiven: string): Boolean; static;
  end;

  /// <summary>Was der Leser gerade liefert.</summary>
  TAtlasLinkEventKind = (None, Text, Ping, Close, Error);

  /// <summary>Ein Ereignis aus TAtlasLinkReader.Next.</summary>
  TAtlasLinkEvent = record
    Kind: TAtlasLinkEventKind;
    /// <summary>Text bei Text, Grund bei Error.</summary>
    Text: string;
    /// <summary>Nutzlast von Ping (für das Pong).</summary>
    Payload: TBytes;
  end;

  /// <summary>Zerlegt die Bytes des Clients in Ereignisse; nach Error oder Close liefert er nichts mehr.</summary>
  TAtlasLinkReader = class
  public const
    cOpContinuation = $0;
    cOpText = $1;
    cOpBinary = $2;
    cOpClose = $8;
    cOpPing = $9;
    cOpPong = $A;
    /// <summary>Größte Nachricht (Vorschläge ganzer Dateien), danach Error.</summary>
    cMaxMessageBytes = 32 * 1024 * 1024;
  private
    FBuffer: TBytes;
    FCount: Integer;
    FMessage: TBytes;
    FMessageCount: Integer;
    FInMessage: Boolean;
    FMessageIsText: Boolean;
    FDone: Boolean;
    function Fail(const AReason: string): TAtlasLinkEvent;
    procedure Consume(ABytes: Integer);
    procedure AppendMessage(const APayload: TBytes);
    function DataEvent(AOpcode: Byte; AFin: Boolean; const APayload: TBytes): TAtlasLinkEvent;
    function ControlEvent(AOpcode: Byte; AFin: Boolean; const APayload: TBytes): TAtlasLinkEvent;
    /// <summary>Erste zwei Bytes vorhanden und gültig; AEvent ist der Fehler, sonst leer.</summary>
    function HeadValid(out AEvent: TAtlasLinkEvent): Boolean;
    /// <summary>Länge der Nutzdaten und Länge des Kopfs ohne Maske; False, solange Bytes fehlen oder bei Fehler
    /// (AEvent).</summary>
    function PayloadLength(out AHead: Integer; out ALength: UInt64; out AEvent: TAtlasLinkEvent): Boolean;
    /// <summary>ACount Bytes ab AStart als Zahl, höchstwertiges Byte zuerst.</summary>
    function BigEndian(AStart, ACount: Integer): UInt64;
    /// <summary>Nutzdaten hinter Kopf und Maske, entschlüsselt.</summary>
    function Unmask(AHead: Integer; ALength: UInt64): TBytes;
    function TakeFrame(out AOpcode: Byte; out AFin: Boolean; out APayload: TBytes; out AEvent: TAtlasLinkEvent):
      Boolean;
  public
    /// <summary>ACount Bytes von AData anhängen.</summary>
    procedure Feed(const AData: TBytes; ACount: Integer);
    /// <summary>Nächstes Ereignis; None, solange Bytes fehlen.</summary>
    function Next: TAtlasLinkEvent;
    /// <summary>Close oder Error kam; die Verbindung ist zu Ende.</summary>
    property Done: Boolean read FDone;
  end;

  TAtlasLinkWriter = class
  public const
    /// <summary>Schließcodes aus RFC 6455.</summary>
    cCloseNormal = 1000;
    cCloseGoingAway = 1001;
    cCloseProtocol = 1002;
    cCloseTooBig = 1009;
  public
    /// <summary>Rahmen mit AOpcode und APayload, ungeteilt und unmaskiert.</summary>
    class function Frame(AOpcode: Byte; const APayload: TBytes): TBytes; static;
    class function Text(const AText: string): TBytes; static;
    class function Pong(const APayload: TBytes): TBytes; static;
    class function Close(ACode: Word): TBytes; static;
  end;

implementation

uses
  System.StrUtils,
  System.Hash,
  System.NetEncoding;

const
  cCrLf = #13#10;
  cHeaderEnd: array[0..3] of Byte = (13, 10, 13, 10);
  /// <summary>Kopfzeilen des Handschlags, klein geschrieben.</summary>
  cHeaderNames: array[0..4] of string = ('sec-websocket-key', 'upgrade', 'connection', 'sec-websocket-version',
    'origin');
  cHeaderKey = 0;
  cHeaderUpgrade = 1;
  cHeaderConnection = 2;
  cHeaderVersion = 3;
  cHeaderOrigin = 4;
  cMethodGet = 'GET';
  cUpgradeWebSocket = 'websocket';
  cConnectionUpgrade = 'upgrade';
  cWebSocketVersion = '13';
  cReasonNoUpgrade = 'no websocket upgrade';
  cReasonOrigin = 'origin not allowed';
  cReasonToken = 'invalid token';
  cReasonReserved = 'reserved bits set';
  cReasonUnmasked = 'client frame not masked';
  cReasonTooBig = 'message too big';
  cReasonControl = 'invalid control frame';
  cReasonContinuation = 'unexpected continuation';
  cReasonOpcode = 'unknown opcode';
  cResponseSwitching = 'HTTP/1.1 101 Switching Protocols' + cCrLf + 'Upgrade: websocket' + cCrLf +
    'Connection: Upgrade' + cCrLf + 'Sec-WebSocket-Accept: ';
  cRefusalStatus = 'HTTP/1.1 %d %s';
  cRefusalHeaders = 'Connection: close' + cCrLf + 'Content-Type: text/plain' + cCrLf + 'Content-Length: %d';
  cTitleUnauthorized = 'Unauthorized';
  cTitleForbidden = 'Forbidden';
  cTitleBadRequest = 'Bad Request';
  /// <summary>Kopf eines Rahmens: zwei Bytes, dazu 2 bzw. 8 Bytes für längere Nutzdaten.</summary>
  cHeadMin = 2;
  cLength16Bytes = 2;
  cLength64Bytes = 8;
  cBitsPerByte = 8;
  cMax16 = $FFFF;
  cLength16 = 126;
  cLength64 = 127;
  cLengthMask = $7F;
  cFinBit = $80;
  cMaskBit = $80;
  cOpcodeMask = $0F;
  cReservedBits = $70;
  cMaskBytes = 4;
  cMaxControlPayload = 125;

{ TAtlasLinkHandshake }

class function TAtlasLinkHandshake.HeaderLength(const ABuffer: TBytes; ACount: Integer): Integer;
var
  mIndex: Integer;
  mMatched: Integer;
begin
  Result := 0;
  mMatched := 0;
  // Leerzeile nach dem Kopf: so viele Bytes in Folge wie cHeaderEnd.
  for mIndex := 0 to ACount - 1 do
  begin
    if ABuffer[mIndex] = cHeaderEnd[mMatched] then
    begin
      Inc(mMatched);
    end
    else
    begin
      mMatched := Ord(ABuffer[mIndex] = cHeaderEnd[0]);
    end;
    if mMatched = Length(cHeaderEnd) then
    begin
      Result := mIndex + 1;
      Exit;
    end;
  end;
end;

class function TAtlasLinkHandshake.Parse(const ARequest, ATokenHeader: string): TAtlasLinkHandshake;
var
  mLines: TArray<string>;
  mParts: TArray<string>;
  mIndex: Integer;
  mColon: Integer;
  mName: string;
  mValue: string;
begin
  Result := Default(TAtlasLinkHandshake);
  mLines := ARequest.Split([cCrLf]);
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  mParts := mLines[0].Split([' ']);
  if Length(mParts) >= 2 then
  begin
    Result.Method := mParts[0];
    Result.Path := mParts[1];
  end;
  for mIndex := 1 to High(mLines) do
  begin
    mColon := Pos(':', mLines[mIndex]);
    if mColon < 2 then
    begin
      Continue;
    end;
    mName := LowerCase(Trim(Copy(mLines[mIndex], 1, mColon - 1)));
    mValue := Trim(Copy(mLines[mIndex], mColon + 1, MaxInt));
    if mName = LowerCase(ATokenHeader) then
    begin
      Result.Token := mValue;
      Continue;
    end;
    case IndexStr(mName, cHeaderNames) of
      cHeaderKey:
        Result.Key := mValue;
      cHeaderUpgrade:
        Result.Upgrade := mValue;
      cHeaderConnection:
        Result.Connection := mValue;
      cHeaderVersion:
        Result.Version := mValue;
      cHeaderOrigin:
        Result.Origin := mValue;
    end;
  end;
end;

function TAtlasLinkHandshake.Admits(const AToken: string; out AReason: string): Boolean;
begin
  Result := False;
  if (Method <> cMethodGet) or not SameText(Upgrade, cUpgradeWebSocket) or
    (Pos(cConnectionUpgrade, LowerCase(Connection)) = 0) or (Key = '') or (Version <> cWebSocketVersion) then
  begin
    AReason := cReasonNoUpgrade;
    Exit;
  end;
  // Ein Browser schickt immer Origin; eine Webseite darf die IDE nicht steuern, auch nicht mit erratenem Port.
  if Origin <> '' then
  begin
    AReason := cReasonOrigin;
    Exit;
  end;
  if (AToken = '') or not SameToken(AToken, Token) then
  begin
    AReason := cReasonToken;
    Exit;
  end;
  AReason := '';
  Result := True;
end;

class function TAtlasLinkHandshake.AcceptOf(const AKey: string): string;
var
  mHash: TBytes;
begin
  // SHA-1 schreibt RFC 6455 für den Handschlag vor; es schützt nichts und belegt nur, dass der Server WebSocket
  // spricht. Das Token schützt die Verbindung.
  mHash := THashSHA1.GetHashBytes(AKey + cAcceptGuid); // lsp-ignore: security-weak-crypto
  Result := TNetEncoding.Base64.EncodeBytesToString(mHash);
end;

function TAtlasLinkHandshake.Response: string;
begin
  Result := cResponseSwitching + AcceptOf(Key) + cCrLf + cCrLf;
end;

class function TAtlasLinkHandshake.Refusal(AStatus: Integer; const AReason: string): string;
var
  mTitle: string;
begin
  case AStatus of
    cStatusUnauthorized:
      mTitle := cTitleUnauthorized;
    cStatusForbidden:
      mTitle := cTitleForbidden;
  else
    mTitle := cTitleBadRequest;
  end;
  Result := Format(cRefusalStatus, [AStatus, mTitle]) + cCrLf + Format(cRefusalHeaders, [Length(AReason)]) + cCrLf +
    cCrLf + AReason;
end;

class function TAtlasLinkHandshake.SameToken(const AExpected, AGiven: string): Boolean;
var
  mIndex: Integer;
  mDiff: Integer;
begin
  mDiff := Length(AExpected) xor Length(AGiven);
  for mIndex := 1 to Length(AExpected) do
  begin
    if mIndex <= Length(AGiven) then
    begin
      mDiff := mDiff or (Ord(AExpected[mIndex]) xor Ord(AGiven[mIndex]));
    end;
  end;
  Result := mDiff = 0;
end;

{ TAtlasLinkReader }

procedure TAtlasLinkReader.Feed(const AData: TBytes; ACount: Integer);
begin
  if (ACount <= 0) or FDone then
  begin
    Exit;
  end;
  if FCount + ACount > Length(FBuffer) then
  begin
    SetLength(FBuffer, (FCount + ACount) * 2);
  end;
  Move(AData[0], FBuffer[FCount], ACount);
  Inc(FCount, ACount);
end;

function TAtlasLinkReader.Fail(const AReason: string): TAtlasLinkEvent;
begin
  FDone := True;
  Result := Default(TAtlasLinkEvent);
  Result.Kind := TAtlasLinkEventKind.Error;
  Result.Text := AReason;
end;

procedure TAtlasLinkReader.Consume(ABytes: Integer);
begin
  if ABytes < FCount then
  begin
    Move(FBuffer[ABytes], FBuffer[0], FCount - ABytes);
  end;
  Dec(FCount, ABytes);
end;

procedure TAtlasLinkReader.AppendMessage(const APayload: TBytes);
begin
  if Length(APayload) = 0 then
  begin
    Exit;
  end;
  if FMessageCount + Length(APayload) > Length(FMessage) then
  begin
    SetLength(FMessage, (FMessageCount + Length(APayload)) * 2);
  end;
  Move(APayload[0], FMessage[FMessageCount], Length(APayload));
  Inc(FMessageCount, Length(APayload));
end;

function TAtlasLinkReader.HeadValid(out AEvent: TAtlasLinkEvent): Boolean;
begin
  Result := False;
  AEvent := Default(TAtlasLinkEvent);
  if FCount < cHeadMin then
  begin
    Exit;
  end;
  if FBuffer[0] and cReservedBits <> 0 then
  begin
    AEvent := Fail(cReasonReserved);
  end
  else if FBuffer[1] and cMaskBit = 0 then
  begin
    AEvent := Fail(cReasonUnmasked);
  end
  else
  begin
    Result := True;
  end;
end;

function TAtlasLinkReader.BigEndian(AStart, ACount: Integer): UInt64;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := AStart to AStart + ACount - 1 do
  begin
    Result := (Result shl cBitsPerByte) or FBuffer[mIndex];
  end;
end;

function TAtlasLinkReader.PayloadLength(out AHead: Integer; out ALength: UInt64; out AEvent: TAtlasLinkEvent):
  Boolean;
var
  mExtra: Integer;
begin
  Result := False;
  AEvent := Default(TAtlasLinkEvent);
  AHead := cHeadMin;
  ALength := FBuffer[1] and cLengthMask;
  mExtra := 0;
  if ALength = cLength16 then
  begin
    mExtra := cLength16Bytes;
  end
  else if ALength = cLength64 then
  begin
    mExtra := cLength64Bytes;
  end;
  if FCount < cHeadMin + mExtra then
  begin
    Exit;
  end;
  if mExtra > 0 then
  begin
    ALength := BigEndian(cHeadMin, mExtra);
    Inc(AHead, mExtra);
  end;
  if ALength > cMaxMessageBytes then
  begin
    AEvent := Fail(cReasonTooBig);
    Exit;
  end;
  Result := True;
end;

function TAtlasLinkReader.Unmask(AHead: Integer; ALength: UInt64): TBytes;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, ALength);
  for mIndex := 0 to Integer(ALength) - 1 do
  begin
    Result[mIndex] := FBuffer[AHead + cMaskBytes + mIndex] xor FBuffer[AHead + mIndex mod cMaskBytes];
  end;
end;

function TAtlasLinkReader.TakeFrame(out AOpcode: Byte; out AFin: Boolean; out APayload: TBytes;
  out AEvent: TAtlasLinkEvent): Boolean;
var
  mHead: Integer;
  mLength: UInt64;
begin
  Result := False;
  APayload := nil;
  AOpcode := 0;
  AFin := False;
  if not HeadValid(AEvent) or not PayloadLength(mHead, mLength, AEvent) then
  begin
    Exit;
  end;
  if FCount < mHead + cMaskBytes + Integer(mLength) then
  begin
    Exit;
  end;
  AFin := FBuffer[0] and cFinBit <> 0;
  AOpcode := FBuffer[0] and cOpcodeMask;
  APayload := Unmask(mHead, mLength);
  Consume(mHead + cMaskBytes + Integer(mLength));
  Result := True;
end;

function TAtlasLinkReader.ControlEvent(AOpcode: Byte; AFin: Boolean; const APayload: TBytes): TAtlasLinkEvent;
begin
  Result := Default(TAtlasLinkEvent);
  if not AFin or (Length(APayload) > cMaxControlPayload) then
  begin
    Result := Fail(cReasonControl);
    Exit;
  end;
  case AOpcode of
    cOpPing:
      begin
        Result.Kind := TAtlasLinkEventKind.Ping;
        Result.Payload := APayload;
      end;
    cOpClose:
      begin
        FDone := True;
        Result.Kind := TAtlasLinkEventKind.Close;
      end;
  end;
end;

function TAtlasLinkReader.DataEvent(AOpcode: Byte; AFin: Boolean; const APayload: TBytes): TAtlasLinkEvent;
begin
  Result := Default(TAtlasLinkEvent);
  if (AOpcode = cOpContinuation) <> FInMessage then
  begin
    Result := Fail(cReasonContinuation);
    Exit;
  end;
  if AOpcode <> cOpContinuation then
  begin
    FInMessage := True;
    FMessageIsText := AOpcode = cOpText;
    FMessageCount := 0;
  end;
  if FMessageCount + Length(APayload) > cMaxMessageBytes then
  begin
    Result := Fail(cReasonTooBig);
    Exit;
  end;
  AppendMessage(APayload);
  if not AFin then
  begin
    Exit;
  end;
  FInMessage := False;
  // Binärnachrichten kennt das Protokoll nicht; sie werden übergangen.
  if FMessageIsText then
  begin
    Result.Kind := TAtlasLinkEventKind.Text;
    Result.Text := TEncoding.UTF8.GetString(FMessage, 0, FMessageCount);
  end;
  FMessageCount := 0;
end;

function TAtlasLinkReader.Next: TAtlasLinkEvent;
var
  mOpcode: Byte;
  mFin: Boolean;
  mPayload: TBytes;
begin
  Result := Default(TAtlasLinkEvent);
  while not FDone and TakeFrame(mOpcode, mFin, mPayload, Result) do
  begin
    case mOpcode of
      cOpContinuation, cOpText, cOpBinary:
        Result := DataEvent(mOpcode, mFin, mPayload);
      cOpClose, cOpPing:
        Result := ControlEvent(mOpcode, mFin, mPayload);
      cOpPong:
        Result := Default(TAtlasLinkEvent);
    else
      Result := Fail(cReasonOpcode);
    end;
    if Result.Kind <> TAtlasLinkEventKind.None then
    begin
      Exit;
    end;
  end;
end;

{ TAtlasLinkWriter }

/// <summary>AValue in ACount Bytes ab AStart, höchstwertiges Byte zuerst.</summary>
procedure PutBigEndian(var ABytes: TBytes; AStart, ACount: Integer; AValue: UInt64);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ACount - 1 do
  begin
    ABytes[AStart + ACount - 1 - mIndex] := Byte(AValue shr (cBitsPerByte * mIndex));
  end;
end;

class function TAtlasLinkWriter.Frame(AOpcode: Byte; const APayload: TBytes): TBytes;
var
  mLength: UInt64;
  mExtra: Integer;
begin
  mLength := Length(APayload);
  mExtra := 0;
  if mLength >= cLength16 then
  begin
    mExtra := cLength16Bytes;
    if mLength > cMax16 then
    begin
      mExtra := cLength64Bytes;
    end;
  end;
  Result := nil;
  SetLength(Result, cHeadMin + mExtra + Integer(mLength));
  Result[0] := cFinBit or (AOpcode and cOpcodeMask);
  case mExtra of
    cLength16Bytes:
      Result[1] := cLength16;
    cLength64Bytes:
      Result[1] := cLength64;
  else
    Result[1] := Byte(mLength);
  end;
  PutBigEndian(Result, cHeadMin, mExtra, mLength);
  if mLength > 0 then
  begin
    Move(APayload[0], Result[cHeadMin + mExtra], mLength);
  end;
end;

class function TAtlasLinkWriter.Text(const AText: string): TBytes;
begin
  Result := Frame(TAtlasLinkReader.cOpText, TEncoding.UTF8.GetBytes(AText));
end;

class function TAtlasLinkWriter.Pong(const APayload: TBytes): TBytes;
begin
  Result := Frame(TAtlasLinkReader.cOpPong, APayload);
end;

class function TAtlasLinkWriter.Close(ACode: Word): TBytes;
var
  mPayload: TBytes;
begin
  mPayload := nil;
  SetLength(mPayload, SizeOf(ACode));
  PutBigEndian(mPayload, 0, SizeOf(ACode), ACode);
  Result := Frame(TAtlasLinkReader.cOpClose, mPayload);
end;

end.
