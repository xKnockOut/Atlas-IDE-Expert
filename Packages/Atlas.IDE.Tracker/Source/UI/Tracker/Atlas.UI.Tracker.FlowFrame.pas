unit Atlas.UI.Tracker.FlowFrame;

// Inhalt des andockbaren Fensters „Atlas-Ablauf“ (#2125), reine VCL ohne Open
// Tools API:
//   ATL · 90 Tage · 214 Issues · 611 Wechsel            [Aktualisieren]
//   (Stand vom … bzw. Fehler)
//   ┌────────┐ 142 ┌──────────────┐ 131 ┌─────────────┐
//   │ Offen  │════▶│In Bearbeitung│════▶│ Zur Prüfung │ …
//   │⌀ 6,0 T │     │⌀ 2,5 T       │◀╌╌╌╌│⌀ 4,1 T      │
//   │3 offen │     │5 offen · 1 ich│ 27 │7 offen · 2 l.│
//   └────────┘     └──────────────┘     └─────────────┘
//   ─────────────────────────────────────────────────────
//   Liegt lange (ab 5 Tagen)
//   Kennung   Titel …            Zustand      seit      Zuständig
// Zustände als Kästen (Hauptweg oben, Rest darunter), genutzte Übergänge als
// Pfeile: Dicke nach Anzahl, gestrichelt der Rückweg, die Zahl daneben.
// Zustände mit liegen gebliebenen Issues rot umrandet, erledigte mit „Ende“.
// Klick auf einen Zustand filtert die Liste (noch einmal: alle), Doppelklick
// auf eine Zeile meldet Events.Open (Vorschau, #1264). Anordnung ohne Fenster
// in TAtlasFlowLayout (testbar). Netz und Zwischenspeicher liegen in der
// IDE-Schicht. Die DFM ist leer, weil TCustomFrame.Create für abgeleitete
// Frames eine Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.FlowMap;

