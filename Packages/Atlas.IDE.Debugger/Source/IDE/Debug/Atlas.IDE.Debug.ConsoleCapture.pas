unit Atlas.IDE.Debug.ConsoleCapture;

// Ausgabe von Konsolenprogrammen andocken (#581) in der IDE, Teil
// „DebugCaptureConsole“ (debug.captureConsole):
// - Start mit Debugger (F9, Menü, Symbolleiste): Vor dem Start fragt die
//   Sitzung die Zuhörer (IAtlasIdeDebugLaunchCheck, BeforeProgramLaunch). Ist
//   das aktive Projekt ein Konsolenprogramm für Win32/Win64 ohne
//   Host-Anwendung (TAtlasConsoleLaunch), lehnt Atlas den Start der IDE ab und
//   startet im nächsten Takt selbst: angehalten und mit Pipes
//   (TAtlasIdeConsoleProcess), dann hängt sich der Debugger der IDE an
//   (IOTADebuggerServices.AttachProcess ohne Halt nach dem Anhängen). Erst
//   wenn die IDE den Prozess laufend oder angehalten führt, läuft der erste
//   Thread weiter (TAtlasConsoleAttach); so greifen Haltepunkte ab der ersten
//   Zeile. Übernimmt der Debugger nicht binnen cAttachTimeoutMs, läuft das
//   Programm trotzdem weiter, mit Meldung.
// - „Ohne Debugger mit Konsolenausgabe starten“ (Menü Start, Befehl): baut,
//   wenn die IDE das Projekt als geändert meldet, und startet ohne Debugger.
// - Fenster „Atlas: Konsolenausgabe“ (TAtlasIdeDebugDockPanel): Zeilen aus
//   stdout und stderr, Eingabefeld (Send schreibt nach stdin), Beenden,
//   Leeren, Klick auf Fundstellen öffnet die Datei (relativ zum Arbeitsordner,
//   dann zum Projektordner). Nach dem Ende bleibt es mit dem Exit-Code stehen.
// - Ein Lauf (TAtlasIdeConsoleRun) gehört zu einem gestarteten Programm:
//   Prozess, Anhängen, Zustand, Fundstellen relativ zu seinen Ordnern.
// - Ein Zeitgeber (cTickMs) holt die gelesenen Stücke im Hauptthread ab;
//   nichts reiht sich in den Hauptthread ein. Release beendet Zeitgeber und
//   Lesethread, das Programm selbst läuft weiter (im Debugger gehört es der
//   IDE).
// Parameter, Arbeitsordner und Umgebung kommen aus den Startoptionen des
// Projekts (also auch aus dem aktiven Startprofil, #575). Das Protokoll
// bekommt keine Parameter oder Pfade, nur Kennung und Zeiten des Anhängens.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Debug.Phases,
  Atlas.Core.Debug.Contract,
  Atlas.Core.Debug.ConsoleCapture,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.ConsoleProcess,
  Atlas.IDE.Debug.DockPanel,
  Atlas.UI.Debug.ConsoleFrame;

