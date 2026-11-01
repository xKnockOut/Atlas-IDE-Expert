unit Atlas.Core.Tracker.MyIssues;

// Bereich „Meine Issues“ der Willkommensseite (#765), Teil ohne VCL und Open
// Tools API: was abgefragt wird, wann, was der Bereich zeigt, welches Issue
// aktiv ist und was „Beginnen“ tut.
// - Ziel: Anbieter, Adresse und Projekt aus .atlas (Abschnitt "tracker");
//   issues.tracker ersetzt den Anbieter. Ohne tracker in der .atlas gilt die
//   persönliche Zuordnung (#1261, issues.projects): Verbindung und
//   Tracker-Projekt der passenden Zeile.
// - Abfrage (#1262): die je Projekt gewählte aus issues.queries
//   (TAtlasTrackerQueries); gemerkt wird ihr Name ("selected") und je Name
//   die Trefferzahl der letzten Abfrage ("counts") für die Klappliste.
// - Abfrage beim Anzeigen, höchstens alle DueMinutes Minuten, Zeitlimit
//   FetchTimeoutMs; ohne Netz bleibt der letzte Stand („Stand vom …“).
// - Aktives Issue: mit „Beginnen“ gemerkt (Branch oder nur gemerkt); sonst
//   aus dem Namen des aktuellen Branchs (Branch → Ticket). Ein mit Branch
//   begonnenes Issue gilt nur auf diesem Branch. „Beenden“ merkt den Branch,
//   damit er das Issue nicht gleich wieder aktiviert.
// - Gespeichert wird im Abschnitt "issues" der Projekt-Zusammenfassung
//   (#592), damit die Seite sofort den letzten Stand zeigt:
//     "issues": {"provider": "github", "server": "https://github.com",
//                "project": "owner/repo", "query": "",
//                "selected": "Mir zugewiesen", "counts": {"Mir zugewiesen": 3},
//                "attempt": "…", "error": "network", "at": "…",
//                "items": [{"key": "#753", "number": 753, "title": "…",
//                           "labels": ["plugin"], "state": "", "priority": "",
//                           "sprint": "", "pr": 760, "checks": "success",
//                           "draft": false}, …],
//                "active": {"key": "#753", "title": "…", "mode": "branch",
//                           "branch": "feature/753-…", "started": "…"},
//                "endedBranch": "feature/612-…", "hook": "yes|no|foreign",
//                "gitDir": "C:\\…\\.git"}
//   Unbekannte Felder im Abschnitt gehen beim Schreiben verloren; die übrige
//   Datei bleibt unverändert (Format 1). Nie Zugangsdaten.

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan;

