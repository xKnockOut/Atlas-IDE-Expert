unit Atlas.Common.JsonRpc.Dispatcher;

// Verteilt eingehende JSON-RPC-Nachrichten anhand des Methodennamens auf
// registrierte Handler. Anfragen (mit id) erhalten immer eine Antwort,
// Benachrichtigungen (ohne id) nie.
//
// Normale Handler laufen im aufrufenden Thread, in der Reihenfolge der
// Nachrichten. Nebenläufige Handler (RegisterConcurrentRequest) übergibt der
// Dispatcher dem Scheduler; ihre Antwort geht später über den Responder.
// Ohne Scheduler laufen auch sie im aufrufenden Thread. Ein normaler Handler
// mit Bedingung (RegisterConditionalRequest, #874) läuft nebenläufig,
// wenn die Bedingung für die Parameter gilt, etwa reine Lesebefehle von
// workspace/executeCommand, die sonst hinter einem Neuladen warten.
//
// Die Wartezeit einer Anfrage (AQueueMs im Beobachter) zählt ab dem Eingang
// beim Lese-Thread, wenn der Aufrufer sie mitgibt, sonst ab der Verteilung.
//
// Antworten der Gegenseite auf eigene Anfragen (etwa workspace/applyEdit an
// den Client, #397) gehen an den mit ExpectResponse gemeldeten Handler; ohne
// Handler werden sie verworfen.
//
// Absturzfälle (#1355): Recent bekommt jede eingehende Nachricht, damit ein
// Fall die letzten Nachrichten nennt; RequestGuard kann eine Anfrage anhand
// ihrer Parameter abweisen (Überspringen nach Absturz). Fängt ein Handler
// einen Stapelüberlauf, stellt der Dispatcher die Schutzseite des Threads
// wieder her (TStackGuard.AfterError), bevor er antwortet; sonst beendete der
// nächste Überlauf im selben Thread den Prozess hart, statt wieder als
// Ausnahme zu kommen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.Watchdog,
  Atlas.Common.JsonRpc.RecentMessages,
  Atlas.Common.JsonRpc.Statistics;

