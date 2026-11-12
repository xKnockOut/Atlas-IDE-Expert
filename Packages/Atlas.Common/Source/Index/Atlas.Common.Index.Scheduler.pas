unit Atlas.Common.Index.Scheduler;

// Reihenfolge der Aufbauten mehrerer Projekte (#648). Alle Projekte einer
// Projektgruppe teilen einen Symbolindex; ihre Aufbauten laufen nacheinander
// und stufenweise: erst die Projektdateien aller Projekte, dann die Units der
// Suchpfade, zuletzt die Bibliothek. Innerhalb einer Stufe kommt das Projekt
// mit der kleineren Priorität zuerst (das aktive Projekt hat 0).
//
// Jeder Aufbau holt sich mit Register ein IIndexTurn. Eine Stufe darf er erst
// betreten, wenn kein anderer Aufbau gerade läuft und kein anderer noch an
// einer früheren Stufe oder an derselben mit kleinerer Priorität steht.
// Hover und Vervollständigung sind davon nicht betroffen: EnsureUnit wartet
// nie auf den Scheduler.
//
// Queue (#1356) nennt für das Fenster „Atlas-Server“, wie viele Aufbauten auf
// eine Stufe warten, ob einer läuft und seit wann der älteste wartet.
//
// TIndexStageWatch (#2142) hält für den Status eines Arbeitsbereichs fest, in
// welcher Stufe sein Aufbau steht und ob er auf sie wartet. Watch legt dazu
// eine Hülle um das IIndexTurn des Aufbaus (auch ohne Scheduler).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  Atlas.Common.Index.Contract;

