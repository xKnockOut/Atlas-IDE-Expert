unit Atlas.IDE.Tracker.Session;

// Übergang (#1455): Der Bereich „Meine Issues“ (TAtlasIdeIssues, #765) führt
// noch Tracker, Vorschau, „Beginnen“, Board, Zeiterfassung und Anhängen und
// liegt bei der Willkommensseite. Bis der Umbau der Willkommensseite diesen
// Kern ins Modul Tracker holt, stellt die Kompositionswurzel ihn über die
// Registry als IAtlasIssuesSession bereit (wie TWelcomeListener); das Modul
// Tracker fragt ihn bei jedem Gebrauch neu und kommt ohne ihn aus (Befehle
// unsichtbar, Teile starten nicht).
// Kein Vertrag unter Source/Contracts: Die Schnittstelle trägt Typen des
// Trackers (Ziel, Vorschau), und Verträge requiren nur rtl (ADR 0017). Sie
// entfällt, sobald „Meine Issues“ im Modul liegt.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Tracker.IssuePreview;

type
  /// <summary>„Meine Issues“ für das Modul Tracker. Alle Aufrufe im Hauptthread.</summary>
  IAtlasIssuesSession = interface
    ['{65970088-B5A1-4428-9211-1A0A6E8E7C65}']
    /// <summary>Läuft der Bereich (gestartet, noch nicht gestoppt)?</summary>
    function Available: Boolean;
    /// <summary>Tracker für Issue-Kennungen im Editor (#1265): das aktive Projekt, sonst das des Bereichs; ohne Netz.
    /// False ohne Tracker.</summary>
    function CodeTarget(out ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Vorschau-Steuerung (Zwischenspeicher, Kurzabfrage); nil ohne.</summary>
    function IssuePreview: TAtlasIdeIssuePreview;
    /// <summary>Vorschau „Atlas-Issue“ mit issues.preview, sonst im Browser.</summary>
    procedure ShowIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
    procedure BrowseIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>„Beginnen“ wie in „Meine Issues“.</summary>
    procedure StartIssue(const ATarget: TAtlasTrackerTarget; const AKey: string);
    function CanStartIssue: Boolean;
    /// <summary>Befehl Atlas.TrackerLogin (#765).</summary>
    procedure EnterCredentials;
    /// <summary>Befehl Atlas.CiLogin (#763); False ohne die Karte der Testergebnisse.</summary>
    function CanEnterCiCredentials: Boolean;
    procedure EnterCiCredentials;
    /// <summary>Befehl Atlas.IssueShow (#1264).</summary>
    procedure ShowPreviewPrompt;
    /// <summary>Befehl Atlas.IssueTimeOpen (#1267).</summary>
    procedure ShowTimeOpen;
    /// <summary>Fenster „Atlas-Board“ (#1272).</summary>
    procedure ShowBoard;
    /// <summary>Befehl Atlas.IssueAttach (#1276).</summary>
    procedure AttachPrompt;
    /// <summary>„Issue anlegen …“ (#1268) aus dem Editor; CanCreateIssue: issues.create und Tracker bereit.</summary>
    function CanCreateIssue: Boolean;
    procedure CreateIssueFromEditor;
  end;

implementation

end.
