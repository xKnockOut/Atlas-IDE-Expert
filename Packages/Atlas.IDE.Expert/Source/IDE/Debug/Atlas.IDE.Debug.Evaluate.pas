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
//   - Verlauf: die letzten HistoryLimit Ausdrücke je Projekt in
//     %LOCALAPPDATA%\Atlas\debug-evaluate-history.json; Pfeil nach unten im
//     leeren Eingabefeld zeigt sie. Die Vervollständigung (#538) gilt auch im
//     Eingabefeld (OwnField).
//   - Strg+F7 (debug.evaluateWindow.replaceCtrlF7): Atlas hängt sich in die
//     Aktion „Auswerten/Ändern“ der IDE (EvaluateActionNames, sonst die Aktion
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
  System.Generics.Collections,
  System.Actions,
  Vcl.ExtCtrls,
  Vcl.ActnList,
  Vcl.Controls,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.DialogCompletion,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Hover.DebugValue,
  Atlas.UI.Debug.EvaluateFrame;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasEvaluateSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugEvaluate = class
  public const
    SliceMs = 30;
    TickMs = 10;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    DeferredTimeoutMs = 2000;
    RequestTimeoutMs = 3000;
    /// <summary>Versuche, bis der Aufrufstapel da ist (je TickMs * 5).</summary>
    LocationRetries = 20;
    HistoryLimit = 50;
    PinnedLimit = 100;
    HistoryFileName = 'debug-evaluate-history.json';
    PinnedFileName = 'debug-evaluate-pinned.json';
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    /// <summary>Hängt an der IDE-Aktion „Auswerten/Ändern“ (wie TTraceHook in Atlas.IDE.Debug.OwnCode).</summary>
    TEvaluateHook = class(TComponent)
    private
      FAction: TContainedAction;
      FOriginal: TNotifyEvent;
      FBypass: Boolean;
      procedure Execute(Sender: TObject);
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    public
      constructor Create(AAction: TContainedAction); reintroduce;
      destructor Destroy; override;
      /// <summary>Die Aktion der IDE wie ohne Atlas ausführen.</summary>
      procedure RunOriginal;
    end;
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Location, Evaluate);
    {$SCOPEDENUMS OFF}
  private class var
    FInstance: TAtlasIdeDebugEvaluate;
  private
    FSession: TAtlasEvaluateSessionFunc;
    FList: TAtlasEvalList;
    FEvaluator: TAtlasIdeDebugValues;
    FLinesEvaluator: TAtlasIdeDebugValues;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FHook: TEvaluateHook;
    FWorkers: TList<TThread>;
    FRequest: Integer;
    FPhase: TPhase;
    FStop: Integer;
    FRetries: Integer;
    FFileName: string;
    FLine: Integer;
    FDeferredKey: string;
    FWaitAt: Cardinal;
    FInternal: Boolean;
    FLinesKey: string;
    FLinesInternal: Boolean;
    FSideEffects: Boolean;
    FHistory: TAtlasExpressionHistory;
    FPinned: TAtlasExpressionHistory;
    FStoreLoaded: Boolean;
    FHistoryKept: Boolean;
    FPinnedKept: Boolean;
    FProject: string;
    constructor Create(const ASession: TAtlasEvaluateSessionFunc);
    procedure Tick(Sender: TObject);
    procedure Stopped;
    procedure Resumed;
    procedure Ended;
    procedure CancelWork;
    procedure EndInternal;
    function StillStopped: Boolean;
    /// <summary>Datei und Zeile des Ausführungspunkts; False: später noch einmal (FPhase bleibt Location).</summary>
    function ReadLocation: Boolean;
    procedure StartEvaluate;
    procedure EvaluateSlice;
    procedure DeferredDone(const AValue: TAtlasDebugValue);
    procedure PutValue(ANode: TAtlasEvalNode; const AValue: TAtlasDebugValue);
    procedure Refresh;
    procedure Add(const AExpression: string; APinned: Boolean);
    procedure Delete(ANode: TAtlasEvalNode);
    procedure TogglePin(ANode: TAtlasEvalNode);
    procedure Expand(const AKey: string);
    procedure AcceptFields(ARequest: Integer; const AKey: string; const AFields: TArray<string>);
    procedure Modify(ANode: TAtlasEvalNode);
    procedure FetchLines(ANode: TAtlasEvalNode);
    procedure LinesDone(const AValue: TAtlasDebugValue);
    procedure SetSideEffects(AValue: Boolean);
    procedure LoadStores;
    procedure SaveStore(AStore: TAtlasExpressionHistory; const AFileName, AWhat: string; AKept: Boolean);
    procedure SyncPinned;
    procedure ReapWorkers(AWait: Boolean);
    procedure InstallHook;
    procedure RemoveHook;
    class function Frame: TAtlasDebugEvaluateFrame; static;
    class procedure WireFrame(AFrame: TAtlasDebugEvaluateFrame); static;
    class function CurrentProject: string; static;
    class function StoreFile(const AName: string): string; static;
    class function FindEvaluateAction: TContainedAction; static;
    /// <summary>Einzeilige Markierung, sonst der Ausdruck unter dem Cursor des obersten Editors.</summary>
    class function CursorExpression: string; static;
    /// <summary>Strg+F7 an Atlas statt an die IDE?</summary>
    class function Intercepts: Boolean; static;
    class function ErrorText(const AValue: TAtlasDebugValue): string; static;
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
  Winapi.Windows,
  System.IOUtils,
  System.JSON,
  Vcl.Menus,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Unavailable,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.DialogCompletion,
  Atlas.IDE.Debug.EvaluateWindow,
  Atlas.UI.Strings;

