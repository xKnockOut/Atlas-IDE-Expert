unit Atlas.Common.Architecture.UnitRelations.Tests;

// Tests der Unit-Beziehungen (#593): „Verwendet“ aus dem Text samt
// Bibliotheks-Units, „Wird verwendet von“ mit Abschnitt und Fundstelle,
// interface-Zyklus A ↔ B mit Rundweg, Neuübersetzungen, Bäume über alle
// Ebenen mit einmal aufgeklappten Units, ungenutzte Einträge, JSON; Kosten
// einer interface-Änderung (#554) über eine Kette und nur im implementation
// gebrauchte interface-Einträge.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator;

type
  [TestFixture]
  TUnitRelationsTests = class
  private
    FTexts: TDictionary<string, string>;
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    function Reader: TUsesTextReader;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UsesComeFromTextWithLibrary;
    [Test]
    procedure UsedByListsSectionsAndLocations;
    [Test]
    procedure InterfaceCycleIsMarkedWithPath;
    [Test]
    procedure RecompileCountMatchesGraph;
    [Test]
    procedure AllLevelsExpandEachUnitOnce;
    [Test]
    procedure LimitedDepthStopsTree;
    [Test]
    procedure UnusedEntriesAreMarked;
    [Test]
    procedure UnknownFileHasOnlyTextUses;
    [Test]
    procedure JsonCarriesAllFields;
    [Test]
    procedure OnlyImplementationEntriesAreMarked;
    [Test]
    procedure InterfaceCostFollowsChain;
    [Test]
    procedure InterfaceCostStopsAtImplementationUses;
    [Test]
    procedure InterfaceCostJsonAndLimit;
  end;

/// <summary>Quelltext einer Unit mit den uses-Listen (Zeilen getrennt durch #10).</summary>
function UnitSource(const AName: string; const AInterface, AImplementation: TArray<string>): string;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Architecture.UnitRelations,
  Atlas.Common.Architecture.UsesGraph.Tests;

function UnitSource(const AName: string; const AInterface, AImplementation: TArray<string>): string;
begin
  Result := 'unit ' + AName + ';'#10 + 'interface'#10;
  if AInterface <> nil then
    Result := Result + 'uses'#10 + '  ' + string.Join(', ', AInterface) + ';'#10;
  Result := Result + 'implementation'#10;
  if AImplementation <> nil then
    Result := Result + 'uses'#10 + '  ' + string.Join(', ', AImplementation) + ';'#10;
  Result := Result + 'end.';
end;

function FileOf(const AName: string): string;
begin
  Result := UsesUnit(AName, nil, nil).FileName;
end;

function NoDefines: TUsesDefinesFunc;
begin
  Result :=
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end;
end;

function Find(const ARelations: TArray<TUnitRelation>; const AName: string): TUnitRelation;
var
  Relation: TUnitRelation;
begin
  for Relation in ARelations do
    if SameText(Relation.Name, AName) then
      Exit(Relation);
  Assert.Fail(AName + ' fehlt');
  Result := Default(TUnitRelation);
end;

function Names(const ARelations: TArray<TUnitRelation>): string;
var
  Relation: TUnitRelation;
begin
  Result := '';
  for Relation in ARelations do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Relation.Name;
  end;
end;

{ TUnitRelationsTests }

procedure TUnitRelationsTests.Setup;
var
  Units: TArray<TUnitIndex>;

  procedure Add(const AName: string; const AInterface, AImplementation: TArray<string>);
  begin
    Units := Units + [UsesUnit(AName, AInterface, AImplementation)];
    FTexts.AddOrSetValue(FileOf(AName), UnitSource(AName, AInterface, AImplementation));
  end;

begin
  // A ↔ B über interface (Zyklus); A verwendet C im implementation, C → D; System kennt der Graph nicht.
  // Verwender von A: B und E im interface, F im implementation; G → E (impl), H → F (impl).
  FTexts := TDictionary<string, string>.Create;
  Units := nil;
  Add('A', ['B', 'System'], ['C']);
  Add('B', ['A'], nil);
  Add('C', ['D'], nil);
  Add('D', nil, nil);
  Add('E', ['A'], nil);
  Add('F', nil, ['A']);
  Add('G', nil, ['E']);
  Add('H', nil, ['F']);
  FGraph := TUsesGraph.Create(Units, TUsesGraphOptions.Default);
  FLocator := TUsesLocator.Create(Reader, NoDefines);
end;

