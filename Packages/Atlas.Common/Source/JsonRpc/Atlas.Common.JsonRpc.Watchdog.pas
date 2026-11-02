unit Atlas.Common.JsonRpc.Watchdog;

// Zeitlimit für Anfragen: Ein eigener Thread bricht Anfragen ab, die länger als
// das Limit laufen (über IJsonRpcPendingRequests.Cancel), und meldet sie.
// Handler, die ihr Abbruchsignal prüfen, enden dann mit RequestCancelled; so
// bleibt eine hängende Anfrage nicht für immer offen.
//
// Nebenläufige Anfragen (Watch mit Token und Responder) beantwortet der
// Watchdog beim Ablauf sofort mit RequestCancelled, falls der Handler noch
// nicht geantwortet hat; dessen spätere Antwort verwirft der Worker
// (IJsonRpcPendingRequests.TryAnswer, Code-Review A-06). Anfragen im Thread
// der Schleife erhalten nur den Abbruch.
//
// OnExpired meldet zusätzlich die id der Anfrage (JSON-Text), damit der
// Absturzfall (#1355) ihre Parameter findet.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests;

type
  /// <summary>Meldet eine Anfrage, deren Zeitlimit abgelaufen ist. AAnswered: Der Watchdog hat sie mit
  /// RequestCancelled beantwortet (nebenläufige Anfragen); sonst wurde nur der Abbruch angefordert.</summary>
  TJsonRpcTimeoutEvent = reference to procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean);
  /// <summary>Wie TJsonRpcTimeoutEvent, mit der id der Anfrage als JSON-Text (#1355); läuft im Thread des
  /// Watchdogs nach dem Abbruch.</summary>
  TJsonRpcExpiredEvent = reference to procedure(const AId, AMethod: string; ATimeoutMs: Cardinal);

  IJsonRpcWatchdog = interface
    ['{7E3C5A91-2D4F-4B86-A0E7-1F9B6C3D8E52}']
    /// <summary>Überwacht eine Anfrage; liefert eine Nummer für Unwatch. Beim Ablauf wird nur abgebrochen
    /// (Anfragen im Thread der Schleife).</summary>
    function Watch(const AId: TJSONValue; const AMethod: string): Int64; overload;
    /// <summary>Wie Watch; beim Ablauf antwortet der Watchdog sofort über AResponder mit RequestCancelled,
    /// sofern der Handler noch nicht geantwortet hat (IJsonRpcPendingRequests.TryAnswer).</summary>
    function Watch(const AId: TJSONValue; const AMethod: string; const AToken: IJsonRpcCancellationToken;
      const AResponder: TJsonRpcResponder): Int64; overload;
    procedure Unwatch(ATicket: Int64);
    /// <summary>Neues Zeitlimit für künftige Anfragen (#283, Einstellung "requestTimeoutMs").
    /// Wirkt nur, wenn die Überwachung mit einem Limit &gt; 0 gestartet wurde.</summary>
    procedure SetTimeout(ATimeoutMs: Cardinal);
  end;

  TJsonRpcWatchdog = class(TInterfacedObject, IJsonRpcWatchdog)
  private type
    TEntry = record
      Id: TJSONValue;
      Method: string;
      Due: UInt64;
      /// <summary>nil: beim Ablauf nur abbrechen.</summary>
      Token: IJsonRpcCancellationToken;
      Responder: TJsonRpcResponder;
    end;
  private
    FPending: IJsonRpcPendingRequests;
    FTimeout: Cardinal;
    FOnTimeout: TJsonRpcTimeoutEvent;
    FOnExpired: TJsonRpcExpiredEvent;
    FEntries: TDictionary<Int64, TEntry>;
    FNextTicket: Int64;
    FStopping: Boolean;
    FThread: TThread;
    /// <summary>Nimmt die abgelaufenen Einträge aus FEntries nach AExpired; liefert die nächste Fälligkeit
    /// (High(UInt64) ohne). Nur unter der Sperre von FEntries.</summary>
    function CollectExpired(AExpired: TList<TEntry>; ATicks: UInt64): UInt64;
    /// <summary>Wartet, bis Einträge ablaufen, und nimmt sie nach AExpired; False beim Beenden.</summary>
    function TakeExpired(AExpired: TList<TEntry>): Boolean;
    procedure Execute;
    procedure Expire(const AEntry: TEntry);
  public
    /// <summary>ATimeoutMs = 0 schaltet die Überwachung ab.</summary>
    constructor Create(const APending: IJsonRpcPendingRequests; ATimeoutMs: Cardinal;
      const AOnTimeout: TJsonRpcTimeoutEvent);
    destructor Destroy; override;
    function Watch(const AId: TJSONValue; const AMethod: string): Int64; overload;
    function Watch(const AId: TJSONValue; const AMethod: string; const AToken: IJsonRpcCancellationToken;
      const AResponder: TJsonRpcResponder): Int64; overload;
    procedure Unwatch(ATicket: Int64);
    procedure SetTimeout(ATimeoutMs: Cardinal);
    function Timeout: Cardinal;
    /// <summary>Optional, vor der ersten Anfrage setzen (#1355).</summary>
    property OnExpired: TJsonRpcExpiredEvent read FOnExpired write FOnExpired;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Messages;

