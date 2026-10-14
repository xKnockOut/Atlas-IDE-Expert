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
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Documentation;

type
  TCompletionContextKind = (None, Scope, Member, UsesClause);
  /// <summary>Einschränkung der Kandidaten im Gültigkeitsbereich (#31).</summary>
  TCompletionFilter = (Any, Types, InheritedCall);
  /// <summary>Stelle im Quelltext für passende Schlüsselwörter (#31).</summary>
  TCompletionPlace = (Unknown, Declaration, ClassBody, Statement);

  TCompletionContext = record
    Kind: TCompletionContextKind;
    /// <summary>Schon getippter Anfang des Namens.</summary>
    Prefix: string;
    /// <summary>Kette vor dem Punkt bei Member, z. B. ['Self', 'Liste'].</summary>
    Names: TArray<string>;
    /// <summary>Offset, an dem die Namen gelten.</summary>
    Offset: Integer;
    /// <summary>Bei Member: Anfang der Kette und Position des Punkts.</summary>
    ChainStart: TTextPosition;
    DotPos: TTextPosition;
    /// <summary>Bei Member: Das letzte Glied steht mit Klammern da, Foo(1). oder TFoo(X). (#188).</summary>
    Called: Boolean;
    /// <summary>Bei Scope: nur Typen bzw. nur Methoden der Vorfahren (#31).</summary>
    Filter: TCompletionFilter;
    /// <summary>Bei Filter Types: auch Typ-Schlüsselwörter wie string und array (nach ":").</summary>
    TypeKeywords: Boolean;
    /// <summary>Bei Scope: Anweisung, Deklaration oder Klassenrumpf (#31).</summary>
    Place: TCompletionPlace;
  end;

  TCompletionItem = record
    Name: string;
    Detail: string;
    /// <summary>CompletionItemKind des LSP.</summary>
    Kind: Integer;
    /// <summary>Text für den Filter des Editors; '' = Name.</summary>
    FilterText: string;
    /// <summary>Weitere Änderungen beim Annehmen, z. B. der uses-Eintrag.</summary>
    AdditionalEdits: TArray<TRuleEdit>;
    /// <summary>Datei und Namensposition der Deklaration für completionItem/resolve; '' ohne.</summary>
    SourceFile: string;
    SourcePosition: TTextPosition;
    /// <summary>Deklarierender Typ bei Mitgliedern (#419); ''.</summary>
    Container: string;
    /// <summary>Vererbungstiefe bei Mitgliedern: 0 = eigener Typ (#419).</summary>
    Depth: Integer;
    /// <summary>Mitglied aus einem Helper (#456).</summary>
    IsHelper: Boolean;
    /// <summary>Namenspositionen weiterer Überladungen in SourceFile (#425).</summary>
    Overloads: TArray<TTextPosition>;
    /// <summary>Routine mit Parametern (in irgendeiner Überladung), für Klammern beim Übernehmen (#430).</summary>
    HasParameters: Boolean;
    /// <summary>Text beim Übernehmen statt des Namens; ''.</summary>
    InsertText: string;
    /// <summary>Erwarteter Typ an der Stelle (#417, #444); '' ohne. Atlas gruppiert dann nach Fits.</summary>
    Expected: string;
    /// <summary>Eintrag passt zu Expected.</summary>
    Fits: Boolean;
    /// <summary>Bedingung der Deklaration ("WIN64", "platform"); '' = immer (#476).</summary>
    Condition: string;
    /// <summary>Unter der aktiven Konfiguration nicht deklariert; Atlas zeigt es abgeschwächt am Ende (#476).</summary>
    Unavailable: Boolean;
    /// <summary>Gültigkeitsbereich ohne Punkt davor (#488): 1 lokal, 2 Parameter, 3 Mitglied von Self,
    /// 4 eigene Unit, 5 andere Unit; 0 = keine Angabe (nach einem Punkt, Schlüsselwörter …).</summary>
    Scope: Integer;
    /// <summary>Unit der Deklaration bei Scope 5 (#488): Atlas zeigt sie als Tag.</summary>
    UnitName: string;
    /// <summary>Verdeckte gleichnamige Deklarationen weiter außen (#488), z. B. "Feld TKunde.Total".</summary>
    Hides: TArray<string>;
    /// <summary>Eintrag erzeugt Code statt nur einen Namen: 'override' (#443), 'create' (neue Methode, #444);
    /// Atlas wertet AdditionalEdits dann nicht als uses-Ergänzung.</summary>
    Action: string;
    /// <summary>Ersetzt TextEdit.Range statt nur den getippten Namen (Postfix-Vorlagen, #188).</summary>
    HasTextEdit: Boolean;
    TextEdit: TRuleEdit;
    /// <summary>Wert einer Aufzählung (#448): Stelle in der Deklaration ab 1; 0 bei anderen Einträgen.</summary>
    Ordinal: Integer;
    /// <summary>Mengenmodus (#448): Aufzählungstyp der Menge; '' sonst. Dann gelten SetChecked und SetRange.</summary>
    SetOf: string;
    /// <summary>Wert steht schon in der Klammer.</summary>
    SetChecked: Boolean;
    /// <summary>Was Enter mit dem neuen Klammerinhalt ersetzt: von "[" bis hinter "]".</summary>
    SetRange: TTextRange;
    /// <summary>Steht immer oben und passt zu jedem getippten Wort („Alle Werte einfügen“, #449).</summary>
    Pinned: Boolean;
    /// <summary>Zahl als Tag (fehlende Werte, #449); 0 ohne.</summary>
    Count: Integer;
    /// <summary>Eintrag deklariert diesen unbekannten Namen (#471); Atlas zeigt die Gruppe „Name ist unbekannt“.</summary>
    Unknown: string;
    /// <summary>Interface implementieren (#466): Eintrag der Liste mit Kontrollkästchen (SetOf = Interfaces,
    /// SetChecked, SetRange = getipptes Wort). Atlas übernimmt die AdditionalEdits aller angehakten Einträge in
    /// Ordinal-Reihenfolge und fasst Einfügungen an derselben Stelle zusammen.</summary>
    Batch: Boolean;
    /// <summary>Hinweis „3 Methoden von IExporter fehlen“ (#466): ganz oben, nie vorgewählt.</summary>
    Hint: Boolean;
    /// <summary>Komponente aus dem Formular (#455): Name des Formulars; Atlas zeigt die Gruppe „Formular …“ oben.</summary>
    Form: string;
    /// <summary>Komponente passt nur über ihren Typ ("button" → btnSave: TButton), nicht über den Namen.</summary>
    ByType: Boolean;
    /// <summary>Sender mit Typumwandlung (#480): Typ, als der Sender gilt; '' sonst. Dann ersetzt TextEdit
    /// "Sender.Na" durch "(Sender as TButton).Name".</summary>
    Sender: string;
    /// <summary>Komponenten, denen die Methode im Designer zugewiesen ist: "btnSave, btnLoad".</summary>
    SenderOf: string;
    /// <summary>Feld- oder Parametername (#461): Datenmenge, aus der der Name stammt; '' sonst.</summary>
    DataSet: string;
    /// <summary>Kurzform der SQL-Anweisung als Quellenangabe für die Fußzeile; '' ohne Anweisung.</summary>
    DataSource: string;
    /// <summary>Freigabe absichern (#489): 'newLine' oder 'routineEnd'; '' sonst. Weitertippen verwirft.</summary>
    Guard: string;
    /// <summary>InsertText bzw. TextEdit.NewText ist ein LSP-Snippet mit Platzhaltern (#51); dann
    /// insertTextFormat = 2. Nur an Clients mit snippetSupport.</summary>
    Snippet: Boolean;
  end;

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

  TCompletionReadText = TDocReadText;

  TCompletionItems = record
    Items: TArray<TCompletionItem>;
    /// <summary>Liste wurde gekürzt; der Editor fragt beim Weitertippen neu.</summary>
    Incomplete: Boolean;
  end;

  TCompletionMatchingFunc = reference to function(const AUri: string): TCompletionMatching;

  /// <summary>Einstellungen der Vervollständigung je Dokument (#466, #480).</summary>
  TCompletionSettingsFunc = reference to function(const AUri: string): TCompletionSettings;

  /// <summary>Teilergebnis einer gestaffelten Vervollständigung (#616), in Anzeigereihenfolge.</summary>
  TCompletionPartialProc = reference to procedure(const AItems: TArray<TCompletionItem>);

  /// <summary>Sendet eine Benachrichtigung an den Client (z. B. $/progress); übernimmt AParams.</summary>
  TCompletionNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);

  /// <summary>Zeitmessung je Anfrage (#616), z. B. für ILogger.Debug.</summary>
  TCompletionLogProc = reference to procedure(const AText: string);

  TLspCompletion = class
  public const
    Method = 'textDocument/completion';
    ResolveMethod = 'completionItem/resolve';
    /// <summary>Eigene Postfix-Vorlagen vom Plugin (#188).</summary>
    PostfixTemplatesMethod = 'atlas/postfixTemplates';
    MaxItems = 1000;
    /// <summary>Höchstzahl der Vorschläge aus nicht eingebundenen Units.</summary>
    MaxImportItems = 200;
    /// <summary>So viele Zeichen muss der Name haben, bevor nicht eingebundene Units mitsuchen.</summary>
    MinImportPrefix = 2;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FMatchingFor: TCompletionMatchingFunc;
    FSettingsFor: TCompletionSettingsFunc;
    FReadText: TCompletionReadText;
    FSlashCommandsFor: TSlashCommandsProvider;
    FPostfixFor: TPostfixOptionsFunc;
    FHintsFor: TDocHintsProvider;
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
    procedure HandlePostfixTemplates(const AParams: TJSONValue);
    function ReadCached(const AFileName: string; out AText: string): Boolean;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleResolve(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>completionProvider mit Punkt als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Was an APosition vervollständigt wird.</summary>
    class function Analyze(ATree: TSyntaxTree; const APosition: TTextPosition): TCompletionContext; static;
    /// <summary>Erwarteter Typ an APosition (#417): Typ des aktiven Parameters im innersten Aufruf, sonst der
    /// linken Seite einer Zuweisung (auch Result); '' wenn unbekannt.</summary>
    class function ExpectedType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): string; static;
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition;
      AMatching: TCompletionMatching = TCompletionMatching.Fuzzy): TCompletionItems; overload; static;
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
    /// <summary>In einer Klassendeklaration nach "procedure " bzw. "function " (#443): überschreibbare
    /// Methoden der Vorfahren; Übernehmen setzt den Rest der Deklaration mit override und erzeugt den Rumpf
    /// mit inherited. False außerhalb dieses Kontexts.</summary>
    class function OverrideItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
      static;
    /// <summary>In "property Name: T read " bzw. "write " im Klassenrumpf (#31): Felder vom Typ T und Methoden mit
    /// passender Signatur (read: Funktion mit Ergebnis T und den Indexparametern; write: Prozedur mit den
    /// Indexparametern und einem Parameter vom Typ T), auch geerbte. False außerhalb dieses Kontexts.</summary>
    class function PropertyItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; AMatching: TCompletionMatching; out AItems: TCompletionItems): Boolean; static;
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
      static;
    /// <summary>Aufzählungen und Mengen (#448). Erwartet die Stelle einen Aufzählungstyp (Zuweisung, Parameter,
    /// Vergleich, case-Zweig), kommen dessen Werte in Deklarationsreihenfolge (Ordinal, bei {$SCOPEDENUMS ON} mit
    /// Typpräfix im InsertText). In einem Mengenkonstruktor ("Anchors := [akLeft, ") kommen alle Werte des
    /// Elementtyps mit SetOf, SetChecked und SetRange; ASetMode ist dann True. False ohne Aufzählungstyp.</summary>
    class function EnumItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
      AMatching: TCompletionMatching; out AItems: TArray<TCompletionItem>; out ASetMode: Boolean): Boolean; static;
    /// <summary>Unbekannter Name am Cursor im Rumpf einer Routine (#471): lokale Variable (mit AInlineVar auch als
    /// Inline-var), Feld der Klasse (F-Konvention, die Verwendung wird umbenannt) und, wenn der Name als Wert
    /// dient, Konstante in der implementation. Typ aus der rechten Seite einer Zuweisung, sonst aus dem
    /// erwarteten Typ, sonst ein Platzhalter. False, wenn der Name bekannt ist oder in AKnown genau vorkommt.</summary>
    class function DeclareItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; AInlineVar: Boolean;
      const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean; static;
    /// <summary>In der Deklaration einer Klasse mit Interfaces in der Vorfahrenliste (#466), wenn Methoden fehlen.
    /// Leere Zeile bis zum Cursor: je fehlender Methode ein Eintrag mit Kontrollkästchen (Batch), ABatch True.
    /// Angefangenes Wort: je Interface ein Hinweis „n Methoden von I fehlen“ (Hint), der alle seine fehlenden
    /// Methoden anlegt. Deklarationen kommen in den Abschnitt ASection (mit Kommentar "{ I }"), Rümpfe wie bei
    /// #443 ohne inherited. False außerhalb dieses Kontexts oder ohne fehlende Methoden.</summary>
    class function InterfaceItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText; ASection: TCompletionInterfaceSection;
      out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean; static;
    /// <summary>Komponenten des Formulars zur Unit (#455), wenn der Cursor ohne Punkt in einer Methode der
    /// Formularklasse steht. Quelle ist die Formulardatei über AReadText, also der Stand im Designer, solange das
    /// Formular offen ist. Je Komponente ein Feld mit ihrem Typ als Detail und Form = Formularname. Passt der Name
    /// nicht zum Getippten, aber der Typ (eigene Klasse beginnt damit ohne "T", oder ein Vorfahr heißt genau so),
    /// kommt sie mit ByType. False ohne Formular oder außerhalb seiner Methoden.</summary>
    class function ComponentItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; const AReadText: TCompletionReadText; AMatching: TCompletionMatching;
      out AItems: TArray<TCompletionItem>): Boolean; static;
    /// <summary>Cursor im ersten Argument von FieldByName, FindField oder ParamByName an einer Datenmenge der
    /// Unit (#461): die Namen aus der Formulardatei (persistente Felder, Spalten der SQL-Anweisung,
    /// Platzhalter, Params). Jeder Eintrag ersetzt den ganzen String-Inhalt. True auch ohne Namen, denn im
    /// String gibt es sonst nichts vorzuschlagen.</summary>
    class function DataNameItems(const AIndex: ISymbolIndex; const AText, AFileName: string; const APosition: TTextPosition;
      const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Freigabe absichern (#489): Nach "Liste := TStringList.Create;" in Zeile APosition.Line „Mit
    /// try…finally absichern“ und, wenn danach noch Zeilen bis zum Routinenende folgen, dieselbe Absicherung bis
    /// dorthin. False, wenn die Anweisung nicht passt (TGuardFree.Check). ANewLine: Ausgelöst durch Enter am
    /// Zeilenende; die Anweisung steht dann in der Zeile davor, und die leere Zeile des Cursors wird ersetzt.</summary>
    class function GuardItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
      const APosition: TTextPosition; AStyle: TCompletionFreeStyle; ANewLine: Boolean;
      out AItems: TCompletionItems): Boolean; static;
    /// <summary>"Sender." in einem Ereignisbehandler mit "Sender: TObject" (#480): Ist die Methode im Formular
    /// Komponenten zugewiesen, die Mitglieder des nächsten gemeinsamen Vorfahren ihrer Typen. Jeder Eintrag
    /// ersetzt "Sender.Na" (TextEdit) durch die Umwandlung nach ACast und den Namen. False ohne Zuweisung im
    /// Formular, bei bereits umgewandeltem Sender oder wenn der gemeinsame Typ TObject ist.</summary>
    class function SenderItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
      AMatching: TCompletionMatching; ACast: TCompletionSenderCast; out AItems: TCompletionItems): Boolean; static;
    class function KindOf(AKind: TIndexSymbolKind): Integer; static;
    /// <summary>Kontextabhängige Code-Vorlagen (#51) für die Zeile von APosition: prop, changed, create, free.
    /// Mit ASnippetSupport als LSP-Snippet, sonst als Klartext ohne Platzhalter.</summary>
    class function ContextItems(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>; const AText: string;
      const APosition: TTextPosition; AMatching: TCompletionMatching;
      ASnippetSupport: Boolean): TArray<TCompletionItem>; static;
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
      const APosition: TTextPosition; const AReadText: TCompletionReadText = nil): TJSONObject; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Liest Dateien für completionItem/resolve; ohne Zuweisung keine Details.</summary>
    property ReadText: TCompletionReadText read FReadText write FReadText;
    /// <summary>Auswahl je Dokument; ohne Zuweisung unscharf.</summary>
    property MatchingFor: TCompletionMatchingFunc read FMatchingFor write FMatchingFor;
    /// <summary>Abschnitt für Interface-Methoden (#466), Typumwandlung von Sender (#480); ohne Zuweisung die
    /// Standardwerte.</summary>
    property SettingsFor: TCompletionSettingsFunc read FSettingsFor write FSettingsFor;
    /// <summary>Schnellbefehle nach "/" am Zeilenanfang (#293); ohne Zuweisung alle eingeschaltet.</summary>
    property SlashCommandsFor: TSlashCommandsProvider read FSlashCommandsFor write FSlashCommandsFor;
    /// <summary>Postfix-Vorlagen je Dokument (#188); ohne Zuweisung an und mit Inline-Variable.</summary>
    property PostfixFor: TPostfixOptionsFunc read FPostfixFor write FPostfixFor;
    /// <summary>Anzeige von XMLDoc (#654) als data.atlas.xmlDoc; ohne Zuweisung fehlt das Feld.</summary>
    property HintsFor: TDocHintsProvider read FHintsFor write FHintsFor;
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
  System.Math,
  System.StrUtils,
  System.Diagnostics,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.DeclareUnknown,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Lsp.CompilerDirectives,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.NameIndex,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Lsp.SignatureHelp,
  System.RegularExpressions,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Lsp.CompletionEnums,
  Atlas.Common.Editing.DataFieldNames,
  Atlas.Common.Editing.GuardFree,
  Atlas.Common.Editing.ContextSnippets;

