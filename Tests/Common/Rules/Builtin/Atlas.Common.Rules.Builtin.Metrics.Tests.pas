unit Atlas.Common.Rules.Builtin.Metrics.Tests;

// Tests der Metrik-Regeln (#66): Treffer mit Regel-ID auf dem Methodennamen,
// Unterdrückung per Kommentar, Grenzwerte aus atlas.json ("max"); Aufbau (#939): Member je Klasse, Zeilen
// der Unit, Units im uses; #980: Operanden einer Bedingung samt Korrektur, lokale Variablen, Ausstiege,
// Vererbungstiefe über Datei und Index (Bibliothek ausgenommen, abgebrochene Kette als Untergrenze).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMetricRulesTests = class
  public
    [Test]
    procedure ParameterCountReportsOnName;
    [Test]
    procedure ParameterCountAtLimitSilent;
    [Test]
    procedure CyclomaticUsesMaxFromConfiguration;
    [Test]
    procedure SuppressedByComment;
    [Test]
    procedure MethodLengthReports;
    [Test]
    procedure NestingDepthReports;
    [Test]
    procedure CognitiveReports;
    [Test]
    procedure LimitsFromSettings;
    [Test]
    procedure InvalidMaxKeepsDefault;
    [Test]
    procedure RulesAreRegistered;
    [Test]
    procedure ClassSizeIssueExample;
    [Test]
    procedure ClassSizeCountsMembers;
    [Test]
    procedure UnitLengthAndUsesCount;
    [Test]
    procedure StructureLimitsOffAndExclude;
    [Test]
    procedure BooleanOperandsIssueExample;
    [Test]
    procedure BooleanOperandsFixExtractsCondition;
    [Test]
    procedure BooleanOperandsOptionsOffAndExclude;
    [Test]
    procedure LocalCountReports;
    [Test]
    procedure ExitPointsReports;
    [Test]
    procedure InheritanceDepthInFile;
    [Test]
    procedure InheritanceDepthSkipsLibrary;
    [Test]
    procedure InheritanceDepthLowerBound;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function InUnit(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + ABody + #10'end.';
end;

const
  SevenParameters = 'procedure Book(A, B, C, D, E, F, G: Integer);'#10'begin'#10'end;';
  SixParameters = 'procedure Book(A, B, C, D, E, F: Integer);'#10'begin'#10'end;';
  /// <summary>Zyklomatisch 4: drei if.</summary>
  ThreeIfs = 'procedure Run;'#10'begin'#10'  if A then X;'#10'  if B then Y;'#10'  if C then Z;'#10'end;';

{ TMetricRulesTests }

procedure TMetricRulesTests.ParameterCountReportsOnName;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.ParameterCount), InUnit(SevenParameters));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(ParameterCountRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(14, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('Methode Book hat 7 Parameter (Grenzwert 6); zusammengehörige Werte bündeln', Findings[0].Message);
end;

procedure TMetricRulesTests.ParameterCountAtLimitSilent;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.ParameterCount), InUnit(SixParameters));
end;

procedure TMetricRulesTests.CyclomaticUsesMaxFromConfiguration;
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.Cyclomatic), InUnit(ThreeIfs));
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.Cyclomatic), InUnit(ThreeIfs),
    '{"rules": {"metric-cyclomatic-complexity": {"severity": "warning", "max": 3}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(CyclomaticComplexityRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('Methode Run hat zyklomatische Komplexität 4 (Grenzwert 3)', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.Cyclomatic), InUnit(ThreeIfs),
    '{"rules": {"metric-cyclomatic-complexity": {"max": 4}}}'))), 'der Grenzwert selbst ist erlaubt');
end;

