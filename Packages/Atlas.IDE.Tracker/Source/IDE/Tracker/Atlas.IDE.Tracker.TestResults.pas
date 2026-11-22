unit Atlas.IDE.Tracker.TestResults;

// Kachel „Testergebnisse“ in der IDE (#763; Kachel des Moduls
// Tracker über Atlas.IDE.Contracts.WelcomeTiles): Quelle der Kachel (für sie
// über Atlas.IDE.Tracker.Adapters.TestResults), Abfrage beim Build-Server im Hintergrund und die
// Aktionen.
// - Projekte: dieselbe Liste wie der Bereich „Projekte“ der Willkommensseite
//   (IAtlasWelcomeProjects), Zusammenfassungen aus Base samt Branch (#571).
//   Lokal gilt der Abschnitt "tests" (letzter DUnitX-Lauf aus der IDE, #69).
// - Build-Server: Server, Job und Multibranch aus der Projektdatei .atlas
//   (#486, Abschnitt ci; ohne Anbieter gilt welcomePage.tests.ci.provider),
//   bei Multibranch der Job des aktuellen Branches. Nur mit
//   welcomePage.tests.ci; sonst kein Netzzugriff. Abgefragt wird beim Anzeigen
//   der Kachel, je Job höchstens alle welcomePage.tests.ci.intervalMinutes
//   (auch nach einem Fehler; gemerkt im Abschnitt "ci" der Zusammenfassung,
//   also auch über einen Neustart hinweg), im Hintergrund mit 5 s für beide
//   Aufrufe zusammen. Ist der Server nicht erreichbar, bleibt der letzte Stand
//   mit „Stand vom …“ stehen; kein Dialog, keine Meldung.
// - Anmeldung: Benutzer und API-Token im Anmeldespeicher von Windows, nie in
//   einer Datei; hinterlegt über „Zugang zum Build-Server hinterlegen …“
//   (Befehl Atlas.CiLogin oder Kontextmenü der Kachel). Ohne Eintrag fragt
//   Atlas ohne Anmeldung (offene Server). Anbieter, Transport und Dialog kommen
//   über IAtlasCiAccess aus der Komposition des Moduls.
// - Rot geworden (neuer Build rot, voriger nicht): Hinweis in der
//   Benachrichtigungszentrale (#601, Quelle buildServer) mit „Im Browser“,
//   abschaltbar mit welcomePage.tests.ci.notify.
// - Aktionen (Atlas.IDE.Tracker.TestActions): Projekt und Test öffnen,
//   „Fehlgeschlagene erneut ausführen“, „Im Debugger“, „Vergleichen“ (#1779)
//   und „Im Browser“.
// - Geänderte Zusammenfassungen (Testlauf, Branch) meldet Base über
//   IAtlasProjectSummaryListener (Atlas.IDE.Tracker.Adapters.TestResults);
//   die Kachel liest dann neu.
// - Protokoll anonym: nur Anbieter, Ergebnis und Fehlerart, nie Adresse, Job,
//   Benutzer oder Token.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.TestFetch,
  Atlas.IDE.Tracker.Access,
  Atlas.IDE.Tracker.TestActions,
  Atlas.IDE.Tracker.WelcomeLink,
  Atlas.Plugin.Diagnostics.WorkerSlot,
  Atlas.Core.Notifications.MessageSink,
  Atlas.Core.Tracker.Contract.TestResults,
  Atlas.IDE.Tracker.TestResultsData;

