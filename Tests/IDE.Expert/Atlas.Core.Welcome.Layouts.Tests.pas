unit Atlas.Core.Welcome.Layouts.Tests;

// Tests der frei anordenbaren Willkommensseite ohne VCL (#767): Bearbeiten
// eines Layouts (Ziehen, Strg+Pfeiltasten, Breite, Ausblenden, Spalten, neue
// und unbekannte Bereiche, JSON), die Lage auf der Fläche, mehrere benannte
// Layouts sowie der Abgleich mit den Plugin-Einstellungen (Auge, Wechsel,
// Zurücksetzen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeArrangeTests = class
  public
    [Test]
    procedure DragMovesStateTileTopLeft;
    [Test]
    procedure DragUnknownSectionAddsSlot;
    [Test]
    procedure CtrlArrowsMoveStepByStep;
    [Test]
    procedure CtrlArrowsStopAtTheEdge;
    [Test]
    procedure WidthIsClampedAndSpansColumns;
    [Test]
    procedure HidingKeepsThePlace;
    [Test]
    procedure ColumnsKeepTheSlots;
    [Test]
    procedure NewSectionsGoToRoomiestColumn;
    [Test]
    procedure JsonKeepsWidthAndVisibility;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeFlowTests = class
  public
    [Test]
    procedure WideSectionStartsBelowBothColumns;
    [Test]
    procedure DropTargetAndInsertLine;
    [Test]
    procedure FitsColumnsToWidth;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeLayoutsTests = class
  public
    [Test]
    procedure DefaultIsStoredEmpty;
    [Test]
    procedure AddRenameDeleteAndActivate;
    [Test]
    procedure TwoLayoutsRoundTrip;
    [Test]
    procedure InvalidEntriesAreDropped;
    [Test]
    procedure UniqueNameCounts;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeCustomizingTests = class
  public
    [Test]
    procedure CatalogSettingsExist;
    [Test]
    procedure EyeTurnsTheSettingOff;
    [Test]
    procedure LoadReadsVisibilityAndColumns;
    [Test]
    procedure StoredWritesOnlyChanges;
    [Test]
    procedure SwitchRemembersVisibility;
    [Test]
    procedure ResetRestoresAtlasLayout;
    [Test]
    procedure AdoptsNewSectionsOnlyWhenStored;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Layouts;

function Section(const AId: string; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, AId, 10, AColumn, nil);
end;

/// <summary>Alle Bereiche des Atlas-Layouts als sichtbare Bereiche.</summary>
function AtlasSections: TArray<TAtlasWelcomeSection>;
var
  mSlot: TAtlasWelcomeSlot;
  mColumn: TAtlasWelcomeColumn;
begin
  Result := nil;
  for mSlot in TAtlasWelcomeLayout.Atlas.Slots do
  begin
    mColumn := TAtlasWelcomeColumn.Left;
    if mSlot.Column > 0 then
    begin
      mColumn := TAtlasWelcomeColumn.Right;
    end;
    Result := Result + [Section(mSlot.Id, mColumn)];
  end;
end;

function Joined(const AIds: TArray<string>): string;
var
  mId: string;
begin
  Result := '';
  for mId in AIds do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mId;
  end;
end;

function Cell(const AId: string; ASpan: Integer): TAtlasWelcomeCell;
begin
  Result := TAtlasWelcomeCell.Create(AId, ASpan);
end;

/// <summary>Übernimmt ANext nach ATarget, wenn AOk. Die Bearbeitungen liefern ihr Ergebnis als out-Parameter;
/// der darf nicht die Variable sein, auf der sie aufgerufen werden (er wird beim Aufruf geleert).</summary>
function Step(AOk: Boolean; var ATarget: TAtlasWelcomeLayouts; const ANext: TAtlasWelcomeLayouts): Boolean;
begin
  Result := AOk;
  if AOk then
  begin
    ATarget := ANext;
  end;
end;

function AllVisible(const ALayout: TAtlasWelcomeLayout): TAtlasWelcomeLayout;
var
  mIndex: Integer;
begin
  Result := ALayout;
  Result.Slots := Copy(ALayout.Slots);
  for mIndex := 0 to High(Result.Slots) do
  begin
    Result.Slots[mIndex].Visible := True;
  end;
end;

{ TAtlasWelcomeArrangeTests }

procedure TAtlasWelcomeArrangeTests.DragMovesStateTileTopLeft;
var
  mMoved: TAtlasWelcomeLayout;
  mColumns: TArray<TArray<string>>;
