unit Atlas.Common.Projects.DelphiVersions.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiVersionsTests = class
  public
    [Test]
    procedure ReadsProjectVersion;
    [Test]
    procedure MapsProjectVersionToBds;
    [Test]
    procedure NamesProducts;
    [Test]
    procedure ConfiguredVersionWins;
    [Test]
    procedure ChoosesMatchingInstallation;
    [Test]
    procedure FallsBackToNextHigherOrLatest;
  end;

implementation

uses
  Atlas.Common.Projects.DelphiVersions;

procedure TDelphiVersionsTests.ReadsProjectVersion;
begin
  Assert.AreEqual('19.5', TDelphiVersions.ProjectVersionOf(
    '<Project><PropertyGroup><ProjectVersion> 19.5 </ProjectVersion></PropertyGroup></Project>'));
  Assert.AreEqual('', TDelphiVersions.ProjectVersionOf('<Project/>'));
end;

procedure TDelphiVersionsTests.MapsProjectVersionToBds;
begin
  Assert.AreEqual('22.0', TDelphiVersions.BdsForProjectVersion('19.5'));
  Assert.AreEqual('23.0', TDelphiVersions.BdsForProjectVersion('20.1'));
  Assert.AreEqual('37.0', TDelphiVersions.BdsForProjectVersion('20.3'));
  Assert.AreEqual('21.0', TDelphiVersions.BdsForProjectVersion('19.2'));
  Assert.AreEqual('', TDelphiVersions.BdsForProjectVersion('12.0'));
  Assert.AreEqual('', TDelphiVersions.BdsForProjectVersion(''));
end;

procedure TDelphiVersionsTests.NamesProducts;
begin
  Assert.AreEqual('Delphi 11', TDelphiVersions.ProductName('22.0'));
  Assert.AreEqual('Delphi 12', TDelphiVersions.ProductName('23.0'));
  Assert.AreEqual('BDS 5.0', TDelphiVersions.ProductName('5.0'));
end;

procedure TDelphiVersionsTests.ConfiguredVersionWins;
begin
  Assert.AreEqual('22.0', TDelphiVersions.Choose('22.0', '20.1', ['23.0', '37.0']));
end;

procedure TDelphiVersionsTests.ChoosesMatchingInstallation;
begin
  // Ein Projekt für Delphi 11 und eines für Delphi 12 auf demselben Rechner.
  Assert.AreEqual('22.0', TDelphiVersions.Choose('', '19.5', ['22.0', '23.0', '37.0']));
  Assert.AreEqual('23.0', TDelphiVersions.Choose('', '20.1', ['22.0', '23.0', '37.0']));
end;

procedure TDelphiVersionsTests.FallsBackToNextHigherOrLatest;
begin
  Assert.AreEqual('23.0', TDelphiVersions.Choose('', '19.5', ['21.0', '23.0', '37.0']));
  Assert.AreEqual('23.0', TDelphiVersions.Choose('', '20.3', ['22.0', '23.0']));
  Assert.AreEqual('23.0', TDelphiVersions.Choose('', '', ['22.0', '23.0']));
  Assert.AreEqual('', TDelphiVersions.Choose('', '19.5', []));
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiVersionsTests);

end.
