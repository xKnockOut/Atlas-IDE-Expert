unit Atlas.IDE.Debug.Session;

// Debug-Sitzung der IDE für alle Debugger-Funktionen von Atlas (#517 und
// folgende): ein IOTADebuggerNotifier für alle, die Ereignisse gehen an
// angemeldete Zuhörer.
//   - Gestartet: erster Prozess angelegt (ProcessCreated). Projekt,
//     Konfiguration und Plattform des Starts merkt BeforeProgramLaunch (#840),
//     dazu die Projektoptionen LaunchOptionNames dieser Konfiguration: Wechselt
//     der Anwender danach die Konfiguration, gilt für den laufenden Prozess
//     weiter der Stand beim Start.
//   - Angehalten: ProcessStateChanged mit psStopped (Haltepunkt, Schritt,
//     Pause), psException (Sprach-Exception) bzw. psFault/psResFault
//     (Exception des Betriebssystems, etwa Zugriffsverletzung).
//   - Fortgesetzt: psRunning nach einem Halt.
//   - Beendet: letzter Prozess abgebaut (ProcessDestroyed).
// Die Zuhörer laufen nie im Notifier selbst: Der Debugger ruft aus seiner
// Benachrichtigung, dort darf weder ausgewertet noch fortgesetzt werden.
// Gemeldet wird über TAtlasMainThread.ForceQueue; ein Halt, der beim Ausführen
// schon vorbei ist, wird nicht mehr gemeldet. Auswertungen von Atlas
// (BeginInternal/EndInternal) ändern den Zustand kurz; diese Wechsel zählen
// nicht. Jeder Zuhörer läuft unter der Sicherung (Feature Debugger, #493).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Debug.CallStack;

type
  {$SCOPEDENUMS ON}
  TAtlasDebugStop = (Paused, Exception, Fault);
  /// <summary>Ergebnis beim Lesen des Aufrufstapels: Ready, Wait (der Debugger liefert ihn später, LLDB), None.
  /// </summary>
  TAtlasDebugStackRead = (Ready, Wait, None);
  {$SCOPEDENUMS OFF}

  IAtlasIdeDebugListener = interface
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

  /// <summary>Zuhörer mit leeren Methoden zum Überschreiben.</summary>
  TAtlasIdeDebugListener = class(TInterfacedObject, IAtlasIdeDebugListener)
  public
    procedure DebugStarted; virtual;
    procedure DebugStopped(AStop: TAtlasDebugStop); virtual;
    procedure DebugResumed; virtual;
    procedure DebugEnded; virtual;
  end;

  TAtlasIdeDebugSession = class
  public const
    /// <summary>Beim Start festgehaltene Projektoptionen (#840): Debug-Informationen, lokale Symbole,
    /// Optimierung, Debug-DCUs.</summary>
    LaunchOptionNames: array[0..3] of string = ('DCC_DebugInformation', 'DCC_LocalDebugSymbols', 'DCC_Optimize',
      'DCC_DebugDCUs');
  private type
    TNotifier = class(TNotifierObject, IOTADebuggerNotifier, IOTADebuggerNotifier90)
    public
      { IOTADebuggerNotifier }
      procedure ProcessCreated(const Process: IOTAProcess);
      procedure ProcessDestroyed(const Process: IOTAProcess);
      procedure BreakpointAdded(const Breakpoint: IOTABreakpoint);
      procedure BreakpointDeleted(const Breakpoint: IOTABreakpoint);
      { IOTADebuggerNotifier90 }
      procedure BreakpointChanged(const Breakpoint: IOTABreakpoint);
      procedure CurrentProcessChanged(const Process: IOTAProcess);
      procedure ProcessStateChanged(const Process: IOTAProcess);
      function BeforeProgramLaunch(const Project: IOTAProject): Boolean;
      procedure ProcessMemoryChanged;
    end;
  private class var
    FNotifierIndex: Integer;
    FListeners: TList<IAtlasIdeDebugListener>;
    FProcesses: Integer;
    FStopped: Boolean;
    FInternal: Integer;
    FStopCount: Integer;
    FProject: string;
    FConfiguration: string;
    FPlatform: string;
    FLaunchValues: array[0..3] of string;
    class procedure Dispatch(const AEvent: TProc<IAtlasIdeDebugListener>); static;
    class procedure StateChanged(const AProcess: IOTAProcess); static;
    class procedure Ended; static;
  public
    /// <summary>Notifier anmelden; mehrfacher Aufruf schadet nicht.</summary>
    class procedure Start; static;
    /// <summary>Notifier abmelden, Zuhörer vergessen; RemoveListener ruft es beim letzten Zuhörer.</summary>
    class procedure Stop; static;
    class function Started: Boolean; static;
    class procedure AddListener(const AListener: IAtlasIdeDebugListener); static;
    class procedure RemoveListener(const AListener: IAtlasIdeDebugListener); static;
    /// <summary>Läuft eine Debug-Sitzung (mindestens ein Prozess)?</summary>
    class function Active: Boolean; static;
    /// <summary>Aktueller Prozess der IDE oder nil.</summary>
    class function Process: IOTAProcess; static;
    /// <summary>Aktueller Thread, wenn der Prozess angehalten ist (psStopped, psFault, psResFault,
    /// psException); sonst nil.</summary>
    class function StoppedThread: IOTAThread; static;
    /// <summary>Halt Nummer n der Sitzung (zählt jeden gemeldeten Halt); 0 vor dem ersten.</summary>
    class function StopCount: Integer; static;
    /// <summary>Projekt (.dproj), Konfiguration und Plattform beim Start ('' = unbekannt, etwa angehängt).
    /// </summary>
    class function LaunchProject: string; static;
    class function LaunchConfiguration: string; static;
    class function LaunchPlatform: string; static;
    /// <summary>Wert der Projektoption AName (aus LaunchOptionNames) beim Start; '' = unbekannt oder Vorgabe.
    /// </summary>
    class function LaunchValue(const AName: string): string; static;
    /// <summary>Um eigene Auswertungen: Zustandswechsel dazwischen werden nicht gemeldet.</summary>
    class procedure BeginInternal; static;
    class procedure EndInternal; static;
    /// <summary>Bis zu AMax Rahmen des Aufrufstapels von AThread (oberster zuerst).</summary>
    class function ReadStack(const AThread: IOTAThread; AMax: Integer;
      out AFrames: TAtlasDebugFrames): TAtlasDebugStackRead; static;
    /// <summary>Name des Threads ('' ohne).</summary>
    class function ThreadName(const AThread: IOTAThread): string; static;
    /// <summary>Prozess fortsetzen (F9); False ohne angehaltenen Prozess.</summary>
    class function Resume: Boolean; static;
    /// <summary>Prozess mit ARunMode fortsetzen (etwa ormRunUntilReturn, #578); False ohne angehaltenen Prozess.
    /// </summary>
    class function RunMode(ARunMode: TOTARunMode): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Projects.Context;

function Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
    Result := nil;
end;

function IsStoppedState(AState: TOTAProcessState): Boolean;
begin
  Result := AState in [psStopped, psFault, psResFault, psException];
end;

{ TAtlasIdeDebugListener }

procedure TAtlasIdeDebugListener.DebugStarted;
begin
end;

procedure TAtlasIdeDebugListener.DebugStopped(AStop: TAtlasDebugStop);
begin
end;

procedure TAtlasIdeDebugListener.DebugResumed;
begin
end;

procedure TAtlasIdeDebugListener.DebugEnded;
begin
end;

{ TAtlasIdeDebugSession.TNotifier }

procedure TAtlasIdeDebugSession.TNotifier.ProcessCreated(const Process: IOTAProcess);
begin
  Inc(TAtlasIdeDebugSession.FProcesses);
  if TAtlasIdeDebugSession.FProcesses = 1 then
  begin
    TAtlasIdeDebugSession.FStopped := False;
    TAtlasIdeDebugSession.FStopCount := 0;
    TAtlasIdeDebugSession.Dispatch(
      procedure(AListener: IAtlasIdeDebugListener)
      begin
        AListener.DebugStarted;
      end);
  end;
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessDestroyed(const Process: IOTAProcess);
begin
  if TAtlasIdeDebugSession.FProcesses > 0 then
    Dec(TAtlasIdeDebugSession.FProcesses);
  if TAtlasIdeDebugSession.FProcesses = 0 then
    TAtlasIdeDebugSession.Ended;
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointAdded(const Breakpoint: IOTABreakpoint);
begin
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointDeleted(const Breakpoint: IOTABreakpoint);
begin
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointChanged(const Breakpoint: IOTABreakpoint);
begin
end;

procedure TAtlasIdeDebugSession.TNotifier.CurrentProcessChanged(const Process: IOTAProcess);
begin
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessStateChanged(const Process: IOTAProcess);
begin
  TAtlasIdeDebugSession.StateChanged(Process);
end;

function TAtlasIdeDebugSession.TNotifier.BeforeProgramLaunch(const Project: IOTAProject): Boolean;
var
  Options: IOTAProjectOptionsConfigurations;
  Index: Integer;
