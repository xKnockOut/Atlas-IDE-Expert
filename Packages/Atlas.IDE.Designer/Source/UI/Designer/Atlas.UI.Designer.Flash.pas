unit Atlas.UI.Designer.Flash;

// Kurzer Rahmen um ein Steuerelement im Designer (#745): zeigt nach einem
// Sprung mit der räumlichen Navigation, wohin es ging. Durchsichtiges
// Fenster über dem Designer wie die Tab-Reihenfolge (TAtlasTabOrderOverlay):
// gehört dem Hauptfenster der IDE, nimmt nie den Fokus, alle Klicks gehen
// durch (WS_EX_TRANSPARENT). Verschwindet nach cDuration Millisekunden von
// selbst.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Palette;

type
  TAtlasDesignerFlash = class(TForm)
  private const
    cKeyColor = TColor($00FF00FF);
    cDuration = 600;
  private
    FColors: TAtlasColors;
    FOwnerWindow: HWND;
    FTimer: TTimer;
    function S(AValue: Integer): Integer;
    procedure TimerTick(Sender: TObject);
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateFlash(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Rahmen um AScreen (Bildschirm) zeigen, ohne den Fokus zu nehmen.</summary>
    procedure FlashAt(const AScreen: TRect);
  end;

implementation

constructor TAtlasDesignerFlash.CreateFlash(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  FColors := AColors;
  BorderStyle := bsNone;
  Color := cKeyColor;
  TransparentColor := True;
  TransparentColorValue := cKeyColor;
  DoubleBuffered := True;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cDuration;
  FTimer.OnTimer := TimerTick;
end;

procedure TAtlasDesignerFlash.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW or WS_EX_TRANSPARENT;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
end;

procedure TAtlasDesignerFlash.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

function TAtlasDesignerFlash.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

procedure TAtlasDesignerFlash.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

procedure TAtlasDesignerFlash.Paint;
var
  mWidth: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := cKeyColor;
  Canvas.FillRect(ClientRect);
  mWidth := S(2);
  Canvas.Pen.Color := TColor(FColors.Accent);
  Canvas.Pen.Width := mWidth;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(mWidth div 2, mWidth div 2, ClientWidth - mWidth div 2 + 1, ClientHeight - mWidth div 2 + 1);
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Width := 1;
end;

procedure TAtlasDesignerFlash.FlashAt(const AScreen: TRect);
var
  mRect: TRect;
begin
  FTimer.Enabled := False;
  if AScreen.IsEmpty then
  begin
    Exit;
  end;
  // Der Rahmen liegt außen um das Steuerelement, damit er nichts verdeckt.
  mRect := AScreen;
  mRect.Inflate(S(3), S(3));
  HandleNeeded;
  SetWindowPos(Handle, HWND_TOP, mRect.Left, mRect.Top, mRect.Width, mRect.Height, SWP_NOACTIVATE or SWP_SHOWWINDOW);
  Invalidate;
  FTimer.Enabled := True;
end;

procedure TAtlasDesignerFlash.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  if HandleAllocated then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
end;

end.
