unit Atlas.Core.Vcs.Contract;

// Versionsverwaltung über eine gemeinsame Schnittstelle (#571). Funktionen, die
// Branch, Revision, geänderte Dateien oder Zeilenherkunft brauchen, fragen nur
// IAtlasVersionControl; ob dahinter Git, SVN oder nichts steht, entscheidet die
// Auswahl (Atlas.Core.Vcs.Composition) nach gefundener Arbeitskopie und der
// Einstellung vcs.provider.
// Die Umsetzungen rufen git bzw. svn über IAtlasVcsRunner auf (Kommandozeile,
// keine Bibliotheken). Jeder Aufruf startet einen Prozess: Er gehört nie in
// den Hauptthread der IDE (siehe Atlas.Core.Vcs.Worker), der Prozessläufer der
// IDE lehnt ihn dort ab.
// Ohne VCL und Open Tools API; auch der Server (--changed mit SVN, #276)
// übersetzt diese Units mit.
// IAtlasVcsLocalWork (#762) ergänzt, was noch nicht auf dem Server liegt:
// lokale Branches mit Vorsprung, Commits, die nur lokal sind, Stashes und das
// Pushen nach Bestätigung. Abfragen lesen nur das lokale Repository (kein
// fetch); nur Push spricht mit dem Server.
// IAtlasVcsIncoming (#755) liefert eingehende Commits: was auf dem verfolgten
// Branch (z. B. origin/main) liegt, aber nicht in gemerkten Ständen, mit Autor
// und geänderten Dateien. Grundlage ist der lokale Stand der Remote-Branches;
// nur Fetch spricht mit dem Server (ohne Rückfrage nach Zugangsdaten).
// IAtlasVcsUpdate (#764) holt neue Commits in die Arbeitskopie: Git nur
// vorwärts (pull --ff-only), SVN mit update; für die Schnellaktion „Pull“
// der Willkommensseite.
// IAtlasVcsBranching (#765) legt für ein Issue einen Branch an und wechselt
// dorthin: Git lokal von einer Basis (checkout -b), SVN als Kopie im
// Repository (svn copy ^/trunk ^/branches/…) mit svn switch; dazu die Ordner
// für den Commit-Hook (Git prepare-commit-msg). Seit #1288 baut
// Atlas.Core.Vcs.BranchPlan die Schritte (TAtlasVcsBranchStep), zeigt sie im
// Dialog „Branch anlegen“ und IAtlasVcsBranching.RunStep führt genau diese
// aus. Seit #1290 bestimmt TAtlasVcsSvnBranchOptions, wo SVN-Branches liegen
// (vcs.branch.svn.location, Vorgabe {projektwurzel}/branches/{name}); Anlegen,
// BranchExists und SwitchBranch nutzen denselben Ort.
// IAtlasVcsSvnWorkingCopy bündelt, was nur SVN kennt (Revisionen der
// Arbeitskopie über svnversion, seit #1291 svn:externals, Wurzel des
// Repositorys und Version von svn); nur die SVN-Umsetzung bietet sie an.
// Externals beim Branch (#1291): TAtlasVcsSvnExternal beschreibt eine Zeile
// aus svn:externals samt Zustand der Arbeitskopie; TAtlasVcsExternalAction
// sagt, was mit ihr im neuen Branch geschieht (festschreiben, lassen,
// mitverzweigen); Regeln und Vorgaben stehen in TAtlasVcsSvnBranchOptions.
// Externals im Alltag (#1292): IAtlasVcsSvnExternals liest den Status samt
// Externals, aktualisiert mit oder ohne Externals (vcs.externals.update),
// zählt neue Commits auf dem Server und setzt svn:externals eines Ordners
// lokal (ohne Commit); IAtlasVcsSubmodules liefert git submodule status.
// IAtlasVcsLineHistory (#1275) liefert ganze Commit-Nachrichten zu Revisionen
// (für Issue-Kennungen in der Zeilenhistorie) und die Commits, die einen
// Zeilenbereich einer Datei geändert haben (Befehl „Issues zu dieser
// Methode“): Git über log -L, SVN über log --diff, rückwärts verfolgt.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Art der Arbeitskopie.</summary>
  TAtlasVcsKind = (None, Git, Svn);

  /// <summary>Einstellung vcs.provider: auto wählt nach gefundener Arbeitskopie (die nächstliegende gilt,
  /// bei Gleichstand Git), git bzw. svn nur diese Art, off schaltet die Versionsverwaltung ab.</summary>
  TAtlasVcsProvider = (Auto, Git, Svn, Off);

  /// <summary>Ergebnis eines Aufrufs. Ok: Werte gültig. NoWorkingCopy: Ordner liegt in keiner Arbeitskopie.
  /// Disabled: vcs.provider = off. ToolMissing: git bzw. svn nicht installiert. Failed: Programm meldete einen
  /// Fehler (Exit-Code ungleich 0 oder unlesbare Ausgabe). TimedOut: Zeitlimit überschritten, Prozess
  /// beendet. Cancelled: Abbruch (Entladen der IDE). MainThread: im Hauptthread abgelehnt. LoginNeeded: der
  /// Server verlangt Zugangsdaten, die fehlen (#1287; nur Aufrufe, die mit dem Server sprechen).</summary>
  TAtlasVcsOutcome = (Ok, NoWorkingCopy, Disabled, ToolMissing, Failed, TimedOut, Cancelled, MainThread,
    LoginNeeded);

  /// <summary>Art einer Änderung gegenüber dem Stand im Repository.</summary>
  TAtlasVcsChangeKind = (Modified, Added, Deleted, Renamed, Copied, TypeChanged, Replaced, Untracked,
    Conflicted, Missing);

  /// <summary>Erkannter Wechsel zwischen zwei Ständen. Branch: anderer Branch bzw. SVN-Pfad (git checkout,
  /// git switch, svn switch). Revision: gleicher Branch, andere Revision (Commit, Pull, svn update).</summary>
  TAtlasVcsSwitch = (None, Branch, Revision);

  /// <summary>Woher die Art der Versionsverwaltung für ein Projekt kommt (#1285): Setting = globales
  /// vcs.provider, Project = persönliche Zeile in vcs.projects (#1286), TeamFile = Abschnitt vcs der .atlas.
  /// </summary>
  TAtlasVcsProviderSource = (Setting, Project, TeamFile);

  /// <summary>Wovon ein SVN-Branch kopiert wird (#1290, vcs.branch.svn.source): Head = Hauptbranch @ HEAD,
  /// WorkingCopy = Pfad der Arbeitskopie @ ihrer Revision (bei gemischter Arbeitskopie die höchste).</summary>
  TAtlasVcsSvnSource = (Head, WorkingCopy);

  /// <summary>Was nach dem Anlegen eines SVN-Branchs passiert (#1290, vcs.branch.svn.after): Switch = Arbeitskopie
  /// umschalten, Checkout = frisch in einen eigenen Ordner auschecken, None = nur anlegen.</summary>
  TAtlasVcsSvnAfter = (Switch, Checkout, None);

  /// <summary>Was mit einem External im neuen Branch geschieht (#1291): Ask = noch nicht gewählt (vcs.externals.
  /// onBranch = ask), Pin = auf die Revision der Arbeitskopie festschreiben, Keep = unverändert lassen, Branch =
  /// das Package mitverzweigen und die Zeile auf den neuen Ort umschreiben.</summary>
  TAtlasVcsExternalAction = (Ask, Pin, Keep, Branch);

  /// <summary>Wann „mitverzweigen“ vorgeschlagen wird (#1291, vcs.externals.suggestBranch).</summary>
  TAtlasVcsExternalSuggest = (Modified, Never, Always);

  /// <summary>Update mit oder ohne Externals (#1292, vcs.externals.update); Ask fragt beim Pull.</summary>
  TAtlasVcsExternalsUpdate = (WithExternals, WithoutExternals, Ask);
{$SCOPEDENUMS OFF}

  /// <summary>Feste Behandlung je Quelle (#1291, vcs.externals.rules): Source ist ein Präfix einer Repository-URL
  /// bzw. ein Pfad mit "^/"; die längste passende Regel gewinnt vor den Vorgaben.</summary>
  TAtlasVcsExternalRule = record
    Source: string;
    Action: TAtlasVcsExternalAction;
    class function Make(const ASource: string; AAction: TAtlasVcsExternalAction): TAtlasVcsExternalRule; static;
  end;

  /// <summary>Inhalt von svn:externals an einem Ordner (#1291).</summary>
  TAtlasVcsSvnExternalDefinition = record
    /// <summary>Ordner relativ zur Wurzel der Arbeitskopie, mit "/" ('' = Wurzel).</summary>
    Owner: string;
    /// <summary>Wert der Eigenschaft, Zeilen mit LF getrennt.</summary>
    Text: string;
    class function Make(const AOwner, AText: string): TAtlasVcsSvnExternalDefinition; static;
  end;

  /// <summary>Eine Zeile aus svn:externals (#1291) mit dem Zustand der Arbeitskopie.</summary>
  TAtlasVcsSvnExternal = record
    /// <summary>Ordner mit der Eigenschaft relativ zur Wurzel der Arbeitskopie, mit "/" ('' = Wurzel).</summary>
    Owner: string;
    /// <summary>Index der Zeile in der Eigenschaft von Owner (ab 0, Kommentare und Leerzeilen mitgezählt).</summary>
    Line: Integer;
    /// <summary>Zielordner relativ zu Owner, mit "/", ohne Anführungszeichen.</summary>
    Folder: string;
    /// <summary>URL, wie sie dasteht, ohne -r und Peg (relativ wie "^/…", "../…" oder vollständig).</summary>
    Url: string;
    /// <summary>Vollständige URL nach dem Auflösen der relativen Angaben.</summary>
    FullUrl: string;
    /// <summary>Pfad im Repository ohne "^/" (dekodiert); '' bei fremdem Repository.</summary>
    Source: string;
    /// <summary>Operative Revision (-r N) bzw. Peg (@N); '' ohne.</summary>
    Revision: string;
    Peg: string;
    /// <summary>Altes Format "Ordner [-r N] URL" (vor svn 1.5).</summary>
    OldFormat: Boolean;
    /// <summary>Quelle liegt in einem anderen Repository: nie mitverzweigen.</summary>
    Foreign: Boolean;
    /// <summary>Datei-External: nur festschreiben oder lassen.</summary>
    IsFile: Boolean;
    /// <summary>Höchste Revision der External-Arbeitskopie (svnversion); '' unbekannt.</summary>
    WorkingRevision: string;
    /// <summary>Lokale Änderungen in der External-Arbeitskopie (svnversion „M“).</summary>
    Modified: Boolean;
    /// <summary>Mit -r bzw. Peg: behält die Revision immer.</summary>
    function Fixed: Boolean;
    /// <summary>Ordner relativ zur Wurzel der Arbeitskopie ("Packages/Drucken").</summary>
    function Path: string;
    /// <summary>Darf mitverzweigt werden (gleiches Repository, Ordner, ohne feste Revision).</summary>
    function CanBranch: Boolean;
  end;

  /// <summary>Optionen für SVN-Branches (#1290) mit den Werten für die Platzhalter. Location und Message sind
  /// Muster; Location beginnt mit {projektwurzel} oder ^/ und kennt {name} und {kennung}; Message kennt
  /// {kennung}, {titel} und {name}; CheckoutFolder kennt {projekt}, {name} und {kennung} und gilt relativ zur
  /// Wurzel der Arbeitskopie. Aufgelöst wird mit TAtlasSvnLayout (Atlas.Core.Vcs.Internals.SvnLayout).</summary>
  TAtlasVcsSvnBranchOptions = record
    Location: string;
    Source: TAtlasVcsSvnSource;
    After: TAtlasVcsSvnAfter;
    CheckoutFolder: string;
    Message: string;
    /// <summary>Kennung und Titel des Issues ('' ohne Issue) und Name des Projekts ('' = Ordner der Arbeitskopie)
    /// für die Platzhalter.</summary>
    Key: string;
    Title: string;
    Project: string;
    /// <summary>Externals (#1291): Vorgabe für Externals ohne Revision (vcs.externals.onBranch), wann
    /// „mitverzweigen“ vorgeschlagen wird (vcs.externals.suggestBranch) und Regeln je Quelle
    /// (vcs.externals.rules).</summary>
    ExternalsOnBranch: TAtlasVcsExternalAction;
    ExternalsSuggest: TAtlasVcsExternalSuggest;
    ExternalsRules: TArray<TAtlasVcsExternalRule>;
    /// <summary>Vorgaben der Einstellungen (vcs.branch.svn.*, vcs.externals.*).</summary>
    class function Default: TAtlasVcsSvnBranchOptions; static;
    /// <summary>Verhalten vor #1290: ^/branches/{name}, HEAD, umschalten, Nachricht „Branch &lt;Name&gt;“; Externals
    /// unverändert, nie mitverzweigen (vor #1291).</summary>
    class function Legacy: TAtlasVcsSvnBranchOptions; static;
  end;


  /// <summary>Gefundene Arbeitskopie.</summary>
  TAtlasVcsWorkingCopy = record
    Kind: TAtlasVcsKind;
    /// <summary>Wurzelordner ohne abschließenden Trenner; '' ohne Arbeitskopie.</summary>
    Root: string;
    class function Empty: TAtlasVcsWorkingCopy; static;
  end;

  /// <summary>Aktueller Stand der Arbeitskopie.</summary>
  TAtlasVcsHead = record
    /// <summary>Git: Name des Branchs, '' bei losgelöstem HEAD. SVN: Pfad im Repository wie "trunk" oder
    /// "branches/x".</summary>
    Branch: string;
    /// <summary>Git: vollständiger Commit-Hash, '' vor dem ersten Commit. SVN: Revisionsnummer der
    /// Arbeitskopie.</summary>
    Revision: string;
    /// <summary>Git: HEAD zeigt auf keinen Branch.</summary>
    Detached: Boolean;
    /// <summary>Git: verfolgter Branch, z. B. "origin/main"; '' ohne (SVN immer '').</summary>
    Upstream: string;
    /// <summary>Git: Commits vor bzw. hinter dem verfolgten Branch nach dem letzten Abruf; -1 unbekannt
    /// (kein verfolgter Branch, SVN).</summary>
    Ahead: Integer;
    Behind: Integer;
    class function Empty: TAtlasVcsHead; static;
    /// <summary>Kurzform der Revision: Git die ersten 7 Zeichen, SVN "r42".</summary>
    function ShortRevision(AKind: TAtlasVcsKind): string;
  end;

  /// <summary>Stand der Versionsverwaltung für das geöffnete Projekt (#1285, Gruppe „Aktuelles Projekt“ der
  /// Optionsseite).</summary>
  TAtlasVcsProjectState = record
    /// <summary>Geöffnete .groupproj bzw. aktive .dproj; '' ohne Projekt.</summary>
    ProjectFile: string;
    Provider: TAtlasVcsProvider;
    Source: TAtlasVcsProviderSource;
    /// <summary>Bei Source Project: „Gilt für“ der Zeile; sonst ''.</summary>
    SourceMatch: string;
    /// <summary>Hauptbranch aus .atlas bzw. vcs.projects (#1286); '' = raten.</summary>
    MainBranch: string;
    WorkingCopy: TAtlasVcsWorkingCopy;
    /// <summary>Ergebnis der Abfrage von Head; NoWorkingCopy, Disabled oder ToolMissing ohne Abfrage.</summary>
    Outcome: TAtlasVcsOutcome;
    Head: TAtlasVcsHead;
    class function Empty: TAtlasVcsProjectState; static;
  end;

  /// <summary>Geänderte oder neue Datei gegenüber dem Stand im Repository.</summary>
  TAtlasVcsChange = record
    /// <summary>Vollständiger Pfad.</summary>
    Path: string;
    /// <summary>Vorheriger vollständiger Pfad bei Renamed und Copied, sonst ''.</summary>
    OldPath: string;
    Kind: TAtlasVcsChangeKind;
    /// <summary>Git: Änderung steht (auch) im Index. SVN: immer False.</summary>
    Staged: Boolean;
    /// <summary>Git: Änderung steht (auch) nur im Arbeitsverzeichnis. SVN: immer True.</summary>
    Unstaged: Boolean;
  end;

  /// <summary>Herkunft einer Zeile (blame).</summary>
  TAtlasVcsBlameLine = record
    /// <summary>Zeilennummer, 1-basiert.</summary>
    Line: Integer;
    /// <summary>Commit bzw. Revision; '' für noch nicht übernommene Zeilen.</summary>
    Revision: string;
    Author: string;
    /// <summary>Zeitpunkt in UTC; 0 für noch nicht übernommene Zeilen.</summary>
    Date: TDateTime;
    /// <summary>Git: erste Zeile der Commit-Nachricht. SVN: ''.</summary>
    Summary: string;
    /// <summary>Zeile ist noch nicht übernommen (lokale Änderung).</summary>
    function Uncommitted: Boolean;
  end;

  /// <summary>Lokaler Branch (Git, #762).</summary>
  TAtlasVcsBranch = record
    /// <summary>Kurzname, z. B. "feature/x".</summary>
    Name: string;
    /// <summary>Verfolgter Branch, z. B. "origin/main"; '' ohne.</summary>
    Upstream: string;
    /// <summary>Remote des verfolgten Branchs, z. B. "origin"; '' ohne.</summary>
    Remote: string;
    /// <summary>Ref auf dem Remote, z. B. "refs/heads/main"; '' ohne.</summary>
    RemoteRef: string;
    /// <summary>Der verfolgte Branch existiert nicht mehr (auf dem Server gelöscht).</summary>
    Gone: Boolean;
    /// <summary>Commits vor bzw. hinter dem verfolgten Branch nach dem letzten Abruf; -1 unbekannt bzw. ohne.</summary>
    Ahead: Integer;
    Behind: Integer;
    /// <summary>Zeitpunkt des letzten Commits (Committer, UTC); 0 unbekannt.</summary>
    TipDate: TDateTime;
    /// <summary>HEAD zeigt auf diesen Branch.</summary>
    Current: Boolean;
    /// <summary>Hat einen verfolgten Branch, der noch existiert.</summary>
    function Tracked: Boolean;
  end;

  /// <summary>Eintrag der Stash-Liste (Git, #762).</summary>
  TAtlasVcsStash = record
    /// <summary>Commit des Stashs (bleibt gleich, wenn neuere dazukommen).</summary>
    Hash: string;
    /// <summary>Auswahl wie "stash@{0}".</summary>
    Ref: string;
    /// <summary>Branch beim Anlegen.</summary>
    Branch: string;
    /// <summary>Name bzw. Nachricht ohne "WIP on …:"/"On …:".</summary>
    Message: string;
    /// <summary>Angelegt (UTC).</summary>
    Date: TDateTime;
  end;

  /// <summary>Commit in einer Liste (z. B. noch nicht gepusht, #762).</summary>
  TAtlasVcsCommit = record
    Hash: string;
    /// <summary>Committer-Zeitpunkt (UTC).</summary>
    Date: TDateTime;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Summary: string;
    /// <summary>Kurzform des Hashs (7 Zeichen).</summary>
    function ShortHash: string;
  end;

  /// <summary>Eingehender Commit mit Autor und geänderten Dateien (#755).</summary>
  TAtlasVcsIncomingCommit = record
    Hash: string;
    /// <summary>Committer-Zeitpunkt (UTC).</summary>
    Date: TDateTime;
    Author: string;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Summary: string;
    /// <summary>Geänderte Dateien, vollständige Pfade; leer bei Merges.</summary>
    Files: TArray<string>;
    /// <summary>Kurzform des Hashs (7 Zeichen).</summary>
    function ShortHash: string;
  end;

  /// <summary>Ganze Commit-Nachricht einer Revision (#1275).</summary>
  TAtlasVcsRevisionMessage = record
    /// <summary>Git: Commit; SVN: Revisionsnummer.</summary>
    Revision: string;
    /// <summary>Ganze Nachricht ohne Leerraum am Ende.</summary>
    Message: string;
  end;

  /// <summary>Commit, der einen Zeilenbereich einer Datei geändert hat (#1275).</summary>
  TAtlasVcsLineCommit = record
    /// <summary>Git: Commit; SVN: Revisionsnummer.</summary>
    Revision: string;
    Author: string;
    /// <summary>Zeitpunkt in UTC (Git: Committer).</summary>
    Date: TDateTime;
    /// <summary>Ganze Nachricht ohne Leerraum am Ende.</summary>
    Message: string;
    /// <summary>Unterschied dieses Commits an der Datei als Zeilen eines Unified-Diffs (Git: nur der verfolgte
    /// Bereich, SVN: die ganze Datei).</summary>
    Patch: TArray<string>;
  end;

  /// <summary>Ergebnis eines Prozessaufrufs.</summary>
  TAtlasVcsRunResult = record
    Outcome: TAtlasVcsOutcome;
    ExitCode: Integer;
    /// <summary>stdout als Bytes; die Umsetzung kennt die Kodierung (Git und svn --xml: UTF-8).</summary>
    Output: TBytes;
    /// <summary>stderr, nur für die Fehlersuche; enthält Pfade und gehört deshalb nie ins Protokoll.</summary>
    ErrorText: string;
    class function Make(AOutcome: TAtlasVcsOutcome; AExitCode: Integer; const AOutput: TBytes): TAtlasVcsRunResult;
      static;
  end;

  /// <summary>Ein Schritt beim Anlegen eines Branchs (#1288), gebaut von TAtlasVcsBranchPlan: Argumente für git
  /// bzw. svn ohne die festen Optionen der Umsetzung (Git: --no-optional-locks, -c core.quotepath=off …).</summary>
  TAtlasVcsBranchStep = record
    Arguments: TArray<string>;
    /// <summary>Spricht mit dem Server: läuft ohne Rückfrage nach Zugangsdaten, fehlende Anmeldung ergibt
    /// LoginNeeded (#1287).</summary>
    Remote: Boolean;
    /// <summary>Ändert das Repository auf dem Server (svn copy, git push); im Dialog markiert, wird bei einem
    /// späteren Fehler nicht zurückgenommen.</summary>
    ChangesServer: Boolean;
    /// <summary>Kann lange dauern (svn switch und checkout holen die ganze Arbeitskopie samt Externals): läuft mit
    /// LongTimeoutMs statt dem Zeitlimit eines Aufrufs (#1290).</summary>
    Long: Boolean;
    /// <summary>Datei, die RunStep vor dem Aufruf mit InputText (UTF-8 ohne BOM, Zeilenende LF) schreibt, z. B.
    /// für svn propset -F (#1291); '' ohne.</summary>
    InputFile: string;
    InputText: string;
    /// <summary>Zusatz für die Anzeige („Was passiert“), z. B. welche Externals umgeschrieben werden; '' ohne.
    /// </summary>
    Note: string;
    class function Make(const AArguments: TArray<string>; ARemote, AChangesServer: Boolean): TAtlasVcsBranchStep;
      overload; static;
    class function Make(const AArguments: TArray<string>; ARemote, AChangesServer,
      ALong: Boolean): TAtlasVcsBranchStep; overload; static;
  public const
    /// <summary>Zeitlimit für Schritte mit Long (10 Minuten).</summary>
    LongTimeoutMs = 600000;
  end;

  /// <summary>Startet git bzw. svn unsichtbar (ohne Konsolenfenster) und wartet höchstens ATimeoutMs.</summary>
  IAtlasVcsRunner = interface
    ['{6B3C8E1D-2F47-4A9B-B0C5-8D1E7A2F9C34}']
    /// <summary>AExecutable: vollständiger Pfad des Programms. AWorkingDir: Arbeitsverzeichnis des Prozesses.
    /// Outcome ist Ok, sobald der Prozess gelaufen ist, auch bei Exit-Code ungleich 0.</summary>
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

  /// <summary>Gemeinsame Schnittstelle für Git, SVN und „keine Versionsverwaltung“ (#571). Jede Methode
  /// außer Kind, WorkingCopy und ChangeMarker startet einen Prozess: nur aus einem Hintergrund-Thread
  /// aufrufen. Implementierungen sind zustandslos und dürfen aus mehreren Threads benutzt werden.</summary>
  IAtlasVersionControl = interface
    ['{9A2E4C61-7D3B-4F58-8E19-C4B6A0D2F713}']
    function Kind: TAtlasVcsKind;
    /// <summary>Arbeitskopie mit Wurzelordner und Art.</summary>
    function WorkingCopy: TAtlasVcsWorkingCopy;
    /// <summary>Aktueller Branch bzw. SVN-Pfad und Revision bzw. Commit.</summary>
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    /// <summary>Geänderte und neue Dateien gegenüber dem Stand im Repository (Git: HEAD samt Index, SVN: BASE),
    /// unversionierte eingeschlossen, ignorierte nicht.</summary>
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    /// <summary>Inhalt von AFileName (vollständiger Pfad) in ARevision als Bytes, für Vergleiche.
    /// ARevision '' = Stand im Repository (Git HEAD, SVN BASE).</summary>
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    /// <summary>Herkunft jeder Zeile von AFileName im Arbeitsverzeichnis (blame), Zeile für Zeile.</summary>
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    /// <summary>Billige Marke aus Dateizeitstempeln der Verwaltungsdaten (ohne Prozess); ändert sie sich, kann
    /// sich Branch oder Revision geändert haben. '' ohne Arbeitskopie.</summary>
    function ChangeMarker: string;
  end;

  /// <summary>Was noch nicht auf dem Server liegt (#762). Git, SVN und die leere Umsetzung bieten diese
  /// Schnittstelle zusätzlich zu IAtlasVersionControl (Supports). SVN kennt weder lokale Commits noch Stashes:
  /// Branches, Stashes, Remotes und Outgoing liefern dort Ok mit leerer Liste, ChangesIn und Push Failed. Jede
  /// Methode startet einen Prozess: nur aus einem Hintergrund-Thread aufrufen. Keine Abfrage spricht mit dem
  /// Server (kein fetch); Vorsprung und Rückstand gelten seit dem letzten Abruf.</summary>
  IAtlasVcsLocalWork = interface
    ['{3F1C7B52-8E4A-4D19-A6E0-5B2D9C8F7A61}']
    /// <summary>Lokale Branches mit verfolgtem Branch und Vorsprung.</summary>
    function Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
    /// <summary>Stashes, neuester zuerst.</summary>
    function Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
    /// <summary>Namen der Remotes, z. B. "origin".</summary>
    function Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
    /// <summary>Commits von ABranch, die nicht in AUpstream liegen ('' = auf keinem Remote), neueste zuerst,
    /// höchstens AMax.</summary>
    function Outgoing(const ABranch, AUpstream: string; AMax: Integer;
      out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
    /// <summary>Dateien, die ARevision (Commit oder Stash) gegenüber ihrem ersten Vorgänger ändert.</summary>
    function ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    /// <summary>Pusht ABranch nach ARemote auf ARemoteRef (z. B. "refs/heads/main"); ASetUpstream trägt ihn als
    /// verfolgten Branch ein. Spricht mit dem Server; nur nach Bestätigung durch den Benutzer.</summary>
    function Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
  end;

  /// <summary>Eingehende Commits (#755). Git, SVN und die leere Umsetzung bieten diese Schnittstelle
  /// zusätzlich zu IAtlasVersionControl (Supports). Resolve und Incoming lesen nur das lokale Repository (Git:
  /// den Stand der Remote-Branches seit dem letzten Abruf); nur Fetch spricht mit dem Server. SVN hält keinen
  /// lokalen Stand des Servers: Resolve liefert dort '', Incoming eine leere Liste und Fetch tut nichts (alle
  /// Ok ohne Prozess). Jede Methode der Git-Umsetzung startet einen Prozess: nur aus einem Hintergrund-Thread
  /// aufrufen.</summary>
  IAtlasVcsIncoming = interface
    ['{5D8B2E47-1C9A-4F63-B7D0-2E6A4C9F1B83}']
    /// <summary>Commit zu ARef (z. B. "origin/main", "HEAD" oder ein Hash); Failed, wenn es ihn nicht gibt.
    /// </summary>
    function Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
    /// <summary>Commits von AUpstream, die in keinem Stand aus AExclude liegen (leere Einträge zählen nicht),
    /// neueste zuerst, höchstens AMax, mit Autor und geänderten Dateien.</summary>
    function Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
      out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
    /// <summary>Remote-Branches von ARemote abrufen ('' = Remote des aktuellen Branchs bzw. origin), ohne
    /// Rückfrage nach Zugangsdaten. Spricht mit dem Server.</summary>
    function Fetch(const ARemote: string): TAtlasVcsOutcome;
  end;

  /// <summary>Arbeitskopie auf den Stand des Servers bringen (#764). Git: pull --ff-only ohne Rückfrage nach
  /// Zugangsdaten (kein Merge, kein Rebase; weicht der Branch ab, Failed); SVN: update. Die leere Umsetzung
  /// liefert ihr Outcome. Ob lokale Änderungen das Holen sperren, entscheidet der Aufrufer vorher. Spricht mit
  /// dem Server und startet einen Prozess: nur aus einem Hintergrund-Thread aufrufen, mit Zeitlimit.</summary>
  IAtlasVcsUpdate = interface
    ['{8AFD73A9-6F83-48FE-B1B8-4B4D0E96D7E8}']
    function Pull: TAtlasVcsOutcome;
  end;

  /// <summary>Branch für ein Issue anlegen und dorthin wechseln (#765, #1288). Git: lokaler Branch von einer
  /// Basis (checkout -b, ohne verfolgten Branch); SVN: Kopie im Repository (svn copy ^/&lt;Basis&gt;
  /// ^/branches/&lt;Name&gt; --parents) und Umstellen der Arbeitskopie (svn switch). Die Schritte baut
  /// TAtlasVcsBranchPlan, RunStep führt sie aus. Die leere Umsetzung liefert ihr Outcome. Ob lokale Änderungen
  /// vorher eine Rückfrage brauchen, entscheidet der Aufrufer. Jede Methode der Git- und SVN-Umsetzung startet
  /// einen Prozess (SVN spricht dabei mit dem Server): nur aus einem Hintergrund-Thread aufrufen, mit Zeitlimit.
  /// Namen mit Leer- oder Steuerzeichen, „..“ oder „-“ am Anfang lehnen alle mit Failed ab.</summary>
  IAtlasVcsBranching = interface
    ['{7E31B5C2-94D8-4A6F-8C27-D15E9F0A3B46}']
    /// <summary>Git: lokaler Branch refs/heads/&lt;AName&gt; existiert. SVN: ^/branches/&lt;AName&gt; existiert
    /// (fehlt er oder antwortet der Server mit einem Fehler, gilt er als nicht vorhanden).</summary>
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome; overload;
    /// <summary>Wie oben; SVN sucht am Ort aus AOptions (#1290, {projektwurzel} aus dem Pfad der Arbeitskopie).
    /// Lässt sich der Ort nicht auflösen (kein erkennbares Layout), Failed. Git und die leere Umsetzung
    /// ignorieren AOptions.</summary>
    function BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
      out AExists: Boolean): TAtlasVcsOutcome; overload;
    /// <summary>Git: Remote-Branch refs/remotes/origin/&lt;AName&gt; existiert im lokalen Stand (ohne fetch).
    /// SVN kennt keine Remote-Branches: Ok mit False.</summary>
    function RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    /// <summary>SVN: aktuelle Revision des Repositorys für ^/&lt;APath&gt; (svn info --show-item revision, mit dem
    /// Server). Git: Ok mit ''.</summary>
    function ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
    /// <summary>SVN: die Arbeitskopie hat svn:externals (propget -R, ohne Server). Git: Ok mit False.</summary>
    function HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
    /// <summary>SVN: voller Pfad der Arbeitskopie im Repository ohne "^/", z. B. "Kasse/trunk" (info --show-item
    /// relative-url, ohne Server; Head.Branch kürzt auf "trunk"). Git: Ok mit ''.</summary>
    function RepositoryPath(out APath: string): TAtlasVcsOutcome;
    /// <summary>Einen Schritt aus TAtlasVcsBranchPlan ausführen (#1288); Remote: ohne Rückfrage, LoginNeeded bei
    /// fehlender Anmeldung. Ohne Argumente Failed.</summary>
    function RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
    /// <summary>Zu einem vorhandenen Branch wechseln (Git checkout, SVN switch ^/branches/&lt;AName&gt;).</summary>
    function SwitchBranch(const AName: string): TAtlasVcsOutcome; overload;
    /// <summary>Wie oben; SVN schaltet auf den Ort aus AOptions um (#1290). Git und die leere Umsetzung
    /// ignorieren AOptions.</summary>
    function SwitchBranch(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
      overload;
    /// <summary>Git: Ordner der Hooks (beachtet core.hooksPath) und Verwaltungsordner dieser Arbeitskopie
    /// (bei Worktrees der eigene), beide vollständig. SVN kennt keine Hooks auf dem Rechner: Ok mit ''. Die leere
    /// Umsetzung liefert ihr Outcome mit ''.</summary>
    function HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
  end;

  /// <summary>Was nur SVN kennt (#1290); nur die SVN-Umsetzung bietet diese Schnittstelle (Supports). Jede
  /// Methode startet einen Prozess: nur aus einem Hintergrund-Thread aufrufen.</summary>
  IAtlasVcsSvnWorkingCopy = interface
    ['{C4E7A1D9-3B62-4F85-9A0E-6D21F8B57C34}']
    /// <summary>Ausgabe von svnversion für die Wurzel (z. B. "48213", "48190:48213M"); ohne Server. Liegt
    /// svnversion nicht neben svn, ToolMissing.</summary>
    function WorkingRevisions(out AText: string): TAtlasVcsOutcome; overload;
    /// <summary>Wie oben für AFolder relativ zur Wurzel (z. B. ein External, #1291).</summary>
    function WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome; overload;
    /// <summary>Ausgabe von svn propget svn:externals --xml -R . (#1291, ohne Server).</summary>
    function ExternalsXml(out AText: string): TAtlasVcsOutcome;
    /// <summary>URL der Wurzel des Repositorys (info --show-item repos-root-url ., ohne Server).</summary>
    function RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
    /// <summary>Version von svn ("1.14.3", svn --version --quiet).</summary>
    function ToolVersion(out AVersion: string): TAtlasVcsOutcome;
  end;

  /// <summary>Externals im Alltag (#1292), nur SVN. StatusXml und SetExternals ohne Server; Update und
  /// CommitsSince sprechen mit dem Server: nur aus einem Hintergrund-Thread, mit Zeitlimit.</summary>
  IAtlasVcsSvnExternals = interface
    ['{5B8E2F14-7C3A-4D96-A1E0-9F6B2C8D4E71}']
    /// <summary>Ausgabe von svn status --xml . samt Externals (je External ein eigener target-Abschnitt).
    /// </summary>
    function StatusXml(out AText: string): TAtlasVcsOutcome;
    /// <summary>svn update der Wurzel; AIgnoreExternals mit --ignore-externals (nur diese Arbeitskopie).</summary>
    function Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
    /// <summary>Commits auf ^/APath nach ARevision bis HEAD (svn log -q --xml -r HEAD:ARevision).</summary>
    function CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
    /// <summary>svn:externals des Ordners AOwner (relativ zur Wurzel, '' = Wurzel) auf AText setzen: nur in
    /// der Arbeitskopie (propset -F), der Commit bleibt beim Nutzer.</summary>
    function SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
  end;

  /// <summary>Git-Submodule (#1292): Ausgabe von git submodule status --recursive (ohne Server).</summary>
  IAtlasVcsSubmodules = interface
    ['{2D6A9C47-E1B8-4F35-8C0D-7A4E5B3F9162}']
    function SubmoduleStatus(out AText: string): TAtlasVcsOutcome;
  end;

  /// <summary>Herkunft von Zeilen über Commits (#1275). Git, SVN und die leere Umsetzung bieten diese Schnittstelle
  /// zusätzlich zu IAtlasVersionControl (Supports). Jede Methode der Git- und SVN-Umsetzung startet einen Prozess
  /// (SVN spricht dabei mit dem Server): nur aus einem Hintergrund-Thread aufrufen. Die leere Umsetzung liefert
  /// ihr Outcome mit leerer Liste.</summary>
  IAtlasVcsLineHistory = interface
    ['{4E7A2C95-3B18-4D6F-A0E2-91C5B8D47F36}']
    /// <summary>Ganze Nachrichten zu ARevisions (Git: Commits aus blame, SVN: Revisionsnummern) der Datei AFileName,
    /// in der Reihenfolge von git bzw. svn; unbekannte fehlen. Revisionen, die als Option gelesen würden, lehnen
    /// beide mit Failed ab. Leere Liste: Ok ohne Prozess.</summary>
    function Messages(const AFileName: string; const ARevisions: TArray<string>;
      out AMessages: TArray<TAtlasVcsRevisionMessage>): TAtlasVcsOutcome;
    /// <summary>Commits, die die Zeilen AFirstLine bis ALastLine (1-basiert, im Stand Git HEAD bzw. SVN BASE) von
    /// AFileName geändert haben, neueste zuerst. AMaxRevisions begrenzt bei Git die Commits des Bereichs, bei SVN
    /// die durchsuchten Revisionen der Datei.</summary>
    function LineHistory(const AFileName: string; AFirstLine, ALastLine, AMaxRevisions: Integer;
      out ACommits: TArray<TAtlasVcsLineCommit>): TAtlasVcsOutcome;
  end;

  /// <summary>Fehler beim Lesen einer Ausgabe; die Umsetzungen machen daraus Outcome Failed.</summary>
  EAtlasVcsParse = class(Exception);

/// <summary>Name für Meldungen: "Git", "SVN" oder "".</summary>
function AtlasVcsKindName(AKind: TAtlasVcsKind): string;
/// <summary>Name des Ergebnisses für Protokoll und Meldungen, z. B. "TimedOut".</summary>
function AtlasVcsOutcomeName(AOutcome: TAtlasVcsOutcome): string;
/// <summary>vcs.provider aus dem Text der Einstellung (auch in Anführungszeichen); unbekannt oder leer = Auto.</summary>
function AtlasVcsProviderOf(const AText: string): TAtlasVcsProvider;
/// <summary>Text der Einstellung: "auto", "git", "svn" oder "off".</summary>
function AtlasVcsProviderText(AProvider: TAtlasVcsProvider): string;
/// <summary>vcs.branch.svn.source (#1290): "workingCopy" = WorkingCopy, sonst Head.</summary>
function AtlasVcsSvnSourceOf(const AText: string): TAtlasVcsSvnSource;
/// <summary>vcs.branch.svn.after (#1290): "checkout", "none", sonst Switch.</summary>
function AtlasVcsSvnAfterOf(const AText: string): TAtlasVcsSvnAfter;
/// <summary>vcs.externals.onBranch bzw. onBranch einer Regel (#1291): "keep", "ask", "branch", sonst Pin.</summary>
function AtlasVcsExternalActionOf(const AText: string): TAtlasVcsExternalAction;
/// <summary>Text der Einstellung: "ask", "pin", "keep" bzw. "branch".</summary>
function AtlasVcsExternalActionText(AAction: TAtlasVcsExternalAction): string;
/// <summary>vcs.externals.suggestBranch (#1291): "never", "always", sonst Modified.</summary>
function AtlasVcsExternalSuggestOf(const AText: string): TAtlasVcsExternalSuggest;

/// <summary>vcs.externals.update: "without", "ask", sonst WithExternals.</summary>
function AtlasVcsExternalsUpdateOf(const AText: string): TAtlasVcsExternalsUpdate;

implementation

function AtlasVcsKindName(AKind: TAtlasVcsKind): string;
begin
  case AKind of
    TAtlasVcsKind.Git:
      Result := 'Git';
    TAtlasVcsKind.Svn:
      Result := 'SVN';
  else
    Result := '';
  end;
end;

function AtlasVcsOutcomeName(AOutcome: TAtlasVcsOutcome): string;
const
  Names: array[TAtlasVcsOutcome] of string = ('Ok', 'NoWorkingCopy', 'Disabled', 'ToolMissing', 'Failed',
    'TimedOut', 'Cancelled', 'MainThread', 'LoginNeeded');
begin
  Result := Names[AOutcome];
end;

function AtlasVcsProviderOf(const AText: string): TAtlasVcsProvider;
var
  Text: string;
begin
  // Auch als JSON-Text mit Anführungszeichen, wie ihn TAtlasJsonText.ValueAt liefert.
  Text := LowerCase(Trim(AText).Trim(['"']));
  if Text = 'git' then
    Result := TAtlasVcsProvider.Git
  else if Text = 'svn' then
    Result := TAtlasVcsProvider.Svn
  else if Text = 'off' then
    Result := TAtlasVcsProvider.Off
  else
    Result := TAtlasVcsProvider.Auto;
end;

function AtlasVcsProviderText(AProvider: TAtlasVcsProvider): string;
begin
  case AProvider of
    TAtlasVcsProvider.Git:
      Result := 'git';
    TAtlasVcsProvider.Svn:
      Result := 'svn';
    TAtlasVcsProvider.Off:
      Result := 'off';
  else
    Result := 'auto';
  end;
end;

function AtlasVcsSvnSourceOf(const AText: string): TAtlasVcsSvnSource;
begin
  if SameText(Trim(AText), 'workingCopy') then
    Result := TAtlasVcsSvnSource.WorkingCopy
  else
    Result := TAtlasVcsSvnSource.Head;
end;

function AtlasVcsSvnAfterOf(const AText: string): TAtlasVcsSvnAfter;
begin
  if SameText(Trim(AText), 'checkout') then
    Result := TAtlasVcsSvnAfter.Checkout
  else if SameText(Trim(AText), 'none') then
    Result := TAtlasVcsSvnAfter.None
  else
    Result := TAtlasVcsSvnAfter.Switch;
end;

function AtlasVcsExternalActionOf(const AText: string): TAtlasVcsExternalAction;
begin
  if SameText(Trim(AText), 'keep') then
    Result := TAtlasVcsExternalAction.Keep
  else if SameText(Trim(AText), 'ask') then
    Result := TAtlasVcsExternalAction.Ask
  else if SameText(Trim(AText), 'branch') then
    Result := TAtlasVcsExternalAction.Branch
  else
    Result := TAtlasVcsExternalAction.Pin;
end;

function AtlasVcsExternalActionText(AAction: TAtlasVcsExternalAction): string;
begin
  case AAction of
    TAtlasVcsExternalAction.Ask:
      Result := 'ask';
    TAtlasVcsExternalAction.Keep:
      Result := 'keep';
    TAtlasVcsExternalAction.Branch:
      Result := 'branch';
  else
    Result := 'pin';
  end;
end;

function AtlasVcsExternalSuggestOf(const AText: string): TAtlasVcsExternalSuggest;
begin
  if SameText(Trim(AText), 'never') then
    Result := TAtlasVcsExternalSuggest.Never
  else if SameText(Trim(AText), 'always') then
    Result := TAtlasVcsExternalSuggest.Always
  else
    Result := TAtlasVcsExternalSuggest.Modified;
end;

function AtlasVcsExternalsUpdateOf(const AText: string): TAtlasVcsExternalsUpdate;
begin
  if SameText(Trim(AText), 'without') then
    Result := TAtlasVcsExternalsUpdate.WithoutExternals
  else if SameText(Trim(AText), 'ask') then
    Result := TAtlasVcsExternalsUpdate.Ask
  else
    Result := TAtlasVcsExternalsUpdate.WithExternals;
end;

{ TAtlasVcsExternalRule }

class function TAtlasVcsExternalRule.Make(const ASource: string;
  AAction: TAtlasVcsExternalAction): TAtlasVcsExternalRule;
begin
  Result.Source := ASource;
  Result.Action := AAction;
end;

{ TAtlasVcsSvnExternalDefinition }

class function TAtlasVcsSvnExternalDefinition.Make(const AOwner, AText: string): TAtlasVcsSvnExternalDefinition;
begin
  Result.Owner := AOwner;
  Result.Text := AText;
end;

{ TAtlasVcsSvnExternal }

function TAtlasVcsSvnExternal.Fixed: Boolean;
begin
  Result := (Revision <> '') or (Peg <> '');
end;

function TAtlasVcsSvnExternal.Path: string;
begin
  if Owner = '' then
    Result := Folder
  else
    Result := Owner + '/' + Folder;
end;

function TAtlasVcsSvnExternal.CanBranch: Boolean;
begin
  Result := not Foreign and not IsFile and not Fixed and (Source <> '');
end;

{ TAtlasVcsWorkingCopy }

class function TAtlasVcsWorkingCopy.Empty: TAtlasVcsWorkingCopy;
begin
  Result.Kind := TAtlasVcsKind.None;
  Result.Root := '';
end;

{ TAtlasVcsProjectState }

class function TAtlasVcsProjectState.Empty: TAtlasVcsProjectState;
begin
  Result.ProjectFile := '';
  Result.Provider := TAtlasVcsProvider.Auto;
  Result.Source := TAtlasVcsProviderSource.Setting;
  Result.SourceMatch := '';
  Result.MainBranch := '';
  Result.WorkingCopy := TAtlasVcsWorkingCopy.Empty;
  Result.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
  Result.Head := TAtlasVcsHead.Empty;
end;

{ TAtlasVcsHead }

class function TAtlasVcsHead.Empty: TAtlasVcsHead;
begin
  Result.Branch := '';
  Result.Revision := '';
  Result.Detached := False;
  Result.Upstream := '';
  Result.Ahead := -1;
  Result.Behind := -1;
end;

function TAtlasVcsHead.ShortRevision(AKind: TAtlasVcsKind): string;
begin
  if Revision = '' then
    Result := ''
  else if AKind = TAtlasVcsKind.Svn then
    Result := 'r' + Revision
  else
    Result := Copy(Revision, 1, 7);
end;

{ TAtlasVcsBlameLine }

function TAtlasVcsBlameLine.Uncommitted: Boolean;
begin
  Result := Revision = '';
end;

{ TAtlasVcsBranch }

function TAtlasVcsBranch.Tracked: Boolean;
begin
  Result := (Upstream <> '') and not Gone;
end;

{ TAtlasVcsCommit }

function TAtlasVcsCommit.ShortHash: string;
begin
  Result := Copy(Hash, 1, 7);
end;

{ TAtlasVcsIncomingCommit }

function TAtlasVcsIncomingCommit.ShortHash: string;
begin
  Result := Copy(Hash, 1, 7);
end;

{ TAtlasVcsRunResult }

class function TAtlasVcsRunResult.Make(AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
  const AOutput: TBytes): TAtlasVcsRunResult;
begin
  Result.Outcome := AOutcome;
  Result.ExitCode := AExitCode;
  Result.Output := AOutput;
  Result.ErrorText := '';
end;

{ TAtlasVcsBranchStep }

class function TAtlasVcsBranchStep.Make(const AArguments: TArray<string>; ARemote,
  AChangesServer: Boolean): TAtlasVcsBranchStep;
begin
  Result := Make(AArguments, ARemote, AChangesServer, False);
end;

class function TAtlasVcsBranchStep.Make(const AArguments: TArray<string>; ARemote, AChangesServer,
  ALong: Boolean): TAtlasVcsBranchStep;
begin
  Result.Arguments := AArguments;
  Result.Remote := ARemote;
  Result.ChangesServer := AChangesServer;
  Result.Long := ALong;
  Result.InputFile := '';
  Result.InputText := '';
  Result.Note := '';
end;

{ TAtlasVcsSvnBranchOptions }

class function TAtlasVcsSvnBranchOptions.Default: TAtlasVcsSvnBranchOptions;
begin
  Result.Location := '{projektwurzel}/branches/{name}';
  Result.Source := TAtlasVcsSvnSource.Head;
  Result.After := TAtlasVcsSvnAfter.Switch;
  Result.CheckoutFolder := '..\{projekt}-{kennung}';
  Result.Message := '{kennung} Branch für {titel}';
  Result.Key := '';
  Result.Title := '';
  Result.Project := '';
  Result.ExternalsOnBranch := TAtlasVcsExternalAction.Pin;
  Result.ExternalsSuggest := TAtlasVcsExternalSuggest.Modified;
  Result.ExternalsRules := nil;
end;

class function TAtlasVcsSvnBranchOptions.Legacy: TAtlasVcsSvnBranchOptions;
begin
  Result := Default;
  Result.Location := '^/branches/{name}';
  Result.Message := 'Branch {name}';
  Result.ExternalsOnBranch := TAtlasVcsExternalAction.Keep;
  Result.ExternalsSuggest := TAtlasVcsExternalSuggest.Never;
end;

end.
