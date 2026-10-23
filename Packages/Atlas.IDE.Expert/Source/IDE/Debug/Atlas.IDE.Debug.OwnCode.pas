unit Atlas.IDE.Debug.OwnCode;

// Nur eigener Code beim Debuggen (#578) in der IDE. Was die Open Tools API
// dafür hergibt (Prüfung aus dem Issue):
//   - Aufrufstapel: IOTAThread.GetCallCount/GetCallHeader/GetCallPos (über
//     TAtlasIdeDebugSession.ReadStack, mit csWait unter LLDB).
//   - Schritte: IOTAProcess.Run(ormRunUntilReturn) setzt bis zur Rückkehr fort.
//   - Was der Benutzer gedrückt hat, meldet die OTA nicht. Atlas hängt sich
//     deshalb an die Aktion „Einzelne Anweisung“ (F7) der IDE
//     (RunTraceIntoCommand, sonst die Aktion mit F7) und merkt sich den Schritt.
//   - Den Editor setzt IOTAActionServices/IOTAEditView (Sprung, Markierung).
// Ablauf:
//   - F7: Hält der Schritt in Code ohne Quelltext (oberster Rahmen ohne Datei,
//     die IDE zeigt sonst die CPU-Ansicht), setzt Atlas „Bis zur Rückkehr“
//     fort, bis wieder Quelltext erreicht ist (höchstens
//     TAtlasDebugOwnCode.MaxReturns-mal).
//   - Exception: Ist der oberste Rahmen mit Quelltext kein eigener Code,
//     springt Atlas nach dem Schließen des Exception-Dialogs der IDE (kein
//     modales Fenster mehr, Prozess steht noch am selben Halt) zur ersten
//     eigenen Zeile des Stapels und markiert sie. Der ursprüngliche Ort bleibt
//     über den Aufrufstapel der IDE und das Fenster „Atlas: Exceptions“
//     erreichbar.
// Ohne debug.justMyCode ist nichts angemeldet und die Aktion unverändert.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Actions,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Debug.Session;

type
  TAtlasIdeDebugOwnCode = class
  public const
    /// <summary>Name der Aktion „Einzelne Anweisung“ (F7) in der Aktionsliste der IDE.</summary>
    TraceIntoAction = 'RunTraceIntoCommand';
    /// <summary>So lange wartet Atlas höchstens auf das Schließen des Exception-Dialogs.</summary>
    JumpWaitMs = 120000;
    IntervalMs = 150;
    StackRetries = 10;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
    /// <summary>Hängt an der Aktion „Einzelne Anweisung“: merkt den Schritt, dann die Aktion wie bisher.</summary>
    TTraceHook = class(TComponent)
    private
      FAction: TContainedAction;
      FOriginal: TNotifyEvent;
      FBypass: Boolean;
      procedure Execute(Sender: TObject);
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    public
      constructor Create(AAction: TContainedAction); reintroduce;
      destructor Destroy; override;
    end;
    TTicker = class
    public
      procedure StepTick(Sender: TObject);
      procedure JumpTick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FHook: TTraceHook;
    FTicker: TTicker;
    FStepTimer: TTimer;
    FJumpTimer: TTimer;
    FMessage: TProc<string>;
    FStepping: Boolean;
    /// <summary>StopCount beim Auslösen des Schritts; der nächste Halt (+1) gehört dazu.</summary>
    FStepStop: Integer;
    FReturns: Integer;
    FStepRetries: Integer;
    FJumpStop: Integer;
    FJumpStarted: UInt64;
    FJumpQuiet: Integer;
    FJumpRetries: Integer;
    class function FindTraceInto: TContainedAction; static;
    class procedure Stepped; static;
    class procedure CheckStep; static;
    class procedure ScheduleJump; static;
    class procedure CheckJump; static;
    class function ReadFrames(out AFrames: TAtlasDebugFrames): TAtlasDebugStackRead; static;
    class function NewTimer(const AOnTimer: TNotifyEvent): TTimer; static;
  public
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.DebugJustMyCode: debug.justMyCode umschalten und speichern.</summary>
    class procedure ToggleSetting(const AMessage: TProc<string>); static;
    /// <summary>Für Tests und Studie: Hängt Atlas an der Aktion „Einzelne Anweisung“?</summary>
    class function Hooked: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.ActnList,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Strings;

{ TAtlasIdeDebugOwnCode.TTraceHook }

constructor TAtlasIdeDebugOwnCode.TTraceHook.Create(AAction: TContainedAction);
begin
  inherited Create(nil);
  FAction := AAction;
  FOriginal := AAction.OnExecute;
  FAction.OnExecute := Execute;
  FAction.FreeNotification(Self);
end;

