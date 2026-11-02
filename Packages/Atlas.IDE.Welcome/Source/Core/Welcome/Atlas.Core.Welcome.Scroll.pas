unit Atlas.Core.Welcome.Scroll;

// Scrollen der Atlas-Willkommensseite (#1440), ohne VCL und Windows: wie weit
// ein Mausrad-Schritt, eine Taste (Bild auf/ab, Pos1/Ende) oder das Ziehen am
// Rand im Bearbeitungsmodus (#767) die Seite bewegt. Die UI-Schicht
// (TAtlasWelcomeBoardFrame) leitet das Mausrad über allen Bereichen an die
// innerste Fläche weiter, die in die Richtung noch scrollen kann, sonst an
// die Seite, und setzt die hier gerechneten Positionen.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Tasten, die die Seite scrollen: Bild auf/ab, Pos1 (Top), Ende (Bottom).</summary>
  TAtlasWelcomeScrollKey = (None, PageUp, PageDown, Top, Bottom);
{$SCOPEDENUMS OFF}

  TAtlasWelcomeScroll = record
  public const
    /// <summary>WHEEL_DELTA: ein Raster des Mausrads.</summary>
    WheelDelta = 120;
    /// <summary>Höhe einer Zeile beim Mausrad in logischen Pixeln (96 dpi).</summary>
    LineHeight = 20;
    /// <summary>Breite des Randstreifens, in dem beim Ziehen gescrollt wird (logische Pixel).</summary>
    EdgeWidth = 32;
    /// <summary>Größter Schritt je Takt beim Scrollen am Rand (logische Pixel).</summary>
    EdgeStep = 24;
  public
    /// <summary>Höchste Position: Inhalt AContent in einer Fläche der Höhe APage; 0, wenn alles passt.</summary>
    class function MaxPosition(AContent, APage: Integer): Integer; static;
    /// <summary>APosition auf 0..AMax begrenzt.</summary>
    class function Clamp(APosition, AMax: Integer): Integer; static;
    /// <summary>Kann eine Fläche an APosition (0..AMax) mit dem Mausrad ADelta (positiv = nach oben) noch
    /// scrollen?</summary>
    class function CanScroll(APosition, AMax, ADelta: Integer): Boolean; static;
    /// <summary>Pixel für ADelta (positiv = nach oben, also negative Pixel): ALines Zeilen je Raster zu je
    /// ALineHeight Pixeln; ALines außerhalb 1..100 (WHEEL_PAGESCROLL) = eine Seite APage je Raster. ARest
    /// sammelt Bruchteile feiner Räder (Touchpad), damit kleine Schritte nicht verloren gehen.</summary>
    class function WheelPixels(var ARest: Integer; ADelta, ALines, ALineHeight, APage: Integer): Integer; static;
    /// <summary>Ganze Zeilen für ADelta (positiv = nach oben, also negativ) bei ALines Zeilen je Raster; ARest wie
    /// bei WheelPixels. Für Listen, die zeilenweise scrollen.</summary>
    class function WheelLines(var ARest: Integer; ADelta, ALines: Integer): Integer; static;
    /// <summary>Neue Position nach AKey: eine Seite APage (abzüglich einer Zeile ALineHeight als Überlappung)
    /// bzw. Anfang/Ende.</summary>
    class function KeyPosition(AKey: TAtlasWelcomeScrollKey; APosition, AMax, APage, ALineHeight: Integer): Integer;
      static;
    /// <summary>Schritt beim Ziehen am Rand: AY ist die Mausposition in einer Fläche der Höhe AHeight; im
    /// Randstreifen AEdge negativ (oben) bzw. positiv (unten), umso größer, je näher am Rand, höchstens AMaxStep;
    /// außerhalb der Fläche AMaxStep. 0 = kein Scrollen.</summary>
    class function EdgeScroll(AY, AHeight, AEdge, AMaxStep: Integer): Integer; static;
  end;

implementation

