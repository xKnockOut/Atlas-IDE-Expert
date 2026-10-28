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
    [Test]
    procedure SyntaxErrorAcceptsValidJsonc;
    [Test]
    procedure SyntaxErrorFindsFirstBadPlace;
    [Test]
    procedure LineColumnCountsLineBreaks;
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

procedure TJsoncScannerTests.SyntaxErrorAcceptsValidJsonc;
begin
  Assert.AreEqual<Integer>(0, TJsoncScanner.SyntaxError('{"a": 1, "b": [true, false, null, -1.5e3, "x\"y"], "c": {}}'));
  Assert.AreEqual<Integer>(0, TJsoncScanner.SyntaxError('{'#13#10'  // k'#13#10'  "a": 1, /* x */'#13#10'}'),
    'Kommentare und Schlusskomma');
  Assert.AreEqual<Integer>(0, TJsoncScanner.SyntaxError(' [] '));
end;

procedure TJsoncScannerTests.SyntaxErrorFindsFirstBadPlace;
begin
  Assert.AreEqual<Integer>(22, TJsoncScanner.SyntaxError('{'#13#10'  "version": 1'#13#10'  "tracker": {}'#13#10'}'),
    'fehlendes Komma: am nächsten Schlüssel');
  Assert.AreEqual<Integer>(11, TJsoncScanner.SyntaxError('{"a": 1}'#13#10'"b": {}'), 'Text nach der Klammer');
  Assert.AreEqual<Integer>(10, TJsoncScanner.SyntaxError('"tracker": {}'), 'ohne äußere Klammern');
  Assert.AreEqual<Integer>(12, TJsoncScanner.SyntaxError('{'#10'  "a": "b'#10'}'), 'String nicht geschlossen');
  Assert.AreEqual<Integer>(8, TJsoncScanner.SyntaxError('{"a": 1'), 'Ende vor der Klammer');
  Assert.AreEqual<Integer>(7, TJsoncScanner.SyntaxError('{"a": tru}'), 'Literal');
  Assert.AreEqual<Integer>(2, TJsoncScanner.SyntaxError('{a: 1}'), 'Schlüssel ohne Anführungszeichen');
  Assert.AreEqual<Integer>(1, TJsoncScanner.SyntaxError(''), 'leer');
end;

procedure TJsoncScannerTests.LineColumnCountsLineBreaks;
var
  Line, Column: Integer;
begin
  TJsoncScanner.LineColumn('{'#13#10'  "version": 1'#13#10'  "tracker": {}'#13#10'}', 22, Line, Column);
  Assert.AreEqual<Integer>(3, Line, 'CRLF');
  Assert.AreEqual<Integer>(3, Column);
  TJsoncScanner.LineColumn('a'#10'b'#13'cd', 6, Line, Column);
  Assert.AreEqual<Integer>(3, Line, 'LF und CR');
  Assert.AreEqual<Integer>(2, Column);
  TJsoncScanner.LineColumn('abc', 2, Line, Column);
  Assert.AreEqual<Integer>(1, Line);
  Assert.AreEqual<Integer>(2, Column);
end;

initialization
  TDUnitX.RegisterTestFixture(TJsoncScannerTests);

end.
