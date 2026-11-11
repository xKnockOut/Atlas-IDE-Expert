unit Atlas.IDE.Debug.InlineValues;

// Werte im Editor beim Debuggen (#508) in der IDE:
//   - Auslöser: Halt der Debug-Sitzung (TAtlasIdeDebugSession). Atlas liest
//     den obersten Rahmen des Aufrufstapels (Datei und Zeile des
//     Ausführungspunkts; LLDB liefert ihn verzögert, dann wieder in 50 ms).
//     Nur diese Datei bekommt Werte.
//   - Bezeichner: textDocument/inlineValue des Servers (Syntaxbaum, #262) im
//     Hintergrund-Thread. Den Text der Datei gleicht Atlas vorher im
//     Hauptthread ab. Startet keinen Server.
//   - Werte: IOTAThread.Evaluate über TAtlasIdeDebugValues ohne
//     Nebenwirkungen (eseNone), im Hauptthread in Zeitscheiben von höchstens
//     SliceMs; dazwischen bedient die IDE Tasten und Zeichnen, ein
//     Einzelschritt wird so nicht spürbar länger. Ausgewertet werden nur
//     schlichte Bezeichner (TAtlasInlineValues.IsPlainIdentifier). Antwortet
//     der Debugger verzögert (Win64/LLDB), wartet Atlas höchstens
//     DeferredTimeoutMs auf den Wert und lässt ihn sonst weg.
//   - Zeichnen: nach dem Zeichnen jeder Zeile (plsEndPaint) gedimmt hinter
//     dem Zeilenende („Count = 3, Name = 'Meier'“), seit dem letzten Halt
//     geänderte Werte in der Warnfarbe; nur, wenn die Zeile im Editor dem
//     abgeglichenen Text entspricht. Platz hinter dem Zeilenende über
//     TAtlasLineTail. Schrift, Farben und GDI: TAtlasInlineValuePainter.
//   - Fortsetzen, neuer Halt und Ende der Sitzung verwerfen die Werte und
//     laufende Anfragen.
//   - Kein Zugriff (#840): Mit debug.explainUnavailable steht ein Name, dessen
//     Auswertung mit einem bekannten Text scheitert, als „Name = ‹kein
//     Zugriff›“ da (TAtlasIdeDebugUnavailable); die Ursache zeigt der Hover.
// Ohne debug.inlineValues ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.InlineValues,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Hover.DebugValue,
  Atlas.UI.Debug.InlineValuePainter;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasInlineValuesSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugInlineValues = class
  public const
    /// <summary>Höchstens so lange wertet Atlas am Stück aus.</summary>
    cSliceMs = 30;
    cTickMs = 10;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    cDeferredTimeoutMs = 500;
    cRequestTimeoutMs = 3000;
    /// <summary>Versuche, bis der Aufrufstapel bzw. der Editor der Datei da ist (je TickMs * 5).</summary>
    cLocationRetries = 20;
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
    TPhase = (Idle, Location, Request, Evaluate);
    /// <summary>Nach einem Wert: weiter, auf den verzögerten warten oder alles verworfen.</summary>
    TSliceStep = (Next, Wait, Dropped);
    {$SCOPEDENUMS OFF}
    TProgress = record
      Phase: TPhase;
      Stop: Integer;
      Request: Integer;
      Retries: Integer;
    end;
    /// <summary>Verzögerter Wert (LLDB) und seit wann Atlas auf ihn wartet.</summary>
    TDeferred = record
      Name: string;
      Since: UInt64;
    end;
  private class var
    FInstance: TAtlasIdeDebugInlineValues;
  private
    FSession: TAtlasInlineValuesSessionFunc;
    FValues: TAtlasInlineValues;
    FEvaluator: TAtlasIdeDebugValues;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FWorkers: TList<TThread>;
    FProgress: TProgress;
    FDeferred: TDeferred;
    FInternal: Boolean;
    FFileName: string;
    FContext: string;
    FLine: Integer;
    FText: string;
    FLines: TArray<string>;
    FStyle: TAtlasInlineValuePainter;
    constructor Create(const ASession: TAtlasInlineValuesSessionFunc);
    /// <summary>Werte und laufende Arbeit verwerfen; AForget auch die gemerkten Werte (Ende der Sitzung).</summary>
    procedure Drop(AForget: Boolean);
    procedure Stopped;
    procedure Tick(Sender: TObject);
    /// <summary>Datei und Zeile des Ausführungspunkts; False: später noch einmal bzw. aufgeben
    /// (FProgress.Phase).</summary>
    function ReadLocation: Boolean;
    procedure Ask;
    procedure Accept(ARequest: Integer; const ARefs: TAtlasInlineValueRefs);
    procedure EvaluateSlice;
    /// <summary>Wartet Atlas noch auf den verzögerten Wert? Nach DeferredTimeoutMs ohne ihn weiter.</summary>
    function DeferredPending: Boolean;
    function EvaluateOne(const AName: string; var AChanged: Boolean): TSliceStep;
    procedure DeferredDone(const AValue: TAtlasDebugValue);
    procedure EndInternal;
    function StillStopped: Boolean;
    procedure ReapWorkers(AWait: Boolean);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    destructor Destroy; override;
    class procedure Start(const ASession: TAtlasInlineValuesSessionFunc); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.inlineValues an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.Core.Diagnostics.Deadline;

