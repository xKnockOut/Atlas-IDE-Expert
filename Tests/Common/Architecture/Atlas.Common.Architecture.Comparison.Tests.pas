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
    /// <summary>Verschiedene Feinheit γ (#1366): Hinweis in Text, Markdown und JSON.</summary>
    [Test]
    procedure NotesDifferentResolution;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Grouping,
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
  mIndex: Integer;
begin
  Result := ArchitectureSampleUnits;
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex].UnitName = AName then
    begin
      Result[mIndex] := UsesUnit(AName, AInterface, AImplementation);
    end;
  end;
end;

procedure AddUnit(var ASnapshot: TArchitectureSnapshot; const AName, ASubsystem: string; ATotal: Integer);
var
  mItem: TSnapshotUnit;
  mIndex: Integer;
  mFound: Boolean;
begin
  mItem := Default(TSnapshotUnit);
  mItem.Name := AName;
  mItem.Subsystem := ASubsystem;
  mItem.Total := ATotal;
  ASnapshot.Units := ASnapshot.Units + [mItem];
  mFound := False;
  for mIndex := 0 to High(ASnapshot.Subsystems) do
  begin
    if ASnapshot.Subsystems[mIndex].Name = ASubsystem then
    begin
      ASnapshot.Subsystems[mIndex].Units := ASnapshot.Subsystems[mIndex].Units + [AName];
      mFound := True;
    end;
  end;
  if not mFound then
  begin
    SetLength(ASnapshot.Subsystems, Length(ASnapshot.Subsystems) + 1);
    ASnapshot.Subsystems[High(ASnapshot.Subsystems)].Name := ASubsystem;
    ASnapshot.Subsystems[High(ASnapshot.Subsystems)].Units := [AName];
  end;
end;

procedure AddEdge(var ASnapshot: TArchitectureSnapshot; const ASource, ATarget: string);
var
  mEdge: TSnapshotEdge;
begin
  mEdge.Source := ASource;
  mEdge.Target := ATarget;
  mEdge.Interface_ := True;
  ASnapshot.Edges := ASnapshot.Edges + [mEdge];
end;

procedure AddCrossLink(var ASnapshot: TArchitectureSnapshot; const ASource, ATarget, AFrom, ATo: string);
var
  mLink: TSnapshotCrossLink;
begin
  mLink := Default(TSnapshotCrossLink);
  mLink.Edge.Source := ASource;
  mLink.Edge.Target := ATarget;
  mLink.FromSubsystem := AFrom;
  mLink.ToSubsystem := ATo;
  mLink.Reason := 'rare';
  ASnapshot.CrossLinks := ASnapshot.CrossLinks + [mLink];
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
  mComparison: TArchitectureComparison;
begin
  mComparison := TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(ArchitectureSampleUnits));
  Assert.IsTrue(mComparison.IsEmpty);
  Assert.AreEqual<TArchitectureFailKinds>([], mComparison.Kinds);
  Assert.AreEqual(0, Integer(Length(mComparison.AddedEdges)));
  Assert.AreEqual('Beispiel', mComparison.BaselineTitle);
  Assert.AreEqual(12, mComparison.BaselineUnits);
end;

procedure TArchitectureComparisonTests.FindsNewAndRemovedCycle;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  mOlder := SnapshotOf(ArchitectureSampleUnits);
  // App.Core.Base braucht nun App.Core.Log: Zyklus Base → Log → Base.
  mNewer := SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log']));
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.AreEqual(1, Integer(Length(mComparison.NewCycles)));
  Assert.Contains(TArchitectureComparer.CyclePath(mComparison.NewCycles[0]), 'App.Core.Base');
  Assert.Contains(TArchitectureComparer.CyclePath(mComparison.NewCycles[0]), 'App.Core.Log');
  Assert.AreEqual(0, Integer(Length(mComparison.RemovedCycles)));
  Assert.IsTrue(TArchitectureFailKind.NewCycle in mComparison.Kinds);
  // Umgekehrt ist der Zyklus entfernt, und es gibt keinen neuen.
  mComparison := TArchitectureComparer.Compare(mNewer, mOlder);
  Assert.AreEqual(0, Integer(Length(mComparison.NewCycles)));
  Assert.AreEqual(1, Integer(Length(mComparison.RemovedCycles)));
  Assert.IsFalse(TArchitectureFailKind.NewCycle in mComparison.Kinds);
end;

