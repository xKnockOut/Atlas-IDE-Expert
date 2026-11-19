unit Atlas.Core.Style.Color;

// Farbmathematik von Atlas (#411), ohne VCL: Farben im Format von TColor
// ($00BBGGRR), damit die Oberfläche sie direkt verwenden kann. Mischen wie
// eine halbtransparente Fläche, HSL zum Aufhellen und Abdunkeln, relative
// Leuchtdichte und Kontrastverhältnis nach WCAG 2.1, Farbabstand ΔE2000 in
// CIELAB (D65) für die Paarfarben (#653).

interface

uses
  System.SysUtils;

type
  /// <summary>Farbe wie TColor: $00BBGGRR.</summary>
  TAtlasColor = type Cardinal;

  TAtlasHSL = record
    /// <summary>Farbton 0..360.</summary>
    H: Double;
    /// <summary>Sättigung 0..1.</summary>
    S: Double;
    /// <summary>Helligkeit 0..1.</summary>
    L: Double;
    class function FromColor(AColor: TAtlasColor): TAtlasHSL; static;
    function ToColor: TAtlasColor;
  end;

  /// <summary>Farbe in CIELAB (D65).</summary>
  TAtlasLab = record
    L: Double;
    A: Double;
    B: Double;
    class function Create(AL, AA, AB: Double): TAtlasLab; static;
  end;

  TAtlasColorMath = class
  public
    class function Rgb(ARed, AGreen, ABlue: Byte): TAtlasColor; static;
    /// <summary>Aus "#RRGGBB"; EConvertError bei ungültiger Angabe.</summary>
    class function FromHex(const AHex: string): TAtlasColor; static;
    /// <summary>Aus "#RRGGBB"; False (AColor 0) bei ungültiger Angabe, ohne Ausnahme.</summary>
    class function TryFromHex(const AHex: string; out AColor: TAtlasColor): Boolean; static;
    class function ToHex(AColor: TAtlasColor): string; static;
    class function Red(AColor: TAtlasColor): Byte; static;
    class function Green(AColor: TAtlasColor): Byte; static;
    class function Blue(AColor: TAtlasColor): Byte; static;
    /// <summary>AFront mit Deckkraft AAlpha (0..1) über ABack, wie rgba() im Entwurf.</summary>
    class function Mix(AFront, ABack: TAtlasColor; AAlpha: Double): TAtlasColor; static;
    /// <summary>Helligkeit in HSL um AAmount (0..1) erhöhen.</summary>
    class function Lighten(AColor: TAtlasColor; AAmount: Double): TAtlasColor; static;
    class function Darken(AColor: TAtlasColor; AAmount: Double): TAtlasColor; static;
    /// <summary>Relative Leuchtdichte nach WCAG, 0 (schwarz) bis 1 (weiß).</summary>
    class function Luminance(AColor: TAtlasColor): Double; static;
    /// <summary>Kontrastverhältnis nach WCAG, 1 bis 21.</summary>
    class function Contrast(A, B: TAtlasColor): Double; static;
    /// <summary>Dunkle Fläche: Leuchtdichte unter der Mitte zwischen Schwarz und Weiß.</summary>
    class function IsDark(AColor: TAtlasColor): Boolean; static;
    /// <summary>sRGB nach CIELAB (D65).</summary>
    class function ToLab(AColor: TAtlasColor): TAtlasLab; static;
    /// <summary>Farbabstand nach CIEDE2000 (kL = kC = kH = 1).</summary>
    class function DeltaE2000(const A, B: TAtlasLab): Double; overload; static;
    class function DeltaE2000(A, B: TAtlasColor): Double; overload; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit.</summary>
  TColorText = (InvalidColor);

  /// <summary>Anteil eines Farbkanals in einem Sechstel des Farbkreises: volle Chroma, Zwischenwert oder nichts.
  /// </summary>
  THueShare = (Chroma, Between, Nothing);

