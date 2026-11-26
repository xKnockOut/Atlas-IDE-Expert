unit Atlas.Common.Completion.SymbolKinds.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionSymbolKindsTests = class
  public
    [Test]
    procedure TypesAndMembers;
    [Test]
    procedure VariablesByDefault;
  end;

implementation

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.SymbolKinds;

procedure TCompletionSymbolKindsTests.TypesAndMembers;
begin
  Assert.AreEqual(cKindClass, CompletionKindOf(TIndexSymbolKind.ClassType));
  Assert.AreEqual(cKindClass, CompletionKindOf(TIndexSymbolKind.TypeAlias));
  Assert.AreEqual(cKindStruct, CompletionKindOf(TIndexSymbolKind.RecordType));
  Assert.AreEqual(cKindInterface, CompletionKindOf(TIndexSymbolKind.InterfaceType));
  Assert.AreEqual(cKindField, CompletionKindOf(TIndexSymbolKind.Field));
  Assert.AreEqual(cKindMethod, CompletionKindOf(TIndexSymbolKind.Method));
  Assert.AreEqual(cKindConstructor, CompletionKindOf(TIndexSymbolKind.Constructor_));
  Assert.AreEqual(cKindFunction, CompletionKindOf(TIndexSymbolKind.Routine));
end;

procedure TCompletionSymbolKindsTests.VariablesByDefault;
begin
  Assert.AreEqual(cKindVariable, CompletionKindOf(TIndexSymbolKind.Variable));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionSymbolKindsTests);

end.
