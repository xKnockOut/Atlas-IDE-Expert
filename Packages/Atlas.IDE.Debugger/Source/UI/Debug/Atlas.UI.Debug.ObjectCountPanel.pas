unit Atlas.UI.Debug.ObjectCountPanel;

// Bereich „Objekte zählen“ im Fenster „Atlas: Speicher“ (#858, experimentell): oben der Knopf, das Filterfeld
// und die Zusammenfassung, darunter die Tabelle Klasse, Anzahl, Zuwachs, Größe (Zuwächse oben), unten ein
// Hinweis. Gezählt wird in der IDE-Schicht (Atlas.IDE.Debug.ObjectCount) auf OnCount; sie reicht das Ergebnis
// mit SetCounts herein. Die Tabelle ist ein TStringGrid, weil dessen Zellen auch ohne Fenster gefüllt werden
// können.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Grids,
  Atlas.Core.Debug.ObjectCount;

type
  TAtlasDebugObjectCountPanel = class(TPanel)
  private type
    TControls = record
      Count: TButton;
      Filter: TEdit;
      Summary: TLabel;
      Grid: TStringGrid;
    end;
    TCounts = record
      Base: TAtlasObjectCount;
      Current: TAtlasObjectCount;
      HasBase: Boolean;
      HasCurrent: Boolean;
    end;
  private
    FControls: TControls;
    FCounts: TCounts;
    FOnCount: TProc;
    procedure CreateBar;
    procedure CreateGrid;
    procedure FillGrid;
    procedure CountClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Neue Zählung zeigen; mit AHasBase den Zuwachs gegenüber ABase.</summary>
    procedure SetCounts(const ABase, ACurrent: TAtlasObjectCount; AHasBase: Boolean);
    /// <summary>Tabelle und Zusammenfassung leeren (neue Sitzung).</summary>
    procedure ClearCounts;
    /// <summary>Meldung statt der Zusammenfassung (etwa „nur angehalten“).</summary>
    procedure ShowStatus(const AText: string);
    /// <summary>Zeilen, wie die Tabelle sie zeigt (gefiltert und sortiert).</summary>
    function Rows: TArray<TAtlasObjectCountRow>;
    property CountButton: TButton read FControls.Count;
    property FilterEdit: TEdit read FControls.Filter;
    property SummaryLabel: TLabel read FControls.Summary;
    property Grid: TStringGrid read FControls.Grid;
    property OnCount: TProc read FOnCount write FOnCount;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Debug.MemoryTimeline,
  Atlas.UI.Debug.Memory.Strings;

const
  /// <summary>Maße in logischen Pixeln.</summary>
  cBarHeight = 32;
  cButtonWidth = 110;
  cFilterWidth = 160;
  cClassWidth = 260;
  cNumberWidth = 80;
  cRowHeight = 20;
  cColumnCount = 4;
  cColClass = 0;
  cColCount = 1;
  cColDelta = 2;
  cColBytes = 3;

function SignedNumber(AValue: Integer): string;
begin
  Result := IntToStr(AValue);
  if AValue > 0 then
  begin
    Result := '+' + Result;
  end;
end;

{ TAtlasDebugObjectCountPanel }

constructor TAtlasDebugObjectCountPanel.Create(AOwner: TComponent);
var
  mHint: TLabel;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
  CreateBar;
  mHint := TLabel.Create(Self);
  mHint.Align := alBottom;
  mHint.Parent := Self;
  mHint.AlignWithMargins := True;
  mHint.ShowAccelChar := False;
  mHint.WordWrap := True;
  mHint.Font.Color := clGrayText;
  mHint.Caption := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountHint);
  CreateGrid;
end;

procedure TAtlasDebugObjectCountPanel.CreateBar;
var
  mBar: TPanel;
begin
  mBar := TPanel.Create(Self);
  mBar.Height := MulDiv(cBarHeight, CurrentPPI, 96);
  mBar.Align := alTop;
  mBar.Parent := Self;
  mBar.BevelOuter := bvNone;
  mBar.ShowCaption := False;
  mBar.ParentBackground := True;
  FControls.Count := TButton.Create(Self);
  FControls.Count.Parent := mBar;
  FControls.Count.Align := alLeft;
  FControls.Count.AlignWithMargins := True;
  FControls.Count.Width := MulDiv(cButtonWidth, CurrentPPI, 96);
  FControls.Count.Caption := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountButton);
  FControls.Count.OnClick := CountClick;
  FControls.Filter := TEdit.Create(Self);
  FControls.Filter.Left := FControls.Count.Left + FControls.Count.Width + 1;
  FControls.Filter.Parent := mBar;
  FControls.Filter.Align := alLeft;
  FControls.Filter.AlignWithMargins := True;
  FControls.Filter.Width := MulDiv(cFilterWidth, CurrentPPI, 96);
  FControls.Filter.TextHint := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountFilter);
  FControls.Filter.OnChange := FilterChange;
  FControls.Summary := TLabel.Create(Self);
  FControls.Summary.Parent := mBar;
  FControls.Summary.Align := alClient;
  FControls.Summary.AlignWithMargins := True;
  FControls.Summary.Layout := tlCenter;
  FControls.Summary.ShowAccelChar := False;
  FControls.Summary.EllipsisPosition := epEndEllipsis;