type
  TAtlasIdeTestResults = class;

  /// <summary>Abfrage beim Build-Server im Hintergrund; Keep hält die Quelle, bis die Ergebnisse im Hauptthread
  /// angekommen sind.</summary>
  TAtlasTestResultsFetchJob = record
    Batch: TArray<TAtlasTestResultsFetch>;
    Access: IAtlasCiAccess;
    Keep: IInterface;
    Owner: TAtlasIdeTestResults;
    /// <summary>Ein Job; Ausnahmen gelten als Netzfehler (kein Dialog, kein Fehler an die IDE).</summary>
    function FetchOne(const AJob: TAtlasCiJob; out ABuild: TAtlasCiBuild; out AError: TAtlasCiFetchError): Boolean;
    procedure Execute;
    /// <summary>Ergebnis eines Jobs an den Hauptthread; eigene Prozedur, damit jede Rückgabe ihre eigenen Werte
    /// behält (die Schleife im Thread läuft weiter).</summary>
    class procedure Deliver(const AKeep: IInterface; AOwner: TAtlasIdeTestResults;
      const AFetch: TAtlasTestResultsFetch; ASucceeded: Boolean; const ABuild: TAtlasCiBuild;
      AError: TAtlasCiFetchError); static;
  end;

  TAtlasIdeTestResults = class(TInterfacedObject)
  public const
    /// <summary>Kennung wie früher als Bereich, damit gespeicherte Layouts gelten.</summary>
    cTileId = 'atlas.tests';
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: nach „Projektverlauf“ in der linken Spalte.
    /// </summary>
    cOrder = 23;
  private
    FLink: TAtlasTrackerWelcomeLink;
    FAccess: IAtlasCiAccess;
    FMessage: TAtlasMessageSink;
    FData: TAtlasTestResultsData;
    FActions: TAtlasTestResultsActions;
    FStarted: Boolean;
    FActive: Boolean;
    FWorker: TAtlasWorkerSlot;
    procedure Changed;
    /// <summary>Fällige Jobs; AForce ohne Intervall, AOnly nur dieses Projekt, AServer nur Jobs dieses Servers
    /// ('' = alle). Derselbe Job (Projektgruppe und ihr Testprojekt) einmal.</summary>
    function DueJobs(AForce: Boolean; const AOnly, AServer: string): TArray<TAtlasTestResultsFetch>;
    procedure Fetch(AForce: Boolean; const AOnly, AServer: string);
    procedure TurnedRed(const AProject: string; const AJob: TAtlasCiJob; const ABuild: TAtlasCiBuild);
    procedure Guarded(const AProc: TProc);
  public
    /// <summary>ALink: Projekte und Kacheln der Willkommensseite (gehört dem Aufrufer). AAccess: Anbieter,
    /// Transport und Zugang des Build-Servers. AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(ALink: TAtlasTrackerWelcomeLink; const AAccess: IAtlasCiAccess; const AMessage: TProc<string>);
    destructor Destroy; override;
    procedure Start;
    /// <summary>Alles lösen und auf die Abfrage warten (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen: Sichtbarkeit und Inhalt neu.</summary>
    procedure Refresh;
    /// <summary>welcomePage.tests an?</summary>
    class function Active: Boolean; static;
    class function Title: string; static;
    /// <summary>Ergebnis eines Jobs im Hauptthread.</summary>
    procedure Fetched(const AFetch: TAtlasTestResultsFetch; ASucceeded: Boolean; const ABuild: TAtlasCiBuild;
      AError: TAtlasCiFetchError);
    /// <summary>Befehl Atlas.CiLogin: Zugang für den Build-Server aus der .atlas des aktiven Projekts.</summary>
    procedure EnterCredentialsForActive;
    /// <summary>Zugang für AJob hinterlegen und danach gleich abfragen.</summary>
    procedure EnterCredentials(const AJob: TAtlasCiJob);
    /// <summary>Geänderte Zusammenfassung (über Atlas.IDE.Tracker.Adapters.TestResults).</summary>
    procedure SummaryChanged(const AProject: string);
    { Für die Kachel (IAtlasTestResultsSource über Atlas.IDE.Tracker.Adapters.TestResults) }
    function View: TAtlasTestResultsView;
    procedure Select(const AProject: string);
    procedure OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    procedure RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
    procedure Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    function CanCompare(const AFailure: TAtlasTestFailureItem): Boolean;
    procedure Compare(const AFailure: TAtlasTestFailureItem);
    procedure Browse(const ARow: TAtlasTestRow);
    procedure QueryNow(const ARow: TAtlasTestRow);
    procedure Credentials(const ARow: TAtlasTestRow);
    procedure OpenProject(const ARow: TAtlasTestRow);
    function CanEnterCredentials: Boolean;
    procedure Shown;
  end;

