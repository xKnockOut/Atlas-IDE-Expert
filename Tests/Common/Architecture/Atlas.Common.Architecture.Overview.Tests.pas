unit Atlas.Common.Architecture.Overview.Tests;

// Tests der Architekturübersicht (#1118): Teilsysteme mit Namen,
// Zusammenhalt, Ausreißer, zentrale Units mit Rolle, Zyklen,
// Querverbindungen mit Fundstelle, Steckbrief, Determinismus, Laufzeit;
// Feinheit γ der Gruppierung (#1366); Nachteilung übergroßer und loser
// Teilsysteme (#1364); Fundament-Units beim Gruppieren (#1365); Zuordnung
// einer Unit zu ihrem Teilsystem (#1368).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TOverviewTests = class
  public
    [Test]
    procedure FindsNamedSubsystems;
    [Test]
    procedure MisplacedUnitIsOutlier;
    [Test]
    procedure RanksCentralUnits;
    [Test]
    procedure ReportsCyclesInterfaceFirst;
    [Test]
    procedure ReportsRareCrossLinkWithLocation;
    [Test]
    procedure ProfileListsNeighbours;
    [Test]
    procedure SameInputSameResult;
    [Test]
    procedure NamespacePartsAndRelativePath;
    [Test]
    [Category('Benchmark')]
    procedure TwoThousandUnitsAreFast;
    [Test]
    procedure ResolutionOneMatchesDefault;
    [Test]
    procedure SmallResolutionMergesNeighbours;
    [Test]
    procedure GroupingIsClampedAndKeyed;
    [Test]
    procedure SplitsOversizedSubsystem;
    [Test]
    procedure WithoutSplitSettingsLikeBefore;
    [Test]
    procedure SplitIsDeterministic;
    [Test]
    procedure SplitThresholds;
    [Test]
    procedure SplitStopsAfterTwoLevels;
    [Test]
    [Category('Benchmark')]
    procedure SplittingTwoThousandUnitsIsFast;
    [Test]
    procedure FoundationsGroupedLikeBefore;
    [Test]
    procedure FoundationsSeparate;
    [Test]
    procedure FoundationsAttached;
    [Test]
    procedure LocalFoundationStays;
    [Test]
    procedure FoundationsTextAndKey;
    [Test]
    procedure AssignmentListsEdgesPerSubsystem;
    [Test]
    procedure AssignmentTieSortedByName;
    [Test]
    procedure AssignmentCloseThreshold;
    [Test]
    procedure AssignmentFoundationDoesNotCount;
    [Test]
    procedure OutliersMatchAssignments;
    [Test]
    [Category('Benchmark')]
    procedure AssignmentsAreCheap;
  end;

/// <summary>Testgraph der Zuordnung (#1368): Z.Own.Mid mit Summe 8 im eigenen und 6 im anderen Teilsystem.
/// </summary>
function AssignmentProject: TArray<TUnitIndex>;
/// <summary>Testgraph der Fundamente (#1365).</summary>
function FoundationProject: TArray<TUnitIndex>;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.UsesGraph.Tests;

/// <summary>Drei Namensräume Core, Data, Ui mit je vier eng verbundenen Units; Data.Db → Core.Base und
/// Ui.Main → Data.Model sind die einzigen Kanten zwischen den Teilsystemen.</summary>
function Project: TArray<TUnitIndex>;
begin
  Result := nil;
  Result := Result + [UsesUnit('App.Core.Base', nil, nil), UsesUnit('App.Core.Types', ['App.Core.Base'], nil),
    UsesUnit('App.Core.Log', ['App.Core.Base', 'App.Core.Types'], nil),
    UsesUnit('App.Core.Util', ['App.Core.Base', 'App.Core.Types'], nil)];
  Result := Result + [UsesUnit('App.Data.Db', nil, ['App.Core.Base']), UsesUnit('App.Data.Model', ['App.Data.Db'],
    nil), UsesUnit('App.Data.Query', ['App.Data.Db', 'App.Data.Model'], nil),
    UsesUnit('App.Data.Cache', ['App.Data.Query', 'App.Data.Model'], nil)];
  Result := Result + [UsesUnit('App.Ui.Theme', nil, nil), UsesUnit('App.Ui.Grid', ['App.Ui.Theme'], nil),
    UsesUnit('App.Ui.Form', ['App.Ui.Theme', 'App.Ui.Grid'], nil),
    UsesUnit('App.Ui.Main', ['App.Ui.Form', 'App.Ui.Grid'], ['App.Data.Model'])];
end;

function Analyze(const AUnits: TArray<TUnitIndex>): TArchitectureOverview;
var
  Graph: TUsesGraph;
begin
  Graph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TArchitectureAnalyzer.Analyze(Graph, nil, 10);
  finally
    Graph.Free;
  end;
end;

function AnalyzeWith(const AUnits: TArray<TUnitIndex>; AResolution: Double): TArchitectureOverview;
var
  mGraph: TUsesGraph;
  mGrouping: TArchitectureGrouping;
begin
  mGrouping := TArchitectureGrouping.Default;
  mGrouping.Resolution := AResolution;
  mGraph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TArchitectureAnalyzer.Analyze(mGraph, nil, 10, mGrouping);
  finally
    mGraph.Free;
  end;
end;

/// <summary>Zwei Dreiergruppen A und B, die über drei interface-Kanten eng verbunden sind.</summary>
function TwoCoupledGroups: TArray<TUnitIndex>;
begin
  Result := nil;
  Result := Result + [UsesUnit('X.A.One', nil, nil), UsesUnit('X.A.Two', ['X.A.One'], nil),
    UsesUnit('X.A.Three', ['X.A.One', 'X.A.Two'], nil)];
  Result := Result + [UsesUnit('X.B.One', ['X.A.One'], nil), UsesUnit('X.B.Two', ['X.B.One', 'X.A.Two'], nil),
    UsesUnit('X.B.Three', ['X.B.One', 'X.B.Two', 'X.A.Three'], nil)];
end;

function AnalyzeGrouped(const AUnits: TArray<TUnitIndex>; const AGrouping: TArchitectureGrouping):
  TArchitectureOverview;
var
  mGraph: TUsesGraph;
begin
  mGraph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TArchitectureAnalyzer.Analyze(mGraph, nil, 10, AGrouping);
  finally
    mGraph.Free;
  end;
end;

/// <summary>Drei dichte Gruppen Big.Lsp, Big.Rules und Big.Index zu je 12 Units (jede verwendet alle vorigen),
/// untereinander mit je zwei Kanten verbunden, dazu Rest.Core mit 80 Units als dichter interface-Block. Neben dem
/// großen Block sind die drei Gruppen zu klein: Louvain legt sie zu einem Teilsystem mit 36 von 116 Units
/// zusammen (Auflösungsgrenze).</summary>
function BigProject: TArray<TUnitIndex>;
const
  cGroups: array[0..2] of string = ('Lsp', 'Rules', 'Index');
