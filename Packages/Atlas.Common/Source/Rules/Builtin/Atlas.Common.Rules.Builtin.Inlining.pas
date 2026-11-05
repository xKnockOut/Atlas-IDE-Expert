unit Atlas.Common.Rules.Builtin.Inlining;

// Regel inline-not-expanded (#1017, Gruppe Compiler vorab): Aufruf einer
// inline-Routine, die der Compiler hier nicht einbettet.
//   H2443  Der Rumpf braucht eine Unit, die hier nicht in uses steht (typisch
//          System.Generics.Collections bei TJSONObject.Count).
//   (H2444 nicht: Auf strict private- und private-Mitglieder aus einer
//          anderen Unit bettet Delphi 13 ohne Meldung ein, #1383.)
//   Alle Fälle gibt es nur unitübergreifend.
//   H2445  Die aufrufende Routine ist selbst inline, und die Unit der
//          gerufenen steht nur im uses des implementation-Teils.
//   H2456  Die Unit der Routine verwendet die übersetzte Unit (Zyklus).
//   H2457  Ebenso über andere Units (indirekter Zyklus).
//          Beide nur, wenn der Rumpf auf etwas außerhalb seiner Unit
//          verweist: Sonst schweigt Delphi 13 je nach Reihenfolge der
//          Übersetzung (Cm.H2456, Cm.H2457; #1381, #1383).
//
// Was der Rumpf braucht, merkt sich der Index je inline-Routine
// (TIndexSymbol.InlineRefs); die Regel löst die Verweise im Bereich der
// deklarierenden Unit auf. Gemeldet wird nur, was sicher aufgelöst ist:
// Verweise, die der Index nicht kennt, und geerbte Mitglieder aus fremden
// Units bleiben stumm. Erfasst werden Aufrufe, Properties mit inline-Getter
// bzw. -Setter und for-in über einen Typ mit inline-GetEnumerator, MoveNext
// oder Current. Mit {$INLINE OFF} in der Datei schweigt die Regel, ebenso
// ohne Projektindex (inline-Routinen der Datei selbst meldet sie nicht).
//
// Ein Verweis auf einen Alias einer Deklaration aus System (System.TypInfo:
// TTypeKind = System.TTypeKind, tkRecord = System.TTypeKind.tkRecord) braucht
// die Unit des Alias nicht: dcc löst ihn auf System auf. Sonst meldete die
// Regel bei jedem TList<T>.Add und TStack<T>.Push „System.TypInfo fehlt“.
// Für H2456/H2457 zählen eingebaute Typen, Intrinsics und System nicht als
// Verweis (THashFNV1a32.GetHashValue mit Integer(...) in
// System.Generics.Defaults).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  InlineNotExpandedRuleId = 'inline-not-expanded';

type
  TInlineNotExpandedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterInliningRules(ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Index.NameFacts,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInliningText = (ImplUses, AddUses, MissingUnit, MissingUnits, CompiledUnit, CompiledUnitIndirect, Title);

const
  cTexts: array[TInliningText] of TAtlasText = (
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s steht nur im uses des implementation-Teils, und die ' +
      'aufrufende Routine ist selbst inline (wie H2445).';
     En: 'Inline function %s is not expanded: %s is only in the uses of the implementation section, and the calling ' +
      'routine is itself inline (like H2445).'),
    (De: 'uses %s ergänzen'; En: 'Add uses %s'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s fehlt in uses (wie H2443).';
     En: 'Inline function %s is not expanded: %s is missing in uses (like H2443).'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s fehlen in uses (wie H2443).';
     En: 'Inline function %s is not expanded: %s are missing in uses (like H2443).'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s verwendet die übersetzte Unit %s (wie H2456).';
     En: 'Inline function %s is not expanded: %s uses the compiled unit %s (like H2456).'),
    (De: 'Inline-Funktion %s wird nicht eingebettet: %s verwendet die übersetzte Unit %s indirekt über %s (wie H2457).';
     En: 'Inline function %s is not expanded: %s uses the compiled unit %s indirectly via %s (like H2457).'),
    (De: 'Inline-Funktion wird nicht eingebettet (wie H2443, H2445, H2456, H2457)';
     En: 'Inline function is not expanded (like H2443, H2445, H2456, H2457)'));

