unit Atlas.Core.StatusBar.Layout;

// Atlas-Statusleiste (#1155), Aufteilung ohne VCL und OTA: Die Leiste hat
// eine feste Höhe und bricht nie um. Fit verteilt die Breite:
// - Passen alle Elemente in voller Breite, bleiben sie so.
// - Sonst kürzen sie sich in der Reihenfolge ihrer Kürzstufe (Shrink, kleiner
//   zuerst; die Methode hat die kleinste) bis auf ihre Mindestbreite
//   (MinWidth: Symbol, Kennzahlen und „…“).
// - Reicht auch das nicht, fallen Elemente in derselben Reihenfolge ganz weg
//   (Breite 0); das Zahnrad rechts gehört nicht zur Aufteilung.
// - Zwischen zwei sichtbaren Elementen steht ein Trennstrich der Breite AGap.
// Place setzt die Elemente von links nebeneinander, IndexAt findet das
// Element unter einem Punkt.

interface

uses
  System.SysUtils;

type
  TAtlasStatusSlot = record
    /// <summary>Volle Breite.</summary>
    Width: Integer;
    /// <summary>Kleinste Breite nach dem Kürzen; = Width, wenn es sich nicht kürzen lässt.</summary>
    MinWidth: Integer;
    /// <summary>Kürzstufe: kleiner kürzt und verschwindet zuerst; bei Gleichstand das hintere zuerst.</summary>
    Shrink: Integer;
    class function Create(AWidth, AMinWidth, AShrink: Integer): TAtlasStatusSlot; static;
  end;

  TAtlasStatusSpan = record
    Left: Integer;
    Right: Integer;
    function IsEmpty: Boolean;
    function Contains(AX: Integer): Boolean;
  end;

  TAtlasStatusBarLayout = class
  public
    /// <summary>Breite je Element bei AAvailable Pixeln (0 = weggefallen), Trennstriche AGap breit.</summary>
    class function Fit(const ASlots: TArray<TAtlasStatusSlot>; AAvailable, AGap: Integer): TArray<Integer>; static;
    /// <summary>Breite aller Elemente in voller Breite samt Trennstrichen.</summary>
    class function FullWidth(const ASlots: TArray<TAtlasStatusSlot>; AGap: Integer): Integer; static;
    /// <summary>Elemente ab ALeft nebeneinander; weggefallene bekommen eine leere Spanne.</summary>
    class function Place(const AWidths: TArray<Integer>; ALeft, AGap: Integer): TArray<TAtlasStatusSpan>; static;
    /// <summary>Element unter X; -1 ohne (auch auf Trennstrichen).</summary>
    class function IndexAt(const ASpans: TArray<TAtlasStatusSpan>; AX: Integer): Integer; static;
  end;

implementation

{ TAtlasStatusSlot }

class function TAtlasStatusSlot.Create(AWidth, AMinWidth, AShrink: Integer): TAtlasStatusSlot;
begin
  Result.Width := AWidth;
  if AMinWidth > AWidth then
  begin
    Result.MinWidth := AWidth;
  end
  else
  begin
    Result.MinWidth := AMinWidth;
  end;
  Result.Shrink := AShrink;
end;

{ TAtlasStatusSpan }

function TAtlasStatusSpan.IsEmpty: Boolean;
begin
  Result := Right <= Left;
end;

function TAtlasStatusSpan.Contains(AX: Integer): Boolean;
begin
  Result := (AX >= Left) and (AX < Right);
end;

{ TAtlasStatusBarLayout }

function Total(const AWidths: TArray<Integer>; AGap: Integer): Integer;
var
  mWidth, mShown: Integer;
begin
  Result := 0;
  mShown := 0;
  for mWidth in AWidths do
  begin
    if mWidth > 0 then
    begin
      Inc(Result, mWidth);
      Inc(mShown);
    end;
  end;
  if mShown > 1 then
  begin
    Inc(Result, (mShown - 1) * AGap);
  end;
end;