{ TAtlasIdeDebugInlineValues.TListener }

procedure TAtlasIdeDebugInlineValues.TListener.DebugStarted;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop(True);
  end;
end;

procedure TAtlasIdeDebugInlineValues.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
  begin
    FInstance.Stopped;
  end;
end;

procedure TAtlasIdeDebugInlineValues.TListener.DebugResumed;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop(False);
  end;
end;

procedure TAtlasIdeDebugInlineValues.TListener.DebugEnded;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop(True);
  end;
end;

{ TAtlasIdeDebugInlineValues.TEvents }

function TAtlasIdeDebugInlineValues.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeDebugInlineValues.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugInlineValues }

constructor TAtlasIdeDebugInlineValues.Create(const ASession: TAtlasInlineValuesSessionFunc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FValues := TAtlasInlineValues.Create;
  FEvaluator := TAtlasIdeDebugValues.Create;
  FWorkers := TList<TThread>.Create;
  FStyle := TAtlasInlineValuePainter.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeDebugInlineValues.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
  end;
  FEventsRef := nil;
  FreeAndNil(FTimer);
  FEvaluator.Cancel;
  EndInternal;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FreeAndNil(FEvaluator);
  FreeAndNil(FValues);
  FreeAndNil(FStyle);
  FText := '';
  FLines := nil;
  inherited Destroy;
end;

class procedure TAtlasIdeDebugInlineValues.Start(const ASession: TAtlasInlineValuesSessionFunc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugInlineValues.Create(ASession);
    FInstance.FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  end;
  TAtlasIdeDebugSession.Start;
  // Eingeschaltet, während der Prozess steht: gleich für diesen Halt.
  if TAtlasIdeDebugSession.StoppedThread <> nil then
  begin
    FInstance.Stopped;
  end;
end;

class procedure TAtlasIdeDebugInlineValues.Release;
var
  mInstance: TAtlasIdeDebugInlineValues;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  FInstance := nil;
  if mInstance.FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(mInstance.FListener);
  end;
  mInstance.FListener := nil;
  mInstance.Free;
  Invalidate;
end;

class function TAtlasIdeDebugInlineValues.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugInlineValues.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugInlineValues;
end;

class procedure TAtlasIdeDebugInlineValues.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

procedure TAtlasIdeDebugInlineValues.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

procedure TAtlasIdeDebugInlineValues.Drop(AForget: Boolean);
var
  mHad: Boolean;
begin
  mHad := FValues.Active;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FEvaluator.Cancel;
  EndInternal;
  FDeferred.Name := '';
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FProgress.Request);
  FProgress.Phase := TPhase.Idle;
  if AForget then
  begin
    FValues.Reset;
  end
  else
  begin
    FValues.Clear;
  end;
  FText := '';
  FLines := nil;
  ReapWorkers(False);
  if mHad then
  begin
    Invalidate;
  end;
end;

function TAtlasIdeDebugInlineValues.StillStopped: Boolean;
begin
  Result := (TAtlasIdeDebugSession.StopCount = FProgress.Stop) and (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeDebugInlineValues.Stopped;
begin
  Drop(False);
  if not Enabled then
  begin
    Exit;
  end;
  FValues.SetUnavailable(TAtlasIdeDebugUnavailable.InlineCaption, TAtlasIdeDebugUnavailable.Patterns);
  FProgress.Stop := TAtlasIdeDebugSession.StopCount;
  FProgress.Retries := 0;
  FProgress.Phase := TPhase.Location;
  if ReadLocation then
  begin
    Ask;
  end;
end;

function TAtlasIdeDebugInlineValues.ReadLocation: Boolean;
var
  mFrames: TAtlasDebugFrames;
  mBuffer: IOTAEditBuffer;
begin
  Result := False;
  case TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, mFrames) of
    TAtlasDebugStackRead.Wait:
      begin
        // LLDB: Stapel kommt später.
        Inc(FProgress.Retries);
        FTimer.Interval := cTickMs * 5;
        FTimer.Enabled := FProgress.Retries <= cLocationRetries;
        if not FTimer.Enabled then
        begin
          FProgress.Phase := TPhase.Idle;
        end;
        Exit;
      end;
    TAtlasDebugStackRead.None:
      begin
        FProgress.Phase := TPhase.Idle;
        Exit;
      end;
  end;
  if (Length(mFrames) = 0) or not mFrames[0].HasSource then
  begin
    // Kein Quelltext am Ausführungspunkt (RTL ohne Quellen, Assembler).
    FProgress.Phase := TPhase.Idle;
    Exit;
  end;
  TAtlasIdeDebugSources.MarkFrames(mFrames);
  mBuffer := TAtlasIdeFiles.BufferOf(mFrames[0].FileName);
  if mBuffer = nil then
  begin
    // Die IDE öffnet die Datei des Halts gleich danach.
    Inc(FProgress.Retries);
    FTimer.Interval := cTickMs * 5;
    FTimer.Enabled := FProgress.Retries <= cLocationRetries;
    if not FTimer.Enabled then
    begin
      FProgress.Phase := TPhase.Idle;
    end;
    Exit;
  end;
  FFileName := mBuffer.FileName;
  FContext := FFileName + '|' + mFrames[0].Routine;
  FLine := mFrames[0].Line - 1;
  FText := TAtlasEditorBuffer.Text(mBuffer);
  FLines := FText.Split([#13#10, #10]);
  FProgress.Phase := TPhase.Request;
  Result := True;
end;

procedure TAtlasIdeDebugInlineValues.Ask;
var
  mSession: TLspSession;
  mFileName: string;
  mLine, mRequest: Integer;
  mWorker: TThread;
begin
  FTimer.Enabled := False;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    FProgress.Phase := TPhase.Idle;
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mFileName := FFileName;
  mLine := FLine;
  mSession.Sync(mFileName, FText);
  ReapWorkers(False);
  Inc(FProgress.Request);
  mRequest := FProgress.Request;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      Refs: TAtlasInlineValueRefs;
    begin
      Refs := nil;
      try
        // Vom Dateianfang bis zum Halt; der Server beschränkt auf die Routine.
        Refs := mSession.InlineValues(mFileName, 0, mLine, mLine, cRequestTimeoutMs);
      except
        // Server langsam oder weg: keine Werte.
        Refs := nil;
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
                  FInstance.Accept(mRequest, Refs);
                end;
              end);
          end;
        end);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TAtlasIdeDebugInlineValues.Accept(ARequest: Integer; const ARefs: TAtlasInlineValueRefs);
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FProgress.Request) or (FProgress.Phase <> TPhase.Request) then
  begin
    Exit;
  end;
  if not StillStopped or not Enabled or (Length(ARefs) = 0) then
  begin
    FProgress.Phase := TPhase.Idle;
    Exit;
  end;
  FValues.Start(FFileName, FContext, FLine, ARefs, TAtlasIdeSettings.Current.DebugInlineValuesPerLine);
  FProgress.Phase := TPhase.Evaluate;
  FTimer.Interval := cTickMs;
  FTimer.Enabled := True;
  EvaluateSlice;
