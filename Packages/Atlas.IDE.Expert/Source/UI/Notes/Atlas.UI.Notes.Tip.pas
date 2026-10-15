unit Atlas.UI.Notes.Tip;

// Tooltip einer persönlichen Notiz (#545) beim Überfahren ihres Symbols in
// der Rinne: oben gedämpft „Notiz vom 15.10.2026“, darunter der Text, auch
// mehrzeilig, umbrochen auf höchstens MaxWidth logische Pixel. Ohne Fokus wie
// alle Atlas-Fenster (TAtlasPopupWindow), Schrift der Oberfläche.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Atlas.UI.Popup.Window;

type
  TAtlasNoteTip = class(TAtlasPopupWindow)
  public const
    /// <summary>Höchstbreite des Textes in logischen Pixeln (96 dpi).</summary>
    MaxWidth = 420;
    Padding = 9;
  private
    FTitle: string;
    FText: string;
    function TextFlags: Cardinal;
    function MeasureText(AWidth: Integer): TRect;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt Überschrift und Text mit der linken oberen Ecke an APoint (Bildschirmkoordinaten).</summary>
    procedure ShowNote(const ATitle, AText: string; const APoint: TPoint);
    /// <summary>Größe für ATitle und AText (ohne zu zeigen), für Tests.</summary>
    function Measure(const ATitle, AText: string): TSize;
    property Title: string read FTitle;
    property Text: string read FText;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Popup.Accessibility;

{ TAtlasNoteTip }

constructor TAtlasNoteTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Notes;
end;

function TAtlasNoteTip.TextFlags: Cardinal;
begin
  Result := DT_LEFT or DT_TOP or DT_WORDBREAK or DT_NOPREFIX or DT_EXPANDTABS;
end;

function TAtlasNoteTip.MeasureText(AWidth: Integer): TRect;
var
  Shown: string;
begin
  Shown := FText;
  if Shown = '' then
    Shown := ' ';
  Result := Rect(0, 0, AWidth, 0);
  Canvas.Font := UIFont;
  DrawText(Canvas.Handle, PChar(Shown), -1, Result, TextFlags or DT_CALCRECT);
end;

function TAtlasNoteTip.Measure(const ATitle, AText: string): TSize;
var
  Body: TRect;
  TitleWidth, Width: Integer;
begin
  FTitle := ATitle;
  // Zeilenumbrüche der Notiz als Windows-Umbrüche, damit DrawText sie einhält.
  FText := AText.Replace(#13#10, #10).Replace(#10, #13#10);
  Canvas.Font := UIFont;
  TitleWidth := Canvas.TextWidth(FTitle);
  Body := MeasureText(Scale(MaxWidth));
  Width := Max(TitleWidth, Body.Width);
  Result.cx := Min(Width, Scale(MaxWidth)) + 2 * Scale(Padding);
  Result.cy := Canvas.TextHeight('Wg') + Scale(4) + Body.Height + 2 * Scale(Padding) - Scale(2);
end;

procedure TAtlasNoteTip.ShowNote(const ATitle, AText: string; const APoint: TPoint);
var
  Area, Bounds: TRect;
  Size: TSize;
begin
  Size := Measure(ATitle, AText);
  Area := WorkAreaAt(APoint);
  Size.cx := Min(Size.cx, Area.Width);
  Size.cy := Min(Size.cy, Area.Height);
  Bounds := TRect.Create(APoint, Size.cx, Size.cy);
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Size.cx), Bounds.Top);
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, Max(Area.Top, Area.Bottom - Size.cy));
  SetAccessible(UiaToolTipControlType, ATitle);
  ShowAt(Bounds);
  Invalidate;
  Announce(ATitle + '. ' + AText);
end;

procedure TAtlasNoteTip.Paint;
var
  Area: TRect;
  TitleHeight: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font := UIFont;
  Canvas.Brush.Style := bsClear;
  TitleHeight := Canvas.TextHeight('Wg');
  Canvas.Font.Color := ToColor(Colors.Muted);
  Area := Rect(Scale(Padding), Scale(Padding) - Scale(2), ClientWidth - Scale(Padding), Scale(Padding) +
    TitleHeight);
  DrawText(Canvas.Handle, PChar(FTitle), -1, Area, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Font.Color := ToColor(Colors.Text);
  Area := Rect(Scale(Padding), Area.Bottom + Scale(4), ClientWidth - Scale(Padding), ClientHeight - Scale(Padding));
  DrawText(Canvas.Handle, PChar(FText), -1, Area, TextFlags or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
