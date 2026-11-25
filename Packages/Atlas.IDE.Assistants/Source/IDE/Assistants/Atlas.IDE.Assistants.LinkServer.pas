unit Atlas.IDE.Assistants.LinkServer;

// Assistenten-Kopplung (#2377), Adapter zu Windows Sockets: ein WebSocket-Server nur auf 127.0.0.1 mit einem
// zufälligen Port aus dem Bereich, den der Client erwartet. Ein Thread nimmt Verbindungen an, je Verbindung liest
// ein Thread Handschlag und Rahmen (Atlas.Core.Assistants.LinkFrames). Ohne gültiges Token, mit Origin eines
// Browsers oder ohne Upgrade lehnt er ab. Ping beantwortet der Lesethread selbst; Textnachrichten, Verbinden und
// Trennen legt er in eine Liste, die der Hauptthread mit TakeEvents abholt (über einen Zeitgeber der Kopplung,
// nicht über TAtlasMainThread: Nach Destroy erreicht so nichts mehr das Modul, ADR 0017 Regel 3).
// Gesendet wird aus dem Hauptthread (Send) unter einer Sperre je Verbindung, damit kein Pong mitten in einen
// Rahmen gerät. Destroy schließt den Port, trennt alle Verbindungen und wartet auf alle Threads.
// Die Funktionen von ws2_32.dll sind hier selbst deklariert (feste Signaturen für Delphi 12 und 13).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TAtlasLinkSocket = NativeUInt;

  {$SCOPEDENUMS ON}
  TAtlasLinkServerEventKind = (Connected, Message, Disconnected);
  {$SCOPEDENUMS OFF}

  TAtlasLinkServerEvent = record
    Kind: TAtlasLinkServerEventKind;
    Connection: Integer;
    Text: string;
  end;

  TAtlasLinkServer = class
  public const
    /// <summary>Höchstens so viele verbundene Clients; weitere werden abgelehnt.</summary>
    cMaxClients = 8;
    /// <summary>So lange darf der Handschlag dauern.</summary>
    cHandshakeMs = 10000;
    /// <summary>Versuche, einen freien Port zu finden.</summary>
    cPortAttempts = 20;
  private type
    TClient = class(TThread)
    private
      FServer: TAtlasLinkServer;
      FSocket: TAtlasLinkSocket;
      FId: Integer;
      FSendLock: TCriticalSection;
      FOpened: Boolean;
      function Handshake(out ARest: TBytes): Boolean;
      procedure ReadFrames(const ARest: TBytes);
    protected
      procedure Execute; override;
    public
      constructor Create(AServer: TAtlasLinkServer; ASocket: TAtlasLinkSocket; AId: Integer);
      destructor Destroy; override;
      function SendBytes(const ABytes: TBytes): Boolean;
      /// <summary>Verbindung beenden: Lesen wacht auf, der Thread endet.</summary>
      procedure Cut;
    end;

    TListener = class(TThread)
    private
      FServer: TAtlasLinkServer;
    protected
      procedure Execute; override;
    public
      constructor Create(AServer: TAtlasLinkServer);
    end;
  private
    FToken: string;
    FTokenHeader: string;
    FStarted: Boolean;
    FListen: TAtlasLinkSocket;
    FPort: Integer;
    FListener: TListener;
    FLock: TCriticalSection;
    FClients: TList<TClient>;
    FEvents: TList<TAtlasLinkServerEvent>;
    FNextId: Integer;
    FClosing: Boolean;
    procedure Post(AKind: TAtlasLinkServerEventKind; AConnection: Integer; const AText: string);
    procedure Accepted(ASocket: TAtlasLinkSocket);
    function FindClient(AConnection: Integer): TClient;
    /// <summary>Beendete Lesethreads freigeben (Hauptthread).</summary>
    procedure Reap;
    function Bind(APort: Integer): Boolean;
  public
    /// <summary>AToken: erwartetes Token; ATokenHeader: Name des Kopfs, in dem es kommt.</summary>
    constructor Create(const AToken, ATokenHeader: string);
    destructor Destroy; override;
    /// <summary>Port öffnen, ARandom liefert Zufallszahlen für den Port. False, wenn kein Port frei war.</summary>
    function Open(const ARandom: TFunc<Cardinal>): Boolean;
    /// <summary>Wartende Ereignisse (Hauptthread); gibt beendete Verbindungen frei.</summary>
    function TakeEvents: TArray<TAtlasLinkServerEvent>;
    /// <summary>Text an die Verbindung AConnection; False, wenn sie nicht mehr besteht.</summary>
    function Send(AConnection: Integer; const AText: string): Boolean;
    /// <summary>Verbindung AConnection trennen (Statusfeld „Trennen“).</summary>
    procedure Drop(AConnection: Integer);
    property Port: Integer read FPort;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Assistants.LinkFrames,
  Atlas.Core.Assistants.LinkLock;

