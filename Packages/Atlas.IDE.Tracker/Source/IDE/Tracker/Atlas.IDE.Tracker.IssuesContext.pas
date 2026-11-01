unit Atlas.IDE.Tracker.IssuesContext;

// Gemeinsamer Stand von „Meine Issues“ (#765, aus Atlas.IDE.Tracker.MyIssues
// gelöst, #1455): Projekt des Bereichs, Tracker je Projekt (.atlas, sonst
// persönliche Zuordnung #1261, 5 s zwischengespeichert), Abschnitt "issues"
// der Projekt-Zusammenfassung, Hinweis, Filter der Sprint-Kachel und die Hooks
// der Komposition. Die Teile (Dienste, Abfrage, Beginnen, Statusfeld, Befehle)
// lesen und schreiben hier; was sie beim Besitzer auslösen, geht über
// IAtlasIdeIssuesActions.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.MyIssues,
  Atlas.IDE.Tracker.TimeTracking,
  Atlas.IDE.Tracker.WelcomeLink;

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

  /// <summary>Hooks der Komposition; jedes Feld darf fehlen. Vor Start setzen, Stop löst sie.</summary>
  TAtlasIdeIssuesHooks = record
    Provider: TAtlasTrackerProviderHook;
    Transport: TAtlasTrackerTransportHook;
    Credentials: TAtlasTrackerCredentialsHook;
    /// <summary>Tools › Optionen › Atlas › Issue-Tracker (Knopf „Tracker-Einstellungen“ der Vorschau).</summary>
    Settings: TProc;
    /// <summary>„zuordnen …“ (#1261): Seite Issue-Tracker mit einer Zeile für „Gilt für“ = Argument öffnen.</summary>
    AssignProject: TProc<string>;
    /// <summary>„Abfragen bearbeiten …“ (#1262): Seite Issue-Tracker bei der Tabelle Abfragen öffnen.</summary>
    EditQueries: TProc;
    /// <summary>Zusatzfeld der Zeiterfassung im Statusfeld (#1267).</summary>
    TimeStatus: TAtlasIdeTimeStatus;
  end;

  /// <summary>Tracker eines Projekts mit Verbindung und Abfragen.</summary>
  TAtlasIssuesCachedTarget = record
    Target: TAtlasTrackerTarget;
    /// <summary>Name der Verbindung (#1261); '' ohne Tracker.</summary>
    Connection: string;
    /// <summary>Passende Abfragen (#1262) und die gewählte; Target.Query ist deren Abfrage.</summary>
    Queries: TArray<TAtlasTrackerQuery>;
    QueryIndex: Integer;
    Tick: UInt64;
    /// <summary>Ohne Tracker (Server '', keine Abfrage).</summary>
    class function Empty: TAtlasIssuesCachedTarget; static;
  end;

  /// <summary>Hinweis unter der Liste, nur für AProject.</summary>
  TAtlasIssuesNotice = record
    Project: string;
    Text: string;
    Failed: Boolean;
    class function Create(const AProject, AText: string; AFailed: Boolean): TAtlasIssuesNotice; static;
  end;

  /// <summary>Filter der Sprint-Kachel (#1277): nur für Project.</summary>
  TAtlasIssuesFilter = record
    Caption: string;
    Project: string;
    Issues: TArray<TAtlasTrackerIssue>;
  end;

  /// <summary>Was die Teile beim Besitzer TAtlasIdeIssues auslösen.</summary>
  IAtlasIdeIssuesActions = interface
    ['{6B0F2C1E-4D7A-4E59-9A3B-2F8C5D1E7A40}']
    /// <summary>„Beginnen“ (#765).</summary>
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    /// <summary>Das aktuelle Issue beenden (nach Rückfrage bzw. Dialog).</summary>
    procedure EndActive;
    /// <summary>Liste auf AIssues beschränken (Sprint-Kachel); ohne den Bereich öffnet es das Board.</summary>
    procedure SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
    /// <summary>„zuordnen …“ (#1261).</summary>
    procedure AssignProject;
    /// <summary>Titel oder Schalter der Kachel geändert: der Willkommensseite melden.</summary>
    procedure UpdateTileInfo;
    /// <summary>Inhalt der Kachel für AProject.</summary>
    function ViewOf(const AProject: string): TAtlasIssuesView;
  end;

  /// <summary>Tracker eines Projekts ohne Zwischenspeicher, Ordner und Hilfen ohne Zustand.</summary>
  TAtlasIdeIssuesTargets = class
  public
    /// <summary>Tracker für AProject: .atlas, sonst persönliche Zuordnung, mit den passenden Abfragen (#1262);
    /// ohne Wahl der Abfrage (Target.Query leer, QueryIndex -1).</summary>
    class function Resolve(const AProject: string): TAtlasIssuesCachedTarget; static;
    /// <summary>Die gewählte Abfrage aus AState in ACached eintragen.</summary>
    class procedure ChooseQuery(var ACached: TAtlasIssuesCachedTarget; const AState: TAtlasIssuesState); static;
    /// <summary>Tracker des Projekts AProject mit dem Namen der Verbindung in AConnection ('' ohne bzw. aus der
    /// .atlas); für „Issue anlegen …“ (#1268). Ohne Netz.</summary>
    class function TrackerOf(const AProject: string; out AConnection: string): TAtlasTrackerTarget; static;
    class function NowUtc: TDateTime; static;
    /// <summary>%LOCALAPPDATA%\Atlas\issues: Zwischenspeicher der Vorschau, des Boards, Entwürfe der Kommentare
    /// (#1278) und notify.json (#1271).</summary>
    class function IssuesFolder: string; static;
    /// <summary>welcomePage.issues an?</summary>
    class function Active: Boolean; static;
    /// <summary>AUrl im Browser, nur Web-Adressen (http, https).</summary>
    class procedure OpenPage(const AUrl: string); static;
  end;

  TAtlasIdeIssuesContext = class
  public const
    /// <summary>Kennung der Kachel; dieselbe wie früher als Bereich der Willkommensseite (Layouts bleiben).
    /// </summary>
    cTileId = 'atlas.issues';
    /// <summary>So lange gilt der gelesene Tracker aus .atlas, bevor er neu gelesen wird.</summary>
    cTargetCacheMs = 5000;
  private
    FWelcome: TAtlasTrackerWelcomeLink;
    FMessage: TProc<string>;
    FStarted: Boolean;
    // Normierter Pfad → Abschnitt "issues" (nicht bei jedem Zeichnen die Datei lesen).
    FStates: TDictionary<string, TAtlasIssuesState>;
    FTargets: TDictionary<string, TAtlasIssuesCachedTarget>;
    FHooks: TAtlasIdeIssuesHooks;
    FNotice: TAtlasIssuesNotice;
    FFilter: TAtlasIssuesFilter;
    FStartProject: string;
    FQueryProject: string;
    FActions: IAtlasIdeIssuesActions;
  public
    /// <summary>AWelcome: Projekte der Willkommensseite und Meldungen an ihre Kacheln (gehört dem Aufrufer).
    /// AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(AWelcome: TAtlasTrackerWelcomeLink; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Inhalt der Kachel geändert: der Willkommensseite melden.</summary>
    procedure Changed;
    /// <summary>Zeile in die Meldungsansicht.</summary>
    procedure Report(const AText: string);
    /// <summary>Das in „Projekte“ gewählte, sonst das aktive der IDE, sonst das oberste der Liste; '' ohne.</summary>
    function CurrentProject: string;
    function ProjectName(const AProject: string): string;
    function TargetOf(const AProject: string): TAtlasTrackerTarget;
    /// <summary>Ziel und Verbindung für AProject (#1261), cTargetCacheMs zwischengespeichert.</summary>
    function CachedTargetOf(const AProject: string): TAtlasIssuesCachedTarget;
    /// <summary>Alle Ziele neu lesen (Einstellungen, Zuordnung oder Abfragen geändert).</summary>
    procedure ForgetTargets;
    /// <summary>Ziel von AProject neu lesen (andere Abfrage gewählt).</summary>
    procedure ForgetTarget(const AProject: string);
    /// <summary>Anbieter zum Namen über Hooks.Provider; nil ohne.</summary>
    function ProviderOf(const AName: string): IAtlasTrackerProvider;
    /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token. Auch im Hintergrund-Thread.
    /// </summary>
    function TransportOf(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget):
      IAtlasCiTransport;
    function StateOf(const AProject: string): TAtlasIssuesState;
    procedure SaveState(const AProject: string; const AState: TAtlasIssuesState);
    function BranchOf(const AProject: string): string;
    /// <summary>Kennung des aktuellen Issues im Projekt des Bereichs; '' ohne.</summary>
    function ActiveKey: string;
    /// <summary>Tracker des aktiven Projekts der IDE, sonst des Bereichs; nil ohne Tracker.</summary>
    function ActiveTarget(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    /// <summary>„Beginnen“ gerade möglich (Bereich an, kein Beginnen läuft, Projekt vorhanden)?</summary>
    function CanStart: Boolean;
    function CanEnterCredentials: Boolean;
    function CanAssign: Boolean;
    /// <summary>Gehört dem Aufrufer; Stop setzt nil.</summary>
    property Welcome: TAtlasTrackerWelcomeLink read FWelcome write FWelcome;
    property Started: Boolean read FStarted write FStarted;
    property Hooks: TAtlasIdeIssuesHooks read FHooks write FHooks;
    property Notice: TAtlasIssuesNotice read FNotice write FNotice;
    property Filter: TAtlasIssuesFilter read FFilter write FFilter;
    /// <summary>Projekt, in dem „Beginnen“ läuft; sperrt ein zweites.</summary>
    property StartProject: string read FStartProject write FStartProject;
    /// <summary>Projekt, dessen Abfrage läuft.</summary>
    property QueryProject: string read FQueryProject write FQueryProject;
    /// <summary>Der Besitzer; Stop setzt nil (löst den Ring).</summary>
    property Actions: IAtlasIdeIssuesActions read FActions write FActions;
  end;

implementation

uses
  Winapi.Windows,
  System.DateUtils,
  System.IOUtils,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.UI.Strings,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Projects.Summaries;

const
  cAppFolder = 'Atlas';
  cIssuesFolder = 'issues';
  cLocalAppData = 'LOCALAPPDATA';
  cHttps = 'https://';
  cHttp = 'http://';

{ TAtlasIssuesCachedTarget }

class function TAtlasIssuesCachedTarget.Empty: TAtlasIssuesCachedTarget;
begin
  Result := Default(TAtlasIssuesCachedTarget);
  Result.Target := TAtlasTrackerTarget.Create('', '', '', '');
  Result.Queries := nil;
  Result.QueryIndex := -1;
end;

{ TAtlasIssuesNotice }

class function TAtlasIssuesNotice.Create(const AProject, AText: string; AFailed: Boolean): TAtlasIssuesNotice;
begin
  Result.Project := AProject;
  Result.Text := AText;
  Result.Failed := AFailed;
end;

{ TAtlasIdeIssuesTargets }

class function TAtlasIdeIssuesTargets.Resolve(const AProject: string): TAtlasIssuesCachedTarget;
var
  mTeam: TAtlasTeamSettings;
  mSettings: TAtlasPluginSettings;
  mResolution: TAtlasTrackerResolution;
  mConnections: TArray<TAtlasTrackerConnection>;
begin
  Result := TAtlasIssuesCachedTarget.Empty;
  if AProject = '' then
  begin
    Exit;
  end;
  try
    mTeam := TAtlasIdeTeamFile.ForProject(AProject);
    mSettings := TAtlasIdeSettings.Current;
    mConnections := TAtlasTrackerConnections.Read(mSettings.IssuesConnections);
    // .atlas vor der persönlichen Zuordnung (.dproj, geöffnete .groupproj, längster Ordner).
    mResolution := TAtlasTrackerProjects.Resolve(TAtlasTrackerTarget.Create(mTeam.Tracker.Provider,
      mTeam.Tracker.Url, mTeam.Tracker.Project, ''), TAtlasTrackerProjects.Read(mSettings.IssuesProjects),
      mConnections, AProject, TAtlasIdeFiles.GroupOfProject(AProject));
    Result.Target := TAtlasMyIssues.TargetFor(mResolution, mSettings.IssuesTracker, '');
    // Sprache der Oberfläche (#1263): Vorgabe „Mir zugewiesen“ in der Sprache, die „Prüfen“ erkannt hat.
    Result.Target.Language := TAtlasTrackerConnections.LanguageOf(mConnections, Result.Target);
    if mResolution.Found then
    begin
      Result.Connection := mResolution.Connection.Name;
    end;
    Result.Queries := TAtlasTrackerQueries.Available(TAtlasTrackerQueries.Read(mSettings.IssuesQueries),
      Result.Target, Result.Connection, mConnections, TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryDefault));
  except
    // .atlas nicht lesbar: ohne Tracker.
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
end;

