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
//     es einmal offen, bleibt sein Bereich bis zum Schließen stehen.
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
  Argus.UI.Popup.Window,
  Argus.UI.Popup.Tip,
  Argus.UI.Completion.Details;

type
  TArgusPositionEvent = reference to procedure(APosition: Integer);

  TArgusCompletionPopup = class(TArgusPopupWindow, IArgusCompletionView)
  public const
    DefaultVisibleRows = 9;
    MinWidth = 280;
    MaxWidth = 720;
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
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Details zum gewählten Eintrag im Panelbereich zeigen; öffnet ihn bei Bedarf.</summary>
    procedure ShowDetails(const ADetails: TArgusItemDetails);
    /// <summary>Details leeren; ein offener Panelbereich bleibt mit Hinweis stehen.</summary>
    procedure ClearDetails;
    { IArgusCompletionView }
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    /// <summary>Caret-Rechteck in Bildschirmkoordinaten; vor dem ersten ShowList setzen.</summary>
    property Anchor: TRect read FAnchor write FAnchor;
    property VisibleRows: Integer read FVisibleRows write FVisibleRows;
    property OnSelect: TArgusPositionEvent read FOnSelect write FOnSelect;
    property OnAccept: TArgusPositionEvent read FOnAccept write FOnAccept;
  end;

implementation

uses
  System.Math,
  Argus.Core.Style.Palette;

const
  TextFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
  FooterKeys = 'Enter übernehmen · Esc schließen';

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
end;

destructor TArgusCompletionPopup.Destroy;
begin
  FDetailView.Free;
  inherited Destroy;
end;

function TArgusCompletionPopup.PanelWidth: Integer;
begin
  if FPanelShown then
    Result := Scale(TArgusDetailView.DefaultWidth)
  else
    Result := 0;
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
  Result := ListLeft + FSessionWidth;
end;

function TArgusCompletionPopup.ListHeight: Integer;
begin
  if FShowingEmpty then
    Result := 2 * Pad + 2 * RowHeight + FooterHeight
  else
    Result := 2 * Pad + RowCount * RowHeight + FooterHeight;
end;

function TArgusCompletionPopup.PanelHeight: Integer;
begin
  if not FPanelShown then
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
  PlaceAt(FSessionWidth, FSessionHeight);
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
  Result := Rect(ListLeft + Pad, Pad + ARow * Height, ListRight - Pad - ScrollReserve, Pad + (ARow + 1) * Height);
end;

function TArgusCompletionPopup.RowAt(AX, AY: Integer): Integer;
begin
  if (AY < Pad) or (AX < ListLeft) or (AX >= ListRight) then
    Exit(-1);
  Result := FTop + (AY - Pad) div RowHeight;
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
  Result := Canvas.TextWidth(ATag.Text) + Scale(10);
  Canvas.Font := Font;
end;

function TArgusCompletionPopup.MeasureWidth: Integer;
var
  Position, Count, Widest, Width: Integer;
  Item: TArgusCompletionItem;
  Tag: TArgusTag;
  Detail: string;
begin
  // Nur die ersten Einträge messen; Breite manuell ziehen folgt mit #416.
  Canvas.Font := Font;
  Widest := 0;
  Count := Min(Length(FOrder), 200);
  for Position := 0 to Count - 1 do
  begin
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
  Widest := Max(Widest, Canvas.TextWidth(FooterKeys + '    999 von 9999') + Scale(18));
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
  Width := AListWidth + PanelWidth;
  // Die Liste bleibt am Wortanfang; das Panel rechts davon, ohne Platz dort links.
  Left := FAnchor.Left;
  FPanelLeft := FPanelShown and (Left + Width > Area.Right) and (Left - PanelWidth >= Area.Left);
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
  FDetailView.Details := Default(TArgusItemDetails);
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
    Canvas.TextWidth('Keine Treffer für „' + APrefix + '“') + Scale(32)));
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
    Line := Rect(ListLeft + Pad + Scale(7), Pad + AIndex * RowHeight, ListRight - Pad - Scale(7),
      Pad + (AIndex + 1) * RowHeight);
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(AColor);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(AText), -1, Line, TextFlags or DT_END_ELLIPSIS);
  end;

begin
  if FEmptyPrefix <> '' then
  begin
    DrawLine(0, 'Keine Treffer für „' + FEmptyPrefix + '“', Colors.Text);
    DrawLine(1, 'Rücktaste erweitert die Suche', Colors.Muted);
  end
  else
    DrawLine(0, 'Keine Vorschläge an dieser Stelle', Colors.Text);
  Canvas.Brush.Style := bsSolid;
  DrawFooter('Esc schließt', Format('0 von %d', [FEmptyTotal]));
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
  FillRounded(Box, Colors.Badges[Badge.Kind].Background, 4);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Height := -Round(Box.Height * 0.62);
  Canvas.Font.Color := ToColor(Colors.Badges[Badge.Kind].Text);
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
  if ATruncated or (FPattern = '') then
  begin
    // Gekürzt ohne Hervorhebung: Die Positionen passen nicht mehr zur Ellipse.
    Canvas.Font.Color := ToColor(Colors.Text);
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
      Canvas.Font.Color := ToColor(Colors.Accent);
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := ToColor(Colors.Text);
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
  DrawText(Canvas.Handle, PChar(ATag.Text), -1, Text, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
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
    Canvas.Font.Color := ToColor(Colors.Muted);
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
  DrawName(Item.Name, NameLeft, Max(NameLeft, X - Gap), Row, NameLeft + NameWidth > X - Gap);
  Canvas.Brush.Style := bsSolid;
  if ARow >= Length(FTruncated) then
    SetLength(FTruncated, ARow + 1);
  FTruncated[ARow] := Truncated or (NameLeft + NameWidth > X - Gap);
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
  Track := Rect(ListRight - Pad - Scale(5), Pad + Scale(2), ListRight - Pad - Scale(1),
    Pad + Visible * RowHeight - Scale(2));
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
    for Row := 0 to RowCount - 1 do
      if FTop + Row < Length(FOrder) then
        DrawRow(Row, FTop + Row);
    DrawScrollBar;
    DrawFooter(FooterKeys, Format('%d von %d', [Length(FOrder), Length(FItems)]));
  end;
  if FPanelShown then
    PaintPanel;
  PaintBorder;
end;

procedure TArgusCompletionPopup.PaintPanel;
var
  Panel: TRect;
  Edge: Integer;
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
  FDetailView.Render(Canvas, Colors, Font, UIFont, Panel, PPI, True);
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
end;

procedure TArgusCompletionPopup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Position: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Position := RowAt(X, Y);
  if (Position >= 0) and Assigned(FOnSelect) then
    FOnSelect(Position);
end;

procedure TArgusCompletionPopup.DblClick;
begin
  inherited;
  if (FSelected >= 0) and Assigned(FOnAccept) then
    FOnAccept(FSelected);
end;

procedure TArgusCompletionPopup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Position: Integer;
begin
  inherited;
  Position := RowAt(X, Y);
  if Position = FHoverPosition then
    Exit;
  HideTip;
  FHoverPosition := Position;
  FTipTimer.Enabled := Position >= 0;
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
    (Row >= Length(FTruncated)) or not FTruncated[Row] then
    Exit;
  Item := FItems[FOrder[FHoverPosition]];
  Text := Item.Name;
  Detail := TArgusItemPresentation.Detail(Item);
  if Detail <> '' then
    Text := Text + '   ' + Detail;
  for Tag in TArgusItemPresentation.Tags(Item) do
    Text := Text + '   [' + Tag.Text + ']';
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
