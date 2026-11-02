unit Atlas.Core.Welcome.Trends;

// Bereich „Projektverlauf“ der Willkommensseite (#758), Teil ohne VCL und Open
// Tools API: welches Projekt, welche Reihen, Kacheln mit letztem Wert, Vorwert
// und Skala sowie die Lage der Punkte für Zeichnen und Treffertest.
// - Projekt: das im Bereich „Projekte“ (#592) gewählte; ohne Auswahl (oder
//   wenn es nicht mehr in der Liste steht) das oberste.
// - Reihen: welcomePage.trends.series (Liste der Namen aus
//   TAtlasProjectSummaries.TrendKeys, Vorgabe alle fünf), immer in der
//   Reihenfolge der Kacheln; unbekannte Namen fallen weg.
// - Punkte: die gespeicherten Messpunkte, höchstens welcomePage.trends.points
//   (die neuesten). Werte kommen unverändert aus der Datei; hier wird nur die
//   Skala bestimmt.
// - Kachel: letzter Wert (Lücke, wenn der letzte Build ihn nicht kannte),
//   Vorwert = letzter bekannter Wert davor, Skala gleich für die ganze Linie
//   und immer mit der Nulllinie.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary;

type
  TAtlasTrendSeriesList = TArray<TAtlasTrendSeries>;

  TAtlasTrendTile = record
    Series: TAtlasTrendSeries;
    /// <summary>Wert je Punkt in Zehnteln; nur mit Has.</summary>
    Values: TArray<Integer>;
    Has: TArray<Boolean>;
    /// <summary>Skala in Zehnteln: Bottom ≤ 0 ≤ Top, Bottom &lt; Top.</summary>
    Bottom: Integer;
    Top: Integer;
    /// <summary>Der letzte Punkt hat einen Wert.</summary>
    function HasLast: Boolean;
    function Last: Integer;
    /// <summary>Letzter bekannter Wert vor dem letzten Punkt; False ohne.</summary>
    function Previous(out AValue: Integer): Boolean;
  end;

  TAtlasTrendView = record
    /// <summary>Projektdatei; '' ohne Projekt.</summary>
    Project: string;
    /// <summary>Gezeigte Punkte, älteste zuerst.</summary>
    Points: TArray<TAtlasTrendPoint>;
    /// <summary>Eine Kachel je gewählter Reihe.</summary>
    Tiles: TArray<TAtlasTrendTile>;
    /// <summary>Höchstens so viele Builds (welcomePage.trends.points).</summary>
    Limit: Integer;
    function Name: string;
  end;

  TAtlasWelcomeTrends = class
  public const
    /// <summary>Vorgabe für welcomePage.trends.series: alle Reihen.</summary>
    DefaultSeries = 'warnings,ruleHits,todos,duration,methodLength';
  public
    class function SeriesKey(ASeries: TAtlasTrendSeries): string; static;
    /// <summary>Reihen aus einer Liste von Namen (Komma, Semikolon oder Leerzeichen; Groß-/Kleinschreibung egal),
    /// in der Reihenfolge der Kacheln, jede einmal; unbekannte fallen weg.</summary>
    class function ParseSeries(const AText: string): TAtlasTrendSeriesList; static;
    /// <summary>Umkehrung von ParseSeries: "warnings,todos".</summary>
    class function SeriesText(const ASeries: TAtlasTrendSeriesList): string; static;
    /// <summary>Normierte Liste: bekannte Namen in Kachel-Reihenfolge, durch Komma getrennt.</summary>
    class function NormalizeSeries(const AText: string): string; static;
    /// <summary>Projekt für den Verlauf: ASelected, wenn es in AProjects steht, sonst das oberste; '' ohne.</summary>
    class function Choose(const AProjects: TArray<string>; const ASelected: string): string; static;
    /// <summary>Ansicht für die Zusammenfassung ASummary mit den Reihen ASeries und höchstens ALimit Punkten.
    /// </summary>
    class function View(const ASummary: TAtlasProjectSummary; const ASeries: TAtlasTrendSeriesList;
      ALimit: Integer): TAtlasTrendView; static;
    /// <summary>Skala über die bekannten Werte; immer mit 0, nie leer.</summary>
    class procedure Scale(const AValues: TArray<Integer>; const AHas: TArray<Boolean>; out ALow,
      AHigh: Integer); static;
    /// <summary>Wert als Text: ganze Zahl bzw. mit einer Nachkommastelle (ADecimal als Trennzeichen).</summary>
    class function ValueText(ASeries: TAtlasTrendSeries; ATenths: Integer; ADecimal: Char): string; static;
    /// <summary>Kurzform eines Commits: 40 bzw. 64 Hexziffern (Git) auf 7 gekürzt, sonst unverändert.</summary>
    class function ShortCommit(const ARevision: string): string; static;
    /// <summary>X-Lage von Punkt AIndex bei ACount Punkten in der Breite AWidth ab ALeft; ein Punkt steht rechts.
    /// </summary>
    class function PointX(AIndex, ACount, ALeft, AWidth: Integer): Integer; static;
    /// <summary>Y-Lage von AValue in der Höhe AHeight ab ATop (oben = AHigh).</summary>
    class function PointY(AValue, ALow, AHigh, ATop, AHeight: Integer): Integer; static;
    /// <summary>Nächster Punkt zur X-Lage AX; -1 ohne Punkte.</summary>
    class function NearestPoint(AX, ACount, ALeft, AWidth: Integer): Integer; static;
  end;

