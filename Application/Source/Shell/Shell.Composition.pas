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
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Common.Lsp.FoldingRanges,
  Atlas.Common.Lsp.LinkedEditing,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Lsp.SelectionRanges,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.Hover,
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
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Todos,
  Atlas.Common.Lsp.SlashMenu,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.SemanticTokens,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Lsp.StringLiteralCommands,
  Atlas.Common.Editing.StringLiterals,
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
  Atlas.Common.Lsp.WorkDoneProgress,
  Shell.CommandLine,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Index.Scheduler,
  Atlas.Windows.Process.ParentWatcher,
  Atlas.Windows.Documents.FileWatcher,
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
    FDocumentSymbols: TLspDocumentSymbols;
    FFoldingRanges: TLspFoldingRanges;
    FLinkedEditing: TLspLinkedEditing;
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
    FParentWatcher: TParentWatcher;
    /// <summary>Anonymisiertes Diagnoselog (#647); FDiagnosticsRef hält die Instanz am Leben.</summary>
    FDiagnostics: TShellDiagnostics;
    FDiagnosticsRef: IJsonRpcRequestObserver;
    /// <summary>Grund für die Endzeile des Diagnoselogs; InputClosed, solange nichts anderes gemeldet ist.</summary>
    FEndReason: TDiagnosticEndReason;
    /// <summary>Zuletzt gesetztes Zeitlimit für Anfragen, für die Einordnung als timeout.</summary>
    FRequestTimeout: Cardinal;
    FCompletion: TLspCompletion;
    FSignatureHelp: TLspSignatureHelp;
    FHierarchies: TLspHierarchies;
    FImplementations: TLspImplementations;
    FInlayHints: TLspInlayHints;
    FCodeLens: TLspCodeLens;
    /// <summary>Code-Metriken (#66): Befehl atlas.server.metrics mit Zwischenspeicher je Datei.</summary>
    FMetrics: TLspMetrics;
    /// <summary>TODO-Übersicht (#68): Befehl atlas.server.todos.</summary>
    FTodos: TLspTodos;
    /// <summary>Baseline für Altprojekte (#97): Befehl atlas.updateBaseline.</summary>
    FBaseline: TLspBaseline;
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
    FStatistics: IJsonRpcStatistics;
    /// <summary>Letzte Logzeilen für den Fehlerbericht (#108); nil ohne CreateForStdio.</summary>
    FRecentLog: IRecentLogLines;
    FWatchedFiles: TLspWatchedFiles;
    /// <summary>Aktive Unit nach der Tipp-Pause neu in den Index (#492).</summary>
    FIndexRefresh: TLspIndexRefresh;
    /// <summary>Build-Ergebnisse und Compilermeldungen aus der IDE (#528).</summary>
    FIdeBuild: TLspIdeBuild;
    /// <summary>Projektkontext aus der IDE (#396).</summary>
    FIdeProject: TLspIdeProject;
    FWorkspaceFolders: TLspWorkspaceFolders;
    /// <summary>Für atlas.json außerhalb aller Ordner: nur Fehlermeldungen.</summary>
    FLooseConfiguration: TLspConfiguration;
    FConnection: TJsonRpcConnection;
    FIndex: ISymbolIndex;
    // Ordner des Arbeitsbereichs. Ändern nur im Thread der Nachrichtenschleife,
    // unter FWorkspacesLock, weil Anfrage-Threads lesen.
    FWorkspaces: TObjectList<TShellWorkspace>;
    FWorkspacesLock: TObject;
    /// <summary>Je Arbeitsbereich die Anfragen, die ihn außerhalb von FWorkspacesLock nutzen (EnsureUnit);
    /// ein entfernter wird erst freigegeben, wenn er hier fehlt. Nur unter FWorkspacesLock.</summary>
    FWorkspaceUsers: TDictionary<TShellWorkspace, Integer>;
    FWorkspaceCounter: Integer;
    /// <summary>Reihenfolge der Indexaufbauten aller Projekte (#648); kleiner = früher.</summary>
    FIndexScheduler: TIndexScheduler;
    FWorkspacePriority: Integer;
    FEditorSettings: string;
    // Globale Benutzerdatei (#227) als unterste Ebene; Pfad, Inhalt und der Beobachter für sie und die
    // atlas.json aller Ordner. FGlobalSettings nur im Thread der Nachrichtenschleife.
    FGlobalSettingsFile: string;
    FGlobalSettings: string;
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
    FPendingCompile: TCompilerRequest;
    /// <summary>Grund, warum der Compiler nicht nutzbar ist; '' = nutzbar. Unter FCompileLock.
    /// Dann kompiliert der Server nach dem Speichern nicht mehr, bis das Projekt neu geladen wird.</summary>
    FCompilerUnavailable: string;
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
    /// <summary>Innerster Ordner zur Datei oder nil. Aufrufer hält FWorkspacesLock.</summary>
    function WorkspaceOf(const AFileName: string): TShellWorkspace;
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Fortschritt des Indexaufbaus in Prozent über alle Projekte; -1, wenn keiner läuft.</summary>
    function IndexLoading: Integer;
    /// <summary>Ein Indexaufbau ist fertig: Befunde mit dem vollständigen Index neu prüfen (#647).
    /// Index-Thread.</summary>
    procedure IndexFinished;
    /// <summary>True, solange ein Projekt seine Projektstufe noch nicht indiziert hat.</summary>
    function ProjectIndexPending: Boolean;
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
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
    /// <summary>Inhalt des Status-Befehls (#28).</summary>
    function CollectBookmarks: TArray<TBookmarkHit>;
    function CollectStatus: TServerStatus;
    /// <summary>Fehlerbericht (#108); AArguments optional [{"anonymize", "client", "target"}].</summary>
    function BugReport(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Wirksame Konfiguration je Arbeitsbereich als formatiertes JSON.</summary>
    function ConfigurationReport: string;
    function DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
    function DelphiVersionFor(const AUri: string): string;
    /// <summary>Schnellbefehle (#293): False = aus; ADisabled samt "uses" bei usesCommand = false.</summary>
    function SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
    function InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
    /// <summary>Einstellungen, Wurzel und Dateien für die Code-Metriken (#66): Datei, Projekt (.dproj/.dpr/.dpk),
    /// Ordner oder '' (einziger Arbeitsbereich).</summary>
    function MetricsSourceFor(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean;
    function HintSettingsFor(const AUri: string): THintSettings;
    function RefactoringSettingsFor(const AUri: string): TRefactoringSettings;
    function CompletionSettingsFor(const AUri: string): TCompletionSettings;
    /// <summary>"stringLiteral" für AUri; AMultiline nach Stil und Delphi-Version (#312).</summary>
    function StringLiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
    function FormatStyleFor(const AUri: string): TFormatStyle;
    function RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    /// <summary>Namespaces aller Projekte an die Features weitergeben, Diagnosen neu prüfen.</summary>
    procedure ProjectLoaded;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    /// <summary>Kompiliert das Projekt zu AFileName ('' = einziger Ordner) im Hintergrund.
    /// AManual: über den Befehl, auch wenn der Compiler zuletzt nicht nutzbar war.</summary>
    procedure StartCompile(const AFileName: string; AManual: Boolean);
    /// <summary>Merkt sich, dass der Compiler nicht nutzbar ist, und meldet das einmal.</summary>
    procedure CompilerUnavailable(const AReason: string);
    /// <summary>Hintergrund-Thread: führt ARequest und vorgemerkte Läufe aus.</summary>
    procedure CompileLoop(const ARequest: TCompilerRequest);
    /// <summary>Ein Compilerlauf mit Fortschritt und Meldungen; Fehler landen im Fortschritt und im Log.</summary>
    procedure CompileOnce(const ARequest: TCompilerRequest);
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
    property Logger: ILogger read FLogger;
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read FDocuments;
    property Index: ISymbolIndex read FIndex;
  end;

implementation

// Winapi.Windows zuerst, damit die System-Units bei gleichen Namen Vorrang haben.
uses
  Winapi.Windows,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Diagnostics,
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
  Shell.SlashHost,
  Shell.VcsChanges,
  Shell.Bootstrap,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Dfm.BinaryForm,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Compiler.OutputParser,
  Atlas.Windows.Compiler.Adapters.ProcessRunner,
  Atlas.Windows.Console.StdStreams,
  Atlas.Windows.Documents.PathCanonicalizer,
  Atlas.Windows.Diagnostics.Adapters.DebugOutputSink,
  Atlas.Windows.Diagnostics.StackTrace,
  Atlas.Common.Logging.RotatingFileStream,
  Atlas.Windows.Editing.SystemColors,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.GroupReader,
  Atlas.Common.JsonRpc.Messages;

function StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
    Result.Add(Value);
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
var
  SlashHost: TShellSlashHost;
begin
  inherited Create;
  FTransport := ATransport;
  FLogger := ALogger;
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
        [AMethod, AError.ClassName, AError.Message, sLineBreak, Params, sLineBreak, AError.StackTrace]));
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
  FDocuments := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TWindowsPathCanonicalizer.Canonicalize(APath);
    end);
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FDispatcher);
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport);
  FSyntaxDiagnostics.OnError :=
    procedure(AError: Exception)
    begin
      FLogger.Error(Format('Fehler beim Prüfen der Syntax: %s: %s', [AError.ClassName, AError.Message]));
    end;
  FCompilerResults := TCompilerResults.Create;
  FCompilerProcess := TProcessRunner.Create;
  FCompileProgress := TLspWorkDoneProgress.Create(FTransport, 'atlas-compile');
  FCompileLock := TObject.Create;
  FSyntaxDiagnostics.CompilerMessagesProvider :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompilerResults.MessagesFor(AFileName);
    end;
  FSyntaxDiagnostics.Attach;
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
  // Long-Polling endet vor dem Zeitlimit des Watchdogs (Code-Review P-14).
  FPullDiagnostics.RequestTimeout :=
    function: Cardinal
    begin
      Result := FRequestTimeout;
    end;
  FPullDiagnostics.Attach(FDispatcher);
  FSyntaxDiagnostics.OnPullChanged := FPullDiagnostics.Changed;
  FDocumentSymbols := TLspDocumentSymbols.Create(FDocuments);
  FDocumentSymbols.Attach(FDispatcher);
  FFoldingRanges := TLspFoldingRanges.Create(FDocuments);
  FFoldingRanges.Attach(FDispatcher);
  FLinkedEditing := TLspLinkedEditing.Create(FDocuments);
  FLinkedEditing.Attach(FDispatcher);
  FFormatting := TLspFormatting.Create(FDocuments, FormatStyleFor,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileExists(AFileName);
      if Result then
        AText := TFile.ReadAllText(AFileName);
    end);
  FFormatting.SlashCommandsFor := SlashCommandsFor;
  FFormatting.DelphiVersionFor := DelphiVersionFor;
  SlashHost := TShellSlashHost.Create(
    function(const AUri: string): TShellWorkspace
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Result := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Result = nil) and (FWorkspaces.Count = 1) then
          Result := FWorkspaces[0];
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AUri: string): string
    var
      Workspace: TShellWorkspace;
      Settings: TServerSettings;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
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
  FFormatting.SlashHost := SlashHost;
  FFormatting.Attach(FDispatcher);
  // Erzeugen-Menü (#719): dieselben Schalter, Versionen und derselbe Host wie die Schnellbefehle nach Enter.
  FSlashMenu := TLspSlashMenu.Create(FDocuments);
  FSlashMenu.SlashCommandsFor := SlashCommandsFor;
  FSlashMenu.DelphiVersionFor := DelphiVersionFor;
  FSlashMenu.SlashHost := SlashHost;
  FSelectionRanges := TLspSelectionRanges.Create(FDocuments);
  FSelectionRanges.Attach(FDispatcher);
  FWorkspaces := TObjectList<TShellWorkspace>.Create(True);
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
  FSyntaxDiagnostics.DefinesProvider := DefinesFor;
  // Zielplattform und Konfiguration für den Hinweis inaktiver Zweige (#615).
  FSyntaxDiagnostics.BuildTargetProvider :=
    function(const AUri: string; out APlatform, AConfig: string): Boolean
    var
      Workspace: TShellWorkspace;
      Project: TProjectInfo;
    begin
      APlatform := '';
      AConfig := '';
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
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
  FSyntaxDiagnostics.IncludePathsProvider :=
    function(const AUri: string): TArray<string>
    var
      Workspace: TShellWorkspace;
    begin
      Result := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if Workspace <> nil then
          Result := Workspace.IncludePaths;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FSyntaxDiagnostics.VersionProvider := DelphiVersionFor;
  FSyntaxDiagnostics.RuleProvider := RuleContextFor;
  FIndex := TSymbolIndex.Create;
  FFormatting.Index := FIndex;
  FSlashMenu.Index := FIndex;
  FEndReason := TDiagnosticEndReason.InputClosed;
  FRequestTimeout := RequestTimeoutMs;
  FDiagnostics := TShellDiagnostics.Create(TShellDiagnostics.DefaultFolder, IntToStr(GetCurrentProcessId),
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
  FDefinition := TLspDefinition.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FDefinition.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end;
  FDefinition.Attach(FDispatcher);
  FHover := TLspHover.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FHover.VersionProvider := DelphiVersionFor;
  FHover.HintsFor := HintSettingsFor;
  FHover.Attach(FDispatcher);
  FWorkspaceSymbols := TLspWorkspaceSymbols.Create(FIndex);
  FBookmarks := TBookmarkStore.Create;
  FWorkspaceSymbols.BookmarksFor := CollectBookmarks;
  FWorkspaceSymbols.Attach(FDispatcher);
  FDocumentHighlights := TLspDocumentHighlights.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FDocumentHighlights.SettingsFor :=
    function(const AUri: string): THighlightSettings
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
        if Workspace <> nil then
          Result := Workspace.Configuration.Settings.Highlight
        else
          Result := THighlightSettings.Default;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end;
  FDocumentHighlights.Attach(FDispatcher);
  FReferences := TLspReferences.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FReferences.Attach(FDispatcher);
  FRename := TLspRename.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FRename.Attach(FDispatcher);
  FCompletion := TLspCompletion.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
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
  // Postfix-Vorlagen (#188): abschaltbar mit completion.postfixTemplates; for var und var Name := nur, wenn die
  // Sprachversion Inline-Variablen kennt und refactoring.inlineVar sie nicht abschaltet.
  FCompletion.PostfixFor :=
    function(const AUri: string): TPostfixOptions
    begin
      Result := TPostfixOptions.Default;
      Result.Enabled := CompletionSettingsFor(AUri).PostfixTemplates;
      Result.InlineVar := RefactoringSettingsFor(AUri).InlineVar and
        TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, DelphiVersionFor(AUri));
    end;
  // Für completionItem/resolve (Detailpanel von Atlas, #405); Anzeige von XMLDoc (#654).
  FCompletion.HintsFor := HintSettingsFor;
  FCompletion.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end;
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
  // „Interface implementieren“ im Erzeugen-Menü (#719, #466) wie in der Vervollständigung.
  FSlashMenu.Completion := FCompletion;
  FSignatureHelp := TLspSignatureHelp.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FSignatureHelp.Attach(FDispatcher);
  FHierarchies := TLspHierarchies.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FHierarchies.Attach(FDispatcher);
  FImplementations := TLspImplementations.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FImplementations.Attach(FDispatcher);
  FInlayHints := TLspInlayHints.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    InlayHintSettingsFor,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FInlayHints.Attach(FDispatcher);
  FCodeLens := TLspCodeLens.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    ProjectSourceFiles,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FCodeLens.MetricsFor :=
    function(const AUri: string; out ALimits: TMetricLimits): Boolean
    var
      Source: TLspMetricsSource;
    begin
      if not MetricsSourceFor(TDocumentUris.ToPath(AUri), False, Source) then
        Source.Settings := TServerSettings.Default;
      ALimits := TMetricRules.Limits(Source.Settings);
      Result := Source.Settings.CodeLens.Metrics;
    end;
  FCodeLens.Attach(FDispatcher);
  FMetrics := TLspMetrics.Create(MetricsSourceFor,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end);
  // Gleiche Quelle wie die Metriken: Einstellungen, Wurzel und Dateien des Projektmodells (#14).
  FTodos := TLspTodos.Create(MetricsSourceFor,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end);
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
  FSemanticTokens := TLspSemanticTokens.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
  FSemanticTokens.Attach(FDispatcher);
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
  FCodeActions.MemberOrderFor :=
    function(const AUri: string): TMemberOrderSettings
    var
      Workspace: TShellWorkspace;
    begin
      TMonitor.Enter(FWorkspacesLock);
      try
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
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
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
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
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
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
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
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
  FCodeActions.ExtraActions :=
    function(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>
    begin
      Result := FTestUnits.Actions(AUri, ARange.StartPos.Line);
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
        Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
        if Workspace <> nil then
          Result := Workspace.IncludePaths;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
    end);
  FDocumentLinks.Attach(FDispatcher);
  FColors := TLspColors.Create(FDocuments, WindowsSystemColor);
  FColors.Attach(FDispatcher);
  FCommands := TLspCommands.Create;
  FCommands.Register(TLspFormFiles.ConvertCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Files: TArray<string>;
      FileName, Form, Backup, Extension: string;
      Converted, Backups: Integer;
    begin
      // Mit URI eine Datei, sonst alle Formulare neben den Projekt-Units.
      Files := nil;
      if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
        Files := [TDocumentUris.ToPath(AArguments.Items[0].Value)]
      else
        for FileName in ProjectSourceFiles do
          for Extension in TArray<string>.Create('.dfm', '.fmx') do
            if FileExists(ChangeFileExt(FileName, Extension)) then
              Files := Files + [ChangeFileExt(FileName, Extension)];
      Converted := 0;
      Backups := 0;
      for Form in Files do
        try
          if TDfmBinary.ConvertFile(Form, Backup) then
          begin
            Inc(Converted);
            if Backup <> '' then
              Inc(Backups);
          end;
        except
          on E: Exception do
            FLogger.Warning(Format('%s nicht umgewandelt: %s', [Form, E.Message]));
        end;
      FLogger.Info(Format('%d binäre Formulare in Text umgewandelt, %d Sicherungskopien (.bak)',
        [Converted, Backups]));
      Result := TJSONString.Create(Format('%d Formulare umgewandelt', [Converted]));
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
  FCommands.Register(TLspBaseline.Command,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Watch: TStopwatch;
    begin
      // Prüft das ganze Projekt: in großen Altprojekten dauert das; nur Zahlen ins Log, keine Pfade.
      Watch := TStopwatch.StartNew;
      Result := FBaseline.Execute(AArguments);
      if Result is TJSONObject then
        FLogger.Info(Format('Baseline aktualisiert: %d Treffer in %d Dateien (%d neu, %d entfernt, %d ohne Datei), ' +
          '%d ms', [TJSONObject(Result).GetValue<Integer>('total', -1), TJSONObject(Result).GetValue<Integer>('files',
          -1), TJSONObject(Result).GetValue<Integer>('added', -1), TJSONObject(Result).GetValue<Integer>('removed',
          -1), TJSONObject(Result).GetValue<Integer>('orphaned.count', -1), Watch.ElapsedMilliseconds]));
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
        function(const AUnitName: string): Boolean
        begin
          Result := EnsureUnit(AUnitName);
        end, FDefinition.Namespaces, AArguments);
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
  FCommands.Register(StatusCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Status: TServerStatus;
    begin
      Status := CollectStatus;
      FLogger.Info('Status:' + sLineBreak + Status.ToMarkdown);
      Result := Status.ToJson;
    end);
  // Einstellungsdialog des Plugins (#227): Prüfung mit dem Parser des Servers und Regelkatalog.
  FCommands.Register(TLspSettingsCommands.CheckCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspSettingsCommands.Check(AArguments);
    end);
  FCommands.Register(TLspSettingsCommands.CatalogCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := TLspSettingsCommands.Catalog(TLspSettingsCommands.CatalogEntries(AArguments), FGlobalSettingsFile);
    end);
  FCommands.Register(TBugReport.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := BugReport(AArguments);
    end);
  FCommands.Register(CompileCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Uri: string;
    begin
      // Optional die URI einer Datei, deren Projekt kompiliert wird.
      Uri := '';
      if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
        Uri := AArguments.Items[0].Value;
      if Uri <> '' then
        StartCompile(TDocumentUris.ToPath(Uri), True)
      else
        StartCompile('', True);
      Result := TJSONNull.Create;
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
      Before, Freed: Int64;
      Removed: Integer;
      Answer: TJSONObject;
    begin
      // „Index löschen“ (#492): alle Caches auf der Platte, auch anderer Projekte und IDE-Versionen;
      // gesperrte Caches anderer Serverinstanzen bleiben. Danach die eigenen Ordner neu indizieren.
      TMonitor.Enter(FWorkspacesLock);
      try
        Targets := FWorkspaces.ToArray;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      for Workspace in Targets do
        Workspace.ReleaseCache;
      Before := TIndexCacheDirectory.TotalSize(TIndexCacheDirectory.DefaultRoot);
      Removed := TIndexCacheDirectory.Clear(TIndexCacheDirectory.DefaultRoot);
      Freed := Before - TIndexCacheDirectory.TotalSize(TIndexCacheDirectory.DefaultRoot);
      FLogger.Info(Format('Index gelöscht: %d Caches, %d KB; %d Ordner werden neu indiziert',
        [Removed, Freed div 1024, Length(Targets)]));
      for Workspace in Targets do
        Workspace.Rebuild;
      Answer := TJSONObject.Create;
      Answer.AddPair('removed', TJSONNumber.Create(Removed));
      Answer.AddPair('freedBytes', TJSONNumber.Create(Freed));
      Result := Answer;
    end);
  FCommands.Register(SelectBuildCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      Options: TJSONObject;
      Config, Platform, Uri, Error: string;
      Workspace: TShellWorkspace;
      Targets: TArray<TShellWorkspace>;
      Project: TProjectInfo;
      Items: TJSONArray;
      Item: TJSONObject;
      DefinesValue, Define: TJSONValue;
      Defines: TArray<string>;
      HasDefines: Boolean;
    begin
      // Argument: {"config": "Release", "platform": "Win64", "uri": "…", "defines": ["DEBUG"]};
      // alle Felder optional. Ohne Konfiguration, Plattform und Symbole nur die aktuelle Auswahl
      // je Projekt (#46). "defines" ersetzt die Symbole der .dproj (Projektoptionen der IDE, #615).
      Config := '';
      Platform := '';
      Uri := '';
      Defines := nil;
      HasDefines := False;
      if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
      begin
        Options := TJSONObject(AArguments.Items[0]);
        Options.TryGetValue<string>('config', Config);
        Options.TryGetValue<string>('platform', Platform);
        Options.TryGetValue<string>('uri', Uri);
        DefinesValue := Options.GetValue('defines');
        if DefinesValue is TJSONArray then
        begin
          HasDefines := True;
          for Define in TJSONArray(DefinesValue) do
            if Define is TJSONString then
              Defines := Defines + [TJSONString(Define).Value];
        end;
      end;
      Targets := nil;
      TMonitor.Enter(FWorkspacesLock);
      try
        if Uri <> '' then
        begin
          Workspace := WorkspaceOf(TDocumentUris.ToPath(Uri));
          if Workspace <> nil then
            Targets := [Workspace];
        end
        else
          Targets := FWorkspaces.ToArray;
      finally
        TMonitor.Exit(FWorkspacesLock);
      end;
      if (Config <> '') or (Platform <> '') or HasDefines then
        for Workspace in Targets do
          if Workspace.Project(Project) and not Workspace.SelectBuild(Config, Platform, Defines, HasDefines, Error) then
            raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Error);
      Items := TJSONArray.Create;
      for Workspace in Targets do
        if Workspace.Project(Project) then
        begin
          Item := TJSONObject.Create;
          Item.AddPair('folder', Workspace.Name);
          Item.AddPair('project', Project.FileName);
          Item.AddPair('config', IfThen(Config <> '', Config, Project.Config));
          Item.AddPair('platform', IfThen(Platform <> '', Platform, Project.Platform));
          Item.AddPair('configs', StringsToJson(Project.Configs));
          Item.AddPair('platforms', StringsToJson(Project.Platforms));
          Items.AddElement(Item);
        end;
      Result := TJSONObject.Create(TJSONPair.Create('projects', Items));
    end);
  FCommands.Attach(FDispatcher);
  FWatchedFiles := TLspWatchedFiles.Create(FTransport);
  FWatchedFiles.OnChanged := HandleWatchedFiles;
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
    end);
  FIndexRefresh.OnError :=
    procedure(E: Exception)
    begin
      FLogger.Warning('Index nach Tipp-Pause: ' + E.Message);
    end;
  FWatchedFiles.Attach(FDispatcher);
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
        Workspace := WorkspaceOf(ABuild.Project);
        if (Workspace = nil) and (FWorkspaces.Count = 1) then
          Workspace := FWorkspaces[0];
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
  FIdeBuild.Attach(FDispatcher);
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
  FIdeProject.Attach(FDispatcher);
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
      // Editor-Ebene: initializationOptions.settings.atlas wie bei didChangeConfiguration, schon vor dem
      // ersten Indexaufbau; sie zählt wie global (TConfigurationScopes). Das IDE-Plugin schickt keine
      // Einstellungen mehr: Es schreibt settings.json, die der Server selbst liest und beobachtet.
      if FLifecycle.InitializeParams <> nil then
        FEditorSettings := TLspConfiguration.EditorSettingsFromParams(
          FLifecycle.InitializeParams.GetValue('initializationOptions'));
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