type
  /// <summary>Antwort der Gegenseite auf eine eigene Anfrage; läuft in der Nachrichtenschleife
  /// (DispatchMessage), AResponse gehört dem Dispatcher.</summary>
  TJsonRpcResponseHandler = reference to procedure(const AResponse: TJSONObject);

  /// <summary>Gilt die Bedingung, läuft ein normaler Handler nebenläufig (#874). Läuft in der
  /// Nachrichtenschleife; eine Ausnahme zählt als False.</summary>
  TJsonRpcConcurrentWhen = reference to function(const AParams: TJSONValue): Boolean;

  /// <summary>Beobachter je Anfrage (#647, Diagnoselog). Beide Aufrufe laufen im Thread des Handlers;
  /// Ausnahmen darin werden verschluckt.</summary>
  IJsonRpcRequestObserver = interface
    ['{9D41E6B2-0C7A-4F35-A8E3-6B2F5C1D7094}']
    /// <summary>Direkt vor dem Handler.</summary>
    procedure Started(const AMethod: string);
    /// <summary>Nach dem Handler: AResult bei Erfolg (gehört der Antwort), sonst AError.
    /// AQueueMs ist die Wartezeit vor dem Start, AElapsedMs die Laufzeit des Handlers.</summary>
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
  end;

  TJsonRpcDispatcher = class
  private
    FRequestHandlers: TDictionary<string, TJsonRpcRequestHandler>;
    FConcurrentHandlers: TDictionary<string, TJsonRpcConcurrentRequestHandler>;
    FConcurrentWhen: TDictionary<string, TJsonRpcConcurrentWhen>;
    FNotificationHandlers: TDictionary<string, TJsonRpcNotificationHandler>;
    FGuard: TJsonRpcGuard;
    FRequestGuard: TJsonRpcRequestGuard;
    FRecent: IJsonRpcRecentMessages;
    FScheduler: TJsonRpcScheduler;
    FResponder: TJsonRpcResponder;
    FPending: IJsonRpcPendingRequests;
    FWatchdog: IJsonRpcWatchdog;
    FOnRequestFailed: TJsonRpcRequestFailedEvent;
    FStatistics: IJsonRpcStatistics;
    FObserver: IJsonRpcRequestObserver;
    FLastMessage: string;
    FExpected: TDictionary<string, TJsonRpcResponseHandler>;
    function DispatchRequest(const AId: TJSONValue; const AMethod: string; const AParams: TJSONValue;
      AQueueMs: Int64): TJSONObject;
    /// <summary>Nebenläufiger Handler für AMethod: eigener oder normaler mit erfüllter Bedingung.</summary>
    function ConcurrentFor(const AMethod: string; const AParams: TJSONValue;
      out AHandler: TJsonRpcConcurrentRequestHandler): Boolean;
    procedure DispatchNotification(const AMethod: string; const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Registriert den Handler einer Anfrage; ein vorhandener wird ersetzt.</summary>
    procedure RegisterRequest(const AMethod: string; const AHandler: TJsonRpcRequestHandler);
    /// <summary>Wie RegisterRequest; gilt AConcurrentWhen für die Parameter einer Anfrage, läuft sie
    /// nebenläufig wie bei RegisterConcurrentRequest, sonst in der Reihenfolge der Nachrichten (#874).</summary>
    procedure RegisterConditionalRequest(const AMethod: string; const AHandler: TJsonRpcRequestHandler;
      const AConcurrentWhen: TJsonRpcConcurrentWhen);
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
    function DispatchMessage(const AMessage: TJSONObject): TJSONObject; overload;
    /// <summary>Wie DispatchMessage; AQueueMs ist die Zeit seit dem Eingang der Nachricht (Diagnoselog).</summary>
    function DispatchMessage(const AMessage: TJSONObject; AQueueMs: Int64): TJSONObject; overload;
    /// <summary>Namen aller registrierten Anfragen (für das Diagnoselog, #647).</summary>
    function Methods: TArray<string>;
    /// <summary>Meldet eine eigene Anfrage mit der id AId (als Text) an; ihre Antwort geht einmal an AHandler.
    /// Threadsicher.</summary>
    procedure ExpectResponse(const AId: string; const AHandler: TJsonRpcResponseHandler);
    /// <summary>Gibt die Anmeldung zurück, etwa wenn die Anfrage nicht gesendet werden konnte.</summary>
    procedure ForgetResponse(const AId: string);
    /// <summary>Optionale Prüfung vor jeder Verteilung, z. B. für den Lebenszyklus des Servers.</summary>
    property Guard: TJsonRpcGuard read FGuard write FGuard;
    /// <summary>Optionale Prüfung jeder Anfrage mit Parametern (#1355), nach Guard.</summary>
    property RequestGuard: TJsonRpcRequestGuard read FRequestGuard write FRequestGuard;
    /// <summary>Optional: die letzten Nachrichten für Absturzfälle (#1355).</summary>
    property Recent: IJsonRpcRecentMessages read FRecent write FRecent;
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
    /// <summary>Optional: sieht jede Anfrage mit Ergebnis und Wartezeit (#647).</summary>
    property Observer: IJsonRpcRequestObserver read FObserver write FObserver;
  end;

implementation

uses
  System.Diagnostics,
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.JsonRpc.CurrentRequest;

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

procedure ObserveStarted(const AObserver: IJsonRpcRequestObserver; const AMethod: string);
begin
  if AObserver <> nil then
    try
      AObserver.Started(AMethod);
    except
      // Das Diagnoselog darf keine Anfrage verhindern.
    end;
end;

procedure ObserveFinished(const AObserver: IJsonRpcRequestObserver; const AMethod: string;
  const AParams, AResult: TJSONValue; const AError: Exception; AQueueMs, AElapsedMs: Int64);
begin
  if AObserver <> nil then
    try
      AObserver.Finished(AMethod, AParams, AResult, AError, AQueueMs, AElapsedMs);
    except
      // Das Diagnoselog darf keine Antwort verhindern.
    end;
end;

function RunConcurrent(const AId, AParams: TJSONValue; const AMethod: string;
  const AHandler: TJsonRpcConcurrentRequestHandler; const AToken: IJsonRpcCancellationToken;
  const AOnFailed: TJsonRpcRequestFailedEvent; const AStatistics: IJsonRpcStatistics;
  const AObserver: IJsonRpcRequestObserver; AQueueMs: Int64): TJSONObject;
var
  Watch: TStopwatch;
  Failed: Boolean;
  Value: TJSONValue;
  Previous: Pointer;
begin
  Watch := TStopwatch.StartNew;
  Failed := False;
  ObserveStarted(AObserver, AMethod);
  try
    AToken.ThrowIfCancellationRequested;
    // Tiefe Aufrufe ohne Token-Parameter (EnsureUnit) fragen das Signal über TJsonRpcCurrentRequest (A-06).
    Previous := TJsonRpcCurrentRequest.Enter(AToken);
    try
      Value := AHandler(AParams, AToken);
    finally
      TJsonRpcCurrentRequest.Leave(Previous);
    end;
    Result := TJsonRpcMessages.Response(AId, Value);
    ObserveFinished(AObserver, AMethod, AParams, Value, nil, AQueueMs, Watch.ElapsedMilliseconds);
  except
    on E: Exception do
    begin
      // Zuerst die Schutzseite nach einem Stapelüberlauf; alles danach darf wieder tief rufen (#1355).
      TStackGuard.AfterError(E);
      Failed := True;
      ObserveFinished(AObserver, AMethod, AParams, nil, E, AQueueMs, Watch.ElapsedMilliseconds);
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
  const AStatistics: IJsonRpcStatistics; const AObserver: IJsonRpcRequestObserver; AQueueMs: Int64);
