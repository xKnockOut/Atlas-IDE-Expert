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
  System.Math;

{ TAtlasHSL }

class function TAtlasHSL.FromColor(AColor: TAtlasColor): TAtlasHSL;
var
  R, G, B, MaxValue, MinValue, Delta: Double;
begin
  R := TAtlasColorMath.Red(AColor) / 255;
  G := TAtlasColorMath.Green(AColor) / 255;
  B := TAtlasColorMath.Blue(AColor) / 255;
  MaxValue := Max(R, Max(G, B));
  MinValue := Min(R, Min(G, B));
  Delta := MaxValue - MinValue;
  Result.L := (MaxValue + MinValue) / 2;
  if Delta = 0 then
  begin
    Result.H := 0;
    Result.S := 0;
    Exit;
  end;
  Result.S := Delta / (1 - Abs(2 * Result.L - 1));
  if MaxValue = R then
    Result.H := 60 * FMod((G - B) / Delta, 6)
  else if MaxValue = G then
    Result.H := 60 * ((B - R) / Delta + 2)
  else
    Result.H := 60 * ((R - G) / Delta + 4);
  if Result.H < 0 then
    Result.H := Result.H + 360;
end;

function TAtlasHSL.ToColor: TAtlasColor;
var
  C, X, M, R, G, B, Hue: Double;
begin
  C := (1 - Abs(2 * EnsureRange(L, 0, 1) - 1)) * EnsureRange(S, 0, 1);
  Hue := FMod(H, 360);
  if Hue < 0 then
    Hue := Hue + 360;
  X := C * (1 - Abs(FMod(Hue / 60, 2) - 1));
  M := EnsureRange(L, 0, 1) - C / 2;
  case Trunc(Hue / 60) of
    0: begin R := C; G := X; B := 0; end;
    1: begin R := X; G := C; B := 0; end;
    2: begin R := 0; G := C; B := X; end;
    3: begin R := 0; G := X; B := C; end;
    4: begin R := X; G := 0; B := C; end;
  else
    R := C; G := 0; B := X;
  end;
  Result := TAtlasColorMath.Rgb(Round((R + M) * 255), Round((G + M) * 255), Round((B + M) * 255));
end;

{ TAtlasColorMath }

class function TAtlasColorMath.Rgb(ARed, AGreen, ABlue: Byte): TAtlasColor;
begin
  Result := TAtlasColor(ARed or (AGreen shl 8) or (ABlue shl 16));
end;

class function TAtlasColorMath.FromHex(const AHex: string): TAtlasColor;
var
  Value: Integer;
begin
  if (Length(AHex) <> 7) or (AHex[1] <> '#') or not TryStrToInt('$' + Copy(AHex, 2, 6), Value) then
    raise EConvertError.CreateFmt('Ungültige Farbe "%s"', [AHex]);
  Result := Rgb((Value shr 16) and $FF, (Value shr 8) and $FF, Value and $FF);
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
  Result := (AColor shr 8) and $FF;
end;

class function TAtlasColorMath.Blue(AColor: TAtlasColor): Byte;
begin
  Result := (AColor shr 16) and $FF;
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
  HSL: TAtlasHSL;
begin
  HSL := TAtlasHSL.FromColor(AColor);
  HSL.L := EnsureRange(HSL.L + AAmount, 0, 1);
  Result := HSL.ToColor;
end;

class function TAtlasColorMath.Darken(AColor: TAtlasColor; AAmount: Double): TAtlasColor;
begin
  Result := Lighten(AColor, -AAmount);
end;

class function TAtlasColorMath.Luminance(AColor: TAtlasColor): Double;

  function Linear(AValue: Byte): Double;
  var
    Value: Double;
  begin
    Value := AValue / 255;
    if Value <= 0.04045 then
      Result := Value / 12.92
    else
      Result := Power((Value + 0.055) / 1.055, 2.4);
  end;

begin
  Result := 0.2126 * Linear(Red(AColor)) + 0.7152 * Linear(Green(AColor)) + 0.0722 * Linear(Blue(AColor));
end;

class function TAtlasColorMath.Contrast(A, B: TAtlasColor): Double;
var
  LumA, LumB: Double;
begin
  LumA := Luminance(A);
  LumB := Luminance(B);
  Result := (Max(LumA, LumB) + 0.05) / (Min(LumA, LumB) + 0.05);
end;

class function TAtlasLab.Create(AL, AA, AB: Double): TAtlasLab;
begin
  Result.L := AL;
  Result.A := AA;
  Result.B := AB;
end;