{$SCOPEDENUMS OFF}

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

  /// <summary>Zyklen zwischen gerufenen Units und der eigenen über die uses-Listen im Index.</summary>
  TInlineCycles = class
  private
    FIndex: ISymbolIndex;
    FNamespaces: TArray<string>;
    FOwnName: string;
    // Zyklus je gerufener Unit (#1220): '' ohne, CycleDirect für H2456, sonst die Unit für H2457. Die Breitensuche
    // lief vorher bei jedem Aufruf neu und machte die Regel auf Units mit vielen inline-Aufrufen sekundenlang.
    FCycles: TDictionary<string, string>;
    /// <summary>Unit aus dem Index, auch über die Namespaces; ohne Nachladen.</summary>
    function FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function UsesOwnUnit(const AUnit: TUnitIndex): Boolean;
    /// <summary>Unit, über die AUnit die eigene Unit indirekt verwendet; '' ohne Zyklus.</summary>
    function IndirectVia(const AUnit: TUnitIndex): string;
  public
    constructor Create(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>);
    destructor Destroy; override;
    function IsOwnUnit(const AName: string): Boolean;
    /// <summary>Zyklus zwischen AUnit und der eigenen Unit, je Unit nur einmal gesucht.</summary>
    function CycleOf(const AUnit: TUnitIndex): string;
    /// <summary>Name der geprüften Unit.</summary>
    property OwnName: string read FOwnName write FOwnName;
  end;

  TInlineCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    // Projektindex oder, ohne ihn, ein leerer: Dann kennt die Prüfung nur die Datei selbst.
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    // Eigener Resolver für die Seite der gerufenen Unit: ResolveNameFrom setzt den Zustand zurück.
    FCallee: TNameResolver;
    FNeeds: TDictionary<string, TInlineNeeds>;
    FCandidates: TDictionary<string, Boolean>;
    // inline-Routinen der eigenen Unit als "container.name" (klein) und alle Namen, die dort Kandidaten sind.
    FOwnInline: TDictionary<string, Boolean>;
    FOwnCandidates: TDictionary<string, Boolean>;
    FReported: TDictionary<Integer, Boolean>;
    FCycles: TInlineCycles;
    FOwn: TUnitIndex;
    FOwnName: string;
    FUsed: TArray<string>;
    FLineBreak: string;
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
    function NeedsOf(const ACallee: TInlineCallee): TInlineNeeds;
    function HasInlineAccessor(const AProperty: TIndexSymbol): Boolean;
    /// <summary>Füllt FOwnInline und FOwnCandidates aus den Symbolen der eigenen Unit.</summary>
    procedure CollectOwnCandidates;
    function IsCandidate(const AName: string): Boolean;
    function IndexSymbolOf(const AResolved: TResolvedSymbol; out ACallee: TInlineCallee): Boolean;
    function Accessor(const ACallee: TInlineCallee; AWrite: Boolean; out AResult: TInlineCallee): Boolean;
    function EnclosingRoutines(AOffset: Integer): TArray<TSyntaxNode>;
    function CallerIsInline(const ARoutines: TArray<TSyntaxNode>): Boolean;
    function OnlyInImplementationUses(const AUnitName: string): Boolean;
    /// <summary>Meldung zu ACallee an ARange, wenn der Compiler ihn nicht einbettet; True bei Treffer.</summary>
    function Report(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
    /// <summary>Meldet, warum ACallee nicht eingebettet wird; False, wenn nichts dagegen spricht.</summary>
    function Explain(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
    /// <summary>H2456/H2457: Zyklus zwischen der Unit von ACallee und der eigenen; True bei Meldung.</summary>
    function ReportedCycle(const ACallee: TInlineCallee; const ANeeds: TInlineNeeds;
      const ARange: TTextRange): Boolean;
    procedure CheckToken(ATokenIndex: Integer);
    /// <summary>Der Enumerator ACallee (GetEnumerator): MoveNext und der Getter von Current.</summary>
    procedure CheckEnumerator(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer);
    procedure CheckForIn(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

const
  ImplicitUnits: array[0..1] of string = ('System', 'SysInit');
  /// <summary>Höchstzahl der Units, die die Suche nach einem indirekten Zyklus besucht.</summary>
  MaxCycleUnits = 400;
  EnumeratorMembers: array[0..1] of string = ('MoveNext', 'Current');
  /// <summary>Ergebnis von CycleOf, wenn die Unit die eigene direkt verwendet; kein gültiger Unit-Name.</summary>
  CycleDirect = '=';

/// <summary>Einbettbare inline-Routine, deren Rumpf auf nichts außerhalb ihrer Unit verweist (#1381)?</summary>
function IsWithoutRefs(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (Length(ASymbol.InlineRefs) = 1) and (ASymbol.InlineRefs[0] = TIndexSymbol.InlineWithoutRefs);
end;

function SplitName(const AQualified: string; out AContainer: string): string;
var
  Dot: Integer;
begin
  Dot := AQualified.LastIndexOf('.');
  if Dot < 0 then
  begin
    AContainer := '';
    Exit(AQualified);
  end;
  AContainer := AQualified.Substring(0, Dot);
  Result := AQualified.Substring(Dot + 1);
end;

/// <summary>Wort hinter read bzw. write im Kopf einer Property; '' ohne.</summary>
function AccessorName(const ASignature: string; AWrite: Boolean): string;
var
  Words: TArray<string>;
  Index: Integer;
  Keyword: string;
begin
  Result := '';
  if AWrite then
  begin
    Keyword := 'write';
  end
  else
  begin
    Keyword := 'read';
  end;
  Words := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 1 do
  begin
    if SameText(Words[Index], Keyword) then
    begin
      Exit(Words[Index + 1]);
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

constructor TInlineCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FIndex := AContext.Index;
  if FIndex = nil then
  begin
    FIndex := TSymbolIndex.Create;
  end;
  FResolver := TNameResolver.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FCallee := TNameResolver.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits);
  FCallee.Namespaces := AContext.Namespaces;
  FNeeds := TDictionary<string, TInlineNeeds>.Create;
  FCandidates := TDictionary<string, Boolean>.Create;
  FOwnInline := TDictionary<string, Boolean>.Create;
  FOwnCandidates := TDictionary<string, Boolean>.Create;
  FReported := TDictionary<Integer, Boolean>.Create;
  FCycles := TInlineCycles.Create(FIndex, AContext.Namespaces);
end;

destructor TInlineCheck.Destroy;
begin
  FCycles.Free;
  FReported.Free;
  FOwnCandidates.Free;
  FOwnInline.Free;
  FCandidates.Free;
  FNeeds.Free;
  FCallee.Free;
  FResolver.Free;
  inherited;
end;

{ TInlineCycles }

constructor TInlineCycles.Create(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>);
begin
  inherited Create;
  FIndex := AIndex;
  FNamespaces := ANamespaces;
  FCycles := TDictionary<string, string>.Create;
end;

destructor TInlineCycles.Destroy;
begin
  FCycles.Free;
  inherited;
end;

function TInlineCycles.IsOwnUnit(const AName: string): Boolean;
var
  Namespace: string;
begin
  if SameText(AName, FOwnName) then
  begin
    Exit(True);
  end;
  for Namespace in FNamespaces do
  begin
    if SameText(Namespace + '.' + AName, FOwnName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TInlineCycles.FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Namespace: string;
begin
  if FIndex.FindUnit(AName, AUnit) then
  begin
    Exit(True);
  end;
  for Namespace in FNamespaces do
  begin
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TInlineCycles.UsesOwnUnit(const AUnit: TUnitIndex): Boolean;
var
  Name: string;
begin
  for Name in AUnit.InterfaceUses + AUnit.ImplementationUses do
  begin
    if IsOwnUnit(Name) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TInlineCycles.IndirectVia(const AUnit: TUnitIndex): string;
var
  Names, Vias: TQueue<string>;
  Seen: TDictionary<string, Boolean>;
  Current: TUnitIndex;
  Name, Via: string;
begin
  // Breitensuche über die uses-Listen der Units im Index; Vias hält zu jedem Namen den direkten Nachbarn von
  // AUnit, über den der Weg läuft. Nur Units, die der Index schon kennt: Nachladen wäre zu teuer, und ohne sie
  // gibt es keine sichere Aussage (dann keine Meldung).
  Result := '';
  Names := TQueue<string>.Create;
  Vias := TQueue<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Seen.Add(UpperCase(AUnit.UnitName), True);
    for Name in AUnit.InterfaceUses + AUnit.ImplementationUses do
    begin
      Names.Enqueue(Name);
      Vias.Enqueue(Name);
    end;
    while (Names.Count > 0) and (Seen.Count < MaxCycleUnits) do
    begin
      Name := Names.Dequeue;
      Via := Vias.Dequeue;
      if IsOwnUnit(Name) or not FindIndexedUnit(Name, Current) or Seen.ContainsKey(UpperCase(Current.UnitName)) then
      begin
        Continue;
      end;
      Seen.Add(UpperCase(Current.UnitName), True);
      for Name in Current.InterfaceUses + Current.ImplementationUses do
      begin
        if IsOwnUnit(Name) then
        begin
          Exit(Via);
        end;
        Names.Enqueue(Name);
        Vias.Enqueue(Via);
      end;
    end;
  finally
    Seen.Free;
    Vias.Free;
    Names.Free;
  end;
end;

function TInlineCycles.CycleOf(const AUnit: TUnitIndex): string;
var
  mKey: string;
begin
  mKey := UpperCase(AUnit.UnitName);
  if FCycles.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  if UsesOwnUnit(AUnit) then
  begin
    Result := CycleDirect;
  end
  else
  begin
    Result := IndirectVia(AUnit);
  end;
  FCycles.Add(mKey, Result);
end;

{ TInlineCheck }

function TInlineCheck.IsImplicitAlias(const AResolved: TResolvedSymbol): Boolean;
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

function TInlineCheck.UnitOfResolved(const AResolved: TResolvedSymbol): string;
begin
  Result := '';
  if not AResolved.Builtin and (AResolved.Kind = TResolvedKind.Symbol) and not IsImplicitAlias(AResolved) then
  begin
    Result := AResolved.UnitName;
  end;
end;

function TInlineCheck.RefUnit(const ACallee: TInlineCallee; const ARef: string; AHasOwner: Boolean;
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

function TInlineCheck.NeedsOf(const ACallee: TInlineCallee): TInlineNeeds;
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
        (IndexText(mUnitName, ImplicitUnits) >= 0) then
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

function TInlineCheck.HasInlineAccessor(const AProperty: TIndexSymbol): Boolean;
var
  Name, mContainer: string;
  Accessors: TArray<string>;
begin
  mContainer := AProperty.Container;
  Result := False;
  Accessors := [AccessorName(AProperty.Signature, False), AccessorName(AProperty.Signature, True)];
  for Name in Accessors do
  begin
    if Name <> '' then
    begin
      if FIndex.HasSymbol(Name,
        function(const AOther: TIndexSymbol): Boolean
        begin
          Result := (AOther.InlineRefs <> nil) and SameText(AOther.Container, mContainer);
        end) then
      begin
        Exit(True);
      end;
      if FOwnInline.ContainsKey(LowerCase(mContainer + '.' + Name)) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

procedure TInlineCheck.CollectOwnCandidates;
var
  Symbol: TIndexSymbol;
begin
  // Einmal je Unit statt je Bezeichner über alle Symbole der Datei: Units mit vielen Symbolen und vielen
  // verschiedenen Namen (Atlas.UI.Settings.Page) brauchten sonst Sekunden.
  for Symbol in FOwn.Symbols do
  begin
    if Symbol.InlineRefs <> nil then
    begin
      FOwnInline.AddOrSetValue(LowerCase(Symbol.Container + '.' + Symbol.Name), True);
      FOwnCandidates.AddOrSetValue(LowerCase(Symbol.Name), True);
    end;
  end;
  for Symbol in FOwn.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.Property_) and not FOwnCandidates.ContainsKey(LowerCase(Symbol.Name)) and
      HasInlineAccessor(Symbol) then
    begin
      FOwnCandidates.AddOrSetValue(LowerCase(Symbol.Name), True);
    end;
  end;
end;

function TInlineCheck.IsCandidate(const AName: string): Boolean;
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
    Result := IndexInlineCandidate(FContext.NameFacts, FIndex, AName);
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

function TInlineCheck.IndexSymbolOf(const AResolved: TResolvedSymbol; out ACallee: TInlineCallee): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  if not AResolved.Found or (AResolved.Kind <> TResolvedKind.Symbol) then
  begin
    Exit;
  end;
  // Routinen der eigenen Unit stehen im Index der Datei, nicht im (womöglich älteren) Projektindex.
  if FCycles.IsOwnUnit(AResolved.UnitName) then
  begin
    ACallee.OwnerUnit := FOwn;
  end
  else if not FResolver.DeclaringUnit(AResolved, ACallee.OwnerUnit) then
  begin
    Exit;
  end
  else if FCycles.IsOwnUnit(ACallee.OwnerUnit.UnitName) then
  begin
    ACallee.OwnerUnit := FOwn;
  end;
  for Symbol in ACallee.OwnerUnit.Symbols do
  begin
    if (Symbol.SelectionRange.StartPos = AResolved.SelectionRange.StartPos) and SameText(Symbol.Name, AResolved.Name)
      and SameText(Symbol.Container, AResolved.Container) then
    begin
      ACallee.Symbol := Symbol;
      Exit(True);
    end;
  end;
end;

function TInlineCheck.Accessor(const ACallee: TInlineCallee; AWrite: Boolean; out AResult: TInlineCallee): Boolean;
var
  Name: string;
  Symbol: TIndexSymbol;
begin
  Result := False;
  Name := AccessorName(ACallee.Symbol.Signature, AWrite);
  if (Name = '') or (Pos('.', Name) > 0) then
  begin
    Exit;
  end;
  for Symbol in ACallee.OwnerUnit.Symbols do
  begin
    if SameText(Symbol.Name, Name) and SameText(Symbol.Container, ACallee.Symbol.Container) and
      (Symbol.Kind = TIndexSymbolKind.Method) and Symbol.InInterface then
    begin
      AResult.OwnerUnit := ACallee.OwnerUnit;
      AResult.Symbol := Symbol;
      Exit(True);
    end;
  end;
end;

function TInlineCheck.EnclosingRoutines(AOffset: Integer): TArray<TSyntaxNode>;
var
  Node: TSyntaxNode;
  Index: Integer;
  Found: Boolean;
begin
  // Von außen nach innen: Methode, dann ihre lokalen Routinen.
  Result := nil;
  Node := FContext.Tree.Root;
  repeat
    Found := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if (Node[Index].StartOffset <= AOffset) and (AOffset < Node[Index].EndOffset) then
      begin
        Node := Node[Index];
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Result := Result + [Node];
        end;
        Found := True;
        Break;
      end;
    end;
  until not Found;
end;

function TInlineCheck.CallerIsInline(const ARoutines: TArray<TSyntaxNode>): Boolean;
var
  Routine, Header: TSyntaxNode;
  Index: Integer;
  Name, Container: string;
  Symbol: TIndexSymbol;
begin
  Result := False;
  if Length(ARoutines) = 0 then
  begin
    Exit;
  end;
  Routine := ARoutines[High(ARoutines)];
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  if Header <> nil then
  begin
    for Index := 0 to Header.ChildCount - 1 do
    begin
      if (Header[Index].Kind = TSyntaxKind.Directive) and SameText(Header[Index].Name, 'inline') then
      begin
        Exit(True);
      end;
    end;
  end;
  // inline steht oft nur an der Deklaration.
  Name := SplitName(Routine.Name, Container);
  for Symbol in FOwn.Symbols do
  begin
    if SameText(Symbol.Name, Name) and SameText(Symbol.Container, Container) and Symbol.HasDirective('inline') then
    begin
      Exit(True);
    end;
  end;
end;

function TInlineCheck.OnlyInImplementationUses(const AUnitName: string): Boolean;
begin
  Result := TUsesClauses.IsUsed(FOwn.ImplementationUses, AUnitName, FContext.Namespaces) and
    not TUsesClauses.IsUsed(FOwn.InterfaceUses, AUnitName, FContext.Namespaces);
end;

function TInlineCheck.Report(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
begin
  Result := False;
  if (ACallee.Symbol.InlineRefs = nil) or FReported.ContainsKey(AOffset) then
  begin
    Exit;
  end;
  Result := Explain(ACallee, ARange, AOffset);
  if Result then
  begin
    FReported.Add(AOffset, True);
  end;
end;

function TInlineCheck.Explain(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
var
  Needs: TInlineNeeds;
  Name, Missing: string;
  Routines: TArray<TSyntaxNode>;
  Missings: TArray<string>;
  UnitName: string;
  Edit: TTextEdit;
  Fixes: TArray<TRuleFix>;
begin
  Result := False;
  Name := ACallee.Symbol.QualifiedName;
  Routines := EnclosingRoutines(AOffset);
  Needs := NeedsOf(ACallee);
  // In derselben Unit sind uses, Zyklen und der implementation-Teil dieselben.
  if FCycles.IsOwnUnit(ACallee.OwnerUnit.UnitName) then
  begin
    Exit;
  end;
  // Zyklen zuerst: Dann bettet der Compiler gar nicht ein, gleich was in uses steht.
  if ReportedCycle(ACallee, Needs, ARange) then
  begin
    Exit(True);
  end;
  // Die billige Frage nach dem uses zuerst: CallerIsInline durchsucht die Symbole der Datei.
  if OnlyInImplementationUses(ACallee.OwnerUnit.UnitName) and CallerIsInline(Routines) then
  begin
    FReport.Add(ARange, cTexts[TInliningText.ImplUses].Fmt([Name, ACallee.OwnerUnit.UnitName]));
    Exit(True);
  end;
  Missings := nil;
  for UnitName in Needs.Units do
  begin
    if not FCycles.IsOwnUnit(UnitName) and not TUsesClauses.IsUsed(FUsed, UnitName, FContext.Namespaces) then
    begin
      Missings := Missings + [UnitName];
    end;
  end;
  if Length(Missings) = 0 then
  begin
    Exit;
  end;
  Missing := String.Join(', ', Missings);
  Fixes := nil;
  if TUsesClauses.AddUnit(FContext.Tree.Tokens, AOffset, Missing, FLineBreak, Edit) then
  begin
    Fixes := [TRuleFix.Create(cTexts[TInliningText.AddUses].Fmt([Missing]), [Edit], True)];
  end;
  if Length(Missings) = 1 then
  begin
    FReport.Add(ARange, cTexts[TInliningText.MissingUnit].Fmt([Name, Missing]), Fixes);
  end
  else
  begin
    FReport.Add(ARange, cTexts[TInliningText.MissingUnits].Fmt([Name, Missing]), Fixes);
  end;
  Result := True;
end;

function TInlineCheck.ReportedCycle(const ACallee: TInlineCallee; const ANeeds: TInlineNeeds;
  const ARange: TTextRange): Boolean;
var
  mCycle, mName: string;
begin
  // Nur bei Rümpfen mit Verweisen wie vor #1381: Ob dcc H2456/H2457 meldet, hängt von der Reihenfolge der
  // Übersetzung ab; bei Cm.H2456 und Cm.H2457 (Rumpf ohne Verweise, die Unit des Falls zuerst übersetzt) schweigt
  // Delphi 13 (#1383). Eingebaute Typen und System zählen nicht als Verweis (Integer(...) in
  // THashFNV1a32.GetHashValue).
  mCycle := '';
  if not IsWithoutRefs(ACallee.Symbol) and ANeeds.External then
  begin
    mCycle := FCycles.CycleOf(ACallee.OwnerUnit);
  end;
  mName := ACallee.Symbol.QualifiedName;
  Result := mCycle <> '';
  if mCycle = CycleDirect then
  begin
    FReport.Add(ARange, cTexts[TInliningText.CompiledUnit].Fmt([mName, ACallee.OwnerUnit.UnitName, FOwnName]));
  end
  else if Result then
  begin
    FReport.Add(ARange, cTexts[TInliningText.CompiledUnitIndirect].Fmt([mName, ACallee.OwnerUnit.UnitName, FOwnName,
      mCycle]));
  end;
end;

procedure TInlineCheck.CheckToken(ATokenIndex: Integer);
var
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  Resolved: TResolvedSymbol;
  Callee, Target: TInlineCallee;
  Next: Integer;
  IsWrite: Boolean;
begin
  Tokens := FContext.Tree.Tokens;
  Token := Tokens[ATokenIndex];
  if not IsCandidate(Token.Text) then
  begin
    Exit;
  end;
  Resolved := FResolver.Resolve(FContext.Tree, FContext.RelativePath, Token.StartPos);
  if not IndexSymbolOf(Resolved, Callee) then
  begin
    Exit;
  end;
  if Callee.Symbol.Kind = TIndexSymbolKind.Property_ then
  begin
    // Zuweisung an die Property ruft den Setter, sonst liest sie über den Getter.
    Next := ATokenIndex + 1;
    while (Next <= High(Tokens)) and (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    begin
      Inc(Next);
    end;
    IsWrite := (Next <= High(Tokens)) and Tokens[Next].IsSymbol(':=');
    if not Accessor(Callee, IsWrite, Target) then
    begin
      Exit;
    end;
    Callee := Target;
  end
  else if not (Callee.Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
  begin
    Exit;
  end;
  Report(Callee, TTextRange.Create(Token.StartPos, Token.EndPos), Token.Offset);
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

procedure TInlineCheck.CheckEnumerator(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer);
var
  mEnumType, mMember: TResolvedSymbol;
  mTarget, mGetter: TInlineCallee;
  mName: string;
begin
  if (ACallee.Symbol.TypeName = '') or
    not FCallee.ResolveTypeTextFrom(ACallee.OwnerUnit, ACallee.Symbol.TypeName, mEnumType) then
  begin
    Exit;
  end;
  for mName in EnumeratorMembers do
  begin
    if not FCallee.DeclaredMember(mEnumType, mName, mMember) or not IndexSymbolOf(mMember, mTarget) then
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
    if Report(mTarget, ARange, AOffset) then
    begin
      Exit;
    end;
  end;
end;

procedure TInlineCheck.CheckForIn(ANode: TSyntaxNode);
var
  mExpr: TSyntaxNode;
  mSymbol, mTypeInfo, mMember: TResolvedSymbol;
  mTypeFound: Boolean;
  mCallee: TInlineCallee;
  mRange: TTextRange;
begin
  mExpr := ForInExpression(ANode);
  if (mExpr = nil) or not FResolver.NodeType(FContext.Tree, FContext.RelativePath, mExpr, mSymbol, mTypeInfo,
    mTypeFound) or not mTypeFound or (mTypeInfo.Kind <> TResolvedKind.Symbol) then
  begin
    Exit;
  end;
  if not FResolver.FindMember(mTypeInfo, 'GetEnumerator', mMember) or not IndexSymbolOf(mMember, mCallee) then
  begin
    Exit;
  end;
  mRange := TTextRange.Create(mExpr.StartPos, mExpr.EndPos);
  // Der Enumerator: MoveNext und der Getter von Current.
  if not Report(mCallee, mRange, mExpr.StartOffset) then
  begin
    CheckEnumerator(mCallee, mRange, mExpr.StartOffset);
  end;
end;

procedure TInlineCheck.Run;
var
  Index: Integer;
  ForIns: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  FOwnName := TUsesClauses.OwnName(FContext.Tree.Tokens);
  if FOwnName = '' then
  begin
    FOwnName := FContext.UnitName;
  end;
  FCycles.OwnName := FOwnName;
  FUsed := TUsesClauses.UsedUnits(FContext.Tree.Tokens);
  FLineBreak := TTextLines.LineBreakOf(FContext.Text);
  FResolver.PinTree(FContext.Tree, FContext.RelativePath);
  try
    FOwn := FResolver.ExtractedUnit(FContext.Tree, FContext.RelativePath);
    CollectOwnCandidates;
    for Index := 0 to High(FContext.Tree.Tokens) do
    begin
      if FContext.Tree.Tokens[Index].Kind = TPascalTokenKind.Identifier then
      begin
        CheckToken(Index);
      end;
    end;
    ForIns := TList<TSyntaxNode>.Create;
    try
      FContext.Tree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := True;
          if ANode.Kind = TSyntaxKind.ForInStatement then
          begin
            ForIns.Add(ANode);
          end;
        end);
      for Node in ForIns do
      begin
        CheckForIn(Node);
      end;
    finally
      ForIns.Free;
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

{ TInlineNotExpandedRule }

function TInlineNotExpandedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(InlineNotExpandedRuleId, TRuleSeverity.Hint,
    cTexts[TInliningText.Title].Text);
end;

procedure TInlineNotExpandedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TInlineCheck;
begin
  if (AContext.Tree = nil) or ContainsText(AContext.Text, '{$INLINE OFF}') then
  begin
    Exit;
  end;
  Check := TInlineCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

procedure RegisterInliningRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInlineNotExpandedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inlining', cTexts);

end.
