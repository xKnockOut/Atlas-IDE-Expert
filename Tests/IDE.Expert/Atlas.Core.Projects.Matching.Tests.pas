unit Atlas.Core.Projects.Matching.Tests;

// Gemeinsame Auflösung „Gilt für“ (#1261, #1286) ohne Dateien: Art der Zeile,
// Pfadvergleich (Groß-/Kleinschreibung, „/“, Laufwerk, UNC), Reihenfolge für
// ein Projekt (.dproj → .groupproj → längster Ordner), Auflösung für einen
// Ordner (längster Ordner, bei Gleichstand .dproj vor .groupproj vor Ordner)
// und Zeilen, die nicht zählen dürfen. Die Tracker-Zuordnung
// (Atlas.Core.Tracker.Projects.Tests) und die Versionsverwaltung je Projekt
// (Atlas.Core.Projects.Vcs.Tests) prüfen dieselbe Auflösung über ihre Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectMatchingTests = class
  public
    [Test]
    procedure KindFollowsExtension;
    [Test]
    procedure PathsCompareCaseInsensitiveWithUnc;
    [Test]
    procedure ProjectBeforeGroupBeforeLongestFolder;
    [Test]
    procedure UnusableRowsDoNotCount;
    [Test]
    procedure FolderQueryPicksLongestFolder;
    [Test]
    procedure FolderQueryTieGoesToProjectFile;
    [Test]
    procedure FolderMatchesWholeFoldersOnly;
    [Test]
    procedure IndexAndCurrentMatch;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Projects.Matching;

const
  cKasseFolder = 'C:\Projekte\Kasse';
  cKasseGroup = 'C:\Projekte\Kasse\Kasse.groupproj';
  cKasseProject = 'C:\Projekte\Kasse\App\Kasse.dproj';
  cLibFolder = 'C:\Projekte\Kasse\Fremd\Lib';

function Rows(const A: array of string): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(A));
  for mIndex := 0 to High(A) do
    Result[mIndex] := A[mIndex];
end;

{ TAtlasProjectMatchingTests }

