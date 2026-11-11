unit Atlas.Core.Designer.Measure;

// Maßlinien im Designer (#605), ohne VCL und Windows: Abstände einer
// Komponente zu ihren Nachbarn im selben Parent und zum Innenrand des
// Parents, alles auf Rechtecken in einem gemeinsamen Koordinatensystem (der
// Aufrufer rechnet vorher in die Designgröße der DFM um).
// - Nachbar in einer Richtung: Geschwister, die quer zur Richtung mit dem
//   Bezug überlappen und ganz jenseits seiner Kante liegen; der nächste
//   gewinnt. Ohne Nachbarn misst die Linie bis zum Innenrand (Client minus
//   Padding).
// - Gleiche Abstände: Kommt derselbe Abstand bei einem anderen Paar im
//   selben Parent vor (Nachbar–Nachbar oder Nachbar–Innenrand auf derselben
//   Achse), ist die Linie „gleich“; der Hinweis nennt, wo das Paar liegt
//   (oben, unten, links, rechts vom Bezug).
// - Größe: Breite und Höhe des Bezugs, dazu Geschwister mit gleicher Breite
//   bzw. Höhe.
// - Zwischen zwei Rechtecken (Alt-Taste): waagrechter und senkrechter Abstand
//   von Kante zu Kante; liegt eines im anderen, die vier Abstände zum Rand.

interface

uses
  System.Types;

type
  TAtlasMeasureItem = record
    Name: string;
    Bounds: TRect;
    class function Create(const AName: string; const ABounds: TRect): TAtlasMeasureItem; static;
  end;

{$SCOPEDENUMS ON}
  TAtlasMeasureSide = (Left, Top, Right, Bottom);
  /// <summary>Wo das Paar mit demselben Abstand liegt, vom Bezug aus gesehen.</summary>
  TAtlasMeasurePlace = (None, Above, Below, LeftOf, RightOf);
{$SCOPEDENUMS OFF}

  TAtlasMeasureLine = record
    Side: TAtlasMeasureSide;
    /// <summary>Anfang (an der Kante des Bezugs) und Ende der Linie.</summary>
    FromPoint: TPoint;
    ToPoint: TPoint;
    Distance: Integer;
    /// <summary>Nachbar am Ende; '' = Innenrand des Parents.</summary>
    Target: string;
    /// <summary>Derselbe Abstand kommt bei einem anderen Paar im Parent vor.</summary>
    Same: TAtlasMeasurePlace;
  end;

  TAtlasMeasureSize = record
    Width: Integer;
    Height: Integer;
    /// <summary>Geschwister mit gleicher Breite bzw. Höhe; '' ohne.</summary>
    SameWidth: string;
    SameHeight: string;
  end;

  TAtlasMeasure = class
  public
    /// <summary>Bis zu vier Linien von ASubject zu den nächsten Nachbarn in ASiblings (ohne den Bezug selbst) bzw.
    /// zum Innenrand AInner. Linien mit negativem Abstand (Überlappung) entfallen.</summary>
    class function Lines(const ASubject: TRect; const ASiblings: TArray<TAtlasMeasureItem>;
      const AInner: TRect): TArray<TAtlasMeasureLine>; static;
    /// <summary>Breite, Höhe und Geschwister gleicher Größe.</summary>
    class function Size(const ASubject: TRect; const ASiblings: TArray<TAtlasMeasureItem>): TAtlasMeasureSize;
      static;
    /// <summary>Abstände zwischen AFrom und ATarget (Alt-Taste): waagrecht und senkrecht von Kante zu Kante,
    /// enthält ATarget AFrom, die vier Abstände zu seinem Rand.</summary>
    class function Between(const AFrom, ATarget: TRect; const ATargetName: string): TArray<TAtlasMeasureLine>;
      static;
    /// <summary>Innenrand: AClient um das Padding verkleinert.</summary>
    class function Inner(const AClient: TRect; APadLeft, APadTop, APadRight, APadBottom: Integer): TRect; static;
    /// <summary>Text an der Linie: „8 px“, gleich „8 px wie oben“; APlaceTexts je Ort (None ungenutzt).</summary>
    class function Caption(const ALine: TAtlasMeasureLine; const APlaceTexts: array of string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasMeasureItem }

