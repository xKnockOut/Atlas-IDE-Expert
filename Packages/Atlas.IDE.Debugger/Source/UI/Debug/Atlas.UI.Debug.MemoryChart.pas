unit Atlas.UI.Debug.MemoryChart;

// Linie des Speicherverlaufs (#858), reine VCL: eine Reihe (privater Speicher,
// Arbeitssatz, Handles, GDI- oder USER-Objekte) über der Zeit seit
// Sitzungsbeginn, Achse mit glatter Obergrenze, Marken als senkrechte Linien
// (Halt gedämpft, Exception rot, eigene Marke im Akzent mit Namen). Ziehen mit
// der linken Maustaste wählt einen Bereich (OnSelection), Doppelklick hebt ihn
// auf. Der Mauszeiger zeigt Zeit und Wert als Hinweis. Mehr Messungen als
// Pixel fasst die Linie je Spalte zu Minimum und Maximum zusammen, damit
// Spitzen sichtbar bleiben. Farben aus dem IDE-Thema; Abbildung und
// Formatierung rechnet der Kern (Atlas.Core.Debug.MemoryTimeline, getestet).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.MemoryTimeline;

type
  TAtlasDebugMemoryChart = class(TCustomControl)
  private type
    TDrag = record
      Active: Boolean;
      StartX: Integer;
      FromMs: Int64;
      ToMs: Int64;
    end;
    TSelection = record
      Has: Boolean;
      FromMs: Int64;
      ToMs: Int64;
    end;
  private
    FTimeline: TAtlasMemoryTimeline;
    FSeries: TAtlasMemorySeries;
    FDrag: TDrag;
    FSelection: TSelection;
    FEmptyText: string;
    FOnSelection: TNotifyEvent;
    function Px(AValue: Integer): Integer;
    function PlotRect: TRect;
    function ChartScale: TAtlasMemoryChartScale;
    procedure PaintAxes(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale; const APlot: TRect);
    procedure PaintSelection(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale; const APlot: TRect);
    procedure PaintMarks(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale; const APlot: TRect);
    procedure PaintLine(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale; const APlot: TRect);
    procedure SetSeries(AValue: TAtlasMemorySeries);
    procedure Changed;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeitpunkt (ms seit Sitzungsbeginn) an der Spalte AX des Steuerelements.</summary>
    function TimeAt(AX: Integer): Int64;
    /// <summary>Hinweis an der Spalte AX: Zeit und Wert der nächsten Messung davor; '' ohne Messung.</summary>
    function HoverText(AX: Integer): string;
    /// <summary>Bereich setzen (Reihenfolge egal), meldet OnSelection.</summary>
    procedure SelectRange(AFromMs, AToMs: Int64);
    procedure ClearSelection;
    /// <summary>Verlauf (nicht im Besitz); nil zeigt EmptyText.</summary>
    property Timeline: TAtlasMemoryTimeline read FTimeline write FTimeline;
    property Series: TAtlasMemorySeries read FSeries write SetSeries;
    property HasSelection: Boolean read FSelection.Has;
    property SelectionFromMs: Int64 read FSelection.FromMs;
    property SelectionToMs: Int64 read FSelection.ToMs;
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnSelection: TNotifyEvent read FOnSelection write FOnSelection;
    property PopupMenu;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.UI.Debug.Strings;

const
  /// <summary>Teilstriche der Wertachse.</summary>
  cTicks = 4;
  /// <summary>Kürzester Zeitraum der Zeitachse in ms, damit die erste Messung nicht am Rand klebt.</summary>
  cMinSpanMs = 10000;
  /// <summary>Kürzeste Zugstrecke in logischen Pixeln, die als Bereich gilt (sonst Klick).</summary>
  cMinDrag = 3;
  /// <summary>Größe vor dem ersten Ausrichten, logische Pixel.</summary>
  cDefaultWidth = 400;
  cDefaultHeight = 200;
  /// <summary>Ränder der Zeichenfläche (links Platz für die Werte, unten für die Zeit), logische Pixel.</summary>
  cPlotLeft = 64;
  cPlotTop = 8;
  cPlotRight = 10;
  cPlotBottom = 20;
  /// <summary>Abstand der Werte zur Fläche, logische Pixel.</summary>
  cLabelGap = 4;
  /// <summary>Länge des Strichs bei nur einer Messung, logische Pixel.</summary>
  cSingleStroke = 3;
  /// <summary>Anteil des Akzents über der Fläche im gewählten Bereich.</summary>
  cSelectionAlpha = 0.15;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function Seconds(AMs: Int64): string;
