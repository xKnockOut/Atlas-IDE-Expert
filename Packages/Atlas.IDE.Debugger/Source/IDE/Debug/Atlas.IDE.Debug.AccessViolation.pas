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
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Debug.AccessViolation,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.AccessViolationUnderline,
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
    cSliceMs = 30;
    cTickMs = 10;
    cWaitMs = 100;
    /// <summary>So lange wartet Atlas höchstens, bis der Dialog der IDE zu ist.</summary>
    cShowWaitMs = 120000;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    cDeferredTimeoutMs = 2000;
    cRequestTimeoutMs = 5000;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Wait, Request, Evaluate);
    /// <summary>Nach einer Antwort: weiter, auf den verzögerten Wert warten oder fertig bzw. verworfen.</summary>
    TSliceStep = (Next, Wait, Stopped);
    {$SCOPEDENUMS OFF}
    THooks = record
      Session: TAtlasAvSessionFunc;
      Message: TProc<string>;
      WhereAssigned: TAtlasAvWhereAssignedProc;
      Evaluate: TAtlasAvEvaluateProc;
    end;
    TProgress = record
      Phase: TPhase;
      Stop: Integer;
      Request: Integer;
      Since: UInt64;
      Quiet: Integer;
    end;
    /// <summary>Verzögerter Wert (LLDB) und seit wann Atlas auf ihn wartet.</summary>
    TDeferred = record
      Active: Boolean;
      Since: UInt64;
    end;
    /// <summary>Was zum Halt gehört: Exception, Meldung, Ort, Zeigergröße und abgeglichener Text der Datei.
    /// </summary>
    TStopFacts = record
      Exception: TAtlasDebugException;
      Access: TAtlasAvMessage;
      FileName: string;
      Line: Integer;
      PointerSize: Integer;
      Lines: TArray<string>;
      /// <summary>„Datei:Zeile“ (1-basiert).</summary>
      function Place: string;
      /// <summary>Klasse, Meldung und Ort für die Überschrift.</summary>
      function Header: string;
    end;
    TOutcome = record
      Explanation: TAtlasDebugBannerExplanation;
      Culprit: TAtlasAvLink;
      HasCulprit: Boolean;
    end;
  private class var
    FInstance: TAtlasIdeDebugAccessViolation;
  private
    FHooks: THooks;
    FListener: IAtlasIdeDebugListener;
    FHandler: Integer;
    FTimer: TTimer;
    FWorkers: TList<TThread>;
    FEvaluator: TAtlasIdeDebugValues;
    FAnalysis: TAtlasAvAnalysis;
    FProgress: TProgress;
    FDeferred: TDeferred;
    FInternal: Boolean;
    FFacts: TStopFacts;
    FOutcome: TOutcome;
    FUnderline: TAtlasIdeAvUnderline;
    constructor Create(const ASession: TAtlasAvSessionFunc; const AMessage: TProc<string>);
    procedure ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
    procedure Drop;
    procedure Tick(Sender: TObject);
    procedure CheckWait;
    procedure Ask;
    procedure Accept(ARequest: Integer; const AChains: TAtlasAvChains);
    procedure EvaluateSlice;
    /// <summary>Wartet Atlas noch auf den verzögerten Wert? Nach DeferredTimeoutMs als Fehler weiter.</summary>
    function DeferredPending: Boolean;
    function EvaluateOne(const ARequest: TAtlasAvRequest): TSliceStep;
    /// <summary>atlas/accessChains im Hintergrund; die Antwort geht an Accept.</summary>
    procedure Fetch(ASession: TLspSession);
    procedure DeferredDone(const AValue: TAtlasDebugValue);
    procedure Finish;
    procedure Publish(const AExplanation: TAtlasDebugBannerExplanation);
    procedure RunAction(AAction: TAtlasDebugBarAction);
    procedure EndInternal;
    function StillStopped: Boolean;
    procedure ReapWorkers(AWait: Boolean);
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
  Atlas.Core.Debug.CallStack,
  Vcl.Forms,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.UI.Debug.AccessViolation,
  Atlas.UI.Debug.Strings,
  Atlas.Text.LogMarks;

{ TAtlasIdeDebugAccessViolation.TListener }

