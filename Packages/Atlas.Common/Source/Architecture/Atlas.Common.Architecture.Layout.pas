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
  begin
    Exit;
  end;
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
  begin
    Exit(TArchitectureLayouter.Spacing * 0.75);
  end;
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
  begin
    if Sqr(ACircles[Index].X - X) + Sqr(ACircles[Index].Y - Y) <
      Sqr(ACircles[Index].Radius + ARadius + TArchitectureLayouter.Gap) - 1E-6 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

const
  /// <summary>Probierte Winkel je Nachbar beim Anlegen eines Teilsystems.</summary>
  cAngles = 36;

type
  /// <summary>Bester bisher gefundener Platz eines Teilsystems (Distance = Abstandsquadrat zum Ziel).</summary>
  TPlacement = record
    X: Double;
    Y: Double;
    Distance: Double;
  end;

/// <summary>Kanten zwischen Teilsystemen (ungerichtet) als Anziehung: Anzahl je Paar.</summary>
function LinksOf(const AOverview: TArchitectureOverview; ACount: Integer): TArray<TArray<Integer>>;
var
  mIndex, mFrom, mTo: Integer;
  mEdge: TOverviewEdge;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    SetLength(Result[mIndex], ACount);
  end;
  for mEdge in AOverview.Edges do
  begin
    mFrom := AOverview.Units[mEdge.Source].Subsystem;
    mTo := AOverview.Units[mEdge.Target].Subsystem;
    if mFrom <> mTo then
    begin
      Inc(Result[mFrom][mTo]);
      Inc(Result[mTo][mFrom]);
    end;
  end;
end;

/// <summary>Ziel für APlaced: Schwerpunkt der Geschwister, sonst nach Kanten gewichteter Schwerpunkt der schon
/// gesetzten Teilsysteme (ohne Kanten der Ursprung).</summary>
function TargetOf(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout;
  const ALinks: TArray<TArray<Integer>>; APlaced: Integer): TLayoutPoint;
var
  mOther, mSiblingCount: Integer;
  mWeight, mTotal: Double;
  mSibling: TLayoutPoint;
begin
  Result := Default(TLayoutPoint);
  mSibling := Default(TLayoutPoint);
  mTotal := 0;
  mSiblingCount := 0;
  for mOther := 0 to APlaced - 1 do
  begin
    mWeight := ALinks[APlaced][mOther];
    Result.X := Result.X + mWeight * ALayout.Subsystems[mOther].X;
    Result.Y := Result.Y + mWeight * ALayout.Subsystems[mOther].Y;
    mTotal := mTotal + mWeight;
    if Siblings(AOverview, APlaced, mOther) then
    begin
      mSibling.X := mSibling.X + ALayout.Subsystems[mOther].X;
      mSibling.Y := mSibling.Y + ALayout.Subsystems[mOther].Y;
      Inc(mSiblingCount);
    end;
  end;
  // Geschwister ziehen stärker als Kanten: Ziel ist ihr Schwerpunkt.
  if mSiblingCount > 0 then
  begin
    Result.X := mSibling.X / mSiblingCount;
    Result.Y := mSibling.Y / mSiblingCount;
  end
  else if mTotal > 0 then
  begin
    Result.X := Result.X / mTotal;
    Result.Y := Result.Y / mTotal;
  end;
end;

/// <summary>Plätze rund um AOther, die keinen gesetzten Kreis überlappen; der dem Ziel nächste landet in ABest.
/// </summary>
procedure TryAround(const ALayout: TArchitectureLayout; APlaced, AOther: Integer; const ATarget: TLayoutPoint;
  var ABest: TPlacement);
var
  mStep: Integer;
  mAngle, mX, mY, mDistance, mRadius: Double;
begin
  mRadius := ALayout.Subsystems[APlaced].Radius;
  for mStep := 0 to cAngles - 1 do
  begin
    mAngle := mStep / cAngles * 2 * Pi;
    mDistance := ALayout.Subsystems[AOther].Radius + mRadius + TArchitectureLayouter.Gap;
    mX := ALayout.Subsystems[AOther].X + Cos(mAngle) * mDistance;
    mY := ALayout.Subsystems[AOther].Y + Sin(mAngle) * mDistance;
    if Overlaps(ALayout.Subsystems, APlaced, mX, mY, mRadius) then
    begin
      Continue;
    end;
    mDistance := Sqr(mX - ATarget.X) + Sqr(mY - ATarget.Y);
    // Gleichstand: der zuerst gefundene Platz (feste Reihenfolge).
    if mDistance < ABest.Distance - 1E-6 then
    begin
      ABest.Distance := mDistance;
      ABest.X := mX;
      ABest.Y := mY;
    end;
  end;
