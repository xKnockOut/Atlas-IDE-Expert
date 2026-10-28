unit Atlas.UI.Tracker.TimeList;

// Dialog „Offene Zeitbuchungen“ (#1267), ohne Open Tools API: noch nicht
// gebuchte Zeit je Issue („ATL-123 · 1 h 25 min · 27.10.2026 – 28.10.2026“),
// zuletzt bearbeitete zuerst. „Buchen …“ bzw. „Verwerfen …“ gelten für die
// gewählte Zeile; der Aufrufer zeigt danach den Buchungsdialog bzw. fragt
// vor dem Verwerfen. Die Liste wird erst mit Fenster gefüllt (TListBox).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.TimeLog;

type
{$SCOPEDENUMS ON}
  TAtlasTimeListAction = (Close, Book, Discard);
{$SCOPEDENUMS OFF}

  TAtlasTrackerTimeListDialog = class(TForm)
  public const
    DialogWidth = 460;
    ListHeight = 200;
  private
    FItems: TArray<TAtlasTimeOpen>;
    FList: TListBox;
    FEmpty: TLabel;
    FBook: TButton;
    FDiscard: TButton;
    FClose: TButton;
    FAction: TAtlasTimeListAction;
    FChosen: Integer;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
    procedure BookClick(Sender: TObject);
    procedure DiscardClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure UpdateButtons;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const AItems: TArray<TAtlasTimeOpen>);
    /// <summary>Gewählte Zeile; -1 ohne.</summary>
    function Selected: Integer;
    /// <summary>Zeile der Liste: Kennung, Dauer und Tage.</summary>
    class function RowText(const AItem: TAtlasTimeOpen): string; static;
    /// <summary>Modal zeigen; Book bzw. Discard mit der gewählten Zeile in AIndex.</summary>
    class function Execute(const AItems: TArray<TAtlasTimeOpen>; out AIndex: Integer): TAtlasTimeListAction; static;
    property Action: TAtlasTimeListAction read FAction;
    /// <summary>Zeile, für die Buchen bzw. Verwerfen gewählt wurde; -1 ohne.</summary>
    property Chosen: Integer read FChosen;
    property List: TListBox read FList;
    property EmptyLabel: TLabel read FEmpty;
    property BookButton: TButton read FBook;
    property DiscardButton: TButton read FDiscard;
    property CloseButton: TButton read FClose;
  end;

implementation

uses
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Strings;

const
  Gap = 8;

{ TAtlasTrackerTimeListDialog }

constructor TAtlasTrackerTimeListDialog.CreateDialog(AOwner: TComponent; const AItems: TArray<TAtlasTimeOpen>);
var
  mButtons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  FItems := Copy(AItems);
  FAction := TAtlasTimeListAction.Close;
  FChosen := -1;
  Caption := TAtlasStrings.Text(TAtlasTextId.TimeOpenCaption);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);

  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alTop;
  FEmpty.AlignWithMargins := True;
  FEmpty.Margins.SetBounds(Gap, Gap, Gap, 0);
  FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.TimeOpenEmpty);
  FEmpty.Visible := Length(FItems) = 0;

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alTop;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, Gap, Gap, 0);
  FList.Top := FEmpty.Top + FEmpty.Height + 1;
  FList.Height := ScaleValue(ListHeight);
  FList.OnClick := ListClick;
  FList.OnDblClick := BookClick;

  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(Gap, Gap, Gap, Gap);
  mButtons.Top := FList.Top + FList.Height + 1;
  FBook := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TimeOpenBook));
  FBook.OnClick := BookClick;
  FBook.Default := True;
  FDiscard := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TimeOpenDiscard));
  FDiscard.OnClick := DiscardClick;
  FClose := AddButton(mButtons, TAtlasStrings.Text(TAtlasTextId.TimeOpenClose));
  FClose.ModalResult := mrCancel;
  FClose.Cancel := True;
  ClientHeight := mButtons.Top + mButtons.Height + Gap;
  UpdateButtons;
end;

function TAtlasTrackerTimeListDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, Gap, Gap div 2);
end;

procedure TAtlasTrackerTimeListDialog.DoShow;
var
  mItem: TAtlasTimeOpen;
begin
  // TListBox.Items braucht das Fenster: erst beim Zeigen füllen.
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mItem in FItems do
      FList.Items.Add(RowText(mItem));
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
    FList.ItemIndex := 0;
  UpdateButtons;
  inherited;
end;

function TAtlasTrackerTimeListDialog.Selected: Integer;
begin
  Result := -1;
  if FList.HandleAllocated and (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FItems)) then
    Result := FList.ItemIndex;
end;

procedure TAtlasTrackerTimeListDialog.UpdateButtons;
begin
  FBook.Enabled := Selected >= 0;
  FDiscard.Enabled := Selected >= 0;
end;

procedure TAtlasTrackerTimeListDialog.ListClick(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TAtlasTrackerTimeListDialog.BookClick(Sender: TObject);
begin
  if Selected < 0 then
    Exit;
  FAction := TAtlasTimeListAction.Book;
  FChosen := Selected;
  ModalResult := mrOk;
end;

procedure TAtlasTrackerTimeListDialog.DiscardClick(Sender: TObject);
begin
  if Selected < 0 then
    Exit;
  FAction := TAtlasTimeListAction.Discard;
  FChosen := Selected;
  ModalResult := mrOk;
end;

class function TAtlasTrackerTimeListDialog.RowText(const AItem: TAtlasTimeOpen): string;
var
  mDays: string;
begin
  mDays := DateToStr(AItem.FirstDay);
  if AItem.LastDay <> AItem.FirstDay then
    mDays := mDays + ' – ' + DateToStr(AItem.LastDay);
  Result := TAtlasStrings.Fmt(TAtlasTextId.TimeOpenRow, [AItem.Issue.Key,
    TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(AItem.Seconds, 1)), mDays]);
end;

class function TAtlasTrackerTimeListDialog.Execute(const AItems: TArray<TAtlasTimeOpen>;
  out AIndex: Integer): TAtlasTimeListAction;
var
  mDialog: TAtlasTrackerTimeListDialog;
begin
  mDialog := TAtlasTrackerTimeListDialog.CreateDialog(nil, AItems);
  try
    mDialog.ShowModal;
    Result := mDialog.Action;
    AIndex := mDialog.Chosen;
    if AIndex < 0 then
      Result := TAtlasTimeListAction.Close;
  finally
    mDialog.Free;
  end;
end;

end.
