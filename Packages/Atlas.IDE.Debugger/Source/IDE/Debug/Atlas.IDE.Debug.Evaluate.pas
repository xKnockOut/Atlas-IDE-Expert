unit Atlas.IDE.Debug.Evaluate;

// Fenster „Auswerten“ (#784) in der IDE:
//   - Zeilen: TAtlasEvalList, angezeigt in TAtlasDebugEvaluateFrame
//     (andockbar, TAtlasIdeDebugEvaluateWindow). Enter im Eingabefeld fügt
//     einen Ausdruck an, Entf entfernt eine Zeile.
//   - Auswerten: bei jedem Halt der Debug-Sitzung alle Zeilen und die
//     aufgeklappten Felder neu, über TAtlasIdeDebugValues im Hauptthread in
//     Zeitscheiben von höchstens SliceMs (wie die Werte im Editor, #508);
//     verzögerte Antworten (LLDB) höchstens DeferredTimeoutMs. Gültigkeits-
//     bereich ist der Ausführungspunkt (oberster Rahmen mit Quelltext).
//     Geänderte Werte markiert TAtlasEvalList gegenüber dem letzten Halt.
//     Ohne „Nebenwirkungen erlauben“ (Vorgabe aus) wertet Atlas mit eseNone
//     aus: keine Funktionsaufrufe, keine Getter.
//   - Aufklappen: Felder aus dem Atlas-Index über atlas/expressionCompletion
//     auf „Ausdruck.“ (Felder; mit Nebenwirkungen auch Eigenschaften), jedes
//     einzeln ausgewertet. Ohne Server oder ohne Felder zerlegt Atlas den
//     Ergebnis-String (TAtlasEvalList.SetParts). Die Anfrage läuft im
//     Hintergrund; der Text der Datei wird vorher im Hauptthread abgeglichen.
//   - Ansicht Zeilen: wertet „Ausdruck.Text“ aus (TStrings).
//   - „Ändern …“ (F2): neuer Wert über InputQuery, IOTAThread.Modify, danach
//     wird die Zeile neu ausgewertet.
//   - Festheften (Strg+Enter): Die ToolsAPI bietet keinen Zugriff auf die
//     Überwachungsliste der IDE; Atlas heftet den Ausdruck daher im Fenster
//     fest. Festgeheftete Zeilen stehen je Projekt in
//     %LOCALAPPDATA%\Atlas\debug-evaluate-pinned.json und kommen mit dem
//     Projekt wieder.
//   - Verlauf (TAtlasIdeEvaluateStore): die letzten HistoryLimit Ausdrücke je Projekt in
//     %LOCALAPPDATA%\Atlas\debug-evaluate-history.json; Pfeil nach unten im
//     leeren Eingabefeld zeigt sie. Die Vervollständigung (#538) gilt auch im
//     Eingabefeld (OwnField).
//   - Strg+F7 (debug.evaluateWindow.replaceCtrlF7): Atlas hängt sich in die
//     Aktion „Auswerten/Ändern“ der IDE (TAtlasIdeEvaluateHook, sonst die Aktion
//     mit Strg+F7) und öffnet stattdessen das Fenster mit dem Ausdruck unter
//     dem Cursor bzw. der einzeiligen Markierung. Mit gedrückter
//     Umschalttaste (auch beim Klick im Menü), mit dem Befehl
//     Atlas.DebugEvaluateIdeDialog und ausgeschaltet öffnet die IDE ihren
//     Dialog.
//   - Kein Zugriff (#840): Scheitert eine Auswertung mit einem bekannten Text,
//     steht „‹kein Zugriff›“ vor der Meldung (TAtlasIdeDebugUnavailable).
// Ohne debug.evaluateWindow ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.EvalSlices,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.StopView,
  Atlas.IDE.Debug.EvaluateHook,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.IDE.Debug.FieldRequests;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasEvaluateSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugEvaluate = class(TAtlasIdeDebugStopView)
  public const
    cSliceMs = 30;
    cTickMs = 10;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    cDeferredTimeoutMs = 2000;
    /// <summary>Versuche, bis der Aufrufstapel da ist (je TickMs * 5).</summary>
    cLocationRetries = 20;
  private type
    /// <summary>Ausführungspunkt: Datei und Zeile (0-basiert, -1 ohne).</summary>
    TPlace = record
      FileName: string;
      Line: Integer;
    end;
    /// <summary>Ansicht Zeilen: „Ausdruck.Text“ einer Zeile.</summary>
    TLines = class
    private
      FEvaluator: IAtlasDebugEvaluator;
      FKey: string;
      procedure Done(const AValue: TAtlasDebugValue);
    public
      constructor Create;
      destructor Destroy; override;
      procedure Fetch(ANode: TAtlasEvalNode; const APlace: TPlace; ASideEffects: Boolean);
      procedure Cancel;
    end;
  private class var
    FInstance: TAtlasIdeDebugEvaluate;
  private
    FSession: TAtlasEvaluateSessionFunc;
    FList: TAtlasEvalList;
    /// <summary>Werte der Zeilen und aufgeklappten Felder in Zeitscheiben.</summary>
    FEvaluation: TAtlasEvalSlices;
    FLines: TLines;
    /// <summary>Für „Ändern …“.</summary>
    FThread: IAtlasDebugEvaluator;
    FHook: TAtlasIdeEvaluateHook;
    FWorkers: TAtlasIdeDebugFieldRequests;
    FPlace: TPlace;
    FSideEffects: Boolean;
    FStore: TAtlasIdeEvaluateStore;
    constructor Create(const ASession: TAtlasEvaluateSessionFunc);
    procedure CancelWork;
    procedure StartEvaluate;
    procedure Add(const AExpression: string; APinned: Boolean);
    procedure Delete(ANode: TAtlasEvalNode);
    procedure TogglePin(ANode: TAtlasEvalNode);
    procedure Expand(const AKey: string);
    procedure AcceptFields(ARequest: Integer; const AKey: string; const AFields: TArray<string>);
    procedure Modify(ANode: TAtlasEvalNode);
    procedure SetSideEffects(AValue: Boolean);
    procedure SyncPinned;
    /// <summary>Strg+F7 über die Aktion der IDE an Atlas (AValue) bzw. wieder an die IDE.</summary>
    procedure SetHooked(AValue: Boolean);
  protected
    procedure SessionStarted; override;
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    /// <summary>Datei und Zeile des Ausführungspunkts; False: später noch einmal (Phase bleibt Location).
    /// </summary>
    function ReadLocation: Boolean; override;
    /// <summary>Am gelesenen Ausführungspunkt: StartEvaluate.</summary>
    procedure Ask; override;
    procedure EvaluateSlice; override;
  public
    destructor Destroy; override;
    class procedure Start(const ASession: TAtlasEvaluateSessionFunc); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.evaluateWindow an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Fenster zeigen, Ausdruck unter dem Cursor ins Eingabefeld (Befehl Atlas.DebugEvaluate, Strg+F7).
    /// </summary>
    class procedure ShowWindow; overload; static;
    /// <summary>Fenster zeigen und AExpression als Zeile auswerten („Ausdruck auswerten“ der Exception-Leiste,
    /// #865).</summary>
    class procedure ShowWindow(const AExpression: string); overload; static;
    /// <summary>Dialog „Auswerten/Ändern“ der IDE öffnen (Befehl Atlas.DebugEvaluateIdeDialog).</summary>
    class procedure OpenIdeDialog; static;
  end;

