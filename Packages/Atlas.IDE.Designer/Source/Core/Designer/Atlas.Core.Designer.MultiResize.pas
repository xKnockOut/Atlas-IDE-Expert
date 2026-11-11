unit Atlas.Core.Designer.MultiResize;

// Gemeinsame Größengriffe im Designer (#737), ohne VCL und Windows: neue
// Lage aller markierten Steuerelemente, wenn eins an einer Kante gezogen
// wird.
// - Kante Right/Bottom/Corner: rechte bzw. untere Kante bewegt sich;
//   Left/Top: die linke bzw. obere, die gegenüberliegende bleibt.
// - Modus Delta: alle ändern sich um denselben Betrag; Align: alle bekommen
//   dieselbe Kante wie das gezogene.
// - Mindestgröße je Steuerelement (sonst cMinSize); wer sie erreicht, bleibt
//   stehen, die anderen ziehen weiter mit.
// - Fixed (AutoSize, Align mit fester Größe) bleibt unverändert.
// - Raster: die gezogene Kante rastet am Raster ein (0 = ohne).
// - Nachbarn (Follow): nicht markierte Steuerelemente derselben Gruppe
//   (Elternelement), die ganz hinter einer bewegten Kante liegen und sich
//   quer mit dem Steuerelement überlappen, rücken um dessen Änderung mit; so
//   bleibt ihr Abstand.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasResizeEdge = (Right, Bottom, Corner, Left, Top);
  TAtlasResizeMode = (Delta, Align);
{$SCOPEDENUMS OFF}

  TAtlasResizeItem = record
    Bounds: TRect;
    MinWidth: Integer;
    MinHeight: Integer;
    /// <summary>AutoSize oder Align mit fester Größe: bleibt, gestrichelt umrandet.</summary>
    Fixed: Boolean;
    /// <summary>Elternelement; Nachbarn nur in derselben Gruppe.</summary>
    Group: Integer;
    class function Create(const ABounds: TRect; AMinWidth, AMinHeight: Integer; AFixed: Boolean;
      AGroup: Integer = 0): TAtlasResizeItem; static;
  end;

  TAtlasResizeNeighbour = record
    Bounds: TRect;
    Group: Integer;
    class function Create(const ABounds: TRect; AGroup: Integer = 0): TAtlasResizeNeighbour; static;
  end;

  TAtlasResizeResult = record
    Items: TArray<TRect>;
    Neighbours: TArray<TRect>;
    /// <summary>Zahl der Steuerelemente, deren Größe sich geändert hat.</summary>
    Changed: Integer;
  end;

  TAtlasMultiResize = class
  public const
    cMinSize = 8;
    cModeDelta = 'delta';
    cModeAlign = 'align';
  public
    /// <summary>AItems[ADragged] wird an AEdge um ADelta gezogen (Bildschirmpixel = Pixel im Formular).</summary>
    class function Apply(const AItems: TArray<TAtlasResizeItem>; const ANeighbours: TArray<TAtlasResizeNeighbour>;
      ADragged: Integer; AEdge: TAtlasResizeEdge; const ADelta: TPoint; AMode: TAtlasResizeMode; AGrid: Integer;
      AFollow: Boolean): TAtlasResizeResult; static;
    /// <summary>Wirkt die Kante waagerecht (Breite) bzw. senkrecht (Höhe)?</summary>
    class function Horizontal(AEdge: TAtlasResizeEdge): Boolean; static;
    class function Vertical(AEdge: TAtlasResizeEdge): Boolean; static;
    /// <summary>Gegenkante bei Alt: Right → Left, Bottom → Top, Corner bleibt.</summary>
    class function Opposite(AEdge: TAtlasResizeEdge): TAtlasResizeEdge; static;
    class function ModeOf(const AText: string): TAtlasResizeMode; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasResizeItem }

class function TAtlasResizeItem.Create(const ABounds: TRect; AMinWidth, AMinHeight: Integer; AFixed: Boolean;
  AGroup: Integer): TAtlasResizeItem;
begin
  Result.Bounds := ABounds;
  Result.MinWidth := AMinWidth;
  Result.MinHeight := AMinHeight;
  Result.Fixed := AFixed;
  Result.Group := AGroup;
end;

{ TAtlasResizeNeighbour }

class function TAtlasResizeNeighbour.Create(const ABounds: TRect; AGroup: Integer): TAtlasResizeNeighbour;
begin
  Result.Bounds := ABounds;
  Result.Group := AGroup;
end;

function SnapTo(AValue, AGrid: Integer): Integer;
begin
  Result := AValue;
  if AGrid > 1 then
  begin
    Result := Round(AValue / AGrid) * AGrid;
  end;
