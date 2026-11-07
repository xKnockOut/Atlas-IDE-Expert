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
    cDefaultWidth = 120;
    cMinWidth = TAtlasPluginSettings.cMinMinimapWidth;
    cMaxWidth = TAtlasPluginSettings.cMaxMinimapWidth;
    cDefaultScale = 2;
    cMinScale = TAtlasPluginSettings.cMinMinimapScale;
    cMaxScale = TAtlasPluginSettings.cMaxMinimapScale;
    cDefaultMaxColumn = 120;
    cMinColumn = TAtlasPluginSettings.cMinMinimapColumn;
    cMaxColumnLimit = TAtlasPluginSettings.cMaxMinimapColumn;
    cRenderNames: array[TAtlasMinimapRender] of string = ('blocks', 'characters');
    cSideNames: array[TAtlasMinimapSide] of string = ('right', 'left');
    cSliderNames: array[TAtlasMinimapSlider] of string = ('always', 'mouseover');
    /// <summary>Höchstzahl der gemerkten gefalteten Bereiche.</summary>
    cMaxFolds = 2000;
  public
    /// <summary>Vorgaben aus dem Katalog (#873).</summary>
    class function Defaults: TAtlasMinimapOptions; static;
    /// <summary>Einstellungen (Minimap*) als Optionen: Namen ohne Groß-/Kleinschreibung, unbekannte als Vorgabe,
    /// Zahlen geklemmt.</summary>
    class function Options(const ASettings: TAtlasPluginSettings): TAtlasMinimapOptions; static;
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
  cKindClass = 5;
  cKindMethod = 6;
  cKindConstructor = 9;
  cKindInterface = 11;
  cKindFunction = 12;
  cKindObject = 19;
  cKindStruct = 23;

function IsRoutine(AKind: Integer): Boolean;
begin
  Result := (AKind = cKindMethod) or (AKind = cKindConstructor) or (AKind = cKindFunction);
end;

function IsHeaderType(AKind: Integer): Boolean;
begin
  Result := (AKind = cKindClass) or (AKind = cKindInterface) or (AKind = cKindObject) or (AKind = cKindStruct);
end;

type
  /// <summary>Sammelt die Balken der Wörter einer Zeile, Spalte für Spalte.</summary>
  TRunBuilder = record
  private
    FRuns: TAtlasMinimapLine;
    FRun: TAtlasMinimapRun;
    FInWord: Boolean;
    FColumn: Integer;
    FMaxColumn: Integer;
    FTabWidth: Integer;
  public
    procedure Init(AMaxColumn, ATabWidth: Integer);
    /// <summary>Offenes Wort an der aktuellen Spalte beenden.</summary>
    procedure Close;
    /// <summary>Ein Zeichen des Tokens der Art AKind.</summary>
    procedure Add(AChar: Char; AKind: TAtlasTokenKind);
    function Full: Boolean;
    property Runs: TAtlasMinimapLine read FRuns;
  end;

procedure TRunBuilder.Init(AMaxColumn, ATabWidth: Integer);
begin
  FRuns := nil;
  FInWord := False;
  FColumn := 0;
  FMaxColumn := AMaxColumn;
  FTabWidth := Max(1, ATabWidth);
end;

procedure TRunBuilder.Close;
begin
  if FInWord then
  begin
    FInWord := False;
    FRun.Stop := Min(FColumn, FMaxColumn);
    if FRun.Stop > FRun.Start then
    begin
      FRuns := FRuns + [FRun];
    end;
  end;
end;

procedure TRunBuilder.Add(AChar: Char; AKind: TAtlasTokenKind);
begin
  if AChar = #9 then
  begin
    Close;
    FColumn := (FColumn div FTabWidth + 1) * FTabWidth;
  end
  else if AChar = ' ' then
  begin
    Close;
    Inc(FColumn);
  end
  else
  begin
    if not FInWord then
    begin
      FInWord := True;
      FRun.Start := FColumn;
      FRun.Kind := AKind;
    end;
    Inc(FColumn);
  end;
end;

function TRunBuilder.Full: Boolean;
begin
  Result := FColumn >= FMaxColumn;
end;

/// <summary>Gemalte Zeilen nach ihrem oberen Rand (stabil).</summary>
function SortedByTop(const APainted: TArray<TAtlasMinimapPainted>): TArray<TAtlasMinimapPainted>;
var
  mItem, mMoved: TAtlasMinimapPainted;
  mPosition: Integer;
