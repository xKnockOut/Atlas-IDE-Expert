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
//
// Was dcc beim Einbetten außerdem verlangt (#2309, aus dem Delphi-13-Bau):
// - die Unit der Routine selbst, sobald ihr Rumpf Verweise hat: Wer
//   TListView.Columns.Count ohne System.Classes liest, bekommt H2443 für
//   TCollection.GetCount, auch ohne Vcl.ComCtrls im uses. Nicht bei System
//   und SysInit (stehen implizit im uses: TMonitor.Enter, Pos) und nicht bei
//   Mitgliedern generischer Typen (FListe[I] auf ein TObjectList<T>-Feld
//   braucht kein System.Generics.Collections);
// - die Unit hinter einem Alias als Ergebnistyp (TFont.GetStyle: TFontStyles =
//   System.UITypes.TFontStyles verlangt System.UITypes);
// - bei einem Feld eines instanziierten generischen Typs (FItems:
//   TList<TCollectionItem>) nicht die Unit des generischen Typs: Die
//   Instanz gehört der Unit der Routine. Erst ein inline-Mitglied der Instanz
//   (FElements[I] über TList<T>.GetItem) bringt dessen Bedarf mit, samt seiner
//   Unit (System.Generics.Collections bei TJSONArray.GetValue). Count liest in
//   Delphi 13 ein Feld (TJSONArray.GetCount braucht nichts weiter).

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
    /// <summary>Units, die der Aufrufer zum Einbetten braucht (ohne System): die des Rumpfs und, wenn der Rumpf
    /// Verweise hat, die eigene Unit der Routine.</summary>
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
    // Routinen, deren Bedarf gerade ermittelt wird: verschachtelte inline-Aufrufe können sich im Kreis rufen.
    FPending: TDictionary<string, Boolean>;
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
    /// außen, der sich nicht auflösen lässt. AOwner: Klasse von ACallee, wenn AHasOwner. Weitere Units (Bedarf
    /// eines inline-Mitglieds einer generischen Instanz) kommen nach AUnits.</summary>
    function RefUnit(const ACallee: TInlineCallee; const ARef: string; AHasOwner: Boolean;
      const AOwner: TResolvedSymbol; AUnits: TList<string>; var AExternal: Boolean): string;
    /// <summary>Bedarf des Verweises ":Typ#Mitglied" auf ein Feld eines instanziierten generischen Typs
    /// (TList&lt;TKunde&gt;): nur der eines inline-Mitglieds, samt dessen Unit. False, wenn das Mitglied unbekannt ist.
    /// </summary>
    function AddInstanceMemberNeeds(const ACallee: TInlineCallee; const AType: TResolvedSymbol;
      const AMember: string; AUnits: TList<string>): Boolean;
    /// <summary>Unit hinter dem Alias des Ergebnistyps von ACallee (TFontStyles = System.UITypes.TFontStyles);
    /// '' ohne.</summary>
    function ResultAliasUnit(const ACallee: TInlineCallee): string;
    /// <summary>Ziel des einfachen Typalias AResolved (TTextPosition = Atlas.Text.Lines.TTextPosition); False bei
    /// anderen Typen.</summary>
    function SimpleAliasTarget(const AResolved: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
    /// <summary>Braucht ein direkter Aufruf von ACallee dessen eigene Unit im uses? Nur bei einem Rumpf mit
    /// Verweisen, nicht für System und SysInit und nicht für Mitglieder generischer Typen.</summary>
    class function OwnUnitNeeded(const ACallee: TInlineCallee): Boolean; static;
    /// <summary>Gehört ACallee zu einem generischen Typ (auch über einen umgebenden Typ) oder ist selbst
    /// generisch?</summary>
    class function IsGenericMember(const ACallee: TInlineCallee): Boolean; static;
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
  FPending := TDictionary<string, Boolean>.Create;
  FCandidates := TDictionary<string, Boolean>.Create;
  FOwnInline := TDictionary<string, Boolean>.Create;
  FOwnCandidates := TDictionary<string, Boolean>.Create;
end;

destructor TInlineCallees.Destroy;
begin
  FOwnCandidates.Free;
  FOwnInline.Free;
  FCandidates.Free;
  FPending.Free;
  FNeeds.Free;
  FCallee.Free;
  inherited;
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
  const AOwner: TResolvedSymbol; AUnits: TList<string>; var AExternal: Boolean): string;
var
  mResolved, mMember, mTarget: TResolvedSymbol;
  mTypeText, mMemberName: string;
  mMark: Integer;
