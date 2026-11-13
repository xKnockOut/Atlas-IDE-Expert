unit Atlas.Core.Tracker.Contract;

// Issue-Tracker für den Bereich „Meine Issues“ der Willkommensseite (#765),
// ohne VCL und Open Tools API.
// - IAtlasTrackerProvider: ein Anbieter (GitHub,
//   Atlas.Core.Tracker.Providers.GitHub; YouTrack,
//   Atlas.Core.Tracker.Providers.YouTrack). Weitere (GitLab, Jira, Redmine)
//   kommen als eigene Umsetzung dazu, ohne dass sich der Bereich ändert; die
//   Komposition wählt sie über TAtlasTrackerTarget.Provider.
// - Das Netz kommt wie beim Build-Server (#763) über IAtlasCiTransport; die
//   echte Umsetzung sendet das Token aus dem Anmeldespeicher von Windows als
//   „Authorization: Bearer“ nur über https und nur an ApiServer.
// - TAtlasTrackerTarget: Anbieter, Adresse und Projekt aus der Projektdatei
//   .atlas (Abschnitt "tracker"), die Abfrage aus den Einstellungen; nie
//   Zugangsdaten.
// - ProbeUrl: Adresse, an der „Verbindung prüfen“ (#1260) das Token einmal
//   ausprobiert; Auswertung in Atlas.Core.Tracker.Connections.
// - ListUrl, SentQuery, ParseList, LocaleUrl: „Testen“ im Dialog „Abfrage
//   bearbeiten“ (#1263) schickt die Abfrage einmal und zeigt die gesendete
//   Abfrage; LocaleUrl liefert die Sprache der Oberfläche (YouTrack), von der
//   die Vorgabe „Mir zugewiesen“ abhängt (TAtlasTrackerTarget.Language).
// - TAtlasTrackerIssue: ein Issue der Liste mit den Feldern, die der Bereich
//   zeigt (GitHub: Labels und verknüpfter Pull Request mit CI-Ampel;
//   YouTrack: Zustand, Priorität, Sprint).
// - TAtlasTrackerDetails (#1264): ein Issue für das Fenster „Atlas-Issue“ mit
//   Feldern, Beschreibung (Markdown), Kommentaren, Anhängen und verknüpften
//   Issues; IAtlasTrackerProvider.Details liest es. Kein Feld enthält ein
//   Token; Adressen kommen aus der Antwort des Trackers und werden vor dem
//   Öffnen geprüft (nur https bzw. derselbe Server).
// - IAtlasTrackerWriter (#1266): Zustand, Zuständigkeit und Kommentar eines
//   Issues ändern (TAtlasTrackerWrite) und Werte für Klapplisten lesen
//   (Zustände, Felder, Benutzer); Anbieter, die schreiben können, setzen sie
//   zusätzlich um. Geschrieben wird über IAtlasCiSend, nur nach einem Klick
//   des Benutzers und nie wiederholt; Fehler kommen mit dem Text des Trackers
//   zurück (TAtlasTrackerWriteResult). Unter einer Zustandsmaschine
//   (#2122) trägt die Änderung statt des Zielwerts einen Übergang;
//   IAtlasTrackerStateRules liest die erlaubten Übergänge eines Issues.
//   Beim Beenden kann die Änderung einen Schließgrund tragen (#2135,
//   TAtlasTrackerClose: erledigt, nicht geplant, Duplikat, offen lassen);
//   nur GitHub wertet ihn aus.
// - IAtlasTrackerFields (#2123): Felder des Projekts mit ihren Werten lesen
//   und einzelne Felder eines Issues setzen (Beenden-Dialog, issues.endFields);
//   nur Anbieter mit benannten Feldern (YouTrack) setzen es um.
// - IAtlasTrackerTimeWriter (#1267): Zeit als Work Item buchen
//   (TAtlasTrackerWorkItem) und Zeiterfassung des Projekts mit Arbeitstypen
//   lesen; nur Anbieter mit Zeiterfassung (YouTrack) setzen sie um.
// - IAtlasTrackerDescriptions (#1273): Beschreibung ungekürzt lesen und
//   zurückschreiben (abgehakte Checklisten); Anbieter, die schreiben können,
//   setzen sie zusätzlich um. Geschrieben wird über IAtlasCiSend.
// - Verknüpfungen (#1279): TAtlasTrackerLink.Kind (hängt ab von, blockiert,
//   Unteraufgabe, übergeordnet, Duplikat, bezieht sich auf, Erwähnung) mit
//   Zustand des verknüpften Issues; Baum, Fortschritt und „blockiert“ in
//   Atlas.Core.Tracker.Links. IAtlasTrackerLinkWriter (optional, über
//   Supports) legt Unteraufgaben an und verknüpft Issues über IAtlasCiSend.
// - Search und Lookup (#1270): Suche der Befehlspalette, je eine Abfrage ohne
//   Pull Requests und Ampeln; Lookup liest ein Issue zur Kennung.
// - IAtlasTrackerPeople (#1278): Benutzer für @-Erwähnungen im
//   Kommentar-Editor (TAtlasTrackerUser mit Anmelde- und Anzeigename);
//   Filter und Ranked ordnen die Treffer zum getippten Text.
// - TAtlasTrackerDevelopment (#1269): was der Tracker zur Entwicklung eines
//   Issues weiß, für den Reiter „Entwicklung“ der Vorschau: Pull Requests mit
//   Zustand und CI-Ampel (GitHub) bzw. verknüpfte VCS-Änderungen (YouTrack);
//   IAtlasTrackerProvider.Development liest es. Branches und Commits kommen
//   nicht vom Tracker, sondern aus der Versionsverwaltung
//   (Atlas.Core.Tracker.Development).
// - TAtlasTrackerChange (#1271): eine Änderung an einem Issue (neuer
//   Kommentar, Zuweisung, Zustand) seit dem letzten Stand;
//   IAtlasTrackerProvider.Changes liest sie für die Meldungen in der
//   Benachrichtigungszentrale (Atlas.Core.Tracker.Notify). TAtlasTrackerPoll
//   trägt den Stand von Abfrage zu Abfrage (seit wann, angemeldeter Benutzer,
//   Umfang, bei GitHub Last-Modified und X-Poll-Interval).
// - IAtlasTrackerPullRequests (#2136, optional über Supports): beim Beenden
//   einen Pull Request anlegen (TAtlasTrackerPullSpec → TAtlasTrackerPullResult).
// Abfragen laufen im Hintergrund; nichts davon zeigt einen Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand der Prüfungen (CI) eines Pull Requests: Ampel im Bereich.</summary>
  TAtlasTrackerChecks = (Unknown, Pending, Success, Failure);
  /// <summary>Zuständigkeit bei einer Änderung (#1266): lassen, mir zuweisen oder an einen Benutzer übergeben.
  /// </summary>
  TAtlasTrackerAssign = (Keep, Me, User);
  /// <summary>Werte für die Klapplisten (#1266): Zustände des Zustandsfeldes (GitHub: Labels), Namen der
  /// Zustandsfelder, Namen der Benutzerfelder (YouTrack) und Benutzer, an die übergeben werden kann. Dazu bei GitHub
  /// (#2134) die Projekte des Repositorys („owner/nummer“) und die Optionen des Statusfeldes des Projekts
  /// AField ('' = erstes); andere Anbieter liefern dafür nichts.</summary>
  TAtlasTrackerValueKind = (States, StateFields, UserFields, Users, Projects, ProjectStates);
  /// <summary>Art einer Verknüpfung aus Sicht des gezeigten Issues (#1279). DependsOn: dieses hängt vom anderen
  /// ab (das andere blockiert dieses); Blocks: das andere hängt von diesem ab; Subtask: das andere ist
  /// Unteraufgabe; Parent: das andere ist übergeordnet; Duplicates: dieses ist Duplikat des anderen; DuplicatedBy:
  /// das andere ist Duplikat von diesem; Mentioned: Erwähnung (GitHub); PullRequest: Pull Request (GitHub).
  /// </summary>
  TAtlasTrackerLinkKind = (Other, DependsOn, Blocks, Subtask, Parent, Duplicates, DuplicatedBy, Relates, Mentioned,
    PullRequest);
  /// <summary>Zustand eines Pull Requests im Reiter „Entwicklung“ (#1269).</summary>
  TAtlasTrackerPullState = (Open, Draft, Merged, Closed);
  /// <summary>Art einer Änderung an einem Issue (#1271).</summary>
  TAtlasTrackerChangeKind = (
    /// <summary>Neuer Kommentar.</summary>
    Comment,
    /// <summary>Zuständig geändert (Value: neuer Zuständiger, ToMe: mir zugewiesen).</summary>
    Assigned,
    /// <summary>Zustand geändert (Value: neuer Zustand).</summary>
    State,
    /// <summary>Sonstige Änderung, die der Tracker meldet (GitHub-Benachrichtigung ohne erkennbare Einzelheit).
    /// </summary>
    Other);
  /// <summary>issues.notify.scope (#1271): welche Issues beobachtet werden. Jeder Umfang schließt den vorigen ein.
  /// </summary>
  TAtlasTrackerNotifyScope = (
    /// <summary>Mir zugewiesen.</summary>
    Assigned,
    /// <summary>Mir zugewiesen oder von mir erstellt (Vorgabe).</summary>
    AssignedOrCreated,
    /// <summary>Dazu die beobachteten (YouTrack „Abonniert“/Stern, GitHub „subscribed“).</summary>
    Watched);
  /// <summary>Abschluss beim Beenden (#2135, GitHub-Schließgründe).</summary>
  TAtlasTrackerClose = (
    /// <summary>Wie bisher: ein Erledigt-Zustand schließt als „completed“, sonst bleibt das Issue offen.</summary>
    ByState,
    /// <summary>Schließen als erledigt ("completed").</summary>
    Completed,
    /// <summary>Schließen als „nicht geplant“ ("not_planned").</summary>
    NotPlanned,
    /// <summary>Schließen als Duplikat ("duplicate") von TAtlasTrackerWrite.DuplicateOf.</summary>
    Duplicate,
    /// <summary>Offen lassen, auch bei einem Erledigt-Zustand.</summary>
    KeepOpen);
{$SCOPEDENUMS OFF}

  /// <summary>Höchstlängen der Texte, die die Parser aus Tracker-Antworten übernehmen (Zeichen).</summary>
  TAtlasTrackerTextLimits = record
  public const
    /// <summary>Login, Schlagwort, Beziehung.</summary>
    cName = 60;
    /// <summary>Vollständiger Name einer Person.</summary>
    cPerson = 80;
    /// <summary>Titel in Listen und Verweisen, Name eines Anhangs.</summary>
    cTitle = 200;
    /// <summary>Fehlermeldung des Servers.</summary>
    cMessage = 300;
    /// <summary>Titel in der Detailansicht.</summary>
    cDetailsTitle = 500;
    /// <summary>Beschreibung eines Pull Requests.</summary>
    cBody = 4000;
  end;

  /// <summary>Offener Pull Request zu einem Issue (GitHub).</summary>
  TAtlasTrackerPullRequest = record
    /// <summary>0 = kein Pull Request.</summary>
    Number: Integer;
    Checks: TAtlasTrackerChecks;
    Draft: Boolean;
    /// <summary>"unknown", "pending", "success" bzw. "failure".</summary>
    class function ChecksKey(AChecks: TAtlasTrackerChecks): string; static;
    /// <summary>Umkehrung von ChecksKey; Unknown für fremde Texte.</summary>
    class function ChecksOf(const AKey: string): TAtlasTrackerChecks; static;
  end;

  /// <summary>Ein Issue der Liste.</summary>
  TAtlasTrackerIssue = record
  public const
    /// <summary>Höchstens so viele Labels werden gelesen und gespeichert.</summary>
    cMaxLabels = 6;
    /// <summary>Höchstens so viele Zeichen eines Titels werden gespeichert.</summary>
    cMaxTitle = 200;
  public
    /// <summary>Kennung wie im Tracker: "#753" (GitHub), "ATL-123" (YouTrack).</summary>
    Key: string;
    /// <summary>Nummer im Projekt (753 bzw. 123); 0 = unbekannt.</summary>
    Number: Integer;
    Title: string;
    /// <summary>GitHub: Namen der Labels.</summary>
    Labels: TArray<string>;
    /// <summary>YouTrack: Zustand, Priorität und Sprint bzw. Board; '' ohne.</summary>
    State: string;
    Priority: string;
    Sprint: string;
    /// <summary>GitHub: verknüpfter offener Pull Request.</summary>
    PullRequest: TAtlasTrackerPullRequest;
    /// <summary>Zuständig (Anzeigename bzw. Login, mehrere mit ", "); '' ohne (#1270).</summary>
    Assignee: string;
    class function Empty: TAtlasTrackerIssue; static;
  end;

  /// <summary>Kommentar eines Issues (#1264).</summary>
  TAtlasTrackerComment = record
    Author: string;
    /// <summary>UTC; 0 = unbekannt.</summary>
    Created: TDateTime;
    /// <summary>Markdown wie im Tracker.</summary>
    Text: string;
  end;

  /// <summary>Anhang eines Issues (#1264).</summary>
  TAtlasTrackerAttachment = record
    Name: string;
    /// <summary>Bytes; -1 = unbekannt.</summary>
    Size: Int64;
    /// <summary>Absolute Adresse zum Laden.</summary>
    Url: string;
    MimeType: string;
    /// <summary>Liegt nicht beim Server des Tokens (GitHub-Dateien): öffnet im Browser statt zu laden.</summary>
    External: Boolean;
    function IsImage: Boolean;
  end;

  /// <summary>Verknüpftes Issue (#1264): YouTrack-Link bzw. GitHub-Verweis.</summary>
  TAtlasTrackerLink = record
    /// <summary>Kennung im selben Tracker ("ATL-12", "#753"); bei GitHub aus einem anderen Repository
    /// "owner/repo#12".</summary>
    Key: string;
    Title: string;
    /// <summary>Art der Verknüpfung wie im Tracker ("relates to", "is required for", "mentioned").</summary>
    Relation: string;
    /// <summary>Seite im Browser, wenn das Issue nicht im selben Fenster geöffnet werden kann; '' sonst.</summary>
    Page: string;
    /// <summary>Im selben Tracker und Projekt: Klick öffnet es in „Atlas-Issue“.</summary>
    Local: Boolean;
    /// <summary>Art der Verknüpfung (#1279); Other, wenn der Tracker sie nicht nennt.</summary>
    Kind: TAtlasTrackerLinkKind;
    /// <summary>Zustand des verknüpften Issues ist bekannt (#1279); sonst gelten State und Resolved nicht.
    /// </summary>
    StateKnown: Boolean;
    /// <summary>Zustand wie im Tracker ("Offen", "In Arbeit", "closed"); '' ohne.</summary>
    State: string;
    /// <summary>Erledigt (YouTrack: resolved, GitHub: closed).</summary>
    Resolved: Boolean;
    /// <summary>Kennung der Art für den Zwischenspeicher: "dependsOn", "blocks", "subtask" …; "" für Other.</summary>
    class function KindKey(AKind: TAtlasTrackerLinkKind): string; static;
    /// <summary>Umkehrung von KindKey; Other für fremde Texte.</summary>
    class function KindOf(const AKey: string): TAtlasTrackerLinkKind; static;
    /// <summary>Offen und als „hängt ab von“ verknüpft: blockiert das gezeigte Issue.</summary>
    function Blocking: Boolean;
  end;

  /// <summary>Benutzer des Trackers für @-Erwähnungen (#1278).</summary>
  TAtlasTrackerUser = record
    /// <summary>Anmeldename, wie ihn eine Erwähnung braucht ("anna").</summary>
    Login: string;
    /// <summary>Anzeigename ("Anna Berger"); '' ohne (GitHub).</summary>
    Name: string;
    class function Create(const ALogin, AName: string): TAtlasTrackerUser; static;
    /// <summary>Anmelde- oder Anzeigename enthält AText (ohne Groß-/Kleinschreibung); leerer Text passt immer.
    /// </summary>
    function Matches(const AText: string): Boolean;
    /// <summary>Rang zu AText: 0 Anmeldename beginnt damit, 1 ein Wort des Anzeigenamens, 2 enthalten, 3 sonst.
    /// </summary>
    function Rank(const AText: string): Integer;
    /// <summary>Nur passende Benutzer (Matches), nach Rang, sonst in der Reihenfolge der Liste; höchstens AMax,
    /// ohne leere und doppelte Anmeldenamen.</summary>
    class function Filter(const AUsers: TArray<TAtlasTrackerUser>; const AText: string;
      AMax: Integer): TArray<TAtlasTrackerUser>; static;
    /// <summary>Wie Filter, behält aber Benutzer ohne Treffer im Text (der Tracker hat sie gefunden, etwa über die
    /// E-Mail-Adresse) hinter den passenden.</summary>
    class function Ranked(const AUsers: TArray<TAtlasTrackerUser>; const AText: string;
      AMax: Integer): TArray<TAtlasTrackerUser>; static;
  end;

  /// <summary>Ein Issue mit allem, was das Fenster „Atlas-Issue“ zeigt (#1264).</summary>
  TAtlasTrackerDetails = record
  public const
    /// <summary>Höchstens so viele Kommentare werden gelesen.</summary>
    cMaxComments = 100;
    /// <summary>Höchstens so viele Anhänge bzw. Verknüpfungen.</summary>
    cMaxAttachments = 50;
    cMaxLinks = 50;
    /// <summary>Höchstens so viele Zeichen je Beschreibung bzw. Kommentar.</summary>
    cMaxText = 100000;
    /// <summary>Längste Beschreibung, die Atlas zurückschreibt (#1273); länger: Invalid, nichts wird geschrieben.
    /// </summary>
    cMaxDescription = 1000000;
  public
    Key: string;
    Number: Integer;
    Title: string;
    /// <summary>Seite des Issues im Browser.</summary>
    Page: string;
    State: string;
    Priority: string;
    /// <summary>Typ (Bug, Feature …).</summary>
    Kind: string;
    Assignee: string;
    /// <summary>Sprint bzw. Meilenstein.</summary>
    Sprint: string;
    /// <summary>Labels (GitHub) bzw. Tags (YouTrack).</summary>
    Labels: TArray<string>;
    /// <summary>UTC; 0 = unbekannt.</summary>
    Created: TDateTime;
    Updated: TDateTime;
    /// <summary>Markdown.</summary>
    Description: string;
    /// <summary>Kommentare wurden abgefragt (issues.preview.comments).</summary>
    CommentsLoaded: Boolean;
    /// <summary>Älteste zuerst.</summary>
    Comments: TArray<TAtlasTrackerComment>;
    Attachments: TArray<TAtlasTrackerAttachment>;
    Links: TArray<TAtlasTrackerLink>;
    /// <summary>Zeitpunkt der Abfrage (UTC); für „Stand vom …“.</summary>
    Fetched: TDateTime;
    class function Empty: TAtlasTrackerDetails; static;
    /// <summary>Für die Liste „Meine Issues“: Kennung, Titel und Felder.</summary>
    function Issue: TAtlasTrackerIssue;
    /// <summary>Anhang mit dem Namen AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function AttachmentIndex(const AName: string): Integer;
  end;

  /// <summary>Pull Request zu einem Issue im Reiter „Entwicklung“ (#1269), offen oder geschlossen.</summary>
  TAtlasTrackerPull = record
    Number: Integer;
    Title: string;
    /// <summary>Branch des Pull Requests (head.ref).</summary>
    Branch: string;
    State: TAtlasTrackerPullState;
    /// <summary>CI-Ampel des letzten Commits; Unknown, wenn nicht abgefragt.</summary>
    Checks: TAtlasTrackerChecks;
    /// <summary>Zuletzt geändert (UTC); 0 = unbekannt.</summary>
    Updated: TDateTime;
    /// <summary>Seite im Browser, aus der eingetragenen Adresse gebildet (nie aus der Antwort).</summary>
    Page: string;
  end;

  /// <summary>Änderung in der Versionsverwaltung, die der Tracker dem Issue zugeordnet hat (YouTrack, #1269).
  /// </summary>
  TAtlasTrackerVcsChange = record
    /// <summary>Commit bzw. Revision wie in der Versionsverwaltung.</summary>
    Version: string;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Text: string;
    Author: string;
    /// <summary>UTC; 0 = unbekannt.</summary>
    Date: TDateTime;
  end;

  /// <summary>Was der Tracker zur Entwicklung eines Issues liefert (#1269).</summary>
  TAtlasTrackerDevelopment = record
  public const
    /// <summary>Höchstens so viele Pull Requests bzw. Änderungen.</summary>
    cMaxPulls = 20;
    cMaxChanges = 100;
  public
    /// <summary>Neueste zuerst.</summary>
    Pulls: TArray<TAtlasTrackerPull>;
    /// <summary>Neueste zuerst.</summary>
    Changes: TArray<TAtlasTrackerVcsChange>;
    /// <summary>Mit dem Issue verknüpfte Branches (GitHub „Development“, #2138), Namen ohne Remote; leer ohne.
    /// </summary>
    LinkedBranches: TArray<string>;
    class function Empty: TAtlasTrackerDevelopment; static;
  end;

  /// <summary>Eine Änderung an einem Issue seit dem letzten Stand (#1271).</summary>
  TAtlasTrackerChange = record
  public const
    /// <summary>Höchstlänge von Text.</summary>
    cMaxText = 300;
  public
    /// <summary>Kennung wie im Tracker ("ATL-123", "#753").</summary>
    Key: string;
    /// <summary>GitHub: "owner/repo" des Issues (Benachrichtigungen kommen aus allen Repositories); sonst ''.
    /// </summary>
    Project: string;
    /// <summary>Titel des Issues; '' = unbekannt.</summary>
    Title: string;
    Kind: TAtlasTrackerChangeKind;
    /// <summary>Anmeldename des Urhebers (Vergleich mit dem angemeldeten Benutzer); '' = unbekannt.</summary>
    Author: string;
    /// <summary>Anzeigename des Urhebers; '' = wie Author.</summary>
    AuthorName: string;
    /// <summary>Zeitpunkt (UTC).</summary>
    Time: TDateTime;
    /// <summary>State: neuer Zustand; Assigned: neuer Zuständiger (Anzeigename); sonst ''.</summary>
    Value: string;
    /// <summary>Assigned: dem angemeldeten Benutzer zugewiesen.</summary>
    ToMe: Boolean;
    /// <summary>State: Zustand davor (#2127, wieder geöffnete Issues); '' = unbekannt.</summary>
    Previous: string;
    /// <summary>Comment: Text des Kommentars, gekürzt auf cMaxText (#2127, Grund in der Meldung); sonst ''.
    /// </summary>
    Text: string;
    class function Create(const AKey: string; AKind: TAtlasTrackerChangeKind; const AAuthor: string;
      ATime: TDateTime): TAtlasTrackerChange; static;
    /// <summary>Anzeigename, sonst der Anmeldename.</summary>
    function Who: string;
  end;

  /// <summary>Stand der Abfrage nach Änderungen einer Verbindung (#1271), von Abfrage zu Abfrage weitergereicht.
  /// </summary>
  TAtlasTrackerPoll = record
    /// <summary>Änderungen nach diesem Zeitpunkt (UTC) sind neu.</summary>
    Since: TDateTime;
    /// <summary>Anmeldename des angemeldeten Benutzers (eigene Änderungen entfallen, Zuweisung an mich).</summary>
    Me: string;
    Scope: TAtlasTrackerNotifyScope;
    /// <summary>GitHub: Last-Modified der letzten Antwort von /notifications (If-Modified-Since); '' ohne.
    /// </summary>
    LastModified: string;
    /// <summary>GitHub: X-Poll-Interval der letzten Antwort in Sekunden; 0 ohne.</summary>
    PollSeconds: Integer;
    /// <summary>Neuester Zeitpunkt, den die Abfrage gesehen hat (UTC; auch eigene Änderungen); 0 ohne. Wird zum
    /// nächsten Since, damit eine falsch gehende Uhr nichts verschluckt.</summary>
    Latest: TDateTime;
    class function Create(ASince: TDateTime; const AMe: string; AScope: TAtlasTrackerNotifyScope): TAtlasTrackerPoll;
      static;
  end;

  /// <summary>Was abgefragt wird; ohne Zugangsdaten.</summary>
  TAtlasTrackerTarget = record
  public const
    cGitHub = 'github';
    cYouTrack = 'youtrack';
    /// <summary>Adresse von GitHub, wenn .atlas keine nennt.</summary>
    cGitHubUrl = 'https://github.com';
  public
    /// <summary>"github" oder "youtrack".</summary>
    Provider: string;
    /// <summary>Adresse ohne „/“ am Ende: "https://github.com", "https://firma.youtrack.cloud".</summary>
    Url: string;
    /// <summary>GitHub "owner/repo", YouTrack Projektkürzel ("ATL"); bei YouTrack darf es fehlen.</summary>
    Project: string;
    /// <summary>Abfrage in der Sprache des Trackers; '' = Vorgabe des Anbieters.</summary>
    Query: string;
    /// <summary>Sprache der Oberfläche des Trackers ("de", "en"), erkannt beim Prüfen der Verbindung (#1263);
    /// '' = unbekannt. Davon hängt die Vorgabe-Abfrage ab (Atlas.Core.Tracker.Templates).</summary>
    Language: string;
    /// <summary>GitHub ohne Adresse: github.com; GitHub-Adresse mit "/owner/repo" und ohne Projekt: das Projekt
    /// kommt aus der Adresse.</summary>
    class function Create(const AProvider, AUrl, AProject, AQuery: string): TAtlasTrackerTarget; static;
    /// <summary>Anbieter und Server bekannt, bei GitHub auch "owner/repo".</summary>
    function Configured: Boolean;
    /// <summary>Schema, Rechner und Port in Kleinbuchstaben; '' bei ungültiger Adresse (wie TAtlasCiJob.Server).
    /// </summary>
    function Server: string;
    /// <summary>Name des Eintrags im Anmeldespeicher von Windows: "Atlas:tracker:" + Server.</summary>
    function CredentialTarget: string;
    /// <summary>Kennung für Vergleich und Merker (klein).</summary>
    function Key: string;
    /// <summary>Server mit https://.</summary>
    function Secure: Boolean;
  end;

  /// <summary>Verbindung einer Abfrage: Ziel, Transport und Zeitgrenze für die ganze Abfrage.</summary>
  TAtlasTrackerCall = record
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    TimeoutMs: Integer;
    class function Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      ATimeoutMs: Integer): TAtlasTrackerCall; static;
  end;

