unit Atlas.Common.Lsp.ImplementationSites;

// Umsetzungen einer virtuellen oder Interface-Methode (#2635), gemeinsam für „Gehe zu Implementierung“
// (TLspImplementations.Targets), die Zahl der Umsetzungen in der Aufrufhierarchie (#1122) und das
// MCP-Werkzeug find_implementations, damit alle drei dieselben Stellen sehen.
// - Virtuelle Methode: der eigene Rumpf (bei abstract die Deklaration) und jede Nachfahrenklasse, die die
//   Methode neu deklariert (override, reintroduce oder verdeckend).
// - Interface-Methode: je Klasse, die das Interface (auch über dessen Nachfahren) umsetzt,
//   - die gleichnamige Methode,
//   - die Methodenzuordnung „procedure IFoo.Bar = MyBar“ (TIndexSymbol.Resolutions),
//   - die Delegation „property … implements IFoo“: die Methode in der Klasse des Feldes; bei einem Feld vom
//     Typ eines Interfaces ist die Umsetzung statisch unbekannt, dann die Property selbst,
//   - sonst die geerbte Methode eines Klassenvorfahren, wenn die Klasse das Interface selbst nennt.
//   Nachfahren einer umsetzenden Klasse zählen nur, wenn sie die Methode neu deklarieren.
// Dieselbe Stelle über zwei Wege zählt einmal.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

{$SCOPEDENUMS ON}

type
  /// <summary>Wie eine Klasse die Methode umsetzt.</summary>
  TImplementationKind = (
    /// <summary>Rumpf der virtuellen Methode selbst.</summary>
    Own,
    /// <summary>Gleichnamige Methode einer Klasse, die das Interface umsetzt.</summary>
    Implements,
    /// <summary>override in einer Nachfahrenklasse.</summary>
    Overrides,
    /// <summary>Deklaration mit abstract, ohne Rumpf.</summary>
    Abstract_,
    /// <summary>reintroduce in einer Nachfahrenklasse.</summary>
    Reintroduces,
    /// <summary>Gleichnamige Methode ohne override: verdeckt die Methode des Vorfahren.</summary>
    Hides,
    /// <summary>Methodenzuordnung procedure IFoo.Bar = MyBar.</summary>
    Mapped,
    /// <summary>Methode eines Klassenvorfahren, die Klasse nennt das Interface selbst.</summary>
    Inherited_,
    /// <summary>property … implements IFoo mit einem Feld vom Typ einer Klasse: deren Methode.</summary>
    Delegated,
    /// <summary>property … implements IFoo mit einem Feld vom Typ eines Interfaces: Umsetzung unbekannt.</summary>
    DelegatedToField);

  TImplementationSite = record
    /// <summary>Klasse, die die Methode umsetzt (bei Delegated die Klasse mit der Property).</summary>
    TypeName: string;
    /// <summary>Klasse, in der die Methode steht; bei Delegated und Inherited_ eine andere als TypeName.</summary>
    DeclaringType: string;
    /// <summary>Name der Methode dort, bei Mapped abweichend vom Namen im Interface; bei DelegatedToField die
    /// Property.</summary>
    MethodName: string;
    Kind: TImplementationKind;
    /// <summary>Property bei Delegated und DelegatedToField; sonst ''.</summary>
    Via: string;
    UnitName: string;
    FileName: string;
    /// <summary>Rumpf, ohne Rumpf die Deklaration (bei DelegatedToField die Property).</summary>
    Range: TTextRange;
    SelectionRange: TTextRange;
    HasBody: Boolean;
  end;

  /// <summary>Unit der Datei AFileName; für den Editor die Datei aus dem Editor statt aus dem Index.</summary>
  TImplementationUnitFunc = reference to function(const AFileName: string; out AUnit: TUnitIndex): Boolean;

  TImplementationSites = class
  public const
    cMaxSites = 500;
  public
    /// <summary>Umsetzungen der Methode AName von AContainer (siehe Kopf der Unit), in der Reihenfolge der
    /// Vererbung. AInterface: AContainer ist ein Interface. AUnitOf = nil liest alle Units aus dem Index.
    /// </summary>
    class function Find(const AIndex: ISymbolIndex; const AUnitOf: TImplementationUnitFunc;
      const AContainer, AName: string; AInterface: Boolean): TArray<TImplementationSite>; overload; static;
    /// <summary>Wie oben; den eigenen Rumpf der virtuellen Methode sucht es in AOwnerFile (Datei der Deklaration,
    /// auch eine nur im Editor geöffnete), '' = über den Index.</summary>
    class function Find(const AIndex: ISymbolIndex; const AUnitOf: TImplementationUnitFunc;
      const AContainer, AName, AOwnerFile: string; AInterface: Boolean): TArray<TImplementationSite>; overload;
      static;
    /// <summary>Alle Nachfahren von ATypeName über alle Stufen, Kreise erkannt.</summary>
    class function AllDescendants(const AIndex: ISymbolIndex; const ATypeName: string): TArray<TSymbolLocation>;
      static;
    /// <summary>Name der Art für JSON: own, implements, overrides, abstract …</summary>
    class function KindName(AKind: TImplementationKind): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections;

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  cClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  cMaxDepth = 32;
  cKindNames: array[TImplementationKind] of string = ('own', 'implements', 'overrides', 'abstract', 'reintroduces',
    'hides', 'mapped', 'inherited', 'delegated', 'delegatedToField');

