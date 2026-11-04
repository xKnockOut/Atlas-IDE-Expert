unit Atlas.UI.Welcome.Trends;

// Bereich „Projektverlauf“ der Willkommensseite (#758), ohne Open Tools API:
//   Demo · letzte 30 Builds
//   ┌ WARNUNGEN + HINWEISE ┐ ┌ REGELTREFFER SEIT … ┐ ┌ OFFENE TODOS ┐ …
//   │ 0  vorher 3          │ │ 4  vorher 6         │ │ 17 vorher 17 │
//   │ ╲___ (Linie, Fläche) │ │ ── ──  (Lücke)      │ │ ──────────── │
//   Auf einen Punkt klicken, um den Build zu sehen.
// Je gewählter Reihe eine Kachel: Bezeichnung, letzter Wert mit Einheit,
// Vorwert („vorher 3“) und eine Linie mit Fläche über die gespeicherten Builds.
// Innerhalb einer Linie gilt eine Skala, die Nulllinie ist immer sichtbar,
// der letzte Punkt ist hervorgehoben. Fehlt ein Wert (z. B. ohne Baseline),
// bricht die Linie dort ab: Lücke statt 0. Ein Klick auf einen Punkt zeigt
// darunter Build-Nummer, Zeitpunkt, Branch, Commit und den Wert.
// Die Kacheln brechen nach Breite um. Daten kommen fertig über
// IAtlasTrendsSource aus der IDE-Schicht (Projekt-Zusammenfassung, #592);
// hier wird nur gezeichnet.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Trends,
  Atlas.UI.Welcome.Frame;