procedure TMetricRulesTests.SuppressedByComment;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.ParameterCount),
    InUnit('// lsp-ignore: metric-parameter-count'#10 + SevenParameters));
  TRuleAssert.Reports(TMetricRule.Create(TMetricKind.ParameterCount),
    InUnit('// lsp-ignore: metric-method-length'#10 + SevenParameters));
end;

procedure TMetricRulesTests.MethodLengthReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.MethodLength),
    InUnit('procedure Run;'#10'begin'#10'  // Kommentar'#10#10'  X;'#10'end;'),
    '{"rules": {"metric-method-length": {"max": 3}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Methode Run hat 4 Codezeilen (Grenzwert 3); in kleinere Methoden aufteilen', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.MethodLength),
    InUnit('procedure Run;'#10'begin'#10'  // Kommentar'#10#10'  X;'#10'end;'),
    '{"rules": {"metric-method-length": {"max": 4}}}'))), 'Kommentar und Leerzeile zählen nicht');
end;

procedure TMetricRulesTests.NestingDepthReports;
const
  Deep = 'procedure Run;'#10'begin'#10'  if A then'#10'    while B do'#10'      try'#10'        X;'#10 +
    '      finally'#10'        Y;'#10'      end;'#10'end;';
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.NestingDepth), InUnit(Deep));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.NestingDepth), InUnit(Deep),
    '{"rules": {"metric-nesting-depth": {"max": 2}}}'))));
end;

procedure TMetricRulesTests.CognitiveReports;
const
  // if (1) + for (2, Ebene 1) + if (3, Ebene 2) = 6
  Nested = 'procedure Run;'#10'begin'#10'  if A then'#10'    for I := 0 to 9 do'#10'      if B then'#10 +
    '        X;'#10'end;';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.Cognitive), InUnit(Nested),
    '{"rules": {"metric-cognitive-complexity": {"max": 5}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Methode Run hat kognitive Komplexität 6 (Grenzwert 5)', Findings[0].Message);
end;

procedure TMetricRulesTests.LimitsFromSettings;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
  Limits: TMetricLimits;
begin
  Settings := TConfigurationParser.Parse('{"rules": {"metric-parameter-count": {"max": 4}, ' +
    '"metric-method-length": "off"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Limits := TMetricRules.Limits(Settings);
  Assert.AreEqual(4, Limits.Values[TMetricKind.ParameterCount]);
  Assert.AreEqual(60, Limits.Values[TMetricKind.MethodLength]);
  Assert.AreEqual(15, Limits.Values[TMetricKind.Cyclomatic]);
end;

procedure TMetricRulesTests.InvalidMaxKeepsDefault;
begin
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('{"max": 0}', 15));
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('{"max": 2.5}', 15));
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('{"max": "10"}', 15));
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('', 15));
  Assert.AreEqual(10, TMetricRules.LimitFromOptions('{"severity": "warning", "max": 10}', 15));
end;

procedure TMetricRulesTests.RulesAreRegistered;
var
  Rule: IRule;
  Found: string;
begin
  Found := '';
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id.StartsWith('metric-') then
      Found := Found + Rule.Descriptor.Id + ' ';
  Assert.AreEqual('metric-method-length metric-nesting-depth metric-cyclomatic-complexity ' +
    'metric-cognitive-complexity metric-parameter-count metric-boolean-operands metric-local-count ' +
    'metric-exit-points metric-class-size metric-unit-length metric-uses-count metric-inheritance-depth ', Found);
end;

/// <summary>Unit mit einer Formularklasse aus ACount Feldern.</summary>
function FormWith(ACount: Integer): string;
var
  Index: Integer;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TfrmHaupt = class(TForm)'#10;
  for Index := 1 to ACount do
    Result := Result + '    Feld' + IntToStr(Index) + ': TLabel;'#10;
  Result := Result + '  end;'#10'implementation'#10'end.';
end;

