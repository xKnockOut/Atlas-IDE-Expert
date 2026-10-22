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
//   metric-boolean-operands       Operanden einer Bedingung (Vorgabe 5, #980), Treffer auf der Bedingung,
//                                 Korrektur „Bedingung in Funktion auslagern“ (Editing.Extract)
//   metric-local-count            lokale Variablen je Routine (Vorgabe 12, #980)
//   metric-exit-points            Exit und raise je Routine (Vorgabe 4, #980)
//   metric-inheritance-depth      Vorfahren ohne RTL, VCL und Bibliotheken (Vorgabe 5, #980), Treffer auf
//                                 dem Klassennamen; Vorfahren über TAncestry (Datei und Index), Bibliothek
//                                 über TLibraryUnits. Bricht die Kette an einem unbekannten Vorfahren ab,
//                                 ist der Wert eine Untergrenze („mindestens“) und meldet nur, wenn schon
//                                 sie über der Grenze liegt.
// Der Treffer liegt auf dem Namen im Kopf der Methode; damit greifen
// Unterdrückung (// lsp-ignore: metric-… in der Zeile davor), Schweregrad,
// Profile und Baseline wie bei jeder Regel. Den Grenzwert setzt die Option
//   "rules": { "metric-cyclomatic-complexity": { "severity": "warning", "max": 10 } }
// Code Lens und Bericht lesen dieselben Grenzwerte über TMetricRules.Limits.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
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
  BooleanOperandsRuleId = 'metric-boolean-operands';
  LocalCountRuleId = 'metric-local-count';
  ExitPointsRuleId = 'metric-exit-points';
  InheritanceDepthRuleId = 'metric-inheritance-depth';
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
    /// <summary>Wie oben; AAtLeast: AValue ist nur eine Untergrenze („mindestens“, Vererbungstiefe #980).</summary>
    class function Message(AKind: TStructureKind; const AName: string; AValue, ALimit: Integer;
      AAtLeast: Boolean): string; overload; static;
    /// <summary>Vererbungstiefe jeder Klasse der Datei (#980): Vorfahren aus Datei und Index ohne RTL, VCL und
    /// Bibliotheken; ALocal ist der Index der Datei. AtLeast, wenn die Kette an einem unbekannten Vorfahren
    /// abbricht, bevor sie die Bibliothek erreicht. Klassen ohne eigene Vorfahren fehlen; leer für Units der
    /// Bibliothek selbst.</summary>
    class function InheritanceDepths(ATree: TSyntaxTree; const AIndex: ISymbolIndex;
      const ALocal: TUnitIndex): TArray<TStructureMetrics>; static;
  end;

procedure RegisterMetricRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.LibraryUnits,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
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
    TMetricKind.ParameterCount:
      Result := ParameterCountRuleId;
    TMetricKind.BooleanOperands:
      Result := BooleanOperandsRuleId;
    TMetricKind.LocalCount:
      Result := LocalCountRuleId;
  else
    Result := ExitPointsRuleId;
  end;
end;