type
  IAtlasTrendsSource = interface
    ['{9C3B6E21-4A7D-4F18-B2E5-7D0A1C8F5E93}']
    /// <summary>Verlauf des gewählten (sonst obersten) Projekts mit den eingestellten Reihen.</summary>
    function View: TAtlasTrendView;
  end;

  TAtlasTrendsHit = record
    /// <summary>Kachel; -1 = keine.</summary>
    Tile: Integer;
    /// <summary>Punkt in der Linie der Kachel; -1 = keiner.</summary>
    Point: Integer;
  end;

  TAtlasWelcomeTrendsFrame = class(TAtlasWelcomeSectionFrame)
  public const
    Indent = 8;
    HeadHeight = 22;
    TileMinWidth = 150;
    TileHeight = 86;
    TileGap = 8;
    TilePadding = 8;
    SparkHeight = 36;
    InfoHeight = 24;
    DotRadius = 3;
    EmptyHeight = 40;
  private
    FSource: IAtlasTrendsSource;
    FBox: TAtlasWelcomeCanvas;
    FView: TAtlasTrendView;
    // Gewählter Punkt: Reihe und Build-Nummer, damit er ein Neuladen übersteht; 0 = keiner.
    FChosenSeries: TAtlasTrendSeries;
    FChosenBuild: Integer;
    FHintTile: Integer;
    FContentHeight: Integer;
    procedure SetSource(const AValue: IAtlasTrendsSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BodyResize(Sender: TObject);
    function AreaWidth: Integer;
    function Columns(AWidth: Integer): Integer;
    function HeightFor(AWidth: Integer): Integer;
    function InfoTop(AWidth: Integer): Integer;
    procedure DrawTile(ACanvas: TCanvas; AIndex: Integer; const ARect: TRect);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Rechteck der Kachel AIndex bei der Breite AWidth.</summary>
    function TileRect(AIndex, AWidth: Integer): TRect;
    /// <summary>Fläche der Linie in der Kachel ARect.</summary>
    function SparkRect(const ATileRect: TRect): TRect;
    /// <summary>Kachel und nächster Punkt an X, Y (Koordinaten der Zeichenfläche).</summary>
    function HitTest(X, Y: Integer): TAtlasTrendsHit;
    /// <summary>Klick wie mit der Maus: wählt den Punkt und zeigt darunter seinen Build (auch für Tests).</summary>
    procedure ClickAt(const AHit: TAtlasTrendsHit);
    /// <summary>Gewählter Punkt in den gezeigten Punkten; -1 = keiner.</summary>
    function ChosenPoint: Integer;
    /// <summary>Kachel des gewählten Punkts; -1 = keine.</summary>
    function ChosenTile: Integer;
    /// <summary>Kopfzeile, z. B. „Demo · letzte 30 Builds“; '' ohne Projekt.</summary>
    function HeadingText: string;
    /// <summary>Zeile unter den Kacheln: Hinweis zum Klick, Angaben zum gewählten Punkt oder ein leerer Zustand.
    /// </summary>
    function InfoText: string;
    /// <summary>„Projektverlauf“ in der Sprache der IDE.</summary>
    class function TitleText: string; static;
    class function SeriesTitle(ASeries: TAtlasTrendSeries): string; static;
    /// <summary>Wert mit Einheit, z. B. „3“, „12,4 s“ oder „18,5 Zeilen“.</summary>
    class function ValueWithUnit(ASeries: TAtlasTrendSeries; ATenths: Integer): string; static;
    /// <summary>Großer Wert der Kachel: letzter Wert mit Einheit bzw. „kein Wert“.</summary>
    class function ValueLine(const ATile: TAtlasTrendTile): string; static;
    /// <summary>„vorher 3“ mit dem letzten bekannten Wert davor; '' ohne.</summary>
    class function PreviousLine(const ATile: TAtlasTrendTile): string; static;
    /// <summary>„Build 3 von 30 · Nr. 27 · 14.10.2026 17:45 · main · 1a2b3c4 · Offene TODOs: 17“: Position in den
    /// gezeigten Punkten, laufende Nummer des Builds (nur wenn sie abweicht), Zeitpunkt, Branch, Commit, Wert.</summary>
    class function PointInfo(const AView: TAtlasTrendView; ATile, APoint: Integer): string; overload; static;
    /// <summary>Wie oben; ANumber = False lässt die laufende Nummer weg (zu wenig Platz).</summary>
    class function PointInfo(const AView: TAtlasTrendView; ATile, APoint: Integer; ANumber: Boolean): string;
      overload; static;
    /// <summary>Dezimaltrennzeichen der Oberflächensprache.</summary>
    class function DecimalChar: Char; static;
    /// <summary>UTC-Zeit als lokale Kurzform; '' für 0.</summary>
    class function LocalText(AUtc: TDateTime): string; static;
    property Source: IAtlasTrendsSource read FSource write SetSource;
    property View: TAtlasTrendView read FView;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  System.DateUtils,
  Vcl.Themes,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings;

type
  /// <summary>Zeichnet die Linie einer Kachel: Nulllinie, Stücke ohne Lücke, letzter und gewählter Punkt.</summary>
  TTrendSparkPainter = record
    Canvas: TCanvas;
    Tile: TAtlasTrendTile;
    Area: TRect;
    ZeroY: Integer;
    Radius: Integer;
    LineWidth: Integer;
    TextColor: TColor;
    LineColor: TColor;
    BackColor: TColor;
    /// <summary>Nulllinie, alle Stücke und den letzten Punkt; setzt ZeroY.</summary>
    procedure Draw(AZeroLineColor: TColor);
    procedure DrawPiece(const APoints: TArray<TPoint>);
    procedure DrawLast;
    /// <summary>Ring um den gewählten Punkt; nichts, wenn AChosen außerhalb liegt. Erst nach Draw.</summary>
    procedure DrawChosen(AChosen: Integer);
    function PointAt(AIndex: Integer): TPoint;
  end;

/// <summary>Mischfarbe: APercent Prozent von AFore auf ABack.</summary>
function Blend(AFore, ABack: TColor; APercent: Integer): TColor;
var
  Fore, Back: Integer;
  R, G, B: Integer;
begin
  Fore := ColorToRGB(AFore);
  Back := ColorToRGB(ABack);
  // TColor nach ColorToRGB: $00BBGGRR.
  R := ((Fore and $FF) * APercent + (Back and $FF) * (100 - APercent)) div 100;
  G := (((Fore shr 8) and $FF) * APercent + ((Back shr 8) and $FF) * (100 - APercent)) div 100;
  B := (((Fore shr 16) and $FF) * APercent + ((Back shr 16) and $FF) * (100 - APercent)) div 100;
  Result := TColor(R or (G shl 8) or (B shl 16));
end;

{ TTrendSparkPainter }

function TTrendSparkPainter.PointAt(AIndex: Integer): TPoint;
begin
  Result := Point(TAtlasWelcomeTrends.PointX(AIndex, Length(Tile.Values), Area.Left, Area.Width),
    TAtlasWelcomeTrends.PointY(Tile.Values[AIndex], Tile.Bottom, Tile.Top, Area.Top, Area.Height));
end;

procedure TTrendSparkPainter.Draw(AZeroLineColor: TColor);
var
  mCount, mIndex: Integer;
  mPoints: TArray<TPoint>;
begin
  mCount := Length(Tile.Values);
  ZeroY := TAtlasWelcomeTrends.PointY(0, Tile.Bottom, Tile.Top, Area.Top, Area.Height);
  Canvas.Pen.Color := AZeroLineColor;
  Canvas.Pen.Style := psDot;
  Canvas.MoveTo(Area.Left, ZeroY);
  Canvas.LineTo(Area.Right, ZeroY);
  Canvas.Pen.Style := psSolid;
  // Zusammenhängende Stücke ohne Lücke: Fläche bis zur Nulllinie, darüber die Linie.
  mIndex := 0;
  while mIndex < mCount do
  begin
    mPoints := nil;
    while (mIndex < mCount) and Tile.Has[mIndex] do
    begin
      mPoints := mPoints + [PointAt(mIndex)];
      Inc(mIndex);
    end;
    if mPoints <> nil then
    begin
      DrawPiece(mPoints);
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
  DrawLast;
end;

procedure TTrendSparkPainter.DrawPiece(const APoints: TArray<TPoint>);
var
  mRadius: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  if Length(APoints) = 1 then
  begin
    // Einzelner Wert zwischen Lücken: als kleiner Punkt.
    Canvas.Brush.Color := LineColor;
    Canvas.Pen.Color := LineColor;
    mRadius := Radius - 1;
    Canvas.Ellipse(APoints[0].X - mRadius, APoints[0].Y - mRadius, APoints[0].X + mRadius + 1,
      APoints[0].Y + mRadius + 1);
    Exit;
  end;
  Canvas.Brush.Color := Blend(LineColor, BackColor, 22);
  Canvas.Pen.Style := psClear;
  Canvas.Polygon(APoints + [Point(APoints[High(APoints)].X, ZeroY), Point(APoints[0].X, ZeroY)]);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := LineColor;
  Canvas.Pen.Width := LineWidth;
  Canvas.Polyline(APoints);
  Canvas.Pen.Width := 1;
end;

procedure TTrendSparkPainter.DrawLast;
var
  mCount, mX, mY: Integer;
begin
  // Letzter Punkt hervorgehoben.
  if not Tile.HasLast then
  begin
    Exit;
  end;
  mCount := Length(Tile.Values);
  mX := TAtlasWelcomeTrends.PointX(mCount - 1, mCount, Area.Left, Area.Width);
  mY := TAtlasWelcomeTrends.PointY(Tile.Last, Tile.Bottom, Tile.Top, Area.Top, Area.Height);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := LineColor;
  Canvas.Pen.Color := LineColor;
  Canvas.Ellipse(mX - Radius, mY - Radius, mX + Radius + 1, mY + Radius + 1);
end;

procedure TTrendSparkPainter.DrawChosen(AChosen: Integer);
var
  mX, mY: Integer;
begin
  if (AChosen < 0) or (AChosen >= Length(Tile.Values)) then
  begin
    Exit;
  end;
  mX := TAtlasWelcomeTrends.PointX(AChosen, Length(Tile.Values), Area.Left, Area.Width);
  mY := ZeroY;
  if Tile.Has[AChosen] then
  begin
    mY := PointAt(AChosen).Y;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := BackColor;
  Canvas.Pen.Color := TextColor;
  Canvas.Pen.Width := LineWidth;
  Canvas.Ellipse(mX - Radius - 1, mY - Radius - 1, mX + Radius + 2, mY + Radius + 2);
  Canvas.Pen.Width := 1;
end;

{ TAtlasWelcomeTrendsFrame }

constructor TAtlasWelcomeTrendsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHintTile := -1;
  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  Body.OnResize := BodyResize;
end;

class function TAtlasWelcomeTrendsFrame.TitleText: string;
begin
  Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsTitle);
