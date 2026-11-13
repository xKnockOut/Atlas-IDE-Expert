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
  Vcl.ExtCtrls,
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
    FListeners: TList<IAtlasIdeDebugListener>;
    FProcesses: Integer;
    FStopped: Boolean;
    FInternal: Integer;
    FStopCount: Integer;
    FProject: string;
    FConfiguration: string;
    FPlatform: string;
    FLaunchValues: array[0..3] of string;
    // Meldet einen Halt nach dem Notifier. Ein Zeitgeber statt ForceQueue: Er feuert auch in der Nachrichtenschleife
    // des Exception-Dialogs der IDE, die Warteschlange erst nach dessen Schließen (#783: Dialog erkennen).
    FStopTimer: TTimer;
    FTicker: TObject;
    FPendingStop: TAtlasDebugStop;
    FPendingCount: Integer;
    class procedure StopTick; static;
    class procedure NotifyListeners(const AEvent: TProc<IAtlasIdeDebugListener>); static;
    class procedure StateChanged(const AProcess: IOTAProcess); static;
    class procedure Ended; static;
    class procedure BreakpointsChanged; static;
    /// <summary>Zuhörer mit IAtlasIdeDebugLaunchCheck fragen; False, wenn einer ablehnt.</summary>
    class function AllowLaunch(const AProject: IOTAProject): Boolean; static;
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
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Projects.Context;

function Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
  begin
    Result := nil;
  end;
end;

function IsStoppedState(AState: TOTAProcessState): Boolean;
begin
  Result := AState in [psStopped, psFault, psResFault, psException];
end;

type
  TStopTicker = class
  public
    procedure Tick(Sender: TObject);
  end;

procedure TStopTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugSession.StopTick);
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
    TAtlasIdeDebugSession.NotifyListeners(
      procedure(AListener: IAtlasIdeDebugListener)
      begin
        AListener.DebugStarted;
      end);
  end;
end;

procedure TAtlasIdeDebugSession.TNotifier.ProcessDestroyed(const Process: IOTAProcess);
begin
  if TAtlasIdeDebugSession.FProcesses > 0 then
  begin
    Dec(TAtlasIdeDebugSession.FProcesses);
  end;
  if TAtlasIdeDebugSession.FProcesses = 0 then
  begin
    TAtlasIdeDebugSession.Ended;
  end;
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointAdded(const Breakpoint: IOTABreakpoint);
begin
  TAtlasIdeDebugSession.BreakpointsChanged;
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointDeleted(const Breakpoint: IOTABreakpoint);
begin
  TAtlasIdeDebugSession.BreakpointsChanged;
end;

procedure TAtlasIdeDebugSession.TNotifier.BreakpointChanged(const Breakpoint: IOTABreakpoint);
begin
  TAtlasIdeDebugSession.BreakpointsChanged;
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
    // Nur Merkwerte; der Start geht in jedem Fall weiter.
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

class procedure TAtlasIdeDebugSession.Start;
var
  mServices: IOTADebuggerServices;
  mNotifier: IOTADebuggerNotifier;
begin
  if FListeners = nil then
  begin
    FListeners := TList<IAtlasIdeDebugListener>.Create;
  end;
  if FNotifierIndex > 0 then
  begin
    Exit;
  end;
  mServices := Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  // Index + 1, damit 0 „nicht angemeldet“ heißt.
  mNotifier := TNotifier.Create;
  FNotifierIndex := mServices.AddNotifier(mNotifier) + 1;
  FProcesses := mServices.ProcessCount;
  FStopped := (mServices.CurrentProcess <> nil) and IsStoppedState(mServices.CurrentProcess.ProcessState);
end;

class procedure TAtlasIdeDebugSession.Stop;
var
  mServices: IOTADebuggerServices;
begin
  if FNotifierIndex > 0 then
  begin
    mServices := Debugger;
    if mServices <> nil then
    begin
      mServices.RemoveNotifier(FNotifierIndex - 1);
    end;
    FNotifierIndex := 0;
  end;
  FreeAndNil(FStopTimer);
  FreeAndNil(FTicker);
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
  begin
    FListeners := TList<IAtlasIdeDebugListener>.Create;
  end;
  if (AListener <> nil) and (FListeners.IndexOf(AListener) < 0) then
  begin
    FListeners.Add(AListener);
  end;
end;

