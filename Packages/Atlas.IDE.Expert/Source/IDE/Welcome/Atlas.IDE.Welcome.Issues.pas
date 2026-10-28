unit Atlas.IDE.Welcome.Issues;

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
  Atlas.Core.Commands.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Welcome.Issues,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Issues,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.TimeTracking,
  Atlas.IDE.Tracker.Board,
  Atlas.IDE.Tracker.Workflow,
  Atlas.IDE.Tracker.PaletteSearch,
  Atlas.IDE.Tracker.CommentAssist,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.Sprint;

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
      /// <summary>Name der Verbindung (#1261); '' ohne Tracker.</summary>
      Connection: string;
      /// <summary>Passende Abfragen (#1262) und die gewählte; Target.Query ist deren Abfrage.</summary>
      Queries: TArray<TAtlasTrackerQuery>;
      QueryIndex: Integer;
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
    // Fenster „Atlas-Board“ (#1272).
    FBoard: TAtlasIdeBoard;
    FBoardRef: IInterface;
    // Sprint-Kachel (#1277) und ihr Filter für die Liste (nur für FFilterProject).
    FSprint: TAtlasIdeSprint;
    FSprintRef: IInterface;
    FFilter: string;
    FFilterProject: string;
    FFilterIssues: TArray<TAtlasTrackerIssue>;
    FOnAssignProject: TProc<string>;
    FOnEditQueries: TProc;
    FSync: TAtlasIdeTrackerSync;
    FTime: TAtlasIdeTrackerTime;
    FTimeRef: IInterface;
    FOnTimeStatus: TAtlasIdeTimeStatus;
    FSearch: TAtlasIdeIssueSearch;
    FSearchRef: IAtlasPaletteSource;
    FComments: TAtlasIdeCommentService;
    FCommentsRef: IInterface;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    // Checkliste des aktuellen Issues (#1273, issues.checklistStatus).
    FChecklistLine: TAtlasStatusLine;
    FChecklistLineRef: IAtlasStatusItem;
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
    /// <summary>Ziel und Verbindung für AProject (#1261), 5 s zwischengespeichert.</summary>
    function CachedTargetOf(const AProject: string): TCachedTarget;
    /// <summary>Tracker für AProject: .atlas, sonst persönliche Zuordnung, mit den passenden Abfragen (#1262);
    /// ohne Zwischenspeicher und ohne Wahl der Abfrage (Target.Query leer, QueryIndex -1).</summary>
    class function ResolveTarget(const AProject: string): TCachedTarget; static;
    /// <summary>Die gewählte Abfrage aus AState in ACached eintragen.</summary>
    class procedure ChooseQuery(var ACached: TCachedTarget; const AState: TAtlasIssuesState); static;
    function ProviderOf(const AName: string): IAtlasTrackerProvider;
    function StateOf(const AProject: string): TAtlasIssuesState;
    procedure SaveState(const AProject: string; const AState: TAtlasIssuesState);
    function BranchOf(const AProject: string): string;
    function Options: TAtlasIssuesOptions;
    function ViewOf(const AProject: string): TAtlasIssuesView;
    procedure Fetch(AForce: Boolean);
    /// <summary>Fetch(False) über die Nachrichtenschleife, z. B. nach einer Abfrage.</summary>
    procedure QueueFetch;
    procedure Fetched(const AProject, AQueryName: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
    class procedure Deliver(const AKeep: IAtlasIssuesSource; AOwner: TAtlasIdeIssues; const AProject,
      AQueryName: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError); static;
    procedure StartChecked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure CheckBlocked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure Blocked(const AProject: string; const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue;
      AMode: TAtlasIssueStart; AKnown: Boolean; const ADetails: TAtlasTrackerDetails);
    procedure Prepared(const AProject: string; const AIssue: TAtlasTrackerIssue; const APlan: TAtlasIssueStartPlan;
      AChanges: Integer; const AFacts: TAtlasVcsBranchFacts);
    /// <summary>„Beginnen“ im Hintergrund ausführen (#1288); AOfferLocal: nach gescheitertem Abruf „Vom lokalen
    /// Stand abzweigen?“ (#1289, nur nach dem Dialog).</summary>
    procedure RunStart(const AProject: string; const AIssue: TAtlasTrackerIssue; const APlan: TAtlasIssueStartPlan;
      AUseRequest: Boolean; const ARequest: TAtlasVcsBranchRequest; const AFacts: TAtlasVcsBranchFacts;
      AOfferLocal: Boolean);
    procedure Finished(const AProject: string; const AIssue: TAtlasTrackerIssue; const APlan: TAtlasIssueStartPlan;
      const AResult: TAtlasIssueStartResult);
    procedure SetNotice(const AProject, AText: string; AFailed: Boolean);
    procedure AskHook(const AProject: string; var AState: TAtlasIssuesState; const AHooks: string);
    procedure SyncPrefix(const AProject: string);
    procedure ClearPrefixes;
    procedure UpdateStatus;
    procedure RemoveStatus;
    procedure UpdateChecklistStatus(const AProject, AKey: string);
    procedure RemoveChecklistStatus;
    procedure ChecklistClicked;
    procedure WatchTick(Sender: TObject);
    procedure FillCommitDialog;
    procedure RegisterSection;
    procedure RegisterIssueLinks;
    procedure StartPreview;
    procedure StartBoard;
    procedure StartSprint;
    procedure StartSync;
    procedure StartTime;
    /// <summary>Die Uhr der Zeiterfassung auf das aktuelle Issue von AProject stellen ('' = keins).</summary>
    procedure SyncTime(const AProject, AKey: string);
    function TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
    /// <summary>Liste auf AIssues beschränken (Sprint-Kachel); ohne den Bereich öffnet es das Board.</summary>
    procedure SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
    procedure StartComments;
    /// <summary>Kennung des aktuellen Issues im Projekt des Bereichs; '' ohne.</summary>
    function ActiveKey: string;
    /// <summary>„Beenden“ ohne Tracker: Zustand, Statuszeile und Hinweis.</summary>
    procedure EndedLocally(const AProject, ABranch, AKey: string);
    /// <summary>„Beenden“ mit Dialog (#1266); beendet erst nach „Senden“.</summary>
    procedure EndWithTracker(const AProject, ABranch, AKey: string; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget; const AState: TAtlasIssuesState);
    procedure StartSearch;
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
    /// <summary>Tracker des Projekts AProject (.atlas, sonst persönliche Zuordnung, #1261) mit dem Namen der
    /// Verbindung in AConnection ('' ohne bzw. aus der .atlas); für „Issue anlegen …“ (#1268). Ohne Netz.</summary>
    class function TrackerOf(const AProject: string; out AConnection: string): TAtlasTrackerTarget; static;
    /// <summary>Anbieter zum Namen über ProviderFactory; nil ohne.</summary>
    function ProviderFor(const AName: string): IAtlasTrackerProvider;
    /// <summary>Transport mit dem Token aus dem Anmeldespeicher (TransportFactory); nil ohne Token. Auch im
    /// Hintergrund-Thread.</summary>
    function TransportFor(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget):
      IAtlasCiTransport;
    /// <summary>„gleich beginnen“ nach „Issue anlegen …“ (#1268): wie „Beginnen“ mit issues.start.</summary>
    procedure StartIssue(const AIssue: TAtlasTrackerIssue); overload;
    /// <summary>Befehl Atlas.IssueShow (#1264): Kennung abfragen und das Issue aus dem Tracker des aktiven
    /// Projekts in „Atlas-Issue“ zeigen.</summary>
    procedure ShowPreviewPrompt;
    /// <summary>Tracker für Issue-Kennungen im Editor (#1265): das aktive Projekt der IDE, sonst das des Bereichs;
    /// TargetCacheMs zwischengespeichert, ohne Netz. False vor Start und ohne Tracker.</summary>
    function CodeTarget(out ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Issue AKey zeigen: Vorschau „Atlas-Issue“ mit issues.preview, sonst im Browser.</summary>
    procedure ShowIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>Seite des Issues AKey im Browser (nur aus der eingetragenen Adresse).</summary>
    procedure BrowseIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>„Beginnen“ für AKey wie in „Meine Issues“.</summary>
    procedure StartIssue(const ATarget: TAtlasTrackerTarget; const AKey: string); overload;
    /// <summary>„Beginnen“ gerade möglich (Bereich an, kein Beginnen läuft, Projekt vorhanden)?</summary>
    function CanStartIssue: Boolean;
    /// <summary>Vorschau-Steuerung (nil vor Start bzw. nach Stop).</summary>
    property IssuePreview: TAtlasIdeIssuePreview read FPreview;
    /// <summary>Fenster „Atlas-Board“ (#1272; nil vor Start bzw. nach Stop).</summary>
    property Board: TAtlasIdeBoard read FBoard;
    /// <summary>Sprint-Kachel (#1277; nil vor Start bzw. nach Stop).</summary>
    property Sprint: TAtlasIdeSprint read FSprint;
    /// <summary>Tracker nachführen (#1266; nil vor Start bzw. nach Stop).</summary>
    property TrackerSync: TAtlasIdeTrackerSync read FSync;
    /// <summary>Zeiterfassung (#1267; nil vor Start bzw. nach Stop).</summary>
    property TimeTracking: TAtlasIdeTrackerTime read FTime;
    /// <summary>Befehl Atlas.IssueTimeOpen (#1267): offene Zeitbuchungen zeigen.</summary>
    procedure ShowTimeOpen;
    /// <summary>Zusatzfeld der Zeiterfassung im Statusfeld (#1267); vor Start setzen.</summary>
    property OnTimeStatus: TAtlasIdeTimeStatus read FOnTimeStatus write FOnTimeStatus;
    /// <summary>Quelle der Befehlspalette für Issues (#1270); nil vor Start bzw. nach Stop.</summary>
    property PaletteSearch: IAtlasPaletteSource read FSearchRef;
    property ProviderFactory: TAtlasTrackerProviderHook read FProviderFactory write FProviderFactory;
    property TransportFactory: TAtlasTrackerTransportHook read FTransportFactory write FTransportFactory;
    property OnCredentials: TAtlasTrackerCredentialsHook read FOnCredentials write FOnCredentials;
    /// <summary>Tools › Optionen › Atlas › Issue-Tracker (Knopf „Tracker-Einstellungen“ der Vorschau).</summary>
    property OnSettings: TProc read FOnSettings write FOnSettings;
    /// <summary>„zuordnen …“ (#1261): Seite Issue-Tracker mit einer Zeile für „Gilt für“ = Argument öffnen.</summary>
    property OnAssignProject: TProc<string> read FOnAssignProject write FOnAssignProject;
    /// <summary>„Abfragen bearbeiten …“ (#1262): Seite Issue-Tracker bei der Tabelle Abfragen öffnen.</summary>
    property OnEditQueries: TProc read FOnEditQueries write FOnEditQueries;
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
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.CommitHook,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Tracker.Preview,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Templates,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.LinkDialogs,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Vcs.Branching,
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
  StartComments;
  StartSync;
  StartTime;
  StartPreview;
  StartBoard;
  StartSprint;
  StartSearch;
  Refresh;
end;

function CacheFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'issues');
end;

procedure TAtlasIdeIssues.StartComments;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mHooks: TAtlasCommentAssistHooks;
begin
  mKeep := Self;
  mOwner := Self;
  mHooks := Default(TAtlasCommentAssistHooks);
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
  mHooks.Recent :=
    function(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>
    begin
      Result := nil;
      if (mKeep <> nil) and (mOwner.FPreview <> nil) then
        Result := mOwner.FPreview.RecentIssues(ATarget);
    end;
  mHooks.Folder :=
    function: string
    begin
      Result := '';
      if mKeep <> nil then
        Result := ExtractFileDir(mOwner.CurrentProject);
    end;
  mHooks.SummaryFolder := TAtlasIdeProjects.Folder;
  // Stop löst den Ring (die Hooks halten diese Quelle).
  FComments := TAtlasIdeCommentService.Create(mHooks, CacheFolder);
  FCommentsRef := FComments;
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
  FSync.CommentAssist :=
    function(const ATarget: TAtlasTrackerTarget; const AKey, AField: string): IAtlasCommentAssist
    begin
      Result := nil;
      if (mKeep <> nil) and (mOwner.FComments <> nil) then
        Result := mOwner.FComments.Assist(ATarget, AKey, AField);
    end;
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
      Result := (mKeep <> nil) and mOwner.CanStartIssue;
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
  mHooks.CommentAssist :=
    function(const ATarget: TAtlasTrackerTarget; const AKey: string): IAtlasCommentAssist
    begin
      Result := nil;
      if (mKeep <> nil) and (mOwner.FComments <> nil) then
        Result := mOwner.FComments.Assist(ATarget, AKey, TAtlasCommentDrafts.FieldPreview);
    end;
  mHooks.CommentSent :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (mKeep <> nil) and (mOwner.FComments <> nil) then
        mOwner.FComments.DeleteDraft(ATarget, AKey, TAtlasCommentDrafts.FieldPreview);
    end;
  FPreview := TAtlasIdeIssuePreview.Create(mHooks, CacheFolder);
  FPreviewRef := FPreview;
  FPreview.Start;
end;

procedure TAtlasIdeIssues.StartBoard;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mHooks: TAtlasBoardHooks;
begin
  mKeep := Self;
  mOwner := Self;
  mHooks := Default(TAtlasBoardHooks);
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
  mHooks.Target :=
    function: TAtlasTrackerTarget
    begin
      // Tracker wie „Issue anzeigen …“: aktives Projekt der IDE, sonst das des Bereichs.
      Result := Default(TAtlasTrackerTarget);
      if mKeep <> nil then
        mOwner.ActiveTarget(Result);
    end;
  mHooks.Preview :=
    procedure(ATarget: TAtlasTrackerTarget; AKey: string)
    begin
      if (mKeep <> nil) and (mOwner.FPreview <> nil) and TAtlasIdeIssuePreview.Active then
        mOwner.FPreview.Show(ATarget, AKey);
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
  mHooks.ActiveKey :=
    function: string
    begin
      Result := '';
      if mKeep <> nil then
        Result := mOwner.ActiveKey;
    end;
  mHooks.Assign :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string; const ADone: TAtlasTrackerSendDone)
    var
      mChange: TAtlasTrackerChange;
    begin
      if (mKeep = nil) or (mOwner.FSync = nil) then
      begin
        ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
        Exit;
      end;
      // Derselbe Schreibweg wie „Beginnen“ (#1266), mit dem Benutzerfeld der Verbindung.
      mChange := TAtlasTrackerChange.Empty;
      mChange.AssigneeField := TAtlasIdeTrackerSync.Options(ATarget).AssigneeField;
      mChange.Assign := TAtlasTrackerAssign.Me;
      mOwner.FSync.Apply(mOwner.ProviderOf(ATarget.Provider), ATarget, AKey, mChange, ADone);
    end;
  mHooks.Message :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
        mOwner.Report(AText);
    end;
  FBoard := TAtlasIdeBoard.Create(mHooks,
    TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'issues'));
  FBoardRef := FBoard;
  FBoard.Start;
