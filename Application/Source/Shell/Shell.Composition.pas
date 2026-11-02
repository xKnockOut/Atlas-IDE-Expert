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
    /// <summary>Baseline für Altprojekte (#97): Befehl atlas.updateBaseline.</summary>
    FBaseline: TLspBaseline;
    FBulkFix: TLspBulkFix;
    /// <summary>Compilermeldungen in der Baseline (#530).</summary>
    FCompilerBaseline: TLspCompilerBaseline;
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
    /// <summary>Projekte zum Eintrag (#648): die genannte .dproj, die Projekte der genannten .groupproj oder
    /// der einzigen .groupproj eines Ordners ohne eindeutige .dproj; leer = bisheriges Verhalten.</summary>
    function ProjectsOf(const AFolder: TWorkspaceFolder): TArray<string>;
    /// <summary>Legt zur Datei den Ordner mit der nächsten Projektdatei an, falls sie in keinem Ordner liegt.</summary>
    procedure DeriveWorkspace(const AFileName: string);
    procedure RemoveWorkspace(const AFolder: TWorkspaceFolder);
    /// <summary>Teil von Create (S-02): Dispatcher mit Watchdog und Fehlerprotokoll, Lebenszyklus (initialize/shutdown).</summary>
    procedure WireProtocol;
    /// <summary>Teil von Create (S-02): Dokumentspeicher, Synchronisation, Syntax- und Pull-Diagnosen, Compilerergebnisse.</summary>
    procedure WireDocuments;
    /// <summary>Teil von WireDocuments (#1355): Absturzfälle und Sicherheitsnetz mit Dokumenten, Einstellungen
    /// und Benachrichtigung an den Client.</summary>
    procedure WireCrashCases;
    /// <summary>Compilerläufe (#40, #261) mit Weg über dcc oder die eigene IDE (cc.ps1).</summary>
    procedure WireCompile;
    /// <summary>Teil von Create (S-02): Dokumentbezogene Funktionen ohne Index: Symbole, Faltung, Formatierung, Schnellbefehle.</summary>
    procedure WireEditing;
    /// <summary>Teil von Create (S-02): Arbeitsbereiche, Indexplanung und Konfiguration ohne Ordner; Pfade für die Syntaxprüfung.</summary>
    procedure WireWorkspaces;
    /// <summary>Teil von Create (S-02): Symbolindex und Diagnoselog.</summary>
    procedure WireIndex;
    /// <summary>Teil von Create (S-02): Definition, Hover, Arbeitsbereichssymbole, Hervorhebungen, Verweise, Umbenennen.</summary>
    procedure WireNavigation;
    /// <summary>Teil von Create (S-02): Vervollständigung mit Einstellungen, Postfix-Vorlagen und Teilergebnissen.</summary>
    procedure WireCompletion;
    /// <summary>Teil von Create (S-02): Signaturhilfe, Hierarchien, Implementierungen, Inlay-Hints, CodeLens, Metriken, TODOs, Baseline, Semantic Tokens.</summary>
    procedure WireAnalysis;
    /// <summary>Teil von Create (S-02): Refactorings und Befehle des Debuggers (Shell.Composition.Refactorings).
    /// </summary>
    procedure WireRefactorings;
    /// <summary>Teil von Create (S-02): Code-Aktionen, Testunits, Dokumentlinks und Farben.</summary>
    procedure WireCodeActions;
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
    /// <summary>Teil von Create (S-02): Arbeitsbereichsordner und Ereignisse nach initialized.</summary>
    procedure WireWorkspaceFolders;
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
    /// <summary>Dateizugriffe für atlas.updateBaseline (#97): schreibt UTF-8 ohne BOM wie --update-baseline.</summary>
    function BaselineFiles: TLspBaselineFiles;
    /// <summary>Muster, Ordner und Testprogramm für Testunits zur Datei (#274, #189).</summary>
    function TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
    /// <summary>Index, Projekte und Dateizugriffe für „Units suchen“ (#777).</summary>
    function UnitSearchContext(out AContext: TUnitSearchContext): Boolean;
    /// <summary>Git-Zustand einer Datei für die Vorschau (#777); '' ohne Git oder Repository.</summary>
    function GitStateOf(const AFileName: string): string;
    /// <summary>Projektdateien aller Ordner und geöffnete Dokumente, für Referenzen und Umbenennen.</summary>
    function ProjectSourceFiles: TArray<string>;
    /// <summary>Dateien der Projektprüfung: ProjectSourceFiles ohne Testunits, wenn excludeTests gilt.</summary>
    function CheckSourceFiles: TArray<string>;
    /// <summary>Befehl „Eigenschaftsregeln anwenden“ (#309): WorkspaceEdit über die Formulardateien.</summary>
    function ApplyDfmPropertyRules(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Projekt der Datei AFileName für Umbauten mit neuen Units; False ohne Projekt.</summary>
    function RefactoringProject(const AFileName: string; out AProject: TProjectInfo): Boolean;
    /// <summary>Suche nach AUnitName im Projekt der Datei AFileName vorbereiten (#550).</summary>
    function MissingUnitSetupFor(const AFileName, AUnitName: string; out ASetup: TMissingUnitSetup): Boolean;
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
    /// <summary>Anfrage der Architekturübersicht (#1118) zum Arbeitsbereich von AFileName: Einstellungen, Wurzel,
    /// Titel, Namensräume und Dateien des Projekts (AScope "project") bzw. aller Projekte (sonst; leer =
    /// architecture.scope).</summary>
    function ArchitectureSourceFor(const AFileName, AScope: string; out ARequest: TArchitectureRequest;
      out ASettings: TServerSettings): Boolean;
    /// <summary>Datenquelle der Code-Abfragen (#1351): alle Projekte der Gruppe wie die Architekturübersicht,
    /// Wurzel und Namensräume des gewählten Arbeitsbereichs; False ohne Arbeitsbereich.</summary>
    function QuerySource(out ASource: TQuerySource): Boolean;
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
    /// <summary>"stringLiteral" für AUri; AMultiline nach Stil und Delphi-Version (#312).</summary>
    function StringLiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
    function FormatStyleFor(const AUri: string): TFormatStyle;
    /// <summary>Formatstil mit .editorconfig, ohne Editor-Optionen (#43); für Schnellbefehle und try/finally.</summary>
    function ResolvedFormatStyleFor(const AUri: string): TFormatStyle;
    function RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
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
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    /// <summary>Auftrag für das Projekt zu AFileName ('' = einziger Ordner); False ohne Projekt oder Installation
    /// (Grund in AError).</summary>
    function CompileJobFor(const AFileName: string; out AJob: TShellCompileJob; out AError: string): Boolean;
    /// <summary>Beenden: Index-Threads aller Ordner anhalten; nil-sicher.</summary>
    procedure StopIndexThreads;
    /// <summary>Beenden: gibt Features, Ordner und Index frei.</summary>
    procedure FreeFeatures;
    procedure HandleDidChangeConfiguration(const AParams: TJSONValue);
    /// <summary>Dateiänderungen von außen: Projektdateien laden das Projekt neu, Quelltexte aktualisieren den Index.</summary>
    procedure HandleWatchedFiles(const AChanges: TArray<TFileChange>);
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
  Atlas.Common.Index.Adapters.DiskFileSystem,
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
  Shell.AffectedTests,
  Atlas.Common.Lsp.AffectedTests,
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
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Metrics.Contract,
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
  mWatchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, RequestTimeoutMs,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
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
    end);
  // Absturzfall auch beim Abbruch durch den Watchdog (#1355); läuft im Thread des Watchdogs.
  mWatchdog.OnExpired :=
    procedure(const AId, AMethod: string; ATimeoutMs: Cardinal)
    begin
      if FCrashCases <> nil then
      begin
        FCrashCases.TimedOut(AId, AMethod, ATimeoutMs);
      end;
    end;
  FDispatcher.Watchdog := mWatchdog;
  // Sicherheitsnetz (#1355): eine Anfrage, die an derselben unveränderten Datei zweimal abstürzte, überspringen.
  FDispatcher.RequestGuard :=
    procedure(const AMethod: string; const AParams: TJSONValue)
    begin
      if FCrashCases <> nil then
      begin
        FCrashCases.Guard(AMethod, AParams);
      end;
    end;
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    var
      Params: string;
    begin
      Params := '';
      if AParams <> nil then
      begin
        Params := AParams.ToJSON;
      end;
      if Length(Params) > 500 then
      begin
        Params := Copy(Params, 1, 500) + '…';
      end;
      FLogger.Error(Format('Anfrage %s fehlgeschlagen: %s: %s%sParameter: %s%s%s',
        [AMethod, AError.ClassName, AError.Message, sLineBreak, Params, sLineBreak, TShellPlatform.StackTraceOf(AError)]));
      // Nachstellbarer Fall (#1355): Anfrage, Datei, Stapel; danach Meldung an den Client.
      if FCrashCases <> nil then
      begin
        FCrashCases.RequestFailed(AMethod, AParams, AError, TShellPlatform.StackTraceOf(AError));
      end;
    end;
  FLifecycle := TLspLifecycle.Create(TProductVersion.Name, TProductVersion.Version,
    function: TJSONObject
    begin
      Result := BuildCapabilities;
      // Pull-Diagnosen nur für Clients, die sie können; sonst bleibt es bei publishDiagnostics (#82).
      if TLspPullDiagnostics.ClientSupportsPull(FLifecycle.InitializeParams) then
      begin
        Result.AddPair('diagnosticProvider', TLspPullDiagnostics.Capability);
        FPullDiagnostics.RefreshSupport := TLspPullDiagnostics.ClientSupportsRefresh(FLifecycle.InitializeParams);
        FSyntaxDiagnostics.PullMode := True;
      end;
    end);
  FLifecycle.Attach(FDispatcher);
  // Ändert der Client ein Dokument, sind laufende Anfragen dazu überholt (#283).
  FDispatcher.PendingRequests.AddContentChangeMethod('textDocument/didChange');
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
  FCrashCases.Notify :=
    procedure(const AMethod: string; AParams: TJSONObject)
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

