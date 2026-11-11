unit Atlas.Core.Designer.FitText;

// Breite im Designer nach dem längsten Text angleichen (#730), ohne VCL und
// Windows. Die Textbreiten misst das Plugin in der Schrift der Komponente
// und übergibt sie; hier stehen die Regeln:
// - Breite = Textbreite + Innenabstand (links und rechts zusammen) + Anteil
//   des Steuerelements (Kästchen, Pfeil, Glyph); das Maximum über alle
//   markierten, mindestens die Mindestbreite.
// - Reihe (gleiche Oberkante ± cRowTolerance): Abstände bleiben; die rechte
//   Kante der Reihe bleibt stehen, wenn die rechteste Komponente akRight hat
//   oder am rechten Rand des Elternelements liegt, sonst die linke.
// - Sonst (untereinander): je Komponente bleibt die linke Kante, bei akRight
//   die rechte.
// - AutoSize und Align ohne freie Breite (alTop, alBottom, alClient): zählen
//   beim Maximum mit, behalten aber ihre Breite.
// - Text: „&“ für Tastenkürzel zählt nicht („&&“ ist ein „&“), mehrzeilig
//   zählt die längste Zeile (Lines).

interface

uses
  System.Types;

type
  TAtlasFitItem = record
    Bounds: TRect;
    /// <summary>Breite des längsten Texts in der Schrift der Komponente.</summary>
    TextWidth: Integer;
    /// <summary>Anteil des Steuerelements: Kästchen bei Checkbox, Pfeil bei ComboBox, Glyph bei Knöpfen.</summary>
    Extra: Integer;
    /// <summary>Breite bleibt (AutoSize oder Align ohne freie Breite).</summary>
    Fixed: Boolean;
    AnchorRight: Boolean;
    class function Create(const ABounds: TRect; ATextWidth, AExtra: Integer; AFixed,
      AAnchorRight: Boolean): TAtlasFitItem; static;
  end;

  TAtlasFitText = class
  public const
    cRowTolerance = 4;
    /// <summary>Abstand zum rechten Rand, der noch als „am Rand“ gilt.</summary>
    cEdgeTolerance = 16;
  public
    /// <summary>Gemeinsame Breite: das Maximum von Text + APadding + Anteil, mindestens AMinWidth.</summary>
    class function Width(const AItems: TArray<TAtlasFitItem>; APadding, AMinWidth: Integer): Integer; static;
    /// <summary>Neue Lage aller Komponenten bei der Breite AWidth im Elternelement der Breite AParentWidth.</summary>
    class function Apply(const AItems: TArray<TAtlasFitItem>; AWidth, AParentWidth: Integer): TArray<TRect>; static;
    /// <summary>Liegen alle in einer Reihe (gleiche Oberkante ± cRowTolerance)?</summary>
    class function IsRow(const AItems: TArray<TAtlasFitItem>): Boolean; static;
    /// <summary>Text ohne „&amp;“ der Tastenkürzel.</summary>
    class function StripAccel(const AText: string): string; static;
    /// <summary>Zeilen des Texts (CR LF, LF oder CR), „&amp;“ entfernt.</summary>
    class function Lines(const AText: string): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasFitItem }

class function TAtlasFitItem.Create(const ABounds: TRect; ATextWidth, AExtra: Integer; AFixed,
  AAnchorRight: Boolean): TAtlasFitItem;
begin
  Result.Bounds := ABounds;
  Result.TextWidth := ATextWidth;
  Result.Extra := AExtra;
  Result.Fixed := AFixed;
  Result.AnchorRight := AAnchorRight;
end;

{ TAtlasFitText }

class function TAtlasFitText.Width(const AItems: TArray<TAtlasFitItem>; APadding, AMinWidth: Integer): Integer;
var
  mItem: TAtlasFitItem;
begin
  Result := AMinWidth;
  for mItem in AItems do
  begin
    if mItem.TextWidth + APadding + mItem.Extra > Result then
    begin
      Result := mItem.TextWidth + APadding + mItem.Extra;
    end;
  end;
end;

class function TAtlasFitText.IsRow(const AItems: TArray<TAtlasFitItem>): Boolean;
var
  mItem: TAtlasFitItem;
begin
  Result := Length(AItems) > 1;
  for mItem in AItems do
  begin
    if Abs(mItem.Bounds.Top - AItems[0].Bounds.Top) > cRowTolerance then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Indizes von links nach rechts.</summary>