type
{$SCOPEDENUMS ON}
  /// <summary>issues.start: Branch anlegen oder nur merken.</summary>
  TAtlasIssueStart = (Branch, Remember);
  /// <summary>Was der Bereich zeigt.</summary>
  TAtlasIssuesStatus = (
    /// <summary>Kein Tracker in .atlas (oder unbekannter Anbieter).</summary>
    NotConfigured,
    /// <summary>Noch keine Abfrage zu diesem Ziel.</summary>
    Waiting,
    Ready,
    /// <summary>Letzte Abfrage fehlgeschlagen, ein älterer Stand ist da („Stand vom …“).</summary>
    Stale,
    /// <summary>Fehlgeschlagen ohne älteren Stand.</summary>
    Failed);
  /// <summary>Ergebnis von „Beginnen“.</summary>
  TAtlasIssueStartOutcome = (
    /// <summary>Branch neu angelegt und ausgecheckt.</summary>
    Started,
    /// <summary>Branch gab es schon; ausgecheckt.</summary>
    Switched,
    /// <summary>Nur gemerkt (start=remember oder ohne Git/SVN).</summary>
    Remembered,
    /// <summary>Versionsverwaltung meldete einen Fehler (Reason).</summary>
    Failed,
    /// <summary>Aus dem Muster entsteht kein gültiger Branch-Name.</summary>
    InvalidName);
{$SCOPEDENUMS OFF}

  /// <summary>Aktuelles Issue eines Projekts.</summary>
  TAtlasActiveIssue = record
    Key: string;
    Title: string;
    Mode: TAtlasIssueStart;
    /// <summary>Branch, auf dem es begonnen wurde; '' bei Remember.</summary>
    Branch: string;
    /// <summary>UTC; 0 = aus dem Branch-Namen erkannt.</summary>
    StartedUtc: TDateTime;
    /// <summary>Nur aus dem Branch-Namen erkannt (nicht mit „Beginnen“).</summary>
    FromBranch: Boolean;
    class function Empty: TAtlasActiveIssue; static;
    function Active: Boolean;
  end;

  /// <summary>Trefferzahl der letzten Abfrage mit diesem Namen (#1262).</summary>
  TAtlasIssuesQueryCount = record
    Name: string;
    Count: Integer;
  end;

  /// <summary>Abschnitt "issues" der Zusammenfassung.</summary>
  TAtlasIssuesState = record
    Provider: string;
    Server: string;
    Project: string;
    Query: string;
    /// <summary>Letzter Versuch (UTC); 0 = noch keiner.</summary>
    Attempt: TDateTime;
    Error: TAtlasCiFetchError;
    /// <summary>Letzte gelungene Abfrage (UTC); Items gelten für diesen Stand.</summary>
    At: TDateTime;
    Items: TArray<TAtlasTrackerIssue>;
    Active: TAtlasActiveIssue;
    /// <summary>Branch, dessen erkanntes Issue beendet wurde.</summary>
    EndedBranch: string;
    /// <summary>Zustimmung zum Git-Hook: '' = noch nicht gefragt, "yes", "no", "foreign" (fremder Hook).</summary>
    Hook: string;
    /// <summary>Verwaltungsordner von Git (für die Präfix-Datei des Hooks); '' ohne Git oder unbekannt.</summary>
    GitDir: string;
    /// <summary>Name der gewählten Abfrage (#1262); '' = erste passende.</summary>
    Selected: string;
    Counts: TArray<TAtlasIssuesQueryCount>;
    class function Empty: TAtlasIssuesState; static;
    /// <summary>Die Liste gehört zu ATarget (Anbieter, Server, Projekt und Abfrage gleich).</summary>
    function Matches(const ATarget: TAtlasTrackerTarget): Boolean;
    function Find(const AKey: string; out AIssue: TAtlasTrackerIssue): Boolean;
    /// <summary>Trefferzahl der letzten Abfrage AName; -1 = noch keine.</summary>
    function CountOf(const AName: string): Integer;
    procedure SetCount(const AName: string; ACount: Integer);
  end;

  /// <summary>Einstellungen issues.* für „Beginnen“.</summary>
  TAtlasIssuesOptions = record
    Start: TAtlasIssueStart;
    /// <summary>'' = je Versionsverwaltung (Git feature/{kennung}-{kurztitel}, SVN {kennung}-{kurztitel}).</summary>
    BranchPattern: string;
    /// <summary>'' = Git main (sonst master), SVN trunk.</summary>
    BranchBase: string;
    /// <summary>'' = aus; nicht gekürzt.</summary>
    CommitPattern: string;
    /// <summary>issues.preview (#1264): Klick auf Zeile bzw. Kennung zeigt das Issue in „Atlas-Issue“,
    /// Strg+Klick öffnet den Browser. Create setzt False.</summary>
    Preview: Boolean;
    /// <summary>Hauptbranch des Projekts (#1286, vcs.projects bzw. .atlas); '' = raten. BranchBase hat Vorrang.
    /// Setzt der Aufrufer je Projekt.</summary>
    MainBranch: string;
    /// <summary>SVN-Optionen (#1290, vcs.branch.svn.*): Ort, Quelle, Danach und Nachricht; Create setzt die
    /// Vorgaben, der Aufrufer die Einstellungen und den Projektnamen.</summary>
    Svn: TAtlasVcsSvnBranchOptions;
    class function Create(AStart: TAtlasIssueStart; const ABranchPattern, ABranchBase,
      ACommitPattern: string): TAtlasIssuesOptions; static;
  end;

  /// <summary>Was „Beginnen“ tut.</summary>
  TAtlasIssueStartPlan = record
    Mode: TAtlasIssueStart;
    Kind: TAtlasVcsKind;
    /// <summary>Name des Branchs (Git) bzw. unter ^/branches/ (SVN).</summary>
    Branch: string;
    /// <summary>Basen der Reihe nach (Git: main, dann master).</summary>
    Bases: TArray<string>;
    /// <summary>Commit-Präfix; '' = aus.</summary>
    Prefix: string;
    /// <summary>Nachricht für svn copy (#1290: aus vcs.branch.svn.message).</summary>
    Message: string;
    /// <summary>SVN-Optionen mit Kennung und Titel des Issues (#1290); BranchExists, SwitchBranch und das Anlegen
    /// ohne Dialog nutzen denselben Ort.</summary>
    Svn: TAtlasVcsSvnBranchOptions;
    /// <summary>False: kein gültiger Branch-Name aus dem Muster.</summary>
    Valid: Boolean;
  end;

  TAtlasIssueStartResult = record
    Outcome: TAtlasIssueStartOutcome;
    /// <summary>Angelegter bzw. ausgecheckter Branch.</summary>
    Branch: string;
    /// <summary>Basis, von der angelegt wurde.</summary>
    Base: string;
    /// <summary>Fehler der Versionsverwaltung bei Failed.</summary>
    Reason: TAtlasVcsOutcome;
    /// <summary>Git: Hook-Ordner und Verwaltungsordner (für Hook und Präfix-Datei); sonst ''.</summary>
    Hooks: string;
    GitDir: string;
    /// <summary>Beim Anlegen (#1288): die Schritte aus TAtlasVcsBranchPlan und wie weit sie kamen; sonst leer.
    /// </summary>
    Steps: TArray<TAtlasVcsBranchStep>;
    Run: TAtlasVcsBranchRun;
    /// <summary>SVN „frisch auschecken“ (#1290): neuer Ordner (für das Angebot, die Gruppe dort zu öffnen);
    /// sonst ''.</summary>
    CheckoutFolder: string;
    /// <summary>Angelegt: Wurzel der bisherigen Arbeitskopie (SVN „frisch auschecken“ #1290, Git worktree #1289).
    /// </summary>
    WorkingRoot: string;
    /// <summary>SVN-Externals (#1291): Der Branch hat Externals festgeschrieben bzw. mitverzweigt und die
    /// Arbeitskopie wurde umgeschaltet; danach den Index neu aufbauen.</summary>
    IndexRebuild: Boolean;
    /// <summary>Git (#1289): angelegt, aber der Push danach scheiterte (Reason nennt den Grund); der lokale
    /// Branch bleibt, Outcome ist Started.</summary>
    PushFailed: Boolean;
    /// <summary>Git: Ordner des worktree, in dem der Branch angelegt wurde ('' = in dieser Arbeitskopie; bei
    /// FolderTaken der belegte Ordner).</summary>
    Folder: string;
    /// <summary>Den Ordner für den worktree gab es schon: nichts angelegt (Outcome Failed).</summary>
    FolderTaken: Boolean;
    function Succeeded: Boolean;
  end;

  TAtlasIssuesView = record
    Status: TAtlasIssuesStatus;
    Error: TAtlasCiFetchError;
    /// <summary>Stand der Liste (UTC); 0 = keiner.</summary>
    At: TDateTime;
    Items: TArray<TAtlasTrackerIssue>;
    Active: TAtlasActiveIssue;
    /// <summary>Von der IDE gesetzt: Projekt (Datei und Name), Anzeigename des Trackers, Abfrage läuft, Hinweis
    /// in der Fußzeile (z. B. nach „Beginnen“), Einstellungen für „Beginnen“ und Versionsverwaltung des Projekts.
    /// </summary>
    Project: string;
    ProjectName: string;
    Tracker: string;
    /// <summary>Name der Verbindung (#1261): aus der Zuordnung bzw. der Projektname bei .atlas; '' ohne.</summary>
    Connection: string;
    /// <summary>Ohne Tracker: „zuordnen …“ anbieten (#1261).</summary>
    CanAssign: Boolean;
    /// <summary>Tracker-Projekt (YouTrack-ID, GitHub owner/repo) für die Fußzeile (#1262).</summary>
    TrackerProject: string;
    /// <summary>Passende Abfragen (#1262), die gewählte (Index, -1 ohne) und je Abfrage die Trefferzahl der
    /// letzten Abfrage (-1 = noch keine).</summary>
    Queries: TArray<TAtlasTrackerQuery>;
    QueryIndex: Integer;
    QueryCounts: TArray<Integer>;
    /// <summary>Gesendete Abfrage (bei der Vorgabe die des Anbieters) für die Fußzeile.</summary>
    QueryText: string;
    /// <summary>Klappliste zeigen (issues.queryPicker).</summary>
    Picker: Boolean;
    Querying: Boolean;
    Notice: string;
    /// <summary>Hinweis ist ein Fehler (rot).</summary>
    NoticeFailed: Boolean;
    /// <summary>„Beginnen“ läuft gerade.</summary>
    Starting: Boolean;
    Options: TAtlasIssuesOptions;
    VcsKind: TAtlasVcsKind;
    /// <summary>Filter aus der Sprint-Kachel (#1277), z. B. „„Sprint 12“, meine offen“: Items sind dann die Issues
    /// des Filters; '' ohne.</summary>
    Filter: string;
    /// <summary>Kennungen mit neuen Änderungen seit dem letzten Öffnen (#1271, Punkt an der Zeile).</summary>
    Unseen: TArray<string>;
    /// <summary>Offene Issues der Liste, z. B. für „ATL-123 · 3 offen“.</summary>
    function OpenCount: Integer;
    /// <summary>AKey trägt einen Punkt (ohne Groß-/Kleinschreibung).</summary>
    function IsUnseen(const AKey: string): Boolean;
  end;

  TAtlasMyIssues = class
  private
    /// <summary>Gemeinsamer Teil von Execute; AUseRequest False: Vorgabe aus TAtlasVcsBranchPlan.</summary>
    class function Start(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan; AUseRequest: Boolean;
      const ARequest: TAtlasVcsBranchRequest; const AProgress: TAtlasVcsBranchProgress): TAtlasIssueStartResult;
      static;
  public const
    cSectionName = 'issues';
    /// <summary>Höchstens so oft wird abgefragt.</summary>
    cDueMinutes = 10;
    cFetchTimeoutMs = 5000;
    /// <summary>Höchstens so viele Issues fragt und zeigt der Bereich.</summary>
    cMaxItems = 10;
    cHookYes = 'yes';
    cHookNo = 'no';
    cHookForeign = 'foreign';
    /// <summary>Kennung des aktuellen Issues im Statusfeld (#591).</summary>
    cStatusId = 'atlas.issue';
    /// <summary>Nach Server, Version, Index und Datei.</summary>
    cStatusOrder = 30;
    /// <summary>Fortschritt der Checkliste des aktuellen Issues im Statusfeld (#1273): „ATL-131 · 3/5“.</summary>
    cChecklistStatusId = 'atlas.issue.checklist';
    /// <summary>Direkt hinter dem aktuellen Issue.</summary>
    cChecklistStatusOrder = 31;
    /// <summary>Zeile „An ATL-123 anhängen …“ direkt unter dem aktuellen Issue (#1276).</summary>
    cAttachStatusId = 'atlas.issue.attach';
    cAttachStatusOrder = 31;
  public
    class function StartName(AStart: TAtlasIssueStart): string; static;
    /// <summary>Versionsverwaltung aus der Projekt-Zusammenfassung ("git", "svn", sonst None).</summary>
    class function VcsKindOf(const AText: string): TAtlasVcsKind; static;
    /// <summary>Umkehrung von StartName; Branch für fremde Texte.</summary>
    class function StartOf(const AText: string): TAtlasIssueStart; static;
    /// <summary>Ziel aus .atlas und den Einstellungen; ASettingTracker '' = Anbieter aus .atlas.</summary>
    class function TargetFor(const ATeamProvider, ATeamUrl, ATeamProject, ASettingTracker,
      ASettingQuery: string): TAtlasTrackerTarget; overload; static;
    /// <summary>Ziel aus der Auflösung (#1261): .atlas wie oben (ASettingTracker ersetzt den Anbieter), sonst
    /// Anbieter und Adresse der Verbindung mit dem Tracker-Projekt der Zuordnung; ohne Treffer leer.</summary>
    class function TargetFor(const AResolution: TAtlasTrackerResolution; const ASettingTracker,
      ASettingQuery: string): TAtlasTrackerTarget; overload; static;
    /// <summary>Abfrage fällig: anderes Ziel, noch keine oder letzte vor mindestens DueMinutes; AForce immer.
    /// </summary>
    class function Due(const AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget; ANowUtc: TDateTime;
      AForce: Boolean): Boolean; static;
    /// <summary>Ergebnis einer Abfrage eintragen. Fehlgeschlagen: der ältere Stand bleibt, wenn er zum Ziel
    /// gehört.</summary>
    class procedure Recorded(var AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget; ANowUtc: TDateTime;
      AOk: Boolean; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError); static;
    /// <summary>Aktives Issue: gemerkt (mit Branch nur auf diesem Branch), sonst aus ABranch erkannt (außer
    /// EndedBranch); Titel aus der Liste.</summary>
    class function Effective(const AState: TAtlasIssuesState; const AProvider, AProject,
      ABranch: string): TAtlasActiveIssue; static;
    class function View(const AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget;
      const ABranch: string): TAtlasIssuesView; static;
    /// <summary>Je Abfrage aus AQueries die Trefferzahl der letzten Abfrage (-1 = noch keine), für die Klappliste
    /// (#1262).</summary>
    class function QueryCounts(const AState: TAtlasIssuesState;
      const AQueries: TArray<TAtlasTrackerQuery>): TArray<Integer>; static;
    /// <summary>Plan für „Beginnen“ auf AIssue. Ohne Git oder SVN wird nur gemerkt.</summary>
    class function PlanStart(AKind: TAtlasVcsKind; const AOptions: TAtlasIssuesOptions;
      const AIssue: TAtlasTrackerIssue): TAtlasIssueStartPlan; static;
    /// <summary>„Beginnen“ ausführen (aus einem Hintergrund-Thread): vorhandenen Branch auschecken, sonst mit
    /// der Vorgabe aus TAtlasVcsBranchPlan anlegen (erster vorhandener Kandidat aus APlan.Bases) und auschecken;
    /// Remember ändert nichts. Git liefert zusätzlich die Ordner für Hook und Präfix-Datei. AVcs nil = nur
    /// merken.</summary>
    class function Execute(const AVcs: IAtlasVersionControl;
      const APlan: TAtlasIssueStartPlan): TAtlasIssueStartResult; overload; static;
    /// <summary>Wie oben mit der Anfrage aus dem Dialog „Branch anlegen“ (#1288): Name und Basis aus ARequest.
    /// </summary>
    class function Execute(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan;
      const ARequest: TAtlasVcsBranchRequest): TAtlasIssueStartResult; overload; static;
    /// <summary>Wie oben; AProgress vor jedem Schritt (im Hintergrund-Thread).</summary>
    class function Execute(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan;
      const ARequest: TAtlasVcsBranchRequest; const AProgress: TAtlasVcsBranchProgress): TAtlasIssueStartResult;
      overload; static;
    /// <summary>Nach „Beginnen“: aktiv setzen, EndedBranch löschen.</summary>
    class procedure Started(var AState: TAtlasIssuesState; const AIssue: TAtlasTrackerIssue;
      AMode: TAtlasIssueStart; const ABranch: string; ANowUtc: TDateTime); static;
    /// <summary>„Beenden“: gemerktes Issue löschen; ein erkanntes Issue bleibt für ABranch aus.</summary>
    class procedure Ended(var AState: TAtlasIssuesState; const ABranch: string); static;
    /// <summary>Commit-Präfix für AActive nach APattern; '' ohne aktives Issue oder bei leerem Muster.</summary>
    class function CommitPrefix(const AActive: TAtlasActiveIssue; const APattern: string): string; static;
    /// <summary>Nummer aus einer Kennung ("#753" → 753, "ATL-123" → 123); 0 ohne.</summary>
    class function NumberOfKey(const AKey: string): Integer; static;
    /// <summary>Felder einer Zeile: GitHub die Labels, YouTrack Zustand, Priorität und Sprint.</summary>
    class function Fields(const AIssue: TAtlasTrackerIssue): TArray<string>; static;
    /// <summary>Abschnitt "issues" aus der Zusammenfassung; False ohne.</summary>
    class function Read(const ASummary: TAtlasProjectSummary; out AState: TAtlasIssuesState): Boolean; static;
    /// <summary>Abschnitt "issues" in die Zusammenfassung (über Raw; TAtlasProjectSummaries.ToJson behält ihn).
    /// </summary>
    class procedure Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasIssuesState); static;
    class function ToJson(const AState: TAtlasIssuesState): string; static;
    class function FromJson(const AJson: string; out AState: TAtlasIssuesState): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Vcs.BranchNames,
  Atlas.Core.Tracker.Naming;

