unit Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols.Tests;

// Tests der Namenshilfen aus TypeRestrictions.Symbols: Namen eines Abschnitts, für Inline-Routinen nutzbare Namen
// des implementation-Teils, Typdeklarationen und letzter Namensteil.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeRestrictionSymbolsTests = class
  public
    [Test]
    procedure LastPartAfterLastDot;
    [Test]
    procedure InlineUsableNamesSkipVariablesAndTypedConstants;
    [Test]
    procedure InlineUsableNamesWithoutSection;
    [Test]
    procedure FindStructDeclFindsRecordsOnly;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols;

const
  cSource = 'unit U;'#10'interface'#10'implementation'#10 +
    'const'#10'  A = 1;'#10'  B: Integer = 2;'#10 +
    'type'#10'  TFarbe = (Rot, Gruen);'#10'  TPunkt = record X: Integer; end;'#10'  TZahl = Integer;'#10 +
    'var'#10'  V: Integer;'#10 +
    'procedure P;'#10'begin'#10'end;'#10 +
    'end.';

{ TTypeRestrictionSymbolsTests }

procedure TTypeRestrictionSymbolsTests.LastPartAfterLastDot;
begin
  Assert.AreEqual('TInnen', LastPart('TAussen.TInnen'));
  Assert.AreEqual('Name', LastPart('Name'));
end;

procedure TTypeRestrictionSymbolsTests.InlineUsableNamesSkipVariablesAndTypedConstants;
var
  mTree: TSyntaxTree;
  mNames: TArray<string>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mNames := InlineUsableNames(mTree.Root.FindChild(TSyntaxKind.ImplementationSection));
    Assert.IsTrue(MatchText('A', mNames), 'echte Konstante');
    Assert.IsTrue(MatchText('TFarbe', mNames), 'Typ');
    Assert.IsTrue(MatchText('Gruen', mNames), 'Aufzählungswert');
    Assert.IsTrue(MatchText('P', mNames), 'Routine');
    Assert.IsFalse(MatchText('B', mNames), 'typisierte Konstante');
    Assert.IsFalse(MatchText('V', mNames), 'Variable');
  finally
    mTree.Free;
  end;
end;

procedure TTypeRestrictionSymbolsTests.InlineUsableNamesWithoutSection;
begin
  Assert.AreEqual(0, Integer(Length(InlineUsableNames(nil))));
end;

procedure TTypeRestrictionSymbolsTests.FindStructDeclFindsRecordsOnly;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsNotNull(FindStructDecl(mTree.Root, 'TPunkt'));
    Assert.IsNull(FindStructDecl(mTree.Root, 'TZahl'));
    Assert.IsNull(FindStructDecl(nil, 'TPunkt'));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeRestrictionSymbolsTests);

end.