begin
  // Akzeptanz: Zustandskachel per Ziehen nach links oben.
  mMoved := TAtlasWelcomeLayout.Atlas.MovedTo(TAtlasWelcomeIds.cState, 0, TAtlasWelcomeIds.cContinue);
  mColumns := mMoved.Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.state,atlas.continue,atlas.projects,atlas.history,atlas.tests', Joined(mColumns[0]));
  Assert.AreEqual('atlas.unsaved,atlas.news,atlas.discover,atlas.setup,atlas.issues,atlas.sprint,atlas.help',
    Joined(mColumns[1]));
  Assert.AreEqual(Integer(Length(TAtlasWelcomeLayout.Atlas.Slots)), Integer(Length(mMoved.Slots)));
  // Ans Ende einer Spalte; unbekanntes ABefore heißt ebenso ans Ende.
  mColumns := mMoved.MovedTo(TAtlasWelcomeIds.cState, 1, '').Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.unsaved,atlas.news,atlas.discover,atlas.setup,atlas.issues,atlas.sprint,atlas.help,' +
    'atlas.state', Joined(mColumns[1]));
  mColumns := mMoved.MovedTo(TAtlasWelcomeIds.cState, 1, 'gibt.es.nicht').Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.state', mColumns[1][High(mColumns[1])]);
  // Gleiche Stelle: unverändert.
  Assert.IsTrue(TAtlasWelcomeLayout.Same(mMoved,
    mMoved.MovedTo(TAtlasWelcomeIds.cState, 0, TAtlasWelcomeIds.cContinue)));
end;

procedure TAtlasWelcomeArrangeTests.DragUnknownSectionAddsSlot;
var
  mMoved: TAtlasWelcomeLayout;
  mSlot: TAtlasWelcomeSlot;
begin
  mMoved := TAtlasWelcomeLayout.Atlas.MovedTo('plugin.extra', 1, TAtlasWelcomeIds.cNews);
  Assert.IsTrue(mMoved.SlotOf('plugin.extra', mSlot));
  Assert.AreEqual(1, mSlot.Column);
  Assert.AreEqual(1, mSlot.Width);
  Assert.IsTrue(mSlot.Visible);
  Assert.AreEqual(mMoved.IndexOf(TAtlasWelcomeIds.cNews) - 1, mMoved.IndexOf('plugin.extra'));
end;

procedure TAtlasWelcomeArrangeTests.CtrlArrowsMoveStepByStep;
var
  mLayout, mMoved: TAtlasWelcomeLayout;
  mColumns: TArray<TArray<string>>;
begin
  // Akzeptanz: dasselbe nur mit Tastatur (Strg+Pfeil links bringt die Kachel nach links oben).
  mLayout := TAtlasWelcomeLayout.Atlas;
  Assert.IsTrue(mLayout.MovedBy(TAtlasWelcomeIds.cState, TAtlasWelcomeMove.Left, AtlasSections, mMoved));
  mColumns := mMoved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.cState, mColumns[0][0]);
  // Strg+Pfeil runter: hinter den nächsten Bereich.
  mLayout := mMoved;
  Assert.IsTrue(mLayout.MovedBy(TAtlasWelcomeIds.cState, TAtlasWelcomeMove.Down, AtlasSections, mMoved));
  mColumns := mMoved.Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.continue,atlas.state,atlas.projects', Joined(Copy(mColumns[0], 0, 3)));
  // Strg+Pfeil hoch: wieder davor.
  mLayout := mMoved;
  Assert.IsTrue(mLayout.MovedBy(TAtlasWelcomeIds.cState, TAtlasWelcomeMove.Up, AtlasSections, mMoved));
  mColumns := mMoved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.cState, mColumns[0][0]);
  // Strg+Pfeil rechts: in derselben Zeile der rechten Spalte.
  mLayout := mMoved;
  Assert.IsTrue(mLayout.MovedBy(TAtlasWelcomeIds.cState, TAtlasWelcomeMove.Right, AtlasSections, mMoved));
  mColumns := mMoved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.cState, mColumns[1][0]);
  // Runter bis ans Ende der Spalte: die vorletzte Kachel (Sprint, #1277) hinter die Hilfe.
  mLayout := TAtlasWelcomeLayout.Atlas;
  Assert.IsTrue(mLayout.MovedBy(TAtlasWelcomeIds.cSprint, TAtlasWelcomeMove.Down, AtlasSections, mMoved));
  mColumns := mMoved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.cSprint, mColumns[1][High(mColumns[1])]);
end;

procedure TAtlasWelcomeArrangeTests.CtrlArrowsStopAtTheEdge;
var
  mLayout, mMoved: TAtlasWelcomeLayout;
begin
  mLayout := TAtlasWelcomeLayout.Atlas;
  Assert.IsFalse(mLayout.MovedBy(TAtlasWelcomeIds.cContinue, TAtlasWelcomeMove.Up, AtlasSections, mMoved));
  Assert.IsFalse(mLayout.MovedBy(TAtlasWelcomeIds.cContinue, TAtlasWelcomeMove.Left, AtlasSections, mMoved));
  Assert.IsFalse(mLayout.MovedBy(TAtlasWelcomeIds.cState, TAtlasWelcomeMove.Right, AtlasSections, mMoved));
  Assert.IsFalse(mLayout.MovedBy(TAtlasWelcomeIds.cHelp, TAtlasWelcomeMove.Down, AtlasSections, mMoved));
  // Ein Bereich, der nicht zu sehen ist, bewegt sich nicht.
  Assert.IsFalse(mLayout.MovedBy(TAtlasWelcomeIds.cState, TAtlasWelcomeMove.Down,
    [Section(TAtlasWelcomeIds.cContinue, TAtlasWelcomeColumn.Left)], mMoved));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(mLayout, mMoved));
end;

