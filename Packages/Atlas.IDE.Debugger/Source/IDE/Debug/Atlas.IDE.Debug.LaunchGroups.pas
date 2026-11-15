unit Atlas.IDE.Debug.LaunchGroups;

// Mehrere Programme gemeinsam debuggen (#867) in der IDE:
// - Verbünde aus der Projektdatei .atlas ("launchGroups", TAtlasIdeTeamFile;
//   Pfade ab ihrem Ordner). Der aktive Verbund ist persönlich und gilt je
//   Projektgruppe (%LOCALAPPDATA%\Atlas\debug-launchgroups.json).
// - Starten (F9 ohne laufende Sitzung, Befehl, Fenster): erst baut Atlas die
//   Projekte, die die IDE als geändert meldet (ShouldBuild), dann startet es
//   sie in Reihenfolge, ein Schritt je Takt (cTickMs): mit Debugger über
//   IOTADebuggerServices.CreateProcess (Parameter aus dem Startprofil bzw. den
//   Startoptionen des Projekts), ohne über CreateProcess von Windows (auch mit
//   Arbeitsordner und Umgebung). Danach die Wartebedingung
//   (TAtlasIdeLaunchProbe im Hintergrund, abgelaufen nach Timeout).
// - Scheitert ein Schritt, hält der Lauf an; eine Rückfrage bietet „Trotzdem
//   weiter“ und „Alle beenden“. Eine Leiste (TAtlasStepsBar) zeigt den Lauf.
// - Strg+F2 bzw. „Startverbund beenden“: alle Programme des Verbunds enden
//   (Debugger: IOTAProcess.Terminate, sonst TerminateProcess).
// - Statusfeld: je Programm „läuft“, „angehalten“ oder „beendet“; ein Klick
//   macht den nächsten Prozess des Verbunds zum aktuellen der IDE. Beim Halt
//   nennt die Meldung den Prozess.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.Core.Debug.DialogCompletion,
  Atlas.Core.Debug.LaunchGroups,
  Atlas.Core.Debug.LaunchProcesses,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.LaunchProbe,
  Atlas.UI.Debug.StepsBar;

type
  /// <summary>Aktiver Verbund je Projektgruppe, persönlich gespeichert.</summary>
  TAtlasIdeLaunchActive = class
  public const
    cFileName = 'debug-launchgroups.json';
  private class var
    FStore: TAtlasExpressionHistory;
    FKept: Boolean;
    class function Store: TAtlasExpressionHistory; static;
    class function GroupKey: string; static;
  public
    /// <summary>Name des aktiven Verbunds der Projektgruppe ('' = keiner).</summary>
    class function Name: string; static;
    class procedure SetName(const AName: string); static;
    class procedure Release; static;
  end;

  TAtlasIdeLaunchGroups = class
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    THandler = class
    public
      procedure Tick(Sender: TObject);
    end;
    /// <summary>Gestartetes Programm des Verbunds.</summary>
  private class var
    FListener: IAtlasIdeDebugListener;
    FHandler: THandler;
    FTimer: TTimer;
    FMessage: TProc<string>;
    FRegistry: IAtlasStatusRegistry;
    FStatus: IAtlasStatusItem;
    FStatusText: string;
    FRun: TAtlasLaunchRun;
    FFolder: string;
    FProbe: TAtlasIdeLaunchProbe;
    FBar: TAtlasStepsBar;
    FStarted: TAtlasLaunchStartedList;
    FKnown: TArray<Cardinal>;
    FDoneAt: UInt64;
    FAsking: Boolean;
    class procedure Say(const AText: string); static;
    class function BuildChanged(const AGroup: TAtlasLaunchGroup): Boolean; static;
    class procedure Tick; static;
    class procedure StartItem(AIndex: Integer); static;
    class procedure TrackPid; static;
    class procedure Fail(const AText: string); static;
    class procedure AskOnFailure; static;
    class procedure FinishRun; static;
    class procedure ShowBar; static;
    class procedure FreeProbe; static;
    class procedure UpdateStatus; static;
    class procedure SwitchProcess; static;
    class function AnyRunning: Boolean; static;
  public
    class procedure Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ThemeChanged; static;
    /// <summary>Verbünde der Projektdatei; AProblems nennt übergangene Einträge.</summary>
    class function Groups(out AProblems: TArray<string>): TAtlasLaunchGroupList; static;
    /// <summary>Befehl Atlas.LaunchGroups: Fenster „Startverbünde“.</summary>
    class procedure ShowWindow; static;
    /// <summary>Befehl Atlas.LaunchGroupRun: aktiven Verbund starten.</summary>
    class procedure RunActive; static;
    /// <summary>Verbund AName starten.</summary>
    class procedure RunGroup(const AName: string); static;
    /// <summary>Befehl Atlas.LaunchGroupStop: alle Programme des Verbunds beenden.</summary>
    class procedure StopAll; static;
    /// <summary>F9: ohne laufende Sitzung und mit aktivem Verbund diesen starten; False = die IDE startet.</summary>
    class function TryRun: Boolean; static;
    /// <summary>Strg+F2: laufen Programme des Verbunds, alle beenden; False = die IDE beendet.</summary>
    class function TryStop: Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Status.Registry,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.StartProfiles.Store,
  Atlas.Core.Debug.Reattach,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.StartOptions,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Debug.Processes,
  Atlas.UI.Debug.LaunchGroupsDialog,
  Atlas.UI.Debug.Strings;

