unit Atlas.UI.Editor.ExtractMembers;

// Dialog „Mitglieder herauslösen“ für „Interface herauslösen“ (#664) und
// „Basisklasse herauslösen“ (#713): Name des neuen Typs, Ziel-Unit (die Unit
// der Klasse, eine Unit des Projekts oder ein neuer Name), Liste der
// Mitglieder mit Häkchen, Art, Sichtbarkeit und Hinweis (gesperrte Einträge
// grau mit Grund), Knöpfe „Alle“ und „Keine“ und die Hinweise des Servers.
// Für die Basisklasse zusätzlich „Abhängigkeiten“ (hakt an, was die gewählten
// Mitglieder benutzen) und „Nur abstrakt“ für die markierte Methode; beides
// erscheint nur, wenn das Modell solche Kandidaten hat. Die Ziel-Unit steht
// am Anfang auf dem Ziel des Servers. Für „Mitglied verschieben“ (#675)
// stehen oben statt Name und Unit das Ziel (ein Vorfahr zur Auswahl bzw. die
// Nachfahren zum Ankreuzen) und die Wahl des Servers („andere Nachfahren
// überschreiben“ bzw. „abstrakt im Vorfahren lassen“). Fehler zeigt die Zeile über den
// Knöpfen; „Vorschau …“ geht erst ohne Fehler. Reine VCL; das Modell ist
// TAtlasClassExtractionModel.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.CheckLst,
  Atlas.Core.Editor.ClassExtraction;

type
  TAtlasExtractMembersDialog = class(TForm)
  private
    FModel: TAtlasClassExtractionModel;
    FName: TEdit;
    FUnit: TComboBox;
    FList: TListView;
    FAbstract: TCheckBox;
    FTarget: TComboBox;
    FTargetList: TCheckListBox;
    FOptionBox: TCheckBox;
    FError: TLabel;
    FOk: TButton;
    FUpdating: Boolean;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabeled(AParent: TWinControl; const ACaption: string; ATop: Integer; AControl: TWinControl): Integer;
    /// <summary>Knöpfe, Hinweise des Servers und Fehlerzeile unten.</summary>
    procedure CreateFooter;
    /// <summary>Name und Ziel-Unit oben; beim Verschieben die Ziele und die Wahl.</summary>
    procedure CreateHeader;
    /// <summary>Ziele und Wahl des Servers ab ARow; liefert die nächste freie Zeile.</summary>
    function CreateMoveHeader(AHeader: TWinControl; ARow: Integer): Integer;
    /// <summary>Knöpfe rechts neben der Liste.</summary>
    procedure CreateSide;
    procedure CreateList;
    procedure FillList;
    procedure Refresh;
    procedure ShowMode;
    procedure NameChange(Sender: TObject);
    procedure TargetChange(Sender: TObject);
    procedure TargetClickCheck(Sender: TObject);
    procedure OptionClick(Sender: TObject);
    procedure UnitChange(Sender: TObject);
    /// <summary>„Alle“ (Tag 1) bzw. „Keine“ (Tag 0).</summary>
    procedure CheckAllClick(Sender: TObject);
    procedure NeedsClick(Sender: TObject);
    procedure AbstractClick(Sender: TObject);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
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
  Vcl.Themes,
  Vcl.Graphics,
  Atlas.UI.Strings;

const
  cGap = 8;
  cDialogWidth = 680;
  cDialogHeight = 480;

function OwnUnitCaption(AModel: TAtlasClassExtractionModel): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractMembersOwnUnit, [AModel.Source.OwnUnit]);
end;

function TargetCaption(AModel: TAtlasClassExtractionModel; AIndex: Integer): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractMembersTargetItem, [AModel.Targets[AIndex].Name,
    AModel.Targets[AIndex].UnitName]);
end;

/// <summary>Hinweise des Servers, eine je Zeile.</summary>
function NotesText(AModel: TAtlasClassExtractionModel): string;
var
  mNote: string;
begin
  Result := '';
  for mNote in AModel.Source.Notes do
  begin
    if Result <> '' then
    begin
      Result := Result + sLineBreak;
    end;
    Result := Result + mNote;
  end;
end;

function KindText(const AMember: TAtlasExtractionMember): string;
begin
  if AMember.Kind = 'property' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ExtractMembersProperty);
  end
  else if AMember.Kind = 'field' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ExtractMembersField);
  end
  else if AMember.Abstract then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ExtractMembersAbstractMethod);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ExtractMembersMethod);
  end;
