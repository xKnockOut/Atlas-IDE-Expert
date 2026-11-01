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
// kommen über Hooks aus der Komposition.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Attach,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.Core.Tracker.MyIssues,
  Atlas.UI.Tracker.MyIssues,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.Attach,
  Atlas.IDE.Tracker.Notify,
  Atlas.IDE.Tracker.TimeTracking,
  Atlas.IDE.Tracker.Board,
  Atlas.IDE.Tracker.Workflow,
  Atlas.IDE.Tracker.PaletteSearch,
  Atlas.IDE.Tracker.CommentAssist,
  Atlas.IDE.Tracker.WelcomeLink,
  Atlas.IDE.Tracker.SprintTile;

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
    /// <summary>Kennung der Kachel; dieselbe wie früher als Bereich der Willkommensseite (Layouts bleiben).
    /// </summary>
    TileId = 'atlas.issues';
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
    FWelcome: TAtlasTrackerWelcomeLink;
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
    FNotify: TAtlasIdeIssueNotify;
    FNotifyRef: IInterface;
    FAttach: TAtlasIdeIssueAttach;
    FAttachRef: IInterface;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    // Checkliste des aktuellen Issues (#1273, issues.checklistStatus).
    FChecklistLine: TAtlasStatusLine;
    FChecklistLineRef: IAtlasStatusItem;
    FAttachLine: TAtlasStatusLine;
    FAttachLineRef: IAtlasStatusItem;
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
    /// <summary>Titel oder Schalter der Kachel geändert: der Willkommensseite melden.</summary>
    procedure UpdateTileInfo;
    /// <summary>UpdateTileInfo über die Nachrichtenschleife (nicht mitten im Zeichnen); hält die Quelle bis dahin.
    /// </summary>
    procedure QueueTileInfo;
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
    procedure StartNotify;
    function NotifyTargets: TArray<TAtlasTrackerTarget>;
    procedure OpenNotified(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
    function UnseenOf(const ATarget: TAtlasTrackerTarget): TArray<string>;
    procedure StartAttach;
    procedure UpdateAttachStatus(const AKey: string);
    procedure RemoveAttachStatus;
    function AttachIssues: TArray<string>;
    function ActiveTarget(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
    class function NowUtc: TDateTime; static;
    /// <summary>%LOCALAPPDATA%\Atlas\issues: Zwischenspeicher der Vorschau, Entwürfe der Kommentare (#1278) und
    /// notify.json (#1271).</summary>
    class function IssuesFolder: string; static;
  public
    /// <summary>AWelcome: Projekte der Willkommensseite und Meldungen an ihre Kacheln (gehört dem Aufrufer, lebt
    /// bis nach Stop). AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(AWelcome: TAtlasTrackerWelcomeLink; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik, Statuszeile und Takt anmelden.</summary>
    procedure Start; overload;
    /// <summary>Alles abmelden und kurz auf die Abfrage warten (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen oder anderem Projekt: Sichtbarkeit, Titel und Inhalt neu.</summary>
    procedure Refresh;
    /// <summary>Titel der Kachel: „Meine Issues · Projekt“, mit Punkt bei neuen Änderungen (#1271).</summary>
    function TileTitle: string;
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
    /// <summary>Befehl Atlas.IssueAttach (#1276): Dialog „An Issue anhängen“ für den Tracker des aktiven Projekts,
    /// das aktuelle Issue vorgewählt.</summary>
    procedure AttachPrompt;
    /// <summary>Dialog „An Issue anhängen“ für AKey bei ATarget mit AFiles vorgewählt (Absturzfall nach „Issue
    /// anlegen“, #1355).</summary>
    procedure AttachFiles(const ATarget: TAtlasTrackerTarget; const AKey: string;
      const AFiles: TArray<TAtlasAttachFile>);
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
    /// <summary>Meldungen zu meinen Issues (#1271; nil vor Start bzw. nach Stop).</summary>
    property IssueNotify: TAtlasIdeIssueNotify read FNotify;
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
  Atlas.UI.Strings,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.LinkDialogs,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Vcs.Branching,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Projects.Summaries;

type
  // Zugriff auf ReadOnly (geschützt in TCustomEdit) für das Nachrichtenfeld des Commit-Dialogs.
  TEditAccess = class(TCustomEdit);

{ TAtlasIdeIssues }

constructor TAtlasIdeIssues.Create(AWelcome: TAtlasTrackerWelcomeLink; const AMessage: TProc<string>);
begin
  inherited Create;
  FWelcome := AWelcome;
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

class function TAtlasIdeIssues.IssuesFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'issues');
end;

procedure TAtlasIdeIssues.Start;
begin
  FStarted := True;
  FWatch := TTimer.Create(nil);
  FWatch.Interval := WatchMs;
  FWatch.OnTimer := WatchTick;
  FTitle := '';
  RegisterIssueLinks;
  StartComments;
  StartSync;
  StartTime;
  // Anhängen vor der Vorschau: deren Knopf „Anhängen …“ ruft es.
  StartAttach;
  StartPreview;
  StartBoard;
  StartSprint;
  StartSearch;
  StartNotify;
  Refresh;
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
      begin
        Result := mOwner.ProviderOf(AName);
      end;
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
      begin
        Result := mFactory(AProvider, ATarget);
      end;
    end;
  mHooks.Recent :=
    function(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>
    begin
      Result := nil;
      if (mKeep <> nil) and (mOwner.FPreview <> nil) then
      begin
        Result := mOwner.FPreview.RecentIssues(ATarget);
      end;
    end;
  mHooks.Folder :=
    function: string
    begin
      Result := '';
      if mKeep <> nil then
      begin
        Result := ExtractFileDir(mOwner.CurrentProject);
      end;
    end;
  mHooks.SummaryFolder := TAtlasIdeProjectSummaries.Folder;
  // Stop löst den Ring (die Hooks halten diese Quelle).
  FComments := TAtlasIdeCommentService.Create(mHooks, IssuesFolder);
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
      begin
        Result := mFactory(AProvider, ATarget);
      end;
    end,
    procedure(AText: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.Report(AText);
      end;
    end);
  FSync.CommentAssist :=
    function(const ATarget: TAtlasTrackerTarget; const AKey, AField: string): IAtlasCommentAssist
    begin
      Result := nil;
      if (mKeep <> nil) and (mOwner.FComments <> nil) then
      begin
        Result := mOwner.FComments.Assist(ATarget, AKey, AField);
      end;
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
      begin
        Result := mOwner.ProviderOf(AName);
      end;
    end,
    procedure(AText: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.Report(AText);
      end;
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
      begin
        Result := mOwner.FTime.TimeText(AKey);
      end;
    end;
  FTime.Start;
end;

function TAtlasIdeIssues.TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
var
  mTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTimeIssue.None;
  if (AProject = '') or (AKey = '') then
  begin
    Exit;
  end;
  mTarget := TargetOf(AProject);
  Result := TAtlasTimeIssue.Create(mTarget.Provider, mTarget.Url, mTarget.Project, AKey);
end;

procedure TAtlasIdeIssues.SyncTime(const AProject, AKey: string);
begin
  if FTime <> nil then
  begin
    FTime.SetIssue(TimeIssueOf(AProject, AKey));
  end;
end;

procedure TAtlasIdeIssues.ShowTimeOpen;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FStarted and (FTime <> nil) and TAtlasIdeTrackerTime.Active then
      begin
        FTime.ShowOpen;
      end;
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
      begin
        Result := mOwner.ProviderOf(AName);
      end;
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
      begin
        Result := mFactory(AProvider, ATarget);
      end;
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
      begin
        mOwner.Start(AIssue, mOwner.Options.Start);
      end;
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
      begin
        mOwner.FOnSettings();
      end;
    end;
  mHooks.Attach :=
    procedure(ATarget: TAtlasTrackerTarget; AKey: string)
    begin
      if (mKeep <> nil) and (mOwner.FAttach <> nil) then
      begin
        mOwner.FAttach.Execute(ATarget, AKey);
      end;
    end;
  mHooks.CanAttach :=
    function: Boolean
    begin
      Result := (mKeep <> nil) and (mOwner.FAttach <> nil) and TAtlasIdeIssueAttach.Active;
    end;
  // Reiter „Entwicklung“ (#1269): Branches und Commits aus der Arbeitskopie des aktuellen Projekts.
  mHooks.Project :=
    function: string
    begin
      Result := '';
      if mKeep <> nil then
      begin
        Result := mOwner.CurrentProject;
      end;
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
      begin
        mOwner.EndActive;
      end;
    end;
  mHooks.Comment :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey, AText: string; const ADone: TAtlasTrackerSendDone)
    begin
      if (mKeep = nil) or (mOwner.FSync = nil) then
      begin
        ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
      end
      else
      begin
        mOwner.FSync.SendComment(mOwner.ProviderOf(ATarget.Provider), ATarget, AKey, AText, ADone);
      end;
    end;
  mHooks.CommentAssist :=
    function(const ATarget: TAtlasTrackerTarget; const AKey: string): IAtlasCommentAssist
    begin
      Result := nil;
      if (mKeep <> nil) and (mOwner.FComments <> nil) then
      begin
        Result := mOwner.FComments.Assist(ATarget, AKey, TAtlasCommentDrafts.FieldPreview);
      end;
    end;
  mHooks.CommentSent :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (mKeep <> nil) and (mOwner.FComments <> nil) then
      begin
        mOwner.FComments.DeleteDraft(ATarget, AKey, TAtlasCommentDrafts.FieldPreview);
      end;
    end;
  FPreview := TAtlasIdeIssuePreview.Create(mHooks, IssuesFolder);
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
      begin
        Result := mOwner.ProviderOf(AName);
      end;
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
      begin
        Result := mFactory(AProvider, ATarget);
      end;
    end;
  mHooks.Target :=
    function: TAtlasTrackerTarget
    begin
      // Tracker wie „Issue anzeigen …“: aktives Projekt der IDE, sonst das des Bereichs.
      Result := Default(TAtlasTrackerTarget);
      if mKeep <> nil then
      begin
        mOwner.ActiveTarget(Result);
      end;
    end;
  mHooks.Preview :=
    procedure(ATarget: TAtlasTrackerTarget; AKey: string)
    begin
      if (mKeep <> nil) and (mOwner.FPreview <> nil) and TAtlasIdeIssuePreview.Active then
      begin
        mOwner.FPreview.Show(ATarget, AKey);
      end;
    end;
  mHooks.Start :=
    procedure(AIssue: TAtlasTrackerIssue)
    begin
      if mKeep <> nil then
      begin
        mOwner.Start(AIssue, mOwner.Options.Start);
      end;
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
      begin
        Result := mOwner.ActiveKey;
      end;
    end;
  mHooks.Assign :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string; const ADone: TAtlasTrackerSendDone)
    var
      mChange: TAtlasTrackerWrite;
    begin
      if (mKeep = nil) or (mOwner.FSync = nil) then
      begin
        ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
        Exit;
      end;
      // Derselbe Schreibweg wie „Beginnen“ (#1266), mit dem Benutzerfeld der Verbindung.
      mChange := TAtlasTrackerWrite.Empty;
      mChange.AssigneeField := TAtlasIdeTrackerSync.Options(ATarget).AssigneeField;
      mChange.Assign := TAtlasTrackerAssign.Me;
      mOwner.FSync.Apply(mOwner.ProviderOf(ATarget.Provider), ATarget, AKey, mChange, ADone);
    end;
  mHooks.Message :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.Report(AText);
      end;
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
      begin
        Result := mOwner.ProviderOf(AName);
      end;
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
      begin
        Result := mFactory(AProvider, ATarget);
      end;
    end;
  mHooks.Project :=
    function: string
    begin
      Result := '';
      if mKeep <> nil then
      begin
        Result := mOwner.CurrentProject;
      end;
    end;
  mHooks.Target :=
    function(AProject: string): TAtlasTrackerTarget
    begin
      Result := TAtlasTrackerTarget.Create('', '', '', '');
      if mKeep <> nil then
      begin
        Result := mOwner.TargetOf(AProject);
      end;
    end;
  mHooks.OpenBoard :=
    procedure
    begin
      if (mKeep <> nil) and (mOwner.FBoard <> nil) then
      begin
        mOwner.FBoard.Show;
      end;
    end;
  mHooks.Filter :=
    procedure(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>)
    begin
      if mKeep <> nil then
      begin
        mOwner.SetFilter(ACaption, AIssues);
      end;
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
      begin
        mOwner.AssignProject;
      end;
    end;
  mHooks.Welcome := FWelcome;
  FSprint := TAtlasIdeSprint.Create(mHooks,
    TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'issues'));
  FSprintRef := FSprint;
  FSprint.Start;
