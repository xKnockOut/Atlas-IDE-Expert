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
//   - Haltepunkte geändert (#863): Zuhörer mit IAtlasIdeDebugBreakpointListener
//     erfahren im Notifier, dass Haltepunkte angelegt, gelöscht oder geändert
//     wurden, und lesen später neu.
//   - Vor dem Start: Zuhörer, die IAtlasIdeDebugLaunchCheck können, fragt
//     BeforeProgramLaunch der Reihe nach (#577: Haltepunkte prüfen); lehnt
//     einer ab, startet die IDE nicht. Nur hier läuft ein Zuhörer im Notifier
//     selbst: Es gibt noch keinen Prozess, und nur hier lässt sich der Start
//     anhalten. Fehler darin lassen den Start zu.
// Die Phasen selbst (Prozesse zählen, Halt, Weiterlaufen, Ende, Filter, Zuhörer)
// stehen ohne Open Tools API in TAtlasDebugPhases (Atlas.Core.Debug.Phases) und
// sind dort getestet. Diese Unit verbindet sie mit der IDE: Der Notifier übersetzt
// IOTAProcess.ProcessState in TAtlasDebugProcessState, das Ziel aus UseAdapters
// (Atlas.IDE.Debug.Adapters.SessionTarget) beantwortet die Fragen der Phasen
// über IOTADebuggerServices, ein Zeitgeber liefert den Tick
// nach der Benachrichtigung des Debuggers, und jeder Zuhörer läuft unter der
// Sicherung (Feature Debugger, #493).
// Ein Halt, den der Filter (SetStopFilter) erledigt, etwa ein Haltepunkt der Herkunft eingereihter Methoden (#859),
// der den Stapel merkt und gleich fortsetzt, erreicht die Zuhörer nicht, auch nicht das Weiterlaufen danach.
// Laufzeit vor einem Halt (#579): Die Phasen zählen mit einer Uhr in Mikrosekunden (TStopwatch), wie lange der
// Prozess vor dem gemeldeten Halt lief (RunTimeBeforeStop).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Contract,
  Atlas.Core.Debug.Phases;