destructor TServerComposition.Destroy;
var
  Unfinished: Boolean;
begin
  // Zuerst: Eine laufende Übernahme greift auf die Ordner zu.
  FreeAndNil(FIndexRefresh);
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
  FWorkspaceUsers.Free;
  FWorkspacesLock.Free;
  // Nach den Ordnern: Ihre Index-Threads sind beendet und abgemeldet.
  FIndexScheduler.Free;
  FLooseConfiguration.Free;
  FWorkspaceFolders.Free;
  FIndex := nil;
  FDocumentSymbols.Free;
  FFoldingRanges.Free;
  FLinkedEditing.Free;
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
  FBaseline.Free;
  FInlayHints.Free;
  FImplementations.Free;
  FHierarchies.Free;
  FSignatureHelp.Free;
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
  FCompileLock.Free;
  FCompilerResults.Free;
  FCompilerProcess := nil;
  FWatchedFiles.Free;
  FIdeBuild.Free;
  FIdeProject.Free;
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
  Index: Integer;
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
  for Index := 0 to High(Projects) do
    AddProjectWorkspace(ExtractFileDir(Projects[Index]), ChangeFileExt(ExtractFileName(Projects[Index]), ''),
      Projects[Index], AFolder.Key, HasOthers or (Index > 0));
