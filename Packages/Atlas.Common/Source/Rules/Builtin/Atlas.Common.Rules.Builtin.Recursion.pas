unit Atlas.Common.Rules.Builtin.Recursion;

// Property-Falle (#623, #910):
//   setter-recursion   Setter schreibt bzw. Getter liest die eigene Property
//                      (Name := Value in SetName) und ruft sich damit endlos
//                      selbst auf. Fehler mit hoher Konfidenz; bis #910 hieß
//                      die Regel recursive-property-accessor (TRuleIdAliases).
// Die Analyse liefert TRecursionAnalysis.AccessorTraps. Die Korrektur setzt
// das Feld ein: aus read/write der Property, sonst F<Name>, wenn die Klasse
// es hat. Geerbte Properties und Accessoren in anderen Units sieht die
// Analyse nicht.
//
// Rekursion ohne Abbruch (#1044):
//   unconditional-recursion  Eine Routine ruft sich auf jedem Pfad selbst auf,
//                      bevor sie zurückkehren kann (Stapelüberlauf). Die direkten
//                      Selbstaufrufe liefert TRecursionAnalysis.Calls (Tiefe 1);
//                      Getter und Setter der eigenen Property bleiben bei
//                      setter-recursion. Ein Pfad ohne Aufruf ist: Zweig von if
//                      ohne else bzw. case ohne else, Rumpf von while und for,
//                      rechter Teil von and/or, Zweige von if-Ausdrücken, anonyme
//                      Methoden. Exit, raise, goto, Halt, Abort (bzw. Break und
//                      Continue in einer Schleife) vor dem Aufruf beenden den Pfad.
//                      Überladene Routinen bleiben still (Aufruf einer anderen
//                      Überladung).

interface

uses
  Atlas.Common.Semantics.Recursion,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  SetterRecursionRuleId = 'setter-recursion';
  UnconditionalRecursionRuleId = 'unconditional-recursion';

type
  TSetterRecursionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Meldungstext eines Treffers.</summary>
    class function Message(const ATrap: TAccessorTrap): string; static;
  end;

  TUnconditionalRecursionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterRecursionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

{ TSetterRecursionRule }

function TSetterRecursionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SetterRecursionRuleId, TRuleSeverity.Error,
    'Setter oder Getter ruft sich selbst auf (Endlosrekursion)');
end;

class function TSetterRecursionRule.Message(const ATrap: TAccessorTrap): string;
begin
  if ATrap.IsSetter then
    Result := Format('Zuweisung an die Property %s im eigenen Setter: Endlosrekursion.', [ATrap.PropertyName])
  else
    Result := Format('Lesen der Property %s im eigenen Getter: Endlosrekursion.', [ATrap.PropertyName]);
end;

procedure TSetterRecursionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Trap: TAccessorTrap;
begin
  if AContext.Tree = nil then
    Exit;
  for Trap in TRecursionAnalysis.AccessorTraps(AContext.Tree) do
    if Trap.Field <> '' then
      AReport.Add(Trap.Range, Message(Trap), [TRuleFix.Create(Format('Feld %s verwenden', [Trap.Field]),
        [TRuleEdit.Create(Trap.Range, Trap.Field)])])
    else
      AReport.Add(Trap.Range, Message(Trap));
end;

{ TUnconditionalRecursionRule }

const
  // Aufrufe, die die Routine verlassen.
  LeavingCalls: array[0..4] of string = ('Exit', 'Halt', 'Abort', 'RunError', 'ExitProcess');
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];

function TUnconditionalRecursionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnconditionalRecursionRuleId, TRuleSeverity.Error, 'Rekursion ohne Abbruch');
end;

function Inside(const APosition: TTextPosition; ANode: TSyntaxNode): Boolean;
begin
  Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
    (ANode.StartPos.Character <= APosition.Character))) and ((APosition.Line < ANode.EndPos.Line) or
    ((APosition.Line = ANode.EndPos.Line) and (APosition.Character < ANode.EndPos.Character)));
end;

