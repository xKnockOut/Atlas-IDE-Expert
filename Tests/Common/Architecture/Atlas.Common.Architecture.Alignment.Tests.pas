unit Atlas.Common.Architecture.Alignment.Tests;

// Tests der Angleichung (#1367): Farben und Namen bleiben, wenn eine neue
// Unit die Reihenfolge zweier gleich großer Teilsysteme vertauscht; bei
// Aufteilung erbt der Teil mit Mehrheit, bei Verschmelzung das größte alte;
// neue Namen werden gegen behaltene eindeutig; Vergleich und Angleichung
// lesen dieselbe Zuordnung; Bericht nennt die Angleichung.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.Overview;

type
  [TestFixture]
  TArchitectureAlignmentTests = class
  public
    [Test]
    procedure SwappedOrderKeepsColorsAndNames;
    [Test]
    procedure SplitPassesOnToMajorityPart;
    [Test]
    procedure MergeKeepsLargestOld;
    [Test]
    procedure WithoutMatchNothingChanges;
    [Test]
    procedure UniqueNames;
    [Test]
    procedure ComparisonAndAlignmentShareMatching;
    [Test]
    procedure SnapshotKeepsColors;
    [Test]
    procedure ReportNamesAlignment;
  end;

/// <summary>ACount Units ANamespace.APrefix1 …, jede verwendet alle vorigen im interface.</summary>
function AlignmentCluster(const ANamespace, APrefix: string; ACount: Integer): TArray<TUnitIndex>;
/// <summary>Drei gleich große Gruppen Index.A*, Index.B* und Ui.X*; mit AExtra eine vierte Unit in Index.B*.
/// </summary>
function AlignmentSample(AExtra: Boolean): TArray<TUnitIndex>;
/// <summary>Übersicht zu AlignmentSample (ohne Fundstellen).</summary>
function AlignmentOverview(AExtra: Boolean): TArchitectureOverview;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Matching,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.Alignment,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Common.Architecture.Snapshot.Tests;

function AlignmentCluster(const ANamespace, APrefix: string; ACount: Integer): TArray<TUnitIndex>;
var
  mIndex, mOther: Integer;
  mUses: TArray<string>;
begin
  Result := nil;
  for mIndex := 1 to ACount do
  begin
    mUses := nil;
    for mOther := 1 to mIndex - 1 do
      mUses := mUses + [ANamespace + '.' + APrefix + IntToStr(mOther)];
    Result := Result + [UsesUnit(ANamespace + '.' + APrefix + IntToStr(mIndex), mUses, nil)];
  end;
end;

function AlignmentSample(AExtra: Boolean): TArray<TUnitIndex>;
begin
  if AExtra then
    Result := AlignmentCluster('Index', 'A', 3) + AlignmentCluster('Index', 'B', 4) + AlignmentCluster('Ui', 'X', 3)
  else
    Result := AlignmentCluster('Index', 'A', 3) + AlignmentCluster('Index', 'B', 3) + AlignmentCluster('Ui', 'X', 3);
end;

function AlignmentOverview(AExtra: Boolean): TArchitectureOverview;
begin
  Result := ArchitectureOverviewOf(AlignmentSample(AExtra));
end;

/// <summary>Teilsystem mit der Unit AUnit.</summary>
function SubsystemWith(const AOverview: TArchitectureOverview; const AUnit: string): TOverviewSubsystem;
begin
  Result := AOverview.Subsystems[AOverview.Units[AOverview.IndexOf(AUnit)].Subsystem];
end;

procedure TArchitectureAlignmentTests.SwappedOrderKeepsColorsAndNames;
var
  mBefore, mAfter, mAligned: TArchitectureOverview;
