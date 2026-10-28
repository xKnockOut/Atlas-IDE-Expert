unit Atlas.UI.Tracker.EndDialog;

// Dialog „ATL-123 beenden“ (#1266), ohne Open Tools API: Zielzustand
// (issues.endStates und „Zustand nicht ändern“, dazu Werte vom Tracker,
// Eingabe von Hand), Kommentar vorgefüllt aus issues.endComment und das
// Häkchen „Zuständigkeit übergeben an“ mit der Benutzerliste vom Tracker.
// - Geschrieben wird nur mit „Senden“: OnSend schreibt im Hintergrund und
//   meldet über SendDone im Hauptthread. Solange gesendet wird, sind Felder
//   und „Abbrechen“ gesperrt und der Dialog schließt nicht (die Zeitgrenze
//   des Schreibens ist TAtlasTrackerWorkflow.WriteTimeoutMs).
// - Fehler erscheinen im Dialog mit dem Text des Trackers (ErrorText, z. B.
//   „Keine Schreibrechte für ATL-123 (403).“); nichts wird wiederholt, der
//   Benutzer kann ändern und erneut senden oder abbrechen.
// - Strg+Enter sendet; Esc bricht ab.
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
  Atlas.UI.Tracker.ValueBox;

type
  /// <summary>Ergebnis des Schreibens, im Hauptthread.</summary>
  TAtlasTrackerSendDone = reference to procedure(const AResult: TAtlasTrackerWriteResult);
  /// <summary>AChange im Hintergrund schreiben und ADone im Hauptthread aufrufen (genau einmal).</summary>
  TAtlasTrackerSendEvent = reference to procedure(const AChange: TAtlasTrackerChange;
    const ADone: TAtlasTrackerSendDone);

  TAtlasTrackerEndDialog = class(TForm)
  public const
    DialogWidth = 520;
    CommentHeight = 150;
  private
    FKey: string;
    FOptions: TAtlasTrackerSyncOptions;
    FState: TAtlasValueBox;
    FComment: TMemo;
    FHandOver: TCheckBox;
    FAssignee: TAtlasValueBox;
    FNote: TLabel;
    FSend: TButton;
    FCancel: TButton;
    FOnSend: TAtlasTrackerSendEvent;
    FSending: Boolean;
    FSent: Boolean;
    FChange: TAtlasTrackerChange;
    function AddRow(AHeight: Integer): TPanel;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
    procedure SendClick(Sender: TObject);
    procedure AssigneeChange(Sender: TObject);
    procedure DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SetBusy(AValue: Boolean);
  public
    /// <summary>AComment: ausgefüllte Vorlage issues.endComment (Zeilen mit #10).</summary>
    constructor CreateDialog(AOwner: TComponent; const AKey: string; const AOptions: TAtlasTrackerSyncOptions;
      const AComment: string);
    /// <summary>Werte des Zustandsfeldes vom Tracker als weitere Vorschläge hinter issues.endStates.</summary>
    procedure SetStates(const AStates: TArray<string>);
    /// <summary>Benutzer vom Tracker für „Zuständigkeit übergeben an“.</summary>
    procedure SetUsers(const AUsers: TArray<string>);
    /// <summary>Änderung nach den Feldern.</summary>
    function Change: TAtlasTrackerChange;
    /// <summary>Ergebnis von OnSend: geschrieben schließt den Dialog mit mrOk, sonst steht der Grund im Dialog.
    /// </summary>
    procedure SendDone(const AResult: TAtlasTrackerWriteResult);
    /// <summary>Vorschläge der Klappliste Zielzustand: „Zustand nicht ändern“, dann AOptions.EndStates.</summary>
    class function StateChoices(const AOptions: TAtlasTrackerSyncOptions): TArray<string>; static;
    /// <summary>Grund eines Fehlers mit dem Text des Trackers; '' bei Erfolg.</summary>
    class function ErrorText(const AKey: string; const AResult: TAtlasTrackerWriteResult): string; static;
    /// <summary>Was geschrieben wurde, z. B. „Zustand „Erledigt“, an anna übergeben, Kommentar“.</summary>
    class function SummaryText(const AChange: TAtlasTrackerChange): string; static;
    /// <summary>Modal zeigen; True nach erfolgreichem „Senden“ mit der geschriebenen Änderung in AChange.
    /// APrepare (darf nil sein) passt das Fenster vorher an und kann Werte nachladen (SetUsers).</summary>
    class function Execute(const AKey: string; const AOptions: TAtlasTrackerSyncOptions; const AComment: string;
      const AOnSend: TAtlasTrackerSendEvent; const APrepare: TProc<TAtlasTrackerEndDialog>;
      out AChange: TAtlasTrackerChange): Boolean; static;
    property OnSend: TAtlasTrackerSendEvent read FOnSend write FOnSend;
    /// <summary>Senden war erfolgreich.</summary>
    property Sent: Boolean read FSent;
    property Sending: Boolean read FSending;
    /// <summary>Gesendete Änderung (gilt mit Sent).</summary>
    property SentChange: TAtlasTrackerChange read FChange;
    property StateBox: TAtlasValueBox read FState;
    property CommentMemo: TMemo read FComment;
    property HandOverCheck: TCheckBox read FHandOver;
    property AssigneeBox: TAtlasValueBox read FAssignee;
    property Note: TLabel read FNote;
    property SendButton: TButton read FSend;
    property CancelButton: TButton read FCancel;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.Core.Ci.Contract,
  Atlas.UI.Strings;