const
  cReasonHeaderTooLong = 'header too long';
  cReasonTooManyClients = 'too many connections';

type
  TWsAddress = record
    Family: Word;
    Port: Word;
    Address: Cardinal;
    Zero: array[0..7] of Byte;
  end;

const
  cWinsock = 'ws2_32.dll';
  cWinsockVersion = $0202;
  cInvalidSocket = TAtlasLinkSocket(not NativeUInt(0));
  cSocketError = -1;
  cAfInet = 2;
  cSockStream = 1;
  cIpProtoTcp = 6;
  cSolSocket = $FFFF;
  /// <summary>SO_EXCLUSIVEADDRUSE (~SO_REUSEADDR): kein anderer Prozess kann den Port mitbenutzen.</summary>
  cSoExclusiveAddrUse = Integer(not 4);
  cSoRcvTimeo = $1006;
  cTcpNoDelay = 1;
  cSdBoth = 2;
  cLoopback = $7F000001;
  cListenBacklog = 4;
  cReadBytes = 65536;
  cWsaDataBytes = 1024;

function WsStartup(AVersion: Word; AData: Pointer): Integer; stdcall; external cWinsock name 'WSAStartup';
function WsCleanup: Integer; stdcall; external cWinsock name 'WSACleanup';
function WsSocket(AFamily, AType, AProtocol: Integer): TAtlasLinkSocket; stdcall; external cWinsock name 'socket';
function WsBind(ASocket: TAtlasLinkSocket; AAddress: Pointer; ALength: Integer): Integer; stdcall;
  external cWinsock name 'bind';
function WsListen(ASocket: TAtlasLinkSocket; ABacklog: Integer): Integer; stdcall; external cWinsock name 'listen';
function WsAccept(ASocket: TAtlasLinkSocket; AAddress: Pointer; ALength: PInteger): TAtlasLinkSocket; stdcall;
  external cWinsock name 'accept';
function WsRecv(ASocket: TAtlasLinkSocket; ABuffer: Pointer; ALength, AFlags: Integer): Integer; stdcall;
  external cWinsock name 'recv';
function WsSend(ASocket: TAtlasLinkSocket; ABuffer: Pointer; ALength, AFlags: Integer): Integer; stdcall;
  external cWinsock name 'send';
function WsClose(ASocket: TAtlasLinkSocket): Integer; stdcall; external cWinsock name 'closesocket';
function WsShutdown(ASocket: TAtlasLinkSocket; AHow: Integer): Integer; stdcall; external cWinsock name 'shutdown';
function WsSetOption(ASocket: TAtlasLinkSocket; ALevel, AName: Integer; AValue: Pointer; ALength: Integer): Integer;
  stdcall; external cWinsock name 'setsockopt';
function WsHostToNet16(AValue: Word): Word; stdcall; external cWinsock name 'htons';
function WsHostToNet32(AValue: Cardinal): Cardinal; stdcall; external cWinsock name 'htonl';

procedure SetOption(ASocket: TAtlasLinkSocket; ALevel, AName, AValue: Integer);
var
  mValue: Integer;
begin
  mValue := AValue;
  WsSetOption(ASocket, ALevel, AName, @mValue, SizeOf(mValue));
end;

function SendAll(ASocket: TAtlasLinkSocket; const ABytes: TBytes): Boolean;
var
  mDone: Integer;
  mSent: Integer;
