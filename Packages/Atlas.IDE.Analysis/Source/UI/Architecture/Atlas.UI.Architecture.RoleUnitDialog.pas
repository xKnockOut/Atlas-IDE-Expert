unit Atlas.UI.Architecture.RoleUnitDialog;

// Dialog des Assistenten „Unit nach Architekturrolle“ (#1821), reine VCL:
// Ausgabeartefakt (Auswahl aus den Präfixen der Projektdatei oder frei),
// Feature, Rolle, Sache; darunter laufend der Name der Unit, was die Rolle
// importieren darf, und bei falschen Angaben der Grund
// (Atlas.Core.Architecture.RoleUnit). „Anlegen“ schließt nur mit gültigen
// Angaben. Aufgebaut im Code (keine DFM).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.Core.Architecture.RoleUnit;

type
  TAtlasRoleUnitDialog = class(TForm)
  private
    FPrefix: TComboBox;
    FFeature: TEdit;
    FRole: TComboBox;
    FThing: TEdit;
    FPreview: TLabel;
    FOwn: TLabel;
    FForeign: TLabel;
    FMessage: TLabel;
    FCreate: TButton;
    FCancel: TButton;
    procedure InputChange(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    function GetInput: TAtlasRoleUnitInput;
    procedure SetInput(const AValue: TAtlasRoleUnitInput);
    procedure ShowState;
  public
    constructor CreateDialog(AOwner: TComponent; const APrefixes: TArray<string>);
    /// <summary>Text zu AProblem; '' für None.</summary>
    class function ProblemText(AProblem: TAtlasRoleUnitProblem): string; static;
    /// <summary>Zeilen „darf importieren“ zu ARole.</summary>
    class procedure ImportTexts(ARole: TAtlasArchitectureRole; out AOwn, AForeign: string); static;
    /// <summary>Modal zeigen; True mit AInput, wenn „Anlegen“ mit gültigen Angaben gewählt wurde.</summary>
    class function Execute(const APrefixes: TArray<string>; var AInput: TAtlasRoleUnitInput): Boolean; static;
    property Input: TAtlasRoleUnitInput read GetInput write SetInput;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.UI.Analysis.Strings;

const
  cGap = 12;
  cLabelWidth = 130;
  cEditWidth = 320;
  cSpacing = 8;

type
  /// <summary>Abstände nach CurrentPPI.</summary>
  TDialogLayout = record
    Gap: Integer;
    LabelWidth: Integer;
    EditWidth: Integer;
    Spacing: Integer;
  end;

function LayoutOf(ADialog: TForm): TDialogLayout;
begin
  Result.Gap := MulDiv(cGap, ADialog.CurrentPPI, 96);
  Result.LabelWidth := MulDiv(cLabelWidth, ADialog.CurrentPPI, 96);
  Result.EditWidth := MulDiv(cEditWidth, ADialog.CurrentPPI, 96);
  Result.Spacing := MulDiv(cSpacing, ADialog.CurrentPPI, 96);
end;

procedure AddLabel(ADialog: TForm; const ALayout: TDialogLayout; AText: TAtlasAnalysisTextId; AFocus: TWinControl);
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(ADialog);
  mLabel.Parent := ADialog;
  mLabel.Left := ALayout.Gap;
  mLabel.Top := AFocus.Top + MulDiv(3, ADialog.CurrentPPI, 96);
  mLabel.Caption := TAtlasAnalysisStrings.Text(AText);
  mLabel.FocusControl := AFocus;
end;

function NewInfo(ADialog: TForm; const ALayout: TDialogLayout; var AY: Integer): TLabel;
begin
  Result := TLabel.Create(ADialog);
  Result.Parent := ADialog;
  Result.ShowAccelChar := False;
  Result.SetBounds(ALayout.Gap, AY, ALayout.LabelWidth + ALayout.EditWidth, Result.Height);
  Inc(AY, Result.Height + MulDiv(4, ADialog.CurrentPPI, 96));
end;

/// <summary>Felder Ausgabeartefakt, Feature, Rolle und Sache ab AY.</summary>
procedure BuildFields(ADialog: TAtlasRoleUnitDialog; const ALayout: TDialogLayout; const APrefixes: TArray<string>;
  var AY: Integer; out APrefix: TComboBox; out AFeature: TEdit; out ARole: TComboBox; out AThing: TEdit);
var
  mPrefix: string;
  mRole: TAtlasArchitectureRole;
begin
  APrefix := TComboBox.Create(ADialog);
  APrefix.Parent := ADialog;
  APrefix.SetBounds(ALayout.Gap + ALayout.LabelWidth, AY, ALayout.EditWidth, APrefix.Height);
  for mPrefix in APrefixes do
  begin
    APrefix.Items.Add(mPrefix);
  end;
  AddLabel(ADialog, ALayout, TAtlasAnalysisTextId.RoleUnitPrefix, APrefix);
  Inc(AY, APrefix.Height + ALayout.Spacing);
  AFeature := TEdit.Create(ADialog);
  AFeature.Parent := ADialog;
  AFeature.SetBounds(ALayout.Gap + ALayout.LabelWidth, AY, ALayout.EditWidth, AFeature.Height);
  AddLabel(ADialog, ALayout, TAtlasAnalysisTextId.RoleUnitFeature, AFeature);
  Inc(AY, AFeature.Height + ALayout.Spacing);
  ARole := TComboBox.Create(ADialog);
  ARole.Parent := ADialog;
  ARole.Style := csDropDownList;
  ARole.SetBounds(ALayout.Gap + ALayout.LabelWidth, AY, ALayout.EditWidth, ARole.Height);
  for mRole := Low(TAtlasArchitectureRole) to High(TAtlasArchitectureRole) do
  begin
    if mRole = TAtlasArchitectureRole.Root then
    begin
      ARole.Items.Add(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.RoleUnitRoot));
    end
    else
    begin
      ARole.Items.Add(TAtlasRoleUnit.RoleName(mRole));
    end;
  end;
  AddLabel(ADialog, ALayout, TAtlasAnalysisTextId.RoleUnitRole, ARole);
  Inc(AY, ARole.Height + ALayout.Spacing);
  AThing := TEdit.Create(ADialog);
  AThing.Parent := ADialog;
  AThing.SetBounds(ALayout.Gap + ALayout.LabelWidth, AY, ALayout.EditWidth, AThing.Height);
  AddLabel(ADialog, ALayout, TAtlasAnalysisTextId.RoleUnitThing, AThing);
  Inc(AY, AThing.Height + ALayout.Spacing * 2);
