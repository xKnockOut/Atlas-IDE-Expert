unit Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls;

// Regeln override-only-inherited (#1143) und inherited-without-ancestor (#1144) aus
// Atlas.Common.Rules.Builtin.Inheritance: override, dessen Rumpf nur inherited mit unveränderten Parametern
// aufruft, und bloßes inherited; in einer neuen Methode, die kein Vorfahr kennt.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TOverrideOnlyInheritedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedWithoutAncestorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cOverrideOnlyInheritedRuleId = 'override-only-inherited';
  cInheritedWithoutAncestorRuleId = 'inherited-without-ancestor';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceInheritedCallsText = (OnlyInheritedTitle, RemoveMethod, OnlyInherited, NoAncestorTitle, RemoveInherited,
    NoAncestor);

const
  cTexts: array[TInheritanceInheritedCallsText] of TAtlasText = (
    (De: 'override ruft nur inherited auf'; En: 'override only calls inherited'),
    (De: 'Methode entfernen'; En: 'Remove method'),
    (De: '%s.%s ruft nur inherited auf und kann entfallen.'; En: '%s.%s only calls inherited and can be removed.'),
    (De: 'inherited ohne Methode im Vorfahr'; En: 'inherited without method in the ancestor'),
    (De: 'inherited entfernen'; En: 'Remove inherited'),
    (De: 'Kein Vorfahr von %s hat %s: inherited tut nichts. Fehlt override?';
     En: 'No ancestor of %s has %s: inherited does nothing. Is override missing?'));

{$SCOPEDENUMS OFF}

{ Hilfen für override-only-inherited und inherited-without-ancestor }

const
  // Öffentliche Methoden von TObject, falls System nicht im Index steht (#1144).
  cObjectMethodNames: array[0..21] of string = ('Create', 'Free', 'DisposeOf', 'ClassType', 'ClassName',
    'ClassNameIs', 'ClassParent', 'ClassInfo', 'InstanceSize', 'InheritsFrom', 'MethodAddress', 'MethodName',
    'QualifiedClassName', 'FieldAddress', 'GetInterface', 'GetInterfaceEntry', 'GetInterfaceTable', 'UnitName',
    'UnitScope', 'CleanupInstance', 'InitInstance', 'NewInstance');

/// <summary>Implementierungen von Methoden (TKlasse.Methode) auf oberster Ebene, ohne lokale Routinen.</summary>
function MethodBodies(const ACache: IRuleDerivedCache; const AContext: TRuleContext): TArray<TSyntaxNode>;
var
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  for mRoutine in TRuleDerived.Routines(ACache, AContext) do
  begin
    if (Pos('.', mRoutine.Name) > 0) and ((mRoutine.Parent = nil) or
      (mRoutine.Parent.Kind <> TSyntaxKind.RoutineDecl)) then
    begin
      Result := Result + [mRoutine];
    end;
  end;
end;

/// <summary>Klasse und Methode aus "TAussen.TKlasse&lt;T&gt;.Methode": TKlasse und Methode.</summary>
procedure SplitMethodName(const AName: string; out AClassName, AMethodName: string);
var
  mParts: TArray<string>;
  mText: string;
  mDepth, mIndex: Integer;
