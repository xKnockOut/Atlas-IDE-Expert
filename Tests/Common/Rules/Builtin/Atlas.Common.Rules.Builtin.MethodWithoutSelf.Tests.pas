unit Atlas.Common.Rules.Builtin.MethodWithoutSelf.Tests;

// Tests der Regel method-without-self (#686): Treffer samt Korrektur „In
// class-Methode umwandeln“, Methoden mit Feldern bleiben stumm, die Regel ist
// experimentell, schweigt mit refactoring.methodKind aus und bei Ereignissen
// der Formulardatei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodWithoutSelfRuleTests = class
  public
    [Test]
    procedure ReportsWithClassMethodFix;
    [Test]
    procedure MethodWithFieldIsSilent;
    [Test]
    procedure ExperimentalAndSwitchedOff;
    [Test]
    procedure FormEventIsSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.MethodWithoutSelf,
  Atlas.Tests.RuleAssert;

const
  Enabled = '{ "rules": { "method-without-self": "hint" } }';
  Source =
    'unit Rechner;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '  public'#10 +
    '    function Doppelt(A: Integer): Integer;'#10 +
    '    function Wert: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TRechner.Doppelt(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'function TRechner.Wert: Integer;'#10 +
    'begin'#10 +
    '  Result := FWert;'#10 +
    'end;'#10 +
    'end.';

function Rule: IRule;
begin
  Result := TMethodWithoutSelfRule.Create;
end;

procedure TMethodWithoutSelfRuleTests.ReportsWithClassMethodFix;
var
  Found: TArray<TRuleFinding>;
  Edit: TTextEdit;
  Inserted: string;
begin
  Found := TRuleAssert.Findings(Rule, Source, Enabled);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('method-without-self', Found[0].RuleId);
  Assert.AreEqual(11, Found[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('TRechner.Doppelt', Found[0].Message) > 0, Found[0].Message);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In class-Methode umwandeln', Found[0].Fixes[0].Title);
  Assert.IsFalse(Found[0].Fixes[0].Safe);
  Inserted := '';
  for Edit in Found[0].Fixes[0].Edits do
    Inserted := Inserted + Edit.NewText + '|';
  Assert.IsTrue(Pos('class ', Inserted) > 0, Inserted);
  Assert.IsTrue(Pos('static;', Inserted) > 0, Inserted);
end;

procedure TMethodWithoutSelfRuleTests.MethodWithFieldIsSilent;
var
  Found: TArray<TRuleFinding>;
  Finding: TRuleFinding;
begin
  Found := TRuleAssert.Findings(Rule, Source, Enabled);
  for Finding in Found do
    Assert.IsTrue(Pos('TRechner.Wert', Finding.Message) = 0, Finding.Message);
end;

procedure TMethodWithoutSelfRuleTests.ExperimentalAndSwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, Source))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, Source,
    '{ "rules": { "method-without-self": "hint" }, "refactoring": { "methodKind": false } }'))));
end;

procedure TMethodWithoutSelfRuleTests.FormEventIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(Rule, Source,
    'object Rechner: TRechner'#10'  OnClick = Doppelt'#10'end', Enabled))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.FormFindings(Rule, Source,
    'object Rechner: TRechner'#10'end', Enabled))));
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodWithoutSelfRuleTests);

end.
