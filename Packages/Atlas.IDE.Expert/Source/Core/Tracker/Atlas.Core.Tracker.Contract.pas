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
//   Issues ändern (TAtlasTrackerChange) und Werte für Klapplisten lesen
//   (Zustände, Felder, Benutzer); Anbieter, die schreiben können, setzen sie
//   zusätzlich um. Geschrieben wird über IAtlasCiSend, nur nach einem Klick
//   des Benutzers und nie wiederholt; Fehler kommen mit dem Text des Trackers
//   zurück (TAtlasTrackerWriteResult).
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
// Abfragen laufen im Hintergrund; nichts davon zeigt einen Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand der Prüfungen (CI) eines Pull Requests: Ampel im Bereich.</summary>
  TAtlasTrackerChecks = (Unknown, Pending, Success, Failure);
  /// <summary>Zuständigkeit bei einer Änderung (#1266): lassen, mir zuweisen oder an einen Benutzer übergeben.
  /// </summary>
  TAtlasTrackerAssign = (Keep, Me, User);
  /// <summary>Werte für die Klapplisten (#1266): Zustände des Zustandsfeldes (GitHub: Labels), Namen der
  /// Zustandsfelder, Namen der Benutzerfelder (YouTrack) und Benutzer, an die übergeben werden kann.</summary>
  TAtlasTrackerValueKind = (States, StateFields, UserFields, Users);
  /// <summary>Art einer Verknüpfung aus Sicht des gezeigten Issues (#1279). DependsOn: dieses hängt vom anderen
  /// ab (das andere blockiert dieses); Blocks: das andere hängt von diesem ab; Subtask: das andere ist
  /// Unteraufgabe; Parent: das andere ist übergeordnet; Duplicates: dieses ist Duplikat des anderen; DuplicatedBy:
  /// das andere ist Duplikat von diesem; Mentioned: Erwähnung (GitHub); PullRequest: Pull Request (GitHub).
  /// </summary>
  TAtlasTrackerLinkKind = (Other, DependsOn, Blocks, Subtask, Parent, Duplicates, DuplicatedBy, Relates, Mentioned,
    PullRequest);
  /// <summary>Zustand eines Pull Requests im Reiter „Entwicklung“ (#1269).</summary>
  TAtlasTrackerPullState = (Open, Draft, Merged, Closed);
{$SCOPEDENUMS OFF}

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
    MaxLabels = 6;
    /// <summary>Höchstens so viele Zeichen eines Titels werden gespeichert.</summary>
    MaxTitle = 200;
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
    MaxComments = 100;
    /// <summary>Höchstens so viele Anhänge bzw. Verknüpfungen.</summary>
    MaxAttachments = 50;
    MaxLinks = 50;
    /// <summary>Höchstens so viele Zeichen je Beschreibung bzw. Kommentar.</summary>
    MaxText = 100000;
    /// <summary>Längste Beschreibung, die Atlas zurückschreibt (#1273); länger: Invalid, nichts wird geschrieben.
    /// </summary>
    MaxDescription = 1000000;
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
    MaxPulls = 20;
    MaxChanges = 100;
  public
    /// <summary>Neueste zuerst.</summary>
    Pulls: TArray<TAtlasTrackerPull>;
    /// <summary>Neueste zuerst.</summary>
    Changes: TArray<TAtlasTrackerVcsChange>;
    class function Empty: TAtlasTrackerDevelopment; static;
  end;

  /// <summary>Was abgefragt wird; ohne Zugangsdaten.</summary>
  TAtlasTrackerTarget = record
  public const
    GitHub = 'github';
    YouTrack = 'youtrack';
    /// <summary>Adresse von GitHub, wenn .atlas keine nennt.</summary>
    GitHubUrl = 'https://github.com';
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

  /// <summary>Unteraufgaben anlegen und Issues verknüpfen (#1279); optional, die Vorschau fragt mit Supports. Der
  /// Transport muss IAtlasCiSend können, sonst NotConfigured. Läuft im Hintergrund.</summary>
  IAtlasTrackerLinkWriter = interface
    ['{8B3E5D21-4A7C-4F96-B2E8-1C6D9A4F7E53}']
    /// <summary>Neues Issue ATitle (ADescription als Markdown) im Projekt des Issues AParentKey anlegen und als
    /// Unteraufgabe verknüpfen. AKey: Kennung des neuen Issues, auch wenn nur das Verknüpfen scheiterte (dann
    /// False mit AError); '' wenn nichts angelegt wurde.</summary>
    function CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean;
    /// <summary>AKey mit AOtherKey verknüpfen: DependsOn (AKey hängt von AOtherKey ab) bzw. Blocks (AOtherKey
    /// hängt von AKey ab); andere Arten: False mit Invalid.</summary>
    function AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
      out AError: TAtlasCiFetchError): Boolean;
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
    /// Kommentare (sonst nicht abgefragt), insgesamt höchstens ATimeoutMs; im Hintergrund (#1264). False mit
    /// AError, wenn das Issue nicht gelesen werden konnte.</summary>
    function Details(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AComments: Boolean; ATimeoutMs: Integer; out ADetails: TAtlasTrackerDetails;
      out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Freitextsuche der Befehlspalette (#1270): höchstens AMax Issues zu AText im Projekt des Ziels, eine
    /// Abfrage ohne Pull Requests und Ampeln, höchstens ATimeoutMs; im Hintergrund. Die Abfrage aus den
    /// Einstellungen (ATarget.Query) gilt hier nicht.</summary>
    function Search(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AText: string;
      ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Issue AKey mit den Feldern der Liste (#1270), eine Abfrage, höchstens ATimeoutMs; im Hintergrund.
    /// False mit AError (NotFound, wenn es die Kennung nicht gibt).</summary>
    function Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Eine Änderung an einem Issue (#1266): Zustand, Zuständigkeit und Kommentar in einem Schritt.</summary>
  TAtlasTrackerChange = record
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
    class function Empty: TAtlasTrackerChange; static;
    /// <summary>Nur ein Kommentar.</summary>
    class function CommentOnly(const AText: string): TAtlasTrackerChange; static;
    /// <summary>Es gibt etwas zu schreiben.</summary>
    function HasWork: Boolean;
  end;

  /// <summary>Ergebnis eines Schreibzugriffs (#1266).</summary>
  TAtlasTrackerWriteResult = record
    /// <summary>None = geschrieben.</summary>
    Error: TAtlasCiFetchError;
    /// <summary>HTTP-Status der fehlgeschlagenen Anfrage; 0 ohne Antwort.</summary>
    Status: Integer;
    /// <summary>Fehlertext des Trackers ("error_description", "message"), gekürzt; '' ohne.</summary>
    Message: string;
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
      const AChange: TAtlasTrackerChange; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    /// <summary>Werte der Art AKind; AField = Zustandsfeld bei States (YouTrack). Ohne Leserecht auf die Felder
    /// des Projekts kommt ein Fehler zurück, die Klappliste bleibt dann frei beschreibbar.</summary>
    function Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
      out AValues: TArray<string>): TAtlasTrackerWriteResult;
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
    /// gelesen werden konnte oder länger als TAtlasTrackerDetails.MaxDescription ist.</summary>
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
    /// Repositorys, hier gefiltert), eine Abfrage, höchstens ATimeoutMs; im Hintergrund.</summary>
    function Users(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AText: string;
      ATimeoutMs, AMax: Integer; out AUsers: TArray<TAtlasTrackerUser>; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Pull Requests (GitHub, mit CI-Ampel) bzw. verknüpfte VCS-Änderungen (YouTrack) zu Issue AKey,
    /// insgesamt höchstens ATimeoutMs; im Hintergrund (#1269). Ein Tracker ohne solche Angaben liefert True mit
    /// leerem Ergebnis. False mit AError, wenn die Abfrage scheiterte.</summary>
    function Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment; out AError: TAtlasCiFetchError): Boolean;
  end;

implementation

const
  ChecksKeys: array[TAtlasTrackerChecks] of string = ('unknown', 'pending', 'success', 'failure');
  LinkKindKeys: array[TAtlasTrackerLinkKind] of string = ('', 'dependsOn', 'blocks', 'subtask', 'parent',
    'duplicates', 'duplicatedBy', 'relates', 'mentioned', 'pullRequest');

{ TAtlasTrackerPullRequest }

class function TAtlasTrackerPullRequest.ChecksKey(AChecks: TAtlasTrackerChecks): string;
begin
  Result := ChecksKeys[AChecks];
end;

class function TAtlasTrackerPullRequest.ChecksOf(const AKey: string): TAtlasTrackerChecks;
var
  Checks: TAtlasTrackerChecks;
begin
  for Checks := Low(TAtlasTrackerChecks) to High(TAtlasTrackerChecks) do
    if SameText(ChecksKeys[Checks], AKey) then
      Exit(Checks);
  Result := TAtlasTrackerChecks.Unknown;
end;

{ TAtlasTrackerLink }

class function TAtlasTrackerLink.KindKey(AKind: TAtlasTrackerLinkKind): string;
begin
  Result := LinkKindKeys[AKind];
end;

class function TAtlasTrackerLink.KindOf(const AKey: string): TAtlasTrackerLinkKind;
var
  mKind: TAtlasTrackerLinkKind;
begin
  Result := TAtlasTrackerLinkKind.Other;
  if AKey = '' then
    Exit;
  for mKind := Low(TAtlasTrackerLinkKind) to High(TAtlasTrackerLinkKind) do
    if SameText(LinkKindKeys[mKind], AKey) then
      Exit(mKind);
end;

function TAtlasTrackerLink.Blocking: Boolean;
begin
  Result := (Kind = TAtlasTrackerLinkKind.DependsOn) and StateKnown and not Resolved;
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
    Exit(0);
  mName := ' ' + LowerCase(Name);
  if Pos(' ' + mText, mName) > 0 then
    Exit(1);
  if (Pos(mText, LowerCase(Login)) > 0) or (Pos(mText, mName) > 0) then
    Exit(2);
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
      Break;
    for mIndex := 0 to High(AUsers) do
    begin
      if Length(Result) >= AMax then
        Exit;
      mUser := AUsers[mIndex];
      if (Trim(mUser.Login) = '') or (mUser.Rank(AText) <> mRank) or
        (Pos('|' + LowerCase(mUser.Login) + '|', mSeen) > 0) then
        Continue;
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
    Exit;
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
  Result.Title := Copy(Title, 1, TAtlasTrackerIssue.MaxTitle);
  mCount := Length(Labels);
  if mCount > TAtlasTrackerIssue.MaxLabels then
    mCount := TAtlasTrackerIssue.MaxLabels;
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
    if SameText(Attachments[mIndex].Name, AName) then
      Exit(mIndex);
  Result := -1;
end;

{ TAtlasTrackerChange }

class function TAtlasTrackerChange.Empty: TAtlasTrackerChange;
begin
  Result := Default(TAtlasTrackerChange);
  Result.Assign := TAtlasTrackerAssign.Keep;
end;

class function TAtlasTrackerChange.CommentOnly(const AText: string): TAtlasTrackerChange;
begin
  Result := Empty;
  Result.Comment := AText;
end;

function TAtlasTrackerChange.HasWork: Boolean;
begin
  Result := (Trim(State) <> '') or (Assign <> TAtlasTrackerAssign.Keep) or (Trim(Comment) <> '');
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
end;

class function TAtlasTrackerWriteResult.Failed(AError: TAtlasCiFetchError; AStatus: Integer;
  const AMessage: string): TAtlasTrackerWriteResult;
begin
  Result.Error := AError;
  Result.Status := AStatus;
  Result.Message := AMessage;
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
end;

{ TAtlasTrackerTarget }

function TrimSlashes(const AText: string): string;
begin
  Result := Trim(AText);
  while (Result <> '') and (Result[1] = '/') do
    Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

class function TAtlasTrackerTarget.Create(const AProvider, AUrl, AProject, AQuery: string): TAtlasTrackerTarget;
var
  Origin, Path: string;
  Parts: TArray<string>;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while (Result.Url <> '') and (Result.Url[Length(Result.Url)] = '/') do
    Delete(Result.Url, Length(Result.Url), 1);
  Result.Project := TrimSlashes(AProject);
  Result.Query := Trim(AQuery);
  Result.Language := '';
  if Result.Provider <> GitHub then
    Exit;
  if Result.Url = '' then
    Result.Url := GitHubUrl;
  // "https://github.com/owner/repo" ohne Projekt: Projekt aus der Adresse.
  Origin := Result.Server;
  if Origin = '' then
    Exit;
  Path := TrimSlashes(Copy(Result.Url, Length(Origin) + 1, MaxInt));
  if Path = '' then
    Exit;
  Parts := Path.Split(['/']);
  if Length(Parts) = 2 then
  begin
    if Result.Project = '' then
      Result.Project := Path;
    Result.Url := Copy(Result.Url, 1, Length(Origin));
  end;
end;

function TAtlasTrackerTarget.Configured: Boolean;
begin
  Result := (Provider <> '') and (Server <> '');
  if Result and (Provider = GitHub) then
    Result := (Pos('/', Project) > 1) and (Pos('/', Project) < Length(Project));
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
    Result := 'Atlas:tracker:' + Server;
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
