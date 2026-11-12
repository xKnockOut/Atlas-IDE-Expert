unit Atlas.UI.Tracker.SprintDialog;

// Rückfrage beim Beginnen, wenn das Issue in keinem laufenden Sprint des
// Boards steht (#2128, issues.sprintOnStart = ask), reine VCL:
//   ATL-2071 beginnen
//   ATL-2071 „Absturz beim Schließen“ ist in keinem Sprint von „Atlas-Board“.
//   In den laufenden Sprint „Sprint 47“ (bis 19.11.) aufnehmen?
//   [ ] Nicht mehr fragen
//        [Ohne Sprint beginnen] [Aufnehmen und beginnen] [Abbrechen]
// Eingabe nimmt auf, Esc bricht das Beginnen ab.

interface

uses
  System.Classes,
  Vcl.StdCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.WrapLabel;

type
{$SCOPEDENUMS ON}
  /// <summary>Antwort: abbrechen, ohne Sprint beginnen, aufnehmen und beginnen.</summary>
  TAtlasSprintAnswer = (Cancel, Without, Add);
{$SCOPEDENUMS OFF}

  TAtlasTrackerSprintDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 460;
  private
    FQuestion: TAtlasWrapLabel;
    FDontAsk: TCheckBox;
    FAdd: TButton;
    FWithout: TButton;
  public
    constructor CreateDialog(AOwner: TComponent; const AKey, ATitle: string; const ASprint: TAtlasTrackerSprintRef);
    /// <summary>Text der Frage; ohne Ende des Sprints ohne „(bis …)“.</summary>
    class function QuestionText(const AKey, ATitle: string; const ASprint: TAtlasTrackerSprintRef): string; static;
    /// <summary>Antwort zu einem ModalResult.</summary>
    class function AnswerOf(AResult: Integer): TAtlasSprintAnswer; static;
    /// <summary>Modal fragen; ADontAsk nur bei einer Antwort außer Cancel.</summary>
    class function Ask(const AKey, ATitle: string; const ASprint: TAtlasTrackerSprintRef;
      out ADontAsk: Boolean): TAtlasSprintAnswer; static;
    property Question: TAtlasWrapLabel read FQuestion;
    property DontAskCheck: TCheckBox read FDontAsk;
    property AddButton: TButton read FAdd;
    property WithoutButton: TButton read FWithout;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.UITypes,
  Vcl.Controls,
  Atlas.UI.Tracker.Strings;

{ TAtlasTrackerSprintDialog }

constructor TAtlasTrackerSprintDialog.CreateDialog(AOwner: TComponent; const AKey, ATitle: string;
  const ASprint: TAtlasTrackerSprintRef);
var
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SprintStartTitle, [AKey]),
    cDialogWidth);
  FQuestion := TAtlasWrapLabel.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FQuestion.Top := NextTop;
  FQuestion.AlignWithMargins := True;
  FQuestion.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap), 0);
  FQuestion.Align := alTop;
  FQuestion.Parent := Self;
  FQuestion.WordWrap := True;
  FQuestion.Caption := QuestionText(AKey, ATitle, ASprint);

  FDontAsk := TCheckBox.Create(Self);
  FDontAsk.Top := NextTop;
  FDontAsk.AlignWithMargins := True;
  FDontAsk.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap), 0);
  FDontAsk.Align := alTop;
  FDontAsk.Parent := Self;
  FDontAsk.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SprintStartDontAsk);

  mButtons := AddButtonRow;
  FWithout := mButtons.AddButton(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SprintStartWithout));
  FWithout.ModalResult := mrNo;
  FAdd := mButtons.AddButton(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SprintStartAccept),
    TAtlasButtonKind.Default);
  FAdd.ModalResult := mrYes;
  mButtons.AddButton(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SprintStartCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  AllowResize(nil);
  ActiveControl := FAdd;
end;

class function TAtlasTrackerSprintDialog.QuestionText(const AKey, ATitle: string;
  const ASprint: TAtlasTrackerSprintRef): string;
var
  mAdd: string;
begin
  if ASprint.Finish > 0 then
  begin
    mAdd := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SprintStartAdd, [ASprint.Sprint,
      FormatDateTime(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SprintStartDate),
      TTimeZone.Local.ToLocalTime(ASprint.Finish), TFormatSettings.Invariant)]);
  end
  else
  begin
    mAdd := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SprintStartAddOpen, [ASprint.Sprint]);
  end;
  Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SprintStartQuestion, [AKey, ATitle, ASprint.Board]) +
    sLineBreak + mAdd;
end;

class function TAtlasTrackerSprintDialog.AnswerOf(AResult: Integer): TAtlasSprintAnswer;
begin
  Result := TAtlasSprintAnswer.Cancel;
  if AResult = mrYes then
  begin
    Result := TAtlasSprintAnswer.Add;
  end
  else if AResult = mrNo then
  begin
    Result := TAtlasSprintAnswer.Without;
  end;
end;

class function TAtlasTrackerSprintDialog.Ask(const AKey, ATitle: string; const ASprint: TAtlasTrackerSprintRef;
  out ADontAsk: Boolean): TAtlasSprintAnswer;
var
  mDialog: TAtlasTrackerSprintDialog;
begin
  mDialog := TAtlasTrackerSprintDialog.CreateDialog(nil, AKey, ATitle, ASprint);
  try
    Result := AnswerOf(mDialog.ShowModal);
    ADontAsk := (Result <> TAtlasSprintAnswer.Cancel) and mDialog.DontAskCheck.Checked;
  finally
    mDialog.Free;
  end;
end;

end.
