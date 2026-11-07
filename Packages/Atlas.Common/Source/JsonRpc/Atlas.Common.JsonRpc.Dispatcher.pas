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
    /// <summary>Verteilt eine Nachricht mit gültiger Methode: Anfrage, Abbruch oder Benachrichtigung.</summary>
    function DispatchValid(const AMessage: TJSONObject; const AId: TJSONValue; const AMethod: string;
      AQueueMs: Int64): TJSONObject;
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
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDispatcherText = (FieldMethodMissing, FieldMethodIsNotA, MethodNotSupported);

const
  cTexts: array[TDispatcherText] of TAtlasText = (
    (De: 'Feld "method" fehlt'; En: 'Field "method" missing'),
    (De: 'Feld "method" ist keine Zeichenkette'; En: 'Field "method" is not a string'),
    (De: 'Methode nicht unterstützt: '; En: 'Method not supported: '));

{$SCOPEDENUMS OFF}

function ErrorResponse(const AId: TJSONValue; const AError: Exception): TJSONObject;
begin
  if AError is EJsonRpcError then
  begin
    Result := TJsonRpcMessages.Error(AId, EJsonRpcError(AError).Code, AError.Message);
  end
  else
  begin
    Result := TJsonRpcMessages.Error(AId, TJsonRpcErrorCode.cInternalError, AError.ClassName + ': ' + AError.Message);
  end;
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

type
  /// <summary>Eine Anfrage auf dem Weg durch den Handler: Kennung, Abbruchsignal und Beobachter.</summary>
  TRequestRun = record
    Id: TJSONValue;
    Params: TJSONValue;
    Method: string;
    Token: IJsonRpcCancellationToken;
    OnFailed: TJsonRpcRequestFailedEvent;
    Statistics: IJsonRpcStatistics;
    Observer: IJsonRpcRequestObserver;
    /// <summary>Wartezeit vor dem Start.</summary>
    QueueMs: Int64;
  end;

procedure ObserveFinished(const ARun: TRequestRun; const AResult: TJSONValue; const AError: Exception;
  AElapsedMs: Int64);
begin
  if ARun.Observer <> nil then
    try
      ARun.Observer.Finished(ARun.Method, ARun.Params, AResult, AError, ARun.QueueMs, AElapsedMs);
    except
      // Das Diagnoselog darf keine Antwort verhindern.
    end;
end;

/// <summary>Antwort mit AValue; meldet Ende und Laufzeit.</summary>
function SucceededResponse(const ARun: TRequestRun; const AValue: TJSONValue; AElapsedMs: Int64): TJSONObject;
begin
  Result := TJsonRpcMessages.Response(ARun.Id, AValue);
  ObserveFinished(ARun, AValue, nil, AElapsedMs);
  if ARun.Statistics <> nil then
  begin
    ARun.Statistics.Add(ARun.Method, AElapsedMs, False);
  end;
end;

/// <summary>Fehlerantwort zu AError; mit AMeasured auch Ende und Laufzeit des Handlers.</summary>
function FailedResponse(const ARun: TRequestRun; const AError: Exception; AMeasured: Boolean;
  AElapsedMs: Int64): TJSONObject;
begin
  // Zuerst die Schutzseite nach einem Stapelüberlauf; alles danach darf wieder tief rufen (#1355).
  TStackGuard.AfterError(AError);
  if AMeasured then
  begin
    ObserveFinished(ARun, nil, AError, AElapsedMs);
  end;
  if AMeasured and (ARun.Statistics <> nil) then
  begin
    ARun.Statistics.Add(ARun.Method, AElapsedMs, True);
  end;
  NotifyFailed(ARun.OnFailed, ARun.Method, ARun.Params, AError);
  Result := ErrorResponse(ARun.Id, AError);
end;

function RunConcurrent(const ARun: TRequestRun; const AHandler: TJsonRpcConcurrentRequestHandler): TJSONObject;
var
  mWatch: TStopwatch;
  mValue: TJSONValue;
  mPrevious: Pointer;
begin
  mWatch := TStopwatch.StartNew;
  ObserveStarted(ARun.Observer, ARun.Method);
  try
    ARun.Token.ThrowIfCancellationRequested;
    // Tiefe Aufrufe ohne Token-Parameter (EnsureUnit) fragen das Signal über TJsonRpcCurrentRequest (A-06).
    mPrevious := TJsonRpcCurrentRequest.Enter(ARun.Token);
    try
      mValue := AHandler(ARun.Params, ARun.Token);
    finally
      TJsonRpcCurrentRequest.Leave(mPrevious);
    end;
    Result := SucceededResponse(ARun, mValue, mWatch.ElapsedMilliseconds);
  except
    on E: Exception do
    begin
      Result := FailedResponse(ARun, E, True, mWatch.ElapsedMilliseconds);
    end;
  end;
