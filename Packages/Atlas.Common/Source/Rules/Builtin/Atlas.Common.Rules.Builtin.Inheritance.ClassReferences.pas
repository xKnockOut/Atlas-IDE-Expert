unit Atlas.Common.Rules.Builtin.Inheritance.ClassReferences;

// Regel class-reference-nonvirtual-constructor aus Atlas.Common.Rules.Builtin.Inheritance (#1032): Create über
// eine Klassenreferenz (class of TBasis), deren Konstruktor nicht virtuell ist (E2391); es läuft immer der
// Konstruktor der Basisklasse.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TClassReferenceNonvirtualConstructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
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
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry;

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
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
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
  Owner: TIndexSymbol;
begin
  AOwner := Default(TIndexSymbol);
  for Owner in AUnit.Symbols do
  begin
    if (Owner.Kind = TIndexSymbolKind.ClassType) and SameText(Owner.QualifiedName, AMember.Container) and
      ContainsLine(Owner.Range, AMember.Range.StartPos.Line) then
    begin
      AOwner := Owner;
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
    'Konstruktor über Klassenreferenz nicht virtuell (wie E2391)');
end;

class function TClassReferenceNonvirtualConstructorRule.ClassRefTarget(const ASignature: string): string;
begin
  Result := TResolverText.ClassRefTarget(ASignature);
end;

procedure TClassReferenceNonvirtualConstructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TClassRefCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Check := TClassRefCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
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
  Low, High, Middle: Integer;
begin
  Result := '';
  if FPaths = nil then
  begin
    Exit;
  end;
  Low := 0;
  High := Length(FTokens) - 1;
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if (FTokens[Middle].StartPos.Line < APosition.Line) or ((FTokens[Middle].StartPos.Line = APosition.Line) and
      (FTokens[Middle].StartPos.Character < APosition.Character)) then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := TConditionalBranches.PathAt(FPaths, Low);
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
  Method: TMethodDecl;
  Fix: TRuleFix;
begin
  AEdits := nil;
  Result := False;
  for Method in ClassMethodsOnce do
  begin
    if (Method.Keyword <> 'constructor') or not (Method.Symbol.SelectionRange.StartPos =
      AConstructor.SelectionRange.StartPos) then
    begin
      Continue;
    end;
    if not AppendDirective(FContext, Method, 'virtual', Fix) then
    begin
      Exit(False);
    end;
    AEdits := AEdits + Fix.Edits;
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
  Method: TMethodDecl;
  Fix: TRuleFix;
begin
  Result := nil;
  for Method in ClassMethodsOnce do
  begin
    if IsOverridingConstructor(Method, AConstructor) and AppendDirective(FContext, Method, 'override', Fix) then
    begin
      Result := Result + Fix.Edits;
    end;
  end;
end;

/// <summary>Korrektur, wenn der Konstruktor in dieser Datei steht: virtual an ihn, override an die
/// gleichlautenden Konstruktoren der Nachfahren in dieser Datei.</summary>
function TClassRefCheck.VirtualFix(const AConstructor: TIndexSymbol; out AFix: TRuleFix): Boolean;
var
  Edits: TArray<TRuleEdit>;
begin
  AFix := Default(TRuleFix);
  Result := VirtualEdits(AConstructor, Edits);
  if not Result then
  begin
    Exit;
  end;
  Edits := Edits + OverrideEdits(AConstructor);
  if Length(Edits) > 1 then
  begin
    AFix := TRuleFix.Create(Format('virtual an %s.%s, override in den Nachfahren', [AConstructor.Container,
      AConstructor.Name]), Edits);
  end
  else
  begin
    AFix := TRuleFix.Create(Format('virtual an %s.%s', [AConstructor.Container, AConstructor.Name]), Edits);
  end;
end;

/// <summary>Der Empfänger ist ein Wert (Variable, Feld, Parameter, Funktion), dessen Typ class of … ist; ABase ist
/// die Klasse hinter class of. Alle Deklarationen stehen sicher, wo der Aufruf übersetzt wird.</summary>
function TClassRefCheck.ReceiverBase(AAccess: TSyntaxNode; out ABase: TResolvedSymbol): Boolean;
var
  Symbol, RefType: TResolvedSymbol;
  TypeFound: Boolean;
  Target: string;
  TypeUnit: TUnitIndex;
