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
  Atlas.Core.Settings.History,
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
  Slot: TAtlasWelcomeSlot;
  Column: TAtlasWelcomeColumn;
begin
  Result := nil;
  for Slot in TAtlasWelcomeLayout.Atlas.Slots do
  begin
    Column := TAtlasWelcomeColumn.Left;
    if Slot.Column > 0 then
      Column := TAtlasWelcomeColumn.Right;
    Result := Result + [Section(Slot.Id, Column)];
  end;
end;

function Joined(const AIds: TArray<string>): string;
var
  Id: string;
begin
  Result := '';
  for Id in AIds do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Id;
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
    ATarget := ANext;
end;

function AllVisible(const ALayout: TAtlasWelcomeLayout): TAtlasWelcomeLayout;
var
  Index: Integer;
begin
  Result := ALayout;
  Result.Slots := Copy(ALayout.Slots);
  for Index := 0 to High(Result.Slots) do
    Result.Slots[Index].Visible := True;
end;

{ TAtlasWelcomeArrangeTests }

procedure TAtlasWelcomeArrangeTests.DragMovesStateTileTopLeft;
var
  Moved: TAtlasWelcomeLayout;
  Columns: TArray<TArray<string>>;
begin
  // Akzeptanz: Zustandskachel per Ziehen nach links oben.
  Moved := TAtlasWelcomeLayout.Atlas.MovedTo(TAtlasWelcomeIds.State, 0, TAtlasWelcomeIds.Continue);
  Columns := Moved.Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.state,atlas.continue,atlas.projects,atlas.history,atlas.tests', Joined(Columns[0]));
  Assert.AreEqual('atlas.unsaved,atlas.news,atlas.discover,atlas.setup,atlas.issues,atlas.sprint,atlas.help',
    Joined(Columns[1]));
  Assert.AreEqual(Integer(Length(TAtlasWelcomeLayout.Atlas.Slots)), Integer(Length(Moved.Slots)));
  // Ans Ende einer Spalte; unbekanntes ABefore heißt ebenso ans Ende.
  Columns := Moved.MovedTo(TAtlasWelcomeIds.State, 1, '').Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.unsaved,atlas.news,atlas.discover,atlas.setup,atlas.issues,atlas.sprint,atlas.help,' +
    'atlas.state', Joined(Columns[1]));
  Columns := Moved.MovedTo(TAtlasWelcomeIds.State, 1, 'gibt.es.nicht').Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.state', Columns[1][High(Columns[1])]);
  // Gleiche Stelle: unverändert.
  Assert.IsTrue(TAtlasWelcomeLayout.Same(Moved, Moved.MovedTo(TAtlasWelcomeIds.State, 0, TAtlasWelcomeIds.Continue)));
end;

procedure TAtlasWelcomeArrangeTests.DragUnknownSectionAddsSlot;
var
  Moved: TAtlasWelcomeLayout;
  Slot: TAtlasWelcomeSlot;
begin
  Moved := TAtlasWelcomeLayout.Atlas.MovedTo('plugin.extra', 1, TAtlasWelcomeIds.News);
  Assert.IsTrue(Moved.SlotOf('plugin.extra', Slot));
  Assert.AreEqual(1, Slot.Column);
  Assert.AreEqual(1, Slot.Width);
  Assert.IsTrue(Slot.Visible);
  Assert.AreEqual(Moved.IndexOf(TAtlasWelcomeIds.News) - 1, Moved.IndexOf('plugin.extra'));
end;

procedure TAtlasWelcomeArrangeTests.CtrlArrowsMoveStepByStep;
var
  Layout, Moved: TAtlasWelcomeLayout;
  Columns: TArray<TArray<string>>;
