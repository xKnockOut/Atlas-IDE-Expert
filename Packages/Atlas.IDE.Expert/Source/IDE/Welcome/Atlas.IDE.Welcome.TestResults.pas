unit Atlas.IDE.Welcome.TestResults;

// Bereich „Testergebnisse“ in der IDE (#763): Quelle des Bereichs
// (IAtlasTestResultsSource), Anmeldung als Bereich atlas.tests der
// Willkommensseite (bzw. des Fensters „Atlas-Start“), Abfrage beim
// Build-Server im Hintergrund und die Aktionen.
// - Projekte: dieselbe Liste wie der Bereich „Projekte“ (#592, schon geladene
//   Zusammenfassungen samt Branch #571). Lokal gilt der Abschnitt "tests"
//   (letzter DUnitX-Lauf aus der IDE, #69).
// - Build-Server: Server, Job und Multibranch aus der Projektdatei .atlas
//   (#486, Abschnitt ci; ohne Anbieter gilt welcomePage.tests.ci.provider),
//   bei Multibranch der Job des aktuellen Branches. Nur mit
//   welcomePage.tests.ci; sonst kein Netzzugriff. Abgefragt wird beim Anzeigen
//   des Bereichs, je Job höchstens alle welcomePage.tests.ci.intervalMinutes
//   (auch nach einem Fehler; gemerkt im Abschnitt "ci" der Zusammenfassung,
//   also auch über einen Neustart hinweg), im Hintergrund mit 5 s für beide
//   Aufrufe zusammen. Ist der Server nicht erreichbar, bleibt der letzte Stand
//   mit „Stand vom …“ stehen; kein Dialog, keine Meldung.
// - Anmeldung: Benutzer und API-Token im Anmeldespeicher von Windows, nie in
//   einer Datei; hinterlegt über „Zugang zum Build-Server hinterlegen …“
//   (Befehl Atlas.CiLogin oder Kontextmenü des Bereichs). Ohne Eintrag fragt
//   Atlas ohne Anmeldung (offene Server).
// - Rot geworden (neuer Build rot, voriger nicht): Hinweis in der
//   Benachrichtigungszentrale (#601, Quelle buildServer) mit „Im Browser“,
//   abschaltbar mit welcomePage.tests.ci.notify.
// - Aktionen: „Fehlgeschlagene erneut ausführen“ startet genau die Tests der
//   Liste im Testprojekt (#69), „Im Debugger“ den gewählten Test (#585),
//   „Im Browser“ die Seite des Builds; Doppelklick öffnet Projekt und Test
//   (für Server-Fehlschläge über die Testunit im Projekt gesucht).
// - Protokoll anonym: nur Anbieter, Ergebnis und Fehlerart, nie Adresse, Job,
//   Benutzer oder Token.
// Die Verbindung zu Tests, Debugger und Build-Server kommt über Hooks aus der
// Komposition (keine Abhängigkeit zwischen den Features).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.TestResults,
  Atlas.UI.Welcome.Projects,
  Atlas.UI.Welcome.TestResults;

