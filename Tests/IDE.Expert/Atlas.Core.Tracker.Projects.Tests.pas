unit Atlas.Core.Tracker.Projects.Tests;

// Tests der Zuordnung Delphi-Projekt → Tracker-Projekt (#1261) ohne Netz und
// ohne Dateien: Liste lesen und schreiben, Art der Zeile, Vergleich der Pfade
// (Groß-/Kleinschreibung, „/“, Laufwerk, UNC), Reihenfolge der Auflösung
// (.atlas → .dproj → .groupproj → längster Ordner), überdeckte Zeilen und das
// Ziel für „Meine Issues“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerProjectsTests = class
  public
    [Test]
    procedure ReadAndWriteRoundTrip;
    [Test]
    procedure ReadSkipsIncompleteAndDuplicateRows;
    [Test]
    procedure KindFollowsExtension;
    /// <summary>Abnahme: Pfade ohne Groß-/Kleinschreibung, mit „/“, Laufwerk und UNC.</summary>
    [Test]
    procedure PathsCompareCaseInsensitiveWithUnc;
    /// <summary>Abnahme: Reihenfolge .atlas → .dproj → .groupproj → längster Ordner.</summary>
    [Test]
    procedure ResolveFollowsOrder;
    /// <summary>Abnahme: Eine Zeile für Kasse.groupproj gilt für jedes Projekt der Gruppe, ohne .atlas.</summary>
    [Test]
    procedure GroupRowAppliesToEveryProjectOfTheGroup;
    /// <summary>Ordner nur als ganzer Ordner: C:\Projekte\Kasse gilt nicht für C:\Projekte\Kassenbuch.</summary>
    [Test]
    procedure FolderMatchesWholeFoldersOnly;
    [Test]
    procedure RowWithoutConnectionDoesNotCount;
    /// <summary>Abnahme: Mit .atlas gilt diese; die persönliche Zeile ist überdeckt.</summary>
    [Test]
    procedure TeamFileWinsAndCoversPersonalRows;
    [Test]
    procedure CurrentMatchPrefersOpenGroup;
    /// <summary>Ziel für „Meine Issues“: Anbieter und Adresse der Verbindung, Tracker-Projekt der Zeile.</summary>
    [Test]
    procedure TargetForMyIssues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Welcome.Issues;

const
  cKassePath = 'C:\Projekte\Kasse';
  cKasseGroup = 'C:\Projekte\Kasse\Kasse.groupproj';
  cKasseProject = 'C:\Projekte\Kasse\Kasse.dproj';
  cBonProject = 'C:\Projekte\Kasse\Bon\Bon.dproj';

function Connections: TArray<TAtlasTrackerConnection>;
begin
  Result := TAtlasTrackerConnections.Read('[{"name": "Firma", "provider": "youtrack", ' +
    '"url": "https://youtrack.firma.local"}, {"name": "GitHub", "provider": "github", "url": "https://github.com"}]');
end;

function NoTeam: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('', '', '', '');
end;

{ TAtlasTrackerProjectsTests }

procedure TAtlasTrackerProjectsTests.ReadAndWriteRoundTrip;
var
  mItems, mAgain: TArray<TAtlasTrackerProjectMapping>;
  mJson: string;
begin
  mItems := TAtlasTrackerProjects.Read('[{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", "connection": "Firma", ' +
    '"project": "KASSE"}, {"match": "C:\\Projekte\\Atlas", "connection": "GitHub", "project": "owner/repo"}]');
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual(cKasseGroup, mItems[0].Match);
  Assert.AreEqual('Firma', mItems[0].Connection);
  Assert.AreEqual('KASSE', mItems[0].Project);
  Assert.IsFalse(mItems[0].ReadOnly);
  mJson := TAtlasTrackerProjects.ToJson(mItems);
  mAgain := TAtlasTrackerProjects.Read(mJson);
  Assert.AreEqual(2, Integer(Length(mAgain)));
  Assert.AreEqual('C:\Projekte\Atlas', mAgain[1].Match);
  Assert.AreEqual('owner/repo', mAgain[1].Project);
  // Die Zeile aus der .atlas bleibt dort.
  mItems := mItems + [TAtlasTrackerProjectMapping.FromTeamFile(cBonProject, 'Bon', 'BON')];
  Assert.IsTrue(mItems[2].ReadOnly);
  Assert.IsFalse(TAtlasTrackerProjects.ToJson(mItems).Contains('BON'));
  Assert.AreEqual('[]', TAtlasTrackerProjects.ToJson(nil));
  mItems := nil;
  mAgain := nil;
end;

