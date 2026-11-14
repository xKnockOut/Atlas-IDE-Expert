unit Atlas.Common.Architecture.UsesGraph.Tests;

// Tests des Uses-Graphen (#268): Zyklen mit Rundweg, Wege, Hüllen, neu zu
// übersetzende Units, Initialisierungsreihenfolge, Namensräume, Ausschlüsse
// und inkrementelle Änderungen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TUsesGraphTests = class
  public
    [Test]
    procedure FindsCycleOverThreeUnitsWithPath;
    [Test]
    procedure InterfaceCycleIsCompilerError;
    [Test]
    procedure AllCyclesListsErrorsFirstWithoutRepeating;
    [Test]
    procedure SelfUseIsCycle;
    [Test]
    procedure ShortestPathPrefersEarlierEntry;
    [Test]
    procedure NoPathGivesEmptyResult;
    [Test]
    procedure TransitiveDependenciesAndDependents;
    [Test]
    procedure RecompileSetFollowsInterfaceUses;
    [Test]
    procedure InitializationOrderIsDepthFirst;
    [Test]
    procedure ResolvesNamesWithoutNamespace;
    [Test]
    procedure LibraryUnitsOnlyOnRequest;
    [Test]
    procedure ExcludeMatchesNameOrPath;
    [Test]
    procedure UpdateReplacesOnlyChangedUnit;
    [Test]
    procedure NewUnitResolvesWaitingEdges;
    [Test]
    procedure RemoveLeavesEdgesOpen;
    [Test]
    procedure SynchronizeAddsChangesAndRemoves;
    [Test]
    procedure ResultsAreDeterministic;
    [Test]
    [Category('Benchmark')]
    procedure TwoThousandUnitsAreFast;
  end;

function UsesUnit(const AName: string; const AInterface, AImplementation: TArray<string>): TUnitIndex;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Common.Architecture.UsesGraph;

function UsesUnit(const AName: string; const AInterface, AImplementation: TArray<string>): TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := 'C:\Projekt\' + StringReplace(AName, '.', '\', [rfReplaceAll]) + '.pas';
  Result.Hash := AName + '|' + string.Join(',', AInterface) + '|' + string.Join(',', AImplementation);
  Result.InterfaceUses := AInterface;
  Result.ImplementationUses := AImplementation;
end;

function Names(AGraph: TUsesGraph; const ANodes: TArray<Integer>): string;
var
  mNode: Integer;
begin
  Result := '';
  for mNode in ANodes do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + AGraph.Node(mNode).UnitName;
  end;
end;

function NewGraph(const AUnits: TArray<TUnitIndex>): TUsesGraph;
begin
  Result := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
end;

{ TUsesGraphTests }

procedure TUsesGraphTests.FindsCycleOverThreeUnitsWithPath;
var
  mGraph: TUsesGraph;
  mCycles: TArray<TUsesCycle>;
  mText: string;
begin
  // A → B (interface), B → C (implementation), C → A (interface), dazu D außerhalb.
  mGraph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, ['C']), UsesUnit('C', ['A'], nil),
    UsesUnit('D', ['A'], nil)]);
  try
    mCycles := mGraph.AllCycles;
    Assert.AreEqual(1, Integer(Length(mCycles)));
    mText := mGraph.Describe(mCycles[0].Edges);
    Assert.AreEqual('A → B → C → A', mText);
    Assert.AreEqual('A,B,C', Names(mGraph, mCycles[0].Component));
    Assert.IsFalse(mCycles[0].InterfaceOnly, 'B → C steht im implementation');
    Assert.AreEqual(Ord(TUsesSection.Implementation_), Ord(mCycles[0].Edges[1].Section));
    Assert.AreEqual(0, Integer(Length(mGraph.Cycles(cInterfaceUsesOnly))), 'kein Compilerfehler');
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.InterfaceCycleIsCompilerError;
var
  mGraph: TUsesGraph;
  mCycles: TArray<TUsesCycle>;
begin
  mGraph := NewGraph([UsesUnit('X', ['Y'], nil), UsesUnit('Y', ['X'], nil)]);
  try
    mCycles := mGraph.Cycles(cInterfaceUsesOnly);
    Assert.AreEqual(1, Integer(Length(mCycles)));
    Assert.IsTrue(mCycles[0].InterfaceOnly);
    Assert.AreEqual('X,Y', Names(mGraph, mCycles[0].Units));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.AllCyclesListsErrorsFirstWithoutRepeating;
var
  mGraph: TUsesGraph;
  mCycles: TArray<TUsesCycle>;
