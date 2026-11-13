unit Atlas.IDE.Debug.Pins;

// Angeheftete Debug-Werte (#526) in der IDE:
//   - Anheften über „Anheften“ unter dem Wert im Debug-Hover (Actions/Act,
//     an TAtlasEditorHover gehängt von der Komposition). Die Einträge gelten je
//     Projekt (beim Debuggen das gestartete) und stehen in
//     %LOCALAPPDATA%\Atlas\debug-pinned-values.json. Ist die Datei gesperrt,
//     beginnt Atlas leer und überschreibt sie nicht (TAtlasDataFile).
//   - Beim Halt wertet Atlas die Einträge in geöffneten Dateien über
//     TAtlasIdeDebugValues ohne Nebenwirkungen aus (eseNone, Kontext ist Datei
//     und Zeile des Eintrags), im Hauptthread in Zeitscheiben wie die Werte im
//     Editor (#508); auf verzögerte Antworten (LLDB) wartet es höchstens
//     cDeferredTimeoutMs.
//   - Zeichnen: gerahmtes Feld „Ausdruck = Wert ✕“ am Ende der Zeile, hinter
//     den Werten im Editor (TAtlasLineTail); seit dem vorigen Halt geänderte
//     Werte in der Warnfarbe. Klick auf ✕ löst den Eintrag dauerhaft.
//   - Fortsetzen lässt die Felder mit den alten Werten stehen; das Ende der
//     Sitzung blendet sie aus und vergisst die Werte, nicht die Einträge.
// Ohne debug.pinnedValues ist nichts angemeldet. Nur im Hauptthread verwenden.

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
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Pins,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Hover.DebugValue,
  Atlas.UI.Debug.InlineValuePainter;

type
  TAtlasIdeDebugPins = class
  public const
    cSliceMs = 30;
    cTickMs = 10;
    cDeferredTimeoutMs = 500;
    cFileName = 'debug-pinned-values.json';
    /// <summary>Id der Aktion „Anheften“ im Debug-Hover.</summary>
    cPinAction = 526;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    /// <summary>Kreuz eines gezeichneten Felds, für den Klick.</summary>
    THit = record
      Pin: TAtlasDebugPin;
      Rect: TRect;
    end;
  private class var
    FInstance: TAtlasIdeDebugPins;
  private
    FPins: TAtlasDebugPins;
    FKept: Boolean;
    FMessage: TProc<string>;
    FEvaluator: TAtlasIdeDebugValues;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FStop: Integer;
    /// <summary>Felder zeigen: seit dem ersten Halt der Sitzung bis zu ihrem Ende.</summary>
    FVisible: Boolean;
    FProject: string;
    FQueue: TList<TAtlasDebugPin>;
    FWaiting: Boolean;
    FDeferred: TAtlasDebugPin;
    FDeferredSince: UInt64;
    FInternal: Boolean;
    FHits: TList<THit>;
    FStyle: TAtlasInlineValuePainter;
    constructor Create(const AMessage: TProc<string>);
    procedure Load;
    procedure Save;
    procedure Stopped;
    procedure Ended;
    procedure Tick(Sender: TObject);
    procedure EvaluateSlice;
    function EvaluateOne(const APin: TAtlasDebugPin): Boolean;
    procedure DeferredDone(const AValue: TAtlasDebugValue);
    function DeferredPending: Boolean;
    procedure EndInternal;
    function StillStopped: Boolean;
    procedure Pin(const APin: TAtlasDebugPin);
    procedure Unpin(const APin: TAtlasDebugPin);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RememberHit(const APin: TAtlasDebugPin; const ARect: TRect);
    class procedure Invalidate; static;
  public
    destructor Destroy; override;
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.pinnedValues an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Aktionen unter dem Wert im Debug-Hover: „Anheften“, solange der Teil läuft.</summary>
    class function Actions(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>; static;
    /// <summary>Aktion AAction für AValue an AFileName, ALine (1-basiert).</summary>
    class procedure Act(const AValue: TAtlasDebugValue; const AFileName: string; ALine, AAction: Integer); static;
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.UI.Debug.Strings;

const
  cWhat = 'Angeheftete Werte';

function StoreFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasIdeDebugPins.cFileName);
end;

{ TAtlasIdeDebugPins.TListener }

procedure TAtlasIdeDebugPins.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
  begin
    FInstance.Stopped;
  end;
end;

procedure TAtlasIdeDebugPins.TListener.DebugEnded;
begin
  if FInstance <> nil then
  begin
    FInstance.Ended;
  end;
end;

{ TAtlasIdeDebugPins.TEvents }

function TAtlasIdeDebugPins.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeDebugPins.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugPins }

constructor TAtlasIdeDebugPins.Create(const AMessage: TProc<string>);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FMessage := AMessage;
  FIndex := -1;
  FPins := TAtlasDebugPins.Create;
  FEvaluator := TAtlasIdeDebugValues.Create;
  FQueue := TList<TAtlasDebugPin>.Create;
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
  Load;
end;

destructor TAtlasIdeDebugPins.Destroy;
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
  FreeAndNil(FQueue);
  FreeAndNil(FHits);
  FreeAndNil(FStyle);
  FreeAndNil(FPins);
  FMessage := nil;
  FProject := '';
  inherited Destroy;