end;

function RunOrdered(const ARun: TRequestRun; const AHandler: TJsonRpcRequestHandler): TJSONObject;
var
  mWatch: TStopwatch;
  mValue: TJSONValue;
  mPrevious: Pointer;
begin
  mWatch := TStopwatch.StartNew;
  ObserveStarted(ARun.Observer, ARun.Method);
  try
    mPrevious := TJsonRpcCurrentRequest.Enter(ARun.Token);
    try
      mValue := AHandler(ARun.Params);
    finally
      TJsonRpcCurrentRequest.Leave(mPrevious);
    end;
    Result := SucceededResponse(ARun, mValue, mWatch.ElapsedMilliseconds);
  except
    on E: Exception do
    begin
      Result := FailedResponse(ARun, E, True, mWatch.ElapsedMilliseconds);
    end;
  end;
end;

/// <summary>Läuft im Worker: Anfrage überwachen, ausführen, Kopien freigeben und genau einmal antworten.
/// AQueued misst die Zeit seit der Übergabe an den Scheduler.</summary>
procedure RunScheduled(const ARun: TRequestRun; const AHandler: TJsonRpcConcurrentRequestHandler;
  const APending: IJsonRpcPendingRequests; const AWatchdog: IJsonRpcWatchdog; const AResponder: TJsonRpcResponder;
  AQueuedMs: Int64);
var
  mRun: TRequestRun;
  mResponse: TJSONObject;
  mTicket: Int64;
begin
  mRun := ARun;
  mRun.QueueMs := ARun.QueueMs + AQueuedMs;
  mTicket := 0;
  // Beim Ablauf antwortet der Watchdog selbst mit RequestCancelled (Code-Review A-06).
  if AWatchdog <> nil then
  begin
    mTicket := AWatchdog.Watch(mRun.Id, mRun.Method, mRun.Token, AResponder);
  end;
  try
    mResponse := RunConcurrent(mRun, AHandler);
  finally
    if AWatchdog <> nil then
    begin
      AWatchdog.Unwatch(mTicket);
    end;
    APending.Release(mRun.Id, mRun.Token);
    mRun.Params.Free;
    mRun.Id.Free;
  end;
  // Hat der Watchdog schon mit RequestCancelled geantwortet, wird die späte Antwort verworfen:
  // genau eine Antwort je Anfrage (A-06).
  if APending.TryAnswer(mRun.Token) then
  begin
    AResponder(mResponse);
  end
  else
  begin
    mResponse.Free;
  end;
end;

// Übergibt eine nebenläufige Anfrage dem Scheduler. Die Arbeit hält nur
// Referenzen auf referenzgezählte Objekte und Kopien von id und Parametern,
// nicht auf den Dispatcher.
procedure ScheduleConcurrent(const AScheduler: TJsonRpcScheduler; const AResponder: TJsonRpcResponder;
  const APending: IJsonRpcPendingRequests; const AWatchdog: IJsonRpcWatchdog;
  const AHandler: TJsonRpcConcurrentRequestHandler; const ARun: TRequestRun);
var
  mRun: TRequestRun;
  mQueued: TStopwatch;
  mResponder: TJsonRpcResponder;
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mHandler: TJsonRpcConcurrentRequestHandler;
begin
  mResponder := AResponder;
  mPending := APending;
  mWatchdog := AWatchdog;
  mHandler := AHandler;
  mQueued := TStopwatch.StartNew;
  mRun := ARun;
  mRun.Id := TJSONValue(ARun.Id.Clone);
  mRun.Params := nil;
  if ARun.Params <> nil then
  begin
    mRun.Params := TJSONValue(ARun.Params.Clone);
  end;

  mPending.BeginWork;
  try
    AScheduler(
      procedure
      begin
        try
          RunScheduled(mRun, mHandler, mPending, mWatchdog, mResponder, mQueued.ElapsedMilliseconds);
        finally
          mPending.EndWork;
        end;
      end);
  except
    mRun.Params.Free;
    mRun.Id.Free;
    mPending.EndWork;
    raise;
  end;
end;

/// <summary>Normaler Handler in der Form eines nebenläufigen.</summary>
function WrappedHandler(const AHandler: TJsonRpcRequestHandler): TJsonRpcConcurrentRequestHandler;
var
  mHandler: TJsonRpcRequestHandler;
