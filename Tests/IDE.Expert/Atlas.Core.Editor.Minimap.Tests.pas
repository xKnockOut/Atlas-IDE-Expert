unit Atlas.Core.Editor.Minimap.Tests;

// Minimap (#873): Auswertung der Einstellungen, Umrechnung Mausposition ↔
// Zeile mit Faltung und Stauchung, Lage und Höhe des Schiebers, Ziel beim
// Ziehen und Klicken, Abschnittsüberschriften, aktuelle Methode, Zuordnung der
// Marken, Balken je Wort, geänderte Zeilen, Erkennen gefalteter Bereiche.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMinimapTests = class
  public
    [Test]
    procedure OptionsFromSettings;
    [Test]
    procedure LinesAndRowsWithFolds;
    [Test]
    procedure PixelsWithoutCompression;
    [Test]
    procedure LongFilesAreCompressed;
    [Test]
    procedure SliderPositionAndHeight;
    [Test]
    procedure DragAndClickTargets;
    [Test]
    procedure SectionHeadersFromOutline;
    [Test]
    procedure CurrentMethodRange;
    [Test]
    procedure MarkersMapToRows;
    [Test]
    procedure RunsPerWord;
    [Test]
    procedure ChangedLinesOnly;
    [Test]
    procedure GlyphHeights;
    [Test]
    procedure FoldsFromPaintedLines;
    [Test]
    procedure NormalizeNestedFolds;
    [Test]
    procedure NoticeOnlyOnce;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Syntax,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Editor.Minimap;

function Node(const AName: string; AKind: Integer; ACategory: TAtlasOutlineCategory;
  AStart, AStop, AParent: Integer): TAtlasOutlineNode;
begin
  Result := Default(TAtlasOutlineNode);
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Category := ACategory;
  Result.StartLine := AStart;
  Result.NameLine := AStart;
  Result.EndLine := AStop;
  Result.Parent := AParent;
  Result.Declaration := -1;
  Result.Body := -1;
end;

function Fold(ALine, AHidden: Integer): TAtlasMinimapFold;
begin
  Result := TAtlasMinimapFold.Create(ALine, AHidden);
end;

procedure TAtlasMinimapTests.OptionsFromSettings;
var
  Options: TAtlasMinimapOptions;
begin
  Options := TAtlasMinimap.Defaults;
  Assert.AreEqual(Ord(TAtlasMinimapRender.Blocks), Ord(Options.Render));
  Assert.AreEqual(120, Options.Width);
  Assert.AreEqual(1, Options.Scale);
  Assert.AreEqual(120, Options.MaxColumn);
  Assert.AreEqual(Ord(TAtlasMinimapSide.Right), Ord(Options.Side));
  Assert.AreEqual(Ord(TAtlasMinimapSlider.Always), Ord(Options.Slider));
  Assert.IsTrue(Options.SectionHeaders and Options.HighlightMethod and Options.Markers and Options.ClickJumps);
  Assert.AreEqual(2, Options.RowHeight);

  Options := TAtlasMinimap.Options('Characters', 'LEFT', 'mouseover', 80, 3, 60, False, False, False, False);
  Assert.AreEqual(Ord(TAtlasMinimapRender.Characters), Ord(Options.Render));
  Assert.AreEqual(Ord(TAtlasMinimapSide.Left), Ord(Options.Side));
  Assert.AreEqual(Ord(TAtlasMinimapSlider.MouseOver), Ord(Options.Slider));
  Assert.AreEqual(80, Options.Width);
  Assert.AreEqual(6, Options.RowHeight, 'Pixel je Zeile = 2 × Maßstab');
  Assert.AreEqual(60, Options.MaxColumn);
  Assert.IsFalse(Options.SectionHeaders or Options.HighlightMethod or Options.Markers or Options.ClickJumps);
  // Spalte 30 von 60 liegt bei 80 Pixeln Breite in der Mitte.
  Assert.AreEqual(40, Options.ColumnX(30, 80));
  Assert.AreEqual(80, Options.ColumnX(200, 80), 'nach der höchsten Spalte geklemmt');

  // Unbekannte Namen: Vorgabe; Zahlen geklemmt.
  Options := TAtlasMinimap.Options('pixel', 'oben', '', 5, 9, 10000, True, True, True, True);
  Assert.AreEqual(Ord(TAtlasMinimapRender.Blocks), Ord(Options.Render));
  Assert.AreEqual(Ord(TAtlasMinimapSide.Right), Ord(Options.Side));
  Assert.AreEqual(Ord(TAtlasMinimapSlider.Always), Ord(Options.Slider));
  Assert.AreEqual(TAtlasMinimap.MinWidth, Options.Width);
  Assert.AreEqual(TAtlasMinimap.MaxScale, Options.Scale);
  Assert.AreEqual(TAtlasMinimap.MaxColumnLimit, Options.MaxColumn);
  Assert.AreEqual(TAtlasMinimap.MaxWidth, TAtlasMinimap.ClampWidth(1000));
  Assert.AreEqual(TAtlasMinimap.MinScale, TAtlasMinimap.ClampScale(0));
  Assert.AreEqual(TAtlasMinimap.MinColumn, TAtlasMinimap.ClampColumn(1));
