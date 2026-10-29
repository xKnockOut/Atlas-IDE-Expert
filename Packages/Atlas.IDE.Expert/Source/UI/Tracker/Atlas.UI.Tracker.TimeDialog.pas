unit Atlas.UI.Tracker.TimeDialog;

// Dialog „1 h 25 min auf ATL-123 buchen?“ (#1267), ohne Open Tools API.
// - Dauer (gerundet auf issues.timeRounding, als "1:25"; Eingabe auch "85",
//   "1 h 25 min"), Beschreibung (Vorlage: Commit-Betreffe) und je nach
//   Tracker der Arbeitstyp (YouTrack, Liste vom Tracker nachgeladen, Eingabe
//   von Hand) bzw. das Häkchen „Als Kommentar … senden“ (GitHub, Vorgabe aus;
//   ohne Häkchen wird nur lokal als gebucht vermerkt).
// - Knöpfe Buchen, Später (Esc) und Verwerfen. Gebucht wird nur mit „Buchen“:
//   OnBook bucht im Hintergrund und meldet über BookDone im Hauptthread;
//   solange sind die Knöpfe gesperrt und der Dialog schließt nicht. Fehler
//   stehen im Dialog, nichts wird wiederholt.
// - SetTrackingOff (Zeiterfassung im YouTrack-Projekt aus): Hinweis, „Buchen“
//   gesperrt, die Zeit bleibt lokal.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.ValueBox;

type
{$SCOPEDENUMS ON}
  /// <summary>Was mit der Zeit geschieht: später fragen, gebucht, verworfen.</summary>
  TAtlasTimeDecision = (Later, Booked, Discarded);
  /// <summary>Art der Buchung: Work Item (YouTrack) oder Kommentar (GitHub, optional).</summary>
  TAtlasTimeBookMode = (WorkItem, Comment);
{$SCOPEDENUMS OFF}

  /// <summary>AItem im Hintergrund buchen und ADone im Hauptthread aufrufen (genau einmal).</summary>
  TAtlasTimeBookEvent = reference to procedure(const AItem: TAtlasTrackerWorkItem;
    const ADone: TAtlasTrackerSendDone);
  /// <summary>Der Fehler bedeutet „Zeiterfassung im Projekt aus“.</summary>
  TAtlasTimeOffCheck = reference to function(const AResult: TAtlasTrackerWriteResult): Boolean;

  TAtlasTrackerTimeDialog = class(TForm)
  public const
    DialogWidth = 480;
    TextHeight = 90;
  private
    FKey: string;
    FDate: TDateTime;
    FMode: TAtlasTimeBookMode;
    FQuestion: TLabel;
    FDuration: TEdit;
    FWorkType: TAtlasValueBox;
    FText: TMemo;
    FAsComment: TCheckBox;
    FNote: TLabel;
    FBook: TButton;
    FLater: TButton;
    FDiscard: TButton;
    FOnBook: TAtlasTimeBookEvent;
    FIsTrackingOff: TAtlasTimeOffCheck;
    FSending: Boolean;
    FTrackingOff: Boolean;
    FDecision: TAtlasTimeDecision;
    FItem: TAtlasTrackerWorkItem;
    FSent: Boolean;
    function AddRow(AHeight: Integer): TPanel;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
    procedure BookClick(Sender: TObject);
    procedure DiscardClick(Sender: TObject);
    procedure DurationChange(Sender: TObject);
    procedure DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure SetBusy(AValue: Boolean);
    procedure ShowNote(const AText: string; AError: Boolean);
  public
    /// <summary>ASeconds: erfasste Zeit; ARounding: issues.timeRounding; ADate: Tag der Buchung; AText:
    /// Vorlage der Beschreibung.</summary>
    constructor CreateDialog(AOwner: TComponent; const AKey: string; ASeconds: Int64; ARounding: Integer;
      ADate: TDateTime; const AText: string; AMode: TAtlasTimeBookMode);
    /// <summary>Arbeitstypen vom Tracker für die Klappliste.</summary>
    procedure SetWorkTypes(const ATypes: TArray<string>);
    /// <summary>Zeiterfassung im Projekt aus: Hinweis, „Buchen“ gesperrt.</summary>
    procedure SetTrackingOff;
    /// <summary>Buchung nach den Feldern; False bei ungültiger Dauer.</summary>
    function Item(out AItem: TAtlasTrackerWorkItem): Boolean;
    /// <summary>Ergebnis von OnBook: gebucht schließt den Dialog, sonst steht der Grund im Dialog.</summary>
    procedure BookDone(const AResult: TAtlasTrackerWriteResult);
    /// <summary>Frage über dem Dialog: „1 h 25 min auf ATL-123 buchen?“.</summary>
    class function QuestionText(const AKey: string; AMinutes: Integer): string; static;
    /// <summary>Modal zeigen; Entscheidung mit der gebuchten Zeit in AItem (gilt bei Booked). APrepare (darf nil
    /// sein) setzt OnBook-Ergänzungen und lädt Arbeitstypen nach.</summary>
    class function Execute(const AKey: string; ASeconds: Int64; ARounding: Integer; ADate: TDateTime;
      const AText: string; AMode: TAtlasTimeBookMode; const AOnBook: TAtlasTimeBookEvent;
      const APrepare: TProc<TAtlasTrackerTimeDialog>; out AItem: TAtlasTrackerWorkItem): TAtlasTimeDecision; static;
    property OnBook: TAtlasTimeBookEvent read FOnBook write FOnBook;
    property IsTrackingOff: TAtlasTimeOffCheck read FIsTrackingOff write FIsTrackingOff;
    property Decision: TAtlasTimeDecision read FDecision;
    /// <summary>Gebuchte Zeit (gilt mit Decision = Booked).</summary>
    property BookedItem: TAtlasTrackerWorkItem read FItem;
    /// <summary>Beim Tracker gebucht (nicht nur lokal vermerkt).</summary>
    property Sent: Boolean read FSent;
    property Sending: Boolean read FSending;
    property TrackingOff: Boolean read FTrackingOff;
    property Question: TLabel read FQuestion;
    property DurationEdit: TEdit read FDuration;
    property WorkTypeBox: TAtlasValueBox read FWorkType;
    property TextMemo: TMemo read FText;
    property AsCommentCheck: TCheckBox read FAsComment;
    property Note: TLabel read FNote;
    property BookButton: TButton read FBook;
    property LaterButton: TButton read FLater;
    property DiscardButton: TButton read FDiscard;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Strings;

