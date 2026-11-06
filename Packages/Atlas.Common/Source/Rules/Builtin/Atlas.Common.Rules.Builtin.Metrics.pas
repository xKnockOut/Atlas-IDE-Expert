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
  Atlas.Common.Rules.Engine,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMetricsText = (MethodLength, Nesting, Cyclomatic, Cognitive, Parameters, Operands, Locals, Exits, MoveClassHint,
    Members, UnitLines, UsesCount, Depth, DepthAtLeast, MembersTitle, UnitLinesTitle, UsesTitle, DepthTitle,
    MethodLengthTitle, NestingTitle, CyclomaticTitle, CognitiveTitle, ParametersTitle, OperandsTitle, LocalsTitle,
    ExitsTitle);

const
  cTexts: array[TMetricsText] of TAtlasText = (
    (De: 'Methode %s hat %d Codezeilen (Grenzwert %d); in kleinere Methoden aufteilen';
     En: 'Method %s has %d code lines (limit %d); split it into smaller methods'),
    (De: 'Methode %s ist %d Ebenen tief verschachtelt (Grenzwert %d); früh verlassen oder Teile auslagern';
     En: 'Method %s is nested %d levels deep (limit %d); exit early or extract parts'),
    (De: 'Methode %s hat zyklomatische Komplexität %d (Grenzwert %d)';
     En: 'Method %s has cyclomatic complexity %d (limit %d)'),
    (De: 'Methode %s hat kognitive Komplexität %d (Grenzwert %d)';
     En: 'Method %s has cognitive complexity %d (limit %d)'),
    (De: 'Methode %s hat %d Parameter (Grenzwert %d); zusammengehörige Werte bündeln';
     En: 'Method %s has %d parameters (limit %d); bundle values that belong together'),
    (De: 'Bedingung mit %d Operanden (Grenze %d).'; En: 'Condition with %d operands (limit %d).'),
    (De: 'Methode %s hat %d lokale Variablen (Grenze %d); Teile in eigene Methoden auslagern';
     En: 'Method %s has %d local variables (limit %d); move parts into separate methods'),
    (De: 'Methode %s hat %d Ausstiege mit Exit oder raise (Grenze %d); Ablauf vereinfachen';
     En: 'Method %s has %d exits with Exit or raise (limit %d); simplify the flow'),
    (De: '; Klassen lassen sich mit „Klasse in eigene Unit verschieben“ auslagern.';
     En: '; classes can be moved out with “Move class to own unit”.'),
    (De: '%s hat %d Member (Grenze %d).'; En: '%s has %d members (limit %d).'),
    (De: 'Unit %s hat %d Zeilen (Grenze %d)'; En: 'Unit %s has %d lines (limit %d)'),
    (De: 'Unit %s hat %d Units im uses (Grenze %d)'; En: 'Unit %s has %d units in uses (limit %d)'),
    (De: '%s hat Vererbungstiefe %d ohne RTL und VCL (Grenze %d).';
     En: '%s has inheritance depth %d without RTL and VCL (limit %d).'),
    (De: '%s hat Vererbungstiefe mindestens %d ohne RTL und VCL (Grenze %d).';
     En: '%s has inheritance depth of at least %d without RTL and VCL (limit %d).'),
    (De: 'Klasse mit mehr Membern als der Grenzwert'; En: 'Class with more members than the limit'),
    (De: 'Unit länger als der Grenzwert'; En: 'Unit longer than the limit'),
    (De: 'Mehr Units im uses als der Grenzwert'; En: 'More units in uses than the limit'),
    (De: 'Klasse mit mehr eigenen Vorfahren (ohne RTL und VCL) als der Grenzwert';
     En: 'Class with more own ancestors (without RTL and VCL) than the limit'),
    (De: 'Methode länger als der Grenzwert (Codezeilen ohne Leerzeilen und Kommentare)';
     En: 'Method longer than the limit (code lines without blank lines and comments)'),
    (De: 'Methode tiefer verschachtelt als der Grenzwert'; En: 'Method nested deeper than the limit'),
    (De: 'Zyklomatische Komplexität einer Methode über dem Grenzwert';
     En: 'Cyclomatic complexity of a method above the limit'),
    (De: 'Kognitive Komplexität einer Methode über dem Grenzwert';
     En: 'Cognitive complexity of a method above the limit'),
    (De: 'Methode mit mehr Parametern als der Grenzwert'; En: 'Method with more parameters than the limit'),
    (De: 'Bedingung mit mehr and/or/xor-Operanden als der Grenzwert';
     En: 'Condition with more and/or/xor operands than the limit'),
    (De: 'Methode mit mehr lokalen Variablen als der Grenzwert'; En: 'Method with more local variables than the limit'),
    (De: 'Methode mit mehr Exit und raise als der Grenzwert'; En: 'Method with more Exit and raise than the limit'));

