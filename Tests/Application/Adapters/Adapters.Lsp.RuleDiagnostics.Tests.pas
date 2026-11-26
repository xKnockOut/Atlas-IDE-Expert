unit Adapters.Lsp.RuleDiagnostics.Tests;

// Tests für den Host-Adapter, der der Diagnose des Sprachservers die Prüfregeln je Dokument gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspRuleDiagnosticsAdapterTests = class
  public
    [Test]
    procedure DelegatesToRules;
    [Test]
    procedure WrapOfNilIsNil;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Findings.Contract,
  Lsp.Contract,
  Rules.Contract.Api,
  Rules.Providers.DocumentChecks,
  Adapters.Lsp.RuleDiagnostics;

const
  cBroken = 'unit A;' + #10 + 'interface' + #10 + 'implementation' + #10 + 'procedure X;' + #10 + 'begin' + #10 +
    '  if True' + #10 + '  X;' + #10 + 'end;' + #10 + 'end.';

{ TLspRuleDiagnosticsAdapterTests }

procedure TLspRuleDiagnosticsAdapterTests.DelegatesToRules;
var
  mChecks: IRuleDocumentChecks;
  mLsp: ILspRuleDiagnostics;
  mRules: ILspDocumentRules;
  mStore: IDocumentStore;
  mDocument: ITextDocument;
  mSyntax: TArray<TRuleFinding>;
begin
  mChecks := TRuleDocumentChecks.Create(nil, nil);
  mLsp := TLspRuleDiagnosticsAdapter.Wrap(mChecks);
  mRules := mLsp.ForDocument('file:///C:/P/A.pas', nil);
  mStore := TDocumentStore.Create;
  mDocument := mStore.Open('file:///C:/P/A.pas', 'objectpascal', 1, cBroken);
  mSyntax := mRules.SyntaxFindings(mDocument, nil);
  Assert.AreEqual(0, Integer(Length(mRules.RuleFindings(mDocument, nil))));
  Assert.AreEqual(0, Integer(Length(mRules.LanguageFeatureFindings(mDocument, nil, '', nil))));
  Assert.AreEqual(1, Integer(Length(mSyntax)));
  Assert.AreEqual('syntax', mSyntax[0].RuleId);
  Assert.IsTrue(mRules.UnusedUsesShown);
  Assert.IsTrue(mRules.OnlyImplementationShown);
end;

procedure TLspRuleDiagnosticsAdapterTests.WrapOfNilIsNil;
var
  mLsp: IInterface;
begin
  mLsp := TLspRuleDiagnosticsAdapter.Wrap(nil);
  Assert.IsNull(mLsp);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRuleDiagnosticsAdapterTests);

end.
