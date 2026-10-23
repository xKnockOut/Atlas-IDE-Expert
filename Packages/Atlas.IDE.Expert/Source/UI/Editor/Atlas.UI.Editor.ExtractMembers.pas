unit Atlas.UI.Editor.ExtractMembers;

// Dialog „Mitglieder herauslösen“ für „Interface herauslösen“ (#664) und
// „Basisklasse herauslösen“ (#713): Name des neuen Typs, Ziel-Unit (die Unit
// der Klasse, eine Unit des Projekts oder ein neuer Name), Liste der
// Mitglieder mit Häkchen, Art, Sichtbarkeit und Hinweis (gesperrte Einträge
// grau mit Grund), Knöpfe „Alle“ und „Keine“ und die Hinweise des Servers.
// Fehler zeigt die Zeile über den Knöpfen; „Vorschau …“ geht erst ohne
// Fehler. Reine VCL; das Modell ist TAtlasClassExtractionModel.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Editor.ClassExtraction;

type
  TAtlasExtractMembersDialog = class(TForm)
  private
    FModel: TAtlasClassExtractionModel;
    FName: TEdit;
    FUnit: TComboBox;
    FList: TListView;
    FAll: TButton;
    FNone: TButton;
    FError: TLabel;
    FNotes: TLabel;
    FOk: TButton;
    FCancel: TButton;
    FUpdating: Boolean;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabeled(AParent: TWinControl; const ACaption: string; ATop: Integer; AControl: TWinControl): Integer;
    function OwnUnitCaption: string;
    procedure FillList;
    procedure Refresh;
    procedure NameChange(Sender: TObject);
    procedure UnitChange(Sender: TObject);
    procedure AllClick(Sender: TObject);
    procedure NoneClick(Sender: TObject);
    procedure ListChecked(Sender: TObject; Item: TListItem);
    procedure ListCustomDraw(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure OkClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; AModel: TAtlasClassExtractionModel; const ATitle: string);
    /// <summary>True, wenn der Benutzer „Vorschau …“ gewählt hat; das Modell enthält dann Name, Ziel und
    /// Auswahl.</summary>
    class function Execute(AModel: TAtlasClassExtractionModel; const ATitle: string): Boolean; static;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 680;
  DialogHeight = 480;

{ TAtlasExtractMembersDialog }

constructor TAtlasExtractMembersDialog.CreateDialog(AOwner: TComponent; AModel: TAtlasClassExtractionModel;
  const ATitle: string);
var
  Bottom, Header, Right: TPanel;
  Column: TListColumn;
  Row: Integer;
  Notes, Note: string;
