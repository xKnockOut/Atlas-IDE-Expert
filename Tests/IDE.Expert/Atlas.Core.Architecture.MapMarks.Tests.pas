unit Atlas.Core.Architecture.MapMarks.Tests;

// Markierungen der Architekturkarte (#1118): zentrale Units, Kanten auf einem
// Zyklus und neue Kanten gegenüber dem gespeicherten Stand (#1121).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasArchitectureMapMarksTests = class
  public
    [Test]
    procedure MarksCentralUnitsAndCycleEdges;
    [Test]
    procedure MarksAddedEdgesOfComparison;
    [Test]
    procedure OutOfRangeIsNotMarked;
  end;

implementation

uses
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.MapMarks,
  Atlas.Core.Architecture.Model.Tests;

function ModelOf(const AAnswer: string): TAtlasArchitectureModel;
var
  mEnabled: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(AAnswer, Result, mEnabled));
end;

procedure TAtlasArchitectureMapMarksTests.MarksCentralUnitsAndCycleEdges;
var
  mModel: TAtlasArchitectureModel;
  mMarks: TAtlasArchitectureMapMarks;
  mEdge: TAtlasArchEdge;
  mLink: TAtlasArchLink;
begin
  mModel := ModelOf(SampleAnswer);
  mMarks := TAtlasArchitectureMapMarks.Create;
  try
    mMarks.Read(mModel);
    Assert.IsTrue(mMarks.IsCentral(mModel.Central[0]));
    Assert.IsTrue(Length(mModel.Cycles) > 0);
    mLink := mModel.Cycles[0].Edges[0];
    mEdge := Default(TAtlasArchEdge);
    mEdge.Source := mLink.Source;
    mEdge.Target := mLink.Target;
    Assert.IsTrue(mMarks.OnCycle(mEdge));
    // Gegenrichtung liegt nicht auf dem Zyklus, wenn es sie nicht als Kante des Zyklus gibt.
    mEdge.Source := Length(mModel.Units);
    Assert.IsFalse(mMarks.OnCycle(mEdge));
    // Ohne Vergleich ist keine Kante neu.
    Assert.IsFalse(mMarks.IsAdded(0));
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasArchitectureMapMarksTests.MarksAddedEdgesOfComparison;
var
  mModel: TAtlasArchitectureModel;
  mMarks: TAtlasArchitectureMapMarks;
  mEdge: Integer;
begin
  mModel := ModelOf(SampleComparisonAnswer);
  Assert.IsTrue(Length(mModel.Comparison.AddedEdges) > 0);
  mMarks := TAtlasArchitectureMapMarks.Create;
  try
    mMarks.Read(mModel);
    for mEdge in mModel.Comparison.AddedEdges do
    begin
      Assert.IsTrue(mMarks.IsAdded(mEdge));
    end;
    // Neue Daten ohne Vergleich heben die Markierungen auf.
    mMarks.Read(ModelOf(SampleAnswer));
    Assert.IsFalse(mMarks.IsAdded(mModel.Comparison.AddedEdges[0]));
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasArchitectureMapMarksTests.OutOfRangeIsNotMarked;
var
  mMarks: TAtlasArchitectureMapMarks;
begin
  mMarks := TAtlasArchitectureMapMarks.Create;
  try
    Assert.IsFalse(mMarks.IsCentral(-1));
    Assert.IsFalse(mMarks.IsCentral(0));
    Assert.IsFalse(mMarks.IsAdded(-1));
    Assert.IsFalse(mMarks.IsAdded(0));
  finally
    mMarks.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureMapMarksTests);

end.