/// <summary>Indizes in Kürzreihenfolge: kleine Stufe zuerst, bei Gleichstand das hintere Element zuerst.</summary>
function ShrinkOrder(const ASlots: TArray<TAtlasStatusSlot>): TArray<Integer>;
var
  mIndex, mInner, mSwap: Integer;
begin
  SetLength(Result, Length(ASlots));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := mIndex;
  end;
  // Einfügesortierung: wenige Elemente, und die Reihenfolge bleibt eindeutig.
  for mIndex := 1 to High(Result) do
  begin
    mInner := mIndex;
    while (mInner > 0) and ((ASlots[Result[mInner]].Shrink < ASlots[Result[mInner - 1]].Shrink) or
      ((ASlots[Result[mInner]].Shrink = ASlots[Result[mInner - 1]].Shrink) and
      (Result[mInner] > Result[mInner - 1]))) do
    begin
      mSwap := Result[mInner];
      Result[mInner] := Result[mInner - 1];
      Result[mInner - 1] := mSwap;
      Dec(mInner);
    end;
  end;
end;

class function TAtlasStatusBarLayout.FullWidth(const ASlots: TArray<TAtlasStatusSlot>; AGap: Integer): Integer;
var
  mWidths: TArray<Integer>;
  mIndex: Integer;
begin
  SetLength(mWidths, Length(ASlots));
  for mIndex := 0 to High(ASlots) do
  begin
    mWidths[mIndex] := ASlots[mIndex].Width;
  end;
  Result := Total(mWidths, AGap);
end;

class function TAtlasStatusBarLayout.Fit(const ASlots: TArray<TAtlasStatusSlot>; AAvailable,
  AGap: Integer): TArray<Integer>;
var
  mIndex, mExcess, mCut: Integer;
  mOrder: TArray<Integer>;
begin
  Result := nil;
  SetLength(Result, Length(ASlots));
  for mIndex := 0 to High(ASlots) do
  begin
    Result[mIndex] := ASlots[mIndex].Width;
  end;
  mExcess := Total(Result, AGap) - AAvailable;
  if mExcess <= 0 then
  begin
    Exit;
  end;
  mOrder := ShrinkOrder(ASlots);
  for mIndex in mOrder do
  begin
    mCut := Result[mIndex] - ASlots[mIndex].MinWidth;
    if mCut > mExcess then
    begin
      mCut := mExcess;
    end;
    if mCut <= 0 then
    begin
      Continue;
    end;
    Dec(Result[mIndex], mCut);
    Dec(mExcess, mCut);
    if mExcess <= 0 then
    begin
      Exit;
    end;
  end;
  // Auch gekürzt zu breit: ganze Elemente weglassen, in derselben Reihenfolge.
  for mIndex in mOrder do
  begin
    if Total(Result, AGap) <= AAvailable then
    begin
      Exit;
    end;
    Result[mIndex] := 0;
  end;
end;

class function TAtlasStatusBarLayout.Place(const AWidths: TArray<Integer>; ALeft,
  AGap: Integer): TArray<TAtlasStatusSpan>;
var
  mIndex, mLeft: Integer;
  mStarted: Boolean;
begin
  Result := nil;
  SetLength(Result, Length(AWidths));
  mLeft := ALeft;
  mStarted := False;
  for mIndex := 0 to High(AWidths) do
  begin
    Result[mIndex].Left := mLeft;
    Result[mIndex].Right := mLeft;
    if AWidths[mIndex] <= 0 then
    begin
      Continue;
    end;
    if mStarted then
    begin
      Inc(mLeft, AGap);
    end;
    mStarted := True;
    Result[mIndex].Left := mLeft;
    Result[mIndex].Right := mLeft + AWidths[mIndex];
    mLeft := Result[mIndex].Right;
  end;
end;

class function TAtlasStatusBarLayout.IndexAt(const ASpans: TArray<TAtlasStatusSpan>; AX: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASpans) do
  begin
    if not ASpans[mIndex].IsEmpty and ASpans[mIndex].Contains(AX) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

end.