begin
  Result := nil;
  for mItem in APainted do
  begin
    Result := Result + [mItem];
    mPosition := High(Result);
    while (mPosition > 0) and (Result[mPosition - 1].Top > Result[mPosition].Top) do
    begin
      mMoved := Result[mPosition - 1];
      Result[mPosition - 1] := Result[mPosition];
      Result[mPosition] := mMoved;
      Dec(mPosition);
    end;
  end;
end;

/// <summary>Faltungen zwischen direkt aufeinanderfolgenden Bildschirmzeilen; AOpened: Kopfzeilen, deren
/// Folgezeile direkt darunter steht.</summary>
function ObservedFolds(const ARows: TArray<TAtlasMinimapPainted>; ARowHeight: Integer;
  out AOpened: TArray<Integer>): TAtlasMinimapFolds;
var
  mIndex, mGap: Integer;
begin
  Result := nil;
  AOpened := nil;
  for mIndex := 1 to High(ARows) do
  begin
    // Nur direkt aufeinanderfolgende Bildschirmzeilen sagen etwas über die Faltung.
    if (ARowHeight > 0) and (ARows[mIndex].Top - ARows[mIndex - 1].Top = ARowHeight) then
    begin
      mGap := ARows[mIndex].Line - ARows[mIndex - 1].Line;
      if mGap > 1 then
      begin
        Result := Result + [TAtlasMinimapFold.Create(ARows[mIndex - 1].Line, mGap - 1)];
      end
      else if mGap = 1 then
      begin
        AOpened := AOpened + [ARows[mIndex - 1].Line];
      end;
    end;
  end;
end;

function ContainsLine(const ALines: TArray<Integer>; ALine: Integer): Boolean;
var
  mLine: Integer;
begin
  Result := False;
  for mLine in ALines do
  begin
    Result := Result or (mLine = ALine);
  end;
end;

function HasFoldAt(const AFolds: TAtlasMinimapFolds; ALine: Integer): Boolean;
var
  mFold: TAtlasMinimapFold;
begin
  Result := False;
  for mFold in AFolds do
  begin
    Result := Result or (mFold.Line = ALine);
  end;
end;

/// <summary>Knoten mit Überschrift: Typen und Routinen außerhalb von Typen (Rümpfe im implementation-Teil und
/// globale Routinen).</summary>
function HasHeader(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := not ANode.InBody and (ANode.Name <> '') and
    (((ANode.Category = TAtlasOutlineCategory.TypeDecl) and IsHeaderType(ANode.Kind)) or
    ((ANode.Category = TAtlasOutlineCategory.Routine) and IsRoutine(ANode.Kind)));
end;

/// <summary>Knoten mit Überschrift, aufsteigend nach Anfangszeile (stabil).</summary>
function HeaderOrder(const ANodes: TAtlasOutlineNodes): TArray<Integer>;
var
  mIndex, mPosition, mMoved: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if HasHeader(ANodes[mIndex]) then
    begin
      Result := Result + [mIndex];
      mPosition := High(Result);
      while (mPosition > 0) and (ANodes[Result[mPosition - 1]].StartLine > ANodes[mIndex].StartLine) do
      begin
        mMoved := Result[mPosition - 1];
        Result[mPosition - 1] := Result[mPosition];
        Result[mPosition] := mMoved;
        Dec(mPosition);
      end;
    end;
  end;
end;

/// <summary>Marken der Art AKind, aufsteigend nach Zeile (stabil).</summary>
function MarksOfKind(const AMarks: TAtlasOverviewMarks; AKind: TAtlasOverviewMarkKind): TArray<Integer>;
var
  mIndex, mPosition, mMoved: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AMarks) do
  begin
    if AMarks[mIndex].Kind = AKind then
    begin
      Result := Result + [mIndex];
      mPosition := High(Result);
      while (mPosition > 0) and (AMarks[Result[mPosition - 1]].Line > AMarks[mIndex].Line) do
      begin
        mMoved := Result[mPosition - 1];
        Result[mPosition - 1] := Result[mPosition];
        Result[mPosition] := mMoved;
        Dec(mPosition);
      end;
    end;
  end;
end;

