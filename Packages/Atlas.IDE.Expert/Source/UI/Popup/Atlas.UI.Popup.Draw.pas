unit Atlas.UI.Popup.Draw;

// Gemeinsame Zeichenbausteine der Popups (D-07): Farbumwandlung, Maße der
// Chips und Tags (einheitlich Innenabstand 12, Radius 4 in logischen Pixeln),
// Daumen der Scrollleisten (Muted über Fläche, AtlasMixThumb) und Trennlinie.
// Bisher hatte jedes Fenster eigene Kopien mit leicht abweichenden Werten.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette;

type
  TAtlasDraw = class
  public const
    /// <summary>Innenabstand links und rechts zusammen (logische Pixel) für Chips und Tags.</summary>
    ChipPad = 12;
    /// <summary>Eckenradius (logische Pixel) für Chips und Tags.</summary>
    ChipRadius = 4;
  public
    /// <summary>Farbe des Scroll-Daumens.</summary>
    class function ThumbColor(const AColors: TAtlasColors): TAtlasColor; static;
    /// <summary>Daumen einer Scrollleiste in ARect; ARadius in Gerätepixeln, 0 = eckig.</summary>
    class procedure Thumb(ACanvas: TCanvas; const ARect: TRect; const AColors: TAtlasColors;
      ARadius: Integer); static;
    /// <summary>Waagrechte Trennlinie von ALeft bis ARight auf Höhe AY.</summary>
    class procedure Separator(ACanvas: TCanvas; ALeft, ARight, AY: Integer; AColor: TAtlasColor); static;
  end;

/// <summary>TColor zur Atlas-Farbe (gleiches Format); eine Stelle für alle Popups.</summary>
function ToColor(AColor: TAtlasColor): TColor;

implementation

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasDraw }

class function TAtlasDraw.ThumbColor(const AColors: TAtlasColors): TAtlasColor;
begin
  Result := TAtlasColorMath.Mix(AColors.Muted, AColors.Surface, AtlasMixThumb);
end;

class procedure TAtlasDraw.Thumb(ACanvas: TCanvas; const ARect: TRect; const AColors: TAtlasColors;
  ARadius: Integer);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ToColor(ThumbColor(AColors));
  if ARadius <= 0 then
  begin
    ACanvas.FillRect(ARect);
    Exit;
  end;
  ACanvas.Pen.Style := psClear;
  // Bei psClear zeichnet RoundRect ein Pixel kleiner; deshalb +1.
  ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right + 1, ARect.Bottom + 1, 2 * ARadius, 2 * ARadius);
  ACanvas.Pen.Style := psSolid;
end;

class procedure TAtlasDraw.Separator(ACanvas: TCanvas; ALeft, ARight, AY: Integer; AColor: TAtlasColor);
begin
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Color := ToColor(AColor);
  ACanvas.MoveTo(ALeft, AY);
  ACanvas.LineTo(ARight, AY);
end;

end.
