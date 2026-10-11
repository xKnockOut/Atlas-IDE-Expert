unit Atlas.Common.Rules.Builtin.Unicode.Tests;

// Tests für die Unicode-Regeln (#150): je Regel positive und negative Fälle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnicodeRuleTests = class
  public
    [Test]
    procedure BidiControlInCommentReported;
    [Test]
    procedure BidiControlPosition;
    [Test]
    procedure PlainCodeHasNoBidiControl;
    [Test]
    procedure ZeroWidthSpaceReported;
    [Test]
    procedure LeadingBomIsAllowed;
    [Test]
    procedure NulAndReplacementCharReported;
    [Test]
    procedure TabsAndLineBreaksAreFine;
    [Test]
    procedure MixedScriptIdentifierReported;
    [Test]
    procedure UmlautIdentifierHiddenByDefault;
    [Test]
    procedure UmlautIdentifierShownWithLowThreshold;
    [Test]
    procedure AsciiIdentifierSilent;
    [Test]
    procedure RegistersAllRules;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Unicode,
  Atlas.Tests.RuleAssert;

function UnitWith(const ABody: string): string;
begin
  Result := 'unit U;'#13#10'interface'#13#10'implementation'#13#10 + ABody + #13#10'end.';
end;

{ TUnicodeRuleTests }

procedure TUnicodeRuleTests.BidiControlInCommentReported;
begin
  TRuleAssert.Reports(TBidiControlRule.Create, UnitWith('// Zugriff ' + Char($202E) + ' { ' + Char($2066) + ' }'), 2);
end;

procedure TUnicodeRuleTests.BidiControlPosition;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TBidiControlRule.Create, UnitWith('const S = ''a' + Char($202E) + 'b'';'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
end;

procedure TUnicodeRuleTests.PlainCodeHasNoBidiControl;
begin
  TRuleAssert.Silent(TBidiControlRule.Create, UnitWith('const S = ''Größe: äöü'';'));
end;

procedure TUnicodeRuleTests.ZeroWidthSpaceReported;
begin
  TRuleAssert.Reports(TInvisibleCharRule.Create, UnitWith('const S = ''a' + Char($200B) + 'b'';'));
end;

procedure TUnicodeRuleTests.LeadingBomIsAllowed;
begin
  TRuleAssert.Silent(TInvisibleCharRule.Create, Char($FEFF) + UnitWith(''));
end;

procedure TUnicodeRuleTests.NulAndReplacementCharReported;
begin
  TRuleAssert.Reports(TControlCharRule.Create, UnitWith('// a'#0'b ' + Char($FFFD)), 2);
end;

procedure TUnicodeRuleTests.TabsAndLineBreaksAreFine;
begin
  TRuleAssert.Silent(TControlCharRule.Create, UnitWith(#9'// Tab'#10'// LF'#12));
end;

procedure TUnicodeRuleTests.MixedScriptIdentifierReported;
var
  Findings: TArray<TRuleFinding>;
begin
  // "Pаssword" mit kyrillischem а (U+0430)
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create,
    UnitWith('var P' + Char($0430) + 'ssword: Integer;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TUnicodeRuleTests.UmlautIdentifierHiddenByDefault;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, UnitWith('var Größe: Integer;'));
end;

procedure TUnicodeRuleTests.UmlautIdentifierShownWithLowThreshold;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var Größe: Integer;'),
    '{ "minConfidence": "low" }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
end;

procedure TUnicodeRuleTests.AsciiIdentifierSilent;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, UnitWith('var Password: Integer;'));
end;

procedure TUnicodeRuleTests.RegistersAllRules;
var
  Registry: TRuleRegistry;
  Rule: IRule;
begin
  Registry := TRuleRegistry.Create;
  try
    RegisterUnicodeRules(Registry);
    Assert.AreEqual(4, Integer(Length(Registry.Rules)));
    Assert.IsTrue(Registry.Find('bidi-control', Rule));
    Assert.IsTrue(Registry.Find('confusable-identifier', Rule));
  finally
    Registry.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnicodeRuleTests);

end.
