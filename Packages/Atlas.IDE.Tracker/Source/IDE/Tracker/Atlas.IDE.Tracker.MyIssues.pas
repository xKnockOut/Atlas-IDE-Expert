unit Atlas.IDE.Tracker.MyIssues;

// Bereich „Meine Issues“ in der IDE (#765): Quelle des Bereichs
// (IAtlasIssuesSource), Anmeldung als Bereich atlas.issues der
// Willkommensseite (bzw. des Fensters „Atlas-Start“), Abfrage beim
// Issue-Tracker im Hintergrund, „Beginnen“, das aktuelle Issue im
// Statusfeld (#591) und das Commit-Präfix.
// - Projekt: das in „Projekte“ gewählte, sonst das aktive der IDE, sonst das
//   oberste der Liste. Tracker (Anbieter, Adresse, Projekt) aus dessen .atlas
//   (#486, Abschnitt tracker); issues.tracker ersetzt den
//   Anbieter. Ohne tracker in der .atlas gilt die
//   persönliche Zuordnung (#1261, TAtlasTrackerProjects.Resolve: .dproj, dann
//   die geöffnete .groupproj, dann der längste Ordner) mit der Verbindung aus
//   issues.connections; ohne beides bietet der Bereich „zuordnen …“ an
//   (OnAssignProject öffnet die Seite Issue-Tracker mit vorbefüllter Zeile).
//   „Zugang zum Issue-Tracker hinterlegen …“ nutzt dieselbe Auflösung.
// - Abfrage (#1262): die passenden aus issues.queries (ohne eigene je
//   Anbieter „Mir zugewiesen“), davon die je Projekt gewählte (Klappliste,
//   SelectQuery; gemerkt im Abschnitt "issues" der Zusammenfassung) bzw. mit
//   issues.queryPicker aus die erste. Ein Wechsel fragt gleich ab; die
//   Trefferzahl je Abfrage bleibt für die Klappliste stehen.
//   „Abfragen bearbeiten …“ öffnet die Seite Issue-Tracker (OnEditQueries).
// - Abfrage nur mit welcomePage.issues (Vorgabe aus; sonst kein Netz), beim
//   Anzeigen, höchstens alle 10 Minuten (gemerkt im Abschnitt "issues" der
//   Projekt-Zusammenfassung), im Hintergrund mit 5 s. Ohne Token im
//   Anmeldespeicher kein Netzzugriff („Zugang hinterlegen“). Ohne Netz bleibt
//   der letzte Stand mit „Stand vom …“; kein Dialog.
// - „Beginnen“: Git legt den Branch nach Muster von der Basis an (main, sonst
//   master) und checkt ihn aus, SVN kopiert ^/trunk nach ^/branches/<Name> und
//   wechselt mit svn switch; ein vorhandener Branch wird nur ausgecheckt. Bei
//   lokalen Änderungen fragt Atlas vorher. start=remember merkt nur die
//   Kennung. Danach öffnet Atlas das Projekt. Fehlt der Branch noch, zeigt
//   Atlas mit vcs.branch.confirm vorher den Dialog „Branch anlegen“ (#1288,
//   TAtlasIdeBranching) mit Name, Basis und den Schritten; die Schritte kommen
//   in jedem Fall aus TAtlasVcsBranchPlan, je Schritt eine Zeile in der
//   Meldungsansicht. Git-Optionen (#1289): Ohne Dialog gelten die Vorgaben
//   aus vcs.branch.git.* (bei uncommitted = ask fragt Atlas „Mitnehmen“,
//   „Beiseitelegen“ oder „Abbrechen“); mit Dialog stehen sie dort. Scheitert
//   der Abruf, fragt Atlas nur nach dem Dialog nach dem lokalen Stand, sonst
//   bricht es ab. Mit worktree gilt das Issue für das Projekt im neuen Ordner,
//   und Atlas bietet an, es dort zu öffnen.
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
// - Issue-Kennungen im Editor (#1265, Atlas.IDE.Tracker.CodeLinks): CodeTarget
//   (Tracker des aktiven Projekts, wie „Issue anzeigen …“), ShowIssue
//   (Vorschau bzw. Browser), BrowseIssue und StartIssue („Beginnen“ mit dem
//   Titel aus dem Zwischenspeicher bzw. einer Kurzabfrage).
// - Warnung beim Beginnen (#1279, issues.warnBlocked): vorher liest die
//   Vorschau die Verknüpfungen des Issues (CheckBlocked); ist ein „hängt ab
//   von“-Issue offen, fragt Atlas „ATL-129 blockiert dieses Issue und ist noch
//   offen“ mit „Trotzdem beginnen“ und „ATL-129 ansehen“. Ohne Antwort und ohne
//   Zwischenspeicher beginnt es ohne Rückfrage (kein Netz hält die Arbeit auf).
// - Sprint-Kachel (#1277, TAtlasIdeSprint): gleicher Tracker wie der Bereich,
//   lädt nach jeder Abfrage mit (keine eigene Schleife). „meine offen“ bzw.
//   „meine erledigt“ filtern die Liste auf die Issues des Sprints („Gefiltert:
//   … · alle zeigen“ hebt den Filter auf); ohne den Bereich öffnet der Klick
//   das Board.
// - Issues in der Befehlspalette (#1270, issues.paletteSearch):
//   TAtlasIdeIssueSearch (PaletteSearch) mit dem Tracker des aktiven Projekts
//   (ActiveTarget), demselben Transport, der Vorschau, „Beginnen“ und den
//   zuletzt in der Vorschau geöffneten Issues.
// - Kommentar-Editor (#1278, issues.commentEditor): TAtlasIdeCommentService
//   (CommentAssist) mit demselben Anbieter und Transport, den zuletzt in der
//   Vorschau geöffneten Issues und dem Ordner des Projekts; Entwürfe in
//   %LOCALAPPDATA%\Atlas\issues\drafts.json, für die Vorschau und den
//   Beenden-Dialog.
// - Meldungen zu meinen Issues (#1271, issues.notify): TAtlasIdeIssueNotify
//   fragt den Tracker des aktuellen Projekts und die persönlichen
//   Verbindungen ab; Issues mit neuen Änderungen tragen bis zum Öffnen einen
//   Punkt (Zeile und Titel des Bereichs). Öffnen des Bereichs fragt sofort.
// - An Issue anhängen (#1276, issues.attach): TAtlasIdeIssueAttach mit
//   Anbieter und Transport wie die Vorschau; Befehl Atlas.IssueAttach
//   (AttachPrompt: aktuelles Issue vorgewählt, Vorschläge aus der Liste),
//   „Anhängen …“ im Fenster „Atlas-Issue“ und Zeile atlas.issue.attach im
//   Statusfeld unter dem aktuellen Issue.
// - Protokoll anonym: nur Anbieter, Anzahl, Ergebnis und Fehlerart, nie
//   Adresse, Projekt, Kennung, Titel oder Token.
// Anbieter, Transport (mit Token aus dem Anmeldespeicher) und Zugangsdialog
// kommen über Hooks aus der Komposition (Context.Hooks).
// - Tracker-Projekt (#1927): Die Klappliste wählt statt „Automatisch“ ein
//   Tracker-Projekt aus issues.projects (SelectProject, issues.welcomeProject)
//   oder „Alle Tracker-Projekte“ (#1928): dann eine Gruppe je Tracker-Projekt
//   mit höchstens issues.allProjects.perGroup Zeilen, eine Abfrage für alle
//   (nur Abfragen, die jedes Projekt kennt); eine Zeile bedient ihr Projekt
//   (Context.Selection.Focus).
// - Wieder geöffnet (#2127, issues.reopened): Marke, Grund und
//   „Weiterarbeiten“ auf dem alten Branch (Services.Reopened, Starter.Resume).
// Aufbau (#1455): TAtlasIdeIssues ist die Quelle der Kachel und hält die
// Teile Kontext (Atlas.IDE.Tracker.IssuesContext), Dienste (IssuesServices),
// Befehle (IssueCommands), Statusfeld und Titel (IssuesStatus), Abfrage
// (IssuesQuery) sowie Beginnen und Beenden (IssueStart).

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.UI.Tracker.MyIssues,
  Atlas.IDE.Tracker.WelcomeLink,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices,
  Atlas.IDE.Tracker.IssueCommands,
  Atlas.IDE.Tracker.IssuesStatus,
  Atlas.IDE.Tracker.IssuesQuery,
  Atlas.IDE.Tracker.IssueStart;

