unit Atlas.UI.Tests.ListDialog;

// Dialog „Neue Testliste“ bzw. „Testliste bearbeiten“ (#2167), reine VCL:
// Name, Ablage („Im Projekt“ in atlas.json oder „Nur für mich“), bei einer
// neuen Liste die Art (fest oder dynamisch) und bei einer dynamischen die
// Regeln: Liste der Regeln, darunter Art (Kategorie, Unit/Fixture, Stand),
// „ist / passt“ bzw. „ist nicht / passt nicht“ und Wert (bekannte Kategorien
// bzw. Stände zur Auswahl) mit „Regel hinzufügen“ und „Regel entfernen“.
// Einwände (Name fehlt oder ist vergeben, keine Regel) zeigt die Hinweiszeile;
// „OK“ schließt erst ohne Einwand. Prüfung und Beschreibung der Regeln in
// Atlas.Core.Tests.ListText.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog,
  Atlas.Core.Tests.Lists,
  Atlas.Core.Tests.ListText;

type
  TAtlasTestsListDialog = class(TAtlasDialog)
  private const
    cWidth = 520;
    cLineHeight = 26;
    cRulesHeight = 120;
    cLabelWidth = 90;
    cKindWidth = 110;
    cModeWidth = 150;
    cNoteHeight = 34;
  private
    FList: TAtlasTestList;
    FTaken: TArray<string>;
    FCategories: TArray<string>;
    FTexts: TAtlasTestListTexts;
    FName: TEdit;
    FStore: TComboBox;
    FFixed: TRadioButton;
    FDynamic: TRadioButton;
    FRules: TListBox;
    FKind: TComboBox;
    FMode: TComboBox;
    FValue: TComboBox;
    FAddRule: TButton;
    FRemoveRule: TButton;
    FNote: TAtlasNoteLabel;
    FFilled: Boolean;
    function AddField(const ACaption: string): TPanel;
    procedure AddKinds(ANew: Boolean);
    procedure AddRuleRows;
    procedure FillRules;
    procedure FillValues;
    procedure KindChange(Sender: TObject);
    procedure KindOfListClick(Sender: TObject);
    procedure AddRuleClick(Sender: TObject);
    procedure RemoveRuleClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    function Dynamic: Boolean;
  protected
    /// <summary>Auswahlfelder und Regeln füllen; sie brauchen ein Fenster.</summary>
    procedure DoShow; override;
  public
    /// <summary>AList bearbeiten (ANew: neue Liste, Art wählbar); ATaken: Namen der anderen Listen; ACategories:
    /// Kategorien des Testprojekts zur Auswahl.</summary>
    constructor CreateFor(AOwner: TComponent; const AList: TAtlasTestList; ANew: Boolean;
      const ATaken, ACategories: TArray<string>; const ATexts: TAtlasTestListTexts);
    /// <summary>Modal zeigen; True mit der geänderten Liste in AList.</summary>
    class function Execute(var AList: TAtlasTestList; ANew: Boolean; const ATaken, ACategories: TArray<string>;
      const ATexts: TAtlasTestListTexts): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Forms,
  Atlas.Core.Style.Signal,
  Atlas.UI.Tests.Strings;

constructor TAtlasTestsListDialog.CreateFor(AOwner: TComponent; const AList: TAtlasTestList; ANew: Boolean;
  const ATaken, ACategories: TArray<string>; const ATexts: TAtlasTestListTexts);
const
  cTitles: array[Boolean] of TAtlasTestsTextId = (TAtlasTestsTextId.ListDialogEdit, TAtlasTestsTextId.ListDialogNew);
var
  mButtons: TAtlasButtonRow;
  mOk, mCancel: TButton;
begin
  inherited CreateDialog(AOwner, TAtlasTestsStrings.Text(cTitles[ANew]), cWidth);
  FList := AList;
  FTaken := ATaken;
  FCategories := ACategories;
  FTexts := ATexts;
  FName := TEdit.Create(Self);
  FName.Parent := AddField(TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogName));
  FName.SetBounds(ScaleValue(cLabelWidth), 0, ScaleValue(cWidth - cLabelWidth - 2 * cRowGap), FName.Height);
  FName.Text := AList.Name;
  FStore := TComboBox.Create(Self);
  FStore.Parent := AddField(TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogStore));
  FStore.Style := csDropDownList;
  FStore.SetBounds(ScaleValue(cLabelWidth), 0, ScaleValue(cWidth - cLabelWidth - 2 * cRowGap), FStore.Height);
  AddKinds(ANew);
  AddRuleRows;
  FNote := AddNote(cNoteHeight);
  mButtons := AddButtonRow;
  mOk := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogOk), TAtlasButtonKind.Default);
  mOk.OnClick := OkClick;
  mCancel := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogCancel),
    TAtlasButtonKind.Cancel);
  mCancel.ModalResult := mrCancel;
  FitHeight;
