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
// auf die Kopfzeile). Ziehen einer Karte in eine andere Spalte meldet
// OnMove; die IDE-Schicht fragt nach, schreibt und ruft danach MoveCard
// (sofort sichtbar) bzw. RevertMove (springt zurück). Klick meldet OnOpen,
// Doppelklick OnStart, Rechtsklick zeigt das Kontextmenü (Beginnen,
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
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Board;

type
  /// <summary>Maße in Pixeln (schon skaliert).</summary>
  TAtlasBoardMetrics = record
    ColumnWidth: Integer;
    Gap: Integer;
    Header: Integer;
    CardHeight: Integer;
    /// <summary>Schmaler als das: Spalten untereinander.</summary>
    NarrowWidth: Integer;
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
    Width: Integer;
    Height: Integer;
    /// <summary>AVisible: Karten nach Filter; ACollapsed: eingeklappte Spalten (Nummer im Board, -1 für „ohne
    /// Spalte“), nur schmal wirksam.</summary>
    class function Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>; AWidth: Integer;
      const ACollapsed: TArray<Integer>; const AMetrics: TAtlasBoardMetrics): TAtlasBoardLayout; static;
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

  /// <summary>Zeichenfläche des Boards: Spalten, Karten, Ziehen.</summary>
  TAtlasBoardView = class(TCustomControl)
  public const
    /// <summary>So weit (Pixel bei 96 dpi) muss die Maus wandern, bis aus einem Klick ein Ziehen wird.</summary>
    DragDistance = 5;
  private
    FSnapshot: TAtlasBoardSnapshot;
    FVisible: TArray<Integer>;
    FLayout: TAtlasBoardLayout;
    FColors: TAtlasColors;
    FCollapsed: TArray<Integer>;
    FActiveKey: string;
    FCanDrag: Boolean;
    FPressCard: Integer;
    FPressPoint: TPoint;
    FDragging: Boolean;
    FDragPoint: TPoint;
    FDropColumn: Integer;
    FOnOpen: TAtlasBoardCardEvent;
    FOnStart: TAtlasBoardCardEvent;
    FOnMove: TAtlasBoardMoveEvent;
    FOnContext: TProc<Integer, TPoint>;
    FColumnName: TFunc<Integer, string>;
    function Metrics: TAtlasBoardMetrics;
    procedure PaintCard(const APlace: TAtlasBoardPlace; const ABounds: TRect; AGhost: Boolean);
    function PriorityColor(const ACard: TAtlasBoardCard): TColor;
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
    property Snapshot: TAtlasBoardSnapshot read FSnapshot;
    property Layout: TAtlasBoardLayout read FLayout;
    property Colors: TAtlasColors read FColors write FColors;
    property ActiveKey: string read FActiveKey write FActiveKey;
    property CanDrag: Boolean read FCanDrag write FCanDrag;
    property OnOpen: TAtlasBoardCardEvent read FOnOpen write FOnOpen;
    property OnStart: TAtlasBoardCardEvent read FOnStart write FOnStart;
    property OnMove: TAtlasBoardMoveEvent read FOnMove write FOnMove;
    /// <summary>Rechtsklick auf eine Karte; Punkt in Bildschirmkoordinaten.</summary>
    property OnContext: TProc<Integer, TPoint> read FOnContext write FOnContext;
    /// <summary>Beschriftung einer Spalte (Board-Nummer, -1 = ohne Spalte).</summary>
    property ColumnName: TFunc<Integer, string> read FColumnName write FColumnName;
  end;

  TAtlasBoardFrame = class(TFrame)
  private
    FHead: TFlowPanel;
    FBoards: TComboBox;
    FSprints: TComboBox;
    FMine: TSpeedButton;
    FAll: TSpeedButton;
    FSearch: TEdit;
    FRefreshButton: TButton;
    FStatus: TLabel;
    FScroll: TScrollBox;
    FView: TAtlasBoardView;
    FEmpty: TLabel;
    FMenu: TPopupMenu;
    FMenuCard: Integer;
    FColors: TAtlasColors;
    FSnapshot: TAtlasBoardSnapshot;
    FHasSnapshot: Boolean;
    FFilling: Boolean;
    FOnlyMine: Boolean;
    FBoardIds: TArray<string>;
    FSprintIds: TArray<string>;
    FOnOpen: TAtlasBoardCardEvent;
    FOnStart: TAtlasBoardCardEvent;
    FOnBrowse: TAtlasBoardCardEvent;
    FOnAssign: TAtlasBoardCardEvent;
    FOnMove: TAtlasBoardMoveEvent;
    FOnRefresh: TProc;
    FOnBoard: TProc<string>;
    FOnSprint: TProc<string>;
    FOnOnlyMine: TProc<Boolean>;
    FOnHidden: TProc;
    function AddMenu(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
    procedure UpdateView;
    /// <summary>Innenbreite der Scrollbox; ohne Fenster ihre Breite (ClientWidth bräuchte ein Handle).</summary>
    function ScrollWidth: Integer;
    procedure FillChoices;
    procedure BoardChange(Sender: TObject);
    procedure SprintChange(Sender: TObject);
    procedure MineClick(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure ScrollResize(Sender: TObject);
    procedure MenuStart(Sender: TObject);
    procedure MenuPreview(Sender: TObject);
    procedure MenuBrowse(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuAssign(Sender: TObject);
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
    /// <summary>Umschalter „Nur meine“/„Alle“ ohne OnOnlyMine.</summary>
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
    property View: TAtlasBoardView read FView;
    property BoardBox: TComboBox read FBoards;
    property SprintBox: TComboBox read FSprints;
    property SearchEdit: TEdit read FSearch;
    property MineButton: TSpeedButton read FMine;
    property AllButton: TSpeedButton read FAll;
    property EmptyLabel: TLabel read FEmpty;
    property OnOpen: TAtlasBoardCardEvent read FOnOpen write FOnOpen;
    property OnStart: TAtlasBoardCardEvent read FOnStart write FOnStart;
    property OnBrowse: TAtlasBoardCardEvent read FOnBrowse write FOnBrowse;
    property OnAssign: TAtlasBoardCardEvent read FOnAssign write FOnAssign;
    property OnMove: TAtlasBoardMoveEvent read FOnMove write FOnMove;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    /// <summary>Anderes Board gewählt (ID).</summary>
    property OnBoard: TProc<string> read FOnBoard write FOnBoard;
    /// <summary>Anderer Sprint gewählt (ID).</summary>
    property OnSprint: TProc<string> read FOnSprint write FOnSprint;
    property OnOnlyMine: TProc<Boolean> read FOnOnlyMine write FOnOnlyMine;
    /// <summary>Fenster geschlossen bzw. versteckt.</summary>
    property OnHidden: TProc read FOnHidden write FOnHidden;
  end;

/// <summary>"#rrggbb" als Farbe; False bei anderem Text.</summary>
function TryWebColor(const AText: string; out AColor: TColor): Boolean;

implementation

uses
  System.Math,
  Winapi.Windows,
  Vcl.Clipbrd,
  Atlas.UI.Strings;

{$R *.dfm}

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
    // #rrggbb → TColor $bbggrr.
    AColor := TColor(((mValue and $FF) shl 16) or (mValue and $FF00) or ((mValue shr 16) and $FF));
end;

{ TAtlasBoardMetrics }

class function TAtlasBoardMetrics.Create(ALineHeight: Integer): TAtlasBoardMetrics;
begin
  Result.ColumnWidth := 180;
  Result.Gap := 8;
  Result.Header := ALineHeight + 10;
  // Kopfzeile der Karte, zwei Zeilen Titel, Ränder.
  Result.CardHeight := 3 * ALineHeight + 16;
  Result.NarrowWidth := TAtlasTrackerBoard.NarrowWidth;
end;

function TAtlasBoardMetrics.Scaled(AMultiplier, ADivider: Integer): TAtlasBoardMetrics;
begin
  Result := Self;
  if (ADivider <= 0) or (AMultiplier = ADivider) then
    Exit;
  Result.ColumnWidth := MulDiv(ColumnWidth, AMultiplier, ADivider);
  Result.Gap := MulDiv(Gap, AMultiplier, ADivider);
  Result.NarrowWidth := MulDiv(NarrowWidth, AMultiplier, ADivider);
end;

{ TAtlasBoardLayout }

function Contains(const AItems: TArray<Integer>; AValue: Integer): Boolean;
var
  mItem: Integer;
begin
  Result := False;
  for mItem in AItems do
    if mItem = AValue then
      Exit(True);
end;

class function TAtlasBoardLayout.Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>;
  AWidth: Integer; const ACollapsed: TArray<Integer>; const AMetrics: TAtlasBoardMetrics): TAtlasBoardLayout;
var
  mIndex, mCount, mColumnWidth, mLeft, mTop, mBottom: Integer;
  mCards: TArray<Integer>;
  mCard: Integer;
  mPlace: TAtlasBoardPlace;
begin
  Result := Default(TAtlasBoardLayout);
  for mIndex := 0 to High(ASnapshot.Columns) do
    Result.Columns := Result.Columns + [mIndex];
  if Length(TAtlasTrackerBoard.ColumnCards(ASnapshot, AVisible, -1)) > 0 then
    Result.Columns := Result.Columns + [-1];
  mCount := Length(Result.Columns);
  SetLength(Result.Headers, mCount);
  SetLength(Result.Areas, mCount);
  SetLength(Result.Counts, mCount);
  Result.Narrow := AWidth < AMetrics.NarrowWidth;
  if mCount = 0 then
    Exit;
  if Result.Narrow then
    mColumnWidth := Max(AWidth - 2 * AMetrics.Gap, 1)
  else
    mColumnWidth := Max(AMetrics.ColumnWidth, (AWidth - (mCount + 1) * AMetrics.Gap) div mCount);
  mLeft := AMetrics.Gap;
  mTop := AMetrics.Gap;
  for mIndex := 0 to mCount - 1 do
  begin
    mCards := TAtlasTrackerBoard.ColumnCards(ASnapshot, AVisible, Result.Columns[mIndex]);
    Result.Counts[mIndex] := Length(mCards);
    if not Result.Narrow then
      mTop := AMetrics.Gap;
    Result.Headers[mIndex] := Rect(mLeft, mTop, mLeft + mColumnWidth, mTop + AMetrics.Header);
    mBottom := mTop + AMetrics.Header;
    if not (Result.Narrow and Contains(ACollapsed, Result.Columns[mIndex])) then
      for mCard in mCards do
      begin
        mPlace.Card := mCard;
        mPlace.Column := Result.Columns[mIndex];
        mPlace.Bounds := Rect(mLeft + 4, mBottom + AMetrics.Gap div 2, mLeft + mColumnWidth - 4,
          mBottom + AMetrics.Gap div 2 + AMetrics.CardHeight);
        Result.Places := Result.Places + [mPlace];
        mBottom := mPlace.Bounds.Bottom;
      end;
    // Leere Spalte: Platz zum Ablegen.
    mBottom := Max(mBottom + AMetrics.Gap div 2, mTop + AMetrics.Header + AMetrics.CardHeight div 2);
    Result.Areas[mIndex] := Rect(mLeft, mTop, mLeft + mColumnWidth, mBottom);
    Result.Height := Max(Result.Height, mBottom + AMetrics.Gap);
    if Result.Narrow then
      mTop := mBottom + AMetrics.Gap
    else
      mLeft := mLeft + mColumnWidth + AMetrics.Gap;
  end;
  if Result.Narrow then
    Result.Width := AWidth
  else
    Result.Width := Max(AWidth, mLeft);
end;

function TAtlasBoardLayout.CardAt(const APoint: TPoint): Integer;
var
  mPlace: TAtlasBoardPlace;
begin
  for mPlace in Places do
    if mPlace.Bounds.Contains(APoint) then
      Exit(mPlace.Card);
  Result := -1;
end;

function TAtlasBoardLayout.ColumnAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Areas) do
    if Areas[mIndex].Contains(APoint) then
      Exit(Columns[mIndex]);
  Result := -2;
end;

function TAtlasBoardLayout.HeaderAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Headers) do
    if Headers[mIndex].Contains(APoint) then
      Exit(Columns[mIndex]);
  Result := -2;
