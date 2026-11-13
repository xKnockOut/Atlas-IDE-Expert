unit Atlas.UI.Debug.EditValueDialog;

// Eingabe eines neuen Werts beim Debuggen (#868), reine VCL:
//   - Oben der jetzige Wert und der Typ.
//   - Eingabe nach Art (TAtlasEditInfo): Aufzählungen und Booleans als
//     Auswahlliste, Mengen mit einem Häkchen je Wert (bis cMaxSetBoxes Werte,
//     darüber als Text), Farben als Text mit „Farbe wählen …“, sonst Text.
//   - Jede Änderung prüft TAtlasEditValue.Check: Ungültige Eingaben stehen rot
//     unter dem Feld, der Grund auch im Tooltip; „Ändern“ ist dann aus.
//   - Ruft das Ändern einen Setter auf, steht das als Warnung darunter.
//   - Enter übernimmt, Esc bricht ab. Aufgebaut im Code (keine DFM).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.EditValue,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasEditValueDialog = class(TAtlasDialog)
  public const
    /// <summary>Mehr Werte einer Menge kommen als Text statt als Häkchen.</summary>
    cMaxSetBoxes = 24;
  private
    FInfo: TAtlasEditInfo;
    FOldValue: string;
    FEdit: TEdit;
    FChoice: TComboBox;
    FBoxes: TArray<TCheckBox>;
    FNote: TAtlasNoteLabel;
    FApply: TButton;
    FCheck: TAtlasEditCheck;
    procedure InputChange(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure ColorClick(Sender: TObject);
    function Choices: TArray<string>;
    function Input: string;
    procedure AddInput;
    procedure AddBoxes;
  protected
    procedure DoShow; override;
  public
    constructor CreateFor(AOwner: TComponent; const AInfo: TAtlasEditInfo; const AOldValue: string);
    /// <summary>Text zum Problem in ACheck; '' ohne.</summary>
    class function ProblemText(const ACheck: TAtlasEditCheck): string; static;
    /// <summary>Modal zeigen; True mit dem geprüften Text für das Ändern in AValue.</summary>
    class function Execute(const AInfo: TAtlasEditInfo; const AOldValue: string; out AValue: string): Boolean;
      static;
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.Strings;

const
  cWidth = 420;
  cRowHeight = 26;
  cNoteHeight = 36;
  cBoxHeight = 22;
  cColorButtonWidth = 120;
  cTrue = 'True';
  cFalse = 'False';

{ TAtlasEditValueDialog }

constructor TAtlasEditValueDialog.CreateFor(AOwner: TComponent; const AInfo: TAtlasEditInfo;
  const AOldValue: string);
var
  mHead: TAtlasNoteLabel;
  mButtons: TAtlasButtonRow;
  mText: string;
begin
  inherited CreateDialog(AOwner, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueTitle, [AInfo.Expression]),
    cWidth);
  FInfo := AInfo;
  FOldValue := AOldValue;
  mHead := AddNote(cRowHeight);
  mText := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueCurrent, [AOldValue]);
  if AInfo.TypeName <> '' then
  begin
    mText := mText + ' · ' + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueType, [AInfo.TypeName]);
  end;
  mHead.ShowNote(mText, TAtlasSignalKind.Idle);
  AddInput;
  FNote := AddNote(cNoteHeight);
  FNote.WordWrap := True;
  mButtons := AddButtonRow;
  FApply := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueApply), TAtlasButtonKind.Default);
  FApply.ModalResult := mrNone;
  FApply.OnClick := ApplyClick;
  mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueCancel), TAtlasButtonKind.Cancel);
  FitHeight;
end;

function TAtlasEditValueDialog.Choices: TArray<string>;
begin
  Result := nil;
  if FInfo.Kind = TAtlasEditKind.Boolean_ then
  begin
    Result := TArray<string>.Create(cFalse, cTrue);
  end
  else if FInfo.Kind = TAtlasEditKind.Enum then
  begin
    Result := FInfo.Values;
  end;
end;

procedure TAtlasEditValueDialog.AddInput;
var
  mRow: TPanel;
  mColor: TButton;
begin
  if (FInfo.Kind = TAtlasEditKind.Set_) and (Length(FInfo.Values) > 0) and
    (Length(FInfo.Values) <= cMaxSetBoxes) then
  begin
    AddBoxes;
    Exit;
  end;
  mRow := AddRow(cRowHeight);
  if Length(Choices) > 0 then
  begin
    // Die Einträge kommen in DoShow: Die Liste braucht ein Fenster.
    FChoice := TComboBox.Create(Self);
    FChoice.Parent := mRow;
    FChoice.Style := csDropDownList;
    FChoice.Width := mRow.Width;
    FChoice.OnChange := InputChange;
    FitRight(FChoice);
    ActiveControl := FChoice;
    Exit;
  end;
  FEdit := TEdit.Create(Self);
  FEdit.Parent := mRow;
  FEdit.Width := mRow.Width;
  FEdit.Text := FOldValue;
  FEdit.ShowHint := True;
  FEdit.OnChange := InputChange;
  if FInfo.Kind = TAtlasEditKind.Color then
  begin
    mColor := TButton.Create(Self);
    mColor.Parent := mRow;
    mColor.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueChooseColor);
    mColor.Width := ScaleValue(cColorButtonWidth);
    mColor.Left := mRow.Width - mColor.Width;
    mColor.Anchors := [akTop, akRight];
    mColor.OnClick := ColorClick;
    FEdit.Width := mColor.Left - ScaleValue(cRowHeight div 2);
  end
  else
  begin
    FitRight(FEdit);
  end;
  ActiveControl := FEdit;
