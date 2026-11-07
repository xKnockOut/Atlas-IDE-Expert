unit Atlas.Common.Rules.Builtin.Flow.OutParamRead.Tests;

// Tests der Teilunit out-param-read: Lesen vor dem Setzen, verwaltete Typen, Übergabe eines Teils, Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowOutParamReadTests = class
  public
    [Test]
    procedure ReadBeforeSetIsReported;
    [Test]
    procedure ManagedTypeSaysEmpty;
    [Test]
    procedure SetBeforeReadIsSilent;
    [Test]
    procedure PassedPartIsSilent;
    [Test]
    procedure SecondNameIsChecked;
    [Test]
    procedure FixReplacesDeclarationAndImplementation;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.OutParamRead,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(out AParams)", deklariert im interface, und dem Rumpf ABody.</summary>
function Routine(const AParams, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'procedure P(out ' + AParams + ');'#10'implementation'#10 +
    'procedure Lies(var A: TPoint);'#10'begin'#10'end;'#10'procedure P(out ' + AParams + ');'#10'begin'#10 +
    ABody + #10'end;'#10'end.';
end;

procedure TFlowOutParamReadTests.ReadBeforeSetIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOutParamReadRule.Create, Routine('N: Integer', '  N := N + 1;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cOutParamReadRuleId, mFindings[0].RuleId);
  Assert.AreEqual('out-Parameter N wird gelesen, bevor er gesetzt ist; sein Wert ist hier undefiniert.',
    mFindings[0].Message);
end;

procedure TFlowOutParamReadTests.ManagedTypeSaysEmpty;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOutParamReadRule.Create, Routine('S: string', '  S := S + ''x'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('out-Parameter S wird gelesen, bevor er gesetzt ist; bei string ist er hier immer leer.',
    mFindings[0].Message);
end;

procedure TFlowOutParamReadTests.SetBeforeReadIsSilent;
begin
  TRuleAssert.Silent(TOutParamReadRule.Create, Routine('N: Integer', '  N := 1;'#10'  N := N + 1;'));
end;

procedure TFlowOutParamReadTests.PassedPartIsSilent;
begin
  TRuleAssert.Silent(TOutParamReadRule.Create, Routine('R: TRect', '  Lies(R.TopLeft);'#10 +
    '  R.Left := R.Right;'));
end;

procedure TFlowOutParamReadTests.SecondNameIsChecked;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOutParamReadRule.Create, Routine('A, B: Integer',
    '  A := 1;'#10'  B := B + A;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('out-Parameter B wird gelesen, bevor er gesetzt ist; sein Wert ist hier undefiniert.',
    mFindings[0].Message);
end;

procedure TFlowOutParamReadTests.FixReplacesDeclarationAndImplementation;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOutParamReadRule.Create, Routine('N: Integer', '  N := N + 1;'));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes[0].Edits)));
  Assert.AreEqual('var', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(2, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowOutParamReadTests);

end.
