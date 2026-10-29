unit Atlas.Common.Architecture.Comparison.Tests;

// Tests des Architekturvergleichs (#1121): je Abschnitt ein Testgraph,
// Zuordnung der Teilsysteme ohne Scheinwechsel, Text mit Ergebnis für
// --fail-on, JSON und die Namen der Abweichungsarten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArchitectureComparisonTests = class
  public
    [Test]
    procedure SameStateHasNoDifference;
    [Test]
    procedure FindsNewAndRemovedCycle;
    [Test]
    procedure FindsNewAndRemovedCrossLinks;
    [Test]
    procedure FindsEdgesBetweenSubsystems;
    [Test]
    procedure RenumberedSubsystemsAreNoChange;
    [Test]
    procedure RenamedSubsystemsAreNoChange;
    [Test]
    procedure FindsSubsystemChange;
    [Test]
    procedure FindsCentralGrowth;
    [Test]
    procedure FindsNewAndRemovedUnits;
    [Test]
    procedure TextNamesSectionsAndResult;
    [Test]
    procedure MarkdownHasComparisonSection;
    [Test]
    procedure JsonIsValid;
    [Test]
    procedure ParsesKinds;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Common.Architecture.Snapshot.Tests;

function SnapshotOf(const AUnits: TArray<TUnitIndex>): TArchitectureSnapshot;
begin
  Result := TArchitectureSnapshots.FromOverview(ArchitectureOverviewOf(AUnits));
end;

/// <summary>Units der Beispielgruppe mit ausgetauschter Unit AName.</summary>
function Replaced(const AName: string; const AInterface, AImplementation: TArray<string>): TArray<TUnitIndex>;
var
  Index: Integer;
begin
  Result := ArchitectureSampleUnits;
  for Index := 0 to High(Result) do
    if Result[Index].UnitName = AName then
      Result[Index] := UsesUnit(AName, AInterface, AImplementation);
end;

procedure AddUnit(var ASnapshot: TArchitectureSnapshot; const AName, ASubsystem: string; ATotal: Integer);
var
  Item: TSnapshotUnit;
  Index: Integer;
  Found: Boolean;
begin
  Item := Default(TSnapshotUnit);
  Item.Name := AName;
  Item.Subsystem := ASubsystem;
  Item.Total := ATotal;
  ASnapshot.Units := ASnapshot.Units + [Item];
  Found := False;
  for Index := 0 to High(ASnapshot.Subsystems) do
    if ASnapshot.Subsystems[Index].Name = ASubsystem then
    begin
      ASnapshot.Subsystems[Index].Units := ASnapshot.Subsystems[Index].Units + [AName];
      Found := True;
    end;
  if not Found then
  begin
    SetLength(ASnapshot.Subsystems, Length(ASnapshot.Subsystems) + 1);
    ASnapshot.Subsystems[High(ASnapshot.Subsystems)].Name := ASubsystem;
    ASnapshot.Subsystems[High(ASnapshot.Subsystems)].Units := [AName];
  end;
end;

procedure AddEdge(var ASnapshot: TArchitectureSnapshot; const ASource, ATarget: string);
var
  Edge: TSnapshotEdge;
begin
  Edge.Source := ASource;
  Edge.Target := ATarget;
  Edge.Interface_ := True;
  ASnapshot.Edges := ASnapshot.Edges + [Edge];
end;

procedure AddCrossLink(var ASnapshot: TArchitectureSnapshot; const ASource, ATarget, AFrom, ATo: string);
var
  Link: TSnapshotCrossLink;
begin
  Link := Default(TSnapshotCrossLink);
  Link.Edge.Source := ASource;
  Link.Edge.Target := ATarget;
  Link.FromSubsystem := AFrom;
  Link.ToSubsystem := ATo;
  Link.Reason := 'rare';
  ASnapshot.CrossLinks := ASnapshot.CrossLinks + [Link];
end;

