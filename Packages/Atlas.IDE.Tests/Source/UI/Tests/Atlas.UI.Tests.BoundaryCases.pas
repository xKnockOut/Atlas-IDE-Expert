unit Atlas.UI.Tests.BoundaryCases;

// Fenster „Grenzfälle von <Routine>“ (#2173), ohne Open Tools API:
//   Nehmen | Name        | AMenge: Integer | AKunde: TKunde | Erwartet: Integer | Grund
//   ✓      | AMenge 99   | 99              | Normal         |                   | AMenge >= 100: knapp darunter
//   ✓      | AMenge 100  | 100             | Normal         | 5                 | AMenge >= 100: genau darauf
//   –      | AKunde nil  | 0               | nil            |                   | passt in kein [TestCase]
//   Hinweis bzw. Grund der Sperre                 [Übernehmen] [Heutiges Ergebnis übernehmen] [Schließen]
// Name und Erwartet sind bearbeitbar, Leertaste oder Doppelklick in einer Zeile wählt den Fall. Die Spalte
// Erwartet gibt es nur bei Funktionen. Übernehmen verlangt bei Funktionen für jeden gewählten Fall einen Wert;
// „Heutiges Ergebnis übernehmen“ lässt offene Werte zu (das Modul trägt das Ergebnis eines Laufs ein) und ist mit
// einem Grund gesperrt, wenn es kein Testprojekt gibt. Das Fenster schreibt nichts: ModalResult mrOk =
// Übernehmen, mrYes = Heutiges Ergebnis; die gewählten Fälle stehen in Cases.

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Grids,
  Atlas.Core.Tests.BoundaryCases,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasTestsBoundaryDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 860;
    cGridHeight = 300;
    cNoteHeight = 40;
    cUseWidth = 56;
    cNameWidth = 130;
    cValueWidth = 100;
    cReasonWidth = 260;
    cUseMark = '✓';
    cNoUseMark = '–';
  private
    FSuggestion: TAtlasBoundarySuggestion;
    FTodayLock: string;
    FGrid: TStringGrid;
    FNote: TAtlasNoteLabel;
    FApply: TButton;
    FToday: TButton;
    FFilling: Boolean;
    function ExpectedColumn: Integer;
    function ReasonColumn: Integer;
    function Editable(ACol: Integer): Boolean;
    function ReasonText(const ACase: TAtlasBoundaryCase): string;
    procedure Fill;
    procedure FillUse(AIndex: Integer);
    procedure Toggle(AIndex: Integer);
    function ChosenCount: Integer;
    function MissingExpected: Boolean;
    procedure UpdateState;
    procedure GridSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    procedure GridDblClick(Sender: TObject);
    procedure GridKeyPress(Sender: TObject; var Key: Char);
    procedure ButtonClick(Sender: TObject);
  public
    /// <summary>ATodayLock: Grund, warum „Heutiges Ergebnis übernehmen“ gesperrt ist; '' = frei.</summary>
    constructor CreateDialog(AOwner: TComponent; const ASuggestion: TAtlasBoundarySuggestion;
      const ATodayLock: string);
    /// <summary>Gewählte Fälle mit Name und Erwartet aus dem Fenster.</summary>
    function Cases: TArray<TAtlasBoundaryCase>;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Signal,
  Atlas.UI.Tests.Strings;

/// <summary>Wert des Parameters AIndex im Fall ACase; '' ohne.</summary>
function ValueAt(const ACase: TAtlasBoundaryCase; AIndex: Integer): string;
begin
  Result := '';
  if AIndex <= High(ACase.Values) then
  begin
    Result := ACase.Values[AIndex];
  end;
end;

{ TAtlasTestsBoundaryDialog }

constructor TAtlasTestsBoundaryDialog.CreateDialog(AOwner: TComponent; const ASuggestion: TAtlasBoundarySuggestion;
  const ATodayLock: string);