type
  /// <summary>Ein Lauf eines Konsolenprogramms: starten, Debugger anhängen und abwarten, Ausgabe in den Puffer,
  /// Eingabe, Beenden; nach dem Ende bleiben Name, Exit-Code und Ordner für Zustand und Fundstellen.</summary>
  TAtlasIdeConsoleRun = class
  public const
    cAttachTimeoutMs = 10000;
  private type
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Attaching, Running, Ended);
    {$SCOPEDENUMS OFF}
  private
    FBuffer: TAtlasConsoleBuffer;
    FMessage: TProc<string>;
    FProcess: TAtlasIdeConsoleProcess;
    FPhase: TPhase;
    FName: string;
    FPid: Cardinal;
    FDebug: Boolean;
    FExitCode: Cardinal;
    FAttachAt: UInt64;
    FWorkingDir: string;
    FProjectDir: string;
    procedure Say(const AText: string);
    procedure Attach;
    /// <summary>True, wenn sich der Zustand geändert hat.</summary>
    function CheckAttach: Boolean;
    function IdeProcess: IOTAProcess;
    function IdeReady: Boolean;
    procedure Finish(AExitCode: Cardinal);
  public
    /// <summary>ABuffer gehört dem Aufrufer; AMessage schreibt in die Meldungsansicht.</summary>
    constructor Create(ABuffer: TAtlasConsoleBuffer; const AMessage: TProc<string>);
    /// <summary>Beendet den Lesethread; das Programm läuft weiter.</summary>
    destructor Destroy; override;
    /// <summary>Programm von AProject mit seinen Startoptionen starten, mit ADebug angehalten und mit Debugger.
    /// </summary>
    function Start(const AProject: IOTAProject; ADebug: Boolean): Boolean;
    /// <summary>Anhängen abwarten, Ausgabe abholen, Ende erkennen; True, wenn das Fenster neu zeichnen soll.
    /// </summary>
    function Tick: Boolean;
    function Running: Boolean;
    /// <summary>Zustandszeile; ARunning, solange das Programm Eingaben nimmt.</summary>
    function StateText(out ARunning: Boolean): string;
    procedure Send(const AText: string);
    procedure CloseInput;
    /// <summary>Im Debugger über die IDE beenden, damit ihre Sitzung sauber endet.</summary>
    procedure Stop;
    /// <summary>Datei einer Fundstelle: wie angegeben, sonst im Arbeitsordner, sonst im Projektordner.</summary>
    function ResolveFile(const AFileName: string): string;
    property Name: string read FName;
  end;

  TAtlasIdeConsoleCapture = class
  private type
    /// <summary>Fragt vor jedem Start mit Debugger, ob Atlas ihn übernimmt.</summary>
    TListener = class(TAtlasDebugListener, IAtlasIdeDebugLaunchCheck)
    public
      function AllowLaunch(const AProject: IOTAProject): Boolean;
    end;
    THandler = class
    public
      procedure Tick(Sender: TObject);
      procedure RunClick(Sender: TObject);
    end;
  private class var
    FInstance: TAtlasIdeConsoleCapture;
  private
    FMessage: TProc<string>;
    FListener: IAtlasDebugListener;
    FHandler: THandler;
    FTimer: TTimer;
    FPanel: TAtlasIdeDebugDockPanel;
    FRunItem: TMenuItem;
    FBuffer: TAtlasConsoleBuffer;
    FRun: TAtlasIdeConsoleRun;
    /// <summary>Vom abgelehnten Start der IDE: Projekt, das der nächste Takt startet ('' = keins).</summary>
    FQueued: string;
    constructor Create(const AMessage: TProc<string>);
    procedure Say(const AText: string);
    procedure Tick;
    function Busy: Boolean;
    function RunName: string;
    function Choose(const AProject: IOTAProject): TAtlasConsoleLaunchChoice;
    procedure Launch(const AProject: IOTAProject; ADebug: Boolean);
    procedure ShowState;
    procedure WireFrame(AFrame: TAtlasDebugConsoleFrame);
    function Frame: TAtlasDebugConsoleFrame;
    procedure Refill;
    procedure SendInput(const AText: string);
    procedure CloseInput;
    procedure StopProgram;
    procedure ClearOutput;
    procedure OpenLocation(const ALocation: TAtlasConsoleLocation);
  public
    destructor Destroy; override;
    /// <summary>Teil starten; AMessage schreibt in die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.captureConsole an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Befehl Atlas.ConsoleOutput: Fenster zeigen.</summary>
    class procedure ShowWindow; static;
    /// <summary>Befehl Atlas.ConsoleRunNoDebug: aktives Projekt bauen und ohne Debugger mit Konsolenausgabe
    /// starten.</summary>
    class procedure RunWithoutDebugger; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  System.IOUtils,
  Winapi.Windows,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Calls.Optional,
  Atlas.Core.StartProfiles.Store,
  Atlas.ToolsApi.Debugger.Services,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.StartOptions,
  Atlas.IDE.Debug.LaunchProbe,
  Atlas.IDE.Debug.RunMenu,
  Atlas.UI.Debug.Console.Strings;

