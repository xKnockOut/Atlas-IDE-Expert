unit Atlas.Windows.Projects.DelphiRegistry.Tests;

// Läuft gegen die echte Registry. Ohne installiertes Delphi prüfen die Tests
// nur, dass nichts schiefgeht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiRegistryTests = class
  public
    [Test]
    procedure VersionsAreSortedAscending;
    [Test]
    procedure EveryVersionHasRootDir;
    [Test]
    procedure UnknownVersionHasNoRootDir;
    [Test]
    procedure MissingKeyOpensNothing;
  end;

implementation

uses
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  Atlas.Windows.Projects.DelphiRegistry;

{ TDelphiRegistryTests }

procedure TDelphiRegistryTests.VersionsAreSortedAscending;
var
  mVersions: TArray<string>;
  mIndex: Integer;
begin
  mVersions := TDelphiRegistry.Versions;
  for mIndex := 1 to High(mVersions) do
  begin
    Assert.IsTrue(StrToFloat(mVersions[mIndex - 1], TFormatSettings.Invariant) <
      StrToFloat(mVersions[mIndex], TFormatSettings.Invariant));
  end;
end;

procedure TDelphiRegistryTests.EveryVersionHasRootDir;
var
  mVersion: string;
  mRoot: string;
begin
  for mVersion in TDelphiRegistry.Versions do
  begin
    mRoot := TDelphiRegistry.RootDirOf(mVersion);
    Assert.AreNotEqual('', mRoot, mVersion);
    Assert.IsFalse(mRoot.EndsWith(PathDelim), mRoot);
  end;
end;

procedure TDelphiRegistryTests.UnknownVersionHasNoRootDir;
begin
  Assert.AreEqual('', TDelphiRegistry.RootDirOf('0.1'));
end;

procedure TDelphiRegistryTests.MissingKeyOpensNothing;
var
  mRegistry: TRegistry;
begin
  mRegistry := TDelphiRegistry.OpenRead(HKEY_CURRENT_USER, TDelphiRegistry.cBdsKey + '\0.1\Fehlt');
  try
    Assert.IsNull(mRegistry);
  finally
    mRegistry.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiRegistryTests);

end.