{$SCOPEDENUMS ON}

  /// <summary>Ergebnis von „Branch auf dem Tracker anlegen und verknüpfen“ (#2138).</summary>
  TAtlasTrackerBranchLinkOutcome = (
    /// <summary>Nicht versucht.</summary>
    None,
    /// <summary>Branch auf dem Server angelegt und mit dem Issue verknüpft.</summary>
    Created,
    /// <summary>Das Issue hat schon einen verknüpften Branch (Branch nennt ihn); nichts angelegt.</summary>
    Found,
    /// <summary>Den Branch gibt es schon (lokal oder auf dem Server); nichts verknüpft.</summary>
    Exists,
    /// <summary>Der Remote origin ist nicht das Repository des Trackers.</summary>
    Foreign,
    /// <summary>Dem Token fehlt das Recht, Branches anzulegen.</summary>
    Denied,
    /// <summary>Anfrage gescheitert (Error, Message), bzw. der Abruf danach (Fetch).</summary>
    Failed);

{$SCOPEDENUMS OFF}

  /// <summary>Branch beim Beginnen auf dem Tracker anlegen (#2138).</summary>
  TAtlasTrackerBranchLink = record
    Outcome: TAtlasTrackerBranchLinkOutcome;
    /// <summary>Angelegter bzw. gefundener Branch ohne Remote; '' ohne.</summary>
    Branch: string;
    /// <summary>Branch, von dessen Kopf angelegt wurde; '' ohne.</summary>
    Base: string;
    Error: TAtlasCiFetchError;
    /// <summary>Erster Fehlertext des Servers; '' ohne.</summary>
    Message: string;
    class function Make(AOutcome: TAtlasTrackerBranchLinkOutcome; const ABranch: string): TAtlasTrackerBranchLink;
      static;
    class function Failure(AError: TAtlasCiFetchError; const AMessage: string): TAtlasTrackerBranchLink; static;
    /// <summary>Created oder Found: Der Branch liegt auf dem Server und gehört zum Issue.</summary>
    function OnServer: Boolean;
  end;

  /// <summary>Branch beim Beginnen auf dem Tracker anlegen und mit dem Issue verknüpfen (#2138, GitHub
  /// createLinkedBranch); optional, „Beginnen“ fragt mit Supports. Läuft im Hintergrund.</summary>
  IAtlasTrackerBranchLinker = interface
    ['{3C9E1F74-8A25-4B6D-9E13-7F42D0B8C5A6}']
    /// <summary>AOriginUrl (Remote origin der Arbeitskopie) zeigt auf das Repository des Ziels.</summary>
    function SameRepository(const ATarget: TAtlasTrackerTarget; const AOriginUrl: string): Boolean;
    /// <summary>Hat Issue AKey schon einen verknüpften Branch, diesen (Found); gibt es ABranch auf dem Server,
    /// Exists; sonst ABranch vom Kopf von ABase (fehlt sie, vom Standard-Branch) anlegen und verknüpfen.</summary>
    function LinkBranch(const ACall: TAtlasTrackerCall; const AKey, ABranch, ABase: string): TAtlasTrackerBranchLink;
  end;

