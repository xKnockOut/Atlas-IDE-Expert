unit Atlas.IDE.Welcome.Issues;

// Bereich „Meine Issues“ in der IDE (#765): Quelle des Bereichs
// (IAtlasIssuesSource), Anmeldung als Bereich atlas.issues der
// Willkommensseite (bzw. des Fensters „Atlas-Start“), Abfrage beim
// Issue-Tracker im Hintergrund, „Beginnen“, das aktuelle Issue im
// Statusfeld (#591) und das Commit-Präfix.
// - Projekt: das in „Projekte“ gewählte, sonst das aktive der IDE, sonst das
//   oberste der Liste. Tracker (Anbieter, Adresse, Projekt) aus dessen .atlas
//   (#486, Abschnitt tracker); issues.tracker ersetzt den
//   Anbieter, issues.query die Abfrage.
// - Abfrage nur mit welcomePage.issues (Vorgabe aus; sonst kein Netz), beim
//   Anzeigen, höchstens alle 10 Minuten (gemerkt im Abschnitt "issues" der
//   Projekt-Zusammenfassung), im Hintergrund mit 5 s. Ohne Token im
//   Anmeldespeicher kein Netzzugriff („Zugang hinterlegen“). Ohne Netz bleibt
//   der letzte Stand mit „Stand vom …“; kein Dialog.
// - „Beginnen“: Git legt den Branch nach Muster von der Basis an (main, sonst
//   master) und checkt ihn aus, SVN kopiert ^/trunk nach ^/branches/<Name> und
//   wechselt mit svn switch; ein vorhandener Branch wird nur ausgecheckt. Bei
//   lokalen Änderungen fragt Atlas vorher. start=remember merkt nur die
//   Kennung. Danach öffnet Atlas das Projekt.
// - Commit-Präfix (issues.commitPattern), solange ein Issue
//   aktuell ist: im Commit-Dialog der IDE (das Nachrichtenfeld wird einmal je
//   Dialog vorne ergänzt) und, nach einmaliger Zustimmung je Projekt, über den
//   Git-Hook prepare-commit-msg (Atlas.Core.Tracker.CommitHook).
// - Statusfeld: Zeile atlas.issue „Issue: ATL-123 Titel“; Klick beendet das
//   Issue nach Rückfrage.
// - Tracker nachführen (#1266, issues.syncState, TAtlasIdeTrackerSync): nach
//   „Beginnen“ Zustand, Zuweisung und Kommentar; „Beenden“ (Statusfeld,
//   Kontextmenü, Knopf der Vorschau) zeigt statt der Rückfrage den Dialog
//   „ATL-123 beenden“, beendet wird nach „Senden“; Kommentare aus der Vorschau.
// - Zeiterfassung (#1267, issues.timeTracking, TAtlasIdeTrackerTime): die Uhr
//   folgt dem aktuellen Issue (UpdateStatus); nach „Beenden“ und beim Wechsel
//   auf ein anderes Issue der Dialog „… buchen?“; {time} im Beenden-Dialog;
//   Befehl Atlas.IssueTimeOpen (ShowTimeOpen). Das Zusatzfeld im Statusfeld
//   setzt die Komposition (OnTimeStatus).
// - Issue-Links "#312" in Begründungen (#1123): Adresse aus dem Tracker des
//   aktuellen Projekts (IssueUrl), angemeldet bei TAtlasDocIssueLinks von Start
//   bis Stop; ohne Tracker sind die Links nicht anklickbar.
// - Issue-Vorschau (#1264, issues.preview): Klick auf Zeile oder Kennung zeigt
//   das Issue im Fenster „Atlas-Issue“ (TAtlasIdeIssuePreview, Zwischenspeicher
//   %LOCALAPPDATA%\Atlas\issues), Strg+Klick öffnet den Browser; Befehl
//   Atlas.IssueShow fragt nach einer Kennung (ShowPreviewPrompt).
// - Protokoll anonym: nur Anbieter, Anzahl, Ergebnis und Fehlerart, nie
//   Adresse, Projekt, Kennung, Titel oder Token.
// Anbieter, Transport (mit Token aus dem Anmeldespeicher) und Zugangsdialog
// kommen über Hooks aus der Komposition.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Welcome.Issues,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Issues,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.TimeTracking,
  Atlas.IDE.Tracker.Workflow,
  Atlas.IDE.Welcome.Projects;

