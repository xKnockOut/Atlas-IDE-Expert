unit Atlas.Core.Tracker.BoardLayout;

// Anordnung des Boards (#1272) ohne Fenster, VCL und Open Tools API:
// - Breit stehen die Spalten nebeneinander, gleichmäßig breit und mindestens
//   ColumnWidth; schmaler als NarrowWidth untereinander als einklappbare
//   Gruppen. Leere Spalten behalten Platz zum Ablegen.
// - Hat das Board Swimlanes (TAtlasBoardLanes), steht breit links eine Spalte
//   mit einer Zeile je Wert; die Karten stehen in den Zellen. Eingeklappte
//   Swimlanes zeigen nur ihren Namen. Sind nicht alle Karten sichtbar
//   (Filter), entfallen Swimlanes ohne sichtbare Karte.
// - TAtlasBoardFolds merkt eingeklappte Spalten und Swimlanes.

interface

uses
  System.Types,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.BoardLanes;

type
  /// <summary>Maße in Pixeln (schon skaliert).</summary>
  TAtlasBoardMetrics = record
    ColumnWidth: Integer;
    Gap: Integer;
    Header: Integer;
    CardHeight: Integer;
    /// <summary>Schmaler als das: Spalten untereinander.</summary>
    NarrowWidth: Integer;
    /// <summary>Breite der Spalte mit den Namen der Swimlanes.</summary>
    LaneWidth: Integer;
    /// <summary>Maße bei 96 dpi aus der Zeilenhöhe der Schrift.</summary>
    class function Create(ALineHeight: Integer): TAtlasBoardMetrics; static;
    /// <summary>Alle Maße mal AScale (PPI/96).</summary>
    function Scaled(AMultiplier, ADivider: Integer): TAtlasBoardMetrics;
  end;

  /// <summary>Lage einer Karte.</summary>
  TAtlasBoardPlace = record
    Card: Integer;
    /// <summary>Spalte im Board (-1 = ohne Spalte).</summary>
    Column: Integer;
    Bounds: TRect;
  end;

  /// <summary>Anordnung von Spalten und Karten; ohne Fenster berechnet (testbar).</summary>
  TAtlasBoardLayout = record
  public const
    /// <summary>Ergebnis von ColumnAt und HeaderAt ohne Spalte (-1 ist „ohne Spalte“).</summary>
    cNoColumn = -2;
  public
    Narrow: Boolean;
    /// <summary>Spalten in Anzeigereihenfolge: Spalten des Boards, dahinter -1, wenn Karten ohne Spalte
    /// sichtbar sind.</summary>
    Columns: TArray<Integer>;
    /// <summary>Kopfzeile und ganze Fläche je Spalte (gleicher Index wie Columns).</summary>
    Headers: TArray<TRect>;
    Areas: TArray<TRect>;
    /// <summary>Sichtbare Karten je Spalte gezählt (gleicher Index wie Columns).</summary>
    Counts: TArray<Integer>;
    Places: TArray<TAtlasBoardPlace>;
    /// <summary>Swimlanes (nur breit); leer ohne.</summary>
    Lanes: TArray<TAtlasBoardLane>;
    /// <summary>Namensfeld je Swimlane über die Höhe der Zeile (gleicher Index wie Lanes).</summary>
    LaneBoxes: TArray<TRect>;
    /// <summary>Sichtbare Karten je Swimlane (gleicher Index wie Lanes).</summary>
    LaneCounts: TArray<Integer>;
    /// <summary>Kopf über den Namen der Swimlanes; leer ohne.</summary>
    Corner: TRect;
    Width: Integer;
    Height: Integer;
    /// <summary>AVisible: Karten nach Filter; ACollapsed: eingeklappte Spalten (Nummer im Board, -1 für „ohne
    /// Spalte“), nur schmal wirksam.</summary>
    class function Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>; AWidth: Integer;
      const ACollapsed: TArray<Integer>; const AMetrics: TAtlasBoardMetrics): TAtlasBoardLayout; overload; static;
    /// <summary>Wie oben; ACollapsedLanes: eingeklappte Swimlanes (LaneKey). Sind nicht alle Karten sichtbar
    /// (Filter), entfallen Swimlanes ohne sichtbare Karte.</summary>
    class function Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>; AWidth: Integer;
      const ACollapsed: TArray<Integer>; const ACollapsedLanes: TArray<string>;
      const AMetrics: TAtlasBoardMetrics): TAtlasBoardLayout; overload; static;
    /// <summary>Schlüssel zum Einklappen einer Swimlane: ihr Name, '' für die Zeile ohne Wert.</summary>
    class function LaneKey(const ALane: TAtlasBoardLane): string; static;
    /// <summary>Swimlane, deren Namensfeld unter APoint liegt; -1 ohne.</summary>
    function LaneAt(const APoint: TPoint): Integer;
    /// <summary>Nummer der Karte unter APoint; -1 ohne.</summary>
    function CardAt(const APoint: TPoint): Integer;
    /// <summary>Spalte des Boards unter APoint (Fläche bzw. Kopf); cNoColumn ohne.</summary>
    function ColumnAt(const APoint: TPoint): Integer;
    /// <summary>Spalte, deren Kopfzeile unter APoint liegt; cNoColumn ohne.</summary>
    function HeaderAt(const APoint: TPoint): Integer;
    /// <summary>Lage der Karte ACard; False, wenn sie nicht zu sehen ist.</summary>
    function PlaceOf(ACard: Integer; out APlace: TAtlasBoardPlace): Boolean;
  end;

  /// <summary>Eingeklappte Spalten (Nummer im Board, -1 für „ohne Spalte“; nur schmal wirksam) und Swimlanes
  /// (TAtlasBoardLayout.LaneKey).</summary>
  TAtlasBoardFolds = class
  private
    FColumns: TArray<Integer>;
    FLanes: TArray<string>;
  public
    destructor Destroy; override;
    /// <summary>Spalte AColumn ein- bzw. ausklappen.</summary>
    procedure ToggleColumn(AColumn: Integer);
    function Collapsed(AColumn: Integer): Boolean;
    /// <summary>Swimlane mit dem Schlüssel AKey ein- bzw. ausklappen.</summary>
    procedure ToggleLane(const AKey: string);
    function LaneCollapsed(const AKey: string): Boolean;
    property Columns: TArray<Integer> read FColumns;
    property Lanes: TArray<string> read FLanes;
  end;

