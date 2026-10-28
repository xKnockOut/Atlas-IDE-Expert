unit Atlas.Core.Welcome.Issues;

// Bereich „Meine Issues“ der Willkommensseite (#765), Teil ohne VCL und Open
// Tools API: was abgefragt wird, wann, was der Bereich zeigt, welches Issue
// aktiv ist und was „Beginnen“ tut.
// - Ziel: Anbieter, Adresse und Projekt aus .atlas (Abschnitt "tracker");
//   issues.tracker ersetzt den Anbieter, .query die Abfrage. Ohne tracker in
//   der .atlas gilt die persönliche Zuordnung (#1261, issues.projects):
//   Verbindung und Tracker-Projekt der passenden Zeile.
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
  Atlas.Core.Ci.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Vcs.Contract;

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
    class function Empty: TAtlasIssuesState; static;
    /// <summary>Die Liste gehört zu ATarget (Anbieter, Server, Projekt und Abfrage gleich).</summary>
    function Matches(const ATarget: TAtlasTrackerTarget): Boolean;
    function Find(const AKey: string; out AIssue: TAtlasTrackerIssue): Boolean;
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
    /// <summary>Nachricht für svn copy.</summary>
    Message: string;
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
    Querying: Boolean;
    Notice: string;
    /// <summary>Hinweis ist ein Fehler (rot).</summary>
    NoticeFailed: Boolean;
    /// <summary>„Beginnen“ läuft gerade.</summary>
    Starting: Boolean;
    Options: TAtlasIssuesOptions;
    VcsKind: TAtlasVcsKind;
    /// <summary>Offene Issues der Liste, z. B. für „ATL-123 · 3 offen“.</summary>
    function OpenCount: Integer;
  end;

  TAtlasWelcomeIssues = class
  public const
    SectionName = 'issues';
    /// <summary>Höchstens so oft wird abgefragt.</summary>
    DueMinutes = 10;
    FetchTimeoutMs = 5000;
    /// <summary>Höchstens so viele Issues fragt und zeigt der Bereich.</summary>
    MaxItems = 10;
    HookYes = 'yes';
    HookNo = 'no';
    HookForeign = 'foreign';
    /// <summary>Kennung des aktuellen Issues im Statusfeld (#591).</summary>
    StatusId = 'atlas.issue';
    /// <summary>Nach Server, Version, Index und Datei.</summary>
    StatusOrder = 30;
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
    /// <summary>Plan für „Beginnen“ auf AIssue. Ohne Git oder SVN wird nur gemerkt.</summary>
    class function PlanStart(AKind: TAtlasVcsKind; const AOptions: TAtlasIssuesOptions;
      const AIssue: TAtlasTrackerIssue): TAtlasIssueStartPlan; static;
    /// <summary>„Beginnen“ ausführen (aus einem Hintergrund-Thread): vorhandenen Branch auschecken, sonst von der
    /// ersten passenden Basis anlegen und auschecken; Remember ändert nichts. Git liefert zusätzlich die Ordner
    /// für Hook und Präfix-Datei. AVcs nil = nur merken.</summary>
    class function Execute(const AVcs: IAtlasVersionControl;
      const APlan: TAtlasIssueStartPlan): TAtlasIssueStartResult; static;
    /// <summary>Anzahl lokaler Änderungen, die ein Wechsel des Branchs betrifft (ohne unversionierte Dateien).
    /// </summary>
    class function LocalChanges(const AChanges: TArray<TAtlasVcsChange>): Integer; static;
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
  Atlas.Core.Tracker.Naming;

const
  StartNames: array[TAtlasIssueStart] of string = ('branch', 'remember');

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
  Result.Active := TAtlasActiveIssue.Empty;
end;

