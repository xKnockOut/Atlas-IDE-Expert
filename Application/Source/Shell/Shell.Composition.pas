unit Shell.Composition;

// Host-Rolle Shell: Komposition des Servers von Hand (DI-Strategie ohne Container).
// Verbindet stdin/stdout, Transport, Dispatcher, Lebenszyklus, Dokumentverwaltung,
// Syntaxdiagnosen, Nachrichtenschleife, Logging, Zeitlimit für Anfragen und
// Absturzprotokoll mit Stacktrace, Absturzfällen und Sicherheitsnetz
// (Shell.CrashCases, #1355). Jeder Ordner des Arbeitsbereichs hat
// eigene Konfiguration, eigenes Projekt und eigenen Indexaufbau
// (TShellWorkspace); der Symbolindex ist gemeinsam.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.JsonRpc.Watchdog,
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.Lsp.Lifecycle,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Common.Lsp.TextDocumentSync,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.PullDiagnostics,
  Atlas.Common.Lsp.WorkspaceCheck,
  Atlas.Common.Lsp.CompilerSwitches,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.DocumentLinks,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.Refactorings,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Query.Contract,
  Atlas.Common.Lsp.Query,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.Baseline,
  Shell.Composition.Baselines,
  Shell.Composition.Overviews,
  Shell.Composition.Analysis,
  Shell.Composition.Navigation,
  Shell.Composition.Completion,
  Shell.Composition.Editing,
  Shell.Composition.EditorCommands,
  Shell.Composition.ServerCommands,
  Shell.Composition.CodeActions,
  Shell.Composition.Status,
  Shell.Composition.Slash,
  Shell.Composition.Contract,
  Shell.Composition.UnitSearch,
  Shell.Composition.TestUnits,
  Shell.Composition.Workspaces,
  Atlas.Common.Lsp.AffectedTests,
  Shell.AffectedTests,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Lsp.SemanticTokens,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Lsp.Processes,
  Atlas.Common.Index.Processes,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Lsp.EnumValueCommands,
  Atlas.Common.Lsp.StringLiteralCommands,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Common.Lsp.WatchedFiles,
  Atlas.Common.Lsp.IndexRefresh,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Lsp.WorkspaceFolders,
  Atlas.Common.Lsp.Configuration,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Results,
  Atlas.Common.Compiler.Backend,
  Atlas.Common.Lsp.WorkDoneProgress,
  Shell.CommandLine,
  Shell.Compiler,
  Shell.Composition.Compile,
  Shell.Composition.Refactorings,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Index.Scheduler,
  Shell.Platform,
  Shell.Workspace,
  Shell.CrashCases,
  Atlas.Common.JsonRpc.RecentMessages,
  Shell.Diagnostics;

