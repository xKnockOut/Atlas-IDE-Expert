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
    [Test]
    procedure UseCandidatesMarkInterfaceCycles;
    [Test]
    procedure UseInfoJsonCarriesPaths;
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
  begin
    Result := Result + 'uses'#10 + '  ' + string.Join(', ', AInterface) + ';'#10;
  end;
  Result := Result + 'implementation'#10;
  if AImplementation <> nil then
  begin
    Result := Result + 'uses'#10 + '  ' + string.Join(', ', AImplementation) + ';'#10;
  end;
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
  mRelation: TUnitRelation;
begin
  for mRelation in ARelations do
  begin
    if SameText(mRelation.Name, AName) then
    begin
      Exit(mRelation);
    end;
  end;
  Assert.Fail(AName + ' fehlt');
  Result := Default(TUnitRelation);
end;

function Names(const ARelations: TArray<TUnitRelation>): string;
var
  mRelation: TUnitRelation;
begin
  Result := '';
  for mRelation in ARelations do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mRelation.Name;
  end;
end;

{ TUnitRelationsTests }

procedure TUnitRelationsTests.Setup;
var
  mUnits: TArray<TUnitIndex>;

  procedure Add(const AName: string; const AInterface, AImplementation: TArray<string>);
  begin
    mUnits := mUnits + [UsesUnit(AName, AInterface, AImplementation)];
    FTexts.AddOrSetValue(FileOf(AName), UnitSource(AName, AInterface, AImplementation));
  end;

begin
  // A ↔ B über interface (Zyklus); A verwendet C im implementation, C → D; System kennt der Graph nicht.
  // Verwender von A: B und E im interface, F im implementation; G → E (impl), H → F (impl).
  FTexts := TDictionary<string, string>.Create;
  mUnits := nil;
  Add('A', ['B', 'System'], ['C']);
  Add('B', ['A'], nil);
  Add('C', ['D'], nil);
  Add('D', nil, nil);
  Add('E', ['A'], nil);
  Add('F', nil, ['A']);
  Add('G', nil, ['E']);
  Add('H', nil, ['F']);
  FGraph := TUsesGraph.Create(mUnits, TUsesGraphOptions.Default);
  FLocator := TUsesLocator.Create(Reader(), NoDefines());
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
  mTexts: TDictionary<string, string>;
begin
  mTexts := FTexts;
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mTexts.TryGetValue(AFileName, AText);
    end;
end;

function Build(AGraph: TUsesGraph; ALocator: TUsesLocator; const AReader: TUsesTextReader; const AFileName: string;
  ADepth: Integer; const AUnused: TArray<string>): TUnitRelations;
var
  mBuilder: TUnitRelationsBuilder;
begin
  mBuilder := TUnitRelationsBuilder.Create(AGraph, ALocator, AReader, NoDefines());
  try
    Result := mBuilder.Build(AFileName, ADepth, AUnused);
  finally
    mBuilder.Free;
  end;
end;

procedure TUnitRelationsTests.UsesComeFromTextWithLibrary;
var
  mRelations: TUnitRelations;
  mSystem_: TUnitRelation;
begin
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('A'), 1, nil);
  Assert.IsTrue(mRelations.Found);
  Assert.AreEqual('A', mRelations.UnitName);
  Assert.AreEqual('B,System,C', Names(mRelations.Uses_), 'Quelltextreihenfolge, erst interface');
  Assert.AreEqual(Ord(TUsesSection.Interface_), Ord(Find(mRelations.Uses_, 'B').Section));
  Assert.AreEqual(Ord(TUsesSection.Implementation_), Ord(Find(mRelations.Uses_, 'C').Section));
  mSystem_ := Find(mRelations.Uses_, 'System');
  Assert.IsTrue(mSystem_.Library_, 'ohne Knoten: Bibliothek');
  Assert.AreEqual('', mSystem_.FileName);
  Assert.IsFalse(Find(mRelations.Uses_, 'B').Library_);
  Assert.AreEqual(FileOf('B'), Find(mRelations.Uses_, 'B').FileName);
  // Fundstelle: der Eintrag in A selbst, Zeile 3 (0-basiert), Spalte 2.
  Assert.AreEqual(FileOf('A'), Find(mRelations.Uses_, 'B').LocationFile);
  Assert.AreEqual(3, Find(mRelations.Uses_, 'B').Line);
  Assert.AreEqual(2, Find(mRelations.Uses_, 'B').Character);
  Assert.AreEqual(6, Find(mRelations.Uses_, 'C').Line);
  Assert.IsNull(Find(mRelations.Uses_, 'C').Children, 'direkt: ohne Kinder');
