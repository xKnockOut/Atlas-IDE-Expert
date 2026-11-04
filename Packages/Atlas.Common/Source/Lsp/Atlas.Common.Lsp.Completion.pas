unit Atlas.Common.Lsp.Completion;

// Code-Vervollständigung (textDocument/completion), Grundstufe:
//   - nach "A.B." die Mitglieder des Typs von A.B samt geerbter, bei Units deren interface-Symbole,
//   - in uses die bekannten Units,
//   - sonst alle sichtbaren Namen (lokal, eigene Klasse, eigene Unit, Units aus uses).
// Ausgewählt wird unscharf (#229, TFuzzyMatch: Teilfolgen, Kürzel, Wortanfänge) oder mit
// completion.matching = prefix nur nach dem Anfang. Unscharf sortiert die Punktzahl,
// bei Gleichstand der nächste Gültigkeitsbereich; isIncomplete lässt den Editor bei
// jedem Tastendruck neu fragen, filterText verhindert, dass er Treffer verwirft.
// Ab zwei getippten Zeichen kommen Symbole aus noch nicht eingebundenen Units dazu (#180),
// Projekt-Units vor Bibliotheken; additionalTextEdits trägt die Unit beim Annehmen ins uses ein.
// Typauflösung mit Überladungen, Generics, Class Helpern, with, var X := … und Sichtbarkeit liefert der
// NameResolver (#263); private und strict private fremder Klassen bzw. Units und protected außerhalb von
// Nachfahren erscheinen nicht.
//
// Kontexte ohne Typauflösung (#31):
//   - nach "inherited " nur Methoden und Konstruktoren der Vorfahren,
//   - nach "class(", "is", "is not", "as" und nach ":" in Deklarationen (auch inline var) nur Typen,
//   - in "property Name: T read/write " nur Felder und Methoden mit passender Signatur (PropertyItems),
//   - nach "override " im Klassenrumpf die überschreibbaren Methoden der Vorfahren (OverrideItems),
//   - Schlüsselwörter passend zur Stelle (Anweisung, Deklaration, Klassenrumpf), sobald etwas getippt ist.
// In Kommentaren und Strings (auch mehrzeiligen ''' ab Delphi 12) wird nichts vorgeschlagen.
//
// Geschwindigkeit (#616): Ist schon etwas getippt, baut der Resolver nur Kandidaten, deren Name passt
// (NameFilter). isIncomplete kommt nur, wenn die Liste wirklich unvollständig ist (gekürzt, oder Importe
// fehlen noch, weil zu wenig getippt ist); sonst filtert der Editor selbst weiter. Schickt der Client einen
// partialResultToken, kommen die Einträge gestaffelt: eigener Gültigkeitsbereich, Units aus uses, zuletzt
// Importe aus nicht eingebundenen Units ($/progress mit CompletionItem[], der Rest in der Antwort).
//
// Postfix-Vorlagen (#188): Hinter "Ausdruck." kommen nach den Mitgliedern Kürzel wie for, tryf,
// ifa und fmt, die den Ausdruck ersetzen (textEdit ab Ausdrucksbeginn, filterText "Ausdruck.Kürzel"),
// sofern der Typ bekannt ist und passt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.Internals.FormCache,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.CompletionAnonymous;

type
  // Typen der Vervollständigung stehen in Atlas.Common.Lsp.CompletionRequest (Code-Review S-01); hier
  // weiter unter ihrem Namen, damit Aufrufer ohne Änderung übersetzen.
  TCompletionContextKind = Atlas.Common.Lsp.CompletionRequest.TCompletionContextKind;
  TCompletionFilter = Atlas.Common.Lsp.CompletionRequest.TCompletionFilter;
  TCompletionPlace = Atlas.Common.Lsp.CompletionRequest.TCompletionPlace;
  TCompletionContext = Atlas.Common.Lsp.CompletionRequest.TCompletionContext;
  TCompletionItem = Atlas.Common.Lsp.CompletionRequest.TCompletionItem;
  TCompletionItems = Atlas.Common.Lsp.CompletionRequest.TCompletionItems;
  TCompletionReadText = Atlas.Common.Lsp.CompletionRequest.TCompletionReadText;
  TCompletionPartialProc = Atlas.Common.Lsp.CompletionRequest.TCompletionPartialProc;
  TCompletionRequest = Atlas.Common.Lsp.CompletionRequest.TCompletionRequest;

  /// <summary>Postfix-Vorlagen (#188) je Dokument.</summary>
  TPostfixOptions = record
    Enabled: Boolean;
    /// <summary>for var Item in … (ab Delphi 10.3 und refactoring.inlineVar); sonst Eintrag im var-Abschnitt.
    /// </summary>
    InlineVar: Boolean;
    /// <summary>Als LSP-Snippet mit Platzhaltern und Endposition (snippetSupport des Clients).</summary>
    Snippet: Boolean;
    /// <summary>Eigene Vorlagen des Plugins (atlas/postfixTemplates).</summary>
    Custom: TArray<TPostfixTemplate>;
    class function Default: TPostfixOptions; static;
  end;

  TPostfixOptionsFunc = reference to function(const AUri: string): TPostfixOptions;

  /// <summary>Auszug des Formulars zur Unit ASourceFile mit dem Text ASourceText (#455, #480); False ohne
  /// Formular.</summary>
  TCompletionFormFunc = reference to function(const ASourceFile, ASourceText: string;
    out ASnapshot: TFormSnapshot): Boolean;

  TCompletionMatchingFunc = reference to function(const AUri: string): TCompletionMatching;

  /// <summary>Einstellungen der Vervollständigung je Dokument (#466, #480).</summary>
  TCompletionSettingsFunc = reference to function(const AUri: string): TCompletionSettings;

  /// <summary>Sendet eine Benachrichtigung an den Client (z. B. $/progress); übernimmt AParams.</summary>
  TCompletionNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);

  /// <summary>Zeitmessung je Anfrage (#616), z. B. für ILogger.Debug.</summary>
  TCompletionLogProc = reference to procedure(const AText: string);

  /// <summary>Ist eine Funktion für das Dokument eingeschaltet (z. B. completeBlocks.docComment, #88)?</summary>
  TCompletionEnabledFunc = reference to function(const AUri: string): Boolean;
  /// <summary>„with auflösen“ über Strg+Leer auf with (#50): Änderungen für die with-Anweisung am Cursor; False
  /// ohne Angebot.</summary>
  TCompletionWithFunc = reference to function(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean;
  /// <summary>„Methode aus Aufruf anlegen“ (#472): Titel, Kopf und Änderungen für den Aufruf am Cursor; False ohne
  /// Angebot (bekannter Name, kein Aufruf, abgeschaltet).</summary>
  TCompletionCreateFunc = reference to function(ARequest: TCompletionRequest; out ATitle, ADetail: string;
    out AEdits: TArray<TTextEdit>): Boolean;
  /// <summary>Präfix für Namensvorschläge (#452) der Art AKind im Projekt von AUri: Vorgabe der Projektdatei,
  /// sonst nach der Zählung im Index (TLspCompletion.NamingPrefix); '' ohne.</summary>
  TCompletionNamingFunc = reference to function(const AUri: string; AKind: TNamingKind): string;

  /// <summary>Ergebnis eines Falls der Vervollständigung (Code-Review S-01): weiter mit dem nächsten Fall oder
  /// fertig mit TCompletionAnswer.Exclusive.</summary>
  TCompletionOutcome = (Next, Answered);

  /// <summary>Antwort im Aufbau (Code-Review S-01, 4.2 Schritt 5): Hinweise oben, vorab bestimmte Einträge
  /// (Aufzählungswerte, Komponenten; bei Staffelung schon gesendet), die allgemeine Liste und der Schluss
  /// (Code-Vorlagen, Deklarieren). Ein exklusiver Fall antwortet mit Exclusive allein.</summary>
  TCompletionAnswer = class
  public
    Hints: TArray<TCompletionItem>;
    Prefetched: TArray<TCompletionItem>;
    Body: TArray<TCompletionItem>;
    Tail: TArray<TCompletionItem>;
    Incomplete: Boolean;
    Exclusive: TCompletionItems;
    /// <summary>Postfix-Vorlagen des Dokuments (#188), gesetzt vor der allgemeinen Liste.</summary>
    Postfix: TPostfixOptions;
    /// <summary>partialResultToken (#616); '' ohne Staffelung.</summary>
    Token: string;
    /// <summary>Schon als $/progress gesendete Einträge; die Antwort setzt sortText dahinter fort.</summary>
    SentCount: Integer;
    Partial: TCompletionPartialProc;
    Cancellation: IJsonRpcCancellationToken;
    Forms: TCompletionFormFunc;
  end;

  /// <summary>Ein Fall von textDocument/completion; die Reihenfolge legt TLspCompletion.RegisterCases fest.
  /// </summary>
  TCompletionCase = reference to function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome;

  TLspCompletion = class
  public const
    Method = 'textDocument/completion';
    ResolveMethod = 'completionItem/resolve';
    /// <summary>Eigene Postfix-Vorlagen vom Plugin (#188).</summary>
    PostfixTemplatesMethod = 'atlas/postfixTemplates';
    MaxItems = CompletionMaxItems;
    /// <summary>Höchstzahl der Vorschläge aus nicht eingebundenen Units.</summary>
    MaxImportItems = CompletionMaxImportItems;
    /// <summary>So viele Zeichen muss der Name haben, bevor nicht eingebundene Units mitsuchen.</summary>
    MinImportPrefix = CompletionMinImportPrefix;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FMatchingFor: TCompletionMatchingFunc;
    FSettingsFor: TCompletionSettingsFunc;
    FReadText: TCompletionReadText;
    FSlashCommandsFor: TSlashCommandsProvider;
    FRuleIdsFor: TSlashRuleIdsFunc;
    FPostfixFor: TPostfixOptionsFunc;
    FWithFor: TCompletionWithFunc;
    FCreateFor: TCompletionCreateFunc;
    FNamingFor: TCompletionNamingFunc;
    FHintsFor: TDocHintsProvider;
    FDocCommentsFor: TCompletionEnabledFunc;
    FSymbolsFor: TConditionalContextFunc;
    FNotify: TCompletionNotifyProc;
    FLog: TCompletionLogProc;
    FSnippetSupport: Boolean;
    FDocumentationMarkdown: Boolean;
    // Eigene Postfix-Vorlagen (#188); unter FCacheLock.
    FCustomPostfix: TArray<TPostfixTemplate>;
    // Zuletzt für completionItem/resolve gelesene Datei (#616): Beim Blättern in der Liste fragt Atlas oft
    // nacheinander Symbole derselben großen Bibliotheks-Unit nach.
    FCacheLock: TObject;
    FCacheFile: string;
    FCacheStamp: TDateTime;
    FCacheText: string;
    // Auszüge der Formulardateien (Code-Review P-06); eigene Sperre.
    FForms: TFormSnapshotCache;
    // Fälle von textDocument/completion in fester Reihenfolge (Code-Review S-01): ohne und mit Syntaxbaum.
    FTextCases: TArray<TCompletionCase>;
    FTreeCases: TArray<TCompletionCase>;
    procedure RegisterCases;
    procedure HandlePostfixTemplates(const AParams: TJSONValue);
    /// <summary>Formular zur Unit über FReadText, zwischengespeichert je Stand der Formulardatei.</summary>
    function FormSnapshot(const ASourceFile, ASourceText: string; out ASnapshot: TFormSnapshot): Boolean;
    function ReadCached(const AFileName: string; out AText: string): Boolean;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>Antwort für ADocument an APosition; AParams (darf nil sein) liefert Auslöser und
    /// partialResultToken.</summary>
    function CompleteDocument(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
      const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>CompletionList für eine Momentaufnahme außerhalb des Dokumentspeichers, etwa mit eingefügtem
    /// Ausdruck (#538); ohne Auslöser und ohne Staffelung.</summary>
    function Complete(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    /// <summary>completionProvider mit Punkt als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Was an APosition vervollständigt wird.</summary>
    class function Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext; static;
    /// <summary>Erwarteter Typ an APosition (#417): Typ des aktiven Parameters im innersten Aufruf, sonst der
    /// linken Seite einer Zuweisung (auch Result); '' wenn unbekannt.</summary>
    class function ExpectedType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): string; static;
    /// <summary>Wie ExpectedType, bei Zuweisungen aber samt Typargumenten der linken Seite (TProc&lt;string&gt;
    /// statt TProc, #468). ExpectedType bleibt ohne, weil die Gruppierung nach Fits mit den Typnamen der
    /// Kandidaten ohne Typargumente vergleicht.</summary>
    class function ExpectedFullType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): string; static;
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      AMatching: TCompletionMatching): TCompletionItems; overload; static;
    /// <summary>Wie oben mit AMatching = Fuzzy.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition): TCompletionItems; overload; static;
    /// <summary>Wie oben, mit Dokumenttext für Postfix-Vorlagen (#188).</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
      const APostfix: TPostfixOptions): TCompletionItems; overload; static;
    /// <summary>Wie oben, gestaffelt (#616): AOnPartial bekommt zuerst den eigenen Gültigkeitsbereich, dann die
    /// Units aus uses; das Ergebnis enthält nur noch den Rest (Importe, nicht verfügbare, Postfix-Vorlagen).
    /// Ohne AOnPartial wie oben.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
      const APostfix: TPostfixOptions; const AOnPartial: TCompletionPartialProc): TCompletionItems; overload; static;
    /// <summary>Wie oben, mit Baum, Resolver, Index, Text, Position und Matching aus ARequest (Code-Review S-01).
    /// </summary>
    class function Collect(ARequest: TCompletionRequest; const APostfix: TPostfixOptions;
      const AOnPartial: TCompletionPartialProc): TCompletionItems; overload; static;
    /// <summary>In einer Klassendeklaration nach "procedure " bzw. "function " (#443): überschreibbare
    /// Methoden der Vorfahren; Übernehmen setzt den Rest der Deklaration mit override und erzeugt den Rumpf
    /// mit inherited. False außerhalb dieses Kontexts.</summary>
    class function OverrideItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
      overload; static;
    /// <summary>Wie oben, mit Baum, Resolver und ReadText aus ARequest (Code-Review S-01).</summary>
    class function OverrideItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; overload;
      static;
    /// <summary>In "property Name: T read " bzw. "write " im Klassenrumpf (#31): Felder vom Typ T und Methoden mit
    /// passender Signatur (read: Funktion mit Ergebnis T und den Indexparametern; write: Prozedur mit den
    /// Indexparametern und einem Parameter vom Typ T), auch geerbte. False außerhalb dieses Kontexts.</summary>
    class function PropertyItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; AMatching: TCompletionMatching; out AItems: TCompletionItems): Boolean;
      overload; static;
    /// <summary>Wie oben, mit Baum, Resolver und Matching aus ARequest.</summary>
    class function PropertyItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; overload;
      static;
    /// <summary>Strg+Leer im String-Literal (#473): „Als resourcestring auslagern“ und, bei gleichem Text,
    /// „Vorhandenen verwenden“. ASnippets: Name als verknüpfter Platzhalter an Stelle und Deklaration. False
    /// außerhalb eines Literals, an unzulässigen Stellen, mit Auslösezeichen oder abgeschaltet.</summary>
    class function ResourceStringItems(ARequest: TCompletionRequest; ASnippets: Boolean;
      out AItems: TCompletionItems): Boolean; static;
    /// <summary>„Feld F&lt;Name&gt; anlegen“, „Get&lt;Name&gt; anlegen“ bzw. „Set&lt;Name&gt; anlegen“ (#467).</summary>
    class function AccessorItems(ARequest: TCompletionRequest; const APropertyName, APropertyType,
      AIndexParameters: string; AIsWrite: Boolean; const APrefix: string): TArray<TCompletionItem>; static;
    /// <summary>Schlüsselwörter für APlace (#31), klein geschrieben.</summary>
    class function Keywords(APlace: TCompletionPlace): TArray<string>; static;
    /// <summary>completionItem.documentationFormat aus initialize (#31): True, wenn der Client Markdown zuerst
    /// nennt; RAD Studio meldet nur plaintext.</summary>
    class function ClientPrefersMarkdown(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>documentation für completionItem/resolve aus Details: Markdown als MarkupContent, sonst Klartext
    /// (ganzer XMLDoc-Text, ersatzweise der Kurztext); nil ohne Doku.</summary>
    class function ResolveDocumentation(const ADetails: TJSONObject; AMarkdown: Boolean): TJSONValue; static;
    /// <summary>Nach "Objekt.Ereignis := " (#444): Methoden der umgebenden Klasse, deren Parameter zum
    /// Methodenzeigertyp des Ereignisses passen, zuletzt "Neue Methode …" mit Deklaration im private-Abschnitt
    /// und leerem Rumpf. False außerhalb dieses Kontexts.</summary>
    class function EventItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
      overload; static;
    /// <summary>Wie oben, mit Baum, Resolver und ReadText aus ARequest.</summary>
    class function EventItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; overload; static;
    /// <summary>Aufzählungen und Mengen (#448). Erwartet die Stelle einen Aufzählungstyp (Zuweisung, Parameter,
    /// Vergleich, case-Zweig), kommen dessen Werte in Deklarationsreihenfolge (Ordinal, bei {$SCOPEDENUMS ON} mit
    /// Typpräfix im InsertText). In einem Mengenkonstruktor ("Anchors := [akLeft, ") kommen alle Werte des
    /// Elementtyps mit SetOf, SetChecked und SetRange; ASetMode ist dann True. False ohne Aufzählungstyp.</summary>
    class function EnumItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
      AMatching: TCompletionMatching; out AItems: TArray<TCompletionItem>; out ASetMode: Boolean): Boolean;
      overload; static;
    /// <summary>Wie oben, mit Baum, Resolver, Index, ReadText und Matching aus ARequest.</summary>
    class function EnumItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
      out ASetMode: Boolean): Boolean; overload; static;
    /// <summary>„case vervollständigen“ (#50): Werte der Aufzählung, über die die case-Anweisung verzweigt, deren
    /// "of" vor APosition endet; APrefix ist "TAlign." bei {$SCOPEDENUMS ON}. False ohne Aufzählungstyp.</summary>
    class function CaseValues(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
      out AValues: TArray<string>; out APrefix: string): Boolean; static;
    /// <summary>Muster fortsetzen (#671): alle Werte des Aufzählungstyps, zu dem der Wert an APosition gehört, in
    /// Deklarationsreihenfolge (ohne Typpräfix). False, wenn dort kein Aufzählungswert steht.</summary>
    class function EnumValuesAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
      out AValues: TArray<string>): Boolean; static;
    /// <summary>Unbekannter Name am Cursor im Rumpf einer Routine (#471): lokale Variable (mit AInlineVar auch als
    /// Inline-var), Feld der Klasse (F-Konvention, die Verwendung wird umbenannt) und, wenn der Name als Wert
    /// dient, Konstante in der implementation. Typ aus der rechten Seite einer Zuweisung, sonst aus dem
    /// erwarteten Typ, sonst ein Platzhalter. False, wenn der Name bekannt ist oder in AKnown genau vorkommt.</summary>
    class function DeclareItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; AInlineVar: Boolean;
      const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean; overload; static;
    /// <summary>Wie oben, mit Baum, Resolver und Index aus ARequest.</summary>
    class function DeclareItems(ARequest: TCompletionRequest; AInlineVar: Boolean;
      const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean; overload; static;
    /// <summary>In der Deklaration einer Klasse mit Interfaces in der Vorfahrenliste (#466), wenn Methoden fehlen.
    /// Leere Zeile bis zum Cursor: je fehlender Methode ein Eintrag mit Kontrollkästchen (Batch), ABatch True.
    /// Angefangenes Wort: je Interface ein Hinweis „n Methoden von I fehlen“ (Hint), der alle seine fehlenden
    /// Methoden anlegt. Deklarationen kommen in den Abschnitt ASection (mit Kommentar "{ I }"), Rümpfe wie bei
    /// #443 ohne inherited. False außerhalb dieses Kontexts oder ohne fehlende Methoden.</summary>
    class function InterfaceItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText; ASection: TCompletionInterfaceSection;
      out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean; overload; static;
    /// <summary>Wie oben, mit Baum, Resolver, ReadText und Abschnitt (Settings.InterfaceSection) aus ARequest.
    /// </summary>
    class function InterfaceItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
      out ABatch: Boolean): Boolean; overload; static;
    /// <summary>„Alle Felder zuweisen (n)“ (#491) hinter "Ausdruck." am Anfang einer Anweisung, wenn der Ausdruck
    /// ein Record oder eine Klasse ist und completion.assignAllFields gilt: je öffentlich beschreibbarem Feld und
    /// jeder Property eine Zuweisung, in Deklarationsreihenfolge; was die folgenden Zeilen schon zuweisen, fällt
    /// weg. Mit ASnippets im Platzhalter-Modus; mehr als 15 Felder kommen als Assignments für die Liste mit
    /// Kontrollkästchen. False außerhalb dieses Kontexts oder ohne Felder.</summary>
    class function AssignAllItem(ARequest: TCompletionRequest; ASnippets: Boolean;
      out AItem: TCompletionItem): Boolean; static;
    /// <summary>Methodenreferenztyp ATypeText, so aufgelöst, wie er in AFromUnit stünde (#468): Deklaration aus
    /// dem Index, Aliase bis TCompletionAnonymous.MaxAliasDepth verfolgt, Typparameter durch die Typargumente
    /// ersetzt; ohne Deklaration im Index die von System.SysUtils (TProc, TFunc, TPredicate). False, wenn
    /// ATypeText kein "reference to procedure/function" ist.</summary>
    class function MethodRefOf(AResolver: TNameResolver; const AFromUnit: TUnitIndex; const ATypeText: string;
      out AMethodRef: TMethodRef): Boolean; static;
    /// <summary>Gerüst einer anonymen Methode (#468), wenn das Argument bzw. die Zuweisung am Cursor einen
    /// Methodenreferenztyp erwartet und completion.anonymousMethods gilt; der Cursor steht ohne Wort oder hinter
    /// einem Anfang von procedure bzw. function. Mit ASnippets im Platzhalter-Modus (/bin/bash im Rumpf). Das Präfix der
    /// Parameter kommt aus ANamingFor bzw. NamingPrefix.</summary>
    class function AnonymousItem(ARequest: TCompletionRequest; ASnippets: Boolean;
      const ANamingFor: TCompletionNamingFunc; out AItem: TCompletionItem): Boolean; static;
    /// <summary>Komponenten des Formulars zur Unit (#455), wenn der Cursor ohne Punkt in einer Methode der
    /// Formularklasse steht. Quelle ist die Formulardatei über AReadText, also der Stand im Designer, solange das
    /// Formular offen ist. Je Komponente ein Feld mit ihrem Typ als Detail und Form = Formularname. Passt der Name
    /// nicht zum Getippten, aber der Typ (eigene Klasse beginnt damit ohne "T", oder ein Vorfahr heißt genau so),
    /// kommt sie mit ByType. False ohne Formular oder außerhalb seiner Methoden.</summary>
    class function ComponentItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText; AMatching: TCompletionMatching;
      out AItems: TArray<TCompletionItem>): Boolean; static;
    /// <summary>Wie ComponentItems, das Formular aber über AForms (z. B. zwischengespeichert, Code-Review P-06).
    /// Außerhalb von Routinen wird AForms nicht gerufen.</summary>
    class function ComponentItemsFromForm(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AForms: TCompletionFormFunc; AMatching: TCompletionMatching;
      out AItems: TArray<TCompletionItem>): Boolean; overload; static;
    /// <summary>Wie oben, mit Baum, Resolver und Matching aus ARequest.</summary>
    class function ComponentItemsFromForm(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
      out AItems: TArray<TCompletionItem>): Boolean; overload; static;
    /// <summary>Cursor im ersten Argument von FieldByName, FindField oder ParamByName an einer Datenmenge der
    /// Unit (#461): die Namen aus der Formulardatei (persistente Felder, Spalten der SQL-Anweisung,
    /// Platzhalter, Params). Jeder Eintrag ersetzt den ganzen String-Inhalt. True auch ohne Namen, denn im
    /// String gibt es sonst nichts vorzuschlagen.</summary>
    class function DataNameItems(const AIndex: ISymbolIndex; const AText, AFileName: string; const APosition: TTextPosition;
      const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean; overload; static;
    /// <summary>Wie oben, mit Index und ReadText aus ARequest.</summary>
    class function DataNameItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; overload; static;
    /// <summary>Freigabe absichern (#489): Nach "Liste := TStringList.Create;" in Zeile APosition.Line „Mit
    /// try…finally absichern“ und, wenn danach noch Zeilen bis zum Routinenende folgen, dieselbe Absicherung bis
    /// dorthin. False, wenn die Anweisung nicht passt (TGuardFree.Check). ANewLine: Ausgelöst durch Enter am
    /// Zeilenende; die Anweisung steht dann in der Zeile davor, und die leere Zeile des Cursors wird ersetzt.</summary>
    class function GuardItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; AStyle: TCompletionFreeStyle; ANewLine: Boolean;
      out AItems: TCompletionItems): Boolean; overload; static;
    /// <summary>Wie oben, mit Baum, Resolver und Freigabe (Settings.FreeStyle) aus ARequest.</summary>
    class function GuardItems(ARequest: TCompletionRequest; ANewLine: Boolean; out AItems: TCompletionItems): Boolean;
      overload; static;
    /// <summary>"Sender." in einem Ereignisbehandler mit "Sender: TObject" (#480): Ist die Methode im Formular
    /// Komponenten zugewiesen, die Mitglieder des nächsten gemeinsamen Vorfahren ihrer Typen. Jeder Eintrag
    /// ersetzt "Sender.Na" (TextEdit) durch die Umwandlung nach ACast und den Namen. False ohne Zuweisung im
    /// Formular, bei bereits umgewandeltem Sender oder wenn der gemeinsame Typ TObject ist.</summary>
    class function SenderItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
      AMatching: TCompletionMatching; ACast: TCompletionSenderCast; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Wie SenderItems, das Formular aber über AForms (Code-Review P-06).</summary>
    class function SenderItemsFromForm(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; const AForms: TCompletionFormFunc;
      AMatching: TCompletionMatching; ACast: TCompletionSenderCast; out AItems: TCompletionItems): Boolean;
      overload; static;
    /// <summary>Wie oben, mit Baum, Resolver, Index, Matching und Typumwandlung (Settings.SenderCast) aus ARequest.
    /// </summary>
    class function SenderItemsFromForm(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
      out AItems: TCompletionItems): Boolean; overload; static;
    class function KindOf(AKind: TIndexSymbolKind): Integer; static;
    /// <summary>Präfix F, A bzw. L für AKind, wenn mindestens 60 % dieser Deklarationen in den Projekt-Units
    /// von AIndex es tragen (#452); sonst ''.</summary>
    class function NamingPrefix(const AIndex: ISymbolIndex; AKind: TNamingKind): string; static;
    /// <summary>Namensvorschläge an der Namensposition einer Deklaration (#452): Namen aus dem Typ mit APrefix,
    /// vergebene mit Ziffer. False, wenn keine Namensposition mit bekanntem Typ vorliegt oder
    /// completion.nameSuggestions aus ist.</summary>
    class function NameItems(ARequest: TCompletionRequest; const ANamingFor: TCompletionNamingFunc;
      out AItems: TCompletionItems): Boolean; static;
    /// <summary>Kontextabhängige Code-Vorlagen (#51) für die Zeile von APosition: prop, changed, create, free.
    /// Mit ASnippetSupport als LSP-Snippet, sonst als Klartext ohne Platzhalter.</summary>
    class function ContextItems(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>; const AText: string;
      const APosition: TTextPosition; AMatching: TCompletionMatching;
      ASnippetSupport: Boolean): TArray<TCompletionItem>; overload; static;
    /// <summary>Wie oben, mit Text, Position, Index und Matching aus ARequest.</summary>
    class function ContextItems(ARequest: TCompletionRequest; const ANamespaces: TArray<string>;
      ASnippetSupport: Boolean): TArray<TCompletionItem>; overload; static;
    /// <summary>Meldet der Client textDocument.completion.completionItem.snippetSupport?</summary>
    class function ClientSupportsSnippets(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>CompletionList des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AItems: TCompletionItems): TJSONObject; overload; static;
    /// <summary>CompletionItem[]; AFirstSort: sortText des ersten Eintrags (bei Teilergebnissen fortlaufend).</summary>
    class function ToJson(const AItems: TArray<TCompletionItem>; AFirstSort: Integer): TJSONArray; overload; static;
    /// <summary>Details zur Deklaration an APosition (Namensposition) in AText für das Detailpanel
    /// von Atlas (#405, #424): declaration, unit, container, visibility, directives, deprecated,
    /// summary, params, returns, exceptions, remarks als Klartext, dazu documentation strukturiert
    /// samt Fundorten der Verweise und documentationText (#654). AReadText liest andere Dateien
    /// für &lt;inheritdoc/&gt;. Der Aufrufer übernimmt das Objekt.</summary>
    class function Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText): TJSONObject; overload; static;
    /// <summary>Wie oben mit AReadText = nil.</summary>
    class function Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
      const APosition: TTextPosition): TJSONObject; overload; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Liest Dateien für completionItem/resolve; ohne Zuweisung keine Details.</summary>
    property ReadText: TCompletionReadText read FReadText write FReadText;
    /// <summary>Auswahl je Dokument; ohne Zuweisung unscharf.</summary>
    property MatchingFor: TCompletionMatchingFunc read FMatchingFor write FMatchingFor;
    /// <summary>Abschnitt für Interface-Methoden (#466), Typumwandlung von Sender (#480); ohne Zuweisung die
    /// Standardwerte.</summary>
    property SettingsFor: TCompletionSettingsFunc read FSettingsFor write FSettingsFor;
    /// <summary>Schnellbefehle nach "/" am Zeilenanfang (#293); ohne Zuweisung alle eingeschaltet.</summary>
    property SlashCommandsFor: TSlashCommandsProvider read FSlashCommandsFor write FSlashCommandsFor;
    /// <summary>Regeln, die in einer Zeile treffen, für /ignore (#297); ohne Zuweisung der ganze Katalog.</summary>
    property RuleIdsFor: TSlashRuleIdsFunc read FRuleIdsFor write FRuleIdsFor;
    /// <summary>Postfix-Vorlagen je Dokument (#188); ohne Zuweisung an und mit Inline-Variable.</summary>
    property PostfixFor: TPostfixOptionsFunc read FPostfixFor write FPostfixFor;
    /// <summary>„with auflösen“ auf dem Wort with (#50); ohne Zuweisung kein Eintrag.</summary>
    property WithFor: TCompletionWithFunc read FWithFor write FWithFor;
    /// <summary>„Methode aus Aufruf anlegen“ (#472); ohne Zuweisung kein Eintrag.</summary>
    property CreateFor: TCompletionCreateFunc read FCreateFor write FCreateFor;
    /// <summary>Präfix der Namensvorschläge (#452); ohne gilt NamingPrefix über den Index der Anfrage.</summary>
    property NamingFor: TCompletionNamingFunc read FNamingFor write FNamingFor;
    /// <summary>Anzeige von XMLDoc (#654) als data.atlas.xmlDoc; ohne Zuweisung fehlt das Feld.</summary>
    property HintsFor: TDocHintsProvider read FHintsFor write FHintsFor;
    /// <summary>„Parameter abgleichen“ in ///-Blöcken (#88); ohne Zuweisung eingeschaltet.</summary>
    property DocCommentsFor: TCompletionEnabledFunc read FDocCommentsFor write FDocCommentsFor;
    /// <summary>Bedingte Symbole in Direktiven und Schalter directives.completion (#102); ohne Zuweisung an,
    /// nur mit den Symbolen der Datei.</summary>
    property SymbolsFor: TConditionalContextFunc read FSymbolsFor write FSymbolsFor;
    /// <summary>Für Teilergebnisse über $/progress (#616); ohne Zuweisung kommt alles in der Antwort.</summary>
    property Notify: TCompletionNotifyProc read FNotify write FNotify;
    /// <summary>Zeiten je Anfrage (#616); ohne Zuweisung keine Messung.</summary>
    property Log: TCompletionLogProc read FLog write FLog;
    /// <summary>Client versteht Snippets (#51); sonst gehen Vorlagen als Klartext. Aus initialize.</summary>
    property SnippetSupport: Boolean read FSnippetSupport write FSnippetSupport;
    /// <summary>Doku in completionItem/resolve als Markdown statt Klartext (#31). Aus initialize.</summary>
    property DocumentationMarkdown: Boolean read FDocumentationMarkdown write FDocumentationMarkdown;
    /// <summary>Eigene Postfix-Vorlagen (#188): {"templates": [{"key", "description", "body", "type"}]}.</summary>
    class function ParsePostfixTemplates(const AParams: TJSONValue): TArray<TPostfixTemplate>; static;
    /// <summary>Setzt die eigenen Postfix-Vorlagen; sonst über atlas/postfixTemplates.</summary>
    procedure SetCustomPostfix(const ATemplates: TArray<TPostfixTemplate>);
    function CustomPostfix: TArray<TPostfixTemplate>;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Internals.CompletionSource,
  Atlas.Common.Lsp.CompletionJson,
  Atlas.Common.Index.Files,
  System.Math,
  System.StrUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.CompletionUses,
  Atlas.Common.Lsp.CompletionInherited,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.AssignFields,
  Atlas.Common.Editing.DeclareUnknown,
  Atlas.Common.Editing.CreateMethod,
  Atlas.Common.Editing.NameSuggestions,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Lsp.CompilerDirectives,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Lsp.SignatureHelp,
  System.RegularExpressions,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Common.Editing.ResourceStrings,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.SlashMenu,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Lsp.CompletionEnums,
  Atlas.Common.Lsp.CompletionGenerics,
  Atlas.Common.Lsp.CompletionAttributes,
  Atlas.Common.Lsp.CompletionExceptions,
  Atlas.Common.Lsp.CompletionSyntax,
  Atlas.Common.Editing.DataFieldNames,
  Atlas.Common.Lsp.CompletionDebugDisplay,
  Atlas.Common.Editing.GuardFree,
  Atlas.Common.Editing.ContextSnippets,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.DocComments,
  Atlas.Text.Lines;