end;

procedure TServerComposition.AddProjectWorkspace(const ARoot, AName, AProjectFile, AOrigin: string;
  ADeferred: Boolean);
var
  Workspace: TShellWorkspace;
  Existing: TShellWorkspace;
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
  // Ordner entstehen in der Nachrichtenschleife (initialized, didChangeWorkspaceFolders, didOpen):
  // Reload ist nur dort erlaubt (Code-Review A-03).
  Workspace.LoopThreadId := TThread.Current.ThreadID;
  Workspace.OnProjectLoaded := ProjectLoaded;
  Workspace.OnIndexFinished := IndexFinished;
  Workspace.OnProjectReady := IndexFinished;
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
  Workspace.Configuration.SetGlobalSettings(FGlobalSettings);
  Workspace.Configuration.SetEditorSettings(FEditorSettings);
  TMonitor.Enter(FWorkspacesLock);
  try
    FWorkspaces.Add(Workspace);
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
  Index: Integer;
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
    for Index := FWorkspaces.Count - 1 downto 0 do
      if SameText(FWorkspaces[Index].Origin, AFolder.Key) then
        Removed := Removed + [FWorkspaces.Extract(FWorkspaces[Index])];
    Remaining := FWorkspaces.ToArray;
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
        TMonitor.Wait(FWorkspacesLock, INFINITE);
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
  Index: Integer;