class function TAtlasMeasureItem.Create(const AName: string; const ABounds: TRect): TAtlasMeasureItem;
begin
  Result.Name := AName;
  Result.Bounds := ABounds;
end;

function Horizontal(ASide: TAtlasMeasureSide): Boolean;
begin
  Result := ASide in [TAtlasMeasureSide.Left, TAtlasMeasureSide.Right];
end;

/// <summary>Überlappen A und B quer zu ASide (bei Links/Rechts senkrecht, sonst waagrecht)?</summary>
function CrossOverlap(const A, B: TRect; ASide: TAtlasMeasureSide): Boolean;
begin
  if Horizontal(ASide) then
  begin
    Result := (B.Top < A.Bottom) and (B.Bottom > A.Top);
  end
  else
  begin
    Result := (B.Left < A.Right) and (B.Right > A.Left);
  end;
end;

/// <summary>Abstand von der Kante ASide von A bis B; negativ, wenn B nicht ganz jenseits liegt.</summary>
function Gap(const A, B: TRect; ASide: TAtlasMeasureSide): Integer;
begin
  case ASide of
    TAtlasMeasureSide.Left:
      Result := A.Left - B.Right;
    TAtlasMeasureSide.Top:
      Result := A.Top - B.Bottom;
    TAtlasMeasureSide.Right:
      Result := B.Left - A.Right;
  else
    Result := B.Top - A.Bottom;
  end;
end;

/// <summary>Abstand von der Kante ASide von A bis zum Innenrand AInner.</summary>
function EdgeGap(const A, AInner: TRect; ASide: TAtlasMeasureSide): Integer;
begin
  case ASide of
    TAtlasMeasureSide.Left:
      Result := A.Left - AInner.Left;
    TAtlasMeasureSide.Top:
      Result := A.Top - AInner.Top;
    TAtlasMeasureSide.Right:
      Result := AInner.Right - A.Right;
  else
    Result := AInner.Bottom - A.Bottom;
  end;
end;

/// <summary>Index des nächsten Nachbarn von A in ASide unter AItems ohne ASkip; -1 ohne.</summary>
function Nearest(const A: TRect; const AItems: TArray<TAtlasMeasureItem>; ASide: TAtlasMeasureSide;
  ASkip: Integer): Integer;
var
  mIndex, mGap, mBest: Integer;
begin
  Result := -1;
  mBest := MaxInt;
  for mIndex := 0 to High(AItems) do
  begin
    if (mIndex = ASkip) or not CrossOverlap(A, AItems[mIndex].Bounds, ASide) then
    begin
      Continue;
    end;
    mGap := Gap(A, AItems[mIndex].Bounds, ASide);
    if (mGap >= 0) and (mGap < mBest) then
    begin
      mBest := mGap;
      Result := mIndex;
    end;
  end;
end;

/// <summary>Mitte des quer überlappenden Bereichs von A und B (bei Links/Rechts y, sonst x).</summary>
function CrossMiddle(const A, B: TRect; ASide: TAtlasMeasureSide): Integer;
begin
  if Horizontal(ASide) then
  begin
    Result := (Max(A.Top, B.Top) + Min(A.Bottom, B.Bottom)) div 2;
  end
  else
  begin
    Result := (Max(A.Left, B.Left) + Min(A.Right, B.Right)) div 2;
  end;
end;

/// <summary>Linie von der Kante ASide von A aus, ADistance lang, quer an ACross.</summary>
function MakeLine(const A: TRect; ASide: TAtlasMeasureSide; ADistance, ACross: Integer;
  const ATarget: string): TAtlasMeasureLine;