end;

constructor TAtlasRoleUnitDialog.CreateDialog(AOwner: TComponent; const APrefixes: TArray<string>);
var
  mLayout: TDialogLayout;
  mY: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.RoleUnitCommand);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  mLayout := LayoutOf(Self);
  ClientWidth := mLayout.Gap * 2 + mLayout.LabelWidth + mLayout.EditWidth;
  mY := mLayout.Gap;
  BuildFields(Self, mLayout, APrefixes, mY, FPrefix, FFeature, FRole, FThing);
  FPreview := NewInfo(Self, mLayout, mY);
  FPreview.Font.Style := [fsBold];
  FOwn := NewInfo(Self, mLayout, mY);
  FForeign := NewInfo(Self, mLayout, mY);
  FMessage := NewInfo(Self, mLayout, mY);
  FMessage.Font.Color := clRed;
  Inc(mY, mLayout.Spacing);
  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.RoleUnitCancel);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.Top := mY;
  FCancel.Left := ClientWidth - mLayout.Gap - FCancel.Width;
  FCreate := TButton.Create(Self);
  FCreate.Parent := Self;
  FCreate.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.RoleUnitCreate);
  FCreate.Default := True;
  FCreate.Top := mY;
  FCreate.Left := FCancel.Left - mLayout.Spacing - FCreate.Width;
  FCreate.OnClick := CreateClick;
  ClientHeight := mY + FCreate.Height + mLayout.Gap;
  FPrefix.OnChange := InputChange;
  FFeature.OnChange := InputChange;
  FRole.OnChange := InputChange;
  FThing.OnChange := InputChange;
  ActiveControl := FFeature;
end;

