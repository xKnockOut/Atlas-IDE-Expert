unit Atlas.Core.Tracker.BoardLayout.Tests;

// Anordnung des Boards (#1272) ohne Fenster: Spalten und Karten breit und
// schmal, Swimlanes, eingeklappte Gruppen, Treffer der Maus und das Merken
// eingeklappter Spalten und Swimlanes.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasBoardLayoutTests = class
  public
    [Test]
    procedure WideLayoutPutsColumnsSideBySide;
    [Test]
    procedure CardsWithoutColumnGetOwnColumn;
    /// <summary>Swimlanes breit: Namen links, eine Zeile je Wert, Karten in ihrer Zelle, Zähler je Spalte und
    /// Zeile, Einklappen per Schlüssel; schmal ohne Swimlanes.</summary>
    [Test]
    procedure SwimlanesLayoutRowsPerValue;
    [Test]
    procedure NarrowLayoutStacksAndCollapses;
    [Test]
    procedure HitTesting;
    /// <summary>Zweimal umschalten klappt wieder aus; Spalten und Swimlanes getrennt.</summary>
    [Test]
    procedure FoldsToggle;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.BoardLayout,
  Atlas.Core.Tracker.BoardLayout.TestSupport;

function Metrics: TAtlasBoardMetrics;
begin
  Result := TAtlasBoardMetrics.Create(16);
end;

function AllCards(const ASnapshot: TAtlasBoardSnapshot): TArray<Integer>;
begin
  Result := TAtlasTrackerBoard.Visible(ASnapshot, False, '');
end;

function Center(const ARect: TRect): TPoint;
begin
  Result := Point((ARect.Left + ARect.Right) div 2, (ARect.Top + ARect.Bottom) div 2);
end;

{ TAtlasBoardLayoutTests }

procedure TAtlasBoardLayoutTests.WideLayoutPutsColumnsSideBySide;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
begin
  mSnapshot := SampleBoard;
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 800, nil, Metrics);
  Assert.IsFalse(mLayout.Narrow);
  Assert.AreEqual(3, Integer(Length(mLayout.Columns)), 'keine Spalte „ohne Spalte“');
  Assert.AreEqual(2, mLayout.Counts[0]);
  Assert.AreEqual(1, mLayout.Counts[1]);
  Assert.AreEqual(1, mLayout.Counts[2]);
  Assert.AreEqual(4, Integer(Length(mLayout.Places)));
  // Nebeneinander, gleiche Höhe der Köpfe.
  Assert.IsTrue(mLayout.Headers[1].Left > mLayout.Headers[0].Right);
  Assert.AreEqual(mLayout.Headers[0].Top, mLayout.Headers[2].Top);
  Assert.IsTrue(mLayout.Width >= 800);
  // Mindestbreite: viele Spalten in wenig Platz werden breiter als das Fenster (Bildlauf).
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 400, nil, Metrics);
  Assert.IsTrue(mLayout.Width > 400);
end;

procedure TAtlasBoardLayoutTests.CardsWithoutColumnGetOwnColumn;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
begin
  mSnapshot := SampleBoard;
  mSnapshot.Cards := mSnapshot.Cards + [SampleCard('ATL-5', 'Wartet', '')];
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 1000, nil, Metrics);
  Assert.AreEqual(4, Integer(Length(mLayout.Columns)));
  Assert.AreEqual(-1, mLayout.Columns[3]);
  Assert.AreEqual(1, mLayout.Counts[3]);
  // Ausgefiltert: keine Spalte „ohne Spalte“.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, TAtlasTrackerBoard.Visible(mSnapshot, False, 'ATL-1'), 1000, nil,
    Metrics);
  Assert.AreEqual(3, Integer(Length(mLayout.Columns)));
end;

procedure TAtlasBoardLayoutTests.SwimlanesLayoutRowsPerValue;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
  mPlace: TAtlasBoardPlace;
begin
  mSnapshot := SampleBoard;
  mSnapshot.Swimlanes.Fields := TArray<string>.Create('Assignee');
  mSnapshot.Swimlanes.Caption := 'Zugewiesen an';
  mSnapshot.Cards[0].Lane := 'Bähring, Marco';
  mSnapshot.Cards[0].LaneId := 'marco';
  mSnapshot.Cards[1].Lane := 'Anna';
  mSnapshot.Cards[1].LaneId := 'anna';
  mSnapshot.Cards[2].Lane := 'Bähring, Marco';
  mSnapshot.Cards[2].LaneId := 'marco';
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 1000, nil, Metrics);
  // Anna, Bähring, ohne Wert (ATL-4).
  Assert.AreEqual(Integer(3), Integer(Length(mLayout.Lanes)));
  Assert.AreEqual('Anna', mLayout.Lanes[0].Name);
  Assert.IsTrue(mLayout.Lanes[2].Orphans);
  Assert.AreEqual(2, mLayout.LaneCounts[1]);
  Assert.AreEqual(2, mLayout.Counts[0], 'Zähler der Spalte über alle Zeilen');
  Assert.AreEqual(4, Integer(Length(mLayout.Places)));
  // Spalten rechts der Namen; Karte ATL-3 (Bähring, In Arbeit) in der zweiten Zeile unter der zweiten Spalte.
  Assert.IsTrue(mLayout.Headers[0].Left >= mLayout.Corner.Right);
  Assert.IsTrue(mLayout.PlaceOf(2, mPlace));
  Assert.IsTrue(mPlace.Bounds.Left >= mLayout.Headers[1].Left);
  Assert.IsTrue(mPlace.Bounds.Top >= mLayout.LaneBoxes[1].Top);
  Assert.IsTrue(mPlace.Bounds.Bottom <= mLayout.LaneBoxes[1].Bottom);
  Assert.AreEqual(1, mLayout.LaneAt(Center(mLayout.LaneBoxes[1])));
  Assert.AreEqual(1, mLayout.ColumnAt(Center(mPlace.Bounds)));
  // Eingeklappt: Zeile ohne Karten, Zähler bleiben.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 1000, nil,
    TArray<string>.Create('Bähring, Marco'), Metrics);
  Assert.AreEqual(2, Integer(Length(mLayout.Places)));
  Assert.AreEqual(2, mLayout.LaneCounts[1]);
  Assert.AreEqual('', TAtlasBoardLayout.LaneKey(mLayout.Lanes[2]));
  // Schmal: ohne Swimlanes.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 300, nil, Metrics);
  Assert.AreEqual(Integer(0), Integer(Length(mLayout.Lanes)));