type
  /// <summary>Tests ATests im Testprojekt AProject ausführen (#69).</summary>
  TAtlasTestsRunHook = reference to procedure(const AProject: string; const ATests: TArray<string>);
  /// <summary>Test AFullName im Debugger starten (#585); False mit Grund.</summary>
  TAtlasTestsDebugHook = reference to function(const AProject, AFullName: string; out AReason: string): Boolean;
  /// <summary>Datei und Zeile (ab 1) des Tests AFullName im Testprojekt AProject.</summary>
  TAtlasTestsLocateHook = reference to function(const AProject, AFullName: string; out AFileName: string;
    out ALine: Integer): Boolean;
  /// <summary>CI-Anbieter zum Namen ("jenkins"); nil, wenn es ihn nicht gibt.</summary>
  TAtlasCiProviderHook = reference to function(const AName: string): IAtlasCiProvider;
  /// <summary>Transport für AJob mit dem Zugang aus dem Anmeldespeicher; läuft im Hintergrund-Thread.</summary>
  TAtlasCiTransportHook = reference to function(const AJob: TAtlasCiJob): IAtlasCiTransport;
  /// <summary>Zugang für AJob abfragen und speichern (Dialog); True, wenn sich etwas geändert hat.</summary>
  TAtlasCiCredentialsHook = reference to function(const AJob: TAtlasCiJob): Boolean;

  TAtlasIdeTestResults = class(TInterfacedObject, IAtlasTestResultsSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: nach „Projektverlauf“ in der linken Spalte (Mockup).
    /// </summary>
    Order = 23;
    /// <summary>So lange gilt der gelesene Job aus .atlas, bevor er neu gelesen wird.</summary>
    JobCacheMs = 5000;
  private type
    TCachedJob = record
      Job: TAtlasCiJob;
      Tick: UInt64;
    end;
    /// <summary>Ein Job und die Projekte, deren Zusammenfassung sein Ergebnis bekommt.</summary>
    TFetch = record
      Job: TAtlasCiJob;
      Projects: TArray<string>;
    end;
  private
    FProjects: IAtlasProjectsSource;
    FMessage: TProc<string>;
    FStarted: Boolean;
    FTitle: string;
    FActive: Boolean;
    FSelected: string;
    FThread: TThread;
    // Normierter Pfad → Abfrage läuft.
    FQuerying: TDictionary<string, Boolean>;
    FJobs: TDictionary<string, TCachedJob>;
    FOnRunTests: TAtlasTestsRunHook;
    FOnDebugTest: TAtlasTestsDebugHook;
    FOnLocateTest: TAtlasTestsLocateHook;
    FProviderFactory: TAtlasCiProviderHook;
    FTransportFactory: TAtlasCiTransportHook;
    FOnCredentials: TAtlasCiCredentialsHook;
    procedure Changed;
    procedure Report(const AText: string);
    function JobOf(const AProject, ABranch: string): TAtlasCiJob;
    function Projects: TArray<TAtlasTestProject>;
    /// <summary>Fällige Jobs im Hintergrund abfragen; AForce ohne Intervall, AOnly nur dieses Projekt, AServer nur
    /// Jobs dieses Servers ('' = alle).</summary>
    procedure Fetch(AForce: Boolean; const AOnly, AServer: string);
    procedure Fetched(const AFetch: TFetch; ASucceeded: Boolean; const ABuild: TAtlasCiBuild;
      AError: TAtlasCiFetchError);
    /// <summary>Ergebnis eines Jobs an den Hauptthread; eigene Prozedur, damit jede Rückgabe ihre eigenen Werte
    /// behält (die Schleife im Thread läuft weiter).</summary>
    class procedure Deliver(const AKeep: IAtlasTestResultsSource; AOwner: TAtlasIdeTestResults; const AFetch: TFetch;
      ASucceeded: Boolean; const ABuild: TAtlasCiBuild; AError: TAtlasCiFetchError); static;
    procedure TurnedRed(const AProject: string; const AJob: TAtlasCiJob; const ABuild: TAtlasCiBuild);
    procedure ReleaseThread(AWait: Boolean);
    function EnsureOpen(const AProject: string): Boolean;
    procedure OpenBuildPage(const AJob: TAtlasCiJob; ANumber: Integer);
    class function TestProjectOf(const ARow: TAtlasTestRow): string; static;
    class function NowUtc: TDateTime; static;
    class function ProjectIsOpen(const AFileName: string): Boolean; static;
  public
    /// <summary>AProjects: Bereich „Projekte“ (Liste, Zusammenfassungen, Öffnen). AMessage: Zeile in die
    /// Meldungsansicht.</summary>
    constructor Create(const AProjects: IAtlasProjectsSource; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich und Fabrik anmelden.</summary>
    procedure Start;
    /// <summary>Alles abmelden und auf die Abfrage warten (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen: Sichtbarkeit und Inhalt neu.</summary>
    procedure Refresh;
    function Section: TAtlasWelcomeSection;
    /// <summary>welcomePage.tests an?</summary>
    class function Active: Boolean; static;
    /// <summary>Befehl Atlas.CiLogin: Zugang für den Build-Server aus der .atlas des aktiven Projekts.</summary>
    procedure EnterCredentialsForActive;
    /// <summary>Zugang für AJob hinterlegen und danach gleich abfragen.</summary>
    procedure EnterCredentials(const AJob: TAtlasCiJob);
    property OnRunTests: TAtlasTestsRunHook read FOnRunTests write FOnRunTests;
    property OnDebugTest: TAtlasTestsDebugHook read FOnDebugTest write FOnDebugTest;
    property OnLocateTest: TAtlasTestsLocateHook read FOnLocateTest write FOnLocateTest;
    property ProviderFactory: TAtlasCiProviderHook read FProviderFactory write FProviderFactory;
    property TransportFactory: TAtlasCiTransportHook read FTransportFactory write FTransportFactory;
    property OnCredentials: TAtlasCiCredentialsHook read FOnCredentials write FOnCredentials;
    { IAtlasTestResultsSource }
    function View: TAtlasTestResultsView;
    procedure Select(const AProject: string);
    procedure OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    procedure RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
    procedure Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    procedure Browse(const ARow: TAtlasTestRow);
    procedure QueryNow(const ARow: TAtlasTestRow);
    procedure Credentials(const ARow: TAtlasTestRow);
    procedure OpenProject(const ARow: TAtlasTestRow);
    function CanEnterCredentials: Boolean;
    procedure Shown;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.DateUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Welcome.Projects;

{ TAtlasIdeTestResults }

constructor TAtlasIdeTestResults.Create(const AProjects: IAtlasProjectsSource; const AMessage: TProc<string>);
begin
  inherited Create;
  FProjects := AProjects;
  FMessage := AMessage;
  FQuerying := TDictionary<string, Boolean>.Create;
  FJobs := TDictionary<string, TCachedJob>.Create;
end;

destructor TAtlasIdeTestResults.Destroy;
begin
  Stop;
  ReleaseThread(True);
  FJobs.Free;
  FQuerying.Free;
  inherited;
end;

class function TAtlasIdeTestResults.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageTests;
end;

class function TAtlasIdeTestResults.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

procedure TAtlasIdeTestResults.Start;
var
  Keep: IAtlasTestResultsSource;
begin
  FStarted := True;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Tests,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeTestResultsFrame;
    begin
      Frame := TAtlasWelcomeTestResultsFrame.Create(AOwner);
      Frame.Source := Keep;
      Result := Frame;
    end);
  FTitle := '';
  Refresh;
end;

procedure TAtlasIdeTestResults.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Tests);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Tests);
  // Die Abfrage bricht beim Abbruchsignal ab (Transport); kurz warten, dann sich selbst überlassen.
  ReleaseThread(True);
  FProjects := nil;
  FOnRunTests := nil;
  FOnDebugTest := nil;
  FOnLocateTest := nil;
  FProviderFactory := nil;
  FTransportFactory := nil;
  FOnCredentials := nil;
