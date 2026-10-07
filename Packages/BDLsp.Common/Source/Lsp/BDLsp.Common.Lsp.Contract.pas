unit BDLsp.Common.Lsp.Contract;

// Contract des Platform-Features Lsp: Konstanten des Language Server Protocol,
// die über JSON-RPC 2.0 hinausgehen.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON;

type
  /// <summary>Zusätzliche Fehlercodes des Language Server Protocol.</summary>
  TLspErrorCode = record
  public const
    ServerNotInitialized = -32002;
    UnknownErrorCode = -32001;
    RequestFailed = -32803;
    ServerCancelled = -32802;
    ContentModified = -32801;
    RequestCancelled = -32800;
  end;

  /// <summary>Werte für die Capability textDocumentSync.</summary>
  TLspTextDocumentSyncKind = record
  public const
    None = 0;
    Full = 1;
    Incremental = 2;
  end;

  /// <summary>Methodennamen des Lebenszyklus.</summary>
  TLspLifecycleMethod = record
  public const
    InitializeRequest = 'initialize';
    InitializedNotification = 'initialized';
    ShutdownRequest = 'shutdown';
    ExitNotification = 'exit';
  end;

  /// <summary>Methodennamen der Dokumentsynchronisation.</summary>
  TLspTextDocumentMethod = record
  public const
    DidOpen = 'textDocument/didOpen';
    DidChange = 'textDocument/didChange';
    DidSave = 'textDocument/didSave';
    DidClose = 'textDocument/didClose';
  end;

  /// <summary>Zustand des Servers im Lebenszyklus.</summary>
  TLspServerState = (
    /// <summary>Wartet auf initialize.</summary>
    Uninitialized,
    /// <summary>initialize beantwortet, bearbeitet Anfragen.</summary>
    Running,
    /// <summary>shutdown beantwortet, wartet auf exit.</summary>
    ShuttingDown,
    /// <summary>exit empfangen.</summary>
    Exited);

  /// <summary>Liefert die Capabilities für die Antwort auf initialize; der Aufrufer übernimmt das Objekt.</summary>
  TLspCapabilitiesFactory = reference to function: TJSONObject;

implementation

end.