end;

function MinOf(AValue: Integer): Integer;
begin
  Result := AValue;
  if Result <= 0 then
  begin
    Result := TAtlasMultiResize.cMinSize;
  end;
end;

/// <summary>Neue Kanten eines Rechtecks auf einer Achse: ANear/AFar alte Kanten, AMoveFar = die ferne Kante
/// bewegt sich; Delta oder Ziel (Align).</summary>
procedure ResizeAxis(var ANear, AFar: Integer; AMoveFar: Boolean; AMode: TAtlasResizeMode; ADelta, ATarget,
  AMin: Integer);
begin
  if AMoveFar then
  begin
    if AMode = TAtlasResizeMode.Align then
    begin
      AFar := Max(ATarget, ANear + AMin);
    end
    else
    begin
      AFar := Max(AFar + ADelta, ANear + AMin);
    end;
  end
  else if AMode = TAtlasResizeMode.Align then
  begin
    ANear := Min(ATarget, AFar - AMin);
  end
  else
  begin
    ANear := Min(ANear + ADelta, AFar - AMin);
  end;
end;

/// <summary>Versatz der gezogenen Kante nach dem Raster: (dx, dy) und Zielkanten (tx, ty) für Align.</summary>
procedure DraggedEdge(const ARect: TRect; AEdge: TAtlasResizeEdge; const ADelta: TPoint; AGrid: Integer;
  out AMove, ATarget: TPoint);
begin
  AMove := Point(0, 0);
  ATarget := Point(0, 0);
  if TAtlasMultiResize.Horizontal(AEdge) then
  begin
    if AEdge = TAtlasResizeEdge.Left then
    begin
      ATarget.X := SnapTo(ARect.Left + ADelta.X, AGrid);
      AMove.X := ATarget.X - ARect.Left;
    end
    else
    begin
      ATarget.X := SnapTo(ARect.Right + ADelta.X, AGrid);
      AMove.X := ATarget.X - ARect.Right;
    end;
  end;
  if TAtlasMultiResize.Vertical(AEdge) then
  begin
    if AEdge = TAtlasResizeEdge.Top then
    begin
      ATarget.Y := SnapTo(ARect.Top + ADelta.Y, AGrid);
      AMove.Y := ATarget.Y - ARect.Top;
    end
    else
    begin
      ATarget.Y := SnapTo(ARect.Bottom + ADelta.Y, AGrid);
      AMove.Y := ATarget.Y - ARect.Bottom;
    end;
  end;
end;

function ResizeOne(const AItem: TAtlasResizeItem; AEdge: TAtlasResizeEdge; AMode: TAtlasResizeMode;
  const AMove, ATarget: TPoint): TRect;
var
  mNear, mFar: Integer;
begin
  Result := AItem.Bounds;
  if AItem.Fixed then
  begin
    Exit;
  end;
  if TAtlasMultiResize.Horizontal(AEdge) then
  begin
    mNear := Result.Left;
    mFar := Result.Right;
    ResizeAxis(mNear, mFar, AEdge <> TAtlasResizeEdge.Left, AMode, AMove.X, ATarget.X, MinOf(AItem.MinWidth));
    Result.Left := mNear;
    Result.Right := mFar;
  end;
  if TAtlasMultiResize.Vertical(AEdge) then
  begin
    mNear := Result.Top;
    mFar := Result.Bottom;
    ResizeAxis(mNear, mFar, AEdge <> TAtlasResizeEdge.Top, AMode, AMove.Y, ATarget.Y, MinOf(AItem.MinHeight));
    Result.Top := mNear;
    Result.Bottom := mFar;
  end;
end;

/// <summary>Versatz eines Nachbarn: größte Änderung der Kante eines Steuerelements, hinter dem er liegt.</summary>
function NeighbourShift(const ANeighbour: TAtlasResizeNeighbour; const AItems: TArray<TAtlasResizeItem>;
  const ANew: TArray<TRect>; AEdge: TAtlasResizeEdge): TPoint;
var
  mIndex, mShift: Integer;
  mOld, mN: TRect;