const
  /// <summary>Art der Stelle im Diagnoselog (#647).</summary>
  ContextCodes: array[TCompletionContextKind] of string = ('none', 'scope', 'memberAccess', 'uses');
  // CompletionItemKind
  KindMethod = 2;
  KindFunction = 3;
  KindConstructor = 4;
  KindField = 5;
  KindVariable = 6;
  KindClass = 7;
  KindInterface = 8;
  KindModule = 9;
  KindProperty = 10;
  KindEnum = 13;
  KindEnumMember = 20;
  KindConstant = 21;
  KindStruct = 22;
  KindKeyword = 14;
  KindSnippet = 15;
  /// <summary>Typen im Index (#31: Filter nach "class(", ":", "is", "as").</summary>
  IndexTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
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

/// <summary>Text der Zeile von APosition bis zum Cursor.</summary>
function LineBefore(const AText: string; const APosition: TTextPosition): string;
var
  Line, Start, Stop: Integer;
begin
  Start := 1;
  for Line := 1 to APosition.Line do
  begin
    Start := PosEx(#10, AText, Start) + 1;
    if Start = 1 then
      Exit('');
  end;
  Stop := Start;
  while (Stop <= Length(AText)) and (AText[Stop] <> #10) and (AText[Stop] <> #13) do
    Inc(Stop);
  Result := Copy(AText, Start, Min(APosition.Character, Stop - Start));
end;

/// <summary>Vorschläge in einer offenen Direktive (#102); False außerhalb.</summary>
function DirectiveItems(const AText: string; const APosition: TTextPosition; out AItems: TCompletionItems): Boolean;
var
  Names: TArray<string>;
  IsWarning: Boolean;
  Name: string;
  Item: TCompletionItem;
  Info: TDirectiveInfo;
begin
  AItems := Default(TCompletionItems);
  Result := TCompilerDirectives.CompletionAt(LineBefore(AText, APosition), Names, IsWarning);
  if not Result then
    Exit;
  for Name in Names do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Name;
    Item.Kind := KindKeyword;
    if IsWarning then
      Item.Detail := 'Compiler-Warnung'
    else if TCompilerDirectives.Find(Name, Info) then
      Item.Detail := Info.Text;
    AItems.Items := AItems.Items + [Item];
  end;
end;

function SlashItems(const AText: string; const APosition: TTextPosition; const ADisabled: TArray<string>;
  out AItems: TCompletionItems): Boolean;
var
  Before, Name, Arguments: string;
  Command: TSlashCommand;
  Item: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  // Nur "/name" ohne Argumente vor dem Cursor; danach vervollständigen die Befehle selbst (#294 ff.).
  Before := LineBefore(AText, APosition);
  if Trim(Before) = '/' then
    Name := ''
  else if not TSlashCommandRegistry.Split(Before, Name, Arguments) or (Arguments <> '') or
    (Before[Length(Before)] = ' ') then
    Exit(False);
  if not TSlashCommandRegistry.IsCodeLine(TPascalLexer.Tokenize(AText), APosition.Line) then
    Exit(False);
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
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
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
      Inc(Depth)
    else if ATokens[Result].IsSymbol('(') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end
    else if ATokens[Result].IsSymbol(';') or ATokens[Result].IsKeyword('begin') then
      Break;
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
      Exit(True);
    if not ((Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.StringLiteral]) or
      Token.IsSymbol('.') or Token.IsSymbol(',') or Token.IsKeyword('in') or IsTrivia(Token)) then
      Exit(False);
    Dec(AIndex);
  end;
  Result := False;
end;

{ TLspCompletion }

constructor TLspCompletion.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FCacheLock := TObject.Create;
end;

destructor TLspCompletion.Destroy;
begin
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
    Exit(FReadText(AFileName, AText));
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
    Exit;
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
    Exit;
  Templates := TJSONObject(AParams).GetValue('templates');
  if not (Templates is TJSONArray) then
    Exit;
  for Value in TJSONArray(Templates) do
  begin
    if not (Value is TJSONObject) then
      Continue;
    Item := TJSONObject(Value);
    Key := Item.GetValue<string>('key', '');
    Body := Item.GetValue<string>('body', '');
    // Nur Kürzel aus Buchstaben, Ziffern und _; sie stehen hinter einem Punkt.
    if (Key = '') or (Body = '') or not IsValidIdent(Key) then
      Continue;
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
    Exit;
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
      Exit(TCompletionPlace.ClassBody);
    if Node.Kind in [TSyntaxKind.Block .. TSyntaxKind.EmptyStatement] then
      Exit(TCompletionPlace.Statement);
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
    Exit;
  if ATokens[ALast].IsKeyword('is') or ATokens[ALast].IsKeyword('as') then
    Exit(True);
  if ATokens[ALast].IsKeyword('not') then
  begin
    Before := PreviousIndex(ATokens, ALast);
    Exit((Before >= 0) and ATokens[Before].IsKeyword('is'));
  end;
  if ATokens[ALast].IsSymbol(':') then
  begin
    if APlace <> TCompletionPlace.Statement then
      Result := True
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
    Index := PreviousIndex(ATokens, Index);
  if (Index < 0) or not ATokens[Index].IsSymbol('(') then
    Exit;
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
begin
  Result := Default(TCompletionContext);
  Result.Kind := TCompletionContextKind.None;
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  // Letztes Token, das vor dem Cursor beginnt.
  Last := -1;
  for Index := 0 to High(Tokens) do
  begin
    if ComparePositions(Tokens[Index].StartPos, APosition) >= 0 then
      Break;
    Last := Index;
  end;
  Result.Offset := 0;
  if Last >= 0 then
  begin
    Token := Tokens[Last];
    Result.Offset := Token.Offset + Length(Token.Text);
    if ComparePositions(APosition, Token.EndPos) < 0 then
    begin
      // Cursor mitten in einem Token: in Kommentaren, Strings und Zahlen nichts anbieten.
      if Token.Kind <> TPascalTokenKind.Identifier then
        Exit;
    end;
    if (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      (ComparePositions(APosition, Token.EndPos) <= 0) then
    begin
      // Angefangener Name; auch ein halbes Schlüsselwort wie "beg" gilt als Anfang.
      if Token.Kind = TPascalTokenKind.Identifier then
        Result.Prefix := CleanName(Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character))
      else
        Result.Prefix := Copy(Token.Text, 1, APosition.Character - Token.StartPos.Character);
      Result.Offset := Token.Offset;
      Last := PreviousIndex(Tokens, Last);
    end
    else if IsTrivia(Token) and (ComparePositions(APosition, Token.EndPos) <= 0) and
      Token.Text.StartsWith('//') then
      // Zeilenkommentar reicht bis zum Zeilenende.
      Exit
    else if IsTrivia(Token) then
      Last := PreviousIndex(Tokens, Last + 1);
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
            Exit;
          Index := PreviousIndex(Tokens, Index);
          if (Index < 0) or (Tokens[Index].Kind <> TPascalTokenKind.Identifier) then
            Exit;
          if Names.Count = 0 then
            Result.Called := True;
        end;
        if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
          Break;
        Names.Insert(0, CleanName(Tokens[Index].Text));
        Result.ChainStart := Tokens[Index].StartPos;
        Index := PreviousIndex(Tokens, Index);
        if (Index >= 0) and Tokens[Index].IsSymbol('.') then
          Index := PreviousIndex(Tokens, Index)
        else
          Break;
      end;
      // 1. oder "a".: nicht auflösbar.
      if (Names.Count = 0) or (Index >= 0) and Tokens[Index].IsSymbol('.') then
        Exit;
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
    Result.Filter := TCompletionFilter.InheritedCall
  else if TypePosition(Tokens, Last, Result.Place, Result.TypeKeywords) then
    Result.Filter := TCompletionFilter.Types;
end;

class function TLspCompletion.KindOf(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias:
      Result := KindClass;
    TIndexSymbolKind.RecordType:
      Result := KindStruct;
    TIndexSymbolKind.InterfaceType:
      Result := KindInterface;
    TIndexSymbolKind.EnumType:
      Result := KindEnum;
    TIndexSymbolKind.EnumMember:
      Result := KindEnumMember;
    TIndexSymbolKind.Constant:
      Result := KindConstant;
    TIndexSymbolKind.Field:
      Result := KindField;
    TIndexSymbolKind.Property_:
      Result := KindProperty;
    TIndexSymbolKind.Method:
      Result := KindMethod;
    TIndexSymbolKind.Constructor_:
      Result := KindConstructor;
    TIndexSymbolKind.Routine:
      Result := KindFunction;
  else
    Result := KindVariable;
  end;
end;

type
  TScoredItem = record
    Item: TCompletionItem;
    Score: Integer;
    Order: Integer;
  end;

  TScoredItemComparer = class(TInterfacedObject, IComparer<TScoredItem>)
  public
    function Compare(const Left, Right: TScoredItem): Integer;
  end;

function TScoredItemComparer.Compare(const Left, Right: TScoredItem): Integer;
begin
  // Höhere Punktzahl zuerst, sonst Reihenfolge der Gültigkeitsbereiche.
  if Left.Score <> Right.Score then
    Result := Right.Score - Left.Score
  else
    Result := Left.Order - Right.Order;
end;

/// <summary>Punktzahl von AName; TFuzzyMatch.NoMatch, wenn er nicht passt.</summary>
/// <summary>Typname für den Vergleich: ohne Leerzeichen und Unit-Präfix, klein.</summary>
function PlainType(const AType: string): string;
begin
  Result := LowerCase(AType.Replace(' ', ''));
  if (Pos('<', Result) = 0) and (LastDelimiter('.', Result) > 0) then
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

type
  TTypeFamily = (None, Integer_, Float, String_, Char_, Boolean_);

/// <summary>Familie eingebauter Typen für die Zuweisungsverträglichkeit (#417).</summary>
function TypeFamily(const APlain: string): TTypeFamily;
begin
  if MatchText(APlain, ['integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'shortint', 'smallint', 'longint',
    'longword', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32', 'fixedint',
    'fixeduint']) then
    Result := TTypeFamily.Integer_
  else if MatchText(APlain, ['double', 'single', 'extended', 'real', 'currency', 'comp']) then
    Result := TTypeFamily.Float
  else if MatchText(APlain, ['string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'rawbytestring',
    'utf8string']) then
    Result := TTypeFamily.String_
  else if MatchText(APlain, ['char', 'widechar', 'ansichar']) then
    Result := TTypeFamily.Char_
  else if MatchText(APlain, ['boolean', 'bytebool', 'wordbool', 'longbool']) then
    Result := TTypeFamily.Boolean_
  else
    Result := TTypeFamily.None;
end;

/// <summary>Ein Wert vom Typ AActual passt zu AExpected: gleich, gleiche Familie eingebauter Typen,
/// Integer zu Gleitkomma, Char zu String. ACheckDescent: Beides sind keine eingebauten Typen; ob AActual
/// von AExpected abstammt, muss die Namensauflösung klären.</summary>
function TypeFits(const AActual, AExpected: string; out ACheckDescent: Boolean): Boolean;
var
  Actual, Expected: TTypeFamily;
begin
  ACheckDescent := False;
  if (AActual = '') or (AExpected = '') then
    Exit(False);
  if PlainType(AActual) = PlainType(AExpected) then
    Exit(True);
  Actual := TypeFamily(PlainType(AActual));
  Expected := TypeFamily(PlainType(AExpected));
  if Expected <> TTypeFamily.None then
    Exit((Actual = Expected) or (Expected = TTypeFamily.Float) and (Actual = TTypeFamily.Integer_) or
      (Expected = TTypeFamily.String_) and (Actual = TTypeFamily.Char_));
  ACheckDescent := Actual = TTypeFamily.None;
  Result := False;
end;

function MatchScore(const AName, APrefix: string; AMatching: TCompletionMatching): Integer;
begin
  if APrefix = '' then
    Exit(0);
  if AMatching = TCompletionMatching.Prefix then
  begin
    if AName.StartsWith(APrefix, True) then
      Exit(0);
    Exit(TFuzzyMatch.NoMatch);
  end;
  Result := TFuzzyMatch.Score(AName, APrefix);
end;

/// <summary>Vorfilter des Resolvers (#616): nur Namen, die zu APrefix passen. GetEnumerator bleibt, weil die
/// Postfix-Vorlagen daran erkennen, ob der Typ aufzählbar ist; Add verwirft ihn ohne Treffer wieder.</summary>
function PrefixFilter(const APrefix: string; AMatching: TCompletionMatching): TCandidateNameFilter;
begin
  Result :=
    function(const AName: string): Boolean
    begin
      Result := (MatchScore(AName, APrefix, AMatching) <> TFuzzyMatch.NoMatch) or SameText(AName, 'GetEnumerator');
    end;
end;

class function TLspCompletion.ExpectedType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
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
    Exit;
  // Argument eines Aufrufs: Typ des aktiven Parameters (erste passende Überladung).
  Site := TLspSignatureHelp.CallSiteAt(ATree, APosition);
  if Site.Found then
  begin
    Callee := AResolver.Resolve(ATree, AFileName, Site.NamePosition);
    if Callee.Found and (Site.ActiveParameter < Length(Callee.ParamTypes)) then
      Result := Callee.ParamTypes[Site.ActiveParameter];
    Exit;
  end;
  // Zuweisung: "Ziel := A.B.Anf|" – rückwärts über die Kette rechts bis zum ":=".
  Tokens := ATree.Tokens;
  Last := -1;
  for Index := 0 to High(Tokens) do
  begin
    if ComparePositions(Tokens[Index].StartPos, APosition) >= 0 then
      Break;
    Last := Index;
  end;
  Index := PreviousIndex(Tokens, Last + 1);
  if (Index >= 0) and (Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (ComparePositions(APosition, Tokens[Index].EndPos) <= 0) then
    Index := PreviousIndex(Tokens, Index);
  while (Index >= 0) and Tokens[Index].IsSymbol('.') do
  begin
    Index := PreviousIndex(Tokens, Index);
    if (Index < 0) or (Tokens[Index].Kind <> TPascalTokenKind.Identifier) then
      Exit;
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
        Result := Target.Name
      else if Target.Found then
        Result := Target.TypeName;
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
      Index := PreviousIndex(Tokens, Index)
    else
      Break;
  end;
  if Names = nil then
    Exit;
  Target := AResolver.ResolveChain(ATree, AFileName, Names, Last);
  if Target.Found and not Target.IsType and (Target.SymbolKind <> TIndexSymbolKind.Routine) and
    (Target.SymbolKind <> TIndexSymbolKind.Method) then
    Result := Target.TypeName;
  // Result: Rückgabetyp der umgebenden Funktion.
  if (Result = '') and (Length(Names) = 1) and SameText(Names[0], 'Result') then
  begin
    UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
    for Symbol in UnitIndex.Symbols do
      if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and (Symbol.TypeName <> '') and
        (Symbol.Range.StartPos.Line < APosition.Line) and (Symbol.Range.EndPos.Line >= APosition.Line) then
        Result := Symbol.TypeName;
  end;
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

/// <summary>Zeile ALine von AText ohne Zeilenende.</summary>
function LineOf(const AText: string; ALine: Integer): string;
var
  Lines: TArray<string>;
begin
  Lines := AText.Split([#10]);
  if (ALine < 0) or (ALine > High(Lines)) then
    Exit('');
  Result := Lines[ALine];
  if Result.EndsWith(#13) then
    SetLength(Result, Length(Result) - 1);
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
      Exit;
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
    Exit;
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
    Result := TJSONString.Create(Text);
end;

class function TLspCompletion.Keywords(APlace: TCompletionPlace): TArray<string>;
var
  Word: string;
begin
  Result := nil;
  case APlace of
    TCompletionPlace.Statement:
      for Word in StatementKeywords do
        Result := Result + [Word];
    TCompletionPlace.Declaration:
      for Word in DeclarationKeywords do
        Result := Result + [Word];
    TCompletionPlace.ClassBody:
      for Word in ClassBodyKeywords do
        Result := Result + [Word];
  end;
end;

class function TLspCompletion.ContextItems(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>;
  const AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  ASnippetSupport: Boolean): TArray<TCompletionItem>;
var
  Slash: TSlashContext;
  Snippet: TContextSnippet;
  Item: TCompletionItem;
  LineText, Word: string;
  Start: Integer;
begin
  Result := nil;
  LineText := LineOf(AText, APosition.Line);
  // Getipptes Wort vor dem Cursor; TContextSnippets prüft, dass sonst nichts in der Zeile steht.
  Start := Min(APosition.Character, Length(LineText));
  while (Start > 0) and CharInSet(LineText[Start], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(Start);
  Word := Copy(LineText, Start + 1, APosition.Character - Start);
  Slash := Default(TSlashContext);
  Slash.Text := AText;
  Slash.Line := APosition.Line;
  Slash.LineText := LineText;
  Slash.Index := AIndex;
  Slash.Namespaces := ANamespaces;
  for Snippet in TContextSnippets.At(Slash, APosition.Character) do
  begin
    if (MatchScore(Snippet.Prefix, Word, AMatching) = TFuzzyMatch.NoMatch) and
      (MatchScore(Snippet.Name, Word, AMatching) = TFuzzyMatch.NoMatch) then
      Continue;
    Item := Default(TCompletionItem);
    Item.Name := Snippet.Name;
    Item.Detail := Snippet.Description;
    Item.Kind := KindSnippet;
    Item.FilterText := Snippet.Prefix;
    Item.HasTextEdit := True;
    Item.Snippet := ASnippetSupport;
    if ASnippetSupport then
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(APosition.Line, Start, APosition.Line,
        APosition.Character), Snippet.Text)
    else
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(APosition.Line, Start, APosition.Line,
        APosition.Character), TContextSnippets.ToPlain(Snippet.Text));
    Item.AdditionalEdits := Snippet.AdditionalEdits;
    // Atlas wertet die weiteren Änderungen dann nicht als uses-Ergänzung.
    Item.Action := 'snippet';
    Result := Result + [Item];
  end;
end;

/// <summary>Steht AOffset in einer Funktion (Exit mit Wert erlaubt, #188)? Innerste Routine mit Kopf "function",
/// "class function" oder "operator".</summary>
function InFunctionAt(ATree: TSyntaxTree; const AText: string; AOffset: Integer): Boolean;

  function Innermost(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    Result := nil;
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.StartOffset <= AOffset) and (AOffset <= Child.EndOffset) then
      begin
        Result := Innermost(Child);
        if (Result = nil) and (Child.Kind = TSyntaxKind.RoutineDecl) then
          Result := Child;
        Exit;
      end;
    end;
  end;

var
  Routine: TSyntaxNode;
  Head: string;
begin
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Routine := Innermost(ATree.Root);
  if Routine = nil then
    Exit;
  Head := LowerCase(TrimLeft(Copy(AText, Routine.StartOffset + 1, 40)));
  if StartsStr('class ', Head) then
    Head := TrimLeft(Copy(Head, Length('class ') + 1, MaxInt));
  Result := StartsStr('function', Head) or StartsStr('operator', Head);
end;

/// <summary>Was über den Typ der Kette bekannt ist; False, wenn er unbekannt ist oder kein Wert vorliegt.</summary>
function PostfixTraits(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AContext: TCompletionContext; const AMembers: TArray<TResolvedSymbol>; out ATraits: TPostfixTraits): Boolean;
var
  Owner, TypeInfo, Member, Enumerator: TResolvedSymbol;
  TypeFound: Boolean;
  OwnerType: string;
begin
  ATraits := Default(TPostfixTraits);
  // Ein Typ ist kein Wert, außer als Typumwandlung TFoo(X) (#188).
  if not AResolver.ChainType(ATree, AFileName, AContext.Names, AContext.Offset, Owner, TypeInfo, TypeFound) or
    (Owner.Kind = TResolvedKind.UnitName) or (Owner.IsType and not AContext.Called) then
    Exit(False);
  // Typargumente stehen getrennt: TArray mit TypeArgs Integer.
  if Owner.IsType then
    OwnerType := Owner.Name
  else
    OwnerType := Owner.TypeName;
  if Owner.TypeArgs <> '' then
    OwnerType := OwnerType + '<' + Owner.TypeArgs + '>';
  // Typ für eine Deklaration im var-Abschnitt; TFoo.Create liefert ein TFoo.
  if Owner.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    ATraits.IsConstructorCall := True;
    ATraits.TypeName := Owner.Container;
  end
  else if OwnerType <> '' then
    ATraits.TypeName := OwnerType
  else if TypeFound then
    ATraits.TypeName := TypeInfo.Name;
  ATraits.ElementType := TPostfixTemplates.ElementOf(OwnerType);
  if (ATraits.ElementType = '') and TypeFound then
    ATraits.ElementType := TPostfixTemplates.ElementOf(TypeInfo.TypeName);
  ATraits.Enumerable := ATraits.ElementType <> '';
  if TypeFound and not TypeInfo.Builtin and (TypeInfo.SymbolKind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType]) then
    for Member in AMembers do
      if SameText(Member.Name, 'GetEnumerator') then
      begin
        ATraits.Enumerable := True;
        // Elementtyp für die klassische Schleife: Current des Enumerators.
        for Enumerator in AResolver.MemberCandidates(ATree, AFileName, AContext.Names + ['GetEnumerator'],
          AContext.Offset) do
          if SameText(Enumerator.Name, 'Current') then
            ATraits.ElementType := Enumerator.TypeName;
        Break;
      end;
  ATraits.IsString := TPostfixTemplates.IsStringType(Owner.TypeName) or
    (TypeFound and TypeInfo.Builtin and TPostfixTemplates.IsStringType(TypeInfo.Name));
  ATraits.IsBoolean := TPostfixTemplates.IsBooleanType(Owner.TypeName) or
    (TypeFound and TypeInfo.Builtin and TPostfixTemplates.IsBooleanType(TypeInfo.Name));
  ATraits.IsClass := TypeFound and not TypeInfo.Builtin and (TypeInfo.SymbolKind = TIndexSymbolKind.ClassType);
  ATraits.IsReference := ATraits.IsClass or
    (TypeFound and not TypeInfo.Builtin and (TypeInfo.SymbolKind = TIndexSymbolKind.InterfaceType)) or
    TPostfixTemplates.IsPointerType(Owner.TypeName) or
    (TypeFound and TPostfixTemplates.IsPointerType(TypeInfo.TypeName));
  Result := TypeFound or ATraits.Enumerable or ATraits.IsString or ATraits.IsReference;
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  const APostfix: TPostfixOptions): TCompletionItems;
begin
  Result := Collect(AResolver, AIndex, ATree, AFileName, AText, APosition, AMatching, APostfix, nil);
end;

class function TLspCompletion.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  const APostfix: TPostfixOptions; const AOnPartial: TCompletionPartialProc): TCompletionItems;
var
  Postfix: TArray<TCompletionItem>;
  // Gestaffelt (#616): schon gesendete Einträge und ihre Namen.
  Sent: Integer;
  SentNames: TDictionary<string, Boolean>;
  Truncated: Boolean;
  ImportsCapped: Boolean;
  Context: TCompletionContext;
  Candidates: TArray<TResolvedSymbol>;
  Units: TArray<TUnitIndex>;
  UnitInfo: TUnitIndex;
  List: TList<TScoredItem>;
  Scored: TScoredItem;
  SourceFile: string;
  SourcePosition: TTextPosition;
  OwnUnit: string;
  Member: TResolvedSymbol;
  Expected: string;
  Descends: TDictionary<string, Boolean>;
  AnyFits: Boolean;

  function MemberFits: Boolean;
  var
    TypeText: string;
    CheckDescent: Boolean;
  begin
    // Typ des Werts: Variablen, Felder, Eigenschaften, Funktionsergebnis; Aufzählungswerte über ihren Typ.
    if Member.SymbolKind = TIndexSymbolKind.EnumMember then
      TypeText := Member.Container
    else if Member.IsType then
      Exit(False)
    else
      TypeText := Member.TypeName;
    Result := TypeFits(TypeText, Expected, CheckDescent);
    if Result or not CheckDescent then
      Exit;
    // Klassen: Nachfahr des erwarteten Typs; je Typname einmal auflösen.
    if not Descends.TryGetValue(LowerCase(TypeText), Result) then
    begin
      Result := AResolver.TypeDescendsFrom(ATree, AFileName, Context.Offset, TypeText, Expected);
      Descends.Add(LowerCase(TypeText), Result);
    end;
  end;

  procedure AddPostfix;
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
    // Nur einzeilige Ausdrücke; der Typ muss bekannt sein.
    if (Context.ChainStart.Line <> APosition.Line) or (Context.DotPos.Line <> APosition.Line) or
      not PostfixTraits(AResolver, ATree, AFileName, Context, Candidates, Traits) then
      Exit;
    Traits.InFunction := InFunctionAt(ATree, AText, Context.Offset);
    LineText := LineOf(AText, APosition.Line);
    Before := Copy(LineText, 1, Context.ChainStart.Character);
    Indent := Copy(LineText, 1, Length(LineText) - Length(TrimLeft(LineText)));
    Expr := Copy(LineText, Context.ChainStart.Character + 1, Context.DotPos.Character - Context.ChainStart.Character);
    if Pos(#13#10, AText) > 0 then
      LineBreak := #13#10
    else
      LineBreak := #10;
    // Eigene Vorlagen mit Typname als Bedingung: der Typ selbst oder ein Nachfahr. Anonyme Methoden fangen nur
    // eigene Variablen ein, nicht die der umgebenden Routine.
    Resolver := AResolver;
    Tree := ATree;
    FileName := AFileName;
    Offset := Context.Offset;
    TypeName := Traits.TypeName;
    Descends :=
      function(ATypeName: string): Boolean
      begin
        Result := Resolver.TypeDescendsFrom(Tree, FileName, Offset, TypeName, ATypeName);
      end;
    for Template in TPostfixTemplates.Templates + APostfix.Custom do
    begin
      if not TPostfixTemplates.Applies(Template, Traits, APostfix.InlineVar, Descends) or
        (Template.Statement and (Trim(Before) <> '')) or
        (MatchScore(Template.Key, Context.Prefix, AMatching) = TFuzzyMatch.NoMatch) then
        Continue;
      Expansion := TPostfixTemplates.Expand(Template, Expr, Indent, LineBreak, Traits, APostfix.InlineVar,
        APostfix.Snippet);
      Item := Default(TCompletionItem);
      Item.Name := Template.Key;
      Item.Detail := Template.Description;
      Item.Kind := KindSnippet;
      // Der Editor filtert über "Ausdruck.Kürzel"; Atlas kennzeichnet den Eintrag als Postfix.
      Item.FilterText := Expr + '.' + Template.Key;
      Item.Action := 'postfix';
      Item.Snippet := APostfix.Snippet;
      Item.HasTextEdit := True;
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(Context.ChainStart, APosition), Expansion.Text);
      if Expansion.Declaration <> '' then
      begin
        // Ohne Inline-Variable: Deklaration in den var-Abschnitt der Routine.
        Slash := Default(TSlashContext);
        Slash.Text := AText;
        Slash.Line := APosition.Line;
        Slash.LineText := LineText;
        Source := TCommandSource.Create(Slash);
        try
          Routine := Source.RoutineAt;
          if Routine = nil then
            Continue;
          Item.AdditionalEdits := [AddLocal(Source, Routine, TSyntaxKind.VarSection, 'var', Expansion.Declaration)];
        finally
          Source.Free;
        end;
      end;
      Postfix := Postfix + [Item];
    end;
  end;

  procedure Add(const AName, ADetail: string; AKind: Integer; APenalty: Integer = 0;
    const AEdits: TArray<TRuleEdit> = nil);
  var
    Range: TTextRange;
    Params: string;
  begin
    Scored.Score := MatchScore(AName, Context.Prefix, AMatching);
    if Scored.Score = TFuzzyMatch.NoMatch then
      Exit;
    Dec(Scored.Score, APenalty);
    // Frisch beginnen: Scored wird wiederverwendet; sonst blieben z. B. HasTextEdit und
    // TextEdit stehen (oder Datenmüll) – im Plugin löschte das alles bis zum Wort.
    Scored.Item := Default(TCompletionItem);
    Scored.Item.Name := AName;
    Scored.Item.AdditionalEdits := AEdits;
    Scored.Item.Detail := ADetail;
    Scored.Item.Kind := AKind;
    Scored.Item.SourceFile := SourceFile;
    Scored.Item.SourcePosition := SourcePosition;
    Scored.Item.Container := Member.Container;
    Scored.Item.Depth := Member.Depth;
    Scored.Item.IsHelper := Member.IsHelper;
    Scored.Item.Overloads := nil;
    Scored.Item.HasParameters := Member.MaxArgs > 0;
    Scored.Item.Condition := Member.Condition;
    Scored.Item.Unavailable := False;
    // Bereichsstufe nur im Gültigkeitsbereich, nicht nach einem Punkt (#488).
    Scored.Item.Scope := 0;
    if (Context.Kind = TCompletionContextKind.Scope) and (Member.Name <> '') then
      if Member.Kind = TResolvedKind.Local then
      begin
        if Member.IsParameter then
          Scored.Item.Scope := 2
        else
          Scored.Item.Scope := 1;
      end
      else if Member.Container <> '' then
        Scored.Item.Scope := 3
      else if (OwnUnit <> '') and SameText(Member.UnitName, OwnUnit) then
        Scored.Item.Scope := 4
      else
      begin
        Scored.Item.Scope := 5;
        Scored.Item.UnitName := Member.UnitName;
      end;
    Scored.Item.Hides := Member.Hides;
    for Params in Member.VariantParams do
      if Params <> '' then
        Scored.Item.HasParameters := True;
    for Range in Member.Overloads do
      Scored.Item.Overloads := Scored.Item.Overloads + [Range.StartPos];
    // Der Editor filtert selbst nach dem getippten Wort; unscharfe Treffer bekommen es
    // als filterText, damit er sie nicht verwirft.
    if (AMatching = TCompletionMatching.Fuzzy) and not AName.StartsWith(Context.Prefix, True) then
      Scored.Item.FilterText := Context.Prefix
    else
      Scored.Item.FilterText := '';
    // Erwarteter Typ (#417): Atlas gruppiert nach Fits.
    Scored.Item.Expected := Expected;
    Scored.Item.Fits := (Expected <> '') and (Member.Name <> '') and MemberFits;
    if Scored.Item.Fits then
      AnyFits := True;
    Scored.Order := List.Count;
    List.Add(Scored);
  end;

  /// <summary>Deklarationen der eigenen und eingebundener Units, die nur unter anderen Bedingungen
  /// existieren (#476): ans Ende, mit Bedingung und als nicht verfügbar markiert.</summary>
  /// <summary>Einträge aus der eigenen Datei: Der Baum des Editors kennt keine {$IFDEF}-Zweige.
  /// Bedingung und Verfügbarkeit kommen aus dem Index dieser Unit, der mit Präprozessor gelesen ist (#476).</summary>
  procedure MarkOwnConditions;
  var
    Own: TUnitIndex;
    Conditions: TDictionary<string, string>;
    Missing: TDictionary<string, string>;
    Symbol: TIndexSymbol;
    Index: Integer;
    Condition: string;
  begin
    if (AIndex = nil) or not AIndex.FindFile(AFileName, Own) then
      Exit;
    Conditions := TDictionary<string, string>.Create;
    Missing := TDictionary<string, string>.Create;
    try
      for Symbol in Own.Symbols do
        if (Symbol.Container = '') and (Symbol.Condition <> '') then
          Conditions.AddOrSetValue(UpperCase(Symbol.Name), Symbol.Condition);
      for Symbol in Own.Unavailable do
        if Symbol.Container = '' then
          Missing.AddOrSetValue(UpperCase(Symbol.Name), Symbol.Condition);
      if (Conditions.Count = 0) and (Missing.Count = 0) then
        Exit;
      for Index := 0 to List.Count - 1 do
      begin
        Scored := List[Index];
        // Nur Einträge aus dieser Datei; gleichnamige aus anderen Units bleiben unberührt.
        if (Scored.Item.Condition <> '') or ((Scored.Item.SourceFile <> '') and
          not SameText(Scored.Item.SourceFile, AFileName)) then
          Continue;
        if Missing.TryGetValue(UpperCase(Scored.Item.Name), Condition) then
        begin
          Scored.Item.Condition := Condition;
          Scored.Item.Unavailable := True;
          // Wie die übrigen nicht verfügbaren Einträge ans Ende.
          Dec(Scored.Score, 500);
        end
        else if Conditions.TryGetValue(UpperCase(Scored.Item.Name), Condition) then
          Scored.Item.Condition := Condition
        else
          Continue;
        List[Index] := Scored;
      end;
    finally
      Missing.Free;
      Conditions.Free;
    end;
  end;

  procedure AddUnavailable;
  var
    Known: TDictionary<string, Boolean>;
    Used: TArray<string>;
    Own: string;
    Existing: TScoredItem;
    UnitInfo: TUnitIndex;
    Symbol: TIndexSymbol;
    Before: Integer;
  begin
    Known := TDictionary<string, Boolean>.Create;
    try
      for Existing in List do
        Known.AddOrSetValue(UpperCase(Existing.Item.Name), True);
      for Own in SentNames.Keys do
        Known.AddOrSetValue(Own, True);
      Used := TUsesClauses.UsedUnits(ATree.Tokens);
      Own := TUsesClauses.OwnName(ATree.Tokens);
      for UnitInfo in AIndex.Units do
      begin
        if Length(UnitInfo.Unavailable) = 0 then
          Continue;
        if not SameText(UnitInfo.UnitName, Own) and
          not TUsesClauses.IsUsed(Used, UnitInfo.UnitName, AResolver.Namespaces) then
          Continue;
        for Symbol in UnitInfo.Unavailable do
        begin
          // Mitglieder nicht geltender Zweige zeigt AddUnavailableMembers hinter "Objekt.".
          if (Symbol.Container <> '') or (not Symbol.InInterface and not SameText(UnitInfo.UnitName, Own)) or
            Known.ContainsKey(UpperCase(Symbol.Name)) or
            ((Context.Filter = TCompletionFilter.Types) and not (Symbol.Kind in IndexTypeKinds)) then
            Continue;
          Member := Default(TResolvedSymbol);
          Member.Name := Symbol.Name;
          Member.Condition := Symbol.Condition;
          SourceFile := UnitInfo.FileName;
          SourcePosition := Symbol.SelectionRange.StartPos;
          Before := List.Count;
          Add(Symbol.Name, UnitInfo.UnitName, KindOf(Symbol.Kind), 500);
          if List.Count > Before then
          begin
            Scored := List[List.Count - 1];
            Scored.Item.Unavailable := True;
            List[List.Count - 1] := Scored;
            Known.AddOrSetValue(UpperCase(Symbol.Name), True);
          end;
        end;
      end;
    finally
      Known.Free;
      SourceFile := '';
      Member := Default(TResolvedSymbol);
    end;
  end;

  procedure AddFromOtherUnits;
  var
    Known: TDictionary<string, Boolean>;
    Used: TArray<string>;
    Own: string;
    Existing: TScoredItem;
    // Lokal: Eine for-Schleifenvariable darf nicht aus der äußeren Routine stammen (E1019).
    UnitInfo: TUnitIndex;
    Symbol: TIndexSymbol;
    Edit: TRuleEdit;
    Added, Before: Integer;
    Names: TImportNameIndex;
    Entry: TImportNameEntry;
    QueryMask: UInt64;
    // Je Unit: 0 = noch nicht geprüft, 1 = überspringen (eigene oder schon eingebunden), 2 = vorschlagen.
    UnitState: TArray<Byte>;
  begin
    Known := TDictionary<string, Boolean>.Create;
    try
      for Existing in List do
        Known.AddOrSetValue(UpperCase(Existing.Item.Name), True);
      for Own in SentNames.Keys do
        Known.AddOrSetValue(Own, True);
      Used := TUsesClauses.UsedUnits(ATree.Tokens);
      Own := TUsesClauses.OwnName(ATree.Tokens);
      Added := 0;
      // Projekt-Units vor der Bibliothek: Sonst füllen RTL/VCL die Höchstzahl, bevor eine
      // gerade getippte Klasse aus dem eigenen Projekt drankommt (#492). Der Namensindex (#617)
      // ist schon so sortiert und enthält nur importierbare Symbole; die Zeichenmaske spart den
      // unscharfen Vergleich für fast alle Namen.
      Names := TImportNames.Current(AIndex);
      QueryMask := TImportNameIndex.MaskOf(Context.Prefix);
      SetLength(UnitState, Length(Names.Units));
      for Entry in Names.Entries do
      begin
        if not TImportNameIndex.MayMatch(Entry.Mask, QueryMask) then
          Continue;
        if UnitState[Entry.UnitPos] = 0 then
        begin
          UnitInfo := Names.Units[Entry.UnitPos];
          if SameText(UnitInfo.UnitName, Own) or TUsesClauses.IsUsed(Used, UnitInfo.UnitName, AResolver.Namespaces) then
            UnitState[Entry.UnitPos] := 1
          else
            UnitState[Entry.UnitPos] := 2;
        end;
        if UnitState[Entry.UnitPos] = 1 then
          Continue;
        UnitInfo := Names.Units[Entry.UnitPos];
        Symbol := UnitInfo.Symbols[Entry.SymbolPos];
        if Known.ContainsKey(UpperCase(Symbol.Name)) or
          ((Context.Filter = TCompletionFilter.Types) and not (Symbol.Kind in IndexTypeKinds)) then
          Continue;
        if MatchScore(Symbol.Name, Context.Prefix, AMatching) = TFuzzyMatch.NoMatch then
          Continue;
        if not TUsesClauses.AddUnit(ATree.Tokens, Context.Offset, UnitInfo.UnitName, #13#10, Edit) then
          Exit;
        Before := List.Count;
        // Add liest Member und Quelle: für den Import aus dem Indexsymbol, nicht vom vorigen
        // Eintrag (sonst fehlten z. B. die Klammern bei ShowMessage aus Vcl.Dialogs).
        Member := Default(TResolvedSymbol);
        Member.Name := Symbol.Name;
        Member.MinArgs := Symbol.MinArgs;
        Member.MaxArgs := Symbol.MaxArgs;
        SourceFile := UnitInfo.FileName;
        SourcePosition := Symbol.SelectionRange.StartPos;
        // Eingebundenes zuerst, dann Projekt-Units, dann RTL/VCL und andere Bibliotheken.
        if UnitInfo.Library_ then
          Add(Symbol.Name, UnitInfo.UnitName + ' (uses ergänzen)', KindOf(Symbol.Kind), 200, [Edit])
        else
          Add(Symbol.Name, UnitInfo.UnitName + ' (uses ergänzen)', KindOf(Symbol.Kind), 100, [Edit]);
        // Gleichnamige Symbole verschiedener Units bleiben alle wählbar.
        if List.Count > Before then
        begin
          Inc(Added);
          if Added >= MaxImportItems then
          begin
            ImportsCapped := True;
            Exit;
          end;
        end;
      end;
    finally
      Known.Free;
    end;
  end;

  /// <summary>Sortiert die gesammelten Einträge, kürzt auf den Rest von MaxItems und leert die Liste.
  /// AStaged: Teilergebnis; dann bleibt Expected stehen, weil spätere Stufen noch passende Einträge bringen
  /// können (Atlas gruppiert erst, wenn einer passt).</summary>
  function TakeStage(AStaged: Boolean): TArray<TCompletionItem>;
  var
    Room: Integer;
    // Lokal: Schleifenvariablen dürfen nicht aus der äußeren Routine stammen (E1019).
    Index: Integer;
    Scored: TScoredItem;
  begin
    MarkOwnConditions;
    List.Sort;
    // Passende zuerst (#417); passt nichts, entfällt die Gruppierung.
    if AnyFits then
    begin
      for Index := 0 to List.Count - 1 do
      begin
        Scored := List[Index];
        Scored.Order := Index + IfThen(Scored.Item.Fits, 0, List.Count);
        List[Index] := Scored;
      end;
      List.Sort(TComparer<TScoredItem>.Construct(
        function(const Left, Right: TScoredItem): Integer
        begin
          Result := Left.Order - Right.Order;
        end));
    end
    else if not AStaged then
      for Index := 0 to List.Count - 1 do
      begin
        Scored := List[Index];
        Scored.Item.Expected := '';
        List[Index] := Scored;
      end;
    Room := Max(0, MaxItems - Sent);
    if List.Count > Room then
    begin
      Truncated := True;
      List.Count := Room;
    end;
    SetLength(Result, List.Count);
    for Index := 0 to List.Count - 1 do
    begin
      Result[Index] := List[Index].Item;
      SentNames.AddOrSetValue(UpperCase(List[Index].Item.Name), True);
    end;
    Inc(Sent, List.Count);
    List.Clear;
  end;

  /// <summary>Teilergebnis senden (#616); ohne AOnPartial bleibt alles für das Ergebnis liegen.</summary>
  procedure SendStage;
  var
    Items: TArray<TCompletionItem>;
  begin
    if not Assigned(AOnPartial) or (List.Count = 0) then
      Exit;
    Items := TakeStage(True);
    if Length(Items) > 0 then
      AOnPartial(Items);
  end;

  procedure SetNameFilter(AOn: Boolean);
  begin
    if AOn and (Context.Prefix <> '') then
      AResolver.NameFilter := PrefixFilter(Context.Prefix, AMatching)
    else
      AResolver.NameFilter := nil;
  end;

  /// <summary>Namen des eigenen Bereichs, die gleichnamige Deklarationen aus uses verdecken (#488): vor dem
  /// Senden der ersten Stufe vermerken, die zweite bringt diese Namen nicht mehr.</summary>
  procedure MarkUsedShadows;
  var
    Names: TDictionary<string, Integer>;
    Shadows: TArray<TResolvedSymbol>;
    Shadow: TResolvedSymbol;
    Index: Integer;
    Text: string;
  begin
    Names := TDictionary<string, Integer>.Create;
    try
      for Index := 0 to List.Count - 1 do
        if (List[Index].Item.Scope >= 1) and (List[Index].Item.Scope <= 4) then
          Names.AddOrSetValue(UpperCase(List[Index].Item.Name), Index);
      if Names.Count = 0 then
        Exit;
      AResolver.NameFilter :=
        function(const AName: string): Boolean
        begin
          Result := Names.ContainsKey(UpperCase(AName));
        end;
      try
        Shadows := AResolver.UsedScopeShadows;
      finally
        AResolver.NameFilter := nil;
      end;
      for Shadow in Shadows do
        if Names.TryGetValue(UpperCase(Shadow.Name), Index) then
        begin
          Scored := List[Index];
          Text := TNameResolver.ShadowText(Shadow);
          if not MatchText(Text, Scored.Item.Hides) then
          begin
            Scored.Item.Hides := Scored.Item.Hides + [Text];
            List[Index] := Scored;
          end;
        end;
    finally
      Names.Free;
    end;
  end;

  /// <summary>Schlüsselwörter passend zur Stelle (#31), erst ab einem getippten Zeichen; ohne Eingabe gingen die
  /// Namen darin unter.</summary>
  procedure AddKeywords;
  var
    Words: TArray<string>;
    Word: string;
  begin
    if Context.Prefix = '' then
      Exit;
    if Context.Filter = TCompletionFilter.Types then
    begin
      if not Context.TypeKeywords then
        Exit;
      Words := nil;
      for Word in TypeKeywords do
        Words := Words + [Word];
    end
    else
      Words := Keywords(Context.Place);
    Member := Default(TResolvedSymbol);
    SourceFile := '';
    SourcePosition := Default(TTextPosition);
    for Word in Words do
      Add(Word, '', KindKeyword, 50);
  end;

  // Mitglieder aus nicht geltenden Zweigen der Typen, deren Mitglieder AMembers schon zeigt (#476):
  // abgeschwächt am Ende, wie die übrigen nicht verfügbaren Einträge.
  procedure AddUnavailableMembers(const AMembers: TArray<TResolvedSymbol>);
  var
    Containers, Known: TDictionary<string, Boolean>;
    Candidate: TResolvedSymbol;
    UnitInfo: TUnitIndex;
    Symbol: TIndexSymbol;
    Existing: TScoredItem;
    Before: Integer;
  begin
    Containers := TDictionary<string, Boolean>.Create;
    Known := TDictionary<string, Boolean>.Create;
    try
      for Candidate in AMembers do
        if Candidate.Container <> '' then
          Containers.AddOrSetValue(UpperCase(Candidate.Container), True);
      if Containers.Count = 0 then
        Exit;
      for Existing in List do
        Known.AddOrSetValue(UpperCase(Existing.Item.Name), True);
      for UnitInfo in AIndex.Units do
        for Symbol in UnitInfo.Unavailable do
        begin
          if (Symbol.Container = '') or not Containers.ContainsKey(UpperCase(Symbol.Container)) or
            Known.ContainsKey(UpperCase(Symbol.Name)) then
            Continue;
          Member := Default(TResolvedSymbol);
          Member.Name := Symbol.Name;
          Member.Container := Symbol.Container;
          Member.Condition := Symbol.Condition;
          SourceFile := UnitInfo.FileName;
          SourcePosition := Symbol.SelectionRange.StartPos;
          Before := List.Count;
          Add(Symbol.Name, Symbol.Container, KindOf(Symbol.Kind), 500);
          if List.Count > Before then
          begin
            Scored := List[List.Count - 1];
            Scored.Item.Unavailable := True;
            List[List.Count - 1] := Scored;
            Known.AddOrSetValue(UpperCase(Symbol.Name), True);
          end;
        end;
    finally
      Known.Free;
      Containers.Free;
      SourceFile := '';
      Member := Default(TResolvedSymbol);
    end;
  end;

  procedure AddCandidates(const ACandidates: TArray<TResolvedSymbol>);
  var
    Candidate: TResolvedSymbol;
  begin
    for Candidate in ACandidates do
    begin
      // Typposition (#31): nur Typen.
      if (Context.Filter = TCompletionFilter.Types) and not Candidate.IsType then
        Continue;
      // Wo die Deklaration steht, für completionItem/resolve.
      SourceFile := Candidate.FileName;
      SourcePosition := Candidate.SelectionRange.StartPos;
      Member := Candidate;
      if Candidate.TypeName <> '' then
        Add(Candidate.Name, Candidate.TypeName, KindOf(Candidate.SymbolKind))
      else if Candidate.Container <> '' then
        Add(Candidate.Name, Candidate.Container, KindOf(Candidate.SymbolKind))
      else
        Add(Candidate.Name, Candidate.UnitName, KindOf(Candidate.SymbolKind));
    end;
    SourceFile := '';
    Member := Default(TResolvedSymbol);
  end;

begin
  Result := Default(TCompletionItems);
  Postfix := nil;
  Sent := 0;
  Truncated := False;
  ImportsCapped := False;
  Context := Analyze(ATree, APosition);
  // Diagnoselog (#647): nur Art und Längen, nie die Namen selbst.
  TRequestDiagnostics.Note('ctx', ContextCodes[Context.Kind]);
  TRequestDiagnostics.Note('prefixLen', Length(Context.Prefix));
  if Context.Kind = TCompletionContextKind.Member then
    TRequestDiagnostics.Note('chainLen', Length(Context.Names))
  else if Context.Kind = TCompletionContextKind.None then
    TRequestDiagnostics.Reason('noContext');
  // Name der eigenen Unit für die Bereichsstufe (#488).
  OwnUnit := '';
  if ATree <> nil then
    OwnUnit := TUsesClauses.OwnName(ATree.Tokens);
  SourceFile := '';
  SourcePosition := Default(TTextPosition);
  Member := Default(TResolvedSymbol);
  Expected := '';
  AnyFits := False;
  if Context.Kind in [TCompletionContextKind.Member, TCompletionContextKind.Scope] then
    Expected := ExpectedType(AResolver, ATree, AFileName, APosition);
  // Viele Typprüfungen auf demselben Baum: einmal auswerten.
  if Expected <> '' then
    AResolver.PinTree(ATree, AFileName);
  Descends := TDictionary<string, Boolean>.Create;
  SentNames := TDictionary<string, Boolean>.Create;
  List := TList<TScoredItem>.Create(TScoredItemComparer.Create);
  try
    case Context.Kind of
      TCompletionContextKind.UsesClause:
        begin
          Units := AIndex.Units;
          for UnitInfo in Units do
            Add(UnitInfo.UnitName, UnitInfo.FileName, KindModule);
        end;
      TCompletionContextKind.Member, TCompletionContextKind.Scope:
        begin
          // Nur passende Namen aufbauen (#616); ohne Eingabe passt ohnehin alles. Der Filter gilt nur beim
          // Sammeln, nicht für die Typprüfungen in Add.
          if Context.Kind = TCompletionContextKind.Member then
          begin
            // AddPostfix braucht die Mitglieder (GetEnumerator).
            SetNameFilter(True);
            try
              Candidates := AResolver.MemberCandidates(ATree, AFileName, Context.Names, Context.Offset);
            finally
              SetNameFilter(False);
            end;
            AddCandidates(Candidates);
            AddUnavailableMembers(Candidates);
          end
          else if Context.Filter = TCompletionFilter.InheritedCall then
          begin
            // Nach "inherited " nur Methoden der Vorfahren (#31).
            SetNameFilter(True);
            try
              Candidates := AResolver.InheritedCandidates(ATree, AFileName, Context.Offset);
            finally
              SetNameFilter(False);
            end;
            AddCandidates(Candidates);
          end
          else
          begin
            // Eigener Gültigkeitsbereich zuerst (#616): lokal, Self, eigene Unit; dann die Units aus uses.
            SetNameFilter(True);
            try
              Candidates := AResolver.OwnScopeCandidates(ATree, AFileName, Context.Offset);
            finally
              SetNameFilter(False);
            end;
            AddCandidates(Candidates);
            MarkUsedShadows;
            SendStage;
            SetNameFilter(True);
            try
              Candidates := AResolver.UsedScopeCandidates;
            finally
              SetNameFilter(False);
            end;
            AddCandidates(Candidates);
          end;
          if (Context.Kind = TCompletionContextKind.Scope) and
            (Context.Filter <> TCompletionFilter.InheritedCall) then
          begin
            // Danach die nicht eingebundenen Units.
            SendStage;
            if Length(Context.Prefix) >= MinImportPrefix then
              AddFromOtherUnits;
            AddUnavailable;
            AddKeywords;
          end;
          // Postfix-Vorlagen stehen immer hinter den echten Mitgliedern.
          if (Context.Kind = TCompletionContextKind.Member) and APostfix.Enabled and (AText <> '') then
            AddPostfix;
        end;
    end;
    Result.Items := TakeStage(Sent > 0);
    // Unvollständig nur, wenn beim Weitertippen etwas dazukommen kann (#616): gekürzt, Importe gekappt oder
    // noch nicht gesucht (zu kurzer Name). Sonst filtert der Editor selbst weiter.
    Result.Incomplete := Truncated or ImportsCapped or
      ((Context.Kind = TCompletionContextKind.Scope) and (Length(Context.Prefix) < MinImportPrefix));
    Result.Items := Result.Items + Postfix;
  finally
    List.Free;
    SentNames.Free;
    Descends.Free;
    if Expected <> '' then
      AResolver.UnpinTree;
  end;
end;

class function TLspCompletion.ToJson(const AItems: TCompletionItems): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('isIncomplete', TJSONBool.Create(AItems.Incomplete));
  Result.AddPair('items', ToJson(AItems.Items, 0));
end;

class function TLspCompletion.ToJson(const AItems: TArray<TCompletionItem>; AFirstSort: Integer): TJSONArray;
var
  Edits, Overloads: TJSONArray;
  Entry, EditJson, Data: TJSONObject;
  Edit: TRuleEdit;
  Index: Integer;
  Position: TTextPosition;
  Text: string;
begin
  Result := TJSONArray.Create;
  for Index := 0 to High(AItems) do
  begin
    Entry := TJSONObject.Create;
    Result.AddElement(Entry);
    Entry.AddPair('label', AItems[Index].Name);
    Entry.AddPair('kind', TJSONNumber.Create(AItems[Index].Kind));
    if AItems[Index].Detail <> '' then
      Entry.AddPair('detail', AItems[Index].Detail);
    if AItems[Index].FilterText <> '' then
      Entry.AddPair('filterText', AItems[Index].FilterText);
    if AItems[Index].HasTextEdit then
    begin
      EditJson := TJSONObject.Create;
      Entry.AddPair('textEdit', EditJson);
      EditJson.AddPair('range', TLspPositions.RangeToJson(AItems[Index].TextEdit.Range));
      EditJson.AddPair('newText', AItems[Index].TextEdit.NewText);
    end
    else if AItems[Index].InsertText <> '' then
      Entry.AddPair('insertText', AItems[Index].InsertText);
    // Code-Vorlagen mit Platzhaltern (#51): InsertTextFormat.Snippet.
    if AItems[Index].Snippet then
      Entry.AddPair('insertTextFormat', TJSONNumber.Create(2));
    if Length(AItems[Index].AdditionalEdits) > 0 then
    begin
      Edits := TJSONArray.Create;
      Entry.AddPair('additionalTextEdits', Edits);
      for Edit in AItems[Index].AdditionalEdits do
      begin
        EditJson := TJSONObject.Create;
        Edits.AddElement(EditJson);
        EditJson.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
        EditJson.AddPair('newText', Edit.NewText);
      end;
    end;
    // Reihenfolge wie geliefert: beste Punktzahl, dann nächster Gültigkeitsbereich.
    Entry.AddPair('sortText', Format('%.5d', [AFirstSort + Index]));
    if (AItems[Index].SourceFile <> '') or (AItems[Index].Expected <> '') or
      (AItems[Index].Action <> '') or (AItems[Index].Condition <> '') or
      (AItems[Index].Scope > 0) or (AItems[Index].Ordinal > 0) or AItems[Index].Pinned or AItems[Index].Hint or
      (AItems[Index].Form <> '') or (AItems[Index].Sender <> '') or (AItems[Index].DataSet <> '') or
      (AItems[Index].Guard <> '') then
    begin
      Data := TJSONObject.Create;
      if AItems[Index].SourceFile <> '' then
      begin
        Data.AddPair('file', AItems[Index].SourceFile);
        Data.AddPair('line', TJSONNumber.Create(AItems[Index].SourcePosition.Line));
        Data.AddPair('character', TJSONNumber.Create(AItems[Index].SourcePosition.Character));
      end;
      if AItems[Index].Expected <> '' then
      begin
        Data.AddPair('expected', AItems[Index].Expected);
        Data.AddPair('fits', TJSONBool.Create(AItems[Index].Fits));
      end;
      if AItems[Index].Action <> '' then
        Data.AddPair('action', AItems[Index].Action);
      // Für die Atlas-Oberfläche: Herkunft, Vererbungstiefe, Helper, Überladungen (#419, #425, #456).
      if AItems[Index].Container <> '' then
        Data.AddPair('container', AItems[Index].Container);
      if AItems[Index].Depth > 0 then
        Data.AddPair('depth', TJSONNumber.Create(AItems[Index].Depth));
      if AItems[Index].IsHelper then
        Data.AddPair('helper', TJSONBool.Create(True));
      if AItems[Index].HasParameters then
        Data.AddPair('parameters', TJSONBool.Create(True));
      // Bedingte Deklarationen (#476).
      if AItems[Index].Condition <> '' then
        Data.AddPair('condition', AItems[Index].Condition);
      if AItems[Index].Unavailable then
        Data.AddPair('unavailable', TJSONBool.Create(True));
      if AItems[Index].Scope > 0 then
        Data.AddPair('scope', TJSONNumber.Create(AItems[Index].Scope));
      // Aufzählungen und Mengen (#448).
      if AItems[Index].Ordinal > 0 then
        Data.AddPair('ordinal', TJSONNumber.Create(AItems[Index].Ordinal));
      if AItems[Index].SetOf <> '' then
      begin
        Data.AddPair('setOf', AItems[Index].SetOf);
        Data.AddPair('checked', TJSONBool.Create(AItems[Index].SetChecked));
        Data.AddPair('setRange', TLspPositions.RangeToJson(AItems[Index].SetRange));
      end;
      // case vervollständigen (#449).
      if AItems[Index].Pinned then
        Data.AddPair('pinned', TJSONBool.Create(True));
      if AItems[Index].Count > 0 then
        Data.AddPair('count', TJSONNumber.Create(AItems[Index].Count));
      // Unbekannter Name (#471).
      if AItems[Index].Unknown <> '' then
        Data.AddPair('unknown', AItems[Index].Unknown);
      // Interface implementieren (#466).
      if AItems[Index].Batch then
        Data.AddPair('batch', TJSONBool.Create(True));
      if AItems[Index].Hint then
        Data.AddPair('hint', TJSONBool.Create(True));
      // Komponenten aus dem Formular (#455).
      if AItems[Index].Form <> '' then
        Data.AddPair('form', AItems[Index].Form);
      if AItems[Index].ByType then
        Data.AddPair('byType', TJSONBool.Create(True));
      // Sender mit Typumwandlung (#480).
      if AItems[Index].Sender <> '' then
      begin
        Data.AddPair('sender', AItems[Index].Sender);
        Data.AddPair('senderOf', AItems[Index].SenderOf);
      end;
      // Feld- und Parameternamen (#461).
      if AItems[Index].DataSet <> '' then
      begin
        Data.AddPair('dataSet', AItems[Index].DataSet);
        if AItems[Index].DataSource <> '' then
          Data.AddPair('dataSource', AItems[Index].DataSource);
      end;
      // Freigabe absichern (#489).
      if AItems[Index].Guard <> '' then
        Data.AddPair('guard', AItems[Index].Guard);
      if AItems[Index].UnitName <> '' then
        Data.AddPair('unit', AItems[Index].UnitName);
      if Length(AItems[Index].Hides) > 0 then
      begin
        Overloads := TJSONArray.Create;
        Data.AddPair('hides', Overloads);
        for Text in AItems[Index].Hides do
          Overloads.Add(Text);
      end;
      if Length(AItems[Index].Overloads) > 0 then
      begin
        Overloads := TJSONArray.Create;
        Data.AddPair('overloads', Overloads);
        for Position in AItems[Index].Overloads do
          Overloads.AddElement(TJSONObject.Create.AddPair('line', TJSONNumber.Create(Position.Line))
            .AddPair('character', TJSONNumber.Create(Position.Character)));
      end;
      Entry.AddPair('data', Data);
    end;
  end;
end;

/// <summary>AItems ohne die Namen aus ANames (#448: Aufzählungswerte, die schon vorab kamen).</summary>
/// <summary>AItems ohne die Schlüsselwörter aus AddKeywords (#31).</summary>
function WithoutKeywords(const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  Item: TCompletionItem;
begin
  Result := nil;
  for Item in AItems do
    if Item.Kind <> KindKeyword then
      Result := Result + [Item];
end;

function WithoutNames(const AItems, ANames: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  Names: TDictionary<string, Boolean>;
  Item: TCompletionItem;
  Count: Integer;
begin
  if Length(ANames) = 0 then
    Exit(AItems);
  Names := TDictionary<string, Boolean>.Create;
  try
    for Item in ANames do
      Names.AddOrSetValue(LowerCase(Item.Name), True);
    SetLength(Result, Length(AItems));
    Count := 0;
    for Item in AItems do
      if not Names.ContainsKey(LowerCase(Item.Name)) then
      begin
        Result[Count] := Item;
        Inc(Count);
      end;
    SetLength(Result, Count);
  finally
    Names.Free;
  end;
end;

function TLspCompletion.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Matching: TCompletionMatching;
  Directives, Overrides, Events: TCompletionItems;
  Postfix: TPostfixOptions;
  Disabled: TArray<string>;
  Token: string;
  Cancel: IJsonRpcCancellationToken;
  Notify: TCompletionNotifyProc;
  Partial: TCompletionPartialProc;
  SentCount: Integer;
  Collected: TCompletionItems;
  Watch: TStopwatch;
  ParseMs: Int64;
  Enums: TArray<TCompletionItem>;
  SetMode: Boolean;
  Trigger: string;
  Position: TTextPosition;
  EnumParams: TJSONObject;
  Declares: TArray<TCompletionItem>;
  Hints: TArray<TCompletionItem>;
  Components: TArray<TCompletionItem>;
  Senders: TCompletionItems;
  GuardTrigger: string;
  Batch: Boolean;
  Settings: TCompletionSettings;
begin
  Watch := TStopwatch.StartNew;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  if not FStore.TryGet(Uri, Document) then
  begin
    TRequestDiagnostics.Reason('documentNotOpen');
    Exit(TJSONNull.Create);
  end;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Disabled := nil;
  if (not Assigned(FSlashCommandsFor) or FSlashCommandsFor(Uri, Disabled)) and
    SlashItems(Document.Text, TLspPositions.ReadPosition(PositionValue), Disabled, Directives) then
    Exit(ToJson(Directives));
  if DirectiveItems(Document.Text, TLspPositions.ReadPosition(PositionValue), Directives) then
    Exit(ToJson(Directives));
  // Feld- und Parameternamen im String-Literal (#461).
  if DataNameItems(FIndex, Document.Text, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue), FReadText,
    Directives) then
    Exit(ToJson(Directives));
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  ParseMs := Watch.ElapsedMilliseconds;
  TRequestDiagnostics.Note('treeMs', Integer(ParseMs));
  TRequestDiagnostics.Note('syntaxErr', Length(Tree.Diagnostics));
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := FNamespaces;
    if Assigned(FSettingsFor) then
      Settings := FSettingsFor(Uri)
    else
      Settings := TCompletionSettings.Default;
    // Freigabe absichern (#489): Das Plugin fragt nach dem ";" bzw. dem Zeilenende (#10) hinter einem übernommenen
    // Konstruktor mit diesem Auslöser; dann gibt es nur dieses Angebot oder nichts.
    if TJSONObject(AParams).TryGetValue<string>('context.triggerCharacter', GuardTrigger) and
      ((GuardTrigger = ';') or (GuardTrigger = #10)) then
    begin
      if not (Settings.OfferTryFinally and GuardItems(Resolver, Tree, Document.Text, TDocumentUris.ToPath(Uri),
        TLspPositions.ReadPosition(PositionValue), Settings.FreeStyle, GuardTrigger = #10, Senders)) then
        Senders := Default(TCompletionItems);
      Exit(ToJson(Senders));
    end;
    if Assigned(FMatchingFor) then
      Matching := FMatchingFor(Uri)
    else
      Matching := TCompletionMatching.Fuzzy;
    // Methoden überschreiben (#443) vor der allgemeinen Vervollständigung.
    if OverrideItems(Resolver, Tree, Document.Text, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
      FReadText, Overrides) then
      Exit(ToJson(Overrides));
    // Property-Zugriffe (#31): nach read bzw. write nur passende Felder und Methoden.
    if PropertyItems(Resolver, Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue), Matching, Overrides) then
      Exit(ToJson(Overrides));
    // Ereignis-Zuweisung (#444).
    if EventItems(Resolver, Tree, Document.Text, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
      FReadText, Events) then
      Exit(ToJson(Events));
    // Interface implementieren (#466): auf leerer Zeile der Klasse nur die fehlenden Methoden mit
    // Kontrollkästchen; bei angefangenem Wort ein Hinweis oben in der normalen Liste.
    if not InterfaceItems(Resolver, Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue), FReadText, Settings.InterfaceSection, Hints, Batch) then
      Hints := nil
    else if Batch then
    begin
      Collected := Default(TCompletionItems);
      Collected.Items := Hints;
      Exit(ToJson(Collected));
    end;
    // Aufzählungen und Mengen (#448): im Mengenkonstruktor nur dessen Werte; sonst die Werte des erwarteten
    // Aufzählungstyps vor der übrigen Liste. Atlas fragt bei "[" mit triggerCharacter: ohne Menge nichts.
    Position := TLspPositions.ReadPosition(PositionValue);
    Trigger := '';
    TJSONObject(AParams).TryGetValue<string>('context.triggerCharacter', Trigger);
    if not EnumItems(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri), Position, FReadText, Matching,
      Enums, SetMode) then
      Enums := nil;
    if SetMode or (Trigger = '[') then
    begin
      Collected := Default(TCompletionItems);
      if SetMode then
        Collected.Items := Enums;
      Exit(ToJson(Collected));
    end;
    // Komponenten aus dem Formular (#455) wie die Aufzählungswerte vorab und vor der übrigen Liste.
    if ComponentItems(Resolver, Tree, Document.Text, TDocumentUris.ToPath(Uri), Position, FReadText, Matching,
      Components) then
      Enums := Enums + Components;
    if Assigned(FPostfixFor) then
      Postfix := FPostfixFor(Uri)
    else
      Postfix := TPostfixOptions.Default;
    Postfix.Snippet := FSnippetSupport;
    Postfix.Custom := CustomPostfix;
    // Gestaffelt (#616), wenn der Client einen partialResultToken mitschickt: Teilergebnisse als $/progress
    // mit CompletionItem[], der Rest in der Antwort. Zwischen den Stufen bricht eine veraltete Anfrage ab.
    Token := '';
    Partial := nil;
    SentCount := 0;
    if Assigned(FNotify) and (TJSONObject(AParams).GetValue('partialResultToken') is TJSONString) then
      Token := TJSONString(TJSONObject(AParams).GetValue('partialResultToken')).Value;
    if Token <> '' then
    begin
      Cancel := ACancellation;
      Notify := FNotify;
      Partial :=
        procedure(const AItems: TArray<TCompletionItem>)
        var
          Params: TJSONObject;
          Items: TArray<TCompletionItem>;
        begin
          Cancel.ThrowIfCancellationRequested;
          // Die Werte der Aufzählung kamen schon vorab (#448).
          Items := WithoutNames(AItems, Enums);
          if Length(Items) = 0 then
            Exit;
          Params := TJSONObject.Create;
          Params.AddPair('token', Token);
          Params.AddPair('value', ToJson(Items, SentCount));
          Inc(SentCount, Length(Items));
          Notify('$/progress', Params);
        end;
      // Aufzählungswerte zuerst (#448).
      if Length(Enums) > 0 then
      begin
        EnumParams := TJSONObject.Create;
        EnumParams.AddPair('token', Token);
        EnumParams.AddPair('value', ToJson(Enums, SentCount));
        Inc(SentCount, Length(Enums));
        Notify('$/progress', EnumParams);
      end;
    end;
    // Sender mit Typumwandlung (#480): statt der Mitglieder von TObject die des zugewiesenen Komponententyps.
    if SenderItems(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri), Position, FReadText, Matching,
      Settings.SenderCast, Senders) then
      Exit(ToJson(Senders));
    Collected := Collect(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), Document.Text,
      TLspPositions.ReadPosition(PositionValue), Matching, Postfix, Partial);
    Collected.Items := WithoutNames(Collected.Items, Enums);
    // Schlüsselwörter abschaltbar (#31, completion.keywords).
    if not Settings.Keywords then
      Collected.Items := WithoutKeywords(Collected.Items);
    // Kontextabhängige Code-Vorlagen (#51) am Ende der Liste.
    Collected.Items := Collected.Items + ContextItems(FIndex, FNamespaces, Document.Text, Position, Matching,
      FSnippetSupport);
    // Unbekannter Name (#471): Deklarieren am Ende. Die Einträge hängen am getippten Namen, deshalb neu fragen.
    if DeclareItems(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri), Position, Postfix.InlineVar,
      Enums + Collected.Items, Declares) then
    begin
      Collected.Items := Collected.Items + Declares;
      Collected.Incomplete := True;
    end;
    if Token = '' then
      Collected.Items := Enums + Collected.Items;
    Collected.Items := Hints + Collected.Items;
    Result := TJSONObject.Create;
    TJSONObject(Result).AddPair('isIncomplete', TJSONBool.Create(Collected.Incomplete));
    TJSONObject(Result).AddPair('items', ToJson(Collected.Items, SentCount));
    // Vorab als $/progress gesendete Einträge zählen mit (#616).
    TRequestDiagnostics.ResultCount(SentCount + Length(Collected.Items));
    if SentCount + Length(Collected.Items) = 0 then
      TRequestDiagnostics.DefaultReason('noCandidates');
    if Assigned(FLog) then
      FLog(Format('completion: %d Einträge (%d vorab), unvollständig %s, Baum %d ms, gesamt %d ms',
        [SentCount + Length(Collected.Items), SentCount, BoolToStr(Collected.Incomplete, True), ParseMs,
        Watch.ElapsedMilliseconds]));
  finally
    Resolver.Free;
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
    if Result[Index].EndsWith(#13) then
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
end;

/// <summary>Deklaration von ARange; über mehr als MaxLines Zeilen (Klassen, Records) nur die erste.</summary>
function DeclarationOf(const ALines: TArray<string>; const ARange: TTextRange): string;
const
  MaxLines = 6;
  MaxLength = 600;
var
  Line, Last: Integer;
begin
  Result := '';
  Last := ARange.EndPos.Line;
  if Last - ARange.StartPos.Line >= MaxLines then
    Last := ARange.StartPos.Line;
  for Line := ARange.StartPos.Line to Last do
  begin
    if (Line < 0) or (Line > High(ALines)) then
      Break;
    if Line = ARange.StartPos.Line then
      Result := Trim(Copy(ALines[Line], ARange.StartPos.Character + 1, MaxInt))
    else
      Result := Result + ' ' + Trim(ALines[Line]);
  end;
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  if Length(Result) > MaxLength then
    Result := Copy(Result, 1, MaxLength) + ' …';
end;

/// <summary>Vorfahrenliste der Klasse ab Zeile AStartLine wie im Quelltext, samt Typargumenten
/// ("TInterfacedObject", "IComparer<TKunde>"); nil, wenn kein "class(" folgt (#466).</summary>
function HeaderAncestors(const ALines: TArray<string>; AStartLine: Integer): TArray<string>;
var
  Text, Part: string;
  Line, Index, Depth: Integer;
  Match: TMatch;
begin
  Result := nil;
  Text := '';
  for Line := AStartLine to Min(AStartLine + 5, High(ALines)) do
    Text := Text + ' ' + ALines[Line];
  Match := TRegEx.Match(Text, '=\s*class\s*(?:sealed\s*|abstract\s*)?\(', [roIgnoreCase]);
  if not Match.Success then
    Exit;
  Depth := 0;
  Part := '';
  for Index := Match.Index + Match.Length to Length(Text) do
  begin
    case Text[Index] of
      '(', '<':
        Inc(Depth);
      ')', '>':
        begin
          if Depth = 0 then
          begin
            if Trim(Part) <> '' then
              Result := Result + [StringReplace(Trim(Part), ' ', '', [rfReplaceAll])];
            Exit;
          end;
          Dec(Depth);
        end;
      ',':
        if Depth = 0 then
        begin
          Result := Result + [StringReplace(Trim(Part), ' ', '', [rfReplaceAll])];
          Part := '';
          Continue;
        end;
    end;
    Part := Part + Text[Index];
  end;
  Result := nil;
end;

/// <summary>Setzt Bindungen "T=TKunde" wortweise in AText ein (#466).</summary>
function SubstituteWords(const AText: string; const ABindings: TArray<string>): string;
var
  Binding: string;
  Equal: Integer;
begin
  Result := AText;
  for Binding in ABindings do
  begin
    Equal := Pos('=', Binding);
    Result := TRegEx.Replace(Result, '(?<![\w.])' + TRegEx.Escape(Copy(Binding, 1, Equal - 1)) + '(?![\w])',
      Copy(Binding, Equal + 1, MaxInt).Replace('$', '$$'));
  end;
end;

/// <summary>"IComparer<TKunde>" aus Container und Bindungen; ohne Bindungen der Container.</summary>
function GenericName(const AContainer: string; const ABindings: TArray<string>): string;
var
  Binding: string;
  Values: TArray<string>;
begin
  Result := AContainer;
  if Length(ABindings) = 0 then
    Exit;
  Values := nil;
  for Binding in ABindings do
    Values := Values + [Copy(Binding, Pos('=', Binding) + 1, MaxInt)];
  Result := Result + '<' + string.Join(', ', Values) + '>';
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
        Quote := Length(ADeclaration);
      if EndsText('deprecated', TrimRight(Text)) then
        ADeprecated := Copy(ADeclaration, Index + 1, Quote - Index - 1);
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
    if (Index > Length(Text)) or not CharInSet(Text[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      if Index - 1 > Start then
        Words := Words + [LowerCase(Copy(Text, Start + 1, Index - 1 - Start))];
      Start := Index;
    end;
  // "class" nur am Anfang (class function), sonst wäre jeder Klassentyp eine Klassenmethode.
  for Index := 0 to High(Words) do
  begin
    Word := Words[Index];
    if not MatchStr(Word, Known) or ((Word = 'class') and (Index > 0)) then
      Continue;
    if (Word = 'class') and ((High(Words) < 1) or not MatchStr(Words[1], ['function', 'procedure', 'property',
      'operator', 'constructor', 'destructor', 'var'])) then
      Continue;
    if Word = 'deprecated' then
      AIsDeprecated := True;
    if IndexStr(Word, Result) < 0 then
      Result := Result + [Word];
  end;
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
      if (Candidate.SelectionRange.StartPos.Line = APosition.Line) and
        (Candidate.SelectionRange.StartPos.Character = APosition.Character) and
        SameText(UnitInfo.SymbolFile(Candidate), AFileName) then
      begin
        Symbol := Candidate;
        Found := True;
        Break;
      end;
  end;
  if Found then
    Range := Symbol.Range
  else
  begin
    // Nicht im Index (lokale Variable, Parameter): die Zeile ab dem Namen.
    Range.StartPos := APosition;
    Range.EndPos := APosition;
  end;
  Declaration := DeclarationOf(Lines, Range);
  if Declaration <> '' then
    Result.AddPair('declaration', Declaration);
  if Found and (Symbol.Container <> '') then
  begin
    Result.AddPair('container', Symbol.Container);
    Result.AddPair('visibility', VisibilityText(Symbol.Visibility));
  end;
  Directives := DirectivesOf(Declaration, Deprecated, IsDeprecated);
  if Length(Directives) > 0 then
  begin
    List := TJSONArray.Create;
    for Directive in Directives do
      List.Add(Directive);
    Result.AddPair('directives', List);
  end;
  if IsDeprecated then
    Result.AddPair('deprecated', Deprecated);
  // XMLDoc wie im Hover (#654): mit <inheritdoc/> und den Fundorten der cref-Verweise.
  Resolver := TNameResolver.Create(AIndex);
  try
    if Found then
      Doc := TLspDocumentation.Load(Resolver, Resolver.SymbolFrom(UnitInfo, Symbol), Lines, Range.StartPos.Line,
        TLspDocumentation.Reader(AFileName, AText, AReadText))
    else
      Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove(Lines, Range.StartPos.Line));
    if not Doc.IsEmpty then
    begin
      Container := '';
      if Found then
      begin
        Container := Symbol.Container;
        if Container = '' then
          Container := Symbol.Name;
        Result.AddPair('documentation', TLspDocumentation.ToJson(Doc,
          TLspDocumentation.Targets(Resolver, UnitInfo, Container, Doc)));
      end
      else
        Result.AddPair('documentation', TLspDocumentation.ToJson(Doc, nil));
      Result.AddPair('documentationText', Doc.ToPlainText);
      // Nur für documentation in completionItem/resolve; HandleResolve nimmt es wieder heraus.
      Result.AddPair('documentationMarkdown', Doc.ToMarkdown);
    end;
  finally
    Resolver.Free;
  end;
  if Doc.Summary <> '' then
    Result.AddPair('summary', Doc.Summary);
  if Doc.Returns <> '' then
    Result.AddPair('returns', Doc.Returns);
  if Doc.Remarks <> '' then
    Result.AddPair('remarks', Doc.Remarks);
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
  Documentation: TJSONValue;
  FileName, Text: string;
  Position: TTextPosition;
begin
  if not (AParams is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'CompletionItem fehlt in ' + ResolveMethod);
  // Antwort ist der Eintrag selbst, ergänzt um Details; ohne data unverändert.
  Item := TJSONObject(AParams.Clone);
  Result := Item;
  if not (Item.GetValue('data') is TJSONObject) or not Assigned(FReadText) then
    Exit;
  Data := TJSONObject(Item.GetValue('data'));
  if not (Data.TryGetValue<string>('file', FileName) and Data.TryGetValue<Integer>('line', Position.Line) and
    Data.TryGetValue<Integer>('character', Position.Character)) then
    Exit;
  if not ReadCached(FileName, Text) then
    Exit;
  Details := TLspCompletion.Details(FIndex, FileName, Text, Position, ReadCached);
  // Für Atlas (Detailpanel) strukturiert in data.atlas; für andere Clients detail und documentation.
  if Details.TryGetValue<string>('declaration', Text) then
  begin
    Item.RemovePair('detail').Free;
    Item.AddPair('detail', Text);
  end;
  // Doku als Klartext oder Markdown, je nach documentationFormat des Clients (#31).
  Documentation := ResolveDocumentation(Details, FDocumentationMarkdown);
  if Documentation <> nil then
    Item.AddPair('documentation', Documentation);
  Details.RemovePair('documentationMarkdown').Free;
  if Assigned(FHintsFor) then
    Details.AddPair('xmlDoc', TLspDocumentation.HintsJson(FHintsFor(TDocumentUris.FromPath(FileName))));
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
    Exit;
  for Group in Copy(AHead, Open + 1, Close - Open - 1).Split([';']) do
  begin
    Names := Group;
    if Pos(':', Names) > 0 then
      Names := Copy(Names, 1, Pos(':', Names) - 1);
    Names := Trim(Names);
    for Name in ['const ', 'var ', 'out ', 'constref '] do
      if StartsText(Name, Names) then
        Names := Trim(Copy(Names, Length(Name) + 1, MaxInt));
    for Name in Names.Split([',']) do
      if Trim(Name) <> '' then
        Result := Result + [Trim(Name)];
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
  Symbol, TypeSymbol: TIndexSymbol;
begin
  Result := False;
  ATypeName := '';
  TypeSymbol := Default(TIndexSymbol);
  for Symbol in AUnit.Symbols do
    if ((Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType]) or
      (ARecords and (Symbol.Kind = TIndexSymbolKind.RecordType))) and
      (Symbol.Range.StartPos.Line < ALine) and (Symbol.Range.EndPos.Line >= ALine) and
      (not Result or (Symbol.Range.StartPos.Line >= TypeSymbol.Range.StartPos.Line)) then
    begin
      TypeSymbol := Symbol;
      Result := True;
    end;
  if not Result then
    Exit;
  if TypeSymbol.Container <> '' then
    ATypeName := TypeSymbol.Container + '.' + TypeSymbol.Name
  else
    ATypeName := TypeSymbol.Name;
end;

class function TLspCompletion.PropertyItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; AMatching: TCompletionMatching;
  out AItems: TCompletionItems): Boolean;
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
  Match := TRegEx.Match(LineBefore(AText, APosition), '^\s*(?:class\s+)?property\s+\w+\s*(\[[^\]]*\])?\s*:\s*' +
    '([\w.<>, ]+?)\s+(?:index\s+\S+\s+)?(?:read\s+\w+\s+)?(read|write)\s+(\w*)$', [roIgnoreCase]);
  if not Match.Success then
    Exit;
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  if not EnclosingType(UnitIndex, APosition.Line, True, TypeName) then
    Exit;
  Result := True;
  PropType := Match.Groups[2].Value;
  IsWrite := SameText(Match.Groups[3].Value, 'write');
  Prefix := Match.Groups[4].Value;
  // Indexparameter: "[I, J: Integer; const S: string]" sind drei.
  IndexCount := 0;
  for Param in Match.Groups[1].Value.Trim(['[', ']']).Split([';']) do
    if Pos(':', Param) > 0 then
      Inc(IndexCount, Length(Copy(Param, 1, Pos(':', Param) - 1).Split([','])));
  for Candidate in AResolver.AccessorCandidates(UnitIndex, TypeName) do
  begin
    if Candidate.SymbolKind = TIndexSymbolKind.Field then
      Fits := (IndexCount = 0) and (PlainType(Candidate.TypeName) = PlainType(PropType))
    else if IsWrite then
      Fits := (Candidate.TypeName = '') and (Candidate.MinArgs <= IndexCount + 1) and
        (Candidate.MaxArgs >= IndexCount + 1) and (Length(Candidate.ParamTypes) > IndexCount) and
        (PlainType(Candidate.ParamTypes[IndexCount]) = PlainType(PropType))
    else
      Fits := (Candidate.TypeName <> '') and (PlainType(Candidate.TypeName) = PlainType(PropType)) and
        (Candidate.MinArgs <= IndexCount) and (Candidate.MaxArgs >= IndexCount);
    if not Fits or (MatchScore(Candidate.Name, Prefix, AMatching) = TFuzzyMatch.NoMatch) then
      Continue;
    Item := Default(TCompletionItem);
    Item.Name := Candidate.Name;
    Item.Kind := KindOf(Candidate.SymbolKind);
    if Candidate.TypeName <> '' then
      Item.Detail := Candidate.TypeName
    else
      Item.Detail := Candidate.Container;
    Item.Container := Candidate.Container;
    Item.Depth := Candidate.Depth;
    Item.SourceFile := Candidate.FileName;
    Item.SourcePosition := Candidate.SelectionRange.StartPos;
    if (AMatching = TCompletionMatching.Fuzzy) and not Candidate.Name.StartsWith(Prefix, True) then
      Item.FilterText := Prefix;
    AItems.Items := AItems.Items + [Item];
  end;
end;

class function TLspCompletion.OverrideItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
var
  Match: TMatch;
  UnitIndex: TUnitIndex;
  TypedClass, IsClass, IsAbstract, AfterOverride: Boolean;
  TypedKind, TypeName, Source, Declaration, Kind, Head, Directives, Insert, Body, Args, LB, MethodName,
    Line, Lead: string;
  Candidate: TResolvedSymbol;
  Item: TCompletionItem;
  Edit: TRuleEdit;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  // "    procedure Ch|", "    function |", "    class procedure |"
  Line := LineBefore(AText, APosition);
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
      Exit;
    AfterOverride := True;
  end;
  // Innerster Klassentyp, in dessen Deklaration die Zeile liegt.
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  if not EnclosingType(UnitIndex, APosition.Line, False, TypeName) then
    Exit;
  Result := True;
  if AText.Contains(#13#10) then
    LB := #13#10
  else
    LB := #10;
  for Candidate in AResolver.OverridableMembers(UnitIndex, TypeName) do
  begin
    if SameText(Candidate.FileName, AFileName) then
      Source := AText
    else if not (Assigned(AReadText) and AReadText(Candidate.FileName, Source)) then
      Continue;
    Declaration := DeclarationOf(TextLines(Source), Candidate.Range);
    if not SplitOverrideDeclaration(Declaration, IsClass, Kind, Head, Directives) or
      (not AfterOverride and ((Kind <> TypedKind) or (IsClass <> TypedClass))) then
      Continue;
    IsAbstract := Directives.Contains(' abstract ');
    Insert := Head + ';';
    if Directives.Contains(' overload ') then
      Insert := Insert + ' overload;';
    Insert := Insert + ' override;';
    // Rumpf: Kopf mit Typ, inherited bzw. Result := inherited ...; abstrakt ohne inherited.
    MethodName := Candidate.Name;
    Args := String.Join(', ', OverrideParamNames(Head));
    // Standardwerte stehen nur in der Deklaration.
    Body := Kind + ' ' + TypeName + '.' + TRegEx.Replace(Head, '\s*=\s*[^;)]+', '') + ';';
    if IsClass then
      Body := 'class ' + Body;
    Body := Body + LB + 'begin' + LB;
    if IsAbstract then
      Body := Body + LB
    else if Kind = 'procedure' then
      Body := Body + '  inherited;' + LB
    else if Args <> '' then
      Body := Body + '  Result := inherited ' + MethodName + '(' + Args + ');' + LB
    else
      Body := Body + '  Result := inherited ' + MethodName + ';' + LB;
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
        Lead := 'class ' + Lead;
      Item.InsertText := '';
      Item.HasTextEdit := True;
      Item.TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(APosition.Line,
        Match.Groups[1].Length), APosition), Lead + Insert);
      Item.FilterText := 'override ' + MethodName;
    end;
    if TClassCompletion.BodyEdit(ATree, AText, TypeName, Body, Edit) then
      Item.AdditionalEdits := [Edit];
    AItems.Items := AItems.Items + [Item];
  end;
end;

class function TLspCompletion.InterfaceItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  ASection: TCompletionInterfaceSection; out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
const
  SectionNames: array[TCompletionInterfaceSection] of string = ('private', 'protected', 'public');
var
  Match: TMatch;
  UnitIndex: TUnitIndex;
  Symbol, TypeSymbol: TIndexSymbol;
  Found, NeedHeader: Boolean;
  Lines, SourceLines: TArray<string>;
  TypeName, LB, Indent, Section, SourceFile, Source: string;
  EndLine, Index, Count: Integer;
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
      Exit;
    Hint := Default(TCompletionItem);
    if Count = 1 then
      Hint.Name := Format('1 Methode von %s fehlt', [AInterface])
    else
      Hint.Name := Format('%d Methoden von %s fehlen', [Count, AInterface]);
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
  Match := TRegEx.Match(LineBefore(AText, APosition), '^(\s*)(\w*)$');
  if not Match.Success then
    Exit;
  Lines := TextLines(AText);
  if (APosition.Line < 0) or (APosition.Line > High(Lines)) then
    Exit;
  ABatch := Match.Groups[2].Length = 0;
  // Leere Zeile nur, wenn auch dahinter nichts steht; vor einer vorhandenen Deklaration bleibt Strg+Leer normal.
  if ABatch and (Trim(Copy(Lines[APosition.Line], APosition.Character + 1, MaxInt)) <> '') then
    Exit;
  // Innerste Klasse, zwischen deren Kopf und "end" der Cursor steht.
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  Found := False;
  TypeSymbol := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Length(Symbol.Ancestors) > 1) and
      (Symbol.Range.StartPos.Line < APosition.Line) and (Symbol.Range.EndPos.Line > APosition.Line) and
      (not Found or (Symbol.Range.StartPos.Line >= TypeSymbol.Range.StartPos.Line)) then
    begin
      TypeSymbol := Symbol;
      Found := True;
    end;
  if not Found then
    Exit;
  EndLine := TypeSymbol.Range.EndPos.Line;
  if (EndLine > High(Lines)) or not TRegEx.IsMatch(Lines[EndLine], '^\s*end\b', [roIgnoreCase]) then
    Exit;
  Indent := Copy(Lines[EndLine], 1, Length(Lines[EndLine]) - Length(TrimLeft(Lines[EndLine])));
  if TypeSymbol.Container <> '' then
    TypeName := TypeSymbol.Container + '.' + TypeSymbol.Name
  else
    TypeName := TypeSymbol.Name;
  // Vorfahrenliste aus dem Quelltext: Der Index kennt die Typargumente nur beim ersten Vorfahren.
  Missing := AResolver.MissingInterfaceMembers(UnitIndex, TypeName,
    HeaderAncestors(Lines, TypeSymbol.Range.StartPos.Line));
  if Length(Missing) = 0 then
    Exit;
  if AText.Contains(#13#10) then
    LB := #13#10
  else
    LB := #10;
  Section := SectionNames[ASection];
  NeedHeader := TInterfaceStubs.LastSection(ATree.Tokens, TypeSymbol.Range.StartPos.Line, EndLine) <> Section;
  WordRange := TTextRange.Create(APosition.Line, Match.Groups[1].Length, APosition.Line, APosition.Character);
  SourceFile := '';
  SourceLines := nil;
  Interfaces := nil;
  Group := nil;
  Count := 0;
  for Index := 0 to High(Missing) do
  begin
    if (SourceFile = '') or not SameText(Missing[Index].FileName, SourceFile) then
    begin
      SourceFile := Missing[Index].FileName;
      if SameText(SourceFile, AFileName) then
        Source := AText
      else if not (Assigned(AReadText) and AReadText(SourceFile, Source)) then
        Source := '';
      SourceLines := TextLines(Source);
    end;
    // Generische Interfaces: Typargumente in die Deklaration einsetzen (IComparer<TKunde>: T → TKunde).
    if not TInterfaceStubs.Make(GenericName(Missing[Index].Container, Missing[Index].Bindings), TypeName,
      SubstituteWords(DeclarationOf(SourceLines, Missing[Index].Range), Missing[Index].Bindings), LB, Stub) then
      Continue;
    if (Length(Interfaces) = 0) or not SameText(Interfaces[High(Interfaces)], Stub.InterfaceName) then
    begin
      if not ABatch and (Length(Interfaces) > 0) then
        AddHint(Interfaces[High(Interfaces)]);
      Interfaces := Interfaces + [Stub.InterfaceName];
      Group := nil;
      Count := 0;
    end;
    Edits := TInterfaceStubs.ClassEdits(Stub, EndLine, Indent, Section, NeedHeader, LB);
    if TClassCompletion.BodyEdit(ATree, AText, TypeName, Stub.Body, Edit) then
      Edits := Edits + [Edit];
    Group := Group + Edits;
    Inc(Count);
    if not ABatch then
      Continue;
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
  if not ABatch and (Length(Interfaces) > 0) then
    AddHint(Interfaces[High(Interfaces)]);
  // Eine Überschrift über der ganzen Liste: „Fehlende Methoden von IExporter, IInterface“.
  for Index := 0 to High(AItems) do
    if AItems[Index].Batch then
    begin
      AItems[Index].SetOf := string.Join(', ', Interfaces);
      AItems[Index].Expected := AItems[Index].SetOf;
      AItems[Index].Fits := True;
    end;
  Result := Length(AItems) > 0;
end;

/// <summary>Benannte Komponenten unter AObject; in Frames (inline) nur der Frame selbst, seine Komponenten
/// sind keine Felder des Formulars.</summary>
procedure CollectComponents(AObject: TDfmObject; var AList: TArray<TDfmObject>);
var
  Child: TDfmObject;
begin
  for Child in AObject.Children do
  begin
    if (Child.Kind = TDfmObjectKind.Item) or (Child.Name = '') or (Child.TypeName = '') then
      Continue;
    AList := AList + [Child];
    if Child.Kind <> TDfmObjectKind.Inline_ then
      CollectComponents(Child, AList);
  end;
end;

/// <summary>Klassenname ohne führendes T.</summary>
function TypeWord(const ATypeName: string): string;
begin
  if (Length(ATypeName) > 1) and CharInSet(ATypeName[1], ['T', 't']) then
    Result := Copy(ATypeName, 2, MaxInt)
  else
    Result := ATypeName;
end;

/// <summary>Ein Typ aus AChain heißt ohne "T" genau AWord.</summary>
function ChainHas(const AChain: TArray<string>; const AWord: string): Boolean;
var
  Name: string;
begin
  for Name in AChain do
    if SameText(TypeWord(Name), AWord) then
      Exit(True);
  Result := False;
end;

class function TLspCompletion.ComponentItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText,
  AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  AMatching: TCompletionMatching; out AItems: TArray<TCompletionItem>): Boolean;