{$SCOPEDENUMS ON}

  /// <summary>Ergebnis von „Pull Request anlegen“ beim Beenden (#2136).</summary>
  TAtlasTrackerPullOutcome = (
    /// <summary>Nicht versucht.</summary>
    None,
    /// <summary>Gepusht und angelegt.</summary>
    Created,
    /// <summary>Gepusht; für den Branch gab es schon einen offenen Pull Request, kein zweiter.</summary>
    Existing,
    /// <summary>Die Arbeitskopie hat ungesicherte Änderungen; nichts gepusht.</summary>
    Dirty,
    /// <summary>Der Remote origin ist nicht das Repository des Trackers (Fork); nichts gepusht.</summary>
    Foreign,
    /// <summary>Der Push scheiterte (Message nennt den Grund); nichts angelegt.</summary>
    PushFailed,
    /// <summary>Anfrage an den Tracker gescheitert (Error, Status, Message).</summary>
    Failed);

{$SCOPEDENUMS OFF}

  /// <summary>Was beim Beenden als Pull Request angelegt werden soll (#2136).</summary>
  TAtlasTrackerPullSpec = record
    /// <summary>False = kein Pull Request.</summary>
    Wanted: Boolean;
    /// <summary>Branch des Issues (Quelle) und Ziel; Base '' = Standard-Branch des Repositorys.</summary>
    Head: string;
    Base: string;
    Title: string;
    Body: string;
    /// <summary>Labels und Meilenstein des Issues übernehmen.</summary>
    CopyIssue: Boolean;
    /// <summary>Anmeldenamen der Prüfer.</summary>
    Reviewers: TArray<string>;
    Draft: Boolean;
    class function None: TAtlasTrackerPullSpec; static;
  end;

  /// <summary>Angelegter bzw. vorhandener Pull Request (#2136).</summary>
  TAtlasTrackerPullResult = record
    Outcome: TAtlasTrackerPullOutcome;
    /// <summary>0 ohne Pull Request.</summary>
    Number: Integer;
    /// <summary>Seite im Browser; '' ohne.</summary>
    Url: string;
    /// <summary>Ziel des Pull Requests; '' unbekannt.</summary>
    Base: string;
    Draft: Boolean;
    Error: TAtlasCiFetchError;
    Status: Integer;
    /// <summary>Fehlertext des Servers bzw. Grund des gescheiterten Pushs; '' ohne.</summary>
    Message: string;
    /// <summary>Der Pull Request steht, aber Labels und Meilenstein bzw. Prüfer ließen sich nicht setzen.</summary>
    DecorateFailed: Boolean;
    ReviewersFailed: Boolean;
    class function Make(AOutcome: TAtlasTrackerPullOutcome): TAtlasTrackerPullResult; static;
    class function Failure(AError: TAtlasCiFetchError; AStatus: Integer;
      const AMessage: string): TAtlasTrackerPullResult; static;
    /// <summary>Created oder Existing: Es gibt einen offenen Pull Request für den Branch.</summary>
    function Stands: Boolean;
  end;

  /// <summary>Pull Requests anlegen (#2136, GitHub); optional, der Beenden-Dialog fragt mit Supports. Der Transport
  /// muss IAtlasCiSend können, sonst NotConfigured. Läuft im Hintergrund.</summary>
  IAtlasTrackerPullRequests = interface
    ['{6A1D3F85-2C47-4E9B-8B05-D3E7F19A2C64}']
    /// <summary>AOriginUrl (Remote origin der Arbeitskopie) zeigt auf das Repository des Ziels.</summary>
    function SameRepository(const ATarget: TAtlasTrackerTarget; const AOriginUrl: string): Boolean;
    /// <summary>Gibt es einen offenen Pull Request mit Kopf ASpec.Head, diesen (Existing); sonst anlegen, dann
    /// Labels und Meilenstein des Issues AKey (ASpec.CopyIssue) und Prüfer setzen.</summary>
    function CreatePull(const ACall: TAtlasTrackerCall; const AKey: string;
      const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult;
  end;

  /// <summary>Unteraufgaben anlegen und Issues verknüpfen (#1279); optional, die Vorschau fragt mit Supports. Der
  /// Transport muss IAtlasCiSend können, sonst NotConfigured. Läuft im Hintergrund.</summary>
  IAtlasTrackerLinkWriter = interface
    ['{8B3E5D21-4A7C-4F96-B2E8-1C6D9A4F7E53}']
    /// <summary>Neues Issue ATitle (ADescription als Markdown) im Projekt des Issues AParentKey anlegen und als
    /// Unteraufgabe verknüpfen. AKey: Kennung des neuen Issues, auch wenn nur das Verknüpfen scheiterte (dann
    /// False mit AError); '' wenn nichts angelegt wurde.</summary>
    function CreateSubtask(const ACall: TAtlasTrackerCall; const AParentKey, ATitle,
      ADescription: string; out AKey: string; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>AKey mit AOtherKey verknüpfen: DependsOn (AKey hängt von AOtherKey ab) bzw. Blocks (AOtherKey
    /// hängt von AKey ab); andere Arten: False mit Invalid.</summary>
    function AddLink(const ACall: TAtlasTrackerCall; const AKey: string; AKind: TAtlasTrackerLinkKind;
      const AOtherKey: string; out AError: TAtlasCiFetchError): Boolean;
  end;

  IAtlasTrackerProvider = interface
    ['{6F2A9C47-3E1B-4D85-B7A0-92C4E8D15F36}']
    /// <summary>Kennung wie in .atlas, z. B. "github".</summary>
    function Name: string;
    /// <summary>Anzeigename, z. B. "GitHub".</summary>
    function Caption: string;
    /// <summary>Abfrage, wenn issues.query leer ist.</summary>
    function DefaultQuery: string;
    /// <summary>Server der Schnittstelle (Origin), an den das Token gehen darf; '' ohne.</summary>
    function ApiServer(const ATarget: TAtlasTrackerTarget): string;
    /// <summary>Höchstens AMax Issues zur Abfrage, insgesamt höchstens ATimeoutMs; im Hintergrund. False mit AError,
    /// wenn keine Liste gelesen werden konnte.</summary>
    function Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs, AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Seite des Issues für den Browser, aus der eingetragenen Adresse; '' ohne.</summary>
    function IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
    /// <summary>Seite eines Pull Requests; '' ohne (YouTrack).</summary>
    function PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
    /// <summary>Adresse für „Verbindung prüfen“ (#1260): der angemeldete Benutzer mit "login" in der Antwort
    /// (YouTrack /api/users/me?fields=login, GitHub /user); '' ohne gültigen Server.</summary>
    function ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
    /// <summary>Adresse der Liste wie in Fetch (#1263); '' ohne gültigen Server bzw. ohne Projekt (GitHub).
    /// </summary>
    function ListUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
    /// <summary>Abfrage, wie sie an den Tracker geht (mit Projekt bzw. Repository, ohne Token).</summary>
    function SentQuery(const ATarget: TAtlasTrackerTarget): string;
    /// <summary>Antwort von ListUrl lesen; False, wenn sie keine Liste ist (z. B. eine Anmeldeseite).</summary>
    function ParseList(const AText: string; AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
    /// <summary>Sprache der Oberfläche (YouTrack /api/admin/globalSettings/localeSettings); '' ohne (GitHub).
    /// </summary>
    function LocaleUrl(const ATarget: TAtlasTrackerTarget): string;
    /// <summary>Issue AKey mit Feldern, Beschreibung, Anhängen und Verknüpfungen, mit AComments auch die
    /// Kommentare (sonst nicht abgefragt), insgesamt höchstens ACall.TimeoutMs; im Hintergrund (#1264). False mit
    /// AError, wenn das Issue nicht gelesen werden konnte.</summary>
    function Details(const ACall: TAtlasTrackerCall; const AKey: string; AComments: Boolean;
      out ADetails: TAtlasTrackerDetails; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Freitextsuche der Befehlspalette (#1270): höchstens AMax Issues zu AText im Projekt des Ziels, eine
    /// Abfrage ohne Pull Requests und Ampeln, höchstens ACall.TimeoutMs; im Hintergrund. Die Abfrage aus den
    /// Einstellungen (ACall.Target.Query) gilt hier nicht.</summary>
    function Search(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Issue AKey mit den Feldern der Liste (#1270), eine Abfrage, höchstens ATimeoutMs; im Hintergrund.
    /// False mit AError (NotFound, wenn es die Kennung nicht gibt).</summary>
    function Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Pull Requests (GitHub, mit CI-Ampel) bzw. verknüpfte VCS-Änderungen (YouTrack) zu Issue AKey,
    /// insgesamt höchstens ATimeoutMs; im Hintergrund (#1269). Ein Tracker ohne solche Angaben liefert True mit
    /// leerem Ergebnis. False mit AError, wenn die Abfrage scheiterte.</summary>
    function Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Änderungen an den Issues im Umfang APoll.Scope nach APoll.Since, über alle Projekte des Servers
    /// (#1271): neue Kommentare, Zuweisungen und Zustandswechsel, älteste zuerst; eigene sind noch dabei
    /// (Atlas.Core.Tracker.Notify filtert sie). Setzt APoll.Latest (und bei GitHub LastModified und PollSeconds).
    /// Insgesamt höchstens ATimeoutMs; im Hintergrund. False mit AError, wenn nichts gelesen werden konnte.
    /// </summary>
    function Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>; out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Übergang einer Zustandsmaschine (Workflow von YouTrack, #1569, #2122): Ereignis mit Kennung und
  /// Anzeigename.</summary>
  TAtlasTrackerTransition = record
    /// <summary>Kennung des Ereignisses ("in-progress"); '' = kein Übergang.</summary>
    Id: string;
    /// <summary>Anzeigename ("In Progress", "Beginnen").</summary>
    Name: string;
    class function Create(const AId, AName: string): TAtlasTrackerTransition; static;
    /// <summary>Anzeigename, ohne Namen die Kennung.</summary>
    function Caption: string;
  end;

  /// <summary>Sprint eines Boards, in den „Beginnen“ das Issue aufnimmt (#2128): Namen wie im Befehl des Trackers
  /// (YouTrack „Board“, Name des Boards, Name des Sprints).</summary>
  TAtlasTrackerSprintRef = record
    Board: string;
    Sprint: string;
    /// <summary>Ende des Sprints (UTC); 0 = unbekannt.</summary>
    Finish: TDateTime;
    class function Create(const ABoard, ASprint: string; AFinish: TDateTime): TAtlasTrackerSprintRef; static;
    class function None: TAtlasTrackerSprintRef; static;
    /// <summary>Board und Sprint sind gesetzt.</summary>
    function IsSet: Boolean;
  end;

  /// <summary>Regeln des Zustandsfeldes eines Issues (#1569, #2122). Steuert eine Zustandsmaschine das Feld
  /// (YouTrack „StateMachineIssueCustomField“), sind ab dem aktuellen Wert nur die Übergänge in Transitions
  /// erlaubt.</summary>
  TAtlasTrackerStateRules = record
    /// <summary>Das Feld steht unter einer Zustandsmaschine.</summary>
    StateMachine: Boolean;
    /// <summary>ID des Feldes am Issue ("82-11"), um einen Übergang auszulösen; '' unbekannt.</summary>
    FieldId: string;
    /// <summary>Aktueller Wert des Feldes; '' unbekannt.</summary>
    Current: string;
    /// <summary>Übergänge ab dem aktuellen Wert.</summary>
    Transitions: TArray<TAtlasTrackerTransition>;
  end;

  /// <summary>Wo GitHub den Zustand führt (#2134, issues.github.*): ToProject = im Projektfeld „Status“ (Projects
  /// v2), wenn das Issue in einem Projekt liegt, sonst als Label.</summary>
  TAtlasTrackerGitHubState = record
    ToProject: Boolean;
    /// <summary>Projekt „owner/nummer“ bei mehreren Projekten und für die Aufnahme; '' = erstes.</summary>
    Project: string;
    /// <summary>Issues ohne Projekt in Project aufnehmen.</summary>
    AddToProject: Boolean;
    /// <summary>„Beginnen“ legt den Branch auf GitHub an und verknüpft ihn mit dem Issue (#2138).</summary>
    LinkBranch: Boolean;
    /// <summary>Beenden-Dialog: Abschnitt „Pull Request anlegen“ vorab angehakt (#2136).</summary>
    CreatePr: Boolean;
    /// <summary>Ziel-Branch des Pull Requests; '' = Standard-Branch.</summary>
    PrBase: string;
    /// <summary>Textvorlage mit {closes}, {branch}, {commits}, {time}.</summary>
    PrBody: string;
    /// <summary>Als Entwurf vorbelegen.</summary>
    PrDraft: Boolean;
  end;

  /// <summary>Zustand im Projekt (#2134) nach einem Schreibzugriff, für die Meldung: Projekt '' = kein Projekt
  /// berührt.</summary>
  TAtlasTrackerProjectStatus = record
    Project: string;
    Before: string;
    After: string;
    /// <summary>Das Issue liegt in mehreren Projekten; Project ist das gewählte.</summary>
    Several: Boolean;
    /// <summary>Das Issue wurde erst ins Projekt aufgenommen.</summary>
    Added: Boolean;
    /// <summary>Projekte nicht lesbar (Berechtigung „project“ fehlt); der Zustand ging als Label.</summary>
    Denied: Boolean;
    /// <summary>Zustand ohne passende Option im Statusfeld; '' sonst.</summary>
    MissingOption: string;
  end;

  /// <summary>Eine Änderung an einem Issue (#1266): Zustand, Zuständigkeit und Kommentar in einem Schritt.</summary>
  TAtlasTrackerWrite = record
    /// <summary>Name des Zustandsfeldes (YouTrack, z. B. "State" oder "Status"); GitHub ohne Bedeutung.</summary>
    StateField: string;
    /// <summary>Neuer Zustand; '' = nicht ändern. GitHub: Name des Labels; ein Erledigt-Zustand schließt das
    /// Issue.</summary>
    State: string;
    /// <summary>Bisheriger Zustand aus „Beginnen“ (GitHub: dieses Label entfällt beim neuen Zustand); '' ohne.
    /// </summary>
    PreviousState: string;
    /// <summary>Name des Benutzerfeldes für die Zuständigkeit (YouTrack, z. B. "Assignee").</summary>
    AssigneeField: string;
    Assign: TAtlasTrackerAssign;
    /// <summary>Anmeldename bei Assign = User.</summary>
    Assignee: string;
    /// <summary>Kommentar (Markdown); '' = keiner.</summary>
    Comment: string;
    /// <summary>Übergang der Zustandsmaschine statt State (#2122); Id '' = keiner. Kommentar und Zuständigkeit
    /// gehen vorher hinaus.</summary>
    Transition: TAtlasTrackerTransition;
    /// <summary>ID des Zustandsfeldes am Issue für Transition (TAtlasTrackerStateRules.FieldId).</summary>
    FieldId: string;
    /// <summary>In diesen Sprint aufnehmen (#2128); nicht gesetzt = keiner. Geht mit Zuständigkeit und Kommentar
    /// hinaus.</summary>
    Sprint: TAtlasTrackerSprintRef;
    /// <summary>Abschluss beim Beenden (#2135, GitHub); ByState = wie bisher nach State.</summary>
    Close: TAtlasTrackerClose;
    /// <summary>Close = Duplicate: Kennung des Issues, von dem dieses ein Duplikat ist ("#418").</summary>
    DuplicateOf: string;
    /// <summary>Close = Duplicate: Kommentar, falls der Tracker „Duplikat“ nicht annimmt und als „nicht geplant“
    /// schließt (ältere GitHub-Enterprise-Server); '' = der Kommentar nennt das Duplikat schon.</summary>
    DuplicateNote: string;
    /// <summary>Wo GitHub den Zustand führt (#2134).</summary>
    GitHub: TAtlasTrackerGitHubState;
    class function Empty: TAtlasTrackerWrite; static;
    /// <summary>Nur ein Kommentar.</summary>
    class function CommentOnly(const AText: string): TAtlasTrackerWrite; static;
    /// <summary>Es gibt etwas zu schreiben.</summary>
    function HasWork: Boolean;
    /// <summary>Close schließt das Issue ausdrücklich (erledigt, nicht geplant, Duplikat).</summary>
    function Closes: Boolean;
  end;

  /// <summary>Ergebnis eines Schreibzugriffs (#1266).</summary>
  TAtlasTrackerWriteResult = record
    /// <summary>None = geschrieben.</summary>
    Error: TAtlasCiFetchError;
    /// <summary>HTTP-Status der fehlgeschlagenen Anfrage; 0 ohne Antwort.</summary>
    Status: Integer;
    /// <summary>Fehlertext des Trackers ("error_description", "message"), gekürzt; '' ohne.</summary>
    Message: string;
    /// <summary>Geschrieben, aber auf einem Ersatzweg (#2135: „Duplikat“ abgelehnt, als „nicht geplant“ mit
    /// Kommentar geschlossen).</summary>
    Fallback: Boolean;
    /// <summary>Zustand im Projekt (#2134, GitHub).</summary>
    Project: TAtlasTrackerProjectStatus;
    class function Ok: TAtlasTrackerWriteResult; static;
    class function Failed(AError: TAtlasCiFetchError; AStatus: Integer;
      const AMessage: string): TAtlasTrackerWriteResult; static;
    function Succeeded: Boolean;
  end;

  /// <summary>Issues ändern und Werte für Klapplisten lesen (#1266). Im Hintergrund; ATransport muss zum Schreiben
  /// IAtlasCiSend unterstützen. Nichts wird wiederholt.</summary>
  IAtlasTrackerWriter = interface
    ['{C3E81F57-4A2D-4B96-8E0F-7D5A1B9C2E63}']
    /// <summary>AChange auf AKey anwenden, insgesamt höchstens ATimeoutMs (YouTrack: ein Befehl bzw. Kommentar;
    /// GitHub: Kommentar, dann Labels, Zuständigkeit und Zustand mit einem PATCH).</summary>
    function Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    /// <summary>Werte der Art AKind; AField = Zustandsfeld bei States (YouTrack). Ohne Leserecht auf die Felder
    /// des Projekts kommt ein Fehler zurück, die Klappliste bleibt dann frei beschreibbar.</summary>
    function Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
      out AValues: TArray<string>): TAtlasTrackerWriteResult;
  end;

  /// <summary>Regeln des Zustandsfeldes eines Issues lesen (#2122): Zustandsmaschine, aktueller Wert und erlaubte
  /// Übergänge. Anbieter mit Workflow-Regeln (YouTrack) setzen es zusätzlich um; ausgelöst wird ein Übergang über
  /// IAtlasTrackerWriter.Apply mit TAtlasTrackerWrite.Transition. Im Hintergrund.</summary>
  IAtlasTrackerStateRules = interface
    ['{6A2D9E41-7C58-4B13-9F06-3E8B1D5C7A92}']
    /// <summary>Regeln des Feldes AField am Issue AKey. Ohne Zustandsmaschine ist ARules.StateMachine False (dann
    /// gilt ein Befehl mit dem Wert).</summary>
    function StateRules(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out ARules: TAtlasTrackerStateRules): TAtlasTrackerWriteResult;
  end;

  /// <summary>Felder eines Issues beim Beenden (#2123): Namen und Werte der Felder des Projekts lesen und einzelne
  /// Felder setzen. Anbieter mit benannten Feldern (YouTrack) setzen es zusätzlich um. Im Hintergrund; ATransport
  /// muss zum Schreiben IAtlasCiSend unterstützen. Nichts wird wiederholt.</summary>
  IAtlasTrackerFields = interface
    ['{998A3C54-16A0-419D-916D-13C98F50B923}']
    /// <summary>AField '': Namen der Felder des Projekts von AKey; sonst die Werte von AField (Versionen,
    /// Aufzählungen, Zustände; nicht archiviert). Ein Feld ohne Werteliste (Text, Zahl) liefert leer.</summary>
    function FieldValues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out AValues: TArray<string>): TAtlasTrackerWriteResult;
    /// <summary>Feld AField von AKey auf AValue setzen (YouTrack: Befehl „Feld Wert“). Lehnt eine Regel des
    /// Ablaufs ab, steht ihr Text in Message.</summary>
    function SetField(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey, AField,
      AValue: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
  end;

  /// <summary>Eine Zeitbuchung (#1267).</summary>
  TAtlasTrackerWorkItem = record
    /// <summary>Dauer in Minuten (> 0).</summary>
    Minutes: Integer;
    /// <summary>Tag der Arbeit (lokal).</summary>
    Date: TDateTime;
    /// <summary>Arbeitstyp des Trackers; '' = ohne.</summary>
    WorkType: string;
    /// <summary>Beschreibung; '' = ohne.</summary>
    Text: string;
    class function Create(AMinutes: Integer; ADate: TDateTime; const AWorkType, AText: string): TAtlasTrackerWorkItem;
      static;
  end;

  /// <summary>Zeiterfassung im Projekt des Trackers (#1267).</summary>
  TAtlasTrackerTimeSettings = record
    /// <summary>Zeiterfassung im Projekt eingeschaltet.</summary>
    Enabled: Boolean;
    /// <summary>Arbeitstypen für die Klappliste; leer = frei.</summary>
    WorkTypes: TArray<string>;
  end;

  /// <summary>Zeit im Tracker buchen (#1267). Im Hintergrund; ATransport muss zum Buchen IAtlasCiSend unterstützen.
  /// Nichts wird wiederholt.</summary>
  IAtlasTrackerTimeWriter = interface
    ['{5B7D0E92-6C1A-4F38-9A24-E8C3F1D07B65}']
    /// <summary>Zeiterfassung und Arbeitstypen des Projekts von AKey. Ohne Leserecht auf die Einstellungen des
    /// Projekts gilt die Zeiterfassung als an (Enabled) mit den allgemeinen Arbeitstypen.</summary>
    function TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
    /// <summary>AItem auf AKey buchen.</summary>
    function BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    /// <summary>AResult von BookTime heißt „Zeiterfassung im Projekt aus“ (die Zeit bleibt dann lokal).</summary>
    function IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
  end;

  /// <summary>Beschreibung eines Issues lesen und schreiben (#1273, Checklisten). Im Hintergrund; ATransport muss
  /// zum Schreiben IAtlasCiSend unterstützen.</summary>
  IAtlasTrackerDescriptions = interface
    ['{8A3E6D52-1F4B-4C97-B2E0-5D7A9C1F3E84}']
    /// <summary>Aktuelle Beschreibung von AKey (Markdown, ungekürzt, '' ohne). False mit AError, wenn sie nicht
    /// gelesen werden konnte oder länger als TAtlasTrackerDetails.cMaxDescription ist.</summary>
    function Description(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Beschreibung von AKey durch AText ersetzen (YouTrack POST /api/issues/&lt;Kennung&gt;, GitHub PATCH
    /// …/issues/&lt;n&gt;). False mit AError; ohne Schreibrecht Unauthorized.</summary>
    function UpdateDescription(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey, AText: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Benutzer für @-Erwähnungen suchen (#1278); Anbieter, die das können, setzen es zusätzlich um.
  /// </summary>
  IAtlasTrackerPeople = interface
    ['{CBC85BCF-7164-48F0-84AE-466842C69E1C}']
    /// <summary>Höchstens AMax Benutzer zu AText (YouTrack: Suche des Trackers, GitHub: mögliche Zuständige des
    /// Repositorys, hier gefiltert), eine Abfrage, höchstens ACall.TimeoutMs; im Hintergrund.</summary>
    function Users(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
      out AUsers: TArray<TAtlasTrackerUser>; out AError: TAtlasCiFetchError): Boolean;
  end;

implementation

uses
  System.StrUtils;

class function TAtlasTrackerCall.Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer): TAtlasTrackerCall;
begin
  Result.Target := ATarget;
  Result.Transport := ATransport;
  Result.TimeoutMs := ATimeoutMs;
end;

const
  /// <summary>Endung einer Klon-Adresse.</summary>
  cGitSuffix = '.git';
  cChecksKeys: array[TAtlasTrackerChecks] of string = ('unknown', 'pending', 'success', 'failure');
  cLinkKindKeys: array[TAtlasTrackerLinkKind] of string = ('', 'dependsOn', 'blocks', 'subtask', 'parent',
    'duplicates', 'duplicatedBy', 'relates', 'mentioned', 'pullRequest');

{ TAtlasTrackerPullRequest }

class function TAtlasTrackerPullRequest.ChecksKey(AChecks: TAtlasTrackerChecks): string;
begin
  Result := cChecksKeys[AChecks];
end;

class function TAtlasTrackerPullRequest.ChecksOf(const AKey: string): TAtlasTrackerChecks;
var
  mChecks: TAtlasTrackerChecks;
begin
  for mChecks := Low(TAtlasTrackerChecks) to High(TAtlasTrackerChecks) do
  begin
    if SameText(cChecksKeys[mChecks], AKey) then
    begin
      Exit(mChecks);
    end;
  end;
  Result := TAtlasTrackerChecks.Unknown;
end;

{ TAtlasTrackerLink }

class function TAtlasTrackerLink.KindKey(AKind: TAtlasTrackerLinkKind): string;
begin
  Result := cLinkKindKeys[AKind];
end;

class function TAtlasTrackerLink.KindOf(const AKey: string): TAtlasTrackerLinkKind;
var
  mKind: TAtlasTrackerLinkKind;
begin
  Result := TAtlasTrackerLinkKind.Other;
  if AKey = '' then
  begin
    Exit;
  end;
  for mKind := Low(TAtlasTrackerLinkKind) to High(TAtlasTrackerLinkKind) do
  begin
    if SameText(cLinkKindKeys[mKind], AKey) then
    begin
      Exit(mKind);
    end;
  end;
end;

function TAtlasTrackerLink.Blocking: Boolean;
begin
  Result := (Kind = TAtlasTrackerLinkKind.DependsOn) and StateKnown and not Resolved;
end;

{ TAtlasTrackerChange }

class function TAtlasTrackerChange.Create(const AKey: string; AKind: TAtlasTrackerChangeKind; const AAuthor: string;
  ATime: TDateTime): TAtlasTrackerChange;
begin
  Result := Default(TAtlasTrackerChange);
  Result.Key := AKey;
  Result.Kind := AKind;
  Result.Author := AAuthor;
  Result.Time := ATime;
end;

function TAtlasTrackerChange.Who: string;
begin
  Result := AuthorName;
  if Result = '' then
  begin
    Result := Author;
  end;
end;

{ TAtlasTrackerPoll }

class function TAtlasTrackerPoll.Create(ASince: TDateTime; const AMe: string;
  AScope: TAtlasTrackerNotifyScope): TAtlasTrackerPoll;
begin
  Result := Default(TAtlasTrackerPoll);
  Result.Since := ASince;
  Result.Me := AMe;
  Result.Scope := AScope;
end;

{ TAtlasTrackerIssue }

class function TAtlasTrackerIssue.Empty: TAtlasTrackerIssue;
begin
  Result := Default(TAtlasTrackerIssue);
  Result.Labels := nil;
end;

{ TAtlasTrackerUser }

class function TAtlasTrackerUser.Create(const ALogin, AName: string): TAtlasTrackerUser;
begin
  Result.Login := Trim(ALogin);
  Result.Name := Trim(AName);
end;

function TAtlasTrackerUser.Matches(const AText: string): Boolean;
begin
  Result := Rank(AText) < 3;
end;

function TAtlasTrackerUser.Rank(const AText: string): Integer;
var
  mText, mName: string;
begin
  mText := LowerCase(Trim(AText));
  if (mText = '') or LowerCase(Login).StartsWith(mText) then
  begin
    Exit(0);
  end;
  mName := ' ' + LowerCase(Name);
  if Pos(' ' + mText, mName) > 0 then
  begin
    Exit(1);
  end;
  if (Pos(mText, LowerCase(Login)) > 0) or (Pos(mText, mName) > 0) then
  begin
    Exit(2);
  end;
  Result := 3;
end;

function RankedUsers(const AUsers: TArray<TAtlasTrackerUser>; const AText: string; AMax: Integer;
  AKeepOthers: Boolean): TArray<TAtlasTrackerUser>;
var
  mRank, mIndex: Integer;
  mUser: TAtlasTrackerUser;
  mSeen: string;
begin
  Result := nil;
  mSeen := '|';
  // Stabil: je Rang in der Reihenfolge der Liste (TArray.Sort ist nicht stabil).
  for mRank := 0 to 3 do
  begin
    if (mRank = 3) and not AKeepOthers then
    begin
      Break;
    end;
    for mIndex := 0 to High(AUsers) do
    begin
      if Length(Result) >= AMax then
      begin
        Exit;
      end;
      mUser := AUsers[mIndex];
      if (Trim(mUser.Login) = '') or (mUser.Rank(AText) <> mRank) or
        (Pos('|' + LowerCase(mUser.Login) + '|', mSeen) > 0) then
      begin
        Continue;
      end;
      mSeen := mSeen + LowerCase(mUser.Login) + '|';
      Result := Result + [mUser];
    end;
  end;
end;

class function TAtlasTrackerUser.Filter(const AUsers: TArray<TAtlasTrackerUser>; const AText: string;
  AMax: Integer): TArray<TAtlasTrackerUser>;
begin
  Result := RankedUsers(AUsers, AText, AMax, False);
end;

class function TAtlasTrackerUser.Ranked(const AUsers: TArray<TAtlasTrackerUser>; const AText: string;
  AMax: Integer): TArray<TAtlasTrackerUser>;
begin
  Result := RankedUsers(AUsers, AText, AMax, True);
end;

{ TAtlasTrackerAttachment }

function TAtlasTrackerAttachment.IsImage: Boolean;
var
  mExt: string;
begin
  Result := MimeType.StartsWith('image/', True);
  if Result or (MimeType <> '') then
  begin
    Exit;
  end;
  mExt := LowerCase(ExtractFileExt(Name));
  Result := (mExt = '.png') or (mExt = '.jpg') or (mExt = '.jpeg') or (mExt = '.gif') or (mExt = '.bmp');
end;

{ TAtlasTrackerDetails }

class function TAtlasTrackerDetails.Empty: TAtlasTrackerDetails;
begin
  Result := Default(TAtlasTrackerDetails);
  Result.Labels := nil;
  Result.Comments := nil;
  Result.Attachments := nil;
  Result.Links := nil;
end;

function TAtlasTrackerDetails.Issue: TAtlasTrackerIssue;
var
  mCount: Integer;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := Key;
  Result.Number := Number;
  Result.Title := Copy(Title, 1, TAtlasTrackerIssue.cMaxTitle);
  mCount := Length(Labels);
  if mCount > TAtlasTrackerIssue.cMaxLabels then
  begin
    mCount := TAtlasTrackerIssue.cMaxLabels;
  end;
  Result.Labels := Copy(Labels, 0, mCount);
  Result.State := State;
  Result.Priority := Priority;
  Result.Sprint := Sprint;
  Result.Assignee := Assignee;
end;

function TAtlasTrackerDetails.AttachmentIndex(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Attachments) do
  begin
    if SameText(Attachments[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TAtlasTrackerWrite }

class function TAtlasTrackerWrite.Empty: TAtlasTrackerWrite;
begin
  Result := Default(TAtlasTrackerWrite);
  Result.Assign := TAtlasTrackerAssign.Keep;
end;

class function TAtlasTrackerWrite.CommentOnly(const AText: string): TAtlasTrackerWrite;
begin
  Result := Empty;
  Result.Comment := AText;
end;

function TAtlasTrackerWrite.HasWork: Boolean;
begin
  Result := (Trim(State) <> '') or (Assign <> TAtlasTrackerAssign.Keep) or (Trim(Comment) <> '') or
    (Transition.Id <> '') or Sprint.IsSet or Closes;
end;

function TAtlasTrackerWrite.Closes: Boolean;
begin
  Result := Close in [TAtlasTrackerClose.Completed, TAtlasTrackerClose.NotPlanned, TAtlasTrackerClose.Duplicate];
end;

{ TAtlasTrackerTransition }

class function TAtlasTrackerTransition.Create(const AId, AName: string): TAtlasTrackerTransition;
begin
  Result.Id := AId;
  Result.Name := AName;
end;

function TAtlasTrackerTransition.Caption: string;
begin
  Result := Name;
  if Result = '' then
  begin
    Result := Id;
  end;
end;

{ TAtlasTrackerSprintRef }

class function TAtlasTrackerSprintRef.Create(const ABoard, ASprint: string;
  AFinish: TDateTime): TAtlasTrackerSprintRef;
begin
  Result.Board := Trim(ABoard);
  Result.Sprint := Trim(ASprint);
  Result.Finish := AFinish;
end;

class function TAtlasTrackerSprintRef.None: TAtlasTrackerSprintRef;
begin
  Result := Create('', '', 0);
end;

function TAtlasTrackerSprintRef.IsSet: Boolean;
begin
  Result := (Board <> '') and (Sprint <> '');
end;

{ TAtlasTrackerWorkItem }

class function TAtlasTrackerWorkItem.Create(AMinutes: Integer; ADate: TDateTime; const AWorkType,
  AText: string): TAtlasTrackerWorkItem;
begin
  Result.Minutes := AMinutes;
  Result.Date := ADate;
  Result.WorkType := Trim(AWorkType);
  Result.Text := AText;
end;

{ TAtlasTrackerWriteResult }

class function TAtlasTrackerWriteResult.Ok: TAtlasTrackerWriteResult;
begin
  Result.Error := TAtlasCiFetchError.None;
  Result.Status := 0;
  Result.Message := '';
  Result.Fallback := False;
  Result.Project := Default(TAtlasTrackerProjectStatus);
end;

class function TAtlasTrackerWriteResult.Failed(AError: TAtlasCiFetchError; AStatus: Integer;
  const AMessage: string): TAtlasTrackerWriteResult;
begin
  Result.Error := AError;
  Result.Status := AStatus;
  Result.Message := AMessage;
  Result.Fallback := False;
  Result.Project := Default(TAtlasTrackerProjectStatus);
end;

function TAtlasTrackerWriteResult.Succeeded: Boolean;
begin
  Result := Error = TAtlasCiFetchError.None;
end;

{ TAtlasTrackerDevelopment }

class function TAtlasTrackerDevelopment.Empty: TAtlasTrackerDevelopment;
begin
  Result := Default(TAtlasTrackerDevelopment);
  Result.Pulls := nil;
  Result.Changes := nil;
  Result.LinkedBranches := nil;
end;

{ TAtlasTrackerBranchLink }

class function TAtlasTrackerBranchLink.Make(AOutcome: TAtlasTrackerBranchLinkOutcome;
  const ABranch: string): TAtlasTrackerBranchLink;
begin
  Result := Default(TAtlasTrackerBranchLink);
  Result.Outcome := AOutcome;
  Result.Branch := ABranch;
  Result.Error := TAtlasCiFetchError.None;
end;

class function TAtlasTrackerBranchLink.Failure(AError: TAtlasCiFetchError;
  const AMessage: string): TAtlasTrackerBranchLink;
begin
  Result := Make(TAtlasTrackerBranchLinkOutcome.Failed, '');
  if AError = TAtlasCiFetchError.Unauthorized then
  begin
    Result.Outcome := TAtlasTrackerBranchLinkOutcome.Denied;
  end;
  Result.Error := AError;
  Result.Message := AMessage;
end;

function TAtlasTrackerBranchLink.OnServer: Boolean;
begin
  Result := Outcome in [TAtlasTrackerBranchLinkOutcome.Created, TAtlasTrackerBranchLinkOutcome.Found];
end;

{ TAtlasTrackerPullSpec }

class function TAtlasTrackerPullSpec.None: TAtlasTrackerPullSpec;
begin
  Result := Default(TAtlasTrackerPullSpec);
  Result.Wanted := False;
end;

{ TAtlasTrackerPullResult }

class function TAtlasTrackerPullResult.Make(AOutcome: TAtlasTrackerPullOutcome): TAtlasTrackerPullResult;
begin
  Result := Default(TAtlasTrackerPullResult);
  Result.Outcome := AOutcome;
  Result.Error := TAtlasCiFetchError.None;
end;

class function TAtlasTrackerPullResult.Failure(AError: TAtlasCiFetchError; AStatus: Integer;
  const AMessage: string): TAtlasTrackerPullResult;
begin
  Result := Make(TAtlasTrackerPullOutcome.Failed);
  Result.Error := AError;
  Result.Status := AStatus;
  Result.Message := AMessage;
end;

function TAtlasTrackerPullResult.Stands: Boolean;
begin
  Result := Outcome in [TAtlasTrackerPullOutcome.Created, TAtlasTrackerPullOutcome.Existing];
end;

{ TAtlasTrackerTarget }

function TrimSlashes(const AText: string): string;
begin
  Result := Trim(AText);
  while (Result <> '') and (Result[1] = '/') do
  begin
    Delete(Result, 1, 1);
  end;
  while (Result <> '') and (Result[Length(Result)] = '/') do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TAtlasTrackerTarget.Create(const AProvider, AUrl, AProject, AQuery: string): TAtlasTrackerTarget;
var
  mOrigin, mPath: string;
  mParts: TArray<string>;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while (Result.Url <> '') and (Result.Url[Length(Result.Url)] = '/') do
  begin
    Delete(Result.Url, Length(Result.Url), 1);
  end;
  Result.Project := TrimSlashes(AProject);
  Result.Query := Trim(AQuery);
  Result.Language := '';
  if Result.Provider <> cGitHub then
  begin
    Exit;
  end;
  if Result.Url = '' then
  begin
    Result.Url := cGitHubUrl;
  end;
  // "https://github.com/owner/repo" ohne Projekt: Projekt aus der Adresse.
  mOrigin := Result.Server;
  if mOrigin = '' then
  begin
    Exit;
  end;
  mPath := TrimSlashes(Copy(Result.Url, Length(mOrigin) + 1, MaxInt));
  // Klon-Adresse „…/owner/repo.git“ (aus git remote kopiert): ohne „.git“, sonst sucht GitHub ein Repo
  // „repo.git“ (Suche 422, Sprint 404).
  if EndsText(cGitSuffix, mPath) then
  begin
    mPath := TrimSlashes(Copy(mPath, 1, Length(mPath) - Length(cGitSuffix)));
  end;
  if mPath = '' then
  begin
    Exit;
  end;
  mParts := mPath.Split(['/']);
  if Length(mParts) = 2 then
  begin
    if Result.Project = '' then
    begin
      Result.Project := mPath;
    end;
    Result.Url := Copy(Result.Url, 1, Length(mOrigin));
  end;
end;

function TAtlasTrackerTarget.Configured: Boolean;
begin
  Result := (Provider <> '') and (Server <> '');
  if Result and (Provider = cGitHub) then
  begin
    Result := (Pos('/', Project) > 1) and (Pos('/', Project) < Length(Project));
  end;
end;

function TAtlasTrackerTarget.Server: string;
begin
  // Dieselben Regeln wie beim Build-Server: nur http(s), nie ein Benutzer in der Adresse.
  Result := TAtlasCiJob.Create('', Url, '', False, '').Server;
end;

function TAtlasTrackerTarget.CredentialTarget: string;
begin
  Result := '';
  if Server <> '' then
  begin
    Result := 'Atlas:tracker:' + Server;
  end;
end;

function TAtlasTrackerTarget.Key: string;
begin
  Result := LowerCase(Provider + '|' + Url + '|' + Project + '|' + Query);
end;

function TAtlasTrackerTarget.Secure: Boolean;
begin
  Result := SameText(Copy(Server, 1, 8), 'https://');
end;

end.