procedure TArchitectureComparisonTests.FindsNewAndRemovedCrossLinks;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  mOlder := TwoGroups('Kern', 'Ui');
  AddCrossLink(mOlder, 'u1', 'k1', 'Ui', 'Kern');
  mNewer := TwoGroups('Kern', 'Ui');
  AddCrossLink(mNewer, 'u2', 'k2', 'Ui', 'Kern');
  // Gleiche Kante, anderer Grund: bleibt dieselbe Querverbindung.
  AddCrossLink(mOlder, 'k4', 'u3', 'Kern', 'Ui');
  AddCrossLink(mNewer, 'K4', 'U3', 'Kern', 'Ui');
  mNewer.CrossLinks[High(mNewer.CrossLinks)].Reason := 'againstDirection';
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.AreEqual(1, Integer(Length(mComparison.NewCrossLinks)));
  Assert.AreEqual('u2', mComparison.NewCrossLinks[0].Source);
  Assert.AreEqual('Ui', mComparison.NewCrossLinks[0].FromSubsystem);
  Assert.AreEqual(1, Integer(Length(mComparison.RemovedCrossLinks)));
  Assert.AreEqual('u1', mComparison.RemovedCrossLinks[0].Source);
  Assert.AreEqual<TArchitectureFailKinds>([TArchitectureFailKind.NewCrossLink], mComparison.Kinds);
end;

procedure TArchitectureComparisonTests.FindsEdgesBetweenSubsystems;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  mOlder := TwoGroups('Kern', 'Ui');
  AddEdge(mOlder, 'u1', 'k1');
  AddEdge(mOlder, 'k2', 'k1');
  mNewer := TwoGroups('Kern', 'Ui');
  // Neu: u2 → k3 über die Grenze, k3 → k1 innen; entfernt: u1 → k1 über die Grenze, k2 → k1 innen.
  AddEdge(mNewer, 'u2', 'k3');
  AddEdge(mNewer, 'k3', 'k1');
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.AreEqual(1, Integer(Length(mComparison.NewEdges)));
  Assert.AreEqual('u2', mComparison.NewEdges[0].Source);
  Assert.AreEqual('Ui', mComparison.NewEdges[0].FromSubsystem);
  Assert.AreEqual('Kern', mComparison.NewEdges[0].ToSubsystem);
  Assert.AreEqual(1, Integer(Length(mComparison.RemovedEdges)));
  Assert.AreEqual('u1', mComparison.RemovedEdges[0].Source);
  // Für die Karte alle Änderungen.
  Assert.AreEqual(2, Integer(Length(mComparison.AddedEdges)));
  Assert.AreEqual(2, Integer(Length(mComparison.DroppedEdges)));
  // Kanten zählen nicht für --fail-on.
  Assert.AreEqual<TArchitectureFailKinds>([], mComparison.Kinds);
end;

procedure TArchitectureComparisonTests.RenumberedSubsystemsAreNoChange;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  // Dieselben Gruppen, aber die Analyse benennt sie anders herum (Nummerierung "Index", "Index 2").
  mOlder := TwoGroups('Index', 'Index 2');
  mNewer := TwoGroups('Index 2', 'Index');
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.AreEqual(0, Integer(Length(mComparison.Moves)));
  Assert.AreEqual('Index', mComparison.MatchOf('Index 2'));
  Assert.AreEqual('Index 2', mComparison.MatchOf('Index'));
  // Auch über die Analyse: Reihenfolge der Units geändert, Teilsysteme gleich.
  mComparison := TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(Copy(ArchitectureSampleUnits, 6, 6) + Copy(ArchitectureSampleUnits, 0, 6)));
  Assert.AreEqual(0, Integer(Length(mComparison.Moves)));
end;

procedure TArchitectureComparisonTests.RenamedSubsystemsAreNoChange;
var
  mComparison: TArchitectureComparison;
begin
  mComparison := TArchitectureComparer.Compare(TwoGroups('Kern', 'Ui'), TwoGroups('Basis', 'Oberfläche'));
  Assert.AreEqual(0, Integer(Length(mComparison.Moves)));
  Assert.AreEqual('Kern', mComparison.MatchOf('Basis'));
end;

procedure TArchitectureComparisonTests.FindsSubsystemChange;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  mOlder := TwoGroups('Kern', 'Ui');
  mNewer := Default(TArchitectureSnapshot);
  AddUnit(mNewer, 'k1', 'Kern', 0);
  AddUnit(mNewer, 'k2', 'Kern', 0);
  AddUnit(mNewer, 'k3', 'Kern', 0);
  AddUnit(mNewer, 'k4', 'Ui', 0);
  AddUnit(mNewer, 'u1', 'Ui', 0);
  AddUnit(mNewer, 'u2', 'Ui', 0);
  AddUnit(mNewer, 'u3', 'Ui', 0);
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.AreEqual(1, Integer(Length(mComparison.Moves)));
  Assert.AreEqual('k4', mComparison.Moves[0].Unit_);
  Assert.AreEqual('Kern', mComparison.Moves[0].FromSubsystem);
  Assert.AreEqual('Ui', mComparison.Moves[0].ToSubsystem);
  Assert.AreEqual<TArchitectureFailKinds>([TArchitectureFailKind.SubsystemChange], mComparison.Kinds);
