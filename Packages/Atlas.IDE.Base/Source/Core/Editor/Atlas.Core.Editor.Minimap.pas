unit Atlas.Core.Editor.Minimap;

// Minimap neben der Scrollleiste (#873, experimentell), ohne VCL und OTA:
// - Options liest die Einstellungen editor.minimap.* (Darstellung, Breite,
//   Maßstab, höchste Spalte, Seite, Schieber, Überschriften, Methode, Marken,
//   Klick) und klemmt sie; unbekannte Namen fallen auf die Vorgabe.
// - TAtlasMinimapMap rechnet zwischen Editorzeile, Minimap-Zeile und Pixel:
//   Ein gefalteter Bereich nimmt nur eine Zeile ein (die Kopfzeile), damit
//   Mausposition und Editorzeile übereinstimmen. Passt die Datei mit festen
//   Pixeln je Zeile (2 × Maßstab) nicht in die Höhe, wird sie gestaucht:
//   Jede Zeile bekommt ihren Anteil an der Höhe.
// - Schieber: Lage und Höhe des sichtbaren Bereichs, Ziel beim Ziehen und
//   beim Klick (Klick zentriert die Zeile unter der Maus).
// - Headers wählt Klassen-, Record- und Interface-Namen sowie Routinen
//   außerhalb von Typen (Rümpfe im implementation-Teil) aus der Gliederung
//   (#395) als Überschriften; überlappende Beschriftungen fallen weg.
// - MethodAt findet die innerste Routine am Cursor (Hinterlegung).
// - MarkerBars ordnet die Marken der Übersichtsleiste (#519) der Minimap zu:
//   Änderungen als Streifen am linken Rand, Befunde und Suchtreffer als
//   Zeilenband; gefaltete Zeilen landen auf ihrer Kopfzeile.
// - Runs zerlegt die Zeilen nach der Syntaxfärbung in Balken je Wort, mit
//   ausgeklappten Tabulatoren und bis zur höchsten Spalte; GlyphHeight gibt
//   die Höhe eines winzigen Zeichens in der Darstellung „characters“.
// - Folds erkennt gefaltete Bereiche aus den gezeichneten Zeilen: Folgen
//   zwei Bildschirmzeilen mit einem Sprung in der Editorzeile aufeinander,
//   ist dazwischen gefaltet.
// Zeilen sind 0-basiert.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Syntax,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Overview;