implementation

uses
  Atlas.Core.Ci.Contract,
  Winapi.Windows,
  System.DateUtils,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.MainThread,
  Atlas.Plugin.Diagnostics.Shutdown,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tracker.TestResults.Strings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Projects.Summaries,
  Atlas.UI.Tracker.TestResults,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.TestResults;

const
  cLogFetched = 'Testergebnisse: %s-Build %s, Tests %d/%d/%d';
  cLogNotFetched = 'Testergebnisse: %s nicht abgefragt (%s)';
  cLogAborted = 'Testergebnisse: Abfrage beim Build-Server mit %s abgebrochen';

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

{ TAtlasTestResultsFetchJob }

function TAtlasTestResultsFetchJob.FetchOne(const AJob: TAtlasCiJob; out ABuild: TAtlasCiBuild;
  out AError: TAtlasCiFetchError): Boolean;
var
  mProvider: IAtlasCiProvider;
begin
  ABuild := TAtlasCiBuild.Empty;
  AError := TAtlasCiFetchError.UnknownProvider;
  Result := False;
  try
    mProvider := Access.Provider(AJob.Provider);
    if mProvider <> nil then
    begin
      // Liest den Zugang aus dem Anmeldespeicher von Windows (ohne Dialog).
      Result := mProvider.Fetch(AJob, Access.Transport(AJob), TAtlasTestResults.cFetchTimeoutMs, ABuild, AError);
    end;
  except
    on E: Exception do
    begin
      Result := False;
      AError := TAtlasCiFetchError.Network;
      TAtlasGuard.Log(Format(cLogAborted, [E.ClassName], TFormatSettings.Invariant));
    end;
  end;
end;

procedure TAtlasTestResultsFetchJob.Execute;
var
  mFetch: TAtlasTestResultsFetch;
  mBuild: TAtlasCiBuild;
  mError: TAtlasCiFetchError;
  mOk: Boolean;
begin
  for mFetch in Batch do
  begin
    if TAtlasShutdown.Signalled then
    begin
      Exit;
    end;
    mOk := FetchOne(mFetch.Job, mBuild, mError);
    if TAtlasShutdown.Signalled then
    begin
      Exit;
    end;
    Deliver(Keep, Owner, mFetch, mOk, mBuild, mError);
  end;
end;

class procedure TAtlasTestResultsFetchJob.Deliver(const AKeep: IInterface; AOwner: TAtlasIdeTestResults;
  const AFetch: TAtlasTestResultsFetch; ASucceeded: Boolean; const ABuild: TAtlasCiBuild; AError: TAtlasCiFetchError);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Tracker,
    procedure
    begin
      if AKeep <> nil then
      begin
        AOwner.Fetched(AFetch, ASucceeded, ABuild, AError);
      end;
    end);
end;

/// <summary>Thread für AJob; eigene Routine, damit die Methodenreferenz nur den Auftrag hält.</summary>
function FetchThread(const AJob: TAtlasTestResultsFetchJob): TThread;
var
  mJob: TAtlasTestResultsFetchJob;
begin
  mJob := AJob;
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      mJob.Execute;
    end);
  Result.FreeOnTerminate := False;
end;

{ TAtlasIdeTestResults }

constructor TAtlasIdeTestResults.Create(ALink: TAtlasTrackerWelcomeLink; const AAccess: IAtlasCiAccess;
  const AMessage: TProc<string>);
begin
  inherited Create;
  FLink := ALink;
  FAccess := AAccess;
  FMessage := TAtlasMessageSink.Create(AMessage);
  FData := TAtlasTestResultsData.Create(ALink);
  FActions := TAtlasTestResultsActions.Create(ALink, AAccess, AMessage);
  FWorker := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasIdeTestResults.Destroy;
begin
  Stop;
  FWorker.Free;
  FActions.Free;
  FData.Free;
  inherited;