var
  mGroup, mItem, mOther: Integer;
  mUses, mLinks: TArray<string>;
begin
  Result := nil;
  for mGroup := 0 to High(cGroups) do
    for mItem := 1 to 12 do
    begin
      mUses := nil;
      for mOther := 1 to mItem - 1 do
        mUses := mUses + [Format('Big.%s.U%.2d', [cGroups[mGroup], mOther])];
      mLinks := nil;
      if (mGroup > 0) and (mItem <= 2) then
        mLinks := mLinks + [Format('Big.%s.U%.2d', [cGroups[mGroup - 1], mItem])];
      if (mGroup = 2) and (mItem in [3, 4]) then
        mLinks := mLinks + [Format('Big.%s.U%.2d', [cGroups[0], mItem])];
      Result := Result + [UsesUnit(Format('Big.%s.U%.2d', [cGroups[mGroup], mItem]), nil, mUses + mLinks)];
    end;
  for mItem := 1 to 80 do
  begin
    mUses := nil;
    for mOther := 1 to mItem - 1 do
      mUses := mUses + [Format('Rest.Core.K%.2d', [mOther])];
    Result := Result + [UsesUnit(Format('Rest.Core.K%.2d', [mItem]), mUses, nil)];
  end;
end;

/// <summary>Zwei getrennte Gruppen App.Ui (fünf Units) und App.Dbg (vier Units), je als Kette über implementation,
/// die beide über interface stark an App.Common.Logging hängen; App.Tool.Only verwendet nur Logging. Dazu App.Index mit drei Units, die nur sie
/// verwenden, an App.Index.Types (Rolle Fundament, aber nur im eigenen Teilsystem verwendet).</summary>
function FoundationProject: TArray<TUnitIndex>;
begin
  Result := nil;
  Result := Result + [UsesUnit('App.Common.Logging', nil, nil), UsesUnit('App.Tool.Only', ['App.Common.Logging'], nil)];
  Result := Result + [UsesUnit('App.Ui.U1', ['App.Common.Logging'], nil),
    UsesUnit('App.Ui.U2', ['App.Common.Logging'], ['App.Ui.U1']),
    UsesUnit('App.Ui.U3', ['App.Common.Logging'], ['App.Ui.U2']),
    UsesUnit('App.Ui.U4', ['App.Common.Logging'], ['App.Ui.U3']),
    UsesUnit('App.Ui.U5', ['App.Common.Logging'], ['App.Ui.U4'])];
  Result := Result + [UsesUnit('App.Dbg.D1', ['App.Common.Logging'], nil),
    UsesUnit('App.Dbg.D2', ['App.Common.Logging'], ['App.Dbg.D1']),
    UsesUnit('App.Dbg.D3', ['App.Common.Logging'], ['App.Dbg.D2']),
    UsesUnit('App.Dbg.D4', ['App.Common.Logging'], ['App.Dbg.D3'])];
  Result := Result + [UsesUnit('App.Index.Types', nil, nil), UsesUnit('App.Index.A', ['App.Index.Types'], nil),
    UsesUnit('App.Index.B', ['App.Index.Types', 'App.Index.A'], nil),
    UsesUnit('App.Index.C', ['App.Index.Types', 'App.Index.B'], nil)];
end;

function FoundationsWith(AMode: TArchitectureFoundations): TArchitectureOverview;
var
  mGrouping: TArchitectureGrouping;
begin
  // Ohne Nachteilung (#1364), die das zusammengezogene Teilsystem sonst ebenfalls trennen würde.
  mGrouping := TArchitectureGrouping.Default;
  mGrouping.Foundations := AMode;
  mGrouping.MaxShare := 0;
  mGrouping.MinCohesion := 0;
  Result := AnalyzeGrouped(FoundationProject, mGrouping);
end;

function SubsystemOf(const AOverview: TArchitectureOverview; const AUnit: string): string;
begin
  Result := AOverview.Subsystems[AOverview.Units[AOverview.IndexOf(AUnit)].Subsystem].Name;
end;

function UnitNames(const AOverview: TArchitectureOverview; const AUnits: TArray<Integer>): string;
var
  Item: Integer;
begin
  Result := '';
  for Item in AUnits do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + AOverview.Units[Item].Name;
  end;
end;

{ TOverviewTests }

procedure TOverviewTests.FindsNamedSubsystems;
var
  Overview: TArchitectureOverview;
  Subsystem: TOverviewSubsystem;
begin
  Overview := Analyze(Project);
  Assert.AreEqual(3, Integer(Length(Overview.Subsystems)));
  Assert.AreEqual('Core', SubsystemOf(Overview, 'App.Core.Util'));
  Assert.AreEqual('Data', SubsystemOf(Overview, 'App.Data.Cache'));
  Assert.AreEqual('Ui', SubsystemOf(Overview, 'App.Ui.Main'));
  for Subsystem in Overview.Subsystems do
  begin
    Assert.AreEqual(4, Integer(Length(Subsystem.Units)), Subsystem.Name);
    Assert.IsTrue(Subsystem.Cohesion > 0.7, Subsystem.Name);
  end;
  Assert.AreEqual('App.Core.Base', Overview.Units[Overview.Subsystems[0].Central].Name,
    'Gleich groß: nach Name der zentralen Unit');
  Assert.AreEqual(0, Integer(Length(Overview.Outliers)));
  Assert.AreEqual(17, Overview.EdgeCount);
end;

procedure TOverviewTests.MisplacedUnitIsOutlier;
var
  Units: TArray<TUnitIndex>;
  Overview: TArchitectureOverview;
  Outlier: TOverviewOutlier;
begin
  // App.Ui.Export verwendet nur Data-Units: Louvain legt sie zu Data, der Namensraum sagt Ui.
  Units := Project;
  Units := Units + [UsesUnit('App.Ui.Export', ['App.Data.Db', 'App.Data.Query', 'App.Data.Model'], nil)];
  Overview := Analyze(Units);
  Assert.AreEqual('Data', SubsystemOf(Overview, 'App.Ui.Export'));
  Assert.AreEqual(1, Integer(Length(Overview.Outliers)));
  Outlier := Overview.Outliers[0];
  Assert.AreEqual('App.Ui.Export', Overview.Units[Outlier.Unit_].Name);
  Assert.AreEqual('Ui', Overview.Subsystems[Outlier.Suggested].Name);
  Assert.IsTrue(Outlier.Reason = TOverviewOutlierReason.Namespace);
  Assert.AreEqual(3, Outlier.Inside);
  Assert.AreEqual(0, Outlier.Toward);
end;

procedure TOverviewTests.RanksCentralUnits;
var
  Overview: TArchitectureOverview;
  Base: TOverviewUnit;
