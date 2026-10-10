unit Argus.UI.Completion.Popup;

// Vervollständigungs-Popup (#410, #413): virtuelle Liste ohne Fokus. Gezeichnet
// werden nur die sichtbaren Zeilen; Filtern liefert nur ein neues Index-Array
// (AOrder), die Einträge selbst werden nicht kopiert.
// Aussehen nach dem Entwurf (#411, #420, #421):
//   - Zeile: farbiges Badge mit Kürzel (fn, pr, pp, ...), Name in der
//     Editorschrift mit den getippten Zeichen in Akzentfarbe, rechtsbündig
//     gedämpft das Detail und Tags ("+ Unit", deprecated). Zu lang: erst das
//     Detail kürzen, dann den Namen.
//   - Gewählte Zeile auf einer abgerundeten Akzentfläche, Text bleibt lesbar.
//   - Fußzeile mit Tasten und "n von m"; schmale Scrollleiste.
//   - Gekürzte Zeilen zeigen nach 600 ms Verweilen mit der Maus den vollen Text (#420).
//   - Detailpanel (#424) im selben Fenster, durch eine Linie abgetrennt auf
//     abgesetzter Fläche; rechts der Liste, ohne Platz dort links davon. Ist
//     es einmal offen, bleibt sein Bereich bis zum Schließen stehen. Strg+Q bzw.
//     Klick auf die Leiste klappt es auf eine schmale Leiste ein und wieder auf
//     (#428); passt es weder rechts noch links, ist es automatisch eingeklappt.
//   - Breiten (#416): Splitter zwischen Liste und Panel, rechter Rand und Griff
//     unten rechts mit der Maus ziehbar; Doppelklick auf den Griff stellt die
//     automatische Breite wieder her. Ohne gezogene Breite wächst die Liste mit
//     dem breitesten Eintrag. Gezogen wird ohne Aktivierung, der Editor behält
//     den Fokus.
// Die Position ergibt sich aus dem Anker (Caret-Rechteck in Bildschirm-
// koordinaten): darunter, sonst darüber; nie über den Monitorrand hinaus.
// Ohne Treffer zeigt es den leeren Zustand (#423). Breite und Höhe wachsen bei
// Bedarf, schrumpfen während einer Sitzung aber nicht (#416), damit es beim
// Filtern und Blättern nicht springt.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Argus.Core.Style.Color,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Controller,
  Argus.Core.Completion.Presentation,
  Argus.Core.Completion.Ranking,
  Argus.UI.Popup.Window,
  Argus.UI.Popup.Tip,
  Argus.UI.Strings,
  Argus.UI.Completion.Details;

type
  TArgusPositionEvent = reference to procedure(APosition: Integer);
  /// <summary>Gezogene Breiten in logischen Pixeln; AListWidth 0 = automatisch.</summary>
  TArgusWidthsEvent = reference to procedure(AListWidth, APanelWidth: Integer);
  TArgusPanelEvent = reference to procedure(ACollapsed: Boolean);

