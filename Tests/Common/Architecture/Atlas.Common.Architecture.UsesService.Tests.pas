unit Atlas.Common.Architecture.UsesService.Tests;

// Tests des Uses-Graph-Dienstes (#268): folgt der Generation des Index,
// gleicht inkrementell ab und baut mit neuen Optionen neu auf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesServiceTests = class
  public
    [Test]
    procedure FollowsIndexGeneration;
    [Test]
    procedure NewOptionsRebuild;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Architecture.UsesGraph.Tests;

function CountEdges(const AService: TUsesGraphService): Integer;
var
  mCount: Integer;
begin
  mCount := 0;
  AService.Read(
    procedure(const AGraph: TUsesGraph)
    begin
      mCount := AGraph.EdgeCount;
    end);
  Result := mCount;
end;

{ TUsesServiceTests }

procedure TUsesServiceTests.FollowsIndexGeneration;
var
  mIndex: ISymbolIndex;
  mService: TUsesGraphService;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', ['B'], nil));
  mService := TUsesGraphService.Create(mIndex, TUsesGraphOptions.Default);
  try
    Assert.AreEqual(-1, Integer(mService.Generation));
    Assert.AreEqual(0, CountEdges(mService), 'B fehlt');
    Assert.AreEqual(1, mService.Rebuilds);
    Assert.AreEqual(0, CountEdges(mService));
    Assert.AreEqual(0, mService.Updates, 'Index unverändert: kein Abgleich');
    mIndex.AddUnit(UsesUnit('B', nil, nil));
    Assert.AreEqual(1, CountEdges(mService));
    Assert.AreEqual(1, mService.Rebuilds);
    Assert.AreEqual(1, mService.Updates);
    Assert.AreEqual(Integer(mIndex.Generation), Integer(mService.Generation));
  finally
    mService.Free;
  end;
end;

procedure TUsesServiceTests.NewOptionsRebuild;
var
  mIndex: ISymbolIndex;
  mService: TUsesGraphService;
  mOptions: TUsesGraphOptions;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', ['B'], nil));
  mIndex.AddUnit(UsesUnit('B', nil, nil));
  mService := TUsesGraphService.Create(mIndex, TUsesGraphOptions.Default);
  try
    Assert.AreEqual(1, CountEdges(mService));
    mOptions := TUsesGraphOptions.Default;
    mOptions.Exclude := ['B'];
    mService.SetOptions(mOptions);
    Assert.AreEqual(0, CountEdges(mService));
    Assert.AreEqual(2, mService.Rebuilds);
    Assert.AreEqual(1, Integer(Length(mService.Options.Exclude)));
  finally
    mService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesServiceTests);

end.
