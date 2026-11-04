unit Atlas.Common.Rules.Builtin.Conditions.Jumps.Tests;

// Tests der Sprünge und Ausgänge (Atlas.Common.Rules.Builtin.Conditions.Jumps): Kurzname, Name eines Aufrufs
// und eines Sprungs (TMonitor.Exit ist keiner), auslösende Routinen, Ausgang einer Schleife über Exit, Break
// und eine auslösende Routine, Break einer inneren Schleife, try … except.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConditionJumpsTests = class
  public
    [Test]
    procedure Names;
    [Test]
    procedure RaisingRoutinesOfFile;
    [Test]
    procedure LoopExits;
    [Test]
    procedure TryExcept;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Conditions.Jumps;

/// <summary>Knoten der Art AKind im Baum in Vorordnung.</summary>
function NodesOf(ARoot: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = AKind then
      begin
        Result := Result + [mNode];
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

function UnitWith(const ABody: string): string;
begin
  Result := 'unit Daten;'#10'interface'#10'implementation'#10 +
    'procedure Fehler;'#10'begin'#10'  raise Exception.Create(''x'');'#10'end;'#10 +
    'procedure P(X: Boolean);'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TConditionJumpsTests.Names;
var
  mTree: TSyntaxTree;
  mCalls: TArray<TSyntaxNode>;
begin
  Assert.AreEqual('Bar', ShortName('TFoo.Bar'));
  Assert.AreEqual('Bar', ShortName('Bar'));
  mTree := TPascalParser.Parse(UnitWith('  Exit;'#10'  TMonitor.Exit(Self);'#10'  Fehler;'#10));
  try
    mCalls := NodesOf(mTree.Root, TSyntaxKind.CallStatement);
    Assert.AreEqual(3, Integer(Length(mCalls)));
    Assert.AreEqual('Exit', JumpName(mCalls[0][0]));
    Assert.AreEqual('', JumpName(mCalls[1][0]));
    Assert.AreEqual('Fehler', CalledName(mCalls[2][0]));
  finally
    mTree.Free;
  end;
end;

procedure TConditionJumpsTests.RaisingRoutinesOfFile;
var
  mTree: TSyntaxTree;
  mRaising: TDictionary<string, Boolean>;
begin
  mTree := TPascalParser.Parse(UnitWith('  X := True;'#10));
  mRaising := RaisingRoutines(mTree);
  try
    Assert.IsTrue(mRaising.ContainsKey('fehler'));
    Assert.IsFalse(mRaising.ContainsKey('p'));
  finally
    mRaising.Free;
    mTree.Free;
  end;
end;

procedure TConditionJumpsTests.LoopExits;
var
  mTree: TSyntaxTree;
  mRaising: TDictionary<string, Boolean>;
  mLoops: TArray<TSyntaxNode>;
begin
  mTree := TPascalParser.Parse(UnitWith('  while True do'#10'    if X then'#10'      Fehler;'#10 +
    '  while True do'#10'    while X do'#10'      Break;'#10 + '  while True do'#10'    X := not X;'#10));
  mRaising := RaisingRoutines(mTree);
  try
    mLoops := NodesOf(mTree.Root, TSyntaxKind.WhileStatement);
    Assert.AreEqual(4, Integer(Length(mLoops)));
    Assert.IsTrue(HasExit(mLoops[0][1], False, mRaising));
    // Break der inneren Schleife verlässt nur diese.
    Assert.IsFalse(HasExit(mLoops[1][1], False, mRaising));
    Assert.IsFalse(HasExit(mLoops[3][1], False, mRaising));
  finally
    mRaising.Free;
    mTree.Free;
  end;
end;

procedure TConditionJumpsTests.TryExcept;
var
  mTree: TSyntaxTree;
  mCalls: TArray<TSyntaxNode>;
begin
  mTree := TPascalParser.Parse(UnitWith('  try'#10'    Fehler;'#10'  except'#10'    Fehler;'#10'  end;'#10));
  try
    mCalls := NodesOf(mTree.Root, TSyntaxKind.CallStatement);
    Assert.AreEqual(2, Integer(Length(mCalls)));
    Assert.IsTrue(InTryExcept(mCalls[0]));
    Assert.IsFalse(InTryExcept(mCalls[1]));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionJumpsTests);

end.
