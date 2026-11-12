unit Atlas.Common.Semantics.NameResolver.Typing;

// Typen der Namensauflösung: Typ eines aufgelösten Namens (Aliase verfolgt, Inline-Variablen aus ihrem
// Ausdruck), Vorfahren, Helfer, Klassenreferenzen, Sichtbarkeit von Mitgliedern und die Klasse der Methode an der
// Stelle.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units,
  Atlas.Common.Semantics.NameResolver.Lookup;

type
  TResolverTyping = class
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
    FLookup: TResolverLookup;
    FInfer: TResolverInferFunc;
    // Je Baum: Helfer je Typname und aufgelöste Vorfahren je Typ (Diagnoselog 15.10.2026: Jeder Mitgliedszugriff
    // lief die ganze Vererbungskette neu durch). Gelten, solange FCacheEpoch dem Stand der Stelle entspricht.
    FHelpers: TDictionary<string, TResolvedSymbol>;
    FAncestors: TDictionary<string, TResolvedSymbol>;
    FCacheEpoch: Integer;
    // Klasse der umgebenden Methode, einmal je Ortswechsel (FClassMove): 0 = noch nicht ermittelt, 1 = keine,
    // 2 = FClass, 3 = wird gerade ermittelt.
    FClassState: Integer;
    FClass: TResolvedSymbol;
    FClassMove: Integer;
    /// <summary>Leert die baumbezogenen Zwischenspeicher, wenn die Stelle den Baum gewechselt hat.</summary>
    procedure SyncCaches;
    /// <summary>Typ, von dem TypeOf ausgeht, bevor Aliase verfolgt werden.</summary>
    function StartType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>TFoo.Create liefert ein TFoo.</summary>
    function ConstructedType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Inline-Variable ohne Typangabe: Typ des Ausdrucks.</summary>
    function InferredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Deklarierter Typ samt Typargumenten, in der Unit der Deklaration aufgelöst.</summary>
    function DeclaredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Verfolgt Aliase von AStart bis zum Grundtyp.</summary>
    function FollowAliases(const AStart: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Name des Typs der umgebenden Methode (TFoo in TFoo.Bar) bzw. der Property-Deklaration; ''
    /// sonst.</summary>
    function MethodTypeName: string;
    /// <summary>Verschachtelte Typen aus dem Kopf (TAussen.TInnen), innerster zuerst; nil, wenn der Pfad nicht
    /// aufgeht.</summary>
    function NestedMethodClasses(const ATypeName: string): TArray<TResolvedSymbol>;
    /// <summary>Reicht die Vorfahrenkette von AType ohne unbekannten Vorfahren bis TObject bzw. ans Ende?
    /// </summary>
    function ReachesRoot(const AType: TResolvedSymbol): Boolean;
  public
    constructor Create(APlace: TResolverPlace; AUnits: TResolverUnits; ALookup: TResolverLookup);
    destructor Destroy; override;
    /// <summary>Typ eines aufgelösten Namens, Aliase verfolgt (Typen sind ihr eigener Typ, TFoo.Create ein TFoo).
    /// </summary>
    function TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Direkter Vorfahr eines Typs (ohne Angabe TObject bzw. IInterface); False ohne oder bei
    /// Helfern.</summary>
    function AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
    /// <summary>Klasse, auf die die Klassenreferenz AType zeigt (class of …), aufgelöst in der Unit von AType.
    /// </summary>
    function ClassRefTargetOf(const AType: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
    /// <summary>Ist AType AAncestor oder stammt davon ab?</summary>
    function DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
    /// <summary>Ist ASymbol (Mitglied von AOwner aus AOwnerUnit) an der Stelle sichtbar? ALocalChain: Ein Typ
    /// zwischen dem Empfänger und AOwner ist in der aktuellen Unit deklariert; dann sind protected-Mitglieder
    /// sichtbar wie in der Unit von AOwner (TKlasse(Control).Click, #1008).</summary>
    function IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex; const AOwner: TResolvedSymbol;
      ALocalChain: Boolean): Boolean;
    /// <summary>Klasse der umgebenden Methode, einmal je Ortswechsel ermittelt.</summary>
    function CurrentClass(out AType: TResolvedSymbol): Boolean;
    /// <summary>Zuletzt sichtbarer Helfer für AType an der Stelle: eigene Unit, dann uses von hinten.</summary>
    function HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
    /// <summary>Vorfahr-Helfer eines Helfers (class helper (TBaseHelper) for T, #848); False ohne.</summary>
    function HelperParent(const AHelper: TResolvedSymbol; out AParent: TResolvedSymbol): Boolean;
    /// <summary>Im Typ AOuter selbst deklarierter Typ AName, ohne Sichtbarkeitsprüfung (Pfad im
    /// Methodenkopf).</summary>
    function NestedType(const AOuter: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Innerster Typ aus MethodClasses.</summary>
    function MethodClass(out AType: TResolvedSymbol): Boolean;
    /// <summary>Typ der umgebenden Methode und bei verschachtelten Typen (TAussen.TInnen.Methode) die
    /// äußeren Typen, innerster zuerst; ihre Mitglieder sind dort ohne Präfix sichtbar. In einer
    /// Property-Deklaration deren Typ (#690).</summary>
    function MethodClasses: TArray<TResolvedSymbol>;
    /// <summary>Bricht die Vorfahrenkette der umgebenden Klasse an einem unbekannten Typ ab?</summary>
    function HasUnknownAncestor: Boolean;
    /// <summary>Namen ohne Unit von AClass und seinen Vorfahren, AClass zuerst (#483); bricht die Kette ab,
    /// zuletzt der Name des unbekannten Vorfahren. AComplete: Die Kette reicht ohne unbekannten Vorfahren bis zum
    /// Ende (#1326).</summary>
    function AncestorNames(const AClass: TResolvedSymbol; out AComplete: Boolean): TArray<string>;
    /// <summary>Typ eines Ausdrucks für Inline-Variablen ohne Typangabe (TResolverExpressions.ExprSymbol).</summary>
    property Infer: TResolverInferFunc read FInfer write FInfer;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  System.SysUtils,
  Atlas.Common.Diagnostics.RequestScope;

constructor TResolverTyping.Create(APlace: TResolverPlace; AUnits: TResolverUnits; ALookup: TResolverLookup);
begin
  inherited Create;
  FPlace := APlace;
  FUnits := AUnits;
  FLookup := ALookup;
  FHelpers := TDictionary<string, TResolvedSymbol>.Create;
  FAncestors := TDictionary<string, TResolvedSymbol>.Create;
  FCacheEpoch := APlace.CacheEpoch;
  FClassMove := APlace.MoveCount;
end;

destructor TResolverTyping.Destroy;
begin
  FAncestors.Free;
  FHelpers.Free;
  inherited;
end;

procedure TResolverTyping.SyncCaches;
begin
  if FCacheEpoch <> FPlace.CacheEpoch then
  begin
    FHelpers.Clear;
    FAncestors.Clear;
    FCacheEpoch := FPlace.CacheEpoch;
  end;
end;

function TResolverTyping.TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mStart: TResolvedSymbol;
begin
  Result := not AResolved.IsTypeParameter and StartType(AResolved, mStart) and FollowAliases(mStart, AType);
end;

function TResolverTyping.StartType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
begin
  // Typen sind ihr eigener Typ; Aliase werden danach verfolgt.
  Result := True;
  if AResolved.IsType then
  begin
    AType := AResolved;
  end
  else if Length(AResolved.Constructed) > 0 then
  begin
    AType := AResolved.Constructed[0];
  end
  else if (AResolved.SymbolKind = TIndexSymbolKind.Constructor_) and (AResolved.Container <> '') then
  begin
    Result := ConstructedType(AResolved, AType);
  end
  else if AResolved.TypeName = '' then
  begin
    Result := InferredType(AResolved, AType);
  end
  else
  begin
    Result := DeclaredType(AResolved, AType);
  end;
end;

function TResolverTyping.ConstructedType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
begin
  Result := FUnits.UnitOf(AResolved, mFromUnit) and FLookup.ResolveTypeName(AResolved.Container, mFromUnit,
    FPlace.IsCurrentFile(mFromUnit.FileName), AType);
  if Result then
  begin
    AType.Bindings := AResolved.Bindings;
  end;
end;

function TResolverTyping.InferredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mValue: TResolvedSymbol;
  mSavedOffset: Integer;
begin
  if (AResolved.Initializer = nil) or (FPlace.InferDepth >= cMaxInferDepth) or (FPlace.Tree = nil) or
    not Assigned(FInfer) then
  begin
    Exit(False);
  end;
  mSavedOffset := FPlace.Offset;
  FPlace.InferDepth := FPlace.InferDepth + 1;
  try
    FPlace.Offset := AResolved.Initializer.StartOffset;
    Result := FInfer(AResolved.Initializer, mValue) and TypeOf(mValue, AType);
  finally
    FPlace.InferDepth := FPlace.InferDepth - 1;
    FPlace.Offset := mSavedOffset;
  end;
end;

function TResolverTyping.DeclaredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
  mWithImplementation: Boolean;
begin
  Result := FUnits.UnitOf(AResolved, mFromUnit);
  if Result then
  begin
    mWithImplementation := (AResolved.Kind = TResolvedKind.Local) or
      (FPlace.IsCurrentFile(mFromUnit.FileName) and FPlace.InImplementation);
    Result := FLookup.ResolveTypeText(TResolverText.Substitute(TResolverText.FullType(AResolved.TypeName,
      AResolved.TypeArgs), AResolved.Bindings), mFromUnit, mWithImplementation, AType);
  end;
end;

function TResolverTyping.FollowAliases(const AStart: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mCurrent, mNext: TResolvedSymbol;
  mFromUnit: TUnitIndex;
  mDepth: Integer;
begin
  mCurrent := AStart;
  mDepth := 0;
  while not mCurrent.Builtin and (mCurrent.SymbolKind = TIndexSymbolKind.TypeAlias) and (mCurrent.TypeName <> '') and
    (mDepth < cMaxDepth) do
  begin
    // Eigene Variable: der out-Parameter würde mCurrent.TypeName vor dem Aufruf leeren.
    if not FUnits.UnitOf(mCurrent, mFromUnit) or
      not FLookup.ResolveTypeText(TResolverText.Substitute(TResolverText.FullType(mCurrent.TypeName,
        mCurrent.TypeArgs), mCurrent.Bindings), mFromUnit, FPlace.IsCurrentFile(mFromUnit.FileName), mNext) then
    begin
      Exit(False);
    end;
    mCurrent := mNext;
    Inc(mDepth);
  end;
  AType := mCurrent;
  Result := True;
end;

function TResolverTyping.AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
  mAlias: TResolvedSymbol;
  mName, mKey: string;
  mWithImplementation: Boolean;
begin
  Result := False;
  // Helfer: der "Vorfahr" ist der erweiterte Typ, nicht der Elterntyp.
  if AType.Builtin or not FUnits.UnitOf(AType, mFromUnit) or (AType.SymbolKind = TIndexSymbolKind.HelperType) then
  begin
    Exit;
  end;
  if Length(AType.Ancestors) > 0 then
  begin
    mName := TResolverText.Substitute(AType.AncestorText(0), AType.Bindings);
  end
  else if (AType.SymbolKind = TIndexSymbolKind.ClassType) and not SameText(AType.Name, 'TObject') then
  begin
    mName := 'TObject';
  end
  else if (AType.SymbolKind = TIndexSymbolKind.InterfaceType) and not SameText(AType.Name, 'IInterface') then
  begin
    mName := 'IInterface';
  end
  else
  begin
    Exit;
  end;
  SyncCaches;
  // Die Sichtbarkeit des implementation-Teils gehört zum Schlüssel: Der Cache überdauert ResolveTypeFrom
  //, dort ist Current eine andere Unit.
  mWithImplementation := FPlace.IsCurrentFile(mFromUnit.FileName);
  mKey := UpperCase(mFromUnit.FileName + '|' + AType.QualifiedName + '|' + mName) + '|' +
    BoolToStr(mWithImplementation, True);
  if FAncestors.TryGetValue(mKey, AAncestor) then
  begin
    Exit(AAncestor.Found);
  end;
  Result := FLookup.ResolveTypeText(mName, mFromUnit, mWithImplementation, AAncestor) and
    not AAncestor.Builtin and not SameText(AAncestor.QualifiedName, AType.QualifiedName);
  // class(TAlias) mit TAlias = TEcht: Vorfahr ist TEcht, der Alias selbst hat keine Member.
  if Result and (AAncestor.SymbolKind = TIndexSymbolKind.TypeAlias) then
  begin
    mAlias := AAncestor;
    Result := FollowAliases(mAlias, AAncestor) and not AAncestor.Builtin and
      not SameText(AAncestor.QualifiedName, AType.QualifiedName);
  end;
  if not Result then
  begin
    AAncestor := TResolvedSymbol.Empty;
  end;
  FAncestors.AddOrSetValue(mKey, AAncestor);
end;

function TResolverTyping.ClassRefTargetOf(const AType: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
var
  mName: string;
  mUnit: TUnitIndex;
begin
  Result := False;
  ATarget := TResolvedSymbol.Empty;
  if AType.Builtin or (AType.SymbolKind <> TIndexSymbolKind.ClassType) or (Length(AType.Ancestors) > 0) then
  begin
    Exit;
  end;
  mName := TResolverText.ClassRefTarget(AType.Signature);
  if (mName = '') or not FUnits.UnitOf(AType, mUnit) then
  begin
    Exit;
  end;
  Result := FLookup.ResolveTypeText(mName, mUnit, FPlace.IsCurrentFile(mUnit.FileName), ATarget) and
    not ATarget.Builtin and (ATarget.SymbolKind = TIndexSymbolKind.ClassType) and
    not SameText(ATarget.QualifiedName, AType.QualifiedName);
  if not Result then
  begin
    ATarget := TResolvedSymbol.Empty;
  end;
end;

function TResolverTyping.DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
var
  mCurrent, mNext: TResolvedSymbol;
  mDepth: Integer;
begin
  mCurrent := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if SameText(mCurrent.QualifiedName, AAncestor.QualifiedName) and
      SameText(mCurrent.UnitName, AAncestor.UnitName) then
    begin
      Exit(True);
    end;
    if not AncestorOf(mCurrent, mNext) then
    begin
      Exit(False);
    end;
    mCurrent := mNext;
  end;
  Result := False;
end;

function TResolverTyping.IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex;
  const AOwner: TResolvedSymbol; ALocalChain: Boolean): Boolean;
var
  mSameUnit: Boolean;
  mOwn: TResolvedSymbol;
begin
  mSameUnit := FPlace.IsCurrentFile(AOwnerUnit.FileName);
  // Aus anderen Units sind nur Deklarationen im interface sichtbar, keine Rümpfe.
  if not mSameUnit and not ASymbol.InInterface then
  begin
    Exit(False);
  end;
  case ASymbol.Visibility of
    TIndexVisibility.Private:
      Result := mSameUnit;
    TIndexVisibility.StrictPrivate:
      Result := mSameUnit and CurrentClass(mOwn) and SameText(mOwn.QualifiedName, AOwner.QualifiedName);
    TIndexVisibility.Protected:
      Result := mSameUnit or ALocalChain or (CurrentClass(mOwn) and DescendsFrom(mOwn, AOwner));
    TIndexVisibility.StrictProtected:
      Result := CurrentClass(mOwn) and DescendsFrom(mOwn, AOwner);
  else
    Result := True;
  end;
end;

function TResolverTyping.CurrentClass(out AType: TResolvedSymbol): Boolean;
begin
  // Einmal je Ortswechsel: Klasse der umgebenden Methode.
  if FClassMove <> FPlace.MoveCount then
  begin
    FClassMove := FPlace.MoveCount;
    FClassState := 0;
  end;
  if FClassState = 3 then
  begin
    // Sicherheitsnetz, zusätzlich zur Ursachenbehebung in MethodClasses: Führt das Ermitteln
    // der Klasse wieder hierher, gilt „keine Klasse“ statt einer Rekursion bis zum Stapelüberlauf. Im
    // Diagnoselog als „resolve classRecursion“ sichtbar, damit ein neuer Weg dorthin auffällt.
    TRequestDiagnostics.ResolveFailed('classRecursion');
    AType := TResolvedSymbol.Empty;
    Exit(False);
  end;
  if FClassState = 0 then
  begin
    FClassState := 3;
    try
      if (FPlace.Tree <> nil) and MethodClass(FClass) then
      begin
        FClassState := 2;
      end
      else
      begin
        FClassState := 1;
      end;
    except
      // Abbruch der Anfrage: beim nächsten Aufruf neu ermitteln, nicht als Rekursion werten.
      FClassState := 0;
      raise;
    end;
  end;
  AType := FClass;
  Result := FClassState = 2;
end;

function TResolverTyping.HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
var
  mKey, mUnitName: string;
  mUnits: TList<TUnitIndex>;
  mUsed: TUnitIndex;
  mPosition: Integer;
  mFound: Boolean;
  mCandidate: TResolvedSymbol;
begin
  SyncCaches;
  // Welche Helfer sichtbar sind, hängt an der Unit und am Abschnitt (uses von interface bzw.
  // implementation); der Cache überdauert ResolveTypeFrom und Abschnittswechsel.
  mKey := UpperCase(AType.UnitName + '.' + AType.QualifiedName + '|' + FPlace.Current.FileName + '|' +
    FPlace.Current.UnitName) + '|' + BoolToStr(FPlace.InImplementation, True);
  if FHelpers.TryGetValue(mKey, AHelper) then
  begin
    Exit(AHelper.Found);
  end;
  AHelper := TResolvedSymbol.Empty;
  // Nur der zuletzt sichtbare Helfer wirkt: eigene Unit, dann uses von hinten; in einer Unit der letzte.
  mUnits := TList<TUnitIndex>.Create;
  try
    mUnits.Add(FPlace.Current);
    for mUnitName in FUnits.ScopeUnits(FPlace.Current, FPlace.InImplementation) do
    begin
      if FUnits.FindUnit(mUnitName, mUsed) then
      begin
        mUnits.Add(mUsed);
      end;
    end;
    for mUsed in mUnits do
    begin
      mFound := False;
      // Nur die vorab ermittelten Helfer-Typen der Unit prüfen statt aller Symbole.
      for mPosition in FUnits.HelperPositions(mUsed) do
      begin
        if TResolverText.HelperTargets(mUsed.Symbols[mPosition].Ancestors[High(mUsed.Symbols[mPosition].Ancestors)],
          AType) and (mUsed.Symbols[mPosition].InInterface or FPlace.IsCurrentFile(mUsed.FileName)) then
        begin
          mCandidate := TResolvedSymbol.FromIndex(mUsed, mUsed.Symbols[mPosition]);
          mFound := True;
        end;
      end;
      if mFound then
      begin
        AHelper := mCandidate;
        Break;
      end;
    end;
  finally
    mUnits.Free;
  end;
  FHelpers.AddOrSetValue(mKey, AHelper);
  Result := AHelper.Found;
end;

function TResolverTyping.HelperParent(const AHelper: TResolvedSymbol; out AParent: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
begin
  AParent := TResolvedSymbol.Empty;
  if (AHelper.SymbolKind <> TIndexSymbolKind.HelperType) or (Length(AHelper.Ancestors) < 2) or
    not FUnits.UnitOf(AHelper, mFromUnit) then
  begin
    Exit(False);
  end;
  Result := FLookup.ResolveTypeText(AHelper.Ancestors[0], mFromUnit, FPlace.IsCurrentFile(mFromUnit.FileName),
    AParent) and (AParent.SymbolKind = TIndexSymbolKind.HelperType) and
    not SameText(AParent.QualifiedName, AHelper.QualifiedName);
  if not Result then
  begin
    AParent := TResolvedSymbol.Empty;
  end;
end;

function TResolverTyping.NestedType(const AOuter: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mOwnerUnit: TUnitIndex;
  mPosition: Integer;
begin
  Result := False;
  if AOuter.Builtin or not FUnits.UnitOf(AOuter, mOwnerUnit) then
  begin
    Exit;
  end;
  for mPosition in mOwnerUnit.SymbolsNamed(AName) do
  begin
    if (mOwnerUnit.Symbols[mPosition].Kind in cTypeKinds) and
      SameText(mOwnerUnit.Symbols[mPosition].Container, AOuter.QualifiedName) then
    begin
      AResult := TResolvedSymbol.FromIndex(mOwnerUnit, mOwnerUnit.Symbols[mPosition]);
      AResult.Bindings := AOuter.Bindings;
      Exit(True);
    end;
  end;
end;

function TResolverTyping.MethodClass(out AType: TResolvedSymbol): Boolean;
var
  mClasses: TArray<TResolvedSymbol>;
begin
  mClasses := MethodClasses;
  Result := Length(mClasses) > 0;
  if Result then
  begin
    AType := mClasses[0];
  end;
end;

function TResolverTyping.MethodTypeName: string;
var
  mRoutines: TArray<TSyntaxNode>;
  mName: string;
  mDot: Integer;
begin
  Result := '';
  if FPlace.Tree = nil then
  begin
    Exit;
  end;
  // Äußerste Routine mit Punkt im Namen: procedure TFoo.Bar
  mRoutines := FPlace.EnclosingRoutines;
  if Length(mRoutines) = 0 then
  begin
    // Zugriffe einer Property (read FName write SetName, #690) stehen im Bereich ihres Typs: Ohne das blieben
    // sie unaufgelöst, und Referenzsuche, Umbenennen und Datenfluss übersahen sie.
    Exit(FPlace.PropertyClassName);
  end;
  mName := mRoutines[High(mRoutines)].Name;
  mDot := LastDelimiter('.', mName);
  if mDot > 0 then
  begin
    Result := Copy(mName, 1, mDot - 1);
  end;
end;

function TResolverTyping.NestedMethodClasses(const ATypeName: string): TArray<TResolvedSymbol>;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mCurrent, mInner: TResolvedSymbol;
begin
  Result := nil;
  mParts := ATypeName.Split(['.']);
  if (Length(mParts) <= 1) or not FLookup.ResolveTypeName(mParts[0], FPlace.Current, True, mCurrent) then
  begin
    Exit;
  end;
  Result := [mCurrent];
  for mIndex := 1 to High(mParts) do
  begin
    // Der Pfad im Kopf benennt den deklarierenden Typ, unabhängig von seiner Sichtbarkeit (strict private
    // verschachtelte Typen werden genauso implementiert). FindMember prüfte die Sichtbarkeit über
    // CurrentClass, das hierher zurückführte.
    if not NestedType(mCurrent, mParts[mIndex], mInner) then
    begin
      Exit(nil);
    end;
    mCurrent := mInner;
    Result := [mCurrent] + Result;
  end;
end;

function TResolverTyping.MethodClasses: TArray<TResolvedSymbol>;
var
  mTypeName: string;
  mCurrent: TResolvedSymbol;
begin
  Result := nil;
  mTypeName := MethodTypeName;
  if mTypeName = '' then
  begin
    Exit;
  end;
  // Verschachtelte Typen zuerst (procedure TAussen.TInnen.Methode): TAussen.TInnen sonst als Unit
  // TAussen gesucht, mit Nachladen über alle Suchpfade, und die Felder blieben unaufgelöst (#647).
  Result := NestedMethodClasses(mTypeName);
  if (Result = nil) and FLookup.ResolveTypeName(mTypeName, FPlace.Current, True, mCurrent) then
  begin
    Result := [mCurrent];
  end;
end;

function TResolverTyping.ReachesRoot(const AType: TResolvedSymbol): Boolean;
var
  mNext, mAncestor: TResolvedSymbol;
  mDepth: Integer;
begin
  mNext := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if (Length(mNext.Ancestors) = 0) or TResolverText.IsObjectRoot(mNext.Ancestors[0]) then
    begin
      Break;
    end;
    if not AncestorOf(mNext, mAncestor) then
    begin
      Exit(False);
    end;
    mNext := mAncestor;
  end;
  Result := True;
end;

function TResolverTyping.HasUnknownAncestor: Boolean;
var
  mClass: TResolvedSymbol;
begin
  for mClass in MethodClasses do
  begin
    if not ReachesRoot(mClass) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverTyping.AncestorNames(const AClass: TResolvedSymbol; out AComplete: Boolean): TArray<string>;
var
  mCurrent, mNext: TResolvedSymbol;
  mDepth: Integer;
begin
  Result := nil;
  AComplete := False;
  if not AClass.Found then
  begin
    Exit;
  end;
  mCurrent := AClass;
  for mDepth := 0 to cMaxDepth do
  begin
    Result := Result + [mCurrent.Name];
    if Length(mCurrent.Ancestors) = 0 then
    begin
      AComplete := True;
      Exit;
    end;
    if not AncestorOf(mCurrent, mNext) then
    begin
      Result := Result + [TResolverText.LastPart(mCurrent.Ancestors[0])];
      Exit;
    end;
    mCurrent := mNext;
  end;
end;

end.
