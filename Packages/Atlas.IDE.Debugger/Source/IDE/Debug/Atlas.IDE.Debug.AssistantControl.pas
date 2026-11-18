unit Atlas.IDE.Debug.AssistantControl;

// Steuerung des Debuggers für KI-Assistenten (#1874): stellt IAtlasDebugControl bereit. Das Modul KI-Assistenten
// nimmt die Aufträge der MCP-Werkzeuge an und fragt den Vertrag über die Registry; den Debugger kennt es nicht.
//   - Launch: Projekt (sonst das aktive) aktiv machen, Konfiguration und Plattform umstellen und „Start“ der IDE
//     auslösen. Eigene Argumente oder ein Test gelten nur für diesen Lauf (TAtlasIdeStartOptions.RunTemporary);
//     am Ende der Sitzung stellt der Hörer sie zurück.
//   - Schritte über TAtlasIdeDebugSession.RunMode, „Bis Zeile“ über TAtlasIdeRunTo (Zeilen dort 0-basiert).
//   - Zustand: Aufrufstapel mit eigenem Code (#578), Exception aus dem Exception-Verlauf (#517), lokale Namen aus
//     dem Fenster Variablen (ohne das Fenster keine), Threads des Prozesses.
//   - Haltepunkte nur in der Gruppe cAtlasDebugControlGroup; die Kennungen vergibt diese Klasse. Haltepunkte des
//     Benutzers fasst sie nie an.
// Nur im Hauptthread verwenden.

interface

uses
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.DebugControl.Types,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Contracts.DebugControl;

type
  TAtlasIdeDebugAssistantControl = class(TInterfacedObject, IAtlasDebugControl)
  private type
    /// <summary>Stellt am Ende der Sitzung vorübergehende Startparameter zurück.</summary>
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugEnded; override;
    end;
  private class var
    /// <summary>Zuletzt aufgenommener Halt wegen einer Exception (für Klasse und Meldung).</summary>
    FLast: TAtlasDebugExceptionStop;
    /// <summary>Projekt mit vorübergehenden Parametern dieses Laufs; '' ohne.</summary>
    FTemporary: string;
    class procedure ExceptionTaken(const AStop: TAtlasDebugExceptionStop); static;
    class procedure EndTemporary; static;
  private
    FHandler: Integer;
    FListener: IAtlasIdeDebugListener;
    FBreakpoints: TDictionary<Integer, IOTABreakpoint>;
    FNextId: Integer;
    /// <summary>Halt vor dem letzten Schritt; -1 ohne Schritt.</summary>
    FStepFrom: Integer;
    function StartProject(const ALaunch: TAtlasDebugControlLaunch; out AReason: string): Boolean;
    function StopReason(const AFileName: string; ALine: Integer): string;
    procedure ReadLocals(var AState: TAtlasDebugControlState);
    procedure ReadThreads(var AState: TAtlasDebugControlState);
  public
    constructor Create;
    destructor Destroy; override;
    function Phase: TAtlasDebugControlPhase;
    function StopCount: Integer;
    function Launch(const ALaunch: TAtlasDebugControlLaunch; out AReason: string): Boolean;
    procedure Terminate;
    function Resume(out AReason: string): Boolean;
    function Step(AKind: TAtlasDebugControlStep; const AFileName: string; ALine: Integer;
      out AReason: string): Boolean;
    function ReadState(AFrames: Integer; ALocals: Boolean; out AState: TAtlasDebugControlState): Boolean;
    function Evaluate(const AExpression: string; ASideEffects: Boolean; out AValue, ATypeName,
      AReason: string): Boolean;
    function AddBreakpoint(const AFileName: string; ALine: Integer; const ACondition: string; APassCount: Integer;
      out ABreakpoint: TAtlasDebugControlBreakpoint; out AReason: string): Boolean;
    function RemoveBreakpoint(AId: Integer): Boolean;
    function RemoveAllBreakpoints: Integer;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.AssistantControl,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.StartOptions,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.RunTo,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Variables,
  Atlas.UI.Debug.Session.Strings;

const
  cRunModes: array[TAtlasDebugControlStep] of TOTARunMode = (ormStmtStepInto, ormStmtStepOver, ormRunUntilReturn,
    ormRun);

{ TAtlasIdeDebugAssistantControl.TListener }

procedure TAtlasIdeDebugAssistantControl.TListener.DebugEnded;
begin
  TAtlasIdeDebugAssistantControl.EndTemporary;
end;

{ TAtlasIdeDebugAssistantControl }

