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
    procedure LongFilesScrollWithEditor;
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
  Atlas.Core.Settings.Plugin,
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

/// <summary>Vorgaben mit den Minimap-Einstellungen aus den Argumenten.</summary>
function MinimapSettings(const ARender, ASide, ASlider: string; AWidth, AScale, AMaxColumn: Integer):
  TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.MinimapRender := ARender;
  Result.MinimapSide := ASide;
  Result.MinimapShowSlider := ASlider;
  Result.MinimapWidth := AWidth;
  Result.MinimapScale := AScale;
  Result.MinimapMaxColumn := AMaxColumn;
end;

/// <summary>Überschriften, Methode, Marken und Klicksprung zugleich an bzw. aus.</summary>
procedure SetMinimapFlags(var ASettings: TAtlasPluginSettings; AValue: Boolean);
begin
  ASettings.MinimapSectionHeaders := AValue;
  ASettings.MinimapHighlightMethod := AValue;
  ASettings.MinimapMarkers := AValue;
  ASettings.MinimapClickJumps := AValue;
end;

procedure TAtlasMinimapTests.OptionsFromSettings;
var
  mOptions: TAtlasMinimapOptions;
  mSettings: TAtlasPluginSettings;
begin
  mOptions := TAtlasMinimap.Defaults;
  Assert.AreEqual(Ord(TAtlasMinimapRender.Characters), Ord(mOptions.Render));
  Assert.AreEqual(120, mOptions.Width);
  Assert.AreEqual(2, mOptions.Scale);
  Assert.AreEqual(120, mOptions.MaxColumn);
  Assert.AreEqual(Ord(TAtlasMinimapSide.Right), Ord(mOptions.Side));
  Assert.AreEqual(Ord(TAtlasMinimapSlider.Always), Ord(mOptions.Slider));
  Assert.IsTrue(mOptions.SectionHeaders and mOptions.HighlightMethod and mOptions.Markers and mOptions.ClickJumps);
  Assert.AreEqual(4, mOptions.RowHeight);

  mSettings := MinimapSettings('Characters', 'LEFT', 'mouseover', 80, 3, 60);
  SetMinimapFlags(mSettings, False);
  mOptions := TAtlasMinimap.Options(mSettings);
  Assert.AreEqual(Ord(TAtlasMinimapRender.Characters), Ord(mOptions.Render));
  Assert.AreEqual(Ord(TAtlasMinimapSide.Left), Ord(mOptions.Side));
  Assert.AreEqual(Ord(TAtlasMinimapSlider.MouseOver), Ord(mOptions.Slider));
  Assert.AreEqual(80, mOptions.Width);
  Assert.AreEqual(6, mOptions.RowHeight, 'Pixel je Zeile = 2 × Maßstab');
  Assert.AreEqual(60, mOptions.MaxColumn);
  Assert.IsFalse(mOptions.SectionHeaders or mOptions.HighlightMethod or mOptions.Markers or mOptions.ClickJumps);
  // Spalte 30 von 60 liegt bei 80 Pixeln Breite in der Mitte.
  Assert.AreEqual(40, mOptions.ColumnX(30, 80));
  Assert.AreEqual(80, mOptions.ColumnX(200, 80), 'nach der höchsten Spalte geklemmt');

  // Unbekannte Namen: Vorgabe; Zahlen geklemmt.
  mSettings := MinimapSettings('pixel', 'oben', '', 5, 9, 10000);
  SetMinimapFlags(mSettings, True);
  mOptions := TAtlasMinimap.Options(mSettings);
  Assert.AreEqual(Ord(TAtlasMinimapRender.Characters), Ord(mOptions.Render));
  Assert.AreEqual(Ord(TAtlasMinimapSide.Right), Ord(mOptions.Side));
  Assert.AreEqual(Ord(TAtlasMinimapSlider.Always), Ord(mOptions.Slider));
  Assert.AreEqual(TAtlasMinimap.cMinWidth, mOptions.Width);
  Assert.AreEqual(TAtlasMinimap.cMaxScale, mOptions.Scale);
  Assert.AreEqual(TAtlasMinimap.cMaxColumnLimit, mOptions.MaxColumn);
  Assert.AreEqual(TAtlasMinimap.cMaxWidth, TAtlasMinimap.ClampWidth(1000));
  Assert.AreEqual(TAtlasMinimap.cMinScale, TAtlasMinimap.ClampScale(0));
  Assert.AreEqual(TAtlasMinimap.cMinColumn, TAtlasMinimap.ClampColumn(1));