procedure TServerComposition.WireDocuments;
begin
  FDocuments := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
    end);
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FDispatcher);
  WireCrashCases;
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport, SyntaxDiagnosticsProviders);
  FSyntaxDiagnostics.OnError :=
    procedure(AError: Exception)
    begin
      FLogger.Error(Format('Fehler beim Prüfen der Syntax: %s: %s', [AError.ClassName, AError.Message]));
    end;
  WireCompile;
  FSyntaxDiagnostics.Attach;
  FIndexRecheck := TWorkspaceCheckIndexGate.Create;
  FPullDiagnostics := TLspPullDiagnostics.Create(FDocuments, FSyntaxDiagnostics, FTransport, CheckSourceFiles,
    function(const AFileName: string; out AStamp: Int64): Boolean
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
    end,
    function(const AFileName: string; out AText: string): Boolean
    var
      FileFormat: TFileFormat;
    begin
      Result := TFile.Exists(AFileName);
      if Result then
      begin
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat);
      end
      else
      begin
        AText := '';
      end;
    end);
  FPullDiagnostics.Busy :=
    function: Boolean
    begin
      Result := ProjectIndexPending;
    end;
  // Unit im Diagnoselog nur anonym (#1094); das Diagnoselog entsteht erst später.
  FPullDiagnostics.FileLabel :=
    function(const AFileName: string): string
    begin
      Result := 'unit';
      if FDiagnostics <> nil then
      begin
        Result := FDiagnostics.FileLabel(AFileName);
      end;
    end;
  // Long-Polling endet vor dem Zeitlimit des Watchdogs (Code-Review P-14).
  FPullDiagnostics.RequestTimeout :=
    function: Cardinal
    begin
      Result := FRequestTimeout;
    end;
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
  FPullDiagnostics.Check.Dependents :=
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
      if FIndex <> nil then
      begin
        Result := TLspWorkspaceCheck.DependentsOf(FIndex.Units, AFileName);
      end;
    end;
  FPullDiagnostics.Check.OnLog :=
    procedure(const AMessage: string)
    begin
      FLogger.Info(AMessage);
    end;
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
  SlashHost := TShellSlashHost.Create(TShellSlashSources.New(
    function(const AUri: string): TShellWorkspace
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Result := PickWorkspace(TDocumentUris.ToPath(AUri));
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end,
    ReadSourceText,
    function(const AUri: string): string
    var
      Workspace: TShellWorkspace;
      Settings: TServerSettings;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        if Workspace = nil then
        begin
          Exit('');
        end;
        Settings := Workspace.Configuration.Settings;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      // Eigene Vorlage der Schnellbefehle, sonst die der Regel file-header (#56).
      Result := Settings.SlashHeaderTemplate;
      if Result = '' then
      begin
        Result := TFileHeaderRule.Template(TRuleEngine.RuleOptions('file-header', Settings));
      end;
    end), FTransport, FLogger, FDispatcher,
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
  SlashHost.TestUnitOf :=
    function(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean
    var
      Context: TTestUnitContext;
      Target: TTestUnitTarget;
    begin
      ATarget := Default(TSlashTestUnit);
      if not TestUnitContextFor(AUri, Context) then
      begin
        ATarget.Reason := 'Datei gehört zu keinem Arbeitsbereich';
        Exit(False);
      end;
      Target := TLspTestUnits.Resolve(TDocumentUris.ToPath(AUri), AText, -1, Context);
      ATarget.UnitName := Target.Counterpart;
      ATarget.TestProgram := Context.TestProgram;
      if Target.UnitName = '' then
      begin
        ATarget.Reason := 'Die Datei ist keine Unit';
      end
      else if Target.IsTest then
      begin
        ATarget.Reason := 'Die Datei ist selbst eine Testunit';
      end
      else if Target.CounterpartFile <> '' then
      begin
        ATarget.FileName := Target.CounterpartFile;
        ATarget.Exists := True;
      end
      else if Target.CanCreate then
      begin
        ATarget.FileName := Target.NewFile;
      end
      else
      begin
        ATarget.Reason := Target.Reason;
      end;
      Result := ATarget.Reason = '';
    end;
  // Protokollaufruf (#304) und Palettenseite (#299) aus der atlas.json des Ordners.
  SlashHost.SettingOf :=
    function(const AUri, AName: string): string
    var
      Workspace: TShellWorkspace;
      Settings: TServerSettings;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        if Workspace = nil then
        begin
          Settings := FLooseSettings;
        end
        else
        begin
          Settings := Workspace.Configuration.Settings;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      if AName = TSlashSettings.LogCall then
      begin
        Result := Settings.SlashLogCall;
      end
      else if AName = TSlashSettings.TodoOwner then
      begin
        Result := Settings.SlashTodoOwner;
      end
      else if AName = TSlashSettings.TodoCategory then
      begin
        Result := Settings.SlashTodoCategory;
      end
      else if AName = TSlashSettings.SortUsesRemoveUnused then
      begin
        Result := LowerCase(BoolToStr(Settings.SlashSortUsesRemoveUnused, True));
      end
      else if AName = TSlashSettings.EnumHelper then
      begin
        Result := LowerCase(BoolToStr(Settings.SlashEnumHelper, True));
      end
      else if AName = TSlashSettings.SetHelper then
      begin
        Result := LowerCase(BoolToStr(Settings.SlashSetHelper, True));
      end
      else if AName = TSlashSettings.ComponentPalette then
      begin
        Result := Settings.SlashComponentPalette;
      end
      else if AName = TSlashSettings.InterfaceSection then
        case Settings.Completion.InterfaceSection of
          TCompletionInterfaceSection.Private:
            Result := 'private';
          TCompletionInterfaceSection.Protected:
            Result := 'protected';
        else
          Result := 'public';
        end
      else
      begin
        Result := '';
      end;
    end;
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
  FDiagnostics.TimeoutMs :=
    function: Cardinal
    begin
      Result := FRequestTimeout;
    end;
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
  FDocumentHighlights.SettingsFor :=
    function(const AUri: string): THighlightSettings
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        if Workspace <> nil then
        begin
          Result := Workspace.Configuration.Settings.Highlight;
        end
        else
        begin
          Result := THighlightSettings.Default;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
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

procedure TServerComposition.WireCompletion;
begin
  FCompletion := TLspCompletion.Create(FDocuments, FIndex,
    EnsureUnit);
  FCompletion.MatchingFor :=
    function(const AUri: string): TCompletionMatching
    begin
      Result := CompletionSettingsFor(AUri).Matching;
    end;
  // Abschnitt für Interface-Methoden (#466), Typumwandlung von Sender (#480).
  FCompletion.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := CompletionSettingsFor(AUri);
    end;
  FCompletion.SlashCommandsFor := SlashCommandsFor;
  FCompletion.RuleIdsFor := SlashRuleIdsAt;
  // Postfix-Vorlagen (#188): abschaltbar mit completion.postfixTemplates; for var und var Name := nur, wenn die
  // Sprachversion Inline-Variablen kennt und refactoring.inlineVar sie nicht abschaltet.
  FCompletion.PostfixFor :=
    function(const AUri: string): TPostfixOptions
    begin
      Result := TPostfixOptions.Default;
      Result.Enabled := CompletionSettingsFor(AUri).PostfixTemplates;
      Result.InlineVar := RefactoringSettingsFor(AUri).InlineVar and
        TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, LanguageLevelFor(AUri));
    end;
  // with auflösen über Strg+Leer auf with (#50), abschaltbar mit refactoring.resolveWith.
  FCompletion.WithFor :=
    function(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean
    var
      Context: TRefactoringContext;
      Action: TCodeAction;
    begin
      AEdits := nil;
      Context := FRefactorings.ContextFor(ARequest.Uri);
      Result := Context.Settings.ResolveWith and TLspRefactorings.WithAction(ARequest.Resolver, ARequest.Tree,
        ARequest.Text, ARequest.Position, Context, Action);
      if Result then
      begin
        AEdits := Action.Edits;
      end;
    end;
  // Methode aus Aufruf anlegen nach "(" bzw. mit Strg+Leer (#472), abschaltbar mit refactoring.createMethod.
  FCompletion.CreateFor :=
    function(ARequest: TCompletionRequest; out ATitle, ADetail: string; out AEdits: TArray<TTextEdit>): Boolean
    var
      Context: TRefactoringContext;
      Created: TCreatedMethod;
    begin
      ATitle := '';
      ADetail := '';
      AEdits := nil;
      Context := FRefactorings.ContextFor(ARequest.Uri);
      // Nur Änderungen in dieser Datei; die Klasse in einer anderen Unit bekommt die Code-Aktion.
      Result := Context.Settings.CreateMethod and TLspRefactorings.CreateMethod(ARequest.Resolver, ARequest.Tree,
        ARequest.Text, ARequest.Position, Context, True, Created) and (Created.FileEdits = nil);
      if Result then
      begin
        ATitle := Created.Title;
        ADetail := Created.Detail;
        AEdits := Created.Edits;
      end;
    end;
  // Präfix der Namensvorschläge (#452): Vorgabe der Projektdatei .atlas aus dem Projektkontext der IDE, sonst die
  // Zählung im Index.
  FCompletion.NamingFor :=
    function(const AUri: string; AKind: TNamingKind): string
    var
      Workspace: TShellWorkspace;
      Project: TProjectInfo;
      Context: TIdeProjectContext;
    begin
      Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
      if (Workspace <> nil) and Workspace.State.Project(Project) and FIdeProject.Find(Project.FileName, Context) and
        Context.HasNaming[AKind] then
      begin
        Exit(Context.Naming[AKind]);
      end;
      Result := TLspCompletion.NamingPrefix(FIndex, AKind);
    end;
  // Für completionItem/resolve (Detailpanel von Atlas, #405); Anzeige von XMLDoc (#654).
  FCompletion.HintsFor := HintSettingsFor;
  // „Parameter abgleichen“ in ///-Blöcken (#88) hängt an completeBlocks.docComment.
  FCompletion.DocCommentsFor := DocCommentsFor;
  // Bedingte Symbole in {$IFDEF } und Co. (#102).
  FCompletion.SymbolsFor := ConditionalContextFor;
  FCompletion.ReadText := ReadSourceText;
  // Teilergebnisse (#616) als $/progress; Zeiten je Anfrage im Debug-Protokoll.
  FCompletion.Notify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    var
      Notification: TJSONObject;
    begin
      Notification := TJsonRpcMessages.Notification(AMethod, AParams);
      try
        FTransport.WriteMessage(Notification);
      finally
        Notification.Free;
      end;
    end;
  FCompletion.Log :=
    procedure(const AText: string)
    begin
      FLogger.Debug(AText);
    end;
  FCompletion.Attach(FDispatcher);
  // Ausdrücke in den Debug-Dialogen (#538) mit denselben Einträgen wie im Editor.
  FExpressionCompletion := TLspExpressionCompletion.Create(FDocuments, FCompletion);
  FExpressionCompletion.Attach(FDispatcher);
  // „Interface implementieren“ im Erzeugen-Menü (#719, #466) wie in der Vervollständigung.
  FSlashMenu.Completion := FCompletion;
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
  FCodeLens.MetricsFor :=
    function(const AUri: string; out ALimits: TMetricLimits): Boolean
    var
      Source: TLspMetricsSource;
    begin
      if not MetricsSourceFor(TDocumentUris.ToPath(AUri), False, Source) then
      begin
        Source.Settings := TServerSettings.Default;
      end;
      ALimits := TMetricRules.Limits(Source.Settings);
      Result := Source.Settings.Metrics and Source.Settings.CodeLens.Metrics;
    end;
  FCodeLens.Attach(FDispatcher);
  FMetrics := TLspMetrics.Create(MetricsSourceFor,
    ReadSourceText);
  // Vererbungstiefe in der Metrik-Linse des Plugins (#980).
  FMetrics.Index := FIndex;
  // Gleiche Quelle wie die Metriken: Einstellungen, Wurzel und Dateien des Projektmodells (#14).
  FTodos := TLspTodos.Create(MetricsSourceFor,
    ReadSourceText);
  // Architekturübersicht (#1118): Fundstellen der uses-Einträge mit den Defines des Projekts der Datei.
  FArchitectureService := TArchitectureService.Create(FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      if not DefinesFor(TDocumentUris.FromPath(AFileName), Result) then
      begin
        Result := nil;
      end;
    end);
  FArchitecture := TLspArchitecture.Create(FArchitectureService, ArchitectureSourceFor);
  FArchitecture.Attach(FDispatcher);
  // Code-Abfragen (#1351): ein Dienst für Fenster, Befehl und die Regeln query:<name>.
  FQueries := TCodeQueryService.Create(QuerySource);
  FQuery := TLspQuery.Create(FQueries, QuerySettingsFor);
  FQuery.Attach(FDispatcher);
  // Hotspots (#1354): Komplexität aus geöffneten Dokumenten bzw. der Platte, Verlauf über Shell.Hotspots.
  FHotspotService := THotspotService.Create(FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end);
  FHotspots := TLspHotspots.Create(FHotspotService, HotspotSourceFor);
  FHotspots.Attach(FDispatcher);
  // Unit-Beziehungen (#593): Wurzel und Namensräume wie die Architektur; die uses-Analyse der Code-Aktionen
  // entsteht erst weiter unten, daher über UsesContextFor.
  FUnitRelationsGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
  FUnitRelations := TLspUnitRelations.Create(FUnitRelationsGraph,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      if not DefinesFor(TDocumentUris.FromPath(AFileName), Result) then
      begin
        Result := nil;
      end;
    end,
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      Result := UsesContextFor(AUri, AContext);
    end,
    function(const AFileName: string): TUsesGraphOptions
    begin
      Result := UnitRelationsOptionsFor(AFileName);
    end);
  FUnitRelations.Attach(FDispatcher);
  // Weg zwischen Symbolen (#1117): eigener Uses-Graph samt Bibliotheks-Units, Fundstellen wie oben.
  FSymbolPath := TLspSymbolPath.Create(FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      if not DefinesFor(TDocumentUris.FromPath(AFileName), Result) then
      begin
        Result := nil;
      end;
    end,
    EnsureUnit, SymbolPathSourceFor);
  FSymbolPath.Attach(FDispatcher);
  // Wertdarstellungen (#854): Dateien wie die TODO-Übersicht, Typen und Vorfahren aus dem Index.
  FDebugDisplay := TLspDebugDisplay.Create(MetricsSourceFor, ReadSourceText);
  FDebugDisplay.Index := FIndex;
  FEventHandlers := TLspEventHandlers.Create(MetricsSourceFor, ReadSourceText);
  FEventHandlers.Index := FIndex;
  // Rekursionssymbole im Editorrand (#623).
  FRecursion := TLspRecursion.Create(ReadSourceText);
  // Baseline (#97): dieselben Dateien wie die Metriken, Prüfung wie im Editor (Regeln, Index, Formulardatei).
  FBaseline := TLspBaseline.Create(MetricsSourceFor,
    function(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean
    var
      Context: TRuleCheckContext;
      Tree: TSyntaxTree;
      Extension: string;
    begin
      ACheck := Default(TLspBaselineCheck);
      Extension := LowerCase(ExtractFileExt(AFileName));
      Result := ((Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk')) and
        ReadSourceText(AFileName, ACheck.Text) and RuleContextFor(TDocumentUris.FromPath(AFileName), Context) and
        (Context.RelativePath <> '');
      if not Result then
      begin
        Exit;
      end;
      ACheck.RelativePath := Context.RelativePath;
      Tree := TSyntaxTreeCache.Parse(ACheck.Text);
      try
        ACheck.Findings := TLspSyntaxDiagnostics.RuleFindings(ACheck.Text, Tree, Context);
      finally
        Tree.Free;
      end;
    end,
    BaselineFiles);
  FBaseline.OnWritten :=
    procedure(AFileName: string)
    begin
      // Der Arbeitsbereich liest die Datei beim nächsten Prüfen neu; offene Dokumente gleich neu prüfen.
      FSyntaxDiagnostics.RefreshLater;
    end;
  // Sammelkorrektur für das Plugin (#1352): Text, Regeln, Projekt, Index und Baseline wie die Editor-Prüfung, aber
  // nicht Live (unused-uses meldet sich nur außerhalb des Editors) und mit den Symbolen des Projekts wie der Linter.
  FBulkFix := TLspBulkFix.Create(
    function(const AFileName: string; out AInput: TLspBulkFixInput): Boolean
    var
      mContext: TRuleCheckContext;
      mDefines: TArray<string>;
      mUri: string;
    begin
      AInput := Default(TLspBulkFixInput);
      mUri := TDocumentUris.FromPath(AFileName);
      Result := ReadSourceText(AFileName, AInput.Text) and RuleContextFor(mUri, mContext);
      if not Result then
      begin
        Exit;
      end;
      AInput.Rules := mContext.Rules;
      AInput.Settings := mContext.Settings;
      AInput.RelativePath := mContext.RelativePath;
      if AInput.RelativePath = '' then
      begin
        AInput.RelativePath := ExtractFileName(AFileName);
      end;
      AInput.Baseline := mContext.Baseline;
      AInput.Project.Application := mContext.Application;
      AInput.Project.Name := mContext.ProjectName;
      AInput.Project.AutoCreateForms := mContext.AutoCreateForms;
      AInput.Project.ProjectMainSource := mContext.ProjectMainSource;
      AInput.Project.FileName := AFileName;
      AInput.Project.Services := mContext.Services;
      if not DefinesFor(mUri, mDefines) then
      begin
        mDefines := nil;
      end;
      AInput.Source := TCheckSource.Create(AFileName, mDefines, IncludeResolverFor(mUri));
    end);
  // Compilermeldungen in derselben Baseline (#530): Text wie im Editor, offene Dokumente vor der Platte.
  FCompilerBaseline := TLspCompilerBaseline.Create(MetricsSourceFor,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    BaselineFiles);
  FCompilerBaseline.OnWritten :=
    procedure(AFileName: string)
    begin
      FSyntaxDiagnostics.RefreshLater;
    end;
  FSemanticTokens := TLspSemanticTokens.Create(FDocuments, FIndex,
    EnsureUnit);
  FSemanticTokens.Attach(FDispatcher);
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
  // Die Code-Aktionen entstehen erst in WireCodeActions: beim Aufruf lesen.
  mServices.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    var
      mProvider: TUsesContextProvider;
    begin
      mProvider := FCodeActions.UsesContextFor;
      Result := Assigned(mProvider) and mProvider(AUri, AContext);
    end;
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
begin
  FCodeActions := TLspCodeActions.Create(FDocuments, RuleContextFor);
  FCodeActions.FormActions :=
    function(const AUri, AText: string; const ARange: TTextRange): TArray<TCodeAction>
    var
      Action: TCodeAction;
    begin
      Result := nil;
      // Binär gespeichert (#122): Umwandeln in Text.
      if TFormModel.IsBinary(AText) then
      begin
        Action := Default(TCodeAction);
        Action.Title := 'Formular in Text umwandeln';
        Action.Kind := QuickFixKind;
        Action.IsPreferred := True;
        Action.Command := TLspFormFiles.ConvertCommand;
        Action.CommandArguments := [AUri];
        Result := [Action];
      end;
    end;
  FCodeActions.StringLiteralFor := StringLiteralFor;
  FCodeActions.DocCommentsFor := DocCommentsFor;
  // try/finally rückt wie das Formatieren ein (#42, #43).
  FCodeActions.FormatStyleFor := ResolvedFormatStyleFor;
  FCodeActions.RefactoringFor := RefactoringSettingsFor;
  FCodeActions.ClassActionContextFor :=
    function(const AUri: string): TClassActionContext
    begin
      Result := TClassActionContext.Default;
      Result.Index := FIndex;
      Result.DelphiVersion := LanguageLevelFor(AUri);
      Result.Uri := AUri;
      Result.Host := FFormatting.SlashHost;
    end;
  FCodeActions.MemberOrderFor :=
    function(const AUri: string): TMemberOrderSettings
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        if Workspace = nil then
        begin
          Result := TMemberOrderSettings.Default;
        end
        else
        begin
          Result := Workspace.Configuration.Settings.MemberOrder;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FCodeActions.SortUsesFor :=
    function(const AUri: string): Boolean
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        Result := (Workspace <> nil) and Workspace.Configuration.Settings.SortUses;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FCodeActions.SortUsesByNamespaceFor :=
    function(const AUri: string): Boolean
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        Result := (Workspace <> nil) and Workspace.Configuration.Settings.SortUsesByNamespace;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FCodeActions.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    var
      Workspace: TShellWorkspace;
    begin
      AContext := Default(TUsesContext);
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        if Workspace <> nil then
        begin
          AContext.Keep := Workspace.Configuration.Settings.UsesKeep;
          AContext.Namespaces := Workspace.State.Namespaces;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      AContext.Info :=
        function(const AUnitName: string): TUsesUnitInfo
        var
          UnitIndex: TUnitIndex;
          Symbol: TIndexSymbol;
        begin
          Result := Default(TUsesUnitInfo);
          EnsureUnit(AUnitName);
          if not FIndex.FindUnit(AUnitName, UnitIndex) then
          begin
            Exit;
          end;
          Result.Known := True;
          Result.HasInitialization := UnitIndex.HasInitialization;
          for Symbol in UnitIndex.Symbols do
          begin
            if Symbol.InInterface then
            begin
              Result.Names := Result.Names + [Symbol.Name];
            end;
          end;
        end;
      AContext.Declaring :=
        function(const AName: string): TArray<string>
        var
          Location: TSymbolLocation;
        begin
          Result := nil;
          for Location in FIndex.FindSymbols(AName) do
          begin
            if Location.Symbol.InInterface and (Location.Symbol.Container = '') and
              (IndexText(Location.UnitName, Result) < 0) then
            begin
              Result := Result + [Location.UnitName];
            end;
          end;
        end;
      Result := True;
    end;
  FTestPrograms := TDictionary<string, TPair<string, UInt64>>.Create;
  FTestUnits := TLspTestUnits.Create(FDocuments, TestUnitContextFor);
  FCodeActions.DefinesFor := DefinesFor;
  FCodeActions.ExtraActions :=
    function(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>
    begin
      Result := FTestUnits.Actions(AUri, ARange.StartPos.Line);
      Result := Result + FRefactorings.Actions(AUri, ARange);
    end;
  FCodeActions.Attach(FDispatcher);
  FDocumentLinks := TLspDocumentLinks.Create(FDocuments,
    function(const AUri: string): TArray<string>
    var
      Workspace: TShellWorkspace;
    begin
      Result := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
        if Workspace <> nil then
        begin
          Result := Workspace.State.IncludePaths;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end);
  FDocumentLinks.Attach(FDispatcher);
  FColors := TLspColors.Create(FDocuments, PlatformSystemColor);
  FColors.Attach(FDispatcher);
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
      Result := FCompilerBaseline.ExecuteClassify(AArguments);
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
  Result := FBaseline.Execute(AArguments);
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
  Result := FBulkFix.Execute(AArguments);
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
  Result := FCompilerBaseline.ExecuteAdd(AArguments);
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
  FIdeBuild.OnMessages :=
    procedure(const AMessages: TArray<TCompilerMessage>)
    begin
      FSyntaxDiagnostics.RefreshFiles(FCompile.Results.Replace(AMessages));
      FLogger.Info(Format('Compilermeldungen aus der IDE: %d', [Length(AMessages)]));
    end;
  // Letzten Build für den MCP-Prozess ablegen (#556): je Arbeitsordner eine Datei im Atlas-Cache.
  FIdeBuild.OnChanged :=
    procedure(const ABuild: TIdeBuild)
    var
      Workspace: TShellWorkspace;
      Root: string;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := PickWorkspace(ABuild.Project);
        if Workspace <> nil then
        begin
          Root := Workspace.Root;
        end
        else
        begin
          Root := ExtractFileDir(ABuild.Project);
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      if Root = '' then
      begin
        Exit;
      end;
      try
        ForceDirectories(TIndexCacheDirectory.DefaultRoot);
        TFile.WriteAllText(TIndexCacheDirectory.BuildFileFor(TIndexCacheDirectory.DefaultRoot, Root),
          TMcpBuildTools.ToFileText(ABuild), TEncoding.UTF8);
      except
        on E: Exception do
          FLogger.Warning(Format('Letzter Build nicht gespeichert: %s', [E.Message]));
      end;
    end;
  // Während die IDE kompiliert, ruht die Projektprüfung (#1247). Die Frist ist ein Sicherheitsnetz für ein
  // verlorenes Ende, keine Steuerung.
  FIdeBuild.OnCompiling :=
    procedure(ARunning: Boolean)
    begin
      FPullDiagnostics.Check.Pause(TLspWorkspaceCheck.cPauseCompile, ARunning, CompilePauseLimitMs);
    end;
  FIdeBuild.Attach(FDispatcher);
  // Projektwahl je Benutzer über Neustarts (#46).
  FProjectSelection := TProjectSelection.Create(TPath.Combine(TIndexCacheDirectory.DefaultRoot,
    'projektauswahl.json'));
  FProjectChoices := TDictionary<string, string>.Create;
  // Konfiguration, Plattform und Optionen aus der IDE (#396): betroffene Projekte neu laden.
  FIdeProject := TLspIdeProject.Create;
  FIdeProject.OnChanged :=
    procedure(const AContext: TIdeProjectContext)
    var
      Workspace: TShellWorkspace;
      Affected: TArray<TShellWorkspace>;
      Project: TProjectInfo;
    begin
      Affected := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        for Workspace in FWorkspaces do
        begin
          if SameText(Workspace.Setup.ProjectFile, AContext.Project) or
            (Workspace.State.Project(Project) and SameText(Project.FileName, AContext.Project)) then
          begin
            Affected := Affected + [Workspace];
          end;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      FLogger.Info(Format('Projektkontext aus der IDE: %s (%s, %s)',
        [ExtractFileName(AContext.Project), AContext.Configuration, AContext.Platform]));
      for Workspace in Affected do
      begin
        Workspace.Reload;
      end;
    end;
  // Neue Präfixe aus .atlas (#1111): naming-prefix und shadowed-name prüfen neu, das Projekt bleibt geladen.
  FIdeProject.OnNamingChanged :=
    procedure(const AContext: TIdeProjectContext)
    begin
      FSyntaxDiagnostics.RefreshLater;
    end;
  FIdeProject.Attach(FDispatcher);
end;

procedure TServerComposition.WireWorkspaceFolders;
begin
  FWorkspaceFolders := TLspWorkspaceFolders.Create;
  FWorkspaceFolders.OnChanged :=
    procedure(const AAdded, ARemoved: TArray<TWorkspaceFolder>)
    var
      Folder: TWorkspaceFolder;
    begin
      for Folder in ARemoved do
      begin
        RemoveWorkspace(Folder);
      end;
      for Folder in AAdded do
      begin
        AddWorkspace(Folder);
      end;
    end;
  FWorkspaceFolders.Attach(FDispatcher);
  FLifecycle.OnInitialized :=
    procedure
    var
      Folders: TArray<TWorkspaceFolder>;
      Folder: TWorkspaceFolder;
    begin
      WatchParent(FLifecycle.InitializeParams);
      // Name des Clients für die Anmeldung am Index-Cache (#62); vor dem Anlegen der Arbeitsbereiche.
      if FLifecycle.InitializeParams <> nil then
      begin
        FClientName := FLifecycle.InitializeParams.GetValue<string>('clientInfo.name', '');
      end;
      // Absturzfälle nennen den Client (#1355); der neue Client erfährt, was nach Abstürzen übersprungen wird.
      if FLifecycle.InitializeParams <> nil then
      begin
        FCrashCases.Client := Trim(FClientName + ' ' +
          FLifecycle.InitializeParams.GetValue<string>('clientInfo.version', ''));
      end;
      FCrashCases.Announce;
      // Editor-Ebene: initializationOptions.settings.atlas wie bei didChangeConfiguration, schon vor dem
      // ersten Indexaufbau; sie zählt wie global (TConfigurationScopes). Das IDE-Plugin schickt keine
      // Einstellungen mehr: Es schreibt settings.json, die der Server selbst liest und beobachtet.
      if FLifecycle.InitializeParams <> nil then
      begin
        SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(
          FLifecycle.InitializeParams.GetValue('initializationOptions')));
      end;
      UpdateLooseSettings;
      FHover.Markdown := TLspHover.ClientSupportsMarkdown(FLifecycle.InitializeParams);
      // Code-Vorlagen mit Platzhaltern nur an Clients mit snippetSupport (#51).
      FCompletion.SnippetSupport := TLspCompletion.ClientSupportsSnippets(FLifecycle.InitializeParams);
      FCompletion.DocumentationMarkdown := TLspCompletion.ClientPrefersMarkdown(FLifecycle.InitializeParams);
      Folders := TLspWorkspaceFolders.FromInitialize(FLifecycle.InitializeParams);
      // Vor dem ersten Laden, damit die Projekte nicht zweimal indiziert werden (#396).
      FIdeProject.LoadInitialize(FLifecycle.InitializeParams);
      // Meldet der Client nur Projektdateien (IDE-Plugin, #648), bekommen Dateien außerhalb dieser
      // Projekte weiter einen abgeleiteten Arbeitsbereich.
      FDeriveWorkspaces := True;
      for Folder in Folders do
      begin
        if Folder.ProjectFile = '' then
        begin
          FDeriveWorkspaces := False;
        end;
      end;
      if Length(Folders) = 0 then
      begin
        FLogger.Info('Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet');
      end;
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
      FFileWatcher := TFileWatcher.Create(
        procedure(const AFiles: TArray<string>)
        begin
          // Im Thread der Nachrichtenschleife verarbeiten wie eine Meldung des Clients.
          FConnection.Post(TLspWatchedFiles.Notification(AFiles));
        end);
      for Folder in Folders do
      begin
        AddWorkspace(Folder);
      end;
      UpdateWatchedSettings;
      FWatchedFiles.RegisterWatchers(FLifecycle.InitializeParams);
    end;
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
  FDocumentSymbols.Free;
  FFoldingRanges.Free;
  FLinkedEditing.Free;
  FInlineValues.Free;
  FCompilerSwitches.Free;
  FDebugUnavailable.Free;
  FFormatting.Free;
  FSlashMenu.Free;
  FSelectionRanges.Free;
  FDefinition.Free;
  FHover.Free;
  FWorkspaceSymbols.Free;
  FBookmarks.Free;
  FDocumentHighlights.Free;
  FReferences.Free;
  FSemanticTokens.Free;
  FCodeLens.Free;
  FMetrics.Free;
  FTodos.Free;
  FSymbolPath.Free;
  FArchitecture.Free;
  FArchitectureService.Free;
  FQuery.Free;
  FQueries := nil;
  FHotspots.Free;
  FHotspotService.Free;
  FUnitRelations.Free;
  FUnitRelationsGraph.Free;
  FDebugDisplay.Free;
  FEventHandlers.Free;
  FRecursion.Free;
  FCompilerBaseline.Free;
  FBaseline.Free;
  FBulkFix.Free;
  FInlayHints.Free;
  FImplementations.Free;
  FImpact.Free;
  FAccessChains.Free;
  FDataFlow.Free;
  FHierarchies.Free;
  FSignatureHelp.Free;
  FExpressionCompletion.Free;
  FCompletion.Free;
  FreeAndNil(FRefactorings);
  FRename.Free;
  FCodeActions.Free;
  FTestUnits.Free;
  FTestPrograms.Free;
  FUnitSearch.Free;
  FDocumentLinks.Free;
  FColors.Free;
  FCommands.Free;
  FreeAndNil(FCompile);
  FCompilerProcess := nil;
  FWatchedFiles.Free;
  FIdeBuild.Free;
  FIdeProject.Free;
  FProjectChoices.Free;
  FProjectSelection.Free;
  FTextDocumentSync.Free;
  // Nach der Verbindung und dem Watchdog: Niemand meldet mehr einen Absturz.
  FreeAndNil(FCrashCases);
  FDocuments := nil;
  FLifecycle.Free;
  FDispatcher.Free;
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
  Workspace: TShellWorkspace;
  Existing: TShellWorkspace;
  Identity: TIndexProcessInfo;
begin
  if AProjectFile <> '' then
  begin
    TMonitor.Enter(FWorkspacesLock);
    try
      for Existing in FWorkspaces do
      begin
        if SameText(Existing.Setup.ProjectFile, AProjectFile) then
        begin
          Exit;
        end;
      end;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
  end;
  if FLogAnonymizer <> nil then
  begin
    FLogAnonymizer.AddNames([AName, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)),
      ChangeFileExt(ExtractFileName(AProjectFile), '')]);
  end;
  Inc(FWorkspaceCounter);
  Workspace := TShellWorkspace.Create(ARoot, AName, TShellWorkspaceServices.Create(FDocuments, FTransport, FLogger,
    FIndex, Format('atlas-index-%d', [FWorkspaceCounter])));
  Workspace.Setup.ProjectFile := AProjectFile;
  Workspace.Setup.Priority := FWorkspacePriority;
  Inc(FWorkspacePriority);
  Workspace.Setup.Scheduler := FIndexScheduler;
  Workspace.Setup.Deferred := ADeferred;
  Workspace.Setup.IdeProjects := FIdeProject;
  Workspace.Setup.Origin := AOrigin;
  Workspace.Setup.Selection := FProjectSelection;
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62).
  Identity := Default(TIndexProcessInfo);
  Identity.Pid := TShellPlatform.CurrentProcessId;
  Identity.Kind := TIndexProcessInfo.KindLsp;
  Identity.Client := FClientName;
  Workspace.Setup.ProcessIdentity := Identity;
  // uses-unit-not-found: Was ein Projekt der Gruppe in einen Suchpfad übersetzt, gibt es beim Bau der Gruppe.
  Workspace.Setup.OnGroupProjects :=
    function: TArray<string>
    var
      Other: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        // Auch Projekte, deren Arbeitsbereich erst nach diesem entsteht: Die Unit-Suche wird beim Laden gebaut.
        Result := FGroupProjectFiles;
        for Other in FWorkspaces do
        begin
          if Other.Setup.ProjectFile <> '' then
          begin
            Result := Result + [Other.Setup.ProjectFile];
          end;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  // requires-Packages als Quelle zuerst bei den Projekten der Gruppe suchen (#46).
  Workspace.Setup.OnPackageFolders :=
    function: TArray<string>
    var
      Other: TShellWorkspace;
    begin
      Result := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        for Other in FWorkspaces do
        begin
          if Other.Setup.ProjectFile <> '' then
          begin
            Result := Result + [ExtractFileDir(Other.Setup.ProjectFile)];
          end;
        end;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  // Ordner entstehen in der Nachrichtenschleife (initialized, didChangeWorkspaceFolders, didOpen):
  // Reload ist nur dort erlaubt (Code-Review A-03).
  Workspace.Setup.LoopThreadId := TThread.Current.ThreadID;
  Workspace.Events.OnProjectLoaded := ProjectLoaded;
  Workspace.Events.OnIndexFinished := IndexFinished;
  Workspace.Events.OnProjectReady := ProjectReady;
  // Projekt- und Unit-Namen erscheinen im Server-Log nicht im Klartext (#647).
  Workspace.Events.OnNames :=
    procedure(ANames: TArray<string>)
    begin
      if FLogAnonymizer <> nil then
      begin
        FLogAnonymizer.AddNames(ANames);
      end;
    end;
  Workspace.Events.OnIndexEvent :=
    procedure(AText: string)
    begin
      // Absicherung: Beim Beenden ist das Diagnoselog schon fort (Code-Review A-05).
      if FDiagnostics <> nil then
      begin
        FDiagnostics.Log.LogEvent(AText);
      end;
    end;
  // Das Zeitlimit gilt serverweit; bei mehreren Ordnern das zuletzt gelesene.
  Workspace.Events.OnSettingsChanged :=
    procedure(ASettings: TServerSettings)
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
  // Eigenschaftsregeln mit unbekannter Klasse oder Property (#309): erst mit fertigem Index, sonst
  // fehlten die Klassen nur, weil sie noch nicht gelesen sind; IndexFinished prüft dann neu.
  Workspace.Configuration.ExtraIssues :=
    function(const ASettings: TServerSettings): TArray<TConfigurationIssue>
    begin
      // Gespeicherte Abfragen mit Fehler (#1351) an der Stelle in atlas.json, unabhängig vom Index.
      Result := TQueryParser.ConfigurationIssues(ASettings.Queries);
      if (Length(ASettings.DfmPropertyRules) = 0) or ProjectIndexPending or (Length(FIndex.Units) = 0) then
      begin
        Exit;
      end;
      Result := Result + TDfmPropertyCheckRule.ConfigurationIssues(ASettings.DfmPropertyRules, FIndex,
        function(const AFileName: string; out AData: TBytes): Boolean
        var
          Text: string;
        begin
          Result := ReadSourceText(AFileName, Text);
          if Result then
          begin
            AData := TEncoding.UTF8.GetBytes(Text);
          end;
        end);
    end;
  Workspace.Configuration.SetGlobalSettings(FGlobalSettings);
  Workspace.Configuration.SetEditorSettings(FEditorSettings);
  TMonitor.Enter(FWorkspacesLock);
  try
    FWorkspaces.Add(Workspace);
    Inc(FWorkspacesStamp);
  finally
    TMonitor.Exit(FWorkspacesLock);
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
  Workspace.Load;
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

procedure TServerComposition.RemoveWorkspace(const AFolder: TWorkspaceFolder);
var
  mIndex: Integer;
  Removed: TArray<TShellWorkspace>;
  Remaining: TArray<TShellWorkspace>;
  Workspace: TShellWorkspace;
  UnitIndex: TUnitIndex;
  Owned: Boolean;
  Shared: Boolean;
begin
  // Ein Eintrag (Ordner, .dproj oder .groupproj) kann mehrere Arbeitsbereiche erzeugt haben (#648).
  Removed := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    for mIndex := FWorkspaces.Count - 1 downto 0 do
    begin
      if SameText(FWorkspaces[mIndex].Setup.Origin, AFolder.Key) then
      begin
        Removed := Removed + [FWorkspaces.Extract(FWorkspaces[mIndex])];
      end;
    end;
    Remaining := FWorkspaces.ToArray;
    Inc(FWorkspacesStamp);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Length(Removed) = 0 then
  begin
    Exit;
  end;
  FLogger.Info(Format('Arbeitsbereich entfernt: %s (%d Projekte)', [AFolder.Path, Length(Removed)]));
  for Workspace in Removed do
  begin
    Workspace.Stop;
  end;
  // Units der entfernten Projekte verlassen den Index, sofern kein verbleibendes Projekt sie enthält;
  // geteilte Bibliotheks-Units bleiben.
  for UnitIndex in FIndex.Units do
  begin
    if UnitIndex.Library_ then
    begin
      Continue;
    end;
    Owned := False;
    for Workspace in Removed do
    begin
      if OwnsFile(Workspace, UnitIndex.FileName) then
      begin
        Owned := True;
        Break;
      end;
    end;
    if not Owned then
    begin
      Continue;
    end;
    Shared := False;
    for Workspace in Remaining do
    begin
      if OwnsFile(Workspace, UnitIndex.FileName) then
      begin
        Shared := True;
        Break;
      end;
    end;
    if not Shared then
    begin
      FIndex.RemoveFile(UnitIndex.FileName);
    end;
  end;
  // Erst freigeben, wenn keine Anfrage sie mehr außerhalb der Sperre nutzt (EnsureUnit). Neue Anfragen
  // sehen sie nicht mehr, das Warten endet also.
  for Workspace in Removed do
  begin
    TMonitor.Enter(FWorkspacesLock);
    try
      while FWorkspaceUsers.ContainsKey(Workspace) do
      begin
        TMonitor.Wait(FWorkspacesLock, WaitForever);
      end;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
    Workspace.Free;
  end;
  UpdateWatchedSettings;
  ProjectLoaded;
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
  Workspace: TShellWorkspace;
  Targets: TArray<TShellWorkspace>;
  Users: Integer;
begin
  // Anfrage-Threads: jeder Ordner versucht es mit seinen Suchpfaden. Das Parsen läuft außerhalb von
  // FWorkspacesLock (#647): Sonst warteten alle Anfragen, die nur kurz einen Arbeitsbereich suchen
  // (Defines, Einstellungen, Diagnoselog), auf das Parsen einer Unit, und Hover dauerte Minuten.
  TMonitor.Enter(FWorkspacesLock);
  try
    Targets := FWorkspaces.ToArray;
    for Workspace in Targets do
    begin
      if FWorkspaceUsers.TryGetValue(Workspace, Users) then
      begin
        FWorkspaceUsers[Workspace] := Users + 1;
      end
      else
      begin
        FWorkspaceUsers.Add(Workspace, 1);
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  try
    Result := False;
    for Workspace in Targets do
    begin
      // Abgebrochene Anfrage (Watchdog, $/cancelRequest): keine weitere Unit parsen (Code-Review A-06).
      TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
      if Workspace.EnsureUnit(AUnitName) then
      begin
        Exit(True);
      end;
    end;
  finally
    TMonitor.Enter(FWorkspacesLock);
    try
      for Workspace in Targets do
      begin
        Users := FWorkspaceUsers[Workspace] - 1;
        if Users = 0 then
        begin
          FWorkspaceUsers.Remove(Workspace);
        end
        else
        begin
          FWorkspaceUsers[Workspace] := Users;
        end;
      end;
      TMonitor.PulseAll(FWorkspacesLock);
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
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

function TServerComposition.BaselineFiles: TLspBaselineFiles;
begin
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := TFile.Exists(AFileName);
    end;
  Result.Read :=
    function(const AFileName: string; out AText: string): Boolean
    var
      FileFormat: TFileFormat;
    begin
      Result := TFile.Exists(AFileName);
      if Result then
      begin
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat);
      end
      else
      begin
        AText := '';
      end;
    end;
  Result.Write :=
    procedure(const AFileName, AText: string)
    var
      Disk: IIndexFileSystem;
      Error: string;
    begin
      // Atomar wie der Index-Cache (Bericht N3): Der Arbeitsbereich liest die Datei nach dem Zeitstempel und sah
      // mit TFile.WriteAllText womöglich einen halben Stand; ein Abbruch hinterließ eine kaputte Baseline.
      // UTF-8 ohne BOM wie bisher.
      Disk := TDiskIndexFileSystem.Create;
      if not Disk.WriteBytes(AFileName, TEncoding.UTF8.GetBytes(AText), Error) then
      begin
        raise EInOutError.Create('Baseline nicht geschrieben (' + Error + ')');
      end;
    end;
  Result.SetAside :=
    function(const AFileName: string; out ATarget: string): Boolean
    begin
      ATarget := AFileName + '.defekt';
      // Eine ältere beiseitegelegte Datei wird in einem Schritt ersetzt: Die jüngere hat den neueren Stand.
      Result := TShellPlatform.MoveReplacing(AFileName, ATarget);
    end;
end;

function TServerComposition.TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
const
  // Testprogramm höchstens so lange merken; ein neu angelegtes wird danach gefunden.
  CacheMs = 10000;
var
  Workspace, Other: TShellWorkspace;
  Info: TProjectInfo;
  Candidates: TArray<string>;
  Root, Folder, Found: string;
  Cached: TPair<string, UInt64>;
  HasCached: Boolean;
begin
  AContext := Default(TTestUnitContext);
  Candidates := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if Workspace = nil then
    begin
      Exit(False);
    end;
    AContext.Settings := Workspace.Configuration.Settings.TestUnits;
    Root := Workspace.Root;
    // Projekte der Gruppe zuerst, dann .dpr in der Wurzel und eine Ebene darunter.
    for Other in FWorkspaces do
    begin
      if Other.State.Project(Info) and (Info.MainSource <> '') then
      begin
        Candidates := Candidates + [Info.MainSource];
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  AContext.Root := Root;
  AContext.ReadText :=
    function(const AFileName: string): string
    begin
      if not ReadSourceText(AFileName, Result) then
      begin
        Result := '';
      end;
    end;
  AContext.Exists :=
    function(const AFileName: string): Boolean
    var
      Document: ITextDocument;
    begin
      Result := FileExists(AFileName) or FDocuments.TryGet(TDocumentUris.FromPath(AFileName), Document);
    end;
  AContext.FindUnit :=
    function(const AUnitName: string): string
    var
      UnitIndex: TUnitIndex;
    begin
      // Nur der Index: Diese Abfrage läuft bei jeder Code-Aktion und soll nichts nachladen.
      if FIndex.FindUnit(AUnitName, UnitIndex) and not UnitIndex.Library_ then
      begin
        Result := UnitIndex.FileName;
      end
      else
      begin
        Result := '';
      end;
    end;
  if AContext.Settings.Project <> '' then
  begin
    Found := AContext.Settings.Project;
    if not TPath.IsPathRooted(Found) then
    begin
      Found := TPath.Combine(Root, Found);
    end;
    AContext.TestProgram := ChangeFileExt(ExpandFileName(Found), '.dpr');
    Exit(True);
  end;
  TMonitor.Enter(FTestPrograms);
  try
    HasCached := FTestPrograms.TryGetValue(LowerCase(Root), Cached) and
      (TThread.GetTickCount64 - Cached.Value < CacheMs);
  finally
    TMonitor.Exit(FTestPrograms);
  end;
  if HasCached then
  begin
    AContext.TestProgram := Cached.Key;
    Exit(True);
  end;
  try
    Candidates := Candidates + TDirectory.GetFiles(Root, '*.dpr', TSearchOption.soTopDirectoryOnly);
    for Folder in TDirectory.GetDirectories(Root) do
    begin
      if not ExtractFileName(Folder).StartsWith('.') then
      begin
        Candidates := Candidates + TDirectory.GetFiles(Folder, '*.dpr', TSearchOption.soTopDirectoryOnly);
      end;
    end;
  except
    on E: EInOutError do
      FLogger.Debug('Testprojekt: Ordner nicht lesbar: ' + E.Message);
  end;
  AContext.TestProgram := TTestUnits.FindTestProgram(Candidates, AContext.ReadText);
  TMonitor.Enter(FTestPrograms);
  try
    FTestPrograms.AddOrSetValue(LowerCase(Root), TPair<string, UInt64>.Create(AContext.TestProgram,
      TThread.GetTickCount64));
  finally
    TMonitor.Exit(FTestPrograms);
  end;
  Result := True;
end;

function TServerComposition.UnitSearchContext(out AContext: TUnitSearchContext): Boolean;
var
  Workspace: TShellWorkspace;
  Info: TProjectInfo;
  Project: TUnitSearchProject;
  Text: string;
begin
  AContext := Default(TUnitSearchContext);
  AContext.Units := FIndex.Units;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      Project := Default(TUnitSearchProject);
      Project.Files := Workspace.State.ProjectFiles;
      if Workspace.State.Project(Info) then
      begin
        Project.FileName := Info.FileName;
        Project.Name := ChangeFileExt(ExtractFileName(Info.FileName), '');
        Project.IsTest := (Info.MainSource <> '') and ReadSourceText(Info.MainSource, Text) and
          TTestUnits.IsTestProgram(Text);
      end
      else
      begin
        Project.Name := Workspace.Name;
      end;
      AContext.Projects := AContext.Projects + [Project];
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  AContext.AncestorsOf :=
    function(AType: string): TArray<string>
    var
      Location: TSymbolLocation;
    begin
      Result := nil;
      for Location in FIndex.FindSymbols(AType) do
      begin
        if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
        begin
          Exit(Location.Symbol.Ancestors);
        end;
      end;
    end;
  AContext.Exists :=
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
  AContext.ReadText :=
    function(AFileName: string): string
    begin
      if not ReadSourceText(AFileName, Result) then
      begin
        Result := '';
      end;
    end;
  AContext.Modified :=
    function(AFileName: string): TDateTime
    begin
      Result := 0;
      if FileExists(AFileName) then
      begin
        Result := TFile.GetLastWriteTime(AFileName);
      end;
    end;
  AContext.GitState :=
    function(AFileName: string): string
    begin
      Result := GitStateOf(AFileName);
    end;
  AContext.UsesFor :=
    function(AUri: string): TUsesContext
    var
      Provider: TUsesContextProvider;
    begin
      Provider := FCodeActions.UsesContextFor;
      if not Assigned(Provider) or not Provider(AUri, Result) then
      begin
        Result := Default(TUsesContext);
      end;
    end;
  Result := True;
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
  Workspace: TShellWorkspace;
  Document: ITextDocument;
  FileName: string;
  Indexed: TUnitIndex;
  Seen: TDictionary<string, Boolean>;
begin
  // Wie ProjectSourceFiles, aber mit excludeTests ohne Testunits: Sonst stehen sie in der Warteschlange der
  // Projektprüfung, werden gezählt und eingelesen und erst in der Regel-Engine übersprungen. Ob eine Unit eine
  // Testunit ist, sagt ihr uses im Index; nicht indizierte Dateien bleiben drin (die Engine entscheidet dann).
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    TMonitor.Enter(FWorkspacesLock);
    try
      for Workspace in FWorkspaces do
      begin
        for FileName in Workspace.State.ProjectFiles do
        begin
          if Seen.ContainsKey(AnsiLowerCase(FileName)) then
          begin
            Continue;
          end;
          Seen.Add(AnsiLowerCase(FileName), True);
          if Workspace.Configuration.Settings.ExcludeTests and (FIndex <> nil) and
            FIndex.FindFile(FileName, Indexed) and
            TUsesClauses.UsesTestFramework(Indexed.InterfaceUses + Indexed.ImplementationUses) then
          begin
            Continue;
          end;
          Result := Result + [FileName];
        end;
      end;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
  finally
    Seen.Free;
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit; geöffnete Testunits prüft der Editor ohnehin.
  for Document in FDocuments.Documents do
  begin
    Result := Result + [TDocumentUris.ToPath(Document.Uri)];
  end;
end;

function TServerComposition.ApplyDfmPropertyRules(const AArguments: TJSONArray): TJSONValue;
var
  Uri, Scope, FileName: string;
  Units: TArray<string>;
  Workspace, Picked: TShellWorkspace;
  Files, Edits: Integer;
begin
  // Argumente: URI der Unit oder Formulardatei, Bereich form (Vorgabe), project oder group.
  if (AArguments = nil) or (AArguments.Count = 0) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument "uri" fehlt');
  end;
  Uri := AArguments.Items[0].Value;
  Scope := TLspDfmPropertyRules.ScopeForm;
  if AArguments.Count > 1 then
  begin
    Scope := AArguments.Items[1].Value;
  end;
  FileName := TLspDfmPropertyRules.UnitOf(TDocumentUris.ToPath(Uri));
  Units := nil;
  if SameText(Scope, TLspDfmPropertyRules.ScopeForm) then
  begin
    Units := [FileName];
  end
  else
  begin
    TMonitor.Enter(FWorkspacesLock);
    try
      Picked := PickWorkspace(FileName);
      for Workspace in FWorkspaces do
      begin
        if SameText(Scope, TLspDfmPropertyRules.ScopeGroup) or (Workspace = Picked) then
        begin
          Units := Units + Workspace.State.ProjectFiles;
        end;
      end;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
  end;
  Result := TLspDfmPropertyRules.BuildEdit(Units,
    function(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean
    var
      Context: TRuleCheckContext;
      Rule: IRule;
      Rules: TArray<IRule>;
      Text: string;
      Tree: TSyntaxTree;
    begin
      AFindings := nil;
      Result := SameText(ExtractFileExt(AFileName), '.pas') and
        RuleContextFor(TDocumentUris.FromPath(AFileName), Context) and (Context.FormFile <> '') and
        ReadSourceText(AFileName, Text);
      if not Result then
      begin
        Exit;
      end;
      // Nur dfm-property; RuleFindings zieht die Baseline nicht ab, der Befehl korrigiert alle Verstöße.
      Rules := nil;
      for Rule in Context.Rules do
      begin
        if SameText(Rule.Descriptor.Id, TLspDfmPropertyRules.RuleId) then
        begin
          Rules := Rules + [Rule];
        end;
      end;
      Context.Rules := Rules;
      Tree := TSyntaxTreeCache.Parse(Text);
      try
        AFindings := TLspSyntaxDiagnostics.RuleFindings(Text, Tree, Context);
      finally
        Tree.Free;
      end;
    end, Files, Edits);
  // Nur Zahlen ins Log, keine Pfade (#647).
  FLogger.Info(Format('Eigenschaftsregeln: %d Änderungen in %d Formulardateien vorgeschlagen', [Edits, Files]));
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
  Workspace, Other: TShellWorkspace;
  Group: TArray<TMissingUnitProject>;
  Member: TMissingUnitProject;
  OtherProject, mProject: TProjectInfo;
  Users: Integer;
begin
  ASetup := Default(TMissingUnitSetup);
  Group := nil;
  // Arbeitsbereich festhalten, die .dproj-Dateien aber außerhalb von FWorkspacesLock lesen (#647).
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(AFileName);
    if Workspace = nil then
    begin
      Exit(False);
    end;
    for Other in FWorkspaces do
    begin
      if (Other <> Workspace) and Other.State.Project(OtherProject) and
        not SameFileName(OtherProject.FileName, Workspace.State.ProjectFileName) then
      begin
        Member.FileName := OtherProject.FileName;
        Member.SearchPaths := OtherProject.SearchPaths;
        Group := Group + [Member];
      end;
    end;
    if FWorkspaceUsers.TryGetValue(Workspace, Users) then
    begin
      FWorkspaceUsers[Workspace] := Users + 1;
    end
    else
    begin
      FWorkspaceUsers.Add(Workspace, 1);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  try
    Result := Workspace.State.Project(mProject);
    if Result then
    begin
      ASetup := TShellWorkspaceJobs.MissingUnitSetupOf(mProject, Workspace.State.Install);
    end;
  finally
    TMonitor.Enter(FWorkspacesLock);
    try
      Users := FWorkspaceUsers[Workspace] - 1;
      if Users = 0 then
      begin
        FWorkspaceUsers.Remove(Workspace);
      end
      else
      begin
        FWorkspaceUsers[Workspace] := Users;
      end;
      TMonitor.PulseAll(FWorkspacesLock);
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
  end;
  if not Result then
  begin
    Exit;
  end;
  ASetup.UnitName := AUnitName;
  ASetup.GroupProjects := Group;
  // Nur der Index: nichts nachladen, die Suche läuft bei jeder Code-Aktion auf der Zeile.
  ASetup.IndexFile :=
    function(AName: string): string
    var
      UnitIndex: TUnitIndex;
    begin
      if FIndex.FindUnit(AName, UnitIndex) then
      begin
        Result := UnitIndex.FileName;
      end
      else
      begin
        Result := '';
      end;
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

function TServerComposition.BugReport(const AArguments: TJSONArray): TJSONValue;
var
  Input: TBugReportInput;
  Options: TJSONObject;
  Workspace: TShellWorkspace;
  Target, Text: string;
  Answer: TJSONObject;
begin
  Input := Default(TBugReportInput);
  Input.Anonymize := True;
  Target := '';
  Options := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
  begin
    Options := TJSONObject(AArguments.Items[0]);
  end;
  if Options <> nil then
  begin
    if Options.GetValue('anonymize') is TJSONBool then
    begin
      Input.Anonymize := TJSONBool(Options.GetValue('anonymize')).AsBoolean;
    end;
    if Options.GetValue('client') is TJSONString then
    begin
      Input.Client := Options.GetValue('client').Value;
    end;
    if Options.GetValue('target') is TJSONString then
    begin
      Target := Options.GetValue('target').Value;
    end;
  end;
  Input.ServerVersion := TProductVersion.Version;
  Input.Created := Now;
  Input.Configuration := ConfigurationReport;
  if FRecentLog <> nil then
  begin
    Input.LogLines := LastLines(FRecentLog.Lines, BugReportLogLines);
  end;
  Input.Requests := FStatistics.Recent;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      Input.Workspaces := Input.Workspaces + [Workspace.Root];
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Input.Identity := TProcessInfo.IdentityNames;
  Text := TBugReport.Build(Input);
  Answer := TJSONObject.Create;
  Answer.AddPair('text', Text);
  if Target <> '' then
  begin
    ForceDirectories(ExtractFileDir(Target));
    TFile.WriteAllText(Target, Text, TEncoding.UTF8);
    Answer.AddPair('file', Target);
  end;
  FLogger.Info('Fehlerbericht erstellt');
  Result := Answer;
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

function TServerComposition.HandleAffectedTests(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri: string;
  mSettings: TServerSettings;
  mQuery: TShellAffectedQuery;
  mRequest: TAffectedRequest;
  mContext: TTestUnitContext;
  mWorkspace: TShellWorkspace;
  mResolver: TNameResolver;
  mEnsureUnit: TEnsureUnitFunc;
  mReadDisk: TReferenceReadText;
  mProcess: ICompilerProcess;
  mFound: TAffectedResult;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "textDocument.uri" fehlt in ' + TAffectedTests.Method);
  end;
  mSettings := SettingsFor(mUri);
  mQuery := Default(TShellAffectedQuery);
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(mUri));
    if mWorkspace = nil then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, 'Kein Arbeitsbereich zu ' + mUri);
    end;
    mQuery.WorkingDir := mWorkspace.Root;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if not TJSONObject(AParams).TryGetValue<string>('base', mQuery.Base) then
  begin
    mQuery.Base := '';
  end;
  if not TJSONObject(AParams).TryGetValue<Boolean>('includeUncommitted', mQuery.IncludeUncommitted) then
  begin
    mQuery.IncludeUncommitted := True;
  end;
  if not TJSONObject(AParams).TryGetValue<Integer>('depth', mQuery.Depth) then
  begin
    mQuery.Depth := 0;
  end;
  mRequest := Default(TAffectedRequest);
  mRequest.Files := ProjectSourceFiles;
  mRequest.TestPrograms := TShellAffectedTests.TestPrograms(mRequest.Files, ReadSourceText);
  if TestUnitContextFor(mUri, mContext) and (mContext.TestProgram <> '') and
    (IndexText(mContext.TestProgram, mRequest.TestPrograms) < 0) then
  begin
    mRequest.TestPrograms := mRequest.TestPrograms + [mContext.TestProgram];
  end;
  // Treffersicherheit und Zeitlimit wie atlas/impact; Testunits aus allen Testprogrammen.
  mRequest.Options := ImpactOptionsFor(mUri);
  mRequest.Options.Tests := TShellAffectedTests.TestScope(mSettings.TestUnits.Pattern, mRequest.TestPrograms,
    ReadSourceText);
  // Typisierte Variable: TNameResolver.Create ist überladen.
  mEnsureUnit := EnsureUnit;
  // git bzw. svn vergleichen die gespeicherten Dateien: Die geänderten Zeilen passen nur zum Text auf der Platte,
  // nicht zu einem ungespeicherten Puffer im Editor.
  mReadDisk :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end;
  mResolver := TNameResolver.Create(FIndex, mEnsureUnit);
  try
    mResolver.Namespaces := FImpact.Namespaces;
    try
      // Eigener Prozessstarter: git/svn laufen neben einem Compilerlauf. Über eine Variable: nie ein frisches
      // Objekt an einen const-Interface-Parameter.
      mProcess := TProcessRunner.Create;
      mFound := TShellAffectedTests.Run(mProcess, mSettings, mQuery,
        TShellAffectedSources.New(mResolver, FIndex, mReadDisk), mRequest, ACancellation);
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
  Workspace, Candidate: TShellWorkspace;
  Project: TProjectInfo;
  Extension: string;
begin
  ASource := Default(TLspMetricsSource);
  ASource.Settings := TServerSettings.Default;
  Extension := LowerCase(ExtractFileExt(AFileName));
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    // Projektdatei: der Arbeitsbereich dieses Projekts (Projektgruppe, #648).
    if (Extension = '.dproj') or (Extension = '.dpr') or (Extension = '.dpk') then
    begin
      for Candidate in FWorkspaces do
      begin
        if (Candidate.State.Project(Project) and (SameText(Project.FileName, AFileName) or
          SameText(Project.MainSource, AFileName) or SameText(ChangeFileExt(Project.FileName, '.dproj'),
          ChangeFileExt(AFileName, '.dproj')))) or SameText(Candidate.Setup.ProjectFile, AFileName) then
        begin
          Workspace := Candidate;
          Break;
        end;
      end;
    end;
    if (Workspace = nil) and (AFileName <> '') then
    begin
      Workspace := WorkspaceOf(AFileName);
    end;
    Workspace := TShellWorkspaces.Choose(Workspace, FWorkspaces);
    if Workspace = nil then
    begin
      Exit(False);
    end;
    ASource.Settings := Workspace.Configuration.Settings;
    ASource.Root := Workspace.Root;
    if Workspace.State.Project(Project) then
    begin
      ASource.Title := ChangeFileExt(ExtractFileName(Project.FileName), '');
    end
    else
    begin
      ASource.Title := Workspace.Name;
    end;
    if AProject then
    begin
      ASource.Files := Workspace.State.ProjectFiles;
    end;
    Result := True;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
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
  Source: TLspMetricsSource;
  Workspace: TShellWorkspace;
  Scope: string;
  Files: TArray<string>;
begin
  ARequest := Default(TArchitectureRequest);
  ASettings := TServerSettings.Default;
  Result := MetricsSourceFor(AFileName, True, Source);
  if not Result then
  begin
    Exit;
  end;
  ASettings := Source.Settings;
  ARequest := TArchitectureRequest.FromSettings(ASettings);
  Scope := AScope;
  if Scope = '' then
  begin
    Scope := ASettings.ArchitectureScope;
  end;
  ARequest.Scope := Scope;
  ARequest.Root := Source.Root;
  ARequest.Title := Source.Title;
  if Scope = 'project' then
  begin
    ARequest.Files := Source.Files;
  end
  else
  begin
    // Projektgruppe (#648): die Dateien aller geladenen Projekte.
    Files := nil;
    TMonitor.Enter(FWorkspacesLock);
    try
      for Workspace in FWorkspaces do
      begin
        Files := Files + Workspace.State.ProjectFiles;
      end;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
    ARequest.Files := Files;
  end;
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
      ARequest.Namespaces := Workspace.State.Namespaces;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Zuletzt berechneter Stand je Projekt bzw. Projektgruppe für die Angleichung (#1367).
  ARequest.PreviousFile := TIndexCacheDirectory.ArchitectureFileFor(TIndexCacheDirectory.DefaultRoot,
    ARequest.ScopeKey);
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
  mFiles := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    // Projektgruppe: Choose liefert nur bei genau einem Arbeitsbereich etwas; sonst hieß es "Kein Projekt
    // geladen". Wurzel, Namensräume und Einstellungen vom in der IDE aktiven Projekt, sonst vom ausgewählten,
    // sonst vom ersten.
    mWorkspace := nil;
    for mCandidate in FWorkspaces do
    begin
      if (mCandidate.State.ProjectFileName <> '') and SameText(mCandidate.State.ProjectFileName, FIdeProject.ActiveProject) then
      begin
        mWorkspace := mCandidate;
      end;
    end;
    if mWorkspace = nil then
    begin
      for mCandidate in FWorkspaces do
      begin
        if (mWorkspace = nil) and IsSelectedProject(mCandidate) then
        begin
          mWorkspace := mCandidate;
        end;
      end;
    end;
    if (mWorkspace = nil) and (FWorkspaces.Count > 0) then
    begin
      mWorkspace := FWorkspaces[0];
    end;
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
    for mWorkspace in FWorkspaces do
    begin
      mFiles := mFiles + mWorkspace.State.ProjectFiles;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  ASource := TLspQuery.Source(FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end,
    mRoot, mFiles, mNamespaces,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    mReferences);
  Result := True;
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

function TServerComposition.RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  Workspace, Other: TShellWorkspace;
  FileName, Folder: string;
  Project: TProjectInfo;
  Projects: TArray<TProjectInfo>;
  RuleProject: TCheckProject;
  Pending: string;
  mLibrary: Boolean;
begin
  AContext := Default(TRuleCheckContext);
  FileName := TDocumentUris.ToPath(AUri);
  AContext.FileName := FileName;
  Projects := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(FileName);
    if Workspace = nil then
    begin
      AContext.Settings := FLooseSettings;
    end
    else
    begin
      AContext.Settings := Workspace.Configuration.Settings;
      AContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(Workspace.Root), FileName);
      AContext.Baseline := Workspace.Baseline;
      // Index, Namespaces, Unit-Suche, Packages und Namenskonvention auf demselben Weg wie MCP und Linter
      // (#1112).
      AContext.Services := Workspace.RuleServices;
      // Gespeicherte Abfragen mit failIfAny als Regeln query:<name> (#1351).
      AContext.Services.Queries := FQueries;
      if Workspace.State.Project(Project) then
      begin
        Projects := Projects + [Project];
      end;
      // Weitere Projekte mit der Datei (#1112): Eine Unit im Testprogramm und im Package hat keine
      // eindeutige Anwendungsart (MergeRuleProjects).
      for Other in FWorkspaces do
      begin
        if (Other <> Workspace) and Other.State.ContainsFile(FileName) and Other.State.Project(Project) then
        begin
          Projects := Projects + [Project];
        end;
      end;
    end;
    // RTL, VCL und Komponenten außerhalb der Projekte (diagnostics.librarySources): Wer mit Strg+Klick in
    // System.Net.HttpClient.pas springt, soll dort keine Befunde zu fremdem Code sehen.
    mLibrary := not AContext.Settings.DiagnosticsLibrarySources and IsLibrarySource(FileName);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Anwendungsart, Projektname und Formulare der .dpr (#926, #943, #956, #1055), wie bei MCP und Linter.
  if Projects <> nil then
  begin
    RuleProject := TShellRuleProjects.RuleProjectOf(Projects, FileName, ReadSourceText);
    AContext.Application := RuleProject.Application;
    AContext.ProjectName := RuleProject.Name;
    AContext.AutoCreateForms := RuleProject.AutoCreateForms;
    AContext.ProjectMainSource := RuleProject.ProjectMainSource;
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
  // Der Server hält alle Ordner: ein Index, Nachladen über alle Ordner (auch für Dateien ohne Ordner) und die
  // Projekte der Gruppe für unused-public-member (#1102); still, solange Projekte laden oder der Index läuft.
  AContext.Services.Index := FIndex;
  AContext.Services.EnsureUnit := EnsureUnit;
  // Solange Projekte laden oder der Index aufgebaut wird, ohne Index prüfen: Ein halber Index kennt Units noch
  // nicht, Regeln wie unresolved-identifier meldeten dann Bezeichner aus ihnen als nicht deklariert. Ohne Index
  // schweigen diese Regeln (wie mit --no-index); IndexFinished prüft danach alle Dateien neu.
  if not RuleProjectsComplete(Pending) then
  begin
    AContext.Services.Index := nil;
    AContext.Services.EnsureUnit := nil;
  end;
  AContext.Services.ProjectFiles := TRuleProjectFiles.Create(RuleProjects, FIndex, ReadSourceText,
    RuleProjectsComplete, FUsesGraph);
  // Editor-Prüfung (#896): Diagnosen, Code-Aktionen, Slash-Befehle und Baseline wie im Editor; uses-cycle folgt
  // dort diagnostics.usesCycleLive.
  AContext.Live := True;
  // Formulardatei neben der Unit für den Abgleich von Feldern und Objekten (#123).
  // Mit Pfad, damit Korrekturen die Formulardatei ändern können (#309).
  if SameText(ExtractFileExt(FileName), '.pas') then
  begin
    if ReadSourceText(ChangeFileExt(FileName, '.dfm'), AContext.FormText) then
    begin
      AContext.FormFile := ChangeFileExt(FileName, '.dfm');
    end
    else if ReadSourceText(ChangeFileExt(FileName, '.fmx'), AContext.FormText) then
    begin
      AContext.FormFile := ChangeFileExt(FileName, '.fmx');
    end
    else
    begin
      AContext.FormText := '';
    end;
  end;
  // Ressourcen neben der Unit, z. B. die .dcr mit den Palettensymbolen (#114).
  Folder := ExtractFilePath(FileName);
  AContext.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(Folder, AName));
      if Result then
      try
        AData := TFile.ReadAllBytes(TPath.Combine(Folder, AName));
      except
        on EInOutError do
          Result := False;
        on EFileStreamError do
          Result := False;
      end;
    end;
  // Fehlende Dateien aus {$I} und {$R} (#1379).
  AContext.FileExists :=
    function(const AName: string): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(Folder, AName));
    end;
  Result := True;
