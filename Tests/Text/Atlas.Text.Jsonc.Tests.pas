unit Atlas.Text.Jsonc.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsoncScannerTests = class
  public
    [Test]
    procedure SkipsSpaceAndComments;
    [Test]
    procedure LineCommentEndsAtCr;
    [Test]
    procedure OpenBlockCommentReturnsFalse;
    [Test]
    procedure StripCommentsKeepsStrings;
    [Test]
    procedure StripCommentsKeepsLineBreaks;
    [Test]
    procedure StripTrailingComma;
  end;

implementation

uses
  Atlas.Text.Jsonc;

procedure TJsoncScannerTests.SkipsSpaceAndComments;
var
  Position: Integer;
begin
  Position := 1;
  Assert.IsTrue(TJsoncScanner.SkipSpace('  // a'#10' /* b */ x', Position));
  Assert.AreEqual<Integer>(17, Position);
end;

procedure TJsoncScannerTests.LineCommentEndsAtCr;
var
  Position: Integer;
begin
  Position := 1;
  Assert.IsTrue(TJsoncScanner.SkipSpace('// a'#13'x', Position));
  Assert.AreEqual<Integer>(6, Position);
end;

procedure TJsoncScannerTests.OpenBlockCommentReturnsFalse;
var
  Position, OpenComment: Integer;
begin
  Position := 1;
  Assert.IsFalse(TJsoncScanner.SkipSpace(' /* a */ /* offen', Position, OpenComment));
  Assert.AreEqual<Integer>(10, OpenComment);
  Assert.AreEqual<Integer>(18, Position);
  Position := 1;
  Assert.IsTrue(TJsoncScanner.SkipSpace('x', Position, OpenComment));
  Assert.AreEqual<Integer>(0, OpenComment);
end;

procedure TJsoncScannerTests.StripCommentsKeepsStrings;
begin
  Assert.AreEqual('{"a": "http://x /* y */", "b": 1     }',
    TJsoncScanner.StripComments('{"a": "http://x /* y */", "b": 1 /**/}'));
  Assert.AreEqual('{"a\"//": 1}', TJsoncScanner.StripComments('{"a\"//": 1}'));
end;

procedure TJsoncScannerTests.StripCommentsKeepsLineBreaks;
begin
  Assert.AreEqual('{    '#13#10'  "a": 1     '#13#10'  }',
    TJsoncScanner.StripComments('{ //x'#13#10'  "a": 1 /* y'#13#10'*/}'));
  // Ein offener Blockkommentar reicht bis zum Textende.
  Assert.AreEqual('{     ', TJsoncScanner.StripComments('{ /* x'));
end;

procedure TJsoncScannerTests.StripTrailingComma;
begin
  Assert.AreEqual('{"a": [1, 2 ] }', TJsoncScanner.StripComments('{"a": [1, 2,] }'));
  Assert.AreEqual('{"a": 1       }', TJsoncScanner.StripComments('{"a": 1, /*x*/}'));
end;

initialization
  TDUnitX.RegisterTestFixture(TJsoncScannerTests);

end.
