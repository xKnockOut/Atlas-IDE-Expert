unit Atlas.IDE.Tracker.IssuesQuery;

// Abfrage von „Meine Issues“ beim Issue-Tracker (aus
// Atlas.IDE.Tracker.MyIssues gelöst, #1455): nur mit welcomePage.issues, beim
// Anzeigen, höchstens alle 10 Minuten, im Hintergrund mit 5 s; eine Abfrage
// zur Zeit. Ohne Token kein Netzzugriff. Dazu die Schaltflächen der Kachel,
// die neu abfragen: „Jetzt abfragen“, „Zugang hinterlegen“, Wahl der Abfrage
// (#1262), „Abfragen bearbeiten …“ und „zuordnen …“ (#1261).
// Bei „Alle Tracker-Projekte“ (#1928) kommen die Projekte nacheinander dran:
// je Fetch das erste fällige; „Jetzt abfragen“ fragt jedes einmal.
// Protokoll anonym: Anbieter, Anzahl bzw. Fehlerart.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices,
  Atlas.IDE.Tracker.IssuesStatus;

type
  /// <summary>Eine Abfrage: was gefragt wird und (nach Execute im Hintergrund) die Antwort.</summary>
  TAtlasIssuesFetchJob = record
    Project: string;
    QueryName: string;
    Target: TAtlasTrackerTarget;
    Provider: IAtlasTrackerProvider;
    Transports: TAtlasTrackerTransportHook;
    Succeeded: Boolean;
    Issues: TArray<TAtlasTrackerIssue>;
    Error: TAtlasCiFetchError;
    /// <summary>Im Hintergrund: Token lesen und abfragen; Fehler werden zu Netzfehlern, kein Dialog.</summary>
    procedure Execute;
  end;

  TAtlasIdeIssuesQuery = class
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    FStatus: TAtlasIdeIssuesStatus;
    FThread: TThread;
    // Bei „Alle“ nach „Jetzt abfragen“ noch zu fragen (#1928).
    FForced: TArray<string>;
    /// <summary>Nächstes Projekt: zuerst die noch zu fragenden, sonst das erste fällige; False ohne.</summary>
    function NextProject(AForce: Boolean; out AProject: string; out AForced: Boolean): Boolean;
    function Prepare(AForce: Boolean; out AJob: TAtlasIssuesFetchJob): Boolean;
    procedure Fetched(const AJob: TAtlasIssuesFetchJob);
    /// <summary>Fetch(False) über die Nachrichtenschleife, z. B. nach einer Abfrage.</summary>
    procedure QueueFetch;
    class procedure Deliver(const AKeep: IAtlasIdeIssuesActions; AOwner: TAtlasIdeIssuesQuery;
      const AJob: TAtlasIssuesFetchJob); static;
  public
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices;
      AStatus: TAtlasIdeIssuesStatus);
    destructor Destroy; override;
    /// <summary>Abfragen, wenn fällig (AForce: sofort).</summary>
    procedure Fetch(AForce: Boolean);
    /// <summary>Beendeten Abfrage-Thread freigeben; AWait: kurz warten, dann sich selbst überlassen.</summary>
    procedure Release(AWait: Boolean);
    /// <summary>„Jetzt abfragen“: Liste und Sprint-Kachel sofort.</summary>
    procedure QueryNow;
    /// <summary>„Zugang hinterlegen“ für den Tracker des Bereichs, danach gleich fragen.</summary>
    procedure Credentials;
    /// <summary>Befehl Atlas.TrackerLogin: Zugang für den Tracker des aktiven Projekts.</summary>
    procedure EnterCredentialsForActive;
    /// <summary>Abfrage AName für das Projekt merken (#1262) und gleich fragen.</summary>
    procedure SelectQuery(const AName: string);
    procedure EditQueries;
    procedure AssignProject;
  end;

implementation

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Projects,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Files;

const
  cLogAborted = 'Meine Issues: Abfrage beim Tracker mit %s abgebrochen';
  cLogFetched = 'Meine Issues: %s, %d Issues';
  cLogNotFetched = 'Meine Issues: %s nicht abgefragt (%s)';

{ TAtlasIssuesFetchJob }

procedure TAtlasIssuesFetchJob.Execute;
var
  mTransport: IAtlasCiTransport;
begin
  Issues := nil;
  Succeeded := False;
  Error := TAtlasCiFetchError.Unauthorized;
  try
    // Liest das Token aus dem Anmeldespeicher von Windows (ohne Dialog); ohne Token kein Netz.
    mTransport := nil;
    if Assigned(Transports) then
    begin
      mTransport := Transports(Provider, Target);
    end;
    if mTransport <> nil then
    begin
      Succeeded := Provider.Fetch(Target, mTransport, TAtlasMyIssues.cFetchTimeoutMs, TAtlasMyIssues.cMaxItems,
        Issues, Error);
    end
    else
    begin
      Error := TAtlasCiFetchError.NoCredentials;
    end;
  except
    // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
    on E: Exception do
    begin
      Succeeded := False;
      Error := TAtlasCiFetchError.Network;
      TAtlasGuard.Log(Format(cLogAborted, [E.ClassName], TFormatSettings.Invariant));
    end;
  end;
  mTransport := nil;