class function TAtlasColorMath.ToLab(AColor: TAtlasColor): TAtlasLab;

  function Linear(AValue: Byte): Double;
  var
    Value: Double;
  begin
    Value := AValue / 255;
    if Value <= 0.04045 then
      Result := Value / 12.92
    else
      Result := Power((Value + 0.055) / 1.055, 2.4);
  end;

  function F(AValue: Double): Double;
  begin
    if AValue > 216 / 24389 then
      Result := Power(AValue, 1 / 3)
    else
      Result := (24389 / 27 * AValue + 16) / 116;
  end;

var
  R, G, B, X, Y, Z: Double;
begin
  R := Linear(Red(AColor));
  G := Linear(Green(AColor));
  B := Linear(Blue(AColor));
  X := F((0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047);
  Y := F(0.2126 * R + 0.7152 * G + 0.0722 * B);
  Z := F((0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883);
  Result := TAtlasLab.Create(116 * Y - 16, 500 * (X - Y), 200 * (Y - Z));
end;

class function TAtlasColorMath.DeltaE2000(const A, B: TAtlasLab): Double;
const
  Pow25 = 6103515625.0; // 25^7
var
  C1, C2, CMean, G, A1, A2, C1p, C2p, H1p, H2p, DLp, DCp, DHp, DeltaHue, LMean, CpMean, HpMean, T, DTheta, Rc,
    Sl, Sc, Sh, Rt: Double;

  function Hue(AB, AA: Double): Double;
  begin
    if (AA = 0) and (AB = 0) then
      Exit(0);
    Result := RadToDeg(ArcTan2(AB, AA));
    if Result < 0 then
      Result := Result + 360;
  end;

begin
  C1 := Sqrt(Sqr(A.A) + Sqr(A.B));
  C2 := Sqrt(Sqr(B.A) + Sqr(B.B));
  CMean := (C1 + C2) / 2;
  G := 0.5 * (1 - Sqrt(Power(CMean, 7) / (Power(CMean, 7) + Pow25)));
  A1 := (1 + G) * A.A;
  A2 := (1 + G) * B.A;
  C1p := Sqrt(Sqr(A1) + Sqr(A.B));
  C2p := Sqrt(Sqr(A2) + Sqr(B.B));
  H1p := Hue(A.B, A1);
  H2p := Hue(B.B, A2);
  DLp := B.L - A.L;
  DCp := C2p - C1p;
  DeltaHue := 0;
  if C1p * C2p <> 0 then
  begin
    DeltaHue := H2p - H1p;
    if DeltaHue > 180 then
      DeltaHue := DeltaHue - 360
    else if DeltaHue < -180 then
      DeltaHue := DeltaHue + 360;
  end;
  DHp := 2 * Sqrt(C1p * C2p) * Sin(DegToRad(DeltaHue / 2));
  LMean := (A.L + B.L) / 2;
  CpMean := (C1p + C2p) / 2;
  if C1p * C2p = 0 then
    HpMean := H1p + H2p
  else if Abs(H1p - H2p) <= 180 then
    HpMean := (H1p + H2p) / 2
  else if H1p + H2p < 360 then
    HpMean := (H1p + H2p + 360) / 2
  else
    HpMean := (H1p + H2p - 360) / 2;
  T := 1 - 0.17 * Cos(DegToRad(HpMean - 30)) + 0.24 * Cos(DegToRad(2 * HpMean)) +
    0.32 * Cos(DegToRad(3 * HpMean + 6)) - 0.20 * Cos(DegToRad(4 * HpMean - 63));
  DTheta := 30 * Exp(-Sqr((HpMean - 275) / 25));
  Rc := 2 * Sqrt(Power(CpMean, 7) / (Power(CpMean, 7) + Pow25));
  Sl := 1 + 0.015 * Sqr(LMean - 50) / Sqrt(20 + Sqr(LMean - 50));
  Sc := 1 + 0.045 * CpMean;
  Sh := 1 + 0.015 * CpMean * T;
  Rt := -Sin(DegToRad(2 * DTheta)) * Rc;
  Result := Sqrt(Sqr(DLp / Sl) + Sqr(DCp / Sc) + Sqr(DHp / Sh) + Rt * (DCp / Sc) * (DHp / Sh));
end;

class function TAtlasColorMath.DeltaE2000(A, B: TAtlasColor): Double;
begin
  Result := DeltaE2000(ToLab(A), ToLab(B));
end;

class function TAtlasColorMath.IsDark(AColor: TAtlasColor): Boolean;
begin
  // 0,18 ist die Leuchtdichte, bei der Schwarz und Weiß gleich gut kontrastieren.
  Result := Luminance(AColor) < 0.18;
end;

end.
