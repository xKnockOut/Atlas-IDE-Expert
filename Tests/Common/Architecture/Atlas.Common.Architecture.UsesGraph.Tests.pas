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
  Node: Integer;
begin
  Result := '';
  for Node in ANodes do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + AGraph.Node(Node).UnitName;
  end;
end;

function NewGraph(const AUnits: TArray<TUnitIndex>): TUsesGraph;
begin
  Result := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
end;

{ TUsesGraphTests }

procedure TUsesGraphTests.FindsCycleOverThreeUnitsWithPath;
var
  Graph: TUsesGraph;
  Cycles: TArray<TUsesCycle>;
  Text: string;
begin
  // A → B (interface), B → C (implementation), C → A (interface), dazu D außerhalb.
  Graph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, ['C']), UsesUnit('C', ['A'], nil),
    UsesUnit('D', ['A'], nil)]);
  try
    Cycles := Graph.AllCycles;
    Assert.AreEqual(1, Integer(Length(Cycles)));
    Text := Graph.Describe(Cycles[0].Edges);
    Assert.AreEqual('A → B → C → A', Text);
    Assert.AreEqual('A,B,C', Names(Graph, Cycles[0].Component));
    Assert.IsFalse(Cycles[0].InterfaceOnly, 'B → C steht im implementation');
    Assert.AreEqual(Ord(TUsesSection.Implementation_), Ord(Cycles[0].Edges[1].Section));
    Assert.AreEqual(0, Integer(Length(Graph.Cycles(InterfaceUsesOnly))), 'kein Compilerfehler');
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.InterfaceCycleIsCompilerError;
var
  Graph: TUsesGraph;
  Cycles: TArray<TUsesCycle>;
begin
  Graph := NewGraph([UsesUnit('X', ['Y'], nil), UsesUnit('Y', ['X'], nil)]);
  try
    Cycles := Graph.Cycles(InterfaceUsesOnly);
    Assert.AreEqual(1, Integer(Length(Cycles)));
    Assert.IsTrue(Cycles[0].InterfaceOnly);
    Assert.AreEqual('X,Y', Names(Graph, Cycles[0].Units));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.AllCyclesListsErrorsFirstWithoutRepeating;
var
  Graph: TUsesGraph;
  Cycles: TArray<TUsesCycle>;
begin
  // X ↔ Y nur interface (Fehler); P → Q → P über implementation; X, Y tauchen kein zweites Mal auf.
  Graph := NewGraph([UsesUnit('X', ['Y'], nil), UsesUnit('Y', ['X'], nil), UsesUnit('P', ['Q'], nil),
    UsesUnit('Q', nil, ['P'])]);
  try
    Cycles := Graph.AllCycles;
    Assert.AreEqual(2, Integer(Length(Cycles)));
    Assert.IsTrue(Cycles[0].InterfaceOnly);
    Assert.AreEqual('X,Y', Names(Graph, Cycles[0].Component));
    Assert.IsFalse(Cycles[1].InterfaceOnly);
    Assert.AreEqual('P,Q', Names(Graph, Cycles[1].Component));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.SelfUseIsCycle;
var
  Graph: TUsesGraph;
  Cycles: TArray<TUsesCycle>;
begin
  Graph := NewGraph([UsesUnit('S', nil, ['S'])]);
  try
    Cycles := Graph.AllCycles;
    Assert.AreEqual(1, Integer(Length(Cycles)));
    Assert.AreEqual('S → S', Graph.Describe(Cycles[0].Edges));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.ShortestPathPrefersEarlierEntry;
var
  Graph: TUsesGraph;
  Path: TUsesEdges;
