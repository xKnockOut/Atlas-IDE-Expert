unit Atlas.UI.Tracker.EndDialog;

// Dialog „ATL-123 beenden“ (#1266), ohne Open Tools API: Zielzustand
// (issues.endStates und „Zustand nicht ändern“, dazu Werte vom Tracker,
// Eingabe von Hand), Kommentar vorgefüllt aus issues.endComment und das
// Häkchen „Zuständigkeit übergeben an“ mit der Benutzerliste vom Tracker.
// - Geschrieben wird nur mit „Senden“: OnSend schreibt im Hintergrund und
//   meldet über SendDone im Hauptthread. Solange gesendet wird, sind Felder
//   und „Abbrechen“ gesperrt und der Dialog schließt nicht (die Zeitgrenze
//   des Schreibens ist TAtlasTrackerWorkflow.cWriteTimeoutMs).
// - Fehler erscheinen im Dialog mit dem Text des Trackers (ErrorText, z. B.
//   „Keine Schreibrechte für ATL-123 (403).“); nichts wird wiederholt, der
//   Benutzer kann ändern und erneut senden oder abbrechen.
// - Strg+Enter sendet; Esc bricht ab.
// - Das Kommentarfeld ist der Kommentar-Editor (#1278): Vorschläge, Textbausteine
//   und Entwurf, sobald APrepare ihn bindet; die Vorlage gilt nicht als Entwurf,
//   ein vorhandener Entwurf wird mit „Übernehmen“ angeboten. Abbrechen behält
//   den Entwurf, erfolgreiches Senden löscht ihn.
// - Unter einer Zustandsmaschine (#2122, SetRules) heißt die Klappliste
//   „Übergang (ab „In Bearbeitung“)“ und bietet nur „Zustand nicht ändern“
//   und die erlaubten Übergänge an, mit bekanntem Ziel dahinter („Zur Prüfung
//   geben → Zur Prüfung“). Vorgewählt ist der erste Übergang in einen
//   Zustand aus issues.endStates (Reihenfolge = Vorliebe); ist der erste
//   Wunsch ab hier nicht erlaubt, sagt es die Hinweiszeile.
// SummaryText bildet die Zeile für die Meldungsansicht („Zustand „Erledigt“,
// Kommentar“), ErrorText auch für „Beginnen“ und die Vorschau.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.CommentEditor,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Ergebnis des Schreibens, im Hauptthread.</summary>
  TAtlasTrackerSendDone = reference to procedure(const AResult: TAtlasTrackerWriteResult);
  /// <summary>AChange im Hintergrund schreiben und ADone im Hauptthread aufrufen (genau einmal).</summary>
  TAtlasTrackerSendEvent = reference to procedure(const AChange: TAtlasTrackerWrite;
    const ADone: TAtlasTrackerSendDone);

  /// <summary>Die Steuerelemente des Dialogs (für Tests und APrepare). Comment ist das Memo des Editors.</summary>
  TAtlasEndDialogParts = record
    StateLabel: TLabel;
    State: TAtlasValueBox;
    Editor: TAtlasCommentEditor;
    Comment: TMemo;
    HandOver: TCheckBox;
    Assignee: TAtlasValueBox;
    Note: TLabel;
    Send: TButton;
    Cancel: TButton;
  end;

  TAtlasTrackerEndDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 520;
    cCommentHeight = 150;
    /// <summary>Leiste des Kommentar-Editors (Vorschau, Textbaustein, Entwurf).</summary>
    cEditorBarHeight = 30;
    /// <summary>Breite der Beschriftungen vor den Klapplisten.</summary>
    cLabelWidth = 176;
  private
    FKey: string;
    FOptions: TAtlasTrackerSyncOptions;
    FParts: TAtlasEndDialogParts;
    FOnSend: TAtlasTrackerSendEvent;
    FSending: Boolean;
    FSent: Boolean;
    FChange: TAtlasTrackerWrite;
    FRules: TAtlasTrackerStateRules;
    FStates: TArray<string>;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
    procedure AddState;
    procedure AddComment(const AComment: string);
    function AddHandOver: TPanel;
    procedure AddButtons(ATop: Integer);
    procedure SendClick(Sender: TObject);
    procedure AssigneeChange(Sender: TObject);
    procedure DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SetBusy(AValue: Boolean);
    procedure EditorCancel(Sender: TObject);
    procedure ShowTransitions;
    function ChosenTransition: Integer;
  public
    /// <summary>AComment: ausgefüllte Vorlage issues.endComment (Zeilen mit #10).</summary>
    constructor CreateDialog(AOwner: TComponent; const AKey: string; const AOptions: TAtlasTrackerSyncOptions;
      const AComment: string);
    /// <summary>Werte des Zustandsfeldes vom Tracker als weitere Vorschläge hinter issues.endStates.</summary>
    procedure SetStates(const AStates: TArray<string>);
    /// <summary>Regeln des Zustandsfeldes vom Tracker (#2122): Unter einer Zustandsmaschine bietet die Klappliste
    /// nur die erlaubten Übergänge an; ohne bleibt sie bei den Zuständen.</summary>
    procedure SetRules(const ARules: TAtlasTrackerStateRules);
    /// <summary>Einträge der Klappliste unter ARules: „Zustand nicht ändern“, dann je Übergang ChoiceText mit
    /// bekanntem Ziel aus AStates.</summary>
    class function TransitionChoices(const ARules: TAtlasTrackerStateRules;
      const AStates: TArray<string>): TArray<string>; static;
    /// <summary>Benutzer vom Tracker für „Zuständigkeit übergeben an“.</summary>
    procedure SetUsers(const AUsers: TArray<string>);
    /// <summary>Änderung nach den Feldern.</summary>
    function Change: TAtlasTrackerWrite;
    /// <summary>Ergebnis von OnSend: geschrieben schließt den Dialog mit mrOk, sonst steht der Grund im Dialog.
    /// </summary>
    procedure SendDone(const AResult: TAtlasTrackerWriteResult);
    /// <summary>Vorschläge der Klappliste Zielzustand: „Zustand nicht ändern“, dann AOptions.EndStates.</summary>
    class function StateChoices(const AOptions: TAtlasTrackerSyncOptions): TArray<string>; static;
    /// <summary>Grund eines Fehlers mit dem Text des Trackers; '' bei Erfolg.</summary>
    class function ErrorText(const AKey: string; const AResult: TAtlasTrackerWriteResult): string; static;
    /// <summary>Was geschrieben wurde, z. B. „Zustand „Erledigt“, an anna übergeben, Kommentar“.</summary>
    class function SummaryText(const AChange: TAtlasTrackerWrite): string; overload; static;
    /// <summary>Wie oben; nach einem Übergang mit dem danach gelesenen Zustand ANewState („Übergang „Beginnen“
    /// → In Bearbeitung“), ANewState '' ohne.</summary>
    class function SummaryText(const AChange: TAtlasTrackerWrite; const ANewState: string): string; overload; static;
    /// <summary>Modal zeigen; True nach erfolgreichem „Senden“ mit der geschriebenen Änderung in AChange.
    /// APrepare (darf nil sein) passt das Fenster vorher an und kann Werte nachladen (SetUsers).</summary>
    class function Execute(const AKey: string; const AOptions: TAtlasTrackerSyncOptions; const AComment: string;
      const AOnSend: TAtlasTrackerSendEvent; const APrepare: TProc<TAtlasTrackerEndDialog>;
      out AChange: TAtlasTrackerWrite): Boolean; static;
    property OnSend: TAtlasTrackerSendEvent read FOnSend write FOnSend;
    /// <summary>Senden war erfolgreich.</summary>
    property Sent: Boolean read FSent;
    property Sending: Boolean read FSending;
    /// <summary>Gesendete Änderung (gilt mit Sent).</summary>
    property SentChange: TAtlasTrackerWrite read FChange;
    property Parts: TAtlasEndDialogParts read FParts;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Transitions,
  Atlas.UI.Tracker.Strings,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