const
  // Name der IDE-Aktion „Auswerten/Ändern“ je Delphi-Version; ungeprüft, siehe Handtest AW15.
  EvaluateActionNames: array[0..2] of string = ('RunEvaluateModifyCommand', 'RunEvaluateCommand',
    'DebugEvaluateCommand');

{ TAtlasIdeDebugEvaluate.TListener }

procedure TAtlasIdeDebugEvaluate.TListener.DebugStarted;
begin
  if FInstance <> nil then
    FInstance.SyncPinned;
end;

procedure TAtlasIdeDebugEvaluate.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
    FInstance.Stopped;
end;

procedure TAtlasIdeDebugEvaluate.TListener.DebugResumed;
begin
  if FInstance <> nil then
    FInstance.Resumed;
end;

procedure TAtlasIdeDebugEvaluate.TListener.DebugEnded;
begin
  if FInstance <> nil then
    FInstance.Ended;
end;

{ TAtlasIdeDebugEvaluate.TEvaluateHook }

constructor TAtlasIdeDebugEvaluate.TEvaluateHook.Create(AAction: TContainedAction);
begin
  inherited Create(nil);
  FAction := AAction;
  FOriginal := AAction.OnExecute;
  FAction.OnExecute := Execute;
  FAction.FreeNotification(Self);
end;

destructor TAtlasIdeDebugEvaluate.TEvaluateHook.Destroy;
begin
  if FAction <> nil then
  begin
    FAction.RemoveFreeNotification(Self);
    FAction.OnExecute := FOriginal;
  end;
  inherited Destroy;
end;

procedure TAtlasIdeDebugEvaluate.TEvaluateHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
    FAction := nil;
end;

procedure TAtlasIdeDebugEvaluate.TEvaluateHook.Execute(Sender: TObject);
begin
  if FBypass or (FAction = nil) then
    Exit;
  if TAtlasIdeDebugEvaluate.Intercepts then
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugEvaluate.ShowWindow);
    Exit;
  end;
  RunOriginal;
end;

procedure TAtlasIdeDebugEvaluate.TEvaluateHook.RunOriginal;
begin
  if FAction = nil then
    Exit;
  if Assigned(FOriginal) then
  begin
    FOriginal(FAction);
    Exit;
  end;
  // Ohne eigenes OnExecute erledigt die IDE die Aktion über ihre Liste: kurz abhängen und ausführen.
  FBypass := True;
  FAction.OnExecute := nil;
  try
    FAction.Execute;
  finally
    if FAction <> nil then
      FAction.OnExecute := Execute;
    FBypass := False;
  end;
end;

{ TAtlasIdeDebugEvaluate }

constructor TAtlasIdeDebugEvaluate.Create(const ASession: TAtlasEvaluateSessionFunc);
begin
  inherited Create;
  FSession := ASession;
  FLine := -1;
  FList := TAtlasEvalList.Create;
  FEvaluator := TAtlasIdeDebugValues.Create;
  FLinesEvaluator := TAtlasIdeDebugValues.Create;
  FWorkers := TList<TThread>.Create;
  FHistory := TAtlasExpressionHistory.Create(HistoryLimit);
  FPinned := TAtlasExpressionHistory.Create(PinnedLimit);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeDebugEvaluate.Destroy;
begin
  FreeAndNil(FTimer);
  RemoveHook;
  CancelWork;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FreeAndNil(FLinesEvaluator);
  FreeAndNil(FEvaluator);
  FreeAndNil(FPinned);
  FreeAndNil(FHistory);
  FreeAndNil(FList);
  inherited Destroy;
end;

