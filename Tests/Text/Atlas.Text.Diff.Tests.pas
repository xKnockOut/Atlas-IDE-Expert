unit Atlas.Text.Diff.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextDiffTests = class
  public
    [Test]
    procedure PrefixSuffixNoOverlap;
    [Test]
    procedure HunksLcs;
    [Test]
    procedure HunksEqualIsEmpty;
    [Test]
    procedure HunksTooLargeOneBlock;
    [Test]
    procedure ChangedLinesSameCount;
    [Test]
    procedure ChangedLinesBlock;
    [Test]
    procedure ChangedLinesLimit;
    [Test]
    procedure ChangedLinesEqualIsEmpty;
    /// <summary>#1358: Kopf, Blöcke mit Umgebung, zusammengefasste Blöcke, Einfügen am Anfang, gleich = leer.
    /// </summary>
    [Test]
    procedure UnifiedDiff;
    /// <summary>Gleicher Anfang und gleiches Ende direkt im Text wie über die Zeilen, für alle kurzen Texte aus
    /// „a“, „b“ und LF.</summary>
    [Test]
    procedure PrefixSuffixOfTextMatchesLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Diff;

procedure TTextDiffTests.PrefixSuffixNoOverlap;
var
  mPrefix, mSuffix: Integer;
begin
  TTextDiff.CommonPrefixSuffix(['a', 'b', 'a'], ['a', 'b', 'x', 'b', 'a'], mPrefix, mSuffix);
  Assert.AreEqual<Integer>(2, mPrefix);
  Assert.AreEqual<Integer>(1, mSuffix);
  TTextDiff.CommonPrefixSuffix(['a', 'a'], ['a', 'a', 'a'], mPrefix, mSuffix);
  Assert.AreEqual<Integer>(2, mPrefix);
  Assert.AreEqual<Integer>(0, mSuffix);
end;

procedure TTextDiffTests.HunksLcs;
var
  mHunks: TArray<TTextLineHunk>;
begin
  mHunks := TTextDiff.Hunks(['a', 'b', 'c', 'd', 'e'], ['a', 'X', 'c', 'd', 'Y', 'Z', 'e']);
  Assert.AreEqual<Integer>(2, Length(mHunks));
  Assert.AreEqual<Integer>(1, mHunks[0].OldStart);
  Assert.AreEqual<Integer>(1, mHunks[0].OldCount);
  Assert.AreEqual<Integer>(1, mHunks[0].NewStart);
  Assert.AreEqual<Integer>(1, mHunks[0].NewCount);
  Assert.AreEqual<Integer>(4, mHunks[1].OldStart);
  Assert.AreEqual<Integer>(0, mHunks[1].OldCount);
  Assert.AreEqual<Integer>(4, mHunks[1].NewStart);
  Assert.AreEqual<Integer>(2, mHunks[1].NewCount);
end;

procedure TTextDiffTests.HunksEqualIsEmpty;
begin
  Assert.AreEqual<Integer>(0, Length(TTextDiff.Hunks(['a', 'b'], ['a', 'b'])));
end;

procedure TTextDiffTests.HunksTooLargeOneBlock;
var
  mOld, mNew: TArray<string>;
  mHunks: TArray<TTextLineHunk>;
  mIndex: Integer;
begin
  mOld := nil;
  mNew := nil;
  SetLength(mOld, 2100);
  SetLength(mNew, 2100);
  for mIndex := 0 to High(mOld) do
  begin
    mOld[mIndex] := 'a' + IntToStr(mIndex);
    mNew[mIndex] := 'b' + IntToStr(mIndex);
  end;
  mHunks := TTextDiff.Hunks(mOld, mNew);
  Assert.AreEqual<Integer>(1, Length(mHunks));
  Assert.AreEqual<Integer>(2100, mHunks[0].OldCount);
  Assert.AreEqual<Integer>(2100, mHunks[0].NewCount);
end;

procedure TTextDiffTests.ChangedLinesSameCount;
var
  mLines: TArray<string>;
begin
  mLines := TTextDiff.ChangedLines(['a', 'b', 'c'], ['a', 'B', 'c']);
  Assert.AreEqual<Integer>(3, Length(mLines));
  Assert.AreEqual('Zeile 2:', mLines[0]);
  Assert.AreEqual('- b', mLines[1]);
  Assert.AreEqual('+ B', mLines[2]);
end;

procedure TTextDiffTests.ChangedLinesBlock;
var
  mLines: TArray<string>;
begin
  mLines := TTextDiff.ChangedLines(['a', 'b', 'c'], ['a', 'x', 'y', 'c']);
  Assert.AreEqual<Integer>(4, Length(mLines));
  Assert.AreEqual('ab Zeile 2:', mLines[0]);
  Assert.AreEqual('- b', mLines[1]);
  Assert.AreEqual('+ x', mLines[2]);
  Assert.AreEqual('+ y', mLines[3]);
end;