begin
  // Punkte in Typargumenten (TDictionary<System.string, …>) trennen nicht.
  mText := '';
  mDepth := 0;
  for mIndex := 1 to Length(AName) do
  begin
    if AName[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AName[mIndex] = '>' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      mText := mText + AName[mIndex];
    end;
  end;
  mParts := mText.Split(['.']);
  AClassName := '';
  AMethodName := '';
  if Length(mParts) < 2 then
  begin
    Exit;
  end;
  AClassName := mParts[High(mParts) - 1];
  AMethodName := mParts[High(mParts)];
end;

/// <summary>Parameter des Kopfs AHeader als "name:typ:modifizierer" je Name, klein geschrieben.</summary>
function ParameterKeys(AHeader: TSyntaxNode): TArray<string>;
var
  mSection, mParameter, mType: TSyntaxNode;
  mIndex: Integer;
  mName, mTypeName: string;
begin
  Result := nil;
  if AHeader = nil then
  begin
    Exit;
  end;
  mSection := AHeader.FindChild(TSyntaxKind.Parameters);
  if mSection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    mParameter := mSection[mIndex];
    mType := mParameter.FindChild(TSyntaxKind.TypeReference);
    mTypeName := '';
    if mType <> nil then
    begin
      mTypeName := BareName(mType.Name);
    end;
    for mName in mParameter.Name.Split([',']) do
    begin
      Result := Result + [LowerCase(Trim(mName) + ':' + mTypeName + ':' + IntToStr(Ord(mParameter.Modifier)))];
    end;
  end;
end;

/// <summary>Namen der Parameter des Kopfs AHeader in Reihenfolge.</summary>
function ParameterNames(AHeader: TSyntaxNode): TArray<string>;
var
  mKey: string;
begin
  Result := nil;
  for mKey in ParameterKeys(AHeader) do
  begin
    Result := Result + [Copy(mKey, 1, Pos(':', mKey) - 1)];
  end;
end;

/// <summary>Hat ein Parameter des Kopfs AHeader einen Standardwert?</summary>
function HasDefaultValues(AHeader: TSyntaxNode): Boolean;
var
  mSection: TSyntaxNode;
  mIndex, mChild: Integer;
begin
  Result := False;
  mSection := AHeader.FindChild(TSyntaxKind.Parameters);
  if mSection <> nil then
  begin
    for mIndex := 0 to mSection.ChildCount - 1 do
    begin
      for mChild := 0 to mSection[mIndex].ChildCount - 1 do
      begin
        if mSection[mIndex][mChild].Kind <> TSyntaxKind.TypeReference then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
end;

/// <summary>Rumpf der Methode AMethod aus ABodies; bei Überladungen der mit denselben Parametern. nil, wenn es
/// keinen eindeutigen gibt.</summary>
function BodyOf(const AMethod: TMethodDecl; const ABodies: TArray<TSyntaxNode>): TSyntaxNode;
var
  mBody: TSyntaxNode;
  mCandidates: TArray<TSyntaxNode>;
  mClassName, mMethodName: string;
  mKeys: TArray<string>;
begin
  Result := nil;
  mCandidates := nil;
  for mBody in ABodies do
  begin
    SplitMethodName(mBody.Name, mClassName, mMethodName);
    if SameText(mClassName, AMethod.ClassName) and SameText(mMethodName, AMethod.Symbol.Name) then
    begin
      mCandidates := mCandidates + [mBody];
    end;
  end;
  if Length(mCandidates) = 1 then
  begin
    Exit(mCandidates[0]);
  end;
  mKeys := ParameterKeys(AMethod.Header);
  for mBody in mCandidates do
  begin
    if string.Join(',', ParameterKeys(mBody.FindChild(TSyntaxKind.RoutineHeader))) = string.Join(',', mKeys) then
    begin
      if Result <> nil then
      begin
        Exit(nil);
      end;
      Result := mBody;
    end;
  end;
end;

/// <summary>Bereich des Methodennamens im Kopf AHeader ("TKlasse.Name"); sonst der ganze Kopf.</summary>
function MethodNameRange(const AContext: TRuleContext; AHeader: TSyntaxNode; const AName: string): TTextRange;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
  for mIndex := AContext.Tree.FirstTokenFrom(AHeader.StartOffset) to High(AContext.Tree.Tokens) do
  begin
    mToken := AContext.Tree.Tokens[mIndex];
    if mToken.Offset < AHeader.StartOffset then
    begin
      Continue;
    end;
    if (mToken.Offset >= AHeader.EndOffset) or mToken.IsSymbol('(') or mToken.IsSymbol(';') or
      mToken.IsSymbol(':') then
    begin
      Break;
    end;
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AName) then
    begin
      Result := TTextRange.Create(mToken.StartPos, mToken.EndPos);
    end;
  end;
end;

/// <summary>Steht zwischen AStart und AEnd ein Kommentar oder eine Direktive?</summary>
function HasCommentBetween(const AContext: TRuleContext; AStart, AEnd: Integer): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  for mIndex := AContext.Tree.FirstTokenFrom(AStart) to High(AContext.Tree.Tokens) do
  begin
    mToken := AContext.Tree.Tokens[mIndex];
    if mToken.Offset < AStart then
    begin
      Continue;
    end;
    if mToken.Offset >= AEnd then
    begin
      Break;
    end;
    if mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TOverrideOnlyInheritedRule }

function TOverrideOnlyInheritedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cOverrideOnlyInheritedRuleId, TRuleSeverity.Hint,
    cTexts[TInheritanceInheritedCallsText.OnlyInheritedTitle].Text);
end;

