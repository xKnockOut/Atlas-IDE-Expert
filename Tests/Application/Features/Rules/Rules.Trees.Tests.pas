unit Rules.Trees.Tests;

// Tests für den Helfer TRuleContextTree: Der Baum geht als Handle durch den Kontext und kommt unverändert zurück.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleContextTreeTests = class
  public
    [Test]
    procedure TreeComesBack;
    [Test]
    procedure WithoutTreeNoHandle;
    /// <summary>Kopien des Kontexts zeigen auf denselben Baum, auch über den Handle.</summary>
    [Test]
    procedure CopySharesTree;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Rules.Contract,
  Rules.Trees;

const
  cSource = 'unit U;'#10'interface'#10'implementation'#10'end.';

{ TRuleContextTreeTests }

procedure TRuleContextTreeTests.TreeComesBack;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
begin
  mTree := TSyntaxTreeCache.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Tree := mTree;
    Assert.AreSame(mTree, mContext.Tree);
    Assert.IsTrue(mContext.TreeHandle = TSyntaxTree.HandleOf(mTree));
    mContext := Default(TRuleContext);
  finally
    mTree.Free;
  end;
end;

procedure TRuleContextTreeTests.WithoutTreeNoHandle;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  Assert.IsNull(mContext.Tree);
  mContext.Tree := nil;
  Assert.IsNull(mContext.TreeHandle);
end;

procedure TRuleContextTreeTests.CopySharesTree;
var
  mTree: TSyntaxTree;
  mContext, mCopy: TRuleContext;
begin
  mTree := TSyntaxTreeCache.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Tree := mTree;
    mCopy := mContext;
    Assert.AreSame(mTree, mCopy.Tree);
    mCopy := Default(TRuleContext);
    mContext := Default(TRuleContext);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleContextTreeTests);

end.
