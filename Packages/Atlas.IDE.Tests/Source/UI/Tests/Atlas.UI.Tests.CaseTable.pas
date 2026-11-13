unit Atlas.UI.Tests.CaseTable;

// Fenster „TestCase-Tabelle“ (#1879), ohne Open Tools API:
//   Fälle von TRechnerTests.Teilen
//   Name    | A: Integer | B: Integer | Letzter Lauf
//   Glatt   | 6          | 3          | bestanden · 2 ms
//   Null    | 1          | x          | fehlgeschlagen        (x rot umrandet, Tooltip „Keine Ganzzahl“)
//   [Zeile hinzufügen] [Zeile löschen] [Nach oben] [Nach unten] [Diesen Fall ausführen] [Im Debugger ausführen]
//   Hinweis bzw. Fehler                                                         [Übernehmen] [Schließen]
// Die Daten (Atlas.Core.Tests.CaseTable) und alle Wege nach außen kommen über THooks: Prüfen und Schreiben fragen
// den Server (die Antwort kommt über ShowProblems bzw. ShowRefused zurück), Ausführen und Letzter Lauf gehen an
// den Läufer. Geprüft wird nach einer Tipp-Pause; jede Prüfung trägt eine Nummer, ältere Antworten verfallen.
// Im Debugger ausführen schließt das Fenster (ModalResult mrRetry, DebugRow nennt die Zeile), damit der Debugger
// nicht hinter einem modalen Fenster startet.

interface

uses
  System.Classes,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Grids,
  Atlas.Core.Tests.CaseTable,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Zeilen an den Server schicken; die Antwort kommt mit AGeneration zurück.</summary>
  TAtlasTestCaseRowsProc = reference to procedure(const ARows: TArray<TAtlasTestCaseRow>; AGeneration: Integer);
  /// <summary>Fall der Zeile AFrom (Index im Quelltext) ausführen.</summary>
  TAtlasTestCaseRunProc = reference to procedure(AFrom: Integer);
  /// <summary>Text „Letzter Lauf“ des Falls AFrom; '' ohne Lauf.</summary>
  TAtlasTestCaseLastRunFunc = reference to function(AFrom: Integer): string;

  TAtlasTestsCaseTableDialog = class(TAtlasDialog)
  public type
    THooks = record
      Check: TAtlasTestCaseRowsProc;
      Apply: TAtlasTestCaseRowsProc;
      Run: TAtlasTestCaseRunProc;
      LastRun: TAtlasTestCaseLastRunFunc;
      /// <summary>Zählt Änderungen an den Läufen; ändert sie sich, liest das Fenster „Letzter Lauf“ neu.</summary>
      Version: TFunc<Integer>;
    end;
    /// <summary>Knöpfe des Fensters; Tag des Knopfs ist der Wert.</summary>
    TTableAction = (taAdd, taDelete, taUp, taDown, taRun, taDebug, taApply);
  public const
    cDialogWidth = 780;
    cGridHeight = 300;
    cNoteHeight = 24;
    cNameWidth = 140;
    cValueWidth = 110;
    cLastRunWidth = 150;
    cTickMs = 150;
    cQuietMs = 400;
  private
    FTable: TAtlasTestCaseTable;
    FRows: TArray<TAtlasTestCaseRow>;
    FHooks: THooks;
    FGrid: TStringGrid;
    FNote: TAtlasNoteLabel;
    FButtons: array[TTableAction] of TButton;
    FTimer: TTimer;
    FGeneration: Integer;
    /// <summary>Seit wann (Ticks) wartet eine Prüfung auf die Tipp-Pause? 0 ohne.</summary>
    FEditedAt: UInt64;
    FVersion: Integer;
    FApplying: Boolean;
    FDebugRow: Integer;
    FHintCell: TPoint;
    FFilling: Boolean;
    /// <summary>Zeile des Gitters beim letzten Takt; ändert sie sich, folgen Knöpfe und Hinweis.</summary>
    FShownRow: Integer;
    function LastColumn: Integer;
    procedure Fill;
    procedure FillLastRun;
    procedure UpdateButtons;
    procedure ShowNote;
    procedure Edited;
    function CurrentRow: Integer;
    procedure SelectRow(AIndex: Integer);
    function ProblemAt(ACol, ARow: Integer): string;
    procedure GridSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
    procedure GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ButtonClick(Sender: TObject);
    /// <summary>Zeile ARow hinzufügen, löschen oder verschieben.</summary>
    procedure ChangeRows(AAction: TTableAction; ARow: Integer);
    procedure ApplyRows;
    procedure Tick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const ATable: TAtlasTestCaseTable; const AHooks: THooks);
    destructor Destroy; override;
    /// <summary>Antwort auf Check bzw. Apply mit Nummer AGeneration: Fehler je Zelle übernehmen; ältere
    /// Antworten verwirft das Fenster.</summary>
    procedure ShowProblems(AGeneration: Integer; const AProposal: TAtlasTestCaseProposal);
    /// <summary>Schreiben ist gescheitert: Grund zeigen, Übernehmen wieder freigeben.</summary>
    procedure ShowRefused(const AReason: string);
    /// <summary>Geschrieben: Fenster schließen (mrOk).</summary>
    procedure Applied;
    /// <summary>Nach mrRetry: Fall (Index im Quelltext), der im Debugger laufen soll; sonst -1.</summary>
    property DebugRow: Integer read FDebugRow;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.UI.Tests.Strings;