end;

procedure TAtlasIdeIssues.SetFilter(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);
begin
  if not FStarted then
  begin
    Exit;
  end;
  // Ohne den Bereich „Meine Issues“ zeigt das Board die Karten.
  if not Active then
  begin
    if FBoard <> nil then
    begin
      FBoard.Show;
    end;
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
      begin
        Result := mOwner.ActiveTarget(ATarget);
      end;
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
      begin
        Result := mFactory(AProvider, ATarget);
      end;
    end;
  mHooks.Show :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (mKeep <> nil) and (mOwner.FPreview <> nil) then
      begin
        mOwner.FPreview.Show(ATarget, AKey);
      end;
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
      begin
        Result := mOwner.FPreview.RecentIssues(ATarget);
      end;
    end;
  mHooks.Start :=
    procedure(AIssue: TAtlasTrackerIssue)
    begin
      if mKeep <> nil then
      begin
        mOwner.Start(AIssue, mOwner.Options.Start);
      end;
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
      begin
        mOwner.Report(AText);
      end;
    end;
  FSearch := TAtlasIdeIssueSearch.Create(mHooks);
  FSearchRef := FSearch;
end;

procedure TAtlasIdeIssues.StartNotify;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mHooks: TAtlasIssueNotifyHooks;
begin
  mKeep := Self;
  mOwner := Self;
  mHooks := Default(TAtlasIssueNotifyHooks);
  mHooks.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := nil;
      if mKeep <> nil then
      begin
        Result := mOwner.ProviderOf(AName);
      end;
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
      begin
        Result := mFactory(AProvider, ATarget);
      end;
    end;
  mHooks.Targets :=
    function: TArray<TAtlasTrackerTarget>
    begin
      Result := nil;
      if mKeep <> nil then
      begin
        Result := mOwner.NotifyTargets;
      end;
    end;
  mHooks.Open :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime)
    begin
      if mKeep <> nil then
      begin
        mOwner.OpenNotified(ATarget, AKey, AAnchor);
      end;
    end;
  mHooks.Settings :=
    procedure
    begin
      if (mKeep <> nil) and Assigned(mOwner.FOnSettings) then
      begin
        mOwner.FOnSettings();
      end;
    end;
  mHooks.Changed :=
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.UpdateTileInfo;
        mOwner.Changed;
      end;
    end;
  mHooks.Updated :=
    procedure
    begin
      if mKeep = nil then
      begin
        Exit;
      end;
      // Das Board lädt nur, wenn es sichtbar ist; der Sprint lädt sofort neu.
      if mOwner.FBoard <> nil then
      begin
        mOwner.FBoard.Refresh;
      end;
      if mOwner.FSprint <> nil then
      begin
        mOwner.FSprint.IssuesFetched(True);
      end;
    end;
  FNotify := TAtlasIdeIssueNotify.Create(mHooks, IssuesFolder);
  FNotifyRef := FNotify;
  FNotify.Start;
