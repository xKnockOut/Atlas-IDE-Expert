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
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Evaluate,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Hover.DebugValue,
  Atlas.IDE.Debug.EvaluateHook,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.UI.Debug.EvaluateFrame;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasEvaluateSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugEvaluate = class
  public const
    cSliceMs = 30;
    cTickMs = 10;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    cDeferredTimeoutMs = 2000;
    cRequestTimeoutMs = 3000;
    /// <summary>Versuche, bis der Aufrufstapel da ist (je TickMs * 5).</summary>
    cLocationRetries = 20;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Location, Evaluate);
    /// <summary>Ergebnis einer Auswertung im Zeitschnitt: weiter, auf den verzögerten Wert warten, kein
    /// angehaltener Prozess mehr.</summary>
    TSliceStep = (Next, Wait, Stopped);
    {$SCOPEDENUMS OFF}
    /// <summary>Ausführungspunkt: Datei und Zeile (0-basiert, -1 ohne).</summary>
    TPlace = record
      FileName: string;
      Line: Integer;
    end;
    /// <summary>Stand der Auswertung eines Halts.</summary>
    TProgress = record
      /// <summary>Nummer der Feldanfragen; ältere Antworten verwirft Atlas.</summary>
      Request: Integer;
      Phase: TPhase;
      /// <summary>Halt (TAtlasIdeDebugSession.StopCount), für den Atlas den Ort liest.</summary>
      Stop: Integer;
      Retries: Integer;
    end;
    /// <summary>Eigene Auswertungen über einen Auswerter: Zustandswechsel dabei sind kein Fortsetzen
    /// (TAtlasIdeDebugSession.BeginInternal), Key ist die Zeile mit verzögertem Wert.</summary>
    TRun = class
    protected
      FValues: TAtlasIdeDebugValues;
      FKey: string;
      FInternal: Boolean;
      procedure EndInternal;
      /// <summary>AExpression am Ort APlace auswerten; ein verzögerter Wert kommt über ADone.</summary>
      function Run(const AExpression: string; const APlace: TPlace; ASideEffects: Boolean;
        const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
      /// <summary>Key der offenen Auswertung (leer ohne) und eigene Auswertung beenden.</summary>
      function TakeKey: string;
    public
      constructor Create;
      destructor Destroy; override;
      procedure Cancel;
    end;
    /// <summary>Werte der Zeilen und aufgeklappten Felder in Zeitscheiben.</summary>
    TEvaluation = class(TRun)
    private
      FList: TAtlasEvalList;
      FWaitAt: Cardinal;
      procedure Done(const AValue: TAtlasDebugValue);
      function EvaluateOne(ANode: TAtlasEvalNode; const APlace: TPlace; ASideEffects: Boolean): TSliceStep;
    public
      constructor Create(AList: TAtlasEvalList);
      /// <summary>Wartet Atlas auf einen verzögerten Wert?</summary>
      function Waiting: Boolean;
      /// <summary>Wartet Atlas länger als DeferredTimeoutMs?</summary>
      function Overdue: Boolean;
      /// <summary>Den verzögerten Wert aufgeben: Zeile mit Zeitüberschreitung.</summary>
      procedure Expire;
      /// <summary>Läuft die Auswertung von ANode oder eines seiner Felder: verwerfen.</summary>
      procedure Drop(ANode: TAtlasEvalNode);
      /// <summary>Offene Zeilen höchstens SliceMs lang; AChanged: mindestens ein Wert neu.</summary>
      function Slice(const APlace: TPlace; ASideEffects: Boolean; out AChanged: Boolean): TSliceStep;
    end;
    /// <summary>Ansicht Zeilen: „Ausdruck.Text“ einer Zeile.</summary>
    TLines = class(TRun)
    private
      procedure Done(const AValue: TAtlasDebugValue);
    public
      procedure Fetch(ANode: TAtlasEvalNode; const APlace: TPlace; ASideEffects: Boolean);
    end;
    /// <summary>Feldanfragen an den Server im Hintergrund.</summary>
    TWorkers = class(TList<TThread>)
    public
      /// <summary>Beendete Anfragen freigeben; mit AWait auch laufende (abwarten).</summary>
      procedure Reap(AWait: Boolean);
      /// <summary>Felder von AExpression („Ausdruck.“) über ASession holen; die Antwort geht an AcceptFields.
      /// </summary>
      procedure StartFields(ASession: TLspSession; const APlace: TPlace; const AExpression: string;
        AWithProperties: Boolean; ARequest: Integer; const AKey: string);
    end;
  private class var
    FInstance: TAtlasIdeDebugEvaluate;
  private
    FSession: TAtlasEvaluateSessionFunc;
    FList: TAtlasEvalList;
    FEvaluation: TEvaluation;
    FLines: TLines;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FHook: TAtlasIdeEvaluateHook;
    FWorkers: TWorkers;
    FProgress: TProgress;
    FPlace: TPlace;
    FSideEffects: Boolean;
    FStore: TAtlasIdeEvaluateStore;
    constructor Create(const ASession: TAtlasEvaluateSessionFunc);
    procedure Tick(Sender: TObject);
    procedure Stopped;
    procedure Ended;
    procedure CancelWork;
    /// <summary>Datei und Zeile des Ausführungspunkts; False: später noch einmal (Phase bleibt Location).
    /// </summary>
    function ReadLocation: Boolean;
    procedure StartEvaluate;
    procedure EvaluateSlice;
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
  System.JSON,
  Vcl.Controls,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Unavailable,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.DialogCompletion,
  Atlas.IDE.Debug.EvaluateWindow,
  Atlas.UI.Debug.Strings;

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

/// <summary>Fehlertext eines Werts; bekannter Text für „kein Zugriff“ (#840) gekennzeichnet, die Ursache erklärt
/// der Hover.</summary>
function ErrorText(const AValue: TAtlasDebugValue): string;
var
  mCaption: string;
begin
  Result := AValue.Text;
  mCaption := TAtlasIdeDebugUnavailable.InlineCaption;
  if (mCaption <> '') and TAtlasDebugUnavailable.IsUnavailable(AValue.Text, TAtlasIdeDebugUnavailable.Patterns) then
  begin
    Result := mCaption + ' ' + Result;
  end;
end;

/// <summary>AValue an ANode in AList.</summary>
procedure PutValue(AList: TAtlasEvalList; ANode: TAtlasEvalNode; const AValue: TAtlasDebugValue);
begin
  case AValue.State of
    TAtlasDebugValueState.Value:
      AList.SetResult(ANode, True, AValue.Text);
    TAtlasDebugValueState.Failed:
      AList.SetResult(ANode, False, ErrorText(AValue));
  else
    ANode.State := TAtlasEvalState.Unavailable;
  end;
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

/// <summary>Text von AFileName: Editorpuffer, sonst die Datei; False, wenn sie sich nicht lesen lässt.</summary>
function LoadSource(const AFileName: string; out ASource: string): Boolean;
var
  mBuffer: IOTAEditBuffer;
begin
  Result := True;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    ASource := TAtlasEditorBuffer.Text(mBuffer);
    Exit;
  end;
  try
    ASource := TAtlasTextFile.LoadText(AFileName);
  except
    on Exception do
    begin
      ASource := '';
      Result := False;
    end;
  end;
end;

/// <summary>Felder von AExpression aus dem Atlas-Index; nil, wenn der Server langsam oder weg ist.</summary>
function QueryFields(ASession: TLspSession; const AFileName: string; ALine: Integer; const AExpression: string;
  AWithProperties: Boolean): TArray<string>;
var
  mResponse: TJSONValue;
begin
  Result := nil;
  try
    mResponse := ASession.ExpressionCompletion(AFileName, ALine, AExpression, Length(AExpression),
      TAtlasIdeDebugEvaluate.cRequestTimeoutMs);
    try
      Result := TAtlasEvalText.FieldsOf(mResponse, AWithProperties);
    finally
      mResponse.Free;
    end;
  except
    // Server langsam oder weg: Teile des Ergebnis-Strings.
    Result := nil;
  end;
end;

/// <summary>AFields im Hauptthread an AcceptFields, solange das Fenster angemeldet ist.</summary>
procedure DeliverFields(ARequest: Integer; const AKey: string; const AFields: TArray<string>);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          if TAtlasIdeDebugEvaluate.FInstance <> nil then
          begin
            TAtlasIdeDebugEvaluate.FInstance.AcceptFields(ARequest, AKey, AFields);
          end;
        end);
    end);