constructor TAtlasIdeDebugAssistantControl.Create;
begin
  inherited Create;
  FLast := Default(TAtlasDebugExceptionStop);
  FBreakpoints := TDictionary<Integer, IOTABreakpoint>.Create;
  FStepFrom := -1;
  FHandler := TAtlasIdeDebugExceptions.AddExceptionHandler(ExceptionTaken);
  FListener := TListener.Create;
  TAtlasIdeDebugSession.AddListener(FListener);
end;

destructor TAtlasIdeDebugAssistantControl.Destroy;
begin
  TAtlasIdeDebugSession.RemoveListener(FListener);
  FListener := nil;
  TAtlasIdeDebugExceptions.RemoveExceptionHandler(FHandler);
  FHandler := 0;
  FLast := Default(TAtlasDebugExceptionStop);
  FreeAndNil(FBreakpoints);
  inherited Destroy;
end;

class procedure TAtlasIdeDebugAssistantControl.ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
begin
  FLast := AStop;
end;

class procedure TAtlasIdeDebugAssistantControl.EndTemporary;
var
  mChanged: Boolean;
begin
  if FTemporary = '' then
  begin
    Exit;
  end;
  TAtlasIdeStartOptions.EndTemporary(FTemporary, mChanged);
  FTemporary := '';
end;

function TAtlasIdeDebugAssistantControl.Phase: TAtlasDebugControlPhase;
begin
  if TAtlasIdeDebugSession.StoppedThread <> nil then
  begin
    Exit(TAtlasDebugControlPhase.Stopped);
  end;
  if TAtlasIdeBreakpoints.CurrentProcess <> nil then
  begin
    Exit(TAtlasDebugControlPhase.Running);
  end;
  Result := TAtlasDebugControlPhase.None;
end;

function TAtlasIdeDebugAssistantControl.StopCount: Integer;
begin
  Result := TAtlasIdeDebugSession.StopCount;
end;

function TAtlasIdeDebugAssistantControl.StartProject(const ALaunch: TAtlasDebugControlLaunch;
  out AReason: string): Boolean;
var
  mProject: IOTAProject;
  mLaunch: TAtlasDebugControlLaunch;
begin
  if ALaunch.Project = '' then
  begin
    mProject := TAtlasIdeStartOptions.ActiveProject;
  end
  else
  begin
    mProject := TAtlasIdeStartOptions.FindProject(ALaunch.Project);
  end;
  if mProject = nil then
  begin
    AReason := TAtlasSessionStrings.Fmt(TAtlasSessionTextId.AssistantNoProject, [ExtractFileName(ALaunch.Project)]);
    Exit(False);
  end;
  // Bleibt nach dem Lauf eingestellt: Der Assistent debuggt, was er gewählt hat, auch beim nächsten Start.
  if (ALaunch.Configuration <> '') and not SameText(mProject.CurrentConfiguration, ALaunch.Configuration) then
  begin
    mProject.CurrentConfiguration := ALaunch.Configuration;
  end;
  if (ALaunch.Platform <> '') and not SameText(mProject.CurrentPlatform, ALaunch.Platform) then
  begin
    mProject.CurrentPlatform := ALaunch.Platform;
  end;
  if not TAtlasDebugAssistantControl.NeedsParameters(ALaunch) then
  begin
    TAtlasIdeStartOptions.MakeActive(mProject);
    Exit(TAtlasIdeStartOptions.Execute(True, AReason));
  end;
  mLaunch := ALaunch;
  Result := TAtlasIdeStartOptions.RunTemporary(mProject.FileName,
    function(AExisting: string): string
    begin
      Result := TAtlasDebugAssistantControl.Parameters(AExisting, mLaunch);
    end, True, AReason);
  if Result then
  begin
    FTemporary := mProject.FileName;
  end;
end;

function TAtlasIdeDebugAssistantControl.Launch(const ALaunch: TAtlasDebugControlLaunch; out AReason: string): Boolean;
begin
  AReason := '';
  if Phase <> TAtlasDebugControlPhase.None then
  begin
    AReason := TAtlasSessionStrings.Text(TAtlasSessionTextId.AssistantRunning);
    Exit(False);
  end;
  FStepFrom := -1;
  Result := StartProject(ALaunch, AReason);
  if not Result then
  begin
    AReason := TAtlasSessionStrings.Fmt(TAtlasSessionTextId.AssistantStartFailed, [AReason]);
  end;
end;

procedure TAtlasIdeDebugAssistantControl.Terminate;
var
  mProcess: IOTAProcess;