type
  TServerComposition = class
  private
    FTransport: IJsonRpcTransport;
    /// <summary>Mitschnitt (--trace) in FTransport, nicht besitzend; nil ohne Mitschnitt.</summary>
    FTracing: TJsonRpcTracingTransport;
    FLogger: ILogger;
    /// <summary>Anonymisiert das Server-Log (#647) und den Status im Diagnosepaket (#1356); kennt alle Namen der
    /// Projekte. Ohne --log bzw. mit --log-names nur für das Paket; nil nur ohne CreateForStdio.</summary>
    FLogAnonymizer: ILogAnonymizer;
    FDispatcher: TJsonRpcDispatcher;
    /// <summary>Die letzten Nachrichten des Clients für Absturzfälle (#1355).</summary>
    FRecent: IJsonRpcRecentMessages;
    /// <summary>Absturzfälle und Sicherheitsnetz (#1355); nach WireDocuments angelegt.</summary>
    FCrashCases: TShellCrashCases;
    /// <summary>--replay (#1355): Einstellungen aus dem Fall, keine eigenen Fälle.</summary>
    FReplaySettingsFile: string;
    FReplay: Boolean;
    FLifecycle: TLspLifecycle;
    FDocuments: IDocumentStore;
    FTextDocumentSync: TLspTextDocumentSync;
    FSyntaxDiagnostics: TLspSyntaxDiagnostics;
    FPullDiagnostics: TLspPullDiagnostics;
    // Projektprüfung je Indexaufbau nur einmal neu starten (29.10.2026).
    FIndexRecheck: TWorkspaceCheckIndexGate;
    /// <summary>Bearbeiten: Gliederung, Falt- und Auswahlbereiche, Formatieren, Erzeugen-Menü (#719).</summary>
    FEditing: TShellEditing;
    /// <summary>Navigation: Definition, Hover, Symbolsuche mit Lesezeichen, Hervorhebungen, verknüpftes
    /// Bearbeiten, Werte beim Debuggen, Compilerschalter, Referenzen und Umbenennen.</summary>
    FNavigation: TShellNavigation;
    /// <summary>Prozessnummer des Editors aus der Befehlszeile (#283); 0 = keine.</summary>
    FClientProcessId: Cardinal;
    /// <summary>clientInfo.name aus initialize, für „Prozesse am Projekt“ (#62).</summary>
    FClientName: string;
    FParentWatcher: TParentWatcher;
    /// <summary>Anonymisiertes Diagnoselog (#647); FDiagnosticsRef hält die Instanz am Leben.</summary>
    FDiagnostics: TShellDiagnostics;
    FDiagnosticsRef: IJsonRpcRequestObserver;
    /// <summary>Grund für die Endzeile des Diagnoselogs; InputClosed, solange nichts anderes gemeldet ist.</summary>
    FEndReason: TDiagnosticEndReason;
    /// <summary>Zuletzt gesetztes Zeitlimit für Anfragen, für die Einordnung als timeout.</summary>
    FRequestTimeout: Cardinal;
    /// <summary>Vervollständigung im Editor und in den Debug-Dialogen (#538).</summary>
    FCompletion: TShellCompletion;
    /// <summary>Analysen: Signaturhilfe, Hierarchien, Auswirkungen, Datenfluss, Zugriffsketten,
    /// Implementierungen, Inlay-Hinweise, Code-Linsen, Metriken, TODOs, semantische Hervorhebung.</summary>
    FAnalysis: TShellAnalysis;
    /// <summary>Übersichten (#1118, #1351, #1354, #593, #1117, #854, #623): Architektur, Abfragen, Hotspots,
    /// Unit-Beziehungen, Weg zwischen Symbolen, Wertdarstellungen, Ereignisbehandlungen, Rekursion.</summary>
    FOverviews: TShellOverviews;
    /// <summary>Baseline für Altprojekte (#97, atlas.updateBaseline), Compilermeldungen darin (#530) und die
    /// Sammelkorrektur (#1352).</summary>
    FBaselines: TShellBaselines;
    /// <summary>Code-Aktionen, Dokumentlinks und Farben.</summary>
    FCodeActions: TShellCodeActions;
    FRefactorings: TShellRefactorings;
    /// <summary>Testunit anlegen und wechseln (#274, #189).</summary>
    FTestUnits: TShellTestUnits;
    /// <summary>Daten des Fensters „Units suchen“ im Plugin (#777).</summary>
    FUnitSearch: TShellUnitSearch;
    FCommands: TLspCommands;
    // Methodenreferenzen für die Befehle, vorab gebildet (Free Pascal). Je Empfänger der eigene Typ: Delphi 12 nimmt
    // TCompletionReadText nicht als TResourceStringRead an, obwohl die Signatur gleich ist.
    FEnsureUnitRef: TEnsureUnitFunc;
    /// <summary>Host der Schnellbefehle (#297) mit seinen Quellen.</summary>
    FSlash: TShellSlash;
    /// <summary>Befehle des Plugins am Editor (#698, #712, #689, #660, #768, #473).</summary>
    FEditorCommands: TShellEditorCommands;
    /// <summary>Befehle am Server selbst: Status, Einstellungen, Bau, Index, Build und Projekt wählen.</summary>
    FServerCommands: TShellServerCommands;
    /// <summary>Status (#28, #1356), Prozesse (#62), Fehlerbericht (#108) und Diagnosepaket (#1356).</summary>
    FStatusReports: TShellStatusReports;
    FStatistics: IJsonRpcStatistics;
    /// <summary>Letzte Logzeilen für den Fehlerbericht (#108); nil ohne CreateForStdio.</summary>
    FRecentLog: IRecentLogLines;
    FWatchedFiles: TLspWatchedFiles;
    /// <summary>Aktive Unit nach der Tipp-Pause neu in den Index (#492).</summary>
    FIndexRefresh: TLspIndexRefresh;
    /// <summary>uses-Listen der übernommenen Puffer (#896): bei Änderung andere offene Units neu prüfen.</summary>
    FUsesChanges: TLspUsesChanges;
    /// <summary>Build-Ergebnisse und Compilermeldungen aus der IDE (#528).</summary>
    FIdeBuild: TLspIdeBuild;
    /// <summary>Projektkontext aus der IDE (#396).</summary>
    FIdeProject: TLspIdeProject;
    /// <summary>Gemerkte Projektwahl über Neustarts (#46): selectBuild je Projekt, selectProject je Ordner.</summary>
    FProjectSelection: TProjectSelection;
    FWorkspaceFolders: TLspWorkspaceFolders;
    /// <summary>Für atlas.json außerhalb aller Ordner: nur Fehlermeldungen.</summary>
    FLooseConfiguration: TLspConfiguration;
    FConnection: TJsonRpcConnection;
    FIndex: ISymbolIndex;
    /// <summary>Uses-Graph über FIndex für uses-cycle und unused-unit (#64); lebt so lange wie der Index.</summary>
    FUsesGraph: TUsesGraphService;
    /// <summary>Ordner des Arbeitsbereichs mit Sperre, Nutzern und Prüfprojekten (Shell.Composition.Workspaces).
    /// </summary>
    FWorkspaces: TShellWorkspaceRegistry;
    FWorkspaceCounter: Integer;
    /// <summary>Reihenfolge der Indexaufbauten aller Projekte (#648); kleiner = früher.</summary>
    FIndexScheduler: TIndexScheduler;
    FWorkspacePriority: Integer;
    /// <summary>Schreibt nur die Nachrichtenschleife, unter FWorkspaces.Lock; der nebenläufige Fehlerbericht
    /// (#874) liest es unter derselben Sperre.</summary>
    FEditorSettings: string;
    // Globale Benutzerdatei (#227) als unterste Ebene; Pfad, Inhalt und der Beobachter für sie und die
    // atlas.json aller Ordner. FGlobalSettings nur im Thread der Nachrichtenschleife.
    FGlobalSettingsFile: string;
    FGlobalSettings: string;
    /// <summary>Einstellungen für Dateien ohne Arbeitsbereich: global und Editor (S-02). Unter FWorkspaces.Lock.</summary>
    FLooseSettings: TServerSettings;
    /// <summary>Zuletzt gesehener Stand von ruleChecks.enabled (#1454): 1 an, 0 aus; nur über TInterlocked.</summary>
    FRuleChecksState: Integer;
    FFileWatcher: TFileWatcher;
    FCompilerProcess: ICompilerProcess;
    /// <summary>Compilerläufe (#40, #261): höchstens ein Lauf zugleich, ein weiterer wird vorgemerkt.</summary>
    FCompile: TShellCompileHost;
    /// <summary>Der Client hat keinen brauchbaren Ordner gemeldet (RAD Studio, #175):
    /// Ordner werden aus den geöffneten Dateien abgeleitet.</summary>
    FDeriveWorkspaces: Boolean;
    /// <summary>Überwacht den Editor-Prozess aus initialize oder der Befehlszeile.</summary>
    procedure WatchParent(const AInitializeParams: TJSONObject);
    procedure AddWorkspace(const AFolder: TWorkspaceFolder);
    /// <summary>Ein Arbeitsbereich; AProjectFile '' = Projekt im Ordner suchen (#648).</summary>
    procedure AddProjectWorkspace(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean);
    /// <summary>Neuer Arbeitsbereich mit Setup, noch ohne Ereignisse und nicht in der Liste.</summary>
    function NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean): TShellWorkspace;
    /// <summary>Hängt Ereignisse und Rückfragen des Arbeitsbereichs an die Komposition.</summary>
    procedure WireWorkspaceEvents(AWorkspace: TShellWorkspace);
    /// <summary>Namen, die das Server-Log nicht im Klartext zeigt (#647).</summary>
    procedure AddLogNames(ANames: TArray<string>);
    /// <summary>Ereignis des Indexaufbaus ins Diagnoselog.</summary>
    procedure LogIndexEvent(AText: string);
    /// <summary>Serverweite Einstellungen aus dem zuletzt gelesenen Arbeitsbereich.</summary>
    procedure WorkspaceSettingsChanged(ASettings: TServerSettings);
    /// <summary>Konfigurationsfehler, die Index oder Abfragen brauchen (#309, #1351).</summary>
    function ConfigurationExtraIssues(const ASettings: TServerSettings): TArray<TConfigurationIssue>;
    /// <summary>Quelltext einer Datei als UTF-8-Bytes.</summary>
    function ReadSourceBytes(const AFileName: string; out AData: TBytes): Boolean;
    /// <summary>Projekte zum Eintrag (#648): die genannte .dproj, die Projekte der genannten .groupproj oder
    /// der einzigen .groupproj eines Ordners ohne eindeutige .dproj; leer = bisheriges Verhalten.</summary>
    function ProjectsOf(const AFolder: TWorkspaceFolder): TArray<string>;
    /// <summary>Legt zur Datei den Ordner mit der nächsten Projektdatei an, falls sie in keinem Ordner liegt.</summary>
    procedure DeriveWorkspace(const AFileName: string);
    procedure RemoveWorkspace(const AFolder: TWorkspaceFolder);
    /// <summary>Units, die nur entfernte Arbeitsbereiche enthalten, verlassen den Index.</summary>
    procedure RemoveOwnedUnits(const ARemoved, ARemaining: TArray<TShellWorkspace>);
    /// <summary>Teil von Create (S-02): Dispatcher mit Watchdog und Fehlerprotokoll, Lebenszyklus (initialize/shutdown).</summary>
    procedure WireProtocol;
    /// <summary>Meldung des Watchdogs, wenn eine Anfrage ihr Zeitlimit überschreitet.</summary>
    procedure RequestTimedOut(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean);
    /// <summary>Absturzfall beim Abbruch durch den Watchdog (#1355); läuft im Thread des Watchdogs.</summary>
    procedure RequestExpired(const AId, AMethod: string; ATimeoutMs: Cardinal);
    /// <summary>Überspringt eine Anfrage, die an derselben unveränderten Datei zweimal abstürzte (#1355).</summary>
    procedure GuardRequest(const AMethod: string; const AParams: TJSONValue);
    /// <summary>Protokolliert eine fehlgeschlagene Anfrage und hält sie als Absturzfall fest.</summary>
    procedure RequestFailed(const AMethod: string; const AParams: TJSONValue; const AError: Exception);
    /// <summary>Fähigkeiten für initialize; Pull-Diagnosen nur für Clients, die sie können.</summary>
    function LifecycleCapabilities: TJSONObject;
    /// <summary>Schickt eine Benachrichtigung an den Client.</summary>
    procedure NotifyClient(const AMethod: string; AParams: TJSONObject);
    /// <summary>Schreibt AText ins Debug-Protokoll.</summary>
    procedure LogDebug(const AText: string);
    /// <summary>Teil von Create (S-02): Dokumentspeicher, Synchronisation, Syntax- und Pull-Diagnosen, Compilerergebnisse.</summary>
    procedure WireDocuments;
    /// <summary>Protokolliert einen Fehler der Syntaxprüfung.</summary>
    procedure SyntaxCheckFailed(AError: Exception);
    /// <summary>Anonyme Bezeichnung einer Unit im Diagnoselog (#1094); 'unit', solange es fehlt.</summary>
    function DiagnosticsFileLabel(const AFileName: string): string;
    /// <summary>Zeitlimit einer Anfrage aus den Einstellungen.</summary>
    function CurrentRequestTimeout: Cardinal;
    /// <summary>Units, die AFileName in uses haben (#1247).</summary>
    function DependentUnitsOf(const AFileName: string): TArray<string>;
    /// <summary>Schreibt AMessage ins Protokoll.</summary>
    procedure LogInfo(const AMessage: string);
    /// <summary>Teil von WireDocuments (#1355): Absturzfälle und Sicherheitsnetz mit Dokumenten, Einstellungen
    /// und Benachrichtigung an den Client.</summary>
    procedure WireCrashCases;
    /// <summary>Compilerläufe (#40, #261) mit Weg über dcc oder die eigene IDE (cc.ps1).</summary>
    procedure WireCompile;
    /// <summary>Teil von Create (S-02): Dokumentbezogene Funktionen ohne Index: Symbole, Faltung, Formatierung, Schnellbefehle.</summary>
    procedure WireEditing;
    /// <summary>Teil von WireEditing: Gliederung, Falt- und Auswahlbereiche, Formatieren, Erzeugen-Menü.</summary>
    procedure WireEditors;
    /// <summary>Arbeitsbereich der Datei für die Schnellbefehle.</summary>
    function SlashWorkspaceOf(const AUri: string): TShellWorkspace;
    /// <summary>Einstellungen des Ordners von AUri unter FWorkspaces.Lock; False ohne Ordner.</summary>
    function WorkspaceSettingsOf(const AUri: string; out ASettings: TServerSettings): Boolean;
    /// <summary>Teil von Create (S-02): Arbeitsbereiche, Indexplanung und Konfiguration ohne Ordner; Pfade für die Syntaxprüfung.</summary>
    procedure WireWorkspaces;
    /// <summary>Dienste des Registers der Arbeitsbereiche; Projektwahl und IDE-Projekt entstehen erst danach.
    /// </summary>
    function WorkspaceRegistryServices: TShellWorkspaceRegistryServices;
    /// <summary>Teil von Create (S-02): Symbolindex und Diagnoselog.</summary>
    procedure WireIndex;
    /// <summary>Teil von Create (S-02): Definition, Hover, Arbeitsbereichssymbole, Hervorhebungen, Verweise, Umbenennen.</summary>
    procedure WireNavigation;
    /// <summary>Einstellungen der Hervorhebungen aus dem Arbeitsbereich von AUri.</summary>
    function HighlightSettingsFor(const AUri: string): THighlightSettings;
    /// <summary>Teil von Create (S-02): Vervollständigung mit Einstellungen, Postfix-Vorlagen und Teilergebnissen.</summary>
    procedure WireCompletion;
    /// <summary>Präfix der Namensvorschläge (#452).</summary>
    function NamingPrefixFor(const AUri: string; AKind: TNamingKind): string;
    /// <summary>Teil von Create (S-02): Signaturhilfe, Hierarchien, Implementierungen, Inlay-Hints, CodeLens, Metriken, TODOs, Baseline, Semantic Tokens.</summary>
    procedure WireAnalysis;
    /// <summary>Teil von WireAnalysis: Architektur, Code-Abfragen, Hotspots, Unit-Beziehungen, Wege, Wertdarstellungen.</summary>
    procedure WireOverviews;
    /// <summary>Teil von WireAnalysis: Baseline, Sammelkorrektur und Baseline der Compilermeldungen.</summary>
    procedure WireBaselines;
    /// <summary>Defines des Projekts zur Datei AFileName; nil ohne Projekt.</summary>
    function DefinesOfFile(const AFileName: string): TArray<string>;
    /// <summary>Grenzen der Metrik-Linse; False, wenn Metriken oder die Linse abgeschaltet sind.</summary>
    function CodeLensMetricsFor(const AUri: string; out ALimits: TMetricLimits): Boolean;
    /// <summary>Offene Dokumente bald neu prüfen.</summary>
    procedure RefreshDiagnosticsLater;
    /// <summary>Teil von Create (S-02): Refactorings und Befehle des Debuggers (Shell.Composition.Refactorings).
    /// </summary>
    procedure WireRefactorings;
    /// <summary>Teil von Create (S-02): Code-Aktionen, Testunits, Dokumentlinks und Farben.</summary>
    procedure WireCodeActions;
    /// <summary>Teil von WireCodeActions: Testunits anlegen und wechseln (#274, #189).</summary>
    procedure WireTestUnits;
    /// <summary>Was die Code-Aktionen vom Arbeitsbereich der Datei brauchen, unter der Sperre gelesen.</summary>
    function CodeActionWorkspaceOf(const AUri: string): TShellCodeActionWorkspace;
    /// <summary>Code-Aktionen für Testunits und der Refactorings.</summary>
    function ExtraCodeActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    /// <summary>Teil von Create (S-02): workspace/executeCommand: alle Befehle des Servers.</summary>
    procedure WireCommands;
    /// <summary>Teil von WireCommands: Befehle des Plugins am Editor.</summary>
    procedure WireEditorCommands;
    /// <summary>Teil von WireCommands: Befehle am Server selbst.</summary>
    procedure WireServerCommands;
    /// <summary>Teil von WireCommands: Status, Prozesse, Fehlerbericht und Diagnosepaket.</summary>
    procedure WireStatus;
    /// <summary>Teil von WireStatus: Zustände von Compiler, Prüflauf und Index-Warteschlange.</summary>
    procedure WireStatusStates(var AServices: TShellStatusServices);
    /// <summary>Ruft AVisit mit allen Arbeitsbereichen unter FWorkspaces.Lock auf.</summary>
    procedure VisitWorkspaces(const AVisit: TShellWorkspacesProc);
    /// <summary>Arbeitsbereich der Datei hinter AUri, mit '' alle; unter der Sperre der Arbeitsbereiche.</summary>
    function CommandWorkspaces(const AUri: string): TArray<TShellWorkspace>;
    /// <summary>Befehle für Metriken, TODOs, Architektur, Abfragen und Hotspots.</summary>
    procedure WireReportCommands;
    /// <summary>Befehle für Compiler-Baseline, Slash-Menü, Testunits und Unit-Suche.</summary>
    procedure WireSlashCommands;
    /// <summary>Teil von WireSlashCommands: Daten des Fensters „Units suchen“ (#777).</summary>
    procedure WireUnitSearch;
    /// <summary>Teil von Create (S-02): Dateiüberwachung und Index-Auffrischung.</summary>
    procedure WireWatchedFiles;
    /// <summary>Teil von Create (S-02): Anbindung an die IDE: Build-Meldungen und Projektkontext.</summary>
    procedure WireIde;
    /// <summary>Compilermeldungen aus dem Meldungsfenster der IDE ersetzen die des letzten Laufs (#528).</summary>
    procedure IdeMessagesReceived(const AMessages: TArray<TCompilerMessage>);
    /// <summary>Wurzel des Arbeitsbereichs zum Projekt AProject, sonst dessen Ordner.</summary>
    function BuildRootOf(const AProject: string): string;
    /// <summary>Legt den letzten Build für den MCP-Prozess ab (#556).</summary>
    procedure IdeBuildChanged(const ABuild: TIdeBuild);
    /// <summary>Während die IDE kompiliert, ruht die Projektprüfung (#1247).</summary>
    procedure IdeCompiling(ARunning: Boolean);
    /// <summary>Arbeitsbereiche, die das Projekt AProject laden.</summary>
    function WorkspacesOfProject(const AProject: string): TArray<TShellWorkspace>;
    /// <summary>Konfiguration, Plattform und Optionen aus der IDE (#396): betroffene Projekte neu laden.</summary>
    procedure IdeProjectChanged(const AContext: TIdeProjectContext);
    /// <summary>Neue Präfixe aus .atlas (#1111): naming-prefix und shadowed-name prüfen neu.</summary>
    procedure IdeNamingChanged(const AContext: TIdeProjectContext);
    /// <summary>Teil von Create (S-02): Arbeitsbereichsordner und Ereignisse nach initialized.</summary>
    procedure WireWorkspaceFolders;
    /// <summary>Arbeitsbereichsordner entfernen und hinzufügen, wie der Client sie meldet.</summary>
    procedure WorkspaceFoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
    /// <summary>Nach initialized: Client, Einstellungen, Beobachtung und erste Arbeitsbereiche.</summary>
    procedure ClientInitialized;
    /// <summary>Name, Fähigkeiten und Editor-Einstellungen des Clients aus initialize.</summary>
    procedure ApplyClientInfo(const AParams: TJSONObject);
    /// <summary>Lädt die globale Benutzerdatei und startet die Dateibeobachtung.</summary>
    procedure StartSettingsWatch;
    /// <summary>Änderungen auf der Platte wie eine Meldung des Clients einreihen.</summary>
    procedure FilesChangedOnDisk(const AFiles: TArray<string>);
    /// <summary>Wirksame Einstellungen zur Datei (S-02): die des Arbeitsbereichs (FWorkspaces.Pick), ohne
    /// Arbeitsbereich globale Datei und Editor-Einstellungen. Sperrt selbst und liefert eine Kopie.</summary>
    function SettingsFor(const AUri: string): TServerSettings;
    /// <summary>FLooseSettings aus globaler Datei und Editor-Einstellungen neu berechnen; Nachrichtenschleife.</summary>
    procedure UpdateLooseSettings;
    /// <summary>Setzt FEditorSettings unter FWorkspaces.Lock (#874).</summary>
    procedure SetEditorSettings(const AText: string);
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Ein Indexaufbau ist fertig: Befunde neu prüfen, falls die Projektstufe das nicht schon getan hat.
    /// Index-Thread.</summary>
    procedure IndexFinished;
    /// <summary>Projektstufe eines Aufbaus fertig: Befunde mit dem Index neu prüfen (#647). Index-Thread.</summary>
    procedure ProjectReady;
    /// <summary>Gemeinsamer Teil von ProjectReady und IndexFinished.</summary>
    procedure IndexStageDone(AProjectStage: Boolean);
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Muster, Ordner und Testprogramm für Testunits zur Datei (#274, #189).</summary>
    function TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
    /// <summary>Projektdateien aller Ordner und geöffnete Dokumente, für Referenzen und Umbenennen.</summary>
    function ProjectSourceFiles: TArray<string>;
    /// <summary>Dateien der Projektprüfung: ProjectSourceFiles ohne Testunits, wenn excludeTests gilt.</summary>
    function CheckSourceFiles: TArray<string>;
    /// <summary>Noch nicht gesehene Projektdateien von AWorkspace, mit excludeTests ohne Testunits.</summary>
    function CheckFilesOf(AWorkspace: TShellWorkspace; ASeen: TDictionary<string, Boolean>): TArray<string>;
    /// <summary>Hat die Unit laut Index ein Test-Framework im uses?</summary>
    function IsIndexedTestUnit(const AFileName: string): Boolean;
    /// <summary>Befehl „Eigenschaftsregeln anwenden“ (#309): WorkspaceEdit über die Formulardateien.</summary>
    function ApplyDfmPropertyRules(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Units im Bereich form, project oder group zur Unit AFileName.</summary>
    function DfmPropertyUnits(const AFileName, AScope: string): TArray<string>;
    /// <summary>Befunde nur der Regel dfm-property für eine Unit mit Formulardatei.</summary>
    function DfmPropertyFindings(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;
    /// <summary>Projekt der Datei AFileName für Umbauten mit neuen Units; False ohne Projekt.</summary>
    function RefactoringProject(const AFileName: string; out AProject: TProjectInfo): Boolean;
    /// <summary>Suche nach AUnitName im Projekt der Datei AFileName vorbereiten (#550).</summary>
    function MissingUnitSetupFor(const AFileName, AUnitName: string; out ASetup: TMissingUnitSetup): Boolean;
    /// <summary>Übrige Projekte der Gruppe mit ihren Suchpfaden. Aufrufer hält FWorkspaces.Lock.</summary>
    function GroupMembersOf(AWorkspace: TShellWorkspace): TArray<TMissingUnitProject>;
    /// <summary>Datei einer Unit aus dem Index, ohne nachzuladen; '' wenn unbekannt.</summary>
    function IndexUnitFile(AName: string): string;
    /// <summary>Präfixe neuer Namen für Refactorings in AUri: die der Namensregel, wenn sie für die Datei läuft
    /// (dieselbe Entscheidung wie in der Prüfung, TRuleEngine.NewNames).</summary>
    function NewNamesFor(const AUri: string): TPascalNamePrefixes;
    function DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
    /// <summary>Include-Resolver mit den Suchpfaden des Projekts von AUri (#860).</summary>
    function IncludeResolverFor(const AUri: string): TIncludeResolver;
    function DelphiVersionFor(const AUri: string): string;
    /// <summary>Sprachstand von AUri (#1126): die ältere aus DelphiVersionFor und minDelphiVersion des Projekts.
    /// Gilt für Diagnosen, Code-Aktionen, Schnellbefehle und Formatieren; Hover und Hilfe-Links nehmen weiter
    /// DelphiVersionFor.</summary>
    function LanguageLevelFor(const AUri: string): string;
    /// <summary>Schnellbefehle (#293): False = aus; ADisabled samt "uses" bei usesCommand = false.</summary>
    function SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
    /// <summary>Index und usesKeep für /sortuses (#297) und die uses-Diagnosen (#621); False, solange die
    /// Code-Aktionen fehlen.</summary>
    function UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
    /// <summary>Optionen des Graphen der Unit-Beziehungen (#593): Wurzel und Namensräume des Projekts der
    /// Datei, ohne Ausschlüsse der Architektur, damit „Wird verwendet von“ vollständig bleibt.</summary>
    function UnitRelationsOptionsFor(const AFileName: string): TUsesGraphOptions;
    /// <summary>"completeBlocks.docComment" (#88).</summary>
    function DocCommentsFor(const AUri: string): Boolean;
    function InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
    /// <summary>Einstellungen, Wurzel und Dateien für die Code-Metriken (#66): Datei, Projekt (.dproj/.dpr/.dpk),
    /// Ordner oder '' (einziger Arbeitsbereich).</summary>
    function MetricsSourceFor(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean;
    /// <summary>Arbeitsbereich für Metriken: Projekt der Projektdatei, sonst der der Datei bzw. der einzige.
    /// Aufrufer hält FWorkspaces.Lock.</summary>
    function MetricsWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Arbeitsbereich, dessen Projekt AFileName ist (.dproj, .dpr, .dpk). Aufrufer hält FWorkspaces.Lock.</summary>
    function ProjectWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Anfrage der Architekturübersicht (#1118) zum Arbeitsbereich von AFileName: Einstellungen, Wurzel,
    /// Titel, Namensräume und Dateien des Projekts (AScope "project") bzw. aller Projekte (sonst; leer =
    /// architecture.scope).</summary>
    function ArchitectureSourceFor(const AFileName, AScope: string; out ARequest: TArchitectureRequest;
      out ASettings: TServerSettings): Boolean;
    /// <summary>Projektdateien aller Arbeitsbereiche. Aufrufer hält FWorkspaces.Lock.</summary>
    function AllProjectFiles: TArray<string>;
    /// <summary>Namensräume des Arbeitsbereichs zu AFileName bzw. des einzigen. Aufrufer hält FWorkspaces.Lock.</summary>
    function NamespacesNear(const AFileName: string): TArray<string>;
    /// <summary>Datenquelle der Code-Abfragen (#1351): alle Projekte der Gruppe wie die Architekturübersicht,
    /// Wurzel und Namensräume des gewählten Arbeitsbereichs; False ohne Arbeitsbereich.</summary>
    function QuerySource(out ASource: TQuerySource): Boolean;
    /// <summary>Arbeitsbereich der Abfragen: aktiv in der IDE, sonst ausgewählt, sonst der erste.
    /// Aufrufer hält FWorkspaces.Lock.</summary>
    function QueryWorkspace: TShellWorkspace;
    /// <summary>Einstellungen und Projektordner für atlas/query zum Arbeitsbereich von AFileName.</summary>
    function QuerySettingsFor(const AFileName: string; out ASettings: TServerSettings; out ARoot: string): Boolean;
    /// <summary>Anfrage, Einstellungen und Versionsverwaltung für die Hotspots (#1354): Umfang wie die
    /// Architekturübersicht mit architecture.scope.</summary>
    function HotspotSourceFor(const AFileName: string; out ARequest: THotspotRequest; out ASettings: TServerSettings;
      out AVcs: IHotspotVcs; out AError: string): Boolean;
    /// <summary>Einstellungen und Namensräume für den Weg zwischen Symbolen (#1117) zum Arbeitsbereich von
    /// AFileName.</summary>
    function SymbolPathSourceFor(const AFileName: string; out ASettings: TServerSettings;
      out ANamespaces: TArray<string>): Boolean;
    function HintSettingsFor(const AUri: string): THintSettings;
    /// <summary>Begründungen (#1123): hints.rationale, Marken, TODO-Marken und ADR-Ordner des Arbeitsbereichs.
    /// </summary>
    function RationaleOptionsFor(const AUri: string): TRationaleOptions;
    /// <summary>Bedingte Symbole für Hover und Vervollständigung in Direktiven (#102): Symbole des Projekts mit
    /// Herkunft aus der .dproj, Compiler-Vorgaben, Include-Pfade und der Schalter "directives".</summary>
    function ConditionalContextFor(const AUri: string): TConditionalContext;
    /// <summary>Projektstand für atlas/compilerSwitches (#558), unabhängig von directives.*.</summary>
    function CompilerSwitchContextFor(const AUri: string): TCompilerSwitchContext;
    function RefactoringSettingsFor(const AUri: string): TRefactoringSettings;
    function CompletionSettingsFor(const AUri: string): TCompletionSettings;
    /// <summary>Formatroutinen für den Parameter-Hint (#451): eingebaute, formatMethods der Regel format-args
    /// (atlas.json) und formatFunctions der Projektdatei .atlas (Projektkontext der IDE).</summary>
    function FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
    /// <summary>"references" (#1119): Treffersicherheit für Verwendungen, Aufrufer und Umbenennen.</summary>
    function ReferenceSettingsFor(const AUri: string): TReferenceSettings;
    /// <summary>Auswirkungsanalyse (#1120): Tiefe aus "navigation", Treffersicherheit, Testunits des Testprogramms
    /// und ein Zeitlimit unter dem der Anfrage, damit die Antwort mit Hinweis statt eines Abbruchs kommt.</summary>
    function ImpactOptionsFor(const AUri: string): TImpactOptions;
    /// <summary>atlas/affectedTests (#1353): betroffene Tests der Änderungen im Arbeitsbereich von
    /// textDocument.uri gegenüber "base"; Antwort wie get_affected_tests im Format json.</summary>
    function HandleAffectedTests(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Arbeitsordner, Basis, Tiefe und ungespeicherte Änderungen aus der Anfrage.</summary>
    function AffectedQueryFor(AParams: TJSONObject; const AUri: string): TShellAffectedQuery;
    /// <summary>Dateien, Testprogramme und Optionen für betroffene Tests zu AUri.</summary>
    function AffectedRequestFor(const AUri: string; const ASettings: TServerSettings): TAffectedRequest;
    /// <summary>"stringLiteral" für AUri; AMultiline nach Stil und Delphi-Version (#312).</summary>
    function StringLiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
    function FormatStyleFor(const AUri: string): TFormatStyle;
    /// <summary>Formatstil mit .editorconfig, ohne Editor-Optionen (#43); für Schnellbefehle und try/finally.</summary>
    function ResolvedFormatStyleFor(const AUri: string): TFormatStyle;
    function RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    /// <summary>Einstellungen, Baseline, Dienste und Projekte aus dem Arbeitsbereich der Datei.</summary>
    procedure RuleWorkspaceContext(const AFileName: string; var AContext: TRuleCheckContext;
      out AProjects: TArray<TProjectInfo>; out ALibrary: Boolean);
    /// <summary>Projekte mit der Datei: das des Arbeitsbereichs, dann weitere. Aufrufer hält FWorkspaces.Lock.</summary>
    function ProjectsWithFile(AWorkspace: TShellWorkspace; const AFileName: string): TArray<TProjectInfo>;
    /// <summary>Anwendungsart, Projektname und Formulare der .dpr in den Prüfkontext.</summary>
    procedure ApplyRuleProject(const AProjects: TArray<TProjectInfo>; const AFileName: string;
      var AContext: TRuleCheckContext);
    /// <summary>Index, Nachladen und Projektdateien; ohne Index, solange Projekte laden.</summary>
    procedure RuleIndexServices(var AContext: TRuleCheckContext);
    /// <summary>Formulardatei (.dfm, sonst .fmx) neben der Unit.</summary>
    procedure ReadRuleFormFile(const AFileName: string; var AContext: TRuleCheckContext);
    /// <summary>Wie RuleContextFor für die Prüfung im Editor (LSP-Sitzung): ohne Regeln, solange der Modul-Schalter
    /// ruleChecks.enabled aus ist (#1454); jeder Wechsel steht einmal im Protokoll. Baseline, Sammelkorrektur,
    /// --check und MCP nehmen RuleContextFor.</summary>
    function LiveRuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    /// <summary>Zielplattform und Konfiguration des Projekts zu AUri für den Hinweis inaktiver Zweige (#615).
    /// </summary>
    function BuildTargetFor(const AUri: string; out APlatform, AConfig: string): Boolean;
    /// <summary>Dienste der Syntaxprüfung; sie lösen erst beim Aufruf auf, die Felder dahinter entstehen in den
    /// späteren Wire-Schritten vor der ersten Nachricht.</summary>
    function SyntaxDiagnosticsProviders: TSyntaxDiagnosticsProviders;
    /// <summary>Namespaces aller Projekte an die Features weitergeben, Diagnosen neu prüfen.</summary>
    procedure ProjectLoaded;
    /// <summary>Namespaces und Bibliothekswurzeln aller Projekte ohne Doppelte.</summary>
    procedure CollectNamespaces(out ANamespaces, ALibraryRoots: TArray<string>);
    /// <summary>Gibt die Namespaces an alle Features und den Uses-Graphen.</summary>
    procedure ApplyNamespaces(const ANamespaces: TArray<string>);
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    /// <summary>WorkspaceOf unter FWorkspaces.Lock.</summary>
    function LockedWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Index und Arbeitsbereiche zu einem Dokumentereignis einer Datei auf der Platte.</summary>
    procedure DocumentIndexEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
    /// <summary>Tipp-Pause (#492): ungespeicherter Stand in den Index, beim Schließen der der Platte.</summary>
    procedure IndexRefreshEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
    /// <summary>Gespeicherte Quelldatei: Index nachziehen (#500), bei compiler.onSave kompilieren (#40).</summary>
    procedure SourceSaved(const AFileName: string);
    /// <summary>Ereignis einer atlas.json im Editor an ihren Arbeitsbereich bzw. die lose Konfiguration.</summary>
    procedure ConfigurationDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    /// <summary>Auftrag für das Projekt zu AFileName ('' = einziger Ordner); False ohne Projekt oder Installation
    /// (Grund in AError).</summary>
    function CompileJobFor(const AFileName: string; out AJob: TShellCompileJob; out AError: string): Boolean;
    /// <summary>Beenden: Index-Threads aller Ordner anhalten; nil-sicher.</summary>
    procedure StopIndexThreads;
    /// <summary>Beenden: gibt Features, Ordner und Index frei.</summary>
    procedure FreeFeatures;
    /// <summary>Teil von FreeFeatures: Editor-Features von Gliederung bis Verweise.</summary>
    procedure FreeEditorFeatures;
    /// <summary>Teil von FreeFeatures: Analyse, Übersichten und Baselines.</summary>
    procedure FreeAnalysisFeatures;
    /// <summary>Teil von FreeFeatures: Vervollständigung, Code-Aktionen, Befehle, IDE und Protokoll.</summary>
    procedure FreeCodeFeatures;
    procedure HandleDidChangeConfiguration(const AParams: TJSONValue);
    /// <summary>Dateiänderungen von außen: Projektdateien laden das Projekt neu, Quelltexte aktualisieren den Index.</summary>
    procedure HandleWatchedFiles(const AChanges: TArray<TFileChange>);
    /// <summary>Ordnet eine Dateiänderung ein: Einstellungen, Projektdatei (AReload) oder Quelltext (ASources).</summary>
    procedure WatchedFileChanged(const AChange: TFileChange; AReload: TList<TShellWorkspace>;
      var ASources: TArray<TFileChange>);
    /// <summary>atlas.json von außen geändert (#227): alle Arbeitsbereiche lesen sie neu.</summary>
    procedure ConfigurationFileChanged(const AFileName: string);
    /// <summary>Lädt die Arbeitsbereiche mit geänderter Projektdatei neu.</summary>
    procedure ReloadWorkspaces(AReload: TList<TShellWorkspace>);
    /// <summary>Geänderte Quelltexte in den Index und in die Projektprüfung (#1247).</summary>
    procedure ApplySourceChanges(const ASources: TArray<TFileChange>);
    /// <summary>Liest die globale Benutzerdatei und gibt sie allen Ordnern (#227).</summary>
    procedure LoadGlobalSettings;
    /// <summary>Gibt dem Dateibeobachter die globale Datei und die atlas.json aller Ordner.</summary>
    procedure UpdateWatchedSettings;
    class function BuildCapabilities: TJSONObject; static;
    /// <summary>Fehlerbeschreibung mit letzter Nachricht und Stacktrace für das Log.</summary>
    function DescribeFailure(const AError: Exception): string;
  public const
    /// <summary>Anfragen, die länger laufen, werden abgebrochen und gemeldet.</summary>
    RequestTimeoutMs = 10000;
  public
    constructor Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Komposition mit stdin/stdout des Prozesses und Logging nach AOptions.</summary>
    class function CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition; static;
    /// <summary>%APPDATA%\Atlas\settings.json; '' ohne APPDATA.</summary>
    class function GlobalSettingsPath: string; static;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe und liefert den Exit-Code.</summary>
    function Run: Integer;
    /// <summary>Nachstellen eines Absturzfalls (--replay, #1355), vor Run: settings.json aus ASettingsFile ('' =
    /// keine) statt der des Benutzers; der Server sichert dabei keine Fälle und überspringt nichts.</summary>
    procedure PrepareReplay(const ASettingsFile: string);
    /// <summary>Absturzfälle und Sicherheitsnetz (#1355).</summary>
    property CrashCases: TShellCrashCases read FCrashCases;
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read FDocuments;
    property Index: ISymbolIndex read FIndex;
  end;

implementation

uses
  System.IOUtils,
  Shell.Composition.Refactorings.Services,
  System.SyncObjs,
  System.StrUtils,
  Atlas.Common.Product.Version,
  Atlas.Common.Query.Language,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Lsp.Adapters.LogMessageSink,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.IncludeFiles,
  Shell.Workspace.Setup,
  Shell.Workspace.Jobs,
  Shell.Workspace.RuleProjects,
  Shell.VcsChanges,
  Shell.Hotspots,
  Shell.Bootstrap,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Diagnostics.ServerPackage,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Lsp.DfmPropertyRules,
  Atlas.Common.Editing.SmartPaste,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.DfmProperties,
  Atlas.Common.Dfm.BinaryForm,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Compiler.OutputParser,
  Atlas.Common.Projects.DelphiVersions,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Logging.RotatingFileStream,
  Atlas.Common.Projects.GroupReader,
  Atlas.Common.JsonRpc.Messages;

const
  /// <summary>Längste Pause der Projektprüfung für einen Compile, falls sein Ende nie ankommt (#1247).</summary>
  CompilePauseLimitMs = 10 * 60 * 1000;

// PowerShell für cc.ps1 (#261): pwsh aus PATH, sonst Windows PowerShell. Der Prozessläufer
// durchsucht PATH nicht selbst.
function PowerShellProgram: string;
begin
  Result := TVcsChanges.FindProgram('pwsh');
  if SameText(Result, 'pwsh') then
  begin
    Result := TVcsChanges.FindProgram('powershell');
  end;
  if SameText(Result, 'powershell') then
  begin
    Result := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\WindowsPowerShell\v1.0\powershell.exe');
  end;
end;

// Mitschnitt anlegen. Rotiert bei Überlänge (#283). Hält ihn schon ein anderer
// Server (jede RAD-Studio-IDE startet einen eigenen), weicht er auf einen Namen
// mit AFallbackTag aus, statt ganz ohne Mitschnitt zu laufen. AActualName ist
// die tatsächlich benutzte Datei.
function CreateTraceStream(const AFileName, AFallbackTag: string; out AActualName: string): TStream;
var
  Directory: string;
  Stream: TRotatingFileStream;
begin
  Directory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if Directory <> '' then
  begin
    ForceDirectories(Directory);
  end;
  Stream := TRotatingFileStream.Create(AFileName, False, AFallbackTag);
  AActualName := Stream.FileName;
  Result := Stream;
end;

{ TServerComposition }

constructor TServerComposition.Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
begin
  inherited Create;
  FTransport := ATransport;
  FLogger := ALogger;
  FRuleChecksState := 1;
  WireProtocol;
  WireDocuments;
  WireEditing;
  WireWorkspaces;
  WireIndex;
  WireNavigation;
  WireRefactorings;
  WireCompletion;
  WireAnalysis;
  WireCodeActions;
  WireCommands;
  WireWatchedFiles;
  WireIde;
  WireWorkspaceFolders;
  FConnection := TJsonRpcConnection.Create(FTransport, FDispatcher);
  FConnection.OnError :=
    procedure(const AError: Exception)
    begin
      FLogger.Error('Fehler bei der Verarbeitung: ' + DescribeFailure(AError));
    end;
  FLifecycle.OnExit :=
    procedure
    begin
      FEndReason := TDiagnosticEndReason.Clean;
      FConnection.Stop;
    end;
end;

procedure TServerComposition.WireProtocol;
var
  mWatchdog: TJsonRpcWatchdog;
begin
  FDispatcher := TJsonRpcDispatcher.Create;
  FStatistics := TJsonRpcStatistics.Create;
  FDispatcher.Statistics := FStatistics;
  FRecent := TJsonRpcRecentMessages.Create;
  FDispatcher.Recent := FRecent;
  mWatchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, RequestTimeoutMs, RequestTimedOut);
  // Absturzfall auch beim Abbruch durch den Watchdog (#1355); läuft im Thread des Watchdogs.
  mWatchdog.OnExpired := RequestExpired;
  FDispatcher.Watchdog := mWatchdog;
  // Sicherheitsnetz (#1355): eine Anfrage, die an derselben unveränderten Datei zweimal abstürzte, überspringen.
  FDispatcher.RequestGuard := GuardRequest;
  FDispatcher.OnRequestFailed := RequestFailed;
  FLifecycle := TLspLifecycle.Create(TProductVersion.Name, TProductVersion.Version, LifecycleCapabilities);
  FLifecycle.Attach(FDispatcher);
  // Ändert der Client ein Dokument, sind laufende Anfragen dazu überholt (#283).
  FDispatcher.PendingRequests.AddContentChangeMethod('textDocument/didChange');
end;

procedure TServerComposition.RequestTimedOut(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean);
begin
  // Code-Review A-06: Nebenläufige Anfragen beantwortet der Watchdog selbst, die übrigen brechen nur ab.
  if AAnswered then
  begin
    FLogger.Warning(Format('Anfrage %s nach %d ms mit RequestCancelled beantwortet (Zeitlimit)',
      [AMethod, ATimeoutMs]));
  end
  else
  begin
    FLogger.Warning(Format('Anfrage %s hat das Zeitlimit von %d ms überschritten; Abbruch angefordert',
      [AMethod, ATimeoutMs]));
  end;
end;

procedure TServerComposition.RequestExpired(const AId, AMethod: string; ATimeoutMs: Cardinal);
begin
  if FCrashCases <> nil then
  begin
    FCrashCases.TimedOut(AId, AMethod, ATimeoutMs);
  end;
end;

procedure TServerComposition.GuardRequest(const AMethod: string; const AParams: TJSONValue);
begin
  if FCrashCases <> nil then
  begin
    FCrashCases.Guard(AMethod, AParams);
  end;
end;

procedure TServerComposition.RequestFailed(const AMethod: string; const AParams: TJSONValue;
  const AError: Exception);
var
  mParams: string;
begin
  mParams := '';
  if AParams <> nil then
  begin
    mParams := AParams.ToJSON;
  end;
  if Length(mParams) > 500 then
  begin
    mParams := Copy(mParams, 1, 500) + '…';
  end;
  FLogger.Error(Format('Anfrage %s fehlgeschlagen: %s: %s%sParameter: %s%s%s',
    [AMethod, AError.ClassName, AError.Message, sLineBreak, mParams, sLineBreak, TShellPlatform.StackTraceOf(AError)]));
  // Nachstellbarer Fall (#1355): Anfrage, Datei, Stapel; danach Meldung an den Client.
  if FCrashCases <> nil then
  begin
    FCrashCases.RequestFailed(AMethod, AParams, AError, TShellPlatform.StackTraceOf(AError));
  end;
end;

function TServerComposition.LifecycleCapabilities: TJSONObject;
begin
  Result := BuildCapabilities;
  // Pull-Diagnosen nur für Clients, die sie können; sonst bleibt es bei publishDiagnostics (#82).
  if TLspPullDiagnostics.ClientSupportsPull(FLifecycle.InitializeParams) then
  begin
    Result.AddPair('diagnosticProvider', TLspPullDiagnostics.Capability);
    FPullDiagnostics.RefreshSupport := TLspPullDiagnostics.ClientSupportsRefresh(FLifecycle.InitializeParams);
    FSyntaxDiagnostics.PullMode := True;
  end;
end;

procedure TServerComposition.NotifyClient(const AMethod: string; AParams: TJSONObject);
var
  mNotification: TJSONObject;
begin
  mNotification := TJsonRpcMessages.Notification(AMethod, AParams);
  try
    FTransport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

procedure TServerComposition.LogDebug(const AText: string);
begin
  FLogger.Debug(AText);
end;

procedure TServerComposition.WireCrashCases;
begin
  FCrashCases := TShellCrashCases.Create('', FLogger, FDocuments, FRecent);
  FCrashCases.AtlasVersion := TProductVersion.Version;
  FCrashCases.ServerPath := ParamStr(0);
  FCrashCases.Initialize :=
    function: string
    begin
      Result := '';
      if (FLifecycle <> nil) and (FLifecycle.InitializeParams <> nil) then
      begin
        Result := FLifecycle.InitializeParams.ToJSON;
      end;
    end;
  FCrashCases.SettingsFiles :=
    function(const AUri: string): TArray<string>
    var
      mWorkspace: TShellWorkspace;
    begin
      Result := nil;
      if FGlobalSettingsFile <> '' then
      begin
        Result := Result + [FGlobalSettingsFile];
      end;
      if not StartsText('file:', AUri) or (FWorkspaces.Lock = nil) then
      begin
        Exit;
      end;
      System.TMonitor.Enter(FWorkspaces.Lock);
      try
        mWorkspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
        if mWorkspace <> nil then
        begin
          Result := Result + [ExistingOrLegacyFile(mWorkspace.Root, ConfigurationFileName,
            LegacyConfigurationFileName)];
        end;
      finally
        System.TMonitor.Exit(FWorkspaces.Lock);
      end;
    end;
  FCrashCases.Notify := NotifyClient;
end;

procedure TServerComposition.PrepareReplay(const ASettingsFile: string);
begin
  FReplay := True;
  FReplaySettingsFile := ASettingsFile;
  FCrashCases.Enabled := False;
  FCrashCases.SkipEnabled := False;
end;

procedure TServerComposition.WireCompile;
var
  mServices: TShellCompileServices;
begin
  mServices := Default(TShellCompileServices);
  FCompilerProcess := TProcessRunner.Create;
  // Starter Edition ohne dcc (#261): Ausgabe je Installation erkennen und merken; eigene IDE über cc.ps1.
  mServices.Editions := TShellCompilerEditions.Create(FCompilerProcess, FLogger, TShellCompilerEditions.DefaultFile);
  mServices.IdeCompiler := TShellIdeCompiler.Create(FCompilerProcess, FLogger, PowerShellProgram,
    function: TArray<Cardinal>
    begin
      Result := TProcessInstances.IdsOf('bds.exe');
    end,
    function(APid: Cardinal): Boolean
    begin
      Result := TProcessInstances.Running(APid);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
      try
        if TFile.Exists(AFileName) then
        begin
          Result := TFileEncoding.LoadLines(AFileName);
        end;
      except
        on E: Exception do
          FLogger.Warning('Build-Log der IDE nicht lesbar: ' + E.ClassName);
      end;
    end);
  mServices.Logger := FLogger;
  mServices.Transport := FTransport;
  mServices.Process := FCompilerProcess;
  mServices.Progress := TLspWorkDoneProgress.Create(FTransport, 'atlas-compile');
  mServices.JobFor := CompileJobFor;
  mServices.Publish :=
    procedure(const AFiles: TArray<string>)
    begin
      FSyntaxDiagnostics.RefreshFiles(AFiles);
    end;
  FCompile := TShellCompileHost.Create(mServices);
end;

/// <summary>Kanonischer Pfad für den Dokumentspeicher.</summary>
function CanonicalPath(const APath: string): string;
begin
  Result := TShellPlatform.CanonicalizePath(APath);
end;

/// <summary>Zeitstempel einer Datei in Millisekunden (UTC); False, wenn sie fehlt.</summary>
function FileStampOf(const AFileName: string; out AStamp: Int64): Boolean;
begin
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AStamp := Round(TFile.GetLastWriteTimeUtc(AFileName) * MSecsPerDay);
  end
  else
  begin
    AStamp := 0;
  end;
end;

/// <summary>Liest eine vorhandene Datei mit erkannter Kodierung; False, wenn sie fehlt.</summary>
function LoadExistingFile(const AFileName: string; out AText: string): Boolean;
var
  mFileFormat: TFileFormat;
begin
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AText := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  end
  else
  begin
    AText := '';
  end;
end;

procedure TServerComposition.WireDocuments;
begin
  FDocuments := TDocumentStore.Create(CanonicalPath);
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FDispatcher);
  WireCrashCases;
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport, SyntaxDiagnosticsProviders);
  FSyntaxDiagnostics.OnError := SyntaxCheckFailed;
  WireCompile;
  FSyntaxDiagnostics.Attach;
  FIndexRecheck := TWorkspaceCheckIndexGate.Create;
  FPullDiagnostics := TLspPullDiagnostics.Create(FDocuments, FSyntaxDiagnostics, FTransport, CheckSourceFiles,
    FileStampOf, LoadExistingFile);
  FPullDiagnostics.Busy :=
    function: Boolean
    begin
      Result := FWorkspaces.ProjectIndexPending;
    end;
  // Unit im Diagnoselog nur anonym (#1094); das Diagnoselog entsteht erst später.
  FPullDiagnostics.FileLabel := DiagnosticsFileLabel;
  // Long-Polling endet vor dem Zeitlimit des Watchdogs (Code-Review P-14).
  FPullDiagnostics.RequestTimeout := CurrentRequestTimeout;
  FPullDiagnostics.Attach(FDispatcher);
  // Als anonyme Methode statt der Methode selbst: Free Pascal (Linux-Bau) bricht an der Zuweisung einer
  // Methode an eine Methodenreferenz intern ab.
  FSyntaxDiagnostics.OnPullChanged :=
    procedure
    begin
      FPullDiagnostics.Changed;
    end;
  // Neue Compilermeldungen (#1247): nur ihre Dateien neu prüfen, nicht alle Units.
  FSyntaxDiagnostics.OnPullFilesChanged :=
    procedure(AFiles: TArray<string>)
    begin
      FPullDiagnostics.FilesChanged(AFiles);
    end;
  // Nach dem Speichern prüft die Projektprüfung auch die Units, die die Datei in uses haben (#1247).
  FPullDiagnostics.Check.Dependents := DependentUnitsOf;
  FPullDiagnostics.Check.OnLog := LogInfo;
end;

procedure TServerComposition.SyntaxCheckFailed(AError: Exception);
begin
  FLogger.Error(Format('Fehler beim Prüfen der Syntax: %s: %s', [AError.ClassName, AError.Message]));
end;

function TServerComposition.DiagnosticsFileLabel(const AFileName: string): string;
begin
  Result := 'unit';
  if FDiagnostics <> nil then
  begin
    Result := FDiagnostics.FileLabel(AFileName);
  end;
end;

function TServerComposition.CurrentRequestTimeout: Cardinal;
begin
  Result := FRequestTimeout;
end;

function TServerComposition.DependentUnitsOf(const AFileName: string): TArray<string>;
begin
  Result := nil;
  if FIndex <> nil then
  begin
    Result := TLspWorkspaceCheck.DependentsOf(FIndex.Units, AFileName);
  end;
end;

procedure TServerComposition.LogInfo(const AMessage: string);
begin
  FLogger.Info(AMessage);
end;

procedure TServerComposition.WireEditing;
var
  mServices: TShellSlashServices;
begin
  WireEditors;
  mServices := Default(TShellSlashServices);
  mServices.Transport := FTransport;
  mServices.Logger := FLogger;
  mServices.Dispatcher := FDispatcher;
  mServices.WorkspaceOf := SlashWorkspaceOf;
  mServices.ReadText := ReadSourceText;
  // Die .dproj geht über das Plugin in die IDE, wenn der Client applyEdit kann (#397).
  mServices.ClientAppliesEdits :=
    function: Boolean
    begin
      Result := TLspApplyEdit.ClientSupports(FLifecycle.InitializeParams);
    end;
  // Neu laden nur im Thread der Nachrichtenschleife (Code-Review A-03); FConnection liest die Closure
  // erst beim Aufruf.
  mServices.RunInLoop :=
    procedure(const AWork: TProc)
    begin
      if (FConnection = nil) or not FConnection.Queue(AWork) then
      begin
        FLogger.Warning('Schnellbefehl: Projekt nicht neu geladen, die Verbindung ist beendet');
      end;
    end;
  mServices.SettingsFor := SettingsFor;
  mServices.WorkspaceSettingsOf := WorkspaceSettingsOf;
  mServices.TestUnitContextFor := TestUnitContextFor;
  mServices.RuleContextFor := RuleContextFor;
  mServices.UsesContextFor := UsesContextFor;
  FSlash := TShellSlash.Create(mServices);
  FEditing.UseSlashHost(FSlash.Host);
end;

procedure TServerComposition.WireEditors;
var
  mServices: TShellEditingServices;
begin
  mServices := Default(TShellEditingServices);
  mServices.Documents := FDocuments;
  mServices.FormatStyleFor := FormatStyleFor;
  mServices.ResolvedFormatStyleFor := ResolvedFormatStyleFor;
  mServices.SlashCommandsFor := SlashCommandsFor;
  mServices.LanguageLevelFor := LanguageLevelFor;
  mServices.DocCommentsFor := DocCommentsFor;
  mServices.ReadText := ReadSourceText;
  FEditing := TShellEditing.Create(mServices);
  FEditing.Attach(FDispatcher);
end;

function TServerComposition.SlashWorkspaceOf(const AUri: string): TShellWorkspace;
begin
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Result := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.WorkspaceSettingsOf(const AUri: string; out ASettings: TServerSettings): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := mWorkspace <> nil;
    if Result then
    begin
      ASettings := mWorkspace.Configuration.Settings;
    end
    else
    begin
      ASettings := Default(TServerSettings);
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.WorkspaceRegistryServices: TShellWorkspaceRegistryServices;
begin
  Result := Default(TShellWorkspaceRegistryServices);
  Result.Logger := FLogger;
  Result.SelectedProject :=
    function(const AOrigin: string): string
    begin
      Result := FProjectSelection.Project(AOrigin);
    end;
  Result.ActiveProject :=
    function: string
    begin
      Result := FIdeProject.ActiveProject;
    end;
  Result.ReadText := ReadSourceText;
end;

procedure TServerComposition.WireWorkspaces;
begin
  FWorkspaces := TShellWorkspaceRegistry.Create(WorkspaceRegistryServices);
  FLooseSettings := TServerSettings.Default;
  FIndexScheduler := TIndexScheduler.Create;
  FLooseConfiguration := TLspConfiguration.Create(FDocuments, FTransport,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end);
  FDocuments.Subscribe(HandleDocumentEvent);
  FDispatcher.RegisterNotification(TLspConfiguration.DidChangeConfigurationMethod, HandleDidChangeConfiguration);
  // Editor-Baum nur aus den aktiven Zweigen des Projekts (#845).
  TSyntaxTreeCache.SetDefinesProvider(DefinesFor);
  // $I-Dateien im Editor-Baum, in Syntaxprüfung und Abblenden (#264, #860): Suchpfade des Projekts.
  TSyntaxTreeCache.SetIncludeProvider(IncludeResolverFor);
end;

procedure TServerComposition.WireIndex;
var
  mIndex: ISymbolIndex;
begin
  FIndex := TSymbolIndex.Create;
  FUsesGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
  // Declared(X) in {$IF} fragt den Index (#847). Die Referenz hält den Index, bis Destroy den Anbieter abmeldet.
  mIndex := FIndex;
  TPascalPreprocessor.SetDeclaredProvider(
    function(const AName: string): Boolean
    var
      Location: TSymbolLocation;
    begin
      for Location in mIndex.FindSymbols(AName) do
      begin
        if Location.Symbol.Container = '' then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end);
  FEditing.UseIndex(FIndex);
  FEndReason := TDiagnosticEndReason.InputClosed;
  FRequestTimeout := RequestTimeoutMs;
  FDiagnostics := TShellDiagnostics.Create(TShellDiagnostics.DefaultFolder, IntToStr(TShellPlatform.CurrentProcessId),
    FDocuments, FIndex);
  FDiagnosticsRef := FDiagnostics;
  FDiagnostics.TimeoutMs := CurrentRequestTimeout;
  FDiagnostics.IndexLoading :=
    function: Integer
    begin
      Result := FWorkspaces.IndexLoading;
    end;
  FDispatcher.Observer := FDiagnosticsRef;
end;

procedure TServerComposition.WireNavigation;
var
  mServices: TShellNavigationServices;
begin
  mServices := Default(TShellNavigationServices);
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.ReadText := ReadSourceText;
  mServices.ProjectFiles := ProjectSourceFiles;
  mServices.EnsureUnit := EnsureUnit;
  mServices.DelphiVersionFor := DelphiVersionFor;
  mServices.HintSettingsFor := HintSettingsFor;
  mServices.RationaleOptionsFor := RationaleOptionsFor;
  mServices.ConditionalContextFor := ConditionalContextFor;
  mServices.HighlightSettingsFor := HighlightSettingsFor;
  mServices.CompilerSwitchContextFor := CompilerSwitchContextFor;
  mServices.ReferenceSettingsFor := ReferenceSettingsFor;
  FNavigation := TShellNavigation.Create(mServices);
  FNavigation.Attach(FDispatcher);
end;

function TServerComposition.HighlightSettingsFor(const AUri: string): THighlightSettings;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.Configuration.Settings.Highlight;
    end
    else
    begin
      Result := THighlightSettings.Default;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.WireCompletion;
var
  mServices: TShellCompletionServices;
begin
  mServices := Default(TShellCompletionServices);
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.EnsureUnit := EnsureUnit;
  mServices.ReadText := ReadSourceText;
  mServices.CompletionSettingsFor := CompletionSettingsFor;
  mServices.RefactoringSettingsFor := RefactoringSettingsFor;
  mServices.LanguageLevelFor := LanguageLevelFor;
  mServices.RefactoringContextFor :=
    function(const AUri: string): TRefactoringContext
    begin
      Result := FRefactorings.ContextFor(AUri);
    end;
  mServices.SlashCommandsFor := SlashCommandsFor;
  mServices.RuleIdsFor :=
    function(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean
    begin
      Result := FSlash.RuleIdsAt(AUri, AText, ALine, AIds);
    end;
  mServices.NamingFor := NamingPrefixFor;
  mServices.HintsFor := HintSettingsFor;
  mServices.DocCommentsFor := DocCommentsFor;
  mServices.SymbolsFor := ConditionalContextFor;
  mServices.Notify := NotifyClient;
  mServices.Log := LogDebug;
  FCompletion := TShellCompletion.Create(mServices);
  FCompletion.Attach(FDispatcher);
  // „Interface implementieren“ im Erzeugen-Menü (#719, #466) wie in der Vervollständigung.
  FEditing.UseCompletion(FCompletion.Completion);
end;

function TServerComposition.NamingPrefixFor(const AUri: string; AKind: TNamingKind): string;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
  mContext: TIdeProjectContext;
begin
  // Vorgabe der Projektdatei .atlas aus dem Projektkontext der IDE, sonst die Zählung im Index.
  mWorkspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
  if (mWorkspace <> nil) and mWorkspace.State.Project(mProject) and FIdeProject.Find(mProject.FileName, mContext) and
    mContext.HasNaming[AKind] then
  begin
    Exit(mContext.Naming[AKind]);
  end;
  Result := TLspCompletion.NamingPrefix(FIndex, AKind);
end;

procedure TServerComposition.WireAnalysis;
var
  mServices: TShellAnalysisServices;
begin
  mServices := Default(TShellAnalysisServices);
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.ReadText := ReadSourceText;
  mServices.ProjectFiles := ProjectSourceFiles;
  mServices.EnsureUnit := EnsureUnit;
  mServices.FormatRoutinesFor := FormatRoutinesFor;
  mServices.ReferenceSettingsFor := ReferenceSettingsFor;
  mServices.ImpactOptionsFor := ImpactOptionsFor;
  mServices.InlayHintSettingsFor := InlayHintSettingsFor;
  mServices.CodeLensMetricsFor := CodeLensMetricsFor;
  mServices.MetricsSourceFor := MetricsSourceFor;
  FAnalysis := TShellAnalysis.Create(mServices);
  FAnalysis.Attach(FDispatcher);
  FDispatcher.RegisterConcurrentRequest(TAffectedTests.Method, HandleAffectedTests);
  WireOverviews;
  WireBaselines;
end;

procedure TServerComposition.WireOverviews;
var
  mServices: TShellOverviewServices;
begin
  mServices := Default(TShellOverviewServices);
  mServices.Index := FIndex;
  mServices.ReadText := ReadSourceText;
  mServices.DefinesOf := DefinesOfFile;
  mServices.EnsureUnit := EnsureUnit;
  mServices.MetricsSourceFor := MetricsSourceFor;
  mServices.UsesContextFor := UsesContextFor;
  mServices.ArchitectureSourceFor := ArchitectureSourceFor;
  mServices.QuerySource := QuerySource;
  mServices.QuerySettingsFor := QuerySettingsFor;
  mServices.HotspotSourceFor := HotspotSourceFor;
  mServices.UnitRelationsOptionsFor := UnitRelationsOptionsFor;
  mServices.SymbolPathSourceFor := SymbolPathSourceFor;
  FOverviews := TShellOverviews.Create(mServices);
  FOverviews.Attach(FDispatcher);
end;

procedure TServerComposition.WireBaselines;
var
  mServices: TShellBaselineServices;
begin
  mServices := Default(TShellBaselineServices);
  mServices.MetricsSourceFor := MetricsSourceFor;
  mServices.ReadText := ReadSourceText;
  mServices.RuleContextFor := RuleContextFor;
  mServices.DefinesFor := DefinesFor;
  mServices.IncludeResolverFor := IncludeResolverFor;
  mServices.RefreshLater := RefreshDiagnosticsLater;
  mServices.Logger := FLogger;
  FBaselines := TShellBaselines.Create(mServices);
end;

procedure TServerComposition.RefreshDiagnosticsLater;
begin
  FSyntaxDiagnostics.RefreshLater;
end;

function TServerComposition.DefinesOfFile(const AFileName: string): TArray<string>;
begin
  if not DefinesFor(TDocumentUris.FromPath(AFileName), Result) then
  begin
    Result := nil;
  end;
end;

function TServerComposition.CodeLensMetricsFor(const AUri: string; out ALimits: TMetricLimits): Boolean;
var
  mSource: TLspMetricsSource;
begin
  if not MetricsSourceFor(TDocumentUris.ToPath(AUri), False, mSource) then
  begin
    mSource.Settings := TServerSettings.Default;
  end;
  ALimits := TMetricRules.Limits(mSource.Settings);
  Result := mSource.Settings.Metrics and mSource.Settings.CodeLens.Metrics;
end;

procedure TServerComposition.WireRefactorings;
var
  mServices: TShellRefactoringServices;
begin
  mServices := Default(TShellRefactoringServices);
  mServices.Logger := FLogger;
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.EnsureUnit := EnsureUnit;
  mServices.Namespaces :=
    function: TArray<string>
    begin
      Result := FNavigation.Namespaces;
    end;
  mServices.ProjectFiles := ProjectSourceFiles;
  mServices.ReadText := ReadSourceText;
  mServices.SettingsFor := RefactoringSettingsFor;
  mServices.FormatStyleFor := ResolvedFormatStyleFor;
  mServices.LanguageLevelFor := LanguageLevelFor;
  mServices.DelphiVersionFor := DelphiVersionFor;
  // Die Code-Aktionen entstehen erst in WireCodeActions: UsesContextFor liest sie beim Aufruf.
  mServices.UsesContextFor := UsesContextFor;
  mServices.MessagesFor :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompile.Results.MessagesFor(AFileName);
    end;
  mServices.ProjectFor := RefactoringProject;
  mServices.NewNamesFor := NewNamesFor;
  mServices.MissingUnitSetupFor := MissingUnitSetupFor;
  FRefactorings := TShellRefactorings.Create(mServices);
end;

procedure TServerComposition.WireCodeActions;
var
  mServices: TShellCodeActionServices;
begin
  WireTestUnits;
  mServices := Default(TShellCodeActionServices);
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.EnsureUnit := EnsureUnit;
  mServices.RuleContextFor := RuleContextFor;
  mServices.StringLiteralFor := StringLiteralFor;
  mServices.DocCommentsFor := DocCommentsFor;
  mServices.FormatStyleFor := ResolvedFormatStyleFor;
  mServices.RefactoringFor := RefactoringSettingsFor;
  mServices.DefinesFor := DefinesFor;
  mServices.ExtraActions := ExtraCodeActions;
  mServices.LanguageLevelFor := LanguageLevelFor;
  mServices.WorkspaceOf := CodeActionWorkspaceOf;
  mServices.SlashHost := FEditing.SlashHost;
  FCodeActions := TShellCodeActions.Create(mServices);
  FCodeActions.Attach(FDispatcher);
end;

procedure TServerComposition.WireTestUnits;
var
  mServices: TShellTestUnitServices;
begin
  mServices := Default(TShellTestUnitServices);
  mServices.Logger := FLogger;
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.ReadText := ReadSourceText;
  mServices.VisitWorkspaces := VisitWorkspaces;
  mServices.PickWorkspace :=
    function(const AFileName: string): TShellWorkspace
    begin
      Result := FWorkspaces.Pick(AFileName);
    end;
  FTestUnits := TShellTestUnits.Create(mServices);
end;

function TServerComposition.CodeActionWorkspaceOf(const AUri: string): TShellCodeActionWorkspace;
var
  mWorkspace: TShellWorkspace;
begin
  Result := Default(TShellCodeActionWorkspace);
  Result.MemberOrder := TMemberOrderSettings.Default;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    if mWorkspace <> nil then
    begin
      Result.Found := True;
      Result.MemberOrder := mWorkspace.Configuration.Settings.MemberOrder;
      Result.SortUses := mWorkspace.Configuration.Settings.SortUses;
      Result.SortUsesByNamespace := mWorkspace.Configuration.Settings.SortUsesByNamespace;
      Result.UsesKeep := mWorkspace.Configuration.Settings.UsesKeep;
      Result.Namespaces := mWorkspace.State.Namespaces;
      Result.IncludePaths := mWorkspace.State.IncludePaths;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.ExtraCodeActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := FTestUnits.Actions(AUri, ARange.StartPos.Line);
  Result := Result + FRefactorings.Actions(AUri, ARange);
end;

procedure TServerComposition.WireEditorCommands;
var
  mServices: TShellEditorCommandServices;
begin
  mServices := Default(TShellEditorCommandServices);
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.EnsureUnit := FEnsureUnitRef;
  mServices.ReadText := ReadSourceText;
  mServices.Namespaces :=
    function: TArray<string>
    begin
      Result := FNavigation.Namespaces;
    end;
  mServices.HighlightSettingsFor := HighlightSettingsFor;
  mServices.StringLiteralFor := StringLiteralFor;
  mServices.ResourceStringWrite := FSlash.ResourceStringWrite;
  FEditorCommands := TShellEditorCommands.Create(mServices);
end;

procedure TServerComposition.WireCommands;
begin
  // Methodenreferenz vorab: Free Pascal (Linux-Bau) bricht ab, wenn eine anonyme Methode die Methode selbst
  // als Referenz weitergibt.
  FEnsureUnitRef := EnsureUnit;
  FCommands := TLspCommands.Create;
  WireStatus;
  WireServerCommands;
  FServerCommands.RegisterConvertCommand(FCommands);
  FCommands.Register(TLspDfmPropertyRules.Command, ApplyDfmPropertyRules);
  FRefactorings.Register(FCommands);
  WireReportCommands;
  FOverviews.RegisterUnitCommands(FCommands);
  WireEditorCommands;
  FEditorCommands.RegisterMarkCommands(FCommands);
  FBaselines.RegisterCommands(FCommands);
  WireSlashCommands;
  FEditorCommands.RegisterTextCommands(FCommands);
  // Reine Lesebefehle laufen nebenläufig (#874), auch der Fehlerbericht und das Diagnosepaket.
  FServerCommands.RegisterReadCommands(FCommands);
  FStatusReports.RegisterCommands(FCommands);
  FServerCommands.RegisterActionCommands(FCommands);
  FCommands.Attach(FDispatcher);
end;

procedure TServerComposition.WireReportCommands;
begin
  FAnalysis.RegisterReportCommands(FCommands);
  FOverviews.RegisterReportCommands(FCommands);
end;

procedure TServerComposition.WireSlashCommands;
begin
  FBaselines.RegisterClassifyCommand(FCommands);
  FEditing.RegisterCommands(FCommands);
  FTestUnits.RegisterCommand(FCommands);
  WireUnitSearch;
  FUnitSearch.RegisterCommands(FCommands);
end;

procedure TServerComposition.WireUnitSearch;
var
  mServices: TShellUnitSearchServices;
begin
  mServices := Default(TShellUnitSearchServices);
  mServices.Logger := FLogger;
  mServices.Index := FIndex;
  mServices.VisitWorkspaces := VisitWorkspaces;
  mServices.ReadText := ReadSourceText;
  mServices.UsesContextFor := UsesContextFor;
  mServices.Process :=
    function: ICompilerProcess
    begin
      Result := FCompilerProcess;
    end;
  FUnitSearch := TShellUnitSearch.Create(mServices);
end;

procedure TServerComposition.WireServerCommands;
var
  mServices: TShellServerCommandServices;
begin
  mServices := Default(TShellServerCommandServices);
  mServices.Logger := FLogger;
  mServices.Status :=
    function(AAnonymize: Boolean): TJSONObject
    begin
      Result := FStatusReports.StatusJson(AAnonymize);
    end;
  mServices.GlobalSettingsFile :=
    function: string
    begin
      Result := FGlobalSettingsFile;
    end;
  mServices.ProjectSourceFiles := ProjectSourceFiles;
  mServices.Compile :=
    function(const AFileName: string; out AChoice: TCompilerBackendChoice): Boolean
    begin
      Result := FCompile.Start(AFileName, True, AChoice);
    end;
  mServices.Workspaces := CommandWorkspaces;
  mServices.IsSelectedProject :=
    function(AWorkspace: TShellWorkspace): Boolean
    begin
      Result := FWorkspaces.IsSelected(AWorkspace);
    end;
  mServices.ActiveProject :=
    function: string
    begin
      Result := FIdeProject.ActiveProject;
    end;
  mServices.SetProject :=
    procedure(const AScope, AProject: string)
    begin
      FProjectSelection.SetProject(AScope, AProject);
    end;
  mServices.RetryCrashCase :=
    function(const AUri: string): Integer
    begin
      Result := FCrashCases.Retry(AUri);
    end;
  mServices.Recheck :=
    procedure
    begin
      FPullDiagnostics.Changed;
    end;
  FServerCommands := TShellServerCommands.Create(mServices);
end;

procedure TServerComposition.WireStatus;
var
  mServices: TShellStatusServices;
begin
  mServices := Default(TShellStatusServices);
  mServices.Logger := FLogger;
  mServices.Index := FIndex;
  mServices.Documents := FDocuments;
  mServices.Statistics := FStatistics;
  mServices.VisitWorkspaces := VisitWorkspaces;
  mServices.EditorSettings :=
    function: string
    begin
      System.TMonitor.Enter(FWorkspaces.Lock);
      try
        Result := FEditorSettings;
      finally
        System.TMonitor.Exit(FWorkspaces.Lock);
      end;
    end;
  mServices.ActiveProject :=
    function: string
    begin
      Result := FIdeProject.ActiveProject;
    end;
  mServices.IsSelectedProject :=
    function(AWorkspace: TShellWorkspace): Boolean
    begin
      Result := FWorkspaces.IsSelected(AWorkspace);
    end;
  // Protokoll, Mitschnitt und Anonymisierung setzt CreateForStdio erst nach Create.
  mServices.RecentLog :=
    function: IRecentLogLines
    begin
      Result := FRecentLog;
    end;
  mServices.Tracing :=
    function: TJsonRpcTracingTransport
    begin
      Result := FTracing;
    end;
  mServices.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := FLogAnonymizer;
    end;
  WireStatusStates(mServices);
  FStatusReports := TShellStatusReports.Create(mServices);
end;

procedure TServerComposition.WireStatusStates(var AServices: TShellStatusServices);
begin
  AServices.CompilerStatus :=
    procedure(var AStatus: TServerStatus)
    begin
      FCompile.StatusOf(AStatus);
    end;
  AServices.CheckStatus :=
    procedure(var AStatus: TServerStatus; out AQueue: TWorkspaceCheckQueue)
    begin
      AQueue := Default(TWorkspaceCheckQueue);
      if FPullDiagnostics <> nil then
      begin
        AStatus.CheckRun := FPullDiagnostics.Check.Profile(TCheckRunProfile.cTop);
        AQueue := FPullDiagnostics.Check.Queue;
      end;
    end;
  AServices.IndexQueue :=
    function: TIndexSchedulerQueue
    begin
      Result := FIndexScheduler.Queue;
    end;
end;

procedure TServerComposition.VisitWorkspaces(const AVisit: TShellWorkspacesProc);
begin
  FWorkspaces.Visit(AVisit);
end;

function TServerComposition.CommandWorkspaces(const AUri: string): TArray<TShellWorkspace>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    if AUri = '' then
    begin
      Result := FWorkspaces.Items.ToArray;
    end
    else
    begin
      mWorkspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
      if mWorkspace <> nil then
      begin
        Result := [mWorkspace];
      end;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.WireWatchedFiles;
begin
  FWatchedFiles := TLspWatchedFiles.Create(FTransport);
  FWatchedFiles.OnChanged := HandleWatchedFiles;
  FUsesChanges := TLspUsesChanges.Create;
  FIndexRefresh := TLspIndexRefresh.Create(TLspIndexRefresh.DefaultDelayMs,
    procedure(const AFileName, AText: string)
    var
      Workspace: TShellWorkspace;
      Targets: TArray<TShellWorkspace>;
      Updated: Boolean;
    begin
      Updated := False;
      TMonitor.Enter(FWorkspaces.Lock);
      try
        Targets := FWorkspaces.Items.ToArray;
      finally
        TMonitor.Exit(FWorkspaces.Lock);
      end;
      for Workspace in Targets do
      begin
        if Workspace.ApplyText(AFileName, AText) then
        begin
          Updated := True;
        end;
      end;
      if Updated then
      begin
        FLogger.Debug(Format('Index nach Tipp-Pause aktualisiert: %s', [ExtractFileName(AFileName)]));
      end;
      // Geänderte uses (#896): Ein Unit-Zyklus anderer offener Units kann über diese Unit laufen; der Graph
      // folgt dem Index, die Neuprüfung ist gebündelt.
      if Updated and FUsesChanges.Changed(AFileName, AText) and (FSyntaxDiagnostics <> nil) then
      begin
        FSyntaxDiagnostics.RefreshLater;
      end;
    end);
  FIndexRefresh.OnError :=
    procedure(E: Exception)
    begin
      FLogger.Warning('Index nach Tipp-Pause: ' + E.Message);
    end;
  FWatchedFiles.Attach(FDispatcher);
end;

procedure TServerComposition.WireIde;
begin
  // Compilermeldungen aus dem Meldungsfenster der IDE ersetzen die des letzten Laufs wie ein eigener Compile (#528).
  FIdeBuild := TLspIdeBuild.Create;
  FIdeBuild.OnMessages := IdeMessagesReceived;
  // Letzten Build für den MCP-Prozess ablegen (#556): je Arbeitsordner eine Datei im Atlas-Cache.
  FIdeBuild.OnChanged := IdeBuildChanged;
  // Während die IDE kompiliert, ruht die Projektprüfung (#1247). Die Frist ist ein Sicherheitsnetz für ein
  // verlorenes Ende, keine Steuerung.
  FIdeBuild.OnCompiling := IdeCompiling;
  FIdeBuild.Attach(FDispatcher);
  // Projektwahl je Benutzer über Neustarts (#46).
  FProjectSelection := TProjectSelection.Create(TPath.Combine(TIndexCacheDirectory.DefaultRoot,
    'projektauswahl.json'));
  // Konfiguration, Plattform und Optionen aus der IDE (#396): betroffene Projekte neu laden.
  FIdeProject := TLspIdeProject.Create;
  FIdeProject.OnChanged := IdeProjectChanged;
  // Neue Präfixe aus .atlas (#1111): naming-prefix und shadowed-name prüfen neu, das Projekt bleibt geladen.
  FIdeProject.OnNamingChanged := IdeNamingChanged;
  FIdeProject.Attach(FDispatcher);
end;

procedure TServerComposition.WireWorkspaceFolders;
begin
  FWorkspaceFolders := TLspWorkspaceFolders.Create;
  FWorkspaceFolders.OnChanged := WorkspaceFoldersChanged;
  FWorkspaceFolders.Attach(FDispatcher);
  FLifecycle.OnInitialized := ClientInitialized;
end;

procedure TServerComposition.IdeMessagesReceived(const AMessages: TArray<TCompilerMessage>);
begin
  FSyntaxDiagnostics.RefreshFiles(FCompile.Results.Replace(AMessages));
  FLogger.Info(Format('Compilermeldungen aus der IDE: %d', [Length(AMessages)]));
end;

function TServerComposition.BuildRootOf(const AProject: string): string;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(AProject);
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.Root;
    end
    else
    begin
      Result := ExtractFileDir(AProject);
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.IdeBuildChanged(const ABuild: TIdeBuild);
var
  mRoot: string;
begin
  // Letzten Build für den MCP-Prozess ablegen (#556): je Arbeitsordner eine Datei im Atlas-Cache.
  mRoot := BuildRootOf(ABuild.Project);
  if mRoot = '' then
  begin
    Exit;
  end;
  try
    ForceDirectories(TIndexCacheDirectory.DefaultRoot);
    TFile.WriteAllText(TIndexCacheDirectory.BuildFileFor(TIndexCacheDirectory.DefaultRoot, mRoot),
      TMcpBuildTools.ToFileText(ABuild), TEncoding.UTF8);
  except
    on E: Exception do
      FLogger.Warning(Format('Letzter Build nicht gespeichert: %s', [E.Message]));
  end;
end;

procedure TServerComposition.IdeCompiling(ARunning: Boolean);
begin
  // Die Frist ist ein Sicherheitsnetz für ein verlorenes Ende, keine Steuerung.
  FPullDiagnostics.Check.Pause(TLspWorkspaceCheck.cPauseCompile, ARunning, CompilePauseLimitMs);
end;

function TServerComposition.WorkspacesOfProject(const AProject: string): TArray<TShellWorkspace>;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
begin
  Result := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    for mWorkspace in FWorkspaces.Items do
    begin
      if SameText(mWorkspace.Setup.ProjectFile, AProject) or
        (mWorkspace.State.Project(mProject) and SameText(mProject.FileName, AProject)) then
      begin
        Result := Result + [mWorkspace];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.IdeProjectChanged(const AContext: TIdeProjectContext);
var
  mWorkspace: TShellWorkspace;
begin
  FLogger.Info(Format('Projektkontext aus der IDE: %s (%s, %s)',
    [ExtractFileName(AContext.Project), AContext.Configuration, AContext.Platform]));
  for mWorkspace in WorkspacesOfProject(AContext.Project) do
  begin
    mWorkspace.Reload;
  end;
end;

procedure TServerComposition.IdeNamingChanged(const AContext: TIdeProjectContext);
begin
  FSyntaxDiagnostics.RefreshLater;
end;

procedure TServerComposition.WorkspaceFoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
var
  mFolder: TWorkspaceFolder;
begin
  for mFolder in ARemoved do
  begin
    RemoveWorkspace(mFolder);
  end;
  for mFolder in AAdded do
  begin
    AddWorkspace(mFolder);
  end;
end;

procedure TServerComposition.ClientInitialized;
var
  mFolders: TArray<TWorkspaceFolder>;
  mFolder: TWorkspaceFolder;
begin
  WatchParent(FLifecycle.InitializeParams);
  ApplyClientInfo(FLifecycle.InitializeParams);
  mFolders := TLspWorkspaceFolders.FromInitialize(FLifecycle.InitializeParams);
  // Vor dem ersten Laden, damit die Projekte nicht zweimal indiziert werden (#396).
  FIdeProject.LoadInitialize(FLifecycle.InitializeParams);
  // Meldet der Client nur Projektdateien (IDE-Plugin, #648), bekommen Dateien außerhalb dieser
  // Projekte weiter einen abgeleiteten Arbeitsbereich.
  FDeriveWorkspaces := True;
  for mFolder in mFolders do
  begin
    if mFolder.ProjectFile = '' then
    begin
      FDeriveWorkspaces := False;
    end;
  end;
  if Length(mFolders) = 0 then
  begin
    FLogger.Info('Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet');
  end;
  StartSettingsWatch;
  for mFolder in mFolders do
  begin
    AddWorkspace(mFolder);
  end;
  UpdateWatchedSettings;
  FWatchedFiles.RegisterWatchers(FLifecycle.InitializeParams);
end;

procedure TServerComposition.ApplyClientInfo(const AParams: TJSONObject);
begin
  if AParams <> nil then
  begin
    // Name des Clients für die Anmeldung am Index-Cache (#62); vor dem Anlegen der Arbeitsbereiche.
    FClientName := AParams.GetValue<string>('clientInfo.name', '');
    // Absturzfälle nennen den Client (#1355).
    FCrashCases.Client := Trim(FClientName + ' ' + AParams.GetValue<string>('clientInfo.version', ''));
  end;
  // Der neue Client erfährt, was nach Abstürzen übersprungen wird.
  FCrashCases.Announce;
  // Editor-Ebene: initializationOptions.settings.atlas wie bei didChangeConfiguration, schon vor dem
  // ersten Indexaufbau; sie zählt wie global (TConfigurationScopes). Das IDE-Plugin schickt keine
  // Einstellungen mehr: Es schreibt settings.json, die der Server selbst liest und beobachtet.
  if AParams <> nil then
  begin
    SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams.GetValue('initializationOptions')));
  end;
  UpdateLooseSettings;
  FNavigation.Hover.Markdown := TLspHover.ClientSupportsMarkdown(AParams);
  // Code-Vorlagen mit Platzhaltern nur an Clients mit snippetSupport (#51).
  FCompletion.Completion.SnippetSupport := TLspCompletion.ClientSupportsSnippets(AParams);
  FCompletion.Completion.DocumentationMarkdown := TLspCompletion.ClientPrefersMarkdown(AParams);
end;

procedure TServerComposition.StartSettingsWatch;
begin
  // Globale Benutzerdatei (#227) vor dem ersten Ordner; der Server beobachtet sie und die atlas.json
  // selbst, weil die RAD-Studio-IDE keine Dateiänderungen meldet.
  if FReplay then
  begin
    FGlobalSettingsFile := FReplaySettingsFile;
  end
  else
  begin
    FGlobalSettingsFile := GlobalSettingsPath;
  end;
  LoadGlobalSettings;
  FFileWatcher := TFileWatcher.Create(FilesChangedOnDisk);
end;

procedure TServerComposition.FilesChangedOnDisk(const AFiles: TArray<string>);
begin
  // Im Thread der Nachrichtenschleife verarbeiten wie eine Meldung des Clients.
  FConnection.Post(TLspWatchedFiles.Notification(AFiles));
end;

destructor TServerComposition.Destroy;
var
  Unfinished: Boolean;
begin
  TPascalPreprocessor.SetDeclaredProvider(nil);
  // Zuerst: Eine laufende Übernahme greift auf die Ordner zu.
  FreeAndNil(FIndexRefresh);
  FreeAndNil(FUsesChanges);
  // Vor der Verbindung: Beide Wächter rufen FConnection.
  FreeAndNil(FFileWatcher);
  FreeAndNil(FParentWatcher);
  // Code-Review A-06: Liefen beim Ende noch Handler, die ihr Abbruchsignal nicht prüfen, nutzen sie
  // Features und Ordner weiter.
  Unfinished := (FConnection <> nil) and FConnection.UnfinishedWork;
  FreeAndNil(FConnection);
  if FDispatcher <> nil then
  begin
    FDispatcher.Watchdog := nil;
  end;
  // Compiler und Index-Threads anhalten, solange Diagnoselog und Syntaxprüfung noch leben (Code-Review A-05):
  // Ein abgebrochener Aufbau meldet sich über OnIndexEvent im Diagnoselog, ein Compilerlauf über die
  // Syntaxprüfung.
  if FCompile <> nil then
  begin
    FCompile.Stop;
  end;
  StopIndexThreads;
  // Der Baum-Cache ist global; ohne Projekte gelten wieder die Vordefinitionen (#845).
  TSyntaxTreeCache.SetDefinesProvider(nil);
  TSyntaxTreeCache.SetIncludeProvider(nil);
  // Erst jetzt meldet sich niemand mehr beim Diagnoselog.
  if FDispatcher <> nil then
  begin
    FDispatcher.Observer := nil;
  end;
  FDiagnostics := nil;
  FDiagnosticsRef := nil;
  if Unfinished then
  begin
    // Der Prozess endet gleich: Speicher stehen lassen, statt ihn unter einem laufenden Handler freizugeben.
    FLogger.Warning('Beim Beenden liefen noch Anfragen; ihre Objekte werden nicht freigegeben');
  end
  else
  begin
    FreeFeatures;
  end;
  if FTracing <> nil then
  begin
    FTracing.OnFailed := nil;
  end;
  // Statusdatei für get_server_status (#1356) gehört nur dem laufenden Server.
  TServerStatusFile.Delete(TIndexCacheDirectory.DefaultRoot, TShellPlatform.CurrentProcessId);
  FTransport := nil;
  FLogger := nil;
  inherited;
end;

procedure TServerComposition.StopIndexThreads;
var
  Workspace: TShellWorkspace;
begin
  if FWorkspaces = nil then
  begin
    Exit;
  end;
  for Workspace in FWorkspaces.Items do
  begin
    Workspace.Stop;
  end;
end;

procedure TServerComposition.FreeFeatures;
begin
  // Vor den Ordnern: der Hintergrund-Thread der Syntaxprüfung fragt ihre Symbole ab.
  FPullDiagnostics.Free;
  FSyntaxDiagnostics.Free;
  // Ordner vor dem Index: ihre Index-Threads laufen noch.
  FWorkspaces.FreeWorkspaces;
  // Nach den Ordnern: Ihre Index-Threads melden Projektstufe und Ende.
  FIndexRecheck.Free;
  FWorkspaces.Free;
  // Nach den Ordnern: Ihre Index-Threads sind beendet und abgemeldet.
  FIndexScheduler.Free;
  FLooseConfiguration.Free;
  FWorkspaceFolders.Free;
  FreeAndNil(FUsesGraph);
  FIndex := nil;
  // Danach die Features in umgekehrter Reihenfolge ihrer Gruppen; Protokoll und Absturzfälle zuletzt.
  FreeEditorFeatures;
  FreeAnalysisFeatures;
  FreeCodeFeatures;
end;

procedure TServerComposition.FreeEditorFeatures;
begin
  FreeAndNil(FEditing);
end;

procedure TServerComposition.FreeAnalysisFeatures;
begin
  FreeAndNil(FAnalysis);
  FreeAndNil(FOverviews);
  FreeAndNil(FBaselines);
end;

procedure TServerComposition.FreeCodeFeatures;
begin
  FreeAndNil(FCompletion);
  FreeAndNil(FRefactorings);
  FreeAndNil(FEditorCommands);
  FreeAndNil(FServerCommands);
  FreeAndNil(FStatusReports);
  FreeAndNil(FNavigation);
  FreeAndNil(FCodeActions);
  FreeAndNil(FTestUnits);
  FreeAndNil(FUnitSearch);
  FreeAndNil(FCommands);
  // Nach allen Nutzern des Hosts der Schnellbefehle: Er ruft dessen Methoden.
  FreeAndNil(FSlash);
  FreeAndNil(FCompile);
  FCompilerProcess := nil;
  FreeAndNil(FWatchedFiles);
  FreeAndNil(FIdeBuild);
  FreeAndNil(FIdeProject);
  FreeAndNil(FProjectSelection);
  FreeAndNil(FTextDocumentSync);
  // Nach der Verbindung und dem Watchdog: Niemand meldet mehr einen Absturz.
  FreeAndNil(FCrashCases);
  FDocuments := nil;
  FreeAndNil(FLifecycle);
  FreeAndNil(FDispatcher);
end;

function TServerComposition.ProjectsOf(const AFolder: TWorkspaceFolder): TArray<string>;
var
  GroupFile: string;
  Groups: TArray<string>;
begin
  Result := nil;
  if SameText(ExtractFileExt(AFolder.ProjectFile), '.dproj') then
  begin
    Result := [AFolder.ProjectFile];
    Exit;
  end;
  GroupFile := '';
  if SameText(ExtractFileExt(AFolder.ProjectFile), '.groupproj') then
  begin
    GroupFile := AFolder.ProjectFile;
  end
  else
    try
      // Genau eine .dproj im Ordner: wie bisher dieses Projekt (oder "project" aus atlas.json).
      if Length(TDirectory.GetFiles(AFolder.Path, '*.dproj')) <> 1 then
      begin
        Groups := TDirectory.GetFiles(AFolder.Path, '*.groupproj');
        if Length(Groups) = 1 then
        begin
          GroupFile := Groups[0];
        end;
      end;
    except
      // Nicht lesbare Ordner haben keine Gruppe.
      on Exception do
        GroupFile := '';
    end;
  if GroupFile <> '' then
  begin
    Result := TShellBootstrap.LoadGroup(GroupFile, FLogger);
  end;
end;

procedure TServerComposition.AddWorkspace(const AFolder: TWorkspaceFolder);
var
  Projects: TArray<string>;
  mIndex: Integer;
  HasOthers: Boolean;
begin
  Projects := ProjectsOf(AFolder);
  if Length(Projects) = 0 then
  begin
    AddProjectWorkspace(AFolder.Path, AFolder.Name, '', AFolder.Key, False);
    Exit;
  end;
  // Projektgruppe (#648): Das erste Projekt ist das aktive (das Plugin meldet es zuerst). Die übrigen
  // warten mit index.projectGroup = false, bis eine ihrer Dateien geöffnet wird.
  HasOthers := FWorkspaces.AddGroupProjects(Projects);
  for mIndex := 0 to High(Projects) do
  begin
    AddProjectWorkspace(ExtractFileDir(Projects[mIndex]), ChangeFileExt(ExtractFileName(Projects[mIndex]), ''),
      Projects[mIndex], AFolder.Key, HasOthers or (mIndex > 0));
  end;
end;

procedure TServerComposition.AddProjectWorkspace(const ARoot, AName, AProjectFile, AOrigin: string;
  ADeferred: Boolean);
var
  mWorkspace: TShellWorkspace;
begin
  if (AProjectFile <> '') and FWorkspaces.HasProject(AProjectFile) then
  begin
    Exit;
  end;
  if FLogAnonymizer <> nil then
  begin
    FLogAnonymizer.AddNames([AName, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)),
      ChangeFileExt(ExtractFileName(AProjectFile), '')]);
  end;
  mWorkspace := NewWorkspace(ARoot, AName, AProjectFile, AOrigin, ADeferred);
  WireWorkspaceEvents(mWorkspace);
  mWorkspace.Configuration.SetGlobalSettings(FGlobalSettings);
  mWorkspace.Configuration.SetEditorSettings(FEditorSettings);
  FWorkspaces.Add(mWorkspace);
  UpdateWatchedSettings;
  if AProjectFile <> '' then
  begin
    FLogger.Info('Arbeitsbereich für Projekt: ' + AProjectFile);
  end
  else
  begin
    FLogger.Info('Arbeitsbereichsordner: ' + ARoot);
  end;
  mWorkspace.Load;