begin
  // Akzeptanz: dasselbe nur mit Tastatur (Strg+Pfeil links bringt die Kachel nach links oben).
  Layout := TAtlasWelcomeLayout.Atlas;
  Assert.IsTrue(Layout.MovedBy(TAtlasWelcomeIds.State, TAtlasWelcomeMove.Left, AtlasSections, Moved));
  Columns := Moved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.State, Columns[0][0]);
  // Strg+Pfeil runter: hinter den nächsten Bereich.
  Layout := Moved;
  Assert.IsTrue(Layout.MovedBy(TAtlasWelcomeIds.State, TAtlasWelcomeMove.Down, AtlasSections, Moved));
  Columns := Moved.Arrange(AtlasSections, 2);
  Assert.AreEqual('atlas.continue,atlas.state,atlas.projects', Joined(Copy(Columns[0], 0, 3)));
  // Strg+Pfeil hoch: wieder davor.
  Layout := Moved;
  Assert.IsTrue(Layout.MovedBy(TAtlasWelcomeIds.State, TAtlasWelcomeMove.Up, AtlasSections, Moved));
  Columns := Moved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.State, Columns[0][0]);
  // Strg+Pfeil rechts: in derselben Zeile der rechten Spalte.
  Layout := Moved;
  Assert.IsTrue(Layout.MovedBy(TAtlasWelcomeIds.State, TAtlasWelcomeMove.Right, AtlasSections, Moved));
  Columns := Moved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.State, Columns[1][0]);
  // Runter bis ans Ende der Spalte: die vorletzte Kachel (Sprint, #1277) hinter die Hilfe.
  Layout := TAtlasWelcomeLayout.Atlas;
  Assert.IsTrue(Layout.MovedBy(TAtlasWelcomeIds.Sprint, TAtlasWelcomeMove.Down, AtlasSections, Moved));
  Columns := Moved.Arrange(AtlasSections, 2);
  Assert.AreEqual(TAtlasWelcomeIds.Sprint, Columns[1][High(Columns[1])]);
end;

procedure TAtlasWelcomeArrangeTests.CtrlArrowsStopAtTheEdge;
var
  Layout, Moved: TAtlasWelcomeLayout;
begin
  Layout := TAtlasWelcomeLayout.Atlas;
  Assert.IsFalse(Layout.MovedBy(TAtlasWelcomeIds.Continue, TAtlasWelcomeMove.Up, AtlasSections, Moved));
  Assert.IsFalse(Layout.MovedBy(TAtlasWelcomeIds.Continue, TAtlasWelcomeMove.Left, AtlasSections, Moved));
  Assert.IsFalse(Layout.MovedBy(TAtlasWelcomeIds.State, TAtlasWelcomeMove.Right, AtlasSections, Moved));
  Assert.IsFalse(Layout.MovedBy(TAtlasWelcomeIds.Help, TAtlasWelcomeMove.Down, AtlasSections, Moved));
  // Ein Bereich, der nicht zu sehen ist, bewegt sich nicht.
  Assert.IsFalse(Layout.MovedBy(TAtlasWelcomeIds.State, TAtlasWelcomeMove.Down,
    [Section(TAtlasWelcomeIds.Continue, TAtlasWelcomeColumn.Left)], Moved));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(Layout, Moved));
end;

procedure TAtlasWelcomeArrangeTests.WidthIsClampedAndSpansColumns;
var
  Wide: TAtlasWelcomeLayout;
  Cells: TAtlasWelcomeCells;
  Item: TAtlasWelcomeCell;
  Span: Integer;
begin
  Wide := TAtlasWelcomeLayout.Atlas.WithWidth(TAtlasWelcomeIds.Projects, 5);
  Assert.AreEqual(2, Wide.WidthOf(TAtlasWelcomeIds.Projects));
  Assert.AreEqual(1, Wide.WithWidth(TAtlasWelcomeIds.Projects, 0).WidthOf(TAtlasWelcomeIds.Projects));
  Assert.AreEqual(1, Wide.WidthOf('gibt.es.nicht'));
  Span := 0;
  Cells := Wide.Cells(AtlasSections, 2);
  for Item in Cells[0] do
    if Item.Id = TAtlasWelcomeIds.Projects then
      Span := Item.Span;
  Assert.AreEqual(2, Span);
  // Eine Spalte: höchstens so breit wie die Fläche.
  Cells := Wide.Cells(AtlasSections, 1);
  for Item in Cells[0] do
    if Item.Id = TAtlasWelcomeIds.Projects then
      Span := Item.Span;
  Assert.AreEqual(1, Span);
end;

procedure TAtlasWelcomeArrangeTests.HidingKeepsThePlace;
var
  Hidden: TAtlasWelcomeLayout;
  Slot: TAtlasWelcomeSlot;
begin
  Hidden := TAtlasWelcomeLayout.Atlas.WithVisible(TAtlasWelcomeIds.Tests, False);
  Assert.IsTrue(Hidden.SlotOf(TAtlasWelcomeIds.Tests, Slot));
  Assert.IsFalse(Slot.Visible);
  Assert.AreEqual(0, Slot.Column);
  Assert.AreEqual(TAtlasWelcomeLayout.Atlas.IndexOf(TAtlasWelcomeIds.Tests), Hidden.IndexOf(TAtlasWelcomeIds.Tests));
  Assert.IsTrue(Hidden.WithVisible(TAtlasWelcomeIds.Tests, True).SlotOf(TAtlasWelcomeIds.Tests, Slot));
  Assert.IsTrue(Slot.Visible);
end;