end;

procedure TAtlasIdeDebugInlineValues.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  try
    case FProgress.Phase of
      TPhase.Location:
        begin
          FTimer.Enabled := False;
          if not StillStopped then
          begin
            FProgress.Phase := TPhase.Idle;
          end
          else if ReadLocation then
          begin
            Ask;
          end;
        end;
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

procedure TAtlasIdeDebugInlineValues.EvaluateSlice;
var
  mStartedAt: UInt64;
  mName: string;
  mStep: TSliceStep;
  mChanged: Boolean;
begin
  if not StillStopped then
  begin
    Drop(False);
    Exit;
  end;
  if DeferredPending then
  begin
    Exit;
  end;
  mChanged := False;
  mStep := TSliceStep.Next;
  mStartedAt := TAtlasTicks.Now;
  while (mStep = TSliceStep.Next) and (TAtlasTicks.Since(mStartedAt) < cSliceMs) and FValues.NextPending(mName) do
  begin
    mStep := EvaluateOne(mName, mChanged);
  end;
  if mStep = TSliceStep.Dropped then
  begin
    Exit;
  end;
  if (FDeferred.Name = '') and not FValues.NextPending(mName) then
  begin
    FTimer.Enabled := False;
    FProgress.Phase := TPhase.Idle;
  end;
  if mChanged then
  begin
    Invalidate;
  end;
end;