const
  cStartNames: array[TAtlasIssueStart] of string = ('branch', 'remember');
  cMinutesPerDay = 24 * 60;
  cNumberDigits = 9;

type
  /// <summary>Ein Lauf von TAtlasMyIssues.Start in Stufen; jede Stufe liefert False, wenn der Lauf damit endet
  /// (Outcome steht dann fest).</summary>
  TAtlasIssueStartRun = record
    Vcs: IAtlasVersionControl;
    Branching: IAtlasVcsBranching;
    Plan: TAtlasIssueStartPlan;
    UseRequest: Boolean;
    Request: TAtlasVcsBranchRequest;
    Outcome: TAtlasIssueStartResult;
    class function Create(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan;
      AUseRequest: Boolean; const ARequest: TAtlasVcsBranchRequest): TAtlasIssueStartRun; static;
    /// <summary>Nur merken endet hier; sonst gültiger Name und Arbeitskopie mit Branches.</summary>
    function Named: Boolean;
    /// <summary>Gibt es den Branch schon, wird auf ihn geschaltet und der Lauf endet.</summary>
    function Missing: Boolean;
    /// <summary>Ohne Dialog die Vorgabe aus dem Plan (#1288): erster Kandidat, den es gibt.</summary>
    function Resolved: Boolean;
    /// <summary>Eigener Ordner (#1289): gibt es ihn schon, nichts anlegen; ohne Schritte ebenso.</summary>
    function FolderFree: Boolean;
    procedure Run(const AProgress: TAtlasVcsBranchProgress);
  end;

