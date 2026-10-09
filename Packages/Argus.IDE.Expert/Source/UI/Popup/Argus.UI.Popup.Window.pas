unit Argus.UI.Popup.Window;

// Basis für Popup, Parameter-Hint und Tooltip von Argus (#410): eigenes,
// selbst gezeichnetes Fenster, das dem Editor nie den Fokus nimmt. Caret, IME
// und Undo bleiben so beim Editor.
//   - WS_POPUP mit WS_EX_NOACTIVATE und WS_EX_TOOLWINDOW, Besitzer ist das
//     Hauptfenster der IDE; Schatten über CS_DROPSHADOW.
//   - WM_MOUSEACTIVATE liefert MA_NOACTIVATE: Klicks wählen, ohne zu aktivieren.
//   - Zeigen über SetWindowPos mit SWP_NOACTIVATE (wie THintWindow), nicht über Visible.
// Aussehen nach dem Entwurf (#411): Farben aus TArgusColors, Rahmen in
// Akzentfarbe, abgerundete Ecken (ab Windows 11 vom Fenstermanager mit
// Kantenglättung, sonst über eine Fensterregion). Code (Namen, Signaturen)
// steht in der Editorschrift (Font), Beschriftungen in der UI-Schrift (UIFont).
// Tasten bekommt das Fenster nie; der Editor leitet sie über den Tastatur-Hook
// weiter (Argus.IDE).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Argus.Core.Style.Color,
  Argus.Core.Style.Palette;

type
  TArgusPopupWindow = class(TCustomControl)
  private
    FColors: TArgusColors;
    FUIFont: TFont;
    FBorderColor: TArgusColor;
    FSystemCorners: Boolean;
    /// <summary>CreateWnd hat entschieden, wer die Ecken rundet; vorher keine Region setzen.</summary>
    FCornersKnown: Boolean;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure SetColors(const AValue: TArgusColors);
    procedure SetBorderColor(AValue: TArgusColor);
    procedure UpdateCorners;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Resize; override;
    /// <summary>Rahmen in BorderColor, sofern nicht der Fenstermanager ihn zeichnet.</summary>
    procedure PaintBorder;
    /// <summary>Logische Pixel (96 dpi) auf den Monitor des Fensters umrechnen.</summary>
    function Scale(AValue: Integer): Integer;
    /// <summary>Gefülltes Rechteck mit abgerundeten Ecken (ARadius logisch).</summary>
    procedure FillRounded(const ARect: TRect; AColor: TArgusColor; ARadius: Integer);
    /// <summary>Umrandetes Rechteck mit abgerundeten Ecken, innen AFill (clNone = durchsichtig).</summary>
    procedure FrameRounded(const ARect: TRect; ALine: TArgusColor; ARadius: Integer; AFill: TColor = clNone);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Zeigt das Fenster ohne Aktivierung an ABounds (Bildschirmkoordinaten).</summary>
    procedure ShowAt(const ABounds: TRect);
    procedure HidePopup;
    function IsShown: Boolean;
    /// <summary>Arbeitsbereich des Monitors, auf dem APoint liegt.</summary>
    class function WorkAreaAt(const APoint: TPoint): TRect; static;
    /// <summary>Farben passend zum aktiven VCL-Stil (in der IDE deren Thema).</summary>
    class function StyleColors: TArgusColors; static;
    property Colors: TArgusColors read FColors write SetColors;
    /// <summary>Rahmenfarbe; Standard Akzent, im Fehlerzustand des Hints Fehlerfarbe.</summary>
    property BorderColor: TArgusColor read FBorderColor write SetBorderColor;
    /// <summary>Schrift für Beschriftungen, folgt Font in der Größe.</summary>
    property UIFont: TFont read FUIFont;
    property Canvas;
    property Font;
  end;

/// <summary>TArgusColor als TColor.</summary>
function ToColor(AColor: TArgusColor): TColor;

implementation

uses
  Winapi.DwmApi,
  System.Math,
  Vcl.Forms,
  Vcl.Themes;

const
  // Windows 11 (ab Build 22000); in älteren Winapi.DwmApi nicht deklariert.
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
  DWMWA_BORDER_COLOR = 34;
  DWMWCP_ROUNDSMALL = 3;
  CornerRadius = 6;

function ToColor(AColor: TArgusColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TArgusPopupWindow }

constructor TArgusPopupWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Visible := False;
  FUIFont := TFont.Create;
  FColors := StyleColors;
  FBorderColor := FColors.Accent;
  Perform(CM_FONTCHANGED, 0, 0);
end;

destructor TArgusPopupWindow.Destroy;
begin
  FUIFont.Free;
  inherited Destroy;
end;

class function TArgusPopupWindow.StyleColors: TArgusColors;
begin
  Result := TArgusColors.ForBackground(TArgusColor(ColorToRGB(StyleServices.GetSystemColor(clWindow))));
end;

function TArgusPopupWindow.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