end;

procedure TAtlasBoardLayoutTests.NarrowLayoutStacksAndCollapses;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
  mPlace: TAtlasBoardPlace;
begin
  mSnapshot := SampleBoard;
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 300, nil, Metrics);
  Assert.IsTrue(mLayout.Narrow);
  Assert.AreEqual(300, mLayout.Width);
  Assert.AreEqual(mLayout.Headers[0].Left, mLayout.Headers[1].Left, 'untereinander');
  Assert.IsTrue(mLayout.Headers[1].Top >= mLayout.Areas[0].Bottom);
  Assert.AreEqual(4, Integer(Length(mLayout.Places)));
  // Gruppe „Offen“ eingeklappt: Kopf bleibt mit Anzahl, Karten verschwinden.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 300, TArray<Integer>.Create(0), Metrics);
  Assert.AreEqual(2, mLayout.Counts[0]);
  Assert.AreEqual(2, Integer(Length(mLayout.Places)));
  Assert.IsFalse(mLayout.PlaceOf(0, mPlace));
  Assert.IsTrue(mLayout.PlaceOf(2, mPlace));
  Assert.AreEqual(1, mPlace.Column);
  // Breit wirkt Einklappen nicht.
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 800, TArray<Integer>.Create(0), Metrics);
  Assert.AreEqual(4, Integer(Length(mLayout.Places)));
end;

procedure TAtlasBoardLayoutTests.HitTesting;
var
  mSnapshot: TAtlasBoardSnapshot;
  mLayout: TAtlasBoardLayout;
  mPlace: TAtlasBoardPlace;
begin
  mSnapshot := SampleBoard;
  mLayout := TAtlasBoardLayout.Build(mSnapshot, AllCards(mSnapshot), 800, nil, Metrics);
  Assert.IsTrue(mLayout.PlaceOf(2, mPlace));
  Assert.AreEqual(2, mLayout.CardAt(Center(mPlace.Bounds)));
  Assert.AreEqual(1, mLayout.ColumnAt(Center(mPlace.Bounds)));
  Assert.AreEqual(2, mLayout.HeaderAt(Center(mLayout.Headers[2])));
  Assert.AreEqual(2, mLayout.ColumnAt(Center(mLayout.Headers[2])), 'Kopf gehört zur Spalte');
  Assert.AreEqual(-1, mLayout.CardAt(Center(mLayout.Headers[2])));
  Assert.AreEqual(-1, mLayout.CardAt(Point(1, 1)));
  Assert.AreEqual(-2, mLayout.ColumnAt(Point(1, 1)), 'Rand gehört zu keiner Spalte');
  Assert.AreEqual(-2, mLayout.HeaderAt(Point(1, 1)));
end;


procedure TAtlasBoardLayoutTests.FoldsToggle;
var
  mFolds: TAtlasBoardFolds;
begin
  mFolds := TAtlasBoardFolds.Create;
  try
    Assert.IsFalse(mFolds.Collapsed(-1));
    mFolds.ToggleColumn(-1);
    mFolds.ToggleColumn(2);
    Assert.IsTrue(mFolds.Collapsed(-1), 'ohne Spalte');
    Assert.IsTrue(mFolds.Collapsed(2));
    Assert.IsFalse(mFolds.Collapsed(0));
    mFolds.ToggleColumn(-1);
    Assert.IsFalse(mFolds.Collapsed(-1), 'wieder ausgeklappt');
    Assert.AreEqual(1, Integer(Length(mFolds.Columns)));
    mFolds.ToggleLane('');
    Assert.IsTrue(mFolds.LaneCollapsed(''), 'Zeile ohne Wert');
    Assert.IsFalse(mFolds.LaneCollapsed('Anna'));
    mFolds.ToggleLane('Anna');
    mFolds.ToggleLane('');
    Assert.IsFalse(mFolds.LaneCollapsed(''));
    Assert.AreEqual(1, Integer(Length(mFolds.Lanes)));
    Assert.AreEqual('Anna', mFolds.Lanes[0]);
  finally
    mFolds.Free;
  end;
end;

end.
