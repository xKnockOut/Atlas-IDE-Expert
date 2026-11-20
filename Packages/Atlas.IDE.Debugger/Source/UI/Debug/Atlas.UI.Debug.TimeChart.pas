unit Atlas.UI.Debug.TimeChart;

// Liniendiagramm über der Zeit seit Sitzungsbeginn, reine VCL; gemeinsamer
// Kern von Speicherverlauf (#858, TAtlasDebugMemoryChart) und Werteverlauf
// aus Logpunkten (#2552, TAtlasDebugValueChart). Die Ableitung liefert die
// Punkte (Zeit, Wert oder Lücke), den Wertebereich, den Text eines Werts und
// Marken; dieser Kern zeichnet Achse mit glatten Grenzen, Marken als
// senkrechte Linien (Halt gedämpft, Fehler rot, eigene Marke im Akzent mit
// Namen) und die Linie. Lücken unterbrechen die Linie. Mehr Punkte als Pixel
// fasst die Linie je Spalte zu Minimum und Maximum zusammen, damit Spitzen
// sichtbar bleiben. Ziehen mit der linken Maustaste wählt einen Bereich
// (OnSelection), Doppelklick hebt ihn auf, ein Klick ohne Zug meldet den
// Punkt davor (OnPointClick). Der Mauszeiger zeigt Zeit und Wert als Hinweis.
// Farben aus dem IDE-Thema; die Abbildung rechnet TAtlasTimeChartScale
// (Atlas.Core.Debug.TimeChart, getestet).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.TimeChart;

type
  {$SCOPEDENUMS ON}
  TAtlasTimeChartMarkKind = (Muted, Error, Accent);
  {$SCOPEDENUMS OFF}

  TAtlasTimeChartMark = record
    AtMs: Int64;
    Kind: TAtlasTimeChartMarkKind;
    /// <summary>Text neben der Linie; '' ohne.</summary>
    Name: string;
  end;

  /// <summary>Klick auf den Punkt AIndex (der letzte bis zur Stelle des Klicks).</summary>
  TAtlasTimeChartPointEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  TAtlasDebugTimeChart = class(TCustomControl)
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
    FDrag: TDrag;
    FSelection: TSelection;
    FEmptyText: string;
    FOnSelection: TNotifyEvent;
    FOnPointClick: TAtlasTimeChartPointEvent;
    function PlotRect: TRect;
    function ChartScale: TAtlasTimeChartScale;
    procedure PaintAxes(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale; const APlot: TRect);
    procedure PaintSelection(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale; const APlot: TRect);
    procedure PaintMarks(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale; const APlot: TRect);
    procedure PaintLine(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale; const APlot: TRect);
    procedure Changed;
  protected
    function Px(AValue: Integer): Integer;
    /// <summary>Zahl der Punkte.</summary>
    function PointCount: Integer; virtual; abstract;
    /// <summary>Zeit des Punkts AIndex in ms seit Sitzungsbeginn (aufsteigend).</summary>
    function PointAtMs(AIndex: Integer): Int64; virtual; abstract;
    /// <summary>Wert des Punkts AIndex; False für eine Lücke.</summary>
    function PointValue(AIndex: Integer; out AValue: Double): Boolean; virtual; abstract;
    /// <summary>Grenzen der Wertachse (glatt, siehe TAtlasTimeChartScale.NiceRange).</summary>
    procedure ValueRange(out ALow, AHigh: Double); virtual; abstract;
    /// <summary>Text eines Werts für Achse und Hinweis.</summary>
    function ValueText(AValue: Double): string; virtual; abstract;
    /// <summary>Hinweis zum Punkt AIndex aus Zeit (Sekunden als Text) und Wert (Text oder Lücke).</summary>
    function HoverOf(AIndex: Integer; const ASeconds: string): string; virtual; abstract;
    function MarkCount: Integer; virtual;
    function MarkAt(AIndex: Integer): TAtlasTimeChartMark; virtual;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeitpunkt (ms seit Sitzungsbeginn) an der Spalte AX des Steuerelements.</summary>
    function TimeAt(AX: Integer): Int64;
    /// <summary>Letzter Punkt bis zur Spalte AX; -1 ohne Punkte.</summary>
    function PointAt(AX: Integer): Integer;
    /// <summary>Hinweis an der Spalte AX: Zeit und Wert des Punkts davor; '' ohne Punkte.</summary>
    function HoverText(AX: Integer): string;
    /// <summary>Sekunden mit einer Nachkommastelle.</summary>
    class function Seconds(AMs: Int64): string; static;
    /// <summary>Bereich setzen (Reihenfolge egal), meldet OnSelection.</summary>
    procedure SelectRange(AFromMs, AToMs: Int64);
    procedure ClearSelection;
    property HasSelection: Boolean read FSelection.Has;
    property SelectionFromMs: Int64 read FSelection.FromMs;
    property SelectionToMs: Int64 read FSelection.ToMs;
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnSelection: TNotifyEvent read FOnSelection write FOnSelection;
    property OnPointClick: TAtlasTimeChartPointEvent read FOnPointClick write FOnPointClick;
    property PopupMenu;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Forms,
  Atlas.Core.Style.Color,
  Atlas.UI.Foundation.Theme;