type
  TAtlasIdeIssues = class(TInterfacedObject, IAtlasIssuesSource, IAtlasIdeIssuesActions)
  public const
    /// <summary>Kennung der Kachel; dieselbe wie früher als Bereich der Willkommensseite (Layouts bleiben).
    /// </summary>
    cTileId = TAtlasIdeIssuesContext.cTileId;
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: nach „Testergebnisse“ (Mockup: rechte Spalte, im
    /// Atlas-Layout ohne festen Platz).</summary>
    cOrder = 26;
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    FCommands: TAtlasIdeIssueCommands;
    FStatus: TAtlasIdeIssuesStatus;
    FQuery: TAtlasIdeIssuesQuery;
    FStarter: TAtlasIdeIssueStart;
    FTitle: TAtlasIdeIssuesTitle;
    /// <summary>Bei „Alle“: das Projekt der Gruppe mit AIssue gilt für die folgende Aktion.</summary>
    procedure FocusIssue(const AIssue: TAtlasTrackerIssue);
  public
    /// <summary>AWelcome: Projekte der Willkommensseite und Meldungen an ihre Kacheln (gehört dem Aufrufer, lebt
    /// bis nach Stop). AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(AWelcome: TAtlasTrackerWelcomeLink; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Dienste, Statuszeile und Takt anmelden; die Hooks (Context.Hooks) vorher setzen.</summary>
    procedure Start; overload;
    /// <summary>Alles abmelden und kurz auf die Abfrage warten (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen oder anderem Projekt: Sichtbarkeit, Titel und Inhalt neu.</summary>
    procedure Refresh;
    /// <summary>Titel der Kachel: „Meine Issues · Projekt“, mit Punkt bei neuen Änderungen (#1271).</summary>
    function TileTitle: string;
    /// <summary>welcomePage.issues an?</summary>
    class function Active: Boolean; static;
    { IAtlasIdeIssuesActions }
    procedure UpdateTileInfo;
    procedure SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
    function ViewOf(const AProject: string): TAtlasIssuesView;
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
    procedure AssignProject;
    function CanAssign: Boolean;
    procedure SelectQuery(const AName: string);
    procedure EditQueries;
    procedure ClearFilter;
    procedure SelectProject(const AKey: string);
    procedure EditProjects;
    procedure Reopened(const AIssue: TAtlasTrackerIssue; AAction: TAtlasIssueReopenedAction);
    /// <summary>Projekt, Tracker, Zustand und Hooks der Komposition.</summary>
    property Context: TAtlasIdeIssuesContext read FContext;
    /// <summary>Vorschau, Board, Sprint, Zeiterfassung, Palettensuche, Meldungen, Anhängen.</summary>
    property Services: TAtlasIdeIssuesServices read FServices;
    /// <summary>Befehle (Issue anzeigen, Kennungen im Editor, Anhängen).</summary>
    property Commands: TAtlasIdeIssueCommands read FCommands;
    /// <summary>Abfrage und Zugang (Atlas.TrackerLogin).</summary>
    property Query: TAtlasIdeIssuesQuery read FQuery;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.Reopened,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.Templates,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl;

/// <summary>Fußzeile: die gesendete Abfrage, bei der Vorgabe die des Anbieters.</summary>
function QueryTextOf(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Query;
  if (Result = '') and (AProvider <> nil) and ATarget.Configured then
  begin
    Result := TAtlasTrackerTemplates.DefaultQuery(AProvider.Name, ATarget.Language);
  end;
  if (Result = '') and (AProvider <> nil) and ATarget.Configured then
  begin
    Result := AProvider.DefaultQuery;
  end;
end;

{ TAtlasIdeIssues }

constructor TAtlasIdeIssues.Create(AWelcome: TAtlasTrackerWelcomeLink; const AMessage: TProc<string>);
begin
  inherited Create;
  FContext := TAtlasIdeIssuesContext.Create(AWelcome, AMessage);
  FServices := TAtlasIdeIssuesServices.Create(FContext);
  FCommands := TAtlasIdeIssueCommands.Create(FContext, FServices);
  FStatus := TAtlasIdeIssuesStatus.Create(FContext, FServices, FCommands);
  FQuery := TAtlasIdeIssuesQuery.Create(FContext, FServices, FStatus);
  FStarter := TAtlasIdeIssueStart.Create(FContext, FServices, FStatus);
  FTitle := TAtlasIdeIssuesTitle.Create(FContext, FServices);
end;

destructor TAtlasIdeIssues.Destroy;
begin
  Stop;
  FTitle.Free;
  FStarter.Free;
  FQuery.Free;
  FStatus.Free;
  FCommands.Free;
  FServices.Free;
  FContext.Free;
  inherited;
end;

class function TAtlasIdeIssues.Active: Boolean;
begin
  Result := TAtlasIdeIssuesTargets.Active;
end;

procedure TAtlasIdeIssues.Start;
begin
  FContext.Started := True;
  // Die Teile halten den Besitzer über Actions bis Stop (Ring).
  FContext.Actions := Self;
  FStatus.Start;
  FTitle.Reset;
  FCommands.Start;
  FServices.Start;
  Refresh;
end;

procedure TAtlasIdeIssues.Stop;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  FContext.Started := False;
  FCommands.Stop;
  // Zuerst die Zeiterfassung (in Services.Stop): Sie schreibt die letzte Zeit und bucht über Sync.
  FServices.Stop;
  FContext.Filter := Default(TAtlasIssuesFilter);
  FStatus.Stop;
  // Die Abfrage bricht beim Abbruchsignal ab (Transport); kurz warten, dann sich selbst überlassen.
  FQuery.Release(True);
  FContext.Welcome := nil;
  FContext.Hooks := Default(TAtlasIdeIssuesHooks);
  // Zuletzt: löst den Ring; danach kann diese Quelle freigegeben sein.
  FContext.Actions := nil;
end;

procedure TAtlasIdeIssues.Refresh;
var
  mTitle: string;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  // Einstellungen geändert (Anbieter, Abfrage): .atlas und Ziel neu.
  FContext.ForgetTargets;
  FServices.Refresh;
  mTitle := FTitle.Last;
  // Titel oder welcomePage.issues geändert: die Seite liest die Kachel neu; sonst nur der Inhalt.
  FTitle.Update;
  FStatus.Update;
  if mTitle = FTitle.Last then
  begin
    FContext.Changed;
  end;
end;

function TAtlasIdeIssues.TileTitle: string;
begin
  Result := FTitle.Text;
end;

procedure TAtlasIdeIssues.UpdateTileInfo;
begin
  FTitle.Update;
end;

procedure TAtlasIdeIssues.SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
begin
  FCommands.SetFilter(ACaption, AIssues);
end;

function TAtlasIdeIssues.ViewOf(const AProject: string): TAtlasIssuesView;
var
  mCached: TAtlasIssuesCachedTarget;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
begin
  Result := Default(TAtlasIssuesView);
  Result.Items := nil;
  if AProject = '' then
  begin
    Result.Status := TAtlasIssuesStatus.NotConfigured;
    Exit;
  end;
  mCached := FContext.CachedTargetOf(AProject);
  mTarget := mCached.Target;
  Result := TAtlasMyIssues.View(FContext.StateOf(AProject), mTarget, FContext.BranchOf(AProject));
  Result.Project := AProject;
  Result.ProjectName := FContext.ProjectName(AProject);
  Result.Connection := mCached.Connection;
  Result.CanAssign := FContext.CanAssign;
  mProvider := FContext.ProviderOf(mTarget.Provider);
  if mProvider <> nil then
  begin
    Result.Tracker := mProvider.Caption;
  end;
  Result.TrackerProject := mTarget.Project;
  Result.Queries := mCached.Queries;
  Result.QueryIndex := mCached.QueryIndex;
  Result.QueryCounts := TAtlasMyIssues.QueryCounts(FContext.StateOf(AProject), mCached.Queries);
  Result.Picker := TAtlasIdeSettings.Current.IssuesQueryPicker;
  Result.QueryText := QueryTextOf(mProvider, mTarget);
  Result.Querying := (FContext.QueryProject <> '') and SameText(FContext.QueryProject, AProject);
  Result.Starting := FContext.StartProject <> '';
  if SameText(FContext.Notice.Project, AProject) then
  begin
    Result.Notice := FContext.Notice.Text;
    Result.NoticeFailed := FContext.Notice.Failed;
  end;
  Result.Options := FServices.Options;
  Result.Options.MainBranch := TAtlasIdeVcs.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject));
  Result.VcsKind := FContext.Selection.VcsKindOf(AProject);
  // Filter der Sprint-Kachel (#1277): nur für das Projekt, in dem er gesetzt wurde.
  if (FContext.Filter.Caption <> '') and SameText(FContext.Filter.Project, AProject) then
  begin
    Result.Filter := FContext.Filter.Caption;
    Result.Items := FContext.Filter.Issues;
  end;
  Result.Unseen := FServices.UnseenOf(mTarget);
  // Wieder geöffnete Issues (#2127).
  if FServices.Reopened <> nil then
  begin
    Result.Reopened := FServices.Reopened.Marks(AProject);
  end;