end;

procedure TUnitRelationsTests.UsedByListsSectionsAndLocations;
var
  mRelations: TUnitRelations;
  F: TUnitRelation;
begin
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('A'), 1, nil);
  Assert.AreEqual('B,E,F', Names(mRelations.UsedBy), 'genau drei, nach Name');
  Assert.AreEqual(Ord(TUsesSection.Interface_), Ord(Find(mRelations.UsedBy, 'B').Section));
  Assert.AreEqual(Ord(TUsesSection.Interface_), Ord(Find(mRelations.UsedBy, 'E').Section));
  F := Find(mRelations.UsedBy, 'F');
  Assert.AreEqual(Ord(TUsesSection.Implementation_), Ord(F.Section));
  // Fundstelle: der Eintrag in der verwendenden Unit F.
  Assert.AreEqual(FileOf('F'), F.LocationFile);
  Assert.AreEqual(4, F.Line);
  Assert.IsFalse(F.Cycle);
  Assert.AreEqual(5, mRelations.DependentCount, 'transitiv: B, E, F, G, H');
  Assert.AreEqual(3, mRelations.DependencyCount, 'B, C, D');
end;

procedure TUnitRelationsTests.InterfaceCycleIsMarkedWithPath;
var
  mRelations: TUnitRelations;
begin
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('A'), 1, nil);
  Assert.IsTrue(mRelations.InCycle);
  Assert.AreEqual('A → B → A', mRelations.CyclePath);
  Assert.IsTrue(Find(mRelations.Uses_, 'B').Cycle, 'Verwendet: B rot');
  Assert.AreEqual('A → B → A', Find(mRelations.Uses_, 'B').CyclePath);
  Assert.IsFalse(Find(mRelations.Uses_, 'C').Cycle);
  Assert.IsFalse(Find(mRelations.Uses_, 'System').Cycle);
  Assert.IsTrue(Find(mRelations.UsedBy, 'B').Cycle, 'Wird verwendet von: B rot');
  Assert.AreEqual('A → B → A', Find(mRelations.UsedBy, 'B').CyclePath);
  Assert.IsFalse(Find(mRelations.UsedBy, 'E').Cycle, 'E verwendet A, aber A nicht E');
  // C liegt in keinem Zyklus.
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('C'), 1, nil);
  Assert.IsFalse(mRelations.InCycle);
  Assert.AreEqual('', mRelations.CyclePath);
end;

procedure TUnitRelationsTests.RecompileCountMatchesGraph;
var
  mRelations: TUnitRelations;
begin
  // A ändert sein interface: B, E, F direkt; G über E (interface); H nicht (F verwendet A im implementation).
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('A'), 1, nil);
  Assert.AreEqual(4, mRelations.RecompileCount);
  Assert.AreEqual(FGraph.RecompileCount(FGraph.IndexOf('A')), mRelations.RecompileCount);
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('D'), 1, nil);
  // D: C, dann über C (interface) A, über A (interface) B und E sowie F und G.
  Assert.AreEqual(FGraph.RecompileCount(FGraph.IndexOf('D')), mRelations.RecompileCount);
  Assert.AreEqual(1, Integer(Length(mRelations.UsedBy)));
end;

procedure TUnitRelationsTests.AllLevelsExpandEachUnitOnce;
var
  mRelations: TUnitRelations;
  B, C, E: TUnitRelation;