const
  cActiveWhat = 'debug launch groups';
  cStatusId = 'atlas.debug.launchGroups';
  cStatusOrder = 87;
  /// <summary>Takt des Laufs.</summary>
  cTickMs = 100;
  /// <summary>So lange bleibt die Leiste nach dem Ende stehen.</summary>
  cDoneMs = 3000;
  cDoneMark = '✓';
  cFailedMark = '✗';

function ActiveFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasIdeLaunchActive.cFileName);
end;

function Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
  begin
    Result := nil;
  end;
end;

function NowMs: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

/// <summary>Prozess des Debuggers mit Kennung APid oder nil.</summary>
function DebuggedProcess(APid: Cardinal): IOTAProcess;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
begin
  Result := nil;
  mServices := Debugger;
  if (mServices = nil) or (APid = 0) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ProcessCount - 1 do
  begin
    if mServices.Processes[mIndex].ProcessId = APid then
    begin
      Exit(mServices.Processes[mIndex]);
    end;
  end;
end;

/// <summary>Projektdatei von AItem ab dem Ordner AFolder der Projektdatei .atlas.</summary>
function ProjectPath(const AFolder: string; const AItem: TAtlasLaunchItem): string;
begin
  Result := TAtlasTeamFile.Combine(AFolder, StringReplace(AItem.Project, '/', '\', [rfReplaceAll]));
end;

/// <summary>Parameter, Arbeitsordner und Umgebung aus dem Startprofil bzw. den Startoptionen.</summary>
function StartArguments(const AItem: TAtlasLaunchItem; const AProject: string;
  out AWorkingDir: string; out AEnvironment: string): string;
var
  mEntry: TAtlasStartProfileEntry;
  mOptions: TAtlasStartOptions;
  mProject: IOTAProject;
begin
  mOptions := Default(TAtlasStartOptions);
  if (AItem.Profile <> '') and TAtlasStartProfiles.Find(TAtlasStartProfiles.ForProject(TAtlasIdeStartOptions.Folder,
    AProject, TAtlasIdeTeamFile.ForProject(AProject)), AItem.Profile, mEntry) then
  begin
    mOptions := TAtlasStartProfiles.OptionsOf(mEntry);
  end
  else
  begin
    mProject := TAtlasIdeStartOptions.FindProject(AProject);
    if mProject <> nil then
    begin
      TAtlasIdeStartOptions.ReadOptions(mProject, mOptions);
    end;
  end;
  AWorkingDir := mOptions.WorkingDir;
  AEnvironment := mOptions.Environment;
  Result := mOptions.Parameters;
end;

{ TAtlasIdeLaunchActive }

class function TAtlasIdeLaunchActive.Store: TAtlasExpressionHistory;
begin
  if FStore = nil then
  begin
    FStore := TAtlasExpressionHistory.Create(1);
    FKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(ActiveFile, cActiveWhat,
      function(const AText: string): Boolean
      begin
        Result := FStore.LoadFromText(AText);
      end));
  end;
  Result := FStore;
end;

class function TAtlasIdeLaunchActive.GroupKey: string;
var
  mModules: IOTAModuleServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.MainProjectGroup <> nil) then
  begin
    Result := mModules.MainProjectGroup.FileName;
  end;
