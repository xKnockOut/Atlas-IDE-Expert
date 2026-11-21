unit Atlas.Common.Pascal.SyntaxNodes.Tests;

// Tests der gemeinsamen Abfragen am Syntaxbaum (Atlas.Common.Pascal.SyntaxNodes): Namen von Punktketten,
// Klammern, umgebende Knoten, Kinder an einem Offset, Direktiven, Zugriffswurzeln und Knotensuche.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSyntaxNodesTests = class
  public
    [Test]
    procedure DottedNamesOfChains;
    [Test]
    procedure ParensAroundExpression;
    [Test]
    procedure EnclosingAndNearestRoutine;
    [Test]
    procedure ChildrenAtOffset;
    [Test]
    procedure KindsAndMentions;
    [Test]
    procedure DirectivesOfHeader;
    [Test]
    procedure AccessRootAndFieldName;
    [Test]
    procedure EmptyBlocksAndFirstChild;
    [Test]
    procedure RoutinePathOfNestedRoutine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.SyntaxNodes;

const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TFoo<T> = class'#10'    procedure Run; virtual; abstract;'#10 +
    '  end;'#10'implementation'#10'procedure Aussen;'#10'  procedure Innen;'#10'  begin'#10'    X := ((Y));'#10 +
    '    Self.F := A.B[1]^;'#10'    Ziel := Unit1.Wert;'#10'  end;'#10'begin'#10'  ;'#10'end;'#10'end.';

/// <summary>Erster Knoten der Art AKind unter ARoot, dessen Name AName ist ('' = jeder).</summary>
function Find(ARoot: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  for mNode in TSyntaxNodes.OfKind(ARoot, AKind) do
  begin
    if (AName = '') or SameText(mNode.Name, AName) then
    begin
      Exit(mNode);
    end;
  end;
  Result := nil;
end;

/// <summary>Rechte Seite der Zuweisung an ATarget.</summary>
function ValueOf(ARoot: TSyntaxNode; const ATarget: string): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  for mNode in TSyntaxNodes.OfKind(ARoot, TSyntaxKind.AssignStatement) do
  begin
    if SameText(TSyntaxNodes.DottedName(mNode[0]), ATarget) then
    begin
      Exit(mNode[1]);
    end;
  end;
  Result := nil;
end;

{ TSyntaxNodesTests }

procedure TSyntaxNodesTests.DottedNamesOfChains;
var
  mTree: TSyntaxTree;
  mValue: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mValue := ValueOf(mTree.Root, 'Ziel');
    Assert.IsNotNull(mValue);
    Assert.AreEqual('Unit1.Wert', TSyntaxNodes.DottedName(mValue));
    Assert.IsTrue(TSyntaxNodes.IsNameChain(mValue));
    mValue := ValueOf(mTree.Root, 'Self.F');
    Assert.IsNotNull(mValue, 'Self.F ist eine Punktkette');
    Assert.AreEqual('', TSyntaxNodes.DottedName(mValue), 'A.B[1]^ ist keine reine Punktkette');
    Assert.IsFalse(TSyntaxNodes.IsNameChain(mValue));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.ParensAroundExpression;
var
  mTree: TSyntaxTree;
  mValue, mInner: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mValue := ValueOf(mTree.Root, 'X');
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.ParenExpr, mValue.Kind);
    mInner := TSyntaxNodes.Unparen(mValue);
    Assert.AreEqual('Y', mInner.Name);
    Assert.AreSame(mValue, TSyntaxNodes.OuterParens(mInner));
    Assert.IsNull(TSyntaxNodes.Unparen(nil));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.EnclosingAndNearestRoutine;
var
  mTree: TSyntaxTree;
  mInner, mOuter, mValue: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mOuter := Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Aussen');
    mInner := Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Innen');
    mValue := ValueOf(mTree.Root, 'X');
    Assert.AreSame(mInner, TSyntaxNodes.Enclosing(mValue, [TSyntaxKind.RoutineDecl]));
    Assert.AreSame(mOuter, TSyntaxNodes.Enclosing(mInner, [TSyntaxKind.RoutineDecl]), 'ANode selbst zählt nicht');
    Assert.IsNull(TSyntaxNodes.Enclosing(mValue, [TSyntaxKind.RoutineDecl], mInner), 'AStop beendet die Suche');
    Assert.AreSame(mInner, TSyntaxNodes.Nearest(mInner, [TSyntaxKind.RoutineDecl]), 'ANode selbst zählt');
    Assert.IsNull(TSyntaxNodes.Nearest(nil, [TSyntaxKind.RoutineDecl]));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.ChildrenAtOffset;
