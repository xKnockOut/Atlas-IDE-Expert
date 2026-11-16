unit Atlas.Core.Debug.Phases;

// Phasen einer Debug-Sitzung ohne Open Tools API (#517 und folgende): Prozesse zählen, Halt, Weiterlaufen,
// Ende, verzögert gemeldeter Halt, Filter für Halte, Zuhörer benachrichtigen. Die IDE-Schicht
// (Atlas.IDE.Debug.Session) übersetzt den Notifier des Debuggers in die Ereignisse ProcessCreated,
// ProcessDestroyed und StateChanged und gibt über IAtlasDebugTarget Auskunft über den Debugger. Tests
// ersetzen ihn durch eine Fälschung.
//   - Gestartet: erster Prozess angelegt.
//   - Angehalten: StateChanged mit Stopped (Haltepunkt, Schritt, Pause), Exception (Sprach-Exception) bzw.
//     Fault (Exception des Betriebssystems). Gemeldet wird erst beim nächsten Tick nach der Benachrichtigung
//     des Debuggers (RequestTick); läuft der Prozess bis dahin weiter, hat er einen neuen Halt oder keinen
//     angehaltenen Thread, entfällt die Meldung.
//   - Fortgesetzt: Running nach einem Halt.
//   - Beendet: letzter Prozess abgebaut.
// Zustandswechsel zwischen BeginInternal und EndInternal (eigene Auswertungen) zählen nicht. Ein Halt, den
// der Filter erledigt, erreicht die Zuhörer nicht, auch nicht das Weiterlaufen danach. Jeder Zuhörer läuft
// einzeln über IAtlasDebugTarget.Run (in der IDE unter der Sicherung). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  /// <summary>Grund eines Halts.</summary>
  TAtlasDebugStop = (Paused, Exception, Fault);
  /// <summary>Zustand des Prozesses, wie ihn der Debugger meldet; Other für alle übrigen (beendet, ohne).
  /// </summary>
  TAtlasDebugProcessState = (Other, Running, Stopped, Exception, Fault);
  {$SCOPEDENUMS OFF}

  IAtlasDebugListener = interface
    ['{6E4F2A8C-1B7D-4C55-9E2A-3F0B8D61C7A4}']
    /// <summary>Erster Prozess der Sitzung angelegt.</summary>
    procedure DebugStarted;
    /// <summary>Prozess angehalten; AStop nennt den Grund.</summary>
    procedure DebugStopped(AStop: TAtlasDebugStop);
    /// <summary>Prozess läuft nach einem Halt weiter.</summary>
    procedure DebugResumed;
    /// <summary>Letzter Prozess abgebaut.</summary>
    procedure DebugEnded;
  end;

  /// <summary>Der Debugger, wie ihn die Phasen sehen; in der IDE über IOTADebuggerServices.</summary>
  IAtlasDebugTarget = interface
    ['{B4D17E2A-6C93-4F0B-8E51-2A7C9D03F6B8}']
    /// <summary>Anzahl der Prozesse der Sitzung.</summary>
    function ProcessCount: Integer;
    /// <summary>Zustand des aktuellen Prozesses; Other ohne Prozess.</summary>
    function CurrentState: TAtlasDebugProcessState;
    /// <summary>Ist der aktuelle Prozess angehalten und hat er einen aktuellen Thread?</summary>
    function HasStoppedThread: Boolean;
    /// <summary>TAtlasDebugPhases.Tick einmal aufrufen, sobald die Benachrichtigung des Debuggers vorbei ist.
    /// </summary>
    procedure RequestTick;
    /// <summary>AProc geschützt ausführen (Zuhörer, Filter); ein Fehler darf die übrigen nicht aufhalten.
    /// </summary>
    procedure Run(const AProc: TProc);
  end;

  /// <summary>Prüft einen Halt vor den Zuhörern; True = erledigt (etwa fortgesetzt), die Zuhörer erfahren nichts.
  /// </summary>
  TAtlasDebugStopFilter = reference to function(AStop: TAtlasDebugStop): Boolean;

  TAtlasDebugPhases = class
  private
    FTarget: IAtlasDebugTarget;
    FListeners: TList<IAtlasDebugListener>;
    FFilter: TAtlasDebugStopFilter;
    FProcesses: Integer;
    FStopped: Boolean;
    FInternal: Integer;
    FStopCount: Integer;
    FPendingStop: TAtlasDebugStop;
    FPendingCount: Integer;
    procedure Halted(AState: TAtlasDebugProcessState);
    function Filtered(AStop: TAtlasDebugStop): Boolean;
  public
    constructor Create(const ATarget: IAtlasDebugTarget);
    destructor Destroy; override;
    class function IsStop(AState: TAtlasDebugProcessState): Boolean; static;
    class function StopOf(AState: TAtlasDebugProcessState): TAtlasDebugStop; static;
    /// <summary>Stand des Debuggers übernehmen (Notifier gerade angemeldet).</summary>
    procedure Attach;
    /// <summary>Zuhörer vergessen, Zähler zurück (Notifier abgemeldet); Filter und StopCount bleiben.</summary>
    procedure Reset;
    procedure AddListener(const AListener: IAtlasDebugListener);
    procedure RemoveListener(const AListener: IAtlasDebugListener);
    function ListenerCount: Integer;
    /// <summary>Kopie der Zuhörer; ein Zuhörer darf sich beim Ereignis ab- oder einen anderen anmelden.</summary>
    function Listeners: TArray<IAtlasDebugListener>;
    /// <summary>AEvent für jeden noch angemeldeten Zuhörer, jeder einzeln über IAtlasDebugTarget.Run.</summary>
    procedure Notify(const AEvent: TProc<IAtlasDebugListener>);
    /// <summary>Filter für Halte (nil = keiner); es gibt nur einen.</summary>
    procedure SetStopFilter(const AFilter: TAtlasDebugStopFilter);
    { Ereignisse des Debuggers }
    procedure ProcessCreated;
    procedure ProcessDestroyed;
    procedure StateChanged(AState: TAtlasDebugProcessState);
    /// <summary>Nach RequestTick: einen noch gültigen Halt melden.</summary>
    procedure Tick;
    { Eigene Auswertungen }
    procedure BeginInternal;
    procedure EndInternal;
    { Zustand }
    /// <summary>Läuft eine Debug-Sitzung (mindestens ein Prozess)?</summary>
    function Active: Boolean;
    /// <summary>Angehalten nach dem zuletzt gezählten Halt?</summary>
    function Stopped: Boolean;
    /// <summary>Halt Nummer n der Sitzung (zählt jeden Halt); 0 vor dem ersten.</summary>
    function StopCount: Integer;
  end;

