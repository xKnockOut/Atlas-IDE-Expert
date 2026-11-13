unit Atlas.IDE.Debug.WhyHere;

// „Warum bin ich hier?“ (#1878) in der IDE:
//   - Auslöser: Halt der Debug-Sitzung. Atlas liest den obersten Rahmen
//     (Datei und Zeile des Ausführungspunkts; LLDB liefert ihn verzögert).
//   - Blöcke: atlas.server.enclosingConditions über TAtlasIdeHost im
//     Hintergrund (Antwort im Hauptthread, nur solange das Modul angemeldet
//     ist); den Text der Datei gleicht Atlas vorher ab. Startet keinen Server.
//   - Werte: IOTAThread.Evaluate über TAtlasIdeDebugValueRequest ohne Nebenwirkungen
//     (eseNone), im Hauptthread in Zeitscheiben wie die Werte im Editor (#508);
//     welcher Teil als Nächstes dran ist (Kurzschluss, Aufrufe), entscheidet
//     TAtlasWhyHere.
//   - Zeichnen: am Ende der Kopfzeile, hinter den Werten im Editor
//     (TAtlasDebugLineEnd), gedimmt wie diese.
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
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.WhyHere,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.ValueRequest,
  Atlas.UI.Debug.InlineValuePainter;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasWhyHereSessionFunc = reference to function: TLspSession;
  /// <summary>Serverbefehl im Hintergrund; ADone im Hauptthread mit der Antwort als JSON-Text ('' bei Fehler).
  /// False = nicht gestartet.</summary>
  TAtlasWhyHereRunner = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeDebugWhyHere = class
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
  private class var
    FInstance: TAtlasIdeDebugWhyHere;
  private
    FSession: TAtlasWhyHereSessionFunc;
    FRun: TAtlasWhyHereRunner;
    FWhy: TAtlasWhyHere;
    FValues: TAtlasIdeDebugValueRequest;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FPhase: TPhase;
    FStop: Integer;
    FRequest: Integer;
    FRetries: Integer;
    FFileName: string;
    FLine: Integer;
    FText: string;
    FLines: TArray<string>;
    /// <summary>Gezeichneter Text je Zeile, für den Klick.</summary>
    FHits: TDictionary<Integer, TRect>;
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
    procedure ValueArrived(const ARef: TAtlasWhyHereRef; const AText: string; AOk: Boolean);
    function StillStopped: Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure AskCalls(ALine: Integer);
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
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.LineEnd,
  Atlas.UI.Debug.Strings;

const
  cSliceMs = 30;
  cTickMs = 10;
  cDeferredTimeoutMs = 500;
  cRequestTimeoutMs = 3000;
  cLocationRetries = 20;
  /// <summary>Wartezeit zwischen zwei Versuchen, den Ausführungspunkt zu lesen: so viele Takte.</summary>
  cLocationTicks = 5;

function WhyHereTexts: TAtlasWhyHereTexts;
begin
  Result := Default(TAtlasWhyHereTexts);
  Result.NotNeeded := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereNotNeeded);
  Result.NotEvaluated := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereNotEvaluated);
  Result.Failed := '?';
  Result.ElseBranch := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereElseBranch);
  Result.Of_ := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereOf);
end;

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
  FValues := TAtlasIdeDebugValueRequest.Create(cDeferredTimeoutMs);
  FHits := TDictionary<Integer, TRect>.Create;
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
  FreeAndNil(FValues);
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
  TAtlasDebugLineEnd.Invalidate;
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

procedure TAtlasIdeDebugWhyHere.Drop;
var
  mHad: Boolean;
begin
  mHad := FWhy.Active;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FValues.Cancel;
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FRequest);
  FPhase := TPhase.Idle;
  FWhy.Clear;
  FHits.Clear;
  FText := '';
  FLines := nil;
  if mHad then
  begin
    TAtlasDebugLineEnd.Invalidate;
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
  FTimer.Interval := cTickMs * cLocationTicks;
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
  mBlocks: TAtlasWhyHereBlocks;
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FRequest) or (FPhase <> TPhase.Request) then
  begin
    Exit;
  end;
  if not TAtlasWhyHere.ReadAnswerText(AAnswer, mBlocks) then
  begin
    mBlocks := nil;
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
  TAtlasDebugLineEnd.Invalidate;
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
  if FValues.Busy then
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
  if not FValues.Busy and not FWhy.NextPending(mRef) then
  begin
    FTimer.Enabled := False;
    FPhase := TPhase.Idle;
  end;
  if mChanged then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

function TAtlasIdeDebugWhyHere.EvaluateOne(const ARef: TAtlasWhyHereRef): Boolean;
var
  mRef: TAtlasWhyHereRef;
begin
  mRef := ARef;
  case FValues.Evaluate(mRef.Expression, FFileName, FLine + 1, mRef.SideEffects,
    procedure(const AText: string; AOk: Boolean)
    begin
      if FInstance <> nil then
      begin
        FInstance.ValueArrived(mRef, AText, AOk);
      end;
    end) of
    TAtlasDebugRequestState.Waiting:
      Result := False;
    TAtlasDebugRequestState.NoProcess:
      begin
        // Kein angehaltener Prozess mehr.
        Drop;
        Result := False;
      end;
  else
    Result := True;
  end;
end;

procedure TAtlasIdeDebugWhyHere.ValueArrived(const ARef: TAtlasWhyHereRef; const AText: string; AOk: Boolean);
begin
  FWhy.Put(ARef, AText, AOk);
  // Verzögerte Antworten kommen außerhalb einer Zeitscheibe: dann neu zeichnen.
  if FPhase = TPhase.Evaluate then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

procedure TAtlasIdeDebugWhyHere.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine, mX, mRight: Integer;
  mTailKey, mText: string;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or
    not FWhy.Active then
  begin
    Exit;
  end;
  try
    mLine := Context.LogicalLineNum - 1;
    mText := FWhy.LineText(Context.FileName, mLine, WhyHereTexts);
    if (mText = '') or (mLine < 0) or (mLine > High(FLines)) or not TAtlasDebugLineEnd.Matches(Context, FLines[mLine])
      then
    begin
      Exit;
    end;
    // Hinter dem letzten Zeichen der Zeile bzw. hinter den Werten im Editor.
    mX := TAtlasDebugLineEnd.Start(Self, Context, Rect, FLines[mLine], FStyle, mTailKey);
    mRight := FStyle.DrawText(Context.Canvas.Handle, Rect, mX, mText);
    TAtlasDebugLineEnd.Finish(Self, mTailKey, mRight);
    FHits.AddOrSetValue(mLine, TRect.Create(mX, Rect.Top, mRight, Rect.Bottom));
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugWhyHere.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  mHit: TPair<Integer, TRect>;
  mLine: Integer;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FWhy.Active then
  begin
    Exit;
  end;
  mLine := -1;
  for mHit in FHits do
  begin
    if mHit.Value.Contains(Point(X, Y)) then
    begin
      mLine := mHit.Key;
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