const
  Gap = 8;
  FieldLeft = 120;

{ TAtlasTrackerTimeDialog }

constructor TAtlasTrackerTimeDialog.CreateDialog(AOwner: TComponent; const AKey: string; ASeconds: Int64;
  ARounding: Integer; ADate: TDateTime; const AText: string; AMode: TAtlasTimeBookMode);
var
  mRow: TPanel;
  mButtons: TFlowPanel;
  mMinutes: Integer;
begin
  inherited CreateNew(AOwner);
  FKey := AKey;
  FDate := ADate;
  FMode := AMode;
  FDecision := TAtlasTimeDecision.Later;
  FItem := TAtlasTrackerWorkItem.Create(0, ADate, '', '');
  Caption := TAtlasStrings.Text(TAtlasTextId.TimeBookCaption);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  OnCloseQuery := DialogCloseQuery;
  mMinutes := TAtlasTimeRounding.Minutes(ASeconds, ARounding);

  mRow := AddRow(22);
  FQuestion := AddLabel(mRow, QuestionText(AKey, mMinutes));
  FQuestion.Font.Style := [fsBold];

  mRow := AddRow(26);
  AddLabel(mRow, TAtlasStrings.Text(TAtlasTextId.TimeBookDuration));
  FDuration := TEdit.Create(Self);
  FDuration.Parent := mRow;
  FDuration.Left := ScaleValue(FieldLeft);
  FDuration.Top := 0;
  FDuration.Width := ScaleValue(80);
  FDuration.Text := TAtlasTimeRounding.ClockText(Int64(mMinutes) * 60);
  FDuration.OnChange := DurationChange;

  FWorkType := TAtlasValueBox.Create(Self);
  FAsComment := TCheckBox.Create(Self);
  mRow := AddRow(26);
  if AMode = TAtlasTimeBookMode.WorkItem then
  begin
    AddLabel(mRow, TAtlasStrings.Text(TAtlasTextId.TimeBookWorkType));
    FWorkType.Parent := mRow;
    FWorkType.Left := ScaleValue(FieldLeft);
    FWorkType.Top := 0;
    FWorkType.Width := ScaleValue(240);
  end
  else
  begin
    FAsComment.Parent := mRow;
    FAsComment.Caption := TAtlasStrings.Text(TAtlasTextId.TimeBookAsComment);
    FAsComment.Left := 0;
    FAsComment.Top := ScaleValue(3);
    FAsComment.Width := ScaleValue(DialogWidth - 2 * Gap);
    FAsComment.Checked := False;
  end;

  mRow := AddRow(20);
  AddLabel(mRow, TAtlasStrings.Text(TAtlasTextId.TimeBookText));
  FText := TMemo.Create(Self);
  FText.Parent := Self;
  FText.Align := alTop;
  FText.AlignWithMargins := True;
  FText.Margins.SetBounds(Gap, Gap div 2, Gap, 0);
  FText.Top := mRow.Top + mRow.Height + 1;
  FText.Height := ScaleValue(TextHeight);
  FText.ScrollBars := ssVertical;
  FText.WantReturns := True;
  FText.Text := AdjustLineBreaks(AText, tlbsCRLF);

  mRow := AddRow(34);
  mRow.Top := FText.Top + FText.Height + 1;
  FNote := TLabel.Create(Self);
  FNote.Parent := mRow;
  FNote.Align := alClient;
  FNote.WordWrap := True;
  FNote.Caption := '';
  if AMode = TAtlasTimeBookMode.Comment then
    ShowNote(TAtlasStrings.Text(TAtlasTextId.TimeBookLocalOnly), False);

  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(Gap, Gap, Gap, Gap);
  mButtons.Top := mRow.Top + mRow.Height + 1;
  FBook := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TimeBookBook));
  FBook.OnClick := BookClick;
  FBook.Default := True;
  FLater := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TimeBookLater));
  FLater.ModalResult := mrCancel;
  FLater.Cancel := True;
  FDiscard := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TimeBookDiscard));
  FDiscard.OnClick := DiscardClick;
  ActiveControl := FDuration;
  ClientHeight := mButtons.Top + mButtons.Height + Gap;