procedure TAtlasWelcomeArrangeTests.WidthIsClampedAndSpansColumns;
var
  mWide: TAtlasWelcomeLayout;
  mCells: TAtlasWelcomeCells;
  mItem: TAtlasWelcomeCell;
  mSpan: Integer;
begin
  mWide := TAtlasWelcomeLayout.Atlas.WithWidth(TAtlasWelcomeIds.cProjects, 5);
  Assert.AreEqual(2, mWide.WidthOf(TAtlasWelcomeIds.cProjects));
  Assert.AreEqual(1, mWide.WithWidth(TAtlasWelcomeIds.cProjects, 0).WidthOf(TAtlasWelcomeIds.cProjects));
  Assert.AreEqual(1, mWide.WidthOf('gibt.es.nicht'));
  mSpan := 0;
  mCells := mWide.Cells(AtlasSections, 2);
  for mItem in mCells[0] do
  begin
    if mItem.Id = TAtlasWelcomeIds.cProjects then
    begin
      mSpan := mItem.Span;
    end;
  end;
  Assert.AreEqual(2, mSpan);
  // Eine Spalte: höchstens so breit wie die Fläche.
  mCells := mWide.Cells(AtlasSections, 1);
  for mItem in mCells[0] do
  begin
    if mItem.Id = TAtlasWelcomeIds.cProjects then
    begin
      mSpan := mItem.Span;
    end;
  end;
  Assert.AreEqual(1, mSpan);
end;

procedure TAtlasWelcomeArrangeTests.HidingKeepsThePlace;
var
  mHidden: TAtlasWelcomeLayout;
  mSlot: TAtlasWelcomeSlot;
begin
  mHidden := TAtlasWelcomeLayout.Atlas.WithVisible(TAtlasWelcomeIds.cTests, False);
  Assert.IsTrue(mHidden.SlotOf(TAtlasWelcomeIds.cTests, mSlot));
  Assert.IsFalse(mSlot.Visible);
  Assert.AreEqual(0, mSlot.Column);
  Assert.AreEqual(TAtlasWelcomeLayout.Atlas.IndexOf(TAtlasWelcomeIds.cTests), mHidden.IndexOf(TAtlasWelcomeIds.cTests));
  Assert.IsTrue(mHidden.WithVisible(TAtlasWelcomeIds.cTests, True).SlotOf(TAtlasWelcomeIds.cTests, mSlot));
  Assert.IsTrue(mSlot.Visible);
end;

procedure TAtlasWelcomeArrangeTests.ColumnsKeepTheSlots;
var
  mLayout: TAtlasWelcomeLayout;
  mColumns: TArray<TArray<string>>;
begin
  mLayout := TAtlasWelcomeLayout.Atlas.MovedTo(TAtlasWelcomeIds.cHelp, 2, '').WithColumns(3);
  Assert.AreEqual(3, mLayout.Columns);
  mColumns := mLayout.Arrange(AtlasSections, mLayout.Columns);
  Assert.AreEqual('atlas.help', Joined(mColumns[2]));
  // Weniger Spalten: Hilfe steht am Ende der letzten, die Plätze bleiben.
  mLayout := mLayout.WithColumns(2);
  mColumns := mLayout.Arrange(AtlasSections, mLayout.Columns);
  Assert.AreEqual('atlas.help', mColumns[1][High(mColumns[1])]);
  Assert.AreEqual('atlas.help', Joined(mLayout.WithColumns(3).Arrange(AtlasSections, 3)[2]), 'zurück an ihrem Platz');
  Assert.AreEqual(TAtlasWelcomeLayout.cMaxColumns, mLayout.WithColumns(9).Columns);
  Assert.AreEqual(TAtlasWelcomeLayout.cMinColumns, mLayout.WithColumns(0).Columns);
end;

procedure TAtlasWelcomeArrangeTests.NewSectionsGoToRoomiestColumn;
var
  mLayout: TAtlasWelcomeLayout;
  mAdded: TArray<string>;
  mSlot: TAtlasWelcomeSlot;
begin
  // Links stehen vier Plätze, rechts sieben: jeder Platz zählt 1.
  mLayout := TAtlasWelcomeLayout.Atlas.Adopted([TAtlasWelcomeIds.cState, 'plugin.neu'], nil, mAdded);
  Assert.AreEqual('plugin.neu', Joined(mAdded));
  Assert.IsTrue(mLayout.SlotOf('plugin.neu', mSlot));
  Assert.AreEqual(0, mSlot.Column);
  Assert.AreEqual(Integer(High(mLayout.Slots)), mLayout.IndexOf('plugin.neu'));
  // Mit Gewicht (Höhe): links ist die Spalte voller.
  mLayout := TAtlasWelcomeLayout.Atlas.Adopted(['plugin.neu'],
    function(const AId: string): Integer
    begin
      Result := 10;
      if AId = TAtlasWelcomeIds.cHistory then
      begin
        Result := 500;
      end;
    end, mAdded);
  Assert.IsTrue(mLayout.SlotOf('plugin.neu', mSlot));
  Assert.AreEqual(1, mSlot.Column);
  // Bekannte Bereiche kommen nicht doppelt.
  TAtlasWelcomeLayout.Atlas.Adopted([TAtlasWelcomeIds.cState], nil, mAdded);
  Assert.AreEqual(0, Integer(Length(mAdded)));
