unit Atlas.Core.VersionControl.Worker;

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
    /// aufrufen; nach Stop wirkungslos. False, wenn nichts gestartet wurde (dann kommt auch ADone nie).</summary>
    function Run(const AWork, ADone: TProc): Boolean;
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

function TAtlasVcsWorker.Run(const AWork, ADone: TProc): Boolean;
var
  mThread: TThread;
  mWork, mDone: TProc;
begin
  Result := False;
  if FStopped then
  begin
    Exit;
  end;
  mWork := AWork;
  mDone := ADone;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      Current: TThread;
    begin
      try
        mWork();
      except
        // Die Arbeit meldet ihre Fehler selbst; ADone kommt trotzdem.
        on Exception do
          ;
      end;
      if TThread.CheckTerminated then
      begin
        Exit;
      end;
      Current := TThread.Current;
      TThread.Queue(Current,
        procedure
        begin
          try
            if Assigned(mDone) then
            begin
              mDone();
            end;
          finally
            Finished(Current);
          end;
        end);
    end);
  mThread.FreeOnTerminate := False;
  FLock.Enter;
  try
    FThreads.Add(mThread);
  finally
    FLock.Leave;
  end;
  mThread.Start;
  Result := True;
end;

function TAtlasVcsWorker.Stop(AMs: Cardinal): Boolean;
var
  mThreads: TArray<TThread>;
  mThread: TThread;
  mDeadline: UInt64;
  mRunning: Boolean;
begin
  FStopped := True;
  FLock.Enter;
  try
    mThreads := FThreads.ToArray;
  finally
    FLock.Leave;
  end;
  for mThread in mThreads do
  begin
    mThread.Terminate;
    // Noch nicht zugestellte Ergebnisse verwerfen.
    TThread.RemoveQueuedEvents(mThread);
  end;
  mDeadline := TThread.GetTickCount64 + AMs;
  repeat
    mRunning := False;
    for mThread in mThreads do
    begin
      if not mThread.Finished then
      begin
        mRunning := True;
      end;
    end;
    if not mRunning or (TThread.GetTickCount64 >= mDeadline) then
    begin
      Break;
    end;
    Sleep(10);
  until False;
  Result := not mRunning;
  for mThread in mThreads do
  begin
    // Ein Thread, der nach dem Signal noch arbeitet, wird nicht freigegeben: lieber ein Rest im Speicher als
    // ein Absturz beim Entladen.
    if not mThread.Finished then
    begin
      Continue;
    end;
    // Ein Ergebnis kann zwischen RemoveQueuedEvents und dem Ende noch eingereiht worden sein.
    TThread.RemoveQueuedEvents(mThread);
    FLock.Enter;
    try
      FThreads.Remove(mThread);
    finally
      FLock.Leave;
    end;
    mThread.Free;
  end;
end;

end.