{$SCOPEDENUMS ON}
  TArgusChipEvent = reference to procedure(AChip: TArgusChip);
  TArgusOverloadEvent = reference to procedure(ADelta: Integer);
  TArgusDragKind = (None, ListWidth, PanelWidth);
  TArgusHitArea = (None, Splitter, Edge, Grip, PanelBar);
{$SCOPEDENUMS OFF}

  TArgusCompletionPopup = class(TArgusPopupWindow, IArgusCompletionView)
  public const
    DefaultVisibleRows = 9;
    MinWidth = 280;
    MaxWidth = 720;
    DefaultPanelWidth = 320;
    CollapsedPanelWidth = 22;
  private
    FItems: TArgusCompletionItems;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FTop: Integer;
    FVisibleRows: Integer;
    FAnchor: TRect;
    FPattern: string;
    FSessionWidth: Integer;
    FSessionHeight: Integer;
    FEmptyPrefix: string;
    FEmptyTotal: Integer;
    FShowingEmpty: Boolean;
    FDetailView: TArgusDetailView;
    /// <summary>Panelbereich in dieser Sitzung belegt.</summary>
    FPanelShown: Boolean;
    /// <summary>Panel links der Liste (rechts kein Platz).</summary>
    FPanelLeft: Boolean;
    FOnSelect: TArgusPositionEvent;
    FOnAccept: TArgusPositionEvent;
    // Tooltip für gekürzte Zeilen (#420): je sichtbarer Zeile gekürzt ja/nein, Zeile unter der Maus.
    FTip: TArgusTextTip;
    FTipTimer: TTimer;
    FTruncated: TArray<Boolean>;
    FHoverPosition: Integer;
    // Breiten (#416) in logischen Pixeln und eingeklapptes Panel (#428).
    FManualListWidth: Integer;
    FPanelWidthSetting: Integer;
    FPanelCollapsed: Boolean;
    FAutoCollapsed: Boolean;
    FDrag: TArgusDragKind;
    FDragStartX: Integer;
    FDragStartWidth: Integer;
    /// <summary>-1, wenn Ziehen nach links verbreitert (Panel links der Liste).</summary>
    FDragSign: Integer;
    FOnWidthsChanged: TArgusWidthsEvent;
    // Filter-Chips (#422) und geerbte Member (#419).
    FChipCounts: TArgusChipCounts;
    FChip: TArgusChip;
    FChipsVisible: Boolean;
    FChipRects: TArray<TRect>;
    FChipKinds: TArray<TArgusChip>;
    FOnChip: TArgusChipEvent;
    FOnOverload: TArgusOverloadEvent;
    FDimInherited: Boolean;
    FDimRow: Boolean;
    // Zeile einer Aktion („Neue Methode …“, #444): Name in Akzentfarbe.
    FActionRow: Boolean;
    FOnPanelToggled: TArgusPanelEvent;
    function Dim(AColor: TArgusColor): TArgusColor;
    function ChipsHeight: Integer;
    function ListTop: Integer;
    procedure DrawChips;
    procedure DrawHeader(ARow, APosition: Integer);
    /// <summary>Rechts in der Fußzeile: „3 von 84“ bzw. mit erwartetem Typ „3 passend · 84 gesamt“ (#417).</summary>
    function CountText: string;
    function ListWidth: Integer;
    function Collapsed: Boolean;
    function HitArea(AX, AY: Integer): TArgusHitArea;
    function Logical(APixels: Integer): Integer;
    procedure DrawGrip;
    procedure WidthsChanged;
    procedure TipTimer(Sender: TObject);
    procedure HideTip;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    function PanelWidth: Integer;
    /// <summary>Linker Rand der Listenspalte im Fenster.</summary>
    function ListLeft: Integer;
    function ListRight: Integer;
    function ListHeight: Integer;
    function PanelHeight: Integer;
    function PanelRect: TRect;
    procedure Relayout;
    function Pad: Integer;
    function RowHeight: Integer;
    function FooterHeight: Integer;
    function ScrollReserve: Integer;
    function RowCount: Integer;
    function RowAt(AX, AY: Integer): Integer;
    function RowRect(ARow: Integer): TRect;
    procedure EnsureSelectedVisible;
    procedure PlaceAndShow;
    function MeasureWidth: Integer;
    function TagWidth(const ATag: TArgusTag): Integer;
    procedure DrawBadge(const ARow: TRect; const AItem: TArgusCompletionItem; out ARight: Integer);
    procedure DrawName(const AName: string; ALeft, ARight: Integer; const ARow: TRect; ATruncated: Boolean);
    procedure DrawTag(const ATag: TArgusTag; ALeft: Integer; const ARow: TRect);
    procedure DrawRow(ARow, APosition: Integer);
    procedure DrawScrollBar;
    procedure DrawFooter(const ALeft, ARight: string);
    procedure PaintEmpty;
    procedure PaintPanel;
    procedure PlaceAt(AListWidth, AHeight: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Details zum gewählten Eintrag im Panelbereich zeigen; öffnet ihn bei Bedarf.</summary>
    procedure ShowDetails(const ADetails: TArgusItemDetails);
    /// <summary>Details leeren; ein offener Panelbereich bleibt mit Hinweis stehen.</summary>
    procedure ClearDetails;
    /// <summary>Panel ein- bzw. ausklappen (Strg+Q, #428).</summary>
    procedure TogglePanel;
    /// <summary>Gezeigte Überladung im Panel (#425); ACount 1 = keine Kopfzeile.</summary>
    procedure SetOverload(AIndex, ACount: Integer);
    { IArgusCompletionView }
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TArgusChipCounts; AActive: TArgusChip; AVisible: Boolean);
    /// <summary>Caret-Rechteck in Bildschirmkoordinaten; vor dem ersten ShowList setzen.</summary>
    property Anchor: TRect read FAnchor write FAnchor;
    property VisibleRows: Integer read FVisibleRows write FVisibleRows;
    property OnSelect: TArgusPositionEvent read FOnSelect write FOnSelect;
    property OnAccept: TArgusPositionEvent read FOnAccept write FOnAccept;
    /// <summary>Gezogene Breite der Liste in logischen Pixeln, 0 = automatisch (#416).</summary>
    property ManualListWidth: Integer read FManualListWidth write FManualListWidth;
    /// <summary>Breite des Panels in logischen Pixeln (#416).</summary>
    property PanelWidthSetting: Integer read FPanelWidthSetting write FPanelWidthSetting;
    property PanelCollapsed: Boolean read FPanelCollapsed write FPanelCollapsed;
    property OnWidthsChanged: TArgusWidthsEvent read FOnWidthsChanged write FOnWidthsChanged;
    property OnPanelToggled: TArgusPanelEvent read FOnPanelToggled write FOnPanelToggled;
    property OnChip: TArgusChipEvent read FOnChip write FOnChip;
    /// <summary>Klick auf ‹ bzw. › im Panel (#425).</summary>
    property OnOverload: TArgusOverloadEvent read FOnOverload write FOnOverload;
    /// <summary>Geerbte Member abgeschwächt zeichnen (#419).</summary>
    property DimInherited: Boolean read FDimInherited write FDimInherited;
  end;

implementation

uses
  System.Math,
  Argus.Core.Style.Palette;

const
  TextFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;

/// <summary>Text einer Marke in der Sprache der IDE (#446).</summary>
function TagText(const ATag: TArgusTag): string;
begin
  case ATag.Id of
    TArgusTagId.Recent: Result := TArgusStrings.Text(TArgusTextId.TagRecent);
    TArgusTagId.Frequent: Result := TArgusStrings.Text(TArgusTextId.TagFrequent);
  else
    Result := ATag.Text;
  end;
end;

{ TArgusCompletionPopup }

constructor TArgusCompletionPopup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVisibleRows := DefaultVisibleRows;
  FSelected := -1;
  FDetailView := TArgusDetailView.Create;
  FHoverPosition := -1;
  FTip := TArgusTextTip.Create(Self);
  FTipTimer := TTimer.Create(Self);
  FTipTimer.Enabled := False;
  FTipTimer.Interval := 600;
  FTipTimer.OnTimer := TipTimer;
  FPanelWidthSetting := DefaultPanelWidth;
end;

destructor TArgusCompletionPopup.Destroy;
begin
  FDetailView.Free;
  inherited Destroy;
end;

function TArgusCompletionPopup.Collapsed: Boolean;
begin
  Result := FPanelCollapsed or FAutoCollapsed;
end;

