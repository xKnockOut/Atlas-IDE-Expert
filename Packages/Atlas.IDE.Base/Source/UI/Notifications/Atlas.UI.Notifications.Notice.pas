unit Atlas.UI.Notifications.Notice;

// Nicht modaler Hinweis mit Aktionen (zuerst für #512 „uses nachziehen“): ein
// kleines Fenster unten rechts im IDE-Fenster mit Überschrift (fett), Text
// (gedämpft, auch mehrzeilig) und einer Zeile Aktionen als Links, getrennt
// durch „ · “. Es nimmt dem Editor nie den Fokus (TAtlasPopupWindow) und
// verschwindet nach VisibleMs von selbst, solange die Maus nicht darüber
// steht; „×“ schließt sofort. Ein Klick auf eine Aktion schließt den Hinweis
// und meldet ihre Nummer an OnAction. Die Benachrichtigungszentrale (#601)
// bleibt der Ort zum Nachlesen; dieser Hinweis ist ihre eigene Einblendung
// für Quellen im Verhalten Show.

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
  Atlas.Core.Style.Color,
  Atlas.UI.Popup.Window;

type
  TAtlasNoticeWindow = class(TAtlasPopupWindow)
  public const
    VisibleMs = 20000;
    /// <summary>Abstand zum Rand des Bereichs, logische Pixel.</summary>
    Margin = 16;
  private
    FTitle: string;
    FText: string;
    FActions: TArray<string>;
    FActionRects: TArray<TRect>;
    FCloseRect: TRect;
    FHot: Integer;
    FTimer: TTimer;
    FOnAction: TProc<Integer>;
    procedure TimerTick(Sender: TObject);
    function Layout(ADraw: Boolean): TSize;
    /// <summary>Breite des Fensters: Überschrift mit „×“, längste Textzeile, Zeile der Aktionen.</summary>
    function MeasureWidth: Integer;
    /// <summary>AText an AX, AY in AColor, nur mit ADraw.</summary>
    procedure PutText(ADraw: Boolean; AX, AY: Integer; const AText: string; AColor: TAtlasColor);
    /// <summary>Zeile der Aktionen ab AX, AY; legt FActionRects an.</summary>
    procedure LayoutActions(ADraw: Boolean; AX, AY, ATextHeight: Integer);
    function HitTest(const APoint: TPoint): Integer;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt den Hinweis unten rechts in AArea (Bildschirm, etwa das IDE-Fenster).</summary>
    procedure ShowNotice(const ATitle, AText: string; const AActions: TArray<string>; const AArea: TRect);
    procedure Dismiss;
    /// <summary>Wie ein Klick auf Aktion AIndex; außerhalb der Aktionen ohne Wirkung.</summary>
    procedure ClickAction(AIndex: Integer);
    /// <summary>Fläche der Aktion AIndex im Fenster; leer, wenn es sie nicht gibt.</summary>
    function ActionRect(AIndex: Integer): TRect;
    function CloseRect: TRect;
    /// <summary>Lage für AWidth × AHeight unten rechts in AArea mit AMargin Abstand, ganz in AWorkArea.</summary>
    class function PlaceCorner(const AArea: TRect; AWidth, AHeight, AMargin: Integer;
      const AWorkArea: TRect): TRect; static;
    property Title: string read FTitle;
    property Text: string read FText;
    property Actions: TArray<string> read FActions;
    property Timer: TTimer read FTimer;
    property OnAction: TProc<Integer> read FOnAction write FOnAction;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Popup.Accessibility;

const
  Pad = 10;
  RowGap = 4;
  Separator = '  ·  ';
  CloseText = '×';
  /// <summary>HitTest: Schließen.</summary>
  HitClose = -2;
  /// <summary>HitTest: nichts.</summary>
  HitNone = -1;

{ TAtlasNoticeWindow }

constructor TAtlasNoticeWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Files;
  SetAccessible(UiaToolTipControlType, 'Atlas');
  FHot := HitNone;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := VisibleMs;
  FTimer.OnTimer := TimerTick;
end;

class function TAtlasNoticeWindow.PlaceCorner(const AArea: TRect; AWidth, AHeight, AMargin: Integer;
  const AWorkArea: TRect): TRect;
var
  mLeft, mTop, Right, Bottom: Integer;
begin
  Right := Min(AArea.Right, AWorkArea.Right) - AMargin;
  Bottom := Min(AArea.Bottom, AWorkArea.Bottom) - AMargin;
  mLeft := Max(Right - AWidth, AWorkArea.Left);
  mTop := Max(Bottom - AHeight, AWorkArea.Top);
  Result := Rect(mLeft, mTop, mLeft + AWidth, mTop + AHeight);
end;

function TAtlasNoticeWindow.MeasureWidth: Integer;
var
  mLine: string;
begin
  Canvas.Font.Style := [fsBold];
  Result := Scale(Pad) + Canvas.TextWidth(FTitle);
  Canvas.Font.Style := [];
  // „×“ rechts neben der Überschrift; die endgültige Lage folgt der Breite.
  Result := Result + Scale(Pad) * 2 + Canvas.TextWidth(CloseText);
  for mLine in FText.Split([sLineBreak]) do
  begin
    Result := Max(Result, Scale(Pad) + Canvas.TextWidth(mLine));
  end;
  if Length(FActions) > 0 then
  begin
    Result := Max(Result, Scale(Pad) + Canvas.TextWidth(string.Join(Separator, FActions)));
  end;
  Result := Result + Scale(Pad);