type
  /// <summary>Tracker-Anbieter zum Namen ("github", "youtrack"); nil, wenn es ihn nicht gibt.</summary>
  TAtlasTrackerProviderHook = reference to function(const AName: string): IAtlasTrackerProvider;
  /// <summary>Transport für ATarget mit dem Token aus dem Anmeldespeicher; nil ohne Token. Läuft im
  /// Hintergrund-Thread.</summary>
  TAtlasTrackerTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  /// <summary>Zugang für ATarget abfragen und speichern (Dialog); True, wenn sich etwas geändert hat.</summary>
  TAtlasTrackerCredentialsHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): Boolean;

  TAtlasIdeIssues = class(TInterfacedObject, IAtlasIssuesSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: nach „Testergebnisse“ (Mockup: rechte Spalte, im
    /// Atlas-Layout ohne festen Platz).</summary>
    Order = 26;
    /// <summary>So lange gilt der gelesene Tracker aus .atlas, bevor er neu gelesen wird.</summary>
    TargetCacheMs = 5000;
    /// <summary>Takt für Commit-Dialog und Statuszeile.</summary>
    WatchMs = 700;
    /// <summary>Alle so viele Takte die Statuszeile neu (Projekt- oder Branch-Wechsel).</summary>
    StatusTicks = 7;
    /// <summary>Zeitlimit je Aufruf der Versionsverwaltung bei „Beginnen“.</summary>
    VcsTimeoutMs = 30000;
  private type
    TCachedTarget = record
      Target: TAtlasTrackerTarget;
      Tick: UInt64;
    end;
  private
    FProjects: TAtlasIdeProjects;
    FProjectsRef: IInterface;
    FMessage: TProc<string>;
    FStarted: Boolean;
    FTitle: string;
    FActive: Boolean;
    FThread: TThread;
    FQueryProject: string;
    FStartProject: string;
    FNotice: string;
    FNoticeProject: string;
    FNoticeFailed: Boolean;
    // Normierter Pfad → Abschnitt "issues" (nicht bei jedem Zeichnen die Datei lesen).
    FStates: TDictionary<string, TAtlasIssuesState>;
    FTargets: TDictionary<string, TCachedTarget>;
    FProviderFactory: TAtlasTrackerProviderHook;
    FTransportFactory: TAtlasTrackerTransportHook;
    FOnCredentials: TAtlasTrackerCredentialsHook;
    FOnSettings: TProc;
    FPreview: TAtlasIdeIssuePreview;
    FPreviewRef: IInterface;
    FSync: TAtlasIdeTrackerSync;
    FTime: TAtlasIdeTrackerTime;
    FTimeRef: IInterface;
    FOnTimeStatus: TAtlasIdeTimeStatus;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FWatch: TTimer;
    FTicks: Integer;
    FPrefix: string;
    // Nachrichtenfelder von Commit-Dialogen, die schon ergänzt wurden.
    FFilled: TList<THandle>;
    // Git-Ordner, in die diese Sitzung ein Präfix für den Hook geschrieben hat (Abschalten löscht es dort).
    FPrefixDirs: TList<string>;
    procedure Changed;
    procedure Report(const AText: string);
    procedure ReleaseThread(AWait: Boolean);
    function CurrentProject: string;
    function ProjectName(const AProject: string): string;
    function TargetOf(const AProject: string): TAtlasTrackerTarget;
    function ProviderOf(const AName: string): IAtlasTrackerProvider;
    function StateOf(const AProject: string): TAtlasIssuesState;
    procedure SaveState(const AProject: string; const AState: TAtlasIssuesState);
    function BranchOf(const AProject: string): string;
    function Options: TAtlasIssuesOptions;
    function ViewOf(const AProject: string): TAtlasIssuesView;
    procedure Fetch(AForce: Boolean);
    procedure Fetched(const AProject: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
    class procedure Deliver(const AKeep: IAtlasIssuesSource; AOwner: TAtlasIdeIssues; const AProject: string;
      const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean; const AIssues: TArray<TAtlasTrackerIssue>;
      AError: TAtlasCiFetchError); static;
    procedure Prepared(const AProject: string; const AIssue: TAtlasTrackerIssue; const APlan: TAtlasIssueStartPlan;
      AChanges: Integer);
    procedure Finished(const AProject: string; const AIssue: TAtlasTrackerIssue; const APlan: TAtlasIssueStartPlan;
      const AResult: TAtlasIssueStartResult);
    procedure SetNotice(const AProject, AText: string; AFailed: Boolean);
    procedure AskHook(const AProject: string; var AState: TAtlasIssuesState; const AHooks: string);
    procedure SyncPrefix(const AProject: string);
    procedure ClearPrefixes;
    procedure UpdateStatus;
    procedure RemoveStatus;
    procedure WatchTick(Sender: TObject);
    procedure FillCommitDialog;
    procedure RegisterSection;
    procedure RegisterIssueLinks;
    procedure StartPreview;
    procedure StartSync;
    procedure StartTime;
    /// <summary>Die Uhr der Zeiterfassung auf das aktuelle Issue von AProject stellen ('' = keins).</summary>
    procedure SyncTime(const AProject, AKey: string);
    function TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
    /// <summary>Kennung des aktuellen Issues im Projekt des Bereichs; '' ohne.</summary>
    function ActiveKey: string;
    /// <summary>„Beenden“ ohne Tracker: Zustand, Statuszeile und Hinweis.</summary>
    procedure EndedLocally(const AProject, ABranch, AKey: string);
    /// <summary>„Beenden“ mit Dialog (#1266); beendet erst nach „Senden“.</summary>
    procedure EndWithTracker(const AProject, ABranch, AKey: string; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget; const AState: TAtlasIssuesState);
    function ActiveTarget(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    class function NowUtc: TDateTime; static;
  public
    /// <summary>AProjects: Bereich „Projekte“ (Liste, Auswahl, Öffnen, Stand der Versionsverwaltung). AMessage:
    /// Zeile in die Meldungsansicht.</summary>
    constructor Create(AProjects: TAtlasIdeProjects; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik, Statuszeile und Takt anmelden.</summary>
    procedure Start; overload;
    /// <summary>Alles abmelden und kurz auf die Abfrage warten (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen oder anderem Projekt: Sichtbarkeit, Titel und Inhalt neu.</summary>
    procedure Refresh;
    function Section: TAtlasWelcomeSection;
    /// <summary>welcomePage.issues an?</summary>
    class function Active: Boolean; static;
    /// <summary>Befehl Atlas.TrackerLogin: Zugang für den Tracker aus der .atlas des aktiven Projekts.</summary>
    procedure EnterCredentialsForActive;
    /// <summary>Adresse des Issues AKey im Tracker des aktuellen Projekts (#1123); '' ohne Tracker. Ohne Netz.
    /// </summary>
    function IssueUrl(const AKey: string): string;
    /// <summary>Befehl Atlas.IssueShow (#1264): Kennung abfragen und das Issue aus dem Tracker des aktiven
    /// Projekts in „Atlas-Issue“ zeigen.</summary>
    procedure ShowPreviewPrompt;
    /// <summary>Vorschau-Steuerung (nil vor Start bzw. nach Stop).</summary>
    property IssuePreview: TAtlasIdeIssuePreview read FPreview;
    /// <summary>Tracker nachführen (#1266; nil vor Start bzw. nach Stop).</summary>
    property TrackerSync: TAtlasIdeTrackerSync read FSync;
    /// <summary>Zeiterfassung (#1267; nil vor Start bzw. nach Stop).</summary>
    property TimeTracking: TAtlasIdeTrackerTime read FTime;
    /// <summary>Befehl Atlas.IssueTimeOpen (#1267): offene Zeitbuchungen zeigen.</summary>
    procedure ShowTimeOpen;
    /// <summary>Zusatzfeld der Zeiterfassung im Statusfeld (#1267); vor Start setzen.</summary>
    property OnTimeStatus: TAtlasIdeTimeStatus read FOnTimeStatus write FOnTimeStatus;
    property ProviderFactory: TAtlasTrackerProviderHook read FProviderFactory write FProviderFactory;
    property TransportFactory: TAtlasTrackerTransportHook read FTransportFactory write FTransportFactory;
    property OnCredentials: TAtlasTrackerCredentialsHook read FOnCredentials write FOnCredentials;
    /// <summary>Tools › Optionen › Atlas › Issue-Tracker (Knopf „Tracker-Einstellungen“ der Vorschau).</summary>
    property OnSettings: TProc read FOnSettings write FOnSettings;
    { IAtlasIssuesSource }
    function View: TAtlasIssuesView;
    procedure Shown;
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart); overload;
    procedure Browse(const AIssue: TAtlasTrackerIssue);
    procedure Preview(const AIssue: TAtlasTrackerIssue);
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    procedure QueryNow;
    procedure Credentials;
    function CanEnterCredentials: Boolean;
    procedure EndActive;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.UITypes,
  System.StrUtils,
  System.DateUtils,
  System.IOUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.CommitHook,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Tracker.Preview,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Vcs.Service;

type
  // Zugriff auf ReadOnly (geschützt in TCustomEdit) für das Nachrichtenfeld des Commit-Dialogs.
  TEditAccess = class(TCustomEdit);

{ TAtlasIdeIssues }

constructor TAtlasIdeIssues.Create(AProjects: TAtlasIdeProjects; const AMessage: TProc<string>);
begin
  inherited Create;
  FProjects := AProjects;
  FProjectsRef := AProjects;
  FMessage := AMessage;
  FStates := TDictionary<string, TAtlasIssuesState>.Create;
  FTargets := TDictionary<string, TCachedTarget>.Create;
  FFilled := TList<THandle>.Create;
  FPrefixDirs := TList<string>.Create;
end;

destructor TAtlasIdeIssues.Destroy;
begin
  Stop;
  ReleaseThread(True);
  FFilled.Free;
  FPrefixDirs.Free;
  FTargets.Free;
  FStates.Free;
  inherited;
end;

class function TAtlasIdeIssues.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageIssues;
end;

class function TAtlasIdeIssues.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

procedure TAtlasIdeIssues.Start;
var
  Keep: IAtlasIssuesSource;
begin
  FStarted := True;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Issues,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeIssuesFrame;
    begin
      Frame := TAtlasWelcomeIssuesFrame.Create(AOwner);
      Frame.Source := Keep;
      Result := Frame;
    end);
  FWatch := TTimer.Create(nil);
  FWatch.Interval := WatchMs;
  FWatch.OnTimer := WatchTick;
  FTitle := '';
  RegisterIssueLinks;
  StartSync;
  StartTime;
  StartPreview;
  Refresh;
end;

procedure TAtlasIdeIssues.StartSync;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
begin
  mKeep := Self;
  mOwner := Self;
  // Stop löst den Ring (Sync hält über die Hooks diese Quelle).
  FSync := TAtlasIdeTrackerSync.Create(
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
        Result := mFactory(AProvider, ATarget);
    end,
    procedure(AText: string)
    begin
      if mKeep <> nil then
        mOwner.Report(AText);
    end);
end;

procedure TAtlasIdeIssues.StartTime;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mStatus: TAtlasIdeTimeStatus;
begin
  mKeep := Self;
  mOwner := Self;
  // Stop löst den Ring (die Zeiterfassung hält über die Hooks diese Quelle).
  FTime := TAtlasIdeTrackerTime.Create(FSync,
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := nil;
      if mKeep <> nil then
        Result := mOwner.ProviderOf(AName);
    end,
    procedure(AText: string)
    begin
      if mKeep <> nil then
        mOwner.Report(AText);
    end,
    TAtlasTimeFile.DefaultPath);
  FTimeRef := FTime;
  mStatus := FOnTimeStatus;
  FTime.OnStatus := mStatus;
  FSync.TimeText :=
    function(const AKey: string): string
    begin
      Result := '';
      if (mKeep <> nil) and (mOwner.FTime <> nil) then
        Result := mOwner.FTime.TimeText(AKey);
    end;
  FTime.Start;
end;

function TAtlasIdeIssues.TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
var
  mTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTimeIssue.None;
  if (AProject = '') or (AKey = '') then
    Exit;
  mTarget := TargetOf(AProject);
  Result := TAtlasTimeIssue.Create(mTarget.Provider, mTarget.Url, mTarget.Project, AKey);
end;

procedure TAtlasIdeIssues.SyncTime(const AProject, AKey: string);
begin
  if FTime <> nil then
    FTime.SetIssue(TimeIssueOf(AProject, AKey));
end;

procedure TAtlasIdeIssues.ShowTimeOpen;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FStarted and (FTime <> nil) and TAtlasIdeTrackerTime.Active then
        FTime.ShowOpen;
    end);
end;

procedure TAtlasIdeIssues.StartPreview;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mHooks: TAtlasIssuePreviewHooks;
begin
  mKeep := Self;
  mOwner := Self;
  mHooks := Default(TAtlasIssuePreviewHooks);
  mHooks.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := nil;
      if mKeep <> nil then
        Result := mOwner.ProviderOf(AName);
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
        Result := mFactory(AProvider, ATarget);
    end;
  mHooks.Credentials :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean
    begin
      Result := (mKeep <> nil) and mOwner.CanEnterCredentials and mOwner.FOnCredentials(AProvider, ATarget);
    end;
  mHooks.Start :=
    procedure(AIssue: TAtlasTrackerIssue)
    begin
      if mKeep <> nil then
        mOwner.Start(AIssue, mOwner.Options.Start);
    end;
  mHooks.CanStart :=
    function: Boolean
    begin
      Result := (mKeep <> nil) and mOwner.FStarted and Active and (mOwner.FStartProject = '') and
        (mOwner.CurrentProject <> '');
    end;
  mHooks.Settings :=
    procedure
    begin
      if (mKeep <> nil) and Assigned(mOwner.FOnSettings) then
        mOwner.FOnSettings();
    end;
  mHooks.CanWrite :=
    function(ATarget: TAtlasTrackerTarget): Boolean
    begin
      Result := (mKeep <> nil) and (mOwner.FSync <> nil) and
        mOwner.FSync.Enabled(mOwner.ProviderOf(ATarget.Provider), ATarget);
    end;
  mHooks.IsActive :=
    function(AKey: string): Boolean
    begin
      Result := (mKeep <> nil) and (AKey <> '') and SameText(mOwner.ActiveKey, AKey);
    end;
  mHooks.EndIssue :=
    procedure(AKey: string)
    begin
      if (mKeep <> nil) and SameText(mOwner.ActiveKey, AKey) then
        mOwner.EndActive;
    end;
  mHooks.Comment :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey, AText: string; const ADone: TAtlasTrackerSendDone)
    begin
      if (mKeep = nil) or (mOwner.FSync = nil) then
        ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''))
      else
        mOwner.FSync.SendComment(mOwner.ProviderOf(ATarget.Provider), ATarget, AKey, AText, ADone);
    end;
  FPreview := TAtlasIdeIssuePreview.Create(mHooks,
    TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'issues'));
  FPreviewRef := FPreview;
  FPreview.Start;