{ TAtlasIssueStartRun }

class function TAtlasIssueStartRun.Create(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan;
  AUseRequest: Boolean; const ARequest: TAtlasVcsBranchRequest): TAtlasIssueStartRun;
var
  mHooks, mGitDir: string;
begin
  Result := Default(TAtlasIssueStartRun);
  Result.Vcs := AVcs;
  Result.Plan := APlan;
  Result.UseRequest := AUseRequest;
  Result.Request := ARequest;
  Result.Outcome := Default(TAtlasIssueStartResult);
  Result.Outcome.Reason := TAtlasVcsOutcome.Ok;
  Result.Outcome.Steps := nil;
  Result.Outcome.Run.Outcome := TAtlasVcsOutcome.Ok;
  Result.Outcome.Run.Done := 0;
  Result.Outcome.Run.Failed := -1;
  Result.Branching := nil;
  if AVcs <> nil then
  begin
    Supports(AVcs, IAtlasVcsBranching, Result.Branching);
  end;
  // Git: Ordner für Hook und Präfix-Datei, auch beim bloßen Merken (das Präfix gilt dann ebenso).
  if (Result.Branching <> nil) and (AVcs.Kind = TAtlasVcsKind.Git) and
    (Result.Branching.HookFolders(mHooks, mGitDir) = TAtlasVcsOutcome.Ok) then
  begin
    Result.Outcome.Hooks := mHooks;
    Result.Outcome.GitDir := mGitDir;
  end;
end;

function TAtlasIssueStartRun.Named: Boolean;
begin
  Result := False;
  if Plan.Mode = TAtlasIssueStart.Remember then
  begin
    Outcome.Outcome := TAtlasIssueStartOutcome.Remembered;
  end
  else
  begin
    if not UseRequest then
    begin
      Request.Name := Plan.Branch;
    end;
    if not Plan.Valid or not TAtlasVcsBranchPlan.SafeName(Request.Name) then
    begin
      Outcome.Outcome := TAtlasIssueStartOutcome.InvalidName;
    end
    else
    begin
      Outcome.Branch := Request.Name;
      Outcome.Outcome := TAtlasIssueStartOutcome.Failed;
      Result := Branching <> nil;
      if not Result then
      begin
        Outcome.Reason := TAtlasVcsOutcome.NoWorkingCopy;
      end;
    end;
  end;
end;

function TAtlasIssueStartRun.Missing: Boolean;
var
  mSvn: TAtlasVcsSvnBranchOptions;
  mExists: Boolean;
begin
  // SVN sucht und schaltet am Ort aus den Optionen (#1290), an dem auch angelegt wird; mit Dialog am Ort der
  // Anfrage.
  mSvn := Plan.Svn;
  if UseRequest and (Request.Kind = TAtlasVcsKind.Svn) and (Request.Location <> '') then
  begin
    mSvn.Location := '^/' + Request.Location;
  end;
  mExists := False;
  Outcome.Reason := Branching.BranchExists(Request.Name, mSvn, mExists);
  Result := (Outcome.Reason = TAtlasVcsOutcome.Ok) and not mExists;
  if (Outcome.Reason = TAtlasVcsOutcome.Ok) and mExists then
  begin
    Outcome.Reason := Branching.SwitchBranch(Request.Name, mSvn);
    if Outcome.Reason = TAtlasVcsOutcome.Ok then
    begin
      Outcome.Outcome := TAtlasIssueStartOutcome.Switched;
    end;
  end;
end;

function TAtlasIssueStartRun.Resolved: Boolean;
var
  mFacts: TAtlasVcsBranchFacts;
begin
  Result := True;
  if not UseRequest then
  begin
    mFacts := TAtlasVcsBranchPlan.Inspect(Vcs, Plan.Bases);
    Outcome.Reason := mFacts.Outcome;
    Result := Outcome.Reason = TAtlasVcsOutcome.Ok;
    if Result and not TAtlasVcsBranchPlan.DefaultRequest(mFacts, Plan.Branch, Plan.Message, Plan.Svn, Request) then
    begin
      Outcome.Reason := TAtlasVcsOutcome.Failed;
      Result := False;
    end;
  end;
end;

function TAtlasIssueStartRun.FolderFree: Boolean;
begin
  if (Request.WorktreeFolder <> '') and DirectoryExists(Request.WorktreeFolder) then
  begin
    Outcome.FolderTaken := True;
    Outcome.Folder := Request.WorktreeFolder;
    Outcome.Reason := TAtlasVcsOutcome.Failed;
    Result := False;
  end
  else
  begin
    Outcome.Steps := TAtlasVcsBranchPlan.Steps(Request);
    Result := Length(Outcome.Steps) > 0;
    if not Result then
    begin
      Outcome.Reason := TAtlasVcsOutcome.Failed;
    end;
  end;
end;

