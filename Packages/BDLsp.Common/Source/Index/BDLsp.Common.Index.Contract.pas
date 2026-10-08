unit BDLsp.Common.Index.Contract;

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
  BDLsp.Common.Documents.Contract;

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
    function QualifiedName: string;
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
    Symbols: TArray<TIndexSymbol>;
    /// <summary>Über eine uses-Liste nachgeladen (RTL, VCL, Bibliotheken), nicht aus dem Projekt.</summary>
    Library_: Boolean;
    /// <summary>Nur interface-Symbole behalten, um das Speicherbudget einzuhalten (#185).</summary>
    Compact: Boolean;
    /// <summary>Eingebundene Include-Dateien (#264); ändert sich eine davon, wird die Unit neu eingelesen.</summary>
    Includes: TArray<string>;
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
    function Units: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
    /// <summary>Geschätzter Speicherbedarf der Einträge in Byte.</summary>
    function MemoryBytes: Int64;
    /// <summary>Zahl der kompakt gehaltenen Units.</summary>
    function CompactCount: Integer;
    /// <summary>Obergrenze in Byte; 0 = unbegrenzt. Wird sie überschritten, hält der Index
    /// zuerst Bibliotheks-, dann Projekt-Units kompakt.</summary>
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
  end;

  IIndexFileSystem = interface
    ['{2F6C8B93-1E4D-4A75-9C02-B7E5D3A86F14}']
    /// <summary>Zeitstempel der Datei; False, wenn sie fehlt.</summary>
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
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

implementation

{ TIndexSymbol }

function TIndexSymbol.QualifiedName: string;
begin
  if Container = '' then
    Result := Name
  else
    Result := Container + '.' + Name;
end;

{ TFileChange }

constructor TFileChange.Create(const AFileName: string; AKind: TFileChangeKind);
begin
  FileName := AFileName;
  Kind := AKind;
end;

end.