procedure TUnitRelationsTests.TearDown;
begin
  FLocator.Free;
  FLocator := nil;
  FGraph.Free;
  FGraph := nil;
  FTexts.Free;
  FTexts := nil;
end;

function TUnitRelationsTests.Reader: TUsesTextReader;
var
  Texts: TDictionary<string, string>;
begin
  Texts := FTexts;
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Texts.TryGetValue(AFileName, AText);
    end;
end;

function Build(AGraph: TUsesGraph; ALocator: TUsesLocator; const AReader: TUsesTextReader; const AFileName: string;
  ADepth: Integer; const AUnused: TArray<string>): TUnitRelations;
var
  Builder: TUnitRelationsBuilder;
begin
  Builder := TUnitRelationsBuilder.Create(AGraph, ALocator, AReader, NoDefines);
  try
    Result := Builder.Build(AFileName, ADepth, AUnused);
  finally
    Builder.Free;
  end;
end;

procedure TUnitRelationsTests.UsesComeFromTextWithLibrary;
var
  Relations: TUnitRelations;
  System_: TUnitRelation;
begin
  Relations := Build(FGraph, FLocator, Reader, FileOf('A'), 1, nil);
  Assert.IsTrue(Relations.Found);
  Assert.AreEqual('A', Relations.UnitName);
  Assert.AreEqual('B,System,C', Names(Relations.Uses_), 'Quelltextreihenfolge, erst interface');
  Assert.AreEqual(Ord(TUsesSection.Interface_), Ord(Find(Relations.Uses_, 'B').Section));
  Assert.AreEqual(Ord(TUsesSection.Implementation_), Ord(Find(Relations.Uses_, 'C').Section));
  System_ := Find(Relations.Uses_, 'System');
  Assert.IsTrue(System_.Library_, 'ohne Knoten: Bibliothek');
  Assert.AreEqual('', System_.FileName);
  Assert.IsFalse(Find(Relations.Uses_, 'B').Library_);
  Assert.AreEqual(FileOf('B'), Find(Relations.Uses_, 'B').FileName);
  // Fundstelle: der Eintrag in A selbst, Zeile 3 (0-basiert), Spalte 2.
  Assert.AreEqual(FileOf('A'), Find(Relations.Uses_, 'B').LocationFile);
  Assert.AreEqual(3, Find(Relations.Uses_, 'B').Line);
  Assert.AreEqual(2, Find(Relations.Uses_, 'B').Character);
  Assert.AreEqual(6, Find(Relations.Uses_, 'C').Line);
  Assert.IsNull(Find(Relations.Uses_, 'C').Children, 'direkt: ohne Kinder');
end;

procedure TUnitRelationsTests.UsedByListsSectionsAndLocations;
var
  Relations: TUnitRelations;
  F: TUnitRelation;
begin
  Relations := Build(FGraph, FLocator, Reader, FileOf('A'), 1, nil);
  Assert.AreEqual('B,E,F', Names(Relations.UsedBy), 'genau drei, nach Name');
  Assert.AreEqual(Ord(TUsesSection.Interface_), Ord(Find(Relations.UsedBy, 'B').Section));
  Assert.AreEqual(Ord(TUsesSection.Interface_), Ord(Find(Relations.UsedBy, 'E').Section));
  F := Find(Relations.UsedBy, 'F');
  Assert.AreEqual(Ord(TUsesSection.Implementation_), Ord(F.Section));
  // Fundstelle: der Eintrag in der verwendenden Unit F.
  Assert.AreEqual(FileOf('F'), F.LocationFile);
  Assert.AreEqual(4, F.Line);
  Assert.IsFalse(F.Cycle);
  Assert.AreEqual(5, Relations.DependentCount, 'transitiv: B, E, F, G, H');
  Assert.AreEqual(3, Relations.DependencyCount, 'B, C, D');
end;

procedure TUnitRelationsTests.InterfaceCycleIsMarkedWithPath;
var
  Relations: TUnitRelations;