end;

procedure TAtlasWelcomeTrendsFrame.SetSource(const AValue: IAtlasTrendsSource);
begin
  FSource := AValue;
  UpdateContent;
end;

procedure TAtlasWelcomeTrendsFrame.UpdateContent;
var
  OldProject: string;
  OldHeight: Integer;
begin
  OldProject := FView.Project;
  OldHeight := HeightFor(ClientWidth);
  FView := Default(TAtlasTrendView);
  if FSource <> nil then
  begin
    FView := FSource.View;
  end;
  // Anderes Projekt: der gewählte Punkt gehört zum alten.
  if not SameText(OldProject, FView.Project) then
  begin
    FChosenBuild := 0;
  end;
  FHintTile := -1;
  FBox.Invalidate;
  inherited;
  if OldHeight <> HeightFor(ClientWidth) then
  begin
    HeightChanged;
  end;
end;

procedure TAtlasWelcomeTrendsFrame.BodyResize(Sender: TObject);
var
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  FContentHeight := HeightFor(ClientWidth);
  // Andere Anzahl Reihen von Kacheln: Der Frame „Atlas“ ordnet die Spalten neu.
  if OldHeight <> FContentHeight then
  begin
    HeightChanged;
  end;
end;

function TAtlasWelcomeTrendsFrame.AreaWidth: Integer;
begin
  // Breite des Frames statt der Zeichenfläche: Die richtet sich erst später nach dem Frame aus; so passen
  // Zeichnen, Treffertest und Höhe immer zusammen.
  Result := ClientWidth;