end;

procedure TAtlasIdeTestResults.Changed;
begin
  if FStarted and (FLink <> nil) then
  begin
    FLink.TileChanged(cTileId);
  end;
end;

function TAtlasIdeTestResults.DueJobs(AForce: Boolean; const AOnly, AServer: string): TArray<TAtlasTestResultsFetch>;
var
  mItem: TAtlasTestProject;
  mStamp: TDateTime;
  mInterval: Integer;
begin
  Result := nil;
  mStamp := NowUtc;
  mInterval := TAtlasIdeSettings.Current.WelcomePageTestsCiIntervalMinutes;
  for mItem in FData.Projects(True) do
  begin
    if TAtlasTestFetchPlan.Wanted(mItem, AOnly, AServer) and (AForce or
      TAtlasTestResults.Due(TAtlasTestResults.CiFor(mItem.Summary, mItem.Job).Attempt, mStamp, mInterval)) then
    begin
      TAtlasTestFetchPlan.AddFetch(Result, mItem);
    end;
  end;
end;

procedure TAtlasIdeTestResults.Fetch(AForce: Boolean; const AOnly, AServer: string);
var
  mSettings: TAtlasPluginSettings;
  mJob: TAtlasTestResultsFetchJob;
  mFetch: TAtlasTestResultsFetch;
begin
  mSettings := TAtlasIdeSettings.Current;
  // welcomePage.tests.ci aus: kein Netzzugriff. Eine Abfrage zur Zeit; die nächste kommt beim nächsten Anzeigen.
  if not TAtlasTestFetchPlan.Fetches(FStarted, mSettings.WelcomePageTests, mSettings.WelcomePageTestsCi,
    FAccess <> nil) then
  begin
    Exit;
  end;
  FWorker.Prune;
  if FWorker.Busy then
  begin
    Exit;
  end;
  mJob := Default(TAtlasTestResultsFetchJob);
  mJob.Batch := DueJobs(AForce, AOnly, AServer);
  if Length(mJob.Batch) = 0 then
  begin
    Exit;
  end;
  for mFetch in mJob.Batch do
  begin
    FData.SetQuerying(mFetch.Projects, True);
  end;
  Changed;
  mJob.Access := FAccess;
  mJob.Keep := Self;
  mJob.Owner := Self;
  FWorker.Start(FetchThread(mJob));
end;

procedure TAtlasIdeTestResults.Guarded(const AProc: TProc);
begin
  if FStarted then
  begin
    TAtlasGuard.Run(TAtlasFeature.Tracker, AProc);
  end;
end;

procedure TAtlasIdeTestResults.Start;
begin
  FStarted := True;
  FActive := Active;
end;

procedure TAtlasIdeTestResults.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  // Die Abfrage bricht beim Abbruchsignal ab (Transport); kurz warten, dann sich selbst überlassen.
  FWorker.Stop(TAtlasShutdown.cStopMs);
  FLink := nil;
  FActions.Release;
  FData.Link := nil;
end;

procedure TAtlasIdeTestResults.Refresh;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FData.Forget('');
  // welcomePage.tests umgeschaltet bzw. Sprache: Titel und Schalter neu; sonst nur der Inhalt.
  if (FActive <> Active) and (FLink <> nil) then
  begin
    FActive := Active;
    FLink.TileInfoChanged(cTileId);
  end;
  Changed;
end;

class function TAtlasIdeTestResults.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageTests;
end;

class function TAtlasIdeTestResults.Title: string;
begin
  Result := TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsTitle);
end;

procedure TAtlasIdeTestResults.Fetched(const AFetch: TAtlasTestResultsFetch; ASucceeded: Boolean;
  const ABuild: TAtlasCiBuild; AError: TAtlasCiFetchError);
var
  mProject: string;
  mStamp: TDateTime;
  mRed: Boolean;
  mJob: TAtlasCiJob;
  mBuild: TAtlasCiBuild;