class function TMetricRules.RuleId(AKind: TStructureKind): string;
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := ClassSizeRuleId;
    TStructureKind.UnitLength:
      Result := UnitLengthRuleId;
    TStructureKind.UsesCount:
      Result := UsesCountRuleId;
  else
    Result := InheritanceDepthRuleId;
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
    TMetricKind.ParameterCount:
      Result := Format('Methode %s hat %d Parameter (Grenzwert %d); zusammengehörige Werte bündeln',
        [AName, AValue, ALimit]);
    TMetricKind.BooleanOperands:
      Result := Format('Bedingung mit %d Operanden (Grenze %d).', [AValue, ALimit]);
    TMetricKind.LocalCount:
      Result := Format('Methode %s hat %d lokale Variablen (Grenze %d); Teile in eigene Methoden auslagern',
        [AName, AValue, ALimit]);
  else
    Result := Format('Methode %s hat %d Ausstiege mit Exit oder raise (Grenze %d); Ablauf vereinfachen',
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
    TStructureKind.UsesCount:
      Result := Format('Unit %s hat %d Units im uses (Grenze %d)', [AName, AValue, ALimit]) + MoveHint;
  else
    Result := Format('%s hat Vererbungstiefe %d ohne RTL und VCL (Grenze %d).', [AName, AValue, ALimit]);
  end;
end;

class function TMetricRules.Message(AKind: TStructureKind; const AName: string; AValue, ALimit: Integer;
  AAtLeast: Boolean): string;
begin
  if AAtLeast and (AKind = TStructureKind.InheritanceDepth) then
    Result := Format('%s hat Vererbungstiefe mindestens %d ohne RTL und VCL (Grenze %d).', [AName, AValue, ALimit])
  else
    Result := Message(AKind, AName, AValue, ALimit);
end;

class function TMetricRules.InheritanceDepths(ATree: TSyntaxTree; const AIndex: ISymbolIndex;
  const ALocal: TUnitIndex): TArray<TStructureMetrics>;
var
  Ancestry: TAncestry;
  Item, Depth: TStructureMetrics;
  Location: TSymbolLocation;
  Complete, ObjectMissing, ReachedLibrary: Boolean;
  Count, Index: Integer;
  Seen: TDictionary<string, Integer>;
begin
  Result := nil;
  if (ATree = nil) or TLibraryUnits.IsLibrary(AIndex, ALocal.UnitName) then
    Exit;
  Ancestry := TAncestry.Create(AIndex, ALocal);
  Seen := TDictionary<string, Integer>.Create;
  try
    for Item in TMetricsCalculator.Structure(ATree) do
    begin
      // Nur Klassen der obersten Ebene; object-Typen und verschachtelte Klassen kennt TAncestry nicht.
      if (Item.Kind <> TStructureKind.ClassSize) or not Ancestry.FindClass(Item.Name, Location) then
        Continue;
      Count := 0;
      ReachedLibrary := False;
      for Location in Ancestry.Ancestors(Item.Name, Complete, ObjectMissing) do
        if (Location.UnitName <> '') and TLibraryUnits.IsLibrary(AIndex, Location.UnitName) then
          ReachedLibrary := True
        else if not SameText(Location.Symbol.Name, 'TObject') then
          Inc(Count);
      if Count = 0 then
        Continue;
      Depth := Item;
      Depth.Kind := TStructureKind.InheritanceDepth;
      Depth.Value := Count;
      // Über einer Bibliotheksklasse folgen nur noch Bibliotheksklassen.
      Depth.AtLeast := not Complete and not ReachedLibrary;
      // Vorwärtsdeklaration und Deklaration: die spätere zählt.
      if Seen.TryGetValue(UpperCase(Item.Name), Index) then
        Result[Index] := Depth
      else
      begin
        Seen.Add(UpperCase(Item.Name), Length(Result));
        Result := Result + [Depth];
      end;
    end;
  finally
    Seen.Free;
    Ancestry.Free;
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
    TStructureKind.UsesCount:
      Result := TRuleDescriptor.Create(UsesCountRuleId, TRuleSeverity.Hint, 'Mehr Units im uses als der Grenzwert');
  else
    Result := TRuleDescriptor.Create(InheritanceDepthRuleId, TRuleSeverity.Hint,
      'Klasse mit mehr eigenen Vorfahren (ohne RTL und VCL) als der Grenzwert');
  end;
end;

procedure TStructureMetricRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Limit: Integer;
  Item: TStructureMetrics;
  Items: TArray<TStructureMetrics>;
begin
  if AContext.Tree = nil then
    Exit;
  Limit := TMetricRules.LimitFromOptions(AContext.Options, TMetricLimits.Default.Structure[FKind]);
  if FKind = TStructureKind.InheritanceDepth then
    Items := TMetricRules.InheritanceDepths(AContext.Tree, AContext.Index,
      TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext))
  else
    Items := TMetricsCalculator.Structure(AContext.Tree);
  for Item in Items do
    if (Item.Kind = FKind) and (Item.Value > Limit) then
      AReport.Add(Item.NameRange, TMetricRules.Message(FKind, Item.Name, Item.Value, Limit, Item.AtLeast));
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
    TMetricKind.ParameterCount:
      Result := TRuleDescriptor.Create(ParameterCountRuleId, TRuleSeverity.Hint,
        'Methode mit mehr Parametern als der Grenzwert');
    TMetricKind.BooleanOperands:
      Result := TRuleDescriptor.Create(BooleanOperandsRuleId, TRuleSeverity.Hint,
        'Bedingung mit mehr and/or/xor-Operanden als der Grenzwert');
    TMetricKind.LocalCount:
      Result := TRuleDescriptor.Create(LocalCountRuleId, TRuleSeverity.Hint,
        'Methode mit mehr lokalen Variablen als der Grenzwert');
  else
    Result := TRuleDescriptor.Create(ExitPointsRuleId, TRuleSeverity.Hint,
      'Methode mit mehr Exit und raise als der Grenzwert');
  end;
end;

/// <summary>Jede Bedingung über dem Grenzwert, mit „Bedingung in Funktion auslagern“ (#980).</summary>
procedure CheckConditions(const AContext: TRuleContext; const AReport: IRuleReport; ALimit: Integer);
var
  Condition: TConditionMetrics;
  Options: TExtractOptions;
  Action: TCodeAction;
  Fixes: TArray<TRuleFix>;
begin
  Options := TExtractOptions.Default;
  Options.Style := AContext.Formatting;
  for Condition in TMetricsCalculator.Conditions(AContext.Tree) do
    if Condition.Operands > ALimit then
    begin
      Fixes := nil;
      if TExtractRefactoring.ExtractCondition(AContext.Text, AContext.Tree, Condition.Range, Options, Action) then
        Fixes := [TRuleFix.Create(Action.Title, Action.Edits)];
      AReport.Add(Condition.Range, TMetricRules.Message(TMetricKind.BooleanOperands, '', Condition.Operands, ALimit),
        Fixes);
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
  if FKind = TMetricKind.BooleanOperands then
  begin
    CheckConditions(AContext, AReport, Limit);
    Exit;
  end;
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