function TArgusCompletionPopup.PanelWidth: Integer;
begin
  if not FPanelShown then
    Result := 0
  else if Collapsed then
    Result := Scale(CollapsedPanelWidth)
  else
    Result := Scale(FPanelWidthSetting);
end;

function TArgusCompletionPopup.ListWidth: Integer;
begin
  if FManualListWidth > 0 then
    Result := Scale(FManualListWidth)
  else
    Result := FSessionWidth;
end;

function TArgusCompletionPopup.Logical(APixels: Integer): Integer;
begin
  Result := MulDiv(APixels, 96, PPI);
end;

function TArgusCompletionPopup.ListLeft: Integer;
begin
  if FPanelShown and FPanelLeft then
    Result := PanelWidth
  else
    Result := 0;
end;

function TArgusCompletionPopup.ListRight: Integer;
begin
  Result := ListLeft + ListWidth;
end;

function TArgusCompletionPopup.ListHeight: Integer;
begin
  if FShowingEmpty then
    Result := 2 * Pad + ChipsHeight + 2 * RowHeight + FooterHeight
  else
    Result := 2 * Pad + ChipsHeight + RowCount * RowHeight + FooterHeight;
end;

function TArgusCompletionPopup.PanelHeight: Integer;
begin
  if not FPanelShown or Collapsed then
    Exit(0);
  Result := FDetailView.Render(Canvas, Colors, Font, UIFont, Rect(0, 0, PanelWidth, 0), PPI, False);
  Canvas.Font := Font;
end;

function TArgusCompletionPopup.PanelRect: TRect;
begin
  if FPanelLeft then
    Result := Rect(0, 0, PanelWidth, ClientHeight)
  else
    Result := Rect(ListRight, 0, ListRight + PanelWidth, ClientHeight);
end;

procedure TArgusCompletionPopup.Relayout;
begin
  // Mit Panel wächst die Höhe nur, damit das Fenster beim Blättern nicht springt.
  if FPanelShown then
    FSessionHeight := Max(FSessionHeight, Max(ListHeight, PanelHeight))
  else
    FSessionHeight := ListHeight;
  PlaceAt(ListWidth, FSessionHeight);
end;

procedure TArgusCompletionPopup.ShowDetails(const ADetails: TArgusItemDetails);
begin
  FDetailView.Details := ADetails;
  if not FPanelShown and ADetails.IsEmpty then
    Exit;
  FPanelShown := True;
  if IsShown then
    Relayout;
  Invalidate;
end;

function TArgusCompletionPopup.Dim(AColor: TArgusColor): TArgusColor;
begin
  if FDimRow then
    Result := TArgusColorMath.Mix(AColor, Colors.Surface, 0.62)
  else
    Result := AColor;
end;

function TArgusCompletionPopup.ChipsHeight: Integer;
begin
  if not FChipsVisible or FShowingEmpty then
    Exit(0);
  Canvas.Font := UIFont;
  Result := Canvas.TextHeight('Wg') + Scale(12);
  Canvas.Font := Font;
end;

function TArgusCompletionPopup.ListTop: Integer;
begin
  Result := Pad + ChipsHeight;
end;

procedure TArgusCompletionPopup.ShowChips(const ACounts: TArgusChipCounts; AActive: TArgusChip; AVisible: Boolean);
var
  Shown: Integer;
  Chip: TArgusChip;
begin
  FChipCounts := ACounts;
  FChip := AActive;
  // Nur sinnvoll, wenn es mehr als eine Art gibt.
  Shown := 0;
  for Chip := Succ(TArgusChip.All) to High(TArgusChip) do
    if ACounts[Chip] > 0 then
      Inc(Shown);
  FChipsVisible := AVisible and (Shown >= 2);
end;

procedure TArgusCompletionPopup.DrawChips;
var
  Chip: TArgusChip;
  Text: string;
  X, Top, Height: Integer;
  Box, TextRect: TRect;