procedure TAtlasIssueStartRun.Run(const AProgress: TAtlasVcsBranchProgress);
begin
  // Mit der Anfrage: Der Arbeitsordner für das Umschreiben der Externals (#1291) wird davor und danach gelöscht.
  Outcome.Run := TAtlasVcsBranchPlan.Execute(Branching, Request, Outcome.Steps, AProgress);
  Outcome.Reason := Outcome.Run.Outcome;
  // Scheitert nur der Push danach, ist der Branch trotzdem angelegt und ausgecheckt.
  if Outcome.Run.Succeeded or TAtlasVcsBranchPlan.OnlyPushFailed(Outcome.Steps, Outcome.Run) then
  begin
    Outcome.Base := TAtlasVcsBranchPlan.BaseName(Request.Kind, Request.Base);
    Outcome.Outcome := TAtlasIssueStartOutcome.Started;
    Outcome.IndexRebuild := TAtlasVcsBranchPlan.ChangesExternals(Request);
    if (Request.Kind = TAtlasVcsKind.Svn) and (Request.After = TAtlasVcsSvnAfter.Checkout) then
    begin
      Outcome.CheckoutFolder := Request.CheckoutFolder;
    end;
    Outcome.WorkingRoot := Vcs.WorkingCopy.Root;
    Outcome.PushFailed := not Outcome.Run.Succeeded;
    Outcome.Folder := Request.WorktreeFolder;
  end;
end;

{ TAtlasActiveIssue }

class function TAtlasActiveIssue.Empty: TAtlasActiveIssue;
begin
  Result := Default(TAtlasActiveIssue);
end;

function TAtlasActiveIssue.Active: Boolean;
begin
  Result := Key <> '';
end;

{ TAtlasIssuesState }

class function TAtlasIssuesState.Empty: TAtlasIssuesState;
begin
  Result := Default(TAtlasIssuesState);
  Result.Items := nil;
  Result.Counts := nil;
  Result.Active := TAtlasActiveIssue.Empty;
end;

function TAtlasIssuesState.CountOf(const AName: string): Integer;
var
  mCount: TAtlasIssuesQueryCount;
begin
  Result := -1;
  for mCount in Counts do
  begin
    if SameText(mCount.Name, AName) then
    begin
      Exit(mCount.Count);
    end;
  end;
end;

procedure TAtlasIssuesState.SetCount(const AName: string; ACount: Integer);
var
  mIndex: Integer;
  mCount: TAtlasIssuesQueryCount;
begin
  if Trim(AName) = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Counts) do
  begin
    if SameText(Counts[mIndex].Name, AName) then
    begin
      Counts[mIndex].Count := ACount;
      Exit;
    end;
  end;
  mCount.Name := Trim(AName);
  mCount.Count := ACount;
  Counts := Counts + [mCount];
end;

