unit Atlas.IDE.Debug.CallStack;

// Fenster „Atlas-Aufrufstapel“ (#843): füllt bei jedem Halt das Fenster mit dem Aufrufstapel des aktuellen Threads.
//   - Gelesen wird nur, solange das Fenster sichtbar ist (IOTAThread über TAtlasIdeDebugSession.ReadStack, eigener
//     Code nach #578). Liefert der Win64-Debugger (LLDB) den Stapel erst später, fragt Atlas bis zu cRetries mal.
//   - Namen und Typen der Parameter: atlas.server.routineParameters je sichtbarem Rahmen mit Quelltext, im
//     Hintergrund über TAtlasIdeHost (Antwort im Hauptthread, nur solange das Modul angemeldet ist); startet keinen
//     Server. Ohne Server bleiben die Werte aus dem Rahmentext der IDE ohne Namen.
//   - Werte (debug.callStackWindow.evaluateParams): ein Parameter je Zeitgeberschritt über TAtlasIdeDebugEvaluator
//     ohne Nebenwirkungen und mit Zeitlimit, nur für sichtbare Rahmen. Im obersten Rahmen über den Namen, sonst
//     über eine Typumwandlung der Adresse aus dem Rahmentext (die ToolsAPI wählt keinen anderen Rahmen). Erst die
//     Visualisierer (#835), dann Objekte mit Klasse und Namensfeld, sonst der Wert der IDE.
//   - Vergleich: Fortsetzen merkt den Stapel je Stelle des Halts (höchstens 20 Stellen, je Sitzung); beim nächsten
//     Halt an derselben Stelle steht er neben dem aktuellen.
//   - Enter bzw. Doppelklick auf einen Rahmen springt auf seine Zeile; den Rahmen im Fenster Aufrufstack der IDE
//     wählt die ToolsAPI nicht.
// Teil „DebugCallStackWindow“ (debug.callStackWindow); Release meldet den Zuhörer ab und gibt Zeitgeber und Fenster
// frei (Regel 3). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.CallStackView,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.CallStackFrame;

type
  /// <summary>Serverbefehl im Hintergrund; ADone im Hauptthread mit der Antwort als JSON-Text ('' bei Fehler).
  /// False = nicht gestartet.</summary>
  TAtlasCallStackRunner = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeDebugCallStack = class
  public const
    cTickMs = 30;
    cRetries = 10;
    cRequestTimeoutMs = 3000;
    cEvaluateTimeoutMs = 500;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Read, Names, Waiting, Values);
    {$SCOPEDENUMS OFF}
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FRun: TAtlasCallStackRunner;
    FMessage: TProc<string>;
    FHistory: TAtlasDebugStackHistory;
    FStack: TAtlasDebugStackView;
    FPrevious: TAtlasDebugStackView;
    FHasPrevious: Boolean;
    FPhase: TPhase;
    FRetries: Integer;
    FStop: Integer;
    FRequest: Integer;
    class procedure Refresh; static;
    class procedure Step; static;
    class procedure ReadStep; static;
    class procedure AskNext; static;
    class procedure Accept(ARequest, AFrame: Integer; const AAnswer: string); static;
    class procedure EvaluateNext; static;
    class function EvaluateParam(AFrame, AParam: Integer): string; static;
    class procedure Remember; static;
    class procedure ShowRunning; static;
    class procedure ShowUpdate; static;
    class procedure Schedule(APhase: TPhase); static;
    class function StillStopped: Boolean; static;
    class procedure OpenFrame(AIndex: Integer); static;
    class procedure WireFrame(AFrame: TAtlasDebugCallStackFrame); static;
  public
    class procedure Start(const ARun: TAtlasCallStackRunner; const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.DebugCallStack: Fenster zeigen und füllen.</summary>
    class procedure ShowWindow; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.CallStackParams,
  Atlas.Core.Debug.OwnCode,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.Visualizers,
  Atlas.IDE.Debug.CallStackWindow,
  Atlas.UI.Debug.Strings;

/// <summary>Fenster, falls es sichtbar ist; sonst nil.</summary>
function ShownFrame: TAtlasDebugCallStackFrame;
begin
  Result := nil;
  if TAtlasIdeDebugCallStackWindow.Visible then
  begin
    Result := TAtlasIdeDebugCallStackWindow.ExistingFrame;
  end;
end;

{ TAtlasIdeDebugCallStack.TListener }

procedure TAtlasIdeDebugCallStack.TListener.DebugStarted;
begin
  // Adressen und Stellen gelten nur in ihrer Sitzung.
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugCallStack.FHistory <> nil then
      begin
        TAtlasIdeDebugCallStack.FHistory.Clear;
      end;
    end);
