unit Atlas.Common.Semantics.NameResolver.Queries;

// Abfragen der Namensauflösung für Prüfregeln, Codeaktionen und Navigation: Typen und Namen aus Sicht einer
// Unit, Verweise in Doku-Kommentaren (cref), Mitglieder für Accessoren, Überschreibungen und inherited, fehlende
// Interface-Methoden, Attribut- und Exception-Klassen, Mitglieder von with-Ausdrücken und Helfer an einer Stelle.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Expressions,
  Atlas.Common.Semantics.NameResolver.Chains;

type
  /// <summary>Besuch eines Vorfahren AAncestor aus AUnit in Vererbungstiefe ADepth (1 = direkter Vorfahr).</summary>
  TResolverAncestorVisit = reference to procedure(const AAncestor: TResolvedSymbol; const AUnit: TUnitIndex;
    ADepth: Integer);

  TResolverQueries = class
  private
    FParts: TResolverParts;
    FExpressions: TResolverExpressions;
    FChains: TResolverChains;
    procedure WalkAncestors(const AOwn: TResolvedSymbol; const AVisit: TResolverAncestorVisit);
    function MemberCref(const AFromUnit: TUnitIndex; const AContainer, AName: string;
      out AResult: TResolvedSymbol): Boolean;
    function ClassTypeOf(const ASymbol: TResolvedSymbol; out AClass: TResolvedSymbol): Boolean;
    function ChainReaches(const AClass: TResolvedSymbol; const ARoot: string; out AOpenAncestor: string): Boolean;
    function OwnAccessor(const AFromUnit: TUnitIndex; const AProperty: TResolvedSymbol; const AName: string;
      out AReadsField: Boolean): Boolean;
  public
    constructor Create(const AParts: TResolverParts; AExpressions: TResolverExpressions; AChains: TResolverChains);
    /// <summary>Typname, wie er in AFromUnit stünde (ohne Baum, Abschnitt implementation).</summary>
    function ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string;
      out AResult: TResolvedSymbol): Boolean;
    /// <summary>Typtext mit Typargumenten, wie er in AFromUnit stünde.</summary>
    function ResolveTypeTextFrom(const AFromUnit: TUnitIndex; const ATypeText: string;
      out AResult: TResolvedSymbol): Boolean;
    /// <summary>Name auf Unit-Ebene, wie er in AFromUnit stünde.</summary>
    function ResolveNameFrom(const AFromUnit: TUnitIndex; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Ziel eines cref-Verweises (Typ, Typ.Mitglied, Mitglied von AContainer, globaler Name).</summary>
    function LocateCref(const AFromUnit: TUnitIndex; const AContainer, ACref: string;
      out AResult: TResolvedSymbol): Boolean;
    /// <summary>Fehlende Interface-Methoden der Klasse ATypeName.</summary>
    function MissingInterfaceMembers(const AFromUnit: TUnitIndex; const ATypeName: string): TArray<TResolvedSymbol>;
      overload;
    /// <summary>Wie oben mit der Vorfahrenliste AAncestors.</summary>
    function MissingInterfaceMembers(const AFromUnit: TUnitIndex; const ATypeName: string;
      const AAncestors: TArray<string>): TArray<TResolvedSymbol>; overload;
    /// <summary>Wie oben ohne die Interfaces ADelegated (implements); AComplete: Klassenkette ganz bekannt.</summary>
    function MissingInterfaceMembers(const AFromUnit: TUnitIndex; const ATypeName: string;
      const AAncestors, ADelegated: TArray<string>; out AComplete: Boolean): TArray<TResolvedSymbol>; overload;
    /// <summary>Typtext ohne Unit-Präfixe der Units im Index.</summary>
    function UnqualifyType(const AText: string): string; overload;
    /// <summary>Wie oben, dazu ohne Präfix AOwnUnit.</summary>
    function UnqualifyType(const AText, AOwnUnit: string): string; overload;
    /// <summary>Felder und Methoden des Typs ATypeName und seiner Vorfahren, die ein Accessor lesen könnte.</summary>
    function AccessorCandidates(const AFromUnit: TUnitIndex; const ATypeName: string): TArray<TResolvedSymbol>;
    /// <summary>Virtuelle Methoden der Vorfahren von ATypeName, die der Typ noch nicht überschreibt.</summary>
    function OverridableMembers(const AFromUnit: TUnitIndex; const ATypeName: string): TArray<TResolvedSymbol>;
    /// <summary>Methoden der Vorfahren der Methodenklasse an AOffset; AStart: Beginn der äußersten Routine,
    /// ADepths: Vererbungstiefe je Methode.</summary>
    function InheritedOverloads(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
      out AStart: Integer; out ADepths: TArray<Integer>): TArray<TIndexSymbol>;
    /// <summary>Property AName des Typs AType samt Vorfahren; ADepth: Vererbungstiefe.</summary>
    function TypedProperty(const AType: TResolvedSymbol; const AName: string; out AProperty: TResolvedSymbol;
      out ADepth: Integer): Boolean;
    /// <summary>Vorfahr-Helfer des Helfers AHelper.</summary>
    function HelperParent(const AHelper: TResolvedSymbol; out AParent: TResolvedSymbol): Boolean;
    /// <summary>ASymbol ist eine Attributklasse (stammt von TCustomAttribute ab).</summary>
    function AttributeClassOf(const ASymbol: TResolvedSymbol; out AClass: TResolvedSymbol): Boolean;
    /// <summary>ASymbol ist eine Exception-Klasse (stammt von Exception ab).</summary>
    function ExceptionClassOf(const ASymbol: TResolvedSymbol; out AClass: TResolvedSymbol): Boolean;
    /// <summary>Namen von AClass und seinen Vorfahren, nächster zuerst.</summary>
    function AncestorNames(const AClass: TResolvedSymbol): TArray<string>; overload;
    /// <summary>Wie oben; AComplete: Die Kette endet ohne unbekannten Vorfahren.</summary>
    function AncestorNames(const AClass: TResolvedSymbol; out AComplete: Boolean): TArray<string>; overload;
    /// <summary>Typ ATypeName stammt an AOffset von ATargetName ab.</summary>
    function TypeDescendsFrom(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
      const ATypeName, ATargetName: string): Boolean;
    /// <summary>with-Anweisung an AOffset, deren Ausdruck ein Mitglied AName hat.</summary>
    function WithMember(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer;
      out AResult: TResolvedWithMember): Boolean;
    /// <summary>Wert AName eines Aufzählungstyps mit SCOPEDENUMS, sichtbar an AOffset; AQualified: Typ.Wert.
    /// </summary>
    function ScopedEnumValue(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer;
      out AQualified: string): Boolean;
    /// <summary>Helfer, der an AOffset für den Typ ATypeName gilt.</summary>
    function VisibleHelper(ATree: TSyntaxTree; const AFileName, ATypeName: string; AOffset: Integer;
      out AHelper: TResolvedSymbol): Boolean;
    /// <summary>Liest die Property AProperty ein Feld (AReadsField) oder eine Methode? False: unbekannt.</summary>
    function PropertyReadsField(const AProperty: TResolvedSymbol; out AReadsField: Boolean): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Semantics.NameResolver.InterfaceMembers;

/// <summary>Sichtbar wie aus einer Methode der abgeleiteten Klasse: protected ja, private nur aus derselben Datei.
/// </summary>
function InheritedVisible(const ASymbol: TIndexSymbol; ASameFile: Boolean): Boolean;
begin
  Result := (ASymbol.Visibility <> TIndexVisibility.StrictPrivate) and
    ((ASymbol.Visibility <> TIndexVisibility.Private) or ASameFile);
end;

/// <summary>Feld oder Methode von AContainer, die ein Accessor der abgeleiteten Klasse lesen könnte.</summary>
function IsAccessor(const ASymbol: TIndexSymbol; const AContainer: string; ASameFile: Boolean): Boolean;
begin
  Result := SameText(ASymbol.Container, AContainer) and
    (ASymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Method]) and InheritedVisible(ASymbol, ASameFile);