{ TAtlasWelcomeScroll }

class function TAtlasWelcomeScroll.MaxPosition(AContent, APage: Integer): Integer;
begin
  Result := AContent - APage;
  if Result < 0 then
    Result := 0;
end;

class function TAtlasWelcomeScroll.Clamp(APosition, AMax: Integer): Integer;
begin
  Result := APosition;
  if Result > AMax then
    Result := AMax;
  if Result < 0 then
    Result := 0;
end;

class function TAtlasWelcomeScroll.CanScroll(APosition, AMax, ADelta: Integer): Boolean;
begin
  if ADelta > 0 then
    Result := APosition > 0
  else if ADelta < 0 then
    Result := APosition < AMax
  else
    Result := False;
end;

class function TAtlasWelcomeScroll.WheelPixels(var ARest: Integer; ADelta, ALines, ALineHeight,
  APage: Integer): Integer;
var
  mStep, mTotal: Integer;
begin
  // Richtungswechsel: Rest der alten Richtung verwerfen.
  if ((ARest > 0) and (ADelta < 0)) or ((ARest < 0) and (ADelta > 0)) then
    ARest := 0;
  if (ALines < 1) or (ALines > 100) then
    mStep := APage
  else
    mStep := ALines * ALineHeight;
  if mStep < 1 then
    mStep := 1;
  mTotal := ARest + ADelta;
  // Pixel = Raster × Schritt; ganze Pixel nach außen geben, den Bruchteil behalten.
  Result := -((mTotal * mStep) div WheelDelta);
  ARest := mTotal - ((-Result) * WheelDelta) div mStep;
end;

class function TAtlasWelcomeScroll.WheelLines(var ARest: Integer; ADelta, ALines: Integer): Integer;
var
  mTotal: Integer;
begin
  if ((ARest > 0) and (ADelta < 0)) or ((ARest < 0) and (ADelta > 0)) then
    ARest := 0;
  if (ALines < 1) or (ALines > 100) then
    ALines := 3;
  mTotal := ARest + ADelta;
  Result := -((mTotal * ALines) div WheelDelta);
  ARest := mTotal - ((-Result) * WheelDelta) div ALines;
end;

class function TAtlasWelcomeScroll.KeyPosition(AKey: TAtlasWelcomeScrollKey; APosition, AMax, APage,
  ALineHeight: Integer): Integer;
var
  mStep: Integer;
begin
  mStep := APage - ALineHeight;
  if mStep < ALineHeight then
    mStep := ALineHeight;
  case AKey of
    TAtlasWelcomeScrollKey.PageUp:
      Result := APosition - mStep;
    TAtlasWelcomeScrollKey.PageDown:
      Result := APosition + mStep;
    TAtlasWelcomeScrollKey.Top:
      Result := 0;
    TAtlasWelcomeScrollKey.Bottom:
      Result := AMax;
  else
    Result := APosition;
  end;
  Result := Clamp(Result, AMax);
end;

class function TAtlasWelcomeScroll.EdgeScroll(AY, AHeight, AEdge, AMaxStep: Integer): Integer;
var
  mEdge: Integer;
begin
  Result := 0;
  if (AHeight <= 0) or (AMaxStep <= 0) then
    Exit;
  mEdge := AEdge;
  // Niedrige Fläche: höchstens ein Drittel als Randstreifen, sonst gäbe es keine ruhige Mitte.
  if mEdge > AHeight div 3 then
    mEdge := AHeight div 3;
  if mEdge < 1 then
    Exit;
  if AY < 0 then
    Result := -AMaxStep
  else if AY >= AHeight then
    Result := AMaxStep
  else if AY < mEdge then
    Result := -(1 + ((mEdge - AY) * (AMaxStep - 1)) div mEdge)
  else if AY >= AHeight - mEdge then
    Result := 1 + ((AY - (AHeight - mEdge) + 1) * (AMaxStep - 1)) div mEdge;
end;

end.
