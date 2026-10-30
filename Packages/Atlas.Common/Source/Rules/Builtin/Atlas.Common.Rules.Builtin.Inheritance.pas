unit Atlas.Common.Rules.Builtin.Inheritance;

// Klassische Deklarationsfehler bei der Vererbung (#125), alles Varianten von
// W1010, aber schon beim Tippen und mit Korrektur:
//   destroy-without-override            destructor Destroy ohne override
//   component-create-without-override   constructor Create(AOwner: TComponent)
//                                       ohne override in TComponent-Nachfahren
//   hides-virtual                       Methode verdeckt eine virtuelle des Vorfahren
//   virtual-instead-of-override         virtual statt override bei gleicher Signatur
//   shadowed-name                       Parameter oder lokale Variable heißt wie ein Feld, eine
//                                       Property (auch geerbt) oder eine globale Variable der Unit (#934)
//   override-target-missing             override ohne passende virtuelle Methode im Vorfahren (E2137),
//                                       auf eine statische (E2170) oder finale (E2352), Ableiten von
//                                       einer sealed-Klasse (E2353) (#997)
//   abstract-class-instantiated         Create auf einer Klasse mit offenen abstrakten Methoden (W1020)
//                                       (#999); "class abstract" allein erzwingt dcc nicht (E2402 gibt es
//                                       nur unter .NET, #1383)
//   inherited-abstract-call             inherited Name(…) auf eine im Vorfahren abstrakte Methode (#1026):
//                                       läuft in EAbstractError; Delphi 13 übersetzt das ohne E2373
//                                       (#1383). Die Methode löst TNameResolver samt Überladungen auf
//   class-reference-nonvirtual-constructor  Create über eine Klassenreferenz (class of TBasis), deren
//                                       Konstruktor nicht virtuell ist (E2391, #1032); läuft immer der
//                                       Konstruktor der Basisklasse
//   member-hides-ancestor               Property heißt wie ein Feld des Vorfahren (W1009), Feld wie ein
//                                       Feld oder eine Property, nicht virtuelle Methode wie eine gleich
//                                       aufgebaute nicht virtuelle des Vorfahren (#1003, ohne Code: dcc
//                                       schweigt dort, #1383); strict private des Vorfahren nur mit
//                                       ignoreStrictPrivate = false
//   override-case-mismatch              Schreibweise oder Sichtbarkeit weicht ab (#1021, aus): override
//                                       anders geschrieben als der Vorfahr (H2365) oder weniger sichtbar
//                                       (H2269, nur Klassen im interface-Teil), Getter/Setter Get<Name>
//                                       bzw. Set<Name> anders geschrieben, inline-Methode greift auf ein
//                                       weniger sichtbares Mitglied zu (beide ohne Code: H2367 und H2440
//                                       meldet Delphi 13 dort nicht, #1383)
//   override-only-inherited             override, dessen Rumpf nur inherited mit unveränderten Parametern
//                                       aufruft (#1143); still bei geänderter Sichtbarkeit, Attributen,
//                                       Kommentaren oder Direktiven im Rumpf, final, deprecated, Standardwerten
//                                       und lokalen Deklarationen. Korrektur entfernt Deklaration und Rumpf
//                                       samt XMLDoc
//   inherited-without-ancestor          bloßes inherited; in einer neuen Methode, die kein Vorfahr kennt
//                                       (#1144): tut nichts, meist fehlt override. Nicht in Konstruktoren,
//                                       Destruktoren und Message-Handlern; unbekannter Vorfahr: still.
//                                       Korrektur entfernt das inherited
//
// Vorfahren werden zuerst in der Datei, dann im Symbolindex gesucht (auch RTL
// und VCL, soweit eingelesen). Ist ein Vorfahr nicht auflösbar oder mehrdeutig,
// endet die Suche ohne Treffer. Mit reintroduce oder override schweigen alle
// Regeln; eine Überladung (overload) mit anderer Signatur ebenso.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  /// <summary>Eine Methodendeklaration einer Klasse der geprüften Datei.</summary>
  TMethodDecl = record
    ClassName: string;
    Header: TSyntaxNode;
    Symbol: TIndexSymbol;
    /// <summary>procedure, function, constructor, destructor (klein).</summary>
    Keyword: string;
    Directives: TArray<string>;
    function Has(const ADirective: string): Boolean;
  end;

  /// <summary>Gefundene virtuelle Methode eines Vorfahren.</summary>
  TInherited = record
    Found: Boolean;
    TypeName: string;
    Symbol: TIndexSymbol;
    SameSignature: Boolean;
  end;

  /// <summary>Löst Vorfahren über die Datei und den Index auf; auch für die Komponentenregeln (#55).</summary>
  TAncestry = class
  private
    FIndex: ISymbolIndex;
    FLocal: TUnitIndex;
    function FindType(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Klasse AName mit AArity Typparametern (#1326: THorseChannel und THorseChannel&lt;T&gt; sind zwei
    /// Typen); AArity &lt; 0 = Zahl unbekannt, jede passt.</summary>
    function FindTypeOf(const AName: string; AArity: Integer; out AType: TSymbolLocation): Boolean;
    /// <summary>Direkter Vorfahr von AType, mit der Zahl seiner Typargumente aufgelöst; TObject ohne Angabe.
    /// AName: sein Name ohne Unit und Typargumente.</summary>
    function ParentLocation(const AType: TSymbolLocation; out AName: string; out AParent: TSymbolLocation): Boolean;
    /// <summary>Ist der Treffer aus dem Index von dieser Datei aus sichtbar? Typen aus dem implementation-Teil
    /// anderer Units nicht (sonst wurde TFrame einer fremden Unit zum Vorfahren von VCL-Frames).</summary>
    function Reachable(const ALocation: TSymbolLocation): Boolean;
    function MethodsOf(const AType: TSymbolLocation; const AName: string): TArray<TIndexSymbol>;
  public
    /// <summary>ALocal ist der Index der geprüften Datei (TRuleDerived.UnitIndex, Review P-03).</summary>
    constructor Create(const AIndex: ISymbolIndex; const ALocal: TUnitIndex);
    /// <summary>Name des direkten Vorfahren; TObject ohne Angabe; '' wenn der Typ unbekannt ist.</summary>
    function ParentOf(const ATypeName: string): string;
    /// <summary>Erbt ATypeName (auch über mehrere Stufen) von AAncestor? False, wenn die Kette abbricht.</summary>
    function DescendsFrom(const ATypeName, AAncestor: string): Boolean;
    /// <summary>Deklariert die Klasse ATypeName selbst einen Konstruktor (Datei oder Index, #919)?</summary>
    function HasConstructor(const ATypeName: string): Boolean;
    /// <summary>Nächste gleichnamige Methode in den Vorfahren, falls sie virtuell ist.</summary>
    function InheritedVirtual(const AMethod: TMethodDecl): TInherited;
    /// <summary>Feld oder Property AName in ATypeName oder einem Vorfahren, das dort sichtbar ist (#934).
    /// Bricht die Kette ab, steht in AUnresolved der Vorfahr, der weder in der Datei noch im Index steht.</summary>
    function FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol; out AUnresolved: string): Boolean;
      overload;
    /// <summary>Wie oben; AUnitName nennt die Unit der Klasse, die das Mitglied deklariert ('' für diese Datei).
    /// </summary>
    function FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol; out AUnresolved,
      AUnitName: string): Boolean; overload;
    /// <summary>Vorfahren von ATypeName vom direkten an aufwärts (#997). AComplete: die Kette reicht bis TObject;
    /// AObjectMissing: TObject selbst steht weder in der Datei noch im Index.</summary>
    function Ancestors(const ATypeName: string; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
      overload;
    /// <summary>Wie oben ab dem schon gefundenen Typ AType (#1326): Bei gleichnamigen Typen mit und ohne
    /// Typparameter gilt so der richtige.</summary>
    function Ancestors(const AType: TSymbolLocation; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
      overload;
    /// <summary>Klasse dieser Datei, in deren Rumpf das Mitglied AMember steht (#1326); False ohne.</summary>
    function OwnerOf(const AMember: TIndexSymbol; out AType: TSymbolLocation): Boolean;
    /// <summary>Klasse AName aus der Datei oder eindeutig aus dem Index (#999).</summary>
    function FindClass(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Methoden, Konstruktoren und Destruktoren der Klasse AType (#997).</summary>
    function Methods(const AType: TSymbolLocation): TArray<TIndexSymbol>;
    /// <summary>Abstrakte Methoden von AType und seinen Vorfahren, die keine nähere Stufe neu deklariert; AOwners
    /// nennt je Methode die Klasse (W1020, #1380). Überladungen unterscheidet die Zahl der Parameter. Bricht die
    /// Kette ab, fehlen nur die Methoden jenseits der Lücke.</summary>
    function OpenAbstractMethods(const AType: TSymbolLocation; out AOwners: TArray<string>): TArray<TIndexSymbol>;
    /// <summary>Ist AName in der Datei oder im Index als Typalias deklariert (type TModus = Integer)?</summary>
    function IsTypeAlias(const AName: string): Boolean;
    /// <summary>Ist AName in der Datei oder im Index als eigener Typ deklariert (Klasse, Record, Aufzählung,
    /// Interface), also kein Alias?</summary>
    function IsDeclaredType(const AName: string): Boolean;
    /// <summary>Typ AName jeder Art (Klasse, Record, Interface, Aufzählung, Alias) aus der Datei oder dem Index
    /// (#1001); bei mehreren gleichnamigen der erste.</summary>
    function FindAnyType(const AName: string; out AType: TSymbolLocation): Boolean;
    /// <summary>Felder, Properties, Methoden und Konstruktoren des Typs AType (#1001).</summary>
    function Members(const AType: TSymbolLocation): TArray<TIndexSymbol>;
    /// <summary>Bezeichnen A und B denselben Typ? Synonyme (Longint, Integer) gleich; Typparameter aus
    /// AWildcards und Aliase der Datei oder des Index passen zu allem (#997, #1001).</summary>
    function SameType(const A, B: string; const AWildcards: TArray<string>): Boolean;
    /// <summary>Steht der Typ sicher für sich (eingebaut oder als Klasse, Record, Aufzählung deklariert)?</summary>
    function KnownType(const AName: string): Boolean;
    property Local: TUnitIndex read FLocal;
  end;

  TDestroyWithoutOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentCreateWithoutOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  THidesVirtualRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TVirtualInsteadOfOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TShadowedNameRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TOverrideTargetMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TAbstractClassInstantiatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedAbstractCallRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Trägt der Methodenkopf ASignature die Direktive abstract ("procedure A; virtual; abstract;")?
    /// </summary>
    class function IsAbstractSignature(const ASignature: string): Boolean; static;
  end;

  TClassReferenceNonvirtualConstructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zieltyp aus "TPluginKlasse = class of TPlugin"; '' ohne class of.</summary>
    class function ClassRefTarget(const ASignature: string): string; static;
  end;

  TMemberHidesAncestorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TOverrideCaseMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TOverrideOnlyInheritedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedWithoutAncestorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  MemberHidesAncestorRuleId = 'member-hides-ancestor';
  OverrideCaseMismatchRuleId = 'override-case-mismatch';
  OverrideOnlyInheritedRuleId = 'override-only-inherited';
  InheritedWithoutAncestorRuleId = 'inherited-without-ancestor';

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Unused,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Index.LibraryUnits,
  Atlas.Text.Fuzzy;

function TMethodDecl.Has(const ADirective: string): Boolean;
begin
  Result := MatchText(ADirective, Directives);
end;

/// <summary>Typname ohne Unit-Präfix und Typargumente.</summary>
function BareName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean;
begin
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line);
end;

function SameSignature(const A, B: TIndexSymbol): Boolean;
var
  Index: Integer;
begin
  Result := (A.MaxArgs = B.MaxArgs) and (Length(A.ParamTypes) = Length(B.ParamTypes)) and
    SameText(A.TypeName, B.TypeName);
  if Result then
    for Index := 0 to High(A.ParamTypes) do
      if not SameText(BareName(A.ParamTypes[Index]), BareName(B.ParamTypes[Index])) then
        Exit(False);
end;

const
  // Virtuelle Instanzmethoden von TObject, falls System nicht im Index steht.
  ObjectVirtualNames: array[0..9] of string = ('AfterConstruction', 'BeforeDestruction', 'Dispatch',
    'DefaultHandler', 'FreeInstance', 'Destroy', 'SafeCallException', 'ToString', 'Equals', 'GetHashCode');
  // Gleiche Typen unter anderem Namen: Name=Grundname.
  TypeSynonyms: array[0..17] of string = ('longint=integer', 'int32=integer', 'longword=cardinal',
    'uint32=cardinal', 'dword=cardinal', 'unicodestring=string', 'widechar=char', 'pwidechar=pchar',
    'intptr=nativeint', 'uintptr=nativeuint', 'int16=smallint', 'int8=shortint', 'uint8=byte', 'uint16=word',
    'real=double', 'tobject=tobject', 'system.tobject=tobject', 'hresult=hresult');
  // Eingebaute Typen, die sicher kein Alias eines anderen sind.
  BuiltinTypes: array[0..25] of string = ('integer', 'cardinal', 'int64', 'uint64', 'string', 'ansistring',
    'shortstring', 'widestring', 'char', 'ansichar', 'boolean', 'double', 'single', 'extended', 'currency', 'byte',
    'word', 'smallint', 'shortint', 'pointer', 'variant', 'tobject', 'nativeint', 'nativeuint', 'pchar',
    'tdatetime');

function CanonicalType(const AName: string): string;
var
  Pair: string;
begin
  Result := LowerCase(BareName(AName));
  for Pair in TypeSynonyms do
    if StartsStr(Result + '=', Pair) then
      Exit(Copy(Pair, Length(Result) + 2, MaxInt));
end;

{ TAncestry }

constructor TAncestry.Create(const AIndex: ISymbolIndex; const ALocal: TUnitIndex);
begin
  inherited Create;
  FIndex := AIndex;
  FLocal := ALocal;
end;

function TAncestry.Reachable(const ALocation: TSymbolLocation): Boolean;
begin
  Result := ALocation.Symbol.InInterface or (ALocation.FileName = '') or SameText(ALocation.FileName, FLocal.FileName);
end;

/// <summary>Zahl der Einträge in einer Liste von Typparametern bzw. -argumenten ("K, V", "string, TList&lt;T&gt;");
/// 0 bei ''.</summary>
function GenericArity(const AList: string): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := 0;
  if Trim(AList) = '' then
    Exit;
  Result := 1;
  mDepth := 0;
  for mIndex := 1 to Length(AList) do
    case AList[mIndex] of
      '<', '(', '[':
        Inc(mDepth);
      '>', ')', ']':
        Dec(mDepth);
      ',':
        if mDepth = 0 then
          Inc(Result);
    end;
end;

/// <summary>Zahl der Typargumente in einem Namen wie "TFoo&lt;T, U&gt;"; -1 ohne spitze Klammern (unbekannt: Die
/// Regeln geben Klassen generischer Typen oft ohne Parameter weiter).</summary>
function NameArity(const AName: string): Integer;
var
  mOpen: Integer;
begin
  mOpen := Pos('<', AName);
  if mOpen = 0 then
    Exit(-1);
  Result := GenericArity(Copy(AName, mOpen + 1, LastDelimiter('>', AName) - mOpen - 1));
end;

function TAncestry.FindType(const AName: string; out AType: TSymbolLocation): Boolean;
var
  mName: string;
begin
  mName := AName;
  if Pos('<', mName) > 0 then
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  Result := FindTypeOf(mName, NameArity(AName), AType);
end;

function TAncestry.FindTypeOf(const AName: string; AArity: Integer; out AType: TSymbolLocation): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Found: Boolean;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and SameText(Symbol.Name, AName) and
      ((AArity < 0) or (GenericArity(Symbol.TypeParams) = AArity)) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := Symbol;
      Exit(True);
    end;
  Result := False;
  if FIndex = nil then
    Exit;
  Found := False;
  for Location in FIndex.FindSymbols(AName) do
  begin
    if (Location.Symbol.Kind <> TIndexSymbolKind.ClassType) or (Location.Symbol.Container <> '') or
      not Reachable(Location) or ((AArity >= 0) and (GenericArity(Location.Symbol.TypeParams) <> AArity)) then
      Continue;
    if not Found then
    begin
      AType := Location;
      Found := True;
    end
    // Mehrere gleichnamige Klassen mit verschiedenen Vorfahren: keine Aussage.
    else if (Length(Location.Symbol.Ancestors) > 0) <> (Length(AType.Symbol.Ancestors) > 0) or
      ((Length(AType.Symbol.Ancestors) > 0) and
      not SameText(BareName(Location.Symbol.Ancestors[0]), BareName(AType.Symbol.Ancestors[0]))) then
      Exit(False);
  end;
  Result := Found;
end;

function TAncestry.Methods(const AType: TSymbolLocation): TArray<TIndexSymbol>;
var
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Symbol in Members(AType) do
    if Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_] then
      Result := Result + [Symbol];
end;

function TAncestry.Members(const AType: TSymbolLocation): TArray<TIndexSymbol>;
var
  Symbols: TArray<TIndexSymbol>;
  Symbol: TIndexSymbol;
  UnitIndex: TUnitIndex;
begin
  Result := nil;
  if AType.FileName = '' then
    Symbols := FLocal.Symbols
  else if (FIndex <> nil) and FIndex.FindFile(AType.FileName, UnitIndex) then
    Symbols := UnitIndex.Symbols
  else
    Exit;
  for Symbol in Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method,
      TIndexSymbolKind.Constructor_]) and SameText(Symbol.Container, AType.Symbol.Name) and
      ContainsLine(AType.Symbol.Range, Symbol.Range.StartPos.Line) then
      Result := Result + [Symbol];
