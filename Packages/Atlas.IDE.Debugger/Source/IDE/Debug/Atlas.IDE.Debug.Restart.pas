unit Atlas.IDE.Debug.Restart;

// Neu starten mit einem Griff (#872) in der IDE. Ablauf nach
// TAtlasRestartRun, ein Schritt je Takt (cIntervalMs), damit die IDE
// zwischen Beenden, Bauen und Starten ihre eigenen Ereignisse abarbeitet:
// - Beenden (nur bei laufender Sitzung): IOTAProcess.Terminate ohne
//   Rückfrage; fertig mit dem Ende der Sitzung (TAtlasIdeDebugSession),
//   höchstens cStopMs.
// - Bauen (nur, wenn IOTAProjectBuilder.ShouldBuild): BuildProject(cmOTAMake);
//   ein Fehler bricht ab, die Meldungen der IDE zeigen ihn.
// - Starten: abgeschaltete Haltepunkte wieder an (debug.restart.
//   reenableBreakpoints), dann die Aktion „Start“ der IDE (F9) mit dem
//   aktiven Startprofil (#575); fertig mit dem Start der Sitzung, höchstens
//   cStartMs.
// - Zurück zur Stelle: Datei und Cursor vor dem Neustart.
// Eine Leiste (TAtlasStepsBar) zeigt die Schritte mit Dauer und verschwindet
// cDoneMs nach dem Ende. Läuft kein Programm, startet der Befehl wie F9.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.Restart,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.StepsBar;

type
  TAtlasIdeDebugRestart = class
  public const
    cIntervalMs = 100;
    cStopMs = 10000;
    cStartMs = 60000;
    cDoneMs = 3000;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugEnded; override;
    end;
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FBar: TAtlasStepsBar;
    FMessage: TProc<string>;
    FRun: TAtlasRestartRun;
    /// <summary>Der laufende Schritt ist abgeschlossen; der nächste Takt beginnt den folgenden.</summary>
    FStepDone: Boolean;
    FStepAt: UInt64;
    FDoneAt: UInt64;
    FFileName: string;
    FLine: Integer;
    FColumn: Integer;
    FEnabledAtStart: TArray<string>;
    FReenable: TArray<string>;
    class procedure Say(const AText: string); static;
    class procedure Tick; static;
    class procedure Next; static;
    class procedure RunStep(AStep: TAtlasRestartStep); static;
    class procedure Fail(const AText: string); static;
    class procedure Finished; static;
    class procedure ShowBar; static;
    class procedure RememberPlace; static;
    class procedure ReturnToPlace; static;
    class procedure Stop; static;
    class procedure Build; static;
    class procedure StartProgram; static;
    class function BreakpointKeys(AEnabled: Boolean): TArray<string>; static;
    class function ReenableBreakpoints: Integer; static;
  public
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ThemeChanged; static;
    /// <summary>Befehl Atlas.DebugRestart.</summary>
    class procedure Execute; static;
  end;

implementation

uses
  System.Classes,
  System.Types,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.UnavailableFixes,
  Atlas.UI.Debug.Strings;

const
  /// <summary>Zeichen hinter fertigen bzw. gescheiterten Schritten.</summary>
  cDoneMark = '✓';
  cFailedMark = '✗';

{ TAtlasIdeDebugRestart.TTicker }

procedure TAtlasIdeDebugRestart.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugRestart.Tick);
end;

{ TAtlasIdeDebugRestart.TListener }

procedure TAtlasIdeDebugRestart.TListener.DebugStarted;
begin
  // Stand der Haltepunkte beim Start: für debug.restart.reenableBreakpoints.
  FEnabledAtStart := TAtlasIdeDebugRestart.BreakpointKeys(True);
  if (FRun <> nil) and FRun.Running and (FRun.Current = TAtlasRestartStep.Start) then
  begin
    FStepDone := True;
  end;
end;

procedure TAtlasIdeDebugRestart.TListener.DebugEnded;
begin
  if (FRun <> nil) and FRun.Running and (FRun.Current = TAtlasRestartStep.Stop) then
  begin
    FStepDone := True;
  end;
end;

{ TAtlasIdeDebugRestart }

class procedure TAtlasIdeDebugRestart.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cIntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugRestart.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FreeAndNil(FBar);
  FreeAndNil(FRun);
  FMessage := nil;
  FEnabledAtStart := nil;
  FReenable := nil;
end;

class function TAtlasIdeDebugRestart.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugRestart.ThemeChanged;
begin
  if (FBar <> nil) and FBar.IsShown then
  begin
    FBar.Colors := TAtlasIdeStyle.Colors;
    FBar.Invalidate;
  end;
end;

class procedure TAtlasIdeDebugRestart.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeDebugRestart.BreakpointKeys(AEnabled: Boolean): TArray<string>;
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
    if (mBreakpoint <> nil) and (mBreakpoint.Enabled = AEnabled) then
    begin
      Result := Result + [TAtlasRestartBreakpoints.KeyOf(mBreakpoint.FileName, mBreakpoint.LineNumber)];
    end;
  end;
end;

class function TAtlasIdeDebugRestart.ReenableBreakpoints: Integer;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mBreakpoint: IOTASourceBreakpoint;
  mKey: string;
begin
  Result := 0;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if (mServices = nil) or (Length(FReenable) = 0) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint = nil) or mBreakpoint.Enabled then
    begin
      Continue;
    end;
    for mKey in FReenable do
    begin
      if SameText(mKey, TAtlasRestartBreakpoints.KeyOf(mBreakpoint.FileName, mBreakpoint.LineNumber)) then
      begin
        mBreakpoint.Enabled := True;
        Inc(Result);
        Break;
      end;
    end;
  end;
