unit Atlas.Core.EditorToolbar.Glyphs;

// Atlas-Editorleiste (#1101), Symbole als Vektorgrafik ohne VCL und OTA: Jedes
// Symbol besteht aus Linienzügen und gefüllten Flächen in einem Feld von
// 16 × 16 Einheiten (wie die Mockups, viewBox 0 0 16 16). Die Oberfläche
// skaliert sie auf die DPI des Editors und zeichnet sie geglättet in Schrift-
// bzw. Akzentfarbe des IDE-Themas; Bögen und Kreise sind hier schon in kurze
// Strecken zerlegt. Letter hat keine Form (die Oberfläche zeichnet den ersten
// Buchstaben der Beschriftung).

interface

uses
  System.SysUtils,
  Atlas.Core.EditorToolbar.Icons;

type
  TAtlasGlyphPoint = record
    X: Single;
    Y: Single;
  end;

  TAtlasGlyphShape = record
    Points: TArray<TAtlasGlyphPoint>;
    /// <summary>Linienzug schließen (Umriss).</summary>
    Closed: Boolean;
    /// <summary>Fläche füllen statt Linie ziehen.</summary>
    Filled: Boolean;
  end;

  TAtlasGlyphs = class
  public const
    /// <summary>Kantenlänge des Felds in Einheiten.</summary>
    Size = 16;
    /// <summary>Linienbreite in Einheiten.</summary>
    StrokeWidth = 1.4;
  public
    class function Shapes(AIcon: TAtlasToolbarIcon): TArray<TAtlasGlyphShape>; static;
  end;

implementation

uses
  System.Math;

function P(X, Y: Single): TAtlasGlyphPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Stroke(const APoints: array of TAtlasGlyphPoint): TAtlasGlyphShape;
var
  Index: Integer;
begin
  SetLength(Result.Points, Length(APoints));
  for Index := 0 to High(APoints) do
    Result.Points[Index] := APoints[Index];
  Result.Closed := False;
  Result.Filled := False;
end;

function Outline(const APoints: array of TAtlasGlyphPoint): TAtlasGlyphShape;
begin
  Result := Stroke(APoints);
  Result.Closed := True;
end;

function Fill(const APoints: array of TAtlasGlyphPoint): TAtlasGlyphShape;
begin
  Result := Stroke(APoints);
  Result.Closed := True;
  Result.Filled := True;
end;

/// <summary>Punkte eines Bogens um CX/CY mit Radius R von AFrom bis ATo Grad (Bildschirmrichtung, 0 = rechts,
/// 90 = unten), ohne den Anfangspunkt.</summary>
function ArcPoints(CX, CY, R, AFrom, ATo: Single; ASteps: Integer): TArray<TAtlasGlyphPoint>;
var
  Index: Integer;
  Angle: Single;
begin
  SetLength(Result, ASteps);
  for Index := 1 to ASteps do
  begin
    Angle := DegToRad(AFrom + (ATo - AFrom) * Index / ASteps);
    Result[Index - 1] := P(CX + R * Cos(Angle), CY + R * Sin(Angle));
  end;
end;

function Circle(CX, CY, R: Single; AFilled: Boolean): TAtlasGlyphShape;
begin
  Result.Points := ArcPoints(CX, CY, R, 0, 360, 24);
  Result.Closed := True;
  Result.Filled := AFilled;
end;

/// <summary>Umriss eines Auges wie im Mockup (Pfad "M1.5 8s2.4-4.5 6.5-4.5S14.5 8 14.5 8 12.1 12.5 8 12.5 1.5 8 1.5
/// 8Z"): vier kubische Bögen, je acht Strecken.</summary>
function EyeOutline: TAtlasGlyphShape;
const
  // Je Bogen Start, zwei Stützpunkte, Ende.
  Arcs: array[0..3, 0..3, 0..1] of Single = (
    ((1.5, 8), (1.5, 8), (3.9, 3.5), (8, 3.5)),
    ((8, 3.5), (12.1, 3.5), (14.5, 8), (14.5, 8)),
    ((14.5, 8), (14.5, 8), (12.1, 12.5), (8, 12.5)),
    ((8, 12.5), (3.9, 12.5), (1.5, 8), (1.5, 8)));
  Steps = 8;
