unit Atlas.Common.Lsp.Contract;

// Contract des Platform-Features Lsp: Konstanten des Language Server Protocol,
// die über JSON-RPC 2.0 hinausgehen.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON,
  Atlas.Common.Diagnostics.Contract;

type
  /// <summary>Zusätzliche Fehlercodes des Language Server Protocol.</summary>
  TLspErrorCode = record
  public const
    cServerNotInitialized = -32002;
    cRequestFailed = -32803;
    cServerCancelled = -32802;
  end;

  /// <summary>Werte für die Capability textDocumentSync.</summary>
  TLspTextDocumentSyncKind = record
  public const
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

  /// <summary>Ein Typ, den die IDE kennt, mit seiner Unit.</summary>
  TIdeTypeEntry = record
    Name: string;
    UnitName: string;
    /// <summary>Direkter Vorfahr einer Klasse mit Unit (Vcl.Controls.TCustomControl); '' ohne Angabe.</summary>
    Parent: string;
  end;

  /// <summary>Typen der laufenden IDE (atlas/ideTypes); threadsicher. Ohne Plugin leer.</summary>
  ILspIdeTypes = interface
    ['{9EEBF436-AD07-4D64-B8AB-436A346A4F28}']
    /// <summary>Units, in denen die IDE den Typ ATypeName kennt (ohne Beachtung der Groß-/Kleinschreibung).</summary>
    function UnitsOf(const ATypeName: string): TArray<string>;
    /// <summary>Alle Typen mit Unit, in der Reihenfolge der Meldung.</summary>
    function Entries: TArray<TIdeTypeEntry>;
  end;

  /// <summary>Projekt und Dateien für die Suche; die Shell liest geöffnete Dokumente vor der Platte.</summary>
  ILeakCandidateFiles = interface
    ['{4C1E7B52-8D3A-4F6E-9B21-6A0D5E3C7F14}']
    /// <summary>Hauptquelltext und Quelldateien des Projekts hinter AUri; False mit AReason ohne Projekt.</summary>
    function ProjectOf(const AUri: string; out AMainSource: string; out AFiles: TArray<string>;
      out AReason: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

  /// <summary>Dateien zum Bericht; die Komposition kennt Projekt und Arbeitsbereich.</summary>
  IRuntimeReportFiles = interface
    ['{8B2F6C41-3E7D-4A95-B1C8-5D0E9F27A6C3}']
    /// <summary>EXE des Projekts hinter AUri (ihre Map gilt, wenn der Aufruf weder Map noch EXE nennt); '' ohne
    /// Projekt oder Ausgabeordner.</summary>
    function ExecutableOf(const AUri: string): string;
    /// <summary>Datei im Projekt hinter AUri zu Unit bzw. Dateiname; '' außerhalb.</summary>
    function UnitFileOf(const AUri: string): TReportUnitFileFunc;
  end;

implementation

end.
