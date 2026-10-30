unit Atlas.Common.Rules.Builtin.Testing.Tests;

// Tests der Regel dunitx-test-without-assert (#945): Test ohne Prüfung,
// Prüfung in Hilfsmethoden und Routinen der Unit, eigene Prüfklassen,
// WillRaise und Ignore, Korrekturen, Optionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestingRulesTests = class
  public
    [Test]
    procedure IssueExampleReported;
    [Test]
    procedure FixesInsertPassAndJump;
    [Test]
    procedure AssertsAreFound;
    [Test]
    procedure HelperMethodsAreFollowed;
    [Test]
    procedure WillRaiseAndIgnoreAreSilent;
    [Test]
    procedure AssertPatternsOption;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure IsAssertion;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Testing,
  Atlas.Tests.RuleAssert;

function TestUnit(const ABody: string): string;
begin
  Result :=
    'unit ImportTests;'#10 +
    'interface'#10 +
    'type'#10 +
    '  [TestFixture]'#10 +
    '  TImportTests = class'#10 +
    '  public'#10 +
    '    [Test]'#10 +
    '    procedure LeereDateiWirdGelesen;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TImportTests.LeereDateiWirdGelesen;'#10 +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

{ TTestingRulesTests }

procedure TTestingRulesTests.IssueExampleReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDUnitXTestWithoutAssertRule.Create,
    TestUnit('  FImport.Laden(''leer.csv'');'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('dunitx-test-without-assert', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Der Test prüft nichts; er ist immer grün.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(14, Findings[0].Range.StartPos.Character);
  // Korrigierte Form.
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, TestUnit('  FImport.Laden(''leer.csv'');'#10 +
    '  Assert.AreEqual(0, FImport.Anzahl);'#10));
end;

procedure TTestingRulesTests.FixesInsertPassAndJump;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDUnitXTestWithoutAssertRule.Create,
    TestUnit('  FImport.Laden(''leer.csv'');'#10));
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Assert.Pass; als Platzhalter einfügen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(13, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('  Assert.Pass;'#10, Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('Zur Methode springen', Findings[0].Fixes[1].Title);
  Assert.IsTrue(Findings[0].Fixes[1].HasJump);
  Assert.AreEqual(10, Findings[0].Fixes[1].JumpTo.Line);
end;

procedure TTestingRulesTests.AssertsAreFound;
begin
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, TestUnit('  Assert.WillRaise(Laden, EImport);'#10));
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, TestUnit('  CheckEquals(1, 1);'#10));
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, TestUnit('  System.Assert(FImport <> nil);'#10));
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, TestUnit('  TRuleAssert.Silent(TRegel.Create, X);'#10));
  // Nur im Kommentar: gemeldet.
  TRuleAssert.Reports(TDUnitXTestWithoutAssertRule.Create, TestUnit('  // Assert.IsTrue(X);'#10'  Laden;'#10));
  // Prüfung in einer lokalen Routine des Tests.
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, StringReplace(TestUnit('  Pruefe(1);'#10),
    'LeereDateiWirdGelesen;'#10'begin', 'LeereDateiWirdGelesen;'#10'  procedure Pruefe(A: Integer);'#10'  begin'#10 +
    '    Assert.IsTrue(A > 0);'#10'  end;'#10'begin', []));
end;

procedure TTestingRulesTests.HelperMethodsAreFollowed;
const
  Source =
    'unit ImportTests;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TImportTests = class'#10 +
    '  private'#10 +
    '    procedure Pruefen(const AName: string);'#10 +
    '  public'#10 +
    '    [Test]'#10 +
    '    procedure Erster;'#10 +
    '    [TestCase(''a'', ''1'')]'#10 +
    '    procedure Zweiter(const A: string);'#10 +
    '    procedure KeinTest;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure Vergleichen;'#10 +
    'begin'#10 +
    '  Assert.AreEqual(1, 1);'#10 +
    'end;'#10 +
    'procedure TImportTests.Pruefen(const AName: string);'#10 +
    'begin'#10 +
    '  Assert.IsNotEmpty(AName);'#10 +
    'end;'#10 +
    'procedure TImportTests.Erster;'#10 +
    'begin'#10 +
    '  Self.Pruefen(''x'');'#10 +
    'end;'#10 +
    'procedure TImportTests.Zweiter(const A: string);'#10 +
    'begin'#10 +
    '  Vergleichen;'#10 +
    'end;'#10 +
    'procedure TImportTests.KeinTest;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
begin
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, Source);
  // Ohne Prüfung im Helfer meldet die Regel den TestCase.
  TRuleAssert.Reports(TDUnitXTestWithoutAssertRule.Create, StringReplace(Source, '  Assert.AreEqual(1, 1);'#10,
    '  Laden;'#10, []));
end;

procedure TTestingRulesTests.WillRaiseAndIgnoreAreSilent;
begin
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, StringReplace(TestUnit('  Laden;'#10), '    [Test]'#10,
    '    [Test]'#10'    [WillRaise(EImport)]'#10, []));
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, StringReplace(TestUnit('  Laden;'#10), '    [Test]'#10,
    '    [Test, Ignore(''später'')]'#10, []));
  // Ohne Attribut Test kein Test.
  TRuleAssert.Silent(TDUnitXTestWithoutAssertRule.Create, StringReplace(TestUnit('  Laden;'#10), '    [Test]'#10,
    '', []));
end;

procedure TTestingRulesTests.AssertPatternsOption;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := TestUnit('  Expect(Laden).ToBe(1);'#10);
  TRuleAssert.Reports(TDUnitXTestWithoutAssertRule.Create, Source);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDUnitXTestWithoutAssertRule.Create, Source,
    '{"rules": {"dunitx-test-without-assert": {"assertPatterns": ["Expect"]}}}'))));
  // Eigene Muster ersetzen die Vorgabe.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDUnitXTestWithoutAssertRule.Create,
    TestUnit('  CheckEquals(1, 1);'#10), '{"rules": {"dunitx-test-without-assert": {"assertPatterns": ["Expect"]}}}'))));
  TConfigurationParser.Parse('{"rules": {"dunitx-test-without-assert": {"assertPatterns": "Expect"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

procedure TTestingRulesTests.OffAndExclude;
var
  Source: string;
begin
  Source := TestUnit('  Laden;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDUnitXTestWithoutAssertRule.Create, Source,
    '{"rules": {"dunitx-test-without-assert": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDUnitXTestWithoutAssertRule.Create, Source,
    '{"rules": {"dunitx-test-without-assert": {"exclude": ["Tests/*.pas"]}}}', 'Tests/ImportTests.pas'))));
end;

procedure TTestingRulesTests.IsAssertion;
begin
  Assert.IsTrue(TDUnitXTestWithoutAssertRule.IsAssertion('Assert.AreEqual',
    TDUnitXTestWithoutAssertRule.DefaultPatterns));
  Assert.IsTrue(TDUnitXTestWithoutAssertRule.IsAssertion('WillRaiseAny', TDUnitXTestWithoutAssertRule.DefaultPatterns));
  Assert.IsTrue(TDUnitXTestWithoutAssertRule.IsAssertion('TJsonAssert.Equal', nil));
  Assert.IsTrue(TDUnitXTestWithoutAssertRule.IsAssertion('Assert', nil));
  Assert.IsFalse(TDUnitXTestWithoutAssertRule.IsAssertion('Laden', TDUnitXTestWithoutAssertRule.DefaultPatterns));
  Assert.IsFalse(TDUnitXTestWithoutAssertRule.IsAssertion('FAssert', nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestingRulesTests);

end.