begin
  // Zuerst das Projekt, das die Datei enthält (#648); mehrere Projekte können im selben Ordner liegen.
  for Workspace in FWorkspaces do
    if Workspace.ContainsFile(AFileName) then
      Exit(Workspace);
  Folders := nil;
  for Workspace in FWorkspaces do
    Folders := Folders + [TWorkspaceFolder.Create(Workspace.Root, Workspace.Name)];
  Index := TLspWorkspaceFolders.FolderOf(Folders, AFileName);
  if Index < 0 then
    Result := nil
  else
    Result := FWorkspaces[Index];
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
    FSyntaxDiagnostics.RefreshLater;
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
      Encoding: TEncoding;
    begin
      Encoding := TUTF8Encoding.Create(False);
      try
        TFile.WriteAllText(AFileName, AText, Encoding);
      finally
        Encoding.Free;
      end;
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
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
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
  Root, Item, Effective: TJSONObject;
  Items: TJSONArray;
  Workspace: TShellWorkspace;
  Targets: TArray<TShellWorkspace>;
  Settings: TServerSettings;

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
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Root := TJSONObject.Create;
  try
    // Eingaben der Schichtung (Editor, dann atlas.json mit Vorrang) und die wichtigsten Ergebnisse.
    Root.AddPair('editor', JsonOrText(FEditorSettings));
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
  Input.Identity := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
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
      Result.Workspaces := Result.Workspaces + [Workspace.IndexStatus];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  Result.Requests := FStatistics.Snapshot;
