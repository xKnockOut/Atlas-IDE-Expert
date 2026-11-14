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
    [Test]
    procedure RemovesVariableSharingLine;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.ControlFlow.Signatures,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals;

const
  cSource =
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
  mLocal: TRoutineLocal;
begin
  Result := '';
  for mLocal in ALocals do
  begin
    Result := Result + mLocal.Name + ':' + IntToStr(Ord(mLocal.Kind)) + ' ';
  end;
end;

procedure TRoutineLocalsTests.CollectsAllKinds;
var
  mTree: TSyntaxTree;
  mLocals: TArray<TRoutineLocal>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mLocals := TRoutineLocals.Collect(cSource, mTree, TRoutineBody.RoutineAt(mTree, Pos('X := A', cSource)));
    // Parameter (0), Konstante (4), Variablen (1), Inline-Variable (2), Laufvariable (3).
    Assert.AreEqual('A:0 B:0 C:0 K:4 X:1 Y:1 Z:1 T:2 I:3 ', Kinds(mLocals));
    Assert.AreEqual('Integer', mLocals[1].TypeText);
    Assert.AreEqual('string', mLocals[2].TypeText);
  finally
    mTree.Free;
  end;
end;

procedure TRoutineLocalsTests.IndexOfHonorsScope;
var
  mTree: TSyntaxTree;
  mLocals: TArray<TRoutineLocal>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mLocals := TRoutineLocals.Collect(cSource, mTree, TRoutineBody.RoutineAt(mTree, Pos('X := A', cSource)));
    Assert.AreEqual(7, TRoutineLocals.IndexOf(mLocals, 't', Pos('Y := T', cSource)));
    // Hinter dem Block ist T nicht mehr sichtbar, I nur in der Schleife.
    Assert.AreEqual(-1, TRoutineLocals.IndexOf(mLocals, 'T', Pos('for var', cSource)));
    Assert.AreEqual(8, TRoutineLocals.IndexOf(mLocals, 'I', Pos('Inc(Z', cSource)));
    Assert.AreEqual(-1, TRoutineLocals.IndexOf(mLocals, 'I', Pos('C := C', cSource)));
    Assert.AreEqual(-1, TRoutineLocals.IndexOf(mLocals, 'IntToStr', Pos('C := C', cSource)));
  finally
    mTree.Free;
  end;
end;

procedure TRoutineLocalsTests.AccessOfDistinguishesWrites;
var
  mTree: TSyntaxTree;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mLookup: TFlowSignatureLookup;
  mText: string;
begin
  mTree := TPascalParser.Parse(cSource);
  mNodes := TList<TSyntaxNode>.Create;
  try
    mLookup := TFlowSignatures.FromTree(mTree.Root);
    TRoutineLocals.CollectKind(mTree.Root, TSyntaxKind.Identifier, mNodes);
    mText := '';
    for mNode in mNodes do
    begin
      if (mNode.StartPos.Line in [10, 16, 17]) and not SameText(mNode.Name, 'Inc') and
        not SameText(mNode.Name, 'IntToStr') then
      begin
        mText := mText + mNode.Name + ':' + IntToStr(Ord(TRoutineLocals.AccessOf(mNode, mLookup))) + ' ';
      end;
    end;
    // Lesen 0, Schreiben 1, beides 2 (Inc ändert sein erstes Argument).
    Assert.AreEqual('X:1 A:0 Z:2 I:0 C:1 C:0 X:0 ', mText);
    Assert.IsTrue(TRoutineLocals.HasKind(mTree.Root, TSyntaxKind.InlineVar));
    Assert.IsFalse(TRoutineLocals.HasKind(mTree.Root, TSyntaxKind.WithStatement));
  finally
    mNodes.Free;
    mTree.Free;
  end;
end;

procedure TRoutineLocalsTests.RemovesVariables;
var
  mTree: TSyntaxTree;
  mLocals: TArray<TRoutineLocal>;
  mEdits: TArray<TTextEdit>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mLocals := TRoutineLocals.Collect(cSource, mTree, TRoutineBody.RoutineAt(mTree, Pos('X := A', cSource)));
    // Ein Name aus einer Gruppe.
    mEdits := nil;
    TRoutineLocals.RemoveVariables(mTree, mLocals[4].Decl, ['X'], mEdits);
    Assert.AreEqual(StringReplace(cSource, '  X, Y: Integer;', '  Y: Integer;', []),
      TChangeSignature.ApplyEdits(cSource, mEdits));
    // Die ganze Zeile.
    mEdits := nil;
    TRoutineLocals.RemoveVariables(mTree, mLocals[6].Decl, ['Z'], mEdits);
    Assert.AreEqual(StringReplace(cSource, '  Z: Integer;'#10, '', []), TChangeSignature.ApplyEdits(cSource, mEdits));
    // Alle Einträge: auch "var".
    mEdits := nil;
    TRoutineLocals.RemoveVariables(mTree, mLocals[4].Decl, ['X', 'Y', 'Z'], mEdits);
    TRoutineLocals.RemoveVariables(mTree, mLocals[6].Decl, ['X', 'Y', 'Z'], mEdits);
    Assert.AreEqual(StringReplace(cSource, 'var'#10'  X, Y: Integer;'#10'  Z: Integer;'#10, '', []),
      TChangeSignature.ApplyEdits(cSource, mEdits));
  finally
    mTree.Free;
  end;
end;

procedure TRoutineLocalsTests.RemovesVariableSharingLine;
const
  cShared = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var X: Integer;'#10 +
    '  Y: Integer; Z: Integer;'#10'begin'#10'  Y := 1;'#10'  Z := Y;'#10'end;'#10'end.';
var
  mTree: TSyntaxTree;
  mLocals: TArray<TRoutineLocal>;
  mEdits: TArray<TTextEdit>;
begin
  // Steht "var" oder ein weiterer Eintrag auf der Zeile, fällt nur der Eintrag weg (#644).
  mTree := TPascalParser.Parse(cShared);
  try
    mLocals := TRoutineLocals.Collect(cShared, mTree, TRoutineBody.RoutineAt(mTree, Pos('Y := 1', cShared)));
    mEdits := nil;
    TRoutineLocals.RemoveVariables(mTree, mLocals[0].Decl, ['X'], mEdits);
    Assert.AreEqual(StringReplace(cShared, 'var X: Integer;', 'var ', []), TChangeSignature.ApplyEdits(cShared, mEdits));
    mEdits := nil;
    TRoutineLocals.RemoveVariables(mTree, mLocals[1].Decl, ['Y'], mEdits);
    Assert.AreEqual(StringReplace(cShared, 'Y: Integer; Z', 'Z', []), TChangeSignature.ApplyEdits(cShared, mEdits));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRoutineLocalsTests);

end.