end;

{ TAtlasIdeIssuesQuery }

constructor TAtlasIdeIssuesQuery.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices;
  AStatus: TAtlasIdeIssuesStatus);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
  FStatus := AStatus;
end;

destructor TAtlasIdeIssuesQuery.Destroy;
begin
  Release(True);
  inherited;
end;

procedure TAtlasIdeIssuesQuery.Release(AWait: Boolean);
begin
  if FThread = nil then
  begin
    Exit;
  end;
  if AWait and not FThread.Finished then
  begin
    TAtlasShutdown.WaitForThreads([FThread]);
  end;
  if FThread.Finished then
  begin
    FreeAndNil(FThread);
  end
  else if AWait then
  begin
    FThread.FreeOnTerminate := True;
    FThread := nil;
  end;
end;

function TAtlasIdeIssuesQuery.NextProject(AForce: Boolean; out AProject: string; out AForced: Boolean): Boolean;
var
  mProjects: TArray<string>;
  mProject: string;
begin
  mProjects := FContext.Projects;
  if AForce then
  begin
    FForced := Copy(mProjects);
  end;
  AForced := Length(FForced) > 0;
  if AForced then
  begin
    AProject := FForced[0];
    Delete(FForced, 0, 1);
    Exit(True);
  end;
  for mProject in mProjects do
  begin
    if TAtlasMyIssues.Due(FContext.StateOf(mProject), FContext.CachedTargetOf(mProject).Target,
      TAtlasIdeIssuesTargets.NowUtc, False) then
    begin
      AProject := mProject;
      Exit(True);
    end;
  end;
  AProject := '';
  Result := False;
end;

function TAtlasIdeIssuesQuery.Prepare(AForce: Boolean; out AJob: TAtlasIssuesFetchJob): Boolean;
var
  mCached: TAtlasIssuesCachedTarget;
  mForced: Boolean;
begin
  AJob := Default(TAtlasIssuesFetchJob);
  // welcomePage.issues aus: kein Netzzugriff. Eine Abfrage zur Zeit; die nächste kommt beim nächsten Anzeigen.
  Release(False);
  AJob.Transports := FContext.Hooks.Transport;
  Result := FContext.Started and TAtlasIdeIssuesTargets.Active and Assigned(AJob.Transports) and (FThread = nil);
  if not Result then
  begin
    Exit;
  end;
  Result := NextProject(AForce, AJob.Project, mForced);
  if not Result then
  begin
    Exit;
  end;
  mCached := FContext.CachedTargetOf(AJob.Project);
  AJob.Target := mCached.Target;
  if mCached.QueryIndex >= 0 then
  begin
    AJob.QueryName := mCached.Queries[mCached.QueryIndex].Name;
  end;
  Result := TAtlasMyIssues.Due(FContext.StateOf(AJob.Project), AJob.Target, TAtlasIdeIssuesTargets.NowUtc,
    mForced);
  if Result then
  begin
    AJob.Provider := FContext.ProviderOf(AJob.Target.Provider);
    Result := AJob.Provider <> nil;
  end;
end;

class procedure TAtlasIdeIssuesQuery.Deliver(const AKeep: IAtlasIdeIssuesActions; AOwner: TAtlasIdeIssuesQuery;
  const AJob: TAtlasIssuesFetchJob);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Tracker,
    procedure
    begin
      if AKeep <> nil then
      begin
        AOwner.Fetched(AJob);
      end;
    end);
end;

procedure TAtlasIdeIssuesQuery.Fetch(AForce: Boolean);
var
  mJob: TAtlasIssuesFetchJob;
  mKeep: IAtlasIdeIssuesActions;
  mOwner: TAtlasIdeIssuesQuery;