end;

procedure TAtlasMinimapTests.LinesAndRowsWithFolds;
var
  Map: TAtlasMinimapMap;
begin
  // Zeilen 11–15 und 21–23 sind gefaltet.
  Map := TAtlasMinimapMap.Create(100, [Fold(20, 3), Fold(10, 5)], 2, 500);
  Assert.AreEqual(92, Map.RowCount);
  Assert.AreEqual(10, Map.Folds[0].Line, 'sortiert');
  Assert.AreEqual(9, Map.RowOf(9));
  Assert.AreEqual(10, Map.RowOf(10));
  Assert.AreEqual(10, Map.RowOf(12), 'verborgen: Kopfzeile');
  Assert.AreEqual(10, Map.RowOf(15));
  Assert.AreEqual(11, Map.RowOf(16));
  Assert.AreEqual(15, Map.RowOf(20));
  Assert.AreEqual(15, Map.RowOf(22));
  Assert.AreEqual(16, Map.RowOf(24));
  Assert.AreEqual(91, Map.RowOf(99));
  Assert.AreEqual(10, Map.LineOf(10));
  Assert.AreEqual(16, Map.LineOf(11));
  Assert.AreEqual(20, Map.LineOf(15));
  Assert.AreEqual(24, Map.LineOf(16));
  Assert.AreEqual(99, Map.LineOf(91));
  Assert.AreEqual(99, Map.LineOf(500), 'geklemmt');
  Assert.AreEqual(0, Map.LineOf(-3));
  Assert.AreEqual(3, Map.VisibleRows(10, 17), 'gefaltete Zeilen zählen einmal');
end;

procedure TAtlasMinimapTests.PixelsWithoutCompression;
var
  Map: TAtlasMinimapMap;
begin
  Map := TAtlasMinimapMap.Create(100, [Fold(10, 5)], 2, 500);
  Assert.IsFalse(Map.Compressed);
  Assert.AreEqual(190, Map.ContentHeight);
  Assert.AreEqual(20, Map.PixelOfLine(10));
  Assert.AreEqual(20, Map.PixelOfLine(13));
  Assert.AreEqual(22, Map.PixelOfLine(16));
  Assert.AreEqual(16, Map.LineAt(22));
  Assert.AreEqual(16, Map.LineAt(23));
  Assert.AreEqual(10, Map.LineAt(21));
  Assert.AreEqual(0, Map.LineAt(-10));
  Assert.AreEqual(99, Map.LineAt(1000), 'unter dem Inhalt: letzte Zeile');
end;

procedure TAtlasMinimapTests.LongFilesAreCompressed;
var
  Map: TAtlasMinimapMap;
begin
  // 10 000 Zeilen mit 2 Pixeln brauchten 20 000 Pixel; 500 sind da.
  Map := TAtlasMinimapMap.Create(10000, nil, 2, 500);
  Assert.IsTrue(Map.Compressed);
  Assert.AreEqual(500, Map.ContentHeight);
  Assert.AreEqual(250, Map.PixelOfLine(5000));
  Assert.AreEqual(5000, Map.LineAt(250));
  Assert.AreEqual(9980, Map.LineAt(499));
  Assert.AreEqual(9999, Map.LineAt(600));
  // Gestaucht mit Faltung: Die verborgenen Zeilen zählen nicht.
  Map := TAtlasMinimapMap.Create(1000, [Fold(0, 499)], 2, 100);
  Assert.AreEqual(501, Map.RowCount);
  Assert.IsTrue(Map.Compressed);
  Assert.AreEqual(749, Map.LineAt(50));
  Assert.AreEqual(49, Map.PixelOfLine(749));
  Assert.AreEqual(0, Map.PixelOfLine(300), 'in der Faltung: Kopfzeile');
  // Gerade noch ohne Stauchung.
  Map := TAtlasMinimapMap.Create(250, nil, 2, 500);
  Assert.IsFalse(Map.Compressed);