const
  // Höchstens so viele Komponenten prüfen, ob sie von hier aus als Feld sichtbar sind.
  MaxProbes = 3;
var
  Context: TCompletionContext;
  FormFile, FormText: string;
  Document: TDfmDocument;
  Components: TArray<TDfmObject>;
  Component: TDfmObject;
  Resolved, TypeSymbol, Ancestor: TResolvedSymbol;
  Visible, ByType: Boolean;
  Probes, Depth: Integer;
  UnitIndex: TUnitIndex;
  Ancestors: TDictionary<string, TArray<string>>;
  Chain: TArray<string>;
  Item: TCompletionItem;
begin
  AItems := nil;
  Result := False;
  if not Assigned(AReadText) then
    Exit;
  Context := Analyze(ATree, APosition);
  if Context.Kind <> TCompletionContextKind.Scope then
    Exit;
  Document := nil;
  for FormFile in TFormFiles.FormFiles(AFileName, AText) do
    if AReadText(FormFile, FormText) then
    begin
      Document := TDfmParser.Parse(FormText);
      if Document.Root <> nil then
        Break;
      FreeAndNil(Document);
    end;
  if Document = nil then
    Exit;
  Ancestors := TDictionary<string, TArray<string>>.Create;
  try
    Components := nil;
    CollectComponents(Document.Root, Components);
    // Sichtbar nur in Methoden der Formularklasse: die ersten Komponenten müssen als deren Feld auflösen.
    Visible := False;
    Probes := 0;
    for Component in Components do
    begin
      Resolved := AResolver.ResolveChain(ATree, AFileName, [Component.Name], Context.Offset);
      if Resolved.Found and (Resolved.SymbolKind = TIndexSymbolKind.Field) and
        SameText(Resolved.Container, Document.Root.TypeName) then
      begin
        Visible := True;
        Break;
      end;
      Inc(Probes);
      if Probes >= MaxProbes then
        Break;
    end;
    if not Visible then
      Exit;
    UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
    for Component in Components do
    begin
      ByType := MatchScore(Component.Name, Context.Prefix, AMatching) = TFuzzyMatch.NoMatch;
      // Suche über den Typ ab zwei Zeichen: eigene Klasse beginnt damit, oder ein Vorfahr heißt genau so
      // ("button" findet TButton und TBitBtn, aber nicht TCheckBox über TButtonControl).
      if ByType then
      begin
        if Length(Context.Prefix) < 2 then
          Continue;
        if not StartsText(Context.Prefix, TypeWord(Component.TypeName)) then
        begin
          if not Ancestors.TryGetValue(LowerCase(Component.TypeName), Chain) then
          begin
            Chain := nil;
            if AResolver.ResolveTypeFrom(UnitIndex, Component.TypeName, TypeSymbol) then
              for Depth := 1 to 32 do
              begin
                if not AResolver.AncestorOf(TypeSymbol, Ancestor) then
                  Break;
                Chain := Chain + [Ancestor.Name];
                TypeSymbol := Ancestor;
              end;
            Ancestors.Add(LowerCase(Component.TypeName), Chain);
          end;
          if not ChainHas(Chain, Context.Prefix) then
            Continue;
        end;
      end;
      Item := Default(TCompletionItem);
      Item.Name := Component.Name;
      Item.Detail := Component.TypeName;
      Item.Kind := KindField;
      Item.Container := Document.Root.TypeName;
      Item.Scope := 3;
      Item.Form := Document.Root.Name;
      Item.ByType := ByType;
      AItems := AItems + [Item];
    end;
  finally
    Ancestors.Free;
    Document.Free;
  end;
  Result := Length(AItems) > 0;