implementation

uses
  System.Math;

/// <summary>Round(AValue * ANumerator / ADenominator) ohne Überlauf; ADenominator &gt; 0.</summary>
function Scaled(AValue, ANumerator, ADenominator: Integer): Integer;
var
  Product: Int64;
begin
  Product := Int64(AValue) * ANumerator;
  if Product >= 0 then
    Result := Integer((Product + ADenominator div 2) div ADenominator)
  else
    Result := -Integer((-Product + ADenominator div 2) div ADenominator);
end;

{ TAtlasTrendTile }

function TAtlasTrendTile.HasLast: Boolean;
begin
  Result := (Length(Has) > 0) and Has[System.High(Has)];
end;

function TAtlasTrendTile.Last: Integer;
begin
  Result := 0;
  if HasLast then
    Result := Values[System.High(Values)];
end;

function TAtlasTrendTile.Previous(out AValue: Integer): Boolean;
var
  Index: Integer;
begin
  AValue := 0;
  for Index := System.High(Has) - 1 downto 0 do
    if Has[Index] then
    begin
      AValue := Values[Index];
      Exit(True);
    end;
  Result := False;
end;

{ TAtlasTrendView }

function TAtlasTrendView.Name: string;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Result := Summary.Name;
end;

{ TAtlasWelcomeTrends }

class function TAtlasWelcomeTrends.SeriesKey(ASeries: TAtlasTrendSeries): string;
begin
  Result := TAtlasProjectSummaries.TrendKeys[ASeries];
end;

class function TAtlasWelcomeTrends.ParseSeries(const AText: string): TAtlasTrendSeriesList;
var
  Parts: TArray<string>;
  Part: string;
  Series: TAtlasTrendSeries;
  Wanted: TAtlasTrendFlags;
begin
  Result := nil;
  for Series := System.Low(TAtlasTrendSeries) to System.High(TAtlasTrendSeries) do
    Wanted[Series] := False;
  Parts := AText.Split([',', ';', ' ']);
  for Part in Parts do
    for Series := System.Low(TAtlasTrendSeries) to System.High(TAtlasTrendSeries) do
      if SameText(Trim(Part), SeriesKey(Series)) then
        Wanted[Series] := True;
  for Series := System.Low(TAtlasTrendSeries) to System.High(TAtlasTrendSeries) do
    if Wanted[Series] then
      Result := Result + [Series];
end;

class function TAtlasWelcomeTrends.SeriesText(const ASeries: TAtlasTrendSeriesList): string;
var
  Series: TAtlasTrendSeries;
begin
  Result := '';
  for Series in ASeries do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + SeriesKey(Series);
  end;
end;

class function TAtlasWelcomeTrends.NormalizeSeries(const AText: string): string;
begin
  Result := SeriesText(ParseSeries(AText));
end;

class function TAtlasWelcomeTrends.Choose(const AProjects: TArray<string>; const ASelected: string): string;
var
  Project, Wanted: string;