begin
  Result := Default(TAtlasMeasureLine);
  Result.Side := ASide;
  Result.Distance := ADistance;
  Result.Target := ATarget;
  case ASide of
    TAtlasMeasureSide.Left:
      begin
        Result.FromPoint := Point(A.Left, ACross);
        Result.ToPoint := Point(A.Left - ADistance, ACross);
      end;
    TAtlasMeasureSide.Top:
      begin
        Result.FromPoint := Point(ACross, A.Top);
        Result.ToPoint := Point(ACross, A.Top - ADistance);
      end;
    TAtlasMeasureSide.Right:
      begin
        Result.FromPoint := Point(A.Right, ACross);
        Result.ToPoint := Point(A.Right + ADistance, ACross);
      end;
  else
    begin
      Result.FromPoint := Point(ACross, A.Bottom);
      Result.ToPoint := Point(ACross, A.Bottom + ADistance);
    end;
  end;
end;

/// <summary>Lage von AOther zum Bezug: die größere Verschiebung der Mitten entscheidet.</summary>
function PlaceOf(const ASubject, AOther: TRect): TAtlasMeasurePlace;
var
  mDX, mDY: Integer;
begin
  mDX := (AOther.Left + AOther.Right) div 2 - (ASubject.Left + ASubject.Right) div 2;
  mDY := (AOther.Top + AOther.Bottom) div 2 - (ASubject.Top + ASubject.Bottom) div 2;
  if Abs(mDY) >= Abs(mDX) then
  begin
    if mDY < 0 then
    begin
      Exit(TAtlasMeasurePlace.Above);
    end;
    Exit(TAtlasMeasurePlace.Below);
  end;
  if mDX < 0 then
  begin
    Exit(TAtlasMeasurePlace.LeftOf);
  end;
  Result := TAtlasMeasurePlace.RightOf;
end;

/// <summary>Gibt es unter den Geschwistern ein Paar auf derselben Achse wie ASide mit Abstand ADistance? Liefert
/// die Lage des nächstgelegenen solchen Paars, sonst None.</summary>
function SamePlace(const ASubject: TRect; const ASiblings: TArray<TAtlasMeasureItem>; const AInner: TRect;
  ASide: TAtlasMeasureSide; ADistance: Integer): TAtlasMeasurePlace;
var
  mIndex, mOther, mBest, mDistance: Integer;
  mSide: TAtlasMeasureSide;
  mBounds: TRect;
begin
  Result := TAtlasMeasurePlace.None;
  mBest := MaxInt;
  for mIndex := 0 to High(ASiblings) do
  begin
    mBounds := ASiblings[mIndex].Bounds;
    for mSide := Low(TAtlasMeasureSide) to High(TAtlasMeasureSide) do
    begin
      // Gleiche Achse: waagrechte Abstände nur mit waagrechten vergleichen.
      if Horizontal(mSide) <> Horizontal(ASide) then
      begin
        Continue;
      end;
      mOther := Nearest(mBounds, ASiblings, mSide, mIndex);
      if (mOther >= 0) and (Gap(mBounds, ASiblings[mOther].Bounds, mSide) = ADistance) or
        (mOther < 0) and (mSide = ASide) and (EdgeGap(mBounds, AInner, mSide) = ADistance) then
      begin
        mDistance := Abs(mBounds.Left - ASubject.Left) + Abs(mBounds.Top - ASubject.Top);
        if mDistance < mBest then
        begin
          mBest := mDistance;
          Result := PlaceOf(ASubject, mBounds);
        end;
      end;
    end;
  end;
end;

{ TAtlasMeasure }

class function TAtlasMeasure.Lines(const ASubject: TRect; const ASiblings: TArray<TAtlasMeasureItem>;
  const AInner: TRect): TArray<TAtlasMeasureLine>;
var
  mSide: TAtlasMeasureSide;
  mIndex, mDistance, mCross: Integer;
  mLine: TAtlasMeasureLine;
