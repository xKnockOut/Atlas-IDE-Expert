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
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 420;
  LabelWidth = 120;

{ TAtlasTodoFilterDialog }

constructor TAtlasTodoFilterDialog.CreateDialog(AOwner: TComponent; const AChoices: TAtlasTodoChoices;
  const AFilter: TAtlasTodoFilter);
var
  Bottom: TPanel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasStrings.Text(TAtlasTextId.TodoFilterTitle);
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  FNextTop := ScaleValue(Gap);

  FCategory := AddCombo(TAtlasStrings.Text(TAtlasTextId.TodoFilterCategory), AChoices.Categories, AFilter.Category);
  FOwner := AddCombo(TAtlasStrings.Text(TAtlasTextId.TodoFilterOwner), AChoices.Owners, AFilter.Owner);
  FUnit := AddCombo(TAtlasStrings.Text(TAtlasTextId.TodoFilterUnit), AChoices.Units, AFilter.UnitName);
  FKeyword := AddCombo(TAtlasStrings.Text(TAtlasTextId.TodoFilterKeyword), AChoices.Keywords, AFilter.Keyword);

  FIncludeDone := TCheckBox.Create(Self);
  FIncludeDone.Parent := Self;
  FIncludeDone.Caption := TAtlasStrings.Text(TAtlasTextId.TodoFilterDone);
  FIncludeDone.Checked := AFilter.IncludeDone;
  FIncludeDone.SetBounds(ScaleValue(Gap + LabelWidth), FNextTop, ClientWidth - ScaleValue(2 * Gap + LabelWidth),
    ScaleValue(20));
  FNextTop := FIncludeDone.Top + FIncludeDone.Height + ScaleValue(Gap);

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.ShowAccelChar := False;
  FHint.WordWrap := True;
  FHint.AutoSize := False;
  FHint.Caption := TAtlasStrings.Text(TAtlasTextId.TodoFilterHint);
  FHint.SetBounds(ScaleValue(Gap), FNextTop, ClientWidth - ScaleValue(2 * Gap), ScaleValue(32));
  FNextTop := FHint.Top + FHint.Height;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  // Rechts „Abbrechen“, links davon „Anzeigen“; ganz links „Zurücksetzen“.
  FCancel := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.TodoFilterCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := Bottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FOk := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.TodoFilterOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(Gap);
  FReset := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.TodoFilterReset), ResetClick);
  FReset.Anchors := [akTop, akLeft];
  FReset.Left := ScaleValue(Gap);

  ClientHeight := FNextTop + ScaleValue(Gap) + Bottom.Height;
  ActiveControl := FCategory;
end;

function TAtlasTodoFilterDialog.AddCombo(const ACaption: string; const AItems: TArray<string>;
  const AText: string): TComboBox;
var
  Prompt: TLabel;
  Item: string;
begin
  Prompt := TLabel.Create(Self);
  Prompt.Parent := Self;
  Prompt.ShowAccelChar := False;
  Prompt.Caption := ACaption;
  Prompt.SetBounds(ScaleValue(Gap), FNextTop + ScaleValue(3), ScaleValue(LabelWidth - Gap), ScaleValue(18));

  Result := TComboBox.Create(Self);
  Result.Parent := Self;
  // Auswahl aus der letzten Liste oder freier Text (etwa eine Unit, die gerade keine Einträge hat).
  Result.Style := csDropDown;
  Result.AutoComplete := True;
  Result.SetBounds(ScaleValue(Gap + LabelWidth), FNextTop, ClientWidth - ScaleValue(2 * Gap + LabelWidth),
    ScaleValue(23));
  for Item in AItems do
    Result.Items.Add(Item);
  Result.Text := AText;
  Prompt.FocusControl := Result;
  FNextTop := Result.Top + Result.Height + ScaleValue(Gap);
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
    Result.Width := ScaleValue(90);
  Result.Top := ScaleValue(Gap);
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
  Dialog: TAtlasTodoFilterDialog;
begin
  Dialog := TAtlasTodoFilterDialog.CreateDialog(nil, AChoices, AFilter);
  try
    Result := Dialog.ShowModal = mrOk;
    if Result then
      AFilter := Dialog.Filter;
  finally
    Dialog.Free;
  end;
end;

end.