end;

/// <summary>ANode und seine Felder neu auswerten; Teile entstehen aus dem neuen Wert.</summary>
procedure MarkPending(ANode: TAtlasEvalNode);
var
  mIndex: Integer;
begin
  if ANode.FromParts then
  begin
    ANode.ClearChildren;
  end;
  if ANode.Expression <> '' then
  begin
    ANode.State := TAtlasEvalState.Pending;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    MarkPending(ANode.Children[mIndex]);
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

{ TAtlasIdeDebugEvaluate.TListener }

procedure TAtlasIdeDebugEvaluate.TListener.DebugStarted;
begin
  if FInstance <> nil then
  begin
    FInstance.SyncPinned;
  end;
end;

procedure TAtlasIdeDebugEvaluate.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
  begin
    FInstance.Stopped;
  end;
end;

procedure TAtlasIdeDebugEvaluate.TListener.DebugResumed;
begin
  // Die Werte bleiben grau stehen bis zum nächsten Halt; nur laufende Auswertungen enden.
  if FInstance <> nil then
  begin
    FInstance.CancelWork;
  end;
end;

procedure TAtlasIdeDebugEvaluate.TListener.DebugEnded;
begin
  if FInstance <> nil then
  begin
    FInstance.Ended;
  end;
end;

{ TAtlasIdeDebugEvaluate.TRun }