class procedure TAtlasIdeIssuesTargets.ChooseQuery(var ACached: TAtlasIssuesCachedTarget;
  const AState: TAtlasIssuesState);
begin
  // Ohne Klappliste gilt die erste passende Abfrage, sonst die gemerkte (falls es sie noch gibt).
  ACached.QueryIndex := TAtlasTrackerQueries.Choose(ACached.Queries, AState.Selected,
    TAtlasIdeSettings.Current.IssuesQueryPicker);
  ACached.Target.Query := '';
  if ACached.QueryIndex >= 0 then
  begin
    ACached.Target.Query := ACached.Queries[ACached.QueryIndex].Query;
  end;
end;

class function TAtlasIdeIssuesTargets.TrackerOf(const AProject: string; out AConnection: string):
  TAtlasTrackerTarget;
var
  mCached: TAtlasIssuesCachedTarget;
begin
  mCached := Resolve(AProject);
  AConnection := mCached.Connection;
  Result := mCached.Target;
  // Die Abfrage gehört zu „Meine Issues“, nicht zum Anlegen.
  Result.Query := '';
end;

class function TAtlasIdeIssuesTargets.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeIssuesTargets.IssuesFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable(cLocalAppData), cAppFolder), cIssuesFolder);
end;

class function TAtlasIdeIssuesTargets.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageIssues;
end;

