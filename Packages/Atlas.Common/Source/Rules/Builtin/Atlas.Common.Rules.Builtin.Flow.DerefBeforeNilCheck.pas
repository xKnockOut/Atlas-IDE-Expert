unit Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck;

// Regel deref-before-nil-check aus Atlas.Common.Rules.Builtin.Flow (#269): X.… oder X^ steht vor der ersten
// Abfrage X = nil, X &lt;&gt; nil, Assigned(X) oder X is T auf demselben Weg, ohne dass X dazwischen geändert wird.
// Die Korrektur zieht eine direkt folgende if-Abfrage vor den Zugriff.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TDerefBeforeNilCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cDerefBeforeNilCheckRuleId = 'deref-before-nil-check';

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowDerefBeforeNilCheckText = (MoveCheck, UsedBeforeCheck, Title);

const
  cTexts: array[TFlowDerefBeforeNilCheckText] of TAtlasText = (
    (De: 'Prüfung vor den Zugriff ziehen'; En: 'Move the check before the access'),
    (De: '%s wird hier benutzt, aber erst in Zeile %d auf nil geprüft.';
     En: '%s is used here but only checked for nil in line %d.'),
    (De: 'Erst benutzt, dann auf nil geprüft'; En: 'Used first, checked for nil later'));

{$SCOPEDENUMS OFF}

function IsNilLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and SameText(ANode.Name, 'nil');
end;

/// <summary>Assigned(APath)?</summary>
function IsAssignedCall(ANode: TSyntaxNode; const APath: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and IsName(ANode[0], 'Assigned') and
    SameText(FreedPath(ANode[1]), APath);
end;

/// <summary>APath = nil oder APath &lt;&gt; nil (auch nil links)?</summary>
function IsNilComparison(ANode: TSyntaxNode; const APath: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and MatchText(ANode.Name, ['=', '<>']) and (ANode.ChildCount = 2);
  Result := Result and ((SameText(FreedPath(ANode[0]), APath) and IsNilLiteral(ANode[1])) or
    (SameText(FreedPath(ANode[1]), APath) and IsNilLiteral(ANode[0])));
end;

/// <summary>Enthält ARoot Assigned(APath), APath = nil oder APath &lt;&gt; nil?</summary>
function ContainsNilCheck(ARoot: TSyntaxNode; const APath: string): Boolean;
var
  mPath: string;
begin
  mPath := APath;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if IsAssignedCall(ANode, mPath) or IsNilComparison(ANode, mPath) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Enthält ARoot APath is TKlasse? Das ist für nil False und schützt wie Assigned (#1371).</summary>
function ContainsIsCheck(ARoot: TSyntaxNode; const APath: string): Boolean;
var
  mPath: string;
begin
  mPath := APath;
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'is') and (ANode.ChildCount = 2) and
        SameText(FreedPath(ANode[0]), mPath) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function NodeHasNilCheck(ANode: TFlowNode; const APath: string): Boolean;
var
  mPart: TSyntaxNode;
begin
  Result := False;
  for mPart in OwnParts(ANode.Syntax) do
  begin
    Result := Result or ContainsNilCheck(mPart, APath) or ContainsIsCheck(mPart, APath);
  end;
end;

/// <summary>Wurzeln der Zugriffe X.… und X^ in ARoot, in Textreihenfolge. X[…] zählt nicht: bei dynamischen
/// Arrays ist X &lt;&gt; nil die übliche Abfrage auf leer.</summary>
procedure CollectDerefs(ARoot: TSyntaxNode; var AList: TArray<TSyntaxNode>);
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) and
        (FreedPath(ANode[0]) <> '') then
      begin
        mFound := mFound + [ANode[0]];
      end;
    end);
  AList := AList + mFound;
end;

