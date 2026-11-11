unit Atlas.UI.Designer.Magnifier;

// Fenster der Lupe für den Designer (#743): schwebendes Werkzeugfenster mit
// frei wählbarer Größe (Vorgabe 240 × 180), gehört dem Hauptfenster der IDE
// und nimmt nie den Fokus, damit der Designer Tastatur und Auswahl behält.
// - Capture holt einen Bildschirmausschnitt über BitBlt mit CAPTUREBLT vom
//   Desktop; die Ansicht zeigt ihn pixelgenau vergrößert, ab 4× mit
//   Pixelraster, in der Mitte ein Fadenkreuz um das Pixel unter der Maus.
// - Kopf- und Fußzeile (Stufe und Koordinaten, Farbe und Komponente) sowie
//   Linien für Kanten setzt die IDE-Schicht.
// - Linksklick meldet OnCopy, Mausrad OnWheel, das Kontextmenü ist
//   PopupMenu, Schließen OnClosed.

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
  /// <summary>Kante in der Ansicht: senkrecht bei X = Position, sonst waagerecht bei Y.</summary>
  TAtlasMagnifierLine = record
    Vertical: Boolean;
    Position: Integer;
    /// <summary>Kante der Auswahl (Akzentfarbe), sonst eines Nachbarn.</summary>
    Selected: Boolean;
    class function Create(AVertical: Boolean; APosition: Integer; ASelected: Boolean): TAtlasMagnifierLine; static;
  end;

  TAtlasMagnifierWindow = class(TForm)
  private
    FColors: TAtlasColors;
    FOwnerWindow: HWND;
    FBitmap: TBitmap;
    FSource: TRect;
    FZoom: Integer;
    FGrid: Boolean;
    FHeader: string;
    FFooter: string;
    FLines: TArray<TAtlasMagnifierLine>;
    FOnCopy: TProc;
    FOnWheel: TProc<Integer>;
    FOnClosed: TProc;
    FShown: Boolean;
    FPlaced: Boolean;
    function BarHeight: Integer;
    procedure PaintView(const AView: TRect);
    procedure PaintCross(const AView: TRect);
    procedure PaintLines(const AView: TRect);
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure WMMouseWheel(var Message: TWMMouseWheel); message WM_MOUSEWHEEL;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateMagnifier(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    destructor Destroy; override;
    function S(AValue: Integer): Integer;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Größe der Ansicht ohne Kopf- und Fußzeile.</summary>
    function ViewSize: TSize;
    /// <summary>Bildschirmausschnitt ASource holen (Stufe AZoom, Raster AGrid).</summary>
    procedure Capture(const ASource: TRect; AZoom: Integer; AGrid: Boolean);
    /// <summary>Farbe ($RRGGBB) des Pixels APoint (Bildschirm) im geholten Ausschnitt; False außerhalb.</summary>
    function ColorAt(const APoint: TPoint; out ARgb: Cardinal): Boolean;
    procedure SetTexts(const AHeader, AFooter: string);
    procedure SetLines(const ALines: TArray<TAtlasMagnifierLine>);
    /// <summary>Zeigen, ohne den Fokus zu nehmen; beim ersten Mal rechts unten über AArea.</summary>
    procedure ShowNear(const AArea: TRect);
    procedure HideWindow;
    /// <summary>Liegt APoint (Bildschirm) über dem Fenster?</summary>
    function Contains(const APoint: TPoint): Boolean;
    property Shown: Boolean read FShown;
    property Source: TRect read FSource;
    property OnCopy: TProc read FOnCopy write FOnCopy;
    property OnWheel: TProc<Integer> read FOnWheel write FOnWheel;
    property OnClosed: TProc read FOnClosed write FOnClosed;
  end;

implementation

const
  // Fehlt in Delphis Winapi.Windows (überlagerte Fenster mit aufnehmen).
  CAPTUREBLT = $40000000;
  cDefaultWidth = 240;
  cDefaultHeight = 180;
  cBarHeight = 18;
  cMargin = 24;

{ TAtlasMagnifierLine }

class function TAtlasMagnifierLine.Create(AVertical: Boolean; APosition: Integer;
  ASelected: Boolean): TAtlasMagnifierLine;
begin
  Result.Vertical := AVertical;
  Result.Position := APosition;
  Result.Selected := ASelected;
end;

{ TAtlasMagnifierWindow }

constructor TAtlasMagnifierWindow.CreateMagnifier(AOwner: TComponent; AOwnerWindow: HWND;
  const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  FColors := AColors;
  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf24bit;
  FZoom := 4;
  BorderStyle := bsSizeToolWin;
  Position := poDesigned;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Size := 8;
  ClientWidth := S(cDefaultWidth);
  ClientHeight := S(cDefaultHeight) + 2 * BarHeight;
  Constraints.MinWidth := S(120);
  Constraints.MinHeight := S(100);
  OnClose := FormClose;
end;

destructor TAtlasMagnifierWindow.Destroy;
begin
  FBitmap.Free;
  inherited Destroy;
end;

procedure TAtlasMagnifierWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
end;

procedure TAtlasMagnifierWindow.WMMouseActivate(var Message: TWMMouseActivate);
begin
  // Klick in die Lupe: Fokus und Auswahl bleiben im Designer.
  Message.Result := MA_NOACTIVATE;
end;

procedure TAtlasMagnifierWindow.WMMouseWheel(var Message: TWMMouseWheel);
begin
  if Assigned(FOnWheel) then
  begin
    FOnWheel(Message.WheelDelta);
  end;
  Message.Result := 1;
end;

procedure TAtlasMagnifierWindow.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Gezeigt wird ohne Visible (kein Aktivieren): selbst ausblenden.
  Action := caNone;
  HideWindow;
  if Assigned(FOnClosed) then
  begin
    FOnClosed();
  end;
end;

function TAtlasMagnifierWindow.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

function TAtlasMagnifierWindow.BarHeight: Integer;
begin
  Result := S(cBarHeight);
end;

procedure TAtlasMagnifierWindow.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

function TAtlasMagnifierWindow.ViewSize: TSize;
begin
  Result.cx := ClientWidth;
  Result.cy := ClientHeight - 2 * BarHeight;
  if Result.cy < 1 then
  begin
    Result.cy := 1;
  end;
end;

procedure TAtlasMagnifierWindow.Capture(const ASource: TRect; AZoom: Integer; AGrid: Boolean);
var
  mScreen: HDC;
begin
  FSource := ASource;
  FZoom := AZoom;
  FGrid := AGrid;
  FBitmap.SetSize(ASource.Width, ASource.Height);
  mScreen := GetDC(0);
  try
    BitBlt(FBitmap.Canvas.Handle, 0, 0, ASource.Width, ASource.Height, mScreen, ASource.Left, ASource.Top,
      SRCCOPY or CAPTUREBLT);
  finally
    ReleaseDC(0, mScreen);
  end;
  Invalidate;
end;

function TAtlasMagnifierWindow.ColorAt(const APoint: TPoint; out ARgb: Cardinal): Boolean;
var
  mColor: TColor;
begin
  ARgb := 0;
  Result := FSource.Contains(APoint) and (FBitmap.Width > 0);
  if Result then
  begin
    mColor := FBitmap.Canvas.Pixels[APoint.X - FSource.Left, APoint.Y - FSource.Top];
    ARgb := (Cardinal(GetRValue(mColor)) shl 16) or (Cardinal(GetGValue(mColor)) shl 8) or GetBValue(mColor);
  end;
end;

procedure TAtlasMagnifierWindow.SetTexts(const AHeader, AFooter: string);
begin
  if (AHeader <> FHeader) or (AFooter <> FFooter) then
  begin
    FHeader := AHeader;
    FFooter := AFooter;
    Invalidate;
  end;
end;

procedure TAtlasMagnifierWindow.SetLines(const ALines: TArray<TAtlasMagnifierLine>);
begin
  FLines := Copy(ALines);
  Invalidate;
end;

procedure TAtlasMagnifierWindow.PaintView(const AView: TRect);
var
  mIndex, mPos: Integer;
begin
  if FBitmap.Width = 0 then
  begin
    Exit;
  end;
  // Pixel als Blöcke, ohne Glätten.
  SetStretchBltMode(Canvas.Handle, COLORONCOLOR);
  StretchBlt(Canvas.Handle, AView.Left, AView.Top, FBitmap.Width * FZoom, FBitmap.Height * FZoom,
    FBitmap.Canvas.Handle, 0, 0, FBitmap.Width, FBitmap.Height, SRCCOPY);
  if not FGrid or (FZoom < 4) then
  begin
    Exit;
  end;
  Canvas.Pen.Color := TColor(FColors.Line);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  for mIndex := 1 to FBitmap.Width - 1 do
  begin
    mPos := AView.Left + mIndex * FZoom;
    Canvas.MoveTo(mPos, AView.Top);
    Canvas.LineTo(mPos, AView.Bottom);
  end;
  for mIndex := 1 to FBitmap.Height - 1 do
  begin
    mPos := AView.Top + mIndex * FZoom;
    Canvas.MoveTo(AView.Left, mPos);
    Canvas.LineTo(AView.Right, mPos);
  end;
end;

procedure TAtlasMagnifierWindow.PaintLines(const AView: TRect);
var
  mLine: TAtlasMagnifierLine;
begin
  Canvas.Pen.Width := 1;
  Canvas.Pen.Style := psSolid;
  for mLine in FLines do
  begin
    if mLine.Selected then
    begin
      Canvas.Pen.Color := TColor(FColors.Accent);
    end
    else
    begin
      Canvas.Pen.Color := TColor(FColors.Warn);
    end;
    if mLine.Vertical then
    begin
      Canvas.MoveTo(AView.Left + mLine.Position, AView.Top);
      Canvas.LineTo(AView.Left + mLine.Position, AView.Bottom);
    end
    else
    begin
      Canvas.MoveTo(AView.Left, AView.Top + mLine.Position);
      Canvas.LineTo(AView.Right, AView.Top + mLine.Position);
    end;
  end;
end;

procedure TAtlasMagnifierWindow.PaintCross(const AView: TRect);
var
  mCell: TRect;
  mX, mY: Integer;
begin
  // Pixel in der Mitte des Ausschnitts (unter der Maus) umrahmen, Linien bis zum Rand.
  mX := AView.Left + (FBitmap.Width div 2) * FZoom;
  mY := AView.Top + (FBitmap.Height div 2) * FZoom;
  mCell := Rect(mX - 1, mY - 1, mX + FZoom + 1, mY + FZoom + 1);
  Canvas.Pen.Color := TColor(FColors.Error);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(mCell);
  Canvas.MoveTo(mX + FZoom div 2, AView.Top);
  Canvas.LineTo(mX + FZoom div 2, mCell.Top);
  Canvas.MoveTo(mX + FZoom div 2, mCell.Bottom);
  Canvas.LineTo(mX + FZoom div 2, AView.Bottom);
  Canvas.MoveTo(AView.Left, mY + FZoom div 2);
  Canvas.LineTo(mCell.Left, mY + FZoom div 2);
  Canvas.MoveTo(mCell.Right, mY + FZoom div 2);
  Canvas.LineTo(AView.Right, mY + FZoom div 2);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasMagnifierWindow.Paint;
var
  mView, mBar: TRect;
begin
  Canvas.Font.Assign(Font);
  mView := Rect(0, BarHeight, ClientWidth, ClientHeight - BarHeight);
  Canvas.Brush.Color := TColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  IntersectClipRect(Canvas.Handle, mView.Left, mView.Top, mView.Right, mView.Bottom);
  PaintView(mView);
  PaintLines(mView);
  PaintCross(mView);
  SelectClipRgn(Canvas.Handle, 0);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := TColor(FColors.Text);
  mBar := Rect(S(4), 0, ClientWidth - S(4), BarHeight);
  DrawText(Canvas.Handle, PChar(FHeader), -1, mBar, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  mBar := Rect(S(4), ClientHeight - BarHeight, ClientWidth - S(4), ClientHeight);
  DrawText(Canvas.Handle, PChar(FFooter), -1, mBar, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasMagnifierWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button = mbLeft) and Assigned(FOnCopy) then
  begin
    FOnCopy();
  end;
end;

procedure TAtlasMagnifierWindow.ShowNear(const AArea: TRect);
begin
  HandleNeeded;
  if FShown then
  begin
    Exit;
  end;
  if not FPlaced and not AArea.IsEmpty then
  begin
    // Beim ersten Zeigen unten rechts über dem Designer; danach bleibt die Lage des Benutzers.
    SetBounds(AArea.Right - Width - S(cMargin), AArea.Bottom - Height - S(cMargin), Width, Height);
    FPlaced := True;
  end;
  SetWindowPos(Handle, HWND_TOP, Left, Top, Width, Height, SWP_NOACTIVATE or SWP_SHOWWINDOW);
  FShown := True;
end;

procedure TAtlasMagnifierWindow.HideWindow;
begin
  if FShown and HandleAllocated then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
  FShown := False;
end;

function TAtlasMagnifierWindow.Contains(const APoint: TPoint): Boolean;
begin
  Result := FShown and HandleAllocated and PtInRect(BoundsRect, APoint);
end;

end.
