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
//   für eingebaute Typen (string, Integer). Ein Helfer mit Vorfahr
//   (class helper (TBaseHelper) for T, #848) erbt dessen Mitglieder;
//   Ancestors des Helfers: Vorfahr-Helfer, zuletzt der Zieltyp.
// - with: Bezeichner werden zuerst in den with-Ausdrücken gesucht (innen
//   nach außen); ist ein Typ dort unbekannt, gibt es kein Ergebnis.
// - Inline-Variablen ohne Typ (var X := ..., for var I := ...) erhalten
//   den Typ ihres Ausdrucks.
// - Sichtbarkeit: private/strict private/protected aus anderen Units bzw.
//   Klassen werden ausgeblendet.
// - Ausdrücke als Empfänger: Foo(1).Bar, Liste[i].Bar, (X as TBar).Bar.
// Was nicht sicher auflösbar ist, liefert kein Ergebnis statt eines
// geratenen.
//
// Aufbau: TNameResolver ist die Fassade über die Teile in Atlas.Common.Semantics.NameResolver.* (Stelle, Units,
// Nachschlagen, Typen, Mitglieder, lokale Namen, Ausdrücke, Ketten, Kandidaten, Abfragen), die TResolverCore
// anlegt. Kandidaten für die Vervollständigung erreicht man über Candidates, Abfragen für Regeln und Aktionen über
// Queries; Hilfen ohne Zustand stehen in TResolverText und als Methoden von TResolvedSymbol.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Core,
  Atlas.Common.Semantics.NameResolver.Candidates,
  Atlas.Common.Semantics.NameResolver.Queries;

