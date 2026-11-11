unit Atlas.Common.Semantics.InlineCallees;

// Gerufene inline-Routinen und was ihr Rumpf braucht (#1017, #1925), geteilt
// von der Regel inline-not-expanded und der Nutzung der uses-Einträge
// (TUsesUsage): Eine Unit, die nur der Rumpf einer gerufenen inline-Routine
// braucht, steht nicht umsonst im uses, ohne sie bettet dcc nicht ein (H2443).
//
// Was der Rumpf braucht, merkt sich der Index je inline-Routine
// (TIndexSymbol.InlineRefs); die Verweise werden im Bereich der deklarierenden
// Unit aufgelöst. Erfasst werden Aufrufe, Properties mit inline-Getter bzw.
// -Setter und for-in über einen Typ mit inline-GetEnumerator, MoveNext oder
// Current.
//
// Ein Verweis auf einen Alias einer Deklaration aus System (System.TypInfo:
// TTypeKind = System.TTypeKind, tkRecord = System.TTypeKind.tkRecord) braucht
// die Unit des Alias nicht: dcc löst ihn auf System auf. Eingebaute Typen,
// Intrinsics und System zählen nicht als Verweis nach außen.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Was eine inline-Routine aus Sicht ihrer Unit braucht.</summary>
  TInlineNeeds = record
    /// <summary>Units, die der Rumpf benutzt (ohne System und die eigene Unit).</summary>
    Units: TArray<string>;
    /// <summary>Verweist der Rumpf auf etwas außerhalb seiner Unit, das nicht eingebaut ist und nicht aus System
    /// stammt? Unaufgelöste Verweise zählen mit (H2456, H2457).</summary>
    External: Boolean;
  end;

  /// <summary>Gerufene inline-Routine samt ihrer Unit.</summary>
  TInlineCallee = record
    Symbol: TIndexSymbol;
    OwnerUnit: TUnitIndex;
  end;

  /// <summary>Findet gerufene inline-Routinen einer Datei und was ihr Rumpf braucht. Der Resolver der Datei gehört
  /// dem Aufrufer, der ihn vor Prepare pinnt.</summary>
  TInlineCallees = class
  private
    FIndex: ISymbolIndex;
    FFacts: IIndexNameFacts;
    FNamespaces: TArray<string>;
    FResolver: TNameResolver;
    // Eigener Resolver für die Seite der gerufenen Unit: ResolveNameFrom setzt den Zustand zurück.
    FCallee: TNameResolver;
    FNeeds: TDictionary<string, TInlineNeeds>;
    FCandidates: TDictionary<string, Boolean>;
    // inline-Routinen der eigenen Unit als "container.name" (klein) und alle Namen, die dort Kandidaten sind.
    FOwnInline: TDictionary<string, Boolean>;
    FOwnCandidates: TDictionary<string, Boolean>;
    FOwn: TUnitIndex;
    FOwnName: string;
    /// <summary>Ist AResolved ein Alias einer Deklaration aus System oder SysInit (tkRecord =
    /// System.TTypeKind.tkRecord)?</summary>
    function IsImplicitAlias(const AResolved: TResolvedSymbol): Boolean;
    /// <summary>Unit der Deklaration AResolved, wenn sie zählt (nicht eingebaut, kein Alias aus System); ''
    /// sonst.</summary>
    function UnitOfResolved(const AResolved: TResolvedSymbol): string;
    /// <summary>Unit, auf die der Verweis ARef im Rumpf von ACallee zeigt; '' ohne. AExternal: Verweis nach
    /// außen, der sich nicht auflösen lässt. AOwner: Klasse von ACallee, wenn AHasOwner.</summary>
    function RefUnit(const ACallee: TInlineCallee; const ARef: string; AHasOwner: Boolean;
      const AOwner: TResolvedSymbol; var AExternal: Boolean): string;
    function HasInlineAccessor(const AProperty: TIndexSymbol): Boolean;
    /// <summary>Füllt FOwnInline und FOwnCandidates aus den Symbolen der eigenen Unit.</summary>
    procedure CollectOwnCandidates;
    /// <summary>Getter (AWrite False) bzw. Setter der Property ACallee, wenn er eine Methode desselben Typs ist.
    /// </summary>
    function Accessor(const ACallee: TInlineCallee; AWrite: Boolean; out AResult: TInlineCallee): Boolean;
    /// <summary>Der Enumerator AEnumerator (Ergebnis von GetEnumerator): MoveNext und der Getter von Current,
    /// soweit bekannt.</summary>
    function EnumeratorCallees(const AEnumerator: TInlineCallee): TArray<TInlineCallee>;
  public
    constructor Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ATreeUnits: ITreeUnits;
      const ANamespaces: TArray<string>; const AFacts: IIndexNameFacts; AResolver: TNameResolver);
    destructor Destroy; override;
    /// <summary>Eigene Unit (aus dem Baum der Datei, TNameResolver.ExtractedUnit) und ihr Name; vor allen
    /// Abfragen.</summary>
    procedure Prepare(const AOwn: TUnitIndex; const AOwnName: string);
    /// <summary>Nennt AName die Unit AOwnName, auch über die Namespaces ANamespaces?</summary>
    class function SameUnit(const AName, AOwnName: string; const ANamespaces: TArray<string>): Boolean; static;
    /// <summary>Ist AName die geprüfte Unit?</summary>
    function IsOwnUnit(const AName: string): Boolean;
    /// <summary>Einbettbare inline-Routine, deren Rumpf auf nichts außerhalb ihrer Unit verweist (#1381)?</summary>
    class function IsWithoutRefs(const ASymbol: TIndexSymbol): Boolean; static;
    /// <summary>Vorfilter: Gibt es im Index oder in der Datei eine gleichnamige inline-Routine mit Verweisen,
    /// oder eine Property, deren Getter oder Setter eine ist?</summary>
    function IsCandidate(const AName: string): Boolean;
    /// <summary>Indexsymbol der Deklaration AResolved samt Unit; False, wenn es keins gibt.</summary>
    function CalleeOf(const AResolved: TResolvedSymbol; out ACallee: TInlineCallee): Boolean;
    /// <summary>Gerufene Routine am Bezeichner ATokenIndex aus ATokens, der zu AResolved aufgelöst ist: Routine
    /// oder Methode, bei einer Property ihr Getter bzw. (bei Zuweisung) ihr Setter. False sonst.</summary>
    function CalleeAt(const AResolved: TResolvedSymbol; const ATokens: TArray<TPascalToken>; ATokenIndex: Integer;
      out ACallee: TInlineCallee): Boolean;
    /// <summary>Gerufene Routinen eines for-in ANode (ForInStatement): GetEnumerator des Ausdrucks, dann MoveNext
    /// und der Getter von Current seines Enumerators. AExpr ist der Ausdruck hinter in; leer, wenn er sich nicht
    /// auflösen lässt.</summary>
    function ForInCallees(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
      out AExpr: TSyntaxNode): TArray<TInlineCallee>;
    /// <summary>Was der Rumpf von ACallee braucht, je Routine nur einmal ausgewertet.</summary>
    function NeedsOf(const ACallee: TInlineCallee): TInlineNeeds;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.NameFacts,
  Atlas.Common.Semantics.UnresolvedNames;

