unit Atlas.Common.Metrics.Limits;

// Grenzwerte der Code-Metriken aus den Einstellungen (#66, #939, #980): je Kennzahl die Option "max" der
// gleichnamigen Regel, z. B.
//   "rules": { "metric-cyclomatic-complexity": { "severity": "warning", "max": 10 } }
// Fehlende oder ungültige Werte (keine ganze Zahl ab 1) nehmen die Vorgabe aus TMetricLimits.Default. Die
// Regeln (Atlas.Common.Rules.Builtin.Metrics), Code Lens und Bericht lesen dieselben Grenzwerte.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.Contract;

const
  cMethodLengthRuleId = 'metric-method-length';
  cNestingDepthRuleId = 'metric-nesting-depth';
  cCyclomaticComplexityRuleId = 'metric-cyclomatic-complexity';
  cCognitiveComplexityRuleId = 'metric-cognitive-complexity';
  cParameterCountRuleId = 'metric-parameter-count';
  cClassSizeRuleId = 'metric-class-size';
  cUnitLengthRuleId = 'metric-unit-length';
  cUsesCountRuleId = 'metric-uses-count';
  cBooleanOperandsRuleId = 'metric-boolean-operands';
  cLocalCountRuleId = 'metric-local-count';
  cExitPointsRuleId = 'metric-exit-points';
  cInheritanceDepthRuleId = 'metric-inheritance-depth';
  /// <summary>Name der Option mit dem Grenzwert.</summary>
  cMetricLimitOption = 'max';

type
  TMetricSettings = class abstract
  public
    /// <summary>Regel-ID der Kennzahl, z. B. metric-cyclomatic-complexity.</summary>
    class function RuleId(AKind: TMetricKind): string; overload; static;
    /// <summary>Regel-ID der Kennzahl des Aufbaus, z. B. metric-class-size (#939).</summary>
    class function RuleId(AKind: TStructureKind): string; overload; static;
    /// <summary>Ganze Zahl ab 1 aus "max" in AOptions (JSON-Text des Regelobjekts), sonst ADefault.</summary>
    class function LimitFromOptions(const AOptions: string; ADefault: Integer): Integer; static;
    /// <summary>Grenzwerte aus "rules" der Einstellungen, fehlende aus TMetricLimits.Default.</summary>
    class function Limits(const ASettings: TServerSettings): TMetricLimits; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

{ TMetricSettings }

class function TMetricSettings.RuleId(AKind: TMetricKind): string;
begin
  case AKind of
    TMetricKind.MethodLength:
      Result := cMethodLengthRuleId;
    TMetricKind.NestingDepth:
      Result := cNestingDepthRuleId;
    TMetricKind.Cyclomatic:
      Result := cCyclomaticComplexityRuleId;
    TMetricKind.Cognitive:
      Result := cCognitiveComplexityRuleId;
    TMetricKind.ParameterCount:
      Result := cParameterCountRuleId;
    TMetricKind.BooleanOperands:
      Result := cBooleanOperandsRuleId;
    TMetricKind.LocalCount:
      Result := cLocalCountRuleId;
  else
    Result := cExitPointsRuleId;
  end;
end;

class function TMetricSettings.RuleId(AKind: TStructureKind): string;
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := cClassSizeRuleId;
    TStructureKind.UnitLength:
      Result := cUnitLengthRuleId;
    TStructureKind.UsesCount:
      Result := cUsesCountRuleId;
  else
    Result := cInheritanceDepthRuleId;
  end;
end;

class function TMetricSettings.LimitFromOptions(const AOptions: string; ADefault: Integer): Integer;
var
  mValue, mLimit: TJSONValue;
  mNumber: Integer;
begin
  Result := ADefault;
  if AOptions = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mLimit := TJSONObject(mValue).GetValue(cMetricLimitOption);
    if (mLimit is TJSONNumber) and TryStrToInt(mLimit.Value, mNumber) and (mNumber >= 1) then
    begin
      Result := mNumber;
    end;
  finally
    mValue.Free;
  end;
end;

class function TMetricSettings.Limits(const ASettings: TServerSettings): TMetricLimits;
var
  mKind: TMetricKind;
  mStructure: TStructureKind;
begin
  Result := TMetricLimits.Default;
  for mKind := Low(TMetricKind) to High(TMetricKind) do
  begin
    Result.Values[mKind] := LimitFromOptions(TRuleSetting.OptionsOf(ASettings.Rules, RuleId(mKind)), Result.Values[mKind]);
  end;
  for mStructure := Low(TStructureKind) to High(TStructureKind) do
  begin
    Result.Structure[mStructure] := LimitFromOptions(TRuleSetting.OptionsOf(ASettings.Rules, RuleId(mStructure)),
      Result.Structure[mStructure]);
  end;
end;

end.