end;

function TAtlasBoardLayout.PlaceOf(ACard: Integer; out APlace: TAtlasBoardPlace): Boolean;
var
  mPlace: TAtlasBoardPlace;
begin
  for mPlace in Places do
    if mPlace.Card = ACard then
    begin
      APlace := mPlace;
      Exit(True);
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
    mLine := 15;
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
  FLayout := TAtlasBoardLayout.Build(FSnapshot, FVisible, AWidth, FCollapsed, Metrics);
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
    if FCollapsed[mIndex] = AColumn then
    begin
      Delete(FCollapsed, mIndex, 1);
      Exit;
    end;
  FCollapsed := FCollapsed + [AColumn];
end;

function TAtlasBoardView.PriorityColor(const ACard: TAtlasBoardCard): TColor;
begin
  if TryWebColor(ACard.PriorityColor, Result) then
    Exit;
  case TAtlasTrackerBoard.PriorityLevel(ACard.Priority) of
    4:
      Result := ToColor(FColors.Error);
    3:
      Result := ToColor(FColors.Warn);
    2:
      Result := ToColor(FColors.Accent);
    1:
      Result := ToColor(FColors.Muted);
  else
    Result := ToColor(FColors.Line);
  end;
end;

procedure TAtlasBoardView.PaintCard(const APlace: TAtlasBoardPlace; const ABounds: TRect; AGhost: Boolean);
var
  mCard: TAtlasBoardCard;
  mRect, mText: TRect;
  mLine, mRight: Integer;
  mMark: string;