end;

procedure TAtlasIdeTestResults.ReleaseThread(AWait: Boolean);
begin
  if FThread = nil then
    Exit;
  if AWait and not FThread.Finished then
    TAtlasShutdown.WaitForThreads([FThread]);
  if FThread.Finished then
    FreeAndNil(FThread)
  else if AWait then
  begin
    FThread.FreeOnTerminate := True;
    FThread := nil;
  end;
end;

function TAtlasIdeTestResults.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Tests, TAtlasStrings.Text(TAtlasTextId.WelcomeTestsTitle),
    Order, TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeTestResults.Refresh;
var
  Next: TAtlasWelcomeSection;
begin
  if not FStarted then
    Exit;
  Next := Section;
  // Nur beim ersten Mal (oder nach einem Sprachwechsel) anmelden: Add meldet allen Beobachtern.
  if Next.Title <> FTitle then
  begin
    FTitle := Next.Title;
    FActive := Active;
    TAtlasWelcomeSections.Default.Add(Next);
    Exit;
  end;
  // welcomePage.tests umgeschaltet: Auswahl der Bereiche neu; sonst nur der Inhalt.
  if FActive <> Active then
  begin
    FActive := Active;
    TAtlasWelcomeSections.Default.Changed;
  end;
  Changed;
end;