end;

function TServerComposition.SlashCommandsFor(const AUri: string; out ADisabled: TArray<string>): Boolean;
var
  Workspace: TShellWorkspace;
begin
  ADisabled := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Exit(True);
    Result := Workspace.Configuration.Settings.SlashCommands;
    ADisabled := Workspace.Configuration.Settings.SlashCommandsDisabled;
    // usesCommand bleibt als Alias erhalten (#254).
    if not Workspace.Configuration.Settings.UsesCommand then
      ADisabled := ADisabled + ['uses'];
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.DelphiVersionFor(const AUri: string): string;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
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

function TServerComposition.CompletionSettingsFor(const AUri: string): TCompletionSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TCompletionSettings.Default
    else
      Result := Workspace.Configuration.Settings.Completion;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.RefactoringSettingsFor(const AUri: string): TRefactoringSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TRefactoringSettings.Default
    else
      Result := Workspace.Configuration.Settings.Refactoring;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.StringLiteralFor(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TStringLiteralSettings.Default
    else
      Result := Workspace.Configuration.Settings.StringLiteral;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  AMultiline := TStringLiterals.UseMultiline(Result.Style, DelphiVersionFor(AUri));
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
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
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

function TServerComposition.InlayHintSettingsFor(const AUri: string): TInlayHintSettings;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TInlayHintSettings.Default
    else
      Result := Workspace.Configuration.Settings.InlayHints;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.HintSettingsFor(const AUri: string): THintSettings;
var
  Workspace: TShellWorkspace;
  Issues: TArray<TConfigurationIssue>;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace <> nil then
      Exit(Workspace.Configuration.Settings.Hints);
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Ohne Arbeitsbereich (z. B. RTL-Unit) gelten die globalen Einstellungen.
  Result := TConfigurationParser.Parse(TConfigurationScopes.Effective(FGlobalSettings, FEditorSettings, ''),
    Issues).Hints;
end;

function TServerComposition.FormatStyleFor(const AUri: string): TFormatStyle;
var
  Workspace: TShellWorkspace;
begin
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(TDocumentUris.ToPath(AUri));
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Result := TFormatStyle.Default
    else
      Result := Workspace.Configuration.Settings.Formatting;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
end;

function TServerComposition.RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  Workspace: TShellWorkspace;
  FileName, Folder: string;
begin
  AContext := Default(TRuleCheckContext);
  FileName := TDocumentUris.ToPath(AUri);
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := WorkspaceOf(FileName);
    if Workspace = nil then
      AContext.Settings := TServerSettings.Default
    else
    begin
      AContext.Settings := Workspace.Configuration.Settings;
      AContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(Workspace.Root), FileName);
      AContext.Baseline := Workspace.Baseline;
      AContext.Namespaces := Workspace.Namespaces;
    end;
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  // Neue Instanzen je Prüfung: Regeln dürfen so Zustand halten, ohne Threads zu teilen.
  AContext.Rules := BuiltinRules;
  AContext.Index := FIndex;
  AContext.EnsureUnit := EnsureUnit;
  // Formulardatei neben der Unit für den Abgleich von Feldern und Objekten (#123).
  if SameText(ExtractFileExt(FileName), '.pas') and
    not ReadSourceText(ChangeFileExt(FileName, '.dfm'), AContext.FormText) and
    not ReadSourceText(ChangeFileExt(FileName, '.fmx'), AContext.FormText) then
    AContext.FormText := '';
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
  Result := True;
