unit Atlas.UI.Tracker.BoardFrame;

// Inhalt des andockbaren Fensters „Atlas-Board“ (#1272), reine VCL ohne Open
// Tools API:
//   [Board ▾] [Sprint ▾] [Nur meine|Alle] [Suchen …] [Aktualisieren]
//   (Stand vom … bzw. Fehler, Verschieben …)
//   OFFEN (3)        IN ARBEIT (2)      ZUR PRÜFUNG (1)    ERLEDIGT (4)
//   ┃ATL-123   ⛔ 3/5 MB
//   ┃Titel in zwei
//   ┃Zeilen …
// Karte: Kennung, Titel (zwei Zeilen), Zuständig als Kürzel, Priorität als
// Farbbalken links, Fortschritt der Checkliste (#1273), Schloss bei offenem
// „hängt ab von“ (#1279), Rahmen in Akzentfarbe beim aktuellen Issue (#765).
// Schmaler als 360 px: Spalten untereinander als einklappbare Gruppen (Klick
// auf die Kopfzeile). Hat das Board Swimlanes (TAtlasBoardLanes), steht breit
// links eine Spalte mit einer Zeile je Wert (z. B. je Zuständigem), die Karten
// in den Zellen darunter; Klick auf den Namen klappt die Zeile, die eigene
// Zeile ist links in Akzentfarbe markiert. Ziehen in eine andere Zeile ändert
// nur die Spalte. Ziehen einer Karte in eine andere Spalte meldet
// Events.Move; die IDE-Schicht fragt nach, schreibt und ruft danach MoveCard
// (sofort sichtbar) bzw. RevertMove (springt zurück); Spalten, die der
// Workflow des Trackers sicher ausschließt (TAtlasBoardTransitions), werden
// beim Ziehen nicht hervorgehoben. Klick meldet Events.Open,
// Doppelklick Events.Start, Rechtsklick zeigt das Kontextmenü (Beginnen, Prüfen …,
// Vorschau, Im Browser öffnen, Kennung kopieren, Mir zuweisen). Mit
// CanDrag = False (ohne Netz) lässt sich nichts ziehen. Filter „Nur meine“
// und Suche wirken lokal. Netz, Zwischenspeicher und Schreiben liegen in der
// IDE-Schicht. Die DFM ist leer, weil TCustomFrame.Create für abgeleitete
// Frames eine Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
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
    /// <summary>Spalte des Boards unter APoint (Fläche bzw. Kopf); -2 ohne.</summary>
    function ColumnAt(const APoint: TPoint): Integer;
    /// <summary>Spalte, deren Kopfzeile unter APoint liegt; -2 ohne.</summary>
    function HeaderAt(const APoint: TPoint): Integer;
    /// <summary>Lage der Karte ACard; False, wenn sie nicht zu sehen ist.</summary>
    function PlaceOf(ACard: Integer; out APlace: TAtlasBoardPlace): Boolean;
  end;

  TAtlasBoardCardEvent = reference to procedure(ACard: Integer);
  TAtlasBoardMoveEvent = reference to procedure(ACard, AColumn: Integer);

  /// <summary>Ereignisse der Zeichenfläche; nil = nichts.</summary>
  TAtlasBoardViewEvents = record
    Open: TAtlasBoardCardEvent;
    Start: TAtlasBoardCardEvent;
    Move: TAtlasBoardMoveEvent;
    /// <summary>Rechtsklick auf eine Karte; Punkt in Bildschirmkoordinaten.</summary>
    Context: TProc<Integer, TPoint>;
    /// <summary>Beschriftung einer Spalte (Board-Nummer, -1 = ohne Spalte).</summary>
    ColumnName: TFunc<Integer, string>;
  end;

  /// <summary>Zeichenfläche des Boards: Spalten, Karten, Ziehen.</summary>
  TAtlasBoardView = class(TCustomControl)
  public const
    /// <summary>So weit (Pixel bei 96 dpi) muss die Maus wandern, bis aus einem Klick ein Ziehen wird.</summary>
    cDragDistance = 5;
  private
    FSnapshot: TAtlasBoardSnapshot;
    FVisible: TArray<Integer>;
    FLayout: TAtlasBoardLayout;
    FColors: TAtlasColors;
    FCollapsed: TArray<Integer>;
    FCollapsedLanes: TArray<string>;
    FActiveKey: string;
    FCanDrag: Boolean;
    FPressCard: Integer;
    FPressPoint: TPoint;
    FDragging: Boolean;
    FDragPoint: TPoint;
    FDropColumn: Integer;
    FEvents: TAtlasBoardViewEvents;
    function Metrics: TAtlasBoardMetrics;
    procedure PaintCard(const APlace: TAtlasBoardPlace; const ABounds: TRect; AGhost: Boolean);
    procedure PaintColumn(AIndex: Integer);
    procedure PaintLane(AIndex: Integer);
    procedure CancelDrag;
    procedure CMMouseLeave(var AMessage: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Neu anordnen für die Breite AWidth; setzt Width und Height auf den Inhalt.</summary>
    procedure Relayout(AWidth: Integer);
    procedure SetData(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>);
    procedure ToggleColumn(AColumn: Integer);
    function Collapsed(AColumn: Integer): Boolean;
    /// <summary>Swimlane mit dem Schlüssel AKey (TAtlasBoardLayout.LaneKey) ein- bzw. ausklappen.</summary>
    procedure ToggleLane(const AKey: string);
    function LaneCollapsed(const AKey: string): Boolean;
    property Snapshot: TAtlasBoardSnapshot read FSnapshot;
    property Layout: TAtlasBoardLayout read FLayout;
    property Colors: TAtlasColors read FColors write FColors;
    property ActiveKey: string read FActiveKey write FActiveKey;
    property CanDrag: Boolean read FCanDrag write FCanDrag;
    property Events: TAtlasBoardViewEvents read FEvents write FEvents;
  end;

  /// <summary>Ereignisse des Frames; nil = nichts.</summary>
  TAtlasBoardFrameEvents = record
    Open: TAtlasBoardCardEvent;
    Start: TAtlasBoardCardEvent;
    /// <summary>„Prüfen …“ (#2126).</summary>
    Review: TAtlasBoardCardEvent;
    Browse: TAtlasBoardCardEvent;
    Assign: TAtlasBoardCardEvent;
    Move: TAtlasBoardMoveEvent;
    Refresh: TProc;
    /// <summary>Anderes Board gewählt (ID).</summary>
    Board: TProc<string>;
    /// <summary>Anderer Sprint gewählt (ID).</summary>
    Sprint: TProc<string>;
    OnlyMine: TProc<Boolean>;
    /// <summary>Fenster geschlossen bzw. versteckt.</summary>
    Hidden: TProc;
  end;

  /// <summary>Steuerelemente des Frames; sie gehören dem Frame.</summary>
  TAtlasBoardFrameParts = record
    Head: TFlowPanel;
    Boards: TComboBox;
    Sprints: TComboBox;
    Mine: TSpeedButton;
    All: TSpeedButton;
    Search: TEdit;
    Refresh: TButton;
    Status: TLabel;
    Scroll: TScrollBox;
    View: TAtlasBoardView;
    Empty: TLabel;
    Menu: TPopupMenu;
  end;

  TAtlasBoardFrame = class(TFrame)
  private
    FParts: TAtlasBoardFrameParts;
    FMenuCard: Integer;
    FColors: TAtlasColors;
    FSnapshot: TAtlasBoardSnapshot;
    FHasSnapshot: Boolean;
    FFilling: Boolean;
    FOnlyMine: Boolean;
    FBoardIds: TArray<string>;
    FSprintIds: TArray<string>;
    FEvents: TAtlasBoardFrameEvents;
    procedure UpdateView;
    /// <summary>Board, Sprint oder Suche geändert.</summary>
    procedure ChoiceChange(Sender: TObject);
    /// <summary>„Nur meine“, „Alle“ oder „Aktualisieren“.</summary>
    procedure ButtonClick(Sender: TObject);
    procedure ScrollResize(Sender: TObject);
    /// <summary>Eintrag des Kontextmenüs (Tag: TBoardMenu).</summary>
    procedure MenuClick(Sender: TObject);
    procedure CMShowingChanged(var AMessage: TMessage); message CM_SHOWINGCHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Stand zeigen; AStatus: Zeile über den Karten ("Stand vom …", Fehler), '' = keine.</summary>
    procedure SetSnapshot(const ASnapshot: TAtlasBoardSnapshot; const AStatus: string);
    /// <summary>Kein Board zu zeigen (kein Tracker, kein Board): Text in der Mitte.</summary>
    procedure ShowNotice(const AText: string);
    procedure SetStatus(const AText: string);
    procedure SetLoading(AValue: Boolean);
    /// <summary>Karte ACard steht sofort in Spalte AColumn (vor dem Schreiben); liefert den alten Wert.</summary>
    function MoveCard(ACard, AColumn: Integer): string;
    /// <summary>Karte AKey springt zurück auf den Wert AState.</summary>
    procedure RevertMove(const AKey, AState: string);
    /// <summary>Kennung des aktuellen Issues (#765): Rahmen in Akzentfarbe.</summary>
    procedure SetActiveKey(const AKey: string);
    /// <summary>Ziehen erlaubt (Verbindung und Schreibweg da).</summary>
    procedure SetCanDrag(AValue: Boolean);
    /// <summary>Umschalter „Nur meine“/„Alle“ ohne OnlyMine-Ereignis.</summary>
    procedure SetOnlyMine(AValue: Boolean);
    /// <summary>Karten nach Filter und Suche.</summary>
    function VisibleCards: TArray<Integer>;
    function StatusText: string;
    function Card(AIndex: Integer): TAtlasBoardCard;
    /// <summary>Beschriftung der Spalte AColumn (-1 = „Ohne Spalte“; GitHub ohne Projekt übersetzt).</summary>
    function ColumnCaption(AColumn: Integer): string;
    property Snapshot: TAtlasBoardSnapshot read FSnapshot;
    property HasSnapshot: Boolean read FHasSnapshot;
    property OnlyMine: Boolean read FOnlyMine;
    property View: TAtlasBoardView read FParts.View;
    property Parts: TAtlasBoardFrameParts read FParts;
    property Events: TAtlasBoardFrameEvents read FEvents write FEvents;
  end;

/// <summary>"#rrggbb" als Farbe; False bei anderem Text.</summary>
function TryWebColor(const AText: string; out AColor: TColor): Boolean;

implementation

uses
  Atlas.Core.Style.Color,
  System.Math,
  Winapi.Windows,
  Vcl.Clipbrd,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Tracker.Board.Strings,
  Atlas.UI.Tracker.Workflow.Strings;

{$R *.dfm}

const
  /// <summary>Breite der Spalte mit den Namen der Swimlanes bei 96 dpi.</summary>
  cLaneWidth = 140;
  /// <summary>Breite der Markierung der eigenen Swimlane bei 96 dpi.</summary>
  cLaneMark = 3;
  /// <summary>Innenabstand im Namensfeld einer Swimlane und im Kopf darüber bei 96 dpi.</summary>
  cLaneInset = 6;

type
  /// <summary>Eine Swimlane beim Anordnen: Nummer, Oberkante, Breite der Spalten, eingeklappt.</summary>
  TLaneRow = record
    Lane: Integer;
    Top: Integer;
    ColumnWidth: Integer;
    Collapsed: Boolean;
  end;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function TryWebColor(const AText: string; out AColor: TColor): Boolean;
var
  mValue: Integer;
  mText: string;
begin
  AColor := clNone;
  mText := Trim(AText);
  Result := (Length(mText) = 7) and (mText[1] = '#') and TryStrToInt('$' + Copy(mText, 2, 6), mValue);
  if Result then
  begin
    // #rrggbb → TColor $bbggrr.
    AColor := TColor(((mValue and $FF) shl 16) or (mValue and $FF00) or ((mValue shr 16) and $FF));
  end;
end;

{ TAtlasBoardMetrics }

class function TAtlasBoardMetrics.Create(ALineHeight: Integer): TAtlasBoardMetrics;
begin
  Result.ColumnWidth := 180;
  Result.Gap := 8;
  Result.Header := ALineHeight + 10;
  // Kopfzeile der Karte, zwei Zeilen Titel, Ränder.
  Result.CardHeight := 3 * ALineHeight + 16;
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
  Result.ColumnWidth := MulDiv(ColumnWidth, AMultiplier, ADivider);
  Result.Gap := MulDiv(Gap, AMultiplier, ADivider);
  Result.NarrowWidth := MulDiv(NarrowWidth, AMultiplier, ADivider);
  Result.LaneWidth := MulDiv(LaneWidth, AMultiplier, ADivider);
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
    mPlace.Bounds := Rect(AColumnBox.Left + 4, Result + AMetrics.Gap div 2, AColumnBox.Right - 4,
      Result + AMetrics.Gap div 2 + AMetrics.CardHeight);
    ALayout.Places := ALayout.Places + [mPlace];
    Result := mPlace.Bounds.Bottom;
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
  AWidth: Integer; const ACollapsed: TArray<Integer>; const AMetrics: TAtlasBoardMetrics): TAtlasBoardLayout;