end;

procedure TAtlasIdeIssues.RegisterIssueLinks;
begin
  // Eigene Routine: Die anonyme Methode hält nur Self, keinen Rahmen von Start.
  TAtlasDocIssueLinks.SetResolver(
    function(const AKey: string): string
    begin
      Result := IssueUrl(AKey);
    end);
end;

function TAtlasIdeIssues.IssueUrl(const AKey: string): string;
var
  Target: TAtlasTrackerTarget;
  Provider: IAtlasTrackerProvider;
begin
  Result := '';
  if not FStarted or (AKey = '') then
    Exit;
  Target := TargetOf(CurrentProject);
  Provider := ProviderOf(Target.Provider);
  if Provider <> nil then
    Result := Provider.IssuePage(Target, AKey);
end;

procedure TAtlasIdeIssues.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  TAtlasDocIssueLinks.Clear;
  // Zuerst die Zeiterfassung: Sie schreibt die letzte Zeit und bucht über FSync.
  if FTime <> nil then
    FTime.Stop;
  FTime := nil;
  FTimeRef := nil;
  FOnTimeStatus := nil;
  if FSync <> nil then
    FSync.Stop;
  // Die Hooks der Vorschau halten diese Quelle: Stop löst den Ring.
  if FPreview <> nil then
    FPreview.Stop;
  FPreview := nil;
  FPreviewRef := nil;
  FreeAndNil(FSync);
  FreeAndNil(FWatch);
  RemoveStatus;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Issues);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Issues);
  // Die Abfrage bricht beim Abbruchsignal ab (Transport); kurz warten, dann sich selbst überlassen.
  ReleaseThread(True);
  FProjects := nil;
  FProjectsRef := nil;
  FProviderFactory := nil;
  FTransportFactory := nil;
  FOnCredentials := nil;
  FOnSettings := nil;