procedure TAtlasIdeDebugAccessViolation.TListener.DebugStarted;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  // Neuer Halt: Das Ergebnis des alten gilt nicht mehr; ExceptionTaken kommt danach, wenn es eine Exception ist.
  if (FInstance <> nil) and (TAtlasIdeDebugSession.StopCount <> FInstance.FProgress.Stop) then
  begin
    FInstance.Drop;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.TListener.DebugResumed;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.TListener.DebugEnded;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop;
  end;
end;

{ TAtlasIdeDebugAccessViolation }

constructor TAtlasIdeDebugAccessViolation.Create(const ASession: TAtlasAvSessionFunc; const AMessage: TProc<string>);
begin
  inherited Create;
  FHooks.Session := ASession;
  FHooks.Message := AMessage;
  FEvaluator := TAtlasIdeDebugValues.Create;
  FWorkers := TList<TThread>.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FUnderline := TAtlasIdeAvUnderline.Create;
end;

destructor TAtlasIdeDebugAccessViolation.Destroy;
begin
  FreeAndNil(FUnderline);
  FreeAndNil(FTimer);
  FEvaluator.Cancel;
  EndInternal;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FreeAndNil(FEvaluator);
  FreeAndNil(FAnalysis);
  FFacts.Lines := nil;
  FHooks.Message := nil;
  FHooks.Session := nil;
  FHooks.WhereAssigned := nil;
  FHooks.Evaluate := nil;
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
        begin
          FInstance.ExceptionTaken(AStop);
        end;
      end);
    TAtlasIdeDebugExceptionBar.SetExplanationHandler(
      procedure(AAction: TAtlasDebugBarAction)
      begin
        if FInstance <> nil then
        begin
          FInstance.RunAction(AAction);
        end;
      end);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugAccessViolation.Release;
var
  mInstance: TAtlasIdeDebugAccessViolation;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  mInstance.Drop;
  FInstance := nil;
  // Abgeschaltet: Die Leiste zeigt wieder nur die Meldung.
  TAtlasIdeDebugExceptionBar.Explain(mInstance.FProgress.Stop, Default(TAtlasDebugBannerExplanation));
  TAtlasIdeDebugExceptionBar.SetExplanationHandler(nil);
  if mInstance.FHandler <> 0 then
  begin
    TAtlasIdeDebugExceptions.RemoveExceptionHandler(mInstance.FHandler);
  end;
  if mInstance.FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(mInstance.FListener);
  end;
  mInstance.FListener := nil;
  mInstance.Free;
  TAtlasIdeAvUnderline.Invalidate;
end;

class function TAtlasIdeDebugAccessViolation.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugAccessViolation.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.DebugExplainAccessViolation;
end;

class procedure TAtlasIdeDebugAccessViolation.SetWhereAssigned(const AProc: TAtlasAvWhereAssignedProc);
begin
  if FInstance <> nil then
  begin
    FInstance.FHooks.WhereAssigned := AProc;
  end;
end;

class procedure TAtlasIdeDebugAccessViolation.SetEvaluate(const AProc: TAtlasAvEvaluateProc);
begin
  if FInstance <> nil then
  begin
    FInstance.FHooks.Evaluate := AProc;
  end;
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
  Result := (TAtlasIdeDebugSession.StopCount = FProgress.Stop) and (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeDebugAccessViolation.Drop;
begin
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FProgress.Request);
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  if FDeferred.Active then
  begin
    FEvaluator.Cancel;
  end;
  FDeferred.Active := False;
  EndInternal;
  FreeAndNil(FAnalysis);
  FProgress.Phase := TPhase.Idle;
  FOutcome.Explanation := Default(TAtlasDebugBannerExplanation);
  FOutcome.Culprit := Default(TAtlasAvLink);
  FOutcome.HasCulprit := False;
  FFacts.Lines := nil;
  ReapWorkers(False);
  if (FUnderline <> nil) and FUnderline.Clear then
  begin
    TAtlasIdeAvUnderline.Invalidate;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
var
  mFrames: TAtlasDebugFrames;