end;

function TAtlasIdeIssues.NotifyTargets: TArray<TAtlasTrackerTarget>;
var
  mConnection: TAtlasTrackerConnection;
  mTarget: TAtlasTrackerTarget;
begin
  Result := nil;
  if not FStarted then
  begin
    Exit;
  end;
  // Der Tracker des aktuellen Projekts, dann die persönlichen Verbindungen (je Server zählt die erste).
  mTarget := TargetOf(CurrentProject);
  if mTarget.Server <> '' then
  begin
    Result := Result + [mTarget];
  end;
  for mConnection in TAtlasTrackerConnections.Read(TAtlasIdeSettings.Current.IssuesConnections) do
  begin
    mTarget := mConnection.Target;
    if mTarget.Server <> '' then
    begin
      Result := Result + [mTarget];
    end;
  end;
end;

procedure TAtlasIdeIssues.OpenNotified(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
var
  mProvider: IAtlasTrackerProvider;
  mUrl: string;
begin
  if not FStarted then
  begin
    Exit;
  end;
  // Mit issues.preview in „Atlas-Issue“ am ersten neuen Kommentar, sonst im Browser.
  if (FPreview <> nil) and TAtlasIdeIssuePreview.Active then
  begin
    FPreview.Show(ATarget, AKey, AAnchor);
    Exit;
  end;
  mProvider := ProviderOf(ATarget.Provider);
  if mProvider = nil then
  begin
    Exit;
  end;
  mUrl := mProvider.IssuePage(ATarget, AKey);
  if mUrl.StartsWith('https://', True) or mUrl.StartsWith('http://', True) then
  begin
    ShellExecute(0, 'open', PChar(mUrl), nil, nil, SW_SHOWNORMAL);
  end;
end;

function TAtlasIdeIssues.UnseenOf(const ATarget: TAtlasTrackerTarget): TArray<string>;
begin
  Result := nil;
  if FNotify <> nil then
  begin
    Result := FNotify.Unseen(ATarget);
  end;
end;

procedure TAtlasIdeIssues.StartAttach;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
  mHooks: TAtlasIssueAttachHooks;
begin
  mKeep := Self;
  mOwner := Self;
  mHooks := Default(TAtlasIssueAttachHooks);
  mHooks.Provider :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := nil;
      if mKeep <> nil then
      begin
        Result := mOwner.ProviderOf(AName);
      end;
    end;
  mHooks.Transport :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    var
      mFactory: TAtlasTrackerTransportHook;
    begin
      Result := nil;
      mFactory := mOwner.FTransportFactory;
      if (mKeep <> nil) and Assigned(mFactory) then
      begin
        Result := mFactory(AProvider, ATarget);
      end;
    end;
  mHooks.Issues :=
    function: TArray<string>
    begin
      Result := nil;
      if mKeep <> nil then
      begin
        Result := mOwner.AttachIssues;
      end;
    end;
  mHooks.Project :=
    function: string
    begin
      Result := '';
      if mKeep <> nil then
      begin
        Result := mOwner.CurrentProject;
      end;
    end;
  mHooks.Report :=
    procedure(AText: string)
    begin
      if mKeep <> nil then
      begin
        mOwner.Report(AText);
      end;
    end;
  FAttach := TAtlasIdeIssueAttach.Create(mHooks);
  FAttachRef := FAttach;
  FAttach.Start;
end;

function TAtlasIdeIssues.AttachIssues: TArray<string>;
var
  mData: TAtlasIssuesView;
  mIssue: TAtlasTrackerIssue;
begin
  // Die zuletzt abgefragte Liste aus „Meine Issues“, ohne Netz.
  Result := nil;
  if not FStarted then
  begin
    Exit;
  end;
  mData := ViewOf(CurrentProject);
  for mIssue in mData.Items do
  begin
    Result := Result + [Trim(mIssue.Key + ' ' + mIssue.Title)];
  end;
end;

procedure TAtlasIdeIssues.AttachPrompt;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mProvider: IAtlasTrackerProvider;
      mData: TAtlasIssuesView;
      mKey: string;
    begin
      if not FStarted or (FAttach = nil) or not TAtlasIdeIssueAttach.Active then
      begin
        Exit;
      end;
      mProvider := ActiveTarget(mTarget);
      if mProvider = nil then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoTracker));
        Exit;
      end;
      // Das aktuelle Issue vorwählen, wenn es zum selben Tracker gehört.
      mKey := '';
      mData := ViewOf(CurrentProject);
      if mData.Active.Active and SameText(TargetOf(CurrentProject).Provider, mTarget.Provider) then
      begin
        mKey := mData.Active.Key;
      end;
      FAttach.Execute(mTarget, mKey);
    end);
end;

procedure TAtlasIdeIssues.AttachFiles(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const AFiles: TArray<TAtlasAttachFile>);
begin
  if not FStarted or (FAttach = nil) or not TAtlasIdeIssueAttach.Active then
  begin
    Exit;
  end;
  FAttach.Execute(ATarget, AKey, AFiles);
end;

procedure TAtlasIdeIssues.UpdateAttachStatus(const AKey: string);
var
  mKeep: IAtlasIssuesSource;
  mAction: TProc;
begin
  if not TAtlasIdeIssueAttach.Active or (FAttach = nil) then
  begin
    RemoveAttachStatus;
    Exit;
  end;
  if FAttachLine = nil then
  begin
    mKeep := Self;
    // Typisierte Variable: Der Konstruktor ist überladen.
    mAction := procedure
      begin
        if mKeep <> nil then
        begin
          AttachPrompt;
        end;
      end;
    FAttachLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, TAtlasMyIssues.AttachStatusId,
      TAtlasMyIssues.AttachStatusOrder, mAction);
    FAttachLineRef := FAttachLine;
    TAtlasStatusRegistry.Default.Add(FAttachLineRef);
  end;
  FAttachLine.Update(TAtlasStrings.Fmt(TAtlasTextId.AttachStatusLine, [AKey]), TAtlasStatusState.Neutral, AKey,
    AKey, TAtlasStrings.Text(TAtlasTextId.AttachStatusHint));
