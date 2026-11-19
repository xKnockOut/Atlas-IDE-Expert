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

const
  /// <summary>Teile der Größe des Symbols: Rand (ein Achtel), Ring (ein Vierzehntel, 1 px bei 16 px), Strich des
  /// Zeichens (ein Achtel), Abstand des Kreuzes (ein Drittel), Strich des Ausrufezeichens (von zwei Fünfteln bis zwei
  /// Dritteln) und Punkt bzw. Strich des „i“ (ab bzw. bis ein Viertel vom Rand).</summary>
  cPadShare = 8;
  cRingShare = 14;
  cStrokeShare = 8;
  cCrossShare = 3;
  cStemTopShare = 5;
  cStemBottomShare = 3;
  cDotShare = 4;

{ TAtlasFindingIcon }

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
  mPad := mSize div cPadShare;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := AFill;
  // Rand dünn (1 px bei 16 px), Zeichen kräftig.
  ACanvas.Pen.Color := ARing;
  ACanvas.Pen.Width := Max(1, mSize div cRingShare);
  case AKind of
    TAtlasFindingKind.Error:
      begin
        // Rotes Kreuz im Kreis.
        ACanvas.Ellipse(X + mPad, Y + mPad, X + mSize - mPad, Y + mSize - mPad);
        ACanvas.Pen.Width := Max(1, mSize div cStrokeShare);
        ACanvas.Pen.Color := AMark;
        ACanvas.MoveTo(X + mSize div cCrossShare, Y + mSize div cCrossShare);
        ACanvas.LineTo(X + mSize - mSize div cCrossShare, Y + mSize - mSize div cCrossShare);
        ACanvas.MoveTo(X + mSize - mSize div cCrossShare - 1, Y + mSize div cCrossShare);
        ACanvas.LineTo(X + mSize div cCrossShare - 1, Y + mSize - mSize div cCrossShare);
      end;
    TAtlasFindingKind.Warning:
      begin
        // Gelb-oranges Dreieck mit Ausrufezeichen.
        mPoints[0] := Point(X + mSize div 2, Y + mPad);
        mPoints[1] := Point(X + mSize - mPad, Y + mSize - mPad);
        mPoints[2] := Point(X + mPad, Y + mSize - mPad);
        ACanvas.Polygon(mPoints);
        ACanvas.Pen.Width := Max(1, mSize div cStrokeShare);
        ACanvas.Pen.Color := AMark;
        ACanvas.MoveTo(X + mSize div 2, Y + mSize * 2 div cStemTopShare);
        ACanvas.LineTo(X + mSize div 2, Y + mSize * 2 div cStemBottomShare);
        ACanvas.MoveTo(X + mSize div 2, Y + mSize - 2 * mPad - 1);
        ACanvas.LineTo(X + mSize div 2, Y + mSize - 2 * mPad);
      end;
  else
    begin
      // Blauer Kreis mit „i“.
      ACanvas.Ellipse(X + mPad, Y + mPad, X + mSize - mPad, Y + mSize - mPad);
      ACanvas.Pen.Width := Max(1, mSize div cStrokeShare);
      ACanvas.Pen.Color := AMark;
      ACanvas.MoveTo(X + mSize div 2, Y + mSize * 2 div cStemTopShare + 1);
      ACanvas.LineTo(X + mSize div 2, Y + mSize - mSize div cDotShare);
      ACanvas.MoveTo(X + mSize div 2, Y + mSize div cDotShare);
      ACanvas.LineTo(X + mSize div 2, Y + mSize div cDotShare + 1);
    end;
  end;
  ACanvas.Pen.Width := 1;
end;

end.
