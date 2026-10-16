unit Atlas.Text.Checkin.Tests;

// Tests der Sperre für eingecheckte Einstellungsdateien (#486): Zugangsdaten
// in Schlüsseln, Namen und Adressen, absolute Pfade und Pfade aus dem Projekt
// heraus.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextCheckinTests = class
  public
    [Test]
    procedure CredentialKeysAreWholeNames;
    [Test]
    procedure CredentialNamesByEnding;
    [Test]
    procedure UrlWithUserOrTokenHasCredentials;
    [Test]
    procedure MachinePathsAreDrivesAndUnc;
    [Test]
    procedure AbsolutePathsIncludeRootAndHome;
    [Test]
    procedure FindsMachinePathInParameters;
    [Test]
    procedure RelativePathStaysInsideRoot;
    [Test]
    procedure RelativePathLeavingRootIsOutside;
  end;

implementation

uses
  Atlas.Text.Checkin;

procedure TTextCheckinTests.CredentialKeysAreWholeNames;
begin
  Assert.IsTrue(TTextCheckin.IsCredentialKey('token'));
  Assert.IsTrue(TTextCheckin.IsCredentialKey('Password'));
  Assert.IsTrue(TTextCheckin.IsCredentialKey('api_key'));
  Assert.IsTrue(TTextCheckin.IsCredentialKey('apiKey'));
  Assert.IsTrue(TTextCheckin.IsCredentialKey('API-Token'));
  Assert.IsTrue(TTextCheckin.IsCredentialKey('user'));
  Assert.IsTrue(TTextCheckin.IsCredentialKey('client_secret'));
  Assert.IsFalse(TTextCheckin.IsCredentialKey('tokenCount'), 'nur der ganze Name');
  Assert.IsFalse(TTextCheckin.IsCredentialKey('hardcoded-password'), 'Regel-ID');
  Assert.IsFalse(TTextCheckin.IsCredentialKey('url'));
  Assert.IsFalse(TTextCheckin.IsCredentialKey('job'));
  Assert.IsFalse(TTextCheckin.IsCredentialKey(''));
end;

procedure TTextCheckinTests.CredentialNamesByEnding;
begin
  Assert.IsTrue(TTextCheckin.IsCredentialName('DB_PASSWORD'));
  Assert.IsTrue(TTextCheckin.IsCredentialName('GITHUB_TOKEN'));
  Assert.IsTrue(TTextCheckin.IsCredentialName('MyApiKey'));
  Assert.IsTrue(TTextCheckin.IsCredentialName('user'), 'ganzer Name wie IsCredentialKey');
  Assert.IsFalse(TTextCheckin.IsCredentialName('ATLAS_MODE'));
  Assert.IsFalse(TTextCheckin.IsCredentialName('TOKEN_COUNT'), 'Endung zählt, nicht der Anfang');
  Assert.IsFalse(TTextCheckin.IsCredentialName('DB_USER_NAME_FIELD'));
end;

procedure TTextCheckinTests.UrlWithUserOrTokenHasCredentials;
begin
  Assert.IsTrue(TTextCheckin.HasUrlCredentials('https://marco:geheim@ci.example.com/job/kasse'));
  Assert.IsTrue(TTextCheckin.HasUrlCredentials('https://marco@ci.example.com'));
  Assert.IsTrue(TTextCheckin.HasUrlCredentials('https://ci.example.com/api?token=abc'));
  Assert.IsTrue(TTextCheckin.HasUrlCredentials('https://ci.example.com/api?a=1&api_key=abc#x'));
  Assert.IsFalse(TTextCheckin.HasUrlCredentials('https://ci.example.com/job/kasse@main'), '@ im Pfad');
  Assert.IsFalse(TTextCheckin.HasUrlCredentials('https://firma.youtrack.cloud/issues?q=for:me'));
  Assert.IsFalse(TTextCheckin.HasUrlCredentials('git@github.com:xKnockOut/Atlas.git'), 'SSH-Benutzer ohne Schema');
  Assert.IsFalse(TTextCheckin.HasUrlCredentials(''));
