unit Atlas.Core.Diagnostics.TimeLimit;

// Blockierschutz (#493): Aufrufe von Datenquellen, die der Hauptthread der IDE
// auslöst, laufen in einem Arbeiter-Thread; der Hauptthread wartet höchstens
// LimitMs (Standard 200 ms) auf das Ende. Dauert es länger, kehrt Run mit
// TimedOut zurück, der Aufrufer bricht ab und zählt es wie einen Fehler. Der
// Arbeiter läuft dann zu Ende und kehrt erst danach in den Vorrat zurück;
// für den nächsten Aufruf startet bei Bedarf ein weiterer. Exceptions im
// Aufruf kommen als Failed mit Klasse und Meldung zurück, nie in die IDE.
// Die Arbeiter warten über TAtlasShutdown und enden beim Entladen (StopAll).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasTimedOutcome = (Done, Failed, TimedOut);
{$SCOPEDENUMS OFF}

  TAtlasTimeLimit = class
  public const
    DefaultMs = 200;
    MinMs = 50;
    MaxMs = 5000;
  private type
    TWorker = class(TThread)
    private
      FStart: TEvent;
      FDone: TEvent;
      FProc: TProc;
      FError: string;
      // Unter FLock: fertig mit dem aktuellen Aufruf bzw. vom Aufrufer aufgegeben.
      FFinished: Boolean;
      FAbandoned: Boolean;
    protected
      procedure Execute; override;
    public
      constructor Create;
      destructor Destroy; override;
    end;
  private class var
    FLock: TCriticalSection;
    FIdle: TList<TWorker>;
    FAll: TList<TWorker>;
    FLimitMs: Integer;
    class function Take: TWorker; static;
    class procedure Release(AWorker: TWorker); static;
    class procedure SetLimitMs(AValue: Integer); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>AProc mit Zeitlimit ausführen (ALimitMs < 0: LimitMs). AError: Klasse und Meldung bei Failed.</summary>
    class function Run(const AProc: TProc; out AError: string; ALimitMs: Integer = -1): TAtlasTimedOutcome; static;
    /// <summary>Alle Arbeiter beenden (nach TAtlasShutdown.Signal); True, wenn alle innerhalb von AMs enden.</summary>
    class function StopAll(AMs: Cardinal = 1000): Boolean; static;
    /// <summary>Arbeiter, die gerade einen Aufruf ausführen (auch aufgegebene).</summary>
    class function BusyCount: Integer; static;
    /// <summary>Zeitlimit für Aufrufe aus dem Hauptthread, MinMs bis MaxMs.</summary>
    class property LimitMs: Integer read FLimitMs write SetLimitMs;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown;

{ TAtlasTimeLimit.TWorker }

constructor TAtlasTimeLimit.TWorker.Create;
begin
  FStart := TEvent.Create(nil, False, False, '');
  FDone := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasTimeLimit.TWorker.Destroy;
begin
  inherited Destroy;
  FDone.Free;
  FStart.Free;
end;

procedure TAtlasTimeLimit.TWorker.Execute;
var
  Proc: TProc;
  Error: string;
  Abandoned: Boolean;
begin
  while not Terminated do
  begin
    if TAtlasShutdown.WaitFor(FStart, 1000) <> wrSignaled then
    begin
      if TAtlasShutdown.Signalled then
        Exit;
      Continue;
    end;
    if Terminated then
      Exit;
    Proc := FProc;
    Error := '';
    try
      if Assigned(Proc) then
        Proc();
    except
      on E: Exception do
        Error := E.ClassName + ': ' + E.Message;
    end;
    Proc := nil;
    // StopAll hat aufgegeben (Entladen): nichts mehr anfassen, was dem Vorrat gehört.
    if Terminated then
      Exit;
    TAtlasTimeLimit.FLock.Enter;
    try
      FProc := nil;
      FError := Error;
      FFinished := True;
      Abandoned := FAbandoned;
      FAbandoned := False;
      FDone.SetEvent;
    finally
      TAtlasTimeLimit.FLock.Leave;
    end;
    // Der Aufrufer hat aufgegeben: Erst jetzt ist der Arbeiter wieder frei.
    if Abandoned then
      TAtlasTimeLimit.Release(Self);
  end;
