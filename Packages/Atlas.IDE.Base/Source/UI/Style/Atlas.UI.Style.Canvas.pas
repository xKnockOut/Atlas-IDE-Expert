unit Atlas.UI.Style.Canvas;

// Zeichenfläche ohne Flackern für selbst gezeichnete Bereiche und Kacheln
// (#753, seit #1455 in Base, damit Module wie der Tracker sie ohne die
// Willkommensseite nutzen). Eine TPaintBox auf Panels mit ParentBackground
// lässt Windows vor jedem Neuzeichnen den Hintergrund der Eltern holen; beim
// Hovern blitzt das. Hier kommen Hintergrund und Inhalt zusammen in einen
// Puffer, gelöscht wird nie. Beim Zeichnen bekommen Panels, Frames und der
// Rollbereich darüber die Hintergrundfarbe des aktiven Stils.

interface

uses
  Winapi.Messages,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAtlasStyledCanvas = class(TCustomControl)
  private
    FOnPaint: TNotifyEvent;
    procedure WMEraseBkgnd(var AMessage: TWMEraseBkgnd); message WM_ERASEBKGND;
    /// <summary>Panels, Frames und den Rollbereich über AControl auf AColor setzen, wo sie abweichen.</summary>
    class procedure ColorParents(AControl: TControl; AColor: TColor); static;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Hintergrund im aktuellen IDE-Thema (clWindow des Stils).</summary>
    class function BackgroundOf(AControl: TControl): TColor; static;
    property Canvas;
    property ShowHint;
    property PopupMenu;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseLeave;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Themes;

type
  TColoredControl = class(TControl);
  TBackgroundControl = class(TWinControl);

{ TAtlasStyledCanvas }

constructor TAtlasStyledCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
end;

procedure TAtlasStyledCanvas.WMEraseBkgnd(var AMessage: TWMEraseBkgnd);
begin
  // Paint deckt alles ab, auch den Hintergrund.
  AMessage.Result := 1;
end;

class function TAtlasStyledCanvas.BackgroundOf(AControl: TControl): TColor;
begin
  // Direkt aus dem Stil wie die Schriftfarben (clWindowText). Die Farbe der Vorfahren war nach einem Wechsel
  // veraltet und bei „Windows-Design anpassen“ fest weiß.
  Result := StyleServices(AControl).GetSystemColor(clWindow);
end;

class procedure TAtlasStyledCanvas.ColorParents(AControl: TControl; AColor: TColor);
var
  mParent: TWinControl;
begin
  // Mit ParentBackground blieb unter den IDE-Stilen nach einem Themenwechsel (und bei „Windows-Design anpassen“)
  // das alte Bild stehen. Beim Zeichnen, weil der Stil erst dann sicher feststeht.
  mParent := AControl.Parent;
  while (mParent is TCustomPanel) or (mParent is TScrollBox) or (mParent is TCustomFrame) do
  begin
    if TBackgroundControl(mParent).ParentBackground or (TColoredControl(mParent).Color <> AColor) then
    begin
      TBackgroundControl(mParent).ParentBackground := False;
      mParent.StyleElements := mParent.StyleElements - [seClient];
      TColoredControl(mParent).Color := AColor;
    end;
    if mParent is TScrollBox then
    begin
      Break;
    end;
    mParent := mParent.Parent;
  end;
end;

procedure TAtlasStyledCanvas.Paint;
var
  mColor: TColor;
begin
  mColor := BackgroundOf(Self);
  ColorParents(Self, mColor);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := mColor;
  Canvas.FillRect(ClientRect);
  if Assigned(FOnPaint) then
  begin
    FOnPaint(Self);
  end;
end;

end.