/// <summary>Ausdruck AExpr aus "Result := AExpr"; False bei anderen Anweisungen.</summary>
function ResultExpression(AStatement: TSyntaxNode; out AExpr: TSyntaxNode): Boolean;
begin
  AExpr := nil;
  Result := (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2);
  Result := Result and (AStatement[0].Kind = TSyntaxKind.Identifier) and SameText(AStatement[0].Name, 'Result');
  if Result then
  begin
    AExpr := AStatement[1];
  end;
end;

/// <summary>Aufruf AExpr der Aufrufanweisung AStatement; False bei anderen Anweisungen.</summary>
function CallExpression(AStatement: TSyntaxNode; out AExpr: TSyntaxNode): Boolean;
begin
  AExpr := nil;
  Result := (AStatement.Kind = TSyntaxKind.CallStatement) and (AStatement.ChildCount = 1);
  if Result then
  begin
    AExpr := AStatement[0];
  end;
end;

/// <summary>Sind die Argumente des Aufrufs ACall genau die Parameter AParams in ihrer Reihenfolge?</summary>
function SameArguments(ACall: TSyntaxNode; const AParams: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  mIndex := 0;
  while Result and (mIndex <= High(AParams)) do
  begin
    Result := (ACall[mIndex + 1].Kind = TSyntaxKind.Identifier) and SameText(ACall[mIndex + 1].Name, AParams[mIndex]);
    Inc(mIndex);
  end;
end;

/// <summary>Ruft AExpr die geerbte Methode AMethodName mit den Parametern AParams auf (inherited Name bzw.
/// inherited Name(…))?</summary>
function CallsInherited(AExpr: TSyntaxNode; const AMethodName: string; const AParams: TArray<string>): Boolean;
begin
  if AExpr.Kind = TSyntaxKind.InheritedExpr then
  begin
    Exit(SameText(AExpr.Name, AMethodName) and (Length(AParams) = 0));
  end;
  Result := (AExpr.Kind = TSyntaxKind.Call) and (AExpr.ChildCount = Length(AParams) + 1);
  Result := Result and (AExpr[0].Kind = TSyntaxKind.InheritedExpr) and SameText(AExpr[0].Name, AMethodName) and
    SameArguments(AExpr, AParams);
end;

/// <summary>Ruft AStatement nur die geerbte Methode AMethodName mit den Parametern AParams in ihrer Reihenfolge auf?
/// In Funktionen nur "Result := inherited Name(…)": ein bloßes inherited; verwirft dort das Ergebnis.</summary>
function OnlyInherited(AStatement: TSyntaxNode; const AMethodName: string; const AParams: TArray<string>;
  AFunction: Boolean): Boolean;
var
  mExpr: TSyntaxNode;
begin
  if AFunction then
  begin
    Result := ResultExpression(AStatement, mExpr);
  end
  else
  begin
    Result := CallExpression(AStatement, mExpr);
    // Ein bloßes inherited; übergibt die eigenen Parameter unverändert.
    if Result and (mExpr.Kind = TSyntaxKind.InheritedExpr) and (mExpr.Name = '') then
    begin
      Exit;
    end;
  end;
  Result := Result and CallsInherited(mExpr, AMethodName, AParams);
end;

/// <summary>Steht vor dem Kopf in der Klasse ein Attribut ([Weak] procedure …)?</summary>
function HasAttribute(AHeader: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mParent := AHeader.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  for mIndex := 1 to mParent.ChildCount - 1 do
  begin
    if mParent[mIndex] = AHeader then
    begin
      Exit(mParent[mIndex - 1].Kind = TSyntaxKind.Attribute);
    end;
  end;
end;

const
  // Direktiven, mit denen das Überschreiben selbst etwas bewirkt.
  cMeaningful: array[0..5] of string = ('final', 'deprecated', 'experimental', 'platform', 'library', 'reintroduce');

/// <summary>override ohne Attribut, Standardwerte und Direktiven, mit denen das Überschreiben etwas bewirkt?
/// </summary>
function IsPlainOverride(const AMethod: TMethodDecl): Boolean;
var
  mDirective: string;
begin
  Result := AMethod.Has('override') and not HasAttribute(AMethod.Header) and not HasDefaultValues(AMethod.Header);
  for mDirective in cMeaningful do
  begin
    Result := Result and not AMethod.Has(mDirective);
  end;
end;

/// <summary>Besteht der Rumpf ABody nur aus Kopf und einem Aufruf der geerbten Methode, ohne lokale Deklarationen
/// und Kommentare?</summary>
function OnlyInheritedBody(const AContext: TRuleContext; const AMethod: TMethodDecl; ABody: TSyntaxNode): Boolean;
var
  mBlock: TSyntaxNode;
begin
  mBlock := ABody.FindChild(TSyntaxKind.Block);
  Result := (ABody.FindChild(TSyntaxKind.RoutineHeader) <> nil) and (mBlock <> nil) and (ABody.ChildCount = 2);
  Result := Result and (mBlock.ChildCount = 1) and not HasCommentBetween(AContext, mBlock.StartOffset,
    mBlock.EndOffset);
  Result := Result and OnlyInherited(mBlock[0], AMethod.Symbol.Name, ParameterNames(AMethod.Header),
    AMethod.Keyword = 'function');
end;

/// <summary>Hat AMethod dieselbe Sichtbarkeit wie die überschriebene Methode? Eine geänderte Sichtbarkeit
/// (protected -> public) ist der Zweck der Methode; unbekannte überschriebene Methode: False.</summary>
function VisibilityKept(AAncestry: TAncestry; const AMethod: TMethodDecl): Boolean;
var
  mOverridden: TInherited;
begin
  mOverridden := AAncestry.InheritedVirtual(AMethod);
  if mOverridden.Found then
  begin
    Result := mOverridden.Symbol.Visibility = AMethod.Symbol.Visibility;
  end
  else
  begin
    Result := MatchText(AMethod.Symbol.Name, cObjectVirtualNames) and
      (AMethod.Symbol.Visibility = TIndexVisibility.Public);
  end;
end;

/// <summary>Korrektur, die Deklaration und Rumpf samt XMLDoc entfernt; leer, wenn sie nicht auf eigenen Zeilen
/// stehen.</summary>
function RemovalFixes(const ACache: IRuleDerivedCache; const AContext: TRuleContext; const AMethod: TMethodDecl;
  ABody: TSyntaxNode): TArray<TRuleFix>;
var
  mDecl, mBodySpan: TLineSpan;
begin
  Result := nil;
  if WholeLineSpan(AContext.Text, AMethod.Header.StartOffset, AMethod.Header.EndOffset, True, False, mDecl) and
    WholeLineSpan(AContext.Text, ABody.StartOffset, ABody.EndOffset, True, True, mBodySpan) then
  begin
    Result := [TRuleFix.Create(cTexts[TInheritanceInheritedCallsText.RemoveMethod].Text, [
      TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mDecl.Start, mDecl.Finish), ''),
      TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mBodySpan.Start, mBodySpan.Finish), '')])];
  end;
