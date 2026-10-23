unit Atlas.UI.Diagnostics.TimingFrame;

// Inhalt des Diagnosefensters (#479), reine VCL: oben die letzte Abfrage (Art
// des Kontexts, Uhrzeit), darunter eine gezeichnete Tabelle mit je Schritt
// der letzten Abfrage, Mittelwert und Maximum der letzten 50 Abfragen und dem
// Budget aus #409; Werte über dem Budget stehen fett in Warnfarbe auf
// abgesetzter Fläche. Je Quelle der Vervollständigung eine Zeile mit ihrem
// Namen. Unten „Dateinamen in den Bericht“ (aus) und „Bericht kopieren“, das
// OnCopy mit dieser Wahl aufruft. Die Zeilen kommen aus TAtlasTimingRows; die
// IDE-Schicht bettet den Frame in ein andockbares Fenster ein und ruft
// SetQueries. Die DFM ist leer, weil TCustomFrame.Create für abgeleitete
// Frames eine Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Timing;

type
  TAtlasTimingFrame = class(TFrame)
  private
    FTitle: TLabel;
    FGrid: TPaintBox;
    FBottom: TPanel;
    FLegend: TLabel;
    FNote: TLabel;
    FFileNames: TCheckBox;
    FCopy: TButton;
    FColors: TAtlasColors;
    FQueries: TArray<TAtlasQueryTiming>;
    FRows: TArray<TAtlasTimingRow>;
    FOnCopy: TProc<Boolean>;
    function Scale(AValue: Integer): Integer;
    function RowHeight: Integer;
    procedure GridPaint(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure UpdateTitle;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Abfragen, älteste zuerst; zeichnet neu.</summary>
    procedure SetQueries(const AQueries: TArray<TAtlasQueryTiming>);
    /// <summary>Farben nach dem IDE-Thema (Fläche, Text, Warnfarbe).</summary>
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Kurzer Hinweis neben den Knöpfen, z. B. nach dem Kopieren.</summary>
    procedure ShowNote(const AText: string);
    /// <summary>Beschriftung einer Zeile in der Sprache der IDE.</summary>
    class function Caption(const ARow: TAtlasTimingRow): string; static;
    property Rows: TArray<TAtlasTimingRow> read FRows;
    property Title: TLabel read FTitle;
    property Grid: TPaintBox read FGrid;
    property FileNames: TCheckBox read FFileNames;
    property CopyButton: TButton read FCopy;
    property Note: TLabel read FNote;
    /// <summary>„Bericht kopieren“; Argument: Dateinamen aufnehmen.</summary>
    property OnCopy: TProc<Boolean> read FOnCopy write FOnCopy;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Strings;

{$R *.dfm}

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasTimingFrame }

constructor TAtlasTimingFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FColors := TAtlasColors.Light;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Self;
  FTitle.Align := alTop;
  FTitle.AlignWithMargins := True;
  FTitle.ShowAccelChar := False;
  FTitle.EllipsisPosition := epEndEllipsis;
  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.BevelOuter := bvNone;
  FBottom.ParentBackground := True;
  FBottom.Height := 56;
  FLegend := TLabel.Create(Self);
  FLegend.Parent := FBottom;
  FLegend.Left := 4;
  FLegend.Top := 2;
  FLegend.ShowAccelChar := False;
  FLegend.Caption := TAtlasStrings.Text(TAtlasTextId.DiagnosticLegend);
  FLegend.Font.Color := clGrayText;
  FFileNames := TCheckBox.Create(Self);
  FFileNames.Parent := FBottom;
  FFileNames.Left := 4;
  FFileNames.Top := 26;
  FFileNames.Width := 200;
  FFileNames.Caption := TAtlasStrings.Text(TAtlasTextId.DiagnosticFileNames);
  FFileNames.Checked := False;
  FCopy := TButton.Create(Self);
  FCopy.Parent := FBottom;
  FCopy.Left := 210;
  FCopy.Top := 22;
  FCopy.Width := 130;
  FCopy.Caption := TAtlasStrings.Text(TAtlasTextId.DiagnosticCopy);
  FCopy.OnClick := CopyClick;
  FNote := TLabel.Create(Self);
  FNote.Parent := FBottom;
  FNote.Left := 348;
  FNote.Top := 27;
  FNote.ShowAccelChar := False;
  FNote.Caption := '';
  FNote.Font.Color := clGrayText;
  FGrid := TPaintBox.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.AlignWithMargins := True;
  FGrid.OnPaint := GridPaint;
  SetQueries(nil);
end;

function TAtlasTimingFrame.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasTimingFrame.RowHeight: Integer;
begin
  Result := Scale(20);
end;

class function TAtlasTimingFrame.Caption(const ARow: TAtlasTimingRow): string;
begin
  case ARow.Kind of
    TAtlasTimingRowKind.Provider:
      Result := TAtlasStrings.Fmt(TAtlasTextId.DiagnosticRowProvider, [ARow.Name]);
    TAtlasTimingRowKind.Entries:
      Result := TAtlasStrings.Text(TAtlasTextId.DiagnosticRowEntries);
  else
    case ARow.Step of
      TAtlasTimingStep.Context:
        Result := TAtlasStrings.Text(TAtlasTextId.DiagnosticRowContext);
      TAtlasTimingStep.FilterSort:
        Result := TAtlasStrings.Text(TAtlasTextId.DiagnosticRowFilter);
      TAtlasTimingStep.Draw:
        Result := TAtlasStrings.Text(TAtlasTextId.DiagnosticRowDraw);
    else
      Result := TAtlasStrings.Text(TAtlasTextId.DiagnosticRowFirst);
    end;
  end;
end;

