unit Atlas.Common.Product.Version.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProductVersionTests = class
  public
    [Test]
    procedure NameIsAtlas;
    [Test]
    procedure VersionHasMajorMinorPatch;
    /// <summary>Server, Plugin und Installer lesen dieselbe Angabe (ADR 0012).</summary>
    [Test]
    procedure ServerAndPluginShareVersion;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Product.Version,
  Atlas.Common.Product.Version,
  Atlas.Core.Product.Version;

procedure TProductVersionTests.NameIsAtlas;
begin
  Assert.AreEqual('Atlas', TProductVersion.Name);
end;

procedure TProductVersionTests.VersionHasMajorMinorPatch;
var
  Version: string;
  Part: string;
begin
  Version := TProductVersion.Version;
  Assert.AreEqual<NativeInt>(3, Length(Version.Split(['.'])), 'Version muss aus Major.Minor.Patch bestehen');
  for Part in Version.Split(['.']) do
    Assert.IsTrue(StrToIntDef(Part, -1) >= 0, Format('"%s" ist keine Zahl', [Part]));
end;

procedure TProductVersionTests.ServerAndPluginShareVersion;
begin
  Assert.AreEqual(TAtlasVersion.Version, TProductVersion.Version);
  Assert.AreEqual(TAtlasVersion.Version, TAtlasPluginVersion.Version);
end;

initialization
  TDUnitX.RegisterTestFixture(TProductVersionTests);

end.
