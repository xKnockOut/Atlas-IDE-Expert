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
    procedure MissingConfiguredVersionFallsBack;
    [Test]
    procedure WarnsAtMissingConfiguredVersion;
    [Test]
    procedure ChoosesMatchingInstallation;
    [Test]
    procedure FallsBackToNextHigherOrLatest;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
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
var
  Missing: Boolean;
begin
  Assert.AreEqual('22.0', TDelphiVersions.Choose('22.0', '20.1', ['22.0', '23.0', '37.0'], Missing));
  Assert.IsFalse(Missing);
  // "23" und "23.0" sind dieselbe Version.
  Assert.IsTrue(TDelphiVersions.IsInstalled('23', ['23.0']));
  Assert.IsFalse(TDelphiVersions.IsInstalled('', ['23.0']));
end;

procedure TDelphiVersionsTests.MissingConfiguredVersionFallsBack;
var
  Missing: Boolean;
begin
  // Abnahme #47: "22.0" ohne Delphi 11 nutzt die automatisch gewählte Version.
  Assert.AreEqual('23.0', TDelphiVersions.Choose('22.0', '20.1', ['23.0', '37.0'], Missing));
  Assert.IsTrue(Missing);
  Assert.AreEqual('37.0', TDelphiVersions.Choose('22.0', '', ['23.0', '37.0'], Missing));
  Assert.IsTrue(Missing);
  Assert.AreEqual('', TDelphiVersions.Choose('22.0', '20.1', [], Missing));
  Assert.IsTrue(Missing);
  Assert.AreEqual('23.0', TDelphiVersions.Choose('', '20.1', ['23.0'], Missing));
  Assert.IsFalse(Missing);
end;

procedure TDelphiVersionsTests.WarnsAtMissingConfiguredVersion;
const
  Json = '{"delphiVersion": "22.0"}';
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := TConfigurationParser.Parse(Json, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Issues := TDelphiVersions.ConfigurationIssues(Settings, ['23.0', '37.0']);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsFalse(Issues[0].IsError, 'Warnung, kein Fehler');
  // Die Warnung steht am Wert "22.0".
  Assert.AreEqual(0, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('"22.0"', Json) - 1, Issues[0].Range.StartPos.Character);
  Assert.AreEqual(Pos('"22.0"', Json) - 1 + Length('"22.0"'), Issues[0].Range.EndPos.Character);
  Assert.IsTrue(Pos('Delphi 11', Issues[0].Message) > 0, Issues[0].Message);
  Assert.IsTrue(Pos('automatisch', Issues[0].Message) > 0, Issues[0].Message);
  // Installiert oder nicht gesetzt: keine Warnung.
  Assert.AreEqual(0, Integer(Length(TDelphiVersions.ConfigurationIssues(Settings, ['22.0', '23.0']))));
  Assert.AreEqual(0, Integer(Length(TDelphiVersions.ConfigurationIssues(TServerSettings.Default, ['23.0']))));
  // Produktnummer: "11" wird zu 22.0.
  Settings := TConfigurationParser.Parse('{"delphiVersion": "11"}', Issues);
  Assert.AreEqual(1, Integer(Length(TDelphiVersions.ConfigurationIssues(Settings, ['23.0']))));
  // Gar kein Delphi installiert: Warnung, dass Pfade und Quellen fehlen.
  Issues := TDelphiVersions.ConfigurationIssues(Settings, []);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Pos('keine andere', Issues[0].Message) > 0, Issues[0].Message);
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
