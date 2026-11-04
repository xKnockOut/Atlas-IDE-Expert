unit Atlas.UI.Diagnostics.Grid;

// Gezeichnete Tabelle der Reiter im Diagnose-Fenster (Hauptthread, Server,
// Hintergrund, Hänger), reine VCL: Kopfzeile, Zeilen mit Warn- und
// Fehlerfarbe je Zelle, auf Wunsch ein Anteilsbalken in der letzten Spalte und
// eine gewählte Zeile (Klick, Rechtsklick, Doppelklick). Die erste Spalte
// nimmt die übrige Breite, die anderen haben feste Breiten (bei 96 dpi). Die
// Zeichenfläche ist so hoch wie alle Zeilen und liegt in einem Rollbereich;
// so braucht nichts davon ein Fenster, bevor es gezeigt wird.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette;

type
{$SCOPEDENUMS ON}
  TAtlasGridMark = (None, Warn, Bad);
{$SCOPEDENUMS OFF}

  TAtlasGridColumn = record
    Caption: string;
    /// <summary>Breite bei 96 dpi; die erste Spalte nimmt den Rest.</summary>
    Width: Integer;
    Right: Boolean;
    class function Make(const ACaption: string; AWidth: Integer; ARight: Boolean): TAtlasGridColumn; static;
  end;

  TAtlasGridRow = record
    Cells: TArray<string>;
    /// <summary>Je Zelle; fehlende Einträge gelten als None.</summary>
    Marks: TArray<TAtlasGridMark>;
    /// <summary>Anteil 0 bis 1 als Balken vor dem Text der letzten Spalte; kleiner 0 ohne Balken.</summary>
    Bar: Double;
    function Mark(AColumn: Integer): TAtlasGridMark;
  end;

  TAtlasDiagnosticGrid = class(TScrollBox)
  private
    FBox: TPaintBox;
    FColumns: TArray<TAtlasGridColumn>;
    FRows: TArray<TAtlasGridRow>;
    FColors: TAtlasColors;
    FSelected: Integer;
    FEmptyText: string;
    FOnSelect: TNotifyEvent;
    FOnOpen: TNotifyEvent;
    function Scale(AValue: Integer): Integer;
    procedure UpdateHeight;
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxDblClick(Sender: TObject);
    procedure PaintRow(ACanvas: TCanvas; const ARow: TAtlasGridRow; ATop: Integer; ASelected: Boolean);
    procedure PaintCell(ACanvas: TCanvas; const ARect: TRect; const AText: string; AMark: TAtlasGridMark;
      ARight, AMuted: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetColumns(const AColumns: TArray<TAtlasGridColumn>);
    /// <summary>Neue Zeilen; die Wahl bleibt auf derselben Nummer, wenn es sie noch gibt.</summary>
    procedure SetRows(const ARows: TArray<TAtlasGridRow>);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Zeile wählen (-1 = keine) und OnSelect melden.</summary>
    procedure SelectRow(AIndex: Integer);
    function RowHeight: Integer;
    /// <summary>Zeile an der Höhe AY der Zeichenfläche; -1 auf der Kopfzeile oder darunter.</summary>
    function RowAt(AY: Integer): Integer;
    /// <summary>Linke und rechte Kante der Spalte AIndex bei der Breite AWidth.</summary>
    function ColumnSpan(AIndex, AWidth: Integer): TPoint;
    /// <summary>Text der Zeile AIndex, Zellen mit Tabulator getrennt (Zeile kopieren).</summary>
    function RowText(AIndex: Integer): string;
    property Box: TPaintBox read FBox;
    property Rows: TArray<TAtlasGridRow> read FRows;
    property Columns: TArray<TAtlasGridColumn> read FColumns;
    property Selected: Integer read FSelected;
    property Colors: TAtlasColors read FColors;
    /// <summary>Text ohne Zeilen.</summary>
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    /// <summary>Doppelklick auf eine Zeile.</summary>
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
  end;

implementation

uses
  Winapi.Windows,
  System.Math;

const
  cTextFlags = DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS;
  cFirstMinWidth = 80;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasGridColumn }

class function TAtlasGridColumn.Make(const ACaption: string; AWidth: Integer; ARight: Boolean): TAtlasGridColumn;
begin
  Result.Caption := ACaption;
  Result.Width := AWidth;
  Result.Right := ARight;
end;

{ TAtlasGridRow }

function TAtlasGridRow.Mark(AColumn: Integer): TAtlasGridMark;
begin
  Result := TAtlasGridMark.None;
  if (AColumn >= 0) and (AColumn < Length(Marks)) then
  begin
    Result := Marks[AColumn];
  end;
end;

{ TAtlasDiagnosticGrid }

constructor TAtlasDiagnosticGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
  HorzScrollBar.Visible := False;
  VertScrollBar.Tracking := True;
  FColors := TAtlasColors.Light;
  FSelected := -1;
  FBox := TPaintBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alTop;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnDblClick := BoxDblClick;
  UpdateHeight;
end;

function TAtlasDiagnosticGrid.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasDiagnosticGrid.RowHeight: Integer;
begin
  Result := Scale(20);
end;

procedure TAtlasDiagnosticGrid.UpdateHeight;
begin
  // Kopfzeile plus Zeilen; ohne Zeilen eine Zeile für EmptyText.
  FBox.Height := RowHeight * (1 + Max(1, Length(FRows)));
end;

procedure TAtlasDiagnosticGrid.SetColumns(const AColumns: TArray<TAtlasGridColumn>);
begin
  FColumns := AColumns;
  FBox.Invalidate;
end;

procedure TAtlasDiagnosticGrid.SetRows(const ARows: TArray<TAtlasGridRow>);
begin
  FRows := ARows;
  if FSelected > High(FRows) then
  begin
    FSelected := -1;
  end;
  UpdateHeight;
  FBox.Invalidate;
end;

procedure TAtlasDiagnosticGrid.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Color := ToColor(AColors.Surface);
  FBox.Invalidate;
end;

procedure TAtlasDiagnosticGrid.SelectRow(AIndex: Integer);
begin
  if (AIndex < -1) or (AIndex > High(FRows)) then
  begin
    AIndex := -1;
  end;
  FSelected := AIndex;
  FBox.Invalidate;
  if Assigned(FOnSelect) then
  begin
    FOnSelect(Self);
  end;
end;

function TAtlasDiagnosticGrid.RowAt(AY: Integer): Integer;
begin
  Result := AY div RowHeight - 1;
  if (AY < RowHeight) or (Result > High(FRows)) then
  begin
    Result := -1;
  end;
end;

function TAtlasDiagnosticGrid.ColumnSpan(AIndex, AWidth: Integer): TPoint;
var
  mFixed, mIndex, mLeft: Integer;
begin
  mFixed := 0;
  for mIndex := 1 to High(FColumns) do
  begin
    Inc(mFixed, Scale(FColumns[mIndex].Width));
  end;
  mLeft := Max(Scale(cFirstMinWidth), AWidth - mFixed);
  if AIndex = 0 then
  begin
    Exit(Point(0, mLeft));
  end;
  for mIndex := 1 to AIndex - 1 do
  begin
    Inc(mLeft, Scale(FColumns[mIndex].Width));
  end;
  Result := Point(mLeft, mLeft + Scale(FColumns[AIndex].Width));
end;