end;

procedure TAtlasIdeIssues.RemoveAttachStatus;
begin
  if FAttachLine = nil then
  begin
    Exit;
  end;
  FAttachLine.Detach;
  TAtlasStatusRegistry.Default.Remove(TAtlasMyIssues.AttachStatusId);
  FAttachLine := nil;
  FAttachLineRef := nil;
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
  begin
    Exit;
  end;
  Target := TargetOf(CurrentProject);
  Provider := ProviderOf(Target.Provider);
  if Provider <> nil then
  begin
    Result := Provider.IssuePage(Target, AKey);
  end;
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
  begin
    Result := FTransportFactory(AProvider, ATarget);
  end;
end;

procedure TAtlasIdeIssues.StartIssue(const AIssue: TAtlasTrackerIssue);
begin
  if CanStartIssue then
  begin
    Start(AIssue, Options.Start);
  end;
end;

procedure TAtlasIdeIssues.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  TAtlasDocIssueLinks.Clear;
  // Zuerst die Zeiterfassung: Sie schreibt die letzte Zeit und bucht über FSync.
  if FTime <> nil then
  begin
    FTime.Stop;
  end;
  FTime := nil;
  FTimeRef := nil;
  FOnTimeStatus := nil;
  if FSync <> nil then
  begin
    FSync.Stop;
  end;
  // Die Hooks der Vorschau und des Boards halten diese Quelle: Stop löst den Ring.
  if FPreview <> nil then
  begin
    FPreview.Stop;
  end;
  FPreview := nil;
  FPreviewRef := nil;
  if FBoard <> nil then
  begin
    FBoard.Stop;
  end;
  FBoard := nil;
  FBoardRef := nil;
  if FSprint <> nil then
  begin
    FSprint.Stop;
  end;
  FSprint := nil;
  FSprintRef := nil;
  FFilterIssues := nil;
  FreeAndNil(FSync);
  // Ebenso die Palettensuche (ihre Hooks halten diese Quelle).
  if FSearch <> nil then
  begin
    FSearch.Stop;
  end;
  FSearch := nil;
  FSearchRef := nil;
  // Nach der Vorschau: deren Kommentarfeld hat seinen Entwurf beim Schließen noch gesichert.
  if FComments <> nil then
  begin
    FComments.Stop;
  end;
  FComments := nil;
  FCommentsRef := nil;
  if FNotify <> nil then
  begin
    FNotify.Stop;
  end;
  FNotify := nil;
  FNotifyRef := nil;
  if FAttach <> nil then
  begin
    FAttach.Stop;
  end;
  FAttach := nil;
  FAttachRef := nil;
  FreeAndNil(FWatch);
  RemoveStatus;
  // Die Abfrage bricht beim Abbruchsignal ab (Transport); kurz warten, dann sich selbst überlassen.
  ReleaseThread(True);
  FWelcome := nil;
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

function TAtlasIdeIssues.TileTitle: string;
var
  mProject: string;
begin
  mProject := '';
  if FStarted and Active then
  begin
    mProject := CurrentProject;
  end;
  Result := TAtlasTrackerIssuesView.TitleText(ProjectName(mProject), (mProject <> '') and
    (Length(UnseenOf(TargetOf(mProject))) > 0));
end;

procedure TAtlasIdeIssues.UpdateTileInfo;
var
  mTitle: string;
begin
  if not FStarted then
  begin
    Exit;
  end;
  mTitle := TileTitle;
  // Nur nach einem Sprachwechsel, mit anderem Projekt im Titel bzw. umgeschaltetem welcomePage.issues.
  if (mTitle <> FTitle) or (FActive <> Active) then
  begin
    FTitle := mTitle;
    FActive := Active;
    if FWelcome <> nil then
    begin
      FWelcome.TileInfoChanged(TileId);
    end;
  end;
end;

procedure TAtlasIdeIssues.QueueTileInfo;
var
  mKeep: IAtlasIssuesSource;
  mOwner: TAtlasIdeIssues;
begin
  mKeep := Self;
  mOwner := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.UpdateTileInfo;
      end;
    end);
end;

procedure TAtlasIdeIssues.Refresh;
var
  Title: string;
begin
  if not FStarted then
  begin
    Exit;
  end;
  // Einstellungen geändert (Anbieter, Abfrage): .atlas und Ziel neu.
  FTargets.Clear;
  // issues.syncState: Kommentarfeld und „Beenden …“ der Vorschau.
  if FPreview <> nil then
  begin
    FPreview.UpdateWrite;
  end;
  // issues.board aus: Fenster „Atlas-Board“ zu.
  if FBoard <> nil then
  begin
    FBoard.UpdateSettings;
  end;
  // welcomePage.sprint, issues.sprint.*, anderes Projekt.
  if FSprint <> nil then
  begin
    FSprint.Refresh;
  end;
  // issues.notify umgeschaltet, Abstand oder Umfang geändert.
  if FNotify <> nil then
  begin
    FNotify.Refresh;
  end;
  Title := FTitle;
  // Titel oder welcomePage.issues geändert: die Seite liest die Kachel neu; sonst nur der Inhalt.
  UpdateTileInfo;
  UpdateStatus;
  if Title = FTitle then
  begin
    Changed;
  end;
end;

procedure TAtlasIdeIssues.Changed;
begin
  if FStarted and (FWelcome <> nil) then
  begin
    FWelcome.TileChanged(TileId);
  end;
end;

procedure TAtlasIdeIssues.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

function TAtlasIdeIssues.CurrentProject: string;
var
  mProjects: TArray<TAtlasWelcomeProject>;
  mProject: TAtlasWelcomeProject;
  mActive: string;
begin
  Result := '';
  if not FStarted or (FWelcome = nil) then
  begin
    Exit;
  end;
  Result := FWelcome.Selected;
  if Result <> '' then
  begin
    Exit;
  end;
  mProjects := FWelcome.Projects;
  mActive := '';
  try
    mActive := TAtlasIdeTeamFile.ActiveProject;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
  if mActive <> '' then
  begin
    mActive := TAtlasIdeProjectSummaries.ProjectFileOf(mActive);
    for mProject in mProjects do
    begin
      if TAtlasProjectSummaries.NormalizedPath(mProject.Project) = TAtlasProjectSummaries.NormalizedPath(mActive) then
      begin
        Exit(mProject.Project);
      end;
    end;
    Exit(mActive);
  end;
  if Length(mProjects) > 0 then
  begin
    Result := mProjects[0].Project;
  end;
end;

