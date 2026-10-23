unit Atlas.Common.Architecture.Overview.Tests;

// Tests der Architekturübersicht (#1118): Teilsysteme mit Namen,
// Zusammenhalt, Ausreißer, zentrale Units mit Rolle, Zyklen,
// Querverbindungen mit Fundstelle, Steckbrief, Determinismus, Laufzeit.

interface

uses
  DUnitX.TestFramework;

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
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Overview,
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

initialization
  TDUnitX.RegisterTestFixture(TOverviewTests);

end.