end;

procedure TAtlasIdeIssues.ReleaseThread(AWait: Boolean);
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

function TAtlasIdeIssues.Section: TAtlasWelcomeSection;
var
  Project: string;
begin
  Project := '';
  if FStarted and Active then
    Project := CurrentProject;
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Issues,
    TAtlasWelcomeIssuesFrame.TitleText(ProjectName(Project)), Order, TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeIssues.RegisterSection;
var
  Next: TAtlasWelcomeSection;
begin
  if not FStarted then
    Exit;
  Next := Section;
  // Nur beim ersten Mal, nach einem Sprachwechsel oder mit anderem Projekt im Titel: Add meldet allen Beobachtern.
  if Next.Title <> FTitle then
  begin
    FTitle := Next.Title;
    FActive := Active;
    TAtlasWelcomeSections.Default.Add(Next);
  end;
end;

procedure TAtlasIdeIssues.Refresh;
var
  Title: string;
begin
  if not FStarted then
    Exit;
  // Einstellungen geändert (Anbieter, Abfrage): .atlas und Ziel neu.
  FTargets.Clear;
  // issues.syncState: Kommentarfeld und „Beenden …“ der Vorschau.
  if FPreview <> nil then
    FPreview.UpdateWrite;
  Title := FTitle;
  RegisterSection;
  if Title <> FTitle then
  begin
    UpdateStatus;
    Exit;
  end;
  // welcomePage.issues umgeschaltet: Auswahl der Bereiche neu; sonst nur der Inhalt.
  if FActive <> Active then
  begin
    FActive := Active;
    TAtlasWelcomeSections.Default.Changed;
  end;
  UpdateStatus;
  Changed;
end;

procedure TAtlasIdeIssues.Changed;
begin
  if FStarted then
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Issues);
end;

procedure TAtlasIdeIssues.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeIssues.CurrentProject: string;
var
  Entries: TAtlasProjectEntries;
  Entry: TAtlasProjectEntry;
  Active_: string;
begin
  Result := '';
  if not FStarted or (FProjects = nil) then
    Exit;
  Result := FProjects.Selected;
  if Result <> '' then
    Exit;
  Entries := FProjects.Entries;
  Active_ := '';
  try
    Active_ := TAtlasIdeTeamFile.ActiveProject;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  if Active_ <> '' then
  begin
    Active_ := TAtlasIdeProjects.ProjectFileOf(Active_);
    for Entry in Entries do
      if TAtlasProjectSummaries.NormalizedPath(Entry.Project) = TAtlasProjectSummaries.NormalizedPath(Active_) then
        Exit(Entry.Project);
    Exit(Active_);
  end;
  if Length(Entries) > 0 then
    Result := Entries[0].Project;
end;

function TAtlasIdeIssues.ProjectName(const AProject: string): string;
var
  Entry: TAtlasProjectEntry;
begin
  Result := '';
  if AProject = '' then
    Exit;
  if FProjects <> nil then
    for Entry in FProjects.Entries do
      if SameText(Entry.Project, AProject) then
        Exit(Entry.Name);
  Result := ChangeFileExt(ExtractFileName(AProject), '');
end;

function TAtlasIdeIssues.TargetOf(const AProject: string): TAtlasTrackerTarget;
var
  Key: string;
  Cached: TCachedTarget;
  Team: TAtlasTeamSettings;
  Settings: TAtlasPluginSettings;
begin
  Result := TAtlasTrackerTarget.Create('', '', '', '');
  if AProject = '' then
    Exit;
  // .atlas nicht bei jedem Zeichnen lesen.
  Key := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FTargets.TryGetValue(Key, Cached) and (GetTickCount64 - Cached.Tick < TargetCacheMs) then
    Exit(Cached.Target);
  try
    Team := TAtlasIdeTeamFile.ForProject(AProject);
    Settings := TAtlasIdeSettings.Current;
    Result := TAtlasWelcomeIssues.TargetFor(Team.Tracker.Provider, Team.Tracker.Url, Team.Tracker.Project,
      Settings.IssuesTracker, Settings.IssuesQuery);
  except
    // .atlas nicht lesbar: ohne Tracker.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Cached.Target := Result;
  Cached.Tick := GetTickCount64;
  FTargets.AddOrSetValue(Key, Cached);
end;

function TAtlasIdeIssues.ProviderOf(const AName: string): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FProviderFactory) and (AName <> '') then
    Result := FProviderFactory(AName);
end;

function TAtlasIdeIssues.StateOf(const AProject: string): TAtlasIssuesState;
var
  Key: string;
  Summary: TAtlasProjectSummary;
begin
  Result := TAtlasIssuesState.Empty;
  if AProject = '' then
    Exit;
  Key := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStates.TryGetValue(Key, Result) then
    Exit;
  if TAtlasProjectSummaries.Load(TAtlasIdeProjects.Folder, AProject, Summary) then
    TAtlasWelcomeIssues.Read(Summary, Result);
  FStates.AddOrSetValue(Key, Result);
end;

procedure TAtlasIdeIssues.SaveState(const AProject: string; const AState: TAtlasIssuesState);
var
  State: TAtlasIssuesState;
begin
  if AProject = '' then
    Exit;
  State := AState;
  FStates.AddOrSetValue(TAtlasProjectSummaries.NormalizedPath(AProject), State);
  TAtlasProjectSummaries.Update(TAtlasIdeProjects.Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasWelcomeIssues.Write(ASummary, State);
    end);
end;

function TAtlasIdeIssues.BranchOf(const AProject: string): string;
begin
  Result := '';
  if (FProjects <> nil) and (AProject <> '') then
    Result := FProjects.VcsOf(AProject).Branch;
end;

function TAtlasIdeIssues.Options: TAtlasIssuesOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasIssuesOptions.Create(TAtlasWelcomeIssues.StartOf(Settings.IssuesStart),
    Settings.IssuesBranchPattern, Settings.IssuesBranchBase,
    Settings.IssuesCommitPattern);
  Result.Preview := Settings.IssuesPreview and (FPreview <> nil);
end;

function TAtlasIdeIssues.ViewOf(const AProject: string): TAtlasIssuesView;
var
  Target: TAtlasTrackerTarget;
  Provider: IAtlasTrackerProvider;