var
  mTree: TSyntaxTree;
  mValue, mAssign: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mValue := ValueOf(mTree.Root, 'X');
    mAssign := mValue.Parent;
    Assert.AreSame(mValue, TSyntaxNodes.ChildAt(mAssign, mValue.StartOffset));
    Assert.IsNull(TSyntaxNodes.ChildAt(mAssign, mAssign.EndOffset + 1));
    Assert.AreEqual('Y', TSyntaxNodes.DeepestAt(mTree.Root, Pos('Y))', cSource) - 1).Name);
    Assert.AreEqual(1, TSyntaxNodes.IndexOf(mAssign, mValue));
    Assert.AreEqual(-1, TSyntaxNodes.IndexOf(mAssign, mTree.Root));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.KindsAndMentions;
var
  mTree: TSyntaxTree;
  mInner: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mInner := Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Innen');
    Assert.IsTrue(TSyntaxNodes.ContainsKind(mInner, TSyntaxKind.Dereference));
    Assert.IsFalse(TSyntaxNodes.ContainsKind(mInner, TSyntaxKind.WithStatement));
    Assert.IsTrue(TSyntaxNodes.Mentions(mInner, 'y'));
    Assert.IsFalse(TSyntaxNodes.Mentions(mInner, 'Z'));
    Assert.AreEqual(2, Integer(Length(TSyntaxNodes.OfKind(mTree.Root, TSyntaxKind.RoutineDecl))));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.DirectivesOfHeader;
var
  mTree: TSyntaxTree;
  mHeader: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mHeader := Find(Find(mTree.Root, TSyntaxKind.ClassType, ''), TSyntaxKind.RoutineHeader, '');
    Assert.IsNotNull(mHeader);
    Assert.IsTrue(TSyntaxNodes.HasDirective(mHeader, ['override', 'Virtual']));
    Assert.IsFalse(TSyntaxNodes.HasDirective(mHeader, ['overload']));
    Assert.IsFalse(TSyntaxNodes.HasDirective(nil, ['virtual']));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.AccessRootAndFieldName;
var
  mTree: TSyntaxTree;
  mValue, mA: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mValue := ValueOf(mTree.Root, 'Self.F');
    mA := Find(mValue, TSyntaxKind.Identifier, 'A');
    Assert.AreSame(mValue, TSyntaxNodes.AccessRoot(mA));
    Assert.AreEqual('F', TSyntaxNodes.FieldName(mValue.Parent[0]));
    Assert.AreEqual('A', TSyntaxNodes.FieldName(mA));
    Assert.AreEqual('', TSyntaxNodes.FieldName(mValue));
    Assert.AreEqual('', TSyntaxNodes.FieldName(nil));
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.EmptyBlocksAndFirstChild;
var
  mTree: TSyntaxTree;
  mOuter, mBlock, mType: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mOuter := Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Aussen');
    mBlock := Find(mOuter, TSyntaxKind.Block, '');
    Assert.IsFalse(TSyntaxNodes.OnlyEmptyStatements(mBlock), 'Erster Block ist der von Innen');
    mBlock := mOuter[mOuter.ChildCount - 1];
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Block, mBlock.Kind);
    Assert.IsTrue(TSyntaxNodes.OnlyEmptyStatements(mBlock));
    mType := Find(mTree.Root, TSyntaxKind.TypeDecl, 'TFoo');
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.ClassType,
      TSyntaxNodes.FirstChildExcept(mType, [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]).Kind);
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxNodesTests.RoutinePathOfNestedRoutine;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual('Aussen.Innen', TSyntaxNodes.RoutinePath(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Innen')));
    Assert.AreEqual('Aussen', TSyntaxNodes.RoutinePath(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Aussen')));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyntaxNodesTests);

end.