type
  /// <summary>Gefundene Methode einer Klasse: Deklaration und, wenn vorhanden, Rumpf.</summary>
  TFoundMethod = record
    UnitIndex: TUnitIndex;
    Declaration: TIndexSymbol;
    Body: TIndexSymbol;
    HasBody: Boolean;
  end;

  /// <summary>Eine Suche nach Umsetzungen mit Liste und Doppelten-Erkennung.</summary>
  TSiteSearch = class
  private
    FIndex: ISymbolIndex;
    FUnitOf: TImplementationUnitFunc;
    FContainer: string;
    FName: string;
    FOwnerFile: string;
    FSites: TList<TImplementationSite>;
    FSeen: TDictionary<string, Boolean>;
    function UnitOf(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindMethod(const AUnit: TUnitIndex; const ATypeName, AName: string; out AFound: TFoundMethod): Boolean;
    function FindType(const ATypeName: string; out AUnit: TUnitIndex; out AType: TIndexSymbol): Boolean;
    function Extends(const AInterface: string): Boolean;
    function NamesInterface(const AType: TIndexSymbol): Boolean;
    function MappedName(const AType: TIndexSymbol; out AName: string): Boolean;
    procedure Add(const AFound: TFoundMethod; const ATypeName: string; AKind: TImplementationKind;
      const AVia: string);
    procedure AddProperty(const AUnit: TUnitIndex; const AProperty: TIndexSymbol; const ATypeName: string);
    function AddInherited(const AType: TIndexSymbol): Boolean;
    function DelegatesInterface(const AProperty: TIndexSymbol): Boolean;
    function AddDelegated(const AUnit: TUnitIndex; const AType: TIndexSymbol): Boolean;
    procedure AddOwn;
    procedure AddVirtualIn(const ALocation: TSymbolLocation);
    procedure AddInterfaceIn(const ALocation: TSymbolLocation);
  public
    constructor Create(const AIndex: ISymbolIndex; const AUnitOf: TImplementationUnitFunc;
      const AContainer, AName, AOwnerFile: string);
    destructor Destroy; override;
    function Run(AInterface: Boolean): TArray<TImplementationSite>;
  end;

/// <summary>Name ohne Typargumente und ohne Unit-Präfix: "Unit.IList&lt;T&gt;" → "IList".</summary>
function ShortTypeName(const AName: string): string;
var
  mAt: Integer;
begin
  Result := AName;
  mAt := Pos('<', Result);
  if mAt > 0 then
  begin
    Result := Copy(Result, 1, mAt - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt).Trim;
end;

/// <summary>Kind der Deklaration ADeclaration in einer Nachfahrenklasse: abstract, override, reintroduce oder
/// verdeckend.</summary>
function RedeclarationKind(const ADeclaration: TIndexSymbol): TImplementationKind;
begin
  if ADeclaration.HasDirective('abstract') then
  begin
    Result := TImplementationKind.Abstract_;
  end
  else if ADeclaration.HasDirective('override') then
  begin
    Result := TImplementationKind.Overrides;
  end
  else if ADeclaration.HasDirective('reintroduce') then
  begin
    Result := TImplementationKind.Reintroduces;
  end
  else
  begin
    Result := TImplementationKind.Hides;
  end;
end;

{ TSiteSearch }

constructor TSiteSearch.Create(const AIndex: ISymbolIndex; const AUnitOf: TImplementationUnitFunc;
  const AContainer, AName, AOwnerFile: string);
begin
  inherited Create;
  FIndex := AIndex;
  FUnitOf := AUnitOf;
  FContainer := AContainer;
  FName := AName;
  FOwnerFile := AOwnerFile;
  FSites := TList<TImplementationSite>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TSiteSearch.Destroy;
begin
  FSeen.Free;
  FSites.Free;
  inherited;
end;

function TSiteSearch.UnitOf(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  if Assigned(FUnitOf) then
  begin
    Result := FUnitOf(AFileName, AUnit);
  end
  else
  begin
    Result := FIndex.FindFile(AFileName, AUnit);
  end;
end;

function TSiteSearch.FindMethod(const AUnit: TUnitIndex; const ATypeName, AName: string;
  out AFound: TFoundMethod): Boolean;
var
  mSymbol: TIndexSymbol;
  mCount: Integer;
begin
  // Erste Fundstelle ist die Deklaration in der Klasse, die letzte bei mehr als einer der Rumpf.
  AFound := Default(TFoundMethod);
  AFound.UnitIndex := AUnit;
  mCount := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, ATypeName) and SameText(mSymbol.Name, AName)
    then
    begin
      if mCount = 0 then
      begin
        AFound.Declaration := mSymbol;
      end;
      AFound.Body := mSymbol;
      Inc(mCount);
    end;
  end;
  AFound.HasBody := mCount >= 2;
  Result := mCount > 0;
end;

function TSiteSearch.FindType(const ATypeName: string; out AUnit: TUnitIndex; out AType: TIndexSymbol): Boolean;
var
  mLocation: TSymbolLocation;
  mShort: string;
begin
  mShort := ShortTypeName(ATypeName);
  for mLocation in FIndex.FindSymbols(mShort) do
  begin
    if (mLocation.Symbol.Kind in cTypeKinds) and SameText(ShortTypeName(mLocation.Symbol.QualifiedName), mShort) and
      UnitOf(mLocation.FileName, AUnit) then
    begin
      AType := mLocation.Symbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ist AInterface das gesuchte Interface oder einer seiner Nachfahren?</summary>
function TSiteSearch.Extends(const AInterface: string): Boolean;
var
  mUnit: TUnitIndex;
  mType: TIndexSymbol;
  mCurrent: string;
  mDepth: Integer;
begin
  mCurrent := AInterface;
  for mDepth := 0 to cMaxDepth do
  begin
    if SameText(ShortTypeName(mCurrent), ShortTypeName(FContainer)) then
    begin
      Exit(True);
    end;
    if not (FindType(mCurrent, mUnit, mType) and (mType.Kind = TIndexSymbolKind.InterfaceType) and
      (Length(mType.Ancestors) > 0)) then
    begin
      Break;
    end;
    mCurrent := mType.Ancestors[0];
  end;
  Result := False;
end;

/// <summary>Nennt die Klasse AType das gesuchte Interface (oder einen Nachfahren) in ihrer Vorfahrenliste?
/// </summary>
function TSiteSearch.NamesInterface(const AType: TIndexSymbol): Boolean;
var
  mAncestor: string;
begin
  for mAncestor in AType.Ancestors do
  begin
    if Extends(mAncestor) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Methodenzuordnung "IFoo.Bar=MyBar" der Klasse AType für die gesuchte Methode.</summary>
function TSiteSearch.MappedName(const AType: TIndexSymbol; out AName: string): Boolean;
var
  mResolution, mLeft: string;
  mAt: Integer;
begin
  for mResolution in AType.Resolutions do
  begin
    mAt := Pos('=', mResolution);
    mLeft := Trim(Copy(mResolution, 1, mAt - 1));
    if (mAt > 0) and SameText(Copy(mLeft, LastDelimiter('.', mLeft) + 1, MaxInt), FName) and
      Extends(Copy(mLeft, 1, LastDelimiter('.', mLeft) - 1)) then
    begin
      AName := Trim(Copy(mResolution, mAt + 1, MaxInt));
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSiteSearch.Add(const AFound: TFoundMethod; const ATypeName: string; AKind: TImplementationKind;
  const AVia: string);
var
  mSite: TImplementationSite;
  mSymbol: TIndexSymbol;
  mKey: string;
begin
  mSymbol := AFound.Declaration;
  if AFound.HasBody then
  begin
    mSymbol := AFound.Body;
  end;
  mKey := UpperCase(AFound.UnitIndex.FileName) + '|' + IntToStr(mSymbol.SelectionRange.StartPos.Line) + '|' +
    IntToStr(mSymbol.SelectionRange.StartPos.Character);
  if FSeen.ContainsKey(mKey) or (FSites.Count >= TImplementationSites.cMaxSites) then
  begin
    Exit;
  end;
  FSeen.Add(mKey, True);
  mSite := Default(TImplementationSite);
  mSite.TypeName := ATypeName;
  mSite.DeclaringType := mSymbol.Container;
  mSite.MethodName := mSymbol.Name;
  mSite.Kind := AKind;
  if AFound.Declaration.HasDirective('abstract') then
  begin
    mSite.Kind := TImplementationKind.Abstract_;
  end;
  mSite.Via := AVia;
  mSite.UnitName := AFound.UnitIndex.UnitName;
  mSite.FileName := AFound.UnitIndex.FileName;
  mSite.Range := mSymbol.Range;
  mSite.SelectionRange := mSymbol.SelectionRange;
  mSite.HasBody := AFound.HasBody;
  FSites.Add(mSite);
end;

procedure TSiteSearch.AddProperty(const AUnit: TUnitIndex; const AProperty: TIndexSymbol; const ATypeName: string);
var
  mFound: TFoundMethod;
begin
  mFound := Default(TFoundMethod);
  mFound.UnitIndex := AUnit;
  mFound.Declaration := AProperty;
  Add(mFound, ATypeName, TImplementationKind.DelegatedToField, AProperty.Name);
end;

/// <summary>Methode eines Klassenvorfahren von AType, wenn die Klasse das Interface selbst nennt.</summary>
function TSiteSearch.AddInherited(const AType: TIndexSymbol): Boolean;
var
  mUnit: TUnitIndex;
  mAncestor: TIndexSymbol;
  mFound: TFoundMethod;
  mCurrent: string;
  mDepth: Integer;
begin
  Result := False;
  if not NamesInterface(AType) or (Length(AType.Ancestors) = 0) then
  begin
    Exit;
  end;
  mCurrent := AType.Ancestors[0];
  for mDepth := 1 to cMaxDepth do
  begin
    if not (FindType(mCurrent, mUnit, mAncestor) and (mAncestor.Kind in cClassKinds)) then
    begin
      Exit;
    end;
    if FindMethod(mUnit, mAncestor.QualifiedName, FName, mFound) then
    begin
      Add(mFound, AType.QualifiedName, TImplementationKind.Inherited_, '');
      Exit(True);
    end;
    if Length(mAncestor.Ancestors) = 0 then
    begin
      Exit;
    end;
    mCurrent := mAncestor.Ancestors[0];
  end;
end;

/// <summary>Nennt die Property AProperty mit "implements" das gesuchte Interface (oder einen Nachfahren)?
/// </summary>
function TSiteSearch.DelegatesInterface(const AProperty: TIndexSymbol): Boolean;
var
  mMatch: TMatch;
  mInterface: string;
begin
  Result := False;
  mMatch := TRegEx.Match(AProperty.Signature, '\bimplements\s+([^;]+)', [TRegExOption.roIgnoreCase]);
  if mMatch.Success then
  begin
    for mInterface in mMatch.Groups[1].Value.Split([',']) do
    begin
      if Extends(Trim(mInterface)) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>Delegation über "property … implements IFoo" in AType.</summary>
function TSiteSearch.AddDelegated(const AUnit: TUnitIndex; const AType: TIndexSymbol): Boolean;
var
  mSymbol, mFieldType: TIndexSymbol;
  mTypeUnit: TUnitIndex;
  mFound: TFoundMethod;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Property_) and SameText(mSymbol.Container, AType.QualifiedName) and
      DelegatesInterface(mSymbol) then
    begin
      // Feld vom Typ einer Klasse: deren Methode; vom Typ eines Interfaces: statisch unbekannt.
      if FindType(mSymbol.TypeName, mTypeUnit, mFieldType) and (mFieldType.Kind in cClassKinds) and
        FindMethod(mTypeUnit, mFieldType.QualifiedName, FName, mFound) then
      begin
        Add(mFound, AType.QualifiedName, TImplementationKind.Delegated, mSymbol.Name);
      end
      else
      begin
        AddProperty(AUnit, mSymbol, AType.QualifiedName);
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSiteSearch.AddOwn;
var
  mUnit: TUnitIndex;
  mType: TIndexSymbol;
  mFound: TFoundMethod;