end;

function TServerComposition.NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string;
  ADeferred: Boolean): TShellWorkspace;
var
  mIdentity: TIndexProcessInfo;
begin
  Inc(FWorkspaceCounter);
  Result := TShellWorkspace.Create(ARoot, AName, TShellWorkspaceServices.Create(FDocuments, FTransport, FLogger,
    FIndex, Format('atlas-index-%d', [FWorkspaceCounter])));
  Result.Setup.ProjectFile := AProjectFile;
  Result.Setup.Priority := FWorkspacePriority;
  Inc(FWorkspacePriority);
  Result.Setup.Scheduler := FIndexScheduler;
  Result.Setup.Deferred := ADeferred;
  Result.Setup.IdeProjects := FIdeProject;
  Result.Setup.Origin := AOrigin;
  Result.Setup.Selection := FProjectSelection;
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62).
  mIdentity := Default(TIndexProcessInfo);
  mIdentity.Pid := TShellPlatform.CurrentProcessId;
  mIdentity.Kind := TIndexProcessInfo.KindLsp;
  mIdentity.Client := FClientName;
  Result.Setup.ProcessIdentity := mIdentity;
  // Ordner entstehen in der Nachrichtenschleife (initialized, didChangeWorkspaceFolders, didOpen):
  // Reload ist nur dort erlaubt (Code-Review A-03).
  Result.Setup.LoopThreadId := TThread.Current.ThreadID;
