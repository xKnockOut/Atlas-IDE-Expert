unit Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe;

// Regel destructor-not-nil-safe aus Atlas.Common.Rules.Builtin.Flow (#269): Wirft der Konstruktor, ruft Delphi den
// Destruktor mit den Feldern auf, die bis dahin gesetzt sind. Ein Zugriff FFeld.X, FFeld[…] oder FFeld^ im
// Destruktor (oder in einer privaten Methode, die nur er aufruft) auf ein Feld, das dann noch nil sein kann,
// stürzt ab und verdeckt die eigentliche Exception. Assigned(FFeld) und FFeld &lt;&gt; nil davor schützen.
// Korrektur: die Anweisung in if Assigned(FFeld) then einschließen.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TDestructorNotNilSafeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cDestructorNotNilSafeRuleId = 'destructor-not-nil-safe';

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Constructors,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowDestructorNotNilSafeText = (WrapInAssigned, Conditional, Raises, Title);

const
  cTexts: array[TFlowDestructorNotNilSafeText] of TAtlasText = (
    (De: 'In if Assigned(%s) then einschließen'; En: 'Wrap in if Assigned(%s) then'),
    (De: '%s wird im Konstruktor nur bedingt angelegt und kann beim Destruktor nil sein; %s stürzt dann ab.';
     En: '%s is created only conditionally in the constructor and can be nil in the destructor; %s then crashes.'),
    (De: 'Wirft %s, ist %s beim Destruktor noch nil; %s stürzt ab und verdeckt die eigentliche Exception.';
     En: 'If %s raises, %s is still nil in the destructor; %s crashes and hides the actual exception.'),
    (De: 'Destruktor benutzt ein Feld, das nach einer Exception im Konstruktor nil ist';
     En: 'Destructor uses a field that is nil after an exception in the constructor'));

{$SCOPEDENUMS OFF}