begin
  if FOwnerFile <> '' then
  begin
    if UnitOf(FOwnerFile, mUnit) and FindMethod(mUnit, FContainer, FName, mFound) then
    begin
      Add(mFound, FContainer, TImplementationKind.Own, '');
    end;
  end
  else if FindType(FContainer, mUnit, mType) and FindMethod(mUnit, mType.QualifiedName, FName, mFound) then
  begin
    Add(mFound, mType.QualifiedName, TImplementationKind.Own, '');
  end;
end;

procedure TSiteSearch.AddVirtualIn(const ALocation: TSymbolLocation);
var
  mUnit: TUnitIndex;
  mFound: TFoundMethod;
begin
  if UnitOf(ALocation.FileName, mUnit) and FindMethod(mUnit, ALocation.Symbol.QualifiedName, FName, mFound) then
  begin
    Add(mFound, ALocation.Symbol.QualifiedName, RedeclarationKind(mFound.Declaration), '');
  end;
end;

procedure TSiteSearch.AddInterfaceIn(const ALocation: TSymbolLocation);
var
  mUnit: TUnitIndex;
  mFound: TFoundMethod;
  mMapped: string;
  mKind: TImplementationKind;
begin
  if not UnitOf(ALocation.FileName, mUnit) then
  begin
    Exit;
  end;
  if MappedName(ALocation.Symbol, mMapped) then
  begin
    if FindMethod(mUnit, ALocation.Symbol.QualifiedName, mMapped, mFound) then
    begin
      Add(mFound, ALocation.Symbol.QualifiedName, TImplementationKind.Mapped, '');
    end;
    Exit;
  end;
  if FindMethod(mUnit, ALocation.Symbol.QualifiedName, FName, mFound) then
  begin
    // Nennt die Klasse das Interface, setzt sie es um; sonst überschreibt bzw. verdeckt sie die Umsetzung
    // eines Vorfahren.
    mKind := TImplementationKind.Implements;
    if not NamesInterface(ALocation.Symbol) then
    begin
      mKind := RedeclarationKind(mFound.Declaration);
    end;
    Add(mFound, ALocation.Symbol.QualifiedName, mKind, '');
    Exit;
  end;
  if not AddDelegated(mUnit, ALocation.Symbol) then
  begin
    AddInherited(ALocation.Symbol);
  end;
