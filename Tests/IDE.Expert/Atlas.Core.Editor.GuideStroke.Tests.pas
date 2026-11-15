unit Atlas.Core.Editor.GuideStroke.Tests;

// Blocklinien in einer Zeile (#514, #653): Bildschirmzeile, Ende am Rand und unter dem Kopf, Lage des Strichs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGuideStrokeTests = class
  public
    [Test]
    procedure RowIndexRoundsToTheMiddle;
    [Test]
    procedure UnderHeaderCountsCoveredRows;
    [Test]
    procedure OpenerLineIsAlwaysALine;
    [Test]
    procedure FirstRowBelowHeaderTapersFromTop;
    [Test]
    procedure LastVisibleRowTapersDownwards;
    [Test]
    procedure RestBelowTheLastRowIsSkipped;
    [Test]
    procedure CloserAtTheEdgeIsALine;
    [Test]
    procedure StrokeStaysLeftOfTheCell;
    [Test]
    procedure StrokeKeepsMarginBeforeCode;
  end;

implementation

uses
  Atlas.Core.Editor.GuideStroke;

function Row(ATop, ABottom, AClient: Integer): TAtlasGuideRow;
begin
  Result := Default(TAtlasGuideRow);
  Result.Top := ATop;
  Result.Bottom := ABottom;
  Result.ClientHeight := AClient;
end;

function EndOf(const ARow: TAtlasGuideRow): Integer;
begin
  Result := Ord(TAtlasGuideStroke.EndOf(ARow));
end;

{ TAtlasGuideStrokeTests }

procedure TAtlasGuideStrokeTests.RowIndexRoundsToTheMiddle;
begin
  Assert.AreEqual(0, TAtlasGuideStroke.RowIndex(0, 16));
  Assert.AreEqual(2, TAtlasGuideStroke.RowIndex(32, 16));
  Assert.AreEqual(3, TAtlasGuideStroke.RowIndex(40, 16), 'halbe Zeile zählt zur nächsten');
  Assert.AreEqual(-1, TAtlasGuideStroke.RowIndex(10, 0));
end;

procedure TAtlasGuideStrokeTests.UnderHeaderCountsCoveredRows;
begin
  Assert.IsTrue(TAtlasGuideStroke.UnderHeader(0, 2));
  Assert.IsTrue(TAtlasGuideStroke.UnderHeader(1, 2));
  Assert.IsFalse(TAtlasGuideStroke.UnderHeader(2, 2));
  Assert.IsFalse(TAtlasGuideStroke.UnderHeader(-1, 2));
  Assert.IsFalse(TAtlasGuideStroke.UnderHeader(0, 0));
end;

procedure TAtlasGuideStrokeTests.OpenerLineIsAlwaysALine;
var
  mRow: TAtlasGuideRow;
begin
  mRow := Row(490, 506, 500);
  mRow.First := True;
  mRow.TaperBelowHeader := True;
  Assert.AreEqual(Ord(TAtlasGuideEnd.Line), EndOf(mRow));
end;

procedure TAtlasGuideStrokeTests.FirstRowBelowHeaderTapersFromTop;
var
  mRow: TAtlasGuideRow;
begin
  mRow := Row(32, 48, 500);
  mRow.TaperBelowHeader := True;
  Assert.AreEqual(Ord(TAtlasGuideEnd.TaperTop), EndOf(mRow));
end;

procedure TAtlasGuideStrokeTests.LastVisibleRowTapersDownwards;
begin
  // Mindestens die Hälfte zu sehen: diese Zeile läuft aus.
  Assert.AreEqual(Ord(TAtlasGuideEnd.TaperBottom), EndOf(Row(490, 506, 500)));
  // Ganz zu sehen, aber die nächste zu weniger als der Hälfte: auch diese.
  Assert.AreEqual(Ord(TAtlasGuideEnd.TaperBottom), EndOf(Row(480, 496, 500)));
  Assert.AreEqual(Ord(TAtlasGuideEnd.Line), EndOf(Row(464, 480, 500)));
end;

procedure TAtlasGuideStrokeTests.RestBelowTheLastRowIsSkipped;
var
  mRow: TAtlasGuideRow;
begin
  Assert.AreEqual(Ord(TAtlasGuideEnd.Skip), EndOf(Row(496, 512, 500)));
  mRow := Row(496, 512, 500);
  mRow.Last := True;
  Assert.AreEqual(Ord(TAtlasGuideEnd.Skip), EndOf(mRow), 'auch das Ende der Linie');
end;

procedure TAtlasGuideStrokeTests.CloserAtTheEdgeIsALine;
var
  mRow: TAtlasGuideRow;
begin
  mRow := Row(490, 506, 500);
  mRow.Last := True;
  Assert.AreEqual(Ord(TAtlasGuideEnd.Line), EndOf(mRow));
end;

procedure TAtlasGuideStrokeTests.StrokeStaysLeftOfTheCell;
begin
  // Zelle 9 px breit: 3 px davor, Stift 1 px.
  Assert.AreEqual(97, TAtlasGuideStroke.StrokeX(100, 9, 1, 0, 0, 4));
  // Schmale Zelle: mindestens 2 px; Stift 3 px mittig.
  Assert.AreEqual(97, TAtlasGuideStroke.StrokeX(100, 4, 3, 0, 0, 4));
end;

procedure TAtlasGuideStrokeTests.StrokeKeepsMarginBeforeCode;
begin
  // Block ab Spalte 1: nicht weiter links als 4 px vor dem Code.
  Assert.AreEqual(47, TAtlasGuideStroke.StrokeX(50, 30, 2, 50, 400, 4));
  Assert.AreEqual(97, TAtlasGuideStroke.StrokeX(100, 9, 1, 50, 400, 4), 'weiter rechts bleibt');
  Assert.AreEqual(46, TAtlasGuideStroke.StrokeX(49, 9, 1, 50, 50, 4), 'ohne Code keine Grenze');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGuideStrokeTests);

end.