function TAtlasIdeIssues.ProjectName(const AProject: string): string;
begin
  Result := '';
  if FWelcome <> nil then
  begin
    Result := FWelcome.NameOf(AProject);
  end;
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
  begin
    Exit;
  end;
  // .atlas nicht bei jedem Zeichnen lesen.
  mKey := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FTargets.TryGetValue(mKey, Result) and (GetTickCount64 - Result.Tick < TargetCacheMs) then
  begin
    Exit;
  end;
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
  begin
    ACached.Target.Query := ACached.Queries[ACached.QueryIndex].Query;
  end;
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
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

function TAtlasIdeIssues.ProviderOf(const AName: string): IAtlasTrackerProvider;
begin
  Result := nil;
  if Assigned(FProviderFactory) and (AName <> '') then
  begin
    Result := FProviderFactory(AName);
  end;
end;

function TAtlasIdeIssues.StateOf(const AProject: string): TAtlasIssuesState;
var
  Key: string;
  Summary: TAtlasProjectSummary;
begin
  Result := TAtlasIssuesState.Empty;
  if AProject = '' then
  begin
    Exit;
  end;
  Key := TAtlasProjectSummaries.NormalizedPath(AProject);
  if FStates.TryGetValue(Key, Result) then
  begin
    Exit;
  end;
  if TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, AProject, Summary) then
  begin
    TAtlasMyIssues.Read(Summary, Result);
  end;
  FStates.AddOrSetValue(Key, Result);
end;

procedure TAtlasIdeIssues.SaveState(const AProject: string; const AState: TAtlasIssuesState);
var
  State: TAtlasIssuesState;
begin
  if AProject = '' then
  begin
    Exit;
  end;
  State := AState;
  FStates.AddOrSetValue(TAtlasProjectSummaries.NormalizedPath(AProject), State);
  TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, AProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasMyIssues.Write(ASummary, State);
    end);
end;

function TAtlasIdeIssues.BranchOf(const AProject: string): string;
begin
  Result := '';
  if FWelcome <> nil then
  begin
    Result := FWelcome.VcsOf(AProject).Branch;
  end;
end;

function TAtlasIdeIssues.Options: TAtlasIssuesOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasIssuesOptions.Create(TAtlasMyIssues.StartOf(Settings.IssuesStart),
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
  Result := TAtlasMyIssues.View(StateOf(AProject), Target, BranchOf(AProject));
  Result.Project := AProject;
  Result.ProjectName := ProjectName(AProject);
  Result.Connection := Cached.Connection;
  Result.CanAssign := CanAssign;
  Provider := ProviderOf(Target.Provider);
  if Provider <> nil then
  begin
    Result.Tracker := Provider.Caption;
  end;
  Result.TrackerProject := Target.Project;
  Result.Queries := Cached.Queries;
  Result.QueryIndex := Cached.QueryIndex;
  Result.QueryCounts := TAtlasMyIssues.QueryCounts(StateOf(AProject), Cached.Queries);
  Result.Picker := TAtlasIdeSettings.Current.IssuesQueryPicker;
  // Fußzeile: die gesendete Abfrage, bei der Vorgabe die des Anbieters.
  Result.QueryText := Target.Query;
  if (Result.QueryText = '') and (Provider <> nil) and Target.Configured then
  begin
    Result.QueryText := TAtlasTrackerTemplates.DefaultQuery(Provider.Name, Target.Language);
  end;
  if (Result.QueryText = '') and (Provider <> nil) and Target.Configured then
  begin
    Result.QueryText := Provider.DefaultQuery;
  end;
  Result.Querying := (FQueryProject <> '') and SameText(FQueryProject, AProject);
  Result.Starting := FStartProject <> '';
  if SameText(FNoticeProject, AProject) then
  begin
    Result.Notice := FNotice;
    Result.NoticeFailed := FNoticeFailed;
  end;
  Result.Options := Options;
  Result.Options.MainBranch := TAtlasIdeVcs.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject));
  if FWelcome <> nil then
  begin
    Result.VcsKind := TAtlasMyIssues.VcsKindOf(FWelcome.VcsOf(AProject).Kind);
  end;
  // Filter der Sprint-Kachel (#1277): nur für das Projekt, in dem er gesetzt wurde.
  if (FFilter <> '') and SameText(FFilterProject, AProject) then
  begin
    Result.Filter := FFilter;
    Result.Items := FFilterIssues;
  end;
  Result.Unseen := UnseenOf(Target);
end;

function TAtlasIdeIssues.View: TAtlasIssuesView;
var
  Project: string;
begin
  Result := Default(TAtlasIssuesView);
  Result.Items := nil;
  if not FStarted or not Active then
  begin
    Exit;
  end;
  Project := CurrentProject;
  Result := ViewOf(Project);
  // Anderes Projekt oder Punkt (#1271): Titel „Meine Issues · <Projekt>“ nachziehen, nicht mitten im Zeichnen.
  if TAtlasTrackerIssuesView.TitleText(Result.ProjectName, Length(Result.Unseen) > 0) <> FTitle then
  begin
    QueueTileInfo;
  end;
end;

procedure TAtlasIdeIssues.Shown;
begin
  Fetch(False);
  // Meldungen zu meinen Issues: beim Öffnen des Bereichs gleich nachsehen (höchstens einmal je Minute).
  if FNotify <> nil then
  begin
    FNotify.PollNow;
  end;
end;

