unit Atlas.Core.Designer.Measure.Tests;

// Tests für die Maßlinien im Designer (#605): Nachbarsuche in vier
// Richtungen, Abstand zum Innenrand mit Padding, gleiche Abstände samt Lage,
// Größe mit gleichen Nachbarn und Abstände zwischen zwei Rechtecken.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasMeasureTests = class
  public
    [Test]
    procedure FourNeighbours;
    [Test]
    procedure EdgeWithPadding;
    [Test]
    procedure NearestWins;
    [Test]
    procedure NoCrossOverlapIsNoNeighbour;
    [Test]
    procedure SameGapAbove;
    [Test]
    procedure SameGapLeftOf;
    [Test]
    procedure DifferentAxisIsNotSame;
    [Test]
    procedure SameEdgeGap;
    [Test]
    procedure SizeWithSameNeighbours;
    [Test]
    procedure BetweenApart;
    [Test]
    procedure BetweenInside;
    [Test]
    procedure CaptionTexts;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.Measure;

function Item(const AName: string; ALeft, ATop, AWidth, AHeight: Integer): TAtlasMeasureItem;
begin
  Result := TAtlasMeasureItem.Create(AName, Bounds(ALeft, ATop, AWidth, AHeight));
end;

function LineOf(const ALines: TArray<TAtlasMeasureLine>; ASide: TAtlasMeasureSide;
  out ALine: TAtlasMeasureLine): Boolean;
var
  mLine: TAtlasMeasureLine;
begin
  for mLine in ALines do
  begin
    if mLine.Side = ASide then
    begin
      ALine := mLine;
      Exit(True);
    end;
  end;
  ALine := Default(TAtlasMeasureLine);
  Result := False;
end;

{ TAtlasMeasureTests }

procedure TAtlasMeasureTests.FourNeighbours;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  // Edit 100,100 80x20; Label links, Label oben, Knopf rechts, Memo unten.
  mLines := TAtlasMeasure.Lines(Bounds(100, 100, 80, 20), [Item('lblLeft', 40, 100, 52, 20),
    Item('lblTop', 100, 70, 80, 21), Item('btnRight', 190, 95, 75, 25), Item('memBottom', 90, 132, 200, 50)],
    Rect(0, 0, 400, 300));
  Assert.AreEqual(4, Integer(Length(mLines)));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Left, mLine));
  Assert.AreEqual(8, mLine.Distance);
  Assert.AreEqual('lblLeft', mLine.Target);
  Assert.AreEqual(100, mLine.FromPoint.X);
  Assert.AreEqual(92, mLine.ToPoint.X);
  Assert.AreEqual(110, mLine.FromPoint.Y, 'Mitte der Überlappung');
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Top, mLine));
  Assert.AreEqual(9, mLine.Distance);
  Assert.AreEqual('lblTop', mLine.Target);
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Right, mLine));
  Assert.AreEqual(10, mLine.Distance);
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Bottom, mLine));
  Assert.AreEqual(12, mLine.Distance);
  Assert.AreEqual('memBottom', mLine.Target);
end;

procedure TAtlasMeasureTests.EdgeWithPadding;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
  mInner: TRect;
begin
  mInner := TAtlasMeasure.Inner(Rect(0, 0, 300, 200), 4, 6, 8, 10);
  Assert.AreEqual(4, mInner.Left);
  Assert.AreEqual(190, mInner.Bottom);
  mLines := TAtlasMeasure.Lines(Bounds(20, 30, 100, 20), nil, mInner);
  Assert.AreEqual(4, Integer(Length(mLines)));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Left, mLine));
  Assert.AreEqual(16, mLine.Distance);
  Assert.AreEqual('', mLine.Target, 'Innenrand');
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Top, mLine));
  Assert.AreEqual(24, mLine.Distance);
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Right, mLine));
  Assert.AreEqual(172, mLine.Distance);
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Bottom, mLine));
  Assert.AreEqual(140, mLine.Distance);
end;

procedure TAtlasMeasureTests.NearestWins;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  mLines := TAtlasMeasure.Lines(Bounds(100, 100, 50, 20), [Item('far', 300, 100, 20, 20),
    Item('near', 170, 105, 20, 20)], Rect(0, 0, 400, 300));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Right, mLine));
  Assert.AreEqual('near', mLine.Target);
  Assert.AreEqual(20, mLine.Distance);
end;

procedure TAtlasMeasureTests.NoCrossOverlapIsNoNeighbour;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  // Rechts, aber ganz darunter: kein Nachbar rechts, die Linie geht zum Rand.
  mLines := TAtlasMeasure.Lines(Bounds(100, 100, 50, 20), [Item('below', 200, 150, 20, 20)],
    Rect(0, 0, 400, 300));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Right, mLine));
  Assert.AreEqual('', mLine.Target);
  Assert.AreEqual(250, mLine.Distance);
end;