type
  /// <summary>Stand der Aufbauten für den Status (#1356).</summary>
  TIndexSchedulerQueue = record
    /// <summary>Aufbauten, die auf ihre Stufe warten.</summary>
    Waiting: Integer;
    /// <summary>1, während ein Aufbau eine Stufe bearbeitet, sonst 0.</summary>
    Running: Integer;
    /// <summary>Wartezeit des am längsten wartenden Aufbaus; 0 ohne.</summary>
    OldestWaitMs: Int64;
  end;

  /// <summary>Stand eines Aufbaus für den Status (#2142).</summary>
  TIndexStageState = record
    /// <summary>Der Aufbau steht in einer Stufe oder wartet auf sie.</summary>
    Running: Boolean;
    Stage: TIndexStage;
    /// <summary>Wartet auf seine Reihe (andere Projekte der Gruppe sind dran).</summary>
    Waiting: Boolean;
    /// <summary>Name der Stufe im Status: 'projectFiles', 'searchPaths', 'library'.</summary>
    function StageName: string;
  end;

  /// <summary>Stufe des laufenden Aufbaus eines Arbeitsbereichs (#2142); threadsicher.</summary>
  TIndexStageWatch = class
  private
    FLock: TCriticalSection;
    FState: TIndexStageState;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Hülle um AInner (nil = ohne Reihenfolge), die Enter hier festhält.</summary>
    function Watch(const AInner: IIndexTurn): IIndexTurn;
    /// <summary>Aufbau will AStage betreten und wartet, bis sie dran ist.</summary>
    procedure Entering(AStage: TIndexStage);
    /// <summary>Stufe betreten (AEntered) bzw. abgebrochen.</summary>
    procedure Entered(AEntered: Boolean);
    /// <summary>Aufbau zu Ende.</summary>
    procedure Clear;
    function State: TIndexStageState;
  end;

  TIndexScheduler = class
  private type
    TEntry = record
      Priority: Integer;
      Stage: TIndexStage;
      /// <summary>Wartet seit diesem Zeitpunkt (TThread.GetTickCount64) in Enter; 0 = wartet nicht.</summary>
      WaitingSince: UInt64;
    end;
  private
    FLock: TObject;
    FEntries: TDictionary<Int64, TEntry>;
    FNextTicket: Int64;
    FRunning: Int64;
    function MayRun(ATicket: Int64; const AEntry: TEntry): Boolean;
    /// <summary>Unter FLock: Wartemarke des Aufbaus löschen (AWaiting False).</summary>
    procedure SetWaiting(ATicket: Int64; AWaiting: Boolean);
    function Enter(ATicket: Int64; AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
    procedure Leave(ATicket: Int64);
    procedure Unregister(ATicket: Int64);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Meldet einen Aufbau an; mit der Freigabe des Ergebnisses ist er wieder abgemeldet.
    /// APriority: kleiner = früher innerhalb einer Stufe.</summary>
    function Register(APriority: Integer): IIndexTurn;
    /// <summary>Zahl der angemeldeten Aufbauten (für Tests).</summary>
    function Count: Integer;
    /// <summary>Wartende und laufende Aufbauten, älteste Wartezeit.</summary>
    function Queue: TIndexSchedulerQueue;
  end;

implementation

type
  TIndexTurn = class(TInterfacedObject, IIndexTurn)
  private
    FScheduler: TIndexScheduler;
    FTicket: Int64;
  public
    constructor Create(AScheduler: TIndexScheduler; ATicket: Int64);
    destructor Destroy; override;
    function Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
    procedure Leave;
  end;

  /// <summary>Hülle von TIndexStageWatch.Watch: reicht an FInner weiter (nil = sofort dran).</summary>
  TWatchedTurn = class(TInterfacedObject, IIndexTurn)
  private
    FInner: IIndexTurn;
    FWatch: TIndexStageWatch;
  public
    constructor Create(const AInner: IIndexTurn; AWatch: TIndexStageWatch);
    function Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
    procedure Leave;
  end;

const
  // Wartende prüfen so oft den Abbruch.
  cPollMs = 100;

{ TIndexTurn }

constructor TIndexTurn.Create(AScheduler: TIndexScheduler; ATicket: Int64);
begin
  inherited Create;
  FScheduler := AScheduler;
  FTicket := ATicket;
end;

destructor TIndexTurn.Destroy;
begin
  FScheduler.Unregister(FTicket);
  inherited;
end;

function TIndexTurn.Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
begin
  Result := FScheduler.Enter(FTicket, AStage, ACancelled);
end;

procedure TIndexTurn.Leave;
begin
  FScheduler.Leave(FTicket);
end;

{ TIndexStageState }

function TIndexStageState.StageName: string;
begin
  case Stage of
    TIndexStage.SearchPaths:
      Result := 'searchPaths';
    TIndexStage.Library_:
      Result := 'library';
  else
    Result := 'projectFiles';
  end;
end;

{ TWatchedTurn }

constructor TWatchedTurn.Create(const AInner: IIndexTurn; AWatch: TIndexStageWatch);
begin
  inherited Create;
  FInner := AInner;
  FWatch := AWatch;
end;

function TWatchedTurn.Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
begin
  FWatch.Entering(AStage);
  Result := True;
  if FInner <> nil then
  begin
    Result := FInner.Enter(AStage, ACancelled);
  end;
  FWatch.Entered(Result);
end;

procedure TWatchedTurn.Leave;
begin
  if FInner <> nil then
  begin
    FInner.Leave;
  end;
end;

{ TIndexStageWatch }

constructor TIndexStageWatch.Create;
begin
  inherited Create;
  // Kein TMonitor: Die Abbruchprüfung des Schedulers liest den Stand, während er seinen Monitor hält.
  FLock := TCriticalSection.Create;
end;

destructor TIndexStageWatch.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TIndexStageWatch.Watch(const AInner: IIndexTurn): IIndexTurn;
begin
  Result := TWatchedTurn.Create(AInner, Self);
end;

procedure TIndexStageWatch.Entering(AStage: TIndexStage);
begin
  FLock.Enter;
  try
    FState.Running := True;
    FState.Stage := AStage;
    FState.Waiting := True;
  finally
    FLock.Leave;
  end;
end;

procedure TIndexStageWatch.Entered(AEntered: Boolean);
begin
  FLock.Enter;
  try
    FState.Running := AEntered;
    FState.Waiting := False;
  finally
    FLock.Leave;
  end;
end;

procedure TIndexStageWatch.Clear;
begin
  FLock.Enter;
  try
    FState := Default(TIndexStageState);
  finally
    FLock.Leave;
  end;
end;

function TIndexStageWatch.State: TIndexStageState;
begin
  FLock.Enter;
  try
    Result := FState;
  finally
    FLock.Leave;
  end;
end;

{ TIndexScheduler }

constructor TIndexScheduler.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FEntries := TDictionary<Int64, TEntry>.Create;
end;

destructor TIndexScheduler.Destroy;
begin
  FEntries.Free;
  FLock.Free;
  inherited;
end;

function TIndexScheduler.Register(APriority: Integer): IIndexTurn;
var
  mEntry: TEntry;
  mTicket: Int64;
begin
  mEntry.Priority := APriority;
  mEntry.Stage := TIndexStage.Project;
  mEntry.WaitingSince := 0;
  TMonitor.Enter(FLock);
  try
    Inc(FNextTicket);
    mTicket := FNextTicket;
    FEntries.Add(mTicket, mEntry);
  finally
    TMonitor.Exit(FLock);
  end;
  Result := TIndexTurn.Create(Self, mTicket);
end;

function TIndexScheduler.Count: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FEntries.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexScheduler.Queue: TIndexSchedulerQueue;
var
  mPair: TPair<Int64, TEntry>;
  mNow: UInt64;
begin
  Result := Default(TIndexSchedulerQueue);
  mNow := TThread.GetTickCount64;
  TMonitor.Enter(FLock);
  try
    if FRunning <> 0 then
    begin
      Result.Running := 1;
    end;
    for mPair in FEntries do
    begin
      if mPair.Value.WaitingSince <> 0 then
      begin
        Inc(Result.Waiting);
        if Int64(mNow - mPair.Value.WaitingSince) > Result.OldestWaitMs then
        begin
          Result.OldestWaitMs := Int64(mNow - mPair.Value.WaitingSince);
        end;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexScheduler.SetWaiting(ATicket: Int64; AWaiting: Boolean);
var
  mEntry: TEntry;
begin
  if not FEntries.TryGetValue(ATicket, mEntry) then
  begin
    Exit;
  end;
  if AWaiting then
  begin
    mEntry.WaitingSince := TThread.GetTickCount64;
  end
  else
  begin
    mEntry.WaitingSince := 0;
  end;
  FEntries[ATicket] := mEntry;
end;

function TIndexScheduler.MayRun(ATicket: Int64; const AEntry: TEntry): Boolean;
var
  mOther: TPair<Int64, TEntry>;
begin
  if (FRunning <> 0) and (FRunning <> ATicket) then
  begin
    Exit(False);
  end;
  for mOther in FEntries do
  begin
    if mOther.Key = ATicket then
    begin
      Continue;
    end;
    if mOther.Value.Stage < AEntry.Stage then
    begin
      Exit(False);
    end;
    // Gleiche Stufe: kleinere Priorität, bei gleicher die frühere Anmeldung zuerst.
    if (mOther.Value.Stage = AEntry.Stage) and ((mOther.Value.Priority < AEntry.Priority) or
      ((mOther.Value.Priority = AEntry.Priority) and (mOther.Key < ATicket))) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TIndexScheduler.Enter(ATicket: Int64; AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
var
  mEntry: TEntry;
begin
  TMonitor.Enter(FLock);
  try
    if not FEntries.TryGetValue(ATicket, mEntry) then
    begin
      Exit(True);
    end;
    mEntry.Stage := AStage;
    mEntry.WaitingSince := TThread.GetTickCount64;
    FEntries[ATicket] := mEntry;
    // Andere sehen die neue Stufe sofort.
    TMonitor.PulseAll(FLock);
    while not MayRun(ATicket, mEntry) do
    begin
      if Assigned(ACancelled) and ACancelled() then
      begin
        SetWaiting(ATicket, False);
        Exit(False);
      end;
      TMonitor.Wait(FLock, cPollMs);
    end;
    SetWaiting(ATicket, False);
    FRunning := ATicket;
    Result := True;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexScheduler.Leave(ATicket: Int64);
var
  mEntry: TEntry;
begin
  TMonitor.Enter(FLock);
  try
    if FRunning = ATicket then
    begin
      FRunning := 0;
    end;
    // Bis zur nächsten Stufe zählt der Aufbau als hinter der verlassenen; so kommen andere an die Reihe.
    if FEntries.TryGetValue(ATicket, mEntry) and (mEntry.Stage < High(TIndexStage)) then
    begin
      mEntry.Stage := Succ(mEntry.Stage);
      FEntries[ATicket] := mEntry;
    end;
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexScheduler.Unregister(ATicket: Int64);
begin
  TMonitor.Enter(FLock);
  try
    FEntries.Remove(ATicket);
    if FRunning = ATicket then
    begin
      FRunning := 0;
    end;
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
