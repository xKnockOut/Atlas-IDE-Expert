unit Atlas.UI.Tests.FromDebugStop;

// Dialog „Test aus dem Debug-Halt“ (#1873), reine VCL:
//   Test für TGewicht.Parse aus dem Halt in Gewicht.pas:42
//   Werte aus dem Halt (abgewählte bleiben Platzhalter):
//   [x] AText = '12.5 kg'
//   [x] FEinheit (Feld) = 'kg'
//   [ ] FListe (Feld) = TODO, wird nicht übernommen
//   (•) Soll funktionieren   ( ) Soll EConvertError werfen
//   Erwartetes Ergebnis (Double; leer = Platzhalter): [        ]
//   Name des Tests: [ParseMit12_5Kg]
//   Testunit: Gewicht.Tests
//                                        [Test anlegen] [Abbrechen]
// Zeilen ohne gelesenen Wert sind gesperrt. „Soll … werfen“ gibt es nur,
// wenn das Programm an einer Exception steht; das erwartete Ergebnis nur bei
// Funktionen und solange der Test funktionieren soll. Den Server fragt die
// IDE-Schicht.

interface

uses
  System.Classes,
  Vcl.StdCtrls,
  Vcl.CheckLst,
  Atlas.Core.Tests.FromDebugStop,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasTestFromDebugDialog = class(TAtlasDialog)
  private
    FDescription: TAtlasStopDescription;
    FChoice: TAtlasStopChoice;
    FValues: TCheckListBox;
    FWorks: TRadioButton;
    FRaises: TRadioButton;
    FExpected: TEdit;
    FName: TEdit;
    FCreate: TButton;
    procedure CreateValues(const ALocation: string);
    procedure CreateKind;
    procedure CreateNameAndUnit;
    procedure KindClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    /// <summary>Dialog zu ADescription (Zeilen mit Vorauswahl) und AChoice (Exception, Vorgaben); ALocation ist
    /// „Datei:Zeile“ des Halts.</summary>
    constructor CreateDialog(AOwner: TComponent; const ADescription: TAtlasStopDescription;
      const AChoice: TAtlasStopChoice; const ALocation: string);
    /// <summary>Liste füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded).</summary>
    procedure Fill;
    /// <summary>Beschreibung mit der Auswahl der Liste.</summary>
    function Description: TAtlasStopDescription;
    /// <summary>Art, erwarteter Wert und Name aus dem Dialog.</summary>
    function Choice: TAtlasStopChoice;
    /// <summary>Text einer Zeile der Liste.</summary>
    class function RowCaption(const ARow: TAtlasStopValueRow): string; static;
    /// <summary>True mit „Test anlegen“; Auswahl dann in ADescription und AChoice.</summary>
    class function Execute(var ADescription: TAtlasStopDescription; var AChoice: TAtlasStopChoice;
      const ALocation: string): Boolean; static;
    property ValueList: TCheckListBox read FValues;
    property WorksButton: TRadioButton read FWorks;
    property RaisesButton: TRadioButton read FRaises;
    property ExpectedEdit: TEdit read FExpected;
    property NameEdit: TEdit read FName;
    property CreateButton: TButton read FCreate;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.UITypes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.UI.Tests.Strings;

const
  cDialogWidth = 520;
  cRowHeight = 26;
  cLabelWidth = 150;
  cListRows = 6;
  cListRowHeight = 20;

{ TAtlasTestFromDebugDialog }

constructor TAtlasTestFromDebugDialog.CreateDialog(AOwner: TComponent; const ADescription: TAtlasStopDescription;
  const AChoice: TAtlasStopChoice; const ALocation: string);
var
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugTitle), cDialogWidth);
  FDescription := ADescription;
  FChoice := AChoice;
  CreateValues(ALocation);
  CreateKind;
  CreateNameAndUnit;
  mButtons := AddButtonRow;
  FCreate := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugCreate),
    TAtlasButtonKind.Default);
  FCreate.ModalResult := mrOk;
  mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  AllowResize(FValues);
  KindClick(nil);
  ActiveControl := FName;
end;

/// <summary>Überschrift und Liste der Werte.</summary>
procedure TAtlasTestFromDebugDialog.CreateValues(const ALocation: string);
var
  mRow: TPanel;
begin
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFromDebugTarget, [FDescription.Target,
    ALocation])).Font.Style := [fsBold];
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugValues));
  FValues := TCheckListBox.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FValues.Top := NextTop;
  FValues.Height := ScaleValue(cListRows * cListRowHeight);
  FValues.AlignWithMargins := True;
  FValues.Margins.SetBounds(ScaleValue(cRowGap), 0, ScaleValue(cRowGap), 0);
  FValues.Align := alTop;
  FValues.Parent := Self;
end;

/// <summary>Art des Tests und erwartetes Ergebnis.</summary>
procedure TAtlasTestFromDebugDialog.CreateKind;
var
  mRow: TPanel;