function ByLeft(const AItems: TArray<TAtlasFitItem>): TArray<Integer>;
var
  mIndex, mPos, mValue: Integer;
begin
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := mIndex;
  end;
  for mIndex := 1 to High(Result) do
  begin
    mValue := Result[mIndex];
    mPos := mIndex - 1;
    while (mPos >= 0) and (AItems[Result[mPos]].Bounds.Left > AItems[mValue].Bounds.Left) do
    begin
      Result[mPos + 1] := Result[mPos];
      Dec(mPos);
    end;
    Result[mPos + 1] := mValue;
  end;
end;

function NewWidth(const AItem: TAtlasFitItem; AWidth: Integer): Integer;
begin
  Result := AWidth;
  if AItem.Fixed then
  begin
    Result := AItem.Bounds.Width;
  end;
end;

/// <summary>Reihe: Abstände bleiben, die linke bzw. rechte Kante der Reihe auch.</summary>
function ApplyRow(const AItems: TArray<TAtlasFitItem>; AWidth, AParentWidth: Integer): TArray<TRect>;
var
  mOrder: TArray<Integer>;
  mIndex, mPos, mEdge, mWidth: Integer;
  mLast: TAtlasFitItem;
begin
  SetLength(Result, Length(AItems));
  mOrder := ByLeft(AItems);
  mLast := AItems[mOrder[High(mOrder)]];
  if mLast.AnchorRight or (mLast.Bounds.Right >= AParentWidth - TAtlasFitText.cEdgeTolerance) then
  begin
    mEdge := mLast.Bounds.Right;
    for mPos := High(mOrder) downto 0 do
    begin
      mIndex := mOrder[mPos];
      mWidth := NewWidth(AItems[mIndex], AWidth);
      if mPos < High(mOrder) then
      begin
        // Abstand zum rechten Nachbarn wie bisher.
        mEdge := mEdge - (AItems[mOrder[mPos + 1]].Bounds.Left - AItems[mIndex].Bounds.Right);
      end;
      Result[mIndex] := Rect(mEdge - mWidth, AItems[mIndex].Bounds.Top, mEdge, AItems[mIndex].Bounds.Bottom);
      mEdge := mEdge - mWidth;
    end;
    Exit;
  end;
  mEdge := AItems[mOrder[0]].Bounds.Left;
  for mPos := 0 to High(mOrder) do
  begin
    mIndex := mOrder[mPos];
    mWidth := NewWidth(AItems[mIndex], AWidth);
    if mPos > 0 then
    begin
      mEdge := mEdge + (AItems[mIndex].Bounds.Left - AItems[mOrder[mPos - 1]].Bounds.Right);
    end;
    Result[mIndex] := Rect(mEdge, AItems[mIndex].Bounds.Top, mEdge + mWidth, AItems[mIndex].Bounds.Bottom);
    mEdge := mEdge + mWidth;
  end;
end;

class function TAtlasFitText.Apply(const AItems: TArray<TAtlasFitItem>; AWidth, AParentWidth: Integer): TArray<TRect>;
var
  mIndex, mWidth: Integer;
  mBounds: TRect;
begin
  if IsRow(AItems) then
  begin
    Exit(ApplyRow(AItems, AWidth, AParentWidth));
  end;
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    mBounds := AItems[mIndex].Bounds;
    mWidth := NewWidth(AItems[mIndex], AWidth);
    if AItems[mIndex].AnchorRight then
    begin
      Result[mIndex] := Rect(mBounds.Right - mWidth, mBounds.Top, mBounds.Right, mBounds.Bottom);
    end
    else
    begin
      Result[mIndex] := Rect(mBounds.Left, mBounds.Top, mBounds.Left + mWidth, mBounds.Bottom);
    end;
  end;
end;

class function TAtlasFitText.StripAccel(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if AText[mIndex] = '&' then
    begin
      Inc(mIndex);
      if (mIndex <= Length(AText)) and (AText[mIndex] = '&') then
      begin
        Result := Result + '&';
        Inc(mIndex);
      end;
      Continue;
    end;
    Result := Result + AText[mIndex];
    Inc(mIndex);
  end;
end;

class function TAtlasFitText.Lines(const AText: string): TArray<string>;
var
  mText, mLine: string;
begin
  mText := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  Result := nil;
  for mLine in mText.Split([#10]) do
  begin
    Result := Result + [StripAccel(mLine)];
  end;
  if Result = nil then
  begin
    Result := [''];
  end;
end;

end.