begin
  Result := Build(ASnapshot, AVisible, AWidth, ACollapsed, nil, AMetrics);
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
  Result := -2;
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
  Result := -2;
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

{ TAtlasBoardView }

constructor TAtlasBoardView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks];
  DoubleBuffered := True;
  TabStop := True;
  FColors := TAtlasColors.Light;
  FPressCard := -1;
  FDropColumn := -2;
end;

function TAtlasBoardView.Metrics: TAtlasBoardMetrics;
var
  mLine: Integer;
begin
  mLine := Abs(Font.Height);
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    mLine := Canvas.TextHeight('Ag');
  end
  else if mLine < 8 then
  begin
    mLine := 15;
  end;
  // Zeilenhöhe ist schon in Bildschirmpixeln; Breiten und Abstände skalieren mit der Schrift.
  Result := TAtlasBoardMetrics.Create(mLine).Scaled(CurrentPPI, 96);
end;

procedure TAtlasBoardView.SetData(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>);
begin
  CancelDrag;
  FSnapshot := ASnapshot;
  FVisible := AVisible;
end;

procedure TAtlasBoardView.Relayout(AWidth: Integer);
begin
  FLayout := TAtlasBoardLayout.Build(FSnapshot, FVisible, AWidth, FCollapsed, FCollapsedLanes, Metrics);
  SetBounds(0, 0, FLayout.Width, Max(FLayout.Height, 1));
  Invalidate;