{$SCOPEDENUMS OFF}

{ TMetricRules }

class function TMetricRules.RuleId(AKind: TMetricKind): string;
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

class function TMetricRules.RuleId(AKind: TStructureKind): string;
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

class function TMetricRules.LimitFromOptions(const AOptions: string; ADefault: Integer): Integer;
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

class function TMetricRules.Limits(const ASettings: TServerSettings): TMetricLimits;
var
  mKind: TMetricKind;
  mStructure: TStructureKind;
begin
  Result := TMetricLimits.Default;
  for mKind := Low(TMetricKind) to High(TMetricKind) do
  begin
    Result.Values[mKind] := LimitFromOptions(TRuleEngine.RuleOptions(RuleId(mKind), ASettings), Result.Values[mKind]);
  end;
  for mStructure := Low(TStructureKind) to High(TStructureKind) do
  begin
    Result.Structure[mStructure] := LimitFromOptions(TRuleEngine.RuleOptions(RuleId(mStructure), ASettings),
      Result.Structure[mStructure]);
  end;
end;

class function TMetricRules.Message(AKind: TMetricKind; const AName: string; AValue, ALimit: Integer): string;
begin
  case AKind of
    TMetricKind.MethodLength:
      Result := cTexts[TMetricsText.MethodLength].Fmt([AName, AValue, ALimit]);
    TMetricKind.NestingDepth:
      Result := cTexts[TMetricsText.Nesting].Fmt([AName, AValue, ALimit]);
    TMetricKind.Cyclomatic:
      Result := cTexts[TMetricsText.Cyclomatic].Fmt([AName, AValue, ALimit]);
    TMetricKind.Cognitive:
      Result := cTexts[TMetricsText.Cognitive].Fmt([AName, AValue, ALimit]);
    TMetricKind.ParameterCount:
      Result := cTexts[TMetricsText.Parameters].Fmt([AName, AValue, ALimit]);
    TMetricKind.BooleanOperands:
      Result := cTexts[TMetricsText.Operands].Fmt([AValue, ALimit]);
    TMetricKind.LocalCount:
      Result := cTexts[TMetricsText.Locals].Fmt([AName, AValue, ALimit]);
  else
    Result := cTexts[TMetricsText.Exits].Fmt([AName, AValue, ALimit]);
  end;
end;

class function TMetricRules.Message(AKind: TStructureKind; const AName: string; AValue, ALimit: Integer): string;
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := cTexts[TMetricsText.Members].Fmt([AName, AValue, ALimit]);
    TStructureKind.UnitLength:
      Result := cTexts[TMetricsText.UnitLines].Fmt([AName, AValue, ALimit]) + cTexts[TMetricsText.MoveClassHint].Text;
    TStructureKind.UsesCount:
      Result := cTexts[TMetricsText.UsesCount].Fmt([AName, AValue, ALimit]) + cTexts[TMetricsText.MoveClassHint].Text;
  else
    Result := cTexts[TMetricsText.Depth].Fmt([AName, AValue, ALimit]);
  end;
end;

class function TMetricRules.Message(AKind: TStructureKind; const AName: string; AValue, ALimit: Integer;
  AAtLeast: Boolean): string;
begin
  if AAtLeast and (AKind = TStructureKind.InheritanceDepth) then
  begin
    Result := cTexts[TMetricsText.DepthAtLeast].Fmt([AName, AValue, ALimit]);
  end
  else
  begin
    Result := Message(AKind, AName, AValue, ALimit);
  end;
end;