destructor TAtlasIdeDebugOwnCode.TTraceHook.Destroy;
begin
  if FAction <> nil then
  begin
    FAction.RemoveFreeNotification(Self);
    FAction.OnExecute := FOriginal;
  end;
  inherited Destroy;
end;

procedure TAtlasIdeDebugOwnCode.TTraceHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
    FAction := nil;
end;

procedure TAtlasIdeDebugOwnCode.TTraceHook.Execute(Sender: TObject);
begin
  if FBypass or (FAction = nil) then
    Exit;
  // Merken darf den Schritt nie verhindern.
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugOwnCode.Stepped);
  if Assigned(FOriginal) then
  begin
    FOriginal(Sender);
    Exit;
  end;
  // Ohne eigenes OnExecute erledigt die IDE die Aktion über ihre Liste: kurz abhängen und ausführen.
  FBypass := True;
  FAction.OnExecute := nil;
  try
    FAction.Execute;
  finally
    if FAction <> nil then
      FAction.OnExecute := Execute;
    FBypass := False;
  end;
end;

{ TAtlasIdeDebugOwnCode.TTicker }

procedure TAtlasIdeDebugOwnCode.TTicker.StepTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugOwnCode.CheckStep);
end;

procedure TAtlasIdeDebugOwnCode.TTicker.JumpTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugOwnCode.CheckJump);
end;

{ TAtlasIdeDebugOwnCode.TListener }

procedure TAtlasIdeDebugOwnCode.TListener.DebugStarted;
begin
  FStepping := False;
  FJumpTimer.Enabled := False;
  FStepTimer.Enabled := False;
end;

procedure TAtlasIdeDebugOwnCode.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  case AStop of
    TAtlasDebugStop.Paused:
      // Nur der Halt direkt nach dem Schritt bzw. nach Atlas' „Bis zur Rückkehr“ gehört dazu.
      if FStepping and (TAtlasIdeDebugSession.StopCount = FStepStop + 1) then
      begin
        FStepRetries := 0;
        CheckStep;
      end
      else
        FStepping := False;
    TAtlasDebugStop.Exception, TAtlasDebugStop.Fault:
      begin
        FStepping := False;
        ScheduleJump;
      end;
  end;
end;

procedure TAtlasIdeDebugOwnCode.TListener.DebugEnded;
begin
  FStepping := False;
  FJumpTimer.Enabled := False;
  FStepTimer.Enabled := False;
end;

{ TAtlasIdeDebugOwnCode }

class function TAtlasIdeDebugOwnCode.NewTimer(const AOnTimer: TNotifyEvent): TTimer;
begin
  Result := TTimer.Create(nil);
  Result.Enabled := False;
  Result.Interval := IntervalMs;
  Result.OnTimer := AOnTimer;
end;

class function TAtlasIdeDebugOwnCode.FindTraceInto: TContainedAction;
var
  Services: INTAServices;
  Index: Integer;
  Action: TContainedAction;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    Action := Services.ActionList.Actions[Index];
    if SameText(Action.Name, TraceIntoAction) then
      Exit(Action);
  end;
  // Ersatz: die Aktion mit F7.
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    Action := Services.ActionList.Actions[Index];
    if (Action is TCustomAction) and (TCustomAction(Action).ShortCut = ShortCut(VK_F7, [])) then
      Exit(Action);
  end;
end;

class procedure TAtlasIdeDebugOwnCode.Start(const AMessage: TProc<string>);
var
  Action: TContainedAction;
begin
  FMessage := AMessage;
  if FTicker = nil then
    FTicker := TTicker.Create;
  if FStepTimer = nil then
    FStepTimer := NewTimer(FTicker.StepTick);
  if FJumpTimer = nil then
    FJumpTimer := NewTimer(FTicker.JumpTick);
  if FHook = nil then
  begin
    Action := FindTraceInto;
    if Action <> nil then
      FHook := TTraceHook.Create(Action)
    else
      TAtlasGuard.Log('Nur eigener Code: Aktion „Einzelne Anweisung“ nicht gefunden; F7 bleibt unverändert');
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugOwnCode.Release;
begin
  if FListener <> nil then
    TAtlasIdeDebugSession.RemoveListener(FListener);
  FListener := nil;
  FreeAndNil(FHook);
  FreeAndNil(FStepTimer);
  FreeAndNil(FJumpTimer);
  FreeAndNil(FTicker);
  FStepping := False;
  FMessage := nil;
  // Den Zwischenspeicher teilt sich Atlas mit dem Exception-Verlauf; er baut ihn bei Bedarf neu auf.
  TAtlasIdeDebugSources.Release;
end;

class function TAtlasIdeDebugOwnCode.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeDebugOwnCode.Hooked: Boolean;
begin
  Result := FHook <> nil;
end;