begin
  mCard := FSnapshot.Cards[APlace.Card];
  mRect := ABounds;
  mLine := Canvas.TextHeight('Ag');
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  if SameText(mCard.Key, FActiveKey) then
  begin
    Canvas.Pen.Color := ToColor(FColors.Accent);
    Canvas.Pen.Width := 2;
  end
  else
  begin
    Canvas.Pen.Color := ToColor(FColors.Line);
    Canvas.Pen.Width := 1;
  end;
  if AGhost then
    Canvas.Pen.Style := psDot
  else
    Canvas.Pen.Style := psSolid;
  Canvas.Rectangle(mRect);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  // Priorität als Farbbalken links.
  Canvas.Brush.Color := PriorityColor(mCard);
  Canvas.FillRect(Rect(mRect.Left + 1, mRect.Top + 1, mRect.Left + 5, mRect.Bottom - 1));
  Canvas.Brush.Style := bsClear;
  // Kopfzeile: Kennung links; rechts Kürzel, Checkliste, Schloss.
  mRight := mRect.Right - 6;
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(FColors.Muted);
  mMark := TAtlasTrackerBoard.Initials(mCard.Assignee);
  if mMark <> '' then
  begin
    Canvas.Font.Style := [fsBold];
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.AccentSoft);
    mText := Rect(mRight - Canvas.TextWidth(mMark) - 6, mRect.Top + 4, mRight, mRect.Top + 4 + mLine);
    Canvas.FillRect(mText);
    Canvas.Font.Color := ToColor(FColors.Text);
    DrawText(Canvas.Handle, PChar(mMark), Length(mMark), mText, DT_CENTER or DT_SINGLELINE or DT_VCENTER);
    Canvas.Brush.Style := bsClear;
    mRight := mText.Left - 6;
    Canvas.Font.Style := [];
    Canvas.Font.Color := ToColor(FColors.Muted);
  end;
  if mCard.Checklist.Any then
  begin
    mMark := mCard.Checklist.Text;
    mText := Rect(mRight - Canvas.TextWidth(mMark), mRect.Top + 4, mRight, mRect.Top + 4 + mLine);
    if mCard.Checklist.Done = mCard.Checklist.Total then
      Canvas.Font.Color := ToColor(FColors.Add);
    DrawText(Canvas.Handle, PChar(mMark), Length(mMark), mText, DT_RIGHT or DT_SINGLELINE);
    Canvas.Font.Color := ToColor(FColors.Muted);
    mRight := mText.Left - 6;
  end;
  if mCard.Locked then
  begin
    mMark := '⛔';
    mText := Rect(mRight - Canvas.TextWidth(mMark), mRect.Top + 4, mRight, mRect.Top + 4 + mLine);
    DrawText(Canvas.Handle, PChar(mMark), Length(mMark), mText, DT_RIGHT or DT_SINGLELINE);
    mRight := mText.Left - 6;
  end;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Accent);
  mText := Rect(mRect.Left + 10, mRect.Top + 4, Max(mRight, mRect.Left + 10), mRect.Top + 4 + mLine);
  DrawText(Canvas.Handle, PChar(mCard.Key), Length(mCard.Key), mText, DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS);
  // Titel in zwei Zeilen.
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(FColors.Text);
  mText := Rect(mRect.Left + 10, mRect.Top + 8 + mLine, mRect.Right - 6, mRect.Top + 8 + 3 * mLine);
  DrawText(Canvas.Handle, PChar(mCard.Title), Length(mCard.Title), mText,
    DT_LEFT or DT_WORDBREAK or DT_END_ELLIPSIS or DT_EDITCONTROL or DT_NOPREFIX);