type
  /// <summary>Maße in Pixeln (schon skaliert).</summary>
  TAtlasFlowMetrics = record
    BoxWidth: Integer;
    BoxHeight: Integer;
    /// <summary>Abstand der Kästen in der Zeile (Platz für Pfeil und Zahl).</summary>
    ColumnGap: Integer;
    RowGap: Integer;
    /// <summary>Rand; oben dazu Platz für Bögen über den Hauptweg.</summary>
    Margin: Integer;
    ArcSpace: Integer;
    /// <summary>Maße bei 96 dpi aus der Zeilenhöhe der Schrift.</summary>
    class function Create(ALineHeight: Integer): TAtlasFlowMetrics; static;
    function Scaled(AMultiplier, ADivider: Integer): TAtlasFlowMetrics;
  end;

  /// <summary>Lage der Zustände; ohne Fenster berechnet (testbar).</summary>
  TAtlasFlowLayout = record
    /// <summary>Kasten je Zustand (gleicher Index wie TAtlasFlowMap.States).</summary>
    Boxes: TArray<TRect>;
    Width: Integer;
    Height: Integer;
    class function Build(const AMap: TAtlasFlowMap; const AMetrics: TAtlasFlowMetrics): TAtlasFlowLayout; static;
    /// <summary>Zustand unter APoint; -1 ohne.</summary>
    function StateAt(const APoint: TPoint): Integer;
  end;

  /// <summary>Linienzug eines Übergangs mit Platz für die Zahl.</summary>
  TAtlasFlowPath = record
    Points: TArray<TPoint>;
    LabelPoint: TPoint;
    /// <summary>Weg zwischen zwei Kästen: benachbart gerade (vorwärts oben, zurück unten versetzt), sonst als
    /// Bogen über (vorwärts) bzw. unter (zurück) der Zeile; zwischen Zeilen von Kante zu Kante.</summary>
    class function Build(const AFrom, ATo: TRect; ASameRow, ABack: Boolean; AArc: Integer): TAtlasFlowPath; static;
  end;

  /// <summary>Zeichenfläche der Karte.</summary>
  TAtlasFlowView = class(TCustomControl)
  private
    FMap: TAtlasFlowMap;
    FLayout: TAtlasFlowLayout;
    FColors: TAtlasColors;
    FSelected: string;
    FOnSelect: TProc<string>;
    function Metrics: TAtlasFlowMetrics;
    procedure PaintTransition(const ATransition: TAtlasFlowTransition; AMax: Integer);
    procedure PaintState(AIndex: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetMap(const AMap: TAtlasFlowMap);
    procedure Relayout;
    property Map: TAtlasFlowMap read FMap;
    property Layout: TAtlasFlowLayout read FLayout;
    property Colors: TAtlasColors read FColors write FColors;
    /// <summary>Gewählter Zustand ('' = keiner).</summary>
    property Selected: string read FSelected write FSelected;
    /// <summary>Klick auf einen Zustand bzw. daneben ('').</summary>
    property OnSelect: TProc<string> read FOnSelect write FOnSelect;
  end;

  /// <summary>Ereignisse des Frames; nil = nichts.</summary>
  TAtlasFlowFrameEvents = record
    Refresh: TProc;
    /// <summary>Issue in der Vorschau zeigen.</summary>
    Open: TProc<string>;
    /// <summary>Fenster geschlossen bzw. versteckt.</summary>
    Hidden: TProc;
  end;

  /// <summary>Steuerelemente des Frames; sie gehören dem Frame.</summary>
  TAtlasFlowFrameParts = record
    Head: TPanel;
    Summary: TLabel;
    Refresh: TButton;
    Status: TLabel;
    Scroll: TScrollBox;
    View: TAtlasFlowView;
    Empty: TLabel;
    Splitter: TSplitter;
    Bottom: TPanel;
    ListTitle: TLabel;
    List: TListView;
  end;

  TAtlasFlowFrame = class(TFrame)
  private
    FParts: TAtlasFlowFrameParts;
    FColors: TAtlasColors;
    FMap: TAtlasFlowMap;
    FHasMap: Boolean;
    FProject: string;
    FStuckDays: Integer;
    FRows: TArray<TAtlasFlowStuck>;
    FListPending: Boolean;
    FEvents: TAtlasFlowFrameEvents;
    procedure FillList;
    procedure SelectState(const AState: string);
    procedure RefreshClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure CMShowingChanged(var AMessage: TMessage); message CM_SHOWINGCHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Karte zeigen; AProject für die Kopfzeile, AStatus: Zeile darunter ('' = keine).</summary>
    procedure SetMap(const AMap: TAtlasFlowMap; const AProject: string; AStuckDays: Integer; const AStatus: string);
    /// <summary>Keine Karte (kein Tracker, Fehler): Text in der Mitte.</summary>
    procedure ShowNotice(const AText: string);
    procedure SetStatus(const AText: string);
    procedure SetLoading(AValue: Boolean);
    function StatusText: string;
    /// <summary>Zeilen der Liste nach dem gewählten Zustand.</summary>
    function VisibleRows: TArray<TAtlasFlowStuck>;
    /// <summary>Überschrift der Liste.</summary>
    function ListCaption: string;
    property Map: TAtlasFlowMap read FMap;
    property HasMap: Boolean read FHasMap;
    property Parts: TAtlasFlowFrameParts read FParts;
    property Events: TAtlasFlowFrameEvents read FEvents write FEvents;
  end;

  /// <summary>Texte eines Kastens und der Liste; ohne Fenster (testbar).</summary>
  TAtlasFlowTexts = class
  public
    /// <summary>"⌀ 2,5 T" bzw. "⌀ –".</summary>
    class function Average(const AState: TAtlasFlowState): string; static;
    /// <summary>"3 offen · 1 ich · 2 lange"; erledigt: "Ende".</summary>
    class function Counts(const AState: TAtlasFlowState): string; static;
    /// <summary>"ATL · 90 Tage · 214 Issues · 611 Wechsel" (unvollständig mit Zusatz).</summary>
    class function Summary(const AMap: TAtlasFlowMap; const AProject: string): string; static;
    /// <summary>"9 Tage" bzw. "> 90 Tage" vor dem Zeitraum.</summary>
    class function Since(const AStuck: TAtlasFlowStuck): string; static;
  end;

implementation

uses
  System.Math,
  Winapi.Windows,
  Atlas.Core.Style.Color,
  Atlas.UI.Tracker.Flow.Strings;

{$R *.dfm}

const
  // Maße bei 96 dpi; Höhen hängen an der Zeilenhöhe der Schrift.
  cBoxWidth = 150;
  // Zeilen eines Kastens: Name, Verweildauer, Zahlen.
  cBoxLines = 3;
  cBoxPadding = 14;
  cBoxInsetX = 6;
  cBoxInsetY = 4;
  cColumnGap = 64;
  cRowGapExtra = 40;
  cMargin = 12;
  cArcExtra = 16;
  // Ohne Fenster und ohne brauchbare Schrifthöhe angenommene Zeilenhöhe.
  cMinLineHeight = 8;
  cFallbackLineHeight = 15;
  // Bis zu so vielen Bogenhöhen Abstand gilt ein Ziel als benachbart (gerade Linie statt Bogen). 5 × cArcLift = 70:
  // Nachbarspalten (cColumnGap = 64) gerade, der übernächste Kasten (64 + 150 + 64) im Bogen.
  cAdjacentArcs = 5;
  cArcLift = 14;
  cArrowSize = 8;
  // Halber Öffnungswinkel der Pfeilspitze im Bogenmaß.
  cArrowSpread = 0.45;
  // Der häufigste Übergang wird so viel breiter als der seltenste.
  cMaxExtraPen = 3;
  cStuckPen = 2;
  cHeadHeight = 32;
  cRefreshWidth = 100;
  cTextMarginX = 8;
  cTextMarginY = 2;
  cTitleMarginTop = 4;
  cListHeight = 180;
  // Spalten: Schlüssel, Titel, Zustand, Seit, Zuständig.
  cColumnWidths: array[0..4] of Integer = (80, 260, 120, 80, 120);
  cEmptyTop = 40;
  cEmptyWidth = 300;
  cEmptyHeight = 60;
  cMinEmptyWidth = 100;
  cDefaultStuckDays = 5;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasFlowMetrics }

class function TAtlasFlowMetrics.Create(ALineHeight: Integer): TAtlasFlowMetrics;
begin
  Result.BoxWidth := cBoxWidth;
  Result.BoxHeight := cBoxLines * ALineHeight + cBoxPadding;
  Result.ColumnGap := cColumnGap;
  Result.RowGap := ALineHeight + cRowGapExtra;
  Result.Margin := cMargin;
  Result.ArcSpace := ALineHeight + cArcExtra;
end;

function TAtlasFlowMetrics.Scaled(AMultiplier, ADivider: Integer): TAtlasFlowMetrics;
begin
  Result := Self;
  if (ADivider <= 0) or (AMultiplier = ADivider) then
  begin
    Exit;
  end;
  Result.BoxWidth := MulDiv(BoxWidth, AMultiplier, ADivider);
  Result.ColumnGap := MulDiv(ColumnGap, AMultiplier, ADivider);
  Result.Margin := MulDiv(Margin, AMultiplier, ADivider);
end;

{ TAtlasFlowLayout }

class function TAtlasFlowLayout.Build(const AMap: TAtlasFlowMap; const AMetrics: TAtlasFlowMetrics): TAtlasFlowLayout;
var
  mIndex, mLeft, mTop: Integer;
begin
  Result := Default(TAtlasFlowLayout);
  SetLength(Result.Boxes, Length(AMap.States));
  Result.Width := 0;
  Result.Height := 0;
  for mIndex := 0 to High(AMap.States) do
  begin
    mLeft := AMetrics.Margin + AMap.States[mIndex].Column * (AMetrics.BoxWidth + AMetrics.ColumnGap);
    mTop := AMetrics.Margin + AMetrics.ArcSpace + AMap.States[mIndex].Row * (AMetrics.BoxHeight + AMetrics.RowGap);
    Result.Boxes[mIndex] := TRect.Create(mLeft, mTop, mLeft + AMetrics.BoxWidth, mTop + AMetrics.BoxHeight);
    Result.Width := Max(Result.Width, Result.Boxes[mIndex].Right + AMetrics.Margin);
    // Unter der Zeile Platz für Bögen der Rückwege.
    Result.Height := Max(Result.Height, Result.Boxes[mIndex].Bottom + AMetrics.ArcSpace + AMetrics.Margin);
  end;
end;

function TAtlasFlowLayout.StateAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Boxes) do
  begin
    if Boxes[mIndex].Contains(APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TAtlasFlowPath }

/// <summary>Weg zwischen zwei Zeilen: von der unteren bzw. oberen Kante zur gegenüberliegenden.</summary>
function CrossRowPoints(const AFrom, ATo: TRect): TArray<TPoint>;
begin
  if AFrom.Top < ATo.Top then
  begin
    Result := TArray<TPoint>.Create(TPoint.Create(AFrom.CenterPoint.X, AFrom.Bottom),
      TPoint.Create(ATo.CenterPoint.X, ATo.Top));
    Exit;
  end;
  Result := TArray<TPoint>.Create(TPoint.Create(AFrom.CenterPoint.X, AFrom.Top),
    TPoint.Create(ATo.CenterPoint.X, ATo.Bottom));
end;

