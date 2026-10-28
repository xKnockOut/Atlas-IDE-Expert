unit Atlas.Core.Projects.Vcs.Tests;

// Versionsverwaltung und Hauptbranch je Projekt (#1286) ohne Dateien und
// Prozesse: Liste lesen und schreiben, Reihenfolge der Auflösung (.atlas →
// .dproj → .groupproj → längster Ordner → global vcs.provider), Auflösung je
// Ordner für die Änderungsmarken, Art „Aus“, Vorrang der .atlas je Feld und
// überdeckte Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsProjectsTests = class
  public
    [Test]
    procedure ReadAndWriteRoundTrip;
    [Test]
    procedure ReadSkipsEmptyDuplicateAndUnknown;
    /// <summary>Abnahme: Reihenfolge .atlas → .dproj → .groupproj → längster Ordner → global.</summary>
    [Test]
    procedure ResolveFollowsOrder;
    /// <summary>Abnahme: Kasse → SVN, Kasse\Fremd\Lib → Git; Units unter Lib Git, der Rest SVN.</summary>
    [Test]
    procedure FolderResolutionUsesLongestRow;
    /// <summary>Abnahme: Art „Aus“ für ein Netzlaufwerk (UNC).</summary>
    [Test]
    procedure OffRowDisablesNetworkShare;
    /// <summary>Abnahme: .atlas mit mainBranch gilt vor der persönlichen Zeile; diese ist überdeckt.</summary>
    [Test]
    procedure TeamFileWinsPerFieldAndCoversRows;
    /// <summary>Abnahme: Leere Liste und keine .atlas: wie bisher das globale vcs.provider.</summary>
    [Test]
    procedure EmptyListBehavesAsBefore;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Projects.Matching,
  Atlas.Core.Projects.Vcs,
  Atlas.Core.Vcs.Contract;

const
  cKasseFolder = 'C:\Projekte\Kasse';
  cKasseGroup = 'C:\Projekte\Kasse\Kasse.groupproj';
  cKasseProject = 'C:\Projekte\Kasse\App\Kasse.dproj';
  cLibFolder = 'C:\Projekte\Kasse\Fremd\Lib';

function Row(const AMatch, AProvider, AMain: string): TAtlasVcsProjectMapping;
begin
  Result := TAtlasVcsProjectMapping.Create(AMatch, AProvider, AMain);
end;

{ TAtlasVcsProjectsTests }

procedure TAtlasVcsProjectsTests.ReadAndWriteRoundTrip;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mJson: string;
begin
  Assert.AreEqual('[]', TAtlasVcsProjects.ToJson(nil));
  mRows := [Row(cKasseFolder, 'svn', ''), Row(cLibFolder, 'GIT', 'develop'),
    TAtlasVcsProjectMapping.FromTeamFile(cKasseProject, 'git', 'main')];
  mJson := TAtlasVcsProjects.ToJson(mRows);
  Assert.AreEqual('[{"match": "C:\\Projekte\\Kasse", "provider": "svn"}, ' +
    '{"match": "C:\\Projekte\\Kasse\\Fremd\\Lib", "provider": "git", "mainBranch": "develop"}]', mJson,
    'ohne Zeile aus der .atlas, ohne leeren Hauptbranch');
  mRows := TAtlasVcsProjects.Read(mJson);
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual(cLibFolder, mRows[1].Match);
  Assert.AreEqual('git', mRows[1].Provider);
  Assert.AreEqual('develop', mRows[1].MainBranch);
  Assert.IsFalse(mRows[1].ReadOnly);
  Assert.IsTrue(mRows[0].Kind = TAtlasProjectMatch.Folder);
end;

procedure TAtlasVcsProjectsTests.ReadSkipsEmptyDuplicateAndUnknown;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
begin
  mRows := TAtlasVcsProjects.Read('[{"match": ""}, 3, {"match": "C:\\A", "provider": "cvs"}, ' +
    '{"match": "c:/a/", "provider": "git"}, {"match": "C:\\B", "mainBranch": 5}]');
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('auto', mRows[0].Provider, 'unbekannte Art: automatisch');
  Assert.AreEqual('', mRows[1].MainBranch, 'Zahl statt Text');
  Assert.AreEqual(0, Integer(Length(TAtlasVcsProjects.Read('{"match": "C:\\A"}'))));
  Assert.AreEqual(0, Integer(Length(TAtlasVcsProjects.Read('kaputt'))));
end;