const
  cImplicitUnits: array[0..1] of string = ('System', 'SysInit');
  cEnumeratorMembers: array[0..1] of string = ('MoveNext', 'Current');

/// <summary>Wort hinter read bzw. write im Kopf einer Property; '' ohne.</summary>
function AccessorName(const ASignature: string; AWrite: Boolean): string;
var
  mWords: TArray<string>;
  mIndex: Integer;
  mKeyword: string;
begin
  Result := '';
  if AWrite then
  begin
    mKeyword := 'write';
  end
  else
  begin
    mKeyword := 'read';
  end;
  mWords := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mWords) - 1 do
  begin
    if SameText(mWords[mIndex], mKeyword) then
    begin
      Exit(mWords[mIndex + 1]);
    end;
  end;
end;

/// <summary>Gibt es im Index eine inline-Routine AName mit Verweisen oder eine Property AName, deren Getter bzw.
/// Setter im selben Typ eine ist? Hängt nur vom Index ab und wird über alle Units gemerkt (TIndexNameFacts); die
/// eigene Datei prüft der Aufrufer.</summary>
function IndexInlineCandidate(const AFacts: IIndexNameFacts; const AIndex: ISymbolIndex;
  const AName: string): Boolean;
var
  mIndex: ISymbolIndex;
  mName: string;
