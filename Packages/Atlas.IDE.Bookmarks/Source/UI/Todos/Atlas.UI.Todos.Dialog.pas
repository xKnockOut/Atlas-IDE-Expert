unit Atlas.UI.Todos.Dialog;

// Filter der TODO-Liste (#68): Kategorie (-c), Person (-o), Unit und Marke
// als Auswahlfelder, in die man auch tippen kann (Vorschläge aus der letzten
// Liste), dazu „Erledigte zeigen (DONE)“. „Anzeigen“ übernimmt, Enter auch;
// „Zurücksetzen“ leert alle Felder; Esc bricht ab. Reine VCL; die Abfrage
// mit dem Filter macht der Aufrufer über den Filter des Servers.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Projects.Todos;

type
  TAtlasTodoFilterDialog = class(TForm)
  private
    FCategory: TComboBox;
    FOwner: TComboBox;
    FUnit: TComboBox;
    FKeyword: TComboBox;
    FIncludeDone: TCheckBox;
    FHint: TLabel;
    FOk: TButton;
    FCancel: TButton;
    FReset: TButton;
    FNextTop: Integer;
    function AddCombo(const ACaption: string; const AItems: TArray<string>; const AText: string): TComboBox;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const AChoices: TAtlasTodoChoices; const AFilter: TAtlasTodoFilter);
    /// <summary>Filter aus den Feldern, ohne Leerraum am Rand.</summary>
    function Filter: TAtlasTodoFilter;
    /// <summary>Zeigt den Dialog modal; True mit dem neuen Filter in AFilter, False bei Abbrechen.</summary>
    class function Execute(const AChoices: TAtlasTodoChoices; var AFilter: TAtlasTodoFilter): Boolean; static;
    property CategoryBox: TComboBox read FCategory;
    property OwnerBox: TComboBox read FOwner;
    property UnitBox: TComboBox read FUnit;
    property KeywordBox: TComboBox read FKeyword;
    property IncludeDoneCheck: TCheckBox read FIncludeDone;
    property OkButton: TButton read FOk;
    property CancelButton: TButton read FCancel;
    property ResetButton: TButton read FReset;
  end;

implementation

uses
  Atlas.UI.Bookmarks.Strings;

const
  cGap = 8;
  cDialogWidth = 420;
  cLabelWidth = 120;

{ TAtlasTodoFilterDialog }

constructor TAtlasTodoFilterDialog.CreateDialog(AOwner: TComponent; const AChoices: TAtlasTodoChoices;
  const AFilter: TAtlasTodoFilter);
var
  mBottom: TPanel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterTitle);
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  FNextTop := ScaleValue(cGap);

  FCategory := AddCombo(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterCategory), AChoices.Categories,
    AFilter.Category);
  FOwner := AddCombo(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterOwner), AChoices.Owners,
    AFilter.Owner);
  FUnit := AddCombo(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterUnit), AChoices.Units,
    AFilter.UnitName);
  FKeyword := AddCombo(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterKeyword), AChoices.Keywords,
    AFilter.Keyword);

  FIncludeDone := TCheckBox.Create(Self);
  FIncludeDone.Parent := Self;
  FIncludeDone.Caption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterDone);
  FIncludeDone.Checked := AFilter.IncludeDone;
  FIncludeDone.SetBounds(ScaleValue(cGap + cLabelWidth), FNextTop, ClientWidth - ScaleValue(2 * cGap + cLabelWidth),
    ScaleValue(20));
  FNextTop := FIncludeDone.Top + FIncludeDone.Height + ScaleValue(cGap);

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.ShowAccelChar := False;
  FHint.WordWrap := True;
  FHint.AutoSize := False;
  FHint.Caption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterHint);
  FHint.SetBounds(ScaleValue(cGap), FNextTop, ClientWidth - ScaleValue(2 * cGap), ScaleValue(32));
  FNextTop := FHint.Top + FHint.Height;

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  // Rechts „Abbrechen“, links davon „Anzeigen“; ganz links „Zurücksetzen“.
  FCancel := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(cGap);
  FOk := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(cGap);
  FReset := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoFilterReset), ResetClick);
  FReset.Anchors := [akTop, akLeft];
  FReset.Left := ScaleValue(cGap);

  ClientHeight := FNextTop + ScaleValue(cGap) + mBottom.Height;
  ActiveControl := FCategory;
end;

function TAtlasTodoFilterDialog.AddCombo(const ACaption: string; const AItems: TArray<string>;
  const AText: string): TComboBox;
var
  mPrompt: TLabel;
  mItem: string;
begin
  mPrompt := TLabel.Create(Self);
  mPrompt.Parent := Self;
  mPrompt.ShowAccelChar := False;
  mPrompt.Caption := ACaption;
  mPrompt.SetBounds(ScaleValue(cGap), FNextTop + ScaleValue(3), ScaleValue(cLabelWidth - cGap), ScaleValue(18));

  Result := TComboBox.Create(Self);
  Result.Parent := Self;
  // Auswahl aus der letzten Liste oder freier Text (etwa eine Unit, die gerade keine Einträge hat).
  Result.Style := csDropDown;
  Result.AutoComplete := True;
  Result.SetBounds(ScaleValue(cGap + cLabelWidth), FNextTop, ClientWidth - ScaleValue(2 * cGap + cLabelWidth),
    ScaleValue(23));
  Result.Items.BeginUpdate;
  try
    for mItem in AItems do
    begin
      Result.Items.Add(mItem);
    end;
  finally
    Result.Items.EndUpdate;
  end;
  Result.Text := AText;
  mPrompt.FocusControl := Result;
  FNextTop := Result.Top + Result.Height + ScaleValue(cGap);
end;

function TAtlasTodoFilterDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  if Result.Width < ScaleValue(90) then
  begin
    Result.Width := ScaleValue(90);
  end;
  Result.Top := ScaleValue(cGap);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

function TAtlasTodoFilterDialog.Filter: TAtlasTodoFilter;
begin
  Result := Default(TAtlasTodoFilter);
  Result.Category := FCategory.Text;
  Result.Owner := FOwner.Text;
  Result.UnitName := FUnit.Text;
  Result.Keyword := FKeyword.Text;
  Result.IncludeDone := FIncludeDone.Checked;
  Result := Result.Trimmed;
end;

procedure TAtlasTodoFilterDialog.OkClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TAtlasTodoFilterDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TAtlasTodoFilterDialog.ResetClick(Sender: TObject);
begin
  FCategory.Text := '';
  FOwner.Text := '';
  FUnit.Text := '';
  FKeyword.Text := '';
  FIncludeDone.Checked := False;
  ActiveControl := FCategory;
end;

class function TAtlasTodoFilterDialog.Execute(const AChoices: TAtlasTodoChoices;
  var AFilter: TAtlasTodoFilter): Boolean;
var
  mDialog: TAtlasTodoFilterDialog;
begin
  mDialog := TAtlasTodoFilterDialog.CreateDialog(nil, AChoices, AFilter);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AFilter := mDialog.Filter;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
