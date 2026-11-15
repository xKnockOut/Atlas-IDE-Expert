unit Atlas.Core.Lsp.TextOffsets.Tests;

// Stellen im Editortext (Atlas.Core.Lsp.TextOffsets): Zeichenindex und UTF-8-Bytes zu Zeile und Zeichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextOffsetsTests = class
  public
    [Test]
    procedure CharOffsetCountsLines;
    [Test]
    procedure CharOffsetStopsAtLineEnd;
    [Test]
    procedure ByteOffsetCountsUtf8;
    [Test]
    procedure Utf8LengthOfUmlauts;
    [Test]
    procedure LineOfWithoutLineBreak;
  end;

implementation

uses
  Atlas.Core.Lsp.TextOffsets;

{ TTextOffsetsTests }

procedure TTextOffsetsTests.CharOffsetCountsLines;
begin
  Assert.AreEqual(0, TAtlasTextOffsets.CharOffset('ab'#13#10'cd', 0, 0));
  Assert.AreEqual(5, TAtlasTextOffsets.CharOffset('ab'#13#10'cd', 1, 1));
  Assert.AreEqual(4, TAtlasTextOffsets.CharOffset('ab'#10'cd'#10'ef', 1, 1));
end;

procedure TTextOffsetsTests.CharOffsetStopsAtLineEnd;
begin
  // Hinter dem Zeilenende das Zeilenende, #13 zählt nicht als Zeichen am Ende.
  Assert.AreEqual(2, TAtlasTextOffsets.CharOffset('ab'#13#10'cd', 0, 10));
  Assert.AreEqual(6, TAtlasTextOffsets.CharOffset('ab'#13#10'cd', 1, 10));
  // Hinter der letzten Zeile das Textende.
  Assert.AreEqual(5, TAtlasTextOffsets.CharOffset('ab'#10'cd', 5, 0));
end;

procedure TTextOffsetsTests.ByteOffsetCountsUtf8;
begin
  Assert.AreEqual(2, TAtlasTextOffsets.ByteOffset('ä'#10'x', 0, 1));
  Assert.AreEqual(3, TAtlasTextOffsets.ByteOffset('ä'#10'öx', 1, 0));
  Assert.AreEqual(5, TAtlasTextOffsets.ByteOffset('ä'#10'öx', 1, 1));
  Assert.AreEqual(3, TAtlasTextOffsets.BytesBefore('äbc', 2));
end;

procedure TTextOffsetsTests.Utf8LengthOfUmlauts;
begin
  Assert.AreEqual(0, TAtlasTextOffsets.Utf8Length(''));
  Assert.AreEqual(6, TAtlasTextOffsets.Utf8Length('Größ'));
  Assert.AreEqual(3, TAtlasTextOffsets.Utf8Length('abc'));
end;

procedure TTextOffsetsTests.LineOfWithoutLineBreak;
begin
  Assert.AreEqual('cd', TAtlasTextOffsets.LineOf('ab'#13#10'cd'#13#10, 1));
  Assert.AreEqual('ab', TAtlasTextOffsets.LineOf('ab'#13#10'cd', 0));
  Assert.AreEqual('', TAtlasTextOffsets.LineOf('ab', 1));
  Assert.AreEqual('', TAtlasTextOffsets.LineOf('ab', -1));
end;

end.