begin
  Result := FormatFloat('0.0', AMs / 1000, FormatSettings);
end;

{ TAtlasDebugMemoryChart }

constructor TAtlasDebugMemoryChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ShowHint := True;
  Width := ScaleValue(cDefaultWidth);
  Height := ScaleValue(cDefaultHeight);
end;

function TAtlasDebugMemoryChart.Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasDebugMemoryChart.PlotRect: TRect;
begin
  Result := TRect.Create(Px(cPlotLeft), Px(cPlotTop), ClientWidth - Px(cPlotRight), ClientHeight - Px(cPlotBottom));
  if Result.Right <= Result.Left then
  begin
    Result.Right := Result.Left + 1;
  end;
  if Result.Bottom <= Result.Top then
  begin
    Result.Bottom := Result.Top + 1;
  end;
end;

function TAtlasDebugMemoryChart.ChartScale: TAtlasMemoryChartScale;
var
  mPlot: TRect;
  mFrom: Int64;
  mTo: Int64;
  mMax: Int64;
begin
  mPlot := PlotRect;
  mFrom := 0;
  mTo := cMinSpanMs;
  mMax := 1;
  if (FTimeline <> nil) and (FTimeline.Count > 0) then
  begin
    mFrom := FTimeline[0].AtMs;
    mTo := Max(FTimeline[FTimeline.Count - 1].AtMs, mFrom + cMinSpanMs);
    mMax := TAtlasMemoryChartScale.NiceMax(Max(FTimeline.MaxOf(FSeries), 1));
  end;
  Result := TAtlasMemoryChartScale.Make(mFrom, mTo, mMax, mPlot.Width, mPlot.Height);
end;

procedure TAtlasDebugMemoryChart.SetSeries(AValue: TAtlasMemorySeries);
begin
  if AValue = FSeries then
  begin
    Exit;
  end;
  FSeries := AValue;
  Invalidate;
end;

procedure TAtlasDebugMemoryChart.Changed;
begin
  Invalidate;
  if Assigned(FOnSelection) then
  begin
    FOnSelection(Self);
  end;
end;

function TAtlasDebugMemoryChart.TimeAt(AX: Integer): Int64;
begin
  Result := ChartScale.AtOf(AX - PlotRect.Left);
end;

function TAtlasDebugMemoryChart.HoverText(AX: Integer): string;
var
  mAt: Int64;
  mIndex: Integer;
  mFound: Integer;
begin
  Result := '';
  if (FTimeline = nil) or (FTimeline.Count = 0) then
  begin
    Exit;
  end;
  mAt := TimeAt(AX);
  mFound := 0;
  for mIndex := 0 to FTimeline.Count - 1 do
  begin
    if FTimeline[mIndex].AtMs > mAt then
    begin
      Break;
    end;
    mFound := mIndex;
  end;
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MemoryHover, [Seconds(FTimeline[mFound].AtMs),
    TAtlasMemoryFormat.Value(FSeries, FTimeline[mFound].Values[FSeries], FormatSettings)]);
end;

procedure TAtlasDebugMemoryChart.SelectRange(AFromMs, AToMs: Int64);
begin
  FSelection.Has := True;
  FSelection.FromMs := Min(AFromMs, AToMs);
  FSelection.ToMs := Max(AFromMs, AToMs);
  Changed;
end;