class procedure TAtlasIdeDebugOwnCode.ToggleSetting(const AMessage: TProc<string>);
var
  Next: TAtlasPluginSettings;
begin
  Next := TAtlasIdeSettings.Stored;
  Next.DebugJustMyCode := not Next.DebugJustMyCode;
  TAtlasIdeSettings.Update(Next);
  if Assigned(AMessage) then
    if Next.DebugJustMyCode then
      AMessage(TAtlasStrings.Text(TAtlasTextId.DebugJustMyCodeOn))
    else
      AMessage(TAtlasStrings.Text(TAtlasTextId.DebugJustMyCodeOff));
end;

class procedure TAtlasIdeDebugOwnCode.Stepped;
begin
  if not TAtlasIdeSettings.Current.DebugJustMyCode or (TAtlasIdeDebugSession.StoppedThread = nil) then
    Exit;
  FStepping := True;
  FStepStop := TAtlasIdeDebugSession.StopCount;
  FReturns := 0;
end;

class function TAtlasIdeDebugOwnCode.ReadFrames(out AFrames: TAtlasDebugFrames): TAtlasDebugStackRead;
var
  Thread: IOTAThread;
begin
  AFrames := nil;
  Thread := TAtlasIdeDebugSession.StoppedThread;
  if Thread = nil then
    Exit(TAtlasDebugStackRead.None);
  Result := TAtlasIdeDebugSession.ReadStack(Thread, TAtlasDebugCallStack.MaxFrames, AFrames);
  if Result = TAtlasDebugStackRead.Ready then
    TAtlasIdeDebugSources.MarkFrames(AFrames);
end;

class procedure TAtlasIdeDebugOwnCode.CheckStep;
var
  Frames: TAtlasDebugFrames;
begin
  FStepTimer.Enabled := False;
  if not FStepping then
    Exit;
  case ReadFrames(Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FStepRetries);
        if FStepRetries <= StackRetries then
          FStepTimer.Enabled := True
        else
          FStepping := False;
        Exit;
      end;
    TAtlasDebugStackRead.None:
      begin
        FStepping := False;
        Exit;
      end;
  end;
  if not TAtlasDebugOwnCode.ShouldReturn(TAtlasIdeSettings.Current.DebugJustMyCode, FStepping, Frames,
    FReturns) then
  begin
    FStepping := False;
    Exit;
  end;
  Inc(FReturns);
  FStepStop := TAtlasIdeDebugSession.StopCount;
  if not TAtlasIdeDebugSession.RunMode(ormRunUntilReturn) then
    FStepping := False;
end;

class procedure TAtlasIdeDebugOwnCode.ScheduleJump;
begin
  if not TAtlasIdeSettings.Current.DebugJustMyCode then
    Exit;
  FJumpStop := TAtlasIdeDebugSession.StopCount;
  FJumpStarted := TThread.GetTickCount64;
  FJumpQuiet := 0;
  FJumpRetries := 0;
  FJumpTimer.Enabled := True;
end;

class procedure TAtlasIdeDebugOwnCode.CheckJump;
var
  Frames: TAtlasDebugFrames;
  Index: Integer;
begin
  // Weitergelaufen (Fortsetzen, still fortgesetzt) oder neuer Halt: kein Sprung.
  if (TAtlasIdeDebugSession.StopCount <> FJumpStop) or (TAtlasIdeDebugSession.StoppedThread = nil) or
    (TThread.GetTickCount64 - FJumpStarted > JumpWaitMs) then
  begin
    FJumpTimer.Enabled := False;
    Exit;
  end;
  // Erst wenn der Exception-Dialog zu ist und die IDE ihren Ort gezeigt hat (zwei ruhige Takte).
  if Application.ModalLevel > 0 then
  begin
    FJumpQuiet := 0;
    Exit;
  end;
  Inc(FJumpQuiet);
  if FJumpQuiet < 2 then
    Exit;
  case ReadFrames(Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FJumpRetries);
        if FJumpRetries > StackRetries then
          FJumpTimer.Enabled := False;
        Exit;
      end;
    TAtlasDebugStackRead.None:
      begin
        FJumpTimer.Enabled := False;
        Exit;
      end;
  end;
  FJumpTimer.Enabled := False;
  Index := TAtlasDebugOwnCode.JumpIndex(Frames, TAtlasIdeSettings.Current.DebugJustMyCode);
  if Index < 0 then
    Exit;
  TAtlasIdeNavigation.MarkLine(Frames[Index].FileName, Frames[Index].Line - 1);
  if Assigned(FMessage) then
    FMessage(TAtlasStrings.Fmt(TAtlasTextId.DebugJustMyCodeJumped,
      [ExtractFileName(Frames[Index].FileName), Frames[Index].Line, Index]));
end;

end.
