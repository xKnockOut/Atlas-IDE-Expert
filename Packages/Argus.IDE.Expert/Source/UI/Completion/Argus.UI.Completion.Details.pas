unit Argus.UI.Completion.Details;

// Detailpanel der Vervollständigung (#424, #426, #427): kein eigenes Fenster,
// sondern der rechte (bzw. linke) Bereich des Popups, wie im Entwurf ein
// Rahmen mit Trennlinie. Inhalt von oben nach unten:
//   1. Tags: Sichtbarkeit und Direktiven als umrandete Marken, deprecated in Warnfarbe
//   2. Deklaration in der Editorschrift, eingefärbt, umbrechend
//   3. Unit · Klasse, gedämpft
//   4. Trennlinie
//   5. Beschreibung (<summary>), bei deprecated "Veraltet: …" in Warnfarbe
//   6. Parameter (Name in Akzentfarbe), Rückgabe (→) und Exceptions (!), zweispaltig
//   7. Bemerkungen (<remarks>), höchstens drei Zeilen
// Leere Abschnitte entfallen. Ohne Details (z. B. Schlüsselwort) steht ein
// gedämpfter Hinweis, damit das Popup beim Blättern nicht schmaler wird.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Argus.Core.Style.Color,
  Argus.Core.Style.Palette,
  Argus.Core.Completion.Contract;

type
  TArgusDetailView = class
  public const
    DefaultWidth = 320;
  private
    FDetails: TArgusItemDetails;
  public
    /// <summary>Zeichnet (ADraw) bzw. misst den Inhalt in ABounds; liefert die benötigte Höhe.
    /// APPI: Pixel je Zoll des Fensters; AFont: Editorschrift; AUIFont: Beschriftungen.</summary>
    function Render(ACanvas: TCanvas; const AColors: TArgusColors; AFont, AUIFont: TFont; const ABounds: TRect;
      APPI: Integer; ADraw: Boolean): Integer;
    property Details: TArgusItemDetails read FDetails write FDetails;
  end;

implementation

uses
  System.Math,
  Argus.UI.Popup.Window,
  Argus.UI.Popup.Styled;

{ TArgusDetailView }

function TArgusDetailView.Render(ACanvas: TCanvas; const AColors: TArgusColors; AFont, AUIFont: TFont;
  const ABounds: TRect; APPI: Integer; ADraw: Boolean): Integer;
