unit Atlas.Core.Designer.Magnifier;

// Lupe für den Designer (#743), ohne VCL und Windows:
// - ToDesign rechnet Bildschirmpixel über die aktuelle Skalierung in Pixel
//   der DFM um (PixelsPerInch des Formulars).
// - Stufen 2×, 4× und 8×: NormalizeZoom, NextZoom (Mausrad).
// - SourceRect: Bildschirmausschnitt für eine Ansicht der Größe AView um
//   einen Mittelpunkt; ToView bildet Bildschirmkoordinaten in die Ansicht ab
//   (Kanten der Auswahl einzeichnen).
// - Farben: HexOf (#RRGGBB) und StandardName (VCL-Name der festen Farben
//   wie clWhite); NamesOf sucht in einer Liste (Systemfarben, die die IDE zur
//   Laufzeit ermittelt). Farben hier immer als $RRGGBB.

interface

uses
  System.Types;

type
  /// <summary>Name und Wert ($RRGGBB) einer Farbe.</summary>
  TAtlasNamedColor = record
    Name: string;
    Rgb: Cardinal;
    class function Create(const AName: string; ARgb: Cardinal): TAtlasNamedColor; static;
  end;

  TAtlasMagnifier = class
  public const
    cMinZoom = 2;
    cMaxZoom = 8;
    cDefaultZoom = 4;
    /// <summary>Ab dieser Stufe gibt es ein Pixelraster.</summary>
    cGridZoom = 4;
  public
    /// <summary>Bildschirmpixel in Pixel der DFM: AValue × ADesignPpi / ACurrentPpi, gerundet.</summary>
    class function ToDesign(AValue, ACurrentPpi, ADesignPpi: Integer): Integer; static;
    /// <summary>Stufe 2, 4 oder 8; anderes wird auf die nächste gültige gesetzt.</summary>
    class function NormalizeZoom(AZoom: Integer): Integer; static;
    /// <summary>Nächste Stufe: ADelta positiv größer, negativ kleiner, an den Enden bleibt sie.</summary>
    class function NextZoom(AZoom, ADelta: Integer): Integer; static;
    /// <summary>Bildschirmausschnitt, den eine Ansicht der Größe AView in Stufe AZoom um ACenter zeigt;
    /// ACenter liegt im Pixel in der Mitte der Ansicht.</summary>
    class function SourceRect(const ACenter: TPoint; const AView: TSize; AZoom: Integer): TRect; static;
    /// <summary>Bildschirmkoordinate in die Ansicht (linke bzw. obere Kante des Pixels).</summary>
    class function ToView(AValue, ASourceOrigin, AZoom: Integer): Integer; static;
    class function HexOf(ARgb: Cardinal): string; static;
    /// <summary>VCL-Name einer festen Farbe (clWhite, clMoneyGreen …); leer ohne.</summary>
    class function StandardName(ARgb: Cardinal): string; static;
    /// <summary>Namen aller Einträge mit diesem Wert, in der Reihenfolge der Liste.</summary>
    class function NamesOf(ARgb: Cardinal; const AColors: TArray<TAtlasNamedColor>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  cStandardNames: array[0..19] of string = ('clBlack', 'clMaroon', 'clGreen', 'clOlive', 'clNavy', 'clPurple',
    'clTeal', 'clGray', 'clSilver', 'clRed', 'clLime', 'clYellow', 'clBlue', 'clFuchsia', 'clAqua', 'clWhite',
    'clMoneyGreen', 'clSkyBlue', 'clCream', 'clMedGray');
  cStandardRgb: array[0..19] of Cardinal = ($000000, $800000, $008000, $808000, $000080, $800080, $008080, $808080,
    $C0C0C0, $FF0000, $00FF00, $FFFF00, $0000FF, $FF00FF, $00FFFF, $FFFFFF, $C0DCC0, $A6CAF0, $FFFBF0, $A0A0A4);

{ TAtlasNamedColor }

class function TAtlasNamedColor.Create(const AName: string; ARgb: Cardinal): TAtlasNamedColor;
begin
  Result.Name := AName;
  Result.Rgb := ARgb;
end;

{ TAtlasMagnifier }

class function TAtlasMagnifier.ToDesign(AValue, ACurrentPpi, ADesignPpi: Integer): Integer;
var
  mScaled: Int64;
begin
  if (ACurrentPpi <= 0) or (ADesignPpi <= 0) or (ACurrentPpi = ADesignPpi) then
  begin
    Exit(AValue);
  end;
  // Kaufmännisch runden, auch für negative Werte (links bzw. über dem Formular).
  mScaled := Int64(Abs(AValue)) * ADesignPpi * 2 + ACurrentPpi;
  Result := Integer(mScaled div (Int64(ACurrentPpi) * 2));
  if AValue < 0 then
  begin
    Result := -Result;
  end;
end;

class function TAtlasMagnifier.NormalizeZoom(AZoom: Integer): Integer;
begin
  if AZoom <= 2 then
  begin
    Result := 2;
  end
  else if AZoom < 6 then
  begin
    Result := 4;
  end
  else
  begin
    Result := 8;
  end;
end;

class function TAtlasMagnifier.NextZoom(AZoom, ADelta: Integer): Integer;
begin
  Result := NormalizeZoom(AZoom);
  if ADelta > 0 then
  begin
    Result := Min(Result * 2, cMaxZoom);
  end
  else if ADelta < 0 then
  begin
    Result := Max(Result div 2, cMinZoom);
  end;
end;

class function TAtlasMagnifier.SourceRect(const ACenter: TPoint; const AView: TSize; AZoom: Integer): TRect;
var
  mZoom, mWidth, mHeight: Integer;
begin
  mZoom := Max(AZoom, 1);
  // Aufrunden, damit die Ansicht bis zum Rand gefüllt ist.
  mWidth := Max((AView.cx + mZoom - 1) div mZoom, 1);
  mHeight := Max((AView.cy + mZoom - 1) div mZoom, 1);
  Result := Rect(ACenter.X - mWidth div 2, ACenter.Y - mHeight div 2, 0, 0);
  Result.Right := Result.Left + mWidth;
  Result.Bottom := Result.Top + mHeight;
end;

class function TAtlasMagnifier.ToView(AValue, ASourceOrigin, AZoom: Integer): Integer;
begin
  Result := (AValue - ASourceOrigin) * AZoom;
end;

class function TAtlasMagnifier.HexOf(ARgb: Cardinal): string;
begin
  Result := '#' + IntToHex(ARgb and $FFFFFF, 6);
end;

class function TAtlasMagnifier.StandardName(ARgb: Cardinal): string;
var
  mIndex: Integer;
begin
  for mIndex := Low(cStandardRgb) to High(cStandardRgb) do
  begin
    if cStandardRgb[mIndex] = (ARgb and $FFFFFF) then
    begin
      Exit(cStandardNames[mIndex]);
    end;
  end;
  Result := '';
end;

class function TAtlasMagnifier.NamesOf(ARgb: Cardinal; const AColors: TArray<TAtlasNamedColor>): TArray<string>;
var
  mColor: TAtlasNamedColor;
begin
  Result := nil;
  for mColor in AColors do
  begin
    if (mColor.Rgb and $FFFFFF) = (ARgb and $FFFFFF) then
    begin
      Result := Result + [mColor.Name];
    end;
  end;
end;

end.