type
  TResolvedKind = Atlas.Common.Semantics.NameResolver.Symbols.TResolvedKind;
  TResolvedSymbol = Atlas.Common.Semantics.NameResolver.Symbols.TResolvedSymbol;
  TResolvedChainType = Atlas.Common.Semantics.NameResolver.Symbols.TResolvedChainType;
  TResolvedWithMember = Atlas.Common.Semantics.NameResolver.Symbols.TResolvedWithMember;
  TCandidateNameFilter = Atlas.Common.Semantics.NameResolver.Symbols.TCandidateNameFilter;
  TResolverText = Atlas.Common.Semantics.NameResolver.Symbols.TResolverText;
  TResolverCandidates = Atlas.Common.Semantics.NameResolver.Candidates.TResolverCandidates;
  TResolverQueries = Atlas.Common.Semantics.NameResolver.Queries.TResolverQueries;

  /// <summary>Alias für Bestandsnutzer; die Deklaration steht in Atlas.Common.Index.Contract.</summary>
  TEnsureUnitFunc = Atlas.Common.Index.Contract.TEnsureUnitFunc;

  TNameResolver = class
  private
    FCore: TResolverCore;
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
    function GetCandidates: TResolverCandidates;
    function GetQueries: TResolverQueries;
  public
    constructor Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AIndex: ISymbolIndex); overload;
    /// <summary>Wie Create, aber Bäume, die ATreeUnits hält, wertet der Resolver nicht selbst aus, sondern nimmt
    /// deren geteilten Stand (#1322). So extrahiert ein Prüflauf die Unit einmal statt je Typabfrage.</summary>
    constructor Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
      const ATreeUnits: ITreeUnits); overload;
    destructor Destroy; override;
    /// <summary>Typ eines aufgelösten Namens, Aliase verfolgt (Typen sind ihr eigener Typ, TFoo.Create ein TFoo);
    /// im Rahmen der zuletzt vorbereiteten Stelle (#689 nutzt es für den Grundtyp eines Alias).</summary>
    function TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Direkter Vorfahr eines Typs (ohne Angabe TObject bzw. IInterface); False ohne oder bei Helfern.</summary>
    function AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
    /// <summary>Löst den Bezeichner an APosition auf; bei gleich guten Überladungen die erste.</summary>
    function Resolve(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TResolvedSymbol;
    /// <summary>Wie Resolve, aber alle gleich guten Kandidaten, wenn die Überladung nicht eindeutig ist (#263).</summary>
    function ResolveAll(ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TResolvedSymbol>;
    /// <summary>Löst die Kette ANames (A.B.C) so auf, wie sie an AOffset stünde.</summary>
    function ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; AInherited: Boolean): TResolvedSymbol; overload;
    /// <summary>Wie oben mit AInherited = False.</summary>
    function ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TResolvedSymbol; overload;
    /// <summary>Typ des Bezeichners an APosition (Aliase verfolgt); Typen liefern sich selbst.</summary>
    function ResolveType(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition): TResolvedSymbol;
    /// <summary>Deklaration und Typ des Ausdrucks ANode aus ATree (#1005): Variable, Feld, Property (bei Liste[i]
    /// die indizierte bzw. Default-Property), Funktion eines Aufrufs. False, wenn der Ausdruck nicht sicher
    /// auflösbar ist; ATypeFound sagt, ob der Typ bekannt ist (Aliase verfolgt).</summary>
    function NodeType(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
      out ASymbol, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
    /// <summary>Kette A.B als Wert und ihr Typ (Aliase verfolgt), z. B. für Postfix-Vorlagen (#188).
    /// False, wenn die Kette nicht auflösbar ist; AResult.TypeFound sagt, ob der Typ bekannt ist.</summary>
    function ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer; out AResult: TResolvedChainType): Boolean;
    /// <summary>Alle Deklarationen, die der Bezeichner bzw. die Kette ACallee aus ATree vor den Klammern eines
    /// Aufrufs meinen kann, ohne Auswahl nach den Argumenten (#1007): Überladungen samt geerbter, Deklaration und
    /// Rumpf mit gleichen Parametern einmal. Leer, wenn ACallee nicht auflösbar ist.</summary>
    function CallCandidates(ATree: TSyntaxTree; const AFileName: string; ACallee: TSyntaxNode): TArray<TResolvedSymbol>;
    /// <summary>Mitglied AName des Typs AType samt Vorfahren und Helfern, sichtbar von der zuletzt vorbereiteten
    /// Stelle (nach NodeType, Resolve …); bei Überladungen das erste.</summary>
    function FindMember(const AType: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Mitglied AName von AType oder dem nächsten Vorfahren, der es deklariert, ohne Rücksicht auf die
    /// Sichtbarkeit (Doku-Vererbung, #654). Die Deklaration im Typ geht dem Rumpf vor.</summary>
    function DeclaredMember(const AType: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Unit, in der AResolved deklariert ist (#654).</summary>
    function DeclaringUnit(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    /// <summary>Helper für den Typ ATypeName (auch eingebaute wie string), der an AOffset wirkt (#686): der
    /// zuletzt sichtbare, eigene Unit zuerst. False ohne.</summary>
    function VisibleHelper(ATree: TSyntaxTree; const AFileName, ATypeName: string; AOffset: Integer;
      out AHelper: TResolvedSymbol): Boolean;
    /// <summary>Löst ATypeName so auf, wie er in AFromUnit stünde (z. B. Vorfahren aus dem Index).</summary>
    function ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Wie ResolveTypeFrom, aber für einen Typtext mit Typargumenten (TFabrik&lt;Integer&gt;): wählt den
    /// generischen Typ mit passender Zahl von Typparametern und bindet die Argumente; eingebaute Typen ohne
    /// Deklaration liefert es mit Builtin (#1028).
    /// TList&lt;TKunde&gt; findet so die generische TList, nicht Classes.TList (#1017).</summary>
    function ResolveTypeTextFrom(const AFromUnit: TUnitIndex; const ATypeText: string;
      out AResult: TResolvedSymbol): Boolean;
    /// <summary>Name (Typ, Routine, Konstante …) so aufgelöst, wie er in AFromUnit stünde (cref, #654).</summary>
    function ResolveNameFrom(const AFromUnit: TUnitIndex; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Ziel eines cref von AFromUnit aus (#654, #979): Typ, Typ.Mitglied, Mitglied von AContainer oder
    /// globaler Name. Parameterlisten wie in "TFoo.Bar(System.Int32)" zählen nicht; das Präfix "M:" usw. entfernt
    /// der Aufrufer (TXmlDoc.NormalizeCref).</summary>
    function LocateCref(const AFromUnit: TUnitIndex; const AContainer, ACref: string;
      out AResult: TResolvedSymbol): Boolean;
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
    /// <summary>Ist AName der Anfang eines Unit-Namens im Bereich (Atlas in Atlas.Core.Foo.Bar, Winapi in
    /// Winapi.Windows.TextOut)? Nach PinTree bzw. Resolve gültig.</summary>
    function IsUnitPrefix(const AName: string): Boolean;
    /// <summary>Bricht die Vorfahrenkette der umgebenden Klasse an einem unbekannten Typ ab (Unit nicht im
    /// Index)? Dann kann ein Name geerbt sein (ClientWidth aus TControl). Nach PinTree bzw. Resolve gültig.</summary>
    function HasUnknownAncestor: Boolean;
    /// <summary>Kann ein Mitglied außerhalb des Index den Bezeichner ACallee aus ATree verdecken, sodass
    /// ACandidate gar nicht gemeint ist (#1326)? Ja bei einem with-Objekt, dessen Typ den Namen nicht kennt, aber
    /// einen unbekannten Vorfahren hat, und bei einer Methode, deren Klasse einen unbekannten Vorfahren hat, wenn
    /// ACandidate weder lokal noch ein Mitglied ist (Error aus TStrings statt einer freien Routine Error).</summary>
    function MayBeHiddenMember(ATree: TSyntaxTree; const AFileName: string; ACallee: TSyntaxNode;
      const ACandidate: TResolvedSymbol): Boolean;
    /// <summary>Liest die Property AProperty direkt aus einem Feld (read FFeld, read FFeld.X)? False, wenn das
    /// nicht sicher feststeht (kein read, Typ oder Mitglied unbekannt); sonst AReadsField (#1005).</summary>
    function PropertyReadsField(const AProperty: TResolvedSymbol; out AReadsField: Boolean): Boolean;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace) für uses ohne Präfix.</summary>
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Kandidaten für die Vervollständigung (sichtbare Namen, Mitglieder, inherited, NameFilter).</summary>
    property Candidates: TResolverCandidates read GetCandidates;
    /// <summary>Abfragen für Regeln und Codeaktionen (fehlende Interface-Methoden, Accessoren, Überschreibungen,
    /// Attribut- und Exception-Klassen, with-Mitglieder …).</summary>
    property Queries: TResolverQueries read GetQueries;
  end;

implementation

constructor TNameResolver.Create(const AIndex: ISymbolIndex);
begin
  Create(AIndex, nil, nil);
end;

constructor TNameResolver.Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc);
begin
  Create(AIndex, AEnsureUnit, nil);
end;

constructor TNameResolver.Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
  const ATreeUnits: ITreeUnits);
begin
  inherited Create;
  FCore := TResolverCore.Create(AIndex, AEnsureUnit, ATreeUnits);
end;

destructor TNameResolver.Destroy;
begin
  FCore.Free;
  inherited;
end;

function TNameResolver.GetNamespaces: TArray<string>;
begin
  Result := FCore.Units.Namespaces;
end;

procedure TNameResolver.SetNamespaces(const AValue: TArray<string>);
begin
  FCore.Units.Namespaces := AValue;
end;

function TNameResolver.GetCandidates: TResolverCandidates;
begin
  Result := FCore.Candidates;
end;

function TNameResolver.GetQueries: TResolverQueries;
begin
  Result := FCore.Queries;
end;

function TNameResolver.TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
begin
  Result := FCore.Typing.TypeOf(AResolved, AType);
end;

function TNameResolver.AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
begin
  Result := FCore.Typing.AncestorOf(AType, AAncestor);
end;

function TNameResolver.Resolve(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  mResults: TArray<TResolvedSymbol>;
begin
  mResults := FCore.Chains.ResolveAt(ATree, AFileName, APosition);
  if Length(mResults) > 0 then
  begin
    Result := mResults[0];
  end
  else
  begin
    Result := TResolvedSymbol.Empty;
  end;
end;

function TNameResolver.ResolveAll(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TResolvedSymbol>;
begin
  Result := FCore.Chains.ResolveAt(ATree, AFileName, APosition);
end;

function TNameResolver.ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; AInherited: Boolean): TResolvedSymbol;
begin
  Result := FCore.Chains.ResolveChain(ATree, AFileName, ANames, AOffset, AInherited);
end;

function TNameResolver.ResolveChain(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer): TResolvedSymbol;
begin
  Result := FCore.Chains.ResolveChain(ATree, AFileName, ANames, AOffset, False);
end;

function TNameResolver.ResolveType(ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  mSymbol, mType: TResolvedSymbol;
begin
  // Resolve setzt die Stelle (aktuelle Unit, Abschnitt), die TypeOf braucht.
  mSymbol := Resolve(ATree, AFileName, APosition);
  if (mSymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and FCore.Typing.TypeOf(mSymbol, mType) and
    not mType.Builtin then
  begin
    Result := mType;
  end
  else
  begin
    Result := TResolvedSymbol.Empty;
  end;
end;

function TNameResolver.NodeType(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out ASymbol, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
begin
  Result := FCore.Chains.NodeType(ATree, AFileName, ANode, ASymbol, AType, ATypeFound);
end;

function TNameResolver.ChainType(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
  AOffset: Integer; out AResult: TResolvedChainType): Boolean;
begin
  Result := FCore.Chains.ChainType(ATree, AFileName, ANames, AOffset, AResult);
end;

function TNameResolver.CallCandidates(ATree: TSyntaxTree; const AFileName: string;
  ACallee: TSyntaxNode): TArray<TResolvedSymbol>;
begin
  Result := FCore.Chains.CallCandidates(ATree, AFileName, ACallee);
end;

function TNameResolver.FindMember(const AType: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  Result := FCore.Members.FindMember(AType, AName, AResult);
end;

function TNameResolver.DeclaredMember(const AType: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  Result := FCore.Members.DeclaredMember(AType, AName, AResult);
end;

function TNameResolver.DeclaringUnit(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  Result := FCore.Units.UnitOf(AResolved, AUnit);
end;

function TNameResolver.VisibleHelper(ATree: TSyntaxTree; const AFileName, ATypeName: string; AOffset: Integer;
  out AHelper: TResolvedSymbol): Boolean;
begin
  Result := FCore.Queries.VisibleHelper(ATree, AFileName, ATypeName, AOffset, AHelper);
end;

function TNameResolver.ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  Result := FCore.Queries.ResolveTypeFrom(AFromUnit, ATypeName, AResult);
end;

function TNameResolver.ResolveTypeTextFrom(const AFromUnit: TUnitIndex; const ATypeText: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  Result := FCore.Queries.ResolveTypeTextFrom(AFromUnit, ATypeText, AResult);
end;

function TNameResolver.ResolveNameFrom(const AFromUnit: TUnitIndex; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  Result := FCore.Queries.ResolveNameFrom(AFromUnit, AName, AResult);
end;

function TNameResolver.LocateCref(const AFromUnit: TUnitIndex; const AContainer, ACref: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  Result := FCore.Queries.LocateCref(AFromUnit, AContainer, ACref, AResult);
end;

procedure TNameResolver.PinTree(ATree: TSyntaxTree; const AFileName: string);
begin
  FCore.Place.PinTree(ATree, AFileName);
end;

procedure TNameResolver.UnpinTree;
begin
  FCore.Place.UnpinTree;
end;

function TNameResolver.ExtractedUnit(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
begin
  Result := FCore.Place.ExtractedUnit(ATree, AFileName);
end;

function TNameResolver.IsUnitPrefix(const AName: string): Boolean;
begin
  Result := FCore.Units.IsUnitPrefix(AName);
end;

function TNameResolver.HasUnknownAncestor: Boolean;
begin
  Result := FCore.Typing.HasUnknownAncestor;
end;

function TNameResolver.MayBeHiddenMember(ATree: TSyntaxTree; const AFileName: string; ACallee: TSyntaxNode;
  const ACandidate: TResolvedSymbol): Boolean;
begin
  Result := FCore.Chains.MayBeHiddenMember(ATree, AFileName, ACallee, ACandidate);
end;

function TNameResolver.PropertyReadsField(const AProperty: TResolvedSymbol; out AReadsField: Boolean): Boolean;
begin
  Result := FCore.Queries.PropertyReadsField(AProperty, AReadsField);
end;

end.