begin
  FChipRects := nil;
  FChipKinds := nil;
  if ChipsHeight = 0 then
    Exit;
  Canvas.Font := UIFont;
  Height := Canvas.TextHeight('Wg') + Scale(4);
  Top := Pad + (ChipsHeight - Height) div 2;
  X := ListLeft + Pad + Scale(4);
  for Chip := Low(TArgusChip) to High(TArgusChip) do
  begin
    if (Chip <> TArgusChip.All) and (FChipCounts[Chip] = 0) then
      Continue;
    Text := Format('%s %d', [TArgusStrings.Text(TArgusTextId(Ord(TArgusTextId.ChipAll) + Ord(Chip))),
      FChipCounts[Chip]]);
    Canvas.Font := UIFont;
    Box := Rect(X, Top, X + Canvas.TextWidth(Text) + Scale(14), Top + Height);
    if Box.Right > ListRight - Pad then
      Break;
    if Chip = FChip then
    begin
      FrameRounded(Box, Colors.Accent, 9, ToColor(Colors.AccentSoft));
      Canvas.Font.Color := ToColor(Colors.Accent);
    end
    else
    begin
      FrameRounded(Box, Colors.Line, 9);
      Canvas.Font.Color := ToColor(Colors.Muted);
    end;
    Canvas.Brush.Style := bsClear;
    TextRect := Box;
    DrawText(Canvas.Handle, PChar(Text), -1, TextRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    FChipRects := FChipRects + [Box];
    FChipKinds := FChipKinds + [Chip];
    X := Box.Right + Scale(6);
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

function TArgusCompletionPopup.CountText: string;
var
  Index, Fitting: Integer;
begin
  Fitting := 0;
  for Index in FOrder do
    if (Index >= 0) and FItems[Index].Fits and not FItems[Index].IsAction then
      Inc(Fitting);
  if Fitting > 0 then
    Result := TArgusStrings.Fmt(TArgusTextId.CountFits, [Fitting, TArgusRanking.ItemCount(FOrder)])
  else
    Result := TArgusStrings.Fmt(TArgusTextId.CountOf, [TArgusRanking.ItemCount(FOrder), Length(FItems)]);
end;

procedure TArgusCompletionPopup.DrawHeader(ARow, APosition: Integer);
var
  Row: TRect;
  Text: string;
begin
  // Überschrift einer Gruppe geerbter Member (#419): Klasse des nächsten Eintrags;
  // mit erwartetem Typ (#417, #444) „Passt zu …“ bzw. „Weitere“.
  Text := TArgusStrings.Text(TArgusTextId.InheritedPlain);
  if (APosition < High(FOrder)) and (FOrder[APosition + 1] >= 0) then
  begin
    if FItems[FOrder[APosition + 1]].ExpectedType <> '' then
    begin
      if FItems[FOrder[APosition + 1]].Fits then
        Text := TArgusStrings.Fmt(TArgusTextId.FitsType, [FItems[FOrder[APosition + 1]].ExpectedType])
      else
        Text := TArgusStrings.Text(TArgusTextId.OtherGroup);
    end
    else if FItems[FOrder[APosition + 1]].DeclaringClass <> '' then
      Text := TArgusStrings.Fmt(TArgusTextId.InheritedFrom, [FItems[FOrder[APosition + 1]].DeclaringClass]);
  end;
  Row := RowRect(ARow);
  Inc(Row.Left, Scale(7));
  Canvas.Font := UIFont;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Muted);
  Canvas.Brush.Style := bsClear;
  Row.Top := Row.Top + Scale(4);
  DrawText(Canvas.Handle, PChar(Text), -1, Row, TextFlags or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
  if ARow >= Length(FTruncated) then
    SetLength(FTruncated, ARow + 1);
  FTruncated[ARow] := False;
end;

procedure TArgusCompletionPopup.SetOverload(AIndex, ACount: Integer);
begin
  if (FDetailView.OverloadIndex = AIndex) and (FDetailView.OverloadCount = ACount) then
    Exit;
  FDetailView.OverloadIndex := AIndex;
  FDetailView.OverloadCount := ACount;
  if IsShown and FPanelShown then
    Relayout;
  Invalidate;
end;

procedure TArgusCompletionPopup.TogglePanel;
begin
  FPanelCollapsed := not FPanelCollapsed;
  if Assigned(FOnPanelToggled) then
    FOnPanelToggled(FPanelCollapsed);
  if IsShown then
    Relayout;
  Invalidate;
end;

procedure TArgusCompletionPopup.ClearDetails;
begin
  FDetailView.Details := Default(TArgusItemDetails);
  if FPanelShown then
    Invalidate;
end;

function TArgusCompletionPopup.Pad: Integer;
begin
  Result := Scale(4);
end;

function TArgusCompletionPopup.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Max(Canvas.TextHeight('Wg') + Scale(9), Scale(24));
end;

function TArgusCompletionPopup.FooterHeight: Integer;
begin
  Canvas.Font := UIFont;
  Result := Canvas.TextHeight('Wg') + Scale(10);
  Canvas.Font := Font;
end;

function TArgusCompletionPopup.ScrollReserve: Integer;
begin
  Result := Scale(8);
end;

function TArgusCompletionPopup.RowCount: Integer;
begin
  Result := Min(FVisibleRows, Length(FOrder));
end;

function TArgusCompletionPopup.PageSize: Integer;
begin
  Result := FVisibleRows;
end;

function TArgusCompletionPopup.RowRect(ARow: Integer): TRect;
var
  Height: Integer;
begin
  Height := RowHeight;
  Result := Rect(ListLeft + Pad, ListTop + ARow * Height, ListRight - Pad - ScrollReserve, ListTop + (ARow + 1) * Height);
end;

function TArgusCompletionPopup.RowAt(AX, AY: Integer): Integer;
begin
  if (AY < ListTop) or (AX < ListLeft) or (AX >= ListRight) then
    Exit(-1);
  Result := FTop + (AY - ListTop) div RowHeight;
  if (Result < FTop) or (Result >= Min(FTop + RowCount, Length(FOrder))) then
    Result := -1;
end;

procedure TArgusCompletionPopup.EnsureSelectedVisible;
begin
  if FSelected < 0 then
    Exit;
  if FSelected < FTop then
    FTop := FSelected
  else if FSelected >= FTop + FVisibleRows then
    FTop := FSelected - FVisibleRows + 1;
  FTop := EnsureRange(FTop, 0, Max(0, Length(FOrder) - FVisibleRows));
end;

function TArgusCompletionPopup.TagWidth(const ATag: TArgusTag): Integer;
begin
  Canvas.Font := UIFont;
  Result := Canvas.TextWidth(TagText(ATag)) + Scale(10);
  Canvas.Font := Font;
end;

function TArgusCompletionPopup.MeasureWidth: Integer;
var
  Position, Count, Widest, Width: Integer;
  Item: TArgusCompletionItem;
  Tag: TArgusTag;
  Detail: string;
begin
  // Nur die ersten Einträge messen; eine gezogene Breite (#416) hat Vorrang (ListWidth).
  Canvas.Font := Font;
  Widest := 0;
  Count := Min(Length(FOrder), 200);
  for Position := 0 to Count - 1 do
  begin
    if FOrder[Position] = TArgusRanking.Header then
      Continue;
    Item := FItems[FOrder[Position]];
    Width := Canvas.TextWidth(Item.Name);
    Detail := TArgusItemPresentation.Detail(Item);
    if Detail <> '' then
      Inc(Width, Scale(12) + Canvas.TextWidth(Detail));
    for Tag in TArgusItemPresentation.Tags(Item) do
      Inc(Width, Scale(6) + TagWidth(Tag));
    Widest := Max(Widest, Width);
  end;
  // Badge (7 + 24 + 9), rechter Rand der Zeile (7), Ränder und Scrollleiste.
  Inc(Widest, Scale(7 + 24 + 9 + 7) + 2 * Pad + ScrollReserve);
  Canvas.Font := UIFont;
  Widest := Max(Widest, Canvas.TextWidth(TArgusStrings.Text(TArgusTextId.FooterKeys) + '    ' +
    TArgusStrings.Fmt(TArgusTextId.CountFits, [999, 9999])) + Scale(18));
  Canvas.Font := Font;
  Result := EnsureRange(Widest, Scale(MinWidth), Scale(MaxWidth));
end;

procedure TArgusCompletionPopup.PlaceAndShow;
begin
  // Nur wachsen, nie schrumpfen, solange die Sitzung läuft (#416).
  FSessionWidth := Max(FSessionWidth, MeasureWidth);
  Relayout;
end;

procedure TArgusCompletionPopup.PlaceAt(AListWidth, AHeight: Integer);
var
  Bounds, Area: TRect;
  Left, Width: Integer;
begin
  Area := WorkAreaAt(FAnchor.TopLeft);
  // Die Liste bleibt am Wortanfang; das Panel rechts davon, ohne Platz dort links, ohne Platz auf
  // beiden Seiten eingeklappt (#428).
  Left := FAnchor.Left;
  FAutoCollapsed := False;
  FPanelLeft := False;
  if FPanelShown then
    if Left + AListWidth + PanelWidth > Area.Right then
      if Left - PanelWidth >= Area.Left then
        FPanelLeft := True
      else if not FPanelCollapsed then
      begin
        FAutoCollapsed := True;
        FPanelLeft := Left + AListWidth + PanelWidth > Area.Right;
      end;
  Width := AListWidth + PanelWidth;
  if FPanelLeft then
    Dec(Left, PanelWidth);
  Bounds := TRect.Create(Point(Left, FAnchor.Bottom + 2), Width, AHeight);
  // Unten kein Platz: über die Zeile.
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, FAnchor.Top - AHeight - 2);
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Width), Bounds.Top);
  if Bounds.Top < Area.Top then
    Bounds.SetLocation(Bounds.Left, Area.Top);
  ShowAt(Bounds);
