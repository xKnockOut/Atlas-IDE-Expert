unit Atlas.IDE.Debug.AccessViolation;

// Zugriffsverletzung erklären (#865) in der IDE:
//   - Auslöser: Halt wegen einer Exception aus dem Exception-Verlauf (#517). Atlas prüft nur
//     EAccessViolation bzw. EExternalException mit C0000005 (TAtlasAvMessage) und nur, wenn der oberste
//     Rahmen eigener Code mit Quelltext ist (#578): Dort steht der Ausführungspunkt, und dort wertet der
//     Debugger aus. Liegt der Fehler in der RTL oder ohne Quelltext, bleibt es bei der Meldung.
//   - Warten: wie die Exception-Leiste, bis kein modales Fenster (Dialog der IDE) mehr offen ist und der Prozess
//     noch am selben Halt steht; ShowWaitMs höchstens.
//   - Zerlegen: atlas/accessChains (TLspSession.AccessChains) im Hintergrund-Thread; den Text der Datei gleicht
//     Atlas vorher im Hauptthread ab. Startet keinen Server.
//   - Auswerten: TAtlasAvAnalysis fragt, Atlas antwortet über TAtlasIdeDebugValues im Hauptthread in
//     Zeitscheiben von höchstens SliceMs (wie die Werte im Editor, #508); verzögerte Antworten (LLDB)
//     höchstens DeferredTimeoutMs. Ohne debug.explainAccessViolation.allowCalls ohne Nebenwirkungen (eseNone):
//     Glieder mit Getter oder Aufruf bleiben „nicht ausgewertet“.
//   - Ergebnis: in der Exception-Leiste (TAtlasIdeDebugExceptionBar.Explain), sonst (debug.exceptionBanner aus)
//     als Zeilen in den Meldungen. Das schuldige Glied unterstreicht Atlas im Editor, bis weitergelaufen wird.
//   - Knöpfe der Leiste: „Wo wird X zugewiesen?“ (OnWhereAssigned, #690), „Ausdruck auswerten“ (OnEvaluate,
//     #784), „Erklärung kopieren“. Was die ersten beiden tun, setzt die Zusammensetzung.
//   - Fortsetzen, neuer Halt, Ende der Sitzung verwerfen Ergebnis, Unterstreichung und laufende Arbeit.
// Ohne debug.explainAccessViolation ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Debug.AccessViolation,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Hover.DebugValue,
  Atlas.UI.Debug.ExceptionBar;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasAvSessionFunc = reference to function: TLspSession;
  /// <summary>„Wo wird AName zugewiesen?“ an der Stelle des Namens (0-basiert).</summary>
  TAtlasAvWhereAssignedProc = reference to procedure(const AFileName: string; ALine, ACharacter: Integer;
    const AName: string);
  TAtlasAvEvaluateProc = reference to procedure(const AExpression: string);

  TAtlasIdeDebugAccessViolation = class
  public const
    SliceMs = 30;
    TickMs = 10;
    WaitMs = 100;
    /// <summary>So lange wartet Atlas höchstens, bis der Dialog der IDE zu ist.</summary>
    ShowWaitMs = 120000;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    DeferredTimeoutMs = 2000;
    RequestTimeoutMs = 5000;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Wait, Request, Evaluate);
    {$SCOPEDENUMS OFF}
  private class var
    FInstance: TAtlasIdeDebugAccessViolation;
  private
    FSession: TAtlasAvSessionFunc;
    FMessage: TProc<string>;
    FOnWhereAssigned: TAtlasAvWhereAssignedProc;
    FOnEvaluate: TAtlasAvEvaluateProc;
    FListener: IAtlasIdeDebugListener;
    FHandler: Integer;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FWorkers: TList<TThread>;
    FEvaluator: TAtlasIdeDebugValues;
    FAnalysis: TAtlasAvAnalysis;
    FPhase: TPhase;
    FStop: Integer;
    FRequest: Integer;
    FSince: UInt64;
    FQuiet: Integer;
    FDeferred: Boolean;
    FWaitAt: UInt64;
    FInternal: Boolean;
    FException: TAtlasDebugException;
    FAccess: TAtlasAvMessage;
    FFileName: string;
    FLine: Integer;
    FPointerSize: Integer;
    FLines: TArray<string>;
    FExplanation: TAtlasDebugBannerExplanation;
    FCulprit: TAtlasAvLink;
    FHasCulprit: Boolean;
    FUnderline: Boolean;
    FUnderlineLine: Integer;
    FUnderlineStart: Integer;
    FUnderlineEnd: Integer;
    constructor Create(const ASession: TAtlasAvSessionFunc; const AMessage: TProc<string>);
    procedure ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
    procedure Drop;
    procedure Tick(Sender: TObject);
    procedure CheckWait;
    procedure Ask;
    procedure Accept(ARequest: Integer; const AChains: TAtlasAvChains);
    procedure EvaluateSlice;
    procedure DeferredDone(const AValue: TAtlasDebugValue);
    procedure Finish;
    procedure Publish(const AExplanation: TAtlasDebugBannerExplanation);
    procedure RunAction(AAction: TAtlasDebugBarAction);
    procedure EndInternal;
    function StillStopped: Boolean;
    function Header: string;
    function Place: string;
    procedure ReapWorkers(AWait: Boolean);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    destructor Destroy; override;
    class procedure Start(const ASession: TAtlasAvSessionFunc; const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.explainAccessViolation an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Knopf „Wo wird X zugewiesen?“; nil = kein Knopf.</summary>
    class procedure SetWhereAssigned(const AProc: TAtlasAvWhereAssignedProc); static;
    /// <summary>Knopf „Ausdruck auswerten“; nil = kein Knopf.</summary>
    class procedure SetEvaluate(const AProc: TAtlasAvEvaluateProc); static;
  end;

implementation

uses
  System.Math,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.UI.Debug.AccessViolation,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasIdeDebugAccessViolation.TListener }

