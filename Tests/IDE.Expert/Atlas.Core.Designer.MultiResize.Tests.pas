unit Atlas.Core.Designer.MultiResize.Tests;

// Tests der gemeinsamen Größengriffe im Designer (#737): beide Modi, alle
// Kanten, Mindestgrößen, AutoSize/Align (Fixed), Raster und Nachbarn.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Designer.MultiResize;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasMultiResizeTests = class
  private
    FColumn: TArray<TAtlasResizeItem>;
    function Run(ADragged: Integer; AEdge: TAtlasResizeEdge; ADX, ADY: Integer;
      AMode: TAtlasResizeMode = TAtlasResizeMode.Delta; AGrid: Integer = 0): TAtlasResizeResult;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RightEdgeDeltaWidensAll;
    [Test]
    procedure AlignGivesSameRightEdge;
    [Test]
    procedure BottomAndCorner;
    [Test]
    procedure LeftEdgeKeepsRight;
    [Test]
    procedure TopEdgeKeepsBottom;
    [Test]
    procedure MinimumStopsOne;
    [Test]
    procedure FixedStays;
    [Test]
    procedure SnapsToGrid;
    [Test]
    procedure NeighbourFollows;
    [Test]
    procedure NeighbourOtherGroupStays;
    [Test]
    procedure OppositeAndMode;
  end;

implementation

procedure TAtlasMultiResizeTests.Setup;
begin
  // Drei Edits untereinander, 180 px breit.
  FColumn := [TAtlasResizeItem.Create(Rect(10, 10, 190, 31), 0, 0, False, 0),
    TAtlasResizeItem.Create(Rect(10, 40, 190, 61), 0, 0, False, 0),
    TAtlasResizeItem.Create(Rect(10, 70, 190, 91), 0, 0, False, 0)];
end;

procedure TAtlasMultiResizeTests.TearDown;
begin
  FColumn := nil;
end;

function TAtlasMultiResizeTests.Run(ADragged: Integer; AEdge: TAtlasResizeEdge; ADX, ADY: Integer;
  AMode: TAtlasResizeMode; AGrid: Integer): TAtlasResizeResult;
begin
  Result := TAtlasMultiResize.Apply(FColumn, nil, ADragged, AEdge, Point(ADX, ADY), AMode, AGrid, False);
end;

procedure TAtlasMultiResizeTests.RightEdgeDeltaWidensAll;
var
  mResult: TAtlasResizeResult;
  mRect: TRect;
begin
  mResult := Run(1, TAtlasResizeEdge.Right, 80, 5);
  for mRect in mResult.Items do
  begin
    Assert.AreEqual(260, mRect.Width);
    Assert.AreEqual(21, mRect.Height, 'Höhe bleibt bei rechter Kante');
  end;
  Assert.AreEqual(3, mResult.Changed);
end;

procedure TAtlasMultiResizeTests.AlignGivesSameRightEdge;
var
  mResult: TAtlasResizeResult;
begin
  FColumn[0].Bounds.Right := 150;
  FColumn[2].Bounds.Left := 40;
  mResult := Run(1, TAtlasResizeEdge.Right, 20, 0, TAtlasResizeMode.Align);
  Assert.AreEqual(210, mResult.Items[0].Right);
  Assert.AreEqual(210, mResult.Items[1].Right);
  Assert.AreEqual(210, mResult.Items[2].Right);
  Assert.AreEqual(40, mResult.Items[2].Left);
end;

procedure TAtlasMultiResizeTests.BottomAndCorner;
var
  mResult: TAtlasResizeResult;
begin
  mResult := Run(0, TAtlasResizeEdge.Bottom, 30, 4);
  Assert.AreEqual(25, mResult.Items[2].Height);
  Assert.AreEqual(180, mResult.Items[2].Width);
  mResult := Run(0, TAtlasResizeEdge.Corner, 10, 4);
  Assert.AreEqual(190, mResult.Items[1].Width);
  Assert.AreEqual(25, mResult.Items[1].Height);
end;

procedure TAtlasMultiResizeTests.LeftEdgeKeepsRight;
var
  mResult: TAtlasResizeResult;
begin
  mResult := Run(0, TAtlasResizeEdge.Left, -10, 0);
  Assert.AreEqual(0, mResult.Items[2].Left);
  Assert.AreEqual(190, mResult.Items[2].Right);
end;

procedure TAtlasMultiResizeTests.TopEdgeKeepsBottom;
var
  mResult: TAtlasResizeResult;