end;

function TAtlasTestsListDialog.AddField(const ACaption: string): TPanel;
begin
  Result := AddRow(cLineHeight);
  AddLabel(Result, ACaption);
end;

procedure TAtlasTestsListDialog.AddKinds(ANew: Boolean);
begin
  FFixed := TRadioButton.Create(Self);
  FFixed.Parent := AddRow(cLineHeight);
  FFixed.Align := alClient;
  FFixed.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogFixed);
  FFixed.Checked := not FList.IsDynamic and not ANew;
  FFixed.OnClick := KindOfListClick;
  FDynamic := TRadioButton.Create(Self);
  FDynamic.Parent := AddRow(cLineHeight);
  FDynamic.Align := alClient;
  FDynamic.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogDynamic);
  // Neue Listen sind zuerst dynamisch; eine feste entsteht meist über „Zu Liste hinzufügen“.
  FDynamic.Checked := FList.IsDynamic or ANew;
  FDynamic.OnClick := KindOfListClick;
  // Die Art einer bestehenden Liste bleibt: Aus fest wird nicht dynamisch (die Namen gingen verloren).
  FFixed.Enabled := ANew;
  FDynamic.Enabled := ANew;
end;

procedure TAtlasTestsListDialog.AddRuleRows;
var
  mRow: TPanel;
  mLeft: Integer;
begin
  FRules := TListBox.Create(Self);
  FRules.Parent := AddRow(cRulesHeight);
  FRules.Align := alClient;
  mRow := AddRow(cLineHeight);
  FKind := TComboBox.Create(Self);
  FKind.Parent := mRow;
  FKind.Style := csDropDownList;
  FKind.SetBounds(0, 0, ScaleValue(cKindWidth), FKind.Height);
  FKind.OnChange := KindChange;
  mLeft := FKind.Width + ScaleValue(cRowGap);
  FMode := TComboBox.Create(Self);
  FMode.Parent := mRow;
  FMode.Style := csDropDownList;
  FMode.SetBounds(mLeft, 0, ScaleValue(cModeWidth), FMode.Height);
  Inc(mLeft, FMode.Width + ScaleValue(cRowGap));
  FValue := TComboBox.Create(Self);
  FValue.Parent := mRow;
  FValue.TextHint := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogValueHint);
  FValue.SetBounds(mLeft, 0, ScaleValue(cWidth - 2 * cRowGap) - mLeft, FValue.Height);
  mRow := AddRow(cLineHeight);
  FAddRule := TButton.Create(Self);
  FAddRule.Parent := mRow;
  FAddRule.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogAddRule);
  FAddRule.SetBounds(0, 0, ScaleValue(cModeWidth), ScaleValue(cLineHeight - 2));
  FAddRule.OnClick := AddRuleClick;
  FRemoveRule := TButton.Create(Self);
  FRemoveRule.Parent := mRow;
  FRemoveRule.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogRemoveRule);
  FRemoveRule.SetBounds(FAddRule.Width + ScaleValue(cRowGap), 0, ScaleValue(cModeWidth),
    ScaleValue(cLineHeight - 2));
  FRemoveRule.OnClick := RemoveRuleClick;
end;

procedure TAtlasTestsListDialog.DoShow;
begin
  inherited DoShow;
  if FFilled then
  begin
    Exit;
  end;
  FFilled := True;
  FStore.Items.Text := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogStoreProject) + sLineBreak +
    TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogStorePersonal);
  FStore.ItemIndex := Ord(FList.Store);
  FKind.Items.Text := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogRuleCategory) + sLineBreak +
    TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogRulePattern) + sLineBreak +
    TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogRuleState);
  FKind.ItemIndex := 0;
  FMode.Items.Text := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogIs) + sLineBreak +
    TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogIsNot);
  FMode.ItemIndex := 0;
  FillValues;
  FillRules;
  KindOfListClick(nil);
end;

function TAtlasTestsListDialog.Dynamic: Boolean;
begin
  Result := FDynamic.Checked;
end;

procedure TAtlasTestsListDialog.FillRules;
var
  mRule: TAtlasTestListRule;
begin
  FRules.Items.BeginUpdate;
  try
    FRules.Items.Clear;
    for mRule in FList.Rules do
    begin
      FRules.Items.Add(TAtlasTestListText.RuleText(mRule, FTexts));
    end;
  finally
    FRules.Items.EndUpdate;
  end;
