unit Atlas.Common.Rules.Builtin.Metrics;

// Grenzwerte der Code-Metriken als Regeln (#66), je Kennzahl eine Regel:
//   metric-method-length          Codezeilen ohne Leerzeilen und Kommentare (Vorgabe 60)
//   metric-nesting-depth          Verschachtelungstiefe (Vorgabe 4)
//   metric-cyclomatic-complexity  zyklomatische Komplexität (Vorgabe 15)
//   metric-cognitive-complexity   kognitive Komplexität (Vorgabe 15)
//   metric-parameter-count        Parameteranzahl (Vorgabe 6)
// Der Treffer liegt auf dem Namen im Kopf der Methode; damit greifen
// Unterdrückung (// lsp-ignore: metric-… in der Zeile davor), Schweregrad,
// Profile und Baseline wie bei jeder Regel. Den Grenzwert setzt die Option
//   "rules": { "metric-cyclomatic-complexity": { "severity": "warning", "max": 10 } }
// Code Lens und Bericht lesen dieselben Grenzwerte über TMetricRules.Limits.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  MethodLengthRuleId = 'metric-method-length';
  NestingDepthRuleId = 'metric-nesting-depth';
  CyclomaticComplexityRuleId = 'metric-cyclomatic-complexity';
  CognitiveComplexityRuleId = 'metric-cognitive-complexity';
  ParameterCountRuleId = 'metric-parameter-count';
  /// <summary>Name der Option mit dem Grenzwert.</summary>
  MetricLimitOption = 'max';

type
  /// <summary>Meldet Methoden, deren Kennzahl über dem Grenzwert liegt.</summary>
  TMetricRule = class(TInterfacedObject, IRule)
  private
    FKind: TMetricKind;
  public
    constructor Create(AKind: TMetricKind);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMetricRules = class
  public
    /// <summary>Regel-ID der Kennzahl, z. B. metric-cyclomatic-complexity.</summary>
    class function RuleId(AKind: TMetricKind): string; static;
    /// <summary>Ganze Zahl ab 1 aus "max" in AOptions (JSON-Text des Regelobjekts), sonst ADefault.</summary>
    class function LimitFromOptions(const AOptions: string; ADefault: Integer): Integer; static;
    /// <summary>Grenzwerte aus "rules" der Einstellungen, fehlende aus TMetricLimits.Default.</summary>
    class function Limits(const ASettings: TServerSettings): TMetricLimits; static;
    /// <summary>Meldungstext eines Treffers.</summary>
    class function Message(AKind: TMetricKind; const AName: string; AValue, ALimit: Integer): string; static;
  end;

procedure RegisterMetricRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Rules.Engine;

{ TMetricRules }

class function TMetricRules.RuleId(AKind: TMetricKind): string;
begin
  case AKind of
    TMetricKind.MethodLength:
      Result := MethodLengthRuleId;
    TMetricKind.NestingDepth:
      Result := NestingDepthRuleId;
    TMetricKind.Cyclomatic:
      Result := CyclomaticComplexityRuleId;
    TMetricKind.Cognitive:
      Result := CognitiveComplexityRuleId;
  else
    Result := ParameterCountRuleId;
  end;
end;

class function TMetricRules.LimitFromOptions(const AOptions: string; ADefault: Integer): Integer;
var
  Value, Limit: TJSONValue;
  Number: Integer;
begin
  Result := ADefault;
  if AOptions = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Limit := TJSONObject(Value).GetValue(MetricLimitOption);
    if (Limit is TJSONNumber) and TryStrToInt(Limit.Value, Number) and (Number >= 1) then
      Result := Number;
  finally
    Value.Free;
  end;
end;

class function TMetricRules.Limits(const ASettings: TServerSettings): TMetricLimits;
var
  Kind: TMetricKind;
begin
  Result := TMetricLimits.Default;
  for Kind := Low(TMetricKind) to High(TMetricKind) do
    Result.Values[Kind] := LimitFromOptions(TRuleEngine.RuleOptions(RuleId(Kind), ASettings), Result.Values[Kind]);
end;

class function TMetricRules.Message(AKind: TMetricKind; const AName: string; AValue, ALimit: Integer): string;
begin
  case AKind of
    TMetricKind.MethodLength:
      Result := Format('Methode %s hat %d Codezeilen (Grenzwert %d); in kleinere Methoden aufteilen',
        [AName, AValue, ALimit]);
    TMetricKind.NestingDepth:
      Result := Format('Methode %s ist %d Ebenen tief verschachtelt (Grenzwert %d); ' +
        'früh verlassen oder Teile auslagern', [AName, AValue, ALimit]);
    TMetricKind.Cyclomatic:
      Result := Format('Methode %s hat zyklomatische Komplexität %d (Grenzwert %d)', [AName, AValue, ALimit]);
    TMetricKind.Cognitive:
      Result := Format('Methode %s hat kognitive Komplexität %d (Grenzwert %d)', [AName, AValue, ALimit]);
  else
    Result := Format('Methode %s hat %d Parameter (Grenzwert %d); zusammengehörige Werte bündeln',
      [AName, AValue, ALimit]);
  end;
end;

{ TMetricRule }

constructor TMetricRule.Create(AKind: TMetricKind);
begin
  inherited Create;
  FKind := AKind;
end;

function TMetricRule.Descriptor: TRuleDescriptor;
begin
  case FKind of
    TMetricKind.MethodLength:
      Result := TRuleDescriptor.Create(MethodLengthRuleId, TRuleSeverity.Hint,
        'Methode länger als der Grenzwert (Codezeilen ohne Leerzeilen und Kommentare)');
    TMetricKind.NestingDepth:
      Result := TRuleDescriptor.Create(NestingDepthRuleId, TRuleSeverity.Hint,
        'Methode tiefer verschachtelt als der Grenzwert');
    TMetricKind.Cyclomatic:
      Result := TRuleDescriptor.Create(CyclomaticComplexityRuleId, TRuleSeverity.Hint,
        'Zyklomatische Komplexität einer Methode über dem Grenzwert');
    TMetricKind.Cognitive:
      Result := TRuleDescriptor.Create(CognitiveComplexityRuleId, TRuleSeverity.Hint,
        'Kognitive Komplexität einer Methode über dem Grenzwert');
  else
    Result := TRuleDescriptor.Create(ParameterCountRuleId, TRuleSeverity.Hint,
      'Methode mit mehr Parametern als der Grenzwert');
  end;
end;

procedure TMetricRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Limit: Integer;
  Routine: TRoutineMetrics;
begin
  if AContext.Tree = nil then
    Exit;
  Limit := TMetricRules.LimitFromOptions(AContext.Options, TMetricLimits.Default.Values[FKind]);
  for Routine in TMetricsCalculator.Routines(AContext.Tree) do
    if Routine.Values[FKind] > Limit then
      AReport.Add(Routine.NameRange, TMetricRules.Message(FKind, Routine.Name, Routine.Values[FKind], Limit));
end;

procedure RegisterMetricRules(const ARegistry: TRuleRegistry);
var
  Kind: TMetricKind;
begin
  for Kind := Low(TMetricKind) to High(TMetricKind) do
    ARegistry.Register(TMetricRule.Create(Kind));
end;

end.
