unit Atlas.IDE.Debug.OwnCode;

// Nur eigener Code beim Debuggen (#578) in der IDE. Was die Open Tools API
// dafür hergibt (Prüfung aus dem Issue):
//   - Aufrufstapel: IOTAThread.GetCallCount/GetCallHeader/GetCallPos (über
//     TAtlasIdeDebugSession.ReadStack, mit csWait unter LLDB).
//   - Schritte: IOTAProcess.Run(ormRunUntilReturn) setzt bis zur Rückkehr fort.
//   - Was der Benutzer gedrückt hat, meldet die OTA nicht. Den Schritt
//     „Einzelne Anweisung“ (F7) meldet TAtlasIdeDebugTrace, auch wenn Atlas
//     selbst hineinspringt (Schrittfilter #850); Atlas merkt ihn sich.
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
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Trace;

type
  TAtlasIdeDebugOwnCode = class
  public const
    /// <summary>Name des Empfängers bei TAtlasIdeDebugTrace.</summary>
    TraceHandler = 'OwnCode';
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
    TTicker = class
    public
      procedure StepTick(Sender: TObject);
      procedure JumpTick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
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
    class procedure Stepped; static;
    class procedure CheckStep; static;
    class procedure ScheduleJump; static;
    class procedure CheckJump; static;
    /// <summary>Darf der Sprung jetzt lesen? Hält den Zeitgeber an, wenn der Halt nicht mehr gilt.</summary>
    class function JumpReady: Boolean; static;
    /// <summary>Zum ersten eigenen Rahmen springen und es melden.</summary>
    class procedure JumpTo(const AFrames: TAtlasDebugFrames); static;
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
    /// <summary>Gemeldeter Schritt (TAtlasIdeDebugTrace): nur „Einzelne Anweisung“ zählt.</summary>
    class procedure Traced(AKind: TAtlasTraceKind); static;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Debug.Strings;

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
      begin
        FStepping := False;
      end;
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

class procedure TAtlasIdeDebugOwnCode.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FStepTimer = nil then
  begin
    FStepTimer := NewTimer(FTicker.StepTick);
  end;
  if FJumpTimer = nil then
  begin
    FJumpTimer := NewTimer(FTicker.JumpTick);
  end;
  TAtlasIdeDebugTrace.AddHandler(TraceHandler,
    procedure(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin)
    begin
      Traced(AKind);
    end);
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
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  TAtlasIdeDebugTrace.RemoveHandler(TraceHandler);
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
  Result := TAtlasIdeDebugTrace.Hooked(TAtlasTraceKind.TraceInto);
end;

class procedure TAtlasIdeDebugOwnCode.Traced(AKind: TAtlasTraceKind);
begin
  if AKind = TAtlasTraceKind.TraceInto then
  begin
    Stepped;
  end;
end;

class procedure TAtlasIdeDebugOwnCode.ToggleSetting(const AMessage: TProc<string>);
var
  Next: TAtlasPluginSettings;
begin
  Next := TAtlasIdeSettings.Stored;
  Next.DebugJustMyCode := not Next.DebugJustMyCode;
  TAtlasIdeSettings.Update(Next);
  if Assigned(AMessage) then
  begin
    if Next.DebugJustMyCode then
    begin
      AMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugJustMyCodeOn));
    end
    else
    begin
      AMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugJustMyCodeOff));
    end;
  end;
end;

class procedure TAtlasIdeDebugOwnCode.Stepped;
begin
  if not TAtlasIdeSettings.Current.DebugJustMyCode or (TAtlasIdeDebugSession.StoppedThread = nil) then
  begin
    Exit;
  end;
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
  begin
    Exit(TAtlasDebugStackRead.None);
  end;
  Result := TAtlasIdeDebugSession.ReadStack(Thread, TAtlasDebugCallStack.MaxFrames, AFrames);
  if Result = TAtlasDebugStackRead.Ready then
  begin
    TAtlasIdeDebugSources.MarkFrames(AFrames);
  end;
end;

class procedure TAtlasIdeDebugOwnCode.CheckStep;
var
  Frames: TAtlasDebugFrames;
begin
  FStepTimer.Enabled := False;
  if not FStepping then
  begin
    Exit;
  end;
  case ReadFrames(Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FStepRetries);
        if FStepRetries <= StackRetries then
        begin
          FStepTimer.Enabled := True;
        end
        else
        begin
          FStepping := False;
        end;
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
  begin
    FStepping := False;
  end;
end;

class procedure TAtlasIdeDebugOwnCode.ScheduleJump;
begin
  if not TAtlasIdeSettings.Current.DebugJustMyCode then
  begin
    Exit;
  end;
  FJumpStop := TAtlasIdeDebugSession.StopCount;
  FJumpStarted := TThread.GetTickCount64;
  FJumpQuiet := 0;
  FJumpRetries := 0;
  FJumpTimer.Enabled := True;
end;

class function TAtlasIdeDebugOwnCode.JumpReady: Boolean;
begin
  Result := False;
  // Weitergelaufen (Fortsetzen, still fortgesetzt) oder neuer Halt: kein Sprung.
  if (TAtlasIdeDebugSession.StopCount <> FJumpStop) or (TAtlasIdeDebugSession.StoppedThread = nil) or
    (TThread.GetTickCount64 - FJumpStarted > JumpWaitMs) then
  begin
    FJumpTimer.Enabled := False;
  end
  // Erst wenn der Exception-Dialog zu ist und die IDE ihren Ort gezeigt hat (zwei ruhige Takte).
  else if Application.ModalLevel > 0 then
  begin
    FJumpQuiet := 0;
  end
  else
  begin
    Inc(FJumpQuiet);
    Result := FJumpQuiet >= 2;
  end;
end;

class procedure TAtlasIdeDebugOwnCode.JumpTo(const AFrames: TAtlasDebugFrames);
var
  mIndex: Integer;
begin
  mIndex := TAtlasDebugOwnCode.JumpIndex(AFrames, TAtlasIdeSettings.Current.DebugJustMyCode);
  if mIndex < 0 then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.MarkLine(AFrames[mIndex].FileName, AFrames[mIndex].Line - 1);
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugJustMyCodeJumped,
      [ExtractFileName(AFrames[mIndex].FileName), AFrames[mIndex].Line, mIndex]));
  end;
end;

class procedure TAtlasIdeDebugOwnCode.CheckJump;
var
  Frames: TAtlasDebugFrames;
begin
  if not JumpReady then
  begin
    Exit;
  end;
  case ReadFrames(Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FJumpRetries);
        if FJumpRetries > StackRetries then
        begin
          FJumpTimer.Enabled := False;
        end;
      end;
    TAtlasDebugStackRead.None:
      FJumpTimer.Enabled := False;
  else
    begin
      FJumpTimer.Enabled := False;
      JumpTo(Frames);
    end;
  end;
end;

end.
