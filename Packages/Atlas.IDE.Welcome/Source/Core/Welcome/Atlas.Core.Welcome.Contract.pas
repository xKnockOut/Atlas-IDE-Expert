unit Atlas.Core.Welcome.Contract;

// Datentypen der Willkommensseite als Vertrag (#1443): Was die Quellen der Bereiche (Atlas.UI.Welcome.Contract) in
// ihren Signaturen tragen, und der Zugriff auf die Registry für die Sicherung des Layouts. Die bisherigen Units
// unter Core/Welcome führen die Namen als Alias weiter und behalten die Logik (Berechnung, JSON).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Projects.Contract.Summary,
  Atlas.Core.Status.Contract,
  Atlas.Core.VersionControl.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Spalte im Atlas-Layout; im Fenster „Atlas-Start“ stehen beide untereinander.</summary>
  TAtlasWelcomeColumn = (Left, Right);
  {$SCOPEDENUMS OFF}

  TAtlasWelcomeSection = record
    /// <summary>Kennung, z. B. "atlas.state"; siehe TAtlasWelcomeIds.</summary>
    Id: string;
    /// <summary>Überschrift in der Sprache der IDE.</summary>
    Title: string;
    /// <summary>Reihenfolge außerhalb eines Layouts, kleiner zuerst; bei Gleichstand nach Kennung.</summary>
    Order: Integer;
    /// <summary>Spalte, wenn das Layout den Bereich nicht kennt.</summary>
    Column: TAtlasWelcomeColumn;
    /// <summary>Schalter des Bereichs (z. B. welcomePage.state); nil = immer an.</summary>
    Enabled: TFunc<Boolean>;
    /// <summary>Ein Satz für „Seite anpassen“ (#767), wenn TAtlasIdeWelcomeLayouts den Bereich nicht kennt
    /// (Kacheln anderer Module, #1455); '' = keiner.</summary>
    Description: string;
    function IsEnabled: Boolean;
    class function Create(const AId, ATitle: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn;
      const AEnabled: TFunc<Boolean>): TAtlasWelcomeSection; static;
  end;

  TAtlasWelcomeSlot = record
    Id: string;
    /// <summary>Spalte ab 0.</summary>
    Column: Integer;
    /// <summary>1 = eine Spalte, 2 = zwei Spalten breit (ab Column nach rechts, #767).</summary>
    Width: Integer;
    /// <summary>Sichtbar? Spiegel der Einstellung des Bereichs im aktiven Layout (#767).</summary>
    Visible: Boolean;
    class function Create(const AId: string; AColumn: Integer): TAtlasWelcomeSlot; overload; static;
    class function Create(const AId: string; AColumn, AWidth: Integer; AVisible: Boolean): TAtlasWelcomeSlot;
      overload; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Verschieben um einen Schritt (Strg+Pfeiltasten im Bearbeitungsmodus, #767).</summary>
  TAtlasWelcomeMove = (Up, Down, Left, Right);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein Bereich in einer Spalte mit seiner Breite in Spalten.</summary>
  TAtlasWelcomeCell = record
    Id: string;
    Span: Integer;
    class function Create(const AId: string; ASpan: Integer): TAtlasWelcomeCell; static;
  end;

  /// <summary>Bereiche je Spalte in Lesereihenfolge.</summary>
  TAtlasWelcomeCells = TArray<TArray<TAtlasWelcomeCell>>;

  /// <summary>Gewicht eines Bereichs für „Spalte mit dem meisten Platz“ (z. B. seine Höhe).</summary>
  TAtlasWelcomeWeight = reference to function(const AId: string): Integer;

  TAtlasWelcomeLayout = record
  public const
    cMinColumns = 1;
    cMaxColumns = 3;
    cMinWidth = 1;
    cMaxWidth = 2;
    /// <summary>Name des Atlas-Layouts und des ersten Layouts (welcomePage.activeLayout, #767).</summary>
    cDefaultName = 'Standard';
  public
    Name: string;
    Columns: Integer;
    /// <summary>Plätze in Lesereihenfolge; innerhalb einer Spalte gilt diese Reihenfolge.</summary>
    Slots: TArray<TAtlasWelcomeSlot>;
  end;

  /// <summary>Ein Reiter des Arbeitsstands.</summary>
  TAtlasWorkTab = record
    /// <summary>Vollständiger Pfad.</summary>
    FileName: string;
    /// <summary>Letzte Änderung (Changed) bzw. Cursor; ab 1, 0 = unbekannt.</summary>
    Line: Integer;
    Column: Integer;
    /// <summary>Methode an dieser Stelle, z. B. TKunde.Laden; '' außerhalb einer Methode.</summary>
    Method: string;
    /// <summary>Line und Column sind eine Änderung.</summary>
    Changed: Boolean;
    /// <summary>Zeitpunkt der Änderung (UTC); 0 = unbekannt.</summary>
    ChangedAt: TDateTime;
    class function Create(const AFileName: string; ALine, AColumn: Integer): TAtlasWorkTab; static;
  end;

  /// <summary>Gespeicherter Arbeitsstand eines Projekts (Abschnitt "continue").</summary>
  TAtlasWorkState = record
    Known: Boolean;
    /// <summary>Zeitpunkt des Schließens (UTC).</summary>
    At: TDateTime;
    /// <summary>Reiter in ihrer Reihenfolge.</summary>
    Tabs: TArray<TAtlasWorkTab>;
    /// <summary>Zuletzt aktiver Reiter (Index in Tabs); -1 = unbekannt.</summary>
    Active: Integer;
    /// <summary>In der Sitzung geänderte Dateien, die beim Schließen nicht mehr offen waren.</summary>
    Edited: TArray<string>;
    /// <summary>"git", "svn", "none" oder '' (nicht abgefragt).</summary>
    VcsKind: string;
    /// <summary>HEAD-Commit beim Schließen; '' unbekannt.</summary>
    Head: string;
    /// <summary>Verfolgter Branch beim Schließen, z. B. "origin/main"; '' ohne.</summary>
    Upstream: string;
    /// <summary>Commit des verfolgten Branchs beim Schließen; '' unbekannt.</summary>
    UpstreamRevision: string;
    class function Empty: TAtlasWorkState; static;
    function TabCount: Integer;
    /// <summary>Reiter mit der jüngsten Änderung, sonst der aktive, sonst der erste; -1 ohne Reiter.</summary>
    function LastIndex: Integer;
  end;

  TAtlasContinueEntry = record
    /// <summary>Projekt oder Projektgruppe (vollständiger Pfad).</summary>
    Project: string;
    State: TAtlasWorkState;
    /// <summary>Dateiname ohne Endung.</summary>
    function Name: string;
    function IsGroup: Boolean;
    /// <summary>Zuletzt bearbeitete Datei (siehe TAtlasWorkState.LastIndex); leer ohne Reiter.</summary>
    function LastTab: TAtlasWorkTab;
  end;

  TAtlasContinueEntries = TArray<TAtlasContinueEntry>;

  /// <summary>Arbeitsstand eines Eintrags (Projekt oder Issue) für TAtlasWorkOrder.</summary>
  TAtlasWorkStateOf<T> = reference to function(const AEntry: T): TAtlasWorkState;

  /// <summary>Reihenfolge der Einträge unter „Fortsetzen“: neueste zuerst.</summary>
  TAtlasWorkOrder = record
  public
    /// <summary>AEntry nach der Zeit seines Arbeitsstands (AStateOf) in AFound einsortieren, neueste zuerst; bei
    /// Gleichstand bleibt die Reihenfolge (stabil).</summary>
    class procedure InsertNewestFirst<T>(var AFound: TArray<T>; const AEntry: T;
      const AStateOf: TAtlasWorkStateOf<T>); static;
  end;

  /// <summary>Eingehender Commit mit den betroffenen Dateien des Arbeitsstands.</summary>
  TAtlasContinueCommit = record
    Commit: TAtlasVcsIncomingCommit;
    /// <summary>Dateien des Arbeitsstands, die der Commit ändert.</summary>
    Files: TArray<string>;
  end;

  /// <summary>Abschnitt „Neu seit deinem letzten Öffnen“ für einen Arbeitsstand.</summary>
  TAtlasContinueIncoming = record
    /// <summary>Abschnitt zeigen: Arbeitskopie mit verfolgtem Branch, Abfrage gelungen.</summary>
    Available: Boolean;
    /// <summary>Projekt, zu dem die Abfrage gehört.</summary>
    Project: string;
    /// <summary>Verfolgter Branch, z. B. "origin/main".</summary>
    Upstream: string;
    /// <summary>Neueste zuerst.</summary>
    Commits: TArray<TAtlasContinueCommit>;
    /// <summary>Es gibt mehr passende Commits als aufgeführt.</summary>
    More: Boolean;
    /// <summary>fetch war gewünscht und ist misslungen (Stand ohne Abruf).</summary>
    FetchFailed: Boolean;
    /// <summary>fetch ist misslungen, weil die Anmeldung am Server fehlt (#1287); dann auch FetchFailed.</summary>
    LoginNeeded: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    At: TDateTime;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Zustand eines Issues: unbekannt, offen oder behoben bzw. geschlossen.</summary>
  TAtlasIssueStateKind = (Unknown, Open, Resolved);
  {$SCOPEDENUMS OFF}

  /// <summary>Gespeicherter Arbeitsstand eines Issues.</summary>
  TAtlasIssueWorkEntry = record
    /// <summary>Kennung wie im Tracker ("#1926", "ATL-12").</summary>
    Key: string;
    /// <summary>Titel beim Speichern; '' unbekannt.</summary>
    Title: string;
    /// <summary>Branch des Issues; '' ohne.</summary>
    Branch: string;
    State: TAtlasWorkState;
    class function Create(const AKey, ATitle, ABranch: string; const AState: TAtlasWorkState): TAtlasIssueWorkEntry;
      static;
  end;

  /// <summary>Eine Zeile des Reiters „Issues“.</summary>
  TAtlasIssueWorkRow = record
    /// <summary>Projekt bzw. Projektgruppe (vollständiger Pfad).</summary>
    Project: string;
    Entry: TAtlasIssueWorkEntry;
    /// <summary>Open oder Unknown; behobene Issues stehen nicht in der Liste.</summary>
    Status: TAtlasIssueStateKind;
    /// <summary>Zuletzt bearbeitete Datei (TAtlasWorkState.LastIndex); leer ohne Reiter.</summary>
    function LastTab: TAtlasWorkTab;
  end;

  TAtlasIssueWorkRows = TArray<TAtlasIssueWorkRow>;

  {$SCOPEDENUMS ON}
  /// <summary>Hinweis zur Nutzung: None = keiner (Zählung aus), Never = „Noch nie benutzt“, sonst „Zuletzt …“.
  /// </summary>
  TAtlasDiscoverAgeKind = (None, Never, Today, Yesterday, Days, Weeks, Months, Years);
  {$SCOPEDENUMS OFF}

  TAtlasDiscoverAge = record
    Kind: TAtlasDiscoverAgeKind;
    /// <summary>Anzahl Tage, Wochen, Monate bzw. Jahre.</summary>
    Count: Integer;
    class function Create(AKind: TAtlasDiscoverAgeKind; ACount: Integer): TAtlasDiscoverAge; static;
  end;

  /// <summary>Was die Karte zeigt.</summary>
  TAtlasDiscoverCard = record
    Id: string;
    Title: string;
    Text: string;
    /// <summary>Tatsächliche Belegung des Befehls; '' ohne.</summary>
    KeyText: string;
    /// <summary>Vollständiger Pfad des Bilds; '' ohne (oder Datei fehlt).</summary>
    ImageFile: string;
    Age: TAtlasDiscoverAge;
    /// <summary>„Ausprobieren“ möglich (Beispieldatei vorhanden oder Befehl vorhanden).</summary>
    CanTry: Boolean;
    /// <summary>Stelle (ab 1) und Zahl der Tipps, die gerade in Frage kommen.</summary>
    Position: Integer;
    Count: Integer;
  end;

  TAtlasProjectEntry = record
    Summary: TAtlasProjectSummary;
    /// <summary>Es gab eine lesbare Zusammenfassung.</summary>
    HasSummary: Boolean;
    /// <summary>Versionsverwaltung in dieser Sitzung abgefragt; sonst gilt der gespeicherte Stand.</summary>
    VcsFresh: Boolean;
    /// <summary>Die Abfrage der Versionsverwaltung läuft gerade.</summary>
    VcsQuerying: Boolean;
    function Project: string;
    function Name: string;
    /// <summary>Branch bzw. SVN-Pfad; bei losgelöstem HEAD die Kurzform des Commits; '' ohne Arbeitskopie.</summary>
    function Branch: string;
    /// <summary>Der gezeigte Stand der Versionsverwaltung stammt aus der Datei („Stand vom …“).</summary>
    function VcsStale: Boolean;
  end;

  TAtlasProjectEntries = TArray<TAtlasProjectEntry>;

  {$SCOPEDENUMS ON}
  TAtlasQuickAction = (Build, Tests, Run, Pull, Folder, Console, Tasks);
  {$SCOPEDENUMS OFF}

  {$SCOPEDENUMS ON}
  /// <summary>Grund, aus dem „Pull“ gesperrt ist.</summary>
  TAtlasPullBlock = (None, LocalChanges, NoWorkingCopy, Busy);
  {$SCOPEDENUMS OFF}

  TAtlasQuickActionButton = record
    Action: TAtlasQuickAction;
    Enabled: Boolean;
    /// <summary>Nur Pull: warum gesperrt; None sonst.</summary>
    Block: TAtlasPullBlock;
    /// <summary>Pull heißt „Aktualisieren“ (SVN).</summary>
    Update: Boolean;
    /// <summary>Der Knopf hat eine Auswahl (▾): Konfiguration und Plattform, Startprofil bzw. Aufgabe.</summary>
    HasMenu: Boolean;
    /// <summary>Nur Pull unter SVN mit vcs.externals.update = ask (#1292): Auswahl „mit Externals“ bzw. „ohne
    /// Externals“ statt sofort zu aktualisieren.</summary>
    AskExternals: Boolean;
  end;

  TAtlasQuickActionButtons = TArray<TAtlasQuickActionButton>;

  {$SCOPEDENUMS ON}
  /// <summary>Stand einer Aktion je Projekt: läuft, fertig (ok bzw. fehlgeschlagen) oder nicht ausgeführt.</summary>
  TAtlasQuickActionPhase = (Idle, Running, Succeeded, Failed, Refused);
  {$SCOPEDENUMS OFF}

  {$SCOPEDENUMS ON}
  /// <summary>Text, den die IDE nach einem Pull in Detail und als Meldung setzt: keiner, lokale Änderungen
  /// (mit Meldung), keine Arbeitskopie, Anmeldung fehlt (mit Meldung), sonst fehlgeschlagen (mit Meldung).</summary>
  TAtlasPullNote = (None, LocalChanges, NoWorkingCopy, Login, Failed);
  {$SCOPEDENUMS OFF}

  /// <summary>Stand der letzten Schnellaktion eines Projekts in dieser Sitzung.</summary>
  TAtlasQuickActionState = record
    Action: TAtlasQuickAction;
    Phase: TAtlasQuickActionPhase;
    /// <summary>Beginn (Tick in ms).</summary>
    StartedMs: UInt64;
    /// <summary>Grund bzw. Ergebnis als fertiger Text der IDE-Schicht (etwa der Grund von „nicht gebaut“).</summary>
    Detail: string;
    /// <summary>Tests: bestanden und fehlgeschlagen (mit Fehlern); Pull: neue Commits geholt.</summary>
    Passed: Integer;
    Failed: Integer;
    Pull: TAtlasPullOutcome;
    class function Idle: TAtlasQuickActionState; static;
    class function Started(AAction: TAtlasQuickAction; ANowMs: UInt64): TAtlasQuickActionState; static;
    function Running: Boolean;
    /// <summary>Ganze Sekunden seit dem Beginn; 0 vor dem Beginn.</summary>
    function ElapsedSeconds(ANowMs: UInt64): Integer;
    /// <summary>Stand nach einem Pull mit Ergebnis AOutcome; AReason ist der Grund eines Fehlschlags. ANote sagt,
    /// welchen Text die IDE noch setzt; bei Failed steht der Name von AReason schon in Detail.</summary>
    function AfterPull(AOutcome: TAtlasPullOutcome; AReason: TAtlasVcsOutcome;
      out ANote: TAtlasPullNote): TAtlasQuickActionState;
    /// <summary>Ein Testlauf endete ohne Ergebnis: läuft nicht mehr oder die Schonzeit AGraceMs ist um.</summary>
    function TestEnded(ANowMs, AGraceMs: UInt64): Boolean;
    /// <summary>Stand nach einem Testlauf mit APassed bestandenen und AFailed fehlgeschlagenen Tests.</summary>
    function AfterTests(APassed, AFailed: Integer): TAtlasQuickActionState;
  end;

  /// <summary>Konfigurationen (ohne „Base“) und eingeschaltete Plattformen einer .dproj in Dateireihenfolge.</summary>
  TAtlasProjectTargets = record
    Configurations: TArray<string>;
    Platforms: TArray<string>;
  end;

  {$SCOPEDENUMS ON}
  TAtlasSavedKind = (Note, Bookmark, Favorite);
  {$SCOPEDENUMS OFF}

  TAtlasSavedItem = record
    Kind: TAtlasSavedKind;
    /// <summary>Kennung der Notiz bzw. des Lesezeichens; beim Favoriten der Schlüssel "typ|member".</summary>
    Id: string;
    /// <summary>Titel der Notiz, Name des Lesezeichens bzw. "TDataSet.Open".</summary>
    Text: string;
    /// <summary>Vollständiger Pfad; '' beim Favoriten.</summary>
    FileName: string;
    /// <summary>Zeile, 0-basiert; -1 ohne (Favorit).</summary>
    Line: Integer;
    /// <summary>Pfad der Projektdatei; '' beim Favoriten (gilt für alle Projekte).</summary>
    Project: string;
    /// <summary>Lesezeichen: Methode; Notiz: weitere Zeilen; Favorit: Signatur.</summary>
    Detail: string;
    /// <summary>Notiz verwaist bzw. Lesezeichen nicht gefunden (letzte bekannte Zeile).</summary>
    Lost: Boolean;
    /// <summary>Nur Favorit: Unit, Typ und Member.</summary>
    UnitName: string;
    TypeName: string;
    Member: string;
    /// <summary>Name des Projekts ohne Endung; '' beim Favoriten.</summary>
    function ProjectName: string;
  end;

  TAtlasSavedItems = TArray<TAtlasSavedItem>;

  {$SCOPEDENUMS ON}
  /// <summary>Lauf eines Schritts in dieser Sitzung (Baseline, Pfadprüfung).</summary>
  TAtlasSetupRun = (Idle, Running, Done, Failed);
  {$SCOPEDENUMS OFF}

  TAtlasSetupCard = record
    /// <summary>Projektdatei des Ziels; '' = kein Projekt.</summary>
    Project: string;
    /// <summary>Dateiname ohne Endung, für den Titel.</summary>
    ProjectName: string;
    /// <summary>Das Ziel ist in der IDE geöffnet (Baseline und Pfadprüfung brauchen das).</summary>
    ProjectOpen: Boolean;
    Facts: TAtlasSetupFacts;
    /// <summary>Projektgruppe: Zahl ihrer Projekte und davon geprüfte; 0 = keine Gruppe.</summary>
    GroupProjects: Integer;
    GroupChecked: Integer;
    /// <summary>Name der vorhandenen Konfiguration (atlas.json bzw. delphi-lsp.json); '' ohne.</summary>
    ConfigName: string;
    ShowCard: Boolean;
    ShowNew: Boolean;
    Baseline: TAtlasSetupRun;
    /// <summary>Start des laufenden Schritts (Millisekunden-Zähler der Quelle).</summary>
    BaselineStarted: UInt64;
    /// <summary>Nach einem erfolgreichen Lauf: Treffer und Dateien in der neuen Baseline.</summary>
    BaselineTotal: Integer;
    BaselineFiles: Integer;
    /// <summary>Neue Regeltreffer seit der Baseline aus der Projekt-Zusammenfassung (nach dem Erzeugen 0);
    /// -1 = unbekannt.</summary>
    BaselineNewHits: Integer;
    /// <summary>Grund bei Failed (Sprache der Oberfläche).</summary>
    BaselineError: string;
    Paths: TAtlasSetupRun;
    PathsStarted: UInt64;
    PathsError: string;
    /// <summary>Hinweis zur Edition der IDE (#1822), etwa ohne Kommandozeilen-Compiler; '' ohne.</summary>
    Edition: string;
    class function Empty: TAtlasSetupCard; static;
    /// <summary>Bereich zeigen (Karte oder Knöpfe).</summary>
    function Visible: Boolean;
  end;

  {$SCOPEDENUMS ON}
  TAtlasStateRowKind = (Server, Version, Index, Setup, Diagnostic);
  {$SCOPEDENUMS OFF}

  TAtlasStateRow = record
    Kind: TAtlasStateRowKind;
    /// <summary>Kennung der Zeile im Statusfeld, z. B. "atlas.server".</summary>
    Id: string;
    /// <summary>Die Zeile gibt es im Statusfeld; sonst Ersatzzeile (neutral, Text von der UI).</summary>
    Present: Boolean;
    State: TAtlasStatusState;
    /// <summary>Kurzform der Zeile, sonst ihr Text; '' bei Ersatzzeilen.</summary>
    Text: string;
    /// <summary>Zusatz rechts; '' = keiner.</summary>
    Detail: string;
    /// <summary>Voller Text der Zeile im Statusfeld (Tooltip).</summary>
    Hint: string;
    /// <summary>Klick auf die Zeile führt die Aktion der Statusfeld-Zeile aus.</summary>
    HasAction: Boolean;
  end;

  TAtlasStateRows = TArray<TAtlasStateRow>;

  {$SCOPEDENUMS ON}
  TAtlasStateButton = (Restart, Settings, LogFolder, Update);
  {$SCOPEDENUMS OFF}

  TAtlasTrendTile = record
    Series: TAtlasTrendSeries;
    /// <summary>Wert je Punkt in Zehnteln; nur mit Has.</summary>
    Values: TArray<Integer>;
    Has: TArray<Boolean>;
    /// <summary>Skala in Zehnteln: Bottom ≤ 0 ≤ Top, Bottom &lt; Top.</summary>
    Bottom: Integer;
    Top: Integer;
    /// <summary>Der letzte Punkt hat einen Wert.</summary>
    function HasLast: Boolean;
    function Last: Integer;
    /// <summary>Letzter bekannter Wert vor dem letzten Punkt; False ohne.</summary>
    function Previous(out AValue: Integer): Boolean;
  end;

  TAtlasTrendView = record
    /// <summary>Projektdatei; '' ohne Projekt.</summary>
    Project: string;
    /// <summary>Gezeigte Punkte, älteste zuerst.</summary>
    Points: TArray<TAtlasTrendPoint>;
    /// <summary>Eine Kachel je gewählter Reihe.</summary>
    Tiles: TArray<TAtlasTrendTile>;
    /// <summary>Höchstens so viele Builds (welcomePage.trends.points).</summary>
    Limit: Integer;
    function Name: string;
  end;

  {$SCOPEDENUMS ON}
  TAtlasUnsavedKind = (Changes, Conflicts, Commits, NoUpstream, Stashes);
  {$SCOPEDENUMS OFF}

  {$SCOPEDENUMS ON}
  /// <summary>Ampel: Fresh grün, Warning gelb, Alert rot.</summary>
  TAtlasUnsavedLevel = (Fresh, Warning, Alert);
  {$SCOPEDENUMS OFF}

  /// <summary>Anteil einer Arbeitskopie (#1292): Wurzel, External oder Submodul.</summary>
  TAtlasUnsavedPlace = record
    /// <summary>Ordner relativ zur Wurzel mit "/" ('' = Wurzel).</summary>
    Path: string;
    Count: Integer;
    class function Create(const APath: string; ACount: Integer): TAtlasUnsavedPlace; static;
  end;

  TAtlasUnsavedItem = record
    Kind: TAtlasUnsavedKind;
    /// <summary>Changes und Conflicts: Dateien; Commits: Commits; NoUpstream: Branches; Stashes: Stashes.</summary>
    Count: Integer;
    /// <summary>Nur Changes: geänderte (auch umbenannt), neue (auch unversioniert) und gelöschte Dateien.</summary>
    Modified: Integer;
    Added: Integer;
    Deleted: Integer;
    /// <summary>Ältester Stand (UTC); 0 = unbekannt.</summary>
    Since: TDateTime;
    /// <summary>Commits und NoUpstream: betroffene Branches.</summary>
    Branches: TArray<string>;
    /// <summary>Nur NoUpstream: Commits, die auf keinem Remote liegen; -1 unbekannt.</summary>
    Commits: Integer;
    /// <summary>Nur Stashes: Name bzw. Nachricht und Commit des ältesten.</summary>
    Name: string;
    Ref: string;
    /// <summary>Nur Changes und Conflicts mit vcs.externals.show (#1292): Anteile, wenn sich die Dateien auf
    /// mehr als eine Arbeitskopie verteilen (Wurzel und Externals bzw. Submodule); sonst leer.</summary>
    Places: TArray<TAtlasUnsavedPlace>;
    class function Create(AKind: TAtlasUnsavedKind; ACount: Integer): TAtlasUnsavedItem; static;
    /// <summary>„Push …“ statt „Ansehen“.</summary>
    function CanPush: Boolean;
  end;

  TAtlasUnsavedRow = record
    Project: string;
    /// <summary>Name des Projekts ohne Endung.</summary>
    Name: string;
    Branch: string;
    /// <summary>"git" oder "svn".</summary>
    VcsKind: string;
    Item: TAtlasUnsavedItem;
    Level: TAtlasUnsavedLevel;
    /// <summary>Stand aus der Datei, nicht in dieser Sitzung abgefragt.</summary>
    Stale: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    At: TDateTime;
  end;

  TAtlasUnsavedView = record
    Rows: TArray<TAtlasUnsavedRow>;
    /// <summary>Zeilen, die zu jung oder bis morgen ignoriert sind.</summary>
    Hidden: Integer;
    /// <summary>Für mindestens ein Projekt ist ein Stand bekannt.</summary>
    Known: Boolean;
    /// <summary>Mindestens eine Abfrage läuft.</summary>
    Querying: Boolean;
    /// <summary>Nichts zu zeigen.</summary>
    function Clean: Boolean;
  end;

  TAtlasWhatsNewItem = record
    Title: string;
    Text: string;
    /// <summary>Titel und Text auf Englisch (#1458); '' = wie Title bzw. Text.</summary>
    TitleEn: string;
    TextEn: string;
    Setting: string;
    Key: string;
    Command: string;
    Sample: string;
    /// <summary>Zeile in Sample ab 1; 0 = Anfang.</summary>
    Line: Integer;
    /// <summary>Experimentelle Funktion (#834): eigener Abschnitt auf der Karte.</summary>
    Experimental: Boolean;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Was die Karte gerade zeigt: Ungelesenes nach Update, die aktuelle Version, alle Versionen.</summary>
  TAtlasWhatsNewView = (Hidden, Unread, Current, All);
  {$SCOPEDENUMS OFF}

  TAtlasWhatsNewVersion = record
    Version: string;
    Items: TArray<TAtlasWhatsNewItem>;
  end;

  TAtlasWhatsNewVersions = TArray<TAtlasWhatsNewVersion>;

  {$SCOPEDENUMS ON}
  /// <summary>REG_SZ, REG_EXPAND_SZ, REG_MULTI_SZ, REG_DWORD, REG_QWORD, REG_BINARY.</summary>
  TAtlasRegKind = (Text, ExpandText, MultiText, Number, Number64, Binary);
  {$SCOPEDENUMS OFF}

  TAtlasRegValue = record
    Name: string;
    Kind: TAtlasRegKind;
    /// <summary>Text; Zahlen dezimal; Binärdaten als Hex ohne Trenner.</summary>
    Data: string;
    /// <summary>Nur MultiText.</summary>
    Lines: TArray<string>;
    class function Create(const AName: string; AKind: TAtlasRegKind; const AData: string): TAtlasRegValue; static;
    class function Same(const ALeft, ARight: TAtlasRegValue): Boolean; static;
  end;

  /// <summary>Ein Registry-Schlüssel mit seinen Werten, ohne Unterschlüssel.</summary>
  TAtlasRegNode = record
    /// <summary>Pfad unter dem gelesenen Schlüssel, Teile mit „\“; '' ist der Schlüssel selbst.</summary>
    Path: string;
    Values: TArray<TAtlasRegValue>;
  end;

  /// <summary>Ein Schlüssel samt Unterschlüsseln: der Schlüssel selbst zuerst, jeder Unterschlüssel nach seinem
  /// übergeordneten.</summary>
  TAtlasRegNodes = TArray<TAtlasRegNode>;

  /// <summary>Zugriff auf die Registry (HKCU) für die Sicherung des Layouts der Willkommensseite der IDE.</summary>
  IAtlasRegistryAccess = interface
    ['{1E0726E5-4259-4FB4-AA7A-3A1870655C39}']
    /// <summary>Schlüssel unter APath (relativ zu HKCU) samt Unterschlüsseln; leer, wenn er fehlt.</summary>
    function Read(const APath: string): TAtlasRegNodes;
    /// <summary>Ersetzt den Schlüssel unter APath vollständig durch ANodes; leer löscht ihn.</summary>
    procedure Replace(const APath: string; const ANodes: TAtlasRegNodes);
  end;


  /// <summary>Offene Reiter in ihrer Reihenfolge mit der Cursorstelle und aktive Datei.</summary>
  TAtlasContinueSnapshot = record
    Tabs: TArray<TAtlasWorkTab>;
    Active: string;
  end;

  /// <summary>Einstellungen von „Weiterarbeiten“ (#755), je Aufruf frisch gelesen.</summary>
  TAtlasContinueSettings = record
    /// <summary>welcomePage.enabled: ohne Willkommensseite schreibt der Bereich nichts mit.</summary>
    WelcomePage: Boolean;
    /// <summary>welcomePage.continue.</summary>
    Continue: Boolean;
    /// <summary>welcomePage.continue.incoming: eingehende Commits und HEAD abfragen.</summary>
    Incoming: Boolean;
    /// <summary>welcomePage.continue.fetch.</summary>
    Fetch: Boolean;
    /// <summary>welcomePage.continue.count.</summary>
    Count: Integer;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Meldungen von „Weiterarbeiten“ in der Sprache der Oberfläche.</summary>
  TAtlasContinueText = (Disabled, Nothing, ProjectMissing, FilesMissing);
  {$SCOPEDENUMS OFF}

  /// <summary>Was eine Abfrage eingehender Commits braucht.</summary>
  TAtlasContinueIncomingRequest = record
    Project: string;
    MainBranch: string;
    State: TAtlasWorkState;
    Fetch: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    Stamp: TDateTime;
  end;

  /// <summary>Ende einer HEAD-Abfrage im Hauptthread.</summary>
  TAtlasContinueHeadDone = reference to procedure(AOk: Boolean; const AHead: TAtlasWorkState);
  /// <summary>Ende einer Abfrage eingehender Commits im Hauptthread.</summary>
  TAtlasContinueIncomingDone = reference to procedure(AOk: Boolean; const AFound: TAtlasContinueIncoming);
  /// <summary>Änderung an einer Projekt-Zusammenfassung unter der Sperre ihrer Datei.</summary>
  TAtlasContinueSummaryChange = reference to procedure(var ASummary: TAtlasProjectSummary);

  /// <summary>Was „Weiterarbeiten“ (TAtlasContinueWork) von der IDE braucht: Einstellungen, Uhr, Editor,
  /// Projekt-Zusammenfassungen, Versionsverwaltung im Hintergrund und Meldungen.</summary>
  IAtlasContinueHost = interface
    ['{22678DF1-04FE-4B7B-AAFF-98CB160E92EC}']
    function Settings: TAtlasContinueSettings;
    /// <summary>Millisekunden seit dem Start (GetTickCount64).</summary>
    function Ticks: UInt64;
    function NowUtc: TDateTime;
    /// <summary>Ziel des offenen Projekts bzw. der offenen Gruppe; '' ohne.</summary>
    function CurrentTarget: string;
    /// <summary>Gespeicherte Projektgruppe, zu der AFileName gehört, sonst das Projekt; '' ohne.</summary>
    function TargetOf(const AFileName: string): string;
    /// <summary>Offene Reiter festhalten; AChanges (großgeschriebener Pfad → letzte Änderung) bekommt die Methode
    /// an der Änderungsstelle.</summary>
    function TakeSnapshot(AChanges: TDictionary<string, TAtlasWorkTab>): TAtlasContinueSnapshot;
    /// <summary>Zuletzt geschlossene Projekte, neueste zuerst; leer, wenn die Liste nicht lesbar ist.</summary>
    function RecentProjects: TArray<string>;
    function LoadSummary(const ATarget: string; out ASummary: TAtlasProjectSummary): Boolean;
    procedure UpdateSummary(const ATarget: string; const AChange: TAtlasContinueSummaryChange);
    /// <summary>HEAD des Ordners im Hintergrund abfragen; False, wenn die Abfrage nicht startet (ADone kommt
    /// dann nicht).</summary>
    function QueryHead(const AFolder: string; const ADone: TAtlasContinueHeadDone): Boolean;
    /// <summary>Eingehende Commits im Hintergrund abfragen; False, wenn die Abfrage nicht startet.</summary>
    function QueryIncoming(const ARequest: TAtlasContinueIncomingRequest;
      const ADone: TAtlasContinueIncomingDone): Boolean;
    /// <summary>Hauptbranch des Projekts für Branches ohne verfolgten Branch (#1286).</summary>
    function MainBranchOf(const AProject: string): string;
    function FileExists(const AFileName: string): Boolean;
    /// <summary>Projekt öffnen, wenn es existiert und noch nicht offen ist.</summary>
    procedure EnsureProject(const AProject: string);
    /// <summary>Datei öffnen, Cursor an Zeile und Spalte des Reiters (ab 1).</summary>
    procedure OpenTab(const ATab: TAtlasWorkTab);
    function Text(AText: TAtlasContinueText; const AArgument: string): string;
    /// <summary>Zeile in die Meldungsansicht.</summary>
    procedure Say(const AText: string);
    /// <summary>Bereich neu zeichnen.</summary>
    procedure Changed;
  end;

//@TYPES
implementation

uses
  System.Math;

const
  /// <summary>Länge der kurzen Git-Revision, wenn kein Branch bekannt ist.</summary>
  cShortRevision = 7;

{ TAtlasWorkOrder }

class procedure TAtlasWorkOrder.InsertNewestFirst<T>(var AFound: TArray<T>; const AEntry: T;
  const AStateOf: TAtlasWorkStateOf<T>);
var
  mIndex, mPosition: Integer;
  mAt: TDateTime;
begin
  mAt := AStateOf(AEntry).At;
  mPosition := Length(AFound);
  for mIndex := High(AFound) downto 0 do
  begin
    if mAt > AStateOf(AFound[mIndex]).At then
    begin
      mPosition := mIndex;
    end;
  end;
  Insert(AEntry, AFound, mPosition);
end;

{ TAtlasWelcomeSection }

function TAtlasWelcomeSection.IsEnabled: Boolean;
begin
  Result := True;
  if Assigned(Enabled) then
  begin
    Result := Enabled();
  end;
end;

class function TAtlasWelcomeSection.Create(const AId, ATitle: string; AOrder: Integer;
  AColumn: TAtlasWelcomeColumn; const AEnabled: TFunc<Boolean>): TAtlasWelcomeSection;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Order := AOrder;
  Result.Column := AColumn;
  Result.Enabled := AEnabled;
  Result.Description := '';
end;

{ TAtlasWelcomeSlot }

class function TAtlasWelcomeSlot.Create(const AId: string; AColumn: Integer): TAtlasWelcomeSlot;
begin
  Result := Create(AId, AColumn, 1, True);
end;

class function TAtlasWelcomeSlot.Create(const AId: string; AColumn, AWidth: Integer;
  AVisible: Boolean): TAtlasWelcomeSlot;
begin
  Result.Id := AId;
  Result.Column := AColumn;
  Result.Width := EnsureRange(AWidth, TAtlasWelcomeLayout.cMinWidth, TAtlasWelcomeLayout.cMaxWidth);
  Result.Visible := AVisible;
end;

{ TAtlasWelcomeCell }

class function TAtlasWelcomeCell.Create(const AId: string; ASpan: Integer): TAtlasWelcomeCell;
begin
  Result.Id := AId;
  Result.Span := ASpan;
end;

{ TAtlasWorkTab }

class function TAtlasWorkTab.Create(const AFileName: string; ALine, AColumn: Integer): TAtlasWorkTab;
begin
  Result := Default(TAtlasWorkTab);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := AColumn;
end;

{ TAtlasWorkState }

class function TAtlasWorkState.Empty: TAtlasWorkState;
begin
  Result := Default(TAtlasWorkState);
  Result.Active := -1;
end;

function TAtlasWorkState.TabCount: Integer;
begin
  Result := Length(Tabs);
end;

function TAtlasWorkState.LastIndex: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Tabs) do
  begin
    if Tabs[mIndex].Changed and (Tabs[mIndex].ChangedAt > 0) and
      ((Result < 0) or (Tabs[mIndex].ChangedAt > Tabs[Result].ChangedAt)) then
    begin
      Result := mIndex;
    end;
  end;
  if Result >= 0 then
  begin
    Exit;
  end;
  if (Active >= 0) and (Active <= High(Tabs)) then
  begin
    Exit(Active);
  end;
  if Length(Tabs) > 0 then
  begin
    Result := 0;
  end;