begin
  Drop;
  if AStop.Continued or not Enabled then
  begin
    Exit;
  end;
  FFacts.Access := TAtlasAvMessage.Parse(AStop.Exception.ExceptionClass, AStop.Exception.Message);
  if not FFacts.Access.IsAccessViolation then
  begin
    Exit;
  end;
  mFrames := AStop.Frames;
  // Der Debugger wertet im obersten Rahmen aus: Nur wenn der eigener Code mit Quelltext ist, passt die Zeile.
  if (Length(mFrames) = 0) or not mFrames[0].HasSource or not mFrames[0].Own then
  begin
    TAtlasGuard.Log('Zugriffsverletzung erklären: Halt nicht in eigenem Code mit Quelltext; nur die Meldung');
    Exit;
  end;
  FFacts.Exception := AStop.Exception;
  FProgress.Stop := AStop.Stop;
  FFacts.FileName := mFrames[0].FileName;
  FFacts.Line := mFrames[0].Line - 1;
  FFacts.PointerSize := TAtlasAvJson.PointerSize(TAtlasIdeDebugSession.LaunchPlatform);
  FProgress.Since := TThread.GetTickCount64;
  FProgress.Quiet := 0;
  FProgress.Phase := TPhase.Wait;
  TAtlasIdeDebugExceptionBar.Explain(FProgress.Stop, TAtlasAvTexts.Busy);
  FTimer.Interval := cWaitMs;
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
    case FProgress.Phase of
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
  if not StillStopped or (TThread.GetTickCount64 - FProgress.Since > cShowWaitMs) then
  begin
    Drop;
    Exit;
  end;
  // Erst wenn kein Dialog mehr offen ist (zwei ruhige Takte); solange könnte der Benutzer noch fortsetzen.
  if Application.ModalLevel > 0 then
  begin
    FProgress.Quiet := 0;
    Exit;
  end;
  Inc(FProgress.Quiet);
  if FProgress.Quiet < 2 then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  Ask;
end;

procedure TAtlasIdeDebugAccessViolation.Ask;
var
  mSession: TLspSession;
  mBuffer: IOTAEditBuffer;
  mText: string;
begin
  mSession := nil;
  if Assigned(FHooks.Session) then
  begin
    mSession := FHooks.Session();
  end;
  if mSession = nil then
  begin
    Publish(TAtlasAvTexts.Failed(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvNoServer), FFacts.Header));
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mBuffer := TAtlasIdeFiles.BufferOf(FFacts.FileName);
  if mBuffer <> nil then
  begin
    FFacts.FileName := mBuffer.FileName;
    mText := TAtlasEditorBuffer.Text(mBuffer);
    FFacts.Lines := mText.Split([#13#10, #10]);
    mSession.Sync(FFacts.FileName, mText);
  end;
  Fetch(mSession);
end;

procedure TAtlasIdeDebugAccessViolation.Fetch(ASession: TLspSession);
var
  mFileName: string;
  mLine, mPointerSize, mRequest: Integer;
  mWorker: TThread;
begin
  mFileName := FFacts.FileName;
  mLine := FFacts.Line;
  mPointerSize := FFacts.PointerSize;
  ReapWorkers(False);
  Inc(FProgress.Request);
  mRequest := FProgress.Request;
  FProgress.Phase := TPhase.Request;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mChains: TAtlasAvChains;
    begin
      mChains := Default(TAtlasAvChains);
      try
        mChains := ASession.AccessChains(mFileName, mLine, mPointerSize, cRequestTimeoutMs);
      except
        // Server langsam oder weg: keine Ketten.
        mChains := Default(TAtlasAvChains);
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen.
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          if FInstance <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.Debugger,
              procedure
              begin
                if FInstance <> nil then
                begin
                  FInstance.Accept(mRequest, mChains);
                end;
              end);
          end;
        end);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TAtlasIdeDebugAccessViolation.Accept(ARequest: Integer; const AChains: TAtlasAvChains);
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FProgress.Request) or (FProgress.Phase <> TPhase.Request) then
  begin
    Exit;
  end;
  if not StillStopped or not Enabled then
  begin
    Drop;
    Exit;
  end;
  if not AChains.Found then
  begin
    Publish(TAtlasAvTexts.Failed(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvNoServer), FFacts.Header));
    Exit;
  end;
  if AChains.Chains = nil then
  begin
    Publish(TAtlasAvTexts.Failed(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvNoChains), FFacts.Header));
    Exit;
  end;
  FAnalysis := TAtlasAvAnalysis.Create(AChains, FFacts.Access, FFacts.PointerSize,
    TAtlasIdeSettings.Current.DebugExplainAccessViolationAllowCalls);
  FProgress.Phase := TPhase.Evaluate;
  FTimer.Interval := cTickMs;
  FTimer.Enabled := True;
  EvaluateSlice;
