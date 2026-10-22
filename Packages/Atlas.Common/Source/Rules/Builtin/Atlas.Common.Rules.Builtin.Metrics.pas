unit Atlas.Common.Rules.Builtin.Metrics;

// Grenzwerte der Code-Metriken als Regeln (#66), je Kennzahl eine Regel:
//   metric-method-length          Codezeilen ohne Leerzeilen und Kommentare (Vorgabe 60)
//   metric-nesting-depth          Verschachtelungstiefe (Vorgabe 4)
//   metric-cyclomatic-complexity  zyklomatische Komplexität (Vorgabe 15)
//   metric-cognitive-complexity   kognitive Komplexität (Vorgabe 15)
//   metric-parameter-count        Parameteranzahl (Vorgabe 6)
//   metric-class-size             Member je Klasse (Vorgabe 40, #939), Treffer auf dem Klassennamen
//   metric-unit-length            Zeilen je Unit (Vorgabe 2000, #939), Treffer auf dem Unit-Namen
//   metric-uses-count             Units im uses (Vorgabe 30, #939), Treffer auf dem ersten uses
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
  ClassSizeRuleId = 'metric-class-size';
  UnitLengthRuleId = 'metric-unit-length';
  UsesCountRuleId = 'metric-uses-count';
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

  /// <summary>Meldet Klassen bzw. Units, deren Aufbau über dem Grenzwert liegt (#939).</summary>
  TStructureMetricRule = class(TInterfacedObject, IRule)
  private
    FKind: TStructureKind;
  public
    constructor Create(AKind: TStructureKind);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMetricRules = class
  public
    /// <summary>Regel-ID der Kennzahl, z. B. metric-cyclomatic-complexity.</summary>
    class function RuleId(AKind: TMetricKind): string; overload; static;
    /// <summary>Regel-ID der Kennzahl des Aufbaus, z. B. metric-class-size (#939).</summary>
    class function RuleId(AKind: TStructureKind): string; overload; static;
    /// <summary>Ganze Zahl ab 1 aus "max" in AOptions (JSON-Text des Regelobjekts), sonst ADefault.</summary>
    class function LimitFromOptions(const AOptions: string; ADefault: Integer): Integer; static;
    /// <summary>Grenzwerte aus "rules" der Einstellungen, fehlende aus TMetricLimits.Default.</summary>
    class function Limits(const ASettings: TServerSettings): TMetricLimits; static;
    /// <summary>Meldungstext eines Treffers.</summary>
    class function Message(AKind: TMetricKind; const AName: string; AValue, ALimit: Integer): string; overload;
      static;
    /// <summary>Meldungstext eines Treffers zum Aufbau (#939).</summary>
    class function Message(AKind: TStructureKind; const AName: string; AValue, ALimit: Integer): string; overload;
      static;
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

class function TMetricRules.RuleId(AKind: TStructureKind): string;
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := ClassSizeRuleId;
    TStructureKind.UnitLength:
      Result := UnitLengthRuleId;
  else
    Result := UsesCountRuleId;
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
  Structure: TStructureKind;
begin
  Result := TMetricLimits.Default;
  for Kind := Low(TMetricKind) to High(TMetricKind) do
    Result.Values[Kind] := LimitFromOptions(TRuleEngine.RuleOptions(RuleId(Kind), ASettings), Result.Values[Kind]);
  for Structure := Low(TStructureKind) to High(TStructureKind) do
    Result.Structure[Structure] := LimitFromOptions(TRuleEngine.RuleOptions(RuleId(Structure), ASettings),
      Result.Structure[Structure]);
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

class function TMetricRules.Message(AKind: TStructureKind; const AName: string; AValue, ALimit: Integer): string;
const
  MoveHint = '; Klassen lassen sich mit „Klasse in eigene Unit verschieben“ auslagern.';
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := Format('%s hat %d Member (Grenze %d).', [AName, AValue, ALimit]);
    TStructureKind.UnitLength:
      Result := Format('Unit %s hat %d Zeilen (Grenze %d)', [AName, AValue, ALimit]) + MoveHint;
  else
    Result := Format('Unit %s hat %d Units im uses (Grenze %d)', [AName, AValue, ALimit]) + MoveHint;
  end;
end;

{ TStructureMetricRule }

constructor TStructureMetricRule.Create(AKind: TStructureKind);
begin
  inherited Create;
  FKind := AKind;
end;

function TStructureMetricRule.Descriptor: TRuleDescriptor;
begin
  case FKind of
    TStructureKind.ClassSize:
      Result := TRuleDescriptor.Create(ClassSizeRuleId, TRuleSeverity.Hint, 'Klasse mit mehr Membern als der Grenzwert');
    TStructureKind.UnitLength:
      Result := TRuleDescriptor.Create(UnitLengthRuleId, TRuleSeverity.Hint, 'Unit länger als der Grenzwert');
  else
    Result := TRuleDescriptor.Create(UsesCountRuleId, TRuleSeverity.Hint, 'Mehr Units im uses als der Grenzwert');
  end;
end;

procedure TStructureMetricRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Limit: Integer;
  Item: TStructureMetrics;
begin
  if AContext.Tree = nil then
    Exit;
  Limit := TMetricRules.LimitFromOptions(AContext.Options, TMetricLimits.Default.Structure[FKind]);
  for Item in TMetricsCalculator.Structure(AContext.Tree) do
    if (Item.Kind = FKind) and (Item.Value > Limit) then
      AReport.Add(Item.NameRange, TMetricRules.Message(FKind, Item.Name, Item.Value, Limit));
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
  Structure: TStructureKind;
begin
  for Kind := Low(TMetricKind) to High(TMetricKind) do
    ARegistry.Register(TMetricRule.Create(Kind));
  for Structure := Low(TStructureKind) to High(TStructureKind) do
    ARegistry.Register(TStructureMetricRule.Create(Structure));
end;

end.
