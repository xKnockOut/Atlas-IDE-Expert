unit Atlas.Common.Semantics.NameResolver;

// Namensauflösung, Grundstufe: ordnet einem Bezeichner im Quelltext seine
// Deklaration zu.
//
// Reihenfolge für den ersten Namen einer Kette A.B.C:
//   1. Lokale Deklarationen der umgebenden Routinen (innen nach außen):
//      Parameter, Result, lokale var/const/type, verschachtelte Routinen,
//      Inline-Variablen vor der Position.
//   2. Bei Methoden (TFoo.Bar) Self und die Mitglieder von TFoo samt
//      Vorfahren.
//   3. Die eigene Unit (im interface-Teil nur deren interface).
//   4. Units aus uses: implementation-uses, dann interface-uses, jeweils
//      von hinten (die letzte Unit gewinnt), zuletzt System.
//   5. Unit-Namen (auch mit Punkten: System.SysUtils.Foo).
// Jeder weitere Name wird im Typ des vorigen gesucht: Mitglieder einer
// Unit, eines Typs oder des deklarierten Typs einer Variablen, eines
// Feldes, einer Property oder des Ergebnisses einer Funktion; Vorfahren
// werden durchlaufen (Klassen ohne Vorfahr erben von TObject).
//
// Ausbaustufe 2 (#263):
// - Überladungen: Auswahl nach Argumentzahl (Standardparameter zählen
//   nicht mit) und bekannten Argumenttypen; bleiben mehrere gleich gut,
//   liefert ResolveAll alle statt eines falschen.
// - Generics: Typargumente werden an die Typparameter gebunden und in
//   Typen von Mitgliedern und Vorfahren eingesetzt (TList<TKunde>.First
//   ist TKunde, class(TObjectList<TKunde>), Foo<Integer>(...)).
// - Class/Record Helper: Mitglieder des zuletzt sichtbaren Helpers für
//   einen Typ gelten für den Typ und verdecken dessen gleichnamige; auch
//   für eingebaute Typen (string, Integer).
// - with: Bezeichner werden zuerst in den with-Ausdrücken gesucht (innen
//   nach außen); ist ein Typ dort unbekannt, gibt es kein Ergebnis.
// - Inline-Variablen ohne Typ (var X := ..., for var I := ...) erhalten
//   den Typ ihres Ausdrucks.
// - Sichtbarkeit: private/strict private/protected aus anderen Units bzw.
//   Klassen werden ausgeblendet.
// - Ausdrücke als Empfänger: Foo(1).Bar, Liste[i].Bar, (X as TBar).Bar.
// Was nicht sicher auflösbar ist, liefert kein Ergebnis statt eines
// geratenen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TResolvedKind = (None, UnitName, Symbol, Local);

  TResolvedSymbol = record
    Kind: TResolvedKind;
    Name: string;
    /// <summary>Unit der Deklaration (bei Local die eigene Unit).</summary>
    UnitName: string;
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
    SymbolKind: TIndexSymbolKind;
    /// <summary>Umgebender Typ bei Mitgliedern.</summary>
    Container: string;
    /// <summary>Bei Mitgliedern (MemberCandidates): 0 = eigener Typ, 1 = direkter Vorfahr usw. (#419).</summary>
    Depth: Integer;
    /// <summary>Mitglied aus einem Class- bzw. Record-Helper (#456).</summary>
    IsHelper: Boolean;
    /// <summary>Namenspositionen weiterer Überladungen in derselben Datei (#425).</summary>
    Overloads: TArray<TTextRange>;
    /// <summary>Parametertypen je Variante (erste zuerst), um Rümpfe nicht als Überladung zu zählen.</summary>
    VariantParams: TArray<string>;
    /// <summary>Deklaration im interface-Abschnitt.</summary>
    InInterface: Boolean;
    /// <summary>Methode mit virtual, dynamic, abstract oder override (#443).</summary>
    IsVirtual: Boolean;
    /// <summary>Bedingung der Deklaration wie im Index (#476); '' = immer.</summary>
    Condition: string;
    /// <summary>Deklarierter Typ (Variablen, Felder, Properties, Parameter, Funktionsergebnis).</summary>
    TypeName: string;
    Ancestors: TArray<string>;
    IsParameter: Boolean;
    /// <summary>Gleichnamige Deklarationen weiter außen, die dieser Eintrag verdeckt (#488), als Text wie
    /// "Feld TKunde.Total"; nur bei Kandidaten für die Vervollständigung.</summary>
    Hides: TArray<string>;
    /// <summary>Wie im Index (#263).</summary>
    TypeArgs: string;
    AncestorArgs: string;
    TypeParams: string;
    Visibility: TIndexVisibility;
    MinArgs: Integer;
    MaxArgs: Integer;
    ParamTypes: TArray<string>;
    IsDefault: Boolean;
    /// <summary>Kopf der Deklaration wie im Index (#492), bei Properties samt read/write (#491); '' ohne Index.
    /// </summary>
    Signature: string;
    /// <summary>Gebundene Typparameter als Name=Typ (bei Mitgliedern die des umgebenden Typs).</summary>
    Bindings: TArray<string>;
    /// <summary>Eingebauter Typ ohne Deklaration im Index (string, Integer ...).</summary>
    Builtin: Boolean;
    /// <summary>Ausdruck, aus dem der Typ einer Inline-Variablen ohne Typangabe folgt.</summary>
    Initializer: TSyntaxNode;
    /// <summary>TKunde.Create: der Typ, an dem der Konstruktor aufgerufen wurde (0 oder 1 Eintrag).</summary>
    Constructed: array of TResolvedSymbol;
    function Found: Boolean;
    function IsType: Boolean;
    function QualifiedName: string;
  end;

  /// <summary>Alias für Bestandsnutzer; die Deklaration steht in Atlas.Common.Index.Contract.</summary>
  TEnsureUnitFunc = Atlas.Common.Index.Contract.TEnsureUnitFunc;

  /// <summary>Vorfilter für Namen von Kandidaten (#616); False = gar nicht erst aufbauen.</summary>
  TCandidateNameFilter = reference to function(const AName: string): Boolean;

  TNameResolver = class
  private type
    /// <summary>Mit PinTree vorab ausgewerteter Baum (Code-Review P-01/P-02).</summary>
    TPin = record
      Tree: TSyntaxTree;
      FileName: string;
      /// <summary>Nur aus dem Baum, wie TIndexExtractor.Extract (ohne Include-Symbole).</summary>
      Extracted: TUnitIndex;
      /// <summary>Wie TreeUnit: mit den Symbolen der Include-Dateien und Namenstabelle.</summary>
      Merged: TUnitIndex;
      /// <summary>Zahl der noch offenen PinTree-Aufrufe für diesen Baum.</summary>
      Depth: Integer;
    end;
    /// <summary>Ein offener PinTree-Aufruf; UnpinTree löst den zuletzt gesetzten.</summary>
    TPinCall = record
      Tree: TSyntaxTree;
      FileName: string;
    end;
    /// <summary>Positionen der Helfer-Typen eines Symbol-Arrays (Code-Review P-17). Symbols hält das
    /// Array fest, damit der Zeigervergleich nie auf ein neu angelegtes Array an derselben Adresse trifft.</summary>
    TUnitHelpers = record
      Symbols: TArray<TIndexSymbol>;
      Positions: TArray<Integer>;
    end;
  private
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FNameFilter: TCandidateNameFilter;
    // Gestaffelte Kandidaten (#616): Stand nach OwnScopeCandidates für UsedScopeCandidates.
    FScopeSeen: TDictionary<string, Boolean>;
    FScopeUnit: TUnitIndex;
    FScopeInImplementation: Boolean;
    FScopeOpen: Boolean;
    // Pro Aufruf von Resolve
    FTree: TSyntaxTree;
    FCurrent: TUnitIndex;
    FOffset: Integer;
    FInImplementation: Boolean;
    // Mit PinTree vorab ausgewertete Bäume als Stapel (verschachtelt, LIFO), für viele Aufrufe auf
    // demselben Baum.
    FPins: TList<TPin>;
    FPinCalls: TList<TPinCall>;
    // Helfer-Positionen je Unit (Schlüssel Dateiname bzw. Unit-Name), einmal je Resolver ermittelt.
    FUnitHelpers: TDictionary<string, TUnitHelpers>;
    // Letztes Ergebnis von ScopeUnits; gilt, solange die uses-Arrays dieselben sind (Code-Review P-17).
    FScopeInterfaceUses: TArray<string>;
    FScopeImplementationUses: TArray<string>;
    FScopeUnitName: string;
    FScopeWithImplementation: Boolean;
    FScopeValid: Boolean;
    FScopeResult: TArray<string>;
    // Je Baum: Helfer je Typname und die Klasse der umgebenden Methode.
    FHelperTree: TSyntaxTree;
    FHelpers: TDictionary<string, TResolvedSymbol>;
    // Aufgelöste Vorfahren je Typ (Diagnoselog 15.10.2026): Jeder Mitgliedszugriff lief die ganze
    // Vererbungskette neu durch; gilt wie FHelpers für einen Baum.
    FAncestors: TDictionary<string, TResolvedSymbol>;
    // Units, die in diesem Resolver schon nicht gefunden wurden: nicht erneut suchen.
    FMissingUnits: TDictionary<string, Boolean>;
    // Zeit im Nachladen (EnsureUnit) für das Diagnoselog (#647).
    FEnsureMs: Int64;
    FClassState: Integer;
    FClass: TResolvedSymbol;
    FInferDepth: Integer;
    function FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Unit als Qualifizierer in einem Ausdruck (A.B.C): nachgeladen nur, wenn sie in uses steht.</summary>
    function FindQualifierUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    function ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
    /// <summary>Positionen der Helfer-Typen (ohne Container) in AUnit.Symbols.</summary>
    function HelperPositions(const AUnit: TUnitIndex): TArray<Integer>;
    /// <summary>Position von (ATree, AFileName) in FPins; -1, wenn nicht gepinnt.</summary>
    function PinnedIndex(ATree: TSyntaxTree; const AFileName: string): Integer;
    /// <summary>AExtracted samt der Symbole ihrer $I-Dateien aus dem Index (#500), mit Namenstabelle.</summary>
    function MergedUnit(const AExtracted: TUnitIndex; const AFileName: string): TUnitIndex;
    function FromSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
    function FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
      AIsParameter: Boolean): TResolvedSymbol;
    function LookupInUnit(const AUnit: TUnitIndex; const AName: string; AOnlyInterface, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol; AArity: Integer = -1): Boolean;
    function LookupGlobal(const AUnit: TUnitIndex; const AName: string; AWithImplementation, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol; AArity: Integer = -1): Boolean;
    function ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
      AWithImplementation: Boolean; out AResult: TResolvedSymbol; AArity: Integer = -1): Boolean;
    function ResolveTypeText(const AText: string; const AFromUnit: TUnitIndex; AWithImplementation: Boolean;
      out AResult: TResolvedSymbol): Boolean;
    function QualifyType(const AText: string; const AFromUnit: TUnitIndex; AWithImplementation: Boolean): string;
    function FindMembers(const AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
    function UnitRoutines(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
    function HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
    function IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex; const AOwner: TResolvedSymbol): Boolean;
    function CurrentClass(out AType: TResolvedSymbol): Boolean;
    function DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
    function DefaultProperty(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
    function ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    function ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
    function LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>; out AStop: Boolean): Boolean;
    function LookupWithOwner(const AName: string; out AResults: TArray<TResolvedSymbol>; out AStop: Boolean;
      out AWith: TSyntaxNode; out AElement: Integer): Boolean;
    function FindReceiver(AEndOffset: Integer): TSyntaxNode;
    function FindCall(ACalleeEnd: Integer): TSyntaxNode;
    function IsForVar(ANode: TSyntaxNode): Boolean;
    /// <summary>Index des ersten Tokens von FTree mit Offset &gt;= AOffset (binäre Suche).</summary>
    function FirstTokenAt(AOffset: Integer): Integer;
    function ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
      out AResults: TArray<TResolvedSymbol>): Boolean;
    function ResolveNames(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; AInherited: Boolean; AReceiver, ACall: TSyntaxNode): TArray<TResolvedSymbol>;
    function ResolveAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TResolvedSymbol>;
    function TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    function FindMember(const AType: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function IsAttributeClass(const AType: TResolvedSymbol): Boolean;
    function EnclosingRoutines: TArray<TSyntaxNode>;
    function LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupInDeclarations(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function LookupInlineVars(ANode: TSyntaxNode; const AName: string; out AResult: TResolvedSymbol): Boolean;
    function MethodClass(out AType: TResolvedSymbol): Boolean;
    /// <summary>Typ der umgebenden Methode und bei verschachtelten Typen (TAussen.TInnen.Methode) die
    /// äußeren Typen, innerster zuerst; ihre Mitglieder sind dort ohne Präfix sichtbar.</summary>
    function MethodClasses: TArray<TResolvedSymbol>;
    /// <summary>Unit aus dem Baum samt der Symbole ihrer $I-Dateien aus dem Index (#500).</summary>
    function TreeUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
    function ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer; out AResult: TResolvedSymbol): Boolean;
    function TokenIndexAt(const APosition: TTextPosition): Integer;
    procedure Prepare(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer);
    procedure AddCandidate(AList: TList<TResolvedSymbol>; ASeen: TDictionary<string, Boolean>;
      const ASymbol: TResolvedSymbol);
    procedure CollectMembers(const AType: TResolvedSymbol; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
    function NameWanted(const AName: string): Boolean;
    procedure CollectUnit(const AUnit: TUnitIndex; AOnlyInterface: Boolean; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
    procedure CollectDeclarations(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
    procedure CollectInlineVars(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
      ASeen: TDictionary<string, Boolean>);
  public
    constructor Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc = nil);
    destructor Destroy; override;
    /// <summary>Direkter Vorfahr eines Typs (ohne Angabe TObject bzw. IInterface); False ohne oder bei Helfern.</summary>
    function AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
    /// <summary>Deklaration der Property AName mit Typ in AType oder seinen Vorfahren (#491): "property Caption;"
    /// hebt nur die Sichtbarkeit an, Typ und Zugriff stehen weiter oben. ADepth wie bei MemberCandidates.
    /// </summary>
    function TypedProperty(const AType: TResolvedSymbol; const AName: string; out AProperty: TResolvedSymbol;
      out ADepth: Integer): Boolean;
    /// <summary>Löst den Bezeichner an APosition auf; bei gleich guten Überladungen die erste.</summary>
    function Resolve(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TResolvedSymbol;
    /// <summary>Wie Resolve, aber alle gleich guten Kandidaten, wenn die Überladung nicht eindeutig ist (#263).</summary>
    function ResolveAll(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TArray<TResolvedSymbol>;
    /// <summary>„with auflösen“ (#50): with-Anweisung und Element (Index unter ihren Kindern), dessen Mitglied
    /// AName an AOffset ist; innerstes with und darin das letzte Element zuerst. False ohne Treffer; AUnknown, wenn
    /// der Typ eines Elements unbekannt ist und der Name dazugehören könnte.</summary>
    function WithMember(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer; out AWith: TSyntaxNode;
      out AElement: Integer; out AUnknown: Boolean): Boolean;
    /// <summary>Löst die Kette ANames (A.B.C) so auf, wie sie an AOffset stünde.</summary>
    function ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; AInherited: Boolean = False): TResolvedSymbol;
    /// <summary>Typ des Bezeichners an APosition (Aliase verfolgt); Typen liefern sich selbst.</summary>
    function ResolveType(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TResolvedSymbol;
    /// <summary>Alle an AOffset ohne Qualifizierung sichtbaren Namen, nächster Gültigkeitsbereich zuerst:
    /// lokale Namen, Mitglieder der eigenen Klasse, eigene Unit, Units aus uses, System.</summary>
    function ScopeCandidates(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Erster Teil von ScopeCandidates (#616): lokale Namen, Mitglieder der eigenen Klasse und die
    /// eigene Unit. Danach liefert UsedScopeCandidates den Rest.</summary>
    function OwnScopeCandidates(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Zweiter Teil (#616): Units aus uses und System, ohne Namen, die der erste Teil schon brachte.
    /// Leer ohne vorheriges OwnScopeCandidates. Mit AWithIntrinsics zuletzt die Bezeichner von System ohne
    /// Quelltext (#880: Assigned, SetLength, Integer ...), soweit kein indexierter Name sie schon brachte.</summary>
    function UsedScopeCandidates(AWithIntrinsics: Boolean = False): TArray<TResolvedSymbol>;
    /// <summary>Alle gleichnamigen verschachtelten Routinen neben der lokalen Routine ASymbol (#881), also
    /// ihre Überladungen in derselben umgebenden Routine, ASymbol eingeschlossen. Nach Resolve auf dem Baum,
    /// aus dem ASymbol stammt; sonst nur ASymbol.</summary>
    function LocalOverloads(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
    /// <summary>Deklarationen aus den Units in uses und System, die NameFilter durchlässt, auch wenn der erste
    /// Teil sie schon verdeckt (#488); ändert den Stand für UsedScopeCandidates nicht. Leer ohne vorheriges
    /// OwnScopeCandidates.</summary>
    function UsedScopeShadows: TArray<TResolvedSymbol>;
    /// <summary>Kurzer Text zu einer verdeckten Deklaration (#488): "lokale Variable X", "Parameter X",
    /// "Feld TKunde.X", "Eigenschaft TKunde.X", "Methode TKunde.X", "Kunde.X".</summary>
    class function ShadowText(const ASymbol: TResolvedSymbol): string; static;
    /// <summary>Passt ein Argument vom Typ AArg zu einem Parameter vom Typ AParam (#498)? Gleiche Typfamilie,
    /// Char an string, Ganzzahl an Gleitkomma, nil an Zeiger und Klassen, [] an Mengen und offene Arrays; Klassen
    /// ohne Vererbungsprüfung. '' (unbekannt) passt immer.</summary>
    class function ArgumentFits(const AParam, AArg: string): Boolean; static;
    /// <summary>Mitglieder hinter A.B. (samt geerbter) bzw. interface-Symbole, wenn die Kette eine Unit ist.</summary>
    function MemberCandidates(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Typ der Kette A.B samt Vorfahren, nächster zuerst (#456): Ziele für Helper aus nicht
    /// eingebundenen Units. Leer, wenn die Kette eine Unit oder ihr Typ unbekannt ist.</summary>
    function ReceiverTypes(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Passt der Zieltyp ATarget eines Helpers (ggf. mit Unit-Präfix) zu AType? string und
    /// UnicodeString gelten als gleich.</summary>
    class function HelperTargets(const ATarget: string; const AType: TResolvedSymbol): Boolean; static;
    /// <summary>Kette A.B als Wert und ihr Typ (Aliase verfolgt), z. B. für Postfix-Vorlagen (#188).
    /// False, wenn die Kette nicht auflösbar ist; ATypeFound sagt, ob der Typ bekannt ist.</summary>
    function ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; out AOwner, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
    /// <summary>Wertet ATree einmal aus und nutzt das für alle folgenden Aufrufe mit demselben Baum,
    /// bis UnpinTree. Der Aufrufer gibt den Baum erst nach UnpinTree frei. Verschachtelt aufrufbar,
    /// auch mit anderen Bäumen; jedes PinTree braucht genau ein UnpinTree (LIFO, try/finally). Ist der
    /// Baum schon gepinnt, zählt PinTree nur hoch und wertet nicht erneut aus.</summary>
    procedure PinTree(ATree: TSyntaxTree; const AFileName: string);
    /// <summary>Löst das zuletzt gesetzte PinTree; ohne gepinnten Baum wirkungslos.</summary>
    procedure UnpinTree;
    /// <summary>Unit-Index nur aus ATree (ohne Include-Symbole), wie TIndexExtractor.Extract; bei gepinntem
    /// Baum ohne neue Auswertung. Die Symbole tragen Positionen in ATree.</summary>
    function ExtractedUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
    /// <summary>Löst ATypeName so auf, wie er in AFromUnit stünde (z. B. Vorfahren aus dem Index).</summary>
    function ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Überschreibbare Methoden für ATypeName aus AFromUnit (#443): virtual, dynamic, abstract oder
    /// override in einem Vorfahren, im Typ selbst noch nicht deklariert; nächster Vorfahr zuerst (Depth 1).</summary>
    function OverridableMembers(const AFromUnit: TUnitIndex; const ATypeName: string): TArray<TResolvedSymbol>;
    /// <summary>Nach "inherited " (#31): Methoden und Konstruktoren der Vorfahren der Klasse, in deren Methode
    /// AOffset liegt, sichtbar wie aus dieser Methode; Depth 1 = direkter Vorfahr. Leer außerhalb einer
    /// Methode.</summary>
    function InheritedCandidates(ATree: TSyntaxTree; const AFileName: string;
      AOffset: Integer): TArray<TResolvedSymbol>;
    /// <summary>Felder und Methoden für read/write einer Property (#31): die des Typs ATypeName aus AFromUnit
    /// in jeder Sichtbarkeit (Depth 0), dann die der Vorfahren ohne strict private und ohne private aus anderen
    /// Units; gleichnamige weiter oben verdecken die der Vorfahren.</summary>
    function AccessorCandidates(const AFromUnit: TUnitIndex; const ATypeName: string): TArray<TResolvedSymbol>;
    /// <summary>Methoden der Interfaces aus der Vorfahrenliste von ATypeName samt ihrer Vorfahren (#466), die
    /// weder der Typ noch eine Vorfahrklasse mit gleichem Namen und gleichen Parametertypen deklariert.
    /// Container ist das deklarierende Interface; Reihenfolge wie in der Vorfahrenliste, je Interface erst seine
    /// Methoden, dann die seiner Vorfahren. AAncestors: Vorfahrenliste wie im Quelltext samt Typargumenten
    /// ("IComparer<TKunde>"); ohne gilt die des Index. Bei generischen Interfaces trägt jedes Ergebnis die
    /// Bindungen ("T=TKunde", ohne Unit-Präfix) in Bindings; verglichen wird mit eingesetzten Typen.</summary>
    function MissingInterfaceMembers(const AFromUnit: TUnitIndex; const ATypeName: string;
      const AAncestors: TArray<string> = nil): TArray<TResolvedSymbol>;
    /// <summary>Entfernt Unit-Präfixe aus einem Typtext ("Kunden.TKunde" → "TKunde", auch in Typargumenten):
    /// Units des Index und AOwnUnit.</summary>
    function UnqualifyType(const AText: string; const AOwnUnit: string = ''): string;
    /// <summary>Name (Typ, Routine, Konstante …) so aufgelöst, wie er in AFromUnit stünde (cref, #654).</summary>
    function ResolveNameFrom(const AFromUnit: TUnitIndex; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Mitglied AName von AType oder dem nächsten Vorfahren, der es deklariert, ohne Rücksicht auf die
    /// Sichtbarkeit (Doku-Vererbung, #654). Die Deklaration im Typ geht dem Rumpf vor.</summary>
    function DeclaredMember(const AType: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Index-Symbol als aufgelöstes Symbol (#654).</summary>
    function SymbolFrom(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
    /// <summary>Unit, in der AResolved deklariert ist (#654).</summary>
    function DeclaringUnit(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    /// <summary>ATypeName ist ATargetName oder stammt davon ab, beide so aufgelöst, wie sie an AOffset
    /// stünden (#417).</summary>
    function TypeDescendsFrom(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
      const ATypeName, ATargetName: string): Boolean;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace) für uses ohne Präfix.</summary>
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    /// <summary>Ist AName der Anfang eines Unit-Namens im Bereich (Atlas in Atlas.Core.Foo.Bar, Winapi in
    /// Winapi.Windows.TextOut)? Nach PinTree bzw. Resolve gültig.</summary>
    function IsUnitPrefix(const AName: string): Boolean;
    /// <summary>Bricht die Vorfahrenkette der umgebenden Klasse an einem unbekannten Typ ab (Unit nicht im
    /// Index)? Dann kann ein Name geerbt sein (ClientWidth aus TControl). Nach PinTree bzw. Resolve gültig.</summary>
    function HasUnknownAncestor: Boolean;
    /// <summary>Eingebauter Typ ohne Deklaration im Index (string, Integer, PChar …).</summary>
    class function IsBuiltinTypeName(const AName: string): Boolean; static;
    /// <summary>Vorfilter für ScopeCandidates und MemberCandidates (#616): Symbole aus dem Index, deren Name
    /// nicht passt, werden nicht aufgebaut. nil = alle. Lokale Namen aus dem Baum filtert er nicht.</summary>
    property NameFilter: TCandidateNameFilter read FNameFilter write FNameFilter;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.Diagnostics,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Semantics.SystemIntrinsics;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess,
    TSyntaxKind.ParenExpr, TSyntaxKind.Dereference];
  MaxDepth = 32;
  MaxInferDepth = 8;
  // Eingebaute Typen, die nicht als Symbol im Index stehen.
  BuiltinTypes: array[0..27] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'Char', 'WideChar', 'AnsiChar', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'Double', 'Single', 'Extended',
    'Currency', 'Real', 'Pointer', 'Variant');
  IntegerTypes: array[0..13] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Int8', 'UInt8');
  FloatTypes: array[0..4] of string = ('Double', 'Single', 'Extended', 'Currency', 'Real');
  StringTypes: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString');
  CharTypes: array[0..2] of string = ('Char', 'WideChar', 'AnsiChar');
  /// <summary>Nehmen ein String-Literal und nil an (#498).</summary>
  PCharTypes: array[0..2] of string = ('PChar', 'PWideChar', 'PAnsiChar');

function NoResult: TResolvedSymbol;
begin
  Result := Default(TResolvedSymbol);
  Result.Kind := TResolvedKind.None;
end;

/// <summary>Knoten mit Parametern und Ergebnistyp einer Routine: der Kopf einer benannten Routine,
/// bei einer anonymen Methode der Knoten selbst; nil ohne Kopf.</summary>
function RoutineHeaderOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  if ARoutine.Kind = TSyntaxKind.AnonymousMethod then
    Result := ARoutine
  else
    Result := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
end;

function Contains(ANode: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

/// <summary>Kommagetrennte Liste auf oberster Ebene: 'string, TList&lt;A, B&gt;' → ['string', 'TList&lt;A, B&gt;'].</summary>
function SplitArgs(const AText: string): TArray<string>;
var
  Index, Depth, Start: Integer;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  Depth := 0;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or ((AText[Index] = ',') and (Depth = 0)) then
    begin
      Result := Result + [Trim(Copy(AText, Start, Index - Start))];
      Start := Index + 1;
    end
    else if AText[Index] = '<' then
      Inc(Depth)
    else if AText[Index] = '>' then
      Dec(Depth);
end;

/// <summary>'TList&lt;TKunde&gt;' → 'TList' und 'TKunde'.</summary>
procedure SplitGeneric(const AText: string; out ABase, AArgs: string);
var
  Open: Integer;
begin
  Open := Pos('<', AText);
  if (Open = 0) or (AText[Length(AText)] <> '>') then
  begin
    ABase := Trim(AText);
    AArgs := '';
  end
  else
  begin
    ABase := Trim(Copy(AText, 1, Open - 1));
    AArgs := Copy(AText, Open + 1, Length(AText) - Open - 1);
  end;
end;

function FullType(const ATypeName, ATypeArgs: string): string;
begin
  if ATypeArgs = '' then
    Result := ATypeName
  else
    Result := ATypeName + '<' + ATypeArgs + '>';
end;

/// <summary>Bindet Typparameter 'T,U' an Typargumente.</summary>
function Bind(const AParams: string; const AArgs: TArray<string>): TArray<string>;
var
  Params: TArray<string>;
  Index: Integer;
begin
  Result := nil;
  Params := SplitArgs(AParams);
  for Index := 0 to High(Params) do
    if Index <= High(AArgs) then
      Result := Result + [Params[Index] + '=' + AArgs[Index]];
end;

/// <summary>Setzt gebundene Typparameter in einen Typtext ein; spätere Bindungen gewinnen.</summary>
function Substitute(const AText: string; const ABindings: TArray<string>): string;
var
  Index, Start, Binding, Equal: Integer;
  Word, Replacement: string;
begin
  if Length(ABindings) = 0 then
    Exit(AText);
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.']) then
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.']) do
        Inc(Index);
      Word := Copy(AText, Start, Index - Start);
      Replacement := Word;
      for Binding := High(ABindings) downto 0 do
      begin
        Equal := Pos('=', ABindings[Binding]);
        if SameText(Copy(ABindings[Binding], 1, Equal - 1), Word) then
        begin
          Replacement := Copy(ABindings[Binding], Equal + 1, MaxInt);
          Break;
        end;
      end;
      Result := Result + Replacement;
    end
    else
    begin
      Result := Result + AText[Index];
      Inc(Index);
    end;
  end;
end;

function IsBuiltinName(const AName: string): Boolean;
begin
  Result := MatchText(AName, BuiltinTypes) or MatchText(AName, IntegerTypes);
end;

function BuiltinType(const AName: string): TResolvedSymbol;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := AName;
  Result.UnitName := 'System';
  Result.SymbolKind := TIndexSymbolKind.RecordType;
  Result.Builtin := True;
end;

/// <summary>Gleiche Typfamilie (string/UnicodeString, Ganzzahlen ...).</summary>
function SameFamily(const A, B: string): Boolean;
begin
  Result := SameText(A, B) or
    (MatchText(A, StringTypes) and MatchText(B, StringTypes)) or
    (MatchText(A, CharTypes) and MatchText(B, CharTypes)) or
    (MatchText(A, IntegerTypes) and MatchText(B, IntegerTypes));
end;

/// <summary>Passt ein Argument vom Typ AArg zum Parameter vom Typ AParam? '' = unbekannt; 'nil' für nil.</summary>
function ArgFits(const AParam, AArg: string): Boolean;
begin
  if (AParam = '') or (AArg = '') or SameText(AParam, 'Variant') or SameText(AParam, 'OleVariant') then
    Exit(True);
  // nil (#498): Zeiger, Klassen, Interfaces, Methodenzeiger, dynamische Arrays, aber keine einfachen Typen.
  if SameText(AArg, 'nil') then
    Exit(SameText(AParam, 'Pointer') or MatchText(AParam, PCharTypes) or not IsBuiltinName(AParam));
  // String-Literal an PChar.
  if MatchText(AParam, PCharTypes) and (MatchText(AArg, StringTypes) or MatchText(AArg, CharTypes)) then
    Exit(True);
  if AArg = '[]' then
    Exit(StartsText('array of', AParam) or StartsText('set of', AParam) or (Pos('<', AParam) = 0));
  if StartsText('array of', AParam) then
    Exit(False);
  Result := SameFamily(AParam, AArg) or
    // Ganzzahl an Gleitkomma, Char an string.
    (MatchText(AParam, FloatTypes) and (MatchText(AArg, IntegerTypes) or MatchText(AArg, FloatTypes))) or
    (MatchText(AParam, StringTypes) and MatchText(AArg, CharTypes)) or
    // Klassen: ohne Vererbungsprüfung als passend werten, nur eingebaute Typen schließen aus.
    (not IsBuiltinName(AParam) and not IsBuiltinName(AArg));
end;

function SameSignature(const A, B: TResolvedSymbol): Boolean;
var
  Index: Integer;
begin
  Result := (A.SymbolKind = B.SymbolKind) and (A.MinArgs = B.MinArgs) and (A.MaxArgs = B.MaxArgs) and
    (Length(A.ParamTypes) = Length(B.ParamTypes));
  if Result then
    for Index := 0 to High(A.ParamTypes) do
      if not SameText(A.ParamTypes[Index], B.ParamTypes[Index]) then
        Exit(False);
end;

/// <summary>Deklaration und Rumpf derselben Routine nur einmal; die Deklaration zuerst.</summary>
procedure AddDistinct(var AList: TArray<TResolvedSymbol>; const ASymbol: TResolvedSymbol);
var
  Existing: TResolvedSymbol;
begin
  for Existing in AList do
    if SameSignature(Existing, ASymbol) then
      Exit;
  AList := AList + [ASymbol];
end;

/// <summary>Wählt Überladungen nach Argumentzahl und -typen; AArgCount &lt; 0 = unbekannt.</summary>
function SelectOverloads(const ACandidates: TArray<TResolvedSymbol>; AArgCount: Integer;
  const AArgTypes: TArray<string>): TArray<TResolvedSymbol>;
var
  Candidate: TResolvedSymbol;
  Fitting: TArray<TResolvedSymbol>;
  Scores: TArray<Integer>;
  Index, Arg, Score, Best: Integer;
begin
  if (AArgCount < 0) or (Length(ACandidates) <= 1) then
    Exit(ACandidates);
  Fitting := nil;
  Scores := nil;
  for Candidate in ACandidates do
  begin
    if (Candidate.SymbolKind in RoutineKinds) and
      ((AArgCount < Candidate.MinArgs) or (AArgCount > Candidate.MaxArgs)) then
      Continue;
    Score := 0;
    for Arg := 0 to Min(AArgCount, Length(Candidate.ParamTypes)) - 1 do
      if Arg <= High(AArgTypes) then
        if not ArgFits(Candidate.ParamTypes[Arg], AArgTypes[Arg]) then
        begin
          Score := -1;
          Break;
        end
        else if (AArgTypes[Arg] <> '') and SameFamily(Candidate.ParamTypes[Arg], AArgTypes[Arg]) then
          Inc(Score);
    if Score < 0 then
      Continue;
    Fitting := Fitting + [Candidate];
    Scores := Scores + [Score];
  end;
  // Passt keine, lieber alle zeigen als eine falsche.
  if Length(Fitting) = 0 then
    Exit(ACandidates);
  Best := MaxIntValue(Scores);
  Result := nil;
  for Index := 0 to High(Fitting) do
    if Scores[Index] = Best then
      Result := Result + [Fitting[Index]];
end;

{ TResolvedSymbol }

function TResolvedSymbol.Found: Boolean;
begin
  Result := Kind <> TResolvedKind.None;
end;

function TResolvedSymbol.IsType: Boolean;
begin
  Result := (Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and (SymbolKind in TypeKinds);
end;

function TResolvedSymbol.QualifiedName: string;
begin
  if Container = '' then
    Result := Name
  else
    Result := Container + '.' + Name;
end;

{ TNameResolver }

constructor TNameResolver.Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FHelpers := TDictionary<string, TResolvedSymbol>.Create;
  FAncestors := TDictionary<string, TResolvedSymbol>.Create;
  FPins := TList<TPin>.Create;
  FPinCalls := TList<TPinCall>.Create;
  FUnitHelpers := TDictionary<string, TUnitHelpers>.Create;
end;

destructor TNameResolver.Destroy;
begin
  FScopeSeen.Free;
  FMissingUnits.Free;
  FUnitHelpers.Free;
  FPinCalls.Free;
  FPins.Free;
  FAncestors.Free;
  FHelpers.Free;
  inherited;
end;

function TNameResolver.FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Namespace, Key: string;
  Watch: TStopwatch;
begin
  if SameText(AName, FCurrent.UnitName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  // Ohne Index (Schnellbefehle in Tests) nur die eigene Unit.
  if FIndex = nil then
    Exit(False);
  if FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  // Erst alle Schreibweisen im Index (uses SysUtils mit Namespace System → System.SysUtils), dann
  // erst nachladen: EnsureUnit durchsucht die Suchpfade aller Projekte und ist viel teurer (#647).
  for Namespace in FNamespaces do
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) then
      Exit(True);
  if not Assigned(FEnsureUnit) then
    Exit(False);
  Key := UpperCase(AName);
  if (FMissingUnits <> nil) and FMissingUnits.ContainsKey(Key) then
    Exit(False);
  Watch := TStopwatch.StartNew;
  try
    // Der Unit-Resolver probiert die Namespaces selbst (SysUtils → System.SysUtils). Findet er AName
    // nicht, findet er auch Namespace.AName nicht; ein Suchlauf je Namespace kostete bei einer
    // fehlenden Unit ein Vielfaches (#647).
    if FEnsureUnit(AName) then
    begin
      if FIndex.FindUnit(AName, AUnit) then
        Exit(True);
      for Namespace in FNamespaces do
        if FIndex.FindUnit(Namespace + '.' + AName, AUnit) then
          Exit(True);
    end;
  finally
    Inc(FEnsureMs, Watch.ElapsedMilliseconds);
    TRequestDiagnostics.Note('ensureMs', Integer(FEnsureMs));
  end;
  // Diagnoselog (#647): Unit weder im Index noch über die Suchpfade gefunden; je Unit einmal.
  if FMissingUnits = nil then
    FMissingUnits := TDictionary<string, Boolean>.Create;
  FMissingUnits.Add(Key, True);
  TRequestDiagnostics.Increment('missingUnits');
  TRequestDiagnostics.ResolveFailed('unitNotFound');
  Result := False;
end;

function TNameResolver.FindQualifierUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Used, Namespace: string;
begin
  // Jeder Ausdruck wie Form1.Edit1.Text prüft, ob ein Präfix eine Unit ist. Nachladen durchsucht die
  // Suchpfade aller Projekte; das lohnt nur für Units aus uses, alle anderen nur aus dem Index (#647).
  for Used in ScopeUnits(FCurrent, FInImplementation) do
  begin
    if SameText(Used, AName) then
      Exit(FindUnit(AName, AUnit));
    for Namespace in FNamespaces do
      if SameText(Namespace + '.' + Used, AName) then
        Exit(FindUnit(AName, AUnit));
  end;
  if SameText(AName, FCurrent.UnitName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  // Ohne Index (Schnellbefehle in Tests) nur die eigene Unit.
  if FIndex = nil then
    Exit(False);
  if FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  for Namespace in FNamespaces do
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) then
      Exit(True);
  Result := False;
end;

function TNameResolver.UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if AResolved.Kind = TResolvedKind.Local then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  if SameText(AResolved.FileName, FCurrent.FileName) then
  begin
    AUnit := FCurrent;
    Exit(True);
  end;
  Result := (FIndex <> nil) and (FIndex.FindFile(AResolved.FileName, AUnit) or FindUnit(AResolved.UnitName, AUnit));
end;

function TNameResolver.ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
var
  Index, Count: Integer;
begin
  // Viele Aufrufe je Anfrage mit derselben Unit (Code-Review P-17): Das Ergebnis hängt nur an den
  // uses-Arrays, dem Abschnitt und dem Unit-Namen. Die Felder halten die Arrays fest, daher trifft der
  // Zeigervergleich nie ein neu angelegtes Array an derselben Adresse.
  if FScopeValid and (Pointer(AUnit.InterfaceUses) = Pointer(FScopeInterfaceUses)) and
    (Pointer(AUnit.ImplementationUses) = Pointer(FScopeImplementationUses)) and
    (AWithImplementation = FScopeWithImplementation) and SameText(AUnit.UnitName, FScopeUnitName) then
    Exit(FScopeResult);
  // Höchste Priorität zuerst: letzte uses-Einträge gewinnen.
  SetLength(Result, Length(AUnit.ImplementationUses) + Length(AUnit.InterfaceUses) + 1);
  Count := 0;
  if AWithImplementation then
    for Index := High(AUnit.ImplementationUses) downto 0 do
    begin
      Result[Count] := AUnit.ImplementationUses[Index];
      Inc(Count);
    end;
  for Index := High(AUnit.InterfaceUses) downto 0 do
  begin
    Result[Count] := AUnit.InterfaceUses[Index];
    Inc(Count);
  end;
  if not SameText(AUnit.UnitName, 'System') then
  begin
    Result[Count] := 'System';
    Inc(Count);
  end;
  SetLength(Result, Count);
  FScopeInterfaceUses := AUnit.InterfaceUses;
  FScopeImplementationUses := AUnit.ImplementationUses;
  FScopeUnitName := AUnit.UnitName;
  FScopeWithImplementation := AWithImplementation;
  FScopeResult := Result;
  FScopeValid := True;
end;

function TNameResolver.HelperPositions(const AUnit: TUnitIndex): TArray<Integer>;
var
  Key: string;
  Entry: TUnitHelpers;
  Positions: TList<Integer>;
  Position: Integer;
begin
  Key := UpperCase(AUnit.FileName + '|' + AUnit.UnitName);
  if FUnitHelpers.TryGetValue(Key, Entry) and (Pointer(Entry.Symbols) = Pointer(AUnit.Symbols)) then
    Exit(Entry.Positions);
  // Über den Index statt for-in: jede Kopie eines Symbol-Records kostet, und hier laufen alle
  // Symbole aller Units der uses-Liste durch (Diagnoselog 15.10.2026).
  Positions := TList<Integer>.Create;
  try
    for Position := 0 to High(AUnit.Symbols) do
      if (AUnit.Symbols[Position].Kind = TIndexSymbolKind.HelperType) and (AUnit.Symbols[Position].Container = '') and
        (Length(AUnit.Symbols[Position].Ancestors) > 0) then
        Positions.Add(Position);
    Result := Positions.ToArray;
  finally
    Positions.Free;
  end;
  Entry.Symbols := AUnit.Symbols;
  Entry.Positions := Result;
  FUnitHelpers.AddOrSetValue(Key, Entry);
end;

function TNameResolver.TypedProperty(const AType: TResolvedSymbol; const AName: string;
  out AProperty: TResolvedSymbol; out ADepth: Integer): Boolean;
var
  Current, Ancestor: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Position, Depth: Integer;
  TypeName: string;
begin
  AProperty := NoResult;
  ADepth := 0;
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit(False);
    TypeName := Current.QualifiedName;
    for Position := 0 to High(OwnerUnit.Symbols) do
      if (OwnerUnit.Symbols[Position].Kind = TIndexSymbolKind.Property_) and
        (OwnerUnit.Symbols[Position].TypeName <> '') and SameText(OwnerUnit.Symbols[Position].Container, TypeName) and
        SameText(OwnerUnit.Symbols[Position].Name, AName) then
      begin
        AProperty := FromSymbol(OwnerUnit, OwnerUnit.Symbols[Position]);
        ADepth := Depth;
        Exit(True);
      end;
    if not AncestorOf(Current, Ancestor) then
      Exit(False);
    Current := Ancestor;
  end;
  Result := False;
end;

function TNameResolver.FromSymbol(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := ASymbol.Name;
  Result.UnitName := AUnit.UnitName;
  Result.FileName := AUnit.SymbolFile(ASymbol);
  Result.Range := ASymbol.Range;
  Result.SelectionRange := ASymbol.SelectionRange;
  Result.SymbolKind := ASymbol.Kind;
  Result.Container := ASymbol.Container;
  Result.TypeName := ASymbol.TypeName;
  Result.Ancestors := ASymbol.Ancestors;
  Result.IsParameter := False;
  Result.TypeArgs := ASymbol.TypeArgs;
  Result.AncestorArgs := ASymbol.AncestorArgs;
  Result.TypeParams := ASymbol.TypeParams;
  Result.Visibility := ASymbol.Visibility;
  Result.MinArgs := ASymbol.MinArgs;
  Result.MaxArgs := ASymbol.MaxArgs;
  Result.ParamTypes := ASymbol.ParamTypes;
  Result.IsDefault := ASymbol.IsDefault;
  Result.Signature := ASymbol.Signature;
  Result.InInterface := ASymbol.InInterface;
  Result.IsVirtual := ASymbol.IsVirtual;
  Result.Condition := ASymbol.Condition;
  Result.VariantParams := [String.Join(';', ASymbol.ParamTypes)];
end;

function TNameResolver.FromNode(ANode: TSyntaxNode; const AName: string; AKind: TIndexSymbolKind;
  AIsParameter: Boolean): TResolvedSymbol;
var
  Index: Integer;
  Token: TPascalToken;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Local;
  Result.Name := AName;
  Result.UnitName := FCurrent.UnitName;
  Result.FileName := FCurrent.FileName;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.SelectionRange := Result.Range;
  // Auswahl auf den Namen selbst legen; ab dem ersten Token des Knotens, nicht ab Dateianfang: Das
  // kostete je lokalem Namen einen Lauf über alle Tokens davor (Diagnoselog 15.10.2026, große Units).
  for Index := FirstTokenAt(ANode.StartOffset) to High(FTree.Tokens) do
  begin
    Token := FTree.Tokens[Index];
    if Token.Offset >= ANode.EndOffset then
      Break;
    if (Token.Kind = TPascalTokenKind.Identifier) and
      (SameText(Token.Text, AName) or SameText(Token.Text, '&' + AName)) then
    begin
      Result.SelectionRange := TTextRange.Create(Token.StartPos, Token.EndPos);
      Break;
    end;
  end;
  Result.SymbolKind := AKind;
  Result.TypeName := TIndexExtractor.DeclaredType(ANode);
  if Result.TypeName <> '' then
    Result.TypeArgs := TIndexExtractor.GenericArgsText(TIndexExtractor.DeclaredTypeNode(ANode))
  // var X := TFoo.Create; const C = 5; for var I := 0 ...: Typ aus dem Ausdruck.
  else if (ANode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ConstDecl]) and
    (ANode.ChildCount > 0) then
    Result.Initializer := ANode[ANode.ChildCount - 1]
  else if (ANode.Kind = TSyntaxKind.ForStatement) and (ANode.ChildCount > 0) then
    Result.Initializer := ANode[0];
  Result.IsParameter := AIsParameter;
  if AKind in RoutineKinds then
    TIndexExtractor.ParamInfo(ANode, Result.MinArgs, Result.MaxArgs, Result.ParamTypes);
end;

function TNameResolver.LookupInUnit(const AUnit: TUnitIndex; const AName: string;
  AOnlyInterface, AOnlyTypes: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  Symbol: TIndexSymbol;
  Pass, Position: Integer;
  Positions: TArray<Integer>;
begin
  // Über die Namenstabelle statt linear durch alle Symbole (Diagnoselog 15.10.2026).
  Positions := AUnit.SymbolsNamed(AName);
  // Mit Typargumenten nur generische Typen passender Stelligkeit; ohne zuerst nicht generische.
  for Pass := 0 to 1 do
  begin
    for Position in Positions do
    begin
      Symbol := AUnit.Symbols[Position];
      if AOnlyInterface and not Symbol.InInterface then
        Continue;
      if AOnlyTypes and not (Symbol.Kind in TypeKinds) then
        Continue;
      // Unit-Ebene; Enum-Werte sind ohne SCOPEDENUMS auch dort sichtbar.
      if (Symbol.Container <> '') and (Symbol.Kind <> TIndexSymbolKind.EnumMember) then
        Continue;
      if AOnlyTypes and (AArity > 0) and (Length(SplitArgs(Symbol.TypeParams)) <> AArity) then
        Continue;
      if AOnlyTypes and (AArity = 0) and (Pass = 0) and (Symbol.TypeParams <> '') then
        Continue;
      AResult := FromSymbol(AUnit, Symbol);
      Exit(True);
    end;
    if not (AOnlyTypes and (AArity = 0)) then
      Break;
  end;
  Result := False;
end;

function TNameResolver.LookupGlobal(const AUnit: TUnitIndex; const AName: string;
  AWithImplementation, AOnlyTypes: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  UnitName: string;
  Used: TUnitIndex;
begin
  if LookupInUnit(AUnit, AName, not AWithImplementation, AOnlyTypes, AResult, AArity) then
    Exit(True);
  for UnitName in ScopeUnits(AUnit, AWithImplementation) do
    if FindUnit(UnitName, Used) and LookupInUnit(Used, AName, True, AOnlyTypes, AResult, AArity) then
      Exit(True);
  Result := False;
end;

function TNameResolver.ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  Dot: Integer;
  Qualifier: TUnitIndex;
begin
  Result := False;
  if ATypeName = '' then
    Exit;
  // Unit.Typ
  Dot := LastDelimiter('.', ATypeName);
  if Dot > 0 then
  begin
    if FindUnit(Copy(ATypeName, 1, Dot - 1), Qualifier) then
      Exit(LookupInUnit(Qualifier, Copy(ATypeName, Dot + 1, MaxInt), not SameText(Qualifier.FileName, FCurrent.FileName),
        True, AResult, AArity));
    Exit;
  end;
  Result := LookupGlobal(AFromUnit, ATypeName, AWithImplementation, True, AResult, AArity);
end;

function TNameResolver.ResolveTypeText(const AText: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol): Boolean;
var
  Base, Args: string;
  ArgList: TArray<string>;
  Index: Integer;
begin
  SplitGeneric(AText, Base, Args);
  ArgList := SplitArgs(Args);
  Result := ResolveTypeName(Base, AFromUnit, AWithImplementation, AResult, Length(ArgList));
  if not Result then
  begin
    if (Args = '') and IsBuiltinName(Base) then
    begin
      AResult := BuiltinType(Base);
      Result := True;
    end;
    Exit;
  end;
  if Length(ArgList) > 0 then
  begin
    // Typargumente gelten dort, wo sie stehen: vor dem Einsetzen in fremden Units qualifizieren.
    for Index := 0 to High(ArgList) do
      ArgList[Index] := QualifyType(ArgList[Index], AFromUnit, AWithImplementation);
    AResult.Bindings := Bind(AResult.TypeParams, ArgList);
  end;
end;

function TNameResolver.QualifyType(const AText: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean): string;
var
  Base, Args: string;
  ArgList: TArray<string>;
  Resolved: TResolvedSymbol;
  Index: Integer;
begin
  SplitGeneric(AText, Base, Args);
  ArgList := SplitArgs(Args);
  Result := Base;
  if (Pos('.', Base) = 0) and ResolveTypeName(Base, AFromUnit, AWithImplementation, Resolved, Length(ArgList)) and
    (Resolved.Kind = TResolvedKind.Symbol) and (Resolved.Container = '') then
    Result := Resolved.UnitName + '.' + Resolved.Name;
  if Length(ArgList) > 0 then
  begin
    for Index := 0 to High(ArgList) do
      ArgList[Index] := QualifyType(ArgList[Index], AFromUnit, AWithImplementation);
    Result := Result + '<' + string.Join(',', ArgList) + '>';
  end;
end;

function TNameResolver.TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  Current, Next, Value: TResolvedSymbol;
  FromUnit: TUnitIndex;
  Depth: Integer;
  WithImplementation: Boolean;
  SavedOffset: Integer;
begin
  Result := False;
  // Typen sind ihr eigener Typ; Aliase werden verfolgt.
  if AResolved.IsType then
    Current := AResolved
  else if Length(AResolved.Constructed) > 0 then
    Current := AResolved.Constructed[0]
  else if (AResolved.SymbolKind = TIndexSymbolKind.Constructor_) and (AResolved.Container <> '') then
  begin
    // TFoo.Create liefert ein TFoo.
    if not UnitOf(AResolved, FromUnit) or
      not ResolveTypeName(AResolved.Container, FromUnit, SameText(FromUnit.FileName, FCurrent.FileName), Current) then
      Exit;
    Current.Bindings := AResolved.Bindings;
  end
  else if AResolved.TypeName = '' then
  begin
    // Inline-Variable ohne Typangabe: Typ des Ausdrucks.
    if (AResolved.Initializer = nil) or (FInferDepth >= MaxInferDepth) or (FTree = nil) then
      Exit;
    SavedOffset := FOffset;
    Inc(FInferDepth);
    try
      FOffset := AResolved.Initializer.StartOffset;
      if not ExprSymbol(AResolved.Initializer, Value) or not TypeOf(Value, Current) then
        Exit;
    finally
      Dec(FInferDepth);
      FOffset := SavedOffset;
    end;
  end
  else
  begin
    if not UnitOf(AResolved, FromUnit) then
      Exit;
    WithImplementation := (AResolved.Kind = TResolvedKind.Local) or
      (SameText(FromUnit.FileName, FCurrent.FileName) and FInImplementation);
    if not ResolveTypeText(Substitute(FullType(AResolved.TypeName, AResolved.TypeArgs), AResolved.Bindings),
      FromUnit, WithImplementation, Current) then
      Exit;
  end;
  Depth := 0;
  while not Current.Builtin and (Current.SymbolKind = TIndexSymbolKind.TypeAlias) and (Current.TypeName <> '') and
    (Depth < MaxDepth) do
  begin
    // Eigene Variable: der out-Parameter würde Current.TypeName vor dem Aufruf leeren.
    if not UnitOf(Current, FromUnit) or
      not ResolveTypeText(Substitute(FullType(Current.TypeName, Current.TypeArgs), Current.Bindings), FromUnit,
        SameText(FromUnit.FileName, FCurrent.FileName), Next) then
      Exit;
    Current := Next;
    Inc(Depth);
  end;
  AType := Current;
  Result := True;
end;

function TNameResolver.AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
var
  FromUnit: TUnitIndex;
  Name, Key: string;
  WithImplementation: Boolean;
begin
  Result := False;
  if AType.Builtin or not UnitOf(AType, FromUnit) then
    Exit;
  if Length(AType.Ancestors) > 0 then
    Name := Substitute(FullType(AType.Ancestors[0], AType.AncestorArgs), AType.Bindings)
  else if (AType.SymbolKind = TIndexSymbolKind.ClassType) and not SameText(AType.Name, 'TObject') then
    Name := 'TObject'
  else if (AType.SymbolKind = TIndexSymbolKind.InterfaceType) and not SameText(AType.Name, 'IInterface') then
    Name := 'IInterface'
  else
    Exit;
  // Helfer: der "Vorfahr" ist der erweiterte Typ, nicht der Elterntyp.
  if AType.SymbolKind = TIndexSymbolKind.HelperType then
    Exit;
  // Die Sichtbarkeit des implementation-Teils gehört zum Schlüssel: Der Cache überdauert ResolveTypeFrom
  // (Code-Review P-17), dort ist FCurrent eine andere Unit.
  WithImplementation := SameText(FromUnit.FileName, FCurrent.FileName);
  Key := UpperCase(FromUnit.FileName + '|' + AType.QualifiedName + '|' + Name) + '|' +
    BoolToStr(WithImplementation, True);
  if FAncestors.TryGetValue(Key, AAncestor) then
    Exit(AAncestor.Found);
  Result := ResolveTypeText(Name, FromUnit, WithImplementation, AAncestor) and
    not AAncestor.Builtin and not SameText(AAncestor.QualifiedName, AType.QualifiedName);
  if not Result then
    AAncestor := NoResult;
  FAncestors.AddOrSetValue(Key, AAncestor);
end;

/// <summary>Stammt die Klasse von TCustomAttribute ab? Bricht die Kette an einem unbekannten Vorfahren ab,
/// gilt sie als Attribut; endet sie bei TObject, nicht.</summary>
function TNameResolver.IsAttributeClass(const AType: TResolvedSymbol): Boolean;
var
  Current, Next: TResolvedSymbol;
  Depth: Integer;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    if SameText(Current.Name, 'TCustomAttribute') then
      Exit(True);
    if (Length(Current.Ancestors) = 0) or SameText(Current.Ancestors[0], 'TObject') or
      SameText(Current.Ancestors[0], 'System.TObject') then
      Exit(False);
    if not AncestorOf(Current, Next) then
      Exit(True);
    Current := Next;
  end;
  Result := True;
end;

function TNameResolver.CurrentClass(out AType: TResolvedSymbol): Boolean;
begin
  // Einmal je Prepare: Klasse der umgebenden Methode.
  if FClassState = 0 then
  begin
    if (FTree <> nil) and MethodClass(FClass) then
      FClassState := 2
    else
      FClassState := 1;
  end;
  AType := FClass;
  Result := FClassState = 2;
end;

function TNameResolver.DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
var
  Current, Next: TResolvedSymbol;
  Depth: Integer;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    if SameText(Current.QualifiedName, AAncestor.QualifiedName) and SameText(Current.UnitName, AAncestor.UnitName) then
      Exit(True);
    if not AncestorOf(Current, Next) then
      Exit(False);
    Current := Next;
  end;
  Result := False;
end;

function TNameResolver.IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex;
  const AOwner: TResolvedSymbol): Boolean;
var
  SameUnit: Boolean;
  Own: TResolvedSymbol;
begin
  SameUnit := SameText(AOwnerUnit.FileName, FCurrent.FileName);
  // Aus anderen Units sind nur Deklarationen im interface sichtbar, keine Rümpfe.
  if not SameUnit and not ASymbol.InInterface then
    Exit(False);
  case ASymbol.Visibility of
    TIndexVisibility.Private:
      Result := SameUnit;
    TIndexVisibility.StrictPrivate:
      Result := SameUnit and CurrentClass(Own) and SameText(Own.QualifiedName, AOwner.QualifiedName);
    TIndexVisibility.Protected:
      Result := SameUnit or (CurrentClass(Own) and DescendsFrom(Own, AOwner));
    TIndexVisibility.StrictProtected:
      Result := CurrentClass(Own) and DescendsFrom(Own, AOwner);
  else
    Result := True;
  end;
end;

function TNameResolver.HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
var
  Key, Target, UnitName: string;
  Units: TList<TUnitIndex>;
  Used: TUnitIndex;
  Position: Integer;
  Found: Boolean;
  Candidate: TResolvedSymbol;

  function Matches(const AName: string): Boolean;
  var
    Dot: Integer;
  begin
    Dot := LastDelimiter('.', AName);
    Result := SameText(Copy(AName, Dot + 1, MaxInt), Target) or
      (MatchText(Target, ['string', 'UnicodeString']) and MatchText(Copy(AName, Dot + 1, MaxInt), ['string', 'UnicodeString']));
  end;

begin
  Target := AType.Name;
  // Welche Helfer sichtbar sind, hängt an der Unit und am Abschnitt (uses von interface bzw.
  // implementation); der Cache überdauert ResolveTypeFrom und Abschnittswechsel (Code-Review P-17).
  Key := UpperCase(AType.UnitName + '.' + AType.QualifiedName + '|' + FCurrent.FileName + '|' +
    FCurrent.UnitName) + '|' + BoolToStr(FInImplementation, True);
  if FHelpers.TryGetValue(Key, AHelper) then
    Exit(AHelper.Found);
  AHelper := NoResult;
  // Nur der zuletzt sichtbare Helfer wirkt: eigene Unit, dann uses von hinten; in einer Unit der letzte.
  Units := TList<TUnitIndex>.Create;
  try
    Units.Add(FCurrent);
    for UnitName in ScopeUnits(FCurrent, FInImplementation) do
      if FindUnit(UnitName, Used) then
        Units.Add(Used);
    for Used in Units do
    begin
      Found := False;
      // Nur die vorab ermittelten Helfer-Typen der Unit prüfen statt aller Symbole (Code-Review P-17).
      for Position in HelperPositions(Used) do
        if Matches(Used.Symbols[Position].Ancestors[High(Used.Symbols[Position].Ancestors)]) and
          (Used.Symbols[Position].InInterface or SameText(Used.FileName, FCurrent.FileName)) then
        begin
          Candidate := FromSymbol(Used, Used.Symbols[Position]);
          Found := True;
        end;
      if Found then
      begin
        AHelper := Candidate;
        Break;
      end;
    end;
  finally
    Units.Free;
  end;
  FHelpers.AddOrSetValue(Key, AHelper);
  Result := AHelper.Found;
end;

function TNameResolver.FindMembers(const AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
var
  Current, Ancestor, Helper, Found: TResolvedSymbol;
  OwnerUnit, HelperUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Depth, Position: Integer;
  TypeName: string;
  Hidden: Boolean;
begin
  Result := nil;
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    // Helfer zuerst: ihre Mitglieder verdecken gleichnamige des Typs.
    if HelperFor(Current, Helper) and UnitOf(Helper, HelperUnit) then
    begin
      for Position in HelperUnit.SymbolsNamed(AName) do
      begin
        Symbol := HelperUnit.Symbols[Position];
        if SameText(Symbol.Container, Helper.QualifiedName) and IsVisible(Symbol, HelperUnit, Helper) then
        begin
          Found := FromSymbol(HelperUnit, Symbol);
          Found.Bindings := Current.Bindings;
          AddDistinct(Result, Found);
        end;
      end;
      if Result <> nil then
        Exit;
    end;
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit;
    TypeName := Current.QualifiedName;
    Hidden := False;
    // Erste Fundstelle: die Deklaration im Typ steht vor dem Rumpf in implementation.
    for Position in OwnerUnit.SymbolsNamed(AName) do
    begin
      Symbol := OwnerUnit.Symbols[Position];
      if SameText(Symbol.Container, TypeName) then
      begin
        // Ist die Deklaration unsichtbar, gilt das auch für ihren Rumpf.
        if Hidden or not IsVisible(Symbol, OwnerUnit, Current) then
        begin
          Hidden := True;
          Continue;
        end;
        Found := FromSymbol(OwnerUnit, Symbol);
        Found.Bindings := Current.Bindings;
        AddDistinct(Result, Found);
      end;
    end;
    if Result <> nil then
      Exit;
    if not AncestorOf(Current, Ancestor) then
      Exit;
    Current := Ancestor;
  end;
end;

function TNameResolver.FindMember(const AType: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Members: TArray<TResolvedSymbol>;
begin
  Members := FindMembers(AType, AName);
  Result := Length(Members) > 0;
  if Result then
    AResult := Members[0];
end;

function TNameResolver.DefaultProperty(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
var
  Current, Ancestor: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Depth: Integer;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit(False);
    for Symbol in OwnerUnit.Symbols do
      if Symbol.IsDefault and (Symbol.Kind = TIndexSymbolKind.Property_) and
        SameText(Symbol.Container, Current.QualifiedName) and IsVisible(Symbol, OwnerUnit, Current) then
      begin
        AResult := FromSymbol(OwnerUnit, Symbol);
        AResult.Bindings := Current.Bindings;
        Exit(True);
      end;
    if not AncestorOf(Current, Ancestor) then
      Exit(False);
    Current := Ancestor;
  end;
  Result := False;
end;

function TNameResolver.UnitRoutines(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  Position: Integer;
  SameUnit: Boolean;
begin
  // Überladene freie Routinen derselben Unit; bei verschachtelten Routinen die der umgebenden Routine (#881).
  if (ASymbol.Kind = TResolvedKind.Local) and (ASymbol.SymbolKind = TIndexSymbolKind.Routine) then
    Exit(LocalOverloads(ASymbol));
  Result := [ASymbol];
  if (ASymbol.Kind <> TResolvedKind.Symbol) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) or
    (ASymbol.Container <> '') or not UnitOf(ASymbol, Owner) then
    Exit;
  SameUnit := SameText(Owner.FileName, FCurrent.FileName);
  for Position in Owner.SymbolsNamed(ASymbol.Name) do
  begin
    Symbol := Owner.Symbols[Position];
    if (Symbol.Kind = TIndexSymbolKind.Routine) and (Symbol.Container = '') and (SameUnit or Symbol.InInterface) then
      AddDistinct(Result, FromSymbol(Owner, Symbol));
  end;
end;

function TNameResolver.LocalOverloads(const ASymbol: TResolvedSymbol): TArray<TResolvedSymbol>;

  function Search(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.StartPos = ASymbol.Range.StartPos) and
      SameText(ANode.Name, ASymbol.Name) then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Result := Search(ANode[Index]);
      if Result <> nil then
        Exit;
    end;
    Result := nil;
  end;

var
  Node, Parent, Sibling: TSyntaxNode;
  Index: Integer;
begin
  Result := [ASymbol];
  if (ASymbol.Kind <> TResolvedKind.Local) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) or (FTree = nil) then
    Exit;
  Node := Search(FTree.Root);
  if (Node = nil) or (Node.Parent = nil) then
    Exit;
  Parent := Node.Parent;
  // Überladungen stehen in derselben umgebenden Routine, vor oder hinter ASymbol; in der Reihenfolge der
  // Deklaration, unabhängig davon, welche die Auflösung gewählt hat.
  Result := nil;
  for Index := 0 to Parent.ChildCount - 1 do
  begin
    Sibling := Parent[Index];
    if Sibling = Node then
      AddDistinct(Result, ASymbol)
    else if (Sibling.Kind = TSyntaxKind.RoutineDecl) and SameText(Sibling.Name, ASymbol.Name) then
      AddDistinct(Result, FromNode(Sibling, Sibling.Name, TIndexSymbolKind.Routine, False));
  end;
end;

function TNameResolver.EnclosingRoutines: TArray<TSyntaxNode>;
var
  Path: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  // Innerste Routine zuerst; anonyme Methoden zählen mit, ihre Parameter und lokalen Variablen
  // verdecken gleichnamige Felder wie die einer benannten Routine.
  Path := TList<TSyntaxNode>.Create;
  try
    Node := FTree.Root;
    repeat
      Descended := False;
      for Index := 0 to Node.ChildCount - 1 do
        if Contains(Node[Index], FOffset) then
        begin
          Node := Node[Index];
          if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
            Path.Insert(0, Node);
          Descended := True;
          Break;
        end;
    until not Descended;
    Result := Path.ToArray;
  finally
    Path.Free;
  end;
end;

function TNameResolver.LookupInDeclarations(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
  Kind: TIndexSymbolKind;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    case Child.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        if LookupInDeclarations(Child, AName, AResult) then
          Exit(True);
      TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
        for Name in Child.Name.Split([',']) do
          if SameText(Name.Trim, AName) then
          begin
            if Child.Kind = TSyntaxKind.VarDecl then
              Kind := TIndexSymbolKind.Variable
            else
              Kind := TIndexSymbolKind.Constant;
            AResult := FromNode(Child, Name.Trim, Kind, False);
            Exit(True);
          end;
      TSyntaxKind.TypeDecl:
        if SameText(Child.Name, AName) then
        begin
          AResult := FromNode(Child, Child.Name, TIndexSymbolKind.TypeAlias, False);
          Exit(True);
        end;
      TSyntaxKind.RoutineDecl:
        if SameText(Child.Name, AName) then
        begin
          AResult := FromNode(Child, Child.Name, TIndexSymbolKind.Routine, False);
          Exit(True);
        end;
    end;
  end;
  Result := False;
end;

function TNameResolver.IsForVar(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  // for var I := ...: das Wort nach "for" ist "var".
  Index := FirstTokenAt(ANode.StartOffset);
  Result := (Index < High(FTree.Tokens)) and FTree.Tokens[Index].IsKeyword('for') and
    FTree.Tokens[Index + 1].IsKeyword('var');
end;

function TNameResolver.FirstTokenAt(AOffset: Integer): Integer;
var
  Low, High_, Middle: Integer;
begin
  // Binäre Suche: erstes Token mit Offset >= AOffset; Length(Tokens), wenn es keines gibt.
  Low := 0;
  High_ := Length(FTree.Tokens);
  while Low < High_ do
  begin
    Middle := (Low + High_) div 2;
    if FTree.Tokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High_ := Middle;
  end;
  Result := Low;
end;

function TNameResolver.LookupInlineVars(ANode: TSyntaxNode; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
begin
  // Inline-Variablen gelten ab ihrer Deklaration; verschachtelte Routinen nicht durchsuchen.
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.StartOffset > FOffset then
      Break;
    if Child.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    begin
      for Name in Child.Name.Split([',']) do
        if SameText(Name.Trim, AName) then
        begin
          AResult := FromNode(Child, Name.Trim, TIndexSymbolKind.Variable, False);
          Exit(True);
        end;
    end
    else if (Child.Kind <> TSyntaxKind.RoutineDecl) and Contains(Child, FOffset) then
    begin
      // for var I := ...: gilt nur in der Schleife.
      if (Child.Kind = TSyntaxKind.ForStatement) and SameText(Child.Name, AName) and IsForVar(Child) then
      begin
        AResult := FromNode(Child, Child.Name, TIndexSymbolKind.Variable, False);
        Exit(True);
      end;
      if LookupInlineVars(Child, AName, AResult) then
        Exit(True);
    end;
  end;
  Result := False;
end;

function TNameResolver.LookupLocal(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  Routine, Header, Params, Param: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  for Routine in EnclosingRoutines do
  begin
    if LookupInlineVars(Routine, AName, AResult) then
      Exit(True);
    Header := RoutineHeaderOf(Routine);
    if Header <> nil then
    begin
      Params := Header.FindChild(TSyntaxKind.Parameters);
      if Params <> nil then
        for Index := 0 to Params.ChildCount - 1 do
        begin
          Param := Params[Index];
          if Param.Kind <> TSyntaxKind.Parameter then
            Continue;
          for Name in Param.Name.Split([',']) do
            if SameText(Name.Trim, AName) then
            begin
              AResult := FromNode(Param, Name.Trim, TIndexSymbolKind.Variable, True);
              Exit(True);
            end;
        end;
      if SameText(AName, 'Result') and (Header.FindChild(TSyntaxKind.TypeReference) <> nil) then
      begin
        AResult := FromNode(Header, 'Result', TIndexSymbolKind.Variable, False);
        AResult.SelectionRange := AResult.Range;
        Exit(True);
      end;
    end;
    if LookupInDeclarations(Routine, AName, AResult) then
      Exit(True);
  end;
  Result := False;
end;

function TNameResolver.MethodClass(out AType: TResolvedSymbol): Boolean;
var
  Classes: TArray<TResolvedSymbol>;
begin
  Classes := MethodClasses;
  Result := Length(Classes) > 0;
  if Result then
    AType := Classes[0];
end;

function TNameResolver.MethodClasses: TArray<TResolvedSymbol>;
var
  Routines: TArray<TSyntaxNode>;
  Name, TypeName: string;
  Parts: TArray<string>;
  Dot, Index: Integer;
  Current, Inner: TResolvedSymbol;
begin
  // Äußerste Routine mit Punkt im Namen: procedure TFoo.Bar
  Result := nil;
  if FTree = nil then
    Exit;
  Routines := EnclosingRoutines;
  if Length(Routines) = 0 then
    Exit;
  Name := Routines[High(Routines)].Name;
  Dot := LastDelimiter('.', Name);
  if Dot = 0 then
    Exit;
  TypeName := Copy(Name, 1, Dot - 1);
  // Verschachtelte Typen zuerst (procedure TAussen.TInnen.Methode): TAussen.TInnen sonst als Unit
  // TAussen gesucht, mit Nachladen über alle Suchpfade, und die Felder blieben unaufgelöst (#647).
  Parts := TypeName.Split(['.']);
  if (Length(Parts) > 1) and ResolveTypeName(Parts[0], FCurrent, True, Current) then
  begin
    Result := [Current];
    for Index := 1 to High(Parts) do
    begin
      if not FindMember(Current, Parts[Index], Inner) then
      begin
        Result := nil;
        Break;
      end;
      Current := Inner;
      Result := [Current] + Result;
    end;
    if Result <> nil then
      Exit;
  end;
  if ResolveTypeName(TypeName, FCurrent, True, Current) then
    Result := [Current];
end;

class function TNameResolver.IsBuiltinTypeName(const AName: string): Boolean;
begin
  Result := IsBuiltinName(AName) or MatchText(AName, ['PChar', 'PAnsiChar', 'PWideChar', 'OleVariant']);
end;

function TNameResolver.HasUnknownAncestor: Boolean;
var
  Current, Next, Ancestor: TResolvedSymbol;
  Depth: Integer;
begin
  for Current in MethodClasses do
  begin
    Next := Current;
    for Depth := 0 to MaxDepth do
    begin
      if (Length(Next.Ancestors) = 0) or SameText(Next.Ancestors[0], 'TObject') or
        SameText(Next.Ancestors[0], 'System.TObject') then
        Break;
      if not AncestorOf(Next, Ancestor) then
        Exit(True);
      Next := Ancestor;
    end;
  end;
  Result := False;
end;

function TNameResolver.IsUnitPrefix(const AName: string): Boolean;
var
  UnitName, Namespace: string;
begin
  if StartsText(AName + '.', FCurrent.UnitName) then
    Exit(True);
  for UnitName in ScopeUnits(FCurrent, FInImplementation) do
  begin
    if StartsText(AName + '.', UnitName) then
      Exit(True);
    for Namespace in FNamespaces do
      if StartsText(AName + '.', Namespace + '.' + UnitName) then
        Exit(True);
  end;
  Result := False;
end;

function TNameResolver.ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer;
  out AResult: TResolvedSymbol): Boolean;
var
  ClassType: TResolvedSymbol;
  Classes: TArray<TResolvedSymbol>;
  Count: Integer;
  UnitName: string;
  Found: TUnitIndex;
begin
  AConsumed := 1;
  if LookupLocal(ANames[0], AResult) then
    Exit(True);
  Classes := MethodClasses;
  if Length(Classes) > 0 then
  begin
    if SameText(ANames[0], 'Self') then
    begin
      AResult := Classes[0];
      Exit(True);
    end;
    // Innerster Typ zuerst, dann die äußeren (verschachtelte Typen sehen deren Mitglieder).
    for ClassType in Classes do
      if FindMember(ClassType, ANames[0], AResult) then
        Exit(True);
  end;
  // Unit-Namen mit Punkten: längstes Präfix zuerst (System.SysUtils.Foo). Der
  // ganze Ausdruck zählt mit, sonst bleibt "Vcl.Werkzeug" in uses unaufgelöst.
  for Count := Length(ANames) downto 2 do
  begin
    UnitName := string.Join('.', Copy(ANames, 0, Count));
    if FindQualifierUnit(UnitName, Found) then
    begin
      AConsumed := Count;
      AResult := NoResult;
      AResult.Kind := TResolvedKind.UnitName;
      AResult.Name := Found.UnitName;
      AResult.UnitName := Found.UnitName;
      AResult.FileName := Found.FileName;
      Exit(True);
    end;
  end;
  if LookupGlobal(FCurrent, ANames[0], FInImplementation, False, AResult) then
    Exit(True);
  if FindQualifierUnit(ANames[0], Found) then
  begin
    AResult := NoResult;
    AResult.Kind := TResolvedKind.UnitName;
    AResult.Name := Found.UnitName;
    AResult.UnitName := Found.UnitName;
    AResult.FileName := Found.FileName;
    Exit(True);
  end;
  Result := False;
end;

function TNameResolver.FindReceiver(AEndOffset: Integer): TSyntaxNode;

  function Search(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    // Äußerster Ausdruck, der genau vor dem Punkt endet.
    if (ANode.Kind in ExpressionKinds) and (ANode.EndOffset = AEndOffset) then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.StartOffset < AEndOffset) and (AEndOffset <= Child.EndOffset) then
      begin
        Result := Search(Child);
        if Result <> nil then
          Exit;
      end;
    end;
    Result := nil;
  end;

begin
  Result := Search(FTree.Root);
end;

function TNameResolver.FindCall(ACalleeEnd: Integer): TSyntaxNode;

  function Search(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and (ANode[0].EndOffset = ACalleeEnd) then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.StartOffset < ACalleeEnd) and (ACalleeEnd <= Child.EndOffset) then
      begin
        Result := Search(Child);
        if Result <> nil then
          Exit;
      end;
    end;
    Result := nil;
  end;

begin
  Result := Search(FTree.Root);
end;

function TNameResolver.ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
var
  Index: Integer;
  Arg: TSyntaxNode;
  Value, TypeInfo: TResolvedSymbol;
  Text: string;
begin
  Result := nil;
  for Index := AFirst to ANode.ChildCount - 1 do
  begin
    Arg := ANode[Index];
    if Arg.Kind = TSyntaxKind.GenericArgs then
      Continue;
    Text := '';
    if Arg.Kind = TSyntaxKind.SetConstructor then
      Text := '[]'
    else if ExprSymbol(Arg, Value) and TypeOf(Value, TypeInfo) then
      Text := TypeInfo.Name;
    Result := Result + [Text];
  end;
end;

function TNameResolver.ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  Owner, TypeInfo, Single: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Consumed, SavedOffset, Index: Integer;
begin
  Result := nil;
  case ANode.Kind of
    TSyntaxKind.Identifier:
      begin
        SavedOffset := FOffset;
        FOffset := ANode.StartOffset;
        try
          if not ResolveFirstAll([ANode.Name], Consumed, Result) then
            Result := nil;
        finally
          FOffset := SavedOffset;
        end;
      end;
    TSyntaxKind.MemberAccess:
      if (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) and (ANode.ChildCount > 0) then
      begin
        if not ExprSymbol(ANode[0], Owner) then
          Exit;
        if Owner.Kind = TResolvedKind.UnitName then
        begin
          if FindUnit(Owner.UnitName, OwnerUnit) and
            LookupInUnit(OwnerUnit, ANode.Name, not SameText(OwnerUnit.FileName, FCurrent.FileName), False, Single) then
            Result := UnitRoutines(Single);
        end
        else if TypeOf(Owner, TypeInfo) then
        begin
          Result := FindMembers(TypeInfo, ANode.Name);
          // TKunde.Create liefert TKunde, auch wenn Create aus TObject stammt.
          if Owner.IsType then
            for Index := 0 to High(Result) do
              if Result[Index].SymbolKind = TIndexSymbolKind.Constructor_ then
                Result[Index].Constructed := [TypeInfo];
        end;
      end
      else if ExprSymbol(ANode, Single) then
        Result := [Single];
  else
    if ExprSymbol(ANode, Single) then
      Result := [Single];
  end;
end;

function TNameResolver.ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  Candidates: TArray<TResolvedSymbol>;
  Base, TypeInfo, Element: TResolvedSymbol;
  Args: TSyntaxNode;
  Text: string;
  Arguments: TArray<string>;
  FromUnit: TUnitIndex;
  Index: Integer;
begin
  Result := False;
  if (ANode = nil) or (FInferDepth > MaxInferDepth * 4) then
    Exit;
  Inc(FInferDepth);
  try
    case ANode.Kind of
      TSyntaxKind.Identifier:
        begin
          Candidates := ExprCandidates(ANode);
          Result := Length(Candidates) > 0;
          if Result then
            AResult := Candidates[0];
        end;
      TSyntaxKind.MemberAccess:
        begin
          Args := ANode.FindChild(TSyntaxKind.GenericArgs);
          if (Args <> nil) and (ANode.ChildCount > 0) and (ANode[0] <> Args) then
          begin
            // Foo<Integer>: Typargumente an die Typparameter der Methode binden.
            if not ExprSymbol(ANode[0], AResult) then
              Exit;
            Arguments := nil;
            for Index := 0 to Args.ChildCount - 1 do
              Arguments := Arguments + [QualifyType(TIndexExtractor.TypeText(Args[Index]), FCurrent, FInImplementation)];
            AResult.Bindings := AResult.Bindings + Bind(AResult.TypeParams, Arguments);
            Exit(True);
          end;
          Candidates := ExprCandidates(ANode);
          Result := Length(Candidates) > 0;
          if Result then
            AResult := Candidates[0];
        end;
      TSyntaxKind.Call:
        begin
          if ANode.ChildCount = 0 then
            Exit;
          Candidates := ExprCandidates(ANode[0]);
          if Length(Candidates) = 0 then
            Exit;
          // TFoo(X) ist eine Typumwandlung.
          if Candidates[0].IsType then
          begin
            AResult := Candidates[0];
            Exit(True);
          end;
          Candidates := SelectOverloads(Candidates, ANode.ChildCount - 1, ArgTypes(ANode, 1));
          AResult := Candidates[0];
          Result := True;
        end;
      TSyntaxKind.IndexAccess:
        begin
          if (ANode.ChildCount = 0) or not ExprSymbol(ANode[0], Base) then
            Exit;
          // Liste.Items[i]: die indizierte Property selbst.
          if (Base.SymbolKind = TIndexSymbolKind.Property_) and (Base.MaxArgs > 0) then
          begin
            AResult := Base;
            Exit(True);
          end;
          if not TypeOf(Base, TypeInfo) then
            Exit;
          if DefaultProperty(TypeInfo, AResult) then
            Exit(True);
          if TypeInfo.Builtin and MatchText(TypeInfo.Name, StringTypes) then
          begin
            AResult := BuiltinType('Char');
            Exit(True);
          end;
          // TArray<T>[i]: das Element.
          if SameText(TypeInfo.Name, 'TArray') and (Length(TypeInfo.Bindings) > 0) then
          begin
            Text := TypeInfo.Bindings[0];
            Text := Copy(Text, Pos('=', Text) + 1, MaxInt);
            if UnitOf(TypeInfo, FromUnit) and ResolveTypeText(Text, FromUnit, True, Element) then
            begin
              AResult := Element;
              Exit(True);
            end;
          end;
        end;
      TSyntaxKind.ParenExpr:
        Result := (ANode.ChildCount > 0) and ExprSymbol(ANode[0], AResult);
      TSyntaxKind.BinaryExpr:
        // (X as TBar): der Zieltyp.
        if SameText(ANode.Name, 'as') and (ANode.ChildCount = 2) then
          Result := ExprSymbol(ANode[1], AResult) and AResult.IsType;
      TSyntaxKind.IfExpr:
        Result := (ANode.ChildCount >= 2) and ExprSymbol(ANode[1], AResult);
      TSyntaxKind.Literal:
        begin
          Text := ANode.Name;
          if Text = '' then
            Exit;
          if CharInSet(Text[1], ['''', '#']) then
            AResult := BuiltinType('string')
          else if CharInSet(Text[1], ['0'..'9', '$', '%']) then
          begin
            if (Text[1] <> '$') and ((Pos('.', Text) > 0) or (Pos('E', UpperCase(Text)) > 0)) then
              AResult := BuiltinType('Double')
            else
              AResult := BuiltinType('Integer');
          end
          else
            Exit;
          Result := True;
        end;
    end;
  finally
    Dec(FInferDepth);
  end;
end;

function TNameResolver.LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>;
  out AStop: Boolean): Boolean;
var
  WithNode: TSyntaxNode;
  Element: Integer;
begin
  Result := LookupWithOwner(AName, AResults, AStop, WithNode, Element);
end;

function TNameResolver.WithMember(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer;
  out AWith: TSyntaxNode; out AElement: Integer; out AUnknown: Boolean): Boolean;
var
  Results: TArray<TResolvedSymbol>;
begin
  Prepare(ATree, AFileName, AOffset);
  Result := LookupWithOwner(AName, Results, AUnknown, AWith, AElement);
end;

function TNameResolver.LookupWithOwner(const AName: string; out AResults: TArray<TResolvedSymbol>;
  out AStop: Boolean; out AWith: TSyntaxNode; out AElement: Integer): Boolean;
var
  Withs: TList<TSyntaxNode>;
  Node, WithNode: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
  Value, TypeInfo: TResolvedSymbol;
  SavedOffset: Integer;
  Known: Boolean;
begin
  Result := False;
  AStop := False;
  AResults := nil;
  AWith := nil;
  AElement := -1;
  if FTree = nil then
    Exit;
  // with-Anweisungen, in deren Rumpf FOffset liegt, innerste zuerst.
  Withs := TList<TSyntaxNode>.Create;
  try
    Node := FTree.Root;
    repeat
      Descended := False;
      for Index := 0 to Node.ChildCount - 1 do
        if Contains(Node[Index], FOffset) then
        begin
          Node := Node[Index];
          if (Node.Kind = TSyntaxKind.WithStatement) and (Node.ChildCount >= 2) and
            Contains(Node[Node.ChildCount - 1], FOffset) then
            Withs.Insert(0, Node);
          Descended := True;
          Break;
        end;
    until not Descended;
    for WithNode in Withs do
      for Index := WithNode.ChildCount - 2 downto 0 do
      begin
        // Den Ausdruck an seiner eigenen Stelle auflösen, außerhalb des with-Rumpfs.
        SavedOffset := FOffset;
        FOffset := WithNode[Index].StartOffset;
        try
          Known := ExprSymbol(WithNode[Index], Value) and TypeOf(Value, TypeInfo);
        finally
          FOffset := SavedOffset;
        end;
        if not Known then
        begin
          // Unbekannter Typ: der Name könnte ein Mitglied sein, also lieber nichts liefern.
          AStop := True;
          Exit;
        end;
        AResults := FindMembers(TypeInfo, AName);
        if Length(AResults) > 0 then
        begin
          AWith := WithNode;
          AElement := Index;
          Exit(True);
        end;
      end;
  finally
    Withs.Free;
  end;
end;

function TNameResolver.ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
  out AResults: TArray<TResolvedSymbol>): Boolean;
var
  First, ClassType: TResolvedSymbol;
  Stop: Boolean;
begin
  AConsumed := 1;
  AResults := nil;
  if LookupWith(ANames[0], AResults, Stop) then
    Exit(True);
  if Stop then
    Exit(False);
  if not ResolveFirst(ANames, AConsumed, First) then
    Exit(False);
  Result := True;
  // Überladungen: Mitglieder der eigenen Klasse oder freie Routinen derselben Unit.
  // Verschachtelte Routinen (#881): ihre Überladungen in der umgebenden Routine.
  if (AConsumed = 1) and (First.Kind = TResolvedKind.Local) and (First.SymbolKind = TIndexSymbolKind.Routine) then
    AResults := LocalOverloads(First)
  else if (AConsumed = 1) and (First.Kind = TResolvedKind.Symbol) and (First.SymbolKind in RoutineKinds) then
  begin
    if (First.Container <> '') and CurrentClass(ClassType) then
      AResults := FindMembers(ClassType, ANames[0]);
    if Length(AResults) = 0 then
      AResults := UnitRoutines(First);
  end
  else
    AResults := [First];
end;

function TNameResolver.ResolveNames(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; AInherited: Boolean; AReceiver, ACall: TSyntaxNode): TArray<TResolvedSymbol>;
var
  Consumed, Index: Integer;
  Current, TypeInfo, Ancestor, Single: TResolvedSymbol;
  Candidates: TArray<TResolvedSymbol>;
  Owner: TUnitIndex;
begin
  Result := nil;
  if (ATree = nil) or (Length(ANames) = 0) then
    Exit;
  Prepare(ATree, AFileName, AOffset);

  if AReceiver <> nil then
  begin
    // Foo(1).Bar, Liste[i].Bar, (X as TBar).Bar: alle Namen sind Mitglieder.
    if not ExprSymbol(AReceiver, Current) then
      Exit;
    Consumed := 0;
    Candidates := [Current];
  end
  else if AInherited then
  begin
    // inherited Create: im Vorfahren der Klasse der umgebenden Methode suchen.
    if not MethodClass(Current) or not AncestorOf(Current, Ancestor) then
      Exit;
    Candidates := FindMembers(Ancestor, ANames[0]);
    if Length(Candidates) = 0 then
      Exit;
    Current := Candidates[0];
    Consumed := 1;
  end
  else
  begin
    if not ResolveFirstAll(ANames, Consumed, Candidates) or (Length(Candidates) = 0) then
      Exit;
    Current := Candidates[0];
  end;

  for Index := Consumed to High(ANames) do
  begin
    if Current.Kind = TResolvedKind.UnitName then
    begin
      if not FindUnit(Current.UnitName, Owner) or
        not LookupInUnit(Owner, ANames[Index], not SameText(Owner.FileName, FCurrent.FileName), False, Single) then
        Exit;
      Candidates := UnitRoutines(Single);
    end
    else
    begin
      if not TypeOf(Current, TypeInfo) then
        Exit;
      Candidates := FindMembers(TypeInfo, ANames[Index]);
      if Length(Candidates) = 0 then
        Exit;
    end;
    Current := Candidates[0];
  end;
  if ACall <> nil then
    Candidates := SelectOverloads(Candidates, ACall.ChildCount - 1, ArgTypes(ACall, 1));
  // Eingebaute Typen haben keine Deklaration, zu der man springen könnte.
  for Current in Candidates do
    if not Current.Builtin then
      Result := Result + [Current];
end;

function TNameResolver.ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; AInherited: Boolean): TResolvedSymbol;
var
  Results: TArray<TResolvedSymbol>;
begin
  Results := ResolveNames(ATree, AFileName, ANames, AOffset, AInherited, nil, nil);
  if Length(Results) > 0 then
    Result := Results[0]
  else
    Result := NoResult;
end;

procedure TNameResolver.Prepare(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer);
var
  Section: TSyntaxNode;
  PinIndex: Integer;
begin
  FTree := ATree;
  FOffset := AOffset;
  FClassState := 0;
  FInferDepth := 0;
  PinIndex := PinnedIndex(ATree, AFileName);
  if PinIndex >= 0 then
    FCurrent := FPins[PinIndex].Merged
  else
    FCurrent := TreeUnit(ATree, AFileName);
  // Helfer hängen an der Unit und ihren uses; je Baum neu bestimmen.
  if ATree <> FHelperTree then
  begin
    FHelpers.Clear;
    FAncestors.Clear;
    FHelperTree := ATree;
  end;
  Section := ATree.Root.FindChild(TSyntaxKind.InterfaceSection);
  // Programme haben keinen interface-Teil: alles ist "implementation".
  FInImplementation := (Section = nil) or not Contains(Section, AOffset);
end;

/// <summary>AOuter ist eine andere Deklaration als ANear, nicht deren Rumpf in implementation (#488).</summary>
function IsOtherDeclaration(const ANear, AOuter: TResolvedSymbol): Boolean;
begin
  if (ANear.Kind = TResolvedKind.Local) and (AOuter.Kind = TResolvedKind.Local) then
    Result := not (ANear.SelectionRange.StartPos = AOuter.SelectionRange.StartPos)
  else
    Result := (ANear.Kind <> AOuter.Kind) or not SameText(ANear.Container, AOuter.Container) or
      not SameText(ANear.FileName, AOuter.FileName);
end;

class function TNameResolver.ArgumentFits(const AParam, AArg: string): Boolean;
begin
  Result := ArgFits(AParam, AArg);
end;

class function TNameResolver.ShadowText(const ASymbol: TResolvedSymbol): string;
begin
  if ASymbol.Kind = TResolvedKind.Local then
  begin
    if ASymbol.IsParameter then
      Result := 'Parameter ' + ASymbol.Name
    else
      Result := 'lokale Variable ' + ASymbol.Name;
  end
  else if ASymbol.Container <> '' then
  begin
    case ASymbol.SymbolKind of
      TIndexSymbolKind.Field: Result := 'Feld ';
      TIndexSymbolKind.Property_: Result := 'Eigenschaft ';
      TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_: Result := 'Methode ';
    else
      Result := '';
    end;
    Result := Result + ASymbol.Container + '.' + ASymbol.Name;
  end
  else if ASymbol.UnitName <> '' then
    Result := ASymbol.UnitName + '.' + ASymbol.Name
  else
    Result := ASymbol.Name;
end;

procedure TNameResolver.AddCandidate(AList: TList<TResolvedSymbol>; ASeen: TDictionary<string, Boolean>;
  const ASymbol: TResolvedSymbol);
var
  Key, Params: string;
  Index: Integer;
  Existing: TResolvedSymbol;
begin
  // Der nächste Gültigkeitsbereich verdeckt gleichnamige weiter außen; Überladungen erscheinen einmal,
  // ihre Positionen merkt sich der erste Eintrag (#425).
  Key := UpperCase(ASymbol.Name);
  if Key = '' then
    Exit;
  if ASeen.ContainsKey(Key) then
  begin
    for Index := AList.Count - 1 downto 0 do
      if SameText(AList[Index].Name, ASymbol.Name) then
      begin
        // Gleiche Klasse und Datei, gleicher Abschnitt (Rümpfe in implementation zählen nicht) und andere
        // Parametertypen als jede bisherige Variante (Rümpfe überladener Methoden wiederholen sie).
        Params := String.Join(';', ASymbol.ParamTypes);
        if SameText(AList[Index].Container, ASymbol.Container) and SameText(AList[Index].FileName, ASymbol.FileName) and
          (AList[Index].SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) and
          (AList[Index].InInterface = ASymbol.InInterface) and
          not MatchText(Params, AList[Index].VariantParams) then
        begin
          Existing := AList[Index];
          Existing.Overloads := Existing.Overloads + [ASymbol.SelectionRange];
          Existing.VariantParams := Existing.VariantParams + [Params];
          AList[Index] := Existing;
        end
        else if IsOtherDeclaration(AList[Index], ASymbol) then
        begin
          // Verdeckt (#488): Das Detailpanel nennt die Deklaration weiter außen.
          Existing := AList[Index];
          Params := ShadowText(ASymbol);
          if not MatchText(Params, Existing.Hides) then
            Existing.Hides := Existing.Hides + [Params];
          AList[Index] := Existing;
        end;
        Break;
      end;
    Exit;
  end;
  ASeen.Add(Key, True);
  AList.Add(ASymbol);
end;

/// <summary>ASymbol als Mitglied in Vererbungstiefe ADepth (#419), ggf. aus einem Helper.</summary>
function MemberOf(const ASymbol: TResolvedSymbol; ADepth: Integer; AIsHelper: Boolean): TResolvedSymbol;
begin
  Result := ASymbol;
  Result.Depth := ADepth;
  Result.IsHelper := AIsHelper;
end;

function TNameResolver.NameWanted(const AName: string): Boolean;
begin
  // Vor FromSymbol prüfen: Das Aufbauen der Records kostet bei großen Units die meiste Zeit (#616).
  Result := not Assigned(FNameFilter) or FNameFilter(AName);
end;

procedure TNameResolver.CollectMembers(const AType: TResolvedSymbol; AList: TList<TResolvedSymbol>;
  ASeen: TDictionary<string, Boolean>);
var
  Current, Ancestor, Helper, Member: TResolvedSymbol;
  OwnerUnit, HelperUnit: TUnitIndex;
  Position, Depth: Integer;
  TypeName: string;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    // Mitglieder des Helfers zuerst (#263), auch für eingebaute Typen. Über den Index statt for-in:
    // keine Kopie des Symbol-Records je geprüftem Symbol (Code-Review P-05).
    if HelperFor(Current, Helper) and UnitOf(Helper, HelperUnit) then
      for Position := 0 to High(HelperUnit.Symbols) do
        if SameText(HelperUnit.Symbols[Position].Container, Helper.QualifiedName) and
          IsVisible(HelperUnit.Symbols[Position], HelperUnit, Helper) and NameWanted(HelperUnit.Symbols[Position].Name) then
          AddCandidate(AList, ASeen, MemberOf(FromSymbol(HelperUnit, HelperUnit.Symbols[Position]), Depth, True));
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit;
    TypeName := Current.QualifiedName;
    for Position := 0 to High(OwnerUnit.Symbols) do
      if SameText(OwnerUnit.Symbols[Position].Container, TypeName) then
        if IsVisible(OwnerUnit.Symbols[Position], OwnerUnit, Current) then
        begin
          if NameWanted(OwnerUnit.Symbols[Position].Name) then
          begin
            // Gebundene Typparameter des Typs (#450): Mitglieder von TObjectList<TKunde> kennen T=TKunde.
            Member := MemberOf(FromSymbol(OwnerUnit, OwnerUnit.Symbols[Position]), Depth, False);
            Member.Bindings := Current.Bindings;
            AddCandidate(AList, ASeen, Member);
          end;
        end
        else
          // Unsichtbare Deklaration: auch ihren Rumpf aus implementation nicht anbieten.
          ASeen.AddOrSetValue(UpperCase(OwnerUnit.Symbols[Position].Name), True);
    if not AncestorOf(Current, Ancestor) then
      Exit;
    Current := Ancestor;
  end;
end;

procedure TNameResolver.CollectUnit(const AUnit: TUnitIndex; AOnlyInterface: Boolean;
  AList: TList<TResolvedSymbol>; ASeen: TDictionary<string, Boolean>);
var
  Position: Integer;
begin
  // Über den Index statt for-in: keine Kopie des Symbol-Records je übersprungenem Symbol (Code-Review P-05).
  for Position := 0 to High(AUnit.Symbols) do
  begin
    if AOnlyInterface and not AUnit.Symbols[Position].InInterface then
      Continue;
    if (AUnit.Symbols[Position].Container <> '') and (AUnit.Symbols[Position].Kind <> TIndexSymbolKind.EnumMember) then
      Continue;
    if not NameWanted(AUnit.Symbols[Position].Name) then
      Continue;
    AddCandidate(AList, ASeen, FromSymbol(AUnit, AUnit.Symbols[Position]));
  end;
end;

procedure TNameResolver.CollectDeclarations(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
  ASeen: TDictionary<string, Boolean>);
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
  Kind: TIndexSymbolKind;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    case Child.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        CollectDeclarations(Child, AList, ASeen);
      TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
        begin
          if Child.Kind = TSyntaxKind.VarDecl then
            Kind := TIndexSymbolKind.Variable
          else
            Kind := TIndexSymbolKind.Constant;
          for Name in Child.Name.Split([',']) do
            AddCandidate(AList, ASeen, FromNode(Child, Name.Trim, Kind, False));
        end;
      TSyntaxKind.TypeDecl:
        AddCandidate(AList, ASeen, FromNode(Child, Child.Name, TIndexSymbolKind.TypeAlias, False));
      TSyntaxKind.RoutineDecl:
        AddCandidate(AList, ASeen, FromNode(Child, Child.Name, TIndexSymbolKind.Routine, False));
    end;
  end;
end;

procedure TNameResolver.CollectInlineVars(ANode: TSyntaxNode; AList: TList<TResolvedSymbol>;
  ASeen: TDictionary<string, Boolean>);
var
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
begin
  // Wie LookupInlineVars: nur bis zum Cursor, nicht in verschachtelte Routinen.
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.StartOffset > FOffset then
      Break;
    if Child.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    begin
      if Child.EndOffset <= FOffset then
        for Name in Child.Name.Split([',']) do
          AddCandidate(AList, ASeen, FromNode(Child, Name.Trim, TIndexSymbolKind.Variable, False));
    end
    else if (Child.Kind <> TSyntaxKind.RoutineDecl) and Contains(Child, FOffset) then
      CollectInlineVars(Child, AList, ASeen);
  end;
end;

function TNameResolver.ScopeCandidates(ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer): TArray<TResolvedSymbol>;
begin
  Result := OwnScopeCandidates(ATree, AFileName, AOffset);
  Result := Result + UsedScopeCandidates;
end;

function TNameResolver.OwnScopeCandidates(ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer): TArray<TResolvedSymbol>;
var
  List: TList<TResolvedSymbol>;
  Routine, Header, Params, Param: TSyntaxNode;
  Index: Integer;
  Name: string;
  ClassType, ResultSymbol: TResolvedSymbol;
begin
  Result := nil;
  FScopeOpen := False;
  if FScopeSeen = nil then
    FScopeSeen := TDictionary<string, Boolean>.Create;
  FScopeSeen.Clear;
  if ATree = nil then
    Exit;
  Prepare(ATree, AFileName, AOffset);
  List := TList<TResolvedSymbol>.Create;
  try
    for Routine in EnclosingRoutines do
    begin
      // Lokale Namen vor den Parametern (#488): Stufe 1 vor Stufe 2.
      CollectInlineVars(Routine, List, FScopeSeen);
      CollectDeclarations(Routine, List, FScopeSeen);
      Header := RoutineHeaderOf(Routine);

      if Header <> nil then
      begin
        Params := Header.FindChild(TSyntaxKind.Parameters);
        if Params <> nil then
          for Index := 0 to Params.ChildCount - 1 do
          begin
            Param := Params[Index];
            if Param.Kind = TSyntaxKind.Parameter then
              for Name in Param.Name.Split([',']) do
                AddCandidate(List, FScopeSeen, FromNode(Param, Name.Trim, TIndexSymbolKind.Variable, True));
          end;
        if Header.FindChild(TSyntaxKind.TypeReference) <> nil then
        begin
          ResultSymbol := FromNode(Header, 'Result', TIndexSymbolKind.Variable, False);
          AddCandidate(List, FScopeSeen, ResultSymbol);
        end;
      end;
    end;
    if MethodClass(ClassType) then
    begin
      ResultSymbol := ClassType;
      ResultSymbol.Name := 'Self';
      ResultSymbol.Kind := TResolvedKind.Local;
      ResultSymbol.SymbolKind := TIndexSymbolKind.Variable;
      ResultSymbol.TypeName := ClassType.QualifiedName;
      AddCandidate(List, FScopeSeen, ResultSymbol);
      CollectMembers(ClassType, List, FScopeSeen);
    end;
    CollectUnit(FCurrent, not FInImplementation, List, FScopeSeen);
    // Für den zweiten Teil merken: Andere Aufrufe dazwischen (z. B. Typprüfungen) bereiten den Zustand neu vor.
    FScopeUnit := FCurrent;
    FScopeInImplementation := FInImplementation;
    FScopeOpen := True;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

/// <summary>Bezeichner von System ohne Quelltext als Kandidat (#880); Überladungen erscheinen einmal.</summary>
function IntrinsicSymbol(const AIntrinsic: TSystemIntrinsic): TResolvedSymbol;
begin
  Result := NoResult;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := AIntrinsic.Name;
  Result.UnitName := 'System';
  Result.SymbolKind := AIntrinsic.Kind;
  Result.MinArgs := AIntrinsic.MinArgs;
  Result.MaxArgs := AIntrinsic.MaxArgs;
  Result.InInterface := True;
  Result.Builtin := True;
end;

function TNameResolver.UsedScopeCandidates(AWithIntrinsics: Boolean): TArray<TResolvedSymbol>;
var
  List: TList<TResolvedSymbol>;
  UnitName: string;
  Used: TUnitIndex;
  Intrinsic: TSystemIntrinsic;
  Symbol: TResolvedSymbol;
begin
  Result := nil;
  if not FScopeOpen then
    Exit;
  FScopeOpen := False;
  List := TList<TResolvedSymbol>.Create;
  try
    for UnitName in ScopeUnits(FScopeUnit, FScopeInImplementation) do
      if FindUnit(UnitName, Used) then
        CollectUnit(Used, True, List, FScopeSeen);
    // Zuletzt, was System ohne Quelltext mitbringt: Indexiertes und Eigenes verdeckt gleichnamige Einträge.
    if AWithIntrinsics then
      for Intrinsic in TSystemIntrinsics.All do
        if not FScopeSeen.ContainsKey(UpperCase(Intrinsic.Name)) and NameWanted(Intrinsic.Name) then
        begin
          Symbol := IntrinsicSymbol(Intrinsic);
          FScopeSeen.Add(UpperCase(Intrinsic.Name), True);
          List.Add(Symbol);
        end
        else if (List.Count > 0) and SameText(List[List.Count - 1].Name, Intrinsic.Name) and
          List[List.Count - 1].Builtin and (Intrinsic.MaxArgs > List[List.Count - 1].MaxArgs) then
        begin
          // Weitere Überladung: Parameter zeigt der Eintrag schon an, wenn eine Variante welche hat.
          Symbol := List[List.Count - 1];
          Symbol.MaxArgs := Intrinsic.MaxArgs;
          List[List.Count - 1] := Symbol;
        end;
    Result := List.ToArray;
  finally
    List.Free;
    FScopeSeen.Clear;
  end;
end;

function TNameResolver.UsedScopeShadows: TArray<TResolvedSymbol>;
var
  List: TList<TResolvedSymbol>;
  Seen: TDictionary<string, Boolean>;
  UnitName: string;
  Used: TUnitIndex;
begin
  Result := nil;
  if not FScopeOpen then
    Exit;
  List := TList<TResolvedSymbol>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for UnitName in ScopeUnits(FScopeUnit, FScopeInImplementation) do
      if FindUnit(UnitName, Used) then
        CollectUnit(Used, True, List, Seen);
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

function TNameResolver.MemberCandidates(ATree: TSyntaxTree; const AFileName: string;
  const ANames: TArray<string>; AOffset: Integer): TArray<TResolvedSymbol>;
var
  Owner, TypeInfo: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  List: TList<TResolvedSymbol>;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  // ResolveChain bereitet den Zustand (aktuelle Unit, Abschnitt) vor.
  Owner := ResolveChain(ATree, AFileName, ANames, AOffset);
  if not Owner.Found then
    Exit;
  List := TList<TResolvedSymbol>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    if Owner.Kind = TResolvedKind.UnitName then
    begin
      if FindUnit(Owner.UnitName, OwnerUnit) then
        CollectUnit(OwnerUnit, not SameText(OwnerUnit.FileName, FCurrent.FileName), List, Seen);
    end
    else if TypeOf(Owner, TypeInfo) then
      CollectMembers(TypeInfo, List, Seen);
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

function TNameResolver.TreeUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
begin
  Result := MergedUnit(TIndexExtractor.Extract(ATree, AFileName), AFileName);
end;

function TNameResolver.MergedUnit(const AExtracted: TUnitIndex; const AFileName: string): TUnitIndex;
var
  Indexed: TUnitIndex;
  Count, Position: Integer;
begin
  Result := AExtracted;
  // Der Baum kennt nur die Datei selbst; Deklarationen aus Include-Dateien stehen im Index.
  if (FIndex <> nil) and (AFileName <> '') and FIndex.FindFile(AFileName, Indexed) then
  begin
    // Eigenes Array (Copy): Result.Symbols teilt es sonst mit AExtracted. Einmal vergrößern statt je
    // Symbol anhängen (Code-Review P-08).
    Count := Length(AExtracted.Symbols);
    Result.Symbols := Copy(AExtracted.Symbols);
    SetLength(Result.Symbols, Count + Length(Indexed.Symbols));
    for Position := 0 to High(Indexed.Symbols) do
      if Indexed.Symbols[Position].FileName <> '' then
      begin
        Result.Symbols[Count] := Indexed.Symbols[Position];
        Inc(Count);
      end;
    SetLength(Result.Symbols, Count);
    Result.Includes := Indexed.Includes;
  end;
  Result.PrepareNames;
end;

function TNameResolver.PinnedIndex(ATree: TSyntaxTree; const AFileName: string): Integer;
var
  Index: Integer;
begin
  for Index := FPins.Count - 1 downto 0 do
    if (FPins[Index].Tree = ATree) and SameText(FPins[Index].FileName, AFileName) then
      Exit(Index);
  Result := -1;
end;

function TNameResolver.ExtractedUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
var
  PinIndex: Integer;
begin
  PinIndex := PinnedIndex(ATree, AFileName);
  if PinIndex >= 0 then
    Result := FPins[PinIndex].Extracted
  else
    Result := TIndexExtractor.Extract(ATree, AFileName);
end;

function TNameResolver.ReceiverTypes(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer): TArray<TResolvedSymbol>;
var
  Owner, Current, Ancestor: TResolvedSymbol;
  Found: Boolean;
  Depth: Integer;
begin
  Result := nil;
  if not ChainType(ATree, AFileName, ANames, AOffset, Owner, Current, Found) or not Found then
    Exit;
  for Depth := 0 to MaxDepth do
  begin
    Result := Result + [Current];
    if Current.Builtin or not AncestorOf(Current, Ancestor) then
      Break;
    Current := Ancestor;
  end;
end;

class function TNameResolver.HelperTargets(const ATarget: string; const AType: TResolvedSymbol): Boolean;
var
  Name: string;
begin
  Name := Copy(ATarget, LastDelimiter('.', ATarget) + 1, MaxInt);
  Result := SameText(Name, AType.Name) or
    (MatchText(Name, ['string', 'UnicodeString']) and MatchText(AType.Name, ['string', 'UnicodeString']));
end;

function TNameResolver.ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; out AOwner, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
begin
  AType := Default(TResolvedSymbol);
  ATypeFound := False;
  AOwner := ResolveChain(ATree, AFileName, ANames, AOffset);
  Result := AOwner.Found;
  if Result and (AOwner.Kind <> TResolvedKind.UnitName) then
    ATypeFound := TypeOf(AOwner, AType);
end;

procedure TNameResolver.PinTree(ATree: TSyntaxTree; const AFileName: string);
var
  Pin: TPin;
  Call: TPinCall;
  PinIndex: Integer;
begin
  // Verschachtelt (Code-Review P-01/P-02): Handle pinnt, Collect pinnt denselben Baum erneut, Find pinnt
  // Fremdbäume. Derselbe Baum zählt nur hoch und wird nicht erneut ausgewertet.
  Call.Tree := ATree;
  Call.FileName := AFileName;
  FPinCalls.Add(Call);
  PinIndex := PinnedIndex(ATree, AFileName);
  if PinIndex >= 0 then
  begin
    Pin := FPins[PinIndex];
    Inc(Pin.Depth);
    FPins[PinIndex] := Pin;
    Exit;
  end;
  Pin := Default(TPin);
  Pin.Tree := ATree;
  Pin.FileName := AFileName;
  Pin.Extracted := TIndexExtractor.Extract(ATree, AFileName);
  Pin.Merged := MergedUnit(Pin.Extracted, AFileName);
  Pin.Depth := 1;
  FPins.Add(Pin);
end;

procedure TNameResolver.UnpinTree;
var
  Pin: TPin;
  Call: TPinCall;
  PinIndex: Integer;
begin
  if FPinCalls.Count = 0 then
    Exit;
  Call := FPinCalls[FPinCalls.Count - 1];
  FPinCalls.Delete(FPinCalls.Count - 1);
  PinIndex := PinnedIndex(Call.Tree, Call.FileName);
  if PinIndex < 0 then
    Exit;
  Pin := FPins[PinIndex];
  Dec(Pin.Depth);
  if Pin.Depth > 0 then
  begin
    FPins[PinIndex] := Pin;
    Exit;
  end;
  FPins.Delete(PinIndex);
  // Der Aufrufer gibt den Baum danach frei: keine Bezüge behalten, die eine wiederverwendete Adresse
  // treffen könnten. Ohne FHelperTree leert das nächste Prepare die baumbezogenen Caches.
  if FHelperTree = Pin.Tree then
    FHelperTree := nil;
  if FTree = Pin.Tree then
    FTree := nil;
end;

function TNameResolver.ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  FTree := nil;
  FOffset := 0;
  FCurrent := AFromUnit;
  FInImplementation := True;
  FClassState := 0;
  // Helfer- und Vorfahren-Cache bleiben (Code-Review P-17): Ihre Schlüssel enthalten Unit und Abschnitt.
  Result := ResolveTypeName(ATypeName, AFromUnit, True, AResult);
end;

function TNameResolver.ResolveNameFrom(const AFromUnit: TUnitIndex; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  FTree := nil;
  FOffset := 0;
  FCurrent := AFromUnit;
  FInImplementation := True;
  FClassState := 0;
  // Helfer- und Vorfahren-Cache bleiben (Code-Review P-17): Ihre Schlüssel enthalten Unit und Abschnitt.
  Result := LookupGlobal(AFromUnit, AName, True, False, AResult);
end;

function TNameResolver.DeclaredMember(const AType: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  Current, Ancestor: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Position, Depth: Integer;
begin
  Current := AType;
  for Depth := 0 to MaxDepth do
  begin
    if Current.Builtin or not UnitOf(Current, OwnerUnit) then
      Exit(False);
    // Über die Namenstabelle statt aller Symbole je Vorfahrstufe (Code-Review P-05).
    for Position in OwnerUnit.SymbolsNamed(AName) do
      if SameText(OwnerUnit.Symbols[Position].Container, Current.QualifiedName) then
      begin
        AResult := FromSymbol(OwnerUnit, OwnerUnit.Symbols[Position]);
        Exit(True);
      end;
    if not AncestorOf(Current, Ancestor) then
      Exit(False);
    Current := Ancestor;
  end;
  Result := False;
end;

function TNameResolver.SymbolFrom(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): TResolvedSymbol;
begin
  Result := FromSymbol(AUnit, ASymbol);
end;

function TNameResolver.DeclaringUnit(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  Result := UnitOf(AResolved, AUnit);
end;

function TNameResolver.InheritedCandidates(ATree: TSyntaxTree; const AFileName: string;
  AOffset: Integer): TArray<TResolvedSymbol>;
var
  Current, Ancestor, Candidate: TResolvedSymbol;
  List: TList<TResolvedSymbol>;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  if ATree = nil then
    Exit;
  Prepare(ATree, AFileName, AOffset);
  if not MethodClass(Current) or not AncestorOf(Current, Ancestor) then
    Exit;
  List := TList<TResolvedSymbol>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    // Wie Mitglieder des Vorfahren, gesehen aus der eigenen Methode (protected sichtbar).
    CollectMembers(Ancestor, List, Seen);
    for Candidate in List do
      if Candidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_] then
        Result := Result + [MemberOf(Candidate, Candidate.Depth + 1, Candidate.IsHelper)];
  finally
    Seen.Free;
    List.Free;
  end;
end;

function TNameResolver.AccessorCandidates(const AFromUnit: TUnitIndex;
  const ATypeName: string): TArray<TResolvedSymbol>;
var
  Own, Current, Ancestor, Candidate: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Seen: TDictionary<string, Boolean>;
  Depth: Integer;
begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    // Eigener Typ aus dem aktuellen Stand der Datei: jede Sichtbarkeit.
    for Symbol in AFromUnit.Symbols do
      if SameText(Symbol.Container, ATypeName) and
        (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Method]) and
        not Seen.ContainsKey(UpperCase(Symbol.Name)) then
      begin
        Seen.Add(UpperCase(Symbol.Name), True);
        Result := Result + [FromSymbol(AFromUnit, Symbol)];
      end;
    if not ResolveTypeFrom(AFromUnit, ATypeName, Own) then
      Exit;
    Current := Own;
    for Depth := 1 to MaxDepth do
    begin
      if not AncestorOf(Current, Ancestor) or not UnitOf(Ancestor, OwnerUnit) then
        Break;
      for Symbol in OwnerUnit.Symbols do
        if SameText(Symbol.Container, Ancestor.QualifiedName) and
          (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Method]) and
          (Symbol.Visibility <> TIndexVisibility.StrictPrivate) and
          ((Symbol.Visibility <> TIndexVisibility.Private) or SameText(OwnerUnit.FileName, AFromUnit.FileName)) and
          not Seen.ContainsKey(UpperCase(Symbol.Name)) then
        begin
          Seen.Add(UpperCase(Symbol.Name), True);
          Candidate := FromSymbol(OwnerUnit, Symbol);
          Candidate.Depth := Depth;
          Result := Result + [Candidate];
        end;
      Current := Ancestor;
    end;
  finally
    Seen.Free;
  end;
end;

function TNameResolver.OverridableMembers(const AFromUnit: TUnitIndex; const ATypeName: string): TArray<TResolvedSymbol>;
var
  Own, Current, Ancestor: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Seen: TDictionary<string, Boolean>;
  List: TList<TResolvedSymbol>;
  Depth: Integer;
  Candidate: TResolvedSymbol;
begin
  Result := nil;
  if not ResolveTypeFrom(AFromUnit, ATypeName, Own) or not UnitOf(Own, OwnerUnit) then
    Exit;
  Seen := TDictionary<string, Boolean>.Create;
  List := TList<TResolvedSymbol>.Create;
  try
    // Im Typ selbst Deklariertes ist schon überschrieben bzw. verdeckt.
    for Symbol in OwnerUnit.Symbols do
      if SameText(Symbol.Container, Own.QualifiedName) then
        Seen.AddOrSetValue(UpperCase(Symbol.Name), True);
    Current := Own;
    for Depth := 1 to MaxDepth do
    begin
      if not AncestorOf(Current, Ancestor) or not UnitOf(Ancestor, OwnerUnit) then
        Break;
      for Symbol in OwnerUnit.Symbols do
        if SameText(Symbol.Container, Ancestor.QualifiedName) and Symbol.IsVirtual and
          (Symbol.Kind in [TIndexSymbolKind.Method]) and (Symbol.Visibility <> TIndexVisibility.StrictPrivate) and
          (Symbol.Visibility <> TIndexVisibility.Private) and not Seen.ContainsKey(UpperCase(Symbol.Name)) then
        begin
          Seen.Add(UpperCase(Symbol.Name), True);
          Candidate := FromSymbol(OwnerUnit, Symbol);
          Candidate.Depth := Depth;
          List.Add(Candidate);
        end;
      Current := Ancestor;
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end;

/// <summary>Name und Parametertypen ohne Unit-Präfix, für den Vergleich von Methodensignaturen (#466).</summary>
function SignatureKey(const AName: string; const AParamTypes: TArray<string>): string;
var
  Index: Integer;
  TypeText: string;
begin
  Result := UpperCase(AName) + '(';
  for Index := 0 to High(AParamTypes) do
  begin
    TypeText := AParamTypes[Index];
    if (Pos('<', TypeText) = 0) and (LastDelimiter('.', TypeText) > 0) then
      TypeText := Copy(TypeText, LastDelimiter('.', TypeText) + 1, MaxInt);
    if Index > 0 then
      Result := Result + ';';
    Result := Result + UpperCase(TypeText);
  end;
  Result := Result + ')';
end;

function TNameResolver.UnqualifyType(const AText, AOwnUnit: string): string;
var
  Index, Start, Dot: Integer;
  Chain: string;
  UnitIndex: TUnitIndex;
begin
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
    if CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_', '&']) then
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.', '&']) do
        Inc(Index);
      Chain := Copy(AText, Start, Index - Start);
      // Längstes Präfix, das eine Unit ist, entfernen.
      Dot := LastDelimiter('.', Chain);
      while Dot > 0 do
      begin
        if ((AOwnUnit <> '') and SameText(Copy(Chain, 1, Dot - 1), AOwnUnit)) or
          ((FIndex <> nil) and FIndex.FindUnit(Copy(Chain, 1, Dot - 1), UnitIndex)) then
        begin
          Chain := Copy(Chain, Dot + 1, MaxInt);
          Break;
        end;
        Dot := LastDelimiter('.', Copy(Chain, 1, Dot - 1));
      end;
      Result := Result + Chain;
    end
    else
    begin
      Result := Result + AText[Index];
      Inc(Index);
    end;
end;

function TNameResolver.MissingInterfaceMembers(const AFromUnit: TUnitIndex; const ATypeName: string;
  const AAncestors: TArray<string>): TArray<TResolvedSymbol>;

  function Unqualified(const ABindings: TArray<string>): TArray<string>;
  var
    Index, Equal: Integer;
  begin
    Result := Copy(ABindings);
    for Index := 0 to High(Result) do
    begin
      Equal := Pos('=', Result[Index]);
      // Auch die eigene Unit, falls sie (noch) nicht im Index steht.
      Result[Index] := Copy(Result[Index], 1, Equal) + UnqualifyType(Copy(Result[Index], Equal + 1, MaxInt),
        AFromUnit.UnitName);
    end;
  end;

  /// <summary>Signaturschlüssel mit eingesetzten Typargumenten.</summary>
  function KeyOf(const ASymbol: TIndexSymbol; const ABindings: TArray<string>): string;
  var
    Types: TArray<string>;
    Index: Integer;
  begin
    Types := Copy(ASymbol.ParamTypes);
    for Index := 0 to High(Types) do
      Types[Index] := UnqualifyType(Substitute(Types[Index], ABindings));
    Result := SignatureKey(ASymbol.Name, Types);
  end;

var
  Own, Current, Ancestor, Intf, Member: TResolvedSymbol;
  OwnerUnit, IntfUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Implemented, SeenInterfaces: TDictionary<string, Boolean>;
  List: TList<TResolvedSymbol>;
  Depth: Integer;
  Name, Key: string;
  Names, Bindings: TArray<string>;
begin
  Result := nil;
  if not ResolveTypeFrom(AFromUnit, ATypeName, Own) or not UnitOf(Own, OwnerUnit) then
    Exit;
  Implemented := TDictionary<string, Boolean>.Create;
  SeenInterfaces := TDictionary<string, Boolean>.Create;
  List := TList<TResolvedSymbol>.Create;
  try
    // Methoden der Klasse und ihrer Vorfahrklassen.
    Current := Own;
    for Depth := 0 to MaxDepth do
    begin
      if (Current.SymbolKind = TIndexSymbolKind.InterfaceType) or not UnitOf(Current, IntfUnit) then
        Break;
      Bindings := Unqualified(Current.Bindings);
      for Symbol in IntfUnit.Symbols do
        if SameText(Symbol.Container, Current.QualifiedName) and (Symbol.Kind in RoutineKinds) then
          Implemented.AddOrSetValue(KeyOf(Symbol, Bindings), True);
      if not AncestorOf(Current, Ancestor) then
        Break;
      Current := Ancestor;
    end;
    // Interfaces der Vorfahrenliste, jeweils mit ihren Vorfahren.
    Names := AAncestors;
    if Length(Names) = 0 then
      Names := Own.Ancestors;
    for Name in Names do
    begin
      if not ResolveTypeText(Name, OwnerUnit, True, Intf) or (Intf.SymbolKind <> TIndexSymbolKind.InterfaceType) then
        Continue;
      for Depth := 0 to MaxDepth do
      begin
        if SeenInterfaces.ContainsKey(UpperCase(Intf.QualifiedName)) or not UnitOf(Intf, IntfUnit) then
          Break;
        SeenInterfaces.Add(UpperCase(Intf.QualifiedName), True);
        Bindings := Unqualified(Intf.Bindings);
        for Symbol in IntfUnit.Symbols do
          if SameText(Symbol.Container, Intf.QualifiedName) and (Symbol.Kind in RoutineKinds) then
          begin
            Key := KeyOf(Symbol, Bindings);
            if Implemented.ContainsKey(Key) then
              Continue;
            Implemented.Add(Key, True);
            Member := FromSymbol(IntfUnit, Symbol);
            Member.Bindings := Bindings;
            List.Add(Member);
          end;
        if not AncestorOf(Intf, Ancestor) or (Ancestor.SymbolKind <> TIndexSymbolKind.InterfaceType) then
          Break;
        Intf := Ancestor;
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
    SeenInterfaces.Free;
    Implemented.Free;
  end;
end;

function TNameResolver.ResolveType(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  Symbol, TypeInfo: TResolvedSymbol;
begin
  // Resolve setzt den Zustand (aktuelle Unit, Abschnitt), den TypeOf braucht.
  Symbol := Resolve(ATree, AFileName, APosition);
  if (Symbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and TypeOf(Symbol, TypeInfo) and
    not TypeInfo.Builtin then
    Result := TypeInfo
  else
    Result := NoResult;
end;

function TNameResolver.TokenIndexAt(const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(FTree.Tokens) do
  begin
    Token := FTree.Tokens[Index];
    if ComparePositions(Token.StartPos, APosition) > 0 then
      Break;
    // Cursor auf oder direkt hinter dem Bezeichner.
    if (Token.Kind = TPascalTokenKind.Identifier) and (ComparePositions(APosition, Token.EndPos) <= 0) then
      Exit(Index);
  end;
  Result := -1;
end;

function TNameResolver.ResolveAt(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TResolvedSymbol>;
var
  Tokens: TArray<TPascalToken>;
  Index, First, Last: Integer;
  Names: TList<string>;
  IsInherited: Boolean;
  UnitName: string;
  UnitIndex: TUnitIndex;
  Symbol: TResolvedSymbol;
  Receiver, Call: TSyntaxNode;
  Before: TPascalToken;
  Use: TAttributeUse;
  AttributeNames: TArray<string>;

  function Clean(const AText: string): string;
  begin
    // &Begin → Begin
    if (AText <> '') and (AText[1] = '&') then
      Result := Copy(AText, 2, MaxInt)
    else
      Result := AText;
  end;

begin
  Result := nil;
  if ATree = nil then
    Exit;
  FTree := ATree;
  Tokens := ATree.Tokens;
  Index := TokenIndexAt(APosition);
  if Index < 0 then
    Exit;
  Names := TList<string>.Create;
  try
    Names.Add(Clean(Tokens[Index].Text));
    First := Index;
    while (First >= 2) and Tokens[First - 1].IsSymbol('.') and
      (Tokens[First - 2].Kind = TPascalTokenKind.Identifier) do
    begin
      Dec(First, 2);
      Names.Insert(0, Clean(Tokens[First].Text));
    end;
    // Foo(1).Bar, A[0].B, (X as TBar).C: Empfänger ist ein Ausdruck (#263).
    Receiver := nil;
    if (First >= 2) and Tokens[First - 1].IsSymbol('.') then
    begin
      Before := Tokens[First - 2];
      Receiver := FindReceiver(Before.Offset + Length(Before.Text));
      if Receiver = nil then
        Exit;
    end
    else
    begin
      // Cursor auf einem vorderen Teil eines Unit-Namens (Vcl in Vcl.Werkzeug):
      // die folgenden Teile ergänzen und den längsten passenden Unit-Namen nehmen.
      Last := Index;
      UnitName := string.Join('.', Names.ToArray);
      Symbol := NoResult;
      while (Last + 2 < Length(Tokens)) and Tokens[Last + 1].IsSymbol('.') and
        (Tokens[Last + 2].Kind = TPascalTokenKind.Identifier) do
      begin
        Inc(Last, 2);
        UnitName := UnitName + '.' + Clean(Tokens[Last].Text);
        // Nur ein Versuch, ob die Teile eine Unit ergeben (TWerkzeug.Create meist nicht): ohne teures
        // Nachladen über alle Suchpfade, außer für Units aus uses (#647).
        if FindQualifierUnit(UnitName, UnitIndex) then
        begin
          Symbol := NoResult;
          Symbol.Kind := TResolvedKind.UnitName;
          Symbol.Name := UnitIndex.UnitName;
          Symbol.UnitName := UnitIndex.UnitName;
          Symbol.FileName := UnitIndex.FileName;
        end;
      end;
      if Symbol.Kind = TResolvedKind.UnitName then
      begin
        Result := [Symbol];
        Exit;
      end;
    end;
    // Aufruf mit Klammern: Argumente bestimmen die Überladung.
    Call := nil;
    if (Index < High(Tokens)) and Tokens[Index + 1].IsSymbol('(') then
      Call := FindCall(Tokens[Index].Offset + Length(Tokens[Index].Text));
    IsInherited := (Receiver = nil) and (First >= 1) and Tokens[First - 1].IsKeyword('inherited');
    // Attribut (#119): [Foo] meint zuerst die Klasse FooAttribute, dann Foo; Argumente gehen an den Konstruktor.
    if (Receiver = nil) and (First >= 1) and (Tokens[First - 1].IsSymbol('[') or Tokens[First - 1].IsSymbol(',')) and
      not ((Index < High(Tokens)) and Tokens[Index + 1].IsSymbol('.')) and TAttributes.At(ATree, APosition, Use) then
    begin
      AttributeNames := Names.ToArray;
      AttributeNames[High(AttributeNames)] := AttributeNames[High(AttributeNames)] + 'Attribute';
      Result := ResolveNames(ATree, AFileName, AttributeNames, Tokens[Index].Offset, False, nil, nil);
      if (Length(Result) > 0) and (Result[0].SymbolKind = TIndexSymbolKind.ClassType) and
        IsAttributeClass(Result[0]) then
        Exit;
      Result := ResolveNames(ATree, AFileName, Names.ToArray, Tokens[Index].Offset, False, nil, nil);
      Exit;
    end;
    Result := ResolveNames(ATree, AFileName, Names.ToArray, Tokens[Index].Offset, IsInherited, Receiver, Call);
  finally
    Names.Free;
  end;
end;

function TNameResolver.ResolveAll(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TResolvedSymbol>;
begin
  Result := ResolveAt(ATree, AFileName, APosition);
end;

function TNameResolver.Resolve(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  Results: TArray<TResolvedSymbol>;
begin
  Results := ResolveAt(ATree, AFileName, APosition);
  if Length(Results) > 0 then
    Result := Results[0]
  else
    Result := NoResult;
end;

function TNameResolver.TypeDescendsFrom(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
  const ATypeName, ATargetName: string): Boolean;
var
  Actual, Target: TResolvedSymbol;
begin
  Actual := ResolveChain(ATree, AFileName, ATypeName.Split(['.']), AOffset);
  Target := ResolveChain(ATree, AFileName, ATargetName.Split(['.']), AOffset);
  Result := Actual.Found and Target.Found and Actual.IsType and Target.IsType and DescendsFrom(Actual, Target);
end;

end.