end;

procedure TAtlasMinimapTests.LinesAndRowsWithFolds;
var
  mMap: TAtlasMinimapMap;
begin
  // Zeilen 11–15 und 21–23 sind gefaltet.
  mMap := TAtlasMinimapMap.Create(100, [Fold(20, 3), Fold(10, 5)], 2, 500);
  Assert.AreEqual(92, mMap.RowCount);
  Assert.AreEqual(10, mMap.Folds[0].Line, 'sortiert');
  Assert.AreEqual(9, mMap.RowOf(9));
  Assert.AreEqual(10, mMap.RowOf(10));
  Assert.AreEqual(10, mMap.RowOf(12), 'verborgen: Kopfzeile');
  Assert.AreEqual(10, mMap.RowOf(15));
  Assert.AreEqual(11, mMap.RowOf(16));
  Assert.AreEqual(15, mMap.RowOf(20));
  Assert.AreEqual(15, mMap.RowOf(22));
  Assert.AreEqual(16, mMap.RowOf(24));
  Assert.AreEqual(91, mMap.RowOf(99));
  Assert.AreEqual(10, mMap.LineOf(10));
  Assert.AreEqual(16, mMap.LineOf(11));
  Assert.AreEqual(20, mMap.LineOf(15));
  Assert.AreEqual(24, mMap.LineOf(16));
  Assert.AreEqual(99, mMap.LineOf(91));
  Assert.AreEqual(99, mMap.LineOf(500), 'geklemmt');
  Assert.AreEqual(0, mMap.LineOf(-3));
  Assert.AreEqual(3, mMap.VisibleRows(10, 17), 'gefaltete Zeilen zählen einmal');
end;

procedure TAtlasMinimapTests.PixelsWithoutCompression;
var
  mMap: TAtlasMinimapMap;
begin
  mMap := TAtlasMinimapMap.Create(100, [Fold(10, 5)], 2, 500);
  Assert.IsFalse(mMap.Compressed);
  Assert.AreEqual(190, mMap.ContentHeight);
  Assert.AreEqual(20, mMap.PixelOfLine(10));
  Assert.AreEqual(20, mMap.PixelOfLine(13));
  Assert.AreEqual(22, mMap.PixelOfLine(16));
  Assert.AreEqual(16, mMap.LineAt(22));
  Assert.AreEqual(16, mMap.LineAt(23));
  Assert.AreEqual(10, mMap.LineAt(21));
  Assert.AreEqual(0, mMap.LineAt(-10));
  Assert.AreEqual(99, mMap.LineAt(1000), 'unter dem Inhalt: letzte Zeile');
end;

procedure TAtlasMinimapTests.LongFilesScrollWithEditor;
var
  mMap: TAtlasMinimapMap;
begin
  // 10 000 Zeilen mit 2 Pixeln brauchen 20 000 Pixel; 500 sind da. Nicht gestaucht: Die Minimap scrollt mit.
  mMap := TAtlasMinimapMap.Create(10000, nil, 2, 500);
  Assert.IsFalse(mMap.Compressed);
  Assert.AreEqual(500, mMap.ContentHeight);
  Assert.AreEqual(0, mMap.Offset, 'oben: Anfang');
  // Mitte: Offset anteilig, 19 500 × 5000 / 9950.
  Assert.IsTrue(mMap.Follow(5000, 5049));
  Assert.AreEqual(9798, mMap.Offset);
  Assert.AreEqual(202, mMap.PixelOfLine(5000));
  Assert.AreEqual(5000, mMap.LineAt(202));
  // Ende: die letzte Zeile ganz unten.
  mMap.Follow(9950, 9999);
  Assert.AreEqual(19500, mMap.Offset);
  Assert.AreEqual(9999, mMap.LineAt(499));
  Assert.AreEqual(498, mMap.PixelOfLine(9999));
  // Zurück nach oben.
  Assert.IsTrue(mMap.Follow(0, 49));
  Assert.AreEqual(0, mMap.Offset);
  // Mit Faltung: verborgene Zeilen gehören zur Kopfzeile.
  mMap := TAtlasMinimapMap.Create(1000, [Fold(0, 499)], 2, 100);
  Assert.AreEqual(501, mMap.RowCount);
  Assert.AreEqual(0, mMap.PixelOfLine(300), 'in der Faltung: Kopfzeile');
  // Passt in die Höhe: kein Offset, Follow ändert nichts.
  mMap := TAtlasMinimapMap.Create(250, nil, 2, 500);
  Assert.IsFalse(mMap.Follow(200, 249));
  Assert.AreEqual(0, mMap.Offset);