end;

function TAtlasWelcomeTrendsFrame.Columns(AWidth: Integer): Integer;
begin
  Result := (AWidth - 2 * ScaleValue(Indent) + ScaleValue(TileGap)) div (ScaleValue(TileMinWidth) +
    ScaleValue(TileGap));
  Result := Max(1, Min(Result, Integer(Length(FView.Tiles))));
end;

function TAtlasWelcomeTrendsFrame.InfoTop(AWidth: Integer): Integer;
var
  Rows: Integer;
begin
  Result := ScaleValue(HeadHeight);
  if (Length(FView.Points) = 0) or (Length(FView.Tiles) = 0) then
  begin
    Exit;
  end;
  Rows := (Length(FView.Tiles) + Columns(AWidth) - 1) div Columns(AWidth);
  Inc(Result, Rows * (ScaleValue(TileHeight) + ScaleValue(TileGap)));
end;

function TAtlasWelcomeTrendsFrame.HeightFor(AWidth: Integer): Integer;
begin
  if FView.Project = '' then
  begin
    Exit(ScaleValue(EmptyHeight));
  end;
  Result := InfoTop(AWidth) + ScaleValue(InfoHeight);
end;

function TAtlasWelcomeTrendsFrame.BodyHeight: Integer;
begin
  // Für die aktuelle Breite: Der Frame „Atlas“ setzt erst die Breite, dann die Höhe.
  FContentHeight := HeightFor(ClientWidth);
  Result := FContentHeight;
end;

function TAtlasWelcomeTrendsFrame.TileRect(AIndex, AWidth: Integer): TRect;
var
  Count, Column, Row, mWidth, mLeft, mTop: Integer;