begin
  Result := '';
  if ARef[1] = ':' then
  begin
    mTypeText := Copy(ARef, 2, MaxInt);
    mMemberName := '';
    mMark := Pos(TIndexSymbol.cInlineMemberMark, mTypeText);
    if mMark > 0 then
    begin
      mMemberName := Copy(mTypeText, mMark + 1, MaxInt);
      mTypeText := Copy(mTypeText, 1, mMark - 1);
    end;
    if not FCallee.ResolveTypeTextFrom(ACallee.OwnerUnit, mTypeText, mResolved) then
    begin
      AExternal := True;
    end
    // Instanz eines generischen Typs: gehört der Unit der Routine; zählt nur ein inline-Mitglied.
    else if (Pos('<', mTypeText) > 0) and (mMemberName <> '') and not mResolved.Builtin then
    begin
      if not AddInstanceMemberNeeds(ACallee, mResolved, mMemberName, AUnits) then
      begin
        AExternal := True;
      end;
    end
    // Mitglied über einen Alias (A.Line bei A: TTextPosition = Atlas.Text.Lines.TTextPosition): dcc braucht die
    // Unit hinter dem Alias.
    else if (mMemberName <> '') and SimpleAliasTarget(mResolved, mTarget) then
    begin
      Result := UnitOfResolved(mTarget);
    end
    else
    begin
      Result := UnitOfResolved(mResolved);
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

function TInlineCallees.AddInstanceMemberNeeds(const ACallee: TInlineCallee; const AType: TResolvedSymbol;
  const AMember: string; AUnits: TList<string>): Boolean;
var
  mMember: TResolvedSymbol;
  mTypeUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mTarget, mGetter: TInlineCallee;
  mUnitName: string;
  mFound: Boolean;
begin
  mFound := False;
  if AMember = '[]' then
  begin
    // Default-Property des generischen Typs selbst (TList<T>.Items).
    if FCallee.DeclaringUnit(AType, mTypeUnit) then
    begin
      for mSymbol in mTypeUnit.Symbols do
      begin
        if not mFound and mSymbol.IsDefault and (mSymbol.Kind = TIndexSymbolKind.Property_) and
          SameText(mSymbol.Container, AType.QualifiedName) then
        begin
          mTarget.OwnerUnit := mTypeUnit;
          mTarget.Symbol := mSymbol;
          mFound := True;
        end;
      end;
    end;
  end
  else
  begin
    mFound := FCallee.DeclaredMember(AType, AMember, mMember) and CalleeOf(mMember, mTarget);
  end;
  Result := mFound;
  if not mFound then
  begin
    Exit;
  end;
  if mTarget.Symbol.Kind = TIndexSymbolKind.Property_ then
  begin
    // Ohne Getter-Methode (read FCount) ruft der Rumpf nichts.
    if not Accessor(mTarget, False, mGetter) then
    begin
      Exit;
    end;
    mTarget := mGetter;
  end;
  if (mTarget.Symbol.InlineRefs = nil) or SameText(mTarget.OwnerUnit.UnitName, ACallee.OwnerUnit.UnitName) then
  begin
    Exit;
  end;
  // Dessen Bedarf und, bei einem Rumpf mit Verweisen, seine Unit (TList<T>.GetItem: System.Generics.Collections).
  // Direkt gerufen braucht ein Mitglied eines generischen Typs seine Unit nicht (OwnUnitNeeded), aus dem
  // eingebetteten Rumpf einer anderen Unit heraus schon (TJSONArray.GetValue).
  for mUnitName in NeedsOf(mTarget).Units do
  begin
    if AUnits.IndexOf(mUnitName) < 0 then
    begin
      AUnits.Add(mUnitName);
    end;
  end;
  if not IsWithoutRefs(mTarget.Symbol) and (AUnits.IndexOf(mTarget.OwnerUnit.UnitName) < 0) then
  begin
    AUnits.Add(mTarget.OwnerUnit.UnitName);
  end;
end;

