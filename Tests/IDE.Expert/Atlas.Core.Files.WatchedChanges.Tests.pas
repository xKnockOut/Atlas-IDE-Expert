unit Atlas.Core.Files.WatchedChanges.Tests;

// Tests für Dateiänderungen außerhalb der IDE (#395).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWatchedChangesTests = class
  public
    [Test]
    procedure WaitsUntilQuiet;
    [Test]
    procedure MergesEventsPerFile;
    [Test]
    procedure IgnoresOtherFilesAndFolders;
    [Test]
    procedure RootsPreferGitWorkingTree;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Files.WatchedChanges;

function Text(const AChanges: TArray<TAtlasFileChange>): string;
const
  Names: array[TAtlasFileChangeKind] of string = ('neu', 'geändert', 'gelöscht');
var
  Change: TAtlasFileChange;
begin
  Result := '';
  for Change in AChanges do
    Result := Result + ExtractFileName(Change.FileName) + '=' + Names[Change.Kind] + ' ';
end;

procedure TAtlasWatchedChangesTests.WaitsUntilQuiet;
var
  Changes: TAtlasWatchedChanges;
begin
  Changes := TAtlasWatchedChanges.Create;
  try
    Assert.AreEqual('', Text(Changes.Take(1000)));
    Changes.Add('C:\P\A.pas', TAtlasWatchedChanges.ActionModified, 1000);
    Changes.Add('C:\P\B.pas', TAtlasWatchedChanges.ActionModified, 1200);
    // Zeit seit dem letzten Ereignis zählt, nicht seit dem ersten.
    Assert.AreEqual('', Text(Changes.Take(1200 + TAtlasWatchedChanges.QuietMs - 1)));
    Assert.AreEqual('A.pas=geändert B.pas=geändert ', Text(Changes.Take(1200 + TAtlasWatchedChanges.QuietMs)));
    Assert.AreEqual('', Text(Changes.Take(5000)), 'nur einmal');
  finally
    Changes.Free;
  end;
end;

procedure TAtlasWatchedChangesTests.MergesEventsPerFile;
var
  Changes: TAtlasWatchedChanges;
begin
  Changes := TAtlasWatchedChanges.Create;
  try
    Changes.Add('C:\P\Twice.pas', TAtlasWatchedChanges.ActionModified, 0);
    Changes.Add('c:\p\twice.pas', TAtlasWatchedChanges.ActionModified, 0);
    // Kurz angelegt und wieder gelöscht (Sicherung eines Editors): nichts.
    Changes.Add('C:\P\Temp.pas', TAtlasWatchedChanges.ActionAdded, 0);
    Changes.Add('C:\P\Temp.pas', TAtlasWatchedChanges.ActionRemoved, 0);
    Changes.Add('C:\P\New.pas', TAtlasWatchedChanges.ActionAdded, 0);
    Changes.Add('C:\P\New.pas', TAtlasWatchedChanges.ActionModified, 0);
    Changes.Add('C:\P\Gone.pas', TAtlasWatchedChanges.ActionModified, 0);
    Changes.Add('C:\P\Gone.pas', TAtlasWatchedChanges.ActionRemoved, 0);
    // Speichern über Löschen und Neuanlegen (git checkout, manche Editoren).
    Changes.Add('C:\P\Replaced.pas', TAtlasWatchedChanges.ActionRemoved, 0);
    Changes.Add('C:\P\Replaced.pas', TAtlasWatchedChanges.ActionAdded, 0);
    // Umbenennen: alter Name gelöscht, neuer angelegt.
    Changes.Add('C:\P\Old.pas', TAtlasWatchedChanges.ActionRenamedOld, 0);
    Changes.Add('C:\P\Renamed.pas', TAtlasWatchedChanges.ActionRenamedNew, 0);
    Assert.AreEqual('Twice.pas=geändert New.pas=neu Gone.pas=gelöscht Replaced.pas=geändert ' +
      'Old.pas=gelöscht Renamed.pas=neu ', Text(Changes.Take(TAtlasWatchedChanges.QuietMs)));
  finally
    Changes.Free;
  end;
end;

procedure TAtlasWatchedChangesTests.IgnoresOtherFilesAndFolders;
begin
  Assert.IsTrue(TAtlasWatchedChanges.IsWatched('C:\P\A.PAS'));
  Assert.IsTrue(TAtlasWatchedChanges.IsWatched('C:\P\Defs.inc'));
  Assert.IsTrue(TAtlasWatchedChanges.IsWatched('C:\P\Main.dfm'));
  Assert.IsTrue(TAtlasWatchedChanges.IsWatched('C:\P\App.dproj'));
  Assert.IsTrue(TAtlasWatchedChanges.IsWatched('C:\P\Gruppe.groupproj'));
  Assert.IsFalse(TAtlasWatchedChanges.IsWatched('C:\P\README.md'));
  Assert.IsFalse(TAtlasWatchedChanges.IsWatched('C:\P\Win64\Debug\A.dcu'));
  Assert.IsFalse(TAtlasWatchedChanges.IsWatched('C:\P\.git\index'));
  Assert.IsFalse(TAtlasWatchedChanges.IsWatched('C:\P\__history\A.pas.~1~'));
  Assert.IsFalse(TAtlasWatchedChanges.IsWatched('C:\P\__recovery\A.pas'));
end;

procedure TAtlasWatchedChangesTests.RootsPreferGitWorkingTree;
var
  Roots: TArray<string>;
begin
  Roots := TAtlasWatchedChanges.Roots(
    ['C:\Repo\App\App.dproj', 'C:\Repo\Lib\Lib.dproj', 'C:\Other\Sub\X\X.dproj', 'C:\Solo\S.dproj',
    'C:\Solo\Inner\T.dproj', 'c:\solo\s2.dproj'],
    function(const APath: string): Boolean
    begin
      Result := SameText(APath, 'C:\Repo\.git') or SameText(APath, 'C:\Other\Sub\.git');
    end);
  Assert.AreEqual(3, Integer(Length(Roots)));
  Assert.AreEqual('C:\Repo', Roots[0]);
  Assert.AreEqual('C:\Other\Sub', Roots[1]);
  Assert.AreEqual('C:\Solo', Roots[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWatchedChangesTests);

end.
