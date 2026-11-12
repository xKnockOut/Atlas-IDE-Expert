unit Atlas.UI.Tracker.ReviewDialog;

// Dialog „ATL-2052 prüfen“ (#2126), ohne Open Tools API und nicht modal: Der
// Ablauf (Atlas.IDE.Tracker.Review) wechselt den Branch, baut und testet im
// Hintergrund, der Dialog zeigt die Schritte mit ✓/✗ und lässt die IDE frei.
// - Branch: Trägt genau ein Branch die Kennung, wechselt der Ablauf von selbst;
//   sonst wählt der Benutzer in der Klappliste und klickt „Wechseln“.
// - Ergebnis: „Zustand nicht ändern“, dann unter einer Zustandsmaschine
//   (#2122) die ab dem Prüfzustand erlaubten Übergänge mit bekanntem Ziel
//   („Verifizieren → Verifiziert“), sonst die Zustände vom Tracker.
// - Kommentar: Kommentar-Editor (#1278) mit issues.reviewComment; {build} und
//   {tests} folgen den Ergebnissen, solange der Benutzer nichts geändert hat.
// - „Danach zurück zu … (mein Stand)“: Rückweg auf den eigenen Branch, für
//   „Senden“ wie für „Später entscheiden“ und das Schließen.
// - Geschrieben wird nur mit „Senden“; ein Fehler steht im Dialog, der offen
//   bleibt. Später entscheiden und Schließen schreiben nichts.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Review,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.CommentEditor,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Ereignisse des Dialogs; nil = nichts.</summary>
  TAtlasReviewDialogEvents = record
    /// <summary>„Wechseln“ auf den gewählten Branch.</summary>
    Switch: TProc<string>;
    /// <summary>„Senden“: Änderung im Hintergrund schreiben, Ergebnis über SendDone.</summary>
    Send: TAtlasTrackerSendEvent;
    /// <summary>Der Dialog schließt (nach Senden, „Später entscheiden“ oder X), genau einmal; AReturn: zurück auf
    /// den eigenen Stand.</summary>
    Closed: TProc<Boolean>;
  end;

  /// <summary>Die Steuerelemente des Dialogs (für Tests).</summary>
  TAtlasReviewDialogParts = record
    Branch: TComboBox;
    Switch: TButton;
    Steps: array[TAtlasReviewStep] of TLabel;
    Choice: TComboBox;
    Editor: TAtlasCommentEditor;
    Comment: TMemo;
    Back: TCheckBox;
    Note: TAtlasNoteLabel;
    Later: TButton;
    Send: TButton;
  end;

  TAtlasTrackerReviewDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 540;
    cCommentHeight = 110;
    cEditorBarHeight = 30;
    cLabelWidth = 90;
  private
    FState: TAtlasReviewState;
    FOptions: TAtlasTrackerSyncOptions;
    FTemplate: string;
    FPreset: string;
    FParts: TAtlasReviewDialogParts;
    FEvents: TAtlasReviewDialogEvents;
    FRules: TAtlasTrackerStateRules;
    FStates: TArray<string>;
    FSending: Boolean;
    procedure AddBranch;
    procedure AddSteps;
    procedure AddChoice;
    procedure AddComment;
    procedure AddFoot;
    procedure SwitchClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure LaterClick(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure EditorCancel(Sender: TObject);
    procedure DialogClose(Sender: TObject; var Action: TCloseAction);
    procedure DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FillChoices;
    procedure UpdateComment;
    procedure UpdateButtons;
    procedure FireClosed;
  public
    /// <summary>ATemplate: issues.reviewComment in der Sprache der IDE.</summary>
    constructor CreateDialog(AOwner: TComponent; const AState: TAtlasReviewState;
      const AOptions: TAtlasTrackerSyncOptions; const ATemplate: string);
    destructor Destroy; override;
    /// <summary>Neuer Stand der Schritte: Zeilen, Kommentarvorlage und Rückweg nachziehen.</summary>
    procedure ShowState(const AState: TAtlasReviewState);
    /// <summary>Branch wählen lassen: AChoices in der Klappliste, ANone = kein Branch trägt die Kennung.</summary>
    procedure AskBranch(const AChoices: TArray<string>; ANone: Boolean);
    /// <summary>Zustände und Regeln vom Tracker (ReadStates): Einträge der Klappliste „Ergebnis“.</summary>
    procedure SetStates(const AStates: TArray<string>; const ARules: TAtlasTrackerStateRules);
    /// <summary>Hinweis- oder Fehlerzeile.</summary>
    procedure ShowNote(const AText: string);
    /// <summary>Änderung nach Klappliste und Kommentar.</summary>
    function Change: TAtlasTrackerWrite;
    /// <summary>Ergebnis von Send: geschrieben schließt den Dialog, sonst steht der Grund im Dialog.</summary>
    procedure SendDone(const AResult: TAtlasTrackerWriteResult);
    /// <summary>Einträge der Klappliste „Ergebnis“: „Zustand nicht ändern“, dann unter einer Zustandsmaschine die
    /// Übergänge (mit Ziel aus AStates), sonst die Zustände außer ACurrent.</summary>
    class function ResultChoices(const ARules: TAtlasTrackerStateRules; const AStates: TArray<string>;
      const ACurrent: string): TArray<string>; static;
    /// <summary>Zeile eines Schritts, z. B. „✓ Build Win64 Debug 0/0/0“.</summary>
    class function StepText(const AState: TAtlasReviewState; AStep: TAtlasReviewStep): string; static;
    /// <summary>{build}: „Build Win64 Debug 0/0/0“, „Build ausgelassen“ …</summary>
    class function BuildText(const AState: TAtlasReviewState): string; static;
    /// <summary>{tests}: „14 Tests bestanden“, „2 von 14 Tests fehlgeschlagen“ …</summary>
    class function TestsText(const AState: TAtlasReviewState): string; static;
    property Events: TAtlasReviewDialogEvents read FEvents write FEvents;
    property Parts: TAtlasReviewDialogParts read FParts;
    property Sending: Boolean read FSending;
  end;

implementation

uses
  Atlas.Core.Style.Signal,
  Atlas.Core.Tracker.Transitions,
  Atlas.UI.Tracker.Strings;

const
  cGap = 8;
  /// <summary>Höhen der Zeilen (Feld, Schritt, Haken) und Breite der Klapplisten bei 96 dpi.</summary>
  cFieldRow = 26;
  cStepRow = 20;
  cCheckRow = 24;
  cFieldWidth = 300;
  /// <summary>Zeichen vor den Schritten: wartet, läuft, fertig, gescheitert, ausgelassen.</summary>
  cMarks: array[TAtlasReviewMark] of string = ('○', '…', '✓', '✗', '–');

{ TAtlasTrackerReviewDialog }

constructor TAtlasTrackerReviewDialog.CreateDialog(AOwner: TComponent; const AState: TAtlasReviewState;
  const AOptions: TAtlasTrackerSyncOptions; const ATemplate: string);
begin
  inherited CreateDialog(AOwner, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewCaption, [AState.Key]),
    cDialogWidth);
  FState := AState;
  FOptions := AOptions;
  FTemplate := ATemplate;
  OnClose := DialogClose;
  OnCloseQuery := DialogCloseQuery;
  AddBranch;
  AddSteps;
  AddChoice;
  AddComment;
  AddFoot;
  FitHeight;
  FillChoices;
  ShowState(AState);