var
  mRow: TPanel;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryTitle,
    [ASuggestion.Routine]), cDialogWidth);
  FSuggestion := ASuggestion;
  FSuggestion.Cases := Copy(ASuggestion.Cases);
  FTodayLock := ATodayLock;
  mRow := AddRow(cGridHeight);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := mRow;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.Options := FGrid.Options + [goTabs, goColSizing, goThumbTracking] - [goRangeSelect];
  FGrid.OnSetEditText := GridSetEditText;
  FGrid.OnSelectCell := GridSelectCell;
  FGrid.OnDblClick := GridDblClick;
  FGrid.OnKeyPress := GridKeyPress;
  FNote := AddNote(cNoteHeight);
  mButtons := AddButtonRow;
  FApply := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryApply),
    TAtlasButtonKind.Default);
  FApply.ModalResult := mrNone;
  FApply.OnClick := ButtonClick;
  FToday := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryToday));
  FToday.ModalResult := mrNone;
  FToday.OnClick := ButtonClick;
  mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryClose), TAtlasButtonKind.Cancel);
  Fill;
  UpdateState;
  ActiveControl := FGrid;
  FitHeight;
  AllowResize(mRow);
end;

function TAtlasTestsBoundaryDialog.ExpectedColumn: Integer;
begin
  Result := -1;
  if FSuggestion.HasResult then
  begin
    Result := Length(FSuggestion.Parameters) + 2;
  end;
end;

function TAtlasTestsBoundaryDialog.ReasonColumn: Integer;
begin
  Result := Length(FSuggestion.Parameters) + 2;
  if FSuggestion.HasResult then
  begin
    Inc(Result);
  end;
end;

function TAtlasTestsBoundaryDialog.Editable(ACol: Integer): Boolean;
begin
  Result := (ACol = 1) or ((ACol = ExpectedColumn) and (ACol >= 0));
end;

function TAtlasTestsBoundaryDialog.ReasonText(const ACase: TAtlasBoundaryCase): string;
begin
  Result := ACase.Reason;
  if not ACase.TestCase then
  begin
    Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNotFitting) + ' · ' + Result;
  end;
end;

procedure TAtlasTestsBoundaryDialog.FillUse(AIndex: Integer);
begin
  if not FSuggestion.Cases[AIndex].TestCase then
  begin
    FGrid.Cells[0, AIndex + 1] := cNoUseMark;
  end
  else if FSuggestion.Cases[AIndex].Use then
  begin
    FGrid.Cells[0, AIndex + 1] := cUseMark;
  end
  else
  begin
    FGrid.Cells[0, AIndex + 1] := '';
  end;
end;

procedure TAtlasTestsBoundaryDialog.Fill;
var
  mRow, mCol: Integer;
  mCase: TAtlasBoundaryCase;
begin
  FFilling := True;
  try
    FGrid.ColCount := ReasonColumn + 1;
    FGrid.RowCount := Max(2, Length(FSuggestion.Cases) + 1);
    FGrid.FixedRows := 1;
    FGrid.Cells[0, 0] := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryUse);
    FGrid.ColWidths[0] := cUseWidth;
    FGrid.Cells[1, 0] := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryName);
    FGrid.ColWidths[1] := cNameWidth;
    for mCol := 0 to High(FSuggestion.Parameters) do
    begin
      FGrid.Cells[mCol + 2, 0] := FSuggestion.Parameters[mCol].Name + ': ' + FSuggestion.Parameters[mCol].TypeName;
      FGrid.ColWidths[mCol + 2] := cValueWidth;
    end;
    if FSuggestion.HasResult then
    begin
      FGrid.Cells[ExpectedColumn, 0] := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryExpected,
        [FSuggestion.ResultType]);
      FGrid.ColWidths[ExpectedColumn] := cValueWidth;
    end;
    FGrid.Cells[ReasonColumn, 0] := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryReason);
    FGrid.ColWidths[ReasonColumn] := cReasonWidth;
    for mRow := 0 to High(FSuggestion.Cases) do
    begin
      mCase := FSuggestion.Cases[mRow];
      FillUse(mRow);
      FGrid.Cells[1, mRow + 1] := mCase.Name;
      for mCol := 0 to High(FSuggestion.Parameters) do
      begin
        FGrid.Cells[mCol + 2, mRow + 1] := ValueAt(mCase, mCol);
      end;
      FGrid.Cells[ReasonColumn, mRow + 1] := ReasonText(mCase);
    end;
  finally
    FFilling := False;
  end;
