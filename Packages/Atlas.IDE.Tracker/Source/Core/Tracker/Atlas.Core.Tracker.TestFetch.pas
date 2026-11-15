unit Atlas.Core.Tracker.TestFetch;

// Entscheidungen der Abfrage beim Build-Server für die Kachel „Testergebnisse“ (#763) ohne IDE prüfbar (#1967);
// die IDE (Atlas.IDE.Tracker.TestResults) ruft nur noch Zusammenfassungen, .atlas, Hintergrundarbeiter und Kachel:
// - Ob überhaupt gefragt wird (welcomePage.tests und welcomePage.tests.ci, Zugang vorhanden).
// - Job eines Projekts aus dem Abschnitt ci von .atlas (ohne Anbieter die Vorgabe der Einstellungen).
// - Welche Projekte gefragt werden (eingerichtet, nicht schon in Abfrage, nur ein Projekt bzw. ein Server) und dass
//   derselbe Job nur einmal gefragt wird.

interface

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.TestResults;

type
  /// <summary>Ein Job und die Projekte, deren Zusammenfassung sein Ergebnis bekommt.</summary>
  TAtlasTestResultsFetch = record
    Job: TAtlasCiJob;
    Projects: TArray<string>;
  end;

  TAtlasTestFetchPlan = class
  public
    /// <summary>Wird beim Build-Server gefragt? Nur mit Kachel (ATests), welcomePage.tests.ci (ACi) und Zugang.
    /// </summary>
    class function Fetches(AStarted, ATests, ACi, AHasAccess: Boolean): Boolean; static;
    /// <summary>Job aus dem Abschnitt ci von .atlas für ABranch; ohne Anbieter ADefaultProvider, ohne Adresse kein
    /// Job.</summary>
    class function JobOf(const ACi: TAtlasTeamCi; const ADefaultProvider, ABranch: string): TAtlasCiJob; static;
    /// <summary>Job ohne Server.</summary>
    class function NoJob: TAtlasCiJob; static;
    /// <summary>AItem fragen? Eingerichtet und nicht schon in Abfrage; AOnly: nur dieses Projekt, AServer: nur Jobs
    /// dieses Servers ('' = alle).</summary>
    class function Wanted(const AItem: TAtlasTestProject; const AOnly, AServer: string): Boolean; static;
    /// <summary>AItem an AList anhängen; derselbe Job (Projektgruppe und ihr Testprojekt) wird einmal gefragt und bei
    /// beiden eingetragen.</summary>
    class procedure AddFetch(var AList: TArray<TAtlasTestResultsFetch>; const AItem: TAtlasTestProject); static;
    /// <summary>Gilt ein gelesener Wert von ATick (ms) bei ANow noch (jünger als AMaxAgeMs)?</summary>
    class function Fresh(ATick, ANow: UInt64; AMaxAgeMs: Cardinal): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasTestFetchPlan.Fetches(AStarted, ATests, ACi, AHasAccess: Boolean): Boolean;
begin
  Result := AStarted and ATests and ACi and AHasAccess;
end;

class function TAtlasTestFetchPlan.JobOf(const ACi: TAtlasTeamCi; const ADefaultProvider,
  ABranch: string): TAtlasCiJob;
var
  mProvider: string;
begin
  Result := NoJob;
  if ACi.Url = '' then
  begin
    Exit;
  end;
  mProvider := ACi.Provider;
  if mProvider = '' then
  begin
    mProvider := ADefaultProvider;
  end;
  Result := TAtlasCiJob.Create(mProvider, ACi.Url, ACi.Job, ACi.Multibranch, ABranch);
end;

class function TAtlasTestFetchPlan.NoJob: TAtlasCiJob;
begin
  Result := TAtlasCiJob.Create('', '', '', False, '');
end;

class function TAtlasTestFetchPlan.Wanted(const AItem: TAtlasTestProject; const AOnly, AServer: string): Boolean;
begin
  Result := AItem.Job.Configured and not AItem.Querying;
  if Result and (AOnly <> '') then
  begin
    Result := SameText(AItem.Project, AOnly);
  end;
  if Result and (AServer <> '') then
  begin
    Result := AItem.Job.Server = AServer;
  end;
end;

class procedure TAtlasTestFetchPlan.AddFetch(var AList: TArray<TAtlasTestResultsFetch>;
  const AItem: TAtlasTestProject);
var
  mIndex: Integer;
  mNext: TAtlasTestResultsFetch;
begin
  for mIndex := 0 to High(AList) do
  begin
    if AList[mIndex].Job.Key = AItem.Job.Key then
    begin
      AList[mIndex].Projects := AList[mIndex].Projects + [AItem.Project];
      Exit;
    end;
  end;
  mNext.Job := AItem.Job;
  mNext.Projects := [AItem.Project];
  AList := AList + [mNext];
end;

class function TAtlasTestFetchPlan.Fresh(ATick, ANow: UInt64; AMaxAgeMs: Cardinal): Boolean;
begin
  Result := ANow - ATick < AMaxAgeMs;
end;

end.
