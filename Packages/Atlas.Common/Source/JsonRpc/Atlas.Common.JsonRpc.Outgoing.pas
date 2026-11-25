unit Atlas.Common.JsonRpc.Outgoing;

// Eigene Anfragen an die Gegenseite, auf deren Antwort der Aufrufer wartet (#2620, MCP elicitation/create):
// Request schreibt die Anfrage mit eigener id und blockiert, bis die Antwort da ist, die Zeit abläuft oder die
// Verbindung endet. Die Antwort fängt der Lese-Thread der Verbindung ab (Observe), bevor sie in den Posteingang
// käme: Ein Werkzeug, das in der Nachrichtenschleife läuft und auf die Antwort wartet, hielte die Schleife sonst
// selbst an. Anfragen ohne Wartenden (ExpectResponse des Dispatchers) bleiben beim Dispatcher.
// Das Objekt ist referenzgezählt und threadsicher; Lese-Thread und Aufrufer halten je eine Referenz.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Ausgang einer eigenen Anfrage.</summary>
  TJsonRpcOutgoingOutcome = (Answered, TimedOut, Closed);
{$SCOPEDENUMS OFF}

  IJsonRpcOutgoing = interface
    ['{6C2B8E41-0F3D-4A97-B5E2-8D17A4C93F60}']
    /// <summary>Lese-Thread: True, wenn AMessage die Antwort auf eine wartende eigene Anfrage ist; sie gehört dann
    /// diesem Objekt. Sonst False, AMessage bleibt beim Aufrufer.</summary>
    function Observe(AMessage: TJSONObject): Boolean;
    /// <summary>Sendet AMethod mit AParams (geht in die Nachricht über) und wartet höchstens ATimeoutMs auf die
    /// Antwort. Bei Answered gehört AResponse (die ganze Antwort mit result oder error) dem Aufrufer.</summary>
    function Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      out AResponse: TJSONObject): TJsonRpcOutgoingOutcome;
    /// <summary>Verbindung beendet: Wartende kehren mit Closed zurück, neue Anfragen ebenso.</summary>
    procedure CloseAll;
  end;

  TJsonRpcOutgoing = class(TInterfacedObject, IJsonRpcOutgoing)
  private type
    TWaiter = class
    public
      Signal: TEvent;
      Response: TJSONObject;
      constructor Create;
      destructor Destroy; override;
    end;
  private
    FTransport: IJsonRpcTransport;
    FPrefix: string;
    FLock: TCriticalSection;
    FWaiters: TObjectDictionary<string, TWaiter>;
    FNextId: Integer;
    FClosed: Boolean;
    function Register(out AId: string; out AWaiter: TWaiter): Boolean;
    function Take(const AId: string; out AResponse: TJSONObject): Boolean;
  public
    /// <summary>ATransport schreibt die Anfragen; APrefix vor jeder id (eigene ids von denen der Gegenseite
    /// unterscheiden, z. B. 'atlas/out/').</summary>
    constructor Create(const ATransport: IJsonRpcTransport; const APrefix: string);
    destructor Destroy; override;
    function Observe(AMessage: TJSONObject): Boolean;
    function Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      out AResponse: TJSONObject): TJsonRpcOutgoingOutcome;
    procedure CloseAll;
    /// <summary>Kennung einer Antwort: id als Text, wenn AMessage eine Antwort ist (id, kein method); sonst ''.
    /// </summary>
    class function ResponseId(AMessage: TJSONObject): string; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Messages;

{ TJsonRpcOutgoing.TWaiter }

constructor TJsonRpcOutgoing.TWaiter.Create;
begin
  inherited Create;
  Signal := TEvent.Create(nil, True, False, '');
end;

destructor TJsonRpcOutgoing.TWaiter.Destroy;
begin
  Response.Free;
  Signal.Free;
  inherited Destroy;
end;

{ TJsonRpcOutgoing }