begin
  Result := Default(TAtlasIssuesView);
  Result.Items := nil;
  if AProject = '' then
  begin
    Result.Status := TAtlasIssuesStatus.NotConfigured;
    Exit;
  end;
  Target := TargetOf(AProject);
  Result := TAtlasWelcomeIssues.View(StateOf(AProject), Target, BranchOf(AProject));
  Result.Project := AProject;
  Result.ProjectName := ProjectName(AProject);
  Provider := ProviderOf(Target.Provider);
  if Provider <> nil then
    Result.Tracker := Provider.Caption;
  Result.Querying := (FQueryProject <> '') and SameText(FQueryProject, AProject);
  Result.Starting := FStartProject <> '';
  if SameText(FNoticeProject, AProject) then
  begin
    Result.Notice := FNotice;
    Result.NoticeFailed := FNoticeFailed;
  end;
  Result.Options := Options;
  if FProjects <> nil then
    Result.VcsKind := TAtlasWelcomeIssues.VcsKindOf(FProjects.VcsOf(AProject).Kind);
end;

function TAtlasIdeIssues.View: TAtlasIssuesView;
var
  Project: string;
begin
  Result := Default(TAtlasIssuesView);
  Result.Items := nil;
  if not FStarted or not Active then
    Exit;
  Project := CurrentProject;
  Result := ViewOf(Project);
  // Anderes Projekt: Titel „Meine Issues · <Projekt>“ nachziehen, nicht mitten im Zeichnen.
  if TAtlasWelcomeIssuesFrame.TitleText(Result.ProjectName) <> FTitle then
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        RegisterSection;
      end);
end;

procedure TAtlasIdeIssues.Shown;
begin
  Fetch(False);
end;

class procedure TAtlasIdeIssues.Deliver(const AKeep: IAtlasIssuesSource; AOwner: TAtlasIdeIssues;
  const AProject: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
begin
  TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if AKeep <> nil then
        AOwner.Fetched(AProject, ATarget, ASucceeded, AIssues, AError);
    end);
end;

procedure TAtlasIdeIssues.Fetch(AForce: Boolean);
var
  Project: string;
  Target: TAtlasTrackerTarget;
  Provider: IAtlasTrackerProvider;
  Transports: TAtlasTrackerTransportHook;
  Keep: IAtlasIssuesSource;
  Owner: TAtlasIdeIssues;
begin
  // welcomePage.issues aus: kein Netzzugriff.
  if not FStarted or not Active or not Assigned(FTransportFactory) then
    Exit;
  // Eine Abfrage zur Zeit; die nächste kommt beim nächsten Anzeigen.
  ReleaseThread(False);
  if FThread <> nil then
    Exit;
  Project := CurrentProject;
  Target := TargetOf(Project);
  if not TAtlasWelcomeIssues.Due(StateOf(Project), Target, NowUtc, AForce) then
    Exit;
  Provider := ProviderOf(Target.Provider);
  if Provider = nil then
    Exit;
  FQueryProject := Project;
  Keep := Self;
  Owner := Self;
  Transports := FTransportFactory;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Transport: IAtlasCiTransport;
      Issues: TArray<TAtlasTrackerIssue>;
      Error: TAtlasCiFetchError;
      Ok: Boolean;
    begin
      Issues := nil;
      Ok := False;
      Error := TAtlasCiFetchError.Unauthorized;
      try
        // Liest das Token aus dem Anmeldespeicher von Windows (ohne Dialog); ohne Token kein Netz.
        Transport := Transports(Provider, Target);
        if Transport <> nil then
          Ok := Provider.Fetch(Target, Transport, TAtlasWelcomeIssues.FetchTimeoutMs, TAtlasWelcomeIssues.MaxItems,
            Issues, Error);
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          Ok := False;
          Error := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Meine Issues: Abfrage beim Tracker mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      Transport := nil;
      if TAtlasShutdown.Signalled then
        Exit;
      Deliver(Keep, Owner, Project, Target, Ok, Issues, Error);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
  Changed;
end;

procedure TAtlasIdeIssues.Fetched(const AProject: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
var
  State: TAtlasIssuesState;
begin
  FQueryProject := '';
  ReleaseThread(False);
  if not FStarted then
    Exit;
  State := StateOf(AProject);
  TAtlasWelcomeIssues.Recorded(State, ATarget, NowUtc, ASucceeded, AIssues, AError);
  SaveState(AProject, State);
  // Anonym: Anbieter, Anzahl bzw. Fehlerart; nie Adresse, Projekt, Kennungen oder Titel.
  if ASucceeded then
    TAtlasGuard.Log(Format('Meine Issues: %s, %d Issues', [ATarget.Provider, Length(AIssues)]))
  else
    TAtlasGuard.Log(Format('Meine Issues: %s nicht abgefragt (%s)', [ATarget.Provider,
      TAtlasCiBuild.ErrorKey(AError)]));
  UpdateStatus;
  Changed;
end;

procedure TAtlasIdeIssues.SetNotice(const AProject, AText: string; AFailed: Boolean);
begin
  FNoticeProject := AProject;
  FNotice := AText;
  FNoticeFailed := AFailed;
end;

procedure TAtlasIdeIssues.Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
var
  Keep: IAtlasIssuesSource;
  Project, Dir: string;
  Issue: TAtlasTrackerIssue;
  Settings: TAtlasIssuesOptions;
  Plan: TAtlasIssueStartPlan;
  Changes: Integer;
begin
  if not FStarted or not Active or (FStartProject <> '') or (AIssue.Key = '') then
    Exit;
  Project := CurrentProject;
  if Project = '' then
    Exit;
  Keep := Self;
  Issue := AIssue;
  Settings := Options;
  Settings.Start := AMode;
  Dir := ExtractFileDir(Project);
  Plan := Default(TAtlasIssueStartPlan);
  Changes := 0;
  FStartProject := Project;
  SetNotice(Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStarting, [Issue.Key]), False);
  Changed;
  // Art der Versionsverwaltung und lokale Änderungen im Hintergrund; die Rückfrage danach im Hauptthread.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      Vcs: IAtlasVersionControl;
      Kind: TAtlasVcsKind;
      Items: TArray<TAtlasVcsChange>;
    begin
      Vcs := TAtlasIdeVcs.ForFolder(Dir, VcsTimeoutMs);
      Kind := TAtlasVcsKind.None;
      if Vcs <> nil then
        Kind := Vcs.Kind;
      Plan := TAtlasWelcomeIssues.PlanStart(Kind, Settings, Issue);
      if (Plan.Mode = TAtlasIssueStart.Branch) and Plan.Valid and (Vcs <> nil) and
        (Vcs.Changes(Items) = TAtlasVcsOutcome.Ok) then
        Changes := TAtlasWelcomeIssues.LocalChanges(Items);
    end,
    procedure
    begin
      if (Keep = nil) or not FStarted then
        Exit;
      Prepared(Project, Issue, Plan, Changes);
    end) then
  begin
    FStartProject := '';
    SetNotice(Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesNotStarted, [Issue.Key]), True);
    Changed;
  end;
