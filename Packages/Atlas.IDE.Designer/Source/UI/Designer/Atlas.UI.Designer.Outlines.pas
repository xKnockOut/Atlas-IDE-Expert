unit Atlas.UI.Designer.Outlines;

// Umrisse geplanter Steuerelemente im Designer (#736, Vorschau von „In Reihe
// duplizieren“): gestrichelte Rahmen mit Namen in der Akzentfarbe, in der
// Fehlerfarbe, wenn eine Kopie herausragt oder etwas überdeckt.
// Durchsichtiges Fenster über dem Elternelement wie die Tab-Reihenfolge
// (TAtlasTabOrderOverlay): gehört dem Hauptfenster der IDE, nimmt nie den
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
  Atlas.Core.Style.Palette,
  Atlas.UI.Designer.Overlay;

type
  TAtlasOutline = record
    /// <summary>Lage im Client des Fensters.</summary>
    Bounds: TRect;
    Name: string;
    Bad: Boolean;
    class function Create(const ABounds: TRect; const AName: string; ABad: Boolean): TAtlasOutline; static;
  end;

  TAtlasDesignerOutlines = class(TAtlasDesignerOverlay)
  private
    FOutlines: TArray<TAtlasOutline>;
  protected
    procedure Paint; override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateOutlines(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    /// <summary>Umrisse über AScreen (Bildschirm) zeigen, ohne den Fokus zu nehmen.</summary>
    procedure ShowOutlines(const AScreen: TRect; const AOutlines: TArray<TAtlasOutline>);
    procedure HideOutlines;
    property Outlines: TArray<TAtlasOutline> read FOutlines;
  end;

implementation

{ TAtlasOutline }

class function TAtlasOutline.Create(const ABounds: TRect; const AName: string; ABad: Boolean): TAtlasOutline;
begin
  Result.Bounds := ABounds;
  Result.Name := AName;
  Result.Bad := ABad;
end;

{ TAtlasDesignerOutlines }

constructor TAtlasDesignerOutlines.CreateOutlines(AOwner: TComponent; AOwnerWindow: HWND;
  const AColors: TAtlasColors);
begin
  inherited CreateOverlayWindow(AOwner, AOwnerWindow, AColors,
    [TAtlasOverlayOption.Popup, TAtlasOverlayOption.KeyColor, TAtlasOverlayOption.ClickThrough]);
end;

procedure TAtlasDesignerOutlines.Paint;
var
  mOutline: TAtlasOutline;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := cKeyColor;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  for mOutline in FOutlines do
  begin
    Canvas.Pen.Color := TColor(Colors.Accent);
    Canvas.Font.Color := TColor(Colors.Accent);
    if mOutline.Bad then
    begin
      Canvas.Pen.Color := TColor(Colors.Error);
      Canvas.Font.Color := TColor(Colors.Error);
    end;
    Canvas.Pen.Style := psDot;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(mOutline.Bounds);
    Canvas.TextOut(mOutline.Bounds.Left + ScalePx(cTextInset), mOutline.Bounds.Top + ScalePx(1), mOutline.Name);
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasDesignerOutlines.ShowOutlines(const AScreen: TRect; const AOutlines: TArray<TAtlasOutline>);
begin
  FOutlines := AOutlines;
  if AScreen.IsEmpty or (Length(AOutlines) = 0) then
  begin
    HideOutlines;
    Exit;
  end;
  HandleNeeded;
  SetWindowPos(Handle, HWND_TOP, AScreen.Left, AScreen.Top, AScreen.Width, AScreen.Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  Invalidate;
end;

procedure TAtlasDesignerOutlines.HideOutlines;
begin
  if HandleAllocated then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
end;

end.