end;

procedure TAtlasWelcomeArrangeTests.JsonKeepsWidthAndVisibility;
var
  mLayout, mLoaded: TAtlasWelcomeLayout;
  mSlot: TAtlasWelcomeSlot;
begin
  mLayout := TAtlasWelcomeLayout.Atlas.WithWidth(TAtlasWelcomeIds.cHistory, 2)
    .WithVisible(TAtlasWelcomeIds.cDiscover, False).MovedTo(TAtlasWelcomeIds.cState, 0, '');
  mLayout.Name := 'Präsentation';
  Assert.IsTrue(TAtlasWelcomeLayout.FromJson(mLayout.ToJson, mLoaded));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(mLayout, mLoaded));
  Assert.IsTrue(mLoaded.SlotOf(TAtlasWelcomeIds.cHistory, mSlot));
  Assert.AreEqual(2, mSlot.Width);
  Assert.IsTrue(mLoaded.SlotOf(TAtlasWelcomeIds.cDiscover, mSlot));
  Assert.IsFalse(mSlot.Visible);
end;

{ TAtlasWelcomeFlowTests }

const
  cClientWidth = 412;
  cGap = 12;
  cMinWidth = 120;

function FlowCells: TAtlasWelcomeCells;
begin
  // Links a und der zweispaltige w, rechts b.
  Result := [[Cell('a', 1), Cell('w', 2)], [Cell('b', 1)]];
end;

function FlowHeight(const AId: string): Integer;
begin
  if AId = 'a' then
  begin
    Result := 100;
  end
  else if AId = 'b' then
  begin
    Result := 50;
  end
  else
  begin
    Result := 40;
  end;
end;

function Placed: TArray<TAtlasWelcomePlaced>;
begin
  Result := TAtlasWelcomeFlow.Place(FlowCells, cClientWidth, cGap, cMinWidth,
    function(const AId: string; AWidth: Integer): Integer
    begin
      Result := FlowHeight(AId);
    end);
end;

procedure TAtlasWelcomeFlowTests.WideSectionStartsBelowBothColumns;
var
  mItems: TArray<TAtlasWelcomePlaced>;
  mWide, mRight: TAtlasWelcomePlaced;
begin
  Assert.AreEqual(188, TAtlasWelcomeFlow.ColumnWidth(2, cClientWidth, cGap, cMinWidth));
  mItems := Placed;
  Assert.AreEqual(3, Integer(Length(mItems)));
  mRight := mItems[TAtlasWelcomeFlow.IndexOf(mItems, 'b')];
  Assert.AreEqual(212, mRight.Left);
  Assert.AreEqual(cGap, mRight.Top);
  mWide := mItems[TAtlasWelcomeFlow.IndexOf(mItems, 'w')];
  Assert.AreEqual(2, mWide.Span);
  Assert.AreEqual(cGap + 100 + cGap, mWide.Top, 'unter dem tieferen Ende beider Spalten');
  Assert.AreEqual(2 * 188 + cGap, mWide.Width);
  Assert.AreEqual(-1, TAtlasWelcomeFlow.IndexOf(mItems, 'x'));
  // Die Spalte mit dem höchsten Ende (ohne w): rechts.
  Assert.AreEqual(1, TAtlasWelcomeFlow.ShortestColumn(FlowCells, Copy(mItems, 0, 2), cGap));
end;

procedure TAtlasWelcomeFlowTests.DropTargetAndInsertLine;
var
  mItems: TArray<TAtlasWelcomePlaced>;
  mArea: TAtlasWelcomeArea;
  mDrop: TAtlasWelcomeDrop;
  mLine: TAtlasWelcomeInsertLine;
begin
  mItems := Placed;
  mArea := TAtlasWelcomeArea.Create(cClientWidth, cGap, cMinWidth);
  // Über der Mitte von b in der rechten Spalte: davor.
  mDrop := TAtlasWelcomeFlow.DropTarget(FlowCells, mItems, mArea, 250, 20, 'a');
  Assert.AreEqual(1, mDrop.Column);
  Assert.AreEqual('b', mDrop.Before);
  // Darunter: ans Ende.
  mDrop := TAtlasWelcomeFlow.DropTarget(FlowCells, mItems, mArea, 250, 200, 'a');
  Assert.AreEqual('', mDrop.Before);
  // Der gezogene Bereich selbst zählt nicht.
  mDrop := TAtlasWelcomeFlow.DropTarget(FlowCells, mItems, mArea, 20, 20, 'a');
  Assert.AreEqual(0, mDrop.Column);
  Assert.AreEqual('w', mDrop.Before);
  mLine := TAtlasWelcomeFlow.InsertLine(FlowCells, mItems, mArea, 1, 'b');
  Assert.AreEqual(212, mLine.Left);
  Assert.AreEqual(cGap - cGap div 2, mLine.Top);
  Assert.AreEqual(188, mLine.Width);
  mLine := TAtlasWelcomeFlow.InsertLine(FlowCells, mItems, mArea, 0, '');
  Assert.AreEqual(cGap + 100 + cGap + 40 + cGap div 2, mLine.Top, 'unter dem letzten Bereich');