end;

procedure TAtlasIdeIssues.StartSprint;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mHooks: TAtlasSprintHooks;
begin
  mKeep := Self;
  mOwner := Self;
  mHooks := Default(TAtlasSprintHooks);
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
  mHooks.Project :=
    function: string
    begin
      Result := '';
      if mKeep <> nil then
        Result := mOwner.CurrentProject;
    end;
  mHooks.Target :=
    function(AProject: string): TAtlasTrackerTarget
    begin
      Result := TAtlasTrackerTarget.Create('', '', '', '');
      if mKeep <> nil then
        Result := mOwner.TargetOf(AProject);
    end;
  mHooks.OpenBoard :=
    procedure
    begin
      if (mKeep <> nil) and (mOwner.FBoard <> nil) then
        mOwner.FBoard.Show;
    end;
  mHooks.Filter :=
    procedure(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>)
    begin
      if mKeep <> nil then
        mOwner.SetFilter(ACaption, AIssues);
    end;
  mHooks.CanAssign :=
    function: Boolean
    begin
      Result := (mKeep <> nil) and mOwner.CanAssign;
    end;
  mHooks.Assign :=
    procedure
    begin
      if mKeep <> nil then
        mOwner.AssignProject;
    end;
  FSprint := TAtlasIdeSprint.Create(mHooks,
    TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'issues'));
  FSprintRef := FSprint;
  FSprint.Start;
