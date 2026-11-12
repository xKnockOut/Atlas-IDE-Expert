unit Atlas.Common.JsonRpc.WorkerPool;

// Eigene Arbeitsthreads für nebenläufige Anfragen des Servers.
//
// Vorher liefen sie über TTask.Run im Standard-Threadpool der RTL. Der hält
// sofort nur etwa so viele Threads bereit, wie der Rechner Kerne hat; weitere
// legt sein Wächter höchstens alle 500 ms an und gar nicht, solange die
// CPU-Last hoch ist. Anfragen, die warten statt rechnen (workspace/diagnostic
// mit Long-Polling bis 10 s, textDocument/diagnostic auf die Prüfung der Datei,
// Befehle, die auf den Index warten), belegten so die Plätze, und kurze
// Anfragen (documentSymbol, hover, codeAction, atlas.server.status) standen in
// der Warteschlange dahinter. Folge im Diagnoselog: codeAction im Mittel 4,5 s,
// Zeitüberschreitungen bei Befehlen, die selbst Millisekunden brauchen.
// Nachgestellt mit 16 gleichzeitigen Prüfungen: documentSymbol (30 ms Arbeit)
// wartete 6 s.
//
// Jetzt: Ist kein Thread frei, startet Run sofort einen neuen, bis MaxThreads.
// Erst darüber warten Aufträge in der Reihenfolge ihres Eingangs. Ein Thread
// ohne Arbeit endet nach IdleMs. Close nimmt keine Aufträge mehr an, lässt die
// angenommenen zu Ende laufen und wartet höchstens ATimeoutMs auf die Threads.
// Die Threads halten den Pool über eine Interface-Referenz; endet Close vor
// ihnen, bleibt er bis zu ihrem Ende gültig.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  IJsonRpcWorkerPool = interface
    ['{B6225FD3-3BA4-423A-9AAC-55826345819D}']
    /// <summary>Führt AWork in einem Arbeitsthread aus; False nach Close (AWork läuft dann nicht).
    /// Ausnahmen von AWork verschluckt der Pool; Handler fangen ihre Fehler selbst.</summary>
    function Run(const AWork: TProc): Boolean;
    /// <summary>Keine neuen Aufträge; wartet höchstens ATimeoutMs, bis alle Threads geendet haben.
    /// False, wenn danach noch Threads laufen.</summary>
    function Close(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Zahl der Threads, die gerade bestehen (arbeitend oder wartend).</summary>
    function ThreadCount: Integer;
  end;

  TJsonRpcWorkerPool = class(TInterfacedObject, IJsonRpcWorkerPool)
  public const
    /// <summary>Obergrenze gleichzeitiger Threads; darüber warten Aufträge.</summary>
    cDefaultMaxThreads = 64;
    /// <summary>So lange wartet ein Thread ohne Arbeit, bevor er endet.</summary>
    cDefaultIdleMs = 30000;
  private type
    TWorker = class(TThread)
    private
      FPool: TJsonRpcWorkerPool;
      // Hält den Pool am Leben, solange der Thread läuft.
      FKeep: IInterface;
    protected
      procedure Execute; override;
    public
      constructor Create(APool: TJsonRpcWorkerPool);
    end;
  private
    FLock: TObject;
    FQueue: TQueue<TProc>;
    // Threads, die Close freigibt; ein Thread, der nach IdleMs endet, nimmt sich heraus und gibt sich selbst frei.
    FWorkers: TList<TWorker>;
    FWaiting: Integer;
    FClosed: Boolean;
    FMaxThreads: Integer;
    FIdleMs: Cardinal;
    /// <summary>Nächster Auftrag für AWorker; False, wenn der Thread enden soll.</summary>
    function Take(AWorker: TWorker; out AWork: TProc): Boolean;
    /// <summary>Wartet bis ADue (Ticks), bis alle AWorkers geendet haben.</summary>
    class function AllFinished(const AWorkers: TArray<TWorker>; ADue: UInt64): Boolean; static;
  public
    constructor Create; overload;
    constructor Create(AMaxThreads: Integer; AIdleMs: Cardinal); overload;
    destructor Destroy; override;
    function Run(const AWork: TProc): Boolean;
    function Close(ATimeoutMs: Cardinal): Boolean;
    function ThreadCount: Integer;
  end;

implementation

{ TJsonRpcWorkerPool.TWorker }

constructor TJsonRpcWorkerPool.TWorker.Create(APool: TJsonRpcWorkerPool);
begin
  FPool := APool;
  FKeep := APool;
  inherited Create(True);
  FreeOnTerminate := False;
end;

procedure TJsonRpcWorkerPool.TWorker.Execute;
var
  mWork: TProc;
begin
  try
    while FPool.Take(Self, mWork) do
    begin
      try
        mWork();
      except
        // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Arbeitsthreads; der Dispatcher meldet Fehler selbst
        on Exception do
        begin
        end;
      end;
      // Erfasstes des Auftrags nicht bis zum nächsten festhalten.
      mWork := nil;
    end;
  finally
    // Letzte Referenz: Der Pool kann mit dem Thread enden, wenn Close nicht mehr auf ihn wartet.
    FKeep := nil;
  end;
end;

{ TJsonRpcWorkerPool }

constructor TJsonRpcWorkerPool.Create;
begin
  Create(cDefaultMaxThreads, cDefaultIdleMs);
end;

constructor TJsonRpcWorkerPool.Create(AMaxThreads: Integer; AIdleMs: Cardinal);
begin
  inherited Create;
  FLock := TObject.Create;
  FQueue := TQueue<TProc>.Create;
  FWorkers := TList<TWorker>.Create;
  FMaxThreads := AMaxThreads;
  if FMaxThreads < 1 then
  begin
    FMaxThreads := 1;
  end;
  FIdleMs := AIdleMs;
end;

destructor TJsonRpcWorkerPool.Destroy;
begin
  // Hier läuft kein Thread mehr: Jeder hält den Pool über FKeep.
  FWorkers.Free;
  FQueue.Free;
  FLock.Free;
  inherited Destroy;
end;

function TJsonRpcWorkerPool.Run(const AWork: TProc): Boolean;
var
  mWorker: TWorker;
begin
  System.TMonitor.Enter(FLock);
  try
    if FClosed then
    begin
      Exit(False);
    end;
    FQueue.Enqueue(AWork);
    // Mehr Aufträge als wartende Threads: sofort einen weiteren starten, nicht auf einen freien warten.
    if (FQueue.Count > FWaiting) and (FWorkers.Count < FMaxThreads) then
    begin
      mWorker := TWorker.Create(Self);
      FWorkers.Add(mWorker);
      mWorker.Start;
    end
    else
    begin
      System.TMonitor.Pulse(FLock);
    end;
    Result := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TJsonRpcWorkerPool.Take(AWorker: TWorker; out AWork: TProc): Boolean;
var
  mSignaled: Boolean;
begin
  AWork := nil;
  System.TMonitor.Enter(FLock);
  try
    while True do
    begin
      // Angenommene Aufträge laufen auch nach Close: Jede Anfrage bekommt ihre Antwort.
      if FQueue.Count > 0 then
      begin
        // Mit (): Dequeue liefert eine Methodenreferenz, ohne Klammern sieht Delphi die Methode selbst (E2010).
        AWork := FQueue.Dequeue();
        Exit(True);
      end;
      if FClosed then
      begin
        Exit(False);
      end;
      Inc(FWaiting);
      try
        mSignaled := System.TMonitor.Wait(FLock, FIdleMs);
      finally
        Dec(FWaiting);
      end;
      if not mSignaled and (FQueue.Count = 0) and not FClosed then
      begin
        // Lange nichts zu tun: Der Thread endet und gibt sich selbst frei; Close wartet nicht mehr auf ihn.
        FWorkers.Remove(AWorker);
        AWorker.FreeOnTerminate := True;
        Exit(False);
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class function TJsonRpcWorkerPool.AllFinished(const AWorkers: TArray<TWorker>; ADue: UInt64): Boolean;
var
  mWorker: TWorker;
begin
  for mWorker in AWorkers do
  begin
    while not mWorker.Finished do
    begin
      if TThread.GetTickCount64 >= ADue then
      begin
        Exit(False);
      end;
      TThread.Sleep(5);
    end;
  end;
  Result := True;
end;

function TJsonRpcWorkerPool.Close(ATimeoutMs: Cardinal): Boolean;
var
  mWorkers: TArray<TWorker>;
  mWorker: TWorker;
begin
  // Der Aufrufer hält den Pool über sein Interface; enden alle Threads, bleibt er trotzdem gültig.
  System.TMonitor.Enter(FLock);
  try
    FClosed := True;
    System.TMonitor.PulseAll(FLock);
    mWorkers := FWorkers.ToArray;
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result := AllFinished(mWorkers, TThread.GetTickCount64 + ATimeoutMs);
  if not Result then
  begin
    // Noch beschäftigte Threads halten den Pool bis zu ihrem Ende und geben sich dann selbst frei. Endet einer
    // genau jetzt, sieht er das vielleicht nicht mehr: höchstens ein Leck, nie ein doppeltes Free.
    for mWorker in mWorkers do
    begin
      if not mWorker.Finished then
      begin
        mWorker.FreeOnTerminate := True;
      end;
    end;
    Exit;
  end;
  System.TMonitor.Enter(FLock);
  try
    FWorkers.Clear;
  finally
    System.TMonitor.Exit(FLock);
  end;
  for mWorker in mWorkers do
  begin
    mWorker.WaitFor;
    mWorker.Free;
  end;
end;

function TJsonRpcWorkerPool.ThreadCount: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FWorkers.Count;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
