unit Atlas.IDE.Debug.WhyHere;

// „Warum bin ich hier?“ (#1878) in der IDE:
//   - Auslöser: Halt der Debug-Sitzung. Atlas liest den obersten Rahmen
//     (Datei und Zeile des Ausführungspunkts; LLDB liefert ihn verzögert).
//   - Blöcke: atlas.server.enclosingConditions über TAtlasIdeHost im
//     Hintergrund (Antwort im Hauptthread, nur solange das Modul angemeldet
//     ist); den Text der Datei gleicht Atlas vorher ab. Startet keinen Server.
//   - Werte: IOTAThread.Evaluate über TAtlasIdeDebugValues ohne Nebenwirkungen
//     (eseNone), im Hauptthread in Zeitscheiben wie die Werte im Editor (#508);
//     welcher Teil als Nächstes dran ist (Kurzschluss, Aufrufe), entscheidet
//     TAtlasWhyHere.
//   - Zeichnen: am Ende der Kopfzeile, hinter den Werten im Editor
//     (TAtlasLineTail), gedimmt wie diese.
//   - Klick auf den Text einer Zeile mit Aufrufen: Rückfrage mit den Aufrufen;
//     erst dann wertet Atlas sie mit Nebenwirkungen (eseAll) aus.
//   - Fortsetzen, neuer Halt und Ende der Sitzung verwerfen alles.
// Ohne debug.whyHere ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.WhyHere,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Hover.DebugValue,
  Atlas.UI.Debug.InlineValuePainter;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasWhyHereSessionFunc = reference to function: TLspSession;
  /// <summary>Serverbefehl im Hintergrund; ADone im Hauptthread mit der Antwort als JSON-Text ('' bei Fehler).
  /// False = nicht gestartet.</summary>
  TAtlasWhyHereRunner = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeDebugWhyHere = class
  public const
    cSliceMs = 30;
    cTickMs = 10;
    cDeferredTimeoutMs = 500;
    cRequestTimeoutMs = 3000;
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
    {$SCOPEDENUMS OFF}
    /// <summary>Gezeichneter Text einer Zeile, für den Klick.</summary>
    THit = record
      Line: Integer;
      Rect: TRect;
    end;
  private class var
    FInstance: TAtlasIdeDebugWhyHere;
  private
    FSession: TAtlasWhyHereSessionFunc;
    FRun: TAtlasWhyHereRunner;
    FWhy: TAtlasWhyHere;
    FEvaluator: TAtlasIdeDebugValues;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FPhase: TPhase;
    FStop: Integer;
    FRequest: Integer;
    FRetries: Integer;
    FDeferred: TAtlasWhyHereRef;
    FDeferredSince: UInt64;
    FWaiting: Boolean;
    FInternal: Boolean;
    FFileName: string;
    FLine: Integer;
    FText: string;
    FLines: TArray<string>;
    FHits: TList<THit>;
    FStyle: TAtlasInlineValuePainter;
    constructor Create(const ASession: TAtlasWhyHereSessionFunc; const ARun: TAtlasWhyHereRunner);
    procedure Drop;
    procedure Stopped;
    procedure Tick(Sender: TObject);
    function ReadLocation: Boolean;
    procedure Retry;
    procedure Ask;
    procedure Accept(ARequest: Integer; const AAnswer: string);
    procedure EvaluateSlice;
    function EvaluateOne(const ARef: TAtlasWhyHereRef): Boolean;
    procedure DeferredDone(const AValue: TAtlasDebugValue);
    function DeferredPending: Boolean;
    procedure EndInternal;
    function StillStopped: Boolean;
    function Texts: TAtlasWhyHereTexts;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RememberHit(ALine: Integer; const ARect: TRect);
    procedure AskCalls(ALine: Integer);
    class procedure Invalidate; static;
  public
    destructor Destroy; override;
    class procedure Start(const ASession: TAtlasWhyHereSessionFunc; const ARun: TAtlasWhyHereRunner); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.whyHere an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Debug.Sources,
  Atlas.UI.Debug.Strings;

{ TAtlasIdeDebugWhyHere.TListener }

procedure TAtlasIdeDebugWhyHere.TListener.DebugStarted;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop;
  end;
end;

procedure TAtlasIdeDebugWhyHere.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
  begin
    FInstance.Stopped;
  end;
end;

