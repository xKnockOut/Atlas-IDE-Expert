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
    FBox: TPaintBox;
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
    /// <summary>„Build 12 · 14.10.2026 17:45 · main · 1a2b3c4 · Offene TODOs: 17“.</summary>
    class function PointInfo(const AView: TAtlasTrendView; ATile, APoint: Integer): string; static;
    /// <summary>Dezimaltrennzeichen der Oberflächensprache.</summary>
    class function DecimalChar: Char; static;
    /// <summary>UTC-Zeit als lokale Kurzform; '' für 0.</summary>
    class function LocalText(AUtc: TDateTime): string; static;
    property Source: IAtlasTrendsSource read FSource write SetSource;
    property View: TAtlasTrendView read FView;
    property PaintBox: TPaintBox read FBox;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  System.DateUtils,
  Vcl.Themes,
  Atlas.UI.Strings;

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

{ TAtlasWelcomeTrendsFrame }

constructor TAtlasWelcomeTrendsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHintTile := -1;
  FBox := TPaintBox.Create(Self);
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
  Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsTitle);
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
    FView := FSource.View;
  // Anderes Projekt: der gewählte Punkt gehört zum alten.
  if not SameText(OldProject, FView.Project) then
    FChosenBuild := 0;
  FHintTile := -1;
  FBox.Invalidate;
  inherited;
  if OldHeight <> HeightFor(ClientWidth) then
    HeightChanged;
end;

procedure TAtlasWelcomeTrendsFrame.BodyResize(Sender: TObject);
var
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  FContentHeight := HeightFor(ClientWidth);
  // Andere Anzahl Reihen von Kacheln: Der Frame „Atlas“ ordnet die Spalten neu.
  if OldHeight <> FContentHeight then
    HeightChanged;
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
    Exit;
  Rows := (Length(FView.Tiles) + Columns(AWidth) - 1) div Columns(AWidth);
  Inc(Result, Rows * (ScaleValue(TileHeight) + ScaleValue(TileGap)));
end;

function TAtlasWelcomeTrendsFrame.HeightFor(AWidth: Integer): Integer;
begin
  if FView.Project = '' then
    Exit(ScaleValue(EmptyHeight));
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
  Count, Column, Row, Width, Left, Top: Integer;
begin
  Count := Columns(AWidth);
  Column := AIndex mod Count;
  Row := AIndex div Count;
  Width := (AWidth - 2 * ScaleValue(Indent) - (Count - 1) * ScaleValue(TileGap)) div Count;
  Left := ScaleValue(Indent) + Column * (Width + ScaleValue(TileGap));
  Top := ScaleValue(HeadHeight) + Row * (ScaleValue(TileHeight) + ScaleValue(TileGap));
  Result := Rect(Left, Top, Left + Width, Top + ScaleValue(TileHeight));
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
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsWarnings);
    TAtlasTrendSeries.RuleHits:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsRuleHits);
    TAtlasTrendSeries.Todos:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsTodos);
    TAtlasTrendSeries.Duration:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsDuration);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsMethodLength);
  end;
end;

class function TAtlasWelcomeTrendsFrame.DecimalChar: Char;
begin
  if TAtlasStrings.Language = TAtlasLanguage.German then
    Result := ','
  else
    Result := '.';
end;

class function TAtlasWelcomeTrendsFrame.ValueWithUnit(ASeries: TAtlasTrendSeries; ATenths: Integer): string;
begin
  Result := TAtlasWelcomeTrends.ValueText(ASeries, ATenths, DecimalChar);
  case ASeries of
    TAtlasTrendSeries.Duration:
      Result := Result + ' ' + TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsSeconds);
    TAtlasTrendSeries.MethodLength:
      Result := Result + ' ' + TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsLines);
  end;
end;

class function TAtlasWelcomeTrendsFrame.ValueLine(const ATile: TAtlasTrendTile): string;
begin
  if ATile.HasLast then
    Result := ValueWithUnit(ATile.Series, ATile.Last)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoValue);
end;

class function TAtlasWelcomeTrendsFrame.PreviousLine(const ATile: TAtlasTrendTile): string;
var
  Value: Integer;
begin
  Result := '';
  if ATile.Previous(Value) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTrendsPrevious, [ValueWithUnit(ATile.Series, Value)]);
end;

class function TAtlasWelcomeTrendsFrame.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc <= 0 then
    Exit;
  Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
end;

class function TAtlasWelcomeTrendsFrame.PointInfo(const AView: TAtlasTrendView; ATile, APoint: Integer): string;
var
  Point: TAtlasTrendPoint;
  Tile: TAtlasTrendTile;
  Value: string;
begin
  Result := '';
  if (ATile < 0) or (ATile > High(AView.Tiles)) or (APoint < 0) or (APoint > High(AView.Points)) then
    Exit;
  Point := AView.Points[APoint];
  Tile := AView.Tiles[ATile];
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTrendsBuild, [Point.Build]);
  if Point.At > 0 then
    Result := Result + ' · ' + LocalText(Point.At);
  if Point.Branch <> '' then
    Result := Result + ' · ' + Point.Branch;
  if Point.Commit <> '' then
    Result := Result + ' · ' + TAtlasWelcomeTrends.ShortCommit(Point.Commit);
  if Tile.Has[APoint] then
    Value := ValueWithUnit(Tile.Series, Tile.Values[APoint])
  else
    Value := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoValue);
  Result := Result + ' · ' + SeriesTitle(Tile.Series) + ': ' + Value;
