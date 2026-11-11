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
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Foundation.Dialog;

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

  /// <summary>Was gebucht werden soll: ASeconds erfasste Zeit, Rounding issues.timeRounding, Date Tag der
  /// Buchung, Text Vorlage der Beschreibung.</summary>
  TAtlasTimeRequest = record
    Key: string;
    Seconds: Int64;
    Rounding: Integer;
    Date: TDateTime;
    Text: string;
    Mode: TAtlasTimeBookMode;
    class function Create(const AKey: string; ASeconds: Int64; ARounding: Integer; ADate: TDateTime;
      const AText: string; AMode: TAtlasTimeBookMode): TAtlasTimeRequest; static;
  end;

  /// <summary>Die Steuerelemente des Dialogs (für Tests und Nachladen).</summary>
  TAtlasTimeDialogParts = record
    Question: TLabel;
    Duration: TEdit;
    WorkType: TAtlasValueBox;
    Text: TMemo;
    AsComment: TCheckBox;
    Note: TLabel;
    Book: TButton;
    Later: TButton;
    Discard: TButton;
  end;

  TAtlasTrackerTimeDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 480;
    cTextHeight = 90;
  private
    FRequest: TAtlasTimeRequest;
    FParts: TAtlasTimeDialogParts;
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
    procedure AddDuration(AMinutes: Integer);
    procedure AddKind;
    function AddText: TPanel;
    procedure AddButtons(ATop: Integer);
    procedure BookClick(Sender: TObject);
    procedure DiscardClick(Sender: TObject);
    procedure DurationChange(Sender: TObject);
    procedure DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure SetBusy(AValue: Boolean);
    procedure ShowNote(const AText: string; AError: Boolean);
  public
    constructor CreateDialog(AOwner: TComponent; const ARequest: TAtlasTimeRequest);
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
    class function Execute(const ARequest: TAtlasTimeRequest; const AOnBook: TAtlasTimeBookEvent;
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
    property Parts: TAtlasTimeDialogParts read FParts;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.Strings,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

const
  cGap = 8;
  cFieldLeft = 120;

{ TAtlasTimeRequest }

class function TAtlasTimeRequest.Create(const AKey: string; ASeconds: Int64; ARounding: Integer; ADate: TDateTime;
  const AText: string; AMode: TAtlasTimeBookMode): TAtlasTimeRequest;
begin
  Result.Key := AKey;
  Result.Seconds := ASeconds;
  Result.Rounding := ARounding;
  Result.Date := ADate;
  Result.Text := AText;
  Result.Mode := AMode;
end;

{ TAtlasTrackerTimeDialog }

constructor TAtlasTrackerTimeDialog.CreateDialog(AOwner: TComponent; const ARequest: TAtlasTimeRequest);
var
  mRow: TPanel;
  mMinutes: Integer;
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FRequest := ARequest;
  FDecision := TAtlasTimeDecision.Later;
  FItem := TAtlasTrackerWorkItem.Create(0, ARequest.Date, '', '');
  Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookCaption);
  OnCloseQuery := DialogCloseQuery;
  mMinutes := TAtlasTimeRounding.Minutes(ARequest.Seconds, ARequest.Rounding);

  mRow := AddRow(22);
  FParts.Question := AddLabel(mRow, QuestionText(ARequest.Key, mMinutes));
  FParts.Question.Font.Style := [fsBold];
  AddDuration(mMinutes);
  AddKind;
  mRow := AddText;
  AddButtons(mRow.Top + mRow.Height + 1);
  ActiveControl := FParts.Duration;
end;

procedure TAtlasTrackerTimeDialog.AddDuration(AMinutes: Integer);
var
  mRow: TPanel;
begin
  mRow := AddRow(26);
  AddLabel(mRow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookDuration));
  FParts.Duration := TEdit.Create(Self);
  FParts.Duration.Parent := mRow;
  FParts.Duration.Left := ScaleValue(cFieldLeft);
  FParts.Duration.Top := 0;
  FParts.Duration.Width := ScaleValue(80);
  FParts.Duration.Text := TAtlasTimeRounding.ClockText(Int64(AMinutes) * 60);
  FParts.Duration.OnChange := DurationChange;
end;