end;

procedure TAtlasIdeDebugCallStack.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugCallStack.Refresh);
end;

procedure TAtlasIdeDebugCallStack.TListener.DebugResumed;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugCallStack.ShowRunning);
end;

procedure TAtlasIdeDebugCallStack.TListener.DebugEnded;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugCallStack.ShowRunning);
end;

{ TAtlasIdeDebugCallStack.TTicker }

procedure TAtlasIdeDebugCallStack.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugCallStack.Step);
end;

{ TAtlasIdeDebugCallStack }

class procedure TAtlasIdeDebugCallStack.Start(const ARun: TAtlasCallStackRunner; const AMessage: TProc<string>);
begin
  FRun := ARun;
  FMessage := AMessage;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cTickMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  if FHistory = nil then
  begin
    FHistory := TAtlasDebugStackHistory.Create;
  end;
  TAtlasIdeDebugCallStackWindow.Prepare;
  TAtlasIdeDebugCallStackWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugCallStackFrame)
    begin
      WireFrame(AFrame);
    end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugCallStack.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  // Späte Serverantworten vergleichen ihre Nummer und verfallen.
  Inc(FRequest);
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FreeAndNil(FHistory);
  TAtlasIdeDebugCallStackWindow.Release;
  FRun := nil;
  FMessage := nil;
  FStack := Default(TAtlasDebugStackView);
  FPrevious := Default(TAtlasDebugStackView);
  FPhase := TPhase.Idle;
end;

class function TAtlasIdeDebugCallStack.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugCallStack.WireFrame(AFrame: TAtlasDebugCallStackFrame);
begin
  AFrame.OnOpenFrame :=
    procedure(AIndex: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          OpenFrame(AIndex);
        end);
    end;
  AFrame.OnExpand :=
    procedure
    begin
      // Aufgeklappte Rahmen bekommen Namen und Werte.
      if StillStopped then
      begin
        Schedule(TPhase.Names);
      end;
    end;
  AFrame.OnCopied :=
    procedure(ACount: Integer)
    begin
      if Assigned(FMessage) then
      begin
        FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.CallStackCopied, [ACount]));
      end;
    end;
end;

class procedure TAtlasIdeDebugCallStack.ShowWindow;
begin
  if not Started then
  begin
    Exit;
  end;
  if TAtlasIdeDebugCallStackWindow.Show = nil then
  begin
    Exit;
  end;
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    ShowRunning;
  end
  else
  begin
    Refresh;
  end;
end;

class procedure TAtlasIdeDebugCallStack.ThemeChanged;
begin
  TAtlasIdeDebugCallStackWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugCallStack.Schedule(APhase: TPhase);
begin
  FPhase := APhase;
  if FTimer <> nil then
  begin
    FTimer.Enabled := APhase <> TPhase.Idle;
  end;
end;

class function TAtlasIdeDebugCallStack.StillStopped: Boolean;
begin
  Result := (FTimer <> nil) and (TAtlasIdeDebugSession.StoppedThread <> nil) and
    (TAtlasIdeDebugSession.StopCount = FStop) and (ShownFrame <> nil);
end;

class procedure TAtlasIdeDebugCallStack.Remember;
begin
  // Der Stapel des zu Ende gehenden Halts, mit den Werten, die bis dahin da waren.
  if (FHistory <> nil) and (FStack.Count > 0) then
  begin
    FHistory.Remember(FStack);
  end;
  FStack := Default(TAtlasDebugStackView);
  FPrevious := Default(TAtlasDebugStackView);
  FHasPrevious := False;
end;

class procedure TAtlasIdeDebugCallStack.ShowRunning;
var
  mFrame: TAtlasDebugCallStackFrame;
