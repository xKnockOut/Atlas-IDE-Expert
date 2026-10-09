unit Argus.UI.Completion.Details;

// Detailpanel der Vervollständigung (#424, #426, #427): Fenster ohne Fokus
// neben der Liste mit Details zum gewählten Eintrag, von oben nach unten:
//   1. Tags: Sichtbarkeit und Direktiven, deprecated in Warnfarbe
//   2. Deklaration, umbrechend
//   3. Unit · Klasse
//   4. Trennlinie
//   5. Beschreibung (<summary>), bei deprecated "Veraltet: …"
//   6. Parameter, Rückgabe (→) und Exceptions (!), zweispaltig
//   7. Bemerkungen (<remarks>), höchstens drei Zeilen
//   8. Fußzeile "Enter übernehmen · Esc schließen"
// Leere Abschnitte entfallen. Breite 340 px (logisch); rechts neben der Liste,
// ohne Platz dort links davon.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Argus.Core.Completion.Contract,
  Argus.UI.Popup.Window;

type
  TArgusDetailPanel = class(TArgusPopupWindow)
  public const
    DefaultWidth = 340;
  private
    FDetails: TArgusItemDetails;
    /// <summary>Zeichnet (ADraw) bzw. misst den Inhalt; liefert die Höhe.</summary>
    function Render(ADraw: Boolean): Integer;
    function Scale(AValue: Integer): Integer;
  protected
    procedure Paint; override;
  public
    /// <summary>Zeigt ADetails neben AList (Bildschirmkoordinaten der Liste).</summary>
    procedure ShowDetails(const ADetails: TArgusItemDetails; const AList: TRect);
    procedure HideDetails;
    /// <summary>Hält das Panel neben der Liste, wenn diese wandert oder wächst.</summary>
    procedure Follow(const AList: TRect);
  end;

implementation

uses
  System.Math;

{ TArgusDetailPanel }