end;

destructor TAtlasTrackerReviewDialog.Destroy;
begin
  FEvents := Default(TAtlasReviewDialogEvents);
  inherited;
end;

procedure TAtlasTrackerReviewDialog.AddBranch;
var
  mRow: TPanel;
begin
  mRow := AddRow(cFieldRow);
  AddLabel(mRow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewBranch));
  FParts.Branch := TComboBox.Create(Self);
  FParts.Branch.Parent := mRow;
  FParts.Branch.Left := ScaleValue(cLabelWidth);
  FParts.Branch.Top := 0;
  FParts.Branch.Width := ScaleValue(cFieldWidth);
  FParts.Branch.Style := csDropDown;
  FParts.Branch.Enabled := False;
  FParts.Switch := TButton.Create(Self);
  FParts.Switch.Parent := mRow;
  FParts.Switch.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewSwitch);
  FParts.Switch.Left := FParts.Branch.Left + FParts.Branch.Width + ScaleValue(cGap);
  FParts.Switch.Top := 0;
  FParts.Switch.Width := ScaleValue(100);
  FParts.Switch.OnClick := SwitchClick;
  FParts.Switch.Visible := False;
end;

procedure TAtlasTrackerReviewDialog.AddSteps;
var
  mStep: TAtlasReviewStep;
  mRow: TPanel;
