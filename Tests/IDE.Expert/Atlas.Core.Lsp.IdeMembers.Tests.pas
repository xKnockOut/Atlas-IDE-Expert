unit Atlas.Core.Lsp.IdeMembers.Tests;

// Tests für die Mitglieder der IDE-Typen im Plugin (atlas/ideMembers): gefragte Units lesen, JSON je Unit mit
// Mitgliedern, Parametern und Aufzählungswerten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIdeMembersTests = class
  public
    [Test]
    procedure WantedUnitsReadsNamesAndSkipsOthers;
    [Test]
    procedure IsIdePathMatchesOnlyServerPrefix;
    [Test]
    procedure JsonGroupsTypesByUnit;
    [Test]
    procedure JsonWritesMembersAndParams;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.IdeMembers;

function Detail(const AUnit, AName, AKind: string): TAtlasIdeTypeDetail;
begin
  Result := Default(TAtlasIdeTypeDetail);
  Result.UnitName := AUnit;
  Result.Name := AName;
  Result.Kind := AKind;
end;

procedure TAtlasIdeMembersTests.IsIdePathMatchesOnlyServerPrefix;
begin
  Assert.IsTrue(TAtlasIdeMembers.IsIdePath('atlas-ide:Vcl.Forms.pas'));
  Assert.IsTrue(TAtlasIdeMembers.IsIdePath('ATLAS-IDE:Vcl.Forms.pas'));
  Assert.IsFalse(TAtlasIdeMembers.IsIdePath('C:\P\atlas-ide:Vcl.Forms.pas'));
  Assert.IsFalse(TAtlasIdeMembers.IsIdePath('C:\P\Vcl.Forms.pas'));
  Assert.IsFalse(TAtlasIdeMembers.IsIdePath(''));
end;

procedure TAtlasIdeMembersTests.WantedUnitsReadsNamesAndSkipsOthers;
var
  mParams: TJSONValue;
  mUnits: TArray<string>;
begin
  mParams := TJSONObject.ParseJSONValue('{"units": ["Vendor.Grid", " ", 3, " Vendor.Base "]}');
  try
    mUnits := TAtlasIdeMembers.WantedUnits(mParams);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mUnits)));
  Assert.AreEqual('Vendor.Grid', mUnits[0]);
  Assert.AreEqual('Vendor.Base', mUnits[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasIdeMembers.WantedUnits(nil))));
end;

procedure TAtlasIdeMembersTests.JsonGroupsTypesByUnit;
var
  mDetails: TArray<TAtlasIdeTypeDetail>;
  mJson: TJSONObject;
begin
  mDetails := [Detail('Vendor.Grid', 'TVendorGrid', 'class'), Detail('Vendor.Base', 'IVendor', 'interface'),
    Detail('vendor.grid', 'TGridState', 'enum'), Detail('', 'TLost', 'class')];
  mDetails[2].Values := ['gsNone', 'gsEdit'];
  mDetails[0].Parent := 'Vcl.Controls.TCustomControl';
  mDetails[0].Interfaces := ['Vendor.Base.IVendor'];
  mJson := TAtlasIdeMembers.ToJson(mDetails);
  try
    Assert.AreEqual('{"units":[{"unit":"Vendor.Grid","types":[{"name":"TVendorGrid","kind":"class",' +
      '"parent":"Vcl.Controls.TCustomControl","interfaces":["Vendor.Base.IVendor"]},' +
      '{"name":"TGridState","kind":"enum","values":["gsNone","gsEdit"]}]},' +
      '{"unit":"Vendor.Base","types":[{"name":"IVendor","kind":"interface"}]}]}', mJson.ToJSON([]));
  finally
    mJson.Free;
  end;
  mDetails := nil;
end;

procedure TAtlasIdeMembersTests.JsonWritesMembersAndParams;
var
  mDetail: TAtlasIdeTypeDetail;
  mMember: TAtlasIdeMember;
  mJson: TJSONObject;
begin
  mDetail := Detail('Vendor.Grid', 'TVendorGrid', 'class');
  mMember := Default(TAtlasIdeMember);
  mMember.Kind := 'function';
  mMember.Name := 'Find';
  mMember.TypeName := 'System.Integer';
  mMember.Visibility := 'public';
  mMember.IsStatic := True;
  mMember.Params := [TAtlasIdeParam.Make('AName', 'System.string', 'const'), TAtlasIdeParam.Make('AData', '', 'var')];
  mDetail.Members := [mMember];
  mMember := Default(TAtlasIdeMember);
  mMember.Kind := 'property';
  mMember.Name := 'Cells';
  mMember.TypeName := 'System.string';
  mMember.Visibility := 'published';
  mMember.IsDefault := True;
  mMember.Index := [TAtlasIdeParam.Make('ACol', 'System.Integer', '')];
  mDetail.Members := mDetail.Members + [mMember];
  mJson := TAtlasIdeMembers.ToJson([mDetail]);
  try
    Assert.AreEqual('{"units":[{"unit":"Vendor.Grid","types":[{"name":"TVendorGrid","kind":"class","members":[' +
      '{"kind":"function","name":"Find","type":"System.Integer","visibility":"public","static":true,' +
      '"params":[{"name":"AName","type":"System.string","flag":"const"},{"name":"AData","flag":"var"}]},' +
      '{"kind":"property","name":"Cells","type":"System.string","visibility":"published","default":true,' +
      '"index":[{"name":"ACol","type":"System.Integer"}]}]}]}]}', mJson.ToJSON([]));
  finally
    mJson.Free;
  end;
  mDetail := Default(TAtlasIdeTypeDetail);
  mMember := Default(TAtlasIdeMember);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeMembersTests);

end.