end;

procedure TAtlasMinimapTests.SliderPositionAndHeight;
var
  Map: TAtlasMinimapMap;
  Span: TAtlasMinimapSpan;
begin
  Map := TAtlasMinimapMap.Create(100, nil, 2, 500);
  Span := Map.Slider(20, 39, 4);
  Assert.AreEqual(40, Span.Top);
  Assert.AreEqual(80, Span.Bottom);
  Span := Map.Slider(0, 0, 8);
  Assert.AreEqual(0, Span.Top);
  Assert.AreEqual(8, Span.Bottom, 'Mindesthöhe');
  // Faltung im sichtbaren Bereich macht den Schieber kürzer.
  Map := TAtlasMinimapMap.Create(100, [Fold(25, 5)], 2, 500);
  Span := Map.Slider(20, 39, 4);
  Assert.AreEqual(40, Span.Top);
  Assert.AreEqual(70, Span.Bottom);
  // Am Ende der gestauchten Datei bleibt der Schieber in der Höhe.
  Map := TAtlasMinimapMap.Create(10000, nil, 2, 500);
  Span := Map.Slider(9990, 9999, 4);
  Assert.AreEqual(496, Span.Top);
  Assert.AreEqual(500, Span.Bottom);
  Span := Map.Slider(5000, 5099, 4);
  Assert.AreEqual(250, Span.Top);
  Assert.AreEqual(255, Span.Bottom);
end;

procedure TAtlasMinimapTests.DragAndClickTargets;
var
  Map: TAtlasMinimapMap;
begin
  Map := TAtlasMinimapMap.Create(100, nil, 2, 500);
  // Schieber 10 Pixel unter seinem oberen Rand gegriffen, Maus bei 100: oberer Rand bei 90 = Zeile 45.
  Assert.AreEqual(45, Map.DragTop(100, 10, 20));
  Assert.AreEqual(80, Map.DragTop(1000, 10, 20), 'unten: die letzte Seite');
  Assert.AreEqual(0, Map.DragTop(5, 10, 20), 'über den Anfang hinaus');
  // Klick zentriert die Zeile unter der Maus.
  Assert.AreEqual(40, Map.ClickTop(100, 20));
  Assert.AreEqual(0, Map.ClickTop(0, 20));
  Assert.AreEqual(80, Map.ClickTop(499, 20));
  // Mit Faltung: Minimap-Zeile 10 ist die Kopfzeile 10.
  Map := TAtlasMinimapMap.Create(100, [Fold(10, 5)], 2, 500);
  Assert.AreEqual(10, Map.ClickTop(40, 20));
  Assert.AreEqual(16, Map.DragTop(22, 0, 20));
  // Gestaucht: flüssig über 10 000 Zeilen.
  Map := TAtlasMinimapMap.Create(10000, nil, 2, 500);
  Assert.AreEqual(5000, Map.DragTop(260, 10, 50));
  Assert.AreEqual(9950, Map.DragTop(499, 0, 50));
end;

procedure TAtlasMinimapTests.SectionHeadersFromOutline;
var
  Nodes: TAtlasOutlineNodes;
  Map: TAtlasMinimapMap;
  Headers: TAtlasMinimapHeaders;
  Local: TAtlasOutlineNode;