end;

procedure TAtlasBoardView.Paint;
var
  mIndex, mColumn: Integer;
  mPlace: TAtlasBoardPlace;
  mText, mName: string;
  mRect: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  for mIndex := 0 to High(FLayout.Columns) do
  begin
    mColumn := FLayout.Columns[mIndex];
    // Fläche der Spalte; Ziel beim Ziehen hervorgehoben.
    if FDragging and (mColumn = FDropColumn) and TAtlasTrackerBoard.CanMove(FSnapshot, FPressCard, mColumn) then
      Canvas.Brush.Color := ToColor(FColors.Selection)
    else
      Canvas.Brush.Color := ToColor(FColors.Gutter);
    Canvas.FillRect(FLayout.Areas[mIndex]);
    mName := '';
    if Assigned(FColumnName) then
      mName := FColumnName(mColumn);
    mText := TAtlasStrings.Fmt(TAtlasTextId.BoardColumnCount, [AnsiUpperCase(mName), FLayout.Counts[mIndex]]);
    if FLayout.Narrow then
    begin
      if Collapsed(mColumn) then
        mText := '▸ ' + mText
      else
        mText := '▾ ' + mText;
    end;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(FColors.Muted);
    mRect := FLayout.Headers[mIndex];
    InflateRect(mRect, -ScaleValue(6), 0);
    DrawText(Canvas.Handle, PChar(mText), Length(mText), mRect,
      DT_LEFT or DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
    Canvas.Font.Style := [];
    Canvas.Brush.Style := bsSolid;
  end;
  for mPlace in FLayout.Places do
    PaintCard(mPlace, mPlace.Bounds, FDragging and (mPlace.Card = FPressCard));
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
    SetFocus;
  mCard := FLayout.CardAt(Point(X, Y));
  if Button = mbRight then
  begin
    if (mCard >= 0) and Assigned(FOnContext) then
      FOnContext(mCard, ClientToScreen(Point(X, Y)));
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  FPressCard := mCard;
  FPressPoint := Point(X, Y);
  FDragging := False;
  // Schmal: Klick auf die Kopfzeile klappt die Gruppe.
  if (mCard < 0) and FLayout.Narrow and (FLayout.HeaderAt(Point(X, Y)) > -2) then
  begin
    ToggleColumn(FLayout.HeaderAt(Point(X, Y)));
    Relayout(Width);
  end;
end;

procedure TAtlasBoardView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mDistance: Integer;
begin
  inherited;
  if (FPressCard < 0) or not (ssLeft in Shift) then
    Exit;
  mDistance := MulDiv(DragDistance, CurrentPPI, 96);
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
    if TAtlasTrackerBoard.CanMove(FSnapshot, FPressCard, FDropColumn) then
      Cursor := crDrag
    else
      Cursor := crNoDrop;
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
    Exit;
  mCard := FPressCard;
  mDragging := FDragging;
  mColumn := FLayout.ColumnAt(Point(X, Y));
  CancelDrag;
  if mCard < 0 then
    Exit;
  if mDragging then
  begin
    if TAtlasTrackerBoard.CanMove(FSnapshot, mCard, mColumn) and Assigned(FOnMove) then
      FOnMove(mCard, mColumn);
  end
  else if (FLayout.CardAt(Point(X, Y)) = mCard) and Assigned(FOnOpen) then
    FOnOpen(mCard);
end;

procedure TAtlasBoardView.DblClick;
var
  mCard: Integer;
begin
  inherited;
  mCard := FLayout.CardAt(ScreenToClient(Mouse.CursorPos));
  if (mCard >= 0) and Assigned(FOnStart) then
    FOnStart(mCard);
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
    Exit;
  // Das Rad blättert die umgebende Fläche, mit Umschalt waagerecht.
  if ssShift in Shift then
    TScrollBox(Parent).HorzScrollBar.Position := TScrollBox(Parent).HorzScrollBar.Position - WheelDelta div 2
  else
    TScrollBox(Parent).VertScrollBar.Position := TScrollBox(Parent).VertScrollBar.Position - WheelDelta div 2;
  Result := True;
end;

procedure TAtlasBoardView.CancelDrag;
begin
  if FDragging then
    MouseCapture := False;
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
    FPressCard := -1;
end;

{ TAtlasBoardFrame }

constructor TAtlasBoardFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FOnlyMine := True;
  FHead := TFlowPanel.Create(Self);
  FHead.Parent := Self;
  FHead.Align := alTop;
  FHead.AutoSize := True;
  FHead.BevelOuter := bvNone;
  FHead.AlignWithMargins := True;
  FHead.Margins.SetBounds(4, 4, 4, 0);
  FBoards := TComboBox.Create(Self);
  FBoards.Parent := FHead;
  FBoards.Style := csDropDownList;
  FBoards.Width := ScaleValue(150);
  FBoards.Hint := TAtlasStrings.Text(TAtlasTextId.BoardBoardHint);
  FBoards.ShowHint := True;
  FBoards.AlignWithMargins := True;
  FBoards.OnChange := BoardChange;
  FSprints := TComboBox.Create(Self);
  FSprints.Parent := FHead;
  FSprints.Style := csDropDownList;
  FSprints.Width := ScaleValue(130);
  FSprints.Hint := TAtlasStrings.Text(TAtlasTextId.BoardSprintHint);
  FSprints.ShowHint := True;
  FSprints.AlignWithMargins := True;
  FSprints.OnChange := SprintChange;
  FMine := TSpeedButton.Create(Self);
  FMine.Parent := FHead;
  FMine.Caption := TAtlasStrings.Text(TAtlasTextId.BoardOnlyMine);
  FMine.GroupIndex := 1;
  FMine.Down := True;
  FMine.Flat := True;
  FMine.Width := ScaleValue(80);
  FMine.Height := ScaleValue(23);
  FMine.AlignWithMargins := True;
  FMine.OnClick := MineClick;
  FAll := TSpeedButton.Create(Self);
  FAll.Parent := FHead;
  FAll.Caption := TAtlasStrings.Text(TAtlasTextId.BoardAll);
  FAll.GroupIndex := 1;
  FAll.Flat := True;
  FAll.Width := ScaleValue(50);
  FAll.Height := ScaleValue(23);
  FAll.AlignWithMargins := True;
  FAll.OnClick := MineClick;
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FHead;
  FSearch.Width := ScaleValue(150);
  FSearch.TextHint := TAtlasStrings.Text(TAtlasTextId.BoardSearchHint);
  FSearch.AlignWithMargins := True;
  FSearch.OnChange := SearchChange;
  FRefreshButton := TButton.Create(Self);
  FRefreshButton.Parent := FHead;
  FRefreshButton.Caption := TAtlasStrings.Text(TAtlasTextId.BoardRefresh);
  FRefreshButton.Width := ScaleValue(90);
  FRefreshButton.AlignWithMargins := True;
  FRefreshButton.OnClick := RefreshClick;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(8, 2, 8, 2);
  FStatus.WordWrap := True;
  FStatus.Visible := False;
  FStatus.Top := FHead.Top + FHead.Height + 1;
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.HorzScrollBar.Tracking := True;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.OnResize := ScrollResize;
  FView := TAtlasBoardView.Create(Self);
  FView.Parent := FScroll;
  FView.ColumnName :=
    function(AColumn: Integer): string
    begin
      Result := ColumnCaption(AColumn);
    end;
  FView.OnOpen :=
    procedure(ACard: Integer)
    begin
      if Assigned(FOnOpen) then
        FOnOpen(ACard);
    end;
  FView.OnStart :=
    procedure(ACard: Integer)
    begin
      if Assigned(FOnStart) then
        FOnStart(ACard);
    end;
  FView.OnMove :=
    procedure(ACard, AColumn: Integer)
    begin
      if Assigned(FOnMove) then
        FOnMove(ACard, AColumn);
    end;
  FView.OnContext :=
    procedure(ACard: Integer; APoint: TPoint)
    begin
      FMenuCard := ACard;
      FMenu.Popup(APoint.X, APoint.Y);
    end;
  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := FScroll;
  FEmpty.AutoSize := False;
  FEmpty.Alignment := taCenter;
  FEmpty.WordWrap := True;
  FEmpty.SetBounds(0, ScaleValue(40), ScaleValue(300), ScaleValue(60));
  FEmpty.Visible := False;
  FMenu := TPopupMenu.Create(Self);
  AddMenu(TAtlasStrings.Text(TAtlasTextId.BoardMenuStart), MenuStart).Default := True;
  AddMenu(TAtlasStrings.Text(TAtlasTextId.BoardMenuPreview), MenuPreview);
  AddMenu(TAtlasStrings.Text(TAtlasTextId.BoardMenuBrowse), MenuBrowse);
  AddMenu(TAtlasStrings.Text(TAtlasTextId.BoardMenuCopy), MenuCopy);
  AddMenu(TAtlasStrings.Text(TAtlasTextId.BoardMenuAssign), MenuAssign);
end;

destructor TAtlasBoardFrame.Destroy;
begin
  if Assigned(FOnHidden) then
    FOnHidden();
  FOnHidden := nil;
  inherited;
end;

function TAtlasBoardFrame.AddMenu(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  FMenu.Items.Add(Result);
end;

procedure TAtlasBoardFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  // Das X versteckt die Form samt Frame: wie Schließen.
  if not Showing and Assigned(FOnHidden) then
    FOnHidden();
end;

procedure TAtlasBoardFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FView.Colors := AColors;
  FScroll.Color := ToColor(AColors.Surface);
  FScroll.ParentBackground := False;
  FEmpty.Font.Color := ToColor(AColors.Muted);
  FStatus.Font.Color := ToColor(AColors.Muted);
  FView.Invalidate;
end;

function TAtlasBoardFrame.ColumnCaption(AColumn: Integer): string;
begin
  if (AColumn < 0) or (AColumn > High(FSnapshot.Columns)) then
    Exit(TAtlasStrings.Text(TAtlasTextId.BoardNoColumn));
  Result := FSnapshot.Columns[AColumn].Name;
  // GitHub ohne Projekt: Zustände des Issues in der Sprache der Oberfläche.
  if FSnapshot.Kind = TAtlasBoardKind.Repository then
    if FSnapshot.Columns[AColumn].Resolved then
      Result := TAtlasStrings.Text(TAtlasTextId.BoardColumnClosed)
    else
      Result := TAtlasStrings.Text(TAtlasTextId.BoardColumnOpen);
end;

function TAtlasBoardFrame.VisibleCards: TArray<Integer>;
begin
  Result := TAtlasTrackerBoard.Visible(FSnapshot, FOnlyMine, FSearch.Text);
end;

function TAtlasBoardFrame.Card(AIndex: Integer): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  if (AIndex >= 0) and (AIndex <= High(FSnapshot.Cards)) then
    Result := FSnapshot.Cards[AIndex];
end;

function TAtlasBoardFrame.ScrollWidth: Integer;
begin
  if FScroll.HandleAllocated then
    Result := FScroll.ClientWidth
  else
    Result := FScroll.Width;
end;

procedure TAtlasBoardFrame.UpdateView;
var
  mVisible: TArray<Integer>;
begin
  mVisible := VisibleCards;
  FView.SetData(FSnapshot, mVisible);
  FView.Visible := FHasSnapshot;
  FView.Relayout(ScrollWidth);
  if FHasSnapshot and (Length(mVisible) = 0) then
  begin
    if FOnlyMine and (Length(FSnapshot.Cards) > 0) then
      FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.BoardEmptyMine)
    else
      FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.BoardEmpty);
    FEmpty.Visible := True;
    FEmpty.Top := FView.Height + ScaleValue(8);
  end
  else if FHasSnapshot then
    FEmpty.Visible := False;
  FEmpty.Width := Max(ScrollWidth, ScaleValue(100));