end;

function TAncestry.FindAnyType(const AName: string; out AType: TSymbolLocation): Boolean;
const
  Kinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind in Kinds) and (Symbol.Container = '') and SameText(Symbol.Name, AName) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := Symbol;
      Exit(True);
    end;
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(AName) do
      if (Location.Symbol.Kind in Kinds) and (Location.Symbol.Container = '') and Reachable(Location) then
      begin
        AType := Location;
        Exit(True);
      end;
  Result := False;
end;

function TAncestry.SameType(const A, B: string; const AWildcards: TArray<string>): Boolean;
begin
  Result := (CanonicalType(A) = CanonicalType(B)) or MatchText(BareName(A), AWildcards) or
    MatchText(BareName(B), AWildcards);
  // Ein Alias der Datei oder des Index kann auf den anderen Typ zeigen: keine Aussage.
  if not Result and (A <> '') and (B <> '') then
    Result := IsTypeAlias(BareName(A)) or IsTypeAlias(BareName(B));
end;

function TAncestry.KnownType(const AName: string): Boolean;
begin
  Result := MatchText(CanonicalType(AName), BuiltinTypes) or IsDeclaredType(BareName(AName));
end;

function TAncestry.OpenAbstractMethods(const AType: TSymbolLocation; out AOwners: TArray<string>):
  TArray<TIndexSymbol>;
var
  mChain: TArray<TSymbolLocation>;
  mLocation: TSymbolLocation;
  mSymbol: TIndexSymbol;
  mSeen, mLevel: TArray<string>;
  mKey: string;
  mComplete, mObjectMissing: Boolean;
begin
  Result := nil;
  AOwners := nil;
  mSeen := nil;
  mChain := [AType] + Ancestors(AType.Symbol.Name, mComplete, mObjectMissing);
  for mLocation in mChain do
  begin
    mLevel := nil;
    for mSymbol in Methods(mLocation) do
    begin
      // Überladungen unterscheidet die Zahl der Parameter; gleich viele gelten als dieselbe Methode.
      mKey := LowerCase(mSymbol.Name) + '/' + IntToStr(mSymbol.MaxArgs);
      if mSymbol.HasDirective('abstract') and (IndexText(mKey, mSeen) < 0) then
      begin
        Result := Result + [mSymbol];
        AOwners := AOwners + [mLocation.Symbol.Name];
      end;
      mLevel := mLevel + [mKey];
    end;
    mSeen := mSeen + mLevel;
  end;
end;

function TAncestry.MethodsOf(const AType: TSymbolLocation; const AName: string): TArray<TIndexSymbol>;
var
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Symbol in Methods(AType) do
    if SameText(Symbol.Name, AName) then
      Result := Result + [Symbol];
end;

function TAncestry.ParentLocation(const AType: TSymbolLocation; out AName: string;
  out AParent: TSymbolLocation): Boolean;
var
  mArity: Integer;
begin
  if Length(AType.Symbol.Ancestors) = 0 then
  begin
    AName := 'TObject';
    mArity := 0;
  end
  else
  begin
    AName := BareName(AType.Symbol.Ancestors[0]);
    // Ohne Typargumente ist der Vorfahr nicht generisch: class(THorseChannel) neben THorseChannel<T>.
    mArity := 0;
    if Length(AType.Symbol.AncestorArgs) > 0 then
      mArity := GenericArity(AType.Symbol.AncestorArgs[0]);
  end;
  Result := FindTypeOf(AName, mArity, AParent);
end;

function TAncestry.Ancestors(const ATypeName: string; out AComplete, AObjectMissing: Boolean): TArray<TSymbolLocation>;
var
  mOwn: TSymbolLocation;
begin
  Result := nil;
  AComplete := False;
  AObjectMissing := False;
  if FindType(ATypeName, mOwn) then
    Result := Ancestors(mOwn, AComplete, AObjectMissing);
end;

function TAncestry.Ancestors(const AType: TSymbolLocation; out AComplete,
  AObjectMissing: Boolean): TArray<TSymbolLocation>;
var
  Name: string;
  Current, Location: TSymbolLocation;
  Depth: Integer;
begin
  Result := nil;
  AComplete := False;
  AObjectMissing := False;
  Current := AType;
  for Depth := 0 to 63 do
  begin
    if not ParentLocation(Current, Name, Location) then
    begin
      AObjectMissing := SameText(Name, 'TObject');
      AComplete := AObjectMissing;
      Exit;
    end;
    Result := Result + [Location];
    if SameText(Name, 'TObject') then
    begin
      AComplete := True;
      Exit;
    end;
    Current := Location;
  end;
end;

function TAncestry.OwnerOf(const AMember: TIndexSymbol; out AType: TSymbolLocation): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FLocal.Symbols do
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.QualifiedName, AMember.Container) and
      ContainsLine(mSymbol.Range, AMember.Range.StartPos.Line) then
    begin
      AType := Default(TSymbolLocation);
      AType.Symbol := mSymbol;
      Exit(True);
    end;
  Result := False;
end;

function TAncestry.FindClass(const AName: string; out AType: TSymbolLocation): Boolean;
begin
  Result := FindType(AName, AType);
end;

function TAncestry.IsDeclaredType(const AName: string): Boolean;
const
  Kinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType];
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind in Kinds) and (Symbol.Container = '') and SameText(Symbol.Name, AName) then
      Exit(True);
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(AName) do
      if (Location.Symbol.Kind in Kinds) and (Location.Symbol.Container = '') and Reachable(Location) then
        Exit(True);
  Result := False;
end;

function TAncestry.IsTypeAlias(const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in FLocal.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.TypeAlias) and SameText(Symbol.Name, AName) then
      Exit(True);
  if FIndex <> nil then
    for Location in FIndex.FindSymbols(AName) do
      if (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) and Reachable(Location) then
        Exit(True);
  Result := False;
end;

function TAncestry.HasConstructor(const ATypeName: string): Boolean;
var
  Location: TSymbolLocation;
  Symbols: TArray<TIndexSymbol>;
  Symbol: TIndexSymbol;
  UnitIndex: TUnitIndex;
begin
  Result := False;
  if not FindType(ATypeName, Location) then
    Exit;
  if Location.FileName = '' then
    Symbols := FLocal.Symbols
  else if (FIndex <> nil) and FIndex.FindFile(Location.FileName, UnitIndex) then
    Symbols := UnitIndex.Symbols
  else
    Exit;
  for Symbol in Symbols do
    // Der Index führt Destruktoren ebenfalls als Constructor_.
    if (Symbol.Kind = TIndexSymbolKind.Constructor_) and not SameText(Symbol.Name, 'Destroy') and
      SameText(Symbol.Container, Location.Symbol.Name) and
      ContainsLine(Location.Symbol.Range, Symbol.Range.StartPos.Line) then
      Exit(True);
end;

function TAncestry.ParentOf(const ATypeName: string): string;
var
  Location: TSymbolLocation;
begin
  if not FindType(ATypeName, Location) then
    Exit('');
  if Length(Location.Symbol.Ancestors) = 0 then
    Result := 'TObject'
  else
    Result := BareName(Location.Symbol.Ancestors[0]);
end;

function TAncestry.DescendsFrom(const ATypeName, AAncestor: string): Boolean;
var
  Name: string;
  Depth: Integer;
begin
  Name := ParentOf(ATypeName);
  Depth := 0;
  while (Name <> '') and (Depth < 64) do
  begin
    if SameText(Name, AAncestor) then
      Exit(True);
    if SameText(Name, 'TObject') then
      Break;
    Name := ParentOf(Name);
    Inc(Depth);
  end;
  Result := False;
end;

function TAncestry.InheritedVirtual(const AMethod: TMethodDecl): TInherited;
var
  Own, Location: TSymbolLocation;
  Candidate: TIndexSymbol;
  Any, mComplete, mObjectMissing: Boolean;
begin
  Result := Default(TInherited);
  // Die Klasse, in deren Rumpf die Methode steht, nicht nur ihr Name (#1326).
  if not OwnerOf(AMethod.Symbol, Own) and not FindType(AMethod.ClassName, Own) then
    Exit;
  for Location in Ancestors(Own, mComplete, mObjectMissing) do
  begin
    Any := False;
    for Candidate in MethodsOf(Location, AMethod.Symbol.Name) do
    begin
      // Private Methoden fremder Units sieht der Nachfahre nicht.
      if (Location.FileName <> '') and (Candidate.Visibility in [TIndexVisibility.Private,
        TIndexVisibility.StrictPrivate]) then
        Continue;
      Any := True;
      if not Candidate.IsVirtual then
        Continue;
      if not Result.Found or (not Result.SameSignature and SameSignature(Candidate, AMethod.Symbol)) then
      begin
        Result.Found := True;
        Result.TypeName := Location.Symbol.Name;
        Result.Symbol := Candidate;
        Result.SameSignature := SameSignature(Candidate, AMethod.Symbol);
      end;
    end;
    // Die nächste Stufe mit gleichnamiger Methode entscheidet.
    if Any then
      Exit;
  end;
end;

{ Hilfen für die Regeln }