begin
  Nodes := [
    Node('TFoo', 5, TAtlasOutlineCategory.TypeDecl, 5, 20, -1),
    Node('Bar', 6, TAtlasOutlineCategory.Method, 7, 7, 0),
    Node('TKind', 10, TAtlasOutlineCategory.TypeDecl, 22, 22, -1),
    Node('TFoo.Bar', 6, TAtlasOutlineCategory.Routine, 30, 40, -1),
    Node('Helper', 12, TAtlasOutlineCategory.Routine, 31, 33, -1),
    Node('Free', 12, TAtlasOutlineCategory.Routine, 50, 60, -1)];
  Local := Node('Inner', 12, TAtlasOutlineCategory.Routine, 52, 54, 5);
  Local.InBody := True;
  Nodes := Nodes + [Local];
  Nodes[3].Hidden := True;
  Map := TAtlasMinimapMap.Create(100, nil, 2, 500);
  Headers := TAtlasMinimap.Headers(Nodes, Map, 8);
  Assert.AreEqual(3, Integer(Length(Headers)), 'Methodendeklaration, Aufzählung, lokale und überdeckte fallen weg');
  Assert.AreEqual('TFoo', Headers[0].Text);
  Assert.IsTrue(Headers[0].IsType);
  Assert.AreEqual(10, Headers[0].Top);
  Assert.AreEqual('TFoo.Bar', Headers[1].Text);
  Assert.IsFalse(Headers[1].IsType);
  Assert.AreEqual(60, Headers[1].Top);
  Assert.AreEqual(3, Headers[1].Node);
  Assert.AreEqual('Free', Headers[2].Text);
  Assert.AreEqual(50, Headers[2].Line);
  // Unten ohne Platz für die Beschriftung: weg.
  Map := TAtlasMinimapMap.Create(100, nil, 2, 200);
  Headers := TAtlasMinimap.Headers(Nodes + [Node('Last', 12, TAtlasOutlineCategory.Routine, 97, 99, -1)], Map, 8);
  Assert.AreEqual(3, Integer(Length(Headers)));
  // In einer Faltung: an der Kopfzeile.
  Map := TAtlasMinimapMap.Create(100, [Fold(25, 10)], 2, 500);
  Headers := TAtlasMinimap.Headers(Nodes, Map, 8);
  Assert.AreEqual(50, Headers[1].Top);
end;

procedure TAtlasMinimapTests.CurrentMethodRange;
var
  Nodes: TAtlasOutlineNodes;
  Local: TAtlasOutlineNode;
  First, Last: Integer;
begin
  Nodes := [
    Node('TFoo', 5, TAtlasOutlineCategory.TypeDecl, 5, 20, -1),
    Node('Bar', 6, TAtlasOutlineCategory.Method, 7, 7, 0),
    Node('TFoo.Bar', 6, TAtlasOutlineCategory.Routine, 30, 40, -1)];
  Local := Node('Inner', 12, TAtlasOutlineCategory.Routine, 32, 35, 2);
  Local.InBody := True;
  Nodes := Nodes + [Local];
  Assert.IsTrue(TAtlasMinimap.MethodAt(Nodes, 33, First, Last));
  Assert.AreEqual(32, First, 'die innerste');
  Assert.AreEqual(35, Last);
  Assert.IsTrue(TAtlasMinimap.MethodAt(Nodes, 38, First, Last));
  Assert.AreEqual(30, First);
  Assert.AreEqual(40, Last);
  Assert.IsFalse(TAtlasMinimap.MethodAt(Nodes, 7, First, Last), 'Deklaration in der Klasse');
  Assert.IsFalse(TAtlasMinimap.MethodAt(Nodes, 50, First, Last));
  Assert.AreEqual(-1, First);
end;

procedure TAtlasMinimapTests.MarkersMapToRows;
var
  Marks: TAtlasOverviewMarks;
  Map: TAtlasMinimapMap;
  Bars: TAtlasOverviewBars;
  Bar: TAtlasOverviewBar;
  Found: Integer;
begin
  Marks := [
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 3, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, 4, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Breakpoint, 5, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Added, 10, 3),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 60, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 61, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 50, 1)];
  Map := TAtlasMinimapMap.Create(100, [Fold(48, 5)], 2, 500);
  Bars := TAtlasMinimap.MarkerBars(Marks, Map, 2);
  Assert.AreEqual(3, Integer(Length(Bars)), 'ohne Cursor, Lesezeichen, Haltepunkt; Treffer zusammengefasst');
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Added), Ord(Bars[0].Kind));
  Assert.AreEqual(Ord(TAtlasOverviewLane.Left), Ord(Bars[0].Lane), 'Änderungen am linken Rand');
  Assert.AreEqual(20, Bars[0].Top);
  Assert.AreEqual(26, Bars[0].Bottom);
  Found := 0;
  for Bar in Bars do
    if Bar.Kind = TAtlasOverviewMarkKind.Search then
    begin
      Inc(Found);
      Assert.AreEqual(Ord(TAtlasOverviewLane.Full), Ord(Bar.Lane), 'Zeilenband');
      Assert.AreEqual(110, Bar.Top);
      Assert.AreEqual(114, Bar.Bottom);
    end;
  Assert.AreEqual(1, Found);
  // Der Fehler liegt in der Faltung: auf ihrer Kopfzeile, wichtigste Art zuletzt.
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Error), Ord(Bars[2].Kind));
  Assert.AreEqual(96, Bars[2].Top);
  Assert.AreEqual(6, Bars[2].Mark);
  Assert.IsTrue(TAtlasMinimap.MarkerKinds = [TAtlasOverviewKind.Diagnostics, TAtlasOverviewKind.Search,
    TAtlasOverviewKind.Changes]);
