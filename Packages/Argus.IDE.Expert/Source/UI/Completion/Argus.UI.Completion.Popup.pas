unit Argus.UI.Completion.Popup;

// Vervollständigungs-Popup (#410, #413): virtuelle Liste ohne Fokus. Gezeichnet
// werden nur die sichtbaren Zeilen; Filtern liefert nur ein neues Index-Array
// (AOrder), die Einträge selbst werden nicht kopiert. Je Zeile Kennbuchstabe der
// Art, Name und grau die Signatur. Schmale eigene Scrollleiste, Mausrad 3 Zeilen.
// Die Position ergibt sich aus dem Anker (Caret-Rechteck in Bildschirm-
// koordinaten): darunter, sonst darüber; nie über den Monitorrand hinaus.
// Ohne Treffer zeigt es den leeren Zustand (#423). Die Breite wächst bei Bedarf,
// schrumpft während einer Sitzung aber nicht (#416), damit es beim Filtern nicht springt.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Controller,
  Argus.UI.Popup.Window;

type
  TArgusPositionEvent = reference to procedure(APosition: Integer);

  TArgusCompletionPopup = class(TArgusPopupWindow, IArgusCompletionView)
  public const
    DefaultVisibleRows = 9;
    MinWidth = 260;
    MaxWidth = 720;
    ScrollBarWidth = 6;
  private
    FItems: TArgusCompletionItems;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FTop: Integer;
    FVisibleRows: Integer;
    FAnchor: TRect;
    FSessionWidth: Integer;
    FEmptyPrefix: string;
    FEmptyTotal: Integer;
    FShowingEmpty: Boolean;
    FOnSelect: TArgusPositionEvent;
    FOnAccept: TArgusPositionEvent;
    function RowHeight: Integer;
    function RowCount: Integer;
    function RowAt(AY: Integer): Integer;
    procedure EnsureSelectedVisible;
    procedure PlaceAndShow;
    function MeasureWidth: Integer;
    procedure DrawRow(ARow, APosition: Integer);
    procedure DrawScrollBar;
    procedure PaintEmpty;
    procedure PlaceAt(AWidth, AHeight: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    { IArgusCompletionView }
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    /// <summary>Caret-Rechteck in Bildschirmkoordinaten; vor dem ersten ShowList setzen.</summary>
    property Anchor: TRect read FAnchor write FAnchor;
    property VisibleRows: Integer read FVisibleRows write FVisibleRows;
    property OnSelect: TArgusPositionEvent read FOnSelect write FOnSelect;
    property OnAccept: TArgusPositionEvent read FOnAccept write FOnAccept;
    /// <summary>Kennbuchstabe der Art, z. B. M für Methode.</summary>
    class function KindLetter(AKind: TArgusItemKind): string; static;
  end;

implementation

uses
  System.Math;

{ TArgusCompletionPopup }

constructor TArgusCompletionPopup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVisibleRows := DefaultVisibleRows;
  FSelected := -1;
end;

class function TArgusCompletionPopup.KindLetter(AKind: TArgusItemKind): string;
begin
  case AKind of
    TArgusItemKind.Method, TArgusItemKind.Procedure_: Result := 'M';
    TArgusItemKind.Function_: Result := 'F';
    TArgusItemKind.Constructor_, TArgusItemKind.Destructor_: Result := 'C';
    TArgusItemKind.Property_: Result := 'P';
    TArgusItemKind.Field: Result := 'f';
    TArgusItemKind.Event: Result := 'E';
    TArgusItemKind.Variable, TArgusItemKind.Parameter: Result := 'v';
    TArgusItemKind.Constant, TArgusItemKind.EnumMember: Result := 'c';
    TArgusItemKind.Type_, TArgusItemKind.Class_, TArgusItemKind.Interface_, TArgusItemKind.Record_,
    TArgusItemKind.Enum: Result := 'T';
    TArgusItemKind.Unit_: Result := 'U';
    TArgusItemKind.Keyword: Result := 'K';
    TArgusItemKind.Snippet: Result := 'S';
  else
    Result := '·';
  end;
end;

function TArgusCompletionPopup.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + MulDiv(6, CurrentPPI, 96);
end;

function TArgusCompletionPopup.RowCount: Integer;
begin
  Result := Min(FVisibleRows, Length(FOrder));
end;

function TArgusCompletionPopup.PageSize: Integer;
begin
  Result := FVisibleRows;
end;

function TArgusCompletionPopup.RowAt(AY: Integer): Integer;
begin
  Result := FTop + (AY - 1) div RowHeight;
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

function TArgusCompletionPopup.MeasureWidth: Integer;
var
  Position, Count, Widest: Integer;
  Item: TArgusCompletionItem;
begin
  // Nur die ersten Einträge messen; Breite manuell ziehen folgt mit #416.
  Canvas.Font := Font;
  Widest := 0;
  Count := Min(Length(FOrder), 200);
  for Position := 0 to Count - 1 do
  begin
    Item := FItems[FOrder[Position]];
    Widest := Max(Widest, Canvas.TextWidth(Item.Name) + Canvas.TextWidth('  ' + Item.Signature));
  end;
  Result := EnsureRange(Widest + RowHeight + MulDiv(24, CurrentPPI, 96), MulDiv(MinWidth, CurrentPPI, 96),
    MulDiv(MaxWidth, CurrentPPI, 96));
end;

procedure TArgusCompletionPopup.PlaceAndShow;
begin
  // Nur wachsen, nie schrumpfen, solange die Sitzung läuft (#416).
  FSessionWidth := Max(FSessionWidth, MeasureWidth);
  PlaceAt(FSessionWidth, RowCount * RowHeight + 2);
end;

procedure TArgusCompletionPopup.PlaceAt(AWidth, AHeight: Integer);
var
  Bounds, Area: TRect;
  Width, Height: Integer;
begin
  Width := AWidth;
  Height := AHeight;
  Area := WorkAreaAt(FAnchor.TopLeft);
  Bounds := TRect.Create(Point(FAnchor.Left, FAnchor.Bottom + 2), Width, Height);
  // Unten kein Platz: über die Zeile.
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, FAnchor.Top - Height - 2);
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Width), Bounds.Top);
  if Bounds.Top < Area.Top then
    Bounds.SetLocation(Bounds.Left, Area.Top);
  ShowAt(Bounds);