const
  WaitForever = Cardinal($FFFFFFFF);

{ TJsonRpcWatchdog }

constructor TJsonRpcWatchdog.Create(const APending: IJsonRpcPendingRequests; ATimeoutMs: Cardinal;
  const AOnTimeout: TJsonRpcTimeoutEvent);
begin
  inherited Create;
  FPending := APending;
  FTimeout := ATimeoutMs;
  FOnTimeout := AOnTimeout;
  FEntries := TDictionary<Int64, TEntry>.Create;
  if FTimeout > 0 then
  begin
    FThread := TThread.CreateAnonymousThread(Execute);
    FThread.FreeOnTerminate := False;
    FThread.Start;
  end;
end;

destructor TJsonRpcWatchdog.Destroy;
var
  Entry: TEntry;
begin
  if FThread <> nil then
  begin
    TMonitor.Enter(FEntries);
    try
      FStopping := True;
      TMonitor.PulseAll(FEntries);
    finally
      TMonitor.Exit(FEntries);
    end;
    FThread.WaitFor;
    FThread.Free;
  end;
  for Entry in FEntries.Values do
  begin
    Entry.Id.Free;
  end;
  FEntries.Free;
  inherited;
end;

function TJsonRpcWatchdog.Watch(const AId: TJSONValue; const AMethod: string): Int64;
begin
  Result := Watch(AId, AMethod, nil, nil);
end;

function TJsonRpcWatchdog.Watch(const AId: TJSONValue; const AMethod: string;
  const AToken: IJsonRpcCancellationToken; const AResponder: TJsonRpcResponder): Int64;
var
  Entry: TEntry;
begin
  if FThread = nil then
  begin
    Exit(0);
  end;
  Entry.Id := TJSONValue(AId.Clone);
  Entry.Method := AMethod;
  Entry.Token := AToken;
  Entry.Responder := AResponder;
  TMonitor.Enter(FEntries);
  try
    Entry.Due := TThread.GetTickCount64 + FTimeout;
    Inc(FNextTicket);
    Result := FNextTicket;
    FEntries.Add(Result, Entry);
    TMonitor.PulseAll(FEntries);
  finally
    TMonitor.Exit(FEntries);
  end;
end;

procedure TJsonRpcWatchdog.Unwatch(ATicket: Int64);
var
  Entry: TEntry;
begin
  if ATicket = 0 then
  begin
    Exit;
  end;
  TMonitor.Enter(FEntries);
  try
    if not FEntries.TryGetValue(ATicket, Entry) then
    begin
      Exit;
    end;
    FEntries.Remove(ATicket);
  finally
    TMonitor.Exit(FEntries);
  end;
  Entry.Id.Free;
end;

