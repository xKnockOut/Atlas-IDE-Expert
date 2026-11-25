unit Atlas.Text.Columns.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextColumnsTests = class
  public
    [Test]
    procedure DisplayLineExpandsTabsAndRunsMatchOnlyAtTheirColumn;
    [Test]
    procedure DisplayColumnAndSameDisplayLine;
  end;

implementation

uses
  Atlas.Text.Columns;

procedure TTextColumnsTests.DisplayLineExpandsTabsAndRunsMatchOnlyAtTheirColumn;
var
  mLine: string;
begin
  Assert.AreEqual('a   b', TTextColumns.DisplayLine('a'#9'b'#13, 4));
  Assert.AreEqual('    x', TTextColumns.DisplayLine(#9'x', 4));
  Assert.AreEqual(#9'x', TTextColumns.DisplayLine(#9'x', 0));
  mLine := TTextColumns.DisplayLine('  if (A) then', 2);
  Assert.IsTrue(TTextColumns.RunMatches(mLine, '(', 6));
  Assert.IsTrue(TTextColumns.RunMatches(mLine, 'if', 3));
  // Lauf einer anderen Zeile bzw. an anderer Spalte: nicht einfärben.
  Assert.IsFalse(TTextColumns.RunMatches(mLine, 'begin', 3));
  Assert.IsFalse(TTextColumns.RunMatches(mLine, '(', 5));
  Assert.IsFalse(TTextColumns.RunMatches(mLine, 'then', 12));
  Assert.IsFalse(TTextColumns.RunMatches(mLine, '', 1));
  // Zeichenindex als Editorspalte (#615).
  Assert.AreEqual(1, TTextColumns.ColumnOf('abc', 0, 4));
  Assert.AreEqual(3, TTextColumns.ColumnOf('abc', 2, 4));
  Assert.AreEqual(5, TTextColumns.ColumnOf('a'#9'b', 2, 4));
  Assert.AreEqual(5, TTextColumns.ColumnOf(#9'x', 1, 4));
  Assert.AreEqual(2, TTextColumns.ColumnOf(#9'x', 1, 0));
end;

procedure TTextColumnsTests.DisplayColumnAndSameDisplayLine;
begin
  Assert.AreEqual(1, TTextColumns.DisplayColumn('a'#9'b', 0, 4));
  Assert.AreEqual(5, TTextColumns.DisplayColumn('a'#9'b', 2, 4));
  // Hinter dem Zeilenende und mit #13 keine weitere Spalte.
  Assert.AreEqual(3, TTextColumns.DisplayColumn('ab'#13, 10, 4));
  Assert.AreEqual(1, TTextColumns.DisplayColumn('ab', -1, 4));
  Assert.IsTrue(TTextColumns.SameDisplayLine(#9'x  ', '    x', 4));
  Assert.IsFalse(TTextColumns.SameDisplayLine(#9'x', '  x', 4));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextColumnsTests);

end.
