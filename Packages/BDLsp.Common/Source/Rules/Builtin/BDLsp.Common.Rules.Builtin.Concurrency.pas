unit BDLsp.Common.Rules.Builtin.Concurrency;

// Nebenläufigkeitsregeln (#148), rein syntaktisch und daher vorsichtig:
//   lock-without-finally         Sperre (Enter, Acquire, BeginWrite …) ohne direkt folgendes
//                                try/finally mit der passenden Freigabe
//   thread-used-after-start      Thread-Variable nach FreeOnTerminate := True und Start weiter benutzt
//   synchronize-in-destructor    Synchronize im Destruktor (Verklemmung, wenn der Hauptthread wartet)
//   deprecated-suspend-resume    veraltetes TThread.Resume/Suspend; Korrektur Resume → Start
//   thread-free-without-waitfor  (experimentell) Thread freigegeben ohne vorheriges WaitFor
//
// Typen kennt die Regel nicht: Sperren und Threads erkennt sie an Namen und
// Mustern im selben Anweisungsblock. Deshalb meldet sie mit mittlerer
// Konfidenz; thread-free-without-waitfor nur mit niedriger, weil
// TThread.Destroy selbst Terminate und WaitFor aufruft.

interface

uses
  System.SysUtils,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

type
  TLockWithoutFinallyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Freigabe zur Sperrmethode (Enter → Leave …), '' wenn AMethod keine Sperre ist.</summary>
    class function ReleaseOf(const AMethod: string): string; static;
  end;

  TThreadUsedAfterStartRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSynchronizeInDestructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDeprecatedSuspendResumeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TThreadFreeWithoutWaitForRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterConcurrencyRules(const ARegistry: TRuleRegistry);

implementation

uses
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Documents.Contract;

