unit Argus.Core.Completion.Contract;

// Datenquelle der Vervollständigung (#408): Die Oberfläche (Popup, #410) kennt
// nur IArgusCompletionProvider und weiß nicht, woher die Einträge kommen.
// Standardquelle ist der Argus-Server (ADR 0001, ADR 0006); weitere Quellen
// (Snippets #51, DelphiLSP #63, Testdaten) werden über TArgusCompletionProviders
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
  System.SysUtils;

{$SCOPEDENUMS ON}

type
  /// <summary>Was an der Cursorstelle vervollständigt wird.</summary>
  TArgusContextKind = (Unknown, Identifier, MemberAccess, ClassDeclaration, EventAssignment, Directive, XmlDoc);

  /// <summary>Art eines Eintrags (Symbol und Badge im Popup, #421).</summary>
  TArgusItemKind = (Unknown, Method, Function_, Procedure_, Constructor_, Destructor_, Property_, Field, Event,
    Variable, Parameter, Constant, Type_, Class_, Interface_, Record_, Enum, EnumMember, Unit_, Keyword, Snippet,
    XmlDocTag);

  TArgusVisibility = (Unknown, StrictPrivate, Private_, StrictProtected, Protected_, Public_, Published_);

  /// <summary>Lernende Gewichtung (#418): zuletzt bzw. häufig gewählt.</summary>
  TArgusUsageMark = (None, Recent, Frequent);

  /// <summary>Textänderung, 0-basiert in UTF-16-Einheiten wie im LSP.</summary>
  TArgusTextEdit = record
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    NewText: string;
  end;

  TArgusContext = record
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
    Kind: TArgusContextKind;
  end;

  TArgusCompletionItem = record
    Name: string;
    Kind: TArgusItemKind;
    /// <summary>Signatur bzw. Typangabe, z. B. "procedure Add(const S: string)".</summary>
    Signature: string;
    ReturnType: string;
    DeclaringClass: string;
    DeclaringUnit: string;
    Visibility: TArgusVisibility;
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
    AdditionalEdits: TArray<TArgusTextEdit>;
    /// <summary>Daten der Quelle, um Details nachzufragen (#424); '' ohne.</summary>
    ResolveData: string;
    /// <summary>Vererbungstiefe bei Mitgliedern: 0 = eigener Typ, 1 = direkter Vorfahr (#419).</summary>
    Depth: Integer;
    /// <summary>Mitglied aus einem Class- bzw. Record-Helper (#456).</summary>
    IsHelper: Boolean;
    /// <summary>ResolveData der weiteren Überladungen (#425); die erste ist ResolveData.</summary>
    OverloadData: TArray<string>;
    /// <summary>Routine mit Parametern (#430): beim Übernehmen Klammern ergänzen.</summary>
    HasParameters: Boolean;
    /// <summary>Vom Controller gesetzt (#418).</summary>
    Usage: TArgusUsageMark;
    /// <summary>Überschrift der Gruppe, z. B. "Passt zu TNotifyEvent" (#444); ''.</summary>
    Group: string;
    /// <summary>Eintrag erzeugt Code („Neue Methode …“, #444): in Akzentfarbe, immer zuletzt.</summary>
    IsAction: Boolean;
    /// <summary>Zahl der Überladungen samt dieser (mindestens 1).</summary>
    function OverloadCount: Integer;
  end;

  TArgusCompletionItems = TArray<TArgusCompletionItem>;

  TArgusDocEntry = record
    /// <summary>Parametername bzw. Exception-Klasse.</summary>
    Name: string;
    Text: string;
  end;

  /// <summary>Details zum gewählten Eintrag für das Detailpanel (#424, #426, #427).</summary>
  TArgusItemDetails = record
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
    Params: TArray<TArgusDocEntry>;
    Exceptions: TArray<TArgusDocEntry>;
    function IsEmpty: Boolean;
  end;

  TArgusDetailsCallback = reference to procedure(const ADetails: TArgusItemDetails);

  /// <summary>Quelle, die Details zu einem ihrer Einträge nachliefern kann.</summary>
  IArgusCompletionResolver = interface
    ['{7D1E4A92-3B6C-4F8E-A5D0-9C2B81E6F347}']
    /// <summary>Fragt die Details zu AItem an; ACallback im Hauptthread, nur für die jüngste Anfrage.
    /// False, wenn die Quelle zu AItem nichts weiß.</summary>
    function Resolve(const AItem: TArgusCompletionItem; const ACallback: TArgusDetailsCallback): Boolean;
  end;

  IArgusCompletionSink = interface
    ['{5B0E6F3A-2C47-4D8E-9A1F-7E3C2B9D4A61}']
    procedure AddItems(const AItems: TArgusCompletionItems);
    /// <summary>Die Liste ist gekürzt (LSP isIncomplete): Beim Weitertippen neu fragen (#431).
    /// Vor Complete aufzurufen.</summary>
    procedure MarkIncomplete;
    /// <summary>Die Quelle ist fertig; genau einmal je Query.</summary>
    procedure Complete;
  end;

  IArgusCompletionProvider = interface
    ['{C3A8D1E4-6F2B-4B7A-8E5D-1A9F0C3E7B24}']
    /// <summary>Startet die Suche und kehrt sofort zurück; bricht einen laufenden Query ab.</summary>
    procedure Query(const AContext: TArgusContext; const ASink: IArgusCompletionSink);
    /// <summary>Bricht den laufenden Query ab; seine Senke wird nicht mehr aufgerufen.</summary>
    procedure Cancel;
  end;

implementation

{ TArgusCompletionItem }

function TArgusCompletionItem.OverloadCount: Integer;
begin
  Result := 1 + Length(OverloadData);
end;

{ TArgusItemDetails }

function TArgusItemDetails.IsEmpty: Boolean;
begin
  Result := (Declaration = '') and (Summary = '') and (UnitName = '');
end;

end.