const
  Gap = 8;

{ TAtlasTrackerEndDialog }

constructor TAtlasTrackerEndDialog.CreateDialog(AOwner: TComponent; const AKey: string;
  const AOptions: TAtlasTrackerSyncOptions; const AComment: string);
var
  mRow: TPanel;
  mLabel: TLabel;
  mButtons: TFlowPanel;
  mChoices: TArray<string>;
begin
  inherited CreateNew(AOwner);
  FKey := AKey;
  FOptions := AOptions;
  FChange := TAtlasTrackerChange.Empty;
  Caption := TAtlasStrings.Fmt(TAtlasTextId.TrackerEndCaption, [AKey]);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  KeyPreview := True;
  OnKeyDown := DialogKeyDown;
  OnCloseQuery := DialogCloseQuery;

  mRow := AddRow(26);
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mRow;
  mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.TrackerEndState);
  mLabel.Left := 0;
  mLabel.Top := ScaleValue(4);
  FState := TAtlasValueBox.Create(Self);
  FState.Parent := mRow;
  FState.Left := ScaleValue(180);
  FState.Top := 0;
  FState.Width := ScaleValue(240);
  mChoices := StateChoices(AOptions);
  FState.SetValues(mChoices);
  // Vorgabe: der erste angebotene Zielzustand, ohne Liste „Zustand nicht ändern“.
  if Length(mChoices) > 1 then
    FState.Value := mChoices[1]
  else
    FState.Value := mChoices[0];

  mRow := AddRow(20);
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mRow;
  mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.TrackerEndComment);
  mLabel.Left := 0;
  mLabel.Top := ScaleValue(2);
  FComment := TMemo.Create(Self);
  FComment.Parent := Self;
  FComment.Align := alTop;
  FComment.AlignWithMargins := True;
  FComment.Margins.SetBounds(Gap, Gap div 2, Gap, 0);
  FComment.Top := mRow.Top + mRow.Height + 1;
  FComment.Height := ScaleValue(CommentHeight);
  FComment.ScrollBars := ssVertical;
  FComment.WantReturns := True;
  FComment.Text := AdjustLineBreaks(AComment, tlbsCRLF);

  mRow := AddRow(26);
  mRow.Top := FComment.Top + FComment.Height + 1;
  FHandOver := TCheckBox.Create(Self);
  FHandOver.Parent := mRow;
  FHandOver.Caption := TAtlasStrings.Text(TAtlasTextId.TrackerEndHandOver);
  FHandOver.Left := 0;
  FHandOver.Top := ScaleValue(3);
  FHandOver.Width := ScaleValue(176);
  FAssignee := TAtlasValueBox.Create(Self);
  FAssignee.Parent := mRow;
  FAssignee.Left := ScaleValue(180);
  FAssignee.Top := 0;
  FAssignee.Width := ScaleValue(240);
  FAssignee.OnChange := AssigneeChange;

  mRow := AddRow(20);
  FNote := TLabel.Create(Self);
  FNote.Parent := mRow;
  FNote.Align := alClient;
  FNote.WordWrap := True;
  FNote.Caption := '';

  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(Gap, Gap, Gap, Gap);
  mButtons.Top := mRow.Top + mRow.Height + 1;
  FSend := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TrackerEndSend));
  FSend.OnClick := SendClick;
  FSend.Default := True;
  FCancel := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TrackerEndCancel));
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  ActiveControl := FComment;
  ClientHeight := mButtons.Top + mButtons.Height + Gap;
end;

function TAtlasTrackerEndDialog.AddRow(AHeight: Integer): TPanel;
var
  mTop: Integer;
  mIndex: Integer;
begin
  // Unter das bisher unterste Element (alTop stapelt nach Top).
  mTop := 0;
  for mIndex := 0 to ControlCount - 1 do
    if Controls[mIndex].Top + Controls[mIndex].Height + 1 > mTop then
      mTop := Controls[mIndex].Top + Controls[mIndex].Height + 1;
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, Gap div 2, Gap, 0);
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.Top := mTop;
  Result.Height := ScaleValue(AHeight);
end;

function TAtlasTrackerEndDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, Gap, Gap div 2);
end;

class function TAtlasTrackerEndDialog.StateChoices(const AOptions: TAtlasTrackerSyncOptions): TArray<string>;
begin
  Result := TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.TrackerEndKeepState)) + Copy(AOptions.EndStates);
end;

procedure TAtlasTrackerEndDialog.SetStates(const AStates: TArray<string>);
var
  mChoices: TArray<string>;
  mState, mChoice: string;
  mFound: Boolean;
