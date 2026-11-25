unit Atlas.Common.Pascal.ObjectUses.Tests;

// Tests der Einordnung eines Objekt-Vorkommens (Atlas.Common.Pascal.ObjectUses): Freigabe, Lesen, Weitergabe als
// Argument samt Stelle, Zuweisung und Wege aus der Routine.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TObjectUsesTests = class
  public
    [Test]
    procedure ReleasesAreRelease;
    [Test]
    procedure MembersAreUse;
    [Test]
    procedure ReadingCallsAreMarkedArguments;
    [Test]
    procedure ArgumentKnowsCallAndPosition;
    [Test]
    procedure EscapesAndAssignments;
    [Test]
    procedure TypeCastIsSeenThrough;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.ObjectUses;

/// <summary>Einordnung des ersten Vorkommens von X in der Anweisung AStatement.</summary>
function UseOf(const AStatement: string; out AArgument: Integer; out ACallee: string): TObjectUseKind;
var
  mTree: TSyntaxTree;
  mUse: TObjectUse;
begin
  mTree := TSyntaxTreeCache.Parse('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  ' + AStatement + #10'end;'#10'end.');
  try
    mUse := TObjectUses.Classify(TSyntaxNode.IdentifierUses(mTree.Root, 'X')[0]);
    AArgument := mUse.Argument;
    ACallee := '';
    if mUse.Node <> nil then
    begin
      ACallee := mUse.Node.Name;
    end;
    Result := mUse.Kind;
  finally
    mTree.Free;
  end;
end;

function KindOf(const AStatement: string): TObjectUseKind;
var
  mArgument: Integer;
  mCallee: string;
begin
  Result := UseOf(AStatement, mArgument, mCallee);
end;

procedure TObjectUsesTests.ReleasesAreRelease;
begin
  Assert.AreEqual(Ord(TObjectUseKind.Release), Ord(KindOf('X.Free;')));
  Assert.AreEqual(Ord(TObjectUseKind.Release), Ord(KindOf('X.DisposeOf;')));
  Assert.AreEqual(Ord(TObjectUseKind.Release), Ord(KindOf('FreeAndNil(X);')));
  Assert.AreEqual(Ord(TObjectUseKind.Release), Ord(KindOf('ObjektFreigeben(X);')));
end;

procedure TObjectUsesTests.ReadingCallsAreMarkedArguments;
var
  mTree: TSyntaxTree;
  mUse: TObjectUse;
begin
  // Assign und AddStrings lesen dem Namen nach nur; ob das stimmt, entscheidet der Index beim Aufrufer.
  mTree := TSyntaxTreeCache.Parse('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  Ziel.Assign(X);'#10'  Weiter(X);'#10'end;'#10'end.');
  try
    mUse := TObjectUses.Classify(TSyntaxNode.IdentifierUses(mTree.Root, 'X')[0]);
    Assert.AreEqual(Ord(TObjectUseKind.Argument), Ord(mUse.Kind));
    Assert.IsTrue(mUse.Reading);
    mUse := TObjectUses.Classify(TSyntaxNode.IdentifierUses(mTree.Root, 'X')[1]);
    Assert.AreEqual(Ord(TObjectUseKind.Argument), Ord(mUse.Kind));
    Assert.IsFalse(mUse.Reading);
  finally
    mTree.Free;
  end;
end;

procedure TObjectUsesTests.MembersAreUse;
begin
  Assert.AreEqual(Ord(TObjectUseKind.Use), Ord(KindOf('X.Add(''a'');')));
  Assert.AreEqual(Ord(TObjectUseKind.Use), Ord(KindOf('if X.Count > 0 then Exit;')));
  Assert.AreEqual(Ord(TObjectUseKind.Use), Ord(KindOf('if X = nil then Exit;')));
end;

procedure TObjectUsesTests.ArgumentKnowsCallAndPosition;
var
  mArgument: Integer;
  mCallee: string;
begin
  Assert.AreEqual(Ord(TObjectUseKind.Argument), Ord(UseOf('StrBreakApart(''a,b'', '','', X);', mArgument,
    mCallee)));
  Assert.AreEqual(2, mArgument);
  Assert.AreEqual('StrBreakApart', mCallee);
  Assert.AreEqual(Ord(TObjectUseKind.Argument), Ord(UseOf('Fuellen((X));', mArgument, mCallee)));
  Assert.AreEqual(0, mArgument);
end;

procedure TObjectUsesTests.EscapesAndAssignments;
begin
  Assert.AreEqual(Ord(TObjectUseKind.Assigned), Ord(KindOf('X := nil;')));
  Assert.AreEqual(Ord(TObjectUseKind.Escape), Ord(KindOf('FListe := X;')));
  Assert.AreEqual(Ord(TObjectUseKind.Escape), Ord(KindOf('Exit(X);')));
  Assert.AreEqual(Ord(TObjectUseKind.Escape), Ord(KindOf('raise X;')));
  Assert.AreEqual(Ord(TObjectUseKind.Escape), Ord(KindOf('Schnitt := X as IInterface;')));
  Assert.AreEqual(Ord(TObjectUseKind.Escape), Ord(KindOf('X.Parent := Self;')));
  Assert.AreEqual(Ord(TObjectUseKind.Escape), Ord(KindOf('X.Start;')));
end;

procedure TObjectUsesTests.TypeCastIsSeenThrough;
var
  mArgument: Integer;
  mCallee: string;
begin
  Assert.AreEqual(Ord(TObjectUseKind.Use), Ord(KindOf('TStringList(X).Sort;')));
  Assert.AreEqual(Ord(TObjectUseKind.Argument), Ord(UseOf('Merken(1, TObject(X));', mArgument, mCallee)));
  Assert.AreEqual(1, mArgument);
  Assert.AreEqual('Merken', mCallee);
end;

end.
