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
  Left, Top, Right, Bottom: Integer;
begin
  Right := Min(AArea.Right, AWorkArea.Right) - AMargin;
  Bottom := Min(AArea.Bottom, AWorkArea.Bottom) - AMargin;
  Left := Max(Right - AWidth, AWorkArea.Left);
  Top := Max(Bottom - AHeight, AWorkArea.Top);
  Result := Rect(Left, Top, Left + AWidth, Top + AHeight);
end;

function TAtlasNoticeWindow.Layout(ADraw: Boolean): TSize;
var
  X, Y, TextHeight, Width, Index: Integer;
  Line: string;
begin
  Canvas.Font := UIFont;
  TextHeight := Canvas.TextHeight('Wg');
  if ADraw then
    Canvas.Brush.Style := bsClear;
  X := Scale(Pad);
  Y := Scale(Pad);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, FTitle);
  end;
  Width := X + Canvas.TextWidth(FTitle);
  Canvas.Font.Style := [];
  // „×“ rechts neben der Überschrift; die endgültige Lage folgt der Breite.
  Width := Width + Scale(Pad) * 2 + Canvas.TextWidth(CloseText);
  for Line in FText.Split([sLineBreak]) do
    Width := Max(Width, Scale(Pad) + Canvas.TextWidth(Line));
  if Length(FActions) > 0 then
    Width := Max(Width, Scale(Pad) + Canvas.TextWidth(string.Join(Separator, FActions)));
  Width := Width + Scale(Pad);
  FCloseRect := Rect(Width - Scale(Pad) - Canvas.TextWidth(CloseText), Y, Width - Scale(Pad), Y + TextHeight);
  if ADraw then
  begin
    if FHot = HitClose then
      Canvas.Font.Color := ToColor(Colors.Text)
    else
      Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(FCloseRect.Left, FCloseRect.Top, CloseText);
  end;
  if FText <> '' then
    for Line in FText.Split([sLineBreak]) do
    begin
      Y := Y + TextHeight + Scale(RowGap);
      if ADraw then
      begin
        Canvas.Font.Color := ToColor(Colors.Muted);
        Canvas.TextOut(X, Y, Line);
      end;
    end;
  SetLength(FActionRects, Length(FActions));
  if Length(FActions) > 0 then
  begin
    Y := Y + TextHeight + Scale(RowGap) * 2;
    for Index := 0 to High(FActions) do
    begin
      if Index > 0 then
      begin
        if ADraw then
        begin
          Canvas.Font.Color := ToColor(Colors.Muted);
          Canvas.TextOut(X, Y, Separator);
        end;
        Inc(X, Canvas.TextWidth(Separator));
      end;
      FActionRects[Index] := Rect(X, Y, X + Canvas.TextWidth(FActions[Index]), Y + TextHeight);
      if ADraw then
      begin
        if FHot = Index then
          Canvas.Font.Style := [fsUnderline];
        Canvas.Font.Color := ToColor(Colors.Accent);
        Canvas.TextOut(X, Y, FActions[Index]);
        Canvas.Font.Style := [];
      end;
      Inc(X, Canvas.TextWidth(FActions[Index]));
    end;
  end;
  if ADraw then
    Canvas.Brush.Style := bsSolid;
  Result.cx := Width;
  Result.cy := Y + TextHeight + Scale(Pad);
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
    Exit;
  Dismiss;
  if Assigned(FOnAction) then
    FOnAction(AIndex);
end;

function TAtlasNoticeWindow.ActionRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FActionRects)) then
    Result := FActionRects[AIndex];
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
    Exit(HitClose);
  for Index := 0 to High(FActionRects) do
    if PtInRect(FActionRects[Index], APoint) then
      Exit(Index);
end;

procedure TAtlasNoticeWindow.TimerTick(Sender: TObject);
begin
  try
    // Wer auf den Hinweis zeigt, liest noch: noch einmal so lange.
    if IsShown and PtInRect(BoundsRect, Mouse.CursorPos) then
      Exit;
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
    Exit;
  Hit := HitTest(Point(X, Y));
  if Hit = HitClose then
    Dismiss
  else if Hit >= 0 then
    ClickAction(Hit);
end;

procedure TAtlasNoticeWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  inherited;
  Hit := HitTest(Point(X, Y));
  if Hit = HitNone then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
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
