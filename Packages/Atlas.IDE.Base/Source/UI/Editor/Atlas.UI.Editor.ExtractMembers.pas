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
// Thema, Schrift und Fehlerfarbe kommen über TAtlasDialog. Spalten der Liste
// richten sich nach dem Inhalt (der Grund füllt den Rest), Beschriftungen und
// Knöpfe nach ihrem Text; das Fenster wächst beim ersten Zeigen bis zum
// Inhalt, höchstens auf 80 % des Arbeitsbereichs, und bleibt ziehbar.

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
  Atlas.Core.Editor.ClassExtraction,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.ListView;

type
  TAtlasExtractMembersDialog = class(TAtlasDialog)
  private
    FModel: TAtlasClassExtractionModel;
    FName: TEdit;
    FUnit: TComboBox;
    FList: TAtlasListView;
    FAbstract: TCheckBox;
    FTarget: TComboBox;
    FTargetList: TCheckListBox;
    FOptionBox: TCheckBox;
    FError: TLabel;
    FOk: TButton;
    /// <summary>Linker Rand der Felder im Kopf (rechts der Beschriftungen), Gerätepixel.</summary>
    FFieldLeft: Integer;
    FUpdating: Boolean;
    FFitted: Boolean;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabeled(AParent: TWinControl; const ACaption: string; ATop: Integer; AControl: TWinControl): Integer;
    /// <summary>Spalten nach Inhalt; Fenster bis zum Inhalt vergrößern, höchstens MaxInitialSize.</summary>
    procedure FitToContent;
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
    procedure ThemeChanged; override;
  public
    constructor CreateDialog(AOwner: TComponent; AModel: TAtlasClassExtractionModel; const ATitle: string);
    /// <summary>True, wenn der Benutzer „Vorschau …“ gewählt hat; das Modell enthält dann Name, Ziel und
    /// Auswahl.</summary>
    class function Execute(AModel: TAtlasClassExtractionModel; const ATitle: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  System.Math,
  Vcl.Themes,
  Vcl.Graphics,
  Atlas.Core.Style.Signal,
  Atlas.UI.Editor.Strings,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Foundation.WrapLabel;

const
  // Anfangsbreiten der Spalten Mitglied, Art, Sichtbarkeit und Grund (logische Pixel), bis FitToContent sie nach
  // dem Inhalt setzt.
  cMemberWidth = 260;
  cKindWidth = 70;
  cVisibilityWidth = 90;
  cReasonWidth = 140;
  /// <summary>Spalten nach Inhalt höchstens so breit, logische Pixel.</summary>
  cColumnMaxWidth = 360;
  cColumnReason = 3;

const
  cGap = 8;
  cDialogWidth = 680;
  cDialogHeight = 480;
  /// <summary>Kleinste Innengröße, logische Pixel.</summary>
  cMinWidth = 560;
  cMinHeight = 380;
  /// <summary>Höhe einer Zeile im Kopf, logische Pixel.</summary>
  cRowHeight = 23;
  cRowStep = 28;
  /// <summary>Beschriftung im Kopf: Abstand von der Oberkante der Zeile und Höhe, logische Pixel.</summary>
  cLabelOffset = 3;
  cLabelHeight = 20;
  /// <summary>Kästchen vor dem Text eines TCheckBox, logische Pixel.</summary>
  cCheckMark = 16;
  /// <summary>Anfangs so viele Zeilen der Liste sichtbar.</summary>
  cInitialRows = 16;

function OwnUnitCaption(AModel: TAtlasClassExtractionModel): string;
begin
  Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.ExtractMembersOwnUnit, [AModel.Source.OwnUnit]);
end;

function TargetCaption(AModel: TAtlasClassExtractionModel; AIndex: Integer): string;
begin
  Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.ExtractMembersTargetItem, [AModel.Targets[AIndex].Name,
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
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersProperty);
  end
  else if AMember.Kind = 'field' then
  begin
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersField);
  end
  else if AMember.Abstract then
  begin
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersAbstractMethod);
  end
  else
  begin
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersMethod);
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
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.ExtractMembersBadName, [ASubject]);
    TAtlasExtractionProblem.SameName:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersSameName);
    TAtlasExtractionProblem.NoMembers:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersNoMembers);
    TAtlasExtractionProblem.BadUnit:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.ExtractMembersBadUnit, [ASubject]);
    TAtlasExtractionProblem.NoTarget:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersNoTarget);
    TAtlasExtractionProblem.MissingDependency:
      begin
        AModel.MissingDependency(mMember, mNeeded);
        Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.ExtractMembersMissing, [mMember, mNeeded]);
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

