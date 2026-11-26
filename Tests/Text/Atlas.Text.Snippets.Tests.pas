unit Atlas.Text.Snippets.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextSnippetsTests = class
  public
    [Test]
    procedure EscapesSnippetCharacters;
    [Test]
    procedure LeavesOtherTextAlone;
  end;

implementation

uses
  Atlas.Text.Snippets;

procedure TTextSnippetsTests.EscapesSnippetCharacters;
begin
  Assert.AreEqual('a\$b\}c\\', TTextSnippets.Escape('a$b}c\'));
  Assert.AreEqual('\\\$', TTextSnippets.Escape('\$'));
end;

procedure TTextSnippetsTests.LeavesOtherTextAlone;
begin
  Assert.AreEqual('FCount := Wert(1) + #13;', TTextSnippets.Escape('FCount := Wert(1) + #13;'));
  Assert.AreEqual('', TTextSnippets.Escape(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextSnippetsTests);

end.
