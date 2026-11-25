unit Atlas.Common.Compiler.Releases.Tests;

// Tests für die Release-Namen der Delphi-Versionen (DocWiki-Links, #27, #54).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiReleasesTests = class
  public
    [Test]
    procedure MapsVersionsToReleases;
    [Test]
    procedure UnknownVersionUsesNewest;
  end;

implementation

uses
  Atlas.Common.Compiler.Releases;

{ TDelphiReleasesTests }

procedure TDelphiReleasesTests.MapsVersionsToReleases;
begin
  Assert.AreEqual('Athens', TDelphiReleases.Name('23.0'));
  Assert.AreEqual('Alexandria', TDelphiReleases.Name('22.0'));
  Assert.AreEqual('Rio', TDelphiReleases.Name(' 20.0 '));
  Assert.AreEqual('Florence', TDelphiReleases.Name('37.0'));
end;

procedure TDelphiReleasesTests.UnknownVersionUsesNewest;
begin
  Assert.AreEqual('Florence', TDelphiReleases.Name(''));
  Assert.AreEqual('Florence', TDelphiReleases.Name('99.0'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiReleasesTests);

end.