/// <summary>Arbeitstyp (YouTrack) bzw. Häkchen „Als Kommentar senden“ (GitHub, Vorgabe aus).</summary>
procedure TAtlasTrackerTimeDialog.AddKind;
var
  mRow: TPanel;
begin
  FParts.WorkType := TAtlasValueBox.Create(Self);
  FParts.AsComment := TCheckBox.Create(Self);
  mRow := AddRow(26);
  if FRequest.Mode = TAtlasTimeBookMode.WorkItem then
  begin
    AddLabel(mRow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookWorkType));
    FParts.WorkType.Parent := mRow;
    FParts.WorkType.Left := ScaleValue(cFieldLeft);
    FParts.WorkType.Top := 0;
    FParts.WorkType.Width := ScaleValue(240);
  end
  else
  begin
    FParts.AsComment.Parent := mRow;
    FParts.AsComment.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookAsComment);
    FParts.AsComment.Left := 0;
    FParts.AsComment.Top := ScaleValue(3);
    FParts.AsComment.Width := ScaleValue(cDialogWidth - 2 * cGap);
    FParts.AsComment.Checked := False;
  end;
end;

/// <summary>Beschreibung und darunter die Zeile für Hinweise; liefert die Hinweiszeile.</summary>
function TAtlasTrackerTimeDialog.AddText: TPanel;
var
  mRow: TPanel;
begin
  mRow := AddRow(20);
  AddLabel(mRow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookText));
  FParts.Text := TMemo.Create(Self);
  FParts.Text.Parent := Self;
  FParts.Text.Align := alTop;
  FParts.Text.AlignWithMargins := True;
  FParts.Text.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  FParts.Text.Top := mRow.Top + mRow.Height + 1;
  FParts.Text.Height := ScaleValue(cTextHeight);
  FParts.Text.ScrollBars := ssVertical;
  FParts.Text.WantReturns := True;
  FParts.Text.Text := AdjustLineBreaks(FRequest.Text, tlbsCRLF);

  Result := AddRow(34);
  Result.Top := FParts.Text.Top + FParts.Text.Height + 1;
  FParts.Note := TLabel.Create(Self);
  FParts.Note.Parent := Result;
  FParts.Note.Align := alClient;
  FParts.Note.WordWrap := True;
  FParts.Note.Caption := '';
  if FRequest.Mode = TAtlasTimeBookMode.Comment then
  begin
    ShowNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookLocalOnly), False);
  end;
end;

procedure TAtlasTrackerTimeDialog.AddButtons(ATop: Integer);
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
  FParts.Book := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookBook));
  FParts.Book.OnClick := BookClick;
  FParts.Book.Default := True;
  FParts.Later := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookLater));
  FParts.Later.ModalResult := mrCancel;
  FParts.Later.Cancel := True;
  FParts.Discard := AddButton(mButtons, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookDiscard));
  FParts.Discard.OnClick := DiscardClick;
  ClientHeight := mButtons.Top + mButtons.Height + ScaleValue(cGap);
end;

function TAtlasTrackerTimeDialog.AddRow(AHeight: Integer): TPanel;
var
  mTop: Integer;
  mIndex: Integer;
begin
  // Unter das bisher unterste Element (alTop stapelt nach Top).
  mTop := 0;
  for mIndex := 0 to ControlCount - 1 do
  begin
    if Controls[mIndex].Top + Controls[mIndex].Height + 1 > mTop then
    begin
      mTop := Controls[mIndex].Top + Controls[mIndex].Height + 1;
    end;
  end;
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
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
  Result.Margins.SetBounds(0, 0, cGap, cGap div 2);
end;

class function TAtlasTrackerTimeDialog.QuestionText(const AKey: string; AMinutes: Integer): string;
begin
  Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeBookQuestion,
    [TAtlasTrackerWorkflow.DurationText(AMinutes), AKey]);
end;

procedure TAtlasTrackerTimeDialog.ShowNote(const AText: string; AError: Boolean);
begin
  // Mit seFont übergeht der Stil Font.Color: Fehler zeichnen ihre Farbe selbst.
  if AError then
  begin
    FParts.Note.StyleElements := FParts.Note.StyleElements - [seFont];
    FParts.Note.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  end
  else
  begin
    FParts.Note.StyleElements := FParts.Note.StyleElements + [seFont];
    FParts.Note.Font.Color := clWindowText;
  end;
  FParts.Note.Caption := AText;
