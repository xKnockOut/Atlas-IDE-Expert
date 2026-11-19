unit Atlas.IDE.Assistants.DebugInbox;

// Eingang für Debug-Aufträge von KI-Assistenten (#1874, Protokoll in Atlas.Core.Assistants.DebugInbox): Sobald der
// Ordner sich ändert (Signal alle 250 ms abgefragt, aufgelistet nur nach einem Signal, bei liegen gebliebenen
// Aufträgen oder alle zwei Sekunden, #1984), übernimmt das Plugin einen wartenden Auftrag der MCP-Werkzeuge
// debug_start … debug_evaluate, prüft Pause, Sitzung und Rechte (TAtlasDebugGate) und führt ihn über den Vertrag
// IAtlasDebugControl des Debuggers aus, den der Eingang bei jedem Auftrag neu in der Registry sucht (Regel 2). Fehlt
// der Debugger, lehnt der Eingang mit Grund ab.
// Start, Weiterlaufen und Schritte beantwortet der Eingang erst beim nächsten Halt, am Ende des Programms oder nach
// waitSeconds (TAtlasDebugWait); solange bleiben weitere Aufträge liegen. Endet die Sitzung des Assistenten oder
// wird der Eingang abgebaut (Einstellung aus, Modul entladen), entfernt er die Haltepunkte der Gruppe Atlas-KI und
// beantwortet einen wartenden Auftrag mit Grund; danach erreicht nichts mehr das Modul (Regel 3).

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Assistants.InboxPace,
  Atlas.Core.Assistants.DebugInbox,
  Atlas.Core.Assistants.DebugGate,
  Atlas.IDE.Contracts.DebugControl,
  Atlas.IDE.Assistants.FolderSignal;