class procedure TAtlasIdeDebugEvaluate.Start(const ASession: TAtlasEvaluateSessionFunc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugEvaluate.Create(ASession);
    FInstance.FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FInstance.FListener);
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
      Current: TAtlasDebugEvaluateFrame;
    begin
      Current := Frame;
      Result := (Current <> nil) and (AControl = Current.Input);
    end;
  ApplySettings;
  // Eingeschaltet, während der Prozess steht: gleich für diesen Halt.
  if TAtlasIdeDebugSession.StoppedThread <> nil then
    FInstance.Stopped;
end;

class procedure TAtlasIdeDebugEvaluate.Release;
var
  Instance: TAtlasIdeDebugEvaluate;
begin
  if FInstance = nil then
    Exit;
  Instance := FInstance;
  FInstance := nil;
  TAtlasIdeDebugDialogCompletion.OwnField := nil;
  if Instance.FListener <> nil then
    TAtlasIdeDebugSession.RemoveListener(Instance.FListener);
  Instance.FListener := nil;
  // Der Frame zeigt die Liste der Instanz: erst lösen, dann Fenster und Instanz freigeben.
  if Frame <> nil then
    Frame.SetList(nil);
  TAtlasIdeDebugEvaluateWindow.Release;
  Instance.Free;
end;

class function TAtlasIdeDebugEvaluate.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugEvaluate.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.DebugEvaluateWindow;
end;

class function TAtlasIdeDebugEvaluate.Intercepts: Boolean;
begin
  // Umschalttaste gedrückt (Strg+Umschalt+F7 oder Umschalt+Klick im Menü): Dialog der IDE.
  Result := (FInstance <> nil) and Enabled and TAtlasIdeSettings.Current.DebugEvaluateReplaceCtrlF7 and
    (GetKeyState(VK_SHIFT) >= 0);
end;

class procedure TAtlasIdeDebugEvaluate.ApplySettings;
begin
  if FInstance = nil then
    Exit;
  if not Enabled then
  begin
    FInstance.RemoveHook;
    TAtlasIdeDebugEvaluateWindow.Hide;
    Exit;
  end;
  if TAtlasIdeSettings.Current.DebugEvaluateReplaceCtrlF7 then
    FInstance.InstallHook
  else
    FInstance.RemoveHook;
end;

class procedure TAtlasIdeDebugEvaluate.ThemeChanged;
begin
  TAtlasIdeDebugEvaluateWindow.ApplyTheme;
end;

class function TAtlasIdeDebugEvaluate.Frame: TAtlasDebugEvaluateFrame;
begin
  Result := TAtlasIdeDebugEvaluateWindow.ExistingFrame;
end;

class procedure TAtlasIdeDebugEvaluate.ShowWindow;
var
  Shown: TAtlasDebugEvaluateFrame;
  Expression: string;
begin
  if (FInstance = nil) or not Enabled then
    Exit;
  // Vor dem Zeigen lesen: Danach hat das Fenster den Fokus, nicht mehr der Editor.
  Expression := CursorExpression;
  Shown := TAtlasIdeDebugEvaluateWindow.Show;
  if Shown = nil then
    Exit;
  WireFrame(Shown);
  FInstance.SyncPinned;
  Shown.FocusInput(Expression);
end;

class procedure TAtlasIdeDebugEvaluate.ShowWindow(const AExpression: string);
var
  Shown: TAtlasDebugEvaluateFrame;
begin
  if (FInstance = nil) or not Enabled or (Trim(AExpression) = '') then
    Exit;
  Shown := TAtlasIdeDebugEvaluateWindow.Show;
  if Shown = nil then
    Exit;
  WireFrame(Shown);
  FInstance.SyncPinned;
  FInstance.Add(AExpression, False);
end;

class procedure TAtlasIdeDebugEvaluate.OpenIdeDialog;
var
  Action: TContainedAction;
begin
  if (FInstance <> nil) and (FInstance.FHook <> nil) then
  begin
    FInstance.FHook.RunOriginal;
    Exit;
  end;
  // Nicht angehängt (Strg+F7 bleibt bei der IDE): die Aktion direkt.
  Action := FindEvaluateAction;
  if Action <> nil then
    Action.Execute;
end;