function TAtlasIssuesState.Matches(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := (Provider <> '') and SameText(Provider, ATarget.Provider) and SameText(Server, ATarget.Server) and
    SameText(Project, ATarget.Project) and (Query = ATarget.Query);
end;

function TAtlasIssuesState.Find(const AKey: string; out AIssue: TAtlasTrackerIssue): Boolean;
var
  Item: TAtlasTrackerIssue;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  Result := False;
  for Item in Items do
    if SameText(Item.Key, AKey) then
    begin
      AIssue := Item;
      Exit(True);
    end;
end;

{ TAtlasIssuesView }

function TAtlasIssuesView.OpenCount: Integer;
begin
  Result := Length(Items);
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
end;

{ TAtlasWelcomeIssues }

class function TAtlasWelcomeIssues.StartName(AStart: TAtlasIssueStart): string;
begin
  Result := StartNames[AStart];
end;

class function TAtlasWelcomeIssues.VcsKindOf(const AText: string): TAtlasVcsKind;
begin
  if SameText(Trim(AText), 'git') then
    Result := TAtlasVcsKind.Git
  else if SameText(Trim(AText), 'svn') then
    Result := TAtlasVcsKind.Svn
  else
    Result := TAtlasVcsKind.None;
end;

class function TAtlasWelcomeIssues.StartOf(const AText: string): TAtlasIssueStart;
begin
  if SameText(Trim(AText), StartNames[TAtlasIssueStart.Remember]) then
    Result := TAtlasIssueStart.Remember
  else
    Result := TAtlasIssueStart.Branch;
end;

class function TAtlasWelcomeIssues.TargetFor(const ATeamProvider, ATeamUrl, ATeamProject, ASettingTracker,
  ASettingQuery: string): TAtlasTrackerTarget;
var
  Provider: string;
begin
  Provider := LowerCase(Trim(ASettingTracker));
  if Provider = '' then
    Provider := LowerCase(Trim(ATeamProvider));
  if (Provider <> TAtlasTrackerTarget.GitHub) and (Provider <> TAtlasTrackerTarget.YouTrack) then
    Provider := '';
  Result := TAtlasTrackerTarget.Create(Provider, ATeamUrl, ATeamProject, ASettingQuery);
end;

class function TAtlasWelcomeIssues.TargetFor(const AResolution: TAtlasTrackerResolution; const ASettingTracker,
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

class function TAtlasWelcomeIssues.Due(const AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget;
  ANowUtc: TDateTime; AForce: Boolean): Boolean;
begin
  if not ATarget.Configured then
    Exit(False);
  if AForce or not AState.Matches(ATarget) or (AState.Attempt <= 0) or (AState.Attempt > ANowUtc) then
    Exit(True);
  Result := (ANowUtc - AState.Attempt) * 24 * 60 >= DueMinutes;
end;

class procedure TAtlasWelcomeIssues.Recorded(var AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget;
  ANowUtc: TDateTime; AOk: Boolean; const AIssues: TArray<TAtlasTrackerIssue>; AError: TAtlasCiFetchError);
var
  Same: Boolean;
  Index: Integer;
begin
  Same := AState.Matches(ATarget);
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
    for Index := 0 to High(AIssues) do
      if Index < MaxItems then
        AState.Items := AState.Items + [AIssues[Index]];
    Exit;
  end;
  AState.Error := AError;
  if AState.Error = TAtlasCiFetchError.None then
    AState.Error := TAtlasCiFetchError.Network;
  // Anderes Ziel: der alte Stand gehört nicht dazu.
  if not Same then
  begin
    AState.At := 0;
    AState.Items := nil;
  end;
end;

class function TAtlasWelcomeIssues.Effective(const AState: TAtlasIssuesState; const AProvider, AProject,
  ABranch: string): TAtlasActiveIssue;
var
  Key: string;
  Issue: TAtlasTrackerIssue;
begin
  Result := TAtlasActiveIssue.Empty;
  if AState.Active.Active then
  begin
    // Mit Branch begonnen: gilt nur, solange dieser Branch ausgecheckt ist (ohne bekannten Branch weiter).
    if (AState.Active.Mode = TAtlasIssueStart.Remember) or (ABranch = '') or (AState.Active.Branch = '') or
      SameText(AState.Active.Branch, ABranch) then
      Exit(AState.Active);
  end;
  if (ABranch = '') or SameText(ABranch, AState.EndedBranch) then
    Exit;
  Key := TAtlasTrackerNaming.KeyOfBranch(AProvider, AProject, ABranch);
  if Key = '' then
    Exit;
  Result.Key := Key;
  Result.Mode := TAtlasIssueStart.Branch;
  Result.Branch := ABranch;
  Result.FromBranch := True;
  if AState.Find(Key, Issue) then
    Result.Title := Issue.Title;
end;

class function TAtlasWelcomeIssues.View(const AState: TAtlasIssuesState; const ATarget: TAtlasTrackerTarget;
  const ABranch: string): TAtlasIssuesView;
begin
  Result := Default(TAtlasIssuesView);
  Result.Items := nil;
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
    Result.Status := TAtlasIssuesStatus.Ready
  else if AState.At > 0 then
    Result.Status := TAtlasIssuesStatus.Stale
  else
    Result.Status := TAtlasIssuesStatus.Failed;
end;

class function TAtlasWelcomeIssues.PlanStart(AKind: TAtlasVcsKind; const AOptions: TAtlasIssuesOptions;
  const AIssue: TAtlasTrackerIssue): TAtlasIssueStartPlan;
var
  Pattern: string;
begin
  Result := Default(TAtlasIssueStartPlan);
  Result.Bases := nil;
  Result.Kind := AKind;
  Result.Mode := AOptions.Start;
  Result.Prefix := TAtlasTrackerNaming.CommitPrefix(AOptions.CommitPattern, AIssue);
  Result.Valid := Trim(AIssue.Key) <> '';
  if (AKind <> TAtlasVcsKind.Git) and (AKind <> TAtlasVcsKind.Svn) then
    Result.Mode := TAtlasIssueStart.Remember;
  if (Result.Mode = TAtlasIssueStart.Remember) or not Result.Valid then
    Exit;
  Pattern := AOptions.BranchPattern;
  if Pattern = '' then
  begin
    if AKind = TAtlasVcsKind.Svn then
      Pattern := TAtlasTrackerNaming.SvnBranchPattern
    else
      Pattern := TAtlasTrackerNaming.GitBranchPattern;
  end;
  Result.Branch := TAtlasTrackerNaming.BranchName(Pattern, AIssue);
  Result.Valid := Result.Branch <> '';
  if AOptions.BranchBase <> '' then
    Result.Bases := [AOptions.BranchBase]
  else if AKind = TAtlasVcsKind.Svn then
    Result.Bases := [TAtlasTrackerNaming.SvnBase]
  else
    Result.Bases := [TAtlasTrackerNaming.GitBase, TAtlasTrackerNaming.GitBaseFallback];
  Result.Message := Trim(AIssue.Key + ' ' + AIssue.Title);
end;

class function TAtlasWelcomeIssues.Execute(const AVcs: IAtlasVersionControl;
  const APlan: TAtlasIssueStartPlan): TAtlasIssueStartResult;
var
  Branching: IAtlasVcsBranching;
  Exists: Boolean;
  Base, Hooks, GitDir: string;
begin
  Result := Default(TAtlasIssueStartResult);
  Result.Reason := TAtlasVcsOutcome.Ok;
  Branching := nil;
  if AVcs <> nil then
    Supports(AVcs, IAtlasVcsBranching, Branching);
  // Git: Ordner für Hook und Präfix-Datei, auch beim bloßen Merken (das Präfix gilt dann ebenso).
  if (Branching <> nil) and (AVcs.Kind = TAtlasVcsKind.Git) and
    (Branching.HookFolders(Hooks, GitDir) = TAtlasVcsOutcome.Ok) then
  begin
    Result.Hooks := Hooks;
    Result.GitDir := GitDir;
  end;
  if APlan.Mode = TAtlasIssueStart.Remember then
  begin
    Result.Outcome := TAtlasIssueStartOutcome.Remembered;
    Exit;
  end;
  if not APlan.Valid or (APlan.Branch = '') then
  begin
    Result.Outcome := TAtlasIssueStartOutcome.InvalidName;
    Exit;
  end;
  Result.Branch := APlan.Branch;
  Result.Outcome := TAtlasIssueStartOutcome.Failed;
  if Branching = nil then
  begin
    Result.Reason := TAtlasVcsOutcome.NoWorkingCopy;
    Exit;
  end;
  Result.Reason := Branching.BranchExists(APlan.Branch, Exists);
  if Result.Reason <> TAtlasVcsOutcome.Ok then
    Exit;
  if Exists then
  begin
    Result.Reason := Branching.SwitchBranch(APlan.Branch);
    if Result.Reason = TAtlasVcsOutcome.Ok then
      Result.Outcome := TAtlasIssueStartOutcome.Switched;
    Exit;
  end;
  Result.Reason := TAtlasVcsOutcome.Failed;
  for Base in APlan.Bases do
  begin
    Result.Reason := Branching.CreateBranch(APlan.Branch, Base, APlan.Message);
    if Result.Reason = TAtlasVcsOutcome.Ok then
    begin
      Result.Base := Base;
      Result.Outcome := TAtlasIssueStartOutcome.Started;
      Exit;
    end;
    // Nur ein Fehler von git/svn selbst (z. B. Basis fehlt) führt zur nächsten Basis.
    if Result.Reason <> TAtlasVcsOutcome.Failed then
      Exit;
  end;
end;

class function TAtlasWelcomeIssues.LocalChanges(const AChanges: TArray<TAtlasVcsChange>): Integer;
var
  Change: TAtlasVcsChange;
begin
  Result := 0;
  for Change in AChanges do
    if Change.Kind <> TAtlasVcsChangeKind.Untracked then
      Inc(Result);
end;

class procedure TAtlasWelcomeIssues.Started(var AState: TAtlasIssuesState; const AIssue: TAtlasTrackerIssue;
  AMode: TAtlasIssueStart; const ABranch: string; ANowUtc: TDateTime);
begin
  AState.Active := TAtlasActiveIssue.Empty;
  AState.Active.Key := AIssue.Key;
  AState.Active.Title := AIssue.Title;
  AState.Active.Mode := AMode;
  if AMode = TAtlasIssueStart.Branch then
    AState.Active.Branch := ABranch;
  AState.Active.StartedUtc := ANowUtc;
  AState.EndedBranch := '';
end;

class procedure TAtlasWelcomeIssues.Ended(var AState: TAtlasIssuesState; const ABranch: string);
begin
  AState.Active := TAtlasActiveIssue.Empty;
  AState.EndedBranch := ABranch;
end;

class function TAtlasWelcomeIssues.NumberOfKey(const AKey: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  Index := Length(AKey);
  while (Index >= 1) and CharInSet(AKey[Index], ['0'..'9']) do
    Dec(Index);
  if (Index < Length(AKey)) and ((Index = 0) or CharInSet(AKey[Index], ['#', '-'])) then
    Result := StrToIntDef(Copy(AKey, Index + 1, 9), 0);
end;

class function TAtlasWelcomeIssues.CommitPrefix(const AActive: TAtlasActiveIssue; const APattern: string): string;
var
  Issue: TAtlasTrackerIssue;
begin
  Result := '';
  if not AActive.Active then
    Exit;
  Issue := TAtlasTrackerIssue.Empty;
  Issue.Key := AActive.Key;
  Issue.Number := NumberOfKey(AActive.Key);
  Issue.Title := AActive.Title;
  Result := TAtlasTrackerNaming.CommitPrefix(APattern, Issue);
end;

class function TAtlasWelcomeIssues.Fields(const AIssue: TAtlasTrackerIssue): TArray<string>;
begin
  Result := nil;
  if Length(AIssue.Labels) > 0 then
    Result := Copy(AIssue.Labels);
  if AIssue.Priority <> '' then
    Result := Result + [AIssue.Priority];
  // GitHub liefert "open" als Zustand; das steht schon in der Abfrage und wird nicht gezeigt.
  if (AIssue.State <> '') and (AIssue.Key <> '') and (AIssue.Key[1] <> '#') then
    Result := [AIssue.State] + Result;
  if AIssue.Sprint <> '' then
    Result := Result + [AIssue.Sprint];
end;

{ JSON }

function TextIn(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function NumberIn(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt;
  if Result < 0 then
    Result := 0;
end;

function FlagIn(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function ObjectIn(AObject: TJSONObject; const AName: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONObject then
    Result := TJSONObject(Value);
end;

function ParseObject(const AJson: string): TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
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
    AObject.AddPair(AName, AValue);
end;

procedure AddTime(AObject: TJSONObject; const AName: string; AValue: TDateTime);
begin
  if AValue > 0 then
    AObject.AddPair(AName, TAtlasProjectSummaries.TimeText(AValue));
end;

function SectionJson(const AState: TAtlasIssuesState): TJSONObject;
var
  Items, Labels: TJSONArray;
  Entry, Active: TJSONObject;
  Item: TAtlasTrackerIssue;
  LabelName: string;
begin
  Result := TJSONObject.Create;
  AddText(Result, 'provider', AState.Provider);
  AddText(Result, 'server', AState.Server);
  AddText(Result, 'project', AState.Project);
  AddText(Result, 'query', AState.Query);
  AddTime(Result, 'attempt', AState.Attempt);
  AddText(Result, 'error', TAtlasCiBuild.ErrorKey(AState.Error));
  AddTime(Result, 'at', AState.At);
  Items := TJSONArray.Create;
  Result.AddPair('items', Items);
  for Item in AState.Items do
  begin
    Entry := TJSONObject.Create;
    Items.AddElement(Entry);
    Entry.AddPair('key', Item.Key);
    if Item.Number > 0 then
      Entry.AddPair('number', TJSONNumber.Create(Item.Number));
    Entry.AddPair('title', Item.Title);
    if Length(Item.Labels) > 0 then
    begin
      Labels := TJSONArray.Create;
      Entry.AddPair('labels', Labels);
      for LabelName in Item.Labels do
        Labels.Add(LabelName);
    end;
    AddText(Entry, 'state', Item.State);
    AddText(Entry, 'priority', Item.Priority);
    AddText(Entry, 'sprint', Item.Sprint);
    if Item.PullRequest.Number > 0 then
    begin
      Entry.AddPair('pr', TJSONNumber.Create(Item.PullRequest.Number));
      Entry.AddPair('checks', TAtlasTrackerPullRequest.ChecksKey(Item.PullRequest.Checks));
      if Item.PullRequest.Draft then
        Entry.AddPair('draft', TJSONBool.Create(True));
    end;
  end;
  if AState.Active.Active and not AState.Active.FromBranch then
  begin
    Active := TJSONObject.Create;
    Result.AddPair('active', Active);
    Active.AddPair('key', AState.Active.Key);
    AddText(Active, 'title', AState.Active.Title);
    Active.AddPair('mode', TAtlasWelcomeIssues.StartName(AState.Active.Mode));
    AddText(Active, 'branch', AState.Active.Branch);
    AddTime(Active, 'started', AState.Active.StartedUtc);
  end;
  AddText(Result, 'endedBranch', AState.EndedBranch);
  AddText(Result, 'hook', AState.Hook);
  AddText(Result, 'gitDir', AState.GitDir);
end;

function StateOf(ASection: TJSONObject; out AState: TAtlasIssuesState): Boolean;
var
  Items, Labels, Value, LabelValue: TJSONValue;
  Entry, Active: TJSONObject;
  Item: TAtlasTrackerIssue;
begin
  AState := TAtlasIssuesState.Empty;
  Result := ASection <> nil;
  if not Result then
    Exit;
  AState.Provider := TextIn(ASection, 'provider');
  AState.Server := TextIn(ASection, 'server');
  AState.Project := TextIn(ASection, 'project');
  AState.Query := TextIn(ASection, 'query');
  AState.Attempt := TAtlasProjectSummaries.TimeOf(TextIn(ASection, 'attempt'));
  AState.Error := TAtlasCiBuild.ErrorOf(TextIn(ASection, 'error'));
  AState.At := TAtlasProjectSummaries.TimeOf(TextIn(ASection, 'at'));
  Items := ASection.GetValue('items');
  if Items is TJSONArray then
    for Value in TJSONArray(Items) do
    begin
      if not (Value is TJSONObject) or (Length(AState.Items) >= TAtlasWelcomeIssues.MaxItems) then
        Continue;
      Entry := TJSONObject(Value);
      Item := TAtlasTrackerIssue.Empty;
      Item.Key := TextIn(Entry, 'key');
      if Item.Key = '' then
        Continue;
      Item.Number := NumberIn(Entry, 'number');
      Item.Title := TextIn(Entry, 'title');
      Labels := Entry.GetValue('labels');
      if Labels is TJSONArray then
        for LabelValue in TJSONArray(Labels) do
          if (LabelValue is TJSONString) and (Length(Item.Labels) < TAtlasTrackerIssue.MaxLabels) then
            Item.Labels := Item.Labels + [TJSONString(LabelValue).Value];
      Item.State := TextIn(Entry, 'state');
      Item.Priority := TextIn(Entry, 'priority');
      Item.Sprint := TextIn(Entry, 'sprint');
      Item.PullRequest.Number := NumberIn(Entry, 'pr');
      Item.PullRequest.Checks := TAtlasTrackerPullRequest.ChecksOf(TextIn(Entry, 'checks'));
      Item.PullRequest.Draft := FlagIn(Entry, 'draft');
      AState.Items := AState.Items + [Item];
    end;
  Active := ObjectIn(ASection, 'active');
  if (Active <> nil) and (TextIn(Active, 'key') <> '') then
  begin
    AState.Active.Key := TextIn(Active, 'key');
    AState.Active.Title := TextIn(Active, 'title');
    AState.Active.Mode := TAtlasWelcomeIssues.StartOf(TextIn(Active, 'mode'));
    AState.Active.Branch := TextIn(Active, 'branch');
    AState.Active.StartedUtc := TAtlasProjectSummaries.TimeOf(TextIn(Active, 'started'));
  end;
  AState.EndedBranch := TextIn(ASection, 'endedBranch');
  AState.Hook := TextIn(ASection, 'hook');
  AState.GitDir := TextIn(ASection, 'gitDir');
end;

class function TAtlasWelcomeIssues.ToJson(const AState: TAtlasIssuesState): string;
var
  Section: TJSONObject;
begin
  Section := SectionJson(AState);
  try
    Result := Section.ToJSON;
  finally
    Section.Free;
  end;
end;

class function TAtlasWelcomeIssues.FromJson(const AJson: string; out AState: TAtlasIssuesState): Boolean;
var
  Value: TJSONValue;
begin
  AState := TAtlasIssuesState.Empty;
  Value := ParseObject(AJson);
  try
    Result := (Value is TJSONObject) and StateOf(TJSONObject(Value), AState);
  finally
    Value.Free;
  end;
end;

class function TAtlasWelcomeIssues.Read(const ASummary: TAtlasProjectSummary; out AState: TAtlasIssuesState): Boolean;
var
  Value: TJSONValue;
begin
  AState := TAtlasIssuesState.Empty;
  Value := ParseObject(ASummary.Raw);
  try
    Result := (Value is TJSONObject) and StateOf(ObjectIn(TJSONObject(Value), SectionName), AState);
  finally
    Value.Free;
  end;
end;

class procedure TAtlasWelcomeIssues.Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasIssuesState);
var
  Value: TJSONValue;
  Original, Root: TJSONObject;
  Index: Integer;
  Pair: TJSONPair;
begin
  Value := ParseObject(ASummary.Raw);
  Root := TJSONObject.Create;
  try
    // Alles außer dem Abschnitt übernehmen; ohne Datei schreibt TAtlasProjectSummaries.ToJson die übrigen
    // Felder aus dem Datensatz.
    if Value is TJSONObject then
    begin
      Original := TJSONObject(Value);
      for Index := 0 to Original.Count - 1 do
      begin
        Pair := Original.Pairs[Index];
        if Pair.JsonString.Value <> SectionName then
          Root.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
      end;
    end;
    Root.AddPair(SectionName, SectionJson(AState));
    ASummary.Raw := Root.ToJSON;
  finally
    Root.Free;
    Value.Free;
  end;
end;

end.