function TAtlasIdeDebugInlineValues.DeferredPending: Boolean;
begin
  Result := False;
  // Verzögerter Wert (LLDB): höchstens DeferredTimeoutMs warten, dann ohne ihn weiter.
  if FDeferred.Name = '' then
  begin
    Exit;
  end;
  Result := TAtlasTicks.Since(FDeferred.Since) < cDeferredTimeoutMs;
  if not Result then
  begin
    FEvaluator.Cancel;
    EndInternal;
    FValues.Put(FDeferred.Name, '', False);
    FDeferred.Name := '';
  end;
end;

function TAtlasIdeDebugInlineValues.EvaluateOne(const AName: string; var AChanged: Boolean): TSliceStep;
var
  mValue: TAtlasDebugValue;
begin
  Result := TSliceStep.Next;
  // Eigene Auswertung: Zustandswechsel dabei sind kein Fortsetzen (TAtlasIdeDebugSession).
  mValue := Default(TAtlasDebugValue);
  TAtlasIdeDebugSession.BeginInternal;
  FInternal := True;
  try
    mValue := FEvaluator.Evaluate(AName, FFileName, FLine + 1, DeferredDone);
  finally
    if mValue.State <> TAtlasDebugValueState.Pending then
    begin
      EndInternal;
    end;
  end;
  case mValue.State of
    TAtlasDebugValueState.Pending:
      begin
        FDeferred.Name := AName;
        FDeferred.Since := TAtlasTicks.Now;
        Result := TSliceStep.Wait;
      end;
    TAtlasDebugValueState.Value:
      begin
        FValues.Put(AName, mValue.Text, True);
        AChanged := True;
      end;
    TAtlasDebugValueState.Failed:
      FValues.Put(AName, '', False);
  else
    // Kein angehaltener Prozess mehr.
    Drop(False);
    Result := TSliceStep.Dropped;
  end;
end;

procedure TAtlasIdeDebugInlineValues.DeferredDone(const AValue: TAtlasDebugValue);
begin
  if FDeferred.Name = '' then
  begin
    Exit;
  end;
  EndInternal;
  FValues.Put(FDeferred.Name, AValue.Text, AValue.State = TAtlasDebugValueState.Value);
  FDeferred.Name := '';
  Invalidate;
end;

procedure TAtlasIdeDebugInlineValues.ReapWorkers(AWait: Boolean);
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

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

/// <summary>Entspricht die Zeile im Editor der abgeglichenen AStored? ATabWidth: Tabweite des Puffers.</summary>
function LineMatches(const AContext: INTACodeEditorPaintContext; const AStored: string;
  out ATabWidth: Integer): Boolean;
var
  mLineState: INTACodeEditorLineState;
begin
  ATabWidth := 0;
  mLineState := AContext.LineState;
  Result := (mLineState <> nil) and (AContext.EditView <> nil) and (AContext.EditView.Buffer <> nil);
  if Result then
  begin
    ATabWidth := TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer);
    Result := TrimRight(TAtlasPairs.DisplayLine(mLineState.Text, ATabWidth)) =
      TrimRight(TAtlasPairs.DisplayLine(AStored, ATabWidth));
  end;
end;

procedure TAtlasIdeDebugInlineValues.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mItems: TAtlasInlineValueItems;
  mLine, mTabWidth, mX: Integer;
  mStored, mTailKey: string;
  mCell: TRect;
  mSample: COLORREF;
  mDC: HDC;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or
    not FValues.Active then
  begin
    Exit;
  end;
  try
    mLine := Context.LogicalLineNum - 1;
    mItems := FValues.Line(Context.FileName, mLine);
    // Nur, wenn die Zeile im Editor der abgeglichenen entspricht.
    if (Length(mItems) = 0) or (mLine < 0) or (mLine > High(FLines)) or
      not LineMatches(Context, FLines[mLine], mTabWidth) then
    begin
      Exit;
    end;
    mStored := FLines[mLine];
    mDC := Context.Canvas.Handle;
    // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile.
    mCell := Context.EditorState.GetCharacterPosPx(ColumnOf(mStored, Length(TrimRight(mStored)), mTabWidth) + 2,
      Context.EditorLineNum);
    mTailKey := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
    mX := TAtlasLineTail.Start(Self, mTailKey, mCell.Left);
    mSample := GetPixel(mDC, mX, Rect.Top + 1);
    if mSample = CLR_INVALID then
    begin
      mSample := COLORREF(ColorToRGB(Context.Canvas.Brush.Color));
    end;
    FStyle.Ensure(mSample, Context.Canvas.Font);
    TAtlasLineTail.Finish(Self, mTailKey, FStyle.Draw(mDC, Rect, mX, mItems));
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

end.