/// <summary>ALabel in der Fehlerfarbe des Themas.</summary>
procedure ShowAsError(ALabel: TLabel);
begin
  // Mit seFont zeichnete der Stil die Schrift in seiner Textfarbe statt in der Fehlerfarbe.
  ALabel.StyleElements := ALabel.StyleElements - [seFont];
  ALabel.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
end;

{ TAtlasExtractMembersDialog }

constructor TAtlasExtractMembersDialog.CreateDialog(AOwner: TComponent; AModel: TAtlasClassExtractionModel;
  const ATitle: string);
begin
  inherited CreateDialog(AOwner, ATitle, cDialogWidth);
  FModel := AModel;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  ClientHeight := ScaleValue(cDialogHeight);
  CreateFooter;
  CreateHeader;
  CreateSide;
  CreateList;
  ShowAsError(FError);
  Constraints.MinWidth := Width - ClientWidth + ScaleValue(cMinWidth);
  Constraints.MinHeight := Height - ClientHeight + ScaleValue(cMinHeight);
  if FName <> nil then
  begin
    ActiveControl := FName;
  end;
end;

procedure TAtlasExtractMembersDialog.ThemeChanged;
begin
  inherited;
  ShowAsError(FError);
end;

procedure TAtlasExtractMembersDialog.FitToContent;
var
  mRow: TRect;
  mLimit: TSize;
  mWidth, mHeight, mIndex, mRowHeight, mRows: Integer;
begin
  if FFitted or (FList.Items.Count = 0) then
  begin
    Exit;
  end;
  FFitted := True;
  mLimit := MaxInitialSize;
  FList.FillColumn(cColumnReason, cReasonWidth);
  FList.FitColumnsToContent(cColumnMaxWidth);
  // Alle Spalten samt ganzem Grund, Rand der Liste und senkrechte Rollleiste.
  mWidth := FList.ContentWidth(cColumnReason) + FList.Margins.Left + FList.Margins.Right +
    MulDiv(GetSystemMetrics(SM_CXVSCROLL), CurrentPPI, Screen.PixelsPerInch) + ScaleValue(cGap);
  for mIndex := 0 to FList.Columns.Count - 1 do
  begin
    if mIndex <> cColumnReason then
    begin
      Inc(mWidth, FList.Columns[mIndex].Width);
    end;
  end;
  Inc(mWidth, ClientWidth - FList.Width - FList.Margins.Left - FList.Margins.Right);
  mRowHeight := Abs(FList.Font.Height) + ScaleValue(cGap);
  if ListView_GetItemRect(FList.Handle, 0, mRow, LVIR_BOUNDS) then
  begin
    mRowHeight := mRow.Height;
  end;
  mRows := Min(FList.Items.Count, cInitialRows);
  // Kopfzeile der Liste etwa so hoch wie eine Zeile, dazu ihr Rahmen.
  mHeight := ClientHeight - FList.Height + (mRows + 2) * mRowHeight;
  ClientWidth := Max(ClientWidth, Min(mWidth, mLimit.cx));
  ClientHeight := Max(ClientHeight, Min(mHeight, mLimit.cy));
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
  FitToContent;
  if FName <> nil then
  begin
    FName.SelectAll;
  end;
end;

function TAtlasExtractMembersDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Result.Width := Max(TextWidth(Font, ACaption) + ScaleValue(TAtlasButtonRow.cButtonPadding),
    ScaleValue(TAtlasButtonRow.cButtonMinWidth));
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
  mCaption.SetBounds(ScaleValue(cGap), ATop + ScaleValue(cLabelOffset), FFieldLeft - ScaleValue(2 * cGap),
    ScaleValue(cLabelHeight));
  mCaption.FocusControl := AControl;
  AControl.Parent := AParent;
  AControl.SetBounds(FFieldLeft, ATop, ClientWidth - FFieldLeft - ScaleValue(cGap), ScaleValue(cRowHeight));
  AControl.Anchors := [akLeft, akTop, akRight];
  Result := ATop + ScaleValue(cRowStep);
end;

procedure TAtlasExtractMembersDialog.CreateFooter;
var
  mButtons: TAtlasButtonRow;
  mNotes: TLabel;