end;

procedure TServerComposition.ProjectLoaded;
var
  Workspace: TShellWorkspace;
  Namespaces: TArray<string>;
  Namespace: string;
  LibraryRoots: TArray<string>;
begin
  // Neues Projekt oder neue Installation: Der Compiler bekommt eine neue Chance (#40).
  if FCompileLock <> nil then
  begin
    TMonitor.Enter(FCompileLock);
    try
      FCompilerUnavailable := '';
    finally
      TMonitor.Exit(FCompileLock);
    end;
  end;
  // Die Features kennen eine Liste: die Namespaces aller Projekte ohne Doppelte.
  Namespaces := nil;
  LibraryRoots := nil;
  TMonitor.Enter(FWorkspacesLock);
  try
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
  FDocumentHighlights.Namespaces := Namespaces;
  FReferences.Namespaces := Namespaces;
  FRename.Namespaces := Namespaces;
  FCompletion.Namespaces := Namespaces;
  FSignatureHelp.Namespaces := Namespaces;
  FHierarchies.Namespaces := Namespaces;
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
begin
  // Tipp-Pause (#492): ungespeicherten Stand in den Index; beim Schließen wieder den der Platte.
  if (FIndexRefresh <> nil) and StartsText('file:', ADocument.Uri) then
    case AKind of
      TDocumentEventKind.Changed:
        FIndexRefresh.Changed(TDocumentUris.ToPath(ADocument.Uri), ADocument.Text);
      TDocumentEventKind.Closed:
        if TLspIndexRefresh.Applies(TDocumentUris.ToPath(ADocument.Uri)) then
        begin
          FIndexRefresh.Closed(TDocumentUris.ToPath(ADocument.Uri));
          HandleWatchedFiles([TFileChange.Create(TDocumentUris.ToPath(ADocument.Uri), TFileChangeKind.Changed)]);
        end;
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
      StartCompile(TDocumentUris.ToPath(ADocument.Uri), False);
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

