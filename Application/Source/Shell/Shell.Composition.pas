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
  System.Diagnostics,
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
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Common.Lsp.FoldingRanges,
  Atlas.Common.Lsp.LinkedEditing,
  Atlas.Common.Lsp.InlineValues,
  Atlas.Common.Lsp.CompilerSwitches,
  Atlas.Common.Lsp.DebugUnavailable,
  Atlas.Common.Lsp.ExpressionCompletion,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Lsp.SelectionRanges,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Lsp.WorkspaceSymbols,
  Atlas.Common.Editing.Bookmarks,
  Atlas.Common.Lsp.DocumentHighlights,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.UnitSearch,
  Atlas.Common.Lsp.DocumentLinks,
  Atlas.Common.Lsp.Colors,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.Refactorings,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.DataFlow,
  Atlas.Common.Lsp.AccessChains,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Todos,
  Atlas.Common.Lsp.Architecture,
  Atlas.Common.Query.Contract,
  Atlas.Common.Lsp.Query,
  Atlas.Common.Lsp.Hotspots,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Lsp.UnitRelations,
  Atlas.Common.Lsp.SymbolPath,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Lsp.DebugDisplay,
  Atlas.Common.Lsp.EventHandlers,
  Atlas.Common.Lsp.Recursion,
  Atlas.Common.Lsp.ExitPoints,
  Atlas.Common.Lsp.Reassigned,
  Atlas.Common.Lsp.ExpressionType,
  Atlas.Common.Lsp.MethodOrder,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.OverrideMarks,
  Atlas.Common.Lsp.SlashMenu,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.BulkFix,
  Atlas.Common.Lsp.CompilerBaseline,
  Shell.Composition.Baselines,
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
  Atlas.Common.Lsp.ResourceStringCommands,
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
  Atlas.Common.Lsp.SettingsCommands,
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
    /// <summary>Start des Prozesses für den Status (#1356).</summary>
    FStartedAt: TDateTime;
    FUptime: TStopwatch;
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
    FDocumentSymbols: TLspDocumentSymbols;
    FFoldingRanges: TLspFoldingRanges;
    FLinkedEditing: TLspLinkedEditing;
    FInlineValues: TLspInlineValues;
    FCompilerSwitches: TLspCompilerSwitches;
    FDebugUnavailable: TLspDebugUnavailable;
    FFormatting: TLspFormatting;
    FSlashMenu: TLspSlashMenu;
    FSelectionRanges: TLspSelectionRanges;
    FDefinition: TLspDefinition;
    FHover: TLspHover;
    FWorkspaceSymbols: TLspWorkspaceSymbols;
    /// <summary>Lesezeichen "// @bookmark Name" für die Symbolsuche (#306).</summary>
    FBookmarks: TBookmarkStore;
    FDocumentHighlights: TLspDocumentHighlights;
    FReferences: TLspReferences;
    FRename: TLspRename;
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
    FCompletion: TLspCompletion;
    FExpressionCompletion: TLspExpressionCompletion;
    FSignatureHelp: TLspSignatureHelp;
    FHierarchies: TLspHierarchies;
    FImpact: TImpactAnalysis;
    // Datenfluss „Woher/Wohin geht der Wert?“ (#690).
    FDataFlow: TLspDataFlow;
    // Zugriffsketten am Ausführungspunkt (#865).
    FAccessChains: TLspAccessChains;
    FImplementations: TLspImplementations;
    FInlayHints: TLspInlayHints;
    FCodeLens: TLspCodeLens;
    /// <summary>Code-Metriken (#66): Befehl atlas.server.metrics mit Zwischenspeicher je Datei.</summary>
    FMetrics: TLspMetrics;
    /// <summary>TODO-Übersicht (#68): Befehl atlas.server.todos.</summary>
    FTodos: TLspTodos;
    /// <summary>Architekturübersicht (#1118): Dienst mit Zwischenspeicher je Index-Generation, Anfrage
    /// atlas/architecture und Befehl atlas.architecture.saveReport.</summary>
    FArchitectureService: TArchitectureService;
    FArchitecture: TLspArchitecture;
    /// <summary>Code-Abfragen (#1351): Dienst mit Zwischenspeicher je Index-Stand für atlas/query, das Fenster
    /// „Atlas-Abfrage“ und die Regeln query:&lt;name&gt;.</summary>
    FQueries: ICodeQueries;
    FQuery: TLspQuery;
    /// <summary>Hotspots (#1354): Dienst mit Zwischenspeicher je Stand der Versionsverwaltung und Index-Generation,
    /// Anfrage atlas/hotspots und Befehle atlas.hotspots und atlas.hotspots.saveReport.</summary>
    FHotspotService: THotspotService;
    FHotspots: TLspHotspots;
    /// <summary>Unit-Beziehungen (#593): eigener Uses-Graph mit Bibliotheks-Units, Anfrage atlas/unitRelations
    /// und Befehle zum Verschieben und Entfernen von uses-Einträgen.</summary>
    FUnitRelationsGraph: TUsesGraphService;
    FUnitRelations: TLspUnitRelations;
    FSymbolPath: TLspSymbolPath;
    /// <summary>Eigene Wertdarstellungen beim Debuggen (#854): Befehl atlas.server.debugDisplayRules.</summary>
    FDebugDisplay: TLspDebugDisplay;
    FEventHandlers: TLspEventHandlers;
    FRecursion: TLspRecursion;
    /// <summary>Baseline für Altprojekte (#97, atlas.updateBaseline), Compilermeldungen darin (#530) und die
    /// Sammelkorrektur (#1352).</summary>
    FBaselines: TShellBaselines;
    FSemanticTokens: TLspSemanticTokens;
    FCodeActions: TLspCodeActions;
    FRefactorings: TShellRefactorings;
    /// <summary>Testunit anlegen und wechseln (#274, #189).</summary>
    FTestUnits: TLspTestUnits;
    /// <summary>Gefundenes Testprogramm je Wurzel mit Zeitpunkt (#274); Sperre ist das Objekt selbst.</summary>
    FTestPrograms: TDictionary<string, TPair<string, UInt64>>;
    /// <summary>Daten des Fensters „Units suchen“ im Plugin (#777).</summary>
    FUnitSearch: TUnitSearch;
    FDocumentLinks: TLspDocumentLinks;
    FColors: TLspColors;
    FCommands: TLspCommands;
    // Methodenreferenzen für die Befehle, vorab gebildet (Free Pascal). Je Empfänger der eigene Typ: Delphi 12 nimmt
    // TCompletionReadText nicht als TResourceStringRead an, obwohl die Signatur gleich ist.
    FEnsureUnitRef: TEnsureUnitFunc;
    FReadSourceTextRef: TCompletionReadText;
    FReadResourceRef: TResourceStringRead;
    /// <summary>Schreibt einen resourcestring in eine andere Unit (#473); über den Host der Schnellbefehle.</summary>
    FResourceStringWrite: TResourceStringWrite;
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
    /// <summary>Zuletzt gewähltes Projekt je Datei, die zu mehreren Projekten gehört (#46), fürs Log; unter
    /// FWorkspacesLock.</summary>
    FProjectChoices: TDictionary<string, string>;
    FWorkspaceFolders: TLspWorkspaceFolders;
    /// <summary>Für atlas.json außerhalb aller Ordner: nur Fehlermeldungen.</summary>
    FLooseConfiguration: TLspConfiguration;
    FConnection: TJsonRpcConnection;
    FIndex: ISymbolIndex;
    /// <summary>Uses-Graph über FIndex für uses-cycle und unused-unit (#64); lebt so lange wie der Index.</summary>
    FUsesGraph: TUsesGraphService;
    // Ordner des Arbeitsbereichs. Ändern nur im Thread der Nachrichtenschleife,
    // unter FWorkspacesLock, weil Anfrage-Threads lesen.
    FWorkspaces: TObjectList<TShellWorkspace>;
    FWorkspacesLock: TObject;
    // Projekte aller gemeldeten Projektgruppen, schon bevor ihre Arbeitsbereiche geladen sind. Unter
    // FWorkspacesLock.
    FGroupProjectFiles: TArray<string>;
    /// <summary>Je Arbeitsbereich die Anfragen, die ihn außerhalb von FWorkspacesLock nutzen (EnsureUnit);
    /// ein entfernter wird erst freigegeben, wenn er hier fehlt. Nur unter FWorkspacesLock.</summary>
    FWorkspaceUsers: TDictionary<TShellWorkspace, Integer>;
    FWorkspaceCounter: Integer;
    /// <summary>Projekte aller Arbeitsbereiche für projektweite Prüfregeln (#1102). Gültig, solange
    /// FRuleProjectsStamp = FWorkspacesStamp; FWorkspacesStamp steigt mit jedem geladenen Projekt und jedem
    /// hinzugefügten oder entfernten Arbeitsbereich. Nur unter FWorkspacesLock.</summary>
    FRuleProjects: TArray<TRuleProject>;
    FRuleProjectsStamp: Integer;
    FWorkspacesStamp: Integer;
    /// <summary>Reihenfolge der Indexaufbauten aller Projekte (#648); kleiner = früher.</summary>
    FIndexScheduler: TIndexScheduler;
    FWorkspacePriority: Integer;
    /// <summary>Schreibt nur die Nachrichtenschleife, unter FWorkspacesLock; der nebenläufige Fehlerbericht
    /// (#874) liest es unter derselben Sperre.</summary>
    FEditorSettings: string;
    // Globale Benutzerdatei (#227) als unterste Ebene; Pfad, Inhalt und der Beobachter für sie und die
    // atlas.json aller Ordner. FGlobalSettings nur im Thread der Nachrichtenschleife.
    FGlobalSettingsFile: string;
    FGlobalSettings: string;
    /// <summary>Einstellungen für Dateien ohne Arbeitsbereich: global und Editor (S-02). Unter FWorkspacesLock.</summary>
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
    /// <summary>Gibt es schon einen Arbeitsbereich für AProjectFile?</summary>
    function HasProjectWorkspace(const AProjectFile: string): Boolean;
    /// <summary>Neuer Arbeitsbereich mit Setup, noch ohne Ereignisse und nicht in der Liste.</summary>
    function NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean): TShellWorkspace;
    /// <summary>Hängt Ereignisse und Rückfragen des Arbeitsbereichs an die Komposition.</summary>
    procedure WireWorkspaceEvents(AWorkspace: TShellWorkspace);
    /// <summary>Projektdateien der Gruppe und aller Arbeitsbereiche.</summary>
    function GroupProjectFiles: TArray<string>;
    /// <summary>Ordner der Projekte aller Arbeitsbereiche, für requires-Packages (#46).</summary>
    function PackageFolders: TArray<string>;
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
    /// <summary>Nimmt die Arbeitsbereiche mit Herkunft AOrigin aus der Liste; ARemaining sind die übrigen.</summary>
    function ExtractWorkspaces(const AOrigin: string; out ARemaining: TArray<TShellWorkspace>): TArray<TShellWorkspace>;
    /// <summary>Units, die nur entfernte Arbeitsbereiche enthalten, verlassen den Index.</summary>
    procedure RemoveOwnedUnits(const ARemoved, ARemaining: TArray<TShellWorkspace>);
    /// <summary>Gibt AWorkspace frei, sobald keine Anfrage ihn mehr nutzt.</summary>
    procedure FreeWhenUnused(AWorkspace: TShellWorkspace);
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
    /// <summary>Arbeitsbereich der Datei für die Schnellbefehle.</summary>
    function SlashWorkspaceOf(const AUri: string): TShellWorkspace;
    /// <summary>Vorlage des Dateikopfs für /header (#56).</summary>
    function SlashHeaderTemplateOf(const AUri: string): string;
    /// <summary>Testunit für /test (#295): dieselbe Suche wie die Code-Aktion aus #274.</summary>
    function SlashTestUnitOf(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
    /// <summary>Protokollaufruf (#304), Palettenseite (#299) und weitere Einstellungen der Schnellbefehle.</summary>
    function SlashSettingOf(const AUri, AName: string): string;
    /// <summary>Teil von Create (S-02): Arbeitsbereiche, Indexplanung und Konfiguration ohne Ordner; Pfade für die Syntaxprüfung.</summary>
    procedure WireWorkspaces;
    /// <summary>Teil von Create (S-02): Symbolindex und Diagnoselog.</summary>
    procedure WireIndex;
    /// <summary>Teil von Create (S-02): Definition, Hover, Arbeitsbereichssymbole, Hervorhebungen, Verweise, Umbenennen.</summary>
    procedure WireNavigation;
    /// <summary>Einstellungen der Hervorhebungen aus dem Arbeitsbereich von AUri.</summary>
    function HighlightSettingsFor(const AUri: string): THighlightSettings;
    /// <summary>Teil von Create (S-02): Vervollständigung mit Einstellungen, Postfix-Vorlagen und Teilergebnissen.</summary>
    procedure WireCompletion;
    function CompletionMatchingFor(const AUri: string): TCompletionMatching;
    /// <summary>Optionen der Postfix-Vorlagen (#188) für AUri.</summary>
    function PostfixOptionsFor(const AUri: string): TPostfixOptions;
    /// <summary>with auflösen über Strg+Leer auf with (#50).</summary>
    function CompletionWithEdits(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean;
    /// <summary>Methode aus Aufruf anlegen nach "(" bzw. mit Strg+Leer (#472).</summary>
    function CompletionCreateMethod(ARequest: TCompletionRequest; out ATitle, ADetail: string;
      out AEdits: TArray<TTextEdit>): Boolean;
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
    /// <summary>Umfeld der Klassen-Aktionen: Index, Sprachversion, Host der Schnellbefehle.</summary>
    function ClassActionContextOf(const AUri: string): TClassActionContext;
    /// <summary>Reihenfolge der Mitglieder aus der atlas.json des Ordners.</summary>
    function MemberOrderOf(const AUri: string): TMemberOrderSettings;
    function SortUsesOf(const AUri: string): Boolean;
    function SortUsesByNamespaceOf(const AUri: string): Boolean;
    /// <summary>uses-Umfeld der Code-Aktionen: Einstellungen und Namensräume des Ordners, Wissen des Index.</summary>
    function CodeActionUsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
    /// <summary>Code-Aktionen für Testunits und der Refactorings.</summary>
    function ExtraCodeActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    /// <summary>Include-Pfade des Projekts für die Dokumentlinks.</summary>
    function IncludePathsOf(const AUri: string): TArray<string>;
    /// <summary>Formulare in Text umwandeln (Logik in Shell.Commands.Build).</summary>
    function RunConvertForms(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Austrittspunkte am Cursor (#698).</summary>
    function RunExitPoints(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Neu zugewiesene Variablen (#712).</summary>
    function RunReassigned(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Typ des markierten Ausdrucks (#689).</summary>
    function RunExpressionType(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Methodenrümpfe in Deklarationsreihenfolge (#660).</summary>
    function RunMethodOrder(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Überschreibungen für die Zeilenleiste (#768).</summary>
    function RunOverrideMarks(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Baseline des Projekts aktualisieren.</summary>
    function RunBaseline(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Vorschau der Sammelkorrektur.</summary>
    function RunBulkFix(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Compilermeldungen in die Baseline.</summary>
    function RunCompilerBaselineAdd(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Qualifizierte Namen.</summary>
    function RunQualifiedNames(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Werte einer Aufzählung.</summary>
    function RunEnumValue(const AArguments: TJSONArray): TJSONValue;
    /// <summary>resourcestring anlegen.</summary>
    function RunAddResourceString(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Literal als reiner Text.</summary>
    function RunPlainText(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Text als Literal.</summary>
    function RunToLiteral(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Status (#28), optional anonymisiert (#1356).</summary>
    function RunStatus(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Prozesse am selben Index-Cache (#62).</summary>
    function RunProcesses(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Einstellungen mit dem Parser des Servers prüfen (#227).</summary>
    function RunSettingsCheck(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Regelkatalog für den Einstellungsdialog (#227, #909).</summary>
    function RunSettingsCatalog(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Kompilieren auf den Befehl (#40, #261).</summary>
    function RunCompile(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Index aller Ordner ohne Cache neu einlesen (#49).</summary>
    function RunRebuildIndex(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Index löschen (#492).</summary>
    function RunClearIndex(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Erneut versuchen nach dem Überspringen (#1355).</summary>
    function RunRetryCrashCase(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Alle Dateien neu prüfen (#1231).</summary>
    function RunRecheck(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Konfiguration und Plattform wählen (#46).</summary>
    function RunSelectBuild(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Projekt für Dateien mehrerer Projekte (#46).</summary>
    function RunSelectProject(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Teil von Create (S-02): workspace/executeCommand: alle Befehle des Servers.</summary>
    procedure WireCommands;
    /// <summary>Befehle für Status, Einstellungen, Fehlerbericht, Bau und Index.</summary>
    procedure WireServerCommands;
    /// <summary>Befehle für Metriken, TODOs, Architektur, Abfragen und Hotspots.</summary>
    procedure WireReportCommands;
    /// <summary>Befehle für Unit-Beziehungen, Symbolpfad, Debuggeranzeige, Ereignisse und Rekursion.</summary>
    procedure WireUnitCommands;
    /// <summary>Befehle für Compiler-Baseline, Slash-Menü, Testunits und Unit-Suche.</summary>
    procedure WireSlashCommands;
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
    /// <summary>Innerster Ordner zur Datei oder nil. Aufrufer hält FWorkspacesLock.</summary>
    function WorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Unter mehreren Projekten mit der Datei (#46): ausgewählt (selectProject), dann aktiv in der IDE,
    /// dann das erste der Gruppe. Ein Wechsel steht im Log. Aufrufer hält FWorkspacesLock.</summary>
    function ChooseProject(const AFileName: string; const ACandidates: TArray<TShellWorkspace>): TShellWorkspace;
    /// <summary>Ist AWorkspace per selectProject gewählt (#46)?</summary>
    function IsSelectedProject(AWorkspace: TShellWorkspace): Boolean;
    /// <summary>Index-Cache je Arbeitsbereich mit den angemeldeten Prozessen (#62).</summary>
    function CollectProcesses: TArray<TLspProcessWorkspace>;
    /// <summary>Arbeitsbereich zur Datei; ohne Treffer bei genau einem Arbeitsbereich dieser, sonst nil
    /// (TShellWorkspace.Choose, S-02). Aufrufer hält FWorkspacesLock.</summary>
    function PickWorkspace(const AFileName: string): TShellWorkspace;
    /// <summary>Wirksame Einstellungen zur Datei (S-02): die des Arbeitsbereichs (PickWorkspace), ohne
    /// Arbeitsbereich globale Datei und Editor-Einstellungen. Sperrt selbst und liefert eine Kopie.</summary>
    function SettingsFor(const AUri: string): TServerSettings;
    /// <summary>FLooseSettings aus globaler Datei und Editor-Einstellungen neu berechnen; Nachrichtenschleife.</summary>
    procedure UpdateLooseSettings;
    /// <summary>Setzt FEditorSettings unter FWorkspacesLock (#874).</summary>
    procedure SetEditorSettings(const AText: string);
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Hält die Arbeitsbereiche gegen Freigabe fest. Aufrufer hält FWorkspacesLock.</summary>
    procedure HoldWorkspaces(const AWorkspaces: TArray<TShellWorkspace>);
    /// <summary>Gibt festgehaltene Arbeitsbereiche wieder frei und weckt Wartende.</summary>
    procedure ReleaseWorkspaces(const AWorkspaces: TArray<TShellWorkspace>);
    /// <summary>Fortschritt des Indexaufbaus in Prozent über alle Projekte; -1, wenn keiner läuft.</summary>
    function IndexLoading: Integer;
    /// <summary>Ein Indexaufbau ist fertig: Befunde neu prüfen, falls die Projektstufe das nicht schon getan hat.
    /// Index-Thread.</summary>
    procedure IndexFinished;
    /// <summary>Projektstufe eines Aufbaus fertig: Befunde mit dem Index neu prüfen (#647). Index-Thread.</summary>
    procedure ProjectReady;
    /// <summary>Gemeinsamer Teil von ProjectReady und IndexFinished.</summary>
    procedure IndexStageDone(AProjectStage: Boolean);
    /// <summary>True, solange ein Projekt seine Projektstufe noch nicht indiziert hat.</summary>
    function ProjectIndexPending: Boolean;
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Projekte aller Arbeitsbereiche mit Art, Testkennung und Formulardateien (#1102); zwischengespeichert
    /// bis zum nächsten geladenen Projekt. Hintergrund-Thread.</summary>
    function RuleProjects: TArray<TRuleProject>;
    /// <summary>Sind alle Projekte geladen und vollständig indiziert? Sonst der Grund in AReason (#1102).</summary>
    function RuleProjectsComplete(out AReason: string): Boolean;
    /// <summary>Muster, Ordner und Testprogramm für Testunits zur Datei (#274, #189).</summary>
    function TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
    /// <summary>Einstellungen, Wurzel und Hauptdateien der Projekte; False ohne Arbeitsbereich.</summary>
    function TestUnitWorkspace(const AFileName: string; var AContext: TTestUnitContext;
      out ACandidates: TArray<string>): Boolean;
    /// <summary>Quelltext einer Datei, '' wenn sie fehlt.</summary>
    function SourceTextOrEmpty(const AFileName: string): string;
    /// <summary>Datei auf der Platte oder als offenes Dokument.</summary>
    function DocumentOrFileExists(const AFileName: string): Boolean;
    /// <summary>Datei einer Projekt-Unit aus dem Index; '' für unbekannte und Bibliotheks-Units.</summary>
    function ProjectUnitFile(const AUnitName: string): string;
    /// <summary>Gemerktes Testprogramm der Wurzel, solange es frisch ist.</summary>
    function CachedTestProgram(const ARoot: string; out AProgram: string): Boolean;
    /// <summary>Merkt das Testprogramm der Wurzel.</summary>
    procedure StoreTestProgram(const ARoot, AProgram: string);
    /// <summary>.dpr in der Wurzel und eine Ebene darunter (ohne Punktordner).</summary>
    function DprFilesNear(const ARoot: string): TArray<string>;
    /// <summary>Index, Projekte und Dateizugriffe für „Units suchen“ (#777).</summary>
    function UnitSearchContext(out AContext: TUnitSearchContext): Boolean;
    /// <summary>Projekte aller Arbeitsbereiche für die Unit-Suche.</summary>
    function UnitSearchProjects: TArray<TUnitSearchProject>;
    /// <summary>Vorfahren der Klasse AType aus dem Index.</summary>
    function IndexAncestorsOf(AType: string): TArray<string>;
    function SearchSourceText(AFileName: string): string;
    function SearchGitState(AFileName: string): string;
    /// <summary>uses-Umfeld der Code-Aktionen für AUri; leer, solange es fehlt.</summary>
    function SearchUsesContext(AUri: string): TUsesContext;
    /// <summary>Git-Zustand einer Datei für die Vorschau (#777); '' ohne Git oder Repository.</summary>
    function GitStateOf(const AFileName: string): string;
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
    /// <summary>Übrige Projekte der Gruppe mit ihren Suchpfaden. Aufrufer hält FWorkspacesLock.</summary>
    function GroupMembersOf(AWorkspace: TShellWorkspace): TArray<TMissingUnitProject>;
    /// <summary>Datei einer Unit aus dem Index, ohne nachzuladen; '' wenn unbekannt.</summary>
    function IndexUnitFile(AName: string): string;
    /// <summary>Präfixe neuer Namen für Refactorings in AUri: die der Namensregel, wenn sie für die Datei läuft
    /// (dieselbe Entscheidung wie in der Prüfung, TRuleEngine.NewNames).</summary>
    function NewNamesFor(const AUri: string): TPascalNamePrefixes;
    /// <summary>Inhalt des Status-Befehls (#28).</summary>
    function CollectBookmarks: TArray<TBookmarkHit>;
    function CollectStatus: TServerStatus;
    /// <summary>Status als JSON für atlas.server.status und das Diagnosepaket (#1356); AAnonymize ersetzt die
    /// Unit-Namen der langsamsten Units durch name#N und lässt die Pfade weg. Nicht anonym schreibt es ihn
    /// zusätzlich für get_server_status (MCP) in die Statusdatei.</summary>
    function StatusJson(AAnonymize: Boolean): TJSONObject;
    /// <summary>Teil des Servers im Diagnosepaket (#1356); AArguments optional [{"anonymize", "traceMinutes"}].
    /// </summary>
    function DiagnosticPackage(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Wurzeln der Arbeitsbereiche.</summary>
    function WorkspaceRoots: TArray<string>;
    /// <summary>Weg zum Compiler für den Status (#28, #261).</summary>
    procedure CollectCompilerStatus(var AStatus: TServerStatus);
    /// <summary>Prozess, Speicher je Bereich, Prüflauf, Warteschlangen und Cache-Treffer (#1356).</summary>
    procedure CollectDiagnosticsStatus(var AStatus: TServerStatus);
    /// <summary>Fehlerbericht (#108); AArguments optional [{"anonymize", "client", "target"}].</summary>
    function BugReport(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Wirksame Konfiguration je Arbeitsbereich als formatiertes JSON.</summary>
    function ConfigurationReport: string;
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
    /// <summary>Kennungen der Prüfregeln, die in Zeile ALine von AText treffen (/ignore, #297); False ohne
    /// Prüfregeln für die Datei.</summary>
    function SlashRuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
    /// <summary>Index und usesKeep für /sortuses (#297) und die uses-Diagnosen (#621); False, solange die
    /// Code-Aktionen fehlen.</summary>
    function UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
    /// <summary>Optionen des Graphen der Unit-Beziehungen (#593): Wurzel und Namensräume des Projekts der
    /// Datei, ohne Ausschlüsse der Architektur, damit „Wird verwendet von“ vollständig bleibt.</summary>
    function UnitRelationsOptionsFor(const AFileName: string): TUsesGraphOptions;
    /// <summary>Regeltreffer der Zeile ALine mit Erklärung aus dem Katalog und sicherer Korrektur (/fix,
    /// /explain, #300); False ohne Prüfregeln für die Datei.</summary>
    function SlashFindingsAt(const AUri, AText: string; ALine: Integer; out AFindings: TArray<TSlashFinding>): Boolean;
    /// <summary>"completeBlocks.docComment" (#88).</summary>
    function DocCommentsFor(const AUri: string): Boolean;
    function InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
    /// <summary>Einstellungen, Wurzel und Dateien für die Code-Metriken (#66): Datei, Projekt (.dproj/.dpr/.dpk),
    /// Ordner oder '' (einziger Arbeitsbereich).</summary>
    function MetricsSourceFor(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean;
    /// <summary>Arbeitsbereich für Metriken: Projekt der Projektdatei, sonst der der Datei bzw. der einzige.
    /// Aufrufer hält FWorkspacesLock.</summary>
    function MetricsWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Arbeitsbereich, dessen Projekt AFileName ist (.dproj, .dpr, .dpk). Aufrufer hält FWorkspacesLock.</summary>
    function ProjectWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Anfrage der Architekturübersicht (#1118) zum Arbeitsbereich von AFileName: Einstellungen, Wurzel,
    /// Titel, Namensräume und Dateien des Projekts (AScope "project") bzw. aller Projekte (sonst; leer =
    /// architecture.scope).</summary>
    function ArchitectureSourceFor(const AFileName, AScope: string; out ARequest: TArchitectureRequest;
      out ASettings: TServerSettings): Boolean;
    /// <summary>Projektdateien aller Arbeitsbereiche. Aufrufer hält FWorkspacesLock.</summary>
    function AllProjectFiles: TArray<string>;
    /// <summary>Namensräume des Arbeitsbereichs zu AFileName bzw. des einzigen. Aufrufer hält FWorkspacesLock.</summary>
    function NamespacesNear(const AFileName: string): TArray<string>;
    /// <summary>Datenquelle der Code-Abfragen (#1351): alle Projekte der Gruppe wie die Architekturübersicht,
    /// Wurzel und Namensräume des gewählten Arbeitsbereichs; False ohne Arbeitsbereich.</summary>
    function QuerySource(out ASource: TQuerySource): Boolean;
    /// <summary>Arbeitsbereich der Abfragen: aktiv in der IDE, sonst ausgewählt, sonst der erste.
    /// Aufrufer hält FWorkspacesLock.</summary>
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
    /// <summary>Projekte mit der Datei: das des Arbeitsbereichs, dann weitere. Aufrufer hält FWorkspacesLock.</summary>
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
    /// <summary>AFileName gehört zu keinem Projekt und liegt in der Delphi-Installation oder einem Bibliothekspfad
    /// (diagnostics.librarySources). Nur unter FWorkspacesLock.</summary>
    function IsLibrarySource(const AFileName: string): Boolean;
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
    /// <summary>WorkspaceOf unter FWorkspacesLock.</summary>
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
    CompileCommand = 'atlas.server.compile';
    SelectBuildCommand = 'atlas.server.selectBuild';
    SelectProjectCommand = 'atlas.server.selectProject';
    RebuildIndexCommand = 'atlas.server.rebuildIndex';
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
  System.Math,
  System.StrUtils,
  Atlas.Common.Product.Version,
  Atlas.Common.Query.Service,
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
  Shell.SlashHost,
  Shell.Workspace.Setup,
  Shell.Workspace.Jobs,
  Shell.Workspace.RuleProjects,
  Shell.VcsChanges,
  Shell.Hotspots,
  Shell.Bootstrap,
  Shell.Commands.Build,
  Shell.Commands.Index,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.LibrarySources,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Diagnostics.ServerPackage,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Lsp.DfmPropertyRules,
  Atlas.Common.Editing.SmartPaste,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.DfmProperties,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Dfm.BinaryForm,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Compiler.OutputParser,
  Atlas.Common.Projects.DelphiVersions,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Logging.RotatingFileStream,
  Atlas.Common.Projects.GroupReader,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Common.Index.Cache,
  Atlas.Common.JsonRpc.Messages;

const
  /// <summary>Ohne Zeitlimit warten (INFINITE, ohne Winapi.Windows).</summary>
  WaitForever = Cardinal($FFFFFFFF);
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
  FStartedAt := Now;
  FUptime := TStopwatch.StartNew;
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
      if not StartsText('file:', AUri) or (FWorkspacesLock = nil) then
      begin
        Exit;
      end;
      System.TMonitor.Enter(FWorkspacesLock);
      try
        mWorkspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if mWorkspace <> nil then
        begin
          Result := Result + [ExistingOrLegacyFile(mWorkspace.Root, ConfigurationFileName,
            LegacyConfigurationFileName)];
        end;
      finally
        System.TMonitor.Exit(FWorkspacesLock);
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
  FPullDiagnostics.Busy := ProjectIndexPending;
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

/// <summary>Schreibt eine resourcestring-Unit (#473) über den Slash-Host AHost. Eigene Routine, damit die Closure
/// nur AHost einfängt und nicht den Rahmen von WireEditing.</summary>
function ResourceStringWriteFor(const AHost: ISlashHost): TResourceStringWrite;
begin
  Result :=
    procedure(const AFileName, ANewText: string; const AEdit: TTextEdit)
    begin
      (AHost as TShellSlashHost).EditFile(TDocumentUris.FromPath(AFileName), AFileName, ANewText, AEdit);
    end;
end;

procedure TServerComposition.WireEditing;
var
  SlashHost: TShellSlashHost;
  KeepHost: ISlashHost;
begin
  FDocumentSymbols := TLspDocumentSymbols.Create(FDocuments);
  FDocumentSymbols.Attach(FDispatcher);
  FFoldingRanges := TLspFoldingRanges.Create(FDocuments);
  FFoldingRanges.Attach(FDispatcher);
  FFormatting := TLspFormatting.Create(FDocuments, FormatStyleFor,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileExists(AFileName);
      if Result then
      begin
        AText := TFileEncoding.LoadText(AFileName);
      end;
    end);
  FFormatting.SlashCommandsFor := SlashCommandsFor;
  FFormatting.DelphiVersionFor := LanguageLevelFor;
  FFormatting.DocCommentsFor := DocCommentsFor;
  SlashHost := TShellSlashHost.Create(TShellSlashSources.New(SlashWorkspaceOf, ReadSourceText, SlashHeaderTemplateOf),
    FTransport, FLogger, FDispatcher,
    // Die .dproj geht über das Plugin in die IDE, wenn der Client applyEdit kann (#397).
    function: Boolean
    begin
      Result := TLspApplyEdit.ClientSupports(FLifecycle.InitializeParams);
    end);
  // Neu laden nur im Thread der Nachrichtenschleife (Code-Review A-03); FConnection liest die Closure
  // erst beim Aufruf.
  SlashHost.RunInLoop :=
    procedure(const AWork: TProc)
    begin
      if (FConnection = nil) or not FConnection.Queue(AWork) then
      begin
        FLogger.Warning('Schnellbefehl: Projekt nicht neu geladen, die Verbindung ist beendet');
      end;
    end;
  // Testunit für /test (#295): dieselbe Suche wie die Code-Aktion aus #274.
  SlashHost.TestUnitOf := SlashTestUnitOf;
  // Protokollaufruf (#304) und Palettenseite (#299) aus der atlas.json des Ordners.
  SlashHost.SettingOf := SlashSettingOf;
  // /ignore und /sortuses (#297): Regeltreffer der Zeile und ungenutzte uses.
  SlashHost.RuleIdsOf := SlashRuleIdsAt;
  SlashHost.UsesContextOf := UsesContextFor;
  SlashHost.FindingsOf := SlashFindingsAt;
  FFormatting.SlashHost := SlashHost;
  // resourcestring in eine andere Unit (#473): Die Schnittstelle hält den Host am Leben. Eigene Routine: Im Rahmen
  // dieser Methode hielte die Closure den Host fest, der seinerseits Closures dieses Rahmens hält (Leck).
  KeepHost := SlashHost;
  FResourceStringWrite := ResourceStringWriteFor(KeepHost);
  FFormatting.Attach(FDispatcher);
  // Erzeugen-Menü (#719): dieselben Schalter, Versionen und derselbe Host wie die Schnellbefehle nach Enter.
  FSlashMenu := TLspSlashMenu.Create(FDocuments);
  FSlashMenu.SlashCommandsFor := SlashCommandsFor;
  FSlashMenu.DelphiVersionFor := LanguageLevelFor;
  FSlashMenu.SlashHost := SlashHost;
  // Einrückung wie beim Formatieren (#43), ohne Editor-Optionen: .editorconfig und "format".
  FSlashMenu.FormatStyleFor := ResolvedFormatStyleFor;
  FSelectionRanges := TLspSelectionRanges.Create(FDocuments);
  FSelectionRanges.Attach(FDispatcher);
end;

function TServerComposition.SlashWorkspaceOf(const AUri: string): TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Result := PickWorkspace(TDocumentUris.ToPath(AUri));
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.SlashHeaderTemplateOf(const AUri: string): string;
var
  mWorkspace: TShellWorkspace;
  mSettings: TServerSettings;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if mWorkspace = nil then
    begin
      Exit('');
    end;
    mSettings := mWorkspace.Configuration.Settings;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Eigene Vorlage der Schnellbefehle, sonst die der Regel file-header (#56).
  Result := mSettings.SlashHeaderTemplate;
  if Result = '' then
  begin
    Result := TFileHeaderRule.Template(TRuleEngine.RuleOptions('file-header', mSettings));
  end;
end;

function TServerComposition.SlashTestUnitOf(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
var
  mContext: TTestUnitContext;
  mTarget: TTestUnitTarget;
begin
  ATarget := Default(TSlashTestUnit);
  if not TestUnitContextFor(AUri, mContext) then
  begin
    ATarget.Reason := 'Datei gehört zu keinem Arbeitsbereich';
    Exit(False);
  end;
  mTarget := TLspTestUnits.Resolve(TDocumentUris.ToPath(AUri), AText, -1, mContext);
  ATarget.UnitName := mTarget.Counterpart;
  ATarget.TestProgram := mContext.TestProgram;
  if mTarget.UnitName = '' then
  begin
    ATarget.Reason := 'Die Datei ist keine Unit';
  end
  else if mTarget.IsTest then
  begin
    ATarget.Reason := 'Die Datei ist selbst eine Testunit';
  end
  else if mTarget.CounterpartFile <> '' then
  begin
    ATarget.FileName := mTarget.CounterpartFile;
    ATarget.Exists := True;
  end
  else if mTarget.CanCreate then
  begin
    ATarget.FileName := mTarget.NewFile;
  end
  else
  begin
    ATarget.Reason := mTarget.Reason;
  end;
  Result := ATarget.Reason = '';
end;

/// <summary>Abschnitt für neue Interface-Methoden als Text der Schnellbefehle.</summary>
function InterfaceSectionText(ASection: TCompletionInterfaceSection): string;
begin
  case ASection of
    TCompletionInterfaceSection.Private:
      Result := 'private';
    TCompletionInterfaceSection.Protected:
      Result := 'protected';
  else
    Result := 'public';
  end;
end;

/// <summary>Einstellung AName der Schnellbefehle als Text; leer, wenn es sie nicht gibt.</summary>
function SlashSettingValue(const ASettings: TServerSettings; const AName: string): string;
begin
  Result := '';
  if AName = TSlashSettings.LogCall then
  begin
    Result := ASettings.SlashLogCall;
  end
  else if AName = TSlashSettings.TodoOwner then
  begin
    Result := ASettings.SlashTodoOwner;
  end
  else if AName = TSlashSettings.TodoCategory then
  begin
    Result := ASettings.SlashTodoCategory;
  end
  else if AName = TSlashSettings.SortUsesRemoveUnused then
  begin
    Result := LowerCase(BoolToStr(ASettings.SlashSortUsesRemoveUnused, True));
  end
  else if AName = TSlashSettings.EnumHelper then
  begin
    Result := LowerCase(BoolToStr(ASettings.SlashEnumHelper, True));
  end
  else if AName = TSlashSettings.SetHelper then
  begin
    Result := LowerCase(BoolToStr(ASettings.SlashSetHelper, True));
  end
  else if AName = TSlashSettings.ComponentPalette then
  begin
    Result := ASettings.SlashComponentPalette;
  end
  else if AName = TSlashSettings.InterfaceSection then
  begin
    Result := InterfaceSectionText(ASettings.Completion.InterfaceSection);
  end;
end;

function TServerComposition.SlashSettingOf(const AUri, AName: string): string;
begin
  Result := SlashSettingValue(SettingsFor(AUri), AName);
end;

procedure TServerComposition.WireWorkspaces;
begin
  FWorkspaces := TObjectList<TShellWorkspace>.Create(True);
  FRuleProjectsStamp := -1;
  FLooseSettings := TServerSettings.Default;
  FWorkspacesLock := TObject.Create;
  FWorkspaceUsers := TDictionary<TShellWorkspace, Integer>.Create;
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
  FFormatting.Index := FIndex;
  // Standardsichtbarkeit published über die Vorfahren (#537).
  FDocumentSymbols.Index := FIndex;
  FDocumentSymbols.ReadText := ReadSourceText;
  FSlashMenu.Index := FIndex;
  FEndReason := TDiagnosticEndReason.InputClosed;
  FRequestTimeout := RequestTimeoutMs;
  FDiagnostics := TShellDiagnostics.Create(TShellDiagnostics.DefaultFolder, IntToStr(TShellPlatform.CurrentProcessId),
    FDocuments, FIndex);
  FDiagnosticsRef := FDiagnostics;
  FDiagnostics.TimeoutMs := CurrentRequestTimeout;
  FDiagnostics.IndexLoading :=
    function: Integer
    begin
      Result := IndexLoading;
    end;
  FDispatcher.Observer := FDiagnosticsRef;
end;

procedure TServerComposition.WireNavigation;
begin
  FDefinition := TLspDefinition.Create(FDocuments, FIndex,
    EnsureUnit);
  FDefinition.ReadText := ReadSourceText;
  FDefinition.Attach(FDispatcher);
  FHover := TLspHover.Create(FDocuments, FIndex,
    ReadSourceText,
    EnsureUnit);
  FHover.VersionProvider := DelphiVersionFor;
  FHover.HintsFor := HintSettingsFor;
  FHover.RationaleFor := RationaleOptionsFor;
  // Zustand und Herkunft bedingter Symbole (#102).
  FHover.SymbolsFor := ConditionalContextFor;
  FHover.Attach(FDispatcher);
  FWorkspaceSymbols := TLspWorkspaceSymbols.Create(FIndex);
  FBookmarks := TBookmarkStore.Create;
  FWorkspaceSymbols.BookmarksFor := CollectBookmarks;
  FWorkspaceSymbols.Attach(FDispatcher);
  FDocumentHighlights := TLspDocumentHighlights.Create(FDocuments, FIndex,
    EnsureUnit);
  FDocumentHighlights.SettingsFor := HighlightSettingsFor;
  FDocumentHighlights.Attach(FDispatcher);
  // Lokale Bezeichner brauchen den Index (#658).
  FLinkedEditing := TLspLinkedEditing.Create(FDocuments, FIndex, EnsureUnit);
  FLinkedEditing.Attach(FDispatcher);
  // Werte beim Debuggen am Zeilenende (#508).
  FInlineValues := TLspInlineValues.Create(FDocuments, FIndex, EnsureUnit);
  FInlineValues.Attach(FDispatcher);
  FCompilerSwitches := TLspCompilerSwitches.Create(FDocuments, CompilerSwitchContextFor);
  FCompilerSwitches.Attach(FDispatcher);
  FDebugUnavailable := TLspDebugUnavailable.Create(FDocuments, FIndex, EnsureUnit, CompilerSwitchContextFor);
  FDebugUnavailable.Attach(FDispatcher);
  FReferences := TLspReferences.Create(FDocuments, FIndex,
    ReadSourceText,
    ProjectSourceFiles,
    EnsureUnit);
  FReferences.SettingsFor := ReferenceSettingsFor;
  FReferences.Attach(FDispatcher);
  FRename := TLspRename.Create(FDocuments, FIndex,
    ReadSourceText,
    ProjectSourceFiles,
    EnsureUnit);
  FRename.SettingsFor := ReferenceSettingsFor;
  FRename.Attach(FDispatcher);
end;

function TServerComposition.HighlightSettingsFor(const AUri: string): THighlightSettings;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.Configuration.Settings.Highlight;
    end
    else
    begin
      Result := THighlightSettings.Default;
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
end;

procedure TServerComposition.WireCompletion;
begin
  FCompletion := TLspCompletion.Create(FDocuments, FIndex,
    EnsureUnit);
  FCompletion.MatchingFor := CompletionMatchingFor;
  // Abschnitt für Interface-Methoden (#466), Typumwandlung von Sender (#480).
  FCompletion.SettingsFor := CompletionSettingsFor;
  FCompletion.SlashCommandsFor := SlashCommandsFor;
  FCompletion.RuleIdsFor := SlashRuleIdsAt;
  // Postfix-Vorlagen (#188): abschaltbar mit completion.postfixTemplates; for var und var Name := nur, wenn die
  // Sprachversion Inline-Variablen kennt und refactoring.inlineVar sie nicht abschaltet.
  FCompletion.PostfixFor := PostfixOptionsFor;
  // with auflösen über Strg+Leer auf with (#50), abschaltbar mit refactoring.resolveWith.
  FCompletion.WithFor := CompletionWithEdits;
  // Methode aus Aufruf anlegen nach "(" bzw. mit Strg+Leer (#472), abschaltbar mit refactoring.createMethod.
  FCompletion.CreateFor := CompletionCreateMethod;
  // Präfix der Namensvorschläge (#452).
  FCompletion.NamingFor := NamingPrefixFor;
  // Für completionItem/resolve (Detailpanel von Atlas, #405); Anzeige von XMLDoc (#654).
  FCompletion.HintsFor := HintSettingsFor;
  // „Parameter abgleichen“ in ///-Blöcken (#88) hängt an completeBlocks.docComment.
  FCompletion.DocCommentsFor := DocCommentsFor;
  // Bedingte Symbole in {$IFDEF } und Co. (#102).
  FCompletion.SymbolsFor := ConditionalContextFor;
  FCompletion.ReadText := ReadSourceText;
  // Teilergebnisse (#616) als $/progress; Zeiten je Anfrage im Debug-Protokoll.
  FCompletion.Notify := NotifyClient;
  FCompletion.Log := LogDebug;
  FCompletion.Attach(FDispatcher);
  // Ausdrücke in den Debug-Dialogen (#538) mit denselben Einträgen wie im Editor.
  FExpressionCompletion := TLspExpressionCompletion.Create(FDocuments, FCompletion);
  FExpressionCompletion.Attach(FDispatcher);
  // „Interface implementieren“ im Erzeugen-Menü (#719, #466) wie in der Vervollständigung.
  FSlashMenu.Completion := FCompletion;
end;

function TServerComposition.CompletionMatchingFor(const AUri: string): TCompletionMatching;
begin
  Result := CompletionSettingsFor(AUri).Matching;
end;

function TServerComposition.PostfixOptionsFor(const AUri: string): TPostfixOptions;
begin
  // Postfix-Vorlagen (#188): abschaltbar mit completion.postfixTemplates; for var und var Name := nur, wenn die
  // Sprachversion Inline-Variablen kennt und refactoring.inlineVar sie nicht abschaltet.
  Result := TPostfixOptions.Default;
  Result.Enabled := CompletionSettingsFor(AUri).PostfixTemplates;
  Result.InlineVar := RefactoringSettingsFor(AUri).InlineVar and
    TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, LanguageLevelFor(AUri));
end;

function TServerComposition.CompletionWithEdits(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean;
var
  mContext: TRefactoringContext;
  mAction: TCodeAction;
begin
  AEdits := nil;
  mContext := FRefactorings.ContextFor(ARequest.Uri);
  Result := mContext.Settings.ResolveWith and TLspRefactorings.WithAction(ARequest.Resolver, ARequest.Tree,
    ARequest.Text, ARequest.Position, mContext, mAction);
  if Result then
  begin
    AEdits := mAction.Edits;
  end;
end;

function TServerComposition.CompletionCreateMethod(ARequest: TCompletionRequest; out ATitle, ADetail: string;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mContext: TRefactoringContext;
  mCreated: TCreatedMethod;
begin
  ATitle := '';
  ADetail := '';
  AEdits := nil;
  mContext := FRefactorings.ContextFor(ARequest.Uri);
  // Nur Änderungen in dieser Datei; die Klasse in einer anderen Unit bekommt die Code-Aktion.
  Result := mContext.Settings.CreateMethod and TLspRefactorings.CreateMethod(ARequest.Resolver, ARequest.Tree,
    ARequest.Text, ARequest.Position, mContext, True, mCreated) and (mCreated.FileEdits = nil);
  if Result then
  begin
    ATitle := mCreated.Title;
    ADetail := mCreated.Detail;
    AEdits := mCreated.Edits;
  end;
end;

function TServerComposition.NamingPrefixFor(const AUri: string; AKind: TNamingKind): string;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
  mContext: TIdeProjectContext;
begin
  // Vorgabe der Projektdatei .atlas aus dem Projektkontext der IDE, sonst die Zählung im Index.
  mWorkspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
  if (mWorkspace <> nil) and mWorkspace.State.Project(mProject) and FIdeProject.Find(mProject.FileName, mContext) and
    mContext.HasNaming[AKind] then
  begin
    Exit(mContext.Naming[AKind]);
  end;
  Result := TLspCompletion.NamingPrefix(FIndex, AKind);
end;

procedure TServerComposition.WireAnalysis;
begin
  FSignatureHelp := TLspSignatureHelp.Create(FDocuments, FIndex,
    ReadSourceText,
    EnsureUnit);
  // Platzhalter von Format und eigenen Formatroutinen (#451).
  FSignatureHelp.FormatRoutinesFor := FormatRoutinesFor;
  FSignatureHelp.Attach(FDispatcher);
  FHierarchies := TLspHierarchies.Create(FDocuments, FIndex,
    ReadSourceText,
    ProjectSourceFiles,
    EnsureUnit);
  FHierarchies.SettingsFor := ReferenceSettingsFor;
  FHierarchies.Attach(FDispatcher);
  FImpact := TImpactAnalysis.Create(FDocuments, FIndex,
    ReadSourceText,
    ProjectSourceFiles,
    EnsureUnit);
  FImpact.OptionsFor := ImpactOptionsFor;
  FImpact.Attach(FDispatcher);
  FDispatcher.RegisterConcurrentRequest(TAffectedTests.Method, HandleAffectedTests);
  FDataFlow := TLspDataFlow.Create(FDocuments, FIndex,
    ReadSourceText,
    ProjectSourceFiles,
    EnsureUnit);
  FDataFlow.Attach(FDispatcher);
  FAccessChains := TLspAccessChains.Create(FDocuments, FIndex,
    ReadSourceText,
    EnsureUnit);
  FAccessChains.Attach(FDispatcher);
  FImplementations := TLspImplementations.Create(FDocuments, FIndex,
    EnsureUnit);
  FImplementations.Attach(FDispatcher);
  FInlayHints := TLspInlayHints.Create(FDocuments, FIndex,
    ReadSourceText,
    InlayHintSettingsFor,
    EnsureUnit);
  FInlayHints.Attach(FDispatcher);
  FCodeLens := TLspCodeLens.Create(FDocuments, FIndex,
    ReadSourceText,
    ProjectSourceFiles,
    EnsureUnit);
  FCodeLens.MetricsFor := CodeLensMetricsFor;
  FCodeLens.Attach(FDispatcher);
  FMetrics := TLspMetrics.Create(MetricsSourceFor,
    ReadSourceText);
  // Vererbungstiefe in der Metrik-Linse des Plugins (#980).
  FMetrics.Index := FIndex;
  // Gleiche Quelle wie die Metriken: Einstellungen, Wurzel und Dateien des Projektmodells (#14).
  FTodos := TLspTodos.Create(MetricsSourceFor,
    ReadSourceText);
  WireOverviews;
  WireBaselines;
  FSemanticTokens := TLspSemanticTokens.Create(FDocuments, FIndex,
    EnsureUnit);
  FSemanticTokens.Attach(FDispatcher);
end;

procedure TServerComposition.WireOverviews;
begin
  // Architekturübersicht (#1118): Fundstellen der uses-Einträge mit den Defines des Projekts der Datei.
  FArchitectureService := TArchitectureService.Create(FIndex,
    ReadSourceText,
    DefinesOfFile);
  FArchitecture := TLspArchitecture.Create(FArchitectureService, ArchitectureSourceFor);
  FArchitecture.Attach(FDispatcher);
  // Code-Abfragen (#1351): ein Dienst für Fenster, Befehl und die Regeln query:<name>.
  FQueries := TCodeQueryService.Create(QuerySource);
  FQuery := TLspQuery.Create(FQueries, QuerySettingsFor);
  FQuery.Attach(FDispatcher);
  // Hotspots (#1354): Komplexität aus geöffneten Dokumenten bzw. der Platte, Verlauf über Shell.Hotspots.
  FHotspotService := THotspotService.Create(FIndex,
    ReadSourceText);
  FHotspots := TLspHotspots.Create(FHotspotService, HotspotSourceFor);
  FHotspots.Attach(FDispatcher);
  // Unit-Beziehungen (#593): Wurzel und Namensräume wie die Architektur; die uses-Analyse der Code-Aktionen
  // entsteht erst weiter unten, daher über UsesContextFor.
  FUnitRelationsGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
  FUnitRelations := TLspUnitRelations.Create(FUnitRelationsGraph,
    ReadSourceText,
    DefinesOfFile,
    UsesContextFor, UnitRelationsOptionsFor);
  FUnitRelations.Attach(FDispatcher);
  // Weg zwischen Symbolen (#1117): eigener Uses-Graph samt Bibliotheks-Units, Fundstellen wie oben.
  FSymbolPath := TLspSymbolPath.Create(FIndex,
    ReadSourceText,
    DefinesOfFile,
    EnsureUnit, SymbolPathSourceFor);
  FSymbolPath.Attach(FDispatcher);
  // Wertdarstellungen (#854): Dateien wie die TODO-Übersicht, Typen und Vorfahren aus dem Index.
  FDebugDisplay := TLspDebugDisplay.Create(MetricsSourceFor, ReadSourceText);
  FDebugDisplay.Index := FIndex;
  FEventHandlers := TLspEventHandlers.Create(MetricsSourceFor, ReadSourceText);
  FEventHandlers.Index := FIndex;
  // Rekursionssymbole im Editorrand (#623).
  FRecursion := TLspRecursion.Create(ReadSourceText);
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
      Result := FRename.Namespaces;
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

/// <summary>Code-Aktion für binär gespeicherte Formulare (#122): Umwandeln in Text.</summary>
function FormActionsFunc(): TFormActionsFunc;
begin
  Result :=
    function(const AUri, AText: string; const ARange: TTextRange): TArray<TCodeAction>
    var
      mAction: TCodeAction;
    begin
      Result := nil;
      if TFormModel.IsBinary(AText) then
      begin
        mAction := Default(TCodeAction);
        mAction.Title := 'Formular in Text umwandeln';
        mAction.Kind := QuickFixKind;
        mAction.IsPreferred := True;
        mAction.Command := TLspFormFiles.ConvertCommand;
        mAction.CommandArguments := [AUri];
        Result := [mAction];
      end;
    end;
end;

/// <summary>Was der Index über eine Unit für die uses-Analyse weiß; lädt sie bei Bedarf über AEnsureUnit.</summary>
function UsesInfoFunc(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc): TUsesUnitInfoFunc;
begin
  Result :=
    function(const AUnitName: string): TUsesUnitInfo
    var
      mUnit: TUnitIndex;
      mSymbol: TIndexSymbol;
    begin
      Result := Default(TUsesUnitInfo);
      AEnsureUnit(AUnitName);
      if not AIndex.FindUnit(AUnitName, mUnit) then
      begin
        Exit;
      end;
      Result.Known := True;
      Result.HasInitialization := mUnit.HasInitialization;
      for mSymbol in mUnit.Symbols do
      begin
        if mSymbol.InInterface then
        begin
          Result.Names := Result.Names + [mSymbol.Name];
        end;
      end;
    end;
end;

/// <summary>Units, die AName im interface auf oberster Ebene deklarieren.</summary>
function DeclaringFunc(const AIndex: ISymbolIndex): TUnitsDeclaringFunc;
begin
  Result :=
    function(const AName: string): TArray<string>
    var
      mLocation: TSymbolLocation;
    begin
      Result := nil;
      for mLocation in AIndex.FindSymbols(AName) do
      begin
        if mLocation.Symbol.InInterface and (mLocation.Symbol.Container = '') and
          (IndexText(mLocation.UnitName, Result) < 0) then
        begin
          Result := Result + [mLocation.UnitName];
        end;
      end;
    end;
end;

procedure TServerComposition.WireCodeActions;
begin
  FCodeActions := TLspCodeActions.Create(FDocuments, RuleContextFor);
  FCodeActions.FormActions := FormActionsFunc();
  FCodeActions.StringLiteralFor := StringLiteralFor;
  FCodeActions.DocCommentsFor := DocCommentsFor;
  // try/finally rückt wie das Formatieren ein (#42, #43).
  FCodeActions.FormatStyleFor := ResolvedFormatStyleFor;
  FCodeActions.RefactoringFor := RefactoringSettingsFor;
  FCodeActions.ClassActionContextFor := ClassActionContextOf;
  FCodeActions.MemberOrderFor := MemberOrderOf;
  FCodeActions.SortUsesFor := SortUsesOf;
  FCodeActions.SortUsesByNamespaceFor := SortUsesByNamespaceOf;
  FCodeActions.UsesContextFor := CodeActionUsesContext;
  FTestPrograms := TDictionary<string, TPair<string, UInt64>>.Create;
  FTestUnits := TLspTestUnits.Create(FDocuments, TestUnitContextFor);
  FCodeActions.DefinesFor := DefinesFor;
  FCodeActions.ExtraActions := ExtraCodeActions;
  FCodeActions.Attach(FDispatcher);
  FDocumentLinks := TLspDocumentLinks.Create(FDocuments, IncludePathsOf);
  FDocumentLinks.Attach(FDispatcher);
  FColors := TLspColors.Create(FDocuments, PlatformSystemColor);
  FColors.Attach(FDispatcher);
end;

function TServerComposition.ClassActionContextOf(const AUri: string): TClassActionContext;
begin
  Result := TClassActionContext.Default;
  Result.Index := FIndex;
  Result.DelphiVersion := LanguageLevelFor(AUri);
  Result.Uri := AUri;
  Result.Host := FFormatting.SlashHost;
end;

function TServerComposition.MemberOrderOf(const AUri: string): TMemberOrderSettings;
var
  mWorkspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if mWorkspace = nil then
    begin
      Result := TMemberOrderSettings.Default;
    end
    else
    begin
      Result := mWorkspace.Configuration.Settings.MemberOrder;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.SortUsesOf(const AUri: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    Result := (mWorkspace <> nil) and mWorkspace.Configuration.Settings.SortUses;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.SortUsesByNamespaceOf(const AUri: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    Result := (mWorkspace <> nil) and mWorkspace.Configuration.Settings.SortUsesByNamespace;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.CodeActionUsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AContext := Default(TUsesContext);
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if mWorkspace <> nil then
    begin
      AContext.Keep := mWorkspace.Configuration.Settings.UsesKeep;
      AContext.Namespaces := mWorkspace.State.Namespaces;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  AContext.Info := UsesInfoFunc(FIndex, FEnsureUnitRef);
  AContext.Declaring := DeclaringFunc(FIndex);
  Result := True;
end;

function TServerComposition.ExtraCodeActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := FTestUnits.Actions(AUri, ARange.StartPos.Line);
  Result := Result + FRefactorings.Actions(AUri, ARange);
end;

function TServerComposition.IncludePathsOf(const AUri: string): TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.State.IncludePaths;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

procedure TServerComposition.WireCommands;
begin
  // Methodenreferenz vorab: Free Pascal (Linux-Bau) bricht ab, wenn eine anonyme Methode die Methode selbst
  // als Referenz weitergibt.
  FEnsureUnitRef := EnsureUnit;
  FReadSourceTextRef := ReadSourceText;
  FReadResourceRef := ReadSourceText;
  FCommands := TLspCommands.Create;
  FCommands.Register(TLspFormFiles.ConvertCommand, RunConvertForms);
  FCommands.Register(TLspDfmPropertyRules.Command, ApplyDfmPropertyRules);
  FRefactorings.Register(FCommands);
  WireReportCommands;
  WireUnitCommands;
  // Austrittspunkte am Cursor für die Hervorhebung im Plugin (#698).
  FCommands.Register(TLspExitPoints.Command, RunExitPoints);
  // Neu zugewiesene Variablen für die Unterstreichung im Plugin (#712).
  FCommands.Register(TLspReassigned.Command, RunReassigned);
  // Typ des markierten Ausdrucks für das Tastenkürzel im Plugin (#689).
  FCommands.Register(TLspExpressionType.Command, RunExpressionType);
  // Methodenrümpfe in Deklarationsreihenfolge für Befehl und Einfügen im Plugin (#660).
  FCommands.Register(TLspMethodOrder.Command, RunMethodOrder);
  // Überschreibungen für die Atlas-Spalte der Zeilenleiste (#768).
  FCommands.Register(TLspOverrideMarks.Command, RunOverrideMarks);
  FCommands.Register(TLspBaseline.Command, RunBaseline);
  FCommands.Register(TLspBulkFix.Command, RunBulkFix);
  FCommands.Register(TLspCompilerBaseline.AddCommand, RunCompilerBaselineAdd);
  WireSlashCommands;
  FCommands.Register(TQualifiedNames.Command, RunQualifiedNames);
  FCommands.Register(TEnumValueCommands.Command, RunEnumValue);
  FCommands.Register(TResourceStringCommands.AddCommand, RunAddResourceString);
  FCommands.Register(TStringLiteralCommands.PlainTextCommand, RunPlainText);
  FCommands.Register(TStringLiteralCommands.ToLiteralCommand, RunToLiteral);
  WireServerCommands;
  FCommands.Attach(FDispatcher);
end;

procedure TServerComposition.WireReportCommands;
begin
  FCommands.Register(TLspMetrics.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FMetrics.Execute(AArguments);
    end);
  FCommands.Register(TLspTodos.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FTodos.Execute(AArguments);
    end);
  FCommands.Register(TLspArchitecture.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FArchitecture.Execute(AArguments);
    end);
  FCommands.Register(TLspArchitecture.SaveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FArchitecture.SaveReport(AArguments);
    end);
  FCommands.Register(TLspQuery.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FQuery.Execute(AArguments);
    end);
  // Hotspots (#1354): nebenläufig; gerechnet wird im Hintergrund, die Antwort kommt sofort (sonst "pending").
  FCommands.RegisterConcurrent(TLspHotspots.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FHotspots.Execute(AArguments);
    end);
  FCommands.RegisterConcurrent(TLspHotspots.SaveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FHotspots.SaveReport(AArguments);
    end);
end;

procedure TServerComposition.WireUnitCommands;
begin
  FCommands.Register(TLspUnitRelations.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Execute(AArguments);
    end);
  FCommands.Register(TLspUnitRelations.MoveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Move(AArguments);
    end);
  FCommands.Register(TLspUnitRelations.RemoveCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Remove(AArguments);
    end);
  FCommands.Register(TLspUnitRelations.CostCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.Cost(AArguments);
    end);
  FCommands.Register(TLspUnitRelations.UseUnitCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitRelations.UseUnitInfo(AArguments);
    end);
  FCommands.Register(TLspSymbolPath.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSymbolPath.Execute(AArguments);
    end);
  FCommands.Register(TLspDebugDisplay.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FDebugDisplay.Execute(AArguments);
    end);
  FCommands.Register(TLspEventHandlers.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FEventHandlers.Execute(AArguments);
    end);
  FCommands.Register(TLspRecursion.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FRecursion.Execute(AArguments);
    end);
end;

procedure TServerComposition.WireSlashCommands;
begin
  FCommands.Register(TLspCompilerBaseline.ClassifyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FBaselines.CompilerBaseline.ExecuteClassify(AArguments);
    end);
  FCommands.Register(TLspSlashMenu.MenuCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteMenu(AArguments);
    end);
  FCommands.Register(TLspSlashMenu.ChoicesCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteChoices(AArguments);
    end);
  FCommands.Register(TLspSlashMenu.RunCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FSlashMenu.ExecuteRun(AArguments);
    end);
  FCommands.Register(TLspTestUnits.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FTestUnits.Execute(AArguments);
    end);
  FUnitSearch := TUnitSearch.Create(UnitSearchContext);
  FCommands.Register(TUnitSearch.UnitsCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitSearch.ExecuteUnits(AArguments);
    end);
  FCommands.Register(TUnitSearch.PreviewCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitSearch.ExecutePreview(AArguments);
    end);
  FCommands.Register(TUnitSearch.AddUsesCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FUnitSearch.ExecuteAddUses(AArguments);
    end);
end;

procedure TServerComposition.WireServerCommands;
begin
  // Reine Lesebefehle laufen nebenläufig (#874): Status, Prüfung und Katalog der Einstellungen, Fehlerbericht.
  // Sie warten so nicht hinter einem Neuladen, während das Plugin auf die Antwort wartet.
  // Status (#28); Argument optional {"anonymize": true} (#1356, Fenster „Atlas-Server“ und Diagnosepaket).
  FCommands.RegisterConcurrent(StatusCommand, RunStatus);
  FCommands.RegisterConcurrent(TServerPackage.Command, DiagnosticPackage);
  // Prozesse am selben Index-Cache (#62): Sperre, Stand, Prozesse und Ereignisse.
  FCommands.RegisterConcurrent(ProcessesCommand, RunProcesses);
  // Einstellungsdialog des Plugins (#227): Prüfung mit dem Parser des Servers und Regelkatalog.
  FCommands.RegisterConcurrent(TLspSettingsCommands.CheckCommand, RunSettingsCheck);
  FCommands.RegisterConcurrent(TLspSettingsCommands.CatalogCommand, RunSettingsCatalog);
  FCommands.RegisterConcurrent(TBugReport.Command, BugReport);
  FCommands.Register(CompileCommand, RunCompile);
  FCommands.Register(RebuildIndexCommand, RunRebuildIndex);
  FCommands.Register(ClearIndexCommand, RunClearIndex);
  // „Erneut versuchen“ nach dem Überspringen (#1355): Argument Uri der Datei, ohne alle.
  FCommands.Register(TShellCrashCases.RetryCommand, RunRetryCrashCase);
  FCommands.Register(TLspPullDiagnostics.RecheckCommand, RunRecheck);
  FCommands.Register(SelectBuildCommand, RunSelectBuild);
  FCommands.Register(SelectProjectCommand, RunSelectProject);
end;

function TServerComposition.RunConvertForms(const AArguments: TJSONArray): TJSONValue;
var
  Converted, Backups: Integer;
begin
  // Mit URI eine Datei, sonst alle Formulare neben den Projekt-Units (Logik in Shell.Commands.Build).
  Converted := TBuildCommands.ConvertForms(TBuildCommands.FormFiles(AArguments, ProjectSourceFiles,
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end), FLogger, Backups);
  FLogger.Info(Format('%d binäre Formulare in Text umgewandelt, %d Sicherungskopien (.bak)',
    [Converted, Backups]));
  Result := TJSONString.Create(Format('%d Formulare umgewandelt', [Converted]));
end;

function TServerComposition.RunExitPoints(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspExitPoints.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, FReadSourceTextRef,
    FDocumentHighlights.SettingsFor, AArguments);
end;

function TServerComposition.RunReassigned(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspReassigned.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, AArguments);
end;

function TServerComposition.RunExpressionType(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspExpressionType.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, AArguments);
end;

function TServerComposition.RunMethodOrder(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspMethodOrder.Execute(FDocuments, AArguments);
end;

function TServerComposition.RunOverrideMarks(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspOverrideMarks.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, AArguments);
end;

function TServerComposition.RunBaseline(const AArguments: TJSONArray): TJSONValue;
var
  Watch: TStopwatch;
begin
  // Prüft das ganze Projekt: in großen Altprojekten dauert das; nur Zahlen ins Log, keine Pfade.
  Watch := TStopwatch.StartNew;
  Result := FBaselines.Baseline.Execute(AArguments);
  if Result is TJSONObject then
  begin
    FLogger.Info(Format('Baseline aktualisiert: %d Treffer, %d Dateien geprüft ' +
      '(%d neu, %d entfernt, %d ohne Datei), %d ms', [TJSONObject(Result).GetValue<Integer>('total', -1),
      TJSONObject(Result).GetValue<Integer>('files', -1), TJSONObject(Result).GetValue<Integer>('added', -1),
      TJSONObject(Result).GetValue<Integer>('removed', -1),
      TJSONObject(Result).GetValue<Integer>('orphaned.count', -1), Watch.ElapsedMilliseconds]));
  end;
end;

function TServerComposition.RunBulkFix(const AArguments: TJSONArray): TJSONValue;
var
  Watch: TStopwatch;
  Summary: string;
begin
  // Nur die Vorschau; geschrieben wird im Plugin. Ins Log nur Zahlen und Regeln, keine Pfade.
  Watch := TStopwatch.StartNew;
  Result := FBaselines.BulkFix.Execute(AArguments);
  if not (Result is TJSONObject) then
  begin
    Exit;
  end;
  Summary := TJSONObject(Result).GetValue<string>('summary', '');
  if Pos(sLineBreak, Summary) > 0 then
  begin
    Summary := Copy(Summary, 1, Pos(sLineBreak, Summary) - 1);
  end;
  FLogger.Info(Format('Sammelkorrektur berechnet (%s), %d ms', [Summary, Watch.ElapsedMilliseconds]));
end;

function TServerComposition.RunCompilerBaselineAdd(const AArguments: TJSONArray): TJSONValue;
begin
  Result := FBaselines.CompilerBaseline.ExecuteAdd(AArguments);
  if Result is TJSONObject then
  begin
    FLogger.Info(Format('Compilermeldungen in die Baseline: %d Einträge (%d neu, %d entfernt)',
      [TJSONObject(Result).GetValue<Integer>('total', -1), TJSONObject(Result).GetValue<Integer>('added', -1),
      TJSONObject(Result).GetValue<Integer>('removed', -1)]));
  end;
end;

function TServerComposition.RunQualifiedNames(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TQualifiedNames.Execute(FDocuments, FIndex,
    FEnsureUnitRef, FDefinition.Namespaces, AArguments);
end;

function TServerComposition.RunEnumValue(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TEnumValueCommands.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces,
    FReadSourceTextRef, AArguments);
end;

function TServerComposition.RunAddResourceString(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TResourceStringCommands.ExecuteAdd(FReadResourceRef, FResourceStringWrite, AArguments);
end;

function TServerComposition.RunPlainText(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TStringLiteralCommands.ExecutePlainText(FDocuments, AArguments);
end;

function TServerComposition.RunToLiteral(const AArguments: TJSONArray): TJSONValue;
var
  Settings: TStringLiteralSettings;
  Multiline: Boolean;
begin
  Settings := TStringLiteralSettings.Default;
  Multiline := False;
  if (AArguments <> nil) and (AArguments.Count > 0) then
  begin
    Settings := StringLiteralFor(AArguments.Items[0].Value, Multiline);
  end;
  Result := TStringLiteralCommands.ExecuteToLiteral(FDocuments, Settings, Multiline, AArguments);
end;

function TServerComposition.RunStatus(const AArguments: TJSONArray): TJSONValue;
var
  mAnonymize: Boolean;
begin
  mAnonymize := (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) and
    (TJSONObject(AArguments.Items[0]).GetValue('anonymize') is TJSONBool) and
    TJSONBool(TJSONObject(AArguments.Items[0]).GetValue('anonymize')).AsBoolean;
  Result := StatusJson(mAnonymize);
end;

function TServerComposition.RunProcesses(const AArguments: TJSONArray): TJSONValue;
var
  Workspaces: TArray<TLspProcessWorkspace>;
begin
  Workspaces := CollectProcesses;
  Result := TLspProcesses.ToJson(Workspaces, TShellPlatform.CurrentProcessId, Now);
  FLogger.Info(TLspProcesses.ToMarkdown(Workspaces, TShellPlatform.CurrentProcessId, Now));
end;

function TServerComposition.RunSettingsCheck(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspSettingsCommands.Check(AArguments);
end;

function TServerComposition.RunSettingsCatalog(const AArguments: TJSONArray): TJSONValue;
var
  Rule: IRule;
  Experimental: TArray<string>;
begin
  // Experimentelle Regeln (#834) kennt nur ihr Deskriptor; die Einstellungsseite (#909) markiert sie.
  Experimental := nil;
  for Rule in BuiltinRules do
  begin
    if Rule.Descriptor.Experimental then
    begin
      Experimental := Experimental + [Rule.Descriptor.Id];
    end;
  end;
  Result := TLspSettingsCommands.Catalog(TLspSettingsCommands.CatalogEntries(AArguments), FGlobalSettingsFile,
    Experimental);
end;

function TServerComposition.RunCompile(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Started: Boolean;
  Choice: TCompilerBackendChoice;
  Answer: TJSONObject;
begin
  // Optional die URI einer Datei, deren Projekt kompiliert wird.
  Uri := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    Uri := AArguments.Items[0].Value;
  end;
  if Uri = '' then
  begin
    Started := FCompile.Start('', True, Choice);
  end
  else
  begin
    Started := FCompile.Start(TDocumentUris.ToPath(Uri), True, Choice);
  end;
  // Ohne nutzbaren Compiler antwortet der Befehl immer mit Grund und Ausweg (#261).
  if not Started then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, Choice.MessageText);
  end;
  Answer := TJSONObject.Create;
  Answer.AddPair('started', TJSONBool.Create(True));
  Answer.AddPair('backend', TCompilerBackends.BackendText(Choice.Backend));
  Result := Answer;
end;

function TServerComposition.RunRebuildIndex(const AArguments: TJSONArray): TJSONValue;
var
  Workspace: TShellWorkspace;
  Targets: TArray<TShellWorkspace>;
begin
  // Alle Ordner ohne Cache neu einlesen (#49), z. B. nach Änderungen außerhalb des Editors.
  TMonitor.Enter(FWorkspacesLock);
  try
    Targets := FWorkspaces.ToArray;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  for Workspace in Targets do
  begin
    Workspace.Rebuild;
  end;
  FLogger.Info(Format('Index wird für %d Ordner neu aufgebaut', [Length(Targets)]));
  Result := TJSONNull.Create;
end;

function TServerComposition.RunClearIndex(const AArguments: TJSONArray): TJSONValue;
var
  Workspace: TShellWorkspace;
  Targets: TArray<TShellWorkspace>;
  Freed: Int64;
  Removed: Integer;
begin
  // „Index löschen“ (#492, Logik in Shell.Commands.Index): Caches freigeben, alle löschen, neu indizieren.
  TMonitor.Enter(FWorkspacesLock);
  try
    Targets := FWorkspaces.ToArray;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  for Workspace in Targets do
  begin
    Workspace.ReleaseCache;
  end;
  Removed := TIndexCommands.ClearCaches(TIndexCacheDirectory.DefaultRoot, Freed);
  FLogger.Info(Format('Index gelöscht: %d Caches, %d KB; %d Ordner werden neu indiziert',
    [Removed, Freed div 1024, Length(Targets)]));
  for Workspace in Targets do
  begin
    Workspace.Rebuild;
  end;
  Result := TIndexCommands.Answer(Removed, Freed);
end;

function TServerComposition.RunRetryCrashCase(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
begin
  mUri := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mUri := AArguments.Items[0].Value;
  end;
  Result := TJSONNumber.Create(FCrashCases.Retry(mUri));
end;

function TServerComposition.RunRecheck(const AArguments: TJSONArray): TJSONValue;
begin
  // Neue Generation (#1231): Alle Ergebnis-Ids veralten, auch die übersprungener Dateien (#1094); geöffnete
  // Dateien holt der Client nach dem refresh, die übrigen liefert workspace/diagnostic nach.
  FPullDiagnostics.Changed;
  FLogger.Info('Alle Dateien werden neu geprüft');
  Result := TJSONNull.Create;
end;

function TServerComposition.RunSelectBuild(const AArguments: TJSONArray): TJSONValue;
var
  Args: TSelectBuildArgs;
  Error: string;
  Workspace: TShellWorkspace;
  Targets: TArray<TShellWorkspace>;
  Project: TProjectInfo;
  Items: TJSONArray;
begin
  // Argumente und Antwort in Shell.Commands.Build; ohne Änderung nur die aktuelle Auswahl je Projekt (#46).
  Args := TSelectBuildArgs.Parse(AArguments);
  Targets := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    if Args.Uri <> '' then
    begin
      Workspace := WorkspaceOf(TDocumentUris.ToPath(Args.Uri));
      if Workspace <> nil then
      begin
        Targets := [Workspace];
      end;
    end
    else
    begin
      Targets := FWorkspaces.ToArray;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Args.Changes then
  begin
    for Workspace in Targets do
    begin
      if Workspace.State.Project(Project) and
        not Workspace.SelectBuild(Args.Config, Args.Platform, Args.Defines, Args.HasDefines, Error) then
      begin
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
      end;
    end;
  end;
  Items := TJSONArray.Create;
  for Workspace in Targets do
  begin
    if Workspace.State.Project(Project) then
    begin
      Items.AddElement(TBuildCommands.ProjectItem(Workspace.Name, Project, Args));
    end;
  end;
  Result := TJSONObject.Create(TJSONPair.Create('projects', Items));
end;

function TServerComposition.RunSelectProject(const AArguments: TJSONArray): TJSONValue;
var
  Args: TSelectProjectArgs;
  Targets: TArray<TShellWorkspace>;
  Items: TArray<TProjectChoiceItem>;
  mIndex: Integer;
  Active: string;
begin
  // Projekt für Dateien, die zu mehreren Projekten gehören (#46); gemerkt über Neustarts.
  Args := TSelectProjectArgs.Parse(AArguments);
  TMonitor.Enter(FWorkspacesLock);
  try
    Targets := nil;
    for mIndex := 0 to FWorkspaces.Count - 1 do
    begin
      if FWorkspaces[mIndex].State.ProjectFileName <> '' then
      begin
        Targets := Targets + [FWorkspaces[mIndex]];
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Active := FIdeProject.ActiveProject;
  SetLength(Items, Length(Targets));
  for mIndex := 0 to High(Targets) do
  begin
    Items[mIndex].Name := Targets[mIndex].Name;
    Items[mIndex].Project := Targets[mIndex].State.ProjectFileName;
    Items[mIndex].Active := SameText(Items[mIndex].Project, Active);
  end;
  if Args.HasProject and (Args.Project = '') then
  begin
    for mIndex := 0 to High(Targets) do
    begin
      FProjectSelection.SetProject(Targets[mIndex].Setup.Origin, '');
    end;
    FLogger.Info('Projektwahl aufgehoben');
  end
  else if Args.HasProject then
  begin
    mIndex := TBuildCommands.FindProject(Items, Args.Project);
    if mIndex < 0 then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
        Format('Projekt %s ist nicht geladen.', [Args.Project]));
    end;
    FProjectSelection.SetProject(Targets[mIndex].Setup.Origin, Items[mIndex].Project);
    FLogger.Info(Format('Projekt %s ausgewählt', [Items[mIndex].Name]));
  end;
  for mIndex := 0 to High(Targets) do
  begin
    Items[mIndex].Selected := IsSelectedProject(Targets[mIndex]);
  end;
  Result := TBuildCommands.ProjectChoices(Items);
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
      TMonitor.Enter(FWorkspacesLock);
      try
        Targets := FWorkspaces.ToArray;
      finally
        TMonitor.Exit(FWorkspacesLock);
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
  FProjectChoices := TDictionary<string, string>.Create;
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(AProject);
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.Root;
    end
    else
    begin
      Result := ExtractFileDir(AProject);
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    for mWorkspace in FWorkspaces do
    begin
      if SameText(mWorkspace.Setup.ProjectFile, AProject) or
        (mWorkspace.State.Project(mProject) and SameText(mProject.FileName, AProject)) then
      begin
        Result := Result + [mWorkspace];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  FHover.Markdown := TLspHover.ClientSupportsMarkdown(AParams);
  // Code-Vorlagen mit Platzhaltern nur an Clients mit snippetSupport (#51).
  FCompletion.SnippetSupport := TLspCompletion.ClientSupportsSnippets(AParams);
  FCompletion.DocumentationMarkdown := TLspCompletion.ClientPrefersMarkdown(AParams);
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
  for Workspace in FWorkspaces do
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
  FWorkspaces.Free;
  // Nach den Ordnern: Ihre Index-Threads melden Projektstufe und Ende.
  FIndexRecheck.Free;
  FWorkspaceUsers.Free;
  FWorkspacesLock.Free;
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
  FreeAndNil(FDocumentSymbols);
  FreeAndNil(FFoldingRanges);
  FreeAndNil(FLinkedEditing);
  FreeAndNil(FInlineValues);
  FreeAndNil(FCompilerSwitches);
  FreeAndNil(FDebugUnavailable);
  FreeAndNil(FFormatting);
  FreeAndNil(FSlashMenu);
  FreeAndNil(FSelectionRanges);
  FreeAndNil(FDefinition);
  FreeAndNil(FHover);
  FreeAndNil(FWorkspaceSymbols);
  FreeAndNil(FBookmarks);
  FreeAndNil(FDocumentHighlights);
  FreeAndNil(FReferences);
end;

procedure TServerComposition.FreeAnalysisFeatures;
begin
  FreeAndNil(FSemanticTokens);
  FreeAndNil(FCodeLens);
  FreeAndNil(FMetrics);
  FreeAndNil(FTodos);
  FreeAndNil(FSymbolPath);
  FreeAndNil(FArchitecture);
  FreeAndNil(FArchitectureService);
  FreeAndNil(FQuery);
  FQueries := nil;
  FreeAndNil(FHotspots);
  FreeAndNil(FHotspotService);
  FreeAndNil(FUnitRelations);
  FreeAndNil(FUnitRelationsGraph);
  FreeAndNil(FDebugDisplay);
  FreeAndNil(FEventHandlers);
  FreeAndNil(FRecursion);
  FreeAndNil(FBaselines);
  FreeAndNil(FInlayHints);
  FreeAndNil(FImplementations);
  FreeAndNil(FImpact);
  FreeAndNil(FAccessChains);
  FreeAndNil(FDataFlow);
  FreeAndNil(FHierarchies);
  FreeAndNil(FSignatureHelp);
end;

procedure TServerComposition.FreeCodeFeatures;
begin
  FreeAndNil(FExpressionCompletion);
  FreeAndNil(FCompletion);
  FreeAndNil(FRefactorings);
  FreeAndNil(FRename);
  FreeAndNil(FCodeActions);
  FreeAndNil(FTestUnits);
  FreeAndNil(FTestPrograms);
  FreeAndNil(FUnitSearch);
  FreeAndNil(FDocumentLinks);
  FreeAndNil(FColors);
  FreeAndNil(FCommands);
  FreeAndNil(FCompile);
  FCompilerProcess := nil;
  FreeAndNil(FWatchedFiles);
  FreeAndNil(FIdeBuild);
  FreeAndNil(FIdeProject);
  FreeAndNil(FProjectChoices);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    HasOthers := FWorkspaces.Count > 0;
    FGroupProjectFiles := FGroupProjectFiles + Projects;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
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
  if (AProjectFile <> '') and HasProjectWorkspace(AProjectFile) then
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    FWorkspaces.Add(mWorkspace);
    Inc(FWorkspacesStamp);
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
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

function TServerComposition.HasProjectWorkspace(const AProjectFile: string): Boolean;
var
  mExisting: TShellWorkspace;
begin
  Result := False;
  System.TMonitor.Enter(FWorkspacesLock);
  try
    for mExisting in FWorkspaces do
    begin
      if SameText(mExisting.Setup.ProjectFile, AProjectFile) then
      begin
        Exit(True);
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
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
  AWorkspace.Setup.OnGroupProjects := GroupProjectFiles;
  // requires-Packages als Quelle zuerst bei den Projekten der Gruppe suchen (#46).
  AWorkspace.Setup.OnPackageFolders := PackageFolders;
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

function TServerComposition.GroupProjectFiles: TArray<string>;
var
  mOther: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspacesLock);
  try
    // Auch Projekte, deren Arbeitsbereich erst nach diesem entsteht: Die Unit-Suche wird beim Laden gebaut.
    Result := FGroupProjectFiles;
    for mOther in FWorkspaces do
    begin
      if mOther.Setup.ProjectFile <> '' then
      begin
        Result := Result + [mOther.Setup.ProjectFile];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.PackageFolders: TArray<string>;
var
  mOther: TShellWorkspace;
begin
  Result := nil;
  System.TMonitor.Enter(FWorkspacesLock);
  try
    for mOther in FWorkspaces do
    begin
      if mOther.Setup.ProjectFile <> '' then
      begin
        Result := Result + [ExtractFileDir(mOther.Setup.ProjectFile)];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
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
  if (Length(ASettings.DfmPropertyRules) = 0) or ProjectIndexPending or (Length(FIndex.Units) = 0) then
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
  mRemoved := ExtractWorkspaces(AFolder.Key, mRemaining);
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
    FreeWhenUnused(mWorkspace);
  end;
  UpdateWatchedSettings;
  ProjectLoaded;
end;

function TServerComposition.ExtractWorkspaces(const AOrigin: string;
  out ARemaining: TArray<TShellWorkspace>): TArray<TShellWorkspace>;
var
  mIndex: Integer;
begin
  Result := nil;
  System.TMonitor.Enter(FWorkspacesLock);
  try
    for mIndex := FWorkspaces.Count - 1 downto 0 do
    begin
      if SameText(FWorkspaces[mIndex].Setup.Origin, AOrigin) then
      begin
        Result := Result + [FWorkspaces.Extract(FWorkspaces[mIndex])];
      end;
    end;
    ARemaining := FWorkspaces.ToArray;
    Inc(FWorkspacesStamp);
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
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

procedure TServerComposition.FreeWhenUnused(AWorkspace: TShellWorkspace);
begin
  // Erst freigeben, wenn keine Anfrage ihn mehr außerhalb der Sperre nutzt (EnsureUnit). Neue Anfragen
  // sehen ihn nicht mehr, das Warten endet also.
  System.TMonitor.Enter(FWorkspacesLock);
  try
    while FWorkspaceUsers.ContainsKey(AWorkspace) do
    begin
      System.TMonitor.Wait(FWorkspacesLock, WaitForever);
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
  AWorkspace.Free;
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Known := WorkspaceOf(AFileName) <> nil;
  finally
    TMonitor.Exit(FWorkspacesLock);
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

function TServerComposition.WorkspaceOf(const AFileName: string): TShellWorkspace;
var
  Folders: TArray<TWorkspaceFolder>;
  Workspace: TShellWorkspace;
  Candidates: TArray<TShellWorkspace>;
  mIndex: Integer;
begin
  // Die .dproj gehört zu ihrem eigenen Projekt (#46), auch wenn mehrere im selben Ordner liegen.
  if SameText(ExtractFileExt(AFileName), '.dproj') then
  begin
    for Workspace in FWorkspaces do
    begin
      if SameText(Workspace.State.ProjectFileName, AFileName) then
      begin
        Exit(Workspace);
      end;
    end;
  end;
  // Zuerst das Projekt, das die Datei enthält (#648); mehrere Projekte können im selben Ordner liegen,
  // und eine Unit kann in mehreren Projekten der Gruppe stehen (#46).
  Candidates := nil;
  for Workspace in FWorkspaces do
  begin
    if Workspace.State.ContainsFile(AFileName) then
    begin
      Candidates := Candidates + [Workspace];
    end;
  end;
  if Length(Candidates) = 1 then
  begin
    Exit(Candidates[0]);
  end;
  if Length(Candidates) > 1 then
  begin
    Exit(ChooseProject(AFileName, Candidates));
  end;
  Folders := nil;
  for Workspace in FWorkspaces do
  begin
    Folders := Folders + [TWorkspaceFolder.Create(Workspace.Root, Workspace.Name)];
  end;
  mIndex := TLspWorkspaceFolders.FolderOf(Folders, AFileName);
  if mIndex < 0 then
  begin
    Result := nil;
  end
  else
  begin
    Result := FWorkspaces[mIndex];
  end;
end;

function TServerComposition.IsSelectedProject(AWorkspace: TShellWorkspace): Boolean;
var
  Selected: string;
begin
  Selected := FProjectSelection.Project(AWorkspace.Setup.Origin);
  Result := (Selected <> '') and SameText(Selected, AWorkspace.State.ProjectFileName);
end;

function TServerComposition.ChooseProject(const AFileName: string;
  const ACandidates: TArray<TShellWorkspace>): TShellWorkspace;
var
  Workspace: TShellWorkspace;
  Active, Reason, Known: string;
begin
  Result := nil;
  Reason := '';
  for Workspace in ACandidates do
  begin
    if IsSelectedProject(Workspace) then
    begin
      Result := Workspace;
      Reason := 'ausgewählt';
      Break;
    end;
  end;
  Active := FIdeProject.ActiveProject;
  if (Result = nil) and (Active <> '') then
  begin
    for Workspace in ACandidates do
    begin
      if SameText(Workspace.State.ProjectFileName, Active) then
      begin
        Result := Workspace;
        Reason := 'aktiv in der IDE';
        Break;
      end;
    end;
  end;
  if Result = nil then
  begin
    Result := ACandidates[0];
    Reason := 'erstes der Gruppe';
  end;
  // Nur Wechsel ins Log, nicht jede Anfrage.
  if not FProjectChoices.TryGetValue(AnsiUpperCase(AFileName), Known) or not SameText(Known, Result.Name) then
  begin
    FProjectChoices.AddOrSetValue(AnsiUpperCase(AFileName), Result.Name);
    FLogger.Info(Format('%s gehört zu %d Projekten; es gilt %s (%s)',
      [ExtractFileName(AFileName), Length(ACandidates), Result.Name, Reason]));
  end;
end;

function TServerComposition.IsLibrarySource(const AFileName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
  mRoots, mProjectRoots: TArray<string>;
  mSources: TLibrarySources;
begin
  mRoots := nil;
  mProjectRoots := nil;
  for mWorkspace in FWorkspaces do
  begin
    if mWorkspace.State.ContainsFile(AFileName) then
    begin
      Exit(False);
    end;
    mProjectRoots := mProjectRoots + [mWorkspace.Root];
    if mWorkspace.State.BdsRoot <> '' then
    begin
      mRoots := mRoots + [mWorkspace.State.BdsRoot];
    end;
    mRoots := mRoots + mWorkspace.State.Install.LibraryPaths;
  end;
  mSources := TLibrarySources.Create(mRoots, mProjectRoots);
  Result := mSources.IsLibraryFile(AFileName);
end;

function TServerComposition.PickWorkspace(const AFileName: string): TShellWorkspace;
begin
  Result := TShellWorkspaces.Choose(WorkspaceOf(AFileName), FWorkspaces);
end;

function TServerComposition.SettingsFor(const AUri: string): TServerSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if Workspace = nil then
    begin
      Result := FLooseSettings;
    end
    else
    begin
      Result := Workspace.Configuration.Settings;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

procedure TServerComposition.SetEditorSettings(const AText: string);
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    FEditorSettings := AText;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

procedure TServerComposition.UpdateLooseSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := TConfigurationParser.Parse(TConfigurationScopes.Effective(FGlobalSettings, FEditorSettings, ''), Issues);
  TMonitor.Enter(FWorkspacesLock);
  try
    FLooseSettings := Settings;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.EnsureUnit(const AUnitName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
begin
  // Anfrage-Threads: jeder Ordner versucht es mit seinen Suchpfaden. Das Parsen läuft außerhalb von
  // FWorkspacesLock (#647): Sonst warteten alle Anfragen, die nur kurz einen Arbeitsbereich suchen
  // (Defines, Einstellungen, Diagnoselog), auf das Parsen einer Unit, und Hover dauerte Minuten.
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mTargets := FWorkspaces.ToArray;
    HoldWorkspaces(mTargets);
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
    ReleaseWorkspaces(mTargets);
  end;
end;

procedure TServerComposition.HoldWorkspaces(const AWorkspaces: TArray<TShellWorkspace>);
var
  mWorkspace: TShellWorkspace;
  mUsers: Integer;
begin
  for mWorkspace in AWorkspaces do
  begin
    if FWorkspaceUsers.TryGetValue(mWorkspace, mUsers) then
    begin
      FWorkspaceUsers[mWorkspace] := mUsers + 1;
    end
    else
    begin
      FWorkspaceUsers.Add(mWorkspace, 1);
    end;
  end;
end;

procedure TServerComposition.ReleaseWorkspaces(const AWorkspaces: TArray<TShellWorkspace>);
var
  mWorkspace: TShellWorkspace;
  mUsers: Integer;
begin
  System.TMonitor.Enter(FWorkspacesLock);
  try
    for mWorkspace in AWorkspaces do
    begin
      mUsers := FWorkspaceUsers[mWorkspace] - 1;
      if mUsers = 0 then
      begin
        FWorkspaceUsers.Remove(mWorkspace);
      end
      else
      begin
        FWorkspaceUsers[mWorkspace] := mUsers;
      end;
    end;
    System.TMonitor.PulseAll(FWorkspacesLock);
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.IndexLoading: Integer;
var
  Workspace: TShellWorkspace;
begin
  Result := -1;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      Result := Max(Result, Workspace.IndexLoading);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  if not ProjectIndexPending then
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
          TMonitor.Enter(FWorkspacesLock);
          try
            Workspaces := FWorkspaces.ToArray;
          finally
            TMonitor.Exit(FWorkspacesLock);
          end;
          for Workspace in Workspaces do
          begin
            Workspace.Configuration.Revalidate;
          end;
        end);
    end;
  end;
end;

function TServerComposition.ProjectIndexPending: Boolean;
var
  Workspace: TShellWorkspace;
begin
  Result := False;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      if Workspace.State.ProjectPending then
      begin
        Exit(True);
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.RuleProjects: TArray<TRuleProject>;
var
  Workspace: TShellWorkspace;
  Stamp, mIndex: Integer;
  Built: TArray<TRuleProject>;
  Project: TRuleProject;
  MainSources: TArray<string>;
  MainSource: string;
begin
  Built := nil;
  MainSources := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    if FRuleProjectsStamp = FWorkspacesStamp then
    begin
      Exit(FRuleProjects);
    end;
    Stamp := FWorkspacesStamp;
    for Workspace in FWorkspaces do
    begin
      if Workspace.State.RuleProject(Project, MainSource) then
      begin
        Built := Built + [Project];
        MainSources := MainSources + [MainSource];
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Hauptquelltexte und Formulardateien außerhalb der Sperre lesen (dieselbe Regel wie find_unused_code, #64).
  for mIndex := 0 to High(Built) do
  begin
    Built[mIndex] := TRuleProjectFiles.ProjectOf(Built[mIndex].FileName, MainSources[mIndex], Built[mIndex].Sources,
      ReadSourceText);
  end;
  TMonitor.Enter(FWorkspacesLock);
  try
    // Inzwischen ein anderes Projekt geladen: Das Ergebnis gilt für diese Prüfung, aber nicht als Vorrat.
    if Stamp = FWorkspacesStamp then
    begin
      FRuleProjects := Built;
      FRuleProjectsStamp := Stamp;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result := Built;
end;

function TServerComposition.RuleProjectsComplete(out AReason: string): Boolean;
var
  Workspace: TShellWorkspace;
begin
  AReason := '';
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      if not Workspace.RuleReady(AReason) then
      begin
        Exit(False);
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result := True;
end;

function TServerComposition.IncludeResolverFor(const AUri: string): TIncludeResolver;
var
  Workspace: TShellWorkspace;
  IncludePaths: TArray<string>;
begin
  IncludePaths := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if Workspace <> nil then
    begin
      IncludePaths := Workspace.State.IncludePaths;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Ohne Projekt sucht der Resolver im Ordner der Datei.
  Result := TIncludeFiles.Resolver(IncludePaths);
end;

function TServerComposition.DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  Workspace: TShellWorkspace;
begin
  ADefines := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    Result := (Workspace <> nil) and Workspace.State.Defines(ADefines);
    // Datei keinem Projekt zugeordnet oder dessen Projekt noch nicht geladen (Projektgruppe): wie das
    // aktive Projekt, das die IDE zuerst meldet. Sonst blieben inaktive Zweige dort ungedimmt (#615).
    if not Result and (FWorkspaces.Count > 0) then
    begin
      Result := FWorkspaces[0].State.Defines(ADefines);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
var
  mCandidates: TArray<string>;
  mFound: string;
begin
  AContext := Default(TTestUnitContext);
  if not TestUnitWorkspace(TDocumentUris.ToPath(AUri), AContext, mCandidates) then
  begin
    Exit(False);
  end;
  AContext.ReadText := SourceTextOrEmpty;
  AContext.Exists := DocumentOrFileExists;
  // Nur der Index: Diese Abfrage läuft bei jeder Code-Aktion und soll nichts nachladen.
  AContext.FindUnit := ProjectUnitFile;
  Result := True;
  if AContext.Settings.Project <> '' then
  begin
    mFound := AContext.Settings.Project;
    if not TPath.IsPathRooted(mFound) then
    begin
      mFound := TPath.Combine(AContext.Root, mFound);
    end;
    AContext.TestProgram := ChangeFileExt(ExpandFileName(mFound), '.dpr');
  end
  else if not CachedTestProgram(AContext.Root, AContext.TestProgram) then
  begin
    AContext.TestProgram := TTestUnits.FindTestProgram(mCandidates + DprFilesNear(AContext.Root), AContext.ReadText);
    StoreTestProgram(AContext.Root, AContext.TestProgram);
  end;
end;

function TServerComposition.TestUnitWorkspace(const AFileName: string; var AContext: TTestUnitContext;
  out ACandidates: TArray<string>): Boolean;
var
  mWorkspace, mOther: TShellWorkspace;
  mInfo: TProjectInfo;
begin
  ACandidates := nil;
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(AFileName);
    Result := mWorkspace <> nil;
    if not Result then
    begin
      Exit;
    end;
    AContext.Settings := mWorkspace.Configuration.Settings.TestUnits;
    AContext.Root := mWorkspace.Root;
    // Projekte der Gruppe zuerst, dann .dpr in der Wurzel und eine Ebene darunter.
    for mOther in FWorkspaces do
    begin
      if mOther.State.Project(mInfo) and (mInfo.MainSource <> '') then
      begin
        ACandidates := ACandidates + [mInfo.MainSource];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.SourceTextOrEmpty(const AFileName: string): string;
begin
  if not ReadSourceText(AFileName, Result) then
  begin
    Result := '';
  end;
end;

function TServerComposition.DocumentOrFileExists(const AFileName: string): Boolean;
var
  mDocument: ITextDocument;
begin
  Result := FileExists(AFileName) or FDocuments.TryGet(TDocumentUris.FromPath(AFileName), mDocument);
end;

function TServerComposition.ProjectUnitFile(const AUnitName: string): string;
var
  mUnit: TUnitIndex;
begin
  if FIndex.FindUnit(AUnitName, mUnit) and not mUnit.Library_ then
  begin
    Result := mUnit.FileName;
  end
  else
  begin
    Result := '';
  end;
end;

function TServerComposition.CachedTestProgram(const ARoot: string; out AProgram: string): Boolean;
const
  // Testprogramm höchstens so lange merken; ein neu angelegtes wird danach gefunden.
  cCacheMs = 10000;
var
  mCached: TPair<string, UInt64>;
begin
  System.TMonitor.Enter(FTestPrograms);
  try
    Result := FTestPrograms.TryGetValue(LowerCase(ARoot), mCached) and
      (TThread.GetTickCount64 - mCached.Value < cCacheMs);
  finally
    System.TMonitor.Exit(FTestPrograms);
  end;
  AProgram := '';
  if Result then
  begin
    AProgram := mCached.Key;
  end;
end;

procedure TServerComposition.StoreTestProgram(const ARoot, AProgram: string);
begin
  System.TMonitor.Enter(FTestPrograms);
  try
    FTestPrograms.AddOrSetValue(LowerCase(ARoot), TPair<string, UInt64>.Create(AProgram, TThread.GetTickCount64));
  finally
    System.TMonitor.Exit(FTestPrograms);
  end;
end;

function TServerComposition.DprFilesNear(const ARoot: string): TArray<string>;
var
  mFolder: string;
begin
  Result := nil;
  try
    Result := TDirectory.GetFiles(ARoot, '*.dpr', TSearchOption.soTopDirectoryOnly);
    for mFolder in TDirectory.GetDirectories(ARoot) do
    begin
      if not ExtractFileName(mFolder).StartsWith('.') then
      begin
        Result := Result + TDirectory.GetFiles(mFolder, '*.dpr', TSearchOption.soTopDirectoryOnly);
      end;
    end;
  except
    on E: EInOutError do
      FLogger.Debug('Testprojekt: Ordner nicht lesbar: ' + E.Message);
  end;
end;

/// <summary>Gibt es die Datei auf der Platte?</summary>
function FileOnDisk(AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
end;

/// <summary>Letzte Änderung der Datei; 0, wenn sie fehlt.</summary>
function FileModified(AFileName: string): TDateTime;
begin
  Result := 0;
  if FileExists(AFileName) then
  begin
    Result := TFile.GetLastWriteTime(AFileName);
  end;
end;

function TServerComposition.UnitSearchContext(out AContext: TUnitSearchContext): Boolean;
begin
  AContext := Default(TUnitSearchContext);
  AContext.Units := FIndex.Units;
  AContext.Projects := UnitSearchProjects;
  AContext.AncestorsOf := IndexAncestorsOf;
  AContext.Exists := FileOnDisk;
  AContext.ReadText := SearchSourceText;
  AContext.Modified := FileModified;
  AContext.GitState := SearchGitState;
  AContext.UsesFor := SearchUsesContext;
  Result := True;
end;

function TServerComposition.UnitSearchProjects: TArray<TUnitSearchProject>;
var
  mWorkspace: TShellWorkspace;
  mInfo: TProjectInfo;
  mProject: TUnitSearchProject;
  mText: string;
begin
  Result := nil;
  System.TMonitor.Enter(FWorkspacesLock);
  try
    for mWorkspace in FWorkspaces do
    begin
      mProject := Default(TUnitSearchProject);
      mProject.Files := mWorkspace.State.ProjectFiles;
      if mWorkspace.State.Project(mInfo) then
      begin
        mProject.FileName := mInfo.FileName;
        mProject.Name := ChangeFileExt(ExtractFileName(mInfo.FileName), '');
        mProject.IsTest := (mInfo.MainSource <> '') and ReadSourceText(mInfo.MainSource, mText) and
          TTestUnits.IsTestProgram(mText);
      end
      else
      begin
        mProject.Name := mWorkspace.Name;
      end;
      Result := Result + [mProject];
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.IndexAncestorsOf(AType: string): TArray<string>;
var
  mLocation: TSymbolLocation;
begin
  Result := nil;
  for mLocation in FIndex.FindSymbols(AType) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
    begin
      Exit(mLocation.Symbol.Ancestors);
    end;
  end;
end;

function TServerComposition.SearchSourceText(AFileName: string): string;
begin
  Result := SourceTextOrEmpty(AFileName);
end;

function TServerComposition.SearchGitState(AFileName: string): string;
begin
  Result := GitStateOf(AFileName);
end;

function TServerComposition.SearchUsesContext(AUri: string): TUsesContext;
var
  mProvider: TUsesContextProvider;
begin
  mProvider := FCodeActions.UsesContextFor;
  if not Assigned(mProvider) or not mProvider(AUri, Result) then
  begin
    Result := Default(TUsesContext);
  end;
end;

function TServerComposition.GitStateOf(const AFileName: string): string;
var
  Request: TCompilerRequest;
  Output: TArray<string>;
  Code: Integer;
begin
  Result := '';
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
  Request := Default(TCompilerRequest);
  Request.Executable := TVcsChanges.FindProgram('git.exe');
  Request.Arguments := ['status', '--porcelain', '--', ExtractFileName(AFileName)];
  Request.WorkingDir := ExtractFileDir(AFileName);
  Output := nil;
  try
    Code := FCompilerProcess.Run(Request,
      procedure(const ALine: string)
      begin
        Output := Output + [ALine];
      end);
  except
    // Ohne Git: kein Zustand.
    on E: Exception do
    begin
      FLogger.Debug('Git-Zustand nicht ermittelt: ' + E.ClassName);
      Exit;
    end;
  end;
  // Exit-Code 128: kein Repository.
  Result := TUnitSearch.GitState(Output, Code = 0);
end;

function TServerComposition.ProjectSourceFiles: TArray<string>;
var
  Workspace: TShellWorkspace;
  Document: ITextDocument;
  FileName: string;
begin
  Result := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      for FileName in Workspace.State.ProjectFiles do
      begin
        Result := Result + [FileName];
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
    System.TMonitor.Enter(FWorkspacesLock);
    try
      for mWorkspace in FWorkspaces do
      begin
        Result := Result + CheckFilesOf(mWorkspace, mSeen);
      end;
    finally
      System.TMonitor.Exit(FWorkspacesLock);
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mPicked := PickWorkspace(AFileName);
    for mWorkspace in FWorkspaces do
    begin
      if SameText(AScope, TLspDfmPropertyRules.ScopeGroup) or (mWorkspace = mPicked) then
      begin
        Result := Result + mWorkspace.State.ProjectFiles;
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(AFileName);
    Result := (Workspace <> nil) and Workspace.State.Project(AProject);
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  // Arbeitsbereich festhalten, die .dproj-Dateien aber außerhalb von FWorkspacesLock lesen (#647).
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(AFileName);
    if mWorkspace = nil then
    begin
      Exit(False);
    end;
    mGroup := GroupMembersOf(mWorkspace);
    HoldWorkspaces(TArray<TShellWorkspace>.Create(mWorkspace));
  finally
    System.TMonitor.Exit(FWorkspacesLock);
  end;
  try
    Result := mWorkspace.State.Project(mProject);
    if Result then
    begin
      ASetup := TShellWorkspaceJobs.MissingUnitSetupOf(mProject, mWorkspace.State.Install);
    end;
  finally
    ReleaseWorkspaces(TArray<TShellWorkspace>.Create(mWorkspace));
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
  for mOther in FWorkspaces do
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(FileName);
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
    TMonitor.Exit(FWorkspacesLock);
  end;
  Context.UnitName := ChangeFileExt(ExtractFileName(FileName), '');
  Result := TRuleEngine.NewNames(BuiltinRules, Settings, Context);
end;

function TServerComposition.CollectBookmarks: TArray<TBookmarkHit>;
var
  Files: TArray<string>;
  FileName: string;
  Document: ITextDocument;
  Stamp: Int64;
begin
  Files := ProjectSourceFiles;
  for FileName in Files do
  begin
    // Geöffnete Dateien nach Version (negativ), sonst nach Änderungszeit der Datei.
    if FDocuments.TryGet(TDocumentUris.FromPath(FileName), Document) then
    begin
      Stamp := -1 - Document.Version;
    end
    else if FileExists(FileName) then
    begin
      Stamp := Trunc(TFile.GetLastWriteTimeUtc(FileName) * MSecsPerDay);
    end
    else
    begin
      Stamp := 0;
    end;
    FBookmarks.Update(FileName, Stamp, ReadSourceText);
  end;
  FBookmarks.Retain(Files);
  Result := FBookmarks.All;
end;

function TServerComposition.ConfigurationReport: string;
var
  Root, Item, Effective, Choice: TJSONObject;
  Items: TJSONArray;
  Workspace: TShellWorkspace;
  Targets: TArray<TShellWorkspace>;
  Settings: TServerSettings;
  EditorSettings: string;
  Status: TWorkspaceStatus;

  function JsonOrText(const AText: string): TJSONValue;
  begin
    Result := nil;
    if AText.Trim <> '' then
    begin
      Result := TJSONObject.ParseJSONValue(AText);
    end;
    if (Result = nil) and (AText.Trim <> '') then
    begin
      Result := TJSONString.Create(AText);
    end;
    if Result = nil then
    begin
      Result := TJSONNull.Create;
    end;
  end;

begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Targets := FWorkspaces.ToArray;
    EditorSettings := FEditorSettings;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Root := TJSONObject.Create;
  try
    // Eingaben der Schichtung (Editor, dann atlas.json mit Vorrang) und die wichtigsten Ergebnisse.
    Root.AddPair('editor', JsonOrText(EditorSettings));
    Items := TJSONArray.Create;
    Root.AddPair('workspaces', Items);
    for Workspace in Targets do
    begin
      Item := TJSONObject.Create;
      Items.AddElement(Item);
      Item.AddPair('root', Workspace.Root);
      Item.AddPair('file', ExtractFileName(Workspace.Configuration.FileName));
      Item.AddPair('fileContent', JsonOrText(Workspace.Configuration.FileText));
      Settings := Workspace.Configuration.Settings;
      Effective := TJSONObject.Create;
      Item.AddPair('effective', Effective);
      Effective.AddPair('delphiVersion', Settings.DelphiVersion);
      Effective.AddPair('language', Settings.Language);
      Effective.AddPair('defaultEncoding', TJSONNumber.Create(Settings.DefaultEncoding));
      Effective.AddPair('project', Settings.Project);
      Effective.AddPair('config', Settings.Config);
      Effective.AddPair('platform', Settings.Platform);
      Effective.AddPair('profile', Settings.Profile);
      Effective.AddPair('rules', TJSONNumber.Create(Length(Settings.Rules)));
      Effective.AddPair('excludeTests', TJSONBool.Create(Settings.ExcludeTests));
      Effective.AddPair('exclude', TJSONNumber.Create(Length(Settings.Exclude)));
      // Projektwahl (#46): geladen, gewählt, aktiv, ausgewählt; Vorrang atlas.json < selectBuild < IDE.
      Status := Workspace.IndexStatus;
      Choice := TJSONObject.Create;
      Item.AddPair('projectChoice', Choice);
      Choice.AddPair('project', Status.Project);
      Choice.AddPair('config', Status.Config);
      Choice.AddPair('platform', Status.Platform);
      Choice.AddPair('buildChosen', TJSONBool.Create(Status.BuildChosen));
      Choice.AddPair('active', TJSONBool.Create((Status.Project <> '') and
        SameText(Status.Project, FIdeProject.ActiveProject)));
      Choice.AddPair('selected', TJSONBool.Create(IsSelectedProject(Workspace)));
    end;
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

const
  /// <summary>So viele Zeilen des Protokolls im Fehlerbericht (#108); das Diagnosepaket nimmt alle (#1356).</summary>
  BugReportLogLines = 200;
  /// <summary>Protokoll der Sitzung im Speicher für Fehlerbericht und Diagnosepaket (#1356).</summary>
  SessionLogLines = 10000;

/// <summary>Die letzten ACount Einträge von ALines.</summary>
function LastLines(const ALines: TArray<string>; ACount: Integer): TArray<string>;
begin
  if Length(ALines) <= ACount then
  begin
    Exit(ALines);
  end;
  Result := Copy(ALines, Length(ALines) - ACount, ACount);
end;

/// <summary>Optionen des Fehlerberichts aus dem ersten Argument: anonymize, client, target.</summary>
procedure ReadBugReportOptions(const AArguments: TJSONArray; var AInput: TBugReportInput; out ATarget: string);
var
  mOptions: TJSONObject;
begin
  ATarget := '';
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONObject) then
  begin
    Exit;
  end;
  mOptions := TJSONObject(AArguments.Items[0]);
  if mOptions.GetValue('anonymize') is TJSONBool then
  begin
    AInput.Anonymize := TJSONBool(mOptions.GetValue('anonymize')).AsBoolean;
  end;
  if mOptions.GetValue('client') is TJSONString then
  begin
    AInput.Client := mOptions.GetValue('client').Value;
  end;
  if mOptions.GetValue('target') is TJSONString then
  begin
    ATarget := mOptions.GetValue('target').Value;
  end;
end;

function TServerComposition.BugReport(const AArguments: TJSONArray): TJSONValue;
var
  mInput: TBugReportInput;
  mTarget, mText: string;
  mAnswer: TJSONObject;
begin
  mInput := Default(TBugReportInput);
  mInput.Anonymize := True;
  ReadBugReportOptions(AArguments, mInput, mTarget);
  mInput.ServerVersion := TProductVersion.Version;
  mInput.Created := Now;
  mInput.Configuration := ConfigurationReport;
  if FRecentLog <> nil then
  begin
    mInput.LogLines := LastLines(FRecentLog.Lines, BugReportLogLines);
  end;
  mInput.Requests := FStatistics.Recent;
  mInput.Workspaces := WorkspaceRoots;
  mInput.Identity := TProcessInfo.IdentityNames;
  mText := TBugReport.Build(mInput);
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('text', mText);
  if mTarget <> '' then
  begin
    ForceDirectories(ExtractFileDir(mTarget));
    TFile.WriteAllText(mTarget, mText, TEncoding.UTF8);
    mAnswer.AddPair('file', mTarget);
  end;
  FLogger.Info('Fehlerbericht erstellt');
  Result := mAnswer;
end;

function TServerComposition.CollectProcesses: TArray<TLspProcessWorkspace>;
var
  Targets: TArray<TShellWorkspace>;
  Workspace: TShellWorkspace;
  Item: TLspProcessWorkspace;
  Status: TWorkspaceStatus;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Targets := FWorkspaces.ToArray;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result := nil;
  for Workspace in Targets do
  begin
    Item := Default(TLspProcessWorkspace);
    if not Workspace.Cache.Processes(Item.CacheFile, Item.Processes) then
    begin
      Continue;
    end;
    Status := Workspace.IndexStatus;
    Item.Name := Workspace.Name;
    Item.Project := Status.Project;
    Item.FormatVersion := TIndexCache.FormatVersion;
    Item.Units := Status.Parsed + Status.FromCache;
    if TFile.Exists(Item.CacheFile) then
    begin
      Item.Saved := TFile.GetLastWriteTime(Item.CacheFile);
    end;
    Result := Result + [Item];
  end;
end;

function TServerComposition.CollectStatus: TServerStatus;
var
  Workspace: TShellWorkspace;
  Document: ITextDocument;
begin
  Result := Default(TServerStatus);
  Result.Units := FIndex.UnitCount;
  Result.Symbols := FIndex.SymbolCount;
  Result.MemoryBytes := AllocatedBytes;
  Result.IndexBytes := FIndex.MemoryBytes;
  Result.CompactUnits := FIndex.CompactCount;
  Result.OffloadedUnits := FIndex.OffloadedCount;
  Result.DiskBytes := TIndexCacheDirectory.TotalSize(TIndexCacheDirectory.DefaultRoot);
  Result.BudgetBytes := FIndex.Budget;
  for Document in FDocuments.Documents do
  begin
    Result.DocumentBytes := Result.DocumentBytes + Length(Document.Text) * SizeOf(Char);
  end;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      Result.Workspaces := Result.Workspaces + [Workspace.IndexStatus];
      // Projektwahl (#46): aktiv in der IDE und per selectProject ausgewählt.
      Result.Workspaces[High(Result.Workspaces)].Active := (Workspace.State.ProjectFileName <> '') and
        SameText(Workspace.State.ProjectFileName, FIdeProject.ActiveProject);
      Result.Workspaces[High(Result.Workspaces)].Selected := IsSelectedProject(Workspace);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result.Requests := FStatistics.Snapshot;
  CollectCompilerStatus(Result);
  CollectDiagnosticsStatus(Result);
end;

procedure TServerComposition.CollectDiagnosticsStatus(var AStatus: TServerStatus);
var
  mParts: TIndexMemoryParts;
  mTrees: TSyntaxTreeCacheStats;
  mIndexQueue: TIndexSchedulerQueue;
  mCheckQueue: TWorkspaceCheckQueue;
  mWorkspace: TWorkspaceStatus;
begin
  // Fenster „Atlas-Server“ (#1356): Prozess, Speicher je Bereich, Prüflauf, Warteschlangen, Cache-Treffer.
  AStatus.ProcessId := TShellPlatform.CurrentProcessId;
  AStatus.Version := TProductVersion.Version;
  AStatus.Started := FStartedAt;
  AStatus.UptimeMs := FUptime.ElapsedMilliseconds;
  mParts := FIndex.MemoryParts;
  mTrees := TSyntaxTreeCache.Stats;
  AStatus.Memory.Symbols := mParts.ProjectBytes;
  AStatus.Memory.Usages := mParts.UsageBytes;
  AStatus.Memory.LibraryUnits := mParts.LibraryBytes;
  AStatus.Memory.TreeCache := mTrees.Bytes;
  AStatus.Memory.Documents := AStatus.DocumentBytes;
  AStatus.Memory.Packages := TPackageCompiledFiles.Bytes;
  AStatus.Memory.Total := AStatus.MemoryBytes;
  AStatus.Memory.Budget := AStatus.BudgetBytes;
  AStatus.IndexCacheHitPercent := TServerStatus.CacheHitPercent(AStatus.Workspaces);
  AStatus.TreeCacheHitPercent := mTrees.HitPercent;
  AStatus.TreeCacheTrees := mTrees.Trees;
  mCheckQueue := Default(TWorkspaceCheckQueue);
  if FPullDiagnostics <> nil then
  begin
    AStatus.CheckRun := FPullDiagnostics.Check.Profile(TCheckRunProfile.cTop);
    mCheckQueue := FPullDiagnostics.Check.Queue;
  end;
  mIndexQueue := FIndexScheduler.Queue;
  AStatus.Queue.IndexWaiting := mIndexQueue.Waiting;
  AStatus.Queue.IndexRunning := mIndexQueue.Running;
  AStatus.Queue.CheckWaiting := mCheckQueue.Waiting;
  AStatus.Queue.CheckRunning := mCheckQueue.Running;
  AStatus.Queue.OldestWaitMs := Max(mIndexQueue.OldestWaitMs, mCheckQueue.OldestWaitMs);
  // Zustand: lädt, solange ein Arbeitsbereich seinen Index aufbaut; prüft, solange ein Prüflauf aktiv ist.
  AStatus.State := TServerStatus.StateReady;
  if AStatus.CheckRun.Active then
  begin
    AStatus.State := TServerStatus.StateChecking;
  end;
  for mWorkspace in AStatus.Workspaces do
  begin
    if mWorkspace.LastIndexMs < 0 then
    begin
      AStatus.State := TServerStatus.StateLoading;
    end;
  end;
end;

function TServerComposition.WorkspaceRoots: TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    for mWorkspace in FWorkspaces do
    begin
      Result := Result + [mWorkspace.Root];
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.StatusJson(AAnonymize: Boolean): TJSONObject;
var
  mStatus: TServerStatus;
  mAnonymizer: ILogAnonymizer;
begin
  mStatus := CollectStatus;
  if AAnonymize then
  begin
    mAnonymizer := FLogAnonymizer;
    mStatus.CheckRun := mStatus.CheckRun.Anonymized(
      function(const AName: string): string
      begin
        Result := AName;
        if mAnonymizer <> nil then
        begin
          Result := mAnonymizer.Anonymize(AName);
        end;
      end);
  end;
  FLogger.Info('Status:' + sLineBreak + mStatus.ToMarkdown);
  Result := mStatus.ToJson;
  // Für get_server_status (#1356): dieselben Zahlen wie das Fenster, nur lokal und nie anonym abgefragt.
  if not AAnonymize then
  begin
    TServerStatusFile.Write(TIndexCacheDirectory.DefaultRoot, TShellPlatform.CurrentProcessId, WorkspaceRoots,
      Result, Now);
  end;
end;

function TServerComposition.DiagnosticPackage(const AArguments: TJSONArray): TJSONValue;
var
  mInput: TServerPackageInput;
  mOptions: TJSONObject;
  mStatus: TJSONObject;
begin
  mInput := Default(TServerPackageInput);
  mInput.Anonymize := True;
  mInput.TraceMinutes := TServerPackage.DefaultTraceMinutes;
  mOptions := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
  begin
    mOptions := TJSONObject(AArguments.Items[0]);
  end;
  if mOptions <> nil then
  begin
    if mOptions.GetValue('anonymize') is TJSONBool then
    begin
      mInput.Anonymize := TJSONBool(mOptions.GetValue('anonymize')).AsBoolean;
    end;
    if mOptions.GetValue('traceMinutes') is TJSONNumber then
    begin
      mInput.TraceMinutes := TJSONNumber(mOptions.GetValue('traceMinutes')).AsInt;
    end;
  end;
  mStatus := StatusJson(mInput.Anonymize);
  try
    mInput.StatusJson := mStatus.ToJSON([]);
  finally
    mStatus.Free;
  end;
  if FRecentLog <> nil then
  begin
    mInput.LogLines := FRecentLog.Lines;
  end;
  mInput.Tracing := FTracing <> nil;
  if FTracing <> nil then
  begin
    mInput.TraceLines := FTracing.RecentLines(mInput.TraceMinutes, Now);
  end;
  mInput.Workspaces := WorkspaceRoots;
  mInput.Identity := TProcessInfo.IdentityNames;
  Result := TServerPackage.ToJson(TServerPackage.Build(mInput));
  FLogger.Info('Diagnosepaket des Servers erstellt');
end;

procedure TServerComposition.CollectCompilerStatus(var AStatus: TServerStatus);
begin
  FCompile.StatusOf(AStatus);
end;

function TServerComposition.SlashRuleIdsAt(const AUri, AText: string; ALine: Integer;
  out AIds: TArray<string>): Boolean;
var
  Context: TRuleCheckContext;
  Tree: TSyntaxTree;
  Finding: TRuleFinding;
begin
  AIds := nil;
  Result := RuleContextFor(AUri, Context);
  if not Result then
  begin
    Exit;
  end;
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    for Finding in TLspSyntaxDiagnostics.RuleFindings(AText, Tree, Context) do
    begin
      if (Finding.Range.StartPos.Line = ALine) and not SameText(Finding.RuleId, 'slash-command') and
        not MatchText(Finding.RuleId, AIds) then
      begin
        AIds := AIds + [Finding.RuleId];
      end;
    end;
  finally
    Tree.Free;
  end;
end;

function TServerComposition.SlashFindingsAt(const AUri, AText: string; ALine: Integer;
  out AFindings: TArray<TSlashFinding>): Boolean;
var
  Context: TRuleCheckContext;
  Tree: TSyntaxTree;
  Catalog: TRuleCatalog;
  Finding: TRuleFinding;
  Entry: TRuleCatalogEntry;
  Item: TSlashFinding;
  Action: TCodeAction;
begin
  AFindings := nil;
  Result := RuleContextFor(AUri, Context);
  if not Result then
  begin
    Exit;
  end;
  Tree := TSyntaxTreeCache.Parse(AText);
  Catalog := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
  try
    for Finding in TLspSyntaxDiagnostics.RuleFindings(AText, Tree, Context) do
    begin
      if (Finding.Range.StartPos.Line <> ALine) or SameText(Finding.RuleId, 'slash-command') then
      begin
        Continue;
      end;
      Item := Default(TSlashFinding);
      Item.RuleId := Finding.RuleId;
      Item.Message := Finding.Message;
      if Catalog.TryFind(Finding.RuleId, Entry) then
      begin
        Item.Explanation := TRuleCatalog.Explanation(Entry, #10);
      end;
      // Nur als sicher markierte Korrekturen, wie beim Speichern (#182).
      if TRuleCodeActions.FixAll([Finding], Action) then
      begin
        Item.SafeFix := Action.Edits;
      end;
      AFindings := AFindings + [Item];
    end;
  finally
    Catalog.Free;
    Tree.Free;
  end;
end;

function TServerComposition.UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := (FCodeActions <> nil) and Assigned(FCodeActions.UsesContextFor) and
    FCodeActions.UsesContextFor(AUri, AContext);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
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
    TMonitor.Exit(FWorkspacesLock);
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
  Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
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
    mResolver.Namespaces := FImpact.Namespaces;
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if mWorkspace = nil then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, 'Kein Arbeitsbereich zu ' + AUri);
    end;
    Result.WorkingDir := mWorkspace.Root;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  System.TMonitor.Enter(FWorkspacesLock);
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
    System.TMonitor.Exit(FWorkspacesLock);
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
    Result := WorkspaceOf(AFileName);
  end;
  Result := TShellWorkspaces.Choose(Result, FWorkspaces);
end;

function TServerComposition.ProjectWorkspaceOf(const AFileName: string): TShellWorkspace;
var
  mCandidate: TShellWorkspace;
  mProject: TProjectInfo;
begin
  for mCandidate in FWorkspaces do
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    if AFileName <> '' then
    begin
      Workspace := WorkspaceOf(AFileName);
    end;
    Workspace := TShellWorkspaces.Choose(Workspace, FWorkspaces);
    if Workspace <> nil then
    begin
      ANamespaces := Workspace.State.Namespaces;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  System.TMonitor.Enter(FWorkspacesLock);
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
    System.TMonitor.Exit(FWorkspacesLock);
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
  for mWorkspace in FWorkspaces do
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
    mWorkspace := WorkspaceOf(AFileName);
  end;
  mWorkspace := TShellWorkspaces.Choose(mWorkspace, FWorkspaces);
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
  System.TMonitor.Enter(FWorkspacesLock);
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
    for mCandidate in FWorkspaces do
    begin
      mRoot := TProjectPaths.CommonFolder(mRoot, mCandidate.Root);
    end;
    mReferences := mWorkspace.Configuration.Settings.References;
    // Projektgruppe (#648): die Dateien aller geladenen Projekte.
    mFiles := AllProjectFiles;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  for mCandidate in FWorkspaces do
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
  for mCandidate in FWorkspaces do
  begin
    if IsSelectedProject(mCandidate) then
    begin
      Exit(mCandidate);
    end;
  end;
  if FWorkspaces.Count > 0 then
  begin
    Result := FWorkspaces[0];
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    if AFileName <> '' then
    begin
      Workspace := WorkspaceOf(AFileName);
    end;
    Workspace := TShellWorkspaces.Choose(Workspace, FWorkspaces);
    if Workspace <> nil then
    begin
      Result.Root := Workspace.Root;
      Result.Namespaces := Workspace.State.Namespaces;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
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
    TMonitor.Exit(FWorkspacesLock);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(Result.FileName);
    if Workspace <> nil then
    begin
      IncludePaths := Workspace.State.IncludePaths;
      HasProject := Workspace.State.Project(Project);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(Result.FileName);
    if Workspace <> nil then
    begin
      IncludePaths := Workspace.State.IncludePaths;
      Result.HasProject := Workspace.State.Project(Project);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    Result := (Workspace <> nil) and Workspace.State.Project(Project);
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(AFileName);
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
      AContext.Services.Queries := FQueries;
      AProjects := ProjectsWithFile(mWorkspace, AFileName);
    end;
    // RTL, VCL und Komponenten außerhalb der Projekte (diagnostics.librarySources): Wer mit Strg+Klick in
    // System.Net.HttpClient.pas springt, soll dort keine Befunde zu fremdem Code sehen.
    ALibrary := not AContext.Settings.DiagnosticsLibrarySources and IsLibrarySource(AFileName);
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  for mOther in FWorkspaces do
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
  if not RuleProjectsComplete(mPending) then
  begin
    AContext.Services.Index := nil;
    AContext.Services.EnsureUnit := nil;
  end;
  AContext.Services.ProjectFiles := TRuleProjectFiles.Create(RuleProjects, FIndex, ReadSourceText,
    RuleProjectsComplete, FUsesGraph);
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    // Projekte für projektweite Prüfregeln neu bestimmen (#1102).
    Inc(FWorkspacesStamp);
    for mWorkspace in FWorkspaces do
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
    System.TMonitor.Exit(FWorkspacesLock);
  end;
end;

procedure TServerComposition.ApplyNamespaces(const ANamespaces: TArray<string>);
var
  mGraphOptions: TUsesGraphOptions;
begin
  FDefinition.Namespaces := ANamespaces;
  FHover.Namespaces := ANamespaces;
  // Uses-Graph (#64) löst Namen ohne Namensraum über dieselbe Liste auf; neu aufgebaut nur bei Änderung.
  mGraphOptions := FUsesGraph.Options;
  if string.Join(';', mGraphOptions.Namespaces) <> string.Join(';', ANamespaces) then
  begin
    mGraphOptions.Namespaces := ANamespaces;
    FUsesGraph.SetOptions(mGraphOptions);
  end;
  FDocumentHighlights.Namespaces := ANamespaces;
  FLinkedEditing.Namespaces := ANamespaces;
  FInlineValues.Namespaces := ANamespaces;
  FReferences.Namespaces := ANamespaces;
  FRename.Namespaces := ANamespaces;
  FCompletion.Namespaces := ANamespaces;
  FSignatureHelp.Namespaces := ANamespaces;
  FHierarchies.Namespaces := ANamespaces;
  FImpact.Namespaces := ANamespaces;
  FDataFlow.Namespaces := ANamespaces;
  FAccessChains.Namespaces := ANamespaces;
  FImplementations.Namespaces := ANamespaces;
  FInlayHints.Namespaces := ANamespaces;
  FCodeLens.Namespaces := ANamespaces;
  FSemanticTokens.Namespaces := ANamespaces;
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    Result := WorkspaceOf(AFileName);
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  System.TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := WorkspaceOf(AFileName);
    mOnSave := (mWorkspace <> nil) and mWorkspace.Configuration.Settings.Compiler.OnSave;
  finally
    System.TMonitor.Exit(FWorkspacesLock);
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
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := nil;
    if AFileName <> '' then
    begin
      mWorkspace := WorkspaceOf(AFileName);
    end;
    mWorkspace := TShellWorkspaces.Choose(mWorkspace, FWorkspaces);
    if mWorkspace = nil then
    begin
      AError := 'Kein Ordner mit Projekt geöffnet';
    end
    else if mWorkspace.CompileJob(AJob, AError) then
    begin
      AError := '';
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result := AError = '';
end;

procedure TServerComposition.HandleDidChangeConfiguration(const AParams: TJSONValue);
var
  Workspace: TShellWorkspace;
begin
  SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams));
  UpdateLooseSettings;
  for Workspace in FWorkspaces.ToArray do
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
  for Workspace in FWorkspaces.ToArray do
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
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      Files := Files + [Workspace.Configuration.PrimaryFileName, Workspace.Configuration.LegacyFileName];
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  for mWorkspace in FWorkspaces.ToArray do
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
  for mWorkspace in FWorkspaces.ToArray do
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
  Commands.Add(CompileCommand);
  Commands.Add(SelectBuildCommand);
  Commands.Add(SelectProjectCommand);
  Commands.Add(RebuildIndexCommand);
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