begin
  mIndex := AIndex;
  mName := AName;
  Result := TIndexNameFacts.Get(AFacts, mIndex, 'inlineCandidate:' + UpperCase(mName),
    function: Integer
    begin
      Result := Ord(mIndex.HasSymbol(mName,
        function(const ASymbol: TIndexSymbol): Boolean
        var
          mAccessor, mContainer: string;
          mWrite: Boolean;
        begin
          Result := ASymbol.InlineRefs <> nil;
          if Result or (ASymbol.Kind <> TIndexSymbolKind.Property_) then
          begin
            Exit;
          end;
          mContainer := ASymbol.Container;
          for mWrite := False to True do
          begin
            mAccessor := AccessorName(ASymbol.Signature, mWrite);
            if (mAccessor <> '') and mIndex.HasSymbol(mAccessor,
              function(const AOther: TIndexSymbol): Boolean
              begin
                Result := (AOther.InlineRefs <> nil) and SameText(AOther.Container, mContainer);
              end) then
            begin
              Exit(True);
            end;
          end;
        end));
    end) <> 0;
end;

/// <summary>Ausdruck hinter in; Kinder: [Typ der Variablen], Ausdruck, [Anweisung]. nil ohne.</summary>
function ForInExpression(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  Result := ANode[0];
  if Result.Kind = TSyntaxKind.TypeReference then
  begin
    Result := nil;
    if ANode.ChildCount >= 2 then
    begin
      Result := ANode[1];
    end;
  end;
end;

{ TInlineCallees }

constructor TInlineCallees.Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
  const ATreeUnits: ITreeUnits; const ANamespaces: TArray<string>; const AFacts: IIndexNameFacts;
  AResolver: TNameResolver);
begin
  inherited Create;
  FIndex := AIndex;
  FFacts := AFacts;
  FNamespaces := ANamespaces;
  FResolver := AResolver;
  FCallee := TNameResolver.Create(AIndex, AEnsureUnit, ATreeUnits);
  FCallee.Namespaces := ANamespaces;
  FNeeds := TDictionary<string, TInlineNeeds>.Create;
  FCandidates := TDictionary<string, Boolean>.Create;
  FOwnInline := TDictionary<string, Boolean>.Create;
  FOwnCandidates := TDictionary<string, Boolean>.Create;
end;

destructor TInlineCallees.Destroy;
begin
  FOwnCandidates.Free;
  FOwnInline.Free;
  FCandidates.Free;
  FNeeds.Free;
  FCallee.Free;
  inherited;
end;

procedure TInlineCallees.Prepare(const AOwn: TUnitIndex; const AOwnName: string);
begin
  FOwn := AOwn;
  FOwnName := AOwnName;
  FOwnInline.Clear;
  FOwnCandidates.Clear;
  FCandidates.Clear;
  CollectOwnCandidates;
end;

class function TInlineCallees.SameUnit(const AName, AOwnName: string; const ANamespaces: TArray<string>): Boolean;
var
  mNamespace: string;