begin
  Result := '';
  if Length(AProjects) = 0 then
    Exit;
  Wanted := TAtlasProjectSummaries.NormalizedPath(ASelected);
  if Wanted <> '' then
    for Project in AProjects do
      if TAtlasProjectSummaries.NormalizedPath(Project) = Wanted then
        Exit(Project);
  Result := AProjects[0];
end;

class procedure TAtlasWelcomeTrends.Scale(const AValues: TArray<Integer>; const AHas: TArray<Boolean>; out ALow,
  AHigh: Integer);
var
  Index: Integer;
begin
  // Die Nulllinie ist immer sichtbar.
  ALow := 0;
  AHigh := 0;
  for Index := 0 to Min(System.High(AValues), System.High(AHas)) do
    if AHas[Index] then
    begin
      ALow := Min(ALow, AValues[Index]);
      AHigh := Max(AHigh, AValues[Index]);
    end;
  // Nur Nullen (oder nichts): eine Einheit Luft nach oben.
  if AHigh = ALow then
    AHigh := ALow + 10;
end;

class function TAtlasWelcomeTrends.View(const ASummary: TAtlasProjectSummary; const ASeries: TAtlasTrendSeriesList;
  ALimit: Integer): TAtlasTrendView;
var
  Points: TArray<TAtlasTrendPoint>;
  Limit, Index: Integer;
  Series: TAtlasTrendSeries;
  Tile: TAtlasTrendTile;
begin
  Result := Default(TAtlasTrendView);
  Result.Project := ASummary.Project;
  Limit := EnsureRange(ALimit, 2, 100);
  Result.Limit := Limit;
  Points := ASummary.Trends.Points;
  if Length(Points) > Limit then
    Points := Copy(Points, Length(Points) - Limit, Limit);
  Result.Points := Points;
  Result.Tiles := nil;
  for Series in ASeries do
  begin
    Tile := Default(TAtlasTrendTile);
    Tile.Series := Series;
    SetLength(Tile.Values, Length(Points));
    SetLength(Tile.Has, Length(Points));
    for Index := 0 to System.High(Points) do
    begin
      Tile.Values[Index] := Points[Index].Values[Series];
      Tile.Has[Index] := Points[Index].Has[Series];
    end;
    Scale(Tile.Values, Tile.Has, Tile.Bottom, Tile.Top);
    Result.Tiles := Result.Tiles + [Tile];
  end;
end;

class function TAtlasWelcomeTrends.ValueText(ASeries: TAtlasTrendSeries; ATenths: Integer; ADecimal: Char): string;
var
  Whole, Tenth: Integer;
begin
  if not TAtlasProjectSummaries.TrendDecimals[ASeries] then
    Exit(IntToStr(ATenths div 10));
  Whole := Abs(ATenths) div 10;
  Tenth := Abs(ATenths) mod 10;
  Result := IntToStr(Whole) + ADecimal + IntToStr(Tenth);
  if ATenths < 0 then
    Result := '-' + Result;
end;

class function TAtlasWelcomeTrends.ShortCommit(const ARevision: string): string;
var
  Index: Integer;
begin
  Result := Trim(ARevision);
  if (Length(Result) <> 40) and (Length(Result) <> 64) then
    Exit;
  for Index := 1 to Length(Result) do
    if not CharInSet(Result[Index], ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit;
  Result := Copy(Result, 1, 7);
end;

class function TAtlasWelcomeTrends.PointX(AIndex, ACount, ALeft, AWidth: Integer): Integer;
begin
  if ACount <= 1 then
    Exit(ALeft + AWidth);
  Result := ALeft + Scaled(AIndex, AWidth, ACount - 1);
end;

class function TAtlasWelcomeTrends.PointY(AValue, ALow, AHigh, ATop, AHeight: Integer): Integer;
begin
  if AHigh <= ALow then
    Exit(ATop + AHeight);
  Result := ATop + AHeight - Scaled(AValue - ALow, AHeight, AHigh - ALow);
end;

class function TAtlasWelcomeTrends.NearestPoint(AX, ACount, ALeft, AWidth: Integer): Integer;
var
  Index, Best, Distance: Integer;
begin
  Result := -1;
  Best := MaxInt;
  for Index := 0 to ACount - 1 do
  begin
    Distance := Abs(PointX(Index, ACount, ALeft, AWidth) - AX);
    if Distance < Best then
    begin
      Best := Distance;
      Result := Index;
    end;
  end;
end;

end.