procedure TTextDiffTests.ChangedLinesLimit;
var
  mLines: TArray<string>;
begin
  mLines := TTextDiff.ChangedLines(['a'], ['b', 'c', 'd', 'e'], 3);
  Assert.AreEqual<Integer>(4, Length(mLines));
  Assert.AreEqual('ab Zeile 1:', mLines[0]);
  Assert.AreEqual('- a', mLines[1]);
  Assert.AreEqual('+ b', mLines[2]);
  Assert.AreEqual('…', mLines[3]);
end;

procedure TTextDiffTests.ChangedLinesEqualIsEmpty;
begin
  Assert.AreEqual<Integer>(0, Length(TTextDiff.ChangedLines(['a', ''], ['a', ''])));
  Assert.AreEqual<Integer>(0, Length(TTextDiff.ChangedLines(nil, nil)));
end;

procedure TTextDiffTests.UnifiedDiff;
begin
  Assert.AreEqual('--- a'#10'+++ b'#10'@@ -1,3 +1,3 @@'#10' 1'#10'-2'#10'+x'#10' 3',
    string.Join(#10, TTextDiff.Unified('a', 'b', ['1', '2', '3'], ['1', 'x', '3'], 1)));
  // Zwei Blöcke mit sich berührender Umgebung werden ein Abschnitt, entfernte zwei.
  Assert.AreEqual('--- a'#10'+++ b'#10'@@ -1,5 +1,5 @@'#10'-1'#10'+x'#10' 2'#10' 3'#10'-4'#10'+y'#10' 5',
    string.Join(#10, TTextDiff.Unified('a', 'b', ['1', '2', '3', '4', '5', '6', '7'],
    ['x', '2', '3', 'y', '5', '6', '7'], 1)));
  Assert.AreEqual('--- a'#10'+++ b'#10'@@ -1 +1 @@'#10'-1'#10'+x'#10'@@ -7 +7 @@'#10'-7'#10'+y',
    string.Join(#10, TTextDiff.Unified('a', 'b', ['1', '2', '3', '4', '5', '6', '7'],
    ['x', '2', '3', '4', '5', '6', 'y'], 0)));
  Assert.AreEqual('--- a'#10'+++ b'#10'@@ -0,0 +1 @@'#10'+neu',
    string.Join(#10, TTextDiff.Unified('a', 'b', ['1'], ['neu', '1'], 0)));
  Assert.AreEqual(0, Integer(Length(TTextDiff.Unified('a', 'b', ['1'], ['1'], 3))));
end;

/// <summary>Zeilen an LF getrennt, auch die leere letzte.</summary>
function LfLines(const AText: string): TArray<string>;
var
  mStart, mIndex, mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AText) + 1);
  mCount := 0;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = #10 then
    begin
      Result[mCount] := Copy(AText, mStart, mIndex - mStart);
      Inc(mCount);
      mStart := mIndex + 1;
    end;
  end;
  Result[mCount] := Copy(AText, mStart, MaxInt);
  SetLength(Result, mCount + 1);
end;

/// <summary>Alle Texte aus „a“, „b“ und LF mit höchstens ALength Zeichen.</summary>
function ShortTexts(ALength: Integer): TArray<string>;
const
  cChars: array[0..2] of Char = ('a', 'b', #10);
var
  mShorter: TArray<string>;
  mText: string;
  mChar: Char;
begin
  Result := TArray<string>.Create('');
  if ALength = 0 then
  begin
    Exit;
  end;
  mShorter := ShortTexts(ALength - 1);
  for mText in mShorter do
  begin
    if Length(mText) = ALength - 1 then
    begin
      for mChar in cChars do
      begin
        Result := Result + [mText + mChar];
      end;
    end;
  end;
  Result := Result + Copy(mShorter, 1, MaxInt);
end;

procedure TTextDiffTests.PrefixSuffixOfTextMatchesLines;
var
  mTexts: TArray<string>;
  mOld, mNew: string;
  mPrefix, mSuffix, mLinePrefix, mLineSuffix, mOldCount, mNewCount: Integer;
begin
  mTexts := ShortTexts(4);
  for mOld in mTexts do
  begin
    for mNew in mTexts do
    begin
      TTextDiff.CommonPrefixSuffix(LfLines(mOld), LfLines(mNew), mLinePrefix, mLineSuffix);
      TTextDiff.CommonPrefixSuffix(mOld, mNew, mPrefix, mSuffix, mOldCount, mNewCount);
      Assert.AreEqual(mLinePrefix, mPrefix, 'Anfang ' + mOld.QuotedString + ' -> ' + mNew.QuotedString);
      Assert.AreEqual(mLineSuffix, mSuffix, 'Ende ' + mOld.QuotedString + ' -> ' + mNew.QuotedString);
      Assert.AreEqual(Integer(Length(LfLines(mNew))), mNewCount, 'Zeilen ' + mNew.QuotedString);
    end;
  end;
  mTexts := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextDiffTests);

end.