implementation

uses
  System.Math;

const
  /// <summary>Breite der Spalte mit den Namen der Swimlanes bei 96 dpi.</summary>
  cLaneWidth = 140;
  cColumnWidth = 180;
  cGap = 8;
  /// <summary>Karte: Kopfzeile und zwei Zeilen Titel, dazu die Ränder.</summary>
  cCardLines = 3;
  cCardPadding = 16;
  /// <summary>Abstand der Karte zum Rand ihrer Spalte.</summary>
  cCardInset = 4;

type
  /// <summary>Eine Swimlane beim Anordnen: Nummer, Oberkante, Breite der Spalten, eingeklappt.</summary>
  TLaneRow = record
    Lane: Integer;
    Top: Integer;
    ColumnWidth: Integer;
    Collapsed: Boolean;
  end;

/// <summary>AValue * AMultiplier / ADivider, gerundet wie MulDiv (Maße sind nicht negativ).</summary>
function ScaleBy(AValue, AMultiplier, ADivider: Integer): Integer;
begin
  Result := Integer((Int64(AValue) * AMultiplier + ADivider div 2) div ADivider);
end;

{ TAtlasBoardMetrics }

class function TAtlasBoardMetrics.Create(ALineHeight: Integer): TAtlasBoardMetrics;
begin
  Result.ColumnWidth := cColumnWidth;
  Result.Gap := cGap;
  Result.Header := ALineHeight + 10;
  Result.CardHeight := cCardLines * ALineHeight + cCardPadding;
  Result.NarrowWidth := TAtlasTrackerBoard.cNarrowWidth;
  Result.LaneWidth := cLaneWidth;
end;

function TAtlasBoardMetrics.Scaled(AMultiplier, ADivider: Integer): TAtlasBoardMetrics;
begin
  Result := Self;
  if (ADivider <= 0) or (AMultiplier = ADivider) then
  begin
    Exit;
  end;
  Result.ColumnWidth := ScaleBy(ColumnWidth, AMultiplier, ADivider);
  Result.Gap := ScaleBy(Gap, AMultiplier, ADivider);
  Result.NarrowWidth := ScaleBy(NarrowWidth, AMultiplier, ADivider);
  Result.LaneWidth := ScaleBy(LaneWidth, AMultiplier, ADivider);
