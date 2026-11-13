unit Atlas.Common.Rules.Builtin.Testing.Attributes.Tests;

// Tests der Regeln dunitx-ignore-without-reason, dunitx-category-empty, dunitx-fixture-without-test und
// dunitx-duplicate-attribute (#154): Treffer, stille Fälle (Begründung, Name, published-Methoden, geerbte Tests,
// verschiedene TestCase-Argumente), Korrektur für doppelte Attribute und Testunits ohne DUnitX.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXAttributeRulesTests = class
  public
    [Test]
    procedure IgnoreWithoutReason;
    [Test]
    procedure CategoryEmpty;
    [Test]
    procedure FixtureWithoutTest;
    [Test]
    procedure DuplicateAttribute;
    [Test]
    procedure RemoveDuplicate;
    [Test]
    procedure SilentOutsideTests;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Builtin.Testing.Attributes,
  Atlas.Tests.RuleAssert;

/// <summary>Testunit mit den Typdeklarationen ADecls (ab Zeile 5).</summary>
function TestUnit(const ADecls: string): string;
begin
  Result := 'unit Fall.Tests;'#10'interface'#10'uses'#10'  DUnitX.TestFramework;'#10'type'#10 + ADecls +
    'implementation'#10'end.';
end;

/// <summary>Testklasse TFallTests mit den Mitgliedern AMembers (ab Zeile 8).</summary>
function Fixture(const AMembers: string): string;
begin
  Result := TestUnit('  [TestFixture]'#10'  TFallTests = class'#10'  public'#10 + AMembers + '  end;'#10);
end;

function Messages(ARule: IRule; const ASource: string): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in TRuleAssert.Findings(ARule, ASource, '', 'Fall.Tests.pas') do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message;
  end;
end;

function Fixed(const ASource: string): string;
var
  mFound: TArray<TRuleFinding>;
begin
  Result := '';
  mFound := TRuleAssert.Findings(TDUnitXDuplicateAttributeRule.Create, ASource, '', 'Fall.Tests.pas');
  if (Length(mFound) = 1) and (Length(mFound[0].Fixes) = 1) then
  begin
    Result := TChangeSignature.ApplyEdits(ASource, mFound[0].Fixes[0].Edits);
  end;
end;

{ TDUnitXAttributeRulesTests }

procedure TDUnitXAttributeRulesTests.IgnoreWithoutReason;
begin
  Assert.AreEqual('8: [Ignore] ohne Begründung: Der Testbericht sagt nicht, warum TFallTests.A nicht läuft und ' +
    'wann der Test wieder an darf. | 11: [Ignore] ohne Begründung: Der Testbericht sagt nicht, warum TFallTests.B ' +
    'nicht läuft und wann der Test wieder an darf.', Messages(TDUnitXIgnoreWithoutReasonRule.Create,
    Fixture('    [Test, Ignore]'#10'    procedure A;'#10'    [Test]'#10'    [DUnitX.TestFramework.IgnoreAttribute(' +
    ''' '')]'#10'    procedure B;'#10'    [Test]'#10'    [Ignore(''Wartet auf #12'')]'#10'    procedure C;'#10 +
    '    [Test]'#10'    [Ignore(cGrund)]'#10'    procedure D;'#10)));
end;

procedure TDUnitXAttributeRulesTests.CategoryEmpty;
begin
  Assert.AreEqual('8: [Category] ohne Namen: TFallTests.A landet in keiner Kategorie, ein Filter findet den Test ' +
    'nie. | 10: [Category] ohne Namen: TFallTests.B landet in keiner Kategorie, ein Filter findet den Test nie.',
    Messages(TDUnitXCategoryEmptyRule.Create, Fixture('    [Test, Category('''')]'#10'    procedure A;'#10 +
    '    [Test, Category('' , '')]'#10'    procedure B;'#10'    [Test, Category(''Schnell,Langsam'')]'#10 +
    '    procedure C;'#10)));
end;

procedure TDUnitXAttributeRulesTests.FixtureWithoutTest;
begin
  Assert.AreEqual('6: TLeer hat [TestFixture], aber keine [Test]-, [TestCase]- oder published-Methode: Die Klasse ' +
    'läuft leer. | 21: TLeerZwei hat [TestFixture], aber keine [Test]-, [TestCase]- oder published-Methode: Die ' +
    'Klasse läuft leer.', Messages(TDUnitXFixtureWithoutTestRule.Create, TestUnit(
    '  [TestFixture]'#10'  TLeer = class'#10'  public'#10'    procedure Hilf;'#10'  end;'#10 +
    '  [TestFixture]'#10'  TVeroeffentlicht = class'#10'  published'#10'    procedure Pruefe;'#10'  end;'#10 +
    '  TBasis = class'#10'  public'#10'    [Test]'#10'    procedure Pruefe;'#10'  end;'#10 +
    '  [TestFixture]'#10'  TLeerZwei = class(TObject)'#10'  end;'#10 +
    '  [TestFixture]'#10'  TAbgeleitet = class(TBasis)'#10'  end;'#10 +
    '  [TestFixture]'#10'  TFremd = class(TAndereBasis)'#10'  end;'#10 +
    '  [TestFixture]'#10'  TMitFall = class'#10'  public'#10'    [TestCase(''A'', ''1'')]'#10 +
    '    procedure Pruefe(A: Integer);'#10'  end;'#10)));
end;

procedure TDUnitXAttributeRulesTests.DuplicateAttribute;
begin
  Assert.AreEqual('9: [Test] steht zweimal an TFallTests.A. | 12: [TestCase] steht zweimal an TFallTests.B.',
    Messages(TDUnitXDuplicateAttributeRule.Create,
    TestUnit('  [TestFixture]'#10'  TFallTests = class'#10'  public'#10'    [Test]'#10'    [Test]'#10 +
    '    procedure A;'#10'    [TestCase(''a'',''1'')]'#10'    [TestCase(''a'', ''1'')]'#10 +
    '    procedure B(X: Integer);'#10'  end;'#10)));
  // Gleicher Name, andere Argumente: TestCase und Category dürfen mehrfach stehen.
  Assert.AreEqual('', Messages(TDUnitXDuplicateAttributeRule.Create, Fixture('    [TestCase(''a'', ''1'')]'#10 +
    '    [TestCase(''b'', ''2'')]'#10'    [Category(''x''), Category(''y'')]'#10'    procedure A(X: Integer);'#10 +
    '    [Eigenes, Eigenes]'#10'    procedure B;'#10)));
end;

procedure TDUnitXAttributeRulesTests.RemoveDuplicate;
begin
  // Eigene Zeile: die Zeile; in einer Liste: samt Komma; neben anderem: samt Leerraum.
  Assert.AreEqual(Fixture('    [Test]'#10'    procedure A;'#10), Fixed(Fixture('    [Test]'#10'    [Test]'#10 +
    '    procedure A;'#10)));
  Assert.AreEqual(Fixture('    [Test, Ignore(''x'')]'#10'    procedure A;'#10),
    Fixed(Fixture('    [Test, Ignore(''x''), Test]'#10'    procedure A;'#10)));
  Assert.AreEqual(Fixture('    [Test] procedure A;'#10), Fixed(Fixture('    [Test] [Test] procedure A;'#10)));
end;

procedure TDUnitXAttributeRulesTests.SilentOutsideTests;
begin
  Assert.AreEqual('', Messages(TDUnitXIgnoreWithoutReasonRule.Create, StringReplace(Fixture('    [Test, Ignore]'#10 +
    '    procedure A;'#10), 'DUnitX.TestFramework', 'System.Classes', [])));
end;

procedure TDUnitXAttributeRulesTests.RulesAreRegistered;
var
  mRule: IRule;
  mFound: Integer;
begin
  mFound := 0;
  for mRule in BuiltinRules do
  begin
    if MatchText(mRule.Descriptor.Id, [cDUnitXIgnoreWithoutReasonRuleId, cDUnitXCategoryEmptyRuleId,
      cDUnitXFixtureWithoutTestRuleId, cDUnitXDuplicateAttributeRuleId]) then
    begin
      Inc(mFound);
    end;
  end;
  Assert.AreEqual(4, mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXAttributeRulesTests);

end.