class procedure TAtlasIdeDebugEvaluate.WireFrame(AFrame: TAtlasDebugEvaluateFrame);
begin
  if FInstance = nil then
    Exit;
  AFrame.OnAdd :=
    procedure(AExpression: string)
    begin
      if FInstance <> nil then
        FInstance.Add(AExpression, False);
    end;
  AFrame.OnPinExpression :=
    procedure(AExpression: string)
    begin
      if FInstance <> nil then
        FInstance.Add(AExpression, True);
    end;
  AFrame.OnPin :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if FInstance <> nil then
        FInstance.TogglePin(ANode);
    end;
  AFrame.OnDelete :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if FInstance <> nil then
        FInstance.Delete(ANode);
    end;
  AFrame.OnExpand :=
    procedure(ANode: TAtlasEvalNode)
    var
      Key: string;
    begin
      // Nicht in der Benachrichtigung des Baums umbauen: später im Hauptthread.
      Key := ANode.Key;
      TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
        procedure
        begin
          if FInstance <> nil then
            FInstance.Expand(Key);
        end);
    end;
  AFrame.OnModify :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if FInstance <> nil then
        FInstance.Modify(ANode);
    end;
  AFrame.OnLines :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if FInstance <> nil then
        FInstance.FetchLines(ANode);
    end;
  AFrame.OnHistory :=
    function: TArray<string>
    begin
      Result := nil;
      if FInstance <> nil then
      begin
        FInstance.LoadStores;
        Result := FInstance.FHistory.Items(CurrentProject);
      end;
    end;
  AFrame.OnSideEffects :=
    procedure(AValue: Boolean)
    begin
      if FInstance <> nil then
        FInstance.SetSideEffects(AValue);
    end;
  AFrame.OnIdeDialog :=
    procedure
    begin
      OpenIdeDialog;
    end;
  AFrame.SetSideEffects(FInstance.FSideEffects);
  AFrame.SetList(FInstance.FList);
end;

class function TAtlasIdeDebugEvaluate.CurrentProject: string;
var
  Project: IOTAProject;
begin
  // Beim Debuggen das gestartete Projekt, sonst das aktive.
  Result := TAtlasIdeDebugSession.LaunchProject;
  if Result <> '' then
    Exit;
  Project := GetActiveProject;
  if Project <> nil then
    Result := Project.FileName;
end;

class function TAtlasIdeDebugEvaluate.StoreFile(const AName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), AName);
end;

class function TAtlasIdeDebugEvaluate.FindEvaluateAction: TContainedAction;
var
  Services: INTAServices;
  Index: Integer;
  Action: TContainedAction;
  Name: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Name in EvaluateActionNames do
    for Index := 0 to Services.ActionList.ActionCount - 1 do
    begin
      Action := Services.ActionList.Actions[Index];
      if SameText(Action.Name, Name) then
        Exit(Action);
    end;
  // Ersatz: die Aktion mit Strg+F7.
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    Action := Services.ActionList.Actions[Index];
    if (Action is TCustomAction) and (TCustomAction(Action).ShortCut = ShortCut(VK_F7, [ssCtrl])) then
      Exit(Action);
  end;
end;

procedure TAtlasIdeDebugEvaluate.InstallHook;
var
  Action: TContainedAction;
begin
  if FHook <> nil then
    Exit;
  Action := FindEvaluateAction;
  if Action = nil then
  begin
    TAtlasGuard.Log('Auswerten: Aktion „Auswerten/Ändern“ der IDE nicht gefunden; Strg+F7 bleibt unverändert');
    Exit;
  end;
  TAtlasGuard.Log('Auswerten: Strg+F7 über die IDE-Aktion ' + Action.Name);
  FHook := TEvaluateHook.Create(Action);
end;

procedure TAtlasIdeDebugEvaluate.RemoveHook;
begin
  FreeAndNil(FHook);
end;

class function TAtlasIdeDebugEvaluate.CursorExpression: string;
var
  View: IOTAEditView;
  Block: IOTAEditBlock;
  Cursor: TOTAEditPos;
  Line: string;
begin
  Result := '';
  View := TAtlasEditorBuffer.ActiveView;
  if View = nil then
    Exit;
  Block := View.Block;
  if (Block <> nil) and Block.IsValid and (Block.Size > 0) and (Block.StartingRow = Block.EndingRow) then
  begin
    Result := Trim(Block.Text);
    if Result <> '' then
      Exit;
  end;
  Cursor := View.CursorPos;
  Line := TAtlasEditorBuffer.LineText(View, Cursor.Line);
  Result := TAtlasEvalText.ExpressionAt(Line, TLspSession.ColumnToIndex(Line, Cursor.Col,
    TAtlasEditorBuffer.TabWidth(View.Buffer)));
end;

class function TAtlasIdeDebugEvaluate.ErrorText(const AValue: TAtlasDebugValue): string;
var
  Caption: string;
begin
  Result := AValue.Text;
  // Bekannter Text für „kein Zugriff“ (#840): kennzeichnen; die Ursache erklärt der Hover.
  Caption := TAtlasIdeDebugUnavailable.InlineCaption;
  if (Caption <> '') and TAtlasDebugUnavailable.IsUnavailable(AValue.Text, TAtlasIdeDebugUnavailable.Patterns) then
    Result := Caption + ' ' + Result;