procedure TJsonRpcWatchdog.SetTimeout(ATimeoutMs: Cardinal);
begin
  if (FThread = nil) or (ATimeoutMs = 0) then
  begin
    Exit;
  end;
  TMonitor.Enter(FEntries);
  try
    FTimeout := ATimeoutMs;
  finally
    TMonitor.Exit(FEntries);
  end;
end;

function TJsonRpcWatchdog.Timeout: Cardinal;
begin
  TMonitor.Enter(FEntries);
  try
    Result := FTimeout;
  finally
    TMonitor.Exit(FEntries);
  end;
end;

procedure TJsonRpcWatchdog.Expire(const AEntry: TEntry);
var
  Answered: Boolean;
  Limit: Cardinal;
begin
  try
    Limit := Timeout;
    Answered := False;
    if (AEntry.Token <> nil) and Assigned(AEntry.Responder) then
    begin
      // Abbrechen und die Antwort beanspruchen: Wer zuerst kommt (Worker oder Watchdog), antwortet.
      // Die Antwort zählt als laufende Arbeit, und zwar schon vor dem Beanspruchen: Der Worker verwirft seine
      // Antwort, sobald der Watchdog sie beansprucht hat, und meldet sein Ende. Ohne eigene Zählung meldete
      // WaitForWork dann Ruhe, bevor die Fehlerantwort geschrieben war; beim Beenden der Verbindung ging sie
      // verloren (Dauerlauf ConnectionSoakDetectsWorkerLeak unter Last: 100 statt 101 Antworten).
      FPending.BeginWork;
      try
        Answered := FPending.Expire(AEntry.Token);
        if Answered then
        begin
          AEntry.Responder(TJsonRpcMessages.Error(AEntry.Id, TJsonRpcErrorCode.RequestCancelled,
            Format('Zeitlimit von %d ms überschritten', [Limit])));
        end;
      finally
        FPending.EndWork;
      end;
    end
    else
    begin
      FPending.Cancel(AEntry.Id);
    end;
    if Assigned(FOnTimeout) then
    begin
      FOnTimeout(AEntry.Method, Limit, Answered);
    end;
    if Assigned(FOnExpired) then
    begin
      FOnExpired(AEntry.Id.ToJSON, AEntry.Method, Limit);
    end;
  finally
    AEntry.Id.Free;
  end;
end;

function TJsonRpcWatchdog.CollectExpired(AExpired: TList<TEntry>; ATicks: UInt64): UInt64;
var
  mPair: TPair<Int64, TEntry>;
begin
  Result := High(UInt64);
  for mPair in FEntries.ToArray do
  begin
    if mPair.Value.Due <= ATicks then
    begin
      AExpired.Add(mPair.Value);
      FEntries.Remove(mPair.Key);
    end
    else if mPair.Value.Due < Result then
    begin
      Result := mPair.Value.Due;
    end;
  end;
end;

function TJsonRpcWatchdog.TakeExpired(AExpired: TList<TEntry>): Boolean;
var
  mTicks, mNextDue: UInt64;
begin
  TMonitor.Enter(FEntries);
  try
    Result := not FStopping;
    if not Result then
    begin
      Exit;
    end;
    mTicks := TThread.GetTickCount64;
    mNextDue := CollectExpired(AExpired, mTicks);
    if (AExpired.Count = 0) and (mNextDue = High(UInt64)) then
    begin
      TMonitor.Wait(FEntries, WaitForever);
    end
    else if AExpired.Count = 0 then
    begin
      TMonitor.Wait(FEntries, Cardinal(mNextDue - mTicks));
    end;
  finally
    TMonitor.Exit(FEntries);
  end;
end;

procedure TJsonRpcWatchdog.Execute;
var
  mExpired: TList<TEntry>;
  mEntry: TEntry;
begin
  mExpired := TList<TEntry>.Create;
  try
    while TakeExpired(mExpired) do
    begin
      // Außerhalb der Sperre: Cancel und Meldung dürfen dauern.
      for mEntry in mExpired do
        try
          Expire(mEntry);
        except
          // Eine fehlerhafte Meldung darf die Überwachung nicht beenden.
        end;
      mExpired.Clear;
    end;
  finally
    mExpired.Free;
  end;
end;

end.