end;

procedure TServerComposition.ProjectLoaded;
var
  Workspace: TShellWorkspace;
  Namespaces: TArray<string>;
  Namespace: string;
  LibraryRoots: TArray<string>;
  GraphOptions: TUsesGraphOptions;
begin
  // Neuer Indexaufbau: Seine Projektstufe oder, falls die ausbleibt, sein Ende startet die Projektprüfung.
  FIndexRecheck.IndexStarted;
  // Neues Projekt oder neue Installation: Der Compiler bekommt eine neue Chance (#40).
  if FCompile <> nil then
  begin
    FCompile.Reset;
  end;
  // Die Features kennen eine Liste: die Namespaces aller Projekte ohne Doppelte.
  Namespaces := nil;
  LibraryRoots := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    // Projekte für projektweite Prüfregeln neu bestimmen (#1102).
    Inc(FWorkspacesStamp);
    for Workspace in FWorkspaces do
    begin
      for Namespace in Workspace.State.Namespaces do
      begin
        if IndexText(Namespace, Namespaces) < 0 then
        begin
          Namespaces := Namespaces + [Namespace];
        end;
      end;
      // Units der Delphi-Installation erscheinen im Diagnoselog mit Namen (#647).
      if (Workspace.State.BdsRoot <> '') and (IndexText(Workspace.State.BdsRoot, LibraryRoots) < 0) then
      begin
        LibraryRoots := LibraryRoots + [Workspace.State.BdsRoot];
      end;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  FDefinition.Namespaces := Namespaces;
  FHover.Namespaces := Namespaces;
  // Uses-Graph (#64) löst Namen ohne Namensraum über dieselbe Liste auf; neu aufgebaut nur bei Änderung.
  GraphOptions := FUsesGraph.Options;
  if string.Join(';', GraphOptions.Namespaces) <> string.Join(';', Namespaces) then
  begin
    GraphOptions.Namespaces := Namespaces;
    FUsesGraph.SetOptions(GraphOptions);
  end;
  FDocumentHighlights.Namespaces := Namespaces;
  FLinkedEditing.Namespaces := Namespaces;
  FInlineValues.Namespaces := Namespaces;
  FReferences.Namespaces := Namespaces;
  FRename.Namespaces := Namespaces;
  FCompletion.Namespaces := Namespaces;
  FSignatureHelp.Namespaces := Namespaces;
  FHierarchies.Namespaces := Namespaces;
  FImpact.Namespaces := Namespaces;
  FDataFlow.Namespaces := Namespaces;
  FAccessChains.Namespaces := Namespaces;
  FImplementations.Namespaces := Namespaces;
  FInlayHints.Namespaces := Namespaces;
  FCodeLens.Namespaces := Namespaces;
  FSemanticTokens.Namespaces := Namespaces;
  FDiagnostics.SetLibraryRoots(LibraryRoots);
  if FLogAnonymizer <> nil then
  begin
    FLogAnonymizer.SetLibraryRoots(LibraryRoots);
  end;
  FSyntaxDiagnostics.Refresh;