begin
  Relations := Build(FGraph, FLocator, Reader, FileOf('A'), 1, nil);
  Assert.IsTrue(Relations.InCycle);
  Assert.AreEqual('A → B → A', Relations.CyclePath);
  Assert.IsTrue(Find(Relations.Uses_, 'B').Cycle, 'Verwendet: B rot');
  Assert.AreEqual('A → B → A', Find(Relations.Uses_, 'B').CyclePath);
  Assert.IsFalse(Find(Relations.Uses_, 'C').Cycle);
  Assert.IsFalse(Find(Relations.Uses_, 'System').Cycle);
  Assert.IsTrue(Find(Relations.UsedBy, 'B').Cycle, 'Wird verwendet von: B rot');
  Assert.AreEqual('A → B → A', Find(Relations.UsedBy, 'B').CyclePath);
  Assert.IsFalse(Find(Relations.UsedBy, 'E').Cycle, 'E verwendet A, aber A nicht E');
  // C liegt in keinem Zyklus.
  Relations := Build(FGraph, FLocator, Reader, FileOf('C'), 1, nil);
  Assert.IsFalse(Relations.InCycle);
  Assert.AreEqual('', Relations.CyclePath);
end;

procedure TUnitRelationsTests.RecompileCountMatchesGraph;
var
  Relations: TUnitRelations;
begin
  // A ändert sein interface: B, E, F direkt; G über E (interface); H nicht (F verwendet A im implementation).
  Relations := Build(FGraph, FLocator, Reader, FileOf('A'), 1, nil);
  Assert.AreEqual(4, Relations.RecompileCount);
  Assert.AreEqual(FGraph.RecompileCount(FGraph.IndexOf('A')), Relations.RecompileCount);
  Relations := Build(FGraph, FLocator, Reader, FileOf('D'), 1, nil);
  // D: C, dann über C (interface) A, über A (interface) B und E sowie F und G.
  Assert.AreEqual(FGraph.RecompileCount(FGraph.IndexOf('D')), Relations.RecompileCount);
  Assert.AreEqual(1, Integer(Length(Relations.UsedBy)));
end;

procedure TUnitRelationsTests.AllLevelsExpandEachUnitOnce;
var
  Relations: TUnitRelations;
  B, C, E: TUnitRelation;
begin
  Relations := Build(FGraph, FLocator, Reader, FileOf('A'), 0, nil);
  C := Find(Relations.Uses_, 'C');
  Assert.AreEqual('D', Names(C.Children));
  B := Find(Relations.Uses_, 'B');
  Assert.AreEqual('A', Names(B.Children), 'B verwendet A');
  Assert.IsTrue(B.Children[0].Repeated, 'A ist die Wurzel: nicht noch einmal aufklappen');
  Assert.IsNull(B.Children[0].Children);
  Assert.IsNull(Find(Relations.Uses_, 'System').Children);
  E := Find(Relations.UsedBy, 'E');
  Assert.AreEqual('G', Names(E.Children));
  Assert.AreEqual('H', Names(Find(Relations.UsedBy, 'F').Children));
  Assert.IsTrue(Find(Relations.UsedBy, 'B').Children[0].Repeated);
  Assert.IsFalse(E.Children[0].Repeated, 'G hat keine Verwender');
end;

procedure TUnitRelationsTests.LimitedDepthStopsTree;
var
  Relations: TUnitRelations;
  Units: TArray<TUnitIndex>;
  Graph: TUsesGraph;
begin
  // Zwei Ebenen: Kinder der ersten Ebene ja, Enkel nein.
  Units := TArray<TUnitIndex>.Create(UsesUnit('A', ['B'], nil), UsesUnit('B', ['C'], nil),
    UsesUnit('C', ['D'], nil), UsesUnit('D', nil, nil));
  FTexts.AddOrSetValue(FileOf('A'), UnitSource('A', ['B'], nil));
  Graph := TUsesGraph.Create(Units, TUsesGraphOptions.Default);
  try
    Relations := Build(Graph, nil, Reader, FileOf('A'), 2, nil);
    Assert.AreEqual('C', Names(Find(Relations.Uses_, 'B').Children));
    Assert.IsNull(Find(Relations.Uses_, 'B').Children[0].Children, 'Tiefe 2');
    Relations := Build(Graph, nil, Reader, FileOf('A'), 3, nil);
    Assert.AreEqual('D', Names(Find(Relations.Uses_, 'B').Children[0].Children));
    Assert.AreEqual(-1, Find(Find(Relations.Uses_, 'B').Children, 'C').Line, 'ohne Locator keine Fundstelle');
  finally
    Graph.Free;
  end;
end;

procedure TUnitRelationsTests.UnusedEntriesAreMarked;
var
  Relations: TUnitRelations;