end;

function TAtlasBoardView.Collapsed(AColumn: Integer): Boolean;
begin
  Result := Contains(FCollapsed, AColumn);
end;

procedure TAtlasBoardView.ToggleColumn(AColumn: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FCollapsed) do
  begin
    if FCollapsed[mIndex] = AColumn then
    begin
      Delete(FCollapsed, mIndex, 1);
      Exit;
    end;
  end;
  FCollapsed := FCollapsed + [AColumn];
end;

function TAtlasBoardView.LaneCollapsed(const AKey: string): Boolean;
begin
  Result := ContainsKey(FCollapsedLanes, AKey);
end;

procedure TAtlasBoardView.ToggleLane(const AKey: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FCollapsedLanes) do
  begin
    if FCollapsedLanes[mIndex] = AKey then
    begin
      Delete(FCollapsedLanes, mIndex, 1);
      Exit;
    end;
  end;
  FCollapsedLanes := FCollapsedLanes + [AKey];
end;

function PriorityColor(const ACard: TAtlasBoardCard; const AColors: TAtlasColors): TColor;
begin
  if TryWebColor(ACard.PriorityColor, Result) then
  begin
    Exit;
  end;
  case TAtlasTrackerBoard.PriorityLevel(ACard.Priority) of
    4:
      Result := ToColor(AColors.Error);
    3:
      Result := ToColor(AColors.Warn);
    2:
      Result := ToColor(AColors.Accent);
    1:
      Result := ToColor(AColors.Muted);
  else
    Result := ToColor(AColors.Line);
  end;
end;

/// <summary>Rahmen der Karte (aktuelles Issue in Akzentfarbe, gezogen gepunktet) und Farbbalken der Priorität.
/// </summary>
procedure PaintCardFrame(ACanvas: TCanvas; const AColors: TAtlasColors; const ABounds: TRect; AActive,
  AGhost: Boolean; APriority: TColor);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ToColor(AColors.Surface);
  ACanvas.Pen.Color := ToColor(AColors.Line);
  ACanvas.Pen.Width := 1;
  if AActive then
  begin
    ACanvas.Pen.Color := ToColor(AColors.Accent);
    ACanvas.Pen.Width := 2;
  end;
  ACanvas.Pen.Style := psSolid;
  if AGhost then
  begin
    ACanvas.Pen.Style := psDot;
  end;
  ACanvas.Rectangle(ABounds);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Brush.Color := APriority;
  ACanvas.FillRect(Rect(ABounds.Left + 1, ABounds.Top + 1, ABounds.Left + 5, ABounds.Bottom - 1));
  ACanvas.Brush.Style := bsClear;
end;

/// <summary>Kürzel des Zuständigen rechts oben bis ARight; Ergebnis: neuer rechter Rand.</summary>
function PaintAssignee(ACanvas: TCanvas; const AColors: TAtlasColors; const AMark: string; ARight, ATop,
  ALine: Integer): Integer;
var
  mText: TRect;
begin
  ACanvas.Font.Style := [fsBold];
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ToColor(AColors.AccentSoft);
  mText := Rect(ARight - ACanvas.TextWidth(AMark) - 6, ATop, ARight, ATop + ALine);
  ACanvas.FillRect(mText);
  ACanvas.Font.Color := ToColor(AColors.Text);
  DrawText(ACanvas.Handle, PChar(AMark), Length(AMark), mText, DT_CENTER or DT_SINGLELINE or DT_VCENTER);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Style := [];
  ACanvas.Font.Color := ToColor(AColors.Muted);
  Result := mText.Left - 6;
end;

/// <summary>Text AMark rechtsbündig bis ARight; Ergebnis: neuer rechter Rand.</summary>
function PaintMark(ACanvas: TCanvas; const AMark: string; ARight, ATop, ALine: Integer): Integer;
var
  mText: TRect;
begin
  mText := Rect(ARight - ACanvas.TextWidth(AMark), ATop, ARight, ATop + ALine);
  DrawText(ACanvas.Handle, PChar(AMark), Length(AMark), mText, DT_RIGHT or DT_SINGLELINE);
  Result := mText.Left - 6;
end;

/// <summary>Kopfzeile rechts: Kürzel, Checkliste, Schloss; Ergebnis: Platz für die Kennung bis hier.</summary>
function PaintMarks(ACanvas: TCanvas; const AColors: TAtlasColors; const ACard: TAtlasBoardCard;
  const ABounds: TRect; ALine: Integer): Integer;
var
  mMark: string;
