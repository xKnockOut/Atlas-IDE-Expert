unit Atlas.Common.Semantics.NameResolver.InterfaceMembers;

// Fehlende Interface-Methoden einer Klasse: Methoden der Interfaces aus der Vorfahrenliste (samt deren Vorfahren),
// die weder die Klasse noch eine Vorfahrklasse implementiert, nicht per Zuordnung (procedure IFoo.Bar = Baz) und
// nicht über ein delegiertes Interface (implements). Signaturen werden ohne Unit-Präfixe verglichen (#466).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Expressions;

type
  /// <summary>Typtexte ohne Unit-Präfixe: "System.Classes.TList" → "TList".</summary>
  TResolverUnqualify = class
  public
    /// <summary>AText mit jedem Bezeichner ohne Unit-Präfix (Units aus AIndex oder AOwnUnit).</summary>
    class function TypeText(const AIndex: ISymbolIndex; const AText, AOwnUnit: string): string; static;
    /// <summary>Punktkette AChain ohne das längste Präfix, das eine Unit ist.</summary>
    class function Chain(const AIndex: ISymbolIndex; const AChain, AOwnUnit: string): string; static;
  end;

  /// <summary>Sammelt für einen Aufruf die fehlenden Interface-Methoden einer Klasse.</summary>
  TResolverInterfaceMembers = class
  private
    FParts: TResolverParts;
    FOwnUnitName: string;
    // Signaturschlüssel implementierter Methoden, Namen von Methoden der RTL-Basis ohne Index, Zuordnungen
    // ("ifoo.bar"), schon besuchte und delegierte Interfaces.
    FImplemented: TDictionary<string, Boolean>;
    FByName: TDictionary<string, Boolean>;
    FResolutions: TDictionary<string, Boolean>;
    FSeenInterfaces: TDictionary<string, Boolean>;
    FDelegated: TDictionary<string, Boolean>;
    FList: TList<TResolvedSymbol>;
    FComplete: Boolean;
    function Unqualified(const ABindings: TArray<string>): TArray<string>;
    function KeyOf(const ASymbol: TIndexSymbol; const ABindings: TArray<string>): string;
    function AddRoot(const ABase: string): Boolean;
    procedure AddDelegated(const AName: string; const AUnit: TUnitIndex);
    procedure AddResolutions(const ASymbol: TIndexSymbol);
    procedure CollectClassLevel(const AClass: TResolvedSymbol; const AUnit: TUnitIndex);
    procedure CloseChain(const AClass: TResolvedSymbol);
    procedure CollectImplemented(const AOwn: TResolvedSymbol);
    function EnterInterface(const AIntf: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    function IsCovered(const AKey: string; const AIntf: TResolvedSymbol; const ASymbol: TIndexSymbol): Boolean;
    procedure CollectInterfaceLevel(const AIntf: TResolvedSymbol; const AUnit: TUnitIndex);
    procedure CollectInterface(const AName: string; const AOwnerUnit: TUnitIndex);
  public
    constructor Create(const AParts: TResolverParts; const AOwnUnitName: string);
    destructor Destroy; override;
    /// <summary>Fehlende Methoden der Klasse AOwn aus AOwnerUnit. AAncestors: Vorfahrenliste (leer = die von AOwn),
    /// ADelegated: per implements übernommene Interfaces; AComplete: Die Klassenkette war ganz bekannt.</summary>
    function Collect(const AOwn: TResolvedSymbol; const AOwnerUnit: TUnitIndex;
      const AAncestors, ADelegated: TArray<string>; out AComplete: Boolean): TArray<TResolvedSymbol>;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  // Öffentliche Methoden von TObject: Sie können Interface-Methoden gleichen Namens implementieren.
  cObjectMethods: array[0..29] of string = ('Free', 'DisposeOf', 'ClassType', 'ClassName', 'ClassNameIs',
    'ClassParent', 'ClassInfo', 'InstanceSize', 'InheritsFrom', 'MethodAddress', 'MethodName', 'QualifiedClassName',
    'FieldAddress', 'GetInterface', 'GetInterfaceEntry', 'GetInterfaceTable', 'UnitName', 'UnitScope', 'Equals',
    'GetHashCode', 'ToString', 'SafeCallException', 'AfterConstruction', 'BeforeDestruction', 'Dispatch',
    'DefaultHandler', 'NewInstance', 'FreeInstance', 'Destroy', 'InitInstance');
  // RTL-Basen, die IInterface implementieren; ohne Index gelten sie als Wurzel der Kette.
  cInterfacedRoots: array[0..4] of string = ('TInterfacedObject', 'TAggregatedObject', 'TContainedObject',
    'TSingletonImplementation', 'TNoRefCountObject');
  cInterfaceMethods: array[0..2] of string = ('QueryInterface', '_AddRef', '_Release');
  cIdentifierStart: TSysCharSet = ['A'..'Z', 'a'..'z', '_', '&'];
  cIdentifierChars: TSysCharSet = ['A'..'Z', 'a'..'z', '_', '0'..'9', '.', '&'];

/// <summary>Name und Parametertypen ohne Unit-Präfix, für den Vergleich von Methodensignaturen (#466).</summary>
function SignatureKey(const AName: string; const AParamTypes: TArray<string>): string;
var
  mIndex: Integer;
  mTypeText: string;
begin
  Result := UpperCase(AName) + '(';
  for mIndex := 0 to High(AParamTypes) do
  begin
    mTypeText := AParamTypes[mIndex];
    if Pos('<', mTypeText) = 0 then
    begin
      mTypeText := TResolverText.LastPart(mTypeText);
    end;
    if mIndex > 0 then
    begin
      Result := Result + ';';
    end;
    Result := Result + UpperCase(mTypeText);
  end;
  Result := Result + ')';
end;

/// <summary>Interfaces, deren Methoden fehlen können: AAncestors, sonst die Vorfahren von AOwn mit eingesetzten
/// Typargumenten. Erst sie binden die Typparameter des Interfaces (IComparer&lt;TKunde&gt;: T=TKunde), sonst
/// weichen alle Köpfe mit T ab.</summary>
function InterfaceNames(const AOwn: TResolvedSymbol; const AAncestors: TArray<string>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := AAncestors;
  if Length(Result) > 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AOwn.Ancestors) do
  begin
    Result := Result + [TResolverText.Substitute(AOwn.AncestorText(mIndex), AOwn.Bindings)];
  end;
end;

/// <summary>Trägt alle Namen aus ANames klein geschrieben in ATarget ein.</summary>
procedure AddNames(ATarget: TDictionary<string, Boolean>; const ANames: array of string);
var
  mName: string;
begin
  for mName in ANames do
  begin
    ATarget.AddOrSetValue(LowerCase(mName), True);
  end;
end;

{ TResolverUnqualify }

class function TResolverUnqualify.TypeText(const AIndex: ISymbolIndex; const AText, AOwnUnit: string): string;
var
  mIndex, mStart: Integer;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if CharInSet(AText[mIndex], cIdentifierStart) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], cIdentifierChars) do
      begin
        Inc(mIndex);
      end;
      Result := Result + Chain(AIndex, Copy(AText, mStart, mIndex - mStart), AOwnUnit);
    end
    else
    begin
      Result := Result + AText[mIndex];
      Inc(mIndex);
    end;
  end;
