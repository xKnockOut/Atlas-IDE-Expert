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
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Lsp.DocumentLinks,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.Refactorings,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Query.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.Baseline,
  Shell.Composition.Editing,
  Shell.Composition.EditorCommands,
  Shell.Composition.ServerCommands,
  Shell.Composition.Status,
  Shell.Composition.Slash,
  Shell.Composition.Contract,
  Shell.Composition.UnitSearch,
  Shell.Composition.Workspaces,
  Shell.Composition.Ide,
  Shell.Composition.FileChanges,
  Shell.Composition.CompileSetup,
  Shell.Composition.Stdio,
  Shell.Composition.DfmPropertyRules,
  Shell.Composition.Core,
  Shell.Composition.AnalysisArea,
  Shell.Composition.CodeArea,
  Atlas.Common.Lsp.SemanticTokens,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Lsp.Processes,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Lsp.EnumValueCommands,
  Atlas.Common.Lsp.StringLiteralCommands,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Common.Lsp.WatchedFiles,
  Atlas.Common.Lsp.IdeProject,
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
  Shell.CommandLine,
  Shell.Composition.Compile,
  Atlas.Common.Diagnostics.Contract,
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
    /// <summary>Teilwurzel Code: Navigation, Refactorings, Vervollständigung, Code-Aktionen und Testunits.</summary>
    FCodeArea: TShellCodeArea;
    /// <summary>Teilwurzel Analyse: Analysen, Übersichten, Baselines und betroffene Tests.</summary>
    FAnalysisArea: TShellAnalysisArea;
    /// <summary>Daten des Fensters „Units suchen“ im Plugin (#777).</summary>
    FUnitSearch: TShellUnitSearch;
    FCommands: TLspCommands;
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
    /// <summary>Dateiänderungen von außen und Tipp-Pause (#492) (Shell.Composition.FileChanges).</summary>
    FFileChanges: TShellFileChanges;
    /// <summary>Build-Ergebnisse, Compilermeldungen (#528) und Projektkontext (#396) aus der IDE
    /// (Shell.Composition.Ide).</summary>
    FIde: TShellIde;
    /// <summary>Gemerkte Projektwahl über Neustarts (#46): selectBuild je Projekt, selectProject je Ordner.</summary>
    FProjectSelection: TProjectSelection;
    FWorkspaceFolders: TLspWorkspaceFolders;
    FConnection: TJsonRpcConnection;
    FIndex: ISymbolIndex;
    /// <summary>Uses-Graph über FIndex für uses-cycle und unused-unit (#64); lebt so lange wie der Index.</summary>
    FUsesGraph: TUsesGraphService;
    /// <summary>Arbeitsbereiche, Einstellungen, Ordner und was je Datei aus ihnen folgt.</summary>
    FCore: TShellCore;
    FCompilerProcess: ICompilerProcess;
    /// <summary>Compilerläufe (#40, #261): höchstens ein Lauf zugleich, ein weiterer wird vorgemerkt.</summary>
    FCompile: TShellCompileHost;
    /// <summary>Der Client hat keinen brauchbaren Ordner gemeldet (RAD Studio, #175):
    /// Ordner werden aus den geöffneten Dateien abgeleitet.</summary>
    FDeriveWorkspaces: Boolean;
    /// <summary>Überwacht den Editor-Prozess aus initialize oder der Befehlszeile.</summary>
    procedure WatchParent(const AInitializeParams: TJSONObject);
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
    /// <summary>Teil von Create (S-02): Arbeitsbereiche, Indexplanung und Konfiguration ohne Ordner; Pfade für die Syntaxprüfung.</summary>
    procedure WireWorkspaces;
    /// <summary>Was der Kern von der Komposition braucht.</summary>
    function CoreServices: TShellCoreServices;
    /// <summary>Teil von CoreServices: Meldungen des Kerns an die Komposition.</summary>
    procedure CoreEvents(var AServices: TShellCoreServices);
    /// <summary>Teil von Create (S-02): Symbolindex und Diagnoselog.</summary>
    procedure WireIndex;
    /// <summary>Teil von Create: Teilwurzel Code nach Kern und Index.</summary>
    procedure WireCode;
    /// <summary>Teil von Create (S-02): Signaturhilfe, Hierarchien, Implementierungen, Inlay-Hints, CodeLens, Metriken, TODOs, Baseline, Semantic Tokens.</summary>
    procedure WireAnalysis;
    /// <summary>Offene Dokumente bald neu prüfen.</summary>
    procedure RefreshDiagnosticsLater;
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
    /// <summary>Ruft AVisit mit allen Arbeitsbereichen unter FCore.Workspaces.Lock auf.</summary>
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
    function FileChangesServices: TShellFileChangesServices;
    /// <summary>Teil von Create (S-02): Anbindung an die IDE: Build-Meldungen und Projektkontext.</summary>
    procedure WireIde;
    /// <summary>Dienste der IDE-Nachrichten: Meldungen ersetzen die des letzten Laufs, Pause der Projektprüfung
    /// während eines Compiles, Neuprüfung nach neuen Präfixen.</summary>
    function IdeServices: TShellIdeServices;
    /// <summary>Teil von Create (S-02): Arbeitsbereichsordner und Ereignisse nach initialized.</summary>
    procedure WireWorkspaceFolders;
    /// <summary>Arbeitsbereichsordner entfernen und hinzufügen, wie der Client sie meldet.</summary>
    procedure WorkspaceFoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
    /// <summary>Nach initialized: Client, Einstellungen, Beobachtung und erste Arbeitsbereiche.</summary>
    procedure ClientInitialized;
    /// <summary>Name, Fähigkeiten und Editor-Einstellungen des Clients aus initialize.</summary>
    procedure ApplyClientInfo(const AParams: TJSONObject);
    /// <summary>Projektstufe (True) bzw. ganzer Aufbau eines Index fertig: Befunde neu prüfen (#647). Index-Thread.
    /// </summary>
    procedure IndexStageDone(AProjectStage: Boolean);
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Muster, Ordner und Testprogramm für Testunits zur Datei (#274, #189).</summary>
    function TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
    /// <summary>Projektdateien aller Ordner und geöffnete Dokumente, für Referenzen und Umbenennen.</summary>
    function ProjectSourceFiles: TArray<string>;
    /// <summary>Index und usesKeep für /sortuses (#297) und die uses-Diagnosen (#621); False, solange die
    /// Code-Aktionen fehlen.</summary>
    function UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
    /// <summary>Formatroutinen für den Parameter-Hint (#451): eingebaute, formatMethods der Regel format-args
    /// (atlas.json) und formatFunctions der Projektdatei .atlas (Projektkontext der IDE).</summary>
    function FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
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
    /// <summary>WorkspaceOf unter FCore.Workspaces.Lock.</summary>
    function LockedWorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Index und Arbeitsbereiche zu einem Dokumentereignis einer Datei auf der Platte.</summary>
    procedure DocumentIndexEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
    /// <summary>Gespeicherte Quelldatei: Index nachziehen (#500), bei compiler.onSave kompilieren (#40).</summary>
    procedure SourceSaved(const AFileName: string);
    /// <summary>Beenden: gibt Features, Ordner und Index frei.</summary>
    procedure FreeFeatures;
    /// <summary>Teil von FreeFeatures: Editor-Features von Gliederung bis Verweise.</summary>
    procedure FreeEditorFeatures;
    /// <summary>Teil von FreeFeatures: Analyse, Übersichten und Baselines.</summary>
    procedure FreeAnalysisFeatures;
    /// <summary>Teil von FreeFeatures: Vervollständigung, Code-Aktionen, Befehle, IDE und Protokoll.</summary>
    procedure FreeCodeFeatures;
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
  System.StrUtils,
  Atlas.Common.Product.Version,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Uris,
  Shell.Bootstrap,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Diagnostics.CheckProfile,
  Atlas.Common.Diagnostics.ServerPackage,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Editing.SmartPaste,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Projects.GroupReader,
  Atlas.Common.JsonRpc.Messages;

const
  /// <summary>Längste Pause der Projektprüfung für einen Compile, falls sein Ende nie ankommt (#1247).</summary>
  CompilePauseLimitMs = 10 * 60 * 1000;

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
  WireCode;
  WireAnalysis;
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
      if (FCore <> nil) and (FCore.Configuration.GlobalSettingsFile <> '') then
      begin
        Result := Result + [FCore.Configuration.GlobalSettingsFile];
      end;
      if not StartsText('file:', AUri) or (FCore = nil) then
      begin
        Exit;
      end;
      System.TMonitor.Enter(FCore.Workspaces.Lock);
      try
        mWorkspace := FCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
        if mWorkspace <> nil then
        begin
          Result := Result + [ExistingOrLegacyFile(mWorkspace.Root, ConfigurationFileName,
            LegacyConfigurationFileName)];
        end;
      finally
        System.TMonitor.Exit(FCore.Workspaces.Lock);
      end;
    end;
  FCrashCases.Notify := NotifyClient;
end;

procedure TServerComposition.PrepareReplay(const ASettingsFile: string);
begin
  FReplay := True;
  FCore.Configuration.UseReplaySettings(ASettingsFile);
  FCrashCases.Enabled := False;
  FCrashCases.SkipEnabled := False;
end;

procedure TServerComposition.WireCompile;
var
  mServices: TShellCompileSetupServices;
begin
  FCompilerProcess := TProcessRunner.Create;
  mServices := Default(TShellCompileSetupServices);
  mServices.Logger := FLogger;
  mServices.Transport := FTransport;
  mServices.Process := FCompilerProcess;
  mServices.Workspaces :=
    function: TShellWorkspaceRegistry
    begin
      Result := FCore.Workspaces;
    end;
  mServices.Publish :=
    procedure(const AFiles: TArray<string>)
    begin
      FSyntaxDiagnostics.RefreshFiles(AFiles);
    end;
  FCompile := TShellCompileSetup.NewHost(mServices);
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
  FPullDiagnostics := TLspPullDiagnostics.Create(FDocuments, FSyntaxDiagnostics, FTransport,
    function: TArray<string>
    begin
      Result := FCore.CheckFiles;
    end,
    FileStampOf, LoadExistingFile);
  FPullDiagnostics.Busy :=
    function: Boolean
    begin
      Result := FCore.Workspaces.ProjectIndexPending;
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
  mServices.SettingsFor :=
    function(const AUri: string): TServerSettings
    begin
      Result := FCore.Settings.SettingsFor(AUri);
    end;
  mServices.WorkspaceSettingsOf :=
    function(const AUri: string; out ASettings: TServerSettings): Boolean
    begin
      Result := FCore.Settings.WorkspaceSettingsOf(AUri, ASettings);
    end;
  mServices.TestUnitContextFor := TestUnitContextFor;
  mServices.RuleContextFor :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      Result := FCore.RuleContext.RuleContextFor(AUri, AContext);
    end;
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
  mServices.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := FCore.FileOptions.FormatStyleFor(AUri);
    end;
  mServices.ResolvedFormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := FCore.FileOptions.ResolvedFormatStyleFor(AUri);
    end;
  // Closure: Der Kern entsteht erst nach dem Editor (WireWorkspaces).
  mServices.SlashCommandsFor :=
    function(const AUri: string; out ADisabled: TArray<string>): Boolean
    begin
      Result := FCore.FileOptions.SlashCommandsFor(AUri, ADisabled);
    end;
  mServices.LanguageLevelFor :=
    function(const AUri: string): string
    begin
      Result := FCore.FileOptions.LanguageLevelFor(AUri);
    end;
  mServices.DocCommentsFor :=
    function(const AUri: string): Boolean
    begin
      Result := FCore.FileOptions.DocCommentsFor(AUri);
    end;
  mServices.ReadText := ReadSourceText;
  FEditing := TShellEditing.Create(mServices);
  FEditing.Attach(FDispatcher);
end;

function TServerComposition.SlashWorkspaceOf(const AUri: string): TShellWorkspace;
begin
  TMonitor.Enter(FCore.Workspaces.Lock);
  try
    Result := FCore.Workspaces.Pick(TDocumentUris.ToPath(AUri));
  finally
    TMonitor.Exit(FCore.Workspaces.Lock);
  end;
end;

procedure TServerComposition.WireWorkspaces;
begin
  FCore := TShellCore.Create(CoreServices);
  FDocuments.Subscribe(HandleDocumentEvent);
  FCore.Attach(FDispatcher);
end;

function TServerComposition.CoreServices: TShellCoreServices;
begin
  Result := Default(TShellCoreServices);
  Result.Logger := FLogger;
  Result.Transport := FTransport;
  Result.Documents := FDocuments;
  Result.Index :=
    function: ISymbolIndex
    begin
      Result := FIndex;
    end;
  Result.UsesGraph :=
    function: TUsesGraphService
    begin
      Result := FUsesGraph;
    end;
  Result.Queries :=
    function: ICodeQueries
    begin
      Result := FAnalysisArea.Overviews.Queries;
    end;
  Result.SelectedProject :=
    function(const AOrigin: string): string
    begin
      Result := FProjectSelection.Project(AOrigin);
    end;
  Result.ActiveProject :=
    function: string
    begin
      Result := FIde.Project.ActiveProject;
    end;
  Result.IdeProject :=
    function: TLspIdeProject
    begin
      Result := FIde.Project;
    end;
  Result.Selection :=
    function: TProjectSelection
    begin
      Result := FProjectSelection;
    end;
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := FLogAnonymizer;
    end;
  Result.ClientName :=
    function: string
    begin
      Result := FClientName;
    end;
  CoreEvents(Result);
end;

procedure TServerComposition.CoreEvents(var AServices: TShellCoreServices);
begin
  AServices.ProjectLoaded := ProjectLoaded;
  AServices.IndexStageDone := IndexStageDone;
  AServices.IndexEvent :=
    procedure(AText: string)
    begin
      // Absicherung: Beim Beenden ist das Diagnoselog schon fort (Code-Review A-05).
      if FDiagnostics <> nil then
      begin
        FDiagnostics.Log.LogEvent(AText);
      end;
    end;
  AServices.SettingsChanged :=
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
  // Im Thread der Nachrichtenschleife verarbeiten wie eine Meldung des Clients.
  AServices.FilesChanged :=
    procedure(const AFiles: TArray<string>)
    begin
      FConnection.Post(TLspWatchedFiles.Notification(AFiles));
    end;
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
      Result := FCore.Workspaces.IndexLoading;
    end;
  FDispatcher.Observer := FDiagnosticsRef;
end;

procedure TServerComposition.WireCode;
var
  mServices: TShellCodeAreaServices;
begin
  mServices := Default(TShellCodeAreaServices);
  mServices.Logger := FLogger;
  mServices.Dispatcher := FDispatcher;
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.Editing := FEditing;
  mServices.RuleIdsFor :=
    function(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean
    begin
      Result := FSlash.RuleIdsAt(AUri, AText, ALine, AIds);
    end;
  mServices.MessagesFor :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompile.Results.MessagesFor(AFileName);
    end;
  // Closure: FIde entsteht erst in WireIde.
  mServices.IdeProjectFor :=
    function(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean
    begin
      Result := FIde.Project.Find(AProjectFile, AContext);
    end;
  mServices.VisitWorkspaces := VisitWorkspaces;
  mServices.Notify := NotifyClient;
  mServices.Log := LogDebug;
  FCodeArea := TShellCodeArea.Create(FCore, mServices);
end;

procedure TServerComposition.WireAnalysis;
var
  mServices: TShellAnalysisAreaServices;
begin
  mServices := Default(TShellAnalysisAreaServices);
  mServices.Logger := FLogger;
  mServices.Dispatcher := FDispatcher;
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.FormatRoutinesFor := FormatRoutinesFor;
  mServices.UsesContextFor := UsesContextFor;
  mServices.RefreshLater := RefreshDiagnosticsLater;
  mServices.TestUnitContext := TestUnitContextFor;
  mServices.RequestTimeout := CurrentRequestTimeout;
  FAnalysisArea := TShellAnalysisArea.Create(FCore, mServices);
end;

procedure TServerComposition.RefreshDiagnosticsLater;
begin
  FSyntaxDiagnostics.RefreshLater;
end;

procedure TServerComposition.WireEditorCommands;
var
  mServices: TShellEditorCommandServices;
begin
  mServices := Default(TShellEditorCommandServices);
  mServices.Documents := FDocuments;
  mServices.Index := FIndex;
  mServices.EnsureUnit := FCore.Folders.EnsureUnitFunc();
  mServices.ReadText := ReadSourceText;
  mServices.Namespaces :=
    function: TArray<string>
    begin
      Result := FCodeArea.Navigation.Namespaces;
    end;
  mServices.HighlightSettingsFor :=
    function(const AUri: string): THighlightSettings
    begin
      Result := FCore.Settings.Highlight(AUri);
    end;
  mServices.StringLiteralFor :=
    function(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings
    begin
      Result := FCore.Settings.StringLiteral(AUri, AMultiline);
    end;
  mServices.ResourceStringWrite := FSlash.ResourceStringWrite;
  FEditorCommands := TShellEditorCommands.Create(mServices);
end;

procedure TServerComposition.WireCommands;
var
  mDfmRules: TShellDfmPropertyRulesServices;
begin
  FCommands := TLspCommands.Create;
  WireStatus;
  WireServerCommands;
  FServerCommands.RegisterConvertCommand(FCommands);
  mDfmRules := Default(TShellDfmPropertyRulesServices);
  mDfmRules.Logger := FLogger;
  mDfmRules.Workspaces := FCore.Workspaces;
  mDfmRules.RuleContext := FCore.RuleContext;
  mDfmRules.ReadText := ReadSourceText;
  TShellDfmPropertyRules.Attach(FCommands, mDfmRules);
  FCodeArea.Refactorings.Register(FCommands);
  WireReportCommands;
  FAnalysisArea.Overviews.RegisterUnitCommands(FCommands);
  WireEditorCommands;
  FEditorCommands.RegisterMarkCommands(FCommands);
  FAnalysisArea.Baselines.RegisterCommands(FCommands);
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
  FAnalysisArea.Analysis.RegisterReportCommands(FCommands);
  FAnalysisArea.Overviews.RegisterReportCommands(FCommands);
end;

procedure TServerComposition.WireSlashCommands;
begin
  FAnalysisArea.Baselines.RegisterClassifyCommand(FCommands);
  FEditing.RegisterCommands(FCommands);
  FCodeArea.TestUnits.RegisterCommand(FCommands);
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
      Result := FCore.Configuration.GlobalSettingsFile;
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
      Result := FCore.Workspaces.IsSelected(AWorkspace);
    end;
  mServices.ActiveProject :=
    function: string
    begin
      Result := FIde.Project.ActiveProject;
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
      Result := FCore.Settings.EditorSettings;
    end;
  mServices.ActiveProject :=
    function: string
    begin
      Result := FIde.Project.ActiveProject;
    end;
  mServices.IsSelectedProject :=
    function(AWorkspace: TShellWorkspace): Boolean
    begin
      Result := FCore.Workspaces.IsSelected(AWorkspace);
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
      Result := FCore.Folders.Scheduler.Queue;
    end;
end;

procedure TServerComposition.VisitWorkspaces(const AVisit: TShellWorkspacesProc);
begin
  FCore.Workspaces.Visit(AVisit);
end;

function TServerComposition.CommandWorkspaces(const AUri: string): TArray<TShellWorkspace>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  TMonitor.Enter(FCore.Workspaces.Lock);
  try
    if AUri = '' then
    begin
      Result := FCore.Workspaces.Items.ToArray;
    end
    else
    begin
      mWorkspace := FCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
      if mWorkspace <> nil then
      begin
        Result := [mWorkspace];
      end;
    end;
  finally
    TMonitor.Exit(FCore.Workspaces.Lock);
  end;
end;

procedure TServerComposition.WireWatchedFiles;
begin
  FFileChanges := TShellFileChanges.Create(FileChangesServices);
  FFileChanges.Attach(FDispatcher);
end;

function TServerComposition.FileChangesServices: TShellFileChangesServices;
begin
  Result := Default(TShellFileChangesServices);
  Result.Logger := FLogger;
  Result.Workspaces := FCore.Workspaces;
  Result.Transport := FTransport;
  Result.Configuration := FCore.Configuration;
  Result.RefreshLater :=
    procedure
    begin
      if FSyntaxDiagnostics <> nil then
      begin
        FSyntaxDiagnostics.RefreshLater;
      end;
    end;
  // Beim Tippen macht die Projektprüfung Platz (#1247).
  Result.Typed :=
    procedure
    begin
      if FPullDiagnostics <> nil then
      begin
        FPullDiagnostics.Typed;
      end;
    end;
  Result.Affected :=
    procedure(const AFiles: TArray<string>)
    begin
      if FPullDiagnostics <> nil then
      begin
        FPullDiagnostics.Check.Affected(AFiles, True);
      end;
    end;
end;

function TServerComposition.IdeServices: TShellIdeServices;
begin
  Result := Default(TShellIdeServices);
  Result.Logger := FLogger;
  Result.Workspaces := FCore.Workspaces;
  Result.MessagesReceived :=
    procedure(const AMessages: TArray<TCompilerMessage>)
    begin
      FSyntaxDiagnostics.RefreshFiles(FCompile.Results.Replace(AMessages));
    end;
  Result.Compiling :=
    procedure(ARunning: Boolean)
    begin
      // Die Frist ist ein Sicherheitsnetz für ein verlorenes Ende, keine Steuerung.
      FPullDiagnostics.Check.Pause(TLspWorkspaceCheck.cPauseCompile, ARunning, CompilePauseLimitMs);
    end;
  Result.NamingChanged :=
    procedure
    begin
      FSyntaxDiagnostics.RefreshLater;
    end;
end;

procedure TServerComposition.WireIde;
begin
  FIde := TShellIde.Create(IdeServices);
  FIde.Attach(FDispatcher);
  // Projektwahl je Benutzer über Neustarts (#46).
  FProjectSelection := TProjectSelection.Create(TPath.Combine(TIndexCacheDirectory.DefaultRoot,
    'projektauswahl.json'));
end;

procedure TServerComposition.WireWorkspaceFolders;
begin
  FWorkspaceFolders := TLspWorkspaceFolders.Create;
  FWorkspaceFolders.OnChanged := WorkspaceFoldersChanged;
  FWorkspaceFolders.Attach(FDispatcher);
  FLifecycle.OnInitialized := ClientInitialized;
end;

procedure TServerComposition.WorkspaceFoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
var
  mFolder: TWorkspaceFolder;
begin
  for mFolder in ARemoved do
  begin
    FCore.Folders.Remove(mFolder);
  end;
  for mFolder in AAdded do
  begin
    FCore.Folders.Add(mFolder);
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
  FIde.Project.LoadInitialize(FLifecycle.InitializeParams);
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
  FCore.Configuration.Start;
  for mFolder in mFolders do
  begin
    FCore.Folders.Add(mFolder);
  end;
  FCore.Configuration.UpdateWatchedFiles;
  FFileChanges.RegisterWatchers(FLifecycle.InitializeParams);
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
    FCore.Settings.SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams.GetValue('initializationOptions')));
  end
  else
  begin
    // Ohne Parameter bleibt die Editor-Ebene leer; die Einstellungen ohne Arbeitsbereich gelten trotzdem neu.
    FCore.Settings.SetEditorSettings(FCore.Settings.EditorSettings);
  end;
  FCodeArea.Navigation.Hover.Markdown := TLspHover.ClientSupportsMarkdown(AParams);
  // Code-Vorlagen mit Platzhaltern nur an Clients mit snippetSupport (#51).
  FCodeArea.Completion.Completion.SnippetSupport := TLspCompletion.ClientSupportsSnippets(AParams);
  FCodeArea.Completion.Completion.DocumentationMarkdown := TLspCompletion.ClientPrefersMarkdown(AParams);
end;

destructor TServerComposition.Destroy;
var
  Unfinished: Boolean;
begin
  TPascalPreprocessor.SetDeclaredProvider(nil);
  // Zuerst: Eine laufende Übernahme greift auf die Ordner zu.
  if FFileChanges <> nil then
  begin
    FFileChanges.StopRefresh;
  end;
  // Vor der Verbindung: Beide Wächter rufen FConnection.
  if FCore <> nil then
  begin
    FCore.Configuration.StopWatching;
  end;
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
  if FCore <> nil then
  begin
    FCore.StopIndexThreads;
  end;
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

procedure TServerComposition.FreeFeatures;
begin
  // Vor den Ordnern: der Hintergrund-Thread der Syntaxprüfung fragt ihre Symbole ab.
  FPullDiagnostics.Free;
  FSyntaxDiagnostics.Free;
  // Ordner vor dem Index: ihre Index-Threads laufen noch.
  FCore.FreeWorkspaces;
  // Nach den Ordnern: Ihre Index-Threads melden Projektstufe und Ende.
  FIndexRecheck.Free;
  FreeAndNil(FCore);
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
  FreeAndNil(FAnalysisArea);
end;

procedure TServerComposition.FreeCodeFeatures;
begin
  FreeAndNil(FCodeArea);
  FreeAndNil(FEditorCommands);
  FreeAndNil(FServerCommands);
  FreeAndNil(FStatusReports);
  FreeAndNil(FUnitSearch);
  FreeAndNil(FCommands);
  // Nach allen Nutzern des Hosts der Schnellbefehle: Er ruft dessen Methoden.
  FreeAndNil(FSlash);
  FreeAndNil(FCompile);
  FCompilerProcess := nil;
  FreeAndNil(FFileChanges);
  FreeAndNil(FIde);
  FreeAndNil(FProjectSelection);
  FreeAndNil(FTextDocumentSync);
  // Nach der Verbindung und dem Watchdog: Niemand meldet mehr einen Absturz.
  FreeAndNil(FCrashCases);
  FDocuments := nil;
  FreeAndNil(FLifecycle);
  FreeAndNil(FDispatcher);
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
  if not FCore.Workspaces.ProjectIndexPending then
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
          TMonitor.Enter(FCore.Workspaces.Lock);
          try
            Workspaces := FCore.Workspaces.Items.ToArray;
          finally
            TMonitor.Exit(FCore.Workspaces.Lock);
          end;
          for Workspace in Workspaces do
          begin
            Workspace.Configuration.Revalidate;
          end;
        end);
    end;
  end;
end;

function AllocatedBytes: Int64;
begin
  Result := TShutdownLeaks.AllocatedBytes;
end;

function TServerComposition.ReadSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FCore.ReadText(AFileName, AText);
end;

function TServerComposition.TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  Result := (FCodeArea <> nil) and FCodeArea.TestUnits.ContextFor(AUri, AContext);
end;

function TServerComposition.ProjectSourceFiles: TArray<string>;
begin
  Result := FCore.ProjectFiles;
end;

function TServerComposition.UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := (FCodeArea <> nil) and FCodeArea.UsesContextFor(AUri, AContext);
end;

function TServerComposition.FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
var
  Workspace: TShellWorkspace;
  Project: TProjectInfo;
  Context: TIdeProjectContext;
  Name: string;
begin
  Result := TFormatRoutines.Defaults;
  for Name in TRuleOptions.Strings(TRuleEngine.RuleOptions(FormatArgsRuleId, FCore.Settings.SettingsFor(AUri)), 'formatMethods',
    nil) do
  begin
    if Trim(Name) <> '' then
    begin
      Result := Result + [TFormatRoutines.Custom(Name, -1)];
    end;
  end;
  Workspace := FCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
  if (Workspace <> nil) and Workspace.State.Project(Project) and FIde.Project.Find(Project.FileName, Context) then
  begin
    Result := Result + Context.FormatFunctions;
  end;
end;

function TServerComposition.SyntaxDiagnosticsProviders: TSyntaxDiagnosticsProviders;
begin
  Result := Default(TSyntaxDiagnosticsProviders);
  // Closures: Die Syntaxprüfung entsteht vor dem Kern (WireDocuments vor WireWorkspaces).
  Result.Defines :=
    function(const AUri: string; out ADefines: TArray<string>): Boolean
    begin
      Result := FCore.Directives.Defines()(AUri, ADefines);
    end;
  // Sprachstand (#1126): minDelphiVersion begrenzt, was die Regeln als verfügbar ansehen.
  Result.Version :=
    function(const AUri: string): string
    begin
      Result := FCore.FileOptions.LanguageLevelFor(AUri);
    end;
  Result.BuildTarget :=
    function(const AUri: string; out APlatform, AConfig: string): Boolean
    begin
      Result := FCore.Directives.BuildTarget()(AUri, APlatform, AConfig);
    end;
  Result.Rules :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      Result := FCore.RuleContext.LiveRuleContextFor(AUri, AContext);
    end;
  Result.CompilerMessages :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := FCompile.Results.MessagesFor(AFileName);
    end;
  // Ungenutzte uses (#621): dieselbe Analyse wie die uses-Aktionen, auch für die Diagnosen.
  Result.UsesContext := UsesContextFor;
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
  System.TMonitor.Enter(FCore.Workspaces.Lock);
  try
    // Projekte für projektweite Prüfregeln neu bestimmen (#1102).
    FCore.Workspaces.Touch;
    for mWorkspace in FCore.Workspaces.Items do
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
    System.TMonitor.Exit(FCore.Workspaces.Lock);
  end;
end;

procedure TServerComposition.ApplyNamespaces(const ANamespaces: TArray<string>);
var
  mGraphOptions: TUsesGraphOptions;
begin
  FCodeArea.Navigation.SetNamespaces(ANamespaces);
  // Uses-Graph (#64) löst Namen ohne Namensraum über dieselbe Liste auf; neu aufgebaut nur bei Änderung.
  mGraphOptions := FUsesGraph.Options;
  if string.Join(';', mGraphOptions.Namespaces) <> string.Join(';', ANamespaces) then
  begin
    mGraphOptions.Namespaces := ANamespaces;
    FUsesGraph.SetOptions(mGraphOptions);
  end;
  FCodeArea.Completion.Completion.Namespaces := ANamespaces;
  FAnalysisArea.Analysis.SetNamespaces(ANamespaces);
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
    FCore.Configuration.DocumentEvent(AKind, ADocument);
  end;
end;

function TServerComposition.LockedWorkspaceOf(const AFileName: string): TShellWorkspace;
begin
  System.TMonitor.Enter(FCore.Workspaces.Lock);
  try
    Result := FCore.Workspaces.WorkspaceOf(AFileName);
  finally
    System.TMonitor.Exit(FCore.Workspaces.Lock);
  end;
end;

procedure TServerComposition.DocumentIndexEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
var
  mWorkspace: TShellWorkspace;
begin
  // Tipp-Pause (#492): ungespeicherten Stand in den Index; beim Schließen wieder den der Platte.
  if FFileChanges <> nil then
  begin
    FFileChanges.DocumentEvent(AKind, AFileName, AText);
  end;
  if AKind <> TDocumentEventKind.Opened then
  begin
    Exit;
  end;
  if FDeriveWorkspaces then
  begin
    FCore.Folders.Derive(AFileName);
  end;
  // Zurückgestelltes Projekt der Gruppe (index.projectGroup = false): jetzt indizieren (#648).
  mWorkspace := LockedWorkspaceOf(AFileName);
  // Nur der Thread der Nachrichtenschleife entfernt Arbeitsbereiche; mWorkspace bleibt gültig.
  if (mWorkspace <> nil) and mWorkspace.Setup.Deferred then
  begin
    mWorkspace.Activate;
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
    FFileChanges.Handle([TFileChange.Create(AFileName, TFileChangeKind.Changed)]);
  end;
  System.TMonitor.Enter(FCore.Workspaces.Lock);
  try
    mWorkspace := FCore.Workspaces.WorkspaceOf(AFileName);
    mOnSave := (mWorkspace <> nil) and mWorkspace.Configuration.Settings.Compiler.OnSave;
  finally
    System.TMonitor.Exit(FCore.Workspaces.Lock);
  end;
  if mOnSave then
  begin
    FCompile.Start(AFileName, False, mChoice);
  end;
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  mChannel: TShellStdioChannel;
  mLogger: ILogger;
begin
  mChannel := TShellStdio.Open(AOptions);
  mLogger := mChannel.Logger;
  Result := TServerComposition.Create(mChannel.Transport, mLogger);
  Result.FTracing := mChannel.Tracing;
  Result.FRecentLog := mChannel.RecentLog;
  Result.FLogAnonymizer := mChannel.Anonymizer;
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