end;

procedure TAtlasWelcomeFlowTests.FitsColumnsToWidth;
begin
  Assert.AreEqual(2, TAtlasWelcomeFlow.FitColumns(3, 300, cGap, cMinWidth));
  Assert.AreEqual(1, TAtlasWelcomeFlow.FitColumns(3, 100, cGap, cMinWidth));
  Assert.AreEqual(3, TAtlasWelcomeFlow.FitColumns(3, 1000, cGap, cMinWidth));
  Assert.AreEqual(0, TAtlasWelcomeFlow.ColumnAt(5, 2, cClientWidth, cGap, cMinWidth));
  Assert.AreEqual(1, TAtlasWelcomeFlow.ColumnAt(250, 2, cClientWidth, cGap, cMinWidth));
  Assert.AreEqual(1, TAtlasWelcomeFlow.ColumnAt(5000, 2, cClientWidth, cGap, cMinWidth));
  Assert.AreEqual(212, TAtlasWelcomeFlow.ColumnLeft(1, 2, cClientWidth, cGap, cMinWidth));
end;

{ TAtlasWelcomeLayoutsTests }

procedure TAtlasWelcomeLayoutsTests.DefaultIsStoredEmpty;
var
  mLayouts: TAtlasWelcomeLayouts;
begin
  mLayouts := TAtlasWelcomeLayouts.Defaults;
  Assert.IsTrue(mLayouts.IsDefault);
  Assert.AreEqual('', mLayouts.ToJson);
  Assert.AreEqual(TAtlasWelcomeLayout.cDefaultName, mLayouts.ActiveName);
  mLayouts := TAtlasWelcomeLayouts.FromJson('', 'gibt es nicht');
  Assert.AreEqual(1, Integer(Length(mLayouts.Items)));
  Assert.AreEqual(0, mLayouts.Active);
  // Sichtbarkeit steht in den Einstellungen und zählt nicht als Änderung.
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.WithVisible(TAtlasWelcomeIds.cTests, False));
  Assert.IsTrue(mLayouts.IsDefault);
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.WithColumns(3));
  Assert.IsFalse(mLayouts.IsDefault);
end;

procedure TAtlasWelcomeLayoutsTests.AddRenameDeleteAndActivate;
var
  mLayouts, mChanged, mNext: TAtlasWelcomeLayouts;
begin
  Assert.IsTrue(TAtlasWelcomeLayouts.Defaults.Added('Arbeit', mLayouts));
  Assert.AreEqual('Standard,Arbeit', Joined(mLayouts.Names));
  Assert.AreEqual('Arbeit', mLayouts.ActiveName, 'das neue Layout ist aktiv');
  Assert.IsFalse(mLayouts.Added('arbeit', mChanged), 'Namen ohne Rücksicht auf Groß- und Kleinschreibung');
  Assert.IsFalse(mLayouts.Added('  ', mChanged));
  Assert.IsTrue(Step(mLayouts.Added(' Präsentation ', mNext), mLayouts, mNext));
  Assert.AreEqual('Präsentation', mLayouts.ActiveName);
  Assert.IsTrue(Step(mLayouts.Renamed('Vortrag', mNext), mLayouts, mNext));
  Assert.AreEqual('Standard,Arbeit,Vortrag', Joined(mLayouts.Names));
  Assert.IsFalse(mLayouts.Renamed('Standard', mChanged));
  Assert.IsTrue(mLayouts.Renamed('VORTRAG', mChanged), 'nur die Schreibung ändern');
  Assert.IsTrue(mLayouts.Activated('arbeit', mChanged));
  Assert.AreEqual(1, mChanged.Active);
  Assert.IsFalse(mLayouts.Activated('Fehlt', mChanged));
  Assert.IsTrue(Step(mLayouts.Deleted(mNext), mLayouts, mNext));
  Assert.AreEqual('Standard,Arbeit', Joined(mLayouts.Names));
  Assert.AreEqual('Arbeit', mLayouts.ActiveName, 'danach das vorige');
  Assert.IsTrue(Step(mLayouts.Activated('Standard', mNext), mLayouts, mNext));
  Assert.IsTrue(Step(mLayouts.Deleted(mNext), mLayouts, mNext));
  Assert.AreEqual('Arbeit', mLayouts.ActiveName);
  Assert.IsFalse(mLayouts.Deleted(mChanged), 'das letzte Layout bleibt');
end;

procedure TAtlasWelcomeLayoutsTests.TwoLayoutsRoundTrip;
var
  mLayouts, mLoaded, mNext: TAtlasWelcomeLayouts;
