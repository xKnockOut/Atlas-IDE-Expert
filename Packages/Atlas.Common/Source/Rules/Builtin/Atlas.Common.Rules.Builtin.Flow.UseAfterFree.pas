unit Atlas.Common.Rules.Builtin.Flow.UseAfterFree;

// Regel use-after-free aus Atlas.Common.Rules.Builtin.Flow (#269): Nach X.Free, X.Destroy, X.DisposeOf,
// FreeAndNil(X) oder Dispose(X) liest ein Weg des Kontrollflusses X wieder. Eine Zuweisung an X, die Übergabe als
// Argument und @X beenden den Weg; Assigned(X) und Vergleiche mit nil trennen ihn. Bei einem Feld der Klasse
// beendet auch der Aufruf einer eigenen Methode den Weg, ebenso inherited: Sie kann das Feld neu belegen. Ebenso
// beenden ihn eine Zuweisung an eine Variable, die mit absolute auf X liegt (oder X auf ihr), und der Aufruf einer
// lokalen Routine: Sie kann die Variablen der umgebenden Routine neu setzen. Im Rumpf eines with kann X ein Mitglied
// des with-Objekts sein: dort keine Meldung (außer Self.X).

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
    FText: string;
    FToNil: Boolean;
    FUses: TArray<TSyntaxNode>;
    FStops: Boolean;
    FGuarded: Boolean;
    /// <summary>Felder und Methoden der Klasse der aktuellen Routine.</summary>
    FFields: TArray<string>;
    FMethods: TArray<string>;
    /// <summary>Lokale Routinen der aktuellen Routine; ihr Aufruf kann jede Variable neu belegen.</summary>
    FNested: TArray<string>;
    /// <summary>absolute-Paare der aktuellen Routine als "alias|ziel" in Kleinschreibung.</summary>
    FAbsolute: TArray<string>;
    /// <summary>Namen, die mit FPath über absolute denselben Speicher teilen.</summary>
    FPathAliases: TArray<string>;
    /// <summary>Ist FPath ein Feld der Klasse? Dann kann eine eigene Methode es neu belegen.</summary>
    FIsField: Boolean;
    function CallsOwnMethod(AStatement: TSyntaxNode; const ANames: TArray<string>;
    AWithInherited: Boolean): Boolean;
    procedure CollectMembers(ARoot, ARoutine: TSyntaxNode);
    procedure CollectLocals(ARoutine: TSyntaxNode);
    function AliasesOf(const APath: string): TArray<string>;
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

/// <summary>Ruft AStatement eine Methode der eigenen Klasse oder geerbt auf (Reset; Self.Reset(1); inherited Reset)?
/// Sie kann ein Feld neu belegen (FP-Prüfung 28.10.2026: FList.Free; Reset; FList.Add(…)). ANames sind die Namen
/// der Methoden bzw. lokalen Routinen; inherited zählt nur mit AWithInherited.</summary>
function TUseAfterFreeCheck.CallsOwnMethod(AStatement: TSyntaxNode; const ANames: TArray<string>;
  AWithInherited: Boolean): Boolean;
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
    // inherited Laden; ruft die Methode des Vorfahren für Self auf (ACBr: FreeAndNil(FListe); inherited
    // CarregaAliquotas; FListe.Add(…)).
    if mTarget.Kind = TSyntaxKind.InheritedExpr then
    begin
      Exit(AWithInherited);
    end;
    // Name oder Self.Name.
    mName := FreedPath(mTarget);
  end;
  Result := (mName <> '') and MatchText(mName, ANames);
end;

/// <summary>Lokale Routinen und absolute-Paare (Y: T absolute X) der Routine ARoutine.</summary>
procedure TUseAfterFreeCheck.CollectLocals(ARoutine: TSyntaxNode);
var
  mSection, mDecl: TSyntaxNode;
  mIndex, mInner: Integer;
  mTarget, mName, mBetween: string;
