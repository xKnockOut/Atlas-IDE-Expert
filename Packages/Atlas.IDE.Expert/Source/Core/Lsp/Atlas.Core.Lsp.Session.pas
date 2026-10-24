unit Atlas.Core.Lsp.Session;

// LSP-Sitzung des IDE-Plugins (ADR 0006): initialize, Dokumentabgleich und die
// Anfragen, die die IDE über den Code Insight-Manager stellt.
// Abgleich: Vor jeder Anfrage wird der aktuelle Editortext geschickt, beim
// ersten Mal als didOpen, danach als didChange mit dem geänderten Bereich
// (#395, TLspTextChanges), aber nur, wenn er sich geändert hat. Positionen
// sind 0-basiert in UTF-16-Einheiten (Delphi-String-Indizes), wie LSP sie
// erwartet.
// Diagnosen (#398) holt das Plugin selbst (Pull: textDocument/diagnostic und
// workspace/diagnostic); eine Anfrage workspace/diagnostic/refresh des Servers
// zählt RefreshCount hoch.
// Projektgruppe (#648): SetProjects vor Initialize schickt die Projekte als
// workspaceFolders (uri ist die .dproj, aktives Projekt zuerst); danach meldet
// es Änderungen als workspace/didChangeWorkspaceFolders.
// Serverneustart (#393): OpenDocuments der alten Sitzung, Reopen in der neuen
// schickt sie sofort wieder als didOpen.
// Änderungen außerhalb der IDE (#395): FilesChanged meldet sie als
// workspace/didChangeWatchedFiles.
// Projektkontext (#396): SetProjectContexts vor Initialize schickt die
// Kontexte in initializationOptions.projectContexts, danach jeden geänderten
// als atlas/projectContext.
// workspace/applyEdit (#397): Mit OnApplyEdit kündigt die Sitzung applyEdit
// an; die Anfrage geht im Lese-Thread an OnApplyEdit, das später über AReply
// antwortet ({applied, failureReason}). Antwortet der Empfänger nicht (Sitzung
// beendet, Eintrag beim Entladen verworfen), gibt die Sitzung die Id frei
// (Code-Review S-07); nur die erste Antwort zählt.
// Ergebnisfenster (#400): Implementierungen, workspace/symbol sowie Typ- und
// Aufrufhierarchie; der Aufrufer gleicht die Puffer vorher ab.
// Bedienung im Editor (#399): Code-Aktionen, Befehle mit Argumenten,
// onTypeFormatting für Schnellbefehle und ///-Gerüste, selectionRange und
// typeDefinition; auch hier gleicht der Aufrufer vorher ab.
// Formatieren (#43): formatting bzw. rangeFormatting, Abgleich wie oben.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Progress,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Projects.Contract,
  Atlas.Core.InlayHints.Store,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  TLspLocation = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert.</summary>
    Character: Integer;
    /// <summary>Referenzsuche (#1119): sicher oder erschlossen; sonst sicher.</summary>
    Confidence: TAtlasConfidence;
  end;

  /// <summary>Code-Aktion oder Befehl aus textDocument/codeAction (#399).</summary>
  TLspCodeAction = record
    Title: string;
    Kind: string;
    Preferred: Boolean;
    /// <summary>Grund, warum die Aktion gerade nicht geht; leer, wenn sie geht.</summary>
    Disabled: string;
    /// <summary>Erst Edit anwenden, dann Command ausführen (LSP).</summary>
    Edit: TLspWorkspaceEdit;
    /// <summary>Befehl ohne Edit oder nach dem Edit; leer ohne.</summary>
    Command: string;
    /// <summary>Argumente des Befehls als JSON-Array; '[]' ohne.</summary>
    ArgumentsJson: string;
    /// <summary>Kennung aus data.tag, z. B. "uses.remove" (#621); '' ohne.</summary>
    Tag: string;
    /// <summary>Vorschau aus data.preview (#663): vor dem Übernehmen zeigen; '' ohne.</summary>
    Preview: string;
    /// <summary>Regel des behobenen Treffers aus diagnostics[0].code (#909); '' ohne.</summary>
    Rule: string;
    /// <summary>Aus einem Eintrag der Antwort: CodeAction oder Command; False bei anderem.</summary>
    class function FromJson(const AValue: TJSONValue; out AAction: TLspCodeAction): Boolean; static;
  end;

  /// <summary>Teile eines Hovers für den Atlas-Tooltip (#442).</summary>
  TLspHoverParts = record
    Declaration: string;
    UnitName: string;
    Documentation: string;
    Value: string;
    Deprecation: string;
    function Found: Boolean;
    /// <summary>Aus einer Hover-Antwort: das Feld "atlas" des Servers, sonst erster Absatz als Deklaration.</summary>
    class function FromHover(const AHover: TJSONValue): TLspHoverParts; static;
  end;

  /// <summary>Diagnosebericht einer Datei (#398).</summary>
  TLspDiagnosticReport = record
    FileName: string;
    ResultId: string;
    /// <summary>Seit der vorigen Ergebnis-Id unverändert; Problems ist dann leer.</summary>
    Unchanged: Boolean;
    Problems: TArray<TAtlasProblem>;
    /// <summary>Aus einem Bericht des Servers ({kind, resultId, items}); AFileName, wenn er keine uri hat.</summary>
    class function FromJson(const AReport: TJSONObject; const AFileName: string): TLspDiagnosticReport; static;
  end;

  /// <summary>Zähler, den der Lese-Thread erhöht; überlebt die Sitzung, solange der Client ihn hält.</summary>
  ILspSignal = interface
    ['{6B0C1E57-3A44-4E0B-9A63-2F7A5C0D8E11}']
    function Count: Integer;
    procedure Signal;
  end;

  /// <summary>Abgeglichenes Dokument mit dem zuletzt geschickten Text (#393).</summary>
  TLspOpenDocument = record
    FileName: string;
    Text: string;
  end;

  /// <summary>Antwort auf workspace/applyEdit; nur einmal aufrufen.</summary>
  TLspApplyEditReply = reference to procedure(AApplied: Boolean; const AFailureReason: string);
  /// <summary>workspace/applyEdit des Servers (#397); läuft im Lese-Thread. AEdit ist schon gelesen.</summary>
  TLspApplyEditProc = reference to procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply);
  /// <summary>window/showMessage des Servers (#121); läuft im Lese-Thread. AType: 1 Fehler, 2 Warnung,
  /// 3 Information, 4 Protokoll.</summary>
  TLspShowMessageProc = reference to procedure(AType: Integer; const AMessage: string);

  TLspSession = class
  private type
    TDocumentState = record
      FileName: string;
      Version: Integer;
      Text: string;
    end;
  private
    FClient: TLspClient;
    FRefresh: ILspSignal;
    FProgress: ILspProgress;
    FTimeoutMs: Cardinal;
    FDocuments: TDictionary<string, TDocumentState>;
    // Schützt FDocuments samt Reihenfolge der didOpen/didChange (#493): Sync läuft auch aus
    // Hintergrund-Threads (Zeitlimit für Quellen).
    FDocLock: TObject;
    FInitialized: Boolean;
    FProjects: TArray<string>;
    /// <summary>Projektkontexte für initialize (#396).</summary>
    FContexts: TArray<TAtlasProjectContext>;
    /// <summary>Zuletzt gemeldeter Schlüssel je Projekt (#396).</summary>
    FSentContexts: TDictionary<string, string>;
    FOnApplyEdit: TLspApplyEditProc;
    FOnShowMessage: TLspShowMessageProc;
    FServerSettings: string;
    FServerVersion: string;
    procedure SyncLocked(const AFileName, AText: string);
    procedure CloseLocked(const AFileName: string);
    function PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
    /// <summary>capabilities für initialize; AApplyEdit: workspace.applyEdit ankündigen.</summary>
    class function ClientCapabilities(AApplyEdit: Boolean): TJSONObject; static;
    /// <summary>Lese-Thread-Empfänger setzen; fängt nur Zähler, Client und Callbacks ein, nie Self.</summary>
    procedure AttachClientHandlers;
  public
    /// <summary>AClient gehört weiter dem Aufrufer.</summary>
    constructor Create(AClient: TLspClient; ATimeoutMs: Cardinal = 3000);
    destructor Destroy; override;
    class function PathToUri(const APath: string): string; static;
    class function UriToPath(const AUri: string): string; static;
    /// <summary>Text aus contents einer Hover-Antwort: String, MarkupContent oder MarkedString-Liste.</summary>
    class function HoverText(const AHover: TJSONValue): string; static;
    /// <summary>Zeichenindex (0-basiert) zur Editorspalte (1-basiert); Tabs springen zur nächsten Tabulatorposition.</summary>
    class function ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer; static;
    /// <summary>workspaceFolders-Einträge zu Projektdateien: uri der Datei, Name ohne Endung (#648).</summary>
    class function ProjectFolders(const AProjects: TArray<string>): TJSONArray; static;
    /// <summary>Hinzugekommene und weggefallene Projekte, Groß- und Kleinschreibung egal (#648).</summary>
    class procedure ProjectChanges(const AOld, ANew: TArray<string>; out AAdded, ARemoved: TArray<string>); static;
    /// <summary>Projekte der Gruppe, aktives zuerst. Vor Initialize nur gemerkt, danach als
    /// didChangeWorkspaceFolders gemeldet, falls sich etwas geändert hat (#648).</summary>
    procedure SetProjects(const AProjects: TArray<string>);
    /// <summary>Projektkontexte aus der IDE (#396). Vor Initialize nur gemerkt, danach jeder neue oder
    /// geänderte als atlas/projectContext gemeldet. Vor SetProjects aufrufen, damit ein neues Projekt
    /// gleich mit seinem Kontext geladen wird. Ergebnis: die neu gemeldeten oder für initialize
    /// gemerkten Kontexte (fürs Diagnoseprotokoll).</summary>
    function SetProjectContexts(const AContexts: TArray<TAtlasProjectContext>): TArray<TAtlasProjectContext>;
    /// <summary>Parameternamen (InlayHintKind 2) und Endmarken („// Name“ ohne kind, #620, EndLabel) in den Zeilen
    /// AFromLine..AToLine (0-basiert) ohne Abgleich: Sync vorher (#401). Namen ohne abschließenden Doppelpunkt,
    /// Endmarken ohne "//".</summary>
    function InlayHints(const AFileName: string; AFromLine, AToLine: Integer;
      ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>; overload;
    /// <summary>Wie oben; AEndMarkerMinLines &gt; 0 setzt die Mindestlänge der Endmarken für diese Anfrage
    /// (#620, editor.blockEndLabels.minLines). Endmarken tragen den Blockanfang aus data.blockStart;
    /// Include-Symbole hinter {$I} (#860) kommen als DefineHint mit den Symbolen aus data.includeDefines.</summary>
    function InlayHints(const AFileName: string; AFromLine, AToLine, AEndMarkerMinLines: Integer;
      ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>; overload;
    /// <summary>Bezeichner für Werte beim Debuggen (#508, textDocument/inlineValue) in den Zeilen
    /// AFromLine..AToLine (0-basiert), Halt an AStoppedLine; ohne Abgleich: Sync vorher im Hauptthread.
    /// Threadsicher wie Completion.</summary>
    function InlineValues(const AFileName: string; AFromLine, AToLine, AStoppedLine: Integer;
      ATimeoutMs: Cardinal): TAtlasInlineValueRefs;
    /// <summary>Bezeichner aus der Antwort auf textDocument/inlineValue; nur InlineValueVariableLookup mit
    /// variableName.</summary>
    class function InlineValueRefsOf(const AResponse: TJSONValue): TAtlasInlineValueRefs; static;
    /// <summary>Wirksame Compiler-Schalter an ALine/ACharacter (0-basiert, #558, atlas/compilerSwitches); ohne
    /// Abgleich: Sync vorher im Hauptthread. Threadsicher wie Completion. Gehört dem Aufrufer; nil ohne Antwort.
    /// </summary>
    function CompilerSwitches(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>atlas/debugUnavailable (#840): Schalter D, L, O, Routine, Lebensdauer von AName und Korrekturen
    /// am Halt in ALine (0-basiert); gehört dem Aufrufer.</summary>
    function DebugUnavailable(const AFileName: string; ALine: Integer; const AName: string;
      ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>atlas/expressionCompletion (#538): Vorschläge für AExpression im Gültigkeitsbereich der Zeile
    /// ALine (0-basiert) von AFileName, Schreibmarke ACharacter im Ausdruck. Ohne Abgleich; gehört dem Aufrufer.
    /// </summary>
    function ExpressionCompletion(const AFileName: string; ALine: Integer; const AExpression: string;
      ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>atlas/accessChains (#865): Zugriffsketten der Anweisungen in ALine (0-basiert) von AFileName für
    /// einen Prozess mit APointerSize. Ohne Abgleich: Sync vorher im Hauptthread. Found = False ohne Antwort.
    /// </summary>
    function AccessChains(const AFileName: string; ALine, APointerSize: Integer; ATimeoutMs: Cardinal): TAtlasAvChains;
    procedure Initialize;
    /// <summary>Parameter von initialize (#396, #397, #408, #648, #652). AApplyEdit: workspace.applyEdit
    /// ankündigen. Gehört dem Aufrufer.</summary>
    class function InitializeParams(const AProjects: TArray<string>; const AServerSettings: string;
      const AContexts: TArray<TAtlasProjectContext>; AApplyEdit: Boolean): TJSONObject; static;
    /// <summary>Antwort auf workspace/applyEdit ({applied, failureReason}). Gehört dem Aufrufer.</summary>
    class function ApplyEditAnswer(AApplied: Boolean; const AFailureReason: string): TJSONObject; static;
    /// <summary>Vor Initialize setzen (#397): workspace/applyEdit des Servers annehmen.</summary>
    property OnApplyEdit: TLspApplyEditProc read FOnApplyEdit write FOnApplyEdit;
    /// <summary>Vor Initialize setzen (#121): Meldungen des Servers für den Benutzer.</summary>
    property OnShowMessage: TLspShowMessageProc read FOnShowMessage write FOnShowMessage;
    /// <summary>type und message aus den Parametern von window/showMessage; False ohne Text.</summary>
    class function ShowMessageParams(const AParams: TJSONValue; out AType: Integer;
      out AMessage: string): Boolean; static;
    /// <summary>{"settings": {"atlas": AJson}} für initializationOptions und didChangeConfiguration (#652);
    /// leeres oder ungültiges AJson ergibt ein leeres atlas-Objekt.</summary>
    class function SettingsParams(const AJson: string): TJSONObject; static;
    /// <summary>Einstellungen der Atlas-Optionen im Format von atlas.json (#652), vor Initialize setzen;
    /// gehen als initializationOptions mit, damit schon der erste Indexaufbau sie nutzt.</summary>
    property ServerSettings: string read FServerSettings write FServerSettings;
    /// <summary>Schickt AText, falls neu oder geändert.</summary>
    procedure Sync(const AFileName, AText: string);
    function Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
    /// <summary>Hover in Teilen (#442).</summary>
    function HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
    /// <summary>Hover mit allen Teilen für den Tooltip (#588): Art, Fundort, Links, Vererbungskette.</summary>
    function HoverData(const AFileName, AText: string; ALine, ACharacter: Integer): TAtlasHoverData;
    /// <summary>Hover an einem Fundort ohne Abgleich: Der Server liest nicht geöffnete Dateien selbst (#588).</summary>
    function HoverDataAt(const AFileName: string; ALine, ACharacter: Integer): TAtlasHoverData;
    /// <summary>Verwendungen des Symbols am Fundort ohne die Deklaration (textDocument/references).</summary>
    function References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>Implementierungen des Symbols (textDocument/implementation, #400).</summary>
    function Implementations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>Projektweite Symbolsuche (workspace/symbol, #400); unscharf filtert der Server.</summary>
    function WorkspaceSymbols(const AQuery: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
    /// <summary>Gliederung einer Datei (textDocument/documentSymbol, #503), flach in Dateireihenfolge.</summary>
    function DocumentSymbols(const AFileName: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
    /// <summary>Unveränderte Antwort von textDocument/documentSymbol samt Atlas-Angaben (Gliederungsfenster,
    /// #537); der Aufrufer gibt sie frei, nil ohne Antwort.</summary>
    function DocumentSymbolTree(const AFileName: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>DocumentSymbol[] (mit children; Container = Name des Elternsymbols) oder SymbolInformation[]
    /// einer documentSymbol-Antwort, flach; AFileName für Symbole ohne Ort.</summary>
    class function SymbolsOfDocument(const AResponse: TJSONValue; const AFileName: string): TArray<TAtlasSymbol>;
      static;
    /// <summary>Wurzeln einer Hierarchie am Fundort (prepareCallHierarchy bzw. prepareTypeHierarchy, #400).</summary>
    function PrepareHierarchy(ADirection: TAtlasHierarchyDirection; const AFileName: string; ALine,
      ACharacter: Integer): TArray<TAtlasHierarchyItem>;
    /// <summary>Nächste Ebene unter AItem in Richtung ADirection (#400).</summary>
    function HierarchyChildren(ADirection: TAtlasHierarchyDirection;
      const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
    /// <summary>Auswirkungen des Symbols am Fundort bis zur Tiefe ADepth (atlas/impact, #1120); ohne Symbol leer.
    /// </summary>
    function Impact(const AFileName: string; ALine, ACharacter, ADepth: Integer): TAtlasImpact;
    /// <summary>Antwort von atlas/impact (#1120); ohne Objekt leer (kein Symbol am Cursor).</summary>
    class function ImpactFromJson(const AValue: TJSONValue): TAtlasImpact; static;
    /// <summary>Woher kommt bzw. wohin geht der Wert des Symbols an der Stelle (atlas/dataFlow, #690).</summary>
    function DataFlow(const ARequest: TAtlasDataFlowRequest): TAtlasDataFlowResult;
    /// <summary>Code-Aktionen für ARange (textDocument/codeAction, #399), Reihenfolge des Servers.</summary>
    function CodeActions(const AFileName: string; const ARange: TLspRange): TArray<TLspCodeAction>; overload;
    /// <summary>Wie oben mit eigener Wartezeit, etwa für die Glühbirne der Zeilenleiste (#768), die den Editor
    /// nicht bremsen darf.</summary>
    function CodeActions(const AFileName: string; const ARange: TLspRange;
      ATimeoutMs: Cardinal): TArray<TLspCodeAction>; overload;
    /// <summary>workspace/executeCommand mit Argumenten (JSON-Array, '' = keine, #399); ELspClientError bei
    /// Fehler oder Zeitlimit. Ergebnis gehört dem Aufrufer.</summary>
    function RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>textDocument/onTypeFormatting (#399): Schnellbefehle nach Enter (ACh = #10) und
    /// ///-Gerüste (ACh = '/'). Leer, wenn der Server nichts ändert.</summary>
    function OnTypeFormatting(const AFileName: string; ALine, ACharacter: Integer; const ACh: string;
      ATabSize: Integer; AInsertSpaces: Boolean; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
    /// <summary>textDocument/formatting (#43): Änderungen für die ganze Datei; leer, wenn nichts zu tun ist.
    /// ELspClientError bei Fehler oder Zeitlimit.</summary>
    function Formatting(const AFileName: string; ATabSize: Integer; AInsertSpaces: Boolean;
      ATimeoutMs: Cardinal): TArray<TLspTextEdit>; overload;
    /// <summary>textDocument/rangeFormatting (#43): nur die Zeilen von ARange.</summary>
    function Formatting(const AFileName: string; const ARange: TLspRange; ATabSize: Integer; AInsertSpaces: Boolean;
      ATimeoutMs: Cardinal): TArray<TLspTextEdit>; overload;
    /// <summary>Umgebende Bereiche am Fundort, innen zuerst (textDocument/selectionRange, #399).</summary>
    function SelectionRanges(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspRange>;
    /// <summary>textDocument/linkedEditingRange nur für lokale Bezeichner ("atlasLocals", #658): Antwort des
    /// Servers (Aufrufer gibt frei), nil ohne Antwort. Threadsicher wie die übrigen Anfragen.</summary>
    function LinkedLocals(const AFileName: string; ALine, ACharacter: Integer): TJSONValue;
    /// <summary>Typ des Symbols (textDocument/typeDefinition, #399).</summary>
    function TypeDefinition(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert); Umkehrung von ColumnToIndex.</summary>
    class function IndexToColumn(const ALine: string; AIndex, ATabWidth: Integer): Integer; static;
    /// <summary>Location, Location[] oder LocationLink[] einer Antwort (#400).</summary>
    class function LocationsOf(const AResponse: TJSONValue): TArray<TLspLocation>; static;
    function Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
      out ALocation: TLspLocation): Boolean;
    /// <summary>textDocument/definition ohne Abgleich (#505): alle Ziele; Sync vorher.</summary>
    function Definitions(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>textDocument/declaration ohne Abgleich (#505): alle Ziele; Sync vorher.</summary>
    function Declarations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>
    /// textDocument/completion ohne Abgleich: Sync vorher im Hauptthread. Darf aus einem
    /// anderen Thread kommen, solange die Sitzung lebt. Liefert die Antwort (CompletionList,
    /// CompletionItem[] oder nil); der Aufrufer gibt sie frei.
    /// </summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
      overload;
    /// <summary>Wie oben, gestaffelt (#616): AOnPartial bekommt Teilergebnisse (CompletionItem[]) im
    /// Lese-Thread, bevor die Antwort den Rest bringt. ATrigger: Zeichen, nach dem automatisch geöffnet wurde
    /// (context.triggerCharacter, #448); '' bei Strg+Leer.</summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      const ATrigger: string; const AOnPartial: TLspPartialProc): TJSONValue; overload;
    /// <summary>textDocument/signatureHelp ohne Abgleich, wie Completion.</summary>
    function SignatureHelp(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>textDocument/prepareRename (#397): Lässt sich hier umbenennen? APlaceholder ist der
    /// bisherige Name (aus placeholder, sonst aus dem Bereich in AText).</summary>
    function PrepareRename(const AFileName, AText: string; ALine, ACharacter: Integer;
      out APlaceholder: string): Boolean;
    /// <summary>textDocument/rename (#397): WorkspaceEdit des Servers, gehört dem Aufrufer; nil ohne.</summary>
    function Rename(const AFileName: string; ALine, ACharacter: Integer; const ANewName: string;
      ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>completionItem/resolve für AItem (wird übernommen); threadsicher wie Completion.</summary>
    function ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Benachrichtigung ohne Antwort, z. B. atlas/compileStarted (#527); übernimmt AParams.</summary>
    procedure Notify(const AMethod: string; AParams: TJSONObject);
    /// <summary>Diagnosen einer Datei (textDocument/diagnostic) ohne Abgleich; threadsicher wie Completion.</summary>
    function DocumentDiagnostics(const AFileName, APreviousResultId: string; ATimeoutMs: Cardinal): TLspDiagnosticReport;
    /// <summary>Diagnosen aller Projektdateien außer den geöffneten (workspace/diagnostic, Long-Polling);
    /// APrevious mit FileName und ResultId der bekannten Stände. Threadsicher wie Completion.</summary>
    function WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
      ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>;
    /// <summary>didClose für eine abgeglichene Datei; danach liest der Server sie wieder von der Platte.</summary>
    procedure Close(const AFileName: string);
    /// <summary>didSave für eine abgeglichene Datei: Der Server prüft dann mit dcc (compiler.onSave, #40).</summary>
    procedure Saved(const AFileName: string);
    /// <summary>Abgeglichene Dateien (Hauptthread).</summary>
    function SyncedFiles: TArray<string>;
    /// <summary>Zuletzt geschickter Text einer Datei (Hauptthread).</summary>
    function SyncedText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Alle abgeglichenen Dokumente mit Text, etwa um sie nach einem Serverneustart
    /// erneut zu öffnen (#393). Hauptthread.</summary>
    function OpenDocuments: TArray<TLspOpenDocument>;
    /// <summary>Öffnet die Dokumente einer früheren Sitzung (didOpen, Version 1); schon
    /// abgeglichene bleiben unverändert. Erst nach Initialize aufrufen (#393).</summary>
    procedure Reopen(const ADocuments: TArray<TLspOpenDocument>);
    /// <summary>workspace/didChangeWatchedFiles für Änderungen außerhalb der IDE (#395).
    /// Geänderte Dateien, die gerade abgeglichen sind, entfallen: Für sie gilt der Editortext.</summary>
    procedure FilesChanged(const AChanges: TArray<TAtlasFileChange>);
    /// <summary>Anzahl der workspace/diagnostic/refresh-Anfragen des Servers.</summary>
    function RefreshCount: Integer;
    /// <summary>Laufende Indizierung o. Ä. des Servers ("Index 45 %"); '' ohne (#492).</summary>
    function ProgressText: string;
    /// <summary>Statusleiste: "Atlas indiziert … (45 %)"; '' ohne laufenden Vorgang (#492).</summary>
    function IndexingText: string;
    /// <summary>Läuft eine Indizierung? APercent = Fortschritt, -1 = unbekannt (#591).</summary>
    function Indexing(out APercent: Integer): Boolean;
    /// <summary>Beobachter für $/progress, im Lese-Thread (#591).</summary>
    procedure SetOnProgress(const AProc: TProc);
    /// <summary>Version aus serverInfo der Antwort auf initialize; '' = unbekannt (#591).</summary>
    property ServerVersion: string read FServerVersion;
    /// <summary>workspace/executeCommand; Ergebnis gehört dem Aufrufer (nil bei Fehler oder Zeitlimit).</summary>
    function ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue; overload;
    /// <summary>Wie oben mit Argumenten; übernimmt AArguments.</summary>
    function ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
      overload;
    property Initialized: Boolean read FInitialized;
  end;

  /// <summary>Laufende Sitzung oder nil; startet nie einen Server (Code-Review A-01). Aus beliebigem Thread
  /// aufgerufen, meist im Zeitlimit-Arbeiter. Steht hier, damit Anbieter verschiedener Features sie ohne
  /// gegenseitigen Import teilen (Code-Review A-10).</summary>
  TAtlasSessionFunc = reference to function: TLspSession;

implementation

uses
  System.SyncObjs,
  Atlas.Text.Uris;

type
  TLspSignal = class(TInterfacedObject, ILspSignal)
  private
    FCount: Integer;
  public
    function Count: Integer;
    procedure Signal;
  end;

{ TLspSignal }

function TLspSignal.Count: Integer;
begin
  Result := TInterlocked.CompareExchange(FCount, 0, 0);
end;

procedure TLspSignal.Signal;
begin
  TInterlocked.Increment(FCount);
end;

type
  /// <summary>Id einer Serveranfrage, auf die später geantwortet wird (#397). Wer zuerst Take ruft, antwortet;
  /// kommt keine Antwort, gibt der letzte Verweis die Id frei (Code-Review S-07).</summary>
  ILspPendingId = interface
    function Take: TJSONValue;
  end;

  TLspPendingId = class(TInterfacedObject, ILspPendingId)
  private
    FId: TJSONValue;
  public
    constructor Create(AId: TJSONValue);
    destructor Destroy; override;
    function Take: TJSONValue;
  end;

{ TLspPendingId }

constructor TLspPendingId.Create(AId: TJSONValue);
begin
  inherited Create;
  FId := AId;
end;

destructor TLspPendingId.Destroy;
begin
  FId.Free;
  inherited Destroy;
end;

function TLspPendingId.Take: TJSONValue;
begin
  Result := TInterlocked.Exchange<TJSONValue>(FId, nil);
end;

{ TLspSession }

constructor TLspSession.Create(AClient: TLspClient; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FClient := AClient;
  FTimeoutMs := ATimeoutMs;
  FDocuments := TDictionary<string, TDocumentState>.Create;
  FSentContexts := TDictionary<string, string>.Create;
  FDocLock := TObject.Create;
  FRefresh := TLspSignal.Create;
  FProgress := TLspProgress.Create;
end;

destructor TLspSession.Destroy;
begin
  FSentContexts.Free;
  FDocuments.Free;
  FDocLock.Free;
  inherited;
end;

class function TLspSession.PathToUri(const APath: string): string;
begin
  // Wie der Server (ADR 0012): c:\x → file:///c%3A/x; \\server\share → file://server/share
  Result := TTextUris.FromPath(APath);
end;

class function TLspSession.UriToPath(const AUri: string): string;
begin
  // file:///c:/x → c:\x; file://server/share → \\server\share; andere Schemata → ''
  Result := StringReplace(TTextUris.ToPath(AUri), '/', '\', [rfReplaceAll]);
end;

class function TLspSession.HoverText(const AHover: TJSONValue): string;
var
  Contents: TJSONValue;
  Item: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
    Exit;
  Contents := TJSONObject(AHover).GetValue('contents');
  if Contents is TJSONString then
    Result := TJSONString(Contents).Value
  else if Contents is TJSONObject then
    Result := TJSONObject(Contents).GetValue<string>('value', '')
  else if Contents is TJSONArray then
    for Item in TJSONArray(Contents) do
    begin
      if Result <> '' then
        Result := Result + sLineBreak;
      if Item is TJSONString then
        Result := Result + TJSONString(Item).Value
      else if Item is TJSONObject then
        Result := Result + TJSONObject(Item).GetValue<string>('value', '');
    end;
end;

class function TLspSession.ColumnToIndex(const ALine: string; AColumn, ATabWidth: Integer): Integer;
var
  Visual: Integer;
begin
  // Spalte 1 = erstes Zeichen. Tabs springen zur nächsten Tabulatorposition.
  Result := 0;
  Visual := 1;
  while (Result < Length(ALine)) and (Visual < AColumn) do
  begin
    if ALine[Result + 1] = #9 then
      Visual := ((Visual - 1) div ATabWidth + 1) * ATabWidth + 1
    else
      Inc(Visual);
    Inc(Result);
  end;
end;

class function TLspSession.ShowMessageParams(const AParams: TJSONValue; out AType: Integer;
  out AMessage: string): Boolean;
begin
  AType := 3;
  AMessage := '';
  if not (AParams is TJSONObject) then
    Exit(False);
  AMessage := TJSONObject(AParams).GetValue<string>('message', '');
  AType := TJSONObject(AParams).GetValue<Integer>('type', 3);
  Result := AMessage <> '';
end;

class function TLspSession.ClientCapabilities(AApplyEdit: Boolean): TJSONObject;
var
  TextDocument, Hover: TJSONObject;
  Formats: TJSONArray;
begin
  Formats := TJSONArray.Create;
  Formats.Add('plaintext');
  Hover := TJSONObject.Create;
  Hover.AddPair('contentFormat', Formats);
  TextDocument := TJSONObject.Create;
  TextDocument.AddPair('hover', Hover);
  // Dokumentation der Vervollständigung als Klartext (#408). Snippets setzt das Plugin selbst mit Platzhalter-Modus
  // ein (#51); ob sie in der Liste erscheinen, regelt completion.snippets im Plugin.
  TextDocument.AddPair('completion', TJSONObject.Create(TJSONPair.Create('completionItem',
    TJSONObject.Create.AddPair('snippetSupport', TJSONBool.Create(True))
      .AddPair('documentationFormat', TJSONArray.Create.Add('plaintext')))));
  // Diagnosen holt das Plugin selbst (#398); der Server bittet per refresh um neues Holen.
  TextDocument.AddPair('diagnostic', TJSONObject.Create.AddPair('dynamicRegistration', TJSONBool.Create(False))
    .AddPair('relatedDocumentSupport', TJSONBool.Create(False)));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TextDocument);
  Result.AddPair('workspace', TJSONObject.Create(TJSONPair.Create('diagnostics',
    TJSONObject.Create(TJSONPair.Create('refreshSupport', TJSONBool.Create(True)))))
    .AddPair('workspaceFolders', TJSONBool.Create(True))
    .AddPair('applyEdit', TJSONBool.Create(AApplyEdit)));
end;

class function TLspSession.InitializeParams(const AProjects: TArray<string>; const AServerSettings: string;
  const AContexts: TArray<TAtlasProjectContext>; AApplyEdit: Boolean): TJSONObject;
var
  Options: TJSONObject;
  Contexts: TJSONArray;
  Context: TAtlasProjectContext;
begin
  Result := TJSONObject.Create;
  Result.AddPair('processId', TJSONNull.Create);
  Result.AddPair('rootUri', TJSONNull.Create);
  Result.AddPair('clientInfo', TJSONObject.Create(TJSONPair.Create('name', 'Atlas IDE Expert')));
  Result.AddPair('capabilities', ClientCapabilities(AApplyEdit));
  if Length(AProjects) > 0 then
    Result.AddPair('workspaceFolders', ProjectFolders(AProjects));
  // Einstellungen der Atlas-Optionen (#652) und Projektkontexte vor dem ersten Laden der Projekte, sonst
  // indiziert der Server sie zweimal (#396).
  Options := nil;
  if AServerSettings <> '' then
    Options := SettingsParams(AServerSettings);
  if Length(AContexts) > 0 then
  begin
    Contexts := TJSONArray.Create;
    for Context in AContexts do
      Contexts.AddElement(Context.ToJson);
    if Options = nil then
      Options := TJSONObject.Create;
    Options.AddPair('projectContexts', Contexts);
  end;
  if Options <> nil then
    Result.AddPair('initializationOptions', Options);
end;

class function TLspSession.ApplyEditAnswer(AApplied: Boolean; const AFailureReason: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('applied', TJSONBool.Create(AApplied));
  if AFailureReason <> '' then
    Result.AddPair('failureReason', AFailureReason);
end;

procedure TLspSession.AttachClientHandlers;
var
  Refresh: ILspSignal;
  Progress: ILspProgress;
  ApplyEdit: TLspApplyEditProc;
  ShowMessageProc: TLspShowMessageProc;
  Client: TLspClient;
begin
  // Nur den Zähler einfangen, nicht die Sitzung: Der Lese-Thread kann die Sitzung überleben.
  Refresh := FRefresh;
  Progress := FProgress;
  ShowMessageProc := FOnShowMessage;
  FClient.OnServerMessage :=
    procedure(const AMethod: string; const AParams: TJSONValue)
    var
      MessageType: Integer;
      Text: string;
    begin
      if AMethod = 'workspace/diagnostic/refresh' then
        Refresh.Signal
      else if AMethod = '$/progress' then
        Progress.Handle(AParams)
      else if (AMethod = 'window/showMessage') and Assigned(ShowMessageProc) and
        ShowMessageParams(AParams, MessageType, Text) then
        ShowMessageProc(MessageType, Text);
    end;
  // Wie oben: Der Lese-Thread kennt nur Client und Empfänger, nicht die Sitzung.
  ApplyEdit := FOnApplyEdit;
  Client := FClient;
  if Assigned(ApplyEdit) then
    FClient.OnServerRequest :=
      function(const AMethod: string; const AParams: TJSONValue; AId: TJSONValue): Boolean
      var
        Edit: TLspWorkspaceEdit;
        Value: TJSONValue;
        Pending: ILspPendingId;
      begin
        Result := AMethod = 'workspace/applyEdit';
        if not Result then
          Exit;
        Value := nil;
        if AParams is TJSONObject then
          Value := TJSONObject(AParams).GetValue('edit');
        Edit := TLspWorkspaceEdit.FromJson(Value);
        // Ab hier gehört AId der Sitzung; antwortet niemand, gibt Pending sie frei (S-07).
        Pending := TLspPendingId.Create(AId);
        try
          ApplyEdit(Edit,
            procedure(AApplied: Boolean; const AFailureReason: string)
            var
              Id: TJSONValue;
            begin
              // Nur die erste Antwort zählt.
              Id := Pending.Take;
              if Id = nil then
                Exit;
              Client.Respond(Id, ApplyEditAnswer(AApplied, AFailureReason));
            end);
        except
          // Nicht angenommen: Der Client antwortet mit null und gibt seine Id selbst frei.
          Pending.Take;
          raise;
        end;
      end;
end;

procedure TLspSession.Initialize;
var
  Params: TJSONObject;
  Context: TAtlasProjectContext;
  Response: TJSONValue;
begin
  Params := InitializeParams(FProjects, FServerSettings, FContexts, Assigned(FOnApplyEdit));
  // Gesendete Kontexte merken: SetProjectContexts schickt danach nur neue oder geänderte (#396).
  for Context in FContexts do
    FSentContexts.AddOrSetValue(AnsiUpperCase(Context.Project), Context.Key);
  // Empfänger vor initialize setzen: Der Server darf gleich danach Nachrichten schicken.
  AttachClientHandlers;
  // Ohne Arbeitsbereich leitet der Server ihn aus den geöffneten Dateien ab, ebenso für Dateien
  // außerhalb der gemeldeten Projekte.
  Response := FClient.Request('initialize', Params, 15000);
  try
    if Response is TJSONObject then
      FServerVersion := TJSONObject(Response).GetValue<string>('serverInfo.version', '');
  finally
    Response.Free;
  end;
  FClient.Notify('initialized', TJSONObject.Create);
  FInitialized := True;
end;

procedure TLspSession.Sync(const AFileName, AText: string);
begin
  TMonitor.Enter(FDocLock);
  try
    SyncLocked(AFileName, AText);
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

procedure TLspSession.SyncLocked(const AFileName, AText: string);
var
  State: TDocumentState;
  Key: string;
  Params, Document, Change: TJSONObject;
  Changes: TJSONArray;
  Edit: TLspTextChange;
begin
  Key := AnsiLowerCase(AFileName);
  Document := TJSONObject.Create;
  Document.AddPair('uri', PathToUri(AFileName));
  if not FDocuments.TryGetValue(Key, State) then
  begin
    State.FileName := AFileName;
    State.Version := 1;
    State.Text := AText;
    FDocuments.Add(Key, State);
    Document.AddPair('languageId', 'delphi');
    Document.AddPair('version', TJSONNumber.Create(State.Version));
    Document.AddPair('text', AText);
    FClient.Notify('textDocument/didOpen', TJSONObject.Create(TJSONPair.Create('textDocument', Document)));
    Exit;
  end;
  if State.Text = AText then
  begin
    Document.Free;
    Exit;
  end;
  // Nur der geänderte Bereich (#395); der Server meldet textDocumentSync.change = Incremental.
  Edit := TLspTextChanges.Between(State.Text, AText);
  Inc(State.Version);
  State.Text := AText;
  FDocuments[Key] := State;
  Document.AddPair('version', TJSONNumber.Create(State.Version));
  Change := TJSONObject.Create;
  Change.AddPair('range', TJSONObject.Create
    .AddPair('start', TJSONObject.Create
      .AddPair('line', TJSONNumber.Create(Edit.StartPos.Line))
      .AddPair('character', TJSONNumber.Create(Edit.StartPos.Character)))
    .AddPair('end', TJSONObject.Create
      .AddPair('line', TJSONNumber.Create(Edit.EndPos.Line))
      .AddPair('character', TJSONNumber.Create(Edit.EndPos.Character))));
  Change.AddPair('text', Edit.Text);
  Changes := TJSONArray.Create;
  Changes.AddElement(Change);
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', Document);
  Params.AddPair('contentChanges', Changes);
  FClient.Notify('textDocument/didChange', Params);
end;

function TLspSession.PositionParams(const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
var
  Position: TJSONObject;
begin
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ALine));
  Position.AddPair('character', TJSONNumber.Create(ACharacter));
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Result.AddPair('position', Position);
end;

function TLspSession.Hover(const AFileName, AText: string; ALine, ACharacter: Integer): string;
var
  Response: TJSONValue;
begin
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := HoverText(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.HoverParts(const AFileName, AText: string; ALine, ACharacter: Integer): TLspHoverParts;
var
  Response: TJSONValue;
begin
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := TLspHoverParts.FromHover(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.HoverData(const AFileName, AText: string; ALine, ACharacter: Integer): TAtlasHoverData;
begin
  Sync(AFileName, AText);
  Result := HoverDataAt(AFileName, ALine, ACharacter);
end;

function TLspSession.HoverDataAt(const AFileName: string; ALine, ACharacter: Integer): TAtlasHoverData;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := TAtlasHoverData.FromHover(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Params: TJSONObject;
  Context: TJSONObject;
  Response, Item: TJSONValue;
  Location: TLspLocation;
begin
  Result := nil;
  Params := PositionParams(AFileName, ALine, ACharacter);
  Context := TJSONObject.Create;
  Context.AddPair('includeDeclaration', TJSONBool.Create(False));
  Params.AddPair('context', Context);
  // Die Suche geht über das ganze Projekt; dafür mehr Zeit als für einen Hover.
  Response := FClient.Request('textDocument/references', Params, FTimeoutMs * 10);
  try
    if Response is TJSONArray then
      for Item in TJSONArray(Response) do
        if Item is TJSONObject then
        begin
          Location.FileName := UriToPath(TJSONObject(Item).GetValue<string>('uri', ''));
          Location.Line := TJSONObject(Item).GetValue<Integer>('range.start.line', 0);
          Location.Character := TJSONObject(Item).GetValue<Integer>('range.start.character', 0);
          Location.Confidence := TAtlasConfidence.FromJson(Item);
          if Location.FileName <> '' then
            Result := Result + [Location];
        end;
  finally
    Response.Free;
  end;
end;

class function TLspSession.LocationsOf(const AResponse: TJSONValue): TArray<TLspLocation>;

  procedure Add(const AItem: TJSONValue);
  var
    Location: TLspLocation;
    Uri, Prefix: string;
  begin
    if not (AItem is TJSONObject) then
      Exit;
    // LocationLink: targetUri und targetSelectionRange; Location: uri und range.
    Prefix := 'range';
    if TJSONObject(AItem).TryGetValue<string>('targetUri', Uri) then
      Prefix := 'targetSelectionRange'
    else
      Uri := TJSONObject(AItem).GetValue<string>('uri', '');
    Location.FileName := UriToPath(Uri);
    Location.Line := TJSONObject(AItem).GetValue<Integer>(Prefix + '.start.line', 0);
    Location.Character := TJSONObject(AItem).GetValue<Integer>(Prefix + '.start.character', 0);
    Location.Confidence := TAtlasConfidence.FromJson(AItem);
    if Location.FileName <> '' then
      Result := Result + [Location];
  end;

var
  Item: TJSONValue;
begin
  Result := nil;
  if AResponse is TJSONArray then
    for Item in TJSONArray(AResponse) do
      Add(Item)
  else
    Add(AResponse);
end;

function TLspSession.Implementations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/implementation', PositionParams(AFileName, ALine, ACharacter),
    FTimeoutMs * 10);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

function RangeToJson(const ARange: TLspRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ARange.StartPos.Line))
    .AddPair('character', TJSONNumber.Create(ARange.StartPos.Character)));
  Result.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ARange.EndPos.Line))
    .AddPair('character', TJSONNumber.Create(ARange.EndPos.Character)));
end;

function RangeOf(const AValue: TJSONValue; out ARange: TLspRange): Boolean;
var
  Range: TJSONObject;
begin
  ARange := Default(TLspRange);
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<TJSONObject>('range', Range) and
    Range.TryGetValue<Integer>('start.line', ARange.StartPos.Line) and
    Range.TryGetValue<Integer>('start.character', ARange.StartPos.Character) and
    Range.TryGetValue<Integer>('end.line', ARange.EndPos.Line) and
    Range.TryGetValue<Integer>('end.character', ARange.EndPos.Character);
end;

{ TLspCodeAction }

class function TLspCodeAction.FromJson(const AValue: TJSONValue; out AAction: TLspCodeAction): Boolean;
var
  Item, Command: TJSONObject;
  Arguments: TJSONArray;
  Value: TJSONValue;
begin
  AAction := Default(TLspCodeAction);
  AAction.ArgumentsJson := '[]';
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<string>('title', AAction.Title);
  if not Result then
    Exit;
  Item := TJSONObject(AValue);
  // Ein Command hat "command" als String, eine CodeAction als Objekt.
  Value := Item.GetValue('command');
  if Value is TJSONString then
    Command := Item
  else if Value is TJSONObject then
    Command := TJSONObject(Value)
  else
    Command := nil;
  if Command <> nil then
  begin
    AAction.Command := Command.GetValue<string>('command', '');
    if Command.TryGetValue<TJSONArray>('arguments', Arguments) then
      AAction.ArgumentsJson := Arguments.ToJSON;
  end;
  if Command = Item then
    Exit;
  AAction.Kind := Item.GetValue<string>('kind', '');
  AAction.Preferred := Item.GetValue<Boolean>('isPreferred', False);
  AAction.Disabled := Item.GetValue<string>('disabled.reason', '');
  AAction.Edit := TLspWorkspaceEdit.FromJson(Item.GetValue('edit'));
  AAction.Tag := Item.GetValue<string>('data.tag', '');
  AAction.Preview := Item.GetValue<string>('data.preview', '');
  if Item.TryGetValue<TJSONArray>('diagnostics', Arguments) and (Arguments.Count > 0) and
    (Arguments.Items[0] is TJSONObject) then
    AAction.Rule := TJSONObject(Arguments.Items[0]).GetValue<string>('code', '');
end;

function TLspSession.CodeActions(const AFileName: string; const ARange: TLspRange): TArray<TLspCodeAction>;
begin
  Result := CodeActions(AFileName, ARange, FTimeoutMs * 2);
end;

function TLspSession.CodeActions(const AFileName: string; const ARange: TLspRange;
  ATimeoutMs: Cardinal): TArray<TLspCodeAction>;
var
  Params, Context: TJSONObject;
  Response, Item: TJSONValue;
  Action: TLspCodeAction;
begin
  Result := nil;
  Context := TJSONObject.Create;
  // Die Befunde der Regeln ermittelt der Server selbst; 1 = ausdrücklich aufgerufen.
  Context.AddPair('diagnostics', TJSONArray.Create);
  Context.AddPair('triggerKind', TJSONNumber.Create(1));
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('range', RangeToJson(ARange));
  Params.AddPair('context', Context);
  Response := FClient.Request('textDocument/codeAction', Params, ATimeoutMs);
  try
    if Response is TJSONArray then
      for Item in TJSONArray(Response) do
        if TLspCodeAction.FromJson(Item, Action) then
          Result := Result + [Action];
  finally
    Response.Free;
  end;
end;

function TLspSession.RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
var
  Arguments: TJSONValue;
begin
  Arguments := nil;
  if Trim(AArgumentsJson) <> '' then
    Arguments := TJSONObject.ParseJSONValue(AArgumentsJson);
  if not (Arguments is TJSONArray) then
  begin
    Arguments.Free;
    Arguments := TJSONArray.Create;
  end;
  Result := FClient.Request('workspace/executeCommand',
    TJSONObject.Create.AddPair('command', ACommand).AddPair('arguments', Arguments), ATimeoutMs);
end;

function TLspSession.OnTypeFormatting(const AFileName: string; ALine, ACharacter: Integer; const ACh: string;
  ATabSize: Integer; AInsertSpaces: Boolean; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
var
  Params: TJSONObject;
  Response, Item: TJSONValue;
  Edit: TLspTextEdit;
begin
  Result := nil;
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('ch', ACh);
  Params.AddPair('options', TJSONObject.Create.AddPair('tabSize', TJSONNumber.Create(ATabSize))
    .AddPair('insertSpaces', TJSONBool.Create(AInsertSpaces)));
  Response := FClient.Request('textDocument/onTypeFormatting', Params, ATimeoutMs);
  try
    if Response is TJSONArray then
      for Item in TJSONArray(Response) do
        if TLspTextEdit.FromJson(Item, Edit) then
          Result := Result + [Edit];
  finally
    Response.Free;
  end;
end;

/// <summary>Parameter von formatting und rangeFormatting ohne Bereich.</summary>
function FormattingParams(const AUri: string; ATabSize: Integer; AInsertSpaces: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
  Result.AddPair('options', TJSONObject.Create.AddPair('tabSize', TJSONNumber.Create(ATabSize))
    .AddPair('insertSpaces', TJSONBool.Create(AInsertSpaces)));
end;

/// <summary>TextEdit[] einer Antwort; gibt AResponse frei.</summary>
function TextEditsOf(AResponse: TJSONValue): TArray<TLspTextEdit>;
var
  Item: TJSONValue;
  Edit: TLspTextEdit;
begin
  Result := nil;
  try
    if AResponse is TJSONArray then
      for Item in TJSONArray(AResponse) do
        if TLspTextEdit.FromJson(Item, Edit) then
          Result := Result + [Edit];
  finally
    AResponse.Free;
  end;
end;

function TLspSession.Formatting(const AFileName: string; ATabSize: Integer; AInsertSpaces: Boolean;
  ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
begin
  Result := TextEditsOf(FClient.Request('textDocument/formatting',
    FormattingParams(PathToUri(AFileName), ATabSize, AInsertSpaces), ATimeoutMs));
end;

function TLspSession.Formatting(const AFileName: string; const ARange: TLspRange; ATabSize: Integer;
  AInsertSpaces: Boolean; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
var
  Params: TJSONObject;
begin
  Params := FormattingParams(PathToUri(AFileName), ATabSize, AInsertSpaces);
  Params.AddPair('range', RangeToJson(ARange));
  Result := TextEditsOf(FClient.Request('textDocument/rangeFormatting', Params, ATimeoutMs));
end;

function TLspSession.SelectionRanges(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspRange>;
var
  Params, Position: TJSONObject;
  Positions: TJSONArray;
  Response, Current: TJSONValue;
  Range: TLspRange;
begin
  Result := nil;
  // selectionRange will eine Liste von Positionen statt "position".
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ALine));
  Position.AddPair('character', TJSONNumber.Create(ACharacter));
  Positions := TJSONArray.Create;
  Positions.AddElement(Position);
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('positions', Positions);
  Response := FClient.Request('textDocument/selectionRange', Params, FTimeoutMs);
  try
    if not (Response is TJSONArray) or (TJSONArray(Response).Count = 0) then
      Exit;
    Current := TJSONArray(Response).Items[0];
    while RangeOf(Current, Range) do
    begin
      Result := Result + [Range];
      Current := TJSONObject(Current).GetValue('parent');
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.LinkedLocals(const AFileName: string; ALine, ACharacter: Integer): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('atlasLocals', TJSONBool.Create(True));
  Result := FClient.Request('textDocument/linkedEditingRange', Params, FTimeoutMs);
end;

function TLspSession.TypeDefinition(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/typeDefinition', PositionParams(AFileName, ALine, ACharacter),
    FTimeoutMs * 2);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

class function TLspSession.IndexToColumn(const ALine: string; AIndex, ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  // Wie ColumnToIndex: Tabs springen zur nächsten Tabulatorposition, hinter dem Zeilenende je Zeichen eine Spalte.
  Result := 1;
  for Index := 1 to AIndex do
    if (Index <= Length(ALine)) and (ALine[Index] = #9) and (ATabWidth > 0) then
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1
    else
      Inc(Result);
end;

function TLspSession.WorkspaceSymbols(const AQuery: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
var
  Response, Item: TJSONValue;
  Entry: TJSONObject;
  Symbol: TAtlasSymbol;
  Locations: TArray<TLspLocation>;
  Location: TJSONValue;
begin
  Result := nil;
  Response := FClient.Request('workspace/symbol', TJSONObject.Create(TJSONPair.Create('query', AQuery)), ATimeoutMs);
  try
    if not (Response is TJSONArray) then
      Exit;
    for Item in TJSONArray(Response) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Entry := TJSONObject(Item);
      Symbol := Default(TAtlasSymbol);
      Symbol.Name := Entry.GetValue<string>('name', '');
      Symbol.Container := Entry.GetValue<string>('containerName', '');
      Symbol.Kind := Entry.GetValue<Integer>('kind', 0);
      Location := Entry.GetValue('location');
      Locations := LocationsOf(Location);
      if (Symbol.Name = '') or (Length(Locations) = 0) then
        Continue;
      Symbol.FileName := Locations[0].FileName;
      Symbol.Line := Locations[0].Line;
      Symbol.Character := Locations[0].Character;
      Result := Result + [Symbol];
    end;
  finally
    Response.Free;
  end;
end;

class function TLspSession.SymbolsOfDocument(const AResponse: TJSONValue;
  const AFileName: string): TArray<TAtlasSymbol>;
var
  Found: TArray<TAtlasSymbol>;

  procedure AddAll(const AItems: TJSONValue; const AContainer: string);
  var
    Item: TJSONValue;
    Entry: TJSONObject;
    Symbol: TAtlasSymbol;
    Locations: TArray<TLspLocation>;
  begin
    if not (AItems is TJSONArray) then
      Exit;
    for Item in TJSONArray(AItems) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Entry := TJSONObject(Item);
      Symbol := Default(TAtlasSymbol);
      Symbol.Name := Entry.GetValue<string>('name', '');
      Symbol.Kind := Entry.GetValue<Integer>('kind', 0);
      Symbol.FileName := AFileName;
      if Entry.GetValue('location') <> nil then
      begin
        // SymbolInformation: Ort und Container stehen am Eintrag.
        Symbol.Container := Entry.GetValue<string>('containerName', '');
        Locations := LocationsOf(Entry.GetValue('location'));
        if Length(Locations) > 0 then
        begin
          Symbol.FileName := Locations[0].FileName;
          Symbol.Line := Locations[0].Line;
          Symbol.Character := Locations[0].Character;
        end;
      end
      else
      begin
        Symbol.Container := AContainer;
        Symbol.Line := Entry.GetValue<Integer>('selectionRange.start.line',
          Entry.GetValue<Integer>('range.start.line', 0));
        Symbol.Character := Entry.GetValue<Integer>('selectionRange.start.character',
          Entry.GetValue<Integer>('range.start.character', 0));
      end;
      if Symbol.Name <> '' then
        Found := Found + [Symbol];
      AddAll(Entry.GetValue('children'), Symbol.Name);
    end;
  end;

begin
  Found := nil;
  AddAll(AResponse, '');
  Result := Found;
end;

function TLspSession.DocumentSymbolTree(const AFileName: string; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/documentSymbol',
    TJSONObject.Create(TJSONPair.Create('textDocument', TJSONObject.Create(TJSONPair.Create('uri',
    PathToUri(AFileName))))), ATimeoutMs);
end;

function TLspSession.DocumentSymbols(const AFileName: string; ATimeoutMs: Cardinal): TArray<TAtlasSymbol>;
var
  Response: TJSONValue;
begin
  Response := DocumentSymbolTree(AFileName, ATimeoutMs);
  try
    Result := SymbolsOfDocument(Response, AFileName);
  finally
    Response.Free;
  end;
end;

function HierarchyItemOf(const AValue: TJSONValue): TAtlasHierarchyItem;
var
  Entry: TJSONObject;
begin
  Result := Default(TAtlasHierarchyItem);
  if not (AValue is TJSONObject) then
    Exit;
  Entry := TJSONObject(AValue);
  Result.Name := Entry.GetValue<string>('name', '');
  Result.Detail := Entry.GetValue<string>('detail', '');
  Result.Kind := Entry.GetValue<Integer>('kind', 0);
  Result.FileName := TLspSession.UriToPath(Entry.GetValue<string>('uri', ''));
  Result.Line := Entry.GetValue<Integer>('selectionRange.start.line', 0);
  Result.Character := Entry.GetValue<Integer>('selectionRange.start.character', 0);
  Result.Raw := Entry.ToJSON;
end;

function ImpactFormsOf(const AValue: TJSONValue): TArray<TAtlasImpactForm>;
var
  Item: TJSONValue;
  Form: TAtlasImpactForm;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for Item in TJSONArray(AValue) do
    if Item is TJSONObject then
    begin
      Form.FileName := TLspSession.UriToPath(TJSONObject(Item).GetValue<string>('uri', ''));
      Form.Line := TJSONObject(Item).GetValue<Integer>('range.start.line', 0);
      Form.Character := TJSONObject(Item).GetValue<Integer>('range.start.character', 0);
      Form.Text := TJSONObject(Item).GetValue<string>('text', '');
      Result := Result + [Form];
    end;
end;

class function TLspSession.ImpactFromJson(const AValue: TJSONValue): TAtlasImpact;
var
  Root, Entry: TJSONObject;
  List, Item, Ranges, First, Names, Name: TJSONValue;
  Place: TAtlasImpactPlace;
  Test: TAtlasImpactTest;
begin
  Result := Default(TAtlasImpact);
  if not (AValue is TJSONObject) then
    Exit;
  Root := TJSONObject(AValue);
  Result.Symbol := HierarchyItemOf(Root.GetValue('symbol'));
  Result.SymbolForms := ImpactFormsOf(Root.GetValue('symbolForms'));
  Result.Depth := Root.GetValue<Integer>('depth', 0);
  Result.DepthReached := Root.GetValue<Boolean>('limits.depth', False);
  Result.CountReached := Root.GetValue<Boolean>('limits.count', False);
  Result.TimeReached := Root.GetValue<Boolean>('limits.time', False);
  Result.Unexpanded := Root.GetValue<Integer>('unexpanded', 0);
  Result.MaxPlaces := Root.GetValue<Integer>('maxPlaces', 0);
  Result.TimeoutMs := Root.GetValue<Integer>('timeoutMs', 0);
  List := Root.GetValue('places');
  if List is TJSONArray then
    for Item in TJSONArray(List) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Entry := TJSONObject(Item);
      Place := Default(TAtlasImpactPlace);
      Place.Item := HierarchyItemOf(Entry.GetValue('item'));
      Place.Item.Confidence := TAtlasConfidence.FromJson(Entry);
      Place.Level := Entry.GetValue<Integer>('level', 0);
      Place.Edge := Entry.GetValue<string>('edge', '');
      Place.Cause := Entry.GetValue<Integer>('cause', -1);
      Place.UseLine := Place.Item.Line;
      Place.UseCharacter := Place.Item.Character;
      Ranges := Entry.GetValue('ranges');
      if (Ranges is TJSONArray) and (TJSONArray(Ranges).Count > 0) then
      begin
        Place.UseCount := TJSONArray(Ranges).Count;
        First := TJSONArray(Ranges).Items[0];
        Place.UseLine := First.GetValue<Integer>('start.line', Place.UseLine);
        Place.UseCharacter := First.GetValue<Integer>('start.character', Place.UseCharacter);
      end;
      Place.Forms := ImpactFormsOf(Entry.GetValue('forms'));
      Place.Terminal := Entry.GetValue<Boolean>('terminal', False);
      Place.Test := Entry.GetValue<string>('test', '');
      Result.Places := Result.Places + [Place];
    end;
  List := Root.GetValue('tests');
  if List is TJSONArray then
    for Item in TJSONArray(List) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Entry := TJSONObject(Item);
      Test := Default(TAtlasImpactTest);
      Test.Name := Entry.GetValue<string>('name', '');
      Names := Entry.GetValue('run');
      if Names is TJSONArray then
        for Name in TJSONArray(Names) do
          Test.RunNames := Test.RunNames + [Name.Value];
      if Test.RunNames = nil then
        Test.RunNames := TArray<string>.Create(Test.Name);
      Test.FileName := TLspSession.UriToPath(Entry.GetValue<string>('uri', ''));
      Test.Line := Entry.GetValue<Integer>('line', 0);
      Test.Level := Entry.GetValue<Integer>('level', 0);
      Result.Tests := Result.Tests + [Test];
    end;
end;

function TLspSession.PrepareHierarchy(ADirection: TAtlasHierarchyDirection; const AFileName: string; ALine,
  ACharacter: Integer): TArray<TAtlasHierarchyItem>;
var
  Method: string;
  Response, Item: TJSONValue;
begin
  Result := nil;
  Method := 'textDocument/prepareTypeHierarchy';
  if ADirection in [TAtlasHierarchyDirection.Incoming, TAtlasHierarchyDirection.Outgoing] then
    Method := 'textDocument/prepareCallHierarchy';
  Response := FClient.Request(Method, PositionParams(AFileName, ALine, ACharacter), FTimeoutMs * 10);
  try
    if Response is TJSONArray then
      for Item in TJSONArray(Response) do
        if Item is TJSONObject then
          Result := Result + [HierarchyItemOf(Item)];
  finally
    Response.Free;
  end;
end;

function TLspSession.Impact(const AFileName: string; ALine, ACharacter, ADepth: Integer): TAtlasImpact;
var
  Params: TJSONObject;
  Response: TJSONValue;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('depth', TJSONNumber.Create(ADepth));
  // Mehrere Referenzsuchen über das ganze Projekt; der Server begrenzt die Zeit selbst und meldet es.
  Response := FClient.Request('atlas/impact', Params, FTimeoutMs * 30);
  try
    Result := ImpactFromJson(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.DataFlow(const ARequest: TAtlasDataFlowRequest): TAtlasDataFlowResult;
var
  Response: TJSONValue;
begin
  // Projektweit über die Referenzsuche; dafür so viel Zeit wie für die Hierarchien.
  Response := FClient.Request(TAtlasDataFlowJson.Method, TAtlasDataFlowJson.Params(ARequest), FTimeoutMs * 10);
  try
    Result := TAtlasDataFlowJson.Parse(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.HierarchyChildren(ADirection: TAtlasHierarchyDirection;
  const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
const
  Methods: array[TAtlasHierarchyDirection] of string = ('callHierarchy/incomingCalls',
    'callHierarchy/outgoingCalls', 'typeHierarchy/supertypes', 'typeHierarchy/subtypes');
  // Aufrufe stecken in {from|to, fromRanges}; Typen kommen direkt.
  Members: array[TAtlasHierarchyDirection] of string = ('from', 'to', '', '');
var
  Raw, Response, Item, Inner: TJSONValue;
  Child: TAtlasHierarchyItem;
begin
  Result := nil;
  Raw := TJSONObject.ParseJSONValue(AItem.Raw);
  if not (Raw is TJSONObject) then
  begin
    Raw.Free;
    Exit;
  end;
  Response := FClient.Request(Methods[ADirection], TJSONObject.Create(TJSONPair.Create('item', Raw)), FTimeoutMs * 10);
  try
    if not (Response is TJSONArray) then
      Exit;
    for Item in TJSONArray(Response) do
    begin
      Inner := Item;
      if (Members[ADirection] <> '') and (Item is TJSONObject) then
        Inner := TJSONObject(Item).GetValue(Members[ADirection]);
      if Inner is TJSONObject then
      begin
        Child := HierarchyItemOf(Inner);
        // Eingehende Aufrufe (#1119): atlasConfidence steht am Aufruf, nicht am Element.
        Child.Confidence := TAtlasConfidence.FromJson(Item);
        // Aufruf über Interface oder virtuelle Methode (#1122), ebenfalls am Aufruf.
        if Item is TJSONObject then
        begin
          Child.Dispatch := TJSONObject(Item).GetValue<string>('atlasDispatch.kind', '');
          Child.Implementations := TJSONObject(Item).GetValue<Integer>('atlasDispatch.implementations', 0);
        end;
        Result := Result + [Child];
      end;
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.InlineValues(const AFileName: string; AFromLine, AToLine, AStoppedLine: Integer;
  ATimeoutMs: Cardinal): TAtlasInlineValueRefs;
var
  Params, Range, Stopped: TJSONObject;
  Response: TJSONValue;
begin
  Range := TJSONObject.Create;
  Range.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AFromLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Range.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AToLine + 1))
    .AddPair('character', TJSONNumber.Create(0)));
  Stopped := TJSONObject.Create;
  Stopped.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AStoppedLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Stopped.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AStoppedLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('range', Range);
  Params.AddPair('context', TJSONObject.Create.AddPair('frameId', TJSONNumber.Create(0))
    .AddPair('stoppedLocation', Stopped));
  Response := FClient.Request('textDocument/inlineValue', Params, ATimeoutMs);
  try
    Result := InlineValueRefsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.CompilerSwitches(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(ACharacter)));
  Result := FClient.Request('atlas/compilerSwitches', Params, ATimeoutMs);
end;

function TLspSession.DebugUnavailable(const AFileName: string; ALine: Integer; const AName: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(0)));
  Params.AddPair('name', AName);
  Result := FClient.Request('atlas/debugUnavailable', Params, ATimeoutMs);
end;

function TLspSession.AccessChains(const AFileName: string; ALine, APointerSize: Integer;
  ATimeoutMs: Cardinal): TAtlasAvChains;
var
  Response: TJSONValue;
begin
  Response := FClient.Request(TAtlasAvJson.Method, TAtlasAvJson.Params(AFileName, ALine, APointerSize), ATimeoutMs);
  try
    Result := TAtlasAvJson.Parse(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.ExpressionCompletion(const AFileName: string; ALine: Integer; const AExpression: string;
  ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(0)));
  Params.AddPair('expression', AExpression);
  Params.AddPair('character', TJSONNumber.Create(ACharacter));
  Result := FClient.Request('atlas/expressionCompletion', Params, ATimeoutMs);
end;

class function TLspSession.InlineValueRefsOf(const AResponse: TJSONValue): TAtlasInlineValueRefs;
var
  Item: TJSONValue;
  Entry: TJSONObject;
  Name: string;
begin
  Result := nil;
  if not (AResponse is TJSONArray) then
    Exit;
  for Item in TJSONArray(AResponse) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Entry := TJSONObject(Item);
    // InlineValueText (text) und InlineValueEvaluatableExpression (expression) wertet Atlas nicht aus.
    Name := Entry.GetValue<string>('variableName', '');
    if Name = '' then
      Continue;
    Result := Result + [TAtlasInlineValueRef.Create(Entry.GetValue<Integer>('range.start.line', -1),
      Entry.GetValue<Integer>('range.start.character', 0), Name, Entry.GetValue<string>('atlasType', ''))];
  end;
end;

function TLspSession.InlayHints(const AFileName: string; AFromLine, AToLine: Integer;
  ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>;
begin
  Result := InlayHints(AFileName, AFromLine, AToLine, 0, ATimeoutMs);
end;

function TLspSession.InlayHints(const AFileName: string; AFromLine, AToLine, AEndMarkerMinLines: Integer;
  ATimeoutMs: Cardinal): TArray<TAtlasInlayHint>;
var
  Params, Range: TJSONObject;
  Response, Item, Part: TJSONValue;
  Entry: TJSONObject;
  Parts, Names: TJSONArray;
  Hint: TAtlasInlayHint;
  Text: string;
  Kind: Integer;
begin
  Result := nil;
  Range := TJSONObject.Create;
  Range.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AFromLine))
    .AddPair('character', TJSONNumber.Create(0)));
  Range.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AToLine + 1))
    .AddPair('character', TJSONNumber.Create(0)));
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  Params.AddPair('range', Range);
  if AEndMarkerMinLines > 0 then
    Params.AddPair('atlas', TJSONObject.Create(TJSONPair.Create('endMarkerMinLines',
      TJSONNumber.Create(AEndMarkerMinLines))));
  Response := FClient.Request('textDocument/inlayHint', Params, ATimeoutMs);
  try
    if not (Response is TJSONArray) then
      Exit;
    for Item in TJSONArray(Response) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Entry := TJSONObject(Item);
      // Parameternamen (kind 2), Typmarken (kind 1, #453), Endmarken ohne kind mit "// …" (#620) und
      // Include-Symbole ohne kind mit data.includeDefines (#860), Steuerzeichen mit data.controlChar (#862) und
      // Methoden ohne Self mit data.methodWithoutSelf (#686).
      Kind := Entry.GetValue<Integer>('kind', 0);
      if (Kind <> 2) and (Kind <> 1) and (Kind <> 0) then
        Continue;
      // label ist ein String oder eine Liste von InlayHintLabelPart.
      Text := '';
      if Entry.TryGetValue<TJSONArray>('label', Parts) then
      begin
        for Part in Parts do
          if Part is TJSONObject then
            Text := Text + TJSONObject(Part).GetValue<string>('value', '');
      end
      else
        Text := Entry.GetValue<string>('label', '');
      Text := Trim(Text);
      Hint := Default(TAtlasInlayHint);
      if (Kind = 0) and Entry.TryGetValue<TJSONArray>('data.includeDefines.names', Names) then
      begin
        // Beschriftung baut die Oberfläche in der Sprache der IDE.
        Hint.DefineHint := True;
        Text := '';
        for Part in Names do
          if Text = '' then
            Text := Part.Value
          else
            Text := Text + ', ' + Part.Value;
      end
      else if (Kind = 0) and (Entry.GetValue<Integer>('data.controlChar.code', -1) >= 0) then
        Hint.CharHint := True
      else if (Kind = 0) and Entry.GetValue<Boolean>('data.methodWithoutSelf', False) then
        // Methode ohne Self (#686); die Beschriftung baut die Oberfläche in der Sprache der IDE.
        Hint.MethodHint := True
      else if Kind = 0 then
      begin
        if not Text.StartsWith('//') then
          Continue;
        Hint.EndLabel := True;
        Text := Trim(Copy(Text, 3, MaxInt));
        // Blockanfang für den Sprung per Klick (#620).
        Hint.BlockLine := Entry.GetValue<Integer>('data.blockStart.line', -1);
        Hint.BlockCharacter := Entry.GetValue<Integer>('data.blockStart.character', 0);
        Hint.HasBlock := Hint.BlockLine >= 0;
      end
      else if Kind = 1 then
      begin
        // ": TStringList" ohne Doppelpunkt.
        Hint.TypeHint := True;
        if Text.StartsWith(':') then
          Text := Trim(Copy(Text, 2, MaxInt));
      end
      else if Text.EndsWith(':') then
        Text := TrimRight(Copy(Text, 1, Length(Text) - 1));
      Hint.Line := Entry.GetValue<Integer>('position.line', -1);
      Hint.Character := Entry.GetValue<Integer>('position.character', 0);
      Hint.Name := Text;
      if (Hint.Line >= 0) and (Hint.Name <> '') then
        Result := Result + [Hint];
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.DocumentDiagnostics(const AFileName, APreviousResultId: string;
  ATimeoutMs: Cardinal): TLspDiagnosticReport;
var
  Params: TJSONObject;
  Response: TJSONValue;
begin
  Params := TJSONObject.Create;
  Params.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  if APreviousResultId <> '' then
    Params.AddPair('previousResultId', APreviousResultId);
  Response := FClient.Request('textDocument/diagnostic', Params, ATimeoutMs);
  try
    if Response is TJSONObject then
      Result := TLspDiagnosticReport.FromJson(TJSONObject(Response), AFileName)
    else
    begin
      Result := Default(TLspDiagnosticReport);
      Result.FileName := AFileName;
    end;
  finally
    Response.Free;
  end;
end;

function TLspSession.WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
  ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>;
var
  Params: TJSONObject;
  Previous: TJSONArray;
  Known: TLspDiagnosticReport;
  Response, Items, Item: TJSONValue;
  Report: TLspDiagnosticReport;
begin
  Result := nil;
  Previous := TJSONArray.Create;
  for Known in APrevious do
    if Known.ResultId <> '' then
      Previous.AddElement(TJSONObject.Create.AddPair('uri', PathToUri(Known.FileName))
        .AddPair('value', Known.ResultId));
  Params := TJSONObject.Create;
  Params.AddPair('previousResultIds', Previous);
  Response := FClient.Request('workspace/diagnostic', Params, ATimeoutMs);
  try
    if not (Response is TJSONObject) then
      Exit;
    Items := TJSONObject(Response).GetValue('items');
    if Items is TJSONArray then
      for Item in TJSONArray(Items) do
        if Item is TJSONObject then
        begin
          Report := TLspDiagnosticReport.FromJson(TJSONObject(Item), '');
          if Report.FileName <> '' then
            Result := Result + [Report];
        end;
  finally
    Response.Free;
  end;
end;

procedure TLspSession.Close(const AFileName: string);
begin
  TMonitor.Enter(FDocLock);
  try
    CloseLocked(AFileName);
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

procedure TLspSession.CloseLocked(const AFileName: string);
var
  Key: string;
begin
  Key := AnsiLowerCase(AFileName);
  if not FDocuments.ContainsKey(Key) then
    Exit;
  FDocuments.Remove(Key);
  FClient.Notify('textDocument/didClose', TJSONObject.Create(TJSONPair.Create('textDocument',
    TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))))));
end;

procedure TLspSession.Saved(const AFileName: string);
var
  Known: Boolean;
begin
  TMonitor.Enter(FDocLock);
  try
    Known := FDocuments.ContainsKey(AnsiLowerCase(AFileName));
  finally
    TMonitor.Exit(FDocLock);
  end;
  if not Known then
    Exit;
  FClient.Notify('textDocument/didSave', TJSONObject.Create(TJSONPair.Create('textDocument',
    TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))))));
end;

function TLspSession.SyncedFiles: TArray<string>;
var
  State: TDocumentState;
begin
  Result := nil;
  TMonitor.Enter(FDocLock);
  try
    for State in FDocuments.Values do
      Result := Result + [State.FileName];
  finally
    TMonitor.Exit(FDocLock);
  end;
end;

function TLspSession.SyncedText(const AFileName: string; out AText: string): Boolean;
var
  State: TDocumentState;
begin
  TMonitor.Enter(FDocLock);
  try
    Result := FDocuments.TryGetValue(AnsiLowerCase(AFileName), State);
  finally
    TMonitor.Exit(FDocLock);
  end;
  if Result then
    AText := State.Text
  else
    AText := '';
end;

function TLspSession.OpenDocuments: TArray<TLspOpenDocument>;
var
  State: TDocumentState;
  Document: TLspOpenDocument;
begin
  Result := nil;
  for State in FDocuments.Values do
  begin
    Document.FileName := State.FileName;
    Document.Text := State.Text;
    Result := Result + [Document];
  end;
end;

procedure TLspSession.Reopen(const ADocuments: TArray<TLspOpenDocument>);
var
  Document: TLspOpenDocument;
begin
  for Document in ADocuments do
    if not FDocuments.ContainsKey(AnsiLowerCase(Document.FileName)) then
      Sync(Document.FileName, Document.Text);
end;

procedure TLspSession.FilesChanged(const AChanges: TArray<TAtlasFileChange>);
var
  Change: TAtlasFileChange;
  Items: TJSONArray;
  Item: TJSONObject;
begin
  Items := TJSONArray.Create;
  for Change in AChanges do
  begin
    if (Change.Kind = TAtlasFileChangeKind.Changed) and FDocuments.ContainsKey(AnsiLowerCase(Change.FileName)) then
      Continue;
    Item := TJSONObject.Create;
    Item.AddPair('uri', PathToUri(Change.FileName));
    Item.AddPair('type', TJSONNumber.Create(Ord(Change.Kind)));
    Items.AddElement(Item);
  end;
  if Items.Count = 0 then
  begin
    Items.Free;
    Exit;
  end;
  FClient.Notify('workspace/didChangeWatchedFiles', TJSONObject.Create(TJSONPair.Create('changes', Items)));
end;

function TLspSession.ProgressText: string;
begin
  Result := FProgress.Text;
end;

function TLspSession.IndexingText: string;
begin
  Result := FProgress.IndexingText;
end;

function TLspSession.Indexing(out APercent: Integer): Boolean;
begin
  Result := FProgress.Active(APercent);
end;

procedure TLspSession.SetOnProgress(const AProc: TProc);
begin
  FProgress.SetOnChanged(AProc);
end;

function TLspSession.ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := ExecuteCommand(ACommand, TJSONArray.Create, ATimeoutMs);
end;

function TLspSession.ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
begin
  try
    Result := FClient.Request('workspace/executeCommand',
      TJSONObject.Create.AddPair('command', ACommand).AddPair('arguments', AArguments), ATimeoutMs);
  except
    Result := nil;
  end;
end;

function TLspSession.RefreshCount: Integer;
begin
  Result := FRefresh.Count;
end;

{ TLspDiagnosticReport }

class function TLspDiagnosticReport.FromJson(const AReport: TJSONObject; const AFileName: string): TLspDiagnosticReport;
var
  Items: TJSONValue;
  Uri: string;
begin
  Result := Default(TLspDiagnosticReport);
  Uri := AReport.GetValue<string>('uri', '');
  if Uri <> '' then
    Result.FileName := TLspSession.UriToPath(Uri)
  else
    Result.FileName := AFileName;
  Result.ResultId := AReport.GetValue<string>('resultId', '');
  Result.Unchanged := AReport.GetValue<string>('kind', 'full') = 'unchanged';
  Items := AReport.GetValue('items');
  if Items is TJSONArray then
    Result.Problems := TAtlasProblem.ListFromJson(TJSONArray(Items));
end;

{ TLspHoverParts }

function TLspHoverParts.Found: Boolean;
begin
  Result := Declaration <> '';
end;

class function TLspHoverParts.FromHover(const AHover: TJSONValue): TLspHoverParts;
var
  Parts: TJSONValue;
  Text: string;
  Paragraphs: TArray<string>;
begin
  Result := Default(TLspHoverParts);
  if not (AHover is TJSONObject) then
    Exit;
  Parts := TJSONObject(AHover).GetValue('atlas');
  if Parts is TJSONObject then
  begin
    Result.Declaration := TJSONObject(Parts).GetValue<string>('declaration', '');
    Result.UnitName := TJSONObject(Parts).GetValue<string>('unit', '');
    // Seit #654 ist "documentation" strukturiert; der Klartext steht in "documentationText".
    if not TJSONObject(Parts).TryGetValue<string>('documentationText', Result.Documentation) and
      (TJSONObject(Parts).GetValue('documentation') is TJSONString) then
      Result.Documentation := TJSONObject(Parts).GetValue('documentation').Value;
    Result.Value := TJSONObject(Parts).GetValue<string>('value', '');
    Result.Deprecation := TJSONObject(Parts).GetValue<string>('deprecation', '');
    Exit;
  end;
  // Ältere Server: Klartext, erster Absatz ist die Deklaration, der Rest Doku.
  Text := TLspSession.HoverText(AHover).Replace(#13#10, #10).Trim;
  if Text = '' then
    Exit;
  Paragraphs := Text.Split([#10#10], 2);
  Result.Declaration := Paragraphs[0];
  if Length(Paragraphs) > 1 then
    Result.Documentation := Paragraphs[1];
end;

function TLspSession.Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
  out ALocation: TLspLocation): Boolean;
var
  Response, Item: TJSONValue;
  Location: TJSONObject;
  Uri: string;
  Range: TJSONObject;
begin
  ALocation := Default(TLspLocation);
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/definition', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    // Location, Location[] oder LocationLink[].
    Item := Response;
    if (Item is TJSONArray) and (TJSONArray(Item).Count > 0) then
      Item := TJSONArray(Item).Items[0];
    if not (Item is TJSONObject) then
      Exit(False);
    Location := TJSONObject(Item);
    if not Location.TryGetValue<string>('uri', Uri) then
      Uri := Location.GetValue<string>('targetUri', '');
    Range := Location.GetValue('range') as TJSONObject;
    if Range = nil then
      Range := Location.GetValue('targetSelectionRange') as TJSONObject;
    if (Uri = '') or (Range = nil) then
      Exit(False);
    ALocation.FileName := UriToPath(Uri);
    ALocation.Line := Range.GetValue<Integer>('start.line', 0);
    ALocation.Character := Range.GetValue<Integer>('start.character', 0);
    Result := ALocation.FileName <> '';
  finally
    Response.Free;
  end;
end;

function TLspSession.Definitions(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/definition', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.Declarations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  Response: TJSONValue;
begin
  Response := FClient.Request('textDocument/declaration', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := LocationsOf(Response);
  finally
    Response.Free;
  end;
end;

function TLspSession.PrepareRename(const AFileName, AText: string; ALine, ACharacter: Integer;
  out APlaceholder: string): Boolean;
var
  Response: TJSONValue;
  Range: TJSONObject;
  Position: TLspTextPosition;
  StartOffset, EndOffset: Integer;
begin
  APlaceholder := '';
  Sync(AFileName, AText);
  Response := FClient.Request('textDocument/prepareRename', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    // Range, {range, placeholder} oder {defaultBehavior}; null heißt: hier nicht.
    if not (Response is TJSONObject) then
      Exit(False);
    if TJSONObject(Response).TryGetValue<string>('placeholder', APlaceholder) then
      Exit(True);
    if not TJSONObject(Response).TryGetValue<TJSONObject>('range', Range) then
      Range := TJSONObject(Response);
    if Range.TryGetValue<Integer>('start.line', Position.Line) and
      Range.TryGetValue<Integer>('start.character', Position.Character) then
    begin
      StartOffset := TLspTextChanges.OffsetOf(AText, Position);
      Position.Line := Range.GetValue<Integer>('end.line', Position.Line);
      Position.Character := Range.GetValue<Integer>('end.character', Position.Character);
      EndOffset := TLspTextChanges.OffsetOf(AText, Position);
      APlaceholder := Copy(AText, StartOffset + 1, EndOffset - StartOffset);
    end;
    Result := True;
  finally
    Response.Free;
  end;
end;

function TLspSession.Rename(const AFileName: string; ALine, ACharacter: Integer; const ANewName: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  Params.AddPair('newName', ANewName);
  Result := FClient.Request('textDocument/rename', Params, ATimeoutMs);
end;

function TLspSession.Completion(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/completion', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSession.Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
  const ATrigger: string; const AOnPartial: TLspPartialProc): TJSONValue;
var
  Params: TJSONObject;
begin
  Params := PositionParams(AFileName, ALine, ACharacter);
  // CompletionContext: triggerKind 2 = TriggerCharacter, 1 = Invoked.
  if ATrigger <> '' then
    Params.AddPair('context', TJSONObject.Create.AddPair('triggerKind', TJSONNumber.Create(2))
      .AddPair('triggerCharacter', ATrigger));
  Result := FClient.Request('textDocument/completion', Params, ATimeoutMs, AOnPartial);
end;

function TLspSession.SignatureHelp(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/signatureHelp', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSession.ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('completionItem/resolve', AItem, ATimeoutMs);
end;

class function TLspSession.SettingsParams(const AJson: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Value := TJSONObject.Create;
  end;
  Result := TJSONObject.Create(TJSONPair.Create('settings', TJSONObject.Create(TJSONPair.Create('atlas', Value))));
end;

procedure TLspSession.Notify(const AMethod: string; AParams: TJSONObject);
begin
  FClient.Notify(AMethod, AParams);
end;

class function TLspSession.ProjectFolders(const AProjects: TArray<string>): TJSONArray;
var
  Project: string;
begin
  Result := TJSONArray.Create;
  for Project in AProjects do
    Result.AddElement(TJSONObject.Create.AddPair('uri', PathToUri(Project))
      .AddPair('name', ChangeFileExt(ExtractFileName(Project), '')));
end;

function ContainsText_(const AValues: TArray<string>; const AValue: string): Boolean;
var
  Value: string;
begin
  for Value in AValues do
    if SameText(Value, AValue) then
      Exit(True);
  Result := False;
end;

class procedure TLspSession.ProjectChanges(const AOld, ANew: TArray<string>; out AAdded, ARemoved: TArray<string>);
var
  Project: string;
begin
  AAdded := nil;
  ARemoved := nil;
  for Project in ANew do
    if not ContainsText_(AOld, Project) and not ContainsText_(AAdded, Project) then
      AAdded := AAdded + [Project];
  for Project in AOld do
    if not ContainsText_(ANew, Project) and not ContainsText_(ARemoved, Project) then
      ARemoved := ARemoved + [Project];
end;

procedure TLspSession.SetProjects(const AProjects: TArray<string>);
var
  Added, Removed: TArray<string>;
begin
  if not FInitialized then
  begin
    FProjects := AProjects;
    Exit;
  end;
  ProjectChanges(FProjects, AProjects, Added, Removed);
  FProjects := AProjects;
  if (Length(Added) = 0) and (Length(Removed) = 0) then
    Exit;
  FClient.Notify('workspace/didChangeWorkspaceFolders', TJSONObject.Create(TJSONPair.Create('event',
    TJSONObject.Create.AddPair('added', ProjectFolders(Added)).AddPair('removed', ProjectFolders(Removed)))));
end;

function TLspSession.SetProjectContexts(const AContexts: TArray<TAtlasProjectContext>):
  TArray<TAtlasProjectContext>;
var
  Context: TAtlasProjectContext;
  Known: string;
begin
  Result := nil;
  if not FInitialized then
  begin
    FContexts := AContexts;
    Exit(AContexts);
  end;
  for Context in AContexts do
    if not FSentContexts.TryGetValue(AnsiUpperCase(Context.Project), Known) or (Known <> Context.Key) then
    begin
      FSentContexts.AddOrSetValue(AnsiUpperCase(Context.Project), Context.Key);
      FClient.Notify('atlas/projectContext', Context.ToJson);
      Result := Result + [Context];
    end;
end;

end.
