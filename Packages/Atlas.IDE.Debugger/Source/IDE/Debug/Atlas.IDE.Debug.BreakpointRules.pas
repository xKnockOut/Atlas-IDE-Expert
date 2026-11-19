unit Atlas.IDE.Debug.BreakpointRules;

// Abhängige Haltepunkte und Trefferbedingungen (#864) im Debugger der IDE:
// - Befehl „Haltepunkt-Regeln …“ (Kontextmenü des Editors unter Atlas ›
//   Debuggen, Menü Atlas, Befehlspalette) für den Haltepunkt an der
//   Cursorzeile bzw. der angeklickten Randzeile.
// - Start der Sitzung: Zählung und Scharfschaltung beginnen neu; abhängige
//   Haltepunkte schaltet Atlas aus. Fehlt der auslösende Haltepunkt, bleibt
//   der abhängige normal an (Zeile in den Meldungen).
// - Halt: Steht der Prozess an einem Auslöser, schaltet Atlas die abhängigen
//   ein. Steht er an einem Haltepunkt mit Regel, entscheidet
//   TAtlasBreakpointRules.Decide; „weiter“ setzt sofort fort (ormRun), „nur
//   einmal“ schaltet den Haltepunkt nach dem Halt wieder aus.
// - Aufrufer (#2548): Nennt die Regel einen Aufrufer, liest Atlas beim Halt
//   den Aufrufstapel (TAtlasIdeDebugSession.ReadStack). Ist er nicht lesbar,
//   hält Atlas lieber an, als einen Halt zu verschlucken. Nach cCallerSkipWarn
//   übergangenen Halten in einer Sitzung steht einmal ein Hinweis auf die
//   Laufzeit in den Meldungen.
// - Ende der Sitzung: abhängige Haltepunkte wieder an, wie der Benutzer sie
//   gesetzt hat.
// - Regeln liegen in %LOCALAPPDATA%\Atlas\breakpoint-rules.json und ziehen
//   mit, wenn #841 einen Haltepunkt verschiebt (Moved).
// Ein Teil der Feature-Tabelle. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Debug.BreakpointRules,
  Atlas.IDE.Debug.Session,
  Atlas.Core.Notifications.MessageSink;

type
  TAtlasIdeBreakpointRules = class
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
  private const
    cStateFile = 'breakpoint-rules.json';
    cCallerSkipWarn = 1000;
  private class var
    /// <summary>Halte der Sitzung, die eine Aufrufer-Bedingung übergangen hat.</summary>
    FCallerSkips: Integer;
    FListener: IAtlasIdeDebugListener;
    FMessage: TAtlasMessageSink;
    FRules: TAtlasBreakpointRuleList;
    FStates: TDictionary<string, TAtlasRuleState>;
    class function StateFile: string; static;
    class procedure Load; static;
    class procedure Save; static;
    class function StateOf(const ARule: TAtlasBreakpointRule): TAtlasRuleState; static;
    class procedure SetState(const ARule: TAtlasBreakpointRule; const AState: TAtlasRuleState); static;
    class procedure SetEnabled(const ARule: TAtlasBreakpointRule; AEnabled: Boolean); static;
    class function PlaceText(const AFileName: string; ALine: Integer): string; static;
    class function StopThread(const AProcess: IOTAProcess; const AThread: IOTAThread): TAtlasStopThread; static;
    class procedure SessionStarted; static;
    class procedure Stopped; static;
    class procedure ArmTriggered(const AFileName: string; ALine: Integer); static;
    class function DecideHere(const AFileName: string; ALine: Integer; const AProcess: IOTAProcess;
      const AThread: IOTAThread): TAtlasRuleDecision; static;
    /// <summary>Routinen des Stapels von AThread (die des Halts zuerst); False, wenn er nicht lesbar ist.
    /// </summary>
    class function ReadRoutines(const AThread: IOTAThread; out ARoutines: TArray<string>): Boolean; static;
    class procedure CountCallerSkip(const ARule: TAtlasBreakpointRule); static;
    class procedure SessionEnded; static;
  public
    /// <summary>Teil starten: Zuhörer der Debug-Sitzung, Regeln laden. AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.breakpointRules an und Teil gestartet?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Befehl „Haltepunkt-Regeln …“.</summary>
    class procedure Edit; static;
    /// <summary>Haltepunkt verschoben (#841): Regeln ziehen mit.</summary>
    class procedure Moved(const AFileName: string; AFromLine, AToLine: Integer); static;
    /// <summary>Regel des Haltepunkts an AFileName/ALine (ab 0); False ohne (für das Haltepunktfenster #863).
    /// </summary>
    class function RuleAt(const AFileName: string; ALine: Integer; out ARule: TAtlasBreakpointRule): Boolean;
      static;
    /// <summary>Hat eine Regel in AFileName einen Aufrufer (Rinne, #2548)?</summary>
    class function HasCallers(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Files.DataFile,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.UI.Debug.BreakpointRules,
  Atlas.UI.Debug.Breakpoints.Strings;

{ TAtlasIdeBreakpointRules.TListener }

procedure TAtlasIdeBreakpointRules.TListener.DebugStarted;
begin
  TAtlasIdeBreakpointRules.SessionStarted;
end;

procedure TAtlasIdeBreakpointRules.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if AStop = TAtlasDebugStop.Paused then
  begin
    TAtlasIdeBreakpointRules.Stopped;
  end;
end;

procedure TAtlasIdeBreakpointRules.TListener.DebugEnded;
begin
  TAtlasIdeBreakpointRules.SessionEnded;
end;

{ TAtlasIdeBreakpointRules }

class function TAtlasIdeBreakpointRules.StateFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cStateFile);
end;

