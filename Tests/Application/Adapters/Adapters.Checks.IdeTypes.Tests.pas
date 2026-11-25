unit Adapters.Checks.IdeTypes.Tests;

// Tests für den Host-Adapter, der die Typen der IDE aus dem Sprachserver den Prüfregeln gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCheckIdeTypesAdapterTests = class
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
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Providers.IdeTypes,
  Adapters.Checks.IdeTypes,
  Atlas.Common.Checks.Contract;

{ TCheckIdeTypesAdapterTests }

procedure TCheckIdeTypesAdapterTests.UnitsOfAsksTheCatalog;
var
  mCatalog: TIdeTypeCatalog;
  mTypes: ILspIdeTypes;
  mRules: ICheckIdeTypes;
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
  mRules := TCheckIdeTypesAdapter.Wrap(mTypes);
  mUnits := mRules.UnitsOf('tvendorgrid');
  Assert.AreEqual(1, Integer(Length(mUnits)));
  Assert.AreEqual('Vendor.Grid', mUnits[0]);
  Assert.AreEqual(0, Integer(Length(mRules.UnitsOf('TUnknown'))));
end;

procedure TCheckIdeTypesAdapterTests.WrapOfNilIsNil;
var
  mRules: IInterface;
begin
  mRules := TCheckIdeTypesAdapter.Wrap(nil);
  Assert.IsNull(mRules);
end;

procedure TCheckIdeTypesAdapterTests.WithoutTypesNoUnits;
var
  mRules: ICheckIdeTypes;
begin
  mRules := TCheckIdeTypesAdapter.Create(nil);
  Assert.AreEqual(0, Integer(Length(mRules.UnitsOf('TVendorGrid'))));
end;

end.