procedure TAtlasWelcomeArrangeTests.ColumnsKeepTheSlots;
var
  Layout: TAtlasWelcomeLayout;
  Columns: TArray<TArray<string>>;
begin
  Layout := TAtlasWelcomeLayout.Atlas.MovedTo(TAtlasWelcomeIds.Help, 2, '').WithColumns(3);
  Assert.AreEqual(3, Layout.Columns);
  Columns := Layout.Arrange(AtlasSections, Layout.Columns);
  Assert.AreEqual('atlas.help', Joined(Columns[2]));
  // Weniger Spalten: Hilfe steht am Ende der letzten, die Plätze bleiben.
  Layout := Layout.WithColumns(2);
  Columns := Layout.Arrange(AtlasSections, Layout.Columns);
  Assert.AreEqual('atlas.help', Columns[1][High(Columns[1])]);
  Assert.AreEqual('atlas.help', Joined(Layout.WithColumns(3).Arrange(AtlasSections, 3)[2]), 'zurück an ihrem Platz');
  Assert.AreEqual(TAtlasWelcomeLayout.MaxColumns, Layout.WithColumns(9).Columns);
  Assert.AreEqual(TAtlasWelcomeLayout.MinColumns, Layout.WithColumns(0).Columns);
end;

procedure TAtlasWelcomeArrangeTests.NewSectionsGoToRoomiestColumn;
var
  Layout: TAtlasWelcomeLayout;
  Added: TArray<string>;
  Slot: TAtlasWelcomeSlot;
begin
  // Links stehen vier Plätze, rechts sieben: jeder Platz zählt 1.
  Layout := TAtlasWelcomeLayout.Atlas.Adopted([TAtlasWelcomeIds.State, 'plugin.neu'], nil, Added);
  Assert.AreEqual('plugin.neu', Joined(Added));
  Assert.IsTrue(Layout.SlotOf('plugin.neu', Slot));
  Assert.AreEqual(0, Slot.Column);
  Assert.AreEqual(Integer(High(Layout.Slots)), Layout.IndexOf('plugin.neu'));
  // Mit Gewicht (Höhe): links ist die Spalte voller.
  Layout := TAtlasWelcomeLayout.Atlas.Adopted(['plugin.neu'],
    function(const AId: string): Integer
    begin
      Result := 10;
      if AId = TAtlasWelcomeIds.History then
        Result := 500;
    end, Added);
  Assert.IsTrue(Layout.SlotOf('plugin.neu', Slot));
  Assert.AreEqual(1, Slot.Column);
  // Bekannte Bereiche kommen nicht doppelt.
  TAtlasWelcomeLayout.Atlas.Adopted([TAtlasWelcomeIds.State], nil, Added);
  Assert.AreEqual(0, Integer(Length(Added)));
end;

procedure TAtlasWelcomeArrangeTests.JsonKeepsWidthAndVisibility;
var
  Layout, Loaded: TAtlasWelcomeLayout;
  Slot: TAtlasWelcomeSlot;
begin
  Layout := TAtlasWelcomeLayout.Atlas.WithWidth(TAtlasWelcomeIds.History, 2)
    .WithVisible(TAtlasWelcomeIds.Discover, False).MovedTo(TAtlasWelcomeIds.State, 0, '');
  Layout.Name := 'Präsentation';
  Assert.IsTrue(TAtlasWelcomeLayout.FromJson(Layout.ToJson, Loaded));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(Layout, Loaded));
  Assert.IsTrue(Loaded.SlotOf(TAtlasWelcomeIds.History, Slot));
  Assert.AreEqual(2, Slot.Width);
  Assert.IsTrue(Loaded.SlotOf(TAtlasWelcomeIds.Discover, Slot));
  Assert.IsFalse(Slot.Visible);
end;

{ TAtlasWelcomeFlowTests }

const
  ClientWidth = 412;
  Gap = 12;
  MinWidth = 120;

function FlowCells: TAtlasWelcomeCells;
begin
  // Links a und der zweispaltige w, rechts b.
  Result := [[Cell('a', 1), Cell('w', 2)], [Cell('b', 1)]];
end;

function FlowHeight(const AId: string; AWidth: Integer): Integer;
begin
  if AId = 'a' then
    Result := 100
  else if AId = 'b' then
    Result := 50
  else
    Result := 40;
end;

function Placed: TArray<TAtlasWelcomePlaced>;
begin
  Result := TAtlasWelcomeFlow.Place(FlowCells, ClientWidth, Gap, MinWidth,
    function(const AId: string; AWidth: Integer): Integer
    begin
      Result := FlowHeight(AId, AWidth);
    end);
end;