/// <summary>Weiter entfernt in derselben Zeile: vorwärts Bogen darüber, zurück darunter.</summary>
function ArcPoints(const AFrom, ATo: TRect; ABack: Boolean; AArc: Integer): TArray<TPoint>;
begin
  if ABack then
  begin
    Result := TArray<TPoint>.Create(TPoint.Create(AFrom.CenterPoint.X, AFrom.Bottom),
      TPoint.Create(AFrom.CenterPoint.X, AFrom.Bottom + AArc), TPoint.Create(ATo.CenterPoint.X, ATo.Bottom + AArc),
      TPoint.Create(ATo.CenterPoint.X, ATo.Bottom));
    Exit;
  end;
  Result := TArray<TPoint>.Create(TPoint.Create(AFrom.CenterPoint.X, AFrom.Top),
    TPoint.Create(AFrom.CenterPoint.X, AFrom.Top - AArc), TPoint.Create(ATo.CenterPoint.X, ATo.Top - AArc),
    TPoint.Create(ATo.CenterPoint.X, ATo.Top));
end;

/// <summary>Weg in derselben Zeile: benachbart gerade (vorwärts im oberen, zurück im unteren Drittel), sonst
/// Bogen.</summary>
function SameRowPoints(const AFrom, ATo: TRect; ABack: Boolean; AArc: Integer): TArray<TPoint>;
var
  mY, mFromX, mToX: Integer;
begin
  mFromX := AFrom.Left;
  mToX := ATo.Right;
  if ATo.Left > AFrom.Left then
  begin
    mFromX := AFrom.Right;
    mToX := ATo.Left;
  end;
  if Abs(mToX - mFromX) > AArc * cAdjacentArcs then
  begin
    Exit(ArcPoints(AFrom, ATo, ABack, AArc));
  end;
  mY := AFrom.Top + AFrom.Height div cBoxLines;
  if ABack then
  begin
    mY := AFrom.Top + (2 * AFrom.Height) div cBoxLines;
  end;
  Result := TArray<TPoint>.Create(TPoint.Create(mFromX, mY), TPoint.Create(mToX, mY));
end;

class function TAtlasFlowPath.Build(const AFrom, ATo: TRect; ASameRow, ABack: Boolean; AArc: Integer): TAtlasFlowPath;
var
  mFirst, mSecond: TPoint;
begin
  Result := Default(TAtlasFlowPath);
  if ASameRow then
  begin
    Result.Points := SameRowPoints(AFrom, ATo, ABack, AArc);
  end
  else
  begin
    Result.Points := CrossRowPoints(AFrom, ATo);
  end;
  // Zahl in der Mitte des mittleren Abschnitts.
  mFirst := Result.Points[(Length(Result.Points) - 1) div 2];
  mSecond := Result.Points[Length(Result.Points) div 2];
  Result.LabelPoint := TPoint.Create((mFirst.X + mSecond.X) div 2, (mFirst.Y + mSecond.Y) div 2);
end;

{ TAtlasFlowTexts }

class function TAtlasFlowTexts.Average(const AState: TAtlasFlowState): string;
begin
  if AState.AverageDays < 0 then
  begin
    Exit(TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowNoAverage));
  end;
  Result := TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowAverage,
    [FormatFloat('0.0', AState.AverageDays, FormatSettings)]);
end;

class function TAtlasFlowTexts.Counts(const AState: TAtlasFlowState): string;
begin
  if AState.Resolved then
  begin
    Exit(TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowEnd));
  end;
  Result := TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowOpen, [AState.OpenCount]);
  if AState.MineCount > 0 then
  begin
    Result := Result + TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowMine, [AState.MineCount]);
  end;
  if AState.StuckCount > 0 then
  begin
    Result := Result + TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowStuckMark, [AState.StuckCount]);
  end;
end;

class function TAtlasFlowTexts.Summary(const AMap: TAtlasFlowMap; const AProject: string): string;
begin
  Result := TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowSummary, [AProject, AMap.Days, AMap.IssueCount,
    AMap.ChangeCount]);
  if AMap.Truncated then
  begin
    Result := Result + TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowTruncated);
  end;
end;

class function TAtlasFlowTexts.Since(const AStuck: TAtlasFlowStuck): string;
begin
  if AStuck.Before then
  begin
    Exit(TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowDaysBefore, [AStuck.Days]));
  end;
  Result := TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowDays, [AStuck.Days]);
end;

{ TAtlasFlowView }

constructor TAtlasFlowView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FColors := TAtlasColors.Light;
end;

function TAtlasFlowView.Metrics: TAtlasFlowMetrics;
var
  mLine: Integer;
begin
  mLine := Abs(Font.Height);
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    mLine := Canvas.TextHeight('Ag');
  end
  else if mLine < cMinLineHeight then
  begin
    mLine := cFallbackLineHeight;
  end;
  Result := TAtlasFlowMetrics.Create(mLine).Scaled(CurrentPPI, USER_DEFAULT_SCREEN_DPI);
end;

