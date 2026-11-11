unit Atlas.Core.Designer.NearAlign.Tests;

// Tests für fast bündige Kanten (#746): linke, rechte, obere und untere Kante,
// Grundlinie, Mehrheit und Gleichstand, Toleranz, Abstand quer zur Kante,
// Ausnahmen, Skip, Beheben und die Ausnahmen als JSON.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasNearAlignTests = class
  public
    [Test]
    procedure LeftMajorityWins;
    [Test]
    procedure RightOneOff;
    [Test]
    procedure OutsideTolerance;
    [Test]
    procedure ExactIsNotReported;
    [Test]
    procedure TieTakesOlder;
    [Test]
    procedure FarApartIgnored;
    [Test]
    procedure TopAndBottomInRow;
    [Test]
    procedure BaselineOnlyWhenOn;
    [Test]
    procedure ExceptionsAndSkip;
    [Test]
    procedure FixMovesAndResizes;
    [Test]
    procedure FixBaselineYieldsToTop;
    [Test]
    procedure ExceptionsJson;
    [Test]
    procedure ExceptionsRemoveNames;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Designer.NearAlign;

function Item(const AName: string; ALeft, ATop, AWidth, AHeight: Integer): TAtlasAlignItem;
begin
  Result := TAtlasAlignItem.Create(AName, Bounds(ALeft, ATop, AWidth, AHeight), -1, False);
end;

function Count(const AFindings: TArray<TAtlasNearFinding>; AEdge: TAtlasEdge): Integer;
var
  mFinding: TAtlasNearFinding;
begin
  Result := 0;
  for mFinding in AFindings do
  begin
    if mFinding.Edge = AEdge then
    begin
      Inc(Result);
    end;
  end;
end;

function FindingOf(const AFindings: TArray<TAtlasNearFinding>; AItem: Integer; AEdge: TAtlasEdge;
  out AFinding: TAtlasNearFinding): Boolean;
var
  mFinding: TAtlasNearFinding;
begin
  for mFinding in AFindings do
  begin
    if (mFinding.Item = AItem) and (mFinding.Edge = AEdge) then
    begin
      AFinding := mFinding;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Drei Edits untereinander, Breite 200.</summary>
function Column(ALeft1, ALeft2, ALeft3: Integer): TArray<TAtlasAlignItem>;
begin
  Result := [Item('edtName', ALeft1, 10, 200, 21), Item('edtFax', ALeft2, 40, 200, 21),
    Item('edtMail', ALeft3, 70, 200, 21)];
end;

procedure TAtlasNearAlignTests.LeftMajorityWins;
var
  mFindings: TArray<TAtlasNearFinding>;
  mFinding: TAtlasNearFinding;
begin
  mFindings := TAtlasNearAlign.Find(Column(90, 92, 90), 3, True, nil);
  Assert.AreEqual(1, Count(mFindings, TAtlasEdge.Left));
  Assert.IsTrue(FindingOf(mFindings, 1, TAtlasEdge.Left, mFinding));
  Assert.AreEqual(92, mFinding.Value);
  Assert.AreEqual(90, mFinding.Target);
  Assert.AreEqual(-2, mFinding.Offset);
end;

procedure TAtlasNearAlignTests.RightOneOff;
var
  mItems: TArray<TAtlasAlignItem>;
  mFindings: TArray<TAtlasNearFinding>;
  mFinding: TAtlasNearFinding;
begin
  mItems := Column(90, 90, 90);
  mItems[2].Bounds.Right := 289;
  mFindings := TAtlasNearAlign.Find(mItems, 3, True, nil);
  Assert.AreEqual(1, Length(mFindings));
  Assert.IsTrue(FindingOf(mFindings, 2, TAtlasEdge.Right, mFinding));
  Assert.AreEqual(290, mFinding.Target);
end;

procedure TAtlasNearAlignTests.OutsideTolerance;
begin
  Assert.AreEqual(0, Length(TAtlasNearAlign.Find(Column(90, 94, 90), 3, True, nil)));
  Assert.AreEqual(2, Length(TAtlasNearAlign.Find(Column(90, 94, 90), 4, True, nil)));
end;

procedure TAtlasNearAlignTests.ExactIsNotReported;
begin
  Assert.AreEqual(0, Length(TAtlasNearAlign.Find(Column(90, 90, 90), 3, True, nil)));
end;

procedure TAtlasNearAlignTests.TieTakesOlder;
var
  mFindings: TArray<TAtlasNearFinding>;
  mFinding: TAtlasNearFinding;
begin
  // Zwei Edits mit 90 und 92: das ältere (Index 0) gibt die Flucht vor.
  mFindings := TAtlasNearAlign.Find([Item('a', 90, 10, 100, 21), Item('b', 92, 40, 98, 21)], 3, True, nil);
  Assert.AreEqual(1, Count(mFindings, TAtlasEdge.Left));
  Assert.IsTrue(FindingOf(mFindings, 1, TAtlasEdge.Left, mFinding));
  Assert.AreEqual(90, mFinding.Target);
end;

procedure TAtlasNearAlignTests.FarApartIgnored;
begin
  Assert.AreEqual(0, Length(TAtlasNearAlign.Find([Item('a', 90, 10, 100, 21), Item('b', 92, 400, 98, 21)], 3,
    True, nil)));
end;

procedure TAtlasNearAlignTests.TopAndBottomInRow;
var
  mFindings: TArray<TAtlasNearFinding>;
  mFinding: TAtlasNearFinding;
