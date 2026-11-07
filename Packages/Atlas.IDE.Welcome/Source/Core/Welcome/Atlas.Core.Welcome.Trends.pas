unit Atlas.Core.Welcome.Trends;

// Bereich „Projektverlauf“ der Willkommensseite (#758), Teil ohne VCL und Open
// Tools API: welches Projekt, welche Reihen, Kacheln mit letztem Wert, Vorwert
// und Skala sowie die Lage der Punkte für Zeichnen und Treffertest.
// - Projekt: das im Bereich „Projekte“ (#592) gewählte; ohne Auswahl (oder
//   wenn es nicht mehr in der Liste steht) das oberste.
// - Reihen: welcomePage.trends.series (Liste der Namen aus
//   TAtlasProjectSummaries.cTrendKeys, Vorgabe alle fünf), immer in der
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
    cDefaultSeries = 'warnings,ruleHits,todos,duration,methodLength';
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
  mProduct: Int64;
begin
  mProduct := Int64(AValue) * ANumerator;
  if mProduct >= 0 then
  begin
    Result := Integer((mProduct + ADenominator div 2) div ADenominator);
  end
  else
  begin
    Result := -Integer((-mProduct + ADenominator div 2) div ADenominator);
  end;
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
  begin
    Result := Values[System.High(Values)];
  end;
end;

function TAtlasTrendTile.Previous(out AValue: Integer): Boolean;
var
  mIndex: Integer;
begin
  AValue := 0;
  for mIndex := System.High(Has) - 1 downto 0 do
  begin
    if Has[mIndex] then
    begin
      AValue := Values[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasTrendView }

function TAtlasTrendView.Name: string;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(Project);
  Result := mSummary.Name;
end;

{ TAtlasWelcomeTrends }

class function TAtlasWelcomeTrends.SeriesKey(ASeries: TAtlasTrendSeries): string;
begin
  Result := TAtlasProjectSummaries.cTrendKeys[ASeries];
end;

class function TAtlasWelcomeTrends.ParseSeries(const AText: string): TAtlasTrendSeriesList;
var
  mParts: TArray<string>;
  mPart: string;
  mSeries: TAtlasTrendSeries;
  mWanted: TAtlasTrendFlags;
begin
  Result := nil;
  for mSeries := System.Low(TAtlasTrendSeries) to System.High(TAtlasTrendSeries) do
  begin
    mWanted[mSeries] := False;
  end;
  mParts := AText.Split([',', ';', ' ']);
  for mPart in mParts do
  begin
    for mSeries := System.Low(TAtlasTrendSeries) to System.High(TAtlasTrendSeries) do
    begin
      if SameText(Trim(mPart), SeriesKey(mSeries)) then
      begin
        mWanted[mSeries] := True;
      end;
    end;
  end;
  for mSeries := System.Low(TAtlasTrendSeries) to System.High(TAtlasTrendSeries) do
  begin
    if mWanted[mSeries] then
    begin
      Result := Result + [mSeries];
    end;
  end;
end;

class function TAtlasWelcomeTrends.SeriesText(const ASeries: TAtlasTrendSeriesList): string;
var
  mSeries: TAtlasTrendSeries;
begin
  Result := '';
  for mSeries in ASeries do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + SeriesKey(mSeries);
  end;
end;

class function TAtlasWelcomeTrends.NormalizeSeries(const AText: string): string;
begin
  Result := SeriesText(ParseSeries(AText));
end;

class function TAtlasWelcomeTrends.Choose(const AProjects: TArray<string>; const ASelected: string): string;
var
  mProject, mWanted: string;
begin
  Result := '';
  if Length(AProjects) = 0 then
  begin
    Exit;
  end;
  mWanted := TAtlasProjectSummaries.NormalizedPath(ASelected);
  if mWanted <> '' then
  begin
    for mProject in AProjects do
    begin
      if TAtlasProjectSummaries.NormalizedPath(mProject) = mWanted then
      begin
        Exit(mProject);
      end;
    end;
  end;
  Result := AProjects[0];
end;

class procedure TAtlasWelcomeTrends.Scale(const AValues: TArray<Integer>; const AHas: TArray<Boolean>; out ALow,
  AHigh: Integer);
var
  mIndex: Integer;