end;

class function TResolverUnqualify.Chain(const AIndex: ISymbolIndex; const AChain, AOwnUnit: string): string;
var
  mDot: Integer;
  mPrefix: string;
  mUnit: TUnitIndex;
begin
  // Längstes Präfix, das eine Unit ist, entfernen.
  mDot := LastDelimiter('.', AChain);
  while mDot > 0 do
  begin
    mPrefix := Copy(AChain, 1, mDot - 1);
    if ((AOwnUnit <> '') and SameText(mPrefix, AOwnUnit)) or ((AIndex <> nil) and AIndex.FindUnit(mPrefix, mUnit)) then
    begin
      Exit(Copy(AChain, mDot + 1, MaxInt));
    end;
    mDot := LastDelimiter('.', mPrefix);
  end;
  Result := AChain;
end;

{ TResolverInterfaceMembers }

constructor TResolverInterfaceMembers.Create(const AParts: TResolverParts; const AOwnUnitName: string);
begin
  inherited Create;
  FParts := AParts;
  FOwnUnitName := AOwnUnitName;
  FImplemented := TDictionary<string, Boolean>.Create;
  FByName := TDictionary<string, Boolean>.Create;
  FResolutions := TDictionary<string, Boolean>.Create;
  FSeenInterfaces := TDictionary<string, Boolean>.Create;
  FDelegated := TDictionary<string, Boolean>.Create;
  FList := TList<TResolvedSymbol>.Create;
end;

destructor TResolverInterfaceMembers.Destroy;
begin
  FList.Free;
  FDelegated.Free;
  FSeenInterfaces.Free;
  FResolutions.Free;
  FByName.Free;
  FImplemented.Free;
  inherited;
end;

function TResolverInterfaceMembers.Unqualified(const ABindings: TArray<string>): TArray<string>;
var
  mIndex, mEqual: Integer;