end;

procedure TAtlasTestsBoundaryDialog.Toggle(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FSuggestion.Cases)) or not FSuggestion.Cases[AIndex].TestCase then
  begin
    Exit;
  end;
  FSuggestion.Cases[AIndex].Use := not FSuggestion.Cases[AIndex].Use;
  FillUse(AIndex);
  UpdateState;
end;

function TAtlasTestsBoundaryDialog.ChosenCount: Integer;
begin
  Result := Length(TAtlasBoundaryCases.Chosen(FSuggestion.Cases));
end;

function TAtlasTestsBoundaryDialog.MissingExpected: Boolean;
var
  mCase: TAtlasBoundaryCase;
begin
  Result := False;
  if not FSuggestion.HasResult then
  begin
    Exit;
  end;
  for mCase in TAtlasBoundaryCases.Chosen(FSuggestion.Cases) do
  begin
    if Trim(mCase.Expected) = '' then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasTestsBoundaryDialog.UpdateState;
var
  mChosen: Boolean;
  mNote: string;
  mKind: TAtlasSignalKind;
begin
  mChosen := ChosenCount > 0;
  FApply.Enabled := mChosen and not MissingExpected;
  FToday.Enabled := mChosen and FSuggestion.HasResult and (FTodayLock = '');
  FToday.Visible := FSuggestion.HasResult;
  mKind := TAtlasSignalKind.Info;
  if not FSuggestion.HasResult then
  begin
    mNote := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryHintProcedure);
  end
  else if FTodayLock <> '' then
  begin
    mNote := FTodayLock;
    mKind := TAtlasSignalKind.Warn;
  end
  else if mChosen and MissingExpected then
  begin
    mNote := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNoExpected);
  end
  else
  begin
    mNote := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryHint);
  end;
  if FSuggestion.Truncated then
  begin
    mNote := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryTruncated, [Length(FSuggestion.Cases)]) + ' ' +
      mNote;
  end;
  FNote.ShowNote(mNote, mKind);
end;

procedure TAtlasTestsBoundaryDialog.GridSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
var
  mRow: Integer;
begin
  mRow := ARow - 1;
  if FFilling or (mRow < 0) or (mRow > High(FSuggestion.Cases)) or not Editable(ACol) then
  begin
    Exit;
  end;
  if ACol = 1 then
  begin
    FSuggestion.Cases[mRow].Name := Value;
  end
  else
  begin
    FSuggestion.Cases[mRow].Expected := Value;
  end;
  UpdateState;
end;

procedure TAtlasTestsBoundaryDialog.GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
begin
  // Nur Name und Erwartet sind bearbeitbar; Werte und Grund kommen aus der Routine.
  if Editable(ACol) then
  begin
    FGrid.Options := FGrid.Options + [goEditing];
  end
  else
  begin
    FGrid.Options := FGrid.Options - [goEditing];
  end;
end;

procedure TAtlasTestsBoundaryDialog.GridDblClick(Sender: TObject);
begin
  if not Editable(FGrid.Col) then
  begin
    Toggle(FGrid.Row - 1);
  end;
end;

procedure TAtlasTestsBoundaryDialog.GridKeyPress(Sender: TObject; var Key: Char);
begin
  if (Key = ' ') and not FGrid.EditorMode and not Editable(FGrid.Col) then
  begin
    Toggle(FGrid.Row - 1);
    Key := #0;
  end;
end;

procedure TAtlasTestsBoundaryDialog.ButtonClick(Sender: TObject);
begin
  // Werte im Editor der Zelle zuerst übernehmen.
  FGrid.EditorMode := False;
  UpdateState;
  if (Sender = FApply) and FApply.Enabled then
  begin
    ModalResult := mrOk;
  end
  else if (Sender = FToday) and FToday.Enabled then
  begin
    ModalResult := mrYes;
  end;
end;

function TAtlasTestsBoundaryDialog.Cases: TArray<TAtlasBoundaryCase>;
begin
  Result := TAtlasBoundaryCases.Chosen(FSuggestion.Cases);
end;

end.