procedure TAtlasTrackerProjectsTests.ReadSkipsIncompleteAndDuplicateRows;
var
  mItems: TArray<TAtlasTrackerProjectMapping>;
begin
  // Ohne match, ohne connection, kein Objekt; derselbe Pfad mit anderer Schreibweise nur einmal.
  mItems := TAtlasTrackerProjects.Read('[{"connection": "Firma"}, {"match": "C:\\A"}, 3, ' +
    '{"match": "C:\\Projekte\\Kasse", "connection": "Firma"}, {"match": "c:/projekte/kasse/", "connection": "GitHub"}]');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('Firma', mItems[0].Connection);
  Assert.AreEqual('', mItems[0].Project, 'Tracker-Projekt darf fehlen');
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerProjects.Read('{"match": "x"}'))), 'keine Liste');
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerProjects.Read('[{"match": '))), 'kaputt');
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerProjects.Read(''))));
  mItems := nil;
end;

procedure TAtlasTrackerProjectsTests.KindFollowsExtension;
begin
  Assert.IsTrue(TAtlasTrackerProjectMapping.Create(cKasseProject, 'Firma', '').Kind = TAtlasTrackerMatch.Project);
  Assert.IsTrue(TAtlasTrackerProjectMapping.Create('C:\Projekte\Kasse\KASSE.GROUPPROJ', 'Firma', '').Kind =
    TAtlasTrackerMatch.Group);
  Assert.IsTrue(TAtlasTrackerProjectMapping.Create(cKassePath + '\', 'Firma', '').Kind = TAtlasTrackerMatch.Folder);
  Assert.IsTrue(TAtlasTrackerProjectMapping.Create('  ', 'Firma', '').Kind = TAtlasTrackerMatch.None);
end;

procedure TAtlasTrackerProjectsTests.PathsCompareCaseInsensitiveWithUnc;
begin
  Assert.AreEqual('c:\projekte\kasse', TAtlasTrackerProjects.NormalizedPath('C:/Projekte//Kasse/'));
  Assert.AreEqual('c:', TAtlasTrackerProjects.NormalizedPath('C:\'));
  Assert.AreEqual('\\server\freigabe\kasse', TAtlasTrackerProjects.NormalizedPath('\\Server\Freigabe\\Kasse\'));
  Assert.AreEqual('\\server\freigabe', TAtlasTrackerProjects.NormalizedPath('//server/freigabe'));
  Assert.AreEqual('', TAtlasTrackerProjects.NormalizedPath('  '));
  // Projekt auf einer Freigabe, Zeile als Ordner der Freigabe; Laufwerk als Ordner.
  Assert.IsTrue(TAtlasTrackerProjects.Matches(TAtlasTrackerProjectMapping.Create('\\SERVER\Freigabe', 'Firma', ''),
    '\\server\freigabe\Kasse\Kasse.dproj', '') = TAtlasTrackerMatch.Folder);
  Assert.IsTrue(TAtlasTrackerProjects.Matches(TAtlasTrackerProjectMapping.Create('D:\', 'Firma', ''),
    'd:\x\y.dproj', '') = TAtlasTrackerMatch.Folder);
  Assert.IsTrue(TAtlasTrackerProjects.Matches(TAtlasTrackerProjectMapping.Create('D:\', 'Firma', ''),
    'C:\x\y.dproj', '') = TAtlasTrackerMatch.None, 'anderes Laufwerk');
  Assert.IsTrue(TAtlasTrackerProjects.Matches(TAtlasTrackerProjectMapping.Create('c:/projekte/kasse/KASSE.dproj',
    'Firma', ''), cKasseProject, '') = TAtlasTrackerMatch.Project);
end;

procedure TAtlasTrackerProjectsTests.ResolveFollowsOrder;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mResult: TAtlasTrackerResolution;
begin
  mRows := [TAtlasTrackerProjectMapping.Create('C:\Projekte', 'GitHub', 'owner/alle'),
    TAtlasTrackerProjectMapping.Create(cKassePath, 'Firma', 'ORDNER'),
    TAtlasTrackerProjectMapping.Create(cKasseGroup, 'Firma', 'KASSE'),
    TAtlasTrackerProjectMapping.Create(cBonProject, 'Firma', 'BON')];
  // .dproj vor .groupproj vor Ordner.
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, cBonProject, cKasseGroup);
  Assert.IsTrue(mResult.Match = TAtlasTrackerMatch.Project);
  Assert.AreEqual(3, mResult.Index);
  Assert.AreEqual('BON', mResult.Project);
  Assert.AreEqual('Firma', mResult.Connection.Name);
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, cKasseProject, cKasseGroup);
  Assert.IsTrue(mResult.Match = TAtlasTrackerMatch.Group);
  Assert.AreEqual('KASSE', mResult.Project);
  // Ohne geöffnete Gruppe: der längste Ordner (C:\Projekte\Kasse vor C:\Projekte).
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, cKasseProject, '');
  Assert.IsTrue(mResult.Match = TAtlasTrackerMatch.Folder);
  Assert.AreEqual('ORDNER', mResult.Project);
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, 'C:\Projekte\Lager\Lager.dproj', '');
  Assert.AreEqual('owner/alle', mResult.Project);
  Assert.AreEqual('github', mResult.Connection.Provider);
  // Außerhalb aller Zeilen: nichts.
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, 'D:\Anderes\X.dproj', '');
  Assert.IsFalse(mResult.Found);
  Assert.AreEqual(-1, mResult.Index);
  mRows := nil;
end;

procedure TAtlasTrackerProjectsTests.GroupRowAppliesToEveryProjectOfTheGroup;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mProject: string;
  mResult: TAtlasTrackerResolution;
begin
  mRows := [TAtlasTrackerProjectMapping.Create(cKasseGroup, 'Firma', 'KASSE')];
  // Auch ein Projekt der Gruppe außerhalb ihres Ordners.
  for mProject in TArray<string>.Create(cKasseProject, cBonProject, 'D:\Gemeinsam\Basis.dproj') do
  begin
    mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, mProject, cKasseGroup);
    Assert.IsTrue(mResult.Found, mProject);
    Assert.AreEqual('KASSE', mResult.Project, mProject);
    Assert.AreEqual('https://youtrack.firma.local', mResult.Connection.Url);
  end;
  // Ist die Gruppe nicht geöffnet (oder das Projekt nicht darin), gilt die Zeile nicht.
  Assert.IsFalse(TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, cKasseProject, '').Found);
  Assert.IsFalse(TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, cKasseProject,
    'C:\Projekte\Andere.groupproj').Found);
  mRows := nil;