end;

procedure TAtlasIdeDebugEvaluate.LoadStores;
begin
  if FStoreLoaded then
    Exit;
  FStoreLoaded := True;
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert ohne Pfad.
  FHistoryKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile(HistoryFileName),
    'Verlauf des Fensters „Auswerten“',
    function(const AText: string): Boolean
    begin
      Result := FHistory.LoadFromText(AText);
    end));
  FPinnedKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile(PinnedFileName),
    'Festgeheftete Ausdrücke',
    function(const AText: string): Boolean
    begin
      Result := FPinned.LoadFromText(AText);
    end));
end;

procedure TAtlasIdeDebugEvaluate.SaveStore(AStore: TAtlasExpressionHistory; const AFileName, AWhat: string;
  AKept: Boolean);
begin
  if AKept then
    Exit;
  try
    TAtlasDataFile.Write(StoreFile(AFileName), AStore.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(AWhat, E);
  end;
end;

procedure TAtlasIdeDebugEvaluate.SyncPinned;
var
  Project: string;
  Pinned: TArray<string>;
  Index: Integer;
  Node: TAtlasEvalNode;
begin
  LoadStores;
  Project := CurrentProject;
  if SameText(Project, FProject) and (FProject <> '') then
    Exit;
  FProject := Project;
  // Festgeheftete Zeilen des vorigen Projekts weg, die des neuen in ihrer Reihenfolge (älteste zuerst) dazu.
  for Index := FList.Count - 1 downto 0 do
    if FList.Roots[Index].Pinned then
      FList.Delete(Index);
  Pinned := FPinned.Items(Project);
  for Index := High(Pinned) downto 0 do
  begin
    Node := FList.Add(Pinned[Index]);
    if Node = nil then
      Continue;
    Node.Pinned := True;
    if not StillStopped then
      Node.State := TAtlasEvalState.Unavailable;
  end;
  Refresh;
  if StillStopped then
    StartEvaluate;
end;

procedure TAtlasIdeDebugEvaluate.Refresh;
var
  Current: TAtlasDebugEvaluateFrame;
begin
  Current := Frame;
  if Current <> nil then
    Current.Refresh;
end;

procedure TAtlasIdeDebugEvaluate.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
  if FLinesInternal then
  begin
    FLinesInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

procedure TAtlasIdeDebugEvaluate.CancelWork;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  FEvaluator.Cancel;
  FLinesEvaluator.Cancel;
  EndInternal;
  FDeferredKey := '';
  FLinesKey := '';
  // Antworten noch laufender Feldanfragen verwerfen.
  Inc(FRequest);
  FPhase := TPhase.Idle;
  ReapWorkers(False);
end;

function TAtlasIdeDebugEvaluate.StillStopped: Boolean;
begin
  Result := TAtlasIdeDebugSession.StoppedThread <> nil;
end;

procedure TAtlasIdeDebugEvaluate.Stopped;
begin
  CancelWork;
  if not Enabled then
    Exit;
  FList.BeginStop;
  if Frame <> nil then
    Frame.InvalidateLines;
  FStop := TAtlasIdeDebugSession.StopCount;
  FRetries := 0;
  FPhase := TPhase.Location;
  Refresh;
  if ReadLocation then
    StartEvaluate;
end;

procedure TAtlasIdeDebugEvaluate.Resumed;
begin
  // Die Werte bleiben grau stehen bis zum nächsten Halt; nur laufende Auswertungen enden.
  CancelWork;
end;

procedure TAtlasIdeDebugEvaluate.Ended;
begin
  CancelWork;
  FList.Unavailable;
  FFileName := '';
  FLine := -1;
  Refresh;
end;

function TAtlasIdeDebugEvaluate.ReadLocation: Boolean;
var
  Frames: TAtlasDebugFrames;
begin
  Result := True;
  FFileName := '';
  FLine := -1;
  case TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        // LLDB: Stapel kommt später; nach LocationRetries ohne Ort weiter.
        Inc(FRetries);
        if FRetries <= LocationRetries then
        begin
          FTimer.Interval := TickMs * 5;
          FTimer.Enabled := True;
          Exit(False);
        end;
      end;
    TAtlasDebugStackRead.Ready:
      if (Length(Frames) > 0) and Frames[0].HasSource then
      begin
        TAtlasIdeDebugSources.MarkFrames(Frames);
        FFileName := Frames[0].FileName;
        FLine := Frames[0].Line - 1;
      end;
  end;
end;

procedure TAtlasIdeDebugEvaluate.StartEvaluate;
begin
  if not StillStopped then
    Exit;
  FPhase := TPhase.Evaluate;
  FTimer.Interval := TickMs;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDebugEvaluate.Tick(Sender: TObject);
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
          if not StillStopped or (TAtlasIdeDebugSession.StopCount <> FStop) then
            FPhase := TPhase.Idle
          else if ReadLocation then
            StartEvaluate;
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

procedure TAtlasIdeDebugEvaluate.PutValue(ANode: TAtlasEvalNode; const AValue: TAtlasDebugValue);
begin
  case AValue.State of
    TAtlasDebugValueState.Value:
      FList.SetResult(ANode, True, AValue.Text);
    TAtlasDebugValueState.Failed:
      FList.SetResult(ANode, False, ErrorText(AValue));
  else
    ANode.State := TAtlasEvalState.Unavailable;
  end;
end;

procedure TAtlasIdeDebugEvaluate.EvaluateSlice;
var
  StartedAt: Cardinal;
  Pending: TArray<TAtlasEvalNode>;
  Node: TAtlasEvalNode;
  Value: TAtlasDebugValue;
  Changed: Boolean;
begin
  if not StillStopped then
  begin
    CancelWork;
    Exit;
  end;
  // Verzögerter Wert (LLDB): höchstens DeferredTimeoutMs warten, dann ohne ihn weiter.
  if FDeferredKey <> '' then
  begin
    if GetTickCount - FWaitAt < DeferredTimeoutMs then
      Exit;
    FEvaluator.Cancel;
    if FInternal then
    begin
      FInternal := False;
      TAtlasIdeDebugSession.EndInternal;
    end;
    Node := FList.Find(FDeferredKey);
    FDeferredKey := '';
    if Node <> nil then
      FList.SetResult(Node, False, TAtlasStrings.Text(TAtlasTextId.DebugEvaluateTimeout));
    Refresh;
  end;
  Changed := False;
  StartedAt := GetTickCount;
  Pending := FList.Pending;
  for Node in Pending do
  begin
    if GetTickCount - StartedAt >= SliceMs then
      Break;
    // Eigene Auswertung: Zustandswechsel dabei sind kein Fortsetzen (TAtlasIdeDebugSession).
    Value := Default(TAtlasDebugValue);
    TAtlasIdeDebugSession.BeginInternal;
    FInternal := True;
    try
      Value := FEvaluator.Evaluate(Node.Expression, FFileName, FLine + 1, FSideEffects, DeferredDone);
    finally
      if (Value.State <> TAtlasDebugValueState.Pending) and FInternal then
      begin
        FInternal := False;
        TAtlasIdeDebugSession.EndInternal;
      end;
    end;
    if Value.State = TAtlasDebugValueState.Pending then
    begin
      FDeferredKey := Node.Key;
      FWaitAt := GetTickCount;
      Break;
    end;
    if Value.State = TAtlasDebugValueState.None then
    begin
      // Kein angehaltener Prozess mehr.
      CancelWork;
      Refresh;
      Exit;
    end;
    PutValue(Node, Value);
    Changed := True;
  end;
  if (FDeferredKey = '') and (Length(FList.Pending) = 0) then
  begin
    FTimer.Enabled := False;
    FPhase := TPhase.Idle;
  end;
  if Changed then
    Refresh;
end;

procedure TAtlasIdeDebugEvaluate.DeferredDone(const AValue: TAtlasDebugValue);
var
  Node: TAtlasEvalNode;
begin
  if FDeferredKey = '' then
    Exit;
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
  Node := FList.Find(FDeferredKey);
  FDeferredKey := '';
  if Node <> nil then
    PutValue(Node, AValue);
  Refresh;
end;

procedure TAtlasIdeDebugEvaluate.Add(const AExpression: string; APinned: Boolean);
var
  Node: TAtlasEvalNode;
  Project: string;
begin
  LoadStores;
  Node := FList.Add(AExpression);
  if Node = nil then
    Exit;
  Project := CurrentProject;
  if FHistory.Add(Project, Node.Expression) then
    SaveStore(FHistory, HistoryFileName, 'Verlauf des Fensters „Auswerten“', FHistoryKept);
  if APinned then
  begin
    Node.Pinned := True;
    if FPinned.Add(Project, Node.Expression) then
      SaveStore(FPinned, PinnedFileName, 'Festgeheftete Ausdrücke', FPinnedKept);
  end;
  if not StillStopped then
    Node.State := TAtlasEvalState.Unavailable;
  Refresh;
  if Frame <> nil then
    Frame.Select(Node.Key);
  if StillStopped and (FPhase = TPhase.Idle) then
    StartEvaluate;
end;

procedure TAtlasIdeDebugEvaluate.Delete(ANode: TAtlasEvalNode);
var
  Index: Integer;
begin
  Index := FList.IndexOf(ANode);
  if Index < 0 then
    Exit;
  if ANode.Pinned and FPinned.Remove(CurrentProject, ANode.Expression) then
    SaveStore(FPinned, PinnedFileName, 'Festgeheftete Ausdrücke', FPinnedKept);
  // Läuft gerade die Auswertung dieser Zeile oder eines ihrer Felder: verwerfen, sonst kommt sie ins Leere.
  if (FDeferredKey <> '') and ((FDeferredKey = ANode.Key) or FDeferredKey.StartsWith(ANode.Key + #1)) then
  begin
    FEvaluator.Cancel;
    if FInternal then
    begin
      FInternal := False;
      TAtlasIdeDebugSession.EndInternal;
    end;
    FDeferredKey := '';
  end;
  FList.Delete(Index);
  Refresh;
end;

procedure TAtlasIdeDebugEvaluate.TogglePin(ANode: TAtlasEvalNode);
var
  Project: string;
  Changed: Boolean;
begin
  if ANode.Parent <> nil then
  begin
    // Feld: als eigene, festgeheftete Zeile.
    Add(ANode.Expression, True);
    Exit;
  end;
  LoadStores;
  Project := CurrentProject;
  ANode.Pinned := not ANode.Pinned;
  if ANode.Pinned then
    Changed := FPinned.Add(Project, ANode.Expression)
  else
    Changed := FPinned.Remove(Project, ANode.Expression);
  if Changed then
    SaveStore(FPinned, PinnedFileName, 'Festgeheftete Ausdrücke', FPinnedKept);
  Refresh;
end;

procedure TAtlasIdeDebugEvaluate.Expand(const AKey: string);
var
  Node: TAtlasEvalNode;
  Session: TLspSession;
  Buffer: IOTAEditBuffer;
  FileName, Source, Expression: string;
  Line, Request: Integer;
  WithProperties: Boolean;
  Worker: TThread;
begin
  Node := FList.Find(AKey);
  if (Node = nil) or Node.ChildrenLoaded then
    Exit;
  Node.Expanded := True;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if (Session = nil) or (FFileName = '') or (Node.Expression = '') then
  begin
    // Ohne Server bzw. ohne Quelltext am Halt: Teile des Ergebnis-Strings.
    AcceptFields(FRequest, AKey, nil);
    Exit;
  end;
  FileName := FFileName;
  Line := FLine;
  // Im Hauptthread abgleichen: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Buffer := TAtlasIdeFiles.BufferOf(FileName);
  if Buffer <> nil then
    Source := TAtlasEditorBuffer.Text(Buffer)
  else
    try
      Source := TAtlasTextFile.LoadText(FileName);
    except
      on Exception do
      begin
        AcceptFields(FRequest, AKey, nil);
        Exit;
      end;
    end;
  Session.Sync(FileName, Source);
  Expression := Node.Expression + '.';
  WithProperties := FSideEffects;
  ReapWorkers(False);
  Request := FRequest;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Response: TJSONValue;
      Fields: TArray<string>;
    begin
      Fields := nil;
      try
        Response := Session.ExpressionCompletion(FileName, Line, Expression, Length(Expression), RequestTimeoutMs);
        try
          Fields := TAtlasEvalText.FieldsOf(Response, WithProperties);
        finally
          Response.Free;
        end;
      except
        // Server langsam oder weg: Teile des Ergebnis-Strings.
        Fields := nil;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.Debugger,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.AcceptFields(Request, AKey, Fields);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

procedure TAtlasIdeDebugEvaluate.AcceptFields(ARequest: Integer; const AKey: string; const AFields: TArray<string>);
var
  Node: TAtlasEvalNode;
begin
  // Antwort eines früheren Halts bzw. für eine entfernte Zeile: verwerfen.
  if ARequest <> FRequest then
    Exit;
  Node := FList.Find(AKey);
  // Felder des Index ersetzen Teile, die der Wert inzwischen geliefert hat (SetResult bei aufgeklapptem Knoten).
  if (Node = nil) or (Node.ChildrenLoaded and not Node.FromParts) then
    Exit;
  if Length(AFields) > 0 then
    FList.SetFields(Node, AFields)
  else if not Node.ChildrenLoaded and not FList.SetParts(Node) then
  begin
    // Weder Felder noch Teile: aufgeklappt mit „(keine Felder)“.
    FList.SetFields(Node, nil);
  end;
  Refresh;
  if StillStopped and (FPhase = TPhase.Idle) and (Length(FList.Pending) > 0) then
    StartEvaluate;
end;

/// <summary>ANode und seine Felder neu auswerten; Teile entstehen aus dem neuen Wert.</summary>
procedure MarkPending(ANode: TAtlasEvalNode);
var
  Index: Integer;
begin
  if ANode.FromParts then
    ANode.ClearChildren;
  if ANode.Expression <> '' then
    ANode.State := TAtlasEvalState.Pending;
  for Index := 0 to ANode.ChildCount - 1 do
    MarkPending(ANode.Children[Index]);
end;

procedure TAtlasIdeDebugEvaluate.Modify(ANode: TAtlasEvalNode);
var
  Key, Expression, NewValue, Outcome: string;
  Node: TAtlasEvalNode;
begin
  if (ANode.Expression = '') or (ANode.State <> TAtlasEvalState.Value) or not StillStopped then
    Exit;
  Key := ANode.Key;
  Expression := ANode.Expression;
  NewValue := ANode.Value;
  if not InputQuery(TAtlasStrings.Text(TAtlasTextId.DebugEvaluateModifyTitle),
    TAtlasStrings.Fmt(TAtlasTextId.DebugEvaluateModifyPrompt, [Expression]), NewValue) then
    Exit;
  // Der Dialog ist modal: Danach kann der Knoten weg sein.
  if not StillStopped then
    Exit;
  TAtlasIdeDebugSession.BeginInternal;
  try
    if not TAtlasIdeDebugValues.Modify(Expression, FFileName, FLine + 1, NewValue, Outcome) then
      MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.DebugEvaluateModifyFailed, [Expression, Outcome]), mtWarning,
        [mbOK], 0);
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
  // Neu auswerten; geändert gegenüber dem letzten Halt ist der Wert dann auch markiert.
  Node := FList.Find(Key);
  if Node <> nil then
    MarkPending(Node);
  if Frame <> nil then
    Frame.InvalidateLines;
  Refresh;
  if FPhase = TPhase.Idle then
    StartEvaluate;
end;

procedure TAtlasIdeDebugEvaluate.FetchLines(ANode: TAtlasEvalNode);
var
  Value: TAtlasDebugValue;
begin
  FLinesEvaluator.Cancel;
  if FLinesInternal then
  begin
    FLinesInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
  FLinesKey := ANode.Key;
  if not StillStopped or (ANode.Expression = '') then
  begin
    LinesDone(Default(TAtlasDebugValue));
    Exit;
  end;
  TAtlasIdeDebugSession.BeginInternal;
  FLinesInternal := True;
  Value := Default(TAtlasDebugValue);
  try
    Value := FLinesEvaluator.Evaluate(TAtlasEvalText.FieldExpression(ANode.Expression, 'Text'), FFileName,
      FLine + 1, FSideEffects, LinesDone);
  finally
    if (Value.State <> TAtlasDebugValueState.Pending) and FLinesInternal then
    begin
      FLinesInternal := False;
      TAtlasIdeDebugSession.EndInternal;
    end;
  end;
  if Value.State <> TAtlasDebugValueState.Pending then
    LinesDone(Value);
end;

procedure TAtlasIdeDebugEvaluate.LinesDone(const AValue: TAtlasDebugValue);
var
  Key: string;
begin
  if FLinesInternal then
  begin
    FLinesInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
  Key := FLinesKey;
  FLinesKey := '';
  if (Key <> '') and (Frame <> nil) then
    Frame.SetLines(Key, AValue.State = TAtlasDebugValueState.Value, AValue.Text);
end;

procedure TAtlasIdeDebugEvaluate.SetSideEffects(AValue: Boolean);
var
  Reload: TList<string>;
  Key: string;

  procedure Collect(ANode: TAtlasEvalNode);
  var
    Index: Integer;
  begin
    // Felder aus dem Index: mit Nebenwirkungen kommen Eigenschaften dazu bzw. fallen weg.
    if ANode.Expanded and ANode.ChildrenLoaded and not ANode.FromParts then
    begin
      ANode.ClearChildren;
      Reload.Add(ANode.Key);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Collect(ANode.Children[Index]);
  end;

var
  Index: Integer;
begin
  if FSideEffects = AValue then
    Exit;
  FSideEffects := AValue;
  if not StillStopped then
    Exit;
  Reload := TList<string>.Create;
  try
    for Index := 0 to FList.Count - 1 do
      Collect(FList.Roots[Index]);
    // Mit oder ohne Funktionsaufrufe kann ein anderer Wert herauskommen: neu auswerten, Felder neu holen.
    Stopped;
    for Key in Reload do
      Expand(Key);
  finally
    Reload.Free;
  end;
end;

procedure TAtlasIdeDebugEvaluate.ReapWorkers(AWait: Boolean);
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

end.