begin
  Result := ABounds.Right - 6;
  ACanvas.Font.Style := [];
  ACanvas.Font.Color := ToColor(AColors.Muted);
  mMark := TAtlasTrackerBoard.Initials(ACard.Assignee);
  if mMark <> '' then
  begin
    Result := PaintAssignee(ACanvas, AColors, mMark, Result, ABounds.Top + 4, ALine);
  end;
  if ACard.Checklist.Any then
  begin
    if ACard.Checklist.Done = ACard.Checklist.Total then
    begin
      ACanvas.Font.Color := ToColor(AColors.Add);
    end;
    Result := PaintMark(ACanvas, ACard.Checklist.Text, Result, ABounds.Top + 4, ALine);
    ACanvas.Font.Color := ToColor(AColors.Muted);
  end;
  if ACard.Locked then
  begin
    Result := PaintMark(ACanvas, '⛔', Result, ABounds.Top + 4, ALine);
  end;
end;

procedure TAtlasBoardView.PaintCard(const APlace: TAtlasBoardPlace; const ABounds: TRect; AGhost: Boolean);
var
  mCard: TAtlasBoardCard;
  mText: TRect;
  mLine, mRight: Integer;
begin
  mCard := FSnapshot.Cards[APlace.Card];
  mLine := Canvas.TextHeight('Ag');
  PaintCardFrame(Canvas, FColors, ABounds, SameText(mCard.Key, FActiveKey), AGhost, PriorityColor(mCard, FColors));
  // Kopfzeile: Kennung links; rechts Kürzel, Checkliste, Schloss.
  mRight := PaintMarks(Canvas, FColors, mCard, ABounds, mLine);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Accent);
  mText := Rect(ABounds.Left + 10, ABounds.Top + 4, Max(mRight, ABounds.Left + 10), ABounds.Top + 4 + mLine);
  DrawText(Canvas.Handle, PChar(mCard.Key), Length(mCard.Key), mText, DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS);
  // Titel in zwei Zeilen.
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(FColors.Text);
  mText := Rect(ABounds.Left + 10, ABounds.Top + 8 + mLine, ABounds.Right - 6, ABounds.Top + 8 + 3 * mLine);
  DrawText(Canvas.Handle, PChar(mCard.Title), Length(mCard.Title), mText,
    DT_LEFT or DT_WORDBREAK or DT_END_ELLIPSIS or DT_EDITCONTROL or DT_NOPREFIX);
end;

/// <summary>Kopfzeile einer Spalte: „NAME (n)“, schmal mit Pfeil zum Auf- und Zuklappen.</summary>
function ColumnTitle(AView: TAtlasBoardView; AIndex: Integer): string;
var
  mColumn: Integer;
  mName: string;
begin
  mColumn := AView.FLayout.Columns[AIndex];
  mName := '';
  if Assigned(AView.FEvents.ColumnName) then
  begin
    mName := AView.FEvents.ColumnName(mColumn);
  end;
  Result := TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardColumnCount,
    [AnsiUpperCase(mName), AView.FLayout.Counts[AIndex]]);
  if not AView.FLayout.Narrow then
  begin
    Exit;
  end;
  if AView.Collapsed(mColumn) then
  begin
    Result := '▸ ' + Result;
  end
  else
  begin
    Result := '▾ ' + Result;
  end;
end;

procedure TAtlasBoardView.PaintColumn(AIndex: Integer);
var
  mColumn: Integer;
  mText: string;
  mRect: TRect;
begin
  mColumn := FLayout.Columns[AIndex];
  // Fläche der Spalte; Ziel beim Ziehen hervorgehoben.
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  if FDragging and (mColumn = FDropColumn) and TAtlasBoardTransitions.Allowed(FSnapshot, FPressCard, mColumn) then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
  end;
  Canvas.FillRect(FLayout.Areas[AIndex]);
  mText := ColumnTitle(Self, AIndex);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Muted);
  mRect := FLayout.Headers[AIndex];
  InflateRect(mRect, -ScaleValue(6), 0);
  DrawText(Canvas.Handle, PChar(mText), Length(mText), mRect,
    DT_LEFT or DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
end;

/// <summary>Beschriftung einer Swimlane: Pfeil, Name bzw. „Ohne Zuordnung“, Anzahl.</summary>
function LaneTitle(AView: TAtlasBoardView; AIndex: Integer): string;
var
  mLane: TAtlasBoardLane;
  mName: string;
begin
  mLane := AView.FLayout.Lanes[AIndex];
  mName := mLane.Name;
  if mLane.Orphans then
  begin
    mName := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardLaneNone);
  end;
  Result := TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardColumnCount, [mName, AView.FLayout.LaneCounts[AIndex]]);
  if AView.LaneCollapsed(TAtlasBoardLayout.LaneKey(mLane)) then
  begin
    Result := '▸ ' + Result;
  end
  else
  begin
    Result := '▾ ' + Result;
  end;
end;

procedure TAtlasBoardView.PaintLane(AIndex: Integer);
var
  mBox, mText: TRect;
  mTitle: string;