/// <summary>Pixelbereich der Marke, mindestens AMinHeight hoch und in der Karte.</summary>
function MarkSpan(const AMark: TAtlasOverviewMark; const AMap: TAtlasMinimapMap; AMinHeight: Integer):
  TAtlasMinimapSpan;
var
  mLastLine: Integer;
begin
  mLastLine := Min(AMark.Line + AMark.Count - 1, AMap.LineCount - 1);
  Result.Top := AMap.PixelOfLine(AMark.Line);
  Result.Bottom := Max(AMap.PixelOfRow(AMap.RowOf(mLastLine) + 1), Result.Top + Max(1, AMinHeight));
  if Result.Bottom > AMap.Height then
  begin
    Result.Bottom := AMap.Height;
    Result.Top := Max(0, Min(Result.Top, AMap.Height - Max(1, AMinHeight)));
  end;
end;

/// <summary>Balken der Marken einer Art; überlappende gehen im vorigen auf.</summary>
procedure AddKindBars(const AMarks: TAtlasOverviewMarks; const AMap: TAtlasMinimapMap; AMinHeight: Integer;
  AKind: TAtlasOverviewMarkKind; var ABars: TAtlasOverviewBars);
var
  mIndex, mLast: Integer;
  mSpan: TAtlasMinimapSpan;
  mBar: TAtlasOverviewBar;
begin
  mLast := -1;
  for mIndex in MarksOfKind(AMarks, AKind) do
  begin
    mSpan := MarkSpan(AMarks[mIndex], AMap, AMinHeight);
    if (mLast >= 0) and (mSpan.Top <= ABars[mLast].Bottom) then
    begin
      ABars[mLast].Bottom := Max(ABars[mLast].Bottom, mSpan.Bottom);
    end
    else
    begin
      mBar.Mark := mIndex;
      mBar.Kind := AKind;
      mBar.Lane := TAtlasOverviewLane.Full;
      if TAtlasOverview.GroupOf(AKind) = TAtlasOverviewKind.Changes then
      begin
        mBar.Lane := TAtlasOverviewLane.Left;
      end;
      mBar.Top := mSpan.Top;
      mBar.Bottom := mSpan.Bottom;
      ABars := ABars + [mBar];
      mLast := High(ABars);
    end;
  end;
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
  mFold: TAtlasMinimapFold;
begin
  Result.LineCount := Max(0, ALineCount);
  Result.RowHeight := Max(1, ARowHeight);
  Result.Height := Max(0, AHeight);
  Result.Folds := TAtlasMinimap.NormalizeFolds(AFolds, Result.LineCount);
  Result.RowCount := Result.LineCount;
  for mFold in Result.Folds do
  begin
    Dec(Result.RowCount, mFold.Hidden);
  end;
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
  mOverflow: Int64;
  mScrollable, mTop, mNewOffset: Integer;
begin
  mOverflow := TotalHeight - Height;
  mNewOffset := 0;
  if (mOverflow > 0) and (RowCount > 0) then
  begin
    // Anteil der Lage im Editor: 0 ganz oben, 1 ganz unten (letzte Seite sichtbar).
    mScrollable := Max(1, RowCount - VisibleRows(ATopLine, Max(ATopLine, ABottomLine)));
    mTop := EnsureRange(RowOf(ATopLine), 0, mScrollable);
    mNewOffset := Integer((mOverflow * mTop) div mScrollable);
  end;
  Result := mNewOffset <> Offset;
  Offset := mNewOffset;
end;

function TAtlasMinimapMap.ContentHeight: Integer;
begin
  Result := Integer(Max(0, Min(TotalHeight - Offset, Int64(Height))));
end;

function TAtlasMinimapMap.RowOf(ALine: Integer): Integer;
var
  mFold: TAtlasMinimapFold;
  mLine, mHiddenBefore: Integer;
begin
  if LineCount <= 0 then
  begin
    Exit(0);
  end;
  mLine := EnsureRange(ALine, 0, LineCount - 1);
  mHiddenBefore := 0;
  for mFold in Folds do
  begin
    if mFold.Line >= mLine then
    begin
      Break;
    end;
    // In der Faltung verborgen: Zeile der Kopfzeile.
    if mLine <= mFold.Line + mFold.Hidden then
    begin
      Exit(mFold.Line - mHiddenBefore);
    end;
    Inc(mHiddenBefore, mFold.Hidden);
  end;
  Result := mLine - mHiddenBefore;
