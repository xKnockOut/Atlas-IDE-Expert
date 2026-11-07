unit Shell.Composition.Status.Contract;

// Internals-Rolle Shell: Dienste, die Status, Fehlerbericht und Diagnosepaket (Shell.Composition.Status) von der
// Komposition bekommen. Eigene Unit, damit die Verdrahtung die Dienste füllen kann, ohne den Statusbericht
// selbst zu kennen.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.WorkspaceCheck,
  Shell.Workspace,
  Shell.Composition.Contract;

type
  TShellStatusTextFunc = reference to function: string;
  TShellStatusSelectedFunc = reference to function(AWorkspace: TShellWorkspace): Boolean;
  TShellStatusRecentLogFunc = reference to function: IRecentLogLines;
  TShellStatusTracingFunc = reference to function: TJsonRpcTracingTransport;
  TShellStatusAnonymizerFunc = reference to function: ILogAnonymizer;
  TShellStatusCompilerProc = reference to procedure(var AStatus: TServerStatus);
  TShellStatusCheckProc = reference to procedure(var AStatus: TServerStatus; out AQueue: TWorkspaceCheckQueue);
  TShellStatusIndexQueueFunc = reference to function: TIndexSchedulerQueue;

  /// <summary>Was Status, Fehlerbericht und Diagnosepaket von der Komposition brauchen.</summary>
  TShellStatusServices = record
    Logger: ILogger;
    Index: ISymbolIndex;
    Documents: IDocumentStore;
    Statistics: IJsonRpcStatistics;
    /// <summary>Ruft AVisit mit allen Arbeitsbereichen unter deren Sperre auf.</summary>
    VisitWorkspaces: TShellVisitWorkspacesProc;
    /// <summary>Einstellungen des Editors (Text der Schichtung).</summary>
    EditorSettings: TShellStatusTextFunc;
    /// <summary>Aktives Projekt der IDE.</summary>
    ActiveProject: TShellStatusTextFunc;
    IsSelectedProject: TShellStatusSelectedFunc;
    /// <summary>Letzte Logzeilen; nil ohne Protokoll im Speicher.</summary>
    RecentLog: TShellStatusRecentLogFunc;
    /// <summary>Mitschnitt der Nachrichten; nil ohne.</summary>
    Tracing: TShellStatusTracingFunc;
    /// <summary>Anonymisierung von Namen; nil ohne.</summary>
    Anonymizer: TShellStatusAnonymizerFunc;
    CompilerStatus: TShellStatusCompilerProc;
    /// <summary>Profil des Prüflaufs in AStatus und dessen Warteschlange.</summary>
    CheckStatus: TShellStatusCheckProc;
    IndexQueue: TShellStatusIndexQueueFunc;
  end;

implementation

end.