begin
  mResult := Run(0, TAtlasResizeEdge.Top, 0, 3);
  Assert.AreEqual(43, mResult.Items[1].Top);
  Assert.AreEqual(61, mResult.Items[1].Bottom);
end;

procedure TAtlasMultiResizeTests.MinimumStopsOne;
var
  mResult: TAtlasResizeResult;
begin
  FColumn[0].Bounds.Right := 40;
  FColumn[1].MinWidth := 100;
  mResult := Run(2, TAtlasResizeEdge.Right, -120, 0);
  Assert.AreEqual(8, mResult.Items[0].Width, 'Vorgabe 8 px');
  Assert.AreEqual(100, mResult.Items[1].Width, 'Constraints.MinWidth');
  Assert.AreEqual(60, mResult.Items[2].Width, 'zieht weiter mit');
end;

procedure TAtlasMultiResizeTests.FixedStays;
var
  mResult: TAtlasResizeResult;
begin
  FColumn[1].Fixed := True;
  mResult := Run(0, TAtlasResizeEdge.Right, 80, 0);
  Assert.AreEqual(180, mResult.Items[1].Width);
  Assert.AreEqual(260, mResult.Items[2].Width);
  Assert.AreEqual(2, mResult.Changed);
end;

procedure TAtlasMultiResizeTests.SnapsToGrid;
var
  mResult: TAtlasResizeResult;
begin
  // Rechte Kante 190 + 13 = 203 rastet bei Raster 8 auf 200.
  mResult := Run(0, TAtlasResizeEdge.Right, 13, 0, TAtlasResizeMode.Delta, 8);
  Assert.AreEqual(200, mResult.Items[0].Right);
  Assert.AreEqual(200, mResult.Items[2].Right);
end;

procedure TAtlasMultiResizeTests.NeighbourFollows;
var
  mResult: TAtlasResizeResult;
begin
  // Knopf rechts neben dem mittleren Edit mit 8 px Abstand; einer weit unten bleibt.
  mResult := TAtlasMultiResize.Apply(FColumn, [TAtlasResizeNeighbour.Create(Rect(198, 38, 273, 63), 0),
    TAtlasResizeNeighbour.Create(Rect(198, 200, 273, 225), 0)], 0, TAtlasResizeEdge.Right, Point(40, 0),
    TAtlasResizeMode.Delta, 0, True);
  Assert.AreEqual(238, mResult.Neighbours[0].Left);
  Assert.AreEqual(8, mResult.Neighbours[0].Left - mResult.Items[1].Right, 'Abstand bleibt');
  Assert.AreEqual(198, mResult.Neighbours[1].Left);
  mResult := TAtlasMultiResize.Apply(FColumn, [TAtlasResizeNeighbour.Create(Rect(198, 38, 273, 63), 0)], 0,
    TAtlasResizeEdge.Right, Point(40, 0), TAtlasResizeMode.Delta, 0, False);
  Assert.AreEqual(198, mResult.Neighbours[0].Left, 'ohne Umschalt');
end;

procedure TAtlasMultiResizeTests.NeighbourOtherGroupStays;
var
  mResult: TAtlasResizeResult;
begin
  mResult := TAtlasMultiResize.Apply(FColumn, [TAtlasResizeNeighbour.Create(Rect(198, 38, 273, 63), 1)], 0,
    TAtlasResizeEdge.Right, Point(40, 0), TAtlasResizeMode.Delta, 0, True);
  Assert.AreEqual(198, mResult.Neighbours[0].Left);
end;

procedure TAtlasMultiResizeTests.OppositeAndMode;
begin
  Assert.AreEqual(Ord(TAtlasResizeEdge.Left), Ord(TAtlasMultiResize.Opposite(TAtlasResizeEdge.Right)));
  Assert.AreEqual(Ord(TAtlasResizeEdge.Top), Ord(TAtlasMultiResize.Opposite(TAtlasResizeEdge.Bottom)));
  Assert.AreEqual(Ord(TAtlasResizeEdge.Corner), Ord(TAtlasMultiResize.Opposite(TAtlasResizeEdge.Corner)));
  Assert.AreEqual(Ord(TAtlasResizeMode.Align), Ord(TAtlasMultiResize.ModeOf('Align')));
  Assert.AreEqual(Ord(TAtlasResizeMode.Delta), Ord(TAtlasMultiResize.ModeOf('x')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMultiResizeTests);

end.
