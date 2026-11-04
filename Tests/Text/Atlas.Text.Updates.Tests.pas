unit Atlas.Text.Updates.Tests;

// Tests der Versionsdatei und Versionsvergleiche (#495, #1519): SemVer,
// Pakete je IDE, Quelltext, unsichere Adressen und Prüfsummen, Namen der
// Packages.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextUpdatesTests = class
  public
    [Test]
    procedure ComparesSemVer;
    [Test]
    procedure RejectsInvalidVersions;
    [Test]
    procedure MajorOfVersion;
    [Test]
    procedure ParsesPackagesAndSource;
    [Test]
    procedure OldManifestWithoutPackages;
    [Test]
    procedure SkipsUnsafePackages;
    [Test]
    procedure RejectsManifestWithoutVersion;
    [Test]
    procedure RoundTripsJson;
    [Test]
    procedure NamesOfPackages;
    [Test]
    procedure SafeUrls;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Updates;

const
  cSha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

procedure TTextUpdatesTests.ComparesSemVer;
begin
  Assert.IsTrue(TUpdateVersions.Compare('2.0.1', '2.0.0') > 0);
  Assert.IsTrue(TUpdateVersions.Compare('2.0.0', '2.0.0-beta.1') > 0);
  Assert.IsTrue(TUpdateVersions.Compare('2.0.0-beta.2', '2.0.0-beta.10') < 0);
  Assert.IsTrue(TUpdateVersions.Compare('2.0.0-beta', '2.0.0-alpha.3') > 0);
  Assert.AreEqual(0, TUpdateVersions.Compare('1.2.3+abc', '1.2.3'));
  Assert.IsTrue(TUpdateVersions.Compare('10.0.0', '9.9.9') > 0);
  Assert.IsTrue(TUpdateVersions.Compare('kaputt', '0.0.1') < 0);
end;

procedure TTextUpdatesTests.RejectsInvalidVersions;
begin
  Assert.IsTrue(TUpdateVersions.IsValidVersion('2.0.0-beta.1'));
  Assert.IsFalse(TUpdateVersions.IsValidVersion('2.0'));
  Assert.IsFalse(TUpdateVersions.IsValidVersion('02.0.0'));
  Assert.IsFalse(TUpdateVersions.IsValidVersion('v2.0.0'));
  Assert.IsFalse(TUpdateVersions.IsValidVersion(''));
end;

procedure TTextUpdatesTests.MajorOfVersion;
begin
  Assert.AreEqual(2, TUpdateVersions.Major('2.0.1'));
  Assert.AreEqual(-1, TUpdateVersions.Major('x'));
end;

procedure TTextUpdatesTests.ParsesPackagesAndSource;
var
  mManifest: TUpdateManifest;
  mFile: TUpdateFile;
begin
  Assert.IsTrue(TUpdateManifests.TryParse('{"version": "2.0.1", "changes": "https://example.org/c",' +
    ' "packages": {"37.0": {"url": "https://example.org/a.zip", "sha256": "' + cSha + '"}},' +
    ' "source": {"url": "https://example.org/s.zip", "sha256": "' + UpperCase(cSha) + '"}}',
    'https://example.org/releases', mManifest));
  Assert.AreEqual('2.0.1', mManifest.Version);
  Assert.AreEqual('https://example.org/c', mManifest.ChangesUrl);
  Assert.IsTrue(mManifest.PackageFor('37.0', mFile));
  Assert.AreEqual('https://example.org/a.zip', mFile.Url);
  Assert.IsFalse(mManifest.PackageFor('36.0', mFile));
  Assert.IsTrue(mManifest.AnyPackage(mFile));
  Assert.IsTrue(mManifest.Source.IsValid);
  // Prüfsummen klein geschrieben.
  Assert.AreEqual(cSha, mManifest.Source.Sha256);
end;

procedure TTextUpdatesTests.OldManifestWithoutPackages;
var
  mManifest: TUpdateManifest;
  mFile: TUpdateFile;
