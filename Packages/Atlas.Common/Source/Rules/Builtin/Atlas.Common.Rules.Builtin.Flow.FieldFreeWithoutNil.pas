unit Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil;

// Regel field-free-without-nil aus Atlas.Common.Rules.Builtin.Flow (#269): Ein Feld wird mit X.Free freigegeben,
// und ein Weg erreicht das Ende der Methode, ohne das Feld neu zu setzen. Ausgenommen sind Destruktoren, Methoden
// aus ignoreMethods, DUnitX-Methoden mit [TearDown] und Methoden, die nur aus solchen aufgerufen werden.
// Korrektur: FreeAndNil(X).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TFieldFreeWithoutNilRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option ignoreMethods.</summary>
    class function DefaultIgnoreMethods: TArray<string>; static;
  end;

const
  cFieldFreeWithoutNilRuleId = 'field-free-without-nil';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowFieldFreeWithoutNilText = (StaysSet, Title);

const
  cTexts: array[TFlowFieldFreeWithoutNilText] of TAtlasText = (
    (De: '%s bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.';
     En: '%s stays set after Free; a later access hits freed memory.'),
    (De: 'Feld freigegeben, Verweis bleibt stehen'; En: 'Field freed, reference remains'));

{$SCOPEDENUMS OFF}

/// <summary>Methoden der Klassendeklaration AClass mit [TearDown] oder [TearDownFixture] (DUnitX).</summary>
function TearDownMethods(AClass: TSyntaxNode): TArray<string>;

  procedure Visit(AE: TSyntaxNode);
  var
    mIndex: Integer;
    mPending: Boolean;
  begin
    mPending := False;
    for mIndex := 0 to AE.ChildCount - 1 do
    begin
      if AE[mIndex].Kind = TSyntaxKind.Attribute then
      begin
        mPending := mPending or MatchText(AE[mIndex].Name, ['TearDown', 'TearDownFixture']);
      end
      else
      begin
        if mPending and (AE[mIndex].Name <> '') then
        begin
          Result := Result + [AE[mIndex].Name];
        end;
        mPending := False;
        if AE[mIndex].Kind = TSyntaxKind.Visibility then
        begin
          Visit(AE[mIndex]);
        end;
      end;
    end;
  end;

begin
  Result := nil;
  if AClass <> nil then
  begin
    Visit(AClass);
  end;
end;

/// <summary>X.Free bzw. X.Free(); liefert X, sonst nil.</summary>
function FreeTarget(AStatement: TSyntaxNode): TSyntaxNode;
var
  mCallee: TSyntaxNode;
begin
  Result := nil;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mCallee := AStatement[0];
  if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount = 1) then
  begin
    mCallee := mCallee[0];
  end;
  if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount = 1) and SameText(mCallee.Name, 'Free') then
  begin
    Result := mCallee[0];
  end;
end;

type
  /// <summary>Prüfung einer Unit für field-free-without-nil; hält die Routinen, die Klasse und den Graphen der
  /// geprüften Methode.</summary>
  TFieldFreeCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRoutines: TArray<TSyntaxNode>;
    FGraph: TControlFlowGraph;
    FIgnore: TArray<string>;
    FFields: TArray<string>;
    FLocals: TArray<string>;
    FTearDowns: TArray<string>;
    FQualifiedClass: string;
    function Text(ANode: TSyntaxNode): string;
    function Releasing(ARoutine: TSyntaxNode): Boolean;
    function OnlyCalledWhileReleasing(ARoutine: TSyntaxNode): Boolean;
    function AssignerMethod(const AName, APath: string): Boolean;
    function IsAssignerCall(ACallee: TSyntaxNode; const APath: string): Boolean;
    function PartCallsAssigner(ARoot: TSyntaxNode; const APath: string): Boolean;
    function CallsAssigner(ANode: TFlowNode; const APath: string): Boolean;
    function ReachesEnd(AFree: TFlowNode; const APath: string): Boolean;
    procedure CheckStatement(ANode: TFlowNode);
    function PrepareRoutine(ARoutine: TSyntaxNode): Boolean;
    procedure CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TFieldFreeCheck }