begin
  Relations := Build(FGraph, FLocator, Reader, FileOf('A'), 1, TArray<string>.Create('System', 'X.C'));
  Assert.IsTrue(Find(Relations.Uses_, 'System').Unused);
  Assert.IsFalse(Find(Relations.Uses_, 'B').Unused);
  Assert.IsTrue(Find(Relations.Uses_, 'C').Unused, 'mit Namensraum geschrieben');
end;

procedure TUnitRelationsTests.UnknownFileHasOnlyTextUses;
var
  Relations: TUnitRelations;
begin
  FTexts.AddOrSetValue('C:\Neu\Neu.pas', UnitSource('Neu', ['A'], ['Fremd']));
  Relations := Build(FGraph, FLocator, Reader, 'C:\Neu\Neu.pas', 0, nil);
  Assert.IsFalse(Relations.Found);
  Assert.AreEqual('Neu', Relations.UnitName);
  Assert.AreEqual('A,Fremd', Names(Relations.Uses_));
  Assert.IsFalse(Find(Relations.Uses_, 'A').Library_);
  Assert.IsTrue(Find(Relations.Uses_, 'Fremd').Library_);
  Assert.IsNull(Relations.UsedBy);
  Assert.AreEqual(0, Relations.RecompileCount);
end;

procedure TUnitRelationsTests.JsonCarriesAllFields;
var
  Json: TJSONObject;
  Item: TJSONObject;
begin
  Json := TUnitRelationsBuilder.ToJson(Build(FGraph, FLocator, Reader, FileOf('A'), 1,
    TArray<string>.Create('System')));
  try
    Assert.IsTrue(Json.GetValue<Boolean>('found'));
    Assert.AreEqual('A', Json.GetValue<string>('unit'));
    Assert.AreEqual(4, Json.GetValue<Integer>('recompileCount'));
    Assert.IsTrue(Json.GetValue<Boolean>('inCycle'));
    Assert.AreEqual(3, Json.GetValue<TJSONArray>('uses').Count);
    Item := Json.GetValue<TJSONArray>('uses').Items[0] as TJSONObject;
    Assert.AreEqual('B', Item.GetValue<string>('name'));
    Assert.AreEqual('interface', Item.GetValue<string>('section'));
    Assert.IsTrue(Item.GetValue<Boolean>('cycle'));
    Assert.AreEqual('A → B → A', Item.GetValue('cyclePath').Value);
    Assert.AreEqual(3, Item.GetValue<Integer>('location.line'));
    Item := Json.GetValue<TJSONArray>('uses').Items[1] as TJSONObject;
    Assert.IsTrue(Item.GetValue<Boolean>('library'));
    Assert.IsTrue(Item.GetValue<Boolean>('unused'));
    Assert.IsNull(Item.GetValue('file'));
    Item := Json.GetValue<TJSONArray>('usedBy').Items[2] as TJSONObject;
    Assert.AreEqual('F', Item.GetValue<string>('name'));
    Assert.AreEqual('implementation', Item.GetValue<string>('section'));
    Assert.IsNull(Item.GetValue('cycle'));
  finally
    Json.Free;
  end;
end;

procedure TUnitRelationsTests.OnlyImplementationEntriesAreMarked;
var
  Relations: TUnitRelations;
  Builder: TUnitRelationsBuilder;
  Json, Item: TJSONObject;
begin
  // B steht im interface und wird nur in der implementation gebraucht; C steht schon dort.
  Relations := Build(FGraph, FLocator, Reader, FileOf('A'), 1, nil);
  Assert.IsFalse(Find(Relations.Uses_, 'B').OnlyImplementation, 'ohne Angabe nichts');
  Json := nil;
  try
    Builder := TUnitRelationsBuilder.Create(FGraph, FLocator, Reader, NoDefines);
    try
      Relations := Builder.Build(FileOf('A'), 1, nil, TArray<string>.Create('X.B', 'C'));
    finally
      Builder.Free;
    end;
    Assert.IsTrue(Find(Relations.Uses_, 'B').OnlyImplementation, 'mit Namensraum geschrieben');
    Assert.IsFalse(Find(Relations.Uses_, 'C').OnlyImplementation, 'steht schon im implementation-uses');
    Assert.IsFalse(Find(Relations.Uses_, 'System').OnlyImplementation);
    Json := TUnitRelationsBuilder.ToJson(Relations);
    Item := Json.GetValue<TJSONArray>('uses').Items[0] as TJSONObject;
    Assert.IsTrue(Item.GetValue<Boolean>('onlyImplementation'));
    Item := Json.GetValue<TJSONArray>('uses').Items[2] as TJSONObject;
    Assert.IsNull(Item.GetValue('onlyImplementation'));
  finally
    Json.Free;
  end;