begin
  FNested := nil;
  FAbsolute := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mSection := ARoutine[mIndex];
    if mSection.Kind = TSyntaxKind.RoutineDecl then
    begin
      FNested := FNested + [ShortName(mSection.Name)];
    end
    else if mSection.Kind = TSyntaxKind.VarSection then
    begin
      for mInner := 0 to mSection.ChildCount - 1 do
      begin
        mDecl := mSection[mInner];
        if (mDecl.Kind <> TSyntaxKind.VarDecl) or (mDecl.ChildCount < 2) then
        begin
          Continue;
        end;
        // Y: T absolute X: zwischen Typ und Ausdruck steht das Wort absolute.
        mBetween := Copy(FText, mDecl[0].EndOffset + 1, mDecl[1].StartOffset - mDecl[0].EndOffset);
        mTarget := FreedPath(mDecl[1]);
        if (mTarget = '') or not ContainsText(mBetween, 'absolute') then
        begin
          Continue;
        end;
        for mName in mDecl.Name.Split([',']) do
        begin
          FAbsolute := FAbsolute + [LowerCase(Trim(mName) + '|' + mTarget)];
        end;
      end;
    end;
  end;
end;

/// <summary>Namen, die über absolute mit APath denselben Speicher teilen (beide Richtungen, eine Stufe).
/// </summary>
function TUseAfterFreeCheck.AliasesOf(const APath: string): TArray<string>;
var
  mPair: string;
  mParts: TArray<string>;
begin
  Result := nil;
  for mPair in FAbsolute do
  begin
    mParts := mPair.Split(['|']);
    if SameText(mParts[0], APath) then
    begin
      Result := Result + [mParts[1]];
    end
    else if SameText(mParts[1], APath) then
    begin
      Result := Result + [mParts[0]];
    end;
  end;
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
  Result := SameText(ANode.Defines, FPath) or (ANode.Defines <> '') and MatchText(ANode.Defines, FPathAliases);
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

/// <summary>Steht AAccess im Rumpf eines with (nicht in dessen Ausdruck)? Dort kann der Name ein Mitglied des
/// with-Objekts sein (ACBr: NFSe.Free; … with Liste.New do NFSe.Numero := …).</summary>
function InWithBody(AAccess: TSyntaxNode): Boolean;
var
  mChild, mParent: TSyntaxNode;
begin
  Result := False;
  mChild := AAccess;
  mParent := AAccess.Parent;
  while (mParent <> nil) and not IsRoutineBody(mParent) and (mParent.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if (mParent.Kind = TSyntaxKind.WithStatement) and (mParent.ChildCount > 0) and
      (mParent[mParent.ChildCount - 1] = mChild) then
    begin
      Exit(True);
    end;
    mChild := mParent;
    mParent := mParent.Parent;
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
  FStops := FStops or FIsField and CallsOwnMethod(ANode.Syntax, FMethods, True) or
    CallsOwnMethod(ANode.Syntax, FNested, False);
  Result := False;
  if not (FGuarded and FToNil) then
  begin
    for mAccess in FUses do
    begin
      if StartsText('Self.', FPath) or not InWithBody(mAccess) then
      begin
        ReportAccess(ANode, mAccess);
      end;
    end;
    Result := not (FStops or FGuarded);
  end;
end;

/// <summary>Ist APath (Name oder Self.Name) einer der Namen AMembers?</summary>
function IsMember(const APath: string; const AMembers: TArray<string>): Boolean;
begin
  Result := MatchText(APath, AMembers) or StartsText('Self.', APath) and
    MatchText(Copy(APath, Length('Self.') + 1, MaxInt), AMembers);
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
  FPathAliases := AliasesOf(APath);
  FIsField := IsMember(APath, FFields);
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
    // Pop.Free mit einer Funktion Pop der eigenen Klasse gibt bei jedem Aufruf ein anderes Objekt frei.
    if (mNode.Kind = TFlowNodeKind.Statement) and FreedBy(mNode.Syntax, mPath, mToNil) and
      not IsMember(mPath, FMethods) then
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
  FText := AContext.Text;
  mCache := TRuleDerived.Open(AContext);
  for mRoutine in TRuleDerived.Routines(mCache, AContext) do
  begin
    FGraph := TRuleDerived.Graph(mCache, AContext, mRoutine);
    if FGraph.Complete then
    begin
      CollectMembers(AContext.Tree.Root, mRoutine);
      CollectLocals(mRoutine);
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