begin
  Count := Columns(AWidth);
  Column := AIndex mod Count;
  Row := AIndex div Count;
  mWidth := (AWidth - 2 * ScaleValue(Indent) - (Count - 1) * ScaleValue(TileGap)) div Count;
  mLeft := ScaleValue(Indent) + Column * (mWidth + ScaleValue(TileGap));
  mTop := ScaleValue(HeadHeight) + Row * (ScaleValue(TileHeight) + ScaleValue(TileGap));
  Result := Rect(mLeft, mTop, mLeft + mWidth, mTop + ScaleValue(TileHeight));
end;

function TAtlasWelcomeTrendsFrame.SparkRect(const ATileRect: TRect): TRect;
var
  Padding: Integer;
begin
  // Platz für den Punkt am Rand: Der letzte steht ganz rechts.
  Padding := ScaleValue(TilePadding) + ScaleValue(DotRadius);
  Result := Rect(ATileRect.Left + Padding, ATileRect.Bottom - ScaleValue(TilePadding) - ScaleValue(SparkHeight),
    ATileRect.Right - Padding, ATileRect.Bottom - ScaleValue(TilePadding));
end;

class function TAtlasWelcomeTrendsFrame.SeriesTitle(ASeries: TAtlasTrendSeries): string;
begin
  case ASeries of
    TAtlasTrendSeries.Warnings:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsWarnings);
    TAtlasTrendSeries.RuleHits:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsRuleHits);
    TAtlasTrendSeries.Todos:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsTodos);
    TAtlasTrendSeries.Duration:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsDuration);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsMethodLength);
  end;
end;

class function TAtlasWelcomeTrendsFrame.DecimalChar: Char;
begin
  if TAtlasStrings.Language = TAtlasLanguage.German then
  begin
    Result := ',';
  end
  else
  begin
    Result := '.';
  end;
end;

class function TAtlasWelcomeTrendsFrame.ValueWithUnit(ASeries: TAtlasTrendSeries; ATenths: Integer): string;
begin
  Result := TAtlasWelcomeTrends.ValueText(ASeries, ATenths, DecimalChar);
  case ASeries of
    TAtlasTrendSeries.Duration:
      Result := Result + ' ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsSeconds);
    TAtlasTrendSeries.MethodLength:
      Result := Result + ' ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsLines);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasWelcomeTrendsFrame.ValueLine(const ATile: TAtlasTrendTile): string;
begin
  if ATile.HasLast then
  begin
    Result := ValueWithUnit(ATile.Series, ATile.Last);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoValue);
  end;
end;

class function TAtlasWelcomeTrendsFrame.PreviousLine(const ATile: TAtlasTrendTile): string;
var
  Value: Integer;
begin
  Result := '';
  if ATile.Previous(Value) then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeTrendsPrevious, [ValueWithUnit(ATile.Series, Value)]);
  end;
end;

class function TAtlasWelcomeTrendsFrame.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc <= 0 then
  begin
    Exit;
  end;
  Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
end;

class function TAtlasWelcomeTrendsFrame.PointInfo(const AView: TAtlasTrendView; ATile, APoint: Integer): string;
begin
  Result := PointInfo(AView, ATile, APoint, True);
end;

class function TAtlasWelcomeTrendsFrame.PointInfo(const AView: TAtlasTrendView; ATile, APoint: Integer;
  ANumber: Boolean): string;
var
  Point: TAtlasTrendPoint;
  Tile: TAtlasTrendTile;
  Value: string;
begin
  Result := '';
  if (ATile < 0) or (ATile > High(AView.Tiles)) or (APoint < 0) or (APoint > High(AView.Points)) then
  begin
    Exit;
  end;
  Point := AView.Points[APoint];
  Tile := AView.Tiles[ATile];
  // Wie im Mockup „Build i von N“ in den gezeigten Punkten; die laufende Nummer zählt alle Builds.
  Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeTrendsBuild, [APoint + 1, Length(AView.Points)]);
  if ANumber and (Point.Build > 0) and (Point.Build <> APoint + 1) then
  begin
    Result := Result + ' · ' + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeTrendsBuildNumber, [Point.Build]);
  end;
  if Point.At > 0 then
  begin
    Result := Result + ' · ' + LocalText(Point.At);
  end;
  if Point.Branch <> '' then
  begin
    Result := Result + ' · ' + Point.Branch;
  end;
  if Point.Commit <> '' then
  begin
    Result := Result + ' · ' + TAtlasWelcomeTrends.ShortCommit(Point.Commit);
  end;
  if Tile.Has[APoint] then
  begin
    Value := ValueWithUnit(Tile.Series, Tile.Values[APoint]);
  end
  else
  begin
    Value := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoValue);
  end;
  Result := Result + ' · ' + SeriesTitle(Tile.Series) + ': ' + Value;