begin
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('A'), 0, nil);
  C := Find(mRelations.Uses_, 'C');
  Assert.AreEqual('D', Names(C.Children));
  B := Find(mRelations.Uses_, 'B');
  Assert.AreEqual('A', Names(B.Children), 'B verwendet A');
  Assert.IsTrue(B.Children[0].Repeated, 'A ist die Wurzel: nicht noch einmal aufklappen');
  Assert.IsNull(B.Children[0].Children);
  Assert.IsNull(Find(mRelations.Uses_, 'System').Children);
  E := Find(mRelations.UsedBy, 'E');
  Assert.AreEqual('G', Names(E.Children));
  Assert.AreEqual('H', Names(Find(mRelations.UsedBy, 'F').Children));
  Assert.IsTrue(Find(mRelations.UsedBy, 'B').Children[0].Repeated);
  Assert.IsFalse(E.Children[0].Repeated, 'G hat keine Verwender');
end;

procedure TUnitRelationsTests.LimitedDepthStopsTree;
var
  mRelations: TUnitRelations;
  mUnits: TArray<TUnitIndex>;
  mGraph: TUsesGraph;
begin
  // Zwei Ebenen: Kinder der ersten Ebene ja, Enkel nein.
  mUnits := TArray<TUnitIndex>.Create(UsesUnit('A', ['B'], nil), UsesUnit('B', ['C'], nil),
    UsesUnit('C', ['D'], nil), UsesUnit('D', nil, nil));
  FTexts.AddOrSetValue(FileOf('A'), UnitSource('A', ['B'], nil));
  mGraph := TUsesGraph.Create(mUnits, TUsesGraphOptions.Default);
  try
    mRelations := Build(mGraph, nil, Reader(), FileOf('A'), 2, nil);
    Assert.AreEqual('C', Names(Find(mRelations.Uses_, 'B').Children));
    Assert.IsNull(Find(mRelations.Uses_, 'B').Children[0].Children, 'Tiefe 2');
    mRelations := Build(mGraph, nil, Reader(), FileOf('A'), 3, nil);
    Assert.AreEqual('D', Names(Find(mRelations.Uses_, 'B').Children[0].Children));
    Assert.AreEqual(-1, Find(Find(mRelations.Uses_, 'B').Children, 'C').Line, 'ohne Locator keine Fundstelle');
  finally
    mGraph.Free;
  end;
end;

procedure TUnitRelationsTests.UnusedEntriesAreMarked;
var
  mRelations: TUnitRelations;
begin
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('A'), 1, TArray<string>.Create('System', 'X.C'));
  Assert.IsTrue(Find(mRelations.Uses_, 'System').Unused);
  Assert.IsFalse(Find(mRelations.Uses_, 'B').Unused);
  Assert.IsTrue(Find(mRelations.Uses_, 'C').Unused, 'mit Namensraum geschrieben');
end;

procedure TUnitRelationsTests.UnknownFileHasOnlyTextUses;
var
  mRelations: TUnitRelations;
begin
  FTexts.AddOrSetValue('C:\Neu\Neu.pas', UnitSource('Neu', ['A'], ['Fremd']));
  mRelations := Build(FGraph, FLocator, Reader(), 'C:\Neu\Neu.pas', 0, nil);
  Assert.IsFalse(mRelations.Found);
  Assert.AreEqual('Neu', mRelations.UnitName);
  Assert.AreEqual('A,Fremd', Names(mRelations.Uses_));
  Assert.IsFalse(Find(mRelations.Uses_, 'A').Library_);
  Assert.IsTrue(Find(mRelations.Uses_, 'Fremd').Library_);
  Assert.IsNull(mRelations.UsedBy);
  Assert.AreEqual(0, mRelations.RecompileCount);
end;

procedure TUnitRelationsTests.JsonCarriesAllFields;
var
  mJson: TJSONObject;
  mItem: TJSONObject;