begin
  mProcess := TAtlasIdeBreakpoints.CurrentProcess;
  if mProcess <> nil then
  begin
    mProcess.Terminate;
  end;
end;

function TAtlasIdeDebugAssistantControl.Resume(out AReason: string): Boolean;
begin
  AReason := '';
  FStepFrom := -1;
  Result := TAtlasIdeDebugSession.Resume;
  if not Result then
  begin
    AReason := TAtlasSessionStrings.Text(TAtlasSessionTextId.AssistantNotStopped);
  end;
end;

function TAtlasIdeDebugAssistantControl.Step(AKind: TAtlasDebugControlStep; const AFileName: string; ALine: Integer;
  out AReason: string): Boolean;
begin
  AReason := '';
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    AReason := TAtlasSessionStrings.Text(TAtlasSessionTextId.AssistantNotStopped);
    Exit(False);
  end;
  FStepFrom := TAtlasIdeDebugSession.StopCount;
  if AKind <> TAtlasDebugControlStep.ToLine then
  begin
    Result := TAtlasIdeDebugSession.RunMode(cRunModes[AKind]);
    if not Result then
    begin
      AReason := TAtlasSessionStrings.Text(TAtlasSessionTextId.AssistantNotStopped);
    end;
    Exit;
  end;
  if not TAtlasIdeRunTo.Enabled then
  begin
    AReason := TAtlasSessionStrings.Text(TAtlasSessionTextId.AssistantRunToOff);
    Exit(False);
  end;
  if not TAtlasIdeRunTo.CodeLine(AFileName, ALine - 1) then
  begin
    AReason := TAtlasSessionStrings.Fmt(TAtlasSessionTextId.AssistantNoCode, [ALine]);
    Exit(False);
  end;
  TAtlasIdeRunTo.RunToLine(AFileName, ALine - 1, False);
  Result := True;
end;

function TAtlasIdeDebugAssistantControl.StopReason(const AFileName: string; ALine: Integer): string;
var
  mStop: TAtlasDebugAssistantStop;
begin
  mStop := TAtlasDebugAssistantControl.StopOf(FLast.Stop = TAtlasIdeDebugSession.StopCount,
    (AFileName <> '') and (TAtlasIdeBreakpoints.Find(AFileName, ALine - 1) <> nil),
    (FStepFrom >= 0) and (TAtlasIdeDebugSession.StopCount = FStepFrom + 1));
  Result := TAtlasDebugAssistantControl.cStopNames[mStop];
end;

procedure TAtlasIdeDebugAssistantControl.ReadLocals(var AState: TAtlasDebugControlState);
var
  mNames: TArray<string>;
  mIndex: Integer;
  mText: string;
begin
  mNames := TAtlasIdeDebugVariables.Locals;
  SetLength(AState.Locals, Length(mNames));
  for mIndex := 0 to High(mNames) do
  begin
    AState.Locals[mIndex].Name := mNames[mIndex];
    TAtlasIdeDebugEvaluator.Evaluate(mNames[mIndex], TAtlasVisualizerEvaluation.Fields,
      TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs, mText);
    AState.Locals[mIndex].Value := mText;
  end;
end;

procedure TAtlasIdeDebugAssistantControl.ReadThreads(var AState: TAtlasDebugControlState);
var
  mProcess: IOTAProcess;
  mCurrent, mThread: IOTAThread;
  mIndex: Integer;
begin
  mProcess := TAtlasIdeBreakpoints.CurrentProcess;
  if mProcess = nil then
  begin
    Exit;
  end;
  mCurrent := mProcess.CurrentThread;
  SetLength(AState.Threads, mProcess.ThreadCount);
  for mIndex := 0 to mProcess.ThreadCount - 1 do
  begin
    mThread := mProcess.Threads[mIndex];
    AState.Threads[mIndex].Id := mThread.GetOSThreadID;
    AState.Threads[mIndex].Name := TAtlasIdeDebugSession.ThreadName(mThread);
    AState.Threads[mIndex].Current := (mCurrent <> nil) and (mCurrent.GetOSThreadID = mThread.GetOSThreadID);
  end;
end;

function TAtlasIdeDebugAssistantControl.ReadState(AFrames: Integer; ALocals: Boolean;
  out AState: TAtlasDebugControlState): Boolean;
var
  mThread: IOTAThread;
  mFrames: TAtlasDebugFrames;
