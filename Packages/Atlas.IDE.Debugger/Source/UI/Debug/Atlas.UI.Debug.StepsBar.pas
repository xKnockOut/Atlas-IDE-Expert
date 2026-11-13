unit Atlas.UI.Debug.StepsBar;

// Kleine Leiste mit den Schritten eines Ablaufs (Neu starten #872), im
// Atlas-Stil (#410, #411), ohne Fokus und ohne Klickflächen:
//     Neu starten
//     Beenden 0,3 s ✓ · Bauen 2,1 s ✓ · Starten …

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Atlas.UI.Popup.Window;

type
  TAtlasStepsBar = class(TAtlasPopupWindow)
  public const
    cGap = 4;
    cPad = 10;
  private
    FTitle: string;
    FText: string;
    function Layout(ADraw: Boolean): TSize;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt ATitle und AText mit der rechten oberen Ecke an APoint (Bildschirm); schon sichtbar, nur
    /// neuer Text.</summary>
    procedure ShowSteps(const ATitle, AText: string; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Rechte obere Ecke im aktiven Fenster der IDE (Bildschirm), etwas eingerückt; auch für andere
    /// Fenster des Debuggers (#869).</summary>
    class function ActiveCorner: TPoint; static;
    property Text: string read FText;
  end;

implementation

uses
  System.Math,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Popup.Accessibility;

const
  /// <summary>Abstand vom rechten bzw. oberen Rand des aktiven Fensters (in cPad).</summary>
  cCornerRight = 3;
  cCornerTop = 8;

class function TAtlasStepsBar.ActiveCorner: TPoint;
var
  mForm: TCustomForm;
  mRect: TRect;
begin
  mForm := Screen.ActiveCustomForm;
  if mForm = nil then
  begin
    mForm := Application.MainForm;
  end;
  if mForm = nil then
  begin
    Exit(Mouse.CursorPos);
  end;
  mRect := mForm.BoundsRect;
  Result := TPoint.Create(mRect.Right - mForm.ScaleValue(cPad * cCornerRight),
    mRect.Top + mForm.ScaleValue(cPad * cCornerTop));
end;

constructor TAtlasStepsBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Debugger;
  SetAccessible(cUiaToolTipControlType, '');
end;

function TAtlasStepsBar.Layout(ADraw: Boolean): TSize;
var
  X, Y, mTextHeight, mWidth: Integer;
begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  X := Scale(cPad);
  Y := Scale(cPad);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(X, Y, FTitle);
  end;
  mWidth := X + Canvas.TextWidth(FTitle);
  Canvas.Font.Style := [];
  Y := Y + mTextHeight + Scale(cGap);
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(X, Y, FText);
    Canvas.Brush.Style := bsSolid;
  end;
  mWidth := Max(mWidth, X + Canvas.TextWidth(FText));
  Result.cx := mWidth + Scale(cPad);
  Result.cy := Y + mTextHeight + Scale(cPad);
end;

procedure TAtlasStepsBar.ShowSteps(const ATitle, AText: string; const APoint: TPoint);
var
  mSize: TSize;
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  FTitle := ATitle;
  FText := AText;
  HandleNeeded;
  mSize := Layout(False);
  mArea := WorkAreaAt(APoint);
  mLeft := Max(mArea.Left, Min(APoint.X - mSize.cx, mArea.Right - mSize.cx));
  mTop := Max(mArea.Top, Min(APoint.Y, mArea.Bottom - mSize.cy));
  ShowAt(Rect(mLeft, mTop, mLeft + mSize.cx, mTop + mSize.cy));
  Invalidate;
end;

procedure TAtlasStepsBar.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasStepsBar.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

end.