type
  /// <summary>Grund eines Halts (aus Atlas.Core.Debug.Contract).</summary>
  TAtlasDebugStop = Atlas.Core.Debug.Contract.TAtlasDebugStop;
  /// <summary>Filter für Halte (aus Atlas.Core.Debug.Phases).</summary>
  TAtlasIdeDebugStopFilter = TAtlasDebugStopFilter;

  {$SCOPEDENUMS ON}
  /// <summary>Ergebnis beim Lesen des Aufrufstapels: Ready, Wait (der Debugger liefert ihn später, LLDB), None.
  /// </summary>
  TAtlasDebugStackRead = (Ready, Wait, None);
  {$SCOPEDENUMS OFF}

  /// <summary>Zusatz eines Zuhörers: Vor dem Start einer Debug-Sitzung gefragt (im Notifier, kein Prozess).
  /// </summary>
  IAtlasIdeDebugLaunchCheck = interface
    ['{3B7E91D2-5C4A-4F08-A6E3-8D2F1B07C95E}']
    /// <summary>False verhindert den Start von AProject.</summary>
    function AllowLaunch(const AProject: IOTAProject): Boolean;
  end;

  /// <summary>Zusatz eines Zuhörers: Quelltext-Haltepunkte angelegt, gelöscht oder geändert (#863). Läuft im
  /// Notifier; der Zuhörer merkt sich nur, dass er neu lesen muss.</summary>
  IAtlasIdeDebugBreakpointListener = interface
    ['{9C3D5E71-2A4B-4F86-B1E0-7D58C2A94F13}']
    procedure BreakpointsChanged;
  end;

  /// <summary>Takt eines Debugger-Helfers aus Klassenmethoden: ein TTimer, anfangs aus, der ATick über
  /// TAtlasGuard ruft (ein TTimer braucht eine Methode eines Objekts). Der Besitzer schaltet Timer.Enabled und gibt
  /// den Takt in Release frei.</summary>
  TAtlasIdeDebugPace = class
  private
    FTimer: TTimer;
    FTick: TProc;
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(AIntervalMs: Integer; const ATick: TProc);
    destructor Destroy; override;
    property Timer: TTimer read FTimer;
  end;

  TAtlasIdeDebugSession = class
  public const
    /// <summary>Beim Start festgehaltene Projektoptionen (#840): Debug-Informationen, lokale Symbole,
    /// Optimierung, Debug-DCUs.</summary>
    cLaunchOptionNames: array[0..3] of string = ('DCC_DebugInformation', 'DCC_LocalDebugSymbols', 'DCC_Optimize',
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
    FTarget: IAtlasDebugTarget;
    FNewEvaluator: TAtlasDebugEvaluatorFactory;
    FPhases: TAtlasDebugPhases;
    FProject: string;
    FConfiguration: string;
    FPlatform: string;
    FLaunchValues: array[0..3] of string;
    // Meldet einen Halt nach dem Notifier. Ein Zeitgeber statt ForceQueue: Er feuert auch in der Nachrichtenschleife
    // des Exception-Dialogs der IDE, die Warteschlange erst nach dessen Schließen (#783: Dialog erkennen).
    FStopTimer: TTimer;
    FTicker: TObject;
    class procedure StopTick; static;
    class function Phases: TAtlasDebugPhases; static;
    /// <summary>Zuhörer mit IAtlasIdeDebugLaunchCheck fragen; False, wenn einer ablehnt.</summary>
    class function AllowLaunch(const AProject: IOTAProject): Boolean; static;
  public
    /// <summary>Adapter der Sitzung; setzt die Komposition des Moduls bei der Anmeldung, vor jedem Teil, und beim
    /// Abmelden mit nil: ATarget ist der Debugger der IDE für die Phasen (Atlas.IDE.Debug.Adapters.SessionTarget),
    /// ANewEvaluator die Fabrik der Auswertungen im angehaltenen Thread (Atlas.IDE.Debug.Adapters.ThreadEvaluator).
    /// </summary>
    class procedure UseAdapters(ATarget: IAtlasDebugTarget; const ANewEvaluator: TAtlasDebugEvaluatorFactory);
      static;
    /// <summary>Neue Auswertung im angehaltenen Thread über die Fabrik.</summary>
    class function NewEvaluator: IAtlasDebugEvaluator; static;
    /// <summary>Tick der Phasen nach der Benachrichtigung des Debuggers anfordern (Zeitgeber, nicht ForceQueue).
    /// </summary>
    class procedure RequestTick; static;
    /// <summary>Zustand der Open Tools API für die Phasen.</summary>
    class function PhaseState(AState: TOTAProcessState): TAtlasDebugProcessState; static;
    /// <summary>Notifier anmelden; mehrfacher Aufruf schadet nicht.</summary>
    class procedure Start; static;
    /// <summary>Notifier abmelden, Zuhörer vergessen; RemoveListener ruft es beim letzten Zuhörer.</summary>
    class procedure Stop; static;
    class function Started: Boolean; static;
    class procedure AddListener(const AListener: IAtlasDebugListener); static;
    class procedure RemoveListener(const AListener: IAtlasDebugListener); static;
    /// <summary>Filter für Halte ohne Namen setzen (nil = keiner).</summary>
    class procedure SetStopFilter(const AFilter: TAtlasIdeDebugStopFilter); static;
    /// <summary>Filter für Halte unter AName (neben dem ohne Namen); nil entfernt ihn.</summary>
    class procedure SetNamedStopFilter(const AName: string; const AFilter: TAtlasIdeDebugStopFilter); static;
    /// <summary>Läuft eine Debug-Sitzung (mindestens ein Prozess)?</summary>
    class function Active: Boolean; static;
    /// <summary>Aktueller Prozess der IDE oder nil.</summary>
    class function Process: IOTAProcess; static;
    /// <summary>Aktueller Thread, wenn der Prozess angehalten ist (psStopped, psFault, psResFault,
    /// psException); sonst nil.</summary>
    class function StoppedThread: IOTAThread; static;
    /// <summary>Halt Nummer n der Sitzung (zählt jeden gemeldeten Halt); 0 vor dem ersten.</summary>
    class function StopCount: Integer; static;
    /// <summary>Laufzeit in Mikrosekunden vor dem zuletzt gemeldeten Halt (#579), ohne angehaltene Zeit; 0 ohne.
    /// </summary>
    class function RunTimeBeforeStop: Int64; static;
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
    /// <summary>Anzahl der Rahmen des Aufrufstapels von AThread, ohne sie zu lesen (Schrittfilter #850: Ist der
    /// Schritt in eine neue Routine gegangen?).</summary>
    class function StackDepth(const AThread: IOTAThread; out ADepth: Integer): TAtlasDebugStackRead; static;
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
  System.Math,
  System.Diagnostics,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Projects.Context,
  Atlas.ToolsApi.Debugger.Services;

function IsStoppedState(AState: TOTAProcessState): Boolean;
begin
  Result := AState in [psStopped, psFault, psResFault, psException];
end;

class function TAtlasIdeDebugSession.PhaseState(AState: TOTAProcessState): TAtlasDebugProcessState;
begin
  case AState of
    psRunning:
      Result := TAtlasDebugProcessState.Running;
    psStopped:
      Result := TAtlasDebugProcessState.Stopped;
    psException:
      Result := TAtlasDebugProcessState.Exception;
    psFault, psResFault:
      Result := TAtlasDebugProcessState.Fault;
  else
    Result := TAtlasDebugProcessState.Other;
  end;
end;

type
  TStopTicker = class
  public
    procedure Tick(Sender: TObject);
  end;

/// <summary>Monotone Uhr in Mikrosekunden für die Laufzeit (#579); ohne Überlauf bei langer Laufzeit des Rechners.
/// </summary>
function MicrosecondsNow: Int64;
const
  cMicrosPerSecond = 1000000;
var
  mStamp, mFrequency: Int64;
begin
  mStamp := TStopwatch.GetTimeStamp;
  mFrequency := TStopwatch.Frequency;
  Result := 0;
  if mFrequency > 0 then
  begin
    Result := (mStamp div mFrequency) * cMicrosPerSecond + ((mStamp mod mFrequency) * cMicrosPerSecond) div mFrequency;
  end;
end;

{ TAtlasIdeDebugPace }

constructor TAtlasIdeDebugPace.Create(AIntervalMs: Integer; const ATick: TProc);
begin
  inherited Create;
  FTick := ATick;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := AIntervalMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasIdeDebugPace.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDebugPace.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, FTick);
