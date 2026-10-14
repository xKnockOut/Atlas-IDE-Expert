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

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract;

type
  TIndexScheduler = class
  private type
    TEntry = record
      Priority: Integer;
      Stage: TIndexStage;
    end;
  private
    FLock: TObject;
    FEntries: TDictionary<Int64, TEntry>;
    FNextTicket: Int64;
    FRunning: Int64;
    function MayRun(ATicket: Int64; const AEntry: TEntry): Boolean;
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
    FEntries[ATicket] := Entry;
    // Andere sehen die neue Stufe sofort.
    TMonitor.PulseAll(FLock);
    while not MayRun(ATicket, Entry) do
    begin
      if Assigned(ACancelled) and ACancelled() then
        Exit(False);
      TMonitor.Wait(FLock, PollMs);
    end;
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
