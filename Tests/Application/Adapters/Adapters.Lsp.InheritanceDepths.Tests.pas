unit Adapters.Lsp.InheritanceDepths.Tests;

// Tests für den Host-Adapter, der dem Sprachserver die Vererbungstiefe aus den Prüfregeln gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspInheritanceDepthsAdapterTests = class
  public
    [Test]
    procedure DelegatesToRules;
    [Test]
    procedure WrapOfNilIsNil;
    [Test]
    procedure WithoutRulesNoDepths;
  end;

implementation

uses
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Lsp.Contract,
  Rules.Contract.Api,
  Rules.Providers.InheritanceDepths,
  Adapters.Lsp.InheritanceDepths;

const
  cFile = 'C:\P\Kette.pas';
  cKette = 'unit Kette;'#10'interface'#10'type'#10'  TA = class'#10'  end;'#10'  TB = class(TA)'#10'  end;'#10 +
    'implementation'#10'end.';

{ TLspInheritanceDepthsAdapterTests }

procedure TLspInheritanceDepthsAdapterTests.DelegatesToRules;
var
  mRules: IRuleInheritanceDepths;
  mLsp: ILspInheritanceDepths;
  mItems: TArray<TStructureMetrics>;
begin
  mRules := TRuleInheritanceDepths.Create;
  mLsp := TLspInheritanceDepthsAdapter.Wrap(mRules);
  mItems := mLsp.Depths(cFile, cKette, nil);
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('TB', mItems[0].Name);
  Assert.AreEqual(1, mItems[0].Value);
end;

procedure TLspInheritanceDepthsAdapterTests.WrapOfNilIsNil;
var
  mLsp: IInterface;
begin
  mLsp := TLspInheritanceDepthsAdapter.Wrap(nil);
  Assert.IsNull(mLsp);
end;

procedure TLspInheritanceDepthsAdapterTests.WithoutRulesNoDepths;
var
  mLsp: ILspInheritanceDepths;
begin
  mLsp := TLspInheritanceDepthsAdapter.Create(nil);
  Assert.AreEqual(0, Integer(Length(mLsp.Depths(cFile, cKette, nil))));
end;

end.