begin
  if SameText(AName, AOwnName) then
  begin
    Exit(True);
  end;
  for mNamespace in ANamespaces do
  begin
    if SameText(mNamespace + '.' + AName, AOwnName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TInlineCallees.IsOwnUnit(const AName: string): Boolean;
begin
  Result := SameUnit(AName, FOwnName, FNamespaces);
end;

class function TInlineCallees.IsWithoutRefs(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (Length(ASymbol.InlineRefs) = 1) and (ASymbol.InlineRefs[0] = TIndexSymbol.cInlineWithoutRefs);
end;

function TInlineCallees.IsImplicitAlias(const AResolved: TResolvedSymbol): Boolean;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mTarget: string;
  mEquals: Integer;
begin
  Result := False;
  if not (AResolved.SymbolKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.TypeAlias]) or
    not FCallee.DeclaringUnit(AResolved, mUnit) then
  begin
    Exit;
  end;
  for mSymbol in mUnit.Symbols do
  begin
    if (mSymbol.SelectionRange.StartPos = AResolved.SelectionRange.StartPos) and
      SameText(mSymbol.Name, AResolved.Name) then
    begin
      // Signatur "tkRecord = System.TTypeKind.tkRecord" bzw. "TTypeKind = System.TTypeKind".
      mEquals := mSymbol.Signature.IndexOf('=');
      if mEquals < 0 then
      begin
        Exit;
      end;
      mTarget := mSymbol.Signature.Substring(mEquals + 1).Trim;
      if mTarget.EndsWith(';') then
      begin
        mTarget := mTarget.Substring(0, mTarget.Length - 1).TrimRight;
      end;
      Exit((StartsText('System.', mTarget) or StartsText('SysInit.', mTarget)) and
        (mTarget.IndexOfAny([' ', '(', '[', '+', '-', '*', '<']) < 0));
    end;
  end;
end;

function TInlineCallees.UnitOfResolved(const AResolved: TResolvedSymbol): string;
begin
  Result := '';
  if not AResolved.Builtin and (AResolved.Kind = TResolvedKind.Symbol) and not IsImplicitAlias(AResolved) then
  begin
    Result := AResolved.UnitName;
  end;
end;

function TInlineCallees.RefUnit(const ACallee: TInlineCallee; const ARef: string; AHasOwner: Boolean;
  const AOwner: TResolvedSymbol; var AExternal: Boolean): string;
var
  mResolved, mMember: TResolvedSymbol;
begin
  Result := '';
  if ARef[1] = ':' then
  begin
    if FCallee.ResolveTypeTextFrom(ACallee.OwnerUnit, Copy(ARef, 2, MaxInt), mResolved) then
    begin
      Result := UnitOfResolved(mResolved);
    end
    else
    begin
      AExternal := True;
    end;
    Exit;
  end;
  // Mitglieder der eigenen Klasse samt Vorfahren gehören nicht zu den Units; ist die Klasse unbekannt, lässt
  // sich das nicht ausschließen.
  if (ACallee.Symbol.Container <> '') and (not AHasOwner or FCallee.DeclaredMember(AOwner, ARef, mMember)) then
  begin
    Exit;
  end;
  if FCallee.ResolveNameFrom(ACallee.OwnerUnit, ARef, mResolved) then
  begin
    Result := UnitOfResolved(mResolved);
  end
  // Eingebaute Typen (Integer(...)) und Intrinsics (SizeOf, Length) löst der Index nicht auf.
  else if not TResolverText.IsBuiltinTypeName(ARef) and not TUnresolvedNames.IsIntrinsic(ARef) then
  begin
    AExternal := True;
  end;
end;

function TInlineCallees.NeedsOf(const ACallee: TInlineCallee): TInlineNeeds;
var
  mKey, mRef, mUnitName: string;
  mOwner: TResolvedSymbol;
  mHasOwner: Boolean;
  mUnits: TList<string>;
begin
  mKey := UpperCase(ACallee.OwnerUnit.UnitName + '|' + ACallee.Symbol.QualifiedName + '|' +
    IntToStr(ACallee.Symbol.SelectionRange.StartPos.Line));
  if FNeeds.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := Default(TInlineNeeds);
  mOwner := Default(TResolvedSymbol);
  mHasOwner := (ACallee.Symbol.Container <> '') and
    FCallee.ResolveTypeFrom(ACallee.OwnerUnit, ACallee.Symbol.Container, mOwner);
  mUnits := TList<string>.Create;
  try
    for mRef in ACallee.Symbol.InlineRefs do
    begin
      // strict private-Mitglied der eigenen Klasse: Delphi 13 bettet trotzdem ein (#1383, Cm.H2440b).
      if (mRef = '') or (mRef[1] = '!') then
      begin
        Continue;
      end;
      mUnitName := RefUnit(ACallee, mRef, mHasOwner, mOwner, Result.External);
      if (mUnitName = '') or SameText(mUnitName, ACallee.OwnerUnit.UnitName) or
        (IndexText(mUnitName, cImplicitUnits) >= 0) then
      begin
        Continue;
      end;
      Result.External := True;
      if mUnits.IndexOf(mUnitName) < 0 then
      begin
        mUnits.Add(mUnitName);
      end;
    end;
    Result.Units := mUnits.ToArray;
  finally
    mUnits.Free;
  end;
  FNeeds.Add(mKey, Result);
end;

function TInlineCallees.HasInlineAccessor(const AProperty: TIndexSymbol): Boolean;
var
  mName, mContainer: string;
  mAccessors: TArray<string>;
begin
  mContainer := AProperty.Container;
  Result := False;
  mAccessors := [AccessorName(AProperty.Signature, False), AccessorName(AProperty.Signature, True)];
  for mName in mAccessors do
  begin
    if mName <> '' then
    begin
      if FIndex.HasSymbol(mName,
        function(const AOther: TIndexSymbol): Boolean
        begin
          Result := (AOther.InlineRefs <> nil) and SameText(AOther.Container, mContainer);
        end) then
      begin
        Exit(True);
      end;
      if FOwnInline.ContainsKey(LowerCase(mContainer + '.' + mName)) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

procedure TInlineCallees.CollectOwnCandidates;
var
  mSymbol: TIndexSymbol;
begin
  // Einmal je Unit statt je Bezeichner über alle Symbole der Datei: Units mit vielen Symbolen und vielen
  // verschiedenen Namen (Atlas.UI.Settings.Page) brauchten sonst Sekunden.
  for mSymbol in FOwn.Symbols do
  begin
    if mSymbol.InlineRefs <> nil then
    begin
      FOwnInline.AddOrSetValue(LowerCase(mSymbol.Container + '.' + mSymbol.Name), True);
      FOwnCandidates.AddOrSetValue(LowerCase(mSymbol.Name), True);
    end;
  end;
  for mSymbol in FOwn.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Property_) and not FOwnCandidates.ContainsKey(LowerCase(mSymbol.Name)) and
      HasInlineAccessor(mSymbol) then
    begin
      FOwnCandidates.AddOrSetValue(LowerCase(mSymbol.Name), True);
    end;
  end;