class procedure TAtlasIdeIssues.Deliver(const AKeep: IAtlasIssuesSource; AOwner: TAtlasIdeIssues;
  const AProject, AQueryName: string; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
begin
  TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if AKeep <> nil then
      begin
        AOwner.Fetched(AProject, AQueryName, ATarget, ASucceeded, AIssues, AError);
      end;
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
  begin
    Exit;
  end;
  // Eine Abfrage zur Zeit; die nächste kommt beim nächsten Anzeigen.
  ReleaseThread(False);
  if FThread <> nil then
  begin
    Exit;
  end;
  Project := CurrentProject;
  mCached := CachedTargetOf(Project);
  Target := mCached.Target;
  mQueryName := '';
  if mCached.QueryIndex >= 0 then
  begin
    mQueryName := mCached.Queries[mCached.QueryIndex].Name;
  end;
  if not TAtlasMyIssues.Due(StateOf(Project), Target, NowUtc, AForce) then
  begin
    Exit;
  end;
  Provider := ProviderOf(Target.Provider);
  if Provider = nil then
  begin
    Exit;
  end;
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
        begin
          Ok := Provider.Fetch(Target, Transport, TAtlasMyIssues.FetchTimeoutMs, TAtlasMyIssues.MaxItems,
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
          Ok := False;
          Error := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Meine Issues: Abfrage beim Tracker mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      Transport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
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
  begin
    Exit;
  end;
  State := StateOf(AProject);
  TAtlasMyIssues.Recorded(State, ATarget, NowUtc, ASucceeded, AIssues, AError);
  // Trefferzahl für die Klappliste (#1262).
  if ASucceeded then
  begin
    State.SetCount(AQueryName, Length(AIssues));
  end;
  SaveState(AProject, State);
  // Anonym: Anbieter, Anzahl bzw. Fehlerart; nie Adresse, Projekt, Kennungen oder Titel.
  if ASucceeded then
  begin
    TAtlasGuard.Log(Format('Meine Issues: %s, %d Issues', [ATarget.Provider, Length(AIssues)]));
  end
  else
  begin
    TAtlasGuard.Log(Format('Meine Issues: %s nicht abgefragt (%s)', [ATarget.Provider,
      TAtlasCiBuild.ErrorKey(AError)]));
  end;
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
      begin
        TAtlasIdeIssues(Keep as TObject).Fetch(False);
      end;
    end);
  // Sprint-Kachel lädt mit „Meine Issues“ (#1277), wenn fällig.
  if FSprint <> nil then
  begin
    FSprint.IssuesFetched(False);
  end;
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
  begin
    Exit;
  end;
  // Erst prüfen, ob ein „hängt ab von“-Issue noch offen ist (#1279).
  if TAtlasIdeSettings.Current.IssuesWarnBlocked and (FPreview <> nil) then
  begin
    CheckBlocked(AIssue, AMode);
  end
  else
  begin
    StartChecked(AIssue, AMode);
  end;
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
      begin
        mOwner.Blocked(mProject, mTarget, mIssue, AMode, AKnown, ADetails);
      end;
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
  begin
    mBlockers := TAtlasTrackerLinks.WarnOnStart(TAtlasIdeSettings.Current.IssuesWarnBlocked, ADetails);
  end;
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
        begin
          FPreview.ShowLink(ATarget, mBlockers[0]);
        end;
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
  begin
    Exit;
  end;
  Project := CurrentProject;
  if Project = '' then
  begin
    Exit;
  end;
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
      begin
        Kind := Vcs.Kind;
      end;
      Plan := TAtlasMyIssues.PlanStart(Kind, Settings, Issue);
      if (Plan.Mode <> TAtlasIssueStart.Branch) or not Plan.Valid or (Vcs = nil) then
      begin
        Exit;
      end;
      if Vcs.Changes(Items) = TAtlasVcsOutcome.Ok then
      begin
        Changes := TAtlasVcsBranchPlan.LocalChanges(Items);
      end;
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
      begin
        Exit;
      end;
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
      begin
        TAtlasIdeBranching.StopAsking;
      end;
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
      begin
        Outcome := TAtlasMyIssues.Execute(TAtlasIdeVcs.ForFolder(Dir, TAtlasIdeVcs.AtLeast(VcsTimeoutMs)), Plan,
          mRequest, TAtlasIdeBranching.Progress(mRequest.Kind));
      end
      else
      begin
        Outcome := TAtlasMyIssues.Execute(TAtlasIdeVcs.ForFolder(Dir, TAtlasIdeVcs.AtLeast(VcsTimeoutMs)), Plan);
      end;
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
      begin
        Exit;
      end;
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
  begin
    Exit;
  end;
  if TAtlasCommitHook.State(AHooks) = TAtlasCommitHookState.Own then
  begin
    AState.Hook := TAtlasMyIssues.HookYes;
    Exit;
  end;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHookPrompt, [sLineBreak + sLineBreak]), mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then
  begin
    AState.Hook := TAtlasMyIssues.HookNo;
    Exit;
  end;
  if TAtlasCommitHook.State(AHooks) = TAtlasCommitHookState.Foreign then
  begin
    AState.Hook := TAtlasMyIssues.HookForeign;
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHookForeign));
    Exit;
  end;
  if TAtlasCommitHook.Install(AHooks) then
  begin
    AState.Hook := TAtlasMyIssues.HookYes;
    TAtlasGuard.Log('Meine Issues: Git-Hook prepare-commit-msg angelegt');
  end
  else
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHookFailed));
  end;
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
  TAtlasGuard.Log(Format('Meine Issues: Beginnen %s, %s (%s)', [TAtlasMyIssues.StartName(APlan.Mode),
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
        begin
          Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderTaken, [AResult.Folder]));
        end
        else if Length(AResult.Steps) > 0 then
        begin
          Report(TAtlasIdeBranching.FailureText(APlan.Kind, AResult.Steps, AResult.Run));
        end
        else
        begin
          Report(FNotice);
        end;
        Changed;
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Mode := TAtlasIssueStart.Branch;
  if AResult.Outcome = TAtlasIssueStartOutcome.Remembered then
  begin
    Mode := TAtlasIssueStart.Remember;
  end;
  // worktree (#1289): Das Issue gilt für das Projekt im neuen Ordner; die bisherige Arbeitskopie bleibt.
  mProject := AProject;
  mOpen := AProject;
  if AResult.Folder <> '' then
  begin
    mProject := TAtlasVcsBranchPlan.ProjectInFolder(AProject, AResult.WorkingRoot, AResult.Folder);
    if mProject = '' then
    begin
      mProject := AProject;
    end;
    mOpen := TAtlasIdeBranching.WorktreeProject(AProject, AResult.WorkingRoot, AResult.Folder);
  end;
  State := StateOf(mProject);
  TAtlasMyIssues.Started(State, AIssue, Mode, AResult.Branch, NowUtc);
  if AResult.GitDir <> '' then
  begin
    State.GitDir := AResult.GitDir;
  end;
  // Git-Hook für das Präfix: nur mit Muster und nach Zustimmung.
  if (APlan.Prefix <> '') and (AResult.Hooks <> '') then
  begin
    AskHook(mProject, State, AResult.Hooks);
  end;
  SaveState(mProject, State);
  case AResult.Outcome of
    TAtlasIssueStartOutcome.Started:
      if AResult.Folder <> '' then
      begin
        Notice := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchWorktreeCreated, [AResult.Branch, AResult.Base,
          AResult.Folder]);
      end
      else
      begin
        Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesCreated, [AResult.Branch, AResult.Base]);
      end;
    TAtlasIssueStartOutcome.Switched:
      Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesSwitched, [AResult.Branch]);
  else
    if APlan.Prefix <> '' then
    begin
      Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesRememberedPrefix, [AIssue.Key, APlan.Prefix]);
    end
    else
    begin
      Notice := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesRemembered, [AIssue.Key]);
    end;
  end;
  SetNotice(AProject, Notice, False);
  UpdateStatus;
  // Tracker nachführen (#1266): Ergebnis als eigene Zeile, der Branch bleibt auch bei einem Fehler.
  if FSync <> nil then
  begin
    FSync.Started(ProviderOf(TargetOf(AProject).Provider), TargetOf(AProject), AIssue.Key, AResult.Branch);
  end;
  if FPreview <> nil then
  begin
    FPreview.UpdateWrite;
  end;
  if FBoard <> nil then
  begin
    FBoard.UpdateActive;
  end;
  // Branch und Änderungen neu abfragen; „Projekte“ meldet sich danach selbst.
  if (FWelcome <> nil) and (AResult.Outcome <> TAtlasIssueStartOutcome.Remembered) then
  begin
    FWelcome.Refresh(AProject);
  end;
  Changed;
  // Nur der Push danach scheiterte (#1289): der lokale Branch bleibt, die Meldung nennt den Grund.
  if AResult.PushFailed then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchPushFailed, [AResult.Branch,
      TAtlasIdeBranching.ServerState(AResult.Reason)]));
  end;
  // Danach das Projekt öffnen (ein offenes bleibt offen); im worktree nur nach Rückfrage das dortige.
  if FWelcome <> nil then
  begin
    if AResult.Folder = '' then
    begin
      FWelcome.Open(AProject);
    end
    else if TAtlasIdeBranching.OfferWorktree(AResult.Branch, AResult.Folder, mOpen) then
    begin
      FWelcome.Open(mOpen);
    end;
  end;
  // SVN „frisch auschecken“ (#1290): die alte Arbeitskopie bleibt; dieselbe Gruppe im neuen Ordner anbieten.
  if AResult.CheckoutFolder <> '' then
  begin
    TAtlasIdeBranching.OfferOpen(AProject, AResult.WorkingRoot, AResult.CheckoutFolder);
  end;
  // Externals festgeschrieben bzw. mitverzweigt und umgeschaltet (#1291): Index neu.
  if AResult.IndexRebuild then
  begin
    TAtlasIdeBranching.RebuildIndex;
  end;