class procedure TAtlasIdeBreakpointRules.Load;
var
  mText: string;
begin
  if not (TAtlasDataFile.TryRead(StateFile, mText) and TAtlasBreakpointRules.Parse(mText, FRules)) then
  begin
    FRules := nil;
  end;
end;

class procedure TAtlasIdeBreakpointRules.Save;
begin
  try
    ForceDirectories(ExtractFileDir(StateFile));
    TAtlasDataFile.Write(StateFile, TAtlasBreakpointRules.ToJson(FRules));
  except
    // Ohne Datei gelten die Regeln nur bis zum Neustart.
    on E: Exception do
      FMessage.Say(E.Message);
  end;
end;

class function TAtlasIdeBreakpointRules.StateOf(const ARule: TAtlasBreakpointRule): TAtlasRuleState;
begin
  if not FStates.TryGetValue(TAtlasBreakpointRules.Key(ARule.FileName, ARule.Line), Result) then
  begin
    Result := TAtlasRuleState.Start(ARule);
  end;
end;

class procedure TAtlasIdeBreakpointRules.SetState(const ARule: TAtlasBreakpointRule; const AState: TAtlasRuleState);
begin
  FStates.AddOrSetValue(TAtlasBreakpointRules.Key(ARule.FileName, ARule.Line), AState);
end;

class procedure TAtlasIdeBreakpointRules.SetEnabled(const ARule: TAtlasBreakpointRule; AEnabled: Boolean);
var
  mBreakpoint: IOTABreakpoint;
begin
  mBreakpoint := TAtlasIdeBreakpoints.Find(ARule.FileName, ARule.Line);
  if (mBreakpoint <> nil) and (mBreakpoint.Enabled <> AEnabled) then
  begin
    mBreakpoint.Enabled := AEnabled;
  end;
end;

class function TAtlasIdeBreakpointRules.PlaceText(const AFileName: string; ALine: Integer): string;
begin
  Result := TAtlasBreakpointRuleDialog.TriggerText(TAtlasRuleTrigger.Create(AFileName, ALine));
end;

class function TAtlasIdeBreakpointRules.StopThread(const AProcess: IOTAProcess;
  const AThread: IOTAThread): TAtlasStopThread;
var
  mMainId: Cardinal;
begin
  mMainId := 0;
  // Der erste Thread des Prozesses ist der Hauptthread.
  if AProcess.ThreadCount > 0 then
  begin
    mMainId := AProcess.Threads[0].GetOSThreadID;
  end;
  Result := TAtlasStopThread.Create(TAtlasIdeDebugSession.ThreadName(AThread), AThread.GetOSThreadID, mMainId);
end;

class procedure TAtlasIdeBreakpointRules.SessionStarted;
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
begin
  FStates.Clear;
  FCallerSkips := 0;
  if not Enabled then
  begin
    Exit;
  end;
  for mRule in FRules do
  begin
    mState := TAtlasRuleState.Start(mRule);
    if mRule.HasTrigger and (TAtlasIdeBreakpoints.Find(mRule.TriggerFile, mRule.TriggerLine) = nil) then
    begin
      FMessage.Say(TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesTriggerMissing,
        [PlaceText(mRule.FileName, mRule.Line), PlaceText(mRule.TriggerFile, mRule.TriggerLine)]));
      mState.Armed := True;
    end;
    SetState(mRule, mState);
    SetEnabled(mRule, TAtlasBreakpointRules.ShouldBeEnabled(mRule, mState));
  end;
