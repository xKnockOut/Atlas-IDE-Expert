unit Atlas.Common.Rules.Builtin.Flow.UseAfterFree;

// Regel use-after-free aus Atlas.Common.Rules.Builtin.Flow (#269): Nach X.Free, X.Destroy, X.DisposeOf,
// FreeAndNil(X) oder Dispose(X) liest ein Weg des Kontrollflusses X wieder. Eine Zuweisung an X, die Übergabe als
// Argument und @X beenden den Weg; Assigned(X) und Vergleiche mit nil trennen ihn. Bei einem Feld der Klasse
// beendet auch der Aufruf einer eigenen Methode den Weg: Sie kann das Feld neu belegen.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TUseAfterFreeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cUseAfterFreeRuleId = 'use-after-free';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowUseAfterFreeText = (FreedAndNil, Freed, JumpToFree, Title);

const
  cTexts: array[TFlowUseAfterFreeText] of TAtlasText = (
    (De: '%s wurde in Zeile %d mit FreeAndNil freigegeben und ist hier nil.';
     En: '%s was freed with FreeAndNil in line %d and is nil here.'),
    (De: '%s wurde in Zeile %d freigegeben und wird hier wieder gelesen.';
     En: '%s was freed in line %d and is read here again.'),
    (De: 'Zur Freigabe in Zeile %d springen'; En: 'Jump to the free in line %d'),
    (De: 'Objekt nach Free weiter benutzt'; En: 'Object still used after Free'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Prüfung einer Unit für use-after-free; hält den Graphen der Routine, die Freigabe und den Stand des
  /// gerade untersuchten Knotens.</summary>
  TUseAfterFreeCheck = class
  strict private
    FReport: IRuleReport;
    FGraph: TControlFlowGraph;
    FReported: TArray<Integer>;
    FFree: TFlowNode;
    FPath: string;
    FToNil: Boolean;
    FUses: TArray<TSyntaxNode>;
    FStops: Boolean;
    FGuarded: Boolean;
    /// <summary>Felder und Methoden der Klasse der aktuellen Routine.</summary>
    FFields: TArray<string>;
    FMethods: TArray<string>;
    /// <summary>Ist FPath ein Feld der Klasse? Dann kann eine eigene Methode es neu belegen.</summary>
    FIsField: Boolean;
    function CallsOwnMethod(AStatement: TSyntaxNode): Boolean;
    procedure CollectMembers(ARoot, ARoutine: TSyntaxNode);
    function AlreadyReported(AOffset: Integer): Boolean;
    function VisitAccess(ANode: TSyntaxNode): Integer;
    procedure VisitArgument(const ACallee: string; AArgument: TSyntaxNode);
    procedure VisitCall(ANode: TSyntaxNode);
    function VisitAddress(ANode: TSyntaxNode): Integer;
    procedure VisitBinary(ANode: TSyntaxNode);
    function FirstChildToVisit(ANode: TSyntaxNode): Integer;
    procedure Visit(ARoot: TSyntaxNode);
    procedure Inspect(ASyntax: TSyntaxNode);
    function StopsAt(ANode: TFlowNode): Boolean;
    procedure ReportAccess(ANode: TFlowNode; AAccess: TSyntaxNode);
    function WalksOn(ANode: TFlowNode): Boolean;
    procedure Follow(AFree: TFlowNode; const APath: string; AToNil: Boolean);
    procedure CheckGraph;
  public
    constructor Create(const AReport: IRuleReport);
    procedure Run(const AContext: TRuleContext);
  end;

{ TUseAfterFreeCheck }

constructor TUseAfterFreeCheck.Create(const AReport: IRuleReport);
begin
  inherited Create;
  FReport := AReport;
end;

function TUseAfterFreeCheck.AlreadyReported(AOffset: Integer): Boolean;
var
  mOffset: Integer;
begin
  Result := False;
  for mOffset in FReported do
  begin
    Result := Result or (mOffset = AOffset);
  end;
end;

/// <summary>X.…, X[…], X^: ein Zugriff; danach nicht mehr in X selbst absteigen.</summary>
function TUseAfterFreeCheck.VisitAccess(ANode: TSyntaxNode): Integer;
begin
  Result := 0;
  if (ANode.ChildCount > 0) and SameText(FreedPath(ANode[0]), FPath) then
  begin
    // Nach FreeAndNil ist ein weiteres Free harmlos.
    if not (FToNil and (ANode.Kind = TSyntaxKind.MemberAccess) and SameText(ANode.Name, 'Free')) then
    begin
      FUses := FUses + [ANode[0]];
    end;
    Result := 1;
  end;
end;

procedure TUseAfterFreeCheck.VisitArgument(const ACallee: string; AArgument: TSyntaxNode);
begin
  if MatchText(ACallee, ['Assigned', 'FreeAndNil']) and not FToNil then
  begin
    // Nach Free: Assigned(X) ist immer True, FreeAndNil(X) gibt doppelt frei.
    FUses := FUses + [AArgument];
  end
  else if SameText(ACallee, 'Assigned') then
  begin
    FGuarded := True;
  end
  else
  begin
    // Übergabe: die Routine kann X neu setzen oder nur vergleichen (List.Remove(X)).
    FStops := True;
  end;
end;

procedure TUseAfterFreeCheck.VisitCall(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mCallee: string;
begin
  mCallee := '';
  if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.Identifier) then
  begin
    mCallee := ANode[0].Name;
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    if SameText(FreedPath(ANode[mIndex]), FPath) then
    begin
      VisitArgument(mCallee, ANode[mIndex]);
    end;
  end;
end;

/// <summary>@X beendet den Weg; die Kinder bleiben aus.</summary>
function TUseAfterFreeCheck.VisitAddress(ANode: TSyntaxNode): Integer;
begin
  Result := 0;
  if (ANode.ChildCount > 0) and SameText(FreedPath(ANode[0]), FPath) then
  begin
    FStops := True;
    Result := ANode.ChildCount;
  end;
end;

/// <summary>X = nil, X &lt;&gt; nil: eine Abfrage, die den Weg trennt.</summary>
procedure TUseAfterFreeCheck.VisitBinary(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    FGuarded := FGuarded or SameText(FreedPath(ANode[mIndex]), FPath);
  end;
end;

/// <summary>Wertet ANode aus; Ergebnis: ab diesem Kind weiter absteigen (ChildCount: gar nicht).</summary>
function TUseAfterFreeCheck.FirstChildToVisit(ANode: TSyntaxNode): Integer;
begin
  case ANode.Kind of
    TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl:
      Result := ANode.ChildCount;
    TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference:
      Result := VisitAccess(ANode);
    TSyntaxKind.Call:
      begin
        VisitCall(ANode);
        Result := 0;
      end;
    TSyntaxKind.AddressOf:
      Result := VisitAddress(ANode);
    TSyntaxKind.BinaryExpr:
      begin
        VisitBinary(ANode);
        Result := 0;
      end;
  else
    // Alle anderen Knoten: sämtliche Kinder besuchen.
    Result := 0;
  end;
end;

procedure TUseAfterFreeCheck.Visit(ARoot: TSyntaxNode);
var
  mIndex, mFirst: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mFirst := FirstChildToVisit(mNode);
      for mIndex := mNode.ChildCount - 1 downto mFirst do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Zugriffe auf FPath im eigenen Teil der Anweisung bzw. Bedingung ASyntax.</summary>
procedure TUseAfterFreeCheck.Inspect(ASyntax: TSyntaxNode);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mAllChildren: Boolean;
begin
  mAllChildren := ASyntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
  for mIndex := 0 to ASyntax.ChildCount - 1 do
  begin
    mChild := ASyntax[mIndex];
    if not mAllChildren and (mChild.Kind in cFlowStatementKinds) then
    begin
      Continue;
    end;
    if (mIndex = 0) and (ASyntax.Kind = TSyntaxKind.AssignStatement) and SameText(FreedPath(mChild), FPath) then
    begin
      FStops := True;
    end
    else if (ASyntax.Kind = TSyntaxKind.WithStatement) and SameText(FreedPath(mChild), FPath) then
    begin
      FUses := FUses + [mChild];
    end
    else
    begin
      Visit(mChild);
    end;
  end;
end;

/// <summary>Weist ANode FPath neu zu? for und for … in tun das in jedem Durchlauf mit der Schleifenvariablen.
/// </summary>
function TUseAfterFreeCheck.StopsAt(ANode: TFlowNode): Boolean;
begin
  Result := SameText(ANode.Defines, FPath);
  if not Result and (ANode.Kind = TFlowNodeKind.Condition) then
  begin
    Result := (ANode.Syntax.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
      SameText(ANode.Syntax.Name, FPath);
  end;
end;

procedure TUseAfterFreeCheck.ReportAccess(ANode: TFlowNode; AAccess: TSyntaxNode);
var
  mConfidence: TRuleConfidence;
  mFreeLine: Integer;
  mMessage: string;
begin
  if AlreadyReported(AAccess.StartOffset) then
  begin
    Exit;
  end;
  FReported := FReported + [AAccess.StartOffset];
  // Im selben Block nacheinander: der Zugriff folgt sicher auf die Freigabe.
  mConfidence := TRuleConfidence.Medium;
  if (ANode.Syntax.Parent = FFree.Syntax.Parent) and (ANode.Syntax.StartOffset > FFree.Syntax.StartOffset) then
  begin
    mConfidence := TRuleConfidence.High;
  end;
  mFreeLine := FFree.Syntax.StartPos.Line + 1;
  if FToNil then
  begin
    mMessage := cTexts[TFlowUseAfterFreeText.FreedAndNil].Fmt([FPath, mFreeLine]);
  end
  else
  begin
    mMessage := cTexts[TFlowUseAfterFreeText.Freed].Fmt([FPath, mFreeLine]);
  end;
  FReport.Add(NodeRange(AAccess), mMessage, mConfidence,
    [TRuleFix.Jump(cTexts[TFlowUseAfterFreeText.JumpToFree].Fmt([mFreeLine]), FFree.Syntax.StartPos)]);
end;

/// <summary>Ruft AStatement eine Methode der eigenen Klasse auf (Reset; Self.Reset(1))? Sie kann ein Feld neu
/// belegen (FP-Prüfung 28.10.2026: FList.Free; Reset; FList.Add(…)).</summary>
function TUseAfterFreeCheck.CallsOwnMethod(AStatement: TSyntaxNode): Boolean;
var
  mTarget: TSyntaxNode;
  mName: string;
begin
  Result := False;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) then
  begin
    Exit;
  end;
  mName := AStatement.Name;
  if AStatement.ChildCount > 0 then
  begin
    mTarget := AStatement[0];
    if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
    begin
      mTarget := mTarget[0];
    end;
    // Name oder Self.Name.
    mName := FreedPath(mTarget);
  end;
  Result := (mName <> '') and MatchText(mName, FMethods);
end;

procedure TUseAfterFreeCheck.CollectMembers(ARoot, ARoutine: TSyntaxNode);
var
  mClass, mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
  mIndex: Integer;
begin
  FFields := nil;
  FMethods := nil;
  if ClassOf(ARoutine) = '' then
  begin
    Exit;
  end;
  mClass := FindClassType(ARoot, DeclaredClassName(ClassOf(ARoutine)));
  FFields := ClassFields(mClass);
  if mClass = nil then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(mClass);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl] then
      begin
        FMethods := FMethods + [ShortName(mNode.Name)];
        Continue;
      end;
      for mIndex := 0 to mNode.ChildCount - 1 do
      begin
        if mNode[mIndex].Kind <> TSyntaxKind.TypeSection then
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Meldet die Zugriffe in ANode; True, wenn der Weg hinter ANode weitergeht.</summary>
function TUseAfterFreeCheck.WalksOn(ANode: TFlowNode): Boolean;
var
  mAccess: TSyntaxNode;
begin
  FStops := StopsAt(ANode);
  FGuarded := False;
  FUses := nil;
  if (ANode.Syntax <> nil) and not FStops then
  begin
    Inspect(ANode.Syntax);
  end;
  FStops := FStops or FIsField and CallsOwnMethod(ANode.Syntax);
  Result := False;
  if not (FGuarded and FToNil) then
  begin
    for mAccess in FUses do
    begin
      ReportAccess(ANode, mAccess);
    end;
    Result := not (FStops or FGuarded);
  end;
end;

procedure TUseAfterFreeCheck.Follow(AFree: TFlowNode; const APath: string; AToNil: Boolean);
var
  mVisited: TArray<Boolean>;
  mQueue: TArray<TFlowNode>;
  mHead: Integer;
  mCurrent: TFlowNode;
begin
  FFree := AFree;
  FPath := APath;
  FToNil := AToNil;
  FIsField := MatchText(APath, FFields) or StartsText('Self.', APath) and
    MatchText(Copy(APath, Length('Self.') + 1, MaxInt), FFields);
  SetLength(mVisited, FGraph.Nodes.Count);
  mQueue := nil;
  QueueSuccessors(AFree, mVisited, mQueue);
  mHead := 0;
  while mHead < Length(mQueue) do
  begin
    mCurrent := mQueue[mHead];
    Inc(mHead);
    if not mVisited[mCurrent.Index] then
    begin
      mVisited[mCurrent.Index] := True;
      if WalksOn(mCurrent) then
      begin
        QueueSuccessors(mCurrent, mVisited, mQueue);
      end;
    end;
  end;
  FUses := nil;
end;

procedure TUseAfterFreeCheck.CheckGraph;
var
  mNode: TFlowNode;
  mPath: string;
  mToNil: Boolean;
begin
  for mNode in FGraph.Nodes do
  begin
    if (mNode.Kind = TFlowNodeKind.Statement) and FreedBy(mNode.Syntax, mPath, mToNil) then
    begin
      Follow(mNode, mPath, mToNil);
    end;
  end;
end;

procedure TUseAfterFreeCheck.Run(const AContext: TRuleContext);
var
  mCache: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(AContext);
  for mRoutine in TRuleDerived.Routines(mCache, AContext) do
  begin
    FGraph := TRuleDerived.Graph(mCache, AContext, mRoutine);
    if FGraph.Complete then
    begin
      CollectMembers(AContext.Tree.Root, mRoutine);
      CheckGraph;
    end;
  end;
end;

{ TUseAfterFreeRule }

function TUseAfterFreeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUseAfterFreeRuleId, TRuleSeverity.Error, cTexts[TFlowUseAfterFreeText.Title].Text);
end;

procedure TUseAfterFreeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUseAfterFreeCheck;
begin
  mCheck := TUseAfterFreeCheck.Create(AReport);
  try
    mCheck.Run(AContext);
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.UseAfterFree', cTexts);

end.
