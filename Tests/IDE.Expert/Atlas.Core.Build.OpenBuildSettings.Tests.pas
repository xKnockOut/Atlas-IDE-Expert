unit Atlas.Core.Build.OpenBuildSettings.Tests;

// Werte der Einstellungen „Bauen beim Öffnen“ (#1293).

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
  mExclude: TArray<string>;
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
  mExclude := TAtlasOpenBuildSettings.ParseExclude('Atlas.IDE.Expert.dpk;  Demo' + #13#10 + 'demo, ,');
  Assert.AreEqual(2, Integer(Length(mExclude)));
  Assert.AreEqual('Atlas.IDE.Expert', mExclude[0]);
  Assert.AreEqual('Demo', mExclude[1]);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', TAtlasOpenBuildSettings.NormalizedExclude('Atlas.IDE.Expert.dpk;Demo;demo'));
end;

procedure TAtlasOpenBuildSettingsTests.PicksTargetKnownToProject;
var
  mConfigurations, mPlatforms: TArray<string>;
begin
  mConfigurations := TArray<string>.Create('Debug', 'Release', 'CI');
  mPlatforms := TArray<string>.Create('Win32', 'Win64');
  Assert.AreEqual('Debug', TAtlasOpenBuildSettings.PickTarget(' debug ', mConfigurations), 'Schreibweise des Projekts');
  Assert.AreEqual('Win64', TAtlasOpenBuildSettings.PickTarget('WIN64', mPlatforms));
  Assert.AreEqual('Win64', TAtlasOpenBuildSettings.PickTarget('Win 64', mPlatforms), 'Leerzeichen wie in der IDE-Anzeige');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('Profil', mConfigurations), 'unbekannt: wie im Projekt');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('Linux64', mPlatforms), 'nicht aktiviert: wie im Projekt');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('', mConfigurations), 'ohne Vorgabe: wie im Projekt');
  Assert.AreEqual('', TAtlasOpenBuildSettings.PickTarget('Debug', nil), 'Projekt ohne Liste');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOpenBuildSettingsTests);

end.