begin
  Overview := Analyze(Project);
  Base := Overview.Units[Overview.IndexOf('App.Core.Base')];
  Assert.AreEqual(4, Base.Direct, 'Types, Log, Util, Db');
  Assert.AreEqual(0, Base.Uses_);
  // Interface-Änderung an Base: Types, Log, Util, Db direkt; über das interface von Types noch Log und Util.
  Assert.AreEqual(4, Base.Total);
  Assert.IsTrue(Base.Role = TOverviewUnitRole.Foundation);
  Assert.AreEqual('App.Core.Base', Overview.Units[Overview.Central[0]].Name);
  Assert.AreEqual(10, Integer(Length(Overview.Central)), 'auf CentralCount gekürzt');
  Assert.AreEqual('Fundament', TArchitectureAnalyzer.RoleCaption(TOverviewUnitRole.Foundation));
  Assert.AreEqual('Drehscheibe', TArchitectureAnalyzer.RoleCaption(TOverviewUnitRole.Hub));
  Assert.AreEqual('', TArchitectureAnalyzer.RoleCaption(TOverviewUnitRole.None));
end;

procedure TOverviewTests.ReportsCyclesInterfaceFirst;
var
  Overview: TArchitectureOverview;
begin
  // X.A ↔ X.B über implementation (erlaubt, aber berichtet), Y.C ↔ Y.D nur interface (Übersetzungsfehler).
  Overview := Analyze([UsesUnit('X.A', ['X.B'], nil), UsesUnit('X.B', nil, ['X.A']), UsesUnit('Y.C', ['Y.D'], nil),
    UsesUnit('Y.D', ['Y.C'], nil)]);
  Assert.AreEqual(2, Integer(Length(Overview.Cycles)));
  Assert.IsTrue(Overview.Cycles[0].InterfaceOnly);
  Assert.AreEqual('Y.C,Y.D', UnitNames(Overview, Overview.Cycles[0].Component));
  Assert.IsFalse(Overview.Cycles[1].InterfaceOnly);
  Assert.AreEqual('X.A,X.B', UnitNames(Overview, Overview.Cycles[1].Component));
  Assert.AreEqual(2, Integer(Length(Overview.Cycles[1].Edges)));
  Assert.IsFalse(Overview.Cycles[1].Edges[0].Located, 'ohne Locator keine Fundstelle');
end;

procedure TOverviewTests.ReportsRareCrossLinkWithLocation;
var
  Units: TArray<TUnitIndex>;
  Graph: TUsesGraph;
  Locator: TUsesLocator;
  Overview: TArchitectureOverview;
  Link: TOverviewCrossLink;
  Files: TDictionary<string, string>;
  Main: TUnitIndex;
begin
  Units := Project;
  Main := Units[11];
  Files := TDictionary<string, string>.Create;
  Files.Add(Main.FileName, 'unit App.Ui.Main;'#10'interface'#10'uses App.Ui.Form, App.Ui.Grid;'#10 +
    'implementation'#10'uses'#10'  App.Data.Model;'#10'end.');
  Graph := TUsesGraph.Create(Units, TUsesGraphOptions.Default);
  Locator := TUsesLocator.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Files.TryGetValue(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end);
  try
    Overview := TArchitectureAnalyzer.Analyze(Graph, Locator, 5);
    Assert.AreEqual(2, Integer(Length(Overview.CrossLinks)), 'Data.Db → Core.Base und Ui.Main → Data.Model');
    Link := Overview.CrossLinks[1];
    Assert.AreEqual('App.Ui.Main', Overview.Units[Link.Edge.Source].Name);
    Assert.AreEqual('App.Data.Model', Overview.Units[Link.Edge.Target].Name);
    Assert.IsTrue(Link.Reason = TOverviewCrossReason.Rare);
    Assert.AreEqual(1, Link.Forward);
    Assert.AreEqual(0, Link.Backward);
    Assert.IsTrue(Link.Edge.Section = TUsesSection.Implementation_);
    Assert.IsTrue(Link.Edge.Located);
    Assert.AreEqual(5, Link.Edge.Location.Range.StartPos.Line);
    Assert.AreEqual(2, Link.Edge.Location.Range.StartPos.Character);
    Assert.IsFalse(Overview.CrossLinks[0].Edge.Located, 'Datei von Data.Db fehlt');
  finally
    Locator.Free;
    Graph.Free;
    Files.Free;
  end;
end;

procedure TOverviewTests.ProfileListsNeighbours;
var
  Overview: TArchitectureOverview;
  Profile: TOverviewProfile;
begin
  Overview := Analyze(Project);
  Profile := Overview.Profile(Overview.IndexOf('App.Data.Model'));
  Assert.AreEqual('App.Data.Db', UnitNames(Overview, Profile.DependsOn));
  Assert.AreEqual('App.Data.Cache,App.Data.Query,App.Ui.Main', UnitNames(Overview, Profile.UsedBy));
  Assert.AreEqual(1, Integer(Length(Profile.CrossLinks)));
  Assert.AreEqual(0, Integer(Length(Profile.Cycles)));
  Assert.AreEqual(-1, Profile.Outlier);
  Assert.AreEqual(-1, Overview.IndexOf('Fehlt'));
end;

procedure TOverviewTests.SameInputSameResult;
var
  First, Second: TArchitectureOverview;
  Index: Integer;
  Reversed: TArray<TUnitIndex>;
  Units: TArray<TUnitIndex>;
begin
  Units := Project;
  SetLength(Reversed, Length(Units));
  for Index := 0 to High(Units) do
    Reversed[High(Units) - Index] := Units[Index];
  First := Analyze(Units);
  Second := Analyze(Reversed);
  Assert.AreEqual(Integer(Length(First.Subsystems)), Integer(Length(Second.Subsystems)));
  for Index := 0 to High(First.Subsystems) do
  begin
    Assert.AreEqual(First.Subsystems[Index].Name, Second.Subsystems[Index].Name);
    Assert.AreEqual(UnitNames(First, First.Subsystems[Index].Units), UnitNames(Second, Second.Subsystems[Index].Units));
  end;
  Assert.AreEqual(UnitNames(First, First.Central), UnitNames(Second, Second.Central));
end;

procedure TOverviewTests.NamespacePartsAndRelativePath;
var
  Overview: TArchitectureOverview;
begin
  Assert.AreEqual('Atlas|Common|Index', string.Join('|', TArchitectureAnalyzer.NamespaceParts('Atlas.Common.Index.Builder')));
  Assert.AreEqual(0, Integer(Length(TArchitectureAnalyzer.NamespaceParts('SysUtils'))));
  Overview := Default(TArchitectureOverview);
  Overview.Root := 'C:\Projekt';
  Assert.AreEqual('App/Ui/Main.pas', Overview.RelativePath('C:\Projekt\App\Ui\Main.pas'));
  Assert.AreEqual('D:/Fremd/X.pas', Overview.RelativePath('D:\Fremd\X.pas'));
end;

procedure TOverviewTests.TwoThousandUnitsAreFast;
var
  Units: TArray<TUnitIndex>;
  Group, Item, Index: Integer;
  Name: string;
  Watch: TStopwatch;
  Overview: TArchitectureOverview;
begin
  // 20 Namensräume zu je 100 Units: Ring mit Sehnen innen, je Unit eine Kante in den nächsten Namensraum.
  SetLength(Units, 2000);
  for Index := 0 to High(Units) do
  begin
    Group := Index div 100;
    Item := Index mod 100;
    Name := Format('P.N%.2d.U%.3d', [Group, Item]);
    Units[Index] := UsesUnit(Name, [Format('P.N%.2d.U%.3d', [Group, (Item + 1) mod 100]),
      Format('P.N%.2d.U%.3d', [Group, (Item * 7 + 3) mod 100])],
      [Format('P.N%.2d.U%.3d', [Group, (Item * 13 + 5) mod 100]),
      Format('P.N%.2d.U%.3d', [(Group + 1) mod 20, Item])]);
  end;
  Watch := TStopwatch.StartNew;
  Overview := Analyze(Units);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, Format('%d ms', [Watch.ElapsedMilliseconds]));
  Assert.AreEqual(2000, Integer(Length(Overview.Units)));
  Assert.IsTrue(Length(Overview.Subsystems) >= 10, IntToStr(Length(Overview.Subsystems)));