end;

{ TStopTicker }

procedure TStopTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugSession.StopTick);
end;

{ TAtlasIdeDebugSession.TNotifier }

/// <summary>Zuhörer mit IAtlasIdeDebugBreakpointListener benachrichtigen (#863).</summary>
procedure NotifyBreakpointsChanged;
begin
  TAtlasIdeDebugSession.Phases.Notify(
    procedure(AListener: IAtlasDebugListener)
    var
      mBreakpoints: IAtlasIdeDebugBreakpointListener;
    begin
      if Supports(AListener, IAtlasIdeDebugBreakpointListener, mBreakpoints) then
      begin
        mBreakpoints.BreakpointsChanged;
      end;
    end);
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessCreated(const Process: IOTAProcess);
begin
  TAtlasIdeDebugSession.Phases.ProcessCreated;
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessDestroyed(const Process: IOTAProcess);
begin
  TAtlasIdeDebugSession.Phases.ProcessDestroyed;
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointAdded(const Breakpoint: IOTABreakpoint);
begin
  NotifyBreakpointsChanged;
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointDeleted(const Breakpoint: IOTABreakpoint);
begin
  NotifyBreakpointsChanged;
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointChanged(const Breakpoint: IOTABreakpoint);
begin
  NotifyBreakpointsChanged;
end;

procedure TAtlasIdeDebugSession.TNotifier.CurrentProcessChanged(const Process: IOTAProcess);
begin
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessStateChanged(const Process: IOTAProcess);
begin
  if Process <> nil then
  begin
    TAtlasIdeDebugSession.Phases.StateChanged(TAtlasIdeDebugSession.PhaseState(Process.ProcessState));
  end;
end;

function TAtlasIdeDebugSession.TNotifier.BeforeProgramLaunch(const Project: IOTAProject): Boolean;
var
  mOptions: IOTAProjectOptionsConfigurations;
  mIndex: Integer;
