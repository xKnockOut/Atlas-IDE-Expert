unit Argus.Core.Style.Color;

// Farbmathematik von Argus (#411), ohne VCL: Farben im Format von TColor
// ($00BBGGRR), damit die Oberfläche sie direkt verwenden kann. Mischen wie
// eine halbtransparente Fläche, HSL zum Aufhellen und Abdunkeln, relative
// Leuchtdichte und Kontrastverhältnis nach WCAG 2.1.

interface

uses
  System.SysUtils;

type
  /// <summary>Farbe wie TColor: $00BBGGRR.</summary>
  TArgusColor = type Cardinal;

  TArgusHSL = record
    /// <summary>Farbton 0..360.</summary>
    H: Double;
    /// <summary>Sättigung 0..1.</summary>
    S: Double;
    /// <summary>Helligkeit 0..1.</summary>
    L: Double;
    class function FromColor(AColor: TArgusColor): TArgusHSL; static;
    function ToColor: TArgusColor;
  end;

  TArgusColorMath = class
  public
    class function Rgb(ARed, AGreen, ABlue: Byte): TArgusColor; static;
    /// <summary>Aus "#RRGGBB"; EConvertError bei ungültiger Angabe.</summary>
    class function FromHex(const AHex: string): TArgusColor; static;
    class function ToHex(AColor: TArgusColor): string; static;
    class function Red(AColor: TArgusColor): Byte; static;
    class function Green(AColor: TArgusColor): Byte; static;
    class function Blue(AColor: TArgusColor): Byte; static;
    /// <summary>AFront mit Deckkraft AAlpha (0..1) über ABack, wie rgba() im Entwurf.</summary>
    class function Mix(AFront, ABack: TArgusColor; AAlpha: Double): TArgusColor; static;
    /// <summary>Helligkeit in HSL um AAmount (0..1) erhöhen.</summary>
    class function Lighten(AColor: TArgusColor; AAmount: Double): TArgusColor; static;
    class function Darken(AColor: TArgusColor; AAmount: Double): TArgusColor; static;
    /// <summary>Relative Leuchtdichte nach WCAG, 0 (schwarz) bis 1 (weiß).</summary>
    class function Luminance(AColor: TArgusColor): Double; static;
    /// <summary>Kontrastverhältnis nach WCAG, 1 bis 21.</summary>
    class function Contrast(A, B: TArgusColor): Double; static;
    /// <summary>Dunkle Fläche: Leuchtdichte unter der Mitte zwischen Schwarz und Weiß.</summary>
    class function IsDark(AColor: TArgusColor): Boolean; static;
  end;

implementation

uses
  System.Math;

{ TArgusHSL }

class function TArgusHSL.FromColor(AColor: TArgusColor): TArgusHSL;
var
  R, G, B, MaxValue, MinValue, Delta: Double;
begin
  R := TArgusColorMath.Red(AColor) / 255;
  G := TArgusColorMath.Green(AColor) / 255;
  B := TArgusColorMath.Blue(AColor) / 255;
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

function TArgusHSL.ToColor: TArgusColor;
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
  Result := TArgusColorMath.Rgb(Round((R + M) * 255), Round((G + M) * 255), Round((B + M) * 255));
end;

{ TArgusColorMath }

class function TArgusColorMath.Rgb(ARed, AGreen, ABlue: Byte): TArgusColor;
begin
  Result := TArgusColor(ARed or (AGreen shl 8) or (ABlue shl 16));
end;

class function TArgusColorMath.FromHex(const AHex: string): TArgusColor;
var
  Value: Integer;
begin
  if (Length(AHex) <> 7) or (AHex[1] <> '#') or not TryStrToInt('$' + Copy(AHex, 2, 6), Value) then
    raise EConvertError.CreateFmt('Ungültige Farbe "%s"', [AHex]);
  Result := Rgb((Value shr 16) and $FF, (Value shr 8) and $FF, Value and $FF);
end;

class function TArgusColorMath.ToHex(AColor: TArgusColor): string;
begin
  Result := Format('#%.2X%.2X%.2X', [Red(AColor), Green(AColor), Blue(AColor)]);
end;

class function TArgusColorMath.Red(AColor: TArgusColor): Byte;
begin
  Result := AColor and $FF;
end;

class function TArgusColorMath.Green(AColor: TArgusColor): Byte;
begin
  Result := (AColor shr 8) and $FF;
end;

class function TArgusColorMath.Blue(AColor: TArgusColor): Byte;
begin
  Result := (AColor shr 16) and $FF;
end;

class function TArgusColorMath.Mix(AFront, ABack: TArgusColor; AAlpha: Double): TArgusColor;

  function Channel(AFrontValue, ABackValue: Byte): Byte;
  begin
    Result := Round(AFrontValue * AAlpha + ABackValue * (1 - AAlpha));
  end;

begin
  AAlpha := EnsureRange(AAlpha, 0, 1);
  Result := Rgb(Channel(Red(AFront), Red(ABack)), Channel(Green(AFront), Green(ABack)),
    Channel(Blue(AFront), Blue(ABack)));
end;

class function TArgusColorMath.Lighten(AColor: TArgusColor; AAmount: Double): TArgusColor;
var
  HSL: TArgusHSL;
begin
  HSL := TArgusHSL.FromColor(AColor);
  HSL.L := EnsureRange(HSL.L + AAmount, 0, 1);
  Result := HSL.ToColor;
end;

class function TArgusColorMath.Darken(AColor: TArgusColor; AAmount: Double): TArgusColor;
begin
  Result := Lighten(AColor, -AAmount);
end;

class function TArgusColorMath.Luminance(AColor: TArgusColor): Double;

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

class function TArgusColorMath.Contrast(A, B: TArgusColor): Double;
var
  LumA, LumB: Double;
begin
  LumA := Luminance(A);
  LumB := Luminance(B);
  Result := (Max(LumA, LumB) + 0.05) / (Min(LumA, LumB) + 0.05);
end;

class function TArgusColorMath.IsDark(AColor: TArgusColor): Boolean;
begin
  // 0,18 ist die Leuchtdichte, bei der Schwarz und Weiß gleich gut kontrastieren.
  Result := Luminance(AColor) < 0.18;
end;

end.
