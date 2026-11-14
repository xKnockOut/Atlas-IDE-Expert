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
    /// <summary>#1321: Ohne Installation die Version zur ProjectVersion, ohne .dproj die neueste bekannte.
    /// </summary>
    [Test]
    procedure WithoutInstallationExpectsProjectVersion;
    /// <summary>#1321: Die erwartete Version ergibt CompilerVersion und VERxxx wie in der IDE.</summary>
    [Test]
    procedure WithoutInstallationDefinesCompilerVersion;
  end;

implementation

uses
  System.StrUtils,
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Projects.Contract,
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
  mMissing: Boolean;
begin
  Assert.AreEqual('22.0', TDelphiVersions.Choose('22.0', '20.1', ['22.0', '23.0', '37.0'], mMissing));
  Assert.IsFalse(mMissing);
  // "23" und "23.0" sind dieselbe Version.
  Assert.IsTrue(TDelphiVersions.IsInstalled('23', ['23.0']));
  Assert.IsFalse(TDelphiVersions.IsInstalled('', ['23.0']));
end;

procedure TDelphiVersionsTests.MissingConfiguredVersionFallsBack;
var
  mMissing: Boolean;
begin
  // Abnahme #47: "22.0" ohne Delphi 11 nutzt die automatisch gewählte Version.
  Assert.AreEqual('23.0', TDelphiVersions.Choose('22.0', '20.1', ['23.0', '37.0'], mMissing));
  Assert.IsTrue(mMissing);
  Assert.AreEqual('37.0', TDelphiVersions.Choose('22.0', '', ['23.0', '37.0'], mMissing));
  Assert.IsTrue(mMissing);
  // Ohne jede Installation gilt die konfigurierte Version für die Symbole (#1321).
  Assert.AreEqual('22.0', TDelphiVersions.Choose('22.0', '20.1', [], mMissing));
  Assert.IsTrue(mMissing);
  Assert.AreEqual('23.0', TDelphiVersions.Choose('', '20.1', ['23.0'], mMissing));
  Assert.IsFalse(mMissing);
end;

procedure TDelphiVersionsTests.WarnsAtMissingConfiguredVersion;
const
  cJson = '{"delphiVersion": "22.0"}';
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := TConfigurationParser.Parse(cJson, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mIssues := TDelphiVersions.ConfigurationIssues(mSettings, ['23.0', '37.0']);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsFalse(mIssues[0].IsError, 'Warnung, kein Fehler');
  // Die Warnung steht am Wert "22.0".
  Assert.AreEqual(0, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('"22.0"', cJson) - 1, mIssues[0].Range.StartPos.Character);
  Assert.AreEqual(Pos('"22.0"', cJson) - 1 + Length('"22.0"'), mIssues[0].Range.EndPos.Character);
  Assert.IsTrue(Pos('Delphi 11', mIssues[0].Message) > 0, mIssues[0].Message);
  Assert.IsTrue(Pos('automatisch', mIssues[0].Message) > 0, mIssues[0].Message);
  // Installiert oder nicht gesetzt: keine Warnung.
  Assert.AreEqual(0, Integer(Length(TDelphiVersions.ConfigurationIssues(mSettings, ['22.0', '23.0']))));
  Assert.AreEqual(0, Integer(Length(TDelphiVersions.ConfigurationIssues(TServerSettings.Default, ['23.0']))));
  // Produktnummer: "11" wird zu 22.0.
  mSettings := TConfigurationParser.Parse('{"delphiVersion": "11"}', mIssues);
  Assert.AreEqual(1, Integer(Length(TDelphiVersions.ConfigurationIssues(mSettings, ['23.0']))));
  // Gar kein Delphi installiert: Warnung, dass Pfade und Quellen fehlen.
  mIssues := TDelphiVersions.ConfigurationIssues(mSettings, []);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(Pos('keine andere', mIssues[0].Message) > 0, mIssues[0].Message);
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
end;

procedure TDelphiVersionsTests.WithoutInstallationExpectsProjectVersion;
var
  mMissing: Boolean;
begin
  Assert.AreEqual('22.0', TDelphiVersions.Choose('', '19.5', []));
  Assert.AreEqual('23.0', TDelphiVersions.Choose('', '20.1', []));
  Assert.AreEqual('37.0', TDelphiVersions.Choose('', '20.3', [], mMissing));
  Assert.IsFalse(mMissing);
  // Ohne .dproj oder mit unbekannter ProjectVersion die neueste bekannte.
  Assert.AreEqual('37.0', TDelphiVersions.LatestKnown);
  Assert.AreEqual(TDelphiVersions.LatestKnown, TDelphiVersions.Choose('', '', []));
  Assert.AreEqual(TDelphiVersions.LatestKnown, TDelphiVersions.Choose('', '12.0', []));
  // Die erwartete Version ist nicht installiert.
  Assert.IsFalse(TDelphiVersions.IsInstalled(TDelphiVersions.Choose('', '20.1', []), []));
end;

procedure TDelphiVersionsTests.WithoutInstallationDefinesCompilerVersion;
var
  mProject: TProjectInfo;
  mDefines: TArray<string>;
  mOptions: TPreprocessorOptions;
begin
  mProject := Default(TProjectInfo);
  mProject.Platform := 'Win32';
  mProject.Defines := ['DEBUG'];
  mDefines := TIndexProjectFiles.Defines(mProject, TDelphiVersions.Choose('', '20.3', []));
  mOptions := TPascalPreprocessor.EditorOptions(mDefines);
  Assert.AreEqual(37.0, mOptions.CompilerVersion, 0.001);
  Assert.AreEqual(37.0, mOptions.RTLVersion, 0.001);
  Assert.IsTrue(IndexText('VER370', mDefines) >= 0, String.Join(' ', mDefines));
  mDefines := TIndexProjectFiles.Defines(mProject, TDelphiVersions.Choose('', '20.1', []));
  mOptions := TPascalPreprocessor.EditorOptions(mDefines);
  Assert.AreEqual(36.0, mOptions.CompilerVersion, 0.001);
  Assert.IsTrue(IndexText('VER360', mDefines) >= 0, String.Join(' ', mDefines));
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiVersionsTests);

end.