end;

procedure TAtlasIdeIssues.SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
begin
  if not FStarted then
    Exit;
  // Ohne den Bereich „Meine Issues“ zeigt das Board die Karten.
  if not Active then
  begin
    if FBoard <> nil then
      FBoard.Show;
    Exit;
  end;
  FFilter := ACaption;
  FFilterIssues := AIssues;
  FFilterProject := CurrentProject;
  Changed;
end;

procedure TAtlasIdeIssues.ClearFilter;
begin
  FFilter := '';
  FFilterIssues := nil;
  FFilterProject := '';
  Changed;
end;

procedure TAtlasIdeIssues.StartSearch;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mHooks: TAtlasIssueSearchHooks;
begin
  mKeep := Self;
  mOwner := Self;
  mHooks := Default(TAtlasIssueSearchHooks);
  mHooks.Target :=
    function(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider
    begin
      ATarget := TAtlasTrackerTarget.Create('', '', '', '');
      Result := nil;
      if (mKeep <> nil) and mOwner.FStarted then
        Result := mOwner.ActiveTarget(ATarget);
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
  mHooks.Show :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (mKeep <> nil) and (mOwner.FPreview <> nil) then
        mOwner.FPreview.Show(ATarget, AKey);
    end;
  mHooks.PreviewActive :=
    function: Boolean
    begin
      Result := (mKeep <> nil) and (mOwner.FPreview <> nil) and TAtlasIdeIssuePreview.Active;
    end;
  mHooks.Recent :=
    function(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>
    begin
      Result := nil;
      if (mKeep <> nil) and (mOwner.FPreview <> nil) then
        Result := mOwner.FPreview.RecentIssues(ATarget);
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
  mHooks.Report :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
        mOwner.Report(AText);
    end;
  FSearch := TAtlasIdeIssueSearch.Create(mHooks);
  FSearchRef := FSearch;
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

class function TAtlasIdeIssues.TrackerOf(const AProject: string; out AConnection: string): TAtlasTrackerTarget;
var
  mCached: TCachedTarget;
begin
  mCached := ResolveTarget(AProject);
  AConnection := mCached.Connection;
  Result := mCached.Target;
  // Die Abfrage gehört zu „Meine Issues“, nicht zum Anlegen.
  Result.Query := '';
end;

function TAtlasIdeIssues.ProviderFor(const AName: string): IAtlasTrackerProvider;
begin
  Result := ProviderOf(AName);
end;

function TAtlasIdeIssues.TransportFor(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
begin
  Result := nil;
  if Assigned(FTransportFactory) and (AProvider <> nil) then
    Result := FTransportFactory(AProvider, ATarget);
end;

procedure TAtlasIdeIssues.StartIssue(const AIssue: TAtlasTrackerIssue);
begin
  if CanStartIssue then
    Start(AIssue, Options.Start);
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
  // Die Hooks der Vorschau und des Boards halten diese Quelle: Stop löst den Ring.
  if FPreview <> nil then
    FPreview.Stop;
  FPreview := nil;
  FPreviewRef := nil;
  if FBoard <> nil then
    FBoard.Stop;
  FBoard := nil;
  FBoardRef := nil;
  if FSprint <> nil then
    FSprint.Stop;
  FSprint := nil;
  FSprintRef := nil;
  FFilterIssues := nil;
  FreeAndNil(FSync);
  // Ebenso die Palettensuche (ihre Hooks halten diese Quelle).
  if FSearch <> nil then
    FSearch.Stop;
  FSearch := nil;
  FSearchRef := nil;
  // Nach der Vorschau: deren Kommentarfeld hat seinen Entwurf beim Schließen noch gesichert.
  if FComments <> nil then
    FComments.Stop;
  FComments := nil;
  FCommentsRef := nil;
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
  FOnAssignProject := nil;
  FOnEditQueries := nil;
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
  // issues.board aus: Fenster „Atlas-Board“ zu.
  if FBoard <> nil then
    FBoard.UpdateSettings;
  // welcomePage.sprint, issues.sprint.*, anderes Projekt.
  if FSprint <> nil then
    FSprint.Refresh;
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
begin
  Result := CachedTargetOf(AProject).Target;
end;

function TAtlasIdeIssues.CachedTargetOf(const AProject: string): TCachedTarget;
var
  mKey: string;
begin
  Result := Default(TCachedTarget);
  Result.Target := TAtlasTrackerTarget.Create('', '', '', '');
  if AProject = '' then
    Exit;
  // .atlas nicht bei jedem Zeichnen lesen.
  mKey := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FTargets.TryGetValue(mKey, Result) and (GetTickCount64 - Result.Tick < TargetCacheMs) then
    Exit;
  Result := ResolveTarget(AProject);
  ChooseQuery(Result, StateOf(AProject));
  Result.Tick := GetTickCount64;
  FTargets.AddOrSetValue(mKey, Result);
end;

class procedure TAtlasIdeIssues.ChooseQuery(var ACached: TCachedTarget; const AState: TAtlasIssuesState);
begin
  // Ohne Klappliste gilt die erste passende Abfrage, sonst die gemerkte (falls es sie noch gibt).
  ACached.QueryIndex := TAtlasTrackerQueries.Choose(ACached.Queries, AState.Selected,
    TAtlasIdeSettings.Current.IssuesQueryPicker);
  ACached.Target.Query := '';
  if ACached.QueryIndex >= 0 then
    ACached.Target.Query := ACached.Queries[ACached.QueryIndex].Query;
end;

class function TAtlasIdeIssues.ResolveTarget(const AProject: string): TCachedTarget;
var
  mTeam: TAtlasTeamSettings;
  mSettings: TAtlasPluginSettings;
  mResolution: TAtlasTrackerResolution;
  mConnections: TArray<TAtlasTrackerConnection>;
begin
  Result := Default(TCachedTarget);
  Result.Target := TAtlasTrackerTarget.Create('', '', '', '');
  Result.Queries := nil;
  Result.QueryIndex := -1;
  if AProject = '' then
    Exit;
  try
    mTeam := TAtlasIdeTeamFile.ForProject(AProject);
    mSettings := TAtlasIdeSettings.Current;
    mConnections := TAtlasTrackerConnections.Read(mSettings.IssuesConnections);
    // .atlas vor der persönlichen Zuordnung (.dproj, geöffnete .groupproj, längster Ordner).
    mResolution := TAtlasTrackerProjects.Resolve(TAtlasTrackerTarget.Create(mTeam.Tracker.Provider,
      mTeam.Tracker.Url, mTeam.Tracker.Project, ''), TAtlasTrackerProjects.Read(mSettings.IssuesProjects),
      mConnections, AProject, TAtlasIdeFiles.GroupOfProject(AProject));
    Result.Target := TAtlasWelcomeIssues.TargetFor(mResolution, mSettings.IssuesTracker, '');
    // Sprache der Oberfläche (#1263): Vorgabe „Mir zugewiesen“ in der Sprache, die „Prüfen“ erkannt hat.
    Result.Target.Language := TAtlasTrackerConnections.LanguageOf(mConnections, Result.Target);
    if mResolution.Found then
      Result.Connection := mResolution.Connection.Name;
    Result.Queries := TAtlasTrackerQueries.Available(TAtlasTrackerQueries.Read(mSettings.IssuesQueries),
      Result.Target, Result.Connection, mConnections, TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryDefault));
  except
    // .atlas nicht lesbar: ohne Tracker.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
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
  Cached: TCachedTarget;
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
  Cached := CachedTargetOf(AProject);
  Target := Cached.Target;
  Result := TAtlasWelcomeIssues.View(StateOf(AProject), Target, BranchOf(AProject));
  Result.Project := AProject;
  Result.ProjectName := ProjectName(AProject);
  Result.Connection := Cached.Connection;
  Result.CanAssign := CanAssign;
  Provider := ProviderOf(Target.Provider);
  if Provider <> nil then
    Result.Tracker := Provider.Caption;
  Result.TrackerProject := Target.Project;
  Result.Queries := Cached.Queries;
  Result.QueryIndex := Cached.QueryIndex;
  Result.QueryCounts := TAtlasWelcomeIssues.QueryCounts(StateOf(AProject), Cached.Queries);
  Result.Picker := TAtlasIdeSettings.Current.IssuesQueryPicker;
  // Fußzeile: die gesendete Abfrage, bei der Vorgabe die des Anbieters.
  Result.QueryText := Target.Query;
  if (Result.QueryText = '') and (Provider <> nil) and Target.Configured then
    Result.QueryText := TAtlasTrackerTemplates.DefaultQuery(Provider.Name, Target.Language);
  if (Result.QueryText = '') and (Provider <> nil) and Target.Configured then
    Result.QueryText := Provider.DefaultQuery;
  Result.Querying := (FQueryProject <> '') and SameText(FQueryProject, AProject);
  Result.Starting := FStartProject <> '';
  if SameText(FNoticeProject, AProject) then
  begin
    Result.Notice := FNotice;
    Result.NoticeFailed := FNoticeFailed;
  end;
  Result.Options := Options;
  Result.Options.MainBranch := TAtlasIdeVcs.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject));
  if FProjects <> nil then
    Result.VcsKind := TAtlasWelcomeIssues.VcsKindOf(FProjects.VcsOf(AProject).Kind);
  // Filter der Sprint-Kachel (#1277): nur für das Projekt, in dem er gesetzt wurde.
  if (FFilter <> '') and SameText(FFilterProject, AProject) then
  begin
    Result.Filter := FFilter;
    Result.Items := FFilterIssues;
  end;
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
  const AProject, AQueryName: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