procedure TAtlasFlowView.SetMap(const AMap: TAtlasFlowMap);
begin
  FMap := AMap;
  if FMap.IndexOf(FSelected) < 0 then
  begin
    FSelected := '';
  end;
end;

procedure TAtlasFlowView.Relayout;
begin
  FLayout := TAtlasFlowLayout.Build(FMap, Metrics);
  SetBounds(0, 0, Max(FLayout.Width, 1), Max(FLayout.Height, 1));
  Invalidate;
end;

/// <summary>Pfeilspitze am Ende von ATo, aus Richtung AFrom.</summary>
procedure PaintArrowHead(ACanvas: TCanvas; const AFrom, ATo: TPoint; ASize: Integer);
var
  mAngle: Double;
  mPoints: array[0..2] of TPoint;
begin
  mAngle := ArcTan2(ATo.Y - AFrom.Y, ATo.X - AFrom.X);
  mPoints[0] := ATo;
  mPoints[1] := TPoint.Create(ATo.X - Round(ASize * Cos(mAngle - cArrowSpread)),
    ATo.Y - Round(ASize * Sin(mAngle - cArrowSpread)));
  mPoints[2] := TPoint.Create(ATo.X - Round(ASize * Cos(mAngle + cArrowSpread)),
    ATo.Y - Round(ASize * Sin(mAngle + cArrowSpread)));
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ACanvas.Pen.Color;
  ACanvas.Polygon(mPoints);
end;

procedure TAtlasFlowView.PaintTransition(const ATransition: TAtlasFlowTransition; AMax: Integer);
var
  mFrom, mTo: TAtlasFlowState;
  mPath: TAtlasFlowPath;
  mText: string;
  mSize: TSize;
  mHighlight: Boolean;
begin
  mFrom := FMap.States[ATransition.FromIndex];
  mTo := FMap.States[ATransition.ToIndex];
  mPath := TAtlasFlowPath.Build(FLayout.Boxes[ATransition.FromIndex], FLayout.Boxes[ATransition.ToIndex],
    mFrom.Row = mTo.Row, ATransition.Back, ScaleValue(cArcLift));
  mHighlight := (FSelected <> '') and (SameText(mFrom.Name, FSelected) or SameText(mTo.Name, FSelected));
  Canvas.Pen.Color := ToColor(FColors.Muted);
  if mHighlight then
  begin
    Canvas.Pen.Color := ToColor(FColors.Accent);
  end;
  // Dicke nach Anzahl; gestrichelt geht unter Windows nur mit Breite 1.
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := ScaleValue(1 + (cMaxExtraPen * ATransition.Count) div Max(1, AMax));
  if ATransition.Back then
  begin
    Canvas.Pen.Style := psDash;
    Canvas.Pen.Width := 1;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Polyline(mPath.Points);
  PaintArrowHead(Canvas, mPath.Points[High(mPath.Points) - 1], mPath.Points[High(mPath.Points)],
    ScaleValue(cArrowSize));
  mText := IntToStr(ATransition.Count);
  Canvas.Font.Style := [];
  Canvas.Font.Color := Canvas.Pen.Color;
  mSize := Canvas.TextExtent(mText);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.TextOut(mPath.LabelPoint.X - mSize.cx div 2, mPath.LabelPoint.Y - mSize.cy - ScaleValue(1), mText);
end;

procedure TAtlasFlowView.PaintState(AIndex: Integer);
var
  mState: TAtlasFlowState;
  mBox, mLine: TRect;
  mText: string;
  mHeight: Integer;