/// <summary>Gitter der Fälle in AParent; bearbeitbar mit AEditable, sonst nur Zeilen wählen.</summary>
function NewGrid(AOwner: TComponent; AParent: TWinControl; AEditable: Boolean): TStringGrid;
begin
  Result := TStringGrid.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.FixedCols := 0;
  Result.Options := Result.Options + [goTabs, goColSizing, goThumbTracking, goRowSelect] - [goRangeSelect];
  if AEditable then
  begin
    Result.Options := Result.Options - [goRowSelect] + [goEditing];
  end;
  Result.ShowHint := True;
end;

{ TAtlasTestsCaseTableDialog }

constructor TAtlasTestsCaseTableDialog.CreateDialog(AOwner: TComponent; const ATable: TAtlasTestCaseTable;
  const AHooks: THooks);
const
  cCaptions: array[taAdd..taDebug] of TAtlasTestsTextId = (TAtlasTestsTextId.TestsCaseTableAddRow,
    TAtlasTestsTextId.TestsCaseTableDeleteRow, TAtlasTestsTextId.TestsCaseTableUp, TAtlasTestsTextId.TestsCaseTableDown,
    TAtlasTestsTextId.TestsCaseTableRun, TAtlasTestsTextId.TestsCaseTableDebug);
var
  mRow: TPanel;
  mTools, mButtons: TAtlasButtonRow;
  mAction: TTableAction;
begin
  inherited CreateDialog(AOwner, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsCaseTableTitle,
    [ATable.Fixture, ATable.Method]), cDialogWidth);
  FTable := ATable;
  FRows := Copy(ATable.Rows);
  FHooks := AHooks;
  FDebugRow := -1;
  FShownRow := -1;
  FHintCell := Point(-1, -1);
  mRow := AddRow(cGridHeight);
  FGrid := NewGrid(Self, mRow, FTable.Editable);
  FGrid.OnSetEditText := GridSetEditText;
  FGrid.OnSelectCell := GridSelectCell;
  FGrid.OnDrawCell := GridDrawCell;
  FGrid.OnMouseMove := GridMouseMove;
  mTools := AddButtonRow;
  for mAction := taAdd to taDebug do
  begin
    FButtons[mAction] := mTools.AddButton(TAtlasTestsStrings.Text(cCaptions[mAction]));
  end;
  FNote := AddNote(cNoteHeight);
  mButtons := AddButtonRow;
  FButtons[taApply] := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableApply),
    TAtlasButtonKind.Default);
  FButtons[taApply].ModalResult := mrNone;
  for mAction := Low(TTableAction) to High(TTableAction) do
  begin
    FButtons[mAction].Tag := Ord(mAction);
    FButtons[mAction].OnClick := ButtonClick;
  end;
  mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableClose), TAtlasButtonKind.Cancel);
  Fill;
  ShowNote;
  UpdateButtons;
  ActiveControl := FGrid;
  FitHeight;
  AllowResize(mRow);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasTestsCaseTableDialog.Destroy;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FHooks := Default(THooks);
  inherited Destroy;
end;

function TAtlasTestsCaseTableDialog.LastColumn: Integer;
begin
  Result := FTable.ValueColumns + 1;
end;

procedure TAtlasTestsCaseTableDialog.Fill;
var
  mRow, mCol: Integer;
begin
  FFilling := True;
  try
    FGrid.ColCount := LastColumn + 1;
    FGrid.RowCount := Max(2, Length(FRows) + 1);
    FGrid.FixedRows := 1;
    FGrid.Cells[0, 0] := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableName);
    FGrid.ColWidths[0] := cNameWidth;
    for mCol := 0 to FTable.ValueColumns - 1 do
    begin
      FGrid.Cells[mCol + 1, 0] := FTable.Header(mCol);
      FGrid.ColWidths[mCol + 1] := cValueWidth;
    end;
    FGrid.Cells[LastColumn, 0] := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableLastRun);
    FGrid.ColWidths[LastColumn] := cLastRunWidth;
    for mRow := 0 to FGrid.RowCount - 2 do
    begin
      for mCol := 0 to LastColumn - 1 do
      begin
        if mRow > High(FRows) then
        begin
          FGrid.Cells[mCol, mRow + 1] := '';
        end
        else if mCol = 0 then
        begin
          FGrid.Cells[mCol, mRow + 1] := FRows[mRow].Name;
        end
        else
        begin
          FGrid.Cells[mCol, mRow + 1] := FRows[mRow].Value(mCol - 1);
        end;
      end;
    end;
  finally
    FFilling := False;
  end;
  FillLastRun;
