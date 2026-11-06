unit Atlas.Core.Lsp.IdeTypes.Tests;

// Tests für die Typen der IDE im Plugin (atlas/ideTypes): qualifizierte Namen aufteilen, JSON je Unit ohne
// Doppelte, Ordner der Installation erkennen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIdeTypesTests = class
  public
    [Test]
    procedure SplitsQualifiedNames;
    [Test]
    procedure RejectsNamesWithoutUnitAndGenerics;
    [Test]
    procedure JsonGroupsByUnitWithoutDuplicates;
    [Test]
    procedure InFoldersIgnoresCaseAndNeedsWholeFolder;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.IdeTypes;

procedure TAtlasIdeTypesTests.SplitsQualifiedNames;
var
  mType: TAtlasIdeType;
begin
  Assert.IsTrue(TAtlasIdeType.FromQualified('Vendor.Grid.TVendorGrid', 'Vcl.Controls.TCustomControl', mType));
  Assert.AreEqual('Vendor.Grid', mType.UnitName);
  Assert.AreEqual('TVendorGrid', mType.Name);
  Assert.AreEqual('Vcl.Controls.TCustomControl', mType.Parent);
  Assert.IsTrue(TAtlasIdeType.FromQualified('Grid.TFoo', '', mType));
  Assert.AreEqual('Grid', mType.UnitName);
  mType := Default(TAtlasIdeType);
end;

procedure TAtlasIdeTypesTests.RejectsNamesWithoutUnitAndGenerics;
var
  mType: TAtlasIdeType;
begin
  Assert.IsFalse(TAtlasIdeType.FromQualified('TFoo', '', mType));
  Assert.IsFalse(TAtlasIdeType.FromQualified('.TFoo', '', mType));
  Assert.IsFalse(TAtlasIdeType.FromQualified('Unit.', '', mType));
  Assert.IsFalse(TAtlasIdeType.FromQualified('System.Generics.Collections.TList<System.Integer>', '', mType));
  Assert.AreEqual('', mType.Name);
  mType := Default(TAtlasIdeType);
end;

procedure TAtlasIdeTypesTests.JsonGroupsByUnitWithoutDuplicates;
var
  mTypes: TArray<TAtlasIdeType>;
  mJson: TJSONObject;
begin
  SetLength(mTypes, 4);
  TAtlasIdeType.FromQualified('Vendor.Grid.TVendorGrid', 'Vcl.Controls.TCustomControl', mTypes[0]);
  TAtlasIdeType.FromQualified('Vendor.Data.TVendorSet', '', mTypes[1]);
  TAtlasIdeType.FromQualified('Vendor.Grid.TVendorColumn', '', mTypes[2]);
  TAtlasIdeType.FromQualified('vendor.grid.TVENDORGRID', '', mTypes[3]);
  mJson := TAtlasIdeTypes.ToJson(mTypes);
  try
    Assert.AreEqual('{"units":[{"unit":"Vendor.Grid","types":[{"name":"TVendorGrid",' +
      '"parent":"Vcl.Controls.TCustomControl"},"TVendorColumn"]},{"unit":"Vendor.Data","types":["TVendorSet"]}]}',
      mJson.ToJSON);
  finally
    mJson.Free;
  end;
  mTypes := nil;
end;

procedure TAtlasIdeTypesTests.InFoldersIgnoresCaseAndNeedsWholeFolder;
var
  mFolders: TArray<string>;
begin
  mFolders := TArray<string>.Create('C:' + PathDelim + 'BDS', '');
  Assert.IsTrue(TAtlasIdeTypes.InFolders('c:' + PathDelim + 'bds' + PathDelim + 'bin' + PathDelim + 'rtl.bpl',
    mFolders));
  Assert.IsFalse(TAtlasIdeTypes.InFolders('C:' + PathDelim + 'BDS2' + PathDelim + 'x.bpl', mFolders));
  Assert.IsFalse(TAtlasIdeTypes.InFolders('D:' + PathDelim + 'x.bpl', mFolders));
  mFolders := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeTypesTests);

end.