end;

function TAtlasMinimapMap.LineOf(ARow: Integer): Integer;
var
  mFold: TAtlasMinimapFold;
  mRow, mHiddenBefore: Integer;
begin
  if RowCount <= 0 then
  begin
    Exit(0);
  end;
  mRow := EnsureRange(ARow, 0, RowCount - 1);
  mHiddenBefore := 0;
  for mFold in Folds do
  begin
    if mFold.Line - mHiddenBefore >= mRow then
    begin
      Break;
    end;
    Inc(mHiddenBefore, mFold.Hidden);
  end;
  Result := Min(mRow + mHiddenBefore, LineCount - 1);
end;

function TAtlasMinimapMap.PixelOfRow(ARow: Integer): Integer;
var
  mRow: Integer;
begin
  if (RowCount <= 0) or (Height <= 0) then
  begin
    Exit(0);
  end;
  mRow := EnsureRange(ARow, 0, RowCount);
  Result := mRow * RowHeight - Offset;
end;

function TAtlasMinimapMap.RowAt(AY: Integer): Integer;
begin
  if (RowCount <= 0) or (Height <= 0) then
  begin
    Exit(0);
  end;
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
  mMinHeight: Integer;
begin
  Result.Top := 0;
  Result.Bottom := 0;
  if (RowCount <= 0) or (Height <= 0) then
  begin
    Exit;
  end;
  mMinHeight := Min(Max(1, AMinHeight), Height);
  Result.Top := PixelOfRow(RowOf(ATopLine));
  Result.Bottom := Max(PixelOfRow(RowOf(Max(ATopLine, ABottomLine)) + 1), Result.Top + mMinHeight);
  if Result.Bottom > Height then
  begin
    Result.Bottom := Height;
    Result.Top := Max(0, Min(Result.Top, Height - mMinHeight));
  end;
end;

function TAtlasMinimapMap.DragTop(AY, AGrab, AVisibleRows: Integer): Integer;
var
  mRow: Integer;
begin
  if RowCount <= 0 then
  begin
    Exit(0);
  end;
  if TotalHeight > Height then
  begin
    // Mitscrollend (Follow): Die Oberkante des Schiebers läuft linear von 0 bis Height − Schieberhöhe, während die
    // oberste Zeile von 0 bis RowCount − AVisibleRows läuft. Umkehrung davon; der Offset ändert sich beim Ziehen mit
    // und darf nicht in die Rechnung eingehen, sonst läuft der Schieber davon.
    mRow := Integer((Int64(Max(0, AY - AGrab)) * Max(1, RowCount - Max(1, AVisibleRows))) div
      Max(1, Height - Max(1, AVisibleRows) * RowHeight));
  end
  else
  begin
    mRow := RowAt(AY - AGrab);
  end;
  // Ganz oben gegriffen und darüber hinaus gezogen: erste Zeile.
  if AY - AGrab <= 0 then
  begin
    mRow := 0;
  end;
  mRow := EnsureRange(mRow, 0, Max(0, RowCount - Max(1, AVisibleRows)));
  Result := LineOf(mRow);
end;

function TAtlasMinimapMap.ClickTop(AY, AVisibleRows: Integer): Integer;
var
  mRow: Integer;
begin
  if RowCount <= 0 then
  begin
    Exit(0);
  end;
  mRow := RowAt(AY) - Max(1, AVisibleRows) div 2;
  mRow := EnsureRange(mRow, 0, Max(0, RowCount - Max(1, AVisibleRows)));
  Result := LineOf(mRow);
end;

{ TAtlasMinimap }

class function TAtlasMinimap.Defaults: TAtlasMinimapOptions;
begin
  // Winzige Zeichen wie VS Code; Balken je Wort sind die Alternative.
  Result.Render := TAtlasMinimapRender.Characters;
  Result.Width := cDefaultWidth;
  Result.Scale := cDefaultScale;
  Result.MaxColumn := cDefaultMaxColumn;
  Result.Side := TAtlasMinimapSide.Right;
  Result.Slider := TAtlasMinimapSlider.Always;
  Result.SectionHeaders := True;
  Result.HighlightMethod := True;
  Result.Markers := True;
  Result.ClickJumps := True;
end;