begin
  mBefore := ArchitectureOverviewOf(AlignmentSample(False));
  Assert.AreEqual(3, Integer(Length(mBefore.Subsystems)));
  Assert.AreEqual('Index', SubsystemWith(mBefore, 'Index.A1').Name);
  Assert.AreEqual('Index 2', SubsystemWith(mBefore, 'Index.B1').Name);
  Assert.AreEqual(0, SubsystemWith(mBefore, 'Index.A1').ColorSlot);
  Assert.AreEqual(1, SubsystemWith(mBefore, 'Index.B1').ColorSlot);
  // Ohne Angleichung tauscht die neue Unit Index.B4 Farbe und Namen der beiden Index-Gruppen.
  mAfter := ArchitectureOverviewOf(AlignmentSample(True));
  Assert.AreEqual('Index', SubsystemWith(mAfter, 'Index.B1').Name);
  Assert.AreEqual(0, SubsystemWith(mAfter, 'Index.B1').ColorSlot);
  Assert.IsFalse(mAfter.IsAligned);
  mAligned := mAfter;
  Assert.AreEqual(3, TArchitectureAlignment.Align(mAligned, TArchitectureSnapshots.FromOverview(mBefore),
    TArchitectureAnalyzer.AlignedLast, EncodeDate(2026, 10, 29)));
  Assert.AreEqual('Index', SubsystemWith(mAligned, 'Index.A1').Name);
  Assert.AreEqual('Index 2', SubsystemWith(mAligned, 'Index.B1').Name);
  Assert.AreEqual(0, SubsystemWith(mAligned, 'Index.A1').ColorSlot);
  Assert.AreEqual(1, SubsystemWith(mAligned, 'Index.B1').ColorSlot);
  Assert.AreEqual(2, SubsystemWith(mAligned, 'Ui.X1').ColorSlot);
  // Reihenfolge bleibt nach Größe: die größere Gruppe zuerst.
  Assert.AreEqual('Index 2', mAligned.Subsystems[0].Name);
  Assert.IsTrue(mAligned.IsAligned);
  Assert.AreEqual(TArchitectureAnalyzer.AlignedLast, mAligned.AlignedSource);
  Assert.AreEqual(3, mAligned.AlignedKept);
  // Die Zuordnungen nennen die angeglichenen Teilsysteme (#1368).
  Assert.AreEqual(Integer(Length(mAligned.Units)), Integer(Length(mAligned.Assignments)));
  // Deterministisch: derselbe vorige Stand ergibt dasselbe.
  mAfter := ArchitectureOverviewOf(AlignmentSample(True));
  TArchitectureAlignment.Align(mAfter, TArchitectureSnapshots.FromOverview(mBefore), TArchitectureAnalyzer.AlignedLast,
    EncodeDate(2026, 10, 29));
  Assert.AreEqual(TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mAligned)),
    TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mAfter)));
end;

procedure TArchitectureAlignmentTests.SplitPassesOnToMajorityPart;
var
  mBefore, mAfter: TArchitectureOverview;
  mPrevious: TArchitectureSnapshot;
  mIndex: Integer;
begin
  // Vorher: Kern mit 6 Units, Ui mit 3; nachher zerfällt Kern in 4 + 2.
  mBefore := ArchitectureOverviewOf(AlignmentCluster('Kern', 'K', 6) + AlignmentCluster('Ui', 'X', 3));
  Assert.AreEqual(2, Integer(Length(mBefore.Subsystems)));
  mPrevious := TArchitectureSnapshots.FromOverview(mBefore);
  // Farbe 5 im alten Stand: Der Teil mit Mehrheit übernimmt sie, nicht die Nummer nach Reihenfolge.
  for mIndex := 0 to High(mPrevious.Subsystems) do
    if mPrevious.Subsystems[mIndex].Name = 'Kern' then
      mPrevious.Subsystems[mIndex].ColorSlot := 5;
  mAfter := ArchitectureOverviewOf(AlignmentCluster('Kern', 'K', 4) + AlignmentCluster('Kern', 'L', 2) +
    AlignmentCluster('Ui', 'X', 3));
  Assert.AreEqual(3, Integer(Length(mAfter.Subsystems)));
  Assert.AreEqual(2, TArchitectureAlignment.Align(mAfter, mPrevious, TArchitectureAnalyzer.AlignedBaseline, Now));
  Assert.AreEqual('Kern', SubsystemWith(mAfter, 'Kern.K1').Name);
  Assert.AreEqual(5, SubsystemWith(mAfter, 'Kern.K1').ColorSlot);
  Assert.AreEqual('Ui', SubsystemWith(mAfter, 'Ui.X1').Name);
  // Der andere Teil: neuer Name (eindeutig gegen „Kern“) und die kleinste freie Farbe.
  Assert.AreEqual('Kern 2', SubsystemWith(mAfter, 'Kern.L1').Name);
  Assert.AreNotEqual(5, SubsystemWith(mAfter, 'Kern.L1').ColorSlot);
  Assert.AreNotEqual(SubsystemWith(mAfter, 'Ui.X1').ColorSlot, SubsystemWith(mAfter, 'Kern.L1').ColorSlot);
  Assert.AreEqual(TArchitectureAnalyzer.AlignedBaseline, mAfter.AlignedSource);
end;