end;

{ TAtlasContinueEntry }

function TAtlasContinueEntry.Name: string;
begin
  Result := TAtlasProjectSummary.Create(Project).Name;
end;

function TAtlasContinueEntry.IsGroup: Boolean;
begin
  Result := SameText(ExtractFileExt(Project), '.groupproj');
end;

function TAtlasContinueEntry.LastTab: TAtlasWorkTab;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasWorkTab);
  mIndex := State.LastIndex;
  if mIndex >= 0 then
  begin
    Result := State.Tabs[mIndex];
  end;
end;

{ TAtlasIssueWorkEntry }

class function TAtlasIssueWorkEntry.Create(const AKey, ATitle, ABranch: string;
  const AState: TAtlasWorkState): TAtlasIssueWorkEntry;
begin
  Result := Default(TAtlasIssueWorkEntry);
  Result.Key := Trim(AKey);
  Result.Title := ATitle;
  Result.Branch := Trim(ABranch);
  Result.State := AState;
end;

{ TAtlasIssueWorkRow }

function TAtlasIssueWorkRow.LastTab: TAtlasWorkTab;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasWorkTab);
  mIndex := Entry.State.LastIndex;
  if mIndex >= 0 then
  begin
    Result := Entry.State.Tabs[mIndex];
  end;