implementation

uses
  Atlas.UI.Debug.EvaluateFrame,
  Vcl.Controls,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.EvaluateRows,
  Atlas.Core.Debug.StopProgress,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.ThreadEvaluator,
  Atlas.IDE.Debug.DialogCompletion,
  Atlas.IDE.Debug.EvaluateWindow,
  Atlas.UI.Debug.Evaluate.Strings;

/// <summary>Das Fenster, falls es schon besteht; sonst nil.</summary>
function Frame: TAtlasDebugEvaluateFrame;
begin
  Result := TAtlasIdeDebugEvaluateWindow.ExistingFrame;
end;

/// <summary>Das Fenster neu zeichnen, falls es besteht.</summary>
procedure RefreshFrame;
var
  mFrame: TAtlasDebugEvaluateFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.Refresh;
  end;
end;

function StillStopped: Boolean;
begin
  Result := TAtlasIdeDebugSession.StoppedThread <> nil;
end;

/// <summary>Kennzeichnung „kein Zugriff“ (#840) der Fehlertexte; die Ursache erklärt der Hover.</summary>
function Unavailable: TAtlasEvalUnavailable;
begin
  Result := TAtlasEvalUnavailable.Create(TAtlasIdeDebugUnavailable.InlineCaption, TAtlasIdeDebugUnavailable.Patterns);