function TInlineCallees.SimpleAliasTarget(const AResolved: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mText: string;
  mEquals, mPosition: Integer;
begin
  Result := False;
  if AResolved.Builtin or (AResolved.SymbolKind <> TIndexSymbolKind.TypeAlias) or
    not FCallee.DeclaringUnit(AResolved, mUnit) then
  begin
    Exit;
  end;
  for mPosition in mUnit.SymbolsNamed(AResolved.Name) do
  begin
    mSymbol := mUnit.Symbols[mPosition];
    if (mSymbol.SelectionRange.StartPos = AResolved.SelectionRange.StartPos) and (mSymbol.Container = '') then
    begin
      // Signatur "TFontStyles = System.UITypes.TFontStyles;": nur einfache Aliase, keine eigenen Typen.
      mEquals := mSymbol.Signature.IndexOf('=');
      if mEquals < 0 then
      begin
        Exit;
      end;
      mText := mSymbol.Signature.Substring(mEquals + 1).Trim;
      if mText.EndsWith(';') then
      begin
        mText := mText.Substring(0, mText.Length - 1).TrimRight;
      end;
      Result := not StartsText('type ', mText) and (mText.IndexOfAny([' ', '(', '[', '<', '^']) < 0) and
        FCallee.ResolveTypeTextFrom(mUnit, mText, ATarget);
      Exit;
    end;
  end;
end;

function TInlineCallees.ResultAliasUnit(const ACallee: TInlineCallee): string;
var
  mResolved, mTarget: TResolvedSymbol;
begin
  Result := '';
  if (ACallee.Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
    (ACallee.Symbol.TypeName <> '') and (Pos('<', ACallee.Symbol.TypeName) = 0) and
    FCallee.ResolveTypeFrom(ACallee.OwnerUnit, ACallee.Symbol.TypeName, mResolved) and
    SimpleAliasTarget(mResolved, mTarget) then
  begin
    Result := UnitOfResolved(mTarget);
  end;
end;

class function TInlineCallees.OwnUnitNeeded(const ACallee: TInlineCallee): Boolean;
begin
  // System und SysInit stehen implizit in jedem uses (TMonitor.Enter, Pos, UpCase). Mitglieder generischer Typen
  // bettet dcc ohne ihre Unit ein: FListe[I] auf ein TObjectList<T>-Feld einer anderen Unit gibt in Delphi 13
  // kein H2443 für TList<T>.GetItem, auch ohne System.Generics.Collections im uses.
  Result := not IsWithoutRefs(ACallee.Symbol) and (IndexText(ACallee.OwnerUnit.UnitName, cImplicitUnits) < 0) and
    not IsGenericMember(ACallee);
end;

class function TInlineCallees.IsGenericMember(const ACallee: TInlineCallee): Boolean;
var
  mContainer, mName: string;
  mPosition, mDot: Integer;
  mSymbol: TIndexSymbol;
begin
  Result := ACallee.Symbol.TypeParams <> '';
  mContainer := ACallee.Symbol.Container;
  // Von innen nach außen: TDictionary.TKeyCollection gehört über TDictionary<TKey,TValue> zu einem generischen Typ.
  while not Result and (mContainer <> '') do
  begin
    mDot := mContainer.LastIndexOf('.');
    mName := mContainer.Substring(mDot + 1);
    if mDot < 0 then
    begin
      mContainer := '';
    end
    else
    begin
      mContainer := mContainer.Substring(0, mDot);
    end;
    for mPosition in ACallee.OwnerUnit.SymbolsNamed(mName) do
    begin
      mSymbol := ACallee.OwnerUnit.Symbols[mPosition];
      if SameText(mSymbol.Container, mContainer) and (mSymbol.TypeParams <> '') then
      begin
        Result := True;
      end;
    end;
  end;
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

function TInlineCallees.NeedsOf(const ACallee: TInlineCallee): TInlineNeeds;
var
  mKey, mRef, mUnitName: string;
  mOwner: TResolvedSymbol;
  mHasOwner: Boolean;
  mUnits: TList<string>;
  mIndex: Integer;
begin
  mKey := UpperCase(ACallee.OwnerUnit.UnitName + '|' + ACallee.Symbol.QualifiedName + '|' +
    IntToStr(ACallee.Symbol.SelectionRange.StartPos.Line));
  Result := Default(TInlineNeeds);
  if FNeeds.TryGetValue(mKey, Result) or FPending.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FPending.Add(mKey, True);
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
      mUnitName := RefUnit(ACallee, mRef, mHasOwner, mOwner, mUnits, Result.External);
      if (mUnitName <> '') and not SameText(mUnitName, ACallee.OwnerUnit.UnitName) and
        (mUnits.IndexOf(mUnitName) < 0) then
      begin
        mUnits.Add(mUnitName);
      end;
    end;
    mUnitName := ResultAliasUnit(ACallee);
    if (mUnitName <> '') and not SameText(mUnitName, ACallee.OwnerUnit.UnitName) and
      (mUnits.IndexOf(mUnitName) < 0) then
    begin
      mUnits.Add(mUnitName);
    end;
    // Units außerhalb der eigenen machen den Rumpf „extern“ (H2456, H2457); System und SysInit zählen nicht.
    for mIndex := mUnits.Count - 1 downto 0 do
    begin
      if (IndexText(mUnits[mIndex], cImplicitUnits) >= 0) or SameText(mUnits[mIndex], ACallee.OwnerUnit.UnitName) then
      begin
        mUnits.Delete(mIndex);
      end;
    end;
    Result.External := Result.External or (mUnits.Count > 0);
    // Mit Verweisen braucht der Aufrufer auch die Unit der Routine (TCollection.GetCount, #2309), außer System
    // und bei Mitgliedern generischer Typen (OwnUnitNeeded).
    if OwnUnitNeeded(ACallee) and (mUnits.IndexOf(ACallee.OwnerUnit.UnitName) < 0) then
    begin
      mUnits.Add(ACallee.OwnerUnit.UnitName);
    end;
    Result.Units := mUnits.ToArray;
  finally
    mUnits.Free;
    FPending.Remove(mKey);
  end;
  FNeeds.Add(mKey, Result);
end;

end.
