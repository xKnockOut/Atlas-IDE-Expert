unit Shell.Composition;

// Host-Rolle Shell: Komposition des Servers von Hand (DI-Strategie ohne Container).
// Verbindet stdin/stdout, Transport, Dispatcher, Lebenszyklus, Dokumentverwaltung,
// Syntaxdiagnosen, Nachrichtenschleife, Logging, Zeitlimit für Anfragen und
// Absturzprotokoll mit Stacktrace. Jeder Ordner des Arbeitsbereichs hat
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
  Atlas.Common.Editing.SuggestConst,
  Atlas.Common.Editing.VarBlock,
  Atlas.Common.Semantics.ResolvedSignatures,
  Atlas.Common.Lsp.OverrideMarks,
  Atlas.Common.Lsp.SlashMenu,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.CompilerBaseline,
  Atlas.Common.Lsp.DisableWarning,
  Atlas.Common.Lsp.CompilerFixes,
  Atlas.Common.Editing.CompilerFixes,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Lsp.MissingUnit,
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
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Index.Scheduler,
  Shell.Platform,
  Shell.Workspace,
  Shell.Diagnostics;

type
  TServerComposition = class
  private
    FTransport: IJsonRpcTransport;
    /// <summary>Mitschnitt (--trace) in FTransport, nicht besitzend; nil ohne Mitschnitt.</summary>
    FTracing: TJsonRpcTracingTransport;
    FLogger: ILogger;
    /// <summary>Anonymisiert das Server-Log (#647); nil ohne --log oder mit --log-names.</summary>
    FLogAnonymizer: ILogAnonymizer;
    FDispatcher: TJsonRpcDispatcher;
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
    /// <summary>Nicht vertrauenswürdiger Arbeitsbereich (#186): kein Compiler-Lauf.</summary>
    FRestricted: Boolean;
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
    /// <summary>Compilermeldungen in der Baseline (#530).</summary>
    FCompilerBaseline: TLspCompilerBaseline;
    FSemanticTokens: TLspSemanticTokens;
    FCodeActions: TLspCodeActions;
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
    FFileWatcher: TFileWatcher;
    // Compiler-Anbindung (#40): höchstens ein Lauf zugleich, ein weiterer wird vorgemerkt.
    FCompilerResults: TCompilerResults;
    FCompilerProcess: ICompilerProcess;
    FCompileProgress: TLspWorkDoneProgress;
    FCompileLock: TObject;
    FCompileThread: TThread;
    FCompiling: Boolean;
    /// <summary>Beenden läuft: kein neuer Compilerlauf mehr (Code-Review A-05). Unter FCompileLock.</summary>
    FCompileStopping: Boolean;
    FHasPendingCompile: Boolean;
    FPendingCompile: TShellCompileJob;
    /// <summary>Grund, warum der Compiler nicht nutzbar ist; '' = nutzbar. Unter FCompileLock.
    /// Dann kompiliert der Server nach dem Speichern nicht mehr, bis das Projekt neu geladen wird.</summary>
    FCompilerUnavailable: string;
    /// <summary>Erkannte Ausgabe der Delphi-Installationen (#261): dcc da und nutzbar?</summary>
    FCompilerEditions: TShellCompilerEditions;
    /// <summary>Eigene IDE über cc.ps1 (#261); nur im Compile-Thread und beim Beenden.</summary>
    FIdeCompiler: TShellIdeCompiler;
    /// <summary>Zuletzt gewählter Weg zum Compiler für den Status (#28, #261). Unter FCompileLock.</summary>
    FCompilerChoice: TCompilerBackendChoice;
    FHasCompilerChoice: Boolean;
    /// <summary>Gründe, die schon als window/showMessage gezeigt wurden (#261): jeder einmal je Sitzung.
    /// Unter FCompileLock.</summary>
    FCompilerShown: TArray<string>;
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
    /// <summary>Teil von Create (S-02): Code-Aktionen, Testunits, Dokumentlinks und Farben.</summary>
    procedure WireCodeActions;
    /// <summary>Teil von Create (S-02): workspace/executeCommand: alle Befehle des Servers.</summary>
    procedure WireCommands;
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
    /// <summary>Befehl „Eigenschaftsregeln anwenden“ (#309): WorkspaceEdit über die Formulardateien.</summary>
    function ApplyDfmPropertyRules(const AArguments: TJSONArray): TJSONValue;
    /// <summary>„Signatur ändern“ (#100): APrepare = Parameter und Einschränkungen, sonst das WorkspaceEdit.</summary>
    function ChangeSignature(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
    /// <summary>Code-Aktion „Signatur ändern …“ an APosition (#100).</summary>
    function ChangeSignatureActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Klasse in eigene Unit verschieben“ (#103): das WorkspaceEdit für Name und Stelle.</summary>
    function MoveClass(const AArguments: TJSONArray): TJSONValue;
    function UnitRenamed(const AArguments: TJSONArray): TJSONValue;
    function PasteUses(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Code-Aktion „Klasse … in eigene Unit verschieben …“ an APosition (#103).</summary>
    function MoveClassActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Property X anlegen“ bzw. „Fehlende Properties anlegen“ an APosition (#682).</summary>
    function PropertyFromAccessorsActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Property aus Getter und Setter“ (#682): das WorkspaceEdit für Stelle und Aufrufe.</summary>
    function PropertyFromAccessors(const AArguments: TJSONArray): TJSONValue;
    function InlineAccessorActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Befehl atlas.server.inlineAccessor: [uri, position, here|unit|project] (#717).</summary>
    function InlineAccessor(const AArguments: TJSONArray): TJSONValue;
    function SafeDeleteActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Befehle atlas.server.safeDelete.prepare: [uri, position] und atlas.server.safeDelete: [uri,
    /// position, {overrides, cascade, force}] (#716).</summary>
    function SafeDelete(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
    /// <summary>Projekt der Datei AFileName für Umbauten mit neuen Units; False ohne Projekt.</summary>
    function RefactoringProject(const AFileName: string; out AProject: TProjectInfo): Boolean;
    /// <summary>Gibt es die Datei auf der Platte oder als offenes Dokument?</summary>
    function SourceExists(const AFileName: string): Boolean;
    /// <summary>Code-Aktion „Interface aus … herauslösen …“ an APosition (#664).</summary>
    function ExtractInterfaceActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Interface herauslösen“ (#664): APrepare = Kandidaten, sonst das WorkspaceEdit.</summary>
    function ExtractInterface(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
    /// <summary>Code-Aktion „Basisklasse aus … herauslösen …“ an APosition (#713).</summary>
    function ExtractSuperclassActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Basisklasse herauslösen“ (#713): APrepare = Kandidaten, sonst das WorkspaceEdit.</summary>
    function ExtractSuperclass(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
    /// <summary>„In Vorfahr/Nachfahren verschieben“ an APosition (#675).</summary>
    function MoveMemberActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Mitglied verschieben“ (#675): APrepare = Kandidaten und Ziele, sonst das WorkspaceEdit.</summary>
    function MoveMember(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
    /// <summary>„Bedeutung umkehren“ an APosition (#715).</summary>
    function InvertBooleanActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Boolean umkehren“ (#715): das WorkspaceEdit für alle Stellen.</summary>
    function InvertBoolean(const AArguments: TJSONArray): TJSONValue;
    /// <summary>„In Feld umwandeln“ bzw. „In lokale Variable umwandeln“ an APosition (#668).</summary>
    function PromoteVariableActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Lokale Variable und Feld umwandeln (#668): das WorkspaceEdit mit dem gewählten Namen.</summary>
    function PromoteVariable(const AArguments: TJSONArray): TJSONValue;
    /// <summary>„In Methode umwandeln“ und „Als anonyme Methode einbetten“ an APosition (#680).</summary>
    function AnonymousMethodActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Anonyme Methode in Methode umwandeln (#680): das WorkspaceEdit mit dem gewählten Namen.</summary>
    function AnonymousMethod(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Methode ohne Self umwandeln (#686): Code-Aktionen an APosition.</summary>
    function MethodKindActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Methode ohne Self umwandeln (#686): das WorkspaceEdit der gewählten Umwandlung über alle Dateien.
    /// </summary>
    function MethodKind(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Typ-Alias einführen und auflösen (#681): Code-Aktionen an APosition.</summary>
    function TypeAliasActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Typ-Alias einführen (#681): das WorkspaceEdit mit dem gewählten Namen und der Reichweite.</summary>
    function TypeAlias(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Alias auflösen (#681): das WorkspaceEdit über alle Verwendungen.</summary>
    function InlineTypeAlias(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Aufzählung mit Namenstabelle (#667): Code-Aktionen an APosition.</summary>
    function EnumTableActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Namenstabelle anlegen (#667): das WorkspaceEdit mit dem gewählten Namen und der Stelle.</summary>
    function EnumTable(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Tabellen und case-Anweisungen über einen Aufzählungstyp nachziehen (#667).</summary>
    function EnumTablesSync(const AArguments: TJSONArray): TJSONValue;
    /// <summary>„Umschließung entfernen“ (#657): Konstrukte am Cursor mit Varianten und Vorschau.</summary>
    function Unwrap(const AArguments: TJSONArray): TJSONValue;
    function StepTargets(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Schrittfilter (#850): Routine an [uri, line] mit Namen und Arten.</summary>
    function StepFilter(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Schrittfilter (#850): Treffer der Arten und Muster über alle Projekt-Units.</summary>
    function StepFilterCounts(const AArguments: TJSONArray): TJSONValue;
    /// <summary>„Typ ausschreiben“ (#453) für die Inline-Variable an APosition.</summary>
    function ExplicitTypeActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>„Warnung hier abschalten“ auf Meldungen des letzten Compilerlaufs (#531).</summary>
    function DisableWarningActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    function DisableWarning(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Schnellkorrekturen an Meldungen des letzten Compilerlaufs (#549).</summary>
    function CompilerFixActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    /// <summary>„Unit nicht gefunden“: Suchpfad ergänzen (#550).</summary>
    function MissingUnitActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    /// <summary>Suche nach AUnitName im Projekt der Datei AFileName vorbereiten (#550).</summary>
    function MissingUnitSetupFor(const AFileName, AUnitName: string; out ASetup: TMissingUnitSetup): Boolean;
    /// <summary>„Als Konstante deklarieren“ (#712, refactoring.suggestConst).</summary>
    function SuggestConstActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>var-Block pflegen (#644, refactoring.varBlock): umwandeln in beide Richtungen, aufräumen.</summary>
    function VarBlockActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    /// <summary>Extrahieren, „case vervollständigen“ und „with auflösen“ (#50).</summary>
    function RefactoringActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    /// <summary>Index, Einstellungen, Sprachversion und Formatstil für die Aktionen aus #50.</summary>
    function RefactoringContextFor(const AUri: string): TRefactoringContext;
    /// <summary>Präfixe neuer Namen für Refactorings in AUri: die der Namensregel, wenn sie für die Datei läuft
    /// (dieselbe Entscheidung wie in der Prüfung, TRuleEngine.NewNames).</summary>
    function NewNamesFor(const AUri: string): TPascalNamePrefixes;
    /// <summary>Inhalt des Status-Befehls (#28).</summary>
    function CollectBookmarks: TArray<TBookmarkHit>;
    function CollectStatus: TServerStatus;
    /// <summary>Weg zum Compiler für den Status (#28, #261).</summary>
    procedure CollectCompilerStatus(var AStatus: TServerStatus);
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
    /// <summary>Zielplattform und Konfiguration des Projekts zu AUri für den Hinweis inaktiver Zweige (#615).
    /// </summary>
    function BuildTargetFor(const AUri: string; out APlatform, AConfig: string): Boolean;
    /// <summary>Dienste der Syntaxprüfung; sie lösen erst beim Aufruf auf, die Felder dahinter entstehen in den
    /// späteren Wire-Schritten vor der ersten Nachricht.</summary>
    function SyntaxDiagnosticsProviders: TSyntaxDiagnosticsProviders;
    /// <summary>Namespaces aller Projekte an die Features weitergeben, Diagnosen neu prüfen.</summary>
    procedure ProjectLoaded;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    /// <summary>Kompiliert das Projekt zu AFileName ('' = einziger Ordner) im Hintergrund.
    /// AManual: über den Befehl, auch wenn der Compiler zuletzt nicht nutzbar war. Wählt vorher den Weg
    /// (#261: dcc, eigene IDE über cc.ps1 oder keiner). False, wenn kein Compiler nutzbar ist; Grund und
    /// Ausweg dann in AChoice.</summary>
    function StartCompile(const AFileName: string; AManual: Boolean; out AChoice: TCompilerBackendChoice): Boolean;
    /// <summary>Merkt sich, dass der Compiler nicht nutzbar ist, schreibt es ins Log und zeigt es einmal je
    /// Grund als window/showMessage (#261).</summary>
    procedure CompilerUnavailable(const AChoice: TCompilerBackendChoice; AShow: Boolean);
    /// <summary>Projekt, Installation und Weg zum Compiler für AFileName ('' = einziger Ordner); erkennt die
    /// Ausgabe der Installation bei Bedarf (#261). False ohne Projekt oder Installation (Grund in AChoice).
    /// </summary>
    function ChooseCompiler(const AFileName: string; out AJob: TShellCompileJob;
      out AChoice: TCompilerBackendChoice): Boolean;
    /// <summary>Merkt sich den gewählten Weg für den Status (#261).</summary>
    procedure RememberCompilerChoice(const AChoice: TCompilerBackendChoice);
    /// <summary>Hintergrund-Thread: führt AJob und vorgemerkte Läufe aus.</summary>
    procedure CompileLoop(const AJob: TShellCompileJob);
    /// <summary>Ein Compilerlauf mit Fortschritt und Meldungen; Fehler landen im Fortschritt und im Log.</summary>
    procedure CompileOnce(const AJob: TShellCompileJob);
    /// <summary>Lauf mit dcc32/dcc64; zeigt dcc den Lizenztext der Starter Edition, merkt sich das der
    /// Server und baut bei einem Befehl gleich über die IDE, wenn cc.ps1 eingerichtet ist (#261).</summary>
    procedure CompileWithDcc(const AJob: TShellCompileJob);
    /// <summary>Lauf über die eigene IDE mit cc.ps1 (#261).</summary>
    procedure CompileWithIde(const AJob: TShellCompileJob);
    /// <summary>Meldungen eines Laufs an Diagnosen, Log und Fortschritt.</summary>
    procedure PublishCompile(const AMessages: TArray<TCompilerMessage>; const AVia: string);
    /// <summary>Beenden: keine neuen Läufe, laufenden Compiler abbrechen, Thread abwarten (A-05).</summary>
    procedure StopCompiler;
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
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read FDocuments;
    property Index: ISymbolIndex read FIndex;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Diagnostics,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Product.Version,
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
  Shell.VcsChanges,
  Shell.AffectedTests,
  Atlas.Common.Lsp.AffectedTests,
  Shell.Bootstrap,
  Shell.Commands.Build,
  Shell.Commands.Index,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Lsp.DfmPropertyRules,
  Atlas.Common.Lsp.ChangeSignature,
  Atlas.Common.Lsp.MoveClass,
  Atlas.Common.Lsp.ExtractInterface,
  Atlas.Common.Lsp.ExtractSuperclass,
  Atlas.Common.Lsp.MoveMember,
  Atlas.Common.Editing.PropertyFromAccessors,
  Atlas.Common.Lsp.PropertyFromAccessors,
  Atlas.Common.Editing.InlineAccessor,
  Atlas.Common.Lsp.InlineAccessor,
  Atlas.Common.Lsp.SafeDelete,
  Atlas.Common.Lsp.InvertBoolean,
  Atlas.Common.Lsp.PromoteVariable,
  Atlas.Common.Lsp.AnonymousMethods,
  Atlas.Common.Lsp.MethodWithoutSelf,
  Atlas.Common.Lsp.TypeAlias,
  Atlas.Common.Editing.TypeAlias,
  Atlas.Common.Lsp.EnumTables,
  Atlas.Common.Lsp.Unwrap,
  Atlas.Common.Lsp.StepTargets,
  Atlas.Common.Lsp.StepFilter,
  Atlas.Common.Lsp.UnitRename,
  Atlas.Common.Lsp.SmartPaste,
  Atlas.Common.Editing.SmartPaste,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
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
    Result := TVcsChanges.FindProgram('powershell');
  if SameText(Result, 'powershell') then
    Result := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\WindowsPowerShell\v1.0\powershell.exe');
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
    ForceDirectories(Directory);
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
  WireProtocol;
  WireDocuments;
  WireEditing;
  WireWorkspaces;
  WireIndex;
  WireNavigation;
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
begin
  FDispatcher := TJsonRpcDispatcher.Create;
  FStatistics := TJsonRpcStatistics.Create;
  FDispatcher.Statistics := FStatistics;
  FDispatcher.Watchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, RequestTimeoutMs,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      // Code-Review A-06: Nebenläufige Anfragen beantwortet der Watchdog selbst, die übrigen brechen nur ab.
      if AAnswered then
        FLogger.Warning(Format('Anfrage %s nach %d ms mit RequestCancelled beantwortet (Zeitlimit)',
          [AMethod, ATimeoutMs]))
      else
        FLogger.Warning(Format('Anfrage %s hat das Zeitlimit von %d ms überschritten; Abbruch angefordert',
          [AMethod, ATimeoutMs]));
    end);
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    var
      Params: string;
    begin
      Params := '';
      if AParams <> nil then
        Params := AParams.ToJSON;
      if Length(Params) > 500 then
        Params := Copy(Params, 1, 500) + '…';
      FLogger.Error(Format('Anfrage %s fehlgeschlagen: %s: %s%sParameter: %s%s%s',
        [AMethod, AError.ClassName, AError.Message, sLineBreak, Params, sLineBreak, TShellPlatform.StackTraceOf(AError)]));
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

procedure TServerComposition.WireDocuments;
begin
  FDocuments := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
    end);
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FDispatcher);
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport, SyntaxDiagnosticsProviders);
  FSyntaxDiagnostics.OnError :=
    procedure(AError: Exception)
    begin
      FLogger.Error(Format('Fehler beim Prüfen der Syntax: %s: %s', [AError.ClassName, AError.Message]));
    end;
  FCompilerResults := TCompilerResults.Create;
  FCompilerProcess := TProcessRunner.Create;
  FCompileProgress := TLspWorkDoneProgress.Create(FTransport, 'atlas-compile');
  FCompileLock := TObject.Create;
  // Starter Edition ohne dcc (#261): Ausgabe je Installation erkennen und merken; eigene IDE über cc.ps1.
  FCompilerEditions := TShellCompilerEditions.Create(FCompilerProcess, FLogger, TShellCompilerEditions.DefaultFile);
  FIdeCompiler := TShellIdeCompiler.Create(FCompilerProcess, FLogger, PowerShellProgram,
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
          Result := TFileEncoding.LoadLines(AFileName);
      except
        on E: Exception do
          FLogger.Warning('Build-Log der IDE nicht lesbar: ' + E.ClassName);
      end;
    end);
  FSyntaxDiagnostics.Attach;
  FIndexRecheck := TWorkspaceCheckIndexGate.Create;
  FPullDiagnostics := TLspPullDiagnostics.Create(FDocuments, FSyntaxDiagnostics, FTransport, ProjectSourceFiles,
    function(const AFileName: string; out AStamp: Int64): Boolean
    begin
      Result := TFile.Exists(AFileName);
      if Result then
        AStamp := Round(TFile.GetLastWriteTimeUtc(AFileName) * MSecsPerDay)
      else
        AStamp := 0;
    end,
    function(const AFileName: string; out AText: string): Boolean
    var
      FileFormat: TFileFormat;
    begin
      Result := TFile.Exists(AFileName);
      if Result then
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
      else
        AText := '';
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
        Result := FDiagnostics.FileLabel(AFileName);
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
        Result := TLspWorkspaceCheck.DependentsOf(FIndex.Units, AFileName);
    end;
  FPullDiagnostics.Check.OnLog :=
    procedure(const AMessage: string)
    begin
      FLogger.Info(AMessage);
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
        AText := TFileEncoding.LoadText(AFileName);
    end);
  FFormatting.SlashCommandsFor := SlashCommandsFor;
  FFormatting.DelphiVersionFor := LanguageLevelFor;
  FFormatting.DocCommentsFor := DocCommentsFor;
  SlashHost := TShellSlashHost.Create(
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
          Exit('');
        Settings := Workspace.Configuration.Settings;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      // Eigene Vorlage der Schnellbefehle, sonst die der Regel file-header (#56).
      Result := Settings.SlashHeaderTemplate;
      if Result = '' then
        Result := TFileHeaderRule.Template(TRuleEngine.RuleOptions('file-header', Settings));
    end, FTransport, FLogger, FDispatcher,
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
        FLogger.Warning('Schnellbefehl: Projekt nicht neu geladen, die Verbindung ist beendet');
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
        ATarget.Reason := 'Die Datei ist keine Unit'
      else if Target.IsTest then
        ATarget.Reason := 'Die Datei ist selbst eine Testunit'
      else if Target.CounterpartFile <> '' then
      begin
        ATarget.FileName := Target.CounterpartFile;
        ATarget.Exists := True;
      end
      else if Target.CanCreate then
        ATarget.FileName := Target.NewFile
      else
        ATarget.Reason := Target.Reason;
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
          Settings := FLooseSettings
        else
          Settings := Workspace.Configuration.Settings;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      if AName = TSlashSettings.LogCall then
        Result := Settings.SlashLogCall
      else if AName = TSlashSettings.TodoOwner then
        Result := Settings.SlashTodoOwner
      else if AName = TSlashSettings.TodoCategory then
        Result := Settings.SlashTodoCategory
      else if AName = TSlashSettings.SortUsesRemoveUnused then
        Result := LowerCase(BoolToStr(Settings.SlashSortUsesRemoveUnused, True))
      else if AName = TSlashSettings.EnumHelper then
        Result := LowerCase(BoolToStr(Settings.SlashEnumHelper, True))
      else if AName = TSlashSettings.SetHelper then
        Result := LowerCase(BoolToStr(Settings.SlashSetHelper, True))
      else if AName = TSlashSettings.ComponentPalette then
        Result := Settings.SlashComponentPalette
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
        Result := '';
    end;
  // /ignore und /sortuses (#297): Regeltreffer der Zeile und ungenutzte uses.
  SlashHost.RuleIdsOf := SlashRuleIdsAt;
  SlashHost.UsesContextOf := UsesContextFor;
  SlashHost.FindingsOf := SlashFindingsAt;
  FFormatting.SlashHost := SlashHost;
  // resourcestring in eine andere Unit (#473): Die Schnittstelle hält den Host am Leben.
  KeepHost := SlashHost;
  FResourceStringWrite :=
    procedure(const AFileName, ANewText: string; const AEdit: TTextEdit)
    begin
      (KeepHost as TShellSlashHost).EditFile(TDocumentUris.FromPath(AFileName), AFileName, ANewText, AEdit);
    end;
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
        if Location.Symbol.Container = '' then
          Exit(True);
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
          Result := Workspace.Configuration.Settings.Highlight
        else
          Result := THighlightSettings.Default;
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
      Context := RefactoringContextFor(ARequest.Uri);
      Result := Context.Settings.ResolveWith and TLspRefactorings.WithAction(ARequest.Resolver, ARequest.Tree,
        ARequest.Text, ARequest.Position, Context, Action);
      if Result then
        AEdits := Action.Edits;
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
      Context := RefactoringContextFor(ARequest.Uri);
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
      if (Workspace <> nil) and Workspace.Project(Project) and FIdeProject.Find(Project.FileName, Context) and
        Context.HasNaming[AKind] then
        Exit(Context.Naming[AKind]);
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
        Source.Settings := TServerSettings.Default;
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
        Result := nil;
    end);
  FArchitecture := TLspArchitecture.Create(FArchitectureService, ArchitectureSourceFor);
  FArchitecture.Attach(FDispatcher);
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
        Result := nil;
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
        Result := nil;
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
        Exit;
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
          Result := TMemberOrderSettings.Default
        else
          Result := Workspace.Configuration.Settings.MemberOrder;
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
          AContext.Namespaces := Workspace.Namespaces;
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
            Exit;
          Result.Known := True;
          Result.HasInitialization := UnitIndex.HasInitialization;
          for Symbol in UnitIndex.Symbols do
            if Symbol.InInterface then
              Result.Names := Result.Names + [Symbol.Name];
        end;
      AContext.Declaring :=
        function(const AName: string): TArray<string>
        var
          Location: TSymbolLocation;
        begin
          Result := nil;
          for Location in FIndex.FindSymbols(AName) do
            if Location.Symbol.InInterface and (Location.Symbol.Container = '') and
              (IndexText(Location.UnitName, Result) < 0) then
              Result := Result + [Location.UnitName];
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
      Result := Result + ChangeSignatureActions(AUri, ARange.StartPos);
      Result := Result + MoveClassActions(AUri, ARange.StartPos);
      Result := Result + PropertyFromAccessorsActions(AUri, ARange.StartPos);
      Result := Result + InlineAccessorActions(AUri, ARange.StartPos);
      Result := Result + SafeDeleteActions(AUri, ARange.StartPos);
      Result := Result + ExtractInterfaceActions(AUri, ARange.StartPos);
      Result := Result + ExtractSuperclassActions(AUri, ARange.StartPos);
      Result := Result + MoveMemberActions(AUri, ARange.StartPos);
      Result := Result + InvertBooleanActions(AUri, ARange.StartPos);
      Result := Result + PromoteVariableActions(AUri, ARange.StartPos);
      Result := Result + AnonymousMethodActions(AUri, ARange.StartPos);
      Result := Result + MethodKindActions(AUri, ARange.StartPos);
      Result := Result + TypeAliasActions(AUri, ARange.StartPos);
      Result := Result + EnumTableActions(AUri, ARange.StartPos);
      Result := Result + ExplicitTypeActions(AUri, ARange.StartPos);
      Result := Result + CompilerFixActions(AUri, ARange);
      Result := Result + MissingUnitActions(AUri, ARange);
      Result := Result + DisableWarningActions(AUri, ARange);
      Result := Result + SuggestConstActions(AUri, ARange.StartPos);
      Result := Result + VarBlockActions(AUri, ARange.StartPos);
      Result := Result + RefactoringActions(AUri, ARange);
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
          Result := Workspace.IncludePaths;
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
  FCommands.Register(TLspFormFiles.ConvertCommand,
    function(const AArguments: TJSONArray): TJSONValue
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
    end);
  FCommands.Register(TLspDfmPropertyRules.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := ApplyDfmPropertyRules(AArguments);
    end);
  FCommands.Register(TLspChangeSignature.PrepareCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := ChangeSignature(AArguments, True);
    end);
  FCommands.Register(TLspChangeSignature.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := ChangeSignature(AArguments, False);
    end);
  FCommands.Register(TLspMoveClass.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := MoveClass(AArguments);
    end);
  FCommands.Register(TLspExtractInterface.PrepareCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := ExtractInterface(AArguments, True);
    end);
  FCommands.Register(TLspExtractInterface.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := ExtractInterface(AArguments, False);
    end);
  FCommands.Register(TLspExtractSuperclass.PrepareCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := ExtractSuperclass(AArguments, True);
    end);
  FCommands.Register(TLspExtractSuperclass.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := ExtractSuperclass(AArguments, False);
    end);
  FCommands.Register(TLspMoveMember.PrepareCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := MoveMember(AArguments, True);
    end);
  FCommands.Register(TLspMoveMember.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := MoveMember(AArguments, False);
    end);
  FCommands.Register(TLspPropertyFromAccessors.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := PropertyFromAccessors(AArguments);
    end);
  FCommands.Register(TLspInlineAccessor.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := InlineAccessor(AArguments);
    end);
  FCommands.Register(TLspSafeDelete.PrepareCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := SafeDelete(AArguments, True);
    end);
  FCommands.Register(TLspSafeDelete.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := SafeDelete(AArguments, False);
    end);
  FCommands.Register(TLspInvertBoolean.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := InvertBoolean(AArguments);
    end);
  FCommands.Register(TLspDisableWarning.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := DisableWarning(AArguments);
    end);
  FCommands.Register(TLspPromoteVariable.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := PromoteVariable(AArguments);
    end);
  FCommands.Register(TLspAnonymousMethods.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := AnonymousMethod(AArguments);
    end);
  FCommands.Register(TLspMethodWithoutSelf.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := MethodKind(AArguments);
    end);
  FCommands.Register(TLspTypeAlias.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TypeAlias(AArguments);
    end);
  FCommands.Register(TLspTypeAlias.InlineApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := InlineTypeAlias(AArguments);
    end);
  FCommands.Register(TLspEnumTables.ApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := EnumTable(AArguments);
    end);
  FCommands.Register(TLspEnumTables.SyncApplyCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := EnumTablesSync(AArguments);
    end);
  FCommands.Register(TLspUnwrap.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := Unwrap(AArguments);
    end);
  FCommands.Register(TLspStepTargets.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := StepTargets(AArguments);
    end);
  FCommands.Register(TLspStepFilter.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := StepFilter(AArguments);
    end);
  FCommands.Register(TLspStepFilter.CountsCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := StepFilterCounts(AArguments);
    end);
  FCommands.Register(TLspUnitRename.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := UnitRenamed(AArguments);
    end);
  FCommands.Register(TLspSmartPaste.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := PasteUses(AArguments);
    end);
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
  // Austrittspunkte am Cursor für die Hervorhebung im Plugin (#698).
  FCommands.Register(TLspExitPoints.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspExitPoints.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, FReadSourceTextRef,
        FDocumentHighlights.SettingsFor, AArguments);
    end);
  // Neu zugewiesene Variablen für die Unterstreichung im Plugin (#712).
  FCommands.Register(TLspReassigned.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspReassigned.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, AArguments);
    end);
  // Typ des markierten Ausdrucks für das Tastenkürzel im Plugin (#689).
  FCommands.Register(TLspExpressionType.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspExpressionType.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, AArguments);
    end);
  // Methodenrümpfe in Deklarationsreihenfolge für Befehl und Einfügen im Plugin (#660).
  FCommands.Register(TLspMethodOrder.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspMethodOrder.Execute(FDocuments, AArguments);
    end);
  // Überschreibungen für die Atlas-Spalte der Zeilenleiste (#768).
  FCommands.Register(TLspOverrideMarks.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspOverrideMarks.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces, AArguments);
    end);
  FCommands.Register(TLspBaseline.Command,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Watch: TStopwatch;
    begin
      // Prüft das ganze Projekt: in großen Altprojekten dauert das; nur Zahlen ins Log, keine Pfade.
      Watch := TStopwatch.StartNew;
      Result := FBaseline.Execute(AArguments);
      if Result is TJSONObject then
        FLogger.Info(Format('Baseline aktualisiert: %d Treffer, %d Dateien geprüft ' +
          '(%d neu, %d entfernt, %d ohne Datei), %d ms', [TJSONObject(Result).GetValue<Integer>('total', -1),
          TJSONObject(Result).GetValue<Integer>('files', -1), TJSONObject(Result).GetValue<Integer>('added', -1),
          TJSONObject(Result).GetValue<Integer>('removed', -1),
          TJSONObject(Result).GetValue<Integer>('orphaned.count', -1), Watch.ElapsedMilliseconds]));
    end);
  FCommands.Register(TLspCompilerBaseline.AddCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := FCompilerBaseline.ExecuteAdd(AArguments);
      if Result is TJSONObject then
        FLogger.Info(Format('Compilermeldungen in die Baseline: %d Einträge (%d neu, %d entfernt)',
          [TJSONObject(Result).GetValue<Integer>('total', -1), TJSONObject(Result).GetValue<Integer>('added', -1),
          TJSONObject(Result).GetValue<Integer>('removed', -1)]));
    end);
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
  FCommands.Register(TQualifiedNames.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TQualifiedNames.Execute(FDocuments, FIndex,
        FEnsureUnitRef, FDefinition.Namespaces, AArguments);
    end);
  FCommands.Register(TEnumValueCommands.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TEnumValueCommands.Execute(FDocuments, FIndex, FEnsureUnitRef, FDefinition.Namespaces,
        FReadSourceTextRef, AArguments);
    end);
  FCommands.Register(TResourceStringCommands.AddCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TResourceStringCommands.ExecuteAdd(FReadResourceRef, FResourceStringWrite, AArguments);
    end);
  FCommands.Register(TStringLiteralCommands.PlainTextCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TStringLiteralCommands.ExecutePlainText(FDocuments, AArguments);
    end);
  FCommands.Register(TStringLiteralCommands.ToLiteralCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Settings: TStringLiteralSettings;
      Multiline: Boolean;
    begin
      Settings := TStringLiteralSettings.Default;
      Multiline := False;
      if (AArguments <> nil) and (AArguments.Count > 0) then
        Settings := StringLiteralFor(AArguments.Items[0].Value, Multiline);
      Result := TStringLiteralCommands.ExecuteToLiteral(FDocuments, Settings, Multiline, AArguments);
    end);
  // Reine Lesebefehle laufen nebenläufig (#874): Status, Prüfung und Katalog der Einstellungen, Fehlerbericht.
  // Sie warten so nicht hinter einem Neuladen, während das Plugin auf die Antwort wartet.
  FCommands.RegisterConcurrent(StatusCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Status: TServerStatus;
    begin
      Status := CollectStatus;
      FLogger.Info('Status:' + sLineBreak + Status.ToMarkdown);
      Result := Status.ToJson;
    end);
  // Prozesse am selben Index-Cache (#62): Sperre, Stand, Prozesse und Ereignisse.
  FCommands.RegisterConcurrent(ProcessesCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Workspaces: TArray<TLspProcessWorkspace>;
    begin
      Workspaces := CollectProcesses;
      Result := TLspProcesses.ToJson(Workspaces, TShellPlatform.CurrentProcessId, Now);
      FLogger.Info(TLspProcesses.ToMarkdown(Workspaces, TShellPlatform.CurrentProcessId, Now));
    end);
  // Einstellungsdialog des Plugins (#227): Prüfung mit dem Parser des Servers und Regelkatalog.
  FCommands.RegisterConcurrent(TLspSettingsCommands.CheckCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspSettingsCommands.Check(AArguments);
    end);
  FCommands.RegisterConcurrent(TLspSettingsCommands.CatalogCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Rule: IRule;
      Experimental: TArray<string>;
    begin
      // Experimentelle Regeln (#834) kennt nur ihr Deskriptor; die Einstellungsseite (#909) markiert sie.
      Experimental := nil;
      for Rule in BuiltinRules do
        if Rule.Descriptor.Experimental then
          Experimental := Experimental + [Rule.Descriptor.Id];
      Result := TLspSettingsCommands.Catalog(TLspSettingsCommands.CatalogEntries(AArguments), FGlobalSettingsFile,
        Experimental);
    end);
  FCommands.RegisterConcurrent(TBugReport.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := BugReport(AArguments);
    end);
  FCommands.Register(CompileCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Uri: string;
      Started: Boolean;
      Choice: TCompilerBackendChoice;
      Answer: TJSONObject;
    begin
      // Optional die URI einer Datei, deren Projekt kompiliert wird.
      Uri := '';
      if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
        Uri := AArguments.Items[0].Value;
      if Uri = '' then
        Started := StartCompile('', True, Choice)
      else
        Started := StartCompile(TDocumentUris.ToPath(Uri), True, Choice);
      // Ohne nutzbaren Compiler antwortet der Befehl immer mit Grund und Ausweg (#261).
      if not Started then
        raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, Choice.MessageText);
      Answer := TJSONObject.Create;
      Answer.AddPair('started', TJSONBool.Create(True));
      Answer.AddPair('backend', TCompilerBackends.BackendText(Choice.Backend));
      Result := Answer;
    end);
  FCommands.Register(RebuildIndexCommand,
    function(const AArguments: TJSONArray): TJSONValue
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
        Workspace.Rebuild;
      FLogger.Info(Format('Index wird für %d Ordner neu aufgebaut', [Length(Targets)]));
      Result := TJSONNull.Create;
    end);
  FCommands.Register(ClearIndexCommand,
    function(const AArguments: TJSONArray): TJSONValue
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
        Workspace.ReleaseCache;
      Removed := TIndexCommands.ClearCaches(TIndexCacheDirectory.DefaultRoot, Freed);
      FLogger.Info(Format('Index gelöscht: %d Caches, %d KB; %d Ordner werden neu indiziert',
        [Removed, Freed div 1024, Length(Targets)]));
      for Workspace in Targets do
        Workspace.Rebuild;
      Result := TIndexCommands.Answer(Removed, Freed);
    end);
  FCommands.Register(TLspPullDiagnostics.RecheckCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      // Neue Generation (#1231): Alle Ergebnis-Ids veralten, auch die übersprungener Dateien (#1094); geöffnete
      // Dateien holt der Client nach dem refresh, die übrigen liefert workspace/diagnostic nach.
      FPullDiagnostics.Changed;
      FLogger.Info('Alle Dateien werden neu geprüft');
      Result := TJSONNull.Create;
    end);
  FCommands.Register(SelectBuildCommand,
    function(const AArguments: TJSONArray): TJSONValue
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
            Targets := [Workspace];
        end
        else
          Targets := FWorkspaces.ToArray;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      if Args.Changes then
        for Workspace in Targets do
          if Workspace.Project(Project) and
            not Workspace.SelectBuild(Args.Config, Args.Platform, Args.Defines, Args.HasDefines, Error) then
            raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
      Items := TJSONArray.Create;
      for Workspace in Targets do
        if Workspace.Project(Project) then
          Items.AddElement(TBuildCommands.ProjectItem(Workspace.Name, Project, Args));
      Result := TJSONObject.Create(TJSONPair.Create('projects', Items));
    end);
  FCommands.Register(SelectProjectCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Args: TSelectProjectArgs;
      Targets: TArray<TShellWorkspace>;
      Items: TArray<TProjectChoiceItem>;
      Index: Integer;
      Active: string;
    begin
      // Projekt für Dateien, die zu mehreren Projekten gehören (#46); gemerkt über Neustarts.
      Args := TSelectProjectArgs.Parse(AArguments);
      TMonitor.Enter(FWorkspacesLock);
      try
        Targets := nil;
        for Index := 0 to FWorkspaces.Count - 1 do
          if FWorkspaces[Index].ProjectFileName <> '' then
            Targets := Targets + [FWorkspaces[Index]];
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      Active := FIdeProject.ActiveProject;
      SetLength(Items, Length(Targets));
      for Index := 0 to High(Targets) do
      begin
        Items[Index].Name := Targets[Index].Name;
        Items[Index].Project := Targets[Index].ProjectFileName;
        Items[Index].Active := SameText(Items[Index].Project, Active);
      end;
      if Args.HasProject and (Args.Project = '') then
      begin
        for Index := 0 to High(Targets) do
          FProjectSelection.SetProject(Targets[Index].Origin, '');
        FLogger.Info('Projektwahl aufgehoben');
      end
      else if Args.HasProject then
      begin
        Index := TBuildCommands.FindProject(Items, Args.Project);
        if Index < 0 then
          raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
            Format('Projekt %s ist nicht geladen.', [Args.Project]));
        FProjectSelection.SetProject(Targets[Index].Origin, Items[Index].Project);
        FLogger.Info(Format('Projekt %s ausgewählt', [Items[Index].Name]));
      end;
      for Index := 0 to High(Targets) do
        Items[Index].Selected := IsSelectedProject(Targets[Index]);
      Result := TBuildCommands.ProjectChoices(Items);
    end);
  FCommands.Attach(FDispatcher);
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
        if Workspace.ApplyText(AFileName, AText) then
          Updated := True;
      if Updated then
        FLogger.Debug(Format('Index nach Tipp-Pause aktualisiert: %s', [ExtractFileName(AFileName)]));
      // Geänderte uses (#896): Ein Unit-Zyklus anderer offener Units kann über diese Unit laufen; der Graph
      // folgt dem Index, die Neuprüfung ist gebündelt.
      if Updated and FUsesChanges.Changed(AFileName, AText) and (FSyntaxDiagnostics <> nil) then
        FSyntaxDiagnostics.RefreshLater;
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
      FSyntaxDiagnostics.RefreshFiles(FCompilerResults.Replace(AMessages));
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
          Root := Workspace.Root
        else
          Root := ExtractFileDir(ABuild.Project);
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      if Root = '' then
        Exit;
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
          if SameText(Workspace.ProjectFile, AContext.Project) or
            (Workspace.Project(Project) and SameText(Project.FileName, AContext.Project)) then
            Affected := Affected + [Workspace];
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      FLogger.Info(Format('Projektkontext aus der IDE: %s (%s, %s)',
        [ExtractFileName(AContext.Project), AContext.Configuration, AContext.Platform]));
      for Workspace in Affected do
        Workspace.Reload;
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
        RemoveWorkspace(Folder);
      for Folder in AAdded do
        AddWorkspace(Folder);
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
        FClientName := FLifecycle.InitializeParams.GetValue<string>('clientInfo.name', '');
      // Editor-Ebene: initializationOptions.settings.atlas wie bei didChangeConfiguration, schon vor dem
      // ersten Indexaufbau; sie zählt wie global (TConfigurationScopes). Das IDE-Plugin schickt keine
      // Einstellungen mehr: Es schreibt settings.json, die der Server selbst liest und beobachtet.
      if FLifecycle.InitializeParams <> nil then
        SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(
          FLifecycle.InitializeParams.GetValue('initializationOptions')));
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
        if Folder.ProjectFile = '' then
          FDeriveWorkspaces := False;
      if Length(Folders) = 0 then
        FLogger.Info('Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet');
      // Globale Benutzerdatei (#227) vor dem ersten Ordner; der Server beobachtet sie und die atlas.json
      // selbst, weil die RAD-Studio-IDE keine Dateiänderungen meldet.
      FGlobalSettingsFile := GlobalSettingsPath;
      LoadGlobalSettings;
      FFileWatcher := TFileWatcher.Create(
        procedure(const AFiles: TArray<string>)
        begin
          // Im Thread der Nachrichtenschleife verarbeiten wie eine Meldung des Clients.
          FConnection.Post(TLspWatchedFiles.Notification(AFiles));
        end);
      for Folder in Folders do
        AddWorkspace(Folder);
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
    FDispatcher.Watchdog := nil;
  // Compiler und Index-Threads anhalten, solange Diagnoselog und Syntaxprüfung noch leben (Code-Review A-05):
  // Ein abgebrochener Aufbau meldet sich über OnIndexEvent im Diagnoselog, ein Compilerlauf über die
  // Syntaxprüfung.
  StopCompiler;
  StopIndexThreads;
  // Der Baum-Cache ist global; ohne Projekte gelten wieder die Vordefinitionen (#845).
  TSyntaxTreeCache.SetDefinesProvider(nil);
  TSyntaxTreeCache.SetIncludeProvider(nil);
  // Erst jetzt meldet sich niemand mehr beim Diagnoselog.
  if FDispatcher <> nil then
    FDispatcher.Observer := nil;
  FDiagnostics := nil;
  FDiagnosticsRef := nil;
  if Unfinished then
    // Der Prozess endet gleich: Speicher stehen lassen, statt ihn unter einem laufenden Handler freizugeben.
    FLogger.Warning('Beim Beenden liefen noch Anfragen; ihre Objekte werden nicht freigegeben')
  else
    FreeFeatures;
  if FTracing <> nil then
    FTracing.OnFailed := nil;
  FTransport := nil;
  FLogger := nil;
  inherited;
end;

procedure TServerComposition.StopCompiler;
begin
  if FCompileLock <> nil then
  begin
    TMonitor.Enter(FCompileLock);
    try
      FCompileStopping := True;
      FHasPendingCompile := False;
    finally
      TMonitor.Exit(FCompileLock);
    end;
  end;
  // Statt unbegrenzt auf dcc32 zu warten: Prozess beenden, dann endet der Thread sofort.
  if FCompilerProcess <> nil then
    FCompilerProcess.Cancel;
  if FCompileThread <> nil then
  begin
    FCompileThread.WaitFor;
    FreeAndNil(FCompileThread);
  end;
  // Eigene IDE (#261) mit dem Server beenden; der alte Läufer ist abgebrochen, deshalb ein neuer.
  if (FIdeCompiler <> nil) and (FIdeCompiler.Pid <> 0) then
    FIdeCompiler.Quit(TProcessRunner.Create);
end;

procedure TServerComposition.StopIndexThreads;
var
  Workspace: TShellWorkspace;
begin
  if FWorkspaces = nil then
    Exit;
  for Workspace in FWorkspaces do
    Workspace.Stop;
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
  FUnitRelations.Free;
  FUnitRelationsGraph.Free;
  FDebugDisplay.Free;
  FEventHandlers.Free;
  FRecursion.Free;
  FCompilerBaseline.Free;
  FBaseline.Free;
  FInlayHints.Free;
  FImplementations.Free;
  FImpact.Free;
  FAccessChains.Free;
  FDataFlow.Free;
  FHierarchies.Free;
  FSignatureHelp.Free;
  FExpressionCompletion.Free;
  FCompletion.Free;
  FRename.Free;
  FCodeActions.Free;
  FTestUnits.Free;
  FTestPrograms.Free;
  FUnitSearch.Free;
  FDocumentLinks.Free;
  FColors.Free;
  FCommands.Free;
  FCompileProgress.Free;
  FIdeCompiler.Free;
  FCompilerEditions.Free;
  FCompileLock.Free;
  FCompilerResults.Free;
  FCompilerProcess := nil;
  FWatchedFiles.Free;
  FIdeBuild.Free;
  FIdeProject.Free;
  FProjectChoices.Free;
  FProjectSelection.Free;
  FTextDocumentSync.Free;
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
    GroupFile := AFolder.ProjectFile
  else
    try
      // Genau eine .dproj im Ordner: wie bisher dieses Projekt (oder "project" aus atlas.json).
      if Length(TDirectory.GetFiles(AFolder.Path, '*.dproj')) <> 1 then
      begin
        Groups := TDirectory.GetFiles(AFolder.Path, '*.groupproj');
        if Length(Groups) = 1 then
          GroupFile := Groups[0];
      end;
    except
      // Nicht lesbare Ordner haben keine Gruppe.
      on Exception do
        GroupFile := '';
    end;
  if GroupFile <> '' then
    Result := TShellBootstrap.LoadGroup(GroupFile, FLogger);
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
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  for mIndex := 0 to High(Projects) do
    AddProjectWorkspace(ExtractFileDir(Projects[mIndex]), ChangeFileExt(ExtractFileName(Projects[mIndex]), ''),
      Projects[mIndex], AFolder.Key, HasOthers or (mIndex > 0));
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
        if SameText(Existing.ProjectFile, AProjectFile) then
          Exit;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
  end;
  if FLogAnonymizer <> nil then
    FLogAnonymizer.AddNames([AName, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)),
      ChangeFileExt(ExtractFileName(AProjectFile), '')]);
  Inc(FWorkspaceCounter);
  Workspace := TShellWorkspace.Create(ARoot, AName, FDocuments, FTransport, FLogger, FIndex,
    Format('atlas-index-%d', [FWorkspaceCounter]));
  Workspace.ProjectFile := AProjectFile;
  Workspace.Priority := FWorkspacePriority;
  Inc(FWorkspacePriority);
  Workspace.Scheduler := FIndexScheduler;
  Workspace.Deferred := ADeferred;
  Workspace.IdeProjects := FIdeProject;
  Workspace.Origin := AOrigin;
  Workspace.Selection := FProjectSelection;
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62).
  Identity := Default(TIndexProcessInfo);
  Identity.Pid := TShellPlatform.CurrentProcessId;
  Identity.Kind := TIndexProcessInfo.KindLsp;
  Identity.Client := FClientName;
  Workspace.ProcessIdentity := Identity;
  // requires-Packages als Quelle zuerst bei den Projekten der Gruppe suchen (#46).
  Workspace.OnPackageFolders :=
    function: TArray<string>
    var
      Other: TShellWorkspace;
    begin
      Result := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        for Other in FWorkspaces do
          if Other.ProjectFile <> '' then
            Result := Result + [ExtractFileDir(Other.ProjectFile)];
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  // Ordner entstehen in der Nachrichtenschleife (initialized, didChangeWorkspaceFolders, didOpen):
  // Reload ist nur dort erlaubt (Code-Review A-03).
  Workspace.LoopThreadId := TThread.Current.ThreadID;
  Workspace.OnProjectLoaded := ProjectLoaded;
  Workspace.OnIndexFinished := IndexFinished;
  Workspace.OnProjectReady := ProjectReady;
  // Projekt- und Unit-Namen erscheinen im Server-Log nicht im Klartext (#647).
  Workspace.OnNames :=
    procedure(ANames: TArray<string>)
    begin
      if FLogAnonymizer <> nil then
        FLogAnonymizer.AddNames(ANames);
    end;
  Workspace.OnIndexEvent :=
    procedure(AText: string)
    begin
      // Absicherung: Beim Beenden ist das Diagnoselog schon fort (Code-Review A-05).
      if FDiagnostics <> nil then
        FDiagnostics.Log.LogEvent(AText);
    end;
  // Das Zeitlimit gilt serverweit; bei mehreren Ordnern das zuletzt gelesene.
  Workspace.OnSettingsChanged :=
    procedure(ASettings: TServerSettings)
    begin
      FDispatcher.Watchdog.SetTimeout(ASettings.RequestTimeoutMs);
      FRequestTimeout := ASettings.RequestTimeoutMs;
      FDiagnostics.ApplySettings(ASettings);
    end;
  // Eigenschaftsregeln mit unbekannter Klasse oder Property (#309): erst mit fertigem Index, sonst
  // fehlten die Klassen nur, weil sie noch nicht gelesen sind; IndexFinished prüft dann neu.
  Workspace.Configuration.ExtraIssues :=
    function(const ASettings: TServerSettings): TArray<TConfigurationIssue>
    begin
      Result := nil;
      if (Length(ASettings.DfmPropertyRules) = 0) or ProjectIndexPending or (Length(FIndex.Units) = 0) then
        Exit;
      Result := TDfmPropertyCheckRule.ConfigurationIssues(ASettings.DfmPropertyRules, FIndex,
        function(const AFileName: string; out AData: TBytes): Boolean
        var
          Text: string;
        begin
          Result := ReadSourceText(AFileName, Text);
          if Result then
            AData := TEncoding.UTF8.GetBytes(Text);
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
    FLogger.Info('Arbeitsbereich für Projekt: ' + AProjectFile)
  else
    FLogger.Info('Arbeitsbereichsordner: ' + ARoot);
  Workspace.Load;
end;

// Gehört AFileName zu AWorkspace? Mit fester Projektdatei nur die Projekt- und Suchpfad-Units,
// sonst alles unter dem Ordner.
function OwnsFile(AWorkspace: TShellWorkspace; const AFileName: string): Boolean;
begin
  Result := AWorkspace.ContainsFile(AFileName);
  if not Result and (AWorkspace.ProjectFile = '') then
    Result := TLspWorkspaceFolders.FolderOf([TWorkspaceFolder.Create(AWorkspace.Root, '')], AFileName) = 0;
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
      if SameText(FWorkspaces[mIndex].Origin, AFolder.Key) then
        Removed := Removed + [FWorkspaces.Extract(FWorkspaces[mIndex])];
    Remaining := FWorkspaces.ToArray;
    Inc(FWorkspacesStamp);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Length(Removed) = 0 then
    Exit;
  FLogger.Info(Format('Arbeitsbereich entfernt: %s (%d Projekte)', [AFolder.Path, Length(Removed)]));
  for Workspace in Removed do
    Workspace.Stop;
  // Units der entfernten Projekte verlassen den Index, sofern kein verbleibendes Projekt sie enthält;
  // geteilte Bibliotheks-Units bleiben.
  for UnitIndex in FIndex.Units do
  begin
    if UnitIndex.Library_ then
      Continue;
    Owned := False;
    for Workspace in Removed do
      if OwnsFile(Workspace, UnitIndex.FileName) then
      begin
        Owned := True;
        Break;
      end;
    if not Owned then
      Continue;
    Shared := False;
    for Workspace in Remaining do
      if OwnsFile(Workspace, UnitIndex.FileName) then
      begin
        Shared := True;
        Break;
      end;
    if not Shared then
      FIndex.RemoveFile(UnitIndex.FileName);
  end;
  // Erst freigeben, wenn keine Anfrage sie mehr außerhalb der Sperre nutzt (EnsureUnit). Neue Anfragen
  // sehen sie nicht mehr, das Warten endet also.
  for Workspace in Removed do
  begin
    TMonitor.Enter(FWorkspacesLock);
    try
      while FWorkspaceUsers.ContainsKey(Workspace) do
        TMonitor.Wait(FWorkspacesLock, WaitForever);
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
    Exit;
  Folder := TLspWorkspaceFolders.ProjectFolderFor(AFileName, HasProjectFile);
  if Folder <> '' then
    AddWorkspace(TWorkspaceFolder.Create(Folder, ExtractFileName(Folder)));
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
    for Workspace in FWorkspaces do
      if SameText(Workspace.ProjectFileName, AFileName) then
        Exit(Workspace);
  // Zuerst das Projekt, das die Datei enthält (#648); mehrere Projekte können im selben Ordner liegen,
  // und eine Unit kann in mehreren Projekten der Gruppe stehen (#46).
  Candidates := nil;
  for Workspace in FWorkspaces do
    if Workspace.ContainsFile(AFileName) then
      Candidates := Candidates + [Workspace];
  if Length(Candidates) = 1 then
    Exit(Candidates[0]);
  if Length(Candidates) > 1 then
    Exit(ChooseProject(AFileName, Candidates));
  Folders := nil;
  for Workspace in FWorkspaces do
    Folders := Folders + [TWorkspaceFolder.Create(Workspace.Root, Workspace.Name)];
  mIndex := TLspWorkspaceFolders.FolderOf(Folders, AFileName);
  if mIndex < 0 then
    Result := nil
  else
    Result := FWorkspaces[mIndex];
end;

function TServerComposition.IsSelectedProject(AWorkspace: TShellWorkspace): Boolean;
var
  Selected: string;
begin
  Selected := FProjectSelection.Project(AWorkspace.Origin);
  Result := (Selected <> '') and SameText(Selected, AWorkspace.ProjectFileName);
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
    if IsSelectedProject(Workspace) then
    begin
      Result := Workspace;
      Reason := 'ausgewählt';
      Break;
    end;
  Active := FIdeProject.ActiveProject;
  if (Result = nil) and (Active <> '') then
    for Workspace in ACandidates do
      if SameText(Workspace.ProjectFileName, Active) then
      begin
        Result := Workspace;
        Reason := 'aktiv in der IDE';
        Break;
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

function TServerComposition.PickWorkspace(const AFileName: string): TShellWorkspace;
begin
  Result := TShellWorkspace.Choose(WorkspaceOf(AFileName), FWorkspaces);
end;

function TServerComposition.SettingsFor(const AUri: string): TServerSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(TDocumentUris.ToPath(AUri));
    if Workspace = nil then
      Result := FLooseSettings
    else
      Result := Workspace.Configuration.Settings;
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
      if FWorkspaceUsers.TryGetValue(Workspace, Users) then
        FWorkspaceUsers[Workspace] := Users + 1
      else
        FWorkspaceUsers.Add(Workspace, 1);
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
        Exit(True);
    end;
  finally
    TMonitor.Enter(FWorkspacesLock);
    try
      for Workspace in Targets do
      begin
        Users := FWorkspaceUsers[Workspace] - 1;
        if Users = 0 then
          FWorkspaceUsers.Remove(Workspace)
        else
          FWorkspaceUsers[Workspace] := Users;
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
      Result := Max(Result, Workspace.IndexLoading);
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
    for UnitIndex in FIndex.Units do
      FLogAnonymizer.AddUnit(UnitIndex.UnitName, UnitIndex.FileName);
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
      FSyntaxDiagnostics.RefreshLater;
    // Meldungen in atlas.json, die den Index brauchen (#309); Publish nur in der Nachrichtenschleife.
    if FConnection <> nil then
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
            Workspace.Configuration.Revalidate;
        end);
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
      if Workspace.ProjectPending then
        Exit(True);
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
      Exit(FRuleProjects);
    Stamp := FWorkspacesStamp;
    for Workspace in FWorkspaces do
      if Workspace.RuleProject(Project, MainSource) then
      begin
        Built := Built + [Project];
        MainSources := MainSources + [MainSource];
      end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Hauptquelltexte und Formulardateien außerhalb der Sperre lesen (dieselbe Regel wie find_unused_code, #64).
  for mIndex := 0 to High(Built) do
    Built[mIndex] := TRuleProjectFiles.ProjectOf(Built[mIndex].FileName, MainSources[mIndex], Built[mIndex].Sources,
      ReadSourceText);
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
      if not Workspace.RuleReady(AReason) then
        Exit(False);
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
      IncludePaths := Workspace.IncludePaths;
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
    Result := (Workspace <> nil) and Workspace.Defines(ADefines);
    // Datei keinem Projekt zugeordnet oder dessen Projekt noch nicht geladen (Projektgruppe): wie das
    // aktive Projekt, das die IDE zuerst meldet. Sonst blieben inaktive Zweige dort ungedimmt (#615).
    if not Result and (FWorkspaces.Count > 0) then
      Result := FWorkspaces[0].Defines(ADefines);
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
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
      else
        AText := '';
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
        raise EInOutError.Create('Baseline nicht geschrieben (' + Error + ')');
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
      Exit(False);
    AContext.Settings := Workspace.Configuration.Settings.TestUnits;
    Root := Workspace.Root;
    // Projekte der Gruppe zuerst, dann .dpr in der Wurzel und eine Ebene darunter.
    for Other in FWorkspaces do
      if Other.Project(Info) and (Info.MainSource <> '') then
        Candidates := Candidates + [Info.MainSource];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  AContext.Root := Root;
  AContext.ReadText :=
    function(const AFileName: string): string
    begin
      if not ReadSourceText(AFileName, Result) then
        Result := '';
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
        Result := UnitIndex.FileName
      else
        Result := '';
    end;
  if AContext.Settings.Project <> '' then
  begin
    Found := AContext.Settings.Project;
    if not TPath.IsPathRooted(Found) then
      Found := TPath.Combine(Root, Found);
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
      if not ExtractFileName(Folder).StartsWith('.') then
        Candidates := Candidates + TDirectory.GetFiles(Folder, '*.dpr', TSearchOption.soTopDirectoryOnly);
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
      Project.Files := Workspace.ProjectFiles;
      if Workspace.Project(Info) then
      begin
        Project.FileName := Info.FileName;
        Project.Name := ChangeFileExt(ExtractFileName(Info.FileName), '');
        Project.IsTest := (Info.MainSource <> '') and ReadSourceText(Info.MainSource, Text) and
          TTestUnits.IsTestProgram(Text);
      end
      else
        Project.Name := Workspace.Name;
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
        if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
          Exit(Location.Symbol.Ancestors);
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
        Result := '';
    end;
  AContext.Modified :=
    function(AFileName: string): TDateTime
    begin
      Result := 0;
      if FileExists(AFileName) then
        Result := TFile.GetLastWriteTime(AFileName);
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
        Result := Default(TUsesContext);
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
    Exit;
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
      for FileName in Workspace.ProjectFiles do
        Result := Result + [FileName];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit.
  for Document in FDocuments.Documents do
    Result := Result + [TDocumentUris.ToPath(Document.Uri)];
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument "uri" fehlt');
  Uri := AArguments.Items[0].Value;
  Scope := TLspDfmPropertyRules.ScopeForm;
  if AArguments.Count > 1 then
    Scope := AArguments.Items[1].Value;
  FileName := TLspDfmPropertyRules.UnitOf(TDocumentUris.ToPath(Uri));
  Units := nil;
  if SameText(Scope, TLspDfmPropertyRules.ScopeForm) then
    Units := [FileName]
  else
  begin
    TMonitor.Enter(FWorkspacesLock);
    try
      Picked := PickWorkspace(FileName);
      for Workspace in FWorkspaces do
        if SameText(Scope, TLspDfmPropertyRules.ScopeGroup) or (Workspace = Picked) then
          Units := Units + Workspace.ProjectFiles;
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
        Exit;
      // Nur dfm-property; RuleFindings zieht die Baseline nicht ab, der Befehl korrigiert alle Verstöße.
      Rules := nil;
      for Rule in Context.Rules do
        if SameText(Rule.Descriptor.Id, TLspDfmPropertyRules.RuleId) then
          Rules := Rules + [Rule];
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

function TServerComposition.ChangeSignatureActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).ChangeSignature or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Result := TLspChangeSignature.Actions(True, Resolver, Shared.Tree, TDocumentUris.ToPath(AUri), AUri, APosition);
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.MoveClassActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).MoveClass or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Result := TLspMoveClass.Actions(True, Resolver, Shared.Tree, TDocumentUris.ToPath(AUri), Document.Text, AUri,
      APosition);
  finally
    Resolver.Free;
  end;
end;

function PropertyOptionsOf(const ASettings: TRefactoringSettings): TPropertyFromAccessorsOptions;
begin
  Result := TPropertyFromAccessorsOptions.FromNames(ASettings.PropertyFromAccessorsPrefixes,
    ASettings.PropertyFromAccessorsSection, ASettings.PropertyFromAccessorsHideAccessors);
end;

function TServerComposition.PropertyFromAccessorsActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Settings: TRefactoringSettings;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Mode: TReplaceCalls;
begin
  Result := nil;
  Settings := RefactoringSettingsFor(AUri);
  if not Settings.PropertyFromAccessors or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Mode := TReplaceCalls.Ask;
  if Settings.PropertyFromAccessorsReplaceCalls = 'always' then
    Mode := TReplaceCalls.Always
  else if Settings.PropertyFromAccessorsReplaceCalls = 'never' then
    Mode := TReplaceCalls.Never;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspPropertyFromAccessors.Actions(True, Shared.Tree, Document.Text, AUri, APosition,
    PropertyOptionsOf(Settings), Mode);
end;

function TServerComposition.PropertyFromAccessors(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Settings: TRefactoringSettings;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TPropertyFromAccessorsContext;
  Answer: TJSONObject;
  ReplaceCalls: Boolean;
begin
  // Argumente: URI, Position, Aufrufe umstellen (true/false).
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri", "position" und "calls" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  ReplaceCalls := (AArguments.Items[2] is TJSONBool) and TJSONBool(AArguments.Items[2]).AsBoolean;
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.PropertyFromAccessors then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Property aus Getter und Setter" ist abgeschaltet (refactoring.propertyFromAccessors).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context := Default(TPropertyFromAccessorsContext);
  Context.Index := FIndex;
  Context.Options := PropertyOptionsOf(Settings);
  if ReplaceCalls or (Context.Options.Hiding <> TAccessorHiding.Off) then
  begin
    Context.Files := ProjectSourceFiles;
    Context.ReadText := ReadSourceText;
  end;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspPropertyFromAccessors.Execute(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text,
      Position, ReplaceCalls, Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Property aus Getter und Setter: %d Properties, %d Aufrufe',
    [(Answer.GetValue('properties') as TJSONNumber).AsInt, (Answer.GetValue('calls') as TJSONNumber).AsInt]));
  Result := Answer;
end;

function InlineAccessorOptionsOf(const ASettings: TRefactoringSettings): TInlineAccessorOptions;
begin
  Result := TInlineAccessorOptions.Default;
  Result.EqualityCheck := ASettings.InlineAccessorEqualityCheck;
end;

function TServerComposition.InlineAccessorActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Settings: TRefactoringSettings;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  Result := nil;
  Settings := RefactoringSettingsFor(AUri);
  if not Settings.InlineAccessor or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspInlineAccessor.Actions(True, Settings.InlineAccessorBulk, Shared.Tree, Document.Text, AUri,
    APosition, InlineAccessorOptionsOf(Settings), FIndex);
end;

function TServerComposition.InlineAccessor(const AArguments: TJSONArray): TJSONValue;
var
  Uri, Scope: string;
  Position: TTextPosition;
  Settings: TRefactoringSettings;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TInlineAccessorContext;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, Bereich (here, unit, project).
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri", "position" und "scope" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Scope := AArguments.Items[2].Value;
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.InlineAccessor then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Zugriffsmethode durch Feld ersetzen" ist abgeschaltet (refactoring.inlineAccessor).');
  if (Scope <> TLspInlineAccessor.ScopeHere) and not Settings.InlineAccessorBulk then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      'Die Sammelaktion ist abgeschaltet (refactoring.inlineAccessorBulk).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context := Default(TInlineAccessorContext);
  Context.Index := FIndex;
  Context.Options := InlineAccessorOptionsOf(Settings);
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspInlineAccessor.Execute(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text,
      Position, Scope, Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Zugriffsmethode durch Feld ersetzen: %d Methoden, %d Dateien',
    [(Answer.GetValue('accessors') as TJSONNumber).AsInt, (Answer.GetValue('files') as TJSONNumber).AsInt]));
  Result := Answer;
end;

function TServerComposition.SafeDeleteActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).SafeDelete or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspSafeDelete.Actions(True, Shared.Tree, Document.Text, AUri, APosition);
end;

function TServerComposition.SafeDelete(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Settings: TRefactoringSettings;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Choices: TSafeDeleteChoices;
  Context: TSafeDeleteContext;
  Provider: TUsesContextProvider;
begin
  // Argumente: URI, Position, beim Löschen die Antworten auf die Rückfragen.
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "position" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Choices := Default(TSafeDeleteChoices);
  if AArguments.Count > 2 then
    Choices := TSafeDeleteChoices.FromJson(AArguments.Items[2]);
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.SafeDelete then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, '"Sicher löschen" ist abgeschaltet (refactoring.safeDelete).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context := Default(TSafeDeleteContext);
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Provider := FCodeActions.UsesContextFor;
  if Assigned(Provider) then
    Context.UsesFor :=
      function(const AFileName: string): TUsesContext
      begin
        if not Provider(TDocumentUris.FromPath(AFileName), Result) then
          Result := Default(TUsesContext);
      end;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    if APrepare then
    begin
      Answer := TLspSafeDelete.Prepare(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, Position,
        Context);
      // Die Einstellungen entscheiden im Plugin über Rückfragen und Vorschau.
      Answer.AddPair('previewWhenUnused', TJSONBool.Create(Settings.SafeDeletePreviewWhenUnused));
      Answer.AddPair('cascadeMode', Settings.SafeDeleteCascade);
      Answer.AddPair('overridesMode', Settings.SafeDeleteIncludeOverrides);
    end
    else
      Answer := TLspSafeDelete.Execute(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, Position,
        Choices, Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  if APrepare then
    FLogger.Info(Format('Sicher löschen geprüft: %d Verwendungen, %d Überschreibungen',
      [(Answer.GetValue('usages') as TJSONArray).Count, (Answer.GetValue('overrides') as TJSONArray).Count]))
  else
    FLogger.Info(Format('Sicher löschen: %d Symbole, %d Dateien',
      [(Answer.GetValue('deleted') as TJSONNumber).AsInt, (Answer.GetValue('files') as TJSONNumber).AsInt]));
  Result := Answer;
end;

function InvertBooleanContextOf(const ASettings: TRefactoringSettings): TInvertBooleanContext;
begin
  Result := Default(TInvertBooleanContext);
  Result.Antonyms := ASettings.InvertBooleanAntonyms;
  Result.Prefix := ASettings.InvertBooleanFallbackPrefix;
  Result.IncludeDfm := ASettings.InvertBooleanIncludeDfm;
end;

function TServerComposition.InvertBooleanActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Settings: TRefactoringSettings;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TInvertBooleanContext;
begin
  Result := nil;
  Settings := RefactoringSettingsFor(AUri);
  if not Settings.InvertBoolean or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Context := InvertBooleanContextOf(Settings);
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Result := TLspInvertBoolean.Actions(True, Resolver, Shared.Tree, TDocumentUris.ToPath(AUri), AUri, APosition,
      Context);
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.InvertBoolean(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Settings: TRefactoringSettings;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TInvertBooleanContext;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, neuer Name.
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri", "position" und "name" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.InvertBoolean then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Boolean umkehren" ist abgeschaltet (refactoring.invertBoolean).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context := InvertBooleanContextOf(Settings);
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspInvertBoolean.Execute(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, Position,
      Trim(AArguments.Items[2].Value), Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Boolean umkehren: %d Stellen in %d Dateien, %d Warnungen',
    [(Answer.GetValue('places') as TJSONNumber).AsInt, (Answer.GetValue('files') as TJSONNumber).AsInt,
    (Answer.GetValue('warnings') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.PromoteVariableActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).PromoteVariable or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, TDocumentUris.ToPath(AUri));
    try
      Result := TLspPromoteVariable.Actions(Shared.Tree, Document.Text, AUri, APosition,
        TLspPromoteVariable.Lookup(Resolver, Shared.Tree, TDocumentUris.ToPath(AUri), ReadSourceText));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.PromoteVariable(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, Name.
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri", "position" und "name" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  if not RefactoringSettingsFor(Uri).PromoteVariable then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Lokale Variable und Feld umwandeln" ist abgeschaltet (refactoring.promoteVariable).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, TDocumentUris.ToPath(Uri));
    try
      Answer := TLspPromoteVariable.Execute(Shared.Tree, Document.Text, Uri, Position,
        Trim(AArguments.Items[2].Value), TLspPromoteVariable.Lookup(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri),
        ReadSourceText), ResolvedFormatStyleFor(Uri));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Variable/Feld umwandeln: %d Stellen, %d Warnungen',
    [(Answer.GetValue('places') as TJSONNumber).AsInt, (Answer.GetValue('warnings') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.AnonymousMethodActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TRefactoringSettings;
begin
  Result := nil;
  Settings := RefactoringSettingsFor(AUri);
  if not Settings.AnonymousMethod or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, TDocumentUris.ToPath(AUri));
    try
      Result := TLspAnonymousMethods.Actions(Shared.Tree, Document.Text, AUri, APosition,
        TLspAnonymousMethods.Lookup(Resolver, Shared.Tree, TDocumentUris.ToPath(AUri), ReadSourceText),
        TLspAnonymousMethods.CaptureOf(Settings.AnonymousMethodDeferredCapture), ResolvedFormatStyleFor(AUri));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.AnonymousMethod(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Settings: TRefactoringSettings;
begin
  // Argumente: URI, Position, Name.
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri", "position" und "name" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.AnonymousMethod then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Anonyme Methode und Methode umwandeln" ist abgeschaltet (refactoring.anonymousMethod).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, TDocumentUris.ToPath(Uri));
    try
      Answer := TLspAnonymousMethods.Execute(Shared.Tree, Document.Text, Uri, Position,
        Trim(AArguments.Items[2].Value), TLspAnonymousMethods.Lookup(Resolver, Shared.Tree,
        TDocumentUris.ToPath(Uri), ReadSourceText), TLspAnonymousMethods.CaptureOf(
        Settings.AnonymousMethodDeferredCapture), ResolvedFormatStyleFor(Uri));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Anonyme Methode umwandeln: %d Änderungen, %d Warnungen',
    [(Answer.GetValue('places') as TJSONNumber).AsInt, (Answer.GetValue('warnings') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.MethodKindActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).MethodKind or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, TDocumentUris.ToPath(AUri));
    try
      Result := TLspMethodWithoutSelf.Actions(Shared.Tree, Document.Text, AUri, APosition,
        TLspMethodWithoutSelf.Lookup(Resolver, Shared.Tree, TDocumentUris.ToPath(AUri), ReadSourceText));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.MethodKind(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Settings: TRefactoringSettings;
  Context: TMethodKindContext;
begin
  // Argumente: URI, Position, Umwandlung.
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Argumente "uri", "position" und "conversion" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.MethodKind then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Methode ohne Self umwandeln" ist abgeschaltet (refactoring.methodKind).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Context.WithStatic := Settings.MethodKindStatic;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspMethodWithoutSelf.Execute(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text,
      Position, Trim(AArguments.Items[2].Value), Context, ResolvedFormatStyleFor(Uri));
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Methode ohne Self umwandeln: %d Änderungen, %d Aufrufe, %d Warnungen',
    [(Answer.GetValue('places') as TJSONNumber).AsInt, (Answer.GetValue('calls') as TJSONNumber).AsInt,
    (Answer.GetValue('warnings') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.TypeAliasActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TRefactoringSettings;
  Scope: TTypeAliasScope;
begin
  Result := nil;
  Settings := RefactoringSettingsFor(AUri);
  if not Settings.TypeAlias or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  if not TTypeAlias.ScopeOf(Settings.TypeAliasScope, Scope) then
    Scope := TTypeAliasScope.InUnit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, TDocumentUris.ToPath(AUri));
    try
      Result := TLspTypeAlias.Actions(Shared.Tree, Document.Text, AUri, APosition, Scope,
        TLspTypeAlias.Lookup(Resolver));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.TypeAlias(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Context: TTypeAliasContext;
begin
  // Argumente: URI, Position, Name, Reichweite.
  if (AArguments = nil) or (AArguments.Count < 4) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Argumente "uri", "position", "name" und "scope" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  if not RefactoringSettingsFor(Uri).TypeAlias then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Typ-Alias einführen" ist abgeschaltet (refactoring.typeAlias).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspTypeAlias.Execute(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, Position,
      AArguments.Items[2].Value, Trim(AArguments.Items[3].Value), Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Typ-Alias einführen: %d Stellen, %d Dateien, %d Warnungen',
    [(Answer.GetValue('places') as TJSONNumber).AsInt, (Answer.GetValue('files') as TJSONNumber).AsInt,
    (Answer.GetValue('warnings') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.InlineTypeAlias(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Context: TTypeAliasContext;
begin
  // Argumente: URI, Position des Alias-Namens.
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "position" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  if not RefactoringSettingsFor(Uri).TypeAlias then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Alias auflösen" ist abgeschaltet (refactoring.typeAlias).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspTypeAlias.ExecuteInline(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, Position,
      Context);
  finally
    Resolver.Free;
  end;
  FLogger.Info(Format('Alias auflösen: %d Stellen, %d Dateien, %d Warnungen',
    [(Answer.GetValue('places') as TJSONNumber).AsInt, (Answer.GetValue('files') as TJSONNumber).AsInt,
    (Answer.GetValue('warnings') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.EnumTableActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).EnumTables or not FDocuments.TryGet(AUri, Document) or
    not MatchText(ExtractFileExt(TDocumentUris.ToPath(AUri)), ['.pas', '.dpr']) then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, TDocumentUris.ToPath(AUri));
    try
      Result := TLspEnumTables.Actions(Resolver, FIndex, Shared.Tree, Document.Text, AUri, APosition);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.EnumTable(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Context: TEnumTablesContext;
begin
  // Argumente: URI, Position, Name, Stelle.
  if (AArguments = nil) or (AArguments.Count < 4) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Argumente "uri", "position", "name" und "placement" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  if not RefactoringSettingsFor(Uri).EnumTables then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Namenstabelle anlegen" ist abgeschaltet (refactoring.enumTables).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context := Default(TEnumTablesContext);
  Context.ResourceStrings := RefactoringSettingsFor(Uri).EnumTablesResourceStrings;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspEnumTables.Execute(Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, Position,
    AArguments.Items[2].Value, Trim(AArguments.Items[3].Value), Context);
  FLogger.Info('Namenstabelle angelegt');
end;

function TServerComposition.EnumTablesSync(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Context: TEnumTablesContext;
begin
  // Argumente: URI, Position des Typnamens.
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "position" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  if not RefactoringSettingsFor(Uri).EnumTables then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Tabellen nachziehen" ist abgeschaltet (refactoring.enumTables).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context := Default(TEnumTablesContext);
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspEnumTables.Sync(Resolver, Shared.Tree, TDocumentUris.ToPath(Uri), Document.Text, Position,
      Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Tabellen nachziehen: %d Stellen, %d Dateien, %d Warnungen',
    [(Answer.GetValue('places') as TJSONNumber).AsInt, (Answer.GetValue('files') as TJSONNumber).AsInt,
    (Answer.GetValue('warnings') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.Unwrap(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  IndentWidth: Integer;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, optional die Einrückungsbreite des Editors.
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "position" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  IndentWidth := 0;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONNumber) then
    IndentWidth := TJSONNumber(AArguments.Items[2]).AsInt;
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspUnwrap.Execute(Resolver, Shared.Tree, Document.Text, Position, RefactoringContextFor(Uri),
      IndentWidth);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Umschließung entfernen: %d Konstrukte', [(Answer.GetValue('candidates') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.StepTargets(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Line: Integer;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
begin
  // Argumente: URI und Zeile (ab 0) des Ausführungspunkts (#836).
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONNumber) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "line" fehlen');
  Uri := AArguments.Items[0].Value;
  Line := TJSONNumber(AArguments.Items[1]).AsInt;
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspStepTargets.Execute(Resolver, FIndex, Shared.Tree, Document.Text, TDocumentUris.ToPath(Uri), Line,
      ReadSourceText);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Gezielt hineinspringen: %d Aufrufe', [(Answer.GetValue('calls') as TJSONArray).Count]));
  Result := Answer;
end;

function TServerComposition.StepFilter(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mFileName, mText: string;
  mLine: Integer;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mTree: TSyntaxTree;
  mAnswer: TJSONObject;
begin
  // Argumente: URI und Zeile (ab 0) des Halts nach F7 bzw. des Methodenkopfs im Kontextmenü (#850).
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONNumber) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "line" fehlen');
  mUri := AArguments.Items[0].Value;
  mLine := TJSONNumber(AArguments.Items[1]).AsInt;
  if FDocuments.TryGet(mUri, mDocument) then
  begin
    mShared := TSyntaxTreeCache.Get(mDocument, nil);
    mAnswer := TLspStepFilter.Execute(mShared.Tree, mDocument.Text, mLine);
  end
  else
  begin
    // Nach F7 steht der Halt oft in einer Datei, die der Editor erst jetzt öffnet: selbst lesen.
    mFileName := TDocumentUris.ToPath(mUri);
    if not ReadSourceText(mFileName, mText) then
      raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht lesbar.');
    mTree := TSyntaxTreeCache.Parse(mText);
    try
      mAnswer := TLspStepFilter.Execute(mTree, mText, mLine);
    finally
      mTree.Free;
    end;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Schrittfilter: Routine %s', [BoolToStr(mAnswer.GetValue<Boolean>('found', False), True)]));
  Result := mAnswer;
end;

function TServerComposition.StepFilterCounts(const AArguments: TJSONArray): TJSONValue;
var
  mPatterns: TArray<string>;
  mCounts: TLspStepFilterCounts;
  mUnit: TUnitIndex;
  mText: string;
  mTree: TSyntaxTree;
begin
  // Argument: Liste der Muster (#850). Gezählt werden die Projekt-Units, Bibliotheken nicht.
  mPatterns := TLspStepFilter.ReadPatterns(AArguments);
  mCounts := TLspStepFilter.NewCounts(mPatterns);
  for mUnit in FIndex.Units do
  begin
    if mUnit.Library_ or (mUnit.FileName = '') then
      Continue;
    if mCounts.Files >= TLspStepFilter.MaxFiles then
    begin
      mCounts.Truncated := True;
      Break;
    end;
    if not ReadSourceText(mUnit.FileName, mText) then
      Continue;
    mTree := TSyntaxTreeCache.Parse(mText);
    try
      TLspStepFilter.AddCounts(mTree, mText, mPatterns, mCounts);
    finally
      mTree.Free;
    end;
  end;
  FLogger.Info(Format('Schrittfilter: %d Dateien, %d Routinen', [mCounts.Files, mCounts.Routines]));
  Result := TLspStepFilter.CountsToJson(mCounts);
end;

function TServerComposition.MoveClass(const AArguments: TJSONArray): TJSONValue;
var
  Uri, FileName: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TMoveClassContext;
  Workspace: TShellWorkspace;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, Name der neuen Unit.
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri", "position" und "name" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  if not RefactoringSettingsFor(Uri).MoveClass then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Klasse verschieben" ist abgeschaltet (refactoring.moveClass).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  FileName := TDocumentUris.ToPath(Uri);
  Context := Default(TMoveClassContext);
  Context.Index := FIndex;
  Context.Files := ProjectSourceFiles;
  Context.ReadText := ReadSourceText;
  Context.Exists :=
    function(const AFileName: string): Boolean
    var
      Open: ITextDocument;
    begin
      Result := FileExists(AFileName) or FDocuments.TryGet(TDocumentUris.FromPath(AFileName), Open);
    end;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(FileName);
    Context.HasProject := (Workspace <> nil) and Workspace.Project(Context.Project);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspMoveClass.Execute(Resolver, Shared.Tree, FileName, Document.Text, Position,
      AArguments.Items[2].Value, Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Klasse verschieben: %d Dateiänderungen',
    [TJSONArray(TJSONObject(Answer.GetValue('edit')).GetValue('documentChanges')).Count]));
  Result := Answer;
end;

function TServerComposition.RefactoringProject(const AFileName: string; out AProject: TProjectInfo): Boolean;
var
  Workspace: TShellWorkspace;
begin
  AProject := Default(TProjectInfo);
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(AFileName);
    Result := (Workspace <> nil) and Workspace.Project(AProject);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.SourceExists(const AFileName: string): Boolean;
var
  Open: ITextDocument;
begin
  Result := FileExists(AFileName) or FDocuments.TryGet(TDocumentUris.FromPath(AFileName), Open);
end;

function TServerComposition.ExtractInterfaceActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).ExtractInterface or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspExtractInterface.Actions(True, Shared.Tree, Document.Text, AUri, APosition);
end;

function TServerComposition.ExtractInterface(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
var
  Uri, FileName: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TExtractInterfaceContext;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, beim Ausführen {name, unit, members}.
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "position" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  if not RefactoringSettingsFor(Uri).ExtractInterface then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Interface herauslösen" ist abgeschaltet (refactoring.extractInterface).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  FileName := TDocumentUris.ToPath(Uri);
  Context := Default(TExtractInterfaceContext);
  Context.Index := FIndex;
  Context.ReadText := ReadSourceText;
  Context.Exists := SourceExists;
  Context.HasProject := RefactoringProject(FileName, Context.Project);
  Shared := TSyntaxTreeCache.Get(Document, nil);
  if APrepare then
    Exit(TLspExtractInterface.Prepare(Shared.Tree, Document.Text, Position, Context));
  if AArguments.Count < 3 then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument mit Name, Ziel und Mitgliedern fehlt');
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspExtractInterface.Execute(Resolver, Shared.Tree, FileName, Document.Text, Position,
      AArguments.Items[2], Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Interface herauslösen: %d Methoden', [(Answer.GetValue('methods') as TJSONNumber).AsInt]));
  Result := Answer;
end;

function TServerComposition.ExtractSuperclassActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).ExtractSuperclass or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspExtractSuperclass.Actions(True, Shared.Tree, Document.Text, AUri, APosition);
end;

function TServerComposition.ExtractSuperclass(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
var
  Uri, FileName: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TRefactoringSettings;
  Context: TExtractSuperclassContext;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, beim Ausführen {name, unit, members, abstract}.
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "position" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.ExtractSuperclass then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Basisklasse herauslösen" ist abgeschaltet (refactoring.extractSuperclass).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  FileName := TDocumentUris.ToPath(Uri);
  Context := Default(TExtractSuperclassContext);
  Context.Index := FIndex;
  Context.ReadText := ReadSourceText;
  Context.Exists := SourceExists;
  Context.HasProject := RefactoringProject(FileName, Context.Project);
  Context.Target := Settings.ExtractSuperclassTarget;
  Context.NameSuffix := Settings.ExtractSuperclassNameSuffix;
  Context.MethodMode := Settings.ExtractSuperclassMethodMode;
  Context.RaiseVisibility := Settings.ExtractSuperclassRaiseVisibility;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  if APrepare then
    Exit(TLspExtractSuperclass.Prepare(Shared.Tree, Document.Text, Position, Context));
  if AArguments.Count < 3 then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument mit Name, Ziel und Mitgliedern fehlt');
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspExtractSuperclass.Execute(Resolver, Shared.Tree, FileName, Document.Text, Position,
      AArguments.Items[2], Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Basisklasse herauslösen: %d Mitglieder', [(Answer.GetValue('moved') as TJSONNumber).AsInt]));
  Result := Answer;
end;

function TServerComposition.MoveMemberActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).MoveMember or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspMoveMember.Actions(True, Shared.Tree, Document.Text, TDocumentUris.ToPath(AUri), AUri, APosition,
    FIndex);
end;

function TServerComposition.MoveMember(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
var
  Uri, FileName, Direction: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TMoveMemberContext;
  Answer: TJSONObject;
begin
  // Argumente: URI, Position, Richtung, beim Ausführen {members, abstract, targets, option}.
  if (AArguments = nil) or (AArguments.Count < 3) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri", "position" und Richtung fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Direction := AArguments.Items[2].Value;
  if not RefactoringSettingsFor(Uri).MoveMember then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Mitglied verschieben" ist abgeschaltet (refactoring.moveMember).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  FileName := TDocumentUris.ToPath(Uri);
  Context := Default(TMoveMemberContext);
  Context.Index := FIndex;
  Context.ReadText := ReadSourceText;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  if APrepare then
    Exit(TLspMoveMember.Prepare(Shared.Tree, Document.Text, FileName, Position, Direction, Context));
  if AArguments.Count < 4 then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument mit Mitgliedern und Zielen fehlt');
  Context.Files := ProjectSourceFiles;
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Answer := TLspMoveMember.Execute(Resolver, Shared.Tree, FileName, Document.Text, Position, Direction,
      AArguments.Items[3], Context);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Mitglied verschieben: %d Mitglieder', [(Answer.GetValue('moved') as TJSONNumber).AsInt]));
  Result := Answer;
end;

function TServerComposition.UnitRenamed(const AArguments: TJSONArray): TJSONValue;
var
  OldUri, NewUri: string;
  Files: TArray<string>;
  Item: TJSONValue;
  Answer: TJSONObject;
begin
  // Argumente: alte URI, neue URI, URIs der Dateien des Bereichs (#512).
  if (AArguments = nil) or (AArguments.Count < 3) or not (AArguments.Items[2] is TJSONArray) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "old", "new" und "files" fehlen');
  OldUri := AArguments.Items[0].Value;
  NewUri := AArguments.Items[1].Value;
  if not RefactoringSettingsFor(NewUri).UnitRenameFollowUp then
  begin
    Answer := TJSONObject.Create;
    Answer.AddPair('enabled', TJSONBool.Create(False));
    Exit(Answer);
  end;
  Files := nil;
  for Item in TJSONArray(AArguments.Items[2]) do
    Files := Files + [TDocumentUris.ToPath(Item.Value)];
  Answer := TLspUnitRename.Execute(TDocumentUris.ToPath(OldUri), TDocumentUris.ToPath(NewUri), Files, ReadSourceText);
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Unit umbenannt: %d von %d Dateien betroffen',
    [(Answer.GetValue('count') as TJSONNumber).AsInt, Length(Files)]));
  Result := Answer;
end;

function TServerComposition.PasteUses(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Context: TUsesContext;
  Provider: TUsesContextProvider;
  Answer: TJSONObject;
begin
  // Argumente: URI, eingefügter Bereich, optional die gewählten Units (#515).
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "range" fehlen');
  Uri := AArguments.Items[0].Value;
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Context := Default(TUsesContext);
  Provider := FCodeActions.UsesContextFor;
  if Assigned(Provider) and not Provider(Uri, Context) then
    Context := Default(TUsesContext);
  Shared := TSyntaxTreeCache.Get(Document, nil);
  try
    Answer := TLspSmartPaste.Execute(AArguments, Uri, Document.Text, Shared.Tree, Context,
      function(const AUnitName: string): TArray<string>
      var
        UnitIndex: TUnitIndex;
      begin
        Result := nil;
        EnsureUnit(AUnitName);
        if FIndex.FindUnit(AUnitName, UnitIndex) then
          Result := UnitIndex.InterfaceUses;
      end);
  except
    on E: EArgumentException do
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, E.Message);
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  if Answer.GetValue('units') is TJSONArray then
    FLogger.Info(Format('Einfügen: %d Units, %d mehrdeutig', [TJSONArray(Answer.GetValue('units')).Count,
      TJSONArray(Answer.GetValue('choices')).Count]))
  else
    FLogger.Info(Format('Einfügen: %d Units eingetragen', [TJSONArray(Answer.GetValue('added')).Count]));
  Result := Answer;
end;

function TServerComposition.ExplicitTypeActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Action: TCodeAction;
  LineBreak: string;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).ExplicitType or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  LineBreak := #10;
  if Pos(#13#10, Document.Text) > 0 then
    LineBreak := #13#10;
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    if TLspInlayHints.ExplicitTypeAction(Resolver, Shared.Tree, TDocumentUris.ToPath(AUri), APosition, LineBreak,
      Action) then
      Result := [TLspCodeActions.ActionToJson(AUri, Action)];
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.DisableWarningActions(const AUri: string;
  const ARange: TTextRange): TArray<TJSONObject>;
var
  Options: TDisableWarningOptions;
  Messages: TArray<TCompilerMessage>;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  Result := nil;
  Options := Default(TDisableWarningOptions);
  Options.Enabled := RefactoringSettingsFor(AUri).DisableWarning;
  if not Options.Enabled or not FDocuments.TryGet(AUri, Document) then
    Exit;
  Messages := FCompilerResults.MessagesFor(TDocumentUris.ToPath(AUri));
  if Messages = nil then
    Exit;
  Options.AskReason := RefactoringSettingsFor(AUri).DisableWarningReason;
  Options.Version := DelphiVersionFor(AUri);
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspDisableWarning.Actions(Options, Shared.Tree, AUri, ARange.StartPos.Line, ARange.EndPos.Line,
    Messages);
end;

function TServerComposition.CompilerFixActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  Messages: TArray<TCompilerMessage>;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Uses_: TUsesContext;
  Context: TCompilerFixContext;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).CompilerFixes or not FDocuments.TryGet(AUri, Document) then
    Exit;
  Messages := FCompilerResults.MessagesFor(TDocumentUris.ToPath(AUri));
  if Messages = nil then
    Exit;
  Context := Default(TCompilerFixContext);
  if FCodeActions.UsesContextFor(AUri, Uses_) then
  begin
    Context.Declaring := Uses_.Declaring;
    Context.Namespaces := Uses_.Namespaces;
  end;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspCompilerFixes.Actions(True, Document.Text, Shared.Tree, AUri, ARange, Messages, Context);
end;

function TServerComposition.MissingUnitActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  FileName: string;
  Messages: TArray<TCompilerMessage>;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).MissingUnit then
    Exit;
  FileName := TDocumentUris.ToPath(AUri);
  Messages := FCompilerResults.MessagesFor(FileName);
  if Messages = nil then
    Exit;
  Result := TLspMissingUnit.Actions(True, ARange.StartPos.Line, ARange.EndPos.Line, Messages,
    function(const AUnitName: string; out ASetup: TMissingUnitSetup): Boolean
    begin
      Result := MissingUnitSetupFor(FileName, AUnitName, ASetup);
    end);
end;

function TServerComposition.MissingUnitSetupFor(const AFileName, AUnitName: string;
  out ASetup: TMissingUnitSetup): Boolean;
var
  Workspace, Other: TShellWorkspace;
  Group: TArray<TMissingUnitProject>;
  Member: TMissingUnitProject;
  OtherProject: TProjectInfo;
  Users: Integer;
begin
  ASetup := Default(TMissingUnitSetup);
  Group := nil;
  // Arbeitsbereich festhalten, die .dproj-Dateien aber außerhalb von FWorkspacesLock lesen (#647).
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(AFileName);
    if Workspace = nil then
      Exit(False);
    for Other in FWorkspaces do
      if (Other <> Workspace) and Other.Project(OtherProject) and
        not SameFileName(OtherProject.FileName, Workspace.ProjectFileName) then
      begin
        Member.FileName := OtherProject.FileName;
        Member.SearchPaths := OtherProject.SearchPaths;
        Group := Group + [Member];
      end;
    if FWorkspaceUsers.TryGetValue(Workspace, Users) then
      FWorkspaceUsers[Workspace] := Users + 1
    else
      FWorkspaceUsers.Add(Workspace, 1);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  try
    Result := Workspace.MissingUnitSetup(ASetup);
  finally
    TMonitor.Enter(FWorkspacesLock);
    try
      Users := FWorkspaceUsers[Workspace] - 1;
      if Users = 0 then
        FWorkspaceUsers.Remove(Workspace)
      else
        FWorkspaceUsers[Workspace] := Users;
      TMonitor.PulseAll(FWorkspacesLock);
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
  end;
  if not Result then
    Exit;
  ASetup.UnitName := AUnitName;
  ASetup.GroupProjects := Group;
  // Nur der Index: nichts nachladen, die Suche läuft bei jeder Code-Aktion auf der Zeile.
  ASetup.IndexFile :=
    function(AName: string): string
    var
      UnitIndex: TUnitIndex;
    begin
      if FIndex.FindUnit(AName, UnitIndex) then
        Result := UnitIndex.FileName
      else
        Result := '';
    end;
end;

function TServerComposition.DisableWarning(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  if (AArguments = nil) or (AArguments.Count < 1) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument "uri" fehlt');
  Uri := AArguments.Items[0].Value;
  if not RefactoringSettingsFor(Uri).DisableWarning then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Warnung abschalten" ist abgeschaltet (refactoring.disableWarning).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Result := TLspDisableWarning.Execute(AArguments, Document.Text, Shared.Tree, DelphiVersionFor(Uri));
end;

function TServerComposition.SuggestConstActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Action: TCodeAction;
  FileName: string;
begin
  Result := nil;
  if not RefactoringSettingsFor(AUri).SuggestConst or
    not TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, LanguageLevelFor(AUri)) or
    not FDocuments.TryGet(AUri, Document) or not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  FileName := TDocumentUris.ToPath(AUri);
  // Dieselbe Übergabeart von Argumenten wie die Unterstreichung im Plugin (atlas.server.reassigned).
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, FileName);
    try
      if TSuggestConst.Action(Document.Text, Shared.Tree, APosition,
        TResolvedSignatures.Lookup(Resolver, Shared.Tree, FileName), Action) then
        Result := [TLspCodeActions.ActionToJson(AUri, Action)];
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

/// <summary>Typ einer Inline-Variablen ohne Typangabe für „In var-Block verschieben“ (#644): dieselbe Ermittlung
/// wie „Typ ausschreiben“ (#453), samt der uses, die ihn sichtbar machen.</summary>
function VarBlockTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  ALineBreak: string): TVarBlockTypeLookup;
begin
  Result :=
    function(ADecl: TSyntaxNode; out AType: string; out AEdits: TArray<TTextEdit>): Boolean
    var
      Found: TInferredType;
      Action: TCodeAction;
    begin
      AType := '';
      AEdits := nil;
      Result := False;
      for Found in TLspInlayHints.Inferred(AResolver, ATree, AFileName, TTextRange.Create(ADecl.StartPos,
        ADecl.EndPos)) do
        if not Found.ForIn and TLspInlayHints.ExplicitTypeAction(AResolver, ATree, AFileName, Found.NameStart,
          ALineBreak, Action) and (Action.Edits <> nil) then
        begin
          // Erstes Edit ": Typ", die übrigen ergänzen uses.
          AType := Copy(Action.Edits[0].NewText, 3, MaxInt);
          AEdits := Copy(Action.Edits, 1, MaxInt);
          Exit(True);
        end;
    end;
end;

function TServerComposition.VarBlockActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TRefactoringSettings;
  Options: TVarBlockOptions;
  Action: TCodeAction;
  FileName, LineBreak: string;
begin
  Result := nil;
  Settings := RefactoringSettingsFor(AUri);
  if not Settings.VarBlock or not FDocuments.TryGet(AUri, Document) or
    not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  FileName := TDocumentUris.ToPath(AUri);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    Resolver.PinTree(Shared.Tree, FileName);
    try
      Options := TVarBlockOptions.Default;
      Options.InlineVariables := TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable,
        LanguageLevelFor(AUri));
      Options.Merge := Settings.VarBlockMerge;
      Options.Sort := TVarBlock.SortOf(Settings.VarBlockSort);
      Options.Style := ResolvedFormatStyleFor(AUri);
      Options.Lookup := TResolvedSignatures.Lookup(Resolver, Shared.Tree, FileName);
      LineBreak := #10;
      if Pos(#13#10, Document.Text) > 0 then
        LineBreak := #13#10;
      Options.Types := VarBlockTypes(Resolver, Shared.Tree, FileName, LineBreak);
      for Action in TVarBlock.Actions(Document.Text, Shared.Tree, APosition, Options) do
        Result := Result + [TLspCodeActions.ActionToJson(AUri, Action)];
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

function TServerComposition.RefactoringContextFor(const AUri: string): TRefactoringContext;
begin
  Result := Default(TRefactoringContext);
  Result.Settings := RefactoringSettingsFor(AUri);
  Result.Index := FIndex;
  Result.EnsureUnit := EnsureUnit;
  Result.Namespaces := FRename.Namespaces;
  Result.FileName := TDocumentUris.ToPath(AUri);
  Result.ReadText := ReadSourceText;
  Result.InlineVar := Result.Settings.InlineVar and
    TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, LanguageLevelFor(AUri));
  Result.IfExpression := TLanguageFeatures.IsAvailable(TLanguageFeature.IfExpression, LanguageLevelFor(AUri));
  Result.Style := ResolvedFormatStyleFor(AUri);
  Result.NewNames := NewNamesFor(AUri);
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
      Settings := FLooseSettings
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

function TServerComposition.RefactoringActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Context: TRefactoringContext;
  Action: TCodeAction;
begin
  Result := nil;
  if not FDocuments.TryGet(AUri, Document) or not SameText(ExtractFileExt(TDocumentUris.ToPath(AUri)), '.pas') then
    Exit;
  Context := RefactoringContextFor(AUri);
  if not (Context.Settings.Extract or Context.Settings.CompleteCase or Context.Settings.ResolveWith or
    Context.Settings.CreateMethod or Context.Settings.InlineCode or Context.Settings.IfCase or
    Context.Settings.Conditions or Context.Settings.ConditionalExpression or Context.Settings.NestedRoutine) then
    Exit;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  for Action in TLspRefactorings.Actions(Shared.Tree, Document.Text, ARange, Context) do
    Result := Result + [TLspCodeActions.ActionToJson(AUri, Action)];
end;

function TServerComposition.ChangeSignature(const AArguments: TJSONArray; APrepare: Boolean): TJSONValue;
var
  Uri, FileName: string;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TRefactoringSettings;
  Mode: TNewParameterMode;
  Request: TChangeSignatureRequest;
  Outcome: TChangeSignatureOutcome;
begin
  // Argumente: URI, Position, beim Ausführen die neue Signatur (TLspChangeSignature.ReadRequest).
  if (AArguments = nil) or (AArguments.Count < 2) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argumente "uri" und "position" fehlen');
  Uri := AArguments.Items[0].Value;
  Position := TLspPositions.ReadPosition(AArguments.Items[1]);
  Settings := RefactoringSettingsFor(Uri);
  if not Settings.ChangeSignature then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      '"Signatur ändern" ist abgeschaltet (refactoring.changeSignature).');
  if not FDocuments.TryGet(Uri, Document) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Die Datei ist nicht geöffnet.');
  FileName := TDocumentUris.ToPath(Uri);
  Mode := TNewParameterMode.UpdateCallers;
  if Settings.NewParameterOverload then
    Mode := TNewParameterMode.Overload;
  Shared := TSyntaxTreeCache.Get(Document, nil);
  Resolver := TNameResolver.Create(FIndex, EnsureUnit);
  try
    Resolver.Namespaces := FRename.Namespaces;
    if APrepare then
      Exit(TLspChangeSignature.InfoToJson(TLspChangeSignature.Prepare(Resolver, FIndex, Shared.Tree, FileName,
        Position, ProjectSourceFiles, ReadSourceText, nil), Mode, Settings.VirtualOverload));
    if AArguments.Count < 3 then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument mit der neuen Signatur fehlt');
    Request := TLspChangeSignature.ReadRequest(AArguments.Items[2], Mode, Settings.VirtualOverload);
    Outcome := TLspChangeSignature.Execute(Resolver, FIndex, Shared.Tree, FileName, Position, Request,
      ProjectSourceFiles, ReadSourceText,
      function(const AFileName: string): Boolean
      begin
        Result := FileExists(AFileName) and FileIsReadOnly(AFileName);
      end, nil);
  finally
    Resolver.Free;
  end;
  // Nur Zahlen ins Log, keine Namen und Pfade (#647).
  FLogger.Info(Format('Signatur ändern: %d Änderungen, %d Warnungen', [Length(Outcome.Edits),
    Length(Outcome.Warnings)]));
  Result := TLspChangeSignature.OutcomeToJson(Outcome);
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
      Stamp := -1 - Document.Version
    else if FileExists(FileName) then
      Stamp := Trunc(TFile.GetLastWriteTimeUtc(FileName) * MSecsPerDay)
    else
      Stamp := 0;
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
      Result := TJSONObject.ParseJSONValue(AText);
    if (Result = nil) and (AText.Trim <> '') then
      Result := TJSONString.Create(AText);
    if Result = nil then
      Result := TJSONNull.Create;
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
    Options := TJSONObject(AArguments.Items[0]);
  if Options <> nil then
  begin
    if Options.GetValue('anonymize') is TJSONBool then
      Input.Anonymize := TJSONBool(Options.GetValue('anonymize')).AsBoolean;
    if Options.GetValue('client') is TJSONString then
      Input.Client := Options.GetValue('client').Value;
    if Options.GetValue('target') is TJSONString then
      Target := Options.GetValue('target').Value;
  end;
  Input.ServerVersion := TProductVersion.Version;
  Input.Created := Now;
  Input.Configuration := ConfigurationReport;
  if FRecentLog <> nil then
    Input.LogLines := FRecentLog.Lines;
  Input.Requests := FStatistics.Recent;
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
      Input.Workspaces := Input.Workspaces + [Workspace.Root];
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
    if not Workspace.Processes(Item.CacheFile, Item.Processes) then
      Continue;
    Status := Workspace.IndexStatus;
    Item.Name := Workspace.Name;
    Item.Project := Status.Project;
    Item.FormatVersion := TIndexCache.FormatVersion;
    Item.Units := Status.Parsed + Status.FromCache;
    if TFile.Exists(Item.CacheFile) then
      Item.Saved := TFile.GetLastWriteTime(Item.CacheFile);
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
    Result.DocumentBytes := Result.DocumentBytes + Length(Document.Text) * SizeOf(Char);
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
    begin
      Result.Workspaces := Result.Workspaces + [Workspace.IndexStatus];
      // Projektwahl (#46): aktiv in der IDE und per selectProject ausgewählt.
      Result.Workspaces[High(Result.Workspaces)].Active := (Workspace.ProjectFileName <> '') and
        SameText(Workspace.ProjectFileName, FIdeProject.ActiveProject);
      Result.Workspaces[High(Result.Workspaces)].Selected := IsSelectedProject(Workspace);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result.Requests := FStatistics.Snapshot;
  CollectCompilerStatus(Result);
end;

procedure TServerComposition.CollectCompilerStatus(var AStatus: TServerStatus);
var
  Choice: TCompilerBackendChoice;
  Job: TShellCompileJob;
  Known: Boolean;
begin
  // Weg zum Compiler (#261): zuletzt gewählt; sonst jetzt prüfen (die Ausgabe der Installation ist
  // meist schon gemerkt). Eine Meldung zeigt erst ein Compilerlauf.
  TMonitor.Enter(FCompileLock);
  try
    Known := FHasCompilerChoice;
    Choice := FCompilerChoice;
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if not Known and not FRestricted then
    try
      if ChooseCompiler('', Job, Choice) then
      begin
        RememberCompilerChoice(Choice);
        Known := True;
      end;
    except
      on E: Exception do
        FLogger.Debug('Weg zum Compiler nicht geprüft: ' + E.ClassName);
    end;
  if FRestricted then
  begin
    Choice := TCompilerBackendChoice.Unavailable('Der Arbeitsbereich ist nicht vertrauenswürdig', '');
    Known := True;
  end;
  if not Known then
  begin
    AStatus.Compiler := TCompilerBackends.UncheckedStatus;
    Exit;
  end;
  AStatus.Compiler := Choice.StatusText;
  AStatus.CompilerBackend := TCompilerBackends.BackendText(Choice.Backend);
  AStatus.CompilerReason := Choice.MessageText;
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
    Exit;
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    for Finding in TLspSyntaxDiagnostics.RuleFindings(AText, Tree, Context) do
      if (Finding.Range.StartPos.Line = ALine) and not SameText(Finding.RuleId, 'slash-command') and
        not MatchText(Finding.RuleId, AIds) then
        AIds := AIds + [Finding.RuleId];
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
    Exit;
  Tree := TSyntaxTreeCache.Parse(AText);
  Catalog := TRuleCatalog.Create(RuleCatalogBaseJson, RuleCatalogOverlayJson('de'));
  try
    for Finding in TLspSyntaxDiagnostics.RuleFindings(AText, Tree, Context) do
    begin
      if (Finding.Range.StartPos.Line <> ALine) or SameText(Finding.RuleId, 'slash-command') then
        Continue;
      Item := Default(TSlashFinding);
      Item.RuleId := Finding.RuleId;
      Item.Message := Finding.Message;
      if Catalog.TryFind(Finding.RuleId, Entry) then
        Item.Explanation := TRuleCatalog.Explanation(Entry, #10);
      // Nur als sicher markierte Korrekturen, wie beim Speichern (#182).
      if TRuleCodeActions.FixAll([Finding], Action) then
        Item.SafeFix := Action.Edits;
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
    ADisabled := ADisabled + ['uses'];
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
      Result := ''
    else
    begin
      // Tatsächlich gewählte Installation (#47), sonst die konfigurierte Version.
      Result := Workspace.DelphiVersion;
      if Result = '' then
        Result := Workspace.Configuration.Settings.DelphiVersion;
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
    if Trim(Name) <> '' then
      Result := Result + [TFormatRoutines.Custom(Name, -1)];
  Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
  if (Workspace <> nil) and Workspace.Project(Project) and FIdeProject.Find(Project.FileName, Context) then
    Result := Result + Context.FormatFunctions;
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
      Text := '';
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Feld "textDocument.uri" fehlt in ' + TAffectedTests.Method);
  mSettings := SettingsFor(mUri);
  mQuery := Default(TShellAffectedQuery);
  TMonitor.Enter(FWorkspacesLock);
  try
    mWorkspace := PickWorkspace(TDocumentUris.ToPath(mUri));
    if mWorkspace = nil then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, 'Kein Arbeitsbereich zu ' + mUri);
    mQuery.WorkingDir := mWorkspace.Root;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if not TJSONObject(AParams).TryGetValue<string>('base', mQuery.Base) then
    mQuery.Base := '';
  if not TJSONObject(AParams).TryGetValue<Boolean>('includeUncommitted', mQuery.IncludeUncommitted) then
    mQuery.IncludeUncommitted := True;
  if not TJSONObject(AParams).TryGetValue<Integer>('depth', mQuery.Depth) then
    mQuery.Depth := 0;
  mRequest := Default(TAffectedRequest);
  mRequest.Files := ProjectSourceFiles;
  mRequest.TestPrograms := TShellAffectedTests.TestPrograms(mRequest.Files, ReadSourceText);
  if TestUnitContextFor(mUri, mContext) and (mContext.TestProgram <> '') and
    (IndexText(mContext.TestProgram, mRequest.TestPrograms) < 0) then
    mRequest.TestPrograms := mRequest.TestPrograms + [mContext.TestProgram];
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
      mFound := TShellAffectedTests.Run(mProcess, mSettings, mQuery, mResolver, FIndex, mRequest, mReadDisk,
        ACancellation);
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
      for Candidate in FWorkspaces do
        if (Candidate.Project(Project) and (SameText(Project.FileName, AFileName) or
          SameText(Project.MainSource, AFileName) or SameText(ChangeFileExt(Project.FileName, '.dproj'),
          ChangeFileExt(AFileName, '.dproj')))) or SameText(Candidate.ProjectFile, AFileName) then
        begin
          Workspace := Candidate;
          Break;
        end;
    if (Workspace = nil) and (AFileName <> '') then
      Workspace := WorkspaceOf(AFileName);
    Workspace := TShellWorkspace.Choose(Workspace, FWorkspaces);
    if Workspace = nil then
      Exit(False);
    ASource.Settings := Workspace.Configuration.Settings;
    ASource.Root := Workspace.Root;
    if Workspace.Project(Project) then
      ASource.Title := ChangeFileExt(ExtractFileName(Project.FileName), '')
    else
      ASource.Title := Workspace.Name;
    if AProject then
      ASource.Files := Workspace.ProjectFiles;
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
    Exit;
  ASettings := Source.Settings;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    if AFileName <> '' then
      Workspace := WorkspaceOf(AFileName);
    Workspace := TShellWorkspace.Choose(Workspace, FWorkspaces);
    if Workspace <> nil then
      ANamespaces := Workspace.Namespaces;
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
    Exit;
  ASettings := Source.Settings;
  ARequest := TArchitectureRequest.FromSettings(ASettings);
  Scope := AScope;
  if Scope = '' then
    Scope := ASettings.ArchitectureScope;
  ARequest.Scope := Scope;
  ARequest.Root := Source.Root;
  ARequest.Title := Source.Title;
  if Scope = 'project' then
    ARequest.Files := Source.Files
  else
  begin
    // Projektgruppe (#648): die Dateien aller geladenen Projekte.
    Files := nil;
    TMonitor.Enter(FWorkspacesLock);
    try
      for Workspace in FWorkspaces do
        Files := Files + Workspace.ProjectFiles;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
    ARequest.Files := Files;
  end;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    if AFileName <> '' then
      Workspace := WorkspaceOf(AFileName);
    Workspace := TShellWorkspace.Choose(Workspace, FWorkspaces);
    if Workspace <> nil then
      ARequest.Namespaces := Workspace.Namespaces;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
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
      Workspace := WorkspaceOf(AFileName);
    Workspace := TShellWorkspace.Choose(Workspace, FWorkspaces);
    if Workspace <> nil then
    begin
      Result.Root := Workspace.Root;
      Result.Namespaces := Workspace.Namespaces;
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
      Result := TRationaleOptions.FromSettings(FLooseSettings, '')
    else
      Result := TRationaleOptions.FromSettings(Workspace.Configuration.Settings, Workspace.Root);
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
    Exit;
  IncludePaths := nil;
  HasProject := False;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(Result.FileName);
    if Workspace <> nil then
    begin
      IncludePaths := Workspace.IncludePaths;
      HasProject := Workspace.Project(Project);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result.ResolveInclude := TIncludeFiles.Resolver(IncludePaths);
  // Dieselben Symbole wie beim Abblenden inaktiver Zweige.
  Result.HasDefines := DefinesFor(AUri, Defines);
  if not Result.HasDefines then
    Exit;
  Result.Defines := Defines;
  if not HasProject then
    Project := Default(TProjectInfo);
  Predefined := TPascalPreprocessor.PredefinedSymbols(Project.Platform,
    TPascalPreprocessor.CompilerVersionFromDefines(Defines));
  Result.Config := Project.Config;
  Result.Platform := Project.Platform;
  Own := nil;
  for Define in Defines do
    if (IndexText(Define, Predefined) < 0) and not TPascalPreprocessor.IsSwitchEntry(Define) then
      Own := Own + [Define];
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
      IncludePaths := Workspace.IncludePaths;
      Result.HasProject := Workspace.Project(Project);
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result.ResolveInclude := TIncludeFiles.Resolver(IncludePaths);
  if not Result.HasProject then
    Project := Default(TProjectInfo);
  Result.Configuration := Project.Config;
  Result.Platform := Project.Platform;
  Result.Input.Properties := Project.Properties;
  // Dieselben Symbole und Schalterstände wie beim Abblenden inaktiver Zweige.
  if not DefinesFor(AUri, Defines) then
    Exit;
  Result.Input.Defines := Defines;
  Predefined := TPascalPreprocessor.PredefinedSymbols(Project.Platform,
    TPascalPreprocessor.CompilerVersionFromDefines(Defines));
  Own := nil;
  for Define in Defines do
    if (IndexText(Define, Predefined) < 0) and not TPascalPreprocessor.IsSwitchEntry(Define) then
      Own := Own + [Define];
  for Source in TConditionalSymbols.SourcesOf(Own, Project.DefineOrigins, Predefined, Project.Platform) do
  begin
    Kind := TSwitchOriginKind.Project;
    if IndexText(Source.Name, Predefined) >= 0 then
      Kind := TSwitchOriginKind.Default;
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
        AText := TFileEncoding.LoadText(AFileName);
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
    Result := (Workspace <> nil) and Workspace.Project(Project);
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
  Result.Rules := RuleContextFor;
  Result.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompilerResults.MessagesFor(AFileName);
    end;
  // Ungenutzte uses (#621): dieselbe Analyse wie die uses-Aktionen, auch für die Diagnosen.
  Result.UsesContext := UsesContextFor;
end;

function TServerComposition.RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  Workspace, Other: TShellWorkspace;
  FileName, Folder: string;
  Project: TProjectInfo;
  Projects: TArray<TProjectInfo>;
  RuleProject: TCheckProject;
  Pending: string;
begin
  AContext := Default(TRuleCheckContext);
  FileName := TDocumentUris.ToPath(AUri);
  AContext.FileName := FileName;
  Projects := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := PickWorkspace(FileName);
    if Workspace = nil then
      AContext.Settings := FLooseSettings
    else
    begin
      AContext.Settings := Workspace.Configuration.Settings;
      AContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(Workspace.Root), FileName);
      AContext.Baseline := Workspace.Baseline;
      // Index, Namespaces, Unit-Suche, Packages und Namenskonvention auf demselben Weg wie MCP und Linter
      // (#1112).
      AContext.Services := Workspace.RuleServices;
      if Workspace.Project(Project) then
        Projects := Projects + [Project];
      // Weitere Projekte mit der Datei (#1112): Eine Unit im Testprogramm und im Package hat keine
      // eindeutige Anwendungsart (MergeRuleProjects).
      for Other in FWorkspaces do
        if (Other <> Workspace) and Other.ContainsFile(FileName) and Other.Project(Project) then
          Projects := Projects + [Project];
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Anwendungsart, Projektname und Formulare der .dpr (#926, #943, #956, #1055), wie bei MCP und Linter.
  if Projects <> nil then
  begin
    RuleProject := TShellWorkspace.RuleProjectOf(Projects, FileName, ReadSourceText);
    AContext.Application := RuleProject.Application;
    AContext.ProjectName := RuleProject.Name;
    AContext.AutoCreateForms := RuleProject.AutoCreateForms;
    AContext.ProjectMainSource := RuleProject.ProjectMainSource;
  end;
  // Neue Instanzen je Prüfung: Regeln dürfen so Zustand halten, ohne Threads zu teilen.
  AContext.Rules := BuiltinRules;
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
      AContext.FormFile := ChangeFileExt(FileName, '.dfm')
    else if ReadSourceText(ChangeFileExt(FileName, '.fmx'), AContext.FormText) then
      AContext.FormFile := ChangeFileExt(FileName, '.fmx')
    else
      AContext.FormText := '';
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
  if FCompileLock <> nil then
  begin
    TMonitor.Enter(FCompileLock);
    try
      FCompilerUnavailable := '';
      // Andere Installation möglich: Der Status prüft den Weg zum Compiler neu (#261).
      FHasCompilerChoice := False;
    finally
      TMonitor.Exit(FCompileLock);
    end;
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
      for Namespace in Workspace.Namespaces do
        if IndexText(Namespace, Namespaces) < 0 then
          Namespaces := Namespaces + [Namespace];
      // Units der Delphi-Installation erscheinen im Diagnoselog mit Namen (#647).
      if (Workspace.BdsRoot <> '') and (IndexText(Workspace.BdsRoot, LibraryRoots) < 0) then
        LibraryRoots := LibraryRoots + [Workspace.BdsRoot];
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
    FLogAnonymizer.SetLibraryRoots(LibraryRoots);
  FSyntaxDiagnostics.Refresh;
end;

procedure TServerComposition.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  Workspace: TShellWorkspace;
  OnSave: Boolean;
  Choice: TCompilerBackendChoice;
begin
  // Tipp-Pause (#492): ungespeicherten Stand in den Index; beim Schließen wieder den der Platte.
  if (FIndexRefresh <> nil) and StartsText('file:', ADocument.Uri) then
    case AKind of
      TDocumentEventKind.Changed:
        begin
          FIndexRefresh.Changed(TDocumentUris.ToPath(ADocument.Uri), ADocument.Text);
          // Beim Tippen macht die Projektprüfung Platz (#1247).
          if FPullDiagnostics <> nil then
            FPullDiagnostics.Typed;
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
    DeriveWorkspace(TDocumentUris.ToPath(ADocument.Uri));
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
    if (Workspace <> nil) and Workspace.Deferred then
      Workspace.Activate;
  end;
  // Nach dem Speichern einer Quelldatei kompilieren (#40), abschaltbar über compiler.onSave.
  if (AKind = TDocumentEventKind.Saved) and MatchText(ExtractFileExt(TDocumentUris.ToPath(ADocument.Uri)),
    ['.pas', '.dpr', '.dpk', '.inc']) then
  begin
    // Index nachziehen (#500): Clients ohne Dateiüberwachung (IDE-Plugin) melden nur das Speichern;
    // bei einer .inc liest der Index die einbindenden Units neu ein.
    if not SameText(ExtractFileExt(TDocumentUris.ToPath(ADocument.Uri)), '.dpk') then
      HandleWatchedFiles([TFileChange.Create(TDocumentUris.ToPath(ADocument.Uri), TFileChangeKind.Changed)]);
    TMonitor.Enter(FWorkspacesLock);
    try
      Workspace := WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
      OnSave := (Workspace <> nil) and Workspace.Configuration.Settings.Compiler.OnSave;
    finally
      TMonitor.Exit(FWorkspacesLock);
    end;
    if OnSave then
      StartCompile(TDocumentUris.ToPath(ADocument.Uri), False, Choice);
    Exit;
  end;
  if not IsConfigurationFileName(ExtractFileName(TDocumentUris.ToPath(ADocument.Uri))) then
    Exit;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Nur der Thread der Nachrichtenschleife entfernt Ordner; Workspace bleibt gültig.
  if Workspace <> nil then
    Workspace.Configuration.DocumentEvent(AKind, ADocument)
  else
    FLooseConfiguration.DocumentEvent(AKind, ADocument);
end;

procedure TServerComposition.RememberCompilerChoice(const AChoice: TCompilerBackendChoice);
begin
  TMonitor.Enter(FCompileLock);
  try
    FCompilerChoice := AChoice;
    FHasCompilerChoice := True;
  finally
    TMonitor.Exit(FCompileLock);
  end;
end;

procedure TServerComposition.CompilerUnavailable(const AChoice: TCompilerBackendChoice; AShow: Boolean);
var
  First, Show: Boolean;
  Shown: string;
  Params, Notification: TJSONObject;
begin
  TMonitor.Enter(FCompileLock);
  try
    First := FCompilerUnavailable <> AChoice.Reason;
    FCompilerUnavailable := AChoice.Reason;
    FCompilerChoice := AChoice;
    FHasCompilerChoice := True;
    Show := AShow;
    for Shown in FCompilerShown do
      if Shown = AChoice.Reason then
        Show := False;
    if Show then
      FCompilerShown := FCompilerShown + [AChoice.Reason];
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if First then
    FLogger.Warning('Kompilieren nicht möglich: ' + AChoice.Reason +
      '. Nach dem Speichern wird bis zum nächsten Laden des Projekts nicht mehr kompiliert; ' +
      'der Befehl "Projekt kompilieren" versucht es erneut.');
  // Das Log sieht im Editor kaum jemand (#261): Grund und Ausweg einmal je Grund und Sitzung als Meldung;
  // dauerhaft steht es im Status (#28).
  if not Show or (FTransport = nil) then
    Exit;
  Params := TJSONObject.Create;
  Params.AddPair('type', TJSONNumber.Create(2));
  Params.AddPair('message', AChoice.MessageText);
  Notification := TJsonRpcMessages.Notification('window/showMessage', Params);
  try
    FTransport.WriteMessage(Notification);
  finally
    Notification.Free;
  end;
end;

function TServerComposition.ChooseCompiler(const AFileName: string; out AJob: TShellCompileJob;
  out AChoice: TCompilerBackendChoice): Boolean;
var
  Workspace: TShellWorkspace;
  Error: string;
  Edition: TCompilerEdition;
begin
  AJob := Default(TShellCompileJob);
  AChoice := Default(TCompilerBackendChoice);
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    if AFileName <> '' then
      Workspace := WorkspaceOf(AFileName);
    Workspace := TShellWorkspace.Choose(Workspace, FWorkspaces);
    if Workspace = nil then
      Error := 'Kein Ordner mit Projekt geöffnet'
    else if Workspace.CompileJob(AJob, Error) then
      Error := '';
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Error <> '' then
  begin
    AChoice := TCompilerBackendChoice.Unavailable(Error, '');
    Exit(False);
  end;
  // Die Ausgabe der Installation zählt nur für auto und dcc; erkannt wird einmal je Installation (#261).
  Edition := TCompilerEdition.Unknown;
  if (AJob.Settings.Backend = TCompilerBackendSetting.Auto) or (AJob.Settings.Backend = TCompilerBackendSetting.Dcc) then
    Edition := FCompilerEditions.Resolve(AJob.BdsRoot, AJob.Version, AJob.Request.Executable);
  AChoice := TCompilerBackends.Choose(AJob.Settings.Backend, Edition, AJob.Settings.IdeCommand,
    (Trim(AJob.Settings.IdeCommand) <> '') and FileExists(AJob.Settings.IdeCommand));
  Result := True;
end;

function TServerComposition.StartCompile(const AFileName: string; AManual: Boolean;
  out AChoice: TCompilerBackendChoice): Boolean;
var
  Job: TShellCompileJob;
  Unavailable: Boolean;
begin
  AChoice := Default(TCompilerBackendChoice);
  // Workspace Trust (#186): Ein Compiler-Lauf kann Build-Events des Projekts ausführen.
  if FRestricted then
  begin
    AChoice := TCompilerBackendChoice.Unavailable('Der Arbeitsbereich ist nicht vertrauenswürdig',
      'Dem Ordner im Editor vertrauen; ein Compilerlauf kann Build-Ereignisse des Projekts ausführen.');
    if AManual then
      FLogger.Warning('Kompilieren ist in einem nicht vertrauenswürdigen Arbeitsbereich abgeschaltet');
    Exit(False);
  end;
  TMonitor.Enter(FCompileLock);
  try
    Unavailable := FCompilerUnavailable <> '';
    if Unavailable then
      AChoice := FCompilerChoice;
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if Unavailable and not AManual then
    Exit(False);
  try
    if not ChooseCompiler(AFileName, Job, AChoice) then
    begin
      // Ohne Projekt oder Installation: nur ins Log, wie bisher (#40).
      CompilerUnavailable(AChoice, False);
      Exit(False);
    end;
  except
    on ECompilerCancelled do
      Exit(False); // Beenden läuft (A-05).
  end;
  if not AChoice.Usable then
  begin
    // Bewusst abgeschaltet: nur der Status sagt es; sonst Grund und Ausweg einmal als Meldung (#261).
    if Job.Settings.Backend = TCompilerBackendSetting.Off then
      RememberCompilerChoice(AChoice)
    else
      CompilerUnavailable(AChoice, True);
    Exit(False);
  end;
  RememberCompilerChoice(AChoice);
  Result := True;
  // Die eigene IDE ist langsam: nur auf den Befehl, nie nach dem Speichern (#261).
  if not AManual and not TCompilerBackends.RunsOnSave(AChoice.Backend) then
    Exit;
  Job.Backend := AChoice.Backend;
  Job.Manual := AManual;
  TMonitor.Enter(FCompileLock);
  try
    // Beenden läuft schon (A-05): keinen neuen Thread mehr starten.
    if FCompileStopping then
      Exit;
    if FCompiling then
    begin
      // Der laufende Lauf startet danach den neuesten Stand; ein vorgemerkter Befehl bleibt ein Befehl.
      if FHasPendingCompile and FPendingCompile.Manual then
        Job.Manual := True;
      FPendingCompile := Job;
      FHasPendingCompile := True;
      Exit;
    end;
    FCompiling := True;
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if FCompileThread <> nil then
  begin
    FCompileThread.WaitFor;
    FreeAndNil(FCompileThread);
  end;
  FCompileThread := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.NameThreadForDebugging('Atlas.Compile');
      CompileLoop(Job);
    end);
  FCompileThread.FreeOnTerminate := False;
  FCompileThread.Start;
end;

procedure TServerComposition.CompileLoop(const AJob: TShellCompileJob);
var
  Job: TShellCompileJob;
  Done: Boolean;
begin
  Job := AJob;
  Done := False;
  try
    try
      repeat
        CompileOnce(Job);
        TMonitor.Enter(FCompileLock);
        try
          if FCompileStopping or not FHasPendingCompile then
          begin
            FCompiling := False;
            Done := True;
          end
          else
          begin
            Job := FPendingCompile;
            FHasPendingCompile := False;
          end;
        finally
          TMonitor.Exit(FCompileLock);
        end;
      until Done;
    except
      // Sonst läge die Ausnahme ungelesen in FatalException und FCompiling bliebe True (Code-Review S-06).
      on E: Exception do
        FLogger.Error(Format('Compilerlauf abgebrochen: %s: %s', [E.ClassName, E.Message]));
    end;
  finally
    if not Done then
    begin
      TMonitor.Enter(FCompileLock);
      try
        FCompiling := False;
        FHasPendingCompile := False;
      finally
        TMonitor.Exit(FCompileLock);
      end;
    end;
  end;
end;

procedure TServerComposition.CompileOnce(const AJob: TShellCompileJob);
begin
  try
    // Im try (S-06): Wirft schon der Start des Fortschritts, endet der Lauf geordnet.
    if AJob.Backend = TCompilerBackend.Ide then
      CompileWithIde(AJob)
    else
      CompileWithDcc(AJob);
  except
    on ECompilerCancelled do
      ; // Beenden (A-05): nichts mehr melden, der Transport ist schon zu.
    on E: Exception do
    begin
      CompilerUnavailable(TCompilerBackendChoice.Unavailable(E.Message, ''), False);
      FCompileProgress.Finish('Fehlgeschlagen');
    end;
  end;
end;

procedure TServerComposition.CompileWithDcc(const AJob: TShellCompileJob);
var
  Lines: TList<string>;
  Messages: TArray<TCompilerMessage>;
  Code, mIndex: Integer;
  Output: string;
  Choice: TCompilerBackendChoice;
  IdeJob: TShellCompileJob;
begin
  Lines := TList<string>.Create;
  try
    FCompileProgress.Start('Projekt kompilieren');
    ForceDirectories(AJob.OutputDir);
    Code := FCompilerProcess.Run(AJob.Request,
      procedure(const ALine: string)
      begin
        Lines.Add(ALine);
      end);
    Messages := TCompilerOutputParser.Parse(Lines.ToArray, AJob.Request.WorkingDir);
    if (Code <> 0) and (Length(Messages) = 0) and TCompilerEditions.HasLicenseText(Lines.ToArray) then
    begin
      // Starter bzw. Community Edition (#261): dcc ist da, darf aber nicht von der Kommandozeile bauen.
      // Merken, damit auto künftig gleich richtig wählt; bei einem Befehl gleich über die IDE bauen.
      FCompilerEditions.Remember(AJob.BdsRoot, AJob.Version, AJob.Request.Executable,
        TCompilerEdition.NoCommandLine);
      Choice := TCompilerBackends.Choose(AJob.Settings.Backend, TCompilerEdition.NoCommandLine,
        AJob.Settings.IdeCommand, (Trim(AJob.Settings.IdeCommand) <> '') and FileExists(AJob.Settings.IdeCommand));
      if not Choice.Usable then
      begin
        CompilerUnavailable(Choice, True);
        FCompileProgress.Finish('Compiler nicht nutzbar');
        Exit;
      end;
      RememberCompilerChoice(Choice);
      FCompileProgress.Finish('Kommandozeilen-Compiler nicht lizenziert');
      if AJob.Manual then
      begin
        IdeJob := AJob;
        IdeJob.Backend := Choice.Backend;
        CompileWithIde(IdeJob);
      end;
      Exit;
    end;
    if (Code <> 0) and (Length(Messages) = 0) then
    begin
      // Abbruch ohne eine einzige Meldung: Der Compiler selbst ist nicht nutzbar.
      // Bisherige Meldungen bleiben stehen.
      Output := '';
      for mIndex := 0 to Min(Lines.Count, 3) - 1 do
        if Trim(Lines[mIndex]) <> '' then
          Output := Output + ' ' + Trim(Lines[mIndex]);
      CompilerUnavailable(TCompilerBackendChoice.Unavailable(Format('%s endet mit Exit-Code %d ohne Meldungen:%s',
        [ExtractFileName(AJob.Request.Executable), Code, Output]), ''), False);
      FCompileProgress.Finish('Compiler nicht nutzbar');
      Exit;
    end;
    PublishCompile(Messages, Format('%s (Exit-Code %d)', [ExtractFileName(AJob.Request.Executable), Code]));
  finally
    Lines.Free;
  end;
end;

procedure TServerComposition.CompileWithIde(const AJob: TShellCompileJob);
var
  Messages: TArray<TCompilerMessage>;
  Succeeded: Boolean;
  Error: string;
begin
  FCompileProgress.Start('Projekt über eine eigene IDE kompilieren');
  if not FIdeCompiler.Build(AJob.Settings.IdeCommand, AJob.Project, AJob.Platform, Messages, Succeeded, Error) then
  begin
    CompilerUnavailable(TCompilerBackendChoice.Unavailable(Error,
      'cc.ps1 und die Delphi-Installation prüfen; Einzelheiten stehen im Server-Log.'), True);
    FCompileProgress.Finish('Fehlgeschlagen');
    Exit;
  end;
  if Succeeded then
    PublishCompile(Messages, 'eigene IDE (erfolgreich)')
  else
    PublishCompile(Messages, 'eigene IDE (misslungen)');
end;

procedure TServerComposition.PublishCompile(const AMessages: TArray<TCompilerMessage>; const AVia: string);
var
  Item: TCompilerMessage;
  Counts: array[TCompilerSeverity] of Integer;
  Summary: string;
begin
  TMonitor.Enter(FCompileLock);
  try
    FCompilerUnavailable := '';
  finally
    TMonitor.Exit(FCompileLock);
  end;
  FillChar(Counts, SizeOf(Counts), 0);
  for Item in AMessages do
  begin
    Inc(Counts[Item.Severity]);
    if Item.FileName = '' then
      FLogger.Warning(Format('Compiler: %s %s', [Item.Code, Item.Text]));
  end;
  FSyntaxDiagnostics.RefreshFiles(FCompilerResults.Replace(AMessages));
  Summary := Format('%d Fehler, %d Warnungen, %d Hinweise',
    [Counts[TCompilerSeverity.Error] + Counts[TCompilerSeverity.Fatal], Counts[TCompilerSeverity.Warning],
    Counts[TCompilerSeverity.Hint]]);
  FLogger.Info(Format('Kompiliert über %s: %s', [AVia, Summary]));
  FCompileProgress.Finish(Summary);
end;

procedure TServerComposition.HandleDidChangeConfiguration(const AParams: TJSONValue);
var
  Workspace: TShellWorkspace;
begin
  SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams));
  UpdateLooseSettings;
  for Workspace in FWorkspaces.ToArray do
    Workspace.Configuration.SetEditorSettings(FEditorSettings);
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
    Exit;
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
      FLogger.Warning(Format('%s(%d,%d): %s', [ExtractFileName(FGlobalSettingsFile), Issue.Range.StartPos.Line + 1,
        Issue.Range.StartPos.Character + 1, Issue.Message]));
  end;
  for Workspace in FWorkspaces.ToArray do
    Workspace.Configuration.SetGlobalSettings(FGlobalSettings);
end;

procedure TServerComposition.UpdateWatchedSettings;
var
  Files: TArray<string>;
  Workspace: TShellWorkspace;
begin
  if FFileWatcher = nil then
    Exit;
  Files := [FGlobalSettingsFile];
  TMonitor.Enter(FWorkspacesLock);
  try
    for Workspace in FWorkspaces do
      Files := Files + [Workspace.Configuration.PrimaryFileName, Workspace.Configuration.LegacyFileName];
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
      if (FGlobalSettingsFile <> '') and SameText(Change.FileName, FGlobalSettingsFile) then
        LoadGlobalSettings
      else if IsConfigurationFileName(ExtractFileName(Change.FileName)) then
      begin
        // atlas.json von außen geändert (#227, etwa im Dialog des Plugins): ohne Neustart übernehmen.
        for Workspace in FWorkspaces.ToArray do
          if Workspace.Configuration.FileChanged(Change.FileName) then
            FLogger.Info(Format('Einstellungen von %s neu gelesen', [Workspace.Root]));
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
          Reload.Add(Workspace);
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
    Exit;
  // Jeder Ordner aktualisiert die Units, die sein Aufbau kennt.
  Updated := 0;
  for Workspace in FWorkspaces.ToArray do
    Inc(Updated, Workspace.ApplyChanges(Sources));
  FLogger.Debug(Format('%d Dateiänderungen von außen, %d Units im Index aktualisiert', [Length(Sources), Updated]));
  // Gespeichert oder von außen geändert (#1247): die Datei und die Units, die sie in uses haben bzw. einbinden.
  if FPullDiagnostics <> nil then
  begin
    Names := nil;
    for Change in Sources do
      Names := Names + [Change.FileName];
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
    LoggerImpl.AddSink(DebugSink, TLogLevel.Debug);
  // stderr zeigt VS Code ebenfalls im Ausgabefenster; dort nur Fehler, um
  // Doppelungen mit window/logMessage zu vermeiden.
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Error);
  // Auszug für den Fehlerbericht (#108), unabhängig von --log.
  RecentSink := TRecentLogSink.Create;
  RecentLog := RecentSink;
  LoggerImpl.AddSink(RecentSink, TLogLevel.Info);
  TShellDiagnostics.AddLogFile(LoggerImpl, AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId),
    AOptions.LogNames, AOptions.LogLevel, Anonymizer);

  // Ab hier erreichen versehentliche Ausgaben (Writeln, Bibliotheken) nur noch stderr.
  Transport := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  if AOptions.TraceFile <> '' then
    try
      Tracing := TJsonRpcTracingTransport.Create(Transport,
        CreateTraceStream(AOptions.TraceFile, IntToStr(TParentWatcher.CurrentProcessId), TraceName), True);
      Transport := Tracing;
      if not SameText(TraceName, AOptions.TraceFile) then
        mLogger.Info(Format('Mitschnitt "%s" ist belegt, schreibe nach "%s"', [AOptions.TraceFile, TraceName]));
    except
      on E: Exception do
        mLogger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [AOptions.TraceFile, E.Message]));
    end;
  LoggerImpl.AddSink(TLspLogMessageSink.Create(Transport), AOptions.LogLevel);

  for Warning in AOptions.Warnings do
    mLogger.Warning(Warning);

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
  Result.FRestricted := AOptions.Restricted;
  Result.FClientProcessId := AOptions.ClientProcessId;
  if AOptions.Restricted then
    mLogger.Info('Eingeschränkter Modus (Arbeitsbereich nicht vertrauenswürdig): der Compiler wird nicht gestartet');
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
      ProcessId := Cardinal(TJSONNumber(Value).AsInt64);
  end;
  if (ProcessId = 0) or (FParentWatcher <> nil) then
    Exit;
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
    Result := Result + sLineBreak + Stack;
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
  Commands.Add(ProcessesCommand);
  Commands.Add(CompileCommand);
  Commands.Add(SelectBuildCommand);
  Commands.Add(SelectProjectCommand);
  Commands.Add(RebuildIndexCommand);
  Commands.Add(ClearIndexCommand);
  Commands.Add(TLspPullDiagnostics.RecheckCommand);
  Commands.Add(TBugReport.Command);
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
    FLogger.Info(Format('%d frühere Serverläufe ohne Endzeile (von der IDE beendet oder abgestürzt)',
      [Previous]));
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