procedure TMetricRulesTests.ClassSizeIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.ClassSize), FormWith(87));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(ClassSizeRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('TfrmHaupt hat 87 Member (Grenze 40).', Findings[0].Message);
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(11, Findings[0].Range.EndPos.Character);
  TRuleAssert.Silent(TStructureMetricRule.Create(TStructureKind.ClassSize), FormWith(40));
  // Option max
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.ClassSize),
    FormWith(40), '{"rules": {"metric-class-size": {"max": 39}}}'))));
end;

procedure TMetricRulesTests.ClassSizeCountsMembers;
const
  // 2 Felder in einer Zeile, Methode, Konstruktor, Property mit Typ, class var: 6 Member. Hochgestufte
  // Property, geschachtelter Typ und Konstante zählen nicht; die geschachtelte Klasse zählt für sich.
  Source = 'unit U;'#10'interface'#10'type'#10'  TFoo = class(TControl)'#10'  private'#10'    FA, FB: Integer;'#10 +
    '    class var FAnzahl: Integer;'#10'  public type'#10'    TInner = class'#10'      X: Integer;'#10'    end;'#10 +
    '  public const'#10'    Grenze = 3;'#10'  public'#10'    constructor Create(AOwner: TComponent); override;'#10 +
    '    procedure Zeichne;'#10'    property A: Integer read FA;'#10'  published'#10'    property Align;'#10 +
    '  end;'#10'implementation'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.ClassSize), Source,
    '{"rules": {"metric-class-size": {"max": 1}}}');
  Assert.AreEqual(1, Integer(Length(Findings)), 'TInner hat genau ein Member');
  Assert.AreEqual('TFoo hat 6 Member (Grenze 1).', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.ClassSize),
    Source, '{"rules": {"metric-class-size": {"max": 6}}}'))));
end;

procedure TMetricRulesTests.UnitLengthAndUsesCount;
const
  Source = 'unit Kasse.Haupt;'#10'interface'#10'uses'#10'  A, B, C;'#10'implementation'#10'uses'#10'  D;'#10 +
    #10'end.';
  ProgramSource = 'program P;'#10'uses'#10'  A, B, C, D, E;'#10'begin'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TStructureMetricRule.Create(TStructureKind.UnitLength), Source);
  TRuleAssert.Silent(TStructureMetricRule.Create(TStructureKind.UsesCount), Source);
  Findings := TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.UnitLength), Source,
    '{"rules": {"metric-unit-length": {"max": 8}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Unit Kasse.Haupt hat 9 Zeilen (Grenze 8); Klassen lassen sich mit „Klasse in eigene Unit ' +
    'verschieben“ auslagern.', Findings[0].Message);
  Assert.AreEqual(0, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(16, Findings[0].Range.EndPos.Character);
  Findings := TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.UsesCount), Source,
    '{"rules": {"metric-uses-count": {"max": 3}}}');
  Assert.AreEqual(1, Integer(Length(Findings)), 'interface und implementation zusammen');
  Assert.AreEqual('Unit Kasse.Haupt hat 4 Units im uses (Grenze 3); Klassen lassen sich mit „Klasse in eigene ' +
    'Unit verschieben“ auslagern.', Findings[0].Message);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Line, 'auf dem ersten uses');
  // Programme zählen nicht: ihr uses führt die Units des Projekts auf.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.UsesCount),
    ProgramSource, '{"rules": {"metric-uses-count": {"max": 1}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.UnitLength),
    ProgramSource, '{"rules": {"metric-unit-length": {"max": 1}}}'))));
end;

procedure TMetricRulesTests.StructureLimitsOffAndExclude;
var
  Issues: TArray<TConfigurationIssue>;
  Limits: TMetricLimits;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.ClassSize),
    FormWith(87), '{"rules": {"metric-class-size": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStructureMetricRule.Create(TStructureKind.ClassSize),
    FormWith(87), '{"rules": {"metric-class-size": {"exclude": ["Formulare/*.pas"]}}}', 'Formulare/U.pas'))));
  Limits := TMetricRules.Limits(TConfigurationParser.Parse('{"rules": {"metric-class-size": {"max": 50}, ' +
    '"metric-uses-count": {"max": 12}}}', Issues));
  Assert.AreEqual(50, Limits.Structure[TStructureKind.ClassSize]);
  Assert.AreEqual(2000, Limits.Structure[TStructureKind.UnitLength]);
  Assert.AreEqual(12, Limits.Structure[TStructureKind.UsesCount]);
