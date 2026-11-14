unit Atlas.Core.Designer.Layout.Tests;

// Tests für die Layoutberechnung der Probegröße (#606): Anchors, Align in der
// Reihenfolge der VCL, Margins und Padding, Constraints, Lage im Formular und
// die Befunde (herausragend, zu klein, Überlappung, zwei alClient, Anchors bei
// Align). Erwartete Werte wie die VCL sie zur Laufzeit liefert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFormLayoutTests = class
  public
    [Test]
    procedure AnchorsLeftTopStay;
    [Test]
    procedure AnchorsRightMoves;
    [Test]
    procedure AnchorsBothStretch;
    [Test]
    procedure NoAnchorsKeepCenter;
    [Test]
    procedure AlignOrder;
    [Test]
    procedure AlignWithMarginsAndPadding;
    [Test]
    procedure NestedPanelGrows;
    [Test]
    procedure ConstraintsLimit;
    [Test]
    procedure ButtonSticksOut;
    [Test]
    procedure TooSmallAndOverlap;
    [Test]
    procedure Conflicts;
    [Test]
    procedure InFormAddsParents;
    [Test]
    procedure ParseSizes;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.Layout,
  Atlas.Tests.RecordText;

function Node(const AName: string; AParent, ALeft, ATop, AWidth, AHeight: Integer): TAtlasLayoutNode;
begin
  Result := TAtlasLayoutNode.Create(AName, 'TControl', AParent, Bounds(ALeft, ATop, AWidth, AHeight));
end;

function Aligned(const AName: string; AParent: Integer; AAlign: TAtlasLayoutAlign;
  const ABounds: TRect): TAtlasLayoutNode;
begin
  Result := Node(AName, AParent, ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height);
  Result.Align := AAlign;
end;

function Has(const AFindings: TArray<TAtlasLayoutFinding>; ANode: Integer; AProblem: TAtlasLayoutProblem;
  out AFinding: TAtlasLayoutFinding): Boolean;
var
  mFinding: TAtlasLayoutFinding;
begin
  for mFinding in AFindings do
  begin
    if (mFinding.Node = ANode) and (mFinding.Problem = AProblem) then
    begin
      AFinding := mFinding;
      Exit(True);
    end;
  end;
  AFinding := Default(TAtlasLayoutFinding);
  Result := False;
end;

procedure AssertRect(const AExpected, AActual: TRect; const AMessage: string); overload;
begin
  Assert.AreEqual(TRecordText.Rect(AExpected), TRecordText.Rect(AActual), AMessage);
end;

procedure AssertRect(const AExpected, AActual: TRect); overload;
begin
  AssertRect(AExpected, AActual, '');
end;

{ TAtlasFormLayoutTests }

procedure TAtlasFormLayoutTests.AnchorsLeftTopStay;
var
  mNew: TArray<TRect>;
begin
  mNew := TAtlasFormLayout.Arrange([Node('btn', -1, 500, 300, 75, 25)], TSize.Create(800, 600),
    TSize.Create(600, 400));
  Assert.AreEqual(500, mNew[0].Left);
  Assert.AreEqual(300, mNew[0].Top);
end;

procedure TAtlasFormLayoutTests.AnchorsRightMoves;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
begin
  mNodes := [Node('btnOk', -1, 700, 560, 75, 25)];
  mNodes[0].Anchors := [TAtlasLayoutAnchor.Right, TAtlasLayoutAnchor.Bottom];
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(800, 600), TSize.Create(600, 400));
  Assert.AreEqual(500, mNew[0].Left);
  Assert.AreEqual(360, mNew[0].Top);
  Assert.AreEqual(75, mNew[0].Width);
end;

procedure TAtlasFormLayoutTests.AnchorsBothStretch;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
begin
  mNodes := [Node('edt', -1, 10, 10, 780, 21)];
  mNodes[0].Anchors := [TAtlasLayoutAnchor.Left, TAtlasLayoutAnchor.Top, TAtlasLayoutAnchor.Right];
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(800, 600), TSize.Create(1000, 600));
  Assert.AreEqual(10, mNew[0].Left);
  Assert.AreEqual(980, mNew[0].Width);
end;

procedure TAtlasFormLayoutTests.NoAnchorsKeepCenter;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
begin
  mNodes := [Node('lbl', -1, 350, 290, 100, 20)];
  mNodes[0].Anchors := [];
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(800, 600), TSize.Create(1000, 800));
  Assert.AreEqual(450, mNew[0].Left);
  Assert.AreEqual(390, mNew[0].Top);