var
  Points: TArray<TAtlasGlyphPoint>;
  Arc, Step: Integer;
  T, U: Single;
begin
  Points := nil;
  for Arc := 0 to High(Arcs) do
    for Step := 0 to Steps - 1 do
    begin
      T := Step / Steps;
      U := 1 - T;
      Points := Points + [P(U * U * U * Arcs[Arc, 0, 0] + 3 * U * U * T * Arcs[Arc, 1, 0] + 3 * U * T * T * Arcs[Arc, 2, 0] +
        T * T * T * Arcs[Arc, 3, 0], U * U * U * Arcs[Arc, 0, 1] + 3 * U * U * T * Arcs[Arc, 1, 1] +
        3 * U * T * T * Arcs[Arc, 2, 1] + T * T * T * Arcs[Arc, 3, 1])];
    end;
  Result.Points := Points;
  Result.Closed := True;
  Result.Filled := False;
end;

/// <summary>Umriss eines Zahnrads um CX/CY mit ATeeth Zähnen: Kopf auf AOuter, Fuß auf AInner, Zahn und Lücke etwa
/// gleich breit. Je Zahn vier Punkte (Fuß, Flanke hinauf, Kopf, Flanke hinab).</summary>
function GearOutline(CX, CY, AOuter, AInner: Single; ATeeth: Integer): TAtlasGlyphShape;
var
  Points: TArray<TAtlasGlyphPoint>;
  Tooth: Integer;
  Step, Start: Single;

  procedure Add(AAngle, ARadius: Single);
  begin
    Points := Points + [P(CX + ARadius * Cos(AAngle), CY + ARadius * Sin(AAngle))];
  end;

begin
  Points := nil;
  Step := 2 * Pi / ATeeth;
  for Tooth := 0 to ATeeth - 1 do
  begin
    Start := Tooth * Step - Step / 4;
    Add(Start, AInner);
    Add(Start + Step * 0.12, AOuter);
    Add(Start + Step * 0.38, AOuter);
    Add(Start + Step * 0.5, AInner);
  end;
  Result.Points := Points;
  Result.Closed := True;
  Result.Filled := False;
end;

function Join(const A: array of TAtlasGlyphPoint; const B: TArray<TAtlasGlyphPoint>;
  const C: array of TAtlasGlyphPoint): TArray<TAtlasGlyphPoint>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(A) do
    Result := Result + [A[Index]];
  Result := Result + B;
  for Index := 0 to High(C) do
    Result := Result + [C[Index]];
end;

function Shape(const APoints: TArray<TAtlasGlyphPoint>; AClosed, AFilled: Boolean): TAtlasGlyphShape;
begin
  Result.Points := APoints;
  Result.Closed := AClosed;
  Result.Filled := AFilled;
end;

/// <summary>Blatt mit Eselsohr (Rahmen der Abschnittssymbole).</summary>
function Sheet: TAtlasGlyphShape;
begin
  Result := Outline([P(3.5, 1.5), P(9.5, 1.5), P(12.5, 4.5), P(12.5, 14.5), P(3.5, 14.5)]);
end;