end;

{ TAtlasDiscoverAge }

class function TAtlasDiscoverAge.Create(AKind: TAtlasDiscoverAgeKind; ACount: Integer): TAtlasDiscoverAge;
begin
  Result.Kind := AKind;
  Result.Count := ACount;
end;

{ TAtlasProjectEntry }

function TAtlasProjectEntry.Project: string;
begin
  Result := Summary.Project;
end;

function TAtlasProjectEntry.Name: string;
begin
  Result := Summary.Name;
end;

function TAtlasProjectEntry.Branch: string;
begin
  Result := '';
  if not Summary.Vcs.InWorkingCopy then
  begin
    Exit;
  end;
  Result := Summary.Vcs.Branch;
  if (Result = '') and SameText(Summary.Vcs.Kind, 'git') then
  begin
    Result := Copy(Summary.Vcs.Revision, 1, cShortRevision);
  end;
end;

function TAtlasProjectEntry.VcsStale: Boolean;
begin
  Result := not VcsFresh and Summary.Vcs.InWorkingCopy;
end;

{ TAtlasQuickActionState }

class function TAtlasQuickActionState.Idle: TAtlasQuickActionState;
begin
  Result := Default(TAtlasQuickActionState);
  Result.Phase := TAtlasQuickActionPhase.Idle;