type
{$SCOPEDENUMS ON}
  TAtlasMinimapRender = (Blocks, Characters);
  TAtlasMinimapSide = (Right, Left);
  TAtlasMinimapSlider = (Always, MouseOver);
{$SCOPEDENUMS OFF}

  TAtlasMinimapOptions = record
    Render: TAtlasMinimapRender;
    /// <summary>Breite in Pixeln bei 96 DPI.</summary>
    Width: Integer;
    /// <summary>Maßstab 1 bis 3; Pixel je Zeile = 2 × Maßstab.</summary>
    Scale: Integer;
    MaxColumn: Integer;
    Side: TAtlasMinimapSide;
    Slider: TAtlasMinimapSlider;
    SectionHeaders: Boolean;
    HighlightMethod: Boolean;
    Markers: Boolean;
    ClickJumps: Boolean;
    /// <summary>Pixel je Zeile bei 96 DPI.</summary>
    function RowHeight: Integer;
    /// <summary>Linker Rand der Spalte AColumn bei AWidth Pixeln Breite.</summary>
    function ColumnX(AColumn, AWidth: Integer): Integer;
  end;

  /// <summary>Gefalteter Bereich: Kopfzeile Line bleibt sichtbar, die Hidden Zeilen danach nicht.</summary>
  TAtlasMinimapFold = record
    Line: Integer;
    Hidden: Integer;
    class function Create(ALine, AHidden: Integer): TAtlasMinimapFold; static;
  end;

  TAtlasMinimapFolds = TArray<TAtlasMinimapFold>;

  /// <summary>Gezeichnete Bildschirmzeile: oberer Rand in Pixeln und Editorzeile (0-basiert).</summary>
  TAtlasMinimapPainted = record
    Top: Integer;
    Line: Integer;
    class function Create(ATop, ALine: Integer): TAtlasMinimapPainted; static;
  end;

  /// <summary>Pixelbereich von Top bis Bottom (ausschließlich).</summary>
  TAtlasMinimapSpan = record
    Top: Integer;
    Bottom: Integer;
  end;

  /// <summary>Umrechnung Zeile ↔ Minimap-Zeile ↔ Pixel für eine Datei.</summary>
  TAtlasMinimapMap = record
    LineCount: Integer;
    /// <summary>Zeilen der Minimap (Zeilen ohne verborgene).</summary>
    RowCount: Integer;
    RowHeight: Integer;
    Height: Integer;
    Folds: TAtlasMinimapFolds;
    /// <summary>Verschiebung des Inhalts nach oben in Pixeln, wenn er höher ist als die Minimap (Follow).</summary>
    Offset: Integer;
    /// <summary>AFolds werden geordnet und geklemmt (siehe TAtlasMinimap.NormalizeFolds).</summary>
    class function Create(ALineCount: Integer; const AFolds: TAtlasMinimapFolds;
      ARowHeight, AHeight: Integer): TAtlasMinimapMap; static;
    /// <summary>Gestaucht wird nicht mehr: Passt der Inhalt nicht, scrollt die Minimap mit (wie VS Code). Immer False;
    /// bleibt für die Stellen, die bei gestauchten Zeilen anders zeichneten.</summary>
    function Compressed: Boolean;
    /// <summary>Höhe des ganzen Inhalts in Pixeln (alle Zeilen in voller Höhe).</summary>
    function TotalHeight: Int64;
    /// <summary>Offset aus der Lage im Editor: oben der Anfang, unten das Ende, dazwischen anteilig. True, wenn
    /// sich der Offset geändert hat.</summary>
    function Follow(ATopLine, ABottomLine: Integer): Boolean;
    /// <summary>Höhe des gezeichneten Inhalts (höchstens Height).</summary>
    function ContentHeight: Integer;
    /// <summary>Minimap-Zeile der Editorzeile; verborgene Zeilen gehören zu ihrer Kopfzeile.</summary>
    function RowOf(ALine: Integer): Integer;
    function LineOf(ARow: Integer): Integer;
    /// <summary>Oberer Rand der Minimap-Zeile ARow; ARow = RowCount ist das Ende des Inhalts.</summary>
    function PixelOfRow(ARow: Integer): Integer;
    /// <summary>Minimap-Zeile am Pixel AY (geklemmt).</summary>
    function RowAt(AY: Integer): Integer;
    function PixelOfLine(ALine: Integer): Integer;
    /// <summary>Editorzeile am Pixel AY (geklemmt).</summary>
    function LineAt(AY: Integer): Integer;
    /// <summary>Sichtbare Minimap-Zeilen zwischen ATopLine und ABottomLine (mindestens 1).</summary>
    function VisibleRows(ATopLine, ABottomLine: Integer): Integer;
    /// <summary>Schieber über ATopLine bis ABottomLine, mindestens AMinHeight hoch.</summary>
    function Slider(ATopLine, ABottomLine, AMinHeight: Integer): TAtlasMinimapSpan;
    /// <summary>Oberste Editorzeile beim Ziehen: Maus bei AY, gegriffen AGrab Pixel unter dem oberen Rand des
    /// Schiebers.</summary>
    function DragTop(AY, AGrab, AVisibleRows: Integer): Integer;
    /// <summary>Oberste Editorzeile nach einem Klick bei AY: die Zeile unter der Maus steht in der Mitte.</summary>
    function ClickTop(AY, AVisibleRows: Integer): Integer;
  end;

  TAtlasMinimapHeader = record
    /// <summary>Knoten in der Gliederung.</summary>
    Node: Integer;
    Line: Integer;
    Text: string;
    /// <summary>Typ (Klasse, Record, Interface); sonst Routine.</summary>
    IsType: Boolean;
    /// <summary>Oberer Rand der Beschriftung in Pixeln.</summary>
    Top: Integer;
  end;

  TAtlasMinimapHeaders = TArray<TAtlasMinimapHeader>;

  /// <summary>Balken eines Worts in Spalten (Start bis Stop ausschließlich, Tabulatoren ausgeklappt).</summary>
  TAtlasMinimapRun = record
    Start: Integer;
    Stop: Integer;
    Kind: TAtlasTokenKind;
  end;

  TAtlasMinimapLine = TArray<TAtlasMinimapRun>;
  TAtlasMinimapLines = TArray<TAtlasMinimapLine>;

  TAtlasMinimap = class
  public const
    DefaultWidth = 120;
    MinWidth = TAtlasPluginSettings.MinMinimapWidth;
    MaxWidth = TAtlasPluginSettings.MaxMinimapWidth;
    DefaultScale = 2;
    MinScale = TAtlasPluginSettings.MinMinimapScale;
    MaxScale = TAtlasPluginSettings.MaxMinimapScale;
    DefaultMaxColumn = 120;
    MinColumn = TAtlasPluginSettings.MinMinimapColumn;
    MaxColumnLimit = TAtlasPluginSettings.MaxMinimapColumn;
    RenderNames: array[TAtlasMinimapRender] of string = ('blocks', 'characters');
    SideNames: array[TAtlasMinimapSide] of string = ('right', 'left');
    SliderNames: array[TAtlasMinimapSlider] of string = ('always', 'mouseover');
    /// <summary>Höchstzahl der gemerkten gefalteten Bereiche.</summary>
    MaxFolds = 2000;
  public
    /// <summary>Vorgaben aus dem Katalog (#873).</summary>
    class function Defaults: TAtlasMinimapOptions; static;
    /// <summary>Einstellungen als Optionen: Namen ohne Groß-/Kleinschreibung, unbekannte als Vorgabe, Zahlen
    /// geklemmt.</summary>
    class function Options(const ARender, ASide, ASlider: string; AWidth, AScale, AMaxColumn: Integer;
      ASectionHeaders, AHighlightMethod, AMarkers, AClickJumps: Boolean): TAtlasMinimapOptions; static;
    class function RenderOf(const AName: string): TAtlasMinimapRender; static;
    class function SideOf(const AName: string): TAtlasMinimapSide; static;
    class function SliderOf(const AName: string): TAtlasMinimapSlider; static;
    class function ClampWidth(AValue: Integer): Integer; static;
    class function ClampScale(AValue: Integer): Integer; static;
    class function ClampColumn(AValue: Integer): Integer; static;
    /// <summary>Aufsteigend nach Kopfzeile; Bereiche ohne verborgene Zeilen fallen weg, verschachtelte gehen im
    /// äußeren auf, das Ende bleibt in der Datei.</summary>
    class function NormalizeFolds(const AFolds: TAtlasMinimapFolds; ALineCount: Integer): TAtlasMinimapFolds;
      static;
    /// <summary>Gefaltete Bereiche nach einem Malvorgang: AKnown sind die bisher bekannten, APainted die gemalten
    /// Bildschirmzeilen mit Zeilenhöhe ARowHeight. Ein Sprung zwischen direkt aufeinanderfolgenden Zeilen ist
    /// ein gefalteter Bereich; ein bekannter, dessen Kopfzeile und Folgezeile jetzt direkt untereinander
    /// stehen, ist aufgeklappt.</summary>
    class function Folds(const AKnown: TAtlasMinimapFolds; const APainted: TArray<TAtlasMinimapPainted>;
      ARowHeight, ALineCount: Integer): TAtlasMinimapFolds; static;
    class function SameFolds(const A, B: TAtlasMinimapFolds): Boolean; static;
    /// <summary>Überschriften für Typen und Routinen außerhalb von Typen, je ALabelHeight Pixel hoch; eine, die
    /// eine frühere überdecken würde, fällt weg.</summary>
    class function Headers(const ANodes: TAtlasOutlineNodes; const AMap: TAtlasMinimapMap;
      ALabelHeight: Integer): TAtlasMinimapHeaders; static;
    /// <summary>Innerste Routine, die ALine enthält; False ohne.</summary>
    class function MethodAt(const ANodes: TAtlasOutlineNodes; ALine: Integer;
      out AStartLine, AEndLine: Integer): Boolean; static;
    /// <summary>Marken als Balken: Änderungen am linken Rand (Lane Left), Befunde und Suchtreffer als Zeilenband
    /// (Lane Full); Cursor, Haltepunkte und Lesezeichen gehören nicht in die Minimap. Gleiche Art auf
    /// demselben Pixel wird zusammengefasst; wichtigere Arten liegen zuletzt.</summary>
    class function MarkerBars(const AMarks: TAtlasOverviewMarks; const AMap: TAtlasMinimapMap;
      AMinHeight: Integer): TAtlasOverviewBars; static;
    /// <summary>Arten der Übersichtsleiste, die die Minimap zeigt.</summary>
    class function MarkerKinds: TAtlasOverviewKinds; static;
    /// <summary>Balken je Zeile: Tokens der Syntaxfärbung, an Leerraum getrennt, bis AMaxColumn.</summary>
    class function Runs(const ALines: TArray<string>; AMaxColumn, ATabWidth: Integer): TAtlasMinimapLines; static;
    /// <summary>Balken einer Zeile zu ihren Tokens.</summary>
    class function LineRuns(const ALine: string; const ATokens: TAtlasTokens;
      AMaxColumn, ATabWidth: Integer): TAtlasMinimapLine; static;
    class function SameLine(const A, B: TAtlasMinimapLine): Boolean; static;
    /// <summary>Zeile mit ausgeklappten Tabulatoren, höchstens AMaxColumn Zeichen: Zeichen der Spalte c ist
    /// Result[c + 1] (Darstellung „characters“).</summary>
    class function Expand(const ALine: string; AMaxColumn, ATabWidth: Integer): string; static;
    /// <summary>Zeilen, deren Balken sich zwischen AOld und ANew unterscheiden (für „nur geänderte Zeilen
    /// zeichnen“); bei anderer Zeilenzahl auch alle Zeilen ab der kürzeren.</summary>
    class function ChangedLines(const AOld, ANew: TAtlasMinimapLines): TArray<Integer>; static;
    /// <summary>Höhe eines winzigen Zeichens in einer Zeile von ARowHeight Pixeln: Großbuchstaben, Ziffern und
    /// Klammern ganz, Kleinbuchstaben zwei Drittel, Satzzeichen ein Pixel, Leerraum 0.</summary>
    class function GlyphHeight(AChar: Char; ARowHeight: Integer): Integer; static;
    /// <summary>Hinweis „IDE-Minimap ist auch sichtbar“ zeigen: Atlas-Minimap an, die der IDE sichtbar, noch
    /// nicht gezeigt.</summary>
    class function ShouldNotice(AOurs, AIdeVisible, AShown: Boolean): Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Chars;