end;

/// <summary>Virtuelle Methode von AContainer, die eine abgeleitete Klasse überschreiben kann.</summary>
function IsOverridable(const ASymbol: TIndexSymbol; const AContainer: string): Boolean;
begin
  Result := SameText(ASymbol.Container, AContainer) and ASymbol.IsVirtual and
    (ASymbol.Kind = TIndexSymbolKind.Method) and
    not (ASymbol.Visibility in [TIndexVisibility.StrictPrivate, TIndexVisibility.Private]);
end;

/// <summary>Methode von AContainer, die inherited aus der abgeleiteten Klasse aufrufen kann.</summary>
function IsInheritedMethod(const ASymbol: TIndexSymbol; const AContainer: string; ASameFile: Boolean): Boolean;
begin
  Result := SameText(ASymbol.Container, AContainer) and
    (ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and not ASymbol.Unavailable and
    InheritedVisible(ASymbol, ASameFile);
end;

/// <summary>Nimmt ASymbol in AList auf, wenn sein Name noch nicht in ASeen steht.</summary>
procedure AddUnseen(ASeen: TDictionary<string, Boolean>; AList: TList<TResolvedSymbol>;
  const ASymbol: TResolvedSymbol);
begin
  if not ASeen.ContainsKey(UpperCase(ASymbol.Name)) then
  begin
    ASeen.Add(UpperCase(ASymbol.Name), True);
    AList.Add(ASymbol);
  end;
end;

/// <summary>"TFoo.Bar(System.Int32)" → "TFoo.Bar".</summary>
function CrefName(const ACref: string): string;
begin
  Result := Trim(ACref);
  if Pos('(', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('(', Result) - 1));
  end;
