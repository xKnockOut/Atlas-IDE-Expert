unit Atlas.Common.Rules.Providers.FindingPrompts.Tests;

// Tests für den Anbieter des Auftrags an KI-Assistenten aus mehreren Befunden: derselbe Text wie
// TFindingPrompt.Many mit dem gemeinsamen Katalog, Höchstzahl der Vorgabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleFindingPromptsTests = class
  public
    [Test]
    procedure MarkdownLikeMany;
    [Test]
    procedure DefaultLimitOfPrompt;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Providers.FindingPrompts;

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

{ TRuleFindingPromptsTests }

procedure TRuleFindingPromptsTests.MarkdownLikeMany;
var
  mPrompts: IRuleFindingPrompts;
begin
  mPrompts := TRuleFindingPrompts.Create;
  Assert.AreEqual(TFindingPrompt.Many(Items, TFindingPrompt.SharedCatalog, TFindingPrompt.cDefaultContext, 1),
    mPrompts.Markdown(Items, 1));
  Assert.Contains(mPrompts.Markdown(Items, 1), 'magic-number');
end;

procedure TRuleFindingPromptsTests.DefaultLimitOfPrompt;
var
  mPrompts: IRuleFindingPrompts;
begin
  mPrompts := TRuleFindingPrompts.Create;
  Assert.AreEqual(TFindingPrompt.cDefaultLimit, mPrompts.DefaultLimit);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleFindingPromptsTests);

end.