constructor TJsonRpcOutgoing.Create(const ATransport: IJsonRpcTransport; const APrefix: string);
begin
  inherited Create;
  FTransport := ATransport;
  FPrefix := APrefix;
  FLock := TCriticalSection.Create;
  FWaiters := TObjectDictionary<string, TWaiter>.Create([doOwnsValues]);
end;

destructor TJsonRpcOutgoing.Destroy;
begin
  FWaiters.Free;
  FLock.Free;
  inherited Destroy;
end;

class function TJsonRpcOutgoing.ResponseId(AMessage: TJSONObject): string;
var
  mId: TJSONValue;
begin
  Result := '';
  if (AMessage = nil) or (AMessage.GetValue('method') <> nil) then
  begin
    Exit;
  end;
  mId := AMessage.GetValue('id');
  if (mId is TJSONString) or (mId is TJSONNumber) then
  begin
    Result := mId.Value;
  end;
end;

function TJsonRpcOutgoing.Register(out AId: string; out AWaiter: TWaiter): Boolean;
begin
  FLock.Acquire;
  try
    Result := not FClosed;
    AWaiter := nil;
    AId := '';
    if Result then
    begin
      Inc(FNextId);
      AId := FPrefix + IntToStr(FNextId);
      AWaiter := TWaiter.Create;
      FWaiters.Add(AId, AWaiter);
    end;
  finally
    FLock.Release;
  end;
end;

function TJsonRpcOutgoing.Take(const AId: string; out AResponse: TJSONObject): Boolean;
var
  mWaiter: TWaiter;
begin
  FLock.Acquire;
  try
    AResponse := nil;
    Result := FWaiters.TryGetValue(AId, mWaiter) and (mWaiter.Response <> nil);
    if Result then
    begin
      AResponse := mWaiter.Response;
      mWaiter.Response := nil;
    end;
    FWaiters.Remove(AId);
  finally
    FLock.Release;
  end;
end;

function TJsonRpcOutgoing.Observe(AMessage: TJSONObject): Boolean;
var
  mId: string;
  mWaiter: TWaiter;
begin
  mId := ResponseId(AMessage);
  Result := False;
  if mId = '' then
  begin
    Exit;
  end;
  FLock.Acquire;
  try
    Result := FWaiters.TryGetValue(mId, mWaiter) and (mWaiter.Response = nil);
    if Result then
    begin
      mWaiter.Response := AMessage;
      mWaiter.Signal.SetEvent;
    end;
  finally
    FLock.Release;
  end;
end;

function TJsonRpcOutgoing.Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
  out AResponse: TJSONObject): TJsonRpcOutgoingOutcome;
var
  mId: string;
  mWaiter: TWaiter;
  mMessage: TJSONObject;
begin
  AResponse := nil;
  if not Register(mId, mWaiter) then
  begin
    AParams.Free;
    Exit(TJsonRpcOutgoingOutcome.Closed);
  end;
  mMessage := TJsonRpcMessages.Notification(AMethod, AParams);
  try
    mMessage.AddPair('id', mId);
    try
      FTransport.WriteMessage(mMessage);
    except
      Take(mId, AResponse);
      raise;
    end;
  finally
    mMessage.Free;
  end;
  // Der Wartende gehört dem Verzeichnis; Take entfernt ihn erst nach dem Warten.
  mWaiter.Signal.WaitFor(ATimeoutMs);
  if Take(mId, AResponse) then
  begin
    Exit(TJsonRpcOutgoingOutcome.Answered);
  end;
  FLock.Acquire;
  try
    if FClosed then
    begin
      Exit(TJsonRpcOutgoingOutcome.Closed);
    end;
  finally
    FLock.Release;
  end;
  Result := TJsonRpcOutgoingOutcome.TimedOut;
end;

procedure TJsonRpcOutgoing.CloseAll;
var
  mWaiter: TWaiter;
begin
  FLock.Acquire;
  try
    FClosed := True;
    for mWaiter in FWaiters.Values do
    begin
      mWaiter.Signal.SetEvent;
    end;
  finally
    FLock.Release;
  end;
end;

end.