end;

/// <summary>Abfragen aus AQueries, die es (nach Name) auch in AOther gibt.</summary>
function CommonQueries(const AQueries, AOther: TArray<TAtlasTrackerQuery>): TArray<TAtlasTrackerQuery>;
var
  mQuery, mOther: TAtlasTrackerQuery;
begin
  Result := nil;
  for mQuery in AQueries do
  begin
    for mOther in AOther do
    begin
      if SameText(mQuery.Name, mOther.Name) then
      begin
        Result := Result + [mQuery];
        Break;
      end;
    end;
  end;
end;

/// <summary>„Alle Tracker-Projekte“ (#1928): Gruppen aus der Ansicht ABase des gezeigten Projekts.</summary>
function AllView(AIssues: TAtlasIdeIssues; const ABase: TAtlasIssuesView): TAtlasIssuesView;
var
  mChoice: TAtlasTrackerChoice;
  mGroup: TAtlasIssuesView;
  mPerGroup, mIndex: Integer;
  mSelected: string;
begin
  Result := ABase;
  Result.Items := nil;
  Result.Unseen := nil;
  Result.Groups := nil;
  // Der Filter der Sprint-Kachel gilt nur für ein Board.
  Result.Filter := '';
  Result.Querying := False;
  Result.Status := TAtlasIssuesStatus.NotConfigured;
  mSelected := '';
  if (ABase.QueryIndex >= 0) and (ABase.QueryIndex <= High(ABase.Queries)) then
  begin
    mSelected := ABase.Queries[ABase.QueryIndex].Name;
  end;
  mPerGroup := TAtlasIdeSettings.Current.IssuesAllProjectsPerGroup;
  for mChoice in AIssues.Context.Selection.Choices do
  begin
    mGroup := AIssues.ViewOf(mChoice.Match);
    TAtlasMyIssues.AddGroup(Result, mChoice.Caption, mChoice.Match, mGroup, mPerGroup);
    Result.Querying := Result.Querying or mGroup.Querying;
    Result.Status := TAtlasIssuesStatus.Ready;
    // Eine Abfrage für alle: nur Abfragen, die jedes Tracker-Projekt kennt.
    Result.Queries := CommonQueries(Result.Queries, mGroup.Queries);
  end;
  Result.QueryCounts := nil;
  Result.QueryIndex := -1;
  for mIndex := 0 to High(Result.Queries) do
  begin
    if SameText(Result.Queries[mIndex].Name, mSelected) then
    begin
      Result.QueryIndex := mIndex;
    end;
  end;
