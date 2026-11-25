unit Atlas.Common.Pascal.TreeHandles.Tests;

// Tests für TSyntaxTreeHandles: Wrap und TreeOf liefern denselben Baum, ohne Baum kein Handle, fremde Handles
// geben keinen Baum her.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSyntaxTreeHandlesTests = class
  public
    [Test]
    procedure TreeComesBack;
    [Test]
    procedure NoTreeNoHandle;
    [Test]
    procedure ForeignHandleHasNoTree;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.TreeHandles;

type
  /// <summary>Handle, den nicht Pascal angelegt hat.</summary>
  TForeignHandle = class(TInterfacedObject, IPascalSyntaxTree);

{ TSyntaxTreeHandlesTests }

procedure TSyntaxTreeHandlesTests.TreeComesBack;
var
  mTree: TSyntaxTree;
  mHandle: IPascalSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse('unit U;'#10'interface'#10'implementation'#10'end.');
  try
    mHandle := TSyntaxTreeHandles.Wrap(mTree);
    Assert.AreSame(mTree, TSyntaxTreeHandles.TreeOf(mHandle));
    mHandle := nil;
  finally
    mTree.Free;
  end;
end;

procedure TSyntaxTreeHandlesTests.NoTreeNoHandle;
begin
  Assert.IsNull(TSyntaxTreeHandles.Wrap(nil));
  Assert.IsNull(TSyntaxTreeHandles.TreeOf(nil));
end;

procedure TSyntaxTreeHandlesTests.ForeignHandleHasNoTree;
var
  mHandle: IPascalSyntaxTree;
begin
  mHandle := TForeignHandle.Create;
  Assert.IsNull(TSyntaxTreeHandles.TreeOf(mHandle));
end;

initialization
  TDUnitX.RegisterTestFixture(TSyntaxTreeHandlesTests);

end.
