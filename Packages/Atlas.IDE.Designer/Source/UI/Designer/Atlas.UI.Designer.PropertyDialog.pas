unit Atlas.UI.Designer.PropertyDialog;

// Dialog „Eigenschaften suchen“ (#524), reine VCL:
//   Bedingung: [Font.Name = 'Tahoma'                 v]
//   Beispiele: Font.Name = 'Tahoma' · Visible = False · …
//   (o) Aktuelles Formular  ( ) Projekt  ( ) Projektgruppe
//                                       [Suchen] [Abbrechen]
// Die Liste der Bedingung hält die letzten Suchen. Eine Bedingung, die sich
// nicht lesen lässt, hält den Dialog offen und nennt den Teil in Rot.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  {$SCOPEDENUMS ON}
  TAtlasPropertyScope = (Form, Project, Group);
  {$SCOPEDENUMS OFF}

  TAtlasPropertyOptions = record
    Query: string;
    Scope: TAtlasPropertyScope;
    /// <summary>Letzte Suchen, neueste zuerst.</summary>
    History: TArray<string>;
    /// <summary>Gibt es ein aktuelles Formular?</summary>
    HasForm: Boolean;
  end;

  TAtlasPropertyDialog = class(TForm)
  public const
    cDialogWidth = 480;
    cMaxHistory = 10;
  private
    FQuery: TComboBox;
    FError: TLabel;
    FScopes: array[TAtlasPropertyScope] of TRadioButton;
    function AddRow: TFlowPanel;
    procedure AddLabel(AParent: TWinControl; const ACaption: string);
    procedure AddScopes(const AOptions: TAtlasPropertyOptions);
    procedure AddButtons;
    procedure CheckQuery(Sender: TObject; var ACanClose: Boolean);
  public
    constructor CreateDialog(AOwner: TComponent; const AOptions: TAtlasPropertyOptions);
    function Options: TAtlasPropertyOptions;
    /// <summary>Modal zeigen; True nach „Suchen“ mit lesbarer Bedingung. AOptions.History enthält sie dann vorn.
    /// </summary>
    class function Execute(var AOptions: TAtlasPropertyOptions): Boolean; static;
    property QueryBox: TComboBox read FQuery;
    property ErrorLabel: TLabel read FError;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.Core.Designer.PropertySearch,
  Atlas.UI.Designer.Strings;

const
  cGap = 10;
  cRadioGap = 24;

{ TAtlasPropertyDialog }

constructor TAtlasPropertyDialog.CreateDialog(AOwner: TComponent; const AOptions: TAtlasPropertyOptions);
var
  mRow: TFlowPanel;
  mHistory: string;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchTitle);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  Canvas.Font := Font;
  OnCloseQuery := CheckQuery;

  mRow := AddRow;
  AddLabel(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchCondition));
  FQuery := TComboBox.Create(Self);
  FQuery.Parent := mRow;
  FQuery.Width := ScaleValue(cDialogWidth) - Canvas.TextWidth(TAtlasDesignerStrings.Text(
    TAtlasDesignerTextId.PropertySearchCondition)) - ScaleValue(cGap * 3);
  for mHistory in AOptions.History do
  begin
    FQuery.Items.Add(mHistory);
  end;
  FQuery.Text := AOptions.Query;
  mRow := AddRow;
  AddLabel(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchExamples));
  mRow := AddRow;
  FError := TLabel.Create(Self);
  FError.Parent := mRow;
  FError.Font.Color := clRed;
  FError.Caption := '';
  AddScopes(AOptions);
  AddButtons;
  ActiveControl := FQuery;
end;

function TAtlasPropertyDialog.AddRow: TFlowPanel;
begin
  Result := TFlowPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  // Hinter alle bisherigen Zeilen (alTop ordnet nach Top).
  Result.Top := ScaleValue(2000) + ComponentCount;
end;

