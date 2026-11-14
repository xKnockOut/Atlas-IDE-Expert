unit Atlas.Common.Rules.Builtin.Conditions.Values.Tests;

// Tests der festen Werte von Bedingungen (Atlas.Common.Rules.Builtin.Conditions.Values): ein fester Operand
// entscheidet and/or, Vergleiche und Rechnen mit Zahlen, Division durch 0 bleibt unbekannt, not und xor,
// untypisierte Konstanten der Datei; BoolText und NodeText.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConditionValuesTests = class
  public
    [Test]
    procedure DecidingOperand;
    [Test]
    procedure ArithmeticAndComparison;
    [Test]
    procedure DivisionByZeroStaysUnknown;
    [Test]
    procedure NotAndXor;
    [Test]
    procedure FileConstant;
    [Test]
    procedure Texts;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Conditions.Values;

const
  cFileName = 'Daten.pas';

/// <summary>Erste Bedingung einer if-Anweisung im Baum.</summary>
function FirstCondition(ARoot: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while (mPending.Count > 0) and (Result = nil) do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.IfStatement) and (mNode.ChildCount > 0) then
      begin
        Result := mNode[0];
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

function UnitWith(const ACondition: string): string;
begin
  Result := 'unit Daten;'#10'interface'#10'implementation'#10'const'#10'  AN = True;'#10 +
    'procedure P(X: Boolean);'#10'begin'#10'  if ' + ACondition + ' then'#10'    X := False;'#10'end;'#10'end.';
end;

function Evaluated(const ACondition: string): TConstantValue;
var
  mText: string;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mValues: TConditionValues;
begin
  mText := UnitWith(ACondition);
  mTree := TPascalParser.Parse(mText);
  mResolver := TNameResolver.Create(nil);
  try
    mResolver.PinTree(mTree, cFileName);
    mValues := TConditionValues.Create(mTree, mText, cFileName, mResolver, nil);
    try
      Result := mValues.Evaluate(FirstCondition(mTree.Root));
    finally
      mValues.Free;
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TConditionValuesTests.DecidingOperand;
var
  mValue: TConstantValue;
begin
  mValue := Evaluated('X or True');
  Assert.AreEqual<TConstantKind>(TConstantKind.Bool, mValue.Kind);
  Assert.IsTrue(mValue.Bool);
  Assert.AreEqual('… or True', mValue.Shown);
  mValue := Evaluated('False and X');
  Assert.AreEqual<TConstantKind>(TConstantKind.Bool, mValue.Kind);
  Assert.IsFalse(mValue.Bool);
  Assert.AreEqual('False and …', mValue.Shown);
  Assert.AreEqual<TConstantKind>(TConstantKind.Unknown, Evaluated('X and True').Kind);
end;

procedure TConditionValuesTests.ArithmeticAndComparison;
var
  mValue: TConstantValue;
begin
  mValue := Evaluated('2 * 3 - 1 >= 5');
  Assert.AreEqual<TConstantKind>(TConstantKind.Bool, mValue.Kind);
  Assert.IsTrue(mValue.Bool);
  Assert.AreEqual('2 * 3 - 1 >= 5', mValue.Shown);
  Assert.IsFalse(Evaluated('7 div 2 <> 3').Bool);
  Assert.IsTrue(Evaluated('7 mod 2 = 1').Bool);
  Assert.IsTrue(Evaluated('-1 < +1').Bool);
end;

procedure TConditionValuesTests.DivisionByZeroStaysUnknown;
begin
  Assert.AreEqual<TConstantKind>(TConstantKind.Unknown, Evaluated('1 div 0 = 1').Kind);
end;

procedure TConditionValuesTests.NotAndXor;
var
  mValue: TConstantValue;
begin
  mValue := Evaluated('not False');
  Assert.IsTrue(mValue.Bool);
  Assert.AreEqual('not False', mValue.Shown);
  Assert.IsFalse(Evaluated('True xor True').Bool);
  Assert.IsTrue(Evaluated('True = (1 < 2)').Bool);
end;

procedure TConditionValuesTests.FileConstant;
var
  mValue: TConstantValue;
begin
  mValue := Evaluated('AN');
  Assert.AreEqual<TConstantKind>(TConstantKind.Bool, mValue.Kind);
  Assert.AreEqual('AN = True', mValue.Shown);
end;

procedure TConditionValuesTests.Texts;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('True', BoolText(True));
  Assert.AreEqual('False', BoolText(False));
  mText := UnitWith('X or True');
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual('X or True', NodeText(mText, FirstCondition(mTree.Root)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionValuesTests);

end.