end;

const
  /// <summary>Beispiel aus #980: sechs Operanden.</summary>
  SixOperands = 'unit U;'#10'interface'#10'type'#10'  TKunde = class'#10'    Aktiv: Boolean;'#10 +
    '    Land: string;'#10'  end;'#10'implementation'#10 +
    'procedure Pruefe(Kunde: TKunde; Betrag: Currency; Gesperrt: Boolean; Datum, Start, Ende: TDate);'#10 +
    'begin'#10'  if (Kunde.Aktiv) and (Kunde.Land = ''DE'') and (Betrag > 0) and'#10 +
    '     (not Gesperrt) and (Datum >= Start) and (Datum <= Ende) then'#10'    Buche;'#10'end;'#10'end.';

procedure TMetricRulesTests.BooleanOperandsIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.BooleanOperands), SixOperands);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(BooleanOperandsRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('Bedingung mit 6 Operanden (Grenze 5).', Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line, 'auf der Bedingung');
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(11, Findings[0].Range.EndPos.Line);
  // Fünf Operanden (auch durch Klammern und not hindurch) sind erlaubt.
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.BooleanOperands),
    StringReplace(SixOperands, ' and (Datum <= Ende)', '', []));
  // Zwei Bedingungen mit je drei Operanden zählen getrennt.
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.BooleanOperands),
    StringReplace(SixOperands, ' and'#10'     (not Gesperrt)', ' then'#10'  if (not Gesperrt)', []));
end;

procedure TMetricRulesTests.BooleanOperandsFixExtractsCondition;
var
  Findings: TArray<TRuleFinding>;
  Fixed: string;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.BooleanOperands), SixOperands);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Bedingung in Funktion auslagern', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(SixOperands, Findings[0].Fixes[0].Edits);
  Assert.Contains(Fixed, 'function ExtractedCondition(const Kunde: TKunde; const Betrag: Currency; ' +
    'const Gesperrt: Boolean; const Datum: TDate; const Start: TDate; const Ende: TDate): Boolean;'#10'begin'#10 +
    '  Result := (Kunde.Aktiv) and (Kunde.Land = ''DE'') and (Betrag > 0) and'#10 +
    '     (not Gesperrt) and (Datum >= Start) and (Datum <= Ende);'#10'end;'#10#10'procedure Pruefe(');
  Assert.Contains(Fixed, '  if ExtractedCondition(Kunde, Betrag, Gesperrt, Datum, Start, Ende) then'#10'    Buche;');
  // Die korrigierte Form meldet nichts mehr.
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.BooleanOperands), Fixed);
end;

procedure TMetricRulesTests.BooleanOperandsOptionsOffAndExclude;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.BooleanOperands),
    SixOperands, '{"rules": {"metric-boolean-operands": {"max": 6}}}'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.BooleanOperands),
    StringReplace(SixOperands, ' and (Datum <= Ende)', '', []), '{"rules": {"metric-boolean-operands": {"max": 4}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.BooleanOperands),
    SixOperands, '{"rules": {"metric-boolean-operands": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.BooleanOperands),
    SixOperands, '{"rules": {"metric-boolean-operands": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TMetricRulesTests.LocalCountReports;