begin
  Remember;
  Inc(FRequest);
  Schedule(TPhase.Idle);
  mFrame := ShownFrame;
  if mFrame <> nil then
  begin
    mFrame.ShowStatus(TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackRunning));
  end;
end;

class procedure TAtlasIdeDebugCallStack.Refresh;
var
  mFrame: TAtlasDebugCallStackFrame;
begin
  Remember;
  Inc(FRequest);
  mFrame := ShownFrame;
  if (FTimer = nil) or (mFrame = nil) then
  begin
    Schedule(TPhase.Idle);
    Exit;
  end;
  FStop := TAtlasIdeDebugSession.StopCount;
  FRetries := 0;
  mFrame.ShowStatus(TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackReading));
  FPhase := TPhase.Read;
  ReadStep;
end;

class procedure TAtlasIdeDebugCallStack.Step;
begin
  if FTimer = nil then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  if not StillStopped then
  begin
    FPhase := TPhase.Idle;
    Exit;
  end;
  case FPhase of
    TPhase.Read:
      ReadStep;
    TPhase.Names:
      AskNext;
    TPhase.Values:
      EvaluateNext;
  end;
end;

class procedure TAtlasIdeDebugCallStack.ReadStep;
var
  mFrames: TAtlasDebugFrames;
  mFrame: TAtlasDebugCallStackFrame;
begin
  if not StillStopped then
  begin
    Schedule(TPhase.Idle);
    Exit;
  end;
  case TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, TAtlasDebugCallStack.cMaxFrames,
    mFrames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FRetries);
        if FRetries <= cRetries then
        begin
          Schedule(TPhase.Read);
          Exit;
        end;
        mFrames := nil;
      end;
    TAtlasDebugStackRead.None:
      mFrames := nil;
  end;
  TAtlasIdeDebugSources.MarkFrames(mFrames);
  FStack := TAtlasDebugStackView.FromFrames(mFrames);
  FHasPrevious := FHistory.Previous(FStack.Key, FPrevious);
  mFrame := ShownFrame;
  if FHasPrevious then
  begin
    FStack.CompareWith(FPrevious);
    FPrevious.CompareWith(FStack);
  end;
  mFrame.SetStack(FStack, FPrevious, FHasPrevious);
  Schedule(TPhase.Names);
end;

class procedure TAtlasIdeDebugCallStack.ShowUpdate;
var
  mFrame: TAtlasDebugCallStackFrame;
begin
  mFrame := ShownFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  if FHasPrevious then
  begin
    FStack.CompareWith(FPrevious);
    FPrevious.CompareWith(FStack);
  end;
  mFrame.UpdateStack(FStack, FPrevious);
end;

class procedure TAtlasIdeDebugCallStack.AskNext;
var
  mUnnamed: TArray<Integer>;
  mFrame, mTarget, mRequest: Integer;
  mArguments: string;
begin
  mUnnamed := FStack.Unnamed(ShownFrame.Rows);
  if mUnnamed = nil then
  begin
    Schedule(TPhase.Values);
    Exit;
  end;
  mTarget := mUnnamed[0];
  // Gilt auch, wenn die Antwort ausbleibt: dann bleiben die Werte ohne Namen.
  FStack.Entries[mTarget].Named := True;
  if not Assigned(FRun) then
  begin
    Schedule(TPhase.Names);
    Exit;
  end;
  mArguments := TAtlasCallStackParams.Arguments(TLspSession.PathToUri(FStack.Entries[mTarget].Frame.FileName),
    FStack.Entries[mTarget].Frame.Line - 1);
  Inc(FRequest);
  mRequest := FRequest;
  FPhase := TPhase.Waiting;
  if not FRun(TAtlasCallStackParams.cCommand, mArguments, cRequestTimeoutMs,
    procedure(AAnswer: string)
    begin
      TAtlasIdeDebugCallStack.Accept(mRequest, mTarget, AAnswer);
    end) then
  begin
    // Kein Server: alle sichtbaren Rahmen bleiben ohne Namen.
    for mFrame in mUnnamed do
    begin
      FStack.Entries[mFrame].Named := True;
    end;
    Schedule(TPhase.Values);
  end;
end;