end;

/// <summary>Kosten in einem eigenen Graphen aus AUnits.</summary>
function CostIn(const AUnits: TArray<TUnitIndex>; const AName: string; ALimit: Integer): TUnitInterfaceCost;
var
  Graph: TUsesGraph;
begin
  Graph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TUnitRelationsBuilder.InterfaceCost(Graph, FileOf(AName), ALimit);
  finally
    Graph.Free;
  end;
end;

procedure TUnitRelationsTests.InterfaceCostFollowsChain;
var
  Units: TArray<TUnitIndex>;
  Cost: TUnitInterfaceCost;
begin
  // Kette Oben → Mitte → Unten über interface-uses: Eine Änderung in Unten übersetzt zwei Units neu.
  Units := TArray<TUnitIndex>.Create(UsesUnit('Oben', ['Mitte'], nil), UsesUnit('Mitte', ['Unten'], nil),
    UsesUnit('Unten', nil, nil));
  Cost := CostIn(Units, 'Unten', 10);
  Assert.IsTrue(Cost.Found);
  Assert.AreEqual('Unten', Cost.UnitName);
  Assert.AreEqual(2, Cost.RecompileCount);
  Assert.AreEqual('Mitte,Oben', string.Join(',', Cost.Units), 'nach Name');
  Assert.AreEqual(1, CostIn(Units, 'Mitte', 10).RecompileCount);
  Assert.AreEqual(0, CostIn(Units, 'Oben', 10).RecompileCount, 'niemand verwendet Oben');
  // Oben verwendet Mitte nur im implementation: Mitte wird neu übersetzt, Oben auch (es verwendet Mitte),
  // weil Mitte Unten im interface verwendet.
  Units := TArray<TUnitIndex>.Create(UsesUnit('Oben', nil, ['Mitte']), UsesUnit('Mitte', ['Unten'], nil),
    UsesUnit('Unten', nil, nil));
  Assert.AreEqual(2, CostIn(Units, 'Unten', 10).RecompileCount);
end;

procedure TUnitRelationsTests.InterfaceCostStopsAtImplementationUses;
var
  Units: TArray<TUnitIndex>;
  Cost: TUnitInterfaceCost;
begin
  // Mitte verwendet Unten nur im implementation: Das interface von Mitte bleibt, Oben bleibt übersetzt.
  Units := TArray<TUnitIndex>.Create(UsesUnit('Oben', ['Mitte'], nil), UsesUnit('Mitte', nil, ['Unten']),
    UsesUnit('Unten', nil, nil));
  Cost := CostIn(Units, 'Unten', 10);
  Assert.AreEqual(1, Cost.RecompileCount);
  Assert.AreEqual('Mitte', string.Join(',', Cost.Units));
  Cost := CostIn(Units, 'Fehlt', 10);
  Assert.IsFalse(Cost.Found, 'nicht im Graphen');
  Assert.AreEqual('Fehlt', Cost.UnitName);
  Assert.AreEqual(0, Cost.RecompileCount);
  Assert.IsNull(Cost.Units);
end;

procedure TUnitRelationsTests.InterfaceCostJsonAndLimit;
var
  Cost: TUnitInterfaceCost;
  Json: TJSONObject;
begin
  // A: B, E, F direkt, G über E (siehe RecompileCountMatchesGraph); nur die ersten zwei Namen.
  Cost := TUnitRelationsBuilder.InterfaceCost(FGraph, FileOf('A'), 2);
  Assert.AreEqual(4, Cost.RecompileCount);
  Assert.AreEqual('B,E', string.Join(',', Cost.Units));
  Assert.AreEqual(0, Integer(Length(TUnitRelationsBuilder.InterfaceCost(FGraph, FileOf('A'), 0).Units)));
  Json := TUnitRelationsBuilder.CostToJson(Cost);
  try
    Assert.IsTrue(Json.GetValue<Boolean>('found'));
    Assert.AreEqual('A', Json.GetValue<string>('unit'));
    Assert.AreEqual(FileOf('A'), Json.GetValue<string>('file'));
    Assert.AreEqual(4, Json.GetValue<Integer>('recompileCount'));
    Assert.AreEqual(2, Json.GetValue<TJSONArray>('units').Count);
    Assert.AreEqual('E', Json.GetValue<TJSONArray>('units').Items[1].Value);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRelationsTests);

end.
