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
  mArea, mBounds: TRect;
  mWidth, mHeight: Integer;
begin
  FText := AText;
  Canvas.Font := Font;
  mArea := WorkAreaAt(APoint);
  mWidth := Min(Canvas.TextWidth(AText) + Scale(18), mArea.Width);
  mHeight := Canvas.TextHeight('Wg') + Scale(10);
  mBounds := TRect.Create(APoint, mWidth, mHeight);
  if mBounds.Right > mArea.Right then
  begin
    mBounds.SetLocation(Max(mArea.Left, mArea.Right - mWidth), mBounds.Top);
  end;
  if mBounds.Bottom > mArea.Bottom then
  begin
    mBounds.SetLocation(mBounds.Left, mArea.Bottom - mHeight);
  end;
  ShowAt(mBounds);
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
