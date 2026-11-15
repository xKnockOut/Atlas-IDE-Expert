unit Atlas.Core.Tracker.TestFetch.Tests;

// Abfrage beim Build-Server für die Kachel „Testergebnisse“ (#763, #1967) ohne IDE: Schalter, Job aus .atlas,
// Auswahl der Projekte, derselbe Job nur einmal, Alter gelesener Werte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTestFetchPlanTests = class
  public
    /// <summary>welcomePage.tests.ci aus oder ohne Zugang: kein Netzzugriff.</summary>
    [Test]
    procedure FetchesOnlyWithTilesCiAndAccess;
    [Test]
    procedure JobFromTeamFileWithDefaultProvider;
    [Test]
    procedure WantedConfiguredIdleAndFiltered;
    /// <summary>Projektgruppe und ihr Testprojekt mit demselben Job: eine Abfrage für beide.</summary>
    [Test]
    procedure SameJobFetchedOnce;
    [Test]
    procedure FreshBelowMaxAge;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.TestFetch,
  Atlas.Core.Tracker.TestResults;

function TeamCi(const AProvider, AUrl: string): TAtlasTeamCi;
begin
  Result := Default(TAtlasTeamCi);
  Result.Provider := AProvider;
  Result.Url := AUrl;
  Result.Job := 'team/kasse';
end;

function TestProject(const AProject, AUrl: string; AQuerying: Boolean): TAtlasTestProject;
begin
  Result := Default(TAtlasTestProject);
  Result.Project := AProject;
  Result.Job := TAtlasCiJob.Create('jenkins', AUrl, 'team/kasse', False, '');
  Result.Querying := AQuerying;
end;

{ TAtlasTestFetchPlanTests }

procedure TAtlasTestFetchPlanTests.FetchesOnlyWithTilesCiAndAccess;
begin
  Assert.IsTrue(TAtlasTestFetchPlan.Fetches(True, True, True, True));
  Assert.IsFalse(TAtlasTestFetchPlan.Fetches(False, True, True, True), 'nicht gestartet');
  Assert.IsFalse(TAtlasTestFetchPlan.Fetches(True, False, True, True), 'Kachel aus');
  Assert.IsFalse(TAtlasTestFetchPlan.Fetches(True, True, False, True), 'welcomePage.tests.ci aus');
  Assert.IsFalse(TAtlasTestFetchPlan.Fetches(True, True, True, False), 'ohne Zugang');
end;

procedure TAtlasTestFetchPlanTests.JobFromTeamFileWithDefaultProvider;
var
  mJob: TAtlasCiJob;
  mCi: TAtlasTeamCi;
begin
  mJob := TAtlasTestFetchPlan.JobOf(TeamCi('', 'https://ci.example'), 'jenkins', 'main');
  Assert.AreEqual('jenkins', mJob.Provider, 'Vorgabe der Einstellungen');
  Assert.AreEqual('https://ci.example', mJob.Url);
  Assert.AreEqual('team/kasse', mJob.Job);
  Assert.AreEqual('main', mJob.Branch);
  mCi := TeamCi('gitlab', 'https://ci.example');
  mCi.Multibranch := True;
  mJob := TAtlasTestFetchPlan.JobOf(mCi, 'jenkins', 'feature/x');
  Assert.AreEqual('gitlab', mJob.Provider);
  Assert.IsTrue(mJob.Multibranch);
  Assert.IsFalse(TAtlasTestFetchPlan.JobOf(TeamCi('jenkins', ''), 'jenkins', 'main').Configured, 'ohne Adresse');
  Assert.IsFalse(TAtlasTestFetchPlan.NoJob.Configured);
end;

procedure TAtlasTestFetchPlanTests.WantedConfiguredIdleAndFiltered;
var
  mItem: TAtlasTestProject;
begin
  mItem := TestProject('C:\P\Kasse.dproj', 'https://ci.example', False);
  Assert.IsTrue(TAtlasTestFetchPlan.Wanted(mItem, '', ''));
  Assert.IsTrue(TAtlasTestFetchPlan.Wanted(mItem, 'c:\p\kasse.dproj', ''), 'Projekt ohne Groß/klein');
  Assert.IsFalse(TAtlasTestFetchPlan.Wanted(mItem, 'C:\P\Anders.dproj', ''));
  Assert.IsTrue(TAtlasTestFetchPlan.Wanted(mItem, '', 'https://ci.example'));
  Assert.IsFalse(TAtlasTestFetchPlan.Wanted(mItem, '', 'https://anders.example'), 'anderer Server');
  Assert.IsFalse(TAtlasTestFetchPlan.Wanted(TestProject('C:\P\Kasse.dproj', 'https://ci.example', True), '', ''),
    'läuft schon');
  Assert.IsFalse(TAtlasTestFetchPlan.Wanted(TestProject('C:\P\Kasse.dproj', '', False), '', ''), 'ohne Server');
end;

procedure TAtlasTestFetchPlanTests.SameJobFetchedOnce;
var
  mList: TArray<TAtlasTestResultsFetch>;
begin
  mList := nil;
  TAtlasTestFetchPlan.AddFetch(mList, TestProject('C:\P\Gruppe.groupproj', 'https://ci.example', False));
  TAtlasTestFetchPlan.AddFetch(mList, TestProject('C:\P\Tests.dproj', 'https://CI.example/', False));
  TAtlasTestFetchPlan.AddFetch(mList, TestProject('C:\P\Anders.dproj', 'https://anders.example', False));
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual(2, Integer(Length(mList[0].Projects)));
  Assert.AreEqual('C:\P\Tests.dproj', mList[0].Projects[1]);
  Assert.AreEqual('C:\P\Anders.dproj', mList[1].Projects[0]);
end;

procedure TAtlasTestFetchPlanTests.FreshBelowMaxAge;
begin
  Assert.IsTrue(TAtlasTestFetchPlan.Fresh(1000, 5999, 5000));
  Assert.IsFalse(TAtlasTestFetchPlan.Fresh(1000, 6000, 5000));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestFetchPlanTests);

end.
