unit Atlas.Common.Configuration.JsonTree.Tests;

// Kommentare in atlas.json: Der Server überspringt sie mit TJsoncScanner aus
// Atlas.Text, wie das Plugin (ADR 0012); ein offener Blockkommentar ist hier
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
  Node: TJsonNode;
begin
  Node := TJsonTree.Parse('{ // a'#10'"x": /* b */ 1, }');
  try
    Assert.IsNotNull(Node);
  finally
    Node.Free;
  end;
end;

procedure TJsonTreeCommentTests.LineCommentEndsAtCr;
var
  Node: TJsonNode;
begin
  Node := TJsonTree.Parse('{ // a'#13'"x": 1 }');
  try
    Assert.IsNotNull(Node);
  finally
    Node.Free;
  end;
end;

procedure TJsonTreeCommentTests.OpenBlockCommentFailsAtItsStart;
var
  Offset: Integer;
begin
  Offset := -1;
  try
    TJsonTree.Parse('{ "x": 1 /* offen').Free;
  except
    on E: EJsonTreeError do
      Offset := E.Offset;
  end;
  Assert.AreEqual(9, Offset);
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonTreeCommentTests);

end.