end;

/// <summary>Meldung zum Fehler der Eingabe in der Sprache der Oberfläche; '' ohne Fehler.</summary>
function ProblemText(AModel: TAtlasClassExtractionModel; AProblem: TAtlasExtractionProblem;
  const ASubject: string): string;
var
  mMember, mNeeded: string;
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
    TAtlasExtractionProblem.NoTarget:
      Result := TAtlasStrings.Text(TAtlasTextId.ExtractMembersNoTarget);
    TAtlasExtractionProblem.MissingDependency:
      begin
        AModel.MissingDependency(mMember, mNeeded);
        Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractMembersMissing, [mMember, mNeeded]);
      end;
  else
    Result := '';
  end;
end;

/// <summary>Nachfahren zum Ankreuzen.</summary>
procedure FillTargetList(AList: TCheckListBox; AModel: TAtlasClassExtractionModel);
var
  mIndex: Integer;
begin
  AList.Items.BeginUpdate;
  try
    for mIndex := 0 to AModel.TargetCount - 1 do
    begin
      AList.Items.Add(TargetCaption(AModel, mIndex));
      AList.Checked[mIndex] := AModel.Targets[mIndex].Checked;
    end;
  finally
    AList.Items.EndUpdate;
  end;
end;

/// <summary>Vorfahren zur Auswahl, der gewählte vorgewählt.</summary>
procedure FillTargetBox(ABox: TComboBox; AModel: TAtlasClassExtractionModel);
var
  mIndex: Integer;
begin
  ABox.Items.BeginUpdate;
  try
    for mIndex := 0 to AModel.TargetCount - 1 do
    begin
      ABox.Items.Add(TargetCaption(AModel, mIndex));
      if AModel.Targets[mIndex].Checked then
      begin
        ABox.ItemIndex := mIndex;
      end;
    end;
  finally
    ABox.Items.EndUpdate;
  end;
end;

/// <summary>Unit der Klasse, die übrigen Units und das Ziel des Servers (refactoring.extractSuperclassTarget)
/// vorgewählt.</summary>
procedure FillUnits(ABox: TComboBox; AModel: TAtlasClassExtractionModel);
var
  mName: string;
  mIndex: Integer;
begin
  ABox.Items.BeginUpdate;
  try
    ABox.Items.Add(OwnUnitCaption(AModel));
    for mName in AModel.Source.Units do
    begin
      if not SameText(mName, AModel.Source.OwnUnit) then
      begin
        ABox.Items.Add(mName);
      end;
    end;
  finally
    ABox.Items.EndUpdate;
  end;
  ABox.ItemIndex := 0;
  if AModel.Target = '' then
  begin
    Exit;
  end;
  mIndex := ABox.Items.IndexOf(AModel.Target);
  if mIndex >= 0 then
  begin
    ABox.ItemIndex := mIndex;
  end
  else
  begin
    ABox.Text := AModel.Target;
  end;
end;

{ TAtlasExtractMembersDialog }

constructor TAtlasExtractMembersDialog.CreateDialog(AOwner: TComponent; AModel: TAtlasClassExtractionModel;
  const ATitle: string);
begin
  inherited CreateNew(AOwner);
  FModel := AModel;
  Caption := ATitle;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  ClientHeight := ScaleValue(cDialogHeight);
  CreateFooter;
  CreateHeader;
  CreateSide;
  CreateList;
  if FName <> nil then
  begin
    ActiveControl := FName;
  end;
end;

procedure TAtlasExtractMembersDialog.CreateFooter;
var
  mBottom: TPanel;
  mCancel: TButton;
  mNotes: TLabel;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  mCancel := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.ExtractMembersCancel), nil);
  mCancel.Cancel := True;
  mCancel.ModalResult := mrCancel;
  mCancel.Left := mBottom.ClientWidth - mCancel.Width - ScaleValue(cGap);
  FOk := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.ExtractMembersPreview), OkClick);
  FOk.Default := True;
  FOk.Left := mCancel.Left - FOk.Width - ScaleValue(cGap);
  // Hinweise des Servers und Fehler über den Knöpfen.
  mNotes := TLabel.Create(Self);
  mNotes.Parent := Self;
  mNotes.Align := alBottom;
  mNotes.AlignWithMargins := True;
  mNotes.Margins.SetBounds(cGap, 0, cGap, cGap div 2);
  mNotes.WordWrap := True;
  mNotes.ShowAccelChar := False;
  mNotes.Caption := NotesText(FModel);
  FError := TLabel.Create(Self);
  FError.Parent := Self;
  FError.Align := alBottom;
  FError.AlignWithMargins := True;
  FError.Margins.SetBounds(cGap, cGap div 2, cGap, cGap div 2);
  FError.WordWrap := True;
  FError.ShowAccelChar := False;
  FError.Font.Color := clRed;
