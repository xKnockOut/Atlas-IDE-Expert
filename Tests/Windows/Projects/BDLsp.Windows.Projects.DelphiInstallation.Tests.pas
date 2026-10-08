unit BDLsp.Windows.Projects.DelphiInstallation.Tests;

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
    procedure VersionsAreSortedAscending;
    [Test]
    procedure LatestProvidesExpandedLibraryPaths;
    [Test]
    procedure UnknownVersionRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Projects.Contract,
  BDLsp.Windows.Projects.DelphiInstallation;

procedure TDelphiInstallationTests.VersionsAreSortedAscending;
var
  Versions: TArray<string>;
  Index: Integer;
begin
  Versions := TDelphiInstallation.Versions;
  for Index := 1 to High(Versions) do
    Assert.IsTrue(StrToFloat(Versions[Index - 1], TFormatSettings.Invariant) <
      StrToFloat(Versions[Index], TFormatSettings.Invariant));
end;

procedure TDelphiInstallationTests.LatestProvidesExpandedLibraryPaths;
var
  Installation: ILibraryPathProvider;
  Path: string;
  Variable: TPair<string, string>;
  HasBds: Boolean;
begin
  Installation := TDelphiInstallation.Latest;
  if Installation = nil then
    Exit;
  HasBds := False;
  for Variable in Installation.Variables do
    if SameText(Variable.Key, 'BDS') then
      HasBds := DirectoryExists(Variable.Value);
  Assert.IsTrue(HasBds, '$(BDS) zeigt auf einen vorhandenen Ordner');
  for Path in Installation.LibraryPaths('Win64') do
    Assert.IsFalse(Path.Contains('$(BDSLIB)') or Path.Contains('$(Platform)'), Path);
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