end;

class procedure TAtlasIdeBreakpointRules.Stopped;
var
  mProcess: IOTAProcess;
  mThread: IOTAThread;
  mFileName: string;
  mLine: Integer;
begin
  mProcess := TAtlasIdeDebugSession.Process;
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if not Enabled or (FRules = nil) or (mProcess = nil) or
    not TAtlasIdeBreakpoints.Position(mThread, mFileName, mLine) then
  begin
    Exit;
  end;
  // Erst die eigene Regel (ein Auslöser kann selbst Regeln haben), dann die abhängigen scharf schalten.
  if DecideHere(mFileName, mLine, mProcess, mThread) = TAtlasRuleDecision.Continue then
  begin
    ArmTriggered(mFileName, mLine);
    mProcess.Run(ormRun);
    Exit;
  end;
  ArmTriggered(mFileName, mLine);
end;

class procedure TAtlasIdeBreakpointRules.ArmTriggered(const AFileName: string; ALine: Integer);
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
begin
  for mRule in FRules do
  begin
    if not mRule.TriggeredBy(AFileName, ALine) then
    begin
      Continue;
    end;
    mState := StateOf(mRule);
    if TAtlasBreakpointRules.Arm(mRule, mState) then
    begin
      FMessage.Say(TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesArmed,
        [PlaceText(mRule.FileName, mRule.Line), PlaceText(AFileName, ALine)]));
    end;
    SetState(mRule, mState);
    SetEnabled(mRule, True);
  end;
end;

class function TAtlasIdeBreakpointRules.ReadRoutines(const AThread: IOTAThread;
  out ARoutines: TArray<string>): Boolean;
var
  mFrames: TAtlasDebugFrames;
  mFrame: TAtlasDebugFrame;
begin
  ARoutines := nil;
  Result := TAtlasIdeDebugSession.ReadStack(AThread, TAtlasDebugCallStack.cMaxFrames, mFrames) =
    TAtlasDebugStackRead.Ready;
  for mFrame in mFrames do
  begin
    ARoutines := ARoutines + [mFrame.Routine];
  end;
end;

class procedure TAtlasIdeBreakpointRules.CountCallerSkip(const ARule: TAtlasBreakpointRule);
begin
  Inc(FCallerSkips);
  if FCallerSkips = cCallerSkipWarn then
  begin
    FMessage.Say(TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesCallerSlow,
      [PlaceText(ARule.FileName, ARule.Line), cCallerSkipWarn]));
  end;
end;

class function TAtlasIdeBreakpointRules.DecideHere(const AFileName: string; ALine: Integer;
  const AProcess: IOTAProcess; const AThread: IOTAThread): TAtlasRuleDecision;
var
  mIndex: Integer;
  mState: TAtlasRuleState;
  mStop: TAtlasStopThread;
begin
  Result := TAtlasRuleDecision.Stop;
  mIndex := TAtlasBreakpointRules.IndexOf(FRules, AFileName, ALine);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mStop := StopThread(AProcess, AThread);
  // Stapel nicht lesbar: lieber halten als einen Halt verschlucken.
  if FRules[mIndex].HasCaller and not ReadRoutines(AThread, mStop.Routines) then
  begin
    Exit;
  end;
  mState := StateOf(FRules[mIndex]);
  Result := TAtlasBreakpointRules.Decide(FRules[mIndex], mState, mStop);
  if FRules[mIndex].HasCaller and (Result = TAtlasRuleDecision.Continue) then
  begin
    CountCallerSkip(FRules[mIndex]);
  end;
  SetState(FRules[mIndex], mState);
  SetEnabled(FRules[mIndex], TAtlasBreakpointRules.ShouldBeEnabled(FRules[mIndex], mState));
end;

class procedure TAtlasIdeBreakpointRules.SessionEnded;
var
  mRule: TAtlasBreakpointRule;
begin
  // Abhängige wieder an, wie gesetzt; die Zählung gilt nur je Sitzung.
  for mRule in FRules do
  begin
    if mRule.HasTrigger then
    begin
      SetEnabled(mRule, True);
    end;
  end;
  if FStates <> nil then
  begin
    FStates.Clear;
  end;
end;

class procedure TAtlasIdeBreakpointRules.Start(const AMessage: TProc<string>);
begin
  FMessage := TAtlasMessageSink.Create(AMessage);
  if FListener = nil then
  begin
    FStates := TDictionary<string, TAtlasRuleState>.Create;
    Load;
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
    TAtlasIdeDebugSession.Start;
  end;