const
  cTexts: array[TAtlasLanguage, TColorText] of string = (
    ('Ungültige Farbe "%s"'),
    ('Invalid color "%s"'));

  /// <summary>Größter Wert eines Farbkanals.</summary>
  cChannelMax = 255;
  /// <summary>Lage von Grün und Blau in $00BBGGRR (Bits); in "#RRGGBB" liegen Rot und Grün an denselben Stellen.
  /// </summary>
  cSecondByteShift = 8;
  cThirdByteShift = 16;
  /// <summary>"#RRGGBB": Zeichen insgesamt und Hexziffern.</summary>
  cHexColorLength = 7;
  cHexColorDigits = 6;
  /// <summary>Vollkreis und Halbkreis in Grad.</summary>
  cFullCircle = 360;
  cHalfCircle = 180;
  /// <summary>Sechstel des Farbkreises in HSL, je 60 Grad.</summary>
  cHueSectors = 6;
  cHueSectorDegrees = cFullCircle div cHueSectors;
  /// <summary>Beginn der Sektoren mit Grün bzw. Blau als stärkstem Kanal (in Sechsteln).</summary>
  cGreenSectorStart = 2;
  cBlueSectorStart = 4;
  /// <summary>Anteile von Rot, Grün und Blau je Sektor (Rot→Gelb, Gelb→Grün, …, Magenta→Rot).</summary>
  cSectorShares: array[0..cHueSectors - 1, 0..2] of THueShare = (
    (THueShare.Chroma, THueShare.Between, THueShare.Nothing),
    (THueShare.Between, THueShare.Chroma, THueShare.Nothing),
    (THueShare.Nothing, THueShare.Chroma, THueShare.Between),
    (THueShare.Nothing, THueShare.Between, THueShare.Chroma),
    (THueShare.Between, THueShare.Nothing, THueShare.Chroma),
    (THueShare.Chroma, THueShare.Nothing, THueShare.Between));

  /// <summary>Übertragungsfunktion von sRGB (IEC 61966-2-1): Knick, Steigung des linearen Teils, Versatz und
  /// Exponent.</summary>
  cSrgbKnee = 0.04045;
  cSrgbSlope = 12.92;
  cSrgbOffset = 0.055;
  cSrgbGamma = 2.4;
  /// <summary>Anteile von Rot, Grün und Blau an der Leuchtdichte (Rec. 709, auch Y in XYZ).</summary>
  cLumaRed = 0.2126;
  cLumaGreen = 0.7152;
  cLumaBlue = 0.0722;
  /// <summary>Streulicht im Kontrastverhältnis nach WCAG.</summary>
  cContrastFlare = 0.05;
  /// <summary>Leuchtdichte, bei der Schwarz und Weiß gleich gut kontrastieren.</summary>
  cDarkLuminance = 0.18;

  /// <summary>sRGB nach XYZ (D65): Zeilen für X und Z; Y ist die Leuchtdichte.</summary>
  cXyzXRed = 0.4124;
  cXyzXGreen = 0.3576;
  cXyzXBlue = 0.1805;
  cXyzZRed = 0.0193;
  cXyzZGreen = 0.1192;
  cXyzZBlue = 0.9505;
  /// <summary>Weißpunkt D65 (X und Z, Y = 1).</summary>
  cWhiteX = 0.95047;
  cWhiteZ = 1.08883;
  /// <summary>CIELAB: Grenze und Steigung des linearen Teils (CIE-Standard 216/24389 und 24389/27), Versatz und
  /// Maßstab von L*, Maßstäbe von a* und b*, Kubikwurzel.</summary>
  cLabEpsilon = 216 / 24389;
  cLabKappa = 24389 / 27;
  cLabOffset = 16;
  cLabScale = 116;
  cLabScaleA = 500;
  cLabScaleB = 200;
  cCubeRoot = 1 / 3;

  /// <summary>CIEDE2000: Exponent und 25^7 im Ausgleich der Chroma, halber Ausgleich.</summary>
  cDe2000Power = 7;
  cPow25 = 6103515625.0;
  cDe2000HalfG = 0.5;
  /// <summary>CIEDE2000: Gewichte und Winkel des Terms T (Grad).</summary>
  cTWeight1 = 0.17;
  cTAngle1 = 30;
  cTWeight2 = 0.24;
  cTWeight3 = 0.32;
  cTFactor3 = 3;
  cTAngle3 = 6;
  cTWeight4 = 0.20;
  cTFactor4 = 4;
  cTAngle4 = 63;
  /// <summary>CIEDE2000: Drehterm, größter Winkel, Mitte und Breite in Grad.</summary>
  cRotationMax = 30;
  cRotationCenter = 275;
  cRotationWidth = 25;
  /// <summary>CIEDE2000: Gewichte S_L (mit Mitte 50 und Versatz 20), S_C und S_H.</summary>
  cSlWeight = 0.015;
  cSlCenter = 50;
  cSlOffset = 20;
  cScWeight = 0.045;
  cShWeight = 0.015;

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TColorText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