procedure TServerComposition.CompilerUnavailable(const AReason: string);
var
  First: Boolean;
begin
  TMonitor.Enter(FCompileLock);
  try
    First := FCompilerUnavailable <> AReason;
    FCompilerUnavailable := AReason;
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if First then
    FLogger.Warning('Kompilieren nicht möglich: ' + AReason +
      '. Nach dem Speichern wird bis zum nächsten Laden des Projekts nicht mehr kompiliert; ' +
      'der Befehl "Projekt kompilieren" versucht es erneut.');
end;

procedure TServerComposition.StartCompile(const AFileName: string; AManual: Boolean);
var
  Workspace: TShellWorkspace;
  Request: TCompilerRequest;
  Error: string;
  Unavailable: Boolean;
begin
  // Workspace Trust (#186): Ein Compiler-Lauf kann Build-Events des Projekts ausführen.
  if FRestricted then
  begin
    if AManual then
      FLogger.Warning('Kompilieren ist in einem nicht vertrauenswürdigen Arbeitsbereich abgeschaltet');
    Exit;
  end;
  TMonitor.Enter(FCompileLock);
  try
    Unavailable := FCompilerUnavailable <> '';
  finally
    TMonitor.Exit(FCompileLock);
  end;
  if Unavailable and not AManual then
    Exit;
  TMonitor.Enter(FWorkspacesLock);
  try
    Workspace := nil;
    if AFileName <> '' then
      Workspace := WorkspaceOf(AFileName);
    if (Workspace = nil) and (FWorkspaces.Count = 1) then
      Workspace := FWorkspaces[0];
    if Workspace = nil then
      Error := 'Kein Ordner mit Projekt geöffnet'
    else if Workspace.CompilerRequest(Request, Error) then
      Error := '';
  finally
    TMonitor.Exit(FWorkspacesLock);
  end;
  if Error <> '' then
  begin
    CompilerUnavailable(Error);
    Exit;
  end;
  TMonitor.Enter(FCompileLock);
  try
    // Beenden läuft schon (A-05): keinen neuen Thread mehr starten.
    if FCompileStopping then
      Exit;
    if FCompiling then
    begin
      // Der laufende Lauf startet danach den neuesten Stand.
      FPendingCompile := Request;
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
      CompileLoop(Request);
    end);
  FCompileThread.FreeOnTerminate := False;
  FCompileThread.Start;
end;

procedure TServerComposition.CompileLoop(const ARequest: TCompilerRequest);
var
  Request: TCompilerRequest;
  Done: Boolean;
begin
  Request := ARequest;
  Done := False;
  try
    try
      repeat
        CompileOnce(Request);
        TMonitor.Enter(FCompileLock);
        try
          if FCompileStopping or not FHasPendingCompile then
          begin
            FCompiling := False;
            Done := True;
          end
          else
          begin
            Request := FPendingCompile;
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

procedure TServerComposition.CompileOnce(const ARequest: TCompilerRequest);
var
  Lines: TList<string>;
  Messages: TArray<TCompilerMessage>;
  Item: TCompilerMessage;
  Counts: array[TCompilerSeverity] of Integer;
  Code, Index: Integer;
  Summary, Output: string;