/// <summary>Zwei Teilsysteme: Kern (k1..k4) und Ui (u1..u3).</summary>
function TwoGroups(const AKern, AUi: string): TArchitectureSnapshot;
begin
  Result := Default(TArchitectureSnapshot);
  Result.Title := 'Alt';
  AddUnit(Result, 'k1', AKern, 0);
  AddUnit(Result, 'k2', AKern, 0);
  AddUnit(Result, 'k3', AKern, 0);
  AddUnit(Result, 'k4', AKern, 0);
  AddUnit(Result, 'u1', AUi, 0);
  AddUnit(Result, 'u2', AUi, 0);
  AddUnit(Result, 'u3', AUi, 0);
end;

{ TArchitectureComparisonTests }

procedure TArchitectureComparisonTests.SameStateHasNoDifference;
var
  Comparison: TArchitectureComparison;
begin
  Comparison := TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits), SnapshotOf(ArchitectureSampleUnits));
  Assert.IsTrue(Comparison.IsEmpty);
  Assert.IsTrue(Comparison.Kinds = []);
  Assert.AreEqual(0, Integer(Length(Comparison.AddedEdges)));
  Assert.AreEqual('Beispiel', Comparison.BaselineTitle);
  Assert.AreEqual(12, Comparison.BaselineUnits);
end;

procedure TArchitectureComparisonTests.FindsNewAndRemovedCycle;
var
  Older, Newer: TArchitectureSnapshot;
  Comparison: TArchitectureComparison;
begin
  Older := SnapshotOf(ArchitectureSampleUnits);
  // App.Core.Base braucht nun App.Core.Log: Zyklus Base → Log → Base.
  Newer := SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log']));
  Comparison := TArchitectureComparer.Compare(Older, Newer);
  Assert.AreEqual(1, Integer(Length(Comparison.NewCycles)));
  Assert.Contains(TArchitectureComparer.CyclePath(Comparison.NewCycles[0]), 'App.Core.Base');
  Assert.Contains(TArchitectureComparer.CyclePath(Comparison.NewCycles[0]), 'App.Core.Log');
  Assert.AreEqual(0, Integer(Length(Comparison.RemovedCycles)));
  Assert.IsTrue(TArchitectureFailKind.NewCycle in Comparison.Kinds);
  // Umgekehrt ist der Zyklus entfernt, und es gibt keinen neuen.
  Comparison := TArchitectureComparer.Compare(Newer, Older);
  Assert.AreEqual(0, Integer(Length(Comparison.NewCycles)));
  Assert.AreEqual(1, Integer(Length(Comparison.RemovedCycles)));
  Assert.IsFalse(TArchitectureFailKind.NewCycle in Comparison.Kinds);
end;

procedure TArchitectureComparisonTests.FindsNewAndRemovedCrossLinks;
var
  Older, Newer: TArchitectureSnapshot;
  Comparison: TArchitectureComparison;
begin
  Older := TwoGroups('Kern', 'Ui');
  AddCrossLink(Older, 'u1', 'k1', 'Ui', 'Kern');
  Newer := TwoGroups('Kern', 'Ui');
  AddCrossLink(Newer, 'u2', 'k2', 'Ui', 'Kern');
  // Gleiche Kante, anderer Grund: bleibt dieselbe Querverbindung.
  AddCrossLink(Older, 'k4', 'u3', 'Kern', 'Ui');
  AddCrossLink(Newer, 'K4', 'U3', 'Kern', 'Ui');
  Newer.CrossLinks[High(Newer.CrossLinks)].Reason := 'againstDirection';
  Comparison := TArchitectureComparer.Compare(Older, Newer);
  Assert.AreEqual(1, Integer(Length(Comparison.NewCrossLinks)));
  Assert.AreEqual('u2', Comparison.NewCrossLinks[0].Source);
  Assert.AreEqual('Ui', Comparison.NewCrossLinks[0].FromSubsystem);
  Assert.AreEqual(1, Integer(Length(Comparison.RemovedCrossLinks)));
  Assert.AreEqual('u1', Comparison.RemovedCrossLinks[0].Source);
  Assert.IsTrue(Comparison.Kinds = [TArchitectureFailKind.NewCrossLink]);