procedure TAtlasPropertyDialog.AddLabel(AParent: TWinControl; const ACaption: string);
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := AParent;
  mLabel.Caption := ACaption;
  mLabel.AlignWithMargins := True;
  mLabel.Margins.SetBounds(0, ScaleValue(3), cGap div 2, 0);
end;

procedure TAtlasPropertyDialog.AddScopes(const AOptions: TAtlasPropertyOptions);
const
  cTexts: array[TAtlasPropertyScope] of TAtlasDesignerTextId = (TAtlasDesignerTextId.PropertySearchScopeForm,
    TAtlasDesignerTextId.PropertySearchScopeProject, TAtlasDesignerTextId.PropertySearchScopeGroup);
var
  mRow: TFlowPanel;
  mScope: TAtlasPropertyScope;
  mRadio: TRadioButton;
begin
  mRow := AddRow;
  for mScope := Low(TAtlasPropertyScope) to High(TAtlasPropertyScope) do
  begin
    mRadio := TRadioButton.Create(Self);
    mRadio.Parent := mRow;
    mRadio.Caption := TAtlasDesignerStrings.Text(cTexts[mScope]);
    mRadio.Width := Canvas.TextWidth(mRadio.Caption) + ScaleValue(cRadioGap);
    mRadio.AlignWithMargins := True;
    mRadio.Margins.SetBounds(0, 0, cGap, 0);
    FScopes[mScope] := mRadio;
  end;
  FScopes[TAtlasPropertyScope.Form].Enabled := AOptions.HasForm;
  mScope := AOptions.Scope;
  if (mScope = TAtlasPropertyScope.Form) and not AOptions.HasForm then
  begin
    mScope := TAtlasPropertyScope.Project;
  end;
  FScopes[mScope].Checked := True;
end;

procedure TAtlasPropertyDialog.AddButtons;
var
  mButtons: TFlowPanel;
  mButton: TButton;
begin
  mButtons := AddRow;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchRun);
  mButton.Default := True;
  mButton.ModalResult := mrOk;
  mButton.AlignWithMargins := True;
  mButton.Margins.SetBounds(0, 0, cGap, 0);
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
  ClientHeight := mButtons.Top + mButtons.Height + cGap;
end;

procedure TAtlasPropertyDialog.CheckQuery(Sender: TObject; var ACanClose: Boolean);
var
  mQuery: TAtlasPropertyQuery;
begin
  if ModalResult <> mrOk then
  begin
    Exit;
  end;
  mQuery := TAtlasPropertyQuery.Parse(FQuery.Text);
  ACanClose := mQuery.Valid;
  if not ACanClose then
  begin
    FError.Caption := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.PropertySearchInvalid, [Trim(mQuery.Invalid)]);
    ActiveControl := FQuery;
  end;
end;

function TAtlasPropertyDialog.Options: TAtlasPropertyOptions;
var
  mScope: TAtlasPropertyScope;
  mIndex: Integer;
begin
  Result := Default(TAtlasPropertyOptions);
  Result.Query := Trim(FQuery.Text);
  Result.HasForm := FScopes[TAtlasPropertyScope.Form].Enabled;
  for mScope := Low(TAtlasPropertyScope) to High(TAtlasPropertyScope) do
  begin
    if FScopes[mScope].Checked then
    begin
      Result.Scope := mScope;
    end;
  end;
  // Die Suche vorn, ohne Doppelte, höchstens cMaxHistory.
  Result.History := [Result.Query];
  for mIndex := 0 to FQuery.Items.Count - 1 do
  begin
    if (Length(Result.History) < cMaxHistory) and not SameText(FQuery.Items[mIndex], Result.Query) then
    begin
      Result.History := Result.History + [FQuery.Items[mIndex]];
    end;
  end;
end;

class function TAtlasPropertyDialog.Execute(var AOptions: TAtlasPropertyOptions): Boolean;
var
  mDialog: TAtlasPropertyDialog;
begin
  mDialog := TAtlasPropertyDialog.CreateDialog(nil, AOptions);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AOptions := mDialog.Options;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
