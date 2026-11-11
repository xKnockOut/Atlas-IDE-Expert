unit Atlas.Core.Designer.InsertSpace;

// Platz im Designer einfügen und entfernen (#740), ohne VCL und Windows. Am
// Beispiel einer waagerechten Linie bei y (Rows; Columns entsprechend mit
// links und rechts):
// - Steuerelemente ohne Align mit Oberkante ≥ y rücken um den Betrag.
// - Wer die Linie schneidet (Oberkante < y < Unterkante), wird nur mit
//   [akTop, akBottom] länger; sonst bleibt er und steht in Untouched.
// - Ausgerichtete Steuerelemente (Align) ordnet die VCL selbst; sie bleiben.
//   Unten ausgerichtete (alBottom) begrenzen die nutzbare Fläche.
// - Entfernen geht höchstens bis zum nächsten Steuerelement über der Linie
//   (ohne eines bis zum Rand).
// - Parent: Einfügen lässt ihn um den Betrag wachsen, wenn der Inhalt sonst
//   nicht mehr hineinpasst. Entfernen lässt ihn schrumpfen, wenn Einfügen
//   desselben Betrags ihn hätte wachsen lassen (der Rand unter dem Inhalt
//   bleibt so gleich). Die Kette nach oben rechnet der Aufrufer Ebene für
//   Ebene mit derselben Funktion: Linie an der alten Unterkante des
//   gewachsenen Kinds, Betrag = dessen Wachstum.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  /// <summary>Rows: waagerechte Linie, verschoben wird senkrecht; Columns: senkrechte Linie.</summary>
  TAtlasSpaceAxis = (Rows, Columns);
  /// <summary>Align bezogen auf die Achse: Near = alTop/alLeft, Far = alBottom/alRight, Fill = alClient,
  /// Across = quer ausgerichtet (alLeft/alRight bei Rows).</summary>
  TAtlasSpaceAlign = (None, Near, Far, Fill, Across);
{$SCOPEDENUMS OFF}

  TAtlasSpaceItem = record
    Bounds: TRect;
    Align: TAtlasSpaceAlign;
    /// <summary>An beiden Seiten der Achse verankert ([akTop, akBottom] bei Rows).</summary>
    Stretch: Boolean;
    class function Create(const ABounds: TRect; AAlign: TAtlasSpaceAlign; AStretch: Boolean): TAtlasSpaceItem; static;
  end;

  TAtlasSpaceResult = record
    /// <summary>Neue Lage je Steuerelement (gleiche Reihenfolge).</summary>
    Bounds: TArray<TRect>;
    /// <summary>Schneiden die Linie, wachsen aber nicht mit (ohne beide Anker).</summary>
    Untouched: TArray<Integer>;
    /// <summary>Betrag, um den der Parent wächst (negativ: schrumpft); 0 = bleibt.</summary>
    Grow: Integer;
    /// <summary>Tatsächlicher Betrag (Entfernen begrenzt).</summary>
    Amount: Integer;
  end;

  TAtlasInsertSpace = class
  public
    /// <summary>Betrag begrenzt: Entfernen (AAmount &lt; 0) höchstens bis zum nächsten Steuerelement davor.</summary>
    class function Clamp(const AItems: TArray<TAtlasSpaceItem>; AAxis: TAtlasSpaceAxis; ALine, AAmount: Integer;
      const AClient: TRect): Integer; static;
    /// <summary>Platz AAmount (negativ: entfernen) an der Linie ALine einfügen.</summary>
    class function Apply(const AItems: TArray<TAtlasSpaceItem>; AAxis: TAtlasSpaceAxis; ALine, AAmount: Integer;
      const AClient: TRect; AGrowParent: Boolean): TAtlasSpaceResult; static;
    /// <summary>AValue auf ein Vielfaches von AGrid gerundet (AGrid &lt;= 1: unverändert).</summary>
    class function Snap(AValue, AGrid: Integer): Integer; static;
  end;

implementation

uses
  System.Math;

{ TAtlasSpaceItem }

class function TAtlasSpaceItem.Create(const ABounds: TRect; AAlign: TAtlasSpaceAlign;
  AStretch: Boolean): TAtlasSpaceItem;
begin
  Result.Bounds := ABounds;
  Result.Align := AAlign;
  Result.Stretch := AStretch;
end;

{ Achsen }

function Lo(const ARect: TRect; AAxis: TAtlasSpaceAxis): Integer;
begin
  Result := ARect.Top;
  if AAxis = TAtlasSpaceAxis.Columns then
  begin
    Result := ARect.Left;
  end;
end;

function Hi(const ARect: TRect; AAxis: TAtlasSpaceAxis): Integer;
begin
  Result := ARect.Bottom;
  if AAxis = TAtlasSpaceAxis.Columns then
  begin
    Result := ARect.Right;
  end;
end;

/// <summary>ARect entlang der Achse verschoben.</summary>
function Shifted(const ARect: TRect; AAxis: TAtlasSpaceAxis; AAmount: Integer): TRect;
begin
  Result := ARect;
  if AAxis = TAtlasSpaceAxis.Rows then
  begin
    Result.Offset(0, AAmount);
  end
  else
  begin
    Result.Offset(AAmount, 0);
  end;
