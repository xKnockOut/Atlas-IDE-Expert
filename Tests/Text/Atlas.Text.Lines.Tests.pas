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
    /// <summary>Charakterisierung der RTL: TStringHelper.Split verwirft ein leeres letztes Element
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
  mMixed: Boolean;
begin
  Assert.IsTrue(TTextLines.DominantOf('a'#10'b'#13#10'c'#10, mMixed) = TTextLineBreak.LF);
  Assert.IsTrue(mMixed);
  Assert.IsTrue(TTextLines.DominantOf('a'#10'b'#13#10, mMixed) = TTextLineBreak.CRLF);
  Assert.IsTrue(TTextLines.DominantOf('a'#10'b'#13#10, TTextLineBreak.LF, mMixed) = TTextLineBreak.LF);
  Assert.IsTrue(TTextLines.DominantOf('a'#13#10'b', TTextLineBreak.LF, mMixed) = TTextLineBreak.CRLF);
  Assert.IsFalse(mMixed);
  Assert.IsTrue(TTextLines.DominantOf('abc', mMixed) = TTextLineBreak.None);
  Assert.IsFalse(mMixed);
end;

procedure TTextLinesTests.SplitLinesCrLfCr;
var
  mLines: TArray<string>;
begin
  mLines := TTextLines.SplitLines('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual<Integer>(4, Length(mLines));
  Assert.AreEqual('a', mLines[0]);
  Assert.AreEqual('b', mLines[1]);
  Assert.AreEqual('c', mLines[2]);
  Assert.AreEqual('d', mLines[3]);
end;

procedure TTextLinesTests.SplitLinesTrailingBreakGivesEmptyLine;
var
  mLines: TArray<string>;
begin
  mLines := TTextLines.SplitLines('a'#13#10);
  Assert.AreEqual<Integer>(2, Length(mLines));
  Assert.AreEqual('a', mLines[0]);
  Assert.AreEqual('', mLines[1]);
end;

procedure TTextLinesTests.SplitLinesEmptyGivesOneLine;
var
  mLines: TArray<string>;
begin
  mLines := TTextLines.SplitLines('');
  Assert.AreEqual<Integer>(1, Length(mLines));
  Assert.AreEqual('', mLines[0]);
end;

procedure TTextLinesTests.SplitLinesReturnsLineBreak;
var
  mLines: TArray<string>;
  mLineBreak: string;
begin
  mLines := TTextLines.SplitLines('a'#13#10'b'#10'c', mLineBreak);
  Assert.AreEqual(#13#10, mLineBreak);
  Assert.AreEqual<Integer>(3, Length(mLines));
  Assert.AreEqual('c', mLines[2]);
end;

procedure TTextLinesTests.SplitKeepingBreaksKeepsEnds;
var
  mLines: TArray<string>;
begin
  mLines := TTextLines.SplitKeepingBreaks('a'#13#10'b'#10'c'#13'd');
  Assert.AreEqual<Integer>(4, Length(mLines));
  Assert.AreEqual('a'#13#10, mLines[0]);
  Assert.AreEqual('b'#10, mLines[1]);
  Assert.AreEqual('c'#13, mLines[2]);
  Assert.AreEqual('d', mLines[3]);
  mLines := TTextLines.SplitKeepingBreaks('a'#10);
  Assert.AreEqual<Integer>(1, Length(mLines));
  Assert.AreEqual('a'#10, mLines[0]);
  Assert.AreEqual<Integer>(0, Length(TTextLines.SplitKeepingBreaks('')));
end;

procedure TTextLinesTests.SplitHelperDropsTrailingEmpty;
var
  mText: string;
begin
  // Verhalten der Laufzeitbibliothek: FPC verwirft die leere letzte Zeile, Delphi nicht. SplitLines gilt für beide.
  {$IFDEF FPC}
  mText := 'a'#10;
  Assert.AreEqual<Integer>(1, Length(mText.Split([#10])), 'Split verwirft die leere letzte Zeile');
  mText := '';
  Assert.AreEqual<Integer>(0, Length(mText.Split([#10])), 'Split liefert für leeren Text nichts');
  {$ELSE}
  mText := '';
  {$ENDIF}
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
  cText = 'begin'#13#10'    x := 1;'#13'  y'#10'z';
begin
  Assert.AreEqual('', TTextLines.IndentOf(cText, 0));
  Assert.AreEqual('    ', TTextLines.IndentOf(cText, 1));
  Assert.AreEqual('  ', TTextLines.IndentOf(cText, 2));
  Assert.AreEqual('', TTextLines.IndentOf(cText, 3));
  Assert.AreEqual('', TTextLines.IndentOf(cText, 4));
  Assert.AreEqual('', TTextLines.IndentOf(cText, -1));
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
  mTable: TLineTable;
begin
  mTable := TLineTable.Build('ab'#13#10'cd'#10'e');
  Assert.AreEqual<Integer>(3, mTable.LineCount);
  Assert.IsTrue(mTable.PositionAt(0) = TTextPosition.Create(0, 0));
  Assert.IsTrue(mTable.PositionAt(4) = TTextPosition.Create(1, 0));
  Assert.IsTrue(mTable.PositionAt(6) = TTextPosition.Create(1, 2));
  Assert.IsTrue(mTable.PositionAt(7) = TTextPosition.Create(2, 0));
end;

procedure TLineTableTests.PositionAtInsideCrlfStaysOnLine;
var
  mTable: TLineTable;
begin
  mTable := TLineTable.Build('ab'#13#10'cd');
  // Offset 3 liegt zwischen CR und LF: Ende der ersten Zeile.
  Assert.IsTrue(mTable.PositionAt(3) = TTextPosition.Create(0, 2));
  Assert.IsTrue(mTable.PositionAt(2) = TTextPosition.Create(0, 2));
end;

procedure TLineTableTests.PositionAtClampsBeyondEnd;
var
  mTable: TLineTable;
begin
  mTable := TLineTable.Build('ab'#10'c');
  Assert.IsTrue(mTable.PositionAt(99) = TTextPosition.Create(1, 1));
  Assert.IsTrue(mTable.PositionAt(-5) = TTextPosition.Create(0, 0));
end;

procedure TLineTableTests.OffsetAtClampsToLineEnd;
var
  mTable: TLineTable;
begin
  mTable := TLineTable.Build('ab'#13#10'cd');
  Assert.AreEqual<Integer>(2, mTable.OffsetAt(TTextPosition.Create(0, 10)));
  Assert.AreEqual<Integer>(5, mTable.OffsetAt(TTextPosition.Create(1, 1)));
  Assert.AreEqual<Integer>(4, mTable.OffsetAt(TTextPosition.Create(1, -3)));
end;

procedure TLineTableTests.OffsetAtLineBeyondEnd;
var
  mTable: TLineTable;
begin
  mTable := TLineTable.Build('ab'#10'cd');
  Assert.AreEqual<Integer>(5, mTable.OffsetAt(TTextPosition.Create(9, 0)));
  Assert.AreEqual<Integer>(0, mTable.OffsetAt(TTextPosition.Create(-1, 4)));
end;

procedure TLineTableTests.RoundTripAllOffsets;
const
  // CR, LF, CRLF und ein Surrogatpaar (U+1F600).
  cText = 'a'#13'b'#10'c'#13#10#$D83D#$DE00'd'#10;
var
  mTable: TLineTable;
  mOffset: Integer;
begin
  mTable := TLineTable.Build(cText);
  Assert.AreEqual<Integer>(5, mTable.LineCount);
  // Text[Offset] gilt nur ab 1.
  for mOffset := 0 to Length(cText) do // lsp-ignore: loop-off-by-one -- Offsets zwischen den Zeichen
  begin
    // Der Offset zwischen CR und LF hat keine eigene Position.
    if (mOffset > 0) and (mOffset < Length(cText)) and (cText[mOffset] = #13) and (cText[mOffset + 1] = #10) then
    begin
      Continue;
    end;
    Assert.AreEqual<Integer>(mOffset, mTable.OffsetAt(mTable.PositionAt(mOffset)), Format('Offset %d', [mOffset]));
  end;
end;

procedure TLineTableTests.LineStartsAndEnds;
var
  mTable: TLineTable;
begin
  mTable := TLineTable.Build('ab'#13#10'c'#13);
  Assert.AreEqual<Integer>(3, mTable.LineCount);
  Assert.AreEqual<Integer>(0, mTable.LineStart(0));
  Assert.AreEqual<Integer>(2, mTable.LineContentEnd(0));
  Assert.AreEqual<Integer>(4, mTable.LineStart(1));
  Assert.AreEqual<Integer>(5, mTable.LineContentEnd(1));
  Assert.AreEqual<Integer>(6, mTable.LineStart(2));
  Assert.AreEqual<Integer>(6, mTable.LineContentEnd(2));
  Assert.AreEqual<Integer>(6, mTable.TextLength);
end;

initialization
  TDUnitX.RegisterTestFixture(TTextLinesTests);
  TDUnitX.RegisterTestFixture(TLineTableTests);

end.