begin
  // A → B → D und A → C → D gleich lang: B steht im uses zuerst. A → E → F → D ist länger.
  Graph := NewGraph([UsesUnit('A', ['E', 'B'], ['C']), UsesUnit('B', ['D'], nil), UsesUnit('C', ['D'], nil),
    UsesUnit('D', nil, nil), UsesUnit('E', ['F'], nil), UsesUnit('F', ['D'], nil)]);
  try
    Path := Graph.Path(Graph.IndexOf('A'), Graph.IndexOf('D'), AllUsesSections);
    Assert.AreEqual('A → B → D', Graph.Describe(Path));
    Path := Graph.Path(Graph.IndexOf('A'), Graph.IndexOf('C'), InterfaceUsesOnly);
    Assert.AreEqual(0, Integer(Length(Path)), 'A → C nur über implementation');
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.NoPathGivesEmptyResult;
var
  Graph: TUsesGraph;
begin
  Graph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil)]);
  try
    Assert.AreEqual(0, Integer(Length(Graph.Path(Graph.IndexOf('B'), Graph.IndexOf('A'), AllUsesSections))));
    Assert.AreEqual(0, Integer(Length(Graph.Path(Graph.IndexOf('A'), Graph.IndexOf('A'), AllUsesSections))));
    Assert.AreEqual(0, Integer(Length(Graph.Path(Graph.IndexOf('A'), -1, AllUsesSections))));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.TransitiveDependenciesAndDependents;
var
  Graph: TUsesGraph;
begin
  Graph := NewGraph([UsesUnit('App', ['Ui'], ['Data']), UsesUnit('Ui', ['Core'], nil), UsesUnit('Data', nil, ['Core']),
    UsesUnit('Core', nil, nil)]);
  try
    Assert.AreEqual('Core,Data,Ui', Names(Graph, Graph.Dependencies(Graph.IndexOf('App'), AllUsesSections)));
    Assert.AreEqual('Core,Ui', Names(Graph, Graph.Dependencies(Graph.IndexOf('App'), InterfaceUsesOnly)));
    Assert.AreEqual('App,Data,Ui', Names(Graph, Graph.Dependents(Graph.IndexOf('Core'), AllUsesSections)));
    Assert.AreEqual('Data,Ui', Names(Graph, Graph.DirectDependents(Graph.IndexOf('Core'), AllUsesSections)));
    Assert.AreEqual('Ui', Names(Graph, Graph.DirectDependencies(Graph.IndexOf('App'), InterfaceUsesOnly)));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.RecompileSetFollowsInterfaceUses;
var
  Graph: TUsesGraph;
begin
  // Y verwendet X im interface, Z verwendet Y im implementation, W verwendet Z im interface:
  // Ändert sich X, werden Y (direkt) und Z (über Ys Schnittstelle) übersetzt, W nicht.
  Graph := NewGraph([UsesUnit('X', nil, nil), UsesUnit('Y', ['X'], nil), UsesUnit('Z', nil, ['Y']),
    UsesUnit('W', ['Z'], nil), UsesUnit('V', nil, ['X'])]);
  try
    Assert.AreEqual('V,Y,Z', Names(Graph, Graph.RecompileSet(Graph.IndexOf('X'))));
    Assert.AreEqual('W', Names(Graph, Graph.RecompileSet(Graph.IndexOf('Z'))));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.InitializationOrderIsDepthFirst;
var
  Graph: TUsesGraph;
  Units: TArray<TUnitIndex>;
begin
  Units := [UsesUnit('P', nil, ['A', 'B']), UsesUnit('A', ['C'], ['B']), UsesUnit('B', nil, nil),
    UsesUnit('C', nil, nil)];
  Units[0].FileName := 'C:\Projekt\P.dpr';
  Units[1].HasInitialization := True;
  Units[2].HasInitialization := True;
  Graph := NewGraph(Units);
  try
    Assert.IsTrue(Graph.Node(Graph.IndexOf('P')).IsProgram);
    Assert.AreEqual('C,B,A,P', Names(Graph, Graph.InitializationOrder(Graph.IndexOf('P'), False)));
    Assert.AreEqual('B,A', Names(Graph, Graph.InitializationOrder(Graph.IndexOf('P'), True)));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.ResolvesNamesWithoutNamespace;