begin
  TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if AKeep <> nil then
        AOwner.Fetched(AProject, AQueryName, ATarget, ASucceeded, AIssues, AError);
    end);
end;

procedure TAtlasIdeIssues.Fetch(AForce: Boolean);
var
  Project, mQueryName: string;
  mCached: TCachedTarget;
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
  mCached := CachedTargetOf(Project);
  Target := mCached.Target;
  mQueryName := '';
  if mCached.QueryIndex >= 0 then
    mQueryName := mCached.Queries[mCached.QueryIndex].Name;
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
      Deliver(Keep, Owner, Project, mQueryName, Target, Ok, Issues, Error);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
  Changed;
end;

procedure TAtlasIdeIssues.Fetched(const AProject, AQueryName: string; const ATarget: TAtlasTrackerTarget;
  ASucceeded: Boolean; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
var
  State: TAtlasIssuesState;
begin
  FQueryProject := '';
  ReleaseThread(False);
  if not FStarted then
    Exit;
  State := StateOf(AProject);
  TAtlasWelcomeIssues.Recorded(State, ATarget, NowUtc, ASucceeded, AIssues, AError);
  // Trefferzahl für die Klappliste (#1262).
  if ASucceeded then
    State.SetCount(AQueryName, Length(AIssues));
  SaveState(AProject, State);
  // Anonym: Anbieter, Anzahl bzw. Fehlerart; nie Adresse, Projekt, Kennungen oder Titel.
  if ASucceeded then
    TAtlasGuard.Log(Format('Meine Issues: %s, %d Issues', [ATarget.Provider, Length(AIssues)]))
  else
    TAtlasGuard.Log(Format('Meine Issues: %s nicht abgefragt (%s)', [ATarget.Provider,
      TAtlasCiBuild.ErrorKey(AError)]));
  UpdateStatus;
  Changed;
  // Während der Abfrage eine andere Abfrage gewählt (#1262): danach deren Liste holen; sonst ist nichts fällig.
  QueueFetch;
end;

procedure TAtlasIdeIssues.QueueFetch;
var
  Keep: IAtlasIssuesSource;
begin
  // Erst nach dem Ende des Abfrage-Threads (Fetch fragt nur, wenn keiner mehr läuft).
  Keep := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Keep <> nil then
        TAtlasIdeIssues(Keep as TObject).Fetch(False);
    end);
  // Sprint-Kachel lädt mit „Meine Issues“ (#1277), wenn fällig.
  if FSprint <> nil then
    FSprint.IssuesFetched(False);