begin
  // Nie den Start verhindern.
  Result := True;
  try
    TAtlasIdeDebugSession.FProject := '';
    TAtlasIdeDebugSession.FConfiguration := '';
    TAtlasIdeDebugSession.FPlatform := '';
    for Index := Low(TAtlasIdeDebugSession.FLaunchValues) to High(TAtlasIdeDebugSession.FLaunchValues) do
      TAtlasIdeDebugSession.FLaunchValues[Index] := '';
    if Project = nil then
      Exit;
    TAtlasIdeDebugSession.FProject := Project.FileName;
    TAtlasIdeDebugSession.FPlatform := Project.CurrentPlatform;
    if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Options) and
      (Options.ActiveConfiguration <> nil) then
      TAtlasIdeDebugSession.FConfiguration := Options.ActiveConfiguration.Name;
    for Index := Low(TAtlasIdeDebugSession.LaunchOptionNames) to High(TAtlasIdeDebugSession.LaunchOptionNames) do
      TAtlasIdeDebugSession.FLaunchValues[Index] := Trim(TAtlasIdeProjectContext.ConfigurationValue(Project,
        TAtlasIdeDebugSession.FConfiguration, TAtlasIdeDebugSession.FPlatform,
        TAtlasIdeDebugSession.LaunchOptionNames[Index]));
  except
    // Nur Merkwerte; der Start geht in jedem Fall weiter.
  end;
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessMemoryChanged;
begin
end;

{ TAtlasIdeDebugSession }

class procedure TAtlasIdeDebugSession.Start;
var
  Services: IOTADebuggerServices;
  Notifier: IOTADebuggerNotifier;
begin
  if FListeners = nil then
    FListeners := TList<IAtlasIdeDebugListener>.Create;
  if FNotifierIndex > 0 then
    Exit;
  Services := Debugger;
  if Services = nil then
    Exit;
  // Index + 1, damit 0 „nicht angemeldet“ heißt.
  Notifier := TNotifier.Create;
  FNotifierIndex := Services.AddNotifier(Notifier) + 1;
  FProcesses := Services.ProcessCount;
  FStopped := (Services.CurrentProcess <> nil) and IsStoppedState(Services.CurrentProcess.ProcessState);
end;

class procedure TAtlasIdeDebugSession.Stop;
var
  Services: IOTADebuggerServices;
begin
  if FNotifierIndex > 0 then
  begin
    Services := Debugger;
    if Services <> nil then
      Services.RemoveNotifier(FNotifierIndex - 1);
    FNotifierIndex := 0;
  end;
  FreeAndNil(FListeners);
  FProcesses := 0;
  FStopped := False;
  FInternal := 0;
end;

class function TAtlasIdeDebugSession.Started: Boolean;
begin
  Result := FNotifierIndex > 0;
end;

class procedure TAtlasIdeDebugSession.AddListener(const AListener: IAtlasIdeDebugListener);
begin
  if FListeners = nil then
    FListeners := TList<IAtlasIdeDebugListener>.Create;
  if (AListener <> nil) and (FListeners.IndexOf(AListener) < 0) then
    FListeners.Add(AListener);
end;

class procedure TAtlasIdeDebugSession.RemoveListener(const AListener: IAtlasIdeDebugListener);
begin
  if FListeners = nil then
    Exit;
  FListeners.Remove(AListener);
  // Ohne Zuhörer braucht Atlas keinen Notifier beim Debugger: Der letzte meldet ihn ab.
  if FListeners.Count = 0 then
    Stop;
end;

class procedure TAtlasIdeDebugSession.Dispatch(const AEvent: TProc<IAtlasIdeDebugListener>);
var
  Listeners: TArray<IAtlasIdeDebugListener>;
  Listener: IAtlasIdeDebugListener;
begin
  if FListeners = nil then
    Exit;
  // Kopie: Ein Zuhörer darf sich beim Ereignis ab- oder einen anderen anmelden.
  Listeners := FListeners.ToArray;
  for Listener in Listeners do
    TAtlasGuard.Run(TAtlasFeature.Debugger,
      procedure
      begin
        if (FListeners <> nil) and (FListeners.IndexOf(Listener) >= 0) then
          AEvent(Listener);
      end);
end;

class procedure TAtlasIdeDebugSession.StateChanged(const AProcess: IOTAProcess);
var
  State: TOTAProcessState;
  Stop: TAtlasDebugStop;
