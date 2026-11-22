unit Atlas.Common.Documents.TextChanges.Tests;

// Tests für das Anwenden von Edits auf einen Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextChangesTests = class
  public
    [Test]
    procedure AppliesEdits;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.TextChanges;

procedure TTextChangesTests.AppliesEdits;
begin
  Assert.AreEqual('ab XY cd', TTextChanges.Apply('ab cd', [
    TTextEdit.Create(TTextRange.Create(0, 2, 0, 2), ' XY'),
    TTextEdit.Create(TTextRange.Create(0, 0, 0, 0), '')]));
  Assert.AreEqual('a'#10'Z', TTextChanges.Apply('a'#10'b', [TTextEdit.Create(TTextRange.Create(1, 0, 1, 1),
    'Z')]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextChangesTests);

end.
