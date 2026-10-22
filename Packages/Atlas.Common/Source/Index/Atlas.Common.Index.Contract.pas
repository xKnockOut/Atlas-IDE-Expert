unit Atlas.Common.Index.Contract;

// Contract des Platform-Features Index: Verzeichnis aller Deklarationen im
// Projekt und in den referenzierten Bibliotheksquellen.
//
// - Je Unit ein TUnitIndex mit Symbolen, uses-Listen, Zeitstempel und Hash.
// - ISymbolIndex ist threadsicher; der Aufbau läuft im Hintergrund, Abfragen
//   (Namensauflösung, Symbolsuche, MCP) lesen jederzeit.
// - Dateizugriffe laufen über IIndexFileSystem, damit Tests ohne Platte
//   auskommen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

type
  TIndexSymbolKind = (
    ClassType, ObjectType, RecordType, InterfaceType, HelperType, EnumType, TypeAlias,
    EnumMember, Constant, Variable, Field, Property_, Method, Constructor_, Routine);

  /// <summary>Sichtbarkeit eines Mitglieds (#263); Public auch für Symbole auf Unit-Ebene.</summary>
  TIndexVisibility = (Public, Published, Protected, StrictProtected, Private, StrictPrivate);

  TIndexSymbol = record
    Name: string;
    /// <summary>Umgebender Typ, z. B. TFoo bei TFoo.Bar; '' auf Unit-Ebene.</summary>
    Container: string;
    Kind: TIndexSymbolKind;
    /// <summary>Gesamte Deklaration.</summary>
    Range: TTextRange;
    /// <summary>Nur der Name.</summary>
    SelectionRange: TTextRange;
    /// <summary>Im interface-Abschnitt (von anderen Units sichtbar).</summary>
    InInterface: Boolean;
    /// <summary>Vorfahr und Interfaces bei Klassen und Interfaces, Zieltyp bei Helfern.</summary>
    Ancestors: TArray<string>;
    /// <summary>Deklarierter Typ bei Variablen, Feldern, Properties, Konstanten und Funktionen (Ergebnis); sonst ''.</summary>
    TypeName: string;
    /// <summary>Typargumente zu TypeName, z. B. 'TKunde' bei TList&lt;TKunde&gt; (#263); sonst ''.</summary>
    TypeArgs: string;
    /// <summary>Typargumente des ersten Vorfahren (class(TObjectList&lt;TKunde&gt;)); sonst ''.</summary>
    AncestorArgs: string;
    /// <summary>Typparameter generischer Typen und Methoden, kommagetrennt (TDictionary&lt;TKey,TValue&gt;).</summary>
    TypeParams: string;
    Visibility: TIndexVisibility;
    /// <summary>Routinen und indizierte Properties: Parameterzahl ohne bzw. mit Standardwerten.</summary>
    MinArgs: Integer;
    MaxArgs: Integer;
    /// <summary>Typen der Parameter in Reihenfolge ('' bei untypisierten).</summary>
    ParamTypes: TArray<string>;
    /// <summary>Default-Property (Liste[i]).</summary>
    IsDefault: Boolean;
    /// <summary>Deklaration einer Methode mit virtual, dynamic, abstract oder override (#125).</summary>
    IsVirtual: Boolean;
    /// <summary>Datei der Deklaration, wenn sie aus einer $I-Datei kommt (#500); '' = Datei der Unit.</summary>
    FileName: string;
    /// <summary>Bedingung, unter der die Deklaration steht ("WIN64", "not MSWINDOWS"), "platform" bei der
    /// gleichnamigen Direktive; '' = immer (#476).</summary>
    Condition: string;
    /// <summary>Steht in einem Zweig, der unter der aktiven Konfiguration nicht gilt (#476).</summary>
    Unavailable: Boolean;
    /// <summary>Feld im varianten Teil eines Records (#846): Marken seines Zweigs ("0", "mkA, mkB"),
    /// verschachtelt mit " › " verbunden ("1 › 0"); '' = kein varianter Zweig.</summary>
    VariantBranch: string;
    /// <summary>Aufzählungstyp und seine Werte unter {$SCOPEDENUMS ON} (#849): Werte gelten nur mit
    /// Typpräfix (TState.Error), nicht unqualifiziert.</summary>
    ScopedEnum: Boolean;
    /// <summary>Kopf der Deklaration als eine Zeile, z. B. "function Foo(A: Integer): string; overload;"
    /// oder "TFoo = class(TBase)" (#492); höchstens TIndexSymbol.MaxSignature Zeichen.</summary>
    Signature: string;
    /// <summary>Direktiven in Kleinschreibung und Reihenfolge der Deklaration: virtual, override,
    /// overload, static, inline, deprecated, platform … (#492).</summary>
    Directives: TArray<string>;
    /// <summary>Grund hinter deprecated 'Grund' (#38); '' ohne Grund oder ohne deprecated.</summary>
    DeprecatedText: string;
    /// <summary>Nur bei inline-Routinen (#1017): was der Rumpf aus anderen Units braucht, aufgelöst im Bereich
    /// der deklarierenden Unit. "Name" = Bezeichner, der nicht in dieser Unit deklariert ist; ":Typ" = Typ eines
    /// Felds oder einer Variablen, dessen Mitglieder der Rumpf benutzt (FListe.Count), bzw. ein Typverweis;
    /// "!Name" = Zugriff auf ein strict private-Mitglied der eigenen Klasse. nil = keine inline-Routine, nicht
    /// einbettbar (asm, with, verschachtelte Routinen) oder ohne solche Verweise.</summary>
    InlineRefs: TArray<string>;
    /// <summary>XMLDoc-Kurztext: Klartext von &lt;summary&gt; aus den ///-Zeilen darüber, eine Zeile,
    /// höchstens TIndexSymbol.MaxSummary Zeichen; '' ohne Doku (#492).</summary>
    Summary: string;
    function QualifiedName: string;
    /// <summary>Trägt die Direktive ADirective (ohne Groß-/Kleinschreibung)?</summary>
    function HasDirective(const ADirective: string): Boolean;
  public const
    MaxSignature = 300;
    MaxSummary = 200;
  end;

  /// <summary>Verwendungen eines Bezeichners in einer Unit (#492, für #470): alle Stellen außer der
  /// Deklaration selbst, nach Position sortiert.</summary>
  TIndexUsage = record
    Name: string;
    Positions: TArray<TTextPosition>;
  end;

  /// <summary>Art einer Deklaration für die Präfix-Konvention des Projekts (#452).</summary>
  TNamingKind = (Field, Parameter, Local);

  /// <summary>Deklarationen einer Art und wie viele davon das übliche Präfix tragen (F, A bzw. L vor einem
  /// Großbuchstaben).</summary>
  TNamingCount = record
    Total: Integer;
    Prefixed: Integer;
  end;

  TNamingCounts = array[TNamingKind] of TNamingCount;