begin
  // Akzeptanz: zwei Layouts „Arbeit“ und „Präsentation“.
  mLayouts := TAtlasWelcomeLayouts.Defaults;
  Assert.IsTrue(Step(mLayouts.Renamed('Arbeit', mNext), mLayouts, mNext));
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.MovedTo(TAtlasWelcomeIds.cState, 0, TAtlasWelcomeIds.cContinue));
  Assert.IsTrue(Step(mLayouts.Added('Präsentation', mNext), mLayouts, mNext));
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.WithColumns(1).WithVisible(TAtlasWelcomeIds.cTests, False));
  Assert.AreEqual('Präsentation', mLayouts.ActiveName, 'WithCurrent behält den Namen');
  mLoaded := TAtlasWelcomeLayouts.FromJson(mLayouts.ToJson, 'präsentation');
  Assert.AreEqual('Arbeit,Präsentation', Joined(mLoaded.Names));
  Assert.AreEqual(1, mLoaded.Active);
  Assert.IsTrue(TAtlasWelcomeLayout.Same(mLayouts.Items[0], mLoaded.Items[0]));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(mLayouts.Items[1], mLoaded.Items[1]));
  Assert.AreEqual(1, mLoaded.Current.Columns);
end;

procedure TAtlasWelcomeLayoutsTests.InvalidEntriesAreDropped;
var
  mLayouts: TAtlasWelcomeLayouts;
begin
  mLayouts := TAtlasWelcomeLayouts.FromJson('[{"name":"A","slots":[{"id":"atlas.state","column":1}]},' +
    '{"name":"a","slots":[{"id":"atlas.news"}]},5,{"name":" ","slots":[]},{"name":"B"}]', 'B');
  Assert.AreEqual('A', Joined(mLayouts.Names));
  Assert.AreEqual(0, mLayouts.Active, 'unbekanntes aktives Layout: das erste');
  mLayouts := TAtlasWelcomeLayouts.FromJson('[]', '');
  Assert.IsTrue(mLayouts.IsDefault);
  mLayouts := TAtlasWelcomeLayouts.FromJson('{"name":"A"}', '');
  Assert.IsTrue(mLayouts.IsDefault);
  mLayouts := TAtlasWelcomeLayouts.FromJson('kein JSON', 'A');
  Assert.IsTrue(mLayouts.IsDefault);
end;

procedure TAtlasWelcomeLayoutsTests.UniqueNameCounts;
var
  mLayouts, mNext: TAtlasWelcomeLayouts;
begin
  mLayouts := TAtlasWelcomeLayouts.Defaults;
  Assert.AreEqual('Arbeit', mLayouts.UniqueName('Arbeit'));
  Assert.AreEqual('Standard 2', mLayouts.UniqueName('Standard'));
  Assert.IsTrue(Step(mLayouts.Added('Standard 2', mNext), mLayouts, mNext));
  Assert.AreEqual('standard 3', mLayouts.UniqueName('standard'));
  Assert.IsFalse(TAtlasWelcomeLayouts.ValidName(' '));
end;

{ TAtlasWelcomeCustomizingTests }

procedure TAtlasWelcomeCustomizingTests.CatalogSettingsExist;
var
  mItem: TAtlasWelcomeCatalogItem;
  mOff, mBack: TAtlasPluginSettings;
  mSlot: TAtlasWelcomeSlot;
begin
  // Jeder Katalogbereich hat eine echte Einstellung: Aus und wieder An kommen in den Einstellungen an.
  for mItem in TAtlasWelcomeCustomizing.Catalog do
  begin
    mOff := TAtlasWelcomeCustomizing.WithSection(TAtlasPluginSettings.Defaults, mItem.Id, False);
    Assert.IsFalse(TAtlasWelcomeCustomizing.IsOn(mOff, mItem.Id), mItem.Setting);
    mBack := TAtlasWelcomeCustomizing.WithSection(mOff, mItem.Id, True);
    Assert.IsTrue(TAtlasWelcomeCustomizing.IsOn(mBack, mItem.Id), mItem.Setting);
  end;
  // Alle Bereiche des Atlas-Layouts stehen im Katalog („Bereich hinzufügen“ listet sie).
  for mSlot in TAtlasWelcomeLayout.Atlas.Slots do
  begin
    Assert.IsTrue(TAtlasWelcomeCustomizing.InCatalog(mSlot.Id), mSlot.Id);
  end;
  Assert.IsFalse(TAtlasWelcomeCustomizing.InCatalog(TAtlasWelcomeIds.cHeader));
  Assert.AreEqual('WelcomePageTests', TAtlasWelcomeCustomizing.SettingOf(TAtlasWelcomeIds.cTests));
  Assert.IsTrue(TAtlasWelcomeCustomizing.IsOn(TAtlasPluginSettings.Defaults, 'plugin.fremd'), 'ohne Schalter');
end;

procedure TAtlasWelcomeCustomizingTests.EyeTurnsTheSettingOff;
var
  mSettings: TAtlasPluginSettings;
