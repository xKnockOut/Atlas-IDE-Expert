unit Atlas.UI.Designer.Handles;

// Griffe über dem Designer (#734 Abstandsgriffe, #737 gemeinsame
// Größengriffe): durchsichtiges Fenster über dem Elternelement wie die
// Tab-Reihenfolge (TAtlasTabOrderOverlay), gehört dem Hauptfenster der IDE
// und nimmt nie den Fokus. Durchsichtig über eine Schlüsselfarbe: Klicks
// neben die Griffe gehen an den Designer.
// - Griffe: Pillen mit Text (Akzentfarbe, abweichende gedämpft) oder kleine
//   Quadrate; je Griff ein Mauszeiger.
// - Rahmen: rot (ragt heraus) oder gestrichelt (übersprungen).
// - Beschriftung: ein Text an einem Punkt (etwa „180 → 260 px (3×)“).
// Ziehen: Druck auf einen Griff fängt die Maus; OnDrag meldet den Versatz
// zum Druckpunkt in Bildschirmpixeln, OnUp das Ende. Doppelklick meldet
// OnDoubleClick. Lage und Inhalt setzt die IDE-Schicht.

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
  Atlas.Core.Style.Palette;

type
{$SCOPEDENUMS ON}
  TAtlasHandleKind = (Pill, Square);
  TAtlasHandleFrameKind = (Bad, Dashed);
{$SCOPEDENUMS OFF}

  TAtlasHandle = record
    /// <summary>Lage im Client des Fensters.</summary>
    Bounds: TRect;
    Kind: TAtlasHandleKind;
    Text: string;
    /// <summary>Gedämpft statt in der Akzentfarbe.</summary>
    Muted: Boolean;
    Cursor: TCursor;
    /// <summary>Frei für den Aufrufer.</summary>
    Tag: Integer;
    class function Create(const ABounds: TRect; AKind: TAtlasHandleKind; const AText: string;
      ACursor: TCursor; ATag: Integer): TAtlasHandle; static;
  end;

  TAtlasHandleFrame = record
    Bounds: TRect;
    Kind: TAtlasHandleFrameKind;
    class function Create(const ABounds: TRect; AKind: TAtlasHandleFrameKind): TAtlasHandleFrame; static;
  end;

  TAtlasDesignerHandles = class(TForm)
  private const
    cKeyColor = TColor($00FF00FF);
  private
    FColors: TAtlasColors;
    FHandles: TArray<TAtlasHandle>;
    FFrames: TArray<TAtlasHandleFrame>;
    FLabel: string;
    FLabelAt: TPoint;
    FOwnerWindow: HWND;
    FShown: Boolean;
    FDragIndex: Integer;
    FDragStart: TPoint;
    FOnDown: TProc<Integer, TShiftState>;
    FOnDrag: TProc<TPoint, TShiftState>;
    FOnUp: TProc<TShiftState>;
    FOnDoubleClick: TProc<Integer, TShiftState>;
    function SameContent(const AHandles: TArray<TAtlasHandle>; const AFrames: TArray<TAtlasHandleFrame>;
      const ALabel: string): Boolean;
    procedure PaintFrames;
    procedure PaintHandle(const AHandle: TAtlasHandle);
    procedure PaintLabel;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateHandles(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    function S(AValue: Integer): Integer;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Inhalt setzen und neu zeichnen.</summary>
    procedure SetContent(const AHandles: TArray<TAtlasHandle>; const AFrames: TArray<TAtlasHandleFrame>;
      const ALabel: string; const ALabelAt: TPoint);
    /// <summary>Griff unter dem Punkt (Client); -1 = keiner.</summary>
    function HandleAt(AX, AY: Integer): Integer;
    /// <summary>Über AScreen zeigen, ohne den Fokus zu nehmen.</summary>
    procedure ShowAt(const AScreen: TRect);
    procedure HideHandles;
    /// <summary>Ziehen beenden ohne OnUp (Abbruch von außen).</summary>
    procedure CancelDrag;
    function Dragging: Boolean;
    property Handles: TArray<TAtlasHandle> read FHandles;
    property Frames: TArray<TAtlasHandleFrame> read FFrames;
    property Shown: Boolean read FShown;
    /// <summary>Druck auf Griff (Index) zu Beginn des Ziehens.</summary>
    property OnDown: TProc<Integer, TShiftState> read FOnDown write FOnDown;
    /// <summary>Versatz zum Druckpunkt (Bildschirmpixel) beim Ziehen.</summary>
    property OnDrag: TProc<TPoint, TShiftState> read FOnDrag write FOnDrag;
    property OnUp: TProc<TShiftState> read FOnUp write FOnUp;
    property OnDoubleClick: TProc<Integer, TShiftState> read FOnDoubleClick write FOnDoubleClick;
  end;

implementation

{ TAtlasHandle }

class function TAtlasHandle.Create(const ABounds: TRect; AKind: TAtlasHandleKind; const AText: string;
  ACursor: TCursor; ATag: Integer): TAtlasHandle;
begin
  Result.Bounds := ABounds;
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Muted := False;
  Result.Cursor := ACursor;
  Result.Tag := ATag;
end;

{ TAtlasHandleFrame }

class function TAtlasHandleFrame.Create(const ABounds: TRect; AKind: TAtlasHandleFrameKind): TAtlasHandleFrame;
begin
  Result.Bounds := ABounds;
  Result.Kind := AKind;
end;

{ TAtlasDesignerHandles }

constructor TAtlasDesignerHandles.CreateHandles(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  FColors := AColors;
  FDragIndex := -1;
  BorderStyle := bsNone;
  Color := cKeyColor;
  TransparentColor := True;
  TransparentColorValue := cKeyColor;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Size := 8;
  Font.Style := [fsBold];
end;

procedure TAtlasDesignerHandles.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
end;

procedure TAtlasDesignerHandles.WMMouseActivate(var Message: TWMMouseActivate);
begin
  // Griff gedrückt: Fokus bleibt im Designer.
  Message.Result := MA_NOACTIVATE;
end;

procedure TAtlasDesignerHandles.WMCaptureChanged(var Message: TMessage);
begin
  inherited;
  // Maus verloren (Fensterwechsel, Esc der IDE): wie Loslassen behandeln.
  if Dragging and (HWND(Message.LParam) <> Handle) then
  begin
    FDragIndex := -1;
    if Assigned(FOnUp) then
    begin
      FOnUp([]);
    end;
  end;
end;

function TAtlasDesignerHandles.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

procedure TAtlasDesignerHandles.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

function TAtlasDesignerHandles.SameContent(const AHandles: TArray<TAtlasHandle>;
  const AFrames: TArray<TAtlasHandleFrame>; const ALabel: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (Length(AHandles) = Length(FHandles)) and (Length(AFrames) = Length(FFrames)) and (ALabel = FLabel);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AHandles) do
  begin
    Result := Result and (AHandles[mIndex].Bounds = FHandles[mIndex].Bounds) and
      (AHandles[mIndex].Text = FHandles[mIndex].Text) and (AHandles[mIndex].Muted = FHandles[mIndex].Muted);
  end;
  for mIndex := 0 to High(AFrames) do
  begin
    Result := Result and (AFrames[mIndex].Bounds = FFrames[mIndex].Bounds) and
      (AFrames[mIndex].Kind = FFrames[mIndex].Kind);
  end;
end;

procedure TAtlasDesignerHandles.SetContent(const AHandles: TArray<TAtlasHandle>;
  const AFrames: TArray<TAtlasHandleFrame>; const ALabel: string; const ALabelAt: TPoint);
begin
  // Der Takt der Leiste setzt alle 200 ms denselben Inhalt: nur bei Änderungen neu zeichnen.
  if SameContent(AHandles, AFrames, ALabel) and (ALabelAt = FLabelAt) then
  begin
    Exit;
  end;
  FHandles := Copy(AHandles);
  FFrames := Copy(AFrames);
  FLabel := ALabel;
  FLabelAt := ALabelAt;
  Invalidate;
end;

function TAtlasDesignerHandles.HandleAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := High(FHandles) downto 0 do
  begin
    if FHandles[mIndex].Bounds.Contains(Point(AX, AY)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasDesignerHandles.Dragging: Boolean;
begin
  Result := FDragIndex >= 0;
end;

procedure TAtlasDesignerHandles.CancelDrag;
begin
  FDragIndex := -1;
  if MouseCapture then
  begin
    MouseCapture := False;
  end;
end;

procedure TAtlasDesignerHandles.PaintFrames;
var
  mFrame: TAtlasHandleFrame;
begin
  Canvas.Brush.Style := bsClear;
  for mFrame in FFrames do
  begin
    if mFrame.Kind = TAtlasHandleFrameKind.Bad then
    begin
      Canvas.Pen.Color := TColor(FColors.Error);
      Canvas.Pen.Style := psSolid;
      Canvas.Pen.Width := S(2);
    end
    else
    begin
      Canvas.Pen.Color := TColor(FColors.Accent);
      Canvas.Pen.Style := psDash;
      Canvas.Pen.Width := 1;
    end;
    Canvas.Rectangle(mFrame.Bounds);
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasDesignerHandles.PaintHandle(const AHandle: TAtlasHandle);
var
  mBack: TColor;
  mRect: TRect;
begin
  mBack := TColor(FColors.Accent);
  if AHandle.Muted then
  begin
    mBack := TColor(FColors.Muted);
  end;
  mRect := AHandle.Bounds;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := mBack;
  Canvas.Pen.Color := TColor(FColors.Surface);
  if AHandle.Kind = TAtlasHandleKind.Square then
  begin
    Canvas.Rectangle(mRect);
    Exit;
  end;
  Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, mRect.Height, mRect.Height);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := TColor(FColors.Surface);
  DrawText(Canvas.Handle, PChar(AHandle.Text), -1, mRect, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasDesignerHandles.PaintLabel;
var
  mSize: TSize;
  mRect: TRect;
begin
  if FLabel = '' then
  begin
    Exit;
  end;
  mSize := Canvas.TextExtent(FLabel);
  mRect := Rect(FLabelAt.X, FLabelAt.Y, FLabelAt.X + mSize.cx + S(10), FLabelAt.Y + mSize.cy + S(4));
  // Im Fenster halten.
  if mRect.Right > ClientWidth then
  begin
    mRect.Offset(ClientWidth - mRect.Right, 0);
  end;
  if mRect.Bottom > ClientHeight then
  begin
    mRect.Offset(0, ClientHeight - mRect.Bottom);
  end;
  Canvas.Brush.Color := TColor(FColors.Surface);
  Canvas.Pen.Color := TColor(FColors.Accent);
  Canvas.Rectangle(mRect);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := TColor(FColors.Text);
  DrawText(Canvas.Handle, PChar(FLabel), -1, mRect, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasDesignerHandles.Paint;
var
  mHandle: TAtlasHandle;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := cKeyColor;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  PaintFrames;
  for mHandle in FHandles do
  begin
    PaintHandle(mHandle);
  end;
  PaintLabel;
end;

procedure TAtlasDesignerHandles.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mIndex := HandleAt(X, Y);
  if mIndex < 0 then
  begin
    Exit;
  end;
  if ssDouble in Shift then
  begin
    CancelDrag;
    if Assigned(FOnDoubleClick) then
    begin
      FOnDoubleClick(mIndex, Shift);
    end;
    Exit;
  end;
  FDragIndex := mIndex;
  FDragStart := ClientToScreen(Point(X, Y));
  MouseCapture := True;
  if Assigned(FOnDown) then
  begin
    FOnDown(mIndex, Shift);
  end;
end;

procedure TAtlasDesignerHandles.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mPoint: TPoint;
begin
  inherited;
  if Dragging then
  begin
    mPoint := ClientToScreen(Point(X, Y));
    if Assigned(FOnDrag) then
    begin
      FOnDrag(Point(mPoint.X - FDragStart.X, mPoint.Y - FDragStart.Y), Shift);
    end;
    Exit;
  end;
  mIndex := HandleAt(X, Y);
  if mIndex >= 0 then
  begin
    Cursor := FHandles[mIndex].Cursor;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

procedure TAtlasDesignerHandles.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button <> mbLeft) or not Dragging then
  begin
    Exit;
  end;
  FDragIndex := -1;
  MouseCapture := False;
  if Assigned(FOnUp) then
  begin
    FOnUp(Shift);
  end;
end;

procedure TAtlasDesignerHandles.ShowAt(const AScreen: TRect);
begin
  if AScreen.IsEmpty then
  begin
    HideHandles;
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

procedure TAtlasDesignerHandles.HideHandles;
begin
  CancelDrag;
  if FShown and HandleAllocated then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
  FShown := False;
end;

end.
