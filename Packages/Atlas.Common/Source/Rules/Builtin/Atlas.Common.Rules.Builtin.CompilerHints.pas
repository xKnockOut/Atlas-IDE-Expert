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
  cCompilerHintsRuleId = 'compiler-hints';

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
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeInfoClasses,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Units,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TCompilerHintsText = (PublishedRtti, NoEffect, OnPointer, Title);

const
  cTexts: array[TCompilerHintsText] of TAtlasText = (
    (De: 'published schaltet für %s RTTI ein ($M+), weil weder die Klasse noch ein Vorfahr mit RTTI übersetzt wird ' +
      '(wie W1055). Von TPersistent ableiten oder {$M+} vor die Deklaration setzen, wenn das gewollt ist.';
     En: 'published turns on RTTI for %s ($M+) because neither the class nor an ancestor is compiled with RTTI (like ' +
      'W1055). Derive from TPersistent or put {$M+} before the declaration if that is intended.'),
    (De: '%s(%s) hat keine Wirkung: %s braucht kein Initialize/Finalize (wie H2243).';
     En: '%s(%s) has no effect: %s needs no Initialize/Finalize (like H2243).'),
    (De: '%s(%s) wirkt auf den Zeiger, nicht auf das Ziel: %s braucht kein Initialize/Finalize, gemeint ist wohl %s^ ' +
      '(wie H2244).';
     En: '%s(%s) acts on the pointer, not on the target: %s needs no Initialize/Finalize, %s^ is probably meant ' +
      '(like H2244).'),
    (De: 'Hinweis des Compilers (wie W1055, H2243, H2244)'; En: 'Compiler hint (like W1055, H2243, H2244)'));

{$SCOPEDENUMS OFF}

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
    function PathOf(ANode: TSyntaxNode): string;
    function HintsEnabled(AOffset: Integer): Boolean;
    /// <summary>Aktive Token der Datei AFileName eines Vorfahren; False, wenn sie sich nicht lesen lässt.</summary>
    function FileTokens(const AFileName: string; out ATokens: TArray<TPascalToken>): Boolean;
    function IsLocal(const ALocation: TSymbolLocation): Boolean;
    function HasPublishedMembers(const ALocation: TSymbolLocation): Boolean;
    /// <summary>Hat ein Vorfahr der Klasse AName RTTI? False nur, wenn die ganze Kette sicher ohne ist; AKnown
    /// sagt, ob sich das sicher bestimmen ließ.</summary>
    function AncestorTypeInfo(const AName: string; out AKnown: Boolean): Boolean;
    /// <summary>Erstes Mitglied hinter dem ersten ausdrücklichen published (ASection); nil ohne.</summary>
    function FirstPublishedMember(ABody: TSyntaxNode; out ASection: TSyntaxNode): TSyntaxNode;
    /// <summary>Bereich des ersten Namens im Mitglied; ohne Namen dessen Anfang.</summary>
    function MemberNameRange(AMember: TSyntaxNode): TTextRange;
    procedure CheckClass(ADecl, ABody: TSyntaxNode);
    /// <summary>Initialize(X) bzw. Finalize(X) der eingebauten Routine mit einer Variablen X außerhalb von with.
    /// </summary>
    function BuiltinCallee(ANode: TSyntaxNode; out ACallee, AArgument: TSyntaxNode): Boolean;
    /// <summary>Typname der sicher deklarierten Variablen AArgument, wenn er aus System stammt.</summary>
    function ArgumentTypeName(AArgument: TSyntaxNode; out ATypeName: string): Boolean;
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

