unit Atlas.Core.Designer.Wrap.Tests;

// Tests für Einpacken und Auflösen (#733): Rechteck mit Innenrand und
// Beschriftung, Koordinaten hin und zurück, TabOrder, Anchors des
// Containers, GridPanel-Zellen und Verweise im Code.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasContainerWrapTests = class
  public
    [Test]
    procedure ContainerRect;
    [Test]
    procedure CoordinatesRoundTrip;
    [Test]
    procedure TabOrders;
    [Test]
    procedure Anchors;
    [Test]
    procedure GridOfSix;
    [Test]
    procedure CodeReferences;
    [Test]
    procedure Prefixes;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.Anchors,
  Atlas.Core.Designer.Wrap,
  Atlas.Tests.RecordText;

procedure TAtlasContainerWrapTests.ContainerRect;
var
  mRect: TRect;
begin
  mRect := TAtlasContainerWrap.ContainerBounds([Bounds(20, 30, 100, 17), Bounds(20, 55, 120, 17),
    Bounds(20, 80, 90, 17)], 8, 0);
  Assert.AreEqual(12, mRect.Left);
  Assert.AreEqual(22, mRect.Top);
  Assert.AreEqual(148, mRect.Right);
  Assert.AreEqual(105, mRect.Bottom);
  mRect := TAtlasContainerWrap.ContainerBounds([Bounds(20, 30, 100, 17)], 8, 15);
  Assert.AreEqual(7, mRect.Top, 'GroupBox: Beschriftung oben');
end;

procedure TAtlasContainerWrapTests.CoordinatesRoundTrip;
var
  mInside, mBack: TRect;
begin
  mInside := TAtlasContainerWrap.IntoContainer(Bounds(20, 30, 100, 17), Rect(12, 7, 148, 105), Point(2, 15));
  Assert.AreEqual(6, mInside.Left);
  Assert.AreEqual(8, mInside.Top);
  Assert.AreEqual(100, mInside.Width);
  mBack := TAtlasContainerWrap.OutOfContainer(mInside, Rect(12, 7, 148, 105), Point(2, 15));
  Assert.AreEqual(TRecordText.Rect(Bounds(20, 30, 100, 17)), TRecordText.Rect(mBack));
end;

procedure TAtlasContainerWrapTests.TabOrders;
var
  mOrder: TArray<Integer>;
begin
  mOrder := TAtlasContainerWrap.ByTabOrder([5, 2, 9]);
  Assert.AreEqual(1, mOrder[0]);
  Assert.AreEqual(0, mOrder[1]);
  Assert.AreEqual(2, mOrder[2]);
  mOrder := TAtlasContainerWrap.UnwrapTabOrders(3, [2, 0, 1]);
  Assert.AreEqual(5, mOrder[0]);
  Assert.AreEqual(3, mOrder[1]);
  Assert.AreEqual(4, mOrder[2]);
end;

procedure TAtlasContainerWrapTests.Anchors;
const
  cL = TAtlasAnchorSide.Left;
  cT = TAtlasAnchorSide.Top;
  cR = TAtlasAnchorSide.Right;
  cB = TAtlasAnchorSide.Bottom;
begin
  Assert.AreEqual<TAtlasAnchorSet>([cL, cT], TAtlasContainerWrap.ContainerAnchors([[cL, cT], [cL, cT, cR]]));
  Assert.AreEqual<TAtlasAnchorSet>([cR, cB],
    TAtlasContainerWrap.ContainerAnchors([[cR, cB], [cR, cB]]), 'alle unten rechts');
  Assert.AreEqual<TAtlasAnchorSet>([cL, cT, cR], TAtlasContainerWrap.ContainerAnchors([[cL, cT, cR], [cL, cT, cR]]));
  Assert.AreEqual<TAtlasAnchorSet>([cL, cT],
    TAtlasContainerWrap.ContainerAnchors([[cR, cT], [cL, cB]]), 'nichts gemeinsam');
  Assert.AreEqual<TAtlasAnchorSet>([cL, cT], TAtlasContainerWrap.ContainerAnchors([]));
end;

procedure TAtlasContainerWrapTests.GridOfSix;
var
  mCells: TAtlasGridCells;
begin
  mCells := TAtlasContainerWrap.GridCells([Bounds(200, 10, 80, 23), Bounds(10, 12, 80, 23), Bounds(105, 9, 80, 23),
    Bounds(10, 45, 80, 23), Bounds(200, 44, 80, 23), Bounds(105, 46, 80, 23)]);
  Assert.AreEqual(3, mCells.Columns);
  Assert.AreEqual(2, mCells.Rows);
  Assert.AreEqual(1, mCells.Order[0]);
  Assert.AreEqual(2, mCells.Order[1]);
  Assert.AreEqual(0, mCells.Order[2]);
  Assert.AreEqual(3, mCells.Order[3]);
  Assert.AreEqual(5, mCells.Order[4]);
  Assert.AreEqual(4, mCells.Order[5]);
end;

procedure TAtlasContainerWrapTests.CodeReferences;
const
  cSource = 'type' + #13#10 + '  TForm1 = class(TForm)' + #13#10 + '    pnlAdresse: TPanel;' + #13#10 +
    '    pnlAdresseX: TPanel;' + #13#10 + '  end;' + #13#10 + 'begin' + #13#10 + '  // pnlAdresse ausblenden' +
    #13#10 + '  pnlAdresse.Visible := False;' + #13#10 + '  Show(pnlAdressen);' + #13#10 + '  X := PNLADRESSE;';
var
  mLines: TArray<Integer>;
begin
  mLines := TAtlasContainerWrap.References(cSource, 'pnlAdresse');
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.AreEqual(8, mLines[0]);
  Assert.AreEqual(10, mLines[1]);
end;

procedure TAtlasContainerWrapTests.Prefixes;
begin
  Assert.AreEqual('gbx', TAtlasContainerWrap.PrefixFor('TGroupBox'));
  Assert.AreEqual('pnl', TAtlasContainerWrap.PrefixFor('TPanel'));
  Assert.AreEqual('car', TAtlasContainerWrap.PrefixFor('TCardPanel'));
end;

end.