begin
  mState := FMap.States[AIndex];
  mBox := FLayout.Boxes[AIndex];
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  if SameText(mState.Name, FSelected) then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.Pen.Width := 1;
  // Liegen hier Issues lange, rot umrandet.
  if mState.StuckCount > 0 then
  begin
    Canvas.Pen.Color := ToColor(FColors.Error);
    Canvas.Pen.Width := ScaleValue(cStuckPen);
  end;
  Canvas.Rectangle(mBox);
  Canvas.Brush.Style := bsClear;
  mHeight := (mBox.Height - ScaleValue(2 * cBoxInsetY)) div cBoxLines;
  mLine := TRect.Create(mBox.Left + ScaleValue(cBoxInsetX), mBox.Top + ScaleValue(cBoxInsetY),
    mBox.Right - ScaleValue(cBoxInsetX), mBox.Top + ScaleValue(cBoxInsetY) + mHeight);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  mText := mState.Name;
  DrawText(Canvas.Handle, PChar(mText), Length(mText), mLine, DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS or
    DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(FColors.Muted);
  mLine.Offset(0, mHeight);
  mText := TAtlasFlowTexts.Average(mState);
  DrawText(Canvas.Handle, PChar(mText), Length(mText), mLine, DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS or
    DT_NOPREFIX);
  mLine.Offset(0, mHeight);
  mText := TAtlasFlowTexts.Counts(mState);
  if mState.StuckCount > 0 then
  begin
    Canvas.Font.Color := ToColor(FColors.Error);
  end;
  DrawText(Canvas.Handle, PChar(mText), Length(mText), mLine, DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS or
    DT_NOPREFIX);
end;

procedure TAtlasFlowView.Paint;
var
  mIndex, mMax: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if Length(FLayout.Boxes) <> Length(FMap.States) then
  begin
    Exit;
  end;
  mMax := FMap.MaxCount;
  for mIndex := 0 to High(FMap.Transitions) do
  begin
    PaintTransition(FMap.Transitions[mIndex], mMax);
  end;
  for mIndex := 0 to High(FMap.States) do
  begin
    PaintState(mIndex);
  end;
end;

procedure TAtlasFlowView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mName: string;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mIndex := FLayout.StateAt(TPoint.Create(X, Y));
  mName := '';
  // Noch einmal auf den gewählten Zustand: Filter aufheben.
  if (mIndex >= 0) and not SameText(FMap.States[mIndex].Name, FSelected) then
  begin
    mName := FMap.States[mIndex].Name;
  end;
  FSelected := mName;
  Invalidate;
  if Assigned(FOnSelect) then
  begin
    FOnSelect(mName);
  end;
end;

{ TAtlasFlowFrame }

/// <summary>Kopfzeile: Zusammenfassung links, Aktualisieren rechts.</summary>
procedure AddHead(AFrame: TAtlasFlowFrame);
begin
  AFrame.FParts.Head := TPanel.Create(AFrame);
  AFrame.FParts.Head.Height := AFrame.ScaleValue(cHeadHeight);
  AFrame.FParts.Head.Top := 0;
  AFrame.FParts.Head.Align := alTop;
  AFrame.FParts.Head.Parent := AFrame;
  AFrame.FParts.Head.BevelOuter := bvNone;
  AFrame.FParts.Head.ParentBackground := True;
  AFrame.FParts.Refresh := TButton.Create(AFrame);
  AFrame.FParts.Refresh.Parent := AFrame.FParts.Head;
  AFrame.FParts.Refresh.Caption := TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowRefresh);
  AFrame.FParts.Refresh.Width := AFrame.ScaleValue(cRefreshWidth);
  AFrame.FParts.Refresh.Align := alRight;
  AFrame.FParts.Refresh.AlignWithMargins := True;
  AFrame.FParts.Refresh.OnClick := AFrame.RefreshClick;
  AFrame.FParts.Summary := TLabel.Create(AFrame);
  AFrame.FParts.Summary.Parent := AFrame.FParts.Head;
  AFrame.FParts.Summary.Align := alClient;
  AFrame.FParts.Summary.Layout := tlCenter;
  AFrame.FParts.Summary.AlignWithMargins := True;
  AFrame.FParts.Summary.Margins.SetBounds(cTextMarginX, cTextMarginY, cTextMarginX, cTextMarginY);
  AFrame.FParts.Summary.Font.Style := [fsBold];
  AFrame.FParts.Summary.EllipsisPosition := epEndEllipsis;
end;

/// <summary>Liste „Liegt lange“ unten mit Trenner.</summary>
procedure AddList(AFrame: TAtlasFlowFrame);
var
  mColumn: TListColumn;
  mId: TAtlasFlowTextId;
  mIds: TArray<TAtlasFlowTextId>;
  mIndex: Integer;