class function TAtlasMinimap.Options(const ASettings: TAtlasPluginSettings): TAtlasMinimapOptions;
begin
  Result.Render := RenderOf(ASettings.MinimapRender);
  Result.Width := ClampWidth(ASettings.MinimapWidth);
  Result.Scale := ClampScale(ASettings.MinimapScale);
  Result.MaxColumn := ClampColumn(ASettings.MinimapMaxColumn);
  Result.Side := SideOf(ASettings.MinimapSide);
  Result.Slider := SliderOf(ASettings.MinimapShowSlider);
  Result.SectionHeaders := ASettings.MinimapSectionHeaders;
  Result.HighlightMethod := ASettings.MinimapHighlightMethod;
  Result.Markers := ASettings.MinimapMarkers;
  Result.ClickJumps := ASettings.MinimapClickJumps;
end;

class function TAtlasMinimap.RenderOf(const AName: string): TAtlasMinimapRender;
var
  mRender: TAtlasMinimapRender;
begin
  for mRender := Low(TAtlasMinimapRender) to High(TAtlasMinimapRender) do
  begin
    if SameText(Trim(AName), cRenderNames[mRender]) then
    begin
      Exit(mRender);
    end;
  end;
  Result := TAtlasMinimapRender.Characters;
end;

class function TAtlasMinimap.SideOf(const AName: string): TAtlasMinimapSide;
var
  mSide: TAtlasMinimapSide;
begin
  for mSide := Low(TAtlasMinimapSide) to High(TAtlasMinimapSide) do
  begin
    if SameText(Trim(AName), cSideNames[mSide]) then
    begin
      Exit(mSide);
    end;
  end;
  Result := TAtlasMinimapSide.Right;
end;

class function TAtlasMinimap.SliderOf(const AName: string): TAtlasMinimapSlider;
var
  mSlider: TAtlasMinimapSlider;
begin
  for mSlider := Low(TAtlasMinimapSlider) to High(TAtlasMinimapSlider) do
  begin
    if SameText(Trim(AName), cSliderNames[mSlider]) then
    begin
      Exit(mSlider);
    end;
  end;
  Result := TAtlasMinimapSlider.Always;
end;

class function TAtlasMinimap.ClampWidth(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, cMinWidth, cMaxWidth);
end;

class function TAtlasMinimap.ClampScale(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, cMinScale, cMaxScale);
end;

class function TAtlasMinimap.ClampColumn(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, cMinColumn, cMaxColumnLimit);
end;

class function TAtlasMinimap.NormalizeFolds(const AFolds: TAtlasMinimapFolds; ALineCount: Integer):
  TAtlasMinimapFolds;
var
  mSorted: TAtlasMinimapFolds;
  mFold, mMoved: TAtlasMinimapFold;
  mIndex, mPosition, mLast, mStop: Integer;
begin
  Result := nil;
  // Gültige Bereiche, nach Kopfzeile sortiert (Einfügen; die Listen sind meist schon sortiert).
  mSorted := nil;
  for mFold in AFolds do
  begin
    if (mFold.Hidden < 1) or (mFold.Line < 0) or (mFold.Line >= ALineCount - 1) then
    begin
      Continue;
    end;
    mSorted := mSorted + [TAtlasMinimapFold.Create(mFold.Line, Min(mFold.Hidden, ALineCount - 1 - mFold.Line))];
    mPosition := High(mSorted);
    while (mPosition > 0) and (mSorted[mPosition - 1].Line > mSorted[mPosition].Line) do
    begin
      mMoved := mSorted[mPosition - 1];
      mSorted[mPosition - 1] := mSorted[mPosition];
      mSorted[mPosition] := mMoved;
      Dec(mPosition);
    end;
  end;
  for mIndex := 0 to High(mSorted) do
  begin
    mLast := High(Result);
    if (mLast >= 0) and (mSorted[mIndex].Line <= Result[mLast].Line + Result[mLast].Hidden) then
    begin
      // Kopfzeile liegt im vorigen Bereich (oder ist dieselbe): geht in ihm auf.
      mStop := Max(Result[mLast].Line + Result[mLast].Hidden, mSorted[mIndex].Line + mSorted[mIndex].Hidden);
      Result[mLast].Hidden := mStop - Result[mLast].Line;
      Continue;
    end;
    Result := Result + [mSorted[mIndex]];
    if Length(Result) >= cMaxFolds then
    begin
      Break;
    end;
  end;
end;