const
  /// <summary>Art der Stelle im Diagnoselog (#647).</summary>
  ContextCodes: array[TCompletionContextKind] of string = ('none', 'scope', 'memberAccess', 'uses');
  // Schlüsselwörter je Stelle (#31).
  StatementKeywords: array[0..34] of string = ('begin', 'end', 'if', 'then', 'else', 'case', 'of', 'for', 'to',
    'downto', 'do', 'while', 'repeat', 'until', 'try', 'except', 'finally', 'on', 'raise', 'with', 'inherited',
    'var', 'const', 'nil', 'not', 'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as');
  DeclarationKeywords: array[0..18] of string = ('procedure', 'function', 'constructor', 'destructor', 'var',
    'const', 'type', 'begin', 'end', 'class', 'record', 'uses', 'implementation', 'initialization', 'finalization',
    'resourcestring', 'threadvar', 'label', 'exports');
  ClassBodyKeywords: array[0..23] of string = ('procedure', 'function', 'constructor', 'destructor', 'property',
    'private', 'protected', 'public', 'published', 'strict', 'class', 'var', 'const', 'type', 'end', 'case',
    'virtual', 'override', 'overload', 'abstract', 'reintroduce', 'dynamic', 'static', 'message');
  TypeKeywords: array[0..7] of string = ('string', 'array', 'set', 'record', 'packed', 'procedure', 'function',
    'reference');

/// <summary>Bedingte Symbole nach {$IFDEF , {$IFNDEF , {$DEFINE , {$UNDEF und in Defined( (#102): Herkunft als
/// Detail, Symbole, die hier nicht gelten, abgeschwächt am Ende.</summary>
function SymbolItems(ARequest: TCompletionRequest; const AContext: TConditionalContext;
  out AItems: TCompletionItems): Boolean;
var
  Prefix: string;
  Symbol: TConditionalSymbol;
  Item: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := TConditionalSymbols.IsSymbolContext(ARequest.LineBefore, Prefix);
  if not Result or not AContext.CompletionEnabled then
  begin
    Exit;
  end;
  for Symbol in TConditionalSymbols.Candidates(ARequest.Text, AContext) do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Symbol.Name;
    Item.Kind := KindConstant;
    Item.Detail := Symbol.Detail;
    Item.Unavailable := not Symbol.Active;
    AItems.Items := AItems.Items + [Item];
  end;
end;

/// <summary>Vorschläge in einer offenen Direktive (#102); False außerhalb.</summary>
function DirectiveItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  Names: TArray<string>;
  IsWarning: Boolean;
  Name: string;
  Item: TCompletionItem;
  Info: TDirectiveInfo;
begin
  AItems := Default(TCompletionItems);
  Result := TCompilerDirectives.CompletionAt(ARequest.LineBefore, Names, IsWarning);
  if not Result then
  begin
    Exit;
  end;
  for Name in Names do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Name;
    Item.Kind := KindKeyword;
    if IsWarning then
    begin
      Item.Detail := 'Compiler-Warnung';
    end
    else if TCompilerDirectives.Find(Name, Info) then
    begin
      Item.Detail := Info.Text;
    end;
    AItems.Items := AItems.Items + [Item];
  end;
end;

function TypeUnitEdits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, ATypeName, ALineBreak: string; AOffset: Integer): TArray<TRuleEdit>; forward;

/// <summary>Kennungen des eingebauten Regelkatalogs für /ignore (#293); sonst leer.</summary>
function RuleIds(AKind: TSlashArgumentKind): TArray<string>;
var
  Catalog: TRuleCatalog;
  Entry: TRuleCatalogEntry;
begin
  Result := nil;
  if AKind <> TSlashArgumentKind.Rules then
  begin
    Exit;
  end;
  Catalog := TRuleCatalog.Create(RuleCatalogBaseJson);
  try
    for Entry in Catalog.Entries do
    begin
      Result := Result + [Entry.Id];
    end;
  finally
    Catalog.Free;
  end;
end;

/// <summary>Für /ignore nur die Regeln, die in der Zeile unter dem Befehl treffen (#297); ohne Auskunft der
/// Katalog.</summary>
function RuleIdsBelow(ARequest: TCompletionRequest; AKind: TSlashArgumentKind;
  const ARuleIdsAt: TSlashRuleIdsFunc): TArray<string>;
var
  Lines: TArray<string>;
  LineBreak: string;
  Line: Integer;
begin
  if (AKind = TSlashArgumentKind.Rules) and Assigned(ARuleIdsAt) then
  begin
    // Ohne die Befehlszeile prüfen, wie nach dem Ausführen.
    Lines := TTextLines.SplitLines(ARequest.Text, LineBreak);
    Line := ARequest.Position.Line;
    if (Line >= 0) and (Line <= High(Lines)) then
    begin
      Lines[Line] := StringOfChar(' ', Length(Lines[Line]));
    end;
    if ARuleIdsAt(ARequest.Uri, TTextLines.JoinLines(Lines, LineBreak), Line + 1, Result) then
    begin
      Exit;
    end;
  end;
  Result := RuleIds(AKind);
end;

function SlashItems(ARequest: TCompletionRequest; const ADisabled: TArray<string>;
  const ARuleIdsAt: TSlashRuleIdsFunc; out AItems: TCompletionItems): Boolean;
var
  Before, Name, Arguments, Choice: string;
  Choices: TArray<string>;
  Command: TSlashCommand;
  Item: TCompletionItem;
  Kind: TSlashArgumentKind;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  AItems := Default(TCompletionItems);
  // "/name" ohne Argumente vor dem Cursor; danach vervollständigen die Befehle selbst (#294 ff.), /sort und
  // /filter mit Sammlungen und Mitgliedern des Elementtyps (#319).
  Before := ARequest.LineBefore;
  if Trim(Before) = '/' then
  begin
    Name := '';
  end
  else if not TSlashCommandRegistry.Split(Before, Name, Arguments) then
  begin
    Exit(False);
  end
  else if (Arguments <> '') or (Before[Length(Before)] = ' ') then
  begin
    if MatchText(Name, ADisabled) or
      not TSlashCommandRegistry.IsCodeLine(TPascalLexer.Tokenize(ARequest.Text), ARequest.Position.Line) then
    begin
      Exit(False);
    end;
    Kind := TSlashMenu.ArgumentKind(Name, Arguments);
    Choices := TSlashMenu.ArgumentChoices(ARequest.Text, ARequest.Position.Line, Name, Arguments, ARequest.Index,
      RuleIdsBelow(ARequest, Kind, ARuleIdsAt));
    Tree := nil;
    Resolver := nil;
    try
      // Typen aus nicht eingebundenen Units bringen ihren uses-Eintrag mit (#294, #180); dieser Fall läuft vor
      // dem Syntaxbaum der Anfrage, daher ein eigener.
      if (Kind in [TSlashArgumentKind.Types, TSlashArgumentKind.Interfaces, TSlashArgumentKind.Exceptions]) and
        (ARequest.Index <> nil) and (Length(Choices) > 0) then
      begin
        Tree := TSyntaxTreeCache.Parse(ARequest.Text);
        Resolver := TNameResolver.Create(ARequest.Index);
      end;
      for Choice in Choices do
      begin
        Item := Default(TCompletionItem);
        Item.Name := Choice;
        Item.Kind := KindField;
        Item.Detail := '/' + Name;
        if Resolver <> nil then
        begin
          Item.AdditionalEdits := TypeUnitEdits(Resolver, ARequest.Index, Tree, ARequest.FileName, Choice,
            ARequest.LineBreak, ARequest.OffsetAt(ARequest.Position));
        end;
        AItems.Items := AItems.Items + [Item];
      end;
    finally
      Resolver.Free;
      Tree.Free;
    end;
    Exit(Length(Choices) > 0);
  end;
  if not TSlashCommandRegistry.IsCodeLine(TPascalLexer.Tokenize(ARequest.Text), ARequest.Position.Line) then
  begin
    Exit(False);
  end;
  for Command in TSlashCommandRegistry.Shared.Matching(Name, ADisabled) do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Command.Name;
    Item.Kind := KindKeyword;
    Item.Detail := Command.Summary + ' – ' + Command.Example;
    Item.InsertText := Command.Name + ' ';
    AItems.Items := AItems.Items + [Item];
  end;
  Result := True;
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Index der öffnenden Klammer zu ")" an AIndex; -1, wenn sie fehlt.</summary>
function OpeningParen(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AIndex;
  while Result >= 0 do
  begin
    if ATokens[Result].IsSymbol(')') then
    begin
      Inc(Depth);
    end
    else if ATokens[Result].IsSymbol('(') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end
    else if ATokens[Result].IsSymbol(';') or ATokens[Result].IsKeyword('begin') then
    begin
      Break;
    end;
    Dec(Result);
  end;
  Result := -1;
end;

function InUsesClause(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Token: TPascalToken;
begin
  // Rückwärts über Unit-Namen, Punkte, Kommas und "in 'Datei'" bis zum uses.
  while AIndex >= 0 do
  begin
    Token := ATokens[AIndex];
    if Token.IsKeyword('uses') or Token.IsKeyword('contains') or Token.IsKeyword('requires') then
    begin
      Exit(True);
    end;
    if not ((Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.StringLiteral]) or
      Token.IsSymbol('.') or Token.IsSymbol(',') or Token.IsKeyword('in') or IsTrivia(Token)) then
    begin
      Exit(False);
    end;
    Dec(AIndex);
  end;
  Result := False;
end;

{ TLspCompletion }

function TLspCompletion.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspCompletion.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspCompletion.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspCompletion.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FCacheLock := TObject.Create;
  FForms := TFormSnapshotCache.Create;
  RegisterCases;
end;

destructor TLspCompletion.Destroy;
begin
  FForms.Free;
  FCacheLock.Free;
  inherited;
end;

function TLspCompletion.ReadCached(const AFileName: string; out AText: string): Boolean;
var
  Document: ITextDocument;
  Stamp: TDateTime;
begin
  // Geöffnete Dateien immer im Stand des Editors; sonst gilt der Zwischenspeicher, solange die Datei
  // unverändert ist.
  if ((FStore <> nil) and FStore.TryGet(TDocumentUris.FromPath(AFileName), Document)) or
    not FileAge(AFileName, Stamp) then
  begin
    Exit(FReadText(AFileName, AText));
  end;
  TMonitor.Enter(FCacheLock);
  try
    if SameText(FCacheFile, AFileName) and (FCacheStamp = Stamp) then
    begin
      AText := FCacheText;
      Exit(True);
    end;
  finally
    TMonitor.Exit(FCacheLock);
  end;
  Result := FReadText(AFileName, AText);
  if not Result then
  begin
    Exit;
  end;
  TMonitor.Enter(FCacheLock);
  try
    FCacheFile := AFileName;
    FCacheStamp := Stamp;
    FCacheText := AText;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

procedure TLspCompletion.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
  ADispatcher.RegisterConcurrentRequest(ResolveMethod, HandleResolve);
  ADispatcher.RegisterNotification(PostfixTemplatesMethod, HandlePostfixTemplates);
end;

class function TLspCompletion.ParsePostfixTemplates(const AParams: TJSONValue): TArray<TPostfixTemplate>;
var
  Templates, Value: TJSONValue;
  Item: TJSONObject;
  Key, Body: string;
begin
  Result := nil;
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  Templates := TJSONObject(AParams).GetValue('templates');
  if not (Templates is TJSONArray) then
  begin
    Exit;
  end;
  for Value in TJSONArray(Templates) do
  begin
    if not (Value is TJSONObject) then
    begin
      Continue;
    end;
    Item := TJSONObject(Value);
    Key := Item.GetValue<string>('key', '');
    Body := Item.GetValue<string>('body', '');
    // Nur Kürzel aus Buchstaben, Ziffern und _; sie stehen hinter einem Punkt.
    if (Key = '') or (Body = '') or not IsValidIdent(Key) then
    begin
      Continue;
    end;
    Result := Result + [TPostfixTemplate.Custom(Key, Item.GetValue<string>('description', ''), Body,
      Item.GetValue<string>('type', ''))];
  end;
end;

procedure TLspCompletion.HandlePostfixTemplates(const AParams: TJSONValue);
begin
  SetCustomPostfix(ParsePostfixTemplates(AParams));
end;

procedure TLspCompletion.SetCustomPostfix(const ATemplates: TArray<TPostfixTemplate>);
begin
  TMonitor.Enter(FCacheLock);
  try
    FCustomPostfix := ATemplates;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

function TLspCompletion.CustomPostfix: TArray<TPostfixTemplate>;
begin
  TMonitor.Enter(FCacheLock);
  try
    Result := FCustomPostfix;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

class function TLspCompletion.Capability: TJSONObject;
var
  Triggers: TJSONArray;
begin
  Triggers := TJSONArray.Create;
  Triggers.Add('.');
  // {$ startet die Vervollständigung von Direktiven (#102).
  Triggers.Add('$');
  // "/" am Zeilenanfang listet die Schnellbefehle (#293).
  Triggers.Add('/');
  Result := TJSONObject.Create;
  Result.AddPair('triggerCharacters', Triggers);
  // Details für das Detailpanel von Atlas erst für den gewählten Eintrag (#405, #424).
  Result.AddPair('resolveProvider', TJSONBool.Create(True));
end;

/// <summary>Anweisung, Deklaration oder Klassenrumpf an AOffset (#31): innerster Knoten, dann nach außen die
/// erste prägende Art.</summary>
function PlaceAt(ARoot: TSyntaxNode; AOffset: Integer): TCompletionPlace;
var
  Node, Child: TSyntaxNode;
  Index: Integer;
  Found: Boolean;
begin
  Result := TCompletionPlace.Unknown;
  if ARoot = nil then
  begin
    Exit;
  end;
  Node := ARoot;
  repeat
    Found := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      Child := Node[Index];
      if (Child.StartOffset <= AOffset) and (AOffset <= Child.EndOffset) then
      begin
        Node := Child;
        Found := True;
        Break;
      end;
    end;
  until not Found;
  while Node <> nil do
  begin
    if Node.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
      TSyntaxKind.InterfaceType, TSyntaxKind.HelperType] then
    begin
      Exit(TCompletionPlace.ClassBody);
    end;
    if Node.Kind in [TSyntaxKind.Block .. TSyntaxKind.EmptyStatement] then
    begin
      Exit(TCompletionPlace.Statement);
    end;
    Node := Node.Parent;
  end;
  Result := TCompletionPlace.Declaration;
end;

/// <summary>An dieser Stelle kann nur ein Typ stehen (#31): nach "is", "is not", "as", in der Vorfahrenliste
/// "class(…" und nach ":" in Deklarationen (in Anweisungen nur bei inline var/const und "on E:").
/// AKeywords: auch string, array … anbieten (nur nach ":").</summary>
function TypePosition(const ATokens: TArray<TPascalToken>; ALast: Integer; APlace: TCompletionPlace;
  out AKeywords: Boolean): Boolean;
var
  Index, Before: Integer;
begin
  AKeywords := False;
  Result := False;
  if ALast < 0 then
  begin
    Exit;
  end;
  if ATokens[ALast].IsKeyword('is') or ATokens[ALast].IsKeyword('as') then
  begin
    Exit(True);
  end;
  if ATokens[ALast].IsKeyword('not') then
  begin
    Before := PreviousIndex(ATokens, ALast);
    Exit((Before >= 0) and ATokens[Before].IsKeyword('is'));
  end;
  if ATokens[ALast].IsSymbol(':') then
  begin
    if APlace <> TCompletionPlace.Statement then
    begin
      Result := True;
    end
    else
    begin
      // var A, B: | bzw. on E: |
      Index := PreviousIndex(ATokens, ALast);
      while (Index >= 0) and not Result and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or
        ATokens[Index].IsSymbol(',')) do
      begin
        Before := PreviousIndex(ATokens, Index);
        Result := SameText(ATokens[Index].Text, 'on') and (Before >= 0) and
          not ATokens[Before].IsSymbol('.');
        Index := Before;
      end;
      Result := Result or (Index >= 0) and (ATokens[Index].IsKeyword('var') or ATokens[Index].IsKeyword('const'));
    end;
    AKeywords := Result;
    Exit;
  end;
  // TFoo = class(TBasis, IFoo, |
  Index := ALast;
  while (Index >= 0) and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol(',') or
    ATokens[Index].IsSymbol('.')) do
  begin
    Index := PreviousIndex(ATokens, Index);
  end;
  if (Index < 0) or not ATokens[Index].IsSymbol('(') then
  begin
    Exit;
  end;
  Before := PreviousIndex(ATokens, Index);
  Result := (Before >= 0) and (ATokens[Before].IsKeyword('class') or ATokens[Before].IsKeyword('interface') or
    ATokens[Before].IsKeyword('object') or ATokens[Before].IsKeyword('dispinterface'));
end;

class function TLspCompletion.Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext;
var
  Tokens: TArray<TPascalToken>;
  Index, Last: Integer;
  Token: TPascalToken;
  Names: TList<string>;
  Site: TGenericArgSite;
  ExceptionSite: TExceptionSite;
  Before: Integer;
begin
  Result := Default(TCompletionContext);
  Result.Kind := TCompletionContextKind.None;
  if ATree = nil then
  begin
    Exit;
  end;
  Tokens := ATree.Tokens;
  // Letztes Token, das vor dem Cursor beginnt.
  Last := -1;
  for Index := 0 to High(Tokens) do
  begin
    if ComparePositions(Tokens[Index].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    Last := Index;
  end;
  Result.Offset := 0;
  if Last >= 0 then
  begin
    Token := Tokens[Last];
    Result.Offset := Token.Offset + Length(Token.Text);
    if ComparePositions(APosition, Token.EndPos) < 0 then
    begin
      // "TFoo<|>": Der Lexer liest "<>" als ein Token; Typargument wie nach "TFoo<" (#450).
      Before := PreviousIndex(Tokens, Last);
      if Token.IsSymbol('<>') and (APosition.Character = Token.StartPos.Character + 1) and (Before >= 0) and
        (Tokens[Before].Kind = TPascalTokenKind.Identifier) then
      begin
        Result.Kind := TCompletionContextKind.Scope;
        Result.Offset := Token.Offset + 1;
        Result.Place := PlaceAt(ATree.Root, Result.Offset);
        Result.Generic := True;
        Result.GenericOwnerPos := Tokens[Before].StartPos;
        Result.GenericParam := 0;
        Exit;
      end;
      // Cursor mitten in einem Token: in Kommentaren, Strings und Zahlen nichts anbieten.
      if Token.Kind <> TPascalTokenKind.Identifier then
      begin
        Exit;
      end;
    end;
    if (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      (ComparePositions(APosition, Token.EndPos) <= 0) then
    begin
      // Angefangener Name; auch ein halbes Schlüsselwort wie "beg" gilt als Anfang.
      if Token.Kind = TPascalTokenKind.Identifier then
      begin
        Result.Prefix := CleanName(Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character));
      end
      else
      begin
        Result.Prefix := Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character);
      end;
      Result.Offset := Token.Offset;
      Last := PreviousIndex(Tokens, Last);
    end
    else if IsTrivia(Token) and (ComparePositions(APosition, Token.EndPos) <= 0) and
      Token.Text.StartsWith('//') then
    begin
      // Zeilenkommentar reicht bis zum Zeilenende.
      Exit;
    end
    else if IsTrivia(Token) then
    begin
      Last := PreviousIndex(Tokens, Last + 1);
    end;
  end;

  if (Last >= 0) and Tokens[Last].IsSymbol('.') then
  begin
    Names := TList<string>.Create;
    try
      Index := PreviousIndex(Tokens, Last);
      while Index >= 0 do
      begin
        // Foo(1). oder TFoo(X).: Klammern überspringen, das Glied davor ist ein Aufruf bzw. eine
        // Typumwandlung (#188).
        if Tokens[Index].IsSymbol(')') then
        begin
          Index := OpeningParen(Tokens, Index);
          if Index < 0 then
          begin
            Exit;
          end;
          Index := PreviousIndex(Tokens, Index);
          if (Index < 0) or (Tokens[Index].Kind <> TPascalTokenKind.Identifier) then
          begin
            Exit;
          end;
          if Names.Count = 0 then
          begin
            Result.Called := True;
          end;
        end;
        if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        begin
          Break;
        end;
        Names.Insert(0, CleanName(Tokens[Index].Text));
        Result.ChainStart := Tokens[Index].StartPos;
        Index := PreviousIndex(Tokens, Index);
        if (Index >= 0) and Tokens[Index].IsSymbol('.') then
        begin
          Index := PreviousIndex(Tokens, Index);
        end
        else
        begin
          Break;
        end;
      end;
      // 1. oder "a".: nicht auflösbar.
      if (Names.Count = 0) or (Index >= 0) and Tokens[Index].IsSymbol('.') then
      begin
        Exit;
      end;
      if InUsesClause(Tokens, Last) then
      begin
        // uses System.Sys…: der Anfang gehört zum Unit-Namen.
        Result.Kind := TCompletionContextKind.UsesClause;
        Result.Prefix := string.Join('.', Names.ToArray) + '.' + Result.Prefix;
        Exit;
      end;
      Result.Kind := TCompletionContextKind.Member;
      Result.Names := Names.ToArray;
      Result.Offset := Tokens[Last].Offset;
      Result.DotPos := Tokens[Last].StartPos;
    finally
      Names.Free;
    end;
    Exit;
  end;
  if (Last >= 0) and InUsesClause(Tokens, Last) then
  begin
    Result.Kind := TCompletionContextKind.UsesClause;
    Exit;
  end;
  Result.Kind := TCompletionContextKind.Scope;
  // Kontexte ohne Typauflösung (#31).
  Result.Place := PlaceAt(ATree.Root, Result.Offset);
  if (Last >= 0) and Tokens[Last].IsKeyword('inherited') then
  begin
    Result.Filter := TCompletionFilter.InheritedCall;
  end
  else if TypePosition(Tokens, Last, Result.Place, Result.TypeKeywords) then
  begin
    Result.Filter := TCompletionFilter.Types;
  end;
  // Attribut nach "[" vor einer Deklaration (#465); ob es gilt, entscheidet Collect nach der Einstellung.
  if (Result.Filter = TCompletionFilter.Any) and TCompletionAttributes.SiteAt(Tokens, Last) then
  begin
    Result.Attribute := True;
    Result.Filter := TCompletionFilter.Types;
    Exit;
  end;
  // Exception-Klassen nach "raise " und "on E: " (#483); ob es gilt, entscheidet Collect nach der Einstellung.
  if (Result.Filter <> TCompletionFilter.InheritedCall) and TCompletionExceptions.SiteAt(Tokens, Last,
    ExceptionSite) then
  begin
    Result.Exceptions := True;
    Result.ExceptionToken := Last;
    Result.Filter := TCompletionFilter.Types;
    Exit;
  end;
  // Typargument nach "TFoo<" (#450); ob TFoo ein generischer Typ ist, klärt Collect.
  if Result.Filter <> TCompletionFilter.InheritedCall then
  begin
    Site := TCompletionGenerics.SiteAt(Tokens, Last);
    if Site.Found then
    begin
      Result.Generic := True;
      Result.GenericOwnerPos := Site.OwnerPosition;
      Result.GenericParam := Site.Parameter;
    end;
  end;
end;

class function TLspCompletion.KindOf(AKind: TIndexSymbolKind): Integer;
begin
  Result := CompletionKindOf(AKind);
end;

/// <summary>Erwarteter Typ am Cursor (siehe TLspCompletion.ExpectedType); mit AWithArgs bei Zuweisungen samt
/// Typargumenten der Variablen.</summary>
function ExpectedTypeOf(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; AWithArgs: Boolean): string;
var
  Site: TCallSite;
  Callee, Target: TResolvedSymbol;
  Tokens: TArray<TPascalToken>;
  Index, Last: Integer;
  Names: TArray<string>;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Slot: TEnumValueSlot;
