unit Argus.UI.Hover.Tip;

// Hover-Tooltip auf Bezeichnern (#442) im Stil von Hint und Panel: eingefärbte
// Deklaration (umbrechend), darunter gedämpft die Unit, ggf. Wert und Hinweis
// auf Veraltung in Warnfarbe, dann die Beschreibung, höchstens vier Zeilen.
// Ohne Fokus wie alle Argus-Fenster; unter dem Bezeichner, ohne Platz darüber.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Argus.Core.Style.Color,
  Argus.UI.Popup.Window;

type
  TArgusHoverContent = record
    Declaration: string;
    UnitName: string;
    Documentation: string;
    Value: string;
    Deprecation: string;
  end;

  TArgusHoverTip = class(TArgusPopupWindow)
  public const
    MaxWidth = 440;
    MaxDocumentationLines = 4;
  private
    FContent: TArgusHoverContent;
    /// <summary>Zeichnet bzw. misst bei ADraw = False; liefert die Höhe.</summary>
    function Render(AWidth: Integer; ADraw: Boolean): Integer;
  protected
    procedure Paint; override;
  public
    /// <summary>Zeigt AContent unter AWord (Bildschirmrechteck des Bezeichners).</summary>
    procedure ShowContent(const AContent: TArgusHoverContent; const AWord: TRect);
  end;

implementation

uses
  System.Math,
  Argus.UI.Popup.Styled;

{ TArgusHoverTip }

function TArgusHoverTip.Render(AWidth: Integer; ADraw: Boolean): Integer;
var
  Left, Right, Y, LineHeight, Line, X: Integer;
  Declaration: TArgusStyledText;
  Lines: TArray<TPoint>;

  procedure Block(const AText: string; AColor: TArgusColor; AMaxLines: Integer);
  var
    Area: TRect;
  begin
    if AText = '' then
      Exit;
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(AColor);
    Canvas.Brush.Style := bsClear;
    Area := Rect(Left, Y, Right, Y);
    DrawText(Canvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Area.Right := Right;
    if AMaxLines > 0 then
      Area.Bottom := Min(Area.Bottom, Y + AMaxLines * Canvas.TextHeight('Wg'));
    if ADraw then
      DrawText(Canvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
    Y := Area.Bottom + Scale(6);
  end;

begin
  Left := Scale(11);
  Right := AWidth - Scale(11);
  Y := Scale(9);
  // Deklaration eingefärbt, an Leerzeichen umbrochen.
  Canvas.Font := Font;
  LineHeight := Canvas.TextHeight('Wg') + Scale(2);
  Declaration := TArgusStyledText.Create(FContent.Declaration);
  Lines := Declaration.WrapAtSpaces(Canvas, Right - Left, Scale(16));
  for Line := 0 to High(Lines) do
  begin
    X := Left + IfThen(Line > 0, Scale(16));
    if ADraw then
      Declaration.Draw(Canvas, Colors, Lines[Line].X, Lines[Line].Y, X, Rect(X, Y, Right, Y + LineHeight), False,
        Scale(3));
    Inc(Y, LineHeight);
  end;
  Inc(Y, Scale(4));
  Block(FContent.UnitName, Colors.Muted, 0);
  if FContent.Value <> '' then
    Block('= ' + FContent.Value, Colors.Muted, 2);
  Block(FContent.Deprecation, Colors.Warn, 2);
  Block(FContent.Documentation, Colors.Text, MaxDocumentationLines);
  Result := Y + Scale(3);
end;

procedure TArgusHoverTip.ShowContent(const AContent: TArgusHoverContent; const AWord: TRect);
var
  Width, Widest, Height: Integer;
  Area, Bounds: TRect;
begin
  FContent := AContent;
  HandleNeeded;
  // Breite: Deklaration in einer Zeile, sonst die Höchstbreite.
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Widest := Canvas.TextWidth(AContent.Declaration);
  Canvas.Font := UIFont;
  Widest := Max(Widest, Canvas.TextWidth(AContent.UnitName));
  if AContent.Documentation <> '' then
    Widest := Scale(MaxWidth);
  Width := EnsureRange(Widest + Scale(26), Scale(200), Scale(MaxWidth));
  Height := Render(Width, False);
  Area := WorkAreaAt(AWord.TopLeft);
  Bounds := TRect.Create(Point(AWord.Left, AWord.Bottom + Scale(4)), Width, Height);
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, AWord.Top - Height - Scale(4));
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Width), Bounds.Top);
  ShowAt(Bounds);
end;

procedure TArgusHoverTip.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Render(ClientWidth, True);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