/// <summary>Methoden in private- und strict-private-Abschnitten der Klassendeklaration.</summary>
function PrivateOf(AClass: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mIsPrivate: Boolean;
begin
  Result := nil;
  if AClass = nil then
  begin
    Exit;
  end;
  mIsPrivate := False;
  for mIndex := 0 to AClass.ChildCount - 1 do
  begin
    if AClass[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      mIsPrivate := MatchText(AClass[mIndex].Name, ['private', 'strict private']);
    end
    else if mIsPrivate and (AClass[mIndex].Kind = TSyntaxKind.RoutineHeader) and (AClass[mIndex].Name <> '') then
    begin
      Result := Result + [AClass[mIndex].Name];
    end;
  end;
end;

/// <summary>Nächste Anweisung über ANode (ANode selbst eingeschlossen); sonst ARoot.</summary>
function EnclosingStatement(ANode, ARoot: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> ARoot) and (Result <> nil) and
    not (Result.Kind in cFlowStatementKinds + [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement]) do
  begin
    Result := Result.Parent;
  end;
  if Result = nil then
  begin
    Result := ARoot;
  end;
end;

/// <summary>X.Free und X.DisposeOf greifen nicht zu: beide vertragen nil.</summary>
function IsReleaseCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and MatchText(ANode.Name, ['Free', 'DisposeOf']);
end;

type
  /// <summary>Prüfung einer Unit für destructor-not-nil-safe; hält die Klasse, die Ergebnisse ihrer Konstruktoren
  /// und die im geprüften Rumpf schon abgefragten Felder.</summary>
  TDestructorCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRoutines: TArray<TSyntaxNode>;
    FScan: TConstructorScan;
    FPrivateMethods: TArray<string>;
    FQualifiedClass: string;
    FLineBreak: string;
    FChecked: TArray<string>;
    FReported: TArray<string>;
    function Text(ANode: TSyntaxNode): string;
    function OnlyCalledFromDestructor(ARoutine: TSyntaxNode): Boolean;
    function IsReleasing(ARoutine: TSyntaxNode): Boolean;
    function GuardFix(AStatement: TSyntaxNode; const AField: string): TArray<TRuleFix>;
    procedure AddChecked(const AName: string);
    procedure AddAllChecked(const ANames: TArray<string>);
    procedure CollectChecks(ARoot: TSyntaxNode);
    procedure CollectShortCircuit(ANode: TSyntaxNode);
    procedure NoteGuards(ANode: TSyntaxNode);
    procedure ReportAccess(AAccess, AStatement: TSyntaxNode; const AField: string; const AItem: TNilAtDestroy);
    procedure CheckAccess(AAccess, ABody: TSyntaxNode);
    function VisitStep(ANode, ABody: TSyntaxNode): TSyntaxSearchStep;
    procedure CheckBody(ARoutine: TSyntaxNode);
    procedure CheckClass;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TDestructorCheck }

constructor TDestructorCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
end;

destructor TDestructorCheck.Destroy;
begin
  FScan.Free;
  inherited Destroy;
end;

function TDestructorCheck.Text(ANode: TSyntaxNode): string;
begin
  Result := SourceText(FContext.Text, ANode);
end;

/// <summary>Private Methode der Klasse, die nur aus dem Destruktor aufgerufen wird (FreeAll aus Destroy);
/// öffentliche Methoden rufen auch andere Units.</summary>
function TDestructorCheck.OnlyCalledFromDestructor(ARoutine: TSyntaxNode): Boolean;
var
  mOther: TSyntaxNode;
  mCallers: Integer;
begin
  Result := MatchText(MethodOf(ARoutine), FPrivateMethods);
  mCallers := 0;
  for mOther in FRoutines do
  begin
    if Result and (mOther <> ARoutine) and CallsMethod(mOther, MethodOf(ARoutine)) then
    begin
      Result := SameText(ClassOf(mOther), FQualifiedClass) and StartsWithWord(FContext.Text, mOther, 'destructor');
      Inc(mCallers);
    end;
  end;
  Result := Result and (mCallers > 0);
end;

/// <summary>Destruktoren und Methoden, die nur sie aufrufen; BeforeDestruction läuft nach einer Exception im
/// Konstruktor nicht.</summary>
function TDestructorCheck.IsReleasing(ARoutine: TSyntaxNode): Boolean;
begin
  Result := SameText(ClassOf(ARoutine), FQualifiedClass);
  Result := Result and (StartsWithWord(FContext.Text, ARoutine, 'destructor') or
    (not StartsWithWord(FContext.Text, ARoutine, 'constructor') and OnlyCalledFromDestructor(ARoutine)));
end;

/// <summary>Korrektur: "if Assigned(FFeld) then" vor eine Anweisung, die allein in einer Anweisungsliste steht.
/// </summary>
function TDestructorCheck.GuardFix(AStatement: TSyntaxNode; const AField: string): TArray<TRuleFix>;
var
  mOuter: string;
begin
  Result := nil;
  if (AStatement.Parent = nil) or (AStatement.Parent.Kind <> TSyntaxKind.Block) or
    (AStatement.StartPos.Line <> AStatement.EndPos.Line) or not LineIndent(FContext.Text, AStatement, mOuter) then
  begin
    Exit;
  end;
  Result := [TRuleFix.Create(cTexts[TFlowDestructorNotNilSafeText.WrapInAssigned].Fmt([AField]),
    [TRuleEdit.Create(NodeRange(AStatement), Format('if Assigned(%s) then', [AField]) + FLineBreak + mOuter +
    '  ' + Trim(Text(AStatement)))])];
end;

/// <summary>X gilt als geprüft, dazu jedes Feld, das jeder Konstruktor vor X setzt.</summary>
procedure TDestructorCheck.AddChecked(const AName: string);
var
  mItem: TGuardImplication;
begin
  FChecked := FChecked + [AName];
  for mItem in FScan.Implications do
  begin
    if SameText(mItem.Guard, AName) then
    begin
      FChecked := FChecked + mItem.Implied;
    end;
  end;
end;

procedure TDestructorCheck.AddAllChecked(const ANames: TArray<string>);
var
  mName: string;
begin
  for mName in ANames do
  begin
    AddChecked(mName);
  end;
end;

/// <summary>Assigned(X), X &lt;&gt; nil, X = nil unter ARoot sammeln: danach gilt X als geprüft.</summary>
procedure TDestructorCheck.CollectChecks(ARoot: TSyntaxNode);
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      AddAllChecked(NilCheckedPaths(ANode));
      Result := TSyntaxSearchStep.Descend;
    end);
end;

/// <summary>Linker Teil von "… and …": Assigned(X) und X &lt;&gt; nil schützen den rechten Teil (Kurzschluss,
/// #1109).</summary>
procedure TDestructorCheck.CollectShortCircuit(ANode: TSyntaxNode);
begin
  if (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) then
  begin
    CollectShortCircuit(ANode[0]);
  end
  else if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.ChildCount = 2) and SameText(ANode.Name, 'and') then
  begin
    CollectShortCircuit(ANode[0]);
    CollectShortCircuit(ANode[1]);
  end
  else if (ANode.Kind = TSyntaxKind.Call) or ((ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '<>')) then
  begin
    AddAllChecked(NilCheckedPaths(ANode));
  end;
end;

/// <summary>Abfragen und Zuweisungen in ANode, die die folgenden Zugriffe schützen.</summary>
procedure TDestructorCheck.NoteGuards(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  // if Assigned(FFeld) then …, while FFeld <> nil do …: die Bedingung schützt alles danach.
  if ANode.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.CaseStatement] then
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if not (ANode[mIndex].Kind in cFlowStatementKinds) then
      begin
        CollectChecks(ANode[mIndex]);
      end;
    end;
  end;
  if (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'and') and (ANode.ChildCount = 2) then
  begin
    CollectShortCircuit(ANode[0]);
  end;
  // Neu zugewiesen im Destruktor: der Wert stammt nicht mehr aus dem Konstruktor.
  if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and (FreedPath(ANode[0]) <> '') then
  begin
    FChecked := FChecked + [FreedPath(ANode[0])];
  end;
