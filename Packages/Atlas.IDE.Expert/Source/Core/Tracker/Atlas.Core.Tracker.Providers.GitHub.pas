unit Atlas.Core.Tracker.Providers.GitHub;

// Issue-Tracker GitHub (#765), ohne VCL und Open Tools API: Adressen der
// REST-API, Lesen der Antworten und Ablauf einer Abfrage. Das Netz kommt über
// IAtlasCiTransport von außen, damit alles hier ohne Server testbar ist.
// - Schnittstelle: github.com → https://api.github.com, GitHub Enterprise →
//   <Server>/api/v3. Das Token geht nur dorthin (ApiServer).
// - Issues: GET /search/issues?q=<Abfrage> repo:<owner/repo> is:issue
//   &per_page=<Max>&sort=updated&order=desc (Vorgabe der Abfrage
//   "assignee:@me state:open"). Einträge mit "pull_request" sind Pull
//   Requests und entfallen.
// - Pull Requests: GET /repos/<owner/repo>/pulls?state=open&per_page=50. Ein
//   PR gehört zu Issue N, wenn sein Branch N als eigenes Stück enthält
//   („feature/753-…“, wie Atlas ihn anlegt) oder Titel bzw. Beschreibung
//   „closes/fixes/resolves #N“ sagen.
// - CI-Ampel: GET /repos/<owner/repo>/commits/<sha>/check-runs; ohne Check
//   Runs der kombinierte Status /commits/<sha>/status. Höchstens MaxChecks
//   Pull Requests je Abfrage.
// - Verbindung prüfen (#1260): GET /user (angemeldeter Benutzer).
// - Vorschau (#1264): GET /repos/<owner/repo>/issues/<n> (Felder, Beschreibung,
//   Labels, Zuständige, Meilenstein, Typ), mit AComments …/comments (die
//   neuesten MaxComments; sonst nicht abgefragt) und …/timeline für Verweise
//   aus anderen Issues und Pull Requests ("cross-referenced"; im selben
//   Repository öffnen sie im Fenster, sonst im Browser). GitHub kennt keine
//   Anhangsliste: Dateien (/user-attachments/files/…) aus Beschreibung und
//   Kommentaren gelten als Anhänge und öffnen im Browser, weil das Token nur
//   an die API geht.
// - Zustand und Kommentar (#1266, IAtlasTrackerWriter): Kommentar mit POST
//   …/issues/<n>/comments, danach Labels, Zuständige und Zustand in einem
//   PATCH …/issues/<n> (Zustand = Label; das Label aus „Beginnen“ entfällt;
//   ein Erledigt-Zustand schließt das Issue mit state_reason "completed").
//   „Mir zuweisen“ fragt vorher /user. Werte für die Klapplisten: Labels
//   (…/labels) und mögliche Zuständige (…/assignees).
// - Checklisten (#1273, IAtlasTrackerDescriptions): Beschreibung ungekürzt aus
//   GET …/issues/<n> ("body"), zurück mit PATCH …/issues/<n> und {"body": …}.
// - Verknüpfungen (#1279): …/sub_issues (Unteraufgaben),
//   …/dependencies/blocked_by (hängt ab von) und …/dependencies/blocking
//   (blockiert); abgefragt nur, wenn sub_issues_summary bzw.
//   issue_dependencies_summary des Issues Einträge melden (fehlen die
//   Zusammenfassungen, wird gefragt; 404 heißt: kennt der Server nicht). Ohne
//   „blocked by“ gelten Erwähnungen wie „depends on #12“ oder „Benötigt: #12“
//   im Text (TAtlasTrackerLinks.TextDependencies); deren Zustand liest
//   …/issues/<n>, höchstens TAtlasTrackerLinks.MaxTextDependencies.
// - Unteraufgabe anlegen (#1279): POST /repos/<owner/repo>/issues, dann
//   POST …/issues/<Eltern>/sub_issues mit {"sub_issue_id": <id>};
//   Verknüpfen: POST …/issues/<n>/dependencies/blocked_by mit
//   {"issue_id": <id>} (die interne ID aus …/issues/<m>).
// - Palettensuche (#1270): GET /search/issues?q=repo:<owner/repo> is:issue
//   <Text>&per_page=<Max> ohne Sortierung (beste Treffer zuerst), ohne Pull
//   Requests und Ampeln; eine Kennung ("#42") liest Lookup direkt über
//   /repos/<owner/repo>/issues/42.
// - Benutzer für @-Erwähnungen (#1278, IAtlasTrackerPeople): die möglichen
//   Zuständigen des Repositorys (…/assignees, eine Seite), gefiltert nach
//   dem getippten Text; GitHub liefert dort keine Anzeigenamen.
// - Entwicklung (#1269): GET /repos/<owner/repo>/pulls?state=all&per_page=100
//   &sort=updated&direction=desc; zum Issue N gehören die Pull Requests, die
//   PullMentions erkennt oder die „#N“ im Titel tragen (PullRefersTo), mit
//   Zustand (offen, Entwurf, gemergt, geschlossen) und CI-Ampel wie oben,
//   höchstens MaxChecks Ampeln.
// - Änderungen (#1271): GET /notifications?since=<Stand> über alle
//   Repositories, bedingt mit If-Modified-Since (IAtlasCiConditional; 304 =
//   nichts Neues), X-Poll-Interval wird zum kleinsten Abstand. Nur Issues;
//   der Grund ("assign", "author", sonst beobachtet) entscheidet über den
//   Umfang. Je Issue …/comments?since=<Stand> (neue Kommentare) und …/events
//   (assigned, closed, reopened); ohne erkennbare Einzelheit bleibt eine
//   allgemeine Änderung. Eigene Aktionen meldet GitHub ohnehin nicht.
// - Anhängen (#1276, IAtlasTrackerAttach): GitHub nimmt über die API keine
//   Dateien an (CanUpload = False). Texte (Protokoll, Debug-Notiz,
//   Exception-Verlauf) gehen als Kommentar POST /repos/<owner/repo>/issues/
//   <n>/comments mit {"body": …}, Protokolle als Codeblock; Bilder legt die
//   IDE-Schicht in die Zwischenablage und öffnet das Issue im Browser.
// Die Zeitgrenze gilt für die ganze Abfrage; reicht sie nach der Liste nicht
// mehr für Pull Requests und Ampeln, bleiben diese unbekannt.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Internals.GitHubApi;
  Atlas.Core.Tracker.Board;
  Atlas.Core.Tracker.Attach;

