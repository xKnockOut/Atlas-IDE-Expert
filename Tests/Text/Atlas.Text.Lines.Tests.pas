unit Atlas.Text.Lines.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextLinesTests = class
  public
    [Test]
    procedure LineBreakOfPrefersCrlf;
    [Test]
    procedure KindOfMixed;
    [Test]
    procedure DominantOfPrefersGivenOnTie;
    [Test]
    procedure SplitLinesCrLfCr;
    [Test]
    procedure SplitLinesTrailingBreakGivesEmptyLine;
    [Test]
    procedure SplitLinesEmptyGivesOneLine;
    [Test]
    procedure SplitLinesReturnsLineBreak;
    [Test]
    procedure SplitKeepingBreaksKeepsEnds;
    /// <summary>Charakterisierung der RTL (D-03): TStringHelper.Split verwirft ein leeres letztes Element
    /// und liefert für '' ein leeres Array. SplitLines tut beides nicht.</summary>
    [Test]
    procedure SplitHelperDropsTrailingEmpty;
    [Test]
    procedure IndentOfSpacesTabs;
    [Test]
    procedure IndentOfWhitespaceOnly;
    [Test]
    procedure IndentOfLineOfText;
    [Test]
    procedure JoinLines;
    [Test]
    procedure StripTrailingCr;
    [Test]
    procedure NormalizeLineBreaks;
  end;

  [TestFixture]
  TLineTableTests = class
  public
    [Test]
    procedure PositionAtCrlf;
    [Test]
    procedure PositionAtInsideCrlfStaysOnLine;
    [Test]
    procedure PositionAtClampsBeyondEnd;
    [Test]
    procedure OffsetAtClampsToLineEnd;
    [Test]
    procedure OffsetAtLineBeyondEnd;
    [Test]
    procedure RoundTripAllOffsets;
    [Test]
    procedure LineStartsAndEnds;
  end;

implementation

uses
  Atlas.Text.Lines;

{ TTextLinesTests }

