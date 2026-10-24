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
  Count: Integer;
begin
  Count := 0;
  AService.Read(
    procedure(const AGraph: TUsesGraph)
    begin
      Count := AGraph.EdgeCount;
    end);
  Result := Count;
end;

{ TUsesServiceTests }

procedure TUsesServiceTests.FollowsIndexGeneration;
var
  Index: ISymbolIndex;
  Service: TUsesGraphService;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('A', ['B'], nil));
  Service := TUsesGraphService.Create(Index, TUsesGraphOptions.Default);
  try
    Assert.AreEqual(-1, Integer(Service.Generation));
    Assert.AreEqual(0, CountEdges(Service), 'B fehlt');
    Assert.AreEqual(1, Service.Rebuilds);
    Assert.AreEqual(0, CountEdges(Service));
    Assert.AreEqual(0, Service.Updates, 'Index unverändert: kein Abgleich');
    Index.AddUnit(UsesUnit('B', nil, nil));
    Assert.AreEqual(1, CountEdges(Service));
    Assert.AreEqual(1, Service.Rebuilds);
    Assert.AreEqual(1, Service.Updates);
    Assert.AreEqual(Integer(Index.Generation), Integer(Service.Generation));
  finally
    Service.Free;
  end;
end;

procedure TUsesServiceTests.NewOptionsRebuild;
var
  Index: ISymbolIndex;
  Service: TUsesGraphService;
  Options: TUsesGraphOptions;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('A', ['B'], nil));
  Index.AddUnit(UsesUnit('B', nil, nil));
  Service := TUsesGraphService.Create(Index, TUsesGraphOptions.Default);
  try
    Assert.AreEqual(1, CountEdges(Service));
    Options := TUsesGraphOptions.Default;
    Options.Exclude := ['B'];
    Service.SetOptions(Options);
    Assert.AreEqual(0, CountEdges(Service));
    Assert.AreEqual(2, Service.Rebuilds);
    Assert.AreEqual(1, Integer(Length(Service.Options.Exclude)));
  finally
    Service.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesServiceTests);

end.
