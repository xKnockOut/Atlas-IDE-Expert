unit Atlas.Core.Completion.Contract;

// Datenquelle der Vervollständigung (#408): Die Oberfläche (Popup, #410) kennt
// nur IAtlasCompletionProvider und weiß nicht, woher die Einträge kommen.
// Standardquelle ist der Atlas-Server (ADR 0001, ADR 0006); weitere Quellen
// (Snippets #51, DelphiLSP #63, Testdaten) werden über TAtlasCompletionProviders
// zusammengeführt.
//
// Ablauf: Query kehrt sofort zurück. Die Quelle liefert ihre Einträge in
// beliebig vielen Teilmengen über AddItems und meldet zum Schluss genau einmal
// Complete, auch wenn sie nichts gefunden hat oder ein Fehler auftrat. Beides
// darf aus jedem Thread kommen; die Oberfläche leitet es selbst in den
// Hauptthread. Nach Cancel oder einem neuen Query ruft die Quelle die Senke
// des alten Query nicht mehr auf.

interface

uses
  System.SysUtils,
  Atlas.Core.Documentation.Contract;

{$SCOPEDENUMS ON}

type
  /// <summary>Was an der Cursorstelle vervollständigt wird.</summary>
  TAtlasContextKind = (Unknown, Identifier, MemberAccess, ClassDeclaration, EventAssignment, Directive, XmlDoc);

  /// <summary>Art eines Eintrags (Symbol und Badge im Popup, #421).</summary>
  TAtlasItemKind = (Unknown, Method, Function_, Procedure_, Constructor_, Destructor_, Property_, Field, Event,
    Variable, Parameter, Constant, Type_, Class_, Interface_, Record_, Enum, EnumMember, Unit_, Keyword, Snippet,
    XmlDocTag);

  TAtlasVisibility = (Unknown, StrictPrivate, Private_, StrictProtected, Protected_, Public_, Published_);

  /// <summary>Lernende Gewichtung (#418): zuletzt bzw. häufig gewählt.</summary>
  TAtlasUsageMark = (None, Recent, Frequent);

  /// <summary>Textänderung, 0-basiert in UTF-16-Einheiten wie im LSP.</summary>
  TAtlasTextEdit = record
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    NewText: string;
  end;

  TAtlasContext = record
    FileName: string;
    /// <summary>Editortext beim Auslösen, im Hauptthread gelesen (auch ungespeichert).</summary>
    Text: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert, UTF-16-Einheiten.</summary>
    Character: Integer;
    /// <summary>Schon getippter Anfang des Namens.</summary>
    Prefix: string;
    /// <summary>Erwarteter Typ an der Stelle, '' wenn unbekannt.</summary>
    ExpectedType: string;
    Kind: TAtlasContextKind;
    /// <summary>Automatisch nach diesem Zeichen geöffnet, '' bei Strg+Leer. Nach "[" (#448) bietet der Server nur
    /// Mengenwerte an; ohne die bleibt das Popup zu.</summary>
    Trigger: string;
    /// <summary>Von der IDE oder nach einem Zeichen geöffnet, nicht mit Strg+Leer. Nach Esc im selben Wort
    /// öffnet Atlas dann nicht wieder (#414).</summary>
    Automatic: Boolean;
    /// <summary>Diagnosemodus (#479): Zeitstempel (TAtlasQueryTimings.Stamp) des auslösenden Ereignisses, ab dem
    /// der Kontext ermittelt wurde; 0 = nicht gemessen.</summary>
    Started: Int64;
  end;

  TAtlasCompletionItem = record
    Name: string;
    Kind: TAtlasItemKind;
    /// <summary>Signatur bzw. Typangabe, z. B. "procedure Add(const S: string)".</summary>
    Signature: string;
    ReturnType: string;
    DeclaringClass: string;
    DeclaringUnit: string;
    Visibility: TAtlasVisibility;
    /// <summary>z. B. virtual, override, deprecated.</summary>
    Directives: TArray<string>;
    /// <summary>XMLDoc bzw. Dokumentation als Klartext.</summary>
    Documentation: string;
    /// <summary>Signaturen der weiteren Überladungen.</summary>
    Overloads: TArray<string>;
    /// <summary>Unit des Symbols ist schon eingebunden (sonst trägt AdditionalEdits sie ein, #180).</summary>
    UnitUsed: Boolean;
    /// <summary>Text beim Übernehmen; '' = Name. "$0" markiert die Cursorposition danach.</summary>
    InsertText: string;
    /// <summary>Text, gegen den gefiltert wird; '' = Name.</summary>
    FilterText: string;
    /// <summary>Rang der Quelle, kleiner = weiter oben.</summary>
    Rank: Integer;
    /// <summary>Weitere Änderungen beim Übernehmen, z. B. der uses-Eintrag.</summary>
    AdditionalEdits: TArray<TAtlasTextEdit>;
    /// <summary>Ersetzt TextEdit statt des getippten Worts, z. B. bei Postfix-Vorlagen wie Liste.for (#188):
    /// vom Anfang des Ausdrucks bis zum Cursor.</summary>
    HasTextEdit: Boolean;
    TextEdit: TAtlasTextEdit;
    /// <summary>Daten der Quelle, um Details nachzufragen (#424); '' ohne.</summary>
    ResolveData: string;
    /// <summary>Vererbungstiefe bei Mitgliedern: 0 = eigener Typ, 1 = direkter Vorfahr (#419).</summary>
    Depth: Integer;
    /// <summary>Mitglied aus einem Class- bzw. Record-Helper (#456).</summary>
    IsHelper: Boolean;
    /// <summary>Bedingung der Deklaration ("WIN64", "platform"); '' = immer (#476).</summary>
    Condition: string;
    /// <summary>Unter der aktiven Konfiguration nicht deklariert: abgeschwächt und am Ende (#476).</summary>
    Unavailable: Boolean;
    /// <summary>Gültigkeitsbereich (#488): 1 lokal, 2 Parameter, 3 Mitglied von Self, 4 eigene Unit,
    /// 5 andere Unit; 0 ohne Angabe.</summary>
    Scope: Integer;
    /// <summary>Verdeckte gleichnamige Deklarationen weiter außen (#488), z. B. "Feld TKunde.Total";
    /// das Detailpanel nennt sie.</summary>
    Hides: TArray<string>;
    /// <summary>ResolveData der weiteren Überladungen (#425); die erste ist ResolveData.</summary>
    OverloadData: TArray<string>;
    /// <summary>Routine mit Parametern (#430): beim Übernehmen Klammern ergänzen.</summary>
    HasParameters: Boolean;
    /// <summary>Vom Controller gesetzt (#418).</summary>
    Usage: TAtlasUsageMark;
    /// <summary>Angeheftet (#458), vom Controller gesetzt: steht vor allen anderen Gruppen, wenn er zum
    /// getippten Präfix passt, und trägt links einen Stern.</summary>
    Favorite: Boolean;
    /// <summary>Erwarteter Typ an der Stelle (#417, #444); '' ohne. Die Liste gruppiert dann nach Fits.</summary>
    ExpectedType: string;
    /// <summary>Eintrag passt zu ExpectedType.</summary>
    Fits: Boolean;
    /// <summary>Eintrag erzeugt Code („Neue Methode …“, #444): in Akzentfarbe, immer zuletzt.</summary>
    IsAction: Boolean;
    /// <summary>Postfix-Vorlage des Servers (#188): steht hinter allen Mitgliedern, Marke „Postfix“; gefiltert wird
    /// über FilterText (Kürzel).</summary>
    Postfix: Boolean;
    /// <summary>Wert einer Aufzählung (#448): Stelle in der Deklaration ab 1, 0 sonst. Ohne Getipptes stehen die
    /// Werte in dieser Reihenfolge vor den übrigen passenden Einträgen.</summary>
    Ordinal: Integer;
    /// <summary>Mengenmodus (#448): Aufzählungstyp der Menge, '' sonst. Dann zeigt das Popup Kontrollkästchen.</summary>
    SetOf: string;
    /// <summary>Im Mengenmodus angehakt.</summary>
    Checked: Boolean;
    /// <summary>Im Mengenmodus: was Enter ersetzt, von "[" bis hinter "]" (NewText leer).</summary>
    SetRange: TAtlasTextEdit;
    /// <summary>Steht immer oben und passt zu jedem getippten Wort („Alle Werte einfügen“, #449).</summary>
    Pinned: Boolean;
    /// <summary>Zahl als Tag, etwa die fehlenden Werte (#449); 0 ohne.</summary>
    Count: Integer;
    /// <summary>Deklariert diesen unbekannten Namen (#471): Gruppe „Name ist unbekannt“ am Ende der Liste.</summary>
    Unknown: string;
    /// <summary>Interface implementieren (#466): Liste mit Kontrollkästchen wie im Mengenmodus (SetOf = Interfaces,
    /// SetRange = getipptes Wort); Enter übernimmt die AdditionalEdits aller angehakten Einträge.</summary>
    Batch: Boolean;
    /// <summary>Hinweis „3 Methoden von IExporter fehlen“ (#466): ganz oben, nie vorgewählt.</summary>
    Hint: Boolean;
    /// <summary>Komponente aus dem Formular (#455): Name des Formulars, '' sonst. Gruppe „Formular …“ ganz oben.</summary>
    Form: string;
    /// <summary>Die Komponente passt nur über ihren Typ ("button" → btnSave): immer sichtbar, hinter den Namenstreffern.</summary>
    ByType: Boolean;
    /// <summary>Sender mit Typumwandlung (#480): Typ, als der Sender gilt („als TButton“); '' sonst.</summary>
    Sender: string;
    /// <summary>Komponenten, denen der Ereignisbehandler zugewiesen ist: "btnSave, btnLoad".</summary>
    SenderOf: string;
    /// <summary>Typkonvertierung (#490): Umwandlung in diesen Typ („→ string“), Name ist der Ausdruck
    /// (Count.ToString); ConvertFrom ist der Name des Originals, vor dem der Eintrag steht und nach dem er
    /// filtert. '' bei anderen Einträgen.</summary>
    Conversion: string;
    ConvertFrom: string;
    /// <summary>Gleitkommawert für eine Ganzzahl (#490): sein Typ; das Detailpanel nennt Round und Trunc.</summary>
    Lossy: string;
    /// <summary>Feld- oder Parametername (#461): Datenmenge, aus der er stammt; '' sonst.</summary>
    DataSet: string;
    /// <summary>Kurzform der SQL-Anweisung für die Fußzeile; '' ohne Anweisung.</summary>
    DataSource: string;
    /// <summary>Freigabe absichern (#489): Angebot nach dem ";" eines Konstruktors. Weitertippen verwirft es.</summary>
    Guard: Boolean;
    /// <summary>Code-Vorlage (#51): Text mit Platzhaltern (${1:Name}, $0); '' sonst. Beim Übernehmen setzt der
    /// Editor ihn mit der Einrückung der Zeile ein und startet den Platzhalter-Modus.</summary>
    Snippet: string;
    /// <summary>Auch die AdditionalEdits tragen Platzhalter im Format von Snippet (#473); gleiche Nummern sind mit
    /// denen des Haupttexts verknüpft (der Name eines resourcestring an Stelle und Deklaration).</summary>
    LinkedEdits: Boolean;
    /// <summary>Befehl des Servers, den der Editor nach dem Übernehmen ausführt (workspace/executeCommand, #473);
    /// '' ohne. CommandArguments: die Argumente als JSON-Array.</summary>
    Command: string;
    CommandArguments: string;
    /// <summary>Typargument nach "TFoo&lt;" (#450): Typparameter ("T"), sein Constraint ("class"), der Code der
    /// Erklärung (classes, values, constructible, implements:X, descends:X) und die ausgeblendeten Arten
    /// ("records,enums"); '' sonst.</summary>
    TypeParam: string;
    Constraint: string;
    ConstraintHint: string;
    HiddenKinds: string;
    /// <summary>Zahl der Überladungen samt dieser (mindestens 1).</summary>
    function OverloadCount: Integer;
  end;

  TAtlasCompletionItems = TArray<TAtlasCompletionItem>;

  TAtlasDocEntry = record
    /// <summary>Parametername bzw. Exception-Klasse.</summary>
    Name: string;
    Text: string;
  end;

  /// <summary>Details zum gewählten Eintrag für das Detailpanel (#424, #426, #427).</summary>
  TAtlasItemDetails = record
    Declaration: string;
    UnitName: string;
    Container: string;
    /// <summary>public, protected, ... bzw. '' bei Symbolen außerhalb von Klassen.</summary>
    Visibility: string;
    Directives: TArray<string>;
    IsDeprecated: Boolean;
    /// <summary>Text hinter deprecated, '' ohne.</summary>
    DeprecatedText: string;
    Summary: string;
    Returns: string;
    Remarks: string;
    Params: TArray<TAtlasDocEntry>;
    Exceptions: TArray<TAtlasDocEntry>;
    /// <summary>Vollständige XMLDoc (#654); leer bei fremden Servern (dann gelten Summary bis Exceptions).</summary>
    Doc: TAtlasDoc;
    /// <summary>Anzeige laut Server (data.atlas.xmlDoc); Known = False ohne Angabe.</summary>
    Display: TAtlasDocDisplay;
    /// <summary>Vom gewählten Eintrag verdeckte Deklarationen (#488).</summary>
    Hides: TArray<string>;
    /// <summary>Warum der Eintrag im aktiven Ziel fehlt (#476); '' = verfügbar.</summary>
    Availability: string;
    /// <summary>Gleitkomma für eine Ganzzahl (#490): Typ des Werts und erwarteter Typ; '' sonst.</summary>
    LossyFrom: string;
    LossyTo: string;
    function IsEmpty: Boolean;
  end;

  TAtlasDetailsCallback = reference to procedure(const ADetails: TAtlasItemDetails);

  /// <summary>Quelle, die Details zu einem ihrer Einträge nachliefern kann.</summary>
  IAtlasCompletionResolver = interface
    ['{7D1E4A92-3B6C-4F8E-A5D0-9C2B81E6F347}']
    /// <summary>Fragt die Details zu AItem an; ACallback im Hauptthread, nur für die jüngste Anfrage.
    /// False, wenn die Quelle zu AItem nichts weiß.</summary>
    function Resolve(const AItem: TAtlasCompletionItem; const ACallback: TAtlasDetailsCallback): Boolean;
  end;

  IAtlasCompletionSink = interface
    ['{5B0E6F3A-2C47-4D8E-9A1F-7E3C2B9D4A61}']
    procedure AddItems(const AItems: TAtlasCompletionItems);
    /// <summary>Die Liste ist gekürzt (LSP isIncomplete): Beim Weitertippen neu fragen (#431).
    /// Vor Complete aufzurufen.</summary>
    procedure MarkIncomplete;
    /// <summary>Die Quelle ist fertig; genau einmal je Query.</summary>
    procedure Complete;
  end;

  IAtlasCompletionProvider = interface
    ['{C3A8D1E4-6F2B-4B7A-8E5D-1A9F0C3E7B24}']
    /// <summary>Startet die Suche und kehrt sofort zurück; bricht einen laufenden Query ab.</summary>
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    /// <summary>Bricht den laufenden Query ab; seine Senke wird nicht mehr aufgerufen.</summary>
    procedure Cancel;
  end;

  /// <summary>Quelle mit Namen (#493): Die Sicherung zählt ihre Fehler getrennt und schaltet nur sie ab.</summary>
  IAtlasNamedProvider = interface
    ['{4E7B2C19-8D3A-4F6E-B1C5-9A0D7E3F2B68}']
    function ProviderName: string;
  end;

implementation

{ TAtlasCompletionItem }

function TAtlasCompletionItem.OverloadCount: Integer;
begin
  Result := 1 + Length(OverloadData);
end;

{ TAtlasItemDetails }

function TAtlasItemDetails.IsEmpty: Boolean;
begin
  Result := (Declaration = '') and (Summary = '') and (UnitName = '') and (Availability = '') and (LossyFrom = '');
end;

end.