end;

procedure TAtlasTestsCaseTableDialog.FillLastRun;
var
  mRow: Integer;
  mText: string;
begin
  for mRow := 0 to High(FRows) do
  begin
    mText := '';
    if (FRows[mRow].From >= 0) and Assigned(FHooks.LastRun) then
    begin
      mText := FHooks.LastRun(FRows[mRow].From);
    end;
    FGrid.Cells[LastColumn, mRow + 1] := mText;
  end;
end;

function TAtlasTestsCaseTableDialog.CurrentRow: Integer;
begin
  Result := FGrid.Row - 1;
  if (Result < 0) or (Result > High(FRows)) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasTestsCaseTableDialog.SelectRow(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex + 1 < FGrid.RowCount) then
  begin
    FGrid.Row := AIndex + 1;
  end;
end;

procedure TAtlasTestsCaseTableDialog.UpdateButtons;
var
  mRow: Integer;
  mCanRun: Boolean;
begin
  mRow := CurrentRow;
  FButtons[taAdd].Enabled := FTable.Editable and not FApplying;
  FButtons[taDelete].Enabled := FTable.Editable and not FApplying and (mRow >= 0) and (Length(FRows) > 1);
  FButtons[taUp].Enabled := FTable.Editable and not FApplying and (mRow > 0);
  FButtons[taDown].Enabled := FTable.Editable and not FApplying and (mRow >= 0) and (mRow < High(FRows));
  mCanRun := (mRow >= 0) and (FRows[mRow].From >= 0) and Assigned(FHooks.Run);
  FButtons[taRun].Enabled := mCanRun;
  FButtons[taDebug].Enabled := mCanRun;
  FButtons[taApply].Enabled := FTable.Editable and not FApplying and TAtlasTestCaseTables.Changed(FTable, FRows);
end;

procedure TAtlasTestsCaseTableDialog.ShowNote;
var
  mRow: Integer;
begin
  if not FTable.Editable then
  begin
    FNote.ShowNote(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsCaseTableReadOnly, [FTable.Reason]),
      TAtlasSignalKind.Warn);
    Exit;
  end;
  mRow := CurrentRow;
  if (mRow >= 0) and (FRows[mRow].From < 0) then
  begin
    FNote.ShowNote(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableNewCase), TAtlasSignalKind.Info);
  end
  else
  begin
    FNote.ShowNote(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableHint), TAtlasSignalKind.Info);
  end;
end;

procedure TAtlasTestsCaseTableDialog.Edited;
begin
  FEditedAt := TAtlasTicks.Now;
  UpdateButtons;
end;

function TAtlasTestsCaseTableDialog.ProblemAt(ACol, ARow: Integer): string;
var
  mRow: Integer;
begin
  Result := '';
  mRow := ARow - 1;
  if (mRow < 0) or (mRow > High(FRows)) then
  begin
    Exit;
  end;
  if ACol = 0 then
  begin
    Result := FRows[mRow].Problem;
  end
  else if ACol < LastColumn then
  begin
    Result := FRows[mRow].CellProblem(ACol - 1);
  end;
end;

procedure TAtlasTestsCaseTableDialog.GridSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
var
  mRow: Integer;
begin
  mRow := ARow - 1;
  if FFilling or (mRow < 0) or (mRow > High(FRows)) or (ACol >= LastColumn) then
  begin
    Exit;
  end;
  if ACol = 0 then
  begin
    FRows[mRow].Name := Value;
  end
  else
  begin
    TAtlasTestCaseTables.SetValue(FRows[mRow], ACol - 1, Value);
  end;
  Edited;
end;

procedure TAtlasTestsCaseTableDialog.GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
begin
  // „Letzter Lauf“ ist nur zum Lesen.
  if FTable.Editable then
  begin
    if ACol = LastColumn then
    begin
      FGrid.Options := FGrid.Options - [goEditing];
    end
    else
    begin
      FGrid.Options := FGrid.Options + [goEditing];
    end;
  end;
  // Knöpfe und Hinweis folgen der Zeile im nächsten Takt (Tick): Row steht erst nach diesem Ereignis.
end;

procedure TAtlasTestsCaseTableDialog.GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect;
  State: TGridDrawState);
var
  mColors: TAtlasColors;
  mCanvas: TCanvas;