const
  cGap = 8;

{ TAtlasTrackerEndDialog }

constructor TAtlasTrackerEndDialog.CreateDialog(AOwner: TComponent; const AKey: string;
  const AOptions: TAtlasTrackerSyncOptions; const AComment: string);
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FKey := AKey;
  FOptions := AOptions;
  FChange := TAtlasTrackerWrite.Empty;
  Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndCaption, [AKey]);
  KeyPreview := True;
  OnKeyDown := DialogKeyDown;
  OnCloseQuery := DialogCloseQuery;
  AddState;
  AddComment(AComment);
  AddButtons(AddHandOver.BoundsRect.Bottom + 1);
  ActiveControl := FParts.Comment;
end;

/// <summary>Zielzustand; Vorgabe ist der erste angebotene, ohne Liste „Zustand nicht ändern“.</summary>
procedure TAtlasTrackerEndDialog.AddState;
var
  mRow: TPanel;
  mLabel: TLabel;
  mChoices: TArray<string>;
begin
  mRow := AddRow(26);
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mRow;
  mLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndState);
  mLabel.Left := 0;
  mLabel.Top := ScaleValue(4);
  // Lange Beschriftung „Übergang (ab „…“)“ endet mit „…“ vor der Klappliste, voll im Hinweis.
  mLabel.AutoSize := False;
  mLabel.Width := ScaleValue(cLabelWidth);
  mLabel.EllipsisPosition := epEndEllipsis;
  mLabel.ShowHint := True;
  FParts.StateLabel := mLabel;
  FParts.State := TAtlasValueBox.Create(Self);
  FParts.State.Parent := mRow;
  FParts.State.Left := ScaleValue(180);
  FParts.State.Top := 0;
  FParts.State.Width := ScaleValue(240);
  mChoices := StateChoices(FOptions);
  FParts.State.SetValues(mChoices);
  FParts.State.Value := mChoices[Min(1, High(mChoices))];