end;

procedure TServerComposition.WireWorkspaceEvents(AWorkspace: TShellWorkspace);
begin
  // uses-unit-not-found: Was ein Projekt der Gruppe in einen Suchpfad übersetzt, gibt es beim Bau der Gruppe.
  AWorkspace.Setup.OnGroupProjects :=
    function: TArray<string>
    begin
      Result := FWorkspaces.GroupProjectFiles;
    end;
  // requires-Packages als Quelle zuerst bei den Projekten der Gruppe suchen (#46).
  AWorkspace.Setup.OnPackageFolders :=
    function: TArray<string>
    begin
      Result := FWorkspaces.PackageFolders;
    end;
  AWorkspace.Events.OnProjectLoaded := ProjectLoaded;
  AWorkspace.Events.OnIndexFinished := IndexFinished;
  AWorkspace.Events.OnProjectReady := ProjectReady;
  // Projekt- und Unit-Namen erscheinen im Server-Log nicht im Klartext (#647).
  AWorkspace.Events.OnNames := AddLogNames;
  AWorkspace.Events.OnIndexEvent := LogIndexEvent;
  // Das Zeitlimit gilt serverweit; bei mehreren Ordnern das zuletzt gelesene.
  AWorkspace.Events.OnSettingsChanged := WorkspaceSettingsChanged;
  // Eigenschaftsregeln mit unbekannter Klasse oder Property (#309): erst mit fertigem Index, sonst
  // fehlten die Klassen nur, weil sie noch nicht gelesen sind; IndexFinished prüft dann neu.
  AWorkspace.Configuration.ExtraIssues := ConfigurationExtraIssues;