begin
  mJson := TUnitRelationsBuilder.ToJson(Build(FGraph, FLocator, Reader(), FileOf('A'), 1,
    TArray<string>.Create('System')));
  try
    Assert.IsTrue(mJson.GetValue<Boolean>('found'));
    Assert.AreEqual('A', mJson.GetValue<string>('unit'));
    Assert.AreEqual(4, mJson.GetValue<Integer>('recompileCount'));
    Assert.IsTrue(mJson.GetValue<Boolean>('inCycle'));
    Assert.AreEqual(3, mJson.GetValue<TJSONArray>('uses').Count);
    mItem := mJson.GetValue<TJSONArray>('uses').Items[0] as TJSONObject;
    Assert.AreEqual('B', mItem.GetValue<string>('name'));
    Assert.AreEqual('interface', mItem.GetValue<string>('section'));
    Assert.IsTrue(mItem.GetValue<Boolean>('cycle'));
    Assert.AreEqual('A → B → A', mItem.GetValue('cyclePath').Value);
    Assert.AreEqual(3, mItem.GetValue<Integer>('location.line'));
    mItem := mJson.GetValue<TJSONArray>('uses').Items[1] as TJSONObject;
    Assert.IsTrue(mItem.GetValue<Boolean>('library'));
    Assert.IsTrue(mItem.GetValue<Boolean>('unused'));
    Assert.IsNull(mItem.GetValue('file'));
    mItem := mJson.GetValue<TJSONArray>('usedBy').Items[2] as TJSONObject;
    Assert.AreEqual('F', mItem.GetValue<string>('name'));
    Assert.AreEqual('implementation', mItem.GetValue<string>('section'));
    Assert.IsNull(mItem.GetValue('cycle'));
  finally
    mJson.Free;
  end;
end;

procedure TUnitRelationsTests.OnlyImplementationEntriesAreMarked;
var
  mRelations: TUnitRelations;
  mBuilder: TUnitRelationsBuilder;
  mJson, mItem: TJSONObject;
begin
  // B steht im interface und wird nur in der implementation gebraucht; C steht schon dort.
  mRelations := Build(FGraph, FLocator, Reader(), FileOf('A'), 1, nil);
  Assert.IsFalse(Find(mRelations.Uses_, 'B').OnlyImplementation, 'ohne Angabe nichts');
  mJson := nil;
  try
    mBuilder := TUnitRelationsBuilder.Create(FGraph, FLocator, Reader(), NoDefines());
    try
      mRelations := mBuilder.Build(FileOf('A'), 1, nil, TArray<string>.Create('X.B', 'C'));
    finally
      mBuilder.Free;
    end;
    Assert.IsTrue(Find(mRelations.Uses_, 'B').OnlyImplementation, 'mit Namensraum geschrieben');
    Assert.IsFalse(Find(mRelations.Uses_, 'C').OnlyImplementation, 'steht schon im implementation-uses');
    Assert.IsFalse(Find(mRelations.Uses_, 'System').OnlyImplementation);
    mJson := TUnitRelationsBuilder.ToJson(mRelations);
    mItem := mJson.GetValue<TJSONArray>('uses').Items[0] as TJSONObject;
    Assert.IsTrue(mItem.GetValue<Boolean>('onlyImplementation'));
    mItem := mJson.GetValue<TJSONArray>('uses').Items[2] as TJSONObject;
    Assert.IsNull(mItem.GetValue('onlyImplementation'));
  finally
    mJson.Free;
  end;
end;

/// <summary>Kosten in einem eigenen Graphen aus AUnits.</summary>
function CostIn(const AUnits: TArray<TUnitIndex>; const AName: string; ALimit: Integer): TUnitInterfaceCost;
var
  mGraph: TUsesGraph;
begin
  mGraph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TUnitRelationsBuilder.InterfaceCost(mGraph, FileOf(AName), ALimit);
  finally
    mGraph.Free;
  end;
end;

procedure TUnitRelationsTests.InterfaceCostFollowsChain;
var
  mUnits: TArray<TUnitIndex>;
  mCost: TUnitInterfaceCost;