end;

procedure TAtlasIdeIssues.SyncPrefix(const AProject: string);
var
  State: TAtlasIssuesState;
  Active_: TAtlasActiveIssue;
  Target: TAtlasTrackerTarget;
  Prefix: string;
begin
  if AProject = '' then
  begin
    Exit;
  end;
  State := StateOf(AProject);
  if (State.GitDir = '') or (State.Hook <> TAtlasMyIssues.HookYes) or not DirectoryExists(State.GitDir) then
  begin
    Exit;
  end;
  Target := TargetOf(AProject);
  Active_ := TAtlasMyIssues.Effective(State, Target.Provider, Target.Project, BranchOf(AProject));
  Prefix := TAtlasMyIssues.CommitPrefix(Active_, Options.CommitPattern);
  if (Prefix <> '') and not FPrefixDirs.Contains(State.GitDir) then
  begin
    FPrefixDirs.Add(State.GitDir);
  end;
  if TAtlasCommitHook.ReadPrefix(State.GitDir) = Prefix then
  begin
    Exit;
  end;
  if not TAtlasCommitHook.WritePrefix(State.GitDir, Prefix) then
  begin
    TAtlasGuard.Log('Meine Issues: Präfix-Datei für den Git-Hook nicht geschrieben');
  end;
end;

procedure TAtlasIdeIssues.ClearPrefixes;
var
  Dir: string;
begin
  // Bereich abgeschaltet: Ohne aktuelles Issue soll der Hook auch außerhalb der IDE nichts mehr voranstellen.
  for Dir in FPrefixDirs do
  begin
    if not TAtlasCommitHook.WritePrefix(Dir, '') then
    begin
      TAtlasGuard.Log('Meine Issues: Präfix-Datei für den Git-Hook nicht gelöscht');
    end;
  end;
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
    begin
      ClearPrefixes;
    end;
    if FWatch <> nil then
    begin
      FWatch.Enabled := False;
    end;
    Exit;
  end;
  if FWatch <> nil then
  begin
    FWatch.Enabled := True;
  end;
  Project := CurrentProject;
  Data := ViewOf(Project);
  FPrefix := TAtlasMyIssues.CommitPrefix(Data.Active, Options.CommitPattern);
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
        begin
          EndActive;
        end;
      end;
    FLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, TAtlasMyIssues.StatusId,
      TAtlasMyIssues.StatusOrder, Action);
    FLineRef := FLine;
    TAtlasStatusRegistry.Default.Add(FLineRef);
  end;
  Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStatusLine, [Trim(Data.Active.Key + ' ' + Data.Active.Title)]);
  FLine.Update(Text, TAtlasStatusState.Neutral, Data.Active.Key, TAtlasTrackerIssuesView.TileText(Data),
    TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStatusHint));
  UpdateChecklistStatus(Project, Data.Active.Key);
  UpdateAttachStatus(Data.Active.Key);
end;

procedure TAtlasIdeIssues.RemoveStatus;
begin
  RemoveChecklistStatus;
  RemoveAttachStatus;
  if FLine = nil then
  begin
    Exit;
  end;
  FLine.Detach;
  TAtlasStatusRegistry.Default.Remove(TAtlasMyIssues.StatusId);
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
        begin
          ChecklistClicked;
        end;
      end;
    FChecklistLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, TAtlasMyIssues.ChecklistStatusId,
      TAtlasMyIssues.ChecklistStatusOrder, mAction);
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
  begin
    Exit;
  end;
  FChecklistLine.Detach;
  TAtlasStatusRegistry.Default.Remove(TAtlasMyIssues.ChecklistStatusId);
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
      begin
        Exit;
      end;
      mData := ViewOf(CurrentProject);
      if not mData.Active.Active or (Trim(mData.Active.Key) = '') then
      begin
        Exit;
      end;
      // In der Vorschau an der Liste; ist sie aus, im Browser.
      if (FPreview <> nil) and TAtlasIdeIssuePreview.Active then
      begin
        FPreview.ShowChecklist(TargetOf(CurrentProject), mData.Active.Key);
      end
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
      begin
        UpdateStatus;
      end;
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
    begin
      Continue;
    end;
    if (Child is TCustomMemo) and Child.Enabled and not TEditAccess(Child).ReadOnly then
    begin
      Exit(TCustomMemo(Child));
    end;
    if Child is TWinControl then
    begin
      Result := FindMessageMemo(TWinControl(Child));
      if Result <> nil then
      begin
        Exit;
      end;
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
  begin
    if not IsWindow(FFilled[Index]) then
    begin
      FFilled.Delete(Index);
    end;
  end;
  if FPrefix = '' then
  begin
    Exit;
  end;
  Form := Screen.ActiveForm;
  // Commit-Dialog der Versionsverwaltung der IDE (Git, SVN, Mercurial): am Namen der Formularklasse erkannt.
  if (Form = nil) or not (ContainsText(Form.ClassName, 'Commit') or ContainsText(Form.Name, 'Commit')) then
  begin
    Exit;
  end;
  Memo := FindMessageMemo(Form);
  if (Memo = nil) or not Memo.HandleAllocated or FFilled.Contains(Memo.Handle) then
  begin
    Exit;
  end;
  // Einmal je Dialog: Was der Benutzer danach ändert, bleibt.
  FFilled.Add(Memo.Handle);
  Text := TAtlasTrackerNaming.Prefixed(TEditAccess(Memo).Text, FPrefix);
  if Text = TEditAccess(Memo).Text then
  begin
    Exit;
  end;
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
      begin
        Exit;
      end;
      Url := Provider.IssuePage(Target, Issue.Key);
      if FNotify <> nil then
      begin
        FNotify.Seen(Target, Issue.Key);
      end;
      // Nur Web-Adressen aus der eingetragenen Adresse, nie etwas aus der Antwort des Trackers.
      if Url.StartsWith('https://', True) or Url.StartsWith('http://', True) then
      begin
        ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
      end;
    end);
end;

procedure TAtlasIdeIssues.Preview(const AIssue: TAtlasTrackerIssue);
var
  mIssue: TAtlasTrackerIssue;