/// <summary>Selbstaufrufe einer Routine und die Prüfung, ob jeder Pfad einen davon ausführt.</summary>
type
  TSelfCalls = class
  private
    FSites: TArray<TTextPosition>;
    function SiteIn(const AFrom, ATo: TTextPosition): Boolean;
    function Leaves(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
  public
    constructor Create(const ASites: TArray<TTextPosition>);
    /// <summary>Wertet ein Ausdruck auf jedem Weg einen Selbstaufruf aus?</summary>
    function InExpression(ANode: TSyntaxNode): Boolean;
    /// <summary>Führt die Anweisung ANode auf jedem Pfad einen Selbstaufruf aus, bevor sie endet oder die
    /// Routine verlässt? ALoop: ANode steht im Rumpf einer Schleife (Break und Continue verlassen ihn).</summary>
    function Always(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
    /// <summary>Wie Always für die Anweisungen AFirst..ALast von AParent nacheinander.</summary>
    function AlwaysList(AParent: TSyntaxNode; AFirst, ALast: Integer; ALoop: Boolean): Boolean;
  end;

constructor TSelfCalls.Create(const ASites: TArray<TTextPosition>);
begin
  inherited Create;
  FSites := ASites;
end;

function TSelfCalls.SiteIn(const AFrom, ATo: TTextPosition): Boolean;
var
  Site: TTextPosition;
begin
  for Site in FSites do
    if ((AFrom.Line < Site.Line) or ((AFrom.Line = Site.Line) and (AFrom.Character <= Site.Character))) and
      ((Site.Line < ATo.Line) or ((Site.Line = ATo.Line) and (Site.Character < ATo.Character))) then
      Exit(True);
  Result := False;
end;

function TSelfCalls.InExpression(ANode: TSyntaxNode): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      case Node.Kind of
        TSyntaxKind.AnonymousMethod:
          Continue;
        TSyntaxKind.Identifier:
          begin
            if SiteIn(Node.StartPos, Node.EndPos) then
              Exit(True);
            Continue;
          end;
        TSyntaxKind.MemberAccess:
          // Self.Name: der Name hinter dem Empfänger.
          if (Node.ChildCount > 0) and SiteIn(Node[0].EndPos, Node.EndPos) then
            Exit(True);
        TSyntaxKind.BinaryExpr:
          // Kurzschluss: rechts von and/or nicht auf jedem Weg.
          if (Node.Name = 'and') or (Node.Name = 'or') then
          begin
            if Node.ChildCount > 0 then
              Pending.Push(Node[0]);
            Continue;
          end;
        TSyntaxKind.IfExpr:
          begin
            if Node.ChildCount > 0 then
              Pending.Push(Node[0]);
            Continue;
          end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

function TSelfCalls.Leaves(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Loops: TStack<Boolean>;
  Node: TSyntaxNode;
  Loop, ChildLoop: Boolean;
  Index: Integer;
  Name: string;
begin
  // Iterativ (Bericht M1); Loops führt ALoop je Knoten mit.
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  Loops := TStack<Boolean>.Create;
  try
    Pending.Push(ANode);
    Loops.Push(ALoop);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Loop := Loops.Pop;
      case Node.Kind of
        TSyntaxKind.AnonymousMethod:
          Continue;
        TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
          Exit(True);
        TSyntaxKind.Identifier, TSyntaxKind.Call:
          begin
            Name := Node.Name;
            if MatchText(Name, LeavingCalls) or (Loop and MatchText(Name, ['Break', 'Continue'])) then
              Exit(True);
          end;
      end;
      ChildLoop := Loop and not (Node.Kind in LoopKinds);
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
        Loops.Push(ChildLoop);
      end;
    end;
  finally
    Loops.Free;
    Pending.Free;
  end;
end;

function TSelfCalls.AlwaysList(AParent: TSyntaxNode; AFirst, ALast: Integer; ALoop: Boolean): Boolean;
var
  Index: Integer;
begin
  for Index := AFirst to ALast do
  begin
    if Always(AParent[Index], ALoop) then
      Exit(True);
    if Leaves(AParent[Index], ALoop) then
      Exit(False);
  end;
  Result := False;
end;

// Lange else-if-Ketten und with-Rümpfe laufen iterativ über Node (Bericht M1); Ausdrücke prüfen die iterativen
// InExpression und Leaves. Rekursiv bleibt nur der Abstieg in then-Zweige, Blöcke und case-Zweige: diese
// Schachtelung baut der Parser selbst rekursiv auf (ParseStatement), sie ist durch dessen größere Rahmen begrenzt.
function TSelfCalls.Always(ANode: TSyntaxNode; ALoop: Boolean): Boolean;
var
  Index: Integer;
  Node, Next, Part: TSyntaxNode;
begin
  Result := False;
  Node := ANode;
  while Node <> nil do
  begin
    Result := False;
    Next := nil;
    case Node.Kind of
      TSyntaxKind.Block, TSyntaxKind.LabeledStatement, TSyntaxKind.FinallyBlock:
        Result := AlwaysList(Node, 0, Node.ChildCount - 1, ALoop);
      TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar,
      TSyntaxKind.InlineConst:
        Result := InExpression(Node);
      TSyntaxKind.IfStatement:
        // else-Zweig als nächster Durchlauf statt rekursiv.
        if Node.ChildCount > 0 then
        begin
          if InExpression(Node[0]) then
            Result := True
          else if (Node.ChildCount = 3) and Always(Node[1], ALoop) then
            Next := Node[2];
        end;
      TSyntaxKind.CaseStatement:
        begin
          if Node.ChildCount = 0 then
            Exit;
          if InExpression(Node[0]) then
            Exit(True);
          if Node.FindChild(TSyntaxKind.CaseElse) = nil then
            Exit;
          for Index := 1 to Node.ChildCount - 1 do
          begin
            Part := Node[Index];
            if Part.Kind = TSyntaxKind.CaseElse then
            begin
              if not AlwaysList(Part, 0, Part.ChildCount - 1, ALoop) then
                Exit;
            end
            else if (Part.ChildCount = 0) or not Always(Part[Part.ChildCount - 1], ALoop) then
              Exit;
          end;
          Result := True;
        end;
      TSyntaxKind.WhileStatement:
        Result := (Node.ChildCount > 0) and InExpression(Node[0]);
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
        for Index := 0 to Node.ChildCount - 2 do
          if InExpression(Node[Index]) then
            Exit(True);
      TSyntaxKind.RepeatStatement:
        Result := (Node.ChildCount > 0) and (AlwaysList(Node, 0, Node.ChildCount - 2, True) or
          (not Leaves(Node, True) and InExpression(Node[Node.ChildCount - 1])));
      TSyntaxKind.WithStatement:
        begin
          for Index := 0 to Node.ChildCount - 2 do
            if InExpression(Node[Index]) then
              Exit(True);
          // Rumpf als nächster Durchlauf statt rekursiv.
          if Node.ChildCount > 0 then
            Next := Node[Node.ChildCount - 1];
        end;
      TSyntaxKind.TryStatement:
        begin
          // try-Teil nacheinander; bei try … finally zählt auch der finally-Teil.
          Index := 0;
          while (Index < Node.ChildCount) and not (Node[Index].Kind in [TSyntaxKind.ExceptBlock,
            TSyntaxKind.FinallyBlock]) do
            Inc(Index);
          Result := AlwaysList(Node, 0, Index - 1, ALoop) or ((Index < Node.ChildCount) and
            (Node[Index].Kind = TSyntaxKind.FinallyBlock) and Always(Node[Index], ALoop));
        end;
    end;
    Node := Next;
  end;
end;

/// <summary>Hinweis auf den fehlenden Abbruch am ersten Parameter, z. B. "K = nil".</summary>
function StopHint(ARoutine: TSyntaxNode): string;
var
  Header, Parameters, Parameter, TypeNode: TSyntaxNode;
  Name, TypeName: string;
begin
  Result := '';
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Exit;
  Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if (Parameters = nil) or (Parameters.ChildCount = 0) then
    Exit;
  Parameter := Parameters[0];
  Name := Parameter.Name.Split([','])[0];
  TypeNode := Parameter.FindChild(TSyntaxKind.TypeReference);
  if TypeNode <> nil then
    TypeName := TypeNode.Name
  else
    TypeName := '';
  if MatchText(TypeName, ['Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'SmallInt', 'ShortInt', 'LongInt', 'LongWord']) then
    Result := Name + ' <= 0'
  else if MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString']) then
    Result := Name + ' = '''''
  else if SameText(TypeName, 'TArray') or StartsText('TArray<', TypeName) or
    (Parameter.FindChild(TSyntaxKind.ArrayType) <> nil) then
    Result := 'Length(' + Name + ') = 0'
  else if (Length(TypeName) > 1) and CharInSet(TypeName[1], ['T', 'P', 'I']) and
    CharInSet(TypeName[2], ['A'..'Z']) then
    Result := Name + ' = nil';
end;

procedure TUnconditionalRecursionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Calls: TArray<TRecursiveCall>;
  Traps: TArray<TAccessorTrap>;
  Overloaded: TArray<string>;
  Reported: TArray<string>;

  // Innerste implementierte Routine, die APosition enthält.
  function RoutineAt(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
  var
    Index: Integer;
    Node, Next: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): je Ebene in das erste Kind, das APosition enthält.
    Result := nil;
    Node := ANode;
    while Node <> nil do
    begin
      Next := nil;
      for Index := 0 to Node.ChildCount - 1 do
        if Inside(APosition, Node[Index]) then
        begin
          Next := Node[Index];
          Break;
        end;
      if (Next <> nil) and (Next.Kind = TSyntaxKind.RoutineDecl) and (Next.FindChild(TSyntaxKind.Block) <> nil) then
        Result := Next;
      Node := Next;
    end;
  end;

  // Kurznamen (klein) mit overload-Direktive oder mehreren Rümpfen gleichen Namens.
  procedure CollectOverloads(ANode: TSyntaxNode; var ABodies: TArray<string>);
  var
    Pending: TStack<TSyntaxNode>;
    Index, Item: Integer;
    Child, Header: TSyntaxNode;
    Key: string;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion (Vorordnung).
    Pending := TStack<TSyntaxNode>.Create;
    try
      for Index := ANode.ChildCount - 1 downto 0 do
        Pending.Push(ANode[Index]);
      while Pending.Count > 0 do
      begin
        Child := Pending.Pop;
        if Child.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
        begin
          Key := LowerCase(Child.Name);
          if Key.Contains('.') then
            Key := Copy(Key, Key.LastIndexOf('.') + 2, MaxInt);
          Header := Child;
          if Child.Kind = TSyntaxKind.RoutineDecl then
            Header := Child.FindChild(TSyntaxKind.RoutineHeader);
          if Header <> nil then
            for Item := 0 to Header.ChildCount - 1 do
              if (Header[Item].Kind = TSyntaxKind.Directive) and SameText(Header[Item].Name, 'overload') then
                Overloaded := Overloaded + [Key];
          if (Child.Kind = TSyntaxKind.RoutineDecl) and (Child.FindChild(TSyntaxKind.Block) <> nil) then
          begin
            if IndexStr(LowerCase(Child.Name), ABodies) >= 0 then
              Overloaded := Overloaded + [Key];
            ABodies := ABodies + [LowerCase(Child.Name)];
          end;
        end;
        for Index := Child.ChildCount - 1 downto 0 do
          Pending.Push(Child[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Call: TRecursiveCall;
  Trap: TAccessorTrap;
  Routine: TSyntaxNode;
  Sites: TArray<TTextPosition>;
  Analysis: TSelfCalls;
  Key, Hint, Name: string;
  Index: Integer;
  Skip: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Calls := TRecursionAnalysis.Calls(AContext.Tree, 1);
  if Calls = nil then
    Exit;
  Traps := TRecursionAnalysis.AccessorTraps(AContext.Tree);
  Overloaded := nil;
  Reported := nil;
  CollectOverloads(AContext.Tree.Root, Reported);
  Reported := nil;
  for Call in Calls do
  begin
    Routine := RoutineAt(AContext.Tree.Root, Call.Range.StartPos);
    if Routine = nil then
      Continue;
    Key := LowerCase(Routine.Name);
    if (IndexStr(Key, Reported) >= 0) or (IndexStr(Copy(Key, Key.LastIndexOf('.') + 2, MaxInt), Overloaded) >= 0) then
      Continue;
    Reported := Reported + [Key];
    // Alle Selbstaufrufe dieser Routine, ohne Property-Zugriffe (setter-recursion).
    Sites := nil;
    for Index := 0 to High(Calls) do
    begin
      Skip := RoutineAt(AContext.Tree.Root, Calls[Index].Range.StartPos) <> Routine;
      for Trap in Traps do
        if Trap.Range.StartPos = Calls[Index].Range.StartPos then
          Skip := True;
      if not Skip then
        Sites := Sites + [Calls[Index].Range.StartPos];
    end;
    if Sites = nil then
      Continue;
    Analysis := TSelfCalls.Create(Sites);
    try
      if not Analysis.Always(Routine.FindChild(TSyntaxKind.Block), False) then
        Continue;
    finally
      Analysis.Free;
    end;
    Name := Call.Chain[0].Name;
    if Name.Contains('.') then
      Name := Copy(Name, Name.LastIndexOf('.') + 2, MaxInt);
    Hint := StopHint(Routine);
    if Hint <> '' then
      AReport.Add(Call.Chain[0].Range, Format('%s ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch ' +
        '(z. B. %s).', [Name, Hint]), TRuleConfidence.High)
    else
      AReport.Add(Call.Chain[0].Range, Format('%s ruft sich auf jedem Pfad selbst auf; es fehlt der Abbruch.',
        [Name]), TRuleConfidence.High);
  end;
end;

procedure RegisterRecursionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSetterRecursionRule.Create);
  ARegistry.Register(TUnconditionalRecursionRule.Create);
end;

end.
