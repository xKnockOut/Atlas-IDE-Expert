unit Atlas.Core.Designer.InsertSpace.Tests;

// Tests für „Platz einfügen und entfernen“ (#740): Verschieben, Schneiden mit
// und ohne beide Anker, Align-Fälle, Wachsen und Schrumpfen des Parents,
// Entfernen mit Grenze, beide Richtungen und Einrasten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasInsertSpaceTests = class
  public
    [Test]
    procedure InsertMovesRowsBelow;
    [Test]
    procedure CrossingStretchesOnlyWithBothAnchors;
    [Test]
    procedure AlignedStay;
    [Test]
    procedure ParentGrowsOnlyWhenNeeded;
    [Test]
    procedure RemoveStopsAtNextControl;
    [Test]
    procedure RemoveShrinksParent;
    [Test]
    procedure Columns;
    [Test]
    procedure ParentChain;
    [Test]
    procedure SnapToGrid;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.InsertSpace;

const
  cClient: TRect = (Left: 0; Top: 0; Right: 400; Bottom: 300);

function Plain(const ARect: TRect): TAtlasSpaceItem;
begin
  Result := TAtlasSpaceItem.Create(ARect, TAtlasSpaceAlign.None, False);
end;

/// <summary>Drei Zeilen und ein OK-Knopf unten rechts (8 px Rand).</summary>
function Mask: TArray<TAtlasSpaceItem>;
begin
  Result := [Plain(Rect(8, 8, 250, 29)), Plain(Rect(8, 40, 250, 61)), Plain(Rect(8, 72, 250, 93)),
    Plain(Rect(300, 267, 375, 292))];
end;

procedure TAtlasInsertSpaceTests.InsertMovesRowsBelow;
var
  mResult: TAtlasSpaceResult;
begin
  mResult := TAtlasInsertSpace.Apply(Mask, TAtlasSpaceAxis.Rows, 66, 30, cClient, True);
  Assert.AreEqual(40, mResult.Bounds[1].Top, 'darüber bleibt');
  Assert.AreEqual(102, mResult.Bounds[2].Top, 'Zeile 3 um 30');
  Assert.AreEqual(297, mResult.Bounds[3].Top, 'Knopf um 30');
  Assert.AreEqual(300, mResult.Bounds[3].Left, 'waagerecht unverändert');
  Assert.AreEqual(30, mResult.Grow, 'Formular 30 höher');
  Assert.AreEqual(30, mResult.Amount);
end;

procedure TAtlasInsertSpaceTests.CrossingStretchesOnlyWithBothAnchors;
var
  mResult: TAtlasSpaceResult;
begin
  mResult := TAtlasInsertSpace.Apply([TAtlasSpaceItem.Create(Rect(260, 8, 390, 200), TAtlasSpaceAlign.None, True),
    Plain(Rect(8, 50, 80, 80))], TAtlasSpaceAxis.Rows, 66, 30, cClient, False);
  Assert.AreEqual(230, mResult.Bounds[0].Bottom, 'Memo mit akTop+akBottom 30 länger');
  Assert.AreEqual(8, mResult.Bounds[0].Top);
  Assert.AreEqual(50, mResult.Bounds[1].Top, 'Label bleibt');
  Assert.AreEqual(1, Length(mResult.Untouched));
  Assert.AreEqual(1, mResult.Untouched[0], 'und wird genannt');
  Assert.AreEqual(0, mResult.Grow, 'ohne growParent');
end;

procedure TAtlasInsertSpaceTests.AlignedStay;
var
  mResult: TAtlasSpaceResult;
begin
  mResult := TAtlasInsertSpace.Apply([TAtlasSpaceItem.Create(Rect(0, 260, 400, 300), TAtlasSpaceAlign.Far, False),
    TAtlasSpaceItem.Create(Rect(0, 0, 400, 30), TAtlasSpaceAlign.Near, False),
    TAtlasSpaceItem.Create(Rect(0, 30, 100, 260), TAtlasSpaceAlign.Across, False),
    TAtlasSpaceItem.Create(Rect(100, 30, 400, 260), TAtlasSpaceAlign.Fill, False), Plain(Rect(110, 230, 200, 251))],
    TAtlasSpaceAxis.Rows, 100, 20, cClient, True);
  Assert.AreEqual(260, mResult.Bounds[0].Top, 'alBottom bleibt am unteren Rand');
  Assert.AreEqual(0, mResult.Bounds[1].Top);
  Assert.AreEqual(260, mResult.Bounds[2].Bottom, 'quer ausgerichtet ordnet die VCL');
  Assert.AreEqual(260, mResult.Bounds[3].Bottom, 'alClient wächst mit dem Parent');
  Assert.AreEqual(250, mResult.Bounds[4].Top);
  Assert.AreEqual(20, mResult.Grow, 'über alBottom hinaus: Parent wächst');