const
  cTickMs = 50;
  cIdentifier = 'AtlasConsoleOutput';
  cRunItemName = 'AtlasConsoleRunNoDebug';

function NowMs: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

/// <summary>Startoptionen von AProject (Parameter, Arbeitsordner, Host, Umgebung); leer, wenn sie fehlen.</summary>
function OptionsOf(const AProject: IOTAProject): TAtlasStartOptions;
begin
  Result := Default(TAtlasStartOptions);
  if AProject <> nil then
  begin
    TAtlasIdeStartOptions.ReadOptions(AProject, Result);
  end;
end;

function TargetOf(const AProject: IOTAProject): string;
begin
  Result := '';
  if (AProject <> nil) and (AProject.ProjectOptions <> nil) then
  begin
    Result := AProject.ProjectOptions.TargetName;
  end;
end;

{ TAtlasIdeConsoleRun }

constructor TAtlasIdeConsoleRun.Create(ABuffer: TAtlasConsoleBuffer; const AMessage: TProc<string>);
begin
  inherited Create;
  FBuffer := ABuffer;
  FMessage := AMessage;
end;

destructor TAtlasIdeConsoleRun.Destroy;
begin
  FreeAndNil(FProcess);
  FMessage := nil;
  inherited Destroy;
end;

procedure TAtlasIdeConsoleRun.Say(const AText: string);
begin
  TAtlasCalls.Send(FMessage, AText);
end;

function TAtlasIdeConsoleRun.Running: Boolean;
begin
  Result := FProcess <> nil;
end;

function TAtlasIdeConsoleRun.Start(const AProject: IOTAProject; ADebug: Boolean): Boolean;
var
  mOptions: TAtlasStartOptions;
  mStart: TAtlasConsoleStart;
  mError: Cardinal;
  mNote: TAtlasConsoleTextId;
begin
  mOptions := OptionsOf(AProject);
  mStart := Default(TAtlasConsoleStart);
  mStart.Exe := TargetOf(AProject);
  mStart.Arguments := mOptions.Parameters;
  mStart.WorkingDir := mOptions.WorkingDir;
  mStart.Environment := TAtlasIdeLaunchProcesses.EnvironmentBlock(
    TAtlasStartProfiles.DecodeEnvironment(mOptions.Environment));
  mStart.Suspended := ADebug;
  FName := ExtractFileName(mStart.Exe);
  FDebug := ADebug;
  FProjectDir := ExtractFileDir(AProject.FileName);
  FWorkingDir := mStart.WorkingDir;
  if FWorkingDir = '' then
  begin
    FWorkingDir := ExtractFileDir(mStart.Exe);
  end;
  mNote := TAtlasConsoleTextId.NoteStarted;
  if ADebug then
  begin
    mNote := TAtlasConsoleTextId.NoteStartedDebug;
  end;
  FBuffer.AddNote(TAtlasConsoleStrings.Fmt(mNote, [FName, mStart.Arguments]));
  FProcess := TAtlasIdeConsoleProcess.Create(Integer(GetACP));
  Result := FProcess.Start(mStart, mError);
  if not Result then
  begin
    FreeAndNil(FProcess);
    FPhase := TPhase.Idle;
    Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.StartFailed, [FName, mError]));
    Exit;
  end;
  FPid := FProcess.Pid;
  FPhase := TPhase.Running;
  if ADebug then
  begin
    Attach;
  end;
end;

procedure TAtlasIdeConsoleRun.Attach;
var
  mServices: IOTADebuggerServices;
begin
  mServices := TAtlasIdeDebugger.Services;
  FAttachAt := NowMs;
  FPhase := TPhase.Attaching;
  try
    if mServices = nil then
    begin
      Abort;
    end;
    // In Delphi 13 nur die Form mit PauseAfterAttach und DetachOnReset: kein Halt, Strg+F2 beendet das Programm.
    mServices.AttachProcess(Integer(FPid), False, False);
    TAtlasIdeHost.Log(Format('Console capture: AttachProcess(%d) returned after %d ms', [FPid, NowMs - FAttachAt]));
  except
    on E: Exception do
    begin
      // Ohne Debugger weiterlaufen lassen statt das Programm angehalten stehen zu lassen.
      TAtlasIdeHost.Log(Format('Console capture: AttachProcess(%d) failed: %s', [FPid, E.ClassName]));
      Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.AttachFailed, [FName, FPid]));
      FProcess.Resume;
      FPhase := TPhase.Running;
    end;
  end;