begin
  // Merkwerte verhindern den Start nie; ablehnen kann nur eine Prüfung (AllowLaunch).
  Result := True;
  try
    TAtlasIdeDebugSession.FProject := '';
    TAtlasIdeDebugSession.FConfiguration := '';
    TAtlasIdeDebugSession.FPlatform := '';
    for mIndex := Low(TAtlasIdeDebugSession.FLaunchValues) to High(TAtlasIdeDebugSession.FLaunchValues) do
    begin
      TAtlasIdeDebugSession.FLaunchValues[mIndex] := '';
    end;
    if Project = nil then
    begin
      Exit;
    end;
    TAtlasIdeDebugSession.FProject := Project.FileName;
    TAtlasIdeDebugSession.FPlatform := Project.CurrentPlatform;
    if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, mOptions) and
      (mOptions.ActiveConfiguration <> nil) then
    begin
      TAtlasIdeDebugSession.FConfiguration := mOptions.ActiveConfiguration.Name;
    end;
    for mIndex := Low(TAtlasIdeDebugSession.cLaunchOptionNames) to High(TAtlasIdeDebugSession.cLaunchOptionNames) do
    begin
      TAtlasIdeDebugSession.FLaunchValues[mIndex] := Trim(TAtlasIdeProjectContext.ConfigurationValue(Project,
        TAtlasIdeDebugSession.FConfiguration, TAtlasIdeDebugSession.FPlatform,
        TAtlasIdeDebugSession.cLaunchOptionNames[mIndex]));
    end;
  except
    // Nur Merkwerte; der Start geht in jedem Fall weiter, der Grund steht im Protokoll.
    on E: Exception do
      TAtlasGuard.Log('Debugsitzung: Startwerte fehlen: ' + TAtlasGuard.ErrorText(E)); // german-ok Protokoll
  end;
  if Project <> nil then
  begin
    Result := TAtlasIdeDebugSession.AllowLaunch(Project);
  end;
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessMemoryChanged;
begin
end;

{ TAtlasIdeDebugSession }

class procedure TAtlasIdeDebugSession.UseAdapters(ATarget: IAtlasDebugTarget;
  const ANewEvaluator: TAtlasDebugEvaluatorFactory);
begin
  // Die Phasen behalten ihr Ziel bis zum Entladen der Unit.
  FTarget := ATarget;
  FNewEvaluator := ANewEvaluator;
end;

class function TAtlasIdeDebugSession.NewEvaluator: IAtlasDebugEvaluator;
begin
  Result := FNewEvaluator();
end;

class function TAtlasIdeDebugSession.Phases: TAtlasDebugPhases;
begin
  // Bleibt bis zum Entladen der Unit: Stop darf aus einem Zuhörer kommen, während Phases benachrichtigt.
  if FPhases = nil then
  begin
    Assert(FTarget <> nil);
    FPhases := TAtlasDebugPhases.Create(FTarget);
    FPhases.Clock := MicrosecondsNow;
  end;
  Result := FPhases;
end;

class procedure TAtlasIdeDebugSession.RequestTick;
begin
  if FStopTimer = nil then
  begin
    FTicker := TStopTicker.Create;
    FStopTimer := TTimer.Create(nil);
    FStopTimer.Enabled := False;
    FStopTimer.Interval := 1;
    FStopTimer.OnTimer := TStopTicker(FTicker).Tick;
  end;
  FStopTimer.Enabled := True;
end;

class function TAtlasIdeDebugSession.AllowLaunch(const AProject: IOTAProject): Boolean;
var
  mListener: IAtlasDebugListener;
  mCheck: IAtlasIdeDebugLaunchCheck;
begin
  Result := True;
  for mListener in Phases.Listeners do
  begin
    if not Supports(mListener, IAtlasIdeDebugLaunchCheck, mCheck) then
    begin
      Continue;
    end;
    try
      if not mCheck.AllowLaunch(AProject) then
      begin
        Exit(False);
      end;
    except
      // Ein Fehler in der Prüfung darf den Start nicht verhindern.
      on E: Exception do
        TAtlasGuard.Log(Format('Launch check failed: %s: %s', [E.ClassName, TAtlasGuard.MessageText(E.Message)]));
    end;
  end;
end;

class procedure TAtlasIdeDebugSession.Start;
var
  mServices: IOTADebuggerServices;
  mNotifier: IOTADebuggerNotifier;
begin
  if FNotifierIndex > 0 then
  begin
    Exit;
  end;
  mServices := TAtlasIdeDebugger.Services;
  if mServices = nil then
  begin
    Exit;
  end;
  // Index + 1, damit 0 „nicht angemeldet“ heißt.
  mNotifier := TNotifier.Create;
  FNotifierIndex := mServices.AddNotifier(mNotifier) + 1;
  Phases.Attach;