end;

function TAtlasWelcomeTrendsFrame.ChosenPoint: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if FChosenBuild <= 0 then
  begin
    Exit;
  end;
  for Index := 0 to High(FView.Points) do
  begin
    if FView.Points[Index].Build = FChosenBuild then
    begin
      Exit(Index);
    end;
  end;
end;

function TAtlasWelcomeTrendsFrame.ChosenTile: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if ChosenPoint < 0 then
  begin
    Exit;
  end;
  for Index := 0 to High(FView.Tiles) do
  begin
    if FView.Tiles[Index].Series = FChosenSeries then
    begin
      Exit(Index);
    end;
  end;
end;

function TAtlasWelcomeTrendsFrame.HeadingText: string;
begin
  Result := '';
  if FView.Project <> '' then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeTrendsHeading, [FView.Name, FView.Limit]);
  end;
end;

function TAtlasWelcomeTrendsFrame.InfoText: string;
begin
  if FView.Project = '' then
  begin
    Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoProject));
  end;
  if Length(FView.Points) = 0 then
  begin
    Exit(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeTrendsNoPoints, [FView.Name]));
  end;
  if Length(FView.Tiles) = 0 then
  begin
    Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoSeries));
  end;
  if ChosenTile >= 0 then
  begin
    Exit(PointInfo(FView, ChosenTile, ChosenPoint));
  end;
  Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsClickHint);
end;

function TAtlasWelcomeTrendsFrame.HitTest(X, Y: Integer): TAtlasTrendsHit;
var
  Index, mWidth: Integer;
  Area: TRect;
begin
  Result.Tile := -1;
  Result.Point := -1;
  if Length(FView.Points) = 0 then
  begin
    Exit;
  end;
  mWidth := AreaWidth;
  for Index := 0 to High(FView.Tiles) do
  begin
    if TileRect(Index, mWidth).Contains(Point(X, Y)) then
    begin
      Result.Tile := Index;
      Area := SparkRect(TileRect(Index, mWidth));
      // Ein paar Punkte Spielraum um die Linie: Sie ist dünn.
      if (Y >= Area.Top - ScaleValue(TilePadding)) and (Y <= Area.Bottom + ScaleValue(TilePadding)) then
      begin
        Result.Point := TAtlasWelcomeTrends.NearestPoint(X, Length(FView.Points), Area.Left, Area.Width);
      end;
      Exit;
    end;
  end;
end;

procedure TAtlasWelcomeTrendsFrame.ClickAt(const AHit: TAtlasTrendsHit);
begin
  // Nur Anzeige im Bereich: keine Aktion der IDE, darum direkt und ohne Nachrichtenschleife.
  if (AHit.Tile < 0) or (AHit.Tile > High(FView.Tiles)) or (AHit.Point < 0) or (AHit.Point > High(FView.Points)) then
  begin
    Exit;
  end;
  FChosenSeries := FView.Tiles[AHit.Tile].Series;
  FChosenBuild := FView.Points[AHit.Point].Build;
  FBox.Invalidate;
end;

procedure TAtlasWelcomeTrendsFrame.DrawTile(ACanvas: TCanvas; AIndex: Integer; const ARect: TRect);
var
  mTile: TAtlasTrendTile;
  mSpark: TTrendSparkPainter;
  mMutedColor: TColor;
  mText: string;
  mX, mY, mValueHeight: Integer;