function TCompilerHintsCheck.PathOf(ANode: TSyntaxNode): string;
begin
  Result := TConditionalBranches.PathAt(FPaths, TokenFrom(FTokens, ANode.StartOffset));
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
    begin
      Break;
    end;
    if (mToken.Kind = TPascalTokenKind.Directive) and (TPascalLexer.DirectiveName(mToken.Text) = 'HINTS') then
    begin
      mBody := TDirectiveNames.Body(mToken.Text);
      Result := not SameText(Trim(Copy(mBody, Length(TDirectiveNames.LeadingName(mBody)) + 1, MaxInt)), 'OFF');
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
    begin
      ATokens := TTypeInfoClasses.ActiveTokens(mText);
    end;
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
  begin
    mSymbols := FLocal.Symbols;
  end
  else if (FContext.Index <> nil) and FContext.Index.FindUnit(ALocation.UnitName, mUnit) then
  begin
    mSymbols := mUnit.Symbols;
  end
  else
  begin
    Exit(True);
  end;
  for mSymbol in mSymbols do
  begin
    if (mSymbol.Visibility = TIndexVisibility.Published) and
      SameText(mSymbol.Container, ALocation.Symbol.QualifiedName) then
    begin
      Exit(True);
    end;
  end;
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
    begin
      Break;
    end;
    // Bekannte Klassen mit RTTI entscheiden auch ohne vollständige Kette.
    if TTypeInfoClasses.KnownTypeInfoClass(mLocation.Symbol.Name) then
    begin
      AKnown := True;
      Exit(True);
    end;
    if (mLocation.Symbol.Kind <> TIndexSymbolKind.ClassType) or (mLocation.Symbol.TypeParams <> '') then
    begin
      Exit;
    end;
    if IsLocal(mLocation) then
    begin
      mTokens := FActive;
    end
    else if not FileTokens(mLocation.FileName, mTokens) then
    begin
      Exit;
    end;
    if TTypeInfoClasses.SwitchAt(mTokens, mLocation.Symbol.Range.StartPos) or HasPublishedMembers(mLocation) then
    begin
      AKnown := True;
      Exit(True);
    end;
  end;
  AKnown := mComplete;
end;

function TCompilerHintsCheck.FirstPublishedMember(ABody: TSyntaxNode; out ASection: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := nil;
  ASection := nil;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mChild := ABody[mIndex];
    if (mChild.Kind = TSyntaxKind.Visibility) and (ASection <> nil) then
    begin
      Break;
    end;
    if (mChild.Kind = TSyntaxKind.Visibility) and (mChild.Name = 'published') then
    begin
      ASection := mChild;
    end
    else if (ASection <> nil) and (mChild.Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl,
      TSyntaxKind.RoutineHeader]) then
    begin
      Exit(mChild);
    end;
  end;
end;

function TCompilerHintsCheck.MemberNameRange(AMember: TSyntaxNode): TTextRange;
var
  mToken: Integer;
begin
  Result := TTextRange.Create(AMember.StartPos, AMember.StartPos);
  mToken := TokenFrom(FTokens, AMember.StartOffset);
  while (mToken < Length(FTokens)) and (FTokens[mToken].Offset < AMember.EndOffset) do
  begin
    if FTokens[mToken].Kind = TPascalTokenKind.Identifier then
    begin
      Exit(TTextRange.Create(FTokens[mToken].StartPos, FTokens[mToken].EndPos));
    end;
    Inc(mToken);
  end;
end;

procedure TCompilerHintsCheck.CheckClass(ADecl, ABody: TSyntaxNode);
var
  mMember, mSection: TSyntaxNode;
  mKnown: Boolean;
begin
  if ADecl.FindChild(TSyntaxKind.GenericParams) <> nil then
  begin
    Exit;
  end;
  // Erstes Mitglied hinter dem ersten ausdrücklichen published.
  mMember := FirstPublishedMember(ABody, mSection);
  if (mMember = nil) or (PathOf(mSection) <> '') or (PathOf(mMember) <> '') or (PathOf(ADecl) <> '') then
  begin
    Exit;
  end;
  if TTypeInfoClasses.SwitchAt(FActive, ADecl.StartPos) or
    not WarningEnabled(FTokens, cTypeInfoWarning, mMember.StartOffset) then
  begin
    Exit;
  end;
  if AncestorTypeInfo(ADecl.Name, mKnown) or not mKnown then
  begin
    Exit;
  end;
  // Am Namen des Mitglieds.
  FReport.Add(MemberNameRange(mMember), cTexts[TCompilerHintsText.PublishedRtti].Fmt([ADecl.Name]));
