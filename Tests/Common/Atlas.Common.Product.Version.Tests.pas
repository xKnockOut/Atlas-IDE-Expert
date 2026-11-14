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
    /// <summary>Server, Plugin und Installer lesen dieselbe Angabe.</summary>
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
  Assert.AreEqual('Atlas', TProductVersion.cName);
end;

procedure TProductVersionTests.VersionHasMajorMinorPatch;
var
  mVersion: string;
  mPart: string;
begin
  // SemVer: Vorabkennung wie -beta.1 steht hinter den drei Zahlen.
  mVersion := TProductVersion.cVersion.Split(['-'])[0];
  Assert.AreEqual<NativeInt>(3, Length(mVersion.Split(['.'])), 'Version muss aus Major.Minor.Patch bestehen');
  for mPart in mVersion.Split(['.']) do
  begin
    Assert.IsTrue(StrToIntDef(mPart, -1) >= 0, Format('"%s" ist keine Zahl', [mPart]));
  end;
end;

procedure TProductVersionTests.ServerAndPluginShareVersion;
begin
  Assert.AreEqual(TAtlasVersion.cVersion, TProductVersion.cVersion);
  Assert.AreEqual(TAtlasVersion.cVersion, TAtlasPluginVersion.cVersion);
end;

initialization
  TDUnitX.RegisterTestFixture(TProductVersionTests);

end.
