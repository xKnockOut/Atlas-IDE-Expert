unit Atlas.Common.Architecture.Layout;

// Anordnung der Architekturkarte (#1118): dieselben Koordinaten für das
// IDE-Fenster und den HTML-Bericht, deterministisch und schnell auch bei
// einigen tausend Units.
//
// - Je Teilsystem ein Kreis: die zentralste Unit in der Mitte, die übrigen
//   nach gesamt abhängig auf Ringen nach außen (Ring r fasst 6·r Units).
// - Teilsysteme nach Größe: das größte in der Mitte, jedes weitere berührt
//   ein schon gesetztes, so nah wie möglich am Schwerpunkt der Teilsysteme,
//   mit denen es Kanten hat, ohne sich zu überlappen. Teile eines
//   nachgeteilten Teilsystems (#1364, gleicher Parent) legen sich an ihre
//   schon gesetzten Geschwister.
// - Einheiten: Abstand zweier Units auf einem Ring etwa Spacing; Ursprung
//   ist die Mitte des ersten Teilsystems, die Karte verschiebt nach Bedarf.

interface

uses
  Atlas.Common.Architecture.Overview;

type
  TLayoutPoint = record
    X: Double;
    Y: Double;
  end;

  TLayoutCircle = record
    X: Double;
    Y: Double;
    Radius: Double;
  end;

  TArchitectureLayout = record
    /// <summary>Lage je Unit (Nummern wie in TArchitectureOverview.Units).</summary>
    Units: TArray<TLayoutPoint>;
    /// <summary>Kreis je Teilsystem.</summary>
    Subsystems: TArray<TLayoutCircle>;
    /// <summary>Umgebendes Rechteck aller Kreise.</summary>
    Left, Top, Right, Bottom: Double;
  end;

  TArchitectureLayouter = class
  public const
    Spacing = 40.0;
    /// <summary>Abstand zwischen zwei Teilsystemen.</summary>
    Gap = 30.0;
  public
    class function Compute(const AOverview: TArchitectureOverview): TArchitectureLayout; static;
  end;

implementation

uses
  System.Math,
  System.SysUtils;

function Siblings(const AOverview: TArchitectureOverview; ALeft, ARight: Integer): Boolean;
begin
  Result := (AOverview.Subsystems[ALeft].Parent <> '') and
    SameText(AOverview.Subsystems[ALeft].Parent, AOverview.Subsystems[ARight].Parent);
end;

/// <summary>Lage einer Unit an Stelle AIndex im Teilsystem (0 = Mitte), relativ zur Mitte.</summary>
function RingPoint(AIndex: Integer): TLayoutPoint;
var
  Ring, First, Capacity, Slot: Integer;
  Angle: Double;
begin
  Result.X := 0;
  Result.Y := 0;
  if AIndex = 0 then
    Exit;
  // Ring r beginnt bei 1 + 3·r·(r-1) und fasst 6·r Units.
  Ring := 1;
  First := 1;
  while AIndex >= First + 6 * Ring do
  begin
    Inc(First, 6 * Ring);
    Inc(Ring);
  end;
  Capacity := 6 * Ring;
  Slot := AIndex - First;
  // Jeder zweite Ring um einen halben Platz versetzt, damit Speichen nicht übereinanderliegen.
  Angle := (Slot + 0.5 * (Ring mod 2)) / Capacity * 2 * Pi - Pi / 2;
  Result.X := Cos(Angle) * Ring * TArchitectureLayouter.Spacing;
  Result.Y := Sin(Angle) * Ring * TArchitectureLayouter.Spacing;
end;

function RingRadius(ACount: Integer): Double;
var
  Ring, First: Integer;
begin
  if ACount <= 1 then
    Exit(TArchitectureLayouter.Spacing * 0.75);
  Ring := 1;
  First := 1;
  while ACount > First + 6 * Ring do
  begin
    Inc(First, 6 * Ring);
    Inc(Ring);
  end;
  Result := (Ring + 0.75) * TArchitectureLayouter.Spacing;
end;

function Overlaps(const ACircles: TArray<TLayoutCircle>; ACount: Integer; X, Y, ARadius: Double): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to ACount - 1 do
    if Sqr(ACircles[Index].X - X) + Sqr(ACircles[Index].Y - Y) <
      Sqr(ACircles[Index].Radius + ARadius + TArchitectureLayouter.Gap) - 1E-6 then
      Exit(True);
  Result := False;
end;

class function TArchitectureLayouter.Compute(const AOverview: TArchitectureOverview): TArchitectureLayout;
const
  Angles = 36;
var
  Count, Index, Other, Placed, Step, Position, Pass: Integer;
  Links: TArray<TArray<Integer>>;
  Edge: TOverviewEdge;
  From_, To_: Integer;
  TargetX, TargetY, Weight, Total, Angle, X, Y, Distance, BestX, BestY, BestDistance: Double;
  SiblingX, SiblingY: Double;
  SiblingCount: Integer;
  Circle: TLayoutCircle;
  Point: TLayoutPoint;