begin
  if (AProcess = nil) or (FInternal > 0) then
    Exit;
  State := AProcess.ProcessState;
  if IsStoppedState(State) then
  begin
    case State of
      psException:
        Stop := TAtlasDebugStop.Exception;
      psFault, psResFault:
        Stop := TAtlasDebugStop.Fault;
    else
      Stop := TAtlasDebugStop.Paused;
    end;
    FStopped := True;
    Inc(FStopCount);
    // Erst nach der Benachrichtigung des Debuggers melden; ist der Halt bis dahin vorbei, entfällt er.
    TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
      procedure
      var
        Thread: IOTAThread;
      begin
        Thread := StoppedThread;
        if Thread = nil then
          Exit;
        Dispatch(
          procedure(AListener: IAtlasIdeDebugListener)
          begin
            AListener.DebugStopped(Stop);
          end);
      end);
  end
  else if (State = psRunning) and FStopped then
  begin
    FStopped := False;
    Dispatch(
      procedure(AListener: IAtlasIdeDebugListener)
      begin
        AListener.DebugResumed;
      end);
  end;
end;

class procedure TAtlasIdeDebugSession.Ended;
begin
  FStopped := False;
  Dispatch(
    procedure(AListener: IAtlasIdeDebugListener)
    begin
      AListener.DebugEnded;
    end);
end;

class function TAtlasIdeDebugSession.Active: Boolean;
begin
  Result := FProcesses > 0;
end;

class function TAtlasIdeDebugSession.Process: IOTAProcess;
var
  Services: IOTADebuggerServices;
begin
  Result := nil;
  Services := Debugger;
  if Services <> nil then
    Result := Services.CurrentProcess;
end;

class function TAtlasIdeDebugSession.StoppedThread: IOTAThread;
var
  Current: IOTAProcess;
begin
  Result := nil;
  Current := Process;
  if (Current <> nil) and IsStoppedState(Current.ProcessState) then
    Result := Current.CurrentThread;
end;

class function TAtlasIdeDebugSession.StopCount: Integer;
begin
  Result := FStopCount;
end;

class function TAtlasIdeDebugSession.LaunchProject: string;
begin
  Result := FProject;
end;

class function TAtlasIdeDebugSession.LaunchConfiguration: string;
begin
  Result := FConfiguration;
end;

class function TAtlasIdeDebugSession.LaunchPlatform: string;
begin
  Result := FPlatform;
end;

class function TAtlasIdeDebugSession.LaunchValue(const AName: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := Low(LaunchOptionNames) to High(LaunchOptionNames) do
    if SameText(LaunchOptionNames[Index], AName) then
      Exit(FLaunchValues[Index]);
end;

class procedure TAtlasIdeDebugSession.BeginInternal;
begin
  Inc(FInternal);
end;

class procedure TAtlasIdeDebugSession.EndInternal;
begin
  if FInternal > 0 then
    Dec(FInternal);
end;

class function TAtlasIdeDebugSession.ReadStack(const AThread: IOTAThread; AMax: Integer;
  out AFrames: TAtlasDebugFrames): TAtlasDebugStackRead;
var
  Access: TOTACallStackState;
  Index, Count, Line: Integer;
  FileName: string;
begin
  AFrames := nil;
  Result := TAtlasDebugStackRead.None;
  if AThread = nil then
    Exit;
  Access := AThread.StartCallStackAccess;
  try
    case Access of
      csWait:
        Exit(TAtlasDebugStackRead.Wait);
      csInaccessible:
        Exit;
    end;
    Count := AThread.GetCallCount;
    if Count > AMax then
      Count := AMax;
    for Index := 0 to Count - 1 do
    begin
      FileName := '';
      Line := 0;
      AThread.GetCallPos(Index, FileName, Line);
      AFrames := AFrames + [TAtlasDebugFrame.Create(AThread.GetCallHeader(Index), FileName, Line)];
    end;
    Result := TAtlasDebugStackRead.Ready;
  finally
    AThread.EndCallStackAccess;
  end;
end;

class function TAtlasIdeDebugSession.ThreadName(const AThread: IOTAThread): string;
begin
  Result := '';
  if AThread = nil then
    Exit;
  try
    Result := AThread.GetThreadName;
  except
    // Ältere Debugger kennen keine Thread-Namen.
    Result := '';
  end;
end;

class function TAtlasIdeDebugSession.Resume: Boolean;
begin
  Result := RunMode(ormRun);
end;

class function TAtlasIdeDebugSession.RunMode(ARunMode: TOTARunMode): Boolean;
var
  Current: IOTAProcess;
begin
  Current := Process;
  Result := (Current <> nil) and IsStoppedState(Current.ProcessState);
  if Result then
    Current.Run(ARunMode);
end;

end.