end;

procedure TAtlasIdeDebugAccessViolation.EvaluateSlice;
var
  mStartedAt: UInt64;
  mRequest: TAtlasAvRequest;
  mStep: TSliceStep;
begin
  if (FAnalysis = nil) or not StillStopped then
  begin
    Drop;
    Exit;
  end;
  if DeferredPending then
  begin
    Exit;
  end;
  mStep := TSliceStep.Next;
  mStartedAt := TThread.GetTickCount64;
  while (mStep = TSliceStep.Next) and (TThread.GetTickCount64 - mStartedAt < cSliceMs) do
  begin
    if FAnalysis.Next(mRequest) then
    begin
      mStep := EvaluateOne(mRequest);
    end
    else
    begin
      Finish;
      mStep := TSliceStep.Stopped;
    end;
  end;
end;

function TAtlasIdeDebugAccessViolation.DeferredPending: Boolean;
begin
  Result := False;
  // Verzögerter Wert (LLDB): höchstens DeferredTimeoutMs warten, dann als Fehler weiter.
  if not FDeferred.Active then
  begin
    Exit;
  end;
  Result := TThread.GetTickCount64 - FDeferred.Since < cDeferredTimeoutMs;
  if not Result then
  begin
    FEvaluator.Cancel;
    EndInternal;
    FDeferred.Active := False;
    FAnalysis.Answer(False, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateTimeout));
  end;
end;

function TAtlasIdeDebugAccessViolation.EvaluateOne(const ARequest: TAtlasAvRequest): TSliceStep;
var
  mValue: TAtlasDebugValue;
begin
  Result := TSliceStep.Next;
  // Eigene Auswertung: Zustandswechsel dabei sind kein Fortsetzen (TAtlasIdeDebugSession).
  mValue := Default(TAtlasDebugValue);
  TAtlasIdeDebugSession.BeginInternal;
  FInternal := True;
  try
    mValue := FEvaluator.Evaluate(ARequest.Expression, FFacts.FileName, FFacts.Line + 1, ARequest.SideEffects,
      DeferredDone);
  finally
    if mValue.State <> TAtlasDebugValueState.Pending then
    begin
      EndInternal;
    end;
  end;
  case mValue.State of
    TAtlasDebugValueState.Pending:
      begin
        FDeferred.Active := True;
        FDeferred.Since := TThread.GetTickCount64;
        Result := TSliceStep.Wait;
      end;
    TAtlasDebugValueState.Value:
      FAnalysis.Answer(True, mValue.Text);
    TAtlasDebugValueState.Failed:
      FAnalysis.Answer(False, mValue.Text);
  else
    // Kein angehaltener Prozess mehr.
    Drop;
    Result := TSliceStep.Stopped;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.DeferredDone(const AValue: TAtlasDebugValue);
begin
  if not FDeferred.Active or (FAnalysis = nil) then
  begin
    Exit;
  end;
  EndInternal;
  FDeferred.Active := False;
  FAnalysis.Answer(AValue.State = TAtlasDebugValueState.Value, AValue.Text);
end;

function TAtlasIdeDebugAccessViolation.TStopFacts.Place: string;
begin
  Result := Format('%s:%d', [ExtractFileName(FileName), Line + 1]);
end;

function TAtlasIdeDebugAccessViolation.TStopFacts.Header: string;
begin
  Result := Exception.ExceptionClass;
  if Exception.Message <> '' then
  begin
    Result := Result + ': ' + Exception.Message;
  end;
  Result := Result + ' (' + Place + ')';
end;

procedure TAtlasIdeDebugAccessViolation.Finish;
var
  mVerdict: TAtlasAvVerdict;
  mEnd: Integer;
