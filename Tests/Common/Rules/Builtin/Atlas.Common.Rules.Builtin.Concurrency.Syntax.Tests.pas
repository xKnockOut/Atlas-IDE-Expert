unit Atlas.Common.Rules.Builtin.Concurrency.Syntax.Tests;

// Tests der gemeinsamen Bausteine der Nebenläufigkeitsregeln (Atlas.Common.Rules.Builtin.Concurrency.Syntax):
// Listensuche, Methodenaufruf als Anweisung, Klassen- und Methodenteil eines Routinennamens, Variablennamen,
// Erwähnung eines Bezeichners, Thread-Klassen über Zwischenklassen und das Entfernen einer ganzen Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConcurrencySyntaxTests = class
  public
    [Test]
    procedure ListsAndNames;
    [Test]
    procedure MethodCalls;
    [Test]
    procedure ThreadClassesOfUnit;
    [Test]
    procedure RemovalOfStatement;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax;

/// <summary>Unit mit den Anweisungen ABody in der Prozedur TFoo.Run.</summary>
function UnitWith(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TBase = class(TThread)'#10'  end;'#10 +
    '  TWorker = class(TBase)'#10'  end;'#10'  TOther = class'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.Run;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TConcurrencySyntaxTests.ListsAndNames;
begin
  Assert.IsTrue(InList(VclGlobals, 'application'));
  Assert.IsFalse(InList(VclGlobals, 'Form1'));
  Assert.AreEqual('TA', ClassPart('TA.Destroy'));
  Assert.AreEqual('', ClassPart('Destroy'));
  Assert.AreEqual('Destroy', MethodPart('TA.Destroy'));
end;

procedure TConcurrencySyntaxTests.MethodCalls;
var
  mTree: TSyntaxTree;
  mLists: TArray<TSyntaxNode>;
  mCall: TMethodCall;
begin
  mTree := TPascalParser.Parse(UnitWith('  FLock.Enter;'#10'  Machwas(FX);'#10'  X := 1;'#10));
  try
    mLists := StatementLists(mTree.Root);
    Assert.AreEqual(1, Integer(Length(mLists)));
    Assert.IsTrue(TryMethodCall(mLists[0][0], mCall));
    Assert.AreEqual('Enter', mCall.Method);
    Assert.AreEqual('FLock', VariableName(mCall.Receiver));
    Assert.IsTrue(TryMethodCall(mLists[0][1], mCall));
    Assert.AreEqual('Machwas', mCall.Method);
    Assert.IsTrue(Mentions(mLists[0][1], 'FX'));
    Assert.IsFalse(Mentions(mLists[0][1], 'FY'));
    Assert.IsFalse(TryMethodCall(mLists[0][2], mCall));
  finally
    mTree.Free;
  end;
end;

procedure TConcurrencySyntaxTests.ThreadClassesOfUnit;
var
  mTree: TSyntaxTree;
  mNames: TArray<string>;
begin
  mTree := TPascalParser.Parse(UnitWith(''));
  try
    mNames := ThreadClasses(mTree.Root);
    TArray.Sort<string>(mNames);
    Assert.AreEqual('TBase,TWorker', string.Join(',', mNames));
  finally
    mTree.Free;
  end;
end;

procedure TConcurrencySyntaxTests.RemovalOfStatement;
var
  mText: string;
  mTree: TSyntaxTree;
  mLists: TArray<TSyntaxNode>;
  mRange: TTextRange;
begin
  mText := UnitWith('  FLock.Enter;'#10'  X := 1; FLock.Leave;'#10);
  mTree := TPascalParser.Parse(mText);
  try
    mLists := StatementLists(mTree.Root);
    // Allein in der Zeile: ganze Zeile samt Zeilenende.
    mRange := StatementRemoval(mText, mLists[0][0]);
    Assert.AreEqual(0, mRange.StartPos.Character);
    Assert.AreEqual(mLists[0][0].StartPos.Line + 1, mRange.EndPos.Line);
    // Mit anderer Anweisung in der Zeile: nur die Anweisung.
    mRange := StatementRemoval(mText, mLists[0][2]);
    Assert.AreEqual(mLists[0][2].StartPos.Character, mRange.StartPos.Character);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TConcurrencySyntaxTests);

end.