procedure TArchitectureAlignmentTests.MergeKeepsLargestOld;
var
  mBefore, mAfter: TArchitectureOverview;
  mUnits: TArray<TUnitIndex>;
begin
  mBefore := ArchitectureOverviewOf(AlignmentCluster('Kern', 'K', 3) + AlignmentCluster('Daten', 'D', 2) +
    AlignmentCluster('Ui', 'X', 3));
  // Nachher verwendet Daten.D1 den Kern: beide verschmelzen.
  mUnits := AlignmentCluster('Kern', 'K', 3) + [UsesUnit('Daten.D1', ['Kern.K1', 'Kern.K2', 'Kern.K3'], nil),
    UsesUnit('Daten.D2', ['Daten.D1', 'Kern.K3'], nil)] + AlignmentCluster('Ui', 'X', 3);
  mAfter := ArchitectureOverviewOf(mUnits);
  Assert.AreEqual(SubsystemWith(mAfter, 'Kern.K1').Name, SubsystemWith(mAfter, 'Daten.D1').Name,
    'Testgraph: Kern und Daten verschmolzen');
  TArchitectureAlignment.Align(mAfter, TArchitectureSnapshots.FromOverview(mBefore), TArchitectureAnalyzer.AlignedLast,
    Now);
  Assert.AreEqual(SubsystemWith(mBefore, 'Kern.K1').Name, SubsystemWith(mAfter, 'Kern.K1').Name);
  Assert.AreEqual(SubsystemWith(mBefore, 'Kern.K1').ColorSlot, SubsystemWith(mAfter, 'Kern.K1').ColorSlot);
  Assert.AreEqual(SubsystemWith(mBefore, 'Ui.X1').ColorSlot, SubsystemWith(mAfter, 'Ui.X1').ColorSlot);
end;

procedure TArchitectureAlignmentTests.WithoutMatchNothingChanges;
var
  mOverview, mAligned: TArchitectureOverview;
  mPrevious: TArchitectureSnapshot;
begin
  mOverview := ArchitectureOverviewOf(AlignmentSample(False));
  mAligned := mOverview;
  // Ein Stand ganz anderer Units: nichts zugeordnet, nichts angeglichen.
  mPrevious := TArchitectureSnapshots.FromOverview(ArchitectureOverviewOf(AlignmentCluster('Alt', 'Z', 3)));
  Assert.AreEqual(0, TArchitectureAlignment.Align(mAligned, mPrevious, TArchitectureAnalyzer.AlignedLast, Now));
  Assert.IsFalse(mAligned.IsAligned);
  Assert.AreEqual(TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mOverview)),
    TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mAligned)));
  // Leerer Stand ebenso.
  Assert.AreEqual(0, TArchitectureAlignment.Align(mAligned, Default(TArchitectureSnapshot),
    TArchitectureAnalyzer.AlignedLast, Now));
end;

procedure TArchitectureAlignmentTests.UniqueNames;
begin
  Assert.AreEqual('Ui', TArchitectureAlignment.UniqueName('Ui', TArray<string>.Create('Kern')));
  Assert.AreEqual('Kern 2', TArchitectureAlignment.UniqueName('Kern', TArray<string>.Create('kern')));
  Assert.AreEqual('Index 3', TArchitectureAlignment.UniqueName('Index 2', TArray<string>.Create('Index', 'Index 2')));
  Assert.AreEqual('Index 3', TArchitectureAlignment.UniqueName('Index', TArray<string>.Create('Index', 'Index 2')));
  // Ein Name, der selbst auf eine Zahl endet, ohne Leerzeichen davor, bleibt ganz.
  Assert.AreEqual('Win32 2', TArchitectureAlignment.UniqueName('Win32', TArray<string>.Create('Win32')));
end;

procedure TArchitectureAlignmentTests.ComparisonAndAlignmentShareMatching;
var
  mBefore, mAfter: TArchitectureOverview;
  mOld, mNew: TArchitectureSnapshot;
  mOverlap, mCompared: TArray<TSubsystemMatch>;
  mIndex: Integer;