const
  /// <summary>Teilstriche der Wertachse.</summary>
  cTicks = 4;
  /// <summary>Kürzester Zeitraum der Zeitachse in ms, damit der erste Punkt nicht am Rand klebt.</summary>
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
  /// <summary>Länge des Strichs bei einem einzelnen Punkt, logische Pixel.</summary>
  cSingleStroke = 3;
  /// <summary>Anteil des Akzents über der Fläche im gewählten Bereich.</summary>
  cSelectionAlpha = 0.15;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

type
  /// <summary>Zustand der Linie beim Zeichnen: Spalte des letzten Punkts mit Minimum und Maximum darin.</summary>
  TLineState = record
    Column: Integer;
    /// <summary>Tiefster (größtes Y) und höchster Punkt (kleinstes Y) der Spalte.</summary>
    Bottom: Integer;
    Top: Integer;
    Open: Boolean;
    Segment: Integer;
  end;

/// <summary>Punkt (AX, AY) an die Linie anfügen; in derselben Spalte nur Minimum und Maximum zeichnen (Spitzen
/// bleiben sichtbar, die Linie bleibt billig).</summary>
procedure LineStep(ACanvas: TCanvas; var AState: TLineState; AX, AY: Integer);
begin
  Inc(AState.Segment);
  if not AState.Open then
  begin
    ACanvas.MoveTo(AX, AY);
    AState.Open := True;
    AState.Segment := 1;
  end
  else if AX = AState.Column then
  begin
    if (AY < AState.Top) or (AY > AState.Bottom) then
    begin
      AState.Top := Min(AState.Top, AY);
      AState.Bottom := Max(AState.Bottom, AY);
      ACanvas.MoveTo(AX, AState.Bottom);
      ACanvas.LineTo(AX, AState.Top - 1);
    end;
    ACanvas.MoveTo(AX, AY);
    Exit;
  end
  else
  begin
    ACanvas.LineTo(AX, AY);
  end;
  AState.Column := AX;
  AState.Bottom := AY;
  AState.Top := AY;
end;

/// <summary>Linienstück beenden; ein einzelner Wert bekommt einen kurzen Strich der Länge AStroke statt nichts.
/// </summary>
procedure EndSegment(ACanvas: TCanvas; var AState: TLineState; AStroke: Integer);
begin
  if AState.Open and (AState.Segment = 1) then
  begin
    ACanvas.LineTo(AState.Column + AStroke, AState.Bottom);
  end;
  AState.Open := False;
  AState.Column := -1;
end;

{ TAtlasDebugTimeChart }

constructor TAtlasDebugTimeChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  ShowHint := True;
  Width := ScaleValue(cDefaultWidth);
  Height := ScaleValue(cDefaultHeight);
end;

class function TAtlasDebugTimeChart.Seconds(AMs: Int64): string;
begin
  Result := FormatFloat('0.0', AMs / 1000, FormatSettings);
end;

function TAtlasDebugTimeChart.MarkCount: Integer;
begin
  Result := 0;
end;

function TAtlasDebugTimeChart.MarkAt(AIndex: Integer): TAtlasTimeChartMark;
begin
  Result := Default(TAtlasTimeChartMark);
end;

