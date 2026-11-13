unit Atlas.IDE.Debug.RunTo;

// Bis hier ausführen (#851) im Debugger der IDE; die Spalte mit ▶ im Rand
// zeichnet Atlas.IDE.Debug.RunToColumn, die Regeln stehen in
// Atlas.Core.Debug.RunTo.
// - Bis hier: Haltepunkt an der Zeile (vorhandener wird eingeschaltet, sonst
//   ein neuer angelegt), dann Weiter (ormRun). Beim nächsten Halt oder am
//   Ende der Sitzung setzt Atlas alles zurück, gleich wo das Programm hält.
// - Haltepunkte überspringen: zusätzlich alle anderen aktiven Haltepunkte
//   ausschalten. Was Atlas geändert hat, steht bis zum Zurücksetzen in
//   %LOCALAPPDATA%\Atlas\debug-runto.json; nach einem Absturz der IDE setzt
//   Atlas es beim nächsten Start einer Debug-Sitzung zurück.
// - Einmaliger Haltepunkt: gewöhnlicher Haltepunkt in der Gruppe
//   Atlas.Einmalig (TAtlasRunTo.cOnceGroup); hält das Programm an ihm, entfernt
//   Atlas ihn. Geht auch, wenn kein Programm läuft.
// - Zeile: die des letzten Rechtsklicks in den Rand (TAtlasIdeGutterMarks),
//   sonst die Cursorzeile. Zeilen ohne ausführbaren Code lehnt Atlas ab.
// F4 der IDE bleibt unverändert. Gesichert über TAtlasFeature.Debugger. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Debug.RunTo,
  Atlas.IDE.Debug.Session;

type
  TAtlasIdeRunTo = class
  private const
    cStateFile = 'debug-runto.json';
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
  private class var
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    FState: TAtlasRunToState;
    FStopCount: Integer;
    class procedure Report(const AText: string); static;
    class function StateFile: string; static;
    class procedure SaveState; static;
    class procedure LoadState; static;
    class procedure Arrived; static;
    class procedure RemoveOnce; static;
    class function SourceStates: TAtlasBreakpointStates; static;
    class function TargetLine(out AFileName: string; out ALine: Integer): Boolean; static;
    /// <summary>Haltepunkt am Ziel einschalten oder anlegen; False mit Meldung.</summary>
    class function PrepareTarget(const AFileName: string; ALine: Integer; var AState: TAtlasRunToState): Boolean;
      static;
    class procedure DisableOthers(var AState: TAtlasRunToState); static;
  public
    /// <summary>Teil starten: Zuhörer bei der Debug-Sitzung. AMessage schreibt eine Zeile in die Meldungsansicht.
    /// </summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.runToClick an und Teil gestartet?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Ausführbarer Code an ALine (ab 0) von AFileName?</summary>
    class function CodeLine(const AFileName: string; ALine: Integer): Boolean; static;
    /// <summary>Bis ALine (ab 0) von AFileName ausführen; ASkip: andere Haltepunkte überspringen.</summary>
    class procedure RunToLine(const AFileName: string; ALine: Integer; ASkip: Boolean); static;
    /// <summary>Was Atlas für den letzten Lauf geändert hat, zurücksetzen.</summary>
    class procedure Restore; static;
    /// <summary>Befehle Atlas.RunToHere und Atlas.RunToHereSkip.</summary>
    class procedure RunHere; static;
    class procedure RunHereSkip; static;
    /// <summary>Taste von „Haltepunkte überspringen“: False, wenn das Programm nicht angehalten ist (die Taste
    /// geht dann an die IDE).</summary>
    class function TryRunHereSkip: Boolean; static;
    /// <summary>Befehl Atlas.OnceBreakpoint.</summary>
    class procedure SetOnce; static;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Files.DataFile,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.UI.Debug.Strings;

{ TAtlasIdeRunTo.TListener }

procedure TAtlasIdeRunTo.TListener.DebugStarted;
begin
  // Rest einer Sitzung, die mit der IDE abgestürzt ist.
  TAtlasIdeRunTo.Restore;
end;

procedure TAtlasIdeRunTo.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  TAtlasIdeRunTo.Arrived;
end;

procedure TAtlasIdeRunTo.TListener.DebugEnded;
begin
  TAtlasIdeRunTo.Restore;
end;

{ TAtlasIdeRunTo }