const
  /// <summary>Übliche Präfixe je Art (#452): F für Felder, A für Parameter, L für lokale Variablen.</summary>
  NamingPrefixes: array[TNamingKind] of string = ('F', 'A', 'L');

type

  /// <summary>Nachschlagetabelle Name → Positionen in TUnitIndex.Symbols (Diagnoselog 15.10.2026): die
  /// Namensauflösung suchte jeden Bezeichner linear in allen Units der uses-Liste, bei großen Units
  /// (Winapi.Windows, Vcl.Controls) mehrere Sekunden je Datei. Gilt nur für das Symbol-Array, aus dem
  /// sie entstand; wird beim ersten Zugriff aufgebaut und ist threadsicher.</summary>
  IUnitNameTable = interface
    ['{6C1F4E27-93A8-4B5D-8E02-D7A4C9B36F51}']
    /// <summary>Positionen der Symbole mit diesem Namen (ohne Groß-/Kleinschreibung) aufsteigend;
    /// False, wenn ASymbols nicht das Array der Tabelle ist.</summary>
    function Positions(const ASymbols: TArray<TIndexSymbol>; const AName: string;
      out APositions: TArray<Integer>): Boolean;
  end;

  TUnitIndex = record
    UnitName: string;
    FileName: string;
    /// <summary>Zeitstempel der Datei beim Einlesen (Ticks, vom Dateisystem vorgegeben).</summary>
    Stamp: Int64;
    /// <summary>Hash des Inhalts.</summary>
    Hash: string;
    InterfaceUses: TArray<string>;
    ImplementationUses: TArray<string>;
    /// <summary>Hinweise im Unit-Kopf (unit X deprecated 'Grund' platform;) in Kleinschreibung: deprecated,
    /// experimental, platform, library (#1018).</summary>
    Directives: TArray<string>;
    /// <summary>Grund hinter deprecated im Unit-Kopf; '' ohne.</summary>
    DeprecatedText: string;
    Symbols: TArray<TIndexSymbol>;
    /// <summary>Über eine uses-Liste nachgeladen (RTL, VCL, Bibliotheken), nicht aus dem Projekt.</summary>
    Library_: Boolean;
    /// <summary>Nur interface-Symbole behalten, um das Speicherbudget einzuhalten (#185).</summary>
    Compact: Boolean;
    /// <summary>Eingebundene Include-Dateien (#264); ändert sich eine davon, wird die Unit neu eingelesen.</summary>
    Includes: TArray<string>;
    /// <summary>Zeitstempel der Include-Dateien beim Einlesen, parallel zu Includes (#617).</summary>
    IncludeStamps: TArray<Int64>;
    /// <summary>Hat einen initialization- oder finalization-Abschnitt (#284); solche Units
    /// entfernt "ungenutzte uses entfernen" nie, weil sie etwas registrieren können.</summary>
    HasInitialization: Boolean;
    /// <summary>Felder, Parameter und lokale Variablen der Unit mit Präfix gezählt (#452); daraus ermittelt
    /// die Vervollständigung die Konvention des Projekts.</summary>
    Naming: TNamingCounts;
    /// <summary>Deklarationen aus Zweigen, die unter der aktiven Konfiguration nicht gelten (#476):
    /// getrennt von Symbols, damit Namensauflösung, Referenzen und Prüfregeln sie nicht sehen;
    /// nur die Vervollständigung zeigt sie abgeschwächt.</summary>
    Unavailable: TArray<TIndexSymbol>;
    /// <summary>Verwendungen der Bezeichner (#492), nach Name sortiert; nur Projekt-Units und nur mit
    /// index.usages.</summary>
    Usages: TArray<TIndexUsage>;
    /// <summary>Verwendungen wurden erfasst (auch wenn es keine gibt); ohne sie liest der Builder die
    /// Unit neu, sobald index.usages eingeschaltet ist.</summary>
    UsagesIndexed: Boolean;
    /// <summary>Verwendungen liegen nur im Cache auf der Platte, weil das Speicherbudget überschritten
    /// war (#492); TIndexService.UsagesOf lädt sie bei Bedarf.</summary>
    UsagesOffloaded: Boolean;
    /// <summary>Nachschlagetabelle der Namen; nil, solange PrepareNames nicht lief.</summary>
    NameTable: IUnitNameTable;
    /// <summary>Datei, in der ASymbol steht: seine Include-Datei (#500), sonst FileName.</summary>
    function SymbolFile(const ASymbol: TIndexSymbol): string;
    /// <summary>Legt die Nachschlagetabelle für die aktuellen Symbols an (aufgebaut wird sie beim ersten
    /// SymbolsNamed); nach jeder Änderung an Symbols erneut aufrufen.</summary>
    procedure PrepareNames;
    /// <summary>Positionen der Symbole mit dem Namen AName in Symbols, aufsteigend; ohne passende
    /// Tabelle linear gesucht.</summary>
    function SymbolsNamed(const AName: string): TArray<Integer>;
  end;

  TSymbolLocation = record
    UnitName: string;
    FileName: string;
    Symbol: TIndexSymbol;
  end;

  ISymbolIndex = interface
    ['{8E3A51C4-7B29-4D6E-A0F8-2C9D41E7B635}']
    /// <summary>Fügt die Unit hinzu oder ersetzt den Stand derselben Datei.</summary>
    procedure AddUnit(const AUnit: TUnitIndex);
    procedure RemoveFile(const AFileName: string);
    function FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    function FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Alle Symbole mit diesem Namen (ohne Groß-/Kleinschreibung).</summary>
    function FindSymbols(const AName: string): TArray<TSymbolLocation>;
    /// <summary>Direkte Nachfahren eines Typs (Klassen, Interfaces, Helfer).</summary>
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    /// <summary>Alle Units. Das Ergebnis ist ein geteilter Schnappschuss (Code-Review P-13): nur lesen, nicht
    /// verändern.</summary>
    function Units: TArray<TUnitIndex>;
    /// <summary>Nur die Units mit Deklarationen aus nicht geltenden Zweigen (#476); meist wenige, für die
    /// Vervollständigung (Code-Review P-13).</summary>
    function UnavailableUnits: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
    /// <summary>Geschätzter Speicherbedarf der Einträge in Byte.</summary>
    function MemoryBytes: Int64;
    /// <summary>Zahl der kompakt gehaltenen Units.</summary>
    function CompactCount: Integer;
    /// <summary>Zahl der Units, deren Verwendungen wegen des Budgets ausgelagert sind (#492).</summary>
    function OffloadedCount: Integer;
    /// <summary>Obergrenze in Byte; 0 = unbegrenzt. Wird sie überschritten, hält der Index
    /// zuerst Bibliotheks-, dann Projekt-Units kompakt.</summary>
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
    /// <summary>Zählt jede Änderung am Index hoch; abgeleitete Strukturen (Namensindex, #617)
    /// erkennen daran, dass sie neu aufgebaut werden müssen.</summary>
    function Generation: Int64;
  end;

  IIndexFileSystem = interface
    ['{2F6C8B93-1E4D-4A75-9C02-B7E5D3A86F14}']
    /// <summary>Zeitstempel der Datei; False, wenn sie fehlt.</summary>
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    /// <summary>Binärer Inhalt (Index-Cache, #617); False, wenn die Datei fehlt.</summary>
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    /// <summary>Schreibt den binären Inhalt so, dass ein Leser nie einen halben Stand sieht. False mit AError
    /// (Grund ohne Pfad, für das anonyme Log), wenn es nicht ging.</summary>
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    /// <summary>Ein Schreiber je Datei über alle Prozesse (Bericht N1): sperrt AFileName, ohne zu warten; nil,
    /// wenn ein anderer sie hält. Freigeben des Ergebnisses hebt die Sperre auf.</summary>
    function TryLockWrite(const AFileName: string): IInterface;
  end;

  TIndexProgressKind = (Started, Report, Finished);

  TFileChangeKind = (Created, Changed, Deleted);

  /// <summary>Änderung einer Datei außerhalb des Editors.</summary>
  TFileChange = record
    FileName: string;
    Kind: TFileChangeKind;
    constructor Create(const AFileName: string; AKind: TFileChangeKind);
  end;

  /// <summary>Fortschritt des Aufbaus; APercent 0..100.</summary>
  TIndexProgressEvent = reference to procedure(AKind: TIndexProgressKind; const AMessage: string;
    APercent: Integer);

  /// <summary>Unit-Name → Datei; '' wenn unbekannt.</summary>
  TUnitFileResolver = reference to function(const AUnitName: string): string;

  /// <summary>Abbruch des Aufbaus abfragen.</summary>
  TIndexCancelled = reference to function: Boolean;

  /// <summary>Lädt AUnitName bei Bedarf in den Index nach (Namensauflösung, #178); True, wenn sie danach
  /// vorliegt. Steht hier statt in Atlas.Common.Semantics.NameResolver, damit Contracts sie ohne fremdes
  /// Root nutzen können (Code-Review A-10).</summary>
  TEnsureUnitFunc = reference to function(const AUnitName: string): Boolean;

  /// <summary>Stufen des Aufbaus (#648): Projektdateien samt über uses erreichbarer Units, dann alle Units
  /// der Projekt-Suchpfade, zuletzt alle Units der Bibliotheks- und Suchpfade der Installation.</summary>
  TIndexStage = (Project, SearchPaths, Library_);

  /// <summary>Reihenfolge mehrerer Aufbauten (Projekte einer Gruppe): Enter wartet, bis die Stufe dran ist,
  /// und liefert False bei Abbruch; Leave gibt sie wieder frei.</summary>
  IIndexTurn = interface
    ['{4A7E2C91-5B38-4F06-9D1A-E3C6B8F0A217}']
    function Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
    procedure Leave;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections;