procedure TAtlasWelcomeFlowTests.WideSectionStartsBelowBothColumns;
var
  Items: TArray<TAtlasWelcomePlaced>;
  Wide, Right: TAtlasWelcomePlaced;
begin
  Assert.AreEqual(188, TAtlasWelcomeFlow.ColumnWidth(2, ClientWidth, Gap, MinWidth));
  Items := Placed;
  Assert.AreEqual(3, Integer(Length(Items)));
  Right := Items[TAtlasWelcomeFlow.IndexOf(Items, 'b')];
  Assert.AreEqual(212, Right.Left);
  Assert.AreEqual(Gap, Right.Top);
  Wide := Items[TAtlasWelcomeFlow.IndexOf(Items, 'w')];
  Assert.AreEqual(2, Wide.Span);
  Assert.AreEqual(Gap + 100 + Gap, Wide.Top, 'unter dem tieferen Ende beider Spalten');
  Assert.AreEqual(2 * 188 + Gap, Wide.Width);
  Assert.AreEqual(-1, TAtlasWelcomeFlow.IndexOf(Items, 'x'));
  // Die Spalte mit dem höchsten Ende (ohne w): rechts.
  Assert.AreEqual(1, TAtlasWelcomeFlow.ShortestColumn(FlowCells, Copy(Items, 0, 2), Gap));
end;

procedure TAtlasWelcomeFlowTests.DropTargetAndInsertLine;
var
  Items: TArray<TAtlasWelcomePlaced>;
  Column, Left, Top, Width: Integer;
  Before: string;
begin
  Items := Placed;
  // Über der Mitte von b in der rechten Spalte: davor.
  TAtlasWelcomeFlow.DropTarget(FlowCells, Items, ClientWidth, Gap, MinWidth, 250, 20, 'a', Column, Before);
  Assert.AreEqual(1, Column);
  Assert.AreEqual('b', Before);
  // Darunter: ans Ende.
  TAtlasWelcomeFlow.DropTarget(FlowCells, Items, ClientWidth, Gap, MinWidth, 250, 200, 'a', Column, Before);
  Assert.AreEqual('', Before);
  // Der gezogene Bereich selbst zählt nicht.
  TAtlasWelcomeFlow.DropTarget(FlowCells, Items, ClientWidth, Gap, MinWidth, 20, 20, 'a', Column, Before);
  Assert.AreEqual(0, Column);
  Assert.AreEqual('w', Before);
  TAtlasWelcomeFlow.InsertLine(FlowCells, Items, ClientWidth, Gap, MinWidth, 1, 'b', Left, Top, Width);
  Assert.AreEqual(212, Left);
  Assert.AreEqual(Gap - Gap div 2, Top);
  Assert.AreEqual(188, Width);
  TAtlasWelcomeFlow.InsertLine(FlowCells, Items, ClientWidth, Gap, MinWidth, 0, '', Left, Top, Width);
  Assert.AreEqual(Gap + 100 + Gap + 40 + Gap div 2, Top, 'unter dem letzten Bereich');
end;

procedure TAtlasWelcomeFlowTests.FitsColumnsToWidth;
begin
  Assert.AreEqual(2, TAtlasWelcomeFlow.FitColumns(3, 300, Gap, MinWidth));
  Assert.AreEqual(1, TAtlasWelcomeFlow.FitColumns(3, 100, Gap, MinWidth));
  Assert.AreEqual(3, TAtlasWelcomeFlow.FitColumns(3, 1000, Gap, MinWidth));
  Assert.AreEqual(0, TAtlasWelcomeFlow.ColumnAt(5, 2, ClientWidth, Gap, MinWidth));
  Assert.AreEqual(1, TAtlasWelcomeFlow.ColumnAt(250, 2, ClientWidth, Gap, MinWidth));
  Assert.AreEqual(1, TAtlasWelcomeFlow.ColumnAt(5000, 2, ClientWidth, Gap, MinWidth));
  Assert.AreEqual(212, TAtlasWelcomeFlow.ColumnLeft(1, 2, ClientWidth, Gap, MinWidth));
end;

{ TAtlasWelcomeLayoutsTests }

procedure TAtlasWelcomeLayoutsTests.DefaultIsStoredEmpty;
var
  Layouts: TAtlasWelcomeLayouts;