begin
  // X ↔ Y nur interface (Fehler); P → Q → P über implementation; X, Y tauchen kein zweites Mal auf.
  mGraph := NewGraph([UsesUnit('X', ['Y'], nil), UsesUnit('Y', ['X'], nil), UsesUnit('P', ['Q'], nil),
    UsesUnit('Q', nil, ['P'])]);
  try
    mCycles := mGraph.AllCycles;
    Assert.AreEqual(2, Integer(Length(mCycles)));
    Assert.IsTrue(mCycles[0].InterfaceOnly);
    Assert.AreEqual('X,Y', Names(mGraph, mCycles[0].Component));
    Assert.IsFalse(mCycles[1].InterfaceOnly);
    Assert.AreEqual('P,Q', Names(mGraph, mCycles[1].Component));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.SelfUseIsCycle;
var
  mGraph: TUsesGraph;
  mCycles: TArray<TUsesCycle>;
begin
  mGraph := NewGraph([UsesUnit('S', nil, ['S'])]);
  try
    mCycles := mGraph.AllCycles;
    Assert.AreEqual(1, Integer(Length(mCycles)));
    Assert.AreEqual('S → S', mGraph.Describe(mCycles[0].Edges));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.ShortestPathPrefersEarlierEntry;
var
  mGraph: TUsesGraph;
  mPath: TUsesEdges;
begin
  // A → B → D und A → C → D gleich lang: B steht im uses zuerst. A → E → F → D ist länger.
  mGraph := NewGraph([UsesUnit('A', ['E', 'B'], ['C']), UsesUnit('B', ['D'], nil), UsesUnit('C', ['D'], nil),
    UsesUnit('D', nil, nil), UsesUnit('E', ['F'], nil), UsesUnit('F', ['D'], nil)]);
  try
    mPath := mGraph.Path(mGraph.IndexOf('A'), mGraph.IndexOf('D'), cAllUsesSections);
    Assert.AreEqual('A → B → D', mGraph.Describe(mPath));
    mPath := mGraph.Path(mGraph.IndexOf('A'), mGraph.IndexOf('C'), cInterfaceUsesOnly);
    Assert.AreEqual(0, Integer(Length(mPath)), 'A → C nur über implementation');
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.NoPathGivesEmptyResult;
var
  mGraph: TUsesGraph;
begin
  mGraph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil)]);
  try
    Assert.AreEqual(0, Integer(Length(mGraph.Path(mGraph.IndexOf('B'), mGraph.IndexOf('A'), cAllUsesSections))));
    Assert.AreEqual(0, Integer(Length(mGraph.Path(mGraph.IndexOf('A'), mGraph.IndexOf('A'), cAllUsesSections))));
    Assert.AreEqual(0, Integer(Length(mGraph.Path(mGraph.IndexOf('A'), -1, cAllUsesSections))));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.TransitiveDependenciesAndDependents;
var
  mGraph: TUsesGraph;
begin
  mGraph := NewGraph([UsesUnit('App', ['Ui'], ['Data']), UsesUnit('Ui', ['Core'], nil), UsesUnit('Data', nil, ['Core']),
    UsesUnit('Core', nil, nil)]);
  try
    Assert.AreEqual('Core,Data,Ui', Names(mGraph, mGraph.Dependencies(mGraph.IndexOf('App'), cAllUsesSections)));
    Assert.AreEqual('Core,Ui', Names(mGraph, mGraph.Dependencies(mGraph.IndexOf('App'), cInterfaceUsesOnly)));
    Assert.AreEqual('App,Data,Ui', Names(mGraph, mGraph.Dependents(mGraph.IndexOf('Core'), cAllUsesSections)));
    Assert.AreEqual('Data,Ui', Names(mGraph, mGraph.DirectDependents(mGraph.IndexOf('Core'), cAllUsesSections)));
    Assert.AreEqual('Ui', Names(mGraph, mGraph.DirectDependencies(mGraph.IndexOf('App'), cInterfaceUsesOnly)));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.RecompileSetFollowsInterfaceUses;
var
  mGraph: TUsesGraph;
begin
  // Y verwendet X im interface, Z verwendet Y im implementation, W verwendet Z im interface:
  // Ändert sich X, werden Y (direkt) und Z (über Ys Schnittstelle) übersetzt, W nicht.
  mGraph := NewGraph([UsesUnit('X', nil, nil), UsesUnit('Y', ['X'], nil), UsesUnit('Z', nil, ['Y']),
    UsesUnit('W', ['Z'], nil), UsesUnit('V', nil, ['X'])]);
  try
    Assert.AreEqual('V,Y,Z', Names(mGraph, mGraph.RecompileSet(mGraph.IndexOf('X'))));
    Assert.AreEqual('W', Names(mGraph, mGraph.RecompileSet(mGraph.IndexOf('Z'))));
    Assert.AreEqual(3, mGraph.RecompileCount(mGraph.IndexOf('X')));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.InitializationOrderIsDepthFirst;
