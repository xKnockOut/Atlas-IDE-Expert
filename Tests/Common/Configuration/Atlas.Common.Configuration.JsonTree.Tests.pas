unit Atlas.Common.Configuration.JsonTree.Tests;

// Kommentare in atlas.json: Der Server überspringt sie mit TJsoncScanner aus
// Atlas.Text, wie das Plugin; ein offener Blockkommentar ist hier
// ein Fehler an der Stelle des "/*".

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonTreeCommentTests = class
  public
    [Test]
    procedure SkipsLineAndBlockComments;
    [Test]
    procedure LineCommentEndsAtCr;
    [Test]
    procedure OpenBlockCommentFailsAtItsStart;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Internals.JsonTree;

procedure TJsonTreeCommentTests.SkipsLineAndBlockComments;
var
  mNode: TJsonNode;
begin
  mNode := TJsonTree.Parse('{ // a'#10'"x": /* b */ 1, }');
  try
    Assert.IsNotNull(mNode);
  finally
    mNode.Free;
  end;
end;

procedure TJsonTreeCommentTests.LineCommentEndsAtCr;
var
  mNode: TJsonNode;
begin
  mNode := TJsonTree.Parse('{ // a'#13'"x": 1 }');
  try
    Assert.IsNotNull(mNode);
  finally
    mNode.Free;
  end;
end;

procedure TJsonTreeCommentTests.OpenBlockCommentFailsAtItsStart;
var
  mOffset: Integer;
begin
  mOffset := -1;
  try
    TJsonTree.Parse('{ "x": 1 /* offen').Free;
  except
    on E: EJsonTreeError do
      mOffset := E.Offset;
  end;
  Assert.AreEqual(9, mOffset);
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonTreeCommentTests);

end.
