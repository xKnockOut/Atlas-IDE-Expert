unit Atlas.Common.Rules.Builtin.Ownership.TokenScan.Tests;

// Tests der gemeinsamen Grundlage der Besitz-Regeln: Code-Tokens ohne Kommentare, Klammern, generische Argumente,
// Text zwischen Tokens, Knoten und Anweisungen an einer Stelle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOwnershipTokenScanTests = class
  public
    [Test]
    procedure SkipsCommentsAndFindsTokens;
    [Test]
    procedure ClosingAndGenericArguments;
    [Test]
    procedure StatementAndNodeAtOffset;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Ownership.TokenScan;

type
  /// <summary>Macht die geschützten Helfer für die Tests zugänglich.</summary>
  TProbeScan = class(TOwnershipTokenScan)
  end;

const
  cText = 'unit U;'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  { Kommentar } L := TList<TObject>.Create(A[1], (B));'#10 + '  L.Free;'#10'end;'#10'end.';

function ContextOf(ATree: TSyntaxTree): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.Text := cText;
  Result.Tree := ATree;
end;

procedure TOwnershipTokenScanTests.SkipsCommentsAndFindsTokens;
var
  mTree: TSyntaxTree;
  mScan: TProbeScan;
  mPosition: Integer;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mScan := TProbeScan.Create(ContextOf(mTree), nil);
    try
      mPosition := mScan.CodeAt(Pos('{', cText) - 1);
      Assert.IsTrue(mScan.IsName(mPosition, 'l'), 'Kommentar zählt nicht als Code');
      Assert.IsTrue(mScan.IsSym(mPosition + 1, ':='));
      Assert.IsTrue(mScan.IsWord(mPosition + 2));
      Assert.IsFalse(mScan.IsWord(-1));
      Assert.IsTrue(mScan.IsKey(mScan.CodeAt(Pos('begin', cText) - 1), 'begin'));
      Assert.AreEqual('L := TList', mScan.TextBetween(mPosition, mPosition + 2));
    finally
      mScan.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TOwnershipTokenScanTests.ClosingAndGenericArguments;
var
  mTree: TSyntaxTree;
  mScan: TProbeScan;
  mGeneric, mAfter, mOpen, mClose: Integer;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mScan := TProbeScan.Create(ContextOf(mTree), nil);
    try
      mGeneric := mScan.CodeAt(Pos('<', cText) - 1);
      mAfter := mScan.SkipGenericArgs(mGeneric);
      Assert.IsTrue(mScan.IsSym(mAfter, '.'), 'hinter <TObject> folgt der Punkt');
      Assert.AreEqual(mGeneric + 1, mScan.SkipGenericArgs(mGeneric + 1), 'ohne < bleibt die Stelle');
      mOpen := mAfter + 2;
      Assert.IsTrue(mScan.IsSym(mOpen, '('));
      mClose := mScan.Closing(mOpen);
      Assert.IsTrue(mScan.IsSym(mClose, ')'));
      Assert.IsTrue(mScan.IsSym(mClose + 1, ';'), 'innere Klammern zählen mit');
    finally
      mScan.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TOwnershipTokenScanTests.StatementAndNodeAtOffset;
var
  mTree: TSyntaxTree;
  mBlock, mStatement: TSyntaxNode;
  mOffset: Integer;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mOffset := Pos('L.Free', cText) - 1;
    mBlock := mTree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Descend;
        if ANode.Kind = TSyntaxKind.Block then
        begin
          Result := TSyntaxSearchStep.Found;
        end;
      end);
    Assert.IsNotNull(mBlock);
    Assert.IsTrue(TProbeScan.InBlock(mBlock, mOffset));
    Assert.IsFalse(TProbeScan.InBlock(mBlock, 0));
    mStatement := TProbeScan.TopStatement(mBlock, mOffset);
    Assert.IsNotNull(mStatement);
    Assert.AreSame(mBlock[1], mStatement, 'zweite Anweisung');
    Assert.IsNull(TProbeScan.TopStatement(mBlock, 0));
    Assert.IsTrue(TProbeScan.InBlock(TProbeScan.NodeAt(mTree.Root, mOffset), mOffset));
    Assert.IsTrue(TProbeScan.NodeAt(mTree.Root, mOffset).ChildCount = 0, 'tiefster Knoten');
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TOwnershipTokenScanTests);

end.