var
  Left, Y, Right, NameWidth, ExceptionWidth, TagX, TagHeight, LineHeight: Integer;
  Entry: TArgusDocEntry;
  Text, Tag: string;
  Declaration: TArgusStyledText;
  Lines: TArray<TPoint>;
  Line, X: Integer;
  Box, Rect_: TRect;

  function Scale(AValue: Integer): Integer;
  begin
    Result := MulDiv(AValue, APPI, 96);
  end;

  procedure Frame(const ARect: TRect; ALine: TArgusColor);
  begin
    ACanvas.Brush.Style := bsClear;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Color := ToColor(ALine);
    ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Scale(6), Scale(6));
  end;

  /// <summary>Text in der UI-Schrift umbrechend ab Y; AMaxLines = 0 ohne Grenze.</summary>
  procedure Block(const AText: string; AColor: TArgusColor; AStyle: TFontStyles; AMaxLines: Integer = 0);
  var
    Area: TRect;
  begin
    if AText = '' then
      Exit;
    ACanvas.Font := AUIFont;
    ACanvas.Font.Style := AStyle;
    ACanvas.Font.Color := ToColor(AColor);
    ACanvas.Brush.Style := bsClear;
    Area := Rect(Left, Y, Right, Y);
    DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Area.Right := Right;
    if AMaxLines > 0 then
      Area.Bottom := Min(Area.Bottom, Y + AMaxLines * ACanvas.TextHeight('Wg'));
    if ADraw then
      DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
    Y := Area.Bottom + Scale(6);
    ACanvas.Font.Style := [];
  end;

  /// <summary>Name links in der Editorschrift (AColor, halbfett), Text rechts umbrechend.</summary>
  procedure Entry2(const AName, AText: string; AColor: TArgusColor; ANameWidth: Integer);
  var
    Area: TRect;
    Bottom: Integer;
  begin
    ACanvas.Font := AFont;
    ACanvas.Font.Style := [fsBold];
    ACanvas.Font.Color := ToColor(AColor);
    ACanvas.Brush.Style := bsClear;
    Area := Rect(Left, Y, Left + ANameWidth, Y + ACanvas.TextHeight('Wg'));
    Bottom := Area.Bottom;
    if ADraw then
      DrawText(ACanvas.Handle, PChar(AName), -1, Area, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
    ACanvas.Font := AUIFont;
    ACanvas.Font.Color := ToColor(AColors.Muted);
    Area := Rect(Left + ANameWidth + Scale(8), Y, Right, Y);
    DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
    Area.Right := Right;
    // Grundlinien angleichen: die UI-Schrift ist etwas kleiner als die Editorschrift.
    OffsetRect(Area, 0, Max(0, (Bottom - Y - ACanvas.TextHeight('Wg')) div 2));
    if ADraw then
      DrawText(ACanvas.Handle, PChar(AText), -1, Area, DT_WORDBREAK or DT_NOPREFIX);
    Y := Max(Bottom, Area.Bottom) + Scale(3);
  end;

  procedure Separator;
  begin
    if ADraw then
    begin
      ACanvas.Pen.Style := psSolid;
      ACanvas.Pen.Color := ToColor(AColors.Line);
      ACanvas.MoveTo(Left, Y + Scale(2));
      ACanvas.LineTo(Right, Y + Scale(2));
    end;
    Inc(Y, Scale(8));
  end;

begin
  Left := ABounds.Left + Scale(13);
  Right := ABounds.Right - Scale(13);
  Y := ABounds.Top + Scale(11);
  if FDetails.IsEmpty then
  begin
    Block('Keine Details zu diesem Eintrag', AColors.Muted, []);
    Exit(Y - ABounds.Top + Scale(5));
  end;
  // 1. Tags als umrandete Marken.
  if (FDetails.Visibility <> '') or (Length(FDetails.Directives) > 0) then
  begin
    ACanvas.Font := AUIFont;
    TagHeight := ACanvas.TextHeight('Wg') + Scale(2);
    TagX := Left;
    for Tag in [FDetails.Visibility] + FDetails.Directives do
    begin
      if Tag = '' then
        Continue;
      ACanvas.Font := AUIFont;
      Box := Rect(TagX, Y, TagX + ACanvas.TextWidth(Tag) + Scale(10), Y + TagHeight);
      if ADraw then
      begin
        if Tag = 'deprecated' then
        begin
          Frame(Box, AColors.Warn);
          ACanvas.Font.Color := ToColor(AColors.Warn);
        end
        else
        begin
          Frame(Box, AColors.Line);
          ACanvas.Font.Color := ToColor(AColors.Muted);
        end;
        ACanvas.Brush.Style := bsClear;
        Rect_ := Box;
        DrawText(ACanvas.Handle, PChar(Tag), -1, Rect_, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
      end;
      TagX := Box.Right + Scale(6);
    end;
    Inc(Y, TagHeight + Scale(8));
  end;
  // 2. Deklaration, eingefärbt und an Leerzeichen umbrochen.
  if FDetails.Declaration <> '' then
  begin
    ACanvas.Font := AFont;
    LineHeight := ACanvas.TextHeight('Wg') + Scale(2);
    Declaration := TArgusStyledText.Create(FDetails.Declaration);
    Lines := Declaration.WrapAtSpaces(ACanvas, Right - Left, Scale(16));
    for Line := 0 to High(Lines) do
    begin
      X := Left + IfThen(Line > 0, Scale(16));
      if ADraw then
        Declaration.Draw(ACanvas, AColors, Lines[Line].X, Lines[Line].Y, X, Rect(X, Y, Right, Y + LineHeight),
          False, Scale(3));
      Inc(Y, LineHeight);
    end;
    Inc(Y, Scale(3));
  end;
  // 3. Unit · Klasse.
  Text := FDetails.UnitName;
  if FDetails.Container <> '' then
    if Text <> '' then
      Text := Text + ' · ' + FDetails.Container
    else
      Text := FDetails.Container;
  Block(Text, AColors.Muted, []);
  // 4.–7. Beschreibung und XMLDoc; ohne Inhalt keine Trennlinie und keine leeren Abschnitte.
  if FDetails.IsDeprecated or (FDetails.Summary <> '') or (FDetails.Returns <> '') or
    (Length(FDetails.Params) > 0) or (Length(FDetails.Exceptions) > 0) or (FDetails.Remarks <> '') then
  begin
    Separator;
    if FDetails.IsDeprecated then
      if FDetails.DeprecatedText <> '' then
        Block('Veraltet: ' + FDetails.DeprecatedText, AColors.Warn, [])
      else
        Block('Veraltet.', AColors.Warn, []);
    Block(FDetails.Summary, AColors.Text, []);
    ACanvas.Font := AFont;
    ACanvas.Font.Style := [fsBold];
    NameWidth := 0;
    for Entry in FDetails.Params do
      NameWidth := Max(NameWidth, ACanvas.TextWidth(Entry.Name));
    if FDetails.Returns <> '' then
      NameWidth := Max(NameWidth, ACanvas.TextWidth('→'));
    NameWidth := Min(NameWidth, (Right - Left) div 3);
    // Exceptions eigene Spalte: lange Klassennamen sollen die Parameter nicht auseinanderziehen.
    ExceptionWidth := 0;
    for Entry in FDetails.Exceptions do
      ExceptionWidth := Max(ExceptionWidth, ACanvas.TextWidth('! ' + Entry.Name));
    ExceptionWidth := Min(ExceptionWidth, (Right - Left) div 2);
    ACanvas.Font.Style := [];
    for Entry in FDetails.Params do
      Entry2(Entry.Name, Entry.Text, AColors.Accent, NameWidth);
    if FDetails.Returns <> '' then
      Entry2('→', FDetails.Returns, AColors.Accent, NameWidth);
    for Entry in FDetails.Exceptions do
      Entry2('! ' + Entry.Name, Entry.Text, AColors.Error, ExceptionWidth);
    if FDetails.Remarks <> '' then
    begin
      Separator;
      Block(FDetails.Remarks, AColors.Muted, [], 3);
    end;
  end;
  ACanvas.Brush.Style := bsSolid;
  Result := Y - ABounds.Top + Scale(5);
end;

end.