end;

procedure TAtlasTrackerProjectsTests.FolderMatchesWholeFoldersOnly;
var
  mRow: TAtlasTrackerProjectMapping;
begin
  mRow := TAtlasTrackerProjectMapping.Create(cKassePath, 'Firma', 'KASSE');
  Assert.IsTrue(TAtlasTrackerProjects.Matches(mRow, cBonProject, '') = TAtlasTrackerMatch.Folder);
  Assert.IsTrue(TAtlasTrackerProjects.Matches(mRow, 'C:\Projekte\Kassenbuch\X.dproj', '') =
    TAtlasTrackerMatch.None);
  Assert.IsTrue(TAtlasTrackerProjects.Matches(mRow, '', '') = TAtlasTrackerMatch.None);
end;

procedure TAtlasTrackerProjectsTests.RowWithoutConnectionDoesNotCount;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mResult: TAtlasTrackerResolution;
begin
  // Die genauere Zeile verweist auf eine gelöschte Verbindung: die nächste passende gilt.
  mRows := [TAtlasTrackerProjectMapping.Create(cKasseProject, 'Gelöscht', 'ALT'),
    TAtlasTrackerProjectMapping.Create(cKassePath, 'firma', 'KASSE')];
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, cKasseProject, '');
  Assert.IsTrue(mResult.Match = TAtlasTrackerMatch.Folder);
  Assert.AreEqual('KASSE', mResult.Project);
  Assert.AreEqual('Firma', mResult.Connection.Name, 'Name ohne Groß-/Kleinschreibung');
  Assert.IsFalse(TAtlasTrackerProjects.Resolve(NoTeam, mRows, nil, cKasseProject, '').Found, 'keine Verbindungen');
  mRows := nil;
end;

procedure TAtlasTrackerProjectsTests.TeamFileWinsAndCoversPersonalRows;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mTeam: TAtlasTrackerTarget;
  mResult: TAtlasTrackerResolution;
