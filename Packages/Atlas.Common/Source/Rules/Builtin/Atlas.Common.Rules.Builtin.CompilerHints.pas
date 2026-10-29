unit Atlas.Common.Rules.Builtin.CompilerHints;

// Regel compiler-hints (#1381, Gruppe Compiler vorab): Hinweise und Warnungen
// des Compilers, die zu keiner anderen Regel gehören.
//   W1055  published in einer Klasse ohne RTTI: Der Compiler schaltet für sie
//          {$M+} ein. Gemeldet am ersten Mitglied hinter dem ersten
//          ausdrücklichen published (wie dcc), einmal je Klasse. Still bei
//          {$M+} bzw. {$TYPEINFO ON} an der Deklaration, bei einem Vorfahren
//          mit RTTI (bekannte Nachfahren von TPersistent, {$M+} an seiner
//          Deklaration oder eigene published-Mitglieder), nach {$WARN
//          TYPEINFO_IMPLICITLY_ADDED OFF} oder {$WARNINGS OFF}. Ein Vorfahr,
//          dessen Kette nicht bis TObject bekannt ist oder dessen Datei sich
//          nicht lesen lässt, hält die Regel still; ebenso generische und
//          verschachtelte Klassen (nicht mit dcc gegengeprüft).
//   H2243  Initialize bzw. Finalize mit einer Variablen eines eingebauten
//          Typs ohne verwaltete Teile (Integer, Double, Boolean, Char …,
//          auch über Aliase).
//   H2244  Ebenso mit einer Variablen eines Zeigers auf einen verwalteten
//          Typ (PString, PVariant …): Gemeint war wohl P^.
// Bei H2243 und H2244 nur der Aufruf mit einem Argument, einem einfachen
// Bezeichner, dessen Typ sicher bekannt ist; still nach {$HINTS OFF} und
// wenn Initialize bzw. Finalize eine eigene Routine oder ein Mitglied meinen
// kann (with, Methode einer Klasse mit unbekanntem Vorfahren).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  CompilerHintsRuleId = 'compiler-hints';

type
  TCompilerHintsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterCompilerHintRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeInfoClasses,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Units;

const
  cTypeInfoWarning = 'TYPEINFO_IMPLICITLY_ADDED';
  /// <summary>Eingebaute Typen ohne verwaltete Teile (H2243), Kleinbuchstaben.</summary>
  cPlainTypes: array[0..30] of string = ('integer', 'cardinal', 'shortint', 'smallint', 'longint', 'longword',
    'int64', 'uint64', 'byte', 'word', 'nativeint', 'nativeuint', 'fixedint', 'fixeduint', 'int8', 'int16', 'int32',
    'uint8', 'uint16', 'uint32', 'boolean', 'bytebool', 'wordbool', 'longbool', 'char', 'ansichar', 'widechar',
    'single', 'double', 'extended', 'currency');
  /// <summary>Zeigertypen der Unit System auf verwaltete Typen (H2244), Kleinbuchstaben.</summary>
  cManagedPointers: array[0..7] of string = ('pstring', 'punicodestring', 'pansistring', 'pwidestring',
    'prawbytestring', 'putf8string', 'pvariant', 'polevariant');

type
  TCompilerHintsCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FActive: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FAncestry: TAncestry;
    FLocal: TUnitIndex;
    FScope: TTypedScope;
    // Gelesene Dateien der Vorfahren: aktive Token, nil = nicht lesbar.
    FFiles: TDictionary<string, TArray<TPascalToken>>;
    function TokenAt(AOffset: Integer): Integer;
    function PathOf(ANode: TSyntaxNode): string;
    function HintsEnabled(AOffset: Integer): Boolean;
    /// <summary>Aktive Token der Datei AFileName eines Vorfahren; False, wenn sie sich nicht lesen lässt.</summary>
    function FileTokens(const AFileName: string; out ATokens: TArray<TPascalToken>): Boolean;
    function IsLocal(const ALocation: TSymbolLocation): Boolean;
    function HasPublishedMembers(const ALocation: TSymbolLocation): Boolean;
    /// <summary>Hat ein Vorfahr der Klasse AName RTTI? False nur, wenn die ganze Kette sicher ohne ist; AKnown
    /// sagt, ob sich das sicher bestimmen ließ.</summary>
    function AncestorTypeInfo(const AName: string; out AKnown: Boolean): Boolean;
    procedure CheckClass(ADecl, ABody: TSyntaxNode);
    procedure CheckCall(ANode: TSyntaxNode);
    function InsideWith(ANode: TSyntaxNode): Boolean;
    procedure VisitDeclarations;
    procedure VisitCalls;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TCompilerHintsCheck }

