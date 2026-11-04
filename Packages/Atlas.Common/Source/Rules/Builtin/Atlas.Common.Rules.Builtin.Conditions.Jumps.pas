unit Atlas.Common.Rules.Builtin.Conditions.Jumps;

// Sprünge und Ausgänge aus Schleifen für die Regeln der Gruppe Bedingungen
// (Atlas.Common.Rules.Builtin.Conditions): Namen von Aufrufen und Sprüngen,
// Routinen, die eine Ausnahme auslösen, und Ausgänge einer Schleife.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree;

const
  // Aufrufe, die die Schleife verlassen: über die Routine, das Programm oder eine Ausnahme.
  LeavingCalls: array[0..4] of string = ('Exit', 'Halt', 'Abort', 'RunError', 'ExitProcess');
  // Aufrufe, die das Programm beenden oder eine Ausnahme auslösen.
  RaisingCalls: array[0..3] of string = ('Halt', 'Abort', 'RunError', 'ExitProcess');

/// <summary>Letzter Teil des Namens einer Routine: "TFoo.Bar" → "Bar".</summary>
function ShortName(const AName: string): string;
/// <summary>Name eines Aufrufs (Bezeichner, Kette X.Name, Name(…)); '' sonst.</summary>
function CalledName(ANode: TSyntaxNode): string;
/// <summary>Name eines Sprungs ohne Qualifizierer (Exit, Break, Halt, Exit(X)); '' sonst. TMonitor.Exit(…) ist
/// kein Sprung.</summary>
function JumpName(ANode: TSyntaxNode): string;
/// <summary>Löst ANode (ohne anonyme Methoden) eine Ausnahme aus oder beendet das Programm, direkt oder über
/// eine Routine aus ARaising?</summary>
function Raises(ANode: TSyntaxNode; ARaising: TDictionary<string, Boolean>): Boolean;
/// <summary>Kurznamen (klein) der Routinen der Datei, die eine Ausnahme auslösen oder das Programm beenden.</summary>
function RaisingRoutines(ATree: TSyntaxTree): TDictionary<string, Boolean>;
/// <summary>Hat ANode einen Ausgang aus der Schleife? AInner: ANode liegt in einer inneren Schleife, ein Break
/// verlässt nur diese.</summary>
function HasExit(ANode: TSyntaxNode; AInner: Boolean; ARaising: TDictionary<string, Boolean>): Boolean;
/// <summary>Steht ANode im try-Teil eines try … except derselben Routine?</summary>
function InTryExcept(ANode: TSyntaxNode): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract;

function ShortName(const AName: string): string;
var
  Dot: Integer;
begin
  Result := AName;
  Dot := Result.LastIndexOf('.');
  if Dot >= 0 then
  begin
    Result := Copy(Result, Dot + 2, MaxInt);
  end;
end;

function CalledName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
  begin
    ANode := ANode[0];
  end;
  if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
  begin
    Result := ANode.Name;
  end;
end;

function JumpName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
  begin
    ANode := ANode[0];
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end;
end;

function Raises(ANode: TSyntaxNode; ARaising: TDictionary<string, Boolean>): Boolean;
var
  Index: Integer;
  Name: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      if Node.Kind = TSyntaxKind.RaiseStatement then
      begin
        Exit(True);
      end;
      if Node.Kind in [TSyntaxKind.Call, TSyntaxKind.Identifier] then
      begin
        Name := CalledName(Node);
        if MatchText(Name, RaisingCalls) or ((Name <> '') and ARaising.ContainsKey(LowerCase(Name))) then
        begin
          Exit(True);
        end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function RaisingRoutines(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  Routines: TList<TSyntaxNode>;
  Changed: Boolean;
  Routine: TSyntaxNode;

  procedure Collect(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routines.Add(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  Result := TDictionary<string, Boolean>.Create;
  Routines := TList<TSyntaxNode>.Create;
  try
    if ATree.Root <> nil then
    begin
      Collect(ATree.Root);
    end;
    // Bis nichts mehr dazukommt: A ruft B, B löst aus.
    repeat
      Changed := False;
      for Routine in Routines do
      begin
        if not Result.ContainsKey(LowerCase(ShortName(Routine.Name))) and (Routine.FindChild(TSyntaxKind.Block) <> nil) and
          Raises(Routine.FindChild(TSyntaxKind.Block), Result) then
        begin
          Result.Add(LowerCase(ShortName(Routine.Name)), True);
          Changed := True;
        end;
      end;
    until not Changed;
  finally
    Routines.Free;
  end;
end;

function HasExit(ANode: TSyntaxNode; AInner: Boolean; ARaising: TDictionary<string, Boolean>): Boolean;
var
  Index: Integer;
  Name: string;
  Inner: Boolean;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
  PendingInner: TStack<Boolean>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  PendingInner := TStack<Boolean>.Create;
  try
    Pending.Push(ANode);
    PendingInner.Push(AInner);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      Inner := PendingInner.Pop;
      case Node.Kind of
        TSyntaxKind.AnonymousMethod:
          Continue;
        TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
          Exit(True);
        TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call:
          begin
            Name := CalledName(Node);
            if SameText(Name, 'Terminated') or MatchText(JumpName(Node), LeavingCalls) or
              ((Name <> '') and ARaising.ContainsKey(LowerCase(Name))) then
            begin
              Exit(True);
            end;
            if SameText(JumpName(Node), 'Break') and not Inner then
            begin
              Exit(True);
            end;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      Inner := Inner or (Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
        TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]);
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
        PendingInner.Push(Inner);
      end;
    end;
  finally
    PendingInner.Free;
    Pending.Free;
  end;
end;

function InTryExcept(ANode: TSyntaxNode): Boolean;
var
  Child, Parent: TSyntaxNode;
begin
  Child := ANode;
  Parent := ANode.Parent;
  while (Parent <> nil) and not (Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    if (Parent.Kind = TSyntaxKind.TryStatement) and (Child.Kind <> TSyntaxKind.ExceptBlock) and
      (Child.Kind <> TSyntaxKind.FinallyBlock) and (Parent.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
    begin
      Exit(True);
    end;
    Child := Parent;
    Parent := Parent.Parent;
  end;
  Result := False;
end;

end.