end;

procedure TAtlasIdeIssues.SetNotice(const AProject, AText: string; AFailed: Boolean);
begin
  FNoticeProject := AProject;
  FNotice := AText;
  FNoticeFailed := AFailed;
end;

procedure TAtlasIdeIssues.Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
begin
  if not FStarted or not Active or (FStartProject <> '') or (AIssue.Key = '') or (CurrentProject = '') then
    Exit;
  // Erst prüfen, ob ein „hängt ab von“-Issue noch offen ist (#1279).
  if TAtlasIdeSettings.Current.IssuesWarnBlocked and (FPreview <> nil) then
    CheckBlocked(AIssue, AMode)
  else
    StartChecked(AIssue, AMode);
end;

procedure TAtlasIdeIssues.CheckBlocked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mProject: string;
  mTarget: TAtlasTrackerTarget;
  mIssue: TAtlasTrackerIssue;
begin
  mKeep := Self;
  mOwner := Self;
  mIssue := AIssue;
  mProject := CurrentProject;
  mTarget := TargetOf(mProject);
  // Sperrt ein zweites „Beginnen“, solange die Prüfung läuft.
  FStartProject := mProject;
  SetNotice(mProject, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStarting, [mIssue.Key]), False);
  Changed;
  FPreview.CheckBlocked(mTarget, mIssue.Key,
    procedure(AKnown: Boolean; const ADetails: TAtlasTrackerDetails)
    begin
      if (mKeep <> nil) and mOwner.FStarted then
        mOwner.Blocked(mProject, mTarget, mIssue, AMode, AKnown, ADetails);
    end);
end;

procedure TAtlasIdeIssues.Blocked(const AProject: string; const ATarget: TAtlasTrackerTarget;
  const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart; AKnown: Boolean; const ADetails: TAtlasTrackerDetails);
var
  mBlockers: TArray<TAtlasTrackerLink>;
begin
  FStartProject := '';
  mBlockers := nil;
  if AKnown then
    mBlockers := TAtlasTrackerLinks.WarnOnStart(TAtlasIdeSettings.Current.IssuesWarnBlocked, ADetails);
  if Length(mBlockers) = 0 then
  begin
    StartChecked(AIssue, AMode);
    Exit;
  end;
  TAtlasGuard.Log(Format('Meine Issues: Beginnen mit %d offenen Abhängigkeiten', [Length(mBlockers)]));
  case TAtlasBlockedPrompt.Ask(mBlockers) of
    TAtlasBlockedChoice.StartAnyway:
      StartChecked(AIssue, AMode);
    TAtlasBlockedChoice.ShowBlocker:
      begin
        SetNotice(AProject, '', False);
        Changed;
        if FPreview <> nil then
          FPreview.ShowLink(ATarget, mBlockers[0]);
      end;
  else
    SetNotice(AProject, '', False);
    Changed;
  end;
end;