const
  KindClass = 5;
  KindMethod = 6;
  KindConstructor = 9;
  KindInterface = 11;
  KindFunction = 12;
  KindObject = 19;
  KindStruct = 23;

function IsRoutine(AKind: Integer): Boolean;
begin
  Result := (AKind = KindMethod) or (AKind = KindConstructor) or (AKind = KindFunction);
end;

function IsHeaderType(AKind: Integer): Boolean;
begin
  Result := (AKind = KindClass) or (AKind = KindInterface) or (AKind = KindObject) or (AKind = KindStruct);
end;

{ TAtlasMinimapOptions }

function TAtlasMinimapOptions.RowHeight: Integer;
begin
  Result := 2 * TAtlasMinimap.ClampScale(Scale);
end;

function TAtlasMinimapOptions.ColumnX(AColumn, AWidth: Integer): Integer;
begin
  Result := Integer((Int64(EnsureRange(AColumn, 0, MaxColumn)) * Max(0, AWidth)) div Max(1, MaxColumn));
end;

{ TAtlasMinimapFold }

class function TAtlasMinimapFold.Create(ALine, AHidden: Integer): TAtlasMinimapFold;
begin
  Result.Line := ALine;
  Result.Hidden := AHidden;
end;

{ TAtlasMinimapPainted }

