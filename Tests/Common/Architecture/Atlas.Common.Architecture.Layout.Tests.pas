unit Atlas.Common.Architecture.Layout.Tests;

// Tests der Kartenanordnung (#1118): zentrale Unit in der Mitte ihres
// Teilsystems, Teilsysteme ohne Überlappung, deterministisch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLayoutTests = class
  public
    [Test]
    procedure CentralUnitSitsInTheMiddle;
    [Test]
    procedure SubsystemsDoNotOverlap;
    [Test]
    procedure EmptyOverviewGivesEmptyLayout;
    [Test]
    procedure SameInputSameLayout;
    [Test]
    procedure PartsOfSplitSubsystemSitSideBySide;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.UsesGraph.Tests;

function Overview: TArchitectureOverview;
var
  mUnits: TArray<TUnitIndex>;
  mGraph: TUsesGraph;
  mGroup, mItem: Integer;
begin
  // Fünf Namensräume zu je acht Units, jede verwendet die erste ihres Namensraums.
  mUnits := nil;
  for mGroup := 0 to 4 do
  begin
    for mItem := 0 to 7 do
    begin
      if mItem = 0 then
      begin
        mUnits := mUnits + [UsesUnit(Format('N%d.U0', [mGroup]), nil, [Format('N%d.U0', [(mGroup + 1) mod 5])])];
      end
      else
      begin
        mUnits := mUnits + [UsesUnit(Format('N%d.U%d', [mGroup, mItem]), [Format('N%d.U0', [mGroup])], nil)];
      end;
    end;
  end;
  mGraph := TUsesGraph.Create(mUnits, TUsesGraphOptions.Default);
  try
    Result := TArchitectureAnalyzer.Analyze(mGraph, nil, 10);
  finally
    mGraph.Free;
  end;
end;

{ TLayoutTests }

procedure TLayoutTests.CentralUnitSitsInTheMiddle;
var
  mData: TArchitectureOverview;
  mLayout: TArchitectureLayout;
  mIndex: Integer;
  mCenter: TLayoutPoint;
begin
  mData := Overview;
  mLayout := TArchitectureLayouter.Compute(mData);
  Assert.AreEqual(5, Integer(Length(mLayout.Subsystems)));
  for mIndex := 0 to High(mData.Subsystems) do
  begin
    mCenter := mLayout.Units[mData.Subsystems[mIndex].Central];
    Assert.AreEqual(mLayout.Subsystems[mIndex].X, mCenter.X, 1E-6);
    Assert.AreEqual(mLayout.Subsystems[mIndex].Y, mCenter.Y, 1E-6);
    Assert.IsTrue(mLayout.Subsystems[mIndex].Radius > TArchitectureLayouter.cSpacing);
  end;
end;

procedure TLayoutTests.SubsystemsDoNotOverlap;
var
  mLayout: TArchitectureLayout;
  A, B: Integer;
begin
  mLayout := TArchitectureLayouter.Compute(Overview);
  for A := 0 to High(mLayout.Subsystems) do
  begin
    for B := A + 1 to High(mLayout.Subsystems) do
    begin
      Assert.IsTrue(Sqrt(Sqr(mLayout.Subsystems[A].X - mLayout.Subsystems[B].X) +
        Sqr(mLayout.Subsystems[A].Y - mLayout.Subsystems[B].Y)) >= mLayout.Subsystems[A].Radius +
        mLayout.Subsystems[B].Radius - 1E-6, Format('%d/%d', [A, B]));
    end;
  end;
  Assert.IsTrue(mLayout.Right > mLayout.Left);
  Assert.IsTrue(mLayout.Bottom > mLayout.Top);
end;

procedure TLayoutTests.PartsOfSplitSubsystemSitSideBySide;
var
  mData: TArchitectureOverview;
  mLayout: TArchitectureLayout;
  mDistance: Double;
begin
  // Teilsystem 3 als Teil desselben ursprünglichen Teilsystems wie 0 (#1364): es legt sich an 0 an.
  mData := Overview;
  mData.Subsystems[0].Parent := 'N';
  mData.Subsystems[3].Parent := 'N';
  mLayout := TArchitectureLayouter.Compute(mData);
  mDistance := Sqrt(Sqr(mLayout.Subsystems[3].X - mLayout.Subsystems[0].X) +
    Sqr(mLayout.Subsystems[3].Y - mLayout.Subsystems[0].Y));
  Assert.AreEqual(mLayout.Subsystems[0].Radius + mLayout.Subsystems[3].Radius + TArchitectureLayouter.cGap, mDistance,
    1E-3);
end;

procedure TLayoutTests.EmptyOverviewGivesEmptyLayout;
var
  mLayout: TArchitectureLayout;
begin
  mLayout := TArchitectureLayouter.Compute(Default(TArchitectureOverview));
  Assert.AreEqual(0, Integer(Length(mLayout.Units)));
  Assert.AreEqual(0, Integer(Length(mLayout.Subsystems)));
end;

procedure TLayoutTests.SameInputSameLayout;
var
  mFirst, mSecond: TArchitectureLayout;
  mIndex: Integer;
begin
  mFirst := TArchitectureLayouter.Compute(Overview);
  mSecond := TArchitectureLayouter.Compute(Overview);
  for mIndex := 0 to High(mFirst.Units) do
  begin
    Assert.AreEqual(mFirst.Units[mIndex].X, mSecond.Units[mIndex].X, 0);
    Assert.AreEqual(mFirst.Units[mIndex].Y, mSecond.Units[mIndex].Y, 0);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLayoutTests);

end.