end;

procedure TOverrideOnlyInheritedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCache: IRuleDerivedCache;
  mAncestry: TAncestry;
  mBodies: TArray<TSyntaxNode>;
  mMethod: TMethodDecl;
  mBody: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'inherited') then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(AContext);
  mBodies := MethodBodies(mCache, AContext);
  if mBodies = nil then
  begin
    Exit;
  end;
  mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(mCache, AContext));
  try
    for mMethod in ClassMethods(AContext, mAncestry) do
    begin
      if not IsPlainOverride(mMethod) then
      begin
        Continue;
      end;
      mBody := BodyOf(mMethod, mBodies);
      if (mBody <> nil) and OnlyInheritedBody(AContext, mMethod, mBody) and VisibilityKept(mAncestry, mMethod) then
      begin
        AReport.Add(MethodNameRange(AContext, mBody.FindChild(TSyntaxKind.RoutineHeader), mMethod.Symbol.Name),
          cTexts[TInheritanceInheritedCallsText.OnlyInherited].Fmt([mMethod.ClassName, mMethod.Symbol.Name]),
          TRuleConfidence.High, RemovalFixes(mCache, AContext, mMethod, mBody));
      end;
    end;
  finally
    mAncestry.Free;
  end;
end;

{ TInheritedWithoutAncestorRule }

function TInheritedWithoutAncestorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInheritedWithoutAncestorRuleId, TRuleSeverity.Hint,
    cTexts[TInheritanceInheritedCallsText.NoAncestorTitle].Text);
end;

/// <summary>Anweisungen "inherited;" ohne Namen im Block ABlock, ohne anonyme Methoden.</summary>
function BareInheritedStatements(ABlock: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ABlock);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount = 1) and
        (mNode[0].Kind = TSyntaxKind.InheritedExpr) and (mNode[0].Name = '') then
      begin
        Result := Result + [mNode];
        Continue;
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

/// <summary>Konstruktor, Destruktor, override oder reintroduce: Dort hat ein bloßes inherited einen Vorfahren
/// bzw. ist gewollt.</summary>
function SkipsInheritedCheck(const AMethod: TMethodDecl): Boolean;
begin
  Result := (AMethod.Keyword = 'constructor') or (AMethod.Keyword = 'destructor') or AMethod.Has('override') or
    AMethod.Has('reintroduce');
