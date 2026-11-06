unit Atlas.Common.Rules.Builtin.Inheritance.ClassReferences;

// Regel class-reference-nonvirtual-constructor aus Atlas.Common.Rules.Builtin.Inheritance (#1032): Create über
// eine Klassenreferenz (class of TBasis), deren Konstruktor nicht virtuell ist (E2391); es läuft immer der
// Konstruktor der Basisklasse. Kennt der Index die Klassenreferenz oder ihre Klasse nicht (RTL unter Linux:
// ExceptClass, Exception), kann die Regel die Zeile nicht entscheiden (IRuleLineCertainty): Ein lsp-ignore dort
// gilt dann nicht als unused-suppression.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TClassReferenceNonvirtualConstructorRule = class(TInterfacedObject, IRule, IRuleLineCertainty)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    function Decides(const AContext: TRuleContext; ALine: Integer): Boolean;
    /// <summary>Zieltyp aus "TPluginKlasse = class of TPlugin"; '' ohne class of.</summary>
    class function ClassRefTarget(const ASignature: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceClassReferencesText = (Title, VirtualOverride, VirtualOn, NotVirtual);

const
  cTexts: array[TInheritanceClassReferencesText] of TAtlasText = (
    (De: 'Konstruktor über Klassenreferenz nicht virtuell (wie E2391)';
     En: 'Constructor via class reference not virtual (like E2391)'),
    (De: 'virtual an %s.%s, override in den Nachfahren'; En: 'virtual on %s.%s, override in the descendants'),
    (De: 'virtual an %s.%s'; En: 'virtual on %s.%s'),
    (De: '%s.%s ist nicht virtuell; über die Klassenreferenz läuft immer %s.%s (wie E2391).';
     En: '%s.%s is not virtual; the class reference always runs %s.%s (like E2391).'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Prüfung einer Unit für class-reference-nonvirtual-constructor.</summary>
  TClassRefCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    FResolver: TNameResolver;
    FFileName: string;
    FLocal: TUnitIndex;
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FMethods: TArray<TMethodDecl>;
    FMethodsRead: Boolean;
    function IsLocal(const AFileName: string): Boolean;
    function UnitFor(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function PathAt(const APosition: TTextPosition): string;
    function Certain(const AFileName, ACondition: string; const ADeclaration: TTextPosition;
      ACall: TSyntaxNode): Boolean;
    function ClassMethodsOnce: TArray<TMethodDecl>;
    function VirtualEdits(const AConstructor: TIndexSymbol; out AEdits: TArray<TRuleEdit>): Boolean;
    function IsOverridingConstructor(const AMethod: TMethodDecl; const AConstructor: TIndexSymbol): Boolean;
    function OverrideEdits(const AConstructor: TIndexSymbol): TArray<TRuleEdit>;
    function VirtualFix(const AConstructor: TIndexSymbol; out AFix: TRuleFix): Boolean;
    function ReceiverBase(AAccess: TSyntaxNode; out ABase: TResolvedSymbol): Boolean;
    function ConstructorMember(AAccess: TSyntaxNode; const ABase: TResolvedSymbol; out AMember: TResolvedSymbol;
      out AUnit: TUnitIndex): Boolean;
    function NonvirtualMatches(AAccess: TSyntaxNode; const AMember: TResolvedSymbol; const AUnit: TUnitIndex;
      out AMatching: TIndexSymbol): Integer;
    procedure CheckCall(AAccess: TSyntaxNode);
    function CollectCalls: TArray<TSyntaxNode>;
    function Decided(AAccess: TSyntaxNode): Boolean;
    procedure Prepare;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
    /// <summary>Konnte die Regel jeden Aufruf X.Create in Zeile ALine (ab 0) entscheiden?</summary>
    function DecidesLine(ALine: Integer): Boolean;
  end;

/// <summary>Zahl der Argumente, wenn AAccess aufgerufen wird ("Klasse.Create(A, B)"), sonst 0.</summary>
function ArgCount(AAccess: TSyntaxNode): Integer;
begin
  Result := 0;
  if (AAccess.Parent <> nil) and (AAccess.Parent.Kind = TSyntaxKind.Call) and (AAccess.Parent[0] = AAccess) then
  begin
    Result := AAccess.Parent.ChildCount - 1;
  end;
end;

/// <summary>Die Klasse, in der AMember deklariert ist: Rümpfe (constructor TPlugin.Create) stehen außerhalb.
/// </summary>
function FindOwner(const AUnit: TUnitIndex; const AMember: TResolvedSymbol; out AOwner: TIndexSymbol): Boolean;
var
  mOwner: TIndexSymbol;
begin
  AOwner := Default(TIndexSymbol);
  for mOwner in AUnit.Symbols do
  begin
    if (mOwner.Kind = TIndexSymbolKind.ClassType) and SameText(mOwner.QualifiedName, AMember.Container) and
      ContainsLine(mOwner.Range, AMember.Range.StartPos.Line) then
    begin
      AOwner := mOwner;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>ACandidate ist eine Überladung des Konstruktors AMember in der Klasse AOwner.</summary>
function IsOverloadOf(const ACandidate: TIndexSymbol; const AMember: TResolvedSymbol;
  const AOwner: TIndexSymbol): Boolean;
begin
  Result := (ACandidate.Kind = TIndexSymbolKind.Constructor_) and SameText(ACandidate.Name, AMember.Name);
  Result := Result and SameText(ACandidate.Container, AMember.Container) and
    ContainsLine(AOwner.Range, ACandidate.Range.StartPos.Line);
end;

/// <summary>Der Konstruktor ACandidate nimmt AArgs Argumente.</summary>
function AcceptsArgs(const ACandidate: TIndexSymbol; AArgs: Integer): Boolean;
begin
  Result := (AArgs >= ACandidate.MinArgs) and ((ACandidate.MaxArgs < 0) or (AArgs <= ACandidate.MaxArgs));
end;

function IsVirtualConstructor(const ACandidate: TIndexSymbol): Boolean;
begin
  Result := ACandidate.IsVirtual or ACandidate.HasDirective('virtual') or ACandidate.HasDirective('dynamic');
  Result := Result or ACandidate.HasDirective('override') or ACandidate.HasDirective('abstract');
end;

{ TClassReferenceNonvirtualConstructorRule }

function TClassReferenceNonvirtualConstructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('class-reference-nonvirtual-constructor', TRuleSeverity.Warning,
    cTexts[TInheritanceClassReferencesText.Title].Text);
end;

class function TClassReferenceNonvirtualConstructorRule.ClassRefTarget(const ASignature: string): string;
begin
  Result := TResolverText.ClassRefTarget(ASignature);
end;

procedure TClassReferenceNonvirtualConstructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TClassRefCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TClassRefCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

function TClassReferenceNonvirtualConstructorRule.Decides(const AContext: TRuleContext; ALine: Integer): Boolean;
var
  mCheck: TClassRefCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit(True);
  end;
  mCheck := TClassRefCheck.Create(AContext, nil);
  try
    Result := mCheck.DecidesLine(ALine);
  finally
    mCheck.Free;
  end;
end;

{ TClassRefCheck }

constructor TClassRefCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

destructor TClassRefCheck.Destroy;
begin
  FAncestry.Free;
  inherited Destroy;
end;

function TClassRefCheck.IsLocal(const AFileName: string): Boolean;
begin
  Result := (AFileName = '') or SameText(AFileName, FFileName);
end;

/// <summary>Unit, in der ein Symbol aus AFileName steht: die geprüfte Datei oder der Index.</summary>
function TClassRefCheck.UnitFor(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := True;
  if IsLocal(AFileName) then
  begin
    AUnit := FLocal;
  end
  else
  begin
    Result := (FContext.Index <> nil) and FContext.Index.FindFile(AFileName, AUnit);
  end;
end;

/// <summary>Zweig der bedingten Übersetzung an APosition ('' ohne {$IF…}).</summary>
function TClassRefCheck.PathAt(const APosition: TTextPosition): string;
var
  mLow, mHigh, mMiddle: Integer;
begin
  Result := '';
  if FPaths = nil then
  begin
    Exit;
  end;
  mLow := 0;
  mHigh := Length(FTokens) - 1;
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if (FTokens[mMiddle].StartPos.Line < APosition.Line) or ((FTokens[mMiddle].StartPos.Line = APosition.Line) and
      (FTokens[mMiddle].StartPos.Character < APosition.Character)) then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := TConditionalBranches.PathAt(FPaths, mLow);
end;

/// <summary>Steht die Deklaration sicher, wo der Aufruf an ACall übersetzt wird? Aus dem Index ohne Bedingung,
/// in der Datei in demselben oder einem umschließenden Zweig.</summary>
function TClassRefCheck.Certain(const AFileName, ACondition: string; const ADeclaration: TTextPosition;
  ACall: TSyntaxNode): Boolean;
begin
  Result := (ACondition = '') and (not IsLocal(AFileName) or
    TConditionalBranches.Implies(PathAt(ACall.StartPos), PathAt(ADeclaration)));
end;

function TClassRefCheck.ClassMethodsOnce: TArray<TMethodDecl>;
begin
  if not FMethodsRead then
  begin
    FMethods := ClassMethods(FContext, FAncestry);
    FMethodsRead := True;
  end;
  Result := FMethods;
end;

/// <summary>virtual an den Konstruktor AConstructor dieser Datei; False, wenn er nicht hier steht oder die
/// Direktive nicht anzuhängen ist.</summary>
function TClassRefCheck.VirtualEdits(const AConstructor: TIndexSymbol; out AEdits: TArray<TRuleEdit>): Boolean;
var
  mMethod: TMethodDecl;
  mFix: TRuleFix;
begin
  AEdits := nil;
  Result := False;
  for mMethod in ClassMethodsOnce do
  begin
    if (mMethod.Keyword <> 'constructor') or not (mMethod.Symbol.SelectionRange.StartPos =
      AConstructor.SelectionRange.StartPos) then
    begin
      Continue;
    end;
    if not AppendDirective(FContext, mMethod, 'virtual', mFix) then
    begin
      Exit(False);
    end;
    AEdits := AEdits + mFix.Edits;
    Result := True;
  end;
end;

/// <summary>AMethod ist ein gleichlautender Konstruktor eines Nachfahren der Klasse von AConstructor.</summary>
function TClassRefCheck.IsOverridingConstructor(const AMethod: TMethodDecl; const AConstructor: TIndexSymbol): Boolean;
begin
  Result := (AMethod.Keyword = 'constructor') and SameText(AMethod.Symbol.Name, AConstructor.Name) and
    not SameText(AMethod.ClassName, AConstructor.Container);
  Result := Result and not Settled(AMethod) and SameSignature(AMethod.Symbol, AConstructor) and
    FAncestry.DescendsFrom(AMethod.ClassName, AConstructor.Container);
end;

/// <summary>override an die gleichlautenden Konstruktoren der Nachfahren in dieser Datei.</summary>
function TClassRefCheck.OverrideEdits(const AConstructor: TIndexSymbol): TArray<TRuleEdit>;
var
  mMethod: TMethodDecl;
  mFix: TRuleFix;
begin
  Result := nil;
  for mMethod in ClassMethodsOnce do
  begin
    if IsOverridingConstructor(mMethod, AConstructor) and AppendDirective(FContext, mMethod, 'override', mFix) then
    begin
      Result := Result + mFix.Edits;
    end;
  end;
end;

/// <summary>Korrektur, wenn der Konstruktor in dieser Datei steht: virtual an ihn, override an die
/// gleichlautenden Konstruktoren der Nachfahren in dieser Datei.</summary>
function TClassRefCheck.VirtualFix(const AConstructor: TIndexSymbol; out AFix: TRuleFix): Boolean;
var
  mEdits: TArray<TRuleEdit>;
begin
  AFix := Default(TRuleFix);
  Result := VirtualEdits(AConstructor, mEdits);
  if not Result then
  begin
    Exit;
  end;
  mEdits := mEdits + OverrideEdits(AConstructor);
  if Length(mEdits) > 1 then
  begin
    AFix := TRuleFix.Create(cTexts[TInheritanceClassReferencesText.VirtualOverride].Fmt([AConstructor.Container,
      AConstructor.Name]), mEdits);
  end
  else
  begin
    AFix := TRuleFix.Create(cTexts[TInheritanceClassReferencesText.VirtualOn].Fmt([AConstructor.Container,
      AConstructor.Name]), mEdits);
  end;
end;

/// <summary>Der Empfänger ist ein Wert (Variable, Feld, Parameter, Funktion), dessen Typ class of … ist; ABase ist
/// die Klasse hinter class of. Alle Deklarationen stehen sicher, wo der Aufruf übersetzt wird.</summary>
function TClassRefCheck.ReceiverBase(AAccess: TSyntaxNode; out ABase: TResolvedSymbol): Boolean;
var
  mSymbol, mRefType: TResolvedSymbol;
  mTypeFound: Boolean;
  mTarget: string;
  mTypeUnit: TUnitIndex;
begin
  ABase := Default(TResolvedSymbol);
  Result := FResolver.NodeType(FContext.Tree, FFileName, AAccess[0], mSymbol, mRefType, mTypeFound) and mTypeFound;
  Result := Result and not mSymbol.IsType and mSymbol.Found and not mRefType.Builtin and
    (mRefType.SymbolKind = TIndexSymbolKind.ClassType);
  if not Result then
  begin
    Exit;
  end;
  mTarget := TClassReferenceNonvirtualConstructorRule.ClassRefTarget(mRefType.Signature);
  Result := (mTarget <> '') and Certain(mSymbol.FileName, mSymbol.Condition, mSymbol.SelectionRange.StartPos,
    AAccess) and
    Certain(mRefType.FileName, mRefType.Condition, mRefType.SelectionRange.StartPos, AAccess);
  Result := Result and UnitFor(mRefType.FileName, mTypeUnit) and FResolver.ResolveTypeFrom(mTypeUnit, mTarget, ABase);
  Result := Result and (ABase.SymbolKind = TIndexSymbolKind.ClassType);
end;

/// <summary>Der nächste Typ der Kette, der Create deklariert: AMember mit der Unit AUnit seiner Deklaration.
/// </summary>
function TClassRefCheck.ConstructorMember(AAccess: TSyntaxNode; const ABase: TResolvedSymbol;
  out AMember: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  Result := FResolver.FindMember(ABase, AAccess.Name, AMember) and not AMember.IsHelper;
  Result := Result and (AMember.SymbolKind = TIndexSymbolKind.Constructor_) and UnitFor(AMember.FileName, AUnit);
end;

/// <summary>Zahl der passenden nicht virtuellen Überladungen von AMember; AMatching die letzte. -1, wenn eine
/// passende virtuelle Überladung genügt, damit die Regel schweigt, oder eine Überladung nicht sicher dort steht.
/// </summary>
function TClassRefCheck.NonvirtualMatches(AAccess: TSyntaxNode; const AMember: TResolvedSymbol;
  const AUnit: TUnitIndex; out AMatching: TIndexSymbol): Integer;
var
  mOwner, mCandidate: TIndexSymbol;
  mArgs: Integer;
begin
  AMatching := Default(TIndexSymbol);
  Result := 0;
  if not FindOwner(AUnit, AMember, mOwner) then
  begin
    Exit;
  end;
  mArgs := ArgCount(AAccess);
  for mCandidate in AUnit.Symbols do
  begin
    if not IsOverloadOf(mCandidate, AMember, mOwner) then
    begin
      Continue;
    end;
    if not Certain(AMember.FileName, mCandidate.Condition, mCandidate.SelectionRange.StartPos, AAccess) or
      (AcceptsArgs(mCandidate, mArgs) and IsVirtualConstructor(mCandidate)) then
    begin
      Exit(-1);
    end;
    if AcceptsArgs(mCandidate, mArgs) then
    begin
      Inc(Result);
      AMatching := mCandidate;
    end;
  end;
end;

procedure TClassRefCheck.CheckCall(AAccess: TSyntaxNode);
var
  mBase, mMember: TResolvedSymbol;
  mMemberUnit: TUnitIndex;
  mMatching: TIndexSymbol;
  mMatches: Integer;
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  if not ReceiverBase(AAccess, mBase) or not ConstructorMember(AAccess, mBase, mMember, mMemberUnit) then
  begin
    Exit;
  end;
  mMatches := NonvirtualMatches(AAccess, mMember, mMemberUnit, mMatching);
  if mMatches <= 0 then
  begin
    Exit;
  end;
  mFixes := nil;
  if (mMatches = 1) and IsLocal(mMember.FileName) and VirtualFix(mMatching, mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(TTextRange.Create(AAccess.StartPos, AAccess.EndPos),
    cTexts[TInheritanceClassReferencesText.NotVirtual].Fmt([mMember.Container, mMember.Name, mMember.Container,
    mMember.Name]), TRuleConfidence.High, mFixes);
end;

/// <summary>Alle Zugriffe X.Create mit Empfänger.</summary>
function TClassRefCheck.CollectCalls: TArray<TSyntaxNode>;
var
  mCalls: TArray<TSyntaxNode>;
begin
  mCalls := nil;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and SameText(ANode.Name, 'Create') then
      begin
        mCalls := mCalls + [ANode];
      end;
      Result := True;
    end);
  Result := mCalls;
end;

/// <summary>Weiß der Index genug über AAccess? Unbekannt sind ein Empfänger ohne Typ und eine Klassenreferenz, deren
/// Klasse oder Konstruktor der Index nicht kennt.</summary>
function TClassRefCheck.Decided(AAccess: TSyntaxNode): Boolean;
var
  mSymbol, mRefType, mBase, mMember: TResolvedSymbol;
  mTypeFound: Boolean;
  mTarget: string;
  mTypeUnit: TUnitIndex;
begin
  if not FResolver.NodeType(FContext.Tree, FFileName, AAccess[0], mSymbol, mRefType, mTypeFound) or not mTypeFound or
    not mSymbol.Found then
  begin
    Exit(False);
  end;
  if mSymbol.IsType or mRefType.Builtin or (mRefType.SymbolKind <> TIndexSymbolKind.ClassType) then
  begin
    Exit(True);
  end;
  mTarget := TClassReferenceNonvirtualConstructorRule.ClassRefTarget(mRefType.Signature);
  if mTarget = '' then
  begin
    Exit(True);
  end;
  Result := UnitFor(mRefType.FileName, mTypeUnit) and FResolver.ResolveTypeFrom(mTypeUnit, mTarget, mBase) and
    FResolver.FindMember(mBase, AAccess.Name, mMember);
end;

procedure TClassRefCheck.Prepare;
begin
  FCache := TRuleDerived.Open(FContext);
  FTokens := FContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FFileName := ResolverFileName(FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(FCache, FContext));
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  FResolver := TRuleDerived.Resolver(FCache, FContext);
end;

function TClassRefCheck.DecidesLine(ALine: Integer): Boolean;
var
  mNode: TSyntaxNode;
  mCalls: TArray<TSyntaxNode>;
begin
  Result := True;
  mCalls := nil;
  for mNode in CollectCalls do
  begin
    if (ALine < 0) or ((mNode.StartPos.Line <= ALine) and (mNode.EndPos.Line >= ALine)) then
    begin
      mCalls := mCalls + [mNode];
    end;
  end;
  if mCalls = nil then
  begin
    Exit;
  end;
  Prepare;
  FResolver.PinTree(FContext.Tree, FFileName);
  try
    FLocal := FResolver.ExtractedUnit(FContext.Tree, FFileName);
    for mNode in mCalls do
    begin
      if not Decided(mNode) then
      begin
        Exit(False);
      end;
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

procedure TClassRefCheck.Run;
var
  mCalls: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  mCalls := CollectCalls;
  if mCalls = nil then
  begin
    Exit;
  end;
  Prepare;
  FResolver.PinTree(FContext.Tree, FFileName);
  try
    FLocal := FResolver.ExtractedUnit(FContext.Tree, FFileName);
    for mNode in mCalls do
    begin
      CheckCall(mNode);
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.ClassReferences', cTexts);

end.