procedure TAtlasProjectMatchingTests.KindFollowsExtension;
begin
  Assert.IsTrue(TAtlasProjectMatching.KindOf(cKasseProject) = TAtlasProjectMatch.Project);
  Assert.IsTrue(TAtlasProjectMatching.KindOf('C:\P\Kasse.GROUPPROJ') = TAtlasProjectMatch.Group);
  Assert.IsTrue(TAtlasProjectMatching.KindOf(cKasseFolder + '\') = TAtlasProjectMatch.Folder);
  Assert.IsTrue(TAtlasProjectMatching.KindOf('  ') = TAtlasProjectMatch.None);
  Assert.AreEqual('c:\projekte\kasse\app', TAtlasProjectMatching.FolderOf(cKasseProject));
  Assert.AreEqual('c:\projekte\kasse', TAtlasProjectMatching.FolderOf('C:/Projekte/Kasse/'));
end;

procedure TAtlasProjectMatchingTests.PathsCompareCaseInsensitiveWithUnc;
begin
  Assert.AreEqual('c:\projekte\kasse', TAtlasProjectMatching.NormalizedPath(' C:/Projekte//Kasse\ '));
  Assert.AreEqual('\\server\freigabe\kasse', TAtlasProjectMatching.NormalizedPath('\\Server\Freigabe\\Kasse\'));
  Assert.AreEqual('c:', TAtlasProjectMatching.NormalizedPath('C:\'), 'Laufwerk ohne Trenner');
  Assert.IsTrue(TAtlasProjectMatching.Matches('\\SERVER\freigabe', '\\server\Freigabe\Kasse\Kasse.dproj', '') =
    TAtlasProjectMatch.Folder, 'UNC');
  Assert.IsTrue(TAtlasProjectMatching.Matches('c:/projekte/kasse/app/KASSE.dproj', cKasseProject, '') =
    TAtlasProjectMatch.Project);
end;

procedure TAtlasProjectMatchingTests.ProjectBeforeGroupBeforeLongestFolder;
var
  mRows: TArray<string>;
  mFound: TAtlasProjectMatchResult;
begin
  mRows := Rows(['C:\Projekte', cKasseFolder, cKasseGroup, cKasseProject]);
  mFound := TAtlasProjectMatching.Find(mRows, nil, cKasseProject, cKasseGroup);
  Assert.AreEqual(3, mFound.Index);
  Assert.IsTrue(mFound.Match = TAtlasProjectMatch.Project);
  mFound := TAtlasProjectMatching.Find(mRows, nil, 'C:\Projekte\Kasse\Tool\Tool.dproj', cKasseGroup);
  Assert.AreEqual(2, mFound.Index, 'Gruppe vor Ordner');
  Assert.IsTrue(mFound.Match = TAtlasProjectMatch.Group);
  mFound := TAtlasProjectMatching.Find(mRows, nil, 'C:\Projekte\Kasse\Tool\Tool.dproj', '');
  Assert.AreEqual(1, mFound.Index, 'längster Ordner ohne geöffnete Gruppe');
  Assert.IsTrue(mFound.Match = TAtlasProjectMatch.Folder);
  mFound := TAtlasProjectMatching.Find(mRows, nil, 'D:\Anders\A.dproj', '');
  Assert.IsFalse(mFound.Found);
  Assert.AreEqual(-1, mFound.Index);
end;

procedure TAtlasProjectMatchingTests.UnusableRowsDoNotCount;
var
  mUsable: TArray<Boolean>;
  mFound: TAtlasProjectMatchResult;
begin
  SetLength(mUsable, 1);
  mUsable[0] := False;
  // Zeile 0 zählt nicht, Zeile 1 (ohne Angabe) schon.
  mFound := TAtlasProjectMatching.Find(Rows([cKasseProject, cKasseFolder]), mUsable, cKasseProject, '');
  Assert.AreEqual(1, mFound.Index);
  mFound := TAtlasProjectMatching.FindForFolder(Rows([cKasseProject, cKasseFolder]), mUsable,
    'C:\Projekte\Kasse\App');
  Assert.AreEqual(1, mFound.Index);
end;

procedure TAtlasProjectMatchingTests.FolderQueryPicksLongestFolder;
var
  mRows: TArray<string>;
  mFound: TAtlasProjectMatchResult;
begin
  // Abnahme #1286: Kasse → SVN, Fremd\Lib → Git; Units unter Lib gehören zur genaueren Zeile.
  mRows := Rows([cKasseFolder + '\', cLibFolder + '\']);
  mFound := TAtlasProjectMatching.FindForFolder(mRows, nil, cLibFolder + '\Source');
  Assert.AreEqual(1, mFound.Index);
  mFound := TAtlasProjectMatching.FindForFolder(mRows, nil, cLibFolder);
  Assert.AreEqual(1, mFound.Index, 'der Ordner selbst');
  mFound := TAtlasProjectMatching.FindForFolder(mRows, nil, 'C:\Projekte\Kasse\App');
  Assert.AreEqual(0, mFound.Index);
  Assert.IsTrue(mFound.Match = TAtlasProjectMatch.Folder);
  // Eine .dproj-Zeile gilt für ihren Ordner; die genauere Ordnerzeile darunter gewinnt trotzdem.
  mRows := Rows([cKasseGroup, cLibFolder]);
  Assert.AreEqual(0, TAtlasProjectMatching.FindForFolder(mRows, nil, 'C:\Projekte\Kasse\App').Index);
  Assert.AreEqual(1, TAtlasProjectMatching.FindForFolder(mRows, nil, cLibFolder + '\X').Index);
  Assert.IsFalse(TAtlasProjectMatching.FindForFolder(mRows, nil, 'C:\Projekte').Found, 'darüber gilt nichts');
  Assert.IsFalse(TAtlasProjectMatching.FindForFolder(mRows, nil, '').Found);
end;

procedure TAtlasProjectMatchingTests.FolderQueryTieGoesToProjectFile;
var
  mFound: TAtlasProjectMatchResult;
begin
  mFound := TAtlasProjectMatching.FindForFolder(Rows([cKasseFolder, cKasseGroup, 'C:\Projekte\Kasse\Kasse.dproj']),
    nil, cKasseFolder + '\Source');
  Assert.AreEqual(2, mFound.Index);
  Assert.IsTrue(mFound.Match = TAtlasProjectMatch.Project);
  mFound := TAtlasProjectMatching.FindForFolder(Rows([cKasseFolder, cKasseGroup]), nil, cKasseFolder);
  Assert.AreEqual(1, mFound.Index);
  Assert.IsTrue(mFound.Match = TAtlasProjectMatch.Group);
end;

procedure TAtlasProjectMatchingTests.FolderMatchesWholeFoldersOnly;
begin
  Assert.IsTrue(TAtlasProjectMatching.Matches(cKasseFolder, 'C:\Projekte\Kassenbuch\K.dproj', '') =
    TAtlasProjectMatch.None);
  Assert.IsFalse(TAtlasProjectMatching.FindForFolder(Rows([cKasseFolder]), nil, 'C:\Projekte\Kassenbuch').Found);
end;

procedure TAtlasProjectMatchingTests.IndexAndCurrentMatch;
begin
  Assert.AreEqual(1, TAtlasProjectMatching.IndexOfMatch(Rows(['C:\A', cKasseFolder]), 'c:/projekte/kasse/'));
  Assert.AreEqual(-1, TAtlasProjectMatching.IndexOfMatch(Rows(['C:\A']), cKasseFolder));
  Assert.AreEqual(cKasseGroup, TAtlasProjectMatching.CurrentMatch(cKasseProject, cKasseGroup));
  Assert.AreEqual(cKasseProject, TAtlasProjectMatching.CurrentMatch(cKasseProject, ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectMatchingTests);

end.