begin
  for mStep := Low(TAtlasReviewStep) to High(TAtlasReviewStep) do
  begin
    mRow := AddRow(cStepRow);
    FParts.Steps[mStep] := TLabel.Create(Self);
    FParts.Steps[mStep].Parent := mRow;
    FParts.Steps[mStep].Align := alClient;
    FParts.Steps[mStep].EllipsisPosition := epEndEllipsis;
    FParts.Steps[mStep].ShowHint := True;
  end;
end;

procedure TAtlasTrackerReviewDialog.AddChoice;
var
  mRow: TPanel;
begin
  mRow := AddRow(cFieldRow);
  AddLabel(mRow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewResult));
  FParts.Choice := TComboBox.Create(Self);
  FParts.Choice.Parent := mRow;
  FParts.Choice.Left := ScaleValue(cLabelWidth);
  FParts.Choice.Top := 0;
  FParts.Choice.Width := ScaleValue(cFieldWidth);
  FParts.Choice.Style := csDropDownList;
end;

/// <summary>Kommentar-Editor (#1278) mit seiner Leiste; die Vorlage ist kein Entwurf.</summary>
procedure TAtlasTrackerReviewDialog.AddComment;
var
  mRow: TPanel;
begin
  mRow := AddRow(cStepRow);
  AddLabel(mRow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewComment));
  FParts.Editor := TAtlasCommentEditor.Create(Self);
  FParts.Editor.Parent := Self;
  FParts.Editor.Align := alTop;
  FParts.Editor.AlignWithMargins := True;
  FParts.Editor.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  FParts.Editor.Top := NextTop;
  FParts.Editor.Height := ScaleValue(cCommentHeight + cEditorBarHeight);
  FParts.Editor.Events := TAtlasCommentEditorEvents.Create(SendClick, EditorCancel);
  FParts.Comment := FParts.Editor.Memo;
end;

procedure TAtlasTrackerReviewDialog.AddFoot;
var
  mRow: TPanel;
  mButtons: TAtlasButtonRow;
begin
  mRow := AddRow(cCheckRow);
  FParts.Back := TCheckBox.Create(Self);
  FParts.Back.Parent := mRow;
  FParts.Back.Align := alClient;
  FParts.Back.Checked := True;
  FParts.Back.OnClick := BackClick;
  FParts.Note := AddNote(cStepRow);
  mButtons := AddButtonRow;
  FParts.Later := mButtons.AddButton(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewLater));
  FParts.Later.OnClick := LaterClick;
  FParts.Send := mButtons.AddButton(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewSendBack),
    TAtlasButtonKind.Default);
  FParts.Send.ModalResult := mrNone;
  FParts.Send.OnClick := SendClick;
end;

class function TAtlasTrackerReviewDialog.ResultChoices(const ARules: TAtlasTrackerStateRules;
  const AStates: TArray<string>; const ACurrent: string): TArray<string>;
var
  mTransition: TAtlasTrackerTransition;
  mState: string;
begin
  Result := TArray<string>.Create(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerEndKeepState));
  if ARules.StateMachine and (ARules.FieldId <> '') then
  begin
    for mTransition in ARules.Transitions do
    begin
      Result := Result + [TAtlasTrackerTransitions.ChoiceText(mTransition, AStates)];
    end;
    Exit;
  end;
  for mState in AStates do
  begin
    if not SameText(Trim(mState), Trim(ACurrent)) then
    begin
      Result := Result + [mState];
    end;
  end;
end;

procedure TAtlasTrackerReviewDialog.FillChoices;
var
  mChoices: TArray<string>;
  mChoice: string;
begin
  mChoices := ResultChoices(FRules, FStates, FRules.Current);
  FParts.Choice.Items.BeginUpdate;
  try
    FParts.Choice.Items.Clear;
    for mChoice in mChoices do
    begin
      FParts.Choice.Items.Add(mChoice);
    end;
  finally
    FParts.Choice.Items.EndUpdate;
  end;
  FParts.Choice.ItemIndex := 0;
end;

procedure TAtlasTrackerReviewDialog.SetStates(const AStates: TArray<string>;
  const ARules: TAtlasTrackerStateRules);
begin
  FStates := Copy(AStates);
  FRules := ARules;
  FillChoices;
end;

function TAtlasTrackerReviewDialog.Change: TAtlasTrackerWrite;
var
  mIndex: Integer;