constructor TCompilerHintsCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FFiles := TDictionary<string, TArray<TPascalToken>>.Create;
end;

destructor TCompilerHintsCheck.Destroy;
begin
  FScope.Free;
  FAncestry.Free;
  FFiles.Free;
  inherited Destroy;
end;

function TCompilerHintsCheck.TokenAt(AOffset: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(FTokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if FTokens[mMiddle].Offset < AOffset then
      mLow := mMiddle + 1
    else
      mHigh := mMiddle;
  end;
  Result := mLow;
end;

function TCompilerHintsCheck.PathOf(ANode: TSyntaxNode): string;
begin
  Result := TConditionalBranches.PathAt(FPaths, TokenAt(ANode.StartOffset));
end;

function TCompilerHintsCheck.HintsEnabled(AOffset: Integer): Boolean;
var
  mToken: TPascalToken;
  mBody: string;
begin
  // Wie WarningEnabled für {$HINTS ON|OFF} in Textreihenfolge.
  Result := True;
  for mToken in FTokens do
  begin
    if mToken.Offset >= AOffset then
      Break;
    if (mToken.Kind = TPascalTokenKind.Directive) and (TPascalLexer.DirectiveName(mToken.Text) = 'HINTS') then
    begin
      mBody := TDirectiveNames.Body(mToken.Text);
      Result := UpperCase(Trim(Copy(mBody, Length(TDirectiveNames.LeadingName(mBody)) + 1, MaxInt))) <> 'OFF';
    end;
  end;
end;

function TCompilerHintsCheck.FileTokens(const AFileName: string; out ATokens: TArray<TPascalToken>): Boolean;
var
  mText: string;
begin
  if not FFiles.TryGetValue(LowerCase(AFileName), ATokens) then
  begin
    ATokens := nil;
    if ReadNeighbour(FContext, AFileName, mText) and (mText <> '') then
      ATokens := TTypeInfoClasses.ActiveTokens(mText);
    FFiles.Add(LowerCase(AFileName), ATokens);
  end;
  Result := ATokens <> nil;
end;

function TCompilerHintsCheck.IsLocal(const ALocation: TSymbolLocation): Boolean;
begin
  Result := (ALocation.FileName = '') or SameText(ALocation.FileName, FContext.FileName) or
    SameText(ALocation.UnitName, FLocal.UnitName);
end;

function TCompilerHintsCheck.HasPublishedMembers(const ALocation: TSymbolLocation): Boolean;
var
  mSymbols: TArray<TIndexSymbol>;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  if IsLocal(ALocation) then
    mSymbols := FLocal.Symbols
  else if (FContext.Index <> nil) and FContext.Index.FindUnit(ALocation.UnitName, mUnit) then
    mSymbols := mUnit.Symbols
  else
    Exit(True);
  for mSymbol in mSymbols do
    if (mSymbol.Visibility = TIndexVisibility.Published) and
      SameText(mSymbol.Container, ALocation.Symbol.QualifiedName) then
      Exit(True);
  Result := False;
end;

function TCompilerHintsCheck.AncestorTypeInfo(const AName: string; out AKnown: Boolean): Boolean;
var
  mChain: TArray<TSymbolLocation>;
  mLocation: TSymbolLocation;
  mComplete, mObjectMissing: Boolean;
  mTokens: TArray<TPascalToken>;
begin
  AKnown := False;
  Result := False;
  mChain := FAncestry.Ancestors(AName, mComplete, mObjectMissing);
  for mLocation in mChain do
  begin
    if SameText(mLocation.Symbol.Name, 'TObject') then
      Break;
    // Bekannte Klassen mit RTTI entscheiden auch ohne vollständige Kette.
    if TTypeInfoClasses.KnownTypeInfoClass(mLocation.Symbol.Name) then
    begin
      AKnown := True;
      Exit(True);
    end;
    if (mLocation.Symbol.Kind <> TIndexSymbolKind.ClassType) or (mLocation.Symbol.TypeParams <> '') then
      Exit;
    if IsLocal(mLocation) then
      mTokens := FActive
    else if not FileTokens(mLocation.FileName, mTokens) then
      Exit;
    if TTypeInfoClasses.SwitchAt(mTokens, mLocation.Symbol.Range.StartPos) or HasPublishedMembers(mLocation) then
    begin
      AKnown := True;
      Exit(True);
    end;
  end;
  AKnown := mComplete;
end;

procedure TCompilerHintsCheck.CheckClass(ADecl, ABody: TSyntaxNode);
var
  mIndex: Integer;
  mMember, mSection: TSyntaxNode;
  mKnown: Boolean;
  mRange: TTextRange;
  mToken: Integer;
begin
  if ADecl.FindChild(TSyntaxKind.GenericParams) <> nil then
    Exit;
  // Erstes Mitglied hinter dem ersten ausdrücklichen published.
  mMember := nil;
  mSection := nil;
  for mIndex := 0 to ABody.ChildCount - 1 do
    if ABody[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      if mSection <> nil then
        Break;
      if ABody[mIndex].Name = 'published' then
        mSection := ABody[mIndex];
    end
    else if (mSection <> nil) and (ABody[mIndex].Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl,
      TSyntaxKind.RoutineHeader]) then
    begin
      mMember := ABody[mIndex];
      Break;
    end;
  if (mMember = nil) or (PathOf(mSection) <> '') or (PathOf(mMember) <> '') or (PathOf(ADecl) <> '') then
    Exit;
  if TTypeInfoClasses.SwitchAt(FActive, ADecl.StartPos) or
    not WarningEnabled(FTokens, cTypeInfoWarning, mMember.StartOffset) then
    Exit;
  if AncestorTypeInfo(ADecl.Name, mKnown) or not mKnown then
    Exit;
  // Am Namen des Mitglieds.
  mRange := TTextRange.Create(mMember.StartPos, mMember.StartPos);
  mToken := TokenAt(mMember.StartOffset);
  while (mToken < Length(FTokens)) and (FTokens[mToken].Offset < mMember.EndOffset) do
  begin
    if FTokens[mToken].Kind = TPascalTokenKind.Identifier then
    begin
      mRange := TTextRange.Create(FTokens[mToken].StartPos, FTokens[mToken].EndPos);
      Break;
    end;
    Inc(mToken);
  end;
  FReport.Add(mRange, Format('published schaltet für %s RTTI ein ($M+), weil weder die Klasse noch ein Vorfahr ' +
    'mit RTTI übersetzt wird (wie W1055). Von TPersistent ableiten oder {$M+} vor die Deklaration setzen, wenn ' +
    'das gewollt ist.', [ADecl.Name]));
end;

function TCompilerHintsCheck.InsideWith(ANode: TSyntaxNode): Boolean;
begin
  while ANode <> nil do
  begin
    if ANode.Kind = TSyntaxKind.WithStatement then
      Exit(True);
    ANode := ANode.Parent;
  end;
  Result := False;
end;

procedure TCompilerHintsCheck.CheckCall(ANode: TSyntaxNode);
var
  mCallee, mArgument: TSyntaxNode;
  mCandidate, mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
  mTypeName: string;
begin
  if ANode.ChildCount <> 2 then
    Exit;
  mCallee := ANode[0];
  if (mCallee.Kind <> TSyntaxKind.Identifier) or not MatchText(mCallee.Name, ['Initialize', 'Finalize']) then
    Exit;
  mArgument := Unwrapped(ANode[1]);
  if (mArgument.Kind <> TSyntaxKind.Identifier) or InsideWith(ANode) or not HintsEnabled(ANode.StartOffset) then
    Exit;
  // Eine eigene Routine oder ein Mitglied gleichen Namens verdeckt die eingebaute.
  for mCandidate in FScope.Resolver.CallCandidates(FContext.Tree, FScope.FileName, mCallee) do
    if not mCandidate.Builtin and not SameText(mCandidate.UnitName, 'System') then
      Exit;
  if FScope.Resolver.MayBeHiddenMember(FContext.Tree, FScope.FileName, mCallee, Default(TResolvedSymbol)) then
    Exit;
  if not FScope.Resolver.NodeType(FContext.Tree, FScope.FileName, mArgument, mSymbol, mType, mTypeFound) or
    not (mSymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) or mSymbol.IsType or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) or
    not FScope.DeclarationSure(mSymbol, mArgument) then
    Exit;
  if mTypeFound then
  begin
    if not mType.Builtin and not SameText(mType.UnitName, 'System') then
      Exit;
    mTypeName := mType.Name;
  end
  else
  begin
    // Ohne Index der RTL ist PString unbekannt; ein gleichnamiger eigener Typ wäre gefunden worden.
    mTypeName := mSymbol.TypeName;
    if IndexText(mTypeName, cManagedPointers) < 0 then
      Exit;
  end;
  if IndexText(mTypeName, cPlainTypes) >= 0 then
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s(%s) hat keine Wirkung: %s ' +
      'braucht kein Initialize/Finalize (wie H2243).', [mCallee.Name, mArgument.Name, mTypeName]))
  else if IndexText(mTypeName, cManagedPointers) >= 0 then
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s(%s) wirkt auf den Zeiger, nicht auf ' +
      'das Ziel: %s braucht kein Initialize/Finalize, gemeint ist wohl %s^ (wie H2244).',
      [mCallee.Name, mArgument.Name, mArgument.Name, mArgument.Name]));