begin
  mChoices := StateChoices(FOptions);
  for mState in AStates do
  begin
    mFound := False;
    for mChoice in mChoices do
      if SameText(mChoice, mState) then
        mFound := True;
    if not mFound then
      mChoices := mChoices + [mState];
  end;
  FState.SetValues(mChoices);
end;

procedure TAtlasTrackerEndDialog.SetUsers(const AUsers: TArray<string>);
begin
  FAssignee.SetValues(AUsers);
end;

procedure TAtlasTrackerEndDialog.AssigneeChange(Sender: TObject);
begin
  // Wer einen Namen einträgt, will übergeben.
  if FAssignee.Value <> '' then
    FHandOver.Checked := True;
end;

function TAtlasTrackerEndDialog.Change: TAtlasTrackerChange;
var
  mState: string;
begin
  mState := FState.Value;
  if SameText(mState, TAtlasStrings.Text(TAtlasTextId.TrackerEndKeepState)) then
    mState := '';
  Result := TAtlasTrackerWorkflow.EndChange(FOptions, mState,
    StringReplace(FComment.Text, #13#10, #10, [rfReplaceAll]), FHandOver.Checked, FAssignee.Value);
end;

procedure TAtlasTrackerEndDialog.SetBusy(AValue: Boolean);
begin
  FSending := AValue;
  FState.Enabled := not AValue;
  FComment.ReadOnly := AValue;
  FHandOver.Enabled := not AValue;
  FAssignee.Enabled := not AValue;
  FSend.Enabled := not AValue;
  FCancel.Enabled := not AValue;
end;

procedure TAtlasTrackerEndDialog.SendClick(Sender: TObject);
var
  mDialog: TAtlasTrackerEndDialog;
begin
  if FSending then
    Exit;
  FChange := Change;
  // Nichts zu schreiben (Zustand bleibt, kein Kommentar, keine Übergabe): nur beenden.
  if not FChange.HasWork or not Assigned(FOnSend) then
  begin
    FSent := True;
    ModalResult := mrOk;
    Exit;
  end;
  FNote.Font.Color := clWindowText;
  FNote.Caption := TAtlasStrings.Text(TAtlasTextId.TrackerEndSending);
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
    FNote.Caption := '';
    ModalResult := mrOk;
    Exit;
  end;
  // Kein neuer Versuch von selbst: Der Benutzer ändert und sendet erneut oder bricht ab.
  FNote.Font.Color := clRed;
  FNote.Caption := ErrorText(FKey, AResult);
end;

procedure TAtlasTrackerEndDialog.DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während des Sendens nicht schließen: Das Ergebnis kommt noch an diesen Dialog.
  CanClose := not FSending;
end;

procedure TAtlasTrackerEndDialog.DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
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
        Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerWriteForbidden, [AKey, AResult.Status])
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerWriteUnauthorized, [AKey, AResult.Status]);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerWriteNotFound, [AKey, AResult.Status]);
    TAtlasCiFetchError.Invalid:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerWriteInvalid, [AKey, AResult.Status]);
    TAtlasCiFetchError.Server:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerWriteServer, [AKey, AResult.Status]);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.TrackerWriteTimeout);
    TAtlasCiFetchError.NotConfigured:
      Result := TAtlasStrings.Text(TAtlasTextId.TrackerWriteNotConfigured);
    TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasStrings.Text(TAtlasTextId.TrackerWriteUnsupported);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.TrackerWriteNetwork);
  end;
  if AResult.Message <> '' then
    Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerWriteReason, [Result, AResult.Message]);
end;

class function TAtlasTrackerEndDialog.SummaryText(const AChange: TAtlasTrackerChange): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if AChange.State <> '' then
    mParts := mParts + [TAtlasStrings.Fmt(TAtlasTextId.TrackerPartState, [AChange.State])];
  case AChange.Assign of
    TAtlasTrackerAssign.Me:
      mParts := mParts + [TAtlasStrings.Text(TAtlasTextId.TrackerPartAssigned)];
    TAtlasTrackerAssign.User:
      mParts := mParts + [TAtlasStrings.Fmt(TAtlasTextId.TrackerPartHandedOver, [AChange.Assignee])];
  else
    // Keep: Zuständigkeit bleibt.
  end;
  if AChange.Comment <> '' then
    mParts := mParts + [TAtlasStrings.Text(TAtlasTextId.TrackerPartComment)];
  Result := string.Join(', ', mParts);
end;

class function TAtlasTrackerEndDialog.Execute(const AKey: string; const AOptions: TAtlasTrackerSyncOptions;
  const AComment: string; const AOnSend: TAtlasTrackerSendEvent; const APrepare: TProc<TAtlasTrackerEndDialog>;
  out AChange: TAtlasTrackerChange): Boolean;
var
  mDialog: TAtlasTrackerEndDialog;
begin
  mDialog := TAtlasTrackerEndDialog.CreateDialog(nil, AKey, AOptions, AComment);
  try
    mDialog.OnSend := AOnSend;
    if Assigned(APrepare) then
      APrepare(mDialog);
    Result := (mDialog.ShowModal = mrOk) and mDialog.Sent;
    AChange := mDialog.SentChange;
  finally
    mDialog.Free;
  end;
end;

end.
