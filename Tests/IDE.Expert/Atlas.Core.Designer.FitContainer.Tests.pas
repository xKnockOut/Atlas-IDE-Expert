unit Atlas.Core.Designer.FitContainer.Tests;

// Tests für „An Inhalt anpassen“ (#742): Rechteck mit Rahmen und
// Beschriftung, Anker rechts und unten, Align des Containers und der Kinder,
// nur alClient, Padding, Constraints, alignTopLeft und gleiche Breite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasFitContainerTests = class
  public
    [Test]
    procedure GroupBoxShrinksToContent;
    [Test]
    procedure RightBottomAnchoredMoveToMargin;
    [Test]
    procedure AlignedContainerKeepsFixedSide;
    [Test]
    procedure OnlyClientChildren;
    [Test]
    procedure AlignedChildrenStack;
    [Test]
    procedure PaddingForAlignedChildren;
    [Test]
    procedure Constraints;
    [Test]
    procedure AlignTopLeft;
    [Test]
    procedure SameWidth;
    [Test]
    procedure ModeOnlyHeight;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.FitContainer;

const
  cTopLeft = [TAtlasFitAnchor.Left, TAtlasFitAnchor.Top];

function Box(AOuterWidth, AOuterHeight, AClientWidth, AClientHeight: Integer): TAtlasFitBox;
begin
  Result.Outer := TSize.Create(AOuterWidth, AOuterHeight);
  Result.Client := TSize.Create(AClientWidth, AClientHeight);
  Result.Inset := Rect(0, 0, 0, 0);
  Result.FreeWidth := True;
  Result.FreeHeight := True;
  Result.MinSize := TSize.Create(0, 0);
  Result.MaxSize := TSize.Create(0, 0);
end;

function Child(const ABounds: TRect): TAtlasFitChild;
begin
  Result := TAtlasFitChild.Create(ABounds, TAtlasFitAlign.None, cTopLeft);
end;

function Options: TAtlasFitOptions;
begin
  Result := TAtlasFitOptions.Create(TAtlasFitMode.Both, 8, False);
end;

procedure TAtlasFitContainerTests.GroupBoxShrinksToContent;
var
  mResult: TAtlasFitResult;
begin
  // GroupBox 270 × 150, Rahmen 2 px; die RadioButtons liegen unter der Beschriftung.
  mResult := TAtlasFitContainer.Fit(Box(270, 150, 266, 146), [Child(Rect(16, 24, 120, 41)),
    Child(Rect(16, 48, 120, 65))], Options);
  Assert.AreEqual(128, mResult.Client.cx);
  Assert.AreEqual(73, mResult.Client.cy);
  Assert.AreEqual(132, mResult.Outer.cx, 'samt Rahmen');
  Assert.AreEqual(77, mResult.Outer.cy);
  Assert.AreEqual(24, mResult.Children[0].Top, 'Lage bleibt');
end;

procedure TAtlasFitContainerTests.RightBottomAnchoredMoveToMargin;
var
  mResult: TAtlasFitResult;
begin
  mResult := TAtlasFitContainer.Fit(Box(500, 400, 500, 400), [Child(Rect(8, 8, 390, 29)),
    TAtlasFitChild.Create(Rect(300, 250, 375, 275), TAtlasFitAlign.None, [TAtlasFitAnchor.Right,
    TAtlasFitAnchor.Bottom])], Options);
  Assert.AreEqual(398, mResult.Client.cx);
  Assert.AreEqual(283, mResult.Client.cy);
  Assert.AreEqual(390, mResult.Children[1].Right, '8 px vom rechten Rand');
  Assert.AreEqual(275, mResult.Children[1].Bottom, '8 px vom unteren Rand');
  Assert.AreEqual(8, mResult.Children[0].Left, 'Feld bleibt');
end;

procedure TAtlasFitContainerTests.AlignedContainerKeepsFixedSide;
var
  mBox: TAtlasFitBox;
  mResult: TAtlasFitResult;
begin
  mBox := Box(400, 120, 400, 120);
  mBox.FreeWidth := False;
  mResult := TAtlasFitContainer.Fit(mBox, [Child(Rect(8, 8, 100, 29))], Options);
  Assert.AreEqual(400, mResult.Outer.cx, 'alTop: Breite bleibt');
  Assert.AreEqual(37, mResult.Outer.cy, 'nur die Höhe');
end;

procedure TAtlasFitContainerTests.OnlyClientChildren;
var
  mResult: TAtlasFitResult;
begin
  mResult := TAtlasFitContainer.Fit(Box(300, 200, 300, 200), [TAtlasFitChild.Create(Rect(0, 0, 300, 200),
    TAtlasFitAlign.Client, cTopLeft)], Options);
  Assert.IsTrue(mResult.OnlyClient);
  Assert.AreEqual(300, mResult.Outer.cx);
  Assert.AreEqual(200, mResult.Outer.cy);
end;