end;

/// <summary>Wort hinter read in der Property-Signatur ASignature, bei read FPunkt.X das Feld FPunkt.</summary>
function ReadTarget(const ASignature: string): string;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  // "property Rect: TRect read FRect write SetRect".
  Result := '';
  mWords := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mWords) - 1 do
  begin
    if SameText(mWords[mIndex], 'read') then
    begin
      Result := mWords[mIndex + 1];
      Break;
    end;
  end;
  if Pos('.', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('.', Result) - 1);
  end;
end;

/// <summary>Wert AName mit SCOPEDENUMS in AUnit (AOnlyInterface: nur aus dem interface-Teil).</summary>
function FindScopedEnum(const AUnit: TUnitIndex; const AName: string; AOnlyInterface: Boolean;
  out AQualified: string): Boolean;
var
  mPosition: Integer;
begin
  for mPosition in AUnit.SymbolsNamed(AName) do
  begin
    if (AUnit.Symbols[mPosition].Kind = TIndexSymbolKind.EnumMember) and AUnit.Symbols[mPosition].ScopedEnum and
      (not AOnlyInterface or AUnit.Symbols[mPosition].InInterface) then
    begin
      AQualified := AUnit.Symbols[mPosition].Container + '.' + AUnit.Symbols[mPosition].Name;
      Exit(True);
    end;
  end;
  Result := False;
end;

constructor TResolverQueries.Create(const AParts: TResolverParts; AExpressions: TResolverExpressions;
  AChains: TResolverChains);
begin
  inherited Create;
  FParts := AParts;
  FExpressions := AExpressions;
  FChains := AChains;
end;

procedure TResolverQueries.WalkAncestors(const AOwn: TResolvedSymbol; const AVisit: TResolverAncestorVisit);
var
  mCurrent, mAncestor: TResolvedSymbol;
  mUnit: TUnitIndex;
  mDepth: Integer;
begin
  mCurrent := AOwn;
  for mDepth := 1 to cMaxDepth do
  begin
    if not FParts.Typing.AncestorOf(mCurrent, mAncestor) or not FParts.Units.UnitOf(mAncestor, mUnit) then
    begin
      Break;
    end;
    AVisit(mAncestor, mUnit, mDepth);
    mCurrent := mAncestor;
  end;
end;