function TArgusDetailPanel.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TArgusDetailPanel.Render(ADraw: Boolean): Integer;
var
  Gap, Y, Right, NameWidth, TagX: Integer;
  Entry: TArgusDocEntry;
  Text, Tag: string;

  /// <summary>Text umbrechend ab Y; AMaxLines = 0 ohne Grenze.</summary>
  procedure Block(const AText: string; AColor: TColor; AStyle: TFontStyles; ALeft: Integer = -1;
    AMaxLines: Integer = 0);
  var
    Rect_: TRect;
    LineHeight: Integer;
  begin
    if AText = '' then
      Exit;
    if ALeft < 0 then
      ALeft := Gap;
    Canvas.Font.Style := AStyle;
    Canvas.Font.Color := AColor;
    Rect_ := Rect(ALeft, Y, Right, Y);
    DrawText(Canvas.Handle, PChar(AText), -1, Rect_, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Rect_.Right := Right;
    if AMaxLines > 0 then
    begin
      LineHeight := Canvas.TextHeight('Wg');
      Rect_.Bottom := Min(Rect_.Bottom, Y + AMaxLines * LineHeight);
    end;
    if ADraw then
      DrawText(Canvas.Handle, PChar(AText), -1, Rect_, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
    Y := Rect_.Bottom + Scale(4);
    Canvas.Font.Style := [];
  end;

  procedure Entry2(const AName, AText: string);
  var
    Rect_: TRect;
    Bottom: Integer;
  begin
    // Name links (halbfett), Text rechts umbrechend.
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := Colors.Text;
    Rect_ := Rect(Gap, Y, Gap + NameWidth, Y + Canvas.TextHeight('Wg'));
    if ADraw then
      DrawText(Canvas.Handle, PChar(AName), -1, Rect_, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Font.Style := [];
    Canvas.Font.Color := Colors.SecondaryText;
    Rect_ := Rect(Gap + NameWidth + Gap, Y, Right, Y);
    DrawText(Canvas.Handle, PChar(AText), -1, Rect_, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Rect_.Right := Right;
    Bottom := Max(Rect_.Bottom, Y + Canvas.TextHeight('Wg'));
    if ADraw then
      DrawText(Canvas.Handle, PChar(AText), -1, Rect_, DT_WORDBREAK or DT_NOPREFIX);
    Y := Bottom + Scale(2);
  end;

  procedure Separator;
  begin
    if ADraw then
    begin
      Canvas.Pen.Color := Colors.Border;
      Canvas.MoveTo(Gap, Y + Scale(2));
      Canvas.LineTo(Right, Y + Scale(2));
    end;
    Inc(Y, Scale(6));
  end;

begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  Gap := Scale(8);
  Right := ClientWidth - Gap;
  if not ADraw then
    Right := Scale(DefaultWidth) - Gap;
  Y := Scale(6);
  // 1. Tags.
  TagX := Gap;
  if (FDetails.Visibility <> '') or (Length(FDetails.Directives) > 0) then
  begin
    Canvas.Font.Style := [];
    for Tag in [FDetails.Visibility] + FDetails.Directives do
    begin
      if Tag = '' then
        Continue;
      if ADraw then
      begin
        if Tag = 'deprecated' then
          Canvas.Font.Color := clRed
        else
          Canvas.Font.Color := Colors.Accent;
        Canvas.TextOut(TagX, Y, Tag);
      end;
      Inc(TagX, Canvas.TextWidth(Tag) + Gap);
    end;
    Inc(Y, Canvas.TextHeight('Wg') + Scale(4));
  end;
  // 2. Deklaration, 3. Unit · Klasse.
  Block(FDetails.Declaration, Colors.Text, [fsBold]);
  Text := FDetails.UnitName;
  if FDetails.Container <> '' then
    if Text <> '' then
      Text := Text + ' · ' + FDetails.Container
    else
      Text := FDetails.Container;
  Block(Text, Colors.SecondaryText, []);
  // 4.–7. Beschreibung und XMLDoc; ohne Inhalt keine Trennlinie und keine leeren Abschnitte.
  if FDetails.IsDeprecated or (FDetails.Summary <> '') or (FDetails.Returns <> '') or
    (Length(FDetails.Params) > 0) or (Length(FDetails.Exceptions) > 0) or (FDetails.Remarks <> '') then
  begin
    Separator;
    if FDetails.IsDeprecated then
      if FDetails.DeprecatedText <> '' then
        Block('Veraltet: ' + FDetails.DeprecatedText, clRed, [])
      else
        Block('Veraltet.', clRed, []);
    Block(FDetails.Summary, Colors.Text, []);
    Canvas.Font.Style := [fsBold];
    NameWidth := 0;
    for Entry in FDetails.Params do
      NameWidth := Max(NameWidth, Canvas.TextWidth(Entry.Name));
    for Entry in FDetails.Exceptions do
      NameWidth := Max(NameWidth, Canvas.TextWidth('! ' + Entry.Name));
    if FDetails.Returns <> '' then
      NameWidth := Max(NameWidth, Canvas.TextWidth('→'));
    NameWidth := Min(NameWidth, (Right - Gap) div 3);
    Canvas.Font.Style := [];
    for Entry in FDetails.Params do
      Entry2(Entry.Name, Entry.Text);
    if FDetails.Returns <> '' then
      Entry2('→', FDetails.Returns);
    for Entry in FDetails.Exceptions do
      Entry2('! ' + Entry.Name, Entry.Text);
    if FDetails.Remarks <> '' then
    begin
      Separator;
      Block(FDetails.Remarks, Colors.SecondaryText, [], -1, 3);
    end;
  end;
  // 8. Fußzeile.
  Separator;
  Block('Enter übernehmen · Esc schließen', Colors.SecondaryText, []);
  Result := Y + Scale(2);
end;

procedure TArgusDetailPanel.Paint;
begin
  Canvas.Brush.Color := Colors.Background;
  Canvas.FillRect(ClientRect);
  Render(True);
  PaintBorder;
end;

procedure TArgusDetailPanel.ShowDetails(const ADetails: TArgusItemDetails; const AList: TRect);
begin
  if ADetails.IsEmpty then
  begin
    HideDetails;
    Exit;
  end;
  FDetails := ADetails;
  Follow(AList);
  Invalidate;
end;

procedure TArgusDetailPanel.Follow(const AList: TRect);
var
  Width, Height: Integer;
  Area, Bounds: TRect;
begin
  if FDetails.IsEmpty then
    Exit;
  HandleNeeded;
  Width := Scale(DefaultWidth);
  Height := Render(False);
  Area := WorkAreaAt(AList.TopLeft);
  Bounds := TRect.Create(Point(AList.Right + Scale(2), AList.Top), Width, Height);
  // Rechts kein Platz: links neben die Liste.
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(AList.Left - Width - Scale(2), AList.Top);
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, Max(Area.Top, Area.Bottom - Height));
  if (not IsShown) or (Bounds <> BoundsRect) then
    ShowAt(Bounds);
end;

procedure TArgusDetailPanel.HideDetails;
begin
  HidePopup;
  FDetails := Default(TArgusItemDetails);
end;

end.