end;

class procedure TAtlasIdeBreakpointRules.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
    // Abhängige Haltepunkte nicht ausgeschaltet zurücklassen.
    SessionEnded;
  end;
  FListener := nil;
  FMessage.Clear;
  FRules := nil;
  FreeAndNil(FStates);
end;

class function TAtlasIdeBreakpointRules.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeBreakpointRules.Enabled: Boolean;
begin
  Result := Started and TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.DebugBreakpointRules;
end;

/// <summary>Andere Quelltext-Haltepunkte als mögliche Auslöser.</summary>
function Triggers(const AFileName: string; ALine: Integer): TAtlasRuleTriggers;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mBreakpoint: IOTASourceBreakpoint;
begin
  Result := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint <> nil) and (mBreakpoint.LineNumber > 0) and
      not (SameFileName(mBreakpoint.FileName, AFileName) and (mBreakpoint.LineNumber - 1 = ALine)) then
    begin
      Result := Result + [TAtlasRuleTrigger.Create(mBreakpoint.FileName, mBreakpoint.LineNumber - 1)];
    end;
  end;
end;

/// <summary>Datei und Zeile des Befehls: angeklickte Randzeile, sonst Cursorzeile.</summary>
function TargetLine(out AFileName: string; out ALine: Integer): Boolean;
var
  mView: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil);
  if not Result then
  begin
    Exit;
  end;
  AFileName := mView.Buffer.FileName;
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := mView.CursorPos.Line - 1;
  end;
end;

/// <summary>Vorschläge für den Aufrufer: Routinen des angehaltenen Stapels ohne die oberste.</summary>
function CallerChoices: TArray<string>;
var
  mRoutines: TArray<string>;
begin
  Result := nil;
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    Exit;
  end;
  if TAtlasIdeBreakpointRules.ReadRoutines(TAtlasIdeDebugSession.StoppedThread, mRoutines) and
    (Length(mRoutines) > 1) then
  begin
    Result := Copy(mRoutines, 1, MaxInt);
  end;
end;

class procedure TAtlasIdeBreakpointRules.Edit;
var
  mFileName: string;
  mLine, mIndex: Integer;
  mRule, mChosen: TAtlasBreakpointRule;
begin
  if not TargetLine(mFileName, mLine) then
  begin
    FMessage.Say(TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesNoEditor));
    Exit;
  end;
  if TAtlasIdeBreakpoints.Find(mFileName, mLine) = nil then
  begin
    FMessage.Say(TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesNoBreakpoint, [mLine + 1]));
    Exit;
  end;
  mIndex := TAtlasBreakpointRules.IndexOf(FRules, mFileName, mLine);
  mRule := Default(TAtlasBreakpointRule);
  mRule.FileName := mFileName;
  mRule.Line := mLine;
  if mIndex >= 0 then
  begin
    mRule := FRules[mIndex];
  end;
  if not TAtlasBreakpointRuleDialog.Execute(mRule, Triggers(mFileName, mLine), CallerChoices, mChosen) then
  begin
    Exit;
  end;
  TAtlasBreakpointRules.Put(FRules, mChosen);
  Save;
  TAtlasIdeEditorRefresh.RepaintTop;
  if mChosen.IsEmpty then
  begin
    SetEnabled(mChosen, True);
    FMessage.Say(TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesRemoved, [PlaceText(mFileName,
      mLine)]));
    Exit;
  end;
  FMessage.Say(TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesSaved, [PlaceText(mFileName,
    mLine)]));
end;

class procedure TAtlasIdeBreakpointRules.Moved(const AFileName: string; AFromLine, AToLine: Integer);
begin
  if Started and (FRules <> nil) then
  begin
    TAtlasBreakpointRules.Moved(FRules, AFileName, AFromLine, AToLine);
    Save;
  end;
end;

class function TAtlasIdeBreakpointRules.RuleAt(const AFileName: string; ALine: Integer;
  out ARule: TAtlasBreakpointRule): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TAtlasBreakpointRules.IndexOf(FRules, AFileName, ALine);
  Result := mIndex >= 0;
  if Result then
  begin
    ARule := FRules[mIndex];
  end
  else
  begin
    ARule := Default(TAtlasBreakpointRule);
  end;
end;

class function TAtlasIdeBreakpointRules.HasCallers(const AFileName: string): Boolean;
var
  mRule: TAtlasBreakpointRule;
begin
  for mRule in FRules do
  begin
    if mRule.HasCaller and SameText(mRule.FileName, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