end;

class function TAtlasQuickActionState.Started(AAction: TAtlasQuickAction; ANowMs: UInt64): TAtlasQuickActionState;
begin
  Result := Idle;
  Result.Action := AAction;
  Result.Phase := TAtlasQuickActionPhase.Running;
  Result.StartedMs := ANowMs;
end;

function TAtlasQuickActionState.Running: Boolean;
begin
  Result := Phase = TAtlasQuickActionPhase.Running;
end;

function TAtlasQuickActionState.ElapsedSeconds(ANowMs: UInt64): Integer;
begin
  Result := 0;
  if (StartedMs = 0) or (ANowMs <= StartedMs) then
  begin
    Exit;
  end;
  Result := Integer((ANowMs - StartedMs) div 1000);
end;

function TAtlasQuickActionState.AfterPull(AOutcome: TAtlasPullOutcome; AReason: TAtlasVcsOutcome;
  out ANote: TAtlasPullNote): TAtlasQuickActionState;
begin
  Result := Self;
  Result.Action := TAtlasQuickAction.Pull;
  Result.Pull := AOutcome;
  Result.Detail := '';
  Result.Phase := TAtlasQuickActionPhase.Failed;
  ANote := TAtlasPullNote.None;
  case AOutcome of
    TAtlasPullOutcome.Updated, TAtlasPullOutcome.UpToDate:
      Result.Phase := TAtlasQuickActionPhase.Succeeded;
    TAtlasPullOutcome.Blocked:
      ANote := TAtlasPullNote.LocalChanges;
    TAtlasPullOutcome.NoWorkingCopy:
      ANote := TAtlasPullNote.NoWorkingCopy;
  else
    // Fehlende Anmeldung (#1287): Ursache und Weg zur Seite Versionsverwaltung statt eines Codes.
    if AReason = TAtlasVcsOutcome.LoginNeeded then
    begin
      ANote := TAtlasPullNote.Login;
    end
    else
    begin
      ANote := TAtlasPullNote.Failed;
      Result.Detail := AtlasVcsOutcomeName(AReason);
    end;
  end;
