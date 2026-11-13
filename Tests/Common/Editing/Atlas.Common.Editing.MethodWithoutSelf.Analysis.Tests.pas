unit Atlas.Common.Editing.MethodWithoutSelf.Analysis.Tests;

// Tests der Analyse-Helfer von „Methode ohne Self“ (#686): einfache Typen für den Record-Helper, Abbruch mit Grund,
// Ortsangabe und die Art einer Verwendung (Aufruf, Methodenzeiger, unbekannt).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodAnalysisTests = class
  public
    [Test]
    procedure SimpleTypesForHelper;
    [Test]
    procedure FailKeepsReason;
    [Test]
    procedure WhereNamesLineAndFile;
    [Test]
    procedure UseAtTellsCallFromPointer;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.MethodWithoutSelf.Contract,
  Atlas.Common.Editing.MethodWithoutSelf.Analysis;

const
  cSource =
    'unit Lager;'#10 +
    'implementation'#10 +
    'procedure Fuelle;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Arbeite;'#10 +
    'var'#10 +
    '  mZeiger: Pointer;'#10 +
    'begin'#10 +
    '  Fuelle;'#10 +
    '  mZeiger := @Fuelle;'#10 +
    'end;'#10 +
    'end.'#10;

procedure TMethodAnalysisTests.SimpleTypesForHelper;
begin
  Assert.IsTrue(TMethodPlan.IsSimpleType('string'));
  Assert.IsTrue(TMethodPlan.IsSimpleType(' Integer '));
  Assert.IsTrue(TMethodPlan.IsSimpleType('tdatetime'));
  Assert.IsFalse(TMethodPlan.IsSimpleType('TLager'));
  Assert.IsFalse(TMethodPlan.IsSimpleType(''));
end;

procedure TMethodAnalysisTests.FailKeepsReason;
var
  mReason: string;
begin
  Assert.IsFalse(TMethodPlan.Fail('virtuell', mReason));
  Assert.AreEqual('virtuell', mReason);
end;

procedure TMethodAnalysisTests.WhereNamesLineAndFile;
begin
  Assert.Contains(TMethodPlan.Where('', 2), '3');
  Assert.Contains(TMethodPlan.Where('C:\Quellen\Lager.pas', 9), 'Lager.pas');
  Assert.Contains(TMethodPlan.Where('C:\Quellen\Lager.pas', 9), '10');
end;

procedure TMethodAnalysisTests.UseAtTellsCallFromPointer;
var
  mTree: TSyntaxTree;
  mCallee: TSyntaxNode;
  mCall: TSyntaxNode;
  mCallAt: Integer;
  mPointerAt: Integer;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mCallAt := Pos('  Fuelle;', cSource) + 1;
    mPointerAt := Pos('@Fuelle', cSource);
    Assert.AreEqual(Ord(TMethodUse.Call), Ord(TMethodPlan.UseAt(mTree, mCallAt, 'Fuelle', mCallee, mCall)));
    Assert.IsNotNull(mCallee);
    Assert.AreEqual(Ord(TMethodUse.Pointer), Ord(TMethodPlan.UseAt(mTree, mPointerAt, 'Fuelle', mCallee, mCall)));
    Assert.AreEqual(Ord(TMethodUse.Unknown), Ord(TMethodPlan.UseAt(mTree, 0, 'Fehlt', mCallee, mCall)));
    Assert.IsNull(mCallee);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodAnalysisTests);

end.