procedure TAtlasDebugMemoryChart.ClearSelection;
begin
  if not FSelection.Has then
  begin
    Exit;
  end;
  FSelection := Default(TSelection);
  Changed;
end;

procedure TAtlasDebugMemoryChart.PaintAxes(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale;
  const APlot: TRect);
var
  mTick: Integer;
  mY: Integer;
  mCaption: string;
  mSize: TSize;
begin
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ToColor(AColors.Muted);
  for mTick := 0 to cTicks do
  begin
    mY := APlot.Top + AScale.YOf(AScale.MaxValue * mTick div cTicks);
    Canvas.Pen.Color := ToColor(AColors.Line);
    Canvas.MoveTo(APlot.Left, mY);
    Canvas.LineTo(APlot.Right, mY);
    mCaption := TAtlasMemoryFormat.Value(FSeries, AScale.MaxValue * mTick div cTicks, FormatSettings);
    mSize := Canvas.TextExtent(mCaption);
    Canvas.TextOut(APlot.Left - mSize.cx - Px(cLabelGap), mY - mSize.cy div 2, mCaption);
  end;
  mCaption := Seconds(AScale.FromMs) + ' s';
  Canvas.TextOut(APlot.Left, APlot.Bottom + Px(2), mCaption);
  mCaption := Seconds(AScale.ToMs) + ' s';
  mSize := Canvas.TextExtent(mCaption);
  Canvas.TextOut(APlot.Right - mSize.cx, APlot.Bottom + Px(2), mCaption);
end;

procedure TAtlasDebugMemoryChart.PaintSelection(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale;
  const APlot: TRect);
var
  mFrom: Int64;
  mTo: Int64;
begin
  if FDrag.Active then
  begin
    mFrom := Min(FDrag.FromMs, FDrag.ToMs);
    mTo := Max(FDrag.FromMs, FDrag.ToMs);
  end
  else if FSelection.Has then
  begin
    mFrom := FSelection.FromMs;
    mTo := FSelection.ToMs;
  end
  else
  begin
    Exit;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(TAtlasColorMath.Mix(AColors.Accent, AColors.Surface, cSelectionAlpha));
  Canvas.FillRect(TRect.Create(APlot.Left + AScale.XOf(mFrom), APlot.Top, APlot.Left + AScale.XOf(mTo) + 1,
    APlot.Bottom));
end;

procedure TAtlasDebugMemoryChart.PaintMarks(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale;
  const APlot: TRect);
var
  mIndex: Integer;
  mMark: TAtlasMemoryMark;
  mX: Integer;
begin
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  for mIndex := 0 to FTimeline.MarkCount - 1 do
  begin
    mMark := FTimeline.Marks[mIndex];
    if (mMark.AtMs < AScale.FromMs) or (mMark.AtMs > AScale.ToMs) then
    begin
      Continue;
    end;
    mX := APlot.Left + AScale.XOf(mMark.AtMs);
    case mMark.Kind of
      TAtlasMemoryMarkKind.Exception:
        Canvas.Pen.Color := ToColor(AColors.Error);
      TAtlasMemoryMarkKind.Custom:
        Canvas.Pen.Color := ToColor(AColors.Accent);
    else
      Canvas.Pen.Color := ToColor(AColors.Muted);
    end;
    Canvas.Pen.Style := psDot;
    Canvas.MoveTo(mX, APlot.Top);
    Canvas.LineTo(mX, APlot.Bottom);
    if mMark.Kind = TAtlasMemoryMarkKind.Custom then
    begin
      Canvas.Font.Color := ToColor(AColors.Accent);
      Canvas.TextOut(mX + Px(2), APlot.Top, mMark.Name);
    end;
  end;
  Canvas.Pen.Style := psSolid;
end;

procedure TAtlasDebugMemoryChart.PaintLine(const AColors: TAtlasColors; const AScale: TAtlasMemoryChartScale;
  const APlot: TRect);
var
  mIndex: Integer;
  mX: Integer;
  mY: Integer;
  mColumn: Integer;
  mLow: Integer;
  mHigh: Integer;