end;

function TAtlasQuickActionState.TestEnded(ANowMs, AGraceMs: UInt64): Boolean;
begin
  Result := not Running or (ANowMs >= StartedMs + AGraceMs);
end;

function TAtlasQuickActionState.AfterTests(APassed, AFailed: Integer): TAtlasQuickActionState;
begin
  Result := Self;
  Result.Action := TAtlasQuickAction.Tests;
  Result.Passed := APassed;
  Result.Failed := AFailed;
  Result.Detail := '';
  Result.Phase := TAtlasQuickActionPhase.Succeeded;
  if AFailed > 0 then
  begin
    Result.Phase := TAtlasQuickActionPhase.Failed;
  end;
end;

{ TAtlasSavedItem }

function TAtlasSavedItem.ProjectName: string;
begin
  Result := '';
  if Project = '' then
  begin
    Exit;
  end;
  Result := TAtlasProjectSummary.Create(Project).Name;
end;

{ TAtlasSetupCard }

class function TAtlasSetupCard.Empty: TAtlasSetupCard;
begin
  Result := Default(TAtlasSetupCard);
  Result.Facts := Default(TAtlasSetupFacts);
  Result.Facts.Setup := TAtlasProjectSetup.Empty;
  Result.BaselineNewHits := -1;
end;

