unit Atlas.IDE.Debug.EditValue;

// Werte ändern beim Debuggen (#868) in der IDE:
//   - Im Debug-Hover: „Ändern …“, bei True/False zusätzlich „Auf False setzen“
//     und nach einer Änderung „Rückgängig (vorher 125)“ (Actions/Act, von der
//     Komposition zusammen mit „Anheften“ #526 an TAtlasEditorHover gehängt).
//   - Im Editor: F2 bzw. „Atlas: Wert ändern“ für den Bezeichner an der
//     Schreibmarke, nur im angehaltenen Zustand; sonst geht F2 an die IDE.
//     „Atlas: Geänderten Wert zurücksetzen“ setzt den alten Wert.
//   - Ablauf: Typ und Art der Eingabe vom Server (atlas.server.valueEdit; ohne
//     Server freie Eingabe), Dialog TAtlasEditValueDialog, bei einem Setter
//     Rückfrage; dann IOTAThread.Modify über TAtlasIdeDebugValues. Eine
//     Eigenschaft mit Setter ändert Atlas über den Aufruf des Setters
//     („K.SetBetrag(150)“, ausgewertet mit Nebenwirkungen).
//   - Geänderte Werte stehen bis zum nächsten Schritt am Zeilenende
//     („Betrag = 150 (vorher 125)“, Warnfarbe); Werte im Editor und
//     angeheftete Werte werten danach im selben Halt neu aus (AChanged).
//     Fortsetzen und Ende der Sitzung vergessen die Änderungen.
// Ohne debug.editValues ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Types,
  ToolsAPI.Editor,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.EditValue,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.InlineValuePainter;

type
  TAtlasIdeDebugEditValue = class
  public const
    /// <summary>Ids der Aktionen im Debug-Hover.</summary>
    cEditAction = 868;
    cToggleAction = 8681;
    cUndoAction = 8682;
    cRequestTimeoutMs = 3000;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    /// <summary>Stelle des Werts: Datei, Zeile (1-basiert), Ausdruck und angezeigter Wert. Direct: neuer Wert ohne
    /// Dialog (Umschalten, Rückgängig); Undoing: Rückgängig, die Änderung wird danach vergessen.</summary>
    TPlace = record
      FileName: string;
      Line: Integer;
      Expression: string;
      Value: string;
      Direct: string;
      Undoing: Boolean;
    end;
  private class var
    FInstance: TAtlasIdeDebugEditValue;
  private
    FChanges: TAtlasEditChanges;
    FRun: TAtlasHostCommandRunner;
    FMessage: TProc<string>;
    FChanged: TProc;
    FListener: IAtlasIdeDebugListener;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FStyle: TAtlasInlineValuePainter;
    /// <summary>Nummer der letzten Anfrage an den Server; ältere Antworten zählen nicht.</summary>
    FRequest: Integer;
    constructor Create(const ARun: TAtlasHostCommandRunner; const AMessage: TProc<string>; const AChanged: TProc);
    procedure Ask(const APlace: TPlace);
    procedure Answered(ARequest: Integer; const APlace: TPlace; const AAnswer: string);
    procedure Edit(const APlace: TPlace; const AInfo: TAtlasEditInfo);
    /// <summary>ANew setzen (bei einem Setter über dessen Aufruf), Änderung merken; False mit Meldung.</summary>
    function Apply(const APlace: TPlace; const AInfo: TAtlasEditInfo; const ANew: string): Boolean;
    procedure Forget;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure Report(const AText: string);
    /// <summary>Stelle an der Schreibmarke des aktiven Editors; False ohne Bezeichner.</summary>
    class function PlaceAtCursor(out APlace: TPlace): Boolean; static;
  public
    destructor Destroy; override;
    /// <summary>Teil starten. ARun schickt Befehle an den laufenden Server, AMessage schreibt in die
    /// Meldungsansicht, AChanged läuft nach jeder Änderung (Werte im Editor neu auswerten).</summary>
    class procedure Start(const ARun: TAtlasHostCommandRunner; const AMessage: TProc<string>;
      const AChanged: TProc); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.editValues an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Aktionen unter dem Wert im Debug-Hover.</summary>
    class function Actions(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>; static;
    /// <summary>Aktion AAction für AValue an AFileName, ALine (1-basiert); False, wenn sie nicht hierher gehört.
    /// </summary>
    class function Act(const AValue: TAtlasDebugValue; const AFileName: string; ALine, AAction: Integer): Boolean;
      static;
    /// <summary>Befehl Atlas.DebugEditValue: Wert an der Schreibmarke ändern.</summary>
    class procedure EditAtCursor; static;
    /// <summary>Taste F2: False, wenn das Programm nicht angehalten ist oder kein Bezeichner an der Schreibmarke
    /// steht (die Taste geht dann an die IDE).</summary>
    class function TryEditAtCursor: Boolean; static;
    /// <summary>Befehl Atlas.DebugUndoValue: geänderten Wert an der Schreibmarke zurücksetzen.</summary>
    class procedure UndoAtCursor; static;
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Debug.InlineValues,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Hover.DebugValue,
  Atlas.IDE.Debug.LineEnd,
  Atlas.UI.Debug.EditValueDialog,
  Atlas.UI.Debug.Strings;

{ TAtlasIdeDebugEditValue.TListener }

procedure TAtlasIdeDebugEditValue.TListener.DebugResumed;
begin
  if FInstance <> nil then
  begin
    FInstance.Forget;
  end;
end;

procedure TAtlasIdeDebugEditValue.TListener.DebugEnded;
begin
  if FInstance <> nil then
  begin
    FInstance.Forget;
  end;
end;

{ TAtlasIdeDebugEditValue.TEvents }

function TAtlasIdeDebugEditValue.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeDebugEditValue.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeDebugEditValue }

constructor TAtlasIdeDebugEditValue.Create(const ARun: TAtlasHostCommandRunner; const AMessage: TProc<string>;
  const AChanged: TProc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FRun := ARun;
  FMessage := AMessage;
  FChanged := AChanged;
  FIndex := -1;
  FChanges := TAtlasEditChanges.Create;
  FStyle := TAtlasInlineValuePainter.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeDebugEditValue.Destroy;
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
  FreeAndNil(FStyle);
  FreeAndNil(FChanges);
  FRun := nil;
  FMessage := nil;
  FChanged := nil;
  inherited Destroy;
end;

class procedure TAtlasIdeDebugEditValue.Start(const ARun: TAtlasHostCommandRunner; const AMessage: TProc<string>;
  const AChanged: TProc);
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TAtlasIdeDebugEditValue.Create(ARun, AMessage, AChanged);
  FInstance.FListener := TListener.Create;
  TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugEditValue.Release;
var
  mInstance: TAtlasIdeDebugEditValue;
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

class function TAtlasIdeDebugEditValue.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugEditValue.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugEditValues;
end;

class function TAtlasIdeDebugEditValue.Actions(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>;
var
  mNew: string;
  mChange: TAtlasEditChange;
  mView: IOTAEditView;
begin
  Result := nil;
  if (FInstance = nil) or (AValue.Expression = '') or not Enabled then
  begin
    Exit;
  end;
  Result := [TAtlasDebugValueFix.Create(cEditAction, TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueAction))];
  // Booleans per Klick umschalten.
  if TAtlasEditValue.Toggled(AValue.Text, mNew) then
  begin
    Result := Result + [TAtlasDebugValueFix.Create(cToggleAction,
      TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueToggle, [mNew]))];
  end;
  // Der Hover gehört zum aktiven Editor.
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and
    FInstance.FChanges.Find(mView.Buffer.FileName, AValue.Expression, mChange) then
  begin
    Result := Result + [TAtlasDebugValueFix.Create(cUndoAction,
      TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueUndo, [mChange.OldValue]))];
  end;
end;

/// <summary>APlace für „Rückgängig“: alter Wert als Direct; False ohne gemerkte Änderung.</summary>
function UndoPlace(var APlace: TAtlasIdeDebugEditValue.TPlace): Boolean;
var
  mChange: TAtlasEditChange;
begin
  Result := (TAtlasIdeDebugEditValue.FInstance <> nil) and
    TAtlasIdeDebugEditValue.FInstance.FChanges.Find(APlace.FileName, APlace.Expression, mChange);
  if Result then
  begin
    APlace.Line := mChange.Line;
    APlace.Value := mChange.NewValue;
    APlace.Direct := mChange.OldValue;
    APlace.Undoing := True;
  end;
end;

class function TAtlasIdeDebugEditValue.Act(const AValue: TAtlasDebugValue; const AFileName: string;
  ALine, AAction: Integer): Boolean;
var
  mPlace: TPlace;
  mNew: string;
begin
  Result := (AAction = cEditAction) or (AAction = cToggleAction) or (AAction = cUndoAction);
  if not Result or (FInstance = nil) or (TAtlasIdeDebugValues.StoppedThread = nil) then
  begin
    Exit;
  end;
  mPlace := Default(TPlace);
  mPlace.FileName := AFileName;
  mPlace.Line := ALine;
  mPlace.Expression := AValue.Expression;
  mPlace.Value := AValue.Text;
  if (AAction = cToggleAction) and TAtlasEditValue.Toggled(AValue.Text, mNew) then
  begin
    mPlace.Direct := mNew;
  end
  else if (AAction = cUndoAction) and not UndoPlace(mPlace) then
  begin
    Exit;
  end;
  // Auch Umschalten und Rückgängig fragen den Server: Eine Eigenschaft mit Setter ändert Atlas nur nach Rückfrage.
  FInstance.Ask(mPlace);