procedure TArgusPopupWindow.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := WS_POPUP;
  Params.ExStyle := WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW or WS_EX_TOPMOST;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW or CS_SAVEBITS;
  // Besitzer: Hauptfenster der IDE, damit das Popup mit ihr minimiert wird und über ihr bleibt.
  if Application.MainFormHandle <> 0 then
    Params.WndParent := Application.MainFormHandle
  else
    Params.WndParent := Application.Handle;
end;

procedure TArgusPopupWindow.CreateWnd;
var
  Preference: DWORD;
begin
  inherited CreateWnd;
  // Windows 11: runde Ecken mit Kantenglättung und Rahmen vom Fenstermanager.
  Preference := DWMWCP_ROUNDSMALL;
  FSystemCorners := Succeeded(DwmSetWindowAttribute(Handle, DWMWA_WINDOW_CORNER_PREFERENCE, @Preference,
    SizeOf(Preference)));
  FCornersKnown := True;
  UpdateCorners;
end;

procedure TArgusPopupWindow.DestroyWnd;
begin
  FCornersKnown := False;
  inherited DestroyWnd;
end;

procedure TArgusPopupWindow.UpdateCorners;
var
  Border: DWORD;
begin
  // Schon während inherited CreateWnd kommt WM_SIZE; eine Region mit der Größe von dann bliebe sonst stehen.
  if not HandleAllocated or not FCornersKnown then
    Exit;
  if FSystemCorners then
  begin
    Border := DWORD(FBorderColor);
    DwmSetWindowAttribute(Handle, DWMWA_BORDER_COLOR, @Border, SizeOf(Border));
  end
  else
    // Ältere Windows-Versionen: Region mit runden Ecken; das Fenster übernimmt sie.
    SetWindowRgn(Handle, CreateRoundRectRgn(0, 0, Width + 1, Height + 1, Scale(2 * CornerRadius),
      Scale(2 * CornerRadius)), IsWindowVisible(Handle));
end;

procedure TArgusPopupWindow.Resize;
begin
  inherited Resize;
  if not FSystemCorners then
    UpdateCorners;
end;

procedure TArgusPopupWindow.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

procedure TArgusPopupWindow.WMNCHitTest(var Message: TWMNCHitTest);
begin
  Message.Result := HTCLIENT;
end;

procedure TArgusPopupWindow.CMFontChanged(var Message: TMessage);
begin
  inherited;
  if FUIFont = nil then
    Exit;
  // UI-Schrift der IDE, eine Stufe kleiner als die Editorschrift (Entwurf: 12 zu 13 px).
  FUIFont.Name := Screen.MessageFont.Name;
  FUIFont.Size := Max(8, Font.Size - 1);
  FUIFont.Charset := Font.Charset;
end;

procedure TArgusPopupWindow.SetColors(const AValue: TArgusColors);
begin
  FColors := AValue;
  FBorderColor := FColors.Accent;
  UpdateCorners;
  Invalidate;
end;

procedure TArgusPopupWindow.SetBorderColor(AValue: TArgusColor);
begin
  if FBorderColor = AValue then
    Exit;
  FBorderColor := AValue;
  UpdateCorners;
  Invalidate;
end;

procedure TArgusPopupWindow.FillRounded(const ARect: TRect; AColor: TArgusColor; ARadius: Integer);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(AColor);
  Canvas.Pen.Style := psClear;
  // Bei psClear zeichnet RoundRect ein Pixel kleiner; deshalb +1.
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right + 1, ARect.Bottom + 1, Scale(2 * ARadius),
    Scale(2 * ARadius));
  Canvas.Pen.Style := psSolid;
end;

procedure TArgusPopupWindow.FrameRounded(const ARect: TRect; ALine: TArgusColor; ARadius: Integer;
  AFill: TColor);
begin
  if AFill = clNone then
    Canvas.Brush.Style := bsClear
  else
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := AFill;
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(ALine);
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Scale(2 * ARadius), Scale(2 * ARadius));
  Canvas.Brush.Style := bsSolid;
end;

procedure TArgusPopupWindow.PaintBorder;
begin
  // Unter Windows 11 zeichnet der Fenstermanager den Rahmen (DWMWA_BORDER_COLOR).
  if FSystemCorners then
    Exit;
  FrameRounded(ClientRect, FBorderColor, CornerRadius);
end;

procedure TArgusPopupWindow.ShowAt(const ABounds: TRect);
begin
  HandleNeeded;
  // Erst Größe, dann ohne Aktivierung zeigen; Visible bleibt False wie bei THintWindow.
  SetBounds(ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height);
  SetWindowPos(Handle, HWND_TOPMOST, ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  Invalidate;
end;

procedure TArgusPopupWindow.HidePopup;
begin
  if HandleAllocated and IsWindowVisible(Handle) then
    ShowWindow(Handle, SW_HIDE);
end;

function TArgusPopupWindow.IsShown: Boolean;
begin
  Result := HandleAllocated and IsWindowVisible(Handle);
end;

class function TArgusPopupWindow.WorkAreaAt(const APoint: TPoint): TRect;
var
  Monitor: TMonitor;
begin
  Monitor := Screen.MonitorFromPoint(APoint, mdNearest);
  if Monitor <> nil then
    Result := Monitor.WorkareaRect
  else
    Result := Screen.WorkAreaRect;
end;

end.