end;

procedure TAtlasMinimapTests.SliderPositionAndHeight;
var
  mMap: TAtlasMinimapMap;
  mSpan: TAtlasMinimapSpan;
begin
  mMap := TAtlasMinimapMap.Create(100, nil, 2, 500);
  mSpan := mMap.Slider(20, 39, 4);
  Assert.AreEqual(40, mSpan.Top);
  Assert.AreEqual(80, mSpan.Bottom);
  mSpan := mMap.Slider(0, 0, 8);
  Assert.AreEqual(0, mSpan.Top);
  Assert.AreEqual(8, mSpan.Bottom, 'Mindesthöhe');
  // Faltung im sichtbaren Bereich macht den Schieber kürzer.
  mMap := TAtlasMinimapMap.Create(100, [Fold(25, 5)], 2, 500);
  mSpan := mMap.Slider(20, 39, 4);
  Assert.AreEqual(40, mSpan.Top);
  Assert.AreEqual(70, mSpan.Bottom);
  // Mitscrollend: Am Ende steht der Schieber unten, in der Mitte anteilig.
  mMap := TAtlasMinimapMap.Create(10000, nil, 2, 500);
  mMap.Follow(9990, 9999);
  mSpan := mMap.Slider(9990, 9999, 4);
  Assert.AreEqual(480, mSpan.Top);
  Assert.AreEqual(500, mSpan.Bottom);
  mMap.Follow(5000, 5099);
  mSpan := mMap.Slider(5000, 5099, 4);
  Assert.AreEqual(152, mSpan.Top);
  Assert.AreEqual(352, mSpan.Bottom);
end;

procedure TAtlasMinimapTests.DragAndClickTargets;
var
  mMap: TAtlasMinimapMap;
begin
  mMap := TAtlasMinimapMap.Create(100, nil, 2, 500);
  // Schieber 10 Pixel unter seinem oberen Rand gegriffen, Maus bei 100: oberer Rand bei 90 = Zeile 45.
  Assert.AreEqual(45, mMap.DragTop(100, 10, 20));
  Assert.AreEqual(80, mMap.DragTop(1000, 10, 20), 'unten: die letzte Seite');
  Assert.AreEqual(0, mMap.DragTop(5, 10, 20), 'über den Anfang hinaus');
  // Klick zentriert die Zeile unter der Maus.
  Assert.AreEqual(40, mMap.ClickTop(100, 20));
  Assert.AreEqual(0, mMap.ClickTop(0, 20));
  Assert.AreEqual(80, mMap.ClickTop(499, 20));
  // Mit Faltung: Minimap-Zeile 10 ist die Kopfzeile 10.
  mMap := TAtlasMinimapMap.Create(100, [Fold(10, 5)], 2, 500);
  Assert.AreEqual(10, mMap.ClickTop(40, 20));
  Assert.AreEqual(16, mMap.DragTop(22, 0, 20));
  // Mitscrollend über 10 000 Zeilen: Der Schieber läuft linear über 400 Pixel (500 − 50 Zeilen × 2), unabhängig
  // vom Offset; Oberkante bei 250 = 62,5 % von 9950.
  mMap := TAtlasMinimapMap.Create(10000, nil, 2, 500);
  Assert.AreEqual(6218, mMap.DragTop(260, 10, 50));
  mMap.Follow(6218, 6267);
  Assert.AreEqual(6218, mMap.DragTop(260, 10, 50), 'Offset ändert das Ziel nicht');
  Assert.AreEqual(9950, mMap.DragTop(499, 0, 50));
end;

procedure TAtlasMinimapTests.SectionHeadersFromOutline;
var
  mNodes: TAtlasOutlineNodes;
  mMap: TAtlasMinimapMap;
  mHeaders: TAtlasMinimapHeaders;
  mLocal: TAtlasOutlineNode;