begin
  mDone := 0;
  while mDone < Length(ABytes) do
  begin
    mSent := WsSend(ASocket, @ABytes[mDone], Length(ABytes) - mDone, 0);
    if mSent <= 0 then
    begin
      Result := False;
      Exit;
    end;
    Inc(mDone, mSent);
  end;
  Result := True;
end;

{ TAtlasLinkServer.TClient }

constructor TAtlasLinkServer.TClient.Create(AServer: TAtlasLinkServer; ASocket: TAtlasLinkSocket; AId: Integer);
begin
  FServer := AServer;
  FSocket := ASocket;
  FId := AId;
  FSendLock := TCriticalSection.Create;
  inherited Create(False);
end;

destructor TAtlasLinkServer.TClient.Destroy;
begin
  Cut;
  inherited Destroy;
  // Erst nach dem Ende des Threads schließen: Sonst könnte Windows die Nummer neu vergeben, während er noch liest.
  WsClose(FSocket);
  FSendLock.Free;
end;

function TAtlasLinkServer.TClient.SendBytes(const ABytes: TBytes): Boolean;
begin
  FSendLock.Enter;
  try
    Result := SendAll(FSocket, ABytes);
  finally
    FSendLock.Leave;
  end;
end;

procedure TAtlasLinkServer.TClient.Cut;
begin
  WsShutdown(FSocket, cSdBoth);
end;

function TAtlasLinkServer.TClient.Handshake(out ARest: TBytes): Boolean;
var
  mBuffer: TBytes;
  mCount: Integer;
  mRead: Integer;
  mHeader: Integer;
  mRequest: TAtlasLinkHandshake;
  mReason: string;
begin
  Result := False;
  ARest := nil;
  mBuffer := nil;
  SetLength(mBuffer, TAtlasLinkHandshake.cMaxHeaderBytes);
  mCount := 0;
  mHeader := 0;
  SetOption(FSocket, cSolSocket, cSoRcvTimeo, cHandshakeMs);
  while (mHeader = 0) and (mCount < Length(mBuffer)) and not Terminated do
  begin
    mRead := WsRecv(FSocket, @mBuffer[mCount], Length(mBuffer) - mCount, 0);
    if mRead <= 0 then
    begin
      Exit;
    end;
    Inc(mCount, mRead);
    mHeader := TAtlasLinkHandshake.HeaderLength(mBuffer, mCount);
  end;
  if mHeader = 0 then
  begin
    SendAll(FSocket, TEncoding.ASCII.GetBytes(TAtlasLinkHandshake.Refusal(TAtlasLinkHandshake.cStatusBadRequest,
      cReasonHeaderTooLong)));
    Exit;
  end;
  mRequest := TAtlasLinkHandshake.Parse(TEncoding.ASCII.GetString(mBuffer, 0, mHeader), FServer.FTokenHeader);
  if not mRequest.Admits(FServer.FToken, mReason) then
  begin
    SendAll(FSocket, TEncoding.ASCII.GetBytes(TAtlasLinkHandshake.Refusal(TAtlasLinkHandshake.cStatusUnauthorized,
      mReason)));
    Exit;
  end;
  SetOption(FSocket, cSolSocket, cSoRcvTimeo, 0);
  Result := SendBytes(TEncoding.ASCII.GetBytes(mRequest.Response));
  ARest := Copy(mBuffer, mHeader, mCount - mHeader);
end;

procedure TAtlasLinkServer.TClient.ReadFrames(const ARest: TBytes);
var
  mReader: TAtlasLinkReader;
  mBuffer: TBytes;
  mRead: Integer;
  mEvent: TAtlasLinkEvent;