end;

procedure TArgusCompletionPopup.ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
begin
  FShowingEmpty := False;
  FItems := AItems;
  FOrder := AOrder;
  FSelected := ASelected;
  FPattern := APattern;
  EnsureSelectedVisible;
  PlaceAndShow;
end;

procedure TArgusCompletionPopup.HideList;
begin
  HideTip;
  HidePopup;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FTop := 0;
  FSessionWidth := 0;
  FSessionHeight := 0;
  FShowingEmpty := False;
  FPanelShown := False;
  FAutoCollapsed := False;
  FDrag := TArgusDragKind.None;
  FDetailView.Details := Default(TArgusItemDetails);
  FDetailView.OverloadIndex := 0;
  FDetailView.OverloadCount := 0;
end;

procedure TArgusCompletionPopup.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FTop := 0;
  FEmptyPrefix := APrefix;
  FEmptyTotal := ATotal;
  FShowingEmpty := True;
  Canvas.Font := UIFont;
  FSessionWidth := Max(FSessionWidth, Max(Scale(MinWidth),
    Canvas.TextWidth(TArgusStrings.Fmt(TArgusTextId.NoMatchesFor, [APrefix])) + Scale(32)));
  Canvas.Font := Font;
  Relayout;
end;

procedure TArgusCompletionPopup.DrawFooter(const ALeft, ARight: string);
var
  Footer, Text: TRect;