end;

class function TAtlasIdeLaunchActive.Name: string;
var
  mItems: TArray<string>;
begin
  Result := '';
  mItems := Store.Items(GroupKey);
  if mItems <> nil then
  begin
    Result := mItems[0];
  end;
end;

class procedure TAtlasIdeLaunchActive.SetName(const AName: string);
var
  mChanged: Boolean;
begin
  if AName = '' then
  begin
    mChanged := Store.Remove(GroupKey, Name);
  end
  else
  begin
    mChanged := Store.Add(GroupKey, AName);
  end;
  if not mChanged or FKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(ActiveFile, FStore.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cActiveWhat, E);
  end;
end;

class procedure TAtlasIdeLaunchActive.Release;
begin
  FreeAndNil(FStore);
  FKept := False;
end;

{ TAtlasIdeLaunchGroups.TListener }

procedure TAtlasIdeLaunchGroups.TListener.DebugStopped(AStop: TAtlasDebugStop);
var
  mProcess: IOTAProcess;
  mStarted: TAtlasLaunchStarted;
begin
  TAtlasIdeLaunchGroups.UpdateStatus;
  mProcess := TAtlasIdeDebugSession.Process;
  // Beim Halt nennt die Meldung den Prozess des Verbunds.
  if (mProcess <> nil) and TAtlasLaunchProcesses.FindDebugged(FStarted, mProcess.ProcessId, mStarted) then
  begin
    TAtlasIdeLaunchGroups.Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchStoppedAt,
      [mStarted.Caption, mStarted.Pid]));
  end;
end;

procedure TAtlasIdeLaunchGroups.TListener.DebugResumed;
begin
  TAtlasIdeLaunchGroups.UpdateStatus;
end;

procedure TAtlasIdeLaunchGroups.TListener.DebugEnded;
begin
  TAtlasIdeLaunchGroups.UpdateStatus;
end;

{ TAtlasIdeLaunchGroups.THandler }

procedure TAtlasIdeLaunchGroups.THandler.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeLaunchGroups.Tick);
end;

{ TAtlasIdeLaunchGroups }

class procedure TAtlasIdeLaunchGroups.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeLaunchGroups.BuildChanged(const AGroup: TAtlasLaunchGroup): Boolean;
var
  mItem: TAtlasLaunchItem;
  mProject: IOTAProject;
begin
  for mItem in AGroup.Items do
  begin
    mProject := TAtlasIdeStartOptions.FindProject(ProjectPath(FFolder, mItem));
    if mProject = nil then
    begin
      Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchNotInGroup, [mItem.Caption]));
      Exit(False);
    end;
    if (mProject.ProjectBuilder <> nil) and mProject.ProjectBuilder.ShouldBuild and
      not mProject.ProjectBuilder.BuildProject(cmOTAMake, True, True) then
    begin
      Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchBuildFailed, [mItem.Caption]));
      Exit(False);
    end;
  end;
  Result := True;