begin
  mNodes := [
    Node('TFoo', 5, TAtlasOutlineCategory.TypeDecl, 5, 20, -1),
    Node('Bar', 6, TAtlasOutlineCategory.Method, 7, 7, 0),
    Node('TKind', 10, TAtlasOutlineCategory.TypeDecl, 22, 22, -1),
    Node('TFoo.Bar', 6, TAtlasOutlineCategory.Routine, 30, 40, -1),
    Node('Helper', 12, TAtlasOutlineCategory.Routine, 31, 33, -1),
    Node('Free', 12, TAtlasOutlineCategory.Routine, 50, 60, -1)];
  mLocal := Node('Inner', 12, TAtlasOutlineCategory.Routine, 52, 54, 5);
  mLocal.InBody := True;
  mNodes := mNodes + [mLocal];
  mNodes[3].Hidden := True;
  mMap := TAtlasMinimapMap.Create(100, nil, 2, 500);
  mHeaders := TAtlasMinimap.Headers(mNodes, mMap, 8);
  Assert.AreEqual(3, Integer(Length(mHeaders)), 'Methodendeklaration, Aufzählung, lokale und überdeckte fallen weg');
  Assert.AreEqual('TFoo', mHeaders[0].Text);
  Assert.IsTrue(mHeaders[0].IsType);
  Assert.AreEqual(10, mHeaders[0].Top);
  Assert.AreEqual('TFoo.Bar', mHeaders[1].Text);
  Assert.IsFalse(mHeaders[1].IsType);
  Assert.AreEqual(60, mHeaders[1].Top);
  Assert.AreEqual(3, mHeaders[1].Node);
  Assert.AreEqual('Free', mHeaders[2].Text);
  Assert.AreEqual(50, mHeaders[2].Line);
  // Unten ohne Platz für die Beschriftung: weg.
  mMap := TAtlasMinimapMap.Create(100, nil, 2, 200);
  mHeaders := TAtlasMinimap.Headers(mNodes + [Node('Last', 12, TAtlasOutlineCategory.Routine, 97, 99, -1)], mMap, 8);
  Assert.AreEqual(3, Integer(Length(mHeaders)));
  // In einer Faltung: an der Kopfzeile.
  mMap := TAtlasMinimapMap.Create(100, [Fold(25, 10)], 2, 500);
  mHeaders := TAtlasMinimap.Headers(mNodes, mMap, 8);
  Assert.AreEqual(50, mHeaders[1].Top);
end;

procedure TAtlasMinimapTests.CurrentMethodRange;
var
  mNodes: TAtlasOutlineNodes;
  mLocal: TAtlasOutlineNode;
  mFirst, mLast: Integer;
begin
  mNodes := [
    Node('TFoo', 5, TAtlasOutlineCategory.TypeDecl, 5, 20, -1),
    Node('Bar', 6, TAtlasOutlineCategory.Method, 7, 7, 0),
    Node('TFoo.Bar', 6, TAtlasOutlineCategory.Routine, 30, 40, -1)];
  mLocal := Node('Inner', 12, TAtlasOutlineCategory.Routine, 32, 35, 2);
  mLocal.InBody := True;
  mNodes := mNodes + [mLocal];
  Assert.IsTrue(TAtlasMinimap.MethodAt(mNodes, 33, mFirst, mLast));
  Assert.AreEqual(32, mFirst, 'die innerste');
  Assert.AreEqual(35, mLast);
  Assert.IsTrue(TAtlasMinimap.MethodAt(mNodes, 38, mFirst, mLast));
  Assert.AreEqual(30, mFirst);
  Assert.AreEqual(40, mLast);
  Assert.IsFalse(TAtlasMinimap.MethodAt(mNodes, 7, mFirst, mLast), 'Deklaration in der Klasse');
  Assert.IsFalse(TAtlasMinimap.MethodAt(mNodes, 50, mFirst, mLast));
  Assert.AreEqual(-1, mFirst);
end;

procedure TAtlasMinimapTests.MarkersMapToRows;
var
  mMarks: TAtlasOverviewMarks;
  mMap: TAtlasMinimapMap;
  mBars: TAtlasOverviewBars;
  mBar: TAtlasOverviewBar;
  mFound: Integer;