class function TAtlasMinimapPainted.Create(ATop, ALine: Integer): TAtlasMinimapPainted;
begin
  Result.Top := ATop;
  Result.Line := ALine;
end;

{ TAtlasMinimapMap }

class function TAtlasMinimapMap.Create(ALineCount: Integer; const AFolds: TAtlasMinimapFolds;
  ARowHeight, AHeight: Integer): TAtlasMinimapMap;
var
  Fold: TAtlasMinimapFold;
begin
  Result.LineCount := Max(0, ALineCount);
  Result.RowHeight := Max(1, ARowHeight);
  Result.Height := Max(0, AHeight);
  Result.Folds := TAtlasMinimap.NormalizeFolds(AFolds, Result.LineCount);
  Result.RowCount := Result.LineCount;
  for Fold in Result.Folds do
    Dec(Result.RowCount, Fold.Hidden);
  Result.Offset := 0;
end;

function TAtlasMinimapMap.Compressed: Boolean;
begin
  Result := False;
end;

function TAtlasMinimapMap.TotalHeight: Int64;
begin
  Result := Int64(Max(0, RowCount)) * RowHeight;
end;

function TAtlasMinimapMap.Follow(ATopLine, ABottomLine: Integer): Boolean;
var
  Overflow: Int64;
  Scrollable, Top, NewOffset: Integer;
begin
  Overflow := TotalHeight - Height;
  NewOffset := 0;
  if (Overflow > 0) and (RowCount > 0) then
  begin
    // Anteil der Lage im Editor: 0 ganz oben, 1 ganz unten (letzte Seite sichtbar).
    Scrollable := Max(1, RowCount - VisibleRows(ATopLine, Max(ATopLine, ABottomLine)));
    Top := EnsureRange(RowOf(ATopLine), 0, Scrollable);
    NewOffset := Integer((Overflow * Top) div Scrollable);
  end;
  Result := NewOffset <> Offset;
  Offset := NewOffset;
end;

function TAtlasMinimapMap.ContentHeight: Integer;
begin
  Result := Integer(Max(0, Min(TotalHeight - Offset, Int64(Height))));
end;

function TAtlasMinimapMap.RowOf(ALine: Integer): Integer;
var
  Fold: TAtlasMinimapFold;
  Line, HiddenBefore: Integer;
begin
  if LineCount <= 0 then
    Exit(0);
  Line := EnsureRange(ALine, 0, LineCount - 1);
  HiddenBefore := 0;
  for Fold in Folds do
  begin
    if Fold.Line >= Line then
      Break;
    // In der Faltung verborgen: Zeile der Kopfzeile.
    if Line <= Fold.Line + Fold.Hidden then
      Exit(Fold.Line - HiddenBefore);
    Inc(HiddenBefore, Fold.Hidden);
  end;
  Result := Line - HiddenBefore;
end;

function TAtlasMinimapMap.LineOf(ARow: Integer): Integer;
var
  Fold: TAtlasMinimapFold;
  Row, HiddenBefore: Integer;
begin
  if RowCount <= 0 then
    Exit(0);
  Row := EnsureRange(ARow, 0, RowCount - 1);
  HiddenBefore := 0;
  for Fold in Folds do
  begin
    if Fold.Line - HiddenBefore >= Row then
      Break;
    Inc(HiddenBefore, Fold.Hidden);
  end;
  Result := Min(Row + HiddenBefore, LineCount - 1);
end;

function TAtlasMinimapMap.PixelOfRow(ARow: Integer): Integer;
var
  Row: Integer;
begin
  if (RowCount <= 0) or (Height <= 0) then
    Exit(0);
  Row := EnsureRange(ARow, 0, RowCount);
  Result := Row * RowHeight - Offset;
end;