end;

function TCompilerHintsCheck.InsideWith(ANode: TSyntaxNode): Boolean;
begin
  while ANode <> nil do
  begin
    if ANode.Kind = TSyntaxKind.WithStatement then
    begin
      Exit(True);
    end;
    ANode := ANode.Parent;
  end;
  Result := False;
end;

function TCompilerHintsCheck.BuiltinCallee(ANode: TSyntaxNode; out ACallee, AArgument: TSyntaxNode): Boolean;
var
  mCandidate: TResolvedSymbol;
begin
  ACallee := nil;
  AArgument := nil;
  Result := ANode.ChildCount = 2;
  Result := Result and (ANode[0].Kind = TSyntaxKind.Identifier) and MatchText(ANode[0].Name,
    ['Initialize', 'Finalize']);
  if not Result then
  begin
    Exit;
  end;
  ACallee := ANode[0];
  AArgument := Unwrapped(ANode[1]);
  Result := (AArgument.Kind = TSyntaxKind.Identifier) and not InsideWith(ANode) and HintsEnabled(ANode.StartOffset);
  if not Result then
  begin
    Exit;
  end;
  // Eine eigene Routine oder ein Mitglied gleichen Namens verdeckt die eingebaute.
  for mCandidate in FScope.Resolver.CallCandidates(FContext.Tree, FScope.FileName, ACallee) do
  begin
    Result := Result and (mCandidate.Builtin or SameText(mCandidate.UnitName, 'System'));
  end;
  Result := Result and not FScope.Resolver.MayBeHiddenMember(FContext.Tree, FScope.FileName, ACallee,
    Default(TResolvedSymbol));
end;

function TCompilerHintsCheck.ArgumentTypeName(AArgument: TSyntaxNode; out ATypeName: string): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  ATypeName := '';
  Result := FScope.Resolver.NodeType(FContext.Tree, FScope.FileName, AArgument, mSymbol, mType, mTypeFound) and
    (mSymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and not mSymbol.IsType;
  Result := Result and (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) and
    FScope.DeclarationSure(mSymbol, AArgument);
  if not Result then
  begin
    Exit;
  end;
  if mTypeFound then
  begin
    ATypeName := mType.Name;
    Result := mType.Builtin or SameText(mType.UnitName, 'System');
  end
  else
  begin
    // Ohne Index der RTL ist PString unbekannt; ein gleichnamiger eigener Typ wäre gefunden worden.
    ATypeName := mSymbol.TypeName;
    Result := IndexText(ATypeName, cManagedPointers) >= 0;
  end;
end;

procedure TCompilerHintsCheck.CheckCall(ANode: TSyntaxNode);
var
  mCallee, mArgument: TSyntaxNode;
  mTypeName: string;
begin
  if not BuiltinCallee(ANode, mCallee, mArgument) or not ArgumentTypeName(mArgument, mTypeName) then
  begin
    Exit;
  end;
  if IndexText(mTypeName, cPlainTypes) >= 0 then
  begin
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TCompilerHintsText.NoEffect].Fmt([mCallee.Name,
      mArgument.Name, mTypeName]));
  end
  else if IndexText(mTypeName, cManagedPointers) >= 0 then
  begin
    FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TCompilerHintsText.OnPointer].Fmt(
      [mCallee.Name, mArgument.Name, mArgument.Name, mArgument.Name]));
  end;
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
        begin
          CheckClass(mNode, mBody);
        end;
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if mNode[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
          TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
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
      begin
        CheckCall(mNode);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
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
  Result := TRuleDescriptor.Create(cCompilerHintsRuleId, TRuleSeverity.Hint,
    cTexts[TCompilerHintsText.Title].Text);
end;

procedure TCompilerHintsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TCompilerHintsCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.CompilerHints', cTexts);

end.