class procedure TAtlasIdeIssuesTargets.OpenPage(const AUrl: string);
begin
  // Nur Web-Adressen aus der eingetragenen Adresse, nie etwas aus der Antwort des Trackers.
  if AUrl.StartsWith(cHttps, True) or AUrl.StartsWith(cHttp, True) then
  begin
    TAtlasTrackerFiles.Shell.Open(AUrl);
  end;
end;

{ TAtlasIdeIssuesContext }

constructor TAtlasIdeIssuesContext.Create(AWelcome: TAtlasTrackerWelcomeLink; const AMessage: TProc<string>);
begin
  inherited Create;
  FWelcome := AWelcome;
  FMessage := AMessage;
  FStates := TDictionary<string, TAtlasIssuesState>.Create;
  FTargets := TDictionary<string, TAtlasIssuesCachedTarget>.Create;
end;

destructor TAtlasIdeIssuesContext.Destroy;
begin
  FTargets.Free;
  FStates.Free;
  inherited;
end;

procedure TAtlasIdeIssuesContext.Changed;
begin
  if FStarted and (FWelcome <> nil) then
  begin
    FWelcome.TileChanged(cTileId);
  end;
end;

procedure TAtlasIdeIssuesContext.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

/// <summary>Aktives Projekt der IDE als Projektdatei; '' ohne bzw. wenn es nicht lesbar ist.</summary>
function IdeProject: string;
begin
  Result := '';
  try
    Result := TAtlasIdeTeamFile.ActiveProject;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
  if Result <> '' then
  begin
    Result := TAtlasIdeProjectSummaries.ProjectFileOf(Result);
  end;