/// <summary>Vorfahren der Klasse ohne Bibliotheksklassen und TObject; AReachedLibrary, wenn eine
/// Bibliotheksklasse darunter war.</summary>
function CountAncestors(const AIndex: ISymbolIndex; const AAncestry: TAncestry; const AName: string;
  out AComplete, AReachedLibrary: Boolean): Integer;
var
  mLocation: TSymbolLocation;
  mObjectMissing: Boolean;
begin
  Result := 0;
  AReachedLibrary := False;
  for mLocation in AAncestry.Ancestors(AName, AComplete, mObjectMissing) do
  begin
    if (mLocation.UnitName <> '') and TLibraryUnits.IsLibrary(AIndex, mLocation.UnitName) then
    begin
      AReachedLibrary := True;
    end
    else if not SameText(mLocation.Symbol.Name, 'TObject') then
    begin
      Inc(Result);
    end;
  end;
end;

class function TMetricRules.InheritanceDepths(ATree: TSyntaxTree; const AIndex: ISymbolIndex;
  const ALocal: TUnitIndex): TArray<TStructureMetrics>;
var
  mAncestry: TAncestry;
  mItem, mDepth: TStructureMetrics;
  mLocation: TSymbolLocation;
  mComplete, mReachedLibrary: Boolean;
  mCount, mIndex: Integer;
  mSeen: TDictionary<string, Integer>;
begin
  Result := nil;
  if (ATree = nil) or TLibraryUnits.IsLibrary(AIndex, ALocal.UnitName) then
  begin
    Exit;
  end;
  mAncestry := TAncestry.Create(AIndex, ALocal);
  mSeen := TDictionary<string, Integer>.Create;
  try
    for mItem in TMetricsCalculator.Structure(ATree) do
    begin
      // Nur Klassen der obersten Ebene; object-Typen und verschachtelte Klassen kennt TAncestry nicht.
      if (mItem.Kind <> TStructureKind.ClassSize) or not mAncestry.FindClass(mItem.Name, mLocation) then
      begin
        Continue;
      end;
      mCount := CountAncestors(AIndex, mAncestry, mItem.Name, mComplete, mReachedLibrary);
      if mCount = 0 then
      begin
        Continue;
      end;
      mDepth := mItem;
      mDepth.Kind := TStructureKind.InheritanceDepth;
      mDepth.Value := mCount;
      // Über einer Bibliotheksklasse folgen nur noch Bibliotheksklassen.
      mDepth.AtLeast := not mComplete and not mReachedLibrary;
      // Vorwärtsdeklaration und Deklaration: die spätere zählt.
      if mSeen.TryGetValue(UpperCase(mItem.Name), mIndex) then
      begin
        Result[mIndex] := mDepth;
      end
      else
      begin
        mSeen.Add(UpperCase(mItem.Name), Length(Result));
        Result := Result + [mDepth];
      end;
    end;
  finally
    mSeen.Free;
    mAncestry.Free;
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
      Result := TRuleDescriptor.Create(cClassSizeRuleId, TRuleSeverity.Hint, cTexts[TMetricsText.MembersTitle].Text);
    TStructureKind.UnitLength:
      Result := TRuleDescriptor.Create(cUnitLengthRuleId, TRuleSeverity.Hint, cTexts[TMetricsText.UnitLinesTitle].Text);
    TStructureKind.UsesCount:
      Result := TRuleDescriptor.Create(cUsesCountRuleId, TRuleSeverity.Hint, cTexts[TMetricsText.UsesTitle].Text);
  else
    Result := TRuleDescriptor.Create(cInheritanceDepthRuleId, TRuleSeverity.Hint,
      cTexts[TMetricsText.DepthTitle].Text);
  end;
end;

