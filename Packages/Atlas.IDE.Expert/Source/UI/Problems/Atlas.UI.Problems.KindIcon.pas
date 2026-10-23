unit Atlas.UI.Problems.KindIcon;

// Symbole der Befundarten aus dem Fenster „Atlas-Prüfung“ (#909): rotes Kreuz
// im Kreis (Fehler), gelb-oranges Dreieck mit Ausrufezeichen (Warnung), blauer
// Kreis mit „i“ (Hinweis). Eine Stelle für die Bildliste des Fensters und die
// Zähler der Atlas-Statusleiste (#1155).

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Problems.Findings;

type
  TAtlasFindingIcon = class
  public
    /// <summary>Grundfarbe der Art (Fläche des Symbols).</summary>
    class function KindColor(AKind: TAtlasFindingKind): TColor; static;
    /// <summary>Symbol in das Quadrat oben links in ARect: Fläche AColor, Zeichen AMark (Kreuz, „i“) bzw.
    /// AWarningMark (Ausrufezeichen auf dem Dreieck).</summary>
    class procedure Draw(ACanvas: TCanvas; const ARect: TRect; AKind: TAtlasFindingKind;
      AColor, AMark, AWarningMark: TColor); static;
  end;

implementation

uses
  System.Math;

const
  KindColors: array[TAtlasFindingKind] of TColor = ($003C3CD8, $0020A8F0, $00D08030);

class function TAtlasFindingIcon.KindColor(AKind: TAtlasFindingKind): TColor;
begin
  Result := KindColors[AKind];
end;

class procedure TAtlasFindingIcon.Draw(ACanvas: TCanvas; const ARect: TRect; AKind: TAtlasFindingKind;
  AColor, AMark, AWarningMark: TColor);
var
  Size, Pad, X, Y: Integer;
  Points: array[0..2] of TPoint;
begin
  Size := Min(ARect.Width, ARect.Height);
  if Size <= 0 then
    Exit;
  X := ARect.Left;
  Y := ARect.Top;
  Pad := Size div 8;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := AColor;
  ACanvas.Pen.Color := AColor;
  ACanvas.Pen.Width := Max(1, Size div 8);
  case AKind of
    TAtlasFindingKind.Error:
      begin
        // Rotes Kreuz im Kreis.
        ACanvas.Ellipse(X + Pad, Y + Pad, X + Size - Pad, Y + Size - Pad);
        ACanvas.Pen.Color := AMark;
        ACanvas.MoveTo(X + Size div 3, Y + Size div 3);
        ACanvas.LineTo(X + Size - Size div 3, Y + Size - Size div 3);
        ACanvas.MoveTo(X + Size - Size div 3 - 1, Y + Size div 3);
        ACanvas.LineTo(X + Size div 3 - 1, Y + Size - Size div 3);
      end;
    TAtlasFindingKind.Warning:
      begin
        // Gelb-oranges Dreieck mit Ausrufezeichen.
        Points[0] := Point(X + Size div 2, Y + Pad);
        Points[1] := Point(X + Size - Pad, Y + Size - Pad);
        Points[2] := Point(X + Pad, Y + Size - Pad);
        ACanvas.Polygon(Points);
        ACanvas.Pen.Color := AWarningMark;
        ACanvas.MoveTo(X + Size div 2, Y + Size * 2 div 5);
        ACanvas.LineTo(X + Size div 2, Y + Size * 2 div 3);
        ACanvas.MoveTo(X + Size div 2, Y + Size - 2 * Pad - 1);
        ACanvas.LineTo(X + Size div 2, Y + Size - 2 * Pad);
      end;
  else
    begin
      // Blauer Kreis mit „i“.
      ACanvas.Ellipse(X + Pad, Y + Pad, X + Size - Pad, Y + Size - Pad);
      ACanvas.Pen.Color := AMark;
      ACanvas.MoveTo(X + Size div 2, Y + Size * 2 div 5 + 1);
      ACanvas.LineTo(X + Size div 2, Y + Size - Size div 4);
      ACanvas.MoveTo(X + Size div 2, Y + Size div 4);
      ACanvas.LineTo(X + Size div 2, Y + Size div 4 + 1);
    end;
  end;
  ACanvas.Pen.Width := 1;
end;

end.