procedure TAtlasIdeIssues.StartChecked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
var
  Keep: IAtlasIssuesSource;
  Project, Dir: string;
  Issue: TAtlasTrackerIssue;
  Settings: TAtlasIssuesOptions;
  Plan: TAtlasIssueStartPlan;
  Changes: Integer;
  mFacts: TAtlasVcsBranchFacts;
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
  // Hauptbranch des Projekts (#1286) als Basis, wenn issues.branchBase leer ist.
  Settings.MainBranch := TAtlasIdeVcs.MainBranchOf(Project, TAtlasIdeFiles.GroupOfProject(Project));
  // SVN (#1290): Ort, Quelle, Danach und Nachricht aus vcs.branch.svn.*.
  Settings.Svn := TAtlasIdeBranching.SvnOptions(Project);
  Dir := ExtractFileDir(Project);
  Plan := Default(TAtlasIssueStartPlan);
  Changes := 0;
  mFacts := TAtlasVcsBranchFacts.Empty;
  FStartProject := Project;
  SetNotice(Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStarting, [Issue.Key]), False);
  Changed;
  // Art der Versionsverwaltung, lokale Änderungen und (fehlt der Branch noch) der Stand für den Plan (#1288) im
  // Hintergrund; Dialog und Rückfrage danach im Hauptthread.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      Vcs: IAtlasVersionControl;
      Kind: TAtlasVcsKind;
      Items: TArray<TAtlasVcsChange>;
      mBranching: IAtlasVcsBranching;
      mExists: Boolean;
    begin
      Vcs := TAtlasIdeVcs.ForFolder(Dir, TAtlasIdeVcs.AtLeast(VcsTimeoutMs));
      Kind := TAtlasVcsKind.None;
      if Vcs <> nil then
        Kind := Vcs.Kind;
      Plan := TAtlasWelcomeIssues.PlanStart(Kind, Settings, Issue);
      if (Plan.Mode <> TAtlasIssueStart.Branch) or not Plan.Valid or (Vcs = nil) then
        Exit;
      if Vcs.Changes(Items) = TAtlasVcsOutcome.Ok then
        Changes := TAtlasWelcomeIssues.LocalChanges(Items);
      // Vorhandener Branch: nur umschalten, ohne Dialog (wie bisher).
      if Supports(Vcs, IAtlasVcsBranching, mBranching) and
        (mBranching.BranchExists(Plan.Branch, Plan.Svn, mExists) = TAtlasVcsOutcome.Ok) and not mExists then
      begin
        mFacts := TAtlasVcsBranchPlan.Inspect(Vcs, Plan.Bases);
        mFacts.LocalChanges := Changes;
      end;
    end,
    procedure
    begin
      if (Keep = nil) or not FStarted then
        Exit;
      Prepared(Project, Issue, Plan, Changes, mFacts);
    end) then
  begin
    FStartProject := '';
    SetNotice(Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesNotStarted, [Issue.Key]), True);
    Changed;
  end;
end;

procedure TAtlasIdeIssues.Prepared(const AProject: string; const AIssue: TAtlasTrackerIssue;
  const APlan: TAtlasIssueStartPlan; AChanges: Integer; const AFacts: TAtlasVcsBranchFacts);
var
  Project: string;
  Plan: TAtlasIssueStartPlan;
  mRequest: TAtlasVcsBranchRequest;
  mUseRequest, mNeverAsk, mDialog, mAsked: Boolean;
  mOptions: TAtlasVcsGitBranchOptions;