end;

/// <summary>Kommentar-Editor (#1278) mit seiner Leiste unter dem Feld; die Vorlage ist kein Entwurf.</summary>
procedure TAtlasTrackerEndDialog.AddComment(const AComment: string);
var
  mRow: TPanel;
  mLabel: TLabel;
begin
  mRow := AddRow(20);
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mRow;
  mLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndComment);
  mLabel.Left := 0;
  mLabel.Top := ScaleValue(2);
  FParts.Editor := TAtlasCommentEditor.Create(Self);
  FParts.Editor.Parent := Self;
  FParts.Editor.Align := alTop;
  FParts.Editor.AlignWithMargins := True;
  FParts.Editor.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  FParts.Editor.Top := mRow.Top + mRow.Height + 1;
  FParts.Editor.Height := ScaleValue(cCommentHeight + cEditorBarHeight);
  FParts.Editor.Events := TAtlasCommentEditorEvents.Create(SendClick, EditorCancel);
  FParts.Editor.SetText(AComment);
  FParts.Comment := FParts.Editor.Memo;
end;

/// <summary>„Zuständigkeit übergeben an“ und die Zeile für Hinweise; liefert die Hinweiszeile.</summary>
function TAtlasTrackerEndDialog.AddHandOver: TPanel;
var
  mRow: TPanel;
begin
  mRow := AddRow(26);
  mRow.Top := FParts.Editor.Top + FParts.Editor.Height + 1;
  FParts.HandOver := TCheckBox.Create(Self);
  FParts.HandOver.Parent := mRow;
  FParts.HandOver.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndHandOver);
  FParts.HandOver.Left := 0;
  FParts.HandOver.Top := ScaleValue(3);
  FParts.HandOver.Width := ScaleValue(176);
  FParts.Assignee := TAtlasValueBox.Create(Self);
  FParts.Assignee.Parent := mRow;
  FParts.Assignee.Left := ScaleValue(180);
  FParts.Assignee.Top := 0;
  FParts.Assignee.Width := ScaleValue(240);
  FParts.Assignee.OnChange := AssigneeChange;

  Result := AddRow(20);
  FParts.Note := TLabel.Create(Self);
  FParts.Note.Parent := Result;
  FParts.Note.Align := alClient;
  FParts.Note.WordWrap := True;
  FParts.Note.Caption := '';