end;

procedure TAtlasExtractMembersDialog.CreateHeader;
var
  mHeader: TPanel;
  mRow: Integer;
begin
  mHeader := TPanel.Create(Self);
  mHeader.Parent := Self;
  mHeader.Align := alTop;
  mHeader.Height := ScaleValue(64);
  mHeader.BevelOuter := bvNone;
  mRow := ScaleValue(cGap);
  if FModel.IsMove then
  begin
    mHeader.Height := CreateMoveHeader(mHeader, mRow) + ScaleValue(cGap div 2);
    Exit;
  end;
  FName := TEdit.Create(Self);
  FUnit := TComboBox.Create(Self);
  mRow := AddLabeled(mHeader, TAtlasStrings.Text(TAtlasTextId.ExtractMembersName), mRow, FName);
  AddLabeled(mHeader, TAtlasStrings.Text(TAtlasTextId.ExtractMembersUnit), mRow, FUnit);
  FName.Text := FModel.Name;
  FName.OnChange := NameChange;
  // Eingabe erlaubt: Ein neuer Unit-Name legt die Unit an.
  FUnit.Style := csDropDown;
  FUnit.OnChange := UnitChange;
end;

function TAtlasExtractMembersDialog.CreateMoveHeader(AHeader: TWinControl; ARow: Integer): Integer;
begin
  Result := ARow;
  if FModel.Source.MultiTarget then
  begin
    FTargetList := TCheckListBox.Create(Self);
    Result := AddLabeled(AHeader, TAtlasStrings.Text(TAtlasTextId.ExtractMembersTargets), Result, FTargetList);
    FTargetList.Height := ScaleValue(66);
    Result := Result + FTargetList.Height - ScaleValue(23);
    FTargetList.OnClickCheck := TargetClickCheck;
  end
  else
  begin
    FTarget := TComboBox.Create(Self);
    Result := AddLabeled(AHeader, TAtlasStrings.Text(TAtlasTextId.ExtractMembersTarget), Result, FTarget);
    FTarget.Style := csDropDownList;
    FTarget.OnChange := TargetChange;
  end;
  if FModel.Source.OptionKind = '' then
  begin
    Exit;
  end;
  FOptionBox := TCheckBox.Create(Self);
  FOptionBox.Parent := AHeader;
  FOptionBox.Caption := TAtlasStrings.Text(TAtlasTextId.ExtractMembersOverrideSiblings);
  if FModel.Source.OptionKind = 'keepAbstract' then
  begin
    FOptionBox.Caption := TAtlasStrings.Text(TAtlasTextId.ExtractMembersKeepAbstract);
  end;
  FOptionBox.SetBounds(ScaleValue(120), Result, ScaleValue(cDialogWidth - 120 - cGap), ScaleValue(23));
  FOptionBox.Anchors := [akLeft, akTop, akRight];
  FOptionBox.Checked := FModel.Option;
  FOptionBox.OnClick := OptionClick;
  Result := Result + ScaleValue(28);
end;

procedure TAtlasExtractMembersDialog.CreateSide;
var
  mRight: TPanel;
  mAll, mNone, mNeeds: TButton;
  mIndex: Integer;