function TAtlasMinimapMap.RowAt(AY: Integer): Integer;
begin
  if (RowCount <= 0) or (Height <= 0) then
    Exit(0);
  Result := (Max(0, AY) + Offset) div RowHeight;
  Result := EnsureRange(Result, 0, RowCount - 1);
end;

function TAtlasMinimapMap.PixelOfLine(ALine: Integer): Integer;
begin
  Result := PixelOfRow(RowOf(ALine));
end;

function TAtlasMinimapMap.LineAt(AY: Integer): Integer;
begin
  Result := LineOf(RowAt(AY));
end;

function TAtlasMinimapMap.VisibleRows(ATopLine, ABottomLine: Integer): Integer;
begin
  Result := Max(1, RowOf(ABottomLine) - RowOf(ATopLine) + 1);
end;

function TAtlasMinimapMap.Slider(ATopLine, ABottomLine, AMinHeight: Integer): TAtlasMinimapSpan;
var
  MinHeight: Integer;
begin
  Result.Top := 0;
  Result.Bottom := 0;
  if (RowCount <= 0) or (Height <= 0) then
    Exit;
  MinHeight := Min(Max(1, AMinHeight), Height);
  Result.Top := PixelOfRow(RowOf(ATopLine));
  Result.Bottom := Max(PixelOfRow(RowOf(Max(ATopLine, ABottomLine)) + 1), Result.Top + MinHeight);
  if Result.Bottom > Height then
  begin
    Result.Bottom := Height;
    Result.Top := Max(0, Min(Result.Top, Height - MinHeight));
  end;
end;

function TAtlasMinimapMap.DragTop(AY, AGrab, AVisibleRows: Integer): Integer;
var
  Row: Integer;
begin
  if RowCount <= 0 then
    Exit(0);
  if TotalHeight > Height then
    // Mitscrollend (Follow): Die Oberkante des Schiebers läuft linear von 0 bis Height − Schieberhöhe, während die
    // oberste Zeile von 0 bis RowCount − AVisibleRows läuft. Umkehrung davon; der Offset ändert sich beim Ziehen mit
    // und darf nicht in die Rechnung eingehen, sonst läuft der Schieber davon.
    Row := Integer((Int64(Max(0, AY - AGrab)) * Max(1, RowCount - Max(1, AVisibleRows))) div
      Max(1, Height - Max(1, AVisibleRows) * RowHeight))
  else
    Row := RowAt(AY - AGrab);
  // Ganz oben gegriffen und darüber hinaus gezogen: erste Zeile.
  if AY - AGrab <= 0 then
    Row := 0;
  Row := EnsureRange(Row, 0, Max(0, RowCount - Max(1, AVisibleRows)));
  Result := LineOf(Row);
end;

function TAtlasMinimapMap.ClickTop(AY, AVisibleRows: Integer): Integer;
var
  Row: Integer;
begin
  if RowCount <= 0 then
    Exit(0);
  Row := RowAt(AY) - Max(1, AVisibleRows) div 2;
  Row := EnsureRange(Row, 0, Max(0, RowCount - Max(1, AVisibleRows)));
  Result := LineOf(Row);
end;

{ TAtlasMinimap }

class function TAtlasMinimap.Defaults: TAtlasMinimapOptions;
begin
  // Winzige Zeichen wie VS Code; Balken je Wort sind die Alternative.
  Result.Render := TAtlasMinimapRender.Characters;
  Result.Width := DefaultWidth;
  Result.Scale := DefaultScale;
  Result.MaxColumn := DefaultMaxColumn;
  Result.Side := TAtlasMinimapSide.Right;
  Result.Slider := TAtlasMinimapSlider.Always;
  Result.SectionHeaders := True;
  Result.HighlightMethod := True;
  Result.Markers := True;
  Result.ClickJumps := True;
end;

class function TAtlasMinimap.Options(const ARender, ASide, ASlider: string; AWidth, AScale, AMaxColumn: Integer;
  ASectionHeaders, AHighlightMethod, AMarkers, AClickJumps: Boolean): TAtlasMinimapOptions;
begin
  Result.Render := RenderOf(ARender);
  Result.Width := ClampWidth(AWidth);
  Result.Scale := ClampScale(AScale);
  Result.MaxColumn := ClampColumn(AMaxColumn);
  Result.Side := SideOf(ASide);
  Result.Slider := SliderOf(ASlider);
  Result.SectionHeaders := ASectionHeaders;
  Result.HighlightMethod := AHighlightMethod;
  Result.Markers := AMarkers;
  Result.ClickJumps := AClickJumps;
end;

class function TAtlasMinimap.RenderOf(const AName: string): TAtlasMinimapRender;
var
  Render: TAtlasMinimapRender;
begin
  for Render := Low(TAtlasMinimapRender) to High(TAtlasMinimapRender) do
    if SameText(Trim(AName), RenderNames[Render]) then
      Exit(Render);
  Result := TAtlasMinimapRender.Characters;
end;

class function TAtlasMinimap.SideOf(const AName: string): TAtlasMinimapSide;
var
  Side: TAtlasMinimapSide;