end;

/// <summary>Im ersten Durchgang nur an verbundenen, verwandten und zuletzt gesetzten Teilsystemen anlegen.</summary>
function IsNearCandidate(const AOverview: TArchitectureOverview; const ALinks: TArray<TArray<Integer>>;
  APlaced, AOther: Integer): Boolean;
begin
  Result := (ALinks[APlaced][AOther] <> 0) or (AOther >= APlaced - 6) or (AOther = 0) or
    Siblings(AOverview, APlaced, AOther);
end;

/// <summary>Teilsystem APlaced an das bestehende Bild anlegen.</summary>
procedure Place(const AOverview: TArchitectureOverview; var ALayout: TArchitectureLayout;
  const ALinks: TArray<TArray<Integer>>; APlaced: Integer);
var
  mOther, mPass: Integer;
  mTarget: TLayoutPoint;
  mBest: TPlacement;
begin
  mTarget := TargetOf(AOverview, ALayout, ALinks, APlaced);
  mBest.Distance := MaxDouble;
  mBest.X := 0;
  mBest.Y := 0;
  // Erst nur an verbundenen und zuletzt gesetzten Teilsystemen anlegen (bei vielen Teilsystemen sonst
  // kubisch), ohne freien Platz dort an allen.
  for mPass := 0 to 1 do
  begin
    for mOther := 0 to APlaced - 1 do
    begin
      if (mPass = 1) or IsNearCandidate(AOverview, ALinks, APlaced, mOther) then
      begin
        TryAround(ALayout, APlaced, mOther, mTarget, mBest);
      end;
    end;
    if mBest.Distance < MaxDouble then
    begin
      Break;
    end;
  end;
  ALayout.Subsystems[APlaced].X := mBest.X;
  ALayout.Subsystems[APlaced].Y := mBest.Y;
end;

/// <summary>Units in Ringen um den Mittelpunkt ihres Teilsystems.</summary>
procedure PlaceUnits(const AOverview: TArchitectureOverview; var ALayout: TArchitectureLayout);
var
  mIndex, mPosition: Integer;
  mPoint: TLayoutPoint;
begin
  for mIndex := 0 to High(ALayout.Subsystems) do
  begin
    for mPosition := 0 to High(AOverview.Subsystems[mIndex].Units) do
    begin
      mPoint := RingPoint(mPosition);
      mPoint.X := mPoint.X + ALayout.Subsystems[mIndex].X;
      mPoint.Y := mPoint.Y + ALayout.Subsystems[mIndex].Y;
      ALayout.Units[AOverview.Subsystems[mIndex].Units[mPosition]] := mPoint;
    end;
  end;
end;

/// <summary>Umgebendes Rechteck aller Kreise.</summary>
procedure ComputeBounds(var ALayout: TArchitectureLayout);
var
  mCircle: TLayoutCircle;
begin
  ALayout.Left := MaxDouble;
  ALayout.Top := MaxDouble;
  ALayout.Right := -MaxDouble;
  ALayout.Bottom := -MaxDouble;
  for mCircle in ALayout.Subsystems do
  begin
    ALayout.Left := Min(ALayout.Left, mCircle.X - mCircle.Radius);
    ALayout.Top := Min(ALayout.Top, mCircle.Y - mCircle.Radius);
    ALayout.Right := Max(ALayout.Right, mCircle.X + mCircle.Radius);
    ALayout.Bottom := Max(ALayout.Bottom, mCircle.Y + mCircle.Radius);
  end;
end;

class function TArchitectureLayouter.Compute(const AOverview: TArchitectureOverview): TArchitectureLayout;
var
  mCount, mIndex: Integer;
  mLinks: TArray<TArray<Integer>>;
begin
  Result := Default(TArchitectureLayout);
  mCount := Length(AOverview.Subsystems);
  SetLength(Result.Subsystems, mCount);
  SetLength(Result.Units, Length(AOverview.Units));
  if mCount = 0 then
  begin
    Exit;
  end;
  mLinks := LinksOf(AOverview, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    Result.Subsystems[mIndex].Radius := RingRadius(Length(AOverview.Subsystems[mIndex].Units));
  end;
  // Das erste (größte) Teilsystem in die Mitte, die übrigen der Reihe nach anlegen.
  Result.Subsystems[0].X := 0;
  Result.Subsystems[0].Y := 0;
  for mIndex := 1 to mCount - 1 do
  begin
    Place(AOverview, Result, mLinks, mIndex);
  end;
  PlaceUnits(AOverview, Result);
  ComputeBounds(Result);
end;

end.