procedure TAtlasIdeTestResults.Changed;
begin
  if FStarted then
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Tests);
end;

procedure TAtlasIdeTestResults.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeTestResults.JobOf(const AProject, ABranch: string): TAtlasCiJob;
var
  Key: string;
  Cached: TCachedJob;
  Team: TAtlasTeamSettings;
  Provider: string;
begin
  // .atlas nicht bei jedem Zeichnen lesen.
  Key := TAtlasProjectSummaries.NormalizedPath(AProject) + '|' + ABranch;
  if FJobs.TryGetValue(Key, Cached) and (GetTickCount64 - Cached.Tick < JobCacheMs) then
    Exit(Cached.Job);
  Result := TAtlasCiJob.Create('', '', '', False, '');
  try
    Team := TAtlasIdeTeamFile.ForProject(AProject);
    Provider := Team.Ci.Provider;
    if Provider = '' then
      Provider := TAtlasIdeSettings.Current.WelcomePageTestsCiProvider;
    if Team.Ci.Url <> '' then
      Result := TAtlasCiJob.Create(Provider, Team.Ci.Url, Team.Ci.Job, Team.Ci.Multibranch, ABranch);
  except
    // .atlas nicht lesbar: ohne Build-Server.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Cached.Job := Result;
  Cached.Tick := GetTickCount64;
  FJobs.AddOrSetValue(Key, Cached);
end;

function TAtlasIdeTestResults.Projects: TArray<TAtlasTestProject>;
var
  Entries: TAtlasProjectEntries;
  Entry: TAtlasProjectEntry;
  Item: TAtlasTestProject;
  CiOn: Boolean;
begin
  Result := nil;
  if not FStarted or (FProjects = nil) then
    Exit;
  CiOn := TAtlasIdeSettings.Current.WelcomePageTestsCi;
  Entries := FProjects.Entries;
  for Entry in Entries do
  begin
    Item := Default(TAtlasTestProject);
    Item.Project := Entry.Project;
    Item.Summary := Entry.Summary;
    if not Entry.HasSummary then
      Item.Summary := TAtlasProjectSummary.Create(Entry.Project);
    Item.Job := TAtlasCiJob.Create('', '', '', False, '');
    // Ohne welcomePage.tests.ci weder .atlas lesen noch Netz.
    if CiOn then
      Item.Job := JobOf(Entry.Project, Item.Summary.Vcs.Branch);
    Item.Querying := FQuerying.ContainsKey(TAtlasProjectSummaries.NormalizedPath(Entry.Project));
    Result := Result + [Item];
  end;
end;

function TAtlasIdeTestResults.View: TAtlasTestResultsView;
var
  Settings: TAtlasPluginSettings;
begin
  Result := Default(TAtlasTestResultsView);
  Result.Selected := -1;
  if not FStarted or not Active then
    Exit;
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasWelcomeTestResults.View(Projects, FSelected, Settings.WelcomePageTestsMaxFailures,
    Settings.WelcomePageTestsCi);
end;

procedure TAtlasIdeTestResults.Shown;
begin
  Fetch(False, '', '');
end;

class procedure TAtlasIdeTestResults.Deliver(const AKeep: IAtlasTestResultsSource; AOwner: TAtlasIdeTestResults;
  const AFetch: TFetch; ASucceeded: Boolean; const ABuild: TAtlasCiBuild; AError: TAtlasCiFetchError);
begin
  TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if AKeep <> nil then
        AOwner.Fetched(AFetch, ASucceeded, ABuild, AError);
    end);
end;

procedure TAtlasIdeTestResults.Fetch(AForce: Boolean; const AOnly, AServer: string);
var
  Settings: TAtlasPluginSettings;
  Item: TAtlasTestProject;
  Batch: TArray<TFetch>;
  Next: TFetch;
  Index, Found: Integer;
  Stamp: TDateTime;
  Keep: IAtlasTestResultsSource;
  Providers: TAtlasCiProviderHook;
  Transports: TAtlasCiTransportHook;
  Name: string;
  Owner: TAtlasIdeTestResults;