class procedure TAtlasIdeDebugSession.RemoveListener(const AListener: IAtlasIdeDebugListener);
begin
  if FListeners = nil then
  begin
    Exit;
  end;
  FListeners.Remove(AListener);
  // Ohne Zuhörer braucht Atlas keinen Notifier beim Debugger: Der letzte meldet ihn ab.
  if FListeners.Count = 0 then
  begin
    Stop;
  end;
end;

class function TAtlasIdeDebugSession.AllowLaunch(const AProject: IOTAProject): Boolean;
var
  mListeners: TArray<IAtlasIdeDebugListener>;
  mListener: IAtlasIdeDebugListener;
  mCheck: IAtlasIdeDebugLaunchCheck;
begin
  Result := True;
  if FListeners = nil then
  begin
    Exit;
  end;
  mListeners := FListeners.ToArray;
  for mListener in mListeners do
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

class procedure TAtlasIdeDebugSession.NotifyListeners(const AEvent: TProc<IAtlasIdeDebugListener>);
var
  mListeners: TArray<IAtlasIdeDebugListener>;
  mListener: IAtlasIdeDebugListener;
begin
  if FListeners = nil then
  begin
    Exit;
  end;
  // Kopie: Ein Zuhörer darf sich beim Ereignis ab- oder einen anderen anmelden.
  mListeners := FListeners.ToArray;
  for mListener in mListeners do
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger,
      procedure
      begin
        if (FListeners <> nil) and (FListeners.IndexOf(mListener) >= 0) then
        begin
          AEvent(mListener);
        end;
      end);
  end;
end;

class procedure TAtlasIdeDebugSession.BreakpointsChanged;
begin
  NotifyListeners(
    procedure(AListener: IAtlasIdeDebugListener)
    var
      mBreakpoints: IAtlasIdeDebugBreakpointListener;
    begin
      if Supports(AListener, IAtlasIdeDebugBreakpointListener, mBreakpoints) then
      begin
        mBreakpoints.BreakpointsChanged;
      end;
    end);
end;

class procedure TAtlasIdeDebugSession.StateChanged(const AProcess: IOTAProcess);
var
  mState: TOTAProcessState;
  mStop: TAtlasDebugStop;
begin
  if (AProcess = nil) or (FInternal > 0) then
  begin
    Exit;
  end;
  mState := AProcess.ProcessState;
  if IsStoppedState(mState) then
  begin
    case mState of
      psException:
        mStop := TAtlasDebugStop.Exception;
      psFault, psResFault:
        mStop := TAtlasDebugStop.Fault;
    else
      mStop := TAtlasDebugStop.Paused;
    end;
    FStopped := True;
    Inc(FStopCount);
    // Erst nach der Benachrichtigung des Debuggers melden; ist der Halt bis dahin vorbei, entfällt er.
    FPendingStop := mStop;
    FPendingCount := FStopCount;
    if FStopTimer = nil then
    begin
      FTicker := TStopTicker.Create;
      FStopTimer := TTimer.Create(nil);
      FStopTimer.Enabled := False;
      FStopTimer.Interval := 1;
      FStopTimer.OnTimer := TStopTicker(FTicker).Tick;
    end;
    FStopTimer.Enabled := True;
  end
  else if (mState = psRunning) and FStopped then
  begin
    FStopped := False;
    NotifyListeners(
      procedure(AListener: IAtlasIdeDebugListener)
      begin
        AListener.DebugResumed;
      end);
  end;
end;

class procedure TAtlasIdeDebugSession.StopTick;
var
  mStop: TAtlasDebugStop;
begin
  FStopTimer.Enabled := False;
  // Weitergelaufen oder schon ein neuer Halt (der meldet sich selbst): dieser entfällt.
  if not FStopped or (FPendingCount <> FStopCount) or (StoppedThread = nil) then
  begin
    Exit;
  end;
  mStop := FPendingStop;
  NotifyListeners(
    procedure(AListener: IAtlasIdeDebugListener)
    begin
      AListener.DebugStopped(mStop);
    end);
end;

class procedure TAtlasIdeDebugSession.Ended;
begin
  FStopped := False;
  NotifyListeners(
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
  mServices: IOTADebuggerServices;
begin
  Result := nil;
  mServices := Debugger;
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
  Inc(FInternal);
end;

class procedure TAtlasIdeDebugSession.EndInternal;
begin
  if FInternal > 0 then
  begin
    Dec(FInternal);
  end;
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
    Result := '';
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

end.