begin
  mBefore := ArchitectureOverviewOf(AlignmentCluster('Kern', 'K', 6) + AlignmentCluster('Ui', 'X', 3));
  mAfter := ArchitectureOverviewOf(AlignmentCluster('Kern', 'K', 4) + AlignmentCluster('Kern', 'L', 2) +
    AlignmentCluster('Ui', 'X', 3));
  mOld := TArchitectureSnapshots.FromOverview(mBefore);
  mNew := TArchitectureSnapshots.FromOverview(mAfter);
  // Der Vergleich liest die gemeinsame Routine im Modus Überschneidung …
  mOverlap := TSubsystemMatcher.Match(mOld, mNew, TSubsystemMatchMode.Overlap);
  mCompared := TArchitectureComparer.Compare(mOld, mNew).Matches;
  Assert.AreEqual(Integer(Length(mOverlap)), Integer(Length(mCompared)));
  for mIndex := 0 to High(mOverlap) do
  begin
    Assert.AreEqual(mOverlap[mIndex].NewName, mCompared[mIndex].NewName);
    Assert.AreEqual(mOverlap[mIndex].OldName, mCompared[mIndex].OldName);
  end;
  // … die Angleichung dieselbe im Modus Mehrheit: Der Teil Kern 2 (2 von 6) bekommt nichts.
  Assert.AreEqual('Kern', TArchitectureComparer.Compare(mOld, mNew).MatchOf('Kern'));
  TArchitectureAlignment.Align(mAfter, mOld, TArchitectureAnalyzer.AlignedLast, Now);
  Assert.AreEqual('Kern', SubsystemWith(mAfter, 'Kern.K1').Name);
  // Nach der Angleichung meldet der Vergleich für die Units des Kerns keinen Wechsel.
  Assert.AreEqual('Kern', TArchitectureComparer.Compare(mOld, TArchitectureSnapshots.FromOverview(mAfter))
    .MatchOf('Kern'));
end;

procedure TArchitectureAlignmentTests.SnapshotKeepsColors;
var
  mOverview: TArchitectureOverview;
  mSnapshot, mParsed: TArchitectureSnapshot;
  mText, mError: string;
begin
  mOverview := ArchitectureOverviewOf(AlignmentSample(False));
  mSnapshot := TArchitectureSnapshots.FromOverview(mOverview);
  mText := TArchitectureSnapshots.Json(mSnapshot);
  Assert.Contains(mText, '"color": 1, "shade": 0}');
  Assert.IsTrue(TArchitectureSnapshots.Parse(mText, mParsed, mError), mError);
  Assert.IsTrue(mParsed.Subsystems[0].HasColor);
  // Stände vor #1367 ohne Farbe: HasColor False, die Angleichung vergibt dann neue Farben.
  Assert.IsTrue(TArchitectureSnapshots.Parse(StringReplace(mText, ', "color": 1', '', [rfReplaceAll]), mParsed,
    mError), mError);
  Assert.IsFalse(mParsed.Subsystems[1].HasColor);
end;

procedure TArchitectureAlignmentTests.ReportNamesAlignment;
var
  mOverview: TArchitectureOverview;
  mJson: TJSONValue;
  mAligned: TJSONObject;
begin
  mOverview := ArchitectureOverviewOf(AlignmentSample(True));
  Assert.AreEqual('', TArchitectureReport.AlignedText(mOverview));
  Assert.DoesNotContain(TArchitectureReport.Json(mOverview, TArchitectureLayouter.Compute(mOverview)), '"aligned"');
  TArchitectureAlignment.Align(mOverview, TArchitectureSnapshots.FromOverview(ArchitectureOverviewOf(
    AlignmentSample(False))), TArchitectureAnalyzer.AlignedBaseline, EncodeDate(2026, 10, 29) + EncodeTime(14, 23, 0,
    0));
  Assert.AreEqual('Teilsysteme an Stand vom 2026-10-29 14:23 angeglichen (architecture.baseline; 3 Teilsysteme ' +
    'behalten Farbe und Namen)', TArchitectureReport.AlignedText(mOverview));
  Assert.Contains(TArchitectureReport.Markdown(mOverview), 'Teilsysteme an Stand vom 2026-10-29 14:23 angeglichen');
  Assert.Contains(TArchitectureReport.Text(mOverview, TArchitectureSection.Overview, 10), 'angeglichen');
  mJson := TJSONObject.ParseJSONValue(TArchitectureReport.Json(mOverview, TArchitectureLayouter.Compute(mOverview)));
  try
    Assert.IsTrue(mJson is TJSONObject);
    mAligned := TJSONObject(TJSONObject(mJson).GetValue('aligned'));
    Assert.IsNotNull(mAligned);
    Assert.AreEqual('baseline', mAligned.GetValue('source').Value);
    Assert.AreEqual('2026-10-29T14:23:00', mAligned.GetValue('at').Value);
    Assert.AreEqual('3', mAligned.GetValue('kept').Value);
  finally
    mJson.Free;
  end;
end;

end.