const
  // 10 Namen im var-Abschnitt, eine Inline-Variable, eine for-var-Schleife: 12. Die lokale Routine und die
  // anonyme Methode zählen für sich.
  Source = 'procedure Run;'#10'var'#10'  A, B, C: Integer;'#10'  D, E, F, G: string;'#10'  H, I, J: Boolean;'#10 +
    '  procedure Inner;'#10'  var'#10'    X, Y: Integer;'#10'  begin'#10'  end;'#10'begin'#10 +
    '  var K := 1;'#10'  for var L := 0 to 9 do'#10'    Inner;'#10 +
    '  TThread.Queue(nil, procedure'#10'    var'#10'      Z: Integer;'#10'    begin'#10'      var W := 2;'#10 +
    '    end);'#10'end;';
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.LocalCount), InUnit(Source));
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.LocalCount), InUnit(Source),
    '{"rules": {"metric-local-count": {"max": 11}}}');
  Assert.AreEqual(1, Integer(Length(Findings)), 'nur Run, nicht Inner');
  Assert.AreEqual(LocalCountRuleId, Findings[0].RuleId);
  Assert.AreEqual('Methode Run hat 12 lokale Variablen (Grenze 11); Teile in eigene Methoden auslagern',
    Findings[0].Message);
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line, 'auf dem Namen im Kopf');
  TRuleAssert.Reports(TMetricRule.Create(TMetricKind.LocalCount),
    InUnit(StringReplace(Source, '  H, I, J: Boolean;', '  H, I, J, M: Boolean;', [])));
end;

