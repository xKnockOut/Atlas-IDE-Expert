unit Atlas.Core.Editor.Overview.Tests;

// Übersichtsleiste (#519): Arten aus der Einstellung, Lage proportional zur
// Zeile (Zeile 900 von 1000 unten), Mindesthöhe und Zusammenfassen,
// Zeichenreihenfolge, Treffer beim Klick, Suche nach dem markierten Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOverviewTests = class
  public
    [Test]
    procedure KindsFromSetting;
    [Test]
    procedure PositionIsProportional;
    [Test]
    procedure LayoutMergesAndOrders;
    [Test]
    procedure HitPrefersImportantMarks;
    [Test]
    procedure FilterByKinds;
    [Test]
    procedure SearchOccurrences;
    [Test]
    procedure SameMarks;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.Overview;

procedure TAtlasOverviewTests.KindsFromSetting;
begin
  Assert.AreEqual('diagnostics,search,changes,breakpoints,bookmarks,cursor',
    TAtlasOverview.KindsText(TAtlasOverview.AllKinds));
  Assert.IsTrue(TAtlasOverview.Kinds('Changes, cursor') = [TAtlasOverviewKind.Changes, TAtlasOverviewKind.Cursor]);
  Assert.AreEqual('search,cursor', TAtlasOverview.Normalize('cursor;gibtsnicht,search,search'));
  Assert.AreEqual('', TAtlasOverview.Normalize(''));
end;

procedure TAtlasOverviewTests.PositionIsProportional;
var
  Bars: TAtlasOverviewBars;
  Marks: TAtlasOverviewMarks;
begin
  // Fehler in Zeile 900 einer Datei mit 1000 Zeilen: unten im Streifen (Akzeptanzkriterium).
  Bars := TAtlasOverview.Layout([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 899, 1)], 1000, 500, 3);
  Assert.AreEqual(1, Integer(Length(Bars)));
  Assert.AreEqual(449, Bars[0].Top);
  Assert.AreEqual(452, Bars[0].Bottom, 'Mindesthöhe');
  Assert.AreEqual(Ord(TAtlasOverviewLane.Right), Ord(Bars[0].Lane));
  Assert.AreEqual(900, TAtlasOverview.LineAt(450, 1000, 500));
  Assert.AreEqual(898, TAtlasOverview.LineAt(449, 1000, 500));
  Assert.AreEqual(0, TAtlasOverview.LineAt(-5, 1000, 500));
  Assert.AreEqual(999, TAtlasOverview.LineAt(9999, 1000, 500));
  // Letzte Zeile bleibt im Streifen.
  Bars := TAtlasOverview.Layout([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 999, 1)], 1000, 500, 3);
  Assert.AreEqual(500, Bars[0].Bottom);
  Assert.AreEqual(497, Bars[0].Top);
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Layout(nil, 1000, 500, 3))));
  Marks := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1)];
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Layout(Marks, 0, 500, 3))), 'leere Datei');
end;

procedure TAtlasOverviewTests.LayoutMergesAndOrders;
var
  Bars: TAtlasOverviewBars;
begin
  Bars := TAtlasOverview.Layout([
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 10, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 11, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 10, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Added, 50, 20),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 30, 1)], 100, 100, 2);
  Assert.AreEqual(4, Integer(Length(Bars)), 'zwei Treffer auf benachbarten Pixeln: ein Balken');
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Cursor), Ord(Bars[0].Kind), 'Cursor zuunterst');
  Assert.AreEqual(Ord(TAtlasOverviewLane.Full), Ord(Bars[0].Lane));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Added), Ord(Bars[1].Kind));
  Assert.AreEqual(50, Bars[1].Top);
  Assert.AreEqual(70, Bars[1].Bottom, 'Block über 20 Zeilen');
  Assert.AreEqual(Ord(TAtlasOverviewLane.Left), Ord(Bars[1].Lane));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Search), Ord(Bars[2].Kind));
  Assert.AreEqual(10, Bars[2].Top);
  Assert.AreEqual(13, Bars[2].Bottom);
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Error), Ord(Bars[3].Kind), 'Fehler zuoberst');
end;

procedure TAtlasOverviewTests.HitPrefersImportantMarks;
var
  Marks: TAtlasOverviewMarks;
  Bars: TAtlasOverviewBars;
  Mark: Integer;
begin
  Marks := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 10, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Warning, 11, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 40, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 70, 1)];
  Bars := TAtlasOverview.Layout(Marks, 100, 100, 2);
  Assert.IsTrue(TAtlasOverview.Hit(Bars, 11, 2, Mark));
  Assert.AreEqual(1, Mark, 'Warnung vor Treffer');
  Assert.IsTrue(TAtlasOverview.Hit(Bars, 43, 2, Mark));
  Assert.AreEqual(2, Mark, 'mit Toleranz');
  Assert.IsFalse(TAtlasOverview.Hit(Bars, 25, 2, Mark));
  Assert.AreEqual(-1, Mark);
  Assert.IsFalse(TAtlasOverview.Hit(Bars, 70, 2, Mark), 'Cursor ist kein Ziel');
end;

procedure TAtlasOverviewTests.FilterByKinds;
var
  Marks: TAtlasOverviewMarks;
begin
  Marks := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Deleted, 2, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Breakpoint, 3, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, 4, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 5, 1)];
  Assert.AreEqual(5, Integer(Length(TAtlasOverview.Filter(Marks, TAtlasOverview.AllKinds))));
  Marks := TAtlasOverview.Filter(Marks, [TAtlasOverviewKind.Changes, TAtlasOverviewKind.Bookmarks]);
  Assert.AreEqual(2, Integer(Length(Marks)));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Deleted), Ord(Marks[0].Kind));
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Bookmark), Ord(Marks[1].Kind));
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Filter(Marks, []))));
end;

procedure TAtlasOverviewTests.SearchOccurrences;
var
  Term: string;
  Lines: TArray<Integer>;
begin
  Assert.IsTrue(TAtlasOverview.SearchTerm('ShowMessage', Term));
  Assert.AreEqual('ShowMessage', Term);
  Assert.IsFalse(TAtlasOverview.SearchTerm('', Term));
  Assert.IsFalse(TAtlasOverview.SearchTerm('   ', Term));
  Assert.IsFalse(TAtlasOverview.SearchTerm('a'#13#10'b', Term), 'mehrzeilig');
  Assert.IsFalse(TAtlasOverview.SearchTerm(StringOfChar('x', TAtlasOverview.MaxTermLength + 1), Term));
  Lines := TAtlasOverview.Occurrences(['begin', '  showmessage(''a'');', 'end;', '  ShowMessage(X);'], 'ShowMessage');
  Assert.AreEqual(2, Integer(Length(Lines)));
  Assert.AreEqual(1, Lines[0], 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual(3, Lines[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasOverview.Occurrences(['a'], ''))));
end;

procedure TAtlasOverviewTests.SameMarks;
var
  A, B: TAtlasOverviewMarks;
begin
  A := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1, 'E2003')];
  B := [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 1, 1, 'E2003')];
  Assert.IsTrue(TAtlasOverview.Same(A, B));
  B[0].Text := 'anders';
  Assert.IsFalse(TAtlasOverview.Same(A, B));
  Assert.IsFalse(TAtlasOverview.Same(A, nil));
  Assert.IsTrue(TAtlasOverview.Same(nil, nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOverviewTests);

end.