end;

function TAtlasWelcomeTrendsFrame.ChosenPoint: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if FChosenBuild <= 0 then
    Exit;
  for Index := 0 to High(FView.Points) do
    if FView.Points[Index].Build = FChosenBuild then
      Exit(Index);
end;

function TAtlasWelcomeTrendsFrame.ChosenTile: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if ChosenPoint < 0 then
    Exit;
  for Index := 0 to High(FView.Tiles) do
    if FView.Tiles[Index].Series = FChosenSeries then
      Exit(Index);
end;

function TAtlasWelcomeTrendsFrame.HeadingText: string;
begin
  Result := '';
  if FView.Project <> '' then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTrendsHeading, [FView.Name, FView.Limit]);
end;

function TAtlasWelcomeTrendsFrame.InfoText: string;
begin
  if FView.Project = '' then
    Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoProject));
  if Length(FView.Points) = 0 then
    Exit(TAtlasStrings.Fmt(TAtlasTextId.WelcomeTrendsNoPoints, [FView.Name]));
  if Length(FView.Tiles) = 0 then
    Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoSeries));
  if ChosenTile >= 0 then
    Exit(PointInfo(FView, ChosenTile, ChosenPoint));
  Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsClickHint);
end;

function TAtlasWelcomeTrendsFrame.HitTest(X, Y: Integer): TAtlasTrendsHit;
var
  Index, Width: Integer;
  Area: TRect;
begin
  Result.Tile := -1;
  Result.Point := -1;
  if Length(FView.Points) = 0 then
    Exit;
  Width := AreaWidth;
  for Index := 0 to High(FView.Tiles) do
    if TileRect(Index, Width).Contains(Point(X, Y)) then
    begin
      Result.Tile := Index;
      Area := SparkRect(TileRect(Index, Width));
      // Ein paar Punkte Spielraum um die Linie: Sie ist dünn.
      if (Y >= Area.Top - ScaleValue(TilePadding)) and (Y <= Area.Bottom + ScaleValue(TilePadding)) then
        Result.Point := TAtlasWelcomeTrends.NearestPoint(X, Length(FView.Points), Area.Left, Area.Width);
      Exit;
    end;
end;

procedure TAtlasWelcomeTrendsFrame.ClickAt(const AHit: TAtlasTrendsHit);
begin
  // Nur Anzeige im Bereich: keine Aktion der IDE, darum direkt und ohne Nachrichtenschleife.
  if (AHit.Tile < 0) or (AHit.Tile > High(FView.Tiles)) or (AHit.Point < 0) or (AHit.Point > High(FView.Points)) then
    Exit;
  FChosenSeries := FView.Tiles[AHit.Tile].Series;
  FChosenBuild := FView.Points[AHit.Point].Build;
  FBox.Invalidate;
end;

procedure TAtlasWelcomeTrendsFrame.DrawTile(ACanvas: TCanvas; AIndex: Integer; const ARect: TRect);
var
  Tile: TAtlasTrendTile;
  Area: TRect;
  Count, Index, ZeroY, X, Y, Radius, ValueHeight, Chosen: Integer;
  Points: TArray<TPoint>;
  TextColor, MutedColor, LineColor, BackColor: TColor;
  Text: string;