begin
  Result := Point(0, 0);
  mN := ANeighbour.Bounds;
  for mIndex := 0 to High(AItems) do
  begin
    mOld := AItems[mIndex].Bounds;
    if AItems[mIndex].Group <> ANeighbour.Group then
    begin
      Continue;
    end;
    // Waagerecht: rechts hinter der rechten Kante (bzw. links vor der linken), senkrecht überlappend.
    if TAtlasMultiResize.Horizontal(AEdge) and (mN.Top < mOld.Bottom) and (mN.Bottom > mOld.Top) then
    begin
      if (AEdge <> TAtlasResizeEdge.Left) and (mN.Left >= mOld.Right) then
      begin
        mShift := ANew[mIndex].Right - mOld.Right;
        if Abs(mShift) > Abs(Result.X) then
        begin
          Result.X := mShift;
        end;
      end
      else if (AEdge = TAtlasResizeEdge.Left) and (mN.Right <= mOld.Left) then
      begin
        mShift := ANew[mIndex].Left - mOld.Left;
        if Abs(mShift) > Abs(Result.X) then
        begin
          Result.X := mShift;
        end;
      end;
    end;
    if TAtlasMultiResize.Vertical(AEdge) and (mN.Left < mOld.Right) and (mN.Right > mOld.Left) then
    begin
      if (AEdge <> TAtlasResizeEdge.Top) and (mN.Top >= mOld.Bottom) then
      begin
        mShift := ANew[mIndex].Bottom - mOld.Bottom;
        if Abs(mShift) > Abs(Result.Y) then
        begin
          Result.Y := mShift;
        end;
      end
      else if (AEdge = TAtlasResizeEdge.Top) and (mN.Bottom <= mOld.Top) then
      begin
        mShift := ANew[mIndex].Top - mOld.Top;
        if Abs(mShift) > Abs(Result.Y) then
        begin
          Result.Y := mShift;
        end;
      end;
    end;
  end;
end;

{ TAtlasMultiResize }

class function TAtlasMultiResize.Horizontal(AEdge: TAtlasResizeEdge): Boolean;
begin
  Result := AEdge in [TAtlasResizeEdge.Right, TAtlasResizeEdge.Corner, TAtlasResizeEdge.Left];
end;

class function TAtlasMultiResize.Vertical(AEdge: TAtlasResizeEdge): Boolean;
begin
  Result := AEdge in [TAtlasResizeEdge.Bottom, TAtlasResizeEdge.Corner, TAtlasResizeEdge.Top];
end;

class function TAtlasMultiResize.Opposite(AEdge: TAtlasResizeEdge): TAtlasResizeEdge;
begin
  case AEdge of
    TAtlasResizeEdge.Right:
      Result := TAtlasResizeEdge.Left;
    TAtlasResizeEdge.Bottom:
      Result := TAtlasResizeEdge.Top;
  else
    Result := AEdge;
  end;
end;

class function TAtlasMultiResize.ModeOf(const AText: string): TAtlasResizeMode;
begin
  if SameText(AText, cModeAlign) then
  begin
    Result := TAtlasResizeMode.Align;
  end
  else
  begin
    Result := TAtlasResizeMode.Delta;
  end;
end;

class function TAtlasMultiResize.Apply(const AItems: TArray<TAtlasResizeItem>;
  const ANeighbours: TArray<TAtlasResizeNeighbour>; ADragged: Integer; AEdge: TAtlasResizeEdge; const ADelta: TPoint;
  AMode: TAtlasResizeMode; AGrid: Integer; AFollow: Boolean): TAtlasResizeResult;
var
  mIndex: Integer;
  mMove, mTarget, mShift: TPoint;
begin
  Result := Default(TAtlasResizeResult);
  SetLength(Result.Items, Length(AItems));
  SetLength(Result.Neighbours, Length(ANeighbours));
  if (ADragged < 0) or (ADragged > High(AItems)) then
  begin
    for mIndex := 0 to High(AItems) do
    begin
      Result.Items[mIndex] := AItems[mIndex].Bounds;
    end;
    for mIndex := 0 to High(ANeighbours) do
    begin
      Result.Neighbours[mIndex] := ANeighbours[mIndex].Bounds;
    end;
    Exit;
  end;
  DraggedEdge(AItems[ADragged].Bounds, AEdge, ADelta, AGrid, mMove, mTarget);
  for mIndex := 0 to High(AItems) do
  begin
    Result.Items[mIndex] := ResizeOne(AItems[mIndex], AEdge, AMode, mMove, mTarget);
    if Result.Items[mIndex] <> AItems[mIndex].Bounds then
    begin
      Inc(Result.Changed);
    end;
  end;
  for mIndex := 0 to High(ANeighbours) do
  begin
    Result.Neighbours[mIndex] := ANeighbours[mIndex].Bounds;
    if AFollow then
    begin
      mShift := NeighbourShift(ANeighbours[mIndex], AItems, Result.Items, AEdge);
      Result.Neighbours[mIndex].Offset(mShift.X, mShift.Y);
    end;
  end;
end;

end.