begin
  // Drei Knöpfe nebeneinander, der mittlere 1 Pixel tiefer.
  mFindings := TAtlasNearAlign.Find([Item('b1', 10, 100, 75, 25), Item('b2', 90, 101, 75, 25),
    Item('b3', 170, 100, 75, 25)], 3, True, nil);
  Assert.IsTrue(FindingOf(mFindings, 1, TAtlasEdge.Top, mFinding));
  Assert.AreEqual(-1, mFinding.Offset);
  Assert.IsTrue(FindingOf(mFindings, 1, TAtlasEdge.Bottom, mFinding));
  Assert.AreEqual(125, mFinding.Target);
  Assert.AreEqual(2, Length(mFindings));
end;

procedure TAtlasNearAlignTests.BaselineOnlyWhenOn;
var
  mItems: TArray<TAtlasAlignItem>;
  mFinding: TAtlasNearFinding;
begin
  // Label und Edit nebeneinander: Ober- und Unterkanten weit auseinander, Grundlinie 1 daneben.
  mItems := [TAtlasAlignItem.Create('lblName', Bounds(10, 15, 40, 11), 25, False),
    TAtlasAlignItem.Create('edtName', Bounds(60, 10, 100, 21), 26, False)];
  Assert.AreEqual(0, Length(TAtlasNearAlign.Find(mItems, 3, False, nil)));
  Assert.IsTrue(FindingOf(TAtlasNearAlign.Find(mItems, 3, True, nil), 1, TAtlasEdge.Baseline, mFinding));
  Assert.AreEqual(25, mFinding.Target);
end;

procedure TAtlasNearAlignTests.ExceptionsAndSkip;
var
  mItems: TArray<TAtlasAlignItem>;
begin
  mItems := Column(90, 92, 90);
  Assert.AreEqual(0, Length(TAtlasNearAlign.Find(mItems, 3, True, ['EDTFAX.left', 'edtFax.right'])));
  mItems[1].Skip := True;
  Assert.AreEqual(0, Length(TAtlasNearAlign.Find(mItems, 3, True, nil)));
  Assert.AreEqual('edtFax.left', TAtlasNearAlign.KeyOf('edtFax', TAtlasEdge.Left));
end;

procedure TAtlasNearAlignTests.FixMovesAndResizes;
var
  mItems: TArray<TAtlasAlignItem>;
  mRects: TArray<TRect>;
begin
  // edtFax 2 zu weit rechts und dabei rechts bündig: verschieben, dann die Breite auf die Flucht.
  mItems := Column(90, 92, 90);
  mItems[1].Bounds.Right := 289;
  mRects := TAtlasNearAlign.FixAll(mItems, TAtlasNearAlign.Find(mItems, 3, True, nil));
  Assert.AreEqual(90, mRects[1].Left);
  Assert.AreEqual(290, mRects[1].Right);
  Assert.AreEqual(40, mRects[1].Top);
  Assert.IsTrue(mRects[0] = mItems[0].Bounds);
end;

procedure TAtlasNearAlignTests.FixBaselineYieldsToTop;
var
  mItems: TArray<TAtlasAlignItem>;
  mRects: TArray<TRect>;
begin
  mItems := [TAtlasAlignItem.Create('a', Bounds(10, 10, 60, 21), 26, False),
    TAtlasAlignItem.Create('b', Bounds(80, 11, 60, 21), 28, False),
    TAtlasAlignItem.Create('c', Bounds(150, 10, 60, 21), 26, False)];
  mRects := TAtlasNearAlign.FixAll(mItems, TAtlasNearAlign.Find(mItems, 3, True, nil));
  Assert.AreEqual(10, mRects[1].Top);
  Assert.AreEqual(31, mRects[1].Bottom);
end;

procedure TAtlasNearAlignTests.ExceptionsJson;
var
  mExceptions, mLoaded: TAtlasNearExceptions;
begin
  mExceptions := TAtlasNearExceptions.Create;
  mLoaded := TAtlasNearExceptions.Create;
  try
    mExceptions.Add('Form1.dfm', ['edtFax.left', 'edtFax.left', 'btnOk.top']);
    Assert.IsTrue(mExceptions.Changed);
    Assert.AreEqual(2, Length(mExceptions.Keys('FORM1.DFM')));
    Assert.IsTrue(mLoaded.LoadJson(mExceptions.ToJson));
    Assert.AreEqual(2, Length(mLoaded.Keys('form1.dfm')));
    Assert.AreEqual('btnOk.top', mLoaded.Keys('Form1.dfm')[1]);
    Assert.IsFalse(mLoaded.Changed);
    Assert.IsFalse(mLoaded.LoadJson('kein json'));
    Assert.AreEqual(0, Length(mLoaded.Keys('Form1.dfm')));
  finally
    mLoaded.Free;
    mExceptions.Free;
  end;
end;

procedure TAtlasNearAlignTests.ExceptionsRemoveNames;
var
  mExceptions: TAtlasNearExceptions;
begin
  mExceptions := TAtlasNearExceptions.Create;
  try
    mExceptions.Add('Form1.dfm', ['edtFax.left', 'edtFax.right', 'edtFaxNr.top', 'btnOk.top']);
    mExceptions.Changed := False;
    Assert.AreEqual(2, mExceptions.RemoveNames('Form1.dfm', ['edtFax']));
    Assert.IsTrue(mExceptions.Changed);
    Assert.AreEqual(2, Length(mExceptions.Keys('Form1.dfm')));
    Assert.AreEqual(0, mExceptions.RemoveNames('Form2.dfm', ['edtFax']));
  finally
    mExceptions.Free;
  end;
end;

end.
