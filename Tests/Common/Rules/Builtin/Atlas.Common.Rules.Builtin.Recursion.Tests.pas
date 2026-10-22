unit Atlas.Common.Rules.Builtin.Recursion.Tests;

// Tests der Regel setter-recursion (#623, #910): Setter und Getter der
// eigenen Property als Fehler, Feld aus der Deklaration bzw. F<Name> als
// Korrektur, keine Meldung ohne Falle, Unterdrückung, Abschalten, Ausnahmen,
// frühere Kennung recursive-property-accessor und Registrierung.
// unconditional-recursion (#1044): Beispiel aus dem Issue, Hinweise je
// Parametertyp, Pfade mit Abbruch (if, case, Exit, Kurzschluss, Schleifen),
// Aufruf auf jedem Pfad (if mit else, repeat, try), Überladungen, Getter
// (setter-recursion), Abschalten und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRecursionRulesTests = class
  public
    [Test]
    procedure SetterExampleIsErrorWithFieldFix;
    [Test]
    procedure GetterUsesFieldOfDeclaration;
    [Test]
    procedure SetterWithoutFieldHasNoFix;
    [Test]
    procedure FieldAccessIsSilent;
    [Test]
    procedure OtherPropertyIsSilent;
    [Test]
    procedure SuppressedByComment;
    [Test]
    procedure FormerIdStillSuppresses;
    [Test]
    procedure OffAndExcludeSilence;
    [Test]
    procedure FormerIdInSettingsApplies;
    [Test]
    procedure AliasesMapFormerIds;
    [Test]
    procedure RuleIsRegistered;
  end;

  [TestFixture]
  TUnconditionalRecursionTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure HintsAndPaths;
    [Test]
    procedure StopsAreSilent;
    [Test]
    procedure OverloadsAndAccessorsAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Recursion,
  Atlas.Tests.RuleAssert;

const
  Header =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    function GetName: string;'#10 +
    '    procedure SetTitle(const AValue: string);'#10 +
    '  public'#10 +
    '    property Name: string read GetName;'#10 +
    '    property Title: string write SetTitle;'#10 +
    '  end;'#10 +
    'implementation'#10;

  // Beispiel aus #910: das Feld steht in read der Property.
  Kunde =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FKundenName: string;'#10 +
    '    procedure SetName(const Value: string);'#10 +
    '  public'#10 +
    '    property Name: string read FKundenName write SetName;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.SetName(const Value: string);'#10 +
    'begin'#10 +
    '  if Name <> Value then'#10 +
    '    Name := Value;'#10 +
    'end;'#10 +
    'end.';

  KundeFixed =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FKundenName: string;'#10 +
    '    procedure SetName(const Value: string);'#10 +
    '  public'#10 +
    '    property Name: string read FKundenName write SetName;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.SetName(const Value: string);'#10 +
    'begin'#10 +
    '  if FKundenName <> Value then'#10 +
    '    FKundenName := Value;'#10 +
    'end;'#10 +
    'end.';

{ TRecursionRulesTests }