begin
  if ProblemAt(ACol, ARow) = '' then
  begin
    Exit;
  end;
  mCanvas := FGrid.Canvas;
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(FGrid.Color)));
  mCanvas.Brush.Style := bsClear;
  mCanvas.Pen.Color := TColor(mColors.Error);
  mCanvas.Pen.Width := 2;
  mCanvas.Rectangle(Rect.Left + 1, Rect.Top + 1, Rect.Right, Rect.Bottom);
  mCanvas.Pen.Width := 1;
end;

procedure TAtlasTestsCaseTableDialog.GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mCol, mRow: Integer;
begin
  FGrid.MouseToCell(X, Y, mCol, mRow);
  if (mCol = FHintCell.X) and (mRow = FHintCell.Y) then
  begin
    Exit;
  end;
  FHintCell := Point(mCol, mRow);
  FGrid.Hint := ProblemAt(mCol, mRow);
  Application.CancelHint;
end;

procedure TAtlasTestsCaseTableDialog.ButtonClick(Sender: TObject);
var
  mAction: TTableAction;
  mRow: Integer;
begin
  mAction := TTableAction((Sender as TButton).Tag);
  mRow := CurrentRow;
  case mAction of
    taRun:
      if (mRow >= 0) and (FRows[mRow].From >= 0) and Assigned(FHooks.Run) then
      begin
        FHooks.Run(FRows[mRow].From);
      end;
    taDebug:
      if (mRow >= 0) and (FRows[mRow].From >= 0) then
      begin
        FDebugRow := FRows[mRow].From;
        ModalResult := mrRetry;
      end;
    taApply:
      ApplyRows;
  else
    ChangeRows(mAction, mRow);
  end;
end;

procedure TAtlasTestsCaseTableDialog.ChangeRows(AAction: TTableAction; ARow: Integer);
var
  mDone: Boolean;
  mSelect: Integer;
begin
  case AAction of
    taAdd:
      begin
        FRows := FRows + [TAtlasTestCaseTables.NewRow(FTable)];
        mDone := True;
        mSelect := High(FRows);
      end;
    taDelete:
      begin
        mDone := TAtlasTestCaseTables.Delete(FRows, ARow);
        mSelect := Min(ARow, High(FRows));
      end;
    taUp:
      begin
        mDone := TAtlasTestCaseTables.Move(FRows, ARow, -1);
        mSelect := ARow - 1;
      end;
  else
    mDone := TAtlasTestCaseTables.Move(FRows, ARow, 1);
    mSelect := ARow + 1;
  end;
  if mDone then
  begin
    Fill;
    SelectRow(mSelect);
    Edited;
    ShowNote;
  end;
end;

procedure TAtlasTestsCaseTableDialog.ApplyRows;
begin
  if not Assigned(FHooks.Apply) or not FButtons[taApply].Enabled then
  begin
    Exit;
  end;
  // Werte im Editor der Zelle zuerst übernehmen.
  FGrid.EditorMode := False;
  FApplying := True;
  FEditedAt := 0;
  Inc(FGeneration);
  UpdateButtons;
  FHooks.Apply(FRows, FGeneration);
end;

procedure TAtlasTestsCaseTableDialog.ShowProblems(AGeneration: Integer; const AProposal: TAtlasTestCaseProposal);
begin
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  TAtlasTestCaseTables.TakeProblems(FRows, AProposal);
  FGrid.Invalidate;
  FHintCell := Point(-1, -1);
  if (AProposal.EditJson = '') and (AProposal.Reason <> '') then
  begin
    FNote.ShowNote(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsCaseTableRefused, [AProposal.Reason]),
      TAtlasSignalKind.Warn);
  end
  else if not FApplying then
  begin
    ShowNote;
  end;
end;

procedure TAtlasTestsCaseTableDialog.ShowRefused(const AReason: string);
begin
  FApplying := False;
  FNote.ShowNote(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsCaseTableRefused, [AReason]),
    TAtlasSignalKind.Error);
  UpdateButtons;
end;

procedure TAtlasTestsCaseTableDialog.Applied;
begin
  FApplying := False;
  ModalResult := mrOk;
end;

procedure TAtlasTestsCaseTableDialog.Tick(Sender: TObject);
var
  mVersion: Integer;
begin
  if FGrid.Row <> FShownRow then
  begin
    FShownRow := FGrid.Row;
    UpdateButtons;
    ShowNote;
  end;
  if (FEditedAt <> 0) and not FApplying and (TAtlasTicks.Since(FEditedAt) >= cQuietMs) and Assigned(FHooks.Check) then
  begin
    FEditedAt := 0;
    Inc(FGeneration);
    FHooks.Check(FRows, FGeneration);
  end;
  if Assigned(FHooks.Version) then
  begin
    mVersion := FHooks.Version();
    if mVersion <> FVersion then
    begin
      FVersion := mVersion;
      FillLastRun;
    end;
  end;
end;

end.