begin
  Layouts := TAtlasWelcomeLayouts.Defaults;
  Assert.IsTrue(Layouts.IsDefault);
  Assert.AreEqual('', Layouts.ToJson);
  Assert.AreEqual(TAtlasWelcomeLayout.DefaultName, Layouts.ActiveName);
  Layouts := TAtlasWelcomeLayouts.FromJson('', 'gibt es nicht');
  Assert.AreEqual(1, Integer(Length(Layouts.Items)));
  Assert.AreEqual(0, Layouts.Active);
  // Sichtbarkeit steht in den Einstellungen und zählt nicht als Änderung.
  Layouts := Layouts.WithCurrent(Layouts.Current.WithVisible(TAtlasWelcomeIds.Tests, False));
  Assert.IsTrue(Layouts.IsDefault);
  Layouts := Layouts.WithCurrent(Layouts.Current.WithColumns(3));
  Assert.IsFalse(Layouts.IsDefault);
end;

procedure TAtlasWelcomeLayoutsTests.AddRenameDeleteAndActivate;
var
  Layouts, Changed, Next: TAtlasWelcomeLayouts;
begin
  Assert.IsTrue(TAtlasWelcomeLayouts.Defaults.Added('Arbeit', Layouts));
  Assert.AreEqual('Standard,Arbeit', Joined(Layouts.Names));
  Assert.AreEqual('Arbeit', Layouts.ActiveName, 'das neue Layout ist aktiv');
  Assert.IsFalse(Layouts.Added('arbeit', Changed), 'Namen ohne Rücksicht auf Groß- und Kleinschreibung');
  Assert.IsFalse(Layouts.Added('  ', Changed));
  Assert.IsTrue(Step(Layouts.Added(' Präsentation ', Next), Layouts, Next));
  Assert.AreEqual('Präsentation', Layouts.ActiveName);
  Assert.IsTrue(Step(Layouts.Renamed('Vortrag', Next), Layouts, Next));
  Assert.AreEqual('Standard,Arbeit,Vortrag', Joined(Layouts.Names));
  Assert.IsFalse(Layouts.Renamed('Standard', Changed));
  Assert.IsTrue(Layouts.Renamed('VORTRAG', Changed), 'nur die Schreibung ändern');
  Assert.IsTrue(Layouts.Activated('arbeit', Changed));
  Assert.AreEqual(1, Changed.Active);
  Assert.IsFalse(Layouts.Activated('Fehlt', Changed));
  Assert.IsTrue(Step(Layouts.Deleted(Next), Layouts, Next));
  Assert.AreEqual('Standard,Arbeit', Joined(Layouts.Names));
  Assert.AreEqual('Arbeit', Layouts.ActiveName, 'danach das vorige');
  Assert.IsTrue(Step(Layouts.Activated('Standard', Next), Layouts, Next));
  Assert.IsTrue(Step(Layouts.Deleted(Next), Layouts, Next));
  Assert.AreEqual('Arbeit', Layouts.ActiveName);
  Assert.IsFalse(Layouts.Deleted(Changed), 'das letzte Layout bleibt');
end;

procedure TAtlasWelcomeLayoutsTests.TwoLayoutsRoundTrip;
var
  Layouts, Loaded, Next: TAtlasWelcomeLayouts;
begin
  // Akzeptanz: zwei Layouts „Arbeit“ und „Präsentation“.
  Layouts := TAtlasWelcomeLayouts.Defaults;
  Assert.IsTrue(Step(Layouts.Renamed('Arbeit', Next), Layouts, Next));
  Layouts := Layouts.WithCurrent(Layouts.Current.MovedTo(TAtlasWelcomeIds.State, 0, TAtlasWelcomeIds.Continue));
  Assert.IsTrue(Step(Layouts.Added('Präsentation', Next), Layouts, Next));
  Layouts := Layouts.WithCurrent(Layouts.Current.WithColumns(1).WithVisible(TAtlasWelcomeIds.Tests, False));
  Assert.AreEqual('Präsentation', Layouts.ActiveName, 'WithCurrent behält den Namen');
  Loaded := TAtlasWelcomeLayouts.FromJson(Layouts.ToJson, 'präsentation');
  Assert.AreEqual('Arbeit,Präsentation', Joined(Loaded.Names));
  Assert.AreEqual(1, Loaded.Active);
  Assert.IsTrue(TAtlasWelcomeLayout.Same(Layouts.Items[0], Loaded.Items[0]));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(Layouts.Items[1], Loaded.Items[1]));
  Assert.AreEqual(1, Loaded.Current.Columns);
end;

procedure TAtlasWelcomeLayoutsTests.InvalidEntriesAreDropped;
var
  Layouts: TAtlasWelcomeLayouts;