type
  TUnitNameTable = class(TInterfacedObject, IUnitNameTable)
  private
    FSymbols: TArray<TIndexSymbol>;
    // Name (groß) → erste Stelle; FNext verkettet die weiteren Stellen gleichen Namens
    // aufsteigend (-1 = Ende). Spart je Name ein eigenes Array (Speicherbedarf, 15.10.2026).
    FFirst: TDictionary<string, Integer>;
    FNext: TArray<Integer>;
    procedure Build;
  public
    constructor Create(const ASymbols: TArray<TIndexSymbol>);
    destructor Destroy; override;
    function Positions(const ASymbols: TArray<TIndexSymbol>; const AName: string;
      out APositions: TArray<Integer>): Boolean;
  end;

{ TUnitNameTable }

constructor TUnitNameTable.Create(const ASymbols: TArray<TIndexSymbol>);
begin
  inherited Create;
  FSymbols := ASymbols;
end;

destructor TUnitNameTable.Destroy;
begin
  FFirst.Free;
  inherited;
end;

procedure TUnitNameTable.Build;
var
  First: TDictionary<string, Integer>;
  Position, Head: Integer;
  Key: string;
begin
  First := TDictionary<string, Integer>.Create;
  SetLength(FNext, Length(FSymbols));
  // Von hinten verketten, damit die Kette aufsteigend läuft; Zugriff über den Index, damit
  // die Symbol-Records nicht kopiert werden.
  for Position := High(FSymbols) downto 0 do
  begin
    Key := UpperCase(FSymbols[Position].Name);
    if not First.TryGetValue(Key, Head) then
      Head := -1;
    FNext[Position] := Head;
    First.AddOrSetValue(Key, Position);
  end;
  First.TrimExcess;
  FFirst := First;