var
  Graph: TUsesGraph;
  Options: TUsesGraphOptions;
begin
  Options := TUsesGraphOptions.Default;
  Options.Namespaces := ['System', 'Vcl'];
  Graph := TUsesGraph.Create([UsesUnit('Main', ['SysUtils', 'Forms'], nil), UsesUnit('System.SysUtils', nil, nil),
    UsesUnit('Vcl.Forms', nil, nil)], Options);
  try
    Assert.AreEqual('System.SysUtils,Vcl.Forms',
      Names(Graph, Graph.DirectDependencies(Graph.IndexOf('Main'), AllUsesSections)));
    Assert.AreEqual(Graph.IndexOf('Vcl.Forms'), Graph.IndexOf('Forms'));
    Assert.AreEqual('SysUtils', Graph.Node(Graph.IndexOf('Main')).Outgoing[0].Name, 'Name wie im uses');
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.LibraryUnitsOnlyOnRequest;
var
  Graph: TUsesGraph;
  Options: TUsesGraphOptions;
  Units: TArray<TUnitIndex>;
begin
  Units := [UsesUnit('Main', ['Lib'], nil), UsesUnit('Lib', nil, nil)];
  Units[1].Library_ := True;
  Graph := NewGraph(Units);
  try
    Assert.AreEqual(1, Graph.ActiveCount);
    Assert.AreEqual(0, Graph.EdgeCount);
  finally
    Graph.Free;
  end;
  Options := TUsesGraphOptions.Default;
  Options.IncludeLibrary := True;
  Graph := TUsesGraph.Create(Units, Options);
  try
    Assert.AreEqual(2, Graph.ActiveCount);
    Assert.AreEqual(1, Graph.EdgeCount);
    Assert.IsTrue(Graph.Node(Graph.IndexOf('Lib')).Library_);
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.ExcludeMatchesNameOrPath;
var
  Graph: TUsesGraph;
  Options: TUsesGraphOptions;
  Units: TArray<TUnitIndex>;
begin
  Units := [UsesUnit('Main', ['Kern'], nil), UsesUnit('Kern', nil, nil), UsesUnit('Kern.Tests', ['Kern'], nil),
    UsesUnit('Hilfe', nil, nil)];
  Units[3].FileName := 'C:\Projekt\Werkzeuge\Hilfe.pas';
  Options := TUsesGraphOptions.Default;
  Options.Root := 'C:\Projekt';
  Options.Exclude := ['*.Tests', 'Werkzeuge/**'];
  Graph := TUsesGraph.Create(Units, Options);
  try
    Assert.AreEqual('Kern,Main', Names(Graph, Graph.SortedNodes));
    Assert.AreEqual('Main', Names(Graph, Graph.DirectDependents(Graph.IndexOf('Kern'), AllUsesSections)));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.UpdateReplacesOnlyChangedUnit;
var
  Graph: TUsesGraph;
  Changed: TUnitIndex;
begin
  Graph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil), UsesUnit('C', nil, nil)]);
  try
    Changed := UsesUnit('A', nil, ['C']);
    Assert.IsTrue(Graph.Update(Changed));
    Assert.AreEqual('C', Names(Graph, Graph.DirectDependencies(Graph.IndexOf('A'), AllUsesSections)));
    Assert.AreEqual('', Names(Graph, Graph.DirectDependents(Graph.IndexOf('B'), AllUsesSections)));
    Assert.AreEqual('A', Names(Graph, Graph.DirectDependents(Graph.IndexOf('C'), AllUsesSections)));
    Assert.AreEqual(3, Graph.NodeCount, 'gleiche Knotennummern');
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.NewUnitResolvesWaitingEdges;
var
  Graph: TUsesGraph;