begin
  Layouts := TAtlasWelcomeLayouts.FromJson('[{"name":"A","slots":[{"id":"atlas.state","column":1}]},' +
    '{"name":"a","slots":[{"id":"atlas.news"}]},5,{"name":" ","slots":[]},{"name":"B"}]', 'B');
  Assert.AreEqual('A', Joined(Layouts.Names));
  Assert.AreEqual(0, Layouts.Active, 'unbekanntes aktives Layout: das erste');
  Layouts := TAtlasWelcomeLayouts.FromJson('[]', '');
  Assert.IsTrue(Layouts.IsDefault);
  Layouts := TAtlasWelcomeLayouts.FromJson('{"name":"A"}', '');
  Assert.IsTrue(Layouts.IsDefault);
  Layouts := TAtlasWelcomeLayouts.FromJson('kein JSON', 'A');
  Assert.IsTrue(Layouts.IsDefault);
end;

procedure TAtlasWelcomeLayoutsTests.UniqueNameCounts;
var
  Layouts, Next: TAtlasWelcomeLayouts;
begin
  Layouts := TAtlasWelcomeLayouts.Defaults;
  Assert.AreEqual('Arbeit', Layouts.UniqueName('Arbeit'));
  Assert.AreEqual('Standard 2', Layouts.UniqueName('Standard'));
  Assert.IsTrue(Step(Layouts.Added('Standard 2', Next), Layouts, Next));
  Assert.AreEqual('standard 3', Layouts.UniqueName('standard'));
  Assert.IsFalse(TAtlasWelcomeLayouts.ValidName(' '));
end;

{ TAtlasWelcomeCustomizingTests }

procedure TAtlasWelcomeCustomizingTests.CatalogSettingsExist;
var
  Item: TAtlasWelcomeCatalogItem;
  Off, Back: TAtlasPluginSettings;
  Slot: TAtlasWelcomeSlot;
begin
  // Jeder Katalogbereich hat eine echte Einstellung: Aus und wieder An kommen in den Einstellungen an.
  for Item in TAtlasWelcomeCustomizing.Catalog do
  begin
    Off := TAtlasWelcomeCustomizing.WithSection(TAtlasPluginSettings.Defaults, Item.Id, False);
    Assert.IsFalse(TAtlasWelcomeCustomizing.IsOn(Off, Item.Id), Item.Setting);
    Back := TAtlasWelcomeCustomizing.WithSection(Off, Item.Id, True);
    Assert.IsTrue(TAtlasWelcomeCustomizing.IsOn(Back, Item.Id), Item.Setting);
  end;
  // Alle Bereiche des Atlas-Layouts stehen im Katalog („Bereich hinzufügen“ listet sie).
  for Slot in TAtlasWelcomeLayout.Atlas.Slots do
    Assert.IsTrue(TAtlasWelcomeCustomizing.InCatalog(Slot.Id), Slot.Id);
  Assert.IsFalse(TAtlasWelcomeCustomizing.InCatalog(TAtlasWelcomeIds.Header));
  Assert.AreEqual('WelcomePageTests', TAtlasWelcomeCustomizing.SettingOf(TAtlasWelcomeIds.Tests));
  Assert.IsTrue(TAtlasWelcomeCustomizing.IsOn(TAtlasPluginSettings.Defaults, 'plugin.fremd'), 'ohne Schalter');
end;

procedure TAtlasWelcomeCustomizingTests.EyeTurnsTheSettingOff;
var
  Settings: TAtlasPluginSettings;
begin
  // Akzeptanz: das Auge an „Testergebnisse“ setzt welcomePage.tests aus; Einschalten blendet wieder ein.
  Settings := TAtlasWelcomeCustomizing.WithSection(TAtlasPluginSettings.Defaults, TAtlasWelcomeIds.Tests, False);
  Assert.IsFalse(Settings.WelcomePageTests);
  Assert.AreEqual(TAtlasWelcomeIds.Tests, Joined(TAtlasWelcomeCustomizing.Hidden(Settings,
    [TAtlasWelcomeIds.State, TAtlasWelcomeIds.Tests, 'plugin.fremd'])));
  Settings.WelcomePageTests := True;
  Assert.AreEqual('', Joined(TAtlasWelcomeCustomizing.Hidden(Settings, [TAtlasWelcomeIds.Tests])));
  // „Neu in Atlas“ ist eine Auswahl: aus = off, an = afterUpdate.
  Settings := TAtlasWelcomeCustomizing.WithSection(Settings, TAtlasWelcomeIds.News, False);
  Assert.AreEqual('off', Settings.WelcomePageWhatsNew);
  Settings := TAtlasWelcomeCustomizing.WithSection(Settings, TAtlasWelcomeIds.News, True);
  Assert.AreEqual('afterUpdate', Settings.WelcomePageWhatsNew);
  Settings.WelcomePageWhatsNew := 'always';
  Settings := TAtlasWelcomeCustomizing.WithSection(Settings, TAtlasWelcomeIds.News, True);
  Assert.AreEqual('always', Settings.WelcomePageWhatsNew, 'schon an: unverändert');