end;

procedure TOverviewTests.ResolutionOneMatchesDefault;
var
  mDefault, mOne: TArchitectureOverview;
  mIndex: Integer;
begin
  mDefault := Analyze(Project);
  mOne := AnalyzeWith(Project, 1);
  Assert.AreEqual(Integer(Length(mDefault.Subsystems)), Integer(Length(mOne.Subsystems)));
  for mIndex := 0 to High(mDefault.Units) do
    Assert.AreEqual(mDefault.Units[mIndex].Subsystem, mOne.Units[mIndex].Subsystem, mDefault.Units[mIndex].Name);
  Assert.AreEqual(Double(1), mDefault.Grouping.Resolution, 1E-9);
  Assert.IsFalse(mDefault.Grouping.ResolutionChanged);
end;

procedure TOverviewTests.SmallResolutionMergesNeighbours;
var
  mOverview: TArchitectureOverview;
begin
  Assert.AreEqual(2, Integer(Length(AnalyzeWith(TwoCoupledGroups, 1).Subsystems)));
  mOverview := AnalyzeWith(TwoCoupledGroups, 0.2);
  Assert.AreEqual(1, Integer(Length(mOverview.Subsystems)));
  Assert.AreEqual(Double(0.2), mOverview.Grouping.Resolution, 1E-9);
  Assert.IsTrue(mOverview.Grouping.ResolutionChanged);
  // Fein: nie weniger Teilsysteme als mit 1,0.
  Assert.IsTrue(Length(AnalyzeWith(Project, 5).Subsystems) >= Length(Analyze(Project).Subsystems));
end;

procedure TOverviewTests.GroupingIsClampedAndKeyed;
var
  mGrouping: TArchitectureGrouping;
begin
  mGrouping := TArchitectureGrouping.Default;
  mGrouping.Resolution := 0.05;
  Assert.AreEqual(Double(0.2), mGrouping.Clamped.Resolution, 1E-9);
  mGrouping.Resolution := 9;
  Assert.AreEqual(Double(5), mGrouping.Clamped.Resolution, 1E-9);
  mGrouping.Resolution := 0;
  Assert.AreEqual(Double(1), mGrouping.Clamped.Resolution, 1E-9);
  Assert.AreEqual(TArchitectureGrouping.Default.Key, mGrouping.Key);
  mGrouping.Resolution := 1.5;
  Assert.AreNotEqual(TArchitectureGrouping.Default.Key, mGrouping.Key);
  Assert.AreEqual('1,5', TArchitectureGrouping.ResolutionText(1.5));
  Assert.AreEqual('2,0', TArchitectureGrouping.ResolutionText(2));
  Assert.IsTrue(TArchitectureGrouping.ValidResolution(0.2));
  Assert.IsTrue(TArchitectureGrouping.ValidResolution(5));
  Assert.IsFalse(TArchitectureGrouping.ValidResolution(0.19));
  Assert.IsFalse(TArchitectureGrouping.ValidResolution(5.01));
end;

function SubsystemAt(const AOverview: TArchitectureOverview; const AUnit: string): TOverviewSubsystem;
begin
  Result := AOverview.Subsystems[AOverview.Units[AOverview.IndexOf(AUnit)].Subsystem];
end;

procedure TOverviewTests.SplitsOversizedSubsystem;
var
  mOverview: TArchitectureOverview;
  mLsp, mRules, mIndex, mCore: TOverviewSubsystem;
begin
  mOverview := Analyze(BigProject);
  Assert.AreEqual(4, Integer(Length(mOverview.Subsystems)), 'drei Teile und Rest.Core');
  mLsp := SubsystemAt(mOverview, 'Big.Lsp.U05');
  mRules := SubsystemAt(mOverview, 'Big.Rules.U05');
  mIndex := SubsystemAt(mOverview, 'Big.Index.U05');
  mCore := SubsystemAt(mOverview, 'Rest.Core.K05');
  // Benannt gegen das ursprüngliche Teilsystem: unterscheidende Abschnitte statt dreimal „Big“.
  Assert.AreEqual('Lsp', mLsp.Name);
  Assert.AreEqual('Rules', mRules.Name);
  Assert.AreEqual('Index', mIndex.Name);
  Assert.AreEqual('Big', mLsp.Parent);
  Assert.AreEqual('Big', mRules.Parent);
  Assert.AreEqual('Big', mIndex.Parent);
  Assert.AreEqual(12, Integer(Length(mLsp.Units)));
  Assert.AreEqual(12, Integer(Length(mIndex.Units)));
  // Der dichte Block bleibt, obwohl er über 25 % liegt: der zweite Lauf findet keine Teile.
  Assert.AreEqual('Core', mCore.Name);
  Assert.AreEqual('', mCore.Parent);
  Assert.AreEqual(80, Integer(Length(mCore.Units)));
  // Farbfamilie: eine Farbe, verschiedene Töne; der Rest eine eigene Farbe.
  Assert.AreEqual(mLsp.ColorSlot, mRules.ColorSlot);
  Assert.AreEqual(mLsp.ColorSlot, mIndex.ColorSlot);
  Assert.AreNotEqual(mLsp.ColorSlot, mCore.ColorSlot);
  Assert.AreEqual(0, mCore.Shade);
  Assert.AreNotEqual(mLsp.Shade, mRules.Shade);
  Assert.AreNotEqual(mLsp.Shade, mIndex.Shade);
  Assert.AreNotEqual(mRules.Shade, mIndex.Shade);
end;

procedure TOverviewTests.WithoutSplitSettingsLikeBefore;
var
  mGrouping: TArchitectureGrouping;
  mOff, mDefault: TArchitectureOverview;
  mIndex: Integer;