begin
  Result := nil;
  for mSide := Low(TAtlasMeasureSide) to High(TAtlasMeasureSide) do
  begin
    mIndex := Nearest(ASubject, ASiblings, mSide, -1);
    if mIndex >= 0 then
    begin
      mDistance := Gap(ASubject, ASiblings[mIndex].Bounds, mSide);
      mCross := CrossMiddle(ASubject, ASiblings[mIndex].Bounds, mSide);
      mLine := MakeLine(ASubject, mSide, mDistance, mCross, ASiblings[mIndex].Name);
    end
    else
    begin
      mDistance := EdgeGap(ASubject, AInner, mSide);
      if mDistance < 0 then
      begin
        Continue;
      end;
      mCross := CrossMiddle(ASubject, ASubject, mSide);
      mLine := MakeLine(ASubject, mSide, mDistance, mCross, '');
    end;
    mLine.Same := SamePlace(ASubject, ASiblings, AInner, mSide, mDistance);
    Result := Result + [mLine];
  end;
end;

class function TAtlasMeasure.Size(const ASubject: TRect;
  const ASiblings: TArray<TAtlasMeasureItem>): TAtlasMeasureSize;
var
  mItem: TAtlasMeasureItem;
begin
  Result := Default(TAtlasMeasureSize);
  Result.Width := ASubject.Width;
  Result.Height := ASubject.Height;
  for mItem in ASiblings do
  begin
    if (Result.SameWidth = '') and (mItem.Bounds.Width = Result.Width) then
    begin
      Result.SameWidth := mItem.Name;
    end;
    if (Result.SameHeight = '') and (mItem.Bounds.Height = Result.Height) then
    begin
      Result.SameHeight := mItem.Name;
    end;
  end;
end;

class function TAtlasMeasure.Between(const AFrom, ATarget: TRect;
  const ATargetName: string): TArray<TAtlasMeasureLine>;
var
  mSide: TAtlasMeasureSide;
  mDistance: Integer;
begin
  Result := nil;
  if ATarget.Contains(AFrom) then
  begin
    for mSide := Low(TAtlasMeasureSide) to High(TAtlasMeasureSide) do
    begin
      mDistance := EdgeGap(AFrom, ATarget, mSide);
      Result := Result + [MakeLine(AFrom, mSide, mDistance, CrossMiddle(AFrom, AFrom, mSide), ATargetName)];
    end;
    Exit;
  end;
  for mSide := Low(TAtlasMeasureSide) to High(TAtlasMeasureSide) do
  begin
    mDistance := Gap(AFrom, ATarget, mSide);
    if mDistance < 0 then
    begin
      Continue;
    end;
    // Ohne Überlappung quer zur Richtung: Linie auf Höhe bzw. Breite der Mitte des Bezugs.
    if CrossOverlap(AFrom, ATarget, mSide) then
    begin
      Result := Result + [MakeLine(AFrom, mSide, mDistance, CrossMiddle(AFrom, ATarget, mSide), ATargetName)];
    end
    else
    begin
      Result := Result + [MakeLine(AFrom, mSide, mDistance, CrossMiddle(AFrom, AFrom, mSide), ATargetName)];
    end;
  end;
end;

class function TAtlasMeasure.Inner(const AClient: TRect; APadLeft, APadTop, APadRight, APadBottom: Integer): TRect;
begin
  Result := Rect(AClient.Left + APadLeft, AClient.Top + APadTop, AClient.Right - APadRight,
    AClient.Bottom - APadBottom);
end;

class function TAtlasMeasure.Caption(const ALine: TAtlasMeasureLine; const APlaceTexts: array of string): string;
var
  mPlace: Integer;
begin
  Result := IntToStr(ALine.Distance) + ' px';
  mPlace := Ord(ALine.Same);
  if (ALine.Same <> TAtlasMeasurePlace.None) and (mPlace <= High(APlaceTexts)) then
  begin
    Result := Result + ' ' + APlaceTexts[mPlace];
  end;
end;

end.