end;

procedure TArchitectureComparisonTests.FindsEdgesBetweenSubsystems;
var
  Older, Newer: TArchitectureSnapshot;
  Comparison: TArchitectureComparison;
begin
  Older := TwoGroups('Kern', 'Ui');
  AddEdge(Older, 'u1', 'k1');
  AddEdge(Older, 'k2', 'k1');
  Newer := TwoGroups('Kern', 'Ui');
  // Neu: u2 → k3 über die Grenze, k3 → k1 innen; entfernt: u1 → k1 über die Grenze, k2 → k1 innen.
  AddEdge(Newer, 'u2', 'k3');
  AddEdge(Newer, 'k3', 'k1');
  Comparison := TArchitectureComparer.Compare(Older, Newer);
  Assert.AreEqual(1, Integer(Length(Comparison.NewEdges)));
  Assert.AreEqual('u2', Comparison.NewEdges[0].Source);
  Assert.AreEqual('Ui', Comparison.NewEdges[0].FromSubsystem);
  Assert.AreEqual('Kern', Comparison.NewEdges[0].ToSubsystem);
  Assert.AreEqual(1, Integer(Length(Comparison.RemovedEdges)));
  Assert.AreEqual('u1', Comparison.RemovedEdges[0].Source);
  // Für die Karte alle Änderungen.
  Assert.AreEqual(2, Integer(Length(Comparison.AddedEdges)));
  Assert.AreEqual(2, Integer(Length(Comparison.DroppedEdges)));
  // Kanten zählen nicht für --fail-on.
  Assert.IsTrue(Comparison.Kinds = []);
end;

procedure TArchitectureComparisonTests.RenumberedSubsystemsAreNoChange;
var
  Older, Newer: TArchitectureSnapshot;
  Comparison: TArchitectureComparison;
begin
  // Dieselben Gruppen, aber die Analyse benennt sie anders herum (Nummerierung "Index", "Index 2").
  Older := TwoGroups('Index', 'Index 2');
  Newer := TwoGroups('Index 2', 'Index');
  Comparison := TArchitectureComparer.Compare(Older, Newer);
  Assert.AreEqual(0, Integer(Length(Comparison.Moves)));
  Assert.AreEqual('Index', Comparison.MatchOf('Index 2'));
  Assert.AreEqual('Index 2', Comparison.MatchOf('Index'));
  // Auch über die Analyse: Reihenfolge der Units geändert, Teilsysteme gleich.
  Comparison := TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(Copy(ArchitectureSampleUnits, 6, 6) + Copy(ArchitectureSampleUnits, 0, 6)));
  Assert.AreEqual(0, Integer(Length(Comparison.Moves)));
end;

procedure TArchitectureComparisonTests.RenamedSubsystemsAreNoChange;
var
  Comparison: TArchitectureComparison;
begin
  Comparison := TArchitectureComparer.Compare(TwoGroups('Kern', 'Ui'), TwoGroups('Basis', 'Oberfläche'));
  Assert.AreEqual(0, Integer(Length(Comparison.Moves)));
  Assert.AreEqual('Kern', Comparison.MatchOf('Basis'));
end;

procedure TArchitectureComparisonTests.FindsSubsystemChange;
var
  Older, Newer: TArchitectureSnapshot;
  Comparison: TArchitectureComparison;