procedure TAtlasIdeDebugAccessViolation.TListener.DebugStarted;
begin
  if FInstance <> nil then
    FInstance.Drop;
end;

procedure TAtlasIdeDebugAccessViolation.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  // Neuer Halt: Das Ergebnis des alten gilt nicht mehr; ExceptionTaken kommt danach, wenn es eine Exception ist.
  if (FInstance <> nil) and (TAtlasIdeDebugSession.StopCount <> FInstance.FStop) then
    FInstance.Drop;
end;

procedure TAtlasIdeDebugAccessViolation.TListener.DebugResumed;
begin
  if FInstance <> nil then
    FInstance.Drop;
end;

procedure TAtlasIdeDebugAccessViolation.TListener.DebugEnded;
begin
  if FInstance <> nil then
    FInstance.Drop;
end;

{ TAtlasIdeDebugAccessViolation.TEvents }

function TAtlasIdeDebugAccessViolation.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeDebugAccessViolation.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugAccessViolation }

constructor TAtlasIdeDebugAccessViolation.Create(const ASession: TAtlasAvSessionFunc; const AMessage: TProc<string>);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FIndex := -1;
  FEvaluator := TAtlasIdeDebugValues.Create;
  FWorkers := TList<TThread>.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeDebugAccessViolation.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  if FEvents <> nil then
    FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  FreeAndNil(FTimer);
  FEvaluator.Cancel;
  EndInternal;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FreeAndNil(FEvaluator);
  FreeAndNil(FAnalysis);
  FLines := nil;
  FMessage := nil;
  FSession := nil;
  FOnWhereAssigned := nil;
  FOnEvaluate := nil;
  inherited Destroy;
end;

