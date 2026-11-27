unit Atlas.Common.Architecture.UsesService.Tests;

// Tests des Uses-Graph-Dienstes (#268): folgt der Generation des Index,
// gleicht inkrementell ab und baut mit neuen Optionen neu auf; behält je
// Optionssatz einen Graphen und liest mit TryRead, ohne zu warten (#3075).

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
    [Test]
    procedure KeepsAGraphPerOptions;
    [Test]
    procedure EvictsTheLeastRecentlyUsed;
    [Test]
    procedure TryReadBuildsInTheBackground;
    [Test]
    procedure TryReadServesStaleWhileUpdating;
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

function Rooted(const ARoot: string): TUsesGraphOptions;
begin
  Result := TUsesGraphOptions.Default;
  Result.Root := ARoot;
end;

function EdgesWith(const AService: TUsesGraphService; const AOptions: TUsesGraphOptions): TUsesGraphRead;
begin
  Result := AService.ReadWith(AOptions,
    procedure(const AGraph: TUsesGraph)
    begin
      // Nur lesen.
    end);
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

procedure TUsesServiceTests.KeepsAGraphPerOptions;
var
  mIndex: ISymbolIndex;
  mService: TUsesGraphService;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', ['B'], nil));
  mService := TUsesGraphService.Create(mIndex, TUsesGraphOptions.Default, TUsesGraphService.cProjectCapacity);
  try
    Assert.AreEqual('rebuilt', EdgesWith(mService, Rooted('P1')).KindName);
    Assert.AreEqual('rebuilt', EdgesWith(mService, Rooted('P2')).KindName);
    Assert.AreEqual('current', EdgesWith(mService, Rooted('p1')).KindName, 'P1 zurück, ohne Aufbau');
    Assert.AreEqual(2, mService.Rebuilds);
    mIndex.AddUnit(UsesUnit('B', nil, nil));
    Assert.AreEqual('updated', EdgesWith(mService, Rooted('P2')).KindName, 'nur abgeglichen');
    Assert.AreEqual(2, mService.Rebuilds);
    Assert.AreEqual(1, mService.Updates);
    Assert.AreEqual(Integer(-1), Integer(mService.Generation), 'Vorgabe-Optionen ohne Graph');
  finally
    mService.Free;
  end;
end;

procedure TUsesServiceTests.EvictsTheLeastRecentlyUsed;
var
  mIndex: ISymbolIndex;
  mService: TUsesGraphService;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', nil, nil));
  mService := TUsesGraphService.Create(mIndex, TUsesGraphOptions.Default, 2);
  try
    EdgesWith(mService, Rooted('P1'));
    EdgesWith(mService, Rooted('P2'));
    EdgesWith(mService, Rooted('P1'));
    EdgesWith(mService, Rooted('P3'));
    Assert.AreEqual(2, mService.Cached);
    Assert.AreEqual('current', EdgesWith(mService, Rooted('P1')).KindName, 'zuletzt benutzt bleibt');
    Assert.AreEqual('rebuilt', EdgesWith(mService, Rooted('P2')).KindName, 'ältester weicht');
  finally
    mService.Free;
  end;
end;

procedure TUsesServiceTests.TryReadBuildsInTheBackground;
var
  mIndex: ISymbolIndex;
  mService: TUsesGraphService;
  mRead: TUsesGraphRead;
  mCount: Integer;
  mReader: TUsesGraphReader;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', ['B'], nil));
  mIndex.AddUnit(UsesUnit('B', nil, nil));
  mService := TUsesGraphService.Create(mIndex, TUsesGraphOptions.Default, TUsesGraphService.cProjectCapacity);
  try
    mCount := -1;
    mReader :=
      procedure(const AGraph: TUsesGraph)
      begin
        mCount := AGraph.EdgeCount;
      end;
    mRead := mService.TryRead(Rooted('P1'), mReader);
    Assert.AreEqual('pending', mRead.KindName);
    Assert.AreEqual(Integer(-1), Integer(mRead.Generation));
    Assert.AreEqual(-1, mCount, 'ohne Graph nicht gelesen');
    mService.WaitIdle;
    Assert.AreEqual(1, mService.Rebuilds);
    mRead := mService.TryRead(Rooted('P1'), mReader);
    Assert.AreEqual('current', mRead.KindName);
    Assert.AreEqual('', mService.WorkerError);
    Assert.AreEqual(1, mCount);
    Assert.AreEqual(Integer(mIndex.Generation), Integer(mRead.Generation));
  finally
    mService.Free;
  end;
  mReader := nil;
end;

procedure TUsesServiceTests.TryReadServesStaleWhileUpdating;
var
  mIndex: ISymbolIndex;
  mService: TUsesGraphService;
  mRead: TUsesGraphRead;
  mCount: Integer;
  mReader: TUsesGraphReader;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', ['B'], nil));
  mService := TUsesGraphService.Create(mIndex, TUsesGraphOptions.Default, TUsesGraphService.cProjectCapacity);
  try
    mCount := -1;
    mReader :=
      procedure(const AGraph: TUsesGraph)
      begin
        mCount := AGraph.EdgeCount;
      end;
    EdgesWith(mService, Rooted('P1'));
    mIndex.AddUnit(UsesUnit('B', nil, nil));
    mRead := mService.TryRead(Rooted('P1'), mReader);
    Assert.AreEqual('stale', mRead.KindName, 'alter Stand, Abgleich im Hintergrund');
    Assert.AreEqual(0, mCount, 'B fehlte im alten Stand');
    mService.WaitIdle;
    mRead := mService.TryRead(Rooted('P1'), mReader);
    Assert.AreEqual('current', mRead.KindName);
    Assert.AreEqual(1, mCount);
    Assert.AreEqual(1, mService.Updates);
  finally
    mService.Free;
  end;
  mReader := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesServiceTests);

end.