begin
  AState := Default(TAtlasDebugControlState);
  AState.Phase := Phase;
  Result := True;
  if AState.Phase <> TAtlasDebugControlPhase.Stopped then
  begin
    Exit;
  end;
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if TAtlasIdeDebugSession.ReadStack(mThread, AFrames, mFrames) = TAtlasDebugStackRead.Ready then
  begin
    TAtlasIdeDebugSources.MarkFrames(mFrames);
    AState.Frames := TAtlasDebugAssistantControl.Frames(mFrames, AFrames);
    TAtlasDebugAssistantControl.Location(mFrames, AState.FileName, AState.Line);
  end;
  AState.StopReason := StopReason(AState.FileName, AState.Line);
  if FLast.Stop = TAtlasIdeDebugSession.StopCount then
  begin
    AState.ExceptionClass := FLast.Exception.ExceptionClass;
    AState.ExceptionMessage := FLast.Exception.Message;
  end;
  if ALocals then
  begin
    ReadLocals(AState);
  end;
  ReadThreads(AState);
end;

function TAtlasIdeDebugAssistantControl.Evaluate(const AExpression: string; ASideEffects: Boolean; out AValue,
  ATypeName, AReason: string): Boolean;
var
  mEvaluation: TAtlasVisualizerEvaluation;
begin
  AValue := '';
  ATypeName := '';
  AReason := '';
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    AReason := TAtlasSessionStrings.Text(TAtlasSessionTextId.AssistantNotStopped);
    Exit(False);
  end;
  mEvaluation := TAtlasVisualizerEvaluation.Fields;
  if ASideEffects then
  begin
    mEvaluation := TAtlasVisualizerEvaluation.Properties;
  end;
  Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, mEvaluation,
    TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs, AValue);
  if not Result then
  begin
    AReason := TAtlasSessionStrings.Fmt(TAtlasSessionTextId.AssistantNoValue, [AValue]);
    AValue := '';
  end;
end;

function TAtlasIdeDebugAssistantControl.AddBreakpoint(const AFileName: string; ALine: Integer;
  const ACondition: string; APassCount: Integer; out ABreakpoint: TAtlasDebugControlBreakpoint;
  out AReason: string): Boolean;
var
  mBreakpoint: IOTABreakpoint;
begin
  ABreakpoint := Default(TAtlasDebugControlBreakpoint);
  AReason := '';
  mBreakpoint := TAtlasIdeBreakpoints.Add(AFileName, ALine - 1, cAtlasDebugControlGroup);
  if mBreakpoint = nil then
  begin
    AReason := TAtlasSessionStrings.Fmt(TAtlasSessionTextId.AssistantNoBreakpoint, [ExtractFileName(AFileName), ALine]);
    Exit(False);
  end;
  mBreakpoint.Expression := ACondition;
  mBreakpoint.PassCount := APassCount;
  Inc(FNextId);
  FBreakpoints.Add(FNextId, mBreakpoint);
  ABreakpoint.Id := FNextId;
  ABreakpoint.FileName := AFileName;
  ABreakpoint.Line := ALine;
  ABreakpoint.Valid := TAtlasIdeRunTo.CodeLine(AFileName, ALine - 1);
  Result := True;
end;

function TAtlasIdeDebugAssistantControl.RemoveBreakpoint(AId: Integer): Boolean;
var
  mList: TArray<IOTABreakpoint>;
begin
  Result := FBreakpoints.ContainsKey(AId);
  if not Result then
  begin
    Exit;
  end;
  mList := [FBreakpoints[AId]];
  FBreakpoints.Remove(AId);
  TAtlasIdeBreakpoints.RemoveAll(mList);
end;

function TAtlasIdeDebugAssistantControl.RemoveAllBreakpoints: Integer;
var
  mServices: IOTADebuggerServices;
  mList: TArray<IOTABreakpoint>;
  mIndex: Integer;
  mBreakpoint: IOTASourceBreakpoint;
begin
  // Auch Haltepunkte der Gruppe aus einer früheren Sitzung (etwa vor dem Neuladen des Moduls).
  mList := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices <> nil then
  begin
    for mIndex := 0 to mServices.SourceBkptCount - 1 do
    begin
      mBreakpoint := mServices.SourceBkpts[mIndex];
      if (mBreakpoint <> nil) and SameText(mBreakpoint.GroupName, cAtlasDebugControlGroup) then
      begin
        mList := mList + [IOTABreakpoint(mBreakpoint)];
      end;
    end;
  end;
  FBreakpoints.Clear;
  Result := Length(mList);
  TAtlasIdeBreakpoints.RemoveAll(mList);
end;

end.