end;

procedure TAtlasWelcomeCustomizingTests.LoadReadsVisibilityAndColumns;
var
  Settings: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
  Slot: TAtlasWelcomeSlot;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.WelcomePageTests := False;
  Settings.WelcomePageColumns := 3;
  Layouts := TAtlasWelcomeCustomizing.Load(Settings);
  Assert.AreEqual(3, Layouts.Current.Columns);
  Assert.IsTrue(Layouts.Current.SlotOf(TAtlasWelcomeIds.Tests, Slot));
  Assert.IsFalse(Slot.Visible);
  Assert.IsTrue(Layouts.Current.SlotOf(TAtlasWelcomeIds.State, Slot));
  Assert.IsTrue(Slot.Visible);
end;

procedure TAtlasWelcomeCustomizingTests.StoredWritesOnlyChanges;
var
  Settings: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.WelcomePageTests := False;
  Settings := TAtlasWelcomeCustomizing.Stored(Settings, TAtlasWelcomeCustomizing.Load(Settings));
  Assert.AreEqual('', Settings.WelcomePageLayouts, 'Ausblenden allein ist kein eigenes Layout');
  Assert.AreEqual('Standard', Settings.WelcomePageActiveLayout);
  Layouts := TAtlasWelcomeCustomizing.Load(Settings);
  Layouts := Layouts.WithCurrent(Layouts.Current.MovedTo(TAtlasWelcomeIds.State, 0, TAtlasWelcomeIds.Continue));
  Settings := TAtlasWelcomeCustomizing.Stored(Settings, Layouts);
  Assert.AreNotEqual('', Settings.WelcomePageLayouts);
  // Nach dem Neustart: die Kachel steht links oben.
  Assert.AreEqual(TAtlasWelcomeIds.State,
    TAtlasWelcomeCustomizing.Load(Settings).Current.Arrange(AtlasSections, 2)[0][0]);
end;

procedure TAtlasWelcomeCustomizingTests.SwitchRemembersVisibility;
var
  Settings: TAtlasPluginSettings;
  Layouts, Next: TAtlasWelcomeLayouts;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Layouts := TAtlasWelcomeCustomizing.Load(Settings);
  Assert.IsTrue(Step(Layouts.Renamed('Arbeit', Next), Layouts, Next));
  Assert.IsTrue(Step(Layouts.Added('Präsentation', Next), Layouts, Next));
  Layouts := Layouts.WithCurrent(Layouts.Current.WithVisible(TAtlasWelcomeIds.Tests, False).WithColumns(1));
  Settings := TAtlasWelcomeCustomizing.Applied(Settings, Layouts);
  Assert.IsFalse(Settings.WelcomePageTests);
  Assert.AreEqual('Präsentation', Settings.WelcomePageActiveLayout);
  Assert.AreEqual(1, Settings.WelcomePageColumns);
  Settings := TAtlasWelcomeCustomizing.Switched(Settings, 'Arbeit');
  Assert.AreEqual('Arbeit', Settings.WelcomePageActiveLayout);
  Assert.IsTrue(Settings.WelcomePageTests);
  Assert.AreEqual(2, Settings.WelcomePageColumns);
  // In „Arbeit“ ausgeblendet: gilt nur dort.
  Settings.WelcomePageHelp := False;
  Settings := TAtlasWelcomeCustomizing.Switched(Settings, 'Präsentation');
  Assert.IsFalse(Settings.WelcomePageTests);
  Assert.IsTrue(Settings.WelcomePageHelp);
  Assert.AreEqual(1, Settings.WelcomePageColumns);
  Settings := TAtlasWelcomeCustomizing.Switched(Settings, 'Arbeit');
  Assert.IsFalse(Settings.WelcomePageHelp);
  Assert.AreEqual('Arbeit', TAtlasWelcomeCustomizing.Switched(Settings, 'Fehlt').WelcomePageActiveLayout);
end;

procedure TAtlasWelcomeCustomizingTests.ResetRestoresAtlasLayout;
var
  Settings: TAtlasPluginSettings;
  Layouts, Next: TAtlasWelcomeLayouts;
  Expected: TAtlasWelcomeLayout;