begin
  AFrame.FParts.Bottom := TPanel.Create(AFrame);
  AFrame.FParts.Bottom.Height := AFrame.ScaleValue(cListHeight);
  AFrame.FParts.Bottom.Align := alBottom;
  AFrame.FParts.Bottom.Parent := AFrame;
  AFrame.FParts.Bottom.BevelOuter := bvNone;
  AFrame.FParts.Splitter := TSplitter.Create(AFrame);
  AFrame.FParts.Splitter.Align := alBottom;
  AFrame.FParts.Splitter.Parent := AFrame;
  AFrame.FParts.Splitter.Top := AFrame.FParts.Bottom.Top - 1;
  AFrame.FParts.ListTitle := TLabel.Create(AFrame);
  AFrame.FParts.ListTitle.Parent := AFrame.FParts.Bottom;
  AFrame.FParts.ListTitle.Align := alTop;
  AFrame.FParts.ListTitle.AlignWithMargins := True;
  AFrame.FParts.ListTitle.Margins.SetBounds(cTextMarginX, cTitleMarginTop, cTextMarginX, cTextMarginY);
  AFrame.FParts.ListTitle.Font.Style := [fsBold];
  AFrame.FParts.List := TListView.Create(AFrame);
  AFrame.FParts.List.Parent := AFrame.FParts.Bottom;
  AFrame.FParts.List.Align := alClient;
  AFrame.FParts.List.ViewStyle := vsReport;
  AFrame.FParts.List.ReadOnly := True;
  AFrame.FParts.List.RowSelect := True;
  AFrame.FParts.List.HideSelection := False;
  AFrame.FParts.List.BorderStyle := bsNone;
  AFrame.FParts.List.OnDblClick := AFrame.ListDblClick;
  mIds := TArray<TAtlasFlowTextId>.Create(TAtlasFlowTextId.FlowColumnKey, TAtlasFlowTextId.FlowColumnTitle,
    TAtlasFlowTextId.FlowColumnState, TAtlasFlowTextId.FlowColumnSince, TAtlasFlowTextId.FlowColumnAssignee);
  for mIndex := 0 to High(mIds) do
  begin
    mId := mIds[mIndex];
    mColumn := AFrame.FParts.List.Columns.Add;
    mColumn.Caption := TAtlasFlowStrings.Text(mId);
    mColumn.Width := AFrame.ScaleValue(cColumnWidths[mIndex]);
  end;
end;

/// <summary>Statuszeile und Fläche mit Zeichenfläche und Hinweis.</summary>
procedure AddBody(AFrame: TAtlasFlowFrame);
var
  mFrame: TAtlasFlowFrame;
begin
  AFrame.FParts.Status := TLabel.Create(AFrame);
  AFrame.FParts.Status.Parent := AFrame;
  AFrame.FParts.Status.Align := alTop;
  AFrame.FParts.Status.AlignWithMargins := True;
  AFrame.FParts.Status.Margins.SetBounds(cTextMarginX, cTextMarginY, cTextMarginX, cTextMarginY);
  AFrame.FParts.Status.WordWrap := True;
  AFrame.FParts.Status.Visible := False;
  AFrame.FParts.Status.Top := AFrame.FParts.Head.Top + AFrame.FParts.Head.Height + 1;
  AFrame.FParts.Scroll := TScrollBox.Create(AFrame);
  AFrame.FParts.Scroll.Parent := AFrame;
  AFrame.FParts.Scroll.Align := alClient;
  AFrame.FParts.Scroll.BorderStyle := bsNone;
  AFrame.FParts.Scroll.HorzScrollBar.Tracking := True;
  AFrame.FParts.Scroll.VertScrollBar.Tracking := True;
  AFrame.FParts.View := TAtlasFlowView.Create(AFrame);
  AFrame.FParts.View.Parent := AFrame.FParts.Scroll;
  AFrame.FParts.View.Visible := False;
  mFrame := AFrame;
  AFrame.FParts.View.OnSelect :=
    procedure(AState: string)
    begin
      mFrame.SelectState(AState);
    end;
  AFrame.FParts.Empty := TLabel.Create(AFrame);
  AFrame.FParts.Empty.Parent := AFrame.FParts.Scroll;
  AFrame.FParts.Empty.AutoSize := False;
  AFrame.FParts.Empty.Alignment := taCenter;
  AFrame.FParts.Empty.WordWrap := True;
  AFrame.FParts.Empty.SetBounds(0, AFrame.ScaleValue(cEmptyTop), AFrame.ScaleValue(cEmptyWidth),
    AFrame.ScaleValue(cEmptyHeight));
  AFrame.FParts.Empty.Visible := False;
end;

constructor TAtlasFlowFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FStuckDays := cDefaultStuckDays;
  AddHead(Self);
  AddList(Self);
  AddBody(Self);
  FParts.ListTitle.Caption := ListCaption;
end;

destructor TAtlasFlowFrame.Destroy;
begin
  if Assigned(FEvents.Hidden) then
  begin
    FEvents.Hidden();
  end;
  FEvents := Default(TAtlasFlowFrameEvents);
  FParts.View.OnSelect := nil;
  inherited;
end;

procedure TAtlasFlowFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  if Showing and FListPending then
  begin
    FillList;
  end;
  // Das X versteckt die Form samt Frame: wie Schließen.
  if not Showing and Assigned(FEvents.Hidden) then
  begin
    FEvents.Hidden();
  end;
end;