begin
  Result := '';
  if ATree = nil then
  begin
    Exit;
  end;
  // Argument eines Aufrufs: Typ des aktiven Parameters (erste passende Überladung).
  Site := TLspSignatureHelp.CallSiteAt(ATree, APosition);
  if Site.Found then
  begin
    Callee := AResolver.Resolve(ATree, AFileName, Site.NamePosition);
    // Mitglied einer generischen Instanz (TBox<TKunde>.Where): Typparameter der Klasse einsetzen (#468).
    if Callee.Found and (Site.ActiveParameter < Length(Callee.ParamTypes)) then
    begin
      Result := TInterfaceStubs.SubstituteWords(Callee.ParamTypes[Site.ActiveParameter], Callee.Bindings);
    end;
    Exit;
  end;
  // Zuweisung: "Ziel := A.B.Anf|" – rückwärts über die Kette rechts bis zum ":=".
  Tokens := ATree.Tokens;
  Last := -1;
  for Index := 0 to High(Tokens) do
  begin
    if ComparePositions(Tokens[Index].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    Last := Index;
  end;
  Index := PreviousIndex(Tokens, Last + 1);
  if (Index >= 0) and (Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (ComparePositions(APosition, Tokens[Index].EndPos) <= 0) then
  begin
    Index := PreviousIndex(Tokens, Index);
  end;
  while (Index >= 0) and Tokens[Index].IsSymbol('.') do
  begin
    Index := PreviousIndex(Tokens, Index);
    if (Index < 0) or (Tokens[Index].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    Index := PreviousIndex(Tokens, Index);
  end;
  if (Index < 0) or not Tokens[Index].IsSymbol(':=') then
  begin
    // Vergleich ("Shape.Kind = ") und case-Zweig (#448): Typ der Kette. Ein Typ selbst steht bei typisierten
    // Konstanten und Standardwerten ("const C: TAlign = ", "A: TAlign = ").
    if TCompletionEnums.ValueSlot(Tokens, APosition, Slot) then
    begin
      Target := AResolver.ResolveChain(ATree, AFileName, Slot.Names, Slot.Offset);
      if Target.Found and Target.IsType then
      begin
        Result := Target.Name;
      end
      else if Target.Found then
      begin
        Result := Target.TypeName;
      end;
    end;
    Exit;
  end;
  Last := Tokens[Index].Offset;
  Index := PreviousIndex(Tokens, Index);
  Names := nil;
  while (Index >= 0) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) do
  begin
    Names := [CleanName(Tokens[Index].Text)] + Names;
    Index := PreviousIndex(Tokens, Index);
    if (Index >= 0) and Tokens[Index].IsSymbol('.') then
    begin
      Index := PreviousIndex(Tokens, Index);
    end
    else
    begin
      Break;
    end;
  end;
  if Names = nil then
  begin
    Exit;
  end;
  Target := AResolver.ResolveChain(ATree, AFileName, Names, Last);
  if Target.Found and not Target.IsType and (Target.SymbolKind <> TIndexSymbolKind.Routine) and
    (Target.SymbolKind <> TIndexSymbolKind.Method) then
  begin
    Result := Target.TypeName;
    if AWithArgs and (Result <> '') and (Target.TypeArgs <> '') then
    begin
      Result := Result + '<' + Target.TypeArgs + '>';
    end;
  end;
  // Result: Rückgabetyp der umgebenden Funktion.
  if (Result = '') and (Length(Names) = 1) and SameText(Names[0], 'Result') then
  begin
    UnitIndex := AResolver.ExtractedUnit(ATree, AFileName);
    for Symbol in UnitIndex.Symbols do
    begin
      if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and (Symbol.TypeName <> '') and
        (Symbol.Range.StartPos.Line < APosition.Line) and (Symbol.Range.EndPos.Line >= APosition.Line) then
      begin
        Result := Symbol.TypeName;
      end;
    end;
  end;
end;

class function TLspCompletion.ExpectedType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
begin
  Result := ExpectedTypeOf(AResolver, ATree, AFileName, APosition, False);
end;

class function TLspCompletion.ExpectedFullType(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition): string;
begin
  Result := ExpectedTypeOf(AResolver, ATree, AFileName, APosition, True);
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition): TCompletionItems;
begin
  Result := Collect(AResolver, AIndex, ATree, AFileName, APosition, TCompletionMatching.Fuzzy);
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; AMatching: TCompletionMatching): TCompletionItems;
var
  Postfix: TPostfixOptions;
begin
  Postfix := TPostfixOptions.Default;
  Postfix.Enabled := False;
  Result := Collect(AResolver, AIndex, ATree, AFileName, '', APosition, AMatching, Postfix);
end;

{ TPostfixOptions }

class function TPostfixOptions.Default: TPostfixOptions;
begin
  Result := System.Default(TPostfixOptions);
  Result.Enabled := True;
  Result.InlineVar := True;
end;

class function TLspCompletion.ClientSupportsSnippets(const AInitializeParams: TJSONObject): Boolean;
var
  Value: Boolean;
begin
  Result := (AInitializeParams <> nil) and AInitializeParams.TryGetValue<Boolean>(
    'capabilities.textDocument.completion.completionItem.snippetSupport', Value) and Value;
end;

class function TLspCompletion.ClientPrefersMarkdown(const AInitializeParams: TJSONObject): Boolean;
const
  Path: array[0..4] of string = ('capabilities', 'textDocument', 'completion', 'completionItem',
    'documentationFormat');
var
  Node: TJSONValue;
  Key: string;
begin
  Result := False;
  Node := AInitializeParams;
  for Key in Path do
  begin
    if not (Node is TJSONObject) then
    begin
      Exit;
    end;
    Node := TJSONObject(Node).GetValue(Key);
  end;
  Result := (Node is TJSONArray) and (TJSONArray(Node).Count > 0) and (TJSONArray(Node).Items[0] is TJSONString) and
    SameText(TJSONString(TJSONArray(Node).Items[0]).Value, 'markdown');
end;

class function TLspCompletion.ResolveDocumentation(const ADetails: TJSONObject; AMarkdown: Boolean): TJSONValue;
var
  Text: string;
  Markup: TJSONObject;
begin
  Result := nil;
  if ADetails = nil then
  begin
    Exit;
  end;
  if AMarkdown and ADetails.TryGetValue<string>('documentationMarkdown', Text) and (Text <> '') then
  begin
    Markup := TJSONObject.Create;
    Markup.AddPair('kind', 'markdown');
    Markup.AddPair('value', Text);
    Exit(Markup);
  end;
  // Klartext (RAD Studio: documentationFormat ["plaintext"]): ganzer Text, sonst der Kurztext.
  if (ADetails.TryGetValue<string>('documentationText', Text) and (Text <> '')) or
    (ADetails.TryGetValue<string>('summary', Text) and (Text <> '')) then
  begin
    Result := TJSONString.Create(Text);
  end;
end;

class function TLspCompletion.Keywords(APlace: TCompletionPlace): TArray<string>;
var
  Word: string;
begin
  Result := nil;
  case APlace of
    TCompletionPlace.Statement:
      for Word in StatementKeywords do
      begin
        Result := Result + [Word];
      end;
    TCompletionPlace.Declaration:
      for Word in DeclarationKeywords do
      begin
        Result := Result + [Word];
      end;
    TCompletionPlace.ClassBody:
      for Word in ClassBodyKeywords do
      begin
        Result := Result + [Word];
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TLspCompletion.ContextItems(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>;
  const AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  ASnippetSupport: Boolean): TArray<TCompletionItem>;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, '', APosition);
  try
    Request.Index := AIndex;
    Request.Matching := AMatching;
    Result := ContextItems(Request, ANamespaces, ASnippetSupport);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.ContextItems(ARequest: TCompletionRequest; const ANamespaces: TArray<string>;
  ASnippetSupport: Boolean): TArray<TCompletionItem>;
var
  Slash: TSlashContext;
  Snippet: TContextSnippet;
  Item: TCompletionItem;
  LineText, Word: string;
  Start: Integer;
begin
  Result := nil;
  LineText := ARequest.LineText(ARequest.Position.Line);
  // Getipptes Wort vor dem Cursor; TContextSnippets prüft, dass sonst nichts in der Zeile steht.
  Start := Min(ARequest.Position.Character, Length(LineText));
  while (Start > 0) and CharInSet(LineText[Start], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Dec(Start);
  end;
  Word := Copy(LineText, Start + 1, ARequest.Position.Character - Start);
  Slash := Default(TSlashContext);
  Slash.Text := ARequest.Text;
  Slash.Line := ARequest.Position.Line;
  Slash.LineText := LineText;
  Slash.Index := ARequest.Index;
  Slash.Namespaces := ANamespaces;
  for Snippet in TContextSnippets.At(Slash, ARequest.Position.Character) do
  begin
    if (MatchScore(Snippet.Prefix, Word, ARequest.Matching) = TFuzzyMatch.NoMatch) and
      (MatchScore(Snippet.Name, Word, ARequest.Matching) = TFuzzyMatch.NoMatch) then
    begin
      Continue;
    end;
    Item := Default(TCompletionItem);
    Item.Name := Snippet.Name;
    Item.Detail := Snippet.Description;
    Item.Kind := KindSnippet;
    Item.FilterText := Snippet.Prefix;
    Item.HasTextEdit := True;
    Item.Snippet := ASnippetSupport;
    if ASnippetSupport then
    begin
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position.Line, Start, ARequest.Position.Line,
        ARequest.Position.Character), Snippet.Text);
    end
    else
    begin
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position.Line, Start, ARequest.Position.Line,
        ARequest.Position.Character), TContextSnippets.ToPlain(Snippet.Text));
    end;
    Item.AdditionalEdits := Snippet.AdditionalEdits;
    // Atlas wertet die weiteren Änderungen dann nicht als uses-Ergänzung.
    Item.Action := 'snippet';
    Result := Result + [Item];
  end;
end;

/// <summary>Steht AOffset in einer Funktion (Exit mit Wert erlaubt, #188)? Innerste Routine mit Kopf "function",
/// "class function" oder "operator".</summary>
function InFunctionAt(ATree: TSyntaxTree; const AText: string; AOffset: Integer): Boolean;

  function Innermost(ARoot: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
    Node, Child: TSyntaxNode;
  begin
    // Schleife statt Rekursion (Bericht M1): dem ersten Kind folgen, das AOffset enthält; die letzte Routine
    // auf dem Weg ist die innerste.
    Result := nil;
    Node := ARoot;
    while Node <> nil do
    begin
      Child := nil;
      for Index := 0 to Node.ChildCount - 1 do
      begin
        if (Node[Index].StartOffset <= AOffset) and (AOffset <= Node[Index].EndOffset) then
        begin
          Child := Node[Index];
          Break;
        end;
      end;
      if (Child <> nil) and (Child.Kind = TSyntaxKind.RoutineDecl) then
      begin
        Result := Child;
      end;
      Node := Child;
    end;
  end;

var
  Routine: TSyntaxNode;
  Head: string;
begin
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Routine := Innermost(ATree.Root);
  if Routine = nil then
  begin
    Exit;
  end;
  Head := LowerCase(TrimLeft(Copy(AText, Routine.StartOffset + 1, 40)));
  if StartsStr('class ', Head) then
  begin
    Head := TrimLeft(Copy(Head, Length('class ') + 1, MaxInt));
  end;
  Result := StartsStr('function', Head) or StartsStr('operator', Head);
end;

/// <summary>Was über den Typ der Kette bekannt ist; False, wenn er unbekannt ist oder kein Wert vorliegt.</summary>
function PostfixTraits(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AContext: TCompletionContext; const AMembers: TArray<TResolvedSymbol>; out ATraits: TPostfixTraits): Boolean;
var
  mChain: TResolvedChainType;
  Member, Enumerator: TResolvedSymbol;
  OwnerType: string;
begin
  ATraits := Default(TPostfixTraits);
  // Ein Typ ist kein Wert, außer als Typumwandlung TFoo(X) (#188).
  if not AResolver.ChainType(ATree, AFileName, AContext.Names, AContext.Offset, mChain) or
    (mChain.Owner.Kind = TResolvedKind.UnitName) or (mChain.Owner.IsType and not AContext.Called) then
  begin
    Exit(False);
  end;
  // Typargumente stehen getrennt: TArray mit TypeArgs Integer.
  if mChain.Owner.IsType then
  begin
    OwnerType := mChain.Owner.Name;
  end
  else
  begin
    OwnerType := mChain.Owner.TypeName;
  end;
  if mChain.Owner.TypeArgs <> '' then
  begin
    OwnerType := OwnerType + '<' + mChain.Owner.TypeArgs + '>';
  end;
  // Typ für eine Deklaration im var-Abschnitt; TFoo.Create liefert ein TFoo.
  if mChain.Owner.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    ATraits.IsConstructorCall := True;
    ATraits.TypeName := mChain.Owner.Container;
  end
  else if OwnerType <> '' then
  begin
    ATraits.TypeName := OwnerType;
  end
  else if mChain.TypeFound then
  begin
    ATraits.TypeName := mChain.TypeInfo.Name;
  end;
  ATraits.ElementType := TPostfixTemplates.ElementOf(OwnerType);
  if (ATraits.ElementType = '') and mChain.TypeFound then
  begin
    ATraits.ElementType := TPostfixTemplates.ElementOf(mChain.TypeInfo.TypeName);
  end;
  ATraits.Enumerable := ATraits.ElementType <> '';
  if mChain.TypeFound and not mChain.TypeInfo.Builtin and (mChain.TypeInfo.SymbolKind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType]) then
  begin
    for Member in AMembers do
    begin
      if SameText(Member.Name, 'GetEnumerator') then
      begin
        ATraits.Enumerable := True;
        // Elementtyp für die klassische Schleife: Current des Enumerators.
        for Enumerator in AResolver.Candidates.MemberCandidates(ATree, AFileName, AContext.Names + ['GetEnumerator'],
          AContext.Offset) do
        begin
          if SameText(Enumerator.Name, 'Current') then
          begin
            ATraits.ElementType := Enumerator.TypeName;
          end;
        end;
        Break;
      end;
    end;
  end;
  ATraits.IsString := TPostfixTemplates.IsStringType(mChain.Owner.TypeName) or
    (mChain.TypeFound and mChain.TypeInfo.Builtin and TPostfixTemplates.IsStringType(mChain.TypeInfo.Name));
  ATraits.IsBoolean := TPostfixTemplates.IsBooleanType(mChain.Owner.TypeName) or
    (mChain.TypeFound and mChain.TypeInfo.Builtin and TPostfixTemplates.IsBooleanType(mChain.TypeInfo.Name));
  ATraits.IsClass := mChain.TypeFound and not mChain.TypeInfo.Builtin and
    (mChain.TypeInfo.SymbolKind = TIndexSymbolKind.ClassType);
  ATraits.IsReference := ATraits.IsClass or
    (mChain.TypeFound and not mChain.TypeInfo.Builtin and
      (mChain.TypeInfo.SymbolKind = TIndexSymbolKind.InterfaceType)) or
    TPostfixTemplates.IsPointerType(mChain.Owner.TypeName) or
    (mChain.TypeFound and TPostfixTemplates.IsPointerType(mChain.TypeInfo.TypeName));
  Result := mChain.TypeFound or ATraits.Enumerable or ATraits.IsString or ATraits.IsReference;
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  const APostfix: TPostfixOptions): TCompletionItems;
begin
  Result := Collect(AResolver, AIndex, ATree, AFileName, AText, APosition, AMatching, APostfix, nil);
end;

/// <summary>Postfix-Vorlagen (#188) hinter "Ausdruck." für ACandidates (die Mitglieder des Ausdrucks); nur
/// einzeilige Ausdrücke mit bekanntem Typ.</summary>
function PostfixItems(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const ACandidates: TArray<TResolvedSymbol>; const APostfix: TPostfixOptions): TArray<TCompletionItem>;
var
  Traits: TPostfixTraits;
  Template: TPostfixTemplate;
  Item: TCompletionItem;
  Expansion: TPostfixExpansion;
  LineText, Before, Indent, Expr, LineBreak: string;
  Slash: TSlashContext;
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Descends: TFunc<string, Boolean>;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  FileName, TypeName: string;
  Offset: Integer;
begin
  Result := nil;
  // Nur einzeilige Ausdrücke; der Typ muss bekannt sein.
  if (AContext.ChainStart.Line <> ARequest.Position.Line) or (AContext.DotPos.Line <> ARequest.Position.Line) or
    not PostfixTraits(ARequest.Resolver, ARequest.Tree, ARequest.FileName, AContext, ACandidates, Traits) then
  begin
    Exit;
  end;
  Traits.InFunction := InFunctionAt(ARequest.Tree, ARequest.Text, AContext.Offset);
  LineText := ARequest.LineText(ARequest.Position.Line);
  Before := Copy(LineText, 1, AContext.ChainStart.Character);
  Indent := Copy(LineText, 1, Length(LineText) - Length(TrimLeft(LineText)));
  Expr := Copy(LineText, AContext.ChainStart.Character + 1, AContext.DotPos.Character - AContext.ChainStart.Character);
  LineBreak := ARequest.LineBreak;
  // Eigene Vorlagen mit Typname als Bedingung: der Typ selbst oder ein Nachfahr. Anonyme Methoden fangen nur
  // eigene Variablen ein, nicht die der umgebenden Routine.
  Resolver := ARequest.Resolver;
  Tree := ARequest.Tree;
  FileName := ARequest.FileName;
  Offset := AContext.Offset;
  TypeName := Traits.TypeName;
  Descends :=
    function(ATypeName: string): Boolean
    begin
      Result := Resolver.Queries.TypeDescendsFrom(Tree, FileName, Offset, TypeName, ATypeName);
    end;
  for Template in TPostfixTemplates.Templates + APostfix.Custom do
  begin
    if not TPostfixTemplates.Applies(Template, Traits, APostfix.InlineVar, Descends) or
      (Template.Statement and (Trim(Before) <> '')) or
      (MatchScore(Template.Key, AContext.Prefix, ARequest.Matching) = TFuzzyMatch.NoMatch) then
    begin
      Continue;
    end;
    Expansion := TPostfixTemplates.Expand(Template, Expr, Traits,
      TPostfixLayout.Create(Indent, LineBreak, APostfix.InlineVar, APostfix.Snippet));
    Item := Default(TCompletionItem);
    Item.Name := Template.Key;
    Item.Detail := Template.Description;
    Item.Kind := KindSnippet;
    // Der Editor filtert über "Ausdruck.Kürzel"; Atlas kennzeichnet den Eintrag als Postfix.
    Item.FilterText := Expr + '.' + Template.Key;
    Item.Action := 'postfix';
    Item.Snippet := APostfix.Snippet;
    Item.HasTextEdit := True;
    Item.TextEdit := TRuleEdit.Create(TTextRange.Create(AContext.ChainStart, ARequest.Position), Expansion.Text);
    if Expansion.Declaration <> '' then
    begin
      // Ohne Inline-Variable: Deklaration in den var-Abschnitt der Routine.
      Slash := Default(TSlashContext);
      Slash.Text := ARequest.Text;
      Slash.Line := ARequest.Position.Line;
      Slash.LineText := LineText;
      Source := TCommandSource.Create(Slash);
      try
        Routine := Source.RoutineAt;
        if Routine = nil then
        begin
          Continue;
        end;
        Item.AdditionalEdits := [AddLocal(Source, Routine, TSyntaxKind.VarSection, 'var', Expansion.Declaration)];
      finally
        Source.Free;
      end;
    end;
    Result := Result + [Item];
  end;
end;

/// <summary>Vollständige inherited-Aufrufe (#482) vor die Namen der Vorfahrmethoden; aus ACandidates fallen
/// die abstrakten und die, deren Aufruf schon oben steht.</summary>
procedure AddInheritedCalls(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  ACollector: TCompletionCollector; var ACandidates: TArray<TResolvedSymbol>);
const
  /// <summary>Vor allen übrigen Einträgen, in der Reihenfolge der Aufrufe.</summary>
  CallBonus = 100000;
var
  Symbols: TArray<TIndexSymbol>;
  Depths: TArray<Integer>;
  Methods: TArray<TInheritedMethod>;
  Method: TInheritedMethod;
  Current, Header: TInheritedHeader;
  Calls: TArray<TInheritedCall>;
  Abstract_, Names: TArray<string>;
  Kept: TArray<TResolvedSymbol>;
  Candidate: TResolvedSymbol;
  Item: TCompletionItem;
  Start, Index, Score, Column: Integer;
  LineBefore, After, Text: string;
  WithResult: Boolean;
begin
  Symbols := ARequest.Resolver.Queries.InheritedOverloads(ARequest.Tree, ARequest.FileName, AContext.Offset, Start,
    Depths);
  if (Start < 0) or not TInheritedHeader.Parse(TCompletionInherited.HeaderText(ARequest.Text, Start + 1),
    Current) then
  begin
    Exit;
  end;
  Methods := nil;
  for Index := 0 to High(Symbols) do
  begin
    if TInheritedHeader.Parse(Symbols[Index].Signature, Header) then
    begin
      Method.Header := Header;
      Method.Container := Symbols[Index].Container;
      Method.Depth := Depths[Index];
      Methods := Methods + [Method];
    end;
  end;
  Calls := TCompletionInherited.Calls(Current, Methods, Abstract_);
  LineBefore := ARequest.LineBefore;
  WithResult := TCompletionInherited.NeedsResult(Current, LineBefore);
  // Semikolon nur, wenn hinter dem Cursor nichts mehr steht.
  After := Copy(ARequest.LineText(ARequest.Position.Line), ARequest.Position.Character + 1, MaxInt);
  Names := nil;
  for Index := 0 to High(Calls) do
  begin
    Names := Names + [Calls[Index].Name];
  end;
  // Unter den Namen fallen die abstrakten weg (auch für die Fußzeile) und die, deren Aufruf oben steht.
  Kept := nil;
  for Candidate in ACandidates do
  begin
    if TInheritedHeader.Parse(Candidate.Signature, Header) and Header.IsAbstract then
    begin
      if not MatchText(Candidate.Container + '.' + Candidate.Name, Abstract_) then
      begin
        Abstract_ := Abstract_ + [Candidate.Container + '.' + Candidate.Name];
      end;
    end
    else if not MatchText(Candidate.Name, Names) then
    begin
      Kept := Kept + [Candidate];
    end;
  end;
  ACandidates := Kept;
  for Index := 0 to High(Calls) do
  begin
    Score := MatchScore(Calls[Index].Name, AContext.Prefix, ARequest.Matching);
    if Score = TFuzzyMatch.NoMatch then
    begin
      Continue;
    end;
    Item := Default(TCompletionItem);
    Item.Name := Calls[Index].Text;
    Item.FilterText := Calls[Index].Name;
    Item.Detail := Calls[Index].Container;
    if Current.Kind = 'constructor' then
    begin
      Item.Kind := KindConstructor;
    end
    else
    begin
      Item.Kind := KindMethod;
    end;
    Item.Container := Calls[Index].Container;
    Item.Depth := Calls[Index].Depth;
    Item.InheritedMatch := TCompletionInherited.MatchNames[Calls[Index].Match];
    Item.InheritedAbstract := Abstract_;
    Text := Calls[Index].Text;
    if Trim(After) = '' then
    begin
      Text := Text + ';';
    end;
    Item.HasTextEdit := True;
    if WithResult then
    begin
      Column := Pos('inherited', LowerCase(LineBefore)) - 1;
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position.Line, Column, ARequest.Position.Line,
        ARequest.Position.Character), 'Result := inherited ' + Text);
    end
    else
    begin
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position.Line,
        ARequest.Position.Character - Length(AContext.Prefix), ARequest.Position.Line,
        ARequest.Position.Character), Text);
    end;
    ACollector.AddItem(Item, Score + CallBonus - Index);
  end;
end;

/// <summary>Schlüsselwörter passend zur Stelle (#31), erst ab einem getippten Zeichen; ohne Eingabe gingen die
/// Namen darin unter.</summary>
function KeywordsAt(const AContext: TCompletionContext): TArray<string>;
var
  Word: string;
begin
  Result := nil;
  if AContext.Prefix = '' then
  begin
    Exit;
  end;
  if AContext.Filter = TCompletionFilter.Types then
  begin
    if not AContext.TypeKeywords then
    begin
      Exit;
    end;
    for Word in TypeKeywords do
    begin
      Result := Result + [Word];
    end;
  end
  else
  begin
    Result := TLspCompletion.Keywords(AContext.Place);
  end;
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  const APostfix: TPostfixOptions; const AOnPartial: TCompletionPartialProc): TCompletionItems;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.Index := AIndex;
    Request.Matching := AMatching;
    Result := Collect(Request, APostfix, AOnPartial);
  finally
    Request.Free;
  end;
end;

/// <summary>Exception-Klassen, die schon ohne Eingabe aus nicht eingebundenen Units kommen (#483): die gängigen
/// und, nach "on E: ", die aus dem try-Block.</summary>
function ExceptionImportNames(ARequest: TCompletionRequest; const AContext: TCompletionContext): TArray<string>;
var
  Site: TExceptionSite;
  Name: string;
  Units: TArray<string>;
begin
  Result := nil;
  for Name in TCompletionExceptions.CommonNames do
  begin
    Result := Result + [Name];
  end;
  if TCompletionExceptions.SiteAt(ARequest.Tree.Tokens, AContext.ExceptionToken, Site) then
  begin
    for Name in TCompletionExceptions.TryClasses(ARequest, Site, Units) do
    begin
      if IndexText(Name, Result) < 0 then
      begin
        Result := Result + [Name];
      end;
    end;
  end;
end;

class function TLspCompletion.Collect(ARequest: TCompletionRequest; const APostfix: TPostfixOptions;
  const AOnPartial: TCompletionPartialProc): TCompletionItems;
var
  Postfix: TArray<TCompletionItem>;
  Context: TCompletionContext;
  Candidates: TArray<TResolvedSymbol>;
  UnitInfo: TUnitIndex;
  Expected: string;
  Collector: TCompletionCollector;
  GenericOwner, Candidate: TResolvedSymbol;
  OnPartial: TCompletionPartialProc;