constructor TAtlasIdeDebugEvaluate.TRun.Create;
begin
  inherited Create;
  FValues := TAtlasIdeDebugValues.Create;
end;

destructor TAtlasIdeDebugEvaluate.TRun.Destroy;
begin
  FreeAndNil(FValues);
  inherited Destroy;
end;

procedure TAtlasIdeDebugEvaluate.TRun.EndInternal;
begin
  if FInternal then
  begin
    FInternal := False;
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

procedure TAtlasIdeDebugEvaluate.TRun.Cancel;
begin
  FValues.Cancel;
  EndInternal;
  FKey := '';
end;

function TAtlasIdeDebugEvaluate.TRun.Run(const AExpression: string; const APlace: TPlace; ASideEffects: Boolean;
  const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  TAtlasIdeDebugSession.BeginInternal;
  FInternal := True;
  try
    Result := FValues.Evaluate(AExpression, APlace.FileName, APlace.Line + 1, ASideEffects, ADone);
  finally
    // Verzögerter Wert: Die eigene Auswertung endet erst mit ihm.
    if Result.State <> TAtlasDebugValueState.Pending then
    begin
      EndInternal;
    end;
  end;
end;

function TAtlasIdeDebugEvaluate.TRun.TakeKey: string;
begin
  EndInternal;
  Result := FKey;
  FKey := '';
end;

{ TAtlasIdeDebugEvaluate.TEvaluation }

constructor TAtlasIdeDebugEvaluate.TEvaluation.Create(AList: TAtlasEvalList);
begin
  inherited Create;
  FList := AList;
end;

function TAtlasIdeDebugEvaluate.TEvaluation.Waiting: Boolean;
begin
  Result := FKey <> '';
end;

function TAtlasIdeDebugEvaluate.TEvaluation.Overdue: Boolean;
begin
  Result := Waiting and (TThread.GetTickCount - FWaitAt >= cDeferredTimeoutMs);
end;

procedure TAtlasIdeDebugEvaluate.TEvaluation.Expire;
var
  mNode: TAtlasEvalNode;
begin
  FValues.Cancel;
  mNode := FList.Find(TakeKey);
  if mNode <> nil then
  begin
    FList.SetResult(mNode, False, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateTimeout));
  end;