begin
  inherited CreateNew(AOwner);
  FModel := AModel;
  Caption := ATitle;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  ClientHeight := ScaleValue(DialogHeight);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  FCancel := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.ExtractMembersCancel), nil);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.Left := Bottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FOk := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.ExtractMembersPreview), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(Gap);

  // Hinweise des Servers und Fehler über den Knöpfen.
  FNotes := TLabel.Create(Self);
  FNotes.Parent := Self;
  FNotes.Align := alBottom;
  FNotes.AlignWithMargins := True;
  FNotes.Margins.SetBounds(Gap, 0, Gap, Gap div 2);
  FNotes.WordWrap := True;
  FNotes.ShowAccelChar := False;
  Notes := '';
  for Note in AModel.Notes do
  begin
    if Notes <> '' then
      Notes := Notes + sLineBreak;
    Notes := Notes + Note;
  end;
  FNotes.Caption := Notes;
  FError := TLabel.Create(Self);
  FError.Parent := Self;
  FError.Align := alBottom;
  FError.AlignWithMargins := True;
  FError.Margins.SetBounds(Gap, Gap div 2, Gap, Gap div 2);
  FError.WordWrap := True;
  FError.ShowAccelChar := False;
  FError.Font.Color := clRed;

  // Name und Ziel oben.
  Header := TPanel.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := ScaleValue(64);
  Header.BevelOuter := bvNone;
  FName := TEdit.Create(Self);
  FUnit := TComboBox.Create(Self);
  Row := ScaleValue(Gap);
  Row := AddLabeled(Header, TAtlasStrings.Text(TAtlasTextId.ExtractMembersName), Row, FName);
  AddLabeled(Header, TAtlasStrings.Text(TAtlasTextId.ExtractMembersUnit), Row, FUnit);
  FName.Text := AModel.Name;
  FName.OnChange := NameChange;
  // Eingabe erlaubt: Ein neuer Unit-Name legt die Unit an.
  FUnit.Style := csDropDown;
  FUnit.OnChange := UnitChange;

  // Knöpfe rechts neben der Liste.
  Right := TPanel.Create(Self);
  Right.Parent := Self;
  Right.Align := alRight;
  Right.Width := ScaleValue(100);
  Right.BevelOuter := bvNone;
  FAll := AddButton(Right, TAtlasStrings.Text(TAtlasTextId.ExtractMembersAll), AllClick);
  FNone := AddButton(Right, TAtlasStrings.Text(TAtlasTextId.ExtractMembersNone), NoneClick);
  FAll.Top := ScaleValue(Gap);
  FNone.Top := FAll.Top + FAll.Height + ScaleValue(4);
  for Row := 0 to Right.ControlCount - 1 do
  begin
    Right.Controls[Row].Left := ScaleValue(Gap);
    Right.Controls[Row].Width := Right.Width - ScaleValue(2 * Gap);
    Right.Controls[Row].Anchors := [akLeft, akTop];
  end;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, Gap, 0, 0);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.Checkboxes := True;
  FList.OnItemChecked := ListChecked;
  FList.OnCustomDrawItem := ListCustomDraw;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ExtractMembersColMember);
  Column.Width := ScaleValue(260);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ExtractMembersColKind);
  Column.Width := ScaleValue(70);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ExtractMembersColVisibility);
  Column.Width := ScaleValue(90);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ExtractMembersColReason);
  Column.Width := ScaleValue(140);
  ActiveControl := FName;
end;

function TAtlasExtractMembersDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Result.Width := ScaleValue(100);
  Result.Top := ScaleValue(Gap);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

function TAtlasExtractMembersDialog.AddLabeled(AParent: TWinControl; const ACaption: string; ATop: Integer;
  AControl: TWinControl): Integer;
var
  Caption: TLabel;
begin
  Caption := TLabel.Create(Self);
  Caption.Parent := AParent;
  Caption.Caption := ACaption;
  Caption.SetBounds(ScaleValue(Gap), ATop + ScaleValue(3), ScaleValue(110), ScaleValue(20));
  Caption.FocusControl := AControl;
  AControl.Parent := AParent;
  AControl.SetBounds(ScaleValue(120), ATop, ScaleValue(DialogWidth - 120 - Gap), ScaleValue(23));
  AControl.Anchors := [akLeft, akTop, akRight];
  Result := ATop + ScaleValue(28);
end;

function TAtlasExtractMembersDialog.OwnUnitCaption: string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractMembersOwnUnit, [FModel.OwnUnit]);
end;

procedure TAtlasExtractMembersDialog.DoShow;
var
  Name: string;
begin
  inherited;
  // Liste und Auswahlfeld brauchen ein Fenster: erst hier füllen.
  if FUnit.Items.Count = 0 then
  begin
    FUpdating := True;
    try
      FUnit.Items.Add(OwnUnitCaption);
      for Name in FModel.Units do
        if not SameText(Name, FModel.OwnUnit) then
          FUnit.Items.Add(Name);
      FUnit.ItemIndex := 0;
    finally
      FUpdating := False;
    end;
    FillList;
  end;
  FName.SelectAll;
end;

procedure TAtlasExtractMembersDialog.FillList;
var
  Index: Integer;
  Item: TListItem;
  Member: TAtlasExtractionMember;