begin
  Graph := NewGraph([UsesUnit('A', ['B'], nil)]);
  try
    Assert.AreEqual(0, Graph.EdgeCount, 'B fehlt noch');
    Graph.Update(UsesUnit('B', nil, nil));
    Assert.AreEqual(1, Graph.EdgeCount);
    Assert.AreEqual('A', Names(Graph, Graph.DirectDependents(Graph.IndexOf('B'), AllUsesSections)));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.RemoveLeavesEdgesOpen;
var
  Graph: TUsesGraph;
begin
  Graph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil)]);
  try
    Graph.Remove(Graph.Node(Graph.IndexOf('B')).FileName);
    Assert.AreEqual(-1, Graph.IndexOf('B'));
    Assert.AreEqual(1, Graph.ActiveCount);
    Assert.AreEqual(0, Graph.EdgeCount);
    // Kommt B zurück, gilt die Kante wieder.
    Graph.Update(UsesUnit('B', nil, nil));
    Assert.AreEqual(1, Graph.EdgeCount);
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.SynchronizeAddsChangesAndRemoves;
var
  Graph: TUsesGraph;
begin
  Graph := NewGraph([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil), UsesUnit('C', nil, nil)]);
  try
    Assert.AreEqual(0, Graph.Synchronize([UsesUnit('A', ['B'], nil), UsesUnit('B', nil, nil),
      UsesUnit('C', nil, nil)]), 'unverändert');
    // A geändert, C entfernt, D neu.
    Assert.AreEqual(3, Graph.Synchronize([UsesUnit('A', ['B', 'D'], nil), UsesUnit('B', nil, nil),
      UsesUnit('D', nil, nil)]));
    Assert.AreEqual('A,B,D', Names(Graph, Graph.SortedNodes));
    Assert.AreEqual('B,D', Names(Graph, Graph.DirectDependencies(Graph.IndexOf('A'), AllUsesSections)));
  finally
    Graph.Free;
  end;
end;

procedure TUsesGraphTests.ResultsAreDeterministic;
var
  First, Second: TUsesGraph;
  Units, Reversed: TArray<TUnitIndex>;
  Index: Integer;
begin
  Units := [UsesUnit('M', ['N'], nil), UsesUnit('N', nil, ['O']), UsesUnit('O', ['M'], nil),
    UsesUnit('K', nil, ['L']), UsesUnit('L', ['K'], nil)];
  SetLength(Reversed, Length(Units));
  for Index := 0 to High(Units) do
    Reversed[High(Units) - Index] := Units[Index];
  First := NewGraph(Units);
  Second := NewGraph(Reversed);
  try
    Assert.AreEqual(Integer(Length(First.AllCycles)), Integer(Length(Second.AllCycles)));
    for Index := 0 to High(First.AllCycles) do
      Assert.AreEqual(First.Describe(First.AllCycles[Index].Edges), Second.Describe(Second.AllCycles[Index].Edges));
  finally
    Second.Free;
    First.Free;
  end;
end;

procedure TUsesGraphTests.TwoThousandUnitsAreFast;
var
  Units: TArray<TUnitIndex>;
  Index: Integer;
  Graph: TUsesGraph;
  Watch: TStopwatch;
begin
  // Ring über 2000 Units mit Querverweisen: Aufbau, Zyklen und Neuübersetzung zusammen deutlich unter 2 s.
  SetLength(Units, 2000);
  for Index := 0 to High(Units) do
    Units[Index] := UsesUnit(Format('U%.4d', [Index]), [Format('U%.4d', [(Index + 1) mod 2000])],
      [Format('U%.4d', [(Index * 7) mod 2000]), Format('U%.4d', [(Index * 13 + 5) mod 2000])]);
  Watch := TStopwatch.StartNew;
  Graph := NewGraph(Units);
  try
    Assert.AreEqual(1, Integer(Length(Graph.AllCycles)));
    Assert.AreEqual(1999, Integer(Length(Graph.RecompileSet(0))));
    Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, Format('%d ms', [Watch.ElapsedMilliseconds]));
  finally
    Graph.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesGraphTests);

end.