class function TAtlasMinimap.Folds(const AKnown: TAtlasMinimapFolds; const APainted: TArray<TAtlasMinimapPainted>;
  ARowHeight, ALineCount: Integer): TAtlasMinimapFolds;
var
  mOpened: TArray<Integer>;
  mFold: TAtlasMinimapFold;
begin
  Result := ObservedFolds(SortedByTop(APainted), ARowHeight, mOpened);
  for mFold in AKnown do
  begin
    // Bekannte bleiben, außer sie sind aufgeklappt oder neu beobachtet (dann gilt der neue Stand).
    if not ContainsLine(mOpened, mFold.Line) and not HasFoldAt(Result, mFold.Line) then
    begin
      Result := Result + [mFold];
    end;
  end;
  Result := NormalizeFolds(Result, ALineCount);
end;

class function TAtlasMinimap.SameFolds(const A, B: TAtlasMinimapFolds): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if (A[mIndex].Line <> B[mIndex].Line) or (A[mIndex].Hidden <> B[mIndex].Hidden) then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasMinimap.Headers(const ANodes: TAtlasOutlineNodes; const AMap: TAtlasMinimapMap;
  ALabelHeight: Integer): TAtlasMinimapHeaders;
var
  mIndex, mTop, mLastBottom, mHeight: Integer;
  mHeader: TAtlasMinimapHeader;
begin
  Result := nil;
  mHeight := Max(1, ALabelHeight);
  mLastBottom := -1;
  for mIndex in HeaderOrder(ANodes) do
  begin
    mTop := AMap.PixelOfLine(ANodes[mIndex].StartLine);
    // Überdeckt keine frühere und passt in die Karte.
    if ((mLastBottom < 0) or (mTop >= mLastBottom)) and ((AMap.Height <= 0) or (mTop + mHeight <= AMap.Height)) then
    begin
      mHeader.Node := mIndex;
      mHeader.Line := ANodes[mIndex].StartLine;
      mHeader.Text := ANodes[mIndex].Name;
      mHeader.IsType := ANodes[mIndex].Category = TAtlasOutlineCategory.TypeDecl;
      mHeader.Top := mTop;
      Result := Result + [mHeader];
      mLastBottom := mTop + mHeight;
    end;
  end;
end;

class function TAtlasMinimap.MethodAt(const ANodes: TAtlasOutlineNodes; ALine: Integer;
  out AStartLine, AEndLine: Integer): Boolean;
var
  mIndex, mBest: Integer;
begin
  AStartLine := -1;
  AEndLine := -1;
  mBest := -1;
  for mIndex := 0 to High(ANodes) do
  begin
    if IsRoutine(ANodes[mIndex].Kind) and (ANodes[mIndex].Category <> TAtlasOutlineCategory.Method) and
      (ANodes[mIndex].StartLine <= ALine) and (ALine <= ANodes[mIndex].EndLine) then
    begin
      // Die innerste gewinnt: späterer Anfang bzw. bei gleichem Anfang das kürzere Ende.
      if (mBest < 0) or (ANodes[mIndex].StartLine > ANodes[mBest].StartLine) or
        ((ANodes[mIndex].StartLine = ANodes[mBest].StartLine) and (ANodes[mIndex].EndLine < ANodes[mBest].EndLine)) then
      begin
        mBest := mIndex;
      end;
    end;
  end;
  Result := mBest >= 0;
  if Result then
  begin
    AStartLine := ANodes[mBest].StartLine;
    AEndLine := ANodes[mBest].EndLine;
  end;
end;

class function TAtlasMinimap.MarkerKinds: TAtlasOverviewKinds;
begin
  Result := [TAtlasOverviewKind.Diagnostics, TAtlasOverviewKind.Search, TAtlasOverviewKind.Changes];
end;

class function TAtlasMinimap.MarkerBars(const AMarks: TAtlasOverviewMarks; const AMap: TAtlasMinimapMap;
  AMinHeight: Integer): TAtlasOverviewBars;
var
  mKind: TAtlasOverviewMarkKind;
begin
  Result := nil;
  if (AMap.LineCount > 0) and (AMap.Height > 0) then
  begin
    for mKind := Low(TAtlasOverviewMarkKind) to High(TAtlasOverviewMarkKind) do
    begin
      if TAtlasOverview.GroupOf(mKind) in MarkerKinds then
      begin
        AddKindBars(AMarks, AMap, AMinHeight, mKind, Result);
      end;
    end;
  end;