procedure TAtlasFitContainerTests.AlignedChildrenStack;
var
  mResult: TAtlasFitResult;
begin
  mResult := TAtlasFitContainer.Fit(Box(400, 300, 400, 300), [TAtlasFitChild.Create(Rect(0, 0, 400, 30),
    TAtlasFitAlign.Top, cTopLeft), TAtlasFitChild.Create(Rect(0, 260, 400, 300), TAtlasFitAlign.Bottom, cTopLeft),
    Child(Rect(8, 40, 200, 60)), TAtlasFitChild.Create(Rect(0, 0, 400, 300), TAtlasFitAlign.Client, cTopLeft)],
    Options);
  Assert.AreEqual(108, mResult.Client.cy, 'Inhalt 60 + 8 + alBottom 40');
  Assert.AreEqual(208, mResult.Client.cx, 'alTop/alBottom zählen in der Breite nicht');
  Assert.IsFalse(mResult.OnlyClient);
end;

procedure TAtlasFitContainerTests.PaddingForAlignedChildren;
var
  mBox: TAtlasFitBox;
  mResult: TAtlasFitResult;
begin
  mBox := Box(300, 200, 300, 200);
  mBox.Inset := Rect(5, 5, 5, 5);
  mResult := TAtlasFitContainer.Fit(mBox, [TAtlasFitChild.Create(Rect(5, 5, 55, 195), TAtlasFitAlign.Left,
    cTopLeft)], Options);
  Assert.AreEqual(60, mResult.Client.cx, 'alLeft 50 + Padding 5 + 5');
  Assert.AreEqual(200, mResult.Client.cy, 'Höhe bestimmt nichts');
end;

procedure TAtlasFitContainerTests.Constraints;
var
  mBox: TAtlasFitBox;
  mResult: TAtlasFitResult;
begin
  mBox := Box(300, 200, 300, 200);
  mBox.MinSize := TSize.Create(200, 0);
  mBox.MaxSize := TSize.Create(0, 30);
  mResult := TAtlasFitContainer.Fit(mBox, [Child(Rect(8, 8, 100, 29)), Child(Rect(8, 40, 100, 61))], Options);
  Assert.AreEqual(200, mResult.Outer.cx, 'MinWidth');
  Assert.AreEqual(30, mResult.Outer.cy, 'MaxHeight');
end;

procedure TAtlasFitContainerTests.AlignTopLeft;
var
  mResult: TAtlasFitResult;
begin
  mResult := TAtlasFitContainer.Fit(Box(300, 200, 300, 200), [Child(Rect(30, 40, 130, 61)),
    Child(Rect(50, 70, 150, 91))], TAtlasFitOptions.Create(TAtlasFitMode.Both, 8, True));
  Assert.AreEqual(8, mResult.Children[0].Left);
  Assert.AreEqual(8, mResult.Children[0].Top);
  Assert.AreEqual(28, mResult.Children[1].Left, 'Abstände bleiben');
  Assert.AreEqual(136, mResult.Client.cx, '128 + 8');
  Assert.AreEqual(67, mResult.Client.cy, '59 + 8');
end;

procedure TAtlasFitContainerTests.SameWidth;
var
  mResults: TArray<TAtlasFitResult>;
  mOptions: TAtlasFitOptions;
begin
  mResults := [TAtlasFitContainer.Fit(Box(300, 100, 296, 96), [Child(Rect(8, 8, 92, 29))], Options),
    TAtlasFitContainer.Fit(Box(300, 100, 296, 96), [Child(Rect(8, 8, 142, 29))], Options),
    TAtlasFitContainer.Fit(Box(300, 100, 296, 96), [Child(Rect(8, 8, 112, 29))], Options)];
  Assert.AreEqual(154, TAtlasFitContainer.MaxOuterWidth(mResults), '142 + 8 + Rahmen 4');
  mOptions := Options;
  mOptions.ForceOuterWidth := TAtlasFitContainer.MaxOuterWidth(mResults);
  Assert.AreEqual(154, TAtlasFitContainer.Fit(Box(300, 100, 296, 96), [Child(Rect(8, 8, 92, 29))],
    mOptions).Outer.cx);
end;

procedure TAtlasFitContainerTests.ModeOnlyHeight;
var
  mResult: TAtlasFitResult;
begin
  mResult := TAtlasFitContainer.Fit(Box(300, 200, 300, 200), [Child(Rect(8, 8, 100, 29)),
    TAtlasFitChild.Create(Rect(200, 150, 290, 175), TAtlasFitAlign.None, [TAtlasFitAnchor.Right,
    TAtlasFitAnchor.Bottom])], TAtlasFitOptions.Create(TAtlasFitMode.Height, 8, False));
  Assert.AreEqual(300, mResult.Outer.cx, 'Breite bleibt');
  Assert.AreEqual(183, mResult.Outer.cy);
  Assert.AreEqual(290, mResult.Children[1].Right, 'rechts nicht verschoben');
end;

end.