begin
  mGrouping := TArchitectureGrouping.Default;
  mGrouping.MaxShare := 0;
  mGrouping.MinCohesion := 0;
  mOff := AnalyzeGrouped(BigProject, mGrouping);
  Assert.AreEqual(2, Integer(Length(mOff.Subsystems)));
  Assert.AreEqual('Big', mOff.Subsystems[1].Name);
  Assert.AreEqual(36, Integer(Length(mOff.Subsystems[1].Units)));
  Assert.AreEqual('', mOff.Subsystems[1].Parent);
  Assert.AreEqual(1, mOff.Subsystems[1].ColorSlot);
  // Kleine Projekte (#1118) teilen auch mit den Vorgaben nichts nach.
  mOff := AnalyzeGrouped(Project, mGrouping);
  mDefault := Analyze(Project);
  Assert.AreEqual(Integer(Length(mOff.Subsystems)), Integer(Length(mDefault.Subsystems)));
  for mIndex := 0 to High(mOff.Subsystems) do
  begin
    Assert.AreEqual(mOff.Subsystems[mIndex].Name, mDefault.Subsystems[mIndex].Name);
    Assert.AreEqual(UnitNames(mOff, mOff.Subsystems[mIndex].Units), UnitNames(mDefault,
      mDefault.Subsystems[mIndex].Units));
    Assert.AreEqual(mIndex, mDefault.Subsystems[mIndex].ColorSlot);
  end;
end;

procedure TOverviewTests.SplitIsDeterministic;
var
  mFirst, mSecond: TArchitectureOverview;
  mIndex: Integer;
begin
  mFirst := Analyze(BigProject);
  mSecond := Analyze(BigProject);
  Assert.AreEqual(Integer(Length(mFirst.Subsystems)), Integer(Length(mSecond.Subsystems)));
  for mIndex := 0 to High(mFirst.Subsystems) do
  begin
    Assert.AreEqual(mFirst.Subsystems[mIndex].Name, mSecond.Subsystems[mIndex].Name);
    Assert.AreEqual(mFirst.Subsystems[mIndex].Parent, mSecond.Subsystems[mIndex].Parent);
    Assert.AreEqual(UnitNames(mFirst, mFirst.Subsystems[mIndex].Units), UnitNames(mSecond,
      mSecond.Subsystems[mIndex].Units));
    // Keine Teile aus einer einzelnen Unit.
    Assert.IsTrue(Length(mFirst.Subsystems[mIndex].Units) > 1, mFirst.Subsystems[mIndex].Name);
  end;
end;

procedure TOverviewTests.SplitThresholds;
var
  mGrouping: TArchitectureGrouping;
begin
  mGrouping := TArchitectureGrouping.Default;
  Assert.AreEqual(Double(0.25), mGrouping.MaxShare, 1E-9);
  Assert.AreEqual(Double(0.3), mGrouping.MinCohesion, 1E-9);
  // Nach Größe: mehr als 25 % und mindestens 10 Units.
  Assert.IsTrue(mGrouping.NeedsSplit(10, 39, 1));
  Assert.IsFalse(mGrouping.NeedsSplit(10, 40, 1), 'genau 25 %');
  Assert.IsFalse(mGrouping.NeedsSplit(9, 10, 1), 'unter 10 Units');
  // Nach Zusammenhalt: ab 30 Units unter 0,3.
  Assert.IsTrue(mGrouping.NeedsSplit(30, 1000, 0.29));
  Assert.IsFalse(mGrouping.NeedsSplit(30, 1000, 0.3));
  Assert.IsFalse(mGrouping.NeedsSplit(29, 1000, 0.1), 'unter 30 Units');
  mGrouping.MaxShare := 0;
  mGrouping.MinCohesion := 0;
  Assert.IsFalse(mGrouping.NeedsSplit(900, 1000, 0));
  mGrouping.MaxShare := 2;
  mGrouping.MinCohesion := -1;
  Assert.AreEqual(Double(0.9), mGrouping.Clamped.MaxShare, 1E-9);
  Assert.AreEqual(Double(0), mGrouping.Clamped.MinCohesion, 1E-9);
  mGrouping.MaxShare := NaN;
  mGrouping.MinCohesion := NaN;
  Assert.AreEqual(Double(0.25), mGrouping.Clamped.MaxShare, 1E-9);
  Assert.AreEqual(Double(0.3), mGrouping.Clamped.MinCohesion, 1E-9);
  Assert.AreEqual(TArchitectureGrouping.Default.Key, mGrouping.Key);
  mGrouping.MaxShare := 0.5;
  Assert.AreNotEqual(TArchitectureGrouping.Default.Key, mGrouping.Key);
end;

function SortedNames(const AOverview: TArchitectureOverview; const AUnits: TArray<Integer>): string;
var
  mNames: TArray<string>;
  mUnit: Integer;
begin
  mNames := nil;
  for mUnit in AUnits do
    mNames := mNames + [AOverview.Units[mUnit].Name];
  TArray.Sort<string>(mNames);
  Result := string.Join(',', mNames);
end;

function IntsText(const AValues: TArray<Integer>): string;
var
  mValue: Integer;
begin
  Result := '';
  for mValue in AValues do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + IntToStr(mValue);
  end;
end;