begin
  mRight := TPanel.Create(Self);
  mRight.Parent := Self;
  mRight.Align := alRight;
  mRight.Width := ScaleValue(100);
  mRight.BevelOuter := bvNone;
  mAll := AddButton(mRight, TAtlasStrings.Text(TAtlasTextId.ExtractMembersAll), CheckAllClick);
  mAll.Tag := 1;
  mNone := AddButton(mRight, TAtlasStrings.Text(TAtlasTextId.ExtractMembersNone), CheckAllClick);
  mNeeds := AddButton(mRight, TAtlasStrings.Text(TAtlasTextId.ExtractMembersTakeNeeds), NeedsClick);
  FAbstract := TCheckBox.Create(Self);
  FAbstract.Parent := mRight;
  FAbstract.Caption := TAtlasStrings.Text(TAtlasTextId.ExtractMembersAbstract);
  FAbstract.Height := ScaleValue(23);
  FAbstract.OnClick := AbstractClick;
  mAll.Top := ScaleValue(cGap);
  mNone.Top := mAll.Top + mAll.Height + ScaleValue(4);
  mNeeds.Top := mNone.Top + mNone.Height + ScaleValue(3 * cGap);
  FAbstract.Top := mNeeds.Top + mNeeds.Height + ScaleValue(cGap);
  // Nur für die Basisklasse (#713): Abhängigkeiten und abstrakte Methoden.
  mNeeds.Visible := FModel.HasNeeds;
  FAbstract.Visible := FModel.HasModes;
  FAbstract.Enabled := False;
  for mIndex := 0 to mRight.ControlCount - 1 do
  begin
    mRight.Controls[mIndex].Left := ScaleValue(cGap);
    mRight.Controls[mIndex].Width := mRight.Width - ScaleValue(2 * cGap);
    mRight.Controls[mIndex].Anchors := [akLeft, akTop];
  end;
end;

procedure TAtlasExtractMembersDialog.CreateList;

  procedure AddColumn(const ACaption: string; AWidth: Integer);
  var
    mColumn: TListColumn;
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := ACaption;
    mColumn.Width := ScaleValue(AWidth);
  end;

begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, 0, 0);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.Checkboxes := True;
  FList.OnItemChecked := ListChecked;
  FList.OnSelectItem := ListSelect;
  FList.OnCustomDrawItem := ListCustomDraw;
  AddColumn(TAtlasStrings.Text(TAtlasTextId.ExtractMembersColMember), 260);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.ExtractMembersColKind), 70);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.ExtractMembersColVisibility), 90);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.ExtractMembersColReason), 140);
end;

function TAtlasExtractMembersDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Result.Width := ScaleValue(100);
  Result.Top := ScaleValue(cGap);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

function TAtlasExtractMembersDialog.AddLabeled(AParent: TWinControl; const ACaption: string; ATop: Integer;
  AControl: TWinControl): Integer;
var
  mCaption: TLabel;
begin
  mCaption := TLabel.Create(Self);
  mCaption.Parent := AParent;
  mCaption.Caption := ACaption;
  mCaption.SetBounds(ScaleValue(cGap), ATop + ScaleValue(3), ScaleValue(110), ScaleValue(20));
  mCaption.FocusControl := AControl;
  AControl.Parent := AParent;
  AControl.SetBounds(ScaleValue(120), ATop, ScaleValue(cDialogWidth - 120 - cGap), ScaleValue(23));
  AControl.Anchors := [akLeft, akTop, akRight];
  Result := ATop + ScaleValue(28);
end;

procedure TAtlasExtractMembersDialog.DoShow;
begin
  inherited;
  // Liste und Auswahlfeld brauchen ein Fenster: erst hier füllen.
  if FModel.IsMove and (FList.Items.Count = 0) then
  begin
    FUpdating := True;
    try
      if FTargetList <> nil then
      begin
        FillTargetList(FTargetList, FModel);
      end
      else
      begin
        FillTargetBox(FTarget, FModel);
      end;
    finally
      FUpdating := False;
    end;
    FillList;
  end;
  if (FUnit <> nil) and (FUnit.Items.Count = 0) then
  begin
    FUpdating := True;
    try
      FillUnits(FUnit, FModel);
    finally
      FUpdating := False;
    end;
    FillList;
  end;
  if FName <> nil then
  begin
    FName.SelectAll;
  end;
end;

procedure TAtlasExtractMembersDialog.CheckAllClick(Sender: TObject);
begin
  FModel.CheckAll((Sender as TComponent).Tag = 1);
  FillList;
end;

procedure TAtlasExtractMembersDialog.FillList;
var
  mIndex, mSelected: Integer;
  mItem: TListItem;
  mMember: TAtlasExtractionMember;
begin
  mSelected := -1;
  if FList.Selected <> nil then
  begin
    mSelected := FList.Selected.Index;
  end;
  FUpdating := True;
  try
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      for mIndex := 0 to FModel.Count - 1 do
      begin
        mMember := FModel[mIndex];
        mItem := FList.Items.Add;
        mItem.Caption := mMember.Display;
        mItem.SubItems.Add(KindText(mMember));
        mItem.SubItems.Add(mMember.Visibility);
        mItem.SubItems.Add(mMember.Reason);
        mItem.Checked := mMember.Checked;
      end;
    finally
      FList.Items.EndUpdate;
    end;
    if (mSelected >= 0) and (mSelected < FList.Items.Count) then
    begin
      FList.Items[mSelected].Selected := True;
    end;
  finally
    FUpdating := False;
  end;
  ShowMode;
  Refresh;