procedure TAtlasTimingFrame.UpdateTitle;
var
  Last: TAtlasQueryTiming;
begin
  if Length(FQueries) = 0 then
  begin
    FTitle.Caption := TAtlasStrings.Text(TAtlasTextId.DiagnosticNoQuery);
    Exit;
  end;
  Last := FQueries[High(FQueries)];
  FTitle.Caption := TAtlasStrings.Fmt(TAtlasTextId.DiagnosticLastQuery, [Last.Kind,
    FormatDateTime('hh":"nn":"ss', Last.Started)]);
end;

procedure TAtlasTimingFrame.SetQueries(const AQueries: TArray<TAtlasQueryTiming>);
begin
  FQueries := AQueries;
  FRows := TAtlasTimingRows.Build(FQueries);
  UpdateTitle;
  FGrid.Invalidate;
end;

procedure TAtlasTimingFrame.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FGrid.Invalidate;
end;

procedure TAtlasTimingFrame.ShowNote(const AText: string);
begin
  FNote.Caption := AText;
end;

procedure TAtlasTimingFrame.CopyClick(Sender: TObject);
begin
  if Assigned(FOnCopy) then
    FOnCopy(FFileNames.Checked);
end;

procedure TAtlasTimingFrame.GridPaint(Sender: TObject);
const
  TextFlags = DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS;
var
  Canvas: TCanvas;
  Bounds, Cell: TRect;
  ValueWidth, Top, Index, Column: Integer;
  Row: TAtlasTimingRow;
  Texts: array[0..4] of string;
  Warns: array[0..4] of Boolean;

  procedure DrawCell(const ARect: TRect; const AText: string; AWarn, ARight, AHeader: Boolean);
  var
    R: TRect;
    Flags: Cardinal;
  begin
    if AWarn then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(FColors.WarnSoft);
      Canvas.FillRect(ARect);
      Canvas.Font.Color := ToColor(FColors.Warn);
      Canvas.Font.Style := [fsBold];
    end
    else
    begin
      if AHeader then
        Canvas.Font.Color := ToColor(FColors.Muted)
      else
        Canvas.Font.Color := ToColor(FColors.Text);
      Canvas.Font.Style := [];
    end;
    Canvas.Brush.Style := bsClear;
    R := ARect;
    InflateRect(R, -Scale(4), 0);
    Flags := TextFlags;
    if ARight then
      Flags := Flags or DT_RIGHT
    else
      Flags := Flags or DT_LEFT;
    DrawText(Canvas.Handle, PChar(AText), Length(AText), R, Flags);
  end;

begin
  Canvas := FGrid.Canvas;
  Bounds := FGrid.ClientRect;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(Bounds);
  ValueWidth := Scale(72);
  // Kopfzeile.
  Texts[0] := TAtlasStrings.Text(TAtlasTextId.DiagnosticColumnStep);
  Texts[1] := TAtlasStrings.Text(TAtlasTextId.DiagnosticColumnLast);
  Texts[2] := TAtlasStrings.Fmt(TAtlasTextId.DiagnosticColumnMean, [Length(FQueries)]);
  Texts[3] := TAtlasStrings.Text(TAtlasTextId.DiagnosticColumnMax);
  Texts[4] := TAtlasStrings.Text(TAtlasTextId.DiagnosticColumnBudget);
  Top := Bounds.Top;
  for Column := 0 to 4 do
  begin
    if Column = 0 then
      Cell := Rect(Bounds.Left, Top, Bounds.Right - 4 * ValueWidth, Top + RowHeight)
    else
      Cell := Rect(Bounds.Right - (5 - Column) * ValueWidth, Top, Bounds.Right - (4 - Column) * ValueWidth,
        Top + RowHeight);
    DrawCell(Cell, Texts[Column], False, Column > 0, True);
  end;
  Inc(Top, RowHeight);
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(Bounds.Left, Top - 1);
  Canvas.LineTo(Bounds.Right, Top - 1);
  for Index := 0 to High(FRows) do
  begin
    Row := FRows[Index];
    Texts[0] := Caption(Row);
    Warns[0] := False;
    if Row.Kind = TAtlasTimingRowKind.Entries then
    begin
      Texts[1] := TAtlasTimingRows.CountText(Row.Last);
      Texts[2] := TAtlasTimingRows.CountText(Row.Mean);
      Texts[3] := TAtlasTimingRows.CountText(Row.Maximum);
      Texts[4] := '';
    end
    else
    begin
      Texts[1] := TAtlasTimingRows.Ms(Row.Last);
      Texts[2] := TAtlasTimingRows.Ms(Row.Mean);
      Texts[3] := TAtlasTimingRows.Ms(Row.Maximum);
      Texts[4] := TAtlasTimingRows.Ms(Row.Budget);
    end;
    Warns[1] := Row.LastWarn;
    Warns[2] := Row.MeanWarn;
    Warns[3] := Row.MaxWarn;
    Warns[4] := False;
    for Column := 0 to 4 do
    begin
      if Column = 0 then
        Cell := Rect(Bounds.Left, Top, Bounds.Right - 4 * ValueWidth, Top + RowHeight)
      else
        Cell := Rect(Bounds.Right - (5 - Column) * ValueWidth, Top, Bounds.Right - (4 - Column) * ValueWidth,
          Top + RowHeight);
      // Quellen eingerückt unter dem Kontext.
      if (Column = 0) and (Row.Kind = TAtlasTimingRowKind.Provider) then
        Inc(Cell.Left, Scale(12));
      DrawCell(Cell, Texts[Column], Warns[Column], Column > 0, Column = 4);
    end;
    Inc(Top, RowHeight);
  end;
end;

end.