begin
  mRow := AddRow(cRowHeight);
  FWorks := TRadioButton.Create(Self);
  FWorks.Parent := mRow;
  FWorks.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugWorks);
  FWorks.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowLabelTop), ScaleValue(cLabelWidth), ScaleValue(18));
  FWorks.Checked := not FChoice.Raises;
  FWorks.OnClick := KindClick;
  FRaises := TRadioButton.Create(Self);
  FRaises.Parent := mRow;
  FRaises.Caption := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFromDebugRaises, [FChoice.ExceptionClass]);
  FRaises.SetBounds(ScaleValue(cRowGap + cLabelWidth + cRowGap), ScaleValue(cRowLabelTop),
    ScaleValue(cDialogWidth - cLabelWidth - 3 * cRowGap), ScaleValue(18));
  FRaises.Checked := FChoice.Raises;
  FRaises.Enabled := FChoice.ExceptionClass <> '';
  FRaises.Visible := FChoice.ExceptionClass <> '';
  FRaises.OnClick := KindClick;
  FExpected := TEdit.Create(Self);
  if FDescription.ResultType = '' then
  begin
    Exit;
  end;
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFromDebugExpected, [FDescription.ResultType]));
  mRow := AddRow(cRowHeight);
  FExpected.Parent := mRow;
  FExpected.SetBounds(ScaleValue(cRowGap), 0, ScaleValue(cDialogWidth - 2 * cRowGap), ScaleValue(22));
  FExpected.Text := FChoice.Expected;
  FitRight(FExpected);
end;

/// <summary>Name des Tests und die Testunit.</summary>
procedure TAtlasTestFromDebugDialog.CreateNameAndUnit;
var
  mRow: TPanel;
  mUnit: TAtlasTestsTextId;
begin
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugName));
  FName := TEdit.Create(Self);
  FName.Parent := mRow;
  FName.SetBounds(ScaleValue(cLabelWidth), 0, ScaleValue(cDialogWidth - cLabelWidth - cRowGap), ScaleValue(22));
  FName.Text := FDescription.TestName;
  FitRight(FName);
  mUnit := TAtlasTestsTextId.TestsFromDebugNewUnit;
  if FDescription.TestUnitExists then
  begin
    mUnit := TAtlasTestsTextId.TestsFromDebugUnit;
  end;
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasTestsStrings.Fmt(mUnit, [FDescription.TestUnit]));
end;

procedure TAtlasTestFromDebugDialog.KindClick(Sender: TObject);
begin
  FExpected.Enabled := FWorks.Checked;
end;

procedure TAtlasTestFromDebugDialog.DoShow;
begin
  inherited DoShow;
  Fill;
end;

class function TAtlasTestFromDebugDialog.RowCaption(const ARow: TAtlasStopValueRow): string;
var
  mValue: string;
begin
  Result := ARow.Name;
  if ARow.Field then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFromDebugField, [ARow.Name]);
  end;
  if ARow.Text = '' then
  begin
    mValue := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugUnread);
  end
  else if ARow.Todo then
  begin
    mValue := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugTodo);
  end
  else if ARow.Literal <> '' then
  begin
    mValue := ARow.Literal;
  end
  else
  begin
    mValue := ARow.Text;
  end;
  Result := Result + ': ' + ARow.TypeName + ' = ' + mValue;
end;

procedure TAtlasTestFromDebugDialog.Fill;
var
  mIndex: Integer;
begin
  if FValues.Items.Count > 0 then
  begin
    Exit;
  end;
  FValues.Items.BeginUpdate;
  try
    for mIndex := 0 to High(FDescription.Rows) do
    begin
      FValues.Items.Add(RowCaption(FDescription.Rows[mIndex]));
      FValues.Checked[mIndex] := FDescription.Rows[mIndex].Chosen;
      FValues.ItemEnabled[mIndex] := FDescription.Rows[mIndex].Text <> '';
    end;
  finally
    FValues.Items.EndUpdate;
  end;
end;

function TAtlasTestFromDebugDialog.Description: TAtlasStopDescription;
var
  mIndex: Integer;
begin
  Result := FDescription;
  for mIndex := 0 to Min(High(Result.Rows), FValues.Items.Count - 1) do
  begin
    Result.Rows[mIndex].Chosen := FValues.Checked[mIndex] and (Result.Rows[mIndex].Text <> '');
  end;
end;

function TAtlasTestFromDebugDialog.Choice: TAtlasStopChoice;
begin
  Result := FChoice;
  Result.Raises := FRaises.Checked and (FChoice.ExceptionClass <> '');
  Result.Expected := '';
  if not Result.Raises then
  begin
    Result.Expected := Trim(FExpected.Text);
  end;
  Result.TestName := Trim(FName.Text);
end;

class function TAtlasTestFromDebugDialog.Execute(var ADescription: TAtlasStopDescription;
  var AChoice: TAtlasStopChoice; const ALocation: string): Boolean;
var
  mDialog: TAtlasTestFromDebugDialog;
begin
  mDialog := TAtlasTestFromDebugDialog.CreateDialog(Application, ADescription, AChoice, ALocation);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      ADescription := mDialog.Description;
      AChoice := mDialog.Choice;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