type
  TAtlasDebugInboxProc = reference to procedure(const AMessage: string);

  TAtlasIdeDebugInbox = class
  private
    FFolder: string;
    FTimer: TTimer;
    FSignal: TAtlasFolderSignal;
    FPace: TAtlasInboxPace;
    FControl: TFunc<IAtlasDebugControl>;
    FRights: TFunc<TAtlasDebugRights>;
    FOnChange: TProc;
    FOnMessage: TAtlasDebugInboxProc;
    FGate: TAtlasDebugGate;
    FWaiting: Boolean;
    FWait: TAtlasDebugWait;
    FWaitRequest: TAtlasDebugRequest;
    procedure Tick(Sender: TObject);
    procedure Observe(const AControl: IAtlasDebugControl);
    procedure Process(const ARequestFile: string; const AControl: IAtlasDebugControl);
    procedure Execute(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure StartProgram(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure StopProgram(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure AddBreakpoint(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure RemoveBreakpoints(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure Proceed(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure BeginWait(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl; ALaunch: Boolean);
    procedure AnswerState(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure Evaluate(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
    procedure Answer(const AId, AText: string);
    procedure Refuse(const AId, AReason: string);
    procedure Changed;
  public
    /// <summary>AControl liefert den Debugger (nil ohne Modul), ARights die Rechte aus den Einstellungen.
    /// AOnChange: Pause, Sitzung oder Zähler haben sich geändert (Leiste). AOnMessage: Zeile für die
    /// Meldungsansicht.</summary>
    constructor Create(const AControl: TFunc<IAtlasDebugControl>; const ARights: TFunc<TAtlasDebugRights>;
      const AOnChange: TProc; const AOnMessage: TAtlasDebugInboxProc);
    destructor Destroy; override;
    /// <summary>„Pause für KI“ (True) bzw. „Fortsetzen“ (False).</summary>
    procedure SetPaused(AValue: Boolean);
    /// <summary>„Übernehmen“: Die Sitzung bleibt, der Assistent ist getrennt; seine Haltepunkte bleiben.</summary>
    procedure TakeOver;
    property Gate: TAtlasDebugGate read FGate;
    property Folder: string read FFolder;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.JSON,
  Atlas.Core.DebugControl.Types,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Assistants.Inbox,
  Atlas.UI.Assistants.Strings;

var
  /// <summary>Ordner dieses Prozesses schon einmal aufgeräumt?</summary>
  GCleaned: Boolean;

/// <summary>Gründe für unlesbare Aufträge in der Sprache der Oberfläche (#1458).</summary>
function InboxTexts: TAtlasDebugInboxTexts;
begin
  Result := Default(TAtlasDebugInboxTexts);
  Result.Unreadable := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.RequestUnreadable);
  Result.UnknownCommand := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugUnknownCommand);
end;

function RefusalText(ARefusal: TAtlasDebugRefusal): string;
const
  cIds: array[TAtlasDebugRefusal] of TAtlasAssistantsTextId = (TAtlasAssistantsTextId.DebugRefusedPaused,
    TAtlasAssistantsTextId.DebugRefusedPaused, TAtlasAssistantsTextId.DebugRefusedUserSession,
    TAtlasAssistantsTextId.DebugRefusedRunning, TAtlasAssistantsTextId.DebugRefusedNoProgram,
    TAtlasAssistantsTextId.DebugRefusedNotStopped, TAtlasAssistantsTextId.DebugRefusedSideEffects,
    TAtlasAssistantsTextId.DebugRefusedModify);
begin
  Result := TAtlasAssistantsStrings.Text(cIds[ARefusal]);
end;

/// <summary>Neue Kennung einer Sitzung.</summary>
function NewSession: string;
begin
  Result := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
end;

const
  /// <summary>Abstand, in dem der Eingang nach neuen Aufträgen sieht (ms).</summary>
  cPollMs = 250;

{ TAtlasIdeDebugInbox }

constructor TAtlasIdeDebugInbox.Create(const AControl: TFunc<IAtlasDebugControl>;
  const ARights: TFunc<TAtlasDebugRights>; const AOnChange: TProc; const AOnMessage: TAtlasDebugInboxProc);
begin
  inherited Create;
  FControl := AControl;
  FRights := ARights;
  FOnChange := AOnChange;
  FOnMessage := AOnMessage;
  FGate := TAtlasDebugGate.Create;
  FFolder := TAtlasDebugInbox.Folder(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    GetCurrentProcessId);
  // Nur beim ersten Start in diesem Prozess aufräumen (Reste eines früheren Prozesses mit derselben Nummer).
  if not GCleaned then
  begin
    try
      if TDirectory.Exists(FFolder) then
      begin
        TDirectory.Delete(FFolder, True);
      end;
    except
      on E: EInOutError do
        TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
    GCleaned := True;
  end;
  FSignal := TAtlasFolderSignal.Create(FFolder);
  FPace := Default(TAtlasInboxPace);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cPollMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeDebugInbox.Destroy;
var
  mControl: IAtlasDebugControl;
begin
  FTimer.Free;
  FSignal.Free;
  try
    // Ein wartender Auftrag bekommt noch seine Antwort; danach erreicht nichts mehr dieses Modul (Regel 3).
    if FWaiting then
    begin
      Refuse(FWaitRequest.Id, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugSwitchedOff));
    end;
    // Haltepunkte des Assistenten gehen mit dem Eingang.
    mControl := FControl();
    if mControl <> nil then
    begin
      mControl.RemoveAllBreakpoints;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
  FWaitRequest := Default(TAtlasDebugRequest);
  FGate.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDebugInbox.Changed;
begin
  if Assigned(FOnChange) then
  begin
    FOnChange();
  end;
end;

procedure TAtlasIdeDebugInbox.SetPaused(AValue: Boolean);
begin
  FGate.SetPaused(AValue);
  Changed;
end;

procedure TAtlasIdeDebugInbox.TakeOver;
begin
  if FWaiting then
  begin
    FWaiting := False;
    Refuse(FWaitRequest.Id, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugTakenOver));
  end;
  FGate.TakeOver;
  Changed;
end;

procedure TAtlasIdeDebugInbox.Answer(const AId, AText: string);
begin
  TAtlasFileInbox.Answer(FFolder, AId, AText);
end;

procedure TAtlasIdeDebugInbox.Refuse(const AId, AReason: string);
begin
  Answer(AId, TAtlasDebugInbox.RefusalText(AReason));
end;

/// <summary>Zustand des Debuggers; None ohne Debugger.</summary>
function PhaseOf(const AControl: IAtlasDebugControl): TAtlasDebugControlPhase;
begin
  Result := TAtlasDebugControlPhase.None;
  if AControl <> nil then
  begin
    Result := AControl.Phase;
  end;
end;

procedure TAtlasIdeDebugInbox.Observe(const AControl: IAtlasDebugControl);
var
  mOwn: Boolean;
begin
  mOwn := FGate.Own;
  FGate.Observe(PhaseOf(AControl));
  if mOwn and not FGate.Own then
  begin
    // Sitzung des Assistenten zu Ende: seine Haltepunkte entfernen.
    if AControl <> nil then
    begin
      AControl.RemoveAllBreakpoints;
    end;
    Changed;
  end;
end;

procedure TAtlasIdeDebugInbox.Tick(Sender: TObject);
var
  mControl: IAtlasDebugControl;
  mPending: TArray<string>;
begin
  try
    mControl := FControl();
    Observe(mControl);
    if FWaiting then
    begin
      // Ohne Debugger (Modul entladen) gleich antworten: Zustand none.
      if (mControl = nil) or FWait.Done(mControl.Phase, mControl.StopCount, GetTickCount64) then
      begin
        FWaiting := False;
        AnswerState(FWaitRequest, mControl);
      end;
      Exit;
    end;
    if not FPace.Due(FSignal.Changed, GetTickCount64) then
    begin
      Exit;
    end;
    FSignal.Reopen;
    mPending := TAtlasFileInbox.Pending(FFolder);
    // Nur einer je Takt: Liegen mehr, listet der nächste Takt wieder.
    FPace.Listed(GetTickCount64, Length(mPending) > 1);
    if Length(mPending) > 0 then
    begin
      Process(mPending[0], mControl);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugInbox.Process(const ARequestFile: string; const AControl: IAtlasDebugControl);
var
  mRequest: TAtlasDebugRequest;
  mId, mText, mReason: string;
  mRefusal: TAtlasDebugRefusal;
begin
  if not TAtlasFileInbox.Claim(ARequestFile, mId, mText) then
  begin
    Exit;
  end;
  if not TAtlasDebugInbox.ParseRequest(mText, InboxTexts, mRequest, mReason) then
  begin
    Refuse(mId, mReason);
    Exit;
  end;
  mRequest.Id := mId;
  if AControl = nil then
  begin
    Refuse(mId, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugNoDebugger));
    Exit;
  end;
  mRefusal := FGate.Refusal(mRequest, AControl.Phase, FRights());
  if mRefusal <> TAtlasDebugRefusal.None then
  begin
    Refuse(mId, RefusalText(mRefusal));
    Exit;
  end;
  FGate.Note(mRequest);
  try
    Execute(mRequest, AControl);
  finally
    Changed;
  end;
end;

procedure TAtlasIdeDebugInbox.BeginWait(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl;
  ALaunch: Boolean);
begin
  FWaitRequest := ARequest;
  FWait := TAtlasDebugWait.Start(AControl.StopCount, GetTickCount64, ARequest.WaitSeconds, ALaunch);
  FWaiting := True;
end;

procedure TAtlasIdeDebugInbox.AnswerState(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
var
  mState: TAtlasDebugControlState;
begin
  mState := Default(TAtlasDebugControlState);
  if (AControl = nil) or not AControl.ReadState(ARequest.Frames, ARequest.Locals, mState) then
  begin
    mState := Default(TAtlasDebugControlState);
    mState.Phase := PhaseOf(AControl);
  end;
  FGate.Observe(mState.Phase);
  Answer(ARequest.Id, TAtlasDebugInbox.SuccessText(TAtlasDebugInbox.StateJson(FGate.Session,
    FGate.StateName(mState.Phase), mState)));
end;

procedure TAtlasIdeDebugInbox.Evaluate(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
var
  mValue, mTypeName, mReason: string;
  mSideEffects: Boolean;
begin
  // Eine Zuweisung braucht Aufrufe des Debuggers; erlaubt hat sie TAtlasDebugGate schon über debug.mcp.modify.
  mSideEffects := ARequest.SideEffects or TAtlasDebugGate.Assigns(ARequest.Expression);
  if AControl.Evaluate(ARequest.Expression, mSideEffects, mValue, mTypeName, mReason) then
  begin
    Answer(ARequest.Id, TAtlasDebugInbox.SuccessText(TAtlasDebugInbox.EvaluationJson(ARequest.Expression, mValue,
      mTypeName)));
    Exit;
  end;
  if not mSideEffects and (Pos('(', ARequest.Expression) > 0) then
  begin
    // Ohne Nebenwirkungen wertet der Debugger keine Aufrufe aus: dem Assistenten sagen, was fehlt.
    mReason := Trim(mReason + ' ' + TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugNeedsSideEffects));
  end;
  Refuse(ARequest.Id, mReason);
end;

procedure TAtlasIdeDebugInbox.StartProgram(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
var
  mReason: string;
begin
  if not AControl.Launch(ARequest.Launch, mReason) then
  begin
    Refuse(ARequest.Id, mReason);
    Exit;
  end;
  FGate.Launched(NewSession);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.DebugStarted,
      [ExtractFileName(ARequest.Launch.Project)]));
  end;
  BeginWait(ARequest, AControl, True);
end;

procedure TAtlasIdeDebugInbox.StopProgram(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
var
  mResult: TJSONObject;
  mRemoved: Integer;
begin
  mRemoved := AControl.RemoveAllBreakpoints;
  if AControl.Phase <> TAtlasDebugControlPhase.None then
  begin
    AControl.Terminate;
  end;
  mResult := TAtlasDebugInbox.StateJson(FGate.Session, TAtlasDebugInbox.cTerminated, Default(TAtlasDebugControlState));
  mResult.AddPair('removed', TJSONNumber.Create(mRemoved));
  Answer(ARequest.Id, TAtlasDebugInbox.SuccessText(mResult));
end;

procedure TAtlasIdeDebugInbox.AddBreakpoint(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
var
  mReason: string;
  mBreakpoint: TAtlasDebugControlBreakpoint;
begin
  if AControl.AddBreakpoint(ARequest.FileName, ARequest.Line, ARequest.Condition, ARequest.PassCount,
    mBreakpoint, mReason) then
  begin
    Answer(ARequest.Id, TAtlasDebugInbox.SuccessText(TAtlasDebugInbox.BreakpointJson(mBreakpoint)));
  end
  else
  begin
    Refuse(ARequest.Id, mReason);
  end;
end;

procedure TAtlasIdeDebugInbox.RemoveBreakpoints(const ARequest: TAtlasDebugRequest;
  const AControl: IAtlasDebugControl);
begin
  if ARequest.All then
  begin
    Answer(ARequest.Id, TAtlasDebugInbox.SuccessText(TAtlasDebugInbox.RemovedJson(AControl.RemoveAllBreakpoints)));
  end
  else if AControl.RemoveBreakpoint(ARequest.BreakpointId) then
  begin
    Answer(ARequest.Id, TAtlasDebugInbox.SuccessText(TAtlasDebugInbox.RemovedJson(1)));
  end
  else
  begin
    Refuse(ARequest.Id, TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.DebugNoBreakpoint, [ARequest.BreakpointId]));
  end;
end;

procedure TAtlasIdeDebugInbox.Proceed(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
var
  mReason: string;
  mDone: Boolean;
begin
  if ARequest.Command = TAtlasDebugCommand.Step then
  begin
    mDone := AControl.Step(ARequest.StepKind, ARequest.FileName, ARequest.Line, mReason);
  end
  else
  begin
    mDone := AControl.Resume(mReason);
  end;
  if mDone then
  begin
    BeginWait(ARequest, AControl, False);
  end
  else
  begin
    Refuse(ARequest.Id, mReason);
  end;
end;

procedure TAtlasIdeDebugInbox.Execute(const ARequest: TAtlasDebugRequest; const AControl: IAtlasDebugControl);
begin
  case ARequest.Command of
    TAtlasDebugCommand.Start:
      StartProgram(ARequest, AControl);
    TAtlasDebugCommand.Stop:
      StopProgram(ARequest, AControl);
    TAtlasDebugCommand.SetBreakpoint:
      AddBreakpoint(ARequest, AControl);
    TAtlasDebugCommand.RemoveBreakpoint:
      RemoveBreakpoints(ARequest, AControl);
    TAtlasDebugCommand.Resume, TAtlasDebugCommand.Step:
      Proceed(ARequest, AControl);
    TAtlasDebugCommand.State:
      AnswerState(ARequest, AControl);
    TAtlasDebugCommand.Evaluate:
      Evaluate(ARequest, AControl);
  end;
end;

end.
