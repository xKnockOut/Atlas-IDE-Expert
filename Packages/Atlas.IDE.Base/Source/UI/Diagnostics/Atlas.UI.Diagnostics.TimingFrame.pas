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
    /// <summary>Zelle der Spalte AColumn (0 = Schritt, 1–4 = Werte) in der Zeile ab ATop.</summary>
    function CellRect(const ABounds: TRect; ATop, AColumn: Integer): TRect;
    /// <summary>Text einer Zelle; AWarn hebt über dem Budget hervor, AMuted zeichnet gedämpft.</summary>
    procedure DrawCell(const ARect: TRect; const AText: string; AWarn, ARight, AMuted: Boolean);
    procedure DrawHeader(const ABounds: TRect);
    procedure DrawRow(const ABounds: TRect; ATop: Integer; const ARow: TAtlasTimingRow);
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
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.Strings;

const
  // Spalten der Zeitentabelle: Schritt, letzte, Mittel, Maximum, Budget.
  cColumnStep = 0;
  cColumnLast = 1;
  cColumnMean = 2;
  cColumnMax = 3;
  cColumnBudget = 4;

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
  FBottom.Height := FBottom.ScaleValue(56);
  FLegend := TLabel.Create(Self);
  FLegend.Parent := FBottom;
  FLegend.Left := FLegend.ScaleValue(4);
  FLegend.Top := FLegend.ScaleValue(2);
  FLegend.ShowAccelChar := False;
  FLegend.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticLegend);
  FLegend.Font.Color := clGrayText;
  FFileNames := TCheckBox.Create(Self);
  FFileNames.Parent := FBottom;
  FFileNames.Left := FFileNames.ScaleValue(4);
  FFileNames.Top := FFileNames.ScaleValue(26);
  FFileNames.Width := FFileNames.ScaleValue(200);
  FFileNames.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticFileNames);
  FFileNames.Checked := False;
  FCopy := TButton.Create(Self);
  FCopy.Parent := FBottom;
  FCopy.Left := FCopy.ScaleValue(210);
  FCopy.Top := FCopy.ScaleValue(22);
  FCopy.Width := FCopy.ScaleValue(130);
  FCopy.Caption := TAtlasStrings.Text(TAtlasTextId.DiagnosticCopy);
  FCopy.OnClick := CopyClick;
  FNote := TLabel.Create(Self);
  FNote.Parent := FBottom;
  FNote.Left := FNote.ScaleValue(348);
  FNote.Top := FNote.ScaleValue(27);
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
      Result := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagnosticRowProvider, [ARow.Name]);
    TAtlasTimingRowKind.Entries:
      Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticRowEntries);
  else
    case ARow.Step of
      TAtlasTimingStep.Context:
        Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticRowContext);
      TAtlasTimingStep.FilterSort:
        Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticRowFilter);
      TAtlasTimingStep.Draw:
        Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticRowDraw);
    else
      Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticRowFirst);
    end;
  end;
end;

procedure TAtlasTimingFrame.UpdateTitle;
var
  mLast: TAtlasQueryTiming;
begin
  if Length(FQueries) = 0 then
  begin
    FTitle.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticNoQuery);
    Exit;
  end;
  mLast := FQueries[High(FQueries)];
  FTitle.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagnosticLastQuery, [mLast.Kind,
    FormatDateTime('hh":"nn":"ss', mLast.Started)]);
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
  begin
    FOnCopy(FFileNames.Checked);
  end;
end;

type
  TCellTexts = array[0..4] of string;
  TCellWarns = array[0..4] of Boolean;

/// <summary>Texte und Warnmarken der Spalten einer Zeile: Zähler ohne Budget, Zeiten in ms.</summary>
procedure RowCells(const ARow: TAtlasTimingRow; out ATexts: TCellTexts; out AWarns: TCellWarns);
begin
  ATexts[0] := TAtlasTimingFrame.Caption(ARow);
  if ARow.Kind = TAtlasTimingRowKind.Entries then
  begin
    ATexts[1] := TAtlasTimingRows.CountText(ARow.Last);
    ATexts[2] := TAtlasTimingRows.CountText(ARow.Mean);
    ATexts[3] := TAtlasTimingRows.CountText(ARow.Maximum);
    ATexts[4] := '';
  end
  else
  begin
    ATexts[1] := TAtlasTimingRows.Ms(ARow.Last);
    ATexts[2] := TAtlasTimingRows.Ms(ARow.Mean);
    ATexts[3] := TAtlasTimingRows.Ms(ARow.Maximum);
    ATexts[4] := TAtlasTimingRows.Ms(ARow.Budget);
  end;
  AWarns[0] := False;
  AWarns[1] := ARow.LastWarn;
  AWarns[2] := ARow.MeanWarn;
  AWarns[3] := ARow.MaxWarn;
  AWarns[4] := False;
