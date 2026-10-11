unit Atlas.UI.Popup.Window;

// Basis für Popup, Parameter-Hint und Tooltip von Atlas (#410): eigenes,
// selbst gezeichnetes Fenster, das dem Editor nie den Fokus nimmt. Caret, IME
// und Undo bleiben so beim Editor.
//   - WS_POPUP mit WS_EX_NOACTIVATE und WS_EX_TOOLWINDOW, Besitzer ist das
//     Hauptfenster der IDE; Schatten über CS_DROPSHADOW.
//   - WM_MOUSEACTIVATE liefert MA_NOACTIVATE: Klicks wählen, ohne zu aktivieren.
//   - Zeigen über SetWindowPos mit SWP_NOACTIVATE (wie THintWindow), nicht über Visible.
// Aussehen nach dem Entwurf (#411): Farben aus TAtlasColors, Rahmen in
// Akzentfarbe, abgerundete Ecken (ab Windows 11 vom Fenstermanager mit
// Kantenglättung, sonst über eine Fensterregion). Code (Namen, Signaturen)
// steht in der Editorschrift (Font), Beschriftungen in der UI-Schrift (UIFont).
// Maße (#412, #445): alle in logischen Pixeln (96 dpi), umgerechnet mit PPI =
// DPI des Monitors am Caret mal Zoom des Editors (SetScaling). So wachsen Schrift,
// Zeilen, Badges und Abstände gemeinsam.
// Barrierefreiheit (#447): Jedes Fenster ist ein UI-Automation-Element mit
// Rolle und Name; Announce lässt die Sprachausgabe einen Text vorlesen.
// Tasten bekommt das Fenster nie; der Editor leitet sie über den Tastatur-Hook
// weiter (Atlas.IDE).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Popup.Accessibility,
  Atlas.Core.Diagnostics.Guard;

type
  TAtlasPopupWindow = class(TCustomControl)
  private
    FColors: TAtlasColors;
    FUIFont: TFont;
    FBorderColor: TAtlasColor;
    FSystemCorners: Boolean;
    FPPI: Integer;
    /// <summary>CreateWnd hat entschieden, wer die Ecken rundet; vorher keine Region setzen.</summary>
    FCornersKnown: Boolean;
    FAccessible: IAtlasRawElementProvider;
    FAccessibleRole: Integer;
    FAccessibleName: string;
    FAnnounced: string;
    FGuardFeature: TAtlasFeature;
    procedure WMGetObject(var Message: TMessage); message WM_GETOBJECT;
    function Accessible: IAtlasRawElementProvider;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure SetColors(const AValue: TAtlasColors);
    procedure SetBorderColor(AValue: TAtlasColor);
    procedure UpdateCorners;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    /// <summary>Alle Nachrichten geschützt (#493): Zeichnen, Maus, Tasten des Fensters.</summary>
    procedure WndProc(var Message: TMessage); override;
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Resize; override;
    /// <summary>Rahmen in BorderColor, sofern nicht der Fenstermanager ihn zeichnet.</summary>
    procedure PaintBorder;
    /// <summary>Logische Pixel (96 dpi) auf den Monitor des Fensters umrechnen.</summary>
    function Scale(AValue: Integer): Integer;
    /// <summary>Gefülltes Rechteck mit abgerundeten Ecken (ARadius logisch).</summary>
    procedure FillRounded(const ARect: TRect; AColor: TAtlasColor; ARadius: Integer);
    /// <summary>Umrandetes Rechteck mit abgerundeten Ecken, innen AFill (clNone = durchsichtig).</summary>
    procedure FrameRounded(const ARect: TRect; ALine: TAtlasColor; ARadius: Integer; AFill: TColor = clNone);
    /// <summary>Rolle (UiaListControlType, UiaToolTipControlType) und Name für Screenreader.</summary>
    procedure SetAccessible(ARole: Integer; const AName: string);
    /// <summary>Feature, dem Fehler des Fensters angerechnet werden (Sicherung, #493).</summary>
    property GuardFeature: TAtlasFeature read FGuardFeature write FGuardFeature;
  public
    /// <summary>Lässt einen Screenreader AText vorlesen; derselbe Text zweimal hintereinander nur einmal.</summary>
    procedure Announce(const AText: string);
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Zeigt das Fenster ohne Aktivierung an ABounds (Bildschirmkoordinaten).</summary>
    procedure ShowAt(const ABounds: TRect);
    procedure HidePopup;
    function IsShown: Boolean;
    /// <summary>Arbeitsbereich des Monitors, auf dem APoint liegt.</summary>
    class function WorkAreaAt(const APoint: TPoint): TRect; static;
    /// <summary>Farben passend zum aktiven VCL-Stil (in der IDE deren Thema).</summary>
    class function StyleColors: TAtlasColors; static;
    property Colors: TAtlasColors read FColors write SetColors;
    /// <summary>Rahmenfarbe; Standard Akzent, im Fehlerzustand des Hints Fehlerfarbe.</summary>
    property BorderColor: TAtlasColor read FBorderColor write SetBorderColor;
    /// <summary>Wirksame Pixel je Zoll: Monitor-DPI mal Zoom; Schriften in AFontName/AFontSize (Punkt).</summary>
    procedure SetScaling(AMonitorPPI: Integer; AZoom: Double; const AFontName: string; AFontSize: Integer);
    /// <summary>Pixel je Zoll des Monitors, auf dem APoint liegt.</summary>
    class function MonitorPPI(const APoint: TPoint): Integer; static;
    /// <summary>Wirksame Pixel je Zoll (Monitor-DPI mal Zoom).</summary>
    property PPI: Integer read FPPI;
    /// <summary>Schrift für Beschriftungen, folgt Font in der Größe.</summary>
    property UIFont: TFont read FUIFont;
    property Canvas;
    property Font;
  end;