begin
  // Knöpfe rechts unten: von rechts nach links „Abbrechen“, dann „Vorschau …“.
  mButtons := TAtlasButtonRow.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alBottom;
  mButtons.FlowStyle := fsRightLeftTopBottom;
  mButtons.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap div 2));
  mButtons.AddButton(TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersCancel), TAtlasButtonKind.Cancel);
  FOk := mButtons.AddButton(TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersPreview),
    TAtlasButtonKind.Default);
  FOk.OnClick := OkClick;
  // Hinweise des Servers und Fehler über den Knöpfen.
  mNotes := TAtlasWrapLabel.Create(Self);
  mNotes.Parent := Self;
  mNotes.Align := alBottom;
  mNotes.AlignWithMargins := True;
  mNotes.Margins.SetBounds(ScaleValue(cGap), 0, ScaleValue(cGap), ScaleValue(cGap div 2));
  mNotes.Caption := NotesText(FModel);
  FError := TAtlasWrapLabel.Create(Self);
  FError.Parent := Self;
  FError.Align := alBottom;
  FError.AlignWithMargins := True;
  FError.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap div 2), ScaleValue(cGap), ScaleValue(cGap div 2));
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
  mHeader.Caption := '';
  // Beschriftungen so breit wie die längste, damit auch längere Übersetzungen nicht abgeschnitten werden.
  FFieldLeft := Max(Max(TextWidth(Font, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersName)),
    TextWidth(Font, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersUnit))),
    Max(TextWidth(Font, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersTargets)),
    TextWidth(Font, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersTarget)))) + ScaleValue(2 * cGap);
  mRow := ScaleValue(cGap);
  if FModel.IsMove then
  begin
    mHeader.Height := CreateMoveHeader(mHeader, mRow) + ScaleValue(cGap div 2);
    Exit;
  end;
  FName := TEdit.Create(Self);
  FUnit := TComboBox.Create(Self);
  mRow := AddLabeled(mHeader, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersName), mRow, FName);
  AddLabeled(mHeader, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersUnit), mRow, FUnit);
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
    Result := AddLabeled(AHeader, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersTargets), Result,
      FTargetList);
    FTargetList.Height := ScaleValue(66);
    Result := Result + FTargetList.Height - ScaleValue(cRowHeight);
    FTargetList.OnClickCheck := TargetClickCheck;
  end
  else
  begin
    FTarget := TComboBox.Create(Self);
    Result := AddLabeled(AHeader, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersTarget), Result, FTarget);
    FTarget.Style := csDropDownList;
    FTarget.OnChange := TargetChange;
  end;
  if FModel.Source.OptionKind = '' then
  begin
    Exit;
  end;
  FOptionBox := TCheckBox.Create(Self);
  FOptionBox.Parent := AHeader;
  FOptionBox.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersOverrideSiblings);
  if FModel.Source.OptionKind = 'keepAbstract' then
  begin
    FOptionBox.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersKeepAbstract);
  end;
  FOptionBox.SetBounds(FFieldLeft, Result, ClientWidth - FFieldLeft - ScaleValue(cGap), ScaleValue(cRowHeight));
  FOptionBox.Anchors := [akLeft, akTop, akRight];
  FOptionBox.Checked := FModel.Option;
  FOptionBox.OnClick := OptionClick;
  Result := Result + ScaleValue(cRowStep);
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
  mRight.BevelOuter := bvNone;
  mRight.Caption := '';
  mAll := AddButton(mRight, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersAll), CheckAllClick);
  mAll.Tag := 1;
  mNone := AddButton(mRight, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersNone), CheckAllClick);
  mNeeds := AddButton(mRight, TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersTakeNeeds), NeedsClick);
  FAbstract := TCheckBox.Create(Self);
  FAbstract.Parent := mRight;
  FAbstract.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersAbstract);
  FAbstract.Height := ScaleValue(cRowHeight);
  FAbstract.OnClick := AbstractClick;
  // So breit wie der breiteste Knopf bzw. das Kästchen samt Text, mit Rand links und rechts.
  mRight.Width := Max(Max(mAll.Width, mNone.Width), Max(mNeeds.Width, TextWidth(Font, FAbstract.Caption) +
    ScaleValue(2 * cGap + cCheckMark))) + ScaleValue(2 * cGap);
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
begin
  FList := TAtlasListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), 0, 0);
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.Checkboxes := True;
  FList.OnItemChecked := ListChecked;
  FList.OnSelectItem := ListSelect;
  FList.OnCustomDrawItem := ListCustomDraw;
  FList.AddColumn(TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersColMember), cMemberWidth);
  FList.AddColumn(TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersColKind), cKindWidth);
  FList.AddColumn(TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersColVisibility), cVisibilityWidth);
  FList.AddColumn(TAtlasEditorStrings.Text(TAtlasEditorTextId.ExtractMembersColReason), cReasonWidth);
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

procedure TAtlasExtractMembersDialog.Refresh;
var
  mProblem: TAtlasExtractionProblem;
  mSubject: string;
begin
  mProblem := FModel.Validate(mSubject);
  FError.Caption := ProblemText(FModel, mProblem, mSubject);
  FOk.Enabled := mProblem = TAtlasExtractionProblem.None;
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

procedure TAtlasExtractMembersDialog.CheckAllClick(Sender: TObject);
begin
  FModel.CheckAll((Sender as TComponent).Tag = 1);
  FillList;
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