begin
  Project := AProject;
  Plan := APlan;
  mUseRequest := False;
  mDialog := False;
  mAsked := False;
  mRequest := Default(TAtlasVcsBranchRequest);
  // Neuer Branch (#1288): mit vcs.branch.confirm erst der Dialog „Branch anlegen“; „Abbrechen“ ändert nichts.
  // Ohne Dialog die Vorgaben aus dem Plan und den Git-Optionen (#1289). Findet SVN ohne erkennbares Layout
  // keinen Ort (#1290), fragt der Dialog trotzdem danach, statt an einem geratenen Ort anzulegen.
  if (Plan.Mode = TAtlasIssueStart.Branch) and Plan.Valid and (AFacts.Outcome = TAtlasVcsOutcome.Ok) then
  begin
    if not TAtlasIdeSettings.Current.VcsBranchConfirm then
    begin
      mOptions := TAtlasIdeBranching.GitOptions;
      mUseRequest := TAtlasVcsBranchPlan.DefaultRequest(AFacts, Plan.Branch, Plan.Message, AIssue.Key, mOptions,
        Plan.Svn, mRequest);
      // uncommitted = ask ohne Dialog: mitnehmen, beiseitelegen oder abbrechen.
      if mUseRequest and (mRequest.Kind = TAtlasVcsKind.Git) and (mRequest.WorktreeFolder = '') and
        (AChanges > 0) and (mOptions.Uncommitted = TAtlasVcsGitUncommitted.Ask) then
      begin
        if not TAtlasIdeBranching.AskUncommitted(AChanges, Plan.Branch, mRequest.Stash) then
        begin
          FStartProject := '';
          SetNotice(Project, '', False);
          Changed;
          Exit;
        end;
        mAsked := True;
      end;
    end;
    if TAtlasIdeSettings.Current.VcsBranchConfirm or (not mUseRequest and (AFacts.Kind = TAtlasVcsKind.Svn)) then
    begin
      if not TAtlasIdeBranching.Ask(ExtractFileDir(Project), AFacts, Plan.Branch, Plan.Message, AIssue.Key, Plan.Svn,
        True, mRequest, mNeverAsk) then
      begin
        FStartProject := '';
        SetNotice(Project, '', False);
        Changed;
        Exit;
      end;
      if mNeverAsk then
        TAtlasIdeBranching.StopAsking;
      mUseRequest := True;
      mDialog := True;
      Plan.Branch := mRequest.Name;
    end;
  end;
  // Lokale Änderungen: vorher fragen (Git nimmt sie mit, wenn sie nicht kollidieren). Nicht, wenn sie schon
  // entschieden sind: im Dialog (Git), bei stash oder worktree (#1289).
  if (Plan.Mode = TAtlasIssueStart.Branch) and Plan.Valid and (AChanges > 0) and not mAsked and
    not (mDialog and (mRequest.Kind = TAtlasVcsKind.Git)) and
    not (mUseRequest and (mRequest.Stash or (mRequest.WorktreeFolder <> ''))) and
    (MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesLocalChanges, [AChanges, Plan.Branch,
    sLineBreak + sLineBreak]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    FStartProject := '';
    SetNotice(Project, '', False);
    Changed;
    Exit;
  end;
  RunStart(Project, AIssue, Plan, mUseRequest, mRequest, AFacts, mDialog);
end;

procedure TAtlasIdeIssues.RunStart(const AProject: string; const AIssue: TAtlasTrackerIssue;
  const APlan: TAtlasIssueStartPlan; AUseRequest: Boolean; const ARequest: TAtlasVcsBranchRequest;
  const AFacts: TAtlasVcsBranchFacts; AOfferLocal: Boolean);
var
  Keep: IAtlasIssuesSource;
  Project, Dir: string;
  Issue: TAtlasTrackerIssue;
  Plan: TAtlasIssueStartPlan;
  Outcome: TAtlasIssueStartResult;
  mRequest: TAtlasVcsBranchRequest;
  mFacts: TAtlasVcsBranchFacts;
  mUseRequest, mOfferLocal: Boolean;
begin
  Project := AProject;
  Issue := AIssue;
  Plan := APlan;
  mRequest := ARequest;
  mFacts := AFacts;
  mUseRequest := AUseRequest;
  mOfferLocal := AOfferLocal;
  Outcome := Default(TAtlasIssueStartResult);
  Keep := Self;
  Dir := ExtractFileDir(Project);
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mBranching: IAtlasVcsBranching;
      mHooks, mGitDir: string;
    begin
      if mUseRequest then
        Outcome := TAtlasWelcomeIssues.Execute(TAtlasIdeVcs.ForFolder(Dir, TAtlasIdeVcs.AtLeast(VcsTimeoutMs)), Plan,
          mRequest, TAtlasIdeBranching.Progress(mRequest.Kind))
      else
        Outcome := TAtlasWelcomeIssues.Execute(TAtlasIdeVcs.ForFolder(Dir, TAtlasIdeVcs.AtLeast(VcsTimeoutMs)), Plan);
      // worktree (#1289): Hook und Präfix-Datei gehören zum neuen Ordner (eigener Verwaltungsordner).
      if (Outcome.Outcome = TAtlasIssueStartOutcome.Started) and (Outcome.Folder <> '') then
      begin
        Outcome.Hooks := '';
        Outcome.GitDir := '';
        mVcs := TAtlasIdeVcs.ForFolder(Outcome.Folder, TAtlasIdeVcs.AtLeast(VcsTimeoutMs));
        if Supports(mVcs, IAtlasVcsBranching, mBranching) and
          (mBranching.HookFolders(mHooks, mGitDir) = TAtlasVcsOutcome.Ok) then
        begin
          Outcome.Hooks := mHooks;
          Outcome.GitDir := mGitDir;
        end;
      end;
    end,
    procedure
    var
      mFallback: TAtlasVcsBranchRequest;
    begin
      if (Keep = nil) or not FStarted then
        Exit;
      // Abruf gescheitert (#1289), noch nichts geändert: nach dem Dialog vom lokalen Stand, ohne erneute Frage.
      if mOfferLocal and (Outcome.Outcome = TAtlasIssueStartOutcome.Failed) and
        TAtlasIdeBranching.AskLocal(mFacts, mRequest, Outcome.Steps, Outcome.Run, mFallback) then
      begin
        RunStart(Project, Issue, Plan, True, mFallback, mFacts, False);
        Exit;
      end;
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
  mProject, mOpen: string;
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
        // Mit Plan (#1288): Schritt, Grund und was schon auf dem Server liegt; worktree-Ordner belegt (#1289).
        if AResult.FolderTaken then
          Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderTaken, [AResult.Folder]))
        else if Length(AResult.Steps) > 0 then
          Report(TAtlasIdeBranching.FailureText(APlan.Kind, AResult.Steps, AResult.Run))
        else
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
  // worktree (#1289): Das Issue gilt für das Projekt im neuen Ordner; die bisherige Arbeitskopie bleibt.
  mProject := AProject;
  mOpen := AProject;
  if AResult.Folder <> '' then
  begin
    mProject := TAtlasVcsBranchPlan.ProjectInFolder(AProject, AResult.WorkingRoot, AResult.Folder);
    if mProject = '' then
      mProject := AProject;
    mOpen := TAtlasIdeBranching.WorktreeProject(AProject, AResult.WorkingRoot, AResult.Folder);
  end;
  State := StateOf(mProject);
  TAtlasWelcomeIssues.Started(State, AIssue, Mode, AResult.Branch, NowUtc);
  if AResult.GitDir <> '' then
    State.GitDir := AResult.GitDir;
  // Git-Hook für das Präfix: nur mit Muster und nach Zustimmung.
  if (APlan.Prefix <> '') and (AResult.Hooks <> '') then
    AskHook(mProject, State, AResult.Hooks);
  SaveState(mProject, State);
  case AResult.Outcome of
    TAtlasIssueStartOutcome.Started:
      if AResult.Folder <> '' then
        Notice := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchWorktreeCreated, [AResult.Branch, AResult.Base,
          AResult.Folder])
      else
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
  if FBoard <> nil then
    FBoard.UpdateActive;
  // Branch und Änderungen neu abfragen; „Projekte“ meldet sich danach selbst.
  if (FProjects <> nil) and (AResult.Outcome <> TAtlasIssueStartOutcome.Remembered) then
    FProjects.Refresh(AProject);
  Changed;
  // Nur der Push danach scheiterte (#1289): der lokale Branch bleibt, die Meldung nennt den Grund.
  if AResult.PushFailed then
    Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchPushFailed, [AResult.Branch,
      TAtlasIdeBranching.ServerState(AResult.Reason)]));
  // Danach das Projekt öffnen (ein offenes bleibt offen); im worktree nur nach Rückfrage das dortige.
  if FProjects <> nil then
  begin
    if AResult.Folder = '' then
      FProjects.Open(AProject)
    else if TAtlasIdeBranching.OfferWorktree(AResult.Branch, AResult.Folder, mOpen) then
      FProjects.Open(mOpen);
  end;
  // SVN „frisch auschecken“ (#1290): die alte Arbeitskopie bleibt; dieselbe Gruppe im neuen Ordner anbieten.
  if AResult.CheckoutFolder <> '' then
    TAtlasIdeBranching.OfferOpen(AProject, AResult.WorkingRoot, AResult.CheckoutFolder);
  // Externals festgeschrieben bzw. mitverzweigt und umgeschaltet (#1291): Index neu.
  if AResult.IndexRebuild then
    TAtlasIdeBranching.RebuildIndex;
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
  UpdateChecklistStatus(Project, Data.Active.Key);
end;

procedure TAtlasIdeIssues.RemoveStatus;
begin
  RemoveChecklistStatus;
  if FLine = nil then
    Exit;
  FLine.Detach;
  TAtlasStatusRegistry.Default.Remove(TAtlasWelcomeIssues.StatusId);
  FLine := nil;
  FLineRef := nil;
end;

procedure TAtlasIdeIssues.UpdateChecklistStatus(const AProject, AKey: string);
var
  mTarget: TAtlasTrackerTarget;
  mProgress: TAtlasChecklistProgress;
  mText: string;
  mKeep: IAtlasIssuesSource;
  mAction: TProc;