begin
  mReader := TAtlasLinkReader.Create;
  try
    mReader.Feed(ARest, Length(ARest));
    mBuffer := nil;
    SetLength(mBuffer, cReadBytes);
    while not Terminated do
    begin
      mEvent := mReader.Next;
      case mEvent.Kind of
        TAtlasLinkEventKind.Text:
          FServer.Post(TAtlasLinkServerEventKind.Message, FId, mEvent.Text);
        TAtlasLinkEventKind.Ping:
          SendBytes(TAtlasLinkWriter.Pong(mEvent.Payload));
        TAtlasLinkEventKind.Close:
          begin
            SendBytes(TAtlasLinkWriter.Close(TAtlasLinkWriter.cCloseNormal));
            Exit;
          end;
        TAtlasLinkEventKind.Error:
          begin
            SendBytes(TAtlasLinkWriter.Close(TAtlasLinkWriter.cCloseProtocol));
            Exit;
          end;
      else
        mRead := WsRecv(FSocket, @mBuffer[0], Length(mBuffer), 0);
        if mRead <= 0 then
        begin
          Exit;
        end;
        mReader.Feed(mBuffer, mRead);
      end;
    end;
  finally
    mReader.Free;
  end;
end;

procedure TAtlasLinkServer.TClient.Execute;
var
  mRest: TBytes;
begin
  try
    try
      if Handshake(mRest) then
      begin
        FOpened := True;
        FServer.Post(TAtlasLinkServerEventKind.Connected, FId, '');
        ReadFrames(mRest);
      end;
    except
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Server, E);
    end;
  finally
    WsShutdown(FSocket, cSdBoth);
    if FOpened then
    begin
      FServer.Post(TAtlasLinkServerEventKind.Disconnected, FId, '');
    end;
  end;
end;

{ TAtlasLinkServer.TListener }

constructor TAtlasLinkServer.TListener.Create(AServer: TAtlasLinkServer);
begin
  FServer := AServer;
  inherited Create(False);
end;

procedure TAtlasLinkServer.TListener.Execute;
var
  mSocket: TAtlasLinkSocket;
begin
  try
    while not Terminated do
    begin
      // Schließt Destroy den Port, kehrt accept mit Fehler zurück.
      mSocket := WsAccept(FServer.FListen, nil, nil);
      if mSocket = cInvalidSocket then
      begin
        Break;
      end;
      FServer.Accepted(mSocket);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Server, E);
  end;
end;

{ TAtlasLinkServer }

constructor TAtlasLinkServer.Create(const AToken, ATokenHeader: string);
var
  mData: TBytes;
begin
  inherited Create;
  FToken := AToken;
  FTokenHeader := ATokenHeader;
  FListen := cInvalidSocket;
  FLock := TCriticalSection.Create;
  FClients := TList<TClient>.Create;
  FEvents := TList<TAtlasLinkServerEvent>.Create;
  mData := nil;
  SetLength(mData, cWsaDataBytes);
  FStarted := WsStartup(cWinsockVersion, @mData[0]) = 0;
end;

destructor TAtlasLinkServer.Destroy;
var
  mClient: TClient;
  mClients: TArray<TClient>;
begin
  FLock.Enter;
  try
    FClosing := True;
    mClients := FClients.ToArray;
    FClients.Clear;
  finally
    FLock.Leave;
  end;
  if FListen <> cInvalidSocket then
  begin
    WsClose(FListen);
  end;
  if FListener <> nil then
  begin
    FListener.Terminate;
    FListener.WaitFor;
    FListener.Free;
  end;
  for mClient in mClients do
  begin
    mClient.Terminate;
    mClient.SendBytes(TAtlasLinkWriter.Close(TAtlasLinkWriter.cCloseGoingAway));
    mClient.Cut;
  end;
  for mClient in mClients do
  begin
    mClient.WaitFor;
    mClient.Free;
  end;
  FEvents.Free;
  FClients.Free;
  FLock.Free;
  if FStarted then
  begin
    WsCleanup;
  end;
  inherited Destroy;
end;

function TAtlasLinkServer.Bind(APort: Integer): Boolean;
var
  mAddress: TWsAddress;
begin
  Result := False;
  FListen := WsSocket(cAfInet, cSockStream, cIpProtoTcp);
  if FListen = cInvalidSocket then
  begin
    Exit;
  end;
  SetOption(FListen, cSolSocket, cSoExclusiveAddrUse, 1);
  mAddress := Default(TWsAddress);
  mAddress.Family := cAfInet;
  mAddress.Port := WsHostToNet16(Word(APort));
  mAddress.Address := WsHostToNet32(cLoopback);
  if (WsBind(FListen, @mAddress, SizeOf(mAddress)) = cSocketError) or
    (WsListen(FListen, cListenBacklog) = cSocketError) then
  begin
    WsClose(FListen);
    FListen := cInvalidSocket;
    Exit;
  end;
  FPort := APort;
  Result := True;