end;

procedure TAtlasIdeIssues.FocusIssue(const AIssue: TAtlasTrackerIssue);
var
  mView: TAtlasIssuesView;
  mIndex, mGroup: Integer;
begin
  if not FContext.Selection.AllMode then
  begin
    Exit;
  end;
  mView := View;
  for mIndex := 0 to High(mView.Items) do
  begin
    mGroup := TAtlasMyIssues.GroupOf(mView, mIndex);
    // Kennung und Titel: „#12“ kann es in zwei Repositorys geben.
    if SameText(mView.Items[mIndex].Key, AIssue.Key) and (mView.Items[mIndex].Title = AIssue.Title) and
      (mGroup >= 0) then
    begin
      FContext.Selection.Focus(mView.Groups[mGroup].Project);
      Exit;
    end;
  end;
end;

procedure TAtlasIdeIssues.SelectProject(const AKey: string);
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    begin
      FContext.Selection.Choose(AKey);
      FQuery.Fetch(False);
    end);
end;

procedure TAtlasIdeIssues.EditProjects;
begin
  // Dieselbe Seite Issue-Tracker wie „Abfragen bearbeiten …“; danach gelten Zeilen und Wahl neu.
  FQuery.EditQueries;
end;

function TAtlasIdeIssues.View: TAtlasIssuesView;
begin
  Result := Default(TAtlasIssuesView);
  Result.Items := nil;
  if not FContext.Started or not Active then
  begin
    Exit;
  end;
  Result := ViewOf(FContext.Selection.CurrentProject);
  if FContext.Selection.AllMode then
  begin
    Result := AllView(Self, Result);
  end;
  FContext.Selection.AddChoices(Result);
  // Anderes Projekt oder Punkt (#1271): Titel „Meine Issues · <Projekt>“ nachziehen, nicht mitten im Zeichnen.
  if TAtlasTrackerIssuesText.TitleText(Result.ProjectName, Length(Result.Unseen) > 0) <> FTitle.Last then
  begin
    FTitle.Queue;
  end;
