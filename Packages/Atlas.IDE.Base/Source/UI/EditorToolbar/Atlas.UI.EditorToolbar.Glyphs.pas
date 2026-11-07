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
  cFactor = 4;

procedure DrawLetter(ACanvas: TCanvas; const ARect: TRect; AFore: TColor; const ALetter: string);
var
  mBox: TRect;
  mText: string;
  mRadius: Integer;
begin
  mBox := ARect;
  InflateRect(mBox, -Max(1, ARect.Width div 16), -Max(1, ARect.Height div 16));
  mRadius := Max(2, ARect.Width div 4);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := AFore;
  ACanvas.Pen.Width := Max(1, ARect.Width div 14);
  ACanvas.RoundRect(mBox.Left, mBox.Top, mBox.Right, mBox.Bottom, mRadius, mRadius);
  mText := UpperCase(Copy(Trim(ALetter), 1, 1));
  if mText = '' then
  begin
    mText := '?';
  end;
  ACanvas.Font.Color := AFore;
  ACanvas.Font.Style := [fsBold];
  ACanvas.Font.Height := -Round(mBox.Height * 0.7);
  DrawText(ACanvas.Handle, PChar(mText), -1, mBox, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  ACanvas.Pen.Width := 1;
end;

/// <summary>Punkte einer Form in Bitmap-Pixeln (AScale je Rastereinheit).</summary>
function ScaledPoints(const AShape: TAtlasGlyphShape; AScale: Single): TArray<TPoint>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AShape.Points));
  for mIndex := 0 to High(AShape.Points) do
  begin
    Result[mIndex] := Point(Round(AShape.Points[mIndex].X * AScale), Round(AShape.Points[mIndex].Y * AScale));
  end;
end;

/// <summary>Eine Form auf ADC; der Stift ist gewählt, gefüllte Formen wählen AFill für die Dauer des
/// Zeichnens.</summary>
procedure DrawShape(ADC: HDC; const AShape: TAtlasGlyphShape; AScale: Single; AFill: HBRUSH);
var
  mPoints: TArray<TPoint>;
begin
  mPoints := ScaledPoints(AShape, AScale);
  if Length(mPoints) = 0 then
  begin
    Exit;
  end;
  if AShape.Filled then
  begin
    SelectObject(ADC, AFill);
    Polygon(ADC, mPoints[0], Length(mPoints));
    SelectObject(ADC, GetStockObject(NULL_BRUSH));
  end
  else if AShape.Closed then
  begin
    Polygon(ADC, mPoints[0], Length(mPoints));
  end
  else
  begin
    Polyline(ADC, mPoints[0], Length(mPoints));
  end;
end;

/// <summary>Alle Formen mit runden Linienenden in Farbe AFore auf ABitmap; AScale je Rastereinheit.</summary>
procedure DrawShapes(ABitmap: TBitmap; const AShapes: TArray<TAtlasGlyphShape>; AScale: Single; AFore: COLORREF);
var
  mShape: TAtlasGlyphShape;
  mBrush: TLogBrush;
  mPen, mOldPen: HPEN;
  mFill, mOldBrush: HBRUSH;
begin
  mBrush.lbStyle := BS_SOLID;
  mBrush.lbColor := AFore;
  mBrush.lbHatch := 0;
  mPen := ExtCreatePen(PS_GEOMETRIC or PS_SOLID or PS_ENDCAP_ROUND or PS_JOIN_ROUND,
    Max(1, Round(TAtlasGlyphs.cStrokeWidth * AScale)), mBrush, 0, nil);
  mFill := CreateSolidBrush(AFore);
  mOldPen := SelectObject(ABitmap.Canvas.Handle, mPen);
  mOldBrush := SelectObject(ABitmap.Canvas.Handle, GetStockObject(NULL_BRUSH));
  try
    for mShape in AShapes do
    begin
      DrawShape(ABitmap.Canvas.Handle, mShape, AScale, mFill);
    end;
  finally
    SelectObject(ABitmap.Canvas.Handle, mOldBrush);
    SelectObject(ABitmap.Canvas.Handle, mOldPen);
    DeleteObject(mFill);
    DeleteObject(mPen);
  end;
end;

/// <summary>ABitmap auf ASize × ASize Pixel ab ATopLeft verkleinert; HALFTONE mittelt die Pixel: glatte Kanten
/// ohne GDI+.</summary>
procedure StretchSmooth(ACanvas: TCanvas; ABitmap: TBitmap; const ATopLeft: TPoint; ASize: Integer);
var
  mOrigin: TPoint;
begin
  SetStretchBltMode(ACanvas.Handle, HALFTONE);
  SetBrushOrgEx(ACanvas.Handle, 0, 0, @mOrigin);
  StretchBlt(ACanvas.Handle, ATopLeft.X, ATopLeft.Y, ASize, ASize, ABitmap.Canvas.Handle, 0, 0, ABitmap.Width,
    ABitmap.Height, SRCCOPY);
  SetBrushOrgEx(ACanvas.Handle, mOrigin.X, mOrigin.Y, nil);
end;

class procedure TAtlasGlyphPainter.Draw(ACanvas: TCanvas; AIcon: TAtlasToolbarIcon; const ARect: TRect; AFore,
  ABack: TColor; const ALetter: string);
var
  mShapes: TArray<TAtlasGlyphShape>;
  mBitmap: TBitmap;
  mSize: Integer;
begin
  mShapes := TAtlasGlyphs.Shapes(AIcon);
  if Length(mShapes) = 0 then
  begin
    DrawLetter(ACanvas, ARect, AFore, ALetter);
    Exit;
  end;
  mSize := Max(1, Min(ARect.Width, ARect.Height));
  mBitmap := TBitmap.Create;
  try
    mBitmap.PixelFormat := pf24bit;
    mBitmap.SetSize(mSize * cFactor, mSize * cFactor);
    mBitmap.Canvas.Brush.Color := ABack;
    mBitmap.Canvas.FillRect(Rect(0, 0, mBitmap.Width, mBitmap.Height));
    DrawShapes(mBitmap, mShapes, mSize * cFactor / TAtlasGlyphs.cSize, ColorToRGB(AFore));
    StretchSmooth(ACanvas, mBitmap, ARect.TopLeft, mSize);
  finally
    mBitmap.Free;
  end;
end;

end.