end;

class procedure TAtlasIdeLaunchGroups.Tick;
var
  mIndex: Integer;
  mWaitingBefore: Boolean;
begin
  if (FRun = nil) or FAsking then
  begin
    UpdateStatus;
    Exit;
  end;
  TrackPid;
  mWaitingBefore := (FRun.Current >= 0) and (FRun.State(FRun.Current) = TAtlasLaunchItemState.Waiting);
  if mWaitingBefore and (FProbe <> nil) then
  begin
    FRun.Check(NowMs, FProbe.PortOpen, FProbe.WindowFound);
  end
  else if mWaitingBefore then
  begin
    FRun.Check(NowMs, False, False);
  end;
  if FRun.Halted then
  begin
    FreeProbe;
    if mWaitingBefore then
    begin
      Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchTimedOut, [FRun.Group.Items[FRun.Current].Caption]));
    end;
    AskOnFailure;
    Exit;
  end;
  if FRun.Advance(NowMs, mIndex) then
  begin
    FreeProbe;
    StartItem(mIndex);
  end;
  ShowBar;
  UpdateStatus;
  if FRun.Finished then
  begin
    FinishRun;
  end;
end;

class procedure TAtlasIdeLaunchGroups.StartItem(AIndex: Integer);
var
  mItem: TAtlasLaunchItem;
  mProject: IOTAProject;
  mStarted: TAtlasLaunchStarted;
  mArgs, mDir, mEnvironment: string;
  mPort: Integer;
begin
  mItem := FRun.Group.Items[AIndex];
  mProject := TAtlasIdeStartOptions.FindProject(ProjectPath(FFolder, mItem));
  mStarted := Default(TAtlasLaunchStarted);
  mStarted.Caption := mItem.Caption;
  mStarted.Debug := mItem.Debug;
  if (mProject <> nil) and (mProject.ProjectOptions <> nil) then
  begin
    mStarted.Exe := mProject.ProjectOptions.TargetName;
  end;
  if (mStarted.Exe = '') or not FileExists(mStarted.Exe) then
  begin
    Fail(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchStartFailed, [mItem.Caption]));
    Exit;
  end;
  mArgs := StartArguments(mItem, ProjectPath(FFolder, mItem), mDir, mEnvironment);
  if mItem.Debug then
  begin
    // Die Kennung kennt erst die Prozessliste: neuer Prozess mit diesem Pfad (TrackPid).
    FKnown := TAtlasReattach.Pids(TAtlasIdeDebugProcesses.Named(TAtlasReattach.NameOf(mStarted.Exe), False));
    Debugger.CreateProcess(mStarted.Exe, mArgs);
  end
  else
  begin
    mStarted.Pid := TAtlasIdeLaunchProcesses.Start(mStarted.Exe, mArgs, mDir,
      TAtlasStartProfiles.DecodeEnvironment(mEnvironment));
    if mStarted.Pid = 0 then
    begin
      Fail(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchStartFailed, [mItem.Caption]));
      Exit;
    end;
  end;
  FStarted := FStarted + [mStarted];
  if TAtlasLaunchProcesses.NeedsProbe(mItem, mPort) then
  begin
    FProbe := TAtlasIdeLaunchProbe.Create(mPort, mStarted.Pid);
  end;
  FRun.Launched(NowMs);
end;

class procedure TAtlasIdeLaunchGroups.TrackPid;
var
  mProcess: TAtlasReattachProcess;
  mLast: Integer;
begin
  mLast := High(FStarted);
  if (mLast < 0) or (FStarted[mLast].Pid <> 0) then
  begin
    Exit;
  end;
  if TAtlasReattach.Arrival(FStarted[mLast].Exe, TAtlasIdeDebugProcesses.Named(
    TAtlasReattach.NameOf(FStarted[mLast].Exe), False), FKnown, mProcess) then
  begin
    FStarted[mLast].Pid := mProcess.Pid;
    if FProbe <> nil then
    begin
      FProbe.SetPid(mProcess.Pid);
    end;
  end;