end;

procedure TAtlasIdeIssues.Prepared(const AProject: string; const AIssue: TAtlasTrackerIssue;
  const APlan: TAtlasIssueStartPlan; AChanges: Integer);
var
  Keep: IAtlasIssuesSource;
  Project, Dir: string;
  Issue: TAtlasTrackerIssue;
  Plan: TAtlasIssueStartPlan;
  Outcome: TAtlasIssueStartResult;
begin
  Project := AProject;
  Issue := AIssue;
  Plan := APlan;
  Outcome := Default(TAtlasIssueStartResult);
  // Lokale Änderungen: vorher fragen (Git nimmt sie mit, wenn sie nicht kollidieren).
  if (Plan.Mode = TAtlasIssueStart.Branch) and Plan.Valid and (AChanges > 0) and
    (MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesLocalChanges, [AChanges, Plan.Branch,
    sLineBreak + sLineBreak]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    FStartProject := '';
    SetNotice(Project, '', False);
    Changed;
    Exit;
  end;
  Keep := Self;
  Dir := ExtractFileDir(Project);
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Outcome := TAtlasWelcomeIssues.Execute(TAtlasIdeVcs.ForFolder(Dir, VcsTimeoutMs), Plan);
    end,
    procedure
    begin
      if (Keep = nil) or not FStarted then
        Exit;
      Finished(Project, Issue, Plan, Outcome);
    end) then
  begin
    FStartProject := '';
    SetNotice(Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesNotStarted, [Issue.Key]), True);
    Changed;
  end;
end;

procedure TAtlasIdeIssues.AskHook(const AProject: string; var AState: TAtlasIssuesState; const AHooks: string);
begin
  // Einmal je Projekt fragen; ein fremder Hook bleibt unangetastet.
  if (AHooks = '') or (AState.Hook <> '') then
    Exit;
  if TAtlasCommitHook.State(AHooks) = TAtlasCommitHookState.Own then
  begin
    AState.Hook := TAtlasWelcomeIssues.HookYes;
    Exit;
  end;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHookPrompt, [sLineBreak + sLineBreak]), mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then
  begin
    AState.Hook := TAtlasWelcomeIssues.HookNo;
    Exit;
  end;
  if TAtlasCommitHook.State(AHooks) = TAtlasCommitHookState.Foreign then
  begin
    AState.Hook := TAtlasWelcomeIssues.HookForeign;
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHookForeign));
    Exit;
  end;
  if TAtlasCommitHook.Install(AHooks) then
  begin
    AState.Hook := TAtlasWelcomeIssues.HookYes;
    TAtlasGuard.Log('Meine Issues: Git-Hook prepare-commit-msg angelegt');
  end
  else
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHookFailed));
end;

procedure TAtlasIdeIssues.Finished(const AProject: string; const AIssue: TAtlasTrackerIssue;
  const APlan: TAtlasIssueStartPlan; const AResult: TAtlasIssueStartResult);
var
  State: TAtlasIssuesState;
  Mode: TAtlasIssueStart;
  Notice: string;
begin
  FStartProject := '';
  // Anonym: Art, Ergebnis; nie Kennung, Branch oder Pfad.
  TAtlasGuard.Log(Format('Meine Issues: Beginnen %s, %s (%s)', [TAtlasWelcomeIssues.StartName(APlan.Mode),
    AtlasVcsKindName(APlan.Kind), AtlasVcsOutcomeName(AResult.Reason)]));
  case AResult.Outcome of
    TAtlasIssueStartOutcome.InvalidName:
      begin
        SetNotice(AProject, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesInvalidName, [AIssue.Key]), True);
        Changed;
        Exit;
      end;
    TAtlasIssueStartOutcome.Failed:
      begin
        SetNotice(AProject, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStartFailed, [AResult.Branch,
          AtlasVcsOutcomeName(AResult.Reason)]), True);
        Report(FNotice);
        Changed;
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Mode := TAtlasIssueStart.Branch;
  if AResult.Outcome = TAtlasIssueStartOutcome.Remembered then
    Mode := TAtlasIssueStart.Remember;
  State := StateOf(AProject);
  TAtlasWelcomeIssues.Started(State, AIssue, Mode, AResult.Branch, NowUtc);
  if AResult.GitDir <> '' then
    State.GitDir := AResult.GitDir;
  // Git-Hook für das Präfix: nur mit Muster und nach Zustimmung.
  if (APlan.Prefix <> '') and (AResult.Hooks <> '') then
    AskHook(AProject, State, AResult.Hooks);
  SaveState(AProject, State);
  case AResult.Outcome of
    TAtlasIssueStartOutcome.Started:
      Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesCreated, [AResult.Branch, AResult.Base]);
    TAtlasIssueStartOutcome.Switched:
      Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesSwitched, [AResult.Branch]);
  else
    if APlan.Prefix <> '' then
      Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesRememberedPrefix, [AIssue.Key, APlan.Prefix])
    else
      Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesRemembered, [AIssue.Key]);
  end;
  SetNotice(AProject, Notice, False);
  UpdateStatus;
  // Tracker nachführen (#1266): Ergebnis als eigene Zeile, der Branch bleibt auch bei einem Fehler.
  if FSync <> nil then
    FSync.Started(ProviderOf(TargetOf(AProject).Provider), TargetOf(AProject), AIssue.Key, AResult.Branch);
  if FPreview <> nil then
    FPreview.UpdateWrite;
  // Branch und Änderungen neu abfragen; „Projekte“ meldet sich danach selbst.
  if (FProjects <> nil) and (AResult.Outcome <> TAtlasIssueStartOutcome.Remembered) then
    FProjects.Refresh(AProject);
  Changed;
  // Danach das Projekt öffnen (ein offenes bleibt offen).
  if FProjects <> nil then
    FProjects.Open(AProject);
end;

procedure TAtlasIdeIssues.SyncPrefix(const AProject: string);
var
  State: TAtlasIssuesState;
  Active_: TAtlasActiveIssue;
  Target: TAtlasTrackerTarget;
  Prefix: string;
begin
  if AProject = '' then
    Exit;
  State := StateOf(AProject);
  if (State.GitDir = '') or (State.Hook <> TAtlasWelcomeIssues.HookYes) or not DirectoryExists(State.GitDir) then
    Exit;
  Target := TargetOf(AProject);
  Active_ := TAtlasWelcomeIssues.Effective(State, Target.Provider, Target.Project, BranchOf(AProject));
  Prefix := TAtlasWelcomeIssues.CommitPrefix(Active_, Options.CommitPattern);
  if (Prefix <> '') and not FPrefixDirs.Contains(State.GitDir) then
    FPrefixDirs.Add(State.GitDir);
  if TAtlasCommitHook.ReadPrefix(State.GitDir) = Prefix then
    Exit;
  if not TAtlasCommitHook.WritePrefix(State.GitDir, Prefix) then
    TAtlasGuard.Log('Meine Issues: Präfix-Datei für den Git-Hook nicht geschrieben');