end;

procedure TDestructorCheck.ReportAccess(AAccess, AStatement: TSyntaxNode; const AField: string;
  const AItem: TNilAtDestroy);
var
  mAccess, mMessage: string;
begin
  mAccess := Trim(Text(AAccess));
  if AItem.Conditional then
  begin
    mMessage := cTexts[TFlowDestructorNotNilSafeText.Conditional].Fmt([AField, mAccess]);
  end
  else
  begin
    mMessage := cTexts[TFlowDestructorNotNilSafeText.Raises].Fmt([AItem.Raiser, AField, mAccess]);
  end;
  FReport.Add(NodeRange(AAccess), mMessage, TRuleConfidence.High, GuardFix(AStatement, AField));
end;

/// <summary>Zugriff FFeld.X (außer Free und DisposeOf), FFeld[…] oder FFeld^; je Anweisung und Feld ein Befund,
/// damit jede Korrektur ihre Anweisung schützt.</summary>
procedure TDestructorCheck.CheckAccess(AAccess, ABody: TSyntaxNode);
var
  mField, mKey: string;
  mItem: TNilAtDestroy;
  mStatement: TSyntaxNode;
begin
  mField := FreedPath(AAccess[0]);
  if (mField = '') or IsReleaseCall(AAccess) or MatchText(mField, FChecked) or not FScan.RiskOf(mField, mItem) then
  begin
    Exit;
  end;
  mStatement := EnclosingStatement(AAccess, ABody);
  mKey := mField + '@' + IntToStr(mStatement.StartOffset);
  if not MatchText(mKey, FReported) then
  begin
    FReported := FReported + [mKey];
    ReportAccess(AAccess, mStatement, mField, mItem);
  end;
end;

function TDestructorCheck.VisitStep(ANode, ABody: TSyntaxNode): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Descend;
  if IsRoutineBody(ANode) then
  begin
    Result := TSyntaxSearchStep.Skip;
    Exit;
  end;
  NoteGuards(ANode);
  if (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
    (ANode.ChildCount > 0) then
  begin
    CheckAccess(ANode, ABody);
  end;
end;

procedure TDestructorCheck.CheckBody(ARoutine: TSyntaxNode);
var
  mBody: TSyntaxNode;
begin
  mBody := ARoutine.FindChild(TSyntaxKind.Block);
  if mBody = nil then
  begin
    Exit;
  end;
  FChecked := nil;
  FReported := nil;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): Vorordnung wie die Rekursion, FChecked wächst in derselben Reihenfolge.
  mBody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := VisitStep(ANode, mBody);
    end);
end;

procedure TDestructorCheck.CheckClass;
var
  mClassType, mOther: TSyntaxNode;
  mFields: TArray<string>;
begin
  mClassType := FindClassType(FContext.Tree.Root, DeclaredClassName(FQualifiedClass));
  mFields := ClassFields(mClassType);
  if mFields = nil then
  begin
    Exit;
  end;
  FPrivateMethods := PrivateOf(mClassType);
  FScan.Start(mFields);
  for mOther in FRoutines do
  begin
    if SameText(ClassOf(mOther), FQualifiedClass) and StartsWithWord(FContext.Text, mOther, 'constructor') then
    begin
      FScan.Scan(mOther);
    end;
  end;
  if FScan.Risky = nil then
  begin
    Exit;
  end;
  for mOther in FRoutines do
  begin
    if IsReleasing(mOther) then
    begin
      CheckBody(mOther);
    end;
  end;
end;

procedure TDestructorCheck.Run;
var
  mRoutine: TSyntaxNode;
  mClasses: TArray<string>;
begin
  if (FContext.Tree = nil) or not ContainsText(FContext.Text, 'destructor') then
  begin
    Exit;
  end;
  FRoutines := TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext);
  FScan := TConstructorScan.Create(FContext.Text, FContext.Tree.Root, FRoutines,
    TRuleOptions.Bool(FContext.Options, 'onlyAfterRaisingCode', True));
  mClasses := nil;
  for mRoutine in FRoutines do
  begin
    FQualifiedClass := ClassOf(mRoutine);
    if (FQualifiedClass <> '') and not MatchText(FQualifiedClass, mClasses) and
      StartsWithWord(FContext.Text, mRoutine, 'destructor') then
    begin
      mClasses := mClasses + [FQualifiedClass];
      CheckClass;
    end;
  end;
end;

{ TDestructorNotNilSafeRule }

function TDestructorNotNilSafeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDestructorNotNilSafeRuleId, TRuleSeverity.Warning,
    cTexts[TFlowDestructorNotNilSafeText.Title].Text);
end;

procedure TDestructorNotNilSafeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TDestructorCheck;
begin
  mCheck := TDestructorCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe', cTexts);

end.
