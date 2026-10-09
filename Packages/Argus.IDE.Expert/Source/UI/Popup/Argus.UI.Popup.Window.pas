unit Argus.UI.Popup.Window;

// Basis für Popup, Parameter-Hint und Tooltip von Argus (#410): eigenes,
// selbst gezeichnetes Fenster, das dem Editor nie den Fokus nimmt. Caret, IME
// und Undo bleiben so beim Editor.
//   - WS_POPUP mit WS_EX_NOACTIVATE und WS_EX_TOOLWINDOW, Besitzer ist das
//     Hauptfenster der IDE; Schatten über CS_DROPSHADOW.
//   - WM_MOUSEACTIVATE liefert MA_NOACTIVATE: Klicks wählen, ohne zu aktivieren.
//   - Zeigen über SetWindowPos mit SWP_NOACTIVATE (wie THintWindow), nicht über Visible.
// Tasten bekommt das Fenster nie; der Editor leitet sie über die
// Tastaturbindung weiter (Argus.IDE).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls;

type
  TArgusPopupColors = record
    Background: TColor;
    Text: TColor;
    /// <summary>Signaturen, Unit-Namen.</summary>
    SecondaryText: TColor;
    SelectionBackground: TColor;
    SelectionText: TColor;
    Border: TColor;
    /// <summary>Kennfarbe für Badges und Scrollleiste.</summary>
    Accent: TColor;
    /// <summary>Aus dem aktiven VCL-Stil (in der IDE deren Thema).</summary>
    class function FromStyle: TArgusPopupColors; static;
  end;

  TArgusPopupWindow = class(TCustomControl)
  private
    FColors: TArgusPopupColors;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure SetColors(const AValue: TArgusPopupColors);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    /// <summary>Rahmen in Border.</summary>
    procedure PaintBorder;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt das Fenster ohne Aktivierung an ABounds (Bildschirmkoordinaten).</summary>
    procedure ShowAt(const ABounds: TRect);
    procedure HidePopup;
    function IsShown: Boolean;
    /// <summary>Arbeitsbereich des Monitors, auf dem APoint liegt.</summary>
    class function WorkAreaAt(const APoint: TPoint): TRect; static;
    property Colors: TArgusPopupColors read FColors write SetColors;
    property Canvas;
    property Font;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.Themes;

{ TArgusPopupColors }

class function TArgusPopupColors.FromStyle: TArgusPopupColors;
var
  Style: TCustomStyleServices;
begin
  Style := StyleServices;
  Result.Background := Style.GetSystemColor(clWindow);
  Result.Text := Style.GetSystemColor(clWindowText);
  Result.SecondaryText := Style.GetSystemColor(clGrayText);
  Result.SelectionBackground := Style.GetSystemColor(clHighlight);
  Result.SelectionText := Style.GetSystemColor(clHighlightText);
  Result.Border := Style.GetSystemColor(clBtnShadow);
  Result.Accent := Style.GetSystemColor(clHighlight);
end;

{ TArgusPopupWindow }

constructor TArgusPopupWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Visible := False;
  FColors := TArgusPopupColors.FromStyle;
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

procedure TArgusPopupWindow.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

procedure TArgusPopupWindow.WMNCHitTest(var Message: TWMNCHitTest);
begin
  Message.Result := HTCLIENT;
end;

procedure TArgusPopupWindow.SetColors(const AValue: TArgusPopupColors);
begin
  FColors := AValue;
  Invalidate;
end;

procedure TArgusPopupWindow.PaintBorder;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := FColors.Border;
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
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