procedure TAtlasVcsProjectsTests.ResolveFollowsOrder;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mResult: TAtlasVcsProjectResolution;
begin
  mRows := [Row('C:\Projekte', 'off', ''), Row(cKasseFolder, 'svn', 'trunk'), Row(cKasseGroup, 'git', 'develop'),
    Row(cKasseProject, 'git', 'main')];
  mResult := TAtlasVcsProjects.Resolve('', '', mRows, TAtlasVcsProvider.Auto, cKasseProject, cKasseGroup);
  Assert.IsTrue(mResult.Match = TAtlasProjectMatch.Project);
  Assert.AreEqual('main', mResult.MainBranch);
  Assert.IsTrue(mResult.Source = TAtlasVcsProviderSource.Project);
  Assert.AreEqual(cKasseProject, mResult.SourceMatch);
  mResult := TAtlasVcsProjects.Resolve('', '', mRows, TAtlasVcsProvider.Auto, 'C:\Projekte\Kasse\Tool\T.dproj',
    cKasseGroup);
  Assert.IsTrue(mResult.Match = TAtlasProjectMatch.Group);
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Git);
  mResult := TAtlasVcsProjects.Resolve('', '', mRows, TAtlasVcsProvider.Auto, 'C:\Projekte\Kasse\Tool\T.dproj', '');
  Assert.IsTrue(mResult.Match = TAtlasProjectMatch.Folder);
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Svn);
  Assert.AreEqual(1, mResult.Index);
  mResult := TAtlasVcsProjects.Resolve('', '', mRows, TAtlasVcsProvider.Svn, 'D:\Anders\A.dproj', '');
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Svn, 'global');
  Assert.IsTrue(mResult.Source = TAtlasVcsProviderSource.Setting);
  Assert.AreEqual('', mResult.MainBranch);
  Assert.AreEqual(-1, mResult.Index);
end;

procedure TAtlasVcsProjectsTests.FolderResolutionUsesLongestRow;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
begin
  mRows := [Row(cKasseFolder + '\', 'svn', ''), Row(cLibFolder + '\', 'git', '')];
  Assert.IsTrue(TAtlasVcsProjects.ResolveFolder('', '', mRows, TAtlasVcsProvider.Auto,
    cLibFolder + '\Source').Provider = TAtlasVcsProvider.Git);
  Assert.IsTrue(TAtlasVcsProjects.ResolveFolder('', '', mRows, TAtlasVcsProvider.Auto,
    'C:\Projekte\Kasse\App').Provider = TAtlasVcsProvider.Svn);
  Assert.IsTrue(TAtlasVcsProjects.ResolveFolder('', '', mRows, TAtlasVcsProvider.Auto,
    'C:\Projekte\Anders').Provider = TAtlasVcsProvider.Auto);
end;

procedure TAtlasVcsProjectsTests.OffRowDisablesNetworkShare;
var
  mResult: TAtlasVcsProjectResolution;
begin
  mResult := TAtlasVcsProjects.ResolveFolder('', '', [Row('\\NAS\Projekte', 'off', '')], TAtlasVcsProvider.Auto,
    '\\nas\projekte\Alt\Source');
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Off);
  Assert.AreEqual('\\NAS\Projekte', mResult.SourceMatch);
end;

procedure TAtlasVcsProjectsTests.TeamFileWinsPerFieldAndCoversRows;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mResult: TAtlasVcsProjectResolution;
  mContext: TAtlasVcsProjectContext;
begin
  mRows := [Row(cKasseProject, 'svn', 'trunk')];
  // Nur mainBranch in der .atlas: Hauptbranch aus der Datei, Art aus der Zeile.
  mResult := TAtlasVcsProjects.Resolve('', 'develop', mRows, TAtlasVcsProvider.Auto, cKasseProject, '');
  Assert.AreEqual('develop', mResult.MainBranch);
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Svn);
  Assert.IsTrue(mResult.Source = TAtlasVcsProviderSource.Project);
  Assert.IsTrue(mResult.Match = TAtlasProjectMatch.TeamFile);
  mResult := TAtlasVcsProjects.Resolve('git', '', mRows, TAtlasVcsProvider.Auto, cKasseProject, '');
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Git);
  Assert.IsTrue(mResult.Source = TAtlasVcsProviderSource.TeamFile);
  Assert.AreEqual('trunk', mResult.MainBranch, 'Hauptbranch der Zeile, wenn die .atlas keinen setzt');
  Assert.IsTrue(TAtlasVcsProjects.Covered(mRows[0], True, cKasseProject, ''));
  Assert.IsFalse(TAtlasVcsProjects.Covered(mRows[0], False, cKasseProject, ''));
  Assert.IsFalse(TAtlasVcsProjects.Covered(TAtlasVcsProjectMapping.FromTeamFile(cKasseProject, 'git', ''), True,
    cKasseProject, ''), 'die Zeile der .atlas selbst');
  mContext := TAtlasVcsProjectContext.Empty;
  Assert.IsFalse(mContext.HasTeam);
  mContext.Team := [TAtlasVcsProjectMapping.FromTeamFile(cKasseProject, 'git', '')];
  Assert.IsTrue(mContext.HasTeam);
  Assert.IsTrue(mContext.Team[0].ReadOnly);
end;

procedure TAtlasVcsProjectsTests.EmptyListBehavesAsBefore;
var
  mResult: TAtlasVcsProjectResolution;
begin
  mResult := TAtlasVcsProjects.Resolve('', '', nil, TAtlasVcsProvider.Git, cKasseProject, cKasseGroup);
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Git);
  Assert.IsTrue(mResult.Source = TAtlasVcsProviderSource.Setting);
  Assert.IsTrue(mResult.Match = TAtlasProjectMatch.None);
  Assert.AreEqual('', mResult.MainBranch, 'raten wie bisher');
  mResult := TAtlasVcsProjects.ResolveFolder('', '', nil, TAtlasVcsProvider.Off, cKasseFolder);
  Assert.IsTrue(mResult.Provider = TAtlasVcsProvider.Off);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsProjectsTests);

end.
