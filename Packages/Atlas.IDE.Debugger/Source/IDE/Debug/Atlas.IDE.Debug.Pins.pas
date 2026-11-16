unit Atlas.IDE.Debug.Pins;

// Angeheftete Debug-Werte (#526) in der IDE:
//   - Anheften über „Anheften“ unter dem Wert im Debug-Hover (Actions/Act,
//     an TAtlasEditorHover gehängt von der Komposition). Die Einträge gelten je
//     Projekt (beim Debuggen das gestartete) und stehen in
//     %LOCALAPPDATA%\Atlas\debug-pinned-values.json. Ist die Datei gesperrt,
//     beginnt Atlas leer und überschreibt sie nicht (TAtlasDataFile).
//   - Beim Halt wertet Atlas die Einträge in geöffneten Dateien über
//     TAtlasIdeDebugValueRequest ohne Nebenwirkungen aus (eseNone, Kontext ist Datei
//     und Zeile des Eintrags), im Hauptthread in Zeitscheiben wie die Werte im
//     Editor (#508); auf verzögerte Antworten (LLDB) wartet es höchstens
//     cDeferredTimeoutMs.
//   - Zeichnen: gerahmtes Feld „Ausdruck = Wert ✕“ am Ende der Zeile, hinter
//     den Werten im Editor (TAtlasDebugLineEnd); seit dem vorigen Halt geänderte
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
  Vcl.Controls,
  ToolsAPI.Editor,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Pins,
  Atlas.Core.Debug.PinsFlow,
  Atlas.IDE.Debug.StopView,

  Atlas.IDE.Debug.ValueRequest,
  Atlas.UI.Debug.InlineValuePainter;

type
  TAtlasIdeDebugPins = class(TAtlasIdeDebugStopView)
  public const
    /// <summary>Id der Aktion „Anheften“ im Debug-Hover.</summary>
    cPinAction = 526;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeDebugPins;
  private
    FPins: TAtlasDebugPins;
    FKept: Boolean;
    FMessage: TProc<string>;
    FValues: TAtlasIdeDebugValueRequest;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FStop: Integer;
    /// <summary>Felder zeigen: seit dem ersten Halt der Sitzung bis zu ihrem Ende.</summary>
    FVisible: Boolean;
    FProject: string;
    FQueue: TList<TAtlasDebugPin>;
    FHits: TList<TAtlasPinHit>;
    FStyle: TAtlasInlineValuePainter;
    constructor Create(const AMessage: TProc<string>);
    procedure Load;
    procedure Save;
    function EvaluateOne(const APin: TAtlasDebugPin): Boolean;
    procedure ValueArrived(const APin: TAtlasDebugPin; const AText: string; AOk: Boolean);
    function StillStopped: Boolean;
    procedure Pin(const APin: TAtlasDebugPin);
    procedure Unpin(const APin: TAtlasDebugPin);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RememberHit(const APin: TAtlasDebugPin; const ARect: TRect);
    function CanPaint(const AContext: INTACodeEditorPaintContext): Boolean;
  protected
    procedure SessionStopped; override;
    procedure SessionEnded; override;
    /// <summary>Jeder Takt wertet ein Stück der Pins aus.</summary>
    procedure Advance; override;
    procedure EvaluateSlice; override;
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
    /// <summary>Im selben Halt neu auswerten, etwa nach dem Ändern eines Werts (#868).</summary>
    class procedure Reevaluate; static;
  end;

implementation

uses
  Atlas.IDE.Debug.Session,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.IDE.Debug.LineEnd,
  Atlas.UI.Debug.Values.Strings;

const
  cWhat = 'Angeheftete Werte';
  cFileName = 'debug-pinned-values.json';
  cSliceMs = 30;
  cTickMs = 10;
  cDeferredTimeoutMs = 500;
  /// <summary>Abstand in Pixeln zwischen zwei Feldern einer Zeile.</summary>
  cFieldGap = 6;

function StoreFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    cFileName);
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
  FValues := TAtlasIdeDebugValueRequest.Create(cDeferredTimeoutMs);
  FQueue := TList<TAtlasDebugPin>.Create;
  FHits := TList<TAtlasPinHit>.Create;
  FStyle := TAtlasInlineValuePainter.Create;
  CreateTimer(cTickMs);
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
  FreeAndNil(FValues);
  FreeAndNil(FQueue);
  FreeAndNil(FHits);
  FreeAndNil(FStyle);
  FreeAndNil(FPins);
  FMessage := nil;
  FProject := '';
  inherited Destroy;
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

procedure TAtlasIdeDebugPins.SessionStopped;
var
  mPin: TAtlasDebugPin;
begin
  FValues.Cancel;
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
  TAtlasDebugLineEnd.Invalidate;
end;

procedure TAtlasIdeDebugPins.SessionEnded;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FValues.Cancel;
  FQueue.Clear;
  FHits.Clear;
  FPins.EndSession;
  if FVisible then
  begin
    FVisible := False;
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

