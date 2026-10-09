unit Argus.Common.Product.Version.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProductVersionTests = class
  public
    [Test]
    procedure NameIsArgus;
    [Test]
    procedure VersionHasMajorMinorPatch;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Product.Version;

procedure TProductVersionTests.NameIsArgus;
begin
  Assert.AreEqual('Argus', TProductVersion.Name);
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

initialization
  TDUnitX.RegisterTestFixture(TProductVersionTests);

end.