end;

class procedure TAtlasIdeDebugSession.Stop;
var
  mServices: IOTADebuggerServices;
begin
  if FNotifierIndex > 0 then
  begin
    mServices := TAtlasIdeDebugger.Services;
    if mServices <> nil then
    begin
      mServices.RemoveNotifier(FNotifierIndex - 1);
    end;
    FNotifierIndex := 0;
  end;
  FreeAndNil(FStopTimer);
  FreeAndNil(FTicker);
  if FPhases <> nil then
  begin
    FPhases.Reset;
  end;
end;

class function TAtlasIdeDebugSession.Started: Boolean;
begin
  Result := FNotifierIndex > 0;
end;

class procedure TAtlasIdeDebugSession.AddListener(const AListener: IAtlasDebugListener);
begin
  Phases.AddListener(AListener);
end;

class procedure TAtlasIdeDebugSession.RemoveListener(const AListener: IAtlasDebugListener);
begin
  if FPhases = nil then
  begin
    Exit;
  end;
  FPhases.RemoveListener(AListener);
  // Ohne Zuhörer braucht Atlas keinen Notifier beim Debugger: Der letzte meldet ihn ab.
  if FPhases.ListenerCount = 0 then
  begin
    Stop;
  end;
end;

class procedure TAtlasIdeDebugSession.StopTick;
begin
  FStopTimer.Enabled := False;
  Phases.Tick;
end;

class procedure TAtlasIdeDebugSession.SetStopFilter(const AFilter: TAtlasIdeDebugStopFilter);
begin
  Phases.SetStopFilter(AFilter);
end;

class procedure TAtlasIdeDebugSession.SetNamedStopFilter(const AName: string;
  const AFilter: TAtlasIdeDebugStopFilter);
begin
  Phases.SetNamedStopFilter(AName, AFilter);
end;

class function TAtlasIdeDebugSession.Active: Boolean;
begin
  Result := (FPhases <> nil) and FPhases.Active;
end;

class function TAtlasIdeDebugSession.Process: IOTAProcess;
var
  mServices: IOTADebuggerServices;
begin
  Result := nil;
  mServices := TAtlasIdeDebugger.Services;
  if mServices <> nil then
  begin
    Result := mServices.CurrentProcess;
  end;
end;

class function TAtlasIdeDebugSession.StoppedThread: IOTAThread;
var
  mCurrent: IOTAProcess;
begin
  Result := nil;
  mCurrent := Process;
  if (mCurrent <> nil) and IsStoppedState(mCurrent.ProcessState) then
  begin
    Result := mCurrent.CurrentThread;
  end;
end;

class function TAtlasIdeDebugSession.StopCount: Integer;
begin
  Result := 0;
  if FPhases <> nil then
  begin
    Result := FPhases.StopCount;
  end;
end;

class function TAtlasIdeDebugSession.RunTimeBeforeStop: Int64;
begin
  Result := 0;
  if FPhases <> nil then
  begin
    Result := FPhases.RunTimeBeforeStop;
  end;
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
  mIndex: Integer;
begin
  Result := '';
  for mIndex := Low(cLaunchOptionNames) to High(cLaunchOptionNames) do
  begin
    if SameText(cLaunchOptionNames[mIndex], AName) then
    begin
      Exit(FLaunchValues[mIndex]);
    end;
  end;
end;

class procedure TAtlasIdeDebugSession.BeginInternal;
begin
  Phases.BeginInternal;
end;

class procedure TAtlasIdeDebugSession.EndInternal;
begin
  Phases.EndInternal;
end;

/// <summary>Höchstens AMax Rahmen von AThread (Zugriff schon begonnen); None, wenn der Halt unterwegs endet
/// oder der Debug-Kernel nicht antwortet.</summary>
function ReadFrames(const AThread: IOTAThread; AMax: Integer; out AFrames: TAtlasDebugFrames):
  TAtlasDebugStackRead;
var
  mIndex, mLine, mCount: Integer;
  mFileName: string;