type
  /// <summary>Aufruf X.M oder X.M(…) als Anweisung.</summary>
  TMethodCall = record
    Method: string;
    /// <summary>Ausdruck vor dem Punkt.</summary>
    Receiver: TSyntaxNode;
    /// <summary>Knoten MemberAccess mit dem Methodennamen.</summary>
    Member: TSyntaxNode;
    /// <summary>Aufruf mit Argumenten, sonst nil.</summary>
    Call: TSyntaxNode;
  end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := LowerCase(Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

function TryMethodCall(AStatement: TSyntaxNode; out ACall: TMethodCall): Boolean;
var
  Target: TSyntaxNode;
begin
  Result := False;
  ACall := Default(TMethodCall);
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
    Exit;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
  begin
    ACall.Call := Target;
    Target := Target[0];
  end;
  if (Target.Kind <> TSyntaxKind.MemberAccess) or (Target.ChildCount = 0) then
    Exit;
  ACall.Method := Target.Name;
  ACall.Member := Target;
  ACall.Receiver := Target[0];
  Result := True;
end;

/// <summary>Bereich des Methodennamens am Ende von AMember.</summary>
function MemberNameRange(AMember: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(AMember.EndPos.Line, AMember.EndPos.Character - Length(AMember.Name),
    AMember.EndPos.Line, AMember.EndPos.Character);
end;

/// <summary>Bezeichner der Variablen in X oder Self.X, sonst ''.</summary>
function VariableName(ANode: TSyntaxNode): string;
begin
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    Result := ANode.Name
  else
    Result := '';
end;

function IsStatementList(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
    TSyntaxKind.ExceptBlock, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection];
end;

/// <summary>True, wenn ANode oder ein Nachfahre den Bezeichner AName benutzt.</summary>
function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if Mentions(ANode[Index], AName) then
      Exit(True);
  Result := False;
end;

{ TLockWithoutFinallyRule }

function TLockWithoutFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('lock-without-finally', TRuleSeverity.Warning,
    'Sperre ohne try/finally mit passender Freigabe');
end;

class function TLockWithoutFinallyRule.ReleaseOf(const AMethod: string): string;
const
  Pairs: array[0..5, 0..1] of string = (('Enter', 'Leave'), ('Acquire', 'Release'), ('BeginWrite', 'EndWrite'),
    ('BeginRead', 'EndRead'), ('LockList', 'UnlockList'), ('Lock', 'Unlock'));
var
  Index: Integer;
begin
  for Index := Low(Pairs) to High(Pairs) do
    if SameText(Pairs[Index, 0], AMethod) then
      Exit(Pairs[Index, 1]);
  Result := '';
end;

/// <summary>Schlüssel einer Sperre: Empfänger, bei TMonitor zusätzlich das erste Argument.</summary>
function LockKey(const AText: string; const ACall: TMethodCall): string;
begin
  Result := NodeText(AText, ACall.Receiver);
  if (ACall.Call <> nil) and (ACall.Call.ChildCount > 1) then
    Result := Result + '(' + NodeText(AText, ACall.Call[1]) + ')';
end;

/// <summary>True, wenn ein Finally-Block von ATry die Freigabe mit demselben Schlüssel enthält.</summary>
function ReleasesIn(const AText: string; ATry: TSyntaxNode; const ARelease, AKey: string): Boolean;

  function Search(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Call: TMethodCall;
  begin
    if TryMethodCall(ANode, Call) and SameText(Call.Method, ARelease) and (LockKey(AText, Call) = AKey) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if Search(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

var
  Final: TSyntaxNode;
begin
  Final := ATry.FindChild(TSyntaxKind.FinallyBlock);
  Result := (Final <> nil) and Search(Final);
end;

procedure TLockWithoutFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  procedure CheckList(AList: TSyntaxNode);
  var
    Index: Integer;
    Call: TMethodCall;
    Release, Key: string;
    Next: TSyntaxNode;
  begin
    for Index := 0 to AList.ChildCount - 1 do
    begin
      if not TryMethodCall(AList[Index], Call) then
        Continue;
      Release := ReleaseOf(Call.Method);
      if Release = '' then
        Continue;
      // TMonitor.Enter(X) gibt mit TMonitor.Exit(X) frei.
      if SameText(Call.Method, 'Enter') and ((NodeText(AContext.Text, Call.Receiver) = 'tmonitor') or
        (NodeText(AContext.Text, Call.Receiver) = 'system.tmonitor')) then
        Release := 'Exit';
      Key := LockKey(AContext.Text, Call);
      // Sperre direkt vor try … finally Freigabe.
      if Index < AList.ChildCount - 1 then
      begin
        Next := AList[Index + 1];
        if (Next.Kind = TSyntaxKind.TryStatement) and ReleasesIn(AContext.Text, Next, Release, Key) then
          Continue;
      end;
      // Sperre als erste Anweisung im try, dessen finally freigibt.
      if (AList.Kind = TSyntaxKind.TryStatement) and ReleasesIn(AContext.Text, AList, Release, Key) then
        Continue;
      AReport.Add(MemberNameRange(Call.Member),
        Format('%s ohne try/finally mit %s: eine Ausnahme lässt die Sperre gesetzt', [Call.Method, Release]),
        TRuleConfidence.Medium);
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if IsStatementList(ANode) then
      CheckList(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Visit(AContext.Tree.Root);
end;

{ TThreadUsedAfterStartRule }

function TThreadUsedAfterStartRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-used-after-start', TRuleSeverity.Warning,
    'Thread mit FreeOnTerminate wird nach dem Start weiter benutzt');
end;

procedure TThreadUsedAfterStartRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  procedure CheckList(AList: TSyntaxNode);
  var
    Index: Integer;
    Statement, Target: TSyntaxNode;
    Call: TMethodCall;
    Name: string;
    Started: Boolean;
  begin
    Name := '';
    Started := False;
    for Index := 0 to AList.ChildCount - 1 do
    begin
      Statement := AList[Index];
      if Started then
      begin
        if Mentions(Statement, Name) then
        begin
          // Neue Zuweisung an die Variable beendet die Beobachtung.
          if (Statement.Kind = TSyntaxKind.AssignStatement) and (Statement.ChildCount > 0) and
            (Statement[0].Kind = TSyntaxKind.Identifier) and SameText(Statement[0].Name, Name) then
          begin
            Name := '';
            Started := False;
            Continue;
          end;
          AReport.Add(TTextRange.Create(Statement.StartPos, Statement.EndPos),
            Format('"%s" gibt sich nach dem Start selbst frei (FreeOnTerminate); der Zugriff kann ein ' +
            'freigegebenes Objekt treffen', [Name]), TRuleConfidence.Medium);
          Name := '';
          Started := False;
        end;
        Continue;
      end;
      if (Statement.Kind = TSyntaxKind.AssignStatement) and (Statement.ChildCount = 2) then
      begin
        Target := Statement[0];
        if (Target.Kind = TSyntaxKind.MemberAccess) and SameText(Target.Name, 'FreeOnTerminate') and
          (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) and
          (Statement[1].Kind = TSyntaxKind.Identifier) and SameText(Statement[1].Name, 'True') then
          Name := Target[0].Name;
      end
      else if (Name <> '') and TryMethodCall(Statement, Call) and
        (SameText(Call.Method, 'Start') or SameText(Call.Method, 'Resume')) and
        SameText(VariableName(Call.Receiver), Name) then
        Started := True;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if IsStatementList(ANode) then
      CheckList(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Visit(AContext.Tree.Root);
end;

{ TSynchronizeInDestructorRule }

function TSynchronizeInDestructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('synchronize-in-destructor', TRuleSeverity.Warning,
    'Synchronize im Destruktor');
end;

procedure TSynchronizeInDestructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  procedure Search(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.AnonymousMethod then
      Exit;
    if ((ANode.Kind = TSyntaxKind.MemberAccess) or (ANode.Kind = TSyntaxKind.Identifier)) and
      SameText(ANode.Name, 'Synchronize') then
    begin
      if ANode.Kind = TSyntaxKind.MemberAccess then
        AReport.Add(MemberNameRange(ANode), 'Synchronize im Destruktor: wartet der Hauptthread auf die ' +
          'Freigabe, verklemmen sich beide', TRuleConfidence.Medium)
      else
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), 'Synchronize im Destruktor: wartet der ' +
          'Hauptthread auf die Freigabe, verklemmen sich beide', TRuleConfidence.Medium);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Search(ANode[Index]);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.RoutineDecl) and (Pos('destructor', NodeText(AContext.Text, ANode)) = 1) then
    begin
      Body := ANode.FindChild(TSyntaxKind.Block);
      if Body <> nil then
        Search(Body);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree <> nil then
    Visit(AContext.Tree.Root);
end;

{ TDeprecatedSuspendResumeRule }

function TDeprecatedSuspendResumeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('deprecated-suspend-resume', TRuleSeverity.Hint,
    'Veraltetes TThread.Suspend oder Resume');
end;

procedure TDeprecatedSuspendResumeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Call: TMethodCall;
    Range: TTextRange;
  begin
    // Nur ohne Argumente: Resume(…) oder Suspend(…) gehören zu anderen Klassen.
    if TryMethodCall(ANode, Call) and (Call.Call = nil) then
    begin
      Range := MemberNameRange(Call.Member);
      if SameText(Call.Method, 'Resume') then
        AReport.Add(Range, 'TThread.Resume ist veraltet; einen erzeugten Thread mit Start starten',
          TRuleConfidence.Medium, [TRuleFix.Create('Durch Start ersetzen', [TRuleEdit.Create(Range, 'Start')])])
      else if SameText(Call.Method, 'Suspend') then
        AReport.Add(Range, 'TThread.Suspend ist veraltet und kann den Thread mitten in einer Sperre anhalten; ' +
          'stattdessen mit einem Ereignis (TEvent) warten', TRuleConfidence.Medium);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree <> nil then
    Visit(AContext.Tree.Root);
end;

{ TThreadFreeWithoutWaitForRule }

function TThreadFreeWithoutWaitForRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-free-without-waitfor', TRuleSeverity.Hint,
    'Thread freigegeben ohne vorheriges Terminate und WaitFor', True);
end;

procedure TThreadFreeWithoutWaitForRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  // Name der freigegebenen Variablen bei X.Free oder FreeAndNil(X), sonst ''.
  function FreedName(AStatement: TSyntaxNode; out ANode: TSyntaxNode): string;
  var
    Call: TMethodCall;
    Inner: TSyntaxNode;
  begin
    Result := '';
    ANode := nil;
    if TryMethodCall(AStatement, Call) and SameText(Call.Method, 'Free') and (Call.Call = nil) then
    begin
      ANode := Call.Member;
      Exit(VariableName(Call.Receiver));
    end;
    if (AStatement.Kind = TSyntaxKind.CallStatement) and (AStatement.ChildCount = 1) then
    begin
      Inner := AStatement[0];
      if (Inner.Kind = TSyntaxKind.Call) and (Inner.ChildCount = 2) and (Inner[0].Kind = TSyntaxKind.Identifier) and
        SameText(Inner[0].Name, 'FreeAndNil') then
      begin
        ANode := Inner;
        Result := VariableName(Inner[1]);
      end;
    end;
  end;

  procedure SearchRoutine(ABody: TSyntaxNode);
  var
    Waited: TArray<string>;

    function HasWaited(const AName: string): Boolean;
    var
      Name: string;
    begin
      for Name in Waited do
        if SameText(Name, AName) then
          Exit(True);
      Result := False;
    end;

    procedure Walk(ANode: TSyntaxNode);
    var
      Index: Integer;
      Call: TMethodCall;
      Name: string;
      Freed: TSyntaxNode;
    begin
      if ANode.Kind = TSyntaxKind.AnonymousMethod then
        Exit;
      if TryMethodCall(ANode, Call) and SameText(Call.Method, 'WaitFor') then
        Waited := Waited + [VariableName(Call.Receiver)];
      Name := FreedName(ANode, Freed);
      if (Name <> '') and (Pos('thread', LowerCase(Name)) > 0) and not HasWaited(Name) then
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
          Format('"%s" wird ohne vorheriges Terminate und WaitFor freigegeben; Ende und Fehler des Threads ' +
          'bleiben so unbemerkt', [Name]), TRuleConfidence.Low);
      for Index := 0 to ANode.ChildCount - 1 do
        Walk(ANode[Index]);
    end;

  begin
    Waited := nil;
    Walk(ABody);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Body := ANode.FindChild(TSyntaxKind.Block);
      if Body <> nil then
        SearchRoutine(Body);
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree <> nil then
    Visit(AContext.Tree.Root);
end;

procedure RegisterConcurrencyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TLockWithoutFinallyRule.Create);
  ARegistry.Register(TThreadUsedAfterStartRule.Create);
  ARegistry.Register(TSynchronizeInDestructorRule.Create);
  ARegistry.Register(TDeprecatedSuspendResumeRule.Create);
  ARegistry.Register(TThreadFreeWithoutWaitForRule.Create);
end;

end.