end;

function TAtlasLinkServer.Open(const ARandom: TFunc<Cardinal>): Boolean;
var
  mAttempt: Integer;
begin
  Result := False;
  if not FStarted then
  begin
    Exit;
  end;
  for mAttempt := 1 to cPortAttempts do
  begin
    if Bind(TAtlasLinkLock.PortOf(ARandom())) then
    begin
      FListener := TListener.Create(Self);
      Result := True;
      Exit;
    end;
  end;
end;

procedure TAtlasLinkServer.Accepted(ASocket: TAtlasLinkSocket);
var
  mRefused: Boolean;
begin
  SetOption(ASocket, cIpProtoTcp, cTcpNoDelay, 1);
  FLock.Enter;
  try
    mRefused := FClosing or (FClients.Count >= cMaxClients);
    if not mRefused then
    begin
      Inc(FNextId);
      FClients.Add(TClient.Create(Self, ASocket, FNextId));
    end;
  finally
    FLock.Leave;
  end;
  if mRefused then
  begin
    SendAll(ASocket, TEncoding.ASCII.GetBytes(TAtlasLinkHandshake.Refusal(TAtlasLinkHandshake.cStatusForbidden,
      cReasonTooManyClients)));
    WsShutdown(ASocket, cSdBoth);
    WsClose(ASocket);
  end;
end;

procedure TAtlasLinkServer.Post(AKind: TAtlasLinkServerEventKind; AConnection: Integer; const AText: string);
var
  mEvent: TAtlasLinkServerEvent;
begin
  mEvent.Kind := AKind;
  mEvent.Connection := AConnection;
  mEvent.Text := AText;
  FLock.Enter;
  try
    if not FClosing then
    begin
      FEvents.Add(mEvent);
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasLinkServer.FindClient(AConnection: Integer): TClient;
var
  mClient: TClient;
begin
  for mClient in FClients do
  begin
    if mClient.FId = AConnection then
    begin
      Result := mClient;
      Exit;
    end;
  end;
  Result := nil;
end;

procedure TAtlasLinkServer.Reap;
var
  mDone: TArray<TClient>;
  mClient: TClient;
  mIndex: Integer;
begin
  mDone := nil;
  FLock.Enter;
  try
    for mIndex := FClients.Count - 1 downto 0 do
    begin
      if FClients[mIndex].Finished then
      begin
        mDone := mDone + [FClients[mIndex]];
        FClients.Delete(mIndex);
      end;
    end;
  finally
    FLock.Leave;
  end;
  for mClient in mDone do
  begin
    mClient.WaitFor;
    mClient.Free;
  end;
end;

function TAtlasLinkServer.TakeEvents: TArray<TAtlasLinkServerEvent>;
begin
  FLock.Enter;
  try
    Result := FEvents.ToArray;
    FEvents.Clear;
  finally
    FLock.Leave;
  end;
  Reap;
end;

function TAtlasLinkServer.Send(AConnection: Integer; const AText: string): Boolean;
var
  mClient: TClient;
begin
  // Unter der Sperre der Liste: Reap gibt den Thread sonst womöglich gerade frei.
  FLock.Enter;
  try
    mClient := FindClient(AConnection);
    Result := (mClient <> nil) and not mClient.Finished and mClient.SendBytes(TAtlasLinkWriter.Text(AText));
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasLinkServer.Drop(AConnection: Integer);
var
  mClient: TClient;
begin
  FLock.Enter;
  try
    mClient := FindClient(AConnection);
    if mClient <> nil then
    begin
      mClient.SendBytes(TAtlasLinkWriter.Close(TAtlasLinkWriter.cCloseNormal));
      mClient.Cut;
    end;
  finally
    FLock.Leave;
  end;
end;

end.