end;

function TSiteSearch.Run(AInterface: Boolean): TArray<TImplementationSite>;
var
  mLocation: TSymbolLocation;
begin
  if not AInterface then
  begin
    AddOwn;
  end;
  for mLocation in TImplementationSites.AllDescendants(FIndex, FContainer) do
  begin
    if not (mLocation.Symbol.Kind in cClassKinds) then
    begin
      Continue;
    end;
    if AInterface then
    begin
      AddInterfaceIn(mLocation);
    end
    else
    begin
      AddVirtualIn(mLocation);
    end;
  end;
  Result := FSites.ToArray;
end;

{ TImplementationSites }

class function TImplementationSites.Find(const AIndex: ISymbolIndex; const AUnitOf: TImplementationUnitFunc;
  const AContainer, AName: string; AInterface: Boolean): TArray<TImplementationSite>;
begin
  Result := Find(AIndex, AUnitOf, AContainer, AName, '', AInterface);
end;

class function TImplementationSites.Find(const AIndex: ISymbolIndex; const AUnitOf: TImplementationUnitFunc;
  const AContainer, AName, AOwnerFile: string; AInterface: Boolean): TArray<TImplementationSite>;
var
  mSearch: TSiteSearch;
begin
  Result := nil;
  if (AIndex = nil) or (AContainer = '') then
  begin
    Exit;
  end;
  mSearch := TSiteSearch.Create(AIndex, AUnitOf, AContainer, AName, AOwnerFile);
  try
    Result := mSearch.Run(AInterface);
  finally
    mSearch.Free;
  end;
