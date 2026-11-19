unit Atlas.Core.Diagnostics.BackgroundJobs;

// Aufträge im Hintergrund mit Ergebnis im Hauptthread, vor allem Aufrufe der
// Versionsverwaltung (#571): Run startet die Arbeit in einem eigenen Thread und
// reicht das Ergebnis über TThread.Queue in den Hauptthread. Der Prozessläufer
// prüft TThread.CheckTerminated; Stop beendet darum laufende git- bzw.
// svn-Prozesse sofort, entfernt noch nicht zugestellte Ergebnisse und wartet
// höchstens AMs auf die Threads.
// Nutzung (Willkommensseite, Projektzustand …):
//   Jobs.Run(
//     procedure begin Outcome := Vcs.Head(Head); end,     // Hintergrund
//     procedure begin Zeigen(Outcome, Head); end);         // Hauptthread
// Die Arbeit fängt ihre Fehler selbst; eine Ausnahme verwirft der Auftrag und
// ruft ADone trotzdem.
// Threads, die nach Stop noch laufen, gehen an TAtlasOverdueThreads, zusammen
// mit dem Package, in dem der Code der Arbeit liegt (AModule, im Package
// HInstance): Die Liste gibt sie nach ihrem Ende frei, und die Modulverwaltung
// hält das Package fest, solange sie laufen. Ein Ergebnis, das ein solcher
// Thread noch einreiht, verwirft IAtlasBackgroundJobsAlive, ohne das Objekt
// oder den Aufrufer zu berühren.
// Anders als TAtlasThreadList gibt Run beendete Threads nicht frei: Ihr
// Ergebnis steht womöglich noch in der Warteschlange, und Freigeben entfernt
// es. Freigegeben wird nach der Zustellung oder in Stop.
// Liegt unter Diagnostics, nicht unter VersionControl: Atlas.Core.VersionControl.*
// übersetzt auch der Server mit, und der kennt weder Hauptthread noch Module.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  /// <summary>Merker, ob die Aufträge noch Ergebnisse zustellen; eingereihte Ergebnisse halten ihn selbst.</summary>
  IAtlasBackgroundJobsAlive = interface
    ['{206DF1A8-5D82-40D8-AA37-2CC34C747183}']
    function Alive: Boolean;
    procedure Kill;
  end;

  TAtlasBackgroundJobs = class
  public const
    /// <summary>Wartezeit von Stop beim Freigeben.</summary>
    cDestroyStopMs = 1000;
  private
    FModule: HMODULE;
    FLock: TCriticalSection;
    FThreads: TList<TThread>;
    FStopped: Boolean;
    FAlive: IAtlasBackgroundJobsAlive;
    procedure Finished(AThread: TThread);
    /// <summary>Thread aus der Liste nehmen; False, wenn er nicht (mehr) darin steht.</summary>
    function Take(AThread: TThread): Boolean;
    /// <summary>Die Threads der Liste; AClear leert sie dabei.</summary>
    function Snapshot(AClear: Boolean): TArray<TThread>;
  public
    /// <summary>AModule: Package, in dem der Code der Arbeit (AWork, ADone) liegt (im Package HInstance).</summary>
    constructor Create(AModule: HMODULE);
    /// <summary>Stop mit cDestroyStopMs; Threads, die dann noch laufen, gibt TAtlasOverdueThreads nach ihrem Ende frei.
    /// </summary>
    destructor Destroy; override;
    /// <summary>AWork im Hintergrund, danach ADone im Hauptthread (nicht nach Stop). Aus dem Hauptthread
    /// aufrufen; nach Stop wirkungslos. False, wenn nichts gestartet wurde (dann kommt auch ADone nie).</summary>
    function Run(const AWork, ADone: TProc): Boolean;
    /// <summary>Keine weiteren Ergebnisse; laufende Prozesse abbrechen und höchstens AMs auf die Threads warten.
    /// True, wenn alle beendet sind. Überfällige gehen an TAtlasOverdueThreads.</summary>
    function Stop(AMs: Cardinal): Boolean;
    /// <summary>Laufende oder noch nicht zugestellte Aufträge.</summary>
    function Pending: Integer;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  TJobsAlive = class(TInterfacedObject, IAtlasBackgroundJobsAlive)
  private
    FAlive: Boolean;
  public
    constructor Create;
    function Alive: Boolean;
    procedure Kill;
  end;