var
  Method: string;
  Statistics: IJsonRpcStatistics;
  Observer: IJsonRpcRequestObserver;
  Queued: TStopwatch;
  Watchdog: IJsonRpcWatchdog;
  OnFailed: TJsonRpcRequestFailedEvent;
  Id: TJSONValue;
  Params: TJSONValue;
  Responder: TJsonRpcResponder;
  Pending: IJsonRpcPendingRequests;
  Handler: TJsonRpcConcurrentRequestHandler;
  Token: IJsonRpcCancellationToken;
  Waited: Int64;
begin
  Responder := AResponder;
  Waited := AQueueMs;
  Pending := APending;
  Handler := AHandler;
  Token := AToken;
  Method := AMethod;
  Watchdog := AWatchdog;
  OnFailed := AOnFailed;
  Statistics := AStatistics;
  Observer := AObserver;
  Queued := TStopwatch.StartNew;
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
          // Beim Ablauf antwortet der Watchdog selbst mit RequestCancelled (Code-Review A-06).
          if Watchdog <> nil then
            Ticket := Watchdog.Watch(Id, Method, Token, Responder);
          try
            Response := RunConcurrent(Id, Params, Method, Handler, Token, OnFailed, Statistics, Observer,
              Waited + Queued.ElapsedMilliseconds);
          finally
            if Watchdog <> nil then
              Watchdog.Unwatch(Ticket);
            Pending.Release(Id, Token);
            Params.Free;
            Id.Free;
          end;
          // Hat der Watchdog schon mit RequestCancelled geantwortet, wird die späte Antwort verworfen:
          // genau eine Antwort je Anfrage (A-06).
          if Pending.TryAnswer(Token) then
            Responder(Response)
          else
            Response.Free;
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
  FConcurrentWhen := TDictionary<string, TJsonRpcConcurrentWhen>.Create;
  FPending := TJsonRpcPendingRequests.Create;
  FNotificationHandlers := TDictionary<string, TJsonRpcNotificationHandler>.Create;
  FExpected := TDictionary<string, TJsonRpcResponseHandler>.Create;
end;

