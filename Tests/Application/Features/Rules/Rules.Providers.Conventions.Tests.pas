unit Rules.Providers.Conventions.Tests;

// Tests des Anbieters der Projektkonventionen (#272) für andere Features: dieselben Konventionen wie
// TRuleConventions mit den mitgegebenen Regeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleConventionsProviderTests = class
  public
    [Test]
    procedure ListsActiveRules;
    [Test]
    procedure WithoutRulesListsNone;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Rules.Contract,
  Rules.Builtin,
  Rules.Contract.Api,
  Rules.Providers.Conventions;

{ TRuleConventionsProviderTests }

procedure TRuleConventionsProviderTests.ListsActiveRules;
var
  mConventions: IRuleConventions;
  mText: string;
begin
  mConventions := TRuleConventionsProvider.Create(BuiltinRules);
  mText := mConventions.Markdown(Default(TServerSettings));
  Assert.Contains(mText, '# Konventionen des Projekts');
  Assert.Contains(mText, 'Regelprofil: `standard`');
  Assert.Contains(mText, '## Aktive Regeln');
  Assert.IsFalse(mText.Contains('## Aktive Regeln (0)'), 'Standardprofil hat aktive Regeln');
end;

procedure TRuleConventionsProviderTests.WithoutRulesListsNone;
var
  mConventions: IRuleConventions;
  mRules: TArray<IRule>;
begin
  mRules := nil;
  mConventions := TRuleConventionsProvider.Create(mRules);
  Assert.Contains(mConventions.Markdown(Default(TServerSettings)), '## Aktive Regeln (0)');
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleConventionsProviderTests);

end.
