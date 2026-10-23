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
  Source =
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
  Nodes: TList<TSyntaxNode>;
begin
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ATree.Root, AKind, Nodes);
    Assert.IsTrue(Nodes.Count > 0);
    Result := Nodes[0];
  finally
    Nodes.Free;
  end;
end;

procedure TRoutinePartsTests.ParametersAndHeads;
var
  Tree: TSyntaxTree;
  Routine: TSyntaxNode;
  Parameters: TArray<TParameterText>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Routine := FirstOf(Tree, TSyntaxKind.RoutineDecl);
    Parameters := TRoutineParts.ParameterTexts(Source, TRoutineParts.HeaderOf(Routine));
    Assert.AreEqual(3, Integer(Length(Parameters)));
    Assert.AreEqual('const A: Integer', Parameters[0].Text);
    Assert.AreEqual('B', Parameters[1].Name);
    Assert.AreEqual('var', Parameters[2].Modifier);
    Assert.AreEqual('function Neu(const A: Integer; const B: Integer; var C: string): Integer;',
      TRoutineParts.HeadText(Source, TRoutineParts.HeaderOf(Routine), 'Neu', Parameters, False));
    Assert.AreEqual('class function Neu: Integer;', TRoutineParts.HeadText(Source, TRoutineParts.HeaderOf(Routine),
      'Neu', nil, True));
    Assert.IsTrue(TRoutineParts.IsFunction(Routine));
  finally
    Tree.Free;
  end;
end;

procedure TRoutinePartsTests.AnonymousHeadAndFunction;
var
  Tree: TSyntaxTree;
  Anonymous: TSyntaxNode;
  Parameters: TArray<TParameterText>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Anonymous := FirstOf(Tree, TSyntaxKind.AnonymousMethod);
    Assert.IsFalse(TRoutineParts.IsFunction(Anonymous));
    Parameters := TRoutineParts.ParameterTexts(Source, Anonymous);
    Assert.AreEqual(1, Integer(Length(Parameters)));
    Assert.AreEqual('procedure(const X: Integer)', TRoutineParts.AnonymousHead(Source, Anonymous, Parameters));
    Assert.AreEqual('procedure Name(const X: Integer);', TRoutineParts.HeadText(Source, Anonymous, 'Name',
      Parameters, False));
    Assert.AreEqual('function(const A: Integer; const B: Integer; var C: string): Integer',
      TRoutineParts.AnonymousHead(Source, TRoutineParts.HeaderOf(FirstOf(Tree, TSyntaxKind.RoutineDecl)),
      TRoutineParts.ParameterTexts(Source, TRoutineParts.HeaderOf(FirstOf(Tree, TSyntaxKind.RoutineDecl)))));
  finally
    Tree.Free;
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
  Tree: TSyntaxTree;
  Anonymous, Routine, Node: TSyntaxNode;
  Cache: TLocalsCache;
  Nodes: TList<TSyntaxNode>;
  Inside: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Source);
  Cache := TLocalsCache.Create(Source, Tree);
  Nodes := TList<TSyntaxNode>.Create;
  try
    Anonymous := FirstOf(Tree, TSyntaxKind.AnonymousMethod);
    Routine := FirstOf(Tree, TSyntaxKind.RoutineDecl);
    // Das X in Log(X) ist der Parameter der anonymen Methode, nicht die Variable der Routine.
    TRoutineLocals.CollectKind(Anonymous, TSyntaxKind.Identifier, Nodes);
    Inside := nil;
    for Node in Nodes do
      if Node.Name = 'X' then
        Inside := Node;
    Assert.IsNotNull(Inside);
    Assert.IsTrue(TRoutineParts.Shadowed(Cache, Inside, Routine, 'X', False));
    Assert.IsFalse(TRoutineParts.Shadowed(Cache, Inside, Routine, 'C', False));
    Assert.IsTrue(TRoutineParts.InAnonymous(Inside, Routine));
    Assert.IsTrue(Cache.Declares(Routine, 'Result', 0));
    Assert.IsFalse(Cache.Declares(Anonymous, 'Result', 0));
  finally
    Nodes.Free;
    Cache.Free;
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRoutinePartsTests);

end.