procedure TAtlasFlowFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FParts.View.Colors := AColors;
  FParts.Scroll.Color := ToColor(AColors.Surface);
  FParts.Scroll.ParentBackground := False;
  FParts.Empty.Font.Color := ToColor(AColors.Muted);
  FParts.Status.Font.Color := ToColor(AColors.Muted);
  FParts.List.Color := ToColor(AColors.Surface);
  FParts.List.Font.Color := ToColor(AColors.Text);
  FParts.View.Invalidate;
end;

function TAtlasFlowFrame.VisibleRows: TArray<TAtlasFlowStuck>;
begin
  Result := FMap.StuckIn(FParts.View.Selected);
end;

function TAtlasFlowFrame.ListCaption: string;
begin
  if FParts.View.Selected = '' then
  begin
    Result := TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowStuckTitle, [FStuckDays]);
  end
  else
  begin
    Result := TAtlasFlowStrings.Fmt(TAtlasFlowTextId.FlowStuckFilter, [FParts.View.Selected, FStuckDays]);
  end;
  if FHasMap and (Length(VisibleRows) = 0) then
  begin
    Result := Result + ' · ' + TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowNoStuck);
  end;
end;

procedure TAtlasFlowFrame.FillList;
var
  mStuck: TAtlasFlowStuck;
  mItem: TListItem;
begin
  FRows := VisibleRows;
  FParts.ListTitle.Caption := ListCaption;
  // Ohne Fenster legt die Liste keine Zeilen an: nachholen, sobald sie zu sehen ist.
  FListPending := not Showing;
  if FListPending then
  begin
    Exit;
  end;
  FParts.List.Items.BeginUpdate;
  try
    FParts.List.Items.Clear;
    for mStuck in FRows do
    begin
      mItem := FParts.List.Items.Add;
      mItem.Caption := mStuck.Key;
      mItem.SubItems.Add(mStuck.Title);
      mItem.SubItems.Add(mStuck.State);
      mItem.SubItems.Add(TAtlasFlowTexts.Since(mStuck));
      mItem.SubItems.Add(mStuck.Assignee);
    end;
  finally
    FParts.List.Items.EndUpdate;
  end;
end;

procedure TAtlasFlowFrame.SelectState(const AState: string);
begin
  FParts.View.Selected := AState;
  FillList;
end;

procedure TAtlasFlowFrame.SetMap(const AMap: TAtlasFlowMap; const AProject: string; AStuckDays: Integer;
  const AStatus: string);
begin
  FMap := AMap;
  FHasMap := True;
  FProject := AProject;
  FStuckDays := AStuckDays;
  FParts.Summary.Caption := TAtlasFlowTexts.Summary(AMap, AProject);
  FParts.View.SetMap(AMap);
  FParts.View.Visible := Length(AMap.States) > 0;
  FParts.View.Relayout;
  FParts.Empty.Visible := Length(AMap.States) = 0;
  FParts.Empty.Caption := TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowEmpty);
  FParts.Empty.Width := Max(FParts.Scroll.Width, ScaleValue(cMinEmptyWidth));
  SetStatus(AStatus);
  FillList;
end;

procedure TAtlasFlowFrame.ShowNotice(const AText: string);
begin
  FHasMap := False;
  FMap := Default(TAtlasFlowMap);
  FParts.View.SetMap(FMap);
  FParts.View.Visible := False;
  FParts.Summary.Caption := '';
  FParts.Empty.Caption := AText;
  FParts.Empty.Top := ScaleValue(cEmptyTop);
  FParts.Empty.Width := Max(FParts.Scroll.Width, ScaleValue(cMinEmptyWidth));
  FParts.Empty.Visible := AText <> '';
  FillList;
end;

procedure TAtlasFlowFrame.SetStatus(const AText: string);
begin
  FParts.Status.Caption := AText;
  FParts.Status.Visible := AText <> '';
end;

function TAtlasFlowFrame.StatusText: string;
begin
  Result := '';
  if FParts.Status.Visible then
  begin
    Result := FParts.Status.Caption;
  end;
end;

procedure TAtlasFlowFrame.SetLoading(AValue: Boolean);
begin
  FParts.Refresh.Enabled := not AValue;
  if AValue then
  begin
    SetStatus(TAtlasFlowStrings.Text(TAtlasFlowTextId.FlowLoading));
  end;
end;

procedure TAtlasFlowFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FEvents.Refresh) then
  begin
    FEvents.Refresh();
  end;
end;

procedure TAtlasFlowFrame.ListDblClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := -1;
  if FParts.List.Selected <> nil then
  begin
    mIndex := FParts.List.Selected.Index;
  end;
  if (mIndex >= 0) and (mIndex <= High(FRows)) and Assigned(FEvents.Open) then
  begin
    FEvents.Open(FRows[mIndex].Key);
  end;
end;

end.