begin
  Result := Copy(ABindings);
  for mIndex := 0 to High(Result) do
  begin
    mEqual := Pos('=', Result[mIndex]);
    // Auch die eigene Unit, falls sie (noch) nicht im Index steht.
    Result[mIndex] := Copy(Result[mIndex], 1, mEqual) +
      TResolverUnqualify.TypeText(FParts.Place.Index, Copy(Result[mIndex], mEqual + 1, MaxInt), FOwnUnitName);
  end;
end;

function TResolverInterfaceMembers.KeyOf(const ASymbol: TIndexSymbol; const ABindings: TArray<string>): string;
var
  mTypes: TArray<string>;
  mIndex: Integer;
begin
  // Signaturschlüssel mit eingesetzten Typargumenten.
  mTypes := Copy(ASymbol.ParamTypes);
  for mIndex := 0 to High(mTypes) do
  begin
    mTypes[mIndex] := TResolverUnqualify.TypeText(FParts.Place.Index,
      TResolverText.Substitute(mTypes[mIndex], ABindings), '');
  end;
  Result := SignatureKey(ASymbol.Name, mTypes);
end;

function TResolverInterfaceMembers.AddRoot(const ABase: string): Boolean;
var
  mInterfaced: Boolean;
begin
  // Methoden einer RTL-Basis ohne Index nach Namen; False, wenn ABase keine bekannte Wurzel ist.
  mInterfaced := (ABase <> '') and MatchText(TResolverText.BareTypeName(ABase), cInterfacedRoots);
  Result := (ABase = '') or SameText(TResolverText.BareTypeName(ABase), 'TObject') or mInterfaced;
  if not Result then
  begin
    Exit;
  end;
  AddNames(FByName, cObjectMethods);
  if mInterfaced then
  begin
    AddNames(FByName, cInterfaceMethods);
  end;
end;

procedure TResolverInterfaceMembers.AddDelegated(const AName: string; const AUnit: TUnitIndex);
var
  mDelegate, mParent: TResolvedSymbol;
  mLevel: Integer;
begin
  // Interface AName und seine Vorfahren als übernommen eintragen.
  FDelegated.AddOrSetValue(UpperCase(TResolverText.BareTypeName(AName)), True);
  if not FParts.Lookup.ResolveTypeText(AName, AUnit, True, mDelegate) then
  begin
    Exit;
  end;
  for mLevel := 0 to cMaxDepth do
  begin
    FDelegated.AddOrSetValue(UpperCase(mDelegate.Name), True);
    if not FParts.Typing.AncestorOf(mDelegate, mParent) or (mParent.SymbolKind <> TIndexSymbolKind.InterfaceType) then
    begin
      Break;
    end;
    mDelegate := mParent;
  end;
end;

procedure TResolverInterfaceMembers.AddResolutions(const ASymbol: TIndexSymbol);
var
  mName, mKey: string;
  mDot: Integer;
begin
  for mName in ASymbol.Resolutions do
  begin
    // "IFoo.Bar=Baz": Schlüssel ifoo.bar ohne Unit-Präfix vor IFoo.
    mKey := Copy(mName, 1, Pos('=', mName) - 1);
    mDot := LastDelimiter('.', mKey);
    FResolutions.AddOrSetValue(LowerCase(TResolverText.BareTypeName(Copy(mKey, 1, mDot - 1)) +
      Copy(mKey, mDot, MaxInt)), True);
  end;
end;

procedure TResolverInterfaceMembers.CollectClassLevel(const AClass: TResolvedSymbol; const AUnit: TUnitIndex);
var
  mBindings: TArray<string>;
  mSymbol: TIndexSymbol;
begin
  // Methoden der Klasse, dazu Zuordnungen "IFoo.Bar = Baz".
  mBindings := Unqualified(AClass.Bindings);
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Container, AClass.QualifiedName) and (mSymbol.Kind in cRoutineKinds) then
    begin
      FImplemented.AddOrSetValue(KeyOf(mSymbol, mBindings), True);
    end
    else if SameText(mSymbol.QualifiedName, AClass.QualifiedName) then
    begin
      AddResolutions(mSymbol);
    end;
  end;
end;

procedure TResolverInterfaceMembers.CloseChain(const AClass: TResolvedSymbol);
var
  mParent: string;
  mAncestor: TResolvedSymbol;
begin
  // Kette zu Ende: ohne Vorfahr bzw. nur mit Interfaces gilt TObject, sonst eine bekannte RTL-Basis.
  mParent := '';
  if (Length(AClass.Ancestors) > 0) and not (FParts.Typing.AncestorOf(AClass, mAncestor) and
    (mAncestor.SymbolKind = TIndexSymbolKind.InterfaceType)) then
  begin
    mParent := AClass.Ancestors[0];
  end;
  if not AddRoot(mParent) then
  begin
    FComplete := False;
  end;