end;

{ TAtlasTimeLimit }

class constructor TAtlasTimeLimit.Create;
begin
  FLock := TCriticalSection.Create;
  FIdle := TList<TWorker>.Create;
  FAll := TList<TWorker>.Create;
  FLimitMs := DefaultMs;
end;

class destructor TAtlasTimeLimit.Destroy;
begin
  StopAll;
  FreeAndNil(FAll);
  FreeAndNil(FIdle);
  FreeAndNil(FLock);
end;

class procedure TAtlasTimeLimit.SetLimitMs(AValue: Integer);
begin
  if AValue < MinMs then
    AValue := MinMs;
  if AValue > MaxMs then
    AValue := MaxMs;
  FLimitMs := AValue;
end;

class function TAtlasTimeLimit.Take: TWorker;
begin
  FLock.Enter;
  try
    Result := nil;
    while (Result = nil) and (FIdle.Count > 0) do
    begin
      Result := FIdle.Last;
      FIdle.Delete(FIdle.Count - 1);
      // Nach einem Abbruchsignal beendet: verwerfen.
      if Result.Finished then
      begin
        FAll.Remove(Result);
        Result.Free;
        Result := nil;
      end;
    end;
    if Result = nil then
    begin
      Result := TWorker.Create;
      FAll.Add(Result);
    end;
    Result.FFinished := False;
    Result.FAbandoned := False;
    Result.FError := '';
    Result.FDone.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

class procedure TAtlasTimeLimit.Release(AWorker: TWorker);
begin
  FLock.Enter;
  try
    if FAll.Contains(AWorker) and not FIdle.Contains(AWorker) then
      FIdle.Add(AWorker);
  finally
    FLock.Leave;
  end;
end;

class function TAtlasTimeLimit.Run(const AProc: TProc; out AError: string; ALimitMs: Integer): TAtlasTimedOutcome;
var
  Worker: TWorker;
  Limit: Cardinal;
  Finished: Boolean;
begin
  AError := '';
  if TAtlasShutdown.Signalled then
  begin
    AError := 'Atlas wird beendet';
    Exit(TAtlasTimedOutcome.Failed);
  end;
  if ALimitMs < 0 then
    Limit := FLimitMs
  else
    Limit := ALimitMs;
  Worker := Take;
  Worker.FProc := AProc;
  Worker.FStart.SetEvent;
  Worker.FDone.WaitFor(Limit);
  FLock.Enter;
  try
    Finished := Worker.FFinished;
    if Finished then
      AError := Worker.FError
    else
      Worker.FAbandoned := True;
  finally
    FLock.Leave;
  end;
  if not Finished then
    Exit(TAtlasTimedOutcome.TimedOut);
  Release(Worker);
  if AError <> '' then
    Result := TAtlasTimedOutcome.Failed
  else
    Result := TAtlasTimedOutcome.Done;
end;

class function TAtlasTimeLimit.BusyCount: Integer;
begin
  FLock.Enter;
  try
    Result := FAll.Count - FIdle.Count;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasTimeLimit.StopAll(AMs: Cardinal): Boolean;
var
  Workers: TArray<TWorker>;
  Worker: TWorker;
  Threads: TArray<TThread>;
begin
  if FLock = nil then
    Exit(True);
  FLock.Enter;
  try
    Workers := FAll.ToArray;
    FAll.Clear;
    FIdle.Clear;
  finally
    FLock.Leave;
  end;
  Threads := nil;
  for Worker in Workers do
  begin
    Worker.Terminate;
    Worker.FStart.SetEvent;
    Threads := Threads + [TThread(Worker)];
  end;
  Result := TAtlasShutdown.WaitForThreads(Threads, AMs);
  for Worker in Workers do
    if Worker.Finished then
      Worker.Free
    else
      // Hängt im Aufruf einer Quelle: gibt sich selbst frei, sobald er zurückkehrt.
      Worker.FreeOnTerminate := True;
end;

end.