constructor TFieldFreeCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TFieldFreeCheck.Text(ANode: TSyntaxNode): string;
begin
  Result := SourceText(FContext.Text, ANode);
end;

/// <summary>Destruktor, Methode aus ignoreMethods oder mit [TearDown].</summary>
function TFieldFreeCheck.Releasing(ARoutine: TSyntaxNode): Boolean;
begin
  Result := MatchText(MethodOf(ARoutine), FIgnore) or StartsText('destructor', Trim(Text(ARoutine))) or
    MatchText(MethodOf(ARoutine), FTearDowns);
end;

/// <summary>Wird die Methode nur aus freigebenden Methoden der Klasse aufgerufen (FreeFeatures aus Destroy)?
/// </summary>
function TFieldFreeCheck.OnlyCalledWhileReleasing(ARoutine: TSyntaxNode): Boolean;
var
  mOther: TSyntaxNode;
  mCallers: Integer;
begin
  mCallers := 0;
  Result := True;
  for mOther in FRoutines do
  begin
    if Result and (mOther <> ARoutine) and CallsMethod(mOther, MethodOf(ARoutine)) then
    begin
      Result := StartsText(FQualifiedClass + '.', mOther.Name) and Releasing(mOther);
      Inc(mCallers);
    end;
  end;
  Result := Result and (mCallers > 0);
end;

/// <summary>Methode derselben Klasse, die APath zuweist.</summary>
function TFieldFreeCheck.AssignerMethod(const AName, APath: string): Boolean;
var
  mOther: TSyntaxNode;
begin
  Result := False;
  for mOther in FRoutines do
  begin
    Result := Result or (SameText(mOther.Name, FQualifiedClass + '.' + AName) and SubtreeAssigns(mOther, APath));
  end;
end;

function TFieldFreeCheck.IsAssignerCall(ACallee: TSyntaxNode; const APath: string): Boolean;
var
  mName: string;
begin
  mName := FreedPath(ACallee);
  Result := (mName <> '') and AssignerMethod(mName, APath);
end;

function TFieldFreeCheck.PartCallsAssigner(ARoot: TSyntaxNode; const APath: string): Boolean;
var
  mPath: string;
begin
  mPath := APath;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and IsAssignerCall(ANode[0], mPath) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Ruft der Knoten eine Methode der Klasse auf, die APath neu setzt (Laden; Self.Laden; Laden(…))?
/// </summary>
function TFieldFreeCheck.CallsAssigner(ANode: TFlowNode; const APath: string): Boolean;
var
  mPart: TSyntaxNode;
begin
  Result := False;
  if ANode.Syntax = nil then
  begin
    Exit;
  end;
  // Aufruf ohne Klammern: "Laden;" bzw. "Self.Laden;".
  if (ANode.Syntax.Kind = TSyntaxKind.CallStatement) and (ANode.Syntax.ChildCount > 0) then
  begin
    Result := IsAssignerCall(ANode.Syntax[0], APath);
  end;
  for mPart in OwnParts(ANode.Syntax) do
  begin
    Result := Result or PartCallsAssigner(mPart, APath);
  end;
end;

/// <summary>Erreicht ein Weg vom Free das normale Ende der Methode, ohne das Feld neu zu setzen?</summary>
function TFieldFreeCheck.ReachesEnd(AFree: TFlowNode; const APath: string): Boolean;
var
  mVisited: TArray<Boolean>;
  mQueue: TArray<TFlowNode>;
  mHead: Integer;
  mCurrent: TFlowNode;