begin
  mBox := FLayout.LaneBoxes[AIndex];
  // Trennlinie über die ganze Breite, Namensfeld links.
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Line);
  Canvas.FillRect(Rect(mBox.Left, mBox.Top, FLayout.Width - Metrics.Gap, mBox.Top + 1));
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(Rect(mBox.Left, mBox.Top + 1, mBox.Right, mBox.Bottom));
  if TAtlasBoardLanes.Mine(FLayout.Lanes[AIndex], FSnapshot.Me) then
  begin
    Canvas.Brush.Color := ToColor(FColors.Accent);
    Canvas.FillRect(Rect(mBox.Left, mBox.Top + 1, mBox.Left + ScaleValue(cLaneMark), mBox.Bottom));
  end;
  mTitle := LaneTitle(Self, AIndex);
  mText := Rect(mBox.Left + ScaleValue(cLaneMark + cLaneInset), mBox.Top + ScaleValue(cLaneInset),
    mBox.Right - ScaleValue(cLaneInset), mBox.Bottom);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  DrawText(Canvas.Handle, PChar(mTitle), Length(mTitle), mText,
    DT_LEFT or DT_WORDBREAK or DT_END_ELLIPSIS or DT_EDITCONTROL or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
end;

/// <summary>Kopf über den Namen der Swimlanes: Name des Feldes.</summary>
procedure PaintCorner(AView: TAtlasBoardView);
var
  mText: string;
  mRect: TRect;
begin
  mText := AnsiUpperCase(AView.FSnapshot.Swimlanes.Caption);
  mRect := AView.FLayout.Corner;
  InflateRect(mRect, -AView.ScaleValue(cLaneInset), 0);
  AView.Canvas.Brush.Style := bsClear;
  AView.Canvas.Font.Style := [fsBold];
  AView.Canvas.Font.Color := ToColor(AView.FColors.Muted);
  DrawText(AView.Canvas.Handle, PChar(mText), Length(mText), mRect,
    DT_LEFT or DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  AView.Canvas.Font.Style := [];
  AView.Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasBoardView.Paint;
var
  mIndex: Integer;
  mPlace: TAtlasBoardPlace;
  mRect: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  for mIndex := 0 to High(FLayout.Columns) do
  begin
    PaintColumn(mIndex);
  end;
  if Length(FLayout.Lanes) > 0 then
  begin
    PaintCorner(Self);
  end;
  for mIndex := 0 to High(FLayout.Lanes) do
  begin
    PaintLane(mIndex);
  end;
  for mPlace in FLayout.Places do
  begin
    PaintCard(mPlace, mPlace.Bounds, FDragging and (mPlace.Card = FPressCard));
  end;
  // Gezogene Karte unter der Maus.
  if FDragging and FLayout.PlaceOf(FPressCard, mPlace) then
  begin
    mRect := mPlace.Bounds;
    mRect.Offset(FDragPoint.X - FPressPoint.X, FDragPoint.Y - FPressPoint.Y);
    PaintCard(mPlace, mRect, False);
  end;
end;

procedure TAtlasBoardView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mCard: Integer;
begin
  inherited;
  if CanFocus then
  begin
    SetFocus;
  end;
  mCard := FLayout.CardAt(Point(X, Y));
  if Button = mbRight then
  begin
    if (mCard >= 0) and Assigned(FEvents.Context) then
    begin
      FEvents.Context(mCard, ClientToScreen(Point(X, Y)));
    end;
    Exit;
  end;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  FPressCard := mCard;
  FPressPoint := Point(X, Y);
  FDragging := False;
  // Schmal: Klick auf die Kopfzeile klappt die Gruppe; breit: Klick auf den Namen die Swimlane.
  if (mCard < 0) and FLayout.Narrow and (FLayout.HeaderAt(Point(X, Y)) > -2) then
  begin
    ToggleColumn(FLayout.HeaderAt(Point(X, Y)));
    Relayout(Width);
  end
  else if (mCard < 0) and (FLayout.LaneAt(Point(X, Y)) >= 0) then
  begin
    ToggleLane(TAtlasBoardLayout.LaneKey(FLayout.Lanes[FLayout.LaneAt(Point(X, Y))]));
    Relayout(Width);
  end;
end;

procedure TAtlasBoardView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mDistance: Integer;
begin
  inherited;
  if (FPressCard < 0) or not (ssLeft in Shift) then
  begin
    Exit;
  end;
  mDistance := MulDiv(cDragDistance, CurrentPPI, 96);
  if not FDragging and FCanDrag and ((Abs(X - FPressPoint.X) > mDistance) or (Abs(Y - FPressPoint.Y) > mDistance))
  then
  begin
    FDragging := True;
    MouseCapture := True;
  end;
  if FDragging then
  begin
    FDragPoint := Point(X, Y);
    FDropColumn := FLayout.ColumnAt(FDragPoint);
    // Spalten, die der Workflow des Trackers sicher nicht zulässt, nehmen nichts an (Grund beim Loslassen).
    if TAtlasBoardTransitions.Allowed(FSnapshot, FPressCard, FDropColumn) then
    begin
      Cursor := crDrag;
    end
    else
    begin
      Cursor := crNoDrop;
    end;
    Invalidate;
  end;
end;

procedure TAtlasBoardView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mCard, mColumn: Integer;
  mDragging: Boolean;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mCard := FPressCard;
  mDragging := FDragging;
  mColumn := FLayout.ColumnAt(Point(X, Y));
  CancelDrag;
  if mCard < 0 then
  begin
    Exit;
  end;
  if mDragging then
  begin
    if TAtlasTrackerBoard.CanMove(FSnapshot, mCard, mColumn) and Assigned(FEvents.Move) then
    begin
      FEvents.Move(mCard, mColumn);
    end;
  end
  else if (FLayout.CardAt(Point(X, Y)) = mCard) and Assigned(FEvents.Open) then
  begin
    FEvents.Open(mCard);
  end;
end;

procedure TAtlasBoardView.DblClick;
var
  mCard: Integer;
begin
  inherited;
  mCard := FLayout.CardAt(ScreenToClient(Mouse.CursorPos));
  if (mCard >= 0) and Assigned(FEvents.Start) then
  begin
    FEvents.Start(mCard);
  end;
end;

procedure TAtlasBoardView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if (Key = VK_ESCAPE) and FDragging then
  begin
    Key := 0;
    CancelDrag;
  end;
end;

function TAtlasBoardView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result or not (Parent is TScrollBox) then
  begin
    Exit;
  end;
  // Das Rad blättert die umgebende Fläche, mit Umschalt waagerecht.
  if ssShift in Shift then
  begin
    TScrollBox(Parent).HorzScrollBar.Position := TScrollBox(Parent).HorzScrollBar.Position - WheelDelta div 2;
  end
  else
  begin
    TScrollBox(Parent).VertScrollBar.Position := TScrollBox(Parent).VertScrollBar.Position - WheelDelta div 2;
  end;
  Result := True;
end;

procedure TAtlasBoardView.CancelDrag;
begin
  if FDragging then
  begin
    MouseCapture := False;
  end;
  FDragging := False;
  FPressCard := -1;
  FDropColumn := -2;
  Cursor := crDefault;
  Invalidate;
end;

procedure TAtlasBoardView.CMMouseLeave(var AMessage: TMessage);
begin
  inherited;
  if not FDragging then
  begin
    FPressCard := -1;
  end;
end;

{ TAtlasBoardFrame }

type
  /// <summary>Einträge des Kontextmenüs einer Karte (Tag).</summary>
  {$SCOPEDENUMS ON}
  TBoardMenu = (Start, Review, Preview, Browse, Copy, Assign);
  {$SCOPEDENUMS OFF}

function AddCombo(AFrame: TAtlasBoardFrame; AWidth: Integer; const AHint: string): TComboBox;
begin
  Result := TComboBox.Create(AFrame);
  Result.Parent := AFrame.FParts.Head;
  Result.Style := csDropDownList;
  Result.Width := AFrame.ScaleValue(AWidth);
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.AlignWithMargins := True;
  Result.OnChange := AFrame.ChoiceChange;
end;

function AddToggle(AFrame: TAtlasBoardFrame; AWidth: Integer; const ACaption: string): TSpeedButton;
begin
  Result := TSpeedButton.Create(AFrame);
  Result.Parent := AFrame.FParts.Head;
  Result.Caption := ACaption;
  Result.GroupIndex := 1;
  Result.Flat := True;
  Result.Width := AFrame.ScaleValue(AWidth);
  Result.Height := AFrame.ScaleValue(23);
  Result.AlignWithMargins := True;
  Result.OnClick := AFrame.ButtonClick;
end;

/// <summary>Kopfleiste: Board, Sprint, „Nur meine“/„Alle“, Suche, Aktualisieren.</summary>
procedure AddHead(AFrame: TAtlasBoardFrame);
const
  // Breiten der Auswahlen und Schalter in der Kopfleiste.
  cBoardsWidth = 150;
  cSprintsWidth = 130;
  cMineWidth = 80;
  cAllWidth = 50;
begin
  AFrame.FParts.Head := TFlowPanel.Create(AFrame);
  AFrame.FParts.Head.Parent := AFrame;
  AFrame.FParts.Head.Align := alTop;
  AFrame.FParts.Head.AutoSize := True;
  AFrame.FParts.Head.BevelOuter := bvNone;
  AFrame.FParts.Head.AlignWithMargins := True;
  AFrame.FParts.Head.Margins.SetBounds(4, 4, 4, 0);
  AFrame.FParts.Boards := AddCombo(AFrame, cBoardsWidth, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardBoardHint));
  AFrame.FParts.Sprints := AddCombo(AFrame, cSprintsWidth, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardSprintHint));
  AFrame.FParts.Mine := AddToggle(AFrame, cMineWidth, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardOnlyMine));
  AFrame.FParts.Mine.Down := True;
  AFrame.FParts.All := AddToggle(AFrame, cAllWidth, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardAll));
  AFrame.FParts.Search := TEdit.Create(AFrame);
  AFrame.FParts.Search.Parent := AFrame.FParts.Head;
  AFrame.FParts.Search.Width := AFrame.ScaleValue(150);
  AFrame.FParts.Search.TextHint := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardSearchHint);
  AFrame.FParts.Search.AlignWithMargins := True;
  AFrame.FParts.Search.OnChange := AFrame.ChoiceChange;
  AFrame.FParts.Refresh := TButton.Create(AFrame);
  AFrame.FParts.Refresh.Parent := AFrame.FParts.Head;
  AFrame.FParts.Refresh.Caption := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardRefresh);
  AFrame.FParts.Refresh.Width := AFrame.ScaleValue(90);
  AFrame.FParts.Refresh.AlignWithMargins := True;
  AFrame.FParts.Refresh.OnClick := AFrame.ButtonClick;