end;

procedure TAtlasEditValueDialog.AddBoxes;
var
  mValue, mItem: string;
  mBox: TCheckBox;
  mOld: TArray<string>;
begin
  mOld := TAtlasEditValue.SetItems(FOldValue);
  for mValue in FInfo.Values do
  begin
    mBox := TCheckBox.Create(Self);
    mBox.Parent := AddRow(cBoxHeight);
    mBox.Caption := mValue;
    mBox.Align := alClient;
    for mItem in mOld do
    begin
      if SameText(mItem, mValue) or SameText(mItem, FInfo.Prefix + mValue) then
      begin
        mBox.Checked := True;
      end;
    end;
    mBox.OnClick := InputChange;
    FBoxes := FBoxes + [mBox];
  end;
end;

procedure TAtlasEditValueDialog.DoShow;
var
  mValue: string;
  mIndex: Integer;
begin
  inherited DoShow;
  if (FChoice <> nil) and (FChoice.Items.Count = 0) then
  begin
    FChoice.Items.BeginUpdate;
    try
      for mValue in Choices do
      begin
        FChoice.Items.Add(mValue);
      end;
    finally
      FChoice.Items.EndUpdate;
    end;
    // Den jetzigen Wert vorwählen (ohne Typpräfix, wie der Debugger ihn zeigt).
    mIndex := FChoice.Items.IndexOf(FOldValue);
    if (mIndex < 0) and FOldValue.StartsWith(FInfo.Prefix) then
    begin
      mIndex := FChoice.Items.IndexOf(Copy(FOldValue, Length(FInfo.Prefix) + 1, MaxInt));
    end;
    FChoice.ItemIndex := mIndex;
  end;
  InputChange(nil);
end;

function TAtlasEditValueDialog.Input: string;
var
  mBox: TCheckBox;
  mNames: TArray<string>;
begin
  if FChoice <> nil then
  begin
    Exit(FChoice.Text);
  end;
  if FEdit <> nil then
  begin
    Exit(FEdit.Text);
  end;
  mNames := nil;
  for mBox in FBoxes do
  begin
    if mBox.Checked then
    begin
      mNames := mNames + [mBox.Caption];
    end;
  end;
  Result := TAtlasEditValue.SetText(FInfo, mNames);
end;

class function TAtlasEditValueDialog.ProblemText(const ACheck: TAtlasEditCheck): string;
begin
  case ACheck.Problem of
    TAtlasEditProblem.Empty:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueEmpty);
    TAtlasEditProblem.NotInteger:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueNotInteger, [ACheck.Detail]);
    TAtlasEditProblem.OutOfRange:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueOutOfRange, [ACheck.Detail]);
    TAtlasEditProblem.NotFloat:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueNotFloat, [ACheck.Detail]);
    TAtlasEditProblem.NotBoolean:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueNotBoolean);
    TAtlasEditProblem.NotChar:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueNotChar, [ACheck.Detail]);
    TAtlasEditProblem.UnknownValue:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueUnknown, [ACheck.Detail]);
    TAtlasEditProblem.ReadOnly:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueReadOnly, [ACheck.Detail]);
  else
    Result := '';
  end;
end;

procedure TAtlasEditValueDialog.InputChange(Sender: TObject);
var
  mProblem: string;
begin
  FCheck := TAtlasEditValue.Check(FInfo, Input);
  mProblem := ProblemText(FCheck);
  if mProblem <> '' then
  begin
    FNote.ShowNote(mProblem, TAtlasSignalKind.Error);
  end
  else if FInfo.Setter <> '' then
  begin
    FNote.ShowNote(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EditValueSetter, [FInfo.Setter]), TAtlasSignalKind.Warn);
  end
  else
  begin
    FNote.ShowNote('', TAtlasSignalKind.Idle);
  end;
  if FEdit <> nil then
  begin
    FEdit.Hint := mProblem;
  end;
  FApply.Enabled := FCheck.Ok;
end;

procedure TAtlasEditValueDialog.ApplyClick(Sender: TObject);
begin
  if FApply.Enabled then
  begin
    ModalResult := mrOk;
  end;
end;

procedure TAtlasEditValueDialog.ColorClick(Sender: TObject);
var
  mDialog: TColorDialog;
  mColor: Integer;
begin
  mDialog := TColorDialog.Create(Self);
  try
    if TAtlasEditValue.ColorOf(FEdit.Text, mColor) then
    begin
      mDialog.Color := mColor;
    end;
    if mDialog.Execute(Handle) then
    begin
      FEdit.Text := TAtlasEditValue.ColorText(mDialog.Color);
    end;
  finally
    mDialog.Free;
  end;
end;

class function TAtlasEditValueDialog.Execute(const AInfo: TAtlasEditInfo; const AOldValue: string;
  out AValue: string): Boolean;
var
  mDialog: TAtlasEditValueDialog;
begin
  AValue := '';
  mDialog := TAtlasEditValueDialog.CreateFor(nil, AInfo, AOldValue);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AValue := mDialog.FCheck.Value;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