function TokenAt(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
    if Token.Offset = AOffset then
    begin
      AToken := Token;
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Position hinter dem letzten Token vor AEndOffset.</summary>
function EndPosition(const AContext: TRuleContext; AEndOffset: Integer; out APosition: TTextPosition): Boolean;
var
  Token: TPascalToken;
begin
  Result := False;
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Offset >= AEndOffset then
      Break;
    if Token.Offset + Length(Token.Text) = AEndOffset then
    begin
      APosition := Token.EndPos;
      Result := True;
    end;
  end;
end;

/// <summary>Korrektur, die " ADirective;" hinter den Methodenkopf setzt.</summary>
function AppendDirective(const AContext: TRuleContext; const AMethod: TMethodDecl; const ADirective: string;
  out AFix: TRuleFix): Boolean;
var
  Position: TTextPosition;
begin
  Result := EndPosition(AContext, AMethod.Header.EndOffset, Position);
  if Result then
    AFix := TRuleFix.Create(Format('"%s" ergänzen', [ADirective]),
      [TRuleEdit.Create(TTextRange.Create(Position, Position), ' ' + ADirective + ';')]);
end;

/// <summary>Erweitert [AStart, AEnd) (Offsets ab 0) auf ganze Zeilen samt Zeilenumbruch, wenn davor und dahinter
/// auf der Zeile nur Leerraum steht; sonst False. ADocComments: darüberstehende ///-Zeilen gehören dazu.
/// ABlankAfter: Steht über dem Bereich eine Leerzeile, fällt auch eine Leerzeile dahinter weg.</summary>
function WholeLines(const AText: string; AStart, AEnd: Integer; ADocComments, ABlankAfter: Boolean;
  out ALineStart, ALineEnd: Integer): Boolean;

  /// <summary>Anfang der Zeile vor der Zeile, die bei AOffset beginnt; AContent ist ihr Text.</summary>
  function PreviousLine(AOffset: Integer; out AContent: string): Integer;
  var
    mEnd: Integer;
  begin
    mEnd := AOffset - 1;
    if (mEnd > 0) and (AText[mEnd] = #13) then
      Dec(mEnd);
    Result := mEnd;
    while (Result > 0) and not CharInSet(AText[Result], [#10, #13]) do
      Dec(Result);
    AContent := Copy(AText, Result + 1, mEnd - Result);
  end;

  /// <summary>Ende der Zeile, die bei AOffset beginnt, samt Zeilenumbruch; AContent ist ihr Text.</summary>
  function LineEndFrom(AOffset: Integer; out AContent: string): Integer;
  begin
    Result := AOffset;
    while (Result < Length(AText)) and not CharInSet(AText[Result + 1], [#10, #13]) do
      Inc(Result);
    AContent := Copy(AText, AOffset + 1, Result - AOffset);
    if (Result < Length(AText)) and (AText[Result + 1] = #13) then
      Inc(Result);
    if (Result < Length(AText)) and (AText[Result + 1] = #10) then
      Inc(Result);
  end;

var
  mStart, mEnd, mPrevious, mNext: Integer;
  mContent, mAfter: string;
begin
  Result := False;
  mStart := AStart;
  while (mStart > 0) and CharInSet(AText[mStart], [' ', #9]) do
    Dec(mStart);
  if (mStart > 0) and not CharInSet(AText[mStart], [#10, #13]) then
    Exit;
  mEnd := AEnd;
  while (mEnd < Length(AText)) and CharInSet(AText[mEnd + 1], [' ', #9]) do
    Inc(mEnd);
  if (mEnd < Length(AText)) and not CharInSet(AText[mEnd + 1], [#10, #13]) then
    Exit;
  mEnd := LineEndFrom(mEnd, mContent);
  while ADocComments and (mStart > 0) do
  begin
    mPrevious := PreviousLine(mStart, mContent);
    if not StartsStr('///', TrimLeft(mContent)) then
      Break;
    mStart := mPrevious;
  end;
  // Die Leerzeile hinter dem Rumpf trennte ihn vom Nächsten; sie geht mit.
  if ABlankAfter and (mEnd < Length(AText)) then
  begin
    mNext := LineEndFrom(mEnd, mAfter);
    if Trim(mAfter) = '' then
      mEnd := mNext;
  end;
  ALineStart := mStart;
  ALineEnd := mEnd;
  Result := True;
end;

/// <summary>Korrektur, die die Anweisung AStatement samt Semikolon entfernt, allein auf der Zeile die ganze Zeile.
/// </summary>
function RemoveStatementFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; AStatement: TSyntaxNode;
  const ATitle: string): TRuleFix;
var
  mText: string;
  mStart, mEnd, mLineStart, mLineEnd: Integer;
begin
  mText := AContext.Text;
  mStart := AStatement.StartOffset;
  mEnd := AStatement.EndOffset;
  while (mEnd < Length(mText)) and CharInSet(mText[mEnd + 1], [' ', #9]) do
    Inc(mEnd);
  if (mEnd < Length(mText)) and (mText[mEnd + 1] = ';') then
    Inc(mEnd)
  else
    mEnd := AStatement.EndOffset;
  if WholeLines(mText, mStart, mEnd, False, False, mLineStart, mLineEnd) then
  begin
    mStart := mLineStart;
    mEnd := mLineEnd;
  end;
  Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mStart, mEnd),
    '')]);
end;

/// <summary>Methodendeklarationen aller Klassen der Datei.</summary>
function ClassMethods(const AContext: TRuleContext; AAncestry: TAncestry): TArray<TMethodDecl>;
const
  // Nur hier stehen Klassendeklarationen. Anweisungen und Ausdrücke bleiben außen vor: Ihre Bäume
  // können sehr tief sein (lange Verkettungen in erzeugten Units), und jede Ebene kostete Stapel.
  Containers = [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.PackageFile,
    TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl,
    TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.HelperType,
    TSyntaxKind.RoutineDecl];
var
  Methods: TList<TMethodDecl>;

  // Eigene Routine für die großen Records (TIndexSymbol, TMethodDecl, TPascalToken): Sie liegen nur
  // einmal auf dem Stapel, nicht in jeder Ebene von Visit.
  procedure AddMethods(ATypeDecl: TSyntaxNode);
  var
    Index, Inner: Integer;
    Body, Header: TSyntaxNode;
    Method: TMethodDecl;
    Token: TPascalToken;
    Symbol: TIndexSymbol;
  begin
    Body := ATypeDecl.FindChild(TSyntaxKind.ClassType);
    if Body = nil then
      Exit;
    for Index := 0 to Body.ChildCount - 1 do
    begin
      Header := Body[Index];
      if Header.Kind <> TSyntaxKind.RoutineHeader then
        Continue;
      Method := Default(TMethodDecl);
      Method.ClassName := ATypeDecl.Name;
      Method.Header := Header;
      if TokenAt(AContext, Header.StartOffset, Token) then
        Method.Keyword := LowerCase(Token.Text);
      for Inner := 0 to Header.ChildCount - 1 do
        if Header[Inner].Kind = TSyntaxKind.Directive then
          Method.Directives := Method.Directives + [LowerCase(Header[Inner].Name)];
      // class procedure/static: keine virtuellen Instanzmethoden.
      if (Method.Keyword = 'class') or Method.Has('static') or Method.Has('message') then
        Continue;
      for Symbol in AAncestry.Local.Symbols do
        if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
          SameText(Symbol.Container, ATypeDecl.Name) and (Symbol.Range.StartPos = Header.StartPos) then
        begin
          Method.Symbol := Symbol;
          Methods.Add(Method);
          Break;
        end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeDecl then
          AddMethods(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind in Containers then
            Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  Methods := TList<TMethodDecl>.Create;
  try
    Visit(AContext.Tree.Root);
    Result := Methods.ToArray;
  finally
    Methods.Free;
  end;
end;

function IsDestroy(const AMethod: TMethodDecl): Boolean;
begin
  Result := (AMethod.Keyword = 'destructor') and SameText(AMethod.Symbol.Name, 'Destroy') and
    (AMethod.Symbol.MaxArgs = 0);
end;

function IsComponentCreate(const AMethod: TMethodDecl): Boolean;
begin
  Result := (AMethod.Keyword = 'constructor') and SameText(AMethod.Symbol.Name, 'Create') and
    (Length(AMethod.Symbol.ParamTypes) = 1) and SameText(BareName(AMethod.Symbol.ParamTypes[0]), 'TComponent');
end;

/// <summary>Wird das Verdecken bereits bewusst angezeigt oder gelöst?</summary>
function Settled(const AMethod: TMethodDecl): Boolean;
begin
  Result := AMethod.Has('override') or AMethod.Has('reintroduce');
end;

/// <summary>Methoden der Datei ohne override/reintroduce; False ohne Syntaxbaum.
/// AAncestry gehört dem Aufrufer.</summary>
function Prepare(const AContext: TRuleContext; out AAncestry: TAncestry; out AMethods: TArray<TMethodDecl>): Boolean;
var
  Method: TMethodDecl;
  Cache: IRuleDerivedCache;
begin
  AAncestry := nil;
  AMethods := nil;
  if AContext.Tree = nil then
    Exit(False);
  // Den Index der Datei teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  AAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  for Method in ClassMethods(AContext, AAncestry) do
    if not Settled(Method) then
      AMethods := AMethods + [Method];
  Result := True;
end;

{ TDestroyWithoutOverrideRule }

function TDestroyWithoutOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('destroy-without-override', TRuleSeverity.Warning,
    'destructor Destroy ohne override');
end;

procedure TDestroyWithoutOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = 'Destroy ohne override: Free ruft diesen Destruktor nicht auf';
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Fix: TRuleFix;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      // Mit virtual meldet virtual-instead-of-override.
      if not IsDestroy(Method) or Method.Has('virtual') or Method.Has('dynamic') then
        Continue;
      if AppendDirective(AContext, Method, 'override', Fix) then
        AReport.Add(Method.Symbol.SelectionRange, Message, [Fix])
      else
        AReport.Add(Method.Symbol.SelectionRange, Message);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TComponentCreateWithoutOverrideRule }

function TComponentCreateWithoutOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-create-without-override', TRuleSeverity.Warning,
    'constructor Create(AOwner: TComponent) ohne override in einer Komponente');
end;

procedure TComponentCreateWithoutOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  Message = 'Create(AOwner: TComponent) ohne override: beim Laden aus der DFM wird dieser Konstruktor ' +
    'nicht aufgerufen';
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Fix: TRuleFix;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      if not IsComponentCreate(Method) or Method.Has('virtual') or Method.Has('dynamic') or
        not Ancestry.DescendsFrom(Method.ClassName, 'TComponent') then
        Continue;
      if AppendDirective(AContext, Method, 'override', Fix) then
        AReport.Add(Method.Symbol.SelectionRange, Message, [Fix])
      else
        AReport.Add(Method.Symbol.SelectionRange, Message);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ THidesVirtualRule }

function THidesVirtualRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('hides-virtual', TRuleSeverity.Warning,
    'Methode verdeckt eine virtuelle Methode des Vorfahren');
end;

procedure THidesVirtualRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Found: TInherited;
  Fixes: TArray<TRuleFix>;
  Fix: TRuleFix;
  Confidence: TRuleConfidence;
  IsVirtual: Boolean;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      // Destroy und Create(TComponent) haben eigene Regeln.
      if IsDestroy(Method) or IsComponentCreate(Method) then
        Continue;
      Found := Ancestry.InheritedVirtual(Method);
      if not Found.Found then
        Continue;
      IsVirtual := Method.Has('virtual') or Method.Has('dynamic');
      // virtual bei gleicher Signatur prüft virtual-instead-of-override; eine Überladung
      // mit anderer Signatur verdeckt nichts.
      if (IsVirtual and Found.SameSignature) or (Method.Has('overload') and not Found.SameSignature) then
        Continue;
      Fixes := nil;
      if Found.SameSignature and AppendDirective(AContext, Method, 'override', Fix) then
      begin
        Fix.Alternative := True;
        Fixes := Fixes + [Fix];
      end;
      if AppendDirective(AContext, Method, 'reintroduce', Fix) then
      begin
        Fix.Alternative := True;
        Fixes := Fixes + [Fix];
      end;
      if Found.SameSignature then
        Confidence := TRuleConfidence.High
      else
        Confidence := TRuleConfidence.Medium;
      AReport.Add(Method.Symbol.SelectionRange, Format('"%s" verdeckt die virtuelle Methode %s.%s; override ' +
        'oder reintroduce angeben', [Method.Symbol.Name, Found.TypeName, Found.Symbol.Name]), Confidence, Fixes);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TVirtualInsteadOfOverrideRule }

function TVirtualInsteadOfOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('virtual-instead-of-override', TRuleSeverity.Warning,
    'virtual im Nachfahren statt override');
end;

/// <summary>Token der Direktive virtual bzw. dynamic im Kopf.</summary>
function VirtualToken(const AContext: TRuleContext; const AMethod: TMethodDecl; out AToken: TPascalToken): Boolean;
var
  Index: Integer;
  Directive: TSyntaxNode;
begin
  for Index := 0 to AMethod.Header.ChildCount - 1 do
  begin
    Directive := AMethod.Header[Index];
    if (Directive.Kind = TSyntaxKind.Directive) and MatchText(Directive.Name, ['virtual', 'dynamic']) and
      TokenAt(AContext, Directive.StartOffset, AToken) then
      Exit(True);
  end;
  Result := False;
end;

procedure TVirtualInsteadOfOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Methods: TArray<TMethodDecl>;
  Method: TMethodDecl;
  Found: TInherited;
  Token: TPascalToken;
  Message: string;
begin
  if not Prepare(AContext, Ancestry, Methods) then
    Exit;
  try
    for Method in Methods do
    begin
      if not Method.Has('virtual') and not Method.Has('dynamic') then
        Continue;
      // TObject.Destroy ist immer virtuell, auch wenn TObject nicht im Index steht.
      if not IsDestroy(Method) then
      begin
        Found := Ancestry.InheritedVirtual(Method);
        if not Found.Found or not Found.SameSignature then
          Continue;
      end;
      Message := Format('"%s" ist im Vorfahren schon virtuell; override statt %s verwenden',
        [Method.Symbol.Name, IfThen(Method.Has('virtual'), 'virtual', 'dynamic')]);
      if VirtualToken(AContext, Method, Token) then
        AReport.Add(Method.Symbol.SelectionRange, Message, [TRuleFix.Create(Format('%s durch override ersetzen',
          [Token.Text]), [TRuleEdit.Create(TTextRange.Create(Token.StartPos, Token.EndPos), 'override')])])
      else
        AReport.Add(Method.Symbol.SelectionRange, Message);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TShadowedNameRule }

const
  ShadowDefaultIgnore: array[0..1] of string = ('Sender', 'Value');
  // Ohne VCL im Index: Mitglieder von TComponent bzw. TControl, wenn die Kette an einer dieser Klassen abbricht.
  ComponentClasses: array[0..1] of string = ('TComponent', 'TDataModule');
  ComponentMembers: array[0..5] of string = ('Name', 'Tag', 'Owner', 'ComponentCount', 'ComponentIndex',
    'Components');
  ControlClasses: array[0..14] of string = ('TControl', 'TWinControl', 'TCustomControl', 'TGraphicControl', 'TForm',
    'TCustomForm', 'TFrame', 'TCustomFrame', 'TScrollingWinControl', 'TPanel', 'TCustomPanel', 'TScrollBox',
    'TPageControl', 'TTabSheet', 'TGroupBox');
  ControlMembers: array[0..20] of string = ('Left', 'Top', 'Width', 'Height', 'Caption', 'Text', 'Hint', 'Visible',
    'Enabled', 'Color', 'Font', 'Parent', 'Align', 'Anchors', 'Cursor', 'ShowHint', 'PopupMenu', 'ClientWidth',
    'ClientHeight', 'Action', 'Constraints');

function TAncestry.FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol;
  out AUnresolved: string): Boolean;
var
  mUnitName: string;
begin
  Result := FindMember(ATypeName, AName, AMember, AUnresolved, mUnitName);
end;

function TAncestry.FindMember(const ATypeName, AName: string; out AMember: TIndexSymbol; out AUnresolved,
  AUnitName: string): Boolean;
var
  Name: string;
  Location: TSymbolLocation;
  Symbols: TArray<TIndexSymbol>;
  Symbol: TIndexSymbol;
  UnitIndex: TUnitIndex;
  Depth: Integer;
  Visible: Boolean;
begin
  AMember := Default(TIndexSymbol);
  AUnresolved := '';
  AUnitName := '';
  Name := ATypeName;
  Depth := 0;
  while (Name <> '') and (Depth < 64) do
  begin
    if not FindType(Name, Location) then
    begin
      AUnresolved := Name;
      Exit(False);
    end;
    if Location.FileName = '' then
      Symbols := FLocal.Symbols
    else if (FIndex <> nil) and FIndex.FindFile(Location.FileName, UnitIndex) then
      Symbols := UnitIndex.Symbols
    else
      Symbols := nil;
    for Symbol in Symbols do
      if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
        SameText(Symbol.Container, Location.Symbol.Name) and SameText(Symbol.Name, AName) and
        ContainsLine(Location.Symbol.Range, Symbol.Range.StartPos.Line) then
      begin
        // private ist nur in derselben Unit sichtbar, strict private nur in der Klasse selbst.
        Visible := (Depth = 0) or ((Location.FileName = '') and (Symbol.Visibility <> TIndexVisibility.StrictPrivate)) or
          not (Symbol.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate]);
        if Visible then
        begin
          AMember := Symbol;
          if Location.FileName <> '' then
            AUnitName := Location.UnitName;
          Exit(True);
        end;
      end;
    if Length(Location.Symbol.Ancestors) = 0 then
      Break;
    Name := BareName(Location.Symbol.Ancestors[0]);
    Inc(Depth);
  end;
  Result := False;
end;

function TShadowedNameRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('shadowed-name', TRuleSeverity.Hint,
    'Lokaler Name verdeckt Feld, Property oder globale Variable');
end;

procedure TShadowedNameRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Ancestry: TAncestry;
  Ignore: TArray<string>;
  Tokens: TArray<TPascalToken>;
  FrameworkMembers: Boolean;

  function SplitNames(const ANames: string): TArray<string>;
  var
    Name: string;
  begin
    Result := nil;
    for Name in SplitString(ANames, ',') do
      if Trim(Name) <> '' then
        Result := Result + [Trim(Name)];
  end;

  // Bezeichner-Token AName in ANode, die nicht hinter einem Punkt stehen (Self.Caption bleibt).
  function NameTokens(ANode: TSyntaxNode; const AName: string): TArray<Integer>;
  var
    Index, Previous: Integer;
  begin
    Result := nil;
    for Index := TSyntaxTree.FirstTokenOf(Tokens, ANode.StartOffset) to High(Tokens) do
    begin
      if Tokens[Index].Offset >= ANode.EndOffset then
        Break;
      if (Tokens[Index].Offset < ANode.StartOffset) or
        not (Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) or
        not SameText(Tokens[Index].Text, AName) then
        Continue;
      Previous := Index - 1;
      while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Dec(Previous);
      if (Previous >= 0) and Tokens[Previous].IsSymbol('.') then
        Continue;
      Result := Result + [Index];
    end;
  end;

  function TokenRange(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AIndex].StartPos, Tokens[AIndex].EndPos);
  end;

  function Assigned_(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          (Node[0].Kind = TSyntaxKind.Identifier) and SameText(Node[0].Name, AName) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Deklaration der Methode in der Klasse: Kopf mit gleichem Namen und demselben Parameter an derselben Stelle.
  function DeclarationHeader(const AClassName, AMethod, AParam: string; AParamIndex: Integer): TSyntaxNode;

    function Search(ARoot: TSyntaxNode): TSyntaxNode;
    var
      Index, Position: Integer;
      Node, Params: TSyntaxNode;
      Name: string;
      InClass: Boolean;
      Pending: TStack<TSyntaxNode>;
      PendingInClass: TStack<Boolean>;
    begin
      // Iterativ (Bericht M1): zu jedem Knoten auf dem Stapel, ob er in der Klasse AClassName liegt.
      Result := nil;
      Pending := TStack<TSyntaxNode>.Create;
      PendingInClass := TStack<Boolean>.Create;
      try
        Pending.Push(ARoot);
        PendingInClass.Push(False);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          InClass := PendingInClass.Pop;
          if Node.Kind = TSyntaxKind.TypeDecl then
            InClass := SameText(Node.Name, AClassName);
          if InClass and (Node.Kind = TSyntaxKind.RoutineHeader) and SameText(Node.Name, AMethod) then
          begin
            Params := Node.FindChild(TSyntaxKind.Parameters);
            Position := 0;
            if Params <> nil then
              for Index := 0 to Params.ChildCount - 1 do
                if Params[Index].Kind = TSyntaxKind.Parameter then
                  for Name in SplitNames(Params[Index].Name) do
                  begin
                    if (Position = AParamIndex) and SameText(Name, AParam) then
                      Exit(Node);
                    Inc(Position);
                  end;
            Continue;
          end;
          if Node.Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.RoutineDecl] then
            Continue;
          for Index := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Index]);
            PendingInClass.Push(InClass);
          end;
        end;
      finally
        PendingInClass.Free;
        Pending.Free;
      end;
    end;

  begin
    Result := Search(AContext.Tree.Root);
  end;

  // Globale Variable der Unit vor ARoutine.
  function GlobalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    Symbol: TIndexSymbol;
  begin
    for Symbol in Ancestry.Local.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Variable) and (Symbol.Container = '') and SameText(Symbol.Name, AName) and
        (Symbol.Range.StartPos.Line < ARoutine.StartPos.Line) then
        Exit(True);
    Result := False;
  end;

  // Nächstes bzw. voriges Token ohne Kommentare und Direktiven; -1 ohne.
  function Significant(AIndex, AStep: Integer): Integer;
  begin
    Result := AIndex + AStep;
    while (Result >= 0) and (Result <= High(Tokens)) and
      (Tokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Inc(Result, AStep);
    if (Result < 0) or (Result > High(Tokens)) then
      Result := -1;
  end;

  // Verwendung von AName in ARoutine außerhalb der Deklaration ADeclaration: AWrites zählt Zuweisungen
  // (X := …, auch die Vorbelegung einer Inline-Variable), AReads reine Lesezugriffe, AUnclear alles, was beides
  // sein kann (Argument eines Aufrufs, @X, X.Feld, X[I]).
  procedure Usage(ARoutine, ADeclaration: TSyntaxNode; const AName: string; out AReads, AWrites,
    AUnclear: Integer);
  var
    mIndex, mNext, mPrevious: Integer;
  begin
    AReads := 0;
    AWrites := 0;
    AUnclear := 0;
    if ADeclaration.Kind = TSyntaxKind.InlineVar then
      for mIndex := TSyntaxTree.FirstTokenOf(Tokens, ADeclaration.StartOffset) to High(Tokens) do
      begin
        if Tokens[mIndex].Offset >= ADeclaration.EndOffset then
          Break;
        if Tokens[mIndex].IsSymbol(':=') then
        begin
          Inc(AWrites);
          Break;
        end;
      end;
    for mIndex in NameTokens(ARoutine, AName) do
    begin
      if (Tokens[mIndex].Offset >= ADeclaration.StartOffset) and (Tokens[mIndex].Offset < ADeclaration.EndOffset) then
        Continue;
      mNext := Significant(mIndex, 1);
      mPrevious := Significant(mIndex, -1);
      if (mNext >= 0) and Tokens[mNext].IsSymbol(':=') then
        Inc(AWrites)
      else if ((mNext >= 0) and (Tokens[mNext].IsSymbol('.') or Tokens[mNext].IsSymbol('[') or
        Tokens[mNext].IsSymbol('^'))) or ((mPrevious >= 0) and (Tokens[mPrevious].IsSymbol('(') or
        Tokens[mPrevious].IsSymbol(',') or Tokens[mPrevious].IsSymbol('@'))) then
        Inc(AUnclear)
      else
        Inc(AReads);
    end;
  end;

  function HasDirective(AHeader: TSyntaxNode; const ANames: array of string): Boolean;
  var
    mIndex: Integer;
  begin
    if AHeader <> nil then
      for mIndex := 0 to AHeader.ChildCount - 1 do
        if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and MatchText(AHeader[mIndex].Name, ANames) then
          Exit(True);
    Result := False;
  end;

  // class procedure/function: Felder und Properties der Instanz sind dort nicht erreichbar.
  function IsClassMethod(ARoutine: TSyntaxNode): Boolean;
  var
    mHeader: TSyntaxNode;
    mIndex: Integer;
  begin
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Result := False;
    if mHeader <> nil then
    begin
      mIndex := TSyntaxTree.FirstTokenOf(Tokens, mHeader.StartOffset);
      Result := (mIndex >= 0) and (mIndex <= High(Tokens)) and Tokens[mIndex].IsKeyword('class');
    end;
  end;

  procedure CheckName(ARoutine: TSyntaxNode; const AClassName, AName: string; AIsParameter: Boolean;
    ADeclaration: TSyntaxNode; AParamIndex: Integer);
  var
    Member: TIndexSymbol;
    Unresolved, What, Kind, NewName, Message, Pattern: string;
    Found: Boolean;
    Header: TSyntaxNode;
    Positions: TArray<Integer>;
    Index: Integer;
    Edits: TArray<TRuleEdit>;
    Fixes: TArray<TRuleFix>;
    mUnitName, mSuffix: string;
    mFramework, mClassMethod: Boolean;
    mReads, mWrites, mUnclear: Integer;
  begin
    for Pattern in Ignore do
      if MatchesWildcard(AName, Pattern) then
        Exit;
    Found := False;
    mFramework := False;
    Kind := '';
    if AClassName <> '' then
    begin
      mClassMethod := IsClassMethod(ARoutine);
      Found := Ancestry.FindMember(AClassName, AName, Member, Unresolved, mUnitName);
      if Found and mClassMethod and not MatchText('class', Member.Directives) then
        // In class-Methoden zählen nur class var und class property.
        Found := False
      else if Found then
      begin
        mFramework := (mUnitName <> '') and TLibraryUnits.IsLibrary(AContext.Index, mUnitName);
        if Member.Kind = TIndexSymbolKind.Field then
          Kind := 'das Feld ' + AClassName + '.' + Member.Name
        else
          Kind := 'die Property ' + AClassName + '.' + Member.Name;
      end
      // Die Mitglieder von TComponent und TControl gehören alle zur Instanz.
      else if not mClassMethod and (MatchText(Unresolved, ComponentClasses) or
        MatchText(Unresolved, ControlClasses)) and MatchText(AName, ComponentMembers) then
      begin
        Found := True;
        mFramework := True;
        Kind := 'die Property ' + AClassName + '.' + AName;
      end
      else if not mClassMethod and MatchText(Unresolved, ControlClasses) and MatchText(AName, ControlMembers) then
      begin
        Found := True;
        mFramework := True;
        Kind := 'die Property ' + AClassName + '.' + AName;
      end;
    end;
    if not Found and GlobalVariable(ARoutine, AName) then
    begin
      Found := True;
      mFramework := False;
      Kind := 'die globale Variable ' + AName;
    end;
    if not Found then
      Exit;
    Header := nil;
    if AIsParameter and (AClassName <> '') then
      Header := DeclarationHeader(AClassName, Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt),
        AName, AParamIndex);
    // override und message: Die Signatur gibt der Vorfahr bzw. die Botschaft vor, z. B.
    // DoClose(var Action: TCloseAction).
    if AIsParameter and (HasDirective(Header, ['override', 'message']) or
      HasDirective(ARoutine.FindChild(TSyntaxKind.RoutineHeader), ['override', 'message'])) then
      Exit;
    if AIsParameter then
      What := 'Parameter'
    else
      What := 'Lokale Variable';
    Message := Format('%s %s verdeckt %s', [What, AName, Kind]);
    mSuffix := '';
    // Geerbt aus RTL, VCL oder einer anderen Bibliothek: Left, Text oder Name als Hilfsvariable sind
    // dort üblich. Gemeldet wird nur, wo das Mitglied gemeint sein könnte: eine lokale Variable, die nur
    // zugewiesen oder nur gelesen wird, ein Werteparameter, dem etwas zugewiesen wird.
    if mFramework and not FrameworkMembers then
    begin
      Usage(ARoutine, ADeclaration, AName, mReads, mWrites, mUnclear);
      if AIsParameter then
      begin
        if (ADeclaration.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) or
          (mWrites = 0) then
          Exit;
      end
      else if mUnclear > 0 then
        Exit
      else if (mReads > 0) and (mWrites = 0) then
        mSuffix := '; gelesen wird die lokale Variable, der nichts zugewiesen wird.'
      else if (mReads > 0) or (mWrites = 0) then
        Exit;
    end;
    if mSuffix <> '' then
      Message := Message + mSuffix
    else if Assigned_(ARoutine, AName) then
    begin
      if AIsParameter then
        Message := Message + '; die Zuweisung ändert nur den Parameter.'
      else
        Message := Message + '; die Zuweisung ändert nur die lokale Variable.';
    end
    else
      Message := Message + '.';
    // Umbenennen: AName für Parameter, LName für lokale Variablen, mit den Präfixen der Projektdatei .atlas
    // (#1111, z. B. mName); alle Vorkommen in der Routine.
    if AIsParameter then
      NewName := TNamingConvention.Expected(AName, NamingPrefixFor(AContext, TRuleNamingKind.Parameter, 'A'))
    else
      NewName := TNamingConvention.Expected(AName, NamingPrefixFor(AContext, TRuleNamingKind.Local, 'L'));
    Fixes := nil;
    Positions := NameTokens(ARoutine, AName);
    if (NameTokens(ARoutine, NewName) = nil) and ((Header = nil) or (NameTokens(Header, NewName) = nil)) then
    begin
      Edits := nil;
      for Index in Positions do
        Edits := Edits + [TRuleEdit.Create(TokenRange(Index), NewName)];
      if Header <> nil then
        for Index in NameTokens(Header, AName) do
          Edits := Edits + [TRuleEdit.Create(TokenRange(Index), NewName)];
      Fixes := [TRuleFix.Create(Format('In %s umbenennen', [NewName]), Edits)];
    end;
    for Index in NameTokens(ADeclaration, AName) do
    begin
      AReport.Add(TokenRange(Index), Message, TRuleConfidence.High, Fixes);
      Exit;
    end;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode; const AClassName: string);
  var
    Header, Params, Child: TSyntaxNode;
    Index, Inner, Position: Integer;
    Name, ClassName: string;
    HasSender: Boolean;

    procedure CheckInline(ARoot: TSyntaxNode);
    var
      Item: Integer;
      InlineName: string;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if Node.Kind = TSyntaxKind.InlineVar then
            for InlineName in SplitNames(Node.Name) do
              CheckName(ARoutine, ClassName, InlineName, False, Node, -1);
          if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
            Continue;
          for Item := Node.ChildCount - 1 downto 0 do
            Pending.Push(Node[Item]);
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    ClassName := AClassName;
    if (ClassName = '') and (Pos('.', ARoutine.Name) > 0) then
    begin
      ClassName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
      ClassName := Copy(ClassName, LastDelimiter('.', ClassName) + 1, MaxInt);
    end;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Params := nil;
    if Header <> nil then
      Params := Header.FindChild(TSyntaxKind.Parameters);
    // Ereignis-Handler (mit Sender): die Signatur gibt der Ereignistyp vor, z. B. FormClose(…; var Action).
    HasSender := False;
    if Params <> nil then
      for Index := 0 to Params.ChildCount - 1 do
        if Params[Index].Kind = TSyntaxKind.Parameter then
          for Name in SplitNames(Params[Index].Name) do
            HasSender := HasSender or SameText(Name, 'Sender');
    if (Params <> nil) and not HasSender then
    begin
      Position := 0;
      for Index := 0 to Params.ChildCount - 1 do
        if Params[Index].Kind = TSyntaxKind.Parameter then
          for Name in SplitNames(Params[Index].Name) do
          begin
            CheckName(ARoutine, ClassName, Name, True, Params[Index], Position);
            Inc(Position);
          end;
    end;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Child := ARoutine[Index];
      if Child.Kind = TSyntaxKind.VarSection then
      begin
        for Inner := 0 to Child.ChildCount - 1 do
          if Child[Inner].Kind = TSyntaxKind.VarDecl then
            for Name in SplitNames(Child[Inner].Name) do
              CheckName(ARoutine, ClassName, Name, False, Child[Inner], -1);
      end
      else if Child.Kind = TSyntaxKind.Block then
        CheckInline(Child)
      else if Child.Kind = TSyntaxKind.RoutineDecl then
        // Die Rekursion bleibt (Bericht M1): sie geht nur über verschachtelte Routinendeklarationen.
        CheckRoutine(Child, ClassName);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          CheckRoutine(Node, '');
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Cache: IRuleDerivedCache;
  Defaults: TArray<string>;
  Name: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Defaults := nil;
  for Name in ShadowDefaultIgnore do
    Defaults := Defaults + [Name];
  Ignore := TRuleOptions.Strings(AContext.Options, 'ignore', Defaults);
  FrameworkMembers := TRuleOptions.Bool(AContext.Options, 'frameworkMembers', False);
  Tokens := AContext.Tree.Tokens;
  Cache := TRuleDerived.Open(AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

{ TOverrideTargetMissingRule }

type
  /// <summary>Gleichnamige Methode eines Vorfahren für override-target-missing (#997).</summary>
  TOverrideCandidate = record
    TypeName: string;
    Symbol: TIndexSymbol;
    /// <summary>procedure, function, constructor oder destructor aus der Signatur.</summary>
    Keyword: string;
    /// <summary>Kopf ab dem Namen ohne Direktiven, z. B. "Ausfuehren(const Modus: TModus)".</summary>
    Head: string;
  end;

  /// <summary>Vergleich zweier Köpfe: gleich, nur Typen anders, anders gebaut.</summary>
  TOverrideMatch = (Same, OtherTypes, Different);

/// <summary>Schlüsselwort und Kopf ab dem Namen aus einer Signatur wie "procedure Foo(A: Integer); virtual;".
/// </summary>
function SplitSignature(const ASignature: string; out AKeyword, AHead: string): Boolean;
var
  Text: string;
  Index, Depth: Integer;
begin
  Text := Trim(ASignature);
  AKeyword := LowerCase(Copy(Text, 1, Pos(' ', Text + ' ') - 1));
  AHead := '';
  Result := MatchText(AKeyword, ['procedure', 'function', 'constructor', 'destructor']);
  if not Result then
    Exit;
  Text := Trim(Copy(Text, Length(AKeyword) + 1, MaxInt));
  Depth := 0;
  for Index := 1 to Length(Text) do
    case Text[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ';':
        if Depth = 0 then
        begin
          AHead := Trim(Copy(Text, 1, Index - 1));
          Exit;
        end;
    end;
  AHead := Text;
end;

/// <summary>Kopf ohne Standardwerte der Parameter, für den Rumpf.</summary>
function WithoutDefaults(const AHead: string): string;
var
  Index, Depth: Integer;
  Skipping: Boolean;
  Quoted: Boolean;
begin
  Result := '';
  Depth := 0;
  Skipping := False;
  Quoted := False;
  for Index := 1 to Length(AHead) do
  begin
    if AHead[Index] = '''' then
      Quoted := not Quoted;
    if not Quoted then
      case AHead[Index] of
        '(', '[':
          Inc(Depth);
        ')', ']':
          begin
            Dec(Depth);
            if Depth = 0 then
              Skipping := False;
          end;
        ';':
          if Depth = 1 then
            Skipping := False;
        '=':
          if Depth = 1 then
            Skipping := True;
      end;
    if not Skipping then
      Result := Result + AHead[Index];
  end;
  Result := StringReplace(Result, ' ;', ';', [rfReplaceAll]);
  Result := StringReplace(Result, ' )', ')', [rfReplaceAll]);
end;

function TOverrideTargetMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('override-target-missing', TRuleSeverity.Error,
    'override ohne passende virtuelle Methode im Vorfahren');
end;

procedure TOverrideTargetMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;

  function Wildcards(const AClassName: string; const AChain: TArray<TSymbolLocation>): TArray<string>;
  var
    Location: TSymbolLocation;
    Symbol: TIndexSymbol;
    Name: string;
  begin
    Result := nil;
    for Location in AChain do
      for Name in SplitString(Location.Symbol.TypeParams, ',') do
        if Trim(Name) <> '' then
          Result := Result + [Trim(Name)];
    for Symbol in Ancestry.Local.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) then
        for Name in SplitString(Symbol.TypeParams, ',') do
          if Trim(Name) <> '' then
            Result := Result + [Trim(Name)];
  end;

  /// <summary>Wie Compare; ACertain: alle abweichenden Typen stehen sicher für sich.</summary>
  function CompareTypes(const AMethod: TMethodDecl; const ACandidate: TOverrideCandidate;
    const AWildcards: TArray<string>; out ACertain: Boolean): TOverrideMatch;
  var
    Index: Integer;

    procedure Differ(const A, B: string);
    begin
      Result := TOverrideMatch.OtherTypes;
      ACertain := ACertain and Ancestry.KnownType(A) and Ancestry.KnownType(B);
    end;

  begin
    ACertain := True;
    if (ACandidate.Keyword <> AMethod.Keyword) or (AMethod.Symbol.MaxArgs <> ACandidate.Symbol.MaxArgs) or
      (Length(AMethod.Symbol.ParamTypes) <> Length(ACandidate.Symbol.ParamTypes)) or
      ((AMethod.Symbol.TypeName = '') <> (ACandidate.Symbol.TypeName = '')) then
      Exit(TOverrideMatch.Different);
    Result := TOverrideMatch.Same;
    for Index := 0 to High(AMethod.Symbol.ParamTypes) do
      if (AMethod.Symbol.ParamTypes[Index] = '') <> (ACandidate.Symbol.ParamTypes[Index] = '') then
        Exit(TOverrideMatch.Different)
      else if not Ancestry.SameType(AMethod.Symbol.ParamTypes[Index], ACandidate.Symbol.ParamTypes[Index],
        AWildcards) then
        Differ(AMethod.Symbol.ParamTypes[Index], ACandidate.Symbol.ParamTypes[Index]);
    if not Ancestry.SameType(AMethod.Symbol.TypeName, ACandidate.Symbol.TypeName, AWildcards) then
      Differ(AMethod.Symbol.TypeName, ACandidate.Symbol.TypeName);
  end;

  function Compare(const AMethod: TMethodDecl; const ACandidate: TOverrideCandidate;
    const AWildcards: TArray<string>): TOverrideMatch;
  var
    Certain: Boolean;
  begin
    Result := CompareTypes(AMethod, ACandidate, AWildcards, Certain);
  end;

  /// <summary>Gleichnamige, im Nachfahren sichtbare Methoden der Vorfahren, der nächste zuerst.</summary>
  function Candidates(const AChain: TArray<TSymbolLocation>; const AName: string): TArray<TOverrideCandidate>;
  var
    Location: TSymbolLocation;
    Symbol: TIndexSymbol;
    Item: TOverrideCandidate;
  begin
    Result := nil;
    for Location in AChain do
      for Symbol in Ancestry.Methods(Location) do
      begin
        if (AName <> '') and not SameText(Symbol.Name, AName) then
          Continue;
        // strict private sieht kein Nachfahre, private nur einer in derselben Unit.
        if (Symbol.Visibility = TIndexVisibility.StrictPrivate) or ((Location.FileName <> '') and
          (Symbol.Visibility = TIndexVisibility.Private)) then
          Continue;
        if StartsText('class ', Symbol.Signature) then
          Continue;
        Item.TypeName := Location.Symbol.Name;
        Item.Symbol := Symbol;
        if not SplitSignature(Symbol.Signature, Item.Keyword, Item.Head) then
          Continue;
        Result := Result + [Item];
      end;
  end;

  /// <summary>Index des Tokens, das bei AOffset beginnt; -1 ohne.</summary>
  function TokenIndex(AOffset: Integer): Integer;
  begin
    // Binär statt ab Dateianfang (#1342).
    Result := TSyntaxTree.FirstTokenOf(Tokens, AOffset);
    if (Result > High(Tokens)) or (Tokens[Result].Offset <> AOffset) then
      Result := -1;
  end;

  /// <summary>Erstes ";" auf Klammertiefe 0 ab dem Token AFrom; -1 ohne.</summary>
  function HeadEnd(AFrom: Integer): Integer;
  var
    Index, Depth: Integer;
  begin
    Depth := 0;
    for Index := AFrom to High(Tokens) do
      if (Tokens[Index].Kind = TPascalTokenKind.Symbol) and ((Tokens[Index].Text = '(') or
        (Tokens[Index].Text = '[')) then
        Inc(Depth)
      else if (Tokens[Index].Kind = TPascalTokenKind.Symbol) and ((Tokens[Index].Text = ')') or
        (Tokens[Index].Text = ']')) then
        Dec(Depth)
      else if (Depth = 0) and (Tokens[Index].Kind = TPascalTokenKind.Symbol) and (Tokens[Index].Text = ';') then
        Exit(Index);
    Result := -1;
  end;

  /// <summary>Kopf des einzigen Rumpfs AClassName.AName: Index des Schlüsselworts; -1 ohne oder bei mehreren.
  /// </summary>
  function BodyStart(const AClassName, AName: string): Integer;
  var
    Index: Integer;
  begin
    Result := -1;
    for Index := 1 to High(Tokens) - 2 do
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AClassName) and
        (Tokens[Index + 1].Text = '.') and SameText(Tokens[Index + 2].Text, AName) and
        (Tokens[Index - 1].Kind = TPascalTokenKind.Keyword) and MatchText(Tokens[Index - 1].Text, ['procedure',
        'function', 'constructor', 'destructor']) then
      begin
        if Result >= 0 then
          Exit(-1);
        Result := Index - 1;
      end;
  end;

  /// <summary>Übernimmt Schlüsselwort und Kopf von ACandidate in Deklaration und, wenn eindeutig, Rumpf.</summary>
  function AdoptFix(const AMethod: TMethodDecl; const ACandidate: TOverrideCandidate; out AFix: TRuleFix): Boolean;
  var
    First, Last, Body, BodyLast: Integer;
    Edits: TArray<TRuleEdit>;
  begin
    AFix := Default(TRuleFix);
    First := TokenIndex(AMethod.Header.StartOffset);
    Result := First >= 0;
    if not Result then
      Exit;
    Last := HeadEnd(First);
    Result := Last > First;
    if not Result then
      Exit;
    Edits := [TRuleEdit.Create(TTextRange.Create(Tokens[First].StartPos, Tokens[Last].StartPos),
      ACandidate.Keyword + ' ' + ACandidate.Head)];
    Body := BodyStart(AMethod.ClassName, AMethod.Symbol.Name);
    if Body > Last then
    begin
      BodyLast := HeadEnd(Body);
      if BodyLast > Body then
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Tokens[Body].StartPos, Tokens[BodyLast].StartPos),
          ACandidate.Keyword + ' ' + AMethod.ClassName + '.' + WithoutDefaults(ACandidate.Head))];
    end;
    AFix := TRuleFix.Create(Format('Signatur von %s.%s übernehmen', [ACandidate.TypeName, ACandidate.Symbol.Name]),
      Edits);
  end;

  function OwnHead(const AMethod: TMethodDecl): string;
  var
    Types: TArray<string>;
    Index: Integer;
  begin
    SetLength(Types, Length(AMethod.Symbol.ParamTypes));
    for Index := 0 to High(Types) do
      Types[Index] := AMethod.Symbol.ParamTypes[Index];
    Result := AMethod.Symbol.Name + '(' + string.Join(', ', Types) + ')';
    if AMethod.Symbol.TypeName <> '' then
      Result := Result + ': ' + AMethod.Symbol.TypeName;
  end;

  procedure CheckMethod(const AMethod: TMethodDecl);
  var
    Own: TSymbolLocation;
    Chain: TArray<TSymbolLocation>;
    Complete, ObjectMissing, Generic: Boolean;
    Found, Virtuals: TArray<TOverrideCandidate>;
    Candidate, Best: TOverrideCandidate;
    Match, BestMatch: TOverrideMatch;
    Certain, BestCertain: Boolean;
    Names: TArray<string>;
    Typo: string;
    Fix: TRuleFix;
    Confidence: TRuleConfidence;
    Fixes: TArray<TRuleFix>;
    Any: Boolean;
  begin
    // Ab der Klasse, in deren Rumpf die Methode steht (#1326): THorseChannel<T> neben THorseChannel.
    if Ancestry.OwnerOf(AMethod.Symbol, Own) then
      Chain := Ancestry.Ancestors(Own, Complete, ObjectMissing)
    else
      Chain := Ancestry.Ancestors(AMethod.ClassName, Complete, ObjectMissing);
    Names := Wildcards(AMethod.ClassName, Chain);
    Found := Candidates(Chain, AMethod.Symbol.Name);
    // Die nächste virtuelle Methode mit gleichem Kopf ist das Ziel.
    for Candidate in Found do
      if Candidate.Symbol.IsVirtual and (Compare(AMethod, Candidate, Names) = TOverrideMatch.Same) then
      begin
        if Candidate.Symbol.HasDirective('final') then
          AReport.Add(AMethod.Symbol.SelectionRange, Format('%s.%s ist final und lässt sich nicht überschreiben ' +
            '(wie E2352).', [Candidate.TypeName, Candidate.Symbol.Name]), TRuleConfidence.High);
        Exit;
      end;
    if ObjectMissing and MatchText(AMethod.Symbol.Name, ObjectVirtualNames) then
      Exit;
    if not Complete then
      Exit;
    for Candidate in Found do
      if Compare(AMethod, Candidate, Names) = TOverrideMatch.Same then
      begin
        AReport.Add(AMethod.Symbol.SelectionRange, Format('%s.%s ist nicht virtuell; override braucht virtual ' +
          'oder dynamic im Vorfahren (wie E2170).', [Candidate.TypeName, Candidate.Symbol.Name]),
          TRuleConfidence.High);
        Exit;
      end;
    // Virtuelle Methode gleichen Namens mit anderem Kopf: die ähnlichste der nächsten Stufe.
    Any := False;
    Best := Default(TOverrideCandidate);
    BestMatch := TOverrideMatch.Different;
    BestCertain := True;
    for Candidate in Found do
      if Candidate.Symbol.IsVirtual then
      begin
        Match := CompareTypes(AMethod, Candidate, Names, Certain);
        if not Any or (Match < BestMatch) then
        begin
          Best := Candidate;
          BestMatch := Match;
          BestCertain := Certain;
          Any := True;
        end;
      end;
    Generic := Names <> nil;
    if Any then
    begin
      Confidence := TRuleConfidence.High;
      // Nur andere Typen: sicher nur, wenn keiner ein unbekannter Alias sein kann.
      if (BestMatch = TOverrideMatch.OtherTypes) and not BestCertain then
        Confidence := TRuleConfidence.Medium;
      Fixes := nil;
      if not Generic and AdoptFix(AMethod, Best, Fix) then
        Fixes := [Fix];
      AReport.Add(AMethod.Symbol.SelectionRange, Format('%s hat kein virtuelles %s; dort heißt es %s (wie E2137).',
        [Best.TypeName, OwnHead(AMethod), Best.Head]), Confidence, Fixes);
      Exit;
    end;
    // Kein gleichnamiger Kandidat: Tippfehler im Namen (Destory)?
    Virtuals := nil;
    Names := nil;
    for Candidate in Candidates(Chain, '') do
      if Candidate.Symbol.IsVirtual and (Candidate.Keyword = AMethod.Keyword) then
      begin
        Virtuals := Virtuals + [Candidate];
        Names := Names + [Candidate.Symbol.Name];
      end;
    if ObjectMissing then
      for Typo in ObjectVirtualNames do
        Names := Names + [Typo];
    Typo := TTextFuzzy.Closest(AMethod.Symbol.Name, Names);
    Fixes := nil;
    for Candidate in Virtuals do
      if (Typo <> '') and SameText(Candidate.Symbol.Name, Typo) and not Generic and (Fixes = nil) and
        AdoptFix(AMethod, Candidate, Fix) then
        Fixes := [Fix];
    if (Typo <> '') and (Fixes = nil) and SameText(Typo, 'Destroy') and (AMethod.Keyword = 'destructor') then
    begin
      Candidate := Default(TOverrideCandidate);
      Candidate.TypeName := 'TObject';
      Candidate.Symbol.Name := 'Destroy';
      Candidate.Keyword := 'destructor';
      Candidate.Head := 'Destroy';
      if AdoptFix(AMethod, Candidate, Fix) then
        Fixes := [Fix];
    end;
    if Typo <> '' then
      AReport.Add(AMethod.Symbol.SelectionRange, Format('Kein Vorfahr von %s hat ein virtuelles %s; gemeint ist ' +
        'wohl %s (wie E2137).', [AMethod.ClassName, AMethod.Symbol.Name, Typo]), TRuleConfidence.High, Fixes)
    else
      AReport.Add(AMethod.Symbol.SelectionRange, Format('Kein Vorfahr von %s hat ein virtuelles %s (wie E2137).',
        [AMethod.ClassName, AMethod.Symbol.Name]), TRuleConfidence.High);
  end;

  /// <summary>E2353: Vorfahr mit sealed in der Signatur ("TBasis = class sealed").</summary>
  procedure CheckSealed;
  var
    Symbol: TIndexSymbol;
    Chain: TArray<TSymbolLocation>;
    Complete, ObjectMissing: Boolean;
    Words: TArray<string>;
    Index: Integer;
  begin
    for Symbol in Ancestry.Local.Symbols do
    begin
      if (Symbol.Kind <> TIndexSymbolKind.ClassType) or (Symbol.Container <> '') or (Symbol.Ancestors = nil) then
        Continue;
      Chain := Ancestry.Ancestors(Symbol.Name, Complete, ObjectMissing);
      if Chain = nil then
        Continue;
      Words := LowerCase(Chain[0].Symbol.Signature).Split([' ', '(', ')', '<', '>', '=', ';'],
        TStringSplitOptions.ExcludeEmpty);
      for Index := 0 to High(Words) - 1 do
        if (Words[Index] = 'class') and ((Words[Index + 1] = 'sealed') or ((Words[Index + 1] = 'abstract') and
          (Index + 2 <= High(Words)) and (Words[Index + 2] = 'sealed'))) then
        begin
          AReport.Add(Symbol.SelectionRange, Format('%s ist sealed; davon lässt sich nicht ableiten (wie E2353).',
            [Chain[0].Symbol.Name]), TRuleConfidence.High);
          Break;
        end;
    end;
  end;

var
  Method: TMethodDecl;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Cache := TRuleDerived.Open(AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    for Method in ClassMethods(AContext, Ancestry) do
      if Method.Has('override') then
        CheckMethod(Method);
    CheckSealed;
  finally
    Ancestry.Free;
  end;
end;

{ TAbstractClassInstantiatedRule }

function TAbstractClassInstantiatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('abstract-class-instantiated', TRuleSeverity.Warning,
    'Instanz einer Klasse mit abstrakten Methoden');
end;

procedure TAbstractClassInstantiatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  MaxNamed = 5;
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;
  Actions: TClassActionContext;

  /// <summary>Klassenname vor ".Create" an Token AIndex (dem Punkt); -1 ohne.</summary>
  function ClassBefore(ADot: Integer): Integer;
  var
    Index, Depth: Integer;
  begin
    Index := ADot - 1;
    // TListe<T>.Create
    if (Index >= 0) and (Tokens[Index].Text = '>') then
    begin
      Depth := 0;
      while Index >= 0 do
      begin
        if Tokens[Index].Text = '>' then
          Inc(Depth)
        else if Tokens[Index].Text = '<' then
        begin
          Dec(Depth);
          if Depth = 0 then
            Break;
        end;
        Dec(Index);
      end;
      Dec(Index);
    end;
    Result := -1;
    if (Index < 0) or (Tokens[Index].Kind <> TPascalTokenKind.Identifier) then
      Exit;
    // constructor TForm.Create: der Kopf eines Rumpfs.
    if (Index > 0) and (Tokens[Index - 1].Kind = TPascalTokenKind.Keyword) and MatchText(Tokens[Index - 1].Text,
      ['constructor', 'procedure', 'function', 'destructor']) then
      Exit;
    Result := Index;
  end;

  procedure CheckCall(AName, ACreate: Integer);
  var
    Location: TSymbolLocation;
    Open: TArray<TIndexSymbol>;
    Owners, Names: TArray<string>;
    Index: Integer;
    Range: TTextRange;
    Fixes: TArray<TRuleFix>;
    Action: TCodeAction;
    Listed: string;
  begin
    if not Ancestry.FindClass(Tokens[AName].Text, Location) then
      Exit;
    Range := TTextRange.Create(Tokens[AName].StartPos, Tokens[ACreate].EndPos);
    Open := Ancestry.OpenAbstractMethods(Location, Owners);
    if Open = nil then
      Exit;
    Names := nil;
    Fixes := nil;
    for Index := 0 to High(Open) do
    begin
      if Length(Names) < MaxNamed then
        if SameText(Owners[Index], Location.Symbol.Name) then
          Names := Names + [Open[Index].Name]
        else
          Names := Names + [Owners[Index] + '.' + Open[Index].Name];
      // Geerbte abstrakte Methoden einer Klasse dieser Datei: dort überschreiben.
      if (Location.FileName = '') and not SameText(Owners[Index], Location.Symbol.Name) and
        TClassActions.OverrideMethod(AContext.Text, Location.Symbol.Range.StartPos.Line, Open[Index].Name, Actions,
        Action) then
        Fixes := Fixes + [TRuleFix.Create(Format('%s in %s überschreiben', [Open[Index].Name,
          Location.Symbol.Name]), Action.Edits)];
    end;
    for Index := 1 to High(Fixes) do
      Fixes[Index].Alternative := True;
    Listed := string.Join(', ', Names);
    if Length(Open) > MaxNamed then
      Listed := Listed + Format(' und %d weitere', [Length(Open) - MaxNamed]);
    if Length(Open) = 1 then
      AReport.Add(Range, Format('%s hat die abstrakte Methode %s; der Aufruf löst EAbstractError aus (wie W1020).',
        [Location.Symbol.Name, Listed]), TRuleConfidence.High, Fixes)
    else
      AReport.Add(Range, Format('%s hat die abstrakten Methoden %s; ihr Aufruf löst EAbstractError aus ' +
        '(wie W1020).', [Location.Symbol.Name, Listed]), TRuleConfidence.High, Fixes);
  end;

var
  Index, Name: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    Actions := TClassActionContext.Default;
    Actions.Index := AContext.Index;
    Actions.Namespaces := AContext.Namespaces;
    Actions.DelphiVersion := AContext.DelphiVersion;
    Actions.Style := AContext.Formatting;
    for Index := 1 to High(Tokens) do
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, 'Create') and
        (Tokens[Index - 1].Text = '.') then
      begin
        Name := ClassBefore(Index - 1);
        if Name >= 0 then
          CheckCall(Name, Index);
      end;
  finally
    Ancestry.Free;
  end;
end;

{ TInheritedAbstractCallRule }

function TInheritedAbstractCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-abstract-call', TRuleSeverity.Warning,
    'inherited ruft eine abstrakte Methode auf');
end;

class function TInheritedAbstractCallRule.IsAbstractSignature(const ASignature: string): Boolean;
var
  Parts: TArray<string>;
  Index, Depth, Position: Integer;
  Text: string;
begin
  // Parameterliste ausblenden: ein Parameter "abstract: Boolean" wäre keine Direktive.
  Text := '';
  Depth := 0;
  for Position := 1 to Length(ASignature) do
    if ASignature[Position] = '(' then
      Inc(Depth)
    else if ASignature[Position] = ')' then
      Dec(Depth)
    else if Depth = 0 then
      Text := Text + ASignature[Position];
  Parts := Text.Split([';']);
  // Der erste Teil ist der Kopf selbst, die Direktiven folgen hinter Semikolons.
  for Index := 1 to High(Parts) do
    if SameText(Trim(Parts[Index]), 'abstract') then
      Exit(True);
  Result := False;
end;

procedure TInheritedAbstractCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Tokens: TArray<TPascalToken>;
  Resolver: TNameResolver;
  FileName: string;
  Calls: TDictionary<Integer, TSyntaxNode>;

  /// <summary>Anweisung, die nur aus dem inherited-Aufruf besteht und in einem begin…end steht; sonst nil.
  /// </summary>
  function OwnStatement(AExpr: TSyntaxNode): TSyntaxNode;
  var
    Node: TSyntaxNode;
  begin
    Result := nil;
    Node := AExpr.Parent;
    if (Node <> nil) and (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and (Node[0] = AExpr) then
      Node := Node.Parent;
    if (Node <> nil) and (Node.Kind = TSyntaxKind.CallStatement) and (Node.Parent <> nil) and
      (Node.Parent.Kind = TSyntaxKind.Block) then
      Result := Node;
  end;

  procedure CheckCall(AExpr: TSyntaxNode; ANameToken: Integer);
  var
    Candidates: TArray<TResolvedSymbol>;
    Candidate: TResolvedSymbol;
    Statement: TSyntaxNode;
    Fixes: TArray<TRuleFix>;
  begin
    Candidates := Resolver.ResolveAll(AContext.Tree, FileName, Tokens[ANameToken].StartPos);
    if Candidates = nil then
      Exit;
    // Nur wenn jede passende Überladung abstrakt ist; sonst wählt der Compiler womöglich eine andere.
    for Candidate in Candidates do
      if not (Candidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) or
        (Candidate.Condition <> '') or not IsAbstractSignature(Candidate.Signature) then
        Exit;
    Fixes := nil;
    Statement := OwnStatement(AExpr);
    if Statement <> nil then
      Fixes := [RemoveStatementFix(Cache, AContext, Statement, 'Aufruf entfernen')];
    AReport.Add(TTextRange.Create(AExpr.StartPos, AExpr.EndPos), Format('%s.%s ist abstrakt; der Aufruf über ' +
      'inherited löst zur Laufzeit EAbstractError aus.', [Candidates[0].Container, Candidates[0].Name]),
      TRuleConfidence.High, Fixes);
  end;

var
  Index: Integer;
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Calls := TDictionary<Integer, TSyntaxNode>.Create;
  try
    // inherited mit Namen; ein bloßes inherited; übergeht der Compiler bei abstrakten Methoden still.
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.InheritedExpr) and (ANode.Name <> '') then
          Calls.AddOrSetValue(ANode.StartOffset, ANode);
        Result := True;
      end);
    if Calls.Count = 0 then
      Exit;
    FileName := AContext.FileName;
    if FileName = '' then
      FileName := AContext.RelativePath;
    if FileName = '' then
      FileName := AContext.UnitName + '.pas';
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      try
        for Index := 0 to High(Tokens) - 1 do
          if Calls.TryGetValue(Tokens[Index].Offset, Node) and
            (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
            CheckCall(Node, Index + 1);
      finally
        Resolver.UnpinTree;
      end;
    finally
      Resolver.Free;
    end;
  finally
    Calls.Free;
  end;
end;

{ TClassReferenceNonvirtualConstructorRule }

function TClassReferenceNonvirtualConstructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('class-reference-nonvirtual-constructor', TRuleSeverity.Warning,
    'Konstruktor über Klassenreferenz nicht virtuell (wie E2391)');
end;

class function TClassReferenceNonvirtualConstructorRule.ClassRefTarget(const ASignature: string): string;
var
  Words: TArray<string>;
  Index: Integer;
begin
  Result := '';
  Words := ASignature.Replace(';', ' ').Split([' ', #9, #10, #13, '='], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 2 do
    if SameText(Words[Index], 'class') and SameText(Words[Index + 1], 'of') then
      Exit(Words[Index + 2]);
end;

procedure TClassReferenceNonvirtualConstructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Resolver: TNameResolver;
  FileName: string;
  Local: TUnitIndex;
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Methods: TArray<TMethodDecl>;
  MethodsRead: Boolean;
  Calls: TArray<TSyntaxNode>;

  function IsLocal(const AFileName: string): Boolean;
  begin
    Result := (AFileName = '') or SameText(AFileName, FileName);
  end;

  /// <summary>Unit, in der ein Symbol aus AFileName steht: die geprüfte Datei oder der Index.</summary>
  function UnitFor(const AFileName: string; out AUnit: TUnitIndex): Boolean;
  begin
    Result := True;
    if IsLocal(AFileName) then
      AUnit := Local
    else
      Result := (AContext.Index <> nil) and AContext.Index.FindFile(AFileName, AUnit);
  end;

  /// <summary>Zweig der bedingten Übersetzung an APosition ('' ohne {$IF…}).</summary>
  function PathAt(const APosition: TTextPosition): string;
  var
    Low, High, Middle: Integer;
  begin
    Result := '';
    if Paths = nil then
      Exit;
    Low := 0;
    High := Length(Tokens) - 1;
    while Low < High do
    begin
      Middle := (Low + High) div 2;
      if (Tokens[Middle].StartPos.Line < APosition.Line) or ((Tokens[Middle].StartPos.Line = APosition.Line) and
        (Tokens[Middle].StartPos.Character < APosition.Character)) then
        Low := Middle + 1
      else
        High := Middle;
    end;
    Result := TConditionalBranches.PathAt(Paths, Low);
  end;

  /// <summary>Steht die Deklaration sicher, wo der Aufruf an ACall übersetzt wird? Aus dem Index ohne Bedingung,
  /// in der Datei in demselben oder einem umschließenden Zweig.</summary>
  function Certain(const AFileName, ACondition: string; const ADeclaration: TTextPosition; ACall: TSyntaxNode):
    Boolean;
  begin
    if ACondition <> '' then
      Exit(False);
    Result := not IsLocal(AFileName) or TConditionalBranches.Implies(PathAt(ACall.StartPos), PathAt(ADeclaration));
  end;

  function ClassMethodsOnce: TArray<TMethodDecl>;
  begin
    if not MethodsRead then
    begin
      Methods := ClassMethods(AContext, Ancestry);
      MethodsRead := True;
    end;
    Result := Methods;
  end;

  /// <summary>Korrektur, wenn der Konstruktor in dieser Datei steht: virtual an ihn, override an die
  /// gleichlautenden Konstruktoren der Nachfahren in dieser Datei.</summary>
  function VirtualFix(const AConstructor: TIndexSymbol; out AFix: TRuleFix): Boolean;
  var
    Method: TMethodDecl;
    Fix: TRuleFix;
    Edits: TArray<TRuleEdit>;
    Found: Boolean;
  begin
    Result := False;
    Found := False;
    Edits := nil;
    for Method in ClassMethodsOnce do
      if (Method.Keyword = 'constructor') and (Method.Symbol.SelectionRange.StartPos =
        AConstructor.SelectionRange.StartPos) then
      begin
        if not AppendDirective(AContext, Method, 'virtual', Fix) then
          Exit;
        Edits := Edits + Fix.Edits;
        Found := True;
      end;
    if not Found then
      Exit;
    for Method in ClassMethodsOnce do
      if (Method.Keyword = 'constructor') and SameText(Method.Symbol.Name, AConstructor.Name) and
        not SameText(Method.ClassName, AConstructor.Container) and not Settled(Method) and
        SameSignature(Method.Symbol, AConstructor) and Ancestry.DescendsFrom(Method.ClassName,
        AConstructor.Container) and AppendDirective(AContext, Method, 'override', Fix) then
        Edits := Edits + Fix.Edits;
    if Length(Edits) > 1 then
      AFix := TRuleFix.Create(Format('virtual an %s.%s, override in den Nachfahren', [AConstructor.Container,
        AConstructor.Name]), Edits)
    else
      AFix := TRuleFix.Create(Format('virtual an %s.%s', [AConstructor.Container, AConstructor.Name]), Edits);
    Result := True;
  end;

  procedure CheckCall(AAccess: TSyntaxNode);
  var
    Symbol, RefType, Base, Member: TResolvedSymbol;
    TypeFound: Boolean;
    Target: string;
    TypeUnit, MemberUnit: TUnitIndex;
    Candidate, Matching, Owner: TIndexSymbol;
    Matches, Args: Integer;
    OwnerFound: Boolean;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
  begin
    // Der Empfänger ist ein Wert (Variable, Feld, Parameter, Funktion), dessen Typ class of … ist.
    if not Resolver.NodeType(AContext.Tree, FileName, AAccess[0], Symbol, RefType, TypeFound) or not TypeFound or
      Symbol.IsType or not Symbol.Found or RefType.Builtin or (RefType.SymbolKind <> TIndexSymbolKind.ClassType) then
      Exit;
    Target := ClassRefTarget(RefType.Signature);
    if (Target = '') or not Certain(Symbol.FileName, Symbol.Condition, Symbol.SelectionRange.StartPos, AAccess) or
      not Certain(RefType.FileName, RefType.Condition, RefType.SelectionRange.StartPos, AAccess) or
      not UnitFor(RefType.FileName, TypeUnit) or not Resolver.ResolveTypeFrom(TypeUnit, Target, Base) or
      (Base.SymbolKind <> TIndexSymbolKind.ClassType) then
      Exit;
    // Der nächste Typ der Kette, der Create deklariert, samt seiner Überladungen.
    if not Resolver.FindMember(Base, AAccess.Name, Member) or Member.IsHelper or
      (Member.SymbolKind <> TIndexSymbolKind.Constructor_) or not UnitFor(Member.FileName, MemberUnit) then
      Exit;
    Args := 0;
    if (AAccess.Parent <> nil) and (AAccess.Parent.Kind = TSyntaxKind.Call) and (AAccess.Parent[0] = AAccess) then
      Args := AAccess.Parent.ChildCount - 1;
    // Die Klasse, in der Member deklariert ist: Rümpfe (constructor TPlugin.Create) stehen außerhalb.
    OwnerFound := False;
    for Owner in MemberUnit.Symbols do
      if (Owner.Kind = TIndexSymbolKind.ClassType) and SameText(Owner.QualifiedName, Member.Container) and
        ContainsLine(Owner.Range, Member.Range.StartPos.Line) then
      begin
        OwnerFound := True;
        Break;
      end;
    if not OwnerFound then
      Exit;
    Matches := 0;
    Matching := Default(TIndexSymbol);
    for Candidate in MemberUnit.Symbols do
      if (Candidate.Kind = TIndexSymbolKind.Constructor_) and SameText(Candidate.Name, Member.Name) and
        SameText(Candidate.Container, Member.Container) and
        ContainsLine(Owner.Range, Candidate.Range.StartPos.Line) then
      begin
        if not Certain(Member.FileName, Candidate.Condition, Candidate.SelectionRange.StartPos, AAccess) then
          Exit;
        if (Args < Candidate.MinArgs) or ((Candidate.MaxArgs >= 0) and (Args > Candidate.MaxArgs)) then
          Continue;
        // Eine passende virtuelle Überladung genügt, damit die Regel schweigt.
        if Candidate.IsVirtual or Candidate.HasDirective('virtual') or Candidate.HasDirective('dynamic') or
          Candidate.HasDirective('override') or Candidate.HasDirective('abstract') then
          Exit;
        Inc(Matches);
        Matching := Candidate;
      end;
    if Matches = 0 then
      Exit;
    Fixes := nil;
    if (Matches = 1) and IsLocal(Member.FileName) and VirtualFix(Matching, Fix) then
      Fixes := [Fix];
    AReport.Add(TTextRange.Create(AAccess.StartPos, AAccess.EndPos), Format('%s.%s ist nicht virtuell; über die ' +
      'Klassenreferenz läuft immer %s.%s (wie E2391).', [Member.Container, Member.Name, Member.Container,
      Member.Name]), TRuleConfidence.High, Fixes);
  end;

var
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Calls := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and SameText(ANode.Name, 'Create') then
        Calls := Calls + [ANode];
      Result := True;
    end);
  if Calls = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  MethodsRead := False;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
    try
      Resolver.Namespaces := AContext.Namespaces;
      Resolver.PinTree(AContext.Tree, FileName);
      try
        Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
        for Node in Calls do
          CheckCall(Node);
      finally
        Resolver.UnpinTree;
      end;
    finally
      Resolver.Free;
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TMemberHidesAncestorRule }

function TMemberHidesAncestorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(MemberHidesAncestorRuleId, TRuleSeverity.Warning,
    'Member verdeckt einen gleichnamigen Member des Vorfahren');
end;

procedure TMemberHidesAncestorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;
  IgnoreStrictPrivate: Boolean;

  /// <summary>Sieht der Nachfahre den Member ASymbol des Vorfahren auf AType?</summary>
  function Visible(const AType: TSymbolLocation; const ASymbol: TIndexSymbol): Boolean;
  begin
    if ASymbol.Visibility = TIndexVisibility.StrictPrivate then
      Result := not IgnoreStrictPrivate and (AType.FileName = '')
    else
      Result := (ASymbol.Visibility <> TIndexVisibility.Private) or (AType.FileName = '');
  end;

  function IsClassMember(const ASymbol: TIndexSymbol): Boolean;
  begin
    Result := ASymbol.HasDirective('class') or StartsText('class ', ASymbol.Signature);
  end;

  /// <summary>Kann AOwn einen Member des Vorfahren verdecken? Neu veröffentlichte Properties (property Caption;),
  /// Konstruktoren, Klassenmethoden und bewusst gelöste Fälle nicht.</summary>
  function Candidate(const AOwn: TIndexSymbol): Boolean;
  begin
    Result := not AOwn.Unavailable;
    if not Result then
      Exit;
    case AOwn.Kind of
      TIndexSymbolKind.Field:
        Result := True;
      TIndexSymbolKind.Property_:
        Result := (AOwn.TypeName <> '') and not IsClassMember(AOwn);
      TIndexSymbolKind.Method:
        Result := not IsClassMember(AOwn) and not AOwn.IsVirtual and not AOwn.HasDirective('reintroduce') and
          not AOwn.HasDirective('overload') and not AOwn.HasDirective('message');
    else
      Result := False;
    end;
  end;

  /// <summary>Kurzname der Klasse ohne führendes T ("TKunde" → "Kunde").</summary>
  function ShortName(const AClassName: string): string;
  begin
    Result := AClassName;
    if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
      Result := Copy(Result, 2, MaxInt);
  end;

  /// <summary>Korrektur: AOwn in der Klassendeklaration und in den Rümpfen der Klasse umbenennen. Zugriffe über einen
  /// anderen Ausdruck (Obj.FName) und andere Units bleiben unverändert.</summary>
  function RenameFix(const AClass: TIndexSymbol; const AOwn: TIndexSymbol): TArray<TRuleFix>;
  var
    NewName, Prefix: string;
    Index, Inner, Body: Integer;
    Edits: TArray<TRuleEdit>;
    Bodies: TArray<TSyntaxNode>;
    Section: TSyntaxNode;
    InBody: Boolean;
  begin
    Result := nil;
    if AOwn.Kind = TIndexSymbolKind.Field then
    begin
      Prefix := '';
      if (Length(AOwn.Name) > 1) and CharInSet(AOwn.Name[1], ['F', 'f']) and CharInSet(AOwn.Name[2], ['A'..'Z']) then
        Prefix := Copy(AOwn.Name, 1, 1);
      NewName := Prefix + ShortName(AClass.Name) + Copy(AOwn.Name, Length(Prefix) + 1, MaxInt);
    end
    else
      NewName := ShortName(AClass.Name) + AOwn.Name;
    for Index := 0 to High(Tokens) do
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, NewName) then
        Exit;
    // Rümpfe der Methoden der Klasse (TKunde.X) aus dem implementation-Teil.
    Bodies := nil;
    Section := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    if Section <> nil then
      for Index := 0 to Section.ChildCount - 1 do
        if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and
          StartsText(AClass.Name + '.', Section[Index].Name) then
          Bodies := Bodies + [Section[Index]];
    Edits := nil;
    for Index := 0 to High(Tokens) do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(Tokens[Index].Text, AOwn.Name) then
        Continue;
      InBody := False;
      for Body := 0 to High(Bodies) do
        InBody := InBody or ((Tokens[Index].Offset >= Bodies[Body].StartOffset) and
          (Tokens[Index].Offset < Bodies[Body].EndOffset));
      if not InBody and not ContainsLine(AClass.Range, Tokens[Index].StartPos.Line) then
        Continue;
      // Obj.FName: nur Self.FName zählt; im Rumpfkopf "procedure TKunde.Name" ist es der Methodenname.
      if (Index > 0) and Tokens[Index - 1].IsSymbol('.') then
      begin
        Inner := Index - 2;
        if (Inner < 0) or not SameText(Tokens[Inner].Text, 'Self') then
          Continue;
      end;
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos), NewName)];
    end;
    if Edits <> nil then
      Result := [TRuleFix.Create(Format('In %s umbenennen (in dieser Unit)', [NewName]), Edits)];
  end;

  procedure CheckMember(const AClass: TIndexSymbol; const AOwn: TIndexSymbol; const AChain: TArray<TSymbolLocation>);
  var
    Level: Integer;
    Symbol, Hidden: TIndexSymbol;
    Any, Found: Boolean;
    Confidence: TRuleConfidence;
    Message: string;
  begin
    for Level := 0 to High(AChain) do
    begin
      Any := False;
      Found := False;
      for Symbol in Ancestry.Members(AChain[Level]) do
      begin
        if not SameText(Symbol.Name, AOwn.Name) then
          Continue;
        // Nur in einem inaktiven Zweig: keine Aussage.
        if Symbol.Unavailable then
          Exit;
        if not Visible(AChain[Level], Symbol) then
          Continue;
        Any := True;
        case AOwn.Kind of
          TIndexSymbolKind.Field:
            Found := Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_];
          TIndexSymbolKind.Property_:
            Found := Symbol.Kind = TIndexSymbolKind.Field;
          TIndexSymbolKind.Method:
            // Virtuelle Methoden meldet hides-virtual.
            Found := (Symbol.Kind = TIndexSymbolKind.Method) and not Symbol.IsVirtual and not IsClassMember(Symbol) and
              SameSignature(Symbol, AOwn);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        if Found then
        begin
          Hidden := Symbol;
          Break;
        end;
      end;
      if Found then
      begin
        Confidence := TRuleConfidence.High;
        if AOwn.Kind = TIndexSymbolKind.Method then
          Confidence := TRuleConfidence.Medium;
        // dcc meldet W1009 nur, wenn eine Property ein Feld verdeckt; Feld über Feld oder Property und
        // statische Methode über statische Methode übersetzt Delphi 13 still (#1383).
        Message := Format('%s verdeckt %s.%s', [AOwn.Name, AChain[Level].Symbol.Name, Hidden.Name]);
        if AOwn.Kind = TIndexSymbolKind.Property_ then
          Message := Message + ' (wie W1009)';
        if AOwn.Kind = TIndexSymbolKind.Method then
          AReport.Add(AOwn.SelectionRange, Message + '.', Confidence)
        else
          AReport.Add(AOwn.SelectionRange, Message + '.', Confidence, RenameFix(AClass, AOwn));
        Exit;
      end;
      // Die nächste Stufe mit gleichnamigem Member entscheidet.
      if Any then
        Exit;
    end;
  end;

var
  Symbol, Member: TIndexSymbol;
  Location: TSymbolLocation;
  Chain: TArray<TSymbolLocation>;
  Complete, ObjectMissing: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  IgnoreStrictPrivate := TRuleOptions.Bool(AContext.Options, 'ignoreStrictPrivate', True);
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    for Symbol in Ancestry.Local.Symbols do
    begin
      if (Symbol.Kind <> TIndexSymbolKind.ClassType) or (Symbol.Container <> '') or Symbol.Unavailable or
        (Symbol.Ancestors = nil) then
        Continue;
      Chain := Ancestry.Ancestors(Symbol.Name, Complete, ObjectMissing);
      if Chain = nil then
        Continue;
      Location := Default(TSymbolLocation);
      Location.Symbol := Symbol;
      for Member in Ancestry.Members(Location) do
        if Candidate(Member) then
          CheckMember(Symbol, Member, Chain);
    end;
  finally
    Ancestry.Free;
  end;
end;

{ TOverrideCaseMismatchRule }

function TOverrideCaseMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OverrideCaseMismatchRuleId, TRuleSeverity.Hint,
    'Schreibweise oder Sichtbarkeit weicht vom Vorfahren ab', True);
end;

/// <summary>Stufe einer Sichtbarkeit: 0 privat, 1 geschützt, 2 öffentlich (public und published). Nur Stufen
/// werden verglichen; private gegen strict protected bleibt offen.</summary>
function VisibilityTier(AVisibility: TIndexVisibility): Integer;
begin
  case AVisibility of
    TIndexVisibility.StrictPrivate, TIndexVisibility.Private:
      Result := 0;
    TIndexVisibility.StrictProtected, TIndexVisibility.Protected:
      Result := 1;
  else
    Result := 2;
  end;
end;

function VisibilityName(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Published:
      Result := 'published';
    TIndexVisibility.Protected:
      Result := 'protected';
    TIndexVisibility.StrictProtected:
      Result := 'strict protected';
    TIndexVisibility.Private:
      Result := 'private';
    TIndexVisibility.StrictPrivate:
      Result := 'strict private';
  else
    Result := 'public';
  end;
end;

procedure TOverrideCaseMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;

  function TokenRange(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AIndex].StartPos, Tokens[AIndex].EndPos);
  end;

  /// <summary>Erstes Token ab AOffset; Length(Tokens) ohne.</summary>
  function TokenFrom(AOffset: Integer): Integer;
  var
    Low, High, Middle: Integer;
  begin
    Low := 0;
    High := Length(Tokens);
    while Low < High do
    begin
      Middle := (Low + High) div 2;
      if Tokens[Middle].Offset < AOffset then
        Low := Middle + 1
      else
        High := Middle;
    end;
    Result := Low;
  end;

  /// <summary>Edits, die den Namen AOld in den Rumpfköpfen "procedure AClassName.AOld" durch ANew ersetzen.</summary>
  function BodyHeadEdits(const AClassName, AOld, ANew: string): TArray<TRuleEdit>;
  var
    Index: Integer;
  begin
    Result := nil;
    for Index := 1 to High(Tokens) - 2 do
      if (Tokens[Index - 1].Kind = TPascalTokenKind.Keyword) and MatchText(Tokens[Index - 1].Text, ['procedure',
        'function', 'constructor', 'destructor']) and SameText(Tokens[Index].Text, AClassName) and
        Tokens[Index + 1].IsSymbol('.') and (Tokens[Index + 2].Kind = TPascalTokenKind.Identifier) and
        SameText(Tokens[Index + 2].Text, AOld) and (Tokens[Index + 2].Text <> ANew) then
        Result := Result + [TRuleEdit.Create(TokenRange(Index + 2), ANew)];
  end;

  /// <summary>Token der Property AProperty: vom Namen bis vor das abschließende ";".</summary>
  procedure PropertyTokens(const AProperty: TIndexSymbol; out AFirst, ALast: Integer);
  begin
    AFirst := 0;
    while (AFirst <= High(Tokens)) and ((Tokens[AFirst].StartPos.Line < AProperty.Range.StartPos.Line) or
      ((Tokens[AFirst].StartPos.Line = AProperty.Range.StartPos.Line) and
      (Tokens[AFirst].StartPos.Character < AProperty.Range.StartPos.Character))) do
      Inc(AFirst);
    ALast := AFirst;
    while (ALast < High(Tokens)) and not Tokens[ALast].IsSymbol(';') do
      Inc(ALast);
  end;

  /// <summary>Edits, die hinter read/write der Property AProperty den Namen AOld durch ANew ersetzen.</summary>
  function AccessorEdits(const AProperty: TIndexSymbol; const AOld, ANew: string): TArray<TRuleEdit>;
  var
    Index, First, Last: Integer;
  begin
    Result := nil;
    PropertyTokens(AProperty, First, Last);
    for Index := First + 1 to Last - 1 do
      if SameText(Tokens[Index].Text, AOld) and (SameText(Tokens[Index - 1].Text, 'read') or
        SameText(Tokens[Index - 1].Text, 'write')) then
        Result := Result + [TRuleEdit.Create(TokenRange(Index), ANew)];
  end;

  /// <summary>Mitglied AName der eigenen Members oder der nächsten Stufe der Kette, die es dort sichtbar gibt.
  /// False, wenn keine Aussage möglich ist (nur in inaktivem Zweig).</summary>
  function FindVisibleMember(const AName: string; const AOwnMembers: TArray<TIndexSymbol>;
    const AChain: TArray<TSymbolLocation>; out AHit: TIndexSymbol; out AFound: Boolean): Boolean;
  var
    Symbol: TIndexSymbol;
    Location: TSymbolLocation;
  begin
    AHit := Default(TIndexSymbol);
    AFound := False;
    for Symbol in AOwnMembers do
      if SameText(Symbol.Name, AName) then
      begin
        if Symbol.Unavailable then
          Exit(False);
        AHit := Symbol;
        AFound := True;
        Exit(True);
      end;
    for Location in AChain do
      for Symbol in Ancestry.Members(Location) do
        if SameText(Symbol.Name, AName) then
        begin
          if Symbol.Unavailable then
            Exit(False);
          if (Symbol.Visibility = TIndexVisibility.StrictPrivate) or ((Location.FileName <> '') and
            (Symbol.Visibility = TIndexVisibility.Private)) then
            Continue;
          AHit := Symbol;
          AFound := True;
          Exit(True);
        end;
    Result := True;
  end;

  /// <summary>Die überschriebene Methode: nächste Stufe mit gleichnamiger, sichtbarer, virtueller Methode gleicher
  /// Parameterzahl; TObject über die Tabelle, wenn System nicht im Index steht. False ohne sichere Aussage.</summary>
  function Overridden(const AOwn: TIndexSymbol; const AChain: TArray<TSymbolLocation>; AObjectMissing: Boolean;
    out AOwner: string; out ATarget: TIndexSymbol): Boolean;
  var
    Location: TSymbolLocation;
    Symbol: TIndexSymbol;
    Any: Boolean;
    Name: string;
  begin
    Result := False;
    ATarget := Default(TIndexSymbol);
    for Location in AChain do
    begin
      Any := False;
      for Symbol in Ancestry.Methods(Location) do
      begin
        if not SameText(Symbol.Name, AOwn.Name) then
          Continue;
        if Symbol.Unavailable then
          Exit;
        if (Symbol.Visibility = TIndexVisibility.StrictPrivate) or ((Location.FileName <> '') and
          (Symbol.Visibility = TIndexVisibility.Private)) then
          Continue;
        Any := True;
        if Symbol.IsVirtual and (Symbol.MaxArgs = AOwn.MaxArgs) and
          (StartsText('class ', Symbol.Signature) = StartsText('class ', AOwn.Signature)) then
        begin
          AOwner := Location.Symbol.Name;
          ATarget := Symbol;
          Exit(True);
        end;
      end;
      if Any then
        Exit;
    end;
    if AObjectMissing and (AOwn.MaxArgs = 0) then
      for Name in ObjectVirtualNames do
        if SameText(Name, AOwn.Name) then
        begin
          AOwner := 'TObject';
          ATarget.Name := Name;
          ATarget.Visibility := TIndexVisibility.Public;
          Exit(True);
        end;
  end;

  procedure CheckOverride(const AClass, AOwn: TIndexSymbol; const AChain: TArray<TSymbolLocation>;
    AObjectMissing: Boolean);
  var
    Owner: string;
    Target: TIndexSymbol;
  begin
    if not Overridden(AOwn, AChain, AObjectMissing, Owner, Target) then
      Exit;
    if Target.Name <> AOwn.Name then
      AReport.Add(AOwn.SelectionRange, Format('Schreibweise weicht von %s.%s ab (wie H2365).', [Owner, Target.Name]),
        TRuleConfidence.High, [TRuleFix.Create('Schreibweise vom Vorfahr übernehmen',
        [TRuleEdit.Create(AOwn.SelectionRange, Target.Name)] + BodyHeadEdits(AClass.Name, AOwn.Name, Target.Name))]);
    // Nur für Klassen im interface-Teil (die Sichtbarkeit sieht man nur dort von außen).
    if AClass.InInterface and (VisibilityTier(AOwn.Visibility) < VisibilityTier(Target.Visibility)) then
      AReport.Add(AOwn.SelectionRange, Format('%s.%s ist %s und damit weniger sichtbar als %s.%s (%s) (wie H2269).',
        [AClass.Name, AOwn.Name, VisibilityName(AOwn.Visibility), Owner, Target.Name,
        VisibilityName(Target.Visibility)]), TRuleConfidence.High);
  end;

  /// <summary>Getter oder Setter heißt Get&lt;Property&gt; bzw. Set&lt;Property&gt;, nur anders geschrieben.
  /// </summary>
  procedure CheckAccessors(const AClass, AProperty: TIndexSymbol; const AOwnMembers: TArray<TIndexSymbol>);
  var
    Index, Last: Integer;
    Expected, Name: string;
    Member, Method: TIndexSymbol;
    Found: Boolean;
    Edits: TArray<TRuleEdit>;
  begin
    PropertyTokens(AProperty, Index, Last);
    while Index < Last do
    begin
      if (Index + 2 <= High(Tokens)) and (Tokens[Index].Kind in [TPascalTokenKind.Identifier,
        TPascalTokenKind.Keyword]) and (SameText(Tokens[Index].Text, 'read') or SameText(Tokens[Index].Text, 'write')) and
        (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) and not Tokens[Index + 2].IsSymbol('.') then
      begin
        Name := Tokens[Index + 1].Text;
        if SameText(Tokens[Index].Text, 'read') then
          Expected := 'Get' + AProperty.Name
        else
          Expected := 'Set' + AProperty.Name;
        Found := False;
        Method := Default(TIndexSymbol);
        for Member in AOwnMembers do
          if SameText(Member.Name, Name) then
          begin
            Found := Member.Kind = TIndexSymbolKind.Method;
            Method := Member;
            if not Found then
              Break;
          end;
        if Found and SameText(Name, Expected) and (Name <> Expected) then
        begin
          // Umbenennen in der Klasse (Deklaration, Properties) und in den Rumpfköpfen.
          Edits := nil;
          for Member in AOwnMembers do
            if (Member.Kind = TIndexSymbolKind.Method) and SameText(Member.Name, Name) then
              Edits := Edits + [TRuleEdit.Create(Member.SelectionRange, Expected)];
          for Member in AOwnMembers do
            if Member.Kind = TIndexSymbolKind.Property_ then
              Edits := Edits + AccessorEdits(Member, Name, Expected);
          Edits := Edits + BodyHeadEdits(AClass.Name, Name, Expected);
          AReport.Add(TokenRange(Index + 1), Format('Die Zugriffsmethode %s.%s sollte %s.%s geschrieben werden.',
            [AClass.Name, Method.Name, AClass.Name, Expected]), TRuleConfidence.High,
            [TRuleFix.Create(Format('In %s umbenennen', [Expected]), Edits)]);
        end;
      end;
      Inc(Index);
    end;
  end;

  /// <summary>Die inline-Methode AMethod greift im Rumpf auf ein weniger sichtbares Mitglied zu.</summary>
  procedure CheckInline(const AType, AMethod: TIndexSymbol; const AOwnMembers: TArray<TIndexSymbol>;
    const AChain: TArray<TSymbolLocation>);
  var
    Section, Routine, Body, Node: TSyntaxNode;
    Stack: TArray<TSyntaxNode>;
    Index, Level, Child: Integer;
    Locals, Reported: TArray<string>;
    HasWith: Boolean;
    Hit, Same: TIndexSymbol;
    Found: Boolean;
  begin
    // Alle gleichnamigen Deklarationen inline und auf derselben Stufe, sonst ist der Rumpf nicht zuzuordnen.
    for Same in AOwnMembers do
      if SameText(Same.Name, AMethod.Name) and ((Same.Kind <> TIndexSymbolKind.Method) or
        not Same.HasDirective('inline') or (VisibilityTier(Same.Visibility) <> VisibilityTier(AMethod.Visibility)) or
        Same.Unavailable) then
        Exit;
    Section := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    if Section = nil then
      Exit;
    Reported := nil;
    for Index := 0 to Section.ChildCount - 1 do
    begin
      Routine := Section[Index];
      if (Routine.Kind <> TSyntaxKind.RoutineDecl) or not SameText(Routine.Name, AType.Name + '.' + AMethod.Name) then
        Continue;
      Body := Routine.FindChild(TSyntaxKind.Block);
      if Body = nil then
        Continue;
      Locals := nil;
      HasWith := False;
      // Lokale Namen (Parameter, Variablen, Konstanten, Typen, verschachtelte Routinen) verdecken Mitglieder.
      Stack := [Routine];
      while Stack <> nil do
      begin
        Node := Stack[High(Stack)];
        SetLength(Stack, Length(Stack) - 1);
        if (Node <> Routine) and (Node.Kind in [TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl,
          TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl]) then
          Locals := Locals + Node.Name.Split([',']);
        if Node.Kind = TSyntaxKind.WithStatement then
          HasWith := True;
        for Child := 0 to Node.ChildCount - 1 do
          Stack := Stack + [Node[Child]];
      end;
      if HasWith then
        Continue;
      for Level := TokenFrom(Body.StartOffset) to High(Tokens) do
      begin
        if Tokens[Level].Offset >= Body.EndOffset then
          Break;
        if (Tokens[Level].Kind <> TPascalTokenKind.Identifier) or MatchText(Tokens[Level].Text, Locals) or
          MatchText(Tokens[Level].Text, Reported) then
          Continue;
        // Obj.FWert gehört einem anderen Ausdruck; nur Self.FWert zählt.
        if (Level > 0) and Tokens[Level - 1].IsSymbol('.') and ((Level < 2) or
          not SameText(Tokens[Level - 2].Text, 'Self')) then
          Continue;
        if not FindVisibleMember(Tokens[Level].Text, AOwnMembers, AChain, Hit, Found) or not Found then
          Continue;
        if VisibilityTier(Hit.Visibility) >= VisibilityTier(AMethod.Visibility) then
          Continue;
        Reported := Reported + [Tokens[Level].Text];
        AReport.Add(TokenRange(Level), Format('Die inline-Methode %s.%s ist %s, greift aber auf %s (%s) zu.',
          [AType.Name, AMethod.Name,
          VisibilityName(AMethod.Visibility), Hit.Name, VisibilityName(Hit.Visibility)]), TRuleConfidence.High);
      end;
    end;
  end;

var
  Symbol, Member: TIndexSymbol;
  Location: TSymbolLocation;
  Chain: TArray<TSymbolLocation>;
  Members: TArray<TIndexSymbol>;
  Complete, ObjectMissing: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    for Symbol in Ancestry.Local.Symbols do
    begin
      if not (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType]) or (Symbol.Container <> '') or
        Symbol.Unavailable then
        Continue;
      Location := Default(TSymbolLocation);
      Location.Symbol := Symbol;
      Members := Ancestry.Members(Location);
      Chain := nil;
      ObjectMissing := False;
      if Symbol.Kind = TIndexSymbolKind.ClassType then
        Chain := Ancestry.Ancestors(Symbol.Name, Complete, ObjectMissing);
      for Member in Members do
      begin
        if Member.Unavailable then
          Continue;
        if (Member.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
          Member.HasDirective('override') and (Symbol.Kind = TIndexSymbolKind.ClassType) then
          CheckOverride(Symbol, Member, Chain, ObjectMissing);
        if Member.Kind = TIndexSymbolKind.Property_ then
          CheckAccessors(Symbol, Member, Members);
        if (Member.Kind = TIndexSymbolKind.Method) and Member.HasDirective('inline') then
          CheckInline(Symbol, Member, Members, Chain);
      end;
    end;
  finally
    Ancestry.Free;
  end;
end;

{ Hilfen für override-only-inherited und inherited-without-ancestor }

const
  // Öffentliche Methoden von TObject, falls System nicht im Index steht (#1144).
  ObjectMethodNames: array[0..21] of string = ('Create', 'Free', 'DisposeOf', 'ClassType', 'ClassName',
    'ClassNameIs', 'ClassParent', 'ClassInfo', 'InstanceSize', 'InheritsFrom', 'MethodAddress', 'MethodName',
    'QualifiedClassName', 'FieldAddress', 'GetInterface', 'GetInterfaceEntry', 'GetInterfaceTable', 'UnitName',
    'UnitScope', 'CleanupInstance', 'InitInstance', 'NewInstance');

/// <summary>Implementierungen von Methoden (TKlasse.Methode) auf oberster Ebene, ohne lokale Routinen.</summary>
function MethodBodies(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TArray<TSyntaxNode>;
var
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  for mRoutine in TRuleDerived.Routines(ACache, AContext) do
    if (Pos('.', mRoutine.Name) > 0) and ((mRoutine.Parent = nil) or
      (mRoutine.Parent.Kind <> TSyntaxKind.RoutineDecl)) then
      Result := Result + [mRoutine];
end;

/// <summary>Klasse und Methode aus "TAussen.TKlasse<T>.Methode": TKlasse und Methode.</summary>
procedure SplitMethodName(const AName: string; out AClassName, AMethodName: string);
var
  mParts: TArray<string>;
  mText: string;
  mDepth, mIndex: Integer;
begin
  // Punkte in Typargumenten (TDictionary<System.string, …>) trennen nicht.
  mText := '';
  mDepth := 0;
  for mIndex := 1 to Length(AName) do
  begin
    if AName[mIndex] = '<' then
      Inc(mDepth)
    else if AName[mIndex] = '>' then
      Dec(mDepth)
    else if mDepth = 0 then
      mText := mText + AName[mIndex];
  end;
  mParts := mText.Split(['.']);
  AClassName := '';
  AMethodName := '';
  if Length(mParts) < 2 then
    Exit;
  AClassName := mParts[High(mParts) - 1];
  AMethodName := mParts[High(mParts)];
end;

/// <summary>Parameter des Kopfs AHeader als "name:typ:modifizierer" je Name, klein geschrieben.</summary>
function ParameterKeys(AHeader: TSyntaxNode): TArray<string>;
var
  mSection, mParameter, mType: TSyntaxNode;
  mIndex: Integer;
  mName, mTypeName: string;
begin
  Result := nil;
  if AHeader = nil then
    Exit;
  mSection := AHeader.FindChild(TSyntaxKind.Parameters);
  if mSection = nil then
    Exit;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    mParameter := mSection[mIndex];
    mType := mParameter.FindChild(TSyntaxKind.TypeReference);
    mTypeName := '';
    if mType <> nil then
      mTypeName := BareName(mType.Name);
    for mName in mParameter.Name.Split([',']) do
      Result := Result + [LowerCase(Trim(mName) + ':' + mTypeName + ':' + IntToStr(Ord(mParameter.Modifier)))];
  end;
end;

/// <summary>Namen der Parameter des Kopfs AHeader in Reihenfolge.</summary>
function ParameterNames(AHeader: TSyntaxNode): TArray<string>;
var
  mKey: string;
begin
  Result := nil;
  for mKey in ParameterKeys(AHeader) do
    Result := Result + [Copy(mKey, 1, Pos(':', mKey) - 1)];
end;

/// <summary>Hat ein Parameter des Kopfs AHeader einen Standardwert?</summary>
function HasDefaultValues(AHeader: TSyntaxNode): Boolean;
var
  mSection: TSyntaxNode;
  mIndex, mChild: Integer;
begin
  Result := False;
  mSection := AHeader.FindChild(TSyntaxKind.Parameters);
  if mSection <> nil then
    for mIndex := 0 to mSection.ChildCount - 1 do
      for mChild := 0 to mSection[mIndex].ChildCount - 1 do
        if mSection[mIndex][mChild].Kind <> TSyntaxKind.TypeReference then
          Exit(True);
end;

/// <summary>Rumpf der Methode AMethod aus ABodies; bei Überladungen der mit denselben Parametern. nil, wenn es
/// keinen eindeutigen gibt.</summary>
function BodyOf(const AMethod: TMethodDecl; const ABodies: TArray<TSyntaxNode>): TSyntaxNode;
var
  mBody: TSyntaxNode;
  mCandidates: TArray<TSyntaxNode>;
  mClassName, mMethodName: string;
  mKeys: TArray<string>;
begin
  Result := nil;
  mCandidates := nil;
  for mBody in ABodies do
  begin
    SplitMethodName(mBody.Name, mClassName, mMethodName);
    if SameText(mClassName, AMethod.ClassName) and SameText(mMethodName, AMethod.Symbol.Name) then
      mCandidates := mCandidates + [mBody];
  end;
  if Length(mCandidates) = 1 then
    Exit(mCandidates[0]);
  mKeys := ParameterKeys(AMethod.Header);
  for mBody in mCandidates do
    if string.Join(',', ParameterKeys(mBody.FindChild(TSyntaxKind.RoutineHeader))) = string.Join(',', mKeys) then
    begin
      if Result <> nil then
        Exit(nil);
      Result := mBody;
    end;
end;

/// <summary>Bereich des Methodennamens im Kopf AHeader ("TKlasse.Name"); sonst der ganze Kopf.</summary>
function MethodNameRange(const AContext: TRuleContext; AHeader: TSyntaxNode; const AName: string): TTextRange;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
  for mIndex := AContext.Tree.FirstTokenFrom(AHeader.StartOffset) to High(AContext.Tree.Tokens) do
  begin
    mToken := AContext.Tree.Tokens[mIndex];
    if mToken.Offset < AHeader.StartOffset then
      Continue;
    if (mToken.Offset >= AHeader.EndOffset) or mToken.IsSymbol('(') or mToken.IsSymbol(';') or
      mToken.IsSymbol(':') then
      Break;
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AName) then
      Result := TTextRange.Create(mToken.StartPos, mToken.EndPos);
  end;
end;

/// <summary>Steht zwischen AStart und AEnd ein Kommentar oder eine Direktive?</summary>
function HasCommentBetween(const AContext: TRuleContext; AStart, AEnd: Integer): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  for mIndex := AContext.Tree.FirstTokenFrom(AStart) to High(AContext.Tree.Tokens) do
  begin
    mToken := AContext.Tree.Tokens[mIndex];
    if mToken.Offset < AStart then
      Continue;
    if mToken.Offset >= AEnd then
      Break;
    if mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Exit(True);
  end;
  Result := False;
end;

{ TOverrideOnlyInheritedRule }

function TOverrideOnlyInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OverrideOnlyInheritedRuleId, TRuleSeverity.Hint,
    'override ruft nur inherited auf');
end;

/// <summary>Ruft AStatement nur die geerbte Methode AMethodName mit den Parametern AParams in ihrer Reihenfolge auf?
/// In Funktionen nur "Result := inherited Name(…)": ein bloßes inherited; verwirft dort das Ergebnis.</summary>
function OnlyInherited(AStatement: TSyntaxNode; const AMethodName: string; const AParams: TArray<string>;
  AFunction: Boolean): Boolean;
var
  mExpr: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  if AFunction then
  begin
    if (AStatement.Kind <> TSyntaxKind.AssignStatement) or (AStatement.ChildCount <> 2) or
      (AStatement[0].Kind <> TSyntaxKind.Identifier) or not SameText(AStatement[0].Name, 'Result') then
      Exit;
    mExpr := AStatement[1];
  end
  else
  begin
    if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
      Exit;
    mExpr := AStatement[0];
    // Ein bloßes inherited; übergibt die eigenen Parameter unverändert.
    if (mExpr.Kind = TSyntaxKind.InheritedExpr) and (mExpr.Name = '') then
      Exit(True);
  end;
  if mExpr.Kind = TSyntaxKind.InheritedExpr then
    Exit(SameText(mExpr.Name, AMethodName) and (Length(AParams) = 0));
  if (mExpr.Kind <> TSyntaxKind.Call) or (mExpr.ChildCount <> Length(AParams) + 1) or
    (mExpr[0].Kind <> TSyntaxKind.InheritedExpr) or not SameText(mExpr[0].Name, AMethodName) then
    Exit;
  for mIndex := 0 to High(AParams) do
    if (mExpr[mIndex + 1].Kind <> TSyntaxKind.Identifier) or not SameText(mExpr[mIndex + 1].Name, AParams[mIndex]) then
      Exit;
  Result := True;
end;

/// <summary>Steht vor dem Kopf in der Klasse ein Attribut ([Weak] procedure …)?</summary>
function HasAttribute(AHeader: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mParent := AHeader.Parent;
  if mParent = nil then
    Exit;
  for mIndex := 1 to mParent.ChildCount - 1 do
    if mParent[mIndex] = AHeader then
      Exit(mParent[mIndex - 1].Kind = TSyntaxKind.Attribute);
end;

procedure TOverrideOnlyInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  // Direktiven, mit denen das Überschreiben selbst etwas bewirkt.
  cMeaningful: array[0..5] of string = ('final', 'deprecated', 'experimental', 'platform', 'library', 'reintroduce');
var
  mCache: IRuleDerivedCache;
  mAncestry: TAncestry;
  mBodies: TArray<TSyntaxNode>;
  mMethod: TMethodDecl;
  mBody, mBlock, mHeader: TSyntaxNode;
  mDeclStart, mDeclEnd, mBodyStart, mBodyEnd: Integer;
  mDirective: string;
  mSkip: Boolean;
  mOverridden: TInherited;
  mVisibility: TIndexVisibility;
  mFixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'inherited') then
    Exit;
  mCache := TRuleDerived.Open(AContext);
  mBodies := MethodBodies(mCache, AContext);
  if mBodies = nil then
    Exit;
  mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(mCache, AContext));
  try
    for mMethod in ClassMethods(AContext, mAncestry) do
    begin
      if not mMethod.Has('override') or HasAttribute(mMethod.Header) or HasDefaultValues(mMethod.Header) then
        Continue;
      mSkip := False;
      for mDirective in cMeaningful do
        mSkip := mSkip or mMethod.Has(mDirective);
      if mSkip then
        Continue;
      mBody := BodyOf(mMethod, mBodies);
      if mBody = nil then
        Continue;
      // Nur Kopf und Rumpf: keine lokalen Variablen, Konstanten oder Routinen.
      mHeader := mBody.FindChild(TSyntaxKind.RoutineHeader);
      mBlock := mBody.FindChild(TSyntaxKind.Block);
      if (mHeader = nil) or (mBlock = nil) or (mBody.ChildCount <> 2) or (mBlock.ChildCount <> 1) or
        HasCommentBetween(AContext, mBlock.StartOffset, mBlock.EndOffset) or
        not OnlyInherited(mBlock[0], mMethod.Symbol.Name, ParameterNames(mMethod.Header),
        mMethod.Keyword = 'function') then
        Continue;
      // Eine geänderte Sichtbarkeit (protected -> public) ist der Zweck der Methode.
      mOverridden := mAncestry.InheritedVirtual(mMethod);
      if mOverridden.Found then
        mVisibility := mOverridden.Symbol.Visibility
      else if MatchText(mMethod.Symbol.Name, ObjectVirtualNames) then
        mVisibility := TIndexVisibility.Public
      else
        Continue;
      if mVisibility <> mMethod.Symbol.Visibility then
        Continue;
      mFixes := nil;
      if WholeLines(AContext.Text, mMethod.Header.StartOffset, mMethod.Header.EndOffset, True, False, mDeclStart,
        mDeclEnd) and WholeLines(AContext.Text, mBody.StartOffset, mBody.EndOffset, True, True, mBodyStart,
        mBodyEnd) then
        mFixes := [TRuleFix.Create('Methode entfernen', [
          TRuleEdit.Create(TRuleDerived.OffsetRange(mCache, AContext, mDeclStart, mDeclEnd), ''),
          TRuleEdit.Create(TRuleDerived.OffsetRange(mCache, AContext, mBodyStart, mBodyEnd), '')])];
      AReport.Add(MethodNameRange(AContext, mHeader, mMethod.Symbol.Name),
        Format('%s.%s ruft nur inherited auf und kann entfallen.', [mMethod.ClassName, mMethod.Symbol.Name]),
        TRuleConfidence.High, mFixes);
    end;
  finally
    mAncestry.Free;
  end;
end;

{ TInheritedWithoutAncestorRule }

function TInheritedWithoutAncestorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InheritedWithoutAncestorRuleId, TRuleSeverity.Hint,
    'inherited ohne Methode im Vorfahr');
end;

/// <summary>Anweisungen "inherited;" ohne Namen im Block ABlock, ohne anonyme Methoden.</summary>
function BareInheritedStatements(ABlock: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ABlock);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AnonymousMethod then
        Continue;
      if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount = 1) and
        (mNode[0].Kind = TSyntaxKind.InheritedExpr) and (mNode[0].Name = '') then
      begin
        Result := Result + [mNode];
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
    end;
  finally
    mPending.Free;
  end;
end;

procedure TInheritedWithoutAncestorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCache: IRuleDerivedCache;
  mAncestry: TAncestry;
  mBodies: TArray<TSyntaxNode>;

  /// <summary>Hat ein Vorfahr von AClassName ein Mitglied AName? True auch, wenn die Kette nicht bekannt ist.
  /// </summary>
  function AncestorKnows(const AClassName, AName: string): Boolean;
  var
    mChain: TArray<TSymbolLocation>;
    mLocation: TSymbolLocation;
    mMember: TIndexSymbol;
    mComplete, mObjectMissing: Boolean;
  begin
    mChain := mAncestry.Ancestors(AClassName, mComplete, mObjectMissing);
    if not mComplete then
      Exit(True);
    for mLocation in mChain do
      for mMember in mAncestry.Members(mLocation) do
        if SameText(mMember.Name, AName) then
          Exit(True);
    Result := mObjectMissing and (MatchText(AName, ObjectMethodNames) or MatchText(AName, ObjectVirtualNames));
  end;

var
  mMethod: TMethodDecl;
  mBody, mBlock, mStatement: TSyntaxNode;
  mClassName, mMethodName: string;
  mStatements: TArray<TSyntaxNode>;
  mFixes: TArray<TRuleFix>;
  mChecked: TDictionary<string, Boolean>;
  mKnown: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'inherited') then
    Exit;
  mCache := TRuleDerived.Open(AContext);
  mBodies := MethodBodies(mCache, AContext);
  if mBodies = nil then
    Exit;
  mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(mCache, AContext));
  mChecked := TDictionary<string, Boolean>.Create;
  try
    // ClassMethods lässt Klassenmethoden, statische Methoden und Message-Handler aus: Dort ruft inherited
    // DefaultHandler bzw. ist kein Fall.
    for mMethod in ClassMethods(AContext, mAncestry) do
    begin
      if (mMethod.Keyword = 'constructor') or (mMethod.Keyword = 'destructor') or mMethod.Has('override') or
        mMethod.Has('reintroduce') or mChecked.ContainsKey(LowerCase(mMethod.ClassName + '.' + mMethod.Symbol.Name)) then
        Continue;
      mChecked.Add(LowerCase(mMethod.ClassName + '.' + mMethod.Symbol.Name), True);
      mKnown := False;
      for mBody in mBodies do
      begin
        SplitMethodName(mBody.Name, mClassName, mMethodName);
        if not SameText(mClassName, mMethod.ClassName) or not SameText(mMethodName, mMethod.Symbol.Name) then
          Continue;
        mBlock := mBody.FindChild(TSyntaxKind.Block);
        if mBlock = nil then
          Continue;
        mStatements := BareInheritedStatements(mBlock);
        if mStatements = nil then
          Continue;
        // Erst bei einem Treffer die Vorfahren befragen.
        if not mKnown then
        begin
          if AncestorKnows(mMethod.ClassName, mMethod.Symbol.Name) then
            Break;
          mKnown := True;
        end;
        for mStatement in mStatements do
        begin
          mFixes := nil;
          if (mStatement.Parent <> nil) and (mStatement.Parent.Kind = TSyntaxKind.Block) then
            mFixes := [RemoveStatementFix(mCache, AContext, mStatement, 'inherited entfernen')];
          AReport.Add(TTextRange.Create(mStatement.StartPos, mStatement.EndPos),
            Format('Kein Vorfahr von %s hat %s: inherited tut nichts. Fehlt override?',
            [mMethod.ClassName, mMethod.Symbol.Name]), TRuleConfidence.High, mFixes);
        end;
      end;
    end;
  finally
    mChecked.Free;
    mAncestry.Free;
  end;
end;

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDestroyWithoutOverrideRule.Create);
  ARegistry.Register(TComponentCreateWithoutOverrideRule.Create);
  ARegistry.Register(THidesVirtualRule.Create);
  ARegistry.Register(TVirtualInsteadOfOverrideRule.Create);
  ARegistry.Register(TShadowedNameRule.Create);
  ARegistry.Register(TOverrideTargetMissingRule.Create);
  ARegistry.Register(TAbstractClassInstantiatedRule.Create);
  ARegistry.Register(TInheritedAbstractCallRule.Create);
  ARegistry.Register(TClassReferenceNonvirtualConstructorRule.Create);
  ARegistry.Register(TMemberHidesAncestorRule.Create);
  ARegistry.Register(TOverrideCaseMismatchRule.Create);
  ARegistry.Register(TOverrideOnlyInheritedRule.Create);
  ARegistry.Register(TInheritedWithoutAncestorRule.Create);
end;

end.