begin
  Result := Default(TArchitectureLayout);
  Count := Length(AOverview.Subsystems);
  SetLength(Result.Subsystems, Count);
  SetLength(Result.Units, Length(AOverview.Units));
  if Count = 0 then
    Exit;
  // Kanten zwischen Teilsystemen (ungerichtet) als Anziehung.
  SetLength(Links, Count);
  for Index := 0 to Count - 1 do
    SetLength(Links[Index], Count);
  for Edge in AOverview.Edges do
  begin
    From_ := AOverview.Units[Edge.Source].Subsystem;
    To_ := AOverview.Units[Edge.Target].Subsystem;
    if From_ <> To_ then
    begin
      Inc(Links[From_][To_]);
      Inc(Links[To_][From_]);
    end;
  end;
  for Index := 0 to Count - 1 do
    Result.Subsystems[Index].Radius := RingRadius(Length(AOverview.Subsystems[Index].Units));
  // Das erste (größte) Teilsystem in die Mitte, die übrigen der Reihe nach anlegen.
  Result.Subsystems[0].X := 0;
  Result.Subsystems[0].Y := 0;
  for Placed := 1 to Count - 1 do
  begin
    Circle := Result.Subsystems[Placed];
    TargetX := 0;
    TargetY := 0;
    Total := 0;
    for Other := 0 to Placed - 1 do
    begin
      Weight := Links[Placed][Other];
      TargetX := TargetX + Weight * Result.Subsystems[Other].X;
      TargetY := TargetY + Weight * Result.Subsystems[Other].Y;
      Total := Total + Weight;
    end;
    if Total > 0 then
    begin
      TargetX := TargetX / Total;
      TargetY := TargetY / Total;
    end;
    // Geschwister ziehen stärker als Kanten: Ziel ist ihr Schwerpunkt.
    SiblingX := 0;
    SiblingY := 0;
    SiblingCount := 0;
    for Other := 0 to Placed - 1 do
      if Siblings(AOverview, Placed, Other) then
      begin
        SiblingX := SiblingX + Result.Subsystems[Other].X;
        SiblingY := SiblingY + Result.Subsystems[Other].Y;
        Inc(SiblingCount);
      end;
    if SiblingCount > 0 then
    begin
      TargetX := SiblingX / SiblingCount;
      TargetY := SiblingY / SiblingCount;
    end;
    BestDistance := MaxDouble;
    BestX := 0;
    BestY := 0;
    // Erst nur an verbundenen und zuletzt gesetzten Teilsystemen anlegen (bei vielen Teilsystemen sonst
    // kubisch), ohne freien Platz dort an allen.
    for Pass := 0 to 1 do
    begin
      for Other := 0 to Placed - 1 do
      begin
        if (Pass = 0) and (Links[Placed][Other] = 0) and (Other < Placed - 6) and (Other > 0) and
          not Siblings(AOverview, Placed, Other) then
          Continue;
        for Step := 0 to Angles - 1 do
        begin
          Angle := Step / Angles * 2 * Pi;
          Distance := Result.Subsystems[Other].Radius + Circle.Radius + Gap;
          X := Result.Subsystems[Other].X + Cos(Angle) * Distance;
          Y := Result.Subsystems[Other].Y + Sin(Angle) * Distance;
          if Overlaps(Result.Subsystems, Placed, X, Y, Circle.Radius) then
            Continue;
          Distance := Sqr(X - TargetX) + Sqr(Y - TargetY);
          // Gleichstand: der zuerst gefundene Platz (feste Reihenfolge).
          if Distance < BestDistance - 1E-6 then
          begin
            BestDistance := Distance;
            BestX := X;
            BestY := Y;
          end;
        end;
      end;
      if BestDistance < MaxDouble then
        Break;
    end;
    Circle.X := BestX;
    Circle.Y := BestY;
    Result.Subsystems[Placed] := Circle;
  end;
  for Index := 0 to Count - 1 do
    for Position := 0 to High(AOverview.Subsystems[Index].Units) do
    begin
      Point := RingPoint(Position);
      Point.X := Point.X + Result.Subsystems[Index].X;
      Point.Y := Point.Y + Result.Subsystems[Index].Y;
      Result.Units[AOverview.Subsystems[Index].Units[Position]] := Point;
    end;
  Result.Left := MaxDouble;
  Result.Top := MaxDouble;
  Result.Right := -MaxDouble;
  Result.Bottom := -MaxDouble;
  for Circle in Result.Subsystems do
  begin
    Result.Left := Min(Result.Left, Circle.X - Circle.Radius);
    Result.Top := Min(Result.Top, Circle.Y - Circle.Radius);
    Result.Right := Max(Result.Right, Circle.X + Circle.Radius);
    Result.Bottom := Max(Result.Bottom, Circle.Y + Circle.Radius);
  end;
end;

end.
