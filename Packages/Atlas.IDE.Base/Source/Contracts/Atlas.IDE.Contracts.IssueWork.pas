unit Atlas.IDE.Contracts.IssueWork;

// Vertrag zwischen Modulen (#2052, Modulregeln 6 und 9): Arbeitsstand je Issue. Der Tracker kennt das aktive Issue
// eines Projekts und den Zustand der Issues (offen, behoben) und stellt dafür über seinen Scope eine
// IAtlasIssueWorkSource bereit. Die Willkommensseite merkt sich den Arbeitsstand („Weiterarbeiten“, #755) zusätzlich
// je Issue und stellt dafür IAtlasIssueWork bereit: Der Tracker meldet vor dem Wechsel des aktiven Issues
// („Beginnen“, „Beenden“) das bisherige Issue und bietet nach „Beginnen“ das Wiederherstellen an. So kennen sich
// Tracker und Willkommensseite nicht; fehlt eines der Module, fragt das andere ins Leere und tut nichts. Nur Typen
// und Interfaces, kein Code; alle Aufrufe im Hauptthread der IDE.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand eines Issues im Tracker: unbekannt (ohne Netz, noch nicht abgefragt), offen oder behoben bzw.
  /// geschlossen.</summary>
  TAtlasIssueWorkStatus = (Unknown, Open, Resolved);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Issue, wie es der Arbeitsstand braucht.</summary>
  TAtlasIssueWorkIssue = record
    /// <summary>Kennung wie im Tracker: "#753" (GitHub), "ATL-123" (YouTrack).</summary>
    Key: string;
    /// <summary>Titel; '' unbekannt.</summary>
    Title: string;
    /// <summary>Branch, auf dem das Issue begonnen wurde; '' ohne bzw. unbekannt.</summary>
    Branch: string;
  end;

  /// <summary>Zustand und Titel eines Issues.</summary>
  TAtlasIssueWorkInfo = record
    Key: string;
    /// <summary>Titel aus dem Tracker; '' unbekannt.</summary>
    Title: string;
    Status: TAtlasIssueWorkStatus;
  end;

  /// <summary>Stellt der Tracker bereit: aktives Issue und Zustand der Issues.</summary>
  IAtlasIssueWorkSource = interface
    ['{B4E0D7A2-6C19-4F3B-8D52-1A9E7C3F0B64}']
    /// <summary>Aktives Issue des Projekts bzw. der Projektgruppe AProject (gemerkt mit „Beginnen“ oder aus dem
    /// Branch erkannt); False ohne.</summary>
    function ActiveIssue(const AProject: string; out AIssue: TAtlasIssueWorkIssue): Boolean;
    /// <summary>Zustand der Issues AKeys im Tracker von AProject, in derselben Reihenfolge. Ohne Netz: nur aus dem
    /// Zwischenspeicher und der Liste „Meine Issues“; Unbekanntes fragt der Tracker im Hintergrund nach und meldet
    /// es danach über IAtlasIssueWork.StatusesChanged.</summary>
    function Statuses(const AProject: string; const AKeys: TArray<string>): TArray<TAtlasIssueWorkInfo>;
  end;

  /// <summary>Stellt die Willkommensseite bereit: Arbeitsstand je Issue sichern und wiederherstellen.</summary>
  IAtlasIssueWork = interface
    ['{5F8A2C61-3B7E-4D90-A6E4-9C02B1D87F35}']
    /// <summary>Funktion an (welcomePage.continue.issues)?</summary>
    function Enabled: Boolean;
    /// <summary>Vor dem Wechsel des aktiven Issues: den Arbeitsstand des offenen Projekts unter AIssue sichern, wenn
    /// AProject (bzw. seine Projektgruppe) gerade offen ist.</summary>
    procedure SaveIssue(const AProject: string; const AIssue: TAtlasIssueWorkIssue);
    /// <summary>Gibt es einen gespeicherten Arbeitsstand für AKey in AProject?</summary>
    function HasState(const AProject, AKey: string): Boolean;
    /// <summary>Nach „Beginnen“: „Arbeitsstand wiederherstellen?“ fragen und bei Ja die Reiter öffnen.</summary>
    procedure OfferRestore(const AProject, AKey: string);
    /// <summary>„Weiterarbeiten“ an einem wieder geöffneten Issue (#2127): den gespeicherten Arbeitsstand von AKey
    /// ohne Rückfrage wiederherstellen; ohne gespeicherten Stand nichts.</summary>
    procedure Restore(const AProject, AKey: string);
    /// <summary>Zustände der Issues haben sich geändert (Abfrage im Hintergrund fertig): neu zeichnen.</summary>
    procedure StatusesChanged;
  end;

implementation

end.