end;

procedure TAtlasIdeDebugEvaluate.TEvaluation.Drop(ANode: TAtlasEvalNode);
begin
  if Waiting and ((FKey = ANode.Key) or FKey.StartsWith(ANode.Key + #1)) then
  begin
    Cancel;
  end;
end;

procedure TAtlasIdeDebugEvaluate.TEvaluation.Done(const AValue: TAtlasDebugValue);
var
  mNode: TAtlasEvalNode;
begin
  if not Waiting then
  begin
    Exit;
  end;
  mNode := FList.Find(TakeKey);
  if mNode <> nil then
  begin
    PutValue(FList, mNode, AValue);
  end;
  RefreshFrame;
end;

function TAtlasIdeDebugEvaluate.TEvaluation.EvaluateOne(ANode: TAtlasEvalNode; const APlace: TPlace;
  ASideEffects: Boolean): TSliceStep;
var
  mValue: TAtlasDebugValue;
begin
  // ",r": Records mit Feldnamen, sonst zeigt der Baum nur [0], [1], … (Werte ohne Namen).
  mValue := Run(TAtlasEvalText.WithFieldNames(ANode.Expression), APlace, ASideEffects, Done);
  case mValue.State of
    TAtlasDebugValueState.Pending:
      begin
        FKey := ANode.Key;
        FWaitAt := TThread.GetTickCount;
        Result := TSliceStep.Wait;
      end;
    TAtlasDebugValueState.None:
      Result := TSliceStep.Stopped;
  else
    PutValue(FList, ANode, mValue);
    Result := TSliceStep.Next;
  end;
end;

function TAtlasIdeDebugEvaluate.TEvaluation.Slice(const APlace: TPlace; ASideEffects: Boolean;
  out AChanged: Boolean): TSliceStep;
var
  mStartedAt: Cardinal;
  mNode: TAtlasEvalNode;
begin
  AChanged := False;
  Result := TSliceStep.Next;
  mStartedAt := TThread.GetTickCount;
  for mNode in FList.Pending do
  begin
    if TThread.GetTickCount - mStartedAt >= cSliceMs then
    begin
      Exit;
    end;
    Result := EvaluateOne(mNode, APlace, ASideEffects);
    if Result <> TSliceStep.Next then
    begin
      Exit;
    end;
    AChanged := True;
  end;
end;

{ TAtlasIdeDebugEvaluate.TLines }

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
  mValue := Run(TAtlasEvalText.FieldExpression(ANode.Expression, 'Text'), APlace, ASideEffects, Done);
  if mValue.State <> TAtlasDebugValueState.Pending then
  begin
    Done(mValue);
  end;
end;

procedure TAtlasIdeDebugEvaluate.TLines.Done(const AValue: TAtlasDebugValue);
var
  mKey: string;
begin
  mKey := TakeKey;
  if (mKey <> '') and (Frame <> nil) then
  begin
    Frame.SetLines(mKey, AValue.State = TAtlasDebugValueState.Value, AValue.Text);
  end;
end;

{ TAtlasIdeDebugEvaluate.TWorkers }

procedure TAtlasIdeDebugEvaluate.TWorkers.Reap(AWait: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := Count - 1 downto 0 do
  begin
    if AWait or Items[mIndex].Finished then
    begin
      Items[mIndex].WaitFor;
      Items[mIndex].Free;
      Self.Delete(mIndex);
    end;
  end;
end;

procedure TAtlasIdeDebugEvaluate.TWorkers.StartFields(ASession: TLspSession; const APlace: TPlace;
  const AExpression: string; AWithProperties: Boolean; ARequest: Integer; const AKey: string);
var
  mFileName: string;
  mLine: Integer;
  mWorker: TThread;
begin
  Reap(False);
  mFileName := APlace.FileName;
  mLine := APlace.Line;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      DeliverFields(ARequest, AKey, QueryFields(ASession, mFileName, mLine, AExpression, AWithProperties));
    end);
  mWorker.FreeOnTerminate := False;
  Self.Add(mWorker);
  mWorker.Start;
end;

{ TAtlasIdeDebugEvaluate }

constructor TAtlasIdeDebugEvaluate.Create(const ASession: TAtlasEvaluateSessionFunc);
begin
  inherited Create;
  FSession := ASession;
  FPlace.Line := -1;
  FList := TAtlasEvalList.Create;
  FEvaluation := TEvaluation.Create(FList);
  FLines := TLines.Create;
  FWorkers := TWorkers.Create;
  FStore := TAtlasIdeEvaluateStore.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeDebugEvaluate.Destroy;
begin
  FreeAndNil(FTimer);
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
  FreeAndNil(FEvaluation);
  FreeAndNil(FStore);
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
      mCurrent: TAtlasDebugEvaluateFrame;
    begin
      mCurrent := Frame;
      Result := (mCurrent <> nil) and (AControl = mCurrent.Parts.Input);
    end;
  ApplySettings;
  // Eingeschaltet, während der Prozess steht: gleich für diesen Halt.
  if StillStopped then
  begin
    FInstance.Stopped;
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
  if mInstance.FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(mInstance.FListener);
  end;
  mInstance.FListener := nil;
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

procedure TAtlasIdeDebugEvaluate.SyncPinned;
var
  mProject: string;
  mPinned: TArray<string>;
  mIndex: Integer;
  mNode: TAtlasEvalNode;
begin
  if not FStore.SwitchProject(mProject) then
  begin
    Exit;
  end;
  // Festgeheftete Zeilen des vorigen Projekts weg, die des neuen in ihrer Reihenfolge (älteste zuerst) dazu.
  for mIndex := FList.Count - 1 downto 0 do
  begin
    if FList.Roots[mIndex].Pinned then
    begin
      FList.Delete(mIndex);
    end;
  end;
  mPinned := FStore.PinnedItems(mProject);
  for mIndex := High(mPinned) downto 0 do
  begin
    mNode := FList.Add(mPinned[mIndex]);
    if mNode = nil then
    begin
      Continue;
    end;
    mNode.Pinned := True;
    if not StillStopped then
    begin
      mNode.State := TAtlasEvalState.Unavailable;
    end;
  end;
  RefreshFrame;
  if StillStopped then
  begin
    StartEvaluate;
  end;
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
  FProgress.Phase := TPhase.Idle;
  FWorkers.Reap(False);
end;

procedure TAtlasIdeDebugEvaluate.Stopped;
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
  FProgress.Phase := TPhase.Location;
  RefreshFrame;
  if ReadLocation then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugEvaluate.Ended;
begin
  CancelWork;
  FList.Unavailable;
  FPlace := Default(TPlace);
  FPlace.Line := -1;
  RefreshFrame;
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

procedure TAtlasIdeDebugEvaluate.StartEvaluate;
begin
  if not StillStopped then
  begin
    Exit;
  end;
  FProgress.Phase := TPhase.Evaluate;
  FTimer.Interval := cTickMs;
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
    case FProgress.Phase of
      TPhase.Location:
        begin
          FTimer.Enabled := False;
          if not StillStopped or (TAtlasIdeDebugSession.StopCount <> FProgress.Stop) then
          begin
            FProgress.Phase := TPhase.Idle;
          end
          else if ReadLocation then
          begin
            StartEvaluate;
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
  if FEvaluation.Waiting then
  begin
    FEvaluation.Expire;
    RefreshFrame;
  end;
  if FEvaluation.Slice(FPlace, FSideEffects, mChanged) = TSliceStep.Stopped then
  begin
    // Kein angehaltener Prozess mehr.
    CancelWork;
    RefreshFrame;
    Exit;
  end;
  if not FEvaluation.Waiting and (Length(FList.Pending) = 0) then
  begin
    FTimer.Enabled := False;
    FProgress.Phase := TPhase.Idle;
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
  if StillStopped and (FProgress.Phase = TPhase.Idle) then
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
  FEvaluation.Drop(ANode);
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
    not LoadSource(FPlace.FileName, mSource) then
  begin
    AcceptFields(FProgress.Request, AKey, nil);
    Exit;
  end;
  // Im Hauptthread abgleichen: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FPlace.FileName, mSource);
  FWorkers.StartFields(mSession, FPlace, mNode.Expression + '.', FSideEffects, FProgress.Request, AKey);
end;

procedure TAtlasIdeDebugEvaluate.AcceptFields(ARequest: Integer; const AKey: string; const AFields: TArray<string>);
var
  mNode: TAtlasEvalNode;
begin
  // Antwort eines früheren Halts bzw. für eine entfernte Zeile: verwerfen.
  if ARequest <> FProgress.Request then
  begin
    Exit;
  end;
  mNode := FList.Find(AKey);
  // Felder des Index ersetzen Teile, die der Wert inzwischen geliefert hat (SetResult bei aufgeklapptem Knoten).
  if (mNode = nil) or (mNode.ChildrenLoaded and not mNode.FromParts) then
  begin
    Exit;
  end;
  if Length(AFields) > 0 then
  begin
    FList.SetFields(mNode, AFields);
  end
  else if not mNode.ChildrenLoaded and not FList.SetParts(mNode) then
  begin
    // Weder Felder noch Teile: aufgeklappt mit „(keine Felder)“.
    FList.SetFields(mNode, nil);
  end;
  RefreshFrame;
  if StillStopped and (FProgress.Phase = TPhase.Idle) and (Length(FList.Pending) > 0) then
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
  if not InputQuery(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateModifyTitle),
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEvaluateModifyPrompt, [mExpression]), mNewValue) or
    not StillStopped then
  begin
    Exit;
  end;
  TAtlasIdeDebugSession.BeginInternal;
  try
    if not TAtlasIdeDebugValues.Modify(mExpression, FPlace.FileName, FPlace.Line + 1, mNewValue, mOutcome) then
    begin
      MessageDlg(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEvaluateModifyFailed, [mExpression, mOutcome]),
        mtWarning, [mbOK], 0);
    end;
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
  // Neu auswerten; geändert gegenüber dem letzten Halt ist der Wert dann auch markiert.
  mNode := FList.Find(mKey);
  if mNode <> nil then
  begin
    MarkPending(mNode);
  end;
  if Frame <> nil then
  begin
    Frame.InvalidateLines;
  end;
  RefreshFrame;
  if FProgress.Phase = TPhase.Idle then
  begin
    StartEvaluate;
  end;