end;

function TAtlasIdeConsoleRun.IdeProcess: IOTAProcess;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
begin
  Result := nil;
  mServices := TAtlasIdeDebugger.Services;
  if (mServices = nil) or (FPid = 0) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ProcessCount - 1 do
  begin
    if mServices.Processes[mIndex].ProcessId = FPid then
    begin
      Result := mServices.Processes[mIndex];
      Exit;
    end;
  end;
end;

function TAtlasIdeConsoleRun.IdeReady: Boolean;
var
  mProcess: IOTAProcess;
begin
  mProcess := IdeProcess;
  Result := (mProcess <> nil) and (mProcess.ProcessState in [psRunning, psStopped]);
end;

function TAtlasIdeConsoleRun.CheckAttach: Boolean;
var
  mFacts: TAtlasConsoleAttachFacts;
  mWaited: UInt64;
begin
  mWaited := NowMs - FAttachAt;
  mFacts := Default(TAtlasConsoleAttachFacts);
  mFacts.ElapsedMs := mWaited;
  mFacts.TimeoutMs := cAttachTimeoutMs;
  mFacts.IdeReady := IdeReady;
  mFacts.Alive := WaitForSingleObject(FProcess.ProcessHandle, 0) = WAIT_TIMEOUT;
  Result := True;
  case TAtlasConsoleAttach.Next(mFacts) of
    TAtlasConsoleAttachStep.Resume:
      begin
        FProcess.Resume;
        FPhase := TPhase.Running;
        TAtlasIdeHost.Log(Format('Console capture: debugger ready for %d after %d ms, resumed', [FPid, mWaited]));
      end;
    TAtlasConsoleAttachStep.ResumeLate:
      begin
        FProcess.Resume;
        FPhase := TPhase.Running;
        TAtlasIdeHost.Log(Format('Console capture: debugger not ready for %d after %d ms, resumed anyway',
          [FPid, mWaited]));
        Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.AttachLate, [FName, FPid, mWaited]));
      end;
    TAtlasConsoleAttachStep.Gone:
      begin
        FPhase := TPhase.Running;
        Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.AttachGone, [FName, FPid]));
      end;
  else
    Result := False;
  end;
end;

procedure TAtlasIdeConsoleRun.Finish(AExitCode: Cardinal);
begin
  FreeAndNil(FProcess);
  FExitCode := AExitCode;
  FPhase := TPhase.Ended;
  FBuffer.Finish;
  if FBuffer.Dropped > 0 then
  begin
    FBuffer.AddNote(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.NoteDropped, [FBuffer.Dropped]));
  end;
  FBuffer.AddNote(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.NoteEnded,
    [TAtlasConsoleLaunch.ExitCodeText(AExitCode)]));
end;

function TAtlasIdeConsoleRun.Tick: Boolean;
var
  mChunk: TAtlasConsoleChunk;
  mExitCode: Cardinal;
begin
  Result := False;
  if FProcess = nil then
  begin
    Exit;
  end;
  if FPhase = TPhase.Attaching then
  begin
    Result := CheckAttach;
  end;
  for mChunk in FProcess.TakeChunks do
  begin
    FBuffer.Add(mChunk.Stream, mChunk.Data, Length(mChunk.Data));
    Result := True;
  end;
  if FProcess.Ended(mExitCode) then
  begin
    Finish(mExitCode);
    Result := True;
  end;
end;

function TAtlasIdeConsoleRun.StateText(out ARunning: Boolean): string;
begin
  ARunning := FProcess <> nil;
  case FPhase of
    TPhase.Attaching:
      Result := TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.StateAttaching, [FName, FPid]);
    TPhase.Running:
      Result := TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.StateRunning, [FName, FPid]);
    TPhase.Ended:
      Result := TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.StateEnded,
        [FName, TAtlasConsoleLaunch.ExitCodeText(FExitCode)]);
  else
    Result := TAtlasConsoleStrings.Text(TAtlasConsoleTextId.StateIdle);
  end;