end;

procedure TAtlasNoticeWindow.PutText(ADraw: Boolean; AX, AY: Integer; const AText: string; AColor: TAtlasColor);
begin
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(AColor);
    Canvas.TextOut(AX, AY, AText);
  end;
end;

procedure TAtlasNoticeWindow.LayoutActions(ADraw: Boolean; AX, AY, ATextHeight: Integer);
var
  mIndex, mX: Integer;
begin
  mX := AX;
  for mIndex := 0 to High(FActions) do
  begin
    if mIndex > 0 then
    begin
      PutText(ADraw, mX, AY, Separator, Colors.Muted);
      Inc(mX, Canvas.TextWidth(Separator));
    end;
    FActionRects[mIndex] := Rect(mX, AY, mX + Canvas.TextWidth(FActions[mIndex]), AY + ATextHeight);
    if ADraw and (FHot = mIndex) then
    begin
      Canvas.Font.Style := [fsUnderline];
    end;
    PutText(ADraw, mX, AY, FActions[mIndex], Colors.Accent);
    Canvas.Font.Style := [];
    Inc(mX, Canvas.TextWidth(FActions[mIndex]));
  end;
end;

function TAtlasNoticeWindow.Layout(ADraw: Boolean): TSize;
var
  mX, mY, mTextHeight, mWidth: Integer;
  mLine: string;
  mCloseColor: TAtlasColor;
begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  mX := Scale(Pad);
  mY := Scale(Pad);
  mWidth := MeasureWidth;
  Canvas.Font.Style := [fsBold];
  PutText(ADraw, mX, mY, FTitle, Colors.Text);
  Canvas.Font.Style := [];
  FCloseRect := Rect(mWidth - Scale(Pad) - Canvas.TextWidth(CloseText), mY, mWidth - Scale(Pad), mY + mTextHeight);
  mCloseColor := Colors.Muted;
  if FHot = HitClose then
  begin
    mCloseColor := Colors.Text;
  end;
  PutText(ADraw, FCloseRect.Left, FCloseRect.Top, CloseText, mCloseColor);
  if FText <> '' then
  begin
    for mLine in FText.Split([sLineBreak]) do
    begin
      mY := mY + mTextHeight + Scale(RowGap);
      PutText(ADraw, mX, mY, mLine, Colors.Muted);
    end;
  end;
  SetLength(FActionRects, Length(FActions));
  if Length(FActions) > 0 then
  begin
    mY := mY + mTextHeight + Scale(RowGap) * 2;
    LayoutActions(ADraw, mX, mY, mTextHeight);
  end;
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth;
  Result.cy := mY + mTextHeight + Scale(Pad);
end;

procedure TAtlasNoticeWindow.ShowNotice(const ATitle, AText: string; const AActions: TArray<string>;
  const AArea: TRect);
var
  Size: TSize;
begin
  FTitle := ATitle;
  FText := AText;
  FActions := AActions;
  FHot := HitNone;
  HandleNeeded;
  Size := Layout(False);
  ShowAt(PlaceCorner(AArea, Size.cx, Size.cy, Scale(Margin), WorkAreaAt(AArea.BottomRight)));
  Announce(Trim(ATitle + ' ' + AText));
  FTimer.Enabled := False;
  FTimer.Interval := VisibleMs;
  FTimer.Enabled := True;
end;

procedure TAtlasNoticeWindow.Dismiss;
begin
  FTimer.Enabled := False;
  FHot := HitNone;
  HidePopup;
end;

procedure TAtlasNoticeWindow.ClickAction(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FActions)) then
  begin
    Exit;
  end;
  Dismiss;
  if Assigned(FOnAction) then
  begin
    FOnAction(AIndex);
  end;
end;

function TAtlasNoticeWindow.ActionRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FActionRects)) then
  begin
    Result := FActionRects[AIndex];
  end;
end;

function TAtlasNoticeWindow.CloseRect: TRect;
begin
  Result := FCloseRect;
end;

function TAtlasNoticeWindow.HitTest(const APoint: TPoint): Integer;
var
  Index: Integer;
begin
  Result := HitNone;
  if not FCloseRect.IsEmpty and PtInRect(FCloseRect, APoint) then
  begin
    Exit(HitClose);
  end;
  for Index := 0 to High(FActionRects) do
  begin
    if PtInRect(FActionRects[Index], APoint) then
    begin
      Exit(Index);
    end;
  end;
end;

procedure TAtlasNoticeWindow.TimerTick(Sender: TObject);
begin
  try
    // Wer auf den Hinweis zeigt, liest noch: noch einmal so lange.
    if IsShown and PtInRect(BoundsRect, Mouse.CursorPos) then
    begin
      Exit;
    end;
    Dismiss;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Files, E);
  end;
end;

procedure TAtlasNoticeWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasNoticeWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  Hit := HitTest(Point(X, Y));
  if Hit = HitClose then
  begin
    Dismiss;
  end
  else if Hit >= 0 then
  begin
    ClickAction(Hit);
  end;
end;

procedure TAtlasNoticeWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  inherited;
  Hit := HitTest(Point(X, Y));
  if Hit = HitNone then
  begin
    Cursor := crDefault;
  end
  else
  begin
    Cursor := crHandPoint;
  end;
  if Hit <> FHot then
  begin
    FHot := Hit;
    Invalidate;
  end;
end;

procedure TAtlasNoticeWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHot <> HitNone then
  begin
    FHot := HitNone;
    Invalidate;
  end;
end;

end.