end;

function TAtlasIdeIssuesContext.CurrentProject: string;
var
  mProjects: TArray<TAtlasWelcomeProject>;
  mProject: TAtlasWelcomeProject;
  mActive: string;
begin
  Result := '';
  if FStarted and (FWelcome <> nil) then
  begin
    Result := FWelcome.Selected;
  end;
  if not FStarted or (FWelcome = nil) or (Result <> '') then
  begin
    Exit;
  end;
  mProjects := FWelcome.Projects;
  mActive := IdeProject;
  Result := mActive;
  for mProject in mProjects do
  begin
    if (mActive <> '') and (TAtlasProjectSummaries.NormalizedPath(mProject.Project) =
      TAtlasProjectSummaries.NormalizedPath(mActive)) then
    begin
      Exit(mProject.Project);
    end;
  end;
  if (mActive = '') and (Length(mProjects) > 0) then
  begin
    Result := mProjects[0].Project;
  end;
end;

function TAtlasIdeIssuesContext.ProjectName(const AProject: string): string;
begin
  Result := '';
  if FWelcome <> nil then
  begin
    Result := FWelcome.NameOf(AProject);
  end;
end;

function TAtlasIdeIssuesContext.TargetOf(const AProject: string): TAtlasTrackerTarget;
begin
  Result := CachedTargetOf(AProject).Target;
end;

function TAtlasIdeIssuesContext.CachedTargetOf(const AProject: string): TAtlasIssuesCachedTarget;
var
  mKey: string;