end;

procedure TAtlasBoardFrame.FillChoices;
var
  mIndex: Integer;
  mText: string;
begin
  // Klapplisten brauchen ein Fenster; ohne Form bleibt die Auswahl leer (Tests).
  if GetParentForm(Self) = nil then
    Exit;
  FFilling := True;
  try
    FBoards.Items.BeginUpdate;
    try
      FBoards.Items.Clear;
      FBoardIds := nil;
      for mIndex := 0 to High(FSnapshot.Boards) do
      begin
        FBoards.Items.Add(FSnapshot.Boards[mIndex].Name);
        FBoardIds := FBoardIds + [FSnapshot.Boards[mIndex].Id];
        if SameText(FSnapshot.Boards[mIndex].Id, FSnapshot.Board.Id) then
          FBoards.ItemIndex := mIndex;
      end;
    finally
      FBoards.Items.EndUpdate;
    end;
    // Eine Auswahl nur, wenn es mehrere Boards gibt.
    FBoards.Visible := Length(FSnapshot.Boards) > 1;
    FSprints.Items.BeginUpdate;
    try
      FSprints.Items.Clear;
      FSprintIds := nil;
      for mIndex := 0 to High(FSnapshot.Sprints) do
      begin
        mText := FSnapshot.Sprints[mIndex].Name;
        FSprints.Items.Add(mText);
        FSprintIds := FSprintIds + [FSnapshot.Sprints[mIndex].Id];
        if SameText(FSnapshot.Sprints[mIndex].Id, FSnapshot.Sprint.Id) then
          FSprints.ItemIndex := mIndex;
      end;
      if (FSprints.ItemIndex < 0) and (FSnapshot.Sprint.Name <> '') then
      begin
        FSprints.Items.Add(FSnapshot.Sprint.Name);
        FSprintIds := FSprintIds + [FSnapshot.Sprint.Id];
        FSprints.ItemIndex := FSprints.Items.Count - 1;
      end;
    finally
      FSprints.Items.EndUpdate;
    end;
    FSprints.Visible := FSprints.Items.Count > 0;
  finally
    FFilling := False;
  end;
