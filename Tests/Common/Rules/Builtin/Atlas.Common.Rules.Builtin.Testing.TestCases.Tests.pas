unit Atlas.Common.Rules.Builtin.Testing.TestCases.Tests;

// Tests der Regel dunitx-testcase-mismatch (#1882): Zahl der Werte, Werte zum Typ (Ganzzahl, Gleitkomma mit
// eigenem Trennzeichen, Boolean, Aufzählung der Datei), Methode ohne Parameter, neue Formen TestCase('Werte') und
// NamedTestCase, stille Fälle (keine Testunit, Werte kein Literal, unbekannter Typ) und die Hilfen von
// TDUnitXTestCases.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXTestCaseMismatchTests = class
  public
    [Test]
    procedure CountMismatchNamesBothNumbers;
    [Test]
    procedure ValueMustFitParameterType;
    [Test]
    procedure MethodWithoutParameters;
    [Test]
    procedure NewerFormsOfDUnitX;
    [Test]
    procedure SilentCases;
    [Test]
    procedure SplitAndDecodeLikeDUnitX;
    [Test]
    procedure ClassesWithTheirAttributes;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Builtin.Testing.Classes,
  Atlas.Common.Rules.Builtin.Testing.TestCases,
  Atlas.Tests.RuleAssert;

/// <summary>Testunit mit den Attributen AAttributes vor der Methode Pruefe(AParameters).</summary>
function TestUnit(const AAttributes, AParameters: string): string;
begin
  Result := 'unit Fall.Tests;'#10'interface'#10'uses'#10'  DUnitX.TestFramework;'#10'type'#10 +
    '  TFarbe = (Rot, Gruen);'#10'  TStufe = (Eins = 1, Zwei = 2);'#10 +
    '  [TestFixture]'#10'  TFallTests = class'#10'  public'#10 + AAttributes + '    procedure Pruefe' + AParameters +
    ';'#10'  end;'#10'implementation'#10'procedure TFallTests.Pruefe' + AParameters + ';'#10'begin'#10 +
    '  Assert.Pass;'#10'end;'#10'initialization'#10'  TDUnitX.RegisterTestFixture(TFallTests);'#10'end.';
end;

function Messages(const ASource: string): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in TRuleAssert.Findings(TDUnitXTestCaseMismatchRule.Create, ASource, '', 'Fall.Tests.pas') do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message;
  end;
end;

{ TDUnitXTestCaseMismatchTests }