begin
  AFrames := nil;
  Result := TAtlasDebugStackRead.Ready;
  try
    mCount := Min(AThread.GetCallCount, AMax);
    mIndex := 0;
    while (Result = TAtlasDebugStackRead.Ready) and (mIndex < mCount) do
    begin
      // Endet die Sitzung während des Lesens (Programm beendet sich nach der Exception), meldet der Kernel
      // jeden weiteren Zugriff mit "Disconnected session": vor jedem Frame prüfen, ob der Halt noch gilt.
      if TAtlasIdeDebugSession.StoppedThread = nil then
      begin
        AFrames := nil;
        Result := TAtlasDebugStackRead.None;
        Continue;
      end;
      mFileName := '';
      mLine := 0;
      // Die Rahmen der Open Tools API zählen ab 1 (ToolsAPI: "CallHeaders are one-based"). Index 0 nimmt der
      // Win32-Debugger hin; der Win64-Debugger meldet darauf "disconnected session".
      AThread.GetCallPos(mIndex + 1, mFileName, mLine);
      AFrames := AFrames + [TAtlasDebugFrame.Create(AThread.GetCallHeader(mIndex + 1), mFileName, mLine)];
      Inc(mIndex);
    end;
  except
    // Verbindung zum Debug-Kernel weg: ohne Stack weiter, nicht die IDE stören.
    on E: Exception do
    begin
      AFrames := nil;
      TAtlasGuard.Log(Format('Debugger-Stack nicht lesbar: %s: %s', [E.ClassName, TAtlasGuard.MessageText(E.Message)]));
      Result := TAtlasDebugStackRead.None;
    end;
  end;
end;

class function TAtlasIdeDebugSession.ReadStack(const AThread: IOTAThread; AMax: Integer;
  out AFrames: TAtlasDebugFrames): TAtlasDebugStackRead;
begin
  AFrames := nil;
  Result := TAtlasDebugStackRead.None;
  if AThread = nil then
  begin
    Exit;
  end;
  try
    case AThread.StartCallStackAccess of
      csWait:
        Result := TAtlasDebugStackRead.Wait;
      csInaccessible:
        ;
    else
      Result := ReadFrames(AThread, AMax, AFrames);
    end;
  finally
    AThread.EndCallStackAccess;
  end;
end;

class function TAtlasIdeDebugSession.StackDepth(const AThread: IOTAThread; out ADepth: Integer): TAtlasDebugStackRead;
var
  mAccess: TOTACallStackState;
begin
  ADepth := 0;
  Result := TAtlasDebugStackRead.None;
  if AThread = nil then
  begin
    Exit;
  end;
  mAccess := AThread.StartCallStackAccess;
  try
    case mAccess of
      csWait:
        Exit(TAtlasDebugStackRead.Wait);
      csInaccessible:
        Exit;
      csAccessible:
        ; // Lesbar: Tiefe unten holen.
    end;
    try
      ADepth := AThread.GetCallCount;
    except
      // Verbindung zum Debug-Kernel weg (siehe ReadStack).
      on E: Exception do
      begin
        ADepth := 0;
        TAtlasGuard.Log(Format('Debugger-Stacktiefe nicht lesbar: %s: %s', [E.ClassName,
          TAtlasGuard.MessageText(E.Message)]));
        Exit(TAtlasDebugStackRead.None);
      end;
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
  begin
    Exit;
  end;
  try
    Result := AThread.GetThreadName;
  except
    // Ältere Debugger kennen keine Thread-Namen.
    on E: Exception do
    begin
      TAtlasGuard.Log('Debugger: Thread-Name nicht lesbar: ' + TAtlasGuard.ErrorText(E)); // german-ok Protokoll
      Result := '';
    end;
  end;
end;

class function TAtlasIdeDebugSession.Resume: Boolean;
begin
  Result := RunMode(ormRun);
end;

class function TAtlasIdeDebugSession.RunMode(ARunMode: TOTARunMode): Boolean;
var
  mCurrent: IOTAProcess;
begin
  mCurrent := Process;
  Result := (mCurrent <> nil) and IsStoppedState(mCurrent.ProcessState);
  if Result then
  begin
    mCurrent.Run(ARunMode);
  end;
end;

initialization

finalization
  FreeAndNil(TAtlasIdeDebugSession.FPhases);
  TAtlasIdeDebugSession.FTarget := nil;
  TAtlasIdeDebugSession.FNewEvaluator := nil;

end.