end;

procedure TServerComposition.AddLogNames(ANames: TArray<string>);
begin
  if FLogAnonymizer <> nil then
  begin
    FLogAnonymizer.AddNames(ANames);
  end;
end;

procedure TServerComposition.LogIndexEvent(AText: string);
begin
  // Absicherung: Beim Beenden ist das Diagnoselog schon fort (Code-Review A-05).
  if FDiagnostics <> nil then
  begin
    FDiagnostics.Log.LogEvent(AText);
  end;
end;

procedure TServerComposition.WorkspaceSettingsChanged(ASettings: TServerSettings);
begin
  FDispatcher.Watchdog.SetTimeout(ASettings.RequestTimeoutMs);
  FRequestTimeout := ASettings.RequestTimeoutMs;
  FDiagnostics.ApplySettings(ASettings);
  // server.crashCases und server.crashSkip (#1355) gelten serverweit; beim Nachstellen bleiben beide aus.
  if not FReplay then
  begin
    FCrashCases.Enabled := ASettings.ServerCrashCases;
    FCrashCases.SkipEnabled := ASettings.ServerCrashSkip;
  end;
end;

function TServerComposition.ConfigurationExtraIssues(const ASettings: TServerSettings): TArray<TConfigurationIssue>;
begin
  // Gespeicherte Abfragen mit Fehler (#1351) an der Stelle in atlas.json, unabhängig vom Index.
  Result := TQueryParser.ConfigurationIssues(ASettings.Queries);
  if (Length(ASettings.DfmPropertyRules) = 0) or FWorkspaces.ProjectIndexPending or (Length(FIndex.Units) = 0) then
  begin
    Exit;
  end;
  Result := Result + TDfmPropertyCheckRule.ConfigurationIssues(ASettings.DfmPropertyRules, FIndex, ReadSourceBytes);
end;

function TServerComposition.ReadSourceBytes(const AFileName: string; out AData: TBytes): Boolean;
var
  mText: string;
begin
  Result := ReadSourceText(AFileName, mText);
  if Result then
  begin
    AData := TEncoding.UTF8.GetBytes(mText);
  end;
end;

// Gehört AFileName zu AWorkspace? Mit fester Projektdatei nur die Projekt- und Suchpfad-Units,
// sonst alles unter dem Ordner.
function OwnsFile(AWorkspace: TShellWorkspace; const AFileName: string): Boolean;
begin
  Result := AWorkspace.State.ContainsFile(AFileName);
  if not Result and (AWorkspace.Setup.ProjectFile = '') then
  begin
    Result := TLspWorkspaceFolders.FolderOf([TWorkspaceFolder.Create(AWorkspace.Root, '')], AFileName) = 0;
  end;
end;

