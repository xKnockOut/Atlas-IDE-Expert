unit Adapters.Lsp.RuleActions.Tests;

// Tests für den Host-Adapter, der den Code-Aktionen des Sprachservers die Prüfregeln je Dokument gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspRuleActionsAdapterTests = class
  public
    [Test]
    procedure DelegatesToRules;
    [Test]
    procedure WrapOfNilIsNil;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Lsp.Contract,
  Rules.Contract.Api,
  Rules.Providers.DocumentActions,
  Adapters.Lsp.RuleActions;

const
  cBroken = 'unit A;' + #10 + 'interface' + #10 + 'implementation' + #10 + 'procedure X;' + #10 + 'begin' + #10 +
    '  if True' + #10 + '  X;' + #10 + 'end;' + #10 + 'end.';

{ TLspRuleActionsAdapterTests }

procedure TLspRuleActionsAdapterTests.DelegatesToRules;
var
  mRules: IRuleCodeActions;
  mActions: ILspDocumentRuleActions;
  mStore: IDocumentStore;
  mDocument: ITextDocument;
  mSyntax, mCached: TArray<TRuleFinding>;
  mAll: TCodeAction;
begin
  mRules := TRuleCodeActionsProvider.Create(nil);
  mActions := TLspRuleActionsAdapter.Wrap(mRules).ForDocument('file:///C:/P/A.pas', nil);
  mStore := TDocumentStore.Create;
  mDocument := mStore.Open('file:///C:/P/A.pas', 'objectpascal', 1, cBroken);
  mSyntax := mActions.SyntaxFindings(mDocument);
  Assert.AreEqual(1, Integer(Length(mSyntax)));
  Assert.AreEqual('syntax', mSyntax[0].RuleId);
  Assert.AreEqual(0, Integer(Length(mActions.SharedRuleFindings(mDocument))));
  Assert.IsTrue(mActions.CachedRuleFindings(mDocument, mCached));
  Assert.AreEqual(0, Integer(Length(mCached)));
  Assert.AreEqual(Integer(Length(mRules.ForDocument('file:///C:/P/A.pas', nil).Fixes(mSyntax, mDocument,
    mSyntax[0].Range, TFormatStyle.Default, False))), Integer(Length(mActions.Fixes(mSyntax, mDocument,
    mSyntax[0].Range, TFormatStyle.Default, False))));
  Assert.IsFalse(mActions.FixAll(nil, mAll));
  Assert.AreNotEqual('', mActions.Prompt(mSyntax[0], 'C:\P\A.pas', cBroken));
  Assert.IsNull(mActions.Index);
end;

procedure TLspRuleActionsAdapterTests.WrapOfNilIsNil;
var
  mLsp: IInterface;
begin
  mLsp := TLspRuleActionsAdapter.Wrap(nil);
  Assert.IsNull(mLsp);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRuleActionsAdapterTests);

end.