end;

procedure TAtlasFormLayoutTests.AlignOrder;
var
  mNew: TArray<TRect>;
begin
  // Zwei alTop untereinander, ein alBottom, ein alLeft, ein alClient im Rest.
  mNew := TAtlasFormLayout.Arrange([Aligned('pnlTop2', -1, TAtlasLayoutAlign.Top, Bounds(0, 40, 800, 30)),
    Aligned('pnlTop1', -1, TAtlasLayoutAlign.Top, Bounds(0, 0, 800, 40)),
    Aligned('pnlBottom', -1, TAtlasLayoutAlign.Bottom, Bounds(0, 560, 800, 40)),
    Aligned('tree', -1, TAtlasLayoutAlign.Left, Bounds(0, 70, 200, 490)),
    Aligned('memo', -1, TAtlasLayoutAlign.Client, Bounds(200, 70, 600, 490))], TSize.Create(800, 600),
    TSize.Create(600, 400));
  Assert.AreEqual(0, mNew[1].Top, 'pnlTop1 zuerst, weil weiter oben');
  Assert.AreEqual(40, mNew[0].Top);
  Assert.AreEqual(600, mNew[0].Width);
  Assert.AreEqual(360, mNew[2].Top, 'alBottom bleibt unten');
  Assert.AreEqual(70, mNew[3].Top);
  Assert.AreEqual(290, mNew[3].Height);
  AssertRect(Rect(200, 70, 600, 360), mNew[4], 'alClient wächst mit');
end;

procedure TAtlasFormLayoutTests.AlignWithMarginsAndPadding;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
begin
  mNodes := [Node('pnl', -1, 0, 0, 400, 300), Aligned('memo', 0, TAtlasLayoutAlign.Client, Bounds(0, 0, 400, 300))];
  mNodes[0].Padding := Rect(4, 4, 4, 4);
  mNodes[1].AlignWithMargins := True;
  mNodes[1].Margins := Rect(3, 3, 3, 3);
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(800, 600), TSize.Create(800, 600));
  AssertRect(Rect(7, 7, 393, 293), mNew[1]);
end;

procedure TAtlasFormLayoutTests.NestedPanelGrows;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
begin
  // Panel alClient mit Rahmen (1 px), darin ein Knopf rechts unten verankert.
  mNodes := [Aligned('pnl', -1, TAtlasLayoutAlign.Client, Bounds(0, 0, 800, 600)), Node('btn', 0, 700, 560, 75, 25)];
  mNodes[0].Inset := Rect(1, 1, 1, 1);
  mNodes[1].Anchors := [TAtlasLayoutAnchor.Right, TAtlasLayoutAnchor.Bottom];
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(800, 600), TSize.Create(1000, 700));
  Assert.AreEqual(1000, mNew[0].Width);
  Assert.AreEqual(900, mNew[1].Left);
  Assert.AreEqual(660, mNew[1].Top);
  AssertRect(Rect(901, 661, 976, 686), TAtlasFormLayout.InForm(mNodes, mNew, 1));
end;

procedure TAtlasFormLayoutTests.ConstraintsLimit;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
  mSize: TSize;
begin
  mNodes := [Node('edt', -1, 10, 10, 300, 21)];
  mNodes[0].Anchors := [TAtlasLayoutAnchor.Left, TAtlasLayoutAnchor.Top, TAtlasLayoutAnchor.Right];
  mNodes[0].MinWidth := 200;
  mNodes[0].MaxWidth := 400;
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(400, 300), TSize.Create(200, 300));
  Assert.AreEqual(200, mNew[0].Width, 'MinWidth');
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(400, 300), TSize.Create(900, 300));
  Assert.AreEqual(400, mNew[0].Width, 'MaxWidth');
  mSize := TAtlasFormLayout.Constrain(TSize.Create(300, 100), 400, 200, 0, 0);
  Assert.AreEqual(400, mSize.cx);
  Assert.AreEqual(200, mSize.cy);
end;

procedure TAtlasFormLayoutTests.ButtonSticksOut;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
  mFinding: TAtlasLayoutFinding;
