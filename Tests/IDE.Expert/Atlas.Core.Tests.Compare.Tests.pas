unit Atlas.Core.Tests.Compare.Tests;

// Tests des Vergleichs von erwartet und erhalten (#1779) ohne IDE: JSON und
// XML einrücken, sichtbarer Leerraum, Zuordnung der Zeilen und der
// abweichende Zeichenbereich, gekürzte Werte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestCompareTests = class
  public
    [Test]
    procedure RecognizesJsonAndXml;
    [Test]
    procedure PrettyJsonIndentsAndKeepsStrings;
    [Test]
    procedure PrettyXmlOneElementPerLine;
    [Test]
    procedure JsonDifferenceIsOneLine;
    [Test]
    procedure LineEndAndTrailingSpaceAreVisible;
    [Test]
    procedure ExtraLinesHaveGapOpposite;
    [Test]
    procedure WithoutFormatTextStaysAsIs;
    [Test]
    procedure TruncatedValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.Compare;

procedure TAtlasTestCompareTests.RecognizesJsonAndXml;
begin
  Assert.IsTrue(TAtlasTestCompare.FormatOf(' {"a":1} ') = TAtlasCompareFormat.Json);
  Assert.IsTrue(TAtlasTestCompare.FormatOf('[1,2]') = TAtlasCompareFormat.Json);
  Assert.IsTrue(TAtlasTestCompare.FormatOf('<a><b/></a>') = TAtlasCompareFormat.Xml);
  Assert.IsTrue(TAtlasTestCompare.FormatOf('abc') = TAtlasCompareFormat.Plain);
  Assert.IsTrue(TAtlasTestCompare.FormatOf('{') = TAtlasCompareFormat.Plain);
end;

procedure TAtlasTestCompareTests.PrettyJsonIndentsAndKeepsStrings;
begin
  Assert.AreEqual('{'#10'  "a": 1,'#10'  "b": ['#10'    "x, {y}",'#10'    "q\"z"'#10'  ],'#10'  "c": {}'#10'}',
    TAtlasTestCompare.PrettyJson('{"a":1, "b":["x, {y}","q\"z"],"c":{ }}'));
end;

procedure TAtlasTestCompareTests.PrettyXmlOneElementPerLine;
begin
  Assert.AreEqual('<?xml version="1.0"?>'#10'<a>'#10'  <b>Text</b>'#10'  <c/>'#10'  <!-- x > y -->'#10'</a>',
    TAtlasTestCompare.PrettyXml('<?xml version="1.0"?><a> <b>Text</b><c/><!-- x > y --></a>'));
end;

procedure TAtlasTestCompareTests.JsonDifferenceIsOneLine;
var
  mResult: TAtlasCompareResult;
  mRow: TAtlasCompareRow;
  mFound: Boolean;
begin
  mResult := TAtlasTestCompare.Build('{"name":"Anna","age":30,"city":"Bonn"}',
    '{"name":"Anna","age":31,"city":"Bonn"}', True);
  Assert.IsTrue(mResult.Format = TAtlasCompareFormat.Json);
  Assert.AreEqual(1, mResult.Differences, 'nur die Zeile mit age');
  mFound := False;
  for mRow in mResult.Rows do
  begin
    if mRow.Kind = TAtlasCompareKind.Changed then
    begin
      mFound := True;
      Assert.AreEqual('  "age": 30,↵', mRow.Left);
      Assert.AreEqual('  "age": 31,↵', mRow.Right);
      Assert.AreEqual(10, mRow.LeftStart, 'nur die abweichende Ziffer');
      Assert.AreEqual(1, mRow.LeftLength);
      Assert.AreEqual(1, mRow.RightLength);
    end;
  end;
  Assert.IsTrue(mFound);
end;

procedure TAtlasTestCompareTests.LineEndAndTrailingSpaceAreVisible;
var
  mLines: TArray<string>;
  mResult: TAtlasCompareResult;
begin
  mLines := TAtlasTestCompare.VisibleLines('a  '#13#10'b'#9'c'#10'd'#13'e');
  Assert.AreEqual(4, Integer(Length(mLines)));
  Assert.AreEqual('a··␍↵', mLines[0]);
  Assert.AreEqual('b→c↵', mLines[1]);
  Assert.AreEqual('d␍', mLines[2]);
  Assert.AreEqual('e', mLines[3]);
  mResult := TAtlasTestCompare.Build('x'#13#10'y', 'x'#10'y', True);
  Assert.AreEqual(1, mResult.Differences, 'nur das Zeilenende');
  Assert.IsTrue(mResult.Rows[0].Kind = TAtlasCompareKind.Changed);
  Assert.AreEqual(1, mResult.Rows[0].LeftStart);
  Assert.AreEqual(1, mResult.Rows[0].LeftLength, 'das ␍');
  Assert.AreEqual(0, mResult.Rows[0].RightLength);
  mResult := TAtlasTestCompare.Build('abc ', 'abc', False);
  Assert.AreEqual('abc·', mResult.Rows[0].Left);
end;

procedure TAtlasTestCompareTests.ExtraLinesHaveGapOpposite;
var
  mResult: TAtlasCompareResult;
begin
  mResult := TAtlasTestCompare.Build('a'#10'b'#10'c', 'a'#10'c', False);
  Assert.AreEqual(3, Integer(Length(mResult.Rows)));
  Assert.IsTrue(mResult.Rows[1].Kind = TAtlasCompareKind.Removed);
  Assert.IsTrue(mResult.Rows[1].HasLeft);
  Assert.IsFalse(mResult.Rows[1].HasRight, 'Lücke rechts');
  Assert.IsTrue(mResult.Rows[2].Kind = TAtlasCompareKind.Same);
  mResult := TAtlasTestCompare.Build('a', 'a'#10'z', False);
  Assert.IsTrue(mResult.Rows[Length(mResult.Rows) - 1].Kind = TAtlasCompareKind.Added);
end;

procedure TAtlasTestCompareTests.WithoutFormatTextStaysAsIs;
var
  mResult: TAtlasCompareResult;
begin
  mResult := TAtlasTestCompare.Build('{"a":1}', '{"a":2}', False);
  Assert.IsTrue(mResult.Format = TAtlasCompareFormat.Plain);
  Assert.AreEqual(1, Integer(Length(mResult.Rows)));
  mResult := TAtlasTestCompare.Build('{"a":1}', '<a/>', True);
  Assert.IsTrue(mResult.Format = TAtlasCompareFormat.Plain, 'verschiedene Formate bleiben roh');
  Assert.AreEqual(0, TAtlasTestCompare.Build('gleich', 'gleich', True).Differences);
end;

procedure TAtlasTestCompareTests.TruncatedValues;
var
  mResult: TAtlasCompareResult;
begin
  mResult := TAtlasTestCompare.Build('abcdef...', 'abcdeg', True);
  Assert.IsTrue(mResult.ExpectedTruncated);
  Assert.IsFalse(mResult.ActualTruncated);
  Assert.IsTrue(TAtlasTestCompare.IsTruncated('abc…'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestCompareTests);

end.