begin
  Settings := TAtlasIdeSettings.Current;
  // welcomePage.tests.ci aus: kein Netzzugriff.
  if not FStarted or not Settings.WelcomePageTests or not Settings.WelcomePageTestsCi or
    not Assigned(FProviderFactory) or not Assigned(FTransportFactory) then
    Exit;
  // Eine Abfrage zur Zeit; die nächste kommt beim nächsten Anzeigen.
  ReleaseThread(False);
  if FThread <> nil then
    Exit;
  Stamp := NowUtc;
  Batch := nil;
  for Item in Projects do
  begin
    if not Item.Job.Configured or Item.Querying then
      Continue;
    if (AOnly <> '') and not SameText(Item.Project, AOnly) then
      Continue;
    if (AServer <> '') and (Item.Job.Server <> AServer) then
      Continue;
    if not AForce and not TAtlasWelcomeTestResults.Due(TAtlasWelcomeTestResults.CiFor(Item.Summary, Item.Job).Attempt,
      Stamp, Settings.WelcomePageTestsCiIntervalMinutes) then
      Continue;
    // Derselbe Job (Projektgruppe und ihr Testprojekt): einmal fragen, bei beiden eintragen.
    Found := -1;
    for Index := 0 to High(Batch) do
      if Batch[Index].Job.Key = Item.Job.Key then
        Found := Index;
    if Found >= 0 then
    begin
      Batch[Found].Projects := Batch[Found].Projects + [Item.Project];
      Continue;
    end;
    Next.Job := Item.Job;
    Next.Projects := [Item.Project];
    Batch := Batch + [Next];
  end;
  if Length(Batch) = 0 then
    Exit;
  for Next in Batch do
    for Name in Next.Projects do
      FQuerying.AddOrSetValue(TAtlasProjectSummaries.NormalizedPath(Name), True);
  Changed;
  // Keep hält die Quelle, bis die Ergebnisse im Hauptthread angekommen sind.
  Keep := Self;
  Owner := Self;
  Providers := FProviderFactory;
  Transports := FTransportFactory;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Job: TFetch;
      Provider: IAtlasCiProvider;
      Transport: IAtlasCiTransport;
      Build: TAtlasCiBuild;
      Error: TAtlasCiFetchError;
      Ok: Boolean;
    begin
      for Job in Batch do
      begin
        if TAtlasShutdown.Signalled then
          Exit;
        Build := TAtlasCiBuild.Empty;
        Ok := False;
        Error := TAtlasCiFetchError.UnknownProvider;
        try
          Provider := Providers(Job.Job.Provider);
          if Provider <> nil then
          begin
            // Liest den Zugang aus dem Anmeldespeicher von Windows (ohne Dialog).
            Transport := Transports(Job.Job);
            Ok := Provider.Fetch(Job.Job, Transport, TAtlasWelcomeTestResults.FetchTimeoutMs, Build, Error);
          end;
        except
          // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
          on E: Exception do
          begin
            Ok := False;
            Error := TAtlasCiFetchError.Network;
            TAtlasGuard.Log('Testergebnisse: Abfrage beim Build-Server mit ' + E.ClassName + ' abgebrochen');
          end;
        end;
        Provider := nil;
        Transport := nil;
        if TAtlasShutdown.Signalled then
          Exit;
        Deliver(Keep, Owner, Job, Ok, Build, Error);
      end;
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeTestResults.Fetched(const AFetch: TFetch; ASucceeded: Boolean; const ABuild: TAtlasCiBuild;
  AError: TAtlasCiFetchError);
var
  Project, Root: string;
  Stamp: TDateTime;
  Red: Boolean;
  Job: TAtlasCiJob;
  Build: TAtlasCiBuild;