end;

class procedure TAtlasIdeDebugRestart.RememberPlace;
var
  mView: IOTAEditView;
begin
  FFileName := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  FFileName := mView.Buffer.FileName;
  FLine := mView.CursorPos.Line - 1;
  FColumn := mView.CursorPos.Col - 1;
end;

class procedure TAtlasIdeDebugRestart.ReturnToPlace;
begin
  if FFileName <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(FFileName, FLine, FColumn);
  end;
end;

class procedure TAtlasIdeDebugRestart.Execute;
var
  mProject: IOTAProject;
  mChanged: Boolean;
begin
  if not Started or ((FRun <> nil) and FRun.Running) then
  begin
    Exit;
  end;
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartNoProject));
    Exit;
  end;
  RememberPlace;
  FReenable := nil;
  if TAtlasIdeSettings.Current.DebugRestartReenableBreakpoints then
  begin
    FReenable := TAtlasRestartBreakpoints.ToReenable(FEnabledAtStart, BreakpointKeys(False));
  end;
  mChanged := (mProject.ProjectBuilder <> nil) and mProject.ProjectBuilder.ShouldBuild;
  FreeAndNil(FRun);
  FRun := TAtlasRestartRun.Create(TAtlasIdeDebugSession.Active, mChanged);
  FDoneAt := 0;
  FStepDone := True;
  FTimer.Enabled := True;
  Tick;
end;

class procedure TAtlasIdeDebugRestart.Tick;
begin
  if FRun = nil then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  if not FRun.Running then
  begin
    // Leiste nach dem Ende noch kurz stehen lassen.
    if (FDoneAt > 0) and (TThread.GetTickCount64 - FDoneAt >= cDoneMs) then
    begin
      FTimer.Enabled := False;
      if FBar <> nil then
      begin
        FBar.Dismiss;
      end;
    end;
    Exit;
  end;
  if FStepDone then
  begin
    Next;
  end
  else if (FRun.Current = TAtlasRestartStep.Stop) and (TThread.GetTickCount64 - FStepAt > cStopMs) then
  begin
    Fail(TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartFailedStop));
  end
  else if (FRun.Current = TAtlasRestartStep.Start) and (TThread.GetTickCount64 - FStepAt > cStartMs) then
  begin
    Fail(TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartFailedStart));
  end;
end;

class procedure TAtlasIdeDebugRestart.Next;
var
  mStep: TAtlasRestartStep;
begin
  FStepDone := False;
  if not FRun.Advance(TThread.GetTickCount64, mStep) then
  begin
    Finished;
    Exit;
  end;
  FStepAt := TThread.GetTickCount64;
  ShowBar;
  RunStep(mStep);
end;

class procedure TAtlasIdeDebugRestart.RunStep(AStep: TAtlasRestartStep);
begin
  case AStep of
    TAtlasRestartStep.Stop:
      Stop;
    TAtlasRestartStep.Build:
      Build;
    TAtlasRestartStep.Start:
      StartProgram;
    TAtlasRestartStep.Return:
      begin
        ReturnToPlace;
        FRun.Finish(True, TThread.GetTickCount64);
        Finished;
      end;
  end;
end;

class procedure TAtlasIdeDebugRestart.Stop;
var
  mProcess: IOTAProcess;
begin
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess = nil then
  begin
    FStepDone := True;
    Exit;
  end;
  try
    mProcess.Terminate;
  except
    on Exception do
      Fail(TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartFailedStop));
  end;
end;

class procedure TAtlasIdeDebugRestart.Build;
var
  mProject: IOTAProject;
  mOk: Boolean;
begin
  mProject := GetActiveProject;
  mOk := (mProject <> nil) and (mProject.ProjectBuilder <> nil) and
    mProject.ProjectBuilder.BuildProject(cmOTAMake, True, True);
  if not mOk then
  begin
    Fail(TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartFailedBuild));
    Exit;
  end;
  FStepDone := True;
end;

class procedure TAtlasIdeDebugRestart.StartProgram;
var
  mCount: Integer;
begin
  mCount := ReenableBreakpoints;
  if mCount > 0 then
  begin
    Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RestartReenabled, [mCount]));
  end;
  TAtlasIdeDebugUnavailableFixes.Run(FMessage);
end;

class procedure TAtlasIdeDebugRestart.Fail(const AText: string);
begin
  FRun.Finish(False, TThread.GetTickCount64);
  Say(AText);
  Finished;
end;

class procedure TAtlasIdeDebugRestart.Finished;
begin
  FDoneAt := TThread.GetTickCount64;
  ShowBar;
end;

class procedure TAtlasIdeDebugRestart.ShowBar;
var
  mCaptions: TAtlasRestartCaptions;
  mPoint: TPoint;
begin
  mCaptions[TAtlasRestartStep.Stop] := TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartStop);
  mCaptions[TAtlasRestartStep.Build] := TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartBuild);
  mCaptions[TAtlasRestartStep.Start] := TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartStart);
  mCaptions[TAtlasRestartStep.Return] := TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartReturn);
  if FBar = nil then
  begin
    FBar := TAtlasStepsBar.Create(nil);
  end;
  mPoint := TAtlasStepsBar.ActiveCorner;
  FBar.Colors := TAtlasIdeStyle.Colors;
  FBar.SetScaling(TAtlasPopupWindow.MonitorPPI(mPoint), 1, '', 10);
  FBar.ShowSteps(TAtlasDebugStrings.Text(TAtlasDebugTextId.RestartTitle), FRun.Text(mCaptions, cDoneMark,
    cFailedMark), mPoint);
end;

end.