/// <summary>Gehört AFileName zu einem der Arbeitsbereiche AWorkspaces?</summary>
function OwnedByAny(const AWorkspaces: TArray<TShellWorkspace>; const AFileName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  Result := False;
  for mWorkspace in AWorkspaces do
  begin
    if OwnsFile(mWorkspace, AFileName) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TServerComposition.RemoveWorkspace(const AFolder: TWorkspaceFolder);
var
  mRemoved: TArray<TShellWorkspace>;
  mRemaining: TArray<TShellWorkspace>;
  mWorkspace: TShellWorkspace;
begin
  // Ein Eintrag (Ordner, .dproj oder .groupproj) kann mehrere Arbeitsbereiche erzeugt haben (#648).
  mRemoved := FWorkspaces.Extract(AFolder.Key, mRemaining);
  if Length(mRemoved) = 0 then
  begin
    Exit;
  end;
  FLogger.Info(Format('Arbeitsbereich entfernt: %s (%d Projekte)', [AFolder.Path, Length(mRemoved)]));
  for mWorkspace in mRemoved do
  begin
    mWorkspace.Stop;
  end;
  RemoveOwnedUnits(mRemoved, mRemaining);
  for mWorkspace in mRemoved do
  begin
    FWorkspaces.FreeWhenUnused(mWorkspace);
  end;
  UpdateWatchedSettings;
  ProjectLoaded;
end;

procedure TServerComposition.RemoveOwnedUnits(const ARemoved, ARemaining: TArray<TShellWorkspace>);
var
  mUnit: TUnitIndex;
begin
  // Units der entfernten Projekte verlassen den Index, sofern kein verbleibendes Projekt sie enthält;
  // geteilte Bibliotheks-Units bleiben.
  for mUnit in FIndex.Units do
  begin
    if not mUnit.Library_ and OwnedByAny(ARemoved, mUnit.FileName) and not OwnedByAny(ARemaining, mUnit.FileName) then
    begin
      FIndex.RemoveFile(mUnit.FileName);
    end;
  end;
end;

function HasProjectFile(const AFolder: string): Boolean;
begin
  try
    Result := (Length(TDirectory.GetFiles(AFolder, '*.dproj')) > 0) or
      (Length(TDirectory.GetFiles(AFolder, '*.groupproj')) > 0);
  except
    // Ungültige oder nicht lesbare Ordner zählen als ohne Projekt.
    on Exception do
      Result := False;
  end;
end;

procedure TServerComposition.DeriveWorkspace(const AFileName: string);
var
  Known: Boolean;
  Folder: string;
begin
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Known := FWorkspaces.WorkspaceOf(AFileName) <> nil;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  if Known then
  begin
    Exit;
  end;
  Folder := TLspWorkspaceFolders.ProjectFolderFor(AFileName, HasProjectFile);
  if Folder <> '' then
  begin
    AddWorkspace(TWorkspaceFolder.Create(Folder, ExtractFileName(Folder)));
  end;
end;

function TServerComposition.SettingsFor(const AUri: string): TServerSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    if Workspace = nil then
    begin
      Result := FLooseSettings;
    end
    else
    begin
      Result := Workspace.Configuration.Settings;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.SetEditorSettings(const AText: string);
begin
  TMonitor.Enter(FWorkspaces.Lock);
  try
    FEditorSettings := AText;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.UpdateLooseSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := TConfigurationParser.Parse(TConfigurationScopes.Effective(FGlobalSettings, FEditorSettings, ''), Issues);
  TMonitor.Enter(FWorkspaces.Lock);
  try
    FLooseSettings := Settings;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.EnsureUnit(const AUnitName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
begin
  // Anfrage-Threads: jeder Ordner versucht es mit seinen Suchpfaden. Das Parsen läuft außerhalb von
  // FWorkspaces.Lock (#647): Sonst warteten alle Anfragen, die nur kurz einen Arbeitsbereich suchen
  // (Defines, Einstellungen, Diagnoselog), auf das Parsen einer Unit, und Hover dauerte Minuten.
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mTargets := FWorkspaces.Items.ToArray;
    FWorkspaces.Hold(mTargets);
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  try
    Result := False;
    for mWorkspace in mTargets do
    begin
      // Abgebrochene Anfrage (Watchdog, $/cancelRequest): keine weitere Unit parsen (Code-Review A-06).
      TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
      if mWorkspace.EnsureUnit(AUnitName) then
      begin
        Exit(True);
      end;
    end;
  finally
    FWorkspaces.Release(mTargets);
  end;
end;

procedure TServerComposition.IndexFinished;
begin
  IndexStageDone(False);
end;

procedure TServerComposition.ProjectReady;
begin
  IndexStageDone(True);
end;

procedure TServerComposition.IndexStageDone(AProjectStage: Boolean);
var
  UnitIndex: TUnitIndex;
begin
  // Units aus Suchpfaden stehen in keiner .dproj; im Server-Log ebenfalls verbergen (#647).
  if FLogAnonymizer <> nil then
  begin
    for UnitIndex in FIndex.Units do
    begin
      FLogAnonymizer.AddUnit(UnitIndex.UnitName, UnitIndex.FileName);
    end;
  end;
  // Befunde aus der Zeit des Aufbaus enthalten Units, die damals noch fehlten. Im Pull-Modus steigt
  // damit die Generation: Der Client holt geöffnete Dateien neu, workspace/diagnostic prüft alle.
  // Gebündelt: Die große Datei zu prüfen dauerte im Log über 20 s, und jedes Projekt meldet sich.
  // In einer Projektgruppe erst, wenn kein Projekt mehr indiziert wird: Sonst prüfte jedes fertige
  // Projekt alle Dateien neu (CPU-Last beim Start).
  if not FWorkspaces.ProjectIndexPending then
  begin
    // Nach der Projektstufe kennt der Index alles, was das Projekt über uses erreicht. Das Ende des Aufbaus
    // (Suchpfade, Bibliothek) startet die Prüfung nicht noch einmal von vorn (Diagnose-Log 29.10.2026).
    if FIndexRecheck.Recheck(AProjectStage) then
    begin
      FSyntaxDiagnostics.RefreshLater;
    end;
    // Meldungen in atlas.json, die den Index brauchen (#309); Publish nur in der Nachrichtenschleife.
    if FConnection <> nil then
    begin
      FConnection.Queue(
        procedure
        var
          Workspace: TShellWorkspace;
          Workspaces: TArray<TShellWorkspace>;
        begin
          TMonitor.Enter(FWorkspaces.Lock);
          try
            Workspaces := FWorkspaces.Items.ToArray;
          finally
            TMonitor.Exit(FWorkspaces.Lock);
          end;
          for Workspace in Workspaces do
          begin
            Workspace.Configuration.Revalidate;
          end;
        end);
    end;
  end;
end;

function TServerComposition.IncludeResolverFor(const AUri: string): TIncludeResolver;
var
  Workspace: TShellWorkspace;
  IncludePaths: TArray<string>;
begin
  IncludePaths := nil;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    if Workspace <> nil then
    begin
      IncludePaths := Workspace.State.IncludePaths;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  // Ohne Projekt sucht der Resolver im Ordner der Datei.
  Result := TIncludeFiles.Resolver(IncludePaths);
end;

function TServerComposition.DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  Workspace: TShellWorkspace;
begin
  ADefines := nil;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
    Result := (Workspace <> nil) and Workspace.State.Defines(ADefines);
    // Datei keinem Projekt zugeordnet oder dessen Projekt noch nicht geladen (Projektgruppe): wie das
    // aktive Projekt, das die IDE zuerst meldet. Sonst blieben inaktive Zweige dort ungedimmt (#615).
    if not Result and (FWorkspaces.Items.Count > 0) then
    begin
      Result := FWorkspaces.Items[0].State.Defines(ADefines);
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function AllocatedBytes: Int64;
begin
  Result := TShutdownLeaks.AllocatedBytes;
end;

function TServerComposition.ReadSourceText(const AFileName: string; out AText: string): Boolean;
var
  Document: ITextDocument;
begin
  // Geöffnete Dokumente haben Vorrang vor der Datei auf der Platte.
  if FDocuments.TryGet(TDocumentUris.FromPath(AFileName), Document) then
  begin
    AText := Document.Text;
    Exit(True);
  end;
  Result := TShellBootstrap.ReadSourceText(AFileName, AText);
end;

function TServerComposition.TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  Result := (FTestUnits <> nil) and FTestUnits.ContextFor(AUri, AContext);
end;

function TServerComposition.ProjectSourceFiles: TArray<string>;
var
  Workspace: TShellWorkspace;
  Document: ITextDocument;
  FileName: string;
begin
  Result := nil;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    for Workspace in FWorkspaces.Items do
    begin
      for FileName in Workspace.State.ProjectFiles do
      begin
        Result := Result + [FileName];
      end;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit.
  for Document in FDocuments.Documents do
  begin
    Result := Result + [TDocumentUris.ToPath(Document.Uri)];
  end;
end;

function TServerComposition.CheckSourceFiles: TArray<string>;
var
  mWorkspace: TShellWorkspace;
  mDocument: ITextDocument;
  mSeen: TDictionary<string, Boolean>;
begin
  // Wie ProjectSourceFiles, aber mit excludeTests ohne Testunits: Sonst stehen sie in der Warteschlange der
  // Projektprüfung, werden gezählt und eingelesen und erst in der Regel-Engine übersprungen. Ob eine Unit eine
  // Testunit ist, sagt ihr uses im Index; nicht indizierte Dateien bleiben drin (die Engine entscheidet dann).
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    System.TMonitor.Enter(FWorkspaces.Lock);
    try
      for mWorkspace in FWorkspaces.Items do
      begin
        Result := Result + CheckFilesOf(mWorkspace, mSeen);
      end;
    finally
      System.TMonitor.Exit(FWorkspaces.Lock);
    end;
  finally
    mSeen.Free;
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit; geöffnete Testunits prüft der Editor ohnehin.
  for mDocument in FDocuments.Documents do
  begin
    Result := Result + [TDocumentUris.ToPath(mDocument.Uri)];
  end;
end;

function TServerComposition.CheckFilesOf(AWorkspace: TShellWorkspace;
  ASeen: TDictionary<string, Boolean>): TArray<string>;
var
  mFileName: string;
begin
  Result := nil;
  for mFileName in AWorkspace.State.ProjectFiles do
  begin
    if ASeen.ContainsKey(AnsiLowerCase(mFileName)) then
    begin
      Continue;
    end;
    ASeen.Add(AnsiLowerCase(mFileName), True);
    if not (AWorkspace.Configuration.Settings.ExcludeTests and IsIndexedTestUnit(mFileName)) then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

function TServerComposition.IsIndexedTestUnit(const AFileName: string): Boolean;
var
  mIndexed: TUnitIndex;
begin
  Result := (FIndex <> nil) and FIndex.FindFile(AFileName, mIndexed) and
    TUsesClauses.UsesTestFramework(mIndexed.InterfaceUses + mIndexed.ImplementationUses);
end;

function TServerComposition.ApplyDfmPropertyRules(const AArguments: TJSONArray): TJSONValue;
var
  mScope: string;
  mFiles, mEdits: Integer;
begin
  // Argumente: URI der Unit oder Formulardatei, Bereich form (Vorgabe), project oder group.
  if (AArguments = nil) or (AArguments.Count = 0) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument "uri" fehlt');
  end;
  mScope := TLspDfmPropertyRules.ScopeForm;
  if AArguments.Count > 1 then
  begin
    mScope := AArguments.Items[1].Value;
  end;
  Result := TLspDfmPropertyRules.BuildEdit(
    DfmPropertyUnits(TLspDfmPropertyRules.UnitOf(TDocumentUris.ToPath(AArguments.Items[0].Value)), mScope),
    DfmPropertyFindings, mFiles, mEdits);
  // Nur Zahlen ins Log, keine Pfade (#647).
  FLogger.Info(Format('Eigenschaftsregeln: %d Änderungen in %d Formulardateien vorgeschlagen', [mEdits, mFiles]));
end;

function TServerComposition.DfmPropertyUnits(const AFileName, AScope: string): TArray<string>;
var
  mWorkspace, mPicked: TShellWorkspace;
begin
  if SameText(AScope, TLspDfmPropertyRules.ScopeForm) then
  begin
    Result := TArray<string>.Create(AFileName);
    Exit;
  end;
  Result := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mPicked := FWorkspaces.Pick(AFileName);
    for mWorkspace in FWorkspaces.Items do
    begin
      if SameText(AScope, TLspDfmPropertyRules.ScopeGroup) or (mWorkspace = mPicked) then
      begin
        Result := Result + mWorkspace.State.ProjectFiles;
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

/// <summary>Nur die Regeln mit der Kennung AId.</summary>
function RulesWithId(const ARules: TArray<IRule>; const AId: string): TArray<IRule>;
var
  mRule: IRule;
begin
  Result := nil;
  for mRule in ARules do
  begin
    if SameText(mRule.Descriptor.Id, AId) then
    begin
      Result := Result + [mRule];
    end;
  end;
end;

function TServerComposition.DfmPropertyFindings(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;
var
  mContext: TRuleCheckContext;
  mText: string;
  mTree: TSyntaxTree;
begin
  AFindings := nil;
  Result := SameText(ExtractFileExt(AFileName), '.pas') and
    RuleContextFor(TDocumentUris.FromPath(AFileName), mContext) and (mContext.FormFile <> '') and
    ReadSourceText(AFileName, mText);
  if not Result then
  begin
    Exit;
  end;
  // Nur dfm-property; RuleFindings zieht die Baseline nicht ab, der Befehl korrigiert alle Verstöße.
  mContext.Rules := RulesWithId(mContext.Rules, TLspDfmPropertyRules.RuleId);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    AFindings := TLspSyntaxDiagnostics.RuleFindings(mText, mTree, mContext);
  finally
    mTree.Free;
  end;
end;

function TServerComposition.RefactoringProject(const AFileName: string; out AProject: TProjectInfo): Boolean;
var
  Workspace: TShellWorkspace;
begin
  AProject := Default(TProjectInfo);
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(AFileName);
    Result := (Workspace <> nil) and Workspace.State.Project(AProject);
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.MissingUnitSetupFor(const AFileName, AUnitName: string;
  out ASetup: TMissingUnitSetup): Boolean;
var
  mWorkspace: TShellWorkspace;
  mGroup: TArray<TMissingUnitProject>;
  mProject: TProjectInfo;
begin
  ASetup := Default(TMissingUnitSetup);
  // Arbeitsbereich festhalten, die .dproj-Dateien aber außerhalb von FWorkspaces.Lock lesen (#647).
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(AFileName);
    if mWorkspace = nil then
    begin
      Exit(False);
    end;
    mGroup := GroupMembersOf(mWorkspace);
    FWorkspaces.Hold(TArray<TShellWorkspace>.Create(mWorkspace));
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  try
    Result := mWorkspace.State.Project(mProject);
    if Result then
    begin
      ASetup := TShellWorkspaceJobs.MissingUnitSetupOf(mProject, mWorkspace.State.Install);
    end;
  finally
    FWorkspaces.Release(TArray<TShellWorkspace>.Create(mWorkspace));
  end;
  if not Result then
  begin
    Exit;
  end;
  ASetup.UnitName := AUnitName;
  ASetup.GroupProjects := mGroup;
  // Nur der Index: nichts nachladen, die Suche läuft bei jeder Code-Aktion auf der Zeile.
  ASetup.IndexFile := IndexUnitFile;
end;

function TServerComposition.GroupMembersOf(AWorkspace: TShellWorkspace): TArray<TMissingUnitProject>;
var
  mOther: TShellWorkspace;
  mMember: TMissingUnitProject;
  mOtherProject: TProjectInfo;
begin
  Result := nil;
  for mOther in FWorkspaces.Items do
  begin
    if (mOther <> AWorkspace) and mOther.State.Project(mOtherProject) and
      not SameFileName(mOtherProject.FileName, AWorkspace.State.ProjectFileName) then
    begin
      mMember := Default(TMissingUnitProject);
      mMember.FileName := mOtherProject.FileName;
      mMember.SearchPaths := mOtherProject.SearchPaths;
      Result := Result + [mMember];
    end;
  end;
end;

function TServerComposition.IndexUnitFile(AName: string): string;
var
  mUnit: TUnitIndex;
begin
  if FIndex.FindUnit(AName, mUnit) then
  begin
    Result := mUnit.FileName;
  end
  else
  begin
    Result := '';
  end;
end;

function TServerComposition.NewNamesFor(const AUri: string): TPascalNamePrefixes;
var
  FileName: string;
  Workspace: TShellWorkspace;
  Settings: TServerSettings;
  Context: TRuleContext;
begin
  FileName := TDocumentUris.ToPath(AUri);
  Context := Default(TRuleContext);
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(FileName);
    if Workspace = nil then
    begin
      Settings := FLooseSettings;
    end
    else
    begin
      Settings := Workspace.Configuration.Settings;
      Context.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(Workspace.Root), FileName);
      Context.Naming := Workspace.RuleServices.Naming;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  Context.UnitName := ChangeFileExt(ExtractFileName(FileName), '');
  Result := TRuleEngine.NewNames(BuiltinRules, Settings, Context);
end;

const
  /// <summary>Protokoll der Sitzung im Speicher für Fehlerbericht und Diagnosepaket (#1356).</summary>
  SessionLogLines = 10000;

function TServerComposition.UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := (FCodeActions <> nil) and FCodeActions.UsesContextOf(AUri, AContext);
end;

function TServerComposition.SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
var
  Settings: TServerSettings;
begin
  Settings := SettingsFor(AUri);
  Result := Settings.SlashCommands;
  ADisabled := Settings.SlashCommandsDisabled;
  // usesCommand bleibt als Alias erhalten (#254).
  if not Settings.UsesCommand then
  begin
    ADisabled := ADisabled + ['uses'];
  end;
end;

function TServerComposition.DocCommentsFor(const AUri: string): Boolean;
begin
  Result := SettingsFor(AUri).CompleteBlocksDocComment;
end;

function TServerComposition.DelphiVersionFor(const AUri: string): string;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    if Workspace = nil then
    begin
      Result := '';
    end
    else
    begin
      // Tatsächlich gewählte Installation (#47), sonst die konfigurierte Version.
      Result := Workspace.State.DelphiVersion;
      if Result = '' then
      begin
        Result := Workspace.Configuration.Settings.DelphiVersion;
      end;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.LanguageLevelFor(const AUri: string): string;
begin
  Result := TLanguageFeatures.LanguageLevel(DelphiVersionFor(AUri), SettingsFor(AUri).MinDelphiVersion);
end;

function TServerComposition.CompletionSettingsFor(const AUri: string): TCompletionSettings;
begin
  Result := SettingsFor(AUri).Completion;
end;

function TServerComposition.FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
var
  Workspace: TShellWorkspace;
  Project: TProjectInfo;
  Context: TIdeProjectContext;
  Name: string;
begin
  Result := TFormatRoutines.Defaults;
  for Name in TRuleOptions.Strings(TRuleEngine.RuleOptions(FormatArgsRuleId, SettingsFor(AUri)), 'formatMethods',
    nil) do
  begin
    if Trim(Name) <> '' then
    begin
      Result := Result + [TFormatRoutines.Custom(Name, -1)];
    end;
  end;
  Workspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
  if (Workspace <> nil) and Workspace.State.Project(Project) and FIdeProject.Find(Project.FileName, Context) then
  begin
    Result := Result + Context.FormatFunctions;
  end;
end;

function TServerComposition.ReferenceSettingsFor(const AUri: string): TReferenceSettings;
begin
  Result := SettingsFor(AUri).References;
end;

function TServerComposition.ImpactOptionsFor(const AUri: string): TImpactOptions;
var
  Context: TTestUnitContext;
  Text: string;
begin
  Result := TImpactOptions.Default;
  Result.Depth := SettingsFor(AUri).Navigation.ImpactDepth;
  Result.References := ReferenceSettingsFor(AUri);
  // Vier Fünftel des Zeitlimits der Anfrage: Danach bräche der Watchdog sie ohne Ergebnis ab.
  Result.TimeoutMs := Integer(FRequestTimeout div 5 * 4);
  if TestUnitContextFor(AUri, Context) then
  begin
    Text := '';
    if (Context.TestProgram <> '') and not ReadSourceText(Context.TestProgram, Text) then
    begin
      Text := '';
    end;
    Result.Tests := TImpactTestScope.FromProgram(Context.Settings.Pattern, Text);
  end;
end;

/// <summary>Text auf der Platte, ohne ungespeicherte Puffer des Editors.</summary>
function DiskSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := TShellBootstrap.ReadSourceText(AFileName, AText);
end;

function TServerComposition.HandleAffectedTests(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mSettings: TServerSettings;
  mQuery: TShellAffectedQuery;
  mRequest: TAffectedRequest;
  mResolver: TNameResolver;
  mEnsureUnit: TEnsureUnitFunc;
  mProcess: ICompilerProcess;
  mFound: TAffectedResult;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "textDocument.uri" fehlt in ' + TAffectedTests.Method);
  end;
  mSettings := SettingsFor(mUri);
  mQuery := AffectedQueryFor(TJSONObject(AParams), mUri);
  mRequest := AffectedRequestFor(mUri, mSettings);
  // Typisierte Variable: TNameResolver.Create ist überladen.
  mEnsureUnit := EnsureUnit;
  mResolver := TNameResolver.Create(FIndex, mEnsureUnit);
  try
    mResolver.Namespaces := FAnalysis.Namespaces;
    try
      // Eigener Prozessstarter: git/svn laufen neben einem Compilerlauf. Über eine Variable: nie ein frisches
      // Objekt an einen const-Interface-Parameter.
      mProcess := TProcessRunner.Create;
      // git bzw. svn vergleichen die gespeicherten Dateien: Die geänderten Zeilen passen nur zum Text auf der
      // Platte, nicht zu einem ungespeicherten Puffer im Editor.
      mFound := TShellAffectedTests.Run(mProcess, mSettings, mQuery,
        TShellAffectedSources.New(mResolver, FIndex, DiskSourceText), mRequest, ACancellation);
    except
      on E: EAffectedTestsOff do
        raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, E.Message);
      on E: EVcsChanges do
        raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, E.Message);
    end;
  finally
    mResolver.Free;
  end;
  Result := TAffectedTests.ToJson(mFound);
end;

function TServerComposition.AffectedQueryFor(AParams: TJSONObject; const AUri: string): TShellAffectedQuery;
var
  mWorkspace: TShellWorkspace;
begin
  Result := Default(TShellAffectedQuery);
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    if mWorkspace = nil then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, 'Kein Arbeitsbereich zu ' + AUri);
    end;
    Result.WorkingDir := mWorkspace.Root;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  if not AParams.TryGetValue<string>('base', Result.Base) then
  begin
    Result.Base := '';
  end;
  if not AParams.TryGetValue<Boolean>('includeUncommitted', Result.IncludeUncommitted) then
  begin
    Result.IncludeUncommitted := True;
  end;
  if not AParams.TryGetValue<Integer>('depth', Result.Depth) then
  begin
    Result.Depth := 0;
  end;
end;

function TServerComposition.AffectedRequestFor(const AUri: string; const ASettings: TServerSettings): TAffectedRequest;
var
  mContext: TTestUnitContext;
begin
  Result := Default(TAffectedRequest);
  Result.Files := ProjectSourceFiles;
  Result.TestPrograms := TShellAffectedTests.TestPrograms(Result.Files, ReadSourceText);
  if TestUnitContextFor(AUri, mContext) and (mContext.TestProgram <> '') and
    (IndexText(mContext.TestProgram, Result.TestPrograms) < 0) then
  begin
    Result.TestPrograms := Result.TestPrograms + [mContext.TestProgram];
  end;
  // Treffersicherheit und Zeitlimit wie atlas/impact; Testunits aus allen Testprogrammen.
  Result.Options := ImpactOptionsFor(AUri);
  Result.Options.Tests := TShellAffectedTests.TestScope(ASettings.TestUnits.Pattern, Result.TestPrograms,
    ReadSourceText);
end;

function TServerComposition.RefactoringSettingsFor(const AUri: string): TRefactoringSettings;
begin
  Result := SettingsFor(AUri).Refactoring;
end;

function TServerComposition.StringLiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
begin
  Result := SettingsFor(AUri).StringLiteral;
  AMultiline := TStringLiterals.UseMultiline(Result.Style, LanguageLevelFor(AUri));
end;

function TServerComposition.MetricsSourceFor(const AFileName: string; AProject: Boolean;
  out ASource: TLspMetricsSource): Boolean;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
begin
  ASource := Default(TLspMetricsSource);
  ASource.Settings := TServerSettings.Default;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := MetricsWorkspaceOf(AFileName);
    if mWorkspace = nil then
    begin
      Exit(False);
    end;
    ASource.Settings := mWorkspace.Configuration.Settings;
    ASource.Root := mWorkspace.Root;
    if mWorkspace.State.Project(mProject) then
    begin
      ASource.Title := ChangeFileExt(ExtractFileName(mProject.FileName), '');
    end
    else
    begin
      ASource.Title := mWorkspace.Name;
    end;
    if AProject then
    begin
      ASource.Files := mWorkspace.State.ProjectFiles;
    end;
    Result := True;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.MetricsWorkspaceOf(const AFileName: string): TShellWorkspace;
begin
  Result := nil;
  // Projektdatei: der Arbeitsbereich dieses Projekts (Projektgruppe, #648).
  if MatchText(ExtractFileExt(AFileName), ['.dproj', '.dpr', '.dpk']) then
  begin
    Result := ProjectWorkspaceOf(AFileName);
  end;
  if (Result = nil) and (AFileName <> '') then
  begin
    Result := FWorkspaces.WorkspaceOf(AFileName);
  end;
  Result := TShellWorkspaces.Choose(Result, FWorkspaces.Items);
end;

function TServerComposition.ProjectWorkspaceOf(const AFileName: string): TShellWorkspace;
var
  mCandidate: TShellWorkspace;
  mProject: TProjectInfo;
begin
  for mCandidate in FWorkspaces.Items do
  begin
    if (mCandidate.State.Project(mProject) and (SameText(mProject.FileName, AFileName) or
      SameText(mProject.MainSource, AFileName) or SameText(ChangeFileExt(mProject.FileName, '.dproj'),
      ChangeFileExt(AFileName, '.dproj')))) or SameText(mCandidate.Setup.ProjectFile, AFileName) then
    begin
      Exit(mCandidate);
    end;
  end;
  Result := nil;
end;

function TServerComposition.SymbolPathSourceFor(const AFileName: string; out ASettings: TServerSettings;
  out ANamespaces: TArray<string>): Boolean;
var
  Source: TLspMetricsSource;
  Workspace: TShellWorkspace;
begin
  ASettings := TServerSettings.Default;
  ANamespaces := nil;
  Result := MetricsSourceFor(AFileName, True, Source);
  if not Result then
  begin
    Exit;
  end;
  ASettings := Source.Settings;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := nil;
    if AFileName <> '' then
    begin
      Workspace := FWorkspaces.WorkspaceOf(AFileName);
    end;
    Workspace := TShellWorkspaces.Choose(Workspace, FWorkspaces.Items);
    if Workspace <> nil then
    begin
      ANamespaces := Workspace.State.Namespaces;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.ArchitectureSourceFor(const AFileName, AScope: string;
  out ARequest: TArchitectureRequest; out ASettings: TServerSettings): Boolean;
var
  mSource: TLspMetricsSource;
begin
  ARequest := Default(TArchitectureRequest);
  ASettings := TServerSettings.Default;
  Result := MetricsSourceFor(AFileName, True, mSource);
  if not Result then
  begin
    Exit;
  end;
  ASettings := mSource.Settings;
  ARequest := TArchitectureRequest.FromSettings(ASettings);
  ARequest.Scope := AScope;
  if ARequest.Scope = '' then
  begin
    ARequest.Scope := ASettings.ArchitectureScope;
  end;
  ARequest.Root := mSource.Root;
  ARequest.Title := mSource.Title;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    if ARequest.Scope = 'project' then
    begin
      ARequest.Files := mSource.Files;
    end
    else
    begin
      // Projektgruppe (#648): die Dateien aller geladenen Projekte.
      ARequest.Files := AllProjectFiles;
    end;
    ARequest.Namespaces := NamespacesNear(AFileName);
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  // Zuletzt berechneter Stand je Projekt bzw. Projektgruppe für die Angleichung (#1367).
  ARequest.PreviousFile := TIndexCacheDirectory.ArchitectureFileFor(TIndexCacheDirectory.DefaultRoot,
    ARequest.ScopeKey);
end;

function TServerComposition.AllProjectFiles: TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  for mWorkspace in FWorkspaces.Items do
  begin
    Result := Result + mWorkspace.State.ProjectFiles;
  end;
end;

function TServerComposition.NamespacesNear(const AFileName: string): TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  mWorkspace := nil;
  if AFileName <> '' then
  begin
    mWorkspace := FWorkspaces.WorkspaceOf(AFileName);
  end;
  mWorkspace := TShellWorkspaces.Choose(mWorkspace, FWorkspaces.Items);
  Result := nil;
  if mWorkspace <> nil then
  begin
    Result := mWorkspace.State.Namespaces;
  end;
end;

function TServerComposition.HotspotSourceFor(const AFileName: string; out ARequest: THotspotRequest;
  out ASettings: TServerSettings; out AVcs: IHotspotVcs; out AError: string): Boolean;