procedure TAtlasIdeDebugWhyHere.TListener.DebugResumed;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop;
  end;
end;

procedure TAtlasIdeDebugWhyHere.TListener.DebugEnded;
begin
  if FInstance <> nil then
  begin
    FInstance.Drop;
  end;
end;

{ TAtlasIdeDebugWhyHere.TEvents }

function TAtlasIdeDebugWhyHere.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeDebugWhyHere.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugWhyHere }

constructor TAtlasIdeDebugWhyHere.Create(const ASession: TAtlasWhyHereSessionFunc; const ARun: TAtlasWhyHereRunner);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FRun := ARun;
  FIndex := -1;
  FWhy := TAtlasWhyHere.Create;
  FEvaluator := TAtlasIdeDebugValues.Create;
  FHits := TList<THit>.Create;
  FStyle := TAtlasInlineValuePainter.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeDebugWhyHere.Destroy;
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
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FreeAndNil(FTimer);
  FEvaluator.Cancel;
  EndInternal;
  FreeAndNil(FEvaluator);
  FreeAndNil(FWhy);
  FreeAndNil(FHits);
  FreeAndNil(FStyle);
  FText := '';
  FLines := nil;
  inherited Destroy;
end;

class procedure TAtlasIdeDebugWhyHere.Start(const ASession: TAtlasWhyHereSessionFunc; const ARun: TAtlasWhyHereRunner);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugWhyHere.Create(ASession, ARun);
    FInstance.FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  end;
  TAtlasIdeDebugSession.Start;
  if TAtlasIdeDebugSession.StoppedThread <> nil then
  begin
    FInstance.Stopped;
  end;
end;

class procedure TAtlasIdeDebugWhyHere.Release;
var
  mInstance: TAtlasIdeDebugWhyHere;
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

class function TAtlasIdeDebugWhyHere.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugWhyHere.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugWhyHere;
end;

class procedure TAtlasIdeDebugWhyHere.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

function TAtlasIdeDebugWhyHere.Texts: TAtlasWhyHereTexts;
begin
  Result := Default(TAtlasWhyHereTexts);
  Result.NotNeeded := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereNotNeeded);
  Result.NotEvaluated := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereNotEvaluated);
  Result.Failed := '?';
  Result.ElseBranch := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereElseBranch);
  Result.Of_ := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereOf);
end;

procedure TAtlasIdeDebugWhyHere.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

procedure TAtlasIdeDebugWhyHere.Drop;
var
  mHad: Boolean;
begin
  mHad := FWhy.Active;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FEvaluator.Cancel;
  EndInternal;
  FWaiting := False;
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FRequest);
  FPhase := TPhase.Idle;
  FWhy.Clear;
  FHits.Clear;
  FText := '';
  FLines := nil;
  if mHad then
  begin
    Invalidate;
  end;
end;