begin
  ABase := Default(TResolvedSymbol);
  Result := FResolver.NodeType(FContext.Tree, FFileName, AAccess[0], Symbol, RefType, TypeFound) and TypeFound;
  Result := Result and not Symbol.IsType and Symbol.Found and not RefType.Builtin and
    (RefType.SymbolKind = TIndexSymbolKind.ClassType);
  if not Result then
  begin
    Exit;
  end;
  Target := TClassReferenceNonvirtualConstructorRule.ClassRefTarget(RefType.Signature);
  Result := (Target <> '') and Certain(Symbol.FileName, Symbol.Condition, Symbol.SelectionRange.StartPos, AAccess) and
    Certain(RefType.FileName, RefType.Condition, RefType.SelectionRange.StartPos, AAccess);
  Result := Result and UnitFor(RefType.FileName, TypeUnit) and FResolver.ResolveTypeFrom(TypeUnit, Target, ABase);
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
  Owner, Candidate: TIndexSymbol;
  Args: Integer;
begin
  AMatching := Default(TIndexSymbol);
  Result := 0;
  if not FindOwner(AUnit, AMember, Owner) then
  begin
    Exit;
  end;
  Args := ArgCount(AAccess);
  for Candidate in AUnit.Symbols do
  begin
    if not IsOverloadOf(Candidate, AMember, Owner) then
    begin
      Continue;
    end;
    if not Certain(AMember.FileName, Candidate.Condition, Candidate.SelectionRange.StartPos, AAccess) or
      (AcceptsArgs(Candidate, Args) and IsVirtualConstructor(Candidate)) then
    begin
      Exit(-1);
    end;
    if AcceptsArgs(Candidate, Args) then
    begin
      Inc(Result);
      AMatching := Candidate;
    end;
  end;
end;

procedure TClassRefCheck.CheckCall(AAccess: TSyntaxNode);
var
  Base, Member: TResolvedSymbol;
  MemberUnit: TUnitIndex;
  Matching: TIndexSymbol;
  Matches: Integer;
  Fix: TRuleFix;
  Fixes: TArray<TRuleFix>;
begin
  if not ReceiverBase(AAccess, Base) or not ConstructorMember(AAccess, Base, Member, MemberUnit) then
  begin
    Exit;
  end;
  Matches := NonvirtualMatches(AAccess, Member, MemberUnit, Matching);
  if Matches <= 0 then
  begin
    Exit;
  end;
  Fixes := nil;
  if (Matches = 1) and IsLocal(Member.FileName) and VirtualFix(Matching, Fix) then
  begin
    Fixes := [Fix];
  end;
  FReport.Add(TTextRange.Create(AAccess.StartPos, AAccess.EndPos), Format('%s.%s ist nicht virtuell; über die ' +
    'Klassenreferenz läuft immer %s.%s (wie E2391).', [Member.Container, Member.Name, Member.Container,
    Member.Name]), TRuleConfidence.High, Fixes);
end;

/// <summary>Alle Zugriffe X.Create mit Empfänger.</summary>
function TClassRefCheck.CollectCalls: TArray<TSyntaxNode>;
var
  Calls: TArray<TSyntaxNode>;
begin
  Calls := nil;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and SameText(ANode.Name, 'Create') then
      begin
        Calls := Calls + [ANode];
      end;
      Result := True;
    end);
  Result := Calls;
end;

procedure TClassRefCheck.Run;
var
  Calls: TArray<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Calls := CollectCalls;
  if Calls = nil then
  begin
    Exit;
  end;
  FCache := TRuleDerived.Open(FContext);
  FTokens := FContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FFileName := ResolverFileName(FContext);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(FCache, FContext));
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  FResolver := TRuleDerived.Resolver(FCache, FContext);
  FResolver.PinTree(FContext.Tree, FFileName);
  try
    FLocal := FResolver.ExtractedUnit(FContext.Tree, FFileName);
    for Node in Calls do
    begin
      CheckCall(Node);
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

end.