end;

{ TAtlasBoardLayout }

function Contains(const AItems: TArray<Integer>; AValue: Integer): Boolean;
var
  mItem: Integer;
begin
  Result := False;
  for mItem in AItems do
  begin
    if mItem = AValue then
    begin
      Exit(True);
    end;
  end;
end;

function ContainsKey(const AItems: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AItems do
  begin
    if mItem = AValue then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Spalten in Anzeigereihenfolge: die des Boards, dahinter -1, wenn Karten ohne Spalte sichtbar sind.
/// </summary>
function ColumnsOf(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ASnapshot.Columns) do
  begin
    Result := Result + [mIndex];
  end;
  if Length(TAtlasTrackerBoard.ColumnCards(ASnapshot, AVisible, -1)) > 0 then
  begin
    Result := Result + [-1];
  end;
end;

/// <summary>Breite einer Spalte: schmal die ganze Fläche, sonst gleichmäßig, mindestens ColumnWidth.</summary>
function ColumnWidthOf(AWidth, ACount: Integer; ANarrow: Boolean; const AMetrics: TAtlasBoardMetrics): Integer;
begin
  if ANarrow then
  begin
    Result := Max(AWidth - 2 * AMetrics.Gap, 1);
  end
  else
  begin
    Result := Max(AMetrics.ColumnWidth, (AWidth - (ACount + 1) * AMetrics.Gap) div ACount);
  end;
end;

/// <summary>Karten ACards der Spalte AColumn untereinander unter AColumnBox.Top, zwischen AColumnBox.Left und
/// .Right; Ergebnis: Unterkante der letzten Karte (ohne Karten AColumnBox.Top).</summary>
function PlaceCards(var ALayout: TAtlasBoardLayout; const ACards: TArray<Integer>; AColumn: Integer;
  const AColumnBox: TRect; const AMetrics: TAtlasBoardMetrics): Integer;
var
  mCard: Integer;
  mPlace: TAtlasBoardPlace;
begin
  Result := AColumnBox.Top;
  for mCard in ACards do
  begin
    mPlace.Card := mCard;
    mPlace.Column := AColumn;
    mPlace.Bounds := Rect(AColumnBox.Left + cCardInset, Result + AMetrics.Gap div 2, AColumnBox.Right - cCardInset,
      Result + AMetrics.Gap div 2 + AMetrics.CardHeight);
    ALayout.Places := ALayout.Places + [mPlace];
    Result := mPlace.Bounds.Bottom;
  end;
end;

{ TAtlasBoardLayout }

class function TAtlasBoardLayout.Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>;
  AWidth: Integer; const ACollapsed: TArray<Integer>; const AMetrics: TAtlasBoardMetrics): TAtlasBoardLayout;
begin
  Result := Build(ASnapshot, AVisible, AWidth, ACollapsed, nil, AMetrics);
end;

/// <summary>Linke Kante der Spalte AIndex neben den Namen der Swimlanes.</summary>
function LaneColumnLeft(AIndex, AColumnWidth: Integer; const AMetrics: TAtlasBoardMetrics): Integer;
begin
  Result := 2 * AMetrics.Gap + AMetrics.LaneWidth + AIndex * (AColumnWidth + AMetrics.Gap);
end;

/// <summary>Karten der Swimlane ALane in ihre Zellen; Ergebnis: Unterkante der Zeile ab ATop.</summary>
function PlaceLane(var ALayout: TAtlasBoardLayout; const ASnapshot: TAtlasBoardSnapshot;
  const AVisible: TArray<Integer>; const ARow: TLaneRow; const AMetrics: TAtlasBoardMetrics): Integer;
var
  mIndex, mLeft: Integer;
  mCards: TArray<Integer>;
begin
  Result := ARow.Top + AMetrics.Header;
  if not ARow.Collapsed then
  begin
    // Leere Zeile: Platz zum Ablegen.
    Result := ARow.Top + AMetrics.CardHeight div 2 + AMetrics.Gap;
  end;
  for mIndex := 0 to High(ALayout.Columns) do
  begin
    mCards := TAtlasBoardLanes.CellCards(ASnapshot, ALayout.Lanes, AVisible, ALayout.Columns[mIndex], ARow.Lane);
    Inc(ALayout.Counts[mIndex], Length(mCards));
    Inc(ALayout.LaneCounts[ARow.Lane], Length(mCards));
    if not ARow.Collapsed then
    begin
      mLeft := LaneColumnLeft(mIndex, ARow.ColumnWidth, AMetrics);
      Result := Max(Result, PlaceCards(ALayout, mCards, ALayout.Columns[mIndex], Rect(mLeft, ARow.Top,
        mLeft + ARow.ColumnWidth, ARow.Top), AMetrics) + AMetrics.Gap div 2);
    end;
  end;