begin
  mTile := FView.Tiles[AIndex];
  mMutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  mSpark.Canvas := ACanvas;
  mSpark.Tile := mTile;
  mSpark.TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  mSpark.LineColor := StyleServices(Self).GetSystemColor(clHighlight);
  mSpark.BackColor := StyleServices(Self).GetSystemColor(clWindow);
  // Rahmen der Kachel.
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := Blend(mMutedColor, mSpark.BackColor, 35);
  ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, ScaleValue(8), ScaleValue(8));
  // Bezeichnung klein und in Großbuchstaben.
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size - 1;
  ACanvas.Font.Color := mMutedColor;
  ACanvas.TextRect(Rect(ARect.Left + ScaleValue(TilePadding), ARect.Top + ScaleValue(5),
    ARect.Right - ScaleValue(TilePadding), ARect.Top + ScaleValue(5) + ACanvas.TextHeight('Ag')),
    ARect.Left + ScaleValue(TilePadding), ARect.Top + ScaleValue(5), AnsiUpperCase(SeriesTitle(mTile.Series)));
  // Letzter Wert groß, Vorwert klein daneben.
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size + 3;
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Color := mSpark.TextColor;
  mText := ValueLine(mTile);
  mX := ARect.Left + ScaleValue(TilePadding);
  mY := ARect.Top + ScaleValue(20);
  ACanvas.TextOut(mX, mY, mText);
  Inc(mX, ACanvas.TextWidth(mText) + ScaleValue(6));
  mValueHeight := ACanvas.TextHeight(mText);
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size - 1;
  ACanvas.Font.Color := mMutedColor;
  ACanvas.TextOut(mX, mY + mValueHeight - ACanvas.TextHeight('Ag') - ScaleValue(1), PreviousLine(mTile));
  // Linie: eine Skala je Kachel, Nulllinie immer sichtbar.
  mSpark.Area := SparkRect(ARect);
  mSpark.Radius := ScaleValue(DotRadius);
  mSpark.LineWidth := ScaleValue(2);
  mSpark.Draw(Blend(mMutedColor, mSpark.BackColor, 50));
  // Gewählter Punkt als Ring; in einer Lücke auf der Nulllinie.
  if mTile.Series = FChosenSeries then
  begin
    mSpark.DrawChosen(ChosenPoint);
  end;
  ACanvas.Brush.Style := bsClear;
end;

procedure TAtlasWelcomeTrendsFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Index, mWidth: Integer;
  MutedColor: TColor;
  Info: string;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  mWidth := AreaWidth;
  if FView.Project = '' then
  begin
    Canvas.Font.Color := MutedColor;
    Canvas.TextOut(ScaleValue(Indent), ScaleValue(Indent), InfoText);
    Exit;
  end;
  Canvas.Font.Color := MutedColor;
  Canvas.TextOut(ScaleValue(Indent), ScaleValue(3), HeadingText);
  if Length(FView.Points) > 0 then
  begin
    for Index := 0 to High(FView.Tiles) do
    begin
      DrawTile(Canvas, Index, TileRect(Index, mWidth));
    end;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := MutedColor;
  Info := InfoText;
  // Zu schmal für alles: die laufende Nummer weglassen.
  if (ChosenTile >= 0) and (Canvas.TextWidth(Info) > mWidth - 2 * ScaleValue(Indent)) then
  begin
    Info := PointInfo(FView, ChosenTile, ChosenPoint, False);
  end;
  Canvas.TextOut(ScaleValue(Indent), InfoTop(mWidth) + ScaleValue(3), Info);
end;

procedure TAtlasWelcomeTrendsFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasTrendsHit;
begin
  Hit := HitTest(X, Y);
  if Hit.Point >= 0 then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  if Hit.Tile = FHintTile then
  begin
    Exit;
  end;
  FHintTile := Hit.Tile;
  if Hit.Tile >= 0 then
  begin
    FBox.Hint := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeTrendsTileHint,
      [SeriesTitle(FView.Tiles[Hit.Tile].Series)]);
  end
  else
  begin
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeTrendsFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
  begin
    ClickAt(HitTest(X, Y));
  end;
end;

end.