end;

/// <summary>Ereignisse der Zeichenfläche an die des Frames weiterreichen.</summary>
function ViewEvents(AFrame: TAtlasBoardFrame): TAtlasBoardViewEvents;
begin
  Result := Default(TAtlasBoardViewEvents);
  Result.ColumnName :=
    function(AColumn: Integer): string
    begin
      Result := AFrame.ColumnCaption(AColumn);
    end;
  Result.Open :=
    procedure(ACard: Integer)
    begin
      if Assigned(AFrame.FEvents.Open) then
      begin
        AFrame.FEvents.Open(ACard);
      end;
    end;
  Result.Start :=
    procedure(ACard: Integer)
    begin
      if Assigned(AFrame.FEvents.Start) then
      begin
        AFrame.FEvents.Start(ACard);
      end;
    end;
  Result.Move :=
    procedure(ACard, AColumn: Integer)
    begin
      if Assigned(AFrame.FEvents.Move) then
      begin
        AFrame.FEvents.Move(ACard, AColumn);
      end;
    end;
  Result.Context :=
    procedure(ACard: Integer; APoint: TPoint)
    begin
      AFrame.FMenuCard := ACard;
      AFrame.FParts.Menu.Popup(APoint.X, APoint.Y);
    end;
end;

/// <summary>Statuszeile, Fläche mit Zeichenfläche und Hinweis.</summary>
procedure AddBody(AFrame: TAtlasBoardFrame);
begin
  AFrame.FParts.Status := TAtlasWrapLabel.Create(AFrame);
  AFrame.FParts.Status.Parent := AFrame;
  AFrame.FParts.Status.Align := alTop;
  AFrame.FParts.Status.AlignWithMargins := True;
  AFrame.FParts.Status.Margins.SetBounds(8, 2, 8, 2);
  AFrame.FParts.Status.WordWrap := True;
  AFrame.FParts.Status.Visible := False;
  AFrame.FParts.Status.Top := AFrame.FParts.Head.Top + AFrame.FParts.Head.Height + 1;
  AFrame.FParts.Scroll := TScrollBox.Create(AFrame);
  AFrame.FParts.Scroll.Parent := AFrame;
  AFrame.FParts.Scroll.Align := alClient;
  AFrame.FParts.Scroll.BorderStyle := bsNone;
  AFrame.FParts.Scroll.HorzScrollBar.Tracking := True;
  AFrame.FParts.Scroll.VertScrollBar.Tracking := True;
  AFrame.FParts.Scroll.OnResize := AFrame.ScrollResize;
  AFrame.FParts.View := TAtlasBoardView.Create(AFrame);
  AFrame.FParts.View.Parent := AFrame.FParts.Scroll;
  AFrame.FParts.View.Events := ViewEvents(AFrame);
  AFrame.FParts.Empty := TLabel.Create(AFrame);
  AFrame.FParts.Empty.Parent := AFrame.FParts.Scroll;
  AFrame.FParts.Empty.AutoSize := False;
  AFrame.FParts.Empty.Alignment := taCenter;
  AFrame.FParts.Empty.WordWrap := True;
  AFrame.FParts.Empty.SetBounds(0, AFrame.ScaleValue(40), AFrame.ScaleValue(300), AFrame.ScaleValue(60));
  AFrame.FParts.Empty.Visible := False;
end;

function AddMenu(AFrame: TAtlasBoardFrame; const ACaption: string; ACommand: TBoardMenu): TMenuItem;
begin
  Result := TMenuItem.Create(AFrame.FParts.Menu);
  Result.Caption := ACaption;
  Result.Tag := Ord(ACommand);
  Result.OnClick := AFrame.MenuClick;
  AFrame.FParts.Menu.Items.Add(Result);
end;