function TAtlasIdeDebugWhyHere.StillStopped: Boolean;
begin
  Result := (TAtlasIdeDebugSession.StopCount = FStop) and (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeDebugWhyHere.Stopped;
begin
  Drop;
  if not Enabled then
  begin
    Exit;
  end;
  FStop := TAtlasIdeDebugSession.StopCount;
  FRetries := 0;
  FPhase := TPhase.Location;
  if ReadLocation then
  begin
    Ask;
  end;
end;

procedure TAtlasIdeDebugWhyHere.Retry;
begin
  // LLDB liefert den Stapel bzw. die IDE öffnet die Datei erst gleich danach.
  Inc(FRetries);
  FTimer.Interval := cTickMs * 5;
  FTimer.Enabled := FRetries <= cLocationRetries;
  if not FTimer.Enabled then
  begin
    FPhase := TPhase.Idle;
  end;
end;

function TAtlasIdeDebugWhyHere.ReadLocation: Boolean;
var
  mFrames: TAtlasDebugFrames;
  mBuffer: IOTAEditBuffer;
begin
  Result := False;
  case TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, mFrames) of
    TAtlasDebugStackRead.Wait:
      begin
        Retry;
        Exit;
      end;
    TAtlasDebugStackRead.None:
      begin
        FPhase := TPhase.Idle;
        Exit;
      end;
  end;
  // Nur in Dateien mit Quelltext (#1878, Punkt 4).
  if (Length(mFrames) = 0) or not mFrames[0].HasSource then
  begin
    FPhase := TPhase.Idle;
    Exit;
  end;
  TAtlasIdeDebugSources.MarkFrames(mFrames);
  mBuffer := TAtlasIdeFiles.BufferOf(mFrames[0].FileName);
  if mBuffer = nil then
  begin
    Retry;
    Exit;
  end;
  FFileName := mBuffer.FileName;
  FLine := mFrames[0].Line - 1;
  FText := TAtlasEditorBuffer.Text(mBuffer);
  FLines := FText.Split([#13#10, #10]);
  FPhase := TPhase.Request;
  Result := True;
end;

procedure TAtlasIdeDebugWhyHere.Ask;
var
  mSession: TLspSession;
  mArguments: string;
  mRequest: Integer;
begin
  FTimer.Enabled := False;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if (mSession = nil) or not Assigned(FRun) then
  begin
    FPhase := TPhase.Idle;
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FFileName, FText);
  mArguments := TAtlasWhyHere.Arguments(TLspSession.PathToUri(FFileName), FLine,
    TAtlasIdeSettings.Current.DebugWhyHereDepth);
  Inc(FRequest);
  mRequest := FRequest;
  if not FRun(TAtlasWhyHere.cCommand, mArguments, cRequestTimeoutMs,
    procedure(AAnswer: string)
    begin
      if FInstance <> nil then
      begin
        FInstance.Accept(mRequest, AAnswer);
      end;
    end) then
  begin
    FPhase := TPhase.Idle;
  end;
end;

procedure TAtlasIdeDebugWhyHere.Accept(ARequest: Integer; const AAnswer: string);
var
  mJson: TJSONValue;
  mBlocks: TAtlasWhyHereBlocks;
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FRequest) or (FPhase <> TPhase.Request) then
  begin
    Exit;
  end;
  mBlocks := nil;
  mJson := nil;
  if AAnswer <> '' then
  begin
    mJson := TJSONObject.ParseJSONValue(AAnswer);
  end;
  try
    if not TAtlasWhyHere.ReadAnswer(mJson, mBlocks) then
    begin
      mBlocks := nil;
    end;
  finally
    mJson.Free;
  end;
  if not StillStopped or not Enabled or (Length(mBlocks) = 0) then
  begin
    FPhase := TPhase.Idle;
    Exit;
  end;
  FWhy.Start(FFileName, mBlocks);
  FPhase := TPhase.Evaluate;
  FTimer.Interval := cTickMs;
  FTimer.Enabled := True;
  EvaluateSlice;
  Invalidate;
end;

procedure TAtlasIdeDebugWhyHere.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  try
    case FPhase of
      TPhase.Location:
        begin
          FTimer.Enabled := False;
          if not StillStopped then
          begin
            FPhase := TPhase.Idle;
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

function TAtlasIdeDebugWhyHere.DeferredPending: Boolean;
begin
  Result := False;
  if not FWaiting then
  begin
    Exit;
  end;
  Result := TAtlasTicks.Since(FDeferredSince) < cDeferredTimeoutMs;
  if not Result then
  begin
    FEvaluator.Cancel;
    EndInternal;
    FWhy.Put(FDeferred, '', False);
    FWaiting := False;
  end;
end;

procedure TAtlasIdeDebugWhyHere.EvaluateSlice;
var
  mStartedAt: UInt64;
  mRef: TAtlasWhyHereRef;
  mChanged, mGoOn: Boolean;
begin
  if not StillStopped then
  begin
    Drop;
    Exit;
  end;
  if DeferredPending then
  begin
    Exit;
  end;
  mChanged := False;
  mGoOn := True;
  mStartedAt := TAtlasTicks.Now;
  while mGoOn and (TAtlasTicks.Since(mStartedAt) < cSliceMs) and FWhy.NextPending(mRef) do
  begin
    mGoOn := EvaluateOne(mRef);
    mChanged := True;
  end;
  if FPhase <> TPhase.Evaluate then
  begin
    Exit;
  end;
  if not FWaiting and not FWhy.NextPending(mRef) then
  begin
    FTimer.Enabled := False;
    FPhase := TPhase.Idle;
  end;
  if mChanged then
  begin
    Invalidate;
  end;
end;

function TAtlasIdeDebugWhyHere.EvaluateOne(const ARef: TAtlasWhyHereRef): Boolean;
var
  mValue: TAtlasDebugValue;