begin
  Tile := FView.Tiles[AIndex];
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  LineColor := StyleServices(Self).GetSystemColor(clHighlight);
  BackColor := StyleServices(Self).GetSystemColor(clWindow);
  // Rahmen der Kachel.
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := Blend(MutedColor, BackColor, 35);
  ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, ScaleValue(8), ScaleValue(8));
  // Bezeichnung klein und in Großbuchstaben.
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size - 1;
  ACanvas.Font.Color := MutedColor;
  ACanvas.TextRect(Rect(ARect.Left + ScaleValue(TilePadding), ARect.Top + ScaleValue(5),
    ARect.Right - ScaleValue(TilePadding), ARect.Top + ScaleValue(5) + ACanvas.TextHeight('Ag')),
    ARect.Left + ScaleValue(TilePadding), ARect.Top + ScaleValue(5), AnsiUpperCase(SeriesTitle(Tile.Series)));
  // Letzter Wert groß, Vorwert klein daneben.
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size + 3;
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Color := TextColor;
  Text := ValueLine(Tile);
  X := ARect.Left + ScaleValue(TilePadding);
  Y := ARect.Top + ScaleValue(20);
  ACanvas.TextOut(X, Y, Text);
  Inc(X, ACanvas.TextWidth(Text) + ScaleValue(6));
  ValueHeight := ACanvas.TextHeight(Text);
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size - 1;
  ACanvas.Font.Color := MutedColor;
  ACanvas.TextOut(X, Y + ValueHeight - ACanvas.TextHeight('Ag') - ScaleValue(1), PreviousLine(Tile));
  // Linie: eine Skala je Kachel, Nulllinie immer sichtbar.
  Area := SparkRect(ARect);
  Count := Length(Tile.Values);
  ZeroY := TAtlasWelcomeTrends.PointY(0, Tile.Bottom, Tile.Top, Area.Top, Area.Height);
  ACanvas.Pen.Color := Blend(MutedColor, BackColor, 50);
  ACanvas.Pen.Style := psDot;
  ACanvas.MoveTo(Area.Left, ZeroY);
  ACanvas.LineTo(Area.Right, ZeroY);
  ACanvas.Pen.Style := psSolid;
  // Zusammenhängende Stücke ohne Lücke: Fläche bis zur Nulllinie, darüber die Linie.
  Index := 0;
  while Index < Count do
  begin
    if not Tile.Has[Index] then
    begin
      Inc(Index);
      Continue;
    end;
    Points := nil;
    while (Index < Count) and Tile.Has[Index] do
    begin
      Points := Points + [Point(TAtlasWelcomeTrends.PointX(Index, Count, Area.Left, Area.Width),
        TAtlasWelcomeTrends.PointY(Tile.Values[Index], Tile.Bottom, Tile.Top, Area.Top, Area.Height))];
      Inc(Index);
    end;
    if Length(Points) > 1 then
    begin
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := Blend(LineColor, BackColor, 22);
      ACanvas.Pen.Style := psClear;
      ACanvas.Polygon(Points + [Point(Points[High(Points)].X, ZeroY), Point(Points[0].X, ZeroY)]);
      ACanvas.Pen.Style := psSolid;
      ACanvas.Pen.Color := LineColor;
      ACanvas.Pen.Width := ScaleValue(2);
      ACanvas.Polyline(Points);
      ACanvas.Pen.Width := 1;
    end
    else
    begin
      // Einzelner Wert zwischen Lücken: als kleiner Punkt.
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := LineColor;
      ACanvas.Pen.Color := LineColor;
      Radius := ScaleValue(DotRadius) - 1;
      ACanvas.Ellipse(Points[0].X - Radius, Points[0].Y - Radius, Points[0].X + Radius + 1,
        Points[0].Y + Radius + 1);
    end;
  end;
  Radius := ScaleValue(DotRadius);
  // Letzter Punkt hervorgehoben.
  if Tile.HasLast then
  begin
    X := TAtlasWelcomeTrends.PointX(Count - 1, Count, Area.Left, Area.Width);
    Y := TAtlasWelcomeTrends.PointY(Tile.Last, Tile.Bottom, Tile.Top, Area.Top, Area.Height);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := LineColor;
    ACanvas.Pen.Color := LineColor;
    ACanvas.Ellipse(X - Radius, Y - Radius, X + Radius + 1, Y + Radius + 1);
  end;
  // Gewählter Punkt als Ring; in einer Lücke auf der Nulllinie.
  Chosen := ChosenPoint;
  if (Chosen >= 0) and (Chosen < Count) and (Tile.Series = FChosenSeries) then
  begin
    X := TAtlasWelcomeTrends.PointX(Chosen, Count, Area.Left, Area.Width);
    Y := ZeroY;
    if Tile.Has[Chosen] then
      Y := TAtlasWelcomeTrends.PointY(Tile.Values[Chosen], Tile.Bottom, Tile.Top, Area.Top, Area.Height);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := BackColor;
    ACanvas.Pen.Color := TextColor;
    ACanvas.Pen.Width := ScaleValue(2);
    ACanvas.Ellipse(X - Radius - 1, Y - Radius - 1, X + Radius + 2, Y + Radius + 2);
    ACanvas.Pen.Width := 1;
  end;
  ACanvas.Brush.Style := bsClear;
end;

procedure TAtlasWelcomeTrendsFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Index, Width: Integer;
  MutedColor: TColor;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  Width := AreaWidth;
  if FView.Project = '' then
  begin
    Canvas.Font.Color := MutedColor;
    Canvas.TextOut(ScaleValue(Indent), ScaleValue(Indent), InfoText);
    Exit;
  end;
  Canvas.Font.Color := MutedColor;
  Canvas.TextOut(ScaleValue(Indent), ScaleValue(3), HeadingText);
  if Length(FView.Points) > 0 then
    for Index := 0 to High(FView.Tiles) do
      DrawTile(Canvas, Index, TileRect(Index, Width));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := MutedColor;
  Canvas.TextOut(ScaleValue(Indent), InfoTop(Width) + ScaleValue(3), InfoText);
end;

procedure TAtlasWelcomeTrendsFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasTrendsHit;
begin
  Hit := HitTest(X, Y);
  if Hit.Point >= 0 then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  if Hit.Tile = FHintTile then
    Exit;
  FHintTile := Hit.Tile;
  if Hit.Tile >= 0 then
    FBox.Hint := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTrendsTileHint, [SeriesTitle(FView.Tiles[Hit.Tile].Series)])
  else
    FBox.Hint := '';
  Application.CancelHint;
end;

procedure TAtlasWelcomeTrendsFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
    ClickAt(HitTest(X, Y));
end;

end.
