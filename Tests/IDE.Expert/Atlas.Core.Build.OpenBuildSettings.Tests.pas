unit Atlas.Core.Build.OpenBuildSettings.Tests;

// Werte der Einstellungen „Bauen beim Öffnen“ (#1293, im Kern seit #1455).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOpenBuildSettingsTests = class
  public
    /// <summary>Namen, Art, Umfang und Ausschlussliste.</summary>
    [Test]
    procedure NamesAndSettingsValues;
    /// <summary>#1293: Vorgabe für Konfiguration und Plattform nur, wenn das Projekt sie kennt, in dessen
    /// Schreibweise; ohne Vorgabe oder unbekannt gilt die Einstellung des Projekts.</summary>
    [Test]
    procedure PicksTargetKnownToProject;
  end;

implementation

uses
  Atlas.Core.Build.Events,
  Atlas.Core.Build.OpenBuildSettings;

procedure TAtlasOpenBuildSettingsTests.NamesAndSettingsValues;
var
  Exclude: TArray<string>;
begin
  Assert.AreEqual('Atlas.IDE.Expert', TAtlasOpenBuildSettings.NameOf('C:\P\Atlas.IDE.Expert.dproj'));
  Assert.AreEqual('App', TAtlasOpenBuildSettings.NameOf('/home/p/App.dpr'));
  Assert.AreEqual('Atlas.Text', TAtlasOpenBuildSettings.NameOf('Atlas.Text'), 'Punkte im Namen bleiben');
  Assert.AreEqual(Ord(TAtlasCompileKind.Check), Ord(TAtlasOpenBuildSettings.KindOf(' Check ')));
  Assert.AreEqual(Ord(TAtlasCompileKind.Build), Ord(TAtlasOpenBuildSettings.KindOf('build')));
  Assert.AreEqual(Ord(TAtlasCompileKind.Make), Ord(TAtlasOpenBuildSettings.KindOf('quatsch')));
  Assert.AreEqual('make', TAtlasOpenBuildSettings.KindName(TAtlasCompileKind.Clean), 'nur check, make, build');
  Assert.AreEqual(Ord(TAtlasOpenBuildScope.Active), Ord(TAtlasOpenBuildSettings.ScopeOf('ACTIVE')));
  Assert.AreEqual(Ord(TAtlasOpenBuildScope.All), Ord(TAtlasOpenBuildSettings.ScopeOf('')));
  Exclude := TAtlasOpenBuildSettings.ParseExclude('Atlas.IDE.Expert.dpk;  Demo' + #13#10 + 'demo, ,');
  Assert.AreEqual(2, Integer(Length(Exclude)));
  Assert.AreEqual('Atlas.IDE.Expert', Exclude[0]);
  Assert.AreEqual('Demo', Exclude[1]);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', TAtlasOpenBuildSettings.NormalizedExclude('Atlas.IDE.Expert.dpk;Demo;demo'));
end;

procedure TAtlasOpenBuildSettingsTests.PicksTargetKnownToProject;
var
  Configurations, Platforms: TArray<string>;
begin
  Configurations := TArray<string>.Create('Debug', 'Release', 'CI');
  Platforms := TArray<string>.Create('Win32', 'Win64');
  Assert.AreEqual('Debug', TAtlasOpenBuildSettings.PickTarget(' debug ', Configurations), 'Schreibweise des Projekts');
  Assert.AreEqual('Win64', TAtlasOpenBuildSettings.PickTarget('WIN64', Platforms));
  Assert.AreEqual('Win64', TAtlasOpenBuildSettings.PickTarget('Win 64', Platforms), 'Leerzeichen wie in der IDE-Anzeige');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('Profil', Configurations), 'unbekannt: wie im Projekt');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('Linux64', Platforms), 'nicht aktiviert: wie im Projekt');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('', Configurations), 'ohne Vorgabe: wie im Projekt');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('Debug', nil), 'Projekt ohne Liste');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOpenBuildSettingsTests);

end.