class procedure TAtlasIdeDebugAccessViolation.Start(const ASession: TAtlasAvSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugAccessViolation.Create(ASession, AMessage);
    FInstance.FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FInstance.FListener);
    FInstance.FHandler := TAtlasIdeDebugExceptions.AddExceptionHandler(
      procedure(const AStop: TAtlasDebugExceptionStop)
      begin
        if FInstance <> nil then
          FInstance.ExceptionTaken(AStop);
      end);
    TAtlasIdeDebugExceptionBar.SetExplanationHandler(
      procedure(AAction: TAtlasDebugBarAction)
      begin
        if FInstance <> nil then
          FInstance.RunAction(AAction);
      end);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugAccessViolation.Release;
var
  Instance: TAtlasIdeDebugAccessViolation;
begin
  if FInstance = nil then
    Exit;
  Instance := FInstance;
  Instance.Drop;
  FInstance := nil;
  // Abgeschaltet: Die Leiste zeigt wieder nur die Meldung.
  TAtlasIdeDebugExceptionBar.Explain(Instance.FStop, Default(TAtlasDebugBannerExplanation));
  TAtlasIdeDebugExceptionBar.SetExplanationHandler(nil);
  if Instance.FHandler <> 0 then
    TAtlasIdeDebugExceptions.RemoveExceptionHandler(Instance.FHandler);
  if Instance.FListener <> nil then
    TAtlasIdeDebugSession.RemoveListener(Instance.FListener);
  Instance.FListener := nil;
  Instance.Free;
  Invalidate;
end;

class function TAtlasIdeDebugAccessViolation.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugAccessViolation.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.DebugExplainAccessViolation;
end;

class procedure TAtlasIdeDebugAccessViolation.SetWhereAssigned(const AProc: TAtlasAvWhereAssignedProc);
begin
  if FInstance <> nil then
    FInstance.FOnWhereAssigned := AProc;
end;

class procedure TAtlasIdeDebugAccessViolation.SetEvaluate(const AProc: TAtlasAvEvaluateProc);
begin
  if FInstance <> nil then
    FInstance.FOnEvaluate := AProc;
end;

class procedure TAtlasIdeDebugAccessViolation.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

procedure TAtlasIdeDebugAccessViolation.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

function TAtlasIdeDebugAccessViolation.StillStopped: Boolean;
begin
  Result := (TAtlasIdeDebugSession.StopCount = FStop) and (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeDebugAccessViolation.Drop;
var
  Underlined: Boolean;
begin
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FRequest);
  if FTimer <> nil then
    FTimer.Enabled := False;
  if FDeferred then
    FEvaluator.Cancel;
  FDeferred := False;
  EndInternal;
  FreeAndNil(FAnalysis);
  FPhase := TPhase.Idle;
  FExplanation := Default(TAtlasDebugBannerExplanation);
  FCulprit := Default(TAtlasAvLink);
  FHasCulprit := False;
  Underlined := FUnderline;
  FUnderline := False;
  FLines := nil;
  ReapWorkers(False);
  if Underlined then
    Invalidate;
end;

procedure TAtlasIdeDebugAccessViolation.ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
var
  Frames: TAtlasDebugFrames;
begin
  Drop;
  if AStop.Continued or not Enabled then
    Exit;
  FAccess := TAtlasAvMessage.Parse(AStop.Exception.ExceptionClass, AStop.Exception.Message);
  if not FAccess.IsAccessViolation then
    Exit;
  Frames := AStop.Frames;
  // Der Debugger wertet im obersten Rahmen aus: Nur wenn der eigener Code mit Quelltext ist, passt die Zeile.
  if (Length(Frames) = 0) or not Frames[0].HasSource or not Frames[0].Own then
  begin
    TAtlasGuard.Log('Zugriffsverletzung erklären: Halt nicht in eigenem Code mit Quelltext; nur die Meldung');
    Exit;
  end;
  FException := AStop.Exception;
  FStop := AStop.Stop;
  FFileName := Frames[0].FileName;
  FLine := Frames[0].Line - 1;
  FPointerSize := TAtlasAvJson.PointerSize(TAtlasIdeDebugSession.LaunchPlatform);
  FSince := TThread.GetTickCount64;
  FQuiet := 0;
  FPhase := TPhase.Wait;
  TAtlasIdeDebugExceptionBar.Explain(FStop, TAtlasAvTexts.Busy);
  FTimer.Interval := WaitMs;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDebugAccessViolation.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  try
    case FPhase of
      TPhase.Wait:
        CheckWait;
      TPhase.Evaluate:
        EvaluateSlice;
    else
      FTimer.Enabled := False;
    end;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.CheckWait;