begin
  mMarks := [
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Cursor, 3, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, 4, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Breakpoint, 5, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Added, 10, 3),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 60, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 61, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 50, 1)];
  mMap := TAtlasMinimapMap.Create(100, [Fold(48, 5)], 2, 500);
  mBars := TAtlasMinimap.MarkerBars(mMarks, mMap, 2);
  Assert.AreEqual(3, Integer(Length(mBars)), 'ohne Cursor, Lesezeichen, Haltepunkt; Treffer zusammengefasst');
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Added), Ord(mBars[0].Kind));
  Assert.AreEqual(Ord(TAtlasOverviewLane.Left), Ord(mBars[0].Lane), 'Änderungen am linken Rand');
  Assert.AreEqual(20, mBars[0].Top);
  Assert.AreEqual(26, mBars[0].Bottom);
  mFound := 0;
  for mBar in mBars do
  begin
    if mBar.Kind = TAtlasOverviewMarkKind.Search then
    begin
      Inc(mFound);
      Assert.AreEqual(Ord(TAtlasOverviewLane.Full), Ord(mBar.Lane), 'Zeilenband');
      Assert.AreEqual(110, mBar.Top);
      Assert.AreEqual(114, mBar.Bottom);
    end;
  end;
  Assert.AreEqual(1, mFound);
  // Der Fehler liegt in der Faltung: auf ihrer Kopfzeile, wichtigste Art zuletzt.
  Assert.AreEqual(Ord(TAtlasOverviewMarkKind.Error), Ord(mBars[2].Kind));
  Assert.AreEqual(96, mBars[2].Top);
  Assert.AreEqual(6, mBars[2].Mark);
  Assert.AreEqual<TAtlasOverviewKinds>([TAtlasOverviewKind.Diagnostics, TAtlasOverviewKind.Search,
    TAtlasOverviewKind.Changes], TAtlasMinimap.MarkerKinds);
end;

procedure TAtlasMinimapTests.RunsPerWord;
var
  mLine: TAtlasMinimapLine;
  mLines: TAtlasMinimapLines;