end;

class function TAtlasMinimap.LineRuns(const ALine: string; const ATokens: TAtlasTokens;
  AMaxColumn, ATabWidth: Integer): TAtlasMinimapLine;
var
  mBuilder: TRunBuilder;
  mTokenIndex, mIndex, mStop: Integer;
begin
  mBuilder := Default(TRunBuilder);
  mBuilder.Init(AMaxColumn, ATabWidth);
  mTokenIndex := 0;
  while (mTokenIndex <= High(ATokens)) and not mBuilder.Full do
  begin
    mBuilder.Close;
    mIndex := Max(0, ATokens[mTokenIndex].Start);
    mStop := Min(ATokens[mTokenIndex].Stop, Length(ALine));
    while (mIndex < mStop) and not mBuilder.Full do
    begin
      mBuilder.Add(ALine[mIndex + 1], ATokens[mTokenIndex].Kind);
      Inc(mIndex);
    end;
    Inc(mTokenIndex);
  end;
  mBuilder.Close;
  Result := mBuilder.Runs;
end;

class function TAtlasMinimap.Runs(const ALines: TArray<string>; AMaxColumn, ATabWidth: Integer):
  TAtlasMinimapLines;
var
  mTokens: TArray<TAtlasTokens>;
  mIndex: Integer;
begin
  mTokens := TAtlasSyntax.LineTokens(ALines);
  SetLength(Result, Length(ALines));
  for mIndex := 0 to High(ALines) do
  begin
    Result[mIndex] := LineRuns(ALines[mIndex], mTokens[mIndex], AMaxColumn, ATabWidth);
  end;
end;

class function TAtlasMinimap.SameLine(const A, B: TAtlasMinimapLine): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if (A[mIndex].Start <> B[mIndex].Start) or (A[mIndex].Stop <> B[mIndex].Stop) or
      (A[mIndex].Kind <> B[mIndex].Kind) then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasMinimap.Expand(const ALine: string; AMaxColumn, ATabWidth: Integer): string;
var
  mIndex, mColumn, mNext: Integer;
begin
  Result := '';
  mColumn := 0;
  for mIndex := 1 to Length(ALine) do
  begin
    if mColumn >= AMaxColumn then
    begin
      Break;
    end;
    if ALine[mIndex] = #9 then
    begin
      mNext := Min((mColumn div Max(1, ATabWidth) + 1) * Max(1, ATabWidth), AMaxColumn);
      Result := Result + StringOfChar(' ', mNext - mColumn);
      mColumn := mNext;
    end
    else
    begin
      Result := Result + ALine[mIndex];
      Inc(mColumn);
    end;
  end;
end;

class function TAtlasMinimap.ChangedLines(const AOld, ANew: TAtlasMinimapLines): TArray<Integer>;
var
  mIndex, mCommon: Integer;
begin
  Result := nil;
  mCommon := Min(Length(AOld), Length(ANew));
  for mIndex := 0 to mCommon - 1 do
  begin
    if not SameLine(AOld[mIndex], ANew[mIndex]) then
    begin
      Result := Result + [mIndex];
    end;
  end;
  for mIndex := mCommon to Max(Length(AOld), Length(ANew)) - 1 do
  begin
    Result := Result + [mIndex];
  end;
end;

class function TAtlasMinimap.GlyphHeight(AChar: Char; ARowHeight: Integer): Integer;
begin
  if ARowHeight <= 0 then
  begin
    Exit(0);
  end;
  if (AChar = ' ') or (AChar = #9) or (AChar < ' ') then
  begin
    Exit(0);
  end;
  if CharInSet(AChar, ['A'..'Z', '0'..'9', '(', ')', '[', ']', '{', '}', '''', '"', '#', '$', '@', '|']) then
  begin
    Exit(ARowHeight);
  end;
  if CharInSet(AChar, ['a'..'z']) or TTextChars.IsIdentStart(AChar) then
  begin
    Exit(Max(1, (ARowHeight * 2 + 2) div 3));
  end;
  Result := 1;
end;

class function TAtlasMinimap.ShouldNotice(AOurs, AIdeVisible, AShown: Boolean): Boolean;
begin
  Result := AOurs and AIdeVisible and not AShown;
end;

end.