begin
  // Weitergelaufen, neuer Halt, Sitzung zu oder zu lange gewartet: nichts.
  if not StillStopped or (TThread.GetTickCount64 - FSince > ShowWaitMs) then
  begin
    Drop;
    Exit;
  end;
  // Erst wenn kein Dialog mehr offen ist (zwei ruhige Takte); solange könnte der Benutzer noch fortsetzen.
  if Application.ModalLevel > 0 then
  begin
    FQuiet := 0;
    Exit;
  end;
  Inc(FQuiet);
  if FQuiet < 2 then
    Exit;
  FTimer.Enabled := False;
  Ask;
end;

procedure TAtlasIdeDebugAccessViolation.Ask;
var
  Session: TLspSession;
  Buffer: IOTAEditBuffer;
  FileName, Text: string;
  Line, PointerSize, Request: Integer;
  Worker: TThread;
begin
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
  begin
    Publish(TAtlasAvTexts.Failed(TAtlasStrings.Text(TAtlasTextId.DebugAvNoServer), Header));
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Buffer := TAtlasIdeFiles.BufferOf(FFileName);
  if Buffer <> nil then
  begin
    FFileName := Buffer.FileName;
    Text := TAtlasEditorBuffer.Text(Buffer);
    FLines := Text.Split([#13#10, #10]);
    Session.Sync(FFileName, Text);
  end;
  FileName := FFileName;
  Line := FLine;
  PointerSize := FPointerSize;
  ReapWorkers(False);
  Inc(FRequest);
  Request := FRequest;
  FPhase := TPhase.Request;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Chains: TAtlasAvChains;
    begin
      Chains := Default(TAtlasAvChains);
      try
        Chains := Session.AccessChains(FileName, Line, PointerSize, RequestTimeoutMs);
      except
        // Server langsam oder weg: keine Ketten.
        Chains := Default(TAtlasAvChains);
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.Debugger,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Accept(Request, Chains);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

procedure TAtlasIdeDebugAccessViolation.Accept(ARequest: Integer; const AChains: TAtlasAvChains);
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FRequest) or (FPhase <> TPhase.Request) then
    Exit;
  if not StillStopped or not Enabled then
  begin
    Drop;
    Exit;
  end;
  if not AChains.Found then
  begin
    Publish(TAtlasAvTexts.Failed(TAtlasStrings.Text(TAtlasTextId.DebugAvNoServer), Header));
    Exit;
  end;
  if AChains.Chains = nil then
  begin
    Publish(TAtlasAvTexts.Failed(TAtlasStrings.Text(TAtlasTextId.DebugAvNoChains), Header));
    Exit;
  end;
  FAnalysis := TAtlasAvAnalysis.Create(AChains, FAccess, FPointerSize,
    TAtlasIdeSettings.Current.DebugExplainAccessViolationAllowCalls);
  FPhase := TPhase.Evaluate;
  FTimer.Interval := TickMs;
  FTimer.Enabled := True;
  EvaluateSlice;
end;

procedure TAtlasIdeDebugAccessViolation.EvaluateSlice;
var
  StartedAt: UInt64;
  Request: TAtlasAvRequest;
  Value: TAtlasDebugValue;
begin
  if (FAnalysis = nil) or not StillStopped then
  begin
    Drop;
    Exit;
  end;
  // Verzögerter Wert (LLDB): höchstens DeferredTimeoutMs warten, dann als Fehler weiter.
  if FDeferred then
  begin
    if TThread.GetTickCount64 - FWaitAt < DeferredTimeoutMs then
      Exit;
    FEvaluator.Cancel;
    EndInternal;
    FDeferred := False;
    FAnalysis.Answer(False, TAtlasStrings.Text(TAtlasTextId.DebugEvaluateTimeout));
  end;
  StartedAt := TThread.GetTickCount64;
  while TThread.GetTickCount64 - StartedAt < SliceMs do
  begin
    if not FAnalysis.Next(Request) then
    begin
      Finish;
      Exit;
    end;
    // Eigene Auswertung: Zustandswechsel dabei sind kein Fortsetzen (TAtlasIdeDebugSession).
    Value := Default(TAtlasDebugValue);
    TAtlasIdeDebugSession.BeginInternal;
    FInternal := True;
    try
      Value := FEvaluator.Evaluate(Request.Expression, FFileName, FLine + 1, Request.SideEffects, DeferredDone);
    finally
      if Value.State <> TAtlasDebugValueState.Pending then
        EndInternal;
    end;
    case Value.State of
      TAtlasDebugValueState.Pending:
        begin
          FDeferred := True;
          FWaitAt := TThread.GetTickCount64;
          Exit;
        end;
      TAtlasDebugValueState.Value:
        FAnalysis.Answer(True, Value.Text);
      TAtlasDebugValueState.Failed:
        FAnalysis.Answer(False, Value.Text);
    else
      // Kein angehaltener Prozess mehr.
      Drop;
      Exit;
    end;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.DeferredDone(const AValue: TAtlasDebugValue);
begin
  if not FDeferred or (FAnalysis = nil) then
    Exit;
  EndInternal;
  FDeferred := False;
  FAnalysis.Answer(AValue.State = TAtlasDebugValueState.Value, AValue.Text);
end;

function TAtlasIdeDebugAccessViolation.Place: string;
begin
  Result := Format('%s:%d', [ExtractFileName(FFileName), FLine + 1]);
end;

function TAtlasIdeDebugAccessViolation.Header: string;
begin
  Result := FException.ExceptionClass;
  if FException.Message <> '' then
    Result := Result + ': ' + FException.Message;
  Result := Result + ' (' + Place + ')';
end;

procedure TAtlasIdeDebugAccessViolation.Finish;
var
  Verdict: TAtlasAvVerdict;
  Settings: TAtlasPluginSettings;
begin
  FTimer.Enabled := False;
  FPhase := TPhase.Idle;
  Settings := TAtlasIdeSettings.Current;
  Verdict := FAnalysis.Verdict;
  FCulprit := Verdict.Culprit;
  FHasCulprit := Verdict.HasCulprit;
  // Unterstreichen: das schuldige Glied in seiner ersten Zeile.
  if FHasCulprit and (FLines <> nil) and (FCulprit.StartLine >= 0) and (FCulprit.StartLine <= High(FLines)) then
  begin
    FUnderline := True;
    FUnderlineLine := FCulprit.StartLine;
    FUnderlineStart := FCulprit.StartCharacter;
    if FCulprit.EndLine = FCulprit.StartLine then
      FUnderlineEnd := FCulprit.EndCharacter
    else
      FUnderlineEnd := Length(TrimRight(FLines[FUnderlineLine]));
    Invalidate;
  end;
  Publish(TAtlasAvTexts.FromAnalysis(FAnalysis, Assigned(FOnWhereAssigned) and Settings.DataFlow,
    Assigned(FOnEvaluate) and Settings.DebugEvaluateWindow, Header));
end;

procedure TAtlasIdeDebugAccessViolation.Publish(const AExplanation: TAtlasDebugBannerExplanation);
var
  Line: string;
begin
  FTimer.Enabled := False;
  FPhase := TPhase.Idle;
  FExplanation := AExplanation;
  TAtlasGuard.Log('Zugriffsverletzung erklären: ' + AExplanation.Headline + ' ' + AExplanation.Detail);
  // Steht (oder kommt) die Leiste für diesen Halt, zeigt sie die Erklärung; sonst die Meldungen.
  if TAtlasIdeDebugExceptionBar.Covers(FStop) then
    TAtlasIdeDebugExceptionBar.Explain(FStop, AExplanation)
  else if Assigned(FMessage) then
    for Line in TAtlasAvTexts.MessageLines(AExplanation, Place) do
      FMessage(Line);
end;

procedure TAtlasIdeDebugAccessViolation.RunAction(AAction: TAtlasDebugBarAction);
begin
  if not FExplanation.Active or FExplanation.Busy then
    Exit;
  case AAction of
    TAtlasDebugBarAction.WhereAssigned:
      if FHasCulprit and Assigned(FOnWhereAssigned) then
        FOnWhereAssigned(FFileName, FCulprit.NameLine, FCulprit.NameCharacter, FCulprit.Name);
    TAtlasDebugBarAction.Evaluate:
      if Assigned(FOnEvaluate) and (FExplanation.EvaluateExpression <> '') then
        FOnEvaluate(FExplanation.EvaluateExpression);
    TAtlasDebugBarAction.CopyExplanation:
      if FExplanation.CopyText <> '' then
        Clipboard.AsText := FExplanation.CopyText;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
    Exit;
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

procedure TAtlasIdeDebugAccessViolation.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  TabWidth, Thickness, Y: Integer;
  Stored: string;
  First, Last: TRect;
  Sample: COLORREF;
  DC: HDC;
  Saved: Integer;
  Pen: HPEN;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FUnderline then
    Exit;
  try
    if (Context.LogicalLineNum - 1 <> FUnderlineLine) or not SameText(Context.FileName, FFileName) or
      (FUnderlineLine > High(FLines)) then
      Exit;
    LineState := Context.LineState;
    if (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) then
      Exit;
    Stored := FLines[FUnderlineLine];
    TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    // Nur, wenn die Zeile im Editor der abgeglichenen entspricht.
    if TrimRight(TAtlasPairs.DisplayLine(LineState.Text, TabWidth)) <>
      TrimRight(TAtlasPairs.DisplayLine(Stored, TabWidth)) then
      Exit;
    First := Context.EditorState.GetCharacterPosPx(ColumnOf(Stored, FUnderlineStart, TabWidth),
      Context.EditorLineNum);
    Last := Context.EditorState.GetCharacterPosPx(ColumnOf(Stored, FUnderlineEnd, TabWidth), Context.EditorLineNum);
    if Last.Left <= First.Left then
      Exit;
    DC := Context.Canvas.Handle;
    Sample := GetPixel(DC, First.Left, Rect.Top + 1);
    if Sample = CLR_INVALID then
      Sample := COLORREF(ColorToRGB(Context.Canvas.Brush.Color));
    // Fehlerfarbe zum Hintergrund, doppelt so dick wie eine Wellenlinie der Diagnosen.
    Thickness := Max(2, (Rect.Bottom - Rect.Top) div 8);
    Y := Rect.Bottom - Thickness;
    // Reines GDI zwischen SaveDC und RestoreDC; der Stift erst nach RestoreDC löschen (dann nicht mehr gewählt).
    Pen := CreatePen(PS_SOLID, Thickness,
      COLORREF(ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(Sample)).Error))));
    Saved := SaveDC(DC);
    try
      SelectObject(DC, Pen);
      MoveToEx(DC, First.Left, Y, nil);
      LineTo(DC, Last.Left, Y);
    finally
      RestoreDC(DC, Saved);
      DeleteObject(Pen);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

end.