end;

/// <summary>Bloße inherited-Anweisungen im Rumpf ABody, wenn er zur Methode AMethod gehört; nil sonst.</summary>
function BareStatementsOf(ABody: TSyntaxNode; const AMethod: TMethodDecl): TArray<TSyntaxNode>;
var
  mClassName, mMethodName: string;
  mBlock: TSyntaxNode;
begin
  Result := nil;
  SplitMethodName(ABody.Name, mClassName, mMethodName);
  mBlock := ABody.FindChild(TSyntaxKind.Block);
  if SameText(mClassName, AMethod.ClassName) and SameText(mMethodName, AMethod.Symbol.Name) and (mBlock <> nil) then
  begin
    Result := BareInheritedStatements(mBlock);
  end;
end;

procedure TInheritedWithoutAncestorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCache: IRuleDerivedCache;
  mAncestry: TAncestry;
  mBodies: TArray<TSyntaxNode>;

  /// <summary>Hat ein Vorfahr von AClassName ein Mitglied AName? True auch, wenn die Kette nicht bekannt ist.
  /// </summary>
  function AncestorKnows(const AClassName, AName: string): Boolean;
  var
    mChain: TArray<TSymbolLocation>;
    mLocation: TSymbolLocation;
    mMember: TIndexSymbol;
    mComplete, mObjectMissing: Boolean;
  begin
    mChain := mAncestry.Ancestors(AClassName, mComplete, mObjectMissing);
    if not mComplete then
    begin
      Exit(True);
    end;
    for mLocation in mChain do
    begin
      for mMember in mAncestry.Members(mLocation) do
      begin
        if SameText(mMember.Name, AName) then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := mObjectMissing and (MatchText(AName, cObjectMethodNames) or MatchText(AName, cObjectVirtualNames));
  end;

  procedure ReportStatements(const AMethod: TMethodDecl; const AStatements: TArray<TSyntaxNode>);
  var
    mStatement: TSyntaxNode;
    mFixes: TArray<TRuleFix>;
  begin
    for mStatement in AStatements do
    begin
      mFixes := nil;
      if (mStatement.Parent <> nil) and (mStatement.Parent.Kind = TSyntaxKind.Block) then
      begin
        mFixes := [RemoveStatementFix(mCache, AContext, mStatement,
          cTexts[TInheritanceInheritedCallsText.RemoveInherited].Text)];
      end;
      AReport.Add(TTextRange.Create(mStatement.StartPos, mStatement.EndPos),
        cTexts[TInheritanceInheritedCallsText.NoAncestor].Fmt(
        [AMethod.ClassName, AMethod.Symbol.Name]), TRuleConfidence.High, mFixes);
    end;
  end;

  procedure CheckMethod(const AMethod: TMethodDecl);
  var
    mBody: TSyntaxNode;
    mStatements: TArray<TSyntaxNode>;
    mKnown: Boolean;
  begin
    mKnown := False;
    for mBody in mBodies do
    begin
      mStatements := BareStatementsOf(mBody, AMethod);
      if mStatements = nil then
      begin
        Continue;
      end;
      // Erst bei einem Treffer die Vorfahren befragen.
      if not mKnown and AncestorKnows(AMethod.ClassName, AMethod.Symbol.Name) then
      begin
        Exit;
      end;
      mKnown := True;
      ReportStatements(AMethod, mStatements);
    end;
  end;

var
  mMethod: TMethodDecl;
  mChecked: TDictionary<string, Boolean>;
  mKey: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'inherited') then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(AContext);
  mBodies := MethodBodies(mCache, AContext);
  if mBodies = nil then
  begin
    Exit;
  end;
  mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(mCache, AContext));
  mChecked := TDictionary<string, Boolean>.Create;
  try
    // ClassMethods lässt Klassenmethoden, statische Methoden und Message-Handler aus: Dort ruft inherited
    // DefaultHandler bzw. ist kein Fall.
    for mMethod in ClassMethods(AContext, mAncestry) do
    begin
      mKey := LowerCase(mMethod.ClassName + '.' + mMethod.Symbol.Name);
      if not SkipsInheritedCheck(mMethod) and not mChecked.ContainsKey(mKey) then
      begin
        mChecked.Add(mKey, True);
        CheckMethod(mMethod);
      end;
    end;
  finally
    mChecked.Free;
    mAncestry.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls', cTexts);

end.