end;

/// <summary>Einzeilige Markierung, sonst der Ausdruck unter dem Cursor des obersten Editors.</summary>
function CursorExpression: string;
var
  mView: IOTAEditView;
  mBlock: IOTAEditBlock;
  mCursor: TOTAEditPos;
  mLine: string;
begin
  Result := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if mView = nil then
  begin
    Exit;
  end;
  mBlock := mView.Block;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) and (mBlock.StartingRow = mBlock.EndingRow) then
  begin
    Result := Trim(mBlock.Text);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  mCursor := mView.CursorPos;
  mLine := TAtlasEditorBuffer.LineText(mView, mCursor.Line);
  Result := TAtlasEvalText.ExpressionAt(mLine, TLspSession.ColumnToIndex(mLine, mCursor.Col,
    TAtlasEditorBuffer.TabWidth(mView.Buffer)));
end;

/// <summary>Strg+F7 an Atlas statt an die IDE? (Die Umschalttaste prüft der Haken.)</summary>
function Intercepts: Boolean;
begin
  Result := (TAtlasIdeDebugEvaluate.FInstance <> nil) and TAtlasIdeDebugEvaluate.Enabled and
    TAtlasIdeSettings.Current.DebugEvaluateReplaceCtrlF7;
end;

/// <summary>Felder für AKey an AcceptFields, solange das Fenster angemeldet ist.</summary>
function FieldsArrived(ARequest: Integer; const AKey: string): TAtlasDebugFieldsArrived;
var
  mKey: string;
begin
  mKey := AKey;
  Result :=
    procedure(const AFields: TArray<string>)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.AcceptFields(ARequest, mKey, AFields);
      end;
    end;
end;

/// <summary>Aufklappen nicht in der Benachrichtigung des Baums: später im Hauptthread.</summary>
procedure QueueExpand(const AKey: string);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.Expand(AKey);
      end;
    end);
end;

/// <summary>Zeilen anfügen, festheften und entfernen.</summary>
procedure WireRows(AFrame: TAtlasDebugEvaluateFrame);
begin
  AFrame.Hooks.Add :=
    procedure(AExpression: string)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.Add(AExpression, False);
      end;
    end;
  AFrame.Hooks.PinExpression :=
    procedure(AExpression: string)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.Add(AExpression, True);
      end;
    end;
  AFrame.Hooks.Pin :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.TogglePin(ANode);
      end;
    end;
  AFrame.Hooks.Delete :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.Delete(ANode);
      end;
    end;
  AFrame.Hooks.History :=
    function: TArray<string>
    begin
      Result := nil;
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        Result := TAtlasIdeDebugEvaluate.FInstance.FStore.HistoryItems;
      end;
    end;
end;

/// <summary>Werte aufklappen, ändern, als Zeilen zeigen; Nebenwirkungen und Dialog der IDE.</summary>
procedure WireValues(AFrame: TAtlasDebugEvaluateFrame);
begin
  AFrame.Hooks.Expand :=
    procedure(ANode: TAtlasEvalNode)
    begin
      QueueExpand(ANode.Key);
    end;
  AFrame.Hooks.Modify :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.Modify(ANode);
      end;
    end;
  AFrame.Hooks.Lines :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.FLines.Fetch(ANode, TAtlasIdeDebugEvaluate.FInstance.FPlace,
          TAtlasIdeDebugEvaluate.FInstance.FSideEffects);
      end;
    end;
  AFrame.Hooks.SideEffects :=
    procedure(AValue: Boolean)
    begin
      if TAtlasIdeDebugEvaluate.FInstance <> nil then
      begin
        TAtlasIdeDebugEvaluate.FInstance.SetSideEffects(AValue);
      end;
    end;
  AFrame.Hooks.IdeDialog :=
    procedure
    begin
      TAtlasIdeDebugEvaluate.OpenIdeDialog;
    end;
end;

/// <summary>AFrame an die Instanz hängen (nach jedem Anlegen des Fensters).</summary>
procedure WireFrame(AFrame: TAtlasDebugEvaluateFrame);
begin
  if TAtlasIdeDebugEvaluate.FInstance = nil then
  begin
    Exit;
  end;
  WireRows(AFrame);
  WireValues(AFrame);
  AFrame.SetSideEffects(TAtlasIdeDebugEvaluate.FInstance.FSideEffects);
  AFrame.SetList(TAtlasIdeDebugEvaluate.FInstance.FList);