begin
  Result := Default(TCompletionItems);
  Postfix := nil;
  Context := Analyze(ARequest.Tree, ARequest.Position);
  // Typargument (#450): nur Typen, gefiltert nach den Constraints. Nicht gestaffelt, weil erst die ganze
  // Liste gefiltert wird.
  GenericOwner := Default(TResolvedSymbol);
  OnPartial := AOnPartial;
  if Context.Generic and ARequest.Settings.GenericConstraints then
  begin
    Context.Generic := False;
    for Candidate in ARequest.Resolver.ResolveAll(ARequest.Tree, ARequest.FileName, Context.GenericOwnerPos) do
    begin
      if Candidate.IsType and (Candidate.TypeParams <> '') then
      begin
        GenericOwner := Candidate;
        Context.Generic := True;
        Context.Filter := TCompletionFilter.Types;
        Context.TypeKeywords := False;
        OnPartial := nil;
        Break;
      end;
    end;
  end
  else
  begin
    Context.Generic := False;
  end;
  // Attribute (#465): erst die ganze Liste filtern und sortieren, deshalb nicht gestaffelt.
  if Context.Attribute and not ARequest.Settings.Attributes then
  begin
    Context.Attribute := False;
    Context.Filter := TCompletionFilter.Any;
  end;
  if Context.Attribute then
  begin
    OnPartial := nil;
  end;
  // Exception-Klassen (#483): ebenso erst die ganze Liste; aus: die gewöhnliche Liste.
  if Context.Exceptions and not ARequest.Settings.ExceptionClasses then
  begin
    Context.Exceptions := False;
    Context.Filter := TCompletionFilter.Any;
  end;
  if Context.Exceptions then
  begin
    OnPartial := nil;
  end;
  // Diagnoselog (#647): nur Art und Längen, nie die Namen selbst.
  TRequestDiagnostics.Note('ctx', ContextCodes[Context.Kind]);
  TRequestDiagnostics.Note('prefixLen', Length(Context.Prefix));
  if Context.Kind = TCompletionContextKind.Member then
  begin
    TRequestDiagnostics.Note('chainLen', Length(Context.Names));
  end
  else if Context.Kind = TCompletionContextKind.None then
  begin
    TRequestDiagnostics.Reason('noContext');
  end;
  Expected := '';
  if Context.Kind in [TCompletionContextKind.Member, TCompletionContextKind.Scope] then
  begin
    Expected := ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ARequest.Position);
  end;
  // Viele Auflösungen auf demselben Baum: einmal auswerten (Code-Review P-02). Hat Handle den Baum schon
  // gepinnt, zählt das nur hoch.
  if ARequest.Tree <> nil then
  begin
    ARequest.Resolver.PinTree(ARequest.Tree, ARequest.FileName);
  end;
  Collector := TCompletionCollector.Create(ARequest, Context, Expected, OnPartial);
  try
    if Context.Attribute then
    begin
      Collector.SetAdmit(TCompletionAttributes.Admit(ARequest.Resolver));
    end;
    if Context.Exceptions then
    begin
      Collector.SetAdmit(TCompletionExceptions.Admit(ARequest.Resolver));
    end;
    case Context.Kind of
      TCompletionContextKind.UsesClause:
        // Gruppen, Hinweise und Zirkelbezüge (#469); aus: alle Units als schlichte Liste.
        if ARequest.Settings.UsesDetails then
        begin
          TCompletionUses.Collect(ARequest, Context, Collector);
        end
        else
        begin
          for UnitInfo in ARequest.Index.Units do
          begin
            Collector.Add(UnitInfo.UnitName, UnitInfo.FileName, KindModule, Default(TResolvedSymbol));
          end;
        end;
      TCompletionContextKind.Member, TCompletionContextKind.Scope:
        begin
          // Nur passende Namen aufbauen (#616); ohne Eingabe passt ohnehin alles. Der Filter gilt nur beim
          // Sammeln, nicht für die Typprüfungen in Add.
          if Context.Kind = TCompletionContextKind.Member then
          begin
            // Die Postfix-Vorlagen brauchen die Mitglieder (GetEnumerator).
            Collector.SetNameFilter(True);
            try
              Candidates := ARequest.Resolver.Candidates.MemberCandidates(ARequest.Tree, ARequest.FileName,
                Context.Names,
                Context.Offset);
            finally
              Collector.SetNameFilter(False);
            end;
            Collector.AddCandidates(Candidates);
            Collector.AddUnavailableMembers(Candidates);
            // Helper aus nicht eingebundenen Units mit uses-Eintrag (#456), wie Symbole bei #180.
            Collector.AddHelpersFromOtherUnits(ARequest.Resolver.Candidates.ReceiverTypes(ARequest.Tree,
              ARequest.FileName,
              Context.Names, Context.Offset));
          end
          else if Context.Filter = TCompletionFilter.InheritedCall then
          begin
            // Nach "inherited " nur Methoden der Vorfahren (#31).
            Collector.SetNameFilter(True);
            try
              Candidates := ARequest.Resolver.Candidates.InheritedCandidates(ARequest.Tree, ARequest.FileName,
                Context.Offset);
            finally
              Collector.SetNameFilter(False);
            end;
            // Vollständiger Aufruf mit den eigenen Parametern zuerst (#482).
            if ARequest.Settings.InheritedCall then
            begin
              AddInheritedCalls(ARequest, Context, Collector, Candidates);
            end;
            Collector.AddCandidates(Candidates);
          end
          else
          begin
            // Eigener Gültigkeitsbereich zuerst (#616): lokal, Self, eigene Unit; dann die Units aus uses.
            Collector.SetNameFilter(True);
            try
              Candidates := ARequest.Resolver.Candidates.OwnScopeCandidates(ARequest.Tree, ARequest.FileName,
                Context.Offset);
            finally
              Collector.SetNameFilter(False);
            end;
            Collector.AddCandidates(Candidates);
            Collector.MarkUsedShadows;
            Collector.SendStage;
            Collector.SetNameFilter(True);
            try
              // Mit Eingabe auch die Bezeichner von System ohne Quelltext (#880): Assigned, SetLength,
              // Integer ... Ohne Eingabe nicht, die Liste ist dann ohnehin unvollständig (Incomplete).
              Candidates := ARequest.Resolver.Candidates.UsedScopeCandidates(Context.Prefix <> '');
            finally
              Collector.SetNameFilter(False);
            end;
            Collector.AddCandidates(Candidates);
            // Gleichnamige Bezeichner aus anderen Units direkt hinter der aktiven Variante (#475).
            Collector.AddSameNameVariants;
          end;
          if (Context.Kind = TCompletionContextKind.Scope) and
            (Context.Filter <> TCompletionFilter.InheritedCall) then
          begin
            // Danach die nicht eingebundenen Units.
            Collector.SendStage;
            if Length(Context.Prefix) >= MinImportPrefix then
            begin
              Collector.AddFromOtherUnits;
            end
            else if Context.Attribute then
            begin
              // Bekannte Attribute (DUnitX, JSON) schon nach "[" mit uses-Eintrag (#465).
              Collector.AddFromOtherUnits(TCompletionAttributes.KnownClassNames);
            end
            else if Context.Exceptions then
            begin
              // Gängige Exception-Klassen schon nach "raise " bzw. "on E: " mit uses-Eintrag (#483).
              Collector.AddFromOtherUnits(ExceptionImportNames(ARequest, Context));
            end;
            Collector.AddUnavailable;
            Collector.AddKeywords(KeywordsAt(Context));
          end;
          // Postfix-Vorlagen stehen immer hinter den echten Mitgliedern.
          if (Context.Kind = TCompletionContextKind.Member) and APostfix.Enabled and (ARequest.Text <> '') then
          begin
            Postfix := PostfixItems(ARequest, Context, Candidates, APostfix);
          end;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    Result.Items := Collector.Finish(Result.Incomplete);
    if Context.Generic then
    begin
      Result.Items := TCompletionGenerics.Apply(ARequest, Context, GenericOwner, Result.Items);
    end;
    if Context.Attribute then
    begin
      Result.Items := TCompletionAttributes.Apply(ARequest, Context, Result.Items);
    end;
    if Context.Exceptions then
    begin
      // Platzhalter wie bei den Postfix-Vorlagen nach snippetSupport des Clients.
      Result.Items := TCompletionExceptions.Apply(ARequest, Context, APostfix.Snippet, Result.Items);
    end;
    Result.Items := Result.Items + Postfix;
  finally
    Collector.Free;
    if ARequest.Tree <> nil then
    begin
      ARequest.Resolver.UnpinTree;
    end;
  end;
end;

class function TLspCompletion.ToJson(const AItems: TCompletionItems): TJSONObject;
begin
  Result := CompletionListToJson(AItems.Items, AItems.Incomplete, 0);
end;

class function TLspCompletion.ToJson(const AItems: TArray<TCompletionItem>; AFirstSort: Integer): TJSONArray;
begin
  Result := CompletionItemsToJson(AItems, AFirstSort);
end;

/// <summary>AItems ohne die Schlüsselwörter aus AddKeywords (#31).</summary>
function WithoutKeywords(const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  Item: TCompletionItem;
  Count: Integer;
begin
  // Einmal anlegen statt je Eintrag anhängen (Code-Review P-08), wie WithoutNames.
  Result := nil;
  SetLength(Result, Length(AItems));
  Count := 0;
  for Item in AItems do
  begin
    if Item.Kind <> KindKeyword then
    begin
      Result[Count] := Item;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

/// <summary>AItems ohne die Namen aus ANames (#448: vorab bestimmte Einträge).</summary>
function WithoutNames(const AItems, ANames: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  Names: TDictionary<string, Boolean>;
  Item: TCompletionItem;
  Count: Integer;
begin
  if Length(ANames) = 0 then
  begin
    Exit(AItems);
  end;
  Names := TDictionary<string, Boolean>.Create;
  try
    for Item in ANames do
    begin
      Names.AddOrSetValue(LowerCase(Item.Name), True);
    end;
    Result := nil;
    SetLength(Result, Length(AItems));
    Count := 0;
    for Item in AItems do
    begin
      if not Names.ContainsKey(LowerCase(Item.Name)) then
      begin
        Result[Count] := Item;
        Inc(Count);
      end;
    end;
    SetLength(Result, Count);
  finally
    Names.Free;
  end;
end;

/// <summary>Läuft ACases der Reihe nach, bis einer antwortet; True dann.</summary>
function RunCases(const ACases: TArray<TCompletionCase>; ARequest: TCompletionRequest;
  AAnswer: TCompletionAnswer): Boolean;
var
  Step: TCompletionCase;
begin
  for Step in ACases do
  begin
    if Step(ARequest, AAnswer) = TCompletionOutcome.Answered then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>„with auflösen“ (#50) als Eintrag, wenn der Cursor auf dem Wort with steht: die Hauptänderung
/// entfernt das Wort (eine Zeile, mit dem Cursor), der Rest der Anweisung kommt als Zusatzänderung.</summary>
function WithItem(ARequest: TCompletionRequest; const AWithFor: TCompletionWithFunc;
  out AItem: TCompletionItem): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Found: Boolean;
begin
  AItem := Default(TCompletionItem);
  Result := False;
  Tokens := ARequest.Tree.Tokens;
  Index := 0;
  while (Index <= High(Tokens)) and (ComparePositions(Tokens[Index].EndPos, ARequest.Position) < 0) do
  begin
    Inc(Index);
  end;
  if (Index > High(Tokens)) or not Tokens[Index].IsKeyword('with') or
    (ComparePositions(Tokens[Index].StartPos, ARequest.Position) > 0) or not AWithFor(ARequest, Edits) then
  begin
    Exit;
  end;
  AItem.Name := 'with auflösen';
  AItem.Kind := KindSnippet;
  AItem.Detail := 'Atlas';
  AItem.Fits := True;
  AItem.Pinned := True;
  AItem.Action := 'with';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos), '');
  Found := False;
  for Edit in Edits do
  begin
    if (Edit.Range.StartPos.Line = Tokens[Index].StartPos.Line) and
      (Edit.Range.StartPos.Character = Tokens[Index].StartPos.Character) then
    begin
      AItem.AdditionalEdits := AItem.AdditionalEdits + [TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos,
        Edit.Range.EndPos), Edit.NewText)];
      Found := True;
    end
    else
    begin
      AItem.AdditionalEdits := AItem.AdditionalEdits + [Edit];
    end;
  end;
  Result := Found;
end;

/// <summary>„Parameter abgleichen“ (#88) als Eintrag, wenn der Cursor in einem ///-Block über einer Routine
/// steht, deren Signatur nicht mehr zum Block passt: An der Cursorstelle ändert sich nichts, fehlende
/// &lt;param&gt; und markierte überzählige kommen als Zusatzänderungen.</summary>
function DocParamsItem(ARequest: TCompletionRequest; out AItem: TCompletionItem): Boolean;
var
  Action: TCodeAction;
begin
  AItem := Default(TCompletionItem);
  Result := TDocComments.AdjustBlock(ARequest.Text, ARequest.Tree, ARequest.Position.Line, Action);
  if not Result then
  begin
    Exit;
  end;
  AItem.Name := Action.Title;
  AItem.Kind := KindSnippet;
  AItem.Detail := 'Atlas';
  AItem.Fits := True;
  AItem.Pinned := True;
  AItem.Action := 'docParams';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position, ARequest.Position), '');
  AItem.AdditionalEdits := Action.Edits;
end;

/// <summary>„Methode aus Aufruf anlegen“ (#472) als Eintrag: Nach dem Auslöser "(" bleibt der Text an der
/// Aufrufstelle, mit Strg+Leer auf dem Namen ersetzt der Eintrag ihn durch sich selbst. Deklaration und Rumpf
/// kommen als Zusatzänderungen; "$0" darin setzt den Cursor in den Rumpf.</summary>
function CreateItem(ARequest: TCompletionRequest; const ACreateFor: TCompletionCreateFunc;
  out AItem: TCompletionItem): Boolean;
var
  Site: TCreateCallSite;
  Title, Detail: string;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
begin
  AItem := Default(TCompletionItem);
  Result := False;
  if (ARequest.Tree = nil) or not TCreateMethod.Site(ARequest.Tree.Tokens, ARequest.Position, Site) or
    not ACreateFor(ARequest, Title, Detail, Edits) then
  begin
    Exit;
  end;
  AItem.Name := Title;
  AItem.Kind := KindMethod;
  AItem.Detail := Detail;
  AItem.Fits := True;
  AItem.Pinned := True;
  AItem.Action := 'create';
  AItem.Unknown := Site.Name;
  AItem.HasTextEdit := True;
  if ARequest.Trigger = '(' then
  begin
    AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(ARequest.Position, ARequest.Position), '');
  end
  else
  begin
    AItem.TextEdit := TRuleEdit.Create(Site.NameRange, Site.Name);
  end;
  for Edit in Edits do
  begin
    AItem.AdditionalEdits := AItem.AdditionalEdits + [Edit];
  end;
  Result := True;
end;

class function TLspCompletion.NamingPrefix(const AIndex: ISymbolIndex; AKind: TNamingKind): string;
var
  Units: TArray<TUnitIndex>;
  Count: TNamingCount;
  Index: Integer;
begin
  Result := '';
  if AIndex = nil then
  begin
    Exit;
  end;
  Count := Default(TNamingCount);
  Units := AIndex.Units;
  for Index := 0 to High(Units) do
  begin
    if not Units[Index].Library_ then
    begin
      Inc(Count.Total, Units[Index].Naming[AKind].Total);
      Inc(Count.Prefixed, Units[Index].Naming[AKind].Prefixed);
    end;
  end;
  if TNameSuggestions.UsesPrefix(Count) then
  begin
    Result := NamingPrefixes[AKind];
  end;
end;

/// <summary>Namen, die an der Namensposition ASite schon vergeben sind: sichtbare Namen (lokal, eigene Klasse,
/// eigene Unit), bei Feldern die Mitglieder der Klasse, bei Parametern die übrigen Parameter. Der Name, der an
/// der Stelle selbst steht, zählt nicht.</summary>
function TakenNames(ARequest: TCompletionRequest; const ASite: TNameSite): TArray<string>;
var
  Own, Container: string;
  Candidate: TResolvedSymbol;
  Symbol: TIndexSymbol;
  Node, Child: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  Result := nil;
  Own := '';
  if ComparePositions(ASite.NameRange.StartPos, ASite.NameRange.EndPos) <> 0 then
  begin
    Own := Copy(ARequest.LineText(ASite.NameRange.StartPos.Line), ASite.NameRange.StartPos.Character + 1,
      ASite.NameRange.EndPos.Character - ASite.NameRange.StartPos.Character);
  end;
  if ARequest.Resolver <> nil then
  begin
    for Candidate in ARequest.Resolver.Candidates.OwnScopeCandidates(ARequest.Tree, ARequest.FileName, ASite.Offset) do
    begin
      Result := Result + [Candidate.Name];
    end;
  end;
  Node := ARequest.Tree.Root;
  while Node <> nil do
  begin
    Child := nil;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if (Node[Index].StartOffset <= ASite.Offset) and (ASite.Offset <= Node[Index].EndOffset) then
      begin
        Child := Node[Index];
      end;
    end;
    if Child = nil then
    begin
      Break;
    end;
    Node := Child;
  end;
  if ASite.Kind = TNamingKind.Parameter then
  begin
    while (Node <> nil) and (Node.Kind <> TSyntaxKind.Parameters) do
    begin
      Node := Node.Parent;
    end;
    if Node <> nil then
    begin
      for Index := 0 to Node.ChildCount - 1 do
      begin
        for Name in Node[Index].Name.Split([',']) do
        begin
          if Trim(Name) <> '' then
          begin
            Result := Result + [Trim(Name)];
          end;
        end;
      end;
    end;
  end
  else if (ASite.Kind = TNamingKind.Field) and not ASite.Global then
  begin
    while (Node <> nil) and not (Node.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
      TSyntaxKind.RecordType, TSyntaxKind.HelperType]) do
    begin
      Node := Node.Parent;
    end;
    if (Node <> nil) and (Node.Parent <> nil) then
    begin
      Container := Node.Parent.Name;
      for Symbol in ARequest.UnitIndex.Symbols do
      begin
        if (Symbol.Container <> '') and SameText(Symbol.Container.Substring(Symbol.Container.LastIndexOf('.') + 1),
          Container) then
        begin
          Result := Result + [Symbol.Name];
        end;
      end;
    end;
  end;
  if Own = '' then
  begin
    Exit;
  end;
  for Index := High(Result) downto 0 do
  begin
    if SameText(Result[Index], Own) then
    begin
      Delete(Result, Index, 1);
    end;
  end;
end;

class function TLspCompletion.NameItems(ARequest: TCompletionRequest; const ANamingFor: TCompletionNamingFunc;
  out AItems: TCompletionItems): Boolean;
var
  Site: TNameSite;
  Prefix, Name: string;
  Item: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  if not ARequest.Settings.NameSuggestions or (ARequest.Tree = nil) or
    not TNameSuggestions.Site(ARequest.Tree, ARequest.Position, Site) then
  begin
    Exit;
  end;
  if Site.Global then
  begin
    Prefix := '';
  end
  else if Assigned(ANamingFor) then
  begin
    Prefix := ANamingFor(ARequest.Uri, Site.Kind);
  end
  else
  begin
    Prefix := NamingPrefix(ARequest.Index, Site.Kind);
  end;
  for Name in TNameSuggestions.Suggest(Site.TypeText, Prefix, TakenNames(ARequest, Site)) do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Name;
    if Site.Kind = TNamingKind.Field then
    begin
      Item.Kind := KindField;
    end
    else
    begin
      Item.Kind := KindVariable;
    end;
    Item.Detail := Site.TypeText;
    Item.Fits := True;
    Item.HasTextEdit := True;
    Item.TextEdit := TRuleEdit.Create(Site.NameRange, Name);
    AItems.Items := AItems.Items + [Item];
  end;
  Result := Length(AItems.Items) > 0;
end;

/// <summary>Hängt ACase an ACases an.</summary>
procedure AddCase(var ACases: TArray<TCompletionCase>; const ACase: TCompletionCase);
begin
  SetLength(ACases, Length(ACases) + 1);
  ACases[High(ACases)] := ACase;
end;