end;

procedure TAtlasMinimapTests.RunsPerWord;
var
  Line: TAtlasMinimapLine;
  Lines: TAtlasMinimapLines;
begin
  Lines := TAtlasMinimap.Runs(['  if Foo then // x', #9'a', 'abcdefgh', '{ offen', 'zu }', ''], 5, 4);
  Assert.AreEqual(6, Integer(Length(Lines)));
  Lines := TAtlasMinimap.Runs(['  if Foo then // x'], 120, 4);
  Line := Lines[0];
  Assert.AreEqual(5, Integer(Length(Line)));
  Assert.AreEqual(2, Line[0].Start);
  Assert.AreEqual(4, Line[0].Stop);
  Assert.AreEqual(Ord(TAtlasTokenKind.Keyword), Ord(Line[0].Kind));
  Assert.AreEqual(5, Line[1].Start);
  Assert.AreEqual(8, Line[1].Stop);
  Assert.AreEqual(Ord(TAtlasTokenKind.Plain), Ord(Line[1].Kind));
  Assert.AreEqual(Ord(TAtlasTokenKind.Keyword), Ord(Line[2].Kind));
  Assert.AreEqual(Ord(TAtlasTokenKind.Comment), Ord(Line[3].Kind));
  Assert.AreEqual(14, Line[3].Start);
  Assert.AreEqual(17, Line[4].Start);
  Assert.AreEqual(Ord(TAtlasTokenKind.Comment), Ord(Line[4].Kind));
  // Tabulator klappt auf die nächste Stufe aus.
  Lines := TAtlasMinimap.Runs([#9'a', ' '#9'b'], 120, 4);
  Assert.AreEqual(4, Lines[0][0].Start);
  Assert.AreEqual(4, Lines[1][0].Start);
  // Höchste Spalte schneidet ab.
  Lines := TAtlasMinimap.Runs(['abcdefgh', '      xy'], 5, 4);
  Assert.AreEqual(1, Integer(Length(Lines[0])));
  Assert.AreEqual(5, Lines[0][0].Stop);
  Assert.AreEqual(0, Integer(Length(Lines[1])), 'erst nach der höchsten Spalte');
  // Ausgeklappt für die Darstellung „characters“.
  Assert.AreEqual('    a', TAtlasMinimap.Expand(#9'a', 120, 4));
  Assert.AreEqual('x   b', TAtlasMinimap.Expand('x'#9'b', 120, 4));
  Assert.AreEqual('abc', TAtlasMinimap.Expand('abcdef', 3, 4));
  Assert.AreEqual('a ', TAtlasMinimap.Expand('a'#9'b', 2, 4), 'Tabulator am Rand geklemmt');
  // Mehrzeiliger Kommentar bleibt Kommentar.
  Lines := TAtlasMinimap.Runs(['{ offen', 'zu }'], 120, 4);
  Assert.AreEqual(Ord(TAtlasTokenKind.Comment), Ord(Lines[1][0].Kind));
end;

procedure TAtlasMinimapTests.ChangedLinesOnly;
var
  Old, New: TAtlasMinimapLines;
  Changed: TArray<Integer>;
begin
  Old := TAtlasMinimap.Runs(['a := 1;', 'b := 2;', 'c := 3;'], 120, 4);
  New := TAtlasMinimap.Runs(['a := 1;', 'bb := 2;', 'c := 3;', 'd;'], 120, 4);
  Changed := TAtlasMinimap.ChangedLines(Old, New);
  Assert.AreEqual(2, Integer(Length(Changed)));
  Assert.AreEqual(1, Changed[0]);
  Assert.AreEqual(3, Changed[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasMinimap.ChangedLines(Old, Old))));
  Assert.IsTrue(TAtlasMinimap.SameLine(Old[0], New[0]));
  Assert.IsFalse(TAtlasMinimap.SameLine(Old[1], New[1]));
end;

procedure TAtlasMinimapTests.GlyphHeights;
begin
  Assert.AreEqual(4, TAtlasMinimap.GlyphHeight('A', 4));
  Assert.AreEqual(4, TAtlasMinimap.GlyphHeight('7', 4));
  Assert.AreEqual(4, TAtlasMinimap.GlyphHeight('(', 4));
  Assert.AreEqual(3, TAtlasMinimap.GlyphHeight('a', 4));
  Assert.AreEqual(1, TAtlasMinimap.GlyphHeight('a', 1));
  Assert.AreEqual(1, TAtlasMinimap.GlyphHeight('.', 4));
  Assert.AreEqual(0, TAtlasMinimap.GlyphHeight(' ', 4));
  Assert.AreEqual(0, TAtlasMinimap.GlyphHeight(#9, 4));
  Assert.AreEqual(0, TAtlasMinimap.GlyphHeight('A', 0));
end;

procedure TAtlasMinimapTests.FoldsFromPaintedLines;
var
  Folds: TAtlasMinimapFolds;
begin
  // Zeilenhöhe 16: auf Zeile 11 folgt direkt Zeile 20, dazwischen ist gefaltet.
  Folds := TAtlasMinimap.Folds(nil, [TAtlasMinimapPainted.Create(32, 20), TAtlasMinimapPainted.Create(0, 10),
    TAtlasMinimapPainted.Create(16, 11)], 16, 100);
  Assert.AreEqual(1, Integer(Length(Folds)));
  Assert.AreEqual(11, Folds[0].Line);
  Assert.AreEqual(8, Folds[0].Hidden);
  // Nicht direkt untereinander (Teil neu gemalt): sagt nichts.
  Folds := TAtlasMinimap.Folds(nil, [TAtlasMinimapPainted.Create(0, 10), TAtlasMinimapPainted.Create(48, 30)], 16,
    100);
  Assert.AreEqual(0, Integer(Length(Folds)));
  // Aufgeklappt: Kopfzeile und Folgezeile stehen untereinander; ein anderer bekannter Bereich bleibt.
  Folds := TAtlasMinimap.Folds([Fold(11, 8), Fold(50, 3)], [TAtlasMinimapPainted.Create(0, 11),
    TAtlasMinimapPainted.Create(16, 12)], 16, 100);
  Assert.AreEqual(1, Integer(Length(Folds)));
  Assert.AreEqual(50, Folds[0].Line);
  // Geändert: der neue Stand gilt.
  Folds := TAtlasMinimap.Folds([Fold(11, 8)], [TAtlasMinimapPainted.Create(0, 11),
    TAtlasMinimapPainted.Create(16, 15)], 16, 100);
  Assert.AreEqual(3, Folds[0].Hidden);
  Assert.IsTrue(TAtlasMinimap.SameFolds([Fold(11, 3)], Folds));
  Assert.IsFalse(TAtlasMinimap.SameFolds([Fold(11, 4)], Folds));
end;

procedure TAtlasMinimapTests.NormalizeNestedFolds;
var
  Folds: TAtlasMinimapFolds;
begin
  Folds := TAtlasMinimap.NormalizeFolds([Fold(40, 0), Fold(12, 2), Fold(10, 10), Fold(18, 6), Fold(95, 20),
    Fold(-1, 3), Fold(99, 1)], 100);
  Assert.AreEqual(2, Integer(Length(Folds)));
  Assert.AreEqual(10, Folds[0].Line);
  Assert.AreEqual(14, Folds[0].Hidden, 'verschachtelte gehen auf, überstehende verlängern');
  Assert.AreEqual(95, Folds[1].Line);
  Assert.AreEqual(4, Folds[1].Hidden, 'am Dateiende geklemmt');
end;

procedure TAtlasMinimapTests.NoticeOnlyOnce;
begin
  Assert.IsTrue(TAtlasMinimap.ShouldNotice(True, True, False));
  Assert.IsFalse(TAtlasMinimap.ShouldNotice(True, True, True));
  Assert.IsFalse(TAtlasMinimap.ShouldNotice(True, False, False));
  Assert.IsFalse(TAtlasMinimap.ShouldNotice(False, True, False));
end;

end.