procedure TAtlasMeasureTests.SameGapAbove;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  // Oben im Panel zwei Felder mit 8 px Abstand; der Bezug hat 8 px zum unteren davon.
  mLines := TAtlasMeasure.Lines(Bounds(10, 66, 100, 21), [Item('edtA', 10, 8, 100, 21),
    Item('edtB', 10, 37, 100, 21)], Rect(0, 0, 300, 300));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Top, mLine));
  Assert.AreEqual(8, mLine.Distance);
  Assert.AreEqual('edtB', mLine.Target);
  Assert.AreEqual(Ord(TAtlasMeasurePlace.Above), Ord(mLine.Same));
end;

procedure TAtlasMeasureTests.SameGapLeftOf;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  // Links eine Zeile Knöpfe mit 6 px Abstand; der Bezug hat 6 px zum letzten Knopf.
  mLines := TAtlasMeasure.Lines(Bounds(162, 200, 75, 25), [Item('btn1', 6, 200, 75, 25),
    Item('btn2', 87, 200, 69, 25)], Rect(0, 0, 400, 400));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Left, mLine));
  Assert.AreEqual(6, mLine.Distance);
  Assert.AreEqual(Ord(TAtlasMeasurePlace.LeftOf), Ord(mLine.Same));
end;

procedure TAtlasMeasureTests.DifferentAxisIsNotSame;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  // Senkrecht 8 px zwischen A und B; der Bezug hat waagrecht 8 px: nicht gleich.
  mLines := TAtlasMeasure.Lines(Bounds(200, 300, 50, 20), [Item('edtA', 10, 8, 100, 21),
    Item('edtB', 10, 37, 100, 21), Item('lbl', 142, 300, 50, 20)], Rect(0, 0, 400, 400));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Left, mLine));
  Assert.AreEqual(8, mLine.Distance);
  Assert.AreEqual(Ord(TAtlasMeasurePlace.None), Ord(mLine.Same));
end;

procedure TAtlasMeasureTests.SameEdgeGap;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  // Ein Feld oben hat 12 px zum linken Innenrand, der Bezug darunter auch.
  mLines := TAtlasMeasure.Lines(Bounds(12, 100, 80, 20), [Item('edtTop', 12, 10, 80, 20)], Rect(0, 0, 300, 300));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Left, mLine));
  Assert.AreEqual(12, mLine.Distance);
  Assert.AreEqual(Ord(TAtlasMeasurePlace.Above), Ord(mLine.Same));
end;

procedure TAtlasMeasureTests.SizeWithSameNeighbours;
var
  mSize: TAtlasMeasureSize;
begin
  mSize := TAtlasMeasure.Size(Bounds(10, 10, 75, 25), [Item('btnA', 100, 10, 80, 25),
    Item('btnB', 200, 10, 75, 30)]);
  Assert.AreEqual(75, mSize.Width);
  Assert.AreEqual(25, mSize.Height);
  Assert.AreEqual('btnB', mSize.SameWidth);
  Assert.AreEqual('btnA', mSize.SameHeight);
  mSize := TAtlasMeasure.Size(Bounds(0, 0, 10, 10), nil);
  Assert.AreEqual('', mSize.SameWidth);
end;

procedure TAtlasMeasureTests.BetweenApart;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  // Ziel rechts unterhalb: ein waagrechter und ein senkrechter Abstand.
  mLines := TAtlasMeasure.Between(Bounds(10, 10, 50, 20), Bounds(100, 60, 40, 20), 'edtOther');
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Right, mLine));
  Assert.AreEqual(40, mLine.Distance);
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Bottom, mLine));
  Assert.AreEqual(30, mLine.Distance);
  Assert.AreEqual('edtOther', mLine.Target);
end;

procedure TAtlasMeasureTests.BetweenInside;
var
  mLines: TArray<TAtlasMeasureLine>;
  mLine: TAtlasMeasureLine;
begin
  mLines := TAtlasMeasure.Between(Bounds(20, 30, 50, 20), Rect(0, 0, 200, 100), 'pnl');
  Assert.AreEqual(4, Integer(Length(mLines)));
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Right, mLine));
  Assert.AreEqual(130, mLine.Distance);
  Assert.IsTrue(LineOf(mLines, TAtlasMeasureSide.Bottom, mLine));
  Assert.AreEqual(50, mLine.Distance);
end;

procedure TAtlasMeasureTests.CaptionTexts;
var
  mLine: TAtlasMeasureLine;
begin
  mLine := Default(TAtlasMeasureLine);
  mLine.Distance := 8;
  Assert.AreEqual('8 px', TAtlasMeasure.Caption(mLine, ['', 'wie oben', 'wie unten', 'wie links', 'wie rechts']));
  mLine.Same := TAtlasMeasurePlace.Above;
  Assert.AreEqual('8 px wie oben', TAtlasMeasure.Caption(mLine, ['', 'wie oben', 'wie unten', 'wie links',
    'wie rechts']));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMeasureTests);

end.