end;

/// <summary>ARect entlang der Achse verlängert, mindestens ein Pixel lang.</summary>
function Stretched(const ARect: TRect; AAxis: TAtlasSpaceAxis; AAmount: Integer): TRect;
begin
  Result := ARect;
  if AAxis = TAtlasSpaceAxis.Rows then
  begin
    Result.Bottom := Max(Result.Top + 1, Result.Bottom + AAmount);
  end
  else
  begin
    Result.Right := Max(Result.Left + 1, Result.Right + AAmount);
  end;
end;

/// <summary>Ende der nutzbaren Fläche: Rand oder Beginn des ersten am Ende ausgerichteten.</summary>
function Limit(const AItems: TArray<TAtlasSpaceItem>; AAxis: TAtlasSpaceAxis; const AClient: TRect): Integer;
var
  mItem: TAtlasSpaceItem;
begin
  Result := Hi(AClient, AAxis);
  for mItem in AItems do
  begin
    if mItem.Align = TAtlasSpaceAlign.Far then
    begin
      Result := Min(Result, Lo(mItem.Bounds, AAxis));
    end;
  end;
end;

/// <summary>Ende des Inhalts ohne Align; -1 ohne solche Steuerelemente.</summary>
function Extent(const AItems: TArray<TAtlasSpaceItem>; const ABounds: TArray<TRect>; AAxis: TAtlasSpaceAxis): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Align = TAtlasSpaceAlign.None then
    begin
      Result := Max(Result, Hi(ABounds[mIndex], AAxis));
    end;
  end;
end;

{ TAtlasInsertSpace }

class function TAtlasInsertSpace.Clamp(const AItems: TArray<TAtlasSpaceItem>; AAxis: TAtlasSpaceAxis;
  ALine, AAmount: Integer; const AClient: TRect): Integer;
var
  mItem: TAtlasSpaceItem;
  mFree: Integer;
begin
  Result := AAmount;
  if AAmount >= 0 then
  begin
    Exit;
  end;
  mFree := ALine - Lo(AClient, AAxis);
  for mItem in AItems do
  begin
    if (mItem.Align = TAtlasSpaceAlign.None) and (Hi(mItem.Bounds, AAxis) <= ALine) then
    begin
      mFree := Min(mFree, ALine - Hi(mItem.Bounds, AAxis));
    end;
  end;
  Result := Max(AAmount, -Max(mFree, 0));
end;

/// <summary>Wachstum des Parents nach den Regeln oben.</summary>
function GrowOf(const AItems: TArray<TAtlasSpaceItem>; const ABounds: TArray<TRect>; AAxis: TAtlasSpaceAxis;
  AAmount: Integer; const AClient: TRect): Integer;
var
  mLimit, mOld, mNew, mIndex: Integer;
  mOldRects: TArray<TRect>;
begin
  Result := 0;
  SetLength(mOldRects, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    mOldRects[mIndex] := AItems[mIndex].Bounds;
  end;
  mLimit := Limit(AItems, AAxis, AClient);
  mOld := Extent(AItems, mOldRects, AAxis);
  mNew := Extent(AItems, ABounds, AAxis);
  if (mOld < 0) or (AAmount = 0) then
  begin
    Exit;
  end;
  if (AAmount > 0) and (mNew > mLimit) then
  begin
    Result := AAmount;
  end
  else if (AAmount < 0) and (mLimit - mOld < -AAmount) and (mNew <= mLimit + AAmount) then
  begin
    Result := AAmount;
  end;
end;

class function TAtlasInsertSpace.Apply(const AItems: TArray<TAtlasSpaceItem>; AAxis: TAtlasSpaceAxis;
  ALine, AAmount: Integer; const AClient: TRect; AGrowParent: Boolean): TAtlasSpaceResult;
var
  mIndex: Integer;
  mItem: TAtlasSpaceItem;
begin
  Result.Amount := Clamp(AItems, AAxis, ALine, AAmount, AClient);
  Result.Untouched := nil;
  SetLength(Result.Bounds, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    mItem := AItems[mIndex];
    Result.Bounds[mIndex] := mItem.Bounds;
    if (mItem.Align <> TAtlasSpaceAlign.None) or (Result.Amount = 0) then
    begin
      Continue;
    end;
    if Lo(mItem.Bounds, AAxis) >= ALine then
    begin
      Result.Bounds[mIndex] := Shifted(mItem.Bounds, AAxis, Result.Amount);
    end
    else if Hi(mItem.Bounds, AAxis) <= ALine then
    begin
      Continue;
    end
    else if mItem.Stretch then
    begin
      Result.Bounds[mIndex] := Stretched(mItem.Bounds, AAxis, Result.Amount);
    end
    else
    begin
      Result.Untouched := Result.Untouched + [mIndex];
    end;
  end;
  Result.Grow := 0;
  if AGrowParent then
  begin
    Result.Grow := GrowOf(AItems, Result.Bounds, AAxis, Result.Amount, AClient);
  end;
end;

class function TAtlasInsertSpace.Snap(AValue, AGrid: Integer): Integer;
begin
  Result := AValue;
  if AGrid > 1 then
  begin
    Result := Round(AValue / AGrid) * AGrid;
  end;
end;

end.