var
  mArchitecture: TArchitectureRequest;
begin
  ARequest := Default(THotspotRequest);
  AVcs := nil;
  AError := '';
  Result := ArchitectureSourceFor(AFileName, '', mArchitecture, ASettings);
  if not Result then
  begin
    Exit;
  end;
  ARequest := THotspotRequest.FromSettings(ASettings);
  ARequest.Title := mArchitecture.Title;
  ARequest.Root := mArchitecture.Root;
  ARequest.Namespaces := mArchitecture.Namespaces;
  ARequest.Files := mArchitecture.Files;
  // Ohne Hotspots kein Prozess; ohne Arbeitskopie meldet die Antwort den Grund statt einer leeren Liste.
  if ASettings.HotspotsEnabled then
  begin
    TShellHotspotVcs.Detect(mArchitecture.Root, ASettings, AVcs, AError);
  end;
end;

function TServerComposition.QuerySource(out ASource: TQuerySource): Boolean;
var
  mWorkspace, mCandidate: TShellWorkspace;
  mFiles, mNamespaces: TArray<string>;
  mRoot: string;
  mReferences: TReferenceSettings;
begin
  ASource := Default(TQuerySource);
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := QueryWorkspace;
    if mWorkspace = nil then
    begin
      Exit(False);
    end;
    mNamespaces := mWorkspace.State.Namespaces;
    // Wurzel für die Spalte "Datei": gemeinsamer Ordner aller Projekte der Gruppe (bei Atlas der Stamm des
    // Repositorys). Mit der Wurzel des aktiven Projekts stand für jede Unit der anderen Projekte der volle Pfad da.
    mRoot := mWorkspace.Root;
    for mCandidate in FWorkspaces.Items do
    begin
      mRoot := TProjectPaths.CommonFolder(mRoot, mCandidate.Root);
    end;
    mReferences := mWorkspace.Configuration.Settings.References;
    // Projektgruppe (#648): die Dateien aller geladenen Projekte.
    mFiles := AllProjectFiles;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  ASource := TLspQuery.Source(FIndex, EnsureUnit, mRoot, mFiles, mNamespaces, ReadSourceText, mReferences);
  Result := True;
end;

function TServerComposition.QueryWorkspace: TShellWorkspace;
var
  mCandidate: TShellWorkspace;
begin
  // Projektgruppe: Choose liefert nur bei genau einem Arbeitsbereich etwas; sonst hieß es "Kein Projekt
  // geladen". Wurzel, Namensräume und Einstellungen vom in der IDE aktiven Projekt, sonst vom ausgewählten,
  // sonst vom ersten.
  Result := nil;
  for mCandidate in FWorkspaces.Items do
  begin
    if (mCandidate.State.ProjectFileName <> '') and
      SameText(mCandidate.State.ProjectFileName, FIdeProject.ActiveProject) then
    begin
      Result := mCandidate;
    end;
  end;
  if Result <> nil then
  begin
    Exit;
  end;
  for mCandidate in FWorkspaces.Items do
  begin
    if FWorkspaces.IsSelected(mCandidate) then
    begin
      Exit(mCandidate);
    end;
  end;
  if FWorkspaces.Items.Count > 0 then
  begin
    Result := FWorkspaces.Items[0];
  end;
end;

function TServerComposition.QuerySettingsFor(const AFileName: string; out ASettings: TServerSettings;
  out ARoot: string): Boolean;
var
  mSource: TLspMetricsSource;
begin
  Result := MetricsSourceFor(AFileName, False, mSource);
  ASettings := mSource.Settings;
  ARoot := mSource.Root;
end;

function TServerComposition.UnitRelationsOptionsFor(const AFileName: string): TUsesGraphOptions;
var
  Workspace: TShellWorkspace;
begin
  Result := TUsesGraphOptions.Default;
  Result.IncludeLibrary := True;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := nil;
    if AFileName <> '' then
    begin
      Workspace := FWorkspaces.WorkspaceOf(AFileName);
    end;
    Workspace := TShellWorkspaces.Choose(Workspace, FWorkspaces.Items);
    if Workspace <> nil then
    begin
      Result.Root := Workspace.Root;
      Result.Namespaces := Workspace.State.Namespaces;
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
var
  Settings: TServerSettings;
begin
  Settings := SettingsFor(AUri);
  Result := Settings.InlayHints;
  // Marke „ohne Self“ (#686) hängt an der Umwandlung, nicht an inlayHints.
  Result.MethodWithoutSelf := Settings.Refactoring.MethodKind and Settings.Refactoring.MethodKindMarker;
end;

function TServerComposition.HintSettingsFor(const AUri: string): THintSettings;
begin
  Result := SettingsFor(AUri).Hints;
end;

function TServerComposition.RationaleOptionsFor(const AUri: string): TRationaleOptions;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    // ADR-Ordner relativ zum Arbeitsbereich; ohne Arbeitsbereich nur ein absoluter.
    if Workspace = nil then
    begin
      Result := TRationaleOptions.FromSettings(FLooseSettings, '');
    end
    else
    begin
      Result := TRationaleOptions.FromSettings(Workspace.Configuration.Settings, Workspace.Root);
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.ConditionalContextFor(const AUri: string): TConditionalContext;
var
  Settings: TDirectiveSettings;
  Workspace: TShellWorkspace;
  Project: TProjectInfo;
  HasProject: Boolean;
  Defines, Predefined, Own: TArray<string>;
  IncludePaths: TArray<string>;
  Define: string;
begin
  Settings := SettingsFor(AUri).Directives;
  Result := TConditionalContext.Default;
  Result.CompletionEnabled := Settings.Completion;
  Result.HoverEnabled := Settings.Hover;
  Result.FileName := TDocumentUris.ToPath(AUri);
  if not (Settings.Completion or Settings.Hover) then
  begin
    Exit;
  end;
  IncludePaths := nil;
  HasProject := False;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(Result.FileName);
    if Workspace <> nil then
    begin
      IncludePaths := Workspace.State.IncludePaths;
      HasProject := Workspace.State.Project(Project);
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  Result.ResolveInclude := TIncludeFiles.Resolver(IncludePaths);
  // Dieselben Symbole wie beim Abblenden inaktiver Zweige.
  Result.HasDefines := DefinesFor(AUri, Defines);
  if not Result.HasDefines then
  begin
    Exit;
  end;
  Result.Defines := Defines;
  if not HasProject then
  begin
    Project := Default(TProjectInfo);
  end;
  Predefined := TPascalPreprocessor.PredefinedSymbols(Project.Platform,
    TPascalPreprocessor.CompilerVersionFromDefines(Defines));
  Result.Config := Project.Config;
  Result.Platform := Project.Platform;
  Own := nil;
  for Define in Defines do
  begin
    if (IndexText(Define, Predefined) < 0) and not TPascalPreprocessor.IsSwitchEntry(Define) then
    begin
      Own := Own + [Define];
    end;
  end;
  Result.Sources := TConditionalSymbols.SourcesOf(Own, Project.DefineOrigins, Predefined, Project.Platform);
end;

function TServerComposition.CompilerSwitchContextFor(const AUri: string): TCompilerSwitchContext;
var
  Workspace: TShellWorkspace;
  Project: TProjectInfo;
  Defines, Predefined, Own: TArray<string>;
  IncludePaths: TArray<string>;
  Define: string;
  Source: TSymbolSource;
  Kind: TSwitchOriginKind;
begin
  Result := Default(TCompilerSwitchContext);
  Result.FileName := TDocumentUris.ToPath(AUri);
  IncludePaths := nil;
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(Result.FileName);
    if Workspace <> nil then
    begin
      IncludePaths := Workspace.State.IncludePaths;
      Result.HasProject := Workspace.State.Project(Project);
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  Result.ResolveInclude := TIncludeFiles.Resolver(IncludePaths);
  if not Result.HasProject then
  begin
    Project := Default(TProjectInfo);
  end;
  Result.Configuration := Project.Config;
  Result.Platform := Project.Platform;
  Result.Input.Properties := Project.Properties;
  // Dieselben Symbole und Schalterstände wie beim Abblenden inaktiver Zweige.
  if not DefinesFor(AUri, Defines) then
  begin
    Exit;
  end;
  Result.Input.Defines := Defines;
  Predefined := TPascalPreprocessor.PredefinedSymbols(Project.Platform,
    TPascalPreprocessor.CompilerVersionFromDefines(Defines));
  Own := nil;
  for Define in Defines do
  begin
    if (IndexText(Define, Predefined) < 0) and not TPascalPreprocessor.IsSwitchEntry(Define) then
    begin
      Own := Own + [Define];
    end;
  end;
  for Source in TConditionalSymbols.SourcesOf(Own, Project.DefineOrigins, Predefined, Project.Platform) do
  begin
    Kind := TSwitchOriginKind.Project;
    if IndexText(Source.Name, Predefined) >= 0 then
    begin
      Kind := TSwitchOriginKind.Default;
    end;
    Result.Input.DefineOrigins := Result.Input.DefineOrigins +
      [TSwitchDefineOrigin.Create(Source.Name, TSwitchOrigin.Make(Kind, Source.Origin))];
  end;
end;

function TServerComposition.FormatStyleFor(const AUri: string): TFormatStyle;
begin
  Result := SettingsFor(AUri).Formatting;
end;

function TServerComposition.ResolvedFormatStyleFor(const AUri: string): TFormatStyle;
begin
  Result := TLspFormatting.Resolve(nil, TDocumentUris.ToPath(AUri), FormatStyleFor(AUri),
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileExists(AFileName);
      if Result then
      begin
        AText := TFileEncoding.LoadText(AFileName);
      end;
    end);
end;

function TServerComposition.BuildTargetFor(const AUri: string; out APlatform, AConfig: string): Boolean;
var
  Workspace: TShellWorkspace;
  Project: TProjectInfo;
begin
  APlatform := '';
  AConfig := '';
  TMonitor.Enter(FWorkspaces.Lock);
  try
    Workspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := (Workspace <> nil) and Workspace.State.Project(Project);
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  if Result then
  begin
    APlatform := Project.Platform;
    AConfig := Project.Config;
  end;
end;

function TServerComposition.SyntaxDiagnosticsProviders: TSyntaxDiagnosticsProviders;
begin
  Result := Default(TSyntaxDiagnosticsProviders);
  Result.Defines := DefinesFor;
  // Sprachstand (#1126): minDelphiVersion begrenzt, was die Regeln als verfügbar ansehen.
  Result.Version := LanguageLevelFor;
  Result.BuildTarget := BuildTargetFor;
  Result.Rules := LiveRuleContextFor;
  Result.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompile.Results.MessagesFor(AFileName);
    end;
  // Ungenutzte uses (#621): dieselbe Analyse wie die uses-Aktionen, auch für die Diagnosen.
  Result.UsesContext := UsesContextFor;
end;

function TServerComposition.LiveRuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  mState: Integer;
begin
  Result := RuleContextFor(AUri, AContext);
  if not Result then
  begin
    Exit;
  end;
  mState := Ord(AContext.Settings.RuleChecksEnabled);
  if TInterlocked.Exchange(FRuleChecksState, mState) <> mState then
  begin
    if mState = 0 then
    begin
      FLogger.Info('Prüfregeln aus (ruleChecks.enabled): Die Prüfung im Editor meldet nur Syntaxfehler und ' +
        'Compilermeldungen; --check und MCP prüfen weiter nach atlas.json.');
    end
    else
    begin
      FLogger.Info('Prüfregeln wieder an (ruleChecks.enabled).');
    end;
  end;
  if mState = 0 then
  begin
    AContext.Rules := nil;
  end;
end;

/// <summary>Liest Ressourcen neben der Unit, z. B. die .dcr mit den Palettensymbolen (#114).</summary>
function FolderFileReader(const AFolder: string): TRuleFileReader;
begin
  Result :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(AFolder, AName));
      if Result then
      try
        AData := TFile.ReadAllBytes(TPath.Combine(AFolder, AName));
      except
        on EInOutError do
          Result := False;
        on EFileStreamError do
          Result := False;
      end;
    end;
end;

/// <summary>Fehlende Dateien aus {$I} und {$R} (#1379) neben der Unit.</summary>
function FolderFileExists(const AFolder: string): TRuleFileExists;
begin
  Result :=
    function(const AName: string): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(AFolder, AName));
    end;
end;

function TServerComposition.RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  mFileName: string;
  mProjects: TArray<TProjectInfo>;
  mLibrary: Boolean;
begin
  AContext := Default(TRuleCheckContext);
  mFileName := TDocumentUris.ToPath(AUri);
  AContext.FileName := mFileName;
  RuleWorkspaceContext(mFileName, AContext, mProjects, mLibrary);
  // Anwendungsart, Projektname und Formulare der .dpr (#926, #943, #956, #1055), wie bei MCP und Linter.
  if mProjects <> nil then
  begin
    ApplyRuleProject(mProjects, mFileName, AContext);
  end;
  // Neue Instanzen je Prüfung: Regeln dürfen so Zustand halten, ohne Threads zu teilen. Ohne Regeln bleibt die
  // Datei still (TLspSyntaxDiagnostics.RuleFindings).
  if mLibrary then
  begin
    AContext.Rules := nil;
  end
  else
  begin
    AContext.Rules := BuiltinRules;
  end;
  RuleIndexServices(AContext);
  // Editor-Prüfung (#896): Diagnosen, Code-Aktionen, Slash-Befehle und Baseline wie im Editor; uses-cycle folgt
  // dort diagnostics.usesCycleLive.
  AContext.Live := True;
  if SameText(ExtractFileExt(mFileName), '.pas') then
  begin
    ReadRuleFormFile(mFileName, AContext);
  end;
  AContext.ReadFile := FolderFileReader(ExtractFilePath(mFileName));
  AContext.FileExists := FolderFileExists(ExtractFilePath(mFileName));
  Result := True;
end;

procedure TServerComposition.RuleWorkspaceContext(const AFileName: string; var AContext: TRuleCheckContext;
  out AProjects: TArray<TProjectInfo>; out ALibrary: Boolean);
var
  mWorkspace: TShellWorkspace;
begin
  AProjects := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(AFileName);
    if mWorkspace = nil then
    begin
      AContext.Settings := FLooseSettings;
    end
    else
    begin
      AContext.Settings := mWorkspace.Configuration.Settings;
      AContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(mWorkspace.Root), AFileName);
      AContext.Baseline := mWorkspace.Baseline;
      // Index, Namespaces, Unit-Suche, Packages und Namenskonvention auf demselben Weg wie MCP und Linter
      // (#1112).
      AContext.Services := mWorkspace.RuleServices;
      // Gespeicherte Abfragen mit failIfAny als Regeln query:<name> (#1351).
      AContext.Services.Queries := FOverviews.Queries;
      AProjects := ProjectsWithFile(mWorkspace, AFileName);
    end;
    // RTL, VCL und Komponenten außerhalb der Projekte (diagnostics.librarySources): Wer mit Strg+Klick in
    // System.Net.HttpClient.pas springt, soll dort keine Befunde zu fremdem Code sehen.
    ALibrary := not AContext.Settings.DiagnosticsLibrarySources and FWorkspaces.IsLibrarySource(AFileName);
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TServerComposition.ProjectsWithFile(AWorkspace: TShellWorkspace;
  const AFileName: string): TArray<TProjectInfo>;
var
  mOther: TShellWorkspace;
  mProject: TProjectInfo;
begin
  Result := nil;
  if AWorkspace.State.Project(mProject) then
  begin
    Result := Result + [mProject];
  end;
  // Weitere Projekte mit der Datei (#1112): Eine Unit im Testprogramm und im Package hat keine
  // eindeutige Anwendungsart (MergeRuleProjects).
  for mOther in FWorkspaces.Items do
  begin
    if (mOther <> AWorkspace) and mOther.State.ContainsFile(AFileName) and mOther.State.Project(mProject) then
    begin
      Result := Result + [mProject];
    end;
  end;
end;

procedure TServerComposition.ApplyRuleProject(const AProjects: TArray<TProjectInfo>; const AFileName: string;
  var AContext: TRuleCheckContext);
var
  mRuleProject: TCheckProject;
begin
  mRuleProject := TShellRuleProjects.RuleProjectOf(AProjects, AFileName, ReadSourceText);
  AContext.Application := mRuleProject.Application;
  AContext.ProjectName := mRuleProject.Name;
  AContext.AutoCreateForms := mRuleProject.AutoCreateForms;
  AContext.ProjectMainSource := mRuleProject.ProjectMainSource;
end;

procedure TServerComposition.RuleIndexServices(var AContext: TRuleCheckContext);
var
  mPending: string;
begin
  // Der Server hält alle Ordner: ein Index, Nachladen über alle Ordner (auch für Dateien ohne Ordner) und die
  // Projekte der Gruppe für unused-public-member (#1102); still, solange Projekte laden oder der Index läuft.
  AContext.Services.Index := FIndex;
  AContext.Services.EnsureUnit := EnsureUnit;
  // Solange Projekte laden oder der Index aufgebaut wird, ohne Index prüfen: Ein halber Index kennt Units noch
  // nicht, Regeln wie unresolved-identifier meldeten dann Bezeichner aus ihnen als nicht deklariert. Ohne Index
  // schweigen diese Regeln (wie mit --no-index); IndexFinished prüft danach alle Dateien neu.
  if not FWorkspaces.RuleProjectsComplete(mPending) then
  begin
    AContext.Services.Index := nil;
    AContext.Services.EnsureUnit := nil;
  end;
  AContext.Services.ProjectFiles := TRuleProjectFiles.Create(FWorkspaces.RuleProjects, FIndex, ReadSourceText,
    function(out AReason: string): Boolean
    begin
      Result := FWorkspaces.RuleProjectsComplete(AReason);
    end, FUsesGraph);
end;

procedure TServerComposition.ReadRuleFormFile(const AFileName: string; var AContext: TRuleCheckContext);
begin
  // Formulardatei neben der Unit für den Abgleich von Feldern und Objekten (#123).
  // Mit Pfad, damit Korrekturen die Formulardatei ändern können (#309).
  if ReadSourceText(ChangeFileExt(AFileName, '.dfm'), AContext.FormText) then
  begin
    AContext.FormFile := ChangeFileExt(AFileName, '.dfm');
  end
  else if ReadSourceText(ChangeFileExt(AFileName, '.fmx'), AContext.FormText) then
  begin
    AContext.FormFile := ChangeFileExt(AFileName, '.fmx');
  end
  else
  begin
    AContext.FormText := '';
  end;
end;

procedure TServerComposition.ProjectLoaded;
var
  mNamespaces: TArray<string>;
  mLibraryRoots: TArray<string>;
begin
  // Neuer Indexaufbau: Seine Projektstufe oder, falls die ausbleibt, sein Ende startet die Projektprüfung.
  FIndexRecheck.IndexStarted;
  // Neues Projekt oder neue Installation: Der Compiler bekommt eine neue Chance (#40).
  if FCompile <> nil then
  begin
    FCompile.Reset;
  end;
  CollectNamespaces(mNamespaces, mLibraryRoots);
  ApplyNamespaces(mNamespaces);
  FDiagnostics.SetLibraryRoots(mLibraryRoots);
  if FLogAnonymizer <> nil then
  begin
    FLogAnonymizer.SetLibraryRoots(mLibraryRoots);
  end;
  FSyntaxDiagnostics.Refresh;
end;

procedure TServerComposition.CollectNamespaces(out ANamespaces, ALibraryRoots: TArray<string>);
var
  mWorkspace: TShellWorkspace;
  mNamespace: string;
begin
  // Die Features kennen eine Liste: die Namespaces aller Projekte ohne Doppelte.
  ANamespaces := nil;
  ALibraryRoots := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    // Projekte für projektweite Prüfregeln neu bestimmen (#1102).
    FWorkspaces.Touch;
    for mWorkspace in FWorkspaces.Items do
    begin
      for mNamespace in mWorkspace.State.Namespaces do
      begin
        if IndexText(mNamespace, ANamespaces) < 0 then
        begin
          ANamespaces := ANamespaces + [mNamespace];
        end;
      end;
      // Units der Delphi-Installation erscheinen im Diagnoselog mit Namen (#647).
      if (mWorkspace.State.BdsRoot <> '') and (IndexText(mWorkspace.State.BdsRoot, ALibraryRoots) < 0) then
      begin
        ALibraryRoots := ALibraryRoots + [mWorkspace.State.BdsRoot];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.ApplyNamespaces(const ANamespaces: TArray<string>);
var
  mGraphOptions: TUsesGraphOptions;
begin
  FNavigation.SetNamespaces(ANamespaces);
  // Uses-Graph (#64) löst Namen ohne Namensraum über dieselbe Liste auf; neu aufgebaut nur bei Änderung.
  mGraphOptions := FUsesGraph.Options;
  if string.Join(';', mGraphOptions.Namespaces) <> string.Join(';', ANamespaces) then
  begin
    mGraphOptions.Namespaces := ANamespaces;
    FUsesGraph.SetOptions(mGraphOptions);
  end;
  FCompletion.Completion.Namespaces := ANamespaces;
  FAnalysis.SetNamespaces(ANamespaces);
end;

procedure TServerComposition.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  mFileName: string;
begin
  // Sicherheitsnetz (#1355): Ein geänderter Inhalt beendet das Überspringen für diese Datei.
  if (FCrashCases <> nil) and (AKind = TDocumentEventKind.Changed) then
  begin
    FCrashCases.DocumentChanged(ADocument.Uri, ADocument.Text);
  end;
  mFileName := TDocumentUris.ToPath(ADocument.Uri);
  if StartsText('file:', ADocument.Uri) then
  begin
    DocumentIndexEvent(AKind, mFileName, ADocument.Text);
  end;
  // Nach dem Speichern einer Quelldatei kompilieren (#40), abschaltbar über compiler.onSave.
  if (AKind = TDocumentEventKind.Saved) and MatchText(ExtractFileExt(mFileName), ['.pas', '.dpr', '.dpk', '.inc']) then
  begin
    SourceSaved(mFileName);
  end
  else if IsConfigurationFileName(ExtractFileName(mFileName)) then
  begin
    ConfigurationDocumentEvent(AKind, ADocument);
  end;