begin
  // Akzeptanz: „Zurücksetzen“ stellt das Atlas-Layout her; ausgeblendete Bereiche bleiben aus.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.WelcomePageTests := False;
  Layouts := TAtlasWelcomeCustomizing.Load(Settings);
  Layouts := Layouts.WithCurrent(Layouts.Current.MovedTo(TAtlasWelcomeIds.State, 0, '').WithWidth(
    TAtlasWelcomeIds.News, 2).WithColumns(3));
  Settings := TAtlasWelcomeCustomizing.Stored(Settings, Layouts);
  Assert.AreEqual(3, Settings.WelcomePageColumns);
  Settings := TAtlasWelcomeCustomizing.Reset(Settings);
  Assert.AreEqual('', Settings.WelcomePageLayouts, 'ein Layout wie Atlas: Vorgabe');
  Assert.AreEqual(2, Settings.WelcomePageColumns);
  Assert.IsFalse(Settings.WelcomePageTests);
  // Gleich der Vorgabe mit denselben Einstellungen (Sichtbarkeit aus den Schaltern).
  Expected := TAtlasWelcomeCustomizing.Load(Settings).Current;
  Assert.AreEqual(TAtlasWelcomeLayout.Atlas.ToJson, AllVisible(Expected).ToJson);
  Assert.IsFalse(Expected.Slots[Expected.IndexOf(TAtlasWelcomeIds.Tests)].Visible);
  // Mit zwei Layouts: nur das aktive, Name bleibt.
  Layouts := TAtlasWelcomeCustomizing.Load(Settings);
  Assert.IsTrue(Step(Layouts.Added('Präsentation', Next), Layouts, Next));
  Layouts := Layouts.WithCurrent(Layouts.Current.MovedTo(TAtlasWelcomeIds.Help, 0, ''));
  Settings := TAtlasWelcomeCustomizing.Reset(TAtlasWelcomeCustomizing.Stored(Settings, Layouts));
  Layouts := TAtlasWelcomeCustomizing.Load(Settings);
  Assert.AreEqual('Standard,Präsentation', Joined(Layouts.Names));
  Assert.AreEqual('Präsentation', Layouts.ActiveName);
  Assert.AreEqual(1, Layouts.Current.Slots[Layouts.Current.IndexOf(TAtlasWelcomeIds.Help)].Column);
end;

procedure TAtlasWelcomeCustomizingTests.AdoptsNewSectionsOnlyWhenStored;
var
  Settings, Adopted: TAtlasPluginSettings;
  Layout: TAtlasWelcomeLayout;
  Layouts: TAtlasWelcomeLayouts;
  Added: TArray<string>;
  Index: Integer;
begin
  // Vorgabe: kennt alle Bereiche dieser Version, nichts zu speichern.
  Settings := TAtlasPluginSettings.Defaults;
  Adopted := TAtlasWelcomeCustomizing.Adopted(Settings, [TAtlasWelcomeIds.Issues, 'plugin.neu'], nil, Added);
  Assert.AreEqual(0, Integer(Length(Added)));
  Assert.AreEqual('', Adopted.WelcomePageLayouts);
  // Ein gespeichertes Layout einer früheren Version ohne „Meine Issues“ und „Hilfe“.
  Layout := TAtlasWelcomeLayout.Atlas.MovedTo(TAtlasWelcomeIds.State, 0, '');
  for Index := High(Layout.Slots) downto 0 do
    if (Layout.Slots[Index].Id = TAtlasWelcomeIds.Issues) or (Layout.Slots[Index].Id = TAtlasWelcomeIds.Help) then
      Delete(Layout.Slots, Index, 1);
  Layouts.Items := [Layout];
  Layouts.Active := 0;
  Settings := TAtlasWelcomeCustomizing.Stored(Settings, Layouts);
  Adopted := TAtlasWelcomeCustomizing.Adopted(Settings, [TAtlasWelcomeIds.Header, TAtlasWelcomeIds.Board,
    TAtlasWelcomeIds.Search, TAtlasWelcomeIds.State, TAtlasWelcomeIds.Issues, TAtlasWelcomeIds.Help], nil, Added);
  Assert.AreEqual('atlas.issues,atlas.help', Joined(Added));
  Layout := TAtlasWelcomeCustomizing.Load(Adopted).Current;
  Assert.IsTrue(Layout.IndexOf(TAtlasWelcomeIds.Issues) >= 0);
  Assert.AreEqual(-1, Layout.IndexOf(TAtlasWelcomeIds.Header), 'Kopf, Tafel und Suche haben feste Plätze');
  // Beim nächsten Start ist nichts mehr neu.
  TAtlasWelcomeCustomizing.Adopted(Adopted, [TAtlasWelcomeIds.Issues, TAtlasWelcomeIds.Help], nil, Added);
  Assert.AreEqual(0, Integer(Length(Added)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeArrangeTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeFlowTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeLayoutsTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeCustomizingTests);

end.
