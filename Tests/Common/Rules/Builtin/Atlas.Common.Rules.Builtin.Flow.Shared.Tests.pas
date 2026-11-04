unit Atlas.Common.Rules.Builtin.Flow.Shared.Tests;

// Tests der gemeinsamen Hilfen der Flussregeln: Verwendungen, die der Kontrollfluss nicht sieht, Namen in Ketten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowSharedTests = class
  public
    [Test]
    procedure OpaqueUses;
    [Test]
    procedure NamesInChains;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Flow.Shared;

/// <summary>Rumpf von "procedure P" mit ABody, als Text einer Unit.</summary>
function Body(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

/// <summary>Erster Knoten der Art AKind unter ARoot.</summary>
function FirstOf(ARoot: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
begin
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = AKind then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

/// <summary>Hat der Rumpf ABody eine für den Fluss unsichtbare Verwendung von AName?</summary>
function Opaque(const ABody, AName: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Body(ABody));
  try
    Result := HasOpaqueUse(FirstOf(mTree.Root, TSyntaxKind.Block), AName);
  finally
    mTree.Free;
  end;
end;

procedure TFlowSharedTests.OpaqueUses;
begin
  Assert.IsTrue(Opaque('  Q := @X;', 'X'));
  Assert.IsTrue(Opaque('  Lies(X);', 'X'));
  Assert.IsTrue(Opaque('  Lies(X.Wert);', 'X'));
  Assert.IsTrue(Opaque('  X.Wert := 1;', 'X'));
  Assert.IsTrue(Opaque('  with X do'#10'    Lauf;', 'X'));
  Assert.IsFalse(Opaque('  X := 1;', 'X'));
  Assert.IsFalse(Opaque('  Q := @X;', 'Y'));
end;

procedure TFlowSharedTests.NamesInChains;
var
  mTree: TSyntaxTree;
  mAssign: TSyntaxNode;
begin
  Assert.AreEqual('Lauf', ShortName('TKunde.Lauf'));
  Assert.AreEqual('Lauf', ShortName('Lauf'));
  mTree := TPascalParser.Parse(Body('  Result.Wert[1] := 2;'));
  try
    mAssign := FirstOf(mTree.Root, TSyntaxKind.AssignStatement);
    Assert.AreEqual('Result', RootName(mAssign[0]));
    Assert.IsFalse(IsAssignTo(mAssign, 'Result'));
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(Body('  Result := 2;'));
  try
    Assert.IsTrue(IsAssignTo(FirstOf(mTree.Root, TSyntaxKind.AssignStatement), 'result'));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowSharedTests);

end.