destructor TJsonRpcDispatcher.Destroy;
begin
  FExpected.Free;
  FNotificationHandlers.Free;
  FConcurrentWhen.Free;
  FConcurrentHandlers.Free;
  FRequestHandlers.Free;
  inherited;
end;

procedure TJsonRpcDispatcher.ExpectResponse(const AId: string; const AHandler: TJsonRpcResponseHandler);
begin
  TMonitor.Enter(FExpected);
  try
    FExpected.AddOrSetValue(AId, AHandler);
  finally
    TMonitor.Exit(FExpected);
  end;
end;

procedure TJsonRpcDispatcher.ForgetResponse(const AId: string);
begin
  TMonitor.Enter(FExpected);
  try
    FExpected.Remove(AId);
  finally
    TMonitor.Exit(FExpected);
  end;
end;

procedure TJsonRpcDispatcher.RegisterRequest(const AMethod: string; const AHandler: TJsonRpcRequestHandler);
begin
  FConcurrentHandlers.Remove(AMethod);
  FConcurrentWhen.Remove(AMethod);
  FRequestHandlers.AddOrSetValue(AMethod, AHandler);
end;

procedure TJsonRpcDispatcher.RegisterConditionalRequest(const AMethod: string;
  const AHandler: TJsonRpcRequestHandler; const AConcurrentWhen: TJsonRpcConcurrentWhen);
begin
  RegisterRequest(AMethod, AHandler);
  if Assigned(AConcurrentWhen) then
    FConcurrentWhen.AddOrSetValue(AMethod, AConcurrentWhen);
end;

procedure TJsonRpcDispatcher.RegisterConcurrentRequest(const AMethod: string;
  const AHandler: TJsonRpcConcurrentRequestHandler);
begin
  FRequestHandlers.Remove(AMethod);
  FConcurrentWhen.Remove(AMethod);
  FConcurrentHandlers.AddOrSetValue(AMethod, AHandler);
end;

procedure TJsonRpcDispatcher.RegisterNotification(const AMethod: string; const AHandler: TJsonRpcNotificationHandler);
begin
  FNotificationHandlers.AddOrSetValue(AMethod, AHandler);
end;

function TJsonRpcDispatcher.DispatchMessage(const AMessage: TJSONObject): TJSONObject;
begin
  Result := DispatchMessage(AMessage, 0);
end;

function TJsonRpcDispatcher.DispatchMessage(const AMessage: TJSONObject; AQueueMs: Int64): TJSONObject;
var
  Id: TJSONValue;
  MethodValue: TJSONValue;
  Params: TJSONValue;
  Handler: TJsonRpcResponseHandler;
  Found: Boolean;
begin
  Id := AMessage.GetValue('id');
  MethodValue := AMessage.GetValue('method');
  Params := AMessage.GetValue('params');
  if FRecent <> nil then
    try
      FRecent.Add(AMessage);
    except
      // Das Mitschreiben für Absturzfälle darf keine Nachricht verhindern.
      on Exception do
        ;
    end;

  if MethodValue = nil then
  begin
    // Antwort der Gegenseite auf eine eigene Anfrage: an den angemeldeten Handler, sonst verwerfen.
    if (AMessage.GetValue('result') <> nil) or (AMessage.GetValue('error') <> nil) then
    begin
      Found := False;
      if Id <> nil then
      begin
        TMonitor.Enter(FExpected);
        try
          Found := FExpected.TryGetValue(Id.Value, Handler);
          if Found then
            FExpected.Remove(Id.Value);
        finally
          TMonitor.Exit(FExpected);
        end;
      end;
      if Found then
        Handler(AMessage);
      Exit(nil);
    end;
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
    if (MethodValue.Value = JsonRpcCancelRequestMethod) or (MethodValue.Value = McpCancelledMethod) then
    begin
      FPending.Observe(AMessage);
      Exit(nil);
    end;
    DispatchNotification(MethodValue.Value, Params);
    Result := nil;
  end
  else
    Result := DispatchRequest(Id, MethodValue.Value, Params, AQueueMs);
end;