procedure TDUnitXTestCaseMismatchTests.CountMismatchNamesBothNumbers;
begin
  Assert.AreEqual('10: [TestCase(''Rest'',''7,2'')] hat 2 Werte, Pruefe erwartet 3 Parameter.',
    Messages(TestUnit('    [TestCase(''Rest'',''7,2'')]'#10, '(A, B: Integer; const C: Integer)')));
  // Leerer Werte-Text ergibt keinen Wert; ein Komma zu viel einen leeren.
  Assert.AreEqual('10: [TestCase(''Leer'', '''')] hat 0 Werte, Pruefe erwartet 1 Parameter. | ' +
    '11: [TestCase(''Zwei'', ''1,'')] hat 2 Werte, Pruefe erwartet 1 Parameter.',
    Messages(TestUnit('    [TestCase(''Leer'', '''')]'#10'    [TestCase(''Zwei'', ''1,'')]'#10, '(A: string)')));
  Assert.AreEqual('', Messages(TestUnit('    [TestCase(''Passt'',''7,2,1'')]'#10, '(A, B: Integer; C: Integer)')));
end;

procedure TDUnitXTestCaseMismatchTests.ValueMustFitParameterType;
begin
  Assert.AreEqual('10: Wert ''drei'' passt nicht zu Parameter C: Integer.',
    Messages(TestUnit('    [TestCase(''Rest'',''7,2,drei'')]'#10, '(A, B, C: Integer)')));
  // Gleitkomma mit Punkt; mit eigenem Trennzeichen auch mit Komma (DUnitX macht einen Punkt daraus).
  Assert.AreEqual('', Messages(TestUnit('    [TestCase(''Punkt'',''3.5,1e3'')]'#10 +
    '    [TestCase(''Komma'',''3,5;-2'', '';'')]'#10, '(const A: Double; B: Single)')));
  Assert.AreEqual('10: Wert ''3x'' passt nicht zu Parameter A: Double.',
    Messages(TestUnit('    [TestCase(''Fehler'',''3x,1'')]'#10, '(const A: Double; B: Single)')));
  // Hex, Vorzeichen und Leerzeichen bei Ganzzahlen.
  Assert.AreEqual('', Messages(TestUnit('    [TestCase(''Hex'',''$FF, -3,0x10'')]'#10, '(A, B: Integer; C: Int64)')));
  Assert.AreEqual('10: Wert ''ja'' passt nicht zu Parameter A: Boolean.',
    Messages(TestUnit('    [TestCase(''Bool'',''ja,True'')]'#10, '(A, B: Boolean)')));
  Assert.AreEqual('10: Wert ''Blau'' passt nicht zu Parameter F: TFarbe (erlaubt: Rot, Gruen).',
    Messages(TestUnit('    [TestCase(''Farbe'',''Blau'')]'#10'    [TestCase(''Gut'',''gruen'')]'#10, '(F: TFarbe)')));
  // Aufzählung mit festen Werten (keine RTTI) und unbekannter Typ: keine Prüfung.
  Assert.AreEqual('', Messages(TestUnit('    [TestCase(''Fest'',''Drei,x'')]'#10, '(S: TStufe; F: TFremd)')));
end;

procedure TDUnitXTestCaseMismatchTests.MethodWithoutParameters;
begin
  Assert.AreEqual('10: [TestCase(''A'', ''1'')] an Pruefe, die keine Parameter hat: DUnitX kann die Werte nicht ' +
    'übergeben.', Messages(TestUnit('    [TestCase(''A'', ''1'')]'#10, '')));
end;

procedure TDUnitXTestCaseMismatchTests.NewerFormsOfDUnitX;
begin
  // TestCase('Werte'[, 'Trenner'[, Trim]]) und NamedTestCase('Name', 'Werte').
  Assert.AreEqual('', Messages(TestUnit('    [TestCase(''1,2'')]'#10'    [TestCase(''1;2'', '';'')]'#10 +
    '    [TestCase(''1, 2'', '','', True)]'#10'    [NamedTestCase(''Name'', ''1,2'')]'#10, '(A, B: Integer)')));
  Assert.AreEqual('10: [TestCase(''1,2,3'')] hat 3 Werte, Pruefe erwartet 2 Parameter. | ' +
    '11: Wert ''x'' passt nicht zu Parameter A: Integer.',
    Messages(TestUnit('    [TestCase(''1,2,3'')]'#10'    [NamedTestCase(''N'', ''x,2'')]'#10, '(A, B: Integer)')));
  // Qualifizierter Name mit Endung Attribute.
  Assert.AreEqual('10: [DUnitX.TestFramework.TestCaseAttribute(''A'', ''1'')] hat 1 Werte, Pruefe erwartet 2 ' +
    'Parameter.', Messages(TestUnit('    [DUnitX.TestFramework.TestCaseAttribute(''A'', ''1'')]'#10,
    '(A, B: Integer)')));
end;

procedure TDUnitXTestCaseMismatchTests.SilentCases;
var
  mSource: string;
begin
  // Keine Testunit.
  mSource := StringReplace(TestUnit('    [TestCase(''Rest'',''7,2'')]'#10, '(A, B, C: Integer)'),
    'DUnitX.TestFramework', 'System.Classes', []);
  Assert.AreEqual('', Messages(mSource));
  // Werte aus einer Konstanten bzw. zusammengesetzt: unbekannt.
  Assert.AreEqual('', Messages(TestUnit('    [TestCase(''A'', cWerte)]'#10'    [TestCase(''B'', ''1'' + ''2'')]'#10,
    '(A, B, C: Integer)')));
end;

procedure TDUnitXTestCaseMismatchTests.SplitAndDecodeLikeDUnitX;
var
  mValue: string;
begin
  Assert.AreEqual(0, Integer(Length(TDUnitXTestCases.Split('', ','))));
  Assert.AreEqual(3, Integer(Length(TDUnitXTestCases.Split('a;b,c', ';,'))));
  Assert.AreEqual('"a', TDUnitXTestCases.Split('"a,b"', ',')[0]);
  Assert.IsTrue(TDUnitXTestCases.Decode('''it''''s''#9''x''', mValue));
  Assert.AreEqual('it''s'#9'x', mValue);
  Assert.IsFalse(TDUnitXTestCases.Decode('cWerte', mValue));
  mValue := '';
end;

procedure TDUnitXTestCaseMismatchTests.ClassesWithTheirAttributes;
var
  mTree: TSyntaxTree;
  mClasses: TArray<TDUnitXClass>;
begin
  mTree := TSyntaxTreeCache.Parse(TestUnit('    [Test, TestCase(''A'', ''1'')]'#10, '(A: Integer)'));
  try
    mClasses := TDUnitXClasses.Collect(mTree.Root);
    Assert.AreEqual(1, Integer(Length(mClasses)));
    Assert.AreEqual('TFallTests', mClasses[0].Name);
    Assert.IsTrue(mClasses[0].HasAttribute('TestFixture'));
    Assert.IsFalse(mClasses[0].IsGeneric);
    Assert.AreEqual(1, Integer(Length(mClasses[0].Members)));
    Assert.AreEqual(2, Integer(Length(mClasses[0].Members[0].Attributes)));
    Assert.IsTrue(mClasses[0].HasMemberWith(['TestCase']));
    Assert.AreEqual(2, Integer(Length(TDUnitXClasses.Arguments(mClasses[0].Members[0].Attributes[1]))));
  finally
    mTree.Free;
  end;
  mTree := TSyntaxTreeCache.Parse('unit U;'#10'interface'#10'type'#10'  [TestFixture]'#10 +
    '  TKind<T> = class(Basis.TFallTests)'#10'  end;'#10'implementation'#10'end.');
  try
    mClasses := TDUnitXClasses.Collect(mTree.Root);
    Assert.AreEqual(1, Integer(Length(mClasses)));
    Assert.IsTrue(mClasses[0].IsGeneric);
    Assert.AreEqual('Basis.TFallTests', mClasses[0].Ancestor);
  finally
    mTree.Free;
  end;
end;

procedure TDUnitXTestCaseMismatchTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    mFound := mFound or (mRule.Descriptor.Id = cDUnitXTestCaseMismatchRuleId);
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXTestCaseMismatchTests);

end.