begin
  mIndex := FParts.Choice.ItemIndex - 1;
  if FRules.StateMachine and (FRules.FieldId <> '') then
  begin
    Result := TAtlasTrackerWorkflow.EndTransition(FOptions, FRules, mIndex, FParts.Editor.Text, False, '');
    Exit;
  end;
  if mIndex >= 0 then
  begin
    Result := TAtlasTrackerWorkflow.EndChange(FOptions, FParts.Choice.Items[FParts.Choice.ItemIndex],
      FParts.Editor.Text, False, '');
  end
  else
  begin
    Result := TAtlasTrackerWorkflow.EndChange(FOptions, '', FParts.Editor.Text, False, '');
  end;
end;

class function TAtlasTrackerReviewDialog.BuildText(const AState: TAtlasReviewState): string;
var
  mBuild: TAtlasReviewBuild;
begin
  mBuild := AState.Build;
  case AState.Marks[TAtlasReviewStep.Build] of
    TAtlasReviewMark.Running:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewBuildRunning);
    TAtlasReviewMark.Done:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewBuildDone, [mBuild.Platform,
        mBuild.Configuration, mBuild.Errors, mBuild.Warnings, mBuild.Hints]);
    TAtlasReviewMark.Failed:
      if mBuild.Errors > 0 then
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewBuildFailed, [mBuild.Platform,
          mBuild.Configuration, mBuild.Errors]);
      end
      else
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewBuildNotStarted);
      end;
    TAtlasReviewMark.Skipped:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewBuildSkipped);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewBuildWaiting);
  end;
  Result := Trim(StringReplace(Result, '  ', ' ', [rfReplaceAll]));
end;

class function TAtlasTrackerReviewDialog.TestsText(const AState: TAtlasReviewState): string;
begin
  case AState.Marks[TAtlasReviewStep.Tests] of
    TAtlasReviewMark.Running:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewTestsRunning);
    TAtlasReviewMark.Done:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewTestsDone, [AState.TestsPassed]);
    TAtlasReviewMark.Failed:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewTestsFailed, [AState.TestsFailed,
        AState.TestsPassed + AState.TestsFailed]);
    TAtlasReviewMark.Skipped:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewTestsSkipped);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewTestsWaiting);
  end;
end;

/// <summary>Text des Schritts „Branch gewechselt“ ohne Zeichen davor.</summary>
function SwitchText(const AState: TAtlasReviewState): string;
begin
  case AState.Marks[TAtlasReviewStep.Switched] of
    TAtlasReviewMark.Running:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewSwitching, [AState.Branch]);
    TAtlasReviewMark.Done:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewSwitched, [AState.Branch]);
    TAtlasReviewMark.Failed:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewSwitchFailed, [AState.Branch,
        AState.SwitchError]);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewSwitchWaiting);
  end;
end;

class function TAtlasTrackerReviewDialog.StepText(const AState: TAtlasReviewState; AStep: TAtlasReviewStep): string;
var
  mText: string;
begin
  case AStep of
    TAtlasReviewStep.Saved:
      if AState.OwnBranch <> '' then
      begin
        mText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewSaved, [AState.OwnBranch]);
      end
      else
      begin
        mText := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewSavedNone);
      end;
    TAtlasReviewStep.Switched:
      mText := SwitchText(AState);
    TAtlasReviewStep.Build:
      mText := BuildText(AState);
  else
    mText := TestsText(AState);
  end;
  Result := cMarks[AState.Marks[AStep]] + ' ' + mText;
end;

procedure TAtlasTrackerReviewDialog.ShowState(const AState: TAtlasReviewState);
var
  mStep: TAtlasReviewStep;
begin
  FState := AState;
  for mStep := Low(TAtlasReviewStep) to High(TAtlasReviewStep) do
  begin
    FParts.Steps[mStep].Caption := StepText(AState, mStep);
    FParts.Steps[mStep].Hint := FParts.Steps[mStep].Caption;
  end;
  if AState.Branch <> '' then
  begin
    FParts.Branch.Text := AState.Branch;
  end;
  FParts.Back.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewBack, [AState.OwnBranch]);
  UpdateComment;
  UpdateButtons;
end;

procedure TAtlasTrackerReviewDialog.AskBranch(const AChoices: TArray<string>; ANone: Boolean);
var
  mChoice: string;
