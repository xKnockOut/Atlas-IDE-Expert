unit Atlas.Common.Lsp.Contract;

// Contract des Platform-Features Lsp: Konstanten des Language Server Protocol,
// die über JSON-RPC 2.0 hinausgehen.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Findings.Contract;

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

  /// <summary>Vererbungstiefe der Klassen einer Datei (#980) für Code Lens und atlas.server.metrics; der Host
  /// rechnet sie wie die Regel metric-inheritance-depth.</summary>
  ILspInheritanceDepths = interface
    ['{2E6CB6E2-A65B-416D-BB3B-154AA0138F25}']
    /// <summary>Je Klasse mit eigenen Vorfahren ein Eintrag; AIndex nil = nur die Datei.</summary>
    function Depths(const AFileName, AText: string; const AIndex: ISymbolIndex): TArray<TStructureMetrics>;
  end;

  /// <summary>Angaben des Regelkatalogs zu einer Regel für data eines Befunds (#909, #1024).</summary>
  TLspRuleFacts = record
    Category: string;
    Group: string;
    /// <summary>Compilermeldungen, die die Regel vorwegnimmt; leer ohne.</summary>
    CompilerCodes: TArray<string>;
  end;

  /// <summary>Regelkatalog für Befunde und Vervollständigung des Sprachservers; der Host fragt die Prüfregeln.
  /// </summary>
  ILspRuleCatalog = interface
    ['{8B3E5C17-A9D2-4F60-8E4B-C1D7F2A96B35}']
    /// <summary>Kennungen aller eingebauten Regeln (/ignore, #293).</summary>
    function RuleIds: TArray<string>;
    /// <summary>Angaben zu ARuleId; False, wenn der Katalog die Regel nicht kennt.</summary>
    function TryDescribe(const ARuleId: string; out AFacts: TLspRuleFacts): Boolean;
    /// <summary>Hilfeseite zu ARuleId (codeDescription.href).</summary>
    function HelpUri(const ARuleId: string): string;
    /// <summary>Befund durchgestrichen zeigen (DiagnosticTag.Deprecated, #38, #1018)?</summary>
    function StruckThrough(const AFinding: TRuleFinding): Boolean;
  end;

  /// <summary>Prüfregeln für ein Dokument der Diagnose (textDocument/publishDiagnostics und Pull); der Host baut
  /// das Umfeld der Regeln. Läuft im Hintergrund-Thread.</summary>
  ILspDocumentRules = interface
    ['{F2D4E2D7-65DE-4E71-A07C-012689A3199D}']
    /// <summary>Syntaxfehler im Baum von ADocument unter ADefines (gemeinsamer Zwischenspeicher, #845) als Treffer
    /// der Regel syntax (#1022): Schweregrad und Gruppe aus der Konfiguration, ohne Umfeld Fehler.</summary>
    function SyntaxFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    /// <summary>Sprachmerkmale, die ADelphiVersion noch nicht kennt, als Treffer der Regel language-feature
    /// (#109, #1126); nicht in AInactive.</summary>
    function LanguageFeatureFindings(const ADocument: ITextDocument; const ADefines: TArray<string>;
      const ADelphiVersion: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
    /// <summary>Treffer der Prüfregeln ohne die bekannten der Baseline (#97), über den gemeinsamen Speicher der
    /// Treffer; leer ohne Regeln. Abbruch zwischen den Regeln mit ERuleCheckCancelled.</summary>
    function RuleFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    /// <summary>Zeigt der Editor ungenutzte uses (Regel unused-uses, #1135)? Ohne Umfeld ja.</summary>
    function UnusedUsesShown: Boolean;
    /// <summary>Zeigt der Editor „nur in der implementation gebraucht“ (uses-only-in-implementation, #1136)? Ohne
    /// Umfeld ja.</summary>
    function OnlyImplementationShown: Boolean;
    /// <summary>Regelkatalog für die Anzeige der Treffer; nil ohne.</summary>
    function Catalog: ILspRuleCatalog;
  end;

  /// <summary>Prüfregeln der Diagnose je Dokument; ohne Anbieter meldet die Diagnose keine Treffer.</summary>
  ILspRuleDiagnostics = interface
    ['{7B7B6495-22F6-4A8E-BCF0-8164981D7119}']
    /// <summary>Prüfung für AUri; ACancelled (nil = nie) bricht zwischen den Regeln ab. Nie nil.</summary>
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): ILspDocumentRules;
  end;

  /// <summary>Prüfregeln für ein Dokument der Code-Aktionen (textDocument/codeAction, #42, #182); der Host baut das
  /// Umfeld der Regeln. Der Baum ist der gemeinsame der Datei.</summary>
  ILspDocumentRuleActions = interface
    ['{E3A9C5D1-7B24-4C8F-A6E0-1F9B3D7C2A58}']
    /// <summary>Syntaxfehler mit ihrer Korrektur (#1022); ohne Umfeld mit den Vorgaben.</summary>
    function SyntaxFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
    /// <summary>Treffer der Prüfregeln aus dem gemeinsamen Speicher, sonst selbst gerechnet; Ende des Wartens mit
    /// ERuleCheckCancelled.</summary>
    function SharedRuleFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
    /// <summary>Treffer nur aus dem gemeinsamen Speicher, ohne eigenen Lauf; False ohne.</summary>
    function CachedRuleFindings(const ADocument: ITextDocument; out AFindings: TArray<TRuleFinding>): Boolean;
    /// <summary>Korrekturen und Unterdrückungen in ARange, mit ATryFinally auch try/finally.</summary>
    function Fixes(const AFindings: TArray<TRuleFinding>; const ADocument: ITextDocument; const ARange: TTextRange;
      const AStyle: TFormatStyle; ATryFinally: Boolean): TArray<TCodeAction>;
    /// <summary>Alle sicheren Korrekturen in einer Aktion; False ohne.</summary>
    function FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
    /// <summary>Befund als Auftrag für KI-Assistenten (#158, #2570).</summary>
    function Prompt(const AFinding: TRuleFinding; const AFileName, AText: string): string;
    /// <summary>Index des Umfelds; nil ohne.</summary>
    function Index: ISymbolIndex;
  end;

  /// <summary>Prüfregeln der Code-Aktionen je Dokument; ohne Anbieter gibt es keine Aktionen zu Treffern.</summary>
  ILspRuleActions = interface
    ['{4D8B2F6A-C1E7-4A39-B05D-9E3C7A1F6B24}']
    /// <summary>Aktionen für AUri; ACancelled (nil = nie) beendet das Warten auf einen fremden Lauf. Nie nil.
    /// </summary>
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): ILspDocumentRuleActions;
  end;

  /// <summary>Antwort von atlas.server.ownership (#1877); der Host fragt die Prüfregeln.</summary>
  ILspOwnershipReport = interface
    ['{08AF5196-3412-4413-90D5-C220EA8A7A51}']
    /// <summary>{ uri, sites: [...] } zu AUri; der Aufrufer übernimmt das Objekt.</summary>
    function Report(const AUri: string): TJSONObject;
  end;

  /// <summary>Text von atlas.server.findingsPrompt (#2570); der Host fragt die Prüfregeln.</summary>
  ILspFindingsPrompt = interface
    ['{E37C5400-D146-4F02-A9CD-7215525CC752}']
    /// <summary>Markdown zu AItems, höchstens ALimit Befunde ausführlich.</summary>
    function Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
    /// <summary>Höchstzahl, wenn die Argumente keine nennen.</summary>
    function DefaultLimit: Integer;
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