end;

procedure TServerComposition.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  Workspace: TShellWorkspace;
  OnSave: Boolean;
  Choice: TCompilerBackendChoice;
begin
  // Sicherheitsnetz (#1355): Ein geänderter Inhalt beendet das Überspringen für diese Datei.
  if (FCrashCases <> nil) and (AKind = TDocumentEventKind.Changed) then
  begin
    FCrashCases.DocumentChanged(ADocument.Uri, ADocument.Text);
  end;
  // Tipp-Pause (#492): ungespeicherten Stand in den Index; beim Schließen wieder den der Platte.
  if (FIndexRefresh <> nil) and StartsText('file:', ADocument.Uri) then
    case AKind of
      TDocumentEventKind.Changed:
        begin
          FIndexRefresh.Changed(TDocumentUris.ToPath(ADocument.Uri), ADocument.Text);
          // Beim Tippen macht die Projektprüfung Platz (#1247).
          if FPullDiagnostics <> nil then
          begin
            FPullDiagnostics.Typed;
          end;
        end;
      TDocumentEventKind.Closed:
        if TLspIndexRefresh.Applies(TDocumentUris.ToPath(ADocument.Uri)) then
        begin
          FIndexRefresh.Closed(TDocumentUris.ToPath(ADocument.Uri));
          FUsesChanges.Forget(TDocumentUris.ToPath(ADocument.Uri));
          HandleWatchedFiles([TFileChange.Create(TDocumentUris.ToPath(ADocument.Uri), TFileChangeKind.Changed)]);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  if FDeriveWorkspaces and (AKind = TDocumentEventKind.Opened) and StartsText('file:', ADocument.Uri) then
  begin
    DeriveWorkspace(TDocumentUris.ToPath(ADocument.Uri));
  end;
  // Zurückgestelltes Projekt der Gruppe (index.projectGroup = false): jetzt indizieren (#648).
  if (AKind = TDocumentEventKind.Opened) and StartsText('file:', ADocument.Uri) then
  begin
    TMonitor.Enter(FWorkspacesLock);
    try
      Workspace := WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
    // Nur der Thread der Nachrichtenschleife entfernt Arbeitsbereiche; Workspace bleibt gültig.
    if (Workspace <> nil) and Workspace.Setup.Deferred then
    begin
      Workspace.Activate;
    end;
  end;
  // Nach dem Speichern einer Quelldatei kompilieren (#40), abschaltbar über compiler.onSave.
  if (AKind = TDocumentEventKind.Saved) and MatchText(ExtractFileExt(TDocumentUris.ToPath(ADocument.Uri)),
    ['.pas', '.dpr', '.dpk', '.inc']) then
  begin
    // Index nachziehen (#500): Clients ohne Dateiüberwachung (IDE-Plugin) melden nur das Speichern;
    // bei einer .inc liest der Index die einbindenden Units neu ein.
    if not SameText(ExtractFileExt(TDocumentUris.ToPath(ADocument.Uri)), '.dpk') then
    begin
      HandleWatchedFiles([TFileChange.Create(TDocumentUris.ToPath(ADocument.Uri), TFileChangeKind.Changed)]);
    end;
    TMonitor.Enter(FWorkspacesLock);
    try
      Workspace := WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
      OnSave := (Workspace <> nil) and Workspace.Configuration.Settings.Compiler.OnSave;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
    if OnSave then
    begin
      FCompile.Start(TDocumentUris.ToPath(ADocument.Uri), False, Choice);
    end;
    Exit;
  end;
  if not IsConfigurationFileName(ExtractFileName(TDocumentUris.ToPath(ADocument.Uri))) then
  begin
    Exit;
  end;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Nur der Thread der Nachrichtenschleife entfernt Ordner; Workspace bleibt gültig.
  if Workspace <> nil then
  begin
    Workspace.Configuration.DocumentEvent(AKind, ADocument);
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
  Change: TFileChange;
  Sources: TArray<TFileChange>;
  Workspace: TShellWorkspace;
  Reload: TList<TShellWorkspace>;
  Updated: Integer;
  Names: TArray<string>;