end;

class procedure TAtlasIdeLaunchGroups.Fail(const AText: string);
begin
  Say(AText);
  FRun.Fail;
  ShowBar;
end;

class procedure TAtlasIdeLaunchGroups.AskOnFailure;
var
  mDialog: TTaskDialog;
  mButton: TTaskDialogBaseButtonItem;
  mContinue: Boolean;
begin
  ShowBar;
  FAsking := True;
  mDialog := TTaskDialog.Create(nil);
  try
    mDialog.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchTitle, [FRun.Group.Name]);
    mDialog.Title := mDialog.Caption;
    mDialog.Text := FRun.Text(Default(TAtlasLaunchTexts));
    mDialog.CommonButtons := [];
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchContinue);
    mButton.ModalResult := mrRetry;
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchStopAll);
    mButton.ModalResult := mrAbort;
    mContinue := mDialog.Execute and (mDialog.ModalResult = mrRetry);
  finally
    mDialog.Free;
    FAsking := False;
  end;
  if FRun = nil then
  begin
    Exit;
  end;
  if mContinue then
  begin
    FRun.Proceed;
    Exit;
  end;
  StopAll;
end;

class procedure TAtlasIdeLaunchGroups.FinishRun;
begin
  if not TAtlasLaunchProcesses.DoneLongEnough(FDoneAt, NowMs, cDoneMs) then
  begin
    Exit;
  end;
  FreeAndNil(FRun);
  if FBar <> nil then
  begin
    FBar.Dismiss;
  end;
  // Weiter je Takt nur für das Statusfeld, solange Programme des Verbunds laufen.
  FTimer.Enabled := AnyRunning;
end;

class procedure TAtlasIdeLaunchGroups.ShowBar;
var
  mTexts: TAtlasLaunchTexts;
begin
  if FRun = nil then
  begin
    Exit;
  end;
  if FBar = nil then
  begin
    FBar := TAtlasStepsBar.Create(nil);
  end;
  FBar.Colors := TAtlasIdeStyle.Colors;
  mTexts.Done := cDoneMark;
  mTexts.Failed := cFailedMark;
  mTexts.Starting := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchStarting);
  mTexts.Waiting := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchWaiting);
  FBar.ShowSteps(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchTitle, [FRun.Group.Name]), FRun.Text(mTexts),
    TAtlasStepsBar.ActiveCorner);
end;

class procedure TAtlasIdeLaunchGroups.FreeProbe;
begin
  // Free wartet auf das Ende des Threads; Terminate weckt ihn sofort.
  FreeAndNil(FProbe);
end;

/// <summary>Zustand eines gestarteten Programms: mit Debugger über den Prozess der IDE, sonst über Windows.</summary>
function StartedState(const AStarted: TAtlasLaunchStarted): TAtlasLaunchProcessState;
var
  mProcess: IOTAProcess;
begin
  if not AStarted.Debug then
  begin
    Exit(TAtlasLaunchProcesses.StateOf(TAtlasIdeLaunchProcesses.Running(AStarted.Pid), False));
  end;
  mProcess := DebuggedProcess(AStarted.Pid);
  Result := TAtlasLaunchProcesses.StateOf(mProcess <> nil, (mProcess <> nil) and
    (mProcess.ProcessState in [psStopped, psFault, psResFault, psException]));
end;

/// <summary>Zustände aller gestarteten Programme in ihrer Reihenfolge.</summary>
function StartedStates: TArray<TAtlasLaunchProcessState>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(TAtlasIdeLaunchGroups.FStarted));
  for mIndex := 0 to High(TAtlasIdeLaunchGroups.FStarted) do
  begin
    Result[mIndex] := StartedState(TAtlasIdeLaunchGroups.FStarted[mIndex]);
  end;