end;

{ TAtlasIdeDebugEvaluate.TLines }

constructor TAtlasIdeDebugEvaluate.TLines.Create;
begin
  inherited Create;
  FEvaluator := TAtlasIdeDebugThreadEvaluator.Create;
end;

destructor TAtlasIdeDebugEvaluate.TLines.Destroy;
begin
  Cancel;
  FEvaluator := nil;
  inherited Destroy;
end;

procedure TAtlasIdeDebugEvaluate.TLines.Done(const AValue: TAtlasDebugValue);
var
  mKey: string;
begin
  mKey := FKey;
  FKey := '';
  if (mKey <> '') and (Frame <> nil) then
  begin
    Frame.SetLines(mKey, AValue.State = TAtlasDebugValueState.Value, AValue.Text);
  end;
end;

procedure TAtlasIdeDebugEvaluate.TLines.Fetch(ANode: TAtlasEvalNode; const APlace: TPlace; ASideEffects: Boolean);
var
  mValue: TAtlasDebugValue;
begin
  Cancel;
  FKey := ANode.Key;
  if not StillStopped or (ANode.Expression = '') then
  begin
    Done(Default(TAtlasDebugValue));
    Exit;
  end;
  mValue := FEvaluator.Evaluate(TAtlasEvalText.FieldExpression(ANode.Expression, 'Text'), APlace.FileName,
    APlace.Line + 1, ASideEffects, Done);
  if mValue.State <> TAtlasDebugValueState.Pending then
  begin
    Done(mValue);
  end;
end;

procedure TAtlasIdeDebugEvaluate.TLines.Cancel;
begin
  FEvaluator.Cancel;
  FKey := '';
end;

{ TAtlasIdeDebugEvaluate }

constructor TAtlasIdeDebugEvaluate.Create(const ASession: TAtlasEvaluateSessionFunc);
begin
  inherited Create;
  FSession := ASession;
  FPlace.Line := -1;
  FList := TAtlasEvalList.Create;
  FEvaluation := TAtlasEvalSlices.Create(TAtlasIdeDebugThreadEvaluator.Create, cSliceMs, cDeferredTimeoutMs);
  FEvaluation.OnArrived := RefreshFrame;
  FLines := TLines.Create;
  FThread := TAtlasIdeDebugThreadEvaluator.Create;
  FWorkers := TAtlasIdeDebugFieldRequests.Create;
  FStore := TAtlasIdeEvaluateStore.Create;
  CreateTimer(cTickMs);
end;

destructor TAtlasIdeDebugEvaluate.Destroy;
begin
  SetHooked(False);
  // FWorkers entsteht als letztes Teil der Auswertung: ohne ihn ist nichts zu beenden.
  if FWorkers <> nil then
  begin
    CancelWork;
    // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
    FWorkers.Reap(True);
  end;
  FreeAndNil(FWorkers);
  FreeAndNil(FLines);
  FThread := nil;
  FreeAndNil(FEvaluation);
  FreeAndNil(FStore);
  FreeAndNil(FList);
  inherited Destroy;
end;

procedure TAtlasIdeDebugEvaluate.SessionStarted;
begin
  SyncPinned;
end;

procedure TAtlasIdeDebugEvaluate.SessionStopped;
begin
  CancelWork;
  if not Enabled then
  begin
    Exit;
  end;
  FList.BeginStop;
  if Frame <> nil then
  begin
    Frame.InvalidateLines;
  end;
  FProgress.Stop := TAtlasIdeDebugSession.StopCount;
  FProgress.Retries := 0;
  FProgress.Phase := TAtlasStopPhase.Location;
  RefreshFrame;
  if ReadLocation then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugEvaluate.SessionResumed;
begin
  // Die Werte bleiben grau stehen bis zum nächsten Halt; nur laufende Auswertungen enden.
  CancelWork;
end;

procedure TAtlasIdeDebugEvaluate.SessionEnded;
begin
  CancelWork;
  FList.Unavailable;
  FPlace := Default(TPlace);
  FPlace.Line := -1;
  RefreshFrame;
end;