end;

function TInlineCallees.IsCandidate(const AName: string): Boolean;
begin
  // Vorfilter wie deprecated-symbol: Gibt es im Index oder in der Datei eine gleichnamige inline-Routine mit
  // Verweisen, oder eine Property, deren Getter oder Setter eine ist?
  if FCandidates.TryGetValue(LowerCase(AName), Result) then
  begin
    Exit;
  end;
  if FOwnCandidates.ContainsKey(LowerCase(AName)) then
  begin
    Result := True;
  end
  // Ohne inline-Routinen in der eigenen Datei hängt die Antwort nur vom Index ab: über alle Units gemerkt.
  else if FOwnInline.Count = 0 then
  begin
    Result := IndexInlineCandidate(FFacts, FIndex, AName);
  end
  else
  begin
    Result := FIndex.HasSymbol(AName,
      function(const ASymbol: TIndexSymbol): Boolean
      begin
        Result := (ASymbol.InlineRefs <> nil) or
          ((ASymbol.Kind = TIndexSymbolKind.Property_) and HasInlineAccessor(ASymbol));
      end);
  end;
  FCandidates.Add(LowerCase(AName), Result);
end;

function TInlineCallees.CalleeOf(const AResolved: TResolvedSymbol; out ACallee: TInlineCallee): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  if not AResolved.Found or (AResolved.Kind <> TResolvedKind.Symbol) then
  begin
    Exit;
  end;
  // Routinen der eigenen Unit stehen im Index der Datei, nicht im (womöglich älteren) Projektindex.
  if IsOwnUnit(AResolved.UnitName) then
  begin
    ACallee.OwnerUnit := FOwn;
  end
  else if not FResolver.DeclaringUnit(AResolved, ACallee.OwnerUnit) then
  begin
    Exit;
  end
  else if IsOwnUnit(ACallee.OwnerUnit.UnitName) then
  begin
    ACallee.OwnerUnit := FOwn;
  end;
  for mSymbol in ACallee.OwnerUnit.Symbols do
  begin
    if (mSymbol.SelectionRange.StartPos = AResolved.SelectionRange.StartPos) and SameText(mSymbol.Name, AResolved.Name)
      and SameText(mSymbol.Container, AResolved.Container) then
    begin
      ACallee.Symbol := mSymbol;
      Exit(True);
    end;
  end;
