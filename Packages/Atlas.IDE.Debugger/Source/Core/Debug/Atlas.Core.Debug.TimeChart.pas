unit Atlas.Core.Debug.TimeChart;

// Abbildung für Liniendiagramme über der Zeit (Speicherverlauf #858,
// Werteverlauf aus Logpunkten #2552), ohne VCL: Zeit seit Sitzungsbeginn
// (ms) und Wert auf Pixel der Zeichenfläche und zurück, glatte Grenzen der
// Wertachse in 1-2-5-Schritten (auch unter 1 und unter 0). Gezeichnet wird
// in Atlas.UI.Debug.TimeChart.

interface

type
  /// <summary>Abbildung zwischen Zeit bzw. Wert und Pixeln der Zeichenfläche.</summary>
  TAtlasTimeChartScale = record
    FromMs: Int64;
    ToMs: Int64;
    MinValue: Double;
    MaxValue: Double;
    Width: Integer;
    Height: Integer;
    /// <summary>Zeitraum AFromMs bis AToMs, Werte AMinValue bis AMaxValue; leere Spannen werden auf 1 erweitert.
    /// </summary>
    class function Make(AFromMs, AToMs: Int64; AMinValue, AMaxValue: Double; AWidth, AHeight: Integer):
      TAtlasTimeChartScale; static;
    /// <summary>Glatte Obergrenze ab AValue: 1, 2 oder 5 mal einer Zehnerpotenz (0,5 und 0,2 unter 1); 1 für Werte
    /// bis 0.</summary>
    class function NiceMax(AValue: Double): Double; static;
    /// <summary>Glatte Grenzen um AMin bis AMax: 0 bleibt Untergrenze, solange kein Wert negativ ist; negative
    /// Untergrenzen glatt nach unten.</summary>
    class procedure NiceRange(AMin, AMax: Double; out ALow, AHigh: Double); static;
    function XOf(AAtMs: Int64): Integer;
    function YOf(AValue: Double): Integer;
    function AtOf(AX: Integer): Int64;
    /// <summary>Wert des Teilstrichs ATick von ATicks (0 = Untergrenze).</summary>
    function TickValue(ATick, ATicks: Integer): Double;
  end;

implementation

uses
  System.Math;

const
  cSteps: array[0..2] of Double = (1, 2, 5);
  /// <summary>Kleinster Wert mit eigener Grenze (darunter gilt der Wert als 0).</summary>
  cMinPower = 1E-9;

{ TAtlasTimeChartScale }

class function TAtlasTimeChartScale.Make(AFromMs, AToMs: Int64; AMinValue, AMaxValue: Double; AWidth,
  AHeight: Integer): TAtlasTimeChartScale;
begin
  Result.FromMs := AFromMs;
  Result.ToMs := Max(AToMs, AFromMs + 1);
  Result.MinValue := AMinValue;
  Result.MaxValue := AMaxValue;
  if Result.MaxValue <= Result.MinValue then
  begin
    Result.MaxValue := Result.MinValue + 1;
  end;
  Result.Width := Max(AWidth, 1);
  Result.Height := Max(AHeight, 1);
end;

class function TAtlasTimeChartScale.NiceMax(AValue: Double): Double;
var
  mPower: Double;
  mStep: Double;
begin
  if AValue <= cMinPower then
  begin
    Exit(1);
  end;
  // Zehnerpotenz unter dem Wert; liegt sie wegen Rundung eine Stufe tiefer, findet die Schleife die nächste.
  mPower := Power(10, Floor(Log10(AValue)));
  while True do
  begin
    for mStep in cSteps do
    begin
      if mStep * mPower >= AValue * (1 - 1E-12) then
      begin
        Exit(mStep * mPower);
      end;
    end;
    mPower := mPower * 10;
  end;
end;

class procedure TAtlasTimeChartScale.NiceRange(AMin, AMax: Double; out ALow, AHigh: Double);
begin
  ALow := 0;
  if AMin < 0 then
  begin
    ALow := -NiceMax(-AMin);
  end;
  AHigh := 0;
  if AMax > 0 then
  begin
    AHigh := NiceMax(AMax);
  end;
  if AHigh <= ALow then
  begin
    AHigh := ALow + 1;
  end;
end;

function TAtlasTimeChartScale.XOf(AAtMs: Int64): Integer;
begin
  Result := Round((AAtMs - FromMs) / (ToMs - FromMs) * (Width - 1));
end;

function TAtlasTimeChartScale.YOf(AValue: Double): Integer;
begin
  Result := (Height - 1) - Round((EnsureRange(AValue, MinValue, MaxValue) - MinValue) / (MaxValue - MinValue) *
    (Height - 1));
end;

function TAtlasTimeChartScale.AtOf(AX: Integer): Int64;
begin
  Result := FromMs + Round(EnsureRange(AX, 0, Width - 1) / Max(Width - 1, 1) * (ToMs - FromMs));
end;

function TAtlasTimeChartScale.TickValue(ATick, ATicks: Integer): Double;
begin
  Result := MinValue + (MaxValue - MinValue) * ATick / Max(ATicks, 1);
end;

end.