begin
  for Project in AFetch.Projects do
    FQuerying.Remove(TAtlasProjectSummaries.NormalizedPath(Project));
  if not FStarted then
    Exit;
  Root := TAtlasIdeProjects.Folder;
  Stamp := NowUtc;
  Job := AFetch.Job;
  Build := ABuild;
  Red := False;
  for Project in AFetch.Projects do
    TAtlasProjectSummaries.Update(Root, Project,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        if ASucceeded and TAtlasWelcomeTestResults.TurnedRed(ASummary.Ci, Job, Build) then
          Red := True;
        ASummary.Ci := TAtlasWelcomeTestResults.Recorded(ASummary.Ci, Job, ASucceeded, Build, AError, Stamp);
      end);
  // Anonym: Anbieter, Ergebnis bzw. Fehlerart; nie Adresse, Job oder Zugang.
  if ASucceeded then
    TAtlasGuard.Log(Format('Testergebnisse: %s-Build %s, Tests %d/%d/%d',
      [AFetch.Job.Provider, TAtlasCiBuild.OutcomeKey(ABuild.Outcome), ABuild.Passed, ABuild.Failed, ABuild.Skipped]))
  else
    TAtlasGuard.Log(Format('Testergebnisse: %s nicht abgefragt (%s)',
      [AFetch.Job.Provider, TAtlasCiBuild.ErrorKey(AError)]));
  if Red and (Length(AFetch.Projects) > 0) then
    TurnedRed(AFetch.Projects[0], AFetch.Job, ABuild);
  Changed;
end;

procedure TAtlasIdeTestResults.TurnedRed(const AProject: string; const AJob: TAtlasCiJob;
  const ABuild: TAtlasCiBuild);
var
  Title, Text: string;
  Job: TAtlasCiJob;
  Number: Integer;
  Keep: IAtlasTestResultsSource;
  Mode: TAtlasNotificationMode;
begin
  if not TAtlasIdeSettings.Current.WelcomePageTestsCiNotify then
    Exit;
  Job := AJob;
  Number := ABuild.Number;
  Keep := Self;
  Title := TAtlasStrings.Fmt(TAtlasTextId.NotificationsBuildServerRed,
    [TAtlasWelcomeTestResults.ProviderCaption(AJob.Provider), ABuild.Number,
    ChangeFileExt(ExtractFileName(AProject), '')]);
  Text := TAtlasWelcomeTestResultsFrame.BuildText(ABuild);
  if AJob.JobBranch <> '' then
    Text := Text + ' · ' + AJob.JobBranch;
  Mode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.BuildServer,
    TAtlasNotificationSeverity.Error, Title, Text,
    [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBrowse),
    procedure
    begin
      if Keep <> nil then
        OpenBuildPage(Job, Number);
    end)]);
  // „Einblenden“ (oder Zentrale aus): auch eine Zeile in der Meldungsansicht.
  if Mode = TAtlasNotificationMode.Show then
    Report(Title + ' – ' + Text);
end;

class function TAtlasIdeTestResults.TestProjectOf(const ARow: TAtlasTestRow): string;
begin
  Result := ARow.TestProject;
  if Result = '' then
    Result := ARow.Project;
end;

class function TAtlasIdeTestResults.ProjectIsOpen(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

function TAtlasIdeTestResults.EnsureOpen(const AProject: string): Boolean;
var
  Actions: IOTAActionServices;
begin
  Result := False;
  if not FileExists(AProject) then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsMissing, [AProject]));
    Exit;
  end;
  // Schon offen: nicht neu laden.
  if ProjectIsOpen(AProject) then
    Exit(True);
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    Actions.OpenProject(AProject, True);
  Result := ProjectIsOpen(AProject);
end;

procedure TAtlasIdeTestResults.Select(const AProject: string);
begin
  FSelected := AProject;
  Changed;
end;

procedure TAtlasIdeTestResults.OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
var
  Row: TAtlasTestRow;
  Item: TAtlasTestFailureItem;
begin
  Row := ARow;
  Item := AFailure;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Target: TAtlasProjectLocation;
      FileName: string;
      Line: Integer;
    begin
      if FProjects = nil then
        Exit;
      Target := Default(TAtlasProjectLocation);
      if (Item.FileName <> '') and FileExists(Item.FileName) then
      begin
        Target.FileName := Item.FileName;
        Target.Line := Item.Line;
      end
      else
      begin
        // Fehlschlag vom Server: Projekt öffnen und den Test in seiner Testunit suchen.
        if not EnsureOpen(Row.Project) then
          Exit;
        if not Assigned(FOnLocateTest) or not FOnLocateTest(TestProjectOf(Row), Item.Test, FileName, Line) then
        begin
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsNotFound, [Item.Test]));
          Exit;
        end;
        Target.FileName := FileName;
        Target.Line := Line;
      end;
      FProjects.OpenAt(Row.Project, Target);
    end);