/// <summary>TAtlasColor als TColor.</summary>
function ToColor(AColor: TAtlasColor): TColor;

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

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasPopupWindow }

constructor TAtlasPopupWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Visible := False;
  FUIFont := TFont.Create;
  FPPI := Screen.PixelsPerInch;
  FColors := StyleColors;
  FBorderColor := FColors.Accent;
  Perform(CM_FONTCHANGED, 0, 0);
end;

destructor TAtlasPopupWindow.Destroy;
begin
  FUIFont.Free;
  inherited Destroy;
end;

class function TAtlasPopupWindow.StyleColors: TAtlasColors;
begin
  Result := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices.GetSystemColor(clWindow))));
end;

function TAtlasPopupWindow.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FPPI, 96);
end;

procedure TAtlasPopupWindow.CreateParams(var Params: TCreateParams);
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

procedure TAtlasPopupWindow.CreateWnd;
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

procedure TAtlasPopupWindow.DestroyWnd;
begin
  FCornersKnown := False;
  if FAccessible <> nil then
  begin
    TAtlasAccessibility.Release(WindowHandle);
    FAccessible := nil;
  end;
  inherited DestroyWnd;
end;

procedure TAtlasPopupWindow.WndProc(var Message: TMessage);
begin
  try
    inherited WndProc(Message);
  except
    on E: Exception do
      TAtlasGuard.Report(FGuardFeature, E);
  end;
end;

procedure TAtlasPopupWindow.SetAccessible(ARole: Integer; const AName: string);
begin
  FAccessibleRole := ARole;
  FAccessibleName := AName;
end;

function TAtlasPopupWindow.Accessible: IAtlasRawElementProvider;
begin
  if (FAccessible = nil) and (FAccessibleRole <> 0) and HandleAllocated then
    FAccessible := TAtlasAccessibleElement.Create(Handle, FAccessibleRole, FAccessibleName);
  Result := FAccessible;
end;

procedure TAtlasPopupWindow.WMGetObject(var Message: TMessage);
begin
  Message.Result := TAtlasAccessibility.Answer(Handle, Message.WParam, Message.LParam, Accessible);
  if Message.Result = 0 then
    inherited;
end;

procedure TAtlasPopupWindow.Announce(const AText: string);
begin
  if (AText = FAnnounced) or not IsShown then
    Exit;
  FAnnounced := AText;
  TAtlasAccessibility.Announce(Accessible, AText);
