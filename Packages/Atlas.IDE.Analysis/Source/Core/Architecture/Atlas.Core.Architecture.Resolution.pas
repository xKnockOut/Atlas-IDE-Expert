unit Atlas.Core.Architecture.Resolution;

// Feinheit der Teilsysteme im Fenster „Atlas-Architektur“ (#1366), ohne VCL und OTA: TAtlasArchResolution rechnet
// zwischen Reglerstellung (logarithmisch über 0,2–5,0, Mitte = 1,0) und Wert, TAtlasArchitectureGroupingSettings
// liest und schreibt architecture.grouping in settings.json. Den Wert der Antwort liest
// Atlas.Core.Architecture.Model.

interface

uses
  System.SysUtils;

type
  /// <summary>Regler „Feinheit“ (#1366): Stellung 0..Steps, logarithmisch über 0,2–5,0, Mitte = 1,0.</summary>
  TAtlasArchResolution = class
  public const
    cMinValue = 0.2;
    cMaxValue = 5.0;
    cSteps = 100;
  public
    /// <summary>Wert zur Stellung, auf zwei Nachkommastellen gerundet.</summary>
    class function ValueAt(APosition: Integer): Double; static;
    /// <summary>Nächste Stellung zum Wert (Werte außerhalb werden begrenzt).</summary>
    class function PositionOf(AValue: Double): Integer; static;
    /// <summary>Wert in den Grenzen; ungültig (≤ 0, NaN) = 1.</summary>
    class function Clamp(AValue: Double): Double; static;
    /// <summary>"1,0" bzw. "1.0" nach AFormat, höchstens zwei Nachkommastellen.</summary>
    class function Text(AValue: Double; const AFormat: TFormatSettings): string; static;
    /// <summary>Gleich auf zwei Nachkommastellen.</summary>
    class function Same(ALeft, ARight: Double): Boolean; static;
  end;

  /// <summary>architecture.grouping in settings.json (#1366): der Server liest denselben Wert.</summary>
  TAtlasArchitectureGroupingSettings = class
  public const
    cResolutionPath = 'architecture.grouping.resolution';
    cSliderPath = 'architecture.grouping.showResolutionSlider';
  public
    /// <summary>Werte aus dem Text von settings.json; fehlende oder ungültige: 1 bzw. True.</summary>
    class procedure Read(const AGlobalText: string; out AResolution: Double; out AShowSlider: Boolean); static;
    /// <summary>Text von settings.json mit neuer Feinheit; übriger Text bleibt.</summary>
    class function WithResolution(const AGlobalText: string; AValue: Double): string; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Atlas.Core.Settings.JsonText;

{ TAtlasArchResolution }

class function TAtlasArchResolution.ValueAt(APosition: Integer): Double;
begin
  // 0,2 · 25^(p/Steps): Mitte 0,2 · 5 = 1,0.
  Result := cMinValue * Power(cMaxValue / cMinValue, EnsureRange(APosition, 0, cSteps) / cSteps);
  Result := Round(Result * 100) / 100;
end;

class function TAtlasArchResolution.PositionOf(AValue: Double): Integer;
begin
  Result := Round(Ln(Clamp(AValue) / cMinValue) / Ln(cMaxValue / cMinValue) * cSteps);
  Result := EnsureRange(Result, 0, cSteps);
end;

class function TAtlasArchResolution.Clamp(AValue: Double): Double;
begin
  if IsNan(AValue) or (AValue <= 0) then
  begin
    Exit(1);
  end;
  Result := EnsureRange(AValue, cMinValue, cMaxValue);
end;

class function TAtlasArchResolution.Text(AValue: Double; const AFormat: TFormatSettings): string;
begin
  Result := FormatFloat('0.0#', AValue, AFormat);
end;

class function TAtlasArchResolution.Same(ALeft, ARight: Double): Boolean;
const
  /// <summary>Halbe Einheit der zweiten Nachkommastelle.</summary>
  cTolerance = 0.005;
begin
  Result := Abs(ALeft - ARight) < cTolerance;
end;

{ TAtlasArchitectureGroupingSettings }

class procedure TAtlasArchitectureGroupingSettings.Read(const AGlobalText: string; out AResolution: Double;
  out AShowSlider: Boolean);
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
begin
  AResolution := 1;
  AShowSlider := True;
  mRoot := TAtlasJsonText.Parse(AGlobalText);
  try
    if mRoot = nil then
    begin
      Exit;
    end;
    mValue := TJSONObject.ParseJSONValue(TAtlasJsonText.ValueAt(mRoot, cResolutionPath));
    try
      if mValue is TJSONNumber then
      begin
        AResolution := TAtlasArchResolution.Clamp(TJSONNumber(mValue).AsDouble);
      end;
    finally
      mValue.Free;
    end;
    AShowSlider := TAtlasJsonText.ValueAt(mRoot, cSliderPath) <> 'false';
  finally
    mRoot.Free;
  end;
end;

class function TAtlasArchitectureGroupingSettings.WithResolution(const AGlobalText: string; AValue: Double): string;
begin
  Result := TAtlasJsonText.SetValue(AGlobalText, cResolutionPath,
    TAtlasArchResolution.Text(TAtlasArchResolution.Clamp(AValue), TFormatSettings.Invariant));
end;

end.