end;

procedure TAtlasInsertSpaceTests.ParentGrowsOnlyWhenNeeded;
var
  mResult: TAtlasSpaceResult;
begin
  mResult := TAtlasInsertSpace.Apply([Plain(Rect(8, 8, 250, 29)), Plain(Rect(8, 72, 250, 93))], TAtlasSpaceAxis.Rows,
    66, 30, cClient, True);
  Assert.AreEqual(0, mResult.Grow, 'genug Platz');
end;

procedure TAtlasInsertSpaceTests.RemoveStopsAtNextControl;
var
  mResult: TAtlasSpaceResult;
begin
  Assert.AreEqual(-11, TAtlasInsertSpace.Clamp(Mask, TAtlasSpaceAxis.Rows, 72, -30, cClient), 'bis Zeile 2');
  Assert.AreEqual(-5, TAtlasInsertSpace.Clamp(Mask, TAtlasSpaceAxis.Rows, 72, -5, cClient));
  Assert.AreEqual(-20, TAtlasInsertSpace.Clamp([Plain(Rect(8, 20, 80, 40))], TAtlasSpaceAxis.Rows, 20, -50, cClient),
    'ohne Steuerelement davor bis zum Rand');
  mResult := TAtlasInsertSpace.Apply(Mask, TAtlasSpaceAxis.Rows, 72, -30, cClient, False);
  Assert.AreEqual(-11, mResult.Amount);
  Assert.AreEqual(61, mResult.Bounds[2].Top, 'Zeile 3 direkt unter Zeile 2');
end;

procedure TAtlasInsertSpaceTests.RemoveShrinksParent;
var
  mResult: TAtlasSpaceResult;
begin
  mResult := TAtlasInsertSpace.Apply(Mask, TAtlasSpaceAxis.Rows, 72, -10, cClient, True);
  Assert.AreEqual(-10, mResult.Grow, 'Rand 8 kleiner als 10: schrumpft wie nach dem Einfügen');
  mResult := TAtlasInsertSpace.Apply(Mask, TAtlasSpaceAxis.Rows, 72, -5, cClient, True);
  Assert.AreEqual(0, mResult.Grow, 'Rand 8 reicht: bleibt');
end;

procedure TAtlasInsertSpaceTests.Columns;
var
  mResult: TAtlasSpaceResult;
begin
  mResult := TAtlasInsertSpace.Apply([Plain(Rect(8, 8, 80, 29)), Plain(Rect(90, 8, 250, 29)),
    TAtlasSpaceItem.Create(Rect(8, 40, 390, 61), TAtlasSpaceAlign.None, True)], TAtlasSpaceAxis.Columns, 85, 40,
    cClient, True);
  Assert.AreEqual(8, mResult.Bounds[0].Left);
  Assert.AreEqual(130, mResult.Bounds[1].Left, 'rechts davon um 40');
  Assert.AreEqual(430, mResult.Bounds[2].Right, 'mit akLeft+akRight breiter');
  Assert.AreEqual(40, mResult.Grow, 'ragt rechts heraus');
  Assert.AreEqual(-5, TAtlasInsertSpace.Clamp([Plain(Rect(8, 8, 80, 29)), Plain(Rect(85, 8, 250, 29))],
    TAtlasSpaceAxis.Columns, 85, -20, cClient));
end;

procedure TAtlasInsertSpaceTests.ParentChain;
var
  mInner, mOuter: TAtlasSpaceResult;
  mPanel: TRect;
begin
  // Panel (8, 8, 392, 108) mit zwei Zeilen; darunter auf dem Formular ein Knopf.
  mPanel := Rect(8, 8, 392, 108);
  mInner := TAtlasInsertSpace.Apply([Plain(Rect(8, 8, 250, 29)), Plain(Rect(8, 70, 250, 91))], TAtlasSpaceAxis.Rows, 50,
    20, Rect(0, 0, mPanel.Width, mPanel.Height), True);
  Assert.AreEqual(20, mInner.Grow, 'Panel wächst');
  mOuter := TAtlasInsertSpace.Apply([Plain(Rect(8, 120, 83, 145))], TAtlasSpaceAxis.Rows, mPanel.Bottom, mInner.Grow,
    cClient, True);
  Assert.AreEqual(140, mOuter.Bounds[0].Top, 'Knopf unter dem Panel rückt mit');
  Assert.AreEqual(0, mOuter.Grow, 'Formular hat Platz');
end;

procedure TAtlasInsertSpaceTests.SnapToGrid;
begin
  Assert.AreEqual(32, TAtlasInsertSpace.Snap(30, 8));
  Assert.AreEqual(24, TAtlasInsertSpace.Snap(26, 8));
  Assert.AreEqual(30, TAtlasInsertSpace.Snap(30, 1), 'ohne Raster');
end;

end.
