unit Atlas.Common.Editing.TypeAlias.Names.Tests;

// Tests für die Namen von „Typ-Alias einführen“ (#681): letzter Namensteil, Typknoten und der Vorschlag aus dem
// Zusammenhang eines Felds.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeAliasNamesTests = class
  public
    [Test]
    procedure LastPartCutsQualifier;
    [Test]
    procedure TypeNodeNeedsTypeKind;
    [Test]
    procedure SuggestsNameFromField;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.TypeAlias.Names;

const
  cSource =
    'unit Lager;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TLager = class'#10 +
    '    FGroups: TList<TKunde>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.'#10;

/// <summary>Erster Knoten der Art AKind unter ANode (Tiefensuche); nil ohne.</summary>
function FindKind(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = AKind then
  begin
    Result := ANode;
    Exit;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindKind(ANode[mIndex], AKind);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
end;

procedure TTypeAliasNamesTests.LastPartCutsQualifier;
begin
  Assert.AreEqual('TList', TTypeAliasNames.LastPart('System.Generics.Collections.TList'));
  Assert.AreEqual('TKunde', TTypeAliasNames.LastPart('TKunde'));
end;

procedure TTypeAliasNamesTests.TypeNodeNeedsTypeKind;
var
  mTree: TSyntaxTree;
begin
  Assert.IsFalse(TTypeAliasNames.IsTypeNode(nil));
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsTrue(TTypeAliasNames.IsTypeNode(FindKind(mTree.Root, TSyntaxKind.TypeReference)));
    Assert.IsFalse(TTypeAliasNames.IsTypeNode(FindKind(mTree.Root, TSyntaxKind.Field)));
  finally
    mTree.Free;
  end;
end;

procedure TTypeAliasNamesTests.SuggestsNameFromField;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual('TKundeGroups', TTypeAliasNames.Suggest(FindKind(mTree.Root, TSyntaxKind.TypeReference)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeAliasNamesTests);

end.
