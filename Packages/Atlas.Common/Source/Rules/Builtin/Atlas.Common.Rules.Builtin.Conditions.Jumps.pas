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
  cLeavingCalls: array[0..4] of string = ('Exit', 'Halt', 'Abort', 'RunError', 'ExitProcess');
  // Aufrufe, die das Programm beenden oder eine Ausnahme auslösen.
  cRaisingCalls: array[0..3] of string = ('Halt', 'Abort', 'RunError', 'ExitProcess');

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
  mDot: Integer;
begin
  Result := AName;
  mDot := Result.LastIndexOf('.');
  if mDot >= 0 then
  begin
    Result := Copy(Result, mDot + 2, MaxInt);
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
  mIndex: Integer;
  mName: string;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      if mNode.Kind = TSyntaxKind.RaiseStatement then
      begin
        Exit(True);
      end;
      if mNode.Kind in [TSyntaxKind.Call, TSyntaxKind.Identifier] then
      begin
        mName := CalledName(mNode);
        if MatchText(mName, cRaisingCalls) or ((mName <> '') and ARaising.ContainsKey(LowerCase(mName))) then
        begin
          Exit(True);
        end;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function RaisingRoutines(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  mRoutines: TList<TSyntaxNode>;
  mChanged: Boolean;
  mRoutine: TSyntaxNode;

  procedure Collect(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mRoutines.Add(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  Result := TDictionary<string, Boolean>.Create;
  mRoutines := TList<TSyntaxNode>.Create;
  try
    if ATree.Root <> nil then
    begin
      Collect(ATree.Root);
    end;
    // Bis nichts mehr dazukommt: A ruft B, B löst aus.
    repeat
      mChanged := False;
      for mRoutine in mRoutines do
      begin
        if not Result.ContainsKey(LowerCase(ShortName(mRoutine.Name))) and
          (mRoutine.FindChild(TSyntaxKind.Block) <> nil) and
          Raises(mRoutine.FindChild(TSyntaxKind.Block), Result) then
        begin
          Result.Add(LowerCase(ShortName(mRoutine.Name)), True);
          mChanged := True;
        end;
      end;
    until not mChanged;
  finally
    mRoutines.Free;
  end;
end;

function HasExit(ANode: TSyntaxNode; AInner: Boolean; ARaising: TDictionary<string, Boolean>): Boolean;
var
  mIndex: Integer;
  mName: string;
  mInner: Boolean;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
  mPendingInner: TStack<Boolean>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  mPendingInner := TStack<Boolean>.Create;
  try
    mPending.Push(ANode);
    mPendingInner.Push(AInner);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mInner := mPendingInner.Pop;
      case mNode.Kind of
        TSyntaxKind.AnonymousMethod:
          Continue;
        TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
          Exit(True);
        TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call:
          begin
            mName := CalledName(mNode);
            if SameText(mName, 'Terminated') or MatchText(JumpName(mNode), cLeavingCalls) or
              ((mName <> '') and ARaising.ContainsKey(LowerCase(mName))) then
            begin
              Exit(True);
            end;
            if SameText(JumpName(mNode), 'Break') and not mInner then
            begin
              Exit(True);
            end;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      mInner := mInner or (mNode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
        TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
        mPendingInner.Push(mInner);
      end;
    end;
  finally
    mPendingInner.Free;
    mPending.Free;
  end;
end;

function InTryExcept(ANode: TSyntaxNode): Boolean;
var
  mChild, mParent: TSyntaxNode;
begin
  mChild := ANode;
  mParent := ANode.Parent;
  while (mParent <> nil) and not (mParent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    if (mParent.Kind = TSyntaxKind.TryStatement) and (mChild.Kind <> TSyntaxKind.ExceptBlock) and
      (mChild.Kind <> TSyntaxKind.FinallyBlock) and (mParent.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
    begin
      Exit(True);
    end;
    mChild := mParent;
    mParent := mParent.Parent;
  end;
  Result := False;
end;

end.