function TAtlasIssuesState.Matches(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := (Provider <> '') and SameText(Provider, ATarget.Provider) and SameText(Server, ATarget.Server) and
    SameText(Project, ATarget.Project) and (Query = ATarget.Query);
end;

function TAtlasIssuesState.Find(const AKey: string; out AIssue: TAtlasTrackerIssue): Boolean;
var
  mItem: TAtlasTrackerIssue;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  Result := False;
  for mItem in Items do
  begin
    if SameText(mItem.Key, AKey) then
    begin
      AIssue := mItem;
      Exit(True);
    end;
  end;
end;

{ TAtlasIssuesView }

function TAtlasIssuesView.OpenCount: Integer;
begin
  Result := Length(Items);
end;

function TAtlasIssuesView.IsUnseen(const AKey: string): Boolean;
var
  mKey: string;
begin
  Result := False;
  if AKey = '' then
  begin
    Exit;
  end;
  for mKey in Unseen do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit(True);
    end;
  end;
end;

{ TAtlasIssueStartResult }

function TAtlasIssueStartResult.Succeeded: Boolean;
begin
  Result := (Outcome = TAtlasIssueStartOutcome.Started) or (Outcome = TAtlasIssueStartOutcome.Switched) or
    (Outcome = TAtlasIssueStartOutcome.Remembered);
end;

{ TAtlasIssuesOptions }

class function TAtlasIssuesOptions.Create(AStart: TAtlasIssueStart; const ABranchPattern, ABranchBase,
  ACommitPattern: string): TAtlasIssuesOptions;
begin
  Result.Start := AStart;
  Result.BranchPattern := Trim(ABranchPattern);
  Result.BranchBase := Trim(ABranchBase);
  Result.CommitPattern := ACommitPattern;
  Result.Preview := False;
  Result.MainBranch := '';
  Result.Svn := TAtlasVcsSvnBranchOptions.Default;
end;

{ TAtlasMyIssues }

class function TAtlasMyIssues.StartName(AStart: TAtlasIssueStart): string;
begin
  Result := cStartNames[AStart];
end;

class function TAtlasMyIssues.VcsKindOf(const AText: string): TAtlasVcsKind;
begin
  if SameText(Trim(AText), 'git') then
  begin
    Result := TAtlasVcsKind.Git;
  end
  else if SameText(Trim(AText), 'svn') then
  begin
    Result := TAtlasVcsKind.Svn;
  end
  else
  begin
    Result := TAtlasVcsKind.None;
  end;
end;

class function TAtlasMyIssues.StartOf(const AText: string): TAtlasIssueStart;
begin
  if SameText(Trim(AText), cStartNames[TAtlasIssueStart.Remember]) then
  begin
    Result := TAtlasIssueStart.Remember;
  end
  else
  begin
    Result := TAtlasIssueStart.Branch;
  end;
end;

class function TAtlasMyIssues.TargetFor(const ATeamProvider, ATeamUrl, ATeamProject, ASettingTracker,
  ASettingQuery: string): TAtlasTrackerTarget;
var
  mProvider: string;
begin
  mProvider := LowerCase(Trim(ASettingTracker));
  if mProvider = '' then
  begin
    mProvider := LowerCase(Trim(ATeamProvider));
  end;
  if (mProvider <> TAtlasTrackerTarget.GitHub) and (mProvider <> TAtlasTrackerTarget.YouTrack) then
  begin
    mProvider := '';
  end;
  Result := TAtlasTrackerTarget.Create(mProvider, ATeamUrl, ATeamProject, ASettingQuery);
end;

class function TAtlasMyIssues.TargetFor(const AResolution: TAtlasTrackerResolution; const ASettingTracker,
  ASettingQuery: string): TAtlasTrackerTarget;
begin
  case AResolution.Match of
    TAtlasTrackerMatch.None:
      Result := TAtlasTrackerTarget.Create('', '', '', '');
    TAtlasTrackerMatch.TeamFile:
      Result := TargetFor(AResolution.Connection.Provider, AResolution.Connection.Url, AResolution.Project,
        ASettingTracker, ASettingQuery);
  else
    // Persönliche Zuordnung: Die Verbindung nennt ihren Anbieter selbst.
    Result := TargetFor(AResolution.Connection.Provider, AResolution.Connection.Url, AResolution.Project, '',
      ASettingQuery);
  end;
end;

class function TAtlasMyIssues.Due(const AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget;
  ANowUtc: TDateTime; AForce: Boolean): Boolean;
begin
  if not ATarget.Configured then
  begin
    Exit(False);
  end;
  if AForce or not AState.Matches(ATarget) or (AState.Attempt <= 0) or (AState.Attempt > ANowUtc) then
  begin
    Exit(True);
  end;
  Result := (ANowUtc - AState.Attempt) * cMinutesPerDay >= cDueMinutes;
end;

class procedure TAtlasMyIssues.Recorded(var AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget;
  ANowUtc: TDateTime; AOk: Boolean; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
var
  mSame: Boolean;
  mIndex: Integer;
begin
  mSame := AState.Matches(ATarget);
  AState.Provider := ATarget.Provider;
  AState.Server := ATarget.Server;
  AState.Project := ATarget.Project;
  AState.Query := ATarget.Query;
  AState.Attempt := ANowUtc;
  if AOk then
  begin
    AState.Error := TAtlasCiFetchError.None;
    AState.At := ANowUtc;
    AState.Items := nil;
    for mIndex := 0 to High(AIssues) do
    begin
      if mIndex < cMaxItems then
      begin
        AState.Items := AState.Items + [AIssues[mIndex]];
      end;
    end;
    Exit;
  end;
  AState.Error := AError;
  if AState.Error = TAtlasCiFetchError.None then
  begin
    AState.Error := TAtlasCiFetchError.Network;
  end;
  // Anderes Ziel: der alte Stand gehört nicht dazu.
  if not mSame then
  begin
    AState.At := 0;
    AState.Items := nil;
  end;
end;

class function TAtlasMyIssues.Effective(const AState: TAtlasIssuesState; const AProvider, AProject,
  ABranch: string): TAtlasActiveIssue;
var
  mKey: string;
  mIssue: TAtlasTrackerIssue;
begin
  Result := TAtlasActiveIssue.Empty;
  if AState.Active.Active then
  begin
    // Mit Branch begonnen: gilt nur, solange dieser Branch ausgecheckt ist (ohne bekannten Branch weiter).
    if (AState.Active.Mode = TAtlasIssueStart.Remember) or (ABranch = '') or (AState.Active.Branch = '') or
      SameText(AState.Active.Branch, ABranch) then
    begin
      Exit(AState.Active);
    end;
  end;
  if (ABranch = '') or SameText(ABranch, AState.EndedBranch) then
  begin
    Exit;
  end;
  mKey := TAtlasTrackerNaming.KeyOfBranch(AProvider, AProject, ABranch);
  if mKey = '' then
  begin
    Exit;
  end;
  Result.Key := mKey;
  Result.Mode := TAtlasIssueStart.Branch;
  Result.Branch := ABranch;
  Result.FromBranch := True;
  if AState.Find(mKey, mIssue) then
  begin
    Result.Title := mIssue.Title;
  end;
end;

class function TAtlasMyIssues.View(const AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget;
  const ABranch: string): TAtlasIssuesView;
begin
  Result := Default(TAtlasIssuesView);
  Result.Items := nil;
  Result.Unseen := nil;
  Result.Active := Effective(AState, ATarget.Provider, ATarget.Project, ABranch);
  if not ATarget.Configured then
  begin
    Result.Status := TAtlasIssuesStatus.NotConfigured;
    Exit;
  end;
  if not AState.Matches(ATarget) or (AState.Attempt <= 0) then
  begin
    Result.Status := TAtlasIssuesStatus.Waiting;
    Exit;
  end;
  Result.Error := AState.Error;
  Result.At := AState.At;
  Result.Items := AState.Items;
  if AState.Error = TAtlasCiFetchError.None then
  begin
    Result.Status := TAtlasIssuesStatus.Ready;
  end
  else if AState.At > 0 then
  begin
    Result.Status := TAtlasIssuesStatus.Stale;
  end
  else
  begin
    Result.Status := TAtlasIssuesStatus.Failed;
  end;
end;

class function TAtlasMyIssues.QueryCounts(const AState: TAtlasIssuesState;
  const AQueries: TArray<TAtlasTrackerQuery>): TArray<Integer>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AQueries));
  for mIndex := 0 to High(AQueries) do
  begin
    Result[mIndex] := AState.CountOf(AQueries[mIndex].Name);
  end;
end;

class function TAtlasMyIssues.PlanStart(AKind: TAtlasVcsKind; const AOptions: TAtlasIssuesOptions;
  const AIssue: TAtlasTrackerIssue): TAtlasIssueStartPlan;
var
  mPattern: string;
begin
  Result := Default(TAtlasIssueStartPlan);
  Result.Bases := nil;
  Result.Kind := AKind;
  Result.Mode := AOptions.Start;
  Result.Prefix := TAtlasTrackerNaming.CommitPrefix(AOptions.CommitPattern, AIssue);
  Result.Valid := Trim(AIssue.Key) <> '';
  if (AKind <> TAtlasVcsKind.Git) and (AKind <> TAtlasVcsKind.Svn) then
  begin
    Result.Mode := TAtlasIssueStart.Remember;
  end;
  if (Result.Mode = TAtlasIssueStart.Remember) or not Result.Valid then
  begin
    Exit;
  end;
  mPattern := AOptions.BranchPattern;
  if mPattern = '' then
  begin
    if AKind = TAtlasVcsKind.Svn then
    begin
      mPattern := TAtlasTrackerNaming.SvnBranchPattern;
    end
    else
    begin
      mPattern := TAtlasTrackerNaming.GitBranchPattern;
    end;
  end;
  Result.Branch := TAtlasTrackerNaming.BranchName(mPattern, AIssue);
  Result.Valid := Result.Branch <> '';
  Result.Bases := TAtlasVcsBranchNames.Bases(AKind = TAtlasVcsKind.Svn, AOptions.BranchBase, AOptions.MainBranch);
  Result.Svn := AOptions.Svn;
  Result.Svn.Key := Trim(AIssue.Key);
  Result.Svn.Title := Trim(AIssue.Title);
  Result.Message := TAtlasVcsBranchPlan.SvnMessage(Result.Svn, Result.Branch);
end;

class function TAtlasMyIssues.Execute(const AVcs: IAtlasVersionControl;
  const APlan: TAtlasIssueStartPlan): TAtlasIssueStartResult;
begin
  Result := Start(AVcs, APlan, False, Default(TAtlasVcsBranchRequest), nil);
end;

class function TAtlasMyIssues.Execute(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan;
  const ARequest: TAtlasVcsBranchRequest): TAtlasIssueStartResult;
begin
  Result := Start(AVcs, APlan, True, ARequest, nil);
end;

class function TAtlasMyIssues.Execute(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan;
  const ARequest: TAtlasVcsBranchRequest; const AProgress: TAtlasVcsBranchProgress): TAtlasIssueStartResult;