var
  mGraph: TUsesGraph;
  mUnits: TArray<TUnitIndex>;
begin
  mUnits := [UsesUnit('P', nil, ['A', 'B']), UsesUnit('A', ['C'], ['B']), UsesUnit('B', nil, nil),
    UsesUnit('C', nil, nil)];
  mUnits[0].FileName := 'C:\Projekt\P.dpr';
  mUnits[1].HasInitialization := True;
  mUnits[2].HasInitialization := True;
  mGraph := NewGraph(mUnits);
  try
    Assert.IsTrue(mGraph.Node(mGraph.IndexOf('P')).IsProgram);
    Assert.AreEqual('C,B,A,P', Names(mGraph, mGraph.InitializationOrder(mGraph.IndexOf('P'), False)));
    Assert.AreEqual('B,A', Names(mGraph, mGraph.InitializationOrder(mGraph.IndexOf('P'), True)));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.ResolvesNamesWithoutNamespace;
var
  mGraph: TUsesGraph;
  mOptions: TUsesGraphOptions;
begin
  mOptions := TUsesGraphOptions.Default;
  mOptions.Namespaces := ['System', 'Vcl'];
  mGraph := TUsesGraph.Create([UsesUnit('Main', ['SysUtils', 'Forms'], nil), UsesUnit('System.SysUtils', nil, nil),
    UsesUnit('Vcl.Forms', nil, nil)], mOptions);
  try
    Assert.AreEqual('System.SysUtils,Vcl.Forms',
      Names(mGraph, mGraph.DirectDependencies(mGraph.IndexOf('Main'), cAllUsesSections)));
    Assert.AreEqual(mGraph.IndexOf('Vcl.Forms'), mGraph.IndexOf('Forms'));
    Assert.AreEqual('SysUtils', mGraph.Node(mGraph.IndexOf('Main')).Outgoing[0].Name, 'Name wie im uses');
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.LibraryUnitsOnlyOnRequest;
var
  mGraph: TUsesGraph;
  mOptions: TUsesGraphOptions;
  mUnits: TArray<TUnitIndex>;
begin
  mUnits := [UsesUnit('Main', ['Lib'], nil), UsesUnit('Lib', nil, nil)];
  mUnits[1].Library_ := True;
  mGraph := NewGraph(mUnits);
  try
    Assert.AreEqual(1, mGraph.ActiveCount);
    Assert.AreEqual(0, mGraph.EdgeCount);
  finally
    mGraph.Free;
  end;
  mOptions := TUsesGraphOptions.Default;
  mOptions.IncludeLibrary := True;
  mGraph := TUsesGraph.Create(mUnits, mOptions);
  try
    Assert.AreEqual(2, mGraph.ActiveCount);
    Assert.AreEqual(1, mGraph.EdgeCount);
    Assert.IsTrue(mGraph.Node(mGraph.IndexOf('Lib')).Library_);
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.ExcludeMatchesNameOrPath;
var
  mGraph: TUsesGraph;
  mOptions: TUsesGraphOptions;
  mUnits: TArray<TUnitIndex>;
begin
  mUnits := [UsesUnit('Main', ['Kern'], nil), UsesUnit('Kern', nil, nil), UsesUnit('Kern.Tests', ['Kern'], nil),
    UsesUnit('Hilfe', nil, nil)];
  mUnits[3].FileName := 'C:\Projekt\Werkzeuge\Hilfe.pas';
  mOptions := TUsesGraphOptions.Default;
  mOptions.Root := 'C:\Projekt';
  mOptions.Exclude := ['*.Tests', 'Werkzeuge/**'];
  mGraph := TUsesGraph.Create(mUnits, mOptions);
  try
    Assert.AreEqual('Kern,Main', Names(mGraph, mGraph.SortedNodes));
    Assert.AreEqual('Main', Names(mGraph, mGraph.DirectDependents(mGraph.IndexOf('Kern'), cAllUsesSections)));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.UpdateReplacesOnlyChangedUnit;
var
  mGraph: TUsesGraph;
  mChanged: TUnitIndex;
begin
  mGraph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil), UsesUnit('C', nil, nil)]);
  try
    mChanged := UsesUnit('A', nil, ['C']);
    Assert.IsTrue(mGraph.Update(mChanged));
    Assert.AreEqual('C', Names(mGraph, mGraph.DirectDependencies(mGraph.IndexOf('A'), cAllUsesSections)));
    Assert.AreEqual('', Names(mGraph, mGraph.DirectDependents(mGraph.IndexOf('B'), cAllUsesSections)));
    Assert.AreEqual('A', Names(mGraph, mGraph.DirectDependents(mGraph.IndexOf('C'), cAllUsesSections)));
    Assert.AreEqual(3, mGraph.NodeCount, 'gleiche Knotennummern');
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.NewUnitResolvesWaitingEdges;
var
  mGraph: TUsesGraph;