begin
  for Side := Low(TAtlasMinimapSide) to High(TAtlasMinimapSide) do
    if SameText(Trim(AName), SideNames[Side]) then
      Exit(Side);
  Result := TAtlasMinimapSide.Right;
end;

class function TAtlasMinimap.SliderOf(const AName: string): TAtlasMinimapSlider;
var
  Slider: TAtlasMinimapSlider;
begin
  for Slider := Low(TAtlasMinimapSlider) to High(TAtlasMinimapSlider) do
    if SameText(Trim(AName), SliderNames[Slider]) then
      Exit(Slider);
  Result := TAtlasMinimapSlider.Always;
end;

class function TAtlasMinimap.ClampWidth(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, MinWidth, MaxWidth);
end;

class function TAtlasMinimap.ClampScale(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, MinScale, MaxScale);
end;

class function TAtlasMinimap.ClampColumn(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, MinColumn, MaxColumnLimit);
end;

class function TAtlasMinimap.NormalizeFolds(const AFolds: TAtlasMinimapFolds; ALineCount: Integer):
  TAtlasMinimapFolds;
var
  Sorted: TAtlasMinimapFolds;
  Fold, Moved: TAtlasMinimapFold;
  Index, Position, Last, Stop: Integer;
begin
  Result := nil;
  // Gültige Bereiche, nach Kopfzeile sortiert (Einfügen; die Listen sind meist schon sortiert).
  Sorted := nil;
  for Fold in AFolds do
  begin
    if (Fold.Hidden < 1) or (Fold.Line < 0) or (Fold.Line >= ALineCount - 1) then
      Continue;
    Sorted := Sorted + [TAtlasMinimapFold.Create(Fold.Line, Min(Fold.Hidden, ALineCount - 1 - Fold.Line))];
    Position := High(Sorted);
    while (Position > 0) and (Sorted[Position - 1].Line > Sorted[Position].Line) do
    begin
      Moved := Sorted[Position - 1];
      Sorted[Position - 1] := Sorted[Position];
      Sorted[Position] := Moved;
      Dec(Position);
    end;
  end;
  for Index := 0 to High(Sorted) do
  begin
    Last := High(Result);
    if (Last >= 0) and (Sorted[Index].Line <= Result[Last].Line + Result[Last].Hidden) then
    begin
      // Kopfzeile liegt im vorigen Bereich (oder ist dieselbe): geht in ihm auf.
      Stop := Max(Result[Last].Line + Result[Last].Hidden, Sorted[Index].Line + Sorted[Index].Hidden);
      Result[Last].Hidden := Stop - Result[Last].Line;
      Continue;
    end;
    Result := Result + [Sorted[Index]];
    if Length(Result) >= MaxFolds then
      Break;
  end;
end;

class function TAtlasMinimap.Folds(const AKnown: TAtlasMinimapFolds; const APainted: TArray<TAtlasMinimapPainted>;
  ARowHeight, ALineCount: Integer): TAtlasMinimapFolds;
var
  Rows: TArray<TAtlasMinimapPainted>;
  Item, Moved: TAtlasMinimapPainted;
  Fold: TAtlasMinimapFold;
  Index, Position: Integer;
  Opened: TArray<Integer>;
  Keep: Boolean;
begin
  // Gemalte Zeilen nach ihrem oberen Rand.
  Rows := nil;
  for Item in APainted do
  begin
    Rows := Rows + [Item];
    Position := High(Rows);
    while (Position > 0) and (Rows[Position - 1].Top > Rows[Position].Top) do
    begin
      Moved := Rows[Position - 1];
      Rows[Position - 1] := Rows[Position];
      Rows[Position] := Moved;
      Dec(Position);
    end;
  end;
  Result := nil;
  Opened := nil;
  for Index := 1 to High(Rows) do
  begin
    // Nur direkt aufeinanderfolgende Bildschirmzeilen sagen etwas über die Faltung.
    if (ARowHeight <= 0) or (Rows[Index].Top - Rows[Index - 1].Top <> ARowHeight) then
      Continue;
    if Rows[Index].Line - Rows[Index - 1].Line > 1 then
      Result := Result + [TAtlasMinimapFold.Create(Rows[Index - 1].Line, Rows[Index].Line - Rows[Index - 1].Line - 1)]
    else if Rows[Index].Line - Rows[Index - 1].Line = 1 then
      Opened := Opened + [Rows[Index - 1].Line];
  end;
  for Fold in AKnown do
  begin
    Keep := True;
    for Index in Opened do
      if Index = Fold.Line then
        Keep := False;
    // Neu beobachtet: der neue Stand gilt.
    for Index := 0 to High(Result) do
      if Result[Index].Line = Fold.Line then
        Keep := False;
    if Keep then
      Result := Result + [Fold];
  end;
  Result := NormalizeFolds(Result, ALineCount);
end;

class function TAtlasMinimap.SameFolds(const A, B: TAtlasMinimapFolds): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for Index := 0 to High(A) do
    if (A[Index].Line <> B[Index].Line) or (A[Index].Hidden <> B[Index].Hidden) then
      Exit(False);
end;