end;

procedure TAtlasIdeConsoleRun.Send(const AText: string);
begin
  if FProcess <> nil then
  begin
    FBuffer.AddInput(AText);
    FProcess.Send(AText);
  end;
end;

procedure TAtlasIdeConsoleRun.CloseInput;
begin
  if FProcess <> nil then
  begin
    FProcess.CloseInput;
    FBuffer.AddNote(TAtlasConsoleStrings.Text(TAtlasConsoleTextId.InputClosed));
  end;
end;

procedure TAtlasIdeConsoleRun.Stop;
var
  mProcess: IOTAProcess;
begin
  if FProcess = nil then
  begin
    Exit;
  end;
  mProcess := nil;
  if FDebug then
  begin
    mProcess := IdeProcess;
  end;
  if mProcess <> nil then
  begin
    mProcess.Terminate;
  end
  else
  begin
    FProcess.Terminate;
  end;
end;

function TAtlasIdeConsoleRun.ResolveFile(const AFileName: string): string;
var
  mName, mFolder, mCandidate: string;
begin
  // Pfade mit „/“ trennt ExtractFilePath unter Windows nicht: erst angleichen.
  mName := StringReplace(AFileName, '/', PathDelim, [rfReplaceAll]);
  Result := mName;
  if (ExtractFileDrive(mName) <> '') or FileExists(mName) then
  begin
    Exit;
  end;
  for mFolder in TArray<string>.Create(FWorkingDir, FProjectDir) do
  begin
    if mFolder = '' then
    begin
      Continue;
    end;
    mCandidate := TPath.Combine(mFolder, mName);
    if FileExists(mCandidate) then
    begin
      Result := mCandidate;
      Exit;
    end;
  end;
end;

{ TAtlasIdeConsoleCapture.TListener }

function TAtlasIdeConsoleCapture.TListener.AllowLaunch(const AProject: IOTAProject): Boolean;
var
  mInstance: TAtlasIdeConsoleCapture;
begin
  Result := True;
  mInstance := TAtlasIdeConsoleCapture.FInstance;
  if (mInstance = nil) or (AProject = nil) then
  begin
    Exit;
  end;
  case mInstance.Choose(AProject) of
    TAtlasConsoleLaunchChoice.Capture:
      begin
        // Nicht im Notifier starten: Der nächste Takt startet und hängt den Debugger an.
        mInstance.FQueued := AProject.FileName;
        Result := False;
      end;
    TAtlasConsoleLaunchChoice.Busy:
      begin
        mInstance.Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.Busy, [mInstance.RunName]));
        Result := False;
      end;
  end;
end;

{ TAtlasIdeConsoleCapture.THandler }

procedure TAtlasIdeConsoleCapture.THandler.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeConsoleCapture.FInstance <> nil then
      begin
        TAtlasIdeConsoleCapture.FInstance.Tick;
      end;
    end);
end;

procedure TAtlasIdeConsoleCapture.THandler.RunClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeConsoleCapture.RunWithoutDebugger);
end;

{ TAtlasIdeConsoleCapture }

constructor TAtlasIdeConsoleCapture.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
  FBuffer := TAtlasConsoleBuffer.Create(Integer(GetACP), TAtlasConsoleBuffer.cDefaultMaxLines);
  FHandler := THandler.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := FHandler.Tick;
  FTimer.Enabled := True;
  FPanel := TAtlasIdeDebugDockPanel.Create(cIdentifier, TAtlasDebugConsoleFrame,
    function: string
    begin
      Result := TAtlasConsoleStrings.Text(TAtlasConsoleTextId.Caption);
    end);
  FRunItem := TAtlasIdeRunMenu.AddItem(cRunItemName, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.MenuRunNoDebug),
    FHandler.RunClick);
  FListener := TListener.Create;
end;