procedure TAtlasIdeDebugEvaluate.CancelWork;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FEvaluation.Cancel;
  FLines.Cancel;
  // Antworten noch laufender Feldanfragen verwerfen.
  Inc(FProgress.Request);
  FProgress.Phase := TAtlasStopPhase.Idle;
  FWorkers.Reap(False);
end;

function TAtlasIdeDebugEvaluate.ReadLocation: Boolean;
var
  mFrames: TAtlasDebugFrames;
begin
  Result := True;
  FPlace := Default(TPlace);
  FPlace.Line := -1;
  case TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, mFrames) of
    TAtlasDebugStackRead.Wait:
      begin
        // LLDB: Stapel kommt später; nach LocationRetries ohne Ort weiter.
        Inc(FProgress.Retries);
        if FProgress.Retries <= cLocationRetries then
        begin
          FTimer.Interval := cTickMs * 5;
          FTimer.Enabled := True;
          Result := False;
        end;
      end;
    TAtlasDebugStackRead.Ready:
      if (Length(mFrames) > 0) and mFrames[0].HasSource then
      begin
        TAtlasIdeDebugSources.MarkFrames(mFrames);
        FPlace.FileName := mFrames[0].FileName;
        FPlace.Line := mFrames[0].Line - 1;
      end;
  end;
end;

procedure TAtlasIdeDebugEvaluate.Ask;
begin
  StartEvaluate;
end;

procedure TAtlasIdeDebugEvaluate.StartEvaluate;
begin
  if StillStopped then
  begin
    BeginEvaluate(cTickMs);
  end;
end;

procedure TAtlasIdeDebugEvaluate.EvaluateSlice;
var
  mChanged: Boolean;
begin
  if not StillStopped then
  begin
    CancelWork;
    Exit;
  end;
  // Verzögerter Wert (LLDB): höchstens DeferredTimeoutMs warten, dann ohne ihn weiter.
  if FEvaluation.Waiting and not FEvaluation.Overdue then
  begin
    Exit;
  end;
  // Kennzeichnung „kein Zugriff“ wie im Hover: Die Muster lassen sich ergänzen.
  FEvaluation.Unavailable := Unavailable;
  FEvaluation.TimeoutText := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateTimeout);
  if FEvaluation.Waiting then
  begin
    FEvaluation.Expire;
    RefreshFrame;
  end;
  if FEvaluation.Slice(TArray<TAtlasEvalList>.Create(FList), TAtlasEvalPlace.Create(FPlace.FileName, FPlace.Line,
    FSideEffects), mChanged) = TAtlasEvalSliceStep.Stopped then
  begin
    // Kein angehaltener Prozess mehr.
    CancelWork;
    RefreshFrame;
    Exit;
  end;
  if not FEvaluation.Waiting and (Length(FList.Pending) = 0) then
  begin
    FTimer.Enabled := False;
    FProgress.Phase := TAtlasStopPhase.Idle;
  end;
  if mChanged then
  begin
    RefreshFrame;
  end;
end;

procedure TAtlasIdeDebugEvaluate.Add(const AExpression: string; APinned: Boolean);
var
  mNode: TAtlasEvalNode;
begin
  mNode := FList.Add(AExpression);
  if mNode = nil then
  begin
    Exit;
  end;
  FStore.Remember(mNode.Expression);
  if APinned then
  begin
    mNode.Pinned := True;
    FStore.Pin(mNode.Expression);
  end;
  if not StillStopped then
  begin
    mNode.State := TAtlasEvalState.Unavailable;
  end;
  RefreshFrame;
  if Frame <> nil then
  begin
    Frame.Select(mNode.Key);
  end;
  if StillStopped and (FProgress.Phase = TAtlasStopPhase.Idle) then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugEvaluate.Delete(ANode: TAtlasEvalNode);
var
  mIndex: Integer;
begin
  mIndex := FList.IndexOf(ANode);
  if mIndex < 0 then
  begin
    Exit;
  end;
  if ANode.Pinned then
  begin
    FStore.Unpin(ANode.Expression);
  end;
  // Läuft gerade die Auswertung dieser Zeile oder eines ihrer Felder: verwerfen, sonst kommt sie ins Leere.
  FEvaluation.Drop(FList, ANode.Key);
  FList.Delete(mIndex);
  RefreshFrame;
end;