{ TJobsAlive }

constructor TJobsAlive.Create;
begin
  inherited Create;
  FAlive := True;
end;

function TJobsAlive.Alive: Boolean;
begin
  Result := FAlive;
end;

procedure TJobsAlive.Kill;
begin
  FAlive := False;
end;

{ TAtlasBackgroundJobs }

constructor TAtlasBackgroundJobs.Create(AModule: HMODULE);
begin
  inherited Create;
  FModule := AModule;
  FLock := TCriticalSection.Create;
  FThreads := TList<TThread>.Create;
  FAlive := TJobsAlive.Create;
end;

destructor TAtlasBackgroundJobs.Destroy;
begin
  Stop(cDestroyStopMs);
  FThreads.Free;
  FLock.Free;
  inherited;
end;

function TAtlasBackgroundJobs.Snapshot(AClear: Boolean): TArray<TThread>;
begin
  FLock.Enter;
  try
    Result := FThreads.ToArray;
    if AClear then
    begin
      FThreads.Clear;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasBackgroundJobs.Take(AThread: TThread): Boolean;
begin
  FLock.Enter;
  try
    Result := FThreads.Remove(AThread) >= 0;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasBackgroundJobs.Finished(AThread: TThread);
begin
  // Im Hauptthread, aus dem zugestellten Ergebnis: Der Thread ist am Ende seiner Arbeit.
  if Take(AThread) then
  begin
    AThread.WaitFor;
    AThread.Free;
  end;
end;

function TAtlasBackgroundJobs.Run(const AWork, ADone: TProc): Boolean;
var
  mThread: TThread;
  mWork, mDone: TProc;
  mAlive: IAtlasBackgroundJobsAlive;
  mOwner: TAtlasBackgroundJobs;
begin
  Result := False;
  if FStopped then
  begin
    Exit;
  end;
  mWork := AWork;
  mDone := ADone;
  mAlive := FAlive;
  mOwner := Self;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mCurrent: TThread;
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
      mCurrent := TThread.Current;
      TThread.Queue(mCurrent,
        procedure
        begin
          // Nach Stop gehört der Thread nicht mehr diesem Objekt, und der Aufrufer ist womöglich schon frei.
          if not mAlive.Alive then
          begin
            Exit;
          end;
          try
            if Assigned(mDone) then
            begin
              mDone();
            end;
          finally
            mOwner.Finished(mCurrent);
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

function TAtlasBackgroundJobs.Stop(AMs: Cardinal): Boolean;
var
  mThreads: TArray<TThread>;
  mThread: TThread;
begin
  FStopped := True;
  FAlive.Kill;
  mThreads := Snapshot(True);
  for mThread in mThreads do
  begin
    mThread.Terminate;
    // Noch nicht zugestellte Ergebnisse verwerfen.
    TThread.RemoveQueuedEvents(mThread);
  end;
  Result := TAtlasShutdown.WaitForThreads(mThreads, AMs);
  for mThread in mThreads do
  begin
    // Ein Ergebnis kann zwischen RemoveQueuedEvents und dem Ende noch eingereiht worden sein.
    TThread.RemoveQueuedEvents(mThread);
    if mThread.Finished then
    begin
      mThread.Free;
    end
    else
    begin
      TAtlasOverdueThreads.Adopt(mThread, FModule);
    end;
  end;
end;

function TAtlasBackgroundJobs.Pending: Integer;
begin
  Result := Length(Snapshot(False));
end;

end.
