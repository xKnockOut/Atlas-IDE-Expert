unit Atlas.UI.EditorToolbar.Glyphs;

// Atlas-Editorleiste (#1101): zeichnet die Vektorsymbole aus
// Atlas.Core.EditorToolbar.Glyphs geglättet in jeder Größe. Ohne GDI+: Das
// Symbol entsteht vierfach vergrößert mit runden Linienenden in einer Bitmap
// auf der Hintergrundfarbe und wird mit HALFTONE auf die Zielgröße
// verkleinert. So skaliert es mit der DPI des Editors (16 px bei 100 %) und
// nimmt Vorder- und Hintergrund aus dem IDE-Thema. Letter zeichnet den ersten
// Buchstaben in einem abgerundeten Rahmen.

interface

uses
  Winapi.Windows,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.EditorToolbar.Icons;

type
  TAtlasGlyphPainter = class
  public
    /// <summary>Symbol AIcon in ARect (quadratisch) mit Linienfarbe AFore auf ABack; bei Letter ALetter.</summary>
    class procedure Draw(ACanvas: TCanvas; AIcon: TAtlasToolbarIcon; const ARect: TRect; AFore, ABack: TColor;
      const ALetter: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.EditorToolbar.Glyphs;

const
  /// <summary>Überabtastung für die Glättung.</summary>
  Factor = 4;

procedure DrawLetter(ACanvas: TCanvas; const ARect: TRect; AFore: TColor; const ALetter: string);
var
  Box: TRect;
  Text: string;
  Radius: Integer;
begin
  Box := ARect;
  InflateRect(Box, -Max(1, ARect.Width div 16), -Max(1, ARect.Height div 16));
  Radius := Max(2, ARect.Width div 4);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := AFore;
  ACanvas.Pen.Width := Max(1, ARect.Width div 14);
  ACanvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, Radius, Radius);
  Text := UpperCase(Copy(Trim(ALetter), 1, 1));
  if Text = '' then
    Text := '?';
  ACanvas.Font.Color := AFore;
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Height := -Round(Box.Height * 0.7);
  DrawText(ACanvas.Handle, PChar(Text), -1, Box, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  ACanvas.Pen.Width := 1;
end;

class procedure TAtlasGlyphPainter.Draw(ACanvas: TCanvas; AIcon: TAtlasToolbarIcon; const ARect: TRect; AFore,
  ABack: TColor; const ALetter: string);
var
  Shapes: TArray<TAtlasGlyphShape>;
  Shape: TAtlasGlyphShape;
  Bitmap: TBitmap;
  Size, Index: Integer;
  Scale: Single;
  Points: array of TPoint;
  Brush: TLogBrush;
  Pen, OldPen: HPEN;
  Fill, OldBrush: HBRUSH;
  Fore: COLORREF;
  Origin: TPoint;
begin
  Shapes := TAtlasGlyphs.Shapes(AIcon);
  if Length(Shapes) = 0 then
  begin
    DrawLetter(ACanvas, ARect, AFore, ALetter);
    Exit;
  end;
  Size := Max(1, Min(ARect.Width, ARect.Height));
  Fore := ColorToRGB(AFore);
  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf24bit;
    Bitmap.SetSize(Size * Factor, Size * Factor);
    Bitmap.Canvas.Brush.Color := ABack;
    Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
    Scale := Size * Factor / TAtlasGlyphs.Size;
    Brush.lbStyle := BS_SOLID;
    Brush.lbColor := Fore;
    Brush.lbHatch := 0;
    Pen := ExtCreatePen(PS_GEOMETRIC or PS_SOLID or PS_ENDCAP_ROUND or PS_JOIN_ROUND,
      Max(1, Round(TAtlasGlyphs.StrokeWidth * Scale)), Brush, 0, nil);
    Fill := CreateSolidBrush(Fore);
    OldPen := SelectObject(Bitmap.Canvas.Handle, Pen);
    OldBrush := SelectObject(Bitmap.Canvas.Handle, GetStockObject(NULL_BRUSH));
    try
      for Shape in Shapes do
      begin
        SetLength(Points, Length(Shape.Points));
        for Index := 0 to High(Shape.Points) do
          Points[Index] := Point(Round(Shape.Points[Index].X * Scale), Round(Shape.Points[Index].Y * Scale));
        if Shape.Filled then
        begin
          SelectObject(Bitmap.Canvas.Handle, Fill);
          Polygon(Bitmap.Canvas.Handle, Points[0], Length(Points));
          SelectObject(Bitmap.Canvas.Handle, GetStockObject(NULL_BRUSH));
        end
        else if Shape.Closed then
          Polygon(Bitmap.Canvas.Handle, Points[0], Length(Points))
        else
          Polyline(Bitmap.Canvas.Handle, Points[0], Length(Points));
      end;
    finally
      SelectObject(Bitmap.Canvas.Handle, OldBrush);
      SelectObject(Bitmap.Canvas.Handle, OldPen);
      DeleteObject(Fill);
      DeleteObject(Pen);
    end;
    // HALFTONE mittelt die Pixel: glatte Kanten ohne GDI+.
    SetStretchBltMode(ACanvas.Handle, HALFTONE);
    SetBrushOrgEx(ACanvas.Handle, 0, 0, @Origin);
    StretchBlt(ACanvas.Handle, ARect.Left, ARect.Top, Size, Size, Bitmap.Canvas.Handle, 0, 0, Bitmap.Width,
      Bitmap.Height, SRCCOPY);
    SetBrushOrgEx(ACanvas.Handle, Origin.X, Origin.Y, nil);
  finally
    Bitmap.Free;
  end;
end;

end.