begin
  Older := TwoGroups('Kern', 'Ui');
  Newer := Default(TArchitectureSnapshot);
  AddUnit(Newer, 'k1', 'Kern', 0);
  AddUnit(Newer, 'k2', 'Kern', 0);
  AddUnit(Newer, 'k3', 'Kern', 0);
  AddUnit(Newer, 'k4', 'Ui', 0);
  AddUnit(Newer, 'u1', 'Ui', 0);
  AddUnit(Newer, 'u2', 'Ui', 0);
  AddUnit(Newer, 'u3', 'Ui', 0);
  Comparison := TArchitectureComparer.Compare(Older, Newer);
  Assert.AreEqual(1, Integer(Length(Comparison.Moves)));
  Assert.AreEqual('k4', Comparison.Moves[0].Unit_);
  Assert.AreEqual('Kern', Comparison.Moves[0].FromSubsystem);
  Assert.AreEqual('Ui', Comparison.Moves[0].ToSubsystem);
  Assert.IsTrue(Comparison.Kinds = [TArchitectureFailKind.SubsystemChange]);
end;

procedure TArchitectureComparisonTests.FindsCentralGrowth;
var
  Older, Newer: TArchitectureSnapshot;
  Comparison: TArchitectureComparison;
begin
  Older := Default(TArchitectureSnapshot);
  AddUnit(Older, 'Wächst', 'Kern', 20);
  AddUnit(Older, 'Knapp', 'Kern', 20);
  AddUnit(Older, 'Prozent', 'Kern', 100);
  AddUnit(Older, 'Rand', 'Kern', 1);
  AddUnit(Older, 'Wird', 'Kern', 40);
  Older.Central := TArray<string>.Create('Prozent', 'Wird', 'Wächst', 'Knapp');
  Newer := Default(TArchitectureSnapshot);
  // +6 bei 20 (30 %): ja; +4 bei 20: unter 5; +6 bei 100: nur 6 %; Rand +9, aber nicht zentral.
  AddUnit(Newer, 'Wächst', 'Kern', 26);
  AddUnit(Newer, 'Knapp', 'Kern', 24);
  AddUnit(Newer, 'Prozent', 'Kern', 106);
  AddUnit(Newer, 'Rand', 'Kern', 10);
  // Erst im neuen Stand zentral: zählt auch. +10 bei 40 (25 %).
  AddUnit(Newer, 'Wird', 'Kern', 50);
  Newer.Central := TArray<string>.Create('Prozent', 'Wird');
  Comparison := TArchitectureComparer.Compare(Older, Newer);
  Assert.AreEqual(2, Integer(Length(Comparison.Growth)));
  Assert.AreEqual('Wird', Comparison.Growth[0].Unit_);
  Assert.AreEqual(40, Comparison.Growth[0].Before);
  Assert.AreEqual(50, Comparison.Growth[0].After);
  Assert.AreEqual('Wächst', Comparison.Growth[1].Unit_);
  Assert.IsTrue(Comparison.Kinds = [TArchitectureFailKind.CentralGrowth]);
end;

procedure TArchitectureComparisonTests.FindsNewAndRemovedUnits;
var
  Older, Newer: TArchitectureSnapshot;
  Comparison: TArchitectureComparison;
begin
  Older := TwoGroups('Kern', 'Ui');
  Newer := TwoGroups('Kern', 'Ui');
  AddUnit(Newer, 'k5', 'Kern', 0);
  Delete(Newer.Units, 4, 1);
  Comparison := TArchitectureComparer.Compare(Older, Newer);
  Assert.AreEqual('k5', string.Join(',', Comparison.NewUnits));
  Assert.AreEqual('u1', string.Join(',', Comparison.RemovedUnits));
  // Neue Units sind kein Teilsystemwechsel.
  Assert.AreEqual(0, Integer(Length(Comparison.Moves)));
end;

procedure TArchitectureComparisonTests.TextNamesSectionsAndResult;
var
  Comparison: TArchitectureComparison;
  Text: string;
