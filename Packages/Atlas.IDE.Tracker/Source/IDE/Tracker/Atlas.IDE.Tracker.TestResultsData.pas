unit Atlas.IDE.Tracker.TestResultsData;

// Daten der Kachel „Testergebnisse“ (#763): Projekte der Willkommensseite,
// ihre Zusammenfassungen aus Base samt Branch (#571) und die Jobs aus der
// .atlas (#486); liest beides höchstens alle cCacheMs neu. Eigene Unit neben
// Atlas.IDE.Tracker.TestResults (Quelle und Abfrage). Hauptthread.

interface

uses
  System.Generics.Collections,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.TestResults,
  Atlas.IDE.Tracker.WelcomeLink;

type
  /// <summary>Projekte, Zusammenfassungen und Jobs der Kachel; liest .atlas und Zusammenfassungen höchstens alle
  /// cCacheMs neu. Hauptthread.</summary>
  TAtlasTestResultsData = class
  public const
    /// <summary>So lange gelten gelesene Jobs und Zusammenfassungen.</summary>
    cCacheMs = 5000;
  private type
    TCachedJob = record
      Job: TAtlasCiJob;
      Tick: UInt64;
    end;
    TCachedSummary = record
      Summary: TAtlasProjectSummary;
      Tick: UInt64;
    end;
  private
    FLink: TAtlasTrackerWelcomeLink;
    FQuerying: TDictionary<string, Boolean>;
    FJobs: TDictionary<string, TCachedJob>;
    FSummaries: TDictionary<string, TCachedSummary>;
    FSelected: string;
    function SummaryOf(const AProject: string): TAtlasProjectSummary;
    function JobOf(const AProject, ABranch: string): TAtlasCiJob;
    function ReadJob(const AProject, ABranch: string): TAtlasCiJob;
  public
    constructor Create(ALink: TAtlasTrackerWelcomeLink);
    destructor Destroy; override;
    /// <summary>Normierter Pfad als Schlüssel.</summary>
    class function KeyOf(const AProject: string): string; static;
    /// <summary>Gezeigte Projekte; ACi = welcomePage.tests.ci (ohne weder .atlas noch Netz).</summary>
    function Projects(ACi: Boolean): TArray<TAtlasTestProject>;
    /// <summary>Zusammenfassung von AProject neu lesen ('' = alle).</summary>
    procedure Forget(const AProject: string);
    /// <summary>Abfrage der Projekte AProjects läuft bzw. ist fertig.</summary>
    procedure SetQuerying(const AProjects: TArray<string>; AQuerying: Boolean);
    property Selected: string read FSelected write FSelected;
    /// <summary>Verbindung zur Willkommensseite; nil nach Stop.</summary>
    property Link: TAtlasTrackerWelcomeLink read FLink write FLink;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.TestFetch,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Projects.Summaries;

{ TAtlasTestResultsData }

constructor TAtlasTestResultsData.Create(ALink: TAtlasTrackerWelcomeLink);
begin
  inherited Create;
  FLink := ALink;
  FQuerying := TDictionary<string, Boolean>.Create;
  FJobs := TDictionary<string, TCachedJob>.Create;
  FSummaries := TDictionary<string, TCachedSummary>.Create;
end;

destructor TAtlasTestResultsData.Destroy;
begin
  FSummaries.Free;
  FJobs.Free;
  FQuerying.Free;
  inherited;
end;

function TAtlasTestResultsData.SummaryOf(const AProject: string): TAtlasProjectSummary;
var
  mCached: TCachedSummary;
  mVcs: TAtlasProjectVcs;
begin
  // Die Zusammenfassung nicht bei jedem Zeichnen lesen.
  if FSummaries.TryGetValue(KeyOf(AProject), mCached) and
    TAtlasTestFetchPlan.Fresh(mCached.Tick, GetTickCount64, cCacheMs) then
  begin
    Exit(mCached.Summary);
  end;
  if not TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, AProject, Result) then
  begin
    Result := TAtlasProjectSummary.Create(AProject);
  end;
  // Branch frisch aus dieser Sitzung, sonst der gespeicherte.
  mVcs := TAtlasTrackerWelcomeLink.VcsOf(AProject);
  if mVcs.Branch <> '' then
  begin
    Result.Vcs := mVcs;
  end;
  mCached.Summary := Result;
  mCached.Tick := GetTickCount64;
  FSummaries.AddOrSetValue(KeyOf(AProject), mCached);
end;

function TAtlasTestResultsData.JobOf(const AProject, ABranch: string): TAtlasCiJob;
var
  mKey: string;
  mCached: TCachedJob;
begin
  // .atlas nicht bei jedem Zeichnen lesen.
  mKey := KeyOf(AProject) + '|' + ABranch;
  if FJobs.TryGetValue(mKey, mCached) and TAtlasTestFetchPlan.Fresh(mCached.Tick, GetTickCount64, cCacheMs) then
  begin
    Exit(mCached.Job);
  end;
  Result := ReadJob(AProject, ABranch);
  mCached.Job := Result;
  mCached.Tick := GetTickCount64;
  FJobs.AddOrSetValue(mKey, mCached);
end;

function TAtlasTestResultsData.ReadJob(const AProject, ABranch: string): TAtlasCiJob;
var
  mTeam: TAtlasTeamSettings;
begin
  Result := TAtlasTestFetchPlan.NoJob;
  try
    mTeam := TAtlasIdeTeamFile.ForProject(AProject);
    Result := TAtlasTestFetchPlan.JobOf(mTeam.Ci, TAtlasIdeSettings.Current.WelcomePageTestsCiProvider, ABranch);
  except
    // .atlas nicht lesbar: ohne Build-Server.
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Tracker, E);
    end;
  end;
end;

class function TAtlasTestResultsData.KeyOf(const AProject: string): string;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(AProject);
end;

function TAtlasTestResultsData.Projects(ACi: Boolean): TArray<TAtlasTestProject>;
var
  mProject: TAtlasWelcomeProject;
  mItem: TAtlasTestProject;
begin
  Result := nil;
  if FLink = nil then
  begin
    Exit;
  end;
  for mProject in FLink.Projects do
  begin
    mItem := Default(TAtlasTestProject);
    mItem.Project := mProject.Project;
    mItem.Summary := SummaryOf(mProject.Project);
    mItem.Job := TAtlasTestFetchPlan.NoJob;
    // Ohne welcomePage.tests.ci weder .atlas lesen noch Netz.
    if ACi then
    begin
      mItem.Job := JobOf(mProject.Project, mItem.Summary.Vcs.Branch);
    end;
    mItem.Querying := FQuerying.ContainsKey(KeyOf(mProject.Project));
    Result := Result + [mItem];
  end;
end;

procedure TAtlasTestResultsData.Forget(const AProject: string);
begin
  if AProject = '' then
  begin
    FSummaries.Clear;
  end
  else
  begin
    FSummaries.Remove(KeyOf(AProject));
  end;
end;

procedure TAtlasTestResultsData.SetQuerying(const AProjects: TArray<string>; AQuerying: Boolean);
var
  mProject: string;
begin
  for mProject in AProjects do
  begin
    if AQuerying then
    begin
      FQuerying.AddOrSetValue(KeyOf(mProject), True);
    end
    else
    begin
      FQuerying.Remove(KeyOf(mProject));
    end;
  end;
end;

end.
