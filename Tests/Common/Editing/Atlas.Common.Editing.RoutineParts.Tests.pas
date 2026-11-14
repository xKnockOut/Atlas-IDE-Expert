unit Atlas.Common.Editing.RoutineParts.Tests;

// Tests für die Bausteine der Routinen-Umformungen (#663, #680): Parameter
// einzeln, Kopf als Text (auch einer anonymen Methode), freie Namen,
// Änderungen in Offsets, lokale Namen einer anonymen Methode und Verdeckung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRoutinePartsTests = class
  public
    [Test]
    procedure ParametersAndHeads;
    [Test]
    procedure AnonymousHeadAndFunction;
    [Test]
    procedure FreeNameAndEdits;
    [Test]
    procedure AnonymousParametersShadow;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineParts;

const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'function Rechne(const A, B: Integer; var C: string): Integer;'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  X := 1;'#10 +
    '  Liste.ForEach(procedure(const X: Integer) begin Log(X); end);'#10 +
    '  Result := X;'#10 +
    'end;'#10 +
    'end.'#10;

function FirstOf(ATree: TSyntaxTree; AKind: TSyntaxKind): TSyntaxNode;
var
  mNodes: TList<TSyntaxNode>;
begin
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ATree.Root, AKind, mNodes);
    Assert.IsTrue(mNodes.Count > 0);
    Result := mNodes[0];
  finally
    mNodes.Free;
  end;
end;

procedure TRoutinePartsTests.ParametersAndHeads;
var
  mTree: TSyntaxTree;
  mRoutine: TSyntaxNode;
  mParameters: TArray<TParameterText>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mRoutine := FirstOf(mTree, TSyntaxKind.RoutineDecl);
    mParameters := TRoutineParts.ParameterTexts(cSource, TRoutineParts.HeaderOf(mRoutine));
    Assert.AreEqual(3, Integer(Length(mParameters)));
    Assert.AreEqual('const A: Integer', mParameters[0].Text);
    Assert.AreEqual('B', mParameters[1].Name);
    Assert.AreEqual('var', mParameters[2].Modifier);
    Assert.AreEqual('function Neu(const A: Integer; const B: Integer; var C: string): Integer;',
      TRoutineParts.HeadText(cSource, TRoutineParts.HeaderOf(mRoutine), 'Neu', mParameters, False));
    Assert.AreEqual('class function Neu: Integer;', TRoutineParts.HeadText(cSource, TRoutineParts.HeaderOf(mRoutine),
      'Neu', nil, True));
    Assert.IsTrue(TRoutineParts.IsFunction(mRoutine));
  finally
    mTree.Free;
  end;
end;

procedure TRoutinePartsTests.AnonymousHeadAndFunction;
var
  mTree: TSyntaxTree;
  mAnonymous: TSyntaxNode;
  mParameters: TArray<TParameterText>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mAnonymous := FirstOf(mTree, TSyntaxKind.AnonymousMethod);
    Assert.IsFalse(TRoutineParts.IsFunction(mAnonymous));
    mParameters := TRoutineParts.ParameterTexts(cSource, mAnonymous);
    Assert.AreEqual(1, Integer(Length(mParameters)));
    Assert.AreEqual('procedure(const X: Integer)', TRoutineParts.AnonymousHead(cSource, mAnonymous, mParameters));
    Assert.AreEqual('procedure Name(const X: Integer);', TRoutineParts.HeadText(cSource, mAnonymous, 'Name',
      mParameters, False));
    Assert.AreEqual('function(const A: Integer; const B: Integer; var C: string): Integer',
      TRoutineParts.AnonymousHead(cSource, TRoutineParts.HeaderOf(FirstOf(mTree, TSyntaxKind.RoutineDecl)),
      TRoutineParts.ParameterTexts(cSource, TRoutineParts.HeaderOf(FirstOf(mTree, TSyntaxKind.RoutineDecl)))));
  finally
    mTree.Free;
  end;
end;

procedure TRoutinePartsTests.FreeNameAndEdits;
begin
  Assert.AreEqual('Neu', TRoutineParts.FreeName('Neu', TArray<string>.Create('Alt')));
  Assert.AreEqual('Neu3', TRoutineParts.FreeName('Neu', TArray<string>.Create('neu', 'Neu2')));
  // Offsets beziehen sich auf den ganzen Text, der Ausschnitt beginnt bei 10.
  Assert.AreEqual('xAyz', TRoutineParts.ApplyEdits('xay', 10, [TOffsetEdit.Create(13, 13, 'z'),
    TOffsetEdit.Create(11, 12, 'A')]));
end;

procedure TRoutinePartsTests.AnonymousParametersShadow;
var
  mTree: TSyntaxTree;
  mAnonymous, mRoutine, mNode: TSyntaxNode;
  mCache: TLocalsCache;
  mNodes: TList<TSyntaxNode>;
  mInside: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  mCache := TLocalsCache.Create(cSource, mTree);
  mNodes := TList<TSyntaxNode>.Create;
  try
    mAnonymous := FirstOf(mTree, TSyntaxKind.AnonymousMethod);
    mRoutine := FirstOf(mTree, TSyntaxKind.RoutineDecl);
    // Das X in Log(X) ist der Parameter der anonymen Methode, nicht die Variable der Routine.
    TRoutineLocals.CollectKind(mAnonymous, TSyntaxKind.Identifier, mNodes);
    mInside := nil;
    for mNode in mNodes do
    begin
      if mNode.Name = 'X' then
      begin
        mInside := mNode;
      end;
    end;
    Assert.IsNotNull(mInside);
    Assert.IsTrue(TRoutineParts.Shadowed(mCache, mInside, mRoutine, 'X', False));
    Assert.IsFalse(TRoutineParts.Shadowed(mCache, mInside, mRoutine, 'C', False));
    Assert.IsTrue(TRoutineParts.InAnonymous(mInside, mRoutine));
    Assert.IsTrue(mCache.Declares(mRoutine, 'Result', 0));
    Assert.IsFalse(mCache.Declares(mAnonymous, 'Result', 0));
  finally
    mNodes.Free;
    mCache.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRoutinePartsTests);

end.