end;

procedure TAtlasTrackerEndDialog.AddButtons(ATop: Integer);
var
  mButtons: TFlowPanel;
begin
  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := ATop;
  FParts.Send := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndSend));
  FParts.Send.OnClick := SendClick;
  FParts.Send.Default := True;
  FParts.Cancel := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndCancel));
  FParts.Cancel.ModalResult := mrCancel;
  FParts.Cancel.Cancel := True;
  ClientHeight := mButtons.Top + mButtons.Height + ScaleValue(cGap);
end;

function TAtlasTrackerEndDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap, cGap div 2);
end;

class function TAtlasTrackerEndDialog.StateChoices(const AOptions: TAtlasTrackerSyncOptions): TArray<string>;
begin
  Result := TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState))
    + Copy(AOptions.EndStates);
end;

procedure TAtlasTrackerEndDialog.SetStates(const AStates: TArray<string>);
var
  mChoices: TArray<string>;
  mState, mChoice: string;
  mFound: Boolean;
begin
  FStates := Copy(AStates);
  // Unter einer Zustandsmaschine nur die Übergänge; die Zustände verraten deren Ziele.
  if FRules.StateMachine then
  begin
    ShowTransitions;
    Exit;
  end;
  mChoices := StateChoices(FOptions);
  for mState in AStates do
  begin
    mFound := False;
    for mChoice in mChoices do
    begin
      if SameText(mChoice, mState) then
      begin
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      mChoices := mChoices + [mState];
    end;
  end;
  FParts.State.SetValues(mChoices);
end;

class function TAtlasTrackerEndDialog.TransitionChoices(const ARules: TAtlasTrackerStateRules;
  const AStates: TArray<string>): TArray<string>;
var
  mTransition: TAtlasTrackerTransition;
begin
  Result := TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState));
  for mTransition in ARules.Transitions do
  begin
    Result := Result + [TAtlasTrackerTransitions.ChoiceText(mTransition, AStates)];
  end;
end;

procedure TAtlasTrackerEndDialog.SetRules(const ARules: TAtlasTrackerStateRules);
begin
  if not ARules.StateMachine or (ARules.FieldId = '') then
  begin
    Exit;
  end;
  FRules := ARules;
  ShowTransitions;
end;

/// <summary>Klappliste und Beschriftung nach FRules; Vorwahl nach issues.endStates, Hinweis, wenn der erste Wunsch
/// ab hier nicht erlaubt ist.</summary>
procedure TAtlasTrackerEndDialog.ShowTransitions;
var
  mChoices, mKnown: TArray<string>;
  mPreferred: Integer;
begin
  if FRules.Current <> '' then
  begin
    FParts.StateLabel.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndTransitionFrom,
      [FRules.Current]);
  end
  else
  begin
    FParts.StateLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndTransition);
  end;
  FParts.StateLabel.Hint := FParts.StateLabel.Caption;
  mKnown := FOptions.EndStates + FStates;
  mChoices := TransitionChoices(FRules, mKnown);
  FParts.State.SetValues(mChoices);
  mPreferred := TAtlasTrackerTransitions.Preferred(FRules, FOptions.EndStates);
  FParts.State.Value := mChoices[mPreferred + 1];
  FParts.Note.Caption := '';
  if (Length(FOptions.EndStates) > 0) and (FRules.Current <> '') and
    (TAtlasTrackerTransitions.Into(FRules, TArray<string>.Create(FOptions.EndStates[0])) < 0) then
  begin
    FParts.Note.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerEndNotAllowed,
      [FOptions.EndStates[0], FRules.Current]);
  end;
end;