begin
  mGraph := NewGraph([UsesUnit('A', ['B'], nil)]);
  try
    Assert.AreEqual(0, mGraph.EdgeCount, 'B fehlt noch');
    mGraph.Update(UsesUnit('B', nil, nil));
    Assert.AreEqual(1, mGraph.EdgeCount);
    Assert.AreEqual('A', Names(mGraph, mGraph.DirectDependents(mGraph.IndexOf('B'), cAllUsesSections)));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.RemoveLeavesEdgesOpen;
var
  mGraph: TUsesGraph;
begin
  mGraph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil)]);
  try
    mGraph.Remove(mGraph.Node(mGraph.IndexOf('B')).FileName);
    Assert.AreEqual(-1, mGraph.IndexOf('B'));
    Assert.AreEqual(1, mGraph.ActiveCount);
    Assert.AreEqual(0, mGraph.EdgeCount);
    // Kommt B zurück, gilt die Kante wieder.
    mGraph.Update(UsesUnit('B', nil, nil));
    Assert.AreEqual(1, mGraph.EdgeCount);
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.SynchronizeAddsChangesAndRemoves;
var
  mGraph: TUsesGraph;
begin
  mGraph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil), UsesUnit('C', nil, nil)]);
  try
    Assert.AreEqual(0, mGraph.Synchronize([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil),
      UsesUnit('C', nil, nil)]), 'unverändert');
    // A geändert, C entfernt, D neu.
    Assert.AreEqual(3, mGraph.Synchronize([UsesUnit('A', ['B', 'D'], nil), UsesUnit('B', nil, nil),
      UsesUnit('D', nil, nil)]));
    Assert.AreEqual('A,B,D', Names(mGraph, mGraph.SortedNodes));
    Assert.AreEqual('B,D', Names(mGraph, mGraph.DirectDependencies(mGraph.IndexOf('A'), cAllUsesSections)));
  finally
    mGraph.Free;
  end;
end;

procedure TUsesGraphTests.ResultsAreDeterministic;
var
  mFirst, mSecond: TUsesGraph;
  mUnits, mReversed: TArray<TUnitIndex>;
  mIndex: Integer;
begin
  mUnits := [UsesUnit('M', ['N'], nil), UsesUnit('N', nil, ['O']), UsesUnit('O', ['M'], nil),
    UsesUnit('K', nil, ['L']), UsesUnit('L', ['K'], nil)];
  SetLength(mReversed, Length(mUnits));
  for mIndex := 0 to High(mUnits) do
  begin
    mReversed[High(mUnits) - mIndex] := mUnits[mIndex];
  end;
  mFirst := NewGraph(mUnits);
  mSecond := NewGraph(mReversed);
  try
    Assert.AreEqual(Integer(Length(mFirst.AllCycles)), Integer(Length(mSecond.AllCycles)));
    for mIndex := 0 to High(mFirst.AllCycles) do
    begin
      Assert.AreEqual(mFirst.Describe(mFirst.AllCycles[mIndex].Edges),
        mSecond.Describe(mSecond.AllCycles[mIndex].Edges));
    end;
  finally
    mSecond.Free;
    mFirst.Free;
  end;
end;

procedure TUsesGraphTests.TwoThousandUnitsAreFast;
var
  mUnits: TArray<TUnitIndex>;
  mIndex: Integer;
  mGraph: TUsesGraph;
  mWatch: TStopwatch;
begin
  // Ring über 2000 Units mit Querverweisen: Aufbau, Zyklen und Neuübersetzung zusammen deutlich unter 2 s.
  SetLength(mUnits, 2000);
  for mIndex := 0 to High(mUnits) do
  begin
    mUnits[mIndex] := UsesUnit(Format('U%.4d', [mIndex]), [Format('U%.4d', [(mIndex + 1) mod 2000])],
      [Format('U%.4d', [(mIndex * 7) mod 2000]), Format('U%.4d', [(mIndex * 13 + 5) mod 2000])]);
  end;
  mWatch := TStopwatch.StartNew;
  mGraph := NewGraph(mUnits);
  try
    Assert.AreEqual(1, Integer(Length(mGraph.AllCycles)));
    Assert.AreEqual(1999, Integer(Length(mGraph.RecompileSet(0))));
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 2000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  finally
    mGraph.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesGraphTests);

end.