/// <summary>Wird APath dem Aufruf ANode als Argument übergeben?</summary>
function PassesPath(ANode: TSyntaxNode; const APath: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    Result := Result or SameText(FreedPath(ANode[mIndex]), APath);
  end;
end;

/// <summary>Kann der Ausdruck ANode selbst APath ändern? Ein Aufruf mit APath als Argument (bei Feldern und
/// globalen Variablen jeder Aufruf außer Assigned) oder @APath.</summary>
function ExpressionChangesPath(ANode: TSyntaxNode; const APath: string; ALocal: Boolean): Boolean;
begin
  if ANode.Kind = TSyntaxKind.Call then
  begin
    Result := (ANode.ChildCount > 0) and not IsName(ANode[0], 'Assigned');
    Result := Result and (not ALocal or PassesPath(ANode, APath));
  end
  else
  begin
    Result := (ANode.Kind = TSyntaxKind.AddressOf) and (ANode.ChildCount > 0) and
      SameText(FreedPath(ANode[0]), APath);
  end;
end;

function PartChangesPath(ARoot: TSyntaxNode; const APath: string; ALocal: Boolean): Boolean;
var
  mPath: string;
  mLocal: Boolean;
begin
  mPath := APath;
  mLocal := ALocal;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ExpressionChangesPath(ANode, mPath, mLocal) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Kann der Knoten APath ändern? Zuweisung, Schleifenvariable, Übergabe als Argument, @X; bei
/// Feldern und globalen Variablen (ALocal = False) jeder Aufruf.</summary>
function ChangesPath(ANode: TFlowNode; const APath: string; ALocal: Boolean): Boolean;
var
  mPart: TSyntaxNode;
begin
  Result := AssignsPath(ANode, APath);
  if Result or (ANode.Syntax = nil) then
  begin
    Exit;
  end;
  // X.Methode ohne Klammern ist ein Aufruf.
  Result := not ALocal and (ANode.Syntax.Kind = TSyntaxKind.CallStatement);
  for mPart in OwnParts(ANode.Syntax) do
  begin
    Result := Result or PartChangesPath(mPart, APath, ALocal);
  end;
end;

procedure AddNames(var ANames: TArray<string>; const AAdded: TArray<string>);
var
  mName: string;
begin
  for mName in AAdded do
  begin
    if not MatchText(mName, ANames) then
    begin
      ANames := ANames + [mName];
    end;
  end;
end;

/// <summary>Pfade, die die Routine irgendwo auf nil prüft; nur diese lohnen die Suche.</summary>
function CheckedNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mNames: TArray<string>;
begin
  mNames := nil;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      AddNames(mNames, NilCheckedPaths(ANode));
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := mNames;
end;

/// <summary>Folgt ANext im selben Block direkt auf AStatement?</summary>
function FollowsDirectly(AStatement, ANext: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
  mPosition: Integer;
begin
  mParent := AStatement.Parent;
  Result := (mParent <> nil) and (mParent = ANext.Parent);
  if Result then
  begin
    mPosition := PositionIn(mParent, AStatement);
    Result := (mPosition >= 0) and (mPosition + 1 < mParent.ChildCount) and (mParent[mPosition + 1] = ANext);
  end;
end;

/// <summary>Teilt "if Bedingung then Rumpf" ohne else; False bei else oder fehlenden Teilen.</summary>
function SplitIf(AIf: TSyntaxNode; out ACondition, ABody: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  ACondition := nil;
  ABody := nil;
  Result := True;
  for mIndex := 0 to AIf.ChildCount - 1 do
  begin
    if AIf[mIndex].Kind in cFlowStatementKinds then
    begin
      Result := Result and (ABody = nil);
      ABody := AIf[mIndex];
    end
    else if ACondition = nil then
    begin
      ACondition := AIf[mIndex];
    end;
  end;
  Result := Result and (ACondition <> nil) and (ABody <> nil);
end;

type
  /// <summary>Prüfung einer Unit für deref-before-nil-check; hält Text, Graph und die Pfade der Routine.
  /// </summary>
  TDerefCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FGraph: TControlFlowGraph;
    FChecked: TArray<string>;
    FLocals: TArray<string>;
    FDone: TArray<string>;
    FLineBreak: string;
    function CheckedBefore(ANode: TFlowNode; const APath: string): Boolean;
    function CheckAfter(ANode: TFlowNode; const APath: string; ALocal: Boolean): TFlowNode;
    function FreesToNil(ANode: TFlowNode; const APath: string): Boolean;
    function AssignedOnWay(AFrom, ATo: TFlowNode; const APath: string): Boolean;
    function GuardsLater(ANode, ACheck: TFlowNode; const APath: string): Boolean;
    function Source(ANode: TSyntaxNode): string;
    function Reindented(const AText, AIndent: string): string;
    function BodyText(ABody: TSyntaxNode; const AInner: string): string;
    function MoveCheckFix(AAccess, ACheck: TFlowNode; out AFix: TRuleFix): Boolean;
    procedure ReportDeref(ANode, ACheck: TFlowNode; ADeref: TSyntaxNode; const APath: string);
    procedure CheckDeref(ANode: TFlowNode; ADeref: TSyntaxNode);
    procedure CheckNode(ANode: TFlowNode);
    procedure CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TDerefCheck }

constructor TDerefCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
end;

/// <summary>Wird APath auf einem Weg zu ANode schon geprüft (ohne Zuweisung dazwischen)? Rückwärts beenden nur
/// sichere Zuweisungen den Weg: lieber eine Prüfung zu viel finden.</summary>
function TDerefCheck.CheckedBefore(ANode: TFlowNode; const APath: string): Boolean;
var
  mVisited: TArray<Boolean>;
  mQueue: TArray<TFlowNode>;
  mHead: Integer;
  mCurrent: TFlowNode;
begin
  Result := False;
  SetLength(mVisited, FGraph.Nodes.Count);
  mQueue := ANode.Predecessors.ToArray;
  mHead := 0;
  while not Result and (mHead < Length(mQueue)) do
  begin
    mCurrent := mQueue[mHead];
    Inc(mHead);
    if not mVisited[mCurrent.Index] then
    begin
      mVisited[mCurrent.Index] := True;
      Result := (mCurrent.Syntax <> nil) and NodeHasNilCheck(mCurrent, APath);
      if not Result and not AssignsPath(mCurrent, APath) then
      begin
        QueuePredecessors(mCurrent, mVisited, mQueue);
      end;
    end;
  end;
end;

/// <summary>Erste Prüfung von APath nach ANode ohne Änderung dazwischen; nil ohne.</summary>
function TDerefCheck.CheckAfter(ANode: TFlowNode; const APath: string; ALocal: Boolean): TFlowNode;
var
  mVisited: TArray<Boolean>;
  mQueue: TArray<TFlowNode>;
  mHead: Integer;
  mCurrent: TFlowNode;
begin
  Result := nil;
  SetLength(mVisited, FGraph.Nodes.Count);
  mQueue := nil;
  QueueSuccessors(ANode, mVisited, mQueue);
  mHead := 0;
  while (Result = nil) and (mHead < Length(mQueue)) do
  begin
    mCurrent := mQueue[mHead];
    Inc(mHead);
    if mVisited[mCurrent.Index] or (mCurrent = ANode) then
    begin
      Continue;
    end;
    mVisited[mCurrent.Index] := True;
    if (mCurrent.Syntax <> nil) and NodeHasNilCheck(mCurrent, APath) then
    begin
      Result := mCurrent;
    end
    else if not ChangesPath(mCurrent, APath, ALocal) then
    begin
      QueueSuccessors(mCurrent, mVisited, mQueue);
    end;
  end;
end;

/// <summary>FreeAndNil(APath) in ANode?</summary>
function TDerefCheck.FreesToNil(ANode: TFlowNode; const APath: string): Boolean;
var
  mFreed: string;
  mToNil: Boolean;
begin
  Result := FreedBy(ANode.Syntax, mFreed, mToNil) and mToNil and SameText(mFreed, APath);
end;

/// <summary>Weist ein Weg von AFrom nach ATo APath neu zu? Dann gilt die Prüfung in ATo auch dem neuen Wert
/// (X := List[I]; if X.Kind = … then X := X.FindChild(…); if X = nil then; #1109). FreeAndNil(X) setzt X ebenso
/// neu (etwa im except-Zweig nach einem gescheiterten Laden): die spätere Prüfung gilt diesem Weg.</summary>
function TDerefCheck.AssignedOnWay(AFrom, ATo: TFlowNode; const APath: string): Boolean;
var
  mVisited: TArray<Boolean>;
  mQueue: TArray<TFlowNode>;
  mHead: Integer;
  mCurrent: TFlowNode;
begin
  Result := False;
  SetLength(mVisited, FGraph.Nodes.Count);
  mQueue := ATo.Predecessors.ToArray;
  mHead := 0;
  while not Result and (mHead < Length(mQueue)) do
  begin
    mCurrent := mQueue[mHead];
    Inc(mHead);
    if not mVisited[mCurrent.Index] and (mCurrent <> AFrom) then
    begin
      mVisited[mCurrent.Index] := True;
      Result := AssignsPath(mCurrent, APath) or FreesToNil(mCurrent, APath);
      QueuePredecessors(mCurrent, mVisited, mQueue);
    end;
  end;
end;

/// <summary>Gilt die spätere Prüfung ACheck dem Zugriff in ANode?</summary>
function TDerefCheck.GuardsLater(ANode, ACheck: TFlowNode; const APath: string): Boolean;
begin
  // Eine Prüfung weiter oben, die erst der nächste Schleifendurchlauf erreicht, schützt den Zugriff.
  Result := (ACheck <> nil) and (ACheck.Syntax.StartOffset >= ANode.Syntax.StartOffset);
  // Nur wenn jeder Weg zur Prüfung durch den Zugriff führt; sonst gilt sie den anderen Wegen
  // (X := TX.Create; X.Init; … if X <> nil nach einem Zweig ohne Create).
  Result := Result and (FGraph.Dominates(ANode, ACheck) = TFlowAnswer.Yes) and
    not AssignedOnWay(ANode, ACheck, APath);
  // while X <> nil do … X := X.Parent: die Bedingung gilt den späteren Durchläufen.
  Result := Result and not ((ACheck.Syntax.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and
    SubtreeAssigns(ACheck.Syntax, APath));
end;

function TDerefCheck.Source(ANode: TSyntaxNode): string;
begin
  Result := SourceText(FContext.Text, ANode);
end;

/// <summary>Zeilen von AText mit AIndent davor; führende und folgende Leerzeilen fallen weg.</summary>
function TDerefCheck.Reindented(const AText, AIndent: string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]) do
  begin
    if Trim(mLine) <> '' then
    begin
      Result := Result + AIndent + mLine + FLineBreak;
    end;
  end;
end;

/// <summary>Rumpf der Abfrage als Zeilen; bei begin … end behalten sie ihre Einrückung.</summary>
function TDerefCheck.BodyText(ABody: TSyntaxNode; const AInner: string): string;
begin
  if ABody.Kind = TSyntaxKind.Block then
  begin
    Result := Source(ABody);
    Result := Reindented(Copy(Result, 6, Length(Result) - 8), '');
  end
  else
  begin
    Result := AInner + Trim(Source(ABody)) + ';' + FLineBreak;
  end;
end;

/// <summary>Prüfung als if ohne else direkt nach dem Zugriff im selben Block: if … then begin Zugriff; Rumpf end.
/// </summary>
function TDerefCheck.MoveCheckFix(AAccess, ACheck: TFlowNode; out AFix: TRuleFix): Boolean;
var
  mAccess, mIfNode, mBody, mCondition: TSyntaxNode;
  mOuter, mInner, mText: string;
begin
  mAccess := AAccess.Syntax;
  mIfNode := ACheck.Syntax;
  Result := (AAccess.Kind = TFlowNodeKind.Statement) and (ACheck.Kind = TFlowNodeKind.Condition) and
    (mIfNode.Kind = TSyntaxKind.IfStatement);
  Result := Result and FollowsDirectly(mAccess, mIfNode) and SplitIf(mIfNode, mCondition, mBody) and
    LineIndent(FContext.Text, mAccess, mOuter);
  if not Result then
  begin
    Exit;
  end;
  mInner := mOuter + '  ';
  mText := 'if ' + Trim(Source(mCondition)) + ' then' + FLineBreak + mOuter + 'begin' + FLineBreak +
    mInner + Trim(Source(mAccess)) + ';' + FLineBreak + BodyText(mBody, mInner) + mOuter + 'end';
  AFix := TRuleFix.Create(cTexts[TFlowDerefBeforeNilCheckText.MoveCheck].Text,
    [TRuleEdit.Create(TTextRange.Create(mAccess.StartPos, mIfNode.EndPos), mText)]);
end;

procedure TDerefCheck.ReportDeref(ANode, ACheck: TFlowNode; ADeref: TSyntaxNode; const APath: string);
var
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  mFixes := nil;
  if MoveCheckFix(ANode, ACheck, mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(NodeRange(ADeref), cTexts[TFlowDerefBeforeNilCheckText.UsedBeforeCheck].Fmt(
    [APath, ACheck.Syntax.StartPos.Line + 1]), TRuleConfidence.Medium, mFixes);
end;

procedure TDerefCheck.CheckDeref(ANode: TFlowNode; ADeref: TSyntaxNode);
var
  mPath, mKey: string;
  mCheck: TFlowNode;
begin
  mPath := FreedPath(ADeref);
  // X := X.Next: die spätere Prüfung gilt dem neuen Wert. Ebenso Supports(Y, IX, X) and X.Foo: die Übergabe im
  // selben Ausdruck setzt X erst.
  if not MatchText(mPath, FChecked) or NodeHasNilCheck(ANode, mPath) or ChangesPath(ANode, mPath, True) then
  begin
    Exit;
  end;
  mCheck := CheckAfter(ANode, mPath, MatchText(mPath, FLocals));
  if not GuardsLater(ANode, mCheck, mPath) then
  begin
    Exit;
  end;
  mKey := LowerCase(mPath) + '@' + IntToStr(mCheck.Index);
  if MatchText(mKey, FDone) or CheckedBefore(ANode, mPath) then
  begin
    Exit;
  end;
  FDone := FDone + [mKey];
  ReportDeref(ANode, mCheck, ADeref, mPath);
end;

procedure TDerefCheck.CheckNode(ANode: TFlowNode);
var
  mDerefs: TArray<TSyntaxNode>;
  mDeref, mPart: TSyntaxNode;
begin
  if (ANode.Syntax = nil) or not (ANode.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) then
  begin
    Exit;
  end;
  mDerefs := nil;
  for mPart in OwnParts(ANode.Syntax) do
  begin
    CollectDerefs(mPart, mDerefs);
  end;
  for mDeref in mDerefs do
  begin
    CheckDeref(ANode, mDeref);
  end;
end;

procedure TDerefCheck.CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
var
  mNode: TFlowNode;
begin
  FChecked := CheckedNames(ARoutine);
  if FChecked = nil then
  begin
    Exit;
  end;
  FGraph := TRuleDerived.Graph(ACache, FContext, ARoutine);
  if not FGraph.Complete then
  begin
    Exit;
  end;
  FLocals := LocalNames(ARoutine);
  FDone := nil;
  for mNode in FGraph.Nodes do
  begin
    CheckNode(mNode);
  end;
end;

procedure TDerefCheck.Run;
var
  mCache: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(FContext);
  for mRoutine in TRuleDerived.Routines(mCache, FContext) do
  begin
    CheckRoutine(mCache, mRoutine);
  end;
end;

{ TDerefBeforeNilCheckRule }

function TDerefBeforeNilCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDerefBeforeNilCheckRuleId, TRuleSeverity.Warning,
    cTexts[TFlowDerefBeforeNilCheckText.Title].Text);
end;

procedure TDerefBeforeNilCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TDerefCheck;
begin
  mCheck := TDerefCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck', cTexts);

end.