begin
  FUpdating := True;
  try
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      for Index := 0 to FModel.Count - 1 do
      begin
        Member := FModel[Index];
        Item := FList.Items.Add;
        Item.Caption := Member.Display;
        if Member.Kind = 'property' then
          Item.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.ExtractMembersProperty))
        else
          Item.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.ExtractMembersMethod));
        Item.SubItems.Add(Member.Visibility);
        Item.SubItems.Add(Member.Reason);
        Item.Checked := Member.Checked;
      end;
    finally
      FList.Items.EndUpdate;
    end;
  finally
    FUpdating := False;
  end;
  Refresh;
end;

/// <summary>Meldung zum Fehler der Eingabe in der Sprache der Oberfläche; '' ohne Fehler.</summary>
function ProblemText(AProblem: TAtlasExtractionProblem; const ASubject: string): string;
begin
  case AProblem of
    TAtlasExtractionProblem.BadName:
      Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractMembersBadName, [ASubject]);
    TAtlasExtractionProblem.SameName:
      Result := TAtlasStrings.Text(TAtlasTextId.ExtractMembersSameName);
    TAtlasExtractionProblem.NoMembers:
      Result := TAtlasStrings.Text(TAtlasTextId.ExtractMembersNoMembers);
    TAtlasExtractionProblem.BadUnit:
      Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractMembersBadUnit, [ASubject]);
  else
    Result := '';
  end;
end;

procedure TAtlasExtractMembersDialog.Refresh;
var
  Problem: TAtlasExtractionProblem;
  Subject: string;
begin
  Problem := FModel.Validate(Subject);
  FError.Caption := ProblemText(Problem, Subject);
  FOk.Enabled := Problem = TAtlasExtractionProblem.None;
end;

procedure TAtlasExtractMembersDialog.NameChange(Sender: TObject);
begin
  FModel.Name := FName.Text;
  Refresh;
end;

procedure TAtlasExtractMembersDialog.UnitChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  // Erster Eintrag = Unit der Klasse.
  if (FUnit.ItemIndex = 0) or (FUnit.Text = OwnUnitCaption) then
    FModel.TargetUnit := ''
  else
    FModel.TargetUnit := FUnit.Text;
  Refresh;
end;

procedure TAtlasExtractMembersDialog.AllClick(Sender: TObject);
begin
  FModel.CheckAll(True);
  FillList;
end;

procedure TAtlasExtractMembersDialog.NoneClick(Sender: TObject);
begin
  FModel.CheckAll(False);
  FillList;
end;

procedure TAtlasExtractMembersDialog.ListChecked(Sender: TObject; Item: TListItem);
begin
  if FUpdating or (Item = nil) then
    Exit;
  FModel.SetChecked(Item.Index, Item.Checked);
  // Gesperrte Einträge springen auf den Stand des Modells zurück.
  if Item.Checked <> FModel[Item.Index].Checked then
  begin
    FUpdating := True;
    try
      Item.Checked := FModel[Item.Index].Checked;
    finally
      FUpdating := False;
    end;
  end;
  Refresh;
end;

procedure TAtlasExtractMembersDialog.ListCustomDraw(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  if (Item <> nil) and (Item.Index < FModel.Count) and not FModel[Item.Index].Enabled then
    Sender.Canvas.Font.Color := clGrayText;
end;

procedure TAtlasExtractMembersDialog.OkClick(Sender: TObject);
begin
  if FModel.Validate = TAtlasExtractionProblem.None then
    ModalResult := mrOk;
end;

class function TAtlasExtractMembersDialog.Execute(AModel: TAtlasClassExtractionModel; const ATitle: string): Boolean;
var
  Dialog: TAtlasExtractMembersDialog;
begin
  Dialog := TAtlasExtractMembersDialog.CreateDialog(nil, AModel, ATitle);
  try
    Result := Dialog.ShowModal = mrOk;
  finally
    Dialog.Free;
  end;
end;

end.