end;

function TAtlasTimingFrame.CellRect(const ABounds: TRect; ATop, AColumn: Integer): TRect;
var
  mValueWidth: Integer;
begin
  mValueWidth := Scale(72);
  if AColumn = 0 then
  begin
    Result := Rect(ABounds.Left, ATop, ABounds.Right - 4 * mValueWidth, ATop + RowHeight);
  end
  else
  begin
    Result := Rect(ABounds.Right - (5 - AColumn) * mValueWidth, ATop, ABounds.Right - (4 - AColumn) * mValueWidth,
      ATop + RowHeight);
  end;
end;

procedure TAtlasTimingFrame.DrawCell(const ARect: TRect; const AText: string; AWarn, ARight, AMuted: Boolean);
const
  cTextFlags = DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS;
var
  mCanvas: TCanvas;
  mRect: TRect;
  mFlags: Cardinal;
begin
  mCanvas := FGrid.Canvas;
  mCanvas.Font.Style := [];
  if AWarn then
  begin
    mCanvas.Brush.Style := bsSolid;
    mCanvas.Brush.Color := ToColor(FColors.WarnSoft);
    mCanvas.FillRect(ARect);
    mCanvas.Font.Color := ToColor(FColors.Warn);
    mCanvas.Font.Style := [fsBold];
  end
  else if AMuted then
  begin
    mCanvas.Font.Color := ToColor(FColors.Muted);
  end
  else
  begin
    mCanvas.Font.Color := ToColor(FColors.Text);
  end;
  mCanvas.Brush.Style := bsClear;
  mRect := ARect;
  InflateRect(mRect, -Scale(4), 0);
  mFlags := cTextFlags or DT_LEFT;
  if ARight then
  begin
    mFlags := cTextFlags or DT_RIGHT;
  end;
  DrawText(mCanvas.Handle, PChar(AText), Length(AText), mRect, mFlags);
end;

procedure TAtlasTimingFrame.DrawHeader(const ABounds: TRect);
var
  mTexts: TCellTexts;
  mColumn: Integer;
begin
  mTexts[cColumnStep] := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticColumnStep);
  mTexts[cColumnLast] := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticColumnLast);
  mTexts[cColumnMean] := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagnosticColumnMean,
    [Length(FQueries)]);
  mTexts[cColumnMax] := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticColumnMax);
  mTexts[cColumnBudget] := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticColumnBudget);
  for mColumn := cColumnStep to cColumnBudget do
  begin
    DrawCell(CellRect(ABounds, ABounds.Top, mColumn), mTexts[mColumn], False, mColumn > 0, True);
  end;
  FGrid.Canvas.Pen.Color := ToColor(FColors.Line);
  FGrid.Canvas.MoveTo(ABounds.Left, ABounds.Top + RowHeight - 1);
  FGrid.Canvas.LineTo(ABounds.Right, ABounds.Top + RowHeight - 1);
end;

procedure TAtlasTimingFrame.DrawRow(const ABounds: TRect; ATop: Integer; const ARow: TAtlasTimingRow);
var
  mTexts: TCellTexts;
  mWarns: TCellWarns;
  mCell: TRect;
  mColumn: Integer;
begin
  RowCells(ARow, mTexts, mWarns);
  for mColumn := 0 to 4 do
  begin
    mCell := CellRect(ABounds, ATop, mColumn);
    // Quellen eingerückt unter dem Kontext.
    if (mColumn = 0) and (ARow.Kind = TAtlasTimingRowKind.Provider) then
    begin
      Inc(mCell.Left, Scale(12));
    end;
    DrawCell(mCell, mTexts[mColumn], mWarns[mColumn], mColumn > 0, mColumn = 4);
  end;
end;

procedure TAtlasTimingFrame.GridPaint(Sender: TObject);
var
  mBounds: TRect;
  mTop, mIndex: Integer;
begin
  mBounds := FGrid.ClientRect;
  FGrid.Canvas.Font := Font;
  FGrid.Canvas.Brush.Style := bsSolid;
  FGrid.Canvas.Brush.Color := ToColor(FColors.Surface);
  FGrid.Canvas.FillRect(mBounds);
  DrawHeader(mBounds);
  mTop := mBounds.Top + RowHeight;
  for mIndex := 0 to High(FRows) do
  begin
    DrawRow(mBounds, mTop, FRows[mIndex]);
    Inc(mTop, RowHeight);
  end;
end;

end.