end;

procedure TArchitectureComparisonTests.FindsCentralGrowth;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  mOlder := Default(TArchitectureSnapshot);
  AddUnit(mOlder, 'Wächst', 'Kern', 20);
  AddUnit(mOlder, 'Knapp', 'Kern', 20);
  AddUnit(mOlder, 'Prozent', 'Kern', 100);
  AddUnit(mOlder, 'Rand', 'Kern', 1);
  AddUnit(mOlder, 'Wird', 'Kern', 40);
  mOlder.Central := TArray<string>.Create('Prozent', 'Wird', 'Wächst', 'Knapp');
  mNewer := Default(TArchitectureSnapshot);
  // +6 bei 20 (30 %): ja; +4 bei 20: unter 5; +6 bei 100: nur 6 %; Rand +9, aber nicht zentral.
  AddUnit(mNewer, 'Wächst', 'Kern', 26);
  AddUnit(mNewer, 'Knapp', 'Kern', 24);
  AddUnit(mNewer, 'Prozent', 'Kern', 106);
  AddUnit(mNewer, 'Rand', 'Kern', 10);
  // Erst im neuen Stand zentral: zählt auch. +10 bei 40 (25 %).
  AddUnit(mNewer, 'Wird', 'Kern', 50);
  mNewer.Central := TArray<string>.Create('Prozent', 'Wird');
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.AreEqual(2, Integer(Length(mComparison.Growth)));
  Assert.AreEqual('Wird', mComparison.Growth[0].Unit_);
  Assert.AreEqual(40, mComparison.Growth[0].Before);
  Assert.AreEqual(50, mComparison.Growth[0].After);
  Assert.AreEqual('Wächst', mComparison.Growth[1].Unit_);
  Assert.AreEqual<TArchitectureFailKinds>([TArchitectureFailKind.CentralGrowth], mComparison.Kinds);
end;

procedure TArchitectureComparisonTests.FindsNewAndRemovedUnits;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  mOlder := TwoGroups('Kern', 'Ui');
  mNewer := TwoGroups('Kern', 'Ui');
  AddUnit(mNewer, 'k5', 'Kern', 0);
  Delete(mNewer.Units, 4, 1);
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.AreEqual('k5', string.Join(',', mComparison.NewUnits));
  Assert.AreEqual('u1', string.Join(',', mComparison.RemovedUnits));
  // Neue Units sind kein Teilsystemwechsel.
  Assert.AreEqual(0, Integer(Length(mComparison.Moves)));
end;

procedure TArchitectureComparisonTests.TextNamesSectionsAndResult;
var
  mComparison: TArchitectureComparison;
  mText: string;
begin
  mComparison := TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log'])));
  mText := TArchitectureComparer.Text(mComparison, [TArchitectureFailKind.NewCycle], 0);
  Assert.StartsWith('Architekturvergleich mit dem Stand „Beispiel“ (12 Units, 18 uses-Kanten)', mText);
  Assert.Contains(mText, 'Neue Zyklen: 1');
  Assert.Contains(mText, 'Entfernte Zyklen: 0');
  Assert.Contains(mText, 'Neue Querverbindungen: ');
  Assert.Contains(mText, 'Teilsystemwechsel: ');
  Assert.Contains(mText, 'Gewachsene zentrale Units: ');
  Assert.Contains(mText, 'Neue Units: 0');
  Assert.Contains(mText, 'Ergebnis: Abweichung newCycle (fail-on newCycle)');
  mText := TArchitectureComparer.Text(mComparison, [TArchitectureFailKind.CentralGrowth], 0);
  Assert.Contains(mText, 'Ergebnis: keine Abweichung der Arten centralGrowth');
  // Gekürzt.
  mComparison.NewUnits := TArray<string>.Create('a', 'b', 'c');
  mText := TArchitectureComparer.Text(mComparison, [], 2);
  Assert.Contains(mText, '  … 1 weitere');
  Assert.Contains(mText, 'keine Abweichung gilt als Fehler');
end;

procedure TArchitectureComparisonTests.MarkdownHasComparisonSection;
var
  mText: string;
