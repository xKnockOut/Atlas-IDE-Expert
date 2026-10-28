unit Atlas.Common.Rules.Builtin.Inlining;

// Regel inline-not-expanded (#1017, Gruppe Compiler vorab): Aufruf einer
// inline-Routine, die der Compiler hier nicht einbettet.
//   H2443  Der Rumpf braucht eine Unit, die hier nicht in uses steht (typisch
//          System.Generics.Collections bei TJSONObject.Count).
//   H2444  Der Rumpf greift auf ein strict private-Mitglied seiner Klasse zu,
//          und der Aufruf steht nicht in einer Methode dieser Klasse; auch
//          in derselben Unit. Alle anderen Fälle gibt es nur unitübergreifend.
//   H2445  Die aufrufende Routine ist selbst inline, und die Unit der
//          gerufenen steht nur im uses des implementation-Teils.
//   H2456  Die Unit der Routine verwendet die übersetzte Unit (Zyklus).
//   H2457  Ebenso über andere Units (indirekter Zyklus).
//
// Was der Rumpf braucht, merkt sich der Index je inline-Routine
// (TIndexSymbol.InlineRefs); die Regel löst die Verweise im Bereich der
// deklarierenden Unit auf. Gemeldet wird nur, was sicher aufgelöst ist:
// Verweise, die der Index nicht kennt, und geerbte Mitglieder aus fremden
// Units bleiben stumm. Erfasst werden Aufrufe, Properties mit inline-Getter
// bzw. -Setter und for-in über einen Typ mit inline-GetEnumerator, MoveNext
// oder Current. Mit {$INLINE OFF} in der Datei schweigt die Regel. Ohne
// Projektindex prüft sie nur die inline-Routinen der Datei selbst.

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
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Was eine inline-Routine aus Sicht ihrer Unit braucht.</summary>
  TInlineNeeds = record
    /// <summary>Units, die der Rumpf benutzt (ohne System und die eigene Unit).</summary>
    Units: TArray<string>;
    /// <summary>strict private-Mitglieder der eigenen Klasse, die der Rumpf benutzt.</summary>
    StrictPrivate: TArray<string>;
  end;

  /// <summary>Gerufene inline-Routine samt ihrer Unit.</summary>
  TInlineCallee = record
    Symbol: TIndexSymbol;
    OwnerUnit: TUnitIndex;
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
    FReported: TDictionary<Integer, Boolean>;
    FOwn: TUnitIndex;
    FOwnName: string;
    FUsed: TArray<string>;
    FLineBreak: string;
    function IsOwnUnit(const AName: string): Boolean;
    /// <summary>Unit aus dem Index, auch über die Namespaces; ohne Nachladen.</summary>
    function FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    function UsesOwnUnit(const AUnit: TUnitIndex): Boolean;
    /// <summary>Unit, über die AUnit die eigene Unit indirekt verwendet; '' ohne Zyklus.</summary>
    function IndirectVia(const AUnit: TUnitIndex): string;
    function NeedsOf(const ACallee: TInlineCallee): TInlineNeeds;
    function HasInlineAccessor(const AProperty: TIndexSymbol): Boolean;
    function IsCandidate(const AName: string): Boolean;
    function IndexSymbolOf(const AResolved: TResolvedSymbol; out ACallee: TInlineCallee): Boolean;
    function Accessor(const ACallee: TInlineCallee; AWrite: Boolean; out AResult: TInlineCallee): Boolean;
    function EnclosingRoutines(AOffset: Integer): TArray<TSyntaxNode>;
    function CallerIsInline(const ARoutines: TArray<TSyntaxNode>): Boolean;
    function CallerClass(const ARoutines: TArray<TSyntaxNode>): string;
    function OnlyInImplementationUses(const AUnitName: string): Boolean;
    /// <summary>Meldung zu ACallee an ARange, wenn der Compiler ihn nicht einbettet; True bei Treffer.</summary>
    function Report(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
    /// <summary>Meldet, warum ACallee nicht eingebettet wird; False, wenn nichts dagegen spricht.</summary>
    function Explain(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
    procedure CheckToken(ATokenIndex: Integer);
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
    Keyword := 'write'
  else
    Keyword := 'read';
  Words := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 1 do
    if SameText(Words[Index], Keyword) then
      Exit(Words[Index + 1]);
end;

{ TInlineCheck }

constructor TInlineCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FIndex := AContext.Index;
  if FIndex = nil then
    FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FCallee := TNameResolver.Create(FIndex, AContext.EnsureUnit, AContext.TreeUnits);
  FCallee.Namespaces := AContext.Namespaces;
  FNeeds := TDictionary<string, TInlineNeeds>.Create;
  FCandidates := TDictionary<string, Boolean>.Create;
  FReported := TDictionary<Integer, Boolean>.Create;
end;

destructor TInlineCheck.Destroy;
begin
  FReported.Free;
  FCandidates.Free;
  FNeeds.Free;
  FCallee.Free;
  FResolver.Free;
  inherited;
end;

function TInlineCheck.IsOwnUnit(const AName: string): Boolean;
var
  Namespace: string;
begin
  if SameText(AName, FOwnName) then
    Exit(True);
  for Namespace in FContext.Namespaces do
    if SameText(Namespace + '.' + AName, FOwnName) then
      Exit(True);
  Result := False;
end;

function TInlineCheck.FindIndexedUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  Namespace: string;
begin
  if FIndex.FindUnit(AName, AUnit) then
    Exit(True);
  for Namespace in FContext.Namespaces do
    if FIndex.FindUnit(Namespace + '.' + AName, AUnit) then
      Exit(True);
  Result := False;
end;

function TInlineCheck.UsesOwnUnit(const AUnit: TUnitIndex): Boolean;
var
  Name: string;
begin
  for Name in AUnit.InterfaceUses + AUnit.ImplementationUses do
    if IsOwnUnit(Name) then
      Exit(True);
  Result := False;
end;

function TInlineCheck.IndirectVia(const AUnit: TUnitIndex): string;
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
        Continue;
      Seen.Add(UpperCase(Current.UnitName), True);
      for Name in Current.InterfaceUses + Current.ImplementationUses do
      begin
        if IsOwnUnit(Name) then
          Exit(Via);
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

function TInlineCheck.NeedsOf(const ACallee: TInlineCallee): TInlineNeeds;
var
  Key, Ref, Container, UnitName: string;
  Owner, Resolved, Member: TResolvedSymbol;
  HasOwner: Boolean;
  Units: TList<string>;
begin
  Key := UpperCase(ACallee.OwnerUnit.UnitName + '|' + ACallee.Symbol.QualifiedName + '|' +
    IntToStr(ACallee.Symbol.SelectionRange.StartPos.Line));
  if FNeeds.TryGetValue(Key, Result) then
    Exit;
  Result := Default(TInlineNeeds);
  Container := ACallee.Symbol.Container;
  HasOwner := (Container <> '') and FCallee.ResolveTypeFrom(ACallee.OwnerUnit, Container, Owner);
  Units := TList<string>.Create;
  try
    for Ref in ACallee.Symbol.InlineRefs do
    begin
      if Ref = '' then
        Continue;
      UnitName := '';
      if Ref[1] = '!' then
      begin
        Result.StrictPrivate := Result.StrictPrivate + [Copy(Ref, 2, MaxInt)];
        Continue;
      end;
      if Ref[1] = ':' then
      begin
        if FCallee.ResolveTypeTextFrom(ACallee.OwnerUnit, Copy(Ref, 2, MaxInt), Resolved) and
          not Resolved.Builtin and (Resolved.Kind = TResolvedKind.Symbol) then
          UnitName := Resolved.UnitName;
      end
      else
      begin
        // Mitglieder der eigenen Klasse samt Vorfahren gehören nicht zu den Units; ist die Klasse unbekannt,
        // lässt sich das nicht ausschließen.
        if Container <> '' then
        begin
          if not HasOwner or FCallee.DeclaredMember(Owner, Ref, Member) then
            Continue;
        end;
        if FCallee.ResolveNameFrom(ACallee.OwnerUnit, Ref, Resolved) and not Resolved.Builtin and
          (Resolved.Kind = TResolvedKind.Symbol) then
          UnitName := Resolved.UnitName;
      end;
      if (UnitName = '') or SameText(UnitName, ACallee.OwnerUnit.UnitName) or
        (IndexText(UnitName, ImplicitUnits) >= 0) then
        Continue;
      if Units.IndexOf(UnitName) < 0 then
        Units.Add(UnitName);
    end;
    Result.Units := Units.ToArray;
  finally
    Units.Free;
  end;
  FNeeds.Add(Key, Result);
end;

function TInlineCheck.HasInlineAccessor(const AProperty: TIndexSymbol): Boolean;
var
  Name: string;
  Accessors: TArray<string>;
  Other: TSymbolLocation;
  Symbol: TIndexSymbol;
begin
  Result := False;
  Accessors := [AccessorName(AProperty.Signature, False), AccessorName(AProperty.Signature, True)];
  for Name in Accessors do
    if Name <> '' then
    begin
      for Other in FIndex.FindSymbols(Name) do
        if (Other.Symbol.InlineRefs <> nil) and SameText(Other.Symbol.Container, AProperty.Container) then
          Exit(True);
      for Symbol in FOwn.Symbols do
        if (Symbol.InlineRefs <> nil) and SameText(Symbol.Name, Name) and
          SameText(Symbol.Container, AProperty.Container) then
          Exit(True);
    end;
end;

function TInlineCheck.IsCandidate(const AName: string): Boolean;
var
  Location: TSymbolLocation;
  Symbol: TIndexSymbol;
begin
  // Vorfilter wie deprecated-symbol: Gibt es im Index oder in der Datei eine gleichnamige inline-Routine mit
  // Verweisen, oder eine Property, deren Getter oder Setter eine ist?
  if FCandidates.TryGetValue(LowerCase(AName), Result) then
    Exit;
  Result := False;
  for Location in FIndex.FindSymbols(AName) do
    if (Location.Symbol.InlineRefs <> nil) or
      ((Location.Symbol.Kind = TIndexSymbolKind.Property_) and HasInlineAccessor(Location.Symbol)) then
    begin
      Result := True;
      Break;
    end;
  if not Result then
    for Symbol in FOwn.Symbols do
      if SameText(Symbol.Name, AName) and ((Symbol.InlineRefs <> nil) or
        ((Symbol.Kind = TIndexSymbolKind.Property_) and HasInlineAccessor(Symbol))) then
      begin
        Result := True;
        Break;
      end;
  FCandidates.Add(LowerCase(AName), Result);
end;

function TInlineCheck.IndexSymbolOf(const AResolved: TResolvedSymbol; out ACallee: TInlineCallee): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  if not AResolved.Found or (AResolved.Kind <> TResolvedKind.Symbol) then
    Exit;
  // Routinen der eigenen Unit stehen im Index der Datei, nicht im (womöglich älteren) Projektindex.
  if IsOwnUnit(AResolved.UnitName) then
    ACallee.OwnerUnit := FOwn
  else if not FResolver.DeclaringUnit(AResolved, ACallee.OwnerUnit) then
    Exit
  else if IsOwnUnit(ACallee.OwnerUnit.UnitName) then
    ACallee.OwnerUnit := FOwn;
  for Symbol in ACallee.OwnerUnit.Symbols do
    if (Symbol.SelectionRange.StartPos = AResolved.SelectionRange.StartPos) and SameText(Symbol.Name, AResolved.Name)
      and SameText(Symbol.Container, AResolved.Container) then
    begin
      ACallee.Symbol := Symbol;
      Exit(True);
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
    Exit;
  for Symbol in ACallee.OwnerUnit.Symbols do
    if SameText(Symbol.Name, Name) and SameText(Symbol.Container, ACallee.Symbol.Container) and
      (Symbol.Kind = TIndexSymbolKind.Method) and Symbol.InInterface then
    begin
      AResult.OwnerUnit := ACallee.OwnerUnit;
      AResult.Symbol := Symbol;
      Exit(True);
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
      if (Node[Index].StartOffset <= AOffset) and (AOffset < Node[Index].EndOffset) then
      begin
        Node := Node[Index];
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Result := Result + [Node];
        Found := True;
        Break;
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
    Exit;
  Routine := ARoutines[High(ARoutines)];
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  if Header <> nil then
    for Index := 0 to Header.ChildCount - 1 do
      if (Header[Index].Kind = TSyntaxKind.Directive) and SameText(Header[Index].Name, 'inline') then
        Exit(True);
  // inline steht oft nur an der Deklaration.
  Name := SplitName(Routine.Name, Container);
  for Symbol in FOwn.Symbols do
    if SameText(Symbol.Name, Name) and SameText(Symbol.Container, Container) and Symbol.HasDirective('inline') then
      Exit(True);
end;

function TInlineCheck.CallerClass(const ARoutines: TArray<TSyntaxNode>): string;
begin
  Result := '';
  if Length(ARoutines) > 0 then
    SplitName(ARoutines[0].Name, Result);
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
    Exit;
  Result := Explain(ACallee, ARange, AOffset);
  if Result then
    FReported.Add(AOffset, True);
end;

function TInlineCheck.Explain(const ACallee: TInlineCallee; const ARange: TTextRange; AOffset: Integer): Boolean;
var
  Needs: TInlineNeeds;
  Name, Via, Member, Missing: string;
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
  // In derselben Unit bleibt nur H2444: uses, Zyklen und der implementation-Teil sind dort dieselben.
  if IsOwnUnit(ACallee.OwnerUnit.UnitName) then
  begin
    if (Length(Needs.StrictPrivate) > 0) and not SameText(CallerClass(Routines), ACallee.Symbol.Container) then
    begin
      FReport.Add(ARange, Format('Inline-Funktion %s wird nicht eingebettet: Zugriff auf %s.%s (strict private) ' +
        'ist hier nicht möglich (wie H2444).', [Name, ACallee.Symbol.Container, Needs.StrictPrivate[0]]));
      Exit(True);
    end;
    Exit;
  end;
  // Zyklen zuerst: Dann bettet der Compiler gar nicht ein, gleich was in uses steht.
  if UsesOwnUnit(ACallee.OwnerUnit) then
  begin
    FReport.Add(ARange, Format('Inline-Funktion %s wird nicht eingebettet: %s verwendet die übersetzte Unit %s ' +
      '(wie H2456).', [Name, ACallee.OwnerUnit.UnitName, FOwnName]));
    Exit(True);
  end;
  Via := IndirectVia(ACallee.OwnerUnit);
  if Via <> '' then
  begin
    FReport.Add(ARange, Format('Inline-Funktion %s wird nicht eingebettet: %s verwendet die übersetzte Unit %s ' +
      'indirekt über %s (wie H2457).', [Name, ACallee.OwnerUnit.UnitName, FOwnName, Via]));
    Exit(True);
  end;
  if CallerIsInline(Routines) and OnlyInImplementationUses(ACallee.OwnerUnit.UnitName) then
  begin
    FReport.Add(ARange, Format('Inline-Funktion %s wird nicht eingebettet: %s steht nur im uses des ' +
      'implementation-Teils, und die aufrufende Routine ist selbst inline (wie H2445).',
      [Name, ACallee.OwnerUnit.UnitName]));
    Exit(True);
  end;
  if (Length(Needs.StrictPrivate) > 0) and not SameText(CallerClass(Routines), ACallee.Symbol.Container) then
  begin
    Member := Needs.StrictPrivate[0];
    FReport.Add(ARange, Format('Inline-Funktion %s wird nicht eingebettet: Zugriff auf %s.%s (strict private) ' +
      'ist hier nicht möglich (wie H2444).', [Name, ACallee.Symbol.Container, Member]));
    Exit(True);
  end;
  Missings := nil;
  for UnitName in Needs.Units do
    if not IsOwnUnit(UnitName) and not TUsesClauses.IsUsed(FUsed, UnitName, FContext.Namespaces) then
      Missings := Missings + [UnitName];
  if Length(Missings) = 0 then
    Exit;
  Missing := String.Join(', ', Missings);
  Fixes := nil;
  if TUsesClauses.AddUnit(FContext.Tree.Tokens, AOffset, Missing, FLineBreak, Edit) then
    Fixes := [TRuleFix.Create(Format('uses %s ergänzen', [Missing]), [Edit], True)];
  if Length(Missings) = 1 then
    FReport.Add(ARange, Format('Inline-Funktion %s wird nicht eingebettet: %s fehlt in uses (wie H2443).',
      [Name, Missing]), Fixes)
  else
    FReport.Add(ARange, Format('Inline-Funktion %s wird nicht eingebettet: %s fehlen in uses (wie H2443).',
      [Name, Missing]), Fixes);
  Result := True;
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
    Exit;
  Resolved := FResolver.Resolve(FContext.Tree, FContext.RelativePath, Token.StartPos);
  if not IndexSymbolOf(Resolved, Callee) then
    Exit;
  if Callee.Symbol.Kind = TIndexSymbolKind.Property_ then
  begin
    // Zuweisung an die Property ruft den Setter, sonst liest sie über den Getter.
    Next := ATokenIndex + 1;
    while (Next <= High(Tokens)) and (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Inc(Next);
    IsWrite := (Next <= High(Tokens)) and Tokens[Next].IsSymbol(':=');
    if not Accessor(Callee, IsWrite, Target) then
      Exit;
    Callee := Target;
  end
  else if not (Callee.Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
    Exit;
  Report(Callee, TTextRange.Create(Token.StartPos, Token.EndPos), Token.Offset);
end;

procedure TInlineCheck.CheckForIn(ANode: TSyntaxNode);
var
  Expr: TSyntaxNode;
  Symbol, TypeInfo, Member, EnumType: TResolvedSymbol;
  TypeFound: Boolean;
  Callee, Target, Getter: TInlineCallee;
  Range: TTextRange;
  Name: string;
begin
  // Kinder: [Typ der Variablen], Ausdruck, [Anweisung].
  if ANode.ChildCount = 0 then
    Exit;
  Expr := ANode[0];
  if Expr.Kind = TSyntaxKind.TypeReference then
  begin
    if ANode.ChildCount < 2 then
      Exit;
    Expr := ANode[1];
  end;
  if not FResolver.NodeType(FContext.Tree, FContext.RelativePath, Expr, Symbol, TypeInfo, TypeFound) or
    not TypeFound or (TypeInfo.Kind <> TResolvedKind.Symbol) then
    Exit;
  if not FResolver.FindMember(TypeInfo, 'GetEnumerator', Member) or not IndexSymbolOf(Member, Callee) then
    Exit;
  Range := TTextRange.Create(Expr.StartPos, Expr.EndPos);
  if Report(Callee, Range, Expr.StartOffset) then
    Exit;
  // Der Enumerator: MoveNext und der Getter von Current.
  if (Callee.Symbol.TypeName = '') or
    not FCallee.ResolveTypeTextFrom(Callee.OwnerUnit, Callee.Symbol.TypeName, EnumType) then
    Exit;
  for Name in EnumeratorMembers do
    if FCallee.DeclaredMember(EnumType, Name, Member) and IndexSymbolOf(Member, Target) then
    begin
      if Target.Symbol.Kind = TIndexSymbolKind.Property_ then
      begin
        if not Accessor(Target, False, Getter) then
          Continue;
        Target := Getter;
      end;
      if Report(Target, Range, Expr.StartOffset) then
        Exit;
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
    FOwnName := FContext.UnitName;
  FUsed := TUsesClauses.UsedUnits(FContext.Tree.Tokens);
  FLineBreak := TTextLines.LineBreakOf(FContext.Text);
  FResolver.PinTree(FContext.Tree, FContext.RelativePath);
  try
    FOwn := FResolver.ExtractedUnit(FContext.Tree, FContext.RelativePath);
    for Index := 0 to High(FContext.Tree.Tokens) do
      if FContext.Tree.Tokens[Index].Kind = TPascalTokenKind.Identifier then
        CheckToken(Index);
    ForIns := TList<TSyntaxNode>.Create;
    try
      FContext.Tree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := True;
          if ANode.Kind = TSyntaxKind.ForInStatement then
            ForIns.Add(ANode);
        end);
      for Node in ForIns do
        CheckForIn(Node);
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
    'Inline-Funktion wird nicht eingebettet (wie H2443, H2444, H2445, H2456, H2457)');
end;

procedure TInlineNotExpandedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TInlineCheck;
begin
  if (AContext.Tree = nil) or ContainsText(AContext.Text, '{$INLINE OFF}') then
    Exit;
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

end.
