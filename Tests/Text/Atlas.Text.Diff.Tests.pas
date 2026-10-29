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
    [Test]
    procedure UnifiedHeaderAndContext;
    [Test]
    procedure UnifiedMergesNearHunks;
    [Test]
    procedure UnifiedSeparateHunks;
    [Test]
    procedure UnifiedRemovedLine;
    [Test]
    procedure UnifiedEqualIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Diff;

procedure TTextDiffTests.PrefixSuffixNoOverlap;
var
  Prefix, Suffix: Integer;
begin
  TTextDiff.CommonPrefixSuffix(['a', 'b', 'a'], ['a', 'b', 'x', 'b', 'a'], Prefix, Suffix);
  Assert.AreEqual<Integer>(2, Prefix);
  Assert.AreEqual<Integer>(1, Suffix);
  TTextDiff.CommonPrefixSuffix(['a', 'a'], ['a', 'a', 'a'], Prefix, Suffix);
  Assert.AreEqual<Integer>(2, Prefix);
  Assert.AreEqual<Integer>(0, Suffix);
end;

procedure TTextDiffTests.HunksLcs;
var
  Hunks: TArray<TTextLineHunk>;
begin
  Hunks := TTextDiff.Hunks(['a', 'b', 'c', 'd', 'e'], ['a', 'X', 'c', 'd', 'Y', 'Z', 'e']);
  Assert.AreEqual<Integer>(2, Length(Hunks));
  Assert.AreEqual<Integer>(1, Hunks[0].OldStart);
  Assert.AreEqual<Integer>(1, Hunks[0].OldCount);
  Assert.AreEqual<Integer>(1, Hunks[0].NewStart);
  Assert.AreEqual<Integer>(1, Hunks[0].NewCount);
  Assert.AreEqual<Integer>(4, Hunks[1].OldStart);
  Assert.AreEqual<Integer>(0, Hunks[1].OldCount);
  Assert.AreEqual<Integer>(4, Hunks[1].NewStart);
  Assert.AreEqual<Integer>(2, Hunks[1].NewCount);
end;

procedure TTextDiffTests.HunksEqualIsEmpty;
begin
  Assert.AreEqual<Integer>(0, Length(TTextDiff.Hunks(['a', 'b'], ['a', 'b'])));
end;

procedure TTextDiffTests.HunksTooLargeOneBlock;
var
  Old, New: TArray<string>;
  Hunks: TArray<TTextLineHunk>;
  Index: Integer;
begin
  Old := nil;
  New := nil;
  SetLength(Old, 2100);
  SetLength(New, 2100);
  for Index := 0 to High(Old) do
  begin
    Old[Index] := 'a' + IntToStr(Index);
    New[Index] := 'b' + IntToStr(Index);
  end;
  Hunks := TTextDiff.Hunks(Old, New);
  Assert.AreEqual<Integer>(1, Length(Hunks));
  Assert.AreEqual<Integer>(2100, Hunks[0].OldCount);
  Assert.AreEqual<Integer>(2100, Hunks[0].NewCount);
end;

procedure TTextDiffTests.ChangedLinesSameCount;
var
  Lines: TArray<string>;
begin
  Lines := TTextDiff.ChangedLines(['a', 'b', 'c'], ['a', 'B', 'c']);
  Assert.AreEqual<Integer>(3, Length(Lines));
  Assert.AreEqual('Zeile 2:', Lines[0]);
  Assert.AreEqual('- b', Lines[1]);
  Assert.AreEqual('+ B', Lines[2]);
end;

procedure TTextDiffTests.ChangedLinesBlock;
var
  Lines: TArray<string>;
begin
  Lines := TTextDiff.ChangedLines(['a', 'b', 'c'], ['a', 'x', 'y', 'c']);
  Assert.AreEqual<Integer>(4, Length(Lines));
  Assert.AreEqual('ab Zeile 2:', Lines[0]);
  Assert.AreEqual('- b', Lines[1]);
  Assert.AreEqual('+ x', Lines[2]);
  Assert.AreEqual('+ y', Lines[3]);
end;

procedure TTextDiffTests.ChangedLinesLimit;
var
  Lines: TArray<string>;
begin
  Lines := TTextDiff.ChangedLines(['a'], ['b', 'c', 'd', 'e'], 3);
  Assert.AreEqual<Integer>(4, Length(Lines));
  Assert.AreEqual('ab Zeile 1:', Lines[0]);
  Assert.AreEqual('- a', Lines[1]);
  Assert.AreEqual('+ b', Lines[2]);
  Assert.AreEqual('…', Lines[3]);
end;

procedure TTextDiffTests.ChangedLinesEqualIsEmpty;
begin
  Assert.AreEqual<Integer>(0, Length(TTextDiff.ChangedLines(['a', ''], ['a', ''])));
  Assert.AreEqual<Integer>(0, Length(TTextDiff.ChangedLines(nil, nil)));
end;

procedure TTextDiffTests.UnifiedHeaderAndContext;
var
  mLines: TArray<string>;
begin
  mLines := TTextDiff.Unified('a/U.pas', 'b/U.pas', ['1', '2', '3', '4', '5', '6'], ['1', '2', '3', 'x', '5', '6'], 1);
  Assert.AreEqual('--- a/U.pas|+++ b/U.pas|@@ -3,3 +3,3 @@| 3|-4|+x| 5', string.Join('|', mLines));
end;

procedure TTextDiffTests.UnifiedMergesNearHunks;
var
  mLines: TArray<string>;
begin
  // Abstand 2 Zeilen bei Kontext 1: ein Block.
  mLines := TTextDiff.Unified('a', 'b', ['1', '2', '3', '4', '5'], ['x', '2', '3', 'y', '5'], 1);
  Assert.AreEqual('--- a|+++ b|@@ -1,5 +1,5 @@|-1|+x| 2| 3|-4|+y| 5', string.Join('|', mLines));
end;

procedure TTextDiffTests.UnifiedSeparateHunks;
var
  mLines: TArray<string>;
begin
  mLines := TTextDiff.Unified('a', 'b', ['1', '2', '3', '4', '5', '6', '7'], ['x', '2', '3', '4', '5', '6', 'y'], 1);
  Assert.AreEqual('--- a|+++ b|@@ -1,2 +1,2 @@|-1|+x| 2|@@ -6,2 +6,2 @@| 6|-7|+y', string.Join('|', mLines));
end;

procedure TTextDiffTests.UnifiedRemovedLine;
var
  mLines: TArray<string>;
begin
  mLines := TTextDiff.Unified('a', 'b', ['uses', '  A,', '  B;'], ['uses', '  B;'], 0);
  Assert.AreEqual('--- a|+++ b|@@ -2 +1,0 @@|-  A,', string.Join('|', mLines));
end;

procedure TTextDiffTests.UnifiedEqualIsEmpty;
begin
  Assert.AreEqual<Integer>(0, Length(TTextDiff.Unified('a', 'b', ['x'], ['x'], 3)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextDiffTests);

end.