end;

procedure TAtlasIdeIssues.Shown;
begin
  FQuery.Fetch(False);
  // Meldungen zu meinen Issues: beim Öffnen des Bereichs gleich nachsehen (höchstens einmal je Minute).
  if FServices.Notify <> nil then
  begin
    FServices.Notify.PollNow;
  end;
end;

procedure TAtlasIdeIssues.Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
begin
  // Bei „Alle“ nimmt „Beginnen“ das Tracker-Projekt der Zeile und dessen Arbeitskopie (#1928).
  FocusIssue(AIssue);
  FStarter.Start(AIssue, AMode);
end;

procedure TAtlasIdeIssues.Reopened(const AIssue: TAtlasTrackerIssue; AAction: TAtlasIssueReopenedAction);
var
  mReopen: TAtlasTrackerReopen;
  mProject: string;
begin
  FocusIssue(AIssue);
  mProject := FContext.Selection.CurrentProject;
  if AAction = TAtlasIssueReopenedAction.Continue then
  begin
    // Ohne Marke (schon ausgeblendet): Weiterarbeiten ohne gemerkten Branch, wie „Beginnen“.
    if (FServices.Reopened = nil) or not FServices.Reopened.Find(mProject, AIssue.Key, mReopen) then
    begin
      mReopen := Default(TAtlasTrackerReopen);
    end;
    FStarter.Resume(AIssue, mReopen.Branch);
  end
  else if FServices.Reopened = nil then
  begin
    Exit;
  end
  else if AAction = TAtlasIssueReopenedAction.Dismiss then
  begin
    FServices.Reopened.Dismiss(mProject, AIssue.Key);
  end
  else
  begin
    FServices.Reopened.ShowComment(mProject, AIssue.Key);
  end;
