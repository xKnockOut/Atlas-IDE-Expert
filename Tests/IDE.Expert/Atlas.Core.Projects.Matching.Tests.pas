unit Atlas.Core.Projects.Matching.Tests;

// Gemeinsame Auflösung „Gilt für“ (#1261, #1286) ohne Dateien: Art der Zeile,
// Pfadvergleich (Groß-/Kleinschreibung, „/“, Laufwerk, UNC), Reihenfolge für
// ein Projekt (.dproj → .groupproj → längster Ordner), Auflösung für einen
// Ordner (längster Ordner, bei Gleichstand .dproj vor .groupproj vor Ordner)
// und Zeilen, die nicht zählen dürfen. Die Tracker-Zuordnung
// (Atlas.Core.Tracker.Projects.Tests) und die Versionsverwaltung je Projekt
// (Atlas.Core.Projects.VersionControl.Tests) prüfen dieselbe Auflösung über ihre Zeilen.

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
  begin
    Result[mIndex] := A[mIndex];
  end;
end;

{ TAtlasProjectMatchingTests }

procedure TAtlasProjectMatchingTests.KindFollowsExtension;
begin
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Project, TAtlasProjectMatching.KindOf(cKasseProject));
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Group, TAtlasProjectMatching.KindOf('C:\P\Kasse.GROUPPROJ'));
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Folder, TAtlasProjectMatching.KindOf(cKasseFolder + '\'));
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.None, TAtlasProjectMatching.KindOf('  '));
  Assert.AreEqual('c:\projekte\kasse\app', TAtlasProjectMatching.FolderOf(cKasseProject));
  Assert.AreEqual('c:\projekte\kasse', TAtlasProjectMatching.FolderOf('C:/Projekte/Kasse/'));
end;

procedure TAtlasProjectMatchingTests.PathsCompareCaseInsensitiveWithUnc;
begin
  Assert.AreEqual('c:\projekte\kasse', TAtlasProjectMatching.NormalizedPath(' C:/Projekte//Kasse\ '));
  Assert.AreEqual('\\server\freigabe\kasse', TAtlasProjectMatching.NormalizedPath('\\Server\Freigabe\\Kasse\'));
  Assert.AreEqual('c:', TAtlasProjectMatching.NormalizedPath('C:\'), 'Laufwerk ohne Trenner');
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Folder,
    TAtlasProjectMatching.Matches('\\SERVER\freigabe', '\\server\Freigabe\Kasse\Kasse.dproj', ''), 'UNC');
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Project,
    TAtlasProjectMatching.Matches('c:/projekte/kasse/app/KASSE.dproj', cKasseProject, ''));
end;

procedure TAtlasProjectMatchingTests.ProjectBeforeGroupBeforeLongestFolder;
var
  mRows: TArray<string>;
  mFound: TAtlasProjectMatchResult;
begin
  mRows := Rows(['C:\Projekte', cKasseFolder, cKasseGroup, cKasseProject]);
  mFound := TAtlasProjectMatching.Find(mRows, nil, cKasseProject, cKasseGroup);
  Assert.AreEqual(3, mFound.Index);
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Project, mFound.Match);
  mFound := TAtlasProjectMatching.Find(mRows, nil, 'C:\Projekte\Kasse\Tool\Tool.dproj', cKasseGroup);
  Assert.AreEqual(2, mFound.Index, 'Gruppe vor Ordner');
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Group, mFound.Match);
  mFound := TAtlasProjectMatching.Find(mRows, nil, 'C:\Projekte\Kasse\Tool\Tool.dproj', '');
  Assert.AreEqual(1, mFound.Index, 'längster Ordner ohne geöffnete Gruppe');
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Folder, mFound.Match);
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
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Folder, mFound.Match);
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
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Project, mFound.Match);
  mFound := TAtlasProjectMatching.FindForFolder(Rows([cKasseFolder, cKasseGroup]), nil, cKasseFolder);
  Assert.AreEqual(1, mFound.Index);
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.Group, mFound.Match);
end;

procedure TAtlasProjectMatchingTests.FolderMatchesWholeFoldersOnly;
begin
  Assert.AreEqual<TAtlasProjectMatch>(TAtlasProjectMatch.None,
    TAtlasProjectMatching.Matches(cKasseFolder, 'C:\Projekte\Kassenbuch\K.dproj', ''));
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