end;

procedure TTextCheckinTests.MachinePathsAreDrivesAndUnc;
begin
  Assert.IsTrue(TTextCheckin.IsMachinePath('C:\Projekte\Kasse'));
  Assert.IsTrue(TTextCheckin.IsMachinePath('d:/daten'));
  Assert.IsTrue(TTextCheckin.IsMachinePath('C:'));
  Assert.IsTrue(TTextCheckin.IsMachinePath('\\server\freigabe'));
  Assert.IsTrue(TTextCheckin.IsMachinePath('//server/freigabe'));
  Assert.IsFalse(TTextCheckin.IsMachinePath('/Generated/**'), 'Glob ab dem Projektordner');
  Assert.IsFalse(TTextCheckin.IsMachinePath('**/Tests/*.pas'));
  Assert.IsFalse(TTextCheckin.IsMachinePath('Vorlagen\Snippets'));
  Assert.IsFalse(TTextCheckin.IsMachinePath('https://ci.example.com'));
  Assert.IsFalse(TTextCheckin.IsMachinePath(''));
end;

procedure TTextCheckinTests.AbsolutePathsIncludeRootAndHome;
begin
  Assert.IsTrue(TTextCheckin.IsAbsolutePath('C:\Daten'));
  Assert.IsTrue(TTextCheckin.IsAbsolutePath('\Daten'));
  Assert.IsTrue(TTextCheckin.IsAbsolutePath('/Daten'));
  Assert.IsTrue(TTextCheckin.IsAbsolutePath('~\Vorlagen'));
  Assert.IsFalse(TTextCheckin.IsAbsolutePath('Vorlagen'));
  Assert.IsFalse(TTextCheckin.IsAbsolutePath('..\Gemeinsam'));
  Assert.IsFalse(TTextCheckin.IsAbsolutePath('$(BDS)\bin\bds.exe'), 'Makro der IDE');
end;

procedure TTextCheckinTests.FindsMachinePathInParameters;
begin
  Assert.IsTrue(TTextCheckin.ContainsMachinePath('-db C:\Daten\test.fdb -v'));
  Assert.IsTrue(TTextCheckin.ContainsMachinePath('--config="D:\Konfig\app.ini"'));
  Assert.IsTrue(TTextCheckin.ContainsMachinePath('Pfad=\\server\daten'));
  Assert.IsFalse(TTextCheckin.ContainsMachinePath('-db test -mode=demo /silent'));
  Assert.IsFalse(TTextCheckin.ContainsMachinePath('--url=https://localhost:8080'));
  Assert.IsFalse(TTextCheckin.ContainsMachinePath(''));
end;

procedure TTextCheckinTests.RelativePathStaysInsideRoot;
begin
  Assert.IsTrue(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo', 'Vorlagen'));
  Assert.IsTrue(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo\App', '..\Vorlagen'), 'bis zur Wurzel hinauf');
  Assert.IsTrue(TTextCheckin.StaysInside('C:\Repo\', 'c:\repo\app\', 'a/../b/./c'));
  Assert.IsTrue(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo', ''), 'leer = der Ordner selbst');
  Assert.IsTrue(TTextCheckin.StaysInside('\\srv\share\Repo', '\\srv\share\Repo\App', '..\bin'));
end;

procedure TTextCheckinTests.RelativePathLeavingRootIsOutside;
begin
  Assert.IsFalse(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo', '..\Anderes'));
  Assert.IsFalse(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo\App', '..\..\Anderes'));
  Assert.IsFalse(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo', 'a\..\..\b'), 'zwischendurch draußen');
  Assert.IsFalse(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo', 'C:\Repo\Vorlagen'), 'absolut');
  Assert.IsFalse(TTextCheckin.StaysInside('C:\Repo', 'C:\Repo', '\Vorlagen'));
  Assert.IsFalse(TTextCheckin.StaysInside('C:\Repo', 'C:\Anderes', 'x'), 'Basis außerhalb der Wurzel');
end;

initialization
  TDUnitX.RegisterTestFixture(TTextCheckinTests);

end.