end;

/// <summary>Alle Objekte unter AObject samt ihm selbst, auch in Frames.</summary>
procedure CollectObjects(AObject: TDfmObject; var AList: TArray<TDfmObject>);
var
  Child: TDfmObject;
begin
  AList := AList + [AObject];
  for Child in AObject.Children do
    CollectObjects(Child, AList);
end;

/// <summary>AType und seine Vorfahren, nächster zuerst; nur AType, wenn er sich nicht auflösen lässt.</summary>
function TypeChain(AResolver: TNameResolver; const AUnit: TUnitIndex; const AType: string): TArray<string>;
var
  Current, Ancestor: TResolvedSymbol;
  Depth: Integer;
begin
  Result := [AType];
  if not AResolver.ResolveTypeFrom(AUnit, AType, Current) then
    Exit;
  for Depth := 1 to 32 do
  begin
    if not AResolver.AncestorOf(Current, Ancestor) then
      Break;
    Result := Result + [Ancestor.Name];
    Current := Ancestor;
  end;
end;

class function TLspCompletion.SenderItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const APosition: TTextPosition; const AReadText: TCompletionReadText;
  AMatching: TCompletionMatching; ACast: TCompletionSenderCast; out AItems: TCompletionItems): Boolean;
const
  // So weit sucht Atlas nach oben nach dem Kopf der Methode bzw. nach dem Parameter darin.
  MaxHeaderDistance = 2000;
  MaxHeaderLines = 6;