end;

procedure TAtlasDebugObjectCountPanel.CreateGrid;
begin
  FControls.Grid := TStringGrid.Create(Self);
  FControls.Grid.Parent := Self;
  FControls.Grid.Align := alClient;
  FControls.Grid.AlignWithMargins := True;
  FControls.Grid.ColCount := cColumnCount;
  FControls.Grid.RowCount := 2;
  FControls.Grid.FixedCols := 0;
  FControls.Grid.FixedRows := 1;
  FControls.Grid.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect,
    goThumbTracking];
  FControls.Grid.DefaultRowHeight := MulDiv(cRowHeight, CurrentPPI, 96);
  FControls.Grid.ColWidths[cColClass] := MulDiv(cClassWidth, CurrentPPI, 96);
  FControls.Grid.ColWidths[cColCount] := MulDiv(cNumberWidth, CurrentPPI, 96);
  FControls.Grid.ColWidths[cColDelta] := MulDiv(cNumberWidth, CurrentPPI, 96);
  FControls.Grid.ColWidths[cColBytes] := MulDiv(cNumberWidth, CurrentPPI, 96);
  FControls.Grid.Cells[cColClass, 0] := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountColumnClass);
  FControls.Grid.Cells[cColCount, 0] := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountColumnCount);
  FControls.Grid.Cells[cColDelta, 0] := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountColumnDelta);
  FControls.Grid.Cells[cColBytes, 0] := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountColumnBytes);
end;

function TAtlasDebugObjectCountPanel.Rows: TArray<TAtlasObjectCountRow>;
begin
  Result := nil;
  if FCounts.HasCurrent then
  begin
    Result := TAtlasObjectCountCompare.Rows(FCounts.Base, FCounts.Current, FCounts.HasBase,
      FControls.Filter.Text);
  end;
end;

procedure TAtlasDebugObjectCountPanel.FillGrid;
var
  mRows: TArray<TAtlasObjectCountRow>;
  mIndex: Integer;
begin
  mRows := Rows;
  // Mindestens eine Zeile unter der Kopfzeile, sonst verliert das Gitter FixedRows.
  FControls.Grid.RowCount := 1 + Length(mRows) + Ord(Length(mRows) = 0);
  FControls.Grid.Rows[1].Clear;
  for mIndex := 0 to High(mRows) do
  begin
    FControls.Grid.Cells[cColClass, mIndex + 1] := mRows[mIndex].Name;
    FControls.Grid.Cells[cColCount, mIndex + 1] := IntToStr(mRows[mIndex].Count);
    FControls.Grid.Cells[cColDelta, mIndex + 1] := '';
    if FCounts.HasBase then
    begin
      FControls.Grid.Cells[cColDelta, mIndex + 1] := SignedNumber(mRows[mIndex].Delta);
    end;
    FControls.Grid.Cells[cColBytes, mIndex + 1] := TAtlasMemoryFormat.Bytes(mRows[mIndex].Bytes, FormatSettings);
  end;
end;

procedure TAtlasDebugObjectCountPanel.SetCounts(const ABase, ACurrent: TAtlasObjectCount; AHasBase: Boolean);
var
  mText: string;
begin
  FCounts.Base := ABase;
  FCounts.Current := ACurrent;
  FCounts.HasBase := AHasBase;
  FCounts.HasCurrent := True;
  mText := TAtlasMemoryStrings.Fmt(TAtlasMemoryTextId.ObjectCountSummary, [ACurrent.Total,
    Length(ACurrent.Classes), TAtlasMemoryFormat.Bytes(Int64(ACurrent.ScannedBytes), FormatSettings)]);
  if AHasBase then
  begin
    mText := mText + ' ' + TAtlasMemoryStrings.Text(TAtlasMemoryTextId.ObjectCountCompared);
  end;
  FControls.Summary.Caption := mText;
  FillGrid;
end;

procedure TAtlasDebugObjectCountPanel.ClearCounts;
begin
  FCounts := Default(TCounts);
  FControls.Summary.Caption := '';
  FillGrid;
end;

procedure TAtlasDebugObjectCountPanel.ShowStatus(const AText: string);
begin
  FControls.Summary.Caption := AText;
end;

procedure TAtlasDebugObjectCountPanel.CountClick(Sender: TObject);
begin
  if Assigned(FOnCount) then
  begin
    FOnCount();
  end;
end;

procedure TAtlasDebugObjectCountPanel.FilterChange(Sender: TObject);
begin
  FillGrid;
end;

end.