begin
  Result := True;
  // Eigene Auswertung: Zustandswechsel dabei sind kein Fortsetzen (TAtlasIdeDebugSession).
  mValue := Default(TAtlasDebugValue);
  TAtlasIdeDebugSession.BeginInternal;
  FInternal := True;
  try
    mValue := FEvaluator.Evaluate(ARef.Expression, FFileName, FLine + 1, ARef.SideEffects, DeferredDone);
  finally
    if mValue.State <> TAtlasDebugValueState.Pending then
    begin
      EndInternal;
    end;
  end;
  case mValue.State of
    TAtlasDebugValueState.Pending:
      begin
        FDeferred := ARef;
        FDeferredSince := TAtlasTicks.Now;
        FWaiting := True;
        Result := False;
      end;
    TAtlasDebugValueState.Value:
      FWhy.Put(ARef, mValue.Text, True);
    TAtlasDebugValueState.Failed:
      FWhy.Put(ARef, '', False);
  else
    // Kein angehaltener Prozess mehr.
    Drop;
    Result := False;
  end;
end;

procedure TAtlasIdeDebugWhyHere.DeferredDone(const AValue: TAtlasDebugValue);
begin
  if not FWaiting then
  begin
    Exit;
  end;
  EndInternal;
  FWhy.Put(FDeferred, AValue.Text, AValue.State = TAtlasDebugValueState.Value);
  FWaiting := False;
  Invalidate;
end;

procedure TAtlasIdeDebugWhyHere.RememberHit(ALine: Integer; const ARect: TRect);
var
  mHit: THit;
  mIndex: Integer;
begin
  for mIndex := FHits.Count - 1 downto 0 do
  begin
    if FHits[mIndex].Line = ALine then
    begin
      FHits.Delete(mIndex);
    end;
  end;
  mHit.Line := ALine;
  mHit.Rect := ARect;
  FHits.Add(mHit);
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

procedure TAtlasIdeDebugWhyHere.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine, mTabWidth, mX, mRight: Integer;
  mStored, mTailKey, mText: string;
  mCell: TRect;
  mSample: COLORREF;
  mDC: HDC;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or
    not FWhy.Active then
  begin
    Exit;
  end;
  try
    mLine := Context.LogicalLineNum - 1;
    mText := FWhy.LineText(Context.FileName, mLine, Texts);
    if (mText = '') or (mLine < 0) or (mLine > High(FLines)) or not LineMatches(Context, FLines[mLine], mTabWidth) then
    begin
      Exit;
    end;
    mStored := FLines[mLine];
    mDC := Context.Canvas.Handle;
    // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile bzw. hinter den Werten im Editor.
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
    mRight := FStyle.DrawText(mDC, Rect, mX, mText);
    TAtlasLineTail.Finish(Self, mTailKey, mRight);
    RememberHit(mLine, TRect.Create(mX, Rect.Top, mRight, Rect.Bottom));
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugWhyHere.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  mHit: THit;
  mLine: Integer;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FWhy.Active then
  begin
    Exit;
  end;
  mLine := -1;
  for mHit in FHits do
  begin
    if PtInRect(mHit.Rect, Point(X, Y)) then
    begin
      mLine := mHit.Line;
    end;
  end;
  if (mLine < 0) or (Length(FWhy.CallsAt(mLine)) = 0) then
  begin
    Exit;
  end;
  // Erst nach dem Mausereignis fragen: Der Editor setzt sonst den Cursor danach.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    begin
      if FInstance <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
            begin
              FInstance.AskCalls(mLine);
            end;
          end);
      end;
    end);
end;

procedure TAtlasIdeDebugWhyHere.AskCalls(ALine: Integer);
var
  mCalls: TArray<string>;
begin
  mCalls := FWhy.CallsAt(ALine);
  if (Length(mCalls) = 0) or not StillStopped then
  begin
    Exit;
  end;
  // Aufrufe können Nebenwirkungen haben: nur nach Rückfrage.
  if MessageDlg(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.WhyHereConfirmCalls, [string.Join(sLineBreak, mCalls)]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel], 0) <> mrOk then
  begin
    Exit;
  end;
  if not StillStopped then
  begin
    Exit;
  end;
  FWhy.AllowCalls(ALine);
  FPhase := TPhase.Evaluate;
  FTimer.Interval := cTickMs;
  FTimer.Enabled := True;
  EvaluateSlice;
end;

end.