end;

procedure TArgusCompletionPopup.ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer);
begin
  FShowingEmpty := False;
  FItems := AItems;
  FOrder := AOrder;
  FSelected := ASelected;
  EnsureSelectedVisible;
  PlaceAndShow;
end;

procedure TArgusCompletionPopup.HideList;
begin
  HidePopup;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FTop := 0;
  FSessionWidth := 0;
  FShowingEmpty := False;
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
  Canvas.Font := Font;
  FSessionWidth := Max(FSessionWidth, Max(MulDiv(MinWidth, CurrentPPI, 96),
    Canvas.TextWidth('Keine Treffer für ‚' + APrefix + '‘') + MulDiv(24, CurrentPPI, 96)));
  PlaceAt(FSessionWidth, 3 * RowHeight + 2);
end;

procedure TArgusCompletionPopup.PaintEmpty;
var
  Line: TRect;
  Gap: Integer;

  procedure DrawLine(AIndex: Integer; const AText: string; AColor: TColor);
  begin
    Line := Rect(Gap, 1 + AIndex * RowHeight, ClientWidth - Gap, 1 + (AIndex + 1) * RowHeight);
    Canvas.Font.Color := AColor;
    DrawText(Canvas.Handle, PChar(AText), -1, Line, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;

begin
  Gap := MulDiv(8, CurrentPPI, 96);
  Canvas.Brush.Style := bsClear;
  if FEmptyPrefix <> '' then
    DrawLine(0, 'Keine Treffer für ‚' + FEmptyPrefix + '‘', Colors.Text)
  else
    DrawLine(0, 'Keine Vorschläge an dieser Stelle', Colors.Text);
  if FEmptyPrefix <> '' then
    DrawLine(1, 'Rücktaste erweitert die Suche', Colors.SecondaryText);
  DrawLine(2, Format('0 von %d    Esc schließt', [FEmptyTotal]), Colors.SecondaryText);
  Canvas.Brush.Style := bsSolid;
end;

procedure TArgusCompletionPopup.DrawRow(ARow, APosition: Integer);
var
  Item: TArgusCompletionItem;
  Row, Badge, Text: TRect;
  Height, Gap: Integer;
  Selected: Boolean;
  Signature: string;
begin
  Item := FItems[FOrder[APosition]];
  Height := RowHeight;
  Gap := MulDiv(6, CurrentPPI, 96);
  Row := Rect(1, 1 + ARow * Height, ClientWidth - 1 - MulDiv(ScrollBarWidth, CurrentPPI, 96), 1 + (ARow + 1) * Height);
  Selected := APosition = FSelected;
  if Selected then
    Canvas.Brush.Color := Colors.SelectionBackground
  else
    Canvas.Brush.Color := Colors.Background;
  Canvas.FillRect(Row);
  // Kennbuchstabe der Art in einem Quadrat.
  Badge := Rect(Row.Left + Gap, Row.Top + 3, Row.Left + Gap + Height - 6, Row.Bottom - 3);
  Canvas.Brush.Color := Colors.Accent;
  Canvas.FillRect(Badge);
  Canvas.Font.Color := Colors.SelectionText;
  Text := Badge;
  DrawText(Canvas.Handle, PChar(KindLetter(Item.Kind)), -1, Text, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  // Name.
  Canvas.Brush.Style := bsClear;
  if Selected then
    Canvas.Font.Color := Colors.SelectionText
  else
    Canvas.Font.Color := Colors.Text;
  Text := Rect(Badge.Right + Gap, Row.Top, Row.Right - Gap, Row.Bottom);
  DrawText(Canvas.Handle, PChar(Item.Name), -1, Text, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  // Signatur grau, rechts daneben, gekürzt.
  Signature := Item.Signature;
  if Signature <> '' then
  begin
    Text.Left := Text.Left + Canvas.TextWidth(Item.Name) + Gap * 2;
    if not Selected then
      Canvas.Font.Color := Colors.SecondaryText;
    DrawText(Canvas.Handle, PChar(Signature), -1, Text,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TArgusCompletionPopup.DrawScrollBar;
var
  Track, Thumb: TRect;
  Total, Visible, ThumbHeight, ThumbTop: Integer;
begin
  Track := Rect(ClientWidth - 1 - MulDiv(ScrollBarWidth, CurrentPPI, 96), 1, ClientWidth - 1, ClientHeight - 1);
  Canvas.Brush.Color := Colors.Background;
  Canvas.FillRect(Track);
  Total := Length(FOrder);
  Visible := RowCount;
  if Total <= Visible then
    Exit;
  ThumbHeight := Max(MulDiv(12, CurrentPPI, 96), Track.Height * Visible div Total);
  ThumbTop := Track.Top + (Track.Height - ThumbHeight) * FTop div Max(1, Total - Visible);
  Thumb := Rect(Track.Left + 1, ThumbTop, Track.Right - 1, ThumbTop + ThumbHeight);
  Canvas.Brush.Color := Colors.SecondaryText;
  Canvas.FillRect(Thumb);
end;

procedure TArgusCompletionPopup.Paint;
var
  Row: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := Colors.Background;
  Canvas.FillRect(ClientRect);
  if FShowingEmpty then
  begin
    PaintEmpty;
    PaintBorder;
    Exit;
  end;
  for Row := 0 to RowCount - 1 do
    if FTop + Row < Length(FOrder) then
      DrawRow(Row, FTop + Row);
  DrawScrollBar;
  PaintBorder;
end;

procedure TArgusCompletionPopup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Position: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Position := RowAt(Y);
  if (Position >= 0) and Assigned(FOnSelect) then
    FOnSelect(Position);
end;

procedure TArgusCompletionPopup.DblClick;
begin
  inherited;
  if (FSelected >= 0) and Assigned(FOnAccept) then
    FOnAccept(FSelected);
end;

function TArgusCompletionPopup.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then
    FTop := Max(0, FTop - 3)
  else
    FTop := Min(Max(0, Length(FOrder) - FVisibleRows), FTop + 3);
  Invalidate;
end;

end.