begin
  // Die Nulllinie ist immer sichtbar.
  ALow := 0;
  AHigh := 0;
  for mIndex := 0 to Min(System.High(AValues), System.High(AHas)) do
  begin
    if AHas[mIndex] then
    begin
      ALow := Min(ALow, AValues[mIndex]);
      AHigh := Max(AHigh, AValues[mIndex]);
    end;
  end;
  // Nur Nullen (oder nichts): eine Einheit Luft nach oben.
  if AHigh = ALow then
  begin
    AHigh := ALow + 10;
  end;
end;

class function TAtlasWelcomeTrends.View(const ASummary: TAtlasProjectSummary; const ASeries: TAtlasTrendSeriesList;
  ALimit: Integer): TAtlasTrendView;
var
  mPoints: TArray<TAtlasTrendPoint>;
  mLimit, mIndex: Integer;
  mSeries: TAtlasTrendSeries;
  mTile: TAtlasTrendTile;
begin
  Result := Default(TAtlasTrendView);
  Result.Project := ASummary.Project;
  mLimit := EnsureRange(ALimit, 2, 100);
  Result.Limit := mLimit;
  mPoints := ASummary.Trends.Points;
  if Length(mPoints) > mLimit then
  begin
    mPoints := Copy(mPoints, Length(mPoints) - mLimit, mLimit);
  end;
  Result.Points := mPoints;
  Result.Tiles := nil;
  for mSeries in ASeries do
  begin
    mTile := Default(TAtlasTrendTile);
    mTile.Series := mSeries;
    SetLength(mTile.Values, Length(mPoints));
    SetLength(mTile.Has, Length(mPoints));
    for mIndex := 0 to System.High(mPoints) do
    begin
      mTile.Values[mIndex] := mPoints[mIndex].Values[mSeries];
      mTile.Has[mIndex] := mPoints[mIndex].Has[mSeries];
    end;
    Scale(mTile.Values, mTile.Has, mTile.Bottom, mTile.Top);
    Result.Tiles := Result.Tiles + [mTile];
  end;
end;

class function TAtlasWelcomeTrends.ValueText(ASeries: TAtlasTrendSeries; ATenths: Integer; ADecimal: Char): string;
var
  mWhole, mTenth: Integer;
begin
  if not TAtlasProjectSummaries.cTrendDecimals[ASeries] then
  begin
    Exit(IntToStr(ATenths div 10));
  end;
  mWhole := Abs(ATenths) div 10;
  mTenth := Abs(ATenths) mod 10;
  Result := IntToStr(mWhole) + ADecimal + IntToStr(mTenth);
  if ATenths < 0 then
  begin
    Result := '-' + Result;
  end;
end;

class function TAtlasWelcomeTrends.ShortCommit(const ARevision: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(ARevision);
  if (Length(Result) <> 40) and (Length(Result) <> 64) then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(Result) do
  begin
    if not CharInSet(Result[mIndex], ['0'..'9', 'a'..'f', 'A'..'F']) then
    begin
      Exit;
    end;
  end;
  Result := Copy(Result, 1, 7);
end;

class function TAtlasWelcomeTrends.PointX(AIndex, ACount, ALeft, AWidth: Integer): Integer;
begin
  if ACount <= 1 then
  begin
    Exit(ALeft + AWidth);
  end;
  Result := ALeft + Scaled(AIndex, AWidth, ACount - 1);
end;

class function TAtlasWelcomeTrends.PointY(AValue, ALow, AHigh, ATop, AHeight: Integer): Integer;
begin
  if AHigh <= ALow then
  begin
    Exit(ATop + AHeight);
  end;
  Result := ATop + AHeight - Scaled(AValue - ALow, AHeight, AHigh - ALow);
end;

class function TAtlasWelcomeTrends.NearestPoint(AX, ACount, ALeft, AWidth: Integer): Integer;
var
  mIndex, mBest, mDistance: Integer;
begin
  Result := -1;
  mBest := MaxInt;
  for mIndex := 0 to ACount - 1 do
  begin
    mDistance := Abs(PointX(mIndex, ACount, ALeft, AWidth) - AX);
    if mDistance < mBest then
    begin
      mBest := mDistance;
      Result := mIndex;
    end;
  end;
end;

end.