constructor TAtlasBoardFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FOnlyMine := True;
  AddHead(Self);
  AddBody(Self);
  FParts.Menu := TPopupMenu.Create(Self);
  AddMenu(Self, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuStart), TBoardMenu.Start).Default := True;
  AddMenu(Self, TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerReviewCommand), TBoardMenu.Review);
  AddMenu(Self, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuPreview), TBoardMenu.Preview);
  AddMenu(Self, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuBrowse), TBoardMenu.Browse);
  AddMenu(Self, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuCopy), TBoardMenu.Copy);
  AddMenu(Self, TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuAssign), TBoardMenu.Assign);
end;

destructor TAtlasBoardFrame.Destroy;
begin
  if Assigned(FEvents.Hidden) then
  begin
    FEvents.Hidden();
  end;
  FEvents := Default(TAtlasBoardFrameEvents);
  inherited;
end;

procedure TAtlasBoardFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  // Das X versteckt die Form samt Frame: wie Schließen.
  if not Showing and Assigned(FEvents.Hidden) then
  begin
    FEvents.Hidden();
  end;
end;

procedure TAtlasBoardFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FParts.View.Colors := AColors;
  FParts.Scroll.Color := ToColor(AColors.Surface);
  FParts.Scroll.ParentBackground := False;
  FParts.Empty.Font.Color := ToColor(AColors.Muted);
  FParts.Status.Font.Color := ToColor(AColors.Muted);
  FParts.View.Invalidate;
end;

function TAtlasBoardFrame.ColumnCaption(AColumn: Integer): string;
begin
  if (AColumn < 0) or (AColumn > High(FSnapshot.Columns)) then
  begin
    Exit(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardNoColumn));
  end;
  Result := FSnapshot.Columns[AColumn].Name;
  // GitHub ohne Projekt: Zustände des Issues in der Sprache der Oberfläche.
  if FSnapshot.Kind = TAtlasBoardKind.Repository then
  begin
    if FSnapshot.Columns[AColumn].Resolved then
    begin
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardColumnClosed);
    end
    else
    begin
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardColumnOpen);
    end;
  end;
end;

function TAtlasBoardFrame.VisibleCards: TArray<Integer>;
begin
  Result := TAtlasTrackerBoard.Visible(FSnapshot, FOnlyMine, FParts.Search.Text);
end;

function TAtlasBoardFrame.Card(AIndex: Integer): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  if (AIndex >= 0) and (AIndex <= High(FSnapshot.Cards)) then
  begin
    Result := FSnapshot.Cards[AIndex];
  end;
end;

/// <summary>Innenbreite der Scrollbox; ohne Fenster ihre Breite (ClientWidth bräuchte ein Handle).</summary>
function ScrollWidth(AScroll: TScrollBox): Integer;
begin
  if AScroll.HandleAllocated then
  begin
    Result := AScroll.ClientWidth;
  end
  else
  begin
    Result := AScroll.Width;
  end;
end;

procedure TAtlasBoardFrame.UpdateView;
var
  mVisible: TArray<Integer>;
begin
  mVisible := VisibleCards;
  FParts.View.SetData(FSnapshot, mVisible);
  FParts.View.Visible := FHasSnapshot;
  FParts.View.Relayout(ScrollWidth(FParts.Scroll));
  if FHasSnapshot and (Length(mVisible) = 0) then
  begin
    if FOnlyMine and (Length(FSnapshot.Cards) > 0) then
    begin
      FParts.Empty.Caption := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardEmptyMine);
    end
    else
    begin
      FParts.Empty.Caption := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardEmpty);
    end;
    FParts.Empty.Visible := True;
    FParts.Empty.Top := FParts.View.Height + ScaleValue(8);
  end
  else if FHasSnapshot then
  begin
    FParts.Empty.Visible := False;
  end;
  FParts.Empty.Width := Max(ScrollWidth(FParts.Scroll), ScaleValue(100));
end;

/// <summary>Namen ANames in ABox; gewählt ist der Eintrag, dessen ID in AIds ASelected ist.</summary>
procedure FillBox(ABox: TComboBox; const ANames, AIds: TArray<string>; const ASelected: string);
var
  mIndex: Integer;
begin
  ABox.Items.BeginUpdate;
  try
    ABox.Items.Clear;
    for mIndex := 0 to High(ANames) do
    begin
      ABox.Items.Add(ANames[mIndex]);
      if SameText(AIds[mIndex], ASelected) then
      begin
        ABox.ItemIndex := mIndex;
      end;
    end;
  finally
    ABox.Items.EndUpdate;
  end;
end;

/// <summary>Namen und IDs der Boards ABoards.</summary>
procedure BoardLists(const ABoards: TArray<TAtlasBoardRef>; out ANames, AIds: TArray<string>);
var
  mBoard: TAtlasBoardRef;
begin
  ANames := nil;
  AIds := nil;
  for mBoard in ABoards do
  begin
    ANames := ANames + [mBoard.Name];
    AIds := AIds + [mBoard.Id];
  end;
end;

/// <summary>Namen und IDs der Sprints ASprints.</summary>
procedure SprintLists(const ASprints: TArray<TAtlasBoardSprint>; out ANames, AIds: TArray<string>);
var
  mSprint: TAtlasBoardSprint;
begin
  ANames := nil;
  AIds := nil;
  for mSprint in ASprints do
  begin
    ANames := ANames + [mSprint.Name];
    AIds := AIds + [mSprint.Id];
  end;
end;

/// <summary>Klapplisten Board und Sprint aus dem Stand.</summary>
procedure FillChoices(AFrame: TAtlasBoardFrame);
var
  mSprints: TComboBox;
  mNames: TArray<string>;
begin
  // Klapplisten brauchen ein Fenster; ohne Form bleibt die Auswahl leer (Tests).
  if GetParentForm(AFrame) = nil then
  begin
    Exit;
  end;
  AFrame.FFilling := True;
  try
    BoardLists(AFrame.FSnapshot.Boards, mNames, AFrame.FBoardIds);
    FillBox(AFrame.FParts.Boards, mNames, AFrame.FBoardIds, AFrame.FSnapshot.Board.Id);
    // Eine Auswahl nur, wenn es mehrere Boards gibt.
    AFrame.FParts.Boards.Visible := Length(AFrame.FSnapshot.Boards) > 1;
    mSprints := AFrame.FParts.Sprints;
    SprintLists(AFrame.FSnapshot.Sprints, mNames, AFrame.FSprintIds);
    FillBox(mSprints, mNames, AFrame.FSprintIds, AFrame.FSnapshot.Sprint.Id);
    if (mSprints.ItemIndex < 0) and (AFrame.FSnapshot.Sprint.Name <> '') then
    begin
      mSprints.Items.Add(AFrame.FSnapshot.Sprint.Name);
      AFrame.FSprintIds := AFrame.FSprintIds + [AFrame.FSnapshot.Sprint.Id];
      mSprints.ItemIndex := mSprints.Items.Count - 1;
    end;
    mSprints.Visible := mSprints.Items.Count > 0;
  finally
    AFrame.FFilling := False;
  end;