begin
  Assert.IsTrue(TUpdateManifests.TryParse('{"version": "1.2.0"}', 'https://example.org/releases', mManifest));
  Assert.AreEqual('https://example.org/releases/tag/v1.2.0', mManifest.ChangesUrl);
  Assert.IsFalse(mManifest.AnyPackage(mFile));
  Assert.IsFalse(mManifest.Source.IsValid);
end;

procedure TTextUpdatesTests.SkipsUnsafePackages;
var
  mManifest: TUpdateManifest;
  mFile: TUpdateFile;
begin
  Assert.IsTrue(TUpdateManifests.TryParse('{"version": "2.0.1", "packages": {' +
    '"37.0": {"url": "http://example.org/a.zip", "sha256": "' + cSha + '"},' +
    '"36.0": {"url": "https://example.org/b.zip", "sha256": "123"}},' +
    '"source": {"url": "https://example.org/s zip", "sha256": "' + cSha + '"}}', 'https://example.org/releases',
    mManifest));
  Assert.IsFalse(mManifest.PackageFor('37.0', mFile));
  Assert.IsFalse(mManifest.PackageFor('36.0', mFile));
  Assert.IsFalse(mManifest.Source.IsValid);
end;

procedure TTextUpdatesTests.RejectsManifestWithoutVersion;
var
  mManifest: TUpdateManifest;
begin
  Assert.IsFalse(TUpdateManifests.TryParse('{"changes": "https://example.org"}', 'https://example.org',
    mManifest));
  Assert.IsFalse(TUpdateManifests.TryParse('kein json', 'https://example.org', mManifest));
  Assert.IsFalse(TUpdateManifests.TryParse('{"version": "2.x"}', 'https://example.org', mManifest));
end;

procedure TTextUpdatesTests.RoundTripsJson;
var
  mManifest, mCopy: TUpdateManifest;
  mFile: TUpdateFile;
begin
  Assert.IsTrue(TUpdateManifests.TryParse('{"version": "2.0.1", "changes": "https://example.org/c",' +
    ' "packages": {"37.0": {"url": "https://example.org/a.zip", "sha256": "' + cSha + '"}}}',
    'https://example.org/releases', mManifest));
  Assert.IsTrue(TUpdateManifests.TryParse(TUpdateManifests.ToJson(mManifest), 'https://example.org/releases',
    mCopy));
  Assert.AreEqual('2.0.1', mCopy.Version);
  Assert.IsTrue(mCopy.PackageFor('37.0', mFile));
  Assert.AreEqual(cSha, mFile.Sha256);
end;

procedure TTextUpdatesTests.NamesOfPackages;
begin
  Assert.AreEqual('Atlas.IDE.Debugger', TUpdateVersions.PackageName('C:\Atlas\Win32\Atlas.IDE.Debugger370.bpl'));
  Assert.AreEqual('Atlas.IDE.Base', TUpdateVersions.PackageName('Atlas.IDE.Base290'));
  Assert.IsTrue(TUpdateVersions.IsRequiredPackage('atlas.ide.base'));
  Assert.IsTrue(TUpdateVersions.IsRequiredPackage(TUpdateVersions.ContractsPackage));
  Assert.IsFalse(TUpdateVersions.IsRequiredPackage('Atlas.IDE.Debugger'));
end;

procedure TTextUpdatesTests.SafeUrls;
begin
  Assert.IsTrue(TUpdateVersions.IsSafeUrl('https://github.com/x'));
  Assert.IsFalse(TUpdateVersions.IsSafeUrl('http://github.com/x'));
  Assert.IsFalse(TUpdateVersions.IsSafeUrl('https://github.com/x y'));
  Assert.IsFalse(TUpdateVersions.IsSafeUrl('https://github.com/x'#10));
  Assert.IsTrue(TUpdateVersions.IsSha256(cSha));
  Assert.IsTrue(TUpdateVersions.IsSafeUrl(TUpdateChannels.UrlOf(False)));
  Assert.IsTrue(TUpdateChannels.UrlOf(True).EndsWith('/atlas-version-beta.json'));
  Assert.IsFalse(TUpdateVersions.IsSha256(Copy(cSha, 2, 63)));
end;

end.