function TJsonRpcDispatcher.ConcurrentFor(const AMethod: string; const AParams: TJSONValue;
  out AHandler: TJsonRpcConcurrentRequestHandler): Boolean;
var
  When: TJsonRpcConcurrentWhen;
  Handler: TJsonRpcRequestHandler;
  Concurrent: Boolean;
begin
  AHandler := nil;
  if FConcurrentHandlers.TryGetValue(AMethod, AHandler) then
    Exit(True);
  if not (FConcurrentWhen.TryGetValue(AMethod, When) and FRequestHandlers.TryGetValue(AMethod, Handler)) then
    Exit(False);
  try
    Concurrent := When(AParams);
  except
    // Unlesbare Parameter: in der Reihenfolge laufen; der Handler meldet den Fehler selbst.
    on Exception do
      Concurrent := False;
  end;
  if not Concurrent then
    Exit(False);
  AHandler :=
    function(const ARequestParams: TJSONValue; const AToken: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := Handler(ARequestParams);
    end;
  Result := True;
end;

function TJsonRpcDispatcher.Methods: TArray<string>;
begin
  Result := FRequestHandlers.Keys.ToArray + FConcurrentHandlers.Keys.ToArray;
end;

function TJsonRpcDispatcher.DispatchRequest(const AId: TJSONValue; const AMethod: string;
  const AParams: TJSONValue; AQueueMs: Int64): TJSONObject;
var
  Handler: TJsonRpcRequestHandler;
  ConcurrentHandler: TJsonRpcConcurrentRequestHandler;
  Token: IJsonRpcCancellationToken;
  Scheduled: Boolean;
  Ticket: Int64;
  Watch: TStopwatch;
  Measured: Boolean;
  Value: TJSONValue;
  Previous: Pointer;
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
      if Assigned(FRequestGuard) then
        FRequestGuard(AMethod, AParams);
      if ConcurrentFor(AMethod, AParams, ConcurrentHandler) then
      begin
        if Assigned(FScheduler) and Assigned(FResponder) then
        begin
          ScheduleConcurrent(FScheduler, FResponder, FPending, ConcurrentHandler, AId, AParams, Token, AMethod,
            FWatchdog, FOnRequestFailed, FStatistics, FObserver, AQueueMs);
          Scheduled := True;
          Exit(nil);
        end;
        // Ohne Scheduler läuft die Anfrage hier; auch dann gilt das Zeitlimit.
        if FWatchdog <> nil then
          Ticket := FWatchdog.Watch(AId, AMethod);
        Exit(RunConcurrent(AId, AParams, AMethod, ConcurrentHandler, Token, FOnRequestFailed, FStatistics,
          FObserver, AQueueMs));
      end;
      if not FRequestHandlers.TryGetValue(AMethod, Handler) then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.MethodNotFound, 'Methode nicht unterstützt: ' + AMethod);
      // Abgebrochen, während die Anfrage noch in der Warteschlange stand.
      Token.ThrowIfCancellationRequested;
      if FWatchdog <> nil then
        Ticket := FWatchdog.Watch(AId, AMethod);
      Measured := True;
      ObserveStarted(FObserver, AMethod);
      Previous := TJsonRpcCurrentRequest.Enter(Token);
      try
        Value := Handler(AParams);
      finally
        TJsonRpcCurrentRequest.Leave(Previous);
      end;
      Result := TJsonRpcMessages.Response(AId, Value);
      ObserveFinished(FObserver, AMethod, AParams, Value, nil, AQueueMs, Watch.ElapsedMilliseconds);
      if FStatistics <> nil then
        FStatistics.Add(AMethod, Watch.ElapsedMilliseconds, False);
    except
      on E: Exception do
      begin
        // Zuerst die Schutzseite nach einem Stapelüberlauf; alles danach darf wieder tief rufen (#1355).
        TStackGuard.AfterError(E);
        if Measured then
          ObserveFinished(FObserver, AMethod, AParams, nil, E, AQueueMs, Watch.ElapsedMilliseconds);
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