function TResolverQueries.ResolveTypeFrom(const AFromUnit: TUnitIndex; const ATypeName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  // Helfer- und Vorfahren-Cache bleiben: Ihre Schlüssel enthalten Unit und Abschnitt.
  FParts.Place.MoveToUnit(AFromUnit);
  Result := FParts.Lookup.ResolveTypeName(ATypeName, AFromUnit, True, AResult);
end;

function TResolverQueries.ResolveTypeTextFrom(const AFromUnit: TUnitIndex; const ATypeText: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  FParts.Place.MoveToUnit(AFromUnit);
  Result := FParts.Lookup.ResolveTypeText(ATypeText, AFromUnit, True, AResult);
end;

function TResolverQueries.ResolveNameFrom(const AFromUnit: TUnitIndex; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
begin
  FParts.Place.MoveToUnit(AFromUnit);
  Result := FParts.Lookup.LookupGlobal(AFromUnit, AName, True, False, AResult);
end;

function TResolverQueries.MemberCref(const AFromUnit: TUnitIndex; const AContainer, AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mDot: Integer;
  mOwner: TResolvedSymbol;
begin
  // Typ.Mitglied
  mDot := LastDelimiter('.', AName);
  if mDot > 0 then
  begin
    Result := ResolveTypeFrom(AFromUnit, Copy(AName, 1, mDot - 1), mOwner) and not mOwner.Builtin and
      FParts.Members.DeclaredMember(mOwner, Copy(AName, mDot + 1, MaxInt), AResult);
    Exit;
  end;
  // Mitglied der eigenen Klasse.
  Result := (AContainer <> '') and ResolveTypeFrom(AFromUnit, AContainer, mOwner) and
    FParts.Members.DeclaredMember(mOwner, AName, AResult);
end;

function TResolverQueries.LocateCref(const AFromUnit: TUnitIndex; const AContainer, ACref: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mName: string;
begin
  AResult := TResolvedSymbol.Empty;
  mName := CrefName(ACref);
  if mName = '' then
  begin
    Exit(False);
  end;
  // Typ (auch qualifiziert, z. B. System.Classes.TList).
  if ResolveTypeFrom(AFromUnit, mName, AResult) and not AResult.Builtin and AResult.IsType then
  begin
    Exit(True);
  end;
  if MemberCref(AFromUnit, AContainer, mName, AResult) then
  begin
    Exit(True);
  end;
  // Globale Routine, Konstante, Variable.
  Result := ResolveNameFrom(AFromUnit, mName, AResult) and (AResult.FileName <> '');
end;

function TResolverQueries.MissingInterfaceMembers(const AFromUnit: TUnitIndex;
  const ATypeName: string): TArray<TResolvedSymbol>;
begin
  Result := MissingInterfaceMembers(AFromUnit, ATypeName, nil);
end;

function TResolverQueries.MissingInterfaceMembers(const AFromUnit: TUnitIndex; const ATypeName: string;
  const AAncestors: TArray<string>): TArray<TResolvedSymbol>;
var
  mComplete: Boolean;
begin
  Result := MissingInterfaceMembers(AFromUnit, ATypeName, AAncestors, nil, mComplete);
end;

function TResolverQueries.MissingInterfaceMembers(const AFromUnit: TUnitIndex; const ATypeName: string;
  const AAncestors, ADelegated: TArray<string>; out AComplete: Boolean): TArray<TResolvedSymbol>;
var
  mOwn: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mCollector: TResolverInterfaceMembers;
begin
  Result := nil;
  AComplete := False;
  if not ResolveTypeFrom(AFromUnit, ATypeName, mOwn) or not FParts.Units.UnitOf(mOwn, mOwnerUnit) then
  begin
    Exit;
  end;
  mCollector := TResolverInterfaceMembers.Create(FParts, AFromUnit.UnitName);
  try
    Result := mCollector.Collect(mOwn, mOwnerUnit, AAncestors, ADelegated, AComplete);
  finally
    mCollector.Free;
  end;
end;

function TResolverQueries.UnqualifyType(const AText: string): string;
begin
  Result := UnqualifyType(AText, '');
end;

function TResolverQueries.UnqualifyType(const AText, AOwnUnit: string): string;
begin
  Result := TResolverUnqualify.TypeText(FParts.Place.Index, AText, AOwnUnit);
end;

function TResolverQueries.AccessorCandidates(const AFromUnit: TUnitIndex;
  const ATypeName: string): TArray<TResolvedSymbol>;
var
  mOwn: TResolvedSymbol;
  mSymbol: TIndexSymbol;
  mSeen: TDictionary<string, Boolean>;
  mList: TList<TResolvedSymbol>;
  mFileName: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mList := TList<TResolvedSymbol>.Create;
  try
    // Eigener Typ aus dem aktuellen Stand der Datei: jede Sichtbarkeit.
    for mSymbol in AFromUnit.Symbols do
    begin
      if SameText(mSymbol.Container, ATypeName) and
        (mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Method]) then
      begin
        AddUnseen(mSeen, mList, TResolvedSymbol.FromIndex(AFromUnit, mSymbol));
      end;
    end;
    mFileName := AFromUnit.FileName;
    if ResolveTypeFrom(AFromUnit, ATypeName, mOwn) then
    begin
      WalkAncestors(mOwn,
        procedure(const AAncestor: TResolvedSymbol; const AUnit: TUnitIndex; ADepth: Integer)
        var
          mInherited: TIndexSymbol;
        begin
          for mInherited in AUnit.Symbols do
          begin
            if IsAccessor(mInherited, AAncestor.QualifiedName, SameText(AUnit.FileName, mFileName)) then
            begin
              AddUnseen(mSeen, mList, TResolvedSymbol.FromIndex(AUnit, mInherited).AsMember(ADepth, False));
            end;
          end;
        end);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mSeen.Free;
  end;
end;

function TResolverQueries.OverridableMembers(const AFromUnit: TUnitIndex;
  const ATypeName: string): TArray<TResolvedSymbol>;
var
  mOwn: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mSeen: TDictionary<string, Boolean>;
  mList: TList<TResolvedSymbol>;
begin
  Result := nil;
  if not ResolveTypeFrom(AFromUnit, ATypeName, mOwn) or not FParts.Units.UnitOf(mOwn, mOwnerUnit) then
  begin
    Exit;
  end;
  mSeen := TDictionary<string, Boolean>.Create;
  mList := TList<TResolvedSymbol>.Create;
  try
    // Im Typ selbst Deklariertes ist schon überschrieben bzw. verdeckt.
    for mSymbol in mOwnerUnit.Symbols do
    begin
      if SameText(mSymbol.Container, mOwn.QualifiedName) then
      begin
        mSeen.AddOrSetValue(UpperCase(mSymbol.Name), True);
      end;
    end;
    WalkAncestors(mOwn,
      procedure(const AAncestor: TResolvedSymbol; const AUnit: TUnitIndex; ADepth: Integer)
      var
        mInherited: TIndexSymbol;
      begin
        for mInherited in AUnit.Symbols do
        begin
          if IsOverridable(mInherited, AAncestor.QualifiedName) then
          begin
            AddUnseen(mSeen, mList, TResolvedSymbol.FromIndex(AUnit, mInherited).AsMember(ADepth, False));
          end;
        end;
      end);
    Result := mList.ToArray;
  finally
    mList.Free;
    mSeen.Free;
  end;
end;

function TResolverQueries.InheritedOverloads(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
  out AStart: Integer; out ADepths: TArray<Integer>): TArray<TIndexSymbol>;
var
  mRoutines: TArray<TSyntaxNode>;
  mClass: TResolvedSymbol;
  mSymbols: TList<TIndexSymbol>;
  mDepths: TList<Integer>;
  mFileName: string;
begin
  Result := nil;
  ADepths := nil;
  AStart := -1;
  if ATree = nil then
  begin
    Exit;
  end;
  FParts.Place.MoveTo(ATree, AFileName, AOffset);
  if not FParts.Typing.MethodClass(mClass) then
  begin
    Exit;
  end;
  mRoutines := FParts.Place.EnclosingRoutines;
  AStart := mRoutines[High(mRoutines)].StartOffset;
  mFileName := AFileName;
  mSymbols := TList<TIndexSymbol>.Create;
  mDepths := TList<Integer>.Create;
  try
    WalkAncestors(mClass,
      procedure(const AAncestor: TResolvedSymbol; const AUnit: TUnitIndex; ADepth: Integer)
      var
        mInherited: TIndexSymbol;
      begin
        for mInherited in AUnit.Symbols do
        begin
          if IsInheritedMethod(mInherited, AAncestor.QualifiedName, SameText(AUnit.FileName, mFileName)) then
          begin
            mSymbols.Add(mInherited);
            mDepths.Add(ADepth);
          end;
        end;
      end);
    Result := mSymbols.ToArray;
    ADepths := mDepths.ToArray;
  finally
    mDepths.Free;
    mSymbols.Free;
  end;
end;

function TResolverQueries.TypedProperty(const AType: TResolvedSymbol; const AName: string;
  out AProperty: TResolvedSymbol; out ADepth: Integer): Boolean;
begin
  Result := FParts.Members.TypedProperty(AType, AName, AProperty, ADepth);
end;

function TResolverQueries.HelperParent(const AHelper: TResolvedSymbol; out AParent: TResolvedSymbol): Boolean;
begin
  Result := FParts.Typing.HelperParent(AHelper, AParent);
end;

function TResolverQueries.ClassTypeOf(const ASymbol: TResolvedSymbol; out AClass: TResolvedSymbol): Boolean;
begin
  Result := ASymbol.Found and ASymbol.IsType and FParts.Typing.TypeOf(ASymbol, AClass) and
    (AClass.SymbolKind = TIndexSymbolKind.ClassType);
end;

function TResolverQueries.ChainReaches(const AClass: TResolvedSymbol; const ARoot: string;
  out AOpenAncestor: string): Boolean;
var
  mCurrent, mNext: TResolvedSymbol;
  mDepth: Integer;
begin
  // AOpenAncestor: erster Vorfahr, der sich nicht auflösen ließ; '' wenn die Kette bei TObject endet.
  AOpenAncestor := '';
  mCurrent := AClass;
  for mDepth := 0 to cMaxDepth do
  begin
    if SameText(mCurrent.Name, ARoot) then
    begin
      Exit(True);
    end;
    if (Length(mCurrent.Ancestors) = 0) or TResolverText.IsObjectRoot(mCurrent.Ancestors[0]) then
    begin
      Break;
    end;
    if not FParts.Typing.AncestorOf(mCurrent, mNext) then
    begin
      AOpenAncestor := mCurrent.Ancestors[0];
      Break;
    end;
    mCurrent := mNext;
  end;
  Result := False;
end;

function TResolverQueries.AttributeClassOf(const ASymbol: TResolvedSymbol; out AClass: TResolvedSymbol): Boolean;
var
  mCurrent: TResolvedSymbol;
  mOpen: string;
begin
  AClass := TResolvedSymbol.Empty;
  if not ClassTypeOf(ASymbol, mCurrent) or SameText(mCurrent.Name, 'TCustomAttribute') then
  begin
    Exit(False);
  end;
  AClass := mCurrent;
  Result := ChainReaches(mCurrent, 'TCustomAttribute', mOpen) or EndsText('Attribute', mOpen);
end;

function TResolverQueries.ExceptionClassOf(const ASymbol: TResolvedSymbol; out AClass: TResolvedSymbol): Boolean;
var
  mCurrent: TResolvedSymbol;
  mOpen: string;
begin
  AClass := TResolvedSymbol.Empty;
  if not ClassTypeOf(ASymbol, mCurrent) then
  begin
    Exit(False);
  end;
  AClass := mCurrent;
  Result := ChainReaches(mCurrent, 'Exception', mOpen) or ((mOpen <> '') and TResolverText.LooksLikeException(mOpen));
end;

function TResolverQueries.AncestorNames(const AClass: TResolvedSymbol): TArray<string>;
var
  mComplete: Boolean;
begin
  Result := FParts.Typing.AncestorNames(AClass, mComplete);
end;

function TResolverQueries.AncestorNames(const AClass: TResolvedSymbol; out AComplete: Boolean): TArray<string>;
begin
  Result := FParts.Typing.AncestorNames(AClass, AComplete);
end;

function TResolverQueries.TypeDescendsFrom(ATree: TSyntaxTree; const AFileName: string; AOffset: Integer;
  const ATypeName, ATargetName: string): Boolean;
var
  mActual, mTarget: TResolvedSymbol;
begin
  mActual := FChains.ResolveChain(ATree, AFileName, ATypeName.Split(['.']), AOffset, False);
  mTarget := FChains.ResolveChain(ATree, AFileName, ATargetName.Split(['.']), AOffset, False);
  Result := mActual.Found and mTarget.Found and mActual.IsType and mTarget.IsType and
    FParts.Typing.DescendsFrom(mActual, mTarget);
end;

function TResolverQueries.WithMember(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer;
  out AResult: TResolvedWithMember): Boolean;
var
  mResults: TArray<TResolvedSymbol>;
begin
  FParts.Place.MoveTo(ATree, AFileName, AOffset);
  Result := FExpressions.LookupWithOwner(AName, mResults, AResult.Unknown, AResult.Statement, AResult.Element);
end;

function TResolverQueries.ScopedEnumValue(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer;
  out AQualified: string): Boolean;
var
  mUnitName: string;
  mUsed: PUnitIndex;
begin
  AQualified := '';
  FParts.Place.MoveTo(ATree, AFileName, AOffset);
  if FindScopedEnum(FParts.Place.Current, AName, False, AQualified) then
  begin
    Exit(True);
  end;
  for mUnitName in FParts.Units.ScopeUnits(FParts.Place.Current, FParts.Place.InImplementation) do
  begin
    if FParts.Units.FindUnitRef(mUnitName, mUsed) and FindScopedEnum(mUsed^, AName, True, AQualified) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverQueries.VisibleHelper(ATree: TSyntaxTree; const AFileName, ATypeName: string; AOffset: Integer;
  out AHelper: TResolvedSymbol): Boolean;
var
  mTarget: TResolvedSymbol;
begin
  AHelper := TResolvedSymbol.Empty;
  if (ATree = nil) or (Trim(ATypeName) = '') then
  begin
    Exit(False);
  end;
  FParts.Place.MoveTo(ATree, AFileName, AOffset);
  if not FParts.Lookup.ResolveTypeName(Trim(ATypeName), FParts.Place.Current, FParts.Place.InImplementation,
    mTarget) then
  begin
    // Eingebaute Typen ohne Deklaration: Der Name genügt für den Vergleich mit dem Zieltyp.
    mTarget := TResolvedSymbol.Empty;
    mTarget.Name := Trim(ATypeName);
  end;
  Result := FParts.Typing.HelperFor(mTarget, AHelper);
end;

function TResolverQueries.OwnAccessor(const AFromUnit: TUnitIndex; const AProperty: TResolvedSymbol;
  const AName: string; out AReadsField: Boolean): Boolean;
var
  mPosition: Integer;
  mSymbol: TIndexSymbol;
begin
  // Zuerst im Typ selbst, auch private: Der Zugriff steht meist privat neben der Property.
  for mPosition in AFromUnit.SymbolsNamed(AName) do
  begin
    mSymbol := AFromUnit.Symbols[mPosition];
    if SameText(mSymbol.Container, AProperty.Container) and
      (mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Method]) then
    begin
      AReadsField := mSymbol.Kind = TIndexSymbolKind.Field;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverQueries.PropertyReadsField(const AProperty: TResolvedSymbol; out AReadsField: Boolean): Boolean;
var
  mName: string;
  mFromUnit: TUnitIndex;
  mOwner, mMember: TResolvedSymbol;
begin
  AReadsField := False;
  Result := False;
  if (AProperty.SymbolKind <> TIndexSymbolKind.Property_) or (AProperty.Container = '') then
  begin
    Exit;
  end;
  mName := ReadTarget(AProperty.Signature);
  if (mName = '') or not FParts.Units.UnitOf(AProperty, mFromUnit) then
  begin
    Exit;
  end;
  if OwnAccessor(mFromUnit, AProperty, mName, AReadsField) then
  begin
    Exit(True);
  end;
  Result := FParts.Lookup.ResolveTypeName(AProperty.Container, mFromUnit, True, mOwner) and
    FParts.Members.FindMember(mOwner, mName, mMember);
  if Result then
  begin
    AReadsField := mMember.SymbolKind = TIndexSymbolKind.Field;
  end;
end;

end.