procedure TAtlasIdeDebugPins.Advance;
begin
  EvaluateSlice;
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
  if FValues.Busy then
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
  if not FValues.Busy and (FQueue.Count = 0) then
  begin
    FTimer.Enabled := False;
  end;
  if mChanged then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

function TAtlasIdeDebugPins.EvaluateOne(const APin: TAtlasDebugPin): Boolean;
var
  mPin: TAtlasDebugPin;
begin
  mPin := APin;
  case FValues.Evaluate(mPin.Expression, mPin.FileName, mPin.Line, False,
    procedure(const AText: string; AOk: Boolean)
    begin
      if FInstance <> nil then
      begin
        FInstance.ValueArrived(mPin, AText, AOk);
      end;
    end) of
    TAtlasDebugRequestState.Waiting:
      Result := False;
    TAtlasDebugRequestState.NoProcess:
      begin
        // Kein angehaltener Prozess mehr.
        FQueue.Clear;
        Result := False;
      end;
  else
    Result := True;
  end;
end;

procedure TAtlasIdeDebugPins.ValueArrived(const APin: TAtlasDebugPin; const AText: string; AOk: Boolean);
begin
  FPins.Put(APin, AText, AOk);
  // Verzögerte Antworten kommen außerhalb einer Zeitscheibe: neu zeichnen.
  TAtlasDebugLineEnd.Invalidate;
end;

function TAtlasIdeDebugPins.StillStopped: Boolean;
begin
  Result := TAtlasPinsFlow.StillStopped(FVisible, FStop, TAtlasIdeDebugSession.StopCount,
    TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeDebugPins.Pin(const APin: TAtlasDebugPin);
var
  mAdded: Boolean;
begin
  mAdded := FPins.Add(APin);
  if mAdded then
  begin
    Save;
    // Gleich auswerten, solange der Prozess steht.
    if StillStopped then
    begin
      FQueue.Add(APin);
      FTimer.Interval := cTickMs;
      FTimer.Enabled := True;
    end;
    TAtlasDebugLineEnd.Invalidate;
  end
  else if TAtlasPinsFlow.ReportLimit(mAdded, Length(FPins.All(APin.Project))) and Assigned(FMessage) then
  begin
    FMessage(TAtlasValuesStrings.Fmt(TAtlasValuesTextId.PinLimit, [TAtlasDebugPins.cLimit]));
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
  TAtlasDebugLineEnd.Invalidate;
end;

procedure TAtlasIdeDebugPins.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mPin: TAtlasDebugPin;
  mClose: TRect;
  mTailKey: string;
  mX: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or not CanPaint(Context) then
  begin
    Exit;
  end;
  try
    mX := -1;
    for mPin in TAtlasPinsFlow.OnLine(FPins.InFile(FProject, Context.FileName), Context.LogicalLineNum) do
    begin
      if mX < 0 then
      begin
        // Hinter dem letzten Zeichen der Zeile bzw. hinter den Werten im Editor.
        mX := TAtlasDebugLineEnd.Start(Self, Context, Rect, Context.LineState.Text, FStyle, mTailKey);
      end;
      mX := FStyle.DrawPin(Context.Canvas.Handle, Rect, mX, FPins.ValueOf(mPin), mClose) + cFieldGap;
      RememberHit(mPin, mClose);
    end;
    if mX >= 0 then
    begin
      TAtlasDebugLineEnd.Finish(Self, mTailKey, mX);
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
  mPin: TAtlasDebugPin;
begin
  if not TAtlasPinsFlow.WantsClick(Button = mbLeft, Shift * [ssShift, ssCtrl, ssAlt] <> [], FVisible) then
  begin
    Exit;
  end;
  if not TAtlasPinsFlow.HitAt(FHits.ToArray, Point(X, Y), mPin) then
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

procedure TAtlasIdeDebugPins.RememberHit(const APin: TAtlasDebugPin; const ARect: TRect);
var
  mHit: TAtlasPinHit;
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

function TAtlasIdeDebugPins.CanPaint(const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := FVisible and (AContext <> nil) and (AContext.LineState <> nil) and
    not TAtlasGuard.Disabled(TAtlasFeature.Debugger);
end;

class procedure TAtlasIdeDebugPins.Start(const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugPins.Create(AMessage);
    FInstance.Listen;
  end;
  TAtlasIdeDebugSession.Start;
  if TAtlasIdeDebugSession.StoppedThread <> nil then
  begin
    FInstance.SessionStopped;
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
  mInstance.Free;
  TAtlasDebugLineEnd.Invalidate;
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
  if TAtlasPinsFlow.CanOffer(FInstance <> nil, AValue.Expression) then
  begin
    Result := TArray<TAtlasDebugValueFix>.Create(TAtlasDebugValueFix.Create(cPinAction,
      TAtlasValuesStrings.Text(TAtlasValuesTextId.PinAction)));
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

class procedure TAtlasIdeDebugPins.Reevaluate;
begin
  if (FInstance <> nil) and FInstance.FVisible and (TAtlasIdeDebugSession.StoppedThread <> nil) then
  begin
    FInstance.SessionStopped;
  end;
end;

end.