end;

class function TAtlasIdeDebugEditValue.PlaceAtCursor(out APlace: TPlace): Boolean;
var
  mView: IOTAEditView;
  mLine: string;
begin
  APlace := Default(TPlace);
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil);
  if not Result then
  begin
    Exit;
  end;
  APlace.FileName := mView.Buffer.FileName;
  APlace.Line := mView.CursorPos.Line;
  mLine := TAtlasEditorBuffer.LineText(mView, APlace.Line);
  // CursorPos.Col ist 1-basiert und steht hinter dem Zeichen; Tabs zählen hier wie ein Zeichen.
  APlace.Expression := TAtlasDebugExpression.AtCharacter(mLine, mView.CursorPos.Col - 1);
  if APlace.Expression = '' then
  begin
    APlace.Expression := TAtlasDebugExpression.AtCharacter(mLine, mView.CursorPos.Col - 2);
  end;
  Result := APlace.Expression <> '';
end;

class procedure TAtlasIdeDebugEditValue.EditAtCursor;
begin
  if not TryEditAtCursor and (FInstance <> nil) then
  begin
    FInstance.Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueNoValue));
  end;
end;

class function TAtlasIdeDebugEditValue.TryEditAtCursor: Boolean;
var
  mPlace: TPlace;
  mValue: TAtlasDebugValue;
begin
  Result := (FInstance <> nil) and Enabled and (TAtlasIdeDebugValues.StoppedThread <> nil) and
    PlaceAtCursor(mPlace);
  if not Result then
  begin
    Exit;
  end;
  // Jetziger Wert für den Dialog; verzögert (LLDB) bleibt er leer.
  TAtlasIdeDebugSession.BeginInternal;
  try
    mValue := TAtlasIdeDebugValues.EvaluateNow(mPlace.Expression, mPlace.FileName, mPlace.Line);
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
  Result := mValue.State = TAtlasDebugValueState.Value;
  if Result then
  begin
    mPlace.Value := mValue.Text;
    FInstance.Ask(mPlace);
  end;
end;

class procedure TAtlasIdeDebugEditValue.UndoAtCursor;
var
  mPlace: TPlace;
begin
  if (FInstance = nil) or (TAtlasIdeDebugValues.StoppedThread = nil) then
  begin
    Exit;
  end;
  if PlaceAtCursor(mPlace) and UndoPlace(mPlace) then
  begin
    FInstance.Ask(mPlace);
  end
  else
  begin
    FInstance.Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueNoChange));
  end;
end;

/// <summary>Antwort des Servers zur Anfrage ARequest an die laufende Instanz.</summary>
function AnswerTo(ARequest: Integer; const APlace: TAtlasIdeDebugEditValue.TPlace): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    begin
      if TAtlasIdeDebugEditValue.FInstance <> nil then
      begin
        TAtlasIdeDebugEditValue.FInstance.Answered(ARequest, APlace, AAnswer);
      end;
    end;
end;

procedure TAtlasIdeDebugEditValue.Ask(const APlace: TPlace);
begin
  Inc(FRequest);
  // Ohne laufenden Server freie Eingabe.
  if not Assigned(FRun) or not FRun(TAtlasEditValue.cCommand,
    TAtlasEditValue.Arguments(TLspSession.PathToUri(APlace.FileName), APlace.Line - 1, APlace.Expression),
    cRequestTimeoutMs, AnswerTo(FRequest, APlace)) then
  begin
    Edit(APlace, TAtlasEditInfo.Plain(APlace.Expression));
  end;
end;

procedure TAtlasIdeDebugEditValue.Answered(ARequest: Integer; const APlace: TPlace; const AAnswer: string);
begin
  // Eine neuere Anfrage oder ein Schritt dazwischen: nichts mehr anzeigen.
  if (ARequest <> FRequest) or (TAtlasIdeDebugValues.StoppedThread = nil) then
  begin
    Exit;
  end;
  Edit(APlace, TAtlasEditValue.ReadAnswerText(AAnswer, APlace.Expression));
end;

procedure TAtlasIdeDebugEditValue.Edit(const APlace: TPlace; const AInfo: TAtlasEditInfo);
var
  mNew: string;
  mCheck: TAtlasEditCheck;
