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

initialization
  TDUnitX.RegisterTestFixture(TTextDiffTests);

end.
