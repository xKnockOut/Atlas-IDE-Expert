unit Atlas.Windows.Projects.Adapters.DelphiInstallation.Tests;

// Läuft gegen die echte Registry. Ohne installiertes Delphi prüfen die Tests
// nur, dass nichts schiefgeht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiInstallationTests = class
  public
    [Test]
    procedure LatestProvidesExpandedLibraryPaths;
    [Test]
    procedure UnknownVersionRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Windows.Projects.Adapters.DelphiInstallation;

{ TDelphiInstallationTests }

procedure TDelphiInstallationTests.LatestProvidesExpandedLibraryPaths;
var
  mInstallation: ILibraryPathProvider;
  mPath: string;
  mVariable: TPair<string, string>;
  mHasBds: Boolean;
begin
  mInstallation := TDelphiInstallation.Latest;
  if mInstallation = nil then
  begin
    Exit;
  end;
  mHasBds := False;
  for mVariable in mInstallation.Variables do
  begin
    if SameText(mVariable.Key, 'BDS') then
    begin
      mHasBds := DirectoryExists(mVariable.Value);
    end;
  end;
  Assert.IsTrue(mHasBds, '$(BDS) zeigt auf einen vorhandenen Ordner');
  for mPath in mInstallation.LibraryPaths('Win64') do
  begin
    Assert.IsFalse(mPath.Contains('$(BDSLIB)') or mPath.Contains('$(Platform)'), mPath);
  end;
end;

procedure TDelphiInstallationTests.UnknownVersionRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TDelphiInstallation.Create('1.0').Free;
    end, EProjectError);
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiInstallationTests);

end.