begin
  FData.SetQuerying(AFetch.Projects, False);
  if not FStarted then
  begin
    Exit;
  end;
  mStamp := NowUtc;
  mJob := AFetch.Job;
  mBuild := ABuild;
  mRed := False;
  for mProject in AFetch.Projects do
  begin
    TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, mProject,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        mRed := mRed or ASucceeded and TAtlasTestResults.TurnedRed(ASummary.Ci, mJob, mBuild);
        ASummary.Ci := TAtlasTestResults.Recorded(ASummary.Ci, mJob, ASucceeded, mBuild, AError, mStamp);
      end);
    FData.Forget(mProject);
  end;
  // Anonym: Anbieter, Ergebnis bzw. Fehlerart; nie Adresse, Job oder Zugang.
  if ASucceeded then
  begin
    TAtlasGuard.Log(Format(cLogFetched, [AFetch.Job.Provider, TAtlasCiBuild.OutcomeKey(ABuild.Outcome), ABuild.Passed,
      ABuild.Failed, ABuild.Skipped], TFormatSettings.Invariant));
  end
  else
  begin
    TAtlasGuard.Log(Format(cLogNotFetched, [AFetch.Job.Provider, TAtlasCiBuild.ErrorKey(AError)],
      TFormatSettings.Invariant));
  end;
  if mRed and (Length(AFetch.Projects) > 0) then
  begin
    TurnedRed(AFetch.Projects[0], AFetch.Job, ABuild);
  end;
  Changed;
end;

procedure TAtlasIdeTestResults.EnterCredentialsForActive;
var
  mProject: string;
begin
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  if mProject = '' then
  begin
    FMessage.Say(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.CiLoginNoServer));
  end
  else
  begin
    EnterCredentials(TAtlasTestResultsActions.JobOfProject(mProject));
  end;
end;

procedure TAtlasIdeTestResults.EnterCredentials(const AJob: TAtlasCiJob);
var
  mJob: TAtlasCiJob;
begin
  mJob := AJob;
  Guarded(
    procedure
    begin
      if not CanEnterCredentials then
      begin
        Exit;
      end;
      if mJob.Server = '' then
      begin
        FMessage.Say(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.CiLoginNoServer));
      end
      else if FAccess.EnterCredentials(mJob) then
      begin
        // Mit dem neuen Zugang gleich alle Jobs dieses Servers fragen (nur mit welcomePage.tests.ci).
        Fetch(True, '', mJob.Server);
      end;
    end);
end;

procedure TAtlasIdeTestResults.SummaryChanged(const AProject: string);
begin
  FData.Forget(AProject);
  Changed;
end;

/// <summary>„Im Browser“ des Hinweises; eigene Routine, damit die Methodenreferenz nur ihre Werte hält.</summary>
function BrowseAction(const AKeep: IInterface; AActions: TAtlasTestResultsActions;
  const AJob: TAtlasCiJob; ANumber: Integer): TProc;
begin
  Result :=
    procedure
    begin
      if AKeep <> nil then
      begin
        AActions.OpenBuildPage(AJob, ANumber);
      end;
    end;
end;

procedure TAtlasIdeTestResults.TurnedRed(const AProject: string; const AJob: TAtlasCiJob;
  const ABuild: TAtlasCiBuild);
var
  mTitle, mText: string;
  mMode: TAtlasNotificationMode;
begin
  if not TAtlasIdeSettings.Current.WelcomePageTestsCiNotify then
  begin
    Exit;
  end;
  mTitle := TAtlasTestResultsStrings.Fmt(TAtlasTestResultsTextId.NotificationsBuildServerRed,
    [TAtlasTestResults.ProviderCaption(AJob.Provider), ABuild.Number, ChangeFileExt(ExtractFileName(AProject), '')]);
  mText := TAtlasTrackerTestResultsText.BuildText(ABuild);
  if AJob.JobBranch <> '' then
  begin
    mText := mText + TAtlasTrackerTestResultsText.cSeparator + AJob.JobBranch;
  end;
  mMode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cBuildServer,
    TAtlasNotificationSeverity.Error, mTitle, mText,
    [TAtlasNotificationCenter.Action(TAtlasTestResultsStrings.Text(TAtlasTestResultsTextId.WelcomeTestsBrowse),
    BrowseAction(Self, FActions, AJob, ABuild.Number))]);
  // „Einblenden“ (oder Zentrale aus): auch eine Zeile in der Meldungsansicht.
  if mMode = TAtlasNotificationMode.Show then
  begin
    FMessage.Say(mTitle + ' – ' + mText);
  end;