end;

function TUnitNameTable.Positions(const ASymbols: TArray<TIndexSymbol>; const AName: string;
  out APositions: TArray<Integer>): Boolean;
var
  Position, Current, Count: Integer;
begin
  APositions := nil;
  if Pointer(ASymbols) <> Pointer(FSymbols) then
    Exit(False);
  if FFirst = nil then
  begin
    TMonitor.Enter(Self);
    try
      if FFirst = nil then
        Build;
    finally
      TMonitor.Exit(Self);
    end;
  end;
  Result := True;
  if not FFirst.TryGetValue(UpperCase(AName), Position) then
    Exit;
  Count := 0;
  Current := Position;
  while Current >= 0 do
  begin
    Inc(Count);
    Current := FNext[Current];
  end;
  SetLength(APositions, Count);
  Count := 0;
  Current := Position;
  while Current >= 0 do
  begin
    APositions[Count] := Current;
    Inc(Count);
    Current := FNext[Current];
  end;
end;

{ TIndexSymbol }

function TIndexSymbol.QualifiedName: string;
begin
  if Container = '' then
    Result := Name
  else
    Result := Container + '.' + Name;
end;

function TIndexSymbol.HasDirective(const ADirective: string): Boolean;
var
  Directive: string;
begin
  for Directive in Directives do
    if SameText(Directive, ADirective) then
      Exit(True);
  Result := False;
end;

{ TUnitIndex }

function TUnitIndex.SymbolFile(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.FileName <> '' then
    Result := ASymbol.FileName
  else
    Result := FileName;
end;

procedure TUnitIndex.PrepareNames;
begin
  NameTable := TUnitNameTable.Create(Symbols);
end;

function TUnitIndex.SymbolsNamed(const AName: string): TArray<Integer>;
var
  Position, Count: Integer;
begin
  if (NameTable <> nil) and NameTable.Positions(Symbols, AName, Result) then
    Exit;
  // Ohne Tabelle linear; das Ergebnis wächst in Stufen statt je Treffer um eins (Code-Review P-08).
  Result := nil;
  Count := 0;
  for Position := 0 to High(Symbols) do
    if SameText(Symbols[Position].Name, AName) then
    begin
      if Count = Length(Result) then
        SetLength(Result, Count * 2 + 4);
      Result[Count] := Position;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

{ TFileChange }

constructor TFileChange.Create(const AFileName: string; AKind: TFileChangeKind);
begin
  FileName := AFileName;
  Kind := AKind;
end;

end.
