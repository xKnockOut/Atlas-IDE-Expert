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

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
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

const
  // Wartende prüfen so oft den Abbruch.
  PollMs = 100;

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
  Entry: TEntry;
  Ticket: Int64;
begin
  Entry.Priority := APriority;
  Entry.Stage := TIndexStage.Project;
  Entry.WaitingSince := 0;
  TMonitor.Enter(FLock);
  try
    Inc(FNextTicket);
    Ticket := FNextTicket;
    FEntries.Add(Ticket, Entry);
  finally
    TMonitor.Exit(FLock);
  end;
  Result := TIndexTurn.Create(Self, Ticket);
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
      Result.Running := 1;
    for mPair in FEntries do
      if mPair.Value.WaitingSince <> 0 then
      begin
        Inc(Result.Waiting);
        if Int64(mNow - mPair.Value.WaitingSince) > Result.OldestWaitMs then
          Result.OldestWaitMs := Int64(mNow - mPair.Value.WaitingSince);
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
    Exit;
  if AWaiting then
    mEntry.WaitingSince := TThread.GetTickCount64
  else
    mEntry.WaitingSince := 0;
  FEntries[ATicket] := mEntry;
end;

function TIndexScheduler.MayRun(ATicket: Int64; const AEntry: TEntry): Boolean;
var
  Other: TPair<Int64, TEntry>;
begin
  if (FRunning <> 0) and (FRunning <> ATicket) then
    Exit(False);
  for Other in FEntries do
  begin
    if Other.Key = ATicket then
      Continue;
    if Other.Value.Stage < AEntry.Stage then
      Exit(False);
    // Gleiche Stufe: kleinere Priorität, bei gleicher die frühere Anmeldung zuerst.
    if (Other.Value.Stage = AEntry.Stage) and ((Other.Value.Priority < AEntry.Priority) or
      ((Other.Value.Priority = AEntry.Priority) and (Other.Key < ATicket))) then
      Exit(False);
  end;
  Result := True;
end;

function TIndexScheduler.Enter(ATicket: Int64; AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
var
  Entry: TEntry;
begin
  TMonitor.Enter(FLock);
  try
    if not FEntries.TryGetValue(ATicket, Entry) then
      Exit(True);
    Entry.Stage := AStage;
    Entry.WaitingSince := TThread.GetTickCount64;
    FEntries[ATicket] := Entry;
    // Andere sehen die neue Stufe sofort.
    TMonitor.PulseAll(FLock);
    while not MayRun(ATicket, Entry) do
    begin
      if Assigned(ACancelled) and ACancelled() then
      begin
        SetWaiting(ATicket, False);
        Exit(False);
      end;
      TMonitor.Wait(FLock, PollMs);
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
  Entry: TEntry;
begin
  TMonitor.Enter(FLock);
  try
    if FRunning = ATicket then
      FRunning := 0;
    // Bis zur nächsten Stufe zählt der Aufbau als hinter der verlassenen; so kommen andere an die Reihe.
    if FEntries.TryGetValue(ATicket, Entry) and (Entry.Stage < High(TIndexStage)) then
    begin
      Entry.Stage := Succ(Entry.Stage);
      FEntries[ATicket] := Entry;
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
      FRunning := 0;
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
