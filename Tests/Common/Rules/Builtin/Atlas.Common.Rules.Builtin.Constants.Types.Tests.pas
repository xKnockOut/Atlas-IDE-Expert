unit Atlas.Common.Rules.Builtin.Constants.Types.Tests;

// Tests der gemeinsamen Bausteine der Regeln für Konstanten und Zahlen (Atlas.Common.Rules.Builtin.Constants.Types):
// einheitliche Typnamen, Wertebereiche, Teilbereiche aus einer Signatur, Text hinter "=", Art eines ganzzahligen
// Typs, Wörter einer Deklaration und der Name eines Operanden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConstantTypesTests = class
  public
    [Test]
    procedure CanonicalNames;
    [Test]
    procedure RangesAndSubranges;
    [Test]
    procedure IntegerKinds;
    [Test]
    procedure WordsAndOperands;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Constants.Types;

procedure TConstantTypesTests.CanonicalNames;
begin
  Assert.AreEqual('integer', CanonicalTypeName('System.LongInt'));
  Assert.AreEqual('cardinal', CanonicalTypeName('DWORD'));
  Assert.AreEqual('double', CanonicalTypeName('Real'));
  Assert.AreEqual('nativeuint', CanonicalTypeName('UIntPtr'));
  Assert.AreEqual('tfoo', CanonicalTypeName(' TFoo '));
end;

procedure TConstantTypesTests.RangesAndSubranges;
var
  mLow, mHigh: Int64;
begin
  Assert.IsTrue(IntegerRange('Byte', mLow, mHigh));
  Assert.AreEqual(Int64(0), mLow);
  Assert.AreEqual(Int64(255), mHigh);
  Assert.IsFalse(IntegerRange('Char', mLow, mHigh));
  Assert.IsTrue(SubrangeOf('TProzent = 0..100;', mLow, mHigh));
  Assert.AreEqual(Int64(100), mHigh);
  Assert.IsFalse(SubrangeOf('TName = string;', mLow, mHigh));
  Assert.AreEqual('UInt64', TypeBodyOf('TGroesse = UInt64;'));
  Assert.AreEqual('', TypeBodyOf('TGroesse'));
end;

procedure TConstantTypesTests.IntegerKinds;
var
  mKind: TIntegerKind;
begin
  mKind := IntegerKindOf('System.Int16');
  Assert.AreEqual(16, mKind.Bits);
  Assert.IsTrue(mKind.Signed);
  mKind := IntegerKindOf('DWORD');
  Assert.AreEqual(32, mKind.Bits);
  Assert.IsFalse(mKind.Signed);
  Assert.AreEqual(0, IntegerKindOf('NativeInt').Bits);
end;

procedure TConstantTypesTests.WordsAndOperands;
var
  mTree: TSyntaxTree;
  mCall: TSyntaxNode;
begin
  Assert.AreEqual('A,B,Integer', string.Join(',', DeclarationWords('A, B: Integer;')));
  mTree := TPascalParser.Parse('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  Liste.Items(1);'#10'end;'#10'end.');
  try
    mCall := mTree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Descend;
        if ANode.Kind = TSyntaxKind.CallStatement then
        begin
          Result := TSyntaxSearchStep.Found;
        end;
      end);
    Assert.IsNotNull(mCall);
    // Name eines Operanden: an Aufrufen entlang nach links bis zum Namen.
    Assert.AreEqual('Items', OperandName(mCall[0]));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TConstantTypesTests);

end.