begin
  // Nur unter der Liste; das Panel reicht bis unten.
  Footer := Rect(ListLeft, ClientHeight - FooterHeight, ListRight, ClientHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(Footer);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(Footer.Left, Footer.Top);
  Canvas.LineTo(Footer.Right, Footer.Top);
  Canvas.Font := UIFont;
  Canvas.Font.Color := ToColor(Colors.Muted);
  Canvas.Brush.Style := bsClear;
  Text := Rect(Footer.Left + Scale(9), Footer.Top + 1, Footer.Right - Scale(9), Footer.Bottom);
  DrawText(Canvas.Handle, PChar(ARight), -1, Text, TextFlags or DT_RIGHT);
  Text.Right := Text.Right - Canvas.TextWidth(ARight) - Scale(10);
  DrawText(Canvas.Handle, PChar(ALeft), -1, Text, TextFlags or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TArgusCompletionPopup.PaintEmpty;
var
  Line: TRect;

  procedure DrawLine(AIndex: Integer; const AText: string; AColor: TArgusColor);
  begin
    Line := Rect(ListLeft + Pad + Scale(7), ListTop + AIndex * RowHeight, ListRight - Pad - Scale(7),
      ListTop + (AIndex + 1) * RowHeight);
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(AColor);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(AText), -1, Line, TextFlags or DT_END_ELLIPSIS);
  end;

begin
  if FEmptyPrefix <> '' then
  begin
    DrawLine(0, TArgusStrings.Fmt(TArgusTextId.NoMatchesFor, [FEmptyPrefix]), Colors.Text);
    DrawLine(1, TArgusStrings.Text(TArgusTextId.BackspaceWidens), Colors.Muted);
  end
  else
    DrawLine(0, TArgusStrings.Text(TArgusTextId.NoSuggestions), Colors.Text);
  Canvas.Brush.Style := bsSolid;
  DrawFooter(TArgusStrings.Text(TArgusTextId.EscCloses), TArgusStrings.Fmt(TArgusTextId.CountOf, [0, FEmptyTotal]));
end;

procedure TArgusCompletionPopup.DrawBadge(const ARow: TRect; const AItem: TArgusCompletionItem;
  out ARight: Integer);
var
  Badge: TArgusBadge;
  Box, Text: TRect;
  Top: Integer;
begin
  Badge := TArgusItemPresentation.Badge(AItem);
  Top := ARow.Top + (ARow.Height - Scale(17)) div 2;
  Box := Rect(ARow.Left + Scale(7), Top, ARow.Left + Scale(7 + 24), Top + Scale(17));
  FillRounded(Box, Dim(Colors.Badges[Badge.Kind].Background), 4);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Height := -Round(Box.Height * 0.62);
  Canvas.Font.Color := ToColor(Dim(Colors.Badges[Badge.Kind].Text));
  Canvas.Brush.Style := bsClear;
  Text := Box;
  DrawText(Canvas.Handle, PChar(Badge.Code), -1, Text, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Canvas.Font := Font;
  ARight := Box.Right;
end;

procedure TArgusCompletionPopup.DrawName(const AName: string; ALeft, ARight: Integer; const ARow: TRect;
  ATruncated: Boolean);
var
  Marks: TArray<Boolean>;
  Position, Index, Run, X: Integer;
  Part: TRect;
  Text: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  if ATruncated or (FPattern = '') or FActionRow then
  begin
    // Gekürzt ohne Hervorhebung: Die Positionen passen nicht mehr zur Ellipse.
    if FActionRow then
      Canvas.Font.Color := ToColor(Colors.Accent)
    else
      Canvas.Font.Color := ToColor(Dim(Colors.Text));
    Part := Rect(ALeft, ARow.Top, ARight, ARow.Bottom);
    DrawText(Canvas.Handle, PChar(AName), -1, Part, TextFlags or DT_END_ELLIPSIS);
    Exit;
  end;
  SetLength(Marks, Length(AName) + 1);
  for Position in TArgusItemPresentation.Highlights(FPattern, AName) do
    if (Position >= 1) and (Position <= Length(AName)) then
      Marks[Position] := True;
  // Läufe gleicher Hervorhebung nacheinander zeichnen.
  X := ALeft;
  Index := 1;
  while Index <= Length(AName) do
  begin
    Run := Index;
    while (Run < Length(AName)) and (Marks[Run + 1] = Marks[Index]) do
      Inc(Run);
    Text := Copy(AName, Index, Run - Index + 1);
    if Marks[Index] then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(Dim(Colors.Accent));
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := ToColor(Dim(Colors.Text));
    end;
    Part := Rect(X, ARow.Top, ARight, ARow.Bottom);
    DrawText(Canvas.Handle, PChar(Text), -1, Part, TextFlags);
    Inc(X, Canvas.TextWidth(Text));
    Index := Run + 1;
  end;
  Canvas.Font.Style := [];
end;

procedure TArgusCompletionPopup.DrawTag(const ATag: TArgusTag; ALeft: Integer; const ARow: TRect);
var
  Box, Text: TRect;
  Line, TextColor: TArgusColor;
  Height: Integer;
begin
  case ATag.Kind of
    TArgusTagKind.Accent: begin Line := Colors.Accent; TextColor := Colors.Accent; end;
    TArgusTagKind.Add: begin Line := Colors.Add; TextColor := Colors.Add; end;
    TArgusTagKind.Warn: begin Line := Colors.Warn; TextColor := Colors.Warn; end;
  else
    Line := Colors.Line;
    TextColor := Colors.Muted;
  end;
  Canvas.Font := UIFont;
  Height := Canvas.TextHeight('Wg') + Scale(2);
  Box := Rect(ALeft, ARow.Top + (ARow.Height - Height) div 2, ALeft + TagWidth(ATag), 0);
  Box.Bottom := Box.Top + Height;
  Canvas.Font := UIFont;
  FrameRounded(Box, Line, 3);
  Canvas.Font.Color := ToColor(TextColor);
  Canvas.Brush.Style := bsClear;
  Text := Box;
  DrawText(Canvas.Handle, PChar(TagText(ATag)), -1, Text, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TArgusCompletionPopup.DrawRow(ARow, APosition: Integer);
var
  Item: TArgusCompletionItem;
  Row, Part: TRect;
  NameLeft, Right, NameWidth, TagsWidth, DetailWidth, Space, Gap, X: Integer;
  Tags: TArgusTags;
  Tag: TArgusTag;
  Detail: string;
  Truncated: Boolean;
begin
  Item := FItems[FOrder[APosition]];
  Row := RowRect(ARow);
  // Geerbte Member mit 62 % Deckkraft (#419); die gewählte Zeile bleibt voll lesbar.
  FDimRow := FDimInherited and (Item.Depth > 0) and (APosition <> FSelected);
  if APosition = FSelected then
    FillRounded(Row, Colors.Selection, 4);
  DrawBadge(Row, Item, NameLeft);
  Inc(NameLeft, Scale(9));
  Right := Row.Right - Scale(7);
  Gap := Scale(6);
  // Breiten: Name, Tags, Detail; zu lang: erst das Detail kürzen bzw. weglassen, dann den Namen.
  Canvas.Font := Font;
  NameWidth := Canvas.TextWidth(Item.Name);
  Tags := TArgusItemPresentation.Tags(Item);
  TagsWidth := 0;
  for Tag in Tags do
    Inc(TagsWidth, TagWidth(Tag) + Gap);
  Detail := TArgusItemPresentation.Detail(Item);
  Canvas.Font := Font;
  DetailWidth := 0;
  Space := Right - NameLeft;
  if Detail <> '' then
  begin
    DetailWidth := Min(Canvas.TextWidth(Detail), Space - NameWidth - TagsWidth - Scale(12));
    if DetailWidth < Scale(40) then
      DetailWidth := 0;
  end;
  Truncated := (Detail <> '') and (DetailWidth < Canvas.TextWidth(Detail));
  // Rechts: Detail ganz außen, Tags davor.
  X := Right;
  if DetailWidth > 0 then
  begin
    Part := Rect(X - DetailWidth, Row.Top, X, Row.Bottom);
    Canvas.Font.Color := ToColor(Dim(Colors.Muted));
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Detail), -1, Part, TextFlags or DT_END_ELLIPSIS);
    Dec(X, DetailWidth + Gap);
  end;
  for Tag in Tags do
  begin
    Dec(X, TagWidth(Tag));
    if X < NameLeft + Scale(40) then
    begin
      Truncated := True;
      Break;
    end;
    DrawTag(Tag, X, Row);
    Dec(X, Gap);
  end;
  FActionRow := Item.IsAction;
  DrawName(Item.Name, NameLeft, Max(NameLeft, X - Gap), Row, NameLeft + NameWidth > X - Gap);
  FActionRow := False;
  Canvas.Brush.Style := bsSolid;
  if ARow >= Length(FTruncated) then
    SetLength(FTruncated, ARow + 1);
  FTruncated[ARow] := Truncated or (NameLeft + NameWidth > X - Gap);
  FDimRow := False;
end;

procedure TArgusCompletionPopup.DrawScrollBar;
var
  Track, Thumb: TRect;
  Total, Visible, ThumbHeight, ThumbTop: Integer;
begin
  Total := Length(FOrder);
  Visible := RowCount;
  if Total <= Visible then
    Exit;
  Track := Rect(ListRight - Pad - Scale(5), ListTop + Scale(2), ListRight - Pad - Scale(1),
    ListTop + Visible * RowHeight - Scale(2));
  ThumbHeight := Max(Scale(16), Track.Height * Visible div Total);
  ThumbTop := Track.Top + (Track.Height - ThumbHeight) * FTop div Max(1, Total - Visible);
  Thumb := Rect(Track.Left, ThumbTop, Track.Right, ThumbTop + ThumbHeight);
  FillRounded(Thumb, TArgusColorMath.Mix(Colors.Muted, Colors.Surface, 0.45), 2);
end;

procedure TArgusCompletionPopup.Paint;
var
  Row: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  if FShowingEmpty then
    PaintEmpty
  else
  begin
    DrawChips;
    for Row := 0 to RowCount - 1 do
      if FTop + Row < Length(FOrder) then
        if FOrder[FTop + Row] = TArgusRanking.Header then
          DrawHeader(Row, FTop + Row)
        else
          DrawRow(Row, FTop + Row);
    DrawScrollBar;
    DrawFooter(TArgusStrings.Text(TArgusTextId.FooterKeys), CountText);
  end;
  if FPanelShown then
    PaintPanel;
  DrawGrip;
  PaintBorder;
end;

procedure TArgusCompletionPopup.PaintPanel;
var
  Panel, Bar: TRect;
  Edge: Integer;
  Arrow: string;
begin
  Panel := PanelRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(Panel);
  // Trennlinie zur Liste.
  if FPanelLeft then
    Edge := Panel.Right - 1
  else
    Edge := Panel.Left;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(Edge, 0);
  Canvas.LineTo(Edge, ClientHeight);
  if Collapsed then
  begin
    // Schmale Leiste (#428): Pfeil zeigt, wohin das Panel aufklappt.
    Canvas.Font := UIFont;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.Brush.Style := bsClear;
    Bar := Rect(Panel.Left, Scale(6), Panel.Right, Scale(6) + Canvas.TextHeight('Wg'));
    if FPanelLeft then
      Arrow := '‹'
    else
      Arrow := '›';
    DrawText(Canvas.Handle, PChar(Arrow), -1, Bar, DT_CENTER or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Font.Style := [];
  end
  else
    FDetailView.Render(Canvas, Colors, Font, UIFont, Panel, PPI, True);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
end;

procedure TArgusCompletionPopup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Position, Index: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  case HitArea(X, Y) of
    TArgusHitArea.PanelBar:
      begin
        TogglePanel;
        Exit;
      end;
    TArgusHitArea.Splitter:
      begin
        // Splitter: rechts liegendes Panel → Breite der Liste; links liegendes → Breite des Panels.
        HideTip;
        FDragSign := 1;
        if FPanelLeft then
        begin
          // Die Liste bleibt am Wortanfang; das Panel wächst nach links.
          FDrag := TArgusDragKind.PanelWidth;
          FDragStartWidth := PanelWidth;
          FDragSign := -1;
        end
        else
        begin
          FDrag := TArgusDragKind.ListWidth;
          FDragStartWidth := ListWidth;
        end;
        FDragStartX := Mouse.CursorPos.X;
        Exit;
      end;
    TArgusHitArea.Edge, TArgusHitArea.Grip:
      begin
        // Rechter Rand: Panel rechts und offen → dessen Breite, sonst die der Liste.
        HideTip;
        FDragSign := 1;
        if FPanelShown and not FPanelLeft and not Collapsed then
        begin
          FDrag := TArgusDragKind.PanelWidth;
          FDragStartWidth := PanelWidth;
        end
        else
        begin
          FDrag := TArgusDragKind.ListWidth;
          FDragStartWidth := ListWidth;
        end;
        FDragStartX := Mouse.CursorPos.X;
        Exit;
      end;
  end;
  // Pfeile der Überladungen im Panel (#425).
  if FPanelShown and not Collapsed and Assigned(FOnOverload) then
    if PtInRect(FDetailView.PreviousRect, Point(X, Y)) then
    begin
      FOnOverload(-1);
      Exit;
    end
    else if PtInRect(FDetailView.NextRect, Point(X, Y)) then
    begin
      FOnOverload(1);
      Exit;
    end;
  // Klick auf einen Chip (#422).
  for Index := 0 to High(FChipRects) do
    if PtInRect(FChipRects[Index], Point(X, Y)) then
    begin
      if Assigned(FOnChip) then
        FOnChip(FChipKinds[Index]);
      Exit;
    end;
  Position := RowAt(X, Y);
  if (Position >= 0) and Assigned(FOnSelect) then
    FOnSelect(Position);
end;

procedure TArgusCompletionPopup.DblClick;
var
  Point_: TPoint;
begin
  inherited;
  // Doppelklick auf den Griff: automatische Breiten (#416).
  Point_ := ScreenToClient(Mouse.CursorPos);
  if HitArea(Point_.X, Point_.Y) = TArgusHitArea.Grip then
  begin
    FManualListWidth := 0;
    FPanelWidthSetting := DefaultPanelWidth;
    FDrag := TArgusDragKind.None;
    Relayout;
    Invalidate;
    WidthsChanged;
    Exit;
  end;
  if (FSelected >= 0) and Assigned(FOnAccept) then
    FOnAccept(FSelected);
end;

procedure TArgusCompletionPopup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Position, Width: Integer;
begin
  inherited;
  // Ziehen (#416): Bildschirmkoordinaten, weil das Fenster beim Ziehen mitwächst.
  if FDrag <> TArgusDragKind.None then
  begin
    Width := FDragStartWidth + FDragSign * (Mouse.CursorPos.X - FDragStartX);
    if FDrag = TArgusDragKind.ListWidth then
      FManualListWidth := EnsureRange(Logical(Width), MinWidth, MaxWidth)
    else
      FPanelWidthSetting := EnsureRange(Logical(Width), 220, 600);
    Relayout;
    Invalidate;
    Exit;
  end;
  case HitArea(X, Y) of
    TArgusHitArea.Splitter: Cursor := crHSplit;
    TArgusHitArea.Edge, TArgusHitArea.Grip: Cursor := crSizeWE;
    TArgusHitArea.PanelBar: Cursor := crHandPoint;
  else
    Cursor := crDefault;
  end;
  Position := RowAt(X, Y);
  if Position = FHoverPosition then
    Exit;
  HideTip;
  FHoverPosition := Position;
  FTipTimer.Enabled := Position >= 0;
end;

procedure TArgusCompletionPopup.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FDrag = TArgusDragKind.None then
    Exit;
  FDrag := TArgusDragKind.None;
  WidthsChanged;
end;

procedure TArgusCompletionPopup.WidthsChanged;
begin
  if Assigned(FOnWidthsChanged) then
    FOnWidthsChanged(FManualListWidth, FPanelWidthSetting);
end;

function TArgusCompletionPopup.HitArea(AX, AY: Integer): TArgusHitArea;
var
  Boundary, Zone: Integer;
begin
  Result := TArgusHitArea.None;
  Zone := Scale(4);
  if AX >= ClientWidth - Zone then
  begin
    if AY >= ClientHeight - Scale(16) then
      Result := TArgusHitArea.Grip
    else
      Result := TArgusHitArea.Edge;
    Exit;
  end;
  if not FPanelShown then
    Exit;
  if Collapsed then
  begin
    if PtInRect(PanelRect, Point(AX, AY)) then
      Result := TArgusHitArea.PanelBar;
    Exit;
  end;
  if FPanelLeft then
    Boundary := PanelWidth
  else
    Boundary := ListRight;
  if Abs(AX - Boundary) <= Zone then
    Result := TArgusHitArea.Splitter;
end;

procedure TArgusCompletionPopup.DrawGrip;
var
  Row, Column, Size, Step, Right, Bottom: Integer;
begin
  // Punktmuster unten rechts (#416): drei Reihen, nach unten rechts dichter.
  Size := Max(1, Scale(2));
  Step := Scale(4);
  Right := ClientWidth - Scale(4);
  Bottom := ClientHeight - Scale(4);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(TArgusColorMath.Mix(Colors.Muted, Colors.Surface, 0.6));
  for Row := 0 to 2 do
    for Column := 0 to 2 - Row do
      Canvas.FillRect(Rect(Right - (Column + 1) * Step + Step - Size, Bottom - (Row + 1) * Step + Step - Size,
        Right - Column * Step, Bottom - Row * Step));
end;

procedure TArgusCompletionPopup.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  HideTip;
  FHoverPosition := -1;
end;

procedure TArgusCompletionPopup.HideTip;
begin
  FTipTimer.Enabled := False;
  FTip.HidePopup;
end;

procedure TArgusCompletionPopup.TipTimer(Sender: TObject);
var
  Row: Integer;
  Item: TArgusCompletionItem;
  Text, Detail: string;
  Tag: TArgusTag;
  Area: TRect;
begin
  FTipTimer.Enabled := False;
  Row := FHoverPosition - FTop;
  if not IsShown or (FHoverPosition < 0) or (FHoverPosition >= Length(FOrder)) or (Row < 0) or
    (Row >= Length(FTruncated)) or not FTruncated[Row] or (FOrder[FHoverPosition] = TArgusRanking.Header) then
    Exit;
  Item := FItems[FOrder[FHoverPosition]];
  Text := Item.Name;
  Detail := TArgusItemPresentation.Detail(Item);
  if Detail <> '' then
    Text := Text + '   ' + Detail;
  for Tag in TArgusItemPresentation.Tags(Item) do
    Text := Text + '   [' + TagText(Tag) + ']';
  FTip.Colors := Colors;
  FTip.SetScaling(PPI, 1, Font.Name, Font.Size);
  Area := RowRect(Row);
  FTip.ShowText(Text, ClientToScreen(Point(Area.Left, Area.Bottom + Scale(2))));
end;

function TArgusCompletionPopup.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  HideTip;
  if WheelDelta > 0 then
    FTop := Max(0, FTop - 3)
  else
    FTop := Min(Max(0, Length(FOrder) - FVisibleRows), FTop + 3);
  Invalidate;
end;

end.
