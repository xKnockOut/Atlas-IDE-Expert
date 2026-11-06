unit Atlas.Common.Lsp.Contract;

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
    cServerNotInitialized = -32002;
    cUnknownErrorCode = -32001;
    cRequestFailed = -32803;
    cServerCancelled = -32802;
    cContentModified = -32801;
    cRequestCancelled = -32800;
  end;

  /// <summary>Werte für die Capability textDocumentSync.</summary>
  TLspTextDocumentSyncKind = record
  public const
    cNone = 0;
    cFull = 1;
    cIncremental = 2;
  end;

  /// <summary>Methodennamen des Lebenszyklus.</summary>
  TLspLifecycleMethod = record
  public const
    cInitializeRequest = 'initialize';
    cInitializedNotification = 'initialized';
    cShutdownRequest = 'shutdown';
    cExitNotification = 'exit';
  end;

  /// <summary>Methodennamen der Dokumentsynchronisation.</summary>
  TLspTextDocumentMethod = record
  public const
    cDidOpen = 'textDocument/didOpen';
    cDidChange = 'textDocument/didChange';
    cDidSave = 'textDocument/didSave';
    cDidClose = 'textDocument/didClose';
    cPublishDiagnostics = 'textDocument/publishDiagnostics';
  end;

  /// <summary>Werte für DiagnosticSeverity.</summary>
  TLspDiagnosticSeverity = record
  public const
    cError = 1;
    cWarning = 2;
    cInformation = 3;
    cHint = 4;
  end;

  /// <summary>Werte für SymbolKind des LSP (Auswahl).</summary>
  TLspSymbolKind = record
  public const
    cModule = 2;
    cNamespace = 3;
    cClass_ = 5;
    cMethod = 6;
    cProperty_ = 7;
    cField = 8;
    cConstructor_ = 9;
    cEnum = 10;
    cInterface_ = 11;
    cFunction_ = 12;
    cVariable = 13;
    cConstant = 14;
    cObject_ = 19;
    cEnumMember = 22;
    cStruct = 23;
    cEvent = 24;
    cTypeParameter = 26;
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