begin
  mText := TArchitectureComparer.Markdown(TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log']))));
  Assert.StartsWith('## Vergleich', mText);
  Assert.Contains(mText, '### Neue Zyklen (1)');
  Assert.Contains(mText, '### Entfernte Units (0)');
  mText := TArchitectureComparer.Markdown(TArchitectureComparer.Compare(SnapshotOf(ArchitectureSampleUnits),
    SnapshotOf(ArchitectureSampleUnits)));
  Assert.Contains(mText, 'Keine Abweichung.');
end;

procedure TArchitectureComparisonTests.JsonIsValid;
var
  mRoot: TJSONValue;
  mData: TJSONObject;
begin
  mRoot := TJSONObject.ParseJSONValue(TArchitectureComparer.Json(TArchitectureComparer.Compare(
    SnapshotOf(ArchitectureSampleUnits), SnapshotOf(Replaced('App.Core.Base', nil, ['App.Core.Log']))),
    TArchitectureComparer.DefaultFailOn));
  try
    Assert.IsTrue(mRoot is TJSONObject);
    mData := TJSONObject(mRoot);
    Assert.AreEqual(1, mData.GetValue<TJSONArray>('newCycles').Count);
    Assert.AreEqual('newCycle', mData.GetValue<TJSONArray>('failed').Items[0].Value);
    Assert.AreEqual('newCycle', mData.GetValue<TJSONArray>('failOn').Items[0].Value);
    Assert.AreEqual(1, mData.GetValue<TJSONArray>('addedEdges').Count);
    Assert.AreEqual('App.Core.Base', (mData.GetValue<TJSONArray>('addedEdges').Items[0] as TJSONArray).Items[0].Value);
    Assert.AreEqual(12, (mData.GetValue('baseline') as TJSONObject).GetValue<Integer>('units'));
  finally
    mRoot.Free;
  end;
end;

procedure TArchitectureComparisonTests.ParsesKinds;
var
  mKinds: TArchitectureFailKinds;
  mError: string;
begin
  Assert.IsTrue(TArchitectureComparer.ParseKindList('newCycle,NEWCROSSLINK subsystemChange', mKinds, mError));
  Assert.AreEqual<TArchitectureFailKinds>([TArchitectureFailKind.NewCycle, TArchitectureFailKind.NewCrossLink,
    TArchitectureFailKind.SubsystemChange], mKinds);
  Assert.IsFalse(TArchitectureComparer.ParseKindList('newCycle,error', mKinds, mError));
  Assert.Contains(mError, '"error"');
  Assert.IsTrue(TArchitectureComparer.ParseKindList('', mKinds, mError));
  Assert.AreEqual<TArchitectureFailKinds>([], mKinds);
  Assert.AreEqual('newCycle,centralGrowth', string.Join(',', TArchitectureComparer.KindNames(
    [TArchitectureFailKind.CentralGrowth, TArchitectureFailKind.NewCycle])));
  Assert.AreEqual<TArchitectureFailKinds>([TArchitectureFailKind.NewCycle], TArchitectureComparer.DefaultFailOn);
end;

procedure TArchitectureComparisonTests.NotesDifferentResolution;
var
  mOlder, mNewer: TArchitectureSnapshot;
  mComparison: TArchitectureComparison;
begin
  mOlder := TwoGroups('Kern', 'Ui');
  mNewer := TwoGroups('Kern', 'Ui');
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.IsFalse(mComparison.ResolutionDiffers, 'Stände ohne Angabe: beide 1,0');
  Assert.AreEqual('', mComparison.GroupingNote);
  mNewer.Grouping := TArchitectureGrouping.Default;
  mNewer.Grouping.Resolution := 2;
  mComparison := TArchitectureComparer.Compare(mOlder, mNewer);
  Assert.IsTrue(mComparison.ResolutionDiffers);
  Assert.Contains(mComparison.GroupingNote, 'Feinheit γ = 1,0', False);
  Assert.Contains(mComparison.GroupingNote, 'γ = 2,0', False);
  Assert.Contains(TArchitectureComparer.Text(mComparison, [], 0), mComparison.GroupingNote, False);
  Assert.Contains(TArchitectureComparer.Markdown(mComparison), mComparison.GroupingNote, False);
  Assert.Contains(TArchitectureComparer.Json(mComparison, []), '"edges":0,"resolution":1}');
  Assert.Contains(TArchitectureComparer.Json(mComparison, []), ',"resolution":2');
end;

initialization
  TDUnitX.RegisterTestFixture(TArchitectureComparisonTests);

end.