end;

procedure TAtlasIdeIssues.ClearPrefixes;
var
  Dir: string;
begin
  // Bereich abgeschaltet: Ohne aktuelles Issue soll der Hook auch außerhalb der IDE nichts mehr voranstellen.
  for Dir in FPrefixDirs do
    if not TAtlasCommitHook.WritePrefix(Dir, '') then
      TAtlasGuard.Log('Meine Issues: Präfix-Datei für den Git-Hook nicht gelöscht');
  FPrefixDirs.Clear;
end;

procedure TAtlasIdeIssues.UpdateStatus;
var
  Project, Text: string;
  Data: TAtlasIssuesView;
  Keep: IAtlasIssuesSource;
  Action: TProc;
begin
  if not FStarted or not Active then
  begin
    RemoveStatus;
    SyncTime('', '');
    FPrefix := '';
    // Beim Entladen (Stop) bleibt das Präfix, damit der Hook außerhalb der IDE weiter gilt.
    if FStarted then
      ClearPrefixes;
    if FWatch <> nil then
      FWatch.Enabled := False;
    Exit;
  end;
  if FWatch <> nil then
    FWatch.Enabled := True;
  Project := CurrentProject;
  Data := ViewOf(Project);
  FPrefix := TAtlasWelcomeIssues.CommitPrefix(Data.Active, Options.CommitPattern);
  try
    SyncPrefix(Project);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  if not Data.Active.Active then
  begin
    RemoveStatus;
    SyncTime('', '');
    Exit;
  end;
  SyncTime(Project, Data.Active.Key);
  if FLine = nil then
  begin
    Keep := Self;
    // Typisierte Variable: Der Konstruktor ist überladen.
    Action := procedure
      begin
        if Keep <> nil then
          EndActive;
      end;
    FLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, TAtlasWelcomeIssues.StatusId,
      TAtlasWelcomeIssues.StatusOrder, Action);
    FLineRef := FLine;
    TAtlasStatusRegistry.Default.Add(FLineRef);
  end;
  Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStatusLine, [Trim(Data.Active.Key + ' ' + Data.Active.Title)]);
  FLine.Update(Text, TAtlasStatusState.Neutral, Data.Active.Key, TAtlasWelcomeIssuesFrame.TileText(Data),
    TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStatusHint));
end;

procedure TAtlasIdeIssues.RemoveStatus;
begin
  if FLine = nil then
    Exit;
  FLine.Detach;
  TAtlasStatusRegistry.Default.Remove(TAtlasWelcomeIssues.StatusId);
  FLine := nil;
  FLineRef := nil;
end;

procedure TAtlasIdeIssues.WatchTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Inc(FTicks);
      if FTicks mod StatusTicks = 0 then
        UpdateStatus;
      FillCommitDialog;
    end);
end;

/// <summary>Erstes beschreibbares, sichtbares Nachrichtenfeld (Memo) in AControl.</summary>
function FindMessageMemo(AControl: TWinControl): TCustomMemo;
var
  Index: Integer;
  Child: TControl;
begin
  Result := nil;
  for Index := 0 to AControl.ControlCount - 1 do
  begin
    Child := AControl.Controls[Index];
    if not Child.Visible then
      Continue;
    if (Child is TCustomMemo) and Child.Enabled and not TEditAccess(Child).ReadOnly then
      Exit(TCustomMemo(Child));
    if Child is TWinControl then
    begin
      Result := FindMessageMemo(TWinControl(Child));
      if Result <> nil then
        Exit;
    end;
  end;
end;

procedure TAtlasIdeIssues.FillCommitDialog;
var
  Form: TCustomForm;
  Memo: TCustomMemo;
  Index: Integer;
  Text: string;
begin
  // Vergessene Felder: Fenster gibt es nicht mehr.
  for Index := FFilled.Count - 1 downto 0 do
    if not IsWindow(FFilled[Index]) then
      FFilled.Delete(Index);
  if FPrefix = '' then
    Exit;
  Form := Screen.ActiveForm;
  // Commit-Dialog der Versionsverwaltung der IDE (Git, SVN, Mercurial): am Namen der Formularklasse erkannt.
  if (Form = nil) or not (ContainsText(Form.ClassName, 'Commit') or ContainsText(Form.Name, 'Commit')) then
    Exit;
  Memo := FindMessageMemo(Form);
  if (Memo = nil) or not Memo.HandleAllocated or FFilled.Contains(Memo.Handle) then
    Exit;
  // Einmal je Dialog: Was der Benutzer danach ändert, bleibt.
  FFilled.Add(Memo.Handle);
  Text := TAtlasTrackerNaming.Prefixed(TEditAccess(Memo).Text, FPrefix);
  if Text = TEditAccess(Memo).Text then
    Exit;
  TEditAccess(Memo).Text := Text;
  Memo.SelStart := Length(Text);
  TAtlasGuard.Log('Meine Issues: Präfix im Commit-Dialog der IDE ergänzt');
end;

procedure TAtlasIdeIssues.Browse(const AIssue: TAtlasTrackerIssue);
var
  Issue: TAtlasTrackerIssue;
begin
  Issue := AIssue;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Target: TAtlasTrackerTarget;
      Provider: IAtlasTrackerProvider;
      Url: string;
    begin
      Target := TargetOf(CurrentProject);
      Provider := ProviderOf(Target.Provider);
      if Provider = nil then
        Exit;
      Url := Provider.IssuePage(Target, Issue.Key);
      // Nur Web-Adressen aus der eingetragenen Adresse, nie etwas aus der Antwort des Trackers.
      if Url.StartsWith('https://', True) or Url.StartsWith('http://', True) then
        ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
    end);
end;

procedure TAtlasIdeIssues.Preview(const AIssue: TAtlasTrackerIssue);
var
  mIssue: TAtlasTrackerIssue;
begin
  mIssue := AIssue;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not FStarted or (FPreview = nil) or not TAtlasIdeIssuePreview.Active then
        Exit;
      FPreview.Show(TargetOf(CurrentProject), mIssue.Key);
    end);
end;