procedure TRecursionRulesTests.SetterExampleIsErrorWithFieldFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde);
  // Das Lesen von Name ruft den Getter (hier ein Feld) nicht rekursiv auf, nur die Zuweisung.
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(SetterRecursionRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Zuweisung an die Property Name im eigenen Setter: Endlosrekursion.', Findings[0].Message);
  Assert.AreEqual(14, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Feld FKundenName verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Assert.AreEqual('FKundenName', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TRecursionRulesTests.GetterUsesFieldOfDeclaration;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := Name;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Lesen der Property Name im eigenen Getter: Endlosrekursion.', Findings[0].Message);
  Assert.AreEqual(15, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Character);
  // Ohne Feld in der Deklaration: F<Name> der Klasse.
  Assert.AreEqual('Feld FName verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual('FName', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TRecursionRulesTests.SetterWithoutFieldHasNoFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Header +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  Self.Title := AValue;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zuweisung an die Property Title im eigenen Setter: Endlosrekursion.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'kein Feld FTitle');
end;

procedure TRecursionRulesTests.FieldAccessIsSilent;
begin
  TRuleAssert.Silent(TSetterRecursionRule.Create, KundeFixed);
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;'#10 +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  FName := AValue + Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.OtherPropertyIsSilent;
begin
  // Ein Setter, der eine andere Property schreibt, ist keine Rekursion.
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  if Name = '''' then'#10 +
    '    FName := AValue;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.SuppressedByComment;
begin
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  // lsp-ignore: setter-recursion'#10 +
    '  Result := Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.FormerIdStillSuppresses;
begin
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  // lsp-ignore: recursive-property-accessor'#10 +
    '  Result := Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.OffAndExcludeSilence;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"setter-recursion": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"setter-recursion": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"setter-recursion": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Kunden.pas'))));
end;

procedure TRecursionRulesTests.FormerIdInSettingsApplies;
var
  Findings: TArray<TRuleFinding>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"recursive-property-accessor": "off"}}', 'Kunden.pas'))));
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"recursive-property-accessor": "warning"}}', 'Kunden.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TRecursionRulesTests.AliasesMapFormerIds;
begin
  Assert.AreEqual('setter-recursion', TRuleIdAliases.Current('recursive-property-accessor'));
  Assert.AreEqual('setter-recursion', TRuleIdAliases.Current('Recursive-Property-Accessor'));
  Assert.AreEqual('self-assignment', TRuleIdAliases.Current('self-assignment'));
end;

procedure TRecursionRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = SetterRecursionRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

{ TUnconditionalRecursionTests }

function RecursionFindings(const ASource: string; const AConfig: string = ''; const APath: string = ''):
  TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TUnconditionalRecursionRule.Create, ASource, AConfig, APath);
end;

function Baum(const ABody: string): string;
begin
  Result := 'unit Baeume;'#10'interface'#10'type'#10'  TBaum = class'#10'    function Tiefe(K: TKnoten): Integer;'#10 +
    '  end;'#10'implementation'#10'function TBaum.Tiefe(K: TKnoten): Integer;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function Routine(const AHeader, ABody: string): string;
begin
  Result := 'unit Hilfen;'#10'interface'#10'implementation'#10 + AHeader + #10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TUnconditionalRecursionTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := RecursionFindings(Baum('  Result := 1 + Max(Tiefe(K.Links), Tiefe(K.Rechts));'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(UnconditionalRecursionRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Assert.AreEqual('Tiefe ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch (z. B. K = nil).',
    Found[0].Message);
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(15, Found[0].Range.StartPos.Character);
end;

procedure TUnconditionalRecursionTests.HintsAndPaths;
var
  Found: TArray<TRuleFinding>;
begin
  Found := RecursionFindings(Routine('function Fakultaet(N: Integer): Int64;', '  Result := N * Fakultaet(N - 1);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Fakultaet ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch (z. B. N <= 0).',
    Found[0].Message);
  Found := RecursionFindings(Routine('function Summe(const W: TArray<Integer>): Integer;', '  Result := Summe(W);'#10));
  Assert.AreEqual('Summe ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch (z. B. Length(W) = 0).',
    Found[0].Message);
  Found := RecursionFindings(Routine('procedure Warten;', '  Sleep(10);'#10'  Warten;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Warten ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch.', Found[0].Message);
  // Aufruf in beiden Zweigen, in repeat, in try und im Vergleich einer while-Bedingung.
  Assert.AreEqual(1, Integer(Length(RecursionFindings(Routine('procedure Laufen(A: Boolean);',
    '  if A then'#10'    Laufen(False)'#10'  else'#10'    Laufen(True);'#10)))), 'if mit else');
  Assert.AreEqual(1, Integer(Length(RecursionFindings(Routine('procedure Laufen(A: Boolean);',
    '  repeat'#10'    Laufen(A);'#10'  until A;'#10)))), 'repeat');
  Assert.AreEqual(1, Integer(Length(RecursionFindings(Routine('procedure Laufen(A: Boolean);',
    '  try'#10'    Laufen(A);'#10'  finally'#10'    Aufraeumen;'#10'  end;'#10)))), 'try');
end;

procedure TUnconditionalRecursionTests.StopsAreSilent;
const
  Bodies: array[0..7] of string = (
    '  if K = nil then'#10'    Exit(0);'#10'  Result := 1 + Max(Tiefe(K.Links), Tiefe(K.Rechts));'#10,
    '  if K <> nil then'#10'    Result := 1 + Tiefe(K.Links)'#10'  else'#10'    Result := 0;'#10,
    '  Result := 0;'#10'  if (K <> nil) and (Tiefe(K.Links) > 0) then'#10'    Result := 1;'#10,
    '  Result := 0;'#10'  while K <> nil do'#10'    Result := Tiefe(K.Links);'#10,
    '  case K.Art of'#10'    1: Result := Tiefe(K.Links);'#10'  else'#10'    Result := 0;'#10'  end;'#10,
    '  if K = nil then'#10'    raise EArgumentNilException.Create(''K'');'#10'  Result := Tiefe(K.Links);'#10,
    '  Result := 0;'#10'  for var I := 0 to K.Anzahl - 1 do'#10'    Result := Tiefe(K.Kind(I));'#10,
    '  Result := 0;'#10'  TThread.Queue(nil, procedure begin Tiefe(K); end);'#10);
var
  Body: string;
begin
  for Body in Bodies do
    Assert.AreEqual(0, Integer(Length(RecursionFindings(Baum(Body)))), Body);
end;

procedure TUnconditionalRecursionTests.OverloadsAndAccessorsAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(RecursionFindings('unit Hilfen;'#10'interface'#10'implementation'#10 +
    'procedure Log(const S: string); overload;'#10'begin'#10'  Writeln(S);'#10'end;'#10 +
    'procedure Log(I: Integer); overload;'#10'begin'#10'  Log(IntToStr(I));'#10'end;'#10'end.'))));
  // Getter der eigenen Property meldet setter-recursion.
  Assert.AreEqual(0, Integer(Length(RecursionFindings(Header + 'function TFoo.GetName: string;'#10'begin'#10 +
    '  Result := Name;'#10'end;'#10'end.'))));
end;

procedure TUnconditionalRecursionTests.OffAndExclude;
var
  Source: string;
begin
  Source := Baum('  Result := Tiefe(K.Links);'#10);
  Assert.AreEqual(1, Integer(Length(RecursionFindings(Source, '', 'Source/Baeume.pas'))));
  Assert.AreEqual(0, Integer(Length(RecursionFindings(Source, '{"rules": {"unconditional-recursion": "off"}}',
    'Source/Baeume.pas'))));
  Assert.AreEqual(0, Integer(Length(RecursionFindings(Source, '{"rules": {"group:find-bugs": "off"}}',
    'Source/Baeume.pas'))));
  Assert.AreEqual(0, Integer(Length(RecursionFindings(Source,
    '{"rules": {"unconditional-recursion": {"exclude": ["Source/*.pas"]}}}', 'Source/Baeume.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnconditionalRecursionTests);
  TDUnitX.RegisterTestFixture(TRecursionRulesTests);

end.