class procedure TAtlasIdeDebugCallStack.Accept(ARequest, AFrame: Integer; const AAnswer: string);
var
  mRoutine: string;
  mDeclared: TAtlasCallStackDeclaredList;
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FRequest) or (FPhase <> TPhase.Waiting) or (AFrame > High(FStack.Entries)) then
  begin
    Exit;
  end;
  if not StillStopped then
  begin
    Schedule(TPhase.Idle);
    Exit;
  end;
  if TAtlasCallStackParams.ReadAnswer(AAnswer, mRoutine, mDeclared) and
    TAtlasCallStackParams.Combine(FStack.Entries[AFrame].Params, mDeclared, Pos('.', mRoutine) > 0) then
  begin
    ShowUpdate;
  end;
  Schedule(TPhase.Names);
end;

class procedure TAtlasIdeDebugCallStack.EvaluateNext;
var
  mRows: TAtlasDebugStackRows;
  mRow: TAtlasDebugStackRow;
  mParam: Integer;
  mValue: string;
begin
  if not TAtlasIdeSettings.Current.DebugCallStackWindowEvaluateParams then
  begin
    Schedule(TPhase.Idle);
    Exit;
  end;
  mRows := ShownFrame.Rows;
  for mRow in mRows do
  begin
    if mRow.Kind <> TAtlasDebugStackRowKind.Frame then
    begin
      Continue;
    end;
    for mParam := 0 to High(FStack.Entries[mRow.First].Params) do
    begin
      if TAtlasCallStackParams.ExpressionFor(FStack.Entries[mRow.First].Params[mParam], mRow.First = 0) = '' then
      begin
        Continue;
      end;
      // Einer je Schritt; dazwischen bedient die IDE Tasten und Zeichnen.
      FStack.Entries[mRow.First].Params[mParam].Done := True;
      mValue := EvaluateParam(mRow.First, mParam);
      if mValue <> '' then
      begin
        FStack.Entries[mRow.First].Params[mParam].Value := mValue;
        ShowUpdate;
      end;
      Schedule(TPhase.Values);
      Exit;
    end;
  end;
  Schedule(TPhase.Idle);
end;

class function TAtlasIdeDebugCallStack.EvaluateParam(AFrame, AParam: Integer): string;
var
  mParam: TAtlasCallStackParam;
  mExpression, mText, mName: string;
begin
  Result := '';
  mParam := FStack.Entries[AFrame].Params[AParam];
  mExpression := TAtlasCallStackParams.ExpressionFor(mParam, AFrame = 0);
  TAtlasIdeDebugSession.BeginInternal;
  try
    if not TAtlasIdeDebugEvaluator.Evaluate(mExpression, TAtlasVisualizerEvaluation.Fields, cEvaluateTimeoutMs,
      mText) then
    begin
      Exit;
    end;
    // Ersatztext der Visualisierer (#835), etwa für TObjectList<TKunde>.
    if mParam.TypeName <> '' then
    begin
      Result := TAtlasIdeVisualizers.HoverText(mExpression, [mParam.TypeName], mText);
    end;
    if Result <> '' then
    begin
      Exit;
    end;
    if not TAtlasCallStackParams.IsStructure(mText) then
    begin
      Result := TAtlasCallStackParams.ValueText(mText, TAtlasCallStackParams.IsStringType(mParam.TypeName));
      Exit;
    end;
    // Objekt: Klasse laut Deklaration und, falls vorhanden, das Namensfeld.
    if TAtlasCallStackParams.IsAddress(mParam.Raw) or (AFrame = 0) then
    begin
      if not TAtlasIdeDebugEvaluator.Evaluate(mExpression + '.Name', TAtlasVisualizerEvaluation.Fields,
        cEvaluateTimeoutMs, mName) or not mName.StartsWith('''') then
      begin
        mName := '';
      end;
      Result := TAtlasCallStackParams.ObjectText(mParam.TypeName, mName, mParam.Raw);
    end;
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

class procedure TAtlasIdeDebugCallStack.OpenFrame(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FStack.Entries)) or not FStack.Entries[AIndex].Frame.HasSource then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.MarkLine(FStack.Entries[AIndex].Frame.FileName, FStack.Entries[AIndex].Frame.Line - 1);
end;

end.