end;

procedure TResolverInterfaceMembers.CollectImplemented(const AOwn: TResolvedSymbol);
var
  mCurrent, mAncestor: TResolvedSymbol;
  mUnit: TUnitIndex;
  mDepth: Integer;
begin
  // Methoden der Klasse und ihrer Vorfahrklassen.
  mCurrent := AOwn;
  for mDepth := 0 to cMaxDepth do
  begin
    if (mCurrent.SymbolKind = TIndexSymbolKind.InterfaceType) or not FParts.Units.UnitOf(mCurrent, mUnit) then
    begin
      FComplete := False;
      Exit;
    end;
    CollectClassLevel(mCurrent, mUnit);
    if not FParts.Typing.AncestorOf(mCurrent, mAncestor) or
      (mAncestor.SymbolKind = TIndexSymbolKind.InterfaceType) then
    begin
      CloseChain(mCurrent);
      Exit;
    end;
    mCurrent := mAncestor;
  end;
end;

function TResolverInterfaceMembers.EnterInterface(const AIntf: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
var
  mKey: string;
begin
  mKey := UpperCase(AIntf.QualifiedName);
  Result := not FSeenInterfaces.ContainsKey(mKey) and FParts.Units.UnitOf(AIntf, AUnit);
  if Result then
  begin
    FSeenInterfaces.Add(mKey, True);
    Result := not FDelegated.ContainsKey(UpperCase(AIntf.Name));
  end;
end;

function TResolverInterfaceMembers.IsCovered(const AKey: string; const AIntf: TResolvedSymbol;
  const ASymbol: TIndexSymbol): Boolean;
begin
  Result := FImplemented.ContainsKey(AKey) or FByName.ContainsKey(LowerCase(ASymbol.Name)) or
    FResolutions.ContainsKey(LowerCase(TResolverText.BareTypeName(AIntf.Name) + '.' + ASymbol.Name));
end;

procedure TResolverInterfaceMembers.CollectInterfaceLevel(const AIntf: TResolvedSymbol; const AUnit: TUnitIndex);
var
  mBindings: TArray<string>;
  mSymbol: TIndexSymbol;
  mKey: string;
  mMember: TResolvedSymbol;
begin
  mBindings := Unqualified(AIntf.Bindings);
  for mSymbol in AUnit.Symbols do
  begin
    if not SameText(mSymbol.Container, AIntf.QualifiedName) or not (mSymbol.Kind in cRoutineKinds) then
    begin
      Continue;
    end;
    mKey := KeyOf(mSymbol, mBindings);
    if IsCovered(mKey, AIntf, mSymbol) then
    begin
      Continue;
    end;
    FImplemented.Add(mKey, True);
    mMember := TResolvedSymbol.FromIndex(AUnit, mSymbol);
    mMember.Bindings := mBindings;
    FList.Add(mMember);
  end;
end;

procedure TResolverInterfaceMembers.CollectInterface(const AName: string; const AOwnerUnit: TUnitIndex);
var
  mIntf, mAncestor: TResolvedSymbol;
  mUnit: TUnitIndex;
  mDepth: Integer;
begin
  // Das Interface mit seinen Vorfahren.
  if not FParts.Lookup.ResolveTypeText(AName, AOwnerUnit, True, mIntf) or
    (mIntf.SymbolKind <> TIndexSymbolKind.InterfaceType) then
  begin
    Exit;
  end;
  mDepth := 0;
  while (mDepth <= cMaxDepth) and EnterInterface(mIntf, mUnit) do
  begin
    CollectInterfaceLevel(mIntf, mUnit);
    if not FParts.Typing.AncestorOf(mIntf, mAncestor) or (mAncestor.SymbolKind <> TIndexSymbolKind.InterfaceType) then
    begin
      Break;
    end;
    mIntf := mAncestor;
    Inc(mDepth);
  end;
end;

function TResolverInterfaceMembers.Collect(const AOwn: TResolvedSymbol; const AOwnerUnit: TUnitIndex;
  const AAncestors, ADelegated: TArray<string>; out AComplete: Boolean): TArray<TResolvedSymbol>;
var
  mName: string;
begin
  FComplete := True;
  CollectImplemented(AOwn);
  for mName in ADelegated do
  begin
    AddDelegated(mName, AOwnerUnit);
  end;
  for mName in InterfaceNames(AOwn, AAncestors) do
  begin
    CollectInterface(mName, AOwnerUnit);
  end;
  AComplete := FComplete;
  Result := FList.ToArray;
end;

end.