begin
  Sources := nil;
  Reload := TList<TShellWorkspace>.Create;
  try
    for Change in AChanges do
    begin
      if (FGlobalSettingsFile <> '') and SameText(Change.FileName, FGlobalSettingsFile) then
      begin
        LoadGlobalSettings;
      end
      else if IsConfigurationFileName(ExtractFileName(Change.FileName)) then
      begin
        // atlas.json von außen geändert (#227, etwa im Dialog des Plugins): ohne Neustart übernehmen.
        for Workspace in FWorkspaces.ToArray do
        begin
          if Workspace.Configuration.FileChanged(Change.FileName) then
          begin
            FLogger.Info(Format('Einstellungen von %s neu gelesen', [Workspace.Root]));
          end;
        end;
      end
      else if TLspWatchedFiles.IsProjectFile(Change.FileName) then
      begin
        TMonitor.Enter(FWorkspacesLock);
        try
          Workspace := WorkspaceOf(Change.FileName);
        finally
          TMonitor.Exit(FWorkspacesLock);
        end;
        if (Workspace <> nil) and not Reload.Contains(Workspace) then
        begin
          Reload.Add(Workspace);
        end;
      end
      // .inc (#264): der Index liest die einbindenden Units neu ein.
      else if MatchText(ExtractFileExt(Change.FileName), ['.pas', '.dpr', '.inc']) then
      begin
        Sources := Sources + [Change];
        // Editor-Bäume mit $I neu lesen (#860): Die Symbole der .inc wählen ihre Zweige.
        if SameText(ExtractFileExt(Change.FileName), '.inc') then
        begin
          TSyntaxTreeCache.IncludesChanged;
          FSyntaxDiagnostics.RefreshLater;
        end;
      end;
    end;
    // Neu aufbauen: Suchpfade, Defines oder Units können sich geändert haben.
    for Workspace in Reload do
    begin
      FLogger.Info(Format('Projektdatei in %s geändert, Symbolindex wird neu aufgebaut', [Workspace.Root]));
      Workspace.Reload;
    end;
  finally
    Reload.Free;
  end;
  if Length(Sources) = 0 then
  begin
    Exit;
  end;
  // Jeder Ordner aktualisiert die Units, die sein Aufbau kennt.
  Updated := 0;
  for Workspace in FWorkspaces.ToArray do
  begin
    Inc(Updated, Workspace.ApplyChanges(Sources));
  end;
  FLogger.Debug(Format('%d Dateiänderungen von außen, %d Units im Index aktualisiert', [Length(Sources), Updated]));
  // Gespeichert oder von außen geändert (#1247): die Datei und die Units, die sie in uses haben bzw. einbinden.
  if FPullDiagnostics <> nil then
  begin
    Names := nil;
    for Change in Sources do
    begin
      Names := Names + [Change.FileName];
    end;
    FPullDiagnostics.Check.Affected(Names, True);
  end;
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  LoggerImpl: TLogger;
  mLogger: ILogger;
  Transport: IJsonRpcTransport;
  Warning: string;
  TraceName: string;
  Anonymizer: ILogAnonymizer;
  RecentSink: TRecentLogSink;
  RecentLog: IRecentLogLines;
  Tracing: TJsonRpcTracingTransport;
  DebugSink: ILogSink;