end;

procedure TAtlasIdeIssues.Browse(const AIssue: TAtlasTrackerIssue);
begin
  FocusIssue(AIssue);
  FCommands.Browse(AIssue);
end;

procedure TAtlasIdeIssues.Preview(const AIssue: TAtlasTrackerIssue);
begin
  FocusIssue(AIssue);
  FCommands.Preview(AIssue);
end;

procedure TAtlasIdeIssues.BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
begin
  FocusIssue(AIssue);
  FCommands.BrowsePullRequest(AIssue);
end;

procedure TAtlasIdeIssues.QueryNow;
begin
  FQuery.QueryNow;
end;

procedure TAtlasIdeIssues.Credentials;
begin
  FQuery.Credentials;
end;

function TAtlasIdeIssues.CanEnterCredentials: Boolean;
begin
  Result := FContext.CanEnterCredentials;
end;

procedure TAtlasIdeIssues.EndActive;
begin
  FStarter.EndActive;
end;

procedure TAtlasIdeIssues.AssignProject;
begin
  FQuery.AssignProject;
end;

function TAtlasIdeIssues.CanAssign: Boolean;
begin
  Result := FContext.CanAssign;
end;

procedure TAtlasIdeIssues.SelectQuery(const AName: string);
begin
  FQuery.SelectQuery(AName);
end;

procedure TAtlasIdeIssues.EditQueries;
begin
  FQuery.EditQueries;
end;

procedure TAtlasIdeIssues.ClearFilter;
begin
  FCommands.ClearFilter;
end;

end.