begin
  Result := Start(AVcs, APlan, True, ARequest, AProgress);
end;

class function TAtlasMyIssues.Start(const AVcs: IAtlasVersionControl; const APlan: TAtlasIssueStartPlan;
  AUseRequest: Boolean; const ARequest: TAtlasVcsBranchRequest;
  const AProgress: TAtlasVcsBranchProgress): TAtlasIssueStartResult;
var
  mRun: TAtlasIssueStartRun;
begin
  mRun := TAtlasIssueStartRun.Create(AVcs, APlan, AUseRequest, ARequest);
  if mRun.Named and mRun.Missing and mRun.Resolved and mRun.FolderFree then
  begin
    mRun.Run(AProgress);
  end;
  Result := mRun.Outcome;
end;

class procedure TAtlasMyIssues.Started(var AState: TAtlasIssuesState; const AIssue: TAtlasTrackerIssue;
  AMode: TAtlasIssueStart; const ABranch: string; ANowUtc: TDateTime);
begin
  AState.Active := TAtlasActiveIssue.Empty;
  AState.Active.Key := AIssue.Key;
  AState.Active.Title := AIssue.Title;
  AState.Active.Mode := AMode;
  if AMode = TAtlasIssueStart.Branch then
  begin
    AState.Active.Branch := ABranch;
  end;
  AState.Active.StartedUtc := ANowUtc;
  AState.EndedBranch := '';
end;

class procedure TAtlasMyIssues.Ended(var AState: TAtlasIssuesState; const ABranch: string);
begin
  AState.Active := TAtlasActiveIssue.Empty;
  AState.EndedBranch := ABranch;
end;