end;

procedure TAtlasTrackerTimeDialog.SetWorkTypes(const ATypes: TArray<string>);
begin
  FParts.WorkType.SetValues(ATypes);
end;

procedure TAtlasTrackerTimeDialog.SetTrackingOff;
begin
  FTrackingOff := True;
  FParts.Book.Enabled := False;
  FParts.Book.Default := False;
  FParts.Later.Default := True;
  ShowNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookOff), False);
end;

procedure TAtlasTrackerTimeDialog.DurationChange(Sender: TObject);
var
  mMinutes: Integer;
begin
  // Die Frage folgt der eingegebenen Dauer.
  if TAtlasTimeRounding.ParseDuration(FParts.Duration.Text, mMinutes) then
  begin
    FParts.Question.Caption := QuestionText(FRequest.Key, mMinutes);
  end;
end;

function TAtlasTrackerTimeDialog.Item(out AItem: TAtlasTrackerWorkItem): Boolean;
var
  mMinutes: Integer;
  mType: string;
begin
  Result := TAtlasTimeRounding.ParseDuration(FParts.Duration.Text, mMinutes);
  mType := '';
  if FRequest.Mode = TAtlasTimeBookMode.WorkItem then
  begin
    mType := FParts.WorkType.Value;
  end;
  AItem := TAtlasTrackerWorkItem.Create(mMinutes, FRequest.Date, mType,
    Trim(StringReplace(FParts.Text.Text, #13#10, #10, [rfReplaceAll])));
end;

procedure TAtlasTrackerTimeDialog.SetBusy(AValue: Boolean);
begin
  FSending := AValue;
  FParts.Duration.ReadOnly := AValue;
  FParts.WorkType.Enabled := not AValue;
  FParts.Text.ReadOnly := AValue;
  FParts.AsComment.Enabled := not AValue;
  FParts.Book.Enabled := not AValue and not FTrackingOff;
  FParts.Later.Enabled := not AValue;
  FParts.Discard.Enabled := not AValue;
end;

procedure TAtlasTrackerTimeDialog.BookClick(Sender: TObject);
var
  mDialog: TAtlasTrackerTimeDialog;
begin
  if FSending or FTrackingOff then
  begin
    Exit;
  end;
  if not Item(FItem) then
  begin
    ShowNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookInvalid), True);
    Exit;
  end;
  // GitHub ohne Häkchen bzw. ohne Buchungsweg: nur lokal als gebucht vermerken.
  if ((FRequest.Mode = TAtlasTimeBookMode.Comment) and not FParts.AsComment.Checked) or not Assigned(FOnBook) then
  begin
    FDecision := TAtlasTimeDecision.Booked;
    ModalResult := mrOk;
    Exit;
  end;
  ShowNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeBookSending), False);
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
    FParts.Note.Caption := '';
    ModalResult := mrOk;
    Exit;
  end;
  if Assigned(FIsTrackingOff) and FIsTrackingOff(AResult) then
  begin
    SetTrackingOff;
    Exit;
  end;
  // Kein neuer Versuch von selbst.
  ShowNote(TAtlasTrackerEndDialog.ErrorText(FRequest.Key, AResult), True);
end;

procedure TAtlasTrackerTimeDialog.DiscardClick(Sender: TObject);
begin
  if FSending then
  begin
    Exit;
  end;
  FDecision := TAtlasTimeDecision.Discarded;
  ModalResult := mrAbort;
end;

procedure TAtlasTrackerTimeDialog.DialogCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während der Buchung nicht schließen: Das Ergebnis kommt noch an diesen Dialog.
  CanClose := not FSending;
end;

class function TAtlasTrackerTimeDialog.Execute(const ARequest: TAtlasTimeRequest; const AOnBook: TAtlasTimeBookEvent;
  const APrepare: TProc<TAtlasTrackerTimeDialog>; out AItem: TAtlasTrackerWorkItem): TAtlasTimeDecision;
var
  mDialog: TAtlasTrackerTimeDialog;
begin
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, ARequest);
  try
    mDialog.OnBook := AOnBook;
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    mDialog.ShowModal;
    Result := mDialog.Decision;
    AItem := mDialog.BookedItem;
  finally
    mDialog.Free;
  end;
end;

end.