begin
  Result := TAtlasIssuesCachedTarget.Empty;
  if AProject = '' then
  begin
    Exit;
  end;
  // .atlas nicht bei jedem Zeichnen lesen.
  mKey := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FTargets.TryGetValue(mKey, Result) and (GetTickCount64 - Result.Tick < cTargetCacheMs) then
  begin
    Exit;
  end;
  Result := TAtlasIdeIssuesTargets.Resolve(AProject);
  TAtlasIdeIssuesTargets.ChooseQuery(Result, StateOf(AProject));
  Result.Tick := GetTickCount64;
  FTargets.AddOrSetValue(mKey, Result);
end;

procedure TAtlasIdeIssuesContext.ForgetTargets;
begin
  FTargets.Clear;
end;

procedure TAtlasIdeIssuesContext.ForgetTarget(const AProject: string);
begin
  FTargets.Remove(TAtlasProjectSummaries.NormalizedPath(AProject));
end;

function TAtlasIdeIssuesContext.ProviderOf(const AName: string): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FHooks.Provider) and (AName <> '') then
  begin
    Result := FHooks.Provider(AName);
  end;
end;

function TAtlasIdeIssuesContext.TransportOf(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
var
  mFactory: TAtlasTrackerTransportHook;
begin
  Result := nil;
  // Einmal lesen: Stop setzt die Hooks im Hauptthread zurück.
  mFactory := FHooks.Transport;
  if Assigned(mFactory) and (AProvider <> nil) then
  begin
    Result := mFactory(AProvider, ATarget);
  end;
end;

function TAtlasIdeIssuesContext.StateOf(const AProject: string): TAtlasIssuesState;
var
  mKey: string;
  mSummary: TAtlasProjectSummary;
begin
  Result := TAtlasIssuesState.Empty;
  if AProject = '' then
  begin
    Exit;
  end;
  mKey := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStates.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  if TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, AProject, mSummary) then
  begin
    TAtlasMyIssues.Read(mSummary, Result);
  end;
  FStates.AddOrSetValue(mKey, Result);
end;

procedure TAtlasIdeIssuesContext.SaveState(const AProject: string; const AState: TAtlasIssuesState);
var
  mState: TAtlasIssuesState;
begin
  if AProject = '' then
  begin
    Exit;
  end;
  mState := AState;
  FStates.AddOrSetValue(TAtlasProjectSummaries.NormalizedPath(AProject), mState);
  TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasMyIssues.Write(ASummary, mState);
    end);
end;

function TAtlasIdeIssuesContext.BranchOf(const AProject: string): string;
begin
  Result := '';
  if FWelcome <> nil then
  begin
    Result := FWelcome.VcsOf(AProject).Branch;
  end;
end;

function TAtlasIdeIssuesContext.ActiveKey: string;
var
  mProject: string;
  mTarget: TAtlasTrackerTarget;
  mCurrent: TAtlasActiveIssue;
begin
  Result := '';
  mProject := CurrentProject;
  if mProject = '' then
  begin
    Exit;
  end;
  mTarget := TargetOf(mProject);
  mCurrent := TAtlasMyIssues.Effective(StateOf(mProject), mTarget.Provider, mTarget.Project, BranchOf(mProject));
  if mCurrent.Active then
  begin
    Result := mCurrent.Key;
  end;
end;

function TAtlasIdeIssuesContext.ActiveTarget(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
var
  mProject: string;
begin
  // Das aktive Projekt der IDE, sonst das des Bereichs; Tracker wie im Bereich (.atlas, sonst Zuordnung #1261).
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
  begin
    mProject := CurrentProject;
  end;
  ATarget := TAtlasIdeIssuesTargets.Resolve(mProject).Target;
  Result := ProviderOf(ATarget.Provider);
  if ATarget.Server = '' then
  begin
    Result := nil;
  end;
end;

function TAtlasIdeIssuesContext.CanStart: Boolean;
begin
  Result := FStarted and TAtlasIdeIssuesTargets.Active and (FStartProject = '') and (CurrentProject <> '');
end;

function TAtlasIdeIssuesContext.CanEnterCredentials: Boolean;
begin
  Result := FStarted and TAtlasIdeSettings.Current.TrackerLogin and Assigned(FHooks.Credentials);
end;

function TAtlasIdeIssuesContext.CanAssign: Boolean;
begin
  Result := FStarted and Assigned(FHooks.AssignProject);
end;

end.