end;

procedure TAtlasBoardFrame.SetSnapshot(const ASnapshot: TAtlasBoardSnapshot; const AStatus: string);
begin
  FSnapshot := ASnapshot;
  FHasSnapshot := True;
  FParts.Empty.Visible := False;
  FillChoices(Self);
  SetStatus(AStatus);
  UpdateView;
end;

procedure TAtlasBoardFrame.ShowNotice(const AText: string);
begin
  FHasSnapshot := False;
  FSnapshot := TAtlasBoardSnapshot.Empty;
  FParts.View.SetData(FSnapshot, nil);
  FParts.View.Visible := False;
  FParts.Empty.Caption := AText;
  FParts.Empty.Top := ScaleValue(40);
  FParts.Empty.Width := Max(ScrollWidth(FParts.Scroll), ScaleValue(100));
  FParts.Empty.Visible := AText <> '';
end;

procedure TAtlasBoardFrame.SetStatus(const AText: string);
begin
  FParts.Status.Caption := AText;
  FParts.Status.Visible := AText <> '';
end;

function TAtlasBoardFrame.StatusText: string;
begin
  Result := '';
  if FParts.Status.Visible then
  begin
    Result := FParts.Status.Caption;
  end;
end;

procedure TAtlasBoardFrame.SetLoading(AValue: Boolean);
begin
  FParts.Refresh.Enabled := not AValue;
  if AValue then
  begin
    SetStatus(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardLoading));
  end;
end;

function TAtlasBoardFrame.MoveCard(ACard, AColumn: Integer): string;
begin
  Result := '';
  if (ACard < 0) or (ACard > High(FSnapshot.Cards)) or (AColumn < 0) or (AColumn > High(FSnapshot.Columns)) then
  begin
    Exit;
  end;
  Result := FSnapshot.Cards[ACard].State;
  if Length(FSnapshot.Columns[AColumn].Values) > 0 then
  begin
    FSnapshot.Cards[ACard].State := FSnapshot.Columns[AColumn].Values[0];
  end;
  UpdateView;
end;

procedure TAtlasBoardFrame.RevertMove(const AKey, AState: string);
var
  mCard: Integer;
begin
  mCard := FSnapshot.CardIndex(AKey);
  if mCard < 0 then
  begin
    Exit;
  end;
  FSnapshot.Cards[mCard].State := AState;
  UpdateView;
end;

procedure TAtlasBoardFrame.SetActiveKey(const AKey: string);
begin
  FParts.View.ActiveKey := AKey;
  FParts.View.Invalidate;
end;

procedure TAtlasBoardFrame.SetCanDrag(AValue: Boolean);
begin
  FParts.View.CanDrag := AValue;
end;

procedure TAtlasBoardFrame.SetOnlyMine(AValue: Boolean);
begin
  FOnlyMine := AValue;
  FParts.Mine.Down := AValue;
  FParts.All.Down := not AValue;
  if FHasSnapshot then
  begin
    UpdateView;
  end;
end;

/// <summary>Gewählte ID aus ABox; False beim Füllen oder ohne Auswahl.</summary>
function ChosenId(AFrame: TAtlasBoardFrame; ABox: TComboBox; const AIds: TArray<string>; out AId: string): Boolean;
begin
  AId := '';
  Result := not AFrame.FFilling and (ABox.ItemIndex >= 0) and (ABox.ItemIndex <= High(AIds));
  if Result then
  begin
    AId := AIds[ABox.ItemIndex];
  end;
end;

procedure TAtlasBoardFrame.ChoiceChange(Sender: TObject);
var
  mId: string;
begin
  if Sender = FParts.Search then
  begin
    if FHasSnapshot then
    begin
      UpdateView;
    end;
  end
  else if (Sender = FParts.Boards) and ChosenId(Self, FParts.Boards, FBoardIds, mId) and
    Assigned(FEvents.Board) then
  begin
    FEvents.Board(mId);
  end
  else if (Sender = FParts.Sprints) and ChosenId(Self, FParts.Sprints, FSprintIds, mId) and
    Assigned(FEvents.Sprint) then
  begin
    FEvents.Sprint(mId);
  end;
end;

procedure TAtlasBoardFrame.ButtonClick(Sender: TObject);
begin
  if Sender = FParts.Refresh then
  begin
    if Assigned(FEvents.Refresh) then
    begin
      FEvents.Refresh();
    end;
  end
  else if FParts.Mine.Down <> FOnlyMine then
  begin
    SetOnlyMine(FParts.Mine.Down);
    if Assigned(FEvents.OnlyMine) then
    begin
      FEvents.OnlyMine(FOnlyMine);
    end;
  end;
end;

procedure TAtlasBoardFrame.ScrollResize(Sender: TObject);
begin
  if FHasSnapshot then
  begin
    FParts.View.Relayout(ScrollWidth(FParts.Scroll));
  end;
  FParts.Empty.Width := Max(ScrollWidth(FParts.Scroll), ScaleValue(100));
end;

procedure FireCard(const AEvent: TAtlasBoardCardEvent; ACard: Integer);
begin
  if Assigned(AEvent) then
  begin
    AEvent(ACard);
  end;
end;

procedure TAtlasBoardFrame.MenuClick(Sender: TObject);
begin
  case TBoardMenu(TMenuItem(Sender).Tag) of
    TBoardMenu.Start:
      FireCard(FEvents.Start, FMenuCard);
    TBoardMenu.Review:
      FireCard(FEvents.Review, FMenuCard);
    TBoardMenu.Preview:
      FireCard(FEvents.Open, FMenuCard);
    TBoardMenu.Browse:
      FireCard(FEvents.Browse, FMenuCard);
    TBoardMenu.Copy:
      begin
        if (FMenuCard >= 0) and (FMenuCard <= High(FSnapshot.Cards)) then
        begin
          Clipboard.AsText := FSnapshot.Cards[FMenuCard].Key;
        end;
      end;
    TBoardMenu.Assign:
      FireCard(FEvents.Assign, FMenuCard);
  end;
end;

end.