end;

function TServerComposition.LockedWorkspaceOf(const AFileName: string): TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    Result := FWorkspaces.WorkspaceOf(AFileName);
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TServerComposition.DocumentIndexEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
var
  mWorkspace: TShellWorkspace;
begin
  // Tipp-Pause (#492): ungespeicherten Stand in den Index; beim Schließen wieder den der Platte.
  if FIndexRefresh <> nil then
  begin
    IndexRefreshEvent(AKind, AFileName, AText);
  end;
  if AKind <> TDocumentEventKind.Opened then
  begin
    Exit;
  end;
  if FDeriveWorkspaces then
  begin
    DeriveWorkspace(AFileName);
  end;
  // Zurückgestelltes Projekt der Gruppe (index.projectGroup = false): jetzt indizieren (#648).
  mWorkspace := LockedWorkspaceOf(AFileName);
  // Nur der Thread der Nachrichtenschleife entfernt Arbeitsbereiche; mWorkspace bleibt gültig.
  if (mWorkspace <> nil) and mWorkspace.Setup.Deferred then
  begin
    mWorkspace.Activate;
  end;
end;

procedure TServerComposition.IndexRefreshEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
begin
  case AKind of
    TDocumentEventKind.Changed:
      begin
        FIndexRefresh.Changed(AFileName, AText);
        // Beim Tippen macht die Projektprüfung Platz (#1247).
        if FPullDiagnostics <> nil then
        begin
          FPullDiagnostics.Typed;
        end;
      end;
    TDocumentEventKind.Closed:
      if TLspIndexRefresh.Applies(AFileName) then
      begin
        FIndexRefresh.Closed(AFileName);
        FUsesChanges.Forget(AFileName);
        HandleWatchedFiles([TFileChange.Create(AFileName, TFileChangeKind.Changed)]);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TServerComposition.SourceSaved(const AFileName: string);
var
  mWorkspace: TShellWorkspace;
  mOnSave: Boolean;
  mChoice: TCompilerBackendChoice;
begin
  // Index nachziehen (#500): Clients ohne Dateiüberwachung (IDE-Plugin) melden nur das Speichern;
  // bei einer .inc liest der Index die einbindenden Units neu ein.
  if not SameText(ExtractFileExt(AFileName), '.dpk') then
  begin
    HandleWatchedFiles([TFileChange.Create(AFileName, TFileChangeKind.Changed)]);
  end;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.WorkspaceOf(AFileName);
    mOnSave := (mWorkspace <> nil) and mWorkspace.Configuration.Settings.Compiler.OnSave;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  if mOnSave then
  begin
    FCompile.Start(AFileName, False, mChoice);
  end;
end;

procedure TServerComposition.ConfigurationDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  mWorkspace: TShellWorkspace;
begin
  mWorkspace := LockedWorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
  // Nur der Thread der Nachrichtenschleife entfernt Ordner; mWorkspace bleibt gültig.
  if mWorkspace <> nil then
  begin
    mWorkspace.Configuration.DocumentEvent(AKind, ADocument);
  end
  else
  begin
    FLooseConfiguration.DocumentEvent(AKind, ADocument);
  end;
end;

function TServerComposition.CompileJobFor(const AFileName: string; out AJob: TShellCompileJob;
  out AError: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AJob := Default(TShellCompileJob);
  AError := '';
  TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := nil;
    if AFileName <> '' then
    begin
      mWorkspace := FWorkspaces.WorkspaceOf(AFileName);
    end;
    mWorkspace := TShellWorkspaces.Choose(mWorkspace, FWorkspaces.Items);
    if mWorkspace = nil then
    begin
      AError := 'Kein Ordner mit Projekt geöffnet';
    end
    else if mWorkspace.CompileJob(AJob, AError) then
    begin
      AError := '';
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  Result := AError = '';
end;

procedure TServerComposition.HandleDidChangeConfiguration(const AParams: TJSONValue);
var
  Workspace: TShellWorkspace;
begin
  SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams));
  UpdateLooseSettings;
  for Workspace in FWorkspaces.Items.ToArray do
  begin
    Workspace.Configuration.SetEditorSettings(FEditorSettings);
  end;
end;

class function TServerComposition.GlobalSettingsPath: string;
begin
  Result := TShellBootstrap.GlobalSettingsFile;
end;

procedure TServerComposition.LoadGlobalSettings;
var
  Settings: TServerSettings;
  Text: string;
  Workspace: TShellWorkspace;
  Issues, Misplaced: TArray<TConfigurationIssue>;
  Issue: TConfigurationIssue;
begin
  // Nicht lesbar (gerade geschrieben oder gesperrt): Warnung im Log, der Beobachter meldet die Datei erneut.
  Text := TShellBootstrap.LoadGlobalSettings(FGlobalSettingsFile, FLogger);
  if Text = FGlobalSettings then
  begin
    Exit;
  end;
  FGlobalSettings := Text;
  UpdateLooseSettings;
  if Text <> '' then
  begin
    Settings := TConfigurationParser.Parse(Text, Issues);
    // Projekt-Schlüssel in der globalen Datei wirken nicht; das Log nennt sie.
    TConfigurationScopes.Filter(Text, TConfigurationScope.Global, Misplaced);
    // "delphiVersion" ist global: Fehlt die Version, steht die Warnung mit Stelle in settings.json im Log
    // (#47); die Projekte nehmen dann die automatisch gewählte Version.
    Misplaced := Misplaced + TDelphiVersions.ConfigurationIssues(Settings, TDelphiInstallation.Versions);
    FLogger.Info(Format('Globale Einstellungen gelesen (%d Meldungen)', [Length(Issues) + Length(Misplaced)]));
    for Issue in Misplaced do
    begin
      FLogger.Warning(Format('%s(%d,%d): %s', [ExtractFileName(FGlobalSettingsFile), Issue.Range.StartPos.Line + 1,
        Issue.Range.StartPos.Character + 1, Issue.Message]));
    end;
  end;
  for Workspace in FWorkspaces.Items.ToArray do
  begin
    Workspace.Configuration.SetGlobalSettings(FGlobalSettings);
  end;
end;

procedure TServerComposition.UpdateWatchedSettings;
var
  Files: TArray<string>;
  Workspace: TShellWorkspace;
begin
  if FFileWatcher = nil then
  begin
    Exit;
  end;
  Files := [FGlobalSettingsFile];
  TMonitor.Enter(FWorkspaces.Lock);
  try
    for Workspace in FWorkspaces.Items do
    begin
      Files := Files + [Workspace.Configuration.PrimaryFileName, Workspace.Configuration.LegacyFileName];
    end;
  finally
    TMonitor.Exit(FWorkspaces.Lock);
  end;
  FFileWatcher.SetFiles(Files);
end;

procedure TServerComposition.HandleWatchedFiles(const AChanges: TArray<TFileChange>);
var
  mChange: TFileChange;
  mSources: TArray<TFileChange>;
  mReload: TList<TShellWorkspace>;
begin
  mSources := nil;
  mReload := TList<TShellWorkspace>.Create;
  try
    for mChange in AChanges do
    begin
      WatchedFileChanged(mChange, mReload, mSources);
    end;
    ReloadWorkspaces(mReload);
  finally
    mReload.Free;
  end;
  if Length(mSources) > 0 then
  begin
    ApplySourceChanges(mSources);
  end;
end;

procedure TServerComposition.WatchedFileChanged(const AChange: TFileChange; AReload: TList<TShellWorkspace>;
  var ASources: TArray<TFileChange>);
var
  mWorkspace: TShellWorkspace;
begin
  if (FGlobalSettingsFile <> '') and SameText(AChange.FileName, FGlobalSettingsFile) then
  begin
    LoadGlobalSettings;
  end
  else if IsConfigurationFileName(ExtractFileName(AChange.FileName)) then
  begin
    ConfigurationFileChanged(AChange.FileName);
  end
  else if TLspWatchedFiles.IsProjectFile(AChange.FileName) then
  begin
    mWorkspace := LockedWorkspaceOf(AChange.FileName);
    if (mWorkspace <> nil) and not AReload.Contains(mWorkspace) then
    begin
      AReload.Add(mWorkspace);
    end;
  end
  // .inc (#264): der Index liest die einbindenden Units neu ein.
  else if MatchText(ExtractFileExt(AChange.FileName), ['.pas', '.dpr', '.inc']) then
  begin
    ASources := ASources + [AChange];
    // Editor-Bäume mit $I neu lesen (#860): Die Symbole der .inc wählen ihre Zweige.
    if SameText(ExtractFileExt(AChange.FileName), '.inc') then
    begin
      TSyntaxTreeCache.IncludesChanged;
      FSyntaxDiagnostics.RefreshLater;
    end;
  end;
end;

procedure TServerComposition.ConfigurationFileChanged(const AFileName: string);
var
  mWorkspace: TShellWorkspace;
begin
  // atlas.json von außen geändert (#227, etwa im Dialog des Plugins): ohne Neustart übernehmen.
  for mWorkspace in FWorkspaces.Items.ToArray do
  begin
    if mWorkspace.Configuration.FileChanged(AFileName) then
    begin
      FLogger.Info(Format('Einstellungen von %s neu gelesen', [mWorkspace.Root]));
    end;
  end;
end;

procedure TServerComposition.ReloadWorkspaces(AReload: TList<TShellWorkspace>);
var
  mWorkspace: TShellWorkspace;
begin
  // Neu aufbauen: Suchpfade, Defines oder Units können sich geändert haben.
  for mWorkspace in AReload do
  begin
    FLogger.Info(Format('Projektdatei in %s geändert, Symbolindex wird neu aufgebaut', [mWorkspace.Root]));
    mWorkspace.Reload;
  end;
end;

procedure TServerComposition.ApplySourceChanges(const ASources: TArray<TFileChange>);
var
  mWorkspace: TShellWorkspace;
  mChange: TFileChange;
  mUpdated: Integer;
  mNames: TArray<string>;
begin
  // Jeder Ordner aktualisiert die Units, die sein Aufbau kennt.
  mUpdated := 0;
  for mWorkspace in FWorkspaces.Items.ToArray do
  begin
    Inc(mUpdated, mWorkspace.ApplyChanges(ASources));
  end;
  FLogger.Debug(Format('%d Dateiänderungen von außen, %d Units im Index aktualisiert', [Length(ASources), mUpdated]));
  // Gespeichert oder von außen geändert (#1247): die Datei und die Units, die sie in uses haben bzw. einbinden.
  if FPullDiagnostics <> nil then
  begin
    mNames := nil;
    for mChange in ASources do
    begin
      mNames := mNames + [mChange.FileName];
    end;
    FPullDiagnostics.Check.Affected(mNames, True);
  end;
end;

/// <summary>Protokoll für den stdio-Betrieb: Debug-Senke der Plattform, stderr nur für Fehler, Auszug der Sitzung
/// und die Datei aus --log samt Anonymisierer.</summary>
function NewStdioLogger(const AOptions: TCommandLineOptions; out ARecentLog: IRecentLogLines;
  out AAnonymizer: ILogAnonymizer): TLogger;
var
  mDebugSink: ILogSink;
  mRecentSink: TRecentLogSink;
begin
  Result := TLogger.Create;
  mDebugSink := TShellPlatform.DebugLogSink;
  if mDebugSink <> nil then
  begin
    Result.AddSink(mDebugSink, TLogLevel.Debug);
  end;
  // stderr zeigt VS Code ebenfalls im Ausgabefenster; dort nur Fehler, um
  // Doppelungen mit window/logMessage zu vermeiden.
  Result.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Error);
  // Auszug für den Fehlerbericht (#108) und das Protokoll der Sitzung im Diagnosepaket (#1356), unabhängig von
  // --log.
  mRecentSink := TRecentLogSink.Create(SessionLogLines);
  ARecentLog := mRecentSink;
  Result.AddSink(mRecentSink, TLogLevel.Info);
  TShellDiagnostics.AddLogFile(Result, AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId),
    AOptions.LogNames, AOptions.LogLevel, AAnonymizer);
  // Ohne --log bzw. mit --log-names trotzdem einer: Er sammelt die Namen der Projekte für den anonymen Status im
  // Diagnosepaket (#1356).
  if AAnonymizer = nil then
  begin
    AAnonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
  end;
end;

/// <summary>Transport über stdin/stdout, mit --trace hinter einem Mitschnitt (ATracing, sonst nil).</summary>
function NewStdioTransport(const AOptions: TCommandLineOptions; const ALogger: ILogger;
  out ATracing: TJsonRpcTracingTransport): IJsonRpcTransport;
var
  mTraceName: string;
begin
  ATracing := nil;
  // Ab hier erreichen versehentliche Ausgaben (Writeln, Bibliotheken) nur noch stderr.
  Result := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  if AOptions.TraceFile = '' then
  begin
    Exit;
  end;
  try
    ATracing := TJsonRpcTracingTransport.Create(Result,
      CreateTraceStream(AOptions.TraceFile, IntToStr(TParentWatcher.CurrentProcessId), mTraceName), True);
    Result := ATracing;
    if not SameText(mTraceName, AOptions.TraceFile) then
    begin
      ALogger.Info(Format('Mitschnitt "%s" ist belegt, schreibe nach "%s"', [AOptions.TraceFile, mTraceName]));
    end;
  except
    on E: Exception do
      ALogger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [AOptions.TraceFile, E.Message]));
  end;
end;

/// <summary>Meldet den Abbruch des Mitschnitts. Fängt nur den Logger ein; den Zyklus Logger → Sink → Transport →
/// Closure bricht das einmalige Leeren beim Melden bzw. Destroy (S-07). Anonym: Klasse und Meldung, kein Pfad.</summary>
procedure WatchTracing(ATracing: TJsonRpcTracingTransport; const ALogger: ILogger);
begin
  ATracing.OnFailed :=
    procedure(const AReason: string)
    begin
      ALogger.Warning('Mitschnitt abgebrochen, der Server arbeitet ohne weiter: ' + AReason);
    end;
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  mLoggerImpl: TLogger;
  mLogger: ILogger;
  mTransport: IJsonRpcTransport;
  mWarning: string;
  mAnonymizer: ILogAnonymizer;
  mRecentLog: IRecentLogLines;
  mTracing: TJsonRpcTracingTransport;
begin
  // Stacktraces für das Absturzprotokoll (Exception.StackTrace).
  TStackTrace.Install;
  // Schutzseite nach Stapelüberlauf (#1094) und Lesen mit FILE_SHARE_DELETE (Bericht M5), soweit die
  // Plattform sie braucht.
  TShellPlatform.InstallGuards;
  mLoggerImpl := NewStdioLogger(AOptions, mRecentLog, mAnonymizer);
  mLogger := mLoggerImpl;
  mTransport := NewStdioTransport(AOptions, mLogger, mTracing);
  mLoggerImpl.AddSink(TLspLogMessageSink.Create(mTransport), AOptions.LogLevel);
  for mWarning in AOptions.Warnings do
  begin
    mLogger.Warning(mWarning);
  end;
  Result := TServerComposition.Create(mTransport, mLogger);
  if mTracing <> nil then
  begin
    Result.FTracing := mTracing;
    WatchTracing(mTracing, mLogger);
  end;
  Result.FRecentLog := mRecentLog;
  Result.FLogAnonymizer := mAnonymizer;
  Result.FCompile.Restricted := AOptions.Restricted;
  Result.FClientProcessId := AOptions.ClientProcessId;
  if AOptions.Restricted then
  begin
    mLogger.Info('Eingeschränkter Modus (Arbeitsbereich nicht vertrauenswürdig): der Compiler wird nicht gestartet');
  end;
end;

procedure TServerComposition.WatchParent(const AInitializeParams: TJSONObject);
var
  ProcessId: Cardinal;
  Value: TJSONValue;
begin
  ProcessId := FClientProcessId;
  if AInitializeParams <> nil then
  begin
    Value := AInitializeParams.GetValue('processId');
    if Value is TJSONNumber then
    begin
      ProcessId := Cardinal(TJSONNumber(Value).AsInt64);
    end;
  end;
  if (ProcessId = 0) or (FParentWatcher <> nil) then
  begin
    Exit;
  end;
  FParentWatcher := TParentWatcher.Create(ProcessId,
    procedure
    begin
      FLogger.Warning(Format('Editor-Prozess %d ist beendet; der Server beendet sich', [ProcessId]));
      FEndReason := TDiagnosticEndReason.ParentExited;
      FConnection.Stop;
    end);
end;

function TServerComposition.DescribeFailure(const AError: Exception): string;
var
  Stack: string;
begin
  Result := Format('%s: %s%sLetzte Nachricht: %s', [AError.ClassName, AError.Message, sLineBreak,
    FDispatcher.LastMessage]);
  Stack := TShellPlatform.StackTraceOf(AError);
  if Stack <> '' then
  begin
    Result := Result + sLineBreak + Stack;
  end;
end;

class function TServerComposition.BuildCapabilities: TJSONObject;
var
  Commands: TJSONArray;
begin
  // Die Features tragen ihre Capabilities hier ein, sobald sie umgesetzt sind.
  Result := TJSONObject.Create;
  Result.AddPair('textDocumentSync', TLspTextDocumentSync.Capability);
  Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('foldingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('linkedEditingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('documentFormattingProvider', TJSONBool.Create(True));
  // Nur für den Schnellbefehl /uses (#254); Blockabschluss (#179) übernimmt die IDE.
  Result.AddPair('documentOnTypeFormattingProvider', TLspFormatting.OnTypeCapability);
  Result.AddPair('documentRangeFormattingProvider', TJSONBool.Create(True));
  Result.AddPair('selectionRangeProvider', TJSONBool.Create(True));
  Result.AddPair('definitionProvider', TJSONBool.Create(True));
  Result.AddPair('declarationProvider', TJSONBool.Create(True));
  Result.AddPair('typeDefinitionProvider', TJSONBool.Create(True));
  Result.AddPair('hoverProvider', TJSONBool.Create(True));
  Result.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('documentHighlightProvider', TJSONBool.Create(True));
  Result.AddPair('referencesProvider', TJSONBool.Create(True));
  Result.AddPair('renameProvider', TLspRename.Capability);
  Result.AddPair('completionProvider', TLspCompletion.Capability);
  Result.AddPair('signatureHelpProvider', TLspSignatureHelp.Capability);
  Result.AddPair('typeHierarchyProvider', TJSONBool.Create(True));
  Result.AddPair('callHierarchyProvider', TJSONBool.Create(True));
  Result.AddPair('implementationProvider', TJSONBool.Create(True));
  Result.AddPair('inlayHintProvider', TJSONBool.Create(True));
  Result.AddPair('inlineValueProvider', TJSONBool.Create(True));
  Result.AddPair('codeLensProvider', TLspCodeLens.Capability);
  Result.AddPair('semanticTokensProvider', TLspSemanticTokens.Capability);
  Result.AddPair('codeActionProvider', TLspCodeActions.Capability);
  Result.AddPair('documentLinkProvider', TLspDocumentLinks.Capability);
  Result.AddPair('colorProvider', TJSONBool.Create(True));
  Commands := TJSONArray.Create;
  Commands.Add(StatusCommand);
  Commands.Add(TShellCrashCases.RetryCommand);
  Commands.Add(ProcessesCommand);
  Commands.Add(TShellServerCommands.CompileCommand);
  Commands.Add(TShellServerCommands.SelectBuildCommand);
  Commands.Add(TShellServerCommands.SelectProjectCommand);
  Commands.Add(TShellServerCommands.RebuildIndexCommand);
  Commands.Add(ClearIndexCommand);
  Commands.Add(TLspPullDiagnostics.RecheckCommand);
  Commands.Add(TBugReport.Command);
  Commands.Add(TServerPackage.Command);
  Commands.Add(TQualifiedNames.Command);
  Commands.Add(TEnumValueCommands.Command);
  Commands.Add(TStringLiteralCommands.PlainTextCommand);
  Commands.Add(TStringLiteralCommands.ToLiteralCommand);
  // Editor-Befehl (#97): Clients wie VS Code bieten ihn damit an.
  Commands.Add(TLspBaseline.Command);
  Result.AddPair('executeCommandProvider', TJSONObject.Create(TJSONPair.Create('commands', Commands)));
  Result.AddPair('workspace', TLspWorkspaceFolders.Capability);
end;

function TServerComposition.Run: Integer;
var
  Previous: Integer;
begin
  FLogger.Info(Format('%s %s gestartet', [TProductVersion.Name, TProductVersion.Version]));
  FDiagnostics.AllowMethods(FDispatcher.Methods);
  Previous := FDiagnostics.BeginRun(TProductVersion.Version, AllocatedBytes);
  // Neustarts erklären (#175): Die IDE beendet ihren Server hart (Projektwechsel, IDE geschlossen);
  // dann fehlt dessen Endzeile, und der nächste Start meldet das hier.
  if Previous > 0 then
  begin
    FLogger.Info(Format('%d frühere Serverläufe ohne Endzeile (von der IDE beendet oder abgestürzt)',
      [Previous]));
  end;
  // Endzeile, sobald die Eingabe endet: Das Plugin beendet den Prozess nach 2 s, auch wenn noch
  // Anfragen laufen; sonst meldete der nächste Lauf einen Absturz (#647).
  FConnection.OnLoopEnded :=
    procedure
    begin
      FLogger.Info('Verbindung beendet: ' + TShellDiagnostics.EndReasonText(FEndReason));
      FDiagnostics.EndRun(FEndReason, FLifecycle.ExitCode, AllocatedBytes);
    end;
  try
    FConnection.Run;
    Result := FLifecycle.ExitCode;
    FDiagnostics.EndRun(FEndReason, Result, AllocatedBytes);
  except
    on E: Exception do
    begin
      FLogger.Error('Server abgebrochen: ' + DescribeFailure(E));
      Result := 1;
      FDiagnostics.EndRun(TDiagnosticEndReason.Exception_, Result, AllocatedBytes, E);
    end;
  end;
  FLogger.Info(Format('Beendet mit Exit-Code %d', [Result]));
end;

end.