class function TAtlasMinimap.Headers(const ANodes: TAtlasOutlineNodes; const AMap: TAtlasMinimapMap;
  ALabelHeight: Integer): TAtlasMinimapHeaders;
var
  Order: TArray<Integer>;
  Index, Position, Moved, Top, LastBottom: Integer;
  Node: TAtlasOutlineNode;
  Header: TAtlasMinimapHeader;
  IsType: Boolean;
begin
  Result := nil;
  Order := nil;
  for Index := 0 to High(ANodes) do
  begin
    Node := ANodes[Index];
    if Node.InBody or (Node.Name = '') then
      Continue;
    IsType := (Node.Category = TAtlasOutlineCategory.TypeDecl) and IsHeaderType(Node.Kind);
    // Routinen außerhalb von Typen: Rümpfe im implementation-Teil und globale Routinen.
    if not IsType and not ((Node.Category = TAtlasOutlineCategory.Routine) and IsRoutine(Node.Kind)) then
      Continue;
    Order := Order + [Index];
    Position := High(Order);
    while (Position > 0) and (ANodes[Order[Position - 1]].StartLine > Node.StartLine) do
    begin
      Moved := Order[Position - 1];
      Order[Position - 1] := Order[Position];
      Order[Position] := Moved;
      Dec(Position);
    end;
  end;
  LastBottom := -1;
  for Index in Order do
  begin
    Node := ANodes[Index];
    Top := AMap.PixelOfLine(Node.StartLine);
    if (LastBottom >= 0) and (Top < LastBottom) then
      Continue;
    if (AMap.Height > 0) and (Top + Max(1, ALabelHeight) > AMap.Height) then
      Continue;
    Header.Node := Index;
    Header.Line := Node.StartLine;
    Header.Text := Node.Name;
    Header.IsType := (Node.Category = TAtlasOutlineCategory.TypeDecl);
    Header.Top := Top;
    Result := Result + [Header];
    LastBottom := Top + Max(1, ALabelHeight);
  end;
end;

class function TAtlasMinimap.MethodAt(const ANodes: TAtlasOutlineNodes; ALine: Integer;
  out AStartLine, AEndLine: Integer): Boolean;
var
  Index, Best: Integer;
begin
  AStartLine := -1;
  AEndLine := -1;
  Best := -1;
  for Index := 0 to High(ANodes) do
    if IsRoutine(ANodes[Index].Kind) and (ANodes[Index].Category <> TAtlasOutlineCategory.Method) and
      (ANodes[Index].StartLine <= ALine) and (ALine <= ANodes[Index].EndLine) then
      // Die innerste gewinnt: späterer Anfang bzw. bei gleichem Anfang das kürzere Ende.
      if (Best < 0) or (ANodes[Index].StartLine > ANodes[Best].StartLine) or
        ((ANodes[Index].StartLine = ANodes[Best].StartLine) and (ANodes[Index].EndLine < ANodes[Best].EndLine)) then
        Best := Index;
  Result := Best >= 0;
  if Result then
  begin
    AStartLine := ANodes[Best].StartLine;
    AEndLine := ANodes[Best].EndLine;
  end;
end;

class function TAtlasMinimap.MarkerKinds: TAtlasOverviewKinds;
begin
  Result := [TAtlasOverviewKind.Diagnostics, TAtlasOverviewKind.Search, TAtlasOverviewKind.Changes];
end;

class function TAtlasMinimap.MarkerBars(const AMarks: TAtlasOverviewMarks; const AMap: TAtlasMinimapMap;
  AMinHeight: Integer): TAtlasOverviewBars;
var
  Kind: TAtlasOverviewMarkKind;
  Order: TArray<Integer>;
  Index, Position, Moved, Top, Bottom, Last, LastLine: Integer;
  Bar: TAtlasOverviewBar;
begin
  Result := nil;
  if (AMap.LineCount <= 0) or (AMap.Height <= 0) then
    Exit;
  for Kind := Low(TAtlasOverviewMarkKind) to High(TAtlasOverviewMarkKind) do
  begin
    if not (TAtlasOverview.GroupOf(Kind) in MarkerKinds) then
      Continue;
    Order := nil;
    for Index := 0 to High(AMarks) do
      if AMarks[Index].Kind = Kind then
      begin
        Order := Order + [Index];
        Position := High(Order);
        while (Position > 0) and (AMarks[Order[Position - 1]].Line > AMarks[Index].Line) do
        begin
          Moved := Order[Position - 1];
          Order[Position - 1] := Order[Position];
          Order[Position] := Moved;
          Dec(Position);
        end;
      end;
    Last := -1;
    for Index in Order do
    begin
      LastLine := Min(AMarks[Index].Line + AMarks[Index].Count - 1, AMap.LineCount - 1);
      Top := AMap.PixelOfLine(AMarks[Index].Line);
      Bottom := Max(AMap.PixelOfRow(AMap.RowOf(LastLine) + 1), Top + Max(1, AMinHeight));
      if Bottom > AMap.Height then
      begin
        Bottom := AMap.Height;
        Top := Max(0, Min(Top, AMap.Height - Max(1, AMinHeight)));
      end;
      if (Last >= 0) and (Top <= Result[Last].Bottom) then
      begin
        Result[Last].Bottom := Max(Result[Last].Bottom, Bottom);
        Continue;
      end;
      Bar.Mark := Index;
      Bar.Kind := Kind;
      if TAtlasOverview.GroupOf(Kind) = TAtlasOverviewKind.Changes then
        Bar.Lane := TAtlasOverviewLane.Left
      else
        Bar.Lane := TAtlasOverviewLane.Full;
      Bar.Top := Top;
      Bar.Bottom := Bottom;
      Result := Result + [Bar];
      Last := High(Result);
    end;
  end;