function TAtlasDiagnosticGrid.RowText(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FRows)) then
  begin
    Result := string.Join(#9, FRows[AIndex].Cells);
  end;
end;

procedure TAtlasDiagnosticGrid.BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mRow: Integer;
begin
  mRow := RowAt(Y);
  if mRow >= 0 then
  begin
    SelectRow(mRow);
  end;
end;

procedure TAtlasDiagnosticGrid.BoxDblClick(Sender: TObject);
begin
  if (FSelected >= 0) and Assigned(FOnOpen) then
  begin
    FOnOpen(Self);
  end;
end;

procedure TAtlasDiagnosticGrid.PaintCell(ACanvas: TCanvas; const ARect: TRect; const AText: string;
  AMark: TAtlasGridMark; ARight, AMuted: Boolean);
var
  mRect: TRect;
  mFlags: Cardinal;
begin
  ACanvas.Font.Style := [];
  ACanvas.Font.Color := ToColor(FColors.Text);
  if AMuted then
  begin
    ACanvas.Font.Color := ToColor(FColors.Muted);
  end
  else if AMark = TAtlasGridMark.Warn then
  begin
    ACanvas.Font.Color := ToColor(FColors.Warn);
  end
  else if AMark = TAtlasGridMark.Bad then
  begin
    ACanvas.Font.Color := ToColor(FColors.Error);
    ACanvas.Font.Style := [fsBold];
  end;
  ACanvas.Brush.Style := bsClear;
  mRect := ARect;
  InflateRect(mRect, -Scale(4), 0);
  mFlags := cTextFlags or DT_LEFT;
  if ARight then
  begin
    mFlags := cTextFlags or DT_RIGHT;
  end;
  DrawText(ACanvas.Handle, PChar(AText), Length(AText), mRect, mFlags);
end;

procedure TAtlasDiagnosticGrid.PaintRow(ACanvas: TCanvas; const ARow: TAtlasGridRow; ATop: Integer;
  ASelected: Boolean);
var
  mColumn: Integer;
  mSpan: TPoint;
  mCell, mBar: TRect;
  mText: string;
begin
  if ASelected then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := ToColor(FColors.Selection);
    ACanvas.FillRect(Rect(0, ATop, FBox.Width, ATop + RowHeight));
  end;
  for mColumn := 0 to High(FColumns) do
  begin
    mSpan := ColumnSpan(mColumn, FBox.Width);
    mCell := Rect(mSpan.X, ATop, mSpan.Y, ATop + RowHeight);
    mText := '';
    if mColumn < Length(ARow.Cells) then
    begin
      mText := ARow.Cells[mColumn];
    end;
    if (mColumn = High(FColumns)) and (ARow.Bar >= 0) then
    begin
      // Balken links in der Zelle, Zahl rechts daneben.
      mBar := Rect(mCell.Left + Scale(4), ATop + Scale(6), mCell.Left + Scale(4) + Round(Min(1, ARow.Bar) *
        Scale(40)), ATop + RowHeight - Scale(6));
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := ToColor(FColors.Accent);
      ACanvas.FillRect(mBar);
    end;
    PaintCell(ACanvas, mCell, mText, ARow.Mark(mColumn), FColumns[mColumn].Right, False);
  end;
end;

procedure TAtlasDiagnosticGrid.BoxPaint(Sender: TObject);
var
  mCanvas: TCanvas;
  mColumn, mIndex, mTop: Integer;
  mSpan: TPoint;
begin
  mCanvas := FBox.Canvas;
  mCanvas.Font := Font;
  mCanvas.Brush.Style := bsSolid;
  mCanvas.Brush.Color := ToColor(FColors.Surface);
  mCanvas.FillRect(FBox.ClientRect);
  mCanvas.Brush.Color := ToColor(FColors.Gutter);
  mCanvas.FillRect(Rect(0, 0, FBox.Width, RowHeight));
  for mColumn := 0 to High(FColumns) do
  begin
    mSpan := ColumnSpan(mColumn, FBox.Width);
    PaintCell(mCanvas, Rect(mSpan.X, 0, mSpan.Y, RowHeight), FColumns[mColumn].Caption, TAtlasGridMark.None,
      FColumns[mColumn].Right, True);
  end;
  mCanvas.Pen.Color := ToColor(FColors.Line);
  mCanvas.MoveTo(0, RowHeight - 1);
  mCanvas.LineTo(FBox.Width, RowHeight - 1);
  if Length(FRows) = 0 then
  begin
    PaintCell(mCanvas, Rect(0, RowHeight, FBox.Width, 2 * RowHeight), FEmptyText, TAtlasGridMark.None, False, True);
    Exit;
  end;
  mTop := RowHeight;
  for mIndex := 0 to High(FRows) do
  begin
    PaintRow(mCanvas, FRows[mIndex], mTop, mIndex = FSelected);
    Inc(mTop, RowHeight);
  end;
end;

end.