begin
  if (FPreview = nil) or not TAtlasIdeSettings.Current.IssuesChecklistStatus or (Trim(AKey) = '') then
  begin
    RemoveChecklistStatus;
    Exit;
  end;
  // Stand aus dem Zwischenspeicher der Vorschau; fehlt er oder ist er alt, frischt ihn Prefetch im Hintergrund auf.
  mTarget := TargetOf(AProject);
  FPreview.Prefetch(mTarget, AKey);
  // Ohne Checkliste kein Feld.
  if not FPreview.ChecklistProgress(mTarget, AKey, mProgress) or not mProgress.Any then
  begin
    RemoveChecklistStatus;
    Exit;
  end;
  if FChecklistLine = nil then
  begin
    mKeep := Self;
    // Typisierte Variable: Der Konstruktor ist überladen.
    mAction := procedure
      begin
        if mKeep <> nil then
          ChecklistClicked;
      end;
    FChecklistLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, TAtlasWelcomeIssues.ChecklistStatusId,
      TAtlasWelcomeIssues.ChecklistStatusOrder, mAction);
    FChecklistLineRef := FChecklistLine;
    TAtlasStatusRegistry.Default.Add(FChecklistLineRef);
  end;
  mText := TAtlasStrings.Fmt(TAtlasTextId.IssueChecklistStatusLine, [AKey, mProgress.Text]);
  FChecklistLine.Update(mText, TAtlasStatusState.Neutral, mText, mText,
    TAtlasStrings.Fmt(TAtlasTextId.IssueChecklistProgress, [mProgress.Done, mProgress.Total]) + sLineBreak +
    TAtlasStrings.Text(TAtlasTextId.IssueChecklistStatusHint));
end;

procedure TAtlasIdeIssues.RemoveChecklistStatus;
begin
  if FChecklistLine = nil then
    Exit;
  FChecklistLine.Detach;
  TAtlasStatusRegistry.Default.Remove(TAtlasWelcomeIssues.ChecklistStatusId);
  FChecklistLine := nil;
  FChecklistLineRef := nil;
end;

procedure TAtlasIdeIssues.ChecklistClicked;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mData: TAtlasIssuesView;
      mIssue: TAtlasTrackerIssue;
    begin
      if not FStarted then
        Exit;
      mData := ViewOf(CurrentProject);
      if not mData.Active.Active or (Trim(mData.Active.Key) = '') then
        Exit;
      // In der Vorschau an der Liste; ist sie aus, im Browser.
      if (FPreview <> nil) and TAtlasIdeIssuePreview.Active then
        FPreview.ShowChecklist(TargetOf(CurrentProject), mData.Active.Key)
      else
      begin
        mIssue := Default(TAtlasTrackerIssue);
        mIssue.Key := mData.Active.Key;
        Browse(mIssue);
      end;
    end);
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
begin
  // Das aktive Projekt der IDE, sonst das des Bereichs; Tracker wie im Bereich (.atlas, sonst Zuordnung #1261).
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
    mProject := CurrentProject;
  ATarget := ResolveTarget(mProject).Target;
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

function TAtlasIdeIssues.CodeTarget(out ATarget: TAtlasTrackerTarget): Boolean;
var
  mProject: string;
begin
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  Result := False;
  if not FStarted then
    Exit;
  // Wie „Issue anzeigen …“: das aktive Projekt der IDE, sonst das des Bereichs.
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
    mProject := CurrentProject;
  ATarget := CachedTargetOf(mProject).Target;
  Result := ProviderOf(ATarget.Provider) <> nil;
end;

procedure TAtlasIdeIssues.ShowIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if not FStarted or (AKey = '') then
    Exit;
  if Options.Preview then
    FPreview.Show(ATarget, AKey)
  else
    BrowseIssue(ATarget, AKey);
end;

procedure TAtlasIdeIssues.BrowseIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mProvider: IAtlasTrackerProvider;
  mUrl: string;
begin
  if not FStarted or (AKey = '') then
    Exit;
  mProvider := ProviderOf(ATarget.Provider);
  if mProvider = nil then
    Exit;
  // Nur die Seite aus der eingetragenen Adresse, nie etwas aus der Antwort des Trackers.
  mUrl := mProvider.IssuePage(ATarget, AKey);
  if TAtlasIssuePreview.MayBrowse(mUrl) then
    ShellExecute(0, 'open', PChar(mUrl), nil, nil, SW_SHOWNORMAL);
end;

function TAtlasIdeIssues.CanStartIssue: Boolean;
begin
  Result := FStarted and Active and (FStartProject = '') and (CurrentProject <> '');
end;

procedure TAtlasIdeIssues.StartIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mDetails: TAtlasTrackerDetails;
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mKey: string;
begin
  if not CanStartIssue or (AKey = '') then
    Exit;
  // Der Titel gehört in Branch-Namen und Präfix: aus dem Zwischenspeicher, sonst erst fragen.
  if (FPreview <> nil) and FPreview.Peek(ATarget, AKey, mDetails) then
  begin
    Start(mDetails.Issue, Options.Start);
    Exit;
  end;
  if FPreview = nil then
    Exit;
  mKeep := Self;
  mOwner := Self;
  mKey := AKey;
  FPreview.Lookup(ATarget, AKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    begin
      if (mKeep = nil) or not mOwner.CanStartIssue then
        Exit;
      if ASucceeded then
        mOwner.Start(ADetails.Issue, mOwner.Options.Start)
      else
        mOwner.Report(TAtlasIssueTip.ErrorText(AError, mKey));
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
      if FSprint <> nil then
        FSprint.IssuesFetched(True);
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

function TAtlasIdeIssues.CanAssign: Boolean;
begin
  Result := FStarted and Assigned(FOnAssignProject);
end;

procedure TAtlasIdeIssues.SelectQuery(const AName: string);
var
  mProject: string;
  mState: TAtlasIssuesState;
begin
  mProject := CurrentProject;
  if not FStarted or (mProject = '') then
    Exit;
  mState := StateOf(mProject);
  if SameText(mState.Selected, AName) then
    Exit;
  // Je Projekt gemerkt; das neue Ziel (andere Abfrage) ist sofort fällig, unabhängig von DueMinutes.
  mState.Selected := AName;
  SaveState(mProject, mState);
  FTargets.Remove(TAtlasProjectSummaries.NormalizedPath(mProject));
  Changed;
  Fetch(False);
end;

procedure TAtlasIdeIssues.EditQueries;
begin
  if FStarted and Assigned(FOnEditQueries) then
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        FOnEditQueries();
        // Nach dem Dialog gelten die neuen Abfragen sofort.
        FTargets.Clear;
        Changed;
        Fetch(False);
      end);
end;

procedure TAtlasIdeIssues.AssignProject;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mProject: string;
    begin
      mProject := CurrentProject;
      if not CanAssign or (mProject = '') then
        Exit;
      // Die geöffnete .groupproj, wenn das Projekt darin ist, sonst die .dproj (wie „Aktuelles Projekt hinzufügen“).
      FOnAssignProject(TAtlasTrackerProjects.CurrentMatch(mProject, TAtlasIdeFiles.GroupOfProject(mProject)));
      // Nach dem Dialog gilt die neue Zuordnung sofort.
      FTargets.Clear;
      Changed;
      Fetch(False);
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
  if FBoard <> nil then
    FBoard.UpdateActive;
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