end;

/// <summary>„Nur abstrakt“ nach der markierten Methode.</summary>
procedure TAtlasExtractMembersDialog.ShowMode;
var
  mMember: TAtlasExtractionMember;
begin
  if not FAbstract.Visible then
  begin
    Exit;
  end;
  FUpdating := True;
  try
    if (FList.Selected <> nil) and (FList.Selected.Index < FModel.Count) then
    begin
      mMember := FModel[FList.Selected.Index];
      FAbstract.Enabled := mMember.CanAbstract;
      FAbstract.Checked := mMember.Abstract;
    end
    else
    begin
      FAbstract.Enabled := False;
      FAbstract.Checked := False;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasExtractMembersDialog.Refresh;
var
  mProblem: TAtlasExtractionProblem;
  mSubject: string;
begin
  mProblem := FModel.Validate(mSubject);
  FError.Caption := ProblemText(FModel, mProblem, mSubject);
  FOk.Enabled := mProblem = TAtlasExtractionProblem.None;
end;

procedure TAtlasExtractMembersDialog.NameChange(Sender: TObject);
begin
  FModel.Name := FName.Text;
  Refresh;
end;

procedure TAtlasExtractMembersDialog.TargetChange(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  FModel.SetTargetChecked(FTarget.ItemIndex, True);
  Refresh;
end;

procedure TAtlasExtractMembersDialog.TargetClickCheck(Sender: TObject);
var
  mIndex: Integer;
begin
  if FUpdating then
  begin
    Exit;
  end;
  for mIndex := 0 to FTargetList.Items.Count - 1 do
  begin
    FModel.SetTargetChecked(mIndex, FTargetList.Checked[mIndex]);
  end;
  Refresh;
end;

procedure TAtlasExtractMembersDialog.OptionClick(Sender: TObject);
begin
  FModel.Option := FOptionBox.Checked;
end;

procedure TAtlasExtractMembersDialog.UnitChange(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  // Erster Eintrag = Unit der Klasse.
  if (FUnit.ItemIndex = 0) or (FUnit.Text = OwnUnitCaption(FModel)) then
  begin
    FModel.TargetUnit := '';
  end
  else
  begin
    FModel.TargetUnit := FUnit.Text;
  end;
  Refresh;
end;

procedure TAtlasExtractMembersDialog.NeedsClick(Sender: TObject);
begin
  FModel.TakeDependencies;
  FillList;
end;

procedure TAtlasExtractMembersDialog.AbstractClick(Sender: TObject);
begin
  if FUpdating or (FList.Selected = nil) then
  begin
    Exit;
  end;
  FModel.SetAbstract(FList.Selected.Index, FAbstract.Checked);
  FList.Selected.SubItems[0] := KindText(FModel[FList.Selected.Index]);
  Refresh;
end;

procedure TAtlasExtractMembersDialog.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not FUpdating then
  begin
    ShowMode;
  end;
end;

procedure TAtlasExtractMembersDialog.ListChecked(Sender: TObject; Item: TListItem);
begin
  if FUpdating or (Item = nil) then
  begin
    Exit;
  end;
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
  begin
    // Hintergrund in der Stilfarbe, sonst zeichnet die Zeile weiß bzw. schwarz (clWindow, clWindowText ohne Stil).
    if not (cdsSelected in State) then
    begin
      Sender.Canvas.Brush.Color := StyleServices(Sender).GetSystemColor(clWindow);
      Sender.Canvas.Font.Color := StyleServices(Sender).GetSystemColor(clWindowText);
    end;
    Sender.Canvas.Font.Color := StyleServices(Sender).GetSystemColor(clGrayText);
  end;
end;

procedure TAtlasExtractMembersDialog.OkClick(Sender: TObject);
begin
  if FModel.Validate = TAtlasExtractionProblem.None then
  begin
    ModalResult := mrOk;
  end;
end;

class function TAtlasExtractMembersDialog.Execute(AModel: TAtlasClassExtractionModel; const ATitle: string): Boolean;
var
  mDialog: TAtlasExtractMembersDialog;
begin
  mDialog := TAtlasExtractMembersDialog.CreateDialog(nil, AModel, ATitle);
  try
    Result := mDialog.ShowModal = mrOk;
  finally
    mDialog.Free;
  end;
end;

end.
