unit Atlas.Common.Rules.Builtin.ForwardDeclarations.Tests;

// Tests für type-used-before-declaration und unneeded-forward-declaration (#685).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TForwardDeclarationRulesTests = class
  public
    [Test]
    procedure UsedBeforeIsErrorWithFix;
    [Test]
    procedure ReasonWithoutFix;
    [Test]
    procedure UnneededIsHintWithSafeFix;
    [Test]
    procedure SwitchedOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.ForwardDeclarations,
  Atlas.Tests.RuleAssert;

const
  Tree = 'unit U;'#10'interface'#10'type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10 +
    '  TNode = class'#10'  end;'#10'implementation'#10'end.';

procedure TForwardDeclarationRulesTests.UsedBeforeIsErrorWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTypeUsedBeforeDeclarationRule.Create, Tree);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual('"TNode" wird in TTree benutzt, bevor es deklariert ist', Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Forward-Deklaration ergänzen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Assert.AreEqual('  TNode = class;'#10, Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TUnneededForwardDeclarationRule.Create, Tree);
end;

procedure TForwardDeclarationRulesTests.ReasonWithoutFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTypeUsedBeforeDeclarationRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10'var'#10'  Baum: TTree;'#10'type'#10'  TNode = class'#10 +
    '  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'keine Korrektur');
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TForwardDeclarationRulesTests.UnneededIsHintWithSafeFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUnneededForwardDeclarationRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TNode = class;'#10'  TNode = class'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.Contains(Findings[0].Message, 'TNode');
  Assert.AreEqual('Forward-Deklaration entfernen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
end;

procedure TForwardDeclarationRulesTests.SwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTypeUsedBeforeDeclarationRule.Create, Tree,
    '{"refactoring": {"forwardDeclaration": false}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnneededForwardDeclarationRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TNode = class;'#10'  TNode = class'#10'  end;'#10'implementation'#10'end.',
    '{"refactoring": {"forwardDeclaration": false}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TForwardDeclarationRulesTests);

end.