end;

function TAtlasIdeTestResults.View: TAtlasTestResultsView;
var
  mSettings: TAtlasPluginSettings;
begin
  Result := Default(TAtlasTestResultsView);
  Result.Selected := -1;
  if not FStarted or not Active then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasTestResults.View(FData.Projects(mSettings.WelcomePageTestsCi), FData.Selected,
    mSettings.WelcomePageTestsMaxFailures, mSettings.WelcomePageTestsCi);
  // Langsamste Tests nur mit tests.showDuration (#1772).
  if not mSettings.TestsShowDuration then
  begin
    Result.Slowest := nil;
  end;
end;

procedure TAtlasIdeTestResults.Select(const AProject: string);
begin
  FData.Selected := AProject;
  Changed;
end;

procedure TAtlasIdeTestResults.OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
var
  mRow: TAtlasTestRow;
  mItem: TAtlasTestFailureItem;
begin
  mRow := ARow;
  mItem := AFailure;
  Guarded(
    procedure
    begin
      FActions.OpenTest(mRow, mItem);
    end);
end;

procedure TAtlasIdeTestResults.RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
var
  mRow: TAtlasTestRow;
  mTests: TArray<string>;
begin
  mRow := ARow;
  mTests := ATests;
  Guarded(
    procedure
    begin
      FActions.RerunFailed(mRow, mTests);
    end);
end;

procedure TAtlasIdeTestResults.Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
var
  mRow: TAtlasTestRow;
  mItem: TAtlasTestFailureItem;
begin
  mRow := ARow;
  mItem := AFailure;
  Guarded(
    procedure
    begin
      FActions.Debug(mRow, mItem);
    end);
end;

function TAtlasIdeTestResults.CanCompare(const AFailure: TAtlasTestFailureItem): Boolean;
begin
  Result := TAtlasTestResultsActions.CanCompare(AFailure);
end;

procedure TAtlasIdeTestResults.Compare(const AFailure: TAtlasTestFailureItem);
var
  mItem: TAtlasTestFailureItem;
begin
  mItem := AFailure;
  Guarded(
    procedure
    begin
      TAtlasTestResultsActions.Compare(mItem);
    end);
end;

procedure TAtlasIdeTestResults.Browse(const ARow: TAtlasTestRow);
var
  mRow: TAtlasTestRow;
begin
  mRow := ARow;
  Guarded(
    procedure
    begin
      if mRow.HasCi and mRow.Ci.HasBuild then
      begin
        FActions.OpenBuildPage(mRow.Job, mRow.Ci.Build.Number);
      end;
    end);
end;

procedure TAtlasIdeTestResults.QueryNow(const ARow: TAtlasTestRow);
var
  mProject: string;
begin
  mProject := ARow.Project;
  Guarded(
    procedure
    begin
      Fetch(True, mProject, '');
    end);
end;

procedure TAtlasIdeTestResults.Credentials(const ARow: TAtlasTestRow);
begin
  EnterCredentials(ARow.Job);
end;

procedure TAtlasIdeTestResults.OpenProject(const ARow: TAtlasTestRow);
var
  mRow: TAtlasTestRow;
begin
  mRow := ARow;
  Guarded(
    procedure
    begin
      FActions.OpenProject(mRow);
    end);
end;

function TAtlasIdeTestResults.CanEnterCredentials: Boolean;
begin
  Result := FStarted and TAtlasIdeSettings.Current.CiLogin and (FAccess <> nil);
end;

procedure TAtlasIdeTestResults.Shown;
begin
  Fetch(False, '', '');
end;

end.