/// <summary>Gewählter Übergang (Index in FRules.Transitions); -1 = Zustand nicht ändern bzw. von Hand
/// eingetragener Text, zu dem kein Übergang passt.</summary>
function TAtlasTrackerEndDialog.ChosenTransition: Integer;
var
  mChoices: TArray<string>;
  mIndex: Integer;
begin
  mChoices := TransitionChoices(FRules, FOptions.EndStates + FStates);
  for mIndex := 1 to High(mChoices) do
  begin
    if SameText(Trim(FParts.State.Value), mChoices[mIndex]) then
    begin
      Exit(mIndex - 1);
    end;
  end;
  // Von Hand eingetragen: Name, Kennung oder Ziel eines Übergangs.
  Result := TAtlasTrackerTransitions.Preferred(FRules, TArray<string>.Create(Trim(FParts.State.Value)));
end;

procedure TAtlasTrackerEndDialog.SetUsers(const AUsers: TArray<string>);
begin
  FParts.Assignee.SetValues(AUsers);
end;

procedure TAtlasTrackerEndDialog.AssigneeChange(Sender: TObject);
begin
  // Wer einen Namen einträgt, will übergeben.
  if FParts.Assignee.Value <> '' then
  begin
    FParts.HandOver.Checked := True;
  end;
end;

function TAtlasTrackerEndDialog.Change: TAtlasTrackerWrite;
var
  mState: string;
  mTransition: Integer;
  mKeep: Boolean;
begin
  mState := FParts.State.Value;
  mKeep := SameText(mState, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState));
  if FRules.StateMachine and not mKeep then
  begin
    mTransition := ChosenTransition;
    // Ohne passenden Übergang geht der Text als Wert hinaus; YouTrack begründet die Ablehnung.
    if mTransition >= 0 then
    begin
      Exit(TAtlasTrackerWorkflow.EndTransition(FOptions, FRules, mTransition,
        StringReplace(FParts.Comment.Text, #13#10, #10, [rfReplaceAll]), FParts.HandOver.Checked,
        FParts.Assignee.Value));
    end;
  end;
  if SameText(mState, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState)) then
  begin
    mState := '';
  end;
  Result := TAtlasTrackerWorkflow.EndChange(FOptions, mState,
    StringReplace(FParts.Comment.Text, #13#10, #10, [rfReplaceAll]), FParts.HandOver.Checked,
    FParts.Assignee.Value);
end;

procedure TAtlasTrackerEndDialog.SetBusy(AValue: Boolean);
begin
  FSending := AValue;
  FParts.State.Enabled := not AValue;
  FParts.Comment.ReadOnly := AValue;
  FParts.HandOver.Enabled := not AValue;
  FParts.Assignee.Enabled := not AValue;
  FParts.Send.Enabled := not AValue;
  FParts.Cancel.Enabled := not AValue;
end;

procedure TAtlasTrackerEndDialog.SendClick(Sender: TObject);
var
  mDialog: TAtlasTrackerEndDialog;
begin
  if FSending then
  begin
    Exit;
  end;
  FChange := Change;
  // Nichts zu schreiben (Zustand bleibt, kein Kommentar, keine Übergabe): nur beenden.
  if not FChange.HasWork or not Assigned(FOnSend) then
  begin
    FSent := True;
    FParts.Editor.Sent;
    ModalResult := mrOk;
    Exit;
  end;
  FParts.Note.Font.Color := clWindowText;
  FParts.Note.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndSending);
  SetBusy(True);
  mDialog := Self;
  FOnSend(FChange,
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      mDialog.SendDone(AResult);
    end);
end;

procedure TAtlasTrackerEndDialog.SendDone(const AResult: TAtlasTrackerWriteResult);
begin
  SetBusy(False);
  if AResult.Succeeded then
  begin
    FSent := True;
    // Geschrieben: Der Entwurf hat sich erledigt.
    FParts.Editor.Sent;
    FParts.Note.Caption := '';
    ModalResult := mrOk;
    Exit;
  end;
  // Kein neuer Versuch von selbst: Der Benutzer ändert und sendet erneut oder bricht ab.
  FParts.Note.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  // Mit seFont übergeht der Stil Font.Color.
  FParts.Note.StyleElements := FParts.Note.StyleElements - [seFont];
  FParts.Note.Caption := ErrorText(FKey, AResult);