end;

procedure TAtlasPopupWindow.UpdateCorners;
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

procedure TAtlasPopupWindow.Resize;
begin
  inherited Resize;
  if not FSystemCorners then
    UpdateCorners;
end;

procedure TAtlasPopupWindow.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

procedure TAtlasPopupWindow.WMNCHitTest(var Message: TWMNCHitTest);
begin
  Message.Result := HTCLIENT;
end;

procedure TAtlasPopupWindow.CMFontChanged(var Message: TMessage);
begin
  inherited;
  if FUIFont = nil then
    Exit;
  // UI-Schrift der IDE, etwas kleiner als die Editorschrift (Entwurf: 12 zu 13 px).
  FUIFont.Name := Screen.MessageFont.Name;
  FUIFont.PixelsPerInch := Font.PixelsPerInch;
  FUIFont.Height := MulDiv(Font.Height, 12, 13);
  FUIFont.Charset := Font.Charset;
end;

procedure TAtlasPopupWindow.SetColors(const AValue: TAtlasColors);
begin
  FColors := AValue;
  FBorderColor := FColors.Accent;
  UpdateCorners;
  Invalidate;
end;

procedure TAtlasPopupWindow.SetBorderColor(AValue: TAtlasColor);
begin
  if FBorderColor = AValue then
    Exit;
  FBorderColor := AValue;
  UpdateCorners;
  Invalidate;
end;

procedure TAtlasPopupWindow.FillRounded(const ARect: TRect; AColor: TAtlasColor; ARadius: Integer);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(AColor);
  Canvas.Pen.Style := psClear;
  // Bei psClear zeichnet RoundRect ein Pixel kleiner; deshalb +1.
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right + 1, ARect.Bottom + 1, Scale(2 * ARadius),
    Scale(2 * ARadius));
  Canvas.Pen.Style := psSolid;
end;

procedure TAtlasPopupWindow.FrameRounded(const ARect: TRect; ALine: TAtlasColor; ARadius: Integer;
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

procedure TAtlasPopupWindow.PaintBorder;
begin
  // Unter Windows 11 zeichnet der Fenstermanager den Rahmen (DWMWA_BORDER_COLOR).
  if FSystemCorners then
    Exit;
  FrameRounded(ClientRect, FBorderColor, CornerRadius);
end;

procedure TAtlasPopupWindow.ShowAt(const ABounds: TRect);
begin
  HandleNeeded;
  // Erst Größe, dann ohne Aktivierung zeigen; Visible bleibt False wie bei THintWindow.
  SetBounds(ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height);
  SetWindowPos(Handle, HWND_TOPMOST, ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  Invalidate;
end;

procedure TAtlasPopupWindow.HidePopup;
begin
  FAnnounced := '';
  if HandleAllocated and IsWindowVisible(Handle) then
    ShowWindow(Handle, SW_HIDE);
end;

function TAtlasPopupWindow.IsShown: Boolean;
begin
  Result := HandleAllocated and IsWindowVisible(Handle);
end;

procedure TAtlasPopupWindow.SetScaling(AMonitorPPI: Integer; AZoom: Double; const AFontName: string;
  AFontSize: Integer);
begin
  FPPI := Max(48, Round(AMonitorPPI * AZoom));
  if AFontName <> '' then
    Font.Name := AFontName;
  Font.PixelsPerInch := FPPI;
  // Erst nach PixelsPerInch: Size rechnet mit der neuen Dichte in die Höhe um.
  Font.Size := AFontSize;
  UpdateCorners;
end;

class function TAtlasPopupWindow.MonitorPPI(const APoint: TPoint): Integer;
var
  Monitor: TMonitor;
begin
  Monitor := Screen.MonitorFromPoint(APoint, mdNearest);
  if Monitor <> nil then
    Result := Monitor.PixelsPerInch
  else
    Result := Screen.PixelsPerInch;
end;

class function TAtlasPopupWindow.WorkAreaAt(const APoint: TPoint): TRect;
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
