unit Adapters.Lsp.RuleCatalog.Tests;

// Tests für den Host-Adapter, der Befunden und Vervollständigung des Sprachservers den Regelkatalog gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspRuleCatalogAdapterTests = class
  public
    [Test]
    procedure DelegatesToCatalog;
    [Test]
    procedure WrapOfNilIsNil;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Lsp.Contract,
  Rules.Contract.Api,
  Rules.Providers.CatalogInfo,
  Adapters.Lsp.RuleCatalog;

{ TLspRuleCatalogAdapterTests }

procedure TLspRuleCatalogAdapterTests.DelegatesToCatalog;
var
  mRules: IRuleCatalogInfo;
  mCatalog: ILspRuleCatalog;
  mFacts: TLspRuleFacts;
  mFinding: TRuleFinding;
begin
  mRules := TRuleCatalogInfo.Create;
  mCatalog := TLspRuleCatalogAdapter.Wrap(mRules);
  Assert.IsTrue(MatchText('magic-number', mCatalog.RuleIds));
  Assert.AreEqual(mRules.HelpUri('magic-number'), mCatalog.HelpUri('magic-number'));
  Assert.IsTrue(mCatalog.TryDescribe('argument-count-mismatch', mFacts));
  Assert.AreEqual('compiler', mFacts.Group);
  Assert.AreEqual(2, Integer(Length(mFacts.CompilerCodes)));
  Assert.AreEqual('E2034', mFacts.CompilerCodes[0]);
  Assert.AreEqual('E2035', mFacts.CompilerCodes[1]);
  Assert.IsFalse(mCatalog.TryDescribe('gibt-es-nicht', mFacts));
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'deprecated-symbol';
  mFinding.Message := 'Symbol X ist veraltet (W1006).';
  Assert.IsTrue(mCatalog.StruckThrough(mFinding));
end;

procedure TLspRuleCatalogAdapterTests.WrapOfNilIsNil;
var
  mLsp: IInterface;
begin
  mLsp := TLspRuleCatalogAdapter.Wrap(nil);
  Assert.IsNull(mLsp);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRuleCatalogAdapterTests);

end.
