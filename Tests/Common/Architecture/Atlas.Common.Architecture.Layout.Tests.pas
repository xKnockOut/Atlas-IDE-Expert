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
  Units: TArray<TUnitIndex>;
  Graph: TUsesGraph;
  Group, Item: Integer;
begin
  // Fünf Namensräume zu je acht Units, jede verwendet die erste ihres Namensraums.
  Units := nil;
  for Group := 0 to 4 do
    for Item := 0 to 7 do
      if Item = 0 then
        Units := Units + [UsesUnit(Format('N%d.U0', [Group]), nil, [Format('N%d.U0', [(Group + 1) mod 5])])]
      else
        Units := Units + [UsesUnit(Format('N%d.U%d', [Group, Item]), [Format('N%d.U0', [Group])], nil)];
  Graph := TUsesGraph.Create(Units, TUsesGraphOptions.Default);
  try
    Result := TArchitectureAnalyzer.Analyze(Graph, nil, 10);
  finally
    Graph.Free;
  end;
end;

{ TLayoutTests }

procedure TLayoutTests.CentralUnitSitsInTheMiddle;
var
  Data: TArchitectureOverview;
  Layout: TArchitectureLayout;
  Index: Integer;
  Center: TLayoutPoint;
begin
  Data := Overview;
  Layout := TArchitectureLayouter.Compute(Data);
  Assert.AreEqual(5, Integer(Length(Layout.Subsystems)));
  for Index := 0 to High(Data.Subsystems) do
  begin
    Center := Layout.Units[Data.Subsystems[Index].Central];
    Assert.AreEqual(Layout.Subsystems[Index].X, Center.X, 1E-6);
    Assert.AreEqual(Layout.Subsystems[Index].Y, Center.Y, 1E-6);
    Assert.IsTrue(Layout.Subsystems[Index].Radius > TArchitectureLayouter.Spacing);
  end;
end;

procedure TLayoutTests.SubsystemsDoNotOverlap;
var
  Layout: TArchitectureLayout;
  A, B: Integer;
begin
  Layout := TArchitectureLayouter.Compute(Overview);
  for A := 0 to High(Layout.Subsystems) do
    for B := A + 1 to High(Layout.Subsystems) do
      Assert.IsTrue(Sqrt(Sqr(Layout.Subsystems[A].X - Layout.Subsystems[B].X) +
        Sqr(Layout.Subsystems[A].Y - Layout.Subsystems[B].Y)) >= Layout.Subsystems[A].Radius +
        Layout.Subsystems[B].Radius - 1E-6, Format('%d/%d', [A, B]));
  Assert.IsTrue(Layout.Right > Layout.Left);
  Assert.IsTrue(Layout.Bottom > Layout.Top);
end;

procedure TLayoutTests.EmptyOverviewGivesEmptyLayout;
var
  Layout: TArchitectureLayout;
begin
  Layout := TArchitectureLayouter.Compute(Default(TArchitectureOverview));
  Assert.AreEqual(0, Integer(Length(Layout.Units)));
  Assert.AreEqual(0, Integer(Length(Layout.Subsystems)));
end;

procedure TLayoutTests.SameInputSameLayout;
var
  First, Second: TArchitectureLayout;
  Index: Integer;
begin
  First := TArchitectureLayouter.Compute(Overview);
  Second := TArchitectureLayouter.Compute(Overview);
  for Index := 0 to High(First.Units) do
  begin
    Assert.AreEqual(First.Units[Index].X, Second.Units[Index].X, 0);
    Assert.AreEqual(First.Units[Index].Y, Second.Units[Index].Y, 0);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLayoutTests);

end.