procedure TMetricRulesTests.ExitPointsReports;
const
  // Exit, Exit(Wert) als Anweisung, raise mit Objekt, raise; im except: 4. Exit in der lokalen Routine und
  // in der anonymen Methode zählen nicht.
  Source = 'function Run(A: Integer): Integer;'#10'  procedure Inner;'#10'  begin'#10'    Exit;'#10'  end;'#10 +
    'begin'#10'  if A = 0 then'#10'    Exit;'#10'  if A = 1 then'#10'    Exit(1);'#10'  try'#10 +
    '    if A < 0 then'#10'      raise EArgumentException.Create(''A'');'#10'  except'#10'    raise;'#10'  end;'#10 +
    '  Call(procedure'#10'    begin'#10'      Exit;'#10'    end);'#10'  Result := A;'#10'end;';
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.ExitPoints), InUnit(Source));
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.ExitPoints), InUnit(Source),
    '{"rules": {"metric-exit-points": {"max": 3}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(ExitPointsRuleId, Findings[0].RuleId);
  Assert.AreEqual('Methode Run hat 4 Ausstiege mit Exit oder raise (Grenze 3); Ablauf vereinfachen',
    Findings[0].Message);
  TRuleAssert.Reports(TMetricRule.Create(TMetricKind.ExitPoints),
    InUnit(StringReplace(Source, '  Result := A;', '  if A = 2 then'#10'    Exit(2);'#10'  Result := A;', [])));
end;

/// <summary>Unit mit der Kette TStufe1 = class(ABasis) bis TStufe<ACount>.</summary>
function Chain(const ABasis: string; ACount: Integer): string;
var
  Index: Integer;
begin
  Result := 'unit Kette;'#10'interface'#10'type'#10'  TStufe1 = class(' + ABasis + ')'#10'  end;'#10;
  for Index := 2 to ACount do
    Result := Result + Format('  TStufe%d = class(TStufe%d)'#10'  end;'#10, [Index, Index - 1]);
  Result := Result + 'implementation'#10'end.';
end;

function IndexOf(const ASources: array of string; const ALibrary: array of Boolean): ISymbolIndex;
var
  Index: Integer;
  Tree: TSyntaxTree;
  Item: TUnitIndex;
begin
  Result := TSymbolIndex.Create;
  for Index := 0 to High(ASources) do
  begin
    Tree := TPascalParser.Parse(ASources[Index]);
    try
      Item := TIndexExtractor.Extract(Tree, Format('C:\Quellen\Unit%d.pas', [Index]));
      Item.Library_ := ALibrary[Index];
      Result.AddUnit(Item);
    finally
      Tree.Free;
    end;
  end;
end;

procedure TMetricRulesTests.InheritanceDepthInFile;
var
  Findings: TArray<TRuleFinding>;
begin
  // TStufe6 hat fünf eigene Vorfahren (TStufe1 bis TStufe5), genau die Grenze; TObject zählt nicht.
  TRuleAssert.Silent(TStructureMetricRule.Create(TStructureKind.InheritanceDepth), Chain('TObject', 6));
  Findings := TRuleAssert.IndexFindings(TStructureMetricRule.Create(TStructureKind.InheritanceDepth),
    Chain('TObject', 7), nil, '', '');
  Assert.AreEqual(1, Integer(Length(Findings)), 'nur TStufe7');
  Assert.AreEqual(InheritanceDepthRuleId, Findings[0].RuleId);
  Assert.AreEqual('TStufe7 hat Vererbungstiefe 6 ohne RTL und VCL (Grenze 5).', Findings[0].Message);
  Assert.AreEqual(15, Findings[0].Range.StartPos.Line, 'auf dem Klassennamen');
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(
    TStructureMetricRule.Create(TStructureKind.InheritanceDepth), Chain('TObject', 7), nil,
    '{"rules": {"metric-inheritance-depth": {"max": 6}}}', ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(
    TStructureMetricRule.Create(TStructureKind.InheritanceDepth), Chain('TObject', 7), nil,
    '{"rules": {"metric-inheritance-depth": "off"}}', ''))));
end;

procedure TMetricRulesTests.InheritanceDepthSkipsLibrary;
const
  Forms = 'unit Vcl.Forms;'#10'interface'#10'type'#10'  TControl = class'#10'  end;'#10 +
    '  TWinControl = class(TControl)'#10'  end;'#10'  TCustomForm = class(TWinControl)'#10'  end;'#10 +
    '  TForm = class(TCustomForm)'#10'  end;'#10'implementation'#10'end.';
  Grid = 'unit cxGrid;'#10'interface'#10'type'#10'  TcxBasis = class'#10'  end;'#10 +
    '  TcxGrid = class(TcxBasis)'#10'  end;'#10'implementation'#10'end.';
var
  Index: ISymbolIndex;
begin
  Index := IndexOf([Forms, Grid], [False, True]);
  // Vier VCL-Klassen über der Kette zählen nicht: TStufe6 hat 5 eigene Vorfahren.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(
    TStructureMetricRule.Create(TStructureKind.InheritanceDepth), Chain('TForm', 6), Index, '', ''))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(
    TStructureMetricRule.Create(TStructureKind.InheritanceDepth), Chain('TForm', 7), Index, '', ''))));
  // Bibliothek laut Index (über den Bibliothekspfad nachgeladen).
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(
    TStructureMetricRule.Create(TStructureKind.InheritanceDepth), Chain('TcxGrid', 6), Index, '', ''))));
  // Die Unit der Bibliothek selbst meldet nichts.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(
    TStructureMetricRule.Create(TStructureKind.InheritanceDepth),
    StringReplace(Chain('TObject', 8), 'unit Kette;', 'unit Vcl.Kette;', []), Index, '', ''))));
end;

procedure TMetricRulesTests.InheritanceDepthLowerBound;
var
  Findings: TArray<TRuleFinding>;
begin
  // TUnbekannt steht weder in der Datei noch im Index: Die Kette bricht ab, der Wert ist eine Untergrenze.
  Findings := TRuleAssert.IndexFindings(TStructureMetricRule.Create(TStructureKind.InheritanceDepth),
    Chain('TUnbekannt', 7), nil, '', '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TStufe7 hat Vererbungstiefe mindestens 6 ohne RTL und VCL (Grenze 5).', Findings[0].Message);
  TRuleAssert.Silent(TStructureMetricRule.Create(TStructureKind.InheritanceDepth), Chain('TUnbekannt', 6));
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricRulesTests);

end.