/// <summary>Farbkanal 0..255 linear (ohne die Gammakurve von sRGB), 0..1.</summary>
function LinearChannel(AValue: Byte): Double;
var
  mValue: Double;
begin
  mValue := AValue / cChannelMax;
  if mValue <= cSrgbKnee then
  begin
    Result := mValue / cSrgbSlope;
  end
  else
  begin
    Result := Power((mValue + cSrgbOffset) / (1 + cSrgbOffset), cSrgbGamma);
  end;
end;

/// <summary>Leuchtdichte aus linearen Kanälen.</summary>
function LinearLuminance(ARed, AGreen, ABlue: Double): Double;
begin
  Result := cLumaRed * ARed + cLumaGreen * AGreen + cLumaBlue * ABlue;
end;

{ TAtlasHSL }

class function TAtlasHSL.FromColor(AColor: TAtlasColor): TAtlasHSL;
var
  R, G, B, mMaxValue, mMinValue, mDelta: Double;
begin
  R := TAtlasColorMath.Red(AColor) / cChannelMax;
  G := TAtlasColorMath.Green(AColor) / cChannelMax;
  B := TAtlasColorMath.Blue(AColor) / cChannelMax;
  mMaxValue := Max(R, Max(G, B));
  mMinValue := Min(R, Min(G, B));
  mDelta := mMaxValue - mMinValue;
  Result.L := (mMaxValue + mMinValue) / 2;
  if mDelta = 0 then
  begin
    Result.H := 0;
    Result.S := 0;
    Exit;
  end;
  Result.S := mDelta / (1 - Abs(2 * Result.L - 1));
  if mMaxValue = R then
  begin
    Result.H := cHueSectorDegrees * FMod((G - B) / mDelta, cHueSectors);
  end
  else if mMaxValue = G then
  begin
    Result.H := cHueSectorDegrees * ((B - R) / mDelta + cGreenSectorStart);
  end
  else
  begin
    Result.H := cHueSectorDegrees * ((R - G) / mDelta + cBlueSectorStart);
  end;
  if Result.H < 0 then
  begin
    Result.H := Result.H + cFullCircle;
  end;
end;

function TAtlasHSL.ToColor: TAtlasColor;
var
  C, X, M, mHue: Double;
  mSector: Integer;

  function Channel(AIndex: Integer): Byte;
  var
    mShare: Double;
  begin
    case cSectorShares[mSector, AIndex] of
      THueShare.Chroma:
        mShare := C;
      THueShare.Between:
        mShare := X;
    else
      mShare := 0;
    end;
    Result := Round((mShare + M) * cChannelMax);
  end;

begin
  C := (1 - Abs(2 * EnsureRange(L, 0, 1) - 1)) * EnsureRange(S, 0, 1);
  mHue := FMod(H, cFullCircle);
  if mHue < 0 then
  begin
    mHue := mHue + cFullCircle;
  end;
  X := C * (1 - Abs(FMod(mHue / cHueSectorDegrees, 2) - 1));
  M := EnsureRange(L, 0, 1) - C / 2;
  mSector := EnsureRange(Trunc(mHue / cHueSectorDegrees), 0, cHueSectors - 1);
  Result := TAtlasColorMath.Rgb(Channel(0), Channel(1), Channel(2));
end;

{ TAtlasColorMath }

class function TAtlasColorMath.Rgb(ARed, AGreen, ABlue: Byte): TAtlasColor;
begin
  Result := TAtlasColor(ARed or (AGreen shl cSecondByteShift) or (ABlue shl cThirdByteShift));
end;

class function TAtlasColorMath.FromHex(const AHex: string): TAtlasColor;
begin
  if not TryFromHex(AHex, Result) then
  begin
    raise EConvertError.CreateFmt(UiText(TColorText.InvalidColor), [AHex]);
  end;
end;

class function TAtlasColorMath.TryFromHex(const AHex: string; out AColor: TAtlasColor): Boolean;
var
  mValue: Integer;
begin
  AColor := 0;
  Result := (Length(AHex) = cHexColorLength) and (AHex[1] = '#') and
    TryStrToInt('$' + Copy(AHex, 2, cHexColorDigits), mValue);
  if Result then
  begin
    AColor := Rgb((mValue shr cThirdByteShift) and $FF, (mValue shr cSecondByteShift) and $FF, mValue and $FF);
  end;
end;