class procedure TAtlasIdeRunTo.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
    TAtlasIdeDebugSession.Start;
    LoadState;
  end;
end;

class procedure TAtlasIdeRunTo.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FMessage := nil;
  // Der Zustand bleibt in der Datei; der nächste Start setzt ihn zurück.
  FState := Default(TAtlasRunToState);
end;

class function TAtlasIdeRunTo.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeRunTo.Enabled: Boolean;
begin
  Result := Started and TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.DebugRunToClick;
end;

class procedure TAtlasIdeRunTo.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeRunTo.StateFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cStateFile);
end;

class procedure TAtlasIdeRunTo.SaveState;
begin
  try
    if FState.Active then
    begin
      ForceDirectories(ExtractFileDir(StateFile));
      TAtlasDataFile.Write(StateFile, TAtlasRunTo.ToJson(FState));
    end
    else if TFile.Exists(StateFile) then
    begin
      TFile.Delete(StateFile);
    end;
  except
    // Ohne Datei geht nur das Zurücksetzen nach einem Absturz verloren.
    on E: Exception do
      Report(E.Message);
  end;
end;

class procedure TAtlasIdeRunTo.LoadState;
var
  mText: string;
begin
  if TAtlasDataFile.TryRead(StateFile, mText) and TAtlasRunTo.Parse(mText, FState) then
  begin
    Restore;
  end;
end;

class function TAtlasIdeRunTo.SourceStates: TAtlasBreakpointStates;
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
    if (mBreakpoint <> nil) and (mBreakpoint.FileName <> '') and (mBreakpoint.LineNumber > 0) then
    begin
      Result := Result + [TAtlasBreakpointState.Create(mBreakpoint.FileName, mBreakpoint.LineNumber - 1,
        mBreakpoint.Enabled)];
    end;
  end;
end;

class function TAtlasIdeRunTo.CodeLine(const AFileName: string; ALine: Integer): Boolean;
var
  mText: string;
begin
  Result := TAtlasIdeFiles.SourceText(AFileName, mText) and TAtlasRunTo.CodeLine(mText, ALine);
end;

class function TAtlasIdeRunTo.TargetLine(out AFileName: string; out ALine: Integer): Boolean;
var
  mView: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil);
  if not Result then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.RunToNoEditor));
    Exit;
  end;
  AFileName := mView.Buffer.FileName;
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := mView.CursorPos.Line - 1;
  end;
end;

class function TAtlasIdeRunTo.PrepareTarget(const AFileName: string; ALine: Integer;
  var AState: TAtlasRunToState): Boolean;
var
  mBreakpoint: IOTABreakpoint;
begin
  mBreakpoint := TAtlasIdeBreakpoints.Find(AFileName, ALine);
  if mBreakpoint = nil then
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Add(AFileName, ALine);
    AState.Created := mBreakpoint <> nil;
  end
  else if not mBreakpoint.Enabled then
  begin
    AState.Changed := AState.Changed + [TAtlasBreakpointState.Create(AFileName, ALine, False)];
    mBreakpoint.Enabled := True;
  end;
  Result := mBreakpoint <> nil;
  if not Result then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToNoBreakpoint, [ALine + 1]));
  end;
end;

class procedure TAtlasIdeRunTo.DisableOthers(var AState: TAtlasRunToState);
var
  mState: TAtlasBreakpointState;
  mBreakpoint: IOTABreakpoint;
begin
  for mState in TAtlasRunTo.ToDisable(SourceStates, AState.FileName, AState.Line) do
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Find(mState.FileName, mState.Line);
    if mBreakpoint <> nil then
    begin
      mBreakpoint.Enabled := False;
      AState.Changed := AState.Changed + [mState];
    end;
  end;
end;

class procedure TAtlasIdeRunTo.RunToLine(const AFileName: string; ALine: Integer; ASkip: Boolean);
var
  mProcess: IOTAProcess;
  mState: TAtlasRunToState;
begin
  mProcess := TAtlasIdeBreakpoints.StoppedProcess;
  if mProcess = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.RunToNotStopped));
    Exit;
  end;
  if not CodeLine(AFileName, ALine) then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToNoCode, [ALine + 1]));
    Exit;
  end;
  // Ein Lauf, der noch nicht angekommen ist (etwa nach Pause), zuerst zurücksetzen.
  Restore;
  mState := Default(TAtlasRunToState);
  mState.FileName := AFileName;
  mState.Line := ALine;
  if not PrepareTarget(AFileName, ALine, mState) then
  begin
    Exit;
  end;
  if ASkip then
  begin
    DisableOthers(mState);
  end;
  FState := mState;
  FStopCount := TAtlasIdeDebugSession.StopCount;
  SaveState;
  mProcess.Run(ormRun);