procedure TLspCompletion.RegisterCases;
begin
  // Ohne Syntaxbaum, in dieser Reihenfolge (Code-Review S-01): Schnellbefehle (#293), Direktiven (#102),
  // Feld- und Parameternamen im String-Literal (#461).
  AddCase(FTextCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Disabled: TArray<string>;
    begin
      Result := TCompletionOutcome.Next;
      Disabled := nil;
      if (not Assigned(FSlashCommandsFor) or FSlashCommandsFor(ARequest.Uri, Disabled)) and
        SlashItems(ARequest, Disabled, FRuleIdsFor, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  AddCase(FTextCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Context: TConditionalContext;
    begin
      Result := TCompletionOutcome.Next;
      Context := TConditionalContext.Default;
      if Assigned(FSymbolsFor) then
      begin
        Context := FSymbolsFor(ARequest.Uri);
      end;
      if SymbolItems(ARequest, Context, AAnswer.Exclusive) or DirectiveItems(ARequest, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
        // Abgeschaltet (directives.completion): in der Direktive gar nichts, auch nicht die übrige Liste.
        if not Context.CompletionEnabled then
        begin
          AAnswer.Exclusive := Default(TCompletionItems);
        end;
      end;
    end);
  AddCase(FTextCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if DataNameItems(ARequest, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Platzhalter in Wertdarstellungen (#854): in // atlas-debug: bzw. [AtlasDebugDisplay] nur die Mitglieder des Typs.
  AddCase(FTextCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if TCompletionDebugDisplay.Items(ARequest, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Mit Baum und Resolver, in dieser Reihenfolge.
  // „Parameter abgleichen“ (#88): Strg+Leer in einem ///-Block, dessen Routine andere Parameter hat; dann nur
  // dieses Angebot (die Tags liefert das Plugin selbst).
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Item: TCompletionItem;
    begin
      Result := TCompletionOutcome.Next;
      if (not Assigned(FDocCommentsFor) or FDocCommentsFor(ARequest.Uri)) and DocParamsItem(ARequest, Item) then
      begin
        AAnswer.Exclusive := Default(TCompletionItems);
        AAnswer.Exclusive.Items := [Item];
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // String als resourcestring auslagern (#473): Strg+Leer im String-Literal; sonst bietet die Liste dort nichts.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if ResourceStringItems(ARequest, FSnippetSupport, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Freigabe absichern (#489): Das Plugin fragt nach dem ";" bzw. dem Zeilenende (#10) hinter einem
  // übernommenen Konstruktor mit diesem Auslöser; dann gibt es nur dieses Angebot oder nichts.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if (ARequest.Trigger <> ';') and (ARequest.Trigger <> #10) then
      begin
        Exit;
      end;
      if not (ARequest.Settings.OfferTryFinally and GuardItems(ARequest, ARequest.Trigger = #10,
        AAnswer.Exclusive)) then
      begin
        AAnswer.Exclusive := Default(TCompletionItems);
      end;
      Result := TCompletionOutcome.Answered;
    end);
  // Anonyme Methoden (#468): Erwartet das Argument einen Methodenreferenztyp, nach "(" nur das Gerüst (dort
  // gibt es keine unbekannte Methode anzulegen), mit Strg+Leer ganz oben in der Liste.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Item: TCompletionItem;
    begin
      Result := TCompletionOutcome.Next;
      if not AnonymousItem(ARequest, FSnippetSupport, FNamingFor, Item) then
      begin
        Exit;
      end;
      if ARequest.Trigger = '(' then
      begin
        AAnswer.Exclusive := Default(TCompletionItems);
        AAnswer.Exclusive.Items := [Item];
        Exit(TCompletionOutcome.Answered);
      end;
      AAnswer.Hints := AAnswer.Hints + [Item];
    end);
  // Methode aus Aufruf anlegen (#472): Nach "(" (Auslöser des Plugins) gibt es nur dieses Angebot oder nichts,
  // mit Strg+Leer auf dem Namen eines Aufrufs steht es oben in der Liste.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Item: TCompletionItem;
      Found: Boolean;
    begin
      Result := TCompletionOutcome.Next;
      Found := Assigned(FCreateFor) and CreateItem(ARequest, FCreateFor, Item);
      if ARequest.Trigger = '(' then
      begin
        AAnswer.Exclusive := Default(TCompletionItems);
        if Found then
        begin
          AAnswer.Exclusive.Items := [Item];
        end;
        Result := TCompletionOutcome.Answered;
      end
      else if Found then
      begin
        AAnswer.Hints := AAnswer.Hints + [Item];
      end;
    end);
  // with auflösen (#50): auf dem Wort with oben in der Liste, die übrige Liste bleibt.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Item: TCompletionItem;
    begin
      Result := TCompletionOutcome.Next;
      if Assigned(FWithFor) and WithItem(ARequest, FWithFor, Item) then
      begin
        AAnswer.Hints := AAnswer.Hints + [Item];
      end;
    end);
  // Alle Felder zuweisen (#491): hinter "Ausdruck." am Anweisungsanfang ganz oben, die übrige Liste bleibt.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Item: TCompletionItem;
    begin
      Result := TCompletionOutcome.Next;
      if AssignAllItem(ARequest, FSnippetSupport, Item) then
      begin
        AAnswer.Hints := AAnswer.Hints + [Item];
      end;
    end);
  // Namensvorschläge (#452): an der Namensposition einer Deklaration mit bekanntem Typ nur die Namen.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if NameItems(ARequest, FNamingFor, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Methoden überschreiben (#443) vor der allgemeinen Vervollständigung.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if OverrideItems(ARequest, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Property-Zugriffe (#31): nach read bzw. write nur passende Felder und Methoden.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if PropertyItems(ARequest, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Ereignis-Zuweisung (#444).
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if EventItems(ARequest, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Interface implementieren (#466): auf leerer Zeile der Klasse nur die fehlenden Methoden mit
  // Kontrollkästchen; bei angefangenem Wort ein Hinweis oben in der normalen Liste.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Items: TArray<TCompletionItem>;
      Batch: Boolean;
    begin
      Result := TCompletionOutcome.Next;
      if not InterfaceItems(ARequest, Items, Batch) then
      begin
        Exit;
      end;
      if Batch then
      begin
        AAnswer.Exclusive := Default(TCompletionItems);
        AAnswer.Exclusive.Items := Items;
        Exit(TCompletionOutcome.Answered);
      end;
      AAnswer.Hints := Items;
    end);
  // Aufzählungen und Mengen (#448): im Mengenkonstruktor nur dessen Werte; sonst die Werte des erwarteten
  // Aufzählungstyps vorab und vor der übrigen Liste. Atlas fragt bei "[" mit triggerCharacter: ohne Menge
  // nichts.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Items: TArray<TCompletionItem>;
      SetMode: Boolean;
    begin
      Result := TCompletionOutcome.Next;
      if EnumItems(ARequest, Items, SetMode) then
      begin
        AAnswer.Prefetched := Items;
      end;
      if SetMode or (ARequest.Trigger = '[') then
      begin
        AAnswer.Exclusive := Default(TCompletionItems);
        if SetMode then
        begin
          AAnswer.Exclusive.Items := AAnswer.Prefetched;
        end;
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Komponenten aus dem Formular (#455) wie die Aufzählungswerte vorab und vor der übrigen Liste.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Items: TArray<TCompletionItem>;
    begin
      Result := TCompletionOutcome.Next;
      if ComponentItemsFromForm(ARequest, AAnswer.Forms, Items) then
      begin
        AAnswer.Prefetched := AAnswer.Prefetched + Items;
      end;
    end);
  // Postfix-Vorlagen je Dokument; gestaffelt (#616), wenn der Client einen partialResultToken mitschickt:
  // Teilergebnisse als $/progress mit CompletionItem[], die vorab bestimmten Einträge zuerst, der Rest in
  // der Antwort. Zwischen den Stufen bricht eine veraltete Anfrage ab.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Notify: TCompletionNotifyProc;
      Params: TJSONObject;
    begin
      Result := TCompletionOutcome.Next;
      if Assigned(FPostfixFor) then
      begin
        AAnswer.Postfix := FPostfixFor(ARequest.Uri);
      end
      else
      begin
        AAnswer.Postfix := TPostfixOptions.Default;
      end;
      AAnswer.Postfix.Snippet := FSnippetSupport;
      AAnswer.Postfix.Custom := CustomPostfix;
      if AAnswer.Token = '' then
      begin
        Exit;
      end;
      Notify := FNotify;
      AAnswer.Partial :=
        procedure(const AItems: TArray<TCompletionItem>)
        var
          Items: TArray<TCompletionItem>;
          Progress: TJSONObject;
        begin
          AAnswer.Cancellation.ThrowIfCancellationRequested;
          // Die vorab bestimmten Einträge kamen schon (#448).
          Items := WithoutNames(AItems, AAnswer.Prefetched);
          if Length(Items) = 0 then
          begin
            Exit;
          end;
          Progress := TJSONObject.Create;
          Progress.AddPair('token', AAnswer.Token);
          Progress.AddPair('value', ToJson(Items, AAnswer.SentCount));
          Inc(AAnswer.SentCount, Length(Items));
          Notify('$/progress', Progress);
        end;
      if Length(AAnswer.Prefetched) > 0 then
      begin
        Params := TJSONObject.Create;
        Params.AddPair('token', AAnswer.Token);
        Params.AddPair('value', ToJson(AAnswer.Prefetched, AAnswer.SentCount));
        Inc(AAnswer.SentCount, Length(AAnswer.Prefetched));
        Notify('$/progress', Params);
      end;
    end);
  // Sender mit Typumwandlung (#480): statt der Mitglieder von TObject die des zugewiesenen Komponententyps.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if SenderItemsFromForm(ARequest, AAnswer.Forms, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end);
  // Die allgemeine Liste ohne die vorab bestimmten Namen; Schlüsselwörter abschaltbar (#31,
  // completion.keywords).
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Collected: TCompletionItems;
    begin
      Result := TCompletionOutcome.Next;
      Collected := Collect(ARequest, AAnswer.Postfix, AAnswer.Partial);
      AAnswer.Body := WithoutNames(Collected.Items, AAnswer.Prefetched);
      if not ARequest.Settings.Keywords then
      begin
        AAnswer.Body := WithoutKeywords(AAnswer.Body);
      end;
      AAnswer.Incomplete := Collected.Incomplete;
    end);
  // Kontextabhängige Code-Vorlagen (#51) am Ende der Liste.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      AAnswer.Tail := AAnswer.Tail + ContextItems(ARequest, Namespaces, FSnippetSupport);
    end);
  // Unbekannter Name (#471): Deklarieren am Ende. Die Einträge hängen am getippten Namen, deshalb neu fragen.
  AddCase(FTreeCases,
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      Declares: TArray<TCompletionItem>;
    begin
      Result := TCompletionOutcome.Next;
      if DeclareItems(ARequest, AAnswer.Postfix.InlineVar, AAnswer.Prefetched + AAnswer.Body + AAnswer.Tail,
        Declares) then
      begin
        AAnswer.Tail := AAnswer.Tail + Declares;
        AAnswer.Incomplete := True;
      end;
    end);
end;

function TLspCompletion.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    TRequestDiagnostics.Reason('documentNotOpen');
    Exit(TJSONNull.Create);
  end;
  Result := CompleteDocument(Document, Uri, TLspPositions.ReadPosition(PositionValue), TJSONObject(AParams),
    ACancellation);
end;

function TLspCompletion.Complete(const ADocument: ITextDocument; const AUri: string; const APosition: TTextPosition;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := CompleteDocument(ADocument, AUri, APosition, nil, ACancellation);
end;

function TLspCompletion.CompleteDocument(const ADocument: ITextDocument; const AUri: string;
  const APosition: TTextPosition; const AParams: TJSONObject; const ACancellation: IJsonRpcCancellationToken):
  TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri, Trigger: string;
  Document: ITextDocument;
  Request: TCompletionRequest;
  Answer: TCompletionAnswer;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  Watch: TStopwatch;
  ParseMs: Int64;
begin
  Watch := TStopwatch.StartNew;
  Uri := AUri;
  Document := ADocument;
  Cancellation := TRequestCancellation.Create(ACancellation);
  // Eine Anfrage für alle Fälle (Code-Review S-01): Text, Datei, Position und was je Dokument gilt.
  Request := TCompletionRequest.Create(Document, TDocumentUris.ToPath(Uri), APosition);
  Answer := TCompletionAnswer.Create;
  try
    Request.Uri := Uri;
    Request.Index := FIndex;
    Request.ReadText := FReadText;
    Trigger := '';
    if AParams <> nil then
    begin
      AParams.TryGetValue<string>('context.triggerCharacter', Trigger);
    end;
    Request.Trigger := Trigger;
    Answer.Cancellation := ACancellation;
    // Formulare über den Zwischenspeicher der Instanz (Code-Review P-06).
    Answer.Forms :=
      function(const ASourceFile, ASourceText: string; out ASnapshot: TFormSnapshot): Boolean
      begin
        Result := FormSnapshot(ASourceFile, ASourceText, ASnapshot);
      end;
    if Assigned(FNotify) and (AParams <> nil) and (AParams.GetValue('partialResultToken') is TJSONString) then
    begin
      Answer.Token := TJSONString(AParams.GetValue('partialResultToken')).Value;
    end;
    if RunCases(FTextCases, Request, Answer) then
    begin
      Exit(ToJson(Answer.Exclusive));
    end;
    Shared := TSyntaxTreeCache.Get(Document, Cancellation);
    Request.Tree := Shared.Tree;
    ACancellation.ThrowIfCancellationRequested;
    ParseMs := Watch.ElapsedMilliseconds;
    TRequestDiagnostics.Note('treeMs', Integer(ParseMs));
    TRequestDiagnostics.Note('syntaxErr', Length(Request.Tree.Diagnostics));
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := Namespaces;
      Request.Resolver := Resolver;
      // Den Baum einmal auswerten für alle Teile der Anfrage (Code-Review P-02).
      Resolver.PinTree(Request.Tree, Request.FileName);
      try
        if Assigned(FSettingsFor) then
        begin
          Request.Settings := FSettingsFor(Uri);
        end
        else
        begin
          Request.Settings := TCompletionSettings.Default;
        end;
        if Assigned(FMatchingFor) then
        begin
          Request.Matching := FMatchingFor(Uri);
        end
        else
        begin
          Request.Matching := TCompletionMatching.Fuzzy;
        end;
        if RunCases(FTreeCases, Request, Answer) then
        begin
          Exit(ToJson(Answer.Exclusive));
        end;
        // Hinweise oben, die vorab gesendeten Einträge nur ohne Staffelung in der Antwort.
        Items := Answer.Hints;
        if Answer.Token = '' then
        begin
          Items := Items + Answer.Prefetched;
        end;
        Items := Items + Answer.Body + Answer.Tail;
        Result := CompletionListToJson(Items, Answer.Incomplete, Answer.SentCount);
        // Hinweis bei unvollständigem Code (#457): Syntaxfehler vor dem Cursor in der aktuellen Routine.
        if Request.Settings.SyntaxNotice then
        begin
          TCompletionSyntax.WriteJson(Result as TJSONObject, TCompletionSyntax.Assess(Request.Tree, Request.Text, Request.Position,
            Answer.SentCount + Length(Items)));
        end;
        // Vorab als $/progress gesendete Einträge zählen mit (#616).
        TRequestDiagnostics.ResultCount(Answer.SentCount + Length(Items));
        if Answer.SentCount + Length(Items) = 0 then
        begin
          TRequestDiagnostics.DefaultReason('noCandidates');
        end;
        if Assigned(FLog) then
        begin
          FLog(Format('completion: %d Einträge (%d vorab), unvollständig %s, Baum %d ms, gesamt %d ms',
            [Answer.SentCount + Length(Items), Answer.SentCount, BoolToStr(Answer.Incomplete, True), ParseMs,
            Watch.ElapsedMilliseconds]));
        end;
      finally
        Resolver.UnpinTree;
      end;
    finally
      Resolver.Free;
    end;
  finally
    Answer.Free;
    Request.Free;
  end;
end;

function VisibilityText(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Published: Result := 'published';
    TIndexVisibility.Protected: Result := 'protected';
    TIndexVisibility.StrictProtected: Result := 'strict protected';
    TIndexVisibility.Private: Result := 'private';
    TIndexVisibility.StrictPrivate: Result := 'strict private';
  else
    Result := 'public';
  end;
end;

/// <summary>Zeilen von AText ohne Zeilenende.</summary>
function TextLines(const AText: string): TArray<string>;
var
  Index: Integer;
begin
  Result := AText.Split([#10]);
  for Index := 0 to High(Result) do
  begin
    if Result[Index].EndsWith(#13) then
    begin
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
    end;
  end;
end;

/// <summary>Deklaration von ARange; über mehr als MaxLines Zeilen (Klassen, Records) nur die erste.</summary>
function DeclarationOf(const ALines: TArray<string>; const ARange: TTextRange): string;
begin
  Result := TInterfaceStubs.DeclarationOf(ALines, ARange);
end;

/// <summary>Vorfahrenliste der Klasse ab Zeile AStartLine wie im Quelltext, samt Typargumenten
/// ("TInterfacedObject", "IComparer&lt;TKunde&gt;"); nil, wenn kein "class(" folgt (#466).</summary>
function HeaderAncestors(const ALines: TArray<string>; AStartLine: Integer): TArray<string>;
begin
  Result := TInterfaceStubs.HeaderAncestors(ALines, AStartLine);
end;

/// <summary>Zeilen von AFileName, je Datei einmal gelesen (Code-Review P-07); AText für die eigene Datei
/// AOwnFile. False, wenn die Datei nicht lesbar ist (auch das merkt sich ACache).</summary>
function CachedLines(ACache: TDictionary<string, TArray<string>>; const AFileName, AOwnFile, AText: string;
  const AReadText: TCompletionReadText; out ALines: TArray<string>): Boolean;
var
  Key, Source: string;
begin
  Key := AnsiUpperCase(AFileName);
  if not ACache.TryGetValue(Key, ALines) then
  begin
    ALines := nil;
    if SameText(AFileName, AOwnFile) then
    begin
      ALines := TextLines(AText);
    end
    else if Assigned(AReadText) and AReadText(AFileName, Source) then
    begin
      ALines := TextLines(Source);
    end;
    // nil steht für "nicht lesbar"; TextLines liefert sonst mindestens eine Zeile.
    ACache.Add(Key, ALines);
  end;
  Result := ALines <> nil;
end;

/// <summary>Setzt Bindungen "T=TKunde" wortweise in AText ein (#466).</summary>
function SubstituteWords(const AText: string; const ABindings: TArray<string>): string;
begin
  Result := TInterfaceStubs.SubstituteWords(AText, ABindings);
end;

/// <summary>"IComparer&lt;TKunde&gt;" aus Container und Bindungen; ohne Bindungen der Container.</summary>
function GenericName(const AContainer: string; const ABindings: TArray<string>): string;
begin
  Result := TInterfaceStubs.GenericName(AContainer, ABindings);
end;

/// <summary>Direktiven einer Deklaration (virtual, override, deprecated ...); ADeprecated: Text
/// hinter deprecated, '' ohne Text; AIsDeprecated: deprecated kommt vor.</summary>
function DirectivesOf(const ADeclaration: string; out ADeprecated: string; out AIsDeprecated: Boolean): TArray<string>;
const
  Known: array[0..13] of string = ('class', 'static', 'virtual', 'dynamic', 'override', 'abstract', 'final',
    'reintroduce', 'overload', 'inline', 'message', 'deprecated', 'platform', 'experimental');
var
  Text, Word: string;
  Index, Start, Quote: Integer;
  Words: TArray<string>;
begin
  Result := nil;
  ADeprecated := '';
  AIsDeprecated := False;
  // Strings ausblenden, damit Wörter darin nicht zählen; den deprecated-Text merken.
  Text := '';
  Index := 1;
  while Index <= Length(ADeclaration) do
  begin
    if ADeclaration[Index] = '''' then
    begin
      Quote := PosEx('''', ADeclaration, Index + 1);
      if Quote = 0 then
      begin
        Quote := Length(ADeclaration);
      end;
      if EndsText('deprecated', TrimRight(Text)) then
      begin
        ADeprecated := Copy(ADeclaration, Index + 1, Quote - Index - 1);
      end;
      Text := Text + ' ';
      Index := Quote + 1;
      Continue;
    end;
    Text := Text + ADeclaration[Index];
    Inc(Index);
  end;
  Words := nil;
  Start := 0;
  for Index := 1 to Length(Text) + 1 do
  begin
    if (Index > Length(Text)) or not CharInSet(Text[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      if Index - 1 > Start then
      begin
        Words := Words + [LowerCase(Copy(Text, Start + 1, Index - 1 - Start))];
      end;
      Start := Index;
    end;
  end;
  // "class" nur am Anfang (class function), sonst wäre jeder Klassentyp eine Klassenmethode.
  for Index := 0 to High(Words) do
  begin
    Word := Words[Index];
    if not MatchStr(Word, Known) or ((Word = 'class') and (Index > 0)) then
    begin
      Continue;
    end;
    if (Word = 'class') and ((High(Words) < 1) or not MatchStr(Words[1], ['function', 'procedure', 'property',
      'operator', 'constructor', 'destructor', 'var'])) then
    begin
      Continue;
    end;
    if Word = 'deprecated' then
    begin
      AIsDeprecated := True;
    end;
    if IndexStr(Word, Result) < 0 then
    begin
      Result := Result + [Word];
    end;
  end;
end;

class function TLspCompletion.Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
  const APosition: TTextPosition): TJSONObject;
begin
  Result := Details(AIndex, AFileName, AText, APosition, nil);
end;

class function TLspCompletion.Details(const AIndex: ISymbolIndex; const AFileName, AText: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText): TJSONObject;
var
  Lines: TArray<string>;
  UnitInfo: TUnitIndex;
  Symbol, Candidate: TIndexSymbol;
  Found, IsDeprecated: Boolean;
  Declaration, Deprecated: string;
  Directives: TArray<string>;
  Directive: string;
  Doc: TXmlDoc;
  Entry: TXmlDocEntry;
  List: TJSONArray;
  Item: TJSONObject;
  Range: TTextRange;
  Resolver: TNameResolver;
  Container: string;
begin
  Result := TJSONObject.Create;
  Lines := TextLines(AText);
  Found := False;
  Symbol := Default(TIndexSymbol);
  // Auch für Include-Dateien (#500): Unit, die sie einbindet; Symbole nur aus dieser Datei.
  if TIndexFiles.UnitOf(AIndex, AFileName, UnitInfo) then
  begin
    Result.AddPair('unit', UnitInfo.UnitName);
    for Candidate in UnitInfo.Symbols do
    begin
      if (Candidate.SelectionRange.StartPos.Line = APosition.Line) and
        (Candidate.SelectionRange.StartPos.Character = APosition.Character) and
        SameText(UnitInfo.SymbolFile(Candidate), AFileName) then
      begin
        Symbol := Candidate;
        Found := True;
        Break;
      end;
    end;
  end;
  if Found then
  begin
    Range := Symbol.Range;
  end
  else
  begin
    // Nicht im Index (lokale Variable, Parameter): die Zeile ab dem Namen.
    Range.StartPos := APosition;
    Range.EndPos := APosition;
  end;
  Declaration := DeclarationOf(Lines, Range);
  if Declaration <> '' then
  begin
    Result.AddPair('declaration', Declaration);
  end;
  if Found and (Symbol.Container <> '') then
  begin
    Result.AddPair('container', Symbol.Container);
    Result.AddPair('visibility', VisibilityText(Symbol.Visibility));
    // Mitglied eines Helpers (#456): Das Panel zeigt dann „Helper · Unit“.
    for Candidate in UnitInfo.Symbols do
    begin
      if (Candidate.Kind = TIndexSymbolKind.HelperType) and SameText(Candidate.QualifiedName, Symbol.Container) then
      begin
        Result.AddPair('helper', TJSONBool.Create(True));
        Break;
      end;
    end;
  end;
  Directives := DirectivesOf(Declaration, Deprecated, IsDeprecated);
  if Length(Directives) > 0 then
  begin
    List := TJSONArray.Create;
    for Directive in Directives do
    begin
      List.Add(Directive);
    end;
    Result.AddPair('directives', List);
  end;
  if IsDeprecated then
  begin
    Result.AddPair('deprecated', Deprecated);
  end;
  // XMLDoc wie im Hover (#654): mit <inheritdoc/> und den Fundorten der cref-Verweise.
  Resolver := TNameResolver.Create(AIndex);
  try
    if Found then
    begin
      Doc := TLspDocumentation.Load(Resolver, TResolvedSymbol.FromIndex(UnitInfo, Symbol), Lines, Range.StartPos.Line,
        TLspDocumentation.Reader(AFileName, AText, AReadText));
    end
    else
    begin
      Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove(Lines, Range.StartPos.Line));
    end;
    if not Doc.IsEmpty then
    begin
      Container := '';
      if Found then
      begin
        Container := Symbol.Container;
        if Container = '' then
        begin
          Container := Symbol.Name;
        end;
        Result.AddPair('documentation', TLspDocumentation.ToJson(Doc,
          TLspDocumentation.Targets(Resolver, UnitInfo, Container, Doc)));
      end
      else
      begin
        Result.AddPair('documentation', TLspDocumentation.ToJson(Doc, nil));
      end;
      Result.AddPair('documentationText', Doc.ToPlainText);
      // Nur für documentation in completionItem/resolve; HandleResolve nimmt es wieder heraus.
      Result.AddPair('documentationMarkdown', Doc.ToMarkdown);
    end;
  finally
    Resolver.Free;
  end;
  if Doc.Summary <> '' then
  begin
    Result.AddPair('summary', Doc.Summary);
  end;
  if Doc.Returns <> '' then
  begin
    Result.AddPair('returns', Doc.Returns);
  end;
  if Doc.Remarks <> '' then
  begin
    Result.AddPair('remarks', Doc.Remarks);
  end;
  if Length(Doc.Params) > 0 then
  begin
    List := TJSONArray.Create;
    for Entry in Doc.Params do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', Entry.Name);
      Item.AddPair('text', Entry.Text);
      List.AddElement(Item);
    end;
    Result.AddPair('params', List);
  end;
  if Length(Doc.Exceptions) > 0 then
  begin
    List := TJSONArray.Create;
    for Entry in Doc.Exceptions do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', Entry.Name);
      Item.AddPair('text', Entry.Text);
      List.AddElement(Item);
    end;
    Result.AddPair('exceptions', List);
  end;
end;

function TLspCompletion.HandleResolve(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Item, Data, Details: TJSONObject;
  Documentation, Binding: TJSONValue;
  FileName, Text: string;
  Position: TTextPosition;
  Bindings: TArray<string>;
begin
  if not (AParams is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'CompletionItem fehlt in ' + ResolveMethod);
  end;
  // Antwort ist der Eintrag selbst, ergänzt um Details; ohne data unverändert.
  Item := TJSONObject(AParams.Clone);
  Result := Item;
  if not (Item.GetValue('data') is TJSONObject) or not Assigned(FReadText) then
  begin
    Exit;
  end;
  Data := TJSONObject(Item.GetValue('data'));
  if not (Data.TryGetValue<string>('file', FileName) and Data.TryGetValue<Integer>('line', Position.Line) and
    Data.TryGetValue<Integer>('character', Position.Character)) then
  begin
    Exit;
  end;
  if not ReadCached(FileName, Text) then
  begin
    Exit;
  end;
  Details := TLspCompletion.Details(FIndex, FileName, Text, Position, ReadCached);
  // Gebundene Typparameter (#450): "procedure Add(const Value: T)" wird zu "... Value: TKunde)".
  Bindings := nil;
  if Data.GetValue('bindings') is TJSONArray then
  begin
    for Binding in TJSONArray(Data.GetValue('bindings')) do
    begin
      Bindings := Bindings + [Binding.Value];
    end;
  end;
  if (Length(Bindings) > 0) and Details.TryGetValue<string>('declaration', Text) then
  begin
    Details.RemovePair('declaration').Free;
    Details.AddPair('declaration', SubstituteWords(Text, Bindings));
  end;
  // Für Atlas (Detailpanel) strukturiert in data.atlas; für andere Clients detail und documentation.
  if Details.TryGetValue<string>('declaration', Text) then
  begin
    Item.RemovePair('detail').Free;
    Item.AddPair('detail', Text);
  end;
  // Doku als Klartext oder Markdown, je nach documentationFormat des Clients (#31).
  Documentation := ResolveDocumentation(Details, FDocumentationMarkdown);
  if Documentation <> nil then
  begin
    Item.AddPair('documentation', Documentation);
  end;
  Details.RemovePair('documentationMarkdown').Free;
  if Assigned(FHintsFor) then
  begin
    Details.AddPair('xmlDoc', TLspDocumentation.HintsJson(FHintsFor(TDocumentUris.FromPath(FileName))));
  end;
  Data.AddPair('atlas', Details);
end;

/// <summary>Parameternamen aus "Name(const A, B: T; var C: U): R" in Reihenfolge (#443).</summary>
function OverrideParamNames(const AHead: string): TArray<string>;
var
  Open, Close: Integer;
  Group, Names, Name: string;
begin
  Result := nil;
  Open := Pos('(', AHead);
  Close := LastDelimiter(')', AHead);
  if (Open = 0) or (Close <= Open) then
  begin
    Exit;
  end;
  for Group in Copy(AHead, Open + 1, Close - Open - 1).Split([';']) do
  begin
    Names := Group;
    if Pos(':', Names) > 0 then
    begin
      Names := Copy(Names, 1, Pos(':', Names) - 1);
    end;
    Names := Trim(Names);
    for Name in ['const ', 'var ', 'out ', 'constref '] do
    begin
      if StartsText(Name, Names) then
      begin
        Names := Trim(Copy(Names, Length(Name) + 1, MaxInt));
      end;
    end;
    for Name in Names.Split([',']) do
    begin
      if Trim(Name) <> '' then
      begin
        Result := Result + [Trim(Name)];
      end;
    end;
  end;
end;

/// <summary>Kopf "Name(...): T" und Direktiven aus "procedure Name(...): T; virtual; overload;".</summary>
function SplitOverrideDeclaration(const ADeclaration: string; out AIsClass: Boolean; out AKind, AHead,
  ADirectives: string): Boolean;
begin
  Result := TInterfaceStubs.Split(ADeclaration, AIsClass, AKind, AHead, ADirectives);
end;

/// <summary>Innerster Klassen- bzw. Objekttyp (mit ARecords auch Record), in dessen Deklaration ALine liegt;
/// ATypeName samt umgebendem Typ.</summary>
function EnclosingType(const AUnit: TUnitIndex; ALine: Integer; ARecords: Boolean; out ATypeName: string): Boolean;
var
  Kinds: TIndexSymbolKinds;
  TypeSymbol: TIndexSymbol;
begin
  ATypeName := '';
  Kinds := [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  if ARecords then
  begin
    Include(Kinds, TIndexSymbolKind.RecordType);
  end;
  Result := EnclosingTypeAt(AUnit, ALine, Kinds, 0, True, TypeSymbol);
  if Result then
  begin
    ATypeName := QualifiedTypeName(TypeSymbol);
  end;
end;

class function TLspCompletion.PropertyItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  out AItems: TCompletionItems): Boolean;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.Matching := AMatching;
    Result := PropertyItems(Request, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.ResourceStringItems(ARequest: TCompletionRequest; ASnippets: Boolean;
  out AItems: TCompletionItems): Boolean;
const
  AddCommand = 'atlas.server.addResourceString';
var
  Literal: TResourceLiteral;
  Entries, TargetEntries: TArray<TResourceEntry>;
  Existing: TResourceEntry;
  Taken: TArray<string>;
  Symbol: TIndexSymbol;
  Target: TUnitIndex;
  TargetText, Name, Declaration, LB, Range: string;
  HasTarget, HasExisting: Boolean;
  Edit, UsesEdit: TTextEdit;
  UsesEdits: TArray<TRuleEdit>;
  Item: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  if not ARequest.Settings.ResourceStrings or (ARequest.Trigger <> '') or (ARequest.Tree = nil) or
    not TResourceStrings.LiteralAt(ARequest.Text, ARequest.Tree.Tokens, ARequest.Position, Literal) or
    not TResourceStrings.Allowed(ARequest.Tree, Literal.StartOffset) then
  begin
    Exit;
  end;
  LB := ARequest.LineBreak;
  Entries := TResourceStrings.Entries(ARequest.Text, ARequest.Tree.Tokens);
  Taken := nil;
  for Symbol in ARequest.UnitIndex.Symbols do
  begin
    Taken := Taken + [Symbol.Name];
  end;
  for Existing in Entries do
  begin
    Taken := Taken + [Existing.Name];
  end;
  // Festgelegte Unit (completion.resourceStringUnit): nur wenn der Index sie kennt und sie lesbar ist.
  HasTarget := False;
  TargetText := '';
  UsesEdits := nil;
  if (ARequest.Settings.ResourceStringUnit <> '') and
    not SameText(ARequest.Settings.ResourceStringUnit, TUsesClauses.OwnName(ARequest.Tree.Tokens)) and
    (ARequest.Index <> nil) and ARequest.Index.FindUnit(ARequest.Settings.ResourceStringUnit, Target) and
    Assigned(ARequest.ReadText) and ARequest.ReadText(Target.FileName, TargetText) then
  begin
    HasTarget := True;
    TargetEntries := TResourceStrings.Entries(TargetText, TPascalLexer.Tokenize(TargetText));
    for Symbol in Target.Symbols do
    begin
      Taken := Taken + [Symbol.Name];
    end;
    for Existing in TargetEntries do
    begin
      Taken := Taken + [Existing.Name];
    end;
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ARequest.Tree.Tokens), Target.UnitName,
      ARequest.Resolver.Namespaces) and TUsesClauses.AddUnit(ARequest.Tree.Tokens, Literal.StartOffset,
      Target.UnitName, LB, UsesEdit) then
    begin
      UsesEdits := [UsesEdit];
    end;
    HasExisting := TResourceStrings.SameText(TargetEntries, Literal.Text, True, -1, Existing);
  end
  else
  begin
    HasExisting := TResourceStrings.SameText(Entries, Literal.Text, False, Literal.Range.StartPos.Line, Existing);
  end;
  Range := Literal.Source;
  if Length(Range) > 40 then
  begin
    Range := Copy(Range, 1, 39) + '…';
  end;
  // Gleicher Text schon vorhanden: zuerst diesen verwenden.
  if HasExisting then
  begin
    Item := Default(TCompletionItem);
    Item.Name := Format('Vorhandenen verwenden: %s', [Existing.Name]);
    Item.Kind := KindConstant;
    Item.Detail := Format('%s = %s', [Existing.Name, Existing.Value]);
    Item.Fits := True;
    Item.Pinned := True;
    Item.Action := 'create';
    Item.HasTextEdit := True;
    Item.TextEdit := TRuleEdit.Create(Literal.Range, Existing.Name);
    Item.AdditionalEdits := UsesEdits;
    AItems.Items := AItems.Items + [Item];
  end;
  Name := TResourceStrings.UniqueName(TResourceStrings.NameFor(Literal.Text), Taken);
  Declaration := Format('%s = %s;', [Name, Literal.Source]);
  Item := Default(TCompletionItem);
  Item.Name := 'Als resourcestring auslagern';
  Item.Kind := KindConstant;
  Item.Fits := True;
  Item.Pinned := True;
  Item.Action := 'create';
  Item.HasTextEdit := True;
  if HasTarget then
  begin
    // Der Eintrag in der anderen Unit kommt über den Befehl; deren Puffer ist ein eigener Undo-Schritt.
    Item.Detail := Format('%s = %s in %s', [Name, Range, Target.UnitName]);
    Item.TextEdit := TRuleEdit.Create(Literal.Range, Name);
    Item.AdditionalEdits := UsesEdits;
    Item.Command := AddCommand;
    Item.CommandTitle := Item.Name;
    Item.CommandArguments := [Target.FileName, Name, Literal.Source];
  end
  else
  begin
    if not TResourceStrings.Insertion(ARequest.Text, ARequest.Tree.Tokens,
      TResourcePlace.Create(False, Literal.Range.StartPos.Line), Declaration, LB, Edit) then
    begin
      Exit(Length(AItems.Items) > 0);
    end;
    Item.Detail := Format('%s = %s', [Name, Range]);
    Item.TextEdit := TRuleEdit.Create(Literal.Range, Name);
    // Platzhalter-Modus (#51): Der Name ist an beiden Stellen derselbe Platzhalter.
    if ASnippets then
    begin
      Item.Snippet := True;
      Item.LinkedEdits := True;
      Item.TextEdit.NewText := '${1:' + Name + '}';
      Edit.NewText := StringReplace(TContextSnippets.Escape(Edit.NewText), Name + ' = ', '${1:' + Name + '} = ',
        []);
    end;
    Item.AdditionalEdits := [Edit];
  end;
  AItems.Items := AItems.Items + [Item];
  Result := True;
end;

class function TLspCompletion.AccessorItems(ARequest: TCompletionRequest; const APropertyName, APropertyType,
  AIndexParameters: string; AIsWrite: Boolean; const APrefix: string): TArray<TCompletionItem>;
const
  Titles: array[TAccessorKind] of string = ('Feld %s anlegen', '%s anlegen', '%s anlegen');
var
  Slash: TSlashContext;
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Kinds: TArray<TAccessorKind>;
  Kind: TAccessorKind;
  Plan: TAccessorPlan;
  Edits: TArray<TTextEdit>;
  WithField: Boolean;
  Item: TCompletionItem;
  Lines: TArray<string>;
begin
  Result := nil;
  // Ein Feld nur ohne Indexparameter: read FWert[I] gibt es nicht.
  Kinds := nil;
  if AIndexParameters = '' then
  begin
    Kinds := [TAccessorKind.Field];
  end;
  if AIsWrite then
  begin
    Kinds := Kinds + [TAccessorKind.Setter];
  end
  else
  begin
    Kinds := Kinds + [TAccessorKind.Getter];
  end;
  Lines := ARequest.Lines;
  Slash := Default(TSlashContext);
  Slash.Text := ARequest.Text;
  Slash.Line := ARequest.Position.Line;
  if ARequest.Position.Line <= High(Lines) then
  begin
    Slash.LineText := Lines[ARequest.Position.Line];
  end;
  Slash.Index := ARequest.Index;
  Source := TCommandSource.Create(Slash);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit;
    end;
    for Kind in Kinds do
    begin
      Plan := Default(TAccessorPlan);
      Plan.Kind := Kind;
      Plan.PropertyName := APropertyName;
      Plan.PropertyType := APropertyType.Trim;
      Plan.IndexParameters := AIndexParameters;
      Plan.MethodSection := 'private';
      if ARequest.Settings.AccessorSection = TCompletionAccessorSection.Protected then
      begin
        Plan.MethodSection := 'protected';
      end;
      if not TAccessorCreation.Edits(Source, ARequest.Index, ClassSymbol, Plan, Edits, WithField) then
      begin
        Continue;
      end;
      Item := Default(TCompletionItem);
      Item.Name := Format(Titles[Kind], [Plan.Name]);
      Item.Kind := KindMethod;
      if Kind = TAccessorKind.Field then
      begin
        Item.Kind := KindField;
      end;
      Item.Detail := TAccessorCreation.Declaration(Plan);
      Item.Fits := True;
      Item.Pinned := True;
      Item.Action := 'create';
      Item.HasTextEdit := True;
      // Der getippte Anfang wird zum Namen: "read Ca|" → "read FCaption".
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ARequest.Position.Line,
        ARequest.Position.Character - Length(APrefix)), ARequest.Position), Plan.Name);
      Item.AdditionalEdits := Edits;
      if WithField then
      begin
        Plan.Kind := TAccessorKind.Field;
        Item.Detail := Item.Detail + ' + ' + TAccessorCreation.Declaration(Plan);
      end;
      Result := Result + [Item];
    end;
  finally
    Source.Free;
  end;
end;

class function TLspCompletion.PropertyItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  Match: TMatch;
  UnitIndex: TUnitIndex;
  TypeName, PropType, Prefix, Param: string;
  IndexCount: Integer;
  IsWrite, Fits: Boolean;
  Candidate: TResolvedSymbol;
  Item: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  // "  property Wert[I: Integer]: Double read |", auch mit "index 3" und schon gesetztem read vor write.
  Match := TRegEx.Match(ARequest.LineBefore, '^\s*(?:class\s+)?property\s+(\w+)\s*(\[[^\]]*\])?\s*:\s*' +
    '([\w.<>, ]+?)\s+(?:index\s+\S+\s+)?(?:read\s+\w+\s+)?(read|write)\s+(\w*)$', [roIgnoreCase]);
  if not Match.Success then
  begin
    Exit;
  end;
  UnitIndex := ARequest.UnitIndex;
  if not EnclosingType(UnitIndex, ARequest.Position.Line, True, TypeName) then
  begin
    Exit;
  end;
  Result := True;
  PropType := Match.Groups[3].Value;
  IsWrite := SameText(Match.Groups[4].Value, 'write');
  Prefix := Match.Groups[5].Value;
  // Feld und Zugriffsmethoden anlegen (#467): oben vor den passenden Mitgliedern.
  if ARequest.Settings.CreateAccessors then
  begin
    AItems.Items := AccessorItems(ARequest, Match.Groups[1].Value, PropType,
      Match.Groups[2].Value.Trim(['[', ']']).Trim, IsWrite, Prefix);
  end;
  // Indexparameter: "[I, J: Integer; const S: string]" sind drei.
  IndexCount := 0;
  for Param in Match.Groups[2].Value.Trim(['[', ']']).Split([';']) do
  begin
    if Pos(':', Param) > 0 then
    begin
      Inc(IndexCount, Length(Copy(Param, 1, Pos(':', Param) - 1).Split([','])));
    end;
  end;
  for Candidate in ARequest.Resolver.Queries.AccessorCandidates(UnitIndex, TypeName) do
  begin
    if Candidate.SymbolKind = TIndexSymbolKind.Field then
    begin
      Fits := (IndexCount = 0) and (PlainType(Candidate.TypeName) = PlainType(PropType));
    end
    else if IsWrite then
    begin
      Fits := (Candidate.TypeName = '') and (Candidate.MinArgs <= IndexCount + 1) and
        (Candidate.MaxArgs >= IndexCount + 1) and (Length(Candidate.ParamTypes) > IndexCount) and
        (PlainType(Candidate.ParamTypes[IndexCount]) = PlainType(PropType));
    end
    else
    begin
      Fits := (Candidate.TypeName <> '') and (PlainType(Candidate.TypeName) = PlainType(PropType)) and
        (Candidate.MinArgs <= IndexCount) and (Candidate.MaxArgs >= IndexCount);
    end;
    if not Fits or (MatchScore(Candidate.Name, Prefix, ARequest.Matching) = TFuzzyMatch.NoMatch) then
    begin
      Continue;
    end;
    Item := Default(TCompletionItem);
    Item.Name := Candidate.Name;
    Item.Kind := KindOf(Candidate.SymbolKind);
    if Candidate.TypeName <> '' then
    begin
      Item.Detail := Candidate.TypeName;
    end
    else
    begin
      Item.Detail := Candidate.Container;
    end;
    Item.Container := Candidate.Container;
    Item.Depth := Candidate.Depth;
    Item.SourceFile := Candidate.FileName;
    Item.SourcePosition := Candidate.SelectionRange.StartPos;
    if (ARequest.Matching = TCompletionMatching.Fuzzy) and not Candidate.Name.StartsWith(Prefix, True) then
    begin
      Item.FilterText := Prefix;
    end;
    AItems.Items := AItems.Items + [Item];
  end;
end;

class function TLspCompletion.OverrideItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.ReadText := AReadText;
    Result := OverrideItems(Request, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.OverrideItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  Match: TMatch;
  UnitIndex: TUnitIndex;
  TypedClass, IsClass, IsAbstract, AfterOverride: Boolean;
  TypedKind, TypeName, Declaration, Kind, Head, Directives, Insert, Body, Args, LB, MethodName,
    Line, Lead: string;
  Candidate: TResolvedSymbol;
  Item: TCompletionItem;
  Edit: TRuleEdit;
  SourceLines: TArray<string>;
  Files: TDictionary<string, TArray<string>>;
  Items: TList<TCompletionItem>;
  DefaultValue: TRegEx;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  // "    procedure Ch|", "    function |", "    class procedure |"
  Line := ARequest.LineBefore;
  Match := TRegEx.Match(Line, '^\s*(class\s+)?(procedure|function)\s+(\w*)$', [roIgnoreCase]);
  AfterOverride := False;
  TypedClass := False;
  TypedKind := '';
  if Match.Success then
  begin
    TypedClass := Match.Groups[1].Length > 0;
    TypedKind := LowerCase(Match.Groups[2].Value);
  end
  else
  begin
    // "    override Ch|" (#31): beide Arten; Übernehmen macht aus der Zeile die Deklaration.
    Match := TRegEx.Match(Line, '^(\s*)override\s+(\w*)$', [roIgnoreCase]);
    if not Match.Success then
    begin
      Exit;
    end;
    AfterOverride := True;
  end;
  // Innerster Klassentyp, in dessen Deklaration die Zeile liegt.
  UnitIndex := ARequest.UnitIndex;
  if not EnclosingType(UnitIndex, ARequest.Position.Line, False, TypeName) then
  begin
    Exit;
  end;
  Result := True;
  LB := ARequest.LineBreak;
  // Je Vorfahren-Unit einmal lesen und zerlegen statt je Kandidat (Code-Review P-07); das Muster für
  // Standardwerte einmal übersetzen (P-11). Lokal, weil die Vervollständigung nebenläufig läuft.
  DefaultValue := TRegEx.Create('\s*=\s*[^;)]+');
  Files := TDictionary<string, TArray<string>>.Create;
  Items := TList<TCompletionItem>.Create;
  try
    for Candidate in ARequest.Resolver.Queries.OverridableMembers(UnitIndex, TypeName) do
    begin
      if not CachedLines(Files, Candidate.FileName, ARequest.FileName, ARequest.Text, ARequest.ReadText,
        SourceLines) then
      begin
        Continue;
      end;
      Declaration := DeclarationOf(SourceLines, Candidate.Range);
      if not SplitOverrideDeclaration(Declaration, IsClass, Kind, Head, Directives) or
        (not AfterOverride and ((Kind <> TypedKind) or (IsClass <> TypedClass))) then
      begin
        Continue;
      end;
      IsAbstract := Directives.Contains(' abstract ');
      Insert := Head + ';';
      if Directives.Contains(' overload ') then
      begin
        Insert := Insert + ' overload;';
      end;
      Insert := Insert + ' override;';
      // Rumpf: Kopf mit Typ, inherited bzw. Result := inherited ...; abstrakt ohne inherited.
      MethodName := Candidate.Name;
      Args := String.Join(', ', OverrideParamNames(Head));
      // Standardwerte stehen nur in der Deklaration.
      Body := Kind + ' ' + TypeName + '.' + DefaultValue.Replace(Head, '') + ';';
      if IsClass then
      begin
        Body := 'class ' + Body;
      end;
      Body := Body + LB + 'begin' + LB;
      if IsAbstract then
      begin
        Body := Body + LB;
      end
      else if Kind = 'procedure' then
      begin
        Body := Body + '  inherited;' + LB;
      end
      else if Args <> '' then
      begin
        Body := Body + '  Result := inherited ' + MethodName + '(' + Args + ');' + LB;
      end
      else
      begin
        Body := Body + '  Result := inherited ' + MethodName + ';' + LB;
      end;
      Body := Body + 'end;';
      Item := Default(TCompletionItem);
      Item.Name := MethodName;
      Item.Kind := KindMethod;
      Item.Detail := Declaration;
      Item.InsertText := Insert;
      Item.Action := 'override';
      Item.Container := Candidate.Container;
      Item.Depth := Candidate.Depth;
      Item.SourceFile := Candidate.FileName;
      Item.SourcePosition := Candidate.SelectionRange.StartPos;
      if AfterOverride then
      begin
        // "override Name" wird zu "procedure Name(...); override;".
        Lead := Kind + ' ';
        if IsClass then
        begin
          Lead := 'class ' + Lead;
        end;
        Item.InsertText := '';
        Item.HasTextEdit := True;
        Item.TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ARequest.Position.Line,
          Match.Groups[1].Length), ARequest.Position), Lead + Insert);
        Item.FilterText := 'override ' + MethodName;
      end;
      if TClassCompletion.BodyEdit(ARequest.Tree, ARequest.Text, TypeName, Body, Edit) then
      begin
        Item.AdditionalEdits := [Edit];
      end;
      Items.Add(Item);
    end;
    AItems.Items := Items.ToArray;
  finally
    Items.Free;
    Files.Free;
  end;
end;

class function TLspCompletion.InterfaceItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  ASection: TCompletionInterfaceSection; out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
var
  Request: TCompletionRequest;
  Settings: TCompletionSettings;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.ReadText := AReadText;
    Settings := Request.Settings;
    Settings.InterfaceSection := ASection;
    Request.Settings := Settings;
    Result := InterfaceItems(Request, AItems, ABatch);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.InterfaceItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
  out ABatch: Boolean): Boolean;