type
  /// <summary>Offener Pull Request, wie ihn /pulls liefert.</summary>
  TAtlasGitHubPull = record
    Number: Integer;
    Draft: Boolean;
    Title: string;
    Body: string;
    Branch: string;
    Sha: string;
    /// <summary>"open" bzw. "closed" (#1269).</summary>
    State: string;
    /// <summary>merged_at ist gesetzt (#1269).</summary>
    Merged: Boolean;
    /// <summary>updated_at (UTC); 0 = unbekannt.</summary>
    Updated: TDateTime;
  end;

  /// <summary>Zusammenfassungen der Verknüpfungen eines Issues (#1279); -1 = unbekannt (ältere Server).</summary>
  TAtlasGitHubLinkSummary = record
    SubIssues: Integer;
    BlockedBy: Integer;
    Blocking: Integer;
  end;

  /// <summary>Eine Benachrichtigung von /notifications (#1271).</summary>
  TAtlasGitHubThread = record
    /// <summary>"owner/repo".</summary>
    Repository: string;
    Number: Integer;
    Title: string;
    /// <summary>Grund wie bei GitHub: "assign", "author", "comment", "mention", "subscribed" …</summary>
    Reason: string;
    /// <summary>UTC.</summary>
    Updated: TDateTime;
  end;

  TAtlasGitHubTracker = class(TInterfacedObject, IAtlasTrackerProvider, IAtlasTrackerWriter,
    IAtlasTrackerDescriptions, IAtlasTrackerLinkWriter, IAtlasTrackerBoards, IAtlasTrackerPeople, IAtlasTrackerAttach)
  public const
    ProviderName = 'github';
    Query = 'assignee:@me state:open';
    ApiHost = TAtlasGitHubApi.ApiHost;
    /// <summary>Höchstens so viele Pull Requests bekommen eine Ampel.</summary>
    MaxChecks = 8;
    /// <summary>Höchstens so viele offene Pull Requests werden gelesen.</summary>
    MaxPulls = 50;
    /// <summary>Einträge je Seite für Kommentare und Zeitleiste (#1264).</summary>
    MaxPageSize = 100;
  private
    /// <summary>Verknüpfungen (#1279) in der restlichen Zeit: Unteraufgaben, „blocked by“, „blocking“, sonst
    /// Abhängigkeiten aus dem Text.</summary>
    procedure LoadRelations(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AUrl: string; const ASummary: TAtlasGitHubLinkSummary; const AWatch: TStopwatch; ATimeoutMs: Integer;
      var ADetails: TAtlasTrackerDetails);
    /// <summary>Höchstens so viele Issues je Abfrage bekommen Kommentare und Ereignisse (#1271).</summary>
    MaxChangedIssues = 20;
  public
    /// <summary>Basis der REST-API ohne „/“ am Ende; '' ohne Server.</summary>
    class function ApiBase(const ATarget: TAtlasTrackerTarget): string; static;
    class function SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string; static;
    /// <summary>Suchtext, wie er an /search/issues geht (mit repo: und is:issue).</summary>
    class function SearchText(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Freitextsuche der Palette (#1270); '' ohne Server, Projekt oder Text.</summary>
    class function TextSearchUrl(const ATarget: TAtlasTrackerTarget; const AText: string; AMax: Integer): string;
      static;
    class function PullsUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function CheckRunsUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string; static;
    class function StatusUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string; static;
    /// <summary>Antwort von /search/issues; False bei ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>): Boolean; static;
    /// <summary>Antwort von /pulls; False bei ungültigem JSON.</summary>
    class function ParsePulls(const AJson: string; out APulls: TArray<TAtlasGitHubPull>): Boolean; static;
    /// <summary>Der Pull Request gehört zu Issue ANumber (Branch, „closes #N“ in Titel oder Beschreibung).
    /// </summary>
    class function PullMentions(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean; static;
    /// <summary>Reiter „Entwicklung“ (#1269): PullMentions oder „#N“ als eigenes Stück im Titel („Vorschau (#753)“).
    /// </summary>
    class function PullRefersTo(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean; static;
    /// <summary>Alle Pull Requests, zuletzt geänderte zuerst (#1269).</summary>
    class function AllPullsUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Zustand für den Reiter „Entwicklung“.</summary>
    class function PullState(const APull: TAtlasGitHubPull): TAtlasTrackerPullState; static;
    /// <summary>Antwort von /check-runs zusammengefasst: rot, sobald einer fehlschlug; gelb, solange einer läuft;
    /// sonst grün; Unknown ohne Check Runs. False bei ungültigem JSON.</summary>
    class function ParseCheckRuns(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean; static;
    /// <summary>Antwort von /status (kombinierter Status); Unknown ohne Einträge. False bei ungültigem JSON.
    /// </summary>
    class function ParseStatus(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean; static;
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    /// <summary>Adresse eines Issues in der API (ohne Anhang wie /comments); '' bei ungültiger Kennung.</summary>
    class function IssueApiUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Antwort von /issues/<n>; False bei ungültigem JSON bzw. ohne Nummer.</summary>
    class function ParseDetails(const AJson: string; out ADetails: TAtlasTrackerDetails;
      out ACommentCount: Integer): Boolean; static;
    /// <summary>Antwort von /issues/<n>/comments (älteste zuerst); False bei ungültigem JSON.</summary>
    class function ParseComments(const AJson: string; out AComments: TArray<TAtlasTrackerComment>): Boolean; static;
    /// <summary>Antwort von /issues/<n>/timeline: Verweise ("cross-referenced"); AProject entscheidet, was im
    /// Fenster öffnet. False bei ungültigem JSON.</summary>
    class function ParseTimeline(const AJson, AProject: string; out ALinks: TArray<TAtlasTrackerLink>): Boolean;
      static;
    /// <summary>Dateien in Beschreibung und Kommentaren als Anhänge (im Browser).</summary>
    class function FileAttachments(const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerAttachment>; static;
    /// <summary>AState schließt das Issue statt ein Label zu setzen (Erledigt, Done, Closed, Geschlossen, Completed,
    /// Fertig; ohne Groß-/Kleinschreibung).</summary>
    class function ClosesIssue(const AState: string): Boolean; static;
    /// <summary>Inhalt für …/comments: {"body": AText}.</summary>
    class function CommentJson(const AText: string): string; static;
    /// <summary>Labels und Zuständige aus /issues/&lt;n&gt;; False bei ungültigem JSON.</summary>
    class function ParseAssignment(const AJson: string; out ALabels, AAssignees: TArray<string>): Boolean; static;
    /// <summary>PATCH-Inhalt für AChange auf dem Stand ALabels/AAssignees; AMe = eigener Anmeldename. '' = nichts
    /// zu ändern.</summary>
    class function PatchJson(const ALabels, AAssignees: TArray<string>; const AChange: TAtlasTrackerChange;
      const AMe: string): string; static;
    /// <summary>Werte "name" (Labels) bzw. "login" (Zuständige) einer Liste; False bei ungültigem JSON.</summary>
    class function ParseNames(const AJson, AField: string; out AValues: TArray<string>): Boolean; static;
    /// <summary>Mögliche Zuständige (…/assignees) als Benutzer ohne Anzeigenamen (#1278); False bei ungültigem
    /// JSON.</summary>
    class function ParseUsers(const AJson: string; out AUsers: TArray<TAtlasTrackerUser>): Boolean; static;
    /// <summary>…/repos/&lt;owner/repo&gt;/assignees (#1266, #1278); '' ohne Server oder Projekt.</summary>
    class function AssigneesUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Fehlertext ("message") einer Antwort; '' ohne.</summary>
    class function ErrorMessage(const AJson: string): string; static;
    /// <summary>"body" aus der Antwort von /issues/<n>, ungekürzt ('' bei null); False bei ungültigem JSON (#1273).
    /// </summary>
    class function ParseBody(const AJson: string; out AText: string): Boolean; static;
    /// <summary>Inhalt des PATCH: {"body": AText}.</summary>
    class function BodyJson(const AText: string): string; static;
    /// <summary>sub_issues_summary und issue_dependencies_summary aus /issues/<n> (#1279).</summary>
    class function ParseLinkSummary(const AJson: string): TAtlasGitHubLinkSummary; static;
    /// <summary>Liste von Issues (…/sub_issues, …/dependencies/…) als Verknüpfungen der Art AKind; AProject
    /// entscheidet, was im Fenster öffnet. False bei ungültigem JSON.</summary>
    class function ParseRelated(const AJson, AProject: string; AKind: TAtlasTrackerLinkKind;
      out ALinks: TArray<TAtlasTrackerLink>): Boolean; static;
    /// <summary>ANew in ALinks übernehmen: eine Erwähnung desselben Issues wird durch die genauere Art ersetzt,
    /// dieselbe Art nicht doppelt; höchstens TAtlasTrackerDetails.MaxLinks.</summary>
    class procedure MergeLinks(var ALinks: TArray<TAtlasTrackerLink>; const ANew: TArray<TAtlasTrackerLink>); static;
    /// <summary>Interne ID ("id") aus /issues/<n> bzw. der Antwort beim Anlegen; 0 ohne.</summary>
    class function ParseIssueId(const AJson: string): Int64; static;
    /// <summary>Inhalt für POST /issues.</summary>
    class function NewIssueBody(const ATitle, ADescription: string): string; static;
    /// <summary>Inhalt {"<AName>": AId} für sub_issues bzw. blocked_by.</summary>
    class function IdBody(const AName: string; AId: Int64): string; static;
    /// <summary>ISO 8601 in UTC ("2026-10-28T10:40:49Z").</summary>
    class function IsoTime(ATime: TDateTime): string; static;
    /// <summary>Adresse der Benachrichtigungen ab ASince (#1271); '' ohne Server.</summary>
    class function NotificationsUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime): string; static;
    /// <summary>Antwort von /notifications: nur Issues, nach ASince. False bei ungültigem JSON.</summary>
    class function ParseNotifications(const AJson: string; ASince: TDateTime;
      out AThreads: TArray<TAtlasGitHubThread>): Boolean; static;
    /// <summary>Der Grund einer Benachrichtigung gehört zum Umfang: Assigned nur "assign", AssignedOrCreated dazu
    /// "author", Watched alle.</summary>
    class function InScope(const AReason: string; AScope: TAtlasTrackerNotifyScope): Boolean; static;
    /// <summary>Neue Kommentare (angelegt nach ASince) aus …/comments als Änderungen an AThread. False bei
    /// ungültigem JSON.</summary>
    class function ParseCommentChanges(const AJson: string; const AThread: TAtlasGitHubThread; ASince: TDateTime;
      out AChanges: TArray<TAtlasTrackerChange>): Boolean; static;
    /// <summary>Ereignisse nach ASince aus …/events: assigned (AMe: an mich?), closed und reopened. False bei
    /// ungültigem JSON.</summary>
    class function ParseEventChanges(const AJson: string; const AThread: TAtlasGitHubThread; const AMe: string;
      ASince: TDateTime; out AChanges: TArray<TAtlasTrackerChange>): Boolean; static;
    /// <summary>Adresse für einen neuen Kommentar (#1276); '' bei ungültiger Kennung.</summary>
    class function CommentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    { IAtlasTrackerProvider }
    function Name: string;
    function Caption: string;
    function DefaultQuery: string;
    function ApiServer(const ATarget: TAtlasTrackerTarget): string;
    function Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs, AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    function IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
    function PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
    function ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
    function ListUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
    function SentQuery(const ATarget: TAtlasTrackerTarget): string;
    function ParseList(const AText: string; AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
    function LocaleUrl(const ATarget: TAtlasTrackerTarget): string;
    function Details(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AComments: Boolean; ATimeoutMs: Integer; out ADetails: TAtlasTrackerDetails;
      out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerWriter }
    function Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AChange: TAtlasTrackerChange; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
      out AValues: TArray<string>): TAtlasTrackerWriteResult;
    { IAtlasTrackerDescriptions }
    function Description(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
    function UpdateDescription(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey, AText: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerLinkWriter }
    function CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean;
    function AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
      out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerBoards (#1272): über TAtlasGitHubBoards }
    function LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
      ATimeoutMs: Integer): TAtlasTrackerWriteResult;
  end;

  // Board für GitHub (#1272), ohne VCL und Open Tools API.
  // - Projekte (v2) über GraphQL (POST <api>/graphql; github.com:
  //   api.github.com/graphql, Enterprise: <server>/api/graphql): erst die
  //   Projekte des Repositorys und der Anmeldename (viewer), dann das gewählte
  //   Projekt mit Feldern und Einträgen. Spalten sind die Optionen des Feldes
  //   „Status“ (sonst des ersten Auswahlfeldes), Sprints die Iterationen des
  //   ersten Iterationsfeldes (aktuelle = enthält heute). Karten nur für
  //   Issues (keine Pull Requests und Entwürfe), höchstens 100 Einträge.
  // - Ohne Projekt: Spalten Offen und Geschlossen aus der REST-Liste der Issues
  //   (offene, dazu die zuletzt geänderten geschlossenen).
  // - Verschieben: erst der Kommentar (fehlen die Rechte, ändert sich nichts),
  //   dann updateProjectV2ItemFieldValue bzw. PATCH state des Issues.
  // GraphQL meldet Fehler mit Status 200 in "errors": fehlende Rechte
  // (INSUFFICIENT_SCOPES, FORBIDDEN) als Unauthorized, sonst Invalid. Dürfen
  // die Projekte nicht gelesen werden, zeigt das Board Offen/Geschlossen mit
  // ProjectsDenied (Hinweis auf die Berechtigung „project“).
  TAtlasGitHubBoards = class(TInterfacedObject, IAtlasTrackerBoards)
  public const
    /// <summary>Projekte des Repositorys und eigener Anmeldename.</summary>
    ProjectsQuery = 'query($owner:String!,$name:String!){viewer{login}repository(owner:$owner,name:$name)' +
      '{projectsV2(first:50){nodes{id title closed}}}}';
    /// <summary>Ein Projekt mit Feldern und Einträgen.</summary>
    ProjectQuery = 'query($id:ID!){node(id:$id){... on ProjectV2{id title url ' +
      'fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}} ' +
      '... on ProjectV2Field{id name dataType} ' +
      '... on ProjectV2IterationField{id name configuration{iterations{id title startDate duration} ' +
      'completedIterations{id title startDate duration}}}}} ' +
      'items(first:100){nodes{id fieldValues(first:20){nodes{' +
      '... on ProjectV2ItemFieldSingleSelectValue{name optionId field{... on ProjectV2SingleSelectField{name}}} ' +
      '... on ProjectV2ItemFieldIterationValue{iterationId field{... on ProjectV2IterationField{name}}} ' +
      '... on ProjectV2ItemFieldNumberValue{number field{... on ProjectV2Field{name}}}}} ' +
      'content{... on Issue{number title url state closedAt body repository{nameWithOwner} ' +
      'assignees(first:5){nodes{login name}}}}}}}}}';
    MoveMutation = 'mutation($project:ID!,$item:ID!,$field:ID!,$option:String!){updateProjectV2ItemFieldValue(' +
      'input:{projectId:$project,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$option}})' +
      '{projectV2Item{id}}}';
    /// <summary>Höchstens so viele geschlossene Issues ohne Projekt.</summary>
    MaxClosed = 30;
  public
    /// <summary>Adresse der GraphQL-Schnittstelle; '' ohne Server.</summary>
    class function GraphQlUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Inhalt eines POST: {"query": AQuery, "variables": {Name: Wert, …}} aus Paaren in AVariables.
    /// </summary>
    class function GraphQlBody(const AQuery: string; const AVariables: array of string): string; static;
    /// <summary>Fehler einer GraphQL-Antwort mit Status 200 ("errors"); None ohne. AMessage: erster Text.</summary>
    class function GraphQlError(const AJson: string; out AMessage: string): TAtlasCiFetchError; static;
    /// <summary>Antwort auf ProjectsQuery: Projekte (offene zuerst) in ASnapshot.Boards, Anmeldename in
    /// ASnapshot.Me. False bei ungültigem JSON.</summary>
    class function ParseProjects(const AJson: string; var ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    /// <summary>Antwort auf ProjectQuery: Spalten, Sprints, Sprint ASprintId ('' = aktueller nach ANow, UTC) und
    /// dessen Karten. False bei ungültigem JSON oder ohne Projekt.</summary>
    class function ParseProject(const AJson: string; const ATarget: TAtlasTrackerTarget; const ASprintId: string;
      ANow: TDateTime; var ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    /// <summary>REST-Liste /issues (ohne Pull Requests) als Karten an ASnapshot.Cards anhängen; False bei
    /// ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; const ATarget: TAtlasTrackerTarget;
      var ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    { IAtlasTrackerBoards }
    function LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
      ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function Search(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AText: string;
      ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    function Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerPeople }
    function Users(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AText: string;
      ATimeoutMs, AMax: Integer; out AUsers: TArray<TAtlasTrackerUser>; out AError: TAtlasCiFetchError): Boolean;
    function Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment; out AError: TAtlasCiFetchError): Boolean;
    function Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerAttach }
    function CanUpload: Boolean;
    function Upload(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey: string;
      const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    function Comment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey, AMarkdown: string;
      ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    function CommentText(const AComment: string; const AFiles: TAtlasAttachFiles): string;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Tracker.Checklist;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.Values[AName];
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
  Number: Int64;
begin
  Result := 0;
  Value := AObject.Values[AName];
  if (Value is TJSONNumber) and TryStrToInt64(TJSONNumber(Value).Value, Number) and (Number > 0) and
    (Number <= MaxInt) then
    Result := Integer(Number);
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.Values[AName];
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function Shorten(const AText: string; AMax: Integer): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > AMax then
    Result := Copy(Result, 1, AMax - 1) + '…';
end;

/// <summary>Logins aus "assignees" mit ", ", ersatzweise "assignee"; '' ohne.</summary>
function AssigneesOf(AObject: TJSONObject): string;
var
  mItem, mEntry: TJSONValue;
  mText: string;
begin
  Result := '';
  mItem := AObject.Values['assignees'];
  if mItem is TJSONArray then
    for mEntry in TJSONArray(mItem) do
    begin
      mText := '';
      if mEntry is TJSONObject then
        mText := Shorten(TextOf(TJSONObject(mEntry), 'login'), 60);
      if mText = '' then
        Continue;
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + mText;
    end;
  mItem := AObject.Values['assignee'];
  if (Result = '') and (mItem is TJSONObject) then
    Result := Shorten(TextOf(TJSONObject(mItem), 'login'), 60);
end;

{ TAtlasGitHubTracker }

class function TAtlasGitHubTracker.ApiBase(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasGitHubApi.Base(ATarget);
end;

class function TAtlasGitHubTracker.SearchText(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Query;
  if Result = '' then
    Result := Query;
  Result := Result + ' repo:' + ATarget.Project + ' is:issue';
end;

class function TAtlasGitHubTracker.SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
var
  Text: string;
  Limit: Integer;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') then
    Exit('');
  Text := SearchText(ATarget);
  Limit := AMax;
  if Limit < 1 then
    Limit := 1;
  if Limit > 100 then
    Limit := 100;
  Result := Result + '/search/issues?q=' + TTextUris.PercentEncode(Text) + '&per_page=' + IntToStr(Limit) +
    '&sort=updated&order=desc';
end;

class function TAtlasGitHubTracker.TextSearchUrl(const ATarget: TAtlasTrackerTarget; const AText: string;
  AMax: Integer): string;
var
  mLimit: Integer;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') or (Trim(AText) = '') then
    Exit('');
  mLimit := AMax;
  if mLimit < 1 then
    mLimit := 1;
  if mLimit > 100 then
    mLimit := 100;
  // Ohne sort: GitHub ordnet nach Treffergüte.
  Result := Result + '/search/issues?q=' + TTextUris.PercentEncode('repo:' + ATarget.Project + ' is:issue ' +
    Trim(AText)) + '&per_page=' + IntToStr(mLimit);
end;

class function TAtlasGitHubTracker.PullsUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/pulls?state=open&per_page=' +
    IntToStr(MaxPulls);
end;

function SafeSha(const ASha: string): Boolean;
var
  Index: Integer;
begin
  Result := (Length(ASha) >= 7) and (Length(ASha) <= 64);
  if Result then
    for Index := 1 to Length(ASha) do
      if not CharInSet(ASha[Index], ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
end;

class function TAtlasGitHubTracker.CheckRunsUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') or not SafeSha(ASha) then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/commits/' + ASha +
    '/check-runs?per_page=100';
end;

class function TAtlasGitHubTracker.StatusUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') or not SafeSha(ASha) then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/commits/' + ASha + '/status';
end;

class function TAtlasGitHubTracker.ParseIssues(const AJson: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
var
  Value, Items, Item, Labels, LabelValue: TJSONValue;
  Issue: TAtlasTrackerIssue;
  LabelName: string;
begin
  AIssues := nil;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Items := TJSONObject(Value).Values['items'];
    if not (Items is TJSONArray) then
      Exit;
    Result := True;
    for Item in TJSONArray(Items) do
    begin
      if Length(AIssues) >= AMax then
        Break;
      if not (Item is TJSONObject) then
        Continue;
      // Die Suche liefert auch Pull Requests; die gehören nicht in die Liste.
      if TJSONObject(Item).Values['pull_request'] <> nil then
        Continue;
      Issue := TAtlasTrackerIssue.Empty;
      Issue.Number := IntOf(TJSONObject(Item), 'number');
      if Issue.Number <= 0 then
        Continue;
      Issue.Key := '#' + IntToStr(Issue.Number);
      Issue.Title := Shorten(TextOf(TJSONObject(Item), 'title'), TAtlasTrackerIssue.MaxTitle);
      Issue.State := TextOf(TJSONObject(Item), 'state');
      Issue.Assignee := AssigneesOf(TJSONObject(Item));
      Labels := TJSONObject(Item).Values['labels'];
      if Labels is TJSONArray then
        for LabelValue in TJSONArray(Labels) do
        begin
          if Length(Issue.Labels) >= TAtlasTrackerIssue.MaxLabels then
            Break;
          LabelName := '';
          if LabelValue is TJSONObject then
            LabelName := Trim(TextOf(TJSONObject(LabelValue), 'name'))
          else if LabelValue is TJSONString then
            LabelName := Trim(TJSONString(LabelValue).Value);
          if LabelName <> '' then
            Issue.Labels := Issue.Labels + [Shorten(LabelName, 40)];
        end;
      AIssues := AIssues + [Issue];
    end;
  finally
    Value.Free;
  end;
end;

/// <summary>updated_at (ISO 8601) als UTC; 0 ohne.</summary>
function UpdatedOf(AObject: TJSONObject): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := TextOf(AObject, 'updated_at');
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
    Result := 0;
end;

class function TAtlasGitHubTracker.ParsePulls(const AJson: string; out APulls: TArray<TAtlasGitHubPull>): Boolean;
var
  Value, Item, Head: TJSONValue;
  Pull: TAtlasGitHubPull;
begin
  APulls := nil;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONArray) then
      Exit;
    Result := True;
    for Item in TJSONArray(Value) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Pull := Default(TAtlasGitHubPull);
      Pull.Number := IntOf(TJSONObject(Item), 'number');
      if Pull.Number <= 0 then
        Continue;
      Pull.Draft := FlagOf(TJSONObject(Item), 'draft');
      Pull.State := LowerCase(TextOf(TJSONObject(Item), 'state'));
      Pull.Merged := TextOf(TJSONObject(Item), 'merged_at') <> '';
      Pull.Updated := UpdatedOf(TJSONObject(Item));
      Pull.Title := TextOf(TJSONObject(Item), 'title');
      // Nur der Anfang: „closes #N“ steht fast immer oben, und lange Beschreibungen kosten nur Speicher.
      Pull.Body := Copy(TextOf(TJSONObject(Item), 'body'), 1, 4000);
      Head := TJSONObject(Item).Values['head'];
      if Head is TJSONObject then
      begin
        Pull.Branch := TextOf(TJSONObject(Head), 'ref');
        Pull.Sha := TextOf(TJSONObject(Head), 'sha');
      end;
      APulls := APulls + [Pull];
    end;
  finally
    Value.Free;
  end;
end;

/// <summary>„close(s|d)“, „fix(es|ed)“ oder „resolve(s|d)“, optional „:“, dann „#N“ ohne weitere Ziffer.</summary>
function ClosesIssue(const AText: string; ANumber: Integer): Boolean;
const
  Words: array[0..8] of string = ('close', 'closes', 'closed', 'fix', 'fixes', 'fixed', 'resolve', 'resolves',
    'resolved');
var
  Lower, Mark: string;
  Index, Start, Stop: Integer;
  Word: string;
begin
  Result := False;
  Lower := LowerCase(AText);
  Mark := '#' + IntToStr(ANumber);
  Index := Pos(Mark, Lower);
  while Index > 0 do
  begin
    Stop := Index + Length(Mark);
    if (Stop > Length(Lower)) or not CharInSet(Lower[Stop], ['0'..'9']) then
    begin
      // Rückwärts: Leerzeichen und ":" überspringen, dann das Wort davor.
      Start := Index - 1;
      while (Start >= 1) and CharInSet(Lower[Start], [' ', ':', #9]) do
        Dec(Start);
      Stop := Start;
      while (Start >= 1) and CharInSet(Lower[Start], ['a'..'z']) do
        Dec(Start);
      if Stop > Start then
        for Word in Words do
          if Copy(Lower, Start + 1, Stop - Start) = Word then
            Exit(True);
    end;
    Index := Pos(Mark, Lower, Index + 1);
  end;
end;

class function TAtlasGitHubTracker.PullMentions(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean;
begin
  Result := False;
  if ANumber <= 0 then
    Exit;
  Result := (TAtlasTrackerNaming.KeyOfBranch(ProviderName, '', APull.Branch) = '#' + IntToStr(ANumber)) or
    ClosesIssue(APull.Title, ANumber) or ClosesIssue(APull.Body, ANumber);
end;

/// <summary>„#N“ ohne Ziffer davor oder danach und ohne Buchstaben davor.</summary>
function NamesNumber(const AText: string; ANumber: Integer): Boolean;
var
  mMark: string;
  mIndex, mStop: Integer;
begin
  Result := False;
  mMark := '#' + IntToStr(ANumber);
  mIndex := Pos(mMark, AText);
  while mIndex > 0 do
  begin
    mStop := mIndex + Length(mMark);
    if ((mStop > Length(AText)) or not CharInSet(AText[mStop], ['0'..'9'])) and
      ((mIndex = 1) or not CharInSet(AText[mIndex - 1], ['0'..'9', 'A'..'Z', 'a'..'z'])) then
      Exit(True);
    mIndex := Pos(mMark, AText, mIndex + 1);
  end;
end;

class function TAtlasGitHubTracker.PullRefersTo(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean;
begin
  Result := (ANumber > 0) and (PullMentions(APull, ANumber) or NamesNumber(APull.Title, ANumber));
end;

class function TAtlasGitHubTracker.AllPullsUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/pulls?state=all&per_page=' +
    IntToStr(MaxPageSize) + '&sort=updated&direction=desc';
end;

class function TAtlasGitHubTracker.PullState(const APull: TAtlasGitHubPull): TAtlasTrackerPullState;
begin
  if APull.Merged then
    Result := TAtlasTrackerPullState.Merged
  else if APull.State = 'closed' then
    Result := TAtlasTrackerPullState.Closed
  else if APull.Draft then
    Result := TAtlasTrackerPullState.Draft
  else
    Result := TAtlasTrackerPullState.Open;
end;

class function TAtlasGitHubTracker.ParseCheckRuns(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean;
var
  Value, Runs, Run: TJSONValue;
  Status, Conclusion: string;
  Any, Running, Failed: Boolean;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Runs := TJSONObject(Value).Values['check_runs'];
    if not (Runs is TJSONArray) then
      Exit;
    Result := True;
    Any := False;
    Running := False;
    Failed := False;
    for Run in TJSONArray(Runs) do
    begin
      if not (Run is TJSONObject) then
        Continue;
      Any := True;
      Status := LowerCase(TextOf(TJSONObject(Run), 'status'));
      Conclusion := LowerCase(TextOf(TJSONObject(Run), 'conclusion'));
      if Status <> 'completed' then
        Running := True
      else if (Conclusion = 'failure') or (Conclusion = 'timed_out') or (Conclusion = 'cancelled') or
        (Conclusion = 'action_required') or (Conclusion = 'startup_failure') then
        Failed := True;
    end;
    if Failed then
      AChecks := TAtlasTrackerChecks.Failure
    else if Running then
      AChecks := TAtlasTrackerChecks.Pending
    else if Any then
      AChecks := TAtlasTrackerChecks.Success;
  finally
    Value.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseStatus(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean;
var
  Value, Statuses: TJSONValue;
  State: string;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Result := True;
    // Ohne einzelne Status meldet GitHub "pending"; das ist keine Ampel.
    Statuses := TJSONObject(Value).Values['statuses'];
    if not (Statuses is TJSONArray) or (TJSONArray(Statuses).Count = 0) then
      Exit;
    State := LowerCase(TextOf(TJSONObject(Value), 'state'));
    if State = 'success' then
      AChecks := TAtlasTrackerChecks.Success
    else if (State = 'failure') or (State = 'error') then
      AChecks := TAtlasTrackerChecks.Failure
    else if State = 'pending' then
      AChecks := TAtlasTrackerChecks.Pending;
  finally
    Value.Free;
  end;
end;

class function TAtlasGitHubTracker.ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError;
begin
  case AStatus of
    401, 403:
      Result := TAtlasCiFetchError.Unauthorized;
    404:
      Result := TAtlasCiFetchError.NotFound;
    400, 422:
      Result := TAtlasCiFetchError.Invalid;
    // Gelöschtes Issue (Vorschau, #1264).
    410:
      Result := TAtlasCiFetchError.NotFound;
  else
    Result := TAtlasCiFetchError.Server;
  end;
end;

function NumberOfKey(const AKey: string): Integer;
begin
  if not TryStrToInt(TAtlasTrackerNaming.BranchKey(AKey), Result) or (Result <= 0) then
    Result := 0;
end;

/// <summary>ISO 8601 ("2026-10-28T10:40:49Z") als UTC; 0 ohne.</summary>
function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := TextOf(AObject, AName);
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
    Result := 0;
end;

function LoginOf(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONObject then
    Result := Shorten(TextOf(TJSONObject(AValue), 'login'), 60);
end;

function Limited(const AText: string): string;
begin
  Result := Copy(AText, 1, TAtlasTrackerDetails.MaxText);
end;

class function TAtlasGitHubTracker.IssueApiUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  mNumber: Integer;
begin
  Result := ApiBase(ATarget);
  mNumber := NumberOfKey(AKey);
  if (Result = '') or (ATarget.Project = '') or (mNumber = 0) then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/issues/' + IntToStr(mNumber);
end;

class function TAtlasGitHubTracker.ParseDetails(const AJson: string; out ADetails: TAtlasTrackerDetails;
  out ACommentCount: Integer): Boolean;
var
  mValue, mItem, mEntry: TJSONValue;
  mRoot: TJSONObject;
  mText, mReason: string;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  ACommentCount := 0;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mRoot := TJSONObject(mValue);
    ADetails.Number := IntOf(mRoot, 'number');
    if ADetails.Number <= 0 then
      Exit;
    ADetails.Key := '#' + IntToStr(ADetails.Number);
    ADetails.Title := Shorten(TextOf(mRoot, 'title'), 500);
    ADetails.Description := Limited(TextOf(mRoot, 'body'));
    // "closed" mit Grund ("completed", "not_planned") wie in der Oberfläche.
    ADetails.State := TextOf(mRoot, 'state');
    mReason := TextOf(mRoot, 'state_reason');
    if (ADetails.State = 'closed') and (mReason <> '') and (mReason <> 'completed') then
      ADetails.State := ADetails.State + ' (' + StringReplace(mReason, '_', ' ', [rfReplaceAll]) + ')';
    ADetails.Created := TimeOf(mRoot, 'created_at');
    ADetails.Updated := TimeOf(mRoot, 'updated_at');
    ACommentCount := IntOf(mRoot, 'comments');
    mItem := mRoot.Values['labels'];
    if mItem is TJSONArray then
      for mEntry in TJSONArray(mItem) do
      begin
        mText := '';
        if mEntry is TJSONObject then
          mText := Trim(TextOf(TJSONObject(mEntry), 'name'))
        else if mEntry is TJSONString then
          mText := Trim(TJSONString(mEntry).Value);
        if mText <> '' then
          ADetails.Labels := ADetails.Labels + [Shorten(mText, 40)];
      end;
    ADetails.Assignee := AssigneesOf(mRoot);
    if mRoot.Values['milestone'] is TJSONObject then
      ADetails.Sprint := Shorten(TextOf(TJSONObject(mRoot.Values['milestone']), 'title'), 60);
    // Issue-Typen (Bug, Feature …) der Organisation.
    if mRoot.Values['type'] is TJSONObject then
      ADetails.Kind := Shorten(TextOf(TJSONObject(mRoot.Values['type']), 'name'), 40);
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseComments(const AJson: string;
  out AComments: TArray<TAtlasTrackerComment>): Boolean;
var
  mValue, mItem: TJSONValue;
  mComment: TAtlasTrackerComment;
begin
  AComments := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mComment := Default(TAtlasTrackerComment);
      mComment.Author := LoginOf(TJSONObject(mItem).Values['user']);
      mComment.Created := TimeOf(TJSONObject(mItem), 'created_at');
      mComment.Text := Limited(TextOf(TJSONObject(mItem), 'body'));
      AComments := AComments + [mComment];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseTimeline(const AJson, AProject: string;
  out ALinks: TArray<TAtlasTrackerLink>): Boolean;
var
  mValue, mItem, mSource, mIssue: TJSONValue;
  mLink: TAtlasTrackerLink;
  mRepository, mPage: string;
  mNumber, mIndex: Integer;
  mKnown: Boolean;
begin
  ALinks := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (TextOf(TJSONObject(mItem), 'event') <> 'cross-referenced') then
        Continue;
      mSource := TJSONObject(mItem).Values['source'];
      if not (mSource is TJSONObject) then
        Continue;
      mIssue := TJSONObject(mSource).Values['issue'];
      if not (mIssue is TJSONObject) then
        Continue;
      mNumber := IntOf(TJSONObject(mIssue), 'number');
      if mNumber <= 0 then
        Continue;
      mRepository := '';
      if TJSONObject(mIssue).Values['repository'] is TJSONObject then
        mRepository := TextOf(TJSONObject(TJSONObject(mIssue).Values['repository']), 'full_name');
      mLink := Default(TAtlasTrackerLink);
      mLink.Local := (mRepository = '') or SameText(mRepository, AProject);
      if mLink.Local then
        mLink.Key := '#' + IntToStr(mNumber)
      else
        mLink.Key := mRepository + '#' + IntToStr(mNumber);
      mLink.Title := Shorten(TextOf(TJSONObject(mIssue), 'title'), 200);
      if TJSONObject(mIssue).Values['pull_request'] <> nil then
      begin
        mLink.Relation := 'pull request';
        mLink.Kind := TAtlasTrackerLinkKind.PullRequest;
      end
      else
      begin
        mLink.Relation := 'cross-referenced';
        mLink.Kind := TAtlasTrackerLinkKind.Mentioned;
      end;
      // Zustand (#1279) steht im Eintrag.
      mLink.State := TextOf(TJSONObject(mIssue), 'state');
      mLink.StateKnown := mLink.State <> '';
      mLink.Resolved := SameText(mLink.State, 'closed');
      // Nur Web-Seiten über https; was nicht im Fenster öffnet, geht in den Browser.
      mPage := TextOf(TJSONObject(mIssue), 'html_url');
      if StartsText('https://', mPage) then
        mLink.Page := mPage;
      mKnown := False;
      for mIndex := 0 to High(ALinks) do
        if SameText(ALinks[mIndex].Key, mLink.Key) then
          mKnown := True;
      if not mKnown and (Length(ALinks) < TAtlasTrackerDetails.MaxLinks) then
        ALinks := ALinks + [mLink];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.FileAttachments(
  const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerAttachment>;
var
  mTexts: TArray<string>;
  mText: string;
  mComment: TAtlasTrackerComment;
  mLink: TAtlasMarkdownLink;
  mAttachment: TAtlasTrackerAttachment;
  mIndex: Integer;
  mKnown: Boolean;
begin
  Result := nil;
  mTexts := TArray<string>.Create(ADetails.Description);
  for mComment in ADetails.Comments do
    mTexts := mTexts + [mComment.Text];
  for mText in mTexts do
    for mLink in TAtlasTrackerMarkdown.Links(mText) do
    begin
      if not StartsText('https://', mLink.Url) or (Pos('/user-attachments/files/', mLink.Url) = 0) then
        Continue;
      mKnown := False;
      for mIndex := 0 to High(Result) do
        if Result[mIndex].Url = mLink.Url then
          mKnown := True;
      if mKnown or (Length(Result) >= TAtlasTrackerDetails.MaxAttachments) then
        Continue;
      mAttachment := Default(TAtlasTrackerAttachment);
      mAttachment.Name := Shorten(mLink.Text, 200);
      if mAttachment.Name = '' then
        mAttachment.Name := Copy(mLink.Url, LastDelimiter('/', mLink.Url) + 1, 200);
      mAttachment.Size := -1;
      mAttachment.Url := mLink.Url;
      mAttachment.External := True;
      Result := Result + [mAttachment];
    end;
end;

function TAtlasGitHubTracker.Name: string;
begin
  Result := ProviderName;
end;

function TAtlasGitHubTracker.Caption: string;
begin
  Result := 'GitHub';
end;

function TAtlasGitHubTracker.DefaultQuery: string;
begin
  Result := Query;
end;

function TAtlasGitHubTracker.ApiServer(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasTrackerTarget.Create('', ApiBase(ATarget), '', '').Server;
end;

function Remaining(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  Rest: Int64;
begin
  Rest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if Rest > 0 then
    Result := Integer(Rest);
end;

function TAtlasGitHubTracker.Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  Watch: TStopwatch;
  Status, Index, PullIndex, Checked: Integer;
  Text: string;
  Pulls: TArray<TAtlasGitHubPull>;
  Checks: TAtlasTrackerChecks;
  Ignored: TAtlasCiFetchError;
  Pull: TAtlasGitHubPull;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if not ATarget.Configured or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  Watch := TStopwatch.StartNew;
  if not ATransport.Get(SearchUrl(ATarget, AMax), ATimeoutMs, Status, Text, AError) then
    Exit;
  if Status <> 200 then
  begin
    AError := ErrorOfStatus(Status);
    Exit;
  end;
  if not ParseIssues(Text, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
  if (Length(AIssues) = 0) or (Remaining(Watch, ATimeoutMs) = 0) then
    Exit;
  // Pull Requests und Ampeln in der restlichen Zeit; was fehlt, bleibt unbekannt.
  if not ATransport.Get(PullsUrl(ATarget), Remaining(Watch, ATimeoutMs), Status, Text, Ignored) or
    (Status <> 200) or not ParsePulls(Text, Pulls) then
    Exit;
  Checked := 0;
  for Index := 0 to High(AIssues) do
    for PullIndex := 0 to High(Pulls) do
    begin
      Pull := Pulls[PullIndex];
      if not PullMentions(Pull, AIssues[Index].Number) then
        Continue;
      AIssues[Index].PullRequest.Number := Pull.Number;
      AIssues[Index].PullRequest.Draft := Pull.Draft;
      if (Checked < MaxChecks) and (Remaining(Watch, ATimeoutMs) > 0) and (CheckRunsUrl(ATarget, Pull.Sha) <> '') then
      begin
        Inc(Checked);
        Checks := TAtlasTrackerChecks.Unknown;
        if ATransport.Get(CheckRunsUrl(ATarget, Pull.Sha), Remaining(Watch, ATimeoutMs), Status, Text, Ignored) and
          (Status = 200) then
          ParseCheckRuns(Text, Checks);
        // Ohne Check Runs: der ältere kombinierte Status (externe CI wie Jenkins).
        if (Checks = TAtlasTrackerChecks.Unknown) and (Remaining(Watch, ATimeoutMs) > 0) and
          ATransport.Get(StatusUrl(ATarget, Pull.Sha), Remaining(Watch, ATimeoutMs), Status, Text, Ignored) and
          (Status = 200) then
          ParseStatus(Text, Checks);
        AIssues[Index].PullRequest.Checks := Checks;
      end;
      Break;
    end;
  AError := TAtlasCiFetchError.None;
end;

function TAtlasGitHubTracker.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  Number: Integer;
begin
  Result := '';
  if (ATarget.Server = '') or (ATarget.Project = '') then
    Exit;
  if not TryStrToInt(TAtlasTrackerNaming.BranchKey(AKey), Number) or (Number <= 0) then
    Exit;
  Result := ATarget.Server + '/' + TTextUris.PercentEncode(ATarget.Project) + '/issues/' + IntToStr(Number);
end;

function TAtlasGitHubTracker.PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
begin
  Result := '';
  if (ATarget.Server = '') or (ATarget.Project = '') or (ANumber <= 0) then
    Exit;
  Result := ATarget.Server + '/' + TTextUris.PercentEncode(ATarget.Project) + '/pull/' + IntToStr(ANumber);
end;

function TAtlasGitHubTracker.ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ApiBase(ATarget);
  if Result <> '' then
    Result := Result + '/user';
end;

function TAtlasGitHubTracker.ListUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
begin
  Result := SearchUrl(ATarget, AMax);
end;

function TAtlasGitHubTracker.SentQuery(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := SearchText(ATarget);
end;

function TAtlasGitHubTracker.ParseList(const AText: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
begin
  Result := ParseIssues(AText, AMax, AIssues);
end;

function TAtlasGitHubTracker.LocaleUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  // Die Suchbegriffe von GitHub sind in jeder Sprache englisch.
  Result := '';
end;

function TAtlasGitHubTracker.Details(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; AComments: Boolean; ATimeoutMs: Integer; out ADetails: TAtlasTrackerDetails;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mUrl, mText: string;
  mStatus, mCount, mPage: Integer;
  mIgnored: TAtlasCiFetchError;
  mComments, mOlder: TArray<TAtlasTrackerComment>;
  mLinks: TArray<TAtlasTrackerLink>;
  mSummary: TAtlasGitHubLinkSummary;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseDetails(mText, ADetails, mCount) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mSummary := ParseLinkSummary(mText);
  ADetails.Page := IssuePage(ATarget, ADetails.Key);
  Result := True;
  // Kommentare und Verweise in der restlichen Zeit; was fehlt, bleibt leer.
  ADetails.CommentsLoaded := AComments;
  if AComments and (mCount > 0) and (Remaining(mWatch, ATimeoutMs) > 0) then
  begin
    // Die neuesten: letzte Seite, bei Bedarf die davor.
    mPage := (mCount + MaxPageSize - 1) div MaxPageSize;
    if ATransport.Get(mUrl + '/comments?per_page=' + IntToStr(MaxPageSize) + '&page=' + IntToStr(mPage),
      Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      ParseComments(mText, mComments) then
    begin
      if (mPage > 1) and (Length(mComments) < TAtlasTrackerDetails.MaxComments) and
        (Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mUrl + '/comments?per_page=' +
        IntToStr(MaxPageSize) + '&page=' + IntToStr(mPage - 1), Remaining(mWatch, ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) and ParseComments(mText, mOlder) then
        mComments := mOlder + mComments;
      if Length(mComments) > TAtlasTrackerDetails.MaxComments then
        mComments := Copy(mComments, Length(mComments) - TAtlasTrackerDetails.MaxComments,
          TAtlasTrackerDetails.MaxComments);
      ADetails.Comments := mComments;
    end;
  end;
  if (Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mUrl + '/timeline?per_page=' + IntToStr(MaxPageSize),
    Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
    ParseTimeline(mText, ATarget.Project, mLinks) then
    ADetails.Links := mLinks;
  LoadRelations(ATarget, ATransport, mUrl, mSummary, mWatch, ATimeoutMs, ADetails);
  ADetails.Attachments := FileAttachments(ADetails);
end;

{ IAtlasTrackerWriter (#1266) }

const
  ClosingStates: array[0..5] of string = ('Erledigt', 'Done', 'Closed', 'Geschlossen', 'Completed', 'Fertig');

class function TAtlasGitHubTracker.ClosesIssue(const AState: string): Boolean;
var
  mState: string;
begin
  Result := False;
  for mState in ClosingStates do
    if SameText(mState, Trim(AState)) then
      Exit(True);
end;

class function TAtlasGitHubTracker.CommentJson(const AText: string): string;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('body', AText);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

function NamesOf(AValue: TJSONValue; const AField: string): TArray<string>;
var
  mItem: TJSONValue;
  mText: string;
begin
  Result := nil;
  if AValue is TJSONArray then
    for mItem in TJSONArray(AValue) do
      if mItem is TJSONObject then
      begin
        mText := Trim(TextOf(TJSONObject(mItem), AField));
        if mText <> '' then
          Result := Result + [mText];
      end;
end;

class function TAtlasGitHubTracker.ParseAssignment(const AJson: string;
  out ALabels, AAssignees: TArray<string>): Boolean;
var
  mValue: TJSONValue;
begin
  ALabels := nil;
  AAssignees := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
      Exit;
    ALabels := NamesOf(TJSONObject(mValue).Values['labels'], 'name');
    AAssignees := NamesOf(TJSONObject(mValue).Values['assignees'], 'login');
  finally
    mValue.Free;
  end;
end;

function IndexOfText(const AItems: TArray<string>; const AText: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
    if SameText(AItems[mIndex], AText) then
      Exit(mIndex);
  Result := -1;
end;

function JsonList(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
    Result.Add(mItem);
end;

class function TAtlasGitHubTracker.PatchJson(const ALabels, AAssignees: TArray<string>;
  const AChange: TAtlasTrackerChange; const AMe: string): string;
var
  mObject: TJSONObject;
  mLabels, mAssignees: TArray<string>;
  mState, mPrevious: string;
  mIndex: Integer;
  mClose, mLabelsChanged, mAssigneesChanged: Boolean;
begin
  Result := '';
  mLabels := Copy(ALabels);
  mAssignees := Copy(AAssignees);
  mState := Trim(AChange.State);
  mPrevious := Trim(AChange.PreviousState);
  mClose := (mState <> '') and ClosesIssue(mState);
  mLabelsChanged := False;
  if mState <> '' then
  begin
    // Der Zustand aus „Beginnen“ gilt nicht mehr.
    mIndex := IndexOfText(mLabels, mPrevious);
    if (mPrevious <> '') and not SameText(mPrevious, mState) and (mIndex >= 0) then
    begin
      Delete(mLabels, mIndex, 1);
      mLabelsChanged := True;
    end;
    if not mClose and (IndexOfText(mLabels, mState) < 0) then
    begin
      mLabels := mLabels + [mState];
      mLabelsChanged := True;
    end;
  end;
  mAssigneesChanged := False;
  case AChange.Assign of
    TAtlasTrackerAssign.Me:
      if (AMe <> '') and (IndexOfText(mAssignees, AMe) < 0) then
      begin
        mAssignees := mAssignees + [AMe];
        mAssigneesChanged := True;
      end;
    TAtlasTrackerAssign.User:
      if Trim(AChange.Assignee) <> '' then
      begin
        // Übergeben: der neue Zuständige statt aller bisherigen.
        mAssigneesChanged := (Length(mAssignees) <> 1) or not SameText(mAssignees[0], Trim(AChange.Assignee));
        mAssignees := TArray<string>.Create(Trim(AChange.Assignee));
      end;
  else
    // Keep: Zuständige bleiben.
  end;
  if not (mLabelsChanged or mAssigneesChanged or mClose) then
    Exit;
  mObject := TJSONObject.Create;
  try
    if mLabelsChanged then
      mObject.AddPair('labels', JsonList(mLabels));
    if mAssigneesChanged then
      mObject.AddPair('assignees', JsonList(mAssignees));
    if mClose then
    begin
      mObject.AddPair('state', 'closed');
      mObject.AddPair('state_reason', 'completed');
    end;
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseNames(const AJson, AField: string; out AValues: TArray<string>): Boolean;
var
  mValue: TJSONValue;
begin
  AValues := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if Result then
      AValues := NamesOf(mValue, AField);
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseUsers(const AJson: string;
  out AUsers: TArray<TAtlasTrackerUser>): Boolean;
var
  mLogins: TArray<string>;
  mLogin: string;
begin
  AUsers := nil;
  Result := ParseNames(AJson, 'login', mLogins);
  for mLogin in mLogins do
    AUsers := AUsers + [TAtlasTrackerUser.Create(mLogin, '')];
end;

class function TAtlasGitHubTracker.AssigneesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/assignees?per_page=' +
    IntToStr(MaxPageSize);
end;

class function TAtlasGitHubTracker.ErrorMessage(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
      Result := TextOf(TJSONObject(mValue), 'message');
  finally
    mValue.Free;
  end;
  Result := Shorten(Result, 300);
end;

function Answered(AStatus: Integer): Boolean;
begin
  Result := (AStatus >= 200) and (AStatus <= 299);
end;

function TAtlasGitHubTracker.Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerChange; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mUrl, mText, mMe, mBody: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
  mValue: TJSONValue;
  mLabels, mAssignees: TArray<string>;
begin
  Result := TAtlasTrackerWriteResult.Ok;
  if not AChange.HasWork then
    Exit;
  mUrl := IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or not Supports(ATransport, IAtlasCiSend, mSend) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  mWatch := TStopwatch.StartNew;
  mMe := '';
  if AChange.Assign = TAtlasTrackerAssign.Me then
  begin
    if not ATransport.Get(ApiBase(ATarget) + '/user', ATimeoutMs, mStatus, mText, mError) then
      Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
    if mStatus <> 200 then
      Exit(TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mText)));
    mValue := TJSONObject.ParseJSONValue(mText);
    try
      if mValue is TJSONObject then
        mMe := Trim(TextOf(TJSONObject(mValue), 'login'));
    finally
      mValue.Free;
    end;
    if mMe = '' then
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, ''));
  end;
  // Zuerst der Kommentar: Fehlen die Schreibrechte, ändert sich nichts am Issue.
  if Trim(AChange.Comment) <> '' then
  begin
    if not mSend.Send('POST', mUrl + '/comments', CommentJson(AChange.Comment), Remaining(mWatch, ATimeoutMs),
      mStatus, mText, mError) then
      Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
    if not Answered(mStatus) then
      Exit(TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mText)));
  end;
  if (Trim(AChange.State) = '') and (AChange.Assign = TAtlasTrackerAssign.Keep) then
    Exit;
  if not ATransport.Get(mUrl, Remaining(mWatch, ATimeoutMs), mStatus, mText, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if mStatus <> 200 then
    Exit(TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mText)));
  if not ParseAssignment(mText, mLabels, mAssignees) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, ''));
  mBody := PatchJson(mLabels, mAssignees, AChange, mMe);
  if mBody = '' then
    Exit;
  if not mSend.Send('PATCH', mUrl, mBody, Remaining(mWatch, ATimeoutMs), mStatus, mText, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if not Answered(mStatus) then
    Result := TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mText));
end;

function TAtlasGitHubTracker.Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
  out AValues: TArray<string>): TAtlasTrackerWriteResult;
var
  mUrl, mText, mField: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  AValues := nil;
  Result := TAtlasTrackerWriteResult.Ok;
  // GitHub kennt keine Felder: Zustände sind Labels, zuständig sind Benutzer.
  if (AKind = TAtlasTrackerValueKind.StateFields) or (AKind = TAtlasTrackerValueKind.UserFields) then
    Exit;
  mUrl := ApiBase(ATarget);
  if (mUrl = '') or (ATarget.Project = '') or (ATransport = nil) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  if AKind = TAtlasTrackerValueKind.Users then
  begin
    mUrl := AssigneesUrl(ATarget);
    mField := 'login';
  end
  else
  begin
    mUrl := mUrl + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/labels?per_page=' + IntToStr(MaxPageSize);
    mField := 'name';
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if mStatus <> 200 then
    Exit(TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mText)));
  if not ParseNames(mText, mField, AValues) then
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, '');
end;

class function TAtlasGitHubTracker.ParseBody(const AJson: string; out AText: string): Boolean;
var
  mValue: TJSONValue;
begin
  AText := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := (mValue is TJSONObject) and (IntOf(TJSONObject(mValue), 'number') > 0);
    if Result then
      AText := TextOf(TJSONObject(mValue), 'body');
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.BodyJson(const AText: string): string;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('body', AText);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

function TAtlasGitHubTracker.Description(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mJson: string;
  mStatus: Integer;
begin
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mJson, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseBody(mJson, AText) or (Length(AText) > TAtlasTrackerDetails.MaxDescription) then
  begin
    AText := '';
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasGitHubTracker.UpdateDescription(const ATarget: TAtlasTrackerTarget;
  const ATransport: IAtlasCiTransport; const AKey, AText: string; ATimeoutMs: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mAnswer: string;
  mStatus: Integer;
  mSend: IAtlasCiSend;
begin
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or not Supports(ATransport, IAtlasCiSend, mSend) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if Length(AText) > TAtlasTrackerDetails.MaxDescription then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if not mSend.Send('PATCH', mUrl, BodyJson(AText), ATimeoutMs, mStatus, mAnswer, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := True;
end;

{ Verknüpfungen (#1279) }

function SummaryCount(ARoot: TJSONObject; const AObject, AName: string): Integer;
var
  mValue: TJSONValue;
  mNumber: Int64;
begin
  Result := -1;
  mValue := ARoot.Values[AObject];
  if not (mValue is TJSONObject) then
    Exit;
  mValue := TJSONObject(mValue).Values[AName];
  if (mValue is TJSONNumber) and TryStrToInt64(TJSONNumber(mValue).Value, mNumber) and (mNumber >= 0) and
    (mNumber <= MaxInt) then
    Result := Integer(mNumber);
end;

class function TAtlasGitHubTracker.ParseLinkSummary(const AJson: string): TAtlasGitHubLinkSummary;
var
  mValue: TJSONValue;
begin
  Result.SubIssues := -1;
  Result.BlockedBy := -1;
  Result.Blocking := -1;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    Result.SubIssues := SummaryCount(TJSONObject(mValue), 'sub_issues_summary', 'total');
    Result.BlockedBy := SummaryCount(TJSONObject(mValue), 'issue_dependencies_summary', 'total_blocked_by');
    Result.Blocking := SummaryCount(TJSONObject(mValue), 'issue_dependencies_summary', 'total_blocking');
  finally
    mValue.Free;
  end;
end;

/// <summary>"owner/repo" eines Issues aus repository_url (…/repos/owner/repo); '' ohne.</summary>
function RepositoryOf(AIssue: TJSONObject): string;
var
  mUrl: string;
  mAt: Integer;
begin
  Result := '';
  mUrl := TextOf(AIssue, 'repository_url');
  mAt := Pos('/repos/', mUrl);
  if mAt > 0 then
    Result := Copy(mUrl, mAt + Length('/repos/'), MaxInt);
end;

class function TAtlasGitHubTracker.ParseRelated(const AJson, AProject: string; AKind: TAtlasTrackerLinkKind;
  out ALinks: TArray<TAtlasTrackerLink>): Boolean;
const
  Relations: array[TAtlasTrackerLinkKind] of string = ('', 'blocked by', 'blocking', 'sub-issue', 'parent', '', '',
    '', 'cross-referenced', 'pull request');
var
  mValue, mItem: TJSONValue;
  mIssue: TJSONObject;
  mLink: TAtlasTrackerLink;
  mNumber: Integer;
  mRepository, mPage: string;
begin
  ALinks := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ALinks) >= TAtlasTrackerDetails.MaxLinks) then
        Continue;
      mIssue := TJSONObject(mItem);
      mNumber := IntOf(mIssue, 'number');
      if mNumber <= 0 then
        Continue;
      mRepository := RepositoryOf(mIssue);
      mLink := Default(TAtlasTrackerLink);
      mLink.Local := (mRepository = '') or SameText(mRepository, AProject);
      if mLink.Local then
        mLink.Key := '#' + IntToStr(mNumber)
      else
        mLink.Key := mRepository + '#' + IntToStr(mNumber);
      mLink.Title := Shorten(TextOf(mIssue, 'title'), 200);
      mLink.Kind := AKind;
      mLink.Relation := Relations[AKind];
      mLink.State := TextOf(mIssue, 'state');
      mLink.StateKnown := mLink.State <> '';
      mLink.Resolved := SameText(mLink.State, 'closed');
      mPage := TextOf(mIssue, 'html_url');
      if StartsText('https://', mPage) then
        mLink.Page := mPage;
      ALinks := ALinks + [mLink];
    end;
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasGitHubTracker.MergeLinks(var ALinks: TArray<TAtlasTrackerLink>;
  const ANew: TArray<TAtlasTrackerLink>);
var
  mLink: TAtlasTrackerLink;
  mIndex: Integer;
  mDone: Boolean;
begin
  for mLink in ANew do
  begin
    mDone := False;
    for mIndex := 0 to High(ALinks) do
      if SameText(ALinks[mIndex].Key, mLink.Key) then
      begin
        if ALinks[mIndex].Kind = mLink.Kind then
          mDone := True
        // Die Erwähnung desselben Issues weicht der genaueren Art.
        else if ALinks[mIndex].Kind in [TAtlasTrackerLinkKind.Mentioned, TAtlasTrackerLinkKind.Other] then
        begin
          ALinks[mIndex] := mLink;
          mDone := True;
        end;
        if mDone then
          Break;
      end;
    if not mDone and (Length(ALinks) < TAtlasTrackerDetails.MaxLinks) then
      ALinks := ALinks + [mLink];
  end;
end;

class function TAtlasGitHubTracker.ParseIssueId(const AJson: string): Int64;
var
  mValue, mId: TJSONValue;
begin
  Result := 0;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mId := TJSONObject(mValue).Values['id'];
    if not (mId is TJSONNumber) or not TryStrToInt64(TJSONNumber(mId).Value, Result) or (Result < 0) then
      Result := 0;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.NewIssueBody(const ATitle, ADescription: string): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('title', Trim(ATitle));
    if Trim(ADescription) <> '' then
      mRoot.AddPair('body', ADescription);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubTracker.IdBody(const AName: string; AId: Int64): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair(AName, TJSONNumber.Create(AId));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasGitHubTracker.LoadRelations(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AUrl: string; const ASummary: TAtlasGitHubLinkSummary; const AWatch: TStopwatch; ATimeoutMs: Integer;
  var ADetails: TAtlasTrackerDetails);
var
  mStatus, mNumber, mCount: Integer;
  mText: string;
  mIgnored: TAtlasCiFetchError;
  mLinks: TArray<TAtlasTrackerLink>;
  mLink: TAtlasTrackerLink;
  mOther: TAtlasTrackerDetails;
  mBlockers, mKnown: Boolean;
  mIndex: Integer;
begin
  // Nur fragen, was die Zusammenfassung meldet; ohne Zusammenfassung (-1) trotzdem.
  if (ASummary.SubIssues <> 0) and (Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/sub_issues?per_page=' + IntToStr(MaxPageSize), Remaining(AWatch, ATimeoutMs), mStatus,
    mText, mIgnored) and (mStatus = 200) and ParseRelated(mText, ATarget.Project, TAtlasTrackerLinkKind.Subtask,
    mLinks) then
    MergeLinks(ADetails.Links, mLinks);
  mBlockers := False;
  if (ASummary.BlockedBy <> 0) and (Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/dependencies/blocked_by?per_page=' + IntToStr(MaxPageSize), Remaining(AWatch,
    ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and ParseRelated(mText, ATarget.Project,
    TAtlasTrackerLinkKind.DependsOn, mLinks) then
  begin
    MergeLinks(ADetails.Links, mLinks);
    mBlockers := Length(mLinks) > 0;
  end;
  if (ASummary.Blocking <> 0) and (Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/dependencies/blocking?per_page=' + IntToStr(MaxPageSize), Remaining(AWatch,
    ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and ParseRelated(mText, ATarget.Project,
    TAtlasTrackerLinkKind.Blocks, mLinks) then
    MergeLinks(ADetails.Links, mLinks);
  if mBlockers then
    Exit;
  // Ohne „blocked by“: Abhängigkeiten aus dem Text, Zustand je Issue nachgefragt.
  for mNumber in TAtlasTrackerLinks.TextDependencies(ADetails.Description) do
  begin
    if mNumber = ADetails.Number then
      Continue;
    mLink := Default(TAtlasTrackerLink);
    mLink.Key := '#' + IntToStr(mNumber);
    mKnown := False;
    for mIndex := 0 to High(ADetails.Links) do
      if SameText(ADetails.Links[mIndex].Key, mLink.Key) and
        (ADetails.Links[mIndex].Kind = TAtlasTrackerLinkKind.DependsOn) then
        mKnown := True;
    if mKnown then
      Continue;
    mLink.Local := True;
    mLink.Kind := TAtlasTrackerLinkKind.DependsOn;
    mLink.Relation := 'depends on';
    mLink.Page := IssuePage(ATarget, mLink.Key);
    if (Remaining(AWatch, ATimeoutMs) > 0) and ATransport.Get(IssueApiUrl(ATarget, mLink.Key),
      Remaining(AWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      ParseDetails(mText, mOther, mCount) then
    begin
      mLink.Title := Shorten(mOther.Title, 200);
      mLink.State := mOther.State;
      mLink.StateKnown := True;
      mLink.Resolved := StartsText('closed', mOther.State);
    end;
    MergeLinks(ADetails.Links, TArray<TAtlasTrackerLink>.Create(mLink));
  end;
end;

/// <summary>Interne ID des Issues AKey über GET; 0 mit AError.</summary>
function IssueId(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
  ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Int64;
var
  mStatus: Integer;
  mText: string;
begin
  Result := 0;
  if not ATransport.Get(TAtlasGitHubTracker.IssueApiUrl(ATarget, AKey), ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := TAtlasGitHubTracker.ParseIssueId(mText);
  if Result = 0 then
    AError := TAtlasCiFetchError.Invalid;
end;

/// <summary>POST mit AStatus 200/201 als Erfolg.</summary>
function Posted(const APost: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
begin
  Result := False;
  if not APost.Send('POST', AUrl, ABody, ATimeoutMs, mStatus, AText, AError) then
    Exit;
  if (mStatus <> 200) and (mStatus <> 201) then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function TAtlasGitHubTracker.CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mWatch: TStopwatch;
  mParent, mText: string;
  mId: Int64;
  mNumber: Integer;
  mValue: TJSONValue;
begin
  AKey := '';
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  mParent := IssueApiUrl(ATarget, AParentKey);
  if (mParent = '') or (ATransport = nil) or not Supports(ATransport, IAtlasCiSend, mPost) then
    Exit;
  if Trim(ATitle) = '' then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not Posted(mPost, ApiBase(ATarget) + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/issues',
    NewIssueBody(ATitle, ADescription), ATimeoutMs, mText, AError) then
    Exit;
  mId := ParseIssueId(mText);
  mNumber := 0;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if mValue is TJSONObject then
      mNumber := IntOf(TJSONObject(mValue), 'number');
  finally
    mValue.Free;
  end;
  if (mId = 0) or (mNumber = 0) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  AKey := '#' + IntToStr(mNumber);
  Result := Posted(mPost, mParent + '/sub_issues', IdBody('sub_issue_id', mId), Remaining(mWatch, ATimeoutMs),
    mText, AError);
end;

function TAtlasGitHubTracker.AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mWatch: TStopwatch;
  mBlocked, mBlocker, mText: string;
  mId: Int64;
begin
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ATransport = nil) or not Supports(ATransport, IAtlasCiSend, mPost) then
    Exit;
  // „hängt ab von“: AKey wird von AOtherKey blockiert; „blockiert“: umgekehrt.
  if AKind = TAtlasTrackerLinkKind.DependsOn then
  begin
    mBlocked := AKey;
    mBlocker := AOtherKey;
  end
  else if AKind = TAtlasTrackerLinkKind.Blocks then
  begin
    mBlocked := AOtherKey;
    mBlocker := AKey;
  end
  else
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if (IssueApiUrl(ATarget, mBlocked) = '') or (IssueApiUrl(ATarget, mBlocker) = '') or
    (NumberOfKey(mBlocked) = NumberOfKey(mBlocker)) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  mId := IssueId(ATarget, ATransport, mBlocker, ATimeoutMs, AError);
  if mId = 0 then
    Exit;
  Result := Posted(mPost, IssueApiUrl(ATarget, mBlocked) + '/dependencies/blocked_by', IdBody('issue_id', mId),
    Remaining(mWatch, ATimeoutMs), mText, AError);
end;

{ Board (#1272) }

/// <summary>ISO 8601 ("2026-10-28T09:12:00Z") als UTC; 0 ohne.</summary>
function TimeOfText(const AText: string): TDateTime;
begin
  Result := 0;
  if (AText = '') or not TryISO8601ToDate(AText, Result, True) then
    Result := 0;
end;

/// <summary>Objekt unter einem Pfad aus Namen ("data", "node"); nil, wenn ein Teil fehlt.</summary>
function ObjectAt(AValue: TJSONValue; const APath: array of string): TJSONObject;
var
  mName: string;
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := AValue;
  for mName in APath do
  begin
    if not (mValue is TJSONObject) then
      Exit;
    mValue := TJSONObject(mValue).Values[mName];
  end;
  if mValue is TJSONObject then
    Result := TJSONObject(mValue);
end;

/// <summary>Liste "nodes" eines Objekts; nil ohne.</summary>
function NodesOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.Values[AName];
  if mValue is TJSONObject then
    mValue := TJSONObject(mValue).Values['nodes'];
  if mValue is TJSONArray then
    Result := TJSONArray(mValue);
end;

function Rest(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  mRest: Int64;
begin
  mRest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if mRest > 0 then
    Result := Integer(mRest);
end;

{ TAtlasGitHubBoards }

class function TAtlasGitHubBoards.GraphQlUrl(const ATarget: TAtlasTrackerTarget): string;
var
  mBase: string;
begin
  Result := '';
  mBase := TAtlasGitHubTracker.ApiBase(ATarget);
  if mBase = '' then
    Exit;
  if mBase = TAtlasGitHubTracker.ApiHost then
    Result := mBase + '/graphql'
  else
    Result := ATarget.Server + '/api/graphql';
end;

class function TAtlasGitHubBoards.GraphQlBody(const AQuery: string; const AVariables: array of string): string;
var
  mRoot, mVariables: TJSONObject;
  mIndex: Integer;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('query', AQuery);
    mVariables := TJSONObject.Create;
    mIndex := 0;
    while mIndex + 1 <= High(AVariables) do
    begin
      mVariables.AddPair(AVariables[mIndex], AVariables[mIndex + 1]);
      Inc(mIndex, 2);
    end;
    mRoot.AddPair('variables', mVariables);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubBoards.GraphQlError(const AJson: string; out AMessage: string): TAtlasCiFetchError;
var
  mValue, mItem: TJSONValue;
  mType: string;
begin
  AMessage := '';
  Result := TAtlasCiFetchError.None;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit(TAtlasCiFetchError.Invalid);
    if not (TJSONObject(mValue).Values['errors'] is TJSONArray) then
      Exit;
    for mItem in TJSONArray(TJSONObject(mValue).Values['errors']) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      if AMessage = '' then
        AMessage := Copy(TextOf(TJSONObject(mItem), 'message'), 1, 300);
      mType := UpperCase(TextOf(TJSONObject(mItem), 'type'));
      if (mType = 'INSUFFICIENT_SCOPES') or (mType = 'FORBIDDEN') then
        Exit(TAtlasCiFetchError.Unauthorized);
      if mType = 'NOT_FOUND' then
        Result := TAtlasCiFetchError.NotFound;
    end;
    if Result = TAtlasCiFetchError.None then
      Result := TAtlasCiFetchError.Invalid;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubBoards.ParseProjects(const AJson: string; var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem: TJSONValue;
  mViewer, mProject: TJSONObject;
  mNodes: TJSONArray;
  mOpen, mClosed: TArray<TAtlasBoardRef>;
  mRef: TAtlasBoardRef;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mViewer := ObjectAt(mValue, ['data', 'viewer']);
    if mViewer <> nil then
      ASnapshot.Me := TextOf(mViewer, 'login');
    mOpen := nil;
    mClosed := nil;
    mNodes := NodesOf(ObjectAt(mValue, ['data', 'repository']), 'projectsV2');
    if mNodes <> nil then
      for mItem in mNodes do
      begin
        if not (mItem is TJSONObject) then
          Continue;
        mProject := TJSONObject(mItem);
        mRef := TAtlasBoardRef.Create(TextOf(mProject, 'id'), TextOf(mProject, 'title'));
        if mRef.Id = '' then
          Continue;
        if FlagOf(mProject, 'closed') then
          mClosed := mClosed + [mRef]
        else
          mOpen := mOpen + [mRef];
      end;
    ASnapshot.Boards := Copy(mOpen + mClosed, 0, TAtlasBoardSnapshot.MaxBoards);
    Result := True;
  finally
    mValue.Free;
  end;
end;

function IterationOf(AObject: TJSONObject): TAtlasBoardSprint;
var
  mStart: TDateTime;
begin
  Result := Default(TAtlasBoardSprint);
  Result.Id := TextOf(AObject, 'id');
  Result.Name := TextOf(AObject, 'title');
  // startDate "2026-10-27" (Tag, UTC), duration in Tagen.
  if TryISO8601ToDate(TextOf(AObject, 'startDate'), mStart, True) then
  begin
    Result.Start := mStart;
    if IntOf(AObject, 'duration') > 0 then
      Result.Finish := mStart + IntOf(AObject, 'duration');
  end;
end;

/// <summary>Zahlenfeld als Schätzung (#1277): "Estimate", "Story Points", "Points", "Size", deutsch ebenso.
/// </summary>
function IsPointsName(const AName: string): Boolean;
const
  Names: array[0..7] of string = ('Estimate', 'Estimation', 'Story Points', 'Points', 'Size', 'Schätzung',
    'Punkte', 'Aufwand');
var
  mName: string;
begin
  Result := False;
  for mName in Names do
    if SameText(Trim(AName), mName) then
      Exit(True);
end;

/// <summary>Spalten, Feld, Schätzfeld und Sprints aus fields.</summary>
procedure ReadFields(AProject: TJSONObject; var ASnapshot: TAtlasBoardSnapshot; out AIteration, APriority: string);
var
  mNodes, mOptions: TJSONArray;
  mItem, mOption: TJSONValue;
  mField, mChosen, mFirst, mConfig: TJSONObject;
  mSprint: TAtlasBoardSprint;
  mName: string;
begin
  AIteration := '';
  APriority := '';
  mChosen := nil;
  mFirst := nil;
  ASnapshot.Columns := nil;
  ASnapshot.Sprints := nil;
  ASnapshot.PointsField := '';
  mNodes := NodesOf(AProject, 'fields');
  if mNodes = nil then
    Exit;
  for mItem in mNodes do
  begin
    if not (mItem is TJSONObject) then
      Continue;
    mField := TJSONObject(mItem);
    mName := TextOf(mField, 'name');
    if mField.Values['options'] is TJSONArray then
    begin
      // Auswahlfeld: „Status“ geht vor, sonst das erste außer der Priorität; diese gibt den Farbbalken.
      if SameText(mName, 'Priority') or SameText(mName, 'Priorität') then
        APriority := mName
      else if SameText(mName, 'Status') then
        mChosen := mField
      else if (mChosen = nil) and (mFirst = nil) then
        mFirst := mField;
    end
    else if (ASnapshot.PointsField = '') and SameText(TextOf(mField, 'dataType'), 'NUMBER') and
      IsPointsName(mName) then
      ASnapshot.PointsField := mName
    else if (AIteration = '') and (mField.Values['configuration'] is TJSONObject) then
    begin
      AIteration := mName;
      mConfig := TJSONObject(mField.Values['configuration']);
      // Laufende und künftige, dann abgeschlossene.
      if mConfig.Values['iterations'] is TJSONArray then
        for mOption in TJSONArray(mConfig.Values['iterations']) do
          if mOption is TJSONObject then
            ASnapshot.Sprints := ASnapshot.Sprints + [IterationOf(TJSONObject(mOption))];
      if mConfig.Values['completedIterations'] is TJSONArray then
        for mOption in TJSONArray(mConfig.Values['completedIterations']) do
          if mOption is TJSONObject then
          begin
            mSprint := IterationOf(TJSONObject(mOption));
            mSprint.Archived := True;
            ASnapshot.Sprints := ASnapshot.Sprints + [mSprint];
          end;
      ASnapshot.Sprints := Copy(ASnapshot.Sprints, 0, TAtlasBoardSnapshot.MaxSprints);
    end;
  end;
  if mChosen = nil then
    mChosen := mFirst;
  if mChosen = nil then
    Exit;
  ASnapshot.Field := TextOf(mChosen, 'name');
  ASnapshot.FieldId := TextOf(mChosen, 'id');
  mOptions := TJSONArray(mChosen.Values['options']);
  for mOption in mOptions do
    if (mOption is TJSONObject) and (TextOf(TJSONObject(mOption), 'name') <> '') then
      ASnapshot.Columns := ASnapshot.Columns + [TAtlasBoardColumn.Create(TextOf(TJSONObject(mOption), 'name'),
        TArray<string>.Create(TextOf(TJSONObject(mOption), 'name')), TextOf(TJSONObject(mOption), 'id'),
        TAtlasGitHubTracker.ClosesIssue(TextOf(TJSONObject(mOption), 'name')))];
end;

/// <summary>Kennung eines Issues: "#12" im Repository des Ziels, sonst "owner/repo#12".</summary>
function KeyOf(AIssue: TJSONObject; const AProject: string): string;
var
  mRepository: string;
begin
  Result := '#' + IntToStr(IntOf(AIssue, 'number'));
  mRepository := '';
  if AIssue.Values['repository'] is TJSONObject then
    mRepository := TextOf(TJSONObject(AIssue.Values['repository']), 'nameWithOwner');
  if (mRepository <> '') and not SameText(mRepository, AProject) then
    Result := mRepository + Result;
end;

/// <summary>Zuständige aus assignees (GraphQL: nodes, REST: Liste).</summary>
procedure ReadAssignees(AValue: TJSONValue; var ACard: TAtlasBoardCard);
var
  mItem: TJSONValue;
  mName: string;
begin
  if AValue is TJSONObject then
    AValue := TJSONObject(AValue).Values['nodes'];
  if not (AValue is TJSONArray) then
    Exit;
  for mItem in TJSONArray(AValue) do
  begin
    if not (mItem is TJSONObject) or (TextOf(TJSONObject(mItem), 'login') = '') then
      Continue;
    ACard.Logins := ACard.Logins + [TextOf(TJSONObject(mItem), 'login')];
    if ACard.Assignee = '' then
    begin
      mName := TextOf(TJSONObject(mItem), 'name');
      if mName = '' then
        mName := TextOf(TJSONObject(mItem), 'login');
      ACard.Assignee := mName;
    end;
  end;
end;

class function TAtlasGitHubBoards.ParseProject(const AJson: string; const ATarget: TAtlasTrackerTarget;
  const ASprintId: string; ANow: TDateTime; var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem, mField: TJSONValue;
  mProject, mEntry, mIssue, mFieldName: TJSONObject;
  mNodes, mValues: TJSONArray;
  mIteration, mPriority, mItemIteration, mName: string;
  mSprint, mIndex: Integer;
  mCard: TAtlasBoardCard;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mProject := ObjectAt(mValue, ['data', 'node']);
    if (mProject = nil) or (TextOf(mProject, 'id') = '') then
      Exit;
    ASnapshot.Kind := TAtlasBoardKind.Project;
    ASnapshot.ProjectId := TextOf(mProject, 'id');
    ASnapshot.Board := TAtlasBoardRef.Create(ASnapshot.ProjectId, TextOf(mProject, 'title'));
    ASnapshot.Page := TextOf(mProject, 'url');
    ReadFields(mProject, ASnapshot, mIteration, mPriority);
    // Sprint: gewählt, sonst der aktuelle.
    ASnapshot.Sprint := Default(TAtlasBoardSprint);
    mSprint := -1;
    for mIndex := 0 to High(ASnapshot.Sprints) do
      if (ASprintId <> '') and SameText(ASnapshot.Sprints[mIndex].Id, ASprintId) then
        mSprint := mIndex;
    if mSprint < 0 then
      mSprint := TAtlasTrackerBoard.CurrentSprint(ASnapshot.Sprints, ANow);
    if mSprint >= 0 then
      ASnapshot.Sprint := ASnapshot.Sprints[mSprint];
    ASnapshot.Cards := nil;
    mNodes := NodesOf(mProject, 'items');
    if mNodes <> nil then
      for mItem in mNodes do
      begin
        if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
          Continue;
        mEntry := TJSONObject(mItem);
        mIssue := ObjectAt(mEntry, ['content']);
        // Nur Issues; Pull Requests und Entwürfe haben hier keinen Inhalt.
        if (mIssue = nil) or (IntOf(mIssue, 'number') <= 0) then
          Continue;
        mCard := Default(TAtlasBoardCard);
        mCard.ItemId := TextOf(mEntry, 'id');
        mCard.Number := IntOf(mIssue, 'number');
        mCard.Key := KeyOf(mIssue, ATarget.Project);
        mCard.Title := Copy(TextOf(mIssue, 'title'), 1, TAtlasBoardCard.MaxTitle);
        mCard.Page := TextOf(mIssue, 'url');
        mCard.Checklist := TAtlasTrackerChecklist.Progress(TextOf(mIssue, 'body'));
        mCard.ResolvedAt := TimeOfText(TextOf(mIssue, 'closedAt'));
        ReadAssignees(mIssue.Values['assignees'], mCard);
        mItemIteration := '';
        mValues := NodesOf(mEntry, 'fieldValues');
        if mValues <> nil then
          for mField in mValues do
          begin
            if not (mField is TJSONObject) then
              Continue;
            mFieldName := ObjectAt(mField, ['field']);
            mName := '';
            if mFieldName <> nil then
              mName := TextOf(mFieldName, 'name');
            if TJSONObject(mField).Values['iterationId'] is TJSONString then
            begin
              if SameText(mName, mIteration) then
                mItemIteration := TextOf(TJSONObject(mField), 'iterationId');
            end
            else if TJSONObject(mField).Values['number'] is TJSONNumber then
            begin
              if (ASnapshot.PointsField <> '') and SameText(mName, ASnapshot.PointsField) then
              begin
                mCard.Points := TJSONNumber(TJSONObject(mField).Values['number']).AsDouble;
                mCard.HasPoints := True;
              end;
            end
            else if SameText(mName, ASnapshot.Field) then
              mCard.State := TextOf(TJSONObject(mField), 'name')
            else if (mPriority <> '') and SameText(mName, mPriority) then
              mCard.Priority := TextOf(TJSONObject(mField), 'name');
          end;
        // Mit Iterationen nur die Karten des Sprints.
        if (ASnapshot.Sprint.Id <> '') and not SameText(mItemIteration, ASnapshot.Sprint.Id) then
          Continue;
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
      end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubBoards.ParseIssues(const AJson: string; const ATarget: TAtlasTrackerTarget;
  var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem: TJSONValue;
  mIssue: TJSONObject;
  mCard: TAtlasBoardCard;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
      Exit;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
        Continue;
      mIssue := TJSONObject(mItem);
      // /issues enthält auch Pull Requests.
      if (mIssue.Values['pull_request'] <> nil) or (IntOf(mIssue, 'number') <= 0) then
        Continue;
      mCard := Default(TAtlasBoardCard);
      mCard.Number := IntOf(mIssue, 'number');
      mCard.Key := '#' + IntToStr(mCard.Number);
      mCard.Title := Copy(TextOf(mIssue, 'title'), 1, TAtlasBoardCard.MaxTitle);
      mCard.State := LowerCase(TextOf(mIssue, 'state'));
      mCard.Page := TextOf(mIssue, 'html_url');
      mCard.Checklist := TAtlasTrackerChecklist.Progress(TextOf(mIssue, 'body'));
      mCard.ResolvedAt := TimeOfText(TextOf(mIssue, 'closed_at'));
      ReadAssignees(mIssue.Values['assignees'], mCard);
      if ASnapshot.CardIndex(mCard.Key) < 0 then
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>GraphQL-Anfrage; True nur mit Antwort ohne "errors".</summary>
function Query(const ASend: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mMessage: string;
begin
  Result := False;
  if not ASend.Send('POST', AUrl, ABody, ATimeoutMs, mStatus, AText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  AError := TAtlasGitHubBoards.GraphQlError(AText, mMessage);
  Result := AError = TAtlasCiFetchError.None;
end;

function GetText(const ATransport: IAtlasCiTransport; const AUrl: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
begin
  Result := False;
  if not ATransport.Get(AUrl, ATimeoutMs, mStatus, AText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := True;
end;

/// <summary>Ohne Projekt: Spalten Offen und Geschlossen, Karten aus /issues, Anmeldename aus /user.</summary>
function LoadRepository(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AWatch: TStopwatch; ATimeoutMs: Integer; var ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mBase, mText: string;
  mValue: TJSONValue;
  mError: TAtlasCiFetchError;
begin
  Result := False;
  ASnapshot.Kind := TAtlasBoardKind.Repository;
  ASnapshot.Board := TAtlasBoardRef.Create('', '');
  ASnapshot.Field := 'state';
  ASnapshot.Columns := [TAtlasBoardColumn.Create('open', TArray<string>.Create('open'), '', False),
    TAtlasBoardColumn.Create('closed', TArray<string>.Create('closed'), '', True)];
  ASnapshot.Cards := nil;
  ASnapshot.PointsField := '';
  // Board im Browser: die Issues des Repositorys.
  ASnapshot.Page := (TAtlasGitHubTracker.Create as IAtlasTrackerProvider).IssuePage(ATarget, '#1');
  if ASnapshot.Page <> '' then
    SetLength(ASnapshot.Page, Length(ASnapshot.Page) - Length('/1'));
  mBase := TAtlasGitHubTracker.ApiBase(ATarget) + '/repos/' + ATarget.Project + '/issues';
  if not GetText(ATransport, mBase + '?state=open&per_page=100', Rest(AWatch, ATimeoutMs), mText, AError) then
    Exit;
  if not TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if GetText(ATransport, mBase + '?state=closed&sort=updated&per_page=' + IntToStr(TAtlasGitHubBoards.MaxClosed),
    Rest(AWatch, ATimeoutMs), mText, mError) then
    TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot);
  if (ASnapshot.Me = '') and GetText(ATransport, TAtlasGitHubTracker.ApiBase(ATarget) + '/user',
    Rest(AWatch, ATimeoutMs), mText, mError) then
  begin
    mValue := TJSONObject.ParseJSONValue(mText);
    try
      if mValue is TJSONObject then
        ASnapshot.Me := TextOf(TJSONObject(mValue), 'login');
    finally
      mValue.Free;
    end;
  end;
  Result := True;
end;

function TAtlasGitHubBoards.LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mUrl, mText, mOwner, mName, mProject: string;
  mIndex: Integer;
  mError: TAtlasCiFetchError;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := GraphQlUrl(ATarget);
  mIndex := Pos('/', ATarget.Project);
  if (mUrl = '') or (mIndex <= 1) or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mOwner := Copy(ATarget.Project, 1, mIndex - 1);
  mName := Copy(ATarget.Project, mIndex + 1, MaxInt);
  mWatch := TStopwatch.StartNew;
  // GraphQL braucht POST; ohne Schreibweg bleibt nur die Liste ohne Projekt.
  mProject := '';
  mError := TAtlasCiFetchError.None;
  if Supports(ATransport, IAtlasCiSend, mSend) and Query(mSend, mUrl,
    GraphQlBody(ProjectsQuery, ['owner', mOwner, 'name', mName]), ATimeoutMs, mText, mError) and
    ParseProjects(mText, ASnapshot) then
  begin
    for mIndex := 0 to High(ASnapshot.Boards) do
      if (ABoardId <> '') and SameText(ASnapshot.Boards[mIndex].Id, ABoardId) then
        mProject := ASnapshot.Boards[mIndex].Id;
    if (mProject = '') and (Length(ASnapshot.Boards) > 0) then
      mProject := ASnapshot.Boards[0].Id;
  end;
  if mProject = '' then
  begin
    Result := LoadRepository(ATarget, ATransport, mWatch, ATimeoutMs, ASnapshot, AError);
    ASnapshot.ProjectsDenied := mError = TAtlasCiFetchError.Unauthorized;
    Exit;
  end;
  if not Query(mSend, mUrl, GraphQlBody(ProjectQuery, ['id', mProject]), Rest(mWatch, ATimeoutMs), mText, AError) then
    Exit;
  if not ParseProject(mText, ATarget, ASprintId, TTimeZone.Local.ToUniversalTime(Now), ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasGitHubBoards.MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
  ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mWriter: IAtlasTrackerWriter;
  mUrl, mText, mMessage, mBody: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
  mColumn: TAtlasBoardColumn;
begin
  if (AColumn < 0) or (AColumn > High(ASnapshot.Columns)) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  if not Supports(ATransport, IAtlasCiSend, mSend) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  mColumn := ASnapshot.Columns[AColumn];
  mWatch := TStopwatch.StartNew;
  // Zuerst der Kommentar (#1266): Fehlen die Schreibrechte, ändert sich nichts. Nur im Repository des Ziels.
  if (Trim(AComment) <> '') and (Copy(ACard.Key, 1, 1) = '#') then
  begin
    mWriter := TAtlasGitHubTracker.Create;
    Result := mWriter.Apply(ATarget, ATransport, ACard.Key, TAtlasTrackerChange.CommentOnly(AComment), ATimeoutMs);
    if not Result.Succeeded then
      Exit;
  end;
  if ASnapshot.Kind = TAtlasBoardKind.Project then
  begin
    if (mColumn.OptionId = '') or (ACard.ItemId = '') or (ASnapshot.FieldId = '') then
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
    mBody := GraphQlBody(MoveMutation, ['project', ASnapshot.ProjectId, 'item', ACard.ItemId, 'field',
      ASnapshot.FieldId, 'option', mColumn.OptionId]);
    if not mSend.Send('POST', GraphQlUrl(ATarget), mBody, Rest(mWatch, ATimeoutMs), mStatus, mText, mError) then
      Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
    if mStatus <> 200 then
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubTracker.ErrorOfStatus(mStatus), mStatus,
        TAtlasGitHubTracker.ErrorMessage(mText)));
    mError := GraphQlError(mText, mMessage);
    if mError <> TAtlasCiFetchError.None then
      Exit(TAtlasTrackerWriteResult.Failed(mError, mStatus, mMessage));
    Exit(TAtlasTrackerWriteResult.Ok);
  end;
  // Ohne Projekt: Zustand des Issues.
  mUrl := TAtlasGitHubTracker.IssueApiUrl(ATarget, ACard.Key);
  if (mUrl = '') or (Length(mColumn.Values) = 0) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  mBody := '{"state":"open"}';
  if mColumn.Resolved then
    mBody := '{"state":"closed"}';
  if not mSend.Send('PATCH', mUrl, mBody, Rest(mWatch, ATimeoutMs), mStatus, mText, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if not Answered(mStatus) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubTracker.ErrorOfStatus(mStatus), mStatus,
      TAtlasGitHubTracker.ErrorMessage(mText)));
  Result := TAtlasTrackerWriteResult.Ok;
end;

{ TAtlasGitHubTracker: IAtlasTrackerBoards }

function TAtlasGitHubTracker.LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasGitHubBoards.Create;
  Result := mBoards.LoadBoard(ATarget, ATransport, ABoardId, ASprintId, ATimeoutMs, ASnapshot, AError);
end;

function TAtlasGitHubTracker.MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
  ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasGitHubBoards.Create;
  Result := mBoards.MoveCard(ATarget, ATransport, ASnapshot, ACard, AColumn, AComment, ATimeoutMs);
end;

function TAtlasGitHubTracker.Search(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AText: string; ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TextSearchUrl(ATarget, AText, AMax);
  if not ATarget.Configured or (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseIssues(mText, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasGitHubTracker.Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus, mComments: Integer;
  mDetails: TAtlasTrackerDetails;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseDetails(mText, mDetails, mComments) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  AIssue := mDetails.Issue;
  Result := True;
end;

function TAtlasGitHubTracker.Users(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AText: string; ATimeoutMs, AMax: Integer; out AUsers: TArray<TAtlasTrackerUser>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
  mUsers: TArray<TAtlasTrackerUser>;
begin
  AUsers := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := AssigneesUrl(ATarget);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseUsers(mText, mUsers) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  // GitHub filtert …/assignees nicht: der getippte Text entscheidet hier.
  AUsers := TAtlasTrackerUser.Filter(mUsers, AText, AMax);
  Result := True;
end;

function TAtlasGitHubTracker.Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mUrl, mText: string;
  mStatus, mNumber, mChecked: Integer;
  mPulls: TArray<TAtlasGitHubPull>;
  mGitHubPull: TAtlasGitHubPull;
  mPull: TAtlasTrackerPull;
  mChecks: TAtlasTrackerChecks;
  mIgnored: TAtlasCiFetchError;
begin
  ADevelopment := TAtlasTrackerDevelopment.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := AllPullsUrl(ATarget);
  mNumber := NumberOfKey(AKey);
  if (mUrl = '') or (mNumber = 0) or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParsePulls(mText, mPulls) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
  AError := TAtlasCiFetchError.None;
  mChecked := 0;
  for mGitHubPull in mPulls do
  begin
    if not PullRefersTo(mGitHubPull, mNumber) then
      Continue;
    if Length(ADevelopment.Pulls) >= TAtlasTrackerDevelopment.MaxPulls then
      Break;
    mPull := Default(TAtlasTrackerPull);
    mPull.Number := mGitHubPull.Number;
    mPull.Title := Shorten(mGitHubPull.Title, TAtlasTrackerIssue.MaxTitle);
    mPull.Branch := mGitHubPull.Branch;
    mPull.State := PullState(mGitHubPull);
    mPull.Updated := mGitHubPull.Updated;
    mPull.Page := PullRequestPage(ATarget, mGitHubPull.Number);
    mPull.Checks := TAtlasTrackerChecks.Unknown;
    // Ampel in der restlichen Zeit, wie in der Liste: Check Runs, sonst der kombinierte Status.
    if (mChecked < MaxChecks) and (Remaining(mWatch, ATimeoutMs) > 0) and
      (CheckRunsUrl(ATarget, mGitHubPull.Sha) <> '') then
    begin
      Inc(mChecked);
      mChecks := TAtlasTrackerChecks.Unknown;
      if ATransport.Get(CheckRunsUrl(ATarget, mGitHubPull.Sha), Remaining(mWatch, ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) then
        ParseCheckRuns(mText, mChecks);
      if (mChecks = TAtlasTrackerChecks.Unknown) and (Remaining(mWatch, ATimeoutMs) > 0) and
        ATransport.Get(StatusUrl(ATarget, mGitHubPull.Sha), Remaining(mWatch, ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) then
        ParseStatus(mText, mChecks);
      mPull.Checks := mChecks;
    end;
    ADevelopment.Pulls := ADevelopment.Pulls + [mPull];
  end;
end;

class function TAtlasGitHubTracker.IsoTime(ATime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', ATime);
end;

class function TAtlasGitHubTracker.NotificationsUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime): string;
begin
  Result := ApiBase(ATarget);
  if Result <> '' then
    Result := Result + '/notifications?since=' + TTextUris.PercentEncode(IsoTime(ASince)) + '&per_page=50';
end;

/// <summary>"owner/repo" und Nummer aus ".../repos/owner/repo/issues/12"; False bei anderer Adresse.</summary>
function IssueOfApiUrl(const AUrl: string; out ARepository: string; out ANumber: Integer): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  Result := False;
  ARepository := '';
  ANumber := 0;
  mParts := AUrl.Split(['/']);
  for mIndex := 0 to High(mParts) - 4 do
    if (mParts[mIndex] = 'repos') and (mParts[mIndex + 3] = 'issues') and
      TryStrToInt(mParts[mIndex + 4], ANumber) and (ANumber > 0) then
    begin
      ARepository := mParts[mIndex + 1] + '/' + mParts[mIndex + 2];
      Exit(True);
    end;
end;

class function TAtlasGitHubTracker.ParseNotifications(const AJson: string; ASince: TDateTime;
  out AThreads: TArray<TAtlasGitHubThread>): Boolean;
var
  mValue, mItem: TJSONValue;
  mObject, mSubject: TJSONObject;
  mThread: TAtlasGitHubThread;
begin
  AThreads := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mObject := TJSONObject(mItem);
      if not (mObject.Values['subject'] is TJSONObject) then
        Continue;
      mSubject := TJSONObject(mObject.Values['subject']);
      // Nur Issues; Pull Requests, Releases und Diskussionen nicht.
      if not SameText(TextOf(mSubject, 'type'), 'Issue') then
        Continue;
      mThread := Default(TAtlasGitHubThread);
      if not IssueOfApiUrl(TextOf(mSubject, 'url'), mThread.Repository, mThread.Number) then
        Continue;
      mThread.Title := Shorten(TextOf(mSubject, 'title'), TAtlasTrackerIssue.MaxTitle);
      mThread.Reason := LowerCase(TextOf(mObject, 'reason'));
      mThread.Updated := TimeOf(mObject, 'updated_at');
      if mThread.Updated > ASince then
        AThreads := AThreads + [mThread];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.InScope(const AReason: string; AScope: TAtlasTrackerNotifyScope): Boolean;
begin
  case AScope of
    TAtlasTrackerNotifyScope.Assigned:
      Result := SameText(AReason, 'assign');
    TAtlasTrackerNotifyScope.AssignedOrCreated:
      Result := SameText(AReason, 'assign') or SameText(AReason, 'author');
  else
    Result := True;
  end;
end;

function ChangeOf(const AThread: TAtlasGitHubThread; AKind: TAtlasTrackerChangeKind; const AAuthor: string;
  ATime: TDateTime): TAtlasTrackerChange;
begin
  Result := TAtlasTrackerChange.Create('#' + IntToStr(AThread.Number), AKind, AAuthor, ATime);
  Result.Project := AThread.Repository;
  Result.Title := AThread.Title;
end;

class function TAtlasGitHubTracker.ParseCommentChanges(const AJson: string; const AThread: TAtlasGitHubThread;
  ASince: TDateTime; out AChanges: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mTime: TDateTime;
begin
  AChanges := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      // since= filtert nach der letzten Bearbeitung; neu ist nur, was danach angelegt wurde.
      mTime := TimeOf(TJSONObject(mItem), 'created_at');
      if mTime > ASince then
        AChanges := AChanges + [ChangeOf(AThread, TAtlasTrackerChangeKind.Comment,
          LoginOf(TJSONObject(mItem).Values['user']), mTime)];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseEventChanges(const AJson: string; const AThread: TAtlasGitHubThread;
  const AMe: string; ASince: TDateTime; out AChanges: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mObject: TJSONObject;
  mEvent: string;
  mChange: TAtlasTrackerChange;
  mTime: TDateTime;
begin
  AChanges := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mObject := TJSONObject(mItem);
      mTime := TimeOf(mObject, 'created_at');
      if mTime <= ASince then
        Continue;
      mEvent := LowerCase(TextOf(mObject, 'event'));
      if mEvent = 'assigned' then
      begin
        mChange := ChangeOf(AThread, TAtlasTrackerChangeKind.Assigned, LoginOf(mObject.Values['actor']), mTime);
        mChange.Value := LoginOf(mObject.Values['assignee']);
        mChange.ToMe := (AMe <> '') and SameText(mChange.Value, AMe);
      end
      else if (mEvent = 'closed') or (mEvent = 'reopened') then
      begin
        mChange := ChangeOf(AThread, TAtlasTrackerChangeKind.State, LoginOf(mObject.Values['actor']), mTime);
        // Zustand wie bei GitHub; die Oberfläche übersetzt "closed" und "open".
        if mEvent = 'closed' then
          mChange.Value := 'closed'
        else
          mChange.Value := 'open';
      end
      else
        Continue;
      AChanges := AChanges + [mChange];
    end;
  finally
    mValue.Free;
  end;
end;

function TAtlasGitHubTracker.Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mConditional: IAtlasCiConditional;
  mStatus, mPoll, mCount, mIndex: Integer;
  mText, mLastModified, mBase, mIssueUrl: string;
  mThreads: TArray<TAtlasGitHubThread>;
  mThread: TAtlasGitHubThread;
  mFound, mMore: TArray<TAtlasTrackerChange>;
  mIgnored: TAtlasCiFetchError;
  mAnswered: Boolean;
begin
  AChanges := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mBase := ApiBase(ATarget);
  if (mBase = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  mPoll := 0;
  mLastModified := '';
  if Supports(ATransport, IAtlasCiConditional, mConditional) then
    mAnswered := mConditional.GetConditional(NotificationsUrl(ATarget, APoll.Since), APoll.LastModified, ATimeoutMs,
      mStatus, mText, mLastModified, mPoll, AError)
  else
    mAnswered := ATransport.Get(NotificationsUrl(ATarget, APoll.Since), ATimeoutMs, mStatus, mText, AError);
  if not mAnswered then
    Exit;
  if mPoll > 0 then
    APoll.PollSeconds := mPoll;
  // Unverändert seit der letzten Antwort.
  if mStatus = 304 then
    Exit(True);
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseNotifications(mText, APoll.Since, mThreads) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if mLastModified <> '' then
    APoll.LastModified := mLastModified;
  Result := True;
  mCount := 0;
  for mThread in mThreads do
  begin
    if mThread.Updated > APoll.Latest then
      APoll.Latest := mThread.Updated;
    if not InScope(mThread.Reason, APoll.Scope) or (mCount >= MaxChangedIssues) then
      Continue;
    Inc(mCount);
    mFound := nil;
    mIssueUrl := mBase + '/repos/' + TTextUris.PercentEncode(mThread.Repository) + '/issues/' +
      IntToStr(mThread.Number);
    if (Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mIssueUrl + '/comments?since=' +
      TTextUris.PercentEncode(IsoTime(APoll.Since)) + '&per_page=' + IntToStr(MaxPageSize),
      Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      ParseCommentChanges(mText, mThread, APoll.Since, mMore) then
      mFound := mFound + mMore;
    if (Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mIssueUrl + '/events?per_page=' +
      IntToStr(MaxPageSize), Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      ParseEventChanges(mText, mThread, APoll.Me, APoll.Since, mMore) then
      mFound := mFound + mMore;
    // Nichts Erkennbares (z. B. Erwähnung, ältere Ereignisse auf späteren Seiten): allgemeine Änderung.
    if Length(mFound) = 0 then
      mFound := [ChangeOf(mThread, TAtlasTrackerChangeKind.Other, '', mThread.Updated)];
    AChanges := AChanges + mFound;
  end;
  // Auch ein Kommentar, den GitHub später stempelt als die Benachrichtigung, kommt nicht noch einmal.
  for mIndex := 0 to High(AChanges) do
    if AChanges[mIndex].Time > APoll.Latest then
      APoll.Latest := AChanges[mIndex].Time;
end;

class function TAtlasGitHubTracker.CommentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := IssueApiUrl(ATarget, AKey);
  if Result <> '' then
    Result := Result + '/comments';
end;

function TAtlasGitHubTracker.CanUpload: Boolean;
begin
  Result := False;
end;

function TAtlasGitHubTracker.Upload(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost;
  const AKey: string; const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
begin
  // Die API von GitHub nimmt keine Dateien an; TAtlasAttachSender nimmt dann den Rückfall.
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
end;

function TAtlasGitHubTracker.Comment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey,
  AMarkdown: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
begin
  Result := TAtlasAttachSender.Post(ASend, CommentsUrl(ATarget, AKey), 'application/json',
    TAtlasAttachComment.JsonBody('body', AMarkdown), ATimeoutMs, mStatus, AError);
  if not Result and (mStatus <> 0) then
    AError := ErrorOfStatus(mStatus);
end;

function TAtlasGitHubTracker.CommentText(const AComment: string; const AFiles: TAtlasAttachFiles): string;
begin
  Result := TAtlasAttachComment.WithTexts(AComment, AFiles, TAtlasAttachComment.MaxTextsLength);
end;

end.