end;

/// <summary>Breit mit Swimlanes: links die Namen, rechts die Spalten; je Swimlane eine Zeile mit Zellen. False
/// ohne Swimlanes (nichts angeordnet).</summary>
function BuildLanes(var ALayout: TAtlasBoardLayout; const ASnapshot: TAtlasBoardSnapshot;
  const AVisible: TArray<Integer>; AWidth: Integer; const ACollapsedLanes: TArray<string>;
  const AMetrics: TAtlasBoardMetrics): Boolean;
var
  mIndex, mCount, mColumnWidth, mLeft, mTop: Integer;
  mRow: TLaneRow;
begin
  ALayout.Lanes := TAtlasBoardLanes.Build(ASnapshot, AVisible, Length(AVisible) < Length(ASnapshot.Cards));
  Result := Length(ALayout.Lanes) > 0;
  if not Result then
  begin
    Exit;
  end;
  mCount := Length(ALayout.Columns);
  mColumnWidth := Max(AMetrics.ColumnWidth, (AWidth - AMetrics.LaneWidth - (mCount + 2) * AMetrics.Gap) div mCount);
  ALayout.Corner := Rect(AMetrics.Gap, AMetrics.Gap, AMetrics.Gap + AMetrics.LaneWidth, AMetrics.Gap + AMetrics.Header);
  SetLength(ALayout.LaneBoxes, Length(ALayout.Lanes));
  SetLength(ALayout.LaneCounts, Length(ALayout.Lanes));
  mTop := ALayout.Corner.Bottom;
  for mIndex := 0 to High(ALayout.Lanes) do
  begin
    mRow.Lane := mIndex;
    mRow.Top := mTop;
    mRow.ColumnWidth := mColumnWidth;
    mRow.Collapsed := ContainsKey(ACollapsedLanes, TAtlasBoardLayout.LaneKey(ALayout.Lanes[mIndex]));
    mTop := PlaceLane(ALayout, ASnapshot, AVisible, mRow, AMetrics);
    ALayout.LaneBoxes[mIndex] := Rect(AMetrics.Gap, mRow.Top, AMetrics.Gap + AMetrics.LaneWidth, mTop);
  end;
  mLeft := AMetrics.Gap;
  for mIndex := 0 to mCount - 1 do
  begin
    mLeft := LaneColumnLeft(mIndex, mColumnWidth, AMetrics);
    ALayout.Headers[mIndex] := Rect(mLeft, AMetrics.Gap, mLeft + mColumnWidth, AMetrics.Gap + AMetrics.Header);
    ALayout.Areas[mIndex] := Rect(mLeft, AMetrics.Gap, mLeft + mColumnWidth, mTop);
  end;
  ALayout.Height := mTop + AMetrics.Gap;
  ALayout.Width := Max(AWidth, mLeft + mColumnWidth + AMetrics.Gap);
end;

class function TAtlasBoardLayout.Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>;
  AWidth: Integer; const ACollapsed: TArray<Integer>; const ACollapsedLanes: TArray<string>;
  const AMetrics: TAtlasBoardMetrics): TAtlasBoardLayout;
var
  mIndex, mCount, mColumnWidth, mLeft, mTop, mBottom: Integer;
  mCards: TArray<Integer>;