begin
  // Kette Oben → Mitte → Unten über interface-uses: Eine Änderung in Unten übersetzt zwei Units neu.
  mUnits := TArray<TUnitIndex>.Create(UsesUnit('Oben', ['Mitte'], nil), UsesUnit('Mitte', ['Unten'], nil),
    UsesUnit('Unten', nil, nil));
  mCost := CostIn(mUnits, 'Unten', 10);
  Assert.IsTrue(mCost.Found);
  Assert.AreEqual('Unten', mCost.UnitName);
  Assert.AreEqual(2, mCost.RecompileCount);
  Assert.AreEqual('Mitte,Oben', string.Join(',', mCost.Units), 'nach Name');
  Assert.AreEqual(1, CostIn(mUnits, 'Mitte', 10).RecompileCount);
  Assert.AreEqual(0, CostIn(mUnits, 'Oben', 10).RecompileCount, 'niemand verwendet Oben');
  // Oben verwendet Mitte nur im implementation: Mitte wird neu übersetzt, Oben auch (es verwendet Mitte),
  // weil Mitte Unten im interface verwendet.
  mUnits := TArray<TUnitIndex>.Create(UsesUnit('Oben', nil, ['Mitte']), UsesUnit('Mitte', ['Unten'], nil),
    UsesUnit('Unten', nil, nil));
  Assert.AreEqual(2, CostIn(mUnits, 'Unten', 10).RecompileCount);
end;

procedure TUnitRelationsTests.InterfaceCostStopsAtImplementationUses;
var
  mUnits: TArray<TUnitIndex>;
  mCost: TUnitInterfaceCost;
begin
  // Mitte verwendet Unten nur im implementation: Das interface von Mitte bleibt, Oben bleibt übersetzt.
  mUnits := TArray<TUnitIndex>.Create(UsesUnit('Oben', ['Mitte'], nil), UsesUnit('Mitte', nil, ['Unten']),
    UsesUnit('Unten', nil, nil));
  mCost := CostIn(mUnits, 'Unten', 10);
  Assert.AreEqual(1, mCost.RecompileCount);
  Assert.AreEqual('Mitte', string.Join(',', mCost.Units));
  mCost := CostIn(mUnits, 'Fehlt', 10);
  Assert.IsFalse(mCost.Found, 'nicht im Graphen');
  Assert.AreEqual('Fehlt', mCost.UnitName);
  Assert.AreEqual(0, mCost.RecompileCount);
  Assert.IsNull(mCost.Units);
end;

procedure TUnitRelationsTests.InterfaceCostJsonAndLimit;
var
  mCost: TUnitInterfaceCost;
  mJson: TJSONObject;
begin
  // A: B, E, F direkt, G über E (siehe RecompileCountMatchesGraph); nur die ersten zwei Namen.
  mCost := TUnitRelationsBuilder.InterfaceCost(FGraph, FileOf('A'), 2);
  Assert.AreEqual(4, mCost.RecompileCount);
  Assert.AreEqual('B,E', string.Join(',', mCost.Units));
  Assert.AreEqual(0, Integer(Length(TUnitRelationsBuilder.InterfaceCost(FGraph, FileOf('A'), 0).Units)));
  mJson := TUnitRelationsBuilder.CostToJson(mCost);
  try
    Assert.IsTrue(mJson.GetValue<Boolean>('found'));
    Assert.AreEqual('A', mJson.GetValue<string>('unit'));
    Assert.AreEqual(FileOf('A'), mJson.GetValue<string>('file'));
    Assert.AreEqual(4, mJson.GetValue<Integer>('recompileCount'));
    Assert.AreEqual(2, mJson.GetValue<TJSONArray>('units').Count);
    Assert.AreEqual('E', mJson.GetValue<TJSONArray>('units').Items[1].Value);
  finally
    mJson.Free;
  end;
end;

/// <summary>„Unit verwenden“-Kandidaten in einem eigenen Graphen aus AUnits.</summary>
function UseIn(const AUnits: TArray<TUnitIndex>; const AName: string): TUnitUseInfo;
var
  mGraph: TUsesGraph;
begin
  mGraph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TUnitRelationsBuilder.UseCandidates(mGraph, FileOf(AName));
  finally
    mGraph.Free;
  end;