end;

function TAtlasTrackerTimeDialog.AddRow(AHeight: Integer): TPanel;
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

function TAtlasTrackerTimeDialog.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := 0;
  Result.Top := ScaleValue(4);
end;

function TAtlasTrackerTimeDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, Gap, Gap div 2);
end;

class function TAtlasTrackerTimeDialog.QuestionText(const AKey: string; AMinutes: Integer): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.TimeBookQuestion, [TAtlasTrackerWorkflow.DurationText(AMinutes), AKey]);
end;

procedure TAtlasTrackerTimeDialog.ShowNote(const AText: string; AError: Boolean);
begin
  if AError then
    FNote.Font.Color := clRed
  else
    FNote.Font.Color := clWindowText;
  FNote.Caption := AText;
end;

procedure TAtlasTrackerTimeDialog.SetWorkTypes(const ATypes: TArray<string>);
begin
  FWorkType.SetValues(ATypes);
end;

procedure TAtlasTrackerTimeDialog.SetTrackingOff;
begin
  FTrackingOff := True;
  FBook.Enabled := False;
  FBook.Default := False;
  FLater.Default := True;
  ShowNote(TAtlasStrings.Text(TAtlasTextId.TimeBookOff), False);
end;

procedure TAtlasTrackerTimeDialog.DurationChange(Sender: TObject);
var
  mMinutes: Integer;
begin
  // Die Frage folgt der eingegebenen Dauer.
  if TAtlasTimeRounding.ParseDuration(FDuration.Text, mMinutes) then
    FQuestion.Caption := QuestionText(FKey, mMinutes);