procedure TAtlasIdeDebugEvaluate.TogglePin(ANode: TAtlasEvalNode);
begin
  if ANode.Parent <> nil then
  begin
    // Feld: als eigene, festgeheftete Zeile.
    Add(ANode.Expression, True);
    Exit;
  end;
  ANode.Pinned := not ANode.Pinned;
  if ANode.Pinned then
  begin
    FStore.Pin(ANode.Expression);
  end
  else
  begin
    FStore.Unpin(ANode.Expression);
  end;
  RefreshFrame;
end;

procedure TAtlasIdeDebugEvaluate.Expand(const AKey: string);
var
  mNode: TAtlasEvalNode;
  mSession: TLspSession;
  mSource: string;
begin
  mNode := FList.Find(AKey);
  if (mNode = nil) or mNode.ChildrenLoaded then
  begin
    Exit;
  end;
  mNode.Expanded := True;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  // Ohne Server, ohne Quelltext am Halt bzw. ohne lesbare Datei: Teile des Ergebnis-Strings.
  if (mSession = nil) or (FPlace.FileName = '') or (mNode.Expression = '') or
    not TAtlasIdeFiles.SourceText(FPlace.FileName, mSource) then
  begin
    AcceptFields(FProgress.Request, AKey, nil);
    Exit;
  end;
  // Im Hauptthread abgleichen: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FPlace.FileName, mSource);
  FWorkers.Start(mSession, FPlace.FileName, FPlace.Line, mNode.Expression + '.', FSideEffects,
    FieldsArrived(FProgress.Request, AKey));
end;

procedure TAtlasIdeDebugEvaluate.AcceptFields(ARequest: Integer; const AKey: string; const AFields: TArray<string>);
begin
  // Antwort eines früheren Halts bzw. für eine entfernte Zeile: verwerfen.
  if ARequest <> FProgress.Request then
  begin
    Exit;
  end;
  if not TAtlasEvalRows.AcceptFields(FList, FList.Find(AKey), AFields) then
  begin
    Exit;
  end;
  RefreshFrame;
  if StillStopped and (FProgress.Phase = TAtlasStopPhase.Idle) and (Length(FList.Pending) > 0) then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugEvaluate.Modify(ANode: TAtlasEvalNode);
var
  mKey, mExpression, mNewValue, mOutcome: string;
  mNode: TAtlasEvalNode;
begin
  if (ANode.Expression = '') or (ANode.State <> TAtlasEvalState.Value) or not StillStopped then
  begin
    Exit;
  end;
  mKey := ANode.Key;
  mExpression := ANode.Expression;
  mNewValue := ANode.Value;
  // Der Dialog ist modal: Danach kann der Knoten weg sein.
  if not InputQuery(TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId.DebugEvaluateModifyTitle),
    TAtlasEvaluateStrings.Fmt(TAtlasEvaluateTextId.DebugEvaluateModifyPrompt, [mExpression]), mNewValue) or
    not StillStopped then
  begin
    Exit;
  end;
  if not FThread.Modify(mExpression, FPlace.FileName, FPlace.Line + 1, mNewValue, mOutcome) then
  begin
    MessageDlg(TAtlasEvaluateStrings.Fmt(TAtlasEvaluateTextId.DebugEvaluateModifyFailed, [mExpression, mOutcome]),
      mtWarning, [mbOK], 0);
  end;
  // Neu auswerten; geändert gegenüber dem letzten Halt ist der Wert dann auch markiert.
  mNode := FList.Find(mKey);
  if mNode <> nil then
  begin
    TAtlasEvalRows.MarkPending(mNode);
  end;
  if Frame <> nil then
  begin
    Frame.InvalidateLines;
  end;
  RefreshFrame;
  if FProgress.Phase = TAtlasStopPhase.Idle then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugEvaluate.SyncPinned;
var
  mProject: string;
begin
  if not FStore.SwitchProject(mProject) then
  begin
    Exit;
  end;
  // Festgeheftete Zeilen des vorigen Projekts weg, die des neuen in ihrer Reihenfolge (älteste zuerst) dazu.
  TAtlasEvalRows.ReplacePinned(FList, FStore.PinnedItems(mProject), StillStopped);
  RefreshFrame;
  if StillStopped then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugEvaluate.SetHooked(AValue: Boolean);
