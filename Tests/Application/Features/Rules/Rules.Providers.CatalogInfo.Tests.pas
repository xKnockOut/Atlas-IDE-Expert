unit Rules.Providers.CatalogInfo.Tests;

// Tests für die Angaben des Regelkatalogs an andere Features: Kennungen, Kategorie, Gruppe, vorweggenommene
// Compilermeldungen, Hilfeseite und welche Befunde der Editor durchstreicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleCatalogInfoTests = class
  public
    [Test]
    procedure ListsBuiltinRules;
    [Test]
    procedure DescribesKnownRule;
    [Test]
    procedure StrikesOnlyDeprecations;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Findings.Contract,
  Rules.Contract.Api,
  Rules.Providers.CatalogInfo;

{ TRuleCatalogInfoTests }

procedure TRuleCatalogInfoTests.ListsBuiltinRules;
var
  mCatalog: IRuleCatalogInfo;
  mIds: TArray<string>;
begin
  mCatalog := TRuleCatalogInfo.Create;
  mIds := mCatalog.RuleIds;
  Assert.IsTrue(MatchText('magic-number', mIds));
  Assert.IsTrue(MatchText('unused-uses', mIds));
  Assert.IsTrue(EndsText('#magic-number', mCatalog.HelpUri('Magic-Number')));
end;

procedure TRuleCatalogInfoTests.DescribesKnownRule;
var
  mCatalog: IRuleCatalogInfo;
  mFacts: TRuleCatalogFacts;
begin
  mCatalog := TRuleCatalogInfo.Create;
  Assert.IsTrue(mCatalog.TryDescribe('argument-count-mismatch', mFacts));
  Assert.AreEqual('compiler', mFacts.Group);
  Assert.AreNotEqual('', mFacts.Category);
  Assert.AreEqual(2, Integer(Length(mFacts.CompilerCodes)));
  Assert.AreEqual('E2034', mFacts.CompilerCodes[0]);
  Assert.AreEqual('E2035', mFacts.CompilerCodes[1]);
  Assert.IsFalse(mCatalog.TryDescribe('gibt-es-nicht', mFacts));
  Assert.AreEqual('', mFacts.Group);
end;

procedure TRuleCatalogInfoTests.StrikesOnlyDeprecations;
var
  mCatalog: IRuleCatalogInfo;
  mFinding: TRuleFinding;
begin
  mCatalog := TRuleCatalogInfo.Create;
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'deprecated-symbol';
  mFinding.Message := 'Symbol X ist veraltet (W1000).';
  Assert.IsTrue(mCatalog.StruckThrough(mFinding));
  mFinding.Message := 'Symbol X ist plattformspezifisch (W1002).';
  Assert.IsFalse(mCatalog.StruckThrough(mFinding));
  mFinding.RuleId := 'magic-number';
  mFinding.Message := 'Symbol X ist veraltet (W1000).';
  Assert.IsFalse(mCatalog.StruckThrough(mFinding));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleCatalogInfoTests);

end.