begin
  if not Prepare(AForce, mJob) then
  begin
    Exit;
  end;
  FContext.QueryProject := mJob.Project;
  mKeep := FContext.Actions;
  mOwner := Self;
  FThread := TThread.CreateAnonymousThread(
    procedure
    begin
      mJob.Execute;
      if not TAtlasShutdown.Signalled then
      begin
        Deliver(mKeep, mOwner, mJob);
      end;
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
  FContext.Changed;
end;

procedure TAtlasIdeIssuesQuery.Fetched(const AJob: TAtlasIssuesFetchJob);
var
  mState: TAtlasIssuesState;
begin
  FContext.QueryProject := '';
  Release(False);
  if not FContext.Started then
  begin
    Exit;
  end;
  mState := FContext.StateOf(AJob.Project);
  TAtlasMyIssues.Recorded(mState, AJob.Target, TAtlasIdeIssuesTargets.NowUtc, AJob.Succeeded, AJob.Issues,
    AJob.Error);
  // Trefferzahl für die Klappliste (#1262). Anonym: Anbieter, Anzahl bzw. Fehlerart; nie Adresse, Projekt,
  // Kennungen oder Titel.
  if AJob.Succeeded then
  begin
    mState.SetCount(AJob.QueryName, Length(AJob.Issues));
    TAtlasGuard.Log(Format(cLogFetched, [AJob.Target.Provider, Length(AJob.Issues)], TFormatSettings.Invariant));
  end
  else
  begin
    TAtlasGuard.Log(Format(cLogNotFetched, [AJob.Target.Provider, TAtlasCiBuild.ErrorKey(AJob.Error)],
      TFormatSettings.Invariant));
  end;
  FContext.SaveState(AJob.Project, mState);
  FStatus.Update;
  FContext.Changed;
  // Während der Abfrage eine andere Abfrage gewählt (#1262): danach deren Liste holen; sonst ist nichts fällig.
  QueueFetch;
end;

procedure TAtlasIdeIssuesQuery.QueueFetch;
var
  mKeep: IAtlasIdeIssuesActions;
  mOwner: TAtlasIdeIssuesQuery;
begin
  // Erst nach dem Ende des Abfrage-Threads (Fetch fragt nur, wenn keiner mehr läuft).
  mKeep := FContext.Actions;
  mOwner := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Tracker,
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Fetch(False);
      end;
    end);
  // Sprint-Kachel lädt mit „Meine Issues“ (#1277), wenn fällig.
  if FServices.Sprint <> nil then
  begin
    FServices.Sprint.IssuesFetched(False);
  end;
end;

procedure TAtlasIdeIssuesQuery.QueryNow;
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    begin
      Fetch(True);
      if FServices.Sprint <> nil then
      begin
        FServices.Sprint.IssuesFetched(True);
      end;
    end);
end;

procedure TAtlasIdeIssuesQuery.Credentials;
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
    begin
      if not FContext.CanEnterCredentials then
      begin
        Exit;
      end;
      mTarget := FContext.TargetOf(FContext.CurrentProject);
      mProvider := FContext.ProviderOf(mTarget.Provider);
      if (mProvider = nil) or (mTarget.Server = '') then
      begin
        FContext.Report(TAtlasStrings.Text(TAtlasTextId.TrackerLoginNoTracker));
      end
      else if FContext.Hooks.Credentials(mProvider, mTarget) then
      begin
        // Mit dem neuen Zugang gleich fragen (nur mit welcomePage.issues).
        Fetch(True);
      end;
    end);
end;

procedure TAtlasIdeIssuesQuery.EnterCredentialsForActive;
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
    begin
      if not FContext.CanEnterCredentials then
      begin
        Exit;
      end;
      mProvider := FContext.ActiveTarget(mTarget);
      if mProvider = nil then
      begin
        FContext.Report(TAtlasStrings.Text(TAtlasTextId.TrackerLoginNoTracker));
      end
      else if FContext.Hooks.Credentials(mProvider, mTarget) then
      begin
        Fetch(True);
      end;
    end);
end;

procedure TAtlasIdeIssuesQuery.SelectQuery(const AName: string);
var
  mProject: string;
  mState: TAtlasIssuesState;
  mChanged: Boolean;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  // Bei „Alle“ (#1928) für jedes Tracker-Projekt, sonst nur für das gezeigte.
  mChanged := False;
  for mProject in FContext.Projects do
  begin
    mState := FContext.StateOf(mProject);
    if SameText(mState.Selected, AName) then
    begin
      Continue;
    end;
    // Je Projekt gemerkt; das neue Ziel (andere Abfrage) ist sofort fällig, unabhängig von DueMinutes.
    mState.Selected := AName;
    FContext.SaveState(mProject, mState);
    FContext.ForgetTarget(mProject);
    mChanged := True;
  end;
  if mChanged then
  begin
    FContext.Changed;
    Fetch(False);
  end;
end;

procedure TAtlasIdeIssuesQuery.EditQueries;
var
  mEdit: TProc;
begin
  mEdit := FContext.Hooks.EditQueries;
  if FContext.Started and Assigned(mEdit) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Tracker,
      procedure
      begin
        mEdit();
        // Nach dem Dialog gelten die neuen Abfragen sofort.
        FContext.ForgetTargets;
        FContext.Changed;
        Fetch(False);
      end);
  end;
end;

procedure TAtlasIdeIssuesQuery.AssignProject;
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mProject: string;
      mAssign: TProc<string>;
    begin
      mProject := FContext.CurrentProject;
      mAssign := FContext.Hooks.AssignProject;
      if not FContext.CanAssign or (mProject = '') or not Assigned(mAssign) then
      begin
        Exit;
      end;
      // Die geöffnete .groupproj, wenn das Projekt darin ist, sonst die .dproj (wie „Aktuelles Projekt hinzufügen“).
      mAssign(TAtlasTrackerProjects.CurrentMatch(mProject, TAtlasIdeFiles.GroupOfProject(mProject)));
      // Nach dem Dialog gilt die neue Zuordnung sofort.
      FContext.ForgetTargets;
      FContext.Changed;
      Fetch(False);
    end);
end;

end.
