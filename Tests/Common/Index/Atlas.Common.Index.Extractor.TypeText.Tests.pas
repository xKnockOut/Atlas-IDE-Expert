unit Atlas.Common.Index.Extractor.TypeText.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexTypeTextTests = class
  public
    [Test]
    procedure TypeTextKeepsNestedTypeArgs;
    [Test]
    procedure ParamInfoCountsNamesAndDefaults;
    [Test]
    procedure UsesOfListsUnits;
    [Test]
    procedure ProcedureTypeAndVirtualHeader;
    [Test]
    procedure NamingOfCountsPrefixedFields;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor.TypeText;

function Join(const ALines: array of string): string;
begin
  Result := String.Join(#13#10, ALines);
end;

/// <summary>Erster Knoten der Art AKind mit dem Namen AName ('' = jeder Name).</summary>
function NodeOf(ARoot: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
begin
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = AKind) and ((AName = '') or SameText(ANode.Name, AName)) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

procedure TIndexTypeTextTests.TypeTextKeepsNestedTypeArgs;
var
  mTree: TSyntaxTree;
  mVar: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', 'var',
    '  Kunden: TDictionary<string, TList<Integer>>;', 'implementation', 'end.']));
  try
    mVar := NodeOf(mTree.Root, TSyntaxKind.VarDecl, 'Kunden');
    Assert.IsNotNull(mVar);
    Assert.AreEqual('TDictionary', TIndexTypeText.DeclaredType(mVar));
    Assert.AreEqual('string,TList<Integer>', TIndexTypeText.GenericArgsText(TIndexTypeText.DeclaredTypeNode(mVar)));
    Assert.AreEqual('TDictionary<string,TList<Integer>>',
      TIndexTypeText.TypeText(TIndexTypeText.DeclaredTypeNode(mVar)));
  finally
    mTree.Free;
  end;
end;

procedure TIndexTypeTextTests.ParamInfoCountsNamesAndDefaults;
var
  mTree: TSyntaxTree;
  mMin, mMax: Integer;
  mTypes: TArray<string>;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface',
    'procedure Laden(A, B: Integer; const C: string = ''x'');', 'implementation', 'end.']));
  try
    TIndexTypeText.ParamInfo(NodeOf(mTree.Root, TSyntaxKind.RoutineHeader, 'Laden'), mMin, mMax, mTypes);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(2, mMin);
  Assert.AreEqual(3, mMax);
  Assert.AreEqual('Integer,Integer,string', String.Join(',', mTypes));
end;

procedure TIndexTypeTextTests.UsesOfListsUnits;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', 'uses System.SysUtils, Werkzeug;',
    'implementation', 'end.']));
  try
    Assert.AreEqual('System.SysUtils,Werkzeug', String.Join(',',
      TIndexTypeText.UsesOf(mTree.Root.FindChild(TSyntaxKind.InterfaceSection))));
    Assert.AreEqual(0, Integer(Length(TIndexTypeText.UsesOf(mTree.Root.FindChild(
      TSyntaxKind.ImplementationSection)))));
  finally
    mTree.Free;
  end;
end;

procedure TIndexTypeTextTests.ProcedureTypeAndVirtualHeader;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', 'type',
    '  TEreignis = procedure(A: Integer) of object;', '  TZahl = Integer;', '  TBasis = class',
    '    procedure Zeichnen; virtual;', '    procedure Laden;', '  end;', 'implementation', 'end.']));
  try
    Assert.IsNotNull(TIndexTypeText.ProcedureTypeOf(NodeOf(mTree.Root, TSyntaxKind.TypeDecl, 'TEreignis')));
    Assert.IsNull(TIndexTypeText.ProcedureTypeOf(NodeOf(mTree.Root, TSyntaxKind.TypeDecl, 'TZahl')));
    Assert.IsTrue(TIndexTypeText.IsVirtualHeader(NodeOf(mTree.Root, TSyntaxKind.RoutineHeader, 'Zeichnen')));
    Assert.IsFalse(TIndexTypeText.IsVirtualHeader(NodeOf(mTree.Root, TSyntaxKind.RoutineHeader, 'Laden')));
  finally
    mTree.Free;
  end;
end;

procedure TIndexTypeTextTests.NamingOfCountsPrefixedFields;
var
  mTree: TSyntaxTree;
  mCounts: TNamingCounts;
begin
  mTree := TPascalParser.Parse(Join(['unit U;', 'interface', 'type', '  TForm = class',
    '    FName, Stadt: string;', '  end;', 'var', '  Global: Integer;', 'implementation', 'end.']));
  try
    mCounts := TIndexTypeText.NamingOf(mTree.Root);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(2, mCounts[TNamingKind.Field].Total);
  Assert.AreEqual(1, mCounts[TNamingKind.Field].Prefixed);
  // Die globale Variable zählt nicht.
  Assert.AreEqual(0, mCounts[TNamingKind.Local].Total);
  Assert.IsTrue(TIndexTypeText.HasNamePrefix('FName', 'F'));
  Assert.IsFalse(TIndexTypeText.HasNamePrefix('Fast', 'F'));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexTypeTextTests);

end.