end;

/// <summary>Aufgeklappte Felder aus dem Index unter ANode leeren und ihre Schlüssel in AReload sammeln: Mit
/// Nebenwirkungen kommen Eigenschaften dazu bzw. fallen weg.</summary>
procedure CollectIndexFields(ANode: TAtlasEvalNode; AReload: TList<string>);
var
  mIndex: Integer;
begin
  if ANode.Expanded and ANode.ChildrenLoaded and not ANode.FromParts then
  begin
    ANode.ClearChildren;
    AReload.Add(ANode.Key);
    Exit;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    CollectIndexFields(ANode.Children[mIndex], AReload);
  end;
end;

procedure TAtlasIdeDebugEvaluate.SetSideEffects(AValue: Boolean);
var
  mReload: TList<string>;
  mKey: string;
  mIndex: Integer;
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
  mReload := TList<string>.Create;
  try
    for mIndex := 0 to FList.Count - 1 do
    begin
      CollectIndexFields(FList.Roots[mIndex], mReload);
    end;
    // Mit oder ohne Funktionsaufrufe kann ein anderer Wert herauskommen: neu auswerten, Felder neu holen.
    Stopped;
    for mKey in mReload do
    begin
      Expand(mKey);
    end;
  finally
    mReload.Free;
  end;
end;

end.