procedure TAtlasDebugTimeChart.Paint;
var
  mColors: TAtlasColors;
  mScale: TAtlasTimeChartScale;
  mPlot: TRect;
  mSize: TSize;
begin
  mColors := TAtlasUiTheme.WindowColors(Self);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(mColors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := ToColor(mColors.Muted);
  if PointCount = 0 then
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

procedure TAtlasDebugTimeChart.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (ssDouble in Shift) or (PointCount = 0) then
  begin
    Exit;
  end;
  FDrag.Active := True;
  FDrag.StartX := X;
  FDrag.FromMs := TimeAt(X);
  FDrag.ToMs := FDrag.FromMs;
  MouseCapture := True;
end;

procedure TAtlasDebugTimeChart.MouseMove(Shift: TShiftState; X, Y: Integer);
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

procedure TAtlasDebugTimeChart.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if not FDrag.Active then
  begin
    Exit;
  end;
  FDrag.Active := False;
  MouseCapture := False;
  // Ein Klick ohne Zug wählt nichts, lässt eine bestehende Wahl stehen und meldet den Punkt.
  if Abs(X - FDrag.StartX) < Px(cMinDrag) then
  begin
    Invalidate;
    mIndex := PointAt(X);
    if (mIndex >= 0) and Assigned(FOnPointClick) then
    begin
      FOnPointClick(Self, mIndex);
    end;
    Exit;
  end;
  SelectRange(FDrag.FromMs, TimeAt(X));
end;

procedure TAtlasDebugTimeChart.DblClick;
begin
  inherited DblClick;
  FDrag.Active := False;
  ClearSelection;
end;

function TAtlasDebugTimeChart.Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasDebugTimeChart.PlotRect: TRect;
var
  mClient: TRect;
begin
  // ClientRect holt das Fenster (GetClientRect(Handle)); ohne Fenster, etwa bevor der Frame
  // gezeigt wird, entspricht die Fläche den Abmessungen (kein Rand).
  if HandleAllocated then
  begin
    mClient := ClientRect;
  end
  else
  begin
    mClient := TRect.Create(0, 0, Width, Height);
  end;
  Result := TRect.Create(Px(cPlotLeft), Px(cPlotTop), mClient.Right - Px(cPlotRight), mClient.Bottom - Px(cPlotBottom));
  if Result.Right <= Result.Left then
  begin
    Result.Right := Result.Left + 1;
  end;
  if Result.Bottom <= Result.Top then
  begin
    Result.Bottom := Result.Top + 1;
  end;
end;

function TAtlasDebugTimeChart.ChartScale: TAtlasTimeChartScale;
var
  mPlot: TRect;
  mFrom, mTo: Int64;
  mLow, mHigh: Double;
begin
  mPlot := PlotRect;
  mFrom := 0;
  mTo := cMinSpanMs;
  mLow := 0;
  mHigh := 1;
  if PointCount > 0 then
  begin
    mFrom := PointAtMs(0);
    mTo := Max(PointAtMs(PointCount - 1), mFrom + cMinSpanMs);
    ValueRange(mLow, mHigh);
  end;
  Result := TAtlasTimeChartScale.Make(mFrom, mTo, mLow, mHigh, mPlot.Width, mPlot.Height);
end;

procedure TAtlasDebugTimeChart.PaintAxes(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale;
  const APlot: TRect);
var
  mTick: Integer;
  mY: Integer;
  mValue: Double;
  mCaption: string;
  mSize: TSize;
begin
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ToColor(AColors.Muted);
  for mTick := 0 to cTicks do
  begin
    mValue := AScale.TickValue(mTick, cTicks);
    mY := APlot.Top + AScale.YOf(mValue);
    Canvas.Pen.Color := ToColor(AColors.Line);
    Canvas.MoveTo(APlot.Left, mY);
    Canvas.LineTo(APlot.Right, mY);
    mCaption := ValueText(mValue);
    mSize := Canvas.TextExtent(mCaption);
    Canvas.TextOut(APlot.Left - mSize.cx - Px(cLabelGap), mY - mSize.cy div 2, mCaption);
  end;
  mCaption := Seconds(AScale.FromMs) + ' s';
  Canvas.TextOut(APlot.Left, APlot.Bottom + Px(2), mCaption);
  mCaption := Seconds(AScale.ToMs) + ' s';
  mSize := Canvas.TextExtent(mCaption);
  Canvas.TextOut(APlot.Right - mSize.cx, APlot.Bottom + Px(2), mCaption);
end;

procedure TAtlasDebugTimeChart.PaintSelection(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale;
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

procedure TAtlasDebugTimeChart.PaintMarks(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale;
  const APlot: TRect);
var
  mIndex: Integer;
  mMark: TAtlasTimeChartMark;
  mX: Integer;
begin
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  for mIndex := 0 to MarkCount - 1 do
  begin
    mMark := MarkAt(mIndex);
    if (mMark.AtMs < AScale.FromMs) or (mMark.AtMs > AScale.ToMs) then
    begin
      Continue;
    end;
    mX := APlot.Left + AScale.XOf(mMark.AtMs);
    case mMark.Kind of
      TAtlasTimeChartMarkKind.Error:
        Canvas.Pen.Color := ToColor(AColors.Error);
      TAtlasTimeChartMarkKind.Accent:
        Canvas.Pen.Color := ToColor(AColors.Accent);
      TAtlasTimeChartMarkKind.Muted:
        Canvas.Pen.Color := ToColor(AColors.Muted);
    end;
    Canvas.Pen.Style := psDot;
    Canvas.MoveTo(mX, APlot.Top);
    Canvas.LineTo(mX, APlot.Bottom);
    if mMark.Name <> '' then
    begin
      Canvas.Font.Color := Canvas.Pen.Color;
      Canvas.TextOut(mX + Px(2), APlot.Top, mMark.Name);
    end;
  end;
  Canvas.Pen.Style := psSolid;
end;

procedure TAtlasDebugTimeChart.PaintLine(const AColors: TAtlasColors; const AScale: TAtlasTimeChartScale;
  const APlot: TRect);
var
  mIndex: Integer;
  mValue: Double;
  mLine: TLineState;
begin
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(AColors.Accent);
  Canvas.Pen.Width := Max(1, Px(2));
  mLine := Default(TLineState);
  mLine.Column := -1;
  for mIndex := 0 to PointCount - 1 do
  begin
    if PointValue(mIndex, mValue) then
    begin
      LineStep(Canvas, mLine, APlot.Left + AScale.XOf(PointAtMs(mIndex)), APlot.Top + AScale.YOf(mValue));
    end
    else
    begin
      // Lücke: die Linie setzt beim nächsten Wert neu an.
      EndSegment(Canvas, mLine, Px(cSingleStroke));
    end;
  end;
  EndSegment(Canvas, mLine, Px(cSingleStroke));
  Canvas.Pen.Width := 1;
end;

procedure TAtlasDebugTimeChart.Changed;
begin
  Invalidate;
  if Assigned(FOnSelection) then
  begin
    FOnSelection(Self);
  end;
end;

function TAtlasDebugTimeChart.TimeAt(AX: Integer): Int64;
begin
  Result := ChartScale.AtOf(AX - PlotRect.Left);
end;

function TAtlasDebugTimeChart.PointAt(AX: Integer): Integer;
var
  mAt: Int64;
  mIndex: Integer;
begin
  Result := -1;
  if PointCount = 0 then
  begin
    Exit;
  end;
  mAt := TimeAt(AX);
  Result := 0;
  for mIndex := 0 to PointCount - 1 do
  begin
    if PointAtMs(mIndex) > mAt then
    begin
      Break;
    end;
    Result := mIndex;
  end;
end;

function TAtlasDebugTimeChart.HoverText(AX: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := PointAt(AX);
  if mIndex >= 0 then
  begin
    Result := HoverOf(mIndex, Seconds(PointAtMs(mIndex)));
  end;
end;

procedure TAtlasDebugTimeChart.SelectRange(AFromMs, AToMs: Int64);
begin
  FSelection.Has := True;
  FSelection.FromMs := Min(AFromMs, AToMs);
  FSelection.ToMs := Max(AFromMs, AToMs);
  Changed;
end;

procedure TAtlasDebugTimeChart.ClearSelection;
begin
  if not FSelection.Has then
  begin
    Exit;
  end;
  FSelection := Default(TSelection);
  Changed;
end;

end.
