unit Atlas.UI.Designer.MeasureOverlay;

// Maßlinien über dem Designer (#605): Linien mit Endstrichen und einer Marke
// mit dem Abstand in Pixeln; gleiche Abstände in der Akzentfarbe, die übrigen
// in der Fehlerfarbe (rot wie die Maßlinien gängiger Entwurfswerkzeuge), dazu
// freie Marken (Breite × Höhe). Durchsichtiges Fenster wie die Umrisse
// (TAtlasDesignerOutlines): gehört dem Hauptfenster der IDE, nimmt nie den
// Fokus, alle Klicks gehen durch (WS_EX_TRANSPARENT).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette;

type
  TAtlasMeasureMark = record
    /// <summary>Linie von FromPoint nach ToPoint im Client des Fensters; gleich = nur eine Marke an FromPoint.
    /// </summary>
    FromPoint: TPoint;
    ToPoint: TPoint;
    Caption: string;
    /// <summary>Hervorgehoben: gleicher Abstand bzw. gleiche Größe wie anderswo.</summary>
    Accent: Boolean;
    class function Line(const AFrom, ATo: TPoint; const ACaption: string; AAccent: Boolean): TAtlasMeasureMark;
      static;
    class function Badge(const AAt: TPoint; const ACaption: string; AAccent: Boolean): TAtlasMeasureMark; static;
    function SameAs(const AOther: TAtlasMeasureMark): Boolean;
  end;

  TAtlasMeasureOverlay = class(TForm)
  private const
    cKeyColor = TColor($00FF00FF);
  private
    FColors: TAtlasColors;
    FMarks: TArray<TAtlasMeasureMark>;
    FOwnerWindow: HWND;
    function S(AValue: Integer): Integer;
    procedure DrawLine(const AMark: TAtlasMeasureMark);
    procedure DrawBadge(const AAt: TPoint; const ACaption: string; AColor: TColor);
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateOverlay(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    /// <summary>Marken über AScreen (Bildschirm) zeigen, ohne den Fokus zu nehmen; gleiche Marken an gleicher
    /// Stelle zeichnen nicht neu.</summary>
    procedure ShowMarks(const AScreen: TRect; const AMarks: TArray<TAtlasMeasureMark>);
    procedure HideMarks;
    procedure ApplyColors(const AColors: TAtlasColors);
    function Shown: Boolean;
    property Marks: TArray<TAtlasMeasureMark> read FMarks;
  end;

implementation

{ TAtlasMeasureMark }

class function TAtlasMeasureMark.Line(const AFrom, ATo: TPoint; const ACaption: string;
  AAccent: Boolean): TAtlasMeasureMark;
begin
  Result.FromPoint := AFrom;
  Result.ToPoint := ATo;
  Result.Caption := ACaption;
  Result.Accent := AAccent;
end;

class function TAtlasMeasureMark.Badge(const AAt: TPoint; const ACaption: string;
  AAccent: Boolean): TAtlasMeasureMark;
begin
  Result := Line(AAt, AAt, ACaption, AAccent);
end;

function TAtlasMeasureMark.SameAs(const AOther: TAtlasMeasureMark): Boolean;
begin
  Result := (FromPoint = AOther.FromPoint) and (ToPoint = AOther.ToPoint) and (Caption = AOther.Caption) and
    (Accent = AOther.Accent);
end;

function SameMarks(const A, B: TArray<TAtlasMeasureMark>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex < Length(A)) do
  begin
    Result := A[mIndex].SameAs(B[mIndex]);
    Inc(mIndex);
  end;
end;

{ TAtlasMeasureOverlay }

constructor TAtlasMeasureOverlay.CreateOverlay(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  FColors := AColors;
  BorderStyle := bsNone;
  Color := cKeyColor;
  TransparentColor := True;
  TransparentColorValue := cKeyColor;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Size := 8;
end;

procedure TAtlasMeasureOverlay.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW or WS_EX_TRANSPARENT;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
end;

procedure TAtlasMeasureOverlay.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

function TAtlasMeasureOverlay.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

/// <summary>Marke mit dem Text auf einer Fläche in AColor, mittig an AAt.</summary>
procedure TAtlasMeasureOverlay.DrawBadge(const AAt: TPoint; const ACaption: string; AColor: TColor);
var
  mSize: TSize;
  mBox: TRect;
begin
  mSize := Canvas.TextExtent(ACaption);
  mBox := Rect(AAt.X - mSize.cx div 2 - S(3), AAt.Y - mSize.cy div 2 - S(1), AAt.X + (mSize.cx + 1) div 2 + S(3),
    AAt.Y + (mSize.cy + 1) div 2 + S(1));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := AColor;
  Canvas.Pen.Color := AColor;
  Canvas.RoundRect(mBox.Left, mBox.Top, mBox.Right, mBox.Bottom, S(4), S(4));
  Canvas.Font.Color := clWhite;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(mBox.Left + S(3), mBox.Top + S(1), ACaption);
end;

procedure TAtlasMeasureOverlay.DrawLine(const AMark: TAtlasMeasureMark);
var
  mColor: TColor;
  mTick: Integer;
begin
  mColor := TColor(FColors.Error);
  if AMark.Accent then
  begin
    mColor := TColor(FColors.Accent);
  end;
  if AMark.FromPoint <> AMark.ToPoint then
  begin
    mTick := S(4);
    Canvas.Pen.Color := mColor;
    Canvas.Pen.Width := 1;
    Canvas.MoveTo(AMark.FromPoint.X, AMark.FromPoint.Y);
    Canvas.LineTo(AMark.ToPoint.X, AMark.ToPoint.Y);
    // Endstriche quer zur Linie.
    if AMark.FromPoint.Y = AMark.ToPoint.Y then
    begin
      Canvas.MoveTo(AMark.FromPoint.X, AMark.FromPoint.Y - mTick);
      Canvas.LineTo(AMark.FromPoint.X, AMark.FromPoint.Y + mTick + 1);
      Canvas.MoveTo(AMark.ToPoint.X, AMark.ToPoint.Y - mTick);
      Canvas.LineTo(AMark.ToPoint.X, AMark.ToPoint.Y + mTick + 1);
    end
    else
    begin
      Canvas.MoveTo(AMark.FromPoint.X - mTick, AMark.FromPoint.Y);
      Canvas.LineTo(AMark.FromPoint.X + mTick + 1, AMark.FromPoint.Y);
      Canvas.MoveTo(AMark.ToPoint.X - mTick, AMark.ToPoint.Y);
      Canvas.LineTo(AMark.ToPoint.X + mTick + 1, AMark.ToPoint.Y);
    end;
  end;
  if AMark.Caption <> '' then
  begin
    DrawBadge(Point((AMark.FromPoint.X + AMark.ToPoint.X) div 2, (AMark.FromPoint.Y + AMark.ToPoint.Y) div 2),
      AMark.Caption, mColor);
  end;
end;

procedure TAtlasMeasureOverlay.Paint;
var
  mMark: TAtlasMeasureMark;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := cKeyColor;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  for mMark in FMarks do
  begin
    DrawLine(mMark);
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasMeasureOverlay.ShowMarks(const AScreen: TRect; const AMarks: TArray<TAtlasMeasureMark>);
begin
  if AScreen.IsEmpty or (Length(AMarks) = 0) then
  begin
    HideMarks;
    Exit;
  end;
  if Shown and (BoundsRect = AScreen) and SameMarks(FMarks, AMarks) then
  begin
    Exit;
  end;
  FMarks := AMarks;
  HandleNeeded;
  SetWindowPos(Handle, HWND_TOP, AScreen.Left, AScreen.Top, AScreen.Width, AScreen.Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  Invalidate;
end;

procedure TAtlasMeasureOverlay.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

function TAtlasMeasureOverlay.Shown: Boolean;
begin
  Result := HandleAllocated and IsWindowVisible(Handle);
end;

procedure TAtlasMeasureOverlay.HideMarks;
begin
  FMarks := nil;
  if HandleAllocated then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
end;

end.