end;

procedure TAtlasIdeTestResults.RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
var
  Row: TAtlasTestRow;
  Tests: TArray<string>;
begin
  Row := ARow;
  Tests := ATests;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if (Length(Tests) = 0) or not Assigned(FOnRunTests) or not EnsureOpen(Row.Project) then
        Exit;
      // Genau diese Tests (--run), im Testprojekt des letzten Laufs.
      FOnRunTests(TestProjectOf(Row), Tests);
    end);
end;

procedure TAtlasIdeTestResults.Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
var
  Row: TAtlasTestRow;
  Item: TAtlasTestFailureItem;
begin
  Row := ARow;
  Item := AFailure;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Reason: string;
    begin
      if not Assigned(FOnDebugTest) or not EnsureOpen(Row.Project) then
        Exit;
      if not FOnDebugTest(TestProjectOf(Row), Item.Test, Reason) and (Reason <> '') then
        Report(Reason);
    end);
end;

procedure TAtlasIdeTestResults.OpenBuildPage(const AJob: TAtlasCiJob; ANumber: Integer);
var
  Provider: IAtlasCiProvider;
  Url: string;
begin
  if not Assigned(FProviderFactory) then
    Exit;
  Provider := FProviderFactory(AJob.Provider);
  if Provider = nil then
    Exit;
  Url := Provider.BuildPage(AJob, ANumber);
  // Nur Web-Adressen aus der eingetragenen Adresse, nie etwas aus der Antwort des Servers.
  if Url.StartsWith('https://', True) or Url.StartsWith('http://', True) then
    ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
end;

procedure TAtlasIdeTestResults.Browse(const ARow: TAtlasTestRow);
var
  Row: TAtlasTestRow;
begin
  Row := ARow;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Row.HasCi and Row.Ci.HasBuild then
        OpenBuildPage(Row.Job, Row.Ci.Build.Number);
    end);
end;

procedure TAtlasIdeTestResults.QueryNow(const ARow: TAtlasTestRow);
var
  Row: TAtlasTestRow;
begin
  Row := ARow;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Fetch(True, Row.Project, '');
    end);
end;

function TAtlasIdeTestResults.CanEnterCredentials: Boolean;
begin
  Result := FStarted and TAtlasIdeSettings.Current.CiLogin and Assigned(FOnCredentials);
end;

procedure TAtlasIdeTestResults.EnterCredentials(const AJob: TAtlasCiJob);
var
  Job: TAtlasCiJob;
begin
  Job := AJob;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not CanEnterCredentials then
        Exit;
      if Job.Server = '' then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.CiLoginNoServer));
        Exit;
      end;
      if not FOnCredentials(Job) then
        Exit;
      // Mit dem neuen Zugang gleich alle Jobs dieses Servers fragen (nur mit welcomePage.tests.ci).
      Fetch(True, '', Job.Server);
    end);
end;

procedure TAtlasIdeTestResults.Credentials(const ARow: TAtlasTestRow);
begin
  EnterCredentials(ARow.Job);
end;

procedure TAtlasIdeTestResults.EnterCredentialsForActive;
var
  Project: string;
  Team: TAtlasTeamSettings;
  Provider: string;
begin
  Project := TAtlasIdeTeamFile.ActiveProject;
  if Project = '' then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.CiLoginNoServer));
    Exit;
  end;
  Team := TAtlasIdeTeamFile.ForProject(Project);
  Provider := Team.Ci.Provider;
  if Provider = '' then
    Provider := TAtlasIdeSettings.Current.WelcomePageTestsCiProvider;
  EnterCredentials(TAtlasCiJob.Create(Provider, Team.Ci.Url, Team.Ci.Job, Team.Ci.Multibranch, ''));
end;

procedure TAtlasIdeTestResults.OpenProject(const ARow: TAtlasTestRow);
var
  Row: TAtlasTestRow;
begin
  Row := ARow;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FProjects <> nil then
        FProjects.Open(Row.Project);
    end);
end;

end.