end;

procedure TAtlasTrackerEndDialog.DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während des Sendens nicht schließen: Das Ergebnis kommt noch an diesen Dialog.
  CanClose := not FSending;
end;

procedure TAtlasTrackerEndDialog.EditorCancel(Sender: TObject);
begin
  // Esc im Kommentarfeld (ohne offene Vorschlagsliste); der Editor hat den Entwurf schon gesichert.
  if not FSending then
  begin
    ModalResult := mrCancel;
  end;
end;

procedure TAtlasTrackerEndDialog.DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Im Kommentarfeld sendet der Editor selbst (und schluckt das Zeichen der Taste).
  if ActiveControl = FParts.Comment then
  begin
    Exit;
  end;
  if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    SendClick(Self);
  end;
end;

class function TAtlasTrackerEndDialog.ErrorText(const AKey: string; const AResult: TAtlasTrackerWriteResult): string;
begin
  case AResult.Error of
    TAtlasCiFetchError.None:
      Exit('');
    TAtlasCiFetchError.Unauthorized:
      if AResult.Status = 403 then
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteForbidden, [AKey, AResult.Status]);
      end
      else
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteUnauthorized, [AKey, AResult.Status]);
      end;
    TAtlasCiFetchError.NotFound:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteNotFound, [AKey, AResult.Status]);
    TAtlasCiFetchError.Invalid:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteInvalid, [AKey, AResult.Status]);
    TAtlasCiFetchError.Server:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteServer, [AKey, AResult.Status]);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteTimeout);
    TAtlasCiFetchError.NotConfigured:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteNotConfigured);
    TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteUnsupported);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerWriteNetwork);
  end;
  if AResult.Message <> '' then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerWriteReason, [Result, AResult.Message]);
  end;
end;

class function TAtlasTrackerEndDialog.SummaryText(const AChange: TAtlasTrackerWrite): string;
begin
  Result := SummaryText(AChange, '');
end;

class function TAtlasTrackerEndDialog.SummaryText(const AChange: TAtlasTrackerWrite; const ANewState: string): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if (AChange.Transition.Id <> '') and (Trim(ANewState) <> '') then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartTransitionTo,
      [AChange.Transition.Caption, Trim(ANewState)])];
  end
  else if AChange.Transition.Id <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartTransition,
      [AChange.Transition.Caption])];
  end
  else if AChange.State <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartState, [AChange.State])];
  end;
  case AChange.Assign of
    TAtlasTrackerAssign.Me:
      mParts := mParts + [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerPartAssigned)];
    TAtlasTrackerAssign.User:
      mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerPartHandedOver, [AChange.Assignee])];
  else
    // Keep: Zuständigkeit bleibt.
  end;
  if AChange.Comment <> '' then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerPartComment)];
  end;
  Result := string.Join(', ', mParts);
end;

class function TAtlasTrackerEndDialog.Execute(const AKey: string; const AOptions: TAtlasTrackerSyncOptions;
  const AComment: string; const AOnSend: TAtlasTrackerSendEvent; const APrepare: TProc<TAtlasTrackerEndDialog>;
  out AChange: TAtlasTrackerWrite): Boolean;
var
  mDialog: TAtlasTrackerEndDialog;
begin
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, AKey, AOptions, AComment);
  try
    mDialog.OnSend := AOnSend;
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    Result := (mDialog.ShowModal = mrOk) and mDialog.Sent;
    AChange := mDialog.SentChange;
    // Entwurf sichern, solange das Fenster noch lebt (nach Senden ist er schon gelöscht).
    mDialog.FParts.Editor.Unbind;
  finally
    mDialog.Free;
  end;
end;

end.
