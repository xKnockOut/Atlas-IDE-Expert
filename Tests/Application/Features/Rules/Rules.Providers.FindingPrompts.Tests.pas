unit Rules.Providers.FindingPrompts.Tests;

// Tests des Anbieters der Aufträge an KI-Assistenten: zu einem Befund (#158) Regel, Fundstelle und Ausschnitt wie
// TFindingPrompt.Markdown; aus mehreren Befunden derselbe Text wie TFindingPrompt.Many mit dem gemeinsamen Katalog,
// Höchstzahl der Vorgabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleFindingPromptsProviderTests = class
  public
    [Test]
    procedure HasRuleAndSnippet;
    [Test]
    procedure MarkdownLikeMany;
    [Test]
    procedure DefaultLimitOfPrompt;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Findings.Contract,
  Rules.Contract.Api,
  Rules.Prompt,
  Rules.Providers.FindingPrompts;

const
  cText = 'unit U;' + #10 + 'interface' + #10 + 'implementation' + #10 + 'end.';

function Items: TArray<TFindingPromptItem>;
var
  mFinding: TRuleFinding;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'magic-number';
  mFinding.Message := 'Zahl';
  mFinding.Range := TTextRange.Create(1, 0, 1, 4);
  Result := nil;
  SetLength(Result, 2);
  Result[0] := TFindingPromptItem.Create(mFinding, 'U.pas', cText);
  mFinding.Range := TTextRange.Create(2, 0, 2, 4);
  Result[1] := TFindingPromptItem.Create(mFinding, 'U.pas', cText);
end;

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
  mText := mPrompts.MarkdownOf(mFinding, 'U.pas', 'a'#13#10'b'#13#10'c'#13#10'd');
  Assert.Contains(mText, '## Befund empty-except');
  Assert.Contains(mText, 'Zeile 3, Spalte 3');
  Assert.Contains(mText, '>    3 | c');
  Assert.Contains(mText, '```pascal');
end;

procedure TRuleFindingPromptsProviderTests.MarkdownLikeMany;
var
  mPrompts: IRuleFindingPrompts;
begin
  mPrompts := TRuleFindingPromptsProvider.Create;
  Assert.AreEqual(TFindingPrompt.Many(Items, TFindingPrompt.SharedCatalog, TFindingPrompt.cDefaultContext, 1),
    mPrompts.Markdown(Items, 1));
  Assert.Contains(mPrompts.Markdown(Items, 1), 'magic-number');
end;

procedure TRuleFindingPromptsProviderTests.DefaultLimitOfPrompt;
var
  mPrompts: IRuleFindingPrompts;
begin
  mPrompts := TRuleFindingPromptsProvider.Create;
  Assert.AreEqual(TFindingPrompt.cDefaultLimit, mPrompts.DefaultLimit);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleFindingPromptsProviderTests);

end.
