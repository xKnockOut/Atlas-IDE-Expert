unit Atlas.Common.Rules.Providers.FindingPrompts.Tests;

// Tests des Anbieters der Aufträge zu einem Befund (#158) für andere Features: Regel, Fundstelle und Ausschnitt
// wie TFindingPrompt.Markdown.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleFindingPromptsProviderTests = class
  public
    [Test]
    procedure HasRuleAndSnippet;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.FindingPrompts;

{ TRuleFindingPromptsProviderTests }

procedure TRuleFindingPromptsProviderTests.HasRuleAndSnippet;
var
  mPrompts: IRuleFindingPrompts;
  mFinding: TRuleFinding;
  mText: string;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'empty-except';
  mFinding.Range := TTextRange.Create(2, 2, 2, 8);
  mFinding.Message := 'Leerer except-Block';
  mFinding.Severity := TRuleSeverity.Warning;
  mPrompts := TRuleFindingPromptsProvider.Create;
  mText := mPrompts.Markdown(mFinding, 'U.pas', 'a'#13#10'b'#13#10'c'#13#10'd');
  Assert.Contains(mText, '## Befund empty-except');
  Assert.Contains(mText, 'Zeile 3, Spalte 3');
  Assert.Contains(mText, '>    3 | c');
  Assert.Contains(mText, '```pascal');
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleFindingPromptsProviderTests);

end.
