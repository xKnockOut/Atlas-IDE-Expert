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
      AGroup: Integer): TAtlasResizeItem; static;
  end;

  TAtlasResizeNeighbour = record
    Bounds: TRect;
    Group: Integer;
    class function Create(const ABounds: TRect; AGroup: Integer): TAtlasResizeNeighbour; static;
  end;

  /// <summary>Zug an einer Kante: AItems[Dragged] wird an Edge um Delta gezogen (Bildschirmpixel = Pixel im
  /// Formular); Grid 0 = ohne Raster; Follow lässt die Nachbarn mitrücken.</summary>
  TAtlasResizeDrag = record
    Dragged: Integer;
    Edge: TAtlasResizeEdge;
    Delta: TPoint;
    Mode: TAtlasResizeMode;
    Grid: Integer;
    Follow: Boolean;
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
    cModeAlign = 'align';
  public
    /// <summary>Neue Lagen nach dem Zug ADrag.</summary>
    class function Apply(const AItems: TArray<TAtlasResizeItem>; const ANeighbours: TArray<TAtlasResizeNeighbour>;
      const ADrag: TAtlasResizeDrag): TAtlasResizeResult; static;
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

/// <summary>Neue Lage der bewegten Kante AOld: Ziel ATarget (Align) oder um ADelta verschoben.</summary>
function MovedEdge(AOld, ADelta, ATarget: Integer; AMode: TAtlasResizeMode): Integer;
begin
  if AMode = TAtlasResizeMode.Align then
  begin
    Result := ATarget;
  end
  else
  begin
    Result := AOld + ADelta;
  end;
end;

/// <summary>Neue Kanten eines Rechtecks auf einer Achse: ANear/AFar alte Kanten, AMoveFar = die ferne Kante
/// bewegt sich nach ATo, sonst die nahe; die Größe bleibt mindestens AMin.</summary>
procedure ResizeAxis(var ANear, AFar: Integer; AMoveFar: Boolean; ATo, AMin: Integer);
begin
  if AMoveFar then
  begin
    AFar := Max(ATo, ANear + AMin);
  end
  else
  begin
    ANear := Min(ATo, AFar - AMin);
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
  mNear, mFar, mTo: Integer;
  mFarMoves: Boolean;
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
    mFarMoves := AEdge <> TAtlasResizeEdge.Left;
    if mFarMoves then
    begin
      mTo := MovedEdge(mFar, AMove.X, ATarget.X, AMode);
    end
    else
    begin
      mTo := MovedEdge(mNear, AMove.X, ATarget.X, AMode);
    end;
    ResizeAxis(mNear, mFar, mFarMoves, mTo, MinOf(AItem.MinWidth));
    Result.Left := mNear;
    Result.Right := mFar;
  end;
  if TAtlasMultiResize.Vertical(AEdge) then
  begin
    mNear := Result.Top;
    mFar := Result.Bottom;
    mFarMoves := AEdge <> TAtlasResizeEdge.Top;
    if mFarMoves then
    begin
      mTo := MovedEdge(mFar, AMove.Y, ATarget.Y, AMode);
    end
    else
    begin
      mTo := MovedEdge(mNear, AMove.Y, ATarget.Y, AMode);
    end;
    ResizeAxis(mNear, mFar, mFarMoves, mTo, MinOf(AItem.MinHeight));
    Result.Top := mNear;
    Result.Bottom := mFar;
  end;
end;

/// <summary>Waagerechte Änderung für den Nachbarn AN des Steuerelements AOld → ANew: rechts hinter der rechten
/// Kante (bzw. links vor der linken bei AEdge Left), senkrecht überlappend; sonst 0.</summary>
function ShiftX(const AN, AOld, ANew: TRect; AEdge: TAtlasResizeEdge): Integer;
begin
  Result := 0;
  if not TAtlasMultiResize.Horizontal(AEdge) or (AN.Top >= AOld.Bottom) or (AN.Bottom <= AOld.Top) then
  begin
    Exit;
  end;
  if (AEdge <> TAtlasResizeEdge.Left) and (AN.Left >= AOld.Right) then
  begin
    Result := ANew.Right - AOld.Right;
  end
  else if (AEdge = TAtlasResizeEdge.Left) and (AN.Right <= AOld.Left) then
  begin
    Result := ANew.Left - AOld.Left;
  end;
end;

/// <summary>Wie ShiftX für die senkrechte Achse (Kante Top statt Left).</summary>
function ShiftY(const AN, AOld, ANew: TRect; AEdge: TAtlasResizeEdge): Integer;
begin
  Result := 0;
  if not TAtlasMultiResize.Vertical(AEdge) or (AN.Left >= AOld.Right) or (AN.Right <= AOld.Left) then
  begin
    Exit;
  end;
  if (AEdge <> TAtlasResizeEdge.Top) and (AN.Top >= AOld.Bottom) then
  begin
    Result := ANew.Bottom - AOld.Bottom;
  end
  else if (AEdge = TAtlasResizeEdge.Top) and (AN.Bottom <= AOld.Top) then
  begin
    Result := ANew.Top - AOld.Top;
  end;
end;

/// <summary>AShift in AValue, wenn er dem Betrag nach größer ist.</summary>
procedure KeepLarger(var AValue: Integer; AShift: Integer);
begin
  if Abs(AShift) > Abs(AValue) then
  begin
    AValue := AShift;
  end;
end;

/// <summary>Versatz eines Nachbarn: größte Änderung der Kante eines Steuerelements, hinter dem er liegt.</summary>
function NeighbourShift(const ANeighbour: TAtlasResizeNeighbour; const AItems: TArray<TAtlasResizeItem>;
  const ANew: TArray<TRect>; AEdge: TAtlasResizeEdge): TPoint;
var
  mIndex: Integer;
begin
  Result := Point(0, 0);
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Group = ANeighbour.Group then
    begin
      KeepLarger(Result.X, ShiftX(ANeighbour.Bounds, AItems[mIndex].Bounds, ANew[mIndex], AEdge));
      KeepLarger(Result.Y, ShiftY(ANeighbour.Bounds, AItems[mIndex].Bounds, ANew[mIndex], AEdge));
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
  const ANeighbours: TArray<TAtlasResizeNeighbour>; const ADrag: TAtlasResizeDrag): TAtlasResizeResult;
var
  mIndex: Integer;
  mMove, mTarget, mShift: TPoint;
begin
  Result := Default(TAtlasResizeResult);
  SetLength(Result.Items, Length(AItems));
  SetLength(Result.Neighbours, Length(ANeighbours));
  if (ADrag.Dragged < 0) or (ADrag.Dragged > High(AItems)) then
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
  DraggedEdge(AItems[ADrag.Dragged].Bounds, ADrag.Edge, ADrag.Delta, ADrag.Grid, mMove, mTarget);
  for mIndex := 0 to High(AItems) do
  begin
    Result.Items[mIndex] := ResizeOne(AItems[mIndex], ADrag.Edge, ADrag.Mode, mMove, mTarget);
    if Result.Items[mIndex] <> AItems[mIndex].Bounds then
    begin
      Inc(Result.Changed);
    end;
  end;
  for mIndex := 0 to High(ANeighbours) do
  begin
    Result.Neighbours[mIndex] := ANeighbours[mIndex].Bounds;
    if ADrag.Follow then
    begin
      mShift := NeighbourShift(ANeighbours[mIndex], AItems, Result.Items, ADrag.Edge);
      Result.Neighbours[mIndex].Offset(mShift.X, mShift.Y);
    end;
  end;
end;

end.