begin
  FTimer.Enabled := False;
  FProgress.Phase := TPhase.Idle;
  mVerdict := FAnalysis.Verdict;
  FOutcome.Culprit := mVerdict.Culprit;
  FOutcome.HasCulprit := mVerdict.HasCulprit;
  // Unterstreichen: das schuldige Glied in seiner ersten Zeile.
  if mVerdict.HasCulprit and (FFacts.Lines <> nil) and (mVerdict.Culprit.StartLine >= 0) and
    (mVerdict.Culprit.StartLine <= High(FFacts.Lines)) then
  begin
    if mVerdict.Culprit.EndLine = mVerdict.Culprit.StartLine then
    begin
      mEnd := mVerdict.Culprit.EndCharacter;
    end
    else
    begin
      mEnd := Length(TrimRight(FFacts.Lines[mVerdict.Culprit.StartLine]));
    end;
    FUnderline.Show(FFacts.FileName, mVerdict.Culprit.StartLine, mVerdict.Culprit.StartCharacter, mEnd,
      FFacts.Lines[mVerdict.Culprit.StartLine]);
  end;
  Publish(TAtlasAvTexts.FromAnalysis(FAnalysis, Assigned(FHooks.WhereAssigned) and
    TAtlasIdeSettings.Current.DataFlow, Assigned(FHooks.Evaluate) and TAtlasIdeSettings.Current.DebugEvaluateWindow,
    FFacts.Header));
end;

procedure TAtlasIdeDebugAccessViolation.Publish(const AExplanation: TAtlasDebugBannerExplanation);
var
  mLine: string;
begin
  FTimer.Enabled := False;
  FProgress.Phase := TPhase.Idle;
  FOutcome.Explanation := AExplanation;
  TAtlasGuard.Log('Zugriffsverletzung erklären: ' + TLogMarks.Text(AExplanation.Headline) + ' ' +
    TLogMarks.Text(AExplanation.Detail));
  // Steht (oder kommt) die Leiste für diesen Halt, zeigt sie die Erklärung; sonst die Meldungen.
  if TAtlasIdeDebugExceptionBar.Covers(FProgress.Stop) then
  begin
    TAtlasIdeDebugExceptionBar.Explain(FProgress.Stop, AExplanation);
  end
  else if Assigned(FHooks.Message) then
  begin
    for mLine in TAtlasAvTexts.MessageLines(AExplanation, FFacts.Place) do
    begin
      FHooks.Message(mLine);
    end;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.RunAction(AAction: TAtlasDebugBarAction);
begin
  if not FOutcome.Explanation.Active or FOutcome.Explanation.Busy then
  begin
    Exit;
  end;
  case AAction of
    TAtlasDebugBarAction.WhereAssigned:
      if FOutcome.HasCulprit and Assigned(FHooks.WhereAssigned) then
      begin
        FHooks.WhereAssigned(FFacts.FileName, FOutcome.Culprit.NameLine, FOutcome.Culprit.NameCharacter,
          FOutcome.Culprit.Name);
      end;
    TAtlasDebugBarAction.Evaluate:
      if Assigned(FHooks.Evaluate) and (FOutcome.Explanation.EvaluateExpression <> '') then
      begin
        FHooks.Evaluate(FOutcome.Explanation.EvaluateExpression);
      end;
    TAtlasDebugBarAction.CopyExplanation:
      if FOutcome.Explanation.CopyText <> '' then
      begin
        Clipboard.AsText := FOutcome.Explanation.CopyText;
      end;
    TAtlasDebugBarAction.None, TAtlasDebugBarAction.BreakHere, TAtlasDebugBarAction.Continue,
    TAtlasDebugBarAction.IgnoreClass, TAtlasDebugBarAction.IgnoreLocation, TAtlasDebugBarAction.Copy,
    TAtlasDebugBarAction.Open: ;
  end;
end;

procedure TAtlasIdeDebugAccessViolation.ReapWorkers(AWait: Boolean);
var
  mIndex: Integer;
begin
  if FWorkers = nil then
  begin
    Exit;
  end;
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    if AWait or FWorkers[mIndex].Finished then
    begin
      FWorkers[mIndex].WaitFor;
      FWorkers[mIndex].Free;
      FWorkers.Delete(mIndex);
    end;
  end;
end;

end.
