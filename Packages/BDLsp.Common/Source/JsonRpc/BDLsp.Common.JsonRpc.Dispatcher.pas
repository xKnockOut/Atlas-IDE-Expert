unit BDLsp.Common.JsonRpc.Dispatcher;

// Verteilt eingehende JSON-RPC-Nachrichten anhand des Methodennamens auf
// registrierte Handler. Anfragen (mit id) erhalten immer eine Antwort,
// Benachrichtigungen (ohne id) nie.
//
// Normale Handler laufen im aufrufenden Thread, in der Reihenfolge der
// Nachrichten. Nebenläufige Handler (RegisterConcurrentRequest) übergibt der
// Dispatcher dem Scheduler; ihre Antwort geht später über den Responder.
// Ohne Scheduler laufen auch sie im aufrufenden Thread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.PendingRequests,
  BDLsp.Common.JsonRpc.Watchdog,
  BDLsp.Common.JsonRpc.Statistics;

type
  TJsonRpcDispatcher = class
  private
    FRequestHandlers: TDictionary<string, TJsonRpcRequestHandler>;
    FConcurrentHandlers: TDictionary<string, TJsonRpcConcurrentRequestHandler>;
    FNotificationHandlers: TDictionary<string, TJsonRpcNotificationHandler>;
    FGuard: TJsonRpcGuard;
    FScheduler: TJsonRpcScheduler;
    FResponder: TJsonRpcResponder;
    FPending: IJsonRpcPendingRequests;
    FWatchdog: IJsonRpcWatchdog;
    FOnRequestFailed: TJsonRpcRequestFailedEvent;
    FStatistics: IJsonRpcStatistics;
    FLastMessage: string;
    function DispatchRequest(const AId: TJSONValue; const AMethod: string; const AParams: TJSONValue): TJSONObject;
    procedure DispatchNotification(const AMethod: string; const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Registriert den Handler einer Anfrage; ein vorhandener wird ersetzt.</summary>
    procedure RegisterRequest(const AMethod: string; const AHandler: TJsonRpcRequestHandler);
    /// <summary>
    /// Registriert den Handler einer Anfrage, die nebenläufig in einem Worker-Thread
    /// laufen darf; ein vorhandener Handler (auch ein normaler) wird ersetzt.
    /// </summary>
    procedure RegisterConcurrentRequest(const AMethod: string; const AHandler: TJsonRpcConcurrentRequestHandler);
    /// <summary>Registriert den Handler einer Benachrichtigung; ein vorhandener wird ersetzt.</summary>
    procedure RegisterNotification(const AMethod: string; const AHandler: TJsonRpcNotificationHandler);
    /// <summary>
    /// Verarbeitet eine Nachricht und liefert die Antwort, die der Aufrufer
    /// sendet und freigibt, oder nil, wenn keine Antwort fällig ist oder sie
    /// später über den Responder kommt.
    /// Fehler in Anfrage-Handlern werden zur Fehlerantwort; Fehler in
    /// Benachrichtigungs-Handlern gehen an den Aufrufer.
    /// </summary>
    function DispatchMessage(const AMessage: TJSONObject): TJSONObject;
    /// <summary>Optionale Prüfung vor jeder Verteilung, z. B. für den Lebenszyklus des Servers.</summary>
    property Guard: TJsonRpcGuard read FGuard write FGuard;
    /// <summary>Führt nebenläufige Anfragen aus. Wirkt nur zusammen mit Responder.</summary>
    property Scheduler: TJsonRpcScheduler read FScheduler write FScheduler;
    /// <summary>Sendet Antworten nebenläufiger Anfragen.</summary>
    property Responder: TJsonRpcResponder read FResponder write FResponder;
    /// <summary>Offene Anfragen und $/cancelRequest, gemeinsam mit dem Lese-Thread genutzt.</summary>
    property PendingRequests: IJsonRpcPendingRequests read FPending;
    /// <summary>Optionales Zeitlimit für Anfragen (siehe TJsonRpcWatchdog).</summary>
    property Watchdog: IJsonRpcWatchdog read FWatchdog write FWatchdog;
    /// <summary>
    /// Wird bei unerwarteten Fehlern eines Anfrage-Handlers aufgerufen (nicht bei
    /// EJsonRpcError), auch aus Worker-Threads; z. B. für ein Absturzprotokoll.
    /// </summary>
    property OnRequestFailed: TJsonRpcRequestFailedEvent read FOnRequestFailed write FOnRequestFailed;
    /// <summary>Methode und id der zuletzt verteilten Nachricht, für Absturzprotokolle.</summary>
    property LastMessage: string read FLastMessage;
    /// <summary>Optional: misst die Antwortzeit jeder Anfrage (#28).</summary>
    property Statistics: IJsonRpcStatistics read FStatistics write FStatistics;
  end;

implementation

uses
  System.Diagnostics,
  BDLsp.Common.JsonRpc.Messages;

function ErrorResponse(const AId: TJSONValue; const AError: Exception): TJSONObject;
begin
  if AError is EJsonRpcError then
    Result := TJsonRpcMessages.Error(AId, EJsonRpcError(AError).Code, AError.Message)
  else
    Result := TJsonRpcMessages.Error(AId, TJsonRpcErrorCode.InternalError, AError.ClassName + ': ' + AError.Message);
end;

// Meldet unerwartete Fehler; Fehler beim Melden selbst werden verschluckt.
procedure NotifyFailed(const AOnFailed: TJsonRpcRequestFailedEvent; const AMethod: string;
  const AParams: TJSONValue; const AError: Exception);
begin
  if Assigned(AOnFailed) and not (AError is EJsonRpcError) then
    try
      AOnFailed(AMethod, AParams, AError);
    except
      // Das Protokollieren darf die Antwort nicht verhindern.
    end;
end;

function RunConcurrent(const AId, AParams: TJSONValue; const AMethod: string;
  const AHandler: TJsonRpcConcurrentRequestHandler; const AToken: IJsonRpcCancellationToken;
  const AOnFailed: TJsonRpcRequestFailedEvent; const AStatistics: IJsonRpcStatistics): TJSONObject;
var
  Watch: TStopwatch;
  Failed: Boolean;
begin
  Watch := TStopwatch.StartNew;
  Failed := False;
  try
    AToken.ThrowIfCancellationRequested;
    Result := TJsonRpcMessages.Response(AId, AHandler(AParams, AToken));
  except
    on E: Exception do
    begin
      Failed := True;
      NotifyFailed(AOnFailed, AMethod, AParams, E);
      Result := ErrorResponse(AId, E);
    end;
  end;
  if AStatistics <> nil then
    AStatistics.Add(AMethod, Watch.ElapsedMilliseconds, Failed);
end;

// Übergibt eine nebenläufige Anfrage dem Scheduler. Die Arbeit hält nur
// Referenzen auf referenzgezählte Objekte und Kopien von id und Parametern,
// nicht auf den Dispatcher.
procedure ScheduleConcurrent(const AScheduler: TJsonRpcScheduler; const AResponder: TJsonRpcResponder;
  const APending: IJsonRpcPendingRequests; const AHandler: TJsonRpcConcurrentRequestHandler;
  const AId, AParams: TJSONValue; const AToken: IJsonRpcCancellationToken; const AMethod: string;
  const AWatchdog: IJsonRpcWatchdog; const AOnFailed: TJsonRpcRequestFailedEvent;
  const AStatistics: IJsonRpcStatistics);
var
  Method: string;
  Statistics: IJsonRpcStatistics;
  Watchdog: IJsonRpcWatchdog;
  OnFailed: TJsonRpcRequestFailedEvent;
  Id: TJSONValue;
  Params: TJSONValue;
  Responder: TJsonRpcResponder;
  Pending: IJsonRpcPendingRequests;
  Handler: TJsonRpcConcurrentRequestHandler;
  Token: IJsonRpcCancellationToken;
begin
  Responder := AResponder;
  Pending := APending;
  Handler := AHandler;
  Token := AToken;
  Method := AMethod;
  Watchdog := AWatchdog;
  OnFailed := AOnFailed;
  Statistics := AStatistics;
  Id := TJSONValue(AId.Clone);
  Params := nil;
  if AParams <> nil then
    Params := TJSONValue(AParams.Clone);

  Pending.BeginWork;
  try
    AScheduler(
      procedure
      var
        Response: TJSONObject;
        Ticket: Int64;
      begin
        try
          Ticket := 0;
          if Watchdog <> nil then
            Ticket := Watchdog.Watch(Id, Method);
          try
            Response := RunConcurrent(Id, Params, Method, Handler, Token, OnFailed, Statistics);
          finally
            if Watchdog <> nil then
              Watchdog.Unwatch(Ticket);
            Pending.Release(Id, Token);
            Params.Free;
            Id.Free;
          end;
          Responder(Response);
        finally
          Pending.EndWork;
        end;
      end);
  except
    Params.Free;
    Id.Free;
    Pending.EndWork;
    raise;
  end;
end;

{ TJsonRpcDispatcher }

constructor TJsonRpcDispatcher.Create;
begin
  inherited Create;
  FRequestHandlers := TDictionary<string, TJsonRpcRequestHandler>.Create;
  FConcurrentHandlers := TDictionary<string, TJsonRpcConcurrentRequestHandler>.Create;
  FPending := TJsonRpcPendingRequests.Create;
  FNotificationHandlers := TDictionary<string, TJsonRpcNotificationHandler>.Create;
end;

destructor TJsonRpcDispatcher.Destroy;
begin
  FNotificationHandlers.Free;
  FConcurrentHandlers.Free;
  FRequestHandlers.Free;
  inherited;
end;

procedure TJsonRpcDispatcher.RegisterRequest(const AMethod: string; const AHandler: TJsonRpcRequestHandler);
begin
  FConcurrentHandlers.Remove(AMethod);
  FRequestHandlers.AddOrSetValue(AMethod, AHandler);
end;

procedure TJsonRpcDispatcher.RegisterConcurrentRequest(const AMethod: string;
  const AHandler: TJsonRpcConcurrentRequestHandler);
begin
  FRequestHandlers.Remove(AMethod);
  FConcurrentHandlers.AddOrSetValue(AMethod, AHandler);
end;

procedure TJsonRpcDispatcher.RegisterNotification(const AMethod: string; const AHandler: TJsonRpcNotificationHandler);
begin
  FNotificationHandlers.AddOrSetValue(AMethod, AHandler);
end;

function TJsonRpcDispatcher.DispatchMessage(const AMessage: TJSONObject): TJSONObject;
var
  Id: TJSONValue;
  MethodValue: TJSONValue;
  Params: TJSONValue;
begin
  Id := AMessage.GetValue('id');
  MethodValue := AMessage.GetValue('method');
  Params := AMessage.GetValue('params');

  if MethodValue = nil then
  begin
    // Antworten der Gegenseite auf eigene Anfragen werden noch nicht ausgewertet.
    if (AMessage.GetValue('result') <> nil) or (AMessage.GetValue('error') <> nil) then
      Exit(nil);
    Exit(TJsonRpcMessages.Error(Id, TJsonRpcErrorCode.InvalidRequest, 'Feld "method" fehlt'));
  end;

  if not (MethodValue is TJSONString) then
  begin
    if Id = nil then
      Exit(nil);
    Exit(TJsonRpcMessages.Error(Id, TJsonRpcErrorCode.InvalidRequest, 'Feld "method" ist keine Zeichenkette'));
  end;

  if Id = nil then
    FLastMessage := MethodValue.Value
  else
    FLastMessage := MethodValue.Value + ' (id ' + Id.ToJSON + ')';

  if Id = nil then
  begin
    // $/cancelRequest ist Teil des Protokolls und gilt in jedem Zustand. Über
    // die Verbindung erledigt das schon der Lese-Thread (IJsonRpcPendingRequests.Observe).
    if MethodValue.Value = JsonRpcCancelRequestMethod then
    begin
      FPending.Observe(AMessage);
      Exit(nil);
    end;
    DispatchNotification(MethodValue.Value, Params);
    Result := nil;
  end
  else
    Result := DispatchRequest(Id, MethodValue.Value, Params);
end;

function TJsonRpcDispatcher.DispatchRequest(const AId: TJSONValue; const AMethod: string;
  const AParams: TJSONValue): TJSONObject;
var
  Handler: TJsonRpcRequestHandler;
  ConcurrentHandler: TJsonRpcConcurrentRequestHandler;
  Token: IJsonRpcCancellationToken;
  Scheduled: Boolean;
  Ticket: Int64;
  Watch: TStopwatch;
  Measured: Boolean;
begin
  Token := FPending.Acquire(AId);
  Scheduled := False;
  Measured := False;
  Watch := TStopwatch.StartNew;
  Ticket := 0;
  try
    try
      if Assigned(FGuard) then
        FGuard(AMethod, True);
      if FConcurrentHandlers.TryGetValue(AMethod, ConcurrentHandler) then
      begin
        if Assigned(FScheduler) and Assigned(FResponder) then
        begin
          ScheduleConcurrent(FScheduler, FResponder, FPending, ConcurrentHandler, AId, AParams, Token, AMethod,
            FWatchdog, FOnRequestFailed, FStatistics);
          Scheduled := True;
          Exit(nil);
        end;
        // Ohne Scheduler läuft die Anfrage hier; auch dann gilt das Zeitlimit.
        if FWatchdog <> nil then
          Ticket := FWatchdog.Watch(AId, AMethod);
        Exit(RunConcurrent(AId, AParams, AMethod, ConcurrentHandler, Token, FOnRequestFailed, FStatistics));
      end;
      if not FRequestHandlers.TryGetValue(AMethod, Handler) then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.MethodNotFound, 'Methode nicht unterstützt: ' + AMethod);
      // Abgebrochen, während die Anfrage noch in der Warteschlange stand.
      Token.ThrowIfCancellationRequested;
      if FWatchdog <> nil then
        Ticket := FWatchdog.Watch(AId, AMethod);
      Measured := True;
      Result := TJsonRpcMessages.Response(AId, Handler(AParams));
      if FStatistics <> nil then
        FStatistics.Add(AMethod, Watch.ElapsedMilliseconds, False);
    except
      on E: Exception do
      begin
        if Measured and (FStatistics <> nil) then
          FStatistics.Add(AMethod, Watch.ElapsedMilliseconds, True);
        NotifyFailed(FOnRequestFailed, AMethod, AParams, E);
        Result := ErrorResponse(AId, E);
      end;
    end;
  finally
    if FWatchdog <> nil then
      FWatchdog.Unwatch(Ticket);
    if not Scheduled then
      FPending.Release(AId, Token);
  end;
end;

procedure TJsonRpcDispatcher.DispatchNotification(const AMethod: string; const AParams: TJSONValue);
var
  Handler: TJsonRpcNotificationHandler;
begin
  // Benachrichtigungen erhalten keine Antwort, auch keine Fehlerantwort.
  // Unbekannte und vom Guard abgelehnte Benachrichtigungen werden verworfen.
  // Andere Exceptions eines Handlers gehen an den Aufrufer.
  if Assigned(FGuard) then
    try
      FGuard(AMethod, False);
    except
      on EJsonRpcError do
        Exit;
    end;
  if FNotificationHandlers.TryGetValue(AMethod, Handler) then
    Handler(AParams);
end;

end.