begin
  Result := False;
  SetLength(mVisited, FGraph.Nodes.Count);
  mQueue := nil;
  QueueSuccessors(AFree, mVisited, mQueue);
  mHead := 0;
  while not Result and (mHead < Length(mQueue)) do
  begin
    mCurrent := mQueue[mHead];
    Inc(mHead);
    if mVisited[mCurrent.Index] or (mCurrent = AFree) then
    begin
      Continue;
    end;
    mVisited[mCurrent.Index] := True;
    Result := mCurrent = FGraph.ExitNode;
    if not Result and not AssignsPath(mCurrent, APath) and not CallsAssigner(mCurrent, APath) then
    begin
      QueueSuccessors(mCurrent, mVisited, mQueue);
    end;
  end;
end;

procedure TFieldFreeCheck.CheckStatement(ANode: TFlowNode);
var
  mTarget: TSyntaxNode;
  mPath, mReplacement: string;
begin
  mTarget := FreeTarget(ANode.Syntax);
  mPath := FreedPath(mTarget);
  if (mPath = '') or MatchText(mPath, FLocals) or not MatchText(mPath, FFields) or not ReachesEnd(ANode, mPath) then
  begin
    Exit;
  end;
  mReplacement := Format('FreeAndNil(%s)', [Text(mTarget)]);
  FReport.Add(NodeRange(ANode.Syntax), cTexts[TFlowFieldFreeWithoutNilText.StaysSet].Fmt([mPath]),
    TRuleConfidence.Medium,
    [TRuleFix.Create(mReplacement, [TRuleEdit.Create(NodeRange(ANode.Syntax), mReplacement)])]);
end;

/// <summary>Stellt Klasse, Felder und TearDown-Methoden der Methode ARoutine bereit; False, wenn sie nicht zu
/// prüfen ist.</summary>
function TFieldFreeCheck.PrepareRoutine(ARoutine: TSyntaxNode): Boolean;
var
  mDot: Integer;
  mClassType: TSyntaxNode;
begin
  mDot := LastDelimiter('.', ARoutine.Name);
  Result := mDot > 0;
  if not Result then
  begin
    Exit;
  end;
  FQualifiedClass := Copy(ARoutine.Name, 1, mDot - 1);
  mClassType := FindClassType(FContext.Tree.Root, DeclaredClassName(FQualifiedClass));
  FFields := ClassFields(mClassType);
  Result := FFields <> nil;
  if Result then
  begin
    FTearDowns := TearDownMethods(mClassType);
    Result := not Releasing(ARoutine) and not OnlyCalledWhileReleasing(ARoutine);
  end;
end;

procedure TFieldFreeCheck.CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
var
  mNode: TFlowNode;
begin
  if not PrepareRoutine(ARoutine) then
  begin
    Exit;
  end;
  FLocals := LocalNames(ARoutine);
  FGraph := TRuleDerived.Graph(ACache, FContext, ARoutine);
  if not FGraph.Complete then
  begin
    Exit;
  end;
  for mNode in FGraph.Nodes do
  begin
    if mNode.Kind = TFlowNodeKind.Statement then
    begin
      CheckStatement(mNode);
    end;
  end;
end;

procedure TFieldFreeCheck.Run;
var
  mCache: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  FIgnore := TRuleOptions.Strings(FContext.Options, 'ignoreMethods', TFieldFreeWithoutNilRule.DefaultIgnoreMethods);
  mCache := TRuleDerived.Open(FContext);
  FRoutines := TRuleDerived.Routines(mCache, FContext);
  for mRoutine in FRoutines do
  begin
    CheckRoutine(mCache, mRoutine);
  end;
end;

{ TFieldFreeWithoutNilRule }

function TFieldFreeWithoutNilRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cFieldFreeWithoutNilRuleId, TRuleSeverity.Warning,
    cTexts[TFlowFieldFreeWithoutNilText.Title].Text);
end;

class function TFieldFreeWithoutNilRule.DefaultIgnoreMethods: TArray<string>;
begin
  Result := ['Destroy', 'BeforeDestruction'];
end;

procedure TFieldFreeWithoutNilRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TFieldFreeCheck;
begin
  mCheck := TFieldFreeCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil', cTexts);

end.