class function TAtlasMyIssues.NumberOfKey(const AKey: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  mIndex := Length(AKey);
  while (mIndex >= 1) and CharInSet(AKey[mIndex], ['0'..'9']) do
  begin
    Dec(mIndex);
  end;
  if (mIndex < Length(AKey)) and ((mIndex = 0) or CharInSet(AKey[mIndex], ['#', '-'])) then
  begin
    Result := StrToIntDef(Copy(AKey, mIndex + 1, cNumberDigits), 0);
  end;
end;

class function TAtlasMyIssues.CommitPrefix(const AActive: TAtlasActiveIssue; const APattern: string): string;
var
  mIssue: TAtlasTrackerIssue;
begin
  Result := '';
  if not AActive.Active then
  begin
    Exit;
  end;
  mIssue := TAtlasTrackerIssue.Empty;
  mIssue.Key := AActive.Key;
  mIssue.Number := NumberOfKey(AActive.Key);
  mIssue.Title := AActive.Title;
  Result := TAtlasTrackerNaming.CommitPrefix(APattern, mIssue);
end;

class function TAtlasMyIssues.Fields(const AIssue: TAtlasTrackerIssue): TArray<string>;
begin
  Result := nil;
  if Length(AIssue.Labels) > 0 then
  begin
    Result := Copy(AIssue.Labels);
  end;
  if AIssue.Priority <> '' then
  begin
    Result := Result + [AIssue.Priority];
  end;
  // GitHub liefert "open" als Zustand; das steht schon in der Abfrage und wird nicht gezeigt.
  if (AIssue.State <> '') and (AIssue.Key <> '') and (AIssue.Key[1] <> '#') then
  begin
    Result := [AIssue.State] + Result;
  end;
  if AIssue.Sprint <> '' then
  begin
    Result := Result + [AIssue.Sprint];
  end;
end;

{ JSON }

function TextIn(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function NumberIn(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function FlagIn(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

function ObjectIn(AObject: TJSONObject; const AName: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end;
end;

function ParseObject(const AJson: string): TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  try
    Result := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Result := nil;
  end;
end;

procedure AddText(AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AObject.AddPair(AName, AValue);
  end;
end;

procedure AddTime(AObject: TJSONObject; const AName: string; AValue: TDateTime);
begin
  if AValue > 0 then
  begin
    AObject.AddPair(AName, TAtlasProjectSummaries.TimeText(AValue));
  end;
end;

function ItemJson(const AItem: TAtlasTrackerIssue): TJSONObject;
var
  mLabels: TJSONArray;
  mLabelName: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('key', AItem.Key);
  if AItem.Number > 0 then
  begin
    Result.AddPair('number', TJSONNumber.Create(AItem.Number));
  end;
  Result.AddPair('title', AItem.Title);
  if Length(AItem.Labels) > 0 then
  begin
    mLabels := TJSONArray.Create;
    Result.AddPair('labels', mLabels);
    for mLabelName in AItem.Labels do
    begin
      mLabels.Add(mLabelName);
    end;
  end;
  AddText(Result, 'state', AItem.State);
  AddText(Result, 'priority', AItem.Priority);
  AddText(Result, 'sprint', AItem.Sprint);
  if AItem.PullRequest.Number > 0 then
  begin
    Result.AddPair('pr', TJSONNumber.Create(AItem.PullRequest.Number));
    Result.AddPair('checks', TAtlasTrackerPullRequest.ChecksKey(AItem.PullRequest.Checks));
    if AItem.PullRequest.Draft then
    begin
      Result.AddPair('draft', TJSONBool.Create(True));
    end;
  end;
end;

function ActiveJson(const AActive: TAtlasActiveIssue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('key', AActive.Key);
  AddText(Result, 'title', AActive.Title);
  Result.AddPair('mode', TAtlasMyIssues.StartName(AActive.Mode));
  AddText(Result, 'branch', AActive.Branch);
  AddTime(Result, 'started', AActive.StartedUtc);
end;

function CountsJson(const ACounts: TArray<TAtlasIssuesQueryCount>): TJSONObject;
var
  mCount: TAtlasIssuesQueryCount;
begin
  Result := TJSONObject.Create;
  for mCount in ACounts do
  begin
    Result.AddPair(mCount.Name, TJSONNumber.Create(mCount.Count));
  end;
end;

function SectionJson(const AState: TAtlasIssuesState): TJSONObject;
var
  mItems: TJSONArray;
  mItem: TAtlasTrackerIssue;
begin
  Result := TJSONObject.Create;
  AddText(Result, 'provider', AState.Provider);
  AddText(Result, 'server', AState.Server);
  AddText(Result, 'project', AState.Project);
  AddText(Result, 'query', AState.Query);
  AddTime(Result, 'attempt', AState.Attempt);
  AddText(Result, 'error', TAtlasCiBuild.ErrorKey(AState.Error));
  AddTime(Result, 'at', AState.At);
  mItems := TJSONArray.Create;
  Result.AddPair('items', mItems);
  for mItem in AState.Items do
  begin
    mItems.AddElement(ItemJson(mItem));
  end;
  if AState.Active.Active and not AState.Active.FromBranch then
  begin
    Result.AddPair('active', ActiveJson(AState.Active));
  end;
  AddText(Result, 'endedBranch', AState.EndedBranch);
  AddText(Result, 'hook', AState.Hook);
  AddText(Result, 'gitDir', AState.GitDir);
  AddText(Result, 'selected', AState.Selected);
  if Length(AState.Counts) > 0 then
  begin
    Result.AddPair('counts', CountsJson(AState.Counts));
  end;
end;

function LabelsOf(AEntry: TJSONObject): TArray<string>;
var
  mLabels, mLabelValue: TJSONValue;
begin
  Result := nil;
  mLabels := AEntry.GetValue('labels');
  if mLabels is TJSONArray then
  begin
    for mLabelValue in TJSONArray(mLabels) do
    begin
      if (mLabelValue is TJSONString) and (Length(Result) < TAtlasTrackerIssue.MaxLabels) then
      begin
        Result := Result + [TJSONString(mLabelValue).Value];
      end;
    end;
  end;
end;

/// <summary>Ein Eintrag aus "items"; False ohne Schlüssel.</summary>
function ItemOf(AEntry: TJSONObject; out AItem: TAtlasTrackerIssue): Boolean;
begin
  AItem := TAtlasTrackerIssue.Empty;
  AItem.Key := TextIn(AEntry, 'key');
  Result := AItem.Key <> '';
  if Result then
  begin
    AItem.Number := NumberIn(AEntry, 'number');
    AItem.Title := TextIn(AEntry, 'title');
    AItem.Labels := LabelsOf(AEntry);
    AItem.State := TextIn(AEntry, 'state');
    AItem.Priority := TextIn(AEntry, 'priority');
    AItem.Sprint := TextIn(AEntry, 'sprint');
    AItem.PullRequest.Number := NumberIn(AEntry, 'pr');
    AItem.PullRequest.Checks := TAtlasTrackerPullRequest.ChecksOf(TextIn(AEntry, 'checks'));
    AItem.PullRequest.Draft := FlagIn(AEntry, 'draft');
  end;
end;

procedure ItemsOf(ASection: TJSONObject; var AState: TAtlasIssuesState);
var
  mItems, mValue: TJSONValue;
  mItem: TAtlasTrackerIssue;
begin
  mItems := ASection.GetValue('items');
  if mItems is TJSONArray then
  begin
    for mValue in TJSONArray(mItems) do
    begin
      if (mValue is TJSONObject) and (Length(AState.Items) < TAtlasMyIssues.cMaxItems) and
        ItemOf(TJSONObject(mValue), mItem) then
      begin
        AState.Items := AState.Items + [mItem];
      end;
    end;
  end;
end;

procedure ActiveOf(ASection: TJSONObject; var AState: TAtlasIssuesState);
var
  mActive: TJSONObject;
begin
  mActive := ObjectIn(ASection, 'active');
  if (mActive <> nil) and (TextIn(mActive, 'key') <> '') then
  begin
    AState.Active.Key := TextIn(mActive, 'key');
    AState.Active.Title := TextIn(mActive, 'title');
    AState.Active.Mode := TAtlasMyIssues.StartOf(TextIn(mActive, 'mode'));
    AState.Active.Branch := TextIn(mActive, 'branch');
    AState.Active.StartedUtc := TAtlasProjectSummaries.TimeOf(TextIn(mActive, 'started'));
  end;
end;

procedure CountsOf(ASection: TJSONObject; var AState: TAtlasIssuesState);
var
  mCounts: TJSONObject;
  mIndex: Integer;
begin
  mCounts := ObjectIn(ASection, 'counts');
  if mCounts <> nil then
  begin
    for mIndex := 0 to mCounts.Count - 1 do
    begin
      if mCounts.Pairs[mIndex].JsonValue is TJSONNumber then
      begin
        AState.SetCount(mCounts.Pairs[mIndex].JsonString.Value, TJSONNumber(mCounts.Pairs[mIndex].JsonValue).AsInt);
      end;
    end;
  end;
end;

function StateOf(ASection: TJSONObject; out AState: TAtlasIssuesState): Boolean;
begin
  AState := TAtlasIssuesState.Empty;
  Result := ASection <> nil;
  if Result then
  begin
    AState.Provider := TextIn(ASection, 'provider');
    AState.Server := TextIn(ASection, 'server');
    AState.Project := TextIn(ASection, 'project');
    AState.Query := TextIn(ASection, 'query');
    AState.Attempt := TAtlasProjectSummaries.TimeOf(TextIn(ASection, 'attempt'));
    AState.Error := TAtlasCiBuild.ErrorOf(TextIn(ASection, 'error'));
    AState.At := TAtlasProjectSummaries.TimeOf(TextIn(ASection, 'at'));
    ItemsOf(ASection, AState);
    ActiveOf(ASection, AState);
    AState.EndedBranch := TextIn(ASection, 'endedBranch');
    AState.Hook := TextIn(ASection, 'hook');
    AState.GitDir := TextIn(ASection, 'gitDir');
    AState.Selected := TextIn(ASection, 'selected');
    CountsOf(ASection, AState);
  end;
end;

class function TAtlasMyIssues.ToJson(const AState: TAtlasIssuesState): string;
var
  mSection: TJSONObject;
begin
  mSection := SectionJson(AState);
  try
    Result := mSection.ToJSON;
  finally
    mSection.Free;
  end;
end;

class function TAtlasMyIssues.FromJson(const AJson: string; out AState: TAtlasIssuesState): Boolean;
var
  mValue: TJSONValue;
begin
  AState := TAtlasIssuesState.Empty;
  mValue := ParseObject(AJson);
  try
    Result := (mValue is TJSONObject) and StateOf(TJSONObject(mValue), AState);
  finally
    mValue.Free;
  end;
end;

class function TAtlasMyIssues.Read(const ASummary: TAtlasProjectSummary; out AState: TAtlasIssuesState): Boolean;
var
  mValue: TJSONValue;
begin
  AState := TAtlasIssuesState.Empty;
  mValue := ParseObject(ASummary.Raw);
  try
    Result := (mValue is TJSONObject) and StateOf(ObjectIn(TJSONObject(mValue), cSectionName), AState);
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasMyIssues.Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasIssuesState);
var
  mValue: TJSONValue;
  mOriginal, mRoot: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
begin
  mValue := ParseObject(ASummary.Raw);
  mRoot := TJSONObject.Create;
  try
    // Alles außer dem Abschnitt übernehmen; ohne Datei schreibt TAtlasProjectSummaries.ToJson die übrigen
    // Felder aus dem Datensatz.
    if mValue is TJSONObject then
    begin
      mOriginal := TJSONObject(mValue);
      for mIndex := 0 to mOriginal.Count - 1 do
      begin
        mPair := mOriginal.Pairs[mIndex];
        if mPair.JsonString.Value <> cSectionName then
        begin
          mRoot.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
        end;
      end;
    end;
    mRoot.AddPair(cSectionName, SectionJson(AState));
    ASummary.Raw := mRoot.ToJSON;
  finally
    mRoot.Free;
    mValue.Free;
  end;
end;

end.