end;

class procedure TAtlasIdeLaunchGroups.UpdateStatus;
var
  mTexts: TAtlasLaunchStateTexts;
  mText: string;
  mLine: TAtlasStatusLine;
begin
  if FRegistry = nil then
  begin
    Exit;
  end;
  mTexts.Running := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchStateRunning);
  mTexts.Paused := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchStatePaused);
  mTexts.Ended := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchStateEnded);
  mText := TAtlasLaunchProcesses.StatusText(FStarted, StartedStates, mTexts);
  if (mText = FStatusText) and ((FStatus <> nil) = (mText <> '')) then
  begin
    Exit;
  end;
  FStatusText := mText;
  if FStatus <> nil then
  begin
    FRegistry.Remove(cStatusId);
    FStatus := nil;
  end;
  if (mText = '') or not AnyRunning then
  begin
    Exit;
  end;
  mLine := TAtlasStatusLine.Create(FRegistry, cStatusId, cStatusOrder,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeLaunchGroups.SwitchProcess);
    end);
  FStatus := mLine;
  mLine.Update(mText, TAtlasStatusState.Neutral, mText);
  FRegistry.Add(FStatus);
end;

class procedure TAtlasIdeLaunchGroups.SwitchProcess;
var
  mServices: IOTADebuggerServices;
  mCurrent: IOTAProcess;
  mIndex: Integer;
  mCandidates: TArray<IOTAProcess>;
  mPids: TArray<Cardinal>;
  mStarted: TAtlasLaunchStarted;
  mProcess: IOTAProcess;
  mCurrentPid: Cardinal;
begin
  mServices := Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  mCandidates := nil;
  for mStarted in FStarted do
  begin
    mProcess := DebuggedProcess(mStarted.Pid);
    if mStarted.Debug and (mProcess <> nil) then
    begin
      mCandidates := mCandidates + [mProcess];
    end;
  end;
  if mCandidates = nil then
  begin
    Exit;
  end;
  // Nächster Prozess des Verbunds nach dem aktuellen der IDE.
  SetLength(mPids, Length(mCandidates));
  for mIndex := 0 to High(mCandidates) do
  begin
    mPids[mIndex] := mCandidates[mIndex].ProcessId;
  end;
  mCurrent := mServices.CurrentProcess;
  mCurrentPid := 0;
  if mCurrent <> nil then
  begin
    mCurrentPid := mCurrent.ProcessId;
  end;
  mServices.CurrentProcess := mCandidates[TAtlasLaunchProcesses.NextIndex(mPids, mCurrentPid)];
  UpdateStatus;
end;

class function TAtlasIdeLaunchGroups.AnyRunning: Boolean;
begin
  Result := TAtlasLaunchProcesses.AnyRunning(StartedStates);
end;

class procedure TAtlasIdeLaunchGroups.Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry);
begin
  FMessage := AMessage;
  FRegistry := ARegistry;
  if FHandler = nil then
  begin
    FHandler := THandler.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cTickMs;
    FTimer.OnTimer := FHandler.Tick;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeLaunchGroups.Release;
begin
  // Regel 3 der Module: Thread, Zeitgeber, Leiste und Statusfeld gehen mit.
  FreeProbe;
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  if (FRegistry <> nil) and (FStatus <> nil) then
  begin
    FRegistry.Remove(cStatusId);
  end;
  FStatus := nil;
  FStatusText := '';
  FRegistry := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FHandler);
  FreeAndNil(FBar);
  FreeAndNil(FRun);
  TAtlasIdeLaunchActive.Release;
  FMessage := nil;
  FStarted := nil;
  FKnown := nil;
  FFolder := '';
end;

class function TAtlasIdeLaunchGroups.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeLaunchGroups.ThemeChanged;
begin
  if (FBar <> nil) and FBar.IsShown then
  begin
    FBar.Colors := TAtlasIdeStyle.Colors;
    FBar.Invalidate;
  end;