end;

class function TImplementationSites.AllDescendants(const AIndex: ISymbolIndex;
  const ATypeName: string): TArray<TSymbolLocation>;
var
  mPending: TQueue<TPair<string, Integer>>;
  mSeen: TDictionary<string, Boolean>;
  mCurrent: TPair<string, Integer>;
  mLocation: TSymbolLocation;
  mKey: string;
begin
  Result := nil;
  mPending := TQueue<TPair<string, Integer>>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mPending.Enqueue(TPair<string, Integer>.Create(ATypeName, 0));
    while mPending.Count > 0 do
    begin
      mCurrent := mPending.Dequeue;
      if mCurrent.Value >= cMaxDepth then
      begin
        Continue;
      end;
      for mLocation in AIndex.Descendants(mCurrent.Key) do
      begin
        if not (mLocation.Symbol.Kind in cTypeKinds) then
        begin
          Continue;
        end;
        mKey := UpperCase(mLocation.FileName + '|' + mLocation.Symbol.QualifiedName);
        if mSeen.ContainsKey(mKey) then
        begin
          Continue;
        end;
        mSeen.Add(mKey, True);
        Result := Result + [mLocation];
        mPending.Enqueue(TPair<string, Integer>.Create(mLocation.Symbol.QualifiedName, mCurrent.Value + 1));
      end;
    end;
  finally
    mSeen.Free;
    mPending.Free;
  end;
end;

class function TImplementationSites.KindName(AKind: TImplementationKind): string;
begin
  Result := cKindNames[AKind];
end;

end.