begin
  Lines := TList<string>.Create;
  try
    try
      // Im try (S-06): Wirft schon der Start des Fortschritts, endet der Lauf geordnet.
      FCompileProgress.Start('Projekt kompilieren');
      Code := FCompilerProcess.Run(ARequest,
        procedure(const ALine: string)
        begin
          Lines.Add(ALine);
        end);
      Messages := TCompilerOutputParser.Parse(Lines.ToArray, ARequest.WorkingDir);
      if (Code <> 0) and (Length(Messages) = 0) then
      begin
        // Abbruch ohne eine einzige Meldung: Der Compiler selbst ist nicht nutzbar,
        // z. B. ohne Lizenz für die Kommandozeile. Bisherige Meldungen bleiben stehen.
        Output := '';
        for Index := 0 to Min(Lines.Count, 3) - 1 do
          if Trim(Lines[Index]) <> '' then
            Output := Output + ' ' + Trim(Lines[Index]);
        CompilerUnavailable(Format('%s endet mit Exit-Code %d ohne Meldungen:%s',
          [ARequest.Executable, Code, Output]));
        FCompileProgress.Finish('Compiler nicht nutzbar');
      end
      else
      begin
        TMonitor.Enter(FCompileLock);
        try
          FCompilerUnavailable := '';
        finally
          TMonitor.Exit(FCompileLock);
        end;
        FillChar(Counts, SizeOf(Counts), 0);
        for Item in Messages do
        begin
          Inc(Counts[Item.Severity]);
          if Item.FileName = '' then
            FLogger.Warning(Format('Compiler: %s %s', [Item.Code, Item.Text]));
        end;
        FSyntaxDiagnostics.RefreshFiles(FCompilerResults.Replace(Messages));
        Summary := Format('%d Fehler, %d Warnungen, %d Hinweise',
          [Counts[TCompilerSeverity.Error] + Counts[TCompilerSeverity.Fatal], Counts[TCompilerSeverity.Warning],
          Counts[TCompilerSeverity.Hint]]);
        FLogger.Info(Format('Kompiliert mit %s (Exit-Code %d): %s', [ARequest.Executable, Code, Summary]));
        FCompileProgress.Finish(Summary);
      end;
    except
      on ECompilerCancelled do
        ; // Beenden (A-05): nichts mehr melden, der Transport ist schon zu.
      on E: Exception do
      begin
        CompilerUnavailable(E.Message);
        FCompileProgress.Finish('Fehlgeschlagen');
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TServerComposition.HandleDidChangeConfiguration(const AParams: TJSONValue);
var
  Workspace: TShellWorkspace;
begin
  FEditorSettings := TLspConfiguration.EditorSettingsFromParams(AParams);
  for Workspace in FWorkspaces.ToArray do
    Workspace.Configuration.SetEditorSettings(FEditorSettings);
end;

class function TServerComposition.GlobalSettingsPath: string;
begin
  Result := TShellBootstrap.GlobalSettingsFile;
end;

procedure TServerComposition.LoadGlobalSettings;
var
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
  if Text <> '' then
  begin
    TConfigurationParser.Parse(Text, Issues);
    // Projekt-Schlüssel in der globalen Datei wirken nicht; das Log nennt sie.
    TConfigurationScopes.Filter(Text, TConfigurationScope.Global, Misplaced);
    FLogger.Info(Format('Globale Einstellungen gelesen (%d Meldungen)', [Length(Issues) + Length(Misplaced)]));
    for Issue in Misplaced do
      FLogger.Warning(Issue.Message);
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
        Sources := Sources + [Change];
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
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  LoggerImpl: TLogger;
  Logger: ILogger;
  Transport: IJsonRpcTransport;
  Warning: string;
  TraceName: string;
  Anonymizer: ILogAnonymizer;
  RecentSink: TRecentLogSink;
  RecentLog: IRecentLogLines;
  Tracing: TJsonRpcTracingTransport;
begin
  Tracing := nil;
  // Stacktraces für das Absturzprotokoll (Exception.StackTrace).
  TStackTrace.Install;
  LoggerImpl := TLogger.Create;
  Logger := LoggerImpl;
  LoggerImpl.AddSink(TDebugOutputLogSink.Create, TLogLevel.Debug);
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
        Logger.Info(Format('Mitschnitt "%s" ist belegt, schreibe nach "%s"', [AOptions.TraceFile, TraceName]));
    except
      on E: Exception do
        Logger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [AOptions.TraceFile, E.Message]));
    end;
  LoggerImpl.AddSink(TLspLogMessageSink.Create(Transport), AOptions.LogLevel);

  for Warning in AOptions.Warnings do
    Logger.Warning(Warning);

  Result := TServerComposition.Create(Transport, Logger);
  if Tracing <> nil then
  begin
    Result.FTracing := Tracing;
    // Nur Logger einfangen; den Zyklus Logger → Sink → Transport → Closure bricht das einmalige
    // Leeren beim Melden bzw. Destroy (S-07). Anonym: Klasse und Meldung, kein Pfad.
    Tracing.OnFailed :=
      procedure(const AReason: string)
      begin
        Logger.Warning('Mitschnitt abgebrochen, der Server arbeitet ohne weiter: ' + AReason);
      end;
  end;
  Result.FRecentLog := RecentLog;
  Result.FLogAnonymizer := Anonymizer;
  Result.FRestricted := AOptions.Restricted;
  Result.FClientProcessId := AOptions.ClientProcessId;
  if AOptions.Restricted then
    Logger.Info('Eingeschränkter Modus (Arbeitsbereich nicht vertrauenswürdig): der Compiler wird nicht gestartet');
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
begin
  Result := Format('%s: %s%sLetzte Nachricht: %s', [AError.ClassName, AError.Message, sLineBreak,
    FDispatcher.LastMessage]);
  if AError.StackTrace <> '' then
    Result := Result + sLineBreak + AError.StackTrace;
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
  Result.AddPair('codeLensProvider', TLspCodeLens.Capability);
  Result.AddPair('semanticTokensProvider', TLspSemanticTokens.Capability);
  Result.AddPair('codeActionProvider', TLspCodeActions.Capability);
  Result.AddPair('documentLinkProvider', TLspDocumentLinks.Capability);
  Result.AddPair('colorProvider', TJSONBool.Create(True));
  Commands := TJSONArray.Create;
  Commands.Add(StatusCommand);
  Commands.Add(CompileCommand);
  Commands.Add(SelectBuildCommand);
  Commands.Add(RebuildIndexCommand);
  Commands.Add(ClearIndexCommand);
  Commands.Add(TBugReport.Command);
  Commands.Add(TQualifiedNames.Command);
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
