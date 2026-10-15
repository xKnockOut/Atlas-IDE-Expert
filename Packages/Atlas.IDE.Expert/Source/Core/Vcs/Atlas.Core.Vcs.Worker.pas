unit Atlas.Core.Vcs.Worker;

// Aufrufe der Versionsverwaltung im Hintergrund (#571): Run startet die Arbeit
// in einem eigenen Thread und reicht das Ergebnis über TThread.Queue in den
// Hauptthread. Der Prozessläufer prüft TThread.CheckTerminated; Stop beendet
// darum laufende git- bzw. svn-Prozesse sofort, entfernt noch nicht
// zugestellte Ergebnisse und wartet höchstens AMs auf die Threads.
// Nutzung (Willkommensseite, Projektzustand …):
//   Worker.Run(
//     procedure begin Outcome := Vcs.Head(Head); end,     // Hintergrund
//     procedure begin Zeigen(Outcome, Head); end);         // Hauptthread
// Die Arbeit fängt ihre Fehler selbst; eine Ausnahme verwirft der Worker und
// ruft ADone trotzdem.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TAtlasVcsWorker = class
  private
    FLock: TCriticalSection;
    FThreads: TList<TThread>;
    FStopped: Boolean;
    procedure Finished(AThread: TThread);
  public
    constructor Create;
    /// <summary>Stop mit 1 s; Threads, die dann noch laufen, bleiben bis zu ihrem Ende im Speicher.</summary>
    destructor Destroy; override;
    /// <summary>AWork im Hintergrund, danach ADone im Hauptthread (nicht nach Stop). Aus dem Hauptthread
    /// aufrufen; nach Stop wirkungslos.</summary>
    procedure Run(const AWork, ADone: TProc);
    /// <summary>Keine weiteren Ergebnisse; laufende Prozesse abbrechen und höchstens AMs auf die Threads warten.
    /// True, wenn alle beendet sind.</summary>
    function Stop(AMs: Cardinal): Boolean;
    /// <summary>Laufende oder noch nicht zugestellte Aufträge.</summary>
    function Pending: Integer;
  end;

implementation

{ TAtlasVcsWorker }

constructor TAtlasVcsWorker.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FThreads := TList<TThread>.Create;
end;

destructor TAtlasVcsWorker.Destroy;
begin
  Stop(1000);
  FThreads.Free;
  FLock.Free;
  inherited;
end;

function TAtlasVcsWorker.Pending: Integer;
begin
  FLock.Enter;
  try
    Result := FThreads.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasVcsWorker.Finished(AThread: TThread);
begin
  // Im Hauptthread, aus dem zugestellten Ergebnis: Der Thread ist am Ende seiner Arbeit.
  FLock.Enter;
  try
    FThreads.Remove(AThread);
  finally
    FLock.Leave;
  end;
  AThread.WaitFor;
  AThread.Free;
end;

procedure TAtlasVcsWorker.Run(const AWork, ADone: TProc);
var
  Thread: TThread;
  Work, Done: TProc;
begin
  if FStopped then
    Exit;
  Work := AWork;
  Done := ADone;
  Thread := TThread.CreateAnonymousThread(
    procedure
    var
      Current: TThread;
    begin
      try
        Work();
      except
        // Die Arbeit meldet ihre Fehler selbst; ADone kommt trotzdem.
        on Exception do
          ;
      end;
      if TThread.CheckTerminated then
        Exit;
      Current := TThread.Current;
      TThread.Queue(Current,
        procedure
        begin
          try
            if Assigned(Done) then
              Done();
          finally
            Finished(Current);
          end;
        end);
    end);
  Thread.FreeOnTerminate := False;
  FLock.Enter;
  try
    FThreads.Add(Thread);
  finally
    FLock.Leave;
  end;
  Thread.Start;
end;

function TAtlasVcsWorker.Stop(AMs: Cardinal): Boolean;
var
  Threads: TArray<TThread>;
  Thread: TThread;
  Deadline: UInt64;
  Running: Boolean;
begin
  FStopped := True;
  FLock.Enter;
  try
    Threads := FThreads.ToArray;
  finally
    FLock.Leave;
  end;
  for Thread in Threads do
  begin
    Thread.Terminate;
    // Noch nicht zugestellte Ergebnisse verwerfen.
    TThread.RemoveQueuedEvents(Thread);
  end;
  Deadline := TThread.GetTickCount64 + AMs;
  repeat
    Running := False;
    for Thread in Threads do
      if not Thread.Finished then
        Running := True;
    if not Running or (TThread.GetTickCount64 >= Deadline) then
      Break;
    Sleep(10);
  until False;
  Result := not Running;
  for Thread in Threads do
  begin
    // Ein Thread, der nach dem Signal noch arbeitet, wird nicht freigegeben: lieber ein Rest im Speicher als
    // ein Absturz beim Entladen.
    if not Thread.Finished then
      Continue;
    // Ein Ergebnis kann zwischen RemoveQueuedEvents und dem Ende noch eingereiht worden sein.
    TThread.RemoveQueuedEvents(Thread);
    FLock.Enter;
    try
      FThreads.Remove(Thread);
    finally
      FLock.Leave;
    end;
    Thread.Free;
  end;
end;

end.