begin
  mIssue := AIssue;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mTarget: TAtlasTrackerTarget;
      mAnchor: TDateTime;
    begin
      if not FStarted or (FPreview = nil) or not TAtlasIdeIssuePreview.Active then
      begin
        Exit;
      end;
      mTarget := TargetOf(CurrentProject);
      // Mit Punkt (#1271): am ersten neuen Kommentar öffnen, der Punkt verschwindet.
      mAnchor := 0;
      if FNotify <> nil then
      begin
        mAnchor := FNotify.AnchorOf(mTarget, mIssue.Key);
        FNotify.Seen(mTarget, mIssue.Key);
      end;
      FPreview.Show(mTarget, mIssue.Key, mAnchor);
    end);
end;

function TAtlasIdeIssues.ActiveTarget(out ATarget: TAtlasTrackerTarget): IAtlasTrackerProvider;
var
  mProject: string;
begin
  // Das aktive Projekt der IDE, sonst das des Bereichs; Tracker wie im Bereich (.atlas, sonst Zuordnung #1261).
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
  begin
    mProject := CurrentProject;
  end;
  ATarget := ResolveTarget(mProject).Target;
  Result := ProviderOf(ATarget.Provider);
  if ATarget.Server = '' then
  begin
    Result := nil;
  end;
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
      begin
        Exit;
      end;
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
      begin
        Exit;
      end;
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
  begin
    Exit;
  end;
  // Wie „Issue anzeigen …“: das aktive Projekt der IDE, sonst das des Bereichs.
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
  begin
    mProject := CurrentProject;
  end;
  ATarget := CachedTargetOf(mProject).Target;
  Result := ProviderOf(ATarget.Provider) <> nil;
end;

procedure TAtlasIdeIssues.ShowIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  if not FStarted or (AKey = '') then
  begin
    Exit;
  end;
  if Options.Preview then
  begin
    FPreview.Show(ATarget, AKey);
  end
  else
  begin
    BrowseIssue(ATarget, AKey);
  end;
end;

procedure TAtlasIdeIssues.BrowseIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mProvider: IAtlasTrackerProvider;
  mUrl: string;
begin
  if not FStarted or (AKey = '') then
  begin
    Exit;
  end;
  mProvider := ProviderOf(ATarget.Provider);
  if mProvider = nil then
  begin
    Exit;
  end;
  // Nur die Seite aus der eingetragenen Adresse, nie etwas aus der Antwort des Trackers.
  mUrl := mProvider.IssuePage(ATarget, AKey);
  if TAtlasIssuePreview.MayBrowse(mUrl) then
  begin
    ShellExecute(0, 'open', PChar(mUrl), nil, nil, SW_SHOWNORMAL);
  end;
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
  begin
    Exit;
  end;
  // Der Titel gehört in Branch-Namen und Präfix: aus dem Zwischenspeicher, sonst erst fragen.
  if (FPreview <> nil) and FPreview.Peek(ATarget, AKey, mDetails) then
  begin
    Start(mDetails.Issue, Options.Start);
    Exit;
  end;
  if FPreview = nil then
  begin
    Exit;
  end;
  mKeep := Self;
  mOwner := Self;
  mKey := AKey;
  FPreview.Lookup(ATarget, AKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    begin
      if (mKeep = nil) or not mOwner.CanStartIssue then
      begin
        Exit;
      end;
      if ASucceeded then
      begin
        mOwner.Start(ADetails.Issue, mOwner.Options.Start);
      end
      else
      begin
        mOwner.Report(TAtlasIssueTip.ErrorText(AError, mKey));
      end;
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
      begin
        Exit;
      end;
      Url := Provider.PullRequestPage(Target, Issue.PullRequest.Number);
      if Url.StartsWith('https://', True) or Url.StartsWith('http://', True) then
      begin
        ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
      end;
    end);
end;

procedure TAtlasIdeIssues.QueryNow;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Fetch(True);
      if FSprint <> nil then
      begin
        FSprint.IssuesFetched(True);
      end;
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
      begin
        Exit;
      end;
      Target := TargetOf(CurrentProject);
      Provider := ProviderOf(Target.Provider);
      if (Provider = nil) or (Target.Server = '') then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.TrackerLoginNoTracker));
        Exit;
      end;
      if not FOnCredentials(Provider, Target) then
      begin
        Exit;
      end;
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
      begin
        Exit;
      end;
      Provider := ActiveTarget(Target);
      if Provider = nil then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.TrackerLoginNoTracker));
        Exit;
      end;
      if FOnCredentials(Provider, Target) then
      begin
        Fetch(True);
      end;
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
  begin
    Exit;
  end;
  mState := StateOf(mProject);
  if SameText(mState.Selected, AName) then
  begin
    Exit;
  end;
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
  begin
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
      begin
        Exit;
      end;
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
      begin
        Exit;
      end;
      Project := CurrentProject;
      if Project = '' then
      begin
        Exit;
      end;
      State := StateOf(Project);
      Branch := BranchOf(Project);
      Target := TargetOf(Project);
      Current := TAtlasMyIssues.Effective(State, Target.Provider, Target.Project, Branch);
      if not Current.Active then
      begin
        Exit;
      end;
      // Tracker nachführen (#1266): Dialog statt Rückfrage; ohne issues.syncState wie bisher.
      Provider := ProviderOf(Target.Provider);
      if (FSync <> nil) and FSync.Enabled(Provider, Target) then
      begin
        EndWithTracker(Project, Branch, Current.Key, Provider, Target, State);
        Exit;
      end;
      if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesEndConfirm, [Current.Key]), mtConfirmation,
        [mbYes, mbNo], 0) <> mrYes then
      begin
        Exit;
      end;
      EndedLocally(Project, Branch, Current.Key);
    end);
end;

procedure TAtlasIdeIssues.EndedLocally(const AProject, ABranch, AKey: string);
var
  mState: TAtlasIssuesState;
begin
  if not FStarted then
  begin
    Exit;
  end;
  mState := StateOf(AProject);
  TAtlasMyIssues.Ended(mState, ABranch);
  SaveState(AProject, mState);
  // Zeiterfassung (#1267): Zeit schreiben und das Buchen anbieten (Beschreibung aus den Commits).
  if FTime <> nil then
  begin
    FTime.Ended(TimeIssueOf(AProject, AKey), ExtractFileDir(AProject), ABranch,
      TAtlasIdeSettings.Current.IssuesBranchBase);
  end;
  SetNotice(AProject, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesEnded, [AKey]), False);
  TAtlasGuard.Log('Meine Issues: aktuelles Issue beendet');
  UpdateStatus;
  if FPreview <> nil then
  begin
    FPreview.UpdateWrite;
  end;
  if FBoard <> nil then
  begin
    FBoard.UpdateActive;
  end;
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
  begin
    mPullRequest := AProvider.PullRequestPage(ATarget, mIssue.PullRequest.Number);
  end;
  FSync.EndIssue(AProvider, ATarget, TAtlasIdeTrackerEnd.Create(AKey, ABranch, ExtractFileDir(AProject),
    TAtlasIdeSettings.Current.IssuesBranchBase, mPullRequest),
    procedure(AChange: TAtlasTrackerWrite)
    begin
      if mKeep <> nil then
      begin
        mOwner.EndedLocally(mProject, mBranch, mKey);
      end;
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
  begin
    Exit;
  end;
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

end.