implementation

{ TAtlasDebugPhases }

constructor TAtlasDebugPhases.Create(const ATarget: IAtlasDebugTarget);
begin
  inherited Create;
  FTarget := ATarget;
  FListeners := TList<IAtlasDebugListener>.Create;
end;

destructor TAtlasDebugPhases.Destroy;
begin
  FListeners.Free;
  FFilter := nil;
  FTarget := nil;
  inherited Destroy;
end;

class function TAtlasDebugPhases.IsStop(AState: TAtlasDebugProcessState): Boolean;
begin
  Result := AState in [TAtlasDebugProcessState.Stopped, TAtlasDebugProcessState.Exception,
    TAtlasDebugProcessState.Fault];
end;

class function TAtlasDebugPhases.StopOf(AState: TAtlasDebugProcessState): TAtlasDebugStop;
begin
  case AState of
    TAtlasDebugProcessState.Exception:
      Result := TAtlasDebugStop.Exception;
    TAtlasDebugProcessState.Fault:
      Result := TAtlasDebugStop.Fault;
  else
    Result := TAtlasDebugStop.Paused;
  end;
end;

procedure TAtlasDebugPhases.Attach;
begin
  FProcesses := FTarget.ProcessCount;
  FStopped := IsStop(FTarget.CurrentState);
end;

procedure TAtlasDebugPhases.Reset;
begin
  FListeners.Clear;
  FProcesses := 0;
  FStopped := False;
  FInternal := 0;
end;

procedure TAtlasDebugPhases.AddListener(const AListener: IAtlasDebugListener);
begin
  if (AListener <> nil) and (FListeners.IndexOf(AListener) < 0) then
  begin
    FListeners.Add(AListener);
  end;
end;

procedure TAtlasDebugPhases.RemoveListener(const AListener: IAtlasDebugListener);
begin
  FListeners.Remove(AListener);
