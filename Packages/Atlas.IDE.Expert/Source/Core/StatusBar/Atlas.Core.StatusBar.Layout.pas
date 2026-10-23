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
    function Contains(X: Integer): Boolean;
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
    class function IndexAt(const ASpans: TArray<TAtlasStatusSpan>; X: Integer): Integer; static;
  end;

implementation

{ TAtlasStatusSlot }

class function TAtlasStatusSlot.Create(AWidth, AMinWidth, AShrink: Integer): TAtlasStatusSlot;
begin
  Result.Width := AWidth;
  if AMinWidth > AWidth then
    Result.MinWidth := AWidth
  else
    Result.MinWidth := AMinWidth;
  Result.Shrink := AShrink;
end;

{ TAtlasStatusSpan }

function TAtlasStatusSpan.IsEmpty: Boolean;
begin
  Result := Right <= Left;
end;

function TAtlasStatusSpan.Contains(X: Integer): Boolean;
begin
  Result := (X >= Left) and (X < Right);
end;

{ TAtlasStatusBarLayout }

function Total(const AWidths: TArray<Integer>; AGap: Integer): Integer;
var
  Width, Shown: Integer;
begin
  Result := 0;
  Shown := 0;
  for Width in AWidths do
    if Width > 0 then
    begin
      Inc(Result, Width);
      Inc(Shown);
    end;
  if Shown > 1 then
    Inc(Result, (Shown - 1) * AGap);
end;

/// <summary>Indizes in Kürzreihenfolge: kleine Stufe zuerst, bei Gleichstand das hintere Element zuerst.</summary>
function ShrinkOrder(const ASlots: TArray<TAtlasStatusSlot>): TArray<Integer>;
var
  Index, Inner, Swap: Integer;
begin
  SetLength(Result, Length(ASlots));
  for Index := 0 to High(Result) do
    Result[Index] := Index;
  // Einfügesortierung: wenige Elemente, und die Reihenfolge bleibt eindeutig.
  for Index := 1 to High(Result) do
  begin
    Inner := Index;
    while (Inner > 0) and ((ASlots[Result[Inner]].Shrink < ASlots[Result[Inner - 1]].Shrink) or
      ((ASlots[Result[Inner]].Shrink = ASlots[Result[Inner - 1]].Shrink) and
      (Result[Inner] > Result[Inner - 1]))) do
    begin
      Swap := Result[Inner];
      Result[Inner] := Result[Inner - 1];
      Result[Inner - 1] := Swap;
      Dec(Inner);
    end;
  end;
end;

class function TAtlasStatusBarLayout.FullWidth(const ASlots: TArray<TAtlasStatusSlot>; AGap: Integer): Integer;
var
  Widths: TArray<Integer>;
  Index: Integer;
begin
  SetLength(Widths, Length(ASlots));
  for Index := 0 to High(ASlots) do
    Widths[Index] := ASlots[Index].Width;
  Result := Total(Widths, AGap);
end;

class function TAtlasStatusBarLayout.Fit(const ASlots: TArray<TAtlasStatusSlot>; AAvailable,
  AGap: Integer): TArray<Integer>;
var
  Index, Excess, Cut: Integer;
  Order: TArray<Integer>;
begin
  Result := nil;
  SetLength(Result, Length(ASlots));
  for Index := 0 to High(ASlots) do
    Result[Index] := ASlots[Index].Width;
  Excess := Total(Result, AGap) - AAvailable;
  if Excess <= 0 then
    Exit;
  Order := ShrinkOrder(ASlots);
  for Index in Order do
  begin
    Cut := Result[Index] - ASlots[Index].MinWidth;
    if Cut > Excess then
      Cut := Excess;
    if Cut <= 0 then
      Continue;
    Dec(Result[Index], Cut);
    Dec(Excess, Cut);
    if Excess <= 0 then
      Exit;
  end;
  // Auch gekürzt zu breit: ganze Elemente weglassen, in derselben Reihenfolge.
  for Index in Order do
  begin
    if Total(Result, AGap) <= AAvailable then
      Exit;
    Result[Index] := 0;
  end;
end;

class function TAtlasStatusBarLayout.Place(const AWidths: TArray<Integer>; ALeft,
  AGap: Integer): TArray<TAtlasStatusSpan>;
var
  Index, Left: Integer;
  Started: Boolean;
begin
  Result := nil;
  SetLength(Result, Length(AWidths));
  Left := ALeft;
  Started := False;
  for Index := 0 to High(AWidths) do
  begin
    Result[Index].Left := Left;
    Result[Index].Right := Left;
    if AWidths[Index] <= 0 then
      Continue;
    if Started then
      Inc(Left, AGap);
    Started := True;
    Result[Index].Left := Left;
    Result[Index].Right := Left + AWidths[Index];
    Left := Result[Index].Right;
  end;
end;

class function TAtlasStatusBarLayout.IndexAt(const ASpans: TArray<TAtlasStatusSpan>; X: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ASpans) do
    if not ASpans[Index].IsEmpty and ASpans[Index].Contains(X) then
      Exit(Index);
  Result := -1;
end;

end.