class function TAtlasColorMath.ToHex(AColor: TAtlasColor): string;
begin
  Result := Format('#%.2X%.2X%.2X', [Red(AColor), Green(AColor), Blue(AColor)]);
end;

class function TAtlasColorMath.Red(AColor: TAtlasColor): Byte;
begin
  Result := AColor and $FF;
end;

class function TAtlasColorMath.Green(AColor: TAtlasColor): Byte;
begin
  Result := (AColor shr cSecondByteShift) and $FF;
end;

class function TAtlasColorMath.Blue(AColor: TAtlasColor): Byte;
begin
  Result := (AColor shr cThirdByteShift) and $FF;
end;

class function TAtlasColorMath.Mix(AFront, ABack: TAtlasColor; AAlpha: Double): TAtlasColor;

  function Channel(AFrontValue, ABackValue: Byte): Byte;
  begin
    Result := Round(AFrontValue * AAlpha + ABackValue * (1 - AAlpha));
  end;

begin
  AAlpha := EnsureRange(AAlpha, 0, 1);
  Result := Rgb(Channel(Red(AFront), Red(ABack)), Channel(Green(AFront), Green(ABack)),
    Channel(Blue(AFront), Blue(ABack)));
end;

class function TAtlasColorMath.Lighten(AColor: TAtlasColor; AAmount: Double): TAtlasColor;
var
  mHSL: TAtlasHSL;
begin
  mHSL := TAtlasHSL.FromColor(AColor);
  mHSL.L := EnsureRange(mHSL.L + AAmount, 0, 1);
  Result := mHSL.ToColor;
end;

class function TAtlasColorMath.Darken(AColor: TAtlasColor; AAmount: Double): TAtlasColor;
begin
  Result := Lighten(AColor, -AAmount);
end;

class function TAtlasColorMath.Luminance(AColor: TAtlasColor): Double;
begin
  Result := LinearLuminance(LinearChannel(Red(AColor)), LinearChannel(Green(AColor)), LinearChannel(Blue(AColor)));
end;

class function TAtlasColorMath.Contrast(A, B: TAtlasColor): Double;
var
  mLumA, mLumB: Double;
begin
  mLumA := Luminance(A);
  mLumB := Luminance(B);
  Result := (Max(mLumA, mLumB) + cContrastFlare) / (Min(mLumA, mLumB) + cContrastFlare);
end;

{ TAtlasLab }

class function TAtlasLab.Create(AL, AA, AB: Double): TAtlasLab;
begin
  Result.L := AL;
  Result.A := AA;
  Result.B := AB;
end;

class function TAtlasColorMath.IsDark(AColor: TAtlasColor): Boolean;
begin
  Result := Luminance(AColor) < cDarkLuminance;
end;

type
  /// <summary>Chroma C' und Farbton h' (Grad) einer Farbe in CIEDE2000.</summary>
  TPrimedLab = record
    C: Double;
    H: Double;
  end;

  /// <summary>Gewichte S_L, S_C, S_H und Drehterm R_T von CIEDE2000.</summary>
  TDeltaWeights = record
    Sl: Double;
    Sc: Double;
    Sh: Double;
    Rt: Double;
  end;

function HueAngle(AB, AA: Double): Double;
begin
  Result := 0;
  if (AA <> 0) or (AB <> 0) then
  begin
    Result := RadToDeg(ArcTan2(AB, AA));
    if Result < 0 then
    begin
      Result := Result + cFullCircle;
    end;
  end;
end;

/// <summary>Ausgleich der Chroma in CIEDE2000: sqrt(C^7 / (C^7 + 25^7)).</summary>
function ChromaBalance(AChroma: Double): Double;
begin
  Result := Sqrt(Power(AChroma, cDe2000Power) / (Power(AChroma, cDe2000Power) + cPow25));
end;

/// <summary>C' und h' von AColor; der Faktor G hängt von beiden Farben (AFirst, ASecond) ab.</summary>
function PrimedLab(const AColor, AFirst, ASecond: TAtlasLab): TPrimedLab;
var
  mCMean, mG, mA: Double;
begin
  mCMean := (Sqrt(Sqr(AFirst.A) + Sqr(AFirst.B)) + Sqrt(Sqr(ASecond.A) + Sqr(ASecond.B))) / 2;
  mG := cDe2000HalfG * (1 - ChromaBalance(mCMean));
  mA := (1 + mG) * AColor.A;
  Result.C := Sqrt(Sqr(mA) + Sqr(AColor.B));
  Result.H := HueAngle(AColor.B, mA);