end;

class function TAtlasMinimap.LineRuns(const ALine: string; const ATokens: TAtlasTokens;
  AMaxColumn, ATabWidth: Integer): TAtlasMinimapLine;
var
  Token: TAtlasToken;
  Index, Column, Start, TabWidth: Integer;
  Run: TAtlasMinimapRun;
  InWord: Boolean;

  procedure Close(AStop: Integer);
  begin
    if not InWord then
      Exit;
    InWord := False;
    Run.Stop := Min(AStop, AMaxColumn);
    if Run.Stop > Run.Start then
      Result := Result + [Run];
  end;

begin
  Result := nil;
  TabWidth := Max(1, ATabWidth);
  Column := 0;
  InWord := False;
  for Token in ATokens do
  begin
    Close(Column);
    Start := Max(0, Token.Start);
    for Index := Start to Min(Token.Stop, Length(ALine)) - 1 do
    begin
      if Column >= AMaxColumn then
        Break;
      if (ALine[Index + 1] = ' ') or (ALine[Index + 1] = #9) then
      begin
        Close(Column);
        if ALine[Index + 1] = #9 then
          Column := (Column div TabWidth + 1) * TabWidth
        else
          Inc(Column);
        Continue;
      end;
      if not InWord then
      begin
        InWord := True;
        Run.Start := Column;
        Run.Kind := Token.Kind;
      end;
      Inc(Column);
    end;
    if Column >= AMaxColumn then
      Break;
  end;
  Close(Column);
end;

class function TAtlasMinimap.Runs(const ALines: TArray<string>; AMaxColumn, ATabWidth: Integer):
  TAtlasMinimapLines;
var
  Tokens: TArray<TAtlasTokens>;
  Index: Integer;
begin
  Tokens := TAtlasSyntax.LineTokens(ALines);
  SetLength(Result, Length(ALines));
  for Index := 0 to High(ALines) do
    Result[Index] := LineRuns(ALines[Index], Tokens[Index], AMaxColumn, ATabWidth);
end;

class function TAtlasMinimap.SameLine(const A, B: TAtlasMinimapLine): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for Index := 0 to High(A) do
    if (A[Index].Start <> B[Index].Start) or (A[Index].Stop <> B[Index].Stop) or (A[Index].Kind <> B[Index].Kind) then
      Exit(False);
end;

class function TAtlasMinimap.Expand(const ALine: string; AMaxColumn, ATabWidth: Integer): string;
var
  Index, Column, Next: Integer;
begin
  Result := '';
  Column := 0;
  for Index := 1 to Length(ALine) do
  begin
    if Column >= AMaxColumn then
      Break;
    if ALine[Index] = #9 then
    begin
      Next := Min((Column div Max(1, ATabWidth) + 1) * Max(1, ATabWidth), AMaxColumn);
      Result := Result + StringOfChar(' ', Next - Column);
      Column := Next;
    end
    else
    begin
      Result := Result + ALine[Index];
      Inc(Column);
    end;
  end;
end;

class function TAtlasMinimap.ChangedLines(const AOld, ANew: TAtlasMinimapLines): TArray<Integer>;
var
  Index, Common: Integer;
begin
  Result := nil;
  Common := Min(Length(AOld), Length(ANew));
  for Index := 0 to Common - 1 do
    if not SameLine(AOld[Index], ANew[Index]) then
      Result := Result + [Index];
  for Index := Common to Max(Length(AOld), Length(ANew)) - 1 do
    Result := Result + [Index];
end;

class function TAtlasMinimap.GlyphHeight(AChar: Char; ARowHeight: Integer): Integer;
begin
  if ARowHeight <= 0 then
    Exit(0);
  if (AChar = ' ') or (AChar = #9) or (AChar < ' ') then
    Exit(0);
  if CharInSet(AChar, ['A'..'Z', '0'..'9', '(', ')', '[', ']', '{', '}', '''', '"', '#', '$', '@', '|']) then
    Exit(ARowHeight);
  if CharInSet(AChar, ['a'..'z']) or TTextChars.IsIdentStart(AChar) then
    Exit(Max(1, (ARowHeight * 2 + 2) div 3));
  Result := 1;
end;

class function TAtlasMinimap.ShouldNotice(AOurs, AIdeVisible, AShown: Boolean): Boolean;
begin
  Result := AOurs and AIdeVisible and not AShown;
end;

end.
