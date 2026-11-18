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
  Atlas.Core.Style.Palette,
  Atlas.UI.Designer.Overlay;

type
  TAtlasDesignerFlash = class(TAtlasDesignerOverlay)
  private const
    cDuration = 600;
  private
    FTimer: TTimer;
    procedure TimerTick(Sender: TObject);
  protected
    procedure Paint; override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateFlash(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    /// <summary>Rahmen um AScreen (Bildschirm) zeigen, ohne den Fokus zu nehmen.</summary>
    procedure FlashAt(const AScreen: TRect);
  end;

implementation

const
  /// <summary>Breite des Rahmens außen um das Steuerelement, logische Pixel.</summary>
  cFrameWidth = 3;

{ TAtlasDesignerFlash }

constructor TAtlasDesignerFlash.CreateFlash(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
begin
  inherited CreateOverlayWindow(AOwner, AOwnerWindow, AColors,
    [TAtlasOverlayOption.Popup, TAtlasOverlayOption.KeyColor, TAtlasOverlayOption.ClickThrough]);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cDuration;
  FTimer.OnTimer := TimerTick;
end;

procedure TAtlasDesignerFlash.Paint;
var
  mWidth: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := cKeyColor;
  Canvas.FillRect(ClientRect);
  mWidth := ScalePx(2);
  Canvas.Pen.Color := TColor(Colors.Accent);
  Canvas.Pen.Width := mWidth;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(mWidth div 2, mWidth div 2, ClientWidth - mWidth div 2 + 1, ClientHeight - mWidth div 2 + 1);
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Width := 1;
end;

procedure TAtlasDesignerFlash.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  if HandleAllocated then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
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
  mRect.Inflate(ScalePx(cFrameWidth), ScalePx(cFrameWidth));
  HandleNeeded;
  SetWindowPos(Handle, HWND_TOP, mRect.Left, mRect.Top, mRect.Width, mRect.Height, SWP_NOACTIVATE or SWP_SHOWWINDOW);
  Invalidate;
  FTimer.Enabled := True;
end;

end.
