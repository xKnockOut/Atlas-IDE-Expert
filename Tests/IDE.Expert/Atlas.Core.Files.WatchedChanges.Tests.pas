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
  cNames: array[TAtlasFileChangeKind] of string = ('neu', 'geändert', 'gelöscht');
var
  mChange: TAtlasFileChange;
begin
  Result := '';
  for mChange in AChanges do
  begin
    Result := Result + ExtractFileName(mChange.FileName) + '=' + cNames[mChange.Kind] + ' ';
  end;
end;

procedure TAtlasWatchedChangesTests.WaitsUntilQuiet;
var
  mChanges: TAtlasWatchedChanges;
begin
  mChanges := TAtlasWatchedChanges.Create;
  try
    Assert.AreEqual('', Text(mChanges.Take(1000)));
    mChanges.Add('C:\P\A.pas', TAtlasWatchedChanges.cActionModified, 1000);
    mChanges.Add('C:\P\B.pas', TAtlasWatchedChanges.cActionModified, 1200);
    // Zeit seit dem letzten Ereignis zählt, nicht seit dem ersten.
    Assert.AreEqual('', Text(mChanges.Take(1200 + TAtlasWatchedChanges.cQuietMs - 1)));
    Assert.AreEqual('A.pas=geändert B.pas=geändert ', Text(mChanges.Take(1200 + TAtlasWatchedChanges.cQuietMs)));
    Assert.AreEqual('', Text(mChanges.Take(5000)), 'nur einmal');
  finally
    mChanges.Free;
  end;
end;

procedure TAtlasWatchedChangesTests.MergesEventsPerFile;
var
  mChanges: TAtlasWatchedChanges;
begin
  mChanges := TAtlasWatchedChanges.Create;
  try
    mChanges.Add('C:\P\Twice.pas', TAtlasWatchedChanges.cActionModified, 0);
    mChanges.Add('c:\p\twice.pas', TAtlasWatchedChanges.cActionModified, 0);
    // Kurz angelegt und wieder gelöscht (Sicherung eines Editors): nichts.
    mChanges.Add('C:\P\Temp.pas', TAtlasWatchedChanges.cActionAdded, 0);
    mChanges.Add('C:\P\Temp.pas', TAtlasWatchedChanges.cActionRemoved, 0);
    mChanges.Add('C:\P\New.pas', TAtlasWatchedChanges.cActionAdded, 0);
    mChanges.Add('C:\P\New.pas', TAtlasWatchedChanges.cActionModified, 0);
    mChanges.Add('C:\P\Gone.pas', TAtlasWatchedChanges.cActionModified, 0);
    mChanges.Add('C:\P\Gone.pas', TAtlasWatchedChanges.cActionRemoved, 0);
    // Speichern über Löschen und Neuanlegen (git checkout, manche Editoren).
    mChanges.Add('C:\P\Replaced.pas', TAtlasWatchedChanges.cActionRemoved, 0);
    mChanges.Add('C:\P\Replaced.pas', TAtlasWatchedChanges.cActionAdded, 0);
    // Umbenennen: alter Name gelöscht, neuer angelegt.
    mChanges.Add('C:\P\Old.pas', TAtlasWatchedChanges.cActionRenamedOld, 0);
    mChanges.Add('C:\P\Renamed.pas', TAtlasWatchedChanges.cActionRenamedNew, 0);
    Assert.AreEqual('Twice.pas=geändert New.pas=neu Gone.pas=gelöscht Replaced.pas=geändert ' +
      'Old.pas=gelöscht Renamed.pas=neu ', Text(mChanges.Take(TAtlasWatchedChanges.cQuietMs)));
  finally
    mChanges.Free;
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
  mRoots: TArray<string>;
begin
  mRoots := TAtlasWatchedChanges.Roots(
    ['C:\Repo\App\App.dproj', 'C:\Repo\Lib\Lib.dproj', 'C:\Other\Sub\X\X.dproj', 'C:\Solo\S.dproj',
    'C:\Solo\Inner\T.dproj', 'c:\solo\s2.dproj'],
    function(const APath: string): Boolean
    begin
      Result := SameText(APath, 'C:\Repo\.git') or SameText(APath, 'C:\Other\Sub\.git');
    end);
  Assert.AreEqual(3, Integer(Length(mRoots)));
  Assert.AreEqual('C:\Repo', mRoots[0]);
  Assert.AreEqual('C:\Other\Sub', mRoots[1]);
  Assert.AreEqual('C:\Solo', mRoots[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWatchedChangesTests);

end.
