unit Atlas.Core.Tracker.Contract.MyIssues;

// Vertrag des Bereichs „Meine Issues“ (#765, #1443): was die Kachel zeigt
// (TAtlasIssuesView mit aktivem Issue, Abfragen, Gruppen und wieder geöffneten
// Issues) und die Optionen von „Beginnen“. Berechnet in Atlas.Core.Tracker.MyIssues
// und Atlas.IDE.Tracker.MyIssues, gezeigt über Atlas.UI.Tracker.Contract.MyIssues.

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Eine Abfrage aus issues.queries (#1262).</summary>
  TAtlasTrackerQuery = record
    Name: string;
    /// <summary>Syntax des Trackers; '' = Vorgabe des Anbieters.</summary>
    Query: string;
    /// <summary>Name der Verbindung; '' = überall.</summary>
    Connection: string;
    /// <summary>Tracker-Projekt; '' = jedes.</summary>
    Project: string;
    /// <summary>Vorgabe des Anbieters, wenn keine eigene Abfrage passt; nie gespeichert.</summary>
    Builtin: Boolean;
    class function Create(const AName, AQuery, AConnection, AProject: string): TAtlasTrackerQuery; static;
    /// <summary>Vorgabe des Anbieters mit Anzeigename AName (z. B. „Mir zugewiesen“).</summary>
    class function Fallback(const AName: string): TAtlasTrackerQuery; static;
  end;

  /// <summary>Marke „wieder offen“ an einem Issue.</summary>
  TAtlasTrackerReopen = record
    Key: string;
    Title: string;
    /// <summary>Zustand jetzt und davor; '' unbekannt.</summary>
    State: string;
    Previous: string;
    /// <summary>Zeitpunkt der Rückkehr bzw. der Erkennung (UTC).</summary>
    At: TDateTime;
    /// <summary>Beendet am (UTC); 0 = nicht mit Atlas beendet. Kommentare danach sind der Grund.</summary>
    EndedAt: TDateTime;
    /// <summary>Branch aus dem Beenden; '' = nach dem Muster.</summary>
    Branch: string;
    /// <summary>Neuester Kommentar seit dem Beenden: Urheber, Zeitpunkt (UTC), Text gekürzt; '' bzw. 0 ohne.
    /// </summary>
    CommentBy: string;
    CommentAt: TDateTime;
    Comment: string;
  end;

  /// <summary>Ein Eintrag der Klappliste „Tracker-Projekt“ (#1927).</summary>
  TAtlasTrackerChoice = record
    /// <summary>„projekt@verbindung“.</summary>
    Key: string;
    Connection: string;
    Project: string;
    /// <summary>„Gilt für“ der ersten Zeile mit diesem Paar; dient als Projekt für Zustand und Auflösung.</summary>
    Match: string;
    /// <summary>Index dieser Zeile in den persönlichen Zeilen.</summary>
    Index: Integer;
    /// <summary>„Verbindung · Projekt“ (ohne Projekt nur die Verbindung).</summary>
    function Caption: string;
  end;

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

  /// <summary>Kopf einer Gruppe bei „Alle Tracker-Projekte“ (#1928).</summary>
  TAtlasIssuesGroup = record
    /// <summary>„Verbindung · Tracker-Projekt“.</summary>
    Caption: string;
    /// <summary>Projekt (Pfad aus „Gilt für“), für „Beginnen“ der Zeilen dieser Gruppe.</summary>
    Project: string;
    /// <summary>Index der ersten Zeile in Items; bei einer leeren Gruppe der der nächsten.</summary>
    First: Integer;
    /// <summary>Gezeigte und gefundene Zeilen.</summary>
    Shown: Integer;
    Total: Integer;
    Status: TAtlasIssuesStatus;
    Error: TAtlasCiFetchError;
    Querying: Boolean;
    /// <summary>Weitere, nicht gezeigte Zeilen („+ N weitere“).</summary>
    function More: Integer;
  end;

  /// <summary>Was die Kachel „Meine Issues“ zeigt.</summary>
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
    /// <summary>Marken „wieder offen“ (#2127, issues.reopened); leer ohne.</summary>
    Reopened: TArray<TAtlasTrackerReopen>;
    /// <summary>Prüfzustände des Trackers (#2126, issues.reviewStates): Zeilen in diesen Zuständen bieten „Prüfen“
    /// statt „Beginnen“; leer = nur im Kontextmenü.</summary>
    ReviewStates: TArray<string>;
    /// <summary>Klappliste „Tracker-Projekt“ (#1927, issues.projectPicker), ihre Einträge und die Wahl ('' =
    /// automatisch, "*" = alle, sonst „projekt@verbindung“).</summary>
    ProjectPicker: Boolean;
    ProjectChoices: TArray<TAtlasTrackerChoice>;
    ProjectKey: string;
    /// <summary>Eintrag „Alle Tracker-Projekte“ anbieten (issues.allProjects).</summary>
    AllProjects: Boolean;
    /// <summary>Name des Delphi-Projekts, nach dem „Automatisch“ wählt; '' ohne.</summary>
    AutomaticName: string;
    /// <summary>Gruppen bei „Alle“ (#1928); leer sonst.</summary>
    Groups: TArray<TAtlasIssuesGroup>;
    /// <summary>Offene Issues der Liste, z. B. für „ATL-123 · 3 offen“.</summary>
    function OpenCount: Integer;
    /// <summary>AKey trägt einen Punkt (ohne Groß-/Kleinschreibung).</summary>
    function IsUnseen(const AKey: string): Boolean;
    /// <summary>Marke „wieder offen“ von AKey; False ohne.</summary>
    function ReopenOf(const AKey: string; out AReopen: TAtlasTrackerReopen): Boolean;
  end;

implementation

{ TAtlasTrackerQuery }

class function TAtlasTrackerQuery.Create(const AName, AQuery, AConnection, AProject: string): TAtlasTrackerQuery;
begin
  Result.Name := Trim(AName);
  // Einzeilig: der Anbieter hängt die Abfrage an die Adresse.
  Result.Query := Trim(AQuery.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' '));
  Result.Connection := Trim(AConnection);
  Result.Project := Trim(AProject);
  Result.Builtin := False;
end;

class function TAtlasTrackerQuery.Fallback(const AName: string): TAtlasTrackerQuery;
begin
  Result := Create(AName, '', '', '');
  Result.Builtin := True;
end;

{ TAtlasTrackerChoice }

function TAtlasTrackerChoice.Caption: string;
begin
  Result := Connection;
  if Project <> '' then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + Project;
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

{ TAtlasIssuesGroup }

function TAtlasIssuesGroup.More: Integer;
begin
  Result := Total - Shown;
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

function TAtlasIssuesView.ReopenOf(const AKey: string; out AReopen: TAtlasTrackerReopen): Boolean;
var
  mReopen: TAtlasTrackerReopen;
begin
  AReopen := Default(TAtlasTrackerReopen);
  Result := False;
  if AKey = '' then
  begin
    Exit;
  end;
  for mReopen in Reopened do
  begin
    if SameText(mReopen.Key, AKey) then
    begin
      AReopen := mReopen;
      Exit(True);
    end;
  end;
end;

end.
