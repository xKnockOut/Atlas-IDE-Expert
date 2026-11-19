unit Atlas.UI.Tracker.Contract.MyIssues;

// Vertrag der Kachel „Meine Issues“ zwischen IDE und Oberfläche (#765, #1443): was
// die Kachel auslöst (IAtlasIssuesSource) und die Aktionen an einer Zeile. Die
// Quelle setzt Atlas.IDE.Tracker.Adapters.MyIssues um, gezeichnet wird in
// Atlas.UI.Tracker.MyIssues.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Contract.MyIssues;

type
  /// <summary>Aktionen an einer Zeile: an einem wieder geöffneten Issue (#2127) Weiterarbeiten auf dem alten
  /// Branch, Marke ausblenden, Grund in der Vorschau am Kommentar zeigen; „Prüfen“ (#2126).</summary>
  // Mit Gültigkeitsbereich: Ein Wert Continue verdeckte sonst in der ganzen Unit die Anweisung Continue (E2014).
  {$SCOPEDENUMS ON}
  TAtlasIssueAction = (Continue, Dismiss, Reason, Review);
  {$SCOPEDENUMS OFF}

  IAtlasIssuesSource = interface
    ['{8D3F6A21-5C4B-4E97-A1D8-2B7E9C05F364}']
    function View: TAtlasIssuesView;
    /// <summary>Der Bereich wird gezeigt: bei Bedarf den Tracker im Hintergrund fragen.</summary>
    procedure Shown;
    /// <summary>„Beginnen“ mit AMode (Branch anlegen oder nur merken).</summary>
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure Browse(const AIssue: TAtlasTrackerIssue);
    /// <summary>Issue im Fenster „Atlas-Issue“ zeigen (#1264).</summary>
    procedure Preview(const AIssue: TAtlasTrackerIssue);
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    /// <summary>Tracker jetzt abfragen (ohne auf den Abstand zu warten).</summary>
    procedure QueryNow;
    /// <summary>„Zugang zum Issue-Tracker hinterlegen …“.</summary>
    procedure Credentials;
    /// <summary>Befehl für den Zugang eingeschaltet (Einstellung TrackerLogin).</summary>
    function CanEnterCredentials: Boolean;
    /// <summary>Aktuelles Issue beenden (mit Rückfrage).</summary>
    procedure EndActive;
    /// <summary>„zuordnen …“ (#1261): Seite Issue-Tracker mit einer Zeile für das Projekt öffnen.</summary>
    procedure AssignProject;
    /// <summary>Abfrage AName für das Projekt wählen und gleich abfragen (#1262).</summary>
    procedure SelectQuery(const AName: string);
    /// <summary>„Abfragen bearbeiten …“: Seite Issue-Tracker öffnen.</summary>
    procedure EditQueries;
    /// <summary>Filter der Sprint-Kachel aufheben (#1277): wieder alle meine Issues.</summary>
    procedure ClearFilter;
    /// <summary>Tracker-Projekt wählen (#1927): '' = automatisch, "*" = alle (#1928), sonst
    /// „projekt@verbindung“.</summary>
    procedure SelectProject(const AKey: string);
    /// <summary>„Tracker-Projekte bearbeiten …“: Seite Issue-Tracker öffnen.</summary>
    procedure EditProjects;
    /// <summary>Aktion AAction an der Zeile AIssue (wieder geöffnet #2127, „Prüfen“ #2126).</summary>
    procedure IssueAction(const AIssue: TAtlasTrackerIssue; AAction: TAtlasIssueAction);
  end;

implementation

end.