end;

function TAtlasDebugPhases.ListenerCount: Integer;
begin
  Result := FListeners.Count;
end;

function TAtlasDebugPhases.Listeners: TArray<IAtlasDebugListener>;
begin
  Result := FListeners.ToArray;
end;

procedure TAtlasDebugPhases.Notify(const AEvent: TProc<IAtlasDebugListener>);
var
  mListener: IAtlasDebugListener;
begin
  for mListener in Listeners do
  begin
    FTarget.Run(
      procedure
      begin
        if FListeners.IndexOf(mListener) >= 0 then
        begin
          AEvent(mListener);
        end;
      end);
  end;
end;

procedure TAtlasDebugPhases.SetStopFilter(const AFilter: TAtlasDebugStopFilter);
begin
  FFilter := AFilter;
end;

procedure TAtlasDebugPhases.ProcessCreated;
begin
  Inc(FProcesses);
  if FProcesses <> 1 then
  begin
    Exit;
  end;
  FStopped := False;
  FStopCount := 0;
  Notify(
    procedure(AListener: IAtlasDebugListener)
    begin
      AListener.DebugStarted;
    end);
end;

procedure TAtlasDebugPhases.ProcessDestroyed;
begin
  if FProcesses > 0 then
  begin
    Dec(FProcesses);
  end;
  if FProcesses > 0 then
  begin
    Exit;
  end;
  FStopped := False;
  Notify(
    procedure(AListener: IAtlasDebugListener)
    begin
      AListener.DebugEnded;
    end);
end;

procedure TAtlasDebugPhases.StateChanged(AState: TAtlasDebugProcessState);
begin
  if FInternal > 0 then
  begin
    Exit;
  end;
  if IsStop(AState) then
  begin
    Halted(AState);
  end
  else if (AState = TAtlasDebugProcessState.Running) and FStopped then
  begin
    FStopped := False;
    Notify(
      procedure(AListener: IAtlasDebugListener)
      begin
        AListener.DebugResumed;
      end);
  end;
end;

procedure TAtlasDebugPhases.Halted(AState: TAtlasDebugProcessState);
begin
  FStopped := True;
  Inc(FStopCount);
  // Erst nach der Benachrichtigung des Debuggers melden: Dort darf weder ausgewertet noch fortgesetzt werden.
  FPendingStop := StopOf(AState);
  FPendingCount := FStopCount;
  FTarget.RequestTick;
end;

function TAtlasDebugPhases.Filtered(AStop: TAtlasDebugStop): Boolean;
var
  mFilter: TAtlasDebugStopFilter;
  mHandled: Boolean;
begin
  mFilter := FFilter;
  if not Assigned(mFilter) then
  begin
    Exit(False);
  end;
  // Vorher als weitergelaufen markieren: Setzt der Filter fort, meldet StateChanged kein DebugResumed.
  FStopped := False;
  mHandled := False;
  FTarget.Run(
    procedure
    begin
      mHandled := mFilter(AStop);
    end);
  if not mHandled then
  begin
    FStopped := True;
  end;
  Result := mHandled;
end;

procedure TAtlasDebugPhases.Tick;
var
  mStop: TAtlasDebugStop;
begin
  // Weitergelaufen oder schon ein neuer Halt (der meldet sich selbst): dieser entfällt.
  if not FStopped or (FPendingCount <> FStopCount) or not FTarget.HasStoppedThread then
  begin
    Exit;
  end;
  mStop := FPendingStop;
  if Filtered(mStop) then
  begin
    Exit;
  end;
  Notify(
    procedure(AListener: IAtlasDebugListener)
    begin
      AListener.DebugStopped(mStop);
    end);
end;

procedure TAtlasDebugPhases.BeginInternal;
begin
  Inc(FInternal);
end;

procedure TAtlasDebugPhases.EndInternal;
begin
  if FInternal > 0 then
  begin
    Dec(FInternal);
  end;
end;

function TAtlasDebugPhases.Active: Boolean;
begin
  Result := FProcesses > 0;
end;

function TAtlasDebugPhases.Stopped: Boolean;
begin
  Result := FStopped;
end;

function TAtlasDebugPhases.StopCount: Integer;
begin
  Result := FStopCount;
end;

end.
