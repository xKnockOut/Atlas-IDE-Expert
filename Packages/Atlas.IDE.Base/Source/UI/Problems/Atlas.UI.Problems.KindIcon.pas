unit Atlas.UI.Problems.KindIcon;

// Symbole der Befundarten aus dem Fenster „Atlas-Prüfung“ (#909): rotes Kreuz
// im Kreis (Fehler), gelb-oranges Dreieck mit Ausrufezeichen (Warnung), blauer
// Kreis mit „i“ (Hinweis). Eine Stelle für die Bildliste des Fensters und die
// Zähler der Atlas-Statusleiste (#1155).
// Farben aus den Signalfarben der Fläche, auf der das Symbol liegt (#1255):
// im hellen Design kräftige Füllung mit dunklem Rand (das gelbe Dreieck hatte
// vorher auf Weiß nur 1,8 : 1), im dunklen helle Füllung mit dunklem Zeichen.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Style.Signal;

type
  TAtlasFindingIcon = class
  public
    /// <summary>Signalfarbe der Art: Fehler, Warnung, Hinweis.</summary>
    class function SignalOf(AKind: TAtlasFindingKind): TAtlasSignalKind; static;
    /// <summary>Symbol in das Quadrat oben links in ARect mit Fill, Ring und Mark von ASignal.</summary>
    class procedure Draw(ACanvas: TCanvas; const ARect: TRect; AKind: TAtlasFindingKind;
      const ASignal: TAtlasSignal); overload; static;
    /// <summary>Symbol in das Quadrat oben links in ARect: Fläche AFill, Rand ARing, Zeichen AMark (Kreuz,
    /// Ausrufezeichen, „i“).</summary>
    class procedure Draw(ACanvas: TCanvas; const ARect: TRect; AKind: TAtlasFindingKind;
      AFill, ARing, AMark: TColor); overload; static;
  end;

implementation

uses
  System.Math;

class function TAtlasFindingIcon.SignalOf(AKind: TAtlasFindingKind): TAtlasSignalKind;
begin
  case AKind of
    TAtlasFindingKind.Error:
      Result := TAtlasSignalKind.Error;
    TAtlasFindingKind.Warning:
      Result := TAtlasSignalKind.Warn;
  else
    Result := TAtlasSignalKind.Info;
  end;
end;

class procedure TAtlasFindingIcon.Draw(ACanvas: TCanvas; const ARect: TRect; AKind: TAtlasFindingKind;
  const ASignal: TAtlasSignal);
begin
  // TAtlasColor hat die Bytefolge von TColor ($00BBGGRR).
  Draw(ACanvas, ARect, AKind, TColor(ASignal.Fill), TColor(ASignal.Ring), TColor(ASignal.Mark));
end;

class procedure TAtlasFindingIcon.Draw(ACanvas: TCanvas; const ARect: TRect; AKind: TAtlasFindingKind;
  AFill, ARing, AMark: TColor);
var
  mSize, mPad, X, Y: Integer;
  mPoints: array[0..2] of TPoint;
begin
  mSize := Min(ARect.Width, ARect.Height);
  if mSize <= 0 then
  begin
    Exit;
  end;
  X := ARect.Left;
  Y := ARect.Top;
  mPad := mSize div 8;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := AFill;
  // Rand dünn (1 px bei 16 px), Zeichen kräftig.
  ACanvas.Pen.Color := ARing;
  ACanvas.Pen.Width := Max(1, mSize div 14);
  case AKind of
    TAtlasFindingKind.Error:
      begin
        // Rotes Kreuz im Kreis.
        ACanvas.Ellipse(X + mPad, Y + mPad, X + mSize - mPad, Y + mSize - mPad);
        ACanvas.Pen.Width := Max(1, mSize div 8);
        ACanvas.Pen.Color := AMark;
        ACanvas.MoveTo(X + mSize div 3, Y + mSize div 3);
        ACanvas.LineTo(X + mSize - mSize div 3, Y + mSize - mSize div 3);
        ACanvas.MoveTo(X + mSize - mSize div 3 - 1, Y + mSize div 3);
        ACanvas.LineTo(X + mSize div 3 - 1, Y + mSize - mSize div 3);
      end;
    TAtlasFindingKind.Warning:
      begin
        // Gelb-oranges Dreieck mit Ausrufezeichen.
        mPoints[0] := Point(X + mSize div 2, Y + mPad);
        mPoints[1] := Point(X + mSize - mPad, Y + mSize - mPad);
        mPoints[2] := Point(X + mPad, Y + mSize - mPad);
        ACanvas.Polygon(mPoints);
        ACanvas.Pen.Width := Max(1, mSize div 8);
        ACanvas.Pen.Color := AMark;
        ACanvas.MoveTo(X + mSize div 2, Y + mSize * 2 div 5);
        ACanvas.LineTo(X + mSize div 2, Y + mSize * 2 div 3);
        ACanvas.MoveTo(X + mSize div 2, Y + mSize - 2 * mPad - 1);
        ACanvas.LineTo(X + mSize div 2, Y + mSize - 2 * mPad);
      end;
  else
    begin
      // Blauer Kreis mit „i“.
      ACanvas.Ellipse(X + mPad, Y + mPad, X + mSize - mPad, Y + mSize - mPad);
      ACanvas.Pen.Width := Max(1, mSize div 8);
      ACanvas.Pen.Color := AMark;
      ACanvas.MoveTo(X + mSize div 2, Y + mSize * 2 div 5 + 1);
      ACanvas.LineTo(X + mSize div 2, Y + mSize - mSize div 4);
      ACanvas.MoveTo(X + mSize div 2, Y + mSize div 4);
      ACanvas.LineTo(X + mSize div 2, Y + mSize div 4 + 1);
    end;
  end;
  ACanvas.Pen.Width := 1;
end;

end.