end;

procedure TCompilerHintsCheck.VisitDeclarations;
var
  mPending: TStack<TSyntaxNode>;
  mNode, mBody: TSyntaxNode;
  mIndex: Integer;
begin
  // Klassen auf Ebene der Abschnitte; verschachtelte und lokale Klassen nicht (Bericht M1: iterativ).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.TypeDecl then
      begin
        mBody := mNode.FindChild(TSyntaxKind.ClassType);
        if mBody <> nil then
          CheckClass(mNode, mBody);
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
        if mNode[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
          TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
          mPending.Push(mNode[mIndex]);
    end;
  finally
    mPending.Free;
  end;
end;

procedure TCompilerHintsCheck.VisitCalls;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.Call then
        CheckCall(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
    end;
  finally
    mPending.Free;
  end;
end;

procedure TCompilerHintsCheck.Run;
var
  mCache: IRuleDerivedCache;
begin
  if ContainsText(FContext.Text, 'published') then
  begin
    mCache := TRuleDerived.Open(FContext);
    FLocal := TRuleDerived.UnitIndex(mCache, FContext);
    FAncestry := TAncestry.Create(FContext.Index, FLocal);
    FActive := TTypeInfoClasses.ActiveTokens(FContext.Text);
    VisitDeclarations;
  end;
  if ContainsText(FContext.Text, 'Initialize') or ContainsText(FContext.Text, 'Finalize') then
  begin
    FScope := TTypedScope.Create(FContext);
    VisitCalls;
  end;
end;

{ TCompilerHintsRule }

function TCompilerHintsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CompilerHintsRuleId, TRuleSeverity.Hint,
    'Hinweis des Compilers (wie W1055, H2243, H2244)');
end;

procedure TCompilerHintsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TCompilerHintsCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mCheck := TCompilerHintsCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterCompilerHintRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TCompilerHintsRule.Create);
end;

end.