const
  SectionNames: array[TCompletionInterfaceSection] of string = ('private', 'protected', 'public');
var
  Match: TMatch;
  UnitIndex: TUnitIndex;
  TypeSymbol: TIndexSymbol;
  NeedHeader: Boolean;
  Lines, SourceLines: TArray<string>;
  TypeName, LB, Indent, Section: string;
  EndLine, Index, Count: Integer;
  Files: TDictionary<string, TArray<string>>;
  Missing: TArray<TResolvedSymbol>;
  Stub: TInterfaceStub;
  Interfaces: TArray<string>;
  Item: TCompletionItem;
  Edit: TRuleEdit;
  Edits, Group: TArray<TRuleEdit>;
  WordRange: TTextRange;

  procedure AddHint(const AInterface: string);
  var
    Hint: TCompletionItem;
  begin
    if Count = 0 then
    begin
      Exit;
    end;
    Hint := Default(TCompletionItem);
    if Count = 1 then
    begin
      Hint.Name := Format('1 Methode von %s fehlt', [AInterface]);
    end
    else
    begin
      Hint.Name := Format('%d Methoden von %s fehlen', [Count, AInterface]);
    end;
    Hint.Detail := 'Interface implementieren';
    Hint.Kind := KindSnippet;
    Hint.Hint := True;
    Hint.Action := 'implement';
    Hint.Container := AInterface;
    // Das angefangene Wort verschwindet, die Methoden kommen über die weiteren Änderungen.
    Hint.HasTextEdit := True;
    Hint.TextEdit := TRuleEdit.Create(WordRange, '');
    Hint.AdditionalEdits := TInterfaceStubs.Merge(Group);
    AItems := AItems + [Hint];
  end;

begin
  AItems := nil;
  ABatch := False;
  Result := False;
  // "    |" (Strg+Leer auf leerer Zeile) bzw. "    Exp|"
  Match := TRegEx.Match(ARequest.LineBefore, '^(\s*)(\w*)$');
  if not Match.Success then
  begin
    Exit;
  end;
  Lines := ARequest.Lines;
  if (ARequest.Position.Line < 0) or (ARequest.Position.Line > High(Lines)) then
  begin
    Exit;
  end;
  ABatch := Match.Groups[2].Length = 0;
  // Leere Zeile nur, wenn auch dahinter nichts steht; vor einer vorhandenen Deklaration bleibt Strg+Leer normal.
  if ABatch and (Trim(Copy(Lines[ARequest.Position.Line], ARequest.Position.Character + 1, MaxInt)) <> '') then
  begin
    Exit;
  end;
  // Innerste Klasse, zwischen deren Kopf und "end" der Cursor steht.
  UnitIndex := ARequest.UnitIndex;
  // Nur Klassen mit Interfaces in der Vorfahrenliste; "end" in der Zeile des Cursors zählt nicht mehr dazu.
  if not EnclosingTypeAt(UnitIndex, ARequest.Position.Line, [TIndexSymbolKind.ClassType], 2, False, TypeSymbol) then
  begin
    Exit;
  end;
  EndLine := TypeSymbol.Range.EndPos.Line;
  if (EndLine > High(Lines)) or not TRegEx.IsMatch(Lines[EndLine], '^\s*end\b', [roIgnoreCase]) then
  begin
    Exit;
  end;
  Indent := Copy(Lines[EndLine], 1, Length(Lines[EndLine]) - Length(TrimLeft(Lines[EndLine])));
  TypeName := QualifiedTypeName(TypeSymbol);
  // Vorfahrenliste aus dem Quelltext: Der Index kennt die Typargumente nur beim ersten Vorfahren.
  Missing := ARequest.Resolver.Queries.MissingInterfaceMembers(UnitIndex, TypeName,
    HeaderAncestors(Lines, TypeSymbol.Range.StartPos.Line));
  if Length(Missing) = 0 then
  begin
    Exit;
  end;
  LB := ARequest.LineBreak;
  Section := SectionNames[ARequest.Settings.InterfaceSection];
  NeedHeader := TInterfaceStubs.LastSection(ARequest.Tree.Tokens, TypeSymbol.Range.StartPos.Line, EndLine) <> Section;
  WordRange := TTextRange.Create(ARequest.Position.Line, Match.Groups[1].Length, ARequest.Position.Line,
    ARequest.Position.Character);
  Interfaces := nil;
  Group := nil;
  Count := 0;
  // Je Datei einmal lesen, auch wenn die Interfaces abwechselnd aus mehreren Units stammen (Code-Review P-07).
  Files := TDictionary<string, TArray<string>>.Create;
  try
    for Index := 0 to High(Missing) do
    begin
      if not CachedLines(Files, Missing[Index].FileName, ARequest.FileName, ARequest.Text, ARequest.ReadText,
        SourceLines) then
      begin
        SourceLines := TextLines('');
      end;
      // Generische Interfaces: Typargumente in die Deklaration einsetzen (IComparer<TKunde>: T → TKunde).
      if not TInterfaceStubs.Make(GenericName(Missing[Index].Container, Missing[Index].Bindings), TypeName,
        SubstituteWords(DeclarationOf(SourceLines, Missing[Index].Range), Missing[Index].Bindings), LB, Stub) then
      begin
        Continue;
      end;
      if (Length(Interfaces) = 0) or not SameText(Interfaces[High(Interfaces)], Stub.InterfaceName) then
      begin
        if not ABatch and (Length(Interfaces) > 0) then
        begin
          AddHint(Interfaces[High(Interfaces)]);
        end;
        Interfaces := Interfaces + [Stub.InterfaceName];
        Group := nil;
        Count := 0;
      end;
      Edits := TInterfaceStubs.ClassEdits(Stub, EndLine, Indent, Section, NeedHeader, LB);
      if TClassCompletion.BodyEdit(ARequest.Tree, ARequest.Text, TypeName, Stub.Body, Edit) then
      begin
        Edits := Edits + [Edit];
      end;
      Group := Group + Edits;
      Inc(Count);
      if not ABatch then
      begin
        Continue;
      end;
      Item := Default(TCompletionItem);
      Item.Name := Stub.Name;
      Item.Kind := KindMethod;
      Item.Detail := Stub.Declaration;
      Item.Container := Stub.InterfaceName;
      Item.Action := 'implement';
      Item.Batch := True;
      Item.Ordinal := Length(AItems) + 1;
      Item.SetChecked := True;
      Item.SetRange := WordRange;
      Item.AdditionalEdits := Edits;
      Item.SourceFile := Missing[Index].FileName;
      Item.SourcePosition := Missing[Index].SelectionRange.StartPos;
      AItems := AItems + [Item];
    end;
  finally
    Files.Free;
  end;
  if not ABatch and (Length(Interfaces) > 0) then
  begin
    AddHint(Interfaces[High(Interfaces)]);
  end;
  // Eine Überschrift über der ganzen Liste: „Fehlende Methoden von IExporter, IInterface“.
  for Index := 0 to High(AItems) do
  begin
    if AItems[Index].Batch then
    begin
      AItems[Index].SetOf := string.Join(', ', Interfaces);
      AItems[Index].Expected := AItems[Index].SetOf;
      AItems[Index].Fits := True;
    end;
  end;
  Result := Length(AItems) > 0;
end;