/// <summary>Halbiert jede Gruppe ab zwei Units (für SplitStopsAfterTwoLevels).</summary>
function Halve(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
begin
  AParts := nil;
  Result := Length(AMembers) >= 2;
  if not Result then
    Exit;
  SetLength(AParts, 2);
  AParts[0] := Copy(AMembers, 0, Length(AMembers) div 2);
  AParts[1] := Copy(AMembers, Length(AMembers) div 2, MaxInt);
end;

procedure TOverviewTests.SplitStopsAfterTwoLevels;
var
  mGroups, mResult: TArray<TArray<Integer>>;
  mFamilies: TArray<Integer>;
  mGroup: TArray<Integer>;
begin
  SetLength(mGroups, 2);
  mGroups[0] := TArray<Integer>.Create(0, 1, 2, 3, 4, 5, 6, 7);
  mGroups[1] := TArray<Integer>.Create(8, 9);
  // Gruppe 1 ist ausgenommen (wie die Sammelgruppe ohne uses-Beziehung).
  mResult := TArchitectureAnalyzer.SplitGroups(mGroups, 1, 2, Halve, mFamilies);
  Assert.AreEqual(5, Integer(Length(mResult)), 'acht Units in zwei Stufen: vier Teile, dazu Gruppe 1');
  for mGroup in mResult do
    Assert.AreEqual(2, Integer(Length(mGroup)));
  Assert.AreEqual('0,1', IntsText(mResult[0]));
  Assert.AreEqual('8,9', IntsText(mResult[1]));
  Assert.AreEqual(0, mFamilies[0]);
  Assert.AreEqual(1, mFamilies[1]);
  Assert.AreEqual(0, mFamilies[2]);
  Assert.AreEqual(0, mFamilies[4]);
end;

procedure TOverviewTests.SplittingTwoThousandUnitsIsFast;
var
  mUnits: TArray<TUnitIndex>;
  mGroup, mItem, mIndex: Integer;
  mWatch: TStopwatch;
  mOverview: TArchitectureOverview;
  mGrouping: TArchitectureGrouping;
begin
  // Wie TwoThousandUnitsAreFast; MaxShare 1 % teilt jedes Teilsystem ab 10 Units nach (zwei Stufen).
  SetLength(mUnits, 2000);
  for mIndex := 0 to High(mUnits) do
  begin
    mGroup := mIndex div 100;
    mItem := mIndex mod 100;
    mUnits[mIndex] := UsesUnit(Format('P.N%.2d.U%.3d', [mGroup, mItem]),
      [Format('P.N%.2d.U%.3d', [mGroup, (mItem + 1) mod 100]), Format('P.N%.2d.U%.3d', [mGroup, (mItem * 7 + 3) mod 100])],
      [Format('P.N%.2d.U%.3d', [mGroup, (mItem * 13 + 5) mod 100]), Format('P.N%.2d.U%.3d', [(mGroup + 1) mod 20,
      mItem])]);
  end;
  mGrouping := TArchitectureGrouping.Default;
  mGrouping.MaxShare := 0.01;
  mWatch := TStopwatch.StartNew;
  mOverview := AnalyzeGrouped(mUnits, mGrouping);
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 2000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  Assert.IsTrue(Length(mOverview.Subsystems) > Length(Analyze(mUnits).Subsystems),
    IntToStr(Length(mOverview.Subsystems)));
end;

procedure TOverviewTests.FoundationsGroupedLikeBefore;
var
  mOverview: TArchitectureOverview;
  mSubsystem: TOverviewSubsystem;
begin
  // Mit group zieht Logging Ui und Dbg in ein Teilsystem (wie vor #1365).
  mOverview := FoundationsWith(TArchitectureFoundations.Group);
  Assert.AreEqual(SubsystemOf(mOverview, 'App.Ui.U3'), SubsystemOf(mOverview, 'App.Dbg.D3'));
  Assert.AreEqual(SubsystemOf(mOverview, 'App.Ui.U3'), SubsystemOf(mOverview, 'App.Common.Logging'));
  for mSubsystem in mOverview.Subsystems do
    Assert.IsFalse(mSubsystem.Foundation);
end;

procedure TOverviewTests.FoundationsSeparate;
var
  mOverview: TArchitectureOverview;
  mFoundation, mUi: TOverviewSubsystem;
  mLink: TOverviewCrossLink;
  mOutlier: TOverviewOutlier;
begin
  mOverview := FoundationsWith(TArchitectureFoundations.Separate);
  // Fundament zuerst, mit Logging und der Unit, die nur Logging verwendet.
  mFoundation := mOverview.Subsystems[0];
  Assert.IsTrue(mFoundation.Foundation);
  Assert.AreEqual(TArchitectureAnalyzer.FoundationName, mFoundation.Name);
  Assert.AreEqual('App.Common.Logging,App.Tool.Only', SortedNames(mOverview, mFoundation.Units));
  Assert.AreEqual(-1, mFoundation.ColorSlot);
  Assert.AreEqual(Double(0), mFoundation.Cohesion, 1E-9);
  // Ui und Dbg getrennt.
  Assert.AreNotEqual(SubsystemOf(mOverview, 'App.Ui.U3'), SubsystemOf(mOverview, 'App.Dbg.D3'));
  Assert.AreEqual('Ui', SubsystemOf(mOverview, 'App.Ui.U1'));
  Assert.AreEqual('Dbg', SubsystemOf(mOverview, 'App.Dbg.D1'));
  // Zusammenhalt ohne die Kanten ins Fundament: Ui hat nur innere Kanten.
  mUi := SubsystemAt(mOverview, 'App.Ui.U1');
  Assert.AreEqual(4, mUi.InnerEdges);
  Assert.AreEqual(0, mUi.OuterEdges);
  Assert.AreEqual(Double(1), mUi.Cohesion, 1E-9);
  // Keine Querverbindung und kein Ausreißer zum Fundament.
  for mLink in mOverview.CrossLinks do
  begin
    Assert.IsFalse(mOverview.Subsystems[mLink.FromSubsystem].Foundation);
    Assert.IsFalse(mOverview.Subsystems[mLink.ToSubsystem].Foundation);
  end;
  for mOutlier in mOverview.Outliers do
  begin
    Assert.IsFalse(mOverview.Subsystems[mOverview.Units[mOutlier.Unit_].Subsystem].Foundation);
    Assert.IsFalse(mOverview.Subsystems[mOutlier.Suggested].Foundation);
  end;
  // Farben der übrigen ab 0 wie ohne Fundament.
  Assert.AreEqual(0, mOverview.Subsystems[1].ColorSlot);
  // Mit allen Vorgaben (Nachteilung an) ebenso, das Fundament in der Mitte der Karte.
  mOverview := Analyze(FoundationProject);
  Assert.IsTrue(mOverview.Subsystems[0].Foundation);
  Assert.AreNotEqual(SubsystemOf(mOverview, 'App.Ui.U3'), SubsystemOf(mOverview, 'App.Dbg.D3'));
  Assert.AreEqual(Double(0), TArchitectureLayouter.Compute(mOverview).Subsystems[0].X, 1E-9);
  mOverview := FoundationsWith(TArchitectureFoundations.Separate);
  // Zweimal gleich.
  Assert.AreEqual(UnitNames(mOverview, mOverview.Subsystems[1].Units),
    UnitNames(FoundationsWith(TArchitectureFoundations.Separate), FoundationsWith(
    TArchitectureFoundations.Separate).Subsystems[1].Units));
end;

procedure TOverviewTests.FoundationsAttached;
var
  mOverview: TArchitectureOverview;
  mSubsystem: TOverviewSubsystem;
begin
  mOverview := FoundationsWith(TArchitectureFoundations.Attach);
  Assert.AreNotEqual(SubsystemOf(mOverview, 'App.Ui.U3'), SubsystemOf(mOverview, 'App.Dbg.D3'));
  // Logging kommt zu Ui (fünf Abhängige gegen vier), App.Tool.Only folgt ihm.
  Assert.AreEqual(SubsystemOf(mOverview, 'App.Ui.U3'), SubsystemOf(mOverview, 'App.Common.Logging'));
  Assert.AreEqual(SubsystemOf(mOverview, 'App.Common.Logging'), SubsystemOf(mOverview, 'App.Tool.Only'));
  for mSubsystem in mOverview.Subsystems do
    Assert.IsFalse(mSubsystem.Foundation);
end;

procedure TOverviewTests.LocalFoundationStays;
var
  mMode: TArchitectureFoundations;
  mOverview: TArchitectureOverview;
begin
  // App.Index.Types hat die Rolle Fundament, wird aber nur in Index verwendet: bleibt dort.
  for mMode := Low(TArchitectureFoundations) to High(TArchitectureFoundations) do
  begin
    mOverview := FoundationsWith(mMode);
    Assert.IsTrue(mOverview.Units[mOverview.IndexOf('App.Index.Types')].Role = TOverviewUnitRole.Foundation);
    Assert.AreEqual(SubsystemOf(mOverview, 'App.Index.A'), SubsystemOf(mOverview, 'App.Index.Types'));
    Assert.AreEqual('Index', SubsystemOf(mOverview, 'App.Index.Types'));
  end;
end;

procedure TOverviewTests.FoundationsTextAndKey;
var
  mGrouping: TArchitectureGrouping;
  mMode: TArchitectureFoundations;
begin
  Assert.IsTrue(TArchitectureGrouping.Default.Foundations = TArchitectureFoundations.Separate);
  for mMode := Low(TArchitectureFoundations) to High(TArchitectureFoundations) do
  begin
    Assert.IsTrue(TArchitectureGrouping.TryFoundations(TArchitectureGrouping.FoundationsText(mMode), mGrouping.Foundations));
    Assert.IsTrue(mGrouping.Foundations = mMode);
  end;
  Assert.IsFalse(TArchitectureGrouping.TryFoundations('Separate', mMode));
  mGrouping := TArchitectureGrouping.Default;
  mGrouping.Foundations := TArchitectureFoundations.Attach;
  Assert.AreNotEqual(TArchitectureGrouping.Default.Key, mGrouping.Key);
end;

/// <summary>Zwei Gruppen Z.Own und Z.Oth zu je fünf Units (Kette über interface, alle an U1); Z.Own.Mid verwendet drei Units
/// von Own über interface und zwei über implementation, von Oth je zwei.</summary>
function AssignmentProject: TArray<TUnitIndex>;
var
  mGroup: string;
  mItem: Integer;
begin
  Result := nil;
  for mGroup in TArray<string>.Create('Own', 'Oth') do
  begin
    Result := Result + [UsesUnit(Format('Z.%s.U1', [mGroup]), nil, nil),
      UsesUnit(Format('Z.%s.U2', [mGroup]), [Format('Z.%s.U1', [mGroup])], nil)];
    for mItem := 3 to 5 do
      Result := Result + [UsesUnit(Format('Z.%s.U%d', [mGroup, mItem]), [Format('Z.%s.U%d', [mGroup, mItem - 1]),
        Format('Z.%s.U1', [mGroup])], nil)];
  end;
  Result := Result + [UsesUnit('Z.Own.Mid', ['Z.Own.U1', 'Z.Own.U2', 'Z.Own.U3', 'Z.Oth.U1', 'Z.Oth.U2'],
    ['Z.Own.U4', 'Z.Own.U5', 'Z.Oth.U3', 'Z.Oth.U4'])];
end;

function Row(ASubsystem, AInterfaces, AImplementations: Integer): TOverviewAssignmentRow;
begin
  Result := Default(TOverviewAssignmentRow);
  Result.Subsystem := ASubsystem;
  Result.Interfaces := AInterfaces;
  Result.Implementations := AImplementations;
  Result.Sum := AInterfaces * TArchitectureAnalyzer.InterfaceWeight +
    AImplementations * TArchitectureAnalyzer.ImplementationWeight;
  Result.Counts := True;
end;

procedure TOverviewTests.AssignmentListsEdgesPerSubsystem;
var
  mOverview: TArchitectureOverview;
  mAssignment: TOverviewAssignment;
  mOwn, mRival: TOverviewAssignmentRow;
begin
  mOverview := Analyze(AssignmentProject);
  Assert.IsTrue(mOverview.ExplainAssignment);
  Assert.AreEqual(Integer(Length(mOverview.Units)), Integer(Length(mOverview.Assignments)));
  Assert.AreEqual('Own', SubsystemOf(mOverview, 'Z.Own.Mid'));
  mAssignment := mOverview.Assignment(mOverview.IndexOf('Z.Own.Mid'));
  Assert.AreEqual(2, Integer(Length(mAssignment.Rows)));
  Assert.AreEqual(0, mAssignment.Own);
  Assert.AreEqual(1, mAssignment.Rival);
  mOwn := mAssignment.Rows[mAssignment.Own];
  mRival := mAssignment.Rows[mAssignment.Rival];
  Assert.AreEqual('Own', mOverview.Subsystems[mOwn.Subsystem].Name);
  Assert.AreEqual(3, mOwn.Interfaces);
  Assert.AreEqual(2, mOwn.Implementations);
  Assert.AreEqual(8, mOwn.Sum);
  Assert.AreEqual('Oth', mOverview.Subsystems[mRival.Subsystem].Name);
  Assert.AreEqual(2, mRival.Interfaces);
  Assert.AreEqual(2, mRival.Implementations);
  Assert.AreEqual(6, mRival.Sum);
  // 6 ≥ 75 % von 8: knapp, mit drei Kanten mehr hätte Oth die Mehrheit.
  Assert.IsTrue(mAssignment.Close);
  Assert.AreEqual(3, mAssignment.Missing);
  Assert.AreEqual(1, mOverview.CloseCount);
  // Eingehende Kanten zählen mit: Z.Own.U1 wird von U2..U5 und Mid verwendet.
  mAssignment := mOverview.Assignment(mOverview.IndexOf('Z.Own.U1'));
  Assert.AreEqual(1, Integer(Length(mAssignment.Rows)));
  Assert.AreEqual(5, mAssignment.Rows[0].Interfaces);
  Assert.IsFalse(mAssignment.Close);
  Assert.AreEqual(-1, mAssignment.Rival);
  // Außerhalb: keine Daten.
  Assert.AreEqual(-1, mOverview.Assignment(-1).Own);
  Assert.AreEqual(-1, mOverview.Assignment(Length(mOverview.Units)).Own);
end;

procedure TOverviewTests.AssignmentTieSortedByName;
var
  mAssignment: TOverviewAssignment;
begin
  // Gleiche Summe 4: Alpha vor Beta, unabhängig von der Nummer; das eigene Teilsystem 3 hat mehr.
  mAssignment := TArchitectureAnalyzer.AssignmentOf(TArray<TOverviewAssignmentRow>.Create(Row(1, 2, 0), Row(2, 1, 2),
    Row(3, 5, 0), Row(0, 0, 1)), 3, TArray<string>.Create('Gamma', 'Beta', 'Alpha', 'Eigen'));
  Assert.AreEqual(4, Integer(Length(mAssignment.Rows)));
  Assert.AreEqual(3, mAssignment.Rows[0].Subsystem);
  Assert.AreEqual(2, mAssignment.Rows[1].Subsystem);
  Assert.AreEqual(1, mAssignment.Rows[2].Subsystem);
  Assert.AreEqual(0, mAssignment.Rows[3].Subsystem);
  Assert.AreEqual(0, mAssignment.Own);
  Assert.AreEqual(1, mAssignment.Rival);
  // 4 von 10 sind unter 75 %.
  Assert.IsFalse(mAssignment.Close);
  Assert.AreEqual(0, mAssignment.Missing);
end;

procedure TOverviewTests.AssignmentCloseThreshold;
var
  mNames: TArray<string>;
  mAssignment: TOverviewAssignment;
begin
  mNames := TArray<string>.Create('Eigen', 'Fremd');
  // Genau 75 %: 3 von 4 (ganzzahlig, ohne Rundung).
  mAssignment := TArchitectureAnalyzer.AssignmentOf(TArray<TOverviewAssignmentRow>.Create(Row(0, 2, 0),
    Row(1, 1, 1)), 0, mNames);
  Assert.IsTrue(mAssignment.Close);
  Assert.AreEqual(2, mAssignment.Missing);
  // Knapp darunter: 5 von 7 sind 71 %.
  mAssignment := TArchitectureAnalyzer.AssignmentOf(TArray<TOverviewAssignmentRow>.Create(Row(0, 3, 1),
    Row(1, 2, 1)), 0, mNames);
  Assert.IsFalse(mAssignment.Close);
  // Das andere hat schon mehr: knapp, es fehlt nichts.
  mAssignment := TArchitectureAnalyzer.AssignmentOf(TArray<TOverviewAssignmentRow>.Create(Row(0, 1, 0),
    Row(1, 1, 1)), 0, mNames);
  Assert.AreEqual(1, mAssignment.Own);
  Assert.AreEqual(0, mAssignment.Rival);
  Assert.IsTrue(mAssignment.Close);
  Assert.AreEqual(0, mAssignment.Missing);
  // Ohne Kanten ins eigene Teilsystem nie knapp.
  mAssignment := TArchitectureAnalyzer.AssignmentOf(TArray<TOverviewAssignmentRow>.Create(Row(0, 0, 0),
    Row(1, 1, 0)), 0, mNames);
  Assert.IsFalse(mAssignment.Close);
end;

procedure TOverviewTests.AssignmentFoundationDoesNotCount;
var
  mOverview: TArchitectureOverview;
  mAssignment: TOverviewAssignment;
  mRow: TOverviewAssignmentRow;
  mFound: Boolean;
begin
  mOverview := FoundationsWith(TArchitectureFoundations.Separate);
  // App.Ui.U2: interface zu Logging (Fundament, Summe 2), implementation zu U1 und von U3 (Ui, Summe 2).
  mAssignment := mOverview.Assignment(mOverview.IndexOf('App.Ui.U2'));
  mFound := False;
  for mRow in mAssignment.Rows do
    if mOverview.Subsystems[mRow.Subsystem].Foundation then
    begin
      mFound := True;
      Assert.IsFalse(mRow.Counts);
      Assert.AreEqual(1, mRow.Interfaces);
    end
    else
      Assert.IsTrue(mRow.Counts);
  Assert.IsTrue(mFound);
  Assert.AreEqual(-1, mAssignment.Rival);
  Assert.IsFalse(mAssignment.Close);
  // Im Fundament zählen die eigenen Kanten; knapp ist eine Fundament-Unit nie, sie liegt nach der Regel dort.
  mAssignment := mOverview.Assignment(mOverview.IndexOf('App.Common.Logging'));
  Assert.IsTrue(mAssignment.Rows[mAssignment.Own].Counts);
  Assert.IsFalse(mAssignment.Close);
  // Mitgruppiert gibt es kein Fundament: alle Zeilen zählen.
  mOverview := FoundationsWith(TArchitectureFoundations.Group);
  for mAssignment in mOverview.Assignments do
    for mRow in mAssignment.Rows do
      Assert.IsTrue(mRow.Counts);
end;

procedure TOverviewTests.OutliersMatchAssignments;
var
  mOverview: TArchitectureOverview;
  mOutlier: TOverviewOutlier;
  mAssignment: TOverviewAssignment;
  mRow: TOverviewAssignmentRow;
  mInside, mToward: Integer;
begin
  // App.Ui.Export verwendet nur Data-Units (Ausreißer wie in MisplacedUnitIsOutlier): Die Zahlen des Ausreißers
  // stammen aus der Zuordnung.
  mOverview := Analyze(Project + [UsesUnit('App.Ui.Export', ['App.Data.Db', 'App.Data.Query', 'App.Data.Model'],
    nil)]);
  Assert.IsTrue(Length(mOverview.Outliers) > 0);
  for mOutlier in mOverview.Outliers do
  begin
    mAssignment := mOverview.Assignment(mOutlier.Unit_);
    mInside := 0;
    mToward := 0;
    for mRow in mAssignment.Rows do
    begin
      if mRow.Subsystem = mOverview.Units[mOutlier.Unit_].Subsystem then
        mInside := mRow.Edges;
      if mRow.Subsystem = mOutlier.Suggested then
        mToward := mRow.Edges;
    end;
    Assert.AreEqual(mInside, mOutlier.Inside);
    Assert.AreEqual(mToward, mOutlier.Toward);
  end;
end;

procedure TOverviewTests.AssignmentsAreCheap;
var
  mUnits: TArray<TUnitIndex>;
  mGroup, mItem, mIndex, mRound: Integer;
  mWatch: TStopwatch;
  mOverview: TArchitectureOverview;
  mTotal, mAssign: Int64;
begin
  // Derselbe Graph wie TwoThousandUnitsAreFast; die Zuordnung darf höchstens 5 % der Übersicht kosten.
  SetLength(mUnits, 2000);
  for mIndex := 0 to High(mUnits) do
  begin
    mGroup := mIndex div 100;
    mItem := mIndex mod 100;
    mUnits[mIndex] := UsesUnit(Format('P.N%.2d.U%.3d', [mGroup, mItem]), [Format('P.N%.2d.U%.3d', [mGroup,
      (mItem + 1) mod 100]), Format('P.N%.2d.U%.3d', [mGroup, (mItem * 7 + 3) mod 100])],
      [Format('P.N%.2d.U%.3d', [mGroup, (mItem * 13 + 5) mod 100]), Format('P.N%.2d.U%.3d', [(mGroup + 1) mod 20,
      mItem])]);
  end;
  mTotal := MaxInt;
  mAssign := MaxInt;
  for mRound := 1 to 3 do
  begin
    mWatch := TStopwatch.StartNew;
    mOverview := Analyze(mUnits);
    mTotal := Min(mTotal, mWatch.ElapsedTicks);
    mWatch := TStopwatch.StartNew;
    TArchitectureAnalyzer.Assignments(mOverview);
    mAssign := Min(mAssign, mWatch.ElapsedTicks);
  end;
  Assert.AreEqual(2000, Integer(Length(mOverview.Assignments)));
  Assert.IsTrue(mAssign * 100 < mTotal * 5, Format('Zuordnung %d, Übersicht %d Ticks', [mAssign, mTotal]));
end;

initialization
  TDUnitX.RegisterTestFixture(TOverviewTests);

end.