end;

class function TAtlasIdeLaunchGroups.Groups(out AProblems: TArray<string>): TAtlasLaunchGroupList;
var
  mTeam: TAtlasTeamSettings;
begin
  mTeam := TAtlasIdeTeamFile.Current;
  FFolder := mTeam.Folder;
  Result := TAtlasLaunchGroups.Parse(mTeam.LaunchGroups, AProblems);
end;

class procedure TAtlasIdeLaunchGroups.ShowWindow;
var
  mProblems: TArray<string>;
  mGroups: TAtlasLaunchGroupList;
  mChosen: string;
begin
  mGroups := Groups(mProblems);
  if mProblems <> nil then
  begin
    Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchProblems, [string.Join(', ', mProblems)]));
  end;
  case TAtlasLaunchGroupsDialog.Execute(mGroups, TAtlasIdeLaunchActive.Name, mChosen) of
    TAtlasLaunchGroupsChoice.Activate:
      TAtlasIdeLaunchActive.SetName(mChosen);
    TAtlasLaunchGroupsChoice.Start:
      begin
        TAtlasIdeLaunchActive.SetName(mChosen);
        RunGroup(mChosen);
      end;
    TAtlasLaunchGroupsChoice.Edit:
      TAtlasIdeTeamFile.OpenInEditor;
  end;
end;

class procedure TAtlasIdeLaunchGroups.RunActive;
begin
  if TAtlasIdeLaunchActive.Name = '' then
  begin
    Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchNoActive));
    Exit;
  end;
  RunGroup(TAtlasIdeLaunchActive.Name);
end;

class procedure TAtlasIdeLaunchGroups.RunGroup(const AName: string);
var
  mProblems: TArray<string>;
  mGroups: TAtlasLaunchGroupList;
  mIndex: Integer;
begin
  mGroups := Groups(mProblems);
  mIndex := TAtlasLaunchGroups.IndexOf(mGroups, AName);
  if mIndex < 0 then
  begin
    Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchNoActive));
    Exit;
  end;
  if (FRun <> nil) and not FRun.Finished then
  begin
    Exit;
  end;
  FreeProbe;
  FreeAndNil(FRun);
  FStarted := nil;
  if not BuildChanged(mGroups[mIndex]) then
  begin
    Exit;
  end;
  FRun := TAtlasLaunchRun.Create(mGroups[mIndex]);
  FDoneAt := 0;
  FTimer.Enabled := True;
  ShowBar;
end;

class procedure TAtlasIdeLaunchGroups.StopAll;
var
  mStarted: TAtlasLaunchStarted;
  mProcess: IOTAProcess;
begin
  if FRun <> nil then
  begin
    FRun.Cancel;
  end;
  FreeProbe;
  for mStarted in FStarted do
  begin
    if mStarted.Debug then
    begin
      mProcess := DebuggedProcess(mStarted.Pid);
      if mProcess <> nil then
      begin
        mProcess.Terminate;
      end;
    end
    else if mStarted.Pid <> 0 then
    begin
      TAtlasIdeLaunchProcesses.Kill(mStarted.Pid);
    end;
  end;
  ShowBar;
  UpdateStatus;
end;

class function TAtlasIdeLaunchGroups.TryRun: Boolean;
begin
  Result := Started and TAtlasIdeSettings.Current.DebugLaunchGroups and not TAtlasIdeDebugSession.Active and
    (TAtlasIdeLaunchActive.Name <> '');
  if Result then
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeLaunchGroups.RunActive);
  end;
end;

class function TAtlasIdeLaunchGroups.TryStop: Boolean;
begin
  Result := Started and TAtlasIdeSettings.Current.DebugLaunchGroups and AnyRunning;
  if Result then
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeLaunchGroups.StopAll);
  end;
end;

end.