destructor TAtlasIdeConsoleCapture.Destroy;
var
  mFrame: TAtlasDebugConsoleFrame;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
    FListener := nil;
  end;
  FreeAndNil(FTimer);
  FreeAndNil(FRunItem);
  // Lesethread beenden; das Programm läuft weiter.
  FreeAndNil(FRun);
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.SetBuffer(nil);
    mFrame.OnSend := nil;
    mFrame.OnCloseInput := nil;
    mFrame.OnStop := nil;
    mFrame.OnClear := nil;
    mFrame.OnOpen := nil;
  end;
  FreeAndNil(FPanel);
  FreeAndNil(FHandler);
  FreeAndNil(FBuffer);
  FMessage := nil;
  inherited Destroy;
end;

procedure TAtlasIdeConsoleCapture.Say(const AText: string);
begin
  TAtlasCalls.Send(FMessage, AText);
end;

function TAtlasIdeConsoleCapture.Busy: Boolean;
begin
  Result := (FRun <> nil) and FRun.Running;
end;

function TAtlasIdeConsoleCapture.RunName: string;
begin
  Result := '';
  if FRun <> nil then
  begin
    Result := FRun.Name;
  end;
end;

function TAtlasIdeConsoleCapture.Choose(const AProject: IOTAProject): TAtlasConsoleLaunchChoice;
var
  mFacts: TAtlasConsoleLaunchFacts;
begin
  mFacts := Default(TAtlasConsoleLaunchFacts);
  mFacts.Enabled := Enabled;
  mFacts.Platform := AProject.CurrentPlatform;
  mFacts.Kind := TAtlasConsoleImage.KindOfFile(TargetOf(AProject));
  mFacts.Host := OptionsOf(AProject).Host;
  mFacts.Busy := Busy;
  Result := TAtlasConsoleLaunch.Choose(mFacts);
end;

function TAtlasIdeConsoleCapture.Frame: TAtlasDebugConsoleFrame;
begin
  Result := nil;
  if (FPanel <> nil) and (FPanel.ExistingFrame is TAtlasDebugConsoleFrame) then
  begin
    Result := TAtlasDebugConsoleFrame(FPanel.ExistingFrame);
  end;
end;

procedure TAtlasIdeConsoleCapture.Refill;
var
  mFrame: TAtlasDebugConsoleFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.Refill;
  end;
end;

procedure TAtlasIdeConsoleCapture.ShowState;
var
  mFrame: TAtlasDebugConsoleFrame;
  mRunning: Boolean;
  mText: string;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mRunning := False;
  mText := TAtlasConsoleStrings.Text(TAtlasConsoleTextId.StateIdle);
  if FRun <> nil then
  begin
    mText := FRun.StateText(mRunning);
  end;
  mFrame.SetState(mText, mRunning);
end;

procedure TAtlasIdeConsoleCapture.WireFrame(AFrame: TAtlasDebugConsoleFrame);
begin
  // Die Ereignisse fragen FInstance: Ein Frame, den die IDE länger hält, erreicht nach Release nichts mehr.
  AFrame.OnSend :=
    procedure(AText: string)
    begin
      if FInstance <> nil then
      begin
        FInstance.SendInput(AText);
      end;
    end;
  AFrame.OnCloseInput :=
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.CloseInput;
      end;
    end;
  AFrame.OnStop :=
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.StopProgram;
      end;
    end;
  AFrame.OnClear :=
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.ClearOutput;
      end;
    end;
  AFrame.OnOpen :=
    procedure(ALocation: TAtlasConsoleLocation)
    begin
      if FInstance <> nil then
      begin
        FInstance.OpenLocation(ALocation);
      end;
    end;
  AFrame.SetBuffer(FBuffer);
  ShowState;
end;

procedure TAtlasIdeConsoleCapture.Launch(const AProject: IOTAProject; ADebug: Boolean);
begin
  FreeAndNil(FRun);
  FBuffer.Clear;
  FPanel.Show;
  FRun := TAtlasIdeConsoleRun.Create(FBuffer, FMessage);
  FRun.Start(AProject, ADebug);
  ShowState;
  Refill;
  if Frame <> nil then
  begin
    Frame.FocusInput;
  end;