var
  Context: TCompletionContext;
  Lines: TArray<string>;
  Line, HeaderLine, ParamLine, Index: Integer;
  Match: TMatch;
  MethodName, FormFile, FormText, CommonType, Cast, LB, Patched: string;
  Document: TDfmDocument;
  Objects: TArray<TDfmObject>;
  DfmObject: TDfmObject;
  Prop: TDfmProperty;
  Types, Names, Chain, First: TArray<string>;
  UnitIndex: TUnitIndex;
  Shared: Boolean;
  Candidate: string;
  PatchedTree: TSyntaxTree;
  Postfix: TPostfixOptions;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  Context := Analyze(ATree, APosition);
  if (Context.Kind <> TCompletionContextKind.Member) or (Length(Context.Names) <> 1) or
    not SameText(Context.Names[0], 'Sender') or not Assigned(AReadText) then
    Exit;
  // Kopf der umgebenden Methode "procedure TForm1.btnAnyClick(Sender: TObject);" oberhalb des Cursors.
  Lines := TextLines(AText);
  HeaderLine := -1;
  for Line := Min(APosition.Line - 1, High(Lines)) downto Max(0, APosition.Line - MaxHeaderDistance) do
  begin
    Match := TRegEx.Match(Lines[Line], '^\s*(class\s+)?(procedure|function)\s+[\w.]+\.(\w+)\s*[(;:]',
      [roIgnoreCase]);
    if Match.Success then
    begin
      HeaderLine := Line;
      MethodName := Match.Groups[3].Value;
      Break;
    end;
  end;
  if HeaderLine < 0 then
    Exit;
  ParamLine := -1;
  for Line := HeaderLine to Min(HeaderLine + MaxHeaderLines - 1, APosition.Line - 1) do
    if TRegEx.IsMatch(Lines[Line], '\bSender\s*:\s*TObject\b', [roIgnoreCase]) then
    begin
      ParamLine := Line;
      Break;
    end;
  if ParamLine < 0 then
    Exit;
  // Komponenten, deren Ereignis im Formular auf diese Methode zeigt.
  Document := nil;
  for FormFile in TFormFiles.FormFiles(AFileName, AText) do
    if AReadText(FormFile, FormText) then
    begin
      Document := TDfmParser.Parse(FormText);
      if Document.Root <> nil then
        Break;
      FreeAndNil(Document);
    end;
  if Document = nil then
    Exit;
  Types := nil;
  Names := nil;
  try
    Objects := nil;
    CollectObjects(Document.Root, Objects);
    for DfmObject in Objects do
      for Prop in DfmObject.Properties do
        if Prop.IsEvent and SameText(Prop.Value, MethodName) and (DfmObject.TypeName <> '') then
        begin
          Names := Names + [DfmObject.Name];
          if IndexText(DfmObject.TypeName, Types) < 0 then
            Types := Types + [DfmObject.TypeName];
          Break;
        end;
  finally
    Document.Free;
  end;
  if Length(Types) = 0 then
    Exit;
  // Nächster gemeinsamer Vorfahr: der erste Typ in der Kette des ersten, den alle Ketten enthalten.
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  First := TypeChain(AResolver, UnitIndex, Types[0]);
  CommonType := '';
  for Candidate in First do
  begin
    Shared := True;
    for Index := 1 to High(Types) do
    begin
      Chain := TypeChain(AResolver, UnitIndex, Types[Index]);
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
    Exit;
  // Mitglieder wie bei "Sender: <Typ>": Parameter im Kopf umschreiben und neu zerlegen; die Zeile des Cursors
  // bleibt gleich, also auch APosition.
  if AText.Contains(#13#10) then
    LB := #13#10
  else
    LB := #10;
  Lines[ParamLine] := TRegEx.Replace(Lines[ParamLine], '\b(Sender\s*:\s*)TObject\b', '$1' + CommonType,
    [roIgnoreCase]);
  Patched := string.Join(LB, Lines);
  PatchedTree := TSyntaxTreeCache.Parse(Patched);
  try
    Postfix := TPostfixOptions.Default;
    Postfix.Enabled := False;
    AItems := Collect(AResolver, AIndex, PatchedTree, AFileName, Patched, APosition, AMatching, Postfix);
  finally
    PatchedTree.Free;
  end;
  if ACast = TCompletionSenderCast.HardCast then
    Cast := CommonType + '(' + Context.Names[0] + ')'
  else
    Cast := '(' + Context.Names[0] + ' as ' + CommonType + ')';
  for Index := 0 to High(AItems.Items) do
  begin
    AItems.Items[Index].Sender := CommonType;
    AItems.Items[Index].SenderOf := string.Join(', ', Names);
    if AItems.Items[Index].HasTextEdit then
      Continue;
    // "Sender.Cap" → "(Sender as TButton).Caption"
    AItems.Items[Index].HasTextEdit := True;
    if AItems.Items[Index].InsertText <> '' then
      AItems.Items[Index].TextEdit := TRuleEdit.Create(TTextRange.Create(Context.ChainStart, APosition),
        Cast + '.' + AItems.Items[Index].InsertText)
    else
      AItems.Items[Index].TextEdit := TRuleEdit.Create(TTextRange.Create(Context.ChainStart, APosition),
        Cast + '.' + AItems.Items[Index].Name);
  end;
  Result := True;
end;

class function TLspCompletion.DataNameItems(const AIndex: ISymbolIndex; const AText, AFileName: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
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
  Lines := TextLines(AText);
  if (APosition.Line < 0) or (APosition.Line > High(Lines)) or
    not TDataFieldNames.CallAt(Lines[APosition.Line], APosition.Character, Call) then
    Exit(False);
  Result := True;
  if not Assigned(AReadText) then
    Exit;
  // Nur aus der Formulardatei: Ohne Designer-Informationen kein geratener Vorschlag.
  Names := TDataFieldNames.Lookup(AText, AFileName, Call, AIndex,
    function(const AName: string; out AContent: string): Boolean
    begin
      Result := AReadText(AName, AContent);
    end, Sql, Found);
  Source := TDataFieldNames.ShortSql(Sql);
  Range := TTextRange.Create(APosition.Line, Call.ContentStart, APosition.Line, Call.ContentEnd);
  for Name in Names do
  begin
    Item := Default(TCompletionItem);
    Item.Name := Name.Name;
    Item.Detail := Name.TypeName;
    if Call.Kind = TDataNameKind.Param then
      Item.Kind := KindVariable
    else
      Item.Kind := KindField;
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
  UnitIndex: TUnitIndex;
  Offer: TGuardOffer;
  Item: TCompletionItem;
  Lines: TArray<string>;
  Line: Integer;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  Line := APosition.Line;
  // Enter am Zeilenende: Anweisung in der Zeile davor, die Zeile des Cursors ist leer.
  if ANewLine then
  begin
    Lines := TextLines(AText);
    Line := APosition.Line - 1;
    if (Line < 0) or (APosition.Line > High(Lines)) or (Trim(Lines[APosition.Line]) <> '') then
      Exit;
  end;
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  // Art des erzeugten Typs: Record oder Interface schließen aus, TComponent-Nachfahren prüfen den Owner.
  Result := TGuardFree.Check(ATree, AText, Line,
    function(const ATypeName: string): TGuardTypeKind
    var
      Symbol: TResolvedSymbol;
    begin
      if not AResolver.ResolveTypeFrom(UnitIndex, ATypeName, Symbol) then
        Exit(TGuardTypeKind.Unknown);
      if Symbol.SymbolKind <> TIndexSymbolKind.ClassType then
        Exit(TGuardTypeKind.Other);
      if IndexText('TComponent', TypeChain(AResolver, UnitIndex, ATypeName)) >= 0 then
        Result := TGuardTypeKind.Component
      else
        Result := TGuardTypeKind.Class_;
    end, Offer);
  if not Result then
    Exit;
  if ANewLine then
    Offer.BlankLine := APosition.Line;
  Item := Default(TCompletionItem);
  Item.Kind := KindSnippet;
  Item.HasTextEdit := True;
  if AStyle = TCompletionFreeStyle.FreeAndNil then
    Item.Detail := 'FreeAndNil(' + Offer.Variable + ')'
  else
    Item.Detail := Offer.Variable + '.Free';
  Item.Name := 'Mit try…finally absichern';
  Item.Guard := 'newLine';
  Item.TextEdit := TGuardFree.Edit(AText, Offer, TGuardScope.NewLine, AStyle);
  AItems.Items := [Item];
  if Offer.CanEnclose then
  begin
    Item.Name := 'Bis Routinenende mit try…finally absichern';
    Item.Guard := 'routineEnd';
    Item.TextEdit := TGuardFree.Edit(AText, Offer, TGuardScope.ToRoutineEnd, AStyle);
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
      Continue;
    Names := Group;
    TypeText := '';
    if Pos(':', Group) > 0 then
    begin
      Names := Copy(Group, 1, Pos(':', Group) - 1);
      TypeText := Copy(Group, Pos(':', Group) + 1, MaxInt);
      if Pos('=', TypeText) > 0 then
        TypeText := Copy(TypeText, 1, Pos('=', TypeText) - 1);
    end;
    Count := Length(Names.Split([',']));
    for Index := 1 to Count do
      Result := Result + [Trim(TypeText)];
  end;
end;

class function TLspCompletion.EventItems(AResolver: TNameResolver; ATree: TSyntaxTree; const AText, AFileName: string;
  const APosition: TTextPosition; const AReadText: TCompletionReadText; out AItems: TCompletionItems): Boolean;
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
  Match := TRegEx.Match(LineBefore(AText, APosition), '(?:^|[^\w.&])((?:&?\w+\.)*)&?(\w+)\s*:=\s*(\w*)$');
  if not Match.Success then
    Exit;
  Prefix := Match.Groups[3].Value;
  Names := nil;
  for Name in Match.Groups[1].Value.Split(['.']) do
    if Name <> '' then
      Names := Names + [CleanName(Name)];
  Names := Names + [Match.Groups[2].Value];
  Offset := Analyze(ATree, APosition).Offset;
  Event := AResolver.ResolveChain(ATree, AFileName, Names, Offset);
  if not Event.Found or not (Event.SymbolKind in [TIndexSymbolKind.Property_, TIndexSymbolKind.Field,
    TIndexSymbolKind.Variable]) or (Event.TypeName = '') then
    Exit;
  // Methodenzeigertyp auflösen: wie im Quelltext, sonst über die Unit der Eigenschaft.
  TypeNames := Event.TypeName.Split(['.']);
  EventType := AResolver.ResolveChain(ATree, AFileName, TypeNames, Offset);
  if not EventType.Found and (Event.UnitName <> '') then
    EventType := AResolver.ResolveChain(ATree, AFileName, Event.UnitName.Split(['.']) + TypeNames, Offset);
  if not EventType.Found or (EventType.FileName = '') then
    Exit;
  if SameText(EventType.FileName, AFileName) then
    Source := AText
  else if not (Assigned(AReadText) and AReadText(EventType.FileName, Source)) then
    Exit;
  Declaration := DeclarationOf(TextLines(Source), EventType.Range);
  TypeMatch := TRegEx.Match(Declaration,
    '=\s*(reference\s+to\s+)?(procedure|function)\s*(?:\((.*)\))?\s*(?::\s*([\w.<>, ]+?))?\s*(of\s+object)?\s*;',
    [roIgnoreCase]);
  if not TypeMatch.Success or ((TypeMatch.Groups[1].Length = 0) and (TypeMatch.Groups[5].Length = 0)) then
    Exit;
  Kind := LowerCase(TypeMatch.Groups[2].Value);
  Params := Trim(TypeMatch.Groups[3].Value);
  ResultType := Trim(TypeMatch.Groups[4].Value);
  ParamTypes := EventParamTypes(Params);
  // Umgebende Klasse: Methodenrumpf, in dem der Cursor steht.
  UnitIndex := TIndexExtractor.Extract(ATree, AFileName);
  TypeName := '';
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and (Symbol.Container <> '') and
      (Symbol.Range.StartPos.Line < APosition.Line) and (Symbol.Range.EndPos.Line >= APosition.Line) then
      TypeName := Symbol.Container;
  if TypeName = '' then
    Exit;
  Result := True;
  LB := IfThen(AText.Contains(#13#10), #13#10, #10);
  Taken := TDictionary<string, Boolean>.Create;
  try
    for Symbol in UnitIndex.Symbols do
      if SameText(Symbol.Container, TypeName) then
        Taken.AddOrSetValue(LowerCase(Symbol.Name), True);
    // Passende Methoden der Klasse samt geerbter.
    for Candidate in AResolver.MemberCandidates(ATree, AFileName, ['Self'], Offset) do
    begin
      Taken.AddOrSetValue(LowerCase(Candidate.Name), True);
      if (Candidate.SymbolKind <> TIndexSymbolKind.Method) or (Length(Candidate.ParamTypes) <> Length(ParamTypes)) or
        ((Kind = 'function') <> (Candidate.TypeName <> '')) or
        ((Kind = 'function') and (PlainType(Candidate.TypeName) <> PlainType(ResultType))) then
        Continue;
      Fits := True;
      for Index := 0 to High(ParamTypes) do
        if PlainType(Candidate.ParamTypes[Index]) <> PlainType(ParamTypes[Index]) then
          Fits := False;
      if not Fits then
        Continue;
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
      Base := Names[High(Names) - 1]
    else if StartsText('T', TypeName) and (Pos('.', TypeName) = 0) then
      Base := Copy(TypeName, 2, MaxInt)
    else
      Base := TypeName.Substring(TypeName.LastIndexOf('.') + 1);
    if StartsText('On', Match.Groups[2].Value) then
      Base := Base + Copy(Match.Groups[2].Value, 3, MaxInt)
    else
      Base := Base + Match.Groups[2].Value;
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
    Header := Header + '(' + Params + ')';
  if Kind = 'function' then
    Header := Header + ': ' + ResultType;
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
  if TClassCompletion.AddDeclaration(ATree, AText, Method, Edit) then
    Item.AdditionalEdits := Item.AdditionalEdits + [Edit];
  Body := Header + ';' + LB + 'begin' + LB + LB + 'end;';
  if TClassCompletion.BodyEdit(ATree, AText, TypeName, Body, Edit) then
    Item.AdditionalEdits := Item.AdditionalEdits + [Edit];
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
    if Line = ARange.StartPos.Line then
      Result := Copy(Lines[Line], ARange.StartPos.Character + 1, MaxInt)
    else
      Result := Result + #10 + Lines[Line];
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
      Inc(Line);
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
function OwnerUnit(const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AFileName: string;
  const ASymbol: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if SameText(ASymbol.FileName, AFileName) then
  begin
    AUnit := TIndexExtractor.Extract(ATree, AFileName);
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
  if (Result.Found and Result.IsType) or (AIndex = nil) or (Pos('.', ATypeName) > 0) then
    Exit;
  // Typ einer Eigenschaft aus einer Unit, die hier nicht eingebunden ist (TAnchors aus Vcl.Controls).
  for Location in AIndex.FindSymbols(ATypeName) do
    if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) and AIndex.FindUnit(Location.UnitName, Owner) and
      AResolver.ResolveTypeFrom(Owner, ATypeName, Result) then
      Exit;
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
      Exit;
    Declaration := RangeText(Source, AType.Range);
    if AType.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Found := True;
      Break;
    end;
    // Alias oder Menge: von der Unit der Deklaration aus weiter auflösen.
    if not OwnerUnit(AIndex, ATree, AFileName, AType, Owner) then
      Exit;
    Element := TCompletionEnums.SetElement(Declaration);
    if Element <> '' then
    begin
      if not AAllowSet or (AEnum.SetName <> '') then
        Exit;
      AEnum.SetName := AType.Name;
      if not AResolver.ResolveTypeFrom(Owner, Element, AType) then
        Exit;
    end
    else if (AType.TypeName = '') or not AResolver.ResolveTypeFrom(Owner, AType.TypeName, AType) then
      Exit;
  end;
  if not Found then
    Exit;
  AEnum.Values := TCompletionEnums.EnumValues(Declaration);
  if AEnum.Values = nil then
    Exit;
  AEnum.Name := AType.Name;
  AEnum.FileName := AType.FileName;
  AEnum.Scoped := TCompletionEnums.ScopedAt(Source, OffsetOf(Source, AType.Range.StartPos));
  // Namenspositionen für completionItem/resolve.
  SetLength(AEnum.Positions, Length(AEnum.Values));
  for Index := 0 to High(AEnum.Positions) do
    AEnum.Positions[Index] := TTextPosition.Create(-1, 0);
  Container := AType.QualifiedName;
  if OwnerUnit(AIndex, ATree, AFileName, AType, Owner) then
    for Symbol in Owner.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, Container) then
        for Index := 0 to High(AEnum.Values) do
          if SameText(AEnum.Values[Index], Symbol.Name) then
            AEnum.Positions[Index] := Symbol.SelectionRange.StartPos;
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
    Result.InsertText := AEnum.Name + '.' + AEnum.Values[AIndex];
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
    Exit;
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10
  else
    LineBreak := #10;
  Prefix := '';
  if AEnum.Scoped then
    Prefix := AEnum.Name + '.';
  if Slot.Labels = nil then
  begin
    AItem.Name := 'Alle Werte einfügen';
    AItem.Count := Length(Missing);
  end
  else
    AItem.Name := Format('Fehlende Werte ergänzen (%d)', [Length(Missing)]);
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
    AItem.AdditionalEdits := [TRuleEdit.Create(TTextRange.Create(Slot.EndInsert, Slot.EndInsert), EndText)];
  Result := True;
end;

/// <summary>Typ eines aufgelösten Ausdrucksteils: Konstruktor → Klasse, Typumwandlung → Typ, sonst sein Typ.</summary>
function TypeOfResolved(const ASymbol: TResolvedSymbol): string;
begin
  Result := '';
  if not ASymbol.Found or (ASymbol.Kind = TResolvedKind.UnitName) then
    Exit;
  if ASymbol.SymbolKind = TIndexSymbolKind.Constructor_ then
    Result := ASymbol.Container
  else if ASymbol.IsType then
    Result := ASymbol.Name
  else if ASymbol.TypeName <> '' then
    Result := ASymbol.TypeName
  else if ASymbol.SymbolKind = TIndexSymbolKind.EnumMember then
    Result := ASymbol.Container;
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
  if (AIndex = nil) or (ATypeName = '') or (Pos('<', ATypeName) > 0) or (Pos('.', ATypeName) > 0) or
    (Pos('{', ATypeName) > 0) or AResolver.ResolveChain(ATree, AFileName, [ATypeName], AOffset).Found then
    Exit;
  for Location in AIndex.FindSymbols(ATypeName) do
    if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.ClassType,
      TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
      TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) and not SameText(Location.UnitName, 'System') and
      not SameText(Location.UnitName, TUsesClauses.OwnName(ATree.Tokens)) and
      not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATree.Tokens), Location.UnitName, AResolver.Namespaces) and
      TUsesClauses.AddUnit(ATree.Tokens, AOffset, Location.UnitName, ALineBreak, Edit) then
      Exit([Edit]);