function TAtlasIdeIssues.ActiveTarget(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
var
  mProject: string;
  mTeam: TAtlasTeamSettings;
  mSettings: TAtlasPluginSettings;
begin
  // Das aktive Projekt der IDE, sonst das des Bereichs.
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
    mProject := CurrentProject;
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  if mProject <> '' then
  begin
    mTeam := TAtlasIdeTeamFile.ForProject(mProject);
    mSettings := TAtlasIdeSettings.Current;
    ATarget := TAtlasWelcomeIssues.TargetFor(mTeam.Tracker.Provider, mTeam.Tracker.Url, mTeam.Tracker.Project,
      mSettings.IssuesTracker, mSettings.IssuesQuery);
  end;
  Result := ProviderOf(ATarget.Provider);
  if ATarget.Server = '' then
    Result := nil;
end;

procedure TAtlasIdeIssues.ShowPreviewPrompt;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
      mInput, mKey: string;
    begin
      if not FStarted or (FPreview = nil) or not TAtlasIdeIssuePreview.Active then
        Exit;
      mProvider := ActiveTarget(mTarget);
      if mProvider = nil then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoTracker));
        Exit;
      end;
      mInput := '';
      if not InputQuery(TAtlasStrings.Text(TAtlasTextId.IssuePreviewCaption),
        TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewPrompt, [TAtlasIssuePreview.KeyExample(mTarget.Provider)]),
        mInput) then
        Exit;
      mKey := TAtlasIssuePreview.KeyOf(mTarget.Provider, mInput);
      if mKey = '' then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewInvalidKey, [Trim(mInput)]));
        Exit;
      end;
      FPreview.Show(mTarget, mKey);
    end);
end;

procedure TAtlasIdeIssues.BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
var
  Issue: TAtlasTrackerIssue;
begin
  Issue := AIssue;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Target: TAtlasTrackerTarget;
      Provider: IAtlasTrackerProvider;
      Url: string;
    begin
      Target := TargetOf(CurrentProject);
      Provider := ProviderOf(Target.Provider);
      if (Provider = nil) or (Issue.PullRequest.Number <= 0) then
        Exit;
      Url := Provider.PullRequestPage(Target, Issue.PullRequest.Number);
      if Url.StartsWith('https://', True) or Url.StartsWith('http://', True) then
        ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
    end);
end;

procedure TAtlasIdeIssues.QueryNow;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Fetch(True);
    end);
end;

function TAtlasIdeIssues.CanEnterCredentials: Boolean;
begin
  Result := FStarted and TAtlasIdeSettings.Current.TrackerLogin and Assigned(FOnCredentials);
end;

procedure TAtlasIdeIssues.Credentials;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Target: TAtlasTrackerTarget;
      Provider: IAtlasTrackerProvider;
    begin
      if not CanEnterCredentials then
        Exit;
      Target := TargetOf(CurrentProject);
      Provider := ProviderOf(Target.Provider);
      if (Provider = nil) or (Target.Server = '') then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.TrackerLoginNoTracker));
        Exit;
      end;
      if not FOnCredentials(Provider, Target) then
        Exit;
      // Mit dem neuen Zugang gleich fragen (nur mit welcomePage.issues).
      Fetch(True);
    end);
end;

procedure TAtlasIdeIssues.EnterCredentialsForActive;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Target: TAtlasTrackerTarget;
      Provider: IAtlasTrackerProvider;
    begin
      if not FStarted or not TAtlasIdeSettings.Current.TrackerLogin or not Assigned(FOnCredentials) then
        Exit;
      Provider := ActiveTarget(Target);
      if Provider = nil then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.TrackerLoginNoTracker));
        Exit;
      end;
      if FOnCredentials(Provider, Target) then
        Fetch(True);
    end);
end;

procedure TAtlasIdeIssues.EndActive;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Project, Branch: string;
      State: TAtlasIssuesState;
      Target: TAtlasTrackerTarget;
      Current: TAtlasActiveIssue;
      Provider: IAtlasTrackerProvider;
    begin
      if not FStarted then
        Exit;
      Project := CurrentProject;
      if Project = '' then
        Exit;
      State := StateOf(Project);
      Branch := BranchOf(Project);
      Target := TargetOf(Project);
      Current := TAtlasWelcomeIssues.Effective(State, Target.Provider, Target.Project, Branch);
      if not Current.Active then
        Exit;
      // Tracker nachführen (#1266): Dialog statt Rückfrage; ohne issues.syncState wie bisher.
      Provider := ProviderOf(Target.Provider);
      if (FSync <> nil) and FSync.Enabled(Provider, Target) then
      begin
        EndWithTracker(Project, Branch, Current.Key, Provider, Target, State);
        Exit;
      end;
      if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesEndConfirm, [Current.Key]), mtConfirmation,
        [mbYes, mbNo], 0) <> mrYes then
        Exit;
      EndedLocally(Project, Branch, Current.Key);
    end);
end;

procedure TAtlasIdeIssues.EndedLocally(const AProject, ABranch, AKey: string);
var
  mState: TAtlasIssuesState;
begin
  if not FStarted then
    Exit;
  mState := StateOf(AProject);
  TAtlasWelcomeIssues.Ended(mState, ABranch);
  SaveState(AProject, mState);
  // Zeiterfassung (#1267): Zeit schreiben und das Buchen anbieten (Beschreibung aus den Commits).
  if FTime <> nil then
    FTime.Ended(TimeIssueOf(AProject, AKey), ExtractFileDir(AProject), ABranch,
      TAtlasIdeSettings.Current.IssuesBranchBase);
  SetNotice(AProject, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesEnded, [AKey]), False);
  TAtlasGuard.Log('Meine Issues: aktuelles Issue beendet');
  UpdateStatus;
  if FPreview <> nil then
    FPreview.UpdateWrite;
  Changed;
end;

procedure TAtlasIdeIssues.EndWithTracker(const AProject, ABranch, AKey: string;
  const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget; const AState: TAtlasIssuesState);
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mIssue: TAtlasTrackerIssue;
  mPullRequest, mProject, mBranch, mKey: string;
begin
  // Eigene Routine: Die Methodenreferenz hält nur diese Werte.
  mKeep := Self;
  mOwner := Self;
  mProject := AProject;
  mBranch := ABranch;
  mKey := AKey;
  mPullRequest := '';
  if AState.Find(AKey, mIssue) and (mIssue.PullRequest.Number > 0) then
    mPullRequest := AProvider.PullRequestPage(ATarget, mIssue.PullRequest.Number);
  FSync.EndIssue(AProvider, ATarget, TAtlasIdeTrackerEnd.Create(AKey, ABranch, ExtractFileDir(AProject),
    TAtlasIdeSettings.Current.IssuesBranchBase, mPullRequest),
    procedure(AChange: TAtlasTrackerChange)
    begin
      if mKeep <> nil then
        mOwner.EndedLocally(mProject, mBranch, mKey);
    end);
end;

function TAtlasIdeIssues.ActiveKey: string;
var
  mProject: string;
  mTarget: TAtlasTrackerTarget;
  mCurrent: TAtlasActiveIssue;
begin
  Result := '';
  if not FStarted then
    Exit;
  mProject := CurrentProject;
  if mProject = '' then
    Exit;
  mTarget := TargetOf(mProject);
  mCurrent := TAtlasWelcomeIssues.Effective(StateOf(mProject), mTarget.Provider, mTarget.Project, BranchOf(mProject));
  if mCurrent.Active then
    Result := mCurrent.Key;
end;

end.
