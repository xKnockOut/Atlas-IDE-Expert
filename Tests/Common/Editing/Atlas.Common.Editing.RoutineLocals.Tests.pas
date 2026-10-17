unit Atlas.Common.Editing.RoutineLocals.Tests;

// Tests für die lokalen Namen einer Routine (#50, #103): Sammeln samt
// gruppierter Parameter, Gültigkeitsbereich von Inline-Variablen, Zugriff
// eines Bezeichners und Entfernen aus dem var-Abschnitt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRoutineLocalsTests = class
  public
    [Test]
    procedure CollectsAllKinds;
    [Test]
    procedure IndexOfHonorsScope;
    [Test]
    procedure AccessOfDistinguishesWrites;
    [Test]
    procedure RemovesVariables;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals;

const
  Source =
    'unit U;'#10 +                                     // 0
    'interface'#10 +                                   // 1
    'implementation'#10 +                              // 2
    'procedure P(A, B: Integer; var C: string);'#10 +  // 3
    'const'#10 +                                       // 4
    '  K = 1;'#10 +                                    // 5
    'var'#10 +                                         // 6
    '  X, Y: Integer;'#10 +                            // 7
    '  Z: Integer;'#10 +                               // 8
    'begin'#10 +                                       // 9
    '  X := A;'#10 +                                   // 10
    '  begin'#10 +                                     // 11
    '    var T := B;'#10 +                             // 12
    '    Y := T;'#10 +                                 // 13
    '  end;'#10 +                                      // 14
    '  for var I := 1 to K do'#10 +                    // 15
    '    Inc(Z, I);'#10 +                              // 16
    '  C := C + IntToStr(X);'#10 +                     // 17
    'end;'#10 +                                        // 18
    'end.'#10;

function Kinds(const ALocals: TArray<TRoutineLocal>): string;
var
  Local: TRoutineLocal;
begin
  Result := '';
  for Local in ALocals do
    Result := Result + Local.Name + ':' + IntToStr(Ord(Local.Kind)) + ' ';
end;

procedure TRoutineLocalsTests.CollectsAllKinds;
var
  Tree: TSyntaxTree;
  Locals: TArray<TRoutineLocal>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Locals := TRoutineLocals.Collect(Source, Tree, TRoutineBody.RoutineAt(Tree, Pos('X := A', Source)));
    // Parameter (0), Konstante (4), Variablen (1), Inline-Variable (2), Laufvariable (3).
    Assert.AreEqual('A:0 B:0 C:0 K:4 X:1 Y:1 Z:1 T:2 I:3 ', Kinds(Locals));
    Assert.AreEqual('Integer', Locals[1].TypeText);
    Assert.AreEqual('string', Locals[2].TypeText);
  finally
    Tree.Free;
  end;
end;

procedure TRoutineLocalsTests.IndexOfHonorsScope;
var
  Tree: TSyntaxTree;
  Locals: TArray<TRoutineLocal>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Locals := TRoutineLocals.Collect(Source, Tree, TRoutineBody.RoutineAt(Tree, Pos('X := A', Source)));
    Assert.AreEqual(7, TRoutineLocals.IndexOf(Locals, 't', Pos('Y := T', Source)));
    // Hinter dem Block ist T nicht mehr sichtbar, I nur in der Schleife.
    Assert.AreEqual(-1, TRoutineLocals.IndexOf(Locals, 'T', Pos('for var', Source)));
    Assert.AreEqual(8, TRoutineLocals.IndexOf(Locals, 'I', Pos('Inc(Z', Source)));
    Assert.AreEqual(-1, TRoutineLocals.IndexOf(Locals, 'I', Pos('C := C', Source)));
    Assert.AreEqual(-1, TRoutineLocals.IndexOf(Locals, 'IntToStr', Pos('C := C', Source)));
  finally
    Tree.Free;
  end;
end;

procedure TRoutineLocalsTests.AccessOfDistinguishesWrites;
var
  Tree: TSyntaxTree;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Lookup: TFlowSignatureLookup;
  Text: string;
begin
  Tree := TPascalParser.Parse(Source);
  Nodes := TList<TSyntaxNode>.Create;
  try
    Lookup := TFlowSignatures.FromTree(Tree.Root);
    TRoutineLocals.CollectKind(Tree.Root, TSyntaxKind.Identifier, Nodes);
    Text := '';
    for Node in Nodes do
      if (Node.StartPos.Line in [10, 16, 17]) and not SameText(Node.Name, 'Inc') and
        not SameText(Node.Name, 'IntToStr') then
        Text := Text + Node.Name + ':' + IntToStr(Ord(TRoutineLocals.AccessOf(Node, Lookup))) + ' ';
    // Lesen 0, Schreiben 1, beides 2 (Inc ändert sein erstes Argument).
    Assert.AreEqual('X:1 A:0 Z:2 I:0 C:1 C:0 X:0 ', Text);
    Assert.IsTrue(TRoutineLocals.HasKind(Tree.Root, TSyntaxKind.InlineVar));
    Assert.IsFalse(TRoutineLocals.HasKind(Tree.Root, TSyntaxKind.WithStatement));
  finally
    Nodes.Free;
    Tree.Free;
  end;
end;

procedure TRoutineLocalsTests.RemovesVariables;
var
  Tree: TSyntaxTree;
  Locals: TArray<TRoutineLocal>;
  Edits: TArray<TTextEdit>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Locals := TRoutineLocals.Collect(Source, Tree, TRoutineBody.RoutineAt(Tree, Pos('X := A', Source)));
    // Ein Name aus einer Gruppe.
    Edits := nil;
    TRoutineLocals.RemoveVariables(Source, Tree, Locals[4].Decl, ['X'], Edits);
    Assert.AreEqual(StringReplace(Source, '  X, Y: Integer;', '  Y: Integer;', []),
      TChangeSignature.ApplyEdits(Source, Edits));
    // Die ganze Zeile.
    Edits := nil;
    TRoutineLocals.RemoveVariables(Source, Tree, Locals[6].Decl, ['Z'], Edits);
    Assert.AreEqual(StringReplace(Source, '  Z: Integer;'#10, '', []), TChangeSignature.ApplyEdits(Source, Edits));
    // Alle Einträge: auch "var".
    Edits := nil;
    TRoutineLocals.RemoveVariables(Source, Tree, Locals[4].Decl, ['X', 'Y', 'Z'], Edits);
    TRoutineLocals.RemoveVariables(Source, Tree, Locals[6].Decl, ['X', 'Y', 'Z'], Edits);
    Assert.AreEqual(StringReplace(Source, 'var'#10'  X, Y: Integer;'#10'  Z: Integer;'#10, '', []),
      TChangeSignature.ApplyEdits(Source, Edits));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRoutineLocalsTests);

end.