begin
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(AColors.Accent);
  Canvas.Pen.Width := Max(1, Px(2));
  mColumn := -1;
  mLow := 0;
  mHigh := 0;
  for mIndex := 0 to FTimeline.Count - 1 do
  begin
    mX := APlot.Left + AScale.XOf(FTimeline[mIndex].AtMs);
    mY := APlot.Top + AScale.YOf(FTimeline[mIndex].Values[FSeries]);
    if mIndex = 0 then
    begin
      Canvas.MoveTo(mX, mY);
    end
    else if mX = mColumn then
    begin
      // Gleiche Spalte: nur Minimum und Maximum zeichnen (Spitzen bleiben sichtbar, die Linie bleibt billig).
      if (mY < mHigh) or (mY > mLow) then
      begin
        mHigh := Min(mHigh, mY);
        mLow := Max(mLow, mY);
        Canvas.MoveTo(mX, mLow);
        Canvas.LineTo(mX, mHigh - 1);
      end;
      Canvas.MoveTo(mX, mY);
      Continue;
    end
    else
    begin
      Canvas.LineTo(mX, mY);
    end;
    mColumn := mX;
    mLow := mY;
    mHigh := mY;
  end;
  if FTimeline.Count = 1 then
  begin
    // Eine Messung: ein kurzer Strich statt nichts.
    mX := APlot.Left + AScale.XOf(FTimeline[0].AtMs);
    mY := APlot.Top + AScale.YOf(FTimeline[0].Values[FSeries]);
    Canvas.LineTo(mX + Px(cSingleStroke), mY);
  end;
  Canvas.Pen.Width := 1;
end;

procedure TAtlasDebugMemoryChart.Paint;
var
  mColors: TAtlasColors;
  mScale: TAtlasMemoryChartScale;
  mPlot: TRect;
  mSize: TSize;
begin
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(mColors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := ToColor(mColors.Muted);
  if (FTimeline = nil) or (FTimeline.Count = 0) then
  begin
    Canvas.Brush.Style := bsClear;
    mSize := Canvas.TextExtent(FEmptyText);
    Canvas.TextOut((ClientWidth - mSize.cx) div 2, (ClientHeight - mSize.cy) div 2, FEmptyText);
    Exit;
  end;
  mPlot := PlotRect;
  mScale := ChartScale;
  PaintSelection(mColors, mScale, mPlot);
  PaintAxes(mColors, mScale, mPlot);
  PaintMarks(mColors, mScale, mPlot);
  PaintLine(mColors, mScale, mPlot);
end;

procedure TAtlasDebugMemoryChart.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (ssDouble in Shift) or (FTimeline = nil) or (FTimeline.Count = 0) then
  begin
    Exit;
  end;
  FDrag.Active := True;
  FDrag.StartX := X;
  FDrag.FromMs := TimeAt(X);
  FDrag.ToMs := FDrag.FromMs;
  MouseCapture := True;
end;

procedure TAtlasDebugMemoryChart.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHint: string;
begin
  inherited MouseMove(Shift, X, Y);
  if FDrag.Active then
  begin
    FDrag.ToMs := TimeAt(X);
    Invalidate;
  end;
  mHint := HoverText(X);
  if mHint <> Hint then
  begin
    Hint := mHint;
    Application.CancelHint;
  end;
end;

procedure TAtlasDebugMemoryChart.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if not FDrag.Active then
  begin
    Exit;
  end;
  FDrag.Active := False;
  MouseCapture := False;
  // Ein Klick ohne Zug wählt nichts und lässt eine bestehende Wahl stehen.
  if Abs(X - FDrag.StartX) < Px(cMinDrag) then
  begin
    Invalidate;
    Exit;
  end;
  SelectRange(FDrag.FromMs, TimeAt(X));
end;

procedure TAtlasDebugMemoryChart.DblClick;
begin
  inherited DblClick;
  FDrag.Active := False;
  ClearSelection;
end;

end.
