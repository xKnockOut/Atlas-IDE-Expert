unit Adapters.Lsp.FindingsPrompt.Tests;

// Tests für den Host-Adapter, der atlas.server.findingsPrompt den Auftrag der Prüfregeln gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFindingsPromptAdapterTests = class
  public
    [Test]
    procedure DelegatesToPrompts;
    [Test]
    procedure WrapOfNilIsNil;
  end;

implementation

uses
  Atlas.Common.Findings.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.FindingPrompts,
  Adapters.Lsp.FindingsPrompt;

{ TLspFindingsPromptAdapterTests }

procedure TLspFindingsPromptAdapterTests.DelegatesToPrompts;
var
  mRules: IRuleFindingPrompts;
  mPrompt: ILspFindingsPrompt;
  mFinding: TRuleFinding;
  mItems: TArray<TFindingPromptItem>;
begin
  mRules := TRuleFindingPromptsProvider.Create;
  mPrompt := TLspFindingsPromptAdapter.Wrap(mRules);
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'magic-number';
  mFinding.Message := 'Zahl';
  mItems := nil;
  SetLength(mItems, 1);
  mItems[0] := TFindingPromptItem.Create(mFinding, 'U.pas', 'unit U;');
  Assert.AreEqual(mRules.DefaultLimit, mPrompt.DefaultLimit);
  Assert.AreEqual(mRules.Markdown(mItems, 5), mPrompt.Markdown(mItems, 5));
end;

procedure TLspFindingsPromptAdapterTests.WrapOfNilIsNil;
var
  mPrompt: IInterface;
begin
  mPrompt := TLspFindingsPromptAdapter.Wrap(nil);
  Assert.IsNull(mPrompt);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFindingsPromptAdapterTests);

end.