begin
  // Akzeptanz: das Auge an „Testergebnisse“ setzt welcomePage.tests aus; Einschalten blendet wieder ein.
  mSettings := TAtlasWelcomeCustomizing.WithSection(TAtlasPluginSettings.Defaults, TAtlasWelcomeIds.cTests, False);
  Assert.IsFalse(mSettings.WelcomePageTests);
  Assert.AreEqual(TAtlasWelcomeIds.cTests, Joined(TAtlasWelcomeCustomizing.Hidden(mSettings,
    [TAtlasWelcomeIds.cState, TAtlasWelcomeIds.cTests, 'plugin.fremd'])));
  mSettings.WelcomePageTests := True;
  Assert.AreEqual('', Joined(TAtlasWelcomeCustomizing.Hidden(mSettings, [TAtlasWelcomeIds.cTests])));
  // „Neu in Atlas“ ist eine Auswahl: aus = off, an = afterUpdate.
  mSettings := TAtlasWelcomeCustomizing.WithSection(mSettings, TAtlasWelcomeIds.cNews, False);
  Assert.AreEqual('off', mSettings.WelcomePageWhatsNew);
  mSettings := TAtlasWelcomeCustomizing.WithSection(mSettings, TAtlasWelcomeIds.cNews, True);
  Assert.AreEqual('afterUpdate', mSettings.WelcomePageWhatsNew);
  mSettings.WelcomePageWhatsNew := 'always';
  mSettings := TAtlasWelcomeCustomizing.WithSection(mSettings, TAtlasWelcomeIds.cNews, True);
  Assert.AreEqual('always', mSettings.WelcomePageWhatsNew, 'schon an: unverändert');
end;

procedure TAtlasWelcomeCustomizingTests.LoadReadsVisibilityAndColumns;
var
  mSettings: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
  mSlot: TAtlasWelcomeSlot;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.WelcomePageTests := False;
  mSettings.WelcomePageColumns := 3;
  mLayouts := TAtlasWelcomeCustomizing.Load(mSettings);
  Assert.AreEqual(3, mLayouts.Current.Columns);
  Assert.IsTrue(mLayouts.Current.SlotOf(TAtlasWelcomeIds.cTests, mSlot));
  Assert.IsFalse(mSlot.Visible);
  Assert.IsTrue(mLayouts.Current.SlotOf(TAtlasWelcomeIds.cState, mSlot));
  Assert.IsTrue(mSlot.Visible);
end;

procedure TAtlasWelcomeCustomizingTests.StoredWritesOnlyChanges;
var
  mSettings: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.WelcomePageTests := False;
  mSettings := TAtlasWelcomeCustomizing.Stored(mSettings, TAtlasWelcomeCustomizing.Load(mSettings));
  Assert.AreEqual('', mSettings.WelcomePageLayouts, 'Ausblenden allein ist kein eigenes Layout');
  Assert.AreEqual('Standard', mSettings.WelcomePageActiveLayout);
  mLayouts := TAtlasWelcomeCustomizing.Load(mSettings);
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.MovedTo(TAtlasWelcomeIds.cState, 0, TAtlasWelcomeIds.cContinue));
  mSettings := TAtlasWelcomeCustomizing.Stored(mSettings, mLayouts);
  Assert.AreNotEqual('', mSettings.WelcomePageLayouts);
  // Nach dem Neustart: die Kachel steht links oben.
  Assert.AreEqual(TAtlasWelcomeIds.cState,
    TAtlasWelcomeCustomizing.Load(mSettings).Current.Arrange(AtlasSections, 2)[0][0]);
end;

procedure TAtlasWelcomeCustomizingTests.SwitchRemembersVisibility;
var
  mSettings: TAtlasPluginSettings;
  mLayouts, mNext: TAtlasWelcomeLayouts;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mLayouts := TAtlasWelcomeCustomizing.Load(mSettings);
  Assert.IsTrue(Step(mLayouts.Renamed('Arbeit', mNext), mLayouts, mNext));
  Assert.IsTrue(Step(mLayouts.Added('Präsentation', mNext), mLayouts, mNext));
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.WithVisible(TAtlasWelcomeIds.cTests, False).WithColumns(1));
  mSettings := TAtlasWelcomeCustomizing.Applied(mSettings, mLayouts);
  Assert.IsFalse(mSettings.WelcomePageTests);
  Assert.AreEqual('Präsentation', mSettings.WelcomePageActiveLayout);
  Assert.AreEqual(1, mSettings.WelcomePageColumns);
  mSettings := TAtlasWelcomeCustomizing.Switched(mSettings, 'Arbeit');
  Assert.AreEqual('Arbeit', mSettings.WelcomePageActiveLayout);
  Assert.IsTrue(mSettings.WelcomePageTests);
  Assert.AreEqual(2, mSettings.WelcomePageColumns);
  // In „Arbeit“ ausgeblendet: gilt nur dort.
  mSettings.WelcomePageHelp := False;
  mSettings := TAtlasWelcomeCustomizing.Switched(mSettings, 'Präsentation');
  Assert.IsFalse(mSettings.WelcomePageTests);
  Assert.IsTrue(mSettings.WelcomePageHelp);
  Assert.AreEqual(1, mSettings.WelcomePageColumns);
  mSettings := TAtlasWelcomeCustomizing.Switched(mSettings, 'Arbeit');
  Assert.IsFalse(mSettings.WelcomePageHelp);
  Assert.AreEqual('Arbeit', TAtlasWelcomeCustomizing.Switched(mSettings, 'Fehlt').WelcomePageActiveLayout);
end;

procedure TAtlasWelcomeCustomizingTests.ResetRestoresAtlasLayout;
var
  mSettings: TAtlasPluginSettings;
  mLayouts, mNext: TAtlasWelcomeLayouts;
  mExpected: TAtlasWelcomeLayout;