begin
  mNew := APlace.Direct;
  if (mNew = '') and not TAtlasEditValueDialog.Execute(AInfo, APlace.Value, mNew) then
  begin
    Exit;
  end;
  // Umschalten und Rückgängig: wie der Dialog umsetzen (Typpräfix, Hochkommas), sonst unverändert.
  mCheck := TAtlasEditValue.Check(AInfo, mNew);
  if (APlace.Direct <> '') and mCheck.Ok then
  begin
    mNew := mCheck.Value;
  end;
  if TAtlasIdeDebugValues.StoppedThread = nil then
  begin
    Exit;
  end;
  if (AInfo.Setter <> '') and (MessageDlg(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueConfirmSetter,
    [AInfo.Setter]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    Exit;
  end;
  Apply(APlace, AInfo, mNew);
end;

/// <summary>ANew über den Setter in AInfo setzen (Aufruf mit Nebenwirkungen); AResult: Fehlertext.</summary>
function CallSetter(const AInfo: TAtlasEditInfo; const AFileName: string; ALine: Integer; const ANew: string;
  out AResult: string): Boolean;
var
  mValues: TAtlasIdeDebugValues;
  mValue: TAtlasDebugValue;
begin
  mValues := TAtlasIdeDebugValues.Create;
  try
    // Eine verzögerte Antwort (LLDB) zeigt sich beim nächsten Auswerten.
    mValue := mValues.Evaluate(TAtlasEditValue.SetterCall(AInfo, ANew), AFileName, ALine, True, nil);
  finally
    mValues.Free;
  end;
  AResult := mValue.Text;
  Result := mValue.State <> TAtlasDebugValueState.Failed;
end;

/// <summary>Gemerkte Änderung: ANew bzw. der Wert, den der Debugger nach dem Ändern meldet (AOutcome).</summary>
function ChangeOf(const APlace: TAtlasIdeDebugEditValue.TPlace; const ANew, AOutcome: string): TAtlasEditChange;
begin
  Result := Default(TAtlasEditChange);
  Result.FileName := APlace.FileName;
  Result.Line := APlace.Line;
  Result.Expression := APlace.Expression;
  Result.OldValue := APlace.Value;
  Result.NewValue := ANew;
  if AOutcome <> '' then
  begin
    Result.NewValue := AOutcome;
  end;
end;

function TAtlasIdeDebugEditValue.Apply(const APlace: TPlace; const AInfo: TAtlasEditInfo; const ANew: string): Boolean;
var
  mOutcome: string;
begin
  TAtlasIdeDebugSession.BeginInternal;
  try
    if AInfo.Setter <> '' then
    begin
      Result := CallSetter(AInfo, APlace.FileName, APlace.Line, ANew, mOutcome);
    end
    else
    begin
      Result := TAtlasIdeDebugValues.Modify(APlace.Expression, APlace.FileName, APlace.Line, ANew, mOutcome);
    end;
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
  if not Result then
  begin
    MessageDlg(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueFailed, [APlace.Expression, mOutcome]), mtWarning,
      [mbOK], 0);
    Exit;
  end;
  if APlace.Undoing then
  begin
    FChanges.Remove(APlace.FileName, APlace.Expression);
  end
  else
  begin
    FChanges.Add(ChangeOf(APlace, ANew, mOutcome));
  end;
  if Assigned(FChanged) then
  begin
    FChanged();
  end;
  TAtlasDebugLineEnd.Invalidate;
end;

procedure TAtlasIdeDebugEditValue.Forget;
begin
  Inc(FRequest);
  if FChanges.Count > 0 then
  begin
    FChanges.Clear;
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

procedure TAtlasIdeDebugEditValue.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

/// <summary>„Betrag = 150 (vorher 125)“ für das Zeilenende, in der Warnfarbe.</summary>
function MarkOf(const AChange: TAtlasEditChange): TAtlasInlineValueItem;
begin
  Result := Default(TAtlasInlineValueItem);
  Result.Name := AChange.Expression;
  Result.Text := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueMark, [AChange.NewValue, AChange.OldValue]);
  Result.State := TAtlasInlineValueState.Ready;
  Result.Changed := True;
end;

procedure TAtlasIdeDebugEditValue.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mItems: TAtlasInlineValueItems;
  mChange: TAtlasEditChange;
  mTailKey: string;
  mX: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (Context.LineState = nil) or
    (FChanges.Count = 0) then
  begin
    Exit;
  end;
  try
    mItems := nil;
    for mChange in FChanges.Items do
    begin
      if (mChange.Line = Context.LogicalLineNum) and SameFileName(mChange.FileName, Context.FileName) then
      begin
        mItems := mItems + [MarkOf(mChange)];
      end;
    end;
    if Length(mItems) = 0 then
    begin
      Exit;
    end;
    // Hinter dem letzten Zeichen der Zeile bzw. hinter den Werten im Editor.
    mX := TAtlasDebugLineEnd.Start(Self, Context, Rect, Context.LineState.Text, FStyle, mTailKey);
    TAtlasDebugLineEnd.Finish(Self, mTailKey, FStyle.Draw(Context.Canvas.Handle, Rect, mX, mItems));
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

end.