begin
  Result := Default(TAtlasBoardLayout);
  Result.Columns := ColumnsOf(ASnapshot, AVisible);
  mCount := Length(Result.Columns);
  SetLength(Result.Headers, mCount);
  SetLength(Result.Areas, mCount);
  SetLength(Result.Counts, mCount);
  Result.Narrow := AWidth < AMetrics.NarrowWidth;
  if mCount = 0 then
  begin
    Exit;
  end;
  if not Result.Narrow and BuildLanes(Result, ASnapshot, AVisible, AWidth, ACollapsedLanes, AMetrics) then
  begin
    Exit;
  end;
  mColumnWidth := ColumnWidthOf(AWidth, mCount, Result.Narrow, AMetrics);
  mLeft := AMetrics.Gap;
  mTop := AMetrics.Gap;
  for mIndex := 0 to mCount - 1 do
  begin
    mCards := TAtlasTrackerBoard.ColumnCards(ASnapshot, AVisible, Result.Columns[mIndex]);
    Result.Counts[mIndex] := Length(mCards);
    if not Result.Narrow then
    begin
      mTop := AMetrics.Gap;
    end;
    Result.Headers[mIndex] := Rect(mLeft, mTop, mLeft + mColumnWidth, mTop + AMetrics.Header);
    mBottom := mTop + AMetrics.Header;
    if not (Result.Narrow and Contains(ACollapsed, Result.Columns[mIndex])) then
    begin
      mBottom := PlaceCards(Result, mCards, Result.Columns[mIndex], Rect(mLeft, mBottom, mLeft + mColumnWidth,
        mBottom), AMetrics);
    end;
    // Leere Spalte: Platz zum Ablegen.
    mBottom := Max(mBottom + AMetrics.Gap div 2, mTop + AMetrics.Header + AMetrics.CardHeight div 2);
    Result.Areas[mIndex] := Rect(mLeft, mTop, mLeft + mColumnWidth, mBottom);
    Result.Height := Max(Result.Height, mBottom + AMetrics.Gap);
    if Result.Narrow then
    begin
      mTop := mBottom + AMetrics.Gap;
    end
    else
    begin
      mLeft := mLeft + mColumnWidth + AMetrics.Gap;
    end;
  end;
  Result.Width := AWidth;
  if not Result.Narrow then
  begin
    Result.Width := Max(AWidth, mLeft);
  end;
end;

class function TAtlasBoardLayout.LaneKey(const ALane: TAtlasBoardLane): string;
begin
  Result := '';
  if not ALane.Orphans then
  begin
    Result := ALane.Name;
  end;
end;

function TAtlasBoardLayout.LaneAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(LaneBoxes) do
  begin
    if LaneBoxes[mIndex].Contains(APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasBoardLayout.CardAt(const APoint: TPoint): Integer;
var
  mPlace: TAtlasBoardPlace;
begin
  for mPlace in Places do
  begin
    if mPlace.Bounds.Contains(APoint) then
    begin
      Exit(mPlace.Card);
    end;
  end;
  Result := -1;
end;

function TAtlasBoardLayout.ColumnAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Areas) do
  begin
    if Areas[mIndex].Contains(APoint) then
    begin
      Exit(Columns[mIndex]);
    end;
  end;
  Result := cNoColumn;
end;

function TAtlasBoardLayout.HeaderAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Headers) do
  begin
    if Headers[mIndex].Contains(APoint) then
    begin
      Exit(Columns[mIndex]);
    end;
  end;
  Result := cNoColumn;
end;

function TAtlasBoardLayout.PlaceOf(ACard: Integer; out APlace: TAtlasBoardPlace): Boolean;
var
  mPlace: TAtlasBoardPlace;
begin
  for mPlace in Places do
  begin
    if mPlace.Card = ACard then
    begin
      APlace := mPlace;
      Exit(True);
    end;
  end;
  APlace := Default(TAtlasBoardPlace);
  Result := False;
end;

{ TAtlasBoardFolds }

destructor TAtlasBoardFolds.Destroy;
begin
  FColumns := nil;
  FLanes := nil;
  inherited;
end;

procedure TAtlasBoardFolds.ToggleColumn(AColumn: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FColumns) do
  begin
    if FColumns[mIndex] = AColumn then
    begin
      Delete(FColumns, mIndex, 1);
      Exit;
    end;
  end;
  FColumns := FColumns + [AColumn];
end;

function TAtlasBoardFolds.Collapsed(AColumn: Integer): Boolean;
begin
  Result := Contains(FColumns, AColumn);
end;

procedure TAtlasBoardFolds.ToggleLane(const AKey: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FLanes) do
  begin
    if FLanes[mIndex] = AKey then
    begin
      Delete(FLanes, mIndex, 1);
      Exit;
    end;
  end;
  FLanes := FLanes + [AKey];
end;

function TAtlasBoardFolds.LaneCollapsed(const AKey: string): Boolean;
begin
  Result := ContainsKey(FLanes, AKey);
end;

end.