end;

function TInlineCallees.Accessor(const ACallee: TInlineCallee; AWrite: Boolean; out AResult: TInlineCallee): Boolean;
var
  mName: string;
  mSymbol: TIndexSymbol;
begin
  Result := False;
  mName := AccessorName(ACallee.Symbol.Signature, AWrite);
  if (mName = '') or (Pos('.', mName) > 0) then
  begin
    Exit;
  end;
  for mSymbol in ACallee.OwnerUnit.Symbols do
  begin
    if SameText(mSymbol.Name, mName) and SameText(mSymbol.Container, ACallee.Symbol.Container) and
      (mSymbol.Kind = TIndexSymbolKind.Method) and mSymbol.InInterface then
    begin
      AResult.OwnerUnit := ACallee.OwnerUnit;
      AResult.Symbol := mSymbol;
      Exit(True);
    end;
  end;
end;

function TInlineCallees.CalleeAt(const AResolved: TResolvedSymbol; const ATokens: TArray<TPascalToken>;
  ATokenIndex: Integer; out ACallee: TInlineCallee): Boolean;
var
  mCallee: TInlineCallee;
  mNext: Integer;
  mIsWrite: Boolean;
begin
  Result := False;
  if not CalleeOf(AResolved, mCallee) then
  begin
    Exit;
  end;
  if mCallee.Symbol.Kind = TIndexSymbolKind.Property_ then
  begin
    // Zuweisung an die Property ruft den Setter, sonst liest sie über den Getter.
    mNext := ATokenIndex + 1;
    while (mNext <= High(ATokens)) and (ATokens[mNext].Kind in [TPascalTokenKind.Comment,
      TPascalTokenKind.Directive]) do
    begin
      Inc(mNext);
    end;
    mIsWrite := (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol(':=');
    Result := Accessor(mCallee, mIsWrite, ACallee);
  end
  else if mCallee.Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine] then
  begin
    ACallee := mCallee;
    Result := True;
  end;
end;

function TInlineCallees.EnumeratorCallees(const AEnumerator: TInlineCallee): TArray<TInlineCallee>;
var
  mEnumType, mMember: TResolvedSymbol;
  mTarget, mGetter: TInlineCallee;
  mName: string;
begin
  Result := nil;
  if (AEnumerator.Symbol.TypeName = '') or
    not FCallee.ResolveTypeTextFrom(AEnumerator.OwnerUnit, AEnumerator.Symbol.TypeName, mEnumType) then
  begin
    Exit;
  end;
  for mName in cEnumeratorMembers do
  begin
    if not FCallee.DeclaredMember(mEnumType, mName, mMember) or not CalleeOf(mMember, mTarget) then
    begin
      Continue;
    end;
    if mTarget.Symbol.Kind = TIndexSymbolKind.Property_ then
    begin
      if not Accessor(mTarget, False, mGetter) then
      begin
        Continue;
      end;
      mTarget := mGetter;
    end;
    Result := Result + [mTarget];
  end;
end;

function TInlineCallees.ForInCallees(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out AExpr: TSyntaxNode): TArray<TInlineCallee>;
var
  mSymbol, mTypeInfo, mMember: TResolvedSymbol;
  mTypeFound: Boolean;
  mCallee: TInlineCallee;
begin
  Result := nil;
  AExpr := ForInExpression(ANode);
  if (AExpr = nil) or not FResolver.NodeType(ATree, AFileName, AExpr, mSymbol, mTypeInfo, mTypeFound) or
    not mTypeFound or (mTypeInfo.Kind <> TResolvedKind.Symbol) then
  begin
    Exit;
  end;
  if not FResolver.FindMember(mTypeInfo, 'GetEnumerator', mMember) or not CalleeOf(mMember, mCallee) then
  begin
    Exit;
  end;
  Result := [mCallee] + EnumeratorCallees(mCallee);
end;

end.
