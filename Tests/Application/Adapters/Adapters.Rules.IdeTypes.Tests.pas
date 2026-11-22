unit Adapters.Rules.IdeTypes.Tests;

// Tests für den Host-Adapter, der die Typen der IDE aus dem Sprachserver den Prüfregeln gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleIdeTypesAdapterTests = class
  public
    [Test]
    procedure UnitsOfAsksTheCatalog;
    [Test]
    procedure WrapOfNilIsNil;
    [Test]
    procedure WithoutTypesNoUnits;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Providers.IdeTypes,
  Adapters.Rules.IdeTypes;

{ TRuleIdeTypesAdapterTests }

procedure TRuleIdeTypesAdapterTests.UnitsOfAsksTheCatalog;
var
  mCatalog: TIdeTypeCatalog;
  mTypes: ILspIdeTypes;
  mRules: IRuleIdeTypes;
  mParams: TJSONValue;
  mUnits: TArray<string>;
begin
  mCatalog := TIdeTypeCatalog.Create;
  mTypes := mCatalog;
  mParams := TJSONObject.ParseJSONValue('{"units": [{"unit": "Vendor.Grid", "types": ["TVendorGrid"]}]}');
  try
    mCatalog.Replace(mParams);
  finally
    mParams.Free;
  end;
  mRules := TRuleIdeTypesAdapter.Wrap(mTypes);
  mUnits := mRules.UnitsOf('tvendorgrid');
  Assert.AreEqual(1, Integer(Length(mUnits)));
  Assert.AreEqual('Vendor.Grid', mUnits[0]);
  Assert.AreEqual(0, Integer(Length(mRules.UnitsOf('TUnknown'))));
end;

procedure TRuleIdeTypesAdapterTests.WrapOfNilIsNil;
var
  mRules: IInterface;
begin
  mRules := TRuleIdeTypesAdapter.Wrap(nil);
  Assert.IsNull(mRules);
end;

procedure TRuleIdeTypesAdapterTests.WithoutTypesNoUnits;
var
  mRules: IRuleIdeTypes;
begin
  mRules := TRuleIdeTypesAdapter.Create(nil);
  Assert.AreEqual(0, Integer(Length(mRules.UnitsOf('TVendorGrid'))));
end;

end.