end;

procedure TUnitRelationsTests.UseCandidatesMarkInterfaceCycles;
var
  mUnits: TArray<TUnitIndex>;
  mInfo: TUnitUseInfo;
begin
  // Oben → Mitte → Unten über interface-uses, Seite → Unten nur im implementation.
  mUnits := TArray<TUnitIndex>.Create(UsesUnit('Oben', ['Mitte'], nil), UsesUnit('Mitte', ['Unten'], nil),
    UsesUnit('Seite', nil, ['Unten']), UsesUnit('Unten', nil, nil), UsesUnit('Fremd', nil, nil));
  mInfo := UseIn(mUnits, 'Unten');
  Assert.IsTrue(mInfo.Found);
  Assert.AreEqual('Unten', mInfo.UnitName);
  Assert.AreEqual(3, Integer(Length(mInfo.Candidates)), 'Fremd verwendet Unten nicht');
  Assert.AreEqual('Mitte', mInfo.Candidates[0].Name, 'nach Name');
  Assert.AreEqual(FileOf('Mitte'), mInfo.Candidates[0].FileName);
  // Unten nimmt Mitte ins interface: Mitte braucht Unten schon im interface, der Compiler lehnt das ab.
  Assert.AreEqual('Unten → Mitte → Unten', mInfo.Candidates[0].InterfacePath);
  Assert.AreEqual('Unten → Mitte → Unten', mInfo.Candidates[0].Path);
  Assert.AreEqual('Oben', mInfo.Candidates[1].Name);
  Assert.AreEqual('Unten → Oben → Mitte → Unten', mInfo.Candidates[1].InterfacePath, 'auch über Umwege');
  // Seite verwendet Unten nur im implementation: erlaubter Kreis, nur ein Hinweis.
  Assert.AreEqual('Seite', mInfo.Candidates[2].Name);
  Assert.AreEqual('', mInfo.Candidates[2].InterfacePath);
  Assert.AreEqual('Unten → Seite → Unten', mInfo.Candidates[2].Path);
  // Oben verwendet niemand: kein Kreis möglich.
  Assert.AreEqual(0, Integer(Length(UseIn(mUnits, 'Oben').Candidates)));
  mInfo := UseIn(mUnits, 'Fehlt');
  Assert.IsFalse(mInfo.Found, 'nicht im Graphen');
  Assert.AreEqual('Fehlt', mInfo.UnitName);
  Assert.IsNull(mInfo.Candidates);
end;

procedure TUnitRelationsTests.UseInfoJsonCarriesPaths;
var
  mUnits: TArray<TUnitIndex>;
  mJson: TJSONObject;
  mCycles: TJSONArray;
begin
  mUnits := TArray<TUnitIndex>.Create(UsesUnit('Mitte', ['Unten'], nil), UsesUnit('Seite', nil, ['Unten']),
    UsesUnit('Unten', nil, nil));
  mJson := TUnitRelationsBuilder.UseInfoToJson(UseIn(mUnits, 'Unten'));
  try
    Assert.IsTrue(mJson.GetValue<Boolean>('found'));
    Assert.AreEqual('Unten', mJson.GetValue<string>('unit'));
    Assert.AreEqual(FileOf('Unten'), mJson.GetValue<string>('file'));
    mCycles := mJson.GetValue<TJSONArray>('cycles');
    Assert.AreEqual(2, mCycles.Count);
    Assert.AreEqual('Mitte', (mCycles.Items[0] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual(FileOf('Mitte'), (mCycles.Items[0] as TJSONObject).GetValue<string>('file'));
    Assert.AreEqual('Unten → Mitte → Unten', (mCycles.Items[0] as TJSONObject).GetValue('interfacePath').Value);
    Assert.IsNull((mCycles.Items[1] as TJSONObject).GetValue('interfacePath'), 'nur über implementation');
    Assert.AreEqual('Unten → Seite → Unten', (mCycles.Items[1] as TJSONObject).GetValue('path').Value);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRelationsTests);

end.