begin
  FParts.Branch.Items.BeginUpdate;
  try
    FParts.Branch.Items.Clear;
    for mChoice in AChoices do
    begin
      FParts.Branch.Items.Add(mChoice);
    end;
  finally
    FParts.Branch.Items.EndUpdate;
  end;
  if Length(AChoices) > 0 then
  begin
    FParts.Branch.ItemIndex := 0;
  end;
  FParts.Branch.Enabled := True;
  FParts.Switch.Visible := True;
  if ANone then
  begin
    ShowNote(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewNoBranch, [FState.Key]));
  end
  else
  begin
    ShowNote(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerReviewChooseBranch, [FState.Key]));
  end;
end;

procedure TAtlasTrackerReviewDialog.ShowNote(const AText: string);
begin
  if AText = '' then
  begin
    FParts.Note.ShowNote('', TAtlasSignalKind.Info);
  end
  else
  begin
    FParts.Note.ShowNote(AText, TAtlasSignalKind.Warning);
  end;
end;

/// <summary>Kommentar aus der Vorlage, solange der Benutzer ihn nicht geändert hat.</summary>
procedure TAtlasTrackerReviewDialog.UpdateComment;
var
  mText: string;
begin
  mText := TAtlasTrackerReview.Comment(FTemplate, FState.Key, FState.Branch, BuildText(FState), TestsText(FState));
  if (FParts.Editor.Text <> FPreset) or (mText = FPreset) then
  begin
    Exit;
  end;
  FPreset := mText;
  FParts.Editor.SetText(mText);
end;

procedure TAtlasTrackerReviewDialog.UpdateButtons;
var
  mWaiting: Boolean;
begin
  mWaiting := FState.Marks[TAtlasReviewStep.Switched] = TAtlasReviewMark.Running;
  FParts.Switch.Enabled := not mWaiting and not FSending;
  FParts.Branch.Enabled := FParts.Switch.Visible and FParts.Switch.Enabled;
  FParts.Back.Enabled := FState.CanReturn and not FSending;
  FParts.Choice.Enabled := not FSending;
  FParts.Later.Enabled := not FSending;
  FParts.Send.Enabled := not FSending;
  if FParts.Back.Enabled and FParts.Back.Checked then
  begin
    FParts.Send.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewSendBack);
  end
  else
  begin
    FParts.Send.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerReviewSend);
  end;
end;

procedure TAtlasTrackerReviewDialog.SwitchClick(Sender: TObject);
var
  mBranch: string;
begin
  mBranch := Trim(FParts.Branch.Text);
  if (mBranch = '') or not Assigned(FEvents.Switch) then
  begin
    Exit;
  end;
  FParts.Switch.Visible := False;
  FParts.Branch.Enabled := False;
  ShowNote('');
  FEvents.Switch(mBranch);
end;

procedure TAtlasTrackerReviewDialog.BackClick(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TAtlasTrackerReviewDialog.SendClick(Sender: TObject);
var
  mChange: TAtlasTrackerWrite;
begin
  if FSending then
  begin
    Exit;
  end;
  mChange := Change;
  if not mChange.HasWork or not Assigned(FEvents.Send) then
  begin
    // Nichts zu schreiben: wie „Später entscheiden“.
    Close;
    Exit;
  end;
  FSending := True;
  ShowNote('');
  UpdateButtons;
  FEvents.Send(mChange, SendDone);
end;

procedure TAtlasTrackerReviewDialog.SendDone(const AResult: TAtlasTrackerWriteResult);
begin
  FSending := False;
  if AResult.Succeeded then
  begin
    Close;
    Exit;
  end;
  ShowNote(TAtlasTrackerEndDialog.ErrorText(FState.Key, AResult));
  UpdateButtons;
end;

procedure TAtlasTrackerReviewDialog.LaterClick(Sender: TObject);
begin
  Close;
end;

procedure TAtlasTrackerReviewDialog.EditorCancel(Sender: TObject);
begin
  Close;
end;

procedure TAtlasTrackerReviewDialog.DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während des Schreibens bleibt der Dialog offen (höchstens TAtlasTrackerWorkflow.cWriteTimeoutMs).
  CanClose := not FSending;
end;

procedure TAtlasTrackerReviewDialog.DialogClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  FireClosed;
end;

procedure TAtlasTrackerReviewDialog.FireClosed;
var
  mClosed: TProc<Boolean>;
begin
  // Genau einmal: Danach sind die Ereignisse gelöst.
  mClosed := FEvents.Closed;
  FEvents := Default(TAtlasReviewDialogEvents);
  if Assigned(mClosed) then
  begin
    mClosed(FParts.Back.Enabled and FParts.Back.Checked);
  end;
end;

end.
