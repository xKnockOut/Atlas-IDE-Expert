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
//
// Freigabe: Wer einen Thread freigibt, entscheidet der Thread selbst unter der
// Sperre, wenn er Execute verlässt. Endet er nach IdleMs oder nachdem Close
// aufgegeben hat, gibt er sich selbst frei (FreeOnTerminate); sonst gibt ihn
// Close frei. So hält FWorkers nie einen Zeiger auf ein Objekt, das sich selbst
// freigibt, und ein zweites Close ist harmlos.

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
    /// <summary>Zahl der Threads, die gerade laufen (arbeitend oder wartend), auch nach einem Close mit
    /// False.</summary>
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
      // Unter FLock: Execute ist verlassen, Close gibt den Thread frei.
      FDone: Boolean;
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
    // Threads, die Close freigibt; wer sich selbst freigibt, steht nicht (mehr) darin.
    FWorkers: TList<TWorker>;
    // Threads, die Execute noch nicht verlassen haben.
    FAlive: Integer;
    FWaiting: Integer;
    FClosed: Boolean;

    FMaxThreads: Integer;
    FIdleMs: Cardinal;
    /// <summary>Nächster Auftrag für AWorker; False, wenn der Thread enden soll.</summary>
    function Take(AWorker: TWorker; out AWork: TProc): Boolean;
    /// <summary>Ende von Execute: Zählt AWorker ab und legt fest, wer ihn freigibt.</summary>
    procedure Leave(AWorker: TWorker);
    /// <summary>Wartet unter FLock bis ADue (Ticks), bis kein Thread mehr läuft; weckt Leave.</summary>
    function WaitAllLeft(ADue: UInt64): Boolean;
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
    FPool.Leave(Self);
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
    // Mehr Aufträge als wartende Threads: sofort einen weiteren starten, nicht auf einen freien warten.
    if (FQueue.Count >= FWaiting) and (FAlive < FMaxThreads) then
    begin
      // Erst den Thread, dann den Auftrag: Scheitert der Start, sieht der Aufrufer die Ausnahme und der
      // Auftrag läuft nicht. Der neue Thread wartet in Take auf die Sperre, bis der Auftrag eingereiht ist.
      mWorker := TWorker.Create(Self);
      try
        mWorker.Start;
      except
        mWorker.Free;
        raise;
      end;
      FWorkers.Add(mWorker);
      Inc(FAlive);
      FQueue.Enqueue(AWork);
    end
    else
    begin
      FQueue.Enqueue(AWork);
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
        // Lange nichts zu tun: Der Thread endet und gibt sich selbst frei (Leave); Close gibt ihn nicht frei.
        FWorkers.Remove(AWorker);
        Exit(False);
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TJsonRpcWorkerPool.Leave(AWorker: TWorker);
begin
  System.TMonitor.Enter(FLock);
  try
    Dec(FAlive);
    if FWorkers.Contains(AWorker) then
    begin
      // Close wartet auf den Thread oder kommt noch: Close gibt ihn frei.
      AWorker.FDone := True;
    end
    else
    begin
      // Nach IdleMs beendet oder von Close aufgegeben: Niemand sonst kennt den Thread mehr.
      AWorker.FreeOnTerminate := True;
    end;
    if FClosed then
    begin
      // Weckt Close; Threads warten nach Close nicht mehr auf Arbeit (Take), anderen schadet der Weckruf nicht.
      System.TMonitor.PulseAll(FLock);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TJsonRpcWorkerPool.WaitAllLeft(ADue: UInt64): Boolean;
var
  mNow: UInt64;
begin
  while FAlive > 0 do
  begin
    mNow := TThread.GetTickCount64;
    if mNow >= ADue then
    begin
      Exit(False);
    end;
    System.TMonitor.Wait(FLock, Cardinal(ADue - mNow));
  end;
  Result := True;
end;

function TJsonRpcWorkerPool.Close(ATimeoutMs: Cardinal): Boolean;
var
  mFree: TList<TWorker>;
  mWorker: TWorker;
begin
  // Der Aufrufer hält den Pool über sein Interface; enden alle Threads, bleibt er trotzdem gültig.
  mFree := TList<TWorker>.Create;
  try
    System.TMonitor.Enter(FLock);
    try
      FClosed := True;
      System.TMonitor.PulseAll(FLock);
      Result := WaitAllLeft(TThread.GetTickCount64 + ATimeoutMs);
      // Beendete Threads gibt Close frei. Die noch laufenden geben sich beim Ende selbst frei (Leave sieht sie
      // nicht mehr in FWorkers) und halten den Pool bis dahin über FKeep.
      for mWorker in FWorkers do
      begin
        if mWorker.FDone then
        begin
          mFree.Add(mWorker);
        end;
      end;
      FWorkers.Clear;
    finally
      System.TMonitor.Exit(FLock);
    end;
    // Außerhalb der Sperre: Execute ist verlassen, WaitFor wartet nur auf das Ende des Threads selbst.
    for mWorker in mFree do
    begin
      mWorker.WaitFor;
      mWorker.Free;
    end;
  finally
    mFree.Free;
  end;
end;

function TJsonRpcWorkerPool.ThreadCount: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FAlive;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
