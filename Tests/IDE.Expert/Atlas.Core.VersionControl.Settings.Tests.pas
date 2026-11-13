unit Atlas.Core.VersionControl.Settings.Tests;

// Tests für vcs.* der globalen Einstellungen im Plugin (#571, #1285, #1967): Werte, Vorgaben und Grenzen des
// Zeitlimits, ohne Datei und IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
  TAtlasVcsPluginSettingsTests = class
  public
    [Test]
    procedure ReadsProviderPathsAndTimeout;
    /// <summary>Außerhalb 1–300 s gilt die Vorgabe wie im Parser des Servers.</summary>
    [Test]
    procedure TimeoutOutsideRangeFallsBackToDefault;
    [Test]
    procedure EmptyOrInvalidTextGivesDefaults;
    [Test]
    procedure PathThatIsNoStringIsIgnored;
  end;

implementation

uses
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Settings;

const
  cDefaultMs = TAtlasVcsPluginSettings.cDefaultTimeoutSeconds * TAtlasVcsPluginSettings.cMsPerSecond;

procedure TAtlasVcsPluginSettingsTests.ReadsProviderPathsAndTimeout;
var
  mSettings: TAtlasVcsPluginSettings;
begin
  mSettings := TAtlasVcsPluginSettings.Parse('{"vcs": {"provider": "svn", "git": {"path": " C:\\Git\\git.exe "},' +
    ' "svn": {"path": "C:\\Svn\\svn.exe"}, "timeoutSeconds": 42}}');
  Assert.IsTrue(mSettings.Provider = TAtlasVcsProvider.Svn);
  Assert.AreEqual('C:\Git\git.exe', mSettings.GitPath, 'getrimmt');
  Assert.AreEqual('C:\Svn\svn.exe', mSettings.SvnPath);
  Assert.AreEqual(Cardinal(42000), mSettings.TimeoutMs);
end;

procedure TAtlasVcsPluginSettingsTests.TimeoutOutsideRangeFallsBackToDefault;
begin
  Assert.AreEqual(Cardinal(cDefaultMs), TAtlasVcsPluginSettings.Parse('{"vcs": {"timeoutSeconds": 0}}').TimeoutMs);
  Assert.AreEqual(Cardinal(cDefaultMs), TAtlasVcsPluginSettings.Parse('{"vcs": {"timeoutSeconds": 301}}').TimeoutMs);
  Assert.AreEqual(Cardinal(300000), TAtlasVcsPluginSettings.Parse('{"vcs": {"timeoutSeconds": 300}}').TimeoutMs);
  Assert.AreEqual(Cardinal(1000), TAtlasVcsPluginSettings.Parse('{"vcs": {"timeoutSeconds": 1}}').TimeoutMs);
end;

procedure TAtlasVcsPluginSettingsTests.EmptyOrInvalidTextGivesDefaults;
var
  mTexts: TArray<string>;
  mText: string;
  mSettings: TAtlasVcsPluginSettings;
begin
  mTexts := TArray<string>.Create('', '[1, 2]', '{kaputt', '{}');
  for mText in mTexts do
  begin
    mSettings := TAtlasVcsPluginSettings.Parse(mText);
    Assert.IsTrue(mSettings.Provider = TAtlasVcsProvider.Auto, mText);
    Assert.AreEqual('', mSettings.GitPath, mText);
    Assert.AreEqual(Cardinal(cDefaultMs), mSettings.TimeoutMs, mText);
    Assert.AreEqual(0, Integer(Length(mSettings.Projects)), mText);
  end;
end;

procedure TAtlasVcsPluginSettingsTests.PathThatIsNoStringIsIgnored;
begin
  Assert.AreEqual('', TAtlasVcsPluginSettings.Parse('{"vcs": {"git": {"path": 5}}}').GitPath);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsPluginSettingsTests);

end.