begin
  // Akzeptanzkriterium: 600 × 400, Knopf am rechten Rand nur links oben verankert.
  mNodes := [Node('btnRight', -1, 700, 10, 75, 25)];
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(800, 600), TSize.Create(600, 400));
  Assert.IsTrue(Has(TAtlasFormLayout.Problems(mNodes, mNew, TSize.Create(600, 400)), 0,
    TAtlasLayoutProblem.OutRight, mFinding));
  Assert.AreEqual(175, mFinding.Amount);
end;

procedure TAtlasFormLayoutTests.TooSmallAndOverlap;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mNew: TArray<TRect>;
  mFindings: TArray<TAtlasLayoutFinding>;
  mFinding: TAtlasLayoutFinding;
begin
  mNodes := [Node('memo', -1, 10, 10, 300, 200), Node('btn', -1, 320, 10, 75, 25)];
  mNodes[0].Anchors := [TAtlasLayoutAnchor.Left, TAtlasLayoutAnchor.Top, TAtlasLayoutAnchor.Right,
    TAtlasLayoutAnchor.Bottom];
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(400, 300), TSize.Create(500, 300));
  mFindings := TAtlasFormLayout.Problems(mNodes, mNew, TSize.Create(500, 300));
  Assert.IsTrue(Has(mFindings, 1, TAtlasLayoutProblem.Overlap, mFinding), 'Memo wächst über den Knopf');
  Assert.AreEqual('memo', mFinding.Other);
  mNew := TAtlasFormLayout.Arrange(mNodes, TSize.Create(400, 300), TSize.Create(80, 300));
  mFindings := TAtlasFormLayout.Problems(mNodes, mNew, TSize.Create(80, 300));
  Assert.IsTrue(Has(mFindings, 0, TAtlasLayoutProblem.TooSmall, mFinding), 'Breite ≤ 0');
end;

procedure TAtlasFormLayoutTests.Conflicts;
var
  mNodes: TArray<TAtlasLayoutNode>;
  mFindings: TArray<TAtlasLayoutFinding>;
  mFinding: TAtlasLayoutFinding;
begin
  mNodes := [Node('pnl', -1, 0, 0, 400, 300), Aligned('memoA', 0, TAtlasLayoutAlign.Client, Bounds(0, 0, 400, 300)),
    Aligned('memoB', 0, TAtlasLayoutAlign.Client, Bounds(0, 0, 400, 300)),
    Aligned('pnlTop', -1, TAtlasLayoutAlign.Top, Bounds(0, 0, 400, 30))];
  mNodes[3].Anchors := [TAtlasLayoutAnchor.Left, TAtlasLayoutAnchor.Top, TAtlasLayoutAnchor.Right,
    TAtlasLayoutAnchor.Bottom];
  mFindings := TAtlasFormLayout.Problems(mNodes, TAtlasFormLayout.Arrange(mNodes, TSize.Create(400, 300),
    TSize.Create(400, 300)), TSize.Create(400, 300));
  Assert.IsTrue(Has(mFindings, 2, TAtlasLayoutProblem.TwoClient, mFinding));
  Assert.AreEqual('memoA', mFinding.Other);
  Assert.IsTrue(Has(mFindings, 3, TAtlasLayoutProblem.AnchorsWithAlign, mFinding));
  Assert.IsFalse(Has(mFindings, 1, TAtlasLayoutProblem.AnchorsWithAlign, mFinding), 'alClient mit allen Anchors');
end;

procedure TAtlasFormLayoutTests.InFormAddsParents;
var
  mNodes: TArray<TAtlasLayoutNode>;
begin
  mNodes := [Node('grp', -1, 10, 20, 200, 100), Node('edt', 0, 8, 18, 100, 21)];
  mNodes[0].Inset := Rect(2, 15, 2, 2);
  AssertRect(Rect(20, 53, 120, 74), TAtlasFormLayout.InForm(mNodes, [mNodes[0].Bounds, mNodes[1].Bounds], 1));
end;

procedure TAtlasFormLayoutTests.ParseSizes;
var
  mSizes: TArray<TSize>;
begin
  mSizes := TAtlasFormLayout.ParseSizes('1366x768, 1920 × 1080; kaputt, 0x5, 800X600');
  Assert.AreEqual(3, Integer(Length(mSizes)));
  Assert.AreEqual(1366, mSizes[0].cx);
  Assert.AreEqual(1080, mSizes[1].cy);
  Assert.AreEqual(800, mSizes[2].cx);
  Assert.AreEqual(0, Integer(Length(TAtlasFormLayout.ParseSizes(''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormLayoutTests);

end.
