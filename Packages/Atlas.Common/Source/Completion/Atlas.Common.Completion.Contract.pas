unit Atlas.Common.Completion.Contract;

// Contract des Features Completion: die Werte der Vervollständigung, die Sprachserver (Atlas.Common.Lsp.Completion)
// und Editing (Quellen der Vervollständigung) teilen: Kontext am Cursor, Eintrag, Liste, Teilergebnisse und die
// Typen aus den Packages der IDE, Ergebnis eines Falls und die Stellen der Quellen. Die Anfrage ist
// Atlas.Common.Completion.Request, die Antwort im Aufbau Atlas.Common.Completion.Answer.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract;

const
  /// <summary>Arten der Einträge (CompletionItemKind des LSP) für TCompletionItem.Kind.</summary>
  cKindMethod = 2;
  cKindFunction = 3;
  cKindConstructor = 4;
  cKindField = 5;
  cKindVariable = 6;
  cKindClass = 7;
  cKindInterface = 8;
  cKindModule = 9;
  cKindProperty = 10;
  cKindEnum = 13;
  cKindEnumMember = 20;
  cKindConstant = 21;
  cKindStruct = 22;
  cKindKeyword = 14;
  cKindSnippet = 15;

type
  /// <summary>Ein Typ, den die IDE kennt, mit seiner Unit.</summary>
  TIdeTypeEntry = record
    Name: string;
    UnitName: string;
    /// <summary>Direkter Vorfahr einer Klasse mit Unit (Vcl.Controls.TCustomControl); '' ohne Angabe.</summary>
    Parent: string;
  end;

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
    /// <summary>Typargument nach "TFoo&lt;" (#450): Position des Typnamens und aktiver Typparameter (0-basiert).
    /// Collect löscht Generic wieder, wenn der Name kein generischer Typ ist.</summary>
    Generic: Boolean;
    GenericOwnerPos: TTextPosition;
    GenericParam: Integer;
    /// <summary>Name in einer Attributklammer vor einer Deklaration (#465): nur Attributklassen.</summary>
    Attribute: Boolean;
    /// <summary>Name nach "raise " bzw. "on E: " (#483): nur Exception-Klassen; ExceptionToken ist das Token davor
    /// (raise bzw. ":").</summary>
    Exceptions: Boolean;
    ExceptionToken: Integer;
  end;

  /// <summary>Zeile von „Alle Felder zuweisen“ (#491) für die Liste mit Kontrollkästchen.</summary>
  TCompletionAssignment = record
    /// <summary>Name des Felds bzw. der Property, Detail ihr Typ.</summary>
    Name: string;
    Detail: string;
    /// <summary>Die Zuweisung samt Zeilenumbruch und Einrückung für die nächste Zeile.</summary>
    Text: string;
  end;

  TCompletionItem = record
    Name: string;
    Detail: string;
    /// <summary>CompletionItemKind des LSP.</summary>
    Kind: Integer;
    /// <summary>Text für den Filter des Editors; '' = Name.</summary>
    FilterText: string;
    /// <summary>Weitere Änderungen beim Annehmen, z. B. der uses-Eintrag.</summary>
    AdditionalEdits: TArray<TTextEdit>;
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
    /// <summary>Feld im varianten Teil eines Records: Marken seines Zweigs ("0", "1 › 0", #846); '' = keiner.
    /// </summary>
    VariantBranch: string;
    /// <summary>Unter der aktiven Konfiguration nicht deklariert; Atlas zeigt es abgeschwächt am Ende (#476).</summary>
    Unavailable: Boolean;
    /// <summary>Gültigkeitsbereich ohne Punkt davor (#488): 1 lokal, 2 Parameter, 3 Mitglied von Self,
    /// 4 eigene Unit, 5 andere Unit, 6 Mitglied eines with-Objekts (#481); 0 = keine Angabe (nach einem Punkt,
    /// Schlüsselwörter …).</summary>
    Scope: Integer;
    /// <summary>Bei Scope 6 (#481): Ausdruck des with-Objekts ("qryOrders") und die verdeckten lokalen Namen bzw.
    /// Mitglieder von Self ("Self.Name"); Atlas zeigt „aus …“ und warnt „verdeckt …“.</summary>
    WithOrigin: string;
    WithShadows: TArray<string>;
    /// <summary>Unit der Deklaration bei Scope 5 (#488): Atlas zeigt sie als Tag.</summary>
    UnitName: string;
    /// <summary>Verdeckte gleichnamige Deklarationen weiter außen (#488), z. B. "Feld TKunde.Total".</summary>
    Hides: TArray<string>;
    /// <summary>Eintrag erzeugt Code statt nur einen Namen: 'override' (#443), 'create' (neue Methode, #444);
    /// Atlas wertet AdditionalEdits dann nicht als uses-Ergänzung.</summary>
    Action: string;
    /// <summary>Ersetzt TextEdit.Range statt nur den getippten Namen (Postfix-Vorlagen, #188).</summary>
    HasTextEdit: Boolean;
    TextEdit: TTextEdit;
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
    /// <summary>Eintrag deklariert diesen unbekannten Namen (#471); Atlas zeigt die Gruppe „Name ist
    /// unbekannt“.</summary>
    Unknown: string;
    /// <summary>Interface implementieren (#466): Eintrag der Liste mit Kontrollkästchen (SetOf = Interfaces,
    /// SetChecked, SetRange = getipptes Wort). Atlas übernimmt die AdditionalEdits aller angehakten Einträge in
    /// Ordinal-Reihenfolge und fasst Einfügungen an derselben Stelle zusammen.</summary>
    Batch: Boolean;
    /// <summary>Hinweis „3 Methoden von IExporter fehlen“ (#466): ganz oben, nie vorgewählt.</summary>
    Hint: Boolean;
    /// <summary>Komponente aus dem Formular (#455): Name des Formulars; Atlas zeigt die Gruppe „Formular …“
    /// oben.</summary>
    Form: string;
    /// <summary>Komponente passt nur über ihren Typ ("button" → btnSave: TButton), nicht über den Namen.</summary>
    ByType: Boolean;
    /// <summary>Sender mit Typumwandlung (#480): Typ, als der Sender gilt; '' sonst. Dann ersetzt TextEdit
    /// "Sender.Na" durch "(Sender as TButton).Name".</summary>
    Sender: string;
    /// <summary>Komponenten, denen die Methode im Designer zugewiesen ist: "btnSave, btnLoad".</summary>
    SenderOf: string;
    /// <summary>Mitglied nach einer Typprüfung (#2107): Typ T aus "if X is T then", den nur dieser Eintrag
    /// braucht; '' sonst. Dann ersetzt TextEdit "X.Na" durch die Umwandlung nach completion.senderCast.</summary>
    Narrowed: string;
    /// <summary>Bei Narrowed: der geprüfte Name ("mLocation") und die Zeile der Prüfung (ab 1).</summary>
    NarrowedName: string;
    NarrowedLine: Integer;
    /// <summary>Nach "X is " bzw. "X as " (#2107): deklarierter Typ von X, wenn dieser Typ von ihm abstammt; ''
    /// sonst.</summary>
    DescendantOf: string;
    /// <summary>Nach "X." (#2109): Stellen, an denen der Name in den Units des Projekts vorkommt; 0 ohne Zählung.
    /// </summary>
    ProjectUses: Integer;
    /// <summary>Feld- oder Parametername (#461): Datenmenge, aus der der Name stammt; '' sonst.</summary>
    DataSet: string;
    /// <summary>Kurzform der SQL-Anweisung als Quellenangabe für die Fußzeile; '' ohne Anweisung.</summary>
    DataSource: string;
    /// <summary>Freigabe absichern (#489): 'newLine' oder 'routineEnd'; '' sonst. Weitertippen verwirft.</summary>
    Guard: string;
    /// <summary>InsertText bzw. TextEdit.NewText ist ein LSP-Snippet mit Platzhaltern (#51); dann
    /// insertTextFormat = 2. Nur an Clients mit snippetSupport.</summary>
    Snippet: Boolean;
    /// <summary>Auch die AdditionalEdits sind LSP-Snippets; gleiche Nummern sind mit denen des Haupttexts verknüpft
    /// (resourcestring auslagern, #473: der Name im Abschnitt und an der Stelle).</summary>
    LinkedEdits: Boolean;
    /// <summary>Befehl, den der Client nach dem Übernehmen über workspace/executeCommand ausführt; '' ohne.</summary>
    Command: string;
    CommandTitle: string;
    CommandArguments: TArray<string>;
    /// <summary>Typargument (#450): Typparameter ("T"), sein Constraint ("class, constructor"), der Code der
    /// Erklärung (classes, values, constructible, implements:IFoo, descends:TBasis) und die ausgeblendeten Arten
    /// (classes, records, interfaces, enums, basic, durch Kommas getrennt); '' sonst.</summary>
    TypeParam: string;
    Constraint: string;
    ConstraintHint: string;
    HiddenKinds: string;
    /// <summary>Gebundene Typparameter des umgebenden Typs ("T=TKunde", #450); Detail ist schon eingesetzt,
    /// completionItem/resolve setzt sie in Deklaration und Dokumentation ein.</summary>
    Bindings: TArray<string>;
    /// <summary>Typkonvertierung (#490): Umwandlungseintrag in diesen erwarteten Typ ("string"), Name ist der
    /// gezeigte Ausdruck (Count.ToString), TextEdit setzt die ganze Kette ein; ConvertFrom ist der Name des
    /// Originals, vor dem Atlas ihn zeigt. '' bei anderen Einträgen.</summary>
    Conversion: string;
    ConvertFrom: string;
    /// <summary>Gleitkommawert für eine Ganzzahl (#490): sein Typ ("Double"); Atlas weist im Detailpanel auf
    /// Round und Trunc hin. '' sonst.</summary>
    Lossy: string;
    /// <summary>„Alle Felder zuweisen“ mit mehr als 15 Feldern (#491): Atlas zeigt beim Übernehmen erst diese
    /// Zeilen mit Kontrollkästchen; TextEdit reicht vom Anfang des Ausdrucks bis zum Cursor.</summary>
    Assignments: TArray<TCompletionAssignment>;
    /// <summary>uses-Abschnitt (#469): Gruppe der Unit (project, rtl, library); '' bei anderen Einträgen.
    /// </summary>
    UsesGroup: string;
    /// <summary>Teil des Unit-Namens, gegen den das Plugin das Wort hinter dem letzten Punkt filtert
    /// ("Generics.Collections" für "Gener").</summary>
    UsesFilter: string;
    /// <summary>Schon im anderen Abschnitt eingebunden: 'interface' bzw. 'implementation'; '' sonst.</summary>
    UsesElsewhere: string;
    /// <summary>Zirkelbezug im interface-Teil: Kette "uA → uB → Eigene"; '' ohne.</summary>
    UsesCycle: string;
    /// <summary>Erste exportierte Typen und ihre Gesamtzahl für das Detailpanel.</summary>
    UsesTypes: TArray<string>;
    UsesTypeCount: Integer;
    /// <summary>In der Liste am Cursor schon eingebundene Units für die Fußzeile.</summary>
    UsesHidden: TArray<string>;
    /// <summary>Vollständiger inherited-Aufruf (#482): 'same' (gleiche Parameter), 'overload' (andere
    /// Überladung), 'other' (weiterer Konstruktor bzw. Destruktor); '' bei anderen Einträgen.</summary>
    InheritedMatch: string;
    /// <summary>Ausgelassene abstrakte Vorfahrmethoden ("TBasis.Zeichnen") für die Fußzeile.</summary>
    InheritedAbstract: TArray<string>;
    /// <summary>Gleichnamige Bezeichner (#475): Variante, die der Compiler wählt; bei den übrigen Varianten
    /// SameNameOf = Unit der aktiven und SameNameInsert, was Enter tut ('prefix', 'prefixAdd' = Präfix und
    /// uses ergänzen, 'move' = in den uses nach hinten, 'add' = uses ergänzen). SameNameUnits: alle Units, die
    /// den Namen deklarieren, die aktive zuerst; SameNameHidden: ausgeblendete FMX-Varianten als "Unit.Name".
    /// </summary>
    SameNameActive: Boolean;
    SameNameOf: string;
    SameNameInsert: string;
    SameNameUnits: TArray<string>;
    SameNameHidden: TArray<string>;
    /// <summary>Attribut nach "[" (#465): Name ohne Endung Attribute; Atlas zeigt das Badge "at".</summary>
    Attribute: Boolean;
    /// <summary>Gerüst einer anonymen Methode (#468): der erwartete Methodenreferenztyp; Atlas zeigt ihn als Tag.
    /// '' sonst.</summary>
    MethodRef: string;
    /// <summary>Exception-Klassen (#483): 'raise' (Übernahme mit Create), 'try' (Gruppe „Aus dem try-Block“),
    /// 'general' („Allgemein“); '' sonst. Unreachable: Klasse eines früheren Zweigs, die diese schon fängt.
    /// </summary>
    ExceptionGroup: string;
    Unreachable: string;
  end;

  /// <summary>Mitglied, das nach "X." nur wegen seiner Sichtbarkeit fehlt (#2108); Zeile und Spalte der
  /// Deklaration ab 0.</summary>
  TCompletionHiddenMember = record
    Name: string;
    /// <summary>CompletionItemKind des LSP.</summary>
    Kind: Integer;
    /// <summary>"private", "strict private", "protected" oder "strict protected".</summary>
    Visibility: string;
    /// <summary>Deklarierende Klasse ohne Unit.</summary>
    Container: string;
    Detail: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Unit außerhalb des Projekts: keine Aktionen.</summary>
    External: Boolean;
  end;

  TCompletionItems = record
    Items: TArray<TCompletionItem>;
    /// <summary>Liste wurde gekürzt; der Editor fragt beim Weitertippen neu.</summary>
    Incomplete: Boolean;
    /// <summary>Passende Mitglieder, die nur wegen der Sichtbarkeit fehlen (#2108); leer ohne.</summary>
    Hidden: TArray<TCompletionHiddenMember>;
  end;

  /// <summary>Teilergebnis einer gestaffelten Vervollständigung (#616), in Anzeigereihenfolge.</summary>
  TCompletionPartialProc = reference to procedure(const AItems: TArray<TCompletionItem>);

  /// <summary>Ergebnis eines Falls oder einer Quelle der Vervollständigung: weiter mit dem nächsten Fall oder
  /// fertig mit TCompletionAnswer.Exclusive.</summary>
  TCompletionOutcome = (Next, Answered);

  /// <summary>Stelle in der festen Reihenfolge der Fälle, an der angemeldete Quellen laufen. Die Reihenfolge
  /// selbst führt der Sprachserver; eine Quelle nennt nur ihre Stelle.</summary>
  TCompletionSlot = (
    /// <summary>Schnellbefehle nach "/" am Zeilenanfang (#293) samt Argumenten: als Erstes, allein.</summary>
    Slash,
    /// <summary>Methode aus Aufruf anlegen (#472): nach "(" allein, sonst oben in der Liste.</summary>
    CreateMethod,
    /// <summary>Kontextabhängige Code-Vorlagen am Zeilenanfang (#51): am Ende der Liste.</summary>
    ContextSnippets,
    /// <summary>Unbekannte Namen deklarieren (#471): ganz am Ende, die Liste bleibt unvollständig.</summary>
    Declare);

implementation

end.