begin
  mLines := TAtlasMinimap.Runs(['  if Foo then // x', #9'a', 'abcdefgh', '{ offen', 'zu }', ''], 5, 4);
  Assert.AreEqual(6, Integer(Length(mLines)));
  mLines := TAtlasMinimap.Runs(['  if Foo then // x'], 120, 4);
  mLine := mLines[0];
  Assert.AreEqual(5, Integer(Length(mLine)));
  Assert.AreEqual(2, mLine[0].Start);
  Assert.AreEqual(4, mLine[0].Stop);
  Assert.AreEqual(Ord(TAtlasTokenKind.Keyword), Ord(mLine[0].Kind));
  Assert.AreEqual(5, mLine[1].Start);
  Assert.AreEqual(8, mLine[1].Stop);
  Assert.AreEqual(Ord(TAtlasTokenKind.Plain), Ord(mLine[1].Kind));
  Assert.AreEqual(Ord(TAtlasTokenKind.Keyword), Ord(mLine[2].Kind));
  Assert.AreEqual(Ord(TAtlasTokenKind.Comment), Ord(mLine[3].Kind));
  Assert.AreEqual(14, mLine[3].Start);
  Assert.AreEqual(17, mLine[4].Start);
  Assert.AreEqual(Ord(TAtlasTokenKind.Comment), Ord(mLine[4].Kind));
  // Tabulator klappt auf die nächste Stufe aus.
  mLines := TAtlasMinimap.Runs([#9'a', ' '#9'b'], 120, 4);
  Assert.AreEqual(4, mLines[0][0].Start);
  Assert.AreEqual(4, mLines[1][0].Start);
  // Höchste Spalte schneidet ab.
  mLines := TAtlasMinimap.Runs(['abcdefgh', '      xy'], 5, 4);
  Assert.AreEqual(1, Integer(Length(mLines[0])));
  Assert.AreEqual(5, mLines[0][0].Stop);
  Assert.AreEqual(0, Integer(Length(mLines[1])), 'erst nach der höchsten Spalte');
  // Ausgeklappt für die Darstellung „characters“.
  Assert.AreEqual('    a', TAtlasMinimap.Expand(#9'a', 120, 4));
  Assert.AreEqual('x   b', TAtlasMinimap.Expand('x'#9'b', 120, 4));
  Assert.AreEqual('abc', TAtlasMinimap.Expand('abcdef', 3, 4));
  Assert.AreEqual('a ', TAtlasMinimap.Expand('a'#9'b', 2, 4), 'Tabulator am Rand geklemmt');
  // Mehrzeiliger Kommentar bleibt Kommentar.
  mLines := TAtlasMinimap.Runs(['{ offen', 'zu }'], 120, 4);
  Assert.AreEqual(Ord(TAtlasTokenKind.Comment), Ord(mLines[1][0].Kind));
end;

procedure TAtlasMinimapTests.ChangedLinesOnly;
var
  mOld, mNew: TAtlasMinimapLines;
  mChanged: TArray<Integer>;
begin
  mOld := TAtlasMinimap.Runs(['a := 1;', 'b := 2;', 'c := 3;'], 120, 4);
  mNew := TAtlasMinimap.Runs(['a := 1;', 'bb := 2;', 'c := 3;', 'd;'], 120, 4);
  mChanged := TAtlasMinimap.ChangedLines(mOld, mNew);
  Assert.AreEqual(2, Integer(Length(mChanged)));
  Assert.AreEqual(1, mChanged[0]);
  Assert.AreEqual(3, mChanged[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasMinimap.ChangedLines(mOld, mOld))));
  Assert.IsTrue(TAtlasMinimap.SameLine(mOld[0], mNew[0]));
  Assert.IsFalse(TAtlasMinimap.SameLine(mOld[1], mNew[1]));
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
  mFolds: TAtlasMinimapFolds;
begin
  // Zeilenhöhe 16: auf Zeile 11 folgt direkt Zeile 20, dazwischen ist gefaltet.
  mFolds := TAtlasMinimap.Folds(nil, [TAtlasMinimapPainted.Create(32, 20), TAtlasMinimapPainted.Create(0, 10),
    TAtlasMinimapPainted.Create(16, 11)], 16, 100);
  Assert.AreEqual(1, Integer(Length(mFolds)));
  Assert.AreEqual(11, mFolds[0].Line);
  Assert.AreEqual(8, mFolds[0].Hidden);
  // Nicht direkt untereinander (Teil neu gemalt): sagt nichts.
  mFolds := TAtlasMinimap.Folds(nil, [TAtlasMinimapPainted.Create(0, 10), TAtlasMinimapPainted.Create(48, 30)], 16,
    100);
  Assert.AreEqual(0, Integer(Length(mFolds)));
  // Aufgeklappt: Kopfzeile und Folgezeile stehen untereinander; ein anderer bekannter Bereich bleibt.
  mFolds := TAtlasMinimap.Folds([Fold(11, 8), Fold(50, 3)], [TAtlasMinimapPainted.Create(0, 11),
    TAtlasMinimapPainted.Create(16, 12)], 16, 100);
  Assert.AreEqual(1, Integer(Length(mFolds)));
  Assert.AreEqual(50, mFolds[0].Line);
  // Geändert: der neue Stand gilt.
  mFolds := TAtlasMinimap.Folds([Fold(11, 8)], [TAtlasMinimapPainted.Create(0, 11),
    TAtlasMinimapPainted.Create(16, 15)], 16, 100);
  Assert.AreEqual(3, mFolds[0].Hidden);
  Assert.IsTrue(TAtlasMinimap.SameFolds([Fold(11, 3)], mFolds));
  Assert.IsFalse(TAtlasMinimap.SameFolds([Fold(11, 4)], mFolds));
end;

procedure TAtlasMinimapTests.NormalizeNestedFolds;
var
  mFolds: TAtlasMinimapFolds;
begin
  mFolds := TAtlasMinimap.NormalizeFolds([Fold(40, 0), Fold(12, 2), Fold(10, 10), Fold(18, 6), Fold(95, 20),
    Fold(-1, 3), Fold(99, 1)], 100);
  Assert.AreEqual(2, Integer(Length(mFolds)));
  Assert.AreEqual(10, mFolds[0].Line);
  Assert.AreEqual(14, mFolds[0].Hidden, 'verschachtelte gehen auf, überstehende verlängern');
  Assert.AreEqual(95, mFolds[1].Line);
  Assert.AreEqual(4, mFolds[1].Hidden, 'am Dateiende geklemmt');
end;

procedure TAtlasMinimapTests.NoticeOnlyOnce;
begin
  Assert.IsTrue(TAtlasMinimap.ShouldNotice(True, True, False));
  Assert.IsFalse(TAtlasMinimap.ShouldNotice(True, True, True));
  Assert.IsFalse(TAtlasMinimap.ShouldNotice(True, False, False));
  Assert.IsFalse(TAtlasMinimap.ShouldNotice(False, True, False));
end;

end.