end;

function HueDelta(const AFirst, ASecond: TPrimedLab): Double;
begin
  Result := 0;
  if AFirst.C * ASecond.C <> 0 then
  begin
    Result := ASecond.H - AFirst.H;
    if Result > cHalfCircle then
    begin
      Result := Result - cFullCircle;
    end
    else if Result < -cHalfCircle then
    begin
      Result := Result + cFullCircle;
    end;
  end;
end;

function MeanHue(const AFirst, ASecond: TPrimedLab): Double;
begin
  if AFirst.C * ASecond.C = 0 then
  begin
    Result := AFirst.H + ASecond.H;
  end
  else if Abs(AFirst.H - ASecond.H) <= cHalfCircle then
  begin
    Result := (AFirst.H + ASecond.H) / 2;
  end
  else if AFirst.H + ASecond.H < cFullCircle then
  begin
    Result := (AFirst.H + ASecond.H + cFullCircle) / 2;
  end
  else
  begin
    Result := (AFirst.H + ASecond.H - cFullCircle) / 2;
  end;
end;

function DeltaWeights(ALMean, ACpMean, AHpMean: Double): TDeltaWeights;
var
  mT, mDTheta: Double;
begin
  mT := 1 - cTWeight1 * Cos(DegToRad(AHpMean - cTAngle1)) + cTWeight2 * Cos(DegToRad(2 * AHpMean)) +
    cTWeight3 * Cos(DegToRad(cTFactor3 * AHpMean + cTAngle3)) -
    cTWeight4 * Cos(DegToRad(cTFactor4 * AHpMean - cTAngle4));
  mDTheta := cRotationMax * Exp(-Sqr((AHpMean - cRotationCenter) / cRotationWidth));
  Result.Sl := 1 + cSlWeight * Sqr(ALMean - cSlCenter) / Sqrt(cSlOffset + Sqr(ALMean - cSlCenter));
  Result.Sc := 1 + cScWeight * ACpMean;
  Result.Sh := 1 + cShWeight * ACpMean * mT;
  Result.Rt := -Sin(DegToRad(2 * mDTheta)) * 2 * ChromaBalance(ACpMean);
end;

class function TAtlasColorMath.ToLab(AColor: TAtlasColor): TAtlasLab;

  function F(AValue: Double): Double;
  begin
    if AValue > cLabEpsilon then
    begin
      Result := Power(AValue, cCubeRoot);
    end
    else
    begin
      Result := (cLabKappa * AValue + cLabOffset) / cLabScale;
    end;
  end;

var
  R, G, B, X, Y, Z: Double;
begin
  R := LinearChannel(Red(AColor));
  G := LinearChannel(Green(AColor));
  B := LinearChannel(Blue(AColor));
  X := F((cXyzXRed * R + cXyzXGreen * G + cXyzXBlue * B) / cWhiteX);
  Y := F(LinearLuminance(R, G, B));
  Z := F((cXyzZRed * R + cXyzZGreen * G + cXyzZBlue * B) / cWhiteZ);
  Result := TAtlasLab.Create(cLabScale * Y - cLabOffset, cLabScaleA * (X - Y), cLabScaleB * (Y - Z));
end;

class function TAtlasColorMath.DeltaE2000(const A, B: TAtlasLab): Double;
var
  mFirst, mSecond: TPrimedLab;
  mDHp, mDCp: Double;
  mWeights: TDeltaWeights;
begin
  mFirst := PrimedLab(A, A, B);
  mSecond := PrimedLab(B, A, B);
  mDCp := mSecond.C - mFirst.C;
  mDHp := 2 * Sqrt(mFirst.C * mSecond.C) * Sin(DegToRad(HueDelta(mFirst, mSecond) / 2));
  mWeights := DeltaWeights((A.L + B.L) / 2, (mFirst.C + mSecond.C) / 2, MeanHue(mFirst, mSecond));
  Result := Sqrt(Sqr((B.L - A.L) / mWeights.Sl) + Sqr(mDCp / mWeights.Sc) + Sqr(mDHp / mWeights.Sh) +
    mWeights.Rt * (mDCp / mWeights.Sc) * (mDHp / mWeights.Sh));
end;

class function TAtlasColorMath.DeltaE2000(A, B: TAtlasColor): Double;
begin
  Result := DeltaE2000(ToLab(A), ToLab(B));
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Style.Color', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