end;

procedure TAtlasBoardFrame.SetSnapshot(const ASnapshot: TAtlasBoardSnapshot; const AStatus: string);
begin
  FSnapshot := ASnapshot;
  FHasSnapshot := True;
  FEmpty.Visible := False;
  FillChoices;
  SetStatus(AStatus);
  UpdateView;
end;

procedure TAtlasBoardFrame.ShowNotice(const AText: string);
begin
  FHasSnapshot := False;
  FSnapshot := TAtlasBoardSnapshot.Empty;
  FView.SetData(FSnapshot, nil);
  FView.Visible := False;
  FEmpty.Caption := AText;
  FEmpty.Top := ScaleValue(40);
  FEmpty.Width := Max(ScrollWidth, ScaleValue(100));
  FEmpty.Visible := AText <> '';
end;

procedure TAtlasBoardFrame.SetStatus(const AText: string);
begin
  FStatus.Caption := AText;
  FStatus.Visible := AText <> '';
end;

function TAtlasBoardFrame.StatusText: string;
begin
  Result := '';
  if FStatus.Visible then
    Result := FStatus.Caption;
end;

procedure TAtlasBoardFrame.SetLoading(AValue: Boolean);
begin
  FRefreshButton.Enabled := not AValue;
  if AValue then
    SetStatus(TAtlasStrings.Text(TAtlasTextId.BoardLoading));