end;

function TAtlasTrackerTimeDialog.Item(out AItem: TAtlasTrackerWorkItem): Boolean;
var
  mMinutes: Integer;
  mType: string;
begin
  Result := TAtlasTimeRounding.ParseDuration(FDuration.Text, mMinutes);
  mType := '';
  if FMode = TAtlasTimeBookMode.WorkItem then
    mType := FWorkType.Value;
  AItem := TAtlasTrackerWorkItem.Create(mMinutes, FDate, mType,
    Trim(StringReplace(FText.Text, #13#10, #10, [rfReplaceAll])));
end;

procedure TAtlasTrackerTimeDialog.SetBusy(AValue: Boolean);
begin
  FSending := AValue;
  FDuration.ReadOnly := AValue;
  FWorkType.Enabled := not AValue;
  FText.ReadOnly := AValue;
  FAsComment.Enabled := not AValue;
  FBook.Enabled := not AValue and not FTrackingOff;
  FLater.Enabled := not AValue;
  FDiscard.Enabled := not AValue;
end;

procedure TAtlasTrackerTimeDialog.BookClick(Sender: TObject);
var
  mDialog: TAtlasTrackerTimeDialog;
begin
  if FSending or FTrackingOff then
    Exit;
  if not Item(FItem) then
  begin
    ShowNote(TAtlasStrings.Text(TAtlasTextId.TimeBookInvalid), True);
    Exit;
  end;
  // GitHub ohne Häkchen bzw. ohne Buchungsweg: nur lokal als gebucht vermerken.
  if ((FMode = TAtlasTimeBookMode.Comment) and not FAsComment.Checked) or not Assigned(FOnBook) then
  begin
    FDecision := TAtlasTimeDecision.Booked;
    ModalResult := mrOk;
    Exit;
  end;
  ShowNote(TAtlasStrings.Text(TAtlasTextId.TimeBookSending), False);
  SetBusy(True);
  mDialog := Self;
  FOnBook(FItem,
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      mDialog.BookDone(AResult);
    end);
end;

procedure TAtlasTrackerTimeDialog.BookDone(const AResult: TAtlasTrackerWriteResult);
begin
  SetBusy(False);
  if AResult.Succeeded then
  begin
    FSent := True;
    FDecision := TAtlasTimeDecision.Booked;
    FNote.Caption := '';
    ModalResult := mrOk;
    Exit;
  end;
  if Assigned(FIsTrackingOff) and FIsTrackingOff(AResult) then
  begin
    SetTrackingOff;
    Exit;
  end;
  // Kein neuer Versuch von selbst.
  ShowNote(TAtlasTrackerEndDialog.ErrorText(FKey, AResult), True);
end;

procedure TAtlasTrackerTimeDialog.DiscardClick(Sender: TObject);
begin
  if FSending then
    Exit;
  FDecision := TAtlasTimeDecision.Discarded;
  ModalResult := mrAbort;
end;

procedure TAtlasTrackerTimeDialog.DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während der Buchung nicht schließen: Das Ergebnis kommt noch an diesen Dialog.
  CanClose := not FSending;
end;

class function TAtlasTrackerTimeDialog.Execute(const AKey: string; ASeconds: Int64; ARounding: Integer;
  ADate: TDateTime; const AText: string; AMode: TAtlasTimeBookMode; const AOnBook: TAtlasTimeBookEvent;
  const APrepare: TProc<TAtlasTrackerTimeDialog>; out AItem: TAtlasTrackerWorkItem): TAtlasTimeDecision;
var
  mDialog: TAtlasTrackerTimeDialog;
begin
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, AKey, ASeconds, ARounding, ADate, AText, AMode);
  try
    mDialog.OnBook := AOnBook;
    if Assigned(APrepare) then
      APrepare(mDialog);
    mDialog.ShowModal;
    Result := mDialog.Decision;
    AItem := mDialog.BookedItem;
  finally
    mDialog.Free;
  end;
end;

end.