procedure TStructureMetricRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLimit: Integer;
  mItem: TStructureMetrics;
  mItems: TArray<TStructureMetrics>;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mLimit := TMetricRules.LimitFromOptions(AContext.Options, TMetricLimits.Default.Structure[FKind]);
  if FKind = TStructureKind.InheritanceDepth then
  begin
    mItems := TMetricRules.InheritanceDepths(AContext.Tree, AContext.Index,
      TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  end
  else
  begin
    mItems := TMetricsCalculator.Structure(AContext.Tree);
  end;
  for mItem in mItems do
  begin
    if (mItem.Kind = FKind) and (mItem.Value > mLimit) then
    begin
      AReport.Add(mItem.NameRange, TMetricRules.Message(FKind, mItem.Name, mItem.Value, mLimit, mItem.AtLeast));
    end;
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
      Result := TRuleDescriptor.Create(cMethodLengthRuleId, TRuleSeverity.Hint,
        cTexts[TMetricsText.MethodLengthTitle].Text);
    TMetricKind.NestingDepth:
      Result := TRuleDescriptor.Create(cNestingDepthRuleId, TRuleSeverity.Hint,
        cTexts[TMetricsText.NestingTitle].Text);
    TMetricKind.Cyclomatic:
      Result := TRuleDescriptor.Create(cCyclomaticComplexityRuleId, TRuleSeverity.Hint,
        cTexts[TMetricsText.CyclomaticTitle].Text);
    TMetricKind.Cognitive:
      Result := TRuleDescriptor.Create(cCognitiveComplexityRuleId, TRuleSeverity.Hint,
        cTexts[TMetricsText.CognitiveTitle].Text);
    TMetricKind.ParameterCount:
      Result := TRuleDescriptor.Create(cParameterCountRuleId, TRuleSeverity.Hint,
        cTexts[TMetricsText.ParametersTitle].Text);
    TMetricKind.BooleanOperands:
      Result := TRuleDescriptor.Create(cBooleanOperandsRuleId, TRuleSeverity.Hint,
        cTexts[TMetricsText.OperandsTitle].Text);
    TMetricKind.LocalCount:
      Result := TRuleDescriptor.Create(cLocalCountRuleId, TRuleSeverity.Hint,
        cTexts[TMetricsText.LocalsTitle].Text);
  else
    Result := TRuleDescriptor.Create(cExitPointsRuleId, TRuleSeverity.Hint,
      cTexts[TMetricsText.ExitsTitle].Text);
  end;
end;

/// <summary>Jede Bedingung über dem Grenzwert, mit „Bedingung in Funktion auslagern“ (#980).</summary>
procedure CheckConditions(const AContext: TRuleContext; const AReport: IRuleReport; ALimit: Integer);
var
  mCondition: TConditionMetrics;
  mOptions: TExtractOptions;
  mAction: TCodeAction;
  mFixes: TArray<TRuleFix>;
begin
  mOptions := TExtractOptions.Default;
  mOptions.Style := AContext.Formatting;
  for mCondition in TMetricsCalculator.Conditions(AContext.Tree) do
  begin
    if mCondition.Operands > ALimit then
    begin
      mFixes := nil;
      if TExtractRefactoring.ExtractCondition(AContext.Text, AContext.Tree, mCondition.Range, mOptions, mAction) then
      begin
        mFixes := [TRuleFix.Create(mAction.Title, mAction.Edits)];
      end;
      AReport.Add(mCondition.Range, TMetricRules.Message(TMetricKind.BooleanOperands, '', mCondition.Operands, ALimit),
        mFixes);
    end;
  end;
end;

procedure TMetricRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mLimit: Integer;
  mRoutine: TRoutineMetrics;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mLimit := TMetricRules.LimitFromOptions(AContext.Options, TMetricLimits.Default.Values[FKind]);
  if FKind = TMetricKind.BooleanOperands then
  begin
    CheckConditions(AContext, AReport, mLimit);
    Exit;
  end;
  for mRoutine in TMetricsCalculator.Routines(AContext.Tree) do
  begin
    if mRoutine.Values[FKind] > mLimit then
    begin
      AReport.Add(mRoutine.NameRange, TMetricRules.Message(FKind, mRoutine.Name, mRoutine.Values[FKind], mLimit));
    end;
  end;
end;

procedure RegisterMetricRules(const ARegistry: TRuleRegistry);
var
  mKind: TMetricKind;
  mStructure: TStructureKind;
begin
  for mKind := Low(TMetricKind) to High(TMetricKind) do
  begin
    ARegistry.Register(TMetricRule.Create(mKind));
  end;
  for mStructure := Low(TStructureKind) to High(TStructureKind) do
  begin
    ARegistry.Register(TStructureMetricRule.Create(mStructure));
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Metrics', cTexts);

end.