class function TAtlasRoleUnitDialog.ProblemText(AProblem: TAtlasRoleUnitProblem): string;
const
  cIds: array[TAtlasRoleUnitProblem] of TAtlasAnalysisTextId = (TAtlasAnalysisTextId.RoleUnitPreview,
    TAtlasAnalysisTextId.RoleUnitNoPrefix, TAtlasAnalysisTextId.RoleUnitBadPrefix,
    TAtlasAnalysisTextId.RoleUnitNoFeature, TAtlasAnalysisTextId.RoleUnitBadFeature,
    TAtlasAnalysisTextId.RoleUnitReservedFeature, TAtlasAnalysisTextId.RoleUnitBadThing,
    TAtlasAnalysisTextId.RoleUnitReservedThing);
begin
  Result := '';
  if AProblem <> TAtlasRoleUnitProblem.None then
  begin
    Result := TAtlasAnalysisStrings.Text(cIds[AProblem]);
  end;
end;

class procedure TAtlasRoleUnitDialog.ImportTexts(ARole: TAtlasArchitectureRole; out AOwn, AForeign: string);
var
  mOwn, mForeign: TArray<TAtlasArchitectureRole>;
  mRoot: string;
begin
  TAtlasRoleUnit.Imports(ARole, mOwn, mForeign);
  mRoot := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.RoleUnitRootShort);
  AOwn := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.RoleUnitOwn, [TAtlasRoleUnit.RoleList(mOwn, mRoot)]);
  AForeign := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.RoleUnitForeign,
    [TAtlasRoleUnit.RoleList(mForeign, mRoot)]);
end;

function TAtlasRoleUnitDialog.GetInput: TAtlasRoleUnitInput;
begin
  Result.Prefix := Trim(FPrefix.Text);
  Result.Feature := Trim(FFeature.Text);
  Result.Role := TAtlasArchitectureRole.Root;
  if FRole.ItemIndex > 0 then
  begin
    Result.Role := TAtlasArchitectureRole(FRole.ItemIndex);
  end;
  Result.Thing := Trim(FThing.Text);
end;

procedure TAtlasRoleUnitDialog.SetInput(const AValue: TAtlasRoleUnitInput);
begin
  FPrefix.Text := AValue.Prefix;
  FFeature.Text := AValue.Feature;
  FRole.ItemIndex := Ord(AValue.Role);
  FThing.Text := AValue.Thing;
  ShowState;
end;

procedure TAtlasRoleUnitDialog.ShowState;
var
  mInput: TAtlasRoleUnitInput;
  mOwn, mForeign: string;
begin
  mInput := GetInput;
  FPreview.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.RoleUnitPreview,
    [TAtlasRoleUnit.UnitName(mInput)]);
  ImportTexts(mInput.Role, mOwn, mForeign);
  FOwn.Caption := mOwn;
  FForeign.Caption := mForeign;
  FMessage.Caption := '';
end;

procedure TAtlasRoleUnitDialog.InputChange(Sender: TObject);
begin
  ShowState;
end;

procedure TAtlasRoleUnitDialog.CreateClick(Sender: TObject);
var
  mProblem: TAtlasRoleUnitProblem;
begin
  mProblem := TAtlasRoleUnit.Check(GetInput);
  if mProblem = TAtlasRoleUnitProblem.None then
  begin
    ModalResult := mrOk;
    Exit;
  end;
  FMessage.Caption := ProblemText(mProblem);
  case mProblem of
    TAtlasRoleUnitProblem.NoPrefix, TAtlasRoleUnitProblem.BadPrefix:
      ActiveControl := FPrefix;
    TAtlasRoleUnitProblem.NoFeature, TAtlasRoleUnitProblem.BadFeature, TAtlasRoleUnitProblem.ReservedFeature:
      ActiveControl := FFeature;
  else
    ActiveControl := FThing;
  end;
end;

class function TAtlasRoleUnitDialog.Execute(const APrefixes: TArray<string>; var AInput: TAtlasRoleUnitInput): Boolean;
var
  mDialog: TAtlasRoleUnitDialog;
begin
  mDialog := TAtlasRoleUnitDialog.CreateDialog(Application, APrefixes);
  try
    mDialog.Input := AInput;
    if mDialog.FPrefix.Text = '' then
    begin
      mDialog.ActiveControl := mDialog.FPrefix;
    end;
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AInput := mDialog.Input;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