begin
  mRows := [TAtlasTrackerProjectMapping.Create(cKasseProject, 'Firma', 'KASSE'),
    TAtlasTrackerProjectMapping.Create('D:\Anderes', 'Firma', 'X')];
  mTeam := TAtlasTrackerTarget.Create('youtrack', 'https://yt.team.local/', 'TEAM', '');
  mResult := TAtlasTrackerProjects.Resolve(mTeam, mRows, Connections, cKasseProject, '');
  Assert.IsTrue(mResult.Match = TAtlasTrackerMatch.TeamFile);
  Assert.AreEqual(-1, mResult.Index);
  Assert.AreEqual('TEAM', mResult.Project);
  Assert.AreEqual('https://yt.team.local', mResult.Connection.Url);
  Assert.AreEqual('Kasse', mResult.Connection.Name, 'Name wie die Verbindung aus der .atlas auf der Seite');
  Assert.IsTrue(mResult.Connection.ReadOnly);
  // Die Zeile für dasselbe Projekt ist überdeckt, eine fremde nicht; ohne .atlas keine.
  Assert.IsTrue(TAtlasTrackerProjects.Covered(mRows[0], True, cKasseProject, ''));
  Assert.IsFalse(TAtlasTrackerProjects.Covered(mRows[1], True, cKasseProject, ''));
  Assert.IsFalse(TAtlasTrackerProjects.Covered(mRows[0], False, cKasseProject, ''));
  Assert.IsFalse(TAtlasTrackerProjects.Covered(TAtlasTrackerProjectMapping.FromTeamFile(cKasseProject, 'Kasse',
    'TEAM'), True, cKasseProject, ''), 'die Zeile der .atlas selbst');
  // Tracker in der .atlas ohne Adresse zählt nicht: die persönliche Zeile gilt.
  mTeam := TAtlasTrackerTarget.Create('youtrack', '', 'TEAM', '');
  Assert.IsTrue(TAtlasTrackerProjects.Resolve(mTeam, mRows, Connections, cKasseProject, '').Match =
    TAtlasTrackerMatch.Project);
  mRows := nil;
end;

procedure TAtlasTrackerProjectsTests.CurrentMatchPrefersOpenGroup;
begin
  Assert.AreEqual(cKasseGroup, TAtlasTrackerProjects.CurrentMatch(cKasseProject, cKasseGroup));
  Assert.AreEqual(cKasseProject, TAtlasTrackerProjects.CurrentMatch(cKasseProject, ''));
  Assert.AreEqual('', TAtlasTrackerProjects.CurrentMatch('', ''));
  Assert.AreEqual(1, TAtlasTrackerProjects.IndexOfMatch([TAtlasTrackerProjectMapping.Create('C:\A', 'Firma', ''),
    TAtlasTrackerProjectMapping.Create(cKassePath, 'Firma', '')], 'c:/projekte/kasse/'));
end;

procedure TAtlasTrackerProjectsTests.TargetForMyIssues;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mResult: TAtlasTrackerResolution;
  mTarget: TAtlasTrackerTarget;
begin
  mRows := [TAtlasTrackerProjectMapping.Create(cKasseGroup, 'Firma', 'KASSE'),
    TAtlasTrackerProjectMapping.Create('C:\Projekte\Atlas', 'GitHub', 'xKnockOut/Atlas-IDE-Expert')];
  // Persönlich: Anbieter der Verbindung; issues.tracker ändert ihn nicht.
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, cKasseProject, cKasseGroup);
  mTarget := TAtlasWelcomeIssues.TargetFor(mResult, 'github', 'assignee: meine #Ungelöst');
  Assert.AreEqual('youtrack', mTarget.Provider);
  Assert.AreEqual('https://youtrack.firma.local', mTarget.Server);
  Assert.AreEqual('KASSE', mTarget.Project);
  Assert.AreEqual('assignee: meine #Ungelöst', mTarget.Query);
  Assert.IsTrue(mTarget.Configured);
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, 'C:\Projekte\Atlas\Atlas.dproj', '');
  mTarget := TAtlasWelcomeIssues.TargetFor(mResult, '', '');
  Assert.AreEqual('github', mTarget.Provider);
  Assert.AreEqual('xKnockOut/Atlas-IDE-Expert', mTarget.Project);
  Assert.IsTrue(mTarget.Configured);
  // .atlas: wie bisher, issues.tracker ersetzt den Anbieter.
  mResult := TAtlasTrackerProjects.Resolve(TAtlasTrackerTarget.Create('github', 'https://github.com',
    'owner/repo', ''), mRows, Connections, cKasseProject, cKasseGroup);
  Assert.AreEqual('github', TAtlasWelcomeIssues.TargetFor(mResult, '', '').Provider);
  Assert.AreEqual('owner/repo', TAtlasWelcomeIssues.TargetFor(mResult, '', '').Project);
  // Ohne Treffer: kein Ziel, „Meine Issues“ bietet „zuordnen …“ an.
  mResult := TAtlasTrackerProjects.Resolve(NoTeam, mRows, Connections, 'D:\X\X.dproj', '');
  Assert.IsFalse(TAtlasWelcomeIssues.TargetFor(mResult, '', '').Configured);
  mRows := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerProjectsTests);

end.