end;

class function TLspCompletion.DeclareItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const APosition: TTextPosition; AInlineVar: Boolean;
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
  if (ATree = nil) or not TDeclareUnknown.Slot(ATree.Tokens, APosition, Slot) then
    Exit;
  // Bekannt: ein Eintrag passt genau oder die Namensauflösung findet ihn.
  for Known in AKnown do
    if SameText(Known.Name, Slot.Name) then
      Exit;
  if AResolver.Resolve(ATree, AFileName, Slot.NameRange.StartPos).Found then
    Exit;
  // Typ: rechte Seite der Zuweisung, sonst der erwartete Typ (Argument, Wert einer Zuweisung).
  TypeName := '';
  if Slot.AssignTarget then
  begin
    TypeName := TDeclareUnknown.Shape(ATree.Tokens, Slot.ValueFirst, Slot.ValueLast, TermFirst, TermLast);
    if (TypeName = '') and (TermFirst >= 0) and (TermFirst = TermLast) then
      TypeName := TDeclareUnknown.LiteralType(ATree.Tokens[TermFirst]);
    if (TypeName = '') and (TermFirst >= 0) then
    begin
      NameToken := TDeclareUnknown.TermName(ATree.Tokens, TermFirst, TermLast);
      if NameToken >= 0 then
        TypeName := TypeOfResolved(AResolver.Resolve(ATree, AFileName, ATree.Tokens[NameToken].StartPos));
    end;
  end
  else
    TypeName := ExpectedType(AResolver, ATree, AFileName, APosition);
  DeclType := TypeName;
  if DeclType = '' then
    DeclType := TDeclareUnknown.TypePlaceholder;
  Lines := TextLines(AText);
  LineText := '';
  if APosition.Line <= High(Lines) then
    LineText := Lines[APosition.Line];
  Slash := Default(TSlashContext);
  Slash.Text := AText;
  Slash.Line := APosition.Line;
  Slash.LineText := LineText;
  Source := TCommandSource.Create(Slash);
  try
    // Nur im Rumpf einer Routine: dort sind Variablen, Felder und Konstanten Deklarationen wert.
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit;
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
      Format('%s: %s;', [Slot.Name, DeclType]))] + TypeUnitEdits(AResolver, AIndex, ATree, AFileName, TypeName,
      Source.LineBreak, Routine.StartOffset);
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
        if (Symbol.Kind = TIndexSymbolKind.Field) and (SameText(Symbol.Container, ClassSymbol.QualifiedName) or
          SameText(Symbol.Container, ClassSymbol.Name)) then
          Fields := Fields + [Symbol.Name];
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
          Edit := Source.AfterLine(Line, Source.Indent(Line) + '  ' + Format('%s: %s;', [Field, DeclType]))
        else
          Edit := Source.BeforeLine(ClassSymbol.Range.EndPos.Line, Source.Indent(ClassSymbol.Range.EndPos.Line) +
            'private' + Source.LineBreak + Source.Indent(ClassSymbol.Range.EndPos.Line) + '  ' +
            Format('%s: %s;', [Field, DeclType]));
        Item.AdditionalEdits := [Edit] + TypeUnitEdits(AResolver, AIndex, ATree, AFileName, TypeName,
          Source.LineBreak, Source.Offset(ClassSymbol.Range.StartPos.Line));
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
        for Index := 0 to Section.ChildCount - 1 do
          if (Section[Index].Kind = TSyntaxKind.ConstSection) and (Node = nil) then
            Node := Section[Index];
      if Node <> nil then
        Edit := Source.AfterLine(Node.EndPos.Line, '  ' + Item.Detail)
      else
        Edit := Source.AfterLine(Source.ImplementationStart, Source.LineBreak + 'const' + Source.LineBreak + '  ' +
          Item.Detail);
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
  if ATree = nil then
    Exit;
  // Mengenkonstruktor: "X in [" nimmt den Typ von X, sonst gilt der erwartete Typ an der Klammer.
  if TCompletionEnums.SetSlot(ATree.Tokens, APosition, Slot) then
  begin
    if Slot.ElementOf <> nil then
    begin
      Target := AResolver.ResolveChain(ATree, AFileName, Slot.ElementOf, Slot.Offset);
      if not Target.Found or Target.IsType or (Target.TypeName = '') then
        Exit;
      TypeInfo := TypeAt(AResolver, AIndex, ATree, AFileName, Slot.Offset, Target.TypeName);
    end
    else
    begin
      Expected := ExpectedType(AResolver, ATree, AFileName, Slot.Bracket);
      if Expected = '' then
        Exit;
      TypeInfo := TypeAt(AResolver, AIndex, ATree, AFileName, Slot.Offset, Expected);
    end;
    if not EnumOf(AResolver, AIndex, ATree, AText, AFileName, TypeInfo, AReadText, Slot.ElementOf = nil, Enum) or
      not TCompletionEnums.Checked(Enum.Values, Slot.Present, Checked) then
      Exit;
    for Index := 0 to High(Enum.Values) do
    begin
      Item := EnumItem(Enum, Index);
      if Enum.SetName <> '' then
        Item.Expected := Enum.SetName
      else
        Item.Expected := 'set of ' + Enum.Name;
      Item.SetOf := Enum.Name;
      Item.SetChecked := Checked[Index];
      Item.SetRange := Slot.EditRange;
      AItems := AItems + [Item];
    end;
    ASetMode := True;
    Exit(True);
  end;
  // Werte: nur ohne Punkt davor ("TAlign." zeigt die Mitglieder selbst).
  Context := Analyze(ATree, APosition);
  if Context.Kind <> TCompletionContextKind.Scope then
    Exit;
  Expected := ExpectedType(AResolver, ATree, AFileName, APosition);
  if Expected = '' then
    Exit;
  TypeInfo := TypeAt(AResolver, AIndex, ATree, AFileName, Context.Offset, Expected);
  if not EnumOf(AResolver, AIndex, ATree, AText, AFileName, TypeInfo, AReadText, False, Enum) then
    Exit;
  // Am Anfang eines case-Zweigs (#449): fehlende Zweige auf einmal, als erster Eintrag.
  if CaseItem(Enum, AText, ATree.Tokens, APosition, Item) then
  begin
    Item.Expected := Expected;
    AItems := AItems + [Item];
  end;
  for Index := 0 to High(Enum.Values) do
    if MatchScore(Enum.Values[Index], Context.Prefix, AMatching) <> TFuzzyMatch.NoMatch then
    begin
      Item := EnumItem(Enum, Index);
      Item.Expected := Expected;
      AItems := AItems + [Item];
    end;
  Result := True;
end;

end.