unit Atlas.Core.Designer.IconAlpha;

// Echte Transparenz eines Symbols, das nur auf einen deckenden Grund gemalt werden kann (Palettensymbole der IDE über
// INTAPalettePaintIcon). Dasselbe Symbol einmal auf Schwarz und einmal auf Weiß gemalt: Der Unterschied je Pixel ist
// die Durchsicht, das Bild auf Schwarz die mit der Deckkraft gewichtete Farbe. Vorher wurde auf Magenta gemalt und nur
// reines Magenta ausgeschnitten; halbtransparente Kanten behielten einen Pinkstich.
// Pixel als BGRA in einem Cardinal (Byte 0 Blau, 1 Grün, 2 Rot, 3 Alpha), wie in einer 32-Bit-Bitmap.

interface

type
  TAtlasIconAlpha = class
  public
    /// <summary>Pixel mit Alpha aus ABlack (auf Schwarz gemalt) und AWhite (auf Weiß gemalt), gleich lang; Farbe
    /// nicht vormultipliziert. Bei ungleicher Länge leer.</summary>
    class function Combine(const ABlack, AWhite: TArray<Cardinal>): TArray<Cardinal>; static;
  end;

implementation

const
  /// <summary>Verschiebung der Farbkanäle Blau, Grün, Rot im Pixel.</summary>
  cShifts: array[0..2] of Integer = (0, 8, 16);
  /// <summary>Verschiebung des Alphakanals im Pixel.</summary>
  cAlphaShift = 24;
  /// <summary>Höchstwert eines Kanals (deckend bzw. volle Farbe).</summary>
  cChannelMax = 255;

function Channel(APixel: Cardinal; AShift: Integer): Integer;
begin
  Result := Integer((APixel shr AShift) and $FF);
end;

function Clamp(AValue: Integer): Integer;
begin
  Result := AValue;
  if Result < 0 then
  begin
    Result := 0;
  end
  else if Result > cChannelMax then
  begin
    Result := cChannelMax;
  end;
end;

class function TAtlasIconAlpha.Combine(const ABlack, AWhite: TArray<Cardinal>): TArray<Cardinal>;
var
  i, mShift, mAlpha, mSpread: Integer;
  mPixel: Cardinal;
begin
  Result := nil;
  if Length(ABlack) <> Length(AWhite) then
  begin
    Exit;
  end;
  SetLength(Result, Length(ABlack));
  for i := 0 to High(ABlack) do
  begin
    // Durchsicht = mittlerer Abstand Weiß − Schwarz über die drei Farbkanäle.
    mSpread := 0;
    for mShift in cShifts do
    begin
      mSpread := mSpread + Channel(AWhite[i], mShift) - Channel(ABlack[i], mShift);
    end;
    mAlpha := Clamp(cChannelMax - mSpread div Length(cShifts));
    mPixel := Cardinal(mAlpha) shl cAlphaShift;
    if mAlpha > 0 then
    begin
      for mShift in cShifts do
      begin
        mPixel := mPixel or
          (Cardinal(Clamp((Channel(ABlack[i], mShift) * cChannelMax + mAlpha div 2) div mAlpha)) shl mShift);
      end;
    end;
    Result[i] := mPixel;
  end;
end;

end.