begin
  Comparison := TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log'])));
  Text := TArchitectureComparer.Text(Comparison, [TArchitectureFailKind.NewCycle], 0);
  Assert.StartsWith('Architekturvergleich mit dem Stand „Beispiel“ (12 Units, 18 uses-Kanten)', Text);
  Assert.Contains(Text, 'Neue Zyklen: 1');
  Assert.Contains(Text, 'Entfernte Zyklen: 0');
  Assert.Contains(Text, 'Neue Querverbindungen: ');
  Assert.Contains(Text, 'Teilsystemwechsel: ');
  Assert.Contains(Text, 'Gewachsene zentrale Units: ');
  Assert.Contains(Text, 'Neue Units: 0');
  Assert.Contains(Text, 'Ergebnis: Abweichung newCycle (fail-on newCycle)');
  Text := TArchitectureComparer.Text(Comparison, [TArchitectureFailKind.CentralGrowth], 0);
  Assert.Contains(Text, 'Ergebnis: keine Abweichung der Arten centralGrowth');
  // Gekürzt.
  Comparison.NewUnits := TArray<string>.Create('a', 'b', 'c');
  Text := TArchitectureComparer.Text(Comparison, [], 2);
  Assert.Contains(Text, '  … 1 weitere');
  Assert.Contains(Text, 'keine Abweichung gilt als Fehler');
end;

procedure TArchitectureComparisonTests.MarkdownHasComparisonSection;
var
  Text: string;
begin
  Text := TArchitectureComparer.Markdown(TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log']))));
  Assert.StartsWith('## Vergleich', Text);
  Assert.Contains(Text, '### Neue Zyklen (1)');
  Assert.Contains(Text, '### Entfernte Units (0)');
  Text := TArchitectureComparer.Markdown(TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(ArchitectureSampleUnits)));
  Assert.Contains(Text, 'Keine Abweichung.');
end;

procedure TArchitectureComparisonTests.JsonIsValid;
var
  Root: TJSONValue;
  Data: TJSONObject;
begin
  Root := TJSONObject.ParseJSONValue(TArchitectureComparer.Json(TArchitectureComparer.Compare(
    SnapshotOf(ArchitectureSampleUnits), SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log']))),
    TArchitectureComparer.DefaultFailOn));
  try
    Assert.IsTrue(Root is TJSONObject);
    Data := TJSONObject(Root);
    Assert.AreEqual(1, Data.GetValue<TJSONArray>('newCycles').Count);
    Assert.AreEqual('newCycle', Data.GetValue<TJSONArray>('failed').Items[0].Value);
    Assert.AreEqual('newCycle', Data.GetValue<TJSONArray>('failOn').Items[0].Value);
    Assert.AreEqual(1, Data.GetValue<TJSONArray>('addedEdges').Count);
    Assert.AreEqual('App.Core.Base', (Data.GetValue<TJSONArray>('addedEdges').Items[0] as TJSONArray).Items[0].Value);
    Assert.AreEqual(12, (Data.GetValue('baseline') as TJSONObject).GetValue<Integer>('units'));
  finally
    Root.Free;
  end;
end;

procedure TArchitectureComparisonTests.ParsesKinds;
var
  Kinds: TArchitectureFailKinds;
  Error: string;
begin
  Assert.IsTrue(TArchitectureComparer.ParseKindList('newCycle,NEWCROSSLINK subsystemChange', Kinds, Error));
  Assert.IsTrue(Kinds = [TArchitectureFailKind.NewCycle, TArchitectureFailKind.NewCrossLink,
    TArchitectureFailKind.SubsystemChange]);
  Assert.IsFalse(TArchitectureComparer.ParseKindList('newCycle,error', Kinds, Error));
  Assert.Contains(Error, '"error"');
  Assert.IsTrue(TArchitectureComparer.ParseKindList('', Kinds, Error));
  Assert.IsTrue(Kinds = []);
  Assert.AreEqual('newCycle,centralGrowth', string.Join(',', TArchitectureComparer.KindNames(
    [TArchitectureFailKind.CentralGrowth, TArchitectureFailKind.NewCycle])));
  Assert.IsTrue(TArchitectureComparer.DefaultFailOn = [TArchitectureFailKind.NewCycle]);
end;

initialization
  TDUnitX.RegisterTestFixture(TArchitectureComparisonTests);

end.
