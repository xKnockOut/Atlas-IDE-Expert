unit Atlas.Common.Architecture.UsesLocator.Tests;

// Tests der Fundstellen im Uses-Graphen (#268): Zeile und Spalte des
// uses-Eintrags, Abschnitt, aktive {$IFDEF}-Zweige, fehlende Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesLocatorTests = class
  public
    [Test]
    procedure LocatesEntryInItsSection;
    [Test]
    procedure PrefersActiveBranch;
    [Test]
    procedure MissingFileOrEntryFails;
    [Test]
    procedure ReadsEachFileOnce;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.UsesGraph.Tests;

const
  MainText = 'unit Main;'#10 +
    'interface'#10 +
    'uses Kern;'#10 +
    'implementation'#10 +
    'uses'#10 +
    '  Daten,'#10 +
    '  Kern.Hilfe;'#10 +
    'end.';
  BranchText = 'unit Main;'#10 +
    'interface'#10 +
    'uses'#10 +
    '{$IFDEF ALT}'#10 +
    '  Kern,'#10 +
    '{$ELSE}'#10 +
    '  Daten, Kern,'#10 +
    '{$ENDIF}'#10 +
    '  Ende;'#10 +
    'implementation'#10 +
    'end.';

function Reader(const AFiles: TDictionary<string, string>; const ACounter: TList<string>): TUsesTextReader;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      ACounter.Add(AFileName);
      Result := AFiles.TryGetValue(AFileName, AText);
    end;
end;

function NoDefines: TUsesDefinesFunc;
begin
  Result :=
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end;
end;

function EdgeTo(AGraph: TUsesGraph; const ASource, ATarget: string): TUsesEdge;
var
  Edge: TUsesEdge;
begin
  for Edge in AGraph.Node(AGraph.IndexOf(ASource)).Outgoing do
    if SameText(AGraph.Node(Edge.Target).UnitName, ATarget) then
      Exit(Edge);
  raise Exception.Create('Kante fehlt: ' + ASource + ' → ' + ATarget);
end;

{ TUsesLocatorTests }

procedure TUsesLocatorTests.LocatesEntryInItsSection;
var
  Files: TDictionary<string, string>;
  Reads: TList<string>;
  Graph: TUsesGraph;
  Locator: TUsesLocator;
  Location: TUsesLocation;
  Main: TUnitIndex;
begin
  Files := TDictionary<string, string>.Create;
  Reads := TList<string>.Create;
  Main := UsesUnit('Main', ['Kern'], ['Daten', 'Kern.Hilfe']);
  Files.Add(Main.FileName, MainText);
  Graph := TUsesGraph.Create([Main, UsesUnit('Kern', nil, nil), UsesUnit('Daten', nil, nil),
    UsesUnit('Kern.Hilfe', nil, nil)], TUsesGraphOptions.Default);
  Locator := TUsesLocator.Create(Reader(Files, Reads), NoDefines);
  try
    Assert.IsTrue(Locator.Locate(Graph, EdgeTo(Graph, 'Main', 'Kern'), Location));
    Assert.AreEqual(Main.FileName, Location.FileName);
    Assert.AreEqual(2, Location.Range.StartPos.Line);
    Assert.AreEqual(5, Location.Range.StartPos.Character);
    Assert.IsTrue(Locator.Locate(Graph, EdgeTo(Graph, 'Main', 'Kern.Hilfe'), Location));
    Assert.AreEqual(6, Location.Range.StartPos.Line);
    Assert.AreEqual(2, Location.Range.StartPos.Character);
    Assert.AreEqual(12, Location.Range.EndPos.Character);
  finally
    Locator.Free;
    Graph.Free;
    Reads.Free;
    Files.Free;
  end;
end;

procedure TUsesLocatorTests.PrefersActiveBranch;
var
  Files: TDictionary<string, string>;
  Reads: TList<string>;
  Graph: TUsesGraph;
  Locator: TUsesLocator;
  Location: TUsesLocation;
  Main: TUnitIndex;
begin
  // Ohne ALT gilt der $ELSE-Zweig: Kern steht in Zeile 6 hinter Daten.
  Files := TDictionary<string, string>.Create;
  Reads := TList<string>.Create;
  Main := UsesUnit('Main', ['Daten', 'Kern', 'Ende'], nil);
  Files.Add(Main.FileName, BranchText);
  Graph := TUsesGraph.Create([Main, UsesUnit('Kern', nil, nil), UsesUnit('Daten', nil, nil),
    UsesUnit('Ende', nil, nil)], TUsesGraphOptions.Default);
  Locator := TUsesLocator.Create(Reader(Files, Reads), NoDefines);
  try
    Assert.IsTrue(Locator.Locate(Graph, EdgeTo(Graph, 'Main', 'Kern'), Location));
    Assert.AreEqual(6, Location.Range.StartPos.Line);
    Assert.AreEqual(9, Location.Range.StartPos.Character);
  finally
    Locator.Free;
    Graph.Free;
    Reads.Free;
    Files.Free;
  end;
end;

procedure TUsesLocatorTests.MissingFileOrEntryFails;
var
  Files: TDictionary<string, string>;
  Reads: TList<string>;
  Graph: TUsesGraph;
  Locator: TUsesLocator;
  Location: TUsesLocation;
  Main, Other: TUnitIndex;
begin
  Files := TDictionary<string, string>.Create;
  Reads := TList<string>.Create;
  Main := UsesUnit('Main', ['Kern'], nil);
  Other := UsesUnit('Other', ['Kern'], nil);
  // Datei von Main ohne den Eintrag (veralteter Index), Datei von Other fehlt.
  Files.Add(Main.FileName, 'unit Main; interface implementation end.');
  Graph := TUsesGraph.Create([Main, Other, UsesUnit('Kern', nil, nil)], TUsesGraphOptions.Default);
  Locator := TUsesLocator.Create(Reader(Files, Reads), NoDefines);
  try
    Assert.IsFalse(Locator.Locate(Graph, EdgeTo(Graph, 'Main', 'Kern'), Location));
    Assert.IsFalse(Locator.Locate(Graph, EdgeTo(Graph, 'Other', 'Kern'), Location));
    Assert.AreEqual(Other.FileName, Location.FileName, 'Datei bleibt für die Anzeige');
  finally
    Locator.Free;
    Graph.Free;
    Reads.Free;
    Files.Free;
  end;
end;

procedure TUsesLocatorTests.ReadsEachFileOnce;
var
  Files: TDictionary<string, string>;
  Reads: TList<string>;
  Graph: TUsesGraph;
  Locator: TUsesLocator;
  Location: TUsesLocation;
  Main: TUnitIndex;
begin
  Files := TDictionary<string, string>.Create;
  Reads := TList<string>.Create;
  Main := UsesUnit('Main', ['Kern'], ['Daten', 'Kern.Hilfe']);
  Files.Add(Main.FileName, MainText);
  Graph := TUsesGraph.Create([Main, UsesUnit('Kern', nil, nil), UsesUnit('Daten', nil, nil),
    UsesUnit('Kern.Hilfe', nil, nil)], TUsesGraphOptions.Default);
  Locator := TUsesLocator.Create(Reader(Files, Reads), NoDefines);
  try
    Locator.Locate(Graph, EdgeTo(Graph, 'Main', 'Kern'), Location);
    Locator.Locate(Graph, EdgeTo(Graph, 'Main', 'Daten'), Location);
    Assert.AreEqual(1, Reads.Count);
  finally
    Locator.Free;
    Graph.Free;
    Reads.Free;
    Files.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesLocatorTests);

end.
