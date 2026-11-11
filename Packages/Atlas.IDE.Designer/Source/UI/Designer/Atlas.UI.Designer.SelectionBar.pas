unit Atlas.UI.Designer.SelectionBar;

// Fenster der Schnellleiste über einer Mehrfachauswahl im Designer (#735):
// schmale Leiste mit Knöpfen, gehört dem Hauptfenster der IDE und nimmt nie
// den Fokus (wie die Griffe TAtlasDesignerHandles), damit der Designer die
// Auswahl behält.
// - Knopf: Text (fett, kursiv), Zustand aus TAtlasBarState (an = gefüllt,
//   gemischt = halb gefüllt, None = grau und ohne Wirkung), optional ein
//   Farbstreifen unter dem Text und ein Trennstrich davor.
// - Tooltip je Knopf über den Hinweis der IDE.
// - Klick meldet OnClick mit dem Index und der linken unteren Ecke des
//   Knopfs auf dem Bildschirm (für ein Menü darunter).
// Inhalt und Lage setzt die IDE-Schicht.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Designer.SelectionBar;

type
  TAtlasBarButton = record
    Text: string;
    State: TAtlasBarState;
    Hint: string;
    Style: TFontStyles;
    /// <summary>Farbstreifen unter dem Text; clNone = keiner.</summary>
    Swatch: TColor;
    /// <summary>Trennstrich vor dem Knopf.</summary>
    Separated: Boolean;
    class function Create(const AText: string; AState: TAtlasBarState; const AHint: string): TAtlasBarButton; static;
  end;

  TAtlasSelectionBarWindow = class(TForm)
  private
    FColors: TAtlasColors;
    FButtons: TArray<TAtlasBarButton>;
    FRects: TArray<TRect>;
    FOwnerWindow: HWND;
    FShown: Boolean;
    FHot: Integer;
    FPressed: Integer;
    FOnClick: TProc<Integer, TPoint>;
    function SameButtons(const AButtons: TArray<TAtlasBarButton>): Boolean;
    procedure Layout;
    procedure PaintButton(AIndex: Integer);
    procedure SetHot(AIndex: Integer);
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateBar(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    function S(AValue: Integer): Integer;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Knöpfe setzen; neu gezeichnet wird nur bei Änderungen.</summary>
    procedure SetButtons(const AButtons: TArray<TAtlasBarButton>);
    /// <summary>Größe der Leiste für die gesetzten Knöpfe.</summary>
    function BarSize: TSize;
    /// <summary>Knopf unter dem Punkt (Client); -1 = keiner.</summary>
    function ButtonAt(AX, AY: Integer): Integer;
    /// <summary>An AScreen zeigen, ohne den Fokus zu nehmen.</summary>
    procedure ShowAt(const AScreen: TRect);
    procedure HideBar;
    /// <summary>Liegt der Mauszeiger über der gezeigten Leiste?</summary>
    function MouseOver: Boolean;
    property Shown: Boolean read FShown;
    property OnClick: TProc<Integer, TPoint> read FOnClick write FOnClick;
  end;

implementation

const
  cButtonHeight = 22;
  cMinButtonWidth = 22;
  cPadding = 3;
  cTextPadding = 8;
  cSeparatorWidth = 9;
  cSwatchHeight = 3;

{ TAtlasBarButton }

class function TAtlasBarButton.Create(const AText: string; AState: TAtlasBarState;
  const AHint: string): TAtlasBarButton;
begin
  Result.Text := AText;
  Result.State := AState;
  Result.Hint := AHint;
  Result.Style := [];
  Result.Swatch := clNone;
  Result.Separated := False;
end;

{ TAtlasSelectionBarWindow }

constructor TAtlasSelectionBarWindow.CreateBar(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  FColors := AColors;
  FHot := -1;
  FPressed := -1;
  BorderStyle := bsNone;
  DoubleBuffered := True;
  ShowHint := True;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
end;

procedure TAtlasSelectionBarWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
end;

procedure TAtlasSelectionBarWindow.WMMouseActivate(var Message: TWMMouseActivate);
begin
  // Knopf gedrückt: Fokus und Auswahl bleiben im Designer.
  Message.Result := MA_NOACTIVATE;
end;

procedure TAtlasSelectionBarWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  SetHot(-1);
end;

function TAtlasSelectionBarWindow.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

procedure TAtlasSelectionBarWindow.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

function TAtlasSelectionBarWindow.SameButtons(const AButtons: TArray<TAtlasBarButton>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AButtons) = Length(FButtons);
  for mIndex := 0 to High(AButtons) do
  begin
    Result := Result and (AButtons[mIndex].Text = FButtons[mIndex].Text) and
      (AButtons[mIndex].State = FButtons[mIndex].State) and (AButtons[mIndex].Hint = FButtons[mIndex].Hint) and
      (AButtons[mIndex].Swatch = FButtons[mIndex].Swatch) and (AButtons[mIndex].Style = FButtons[mIndex].Style) and
      (AButtons[mIndex].Separated = FButtons[mIndex].Separated);
  end;
end;

procedure TAtlasSelectionBarWindow.Layout;
var
  mIndex, mX, mWidth: Integer;
begin
  Canvas.Font.Assign(Font);
  SetLength(FRects, Length(FButtons));
  mX := S(cPadding);
  for mIndex := 0 to High(FButtons) do
  begin
    if FButtons[mIndex].Separated and (mIndex > 0) then
    begin
      Inc(mX, S(cSeparatorWidth));
    end;
    Canvas.Font.Style := FButtons[mIndex].Style;
    mWidth := Canvas.TextWidth(FButtons[mIndex].Text) + S(cTextPadding);
    if mWidth < S(cMinButtonWidth) then
    begin
      mWidth := S(cMinButtonWidth);
    end;
    FRects[mIndex] := Rect(mX, S(cPadding), mX + mWidth, S(cPadding) + S(cButtonHeight));
    Inc(mX, mWidth + S(1));
  end;
  Canvas.Font.Style := [];
end;

procedure TAtlasSelectionBarWindow.SetButtons(const AButtons: TArray<TAtlasBarButton>);
begin
  if SameButtons(AButtons) then
  begin
    Exit;
  end;
  FButtons := Copy(AButtons);
  Layout;
  if (FHot >= 0) and (FHot <= High(FButtons)) then
  begin
    Hint := FButtons[FHot].Hint;
  end;
  Invalidate;
end;

function TAtlasSelectionBarWindow.BarSize: TSize;
begin
  Result.cx := S(cPadding) * 2;
  if Length(FRects) > 0 then
  begin
    Result.cx := FRects[High(FRects)].Right + S(cPadding);
  end;
  Result.cy := S(cButtonHeight) + S(cPadding) * 2;
end;

function TAtlasSelectionBarWindow.ButtonAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRects) do
  begin
    if FRects[mIndex].Contains(Point(AX, AY)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasSelectionBarWindow.PaintButton(AIndex: Integer);
var
  mButton: TAtlasBarButton;
  mRect, mHalf, mText: TRect;
begin
  mButton := FButtons[AIndex];
  mRect := FRects[AIndex];
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Color := TColor(FColors.Line);
  Canvas.Brush.Color := TColor(FColors.Surface);
  if mButton.State = TAtlasBarState.On then
  begin
    Canvas.Brush.Color := TColor(FColors.Accent);
  end
  else if mButton.State = TAtlasBarState.Mixed then
  begin
    Canvas.Brush.Color := TColor(FColors.AccentSoft);
  end;
  if (AIndex = FHot) and (mButton.State <> TAtlasBarState.None) then
  begin
    Canvas.Pen.Color := TColor(FColors.Accent);
  end;
  Canvas.Rectangle(mRect);
  if mButton.State = TAtlasBarState.Mixed then
  begin
    // Halb gefüllt: untere Hälfte in der Akzentfarbe.
    mHalf := Rect(mRect.Left + 1, mRect.Top + mRect.Height div 2, mRect.Right - 1, mRect.Bottom - 1);
    Canvas.Brush.Color := TColor(FColors.Accent);
    Canvas.FillRect(mHalf);
  end;
  mText := mRect;
  if mButton.Swatch <> clNone then
  begin
    Canvas.Brush.Color := mButton.Swatch;
    Canvas.FillRect(Rect(mRect.Left + S(4), mRect.Bottom - S(cSwatchHeight) - S(2), mRect.Right - S(4),
      mRect.Bottom - S(2)));
    mText.Bottom := mText.Bottom - S(cSwatchHeight);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := mButton.Style;
  Canvas.Font.Color := TColor(FColors.Text);
  if mButton.State = TAtlasBarState.On then
  begin
    Canvas.Font.Color := TColor(FColors.Surface);
  end
  else if mButton.State = TAtlasBarState.None then
  begin
    Canvas.Font.Color := TColor(FColors.Muted);
  end;
  DrawText(Canvas.Handle, PChar(mButton.Text), -1, mText, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasSelectionBarWindow.Paint;
var
  mIndex, mX: Integer;
begin
  Canvas.Font.Assign(Font);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(FColors.Surface);
  Canvas.Pen.Color := TColor(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  for mIndex := 0 to High(FButtons) do
  begin
    if FButtons[mIndex].Separated and (mIndex > 0) then
    begin
      mX := FRects[mIndex].Left - S(cSeparatorWidth) div 2 - 1;
      Canvas.Pen.Color := TColor(FColors.Line);
      Canvas.MoveTo(mX, FRects[mIndex].Top + S(3));
      Canvas.LineTo(mX, FRects[mIndex].Bottom - S(3));
    end;
    PaintButton(mIndex);
  end;
end;

procedure TAtlasSelectionBarWindow.SetHot(AIndex: Integer);
begin
  if AIndex = FHot then
  begin
    Exit;
  end;
  FHot := AIndex;
  Application.CancelHint;
  Hint := '';
  if AIndex >= 0 then
  begin
    Hint := FButtons[AIndex].Hint;
  end;
  Invalidate;
end;

procedure TAtlasSelectionBarWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  FPressed := -1;
  if Button = mbLeft then
  begin
    FPressed := ButtonAt(X, Y);
  end;
end;

procedure TAtlasSelectionBarWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  SetHot(ButtonAt(X, Y));
end;

procedure TAtlasSelectionBarWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited;
  mIndex := ButtonAt(X, Y);
  if (Button <> mbLeft) or (mIndex < 0) or (mIndex <> FPressed) then
  begin
    FPressed := -1;
    Exit;
  end;
  FPressed := -1;
  if (FButtons[mIndex].State <> TAtlasBarState.None) and Assigned(FOnClick) then
  begin
    Application.CancelHint;
    FOnClick(mIndex, ClientToScreen(Point(FRects[mIndex].Left, FRects[mIndex].Bottom)));
  end;
end;

procedure TAtlasSelectionBarWindow.ShowAt(const AScreen: TRect);
begin
  if AScreen.IsEmpty then
  begin
    HideBar;
    Exit;
  end;
  HandleNeeded;
  if not FShown or (BoundsRect <> AScreen) then
  begin
    SetWindowPos(Handle, HWND_TOP, AScreen.Left, AScreen.Top, AScreen.Width, AScreen.Height,
      SWP_NOACTIVATE or SWP_SHOWWINDOW);
  end;
  FShown := True;
end;

procedure TAtlasSelectionBarWindow.HideBar;
begin
  if FShown and HandleAllocated then
  begin
    Application.CancelHint;
    ShowWindow(Handle, SW_HIDE);
  end;
  FShown := False;
  FHot := -1;
  FPressed := -1;
end;

function TAtlasSelectionBarWindow.MouseOver: Boolean;
var
  mPoint: TPoint;
begin
  Result := FShown and HandleAllocated and GetCursorPos(mPoint) and PtInRect(BoundsRect, mPoint);
end;

end.