end;

class procedure TAtlasIdeDebugPins.Start(const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugPins.Create(AMessage);
    FInstance.FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  end;
  TAtlasIdeDebugSession.Start;
  if TAtlasIdeDebugSession.StoppedThread <> nil then
  begin
    FInstance.Stopped;
  end;
end;

class procedure TAtlasIdeDebugPins.Release;
var
  mInstance: TAtlasIdeDebugPins;
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

class function TAtlasIdeDebugPins.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugPins.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugPinnedValues;
end;

class function TAtlasIdeDebugPins.Actions(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>;
begin
  Result := nil;
  if (FInstance <> nil) and (AValue.Expression <> '') then
  begin
    Result := TArray<TAtlasDebugValueFix>.Create(TAtlasDebugValueFix.Create(cPinAction,
      TAtlasDebugStrings.Text(TAtlasDebugTextId.PinAction)));
  end;
end;

class procedure TAtlasIdeDebugPins.Act(const AValue: TAtlasDebugValue; const AFileName: string;
  ALine, AAction: Integer);
begin
  if (FInstance <> nil) and (AAction = cPinAction) then
  begin
    FInstance.Pin(TAtlasDebugPin.Create(TAtlasIdeEvaluateStore.CurrentProject, AFileName, ALine,
      AValue.Expression));
  end;
end;

class procedure TAtlasIdeDebugPins.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

procedure TAtlasIdeDebugPins.Load;
begin
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert ohne Pfad.
  FKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile, cWhat,
    function(const AText: string): Boolean
    begin
      Result := FPins.LoadFromText(AText);
    end));
end;

procedure TAtlasIdeDebugPins.Save;
begin
  if FKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(StoreFile, FPins.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cWhat, E);
  end;
end;

procedure TAtlasIdeDebugPins.Pin(const APin: TAtlasDebugPin);
begin
  if FPins.Add(APin) then
  begin
    Save;
    // Gleich auswerten, solange der Prozess steht.
    if StillStopped then
    begin
      FQueue.Add(APin);
      FTimer.Interval := cTickMs;
      FTimer.Enabled := True;
    end;
    Invalidate;
  end
  else if (Length(FPins.All(APin.Project)) >= TAtlasDebugPins.cLimit) and Assigned(FMessage) then
  begin
    FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.PinLimit, [TAtlasDebugPins.cLimit]));
  end;
end;

procedure TAtlasIdeDebugPins.Unpin(const APin: TAtlasDebugPin);
var
  mIndex: Integer;
begin
  if not FPins.Remove(APin) then
  begin
    Exit;
  end;
  for mIndex := FQueue.Count - 1 downto 0 do
  begin
    if FQueue[mIndex].Key = APin.Key then
    begin
      FQueue.Delete(mIndex);
    end;
  end;
  Save;
  Invalidate;
end;

procedure TAtlasIdeDebugPins.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