end;

procedure TAtlasTestsListDialog.FillValues;
var
  mState: TAtlasTestListState;
  mName: string;
begin
  FValue.Items.BeginUpdate;
  try
    FValue.Items.Clear;
    if FKind.ItemIndex = Ord(TAtlasTestListRuleKind.State) then
    begin
      for mState := Low(TAtlasTestListState) to High(TAtlasTestListState) do
      begin
        FValue.Items.Add(FTexts.States[mState]);
      end;
    end
    else if FKind.ItemIndex = Ord(TAtlasTestListRuleKind.Category) then
    begin
      for mName in FCategories do
      begin
        FValue.Items.Add(mName);
      end;
    end;
  finally
    FValue.Items.EndUpdate;
  end;
  FValue.Text := '';
end;

procedure TAtlasTestsListDialog.KindChange(Sender: TObject);
begin
  FillValues;
end;

procedure TAtlasTestsListDialog.KindOfListClick(Sender: TObject);
var
  mDynamic: Boolean;
begin
  mDynamic := Dynamic;
  FRules.Enabled := mDynamic;
  FKind.Enabled := mDynamic;
  FMode.Enabled := mDynamic;
  FValue.Enabled := mDynamic;
  FAddRule.Enabled := mDynamic;
  FRemoveRule.Enabled := mDynamic;
end;

procedure TAtlasTestsListDialog.AddRuleClick(Sender: TObject);
var
  mKind: TAtlasTestListRuleKind;
  mValue: string;
  mExclude: Boolean;
  mState: Integer;
begin
  mKind := TAtlasTestListRuleKind(FKind.ItemIndex);
  mValue := Trim(FValue.Text);
  mExclude := FMode.ItemIndex = 1;
  if mKind = TAtlasTestListRuleKind.State then
  begin
    mState := FValue.Items.IndexOf(mValue);
    if mState < 0 then
    begin
      FNote.ShowNote(TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogValueMissing), TAtlasSignalKind.Error);
      Exit;
    end;
    FList.Rules := FList.Rules + [TAtlasTestListRule.OfState(TAtlasTestListState(mState), mExclude)];
  end
  else if mValue = '' then
  begin
    FNote.ShowNote(TAtlasTestsStrings.Text(TAtlasTestsTextId.ListDialogValueMissing), TAtlasSignalKind.Error);
    Exit;
  end
  else if mKind = TAtlasTestListRuleKind.Category then
  begin
    FList.Rules := FList.Rules + [TAtlasTestListRule.Category(mValue, mExclude)];
  end
  else
  begin
    FList.Rules := FList.Rules + [TAtlasTestListRule.Pattern(mValue, mExclude)];
  end;
  FNote.ShowNote('', TAtlasSignalKind.Info);
  FValue.Text := '';
  FillRules;
end;

procedure TAtlasTestsListDialog.RemoveRuleClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FRules.ItemIndex;
  if (mIndex < 0) or (mIndex > High(FList.Rules)) then
  begin
    Exit;
  end;
  Delete(FList.Rules, mIndex, 1);
  FillRules;
end;

procedure TAtlasTestsListDialog.OkClick(Sender: TObject);
const
  cProblems: array[TAtlasTestListProblem] of TAtlasTestsTextId = (TAtlasTestsTextId.ListDialogOk,
    TAtlasTestsTextId.ListDialogNameMissing, TAtlasTestsTextId.ListDialogNameTaken,
    TAtlasTestsTextId.ListDialogNoRule);
var
  mProblem: TAtlasTestListProblem;
begin
  FList.Name := Trim(FName.Text);
  FList.Store := TAtlasTestListStore(FStore.ItemIndex);
  if not Dynamic then
  begin
    FList.Rules := nil;
  end;
  mProblem := TAtlasTestListText.Problem(FList, Dynamic, FTaken);
  if mProblem <> TAtlasTestListProblem.None then
  begin
    FNote.ShowNote(TAtlasTestsStrings.Fmt(cProblems[mProblem], [FList.Name]), TAtlasSignalKind.Error);
    Exit;
  end;
  ModalResult := mrOk;
end;

class function TAtlasTestsListDialog.Execute(var AList: TAtlasTestList; ANew: Boolean;
  const ATaken, ACategories: TArray<string>; const ATexts: TAtlasTestListTexts): Boolean;
var
  mDialog: TAtlasTestsListDialog;
begin
  mDialog := TAtlasTestsListDialog.CreateFor(Application, AList, ANew, ATaken, ACategories, ATexts);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AList := mDialog.FList;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