/// <summary>Liegt APosition in ARange (Grenzen eingeschlossen)?</summary>
function RangeHas(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((APosition.Line > ARange.StartPos.Line) or ((APosition.Line = ARange.StartPos.Line) and
    (APosition.Character >= ARange.StartPos.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Innerste Routine aus AUnit (aus dem Baum), deren Bereich APosition enthält (Code-Review P-06,
/// P-11); lokale Prozeduren stehen nicht im Index, daher ist das die umgebende Methode bzw. Routine.</summary>
function RoutineAt(const AUnit: TUnitIndex; const APosition: TTextPosition; out ARoutine: TIndexSymbol): Boolean;
var
  Index: Integer;
begin
  Result := False;
  ARoutine := Default(TIndexSymbol);
  for Index := 0 to High(AUnit.Symbols) do
  begin
    if (AUnit.Symbols[Index].Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
      TIndexSymbolKind.Routine]) and RangeHas(AUnit.Symbols[Index].Range, APosition) and
      (not Result or (AUnit.Symbols[Index].Range.StartPos.Line >= ARoutine.Range.StartPos.Line)) then
    begin
      ARoutine := AUnit.Symbols[Index];
      Result := True;
    end;
  end;
end;

/// <summary>Zerlegt AFormText; False, wenn die Datei kein Wurzelobjekt hat.</summary>
function ParseForm(const AFormFile, AFormText: string; out ASnapshot: TFormSnapshot): Boolean;
var
  Document: TDfmDocument;
begin
  ASnapshot := Default(TFormSnapshot);
  Document := TDfmParser.Parse(AFormText);
  try
    Result := Document.Root <> nil;
    if Result then
    begin
      ASnapshot := TFormSnapshotCache.FromDocument(AFormFile, Document);
    end;
  finally
    Document.Free;
  end;
end;

/// <summary>Formular zur Unit über AReadText, ohne Zwischenspeicher (für Aufrufer ohne Instanz, z. B. Tests);
/// nil ohne AReadText.</summary>
function UncachedForms(const AReadText: TCompletionReadText): TCompletionFormFunc;
begin
  Result := nil;
  if not Assigned(AReadText) then
  begin
    Exit;
  end;
  Result :=
    function(const ASourceFile, ASourceText: string; out ASnapshot: TFormSnapshot): Boolean
    var
      FormFile, FormText: string;
    begin
      ASnapshot := Default(TFormSnapshot);
      for FormFile in TFormFiles.FormFiles(ASourceFile, ASourceText) do
      begin
        if AReadText(FormFile, FormText) and ParseForm(FormFile, FormText, ASnapshot) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

function TLspCompletion.FormSnapshot(const ASourceFile, ASourceText: string; out ASnapshot: TFormSnapshot): Boolean;
var
  FormFile, FormText, Stamp: string;
  Document: ITextDocument;
  Age: TDateTime;
begin
  ASnapshot := Default(TFormSnapshot);
  Result := False;
  if not Assigned(FReadText) then
  begin
    Exit;
  end;
  for FormFile in TFormFiles.FormFiles(ASourceFile, ASourceText) do
  begin
    // Stand des Auszugs (Code-Review P-06): Offene Formulare (Designer) über ihren Text – die Versionsnummer
    // beginnt nach Schließen und erneutem Öffnen wieder vorn –, Dateien auf der Platte über die Dateizeit.
    // Ohne Stand wird nicht zwischengespeichert.
    Stamp := '';
    FormText := '';
    if (FStore <> nil) and FStore.TryGet(TDocumentUris.FromPath(FormFile), Document) then
    begin
      if not FReadText(FormFile, FormText) then
      begin
        Continue;
      end;
      Stamp := 'd' + FormText;
    end
    else if FileAge(FormFile, Age) then
    begin
      Stamp := 't' + FloatToStr(Age, TFormatSettings.Invariant);
    end;
    if (Stamp <> '') and FForms.TryGet(FormFile, Stamp, ASnapshot) then
    begin
      Exit(True);
    end;
    if (FormText = '') and not FReadText(FormFile, FormText) then
    begin
      Continue;
    end;
    if ParseForm(FormFile, FormText, ASnapshot) then
    begin
      if Stamp <> '' then
      begin
        FForms.Put(FormFile, Stamp, ASnapshot);
      end;
      Exit(True);
    end;
  end;
end;

/// <summary>Klassenname ohne führendes T.</summary>
function TypeWord(const ATypeName: string): string;
begin
  if (Length(ATypeName) > 1) and CharInSet(ATypeName[1], ['T', 't']) then
  begin
    Result := Copy(ATypeName, 2, MaxInt);
  end
  else
  begin
    Result := ATypeName;
  end;
end;

/// <summary>Ein Typ aus AChain heißt ohne "T" genau AWord.</summary>
function ChainHas(const AChain: TArray<string>; const AWord: string): Boolean;
var
  Name: string;
begin
  for Name in AChain do
  begin
    if SameText(TypeWord(Name), AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TLspCompletion.ComponentItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  AMatching: TCompletionMatching; out AItems: TArray<TCompletionItem>): Boolean;
begin
  Result := ComponentItemsFromForm(AResolver, ATree, AText, AFileName, APosition, UncachedForms(AReadText), AMatching,
    AItems);
end;

class function TLspCompletion.ComponentItemsFromForm(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; const AForms: TCompletionFormFunc;
  AMatching: TCompletionMatching; out AItems: TArray<TCompletionItem>): Boolean;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.Matching := AMatching;
    Result := ComponentItemsFromForm(Request, AForms, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.ComponentItemsFromForm(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
  out AItems: TArray<TCompletionItem>): Boolean;
const
  // Höchstens so viele Komponenten prüfen, ob sie von hier aus als Feld sichtbar sind.
  MaxProbes = 3;
var
  Context: TCompletionContext;
  Form: TFormSnapshot;
  Component: TFormSnapshotComponent;
  Routine: TIndexSymbol;
  Resolved, TypeSymbol, Ancestor: TResolvedSymbol;
  Visible, ByType: Boolean;
  Probes, Depth: Integer;
  UnitIndex: TUnitIndex;
  Ancestors: TDictionary<string, TArray<string>>;
  Chain: TArray<string>;
  Item: TCompletionItem;
  Items: TList<TCompletionItem>;
begin
  AItems := nil;
  Result := False;
  if not Assigned(AForms) then
  begin
    Exit;
  end;
  Context := Analyze(ARequest.Tree, ARequest.Position);
  if Context.Kind <> TCompletionContextKind.Scope then
  begin
    Exit;
  end;
  // Komponenten gibt es nur in Routinen (Methoden der Formularklasse): außerhalb das Formular gar nicht
  // erst lesen (Code-Review P-06).
  UnitIndex := ARequest.UnitIndex;
  if not RoutineAt(UnitIndex, ARequest.Position, Routine) then
  begin
    Exit;
  end;
  if not AForms(ARequest.FileName, ARequest.Text, Form) then
  begin
    Exit;
  end;
  Ancestors := TDictionary<string, TArray<string>>.Create;
  Items := TList<TCompletionItem>.Create;
  try
    // Sichtbar nur in Methoden der Formularklasse: die ersten Komponenten müssen als deren Feld auflösen.
    Visible := False;
    Probes := 0;
    for Component in Form.Components do
    begin
      Resolved := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, [Component.Name], Context.Offset);
      if Resolved.Found and (Resolved.SymbolKind = TIndexSymbolKind.Field) and
        SameText(Resolved.Container, Form.RootType) then
      begin
        Visible := True;
        Break;
      end;
      Inc(Probes);
      if Probes >= MaxProbes then
      begin
        Break;
      end;
    end;
    if not Visible then
    begin
      Exit;
    end;
    for Component in Form.Components do
    begin
      ByType := MatchScore(Component.Name, Context.Prefix, ARequest.Matching) = TFuzzyMatch.NoMatch;
      // Suche über den Typ ab zwei Zeichen: eigene Klasse beginnt damit, oder ein Vorfahr heißt genau so
      // ("button" findet TButton und TBitBtn, aber nicht TCheckBox über TButtonControl).
      if ByType then
      begin
        if Length(Context.Prefix) < 2 then
        begin
          Continue;
        end;
        if not StartsText(Context.Prefix, TypeWord(Component.TypeName)) then
        begin
          if not Ancestors.TryGetValue(LowerCase(Component.TypeName), Chain) then
          begin
            Chain := nil;
            if ARequest.Resolver.ResolveTypeFrom(UnitIndex, Component.TypeName, TypeSymbol) then
            begin
              for Depth := 1 to 32 do
              begin
                if not ARequest.Resolver.AncestorOf(TypeSymbol, Ancestor) then
                begin
                  Break;
                end;
                Chain := Chain + [Ancestor.Name];
                TypeSymbol := Ancestor;
              end;
            end;
            Ancestors.Add(LowerCase(Component.TypeName), Chain);
          end;
          if not ChainHas(Chain, Context.Prefix) then
          begin
            Continue;
          end;
        end;
      end;
      Item := Default(TCompletionItem);
      Item.Name := Component.Name;
      Item.Detail := Component.TypeName;
      Item.Kind := KindField;
      Item.Container := Form.RootType;
      Item.Scope := 3;
      Item.Form := Form.RootName;
      Item.ByType := ByType;
      // Wie im Sammler (#882): Unscharfe Treffer und Treffer über den Typ bekommen das getippte Wort als
      // filterText, sonst verwirft ein Editor mit eigenem Präfixfilter (VS Code) alles ohne passenden Anfang.
      if (ARequest.Matching = TCompletionMatching.Fuzzy) and (Context.Prefix <> '') and
        not Component.Name.StartsWith(Context.Prefix, True) then
      begin
        Item.FilterText := Context.Prefix;
      end;
      // Liste statt AItems := AItems + [...] (Code-Review P-08).
      Items.Add(Item);
    end;
    AItems := Items.ToArray;
  finally
    Items.Free;
    Ancestors.Free;
  end;
  Result := Length(AItems) > 0;
end;

class function TLspCompletion.SenderItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  AMatching: TCompletionMatching; ACast: TCompletionSenderCast; out AItems: TCompletionItems): Boolean;
begin
  Result := SenderItemsFromForm(AResolver, AIndex, ATree, AText, AFileName, APosition, UncachedForms(AReadText),
    AMatching, ACast, AItems);
end;

class function TLspCompletion.SenderItemsFromForm(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const AText, AFileName: string; const APosition: TTextPosition;
  const AForms: TCompletionFormFunc; AMatching: TCompletionMatching; ACast: TCompletionSenderCast;
  out AItems: TCompletionItems): Boolean;
var
  Request: TCompletionRequest;
  Settings: TCompletionSettings;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.Index := AIndex;
    Request.Matching := AMatching;
    Settings := Request.Settings;
    Settings.SenderCast := ACast;
    Request.Settings := Settings;
    Result := SenderItemsFromForm(Request, AForms, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.SenderItemsFromForm(ARequest: TCompletionRequest; const AForms: TCompletionFormFunc;
  out AItems: TCompletionItems): Boolean;
const
  // So weit sucht Atlas nach oben nach dem Kopf der Methode bzw. nach dem Parameter darin.
  MaxHeaderDistance = 2000;
  MaxHeaderLines = 6;
var
  Context: TCompletionContext;
  Lines: TArray<string>;
  Line, HeaderLine, ParamLine, Index, LastObject: Integer;
  Match: TMatch;
  MethodName, CommonType, Cast, LB, Patched: string;
  Form: TFormSnapshot;
  Handler: TFormSnapshotHandler;
  Routine: TIndexSymbol;
  Types, Names, Chain, First: TArray<string>;
  UnitIndex: TUnitIndex;
  Shared: Boolean;
  Candidate: string;
  PatchedTree: TSyntaxTree;
  Postfix: TPostfixOptions;
  Header, SenderParam: TRegEx;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  Context := Analyze(ARequest.Tree, ARequest.Position);
  if (Context.Kind <> TCompletionContextKind.Member) or (Length(Context.Names) <> 1) or
    not SameText(Context.Names[0], 'Sender') or not Assigned(AForms) then
  begin
    Exit;
  end;
  // Muster einmal je Aufruf übersetzen (Code-Review P-11); lokal, weil die Vervollständigung nebenläufig läuft.
  SenderParam := TRegEx.Create('\b(Sender\s*:\s*)TObject\b', [roIgnoreCase]);
  // Kopf der umgebenden Methode "procedure TForm1.btnAnyClick(Sender: TObject);" oberhalb des Cursors: aus dem
  // Baum (Code-Review P-11); nur ohne passende Methode dort wie bisher Zeile für Zeile nach oben.
  // Kopie: Die Zeile mit dem Parameter wird unten umgeschrieben.
  Lines := Copy(ARequest.Lines);
  UnitIndex := ARequest.UnitIndex;
  HeaderLine := -1;
  if RoutineAt(UnitIndex, ARequest.Position, Routine) and (Routine.Container <> '') and
    (Routine.Range.StartPos.Line < ARequest.Position.Line) and (Routine.Range.StartPos.Line <= High(Lines)) then
  begin
    HeaderLine := Routine.Range.StartPos.Line;
    MethodName := Routine.Name;
  end
  else
  begin
    Header := TRegEx.Create('^\s*(class\s+)?(procedure|function)\s+[\w.]+\.(\w+)\s*[(;:]', [roIgnoreCase]);
    for Line := Min(ARequest.Position.Line - 1, High(Lines)) downto
      Max(0, ARequest.Position.Line - MaxHeaderDistance) do
    begin
      Match := Header.Match(Lines[Line]);
      if Match.Success then
      begin
        HeaderLine := Line;
        MethodName := Match.Groups[3].Value;
        Break;
      end;
    end;
  end;
  if HeaderLine < 0 then
  begin
    Exit;
  end;
  ParamLine := -1;
  for Line := HeaderLine to Min(HeaderLine + MaxHeaderLines - 1, ARequest.Position.Line - 1) do
  begin
    if SenderParam.IsMatch(Lines[Line]) then
    begin
      ParamLine := Line;
      Break;
    end;
  end;
  if ParamLine < 0 then
  begin
    Exit;
  end;
  // Komponenten, deren Ereignis im Formular auf diese Methode zeigt; je Objekt die erste Zuweisung.
  if not AForms(ARequest.FileName, ARequest.Text, Form) then
  begin
    Exit;
  end;
  Types := nil;
  Names := nil;
  LastObject := -1;
  for Handler in Form.Handlers do
  begin
    if (Handler.ObjectIndex <> LastObject) and SameText(Handler.MethodName, MethodName) and
      (Handler.TypeName <> '') then
    begin
      LastObject := Handler.ObjectIndex;
      Names := Names + [Handler.ObjectName];
      if IndexText(Handler.TypeName, Types) < 0 then
      begin
        Types := Types + [Handler.TypeName];
      end;
    end;
  end;
  if Length(Types) = 0 then
  begin
    Exit;
  end;
  // Nächster gemeinsamer Vorfahr: der erste Typ in der Kette des ersten, den alle Ketten enthalten.
  First := TypeChain(ARequest.Resolver, UnitIndex, Types[0]);
  CommonType := '';
  for Candidate in First do
  begin
    Shared := True;
    for Index := 1 to High(Types) do
    begin
      Chain := TypeChain(ARequest.Resolver, UnitIndex, Types[Index]);
      if IndexText(Candidate, Chain) < 0 then
      begin
        Shared := False;
        Break;
      end;
    end;
    if Shared then
    begin
      CommonType := Candidate;
      Break;
    end;
  end;
  if (CommonType = '') or SameText(CommonType, 'TObject') then
  begin
    Exit;
  end;
  // Mitglieder wie bei "Sender: <Typ>": Parameter im Kopf umschreiben und neu zerlegen; die Zeile des Cursors
  // bleibt gleich, also auch ARequest.Position.
  LB := ARequest.LineBreak;
  Lines[ParamLine] := SenderParam.Replace(Lines[ParamLine], '$1' + CommonType);
  Patched := string.Join(LB, Lines);
  PatchedTree := TSyntaxTreeCache.Parse(Patched);
  try
    Postfix := TPostfixOptions.Default;
    Postfix.Enabled := False;
    AItems := Collect(ARequest.Resolver, ARequest.Index, PatchedTree, ARequest.FileName, Patched, ARequest.Position,
      ARequest.Matching, Postfix);
  finally
    PatchedTree.Free;
  end;
  if ARequest.Settings.SenderCast = TCompletionSenderCast.HardCast then
  begin
    Cast := CommonType + '(' + Context.Names[0] + ')';
  end
  else
  begin
    Cast := '(' + Context.Names[0] + ' as ' + CommonType + ')';
  end;
  for Index := 0 to High(AItems.Items) do
  begin
    AItems.Items[Index].Sender := CommonType;
    AItems.Items[Index].SenderOf := string.Join(', ', Names);
    if AItems.Items[Index].HasTextEdit then
    begin
      Continue;
    end;
    // "Sender.Cap" → "(Sender as TButton).Caption"
    AItems.Items[Index].HasTextEdit := True;
    if AItems.Items[Index].InsertText <> '' then
    begin
      AItems.Items[Index].TextEdit := TRuleEdit.Create(TTextRange.Create(Context.ChainStart, ARequest.Position),
        Cast + '.' + AItems.Items[Index].InsertText);
    end
    else
    begin
      AItems.Items[Index].TextEdit := TRuleEdit.Create(TTextRange.Create(Context.ChainStart, ARequest.Position),
        Cast + '.' + AItems.Items[Index].Name);
    end;
  end;
  Result := True;
end;

class function TLspCompletion.DataNameItems(const AIndex: ISymbolIndex; const AText, AFileName: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Index := AIndex;
    Request.ReadText := AReadText;
    Result := DataNameItems(Request, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.DataNameItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  Lines: TArray<string>;
  Call: TDataNameCall;
  Sql, Source: string;
  Names: TArray<TDataName>;
  Name: TDataName;
  Found: Boolean;
  Item: TCompletionItem;
  Range: TTextRange;
begin
  AItems := Default(TCompletionItems);
  Lines := ARequest.Lines;
  if (ARequest.Position.Line < 0) or (ARequest.Position.Line > High(Lines)) or
    not TDataFieldNames.CallAt(Lines[ARequest.Position.Line], ARequest.Position.Character, Call) then
  begin
    Exit(False);
  end;
  Result := True;
  if not Assigned(ARequest.ReadText) then
  begin
    Exit;
  end;
  // Nur aus der Formulardatei: Ohne Designer-Informationen kein geratener Vorschlag.
  Names := TDataFieldNames.Lookup(ARequest.Text, ARequest.FileName, Call, ARequest.Index,
    function(const AName: string; out AContent: string): Boolean
    begin
      Result := ARequest.ReadText(AName, AContent);
    end, Sql, Found);
  Source := TDataFieldNames.ShortSql(Sql);
  Range := TTextRange.Create(ARequest.Position.Line, Call.ContentStart, ARequest.Position.Line, Call.ContentEnd);
  for Name in Names do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Name.Name;
    Item.Detail := Name.TypeName;
    if Call.Kind = TDataNameKind.Param then
    begin
      Item.Kind := KindVariable;
    end
    else
    begin
      Item.Kind := KindField;
    end;
    // Schreibweise wie in der Quelle; ersetzt den ganzen Inhalt zwischen den Anführungszeichen.
    Item.HasTextEdit := True;
    Item.TextEdit := TRuleEdit.Create(Range, StringReplace(Name.Name, '''', '''''', [rfReplaceAll]));
    Item.DataSet := Call.DisplayName;
    Item.DataSource := Source;
    AItems.Items := AItems.Items + [Item];
  end;
end;

class function TLspCompletion.GuardItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; AStyle: TCompletionFreeStyle; ANewLine: Boolean;
  out AItems: TCompletionItems): Boolean;
var
  Request: TCompletionRequest;
  Settings: TCompletionSettings;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Settings := Request.Settings;
    Settings.FreeStyle := AStyle;
    Request.Settings := Settings;
    Result := GuardItems(Request, ANewLine, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.GuardItems(ARequest: TCompletionRequest; ANewLine: Boolean;
  out AItems: TCompletionItems): Boolean;
var
  UnitIndex: TUnitIndex;
  Offer: TGuardOffer;
  Item: TCompletionItem;
  Lines: TArray<string>;
  Line: Integer;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  Line := ARequest.Position.Line;
  // Enter am Zeilenende: Anweisung in der Zeile davor, die Zeile des Cursors ist leer.
  if ANewLine then
  begin
    Lines := ARequest.Lines;
    Line := ARequest.Position.Line - 1;
    if (Line < 0) or (ARequest.Position.Line > High(Lines)) or (Trim(Lines[ARequest.Position.Line]) <> '') then
    begin
      Exit;
    end;
  end;
  UnitIndex := ARequest.UnitIndex;
  // Art des erzeugten Typs: Record oder Interface schließen aus, TComponent-Nachfahren prüfen den Owner.
  Result := TGuardFree.Check(ARequest.Tree, ARequest.Text, Line,
    function(const ATypeName: string): TGuardTypeKind
    var
      Symbol: TResolvedSymbol;
    begin
      if not ARequest.Resolver.ResolveTypeFrom(UnitIndex, ATypeName, Symbol) then
      begin
        Exit(TGuardTypeKind.Unknown);
      end;
      if Symbol.SymbolKind <> TIndexSymbolKind.ClassType then
      begin
        Exit(TGuardTypeKind.Other);
      end;
      if IndexText('TComponent', TypeChain(ARequest.Resolver, UnitIndex, ATypeName)) >= 0 then
      begin
        Result := TGuardTypeKind.Component;
      end
      else
      begin
        Result := TGuardTypeKind.Class_;
      end;
    end, Offer);
  if not Result then
  begin
    Exit;
  end;
  if ANewLine then
  begin
    Offer.BlankLine := ARequest.Position.Line;
  end;
  Item := Default(TCompletionItem);
  Item.Kind := KindSnippet;
  Item.HasTextEdit := True;
  if ARequest.Settings.FreeStyle = TCompletionFreeStyle.FreeAndNil then
  begin
    Item.Detail := 'FreeAndNil(' + Offer.Variable + ')';
  end
  else
  begin
    Item.Detail := Offer.Variable + '.Free';
  end;
  Item.Name := 'Mit try…finally absichern';
  Item.Guard := 'newLine';
  Item.TextEdit := TGuardFree.Edit(ARequest.Text, Offer, TGuardScope.NewLine, ARequest.Settings.FreeStyle);
  AItems.Items := [Item];
  if Offer.CanEnclose then
  begin
    Item.Name := 'Bis Routinenende mit try…finally absichern';
    Item.Guard := 'routineEnd';
    Item.TextEdit := TGuardFree.Edit(ARequest.Text, Offer, TGuardScope.ToRoutineEnd, ARequest.Settings.FreeStyle);
    AItems.Items := AItems.Items + [Item];
  end;
end;

/// <summary>Typen der Parameter aus "const A, B: T; var C: U; D" in Reihenfolge; untypisiert ''.</summary>
function EventParamTypes(const AParams: string): TArray<string>;
var
  Group, Names, TypeText: string;
  Count, Index: Integer;
begin
  Result := nil;
  for Group in AParams.Split([';']) do
  begin
    if Trim(Group) = '' then
    begin
      Continue;
    end;
    Names := Group;
    TypeText := '';
    if Pos(':', Group) > 0 then
    begin
      Names := Copy(Group, 1, Pos(':', Group) - 1);
      TypeText := Copy(Group, Pos(':', Group) + 1, MaxInt);
      if Pos('=', TypeText) > 0 then
      begin
        TypeText := Copy(TypeText, 1, Pos('=', TypeText) - 1);
      end;
    end;
    Count := Length(Names.Split([',']));
    for Index := 1 to Count do
    begin
      Result := Result + [Trim(TypeText)];
    end;
  end;
end;

class function TLspCompletion.EventItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.ReadText := AReadText;
    Result := EventItems(Request, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.EventItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  Match, TypeMatch: TMatch;
  Names, TypeNames: TArray<string>;
  Offset, Index, Number: Integer;
  Event, EventType, Candidate: TResolvedSymbol;
  Source, Declaration, Kind, Params, ResultType, Base, Name, Header, Body, LB, TypeName, Prefix: string;
  ParamTypes: TArray<string>;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Taken: TDictionary<string, Boolean>;
  Item: TCompletionItem;
  Method: TUnmatchedMethod;
  Edit: TRuleEdit;
  Fits: Boolean;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  // "btnSave.OnClick := btn|", "OnClick := |"; nicht "A.B := " in Ausdrücken mit "=" davor.
  Match := TRegEx.Match(ARequest.LineBefore, '(?:^|[^\w.&])((?:&?\w+\.)*)&?(\w+)\s*:=\s*(\w*)$');
  if not Match.Success then
  begin
    Exit;
  end;
  Prefix := Match.Groups[3].Value;
  Names := nil;
  for Name in Match.Groups[1].Value.Split(['.']) do
  begin
    if Name <> '' then
    begin
      Names := Names + [CleanName(Name)];
    end;
  end;
  Names := Names + [Match.Groups[2].Value];
  Offset := Analyze(ARequest.Tree, ARequest.Position).Offset;
  Event := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, Names, Offset);
  if not Event.Found or not (Event.SymbolKind in [TIndexSymbolKind.Property_, TIndexSymbolKind.Field,
    TIndexSymbolKind.Variable]) or (Event.TypeName = '') then
  begin
    Exit;
  end;
  // Methodenzeigertyp auflösen: wie im Quelltext, sonst über die Unit der Eigenschaft.
  TypeNames := Event.TypeName.Split(['.']);
  EventType := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, TypeNames, Offset);
  if not EventType.Found and (Event.UnitName <> '') then
  begin
    EventType := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName,
      Event.UnitName.Split(['.']) + TypeNames, Offset);
  end;
  if not EventType.Found or (EventType.FileName = '') then
  begin
    Exit;
  end;
  if SameText(EventType.FileName, ARequest.FileName) then
  begin
    Source := ARequest.Text;
  end
  else if not (Assigned(ARequest.ReadText) and ARequest.ReadText(EventType.FileName, Source)) then
  begin
    Exit;
  end;
  Declaration := DeclarationOf(TextLines(Source), EventType.Range);
  TypeMatch := TRegEx.Match(Declaration,
    '=\s*(reference\s+to\s+)?(procedure|function)\s*(?:\((.*)\))?\s*(?::\s*([\w.<>, ]+?))?\s*(of\s+object)?\s*;',
    [roIgnoreCase]);
  if not TypeMatch.Success or ((TypeMatch.Groups[1].Length = 0) and (TypeMatch.Groups[5].Length = 0)) then
  begin
    Exit;
  end;
  Kind := LowerCase(TypeMatch.Groups[2].Value);
  Params := Trim(TypeMatch.Groups[3].Value);
  ResultType := Trim(TypeMatch.Groups[4].Value);
  ParamTypes := EventParamTypes(Params);
  // Umgebende Klasse: Methodenrumpf, in dem der Cursor steht.
  UnitIndex := ARequest.UnitIndex;
  TypeName := '';
  for Symbol in UnitIndex.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and (Symbol.Container <> '') and
      (Symbol.Range.StartPos.Line < ARequest.Position.Line) and
      (Symbol.Range.EndPos.Line >= ARequest.Position.Line) then
    begin
      TypeName := Symbol.Container;
    end;
  end;
  if TypeName = '' then
  begin
    Exit;
  end;
  Result := True;
  LB := ARequest.LineBreak;
  Taken := TDictionary<string, Boolean>.Create;
  try
    for Symbol in UnitIndex.Symbols do
    begin
      if SameText(Symbol.Container, TypeName) then
      begin
        Taken.AddOrSetValue(LowerCase(Symbol.Name), True);
      end;
    end;
    // Passende Methoden der Klasse samt geerbter.
    for Candidate in ARequest.Resolver.Candidates.MemberCandidates(ARequest.Tree, ARequest.FileName, ['Self'],
      Offset) do
    begin
      Taken.AddOrSetValue(LowerCase(Candidate.Name), True);
      if (Candidate.SymbolKind <> TIndexSymbolKind.Method) or (Length(Candidate.ParamTypes) <> Length(ParamTypes)) or
        ((Kind = 'function') <> (Candidate.TypeName <> '')) or
        ((Kind = 'function') and (PlainType(Candidate.TypeName) <> PlainType(ResultType))) then
      begin
        Continue;
      end;
      Fits := True;
      for Index := 0 to High(ParamTypes) do
      begin
        if PlainType(Candidate.ParamTypes[Index]) <> PlainType(ParamTypes[Index]) then
        begin
          Fits := False;
        end;
      end;
      if not Fits then
      begin
        Continue;
      end;
      Item := Default(TCompletionItem);
      Item.Name := Candidate.Name;
      Item.Kind := KindMethod;
      Item.Detail := Candidate.Container;
      Item.Container := Candidate.Container;
      Item.Depth := Candidate.Depth;
      Item.SourceFile := Candidate.FileName;
      Item.SourcePosition := Candidate.SelectionRange.StartPos;
      Item.Expected := EventType.Name;
      Item.Fits := True;
      AItems.Items := AItems.Items + [Item];
    end;
    // Neue Methode: Objekt + Ereignis ohne "On" (btnSave.OnClick → btnSaveClick), eindeutig gemacht.
    if (Length(Names) > 1) and not SameText(Names[High(Names) - 1], 'Self') then
    begin
      Base := Names[High(Names) - 1];
    end
    else if StartsText('T', TypeName) and (Pos('.', TypeName) = 0) then
    begin
      Base := Copy(TypeName, 2, MaxInt);
    end
    else
    begin
      Base := TypeName.Substring(TypeName.LastIndexOf('.') + 1);
    end;
    if StartsText('On', Match.Groups[2].Value) then
    begin
      Base := Base + Copy(Match.Groups[2].Value, 3, MaxInt);
    end
    else
    begin
      Base := Base + Match.Groups[2].Value;
    end;
    Name := Base;
    Number := 1;
    while Taken.ContainsKey(LowerCase(Name)) do
    begin
      Inc(Number);
      Name := Base + IntToStr(Number);
    end;
  finally
    Taken.Free;
  end;
  Header := Kind + ' ' + TypeName + '.' + Name;
  if Params <> '' then
  begin
    Header := Header + '(' + Params + ')';
  end;
  if Kind = 'function' then
  begin
    Header := Header + ': ' + ResultType;
  end;
  Item := Default(TCompletionItem);
  Item.Name := 'Neue Methode ' + Name + ' …';
  Item.Kind := KindMethod;
  Item.Detail := Copy(Header, Length(Kind) + 2, MaxInt);
  Item.InsertText := Name;
  // Immer sichtbar, auch wenn das Getippte nicht zum Namen passt.
  Item.FilterText := Prefix;
  Item.Action := 'create';
  Method := Default(TUnmatchedMethod);
  Method.TypeName := TypeName;
  Method.Header := Header;
  Method.Symbol.Name := Name;
  Method.Declared := False;
  if TClassCompletion.AddDeclaration(ARequest.Tree, ARequest.Text, Method, Edit) then
  begin
    Item.AdditionalEdits := Item.AdditionalEdits + [Edit];
  end;
  Body := Header + ';' + LB + 'begin' + LB + LB + 'end;';
  if TClassCompletion.BodyEdit(ARequest.Tree, ARequest.Text, TypeName, Body, Edit) then
  begin
    Item.AdditionalEdits := Item.AdditionalEdits + [Edit];
  end;
  AItems.Items := AItems.Items + [Item];
end;

type
  /// <summary>Aufzählungstyp mit seinen Werten (#448).</summary>
  TEnumType = record
    Name: string;
    /// <summary>Mengentyp, über den er gefunden wurde ("TAnchors"); '' ohne.</summary>
    SetName: string;
    Values: TArray<string>;
    /// <summary>Namenspositionen der Werte in FileName; Line -1, wenn unbekannt.</summary>
    Positions: TArray<TTextPosition>;
    FileName: string;
    /// <summary>{$SCOPEDENUMS ON} an der Deklaration: Werte nur mit Typpräfix.</summary>
    Scoped: Boolean;
  end;

/// <summary>Text von ARange, über höchstens 400 Zeilen (lange Aufzählungen stehen über viele Zeilen).</summary>
function RangeText(const AText: string; const ARange: TTextRange): string;
var
  Lines: TArray<string>;
  Line: Integer;
begin
  Result := '';
  Lines := TextLines(AText);
  for Line := Max(0, ARange.StartPos.Line) to Min(Min(ARange.EndPos.Line, ARange.StartPos.Line + 400), High(Lines)) do
  begin
    if Line = ARange.StartPos.Line then
    begin
      Result := Copy(Lines[Line], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + #10 + Lines[Line];
    end;
  end;
end;

/// <summary>Offset (0-basiert) von APosition in AText.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Index, Line: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
    begin
      Inc(Line);
    end;
    Inc(Index);
  end;
  Result := Index - 1 + APosition.Character;
end;

/// <summary>Quelltext der Datei von ASymbol: das offene Dokument oder über AReadText.</summary>
function SourceOf(const ASymbol: TResolvedSymbol; const AText, AFileName: string;
  const AReadText: TCompletionReadText; out ASource: string): Boolean;
begin
  ASource := '';
  if SameText(ASymbol.FileName, AFileName) then
  begin
    ASource := AText;
    Exit(True);
  end;
  Result := (ASymbol.FileName <> '') and Assigned(AReadText) and AReadText(ASymbol.FileName, ASource);
end;

/// <summary>Index-Eintrag der Unit von ASymbol; für das offene Dokument aus dessen Baum.</summary>
function OwnerUnit(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const ASymbol: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if SameText(ASymbol.FileName, AFileName) then
  begin
    AUnit := AResolver.ExtractedUnit(ATree, AFileName);
    Exit(True);
  end;
  Result := (AIndex <> nil) and AIndex.FindFile(ASymbol.FileName, AUnit);
end;

/// <summary>Typ ATypeName, wie er an AOffset stünde; sonst ein gleichnamiger Typ aus dem Index.</summary>
function TypeAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer; const ATypeName: string): TResolvedSymbol;
var
  Location: TSymbolLocation;
  Owner: TUnitIndex;
begin
  Result := AResolver.ResolveChain(ATree, AFileName, ATypeName.Split(['.']), AOffset);
  // Eingebaute Typen (Integer, string) stehen nicht im Index: nicht danach suchen (Code-Review P-12).
  if (Result.Found and Result.IsType) or (AIndex = nil) or (Pos('.', ATypeName) > 0) or
    TResolverText.IsBuiltinTypeName(ATypeName) then
  begin
    Exit;
  end;
  // Typ einer Eigenschaft aus einer Unit, die hier nicht eingebunden ist (TAnchors aus Vcl.Controls).
  for Location in AIndex.FindSymbols(ATypeName) do
  begin
    if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) and AIndex.FindUnit(Location.UnitName, Owner) and
      AResolver.ResolveTypeFrom(Owner, ATypeName, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Aufzählung zu AType, Aliase verfolgt; mit AAllowSet auch der Elementtyp einer Menge.</summary>
function EnumOf(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; AType: TResolvedSymbol; const AReadText: TCompletionReadText; AAllowSet: Boolean;
  out AEnum: TEnumType): Boolean;
var
  Source, Declaration, Element, Container: string;
  Owner: TUnitIndex;
  Step, Index: Integer;
  Symbol: TIndexSymbol;
  Found: Boolean;
begin
  AEnum := Default(TEnumType);
  Result := False;
  Found := False;
  Source := '';
  Declaration := '';
  for Step := 1 to 4 do
  begin
    // Erst die Art prüfen: Klassen und eingebaute Typen brauchen den Quelltext nicht.
    if not AType.Found or not AType.IsType or not (AType.SymbolKind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) or not SourceOf(AType, AText, AFileName, AReadText, Source) then
    begin
      Exit;
    end;
    Declaration := RangeText(Source, AType.Range);
    if AType.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Found := True;
      Break;
    end;
    // Alias oder Menge: von der Unit der Deklaration aus weiter auflösen.
    if not OwnerUnit(AResolver, AIndex, ATree, AFileName, AType, Owner) then
    begin
      Exit;
    end;
    Element := TCompletionEnums.SetElement(Declaration);
    if Element <> '' then
    begin
      if not AAllowSet or (AEnum.SetName <> '') then
      begin
        Exit;
      end;
      AEnum.SetName := AType.Name;
      if not AResolver.ResolveTypeFrom(Owner, Element, AType) then
      begin
        Exit;
      end;
    end
    else if (AType.TypeName = '') or not AResolver.ResolveTypeFrom(Owner, AType.TypeName, AType) then
    begin
      Exit;
    end;
  end;
  if not Found then
  begin
    Exit;
  end;
  AEnum.Values := TCompletionEnums.EnumValues(Declaration);
  if AEnum.Values = nil then
  begin
    Exit;
  end;
  AEnum.Name := AType.Name;
  AEnum.FileName := AType.FileName;
  AEnum.Scoped := TCompletionEnums.ScopedAt(Source, OffsetOf(Source, AType.Range.StartPos));
  // Namenspositionen für completionItem/resolve.
  SetLength(AEnum.Positions, Length(AEnum.Values));
  for Index := 0 to High(AEnum.Positions) do
  begin
    AEnum.Positions[Index] := TTextPosition.Create(-1, 0);
  end;
  Container := AType.QualifiedName;
  if OwnerUnit(AResolver, AIndex, ATree, AFileName, AType, Owner) then
  begin
    for Symbol in Owner.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, Container) then
      begin
        for Index := 0 to High(AEnum.Values) do
        begin
          if SameText(AEnum.Values[Index], Symbol.Name) then
          begin
            AEnum.Positions[Index] := Symbol.SelectionRange.StartPos;
          end;
        end;
      end;
    end;
  end;
  Result := True;
end;

/// <summary>Eintrag für den Wert AIndex von AEnum.</summary>
function EnumItem(const AEnum: TEnumType; AIndex: Integer): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := AEnum.Values[AIndex];
  Result.Kind := KindEnumMember;
  Result.Detail := AEnum.Name;
  Result.Container := AEnum.Name;
  Result.Ordinal := AIndex + 1;
  Result.Fits := True;
  if AEnum.Scoped then
  begin
    Result.InsertText := AEnum.Name + '.' + AEnum.Values[AIndex];
  end;
  if AEnum.Positions[AIndex].Line >= 0 then
  begin
    Result.SourceFile := AEnum.FileName;
    Result.SourcePosition := AEnum.Positions[AIndex];
  end;
end;

/// <summary>„Alle Werte einfügen“ bzw. „Fehlende Werte ergänzen (n)“ am Anfang eines case-Zweigs (#449).</summary>
function CaseItem(const AEnum: TEnumType; const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; out AItem: TCompletionItem): Boolean;
var
  Slot: TCaseBranchSlot;
  Missing: TArray<string>;
  Prefix, LineBreak, EndText: string;
begin
  AItem := Default(TCompletionItem);
  Result := False;
  if not TCaseCompletion.BranchSlot(AText, ATokens, APosition, Slot) or
    not TCaseCompletion.Missing(AEnum.Values, Slot.Labels, Missing) or (Missing = nil) then
  begin
    Exit;
  end;
  if Pos(#13#10, AText) > 0 then
  begin
    LineBreak := #13#10;
  end
  else
  begin
    LineBreak := #10;
  end;
  Prefix := '';
  if AEnum.Scoped then
  begin
    Prefix := AEnum.Name + '.';
  end;
  if Slot.Labels = nil then
  begin
    AItem.Name := 'Alle Werte einfügen';
    AItem.Count := Length(Missing);
  end
  else
  begin
    AItem.Name := Format('Fehlende Werte ergänzen (%d)', [Length(Missing)]);
  end;
  AItem.Kind := KindSnippet;
  AItem.Detail := AEnum.Name;
  AItem.Fits := True;
  AItem.Pinned := True;
  // Erzeugt Code: Atlas wertet die Zusatzänderung ("end;") nicht als uses-Ergänzung.
  AItem.Action := 'case';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(Slot.EditRange, TCaseCompletion.BranchesText(Slot, Missing, Prefix, LineBreak));
  EndText := TCaseCompletion.EndText(Slot, LineBreak);
  if EndText <> '' then
  begin
    AItem.AdditionalEdits := [TRuleEdit.Create(TTextRange.Create(Slot.EndInsert, Slot.EndInsert), EndText)];
  end;
  Result := True;
end;

/// <summary>Typ eines aufgelösten Ausdrucksteils: Konstruktor → Klasse, Typumwandlung → Typ, sonst sein Typ.</summary>
function TypeOfResolved(const ASymbol: TResolvedSymbol): string;
begin
  Result := '';
  if not ASymbol.Found or (ASymbol.Kind = TResolvedKind.UnitName) then
  begin
    Exit;
  end;
  if ASymbol.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    Result := ASymbol.Container;
  end
  else if ASymbol.IsType then
  begin
    Result := ASymbol.Name;
  end
  else if ASymbol.TypeName <> '' then
  begin
    Result := ASymbol.TypeName;
  end
  else if ASymbol.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := ASymbol.Container;
  end;
end;

/// <summary>uses-Eintrag für ATypeName (#180), wenn der Typ an AOffset nicht sichtbar ist und der Index ihn
/// in einer anderen Unit kennt; leer sonst.</summary>
function TypeUnitEdits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, ATypeName, ALineBreak: string; AOffset: Integer): TArray<TRuleEdit>;
var
  Location: TSymbolLocation;
  Edit: TRuleEdit;
begin
  Result := nil;
  // Eingebaute Typen brauchen nie einen uses-Eintrag (Code-Review P-12).
  if (AIndex = nil) or (ATypeName = '') or (Pos('<', ATypeName) > 0) or (Pos('.', ATypeName) > 0) or
    (Pos('{', ATypeName) > 0) or TResolverText.IsBuiltinTypeName(ATypeName) or
    AResolver.ResolveChain(ATree, AFileName, [ATypeName], AOffset).Found then
  begin
    Exit;
  end;
  for Location in AIndex.FindSymbols(ATypeName) do
  begin
    if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.ClassType,
      TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
      TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) and not SameText(Location.UnitName, 'System') and
      not SameText(Location.UnitName, TUsesClauses.OwnName(ATree.Tokens)) and
      not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATree.Tokens), Location.UnitName, AResolver.Namespaces) and
      TUsesClauses.AddUnit(ATree.Tokens, AOffset, Location.UnitName, ALineBreak, Edit) then
      begin Result := [Edit]; Exit; end;
  end;
end;

class function TLspCompletion.DeclareItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const APosition: TTextPosition; AInlineVar: Boolean;
  const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.Index := AIndex;
    Result := DeclareItems(Request, AInlineVar, AKnown, AItems);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.DeclareItems(ARequest: TCompletionRequest; AInlineVar: Boolean;
  const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean;
var
  Slot: TUnknownSlot;
  Known: TCompletionItem;
  TypeName, DeclType, Field, LineText: string;
  TermFirst, TermLast, NameToken, Line, Index: Integer;
  Slash: TSlashContext;
  Source: TCommandSource;
  Routine, Section, Node: TSyntaxNode;
  ClassSymbol, Symbol: TIndexSymbol;
  Fields: TArray<string>;
  Item, Base: TCompletionItem;
  Edit: TRuleEdit;
  Lines: TArray<string>;
begin
  AItems := nil;
  Result := False;
  if (ARequest.Tree = nil) or not TDeclareUnknown.Slot(ARequest.Tree.Tokens, ARequest.Position, Slot) then
  begin
    Exit;
  end;
  // Bekannt: ein Eintrag passt genau oder die Namensauflösung findet ihn.
  for Known in AKnown do
  begin
    if SameText(Known.Name, Slot.Name) then
    begin
      Exit;
    end;
  end;
  if ARequest.Resolver.Resolve(ARequest.Tree, ARequest.FileName, Slot.NameRange.StartPos).Found then
  begin
    Exit;
  end;
  // Typ: rechte Seite der Zuweisung, sonst der erwartete Typ (Argument, Wert einer Zuweisung).
  TypeName := '';
  if Slot.AssignTarget then
  begin
    TypeName := TDeclareUnknown.Shape(ARequest.Tree.Tokens, Slot.ValueFirst, Slot.ValueLast, TermFirst, TermLast);
    if (TypeName = '') and (TermFirst >= 0) and (TermFirst = TermLast) then
    begin
      TypeName := TDeclareUnknown.LiteralType(ARequest.Tree.Tokens[TermFirst]);
    end;
    if (TypeName = '') and (TermFirst >= 0) then
    begin
      NameToken := TDeclareUnknown.TermName(ARequest.Tree.Tokens, TermFirst, TermLast);
      if NameToken >= 0 then
      begin
        TypeName := TypeOfResolved(ARequest.Resolver.Resolve(ARequest.Tree, ARequest.FileName,
          ARequest.Tree.Tokens[NameToken].StartPos));
      end;
    end;
  end
  else
  begin
    TypeName := ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ARequest.Position);
  end;
  DeclType := TypeName;
  if DeclType = '' then
  begin
    DeclType := TDeclareUnknown.TypePlaceholder;
  end;
  Lines := ARequest.Lines;
  LineText := '';
  if ARequest.Position.Line <= High(Lines) then
  begin
    LineText := Lines[ARequest.Position.Line];
  end;
  Slash := Default(TSlashContext);
  Slash.Text := ARequest.Text;
  Slash.Line := ARequest.Position.Line;
  Slash.LineText := LineText;
  Source := TCommandSource.Create(Slash);
  try
    // Nur im Rumpf einer Routine: dort sind Variablen, Felder und Konstanten Deklarationen wert.
    Routine := Source.RoutineAt;
    if Routine = nil then
    begin
      Exit;
    end;
    Base := Default(TCompletionItem);
    Base.Action := 'declare';
    Base.Unknown := Slot.Name;
    Base.HasTextEdit := True;
    // Lokale Variable im var-Abschnitt; der Cursor bleibt im Namen.
    Item := Base;
    Item.Name := 'Lokale Variable anlegen';
    Item.Kind := KindVariable;
    Item.Detail := Format('%s: %s', [Slot.Name, DeclType]);
    Item.TextEdit := TRuleEdit.Create(Slot.NameRange, TDeclareUnknown.WithCaret(Slot.Name, Slot.CursorOffset));
    Item.AdditionalEdits := [AddLocal(Source, Routine, TSyntaxKind.VarSection, 'var',
      Format('%s: %s;', [Slot.Name, DeclType]))] + TypeUnitEdits(ARequest.Resolver, ARequest.Index, ARequest.Tree,
      ARequest.FileName, TypeName, Source.LineBreak, Routine.StartOffset);
    AItems := AItems + [Item];
    // Inline-Variable an der Stelle (ab Delphi 10.3): Den Typ leitet der Compiler ab.
    if AInlineVar and Slot.InlineAllowed then
    begin
      Item := Base;
      Item.Name := 'Inline-Variable anlegen';
      Item.Kind := KindVariable;
      Item.Detail := Format('var %s := …', [Slot.Name]);
      Item.TextEdit := TRuleEdit.Create(Slot.NameRange, TDeclareUnknown.WithCaret('var ' + Slot.Name,
        Slot.CursorOffset + 4));
      AItems := AItems + [Item];
    end;
    // Feld im private-Abschnitt der Klasse, wenn die Routine eine ihrer Methoden ist.
    if (Pos('.', Routine.Name) > 0) and Source.ClassAt(ClassSymbol) then
    begin
      Fields := nil;
      for Symbol in Source.UnitIndex.Symbols do
      begin
        if (Symbol.Kind = TIndexSymbolKind.Field) and (SameText(Symbol.Container, ClassSymbol.QualifiedName) or
          SameText(Symbol.Container, ClassSymbol.Name)) then
        begin
          Fields := Fields + [Symbol.Name];
        end;
      end;
      Field := TDeclareUnknown.FieldName(Slot.Name, TDeclareUnknown.UsesFieldPrefix(Fields));
      if not MatchText(Field, Fields) then
      begin
        Item := Base;
        Item.Name := Format('Feld %s anlegen', [Field]);
        Item.Kind := KindField;
        Item.Detail := Format('%s: %s', [Field, DeclType]);
        // Die Verwendung heißt danach wie das Feld; der Cursor bleibt an derselben Stelle im Namen.
        Item.TextEdit := TRuleEdit.Create(Slot.NameRange, TDeclareUnknown.WithCaret(Field,
          Slot.CursorOffset + Length(Field) - Length(Slot.Name)));
        Line := Source.PrivateLine(ClassSymbol);
        if Line >= 0 then
        begin
          Edit := Source.AfterLine(Line, Source.Indent(Line) + '  ' + Format('%s: %s;', [Field, DeclType]));
        end
        else
        begin
          Edit := Source.BeforeLine(ClassSymbol.Range.EndPos.Line, Source.Indent(ClassSymbol.Range.EndPos.Line) +
            'private' + Source.LineBreak + Source.Indent(ClassSymbol.Range.EndPos.Line) + '  ' +
            Format('%s: %s;', [Field, DeclType]));
        end;
        Item.AdditionalEdits := [Edit] + TypeUnitEdits(ARequest.Resolver, ARequest.Index, ARequest.Tree,
          ARequest.FileName, TypeName, Source.LineBreak, Source.Offset(ClassSymbol.Range.StartPos.Line));
        AItems := AItems + [Item];
      end;
    end;
    // Konstante in der implementation, wenn der Name als Wert dient; der Wert ist ein Platzhalter.
    if not Slot.AssignTarget and (Source.ImplementationStart >= 0) then
    begin
      Item := Base;
      Item.Name := 'Konstante anlegen';
      Item.Kind := KindConstant;
      Item.Detail := Format('%s = %s;', [Slot.Name, TDeclareUnknown.DefaultValue(TypeName)]);
      Item.TextEdit := TRuleEdit.Create(Slot.NameRange, TDeclareUnknown.WithCaret(Slot.Name, Slot.CursorOffset));
      Section := Source.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
      Node := nil;
      if Section <> nil then
      begin
        for Index := 0 to Section.ChildCount - 1 do
        begin
          if (Section[Index].Kind = TSyntaxKind.ConstSection) and (Node = nil) then
          begin
            Node := Section[Index];
          end;
        end;
      end;
      if Node <> nil then
      begin
        Edit := Source.AfterLine(Node.EndPos.Line, '  ' + Item.Detail);
      end
      else
      begin
        Edit := Source.AfterLine(Source.ImplementationStart, Source.LineBreak + 'const' + Source.LineBreak + '  ' +
          Item.Detail);
      end;
      Item.AdditionalEdits := [Edit];
      AItems := AItems + [Item];
    end;
  finally
    Source.Free;
  end;
  Result := AItems <> nil;
end;

class function TLspCompletion.EnumItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  AMatching: TCompletionMatching; out AItems: TArray<TCompletionItem>; out ASetMode: Boolean): Boolean;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create(AText, AFileName, APosition);
  try
    Request.Tree := ATree;
    Request.Resolver := AResolver;
    Request.Index := AIndex;
    Request.ReadText := AReadText;
    Request.Matching := AMatching;
    Result := EnumItems(Request, AItems, ASetMode);
  finally
    Request.Free;
  end;
end;

class function TLspCompletion.EnumItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
  out ASetMode: Boolean): Boolean;
var
  Slot: TEnumSetSlot;
  Context: TCompletionContext;
  Expected: string;
  Target, TypeInfo: TResolvedSymbol;
  Enum: TEnumType;
  Checked: TArray<Boolean>;
  Index: Integer;
  Item: TCompletionItem;
begin
  AItems := nil;
  ASetMode := False;
  Result := False;
  if ARequest.Tree = nil then
  begin
    Exit;
  end;
  // Mengenkonstruktor: "X in [" nimmt den Typ von X, sonst gilt der erwartete Typ an der Klammer.
  if TCompletionEnums.SetSlot(ARequest.Tree.Tokens, ARequest.Position, Slot) then
  begin
    if Slot.ElementOf <> nil then
    begin
      Target := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, Slot.ElementOf, Slot.Offset);
      if not Target.Found or Target.IsType or (Target.TypeName = '') then
      begin
        Exit;
      end;
      TypeInfo := TypeAt(ARequest.Resolver, ARequest.Index, ARequest.Tree, ARequest.FileName, Slot.Offset,
        Target.TypeName);
    end
    else
    begin
      Expected := ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, Slot.Bracket);
      if Expected = '' then
      begin
        Exit;
      end;
      TypeInfo := TypeAt(ARequest.Resolver, ARequest.Index, ARequest.Tree, ARequest.FileName, Slot.Offset, Expected);
    end;
    if not EnumOf(ARequest.Resolver, ARequest.Index, ARequest.Tree, ARequest.Text, ARequest.FileName, TypeInfo,
      ARequest.ReadText, Slot.ElementOf = nil, Enum) or
      not TCompletionEnums.Checked(Enum.Values, Slot.Present, Checked) then
    begin
      Exit;
    end;
    for Index := 0 to High(Enum.Values) do
    begin
      Item := EnumItem(Enum, Index);
      if Enum.SetName <> '' then
      begin
        Item.Expected := Enum.SetName;
      end
      else
      begin
        Item.Expected := 'set of ' + Enum.Name;
      end;
      Item.SetOf := Enum.Name;
      Item.SetChecked := Checked[Index];
      Item.SetRange := Slot.EditRange;
      AItems := AItems + [Item];
    end;
    ASetMode := True;
    Exit(True);
  end;
  // Werte: nur ohne Punkt davor ("TAlign." zeigt die Mitglieder selbst).
  Context := Analyze(ARequest.Tree, ARequest.Position);
  if Context.Kind <> TCompletionContextKind.Scope then
  begin
    Exit;
  end;
  Expected := ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ARequest.Position);
  if Expected = '' then
  begin
    Exit;
  end;
  TypeInfo := TypeAt(ARequest.Resolver, ARequest.Index, ARequest.Tree, ARequest.FileName, Context.Offset, Expected);
  if not EnumOf(ARequest.Resolver, ARequest.Index, ARequest.Tree, ARequest.Text, ARequest.FileName, TypeInfo,
    ARequest.ReadText, False, Enum) then
  begin
    Exit;
  end;
  // Am Anfang eines case-Zweigs (#449): fehlende Zweige auf einmal, als erster Eintrag.
  if CaseItem(Enum, ARequest.Text, ARequest.Tree.Tokens, ARequest.Position, Item) then
  begin
    Item.Expected := Expected;
    AItems := AItems + [Item];
  end;
  for Index := 0 to High(Enum.Values) do
  begin
    if MatchScore(Enum.Values[Index], Context.Prefix, ARequest.Matching) <> TFuzzyMatch.NoMatch then
    begin
      Item := EnumItem(Enum, Index);
      Item.Expected := Expected;
      AItems := AItems + [Item];
    end;
  end;
  Result := True;
end;

class function TLspCompletion.CaseValues(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  out AValues: TArray<string>; out APrefix: string): Boolean;
var
  Expected: string;
  TypeInfo: TResolvedSymbol;
  Enum: TEnumType;
begin
  AValues := nil;
  APrefix := '';
  Result := False;
  if ATree = nil then
  begin
    Exit;
  end;
  // Am Anfang eines Zweigs ist der erwartete Typ der des Selektors (#448).
  Expected := ExpectedType(AResolver, ATree, AFileName, APosition);
  if Expected = '' then
  begin
    Exit;
  end;
  TypeInfo := TypeAt(AResolver, AIndex, ATree, AFileName, OffsetOf(AText, APosition), Expected);
  if not EnumOf(AResolver, AIndex, ATree, AText, AFileName, TypeInfo, AReadText, False, Enum) then
  begin
    Exit;
  end;
  AValues := Enum.Values;
  if Enum.Scoped then
  begin
    APrefix := Enum.Name + '.';
  end;
  Result := True;
end;

class function TLspCompletion.EnumValuesAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  out AValues: TArray<string>): Boolean;
var
  Member, TypeInfo: TResolvedSymbol;
  Owner: TUnitIndex;
  Enum: TEnumType;
begin
  AValues := nil;
  Result := False;
  if ATree = nil then
  begin
    Exit;
  end;
  Member := AResolver.Resolve(ATree, AFileName, APosition);
  if not Member.Found or (Member.SymbolKind <> TIndexSymbolKind.EnumMember) or (Member.Container = '') then
  begin
    Exit;
  end;
  // Der Typ, wie er an der Stelle sichtbar ist; sonst von der Unit des Werts aus.
  TypeInfo := TypeAt(AResolver, AIndex, ATree, AFileName, OffsetOf(AText, APosition), Member.Container);
  if not (TypeInfo.Found and TypeInfo.IsType) and OwnerUnit(AResolver, AIndex, ATree, AFileName, Member, Owner) then
  begin
    AResolver.ResolveTypeFrom(Owner, Member.Container, TypeInfo);
  end;
  if not EnumOf(AResolver, AIndex, ATree, AText, AFileName, TypeInfo, AReadText, False, Enum) then
  begin
    Exit;
  end;
  AValues := Enum.Values;
  Result := True;
end;

/// <summary>Steht vor APosition (Anfang einer Kette) der Anfang einer Anweisung? Davor ";", ein Schlüsselwort,
/// nach dem eine Anweisung beginnt, eine case-Marke oder nichts.</summary>
function AtStatementStart(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean;
var
  Index: Integer;
begin
  Index := -1;
  while (Index < High(ATokens)) and (ComparePositions(ATokens[Index + 1].EndPos, APosition) <= 0) do
  begin
    Inc(Index);
  end;
  while (Index >= 0) and (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Index);
  end;
  Result := (Index < 0) or ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(':') or
    ATokens[Index].IsKeyword('begin') or ATokens[Index].IsKeyword('then') or ATokens[Index].IsKeyword('else') or
    ATokens[Index].IsKeyword('do') or ATokens[Index].IsKeyword('try') or ATokens[Index].IsKeyword('finally') or
    ATokens[Index].IsKeyword('except') or ATokens[Index].IsKeyword('repeat') or
    ATokens[Index].IsKeyword('otherwise');
end;

/// <summary>Vorgabe für ein Feld vom Typ ATypeName (#491): eingebaute Typen aus dem Text, sonst über die
/// Namensauflösung (Aufzählung → erster Wert, Klasse und Interface → nil), Aliase verfolgt; sonst Default(T).
/// </summary>
function AssignValue(ARequest: TCompletionRequest; AOffset: Integer; const ATypeName: string): string;
var
  Kind: TAssignValueKind;
  TypeInfo: TResolvedSymbol;
  Enum: TEnumType;
  Current, First, Source, Declaration: string;
  Step: Integer;
begin
  Current := ATypeName;
  for Step := 1 to 4 do
  begin
    if TAssignFields.KindOfText(Current, Kind) then
    begin
      Exit(TAssignFields.DefaultValue(Kind, ATypeName, ''));
    end;
    // Typargumente gehören nicht zum Namen: TList<Integer> ist eine Klasse.
    if Pos('<', Current) > 0 then
    begin
      Current := Trim(Copy(Current, 1, Pos('<', Current) - 1));
    end;
    TypeInfo := TypeAt(ARequest.Resolver, ARequest.Index, ARequest.Tree, ARequest.FileName, AOffset, Current);
    if not TypeInfo.Found or not TypeInfo.IsType then
    begin
      Break;
    end;
    case TypeInfo.SymbolKind of
      TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
        Exit('nil');
      TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias:
        if EnumOf(ARequest.Resolver, ARequest.Index, ARequest.Tree, ARequest.Text, ARequest.FileName, TypeInfo,
          ARequest.ReadText, False, Enum) then
        begin
          First := Enum.Values[0];
          if Enum.Scoped then
          begin
            First := Enum.Name + '.' + First;
          end;
          Exit(TAssignFields.DefaultValue(TAssignValueKind.Enum, ATypeName, First));
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    if TypeInfo.SymbolKind <> TIndexSymbolKind.TypeAlias then
    begin
      Break;
    end;
    // "TKinds = set of TKind": die rechte Seite steht nur im Quelltext.
    if SourceOf(TypeInfo, ARequest.Text, ARequest.FileName, ARequest.ReadText, Source) then
    begin
      Declaration := RangeText(Source, TypeInfo.Range);
      if (Pos('=', Declaration) > 0) and TAssignFields.KindOfText(Trim(StringReplace(Copy(Declaration,
        Pos('=', Declaration) + 1, MaxInt), ';', '', [])), Kind) then
      begin
        Exit(TAssignFields.DefaultValue(Kind, ATypeName, ''));
      end;
    end;
    if TypeInfo.TypeName = '' then
    begin
      Break;
    end;
    Current := TypeInfo.TypeName;
    if TypeInfo.TypeArgs <> '' then
    begin
      Current := Current + '<' + TypeInfo.TypeArgs + '>';
    end;
  end;
  Result := TAssignFields.DefaultValue(TAssignValueKind.Other, ATypeName, '');
end;

class function TLspCompletion.AssignAllItem(ARequest: TCompletionRequest; ASnippets: Boolean;
  out AItem: TCompletionItem): Boolean;
var
  Context: TCompletionContext;
  mChain: TResolvedChainType;
  Swap: TResolvedSymbol;
  Candidates: TArray<TResolvedSymbol>;
  LineText, Expr, Indent, LineBreak, TypeText: string;
  Members: TArray<TAssignMember>;
  Member: TAssignMember;
  Fields: TArray<TAssignField>;
  Field: TAssignField;
  Assignment: TCompletionAssignment;
  Values: TDictionary<string, string>;
  Index, Other: Integer;

  function Before(const A, B: TResolvedSymbol): Boolean;
  begin
    // Vorfahren zuerst, darin nach der Stelle der Deklaration.
    if A.Depth <> B.Depth then
    begin
      Exit(A.Depth > B.Depth);
    end;
    if not SameText(A.FileName, B.FileName) then
    begin
      Exit(CompareText(A.FileName, B.FileName) < 0);
    end;
    Result := ComparePositions(A.Range.StartPos, B.Range.StartPos) < 0;
  end;

begin
  AItem := Default(TCompletionItem);
  Result := False;
  if not ARequest.Settings.AssignAllFields or (ARequest.Tree = nil) or (ARequest.Text = '') then
  begin
    Exit;
  end;
  Context := Analyze(ARequest.Tree, ARequest.Position);
  if (Context.Kind <> TCompletionContextKind.Member) or (Context.Prefix <> '') or
    (Context.ChainStart.Line <> ARequest.Position.Line) or (Context.DotPos.Line <> ARequest.Position.Line) then
  begin
    Exit;
  end;
  // Am Anfang einer Anweisung, allein in der Zeile.
  LineText := ARequest.LineText(ARequest.Position.Line);
  if (Trim(Copy(LineText, 1, Context.ChainStart.Character)) <> '') or
    (Trim(Copy(LineText, ARequest.Position.Character + 1, MaxInt)) <> '') or
    not AtStatementStart(ARequest.Tree.Tokens, Context.ChainStart) then
  begin
    Exit;
  end;
  // Ein Wert vom Typ Record oder Klasse; TFoo. allein ist ein Typ, TFoo(X). eine Typumwandlung.
  if not ARequest.Resolver.ChainType(ARequest.Tree, ARequest.FileName, Context.Names, Context.Offset, mChain) or
    not mChain.TypeFound or (mChain.Owner.Kind = TResolvedKind.UnitName) or
    (mChain.Owner.IsType and not Context.Called) or mChain.TypeInfo.Builtin or not (mChain.TypeInfo.SymbolKind in
    [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType]) then
  begin
    Exit;
  end;
  Candidates := ARequest.Resolver.Candidates.MemberCandidates(ARequest.Tree, ARequest.FileName, Context.Names,
    Context.Offset);
  // "property Caption;" hebt nur die Sichtbarkeit an: Typ, Zugriff und Stelle der Deklaration weiter oben.
  for Index := 0 to High(Candidates) do
  begin
    if (Candidates[Index].SymbolKind = TIndexSymbolKind.Property_) and (Candidates[Index].TypeName = '') and
      ARequest.Resolver.Queries.TypedProperty(mChain.TypeInfo, Candidates[Index].Name, Swap, Other) then
    begin
      Swap.Visibility := Candidates[Index].Visibility;
      Swap.Depth := Other;
      Candidates[Index] := Swap;
    end;
  end;
  // Wenige Mitglieder: Einfügen genügt.
  for Index := 1 to High(Candidates) do
  begin
    Other := Index;
    while (Other > 0) and Before(Candidates[Other], Candidates[Other - 1]) do
    begin
      Swap := Candidates[Other];
      Candidates[Other] := Candidates[Other - 1];
      Candidates[Other - 1] := Swap;
      Dec(Other);
    end;
  end;
  Members := nil;
  for Index := 0 to High(Candidates) do
  begin
    if Candidates[Index].IsHelper or not (Candidates[Index].SymbolKind in [TIndexSymbolKind.Field,
      TIndexSymbolKind.Property_]) then
    begin
      Continue;
    end;
    Member := Default(TAssignMember);
    Member.Name := Candidates[Index].Name;
    Member.Kind := Candidates[Index].SymbolKind;
    Member.Signature := Candidates[Index].Signature;
    TypeText := Candidates[Index].TypeName;
    if (TypeText <> '') and (Candidates[Index].TypeArgs <> '') then
    begin
      TypeText := TypeText + '<' + Candidates[Index].TypeArgs + '>';
    end;
    // Generische Typen: TPair<string, Integer>.Key ist ein string.
    Member.TypeName := SubstituteWords(TypeText, Candidates[Index].Bindings);
    Member.Visibility := Candidates[Index].Visibility;
    Member.MaxArgs := Candidates[Index].MaxArgs;
    Members := Members + [Member];
  end;
  Fields := nil;
  Values := TDictionary<string, string>.Create;
  try
    for Member in TAssignFields.Merge(Members) do
    begin
      if not TAssignFields.Writable(Member) then
      begin
        Continue;
      end;
      Field.Name := Member.Name;
      Field.TypeName := Member.TypeName;
      if not Values.TryGetValue(LowerCase(Member.TypeName), Field.Value) then
      begin
        Field.Value := AssignValue(ARequest, Context.Offset, Member.TypeName);
        Values.Add(LowerCase(Member.TypeName), Field.Value);
      end;
      Fields := Fields + [Field];
    end;
  finally
    Values.Free;
  end;
  Expr := Copy(LineText, Context.ChainStart.Character + 1, Context.DotPos.Character - Context.ChainStart.Character);
  // Was die folgenden Zeilen schon zuweisen, fällt weg; die Zahl im Titel zählt nur den Rest.
  Fields := TAssignFields.Without(Fields, TAssignFields.AssignedAfter(TextLines(ARequest.Text),
    ARequest.Position.Line, Expr));
  if Length(Fields) = 0 then
  begin
    Exit;
  end;
  Indent := Copy(LineText, 1, Context.ChainStart.Character);
  LineBreak := ARequest.LineBreak;
  AItem.Name := TAssignFields.Title(Length(Fields));
  AItem.Kind := KindSnippet;
  AItem.Detail := mChain.TypeInfo.Name;
  AItem.Fits := True;
  AItem.Pinned := True;
  // Erzeugt Code: Atlas zeigt die Zusatzänderungen nicht als uses-Ergänzung.
  AItem.Action := 'assign';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(Context.ChainStart, ARequest.Position), '');
  if Length(Fields) > TAssignFields.ListThreshold then
  begin
    // Zuerst die Liste mit Kontrollkästchen: je Zeile die Zuweisung samt Umbruch für die nächste.
    AItem.TextEdit.NewText := Expr + '.';
    for Field in Fields do
    begin
      Assignment.Name := Field.Name;
      Assignment.Detail := Field.TypeName;
      Assignment.Text := TAssignFields.Line(Expr, Field) + LineBreak + Indent;
      AItem.Assignments := AItem.Assignments + [Assignment];
    end;
  end
  else if ASnippets then
  begin
    // Platzhalter-Modus (#51): Zeilen mit #10, die Einrückung setzt der Editor.
    AItem.Snippet := True;
    AItem.TextEdit.NewText := TAssignFields.Snippet(Expr, Fields);
  end
  else
  begin
    AItem.TextEdit.NewText := TAssignFields.Plain(Expr, Indent, LineBreak, Fields);
  end;
  Result := True;
end;


class function TLspCompletion.MethodRefOf(AResolver: TNameResolver; const AFromUnit: TUnitIndex;
  const ATypeText: string; out AMethodRef: TMethodRef): Boolean;
var
  TypeText, Base, Signature, Target: string;
  Args, TypeParams: TArray<string>;
  FromUnit: TUnitIndex;
  Resolved: TResolvedSymbol;
  Depth, Index: Integer;
begin
  AMethodRef := Default(TMethodRef);
  Result := False;
  TypeText := ATypeText;
  FromUnit := AFromUnit;
  for Depth := 0 to TCompletionAnonymous.MaxAliasDepth do
  begin
    Args := TCompletionAnonymous.TypeArgs(TypeText, Base);
    Signature := '';
    if (AResolver <> nil) and AResolver.ResolveTypeTextFrom(FromUnit, TypeText, Resolved) and
      not Resolved.Builtin then
    begin
      Signature := Resolved.Signature;
    end;
    // Ohne Quellen der RTL im Index: die Deklarationen von System.SysUtils.
    if Signature = '' then
    begin
      Signature := TCompletionAnonymous.RtlDeclaration(Base, Length(Args));
    end;
    if Signature = '' then
    begin
      Exit;
    end;
    if TCompletionAnonymous.Parse(Signature, TypeParams, AMethodRef, Target) then
    begin
      for Index := 0 to High(AMethodRef.Params) do
      begin
        AMethodRef.Params[Index].TypeText := TCompletionAnonymous.Substitute(AMethodRef.Params[Index].TypeText,
          TypeParams, Args);
      end;
      AMethodRef.ResultType := TCompletionAnonymous.Substitute(AMethodRef.ResultType, TypeParams, Args);
      Exit(True);
    end;
    // Alias ("TKundenFilter = TPredicate<TKunde>"): weiter mit dem Ziel, gelesen in der Unit des Alias.
    if (Target = '') or not AResolver.DeclaringUnit(Resolved, FromUnit) then
    begin
      Exit;
    end;
    TypeText := TCompletionAnonymous.Substitute(Target, TypeParams, Args);
  end;
end;

class function TLspCompletion.AnonymousItem(ARequest: TCompletionRequest; ASnippets: Boolean;
  const ANamingFor: TCompletionNamingFunc; out AItem: TCompletionItem): Boolean;
var
  Context: TCompletionContext;
  Expected, Prefix, LineText, Indent: string;
  MethodRef: TMethodRef;
  Start: TTextPosition;
  Index: Integer;
begin
  AItem := Default(TCompletionItem);
  Result := False;
  if not ARequest.Settings.AnonymousMethods or (ARequest.Tree = nil) or (ARequest.Resolver = nil) then
  begin
    Exit;
  end;
  Context := Analyze(ARequest.Tree, ARequest.Position);
  if (Context.Kind <> TCompletionContextKind.Scope) or (Context.Filter <> TCompletionFilter.Any) or
    Context.Attribute or Context.Generic then
  begin
    Exit;
  end;
  if (Context.Prefix <> '') and not StartsText(Context.Prefix, 'procedure') and
    not StartsText(Context.Prefix, 'function') then
  begin
    Exit;
  end;
  Expected := ExpectedFullType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ARequest.Position);
  if (Expected = '') or not MethodRefOf(ARequest.Resolver, ARequest.UnitIndex, Expected, MethodRef) then
  begin
    Exit;
  end;
  // Bindungen generischer Instanzen sind qualifiziert ("Kunden.TKunde"); im Gerüst wie im Quelltext üblich.
  Expected := ARequest.Resolver.Queries.UnqualifyType(Expected, ARequest.UnitIndex.UnitName);
  for Index := 0 to High(MethodRef.Params) do
  begin
    MethodRef.Params[Index].TypeText := ARequest.Resolver.Queries.UnqualifyType(MethodRef.Params[Index].TypeText,
      ARequest.UnitIndex.UnitName);
  end;
  MethodRef.ResultType := ARequest.Resolver.Queries.UnqualifyType(MethodRef.ResultType, ARequest.UnitIndex.UnitName);
  if Assigned(ANamingFor) then
  begin
    Prefix := ANamingFor(ARequest.Uri, TNamingKind.Parameter);
  end
  else
  begin
    Prefix := NamingPrefix(ARequest.Index, TNamingKind.Parameter);
  end;
  MethodRef := TCompletionAnonymous.Named(MethodRef, Prefix);
  AItem.Name := TCompletionAnonymous.Header(MethodRef);
  if MethodRef.IsFunction then
  begin
    AItem.FilterText := 'function';
  end
  else
  begin
    AItem.FilterText := 'procedure';
  end;
  AItem.Kind := KindSnippet;
  // Den Typ zeigt Atlas als Tag (MethodRef); rechts steht, was der Eintrag ist.
  AItem.Detail := 'anonyme Methode';
  AItem.MethodRef := Expected;
  AItem.Expected := Expected;
  AItem.Fits := True;
  AItem.Pinned := True;
  // Erzeugt Code: keine uses-Ergänzung.
  AItem.Action := 'anonymous';
  AItem.HasTextEdit := True;
  Start := ARequest.Position;
  Start.Character := Max(0, Start.Character - Length(Context.Prefix));
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(Start, ARequest.Position), '');
  if ASnippets then
  begin
    // Zeilen mit #10, die Einrückung der Zeile setzt der Editor davor.
    AItem.Snippet := True;
    AItem.TextEdit.NewText := TCompletionAnonymous.Snippet(MethodRef);
  end
  else
  begin
    LineText := ARequest.LineText(ARequest.Position.Line);
    Index := 1;
    while (Index <= Length(LineText)) and CharInSet(LineText[Index], [' ', #9]) do
    begin
      Inc(Index);
    end;
    Indent := Copy(LineText, 1, Index - 1);
    AItem.TextEdit.NewText := TCompletionAnonymous.Plain(MethodRef, Indent, ARequest.LineBreak);
  end;
  Result := True;
end;

end.
