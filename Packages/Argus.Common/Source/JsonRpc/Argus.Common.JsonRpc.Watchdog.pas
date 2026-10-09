unit Argus.Common.JsonRpc.Watchdog;

// Zeitlimit für Anfragen: Ein eigener Thread bricht Anfragen ab, die länger als
// das Limit laufen (über IJsonRpcPendingRequests.Cancel), und meldet sie.
// Handler, die ihr Abbruchsignal prüfen, enden dann mit RequestCancelled; so
// bleibt eine hängende Anfrage nicht für immer offen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Argus.Common.JsonRpc.PendingRequests;

type
  /// <summary>Meldet eine Anfrage, deren Zeitlimit abgelaufen ist.</summary>
  TJsonRpcTimeoutEvent = reference to procedure(const AMethod: string; ATimeoutMs: Cardinal);

  IJsonRpcWatchdog = interface
    ['{7E3C5A91-2D4F-4B86-A0E7-1F9B6C3D8E52}']
    /// <summary>Überwacht eine Anfrage; liefert eine Nummer für Unwatch.</summary>
    function Watch(const AId: TJSONValue; const AMethod: string): Int64;
    procedure Unwatch(ATicket: Int64);
  end;

  TJsonRpcWatchdog = class(TInterfacedObject, IJsonRpcWatchdog)
  private type
    TEntry = record
      Id: TJSONValue;
      Method: string;
      Due: UInt64;
    end;
  private
    FPending: IJsonRpcPendingRequests;
    FTimeout: Cardinal;
    FOnTimeout: TJsonRpcTimeoutEvent;
    FEntries: TDictionary<Int64, TEntry>;
    FNextTicket: Int64;
    FStopping: Boolean;
    FThread: TThread;
    procedure Execute;
    procedure Expire(const AEntry: TEntry);
  public
    /// <summary>ATimeoutMs = 0 schaltet die Überwachung ab.</summary>
    constructor Create(const APending: IJsonRpcPendingRequests; ATimeoutMs: Cardinal;
      const AOnTimeout: TJsonRpcTimeoutEvent);
    destructor Destroy; override;
    function Watch(const AId: TJSONValue; const AMethod: string): Int64;
    procedure Unwatch(ATicket: Int64);
  end;

implementation

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
    Entry.Id.Free;
  FEntries.Free;
  inherited;
end;

function TJsonRpcWatchdog.Watch(const AId: TJSONValue; const AMethod: string): Int64;
var
  Entry: TEntry;
begin
  if FThread = nil then
    Exit(0);
  Entry.Id := TJSONValue(AId.Clone);
  Entry.Method := AMethod;
  Entry.Due := TThread.GetTickCount64 + FTimeout;
  TMonitor.Enter(FEntries);
  try
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
    Exit;
  TMonitor.Enter(FEntries);
  try
    if not FEntries.TryGetValue(ATicket, Entry) then
      Exit;
    FEntries.Remove(ATicket);
  finally
    TMonitor.Exit(FEntries);
  end;
  Entry.Id.Free;
end;

procedure TJsonRpcWatchdog.Expire(const AEntry: TEntry);
begin
  try
    FPending.Cancel(AEntry.Id);
    if Assigned(FOnTimeout) then
      FOnTimeout(AEntry.Method, FTimeout);
  finally
    AEntry.Id.Free;
  end;
end;

procedure TJsonRpcWatchdog.Execute;
var
  Pair: TPair<Int64, TEntry>;
  Expired: TList<TEntry>;
  Entry: TEntry;
  Ticks: UInt64;
  NextDue: UInt64;
begin
  Expired := TList<TEntry>.Create;
  try
    while True do
    begin
      TMonitor.Enter(FEntries);
      try
        if FStopping then
          Exit;
        Ticks := TThread.GetTickCount64;
        NextDue := High(UInt64);
        for Pair in FEntries do
          if Pair.Value.Due <= Ticks then
            Expired.Add(Pair.Value)
          else if Pair.Value.Due < NextDue then
            NextDue := Pair.Value.Due;
        for Pair in FEntries.ToArray do
          if Pair.Value.Due <= Ticks then
            FEntries.Remove(Pair.Key);
        if Expired.Count = 0 then
        begin
          if NextDue = High(UInt64) then
            TMonitor.Wait(FEntries, WaitForever)
          else
            TMonitor.Wait(FEntries, Cardinal(NextDue - Ticks));
        end;
      finally
        TMonitor.Exit(FEntries);
      end;
      // Außerhalb der Sperre: Cancel und Meldung dürfen dauern.
      for Entry in Expired do
        try
          Expire(Entry);
        except
          // Eine fehlerhafte Meldung darf die Überwachung nicht beenden.
        end;
      Expired.Clear;
    end;
  finally
    Expired.Free;
  end;
end;

end.
