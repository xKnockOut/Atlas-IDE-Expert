unit Atlas.UI.Welcome.Contract;

// Quellen der Bereiche der Willkommensseite als Vertrag (#1443): Was ein Bereich von seiner Quelle braucht. Die
// IDE-Seite implementiert die Quellen als Adapter (Atlas.IDE.Welcome.Adapters.*), die Bereiche zeigen nur an.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Generate.Contract,
  Atlas.Core.Projects.Contract.Summary,
  Atlas.Core.Welcome.Contract,
  Atlas.Core.Foundation.Contract;

type
  /// <summary>Ein Atlas-Bereich für „Bereich hinzufügen“ und die Leiste „Ausgeblendet“.</summary>
  TAtlasWelcomeCatalogEntry = record
    Id: string;
    Title: string;
    /// <summary>Kurze Beschreibung für „Bereich hinzufügen“.</summary>
    Description: string;
    /// <summary>Einstellung des Bereichs an?</summary>
    Shown: Boolean;
    class function Create(const AId, ATitle, ADescription: string; AShown: Boolean): TAtlasWelcomeCatalogEntry;
      static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Schalter einer Zeile: keiner (keine oder unbekannte Einstellung), aus, an.</summary>
  TAtlasWhatsNewSwitch = (None, Off, On);
  {$SCOPEDENUMS OFF}

  IAtlasWelcomeArrangeSource = interface
    ['{3F7B2C91-6A4E-4D08-B5C1-9E2A7D4F6B13}']
    /// <summary>welcomePage.customLayout: Bearbeitungsmodus, Stift und Layout-Umschalter.</summary>
    function CanCustomize: Boolean;
    /// <summary>Bearbeitungsmodus an (gilt für Willkommensseite und „Atlas-Start“ zugleich)?</summary>
    function Editing: Boolean;
    procedure SetEditing(AOn: Boolean);
    function LayoutNames: TArray<string>;
    function ActiveLayout: string;
    /// <summary>Alle angemeldeten Atlas-Bereiche in der Reihenfolge des Atlas-Layouts.</summary>
    function Catalog: TArray<TAtlasWelcomeCatalogEntry>;
    /// <summary>Plätze, Breiten oder Spalten des aktiven Layouts geändert.</summary>
    procedure Arrange(const ALayout: TAtlasWelcomeLayout);
    /// <summary>Ausgeblendeten Bereich einschalten und in Spalte AColumn vor ABefore ('' = ans Ende) setzen.
    /// </summary>
    procedure ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
    /// <summary>Auge: Einstellung des Bereichs aus.</summary>
    procedure HideSection(const AId: string);
    /// <summary>Rechtsklick „Ausblenden“ wie am Element (#628): mit „Rückgängig“ an APoint (Bildschirm).
    /// </summary>
    procedure HideSectionAt(const AId: string; const APoint: TPoint);
    /// <summary>Optionsseite mit der Einstellung des Bereichs.</summary>
    procedure ShowSectionSettings(const AId: string);
    procedure SwitchLayout(const AName: string);
    /// <summary>Kopie des aktiven Layouts unter AName; False bei leerem oder vergebenem Namen.</summary>
    function AddLayout(const AName: string): Boolean;
    function RenameLayout(const AName: string): Boolean;
    /// <summary>Aktives Layout löschen; False beim letzten.</summary>
    function DeleteLayout: Boolean;
    /// <summary>„Zurücksetzen“: Atlas-Layout (#753) für das aktive Layout.</summary>
    procedure ResetLayout;
  end;

  IAtlasContinueSource = interface(IAtlasShownSource)
    ['{2B7E9C41-5D3A-4E86-9F1B-C4A07D2E8B95}']
    /// <summary>Gezeigte Arbeitsstände, neueste zuerst.</summary>
    function Entries: TAtlasContinueEntries;
    /// <summary>Eingehende Commits zum obersten Eintrag; Available = False: kein Abschnitt.</summary>
    function Incoming: TAtlasContinueIncoming;
    /// <summary>Die Abfrage der eingehenden Commits läuft gerade.</summary>
    function IncomingQuerying: Boolean;
    /// <summary>Reiter „Gemerkt“ zeigen (welcomePage.saved).</summary>
    function SavedEnabled: Boolean;
    /// <summary>Notizen, Lesezeichen und Favoriten aller Projekte.</summary>
    function Saved: TAtlasSavedItems;
    /// <summary>Hinweis unter der Liste (z. B. übersprungene Dateien); '' ohne.</summary>
    function Notice: string;
    /// <summary>„Fortsetzen“: Projekt öffnen, Reiter in ihrer Reihenfolge, Cursor an die letzte Änderung.</summary>
    procedure Resume(const AProject: string);
    /// <summary>Dateien eines eingehenden Commits zeigen.</summary>
    procedure ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
    /// <summary>Projekt öffnen und zum gemerkten Eintrag springen.</summary>
    procedure OpenSaved(const AItem: TAtlasSavedItem);
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Seite Versionsverwaltung für AProject öffnen.
    /// </summary>
    procedure ShowServerAccess(const AProject: string);
    // Shown (IAtlasShownSource): Der Bereich wird gezeigt: eingehende Commits bei Bedarf im Hintergrund abfragen.
  end;

  IAtlasContinueIssuesSource = interface
    ['{8D3F61B0-27C4-4A5E-9B18-E4C07A2D5F93}']
    /// <summary>Reiter „Issues“ zeigen (welcomePage.continue.issues an und Tracker vorhanden).</summary>
    function IssuesEnabled: Boolean;
    /// <summary>Gespeicherte Arbeitsstände offener Issues, neueste zuerst.</summary>
    function IssueRows: TAtlasIssueWorkRows;
    /// <summary>Hinweis unter der Liste (z. B. Branch fehlt, übersprungene Dateien); '' ohne.</summary>
    function IssuesNotice: string;
    /// <summary>„Fortsetzen“: Projekt öffnen, Branch nur nach Rückfrage wechseln, Reiter wiederherstellen.</summary>
    procedure ResumeIssue(const AProject, AKey: string);
  end;

  IAtlasDiscoverSource = interface
    ['{3E7C9A14-5B2D-4F86-A1C0-8D6E2F4B7A93}']
    /// <summary>Der Tipp, den die Karte gerade zeigt; False ohne Tipp.</summary>
    function Card(out ACard: TAtlasDiscoverCard): Boolean;
    /// <summary>„Ausprobieren“: Befehl ausführen oder Beispieldatei öffnen.</summary>
    procedure TryTip(const AId: string);
    /// <summary>„Nächster Tipp“.</summary>
    procedure NextTip(const AId: string);
    /// <summary>„Nicht mehr zeigen“: Tipp dauerhaft sperren.</summary>
    procedure BlockTip(const AId: string);
  end;

  IAtlasHelpSource = interface
    ['{6B1E2F7A-3C94-4D58-9A0B-5E7C1D2F8A46}']
    /// <summary>Gibt es die Tastenkürzel-Übersicht (#520)?</summary>
    function KeysAvailable: Boolean;
    /// <summary>„Atlas-Doku“: installierte Doku oder Doku-Seite des Repositorys im Browser.</summary>
    procedure OpenDocs;
    /// <summary>„Tastenkürzel“: Übersicht aus #520.</summary>
    procedure ShowKeys;
    /// <summary>„Problem melden …“: Dialog mit Diagnosepaket.</summary>
    procedure ReportProblem;
    /// <summary>„Atlas unterstützen“: Spendenseite im Browser.</summary>
    procedure Donate;
  end;

  IAtlasProjectsSource = interface(IAtlasShownSource)
    ['{4E7C2A19-6B3D-4F80-9C51-8A2D0E6F3B47}']
    /// <summary>Gezeigte Projekte mit Zusammenfassung und Stand der Versionsverwaltung.</summary>
    function Entries: TAtlasProjectEntries;
    procedure Open(const AProject: string);
    /// <summary>Projekt öffnen und zu ATarget springen (Fehler-Marke).</summary>
    procedure OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
    procedure OpenFolder(const AProject: string);
    /// <summary>„Branch anlegen …“ (#1288): Dialog für die Arbeitskopie von AProject.</summary>
    procedure CreateBranch(const AProject: string);
    /// <summary>„Arbeitskopien …“ (#1292): Tabelle der Arbeitskopien von AProject (Wurzel, Externals,
    /// Submodule).</summary>
    procedure ShowWorkingCopies(const AProject: string);
    /// <summary>vcs.externals.show: Eintrag „Arbeitskopien …“ zeigen.</summary>
    function WorkingCopies: Boolean;
    /// <summary>„Aus Liste entfernen“: nur in diesem Bereich, die Liste der IDE bleibt.</summary>
    procedure Remove(const AProject: string);
    // Shown (IAtlasShownSource): Der Bereich wird gezeigt: Versionsverwaltung bei Bedarf im Hintergrund frisch
    // abfragen.
    /// <summary>Klick wählt eine Zeile für den Projektverlauf (#758) statt sie zu öffnen.</summary>
    function Selectable: Boolean;
    /// <summary>Projekt für den Projektverlauf wählen (#758).</summary>
    procedure Select(const AProject: string);
    /// <summary>Gewähltes Projekt; '' = keins (der Verlauf zeigt dann das oberste).</summary>
    function Selected: string;
  end;

  IAtlasQuickActionsSource = interface
    ['{C7F5C025-7259-4CF4-BB0A-6D6A1251CC59}']
    /// <summary>welcomePage.quickActions; aus = keine Knöpfe, keine Tasten.</summary>
    function Enabled: Boolean;
    /// <summary>Knöpfe für AProject nach welcomePage.quickActions.items, Versionsverwaltung und laufenden
    /// Aktionen.</summary>
    function Buttons(const AProject: string): TAtlasQuickActionButtons;
    /// <summary>Stand der letzten Schnellaktion von AProject in dieser Sitzung.</summary>
    function State(const AProject: string): TAtlasQuickActionState;
    /// <summary>Jetzt als Tick in ms (wie TAtlasQuickActionState.StartedMs).</summary>
    function NowMs: UInt64;
    /// <summary>Aktion mit den Vorgaben ausführen (Bauen: zuletzt benutzte Konfiguration und Plattform; Tests: das
    /// eine Testprojekt; Start: aktives Startprofil).</summary>
    procedure Execute(const AProject: string; AAction: TAtlasQuickAction);
    /// <summary>Konfigurationen und Plattformen von AProject; AConfiguration/APlatform: Vorgabe ('' = wie in der
    /// IDE).</summary>
    function Targets(const AProject: string; out AConfiguration, APlatform: string): TAtlasProjectTargets;
    procedure Build(const AProject, AConfiguration, APlatform: string);
    /// <summary>Testprojekte zu AProject: eins = das zugeordnete, mehrere = Auswahl, keins = keins gefunden.</summary>
    function TestProjects(const AProject: string): TArray<string>;
    procedure RunTests(const AProject, ATestProject: string);
    /// <summary>Namen der Startprofile von AProject; AActive: aktives ('' = keins).</summary>
    function Profiles(const AProject: string; out AActive: string): TArray<string>;
    /// <summary>Öffnen und mit AProfile starten ('' = ohne Startprofil).</summary>
    procedure Run(const AProject, AProfile: string);
    /// <summary>Namen der Projektaufgaben von AProject (#900) in der Reihenfolge der atlas.json.</summary>
    function TaskNames(const AProject: string): TArray<string>;
    /// <summary>Projektaufgabe AName von AProject im Hintergrund starten.</summary>
    procedure RunTask(const AProject, AName: string);
    /// <summary>Aktualisieren mit bzw. ohne Externals (#1292, Auswahl bei vcs.externals.update = ask).</summary>
    procedure Pull(const AProject: string; AIgnoreExternals: Boolean);
    /// <summary>Strg+B bzw. Strg+T als TShortCut; 0 = keine Taste.</summary>
    function BuildKey: Integer;
    function TestKey: Integer;
    /// <summary>Programm für „Konsole“ (Tooltip).</summary>
    function ConsoleProgram: string;
  end;

  IAtlasSetupSource = interface
    ['{8C2D4E61-7A3B-4F95-B1C0-2E9D6A4F7B13}']
    /// <summary>Stand der Karte für das Ziel.</summary>
    function Card: TAtlasSetupCard;
    /// <summary>„Anlegen …“: Inhalt zeigen, nach Bestätigung atlas.json neben die Projektdatei schreiben.
    /// </summary>
    procedure CreateConfig(ATemplate: TAtlasSetupTemplate);
    /// <summary>„Starten“: Baseline erzeugen (#97).</summary>
    procedure StartBaseline;
    /// <summary>„Prüfen“: Suchpfade und Defines prüfen.</summary>
    procedure CheckPaths;
    /// <summary>Projektoptionen des Ziels öffnen.</summary>
    procedure OpenOptions;
    /// <summary>Ziel in der IDE öffnen.</summary>
    procedure OpenProject;
    /// <summary>„Für dieses Projekt nicht mehr fragen“.</summary>
    procedure Dismiss;
    /// <summary>„Neu mit Atlas“: Erzeugen-Menü mit den Dateivorlagen der Art AKind.</summary>
    procedure NewFile(AKind: TAtlasNewFileKind);
  end;

  IAtlasStateSource = interface
    ['{5B8E1D37-2C4A-4F69-9E03-7A6D2B1C8F54}']
    /// <summary>Die fünf Zeilen aus dem Atlas-Statusfeld (#591).</summary>
    function Rows: TAtlasStateRows;
    /// <summary>Aktion der Statusfeld-Zeile AId ausführen.</summary>
    procedure RunRow(const AId: string);
    /// <summary>Knopf unter den Zeilen.</summary>
    procedure Run(AButton: TAtlasStateButton);
  end;

  IAtlasTrendsSource = interface
    ['{9C3B6E21-4A7D-4F18-B2E5-7D0A1C8F5E93}']
    /// <summary>Verlauf des gewählten (sonst obersten) Projekts mit den eingestellten Reihen.</summary>
    function View: TAtlasTrendView;
  end;

  IAtlasUnsavedSource = interface(IAtlasShownSource)
    ['{8C2D4E61-3A7B-4F95-B1E8-6D0C9A2F5E73}']
    /// <summary>Zeilen und Zustand des Bereichs.</summary>
    function View: TAtlasUnsavedView;
    /// <summary>„Ansehen“: Projekt öffnen und die betroffenen Dateien zeigen.</summary>
    procedure Show(const ARow: TAtlasUnsavedRow);
    /// <summary>„Push …“: Ziel und Commits zeigen, nur nach Bestätigung pushen.</summary>
    procedure Push(const ARow: TAtlasUnsavedRow);
    procedure OpenFolder(const ARow: TAtlasUnsavedRow);
    /// <summary>„Ignorieren bis morgen“.</summary>
    procedure Ignore(const ARow: TAtlasUnsavedRow);
    // Shown (IAtlasShownSource): Der Bereich wird gezeigt: bei Bedarf im Hintergrund frisch abfragen.
  end;

  IAtlasWhatsNewSource = interface
    ['{6B0F3E52-8D1A-4C7E-9A35-2E4D7C1B8F60}']
    /// <summary>Was die Karte gerade zeigt.</summary>
    function View: TAtlasWhatsNewView;
    /// <summary>Versionen zu View, neueste zuerst.</summary>
    function Versions: TAtlasWhatsNewVersions;
    function SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
    /// <summary>Tatsächliche Belegung der Tasten-Einstellung AKey als Text; '' ohne.</summary>
    function KeyText(const AKey: string): string;
    /// <summary>Hat der Eintrag einen ausführbaren Befehl oder eine vorhandene Beispieldatei?</summary>
    function CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
    procedure SetSwitch(const ASetting: string; AOn: Boolean);
    procedure TryItem(const AItem: TAtlasWhatsNewItem);
    /// <summary>„Gelesen“ nach einem Update, sonst „Schließen“: zurück zur Vorgabe der Einstellung.</summary>
    procedure Dismiss;
    procedure Show(AView: TAtlasWhatsNewView);
  end;

//@TYPES
implementation

{ TAtlasWelcomeCatalogEntry }

class function TAtlasWelcomeCatalogEntry.Create(const AId, ATitle, ADescription: string;
  AShown: Boolean): TAtlasWelcomeCatalogEntry;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Description := ADescription;
  Result.Shown := AShown;
end;



























//@IMPL
end.