function TAtlasSetupCard.Visible: Boolean;
begin
  Result := ShowCard or ShowNew;
end;

{ TAtlasTrendTile }

function TAtlasTrendTile.HasLast: Boolean;
begin
  Result := (Length(Has) > 0) and Has[System.High(Has)];
end;

function TAtlasTrendTile.Last: Integer;
begin
  Result := 0;
  if HasLast then
  begin
    Result := Values[System.High(Values)];
  end;
end;

function TAtlasTrendTile.Previous(out AValue: Integer): Boolean;
var
  mIndex: Integer;
begin
  AValue := 0;
  for mIndex := System.High(Has) - 1 downto 0 do
  begin
    if Has[mIndex] then
    begin
      AValue := Values[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasTrendView }

function TAtlasTrendView.Name: string;
begin
  Result := TAtlasProjectSummary.Create(Project).Name;
end;

{ TAtlasUnsavedPlace }

class function TAtlasUnsavedPlace.Create(const APath: string; ACount: Integer): TAtlasUnsavedPlace;
begin
  Result.Path := APath;
  Result.Count := ACount;
end;

{ TAtlasUnsavedItem }

class function TAtlasUnsavedItem.Create(AKind: TAtlasUnsavedKind; ACount: Integer): TAtlasUnsavedItem;
begin
  Result := Default(TAtlasUnsavedItem);
  Result.Kind := AKind;
  Result.Count := ACount;
  Result.Commits := -1;
end;

function TAtlasUnsavedItem.CanPush: Boolean;
begin
  Result := (Kind = TAtlasUnsavedKind.Commits) or (Kind = TAtlasUnsavedKind.NoUpstream);
end;

{ TAtlasUnsavedView }

function TAtlasUnsavedView.Clean: Boolean;
begin
  Result := Length(Rows) = 0;
end;

{ TAtlasRegValue }

class function TAtlasRegValue.Create(const AName: string; AKind: TAtlasRegKind; const AData: string): TAtlasRegValue;
begin
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Data := AData;
  Result.Lines := nil;
end;

class function TAtlasRegValue.Same(const ALeft, ARight: TAtlasRegValue): Boolean;
var
  mIndex: Integer;
begin
  Result := SameText(ALeft.Name, ARight.Name) and (ALeft.Kind = ARight.Kind) and (ALeft.Data = ARight.Data) and
    (Length(ALeft.Lines) = Length(ARight.Lines));
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ALeft.Lines) do
  begin
    if ALeft.Lines[mIndex] <> ARight.Lines[mIndex] then
    begin
      Exit(False);
    end;
  end;
end;



//@IMPL
end.