end;

procedure TAtlasIdeConsoleCapture.Tick;
var
  mProject: IOTAProject;
begin
  if FQueued <> '' then
  begin
    mProject := TAtlasIdeStartOptions.FindProject(FQueued);
    FQueued := '';
    if mProject <> nil then
    begin
      Launch(mProject, True);
    end;
  end;
  if (FRun <> nil) and FRun.Tick then
  begin
    ShowState;
    Refill;
  end;
end;

procedure TAtlasIdeConsoleCapture.SendInput(const AText: string);
begin
  if FRun <> nil then
  begin
    FRun.Send(AText);
    Refill;
  end;
end;

procedure TAtlasIdeConsoleCapture.CloseInput;
begin
  if FRun <> nil then
  begin
    FRun.CloseInput;
    Refill;
  end;
end;

procedure TAtlasIdeConsoleCapture.StopProgram;
begin
  if FRun <> nil then
  begin
    FRun.Stop;
  end;
end;

procedure TAtlasIdeConsoleCapture.ClearOutput;
begin
  FBuffer.Clear;
  Refill;
end;

procedure TAtlasIdeConsoleCapture.OpenLocation(const ALocation: TAtlasConsoleLocation);
var
  mFileName: string;
  mColumn: Integer;
begin
  mFileName := ALocation.FileName;
  if FRun <> nil then
  begin
    mFileName := FRun.ResolveFile(mFileName);
  end;
  mColumn := ALocation.Column - 1;
  if mColumn < 0 then
  begin
    mColumn := 0;
  end;
  TAtlasIdeNavigation.GoToLocation(mFileName, ALocation.Line - 1, mColumn);
end;

class procedure TAtlasIdeConsoleCapture.Start(const AMessage: TProc<string>);
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TAtlasIdeConsoleCapture.Create(AMessage);
  FInstance.FPanel.OnFrame :=
    procedure(AFrame: TCustomFrame)
    begin
      if (FInstance <> nil) and (AFrame is TAtlasDebugConsoleFrame) then
      begin
        FInstance.WireFrame(TAtlasDebugConsoleFrame(AFrame));
      end;
    end;
  // Früh anmelden, damit der Desktop das Fenster speichert und wiederherstellt (#879).
  FInstance.FPanel.Prepare;
  TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeConsoleCapture.Release;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeConsoleCapture.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeConsoleCapture.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.DebugCaptureConsole;
end;

class procedure TAtlasIdeConsoleCapture.ShowWindow;
begin
  if FInstance <> nil then
  begin
    FInstance.FPanel.Show;
    FInstance.Refill;
  end;
end;

class procedure TAtlasIdeConsoleCapture.RunWithoutDebugger;
var
  mProject: IOTAProject;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    FInstance.Say(TAtlasConsoleStrings.Text(TAtlasConsoleTextId.NoProject));
    Exit;
  end;
  if (mProject.ProjectBuilder <> nil) and mProject.ProjectBuilder.ShouldBuild and
    not mProject.ProjectBuilder.BuildProject(cmOTAMake, True, True) then
  begin
    FInstance.Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.BuildFailed,
      [ExtractFileName(mProject.FileName)]));
    Exit;
  end;
  case FInstance.Choose(mProject) of
    TAtlasConsoleLaunchChoice.Capture:
      FInstance.Launch(mProject, False);
    TAtlasConsoleLaunchChoice.Busy:
      FInstance.Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.Busy, [FInstance.RunName]));
  else
    FInstance.Say(TAtlasConsoleStrings.Fmt(TAtlasConsoleTextId.NotConsole,
      [ExtractFileName(TargetOf(mProject))]));
  end;
end;

class procedure TAtlasIdeConsoleCapture.ThemeChanged;
begin
  if FInstance <> nil then
  begin
    FInstance.FPanel.ApplyTheme;
    // Farben von stderr, Eingabe und Hinweisen hängen vom Hintergrund des Themas ab.
    FInstance.Refill;
  end;
end;

end.