end;

function TAtlasBoardFrame.MoveCard(ACard, AColumn: Integer): string;
begin
  Result := '';
  if (ACard < 0) or (ACard > High(FSnapshot.Cards)) or (AColumn < 0) or (AColumn > High(FSnapshot.Columns)) then
    Exit;
  Result := FSnapshot.Cards[ACard].State;
  if Length(FSnapshot.Columns[AColumn].Values) > 0 then
    FSnapshot.Cards[ACard].State := FSnapshot.Columns[AColumn].Values[0];
  UpdateView;
end;

procedure TAtlasBoardFrame.RevertMove(const AKey, AState: string);
var
  mCard: Integer;
begin
  mCard := FSnapshot.CardIndex(AKey);
  if mCard < 0 then
    Exit;
  FSnapshot.Cards[mCard].State := AState;
  UpdateView;
end;

procedure TAtlasBoardFrame.SetActiveKey(const AKey: string);
begin
  FView.ActiveKey := AKey;
  FView.Invalidate;
end;

procedure TAtlasBoardFrame.SetCanDrag(AValue: Boolean);
begin
  FView.CanDrag := AValue;
end;

procedure TAtlasBoardFrame.SetOnlyMine(AValue: Boolean);
begin
  FOnlyMine := AValue;
  FMine.Down := AValue;
  FAll.Down := not AValue;
  if FHasSnapshot then
    UpdateView;