class function TAtlasGlyphs.Shapes(AIcon: TAtlasToolbarIcon): TArray<TAtlasGlyphShape>;
begin
  case AIcon of
    TAtlasToolbarIcon.InterfacePart:
      // Obere Hälfte gefüllt: der Kopf der Unit.
      Result := [Sheet, Fill([P(3.5, 1.5), P(9.5, 1.5), P(12.5, 4.5), P(12.5, 8), P(3.5, 8)]),
        Stroke([P(5.5, 10.5), P(10.5, 10.5)]), Stroke([P(5.5, 12.5), P(9, 12.5)])];
    TAtlasToolbarIcon.ImplementationPart:
      // Untere Hälfte gefüllt.
      Result := [Sheet, Fill([P(3.5, 8), P(12.5, 8), P(12.5, 14.5), P(3.5, 14.5)]),
        Stroke([P(5.5, 4), P(9, 4)]), Stroke([P(5.5, 6), P(10.5, 6)])];
    TAtlasToolbarIcon.UsesClause:
      Result := [Sheet, Stroke([P(5.5, 5.5), P(10.5, 5.5)]), Stroke([P(5.5, 8), P(10.5, 8)]),
        Stroke([P(5.5, 10.5), P(8.5, 10.5)]), Circle(12.5, 12.5, 2.2, True)];
    TAtlasToolbarIcon.Initialization_:
      Result := [Sheet, Fill([P(6.5, 8.5), P(9.5, 10.5), P(6.5, 12.5)])];
    TAtlasToolbarIcon.Return:
      Result := [Shape(Join([P(13, 3.5), P(13, 7.5)], ArcPoints(10.5, 7.5, 2.5, 0, 90, 6), [P(3.5, 10)]), False,
        False), Stroke([P(6.5, 7), P(3.5, 10), P(6.5, 13)])];
    TAtlasToolbarIcon.Back:
      Result := [Stroke([P(10, 3.5), P(5.5, 8), P(10, 12.5)])];
    TAtlasToolbarIcon.Forward:
      Result := [Stroke([P(6, 3.5), P(10.5, 8), P(6, 12.5)])];
    TAtlasToolbarIcon.Toggle:
      Result := [Stroke([P(5, 2.5), P(5, 11.5)]), Stroke([P(2.5, 9), P(5, 11.5), P(7.5, 9)]),
        Stroke([P(11, 13.5), P(11, 4.5)]), Stroke([P(8.5, 7), P(11, 4.5), P(13.5, 7)])];
    TAtlasToolbarIcon.TestUnit:
      // Kolben.
      Result := [Stroke([P(6, 1.5), P(6, 6), P(2.5, 13), P(2.6, 14), P(3.4, 14.5), P(12.6, 14.5), P(13.4, 14),
        P(13.5, 13), P(10, 6), P(10, 1.5)]), Stroke([P(5, 1.5), P(11, 1.5)]), Stroke([P(4.4, 10.5), P(11.6, 10.5)])];
    TAtlasToolbarIcon.UnitSearch:
      Result := [Circle(7, 7, 4.5, False), Stroke([P(10.4, 10.4), P(14, 14)]), Stroke([P(5.5, 5.5), P(8.5, 5.5)]),
        Stroke([P(5.5, 7.5), P(8.5, 7.5)])];
    TAtlasToolbarIcon.FindMethod:
      Result := [Stroke([P(2.5, 4), P(8.5, 4)]), Stroke([P(2.5, 7), P(6.5, 7)]), Stroke([P(2.5, 10), P(7.5, 10)]),
        Circle(11.5, 9.5, 2.5, False), Stroke([P(13.3, 11.3), P(15, 13)])];
    TAtlasToolbarIcon.QuickOpen:
      Result := [Stroke([P(1.5, 4.5), P(1.5, 12.5), P(12.5, 12.5), P(14.5, 6.5), P(3.5, 6.5), P(1.5, 12.5)]),
        Stroke([P(1.5, 4.5), P(1.5, 3.5), P(5.5, 3.5), P(6.5, 4.5), P(11.5, 4.5), P(11.5, 6.5)])];
    TAtlasToolbarIcon.CodeActions:
      // Glühbirne: Bogen über dem Sockel.
      Result := [Shape(Join([P(5.5, 10.5)], ArcPoints(8, 6.758, 4.5, 123.75, 416.25, 20), [P(10.5, 12), P(5.5, 12)]),
        True, False), Stroke([P(6, 14), P(10, 14)])];
    TAtlasToolbarIcon.Format:
      Result := [Stroke([P(2, 3.5), P(14, 3.5)]), Stroke([P(5, 6.5), P(14, 6.5)]), Stroke([P(5, 9.5), P(14, 9.5)]),
        Stroke([P(2, 12.5), P(14, 12.5)])];
    TAtlasToolbarIcon.Problems:
      // Schild mit Haken.
      Result := [Outline([P(8, 1.5), P(13.5, 3.5), P(13.5, 7.5), P(13.2, 10.2), P(11.5, 12.6), P(8, 14.5),
        P(4.5, 12.6), P(2.8, 10.2), P(2.5, 7.5), P(2.5, 3.5)]), Stroke([P(5.5, 8), P(7.5, 10), P(10.5, 6.5)])];
    TAtlasToolbarIcon.Outline:
      Result := [Stroke([P(2.5, 3), P(5.5, 3)]), Stroke([P(4, 3), P(4, 12.5), P(6, 12.5)]), Stroke([P(4, 8), P(6, 8)]),
        Stroke([P(8, 3), P(13.5, 3)]), Stroke([P(8, 8), P(13.5, 8)]), Stroke([P(8, 12.5), P(13.5, 12.5)])];
    TAtlasToolbarIcon.Palette:
      Result := [Outline([P(3, 3), P(13, 3), P(14.5, 4.5), P(14.5, 11.5), P(13, 13), P(3, 13), P(1.5, 11.5),
        P(1.5, 4.5)]), Stroke([P(4, 6.5), P(6, 8), P(4, 9.5)]), Stroke([P(7.5, 10), P(11.5, 10)])];
    TAtlasToolbarIcon.More:
      Result := [Stroke([P(4, 4.5), P(7.5, 8), P(4, 11.5)]), Stroke([P(8.5, 4.5), P(12, 8), P(8.5, 11.5)])];
    TAtlasToolbarIcon.Gear:
      // Zahnkranz mit Loch; früher Kreis mit acht Strahlen, das sah aus wie eine Sonne.
      Result := [GearOutline(8, 8, 6.8, 5, 8), Circle(8, 8, 2.2, False)];
    // Designer-Leiste (#1442): Formen wie in den Mockups (Strichsymbole, viewBox 0 0 16 16).
    TAtlasToolbarIcon.ComponentSearch:
      // Lupe.
      Result := [Circle(7, 7, 4.5, False), Stroke([P(10.5, 10.5), P(14, 14)])];
    TAtlasToolbarIcon.NonVisual:
      // Auge.
      Result := [EyeOutline, Circle(8, 8, 2, False)];
    TAtlasToolbarIcon.NonVisualHidden:
      // Durchgestrichenes Auge: Die IDE blendet die nichtvisuellen Komponenten aus.
      Result := [EyeOutline, Circle(8, 8, 2, False), Stroke([P(2.5, 13.5), P(13.5, 2.5)])];
    TAtlasToolbarIcon.SelectParent:
      // Pfeil nach oben.
      Result := [Stroke([P(8, 13), P(8, 4)]), Stroke([P(4.5, 7.5), P(8, 4), P(11.5, 7.5)])];
    TAtlasToolbarIcon.TabOrder:
      // Pfeil nach rechts oben, nach links unten.
      Result := [Stroke([P(2, 5), P(11, 5)]), Stroke([P(8, 2), P(11, 5), P(8, 8)]), Stroke([P(14, 11), P(5, 11)]),
        Stroke([P(8, 8), P(5, 11), P(8, 14)])];
    TAtlasToolbarIcon.AlignControls:
      // Linke Kante mit zwei bündigen Balken.
      Result := [Stroke([P(2, 2), P(2, 14)]), Outline([P(5, 4), P(13, 4), P(13, 7), P(5, 7)]),
        Outline([P(5, 9), P(10, 9), P(10, 12), P(5, 12)])];
  else
    Result := nil;
  end;
end;

end.