begin
  if not AValue then
  begin
    FreeAndNil(FHook);
    Exit;
  end;
  if FHook <> nil then
  begin
    Exit;
  end;
  FHook := TAtlasIdeEvaluateHook.Install(
    function: Boolean
    begin
      Result := Intercepts;
    end,
    procedure
    begin
      ShowWindow;
    end);
end;

class procedure TAtlasIdeDebugEvaluate.Start(const ASession: TAtlasEvaluateSessionFunc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugEvaluate.Create(ASession);
    FInstance.Listen;
  end;
  TAtlasIdeDebugSession.Start;
  TAtlasIdeDebugEvaluateWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugEvaluateFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugEvaluateWindow.Prepare;
  TAtlasIdeDebugDialogCompletion.OwnField :=
    function(AControl: TWinControl): Boolean
    var
      mCurrent: TAtlasDebugEvaluateFrame;
    begin
      mCurrent := Frame;
      Result := (mCurrent <> nil) and (AControl = mCurrent.Parts.Input);
    end;
  ApplySettings;
  // Eingeschaltet, während der Prozess steht: gleich für diesen Halt.
  if StillStopped then
  begin
    FInstance.SessionStopped;
  end;
end;

class procedure TAtlasIdeDebugEvaluate.Release;
var
  mInstance: TAtlasIdeDebugEvaluate;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  FInstance := nil;
  TAtlasIdeDebugDialogCompletion.OwnField := nil;
  // Der Frame zeigt die Liste der Instanz: erst lösen, dann Fenster und Instanz freigeben.
  if Frame <> nil then
  begin
    Frame.SetList(nil);
  end;
  TAtlasIdeDebugEvaluateWindow.Release;
  mInstance.Free;
end;

class function TAtlasIdeDebugEvaluate.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugEvaluate.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugEvaluateWindow;
end;

class procedure TAtlasIdeDebugEvaluate.ApplySettings;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.SetHooked(Enabled and TAtlasIdeSettings.Current.DebugEvaluateReplaceCtrlF7);
  if not Enabled then
  begin
    TAtlasIdeDebugEvaluateWindow.Hide;
  end;
end;

class procedure TAtlasIdeDebugEvaluate.ThemeChanged;
begin
  TAtlasIdeDebugEvaluateWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugEvaluate.ShowWindow;
var
  mShown: TAtlasDebugEvaluateFrame;
  mExpression: string;
begin
  if (FInstance = nil) or not Enabled then
  begin
    Exit;
  end;
  // Vor dem Zeigen lesen: Danach hat das Fenster den Fokus, nicht mehr der Editor.
  mExpression := CursorExpression;
  mShown := TAtlasIdeDebugEvaluateWindow.Show;
  if mShown = nil then
  begin
    Exit;
  end;
  WireFrame(mShown);
  FInstance.SyncPinned;
  mShown.FocusInput(mExpression);
end;

class procedure TAtlasIdeDebugEvaluate.ShowWindow(const AExpression: string);
var
  mShown: TAtlasDebugEvaluateFrame;
begin
  if (FInstance = nil) or not Enabled or (Trim(AExpression) = '') then
  begin
    Exit;
  end;
  mShown := TAtlasIdeDebugEvaluateWindow.Show;
  if mShown = nil then
  begin
    Exit;
  end;
  WireFrame(mShown);
  FInstance.SyncPinned;
  FInstance.Add(AExpression, False);
end;

class procedure TAtlasIdeDebugEvaluate.OpenIdeDialog;
var
  mHook: TAtlasIdeEvaluateHook;
begin
  // Nicht angehängt (Strg+F7 bleibt bei der IDE): die Aktion direkt.
  mHook := nil;
  if FInstance <> nil then
  begin
    mHook := FInstance.FHook;
  end;
  TAtlasIdeEvaluateHook.OpenIdeDialog(mHook);
end;

procedure TAtlasIdeDebugEvaluate.SetSideEffects(AValue: Boolean);
var
  mReload: TArray<string>;
  mKey: string;
begin
  if FSideEffects = AValue then
  begin
    Exit;
  end;
  FSideEffects := AValue;
  if not StillStopped then
  begin
    Exit;
  end;
  mReload := TAtlasEvalRows.IndexFieldKeys(FList);
  // Mit oder ohne Funktionsaufrufe kann ein anderer Wert herauskommen: neu auswerten, Felder neu holen.
  SessionStopped;
  for mKey in mReload do
  begin
    Expand(mKey);
  end;
end;

end.