begin
  // Akzeptanz: „Zurücksetzen“ stellt das Atlas-Layout her; ausgeblendete Bereiche bleiben aus.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.WelcomePageTests := False;
  mLayouts := TAtlasWelcomeCustomizing.Load(mSettings);
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.MovedTo(TAtlasWelcomeIds.cState, 0, '').WithWidth(
    TAtlasWelcomeIds.cNews, 2).WithColumns(3));
  mSettings := TAtlasWelcomeCustomizing.Stored(mSettings, mLayouts);
  Assert.AreEqual(3, mSettings.WelcomePageColumns);
  mSettings := TAtlasWelcomeCustomizing.Reset(mSettings);
  Assert.AreEqual('', mSettings.WelcomePageLayouts, 'ein Layout wie Atlas: Vorgabe');
  Assert.AreEqual(2, mSettings.WelcomePageColumns);
  Assert.IsFalse(mSettings.WelcomePageTests);
  // Gleich der Vorgabe mit denselben Einstellungen (Sichtbarkeit aus den Schaltern).
  mExpected := TAtlasWelcomeCustomizing.Load(mSettings).Current;
  Assert.AreEqual(TAtlasWelcomeLayout.Atlas.ToJson, AllVisible(mExpected).ToJson);
  Assert.IsFalse(mExpected.Slots[mExpected.IndexOf(TAtlasWelcomeIds.cTests)].Visible);
  // Mit zwei Layouts: nur das aktive, Name bleibt.
  mLayouts := TAtlasWelcomeCustomizing.Load(mSettings);
  Assert.IsTrue(Step(mLayouts.Added('Präsentation', mNext), mLayouts, mNext));
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.MovedTo(TAtlasWelcomeIds.cHelp, 0, ''));
  mSettings := TAtlasWelcomeCustomizing.Reset(TAtlasWelcomeCustomizing.Stored(mSettings, mLayouts));
  mLayouts := TAtlasWelcomeCustomizing.Load(mSettings);
  Assert.AreEqual('Standard,Präsentation', Joined(mLayouts.Names));
  Assert.AreEqual('Präsentation', mLayouts.ActiveName);
  Assert.AreEqual(1, mLayouts.Current.Slots[mLayouts.Current.IndexOf(TAtlasWelcomeIds.cHelp)].Column);
end;

procedure TAtlasWelcomeCustomizingTests.AdoptsNewSectionsOnlyWhenStored;
var
  mSettings, mAdopted: TAtlasPluginSettings;
  mLayout: TAtlasWelcomeLayout;
  mLayouts: TAtlasWelcomeLayouts;
  mAdded: TArray<string>;
  mIndex: Integer;
begin
  // Vorgabe: kennt alle Bereiche dieser Version, nichts zu speichern.
  mSettings := TAtlasPluginSettings.Defaults;
  mAdopted := TAtlasWelcomeCustomizing.Adopted(mSettings, [TAtlasWelcomeIds.cIssues, 'plugin.neu'], nil, mAdded);
  Assert.AreEqual(0, Integer(Length(mAdded)));
  Assert.AreEqual('', mAdopted.WelcomePageLayouts);
  // Ein gespeichertes Layout einer früheren Version ohne „Meine Issues“ und „Hilfe“.
  mLayout := TAtlasWelcomeLayout.Atlas.MovedTo(TAtlasWelcomeIds.cState, 0, '');
  for mIndex := High(mLayout.Slots) downto 0 do
  begin
    if (mLayout.Slots[mIndex].Id = TAtlasWelcomeIds.cIssues) or (mLayout.Slots[mIndex].Id = TAtlasWelcomeIds.cHelp) then
    begin
      Delete(mLayout.Slots, mIndex, 1);
    end;
  end;
  mLayouts.Items := [mLayout];
  mLayouts.Active := 0;
  mSettings := TAtlasWelcomeCustomizing.Stored(mSettings, mLayouts);
  mAdopted := TAtlasWelcomeCustomizing.Adopted(mSettings, [TAtlasWelcomeIds.cHeader, TAtlasWelcomeIds.cBoard,
    TAtlasWelcomeIds.cSearch, TAtlasWelcomeIds.cState, TAtlasWelcomeIds.cIssues, TAtlasWelcomeIds.cHelp], nil, mAdded);
  Assert.AreEqual('atlas.issues,atlas.help', Joined(mAdded));
  mLayout := TAtlasWelcomeCustomizing.Load(mAdopted).Current;
  Assert.IsTrue(mLayout.IndexOf(TAtlasWelcomeIds.cIssues) >= 0);
  Assert.AreEqual(-1, mLayout.IndexOf(TAtlasWelcomeIds.cHeader), 'Kopf, Tafel und Suche haben feste Plätze');
  // Beim nächsten Start ist nichts mehr neu.
  TAtlasWelcomeCustomizing.Adopted(mAdopted, [TAtlasWelcomeIds.cIssues, TAtlasWelcomeIds.cHelp], nil, mAdded);
  Assert.AreEqual(0, Integer(Length(mAdded)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeArrangeTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeFlowTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeLayoutsTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeCustomizingTests);

end.