end;

class procedure TAtlasIdeRunTo.Arrived;
begin
  // Erst ein Halt nach dem Weiter zählt; der Halt, von dem aus gestartet wurde, kann noch gemeldet werden.
  if FState.Active and (TAtlasIdeDebugSession.StopCount > FStopCount) then
  begin
    Restore;
  end;
  RemoveOnce;
end;

class procedure TAtlasIdeRunTo.Restore;
var
  mState: TAtlasBreakpointState;
  mBreakpoint: IOTABreakpoint;
  mDone: TAtlasBreakpointStates;
  mTarget: TArray<IOTABreakpoint>;
begin
  if not FState.Active then
  begin
    Exit;
  end;
  mDone := nil;
  for mState in FState.Changed do
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Find(mState.FileName, mState.Line);
    if mBreakpoint <> nil then
    begin
      mBreakpoint.Enabled := mState.Enabled;
      mDone := mDone + [mState];
    end;
  end;
  mBreakpoint := TAtlasIdeBreakpoints.Find(FState.FileName, FState.Line);
  if FState.Created and (mBreakpoint <> nil) then
  begin
    mTarget := [mBreakpoint];
    TAtlasIdeBreakpoints.RemoveAll(mTarget);
    FState.Created := False;
  end;
  FState.Changed := TAtlasRunTo.Without(FState.Changed, mDone);
  // Was sich noch nicht finden lässt (Haltepunkte der IDE noch nicht geladen), bleibt für den nächsten Versuch.
  if (FState.Changed = nil) and not FState.Created then
  begin
    FState := Default(TAtlasRunToState);
  end;
  SaveState;
  if Length(mDone) > 1 then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToRestored, [Length(mDone)]));
  end;
end;

class procedure TAtlasIdeRunTo.RemoveOnce;
var
  mThread: IOTAThread;
  mFileName: string;
  mLine: Integer;
  mBreakpoints: TArray<IOTABreakpoint>;
begin
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if (mThread = nil) or not TAtlasIdeBreakpoints.Position(mThread, mFileName, mLine) then
  begin
    Exit;
  end;
  mBreakpoints := [TAtlasIdeBreakpoints.Find(mFileName, mLine)];
  if (mBreakpoints[0] <> nil) and SameText(mBreakpoints[0].GroupName, TAtlasRunTo.cOnceGroup) then
  begin
    TAtlasIdeBreakpoints.RemoveAll(mBreakpoints);
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToOnceRemoved, [ExtractFileName(mFileName), mLine + 1]));
  end;
end;

class procedure TAtlasIdeRunTo.RunHere;
var
  mFileName: string;
  mLine: Integer;
begin
  if TargetLine(mFileName, mLine) then
  begin
    RunToLine(mFileName, mLine, False);
  end;
end;

class procedure TAtlasIdeRunTo.RunHereSkip;
var
  mFileName: string;
  mLine: Integer;
begin
  if TargetLine(mFileName, mLine) then
  begin
    RunToLine(mFileName, mLine, True);
  end;
end;

class function TAtlasIdeRunTo.TryRunHereSkip: Boolean;
begin
  Result := Enabled and (TAtlasIdeBreakpoints.StoppedProcess <> nil);
  if Result then
  begin
    RunHereSkip;
  end;
end;

class procedure TAtlasIdeRunTo.SetOnce;
var
  mFileName: string;
  mLine: Integer;
begin
  if not TargetLine(mFileName, mLine) then
  begin
    Exit;
  end;
  if TAtlasIdeBreakpoints.Find(mFileName, mLine) <> nil then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToOnceExists, [mLine + 1]));
  end
  else if not CodeLine(mFileName, mLine) then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToNoCode, [mLine + 1]));
  end
  else if TAtlasIdeBreakpoints.Add(mFileName, mLine, TAtlasRunTo.cOnceGroup) = nil then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToNoBreakpoint, [mLine + 1]));
  end
  else
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToOnceSet, [mLine + 1]));
  end;
end;

end.