begin
  Tracing := nil;
  // Stacktraces für das Absturzprotokoll (Exception.StackTrace).
  TStackTrace.Install;
  // Schutzseite nach Stapelüberlauf (#1094) und Lesen mit FILE_SHARE_DELETE (Bericht M5), soweit die
  // Plattform sie braucht.
  TShellPlatform.InstallGuards;
  LoggerImpl := TLogger.Create;
  mLogger := LoggerImpl;
  DebugSink := TShellPlatform.DebugLogSink;
  if DebugSink <> nil then
  begin
    LoggerImpl.AddSink(DebugSink, TLogLevel.Debug);
  end;
  // stderr zeigt VS Code ebenfalls im Ausgabefenster; dort nur Fehler, um
  // Doppelungen mit window/logMessage zu vermeiden.
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Error);
  // Auszug für den Fehlerbericht (#108) und das Protokoll der Sitzung im Diagnosepaket (#1356), unabhängig von
  // --log.
  RecentSink := TRecentLogSink.Create(SessionLogLines);
  RecentLog := RecentSink;
  LoggerImpl.AddSink(RecentSink, TLogLevel.Info);
  TShellDiagnostics.AddLogFile(LoggerImpl, AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId),
    AOptions.LogNames, AOptions.LogLevel, Anonymizer);
  // Ohne --log bzw. mit --log-names trotzdem einer: Er sammelt die Namen der Projekte für den anonymen Status im
  // Diagnosepaket (#1356).
  if Anonymizer = nil then
  begin
    Anonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
  end;

  // Ab hier erreichen versehentliche Ausgaben (Writeln, Bibliotheken) nur noch stderr.
  Transport := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  if AOptions.TraceFile <> '' then
    try
      Tracing := TJsonRpcTracingTransport.Create(Transport,
        CreateTraceStream(AOptions.TraceFile, IntToStr(TParentWatcher.CurrentProcessId), TraceName), True);
      Transport := Tracing;
      if not SameText(TraceName, AOptions.TraceFile) then
      begin
        mLogger.Info(Format('Mitschnitt "%s" ist belegt, schreibe nach "%s"', [AOptions.TraceFile, TraceName]));
      end;
    except
      on E: Exception do
        mLogger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [AOptions.TraceFile, E.Message]));
    end;
  LoggerImpl.AddSink(TLspLogMessageSink.Create(Transport), AOptions.LogLevel);

  for Warning in AOptions.Warnings do
  begin
    mLogger.Warning(Warning);
  end;

  Result := TServerComposition.Create(Transport, mLogger);
  if Tracing <> nil then
  begin
    Result.FTracing := Tracing;
    // Nur Logger einfangen; den Zyklus Logger → Sink → Transport → Closure bricht das einmalige
    // Leeren beim Melden bzw. Destroy (S-07). Anonym: Klasse und Meldung, kein Pfad.
    Tracing.OnFailed :=
      procedure(const AReason: string)
      begin
        mLogger.Warning('Mitschnitt abgebrochen, der Server arbeitet ohne weiter: ' + AReason);
      end;
  end;
  Result.FRecentLog := RecentLog;
  Result.FLogAnonymizer := Anonymizer;
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
