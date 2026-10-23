unit Atlas.UI.Popup.Tip;

// Kleiner Tooltip im Atlas-Stil (#420): zeigt den vollständigen Text eines
// gekürzten Eintrags. Ohne Fokus wie alle Atlas-Fenster, eine Zeile in der
// Editorschrift, höchstens so breit wie der Arbeitsbereich des Monitors.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Atlas.UI.Popup.Window;

type
  TAtlasTextTip = class(TAtlasPopupWindow)
  private
    FText: string;
  protected
    procedure Paint; override;
  public
    /// <summary>Zeigt AText mit der linken oberen Ecke an APoint (Bildschirmkoordinaten).</summary>
    procedure ShowText(const AText: string; const APoint: TPoint);
    property Text: string read FText;
  end;

implementation

uses
  System.Math;

{ TAtlasTextTip }

procedure TAtlasTextTip.ShowText(const AText: string; const APoint: TPoint);
var
  Area, Bounds: TRect;
  mWidth, mHeight: Integer;
begin
  FText := AText;
  Canvas.Font := Font;
  Area := WorkAreaAt(APoint);
  mWidth := Min(Canvas.TextWidth(AText) + Scale(18), Area.Width);
  mHeight := Canvas.TextHeight('Wg') + Scale(10);
  Bounds := TRect.Create(APoint, mWidth, mHeight);
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - mWidth), Bounds.Top);
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, Area.Bottom - mHeight);
  ShowAt(Bounds);
  Invalidate;
end;

procedure TAtlasTextTip.Paint;
var
  mText: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(Colors.Text);
  Canvas.Brush.Style := bsClear;
  mText := Rect(Scale(9), 0, ClientWidth - Scale(9), ClientHeight);
  DrawText(Canvas.Handle, PChar(FText), -1, mText, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