end;

procedure TAtlasBoardFrame.BoardChange(Sender: TObject);
begin
  if FFilling or (FBoards.ItemIndex < 0) or (FBoards.ItemIndex > High(FBoardIds)) then
    Exit;
  if Assigned(FOnBoard) then
    FOnBoard(FBoardIds[FBoards.ItemIndex]);
end;

procedure TAtlasBoardFrame.SprintChange(Sender: TObject);
begin
  if FFilling or (FSprints.ItemIndex < 0) or (FSprints.ItemIndex > High(FSprintIds)) then
    Exit;
  if Assigned(FOnSprint) then
    FOnSprint(FSprintIds[FSprints.ItemIndex]);
end;

procedure TAtlasBoardFrame.MineClick(Sender: TObject);
begin
  if FMine.Down = FOnlyMine then
    Exit;
  SetOnlyMine(FMine.Down);
  if Assigned(FOnOnlyMine) then
    FOnOnlyMine(FOnlyMine);
end;

procedure TAtlasBoardFrame.SearchChange(Sender: TObject);
begin
  if FHasSnapshot then
    UpdateView;
end;

procedure TAtlasBoardFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TAtlasBoardFrame.ScrollResize(Sender: TObject);
begin
  if FHasSnapshot then
    FView.Relayout(ScrollWidth);
  FEmpty.Width := Max(ScrollWidth, ScaleValue(100));
end;

procedure TAtlasBoardFrame.MenuStart(Sender: TObject);
begin
  if Assigned(FOnStart) then
    FOnStart(FMenuCard);
end;

procedure TAtlasBoardFrame.MenuPreview(Sender: TObject);
begin
  if Assigned(FOnOpen) then
    FOnOpen(FMenuCard);
end;

procedure TAtlasBoardFrame.MenuBrowse(Sender: TObject);
begin
  if Assigned(FOnBrowse) then
    FOnBrowse(FMenuCard);
end;

procedure TAtlasBoardFrame.MenuCopy(Sender: TObject);
begin
  if (FMenuCard >= 0) and (FMenuCard <= High(FSnapshot.Cards)) then
    Clipboard.AsText := FSnapshot.Cards[FMenuCard].Key;
end;

procedure TAtlasBoardFrame.MenuAssign(Sender: TObject);
begin
  if Assigned(FOnAssign) then
    FOnAssign(FMenuCard);
end;

end.