procedure TTextLinesTests.LineBreakOfPrefersCrlf;
begin
  Assert.AreEqual(#13#10, TTextLines.LineBreakOf('a'#10'b'#13#10'c'));
  Assert.AreEqual(#10, TTextLines.LineBreakOf('a'#10'b'));
  Assert.AreEqual(#10, TTextLines.LineBreakOf('a'#13'b'));
  Assert.AreEqual(#10, TTextLines.LineBreakOf(''));
end;

procedure TTextLinesTests.KindOfMixed;
begin
  Assert.IsTrue(TTextLines.KindOf('abc') = TTextLineBreak.None);
  Assert.IsTrue(TTextLines.KindOf('a'#13#10'b'#13#10) = TTextLineBreak.CRLF);
  Assert.IsTrue(TTextLines.KindOf('a'#10'b') = TTextLineBreak.LF);
  Assert.IsTrue(TTextLines.KindOf('a'#13'b') = TTextLineBreak.CR);
  Assert.IsTrue(TTextLines.KindOf('a'#13#10'b'#10) = TTextLineBreak.Mixed);
end;

procedure TTextLinesTests.DominantOfPrefersGivenOnTie;
var
  Mixed: Boolean;
begin
  Assert.IsTrue(TTextLines.DominantOf('a'#10'b'#13#10'c'#10, Mixed) = TTextLineBreak.LF);
  Assert.IsTrue(Mixed);
  Assert.IsTrue(TTextLines.DominantOf('a'#10'b'#13#10, Mixed) = TTextLineBreak.CRLF);
  Assert.IsTrue(TTextLines.DominantOf('a'#10'b'#13#10, TTextLineBreak.LF, Mixed) = TTextLineBreak.LF);
  Assert.IsTrue(TTextLines.DominantOf('a'#13#10'b', TTextLineBreak.LF, Mixed) = TTextLineBreak.CRLF);
  Assert.IsFalse(Mixed);
  Assert.IsTrue(TTextLines.DominantOf('abc', Mixed) = TTextLineBreak.None);
  Assert.IsFalse(Mixed);
end;

procedure TTextLinesTests.SplitLinesCrLfCr;
var
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitLines('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual<Integer>(4, Length(Lines));
  Assert.AreEqual('a', Lines[0]);
  Assert.AreEqual('b', Lines[1]);
  Assert.AreEqual('c', Lines[2]);
  Assert.AreEqual('d', Lines[3]);
end;

procedure TTextLinesTests.SplitLinesTrailingBreakGivesEmptyLine;
var
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitLines('a'#13#10);
  Assert.AreEqual<Integer>(2, Length(Lines));
  Assert.AreEqual('a', Lines[0]);
  Assert.AreEqual('', Lines[1]);
end;

procedure TTextLinesTests.SplitLinesEmptyGivesOneLine;
var
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitLines('');
  Assert.AreEqual<Integer>(1, Length(Lines));
  Assert.AreEqual('', Lines[0]);
end;

procedure TTextLinesTests.SplitLinesReturnsLineBreak;
var
  Lines: TArray<string>;
  LineBreak: string;
begin
  Lines := TTextLines.SplitLines('a'#13#10'b'#10'c', LineBreak);
  Assert.AreEqual(#13#10, LineBreak);
  Assert.AreEqual<Integer>(3, Length(Lines));
  Assert.AreEqual('c', Lines[2]);
end;

procedure TTextLinesTests.SplitKeepingBreaksKeepsEnds;
var
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitKeepingBreaks('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual<Integer>(4, Length(Lines));
  Assert.AreEqual('a'#13#10, Lines[0]);
  Assert.AreEqual('b'#10, Lines[1]);
  Assert.AreEqual('c'#13, Lines[2]);
  Assert.AreEqual('d', Lines[3]);
  Lines := TTextLines.SplitKeepingBreaks('a'#10);
  Assert.AreEqual<Integer>(1, Length(Lines));
  Assert.AreEqual('a'#10, Lines[0]);
  Assert.AreEqual<Integer>(0, Length(TTextLines.SplitKeepingBreaks('')));
end;

procedure TTextLinesTests.SplitHelperDropsTrailingEmpty;
var
  Text: string;
begin
  Text := 'a'#10;
  Assert.AreEqual<Integer>(1, Length(Text.Split([#10])), 'Split verwirft die leere letzte Zeile');
  Text := '';
  Assert.AreEqual<Integer>(0, Length(Text.Split([#10])), 'Split liefert für leeren Text nichts');
  Assert.AreEqual<Integer>(2, Length(TTextLines.SplitLines('a'#10)));
  Assert.AreEqual<Integer>(1, Length(TTextLines.SplitLines('')));
end;

procedure TTextLinesTests.IndentOfSpacesTabs;
begin
  Assert.AreEqual('  '#9' ', TTextLines.IndentOf('  '#9' x := 1;'));
  Assert.AreEqual<Integer>(4, TTextLines.IndentLength('  '#9' x := 1;'));
  Assert.AreEqual('', TTextLines.IndentOf('x'));
end;

procedure TTextLinesTests.IndentOfWhitespaceOnly;
begin
  Assert.AreEqual('   ', TTextLines.IndentOf('   '));
  Assert.AreEqual<Integer>(3, TTextLines.IndentLength('   '));
  Assert.AreEqual('', TTextLines.IndentOf(''));
end;

procedure TTextLinesTests.IndentOfLineOfText;
const
  Text = 'begin'#13#10'    x := 1;'#13'  y'#10'z';
begin
  Assert.AreEqual('', TTextLines.IndentOf(Text, 0));
  Assert.AreEqual('    ', TTextLines.IndentOf(Text, 1));
  Assert.AreEqual('  ', TTextLines.IndentOf(Text, 2));
  Assert.AreEqual('', TTextLines.IndentOf(Text, 3));
  Assert.AreEqual('', TTextLines.IndentOf(Text, 4));
  Assert.AreEqual('', TTextLines.IndentOf(Text, -1));
end;

procedure TTextLinesTests.JoinLines;
begin
  Assert.AreEqual('a'#13#10'b'#13#10'c', TTextLines.JoinLines(['a', 'b', 'c'], #13#10));
  Assert.AreEqual('', TTextLines.JoinLines([], #10));
end;

procedure TTextLinesTests.StripTrailingCr;
begin
  Assert.AreEqual('a', TTextLines.StripTrailingCr('a'#13));
  Assert.AreEqual('a', TTextLines.StripTrailingCr('a'));
  Assert.AreEqual('', TTextLines.StripTrailingCr(''));
end;

procedure TTextLinesTests.NormalizeLineBreaks;
begin
  Assert.AreEqual('a'#13#10'b'#13#10'c'#13#10, TTextLines.NormalizeLineBreaks('a'#10'b'#13'c'#13#10, #13#10));
  Assert.AreEqual('a'#10'b', TTextLines.NormalizeLineBreaks('a'#13#10'b', #10));
end;

{ TLineTableTests }

procedure TLineTableTests.PositionAtCrlf;
var
  Table: TLineTable;
begin
  Table := TLineTable.Build('ab'#13#10'cd'#10'e');
  Assert.AreEqual<Integer>(3, Table.LineCount);
  Assert.IsTrue(Table.PositionAt(0) = TTextPosition.Create(0, 0));
  Assert.IsTrue(Table.PositionAt(4) = TTextPosition.Create(1, 0));
  Assert.IsTrue(Table.PositionAt(6) = TTextPosition.Create(1, 2));
  Assert.IsTrue(Table.PositionAt(7) = TTextPosition.Create(2, 0));
end;

procedure TLineTableTests.PositionAtInsideCrlfStaysOnLine;
var
  Table: TLineTable;
begin
  Table := TLineTable.Build('ab'#13#10'cd');
  // Offset 3 liegt zwischen CR und LF: Ende der ersten Zeile.
  Assert.IsTrue(Table.PositionAt(3) = TTextPosition.Create(0, 2));
  Assert.IsTrue(Table.PositionAt(2) = TTextPosition.Create(0, 2));
end;

procedure TLineTableTests.PositionAtClampsBeyondEnd;
var
  Table: TLineTable;
begin
  Table := TLineTable.Build('ab'#10'c');
  Assert.IsTrue(Table.PositionAt(99) = TTextPosition.Create(1, 1));
  Assert.IsTrue(Table.PositionAt(-5) = TTextPosition.Create(0, 0));
end;

procedure TLineTableTests.OffsetAtClampsToLineEnd;
var
  Table: TLineTable;
begin
  Table := TLineTable.Build('ab'#13#10'cd');
  Assert.AreEqual<Integer>(2, Table.OffsetAt(TTextPosition.Create(0, 10)));
  Assert.AreEqual<Integer>(5, Table.OffsetAt(TTextPosition.Create(1, 1)));
  Assert.AreEqual<Integer>(4, Table.OffsetAt(TTextPosition.Create(1, -3)));
end;

procedure TLineTableTests.OffsetAtLineBeyondEnd;
var
  Table: TLineTable;
begin
  Table := TLineTable.Build('ab'#10'cd');
  Assert.AreEqual<Integer>(5, Table.OffsetAt(TTextPosition.Create(9, 0)));
  Assert.AreEqual<Integer>(0, Table.OffsetAt(TTextPosition.Create(-1, 4)));
end;

procedure TLineTableTests.RoundTripAllOffsets;
const
  // CR, LF, CRLF und ein Surrogatpaar (U+1F600).
  Text = 'a'#13'b'#10'c'#13#10#$D83D#$DE00'd'#10;
var
  Table: TLineTable;
  Offset: Integer;
begin
  Table := TLineTable.Build(Text);
  Assert.AreEqual<Integer>(5, Table.LineCount);
  for Offset := 0 to Length(Text) do
  begin
    // Der Offset zwischen CR und LF hat keine eigene Position.
    if (Offset > 0) and (Offset < Length(Text)) and (Text[Offset] = #13) and (Text[Offset + 1] = #10) then
      Continue;
    Assert.AreEqual<Integer>(Offset, Table.OffsetAt(Table.PositionAt(Offset)), Format('Offset %d', [Offset]));
  end;
end;

procedure TLineTableTests.LineStartsAndEnds;
var
  Table: TLineTable;
begin
  Table := TLineTable.Build('ab'#13#10'c'#13);
  Assert.AreEqual<Integer>(3, Table.LineCount);
  Assert.AreEqual<Integer>(0, Table.LineStart(0));
  Assert.AreEqual<Integer>(2, Table.LineContentEnd(0));
  Assert.AreEqual<Integer>(4, Table.LineStart(1));
  Assert.AreEqual<Integer>(5, Table.LineContentEnd(1));
  Assert.AreEqual<Integer>(6, Table.LineStart(2));
  Assert.AreEqual<Integer>(6, Table.LineContentEnd(2));
  Assert.AreEqual<Integer>(6, Table.TextLength);
end;

initialization
  TDUnitX.RegisterTestFixture(TTextLinesTests);
  TDUnitX.RegisterTestFixture(TLineTableTests);

end.