begin
  mHandler := AHandler;
  Result :=
    function(const ARequestParams: TJSONValue; const AToken: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := mHandler(ARequestParams);
    end;
end;

/// <summary>Nebenläufiger Handler für AMethod: eigener oder normaler mit erfüllter Bedingung.</summary>
function ConcurrentFor(AConcurrent: TDictionary<string, TJsonRpcConcurrentRequestHandler>;
  AWhen: TDictionary<string, TJsonRpcConcurrentWhen>; ARequests: TDictionary<string, TJsonRpcRequestHandler>;
  const AMethod: string; const AParams: TJSONValue; out AHandler: TJsonRpcConcurrentRequestHandler): Boolean;
var
  mWhen: TJsonRpcConcurrentWhen;
  mHandler: TJsonRpcRequestHandler;
begin
  AHandler := nil;
  if AConcurrent.TryGetValue(AMethod, AHandler) then
  begin
    Exit(True);
  end;
  Result := AWhen.TryGetValue(AMethod, mWhen) and ARequests.TryGetValue(AMethod, mHandler);
  if Result then
    try
      Result := mWhen(AParams);
    except
      // Unlesbare Parameter: in der Reihenfolge laufen; der Handler meldet den Fehler selbst.
      on Exception do
        Result := False;
    end;
  if Result then
  begin
    AHandler := WrappedHandler(mHandler);
  end;
end;

/// <summary>Merkt AMessage für Absturzfälle; Fehler dabei verhindern keine Nachricht.</summary>

procedure RememberMessage(const ARecent: IJsonRpcRecentMessages; const AMessage: TJSONObject);
begin
  if ARecent <> nil then
    try
      ARecent.Add(AMessage);
    except
      // Das Mitschreiben für Absturzfälle darf keine Nachricht verhindern.
      on Exception do
        ;
    end;
end;

/// <summary>Nimmt den angemeldeten Handler der Antwort auf die eigene Anfrage AId heraus; False ohne.</summary>

function TakeExpected(AExpected: TDictionary<string, TJsonRpcResponseHandler>; const AId: TJSONValue;
  out AHandler: TJsonRpcResponseHandler): Boolean;
begin
  Result := False;
  if AId = nil then
  begin
    Exit;
  end;
  TMonitor.Enter(AExpected);
  try
    Result := AExpected.TryGetValue(AId.Value, AHandler);
    if Result then
    begin
      AExpected.Remove(AId.Value);
    end;
  finally
    TMonitor.Exit(AExpected);
  end;
end;

/// <summary>Methode und id für Absturzprotokolle.</summary>

function MessageLabel(const AMethod: string; const AId: TJSONValue): string;
begin
  Result := AMethod;
  if AId <> nil then
  begin
    Result := AMethod + ' (id ' + AId.ToJSON + ')';
  end;
end;

/// <summary>Prüft Guard und RequestGuard von ADispatcher; eine Ausnahme lehnt die Anfrage ab.</summary>

procedure CheckGuards(ADispatcher: TJsonRpcDispatcher; const AMethod: string; const AParams: TJSONValue);
begin
  if Assigned(ADispatcher.Guard) then
  begin
    ADispatcher.Guard(AMethod, True);
  end;
  if Assigned(ADispatcher.RequestGuard) then
  begin
    ADispatcher.RequestGuard(AMethod, AParams);
  end;
end;

/// <summary>Anfrage AId mit Abbruchsignal AToken und den Beobachtern von ADispatcher.</summary>

function NewRun(ADispatcher: TJsonRpcDispatcher; const AId: TJSONValue; const AMethod: string;
  const AParams: TJSONValue; const AToken: IJsonRpcCancellationToken; AQueueMs: Int64): TRequestRun;
begin
  Result.Id := AId;
  Result.Params := AParams;
  Result.Method := AMethod;
  Result.Token := AToken;
  Result.OnFailed := ADispatcher.OnRequestFailed;
  Result.Statistics := ADispatcher.Statistics;
  Result.Observer := ADispatcher.Observer;
  Result.QueueMs := AQueueMs;
end;

/// <summary>Verteilt eine Benachrichtigung. Sie erhält keine Antwort, auch keine Fehlerantwort; unbekannte und
/// vom Guard abgelehnte werden verworfen. Andere Exceptions eines Handlers gehen an den Aufrufer.</summary>

procedure DispatchNotification(const AGuard: TJsonRpcGuard;
  AHandlers: TDictionary<string, TJsonRpcNotificationHandler>; const AMethod: string; const AParams: TJSONValue);
var
  mHandler: TJsonRpcNotificationHandler;
begin
  if Assigned(AGuard) then
    try
      AGuard(AMethod, False);
    except
      on EJsonRpcError do
        Exit;
    end;
  if AHandlers.TryGetValue(AMethod, mHandler) then
  begin
    mHandler(AParams);
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
  begin
    FConcurrentWhen.AddOrSetValue(AMethod, AConcurrentWhen);
  end;
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
  mId, mMethodValue: TJSONValue;
  mHandler: TJsonRpcResponseHandler;
begin
  Result := nil;
  mId := AMessage.GetValue('id');
  mMethodValue := AMessage.GetValue('method');
  RememberMessage(FRecent, AMessage);
  if (mMethodValue = nil) and ((AMessage.GetValue('result') <> nil) or (AMessage.GetValue('error') <> nil)) then
  begin
    // Antwort der Gegenseite auf eine eigene Anfrage: an den angemeldeten Handler, sonst verwerfen.
    if TakeExpected(FExpected, mId, mHandler) then
    begin
      mHandler(AMessage);
    end;
  end
  else if mMethodValue = nil then
  begin
    Result := TJsonRpcMessages.Error(mId, TJsonRpcErrorCode.cInvalidRequest,
      cTexts[TDispatcherText.FieldMethodMissing].Text);
  end
  else if not (mMethodValue is TJSONString) then
  begin
    if mId <> nil then
    begin
      Result := TJsonRpcMessages.Error(mId, TJsonRpcErrorCode.cInvalidRequest,
        cTexts[TDispatcherText.FieldMethodIsNotA].Text);
    end;
  end
  else
  begin
    FLastMessage := MessageLabel(mMethodValue.Value, mId);
    Result := DispatchValid(AMessage, mId, mMethodValue.Value, AQueueMs);
  end;
end;

function TJsonRpcDispatcher.DispatchValid(const AMessage: TJSONObject; const AId: TJSONValue;
  const AMethod: string; AQueueMs: Int64): TJSONObject;
begin
  Result := nil;
  if AId <> nil then
  begin
    Result := DispatchRequest(AId, AMethod, AMessage.GetValue('params'), AQueueMs);
  end
  // $/cancelRequest ist Teil des Protokolls und gilt in jedem Zustand. Über
  // die Verbindung erledigt das schon der Lese-Thread (IJsonRpcPendingRequests.Observe).
  else if (AMethod = cJsonRpcCancelRequestMethod) or (AMethod = cMcpCancelledMethod) then
  begin
    FPending.Observe(AMessage);
  end
  else
  begin
    DispatchNotification(FGuard, FNotificationHandlers, AMethod, AMessage.GetValue('params'));
  end;
end;

function TJsonRpcDispatcher.Methods: TArray<string>;
begin
  Result := FRequestHandlers.Keys.ToArray + FConcurrentHandlers.Keys.ToArray;
end;

function TJsonRpcDispatcher.DispatchRequest(const AId: TJSONValue; const AMethod: string;
  const AParams: TJSONValue; AQueueMs: Int64): TJSONObject;
var
  mRun: TRequestRun;
  mHandler: TJsonRpcRequestHandler;
  mConcurrent: TJsonRpcConcurrentRequestHandler;
  mScheduled: Boolean;
  mTicket: Int64;
begin
  mRun := NewRun(Self, AId, AMethod, AParams, FPending.Acquire(AId), AQueueMs);
  mScheduled := False;
  mTicket := 0;
  try
    try
      CheckGuards(Self, AMethod, AParams);
      if ConcurrentFor(FConcurrentHandlers, FConcurrentWhen, FRequestHandlers, AMethod, AParams, mConcurrent) then
      begin
        mScheduled := Assigned(FScheduler) and Assigned(FResponder);
        if mScheduled then
        begin
          ScheduleConcurrent(FScheduler, FResponder, FPending, FWatchdog, mConcurrent, mRun);
          Exit(nil);
        end;
        // Ohne Scheduler läuft die Anfrage hier; auch dann gilt das Zeitlimit.
        if FWatchdog <> nil then
        begin
          mTicket := FWatchdog.Watch(AId, AMethod);
        end;
        Exit(RunConcurrent(mRun, mConcurrent));
      end;
      if not FRequestHandlers.TryGetValue(AMethod, mHandler) then
      begin
        raise EJsonRpcError.Create(TJsonRpcErrorCode.cMethodNotFound, cTexts[TDispatcherText.MethodNotSupported].Text +
          AMethod);
      end;
      // Abgebrochen, während die Anfrage noch in der Warteschlange stand.
      mRun.Token.ThrowIfCancellationRequested;
      if FWatchdog <> nil then
      begin
        mTicket := FWatchdog.Watch(AId, AMethod);
      end;
      Result := RunOrdered(mRun, mHandler);
    except
      on E: Exception do
      begin
        Result := FailedResponse(mRun, E, False, 0);
      end;
    end;
  finally
    if FWatchdog <> nil then
    begin
      FWatchdog.Unwatch(mTicket);
    end;
    if not mScheduled then
    begin
      FPending.Release(AId, mRun.Token);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.JsonRpc.Dispatcher', cTexts);

end.
