unit Atlas.Core.Designer.Layers;

// Ebenen im Designer schrittweise ordnen (#749), ohne VCL und Windows. Die
// Steuerelemente eines Parents kommen in der Reihenfolge seiner Controls, von
// unten nach oben: erst die fensterlosen (TGraphicControl), dann die
// fensterbehafteten. Fensterlose liegen immer unter fensterbehafteten; jede
// Verschiebung bleibt deshalb unter den Steuerelementen derselben Art.
// - Stapel: alle, die ein Rechteck schneiden, oberstes zuerst.
// - Eine Ebene nach vorn: über das nächsthöhere überlappende Steuerelement
//   derselben Art; nach hinten entsprechend unter das nächsttiefere. Ohne
//   Überlappung in dieser Richtung bleibt alles (nil).
// - Ganz nach vorn/hinten: an das Ende bzw. den Anfang der eigenen Art.
// Ergebnis ist die neue Reihenfolge als Indizes, von unten nach oben.

interface

uses
  System.Types;

type
  TAtlasLayerItem = record
    Name: string;
    Bounds: TRect;
    /// <summary>Fensterbehaftet (TWinControl); fensterlose liegen immer darunter.</summary>
    Windowed: Boolean;
    class function Create(const AName: string; const ABounds: TRect; AWindowed: Boolean): TAtlasLayerItem; static;
  end;

  TAtlasLayers = class
  public
    /// <summary>Indizes aller, die ARect schneiden, oberstes zuerst.</summary>
    class function Stack(const AItems: TArray<TAtlasLayerItem>; const ARect: TRect): TArray<Integer>; static;
    /// <summary>Neue Reihenfolge, wenn AIndex eine Ebene nach vorn (AForward) bzw. hinten geht; nil ohne
    /// überlappendes Steuerelement derselben Art in dieser Richtung.</summary>
    class function Step(const AItems: TArray<TAtlasLayerItem>; AIndex: Integer;
      AForward: Boolean): TArray<Integer>; static;
    /// <summary>Neue Reihenfolge, wenn AIndex ganz nach vorn (AFront) bzw. hinten geht; nil, wenn es schon
    /// dort liegt.</summary>
    class function Extreme(const AItems: TArray<TAtlasLayerItem>; AIndex: Integer;
      AFront: Boolean): TArray<Integer>; static;
  end;

implementation

{ TAtlasLayerItem }

class function TAtlasLayerItem.Create(const AName: string; const ABounds: TRect;
  AWindowed: Boolean): TAtlasLayerItem;
begin
  Result.Name := AName;
  Result.Bounds := ABounds;
  Result.Windowed := AWindowed;
end;

{ TAtlasLayers }

function Overlap(const A, B: TRect): Boolean;
begin
  Result := (A.Left < B.Right) and (B.Left < A.Right) and (A.Top < B.Bottom) and (B.Top < A.Bottom);
end;

class function TAtlasLayers.Stack(const AItems: TArray<TAtlasLayerItem>; const ARect: TRect): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := High(AItems) downto 0 do
  begin
    if Overlap(AItems[mIndex].Bounds, ARect) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Reihenfolge 0..n-1 mit AIndex an die Stelle vor AAt (in der Reihenfolge ohne AIndex).</summary>
function Moved(ACount, AIndex, AAt: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ACount - 1 do
  begin
    if mIndex = AAt then
    begin
      Result := Result + [AIndex];
    end;
    if mIndex <> AIndex then
    begin
      Result := Result + [mIndex];
    end;
  end;
  if AAt >= ACount then
  begin
    Result := Result + [AIndex];
  end;
end;

/// <summary>Kommt AOther für AIndex in Frage (andere, gleiche Art, überlappend)?</summary>
function Peer(const AItems: TArray<TAtlasLayerItem>; AIndex, AOther: Integer): Boolean;
begin
  Result := (AOther <> AIndex) and (AItems[AOther].Windowed = AItems[AIndex].Windowed) and
    Overlap(AItems[AOther].Bounds, AItems[AIndex].Bounds);
end;

class function TAtlasLayers.Step(const AItems: TArray<TAtlasLayerItem>; AIndex: Integer;
  AForward: Boolean): TArray<Integer>;
var
  mOther: Integer;
begin
  Result := nil;
  if AForward then
  begin
    for mOther := AIndex + 1 to High(AItems) do
    begin
      if Peer(AItems, AIndex, mOther) then
      begin
        Exit(Moved(Length(AItems), AIndex, mOther + 1));
      end;
    end;
  end
  else
  begin
    for mOther := AIndex - 1 downto 0 do
    begin
      if Peer(AItems, AIndex, mOther) then
      begin
        Exit(Moved(Length(AItems), AIndex, mOther));
      end;
    end;
  end;
end;

class function TAtlasLayers.Extreme(const AItems: TArray<TAtlasLayerItem>; AIndex: Integer;
  AFront: Boolean): TArray<Integer>;
var
  mEdge, mOther: Integer;
begin
  // Rand der eigenen Art: höchster bzw. tiefster Index derselben Art.
  mEdge := AIndex;
  for mOther := 0 to High(AItems) do
  begin
    if AItems[mOther].Windowed <> AItems[AIndex].Windowed then
    begin
      Continue;
    end;
    if (AFront and (mOther > mEdge)) or (not AFront and (mOther < mEdge)) then
    begin
      mEdge := mOther;
    end;
  end;
  Result := nil;
  if mEdge = AIndex then
  begin
    Exit;
  end;
  if AFront then
  begin
    Result := Moved(Length(AItems), AIndex, mEdge + 1);
  end
  else
  begin
    Result := Moved(Length(AItems), AIndex, mEdge);
  end;
end;

end.