function TAtlasIdeDebugPins.StillStopped: Boolean;
begin
  Result := FVisible and (TAtlasIdeDebugSession.StopCount = FStop) and (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeDebugPins.Stopped;
var
  mPin: TAtlasDebugPin;
begin
  FEvaluator.Cancel;
  EndInternal;
  FWaiting := False;
  FQueue.Clear;
  FPins.NewStop;
  FStop := TAtlasIdeDebugSession.StopCount;
  FProject := TAtlasIdeEvaluateStore.CurrentProject;
  FVisible := Enabled;
  if not FVisible then
  begin
    Exit;
  end;
  // Nur Einträge in geöffneten Dateien: Die anderen sieht niemand, und jede Auswertung kostet.
  for mPin in FPins.All(FProject) do
  begin
    if TAtlasIdeFiles.BufferOf(mPin.FileName) <> nil then
    begin
      FQueue.Add(mPin);
    end;
  end;
  FTimer.Interval := cTickMs;
  FTimer.Enabled := FQueue.Count > 0;
  Invalidate;
end;

procedure TAtlasIdeDebugPins.Ended;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FEvaluator.Cancel;
  EndInternal;
  FWaiting := False;
  FQueue.Clear;
  FHits.Clear;
  FPins.EndSession;
  if FVisible then
  begin
    FVisible := False;
    Invalidate;
  end;
end;

procedure TAtlasIdeDebugPins.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  try
    EvaluateSlice;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  end;
end;

function TAtlasIdeDebugPins.DeferredPending: Boolean;
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
    FPins.Put(FDeferred, '', False);
    FWaiting := False;
  end;
end;

procedure TAtlasIdeDebugPins.EvaluateSlice;
var
  mStartedAt: UInt64;
  mChanged, mGoOn: Boolean;
  mPin: TAtlasDebugPin;
begin
  if not StillStopped then
  begin
    FTimer.Enabled := False;
    FQueue.Clear;
    Exit;
  end;
  if DeferredPending then
  begin
    Exit;
  end;
  mChanged := False;
  mGoOn := True;
  mStartedAt := TAtlasTicks.Now;
  while mGoOn and (FQueue.Count > 0) and (TAtlasTicks.Since(mStartedAt) < cSliceMs) do
  begin
    mPin := FQueue[0];
    FQueue.Delete(0);
    mGoOn := EvaluateOne(mPin);
    mChanged := True;
  end;
  if not FWaiting and (FQueue.Count = 0) then
  begin
    FTimer.Enabled := False;
  end;
  if mChanged then
  begin
    Invalidate;
  end;
end;

function TAtlasIdeDebugPins.EvaluateOne(const APin: TAtlasDebugPin): Boolean;
var
  mValue: TAtlasDebugValue;
begin
  Result := True;
  // Eigene Auswertung: Zustandswechsel dabei sind kein Fortsetzen (TAtlasIdeDebugSession).
  mValue := Default(TAtlasDebugValue);
  TAtlasIdeDebugSession.BeginInternal;
  FInternal := True;
  try
    mValue := FEvaluator.Evaluate(APin.Expression, APin.FileName, APin.Line, False, DeferredDone);
  finally
    if mValue.State <> TAtlasDebugValueState.Pending then
    begin
      EndInternal;
    end;
  end;
  case mValue.State of
    TAtlasDebugValueState.Pending:
      begin
        FDeferred := APin;
        FDeferredSince := TAtlasTicks.Now;
        FWaiting := True;
        Result := False;
      end;
    TAtlasDebugValueState.Value:
      FPins.Put(APin, mValue.Text, True);
    TAtlasDebugValueState.Failed:
      FPins.Put(APin, '', False);
  else
    // Kein angehaltener Prozess mehr.
    FQueue.Clear;
    Result := False;
  end;
end;

procedure TAtlasIdeDebugPins.DeferredDone(const AValue: TAtlasDebugValue);
begin
  if not FWaiting then
  begin
    Exit;
  end;
  EndInternal;
  FPins.Put(FDeferred, AValue.Text, AValue.State = TAtlasDebugValueState.Value);
  FWaiting := False;
  Invalidate;
end;

procedure TAtlasIdeDebugPins.RememberHit(const APin: TAtlasDebugPin; const ARect: TRect);
var
  mHit: THit;
  mIndex: Integer;
begin
  for mIndex := FHits.Count - 1 downto 0 do
  begin
    if FHits[mIndex].Pin.Key = APin.Key then
    begin
      FHits.Delete(mIndex);
    end;
  end;
  mHit.Pin := APin;
  mHit.Rect := ARect;
  FHits.Add(mHit);
end;

/// <summary>Tabweite des Puffers im Zeichenkontext; 0 ohne.</summary>
function TabWidth(const AContext: INTACodeEditorPaintContext): Integer;
begin
  Result := 0;
  if (AContext.EditView <> nil) and (AContext.EditView.Buffer <> nil) then
  begin
    Result := TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer);
  end;
end;

procedure TAtlasIdeDebugPins.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mPin: TAtlasDebugPin;
  mLineState: INTACodeEditorLineState;
  mCell, mClose: TRect;
  mTailKey: string;
  mX: Integer;
  mSample: COLORREF;
  mDC: HDC;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or
    not FVisible then
  begin
    Exit;
  end;
  try
    mLineState := Context.LineState;
    if mLineState = nil then
    begin
      Exit;
    end;
    mTailKey := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
    mX := -1;
    mDC := Context.Canvas.Handle;
    for mPin in FPins.InFile(FProject, Context.FileName) do
    begin
      if mPin.Line <> Context.LogicalLineNum then
      begin
        Continue;
      end;
      if mX < 0 then
      begin
        // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile bzw. hinter den Werten im Editor.
        mCell := Context.EditorState.GetCharacterPosPx(Length(TAtlasPairs.DisplayLine(TrimRight(mLineState.Text),
          TabWidth(Context))) + 3, Context.EditorLineNum);
        mX := TAtlasLineTail.Start(Self, mTailKey, mCell.Left);
        mSample := GetPixel(mDC, mX, Rect.Top + 1);
        if mSample = CLR_INVALID then
        begin
          mSample := COLORREF(ColorToRGB(Context.Canvas.Brush.Color));
        end;
        FStyle.Ensure(mSample, Context.Canvas.Font);
      end;
      mX := FStyle.DrawPin(mDC, Rect, mX, FPins.ValueOf(mPin), mClose) + 6;
      RememberHit(mPin, mClose);
    end;
    if mX >= 0 then
    begin
      TAtlasLineTail.Finish(Self, mTailKey, mX);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugPins.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mHit: THit;
  mPin: TAtlasDebugPin;
  mFound: Boolean;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FVisible then
  begin
    Exit;
  end;
  mFound := False;
  for mHit in FHits do
  begin
    if PtInRect(mHit.Rect, Point(X, Y)) then
    begin
      mPin := mHit.Pin;
      mFound := True;
    end;
  end;
  if not mFound then
  begin
    Exit;
  end;
  // Nach dem Mausereignis lösen: Der Editor setzt sonst danach noch den Cursor in die gelöste Zeile.
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
              FInstance.Unpin(mPin);
            end;
          end);
      end;
    end);
end;

end.
