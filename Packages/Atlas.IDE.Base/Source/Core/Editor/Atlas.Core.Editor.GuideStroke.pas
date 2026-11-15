unit Atlas.Core.Editor.GuideStroke;

// Blocklinien in einer Zeile (#514, #653), ohne VCL und Open Tools API: wo der Strich steht und wie er endet.
// - Erste Zeile unter dem mitlaufenden Kopf: Ist das Element der Linie dahinter verschwunden, beginnt die Linie
//   hier spitz (TaperTop).
// - Letzte sichtbare Zeile: Läuft die Linie darunter weiter, endet sie spitz (TaperBottom). Genau eine Zeile
//   läuft aus: die angeschnittene letzte, wenn mindestens die Hälfte zu sehen ist, sonst die vorletzte; im Rest
//   darunter dann nichts (Skip), sonst begänne die Linie dort wieder breit.
// - Blöcke ab Spalte 1 (procedure … end): Linie knapp links vom Text, nicht durch das erste Zeichen.

{$SCOPEDENUMS ON}

interface

type
  /// <summary>Wie eine Blocklinie in einer Zeile endet: als Linie, spitz von oben (unter dem mitlaufenden Kopf),
  /// spitz nach unten (letzte sichtbare Zeile) oder gar nicht (Rest unter der letzten Zeile).</summary>
  TAtlasGuideEnd = (Line, TaperTop, TaperBottom, Skip);

  /// <summary>Lage einer Zeile und einer Linie darin.</summary>
  TAtlasGuideRow = record
    /// <summary>Zeile des Öffners bzw. des Schließers der Linie.</summary>
    First: Boolean;
    Last: Boolean;
    /// <summary>Erste Zeile unter dem Kopf, und dessen Linie läuft hier spitz an.</summary>
    TaperBelowHeader: Boolean;
    /// <summary>Oberer und unterer Rand der Zeile und Höhe des Editors in Pixeln.</summary>
    Top: Integer;
    Bottom: Integer;
    ClientHeight: Integer;
  end;

  TAtlasGuideStroke = record
  public const
    /// <summary>Abstand des Strichs vor der Zelle: ein Drittel ihrer Breite, mindestens cMinGap Pixel.</summary>
    cGapDivisor = 3;
    cMinGap = 2;
  public
    /// <summary>Bildschirmzeile (0-basiert) einer Zeile mit ATop und AHeight; -1 ohne Höhe.</summary>
    class function RowIndex(ATop, AHeight: Integer): Integer; static;
    /// <summary>Zeile ARow liegt unter dem mitlaufenden Kopf mit ACovered Zeilen.</summary>
    class function UnderHeader(ARow, ACovered: Integer): Boolean; static;
    /// <summary>Wie die Linie in der Zeile endet.</summary>
    class function EndOf(const ARow: TAtlasGuideRow): TAtlasGuideEnd; static;
    /// <summary>Waagrechte Lage des Strichs: vor der Zelle ACellLeft/ACellWidth der Spalte, mit der Stiftbreite
    /// APenWidth mittig; nie weiter links als AMargin Pixel vor dem Code (ACodeLeft, ACodeRight; ohne Code
    /// ACodeRight &lt;= ACodeLeft).</summary>
    class function StrokeX(ACellLeft, ACellWidth, APenWidth, ACodeLeft, ACodeRight, AMargin: Integer): Integer;
      static;
  end;

implementation

uses
  System.Math;

{ TAtlasGuideStroke }

class function TAtlasGuideStroke.RowIndex(ATop, AHeight: Integer): Integer;
begin
  Result := -1;
  if AHeight > 0 then
  begin
    Result := (ATop + AHeight div 2) div AHeight;
  end;
end;

class function TAtlasGuideStroke.UnderHeader(ARow, ACovered: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow < ACovered);
end;

class function TAtlasGuideStroke.EndOf(const ARow: TAtlasGuideRow): TAtlasGuideEnd;
var
  mHalf: Integer;
begin
  Result := TAtlasGuideEnd.Line;
  if ARow.First then
  begin
    Exit;
  end;
  mHalf := (ARow.Bottom - ARow.Top) div 2;
  if ARow.TaperBelowHeader then
  begin
    Result := TAtlasGuideEnd.TaperTop;
  end
  else if ARow.ClientHeight - ARow.Top < mHalf then
  begin
    Result := TAtlasGuideEnd.Skip;
  end
  else if not ARow.Last and (ARow.Bottom + mHalf > ARow.ClientHeight) then
  begin
    Result := TAtlasGuideEnd.TaperBottom;
  end;
end;

class function TAtlasGuideStroke.StrokeX(ACellLeft, ACellWidth, APenWidth, ACodeLeft, ACodeRight,
  AMargin: Integer): Integer;
var
  mMinX: Integer;
begin
  Result := ACellLeft - Max(cMinGap, ACellWidth div cGapDivisor) - (APenWidth - 1) div 2;
  mMinX := ACodeLeft - AMargin + APenWidth div 2;
  if (ACodeRight > ACodeLeft) and (Result < mMinX) then
  begin
    Result := mMinX;
  end;
end;

end.
