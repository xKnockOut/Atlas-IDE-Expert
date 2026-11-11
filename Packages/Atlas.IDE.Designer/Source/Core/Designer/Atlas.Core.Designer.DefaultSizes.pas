unit Atlas.Core.Designer.DefaultSizes;

// Standardgrößen je Komponentenklasse im Designer (#747), ohne VCL und
// Windows:
// - Tabelle als Text „Klasse=Breite,Höhe; …“ (designer.defaultSizes.table).
//   Ein leerer Wert bleibt unverändert, „text“ als Breite heißt Breite nach
//   Text (#730; die Breite misst das Plugin).
// - Ein Eintrag gilt für die Klasse und ihre Nachfahren; der Eintrag der
//   nächsten Klasse in der Ahnenreihe gewinnt (TCustomEdit deckt TEdit ab,
//   solange TEdit keinen eigenen hat).
// - Lage: Reihe (gleiche Oberkante ± cRowTolerance, nebeneinander) behält die
//   Abstände; ihre rechte Kante bleibt, wenn die rechteste Komponente rechts
//   verankert ist oder am rechten Rand liegt, sonst die linke. Einzelne
//   behalten links, rechts verankerte rechts; unten verankerte behalten die
//   untere Kante.
// - Lernen: die häufigste Größe je Klasse aus den Komponenten eines Formulars
//   (bei Gleichstand die zuerst gesehene).

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasSizeKind = (Keep, Fixed, Text);
{$SCOPEDENUMS OFF}

  TAtlasSizeValue = record
    Kind: TAtlasSizeKind;
    Value: Integer;
    class function Keep: TAtlasSizeValue; static;
    class function Fixed(AValue: Integer): TAtlasSizeValue; static;
    class function Text: TAtlasSizeValue; static;
    function ToText: string;
  end;

  TAtlasSizeEntry = record
    ClassName: string;
    Width: TAtlasSizeValue;
    Height: TAtlasSizeValue;
    class function Create(const AClassName: string; const AWidth, AHeight: TAtlasSizeValue): TAtlasSizeEntry; static;
  end;

  /// <summary>Eine Komponente für die Lage: Rechteck, Sollgröße (-1 = bleibt) und Anker.</summary>
  TAtlasSizeItem = record
    Bounds: TRect;
    Width: Integer;
    Height: Integer;
    AnchorRight: Boolean;
    AnchorBottom: Boolean;
    class function Create(const ABounds: TRect; AWidth, AHeight: Integer; AAnchorRight,
      AAnchorBottom: Boolean): TAtlasSizeItem; static;
  end;

  /// <summary>Eine Komponente des Formulars für das Lernen.</summary>
  TAtlasSizeSample = record
    ClassName: string;
    Size: TSize;
    class function Create(const AClassName: string; AWidth, AHeight: Integer): TAtlasSizeSample; static;
  end;

  TAtlasDefaultSizes = class
  public const
    cRowTolerance = 4;
    cEdgeTolerance = 16;
    cTextValue = 'text';
  public
    /// <summary>Tabelle aus dem Text; unbrauchbare Einträge fallen weg.</summary>
    class function Parse(const AText: string): TArray<TAtlasSizeEntry>; static;
    class function ToText(const AEntries: TArray<TAtlasSizeEntry>): string; static;
    /// <summary>Eintrag für die Ahnenreihe AClassChain (die Klasse zuerst); False ohne.</summary>
    class function Resolve(const AEntries: TArray<TAtlasSizeEntry>; const AClassChain: TArray<string>;
      out AEntry: TAtlasSizeEntry): Boolean; static;
    /// <summary>Sollwert: -1 bleibt; ATextSize für „text“ (-1 ohne Text).</summary>
    class function Target(const AValue: TAtlasSizeValue; ATextSize: Integer): Integer; static;
    /// <summary>Neue Lage aller Komponenten eines Parents der Breite AParentWidth.</summary>
    class function Layout(const AItems: TArray<TAtlasSizeItem>; AParentWidth: Integer): TArray<TRect>; static;
    /// <summary>Häufigste Größe je Klasse, Klassen in der Reihenfolge des ersten Auftretens.</summary>
    class function Learn(const ASamples: TArray<TAtlasSizeSample>): TArray<TAtlasSizeEntry>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasSizeValue }

class function TAtlasSizeValue.Keep: TAtlasSizeValue;
begin
  Result.Kind := TAtlasSizeKind.Keep;
  Result.Value := 0;
end;

class function TAtlasSizeValue.Fixed(AValue: Integer): TAtlasSizeValue;
begin
  Result.Kind := TAtlasSizeKind.Fixed;
  Result.Value := AValue;
end;

class function TAtlasSizeValue.Text: TAtlasSizeValue;
begin
  Result.Kind := TAtlasSizeKind.Text;
  Result.Value := 0;
end;

function TAtlasSizeValue.ToText: string;
begin
  case Kind of
    TAtlasSizeKind.Fixed:
      Result := IntToStr(Value);
    TAtlasSizeKind.Text:
      Result := TAtlasDefaultSizes.cTextValue;
  else
    Result := '';
  end;
end;

{ TAtlasSizeEntry }

class function TAtlasSizeEntry.Create(const AClassName: string; const AWidth,
  AHeight: TAtlasSizeValue): TAtlasSizeEntry;
begin
  Result.ClassName := AClassName;
  Result.Width := AWidth;
  Result.Height := AHeight;
end;

{ TAtlasSizeItem }

class function TAtlasSizeItem.Create(const ABounds: TRect; AWidth, AHeight: Integer; AAnchorRight,
  AAnchorBottom: Boolean): TAtlasSizeItem;
begin
  Result.Bounds := ABounds;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.AnchorRight := AAnchorRight;
  Result.AnchorBottom := AAnchorBottom;
end;

{ TAtlasSizeSample }

class function TAtlasSizeSample.Create(const AClassName: string; AWidth, AHeight: Integer): TAtlasSizeSample;
begin
  Result.ClassName := AClassName;
  Result.Size := TSize.Create(AWidth, AHeight);
end;

{ TAtlasDefaultSizes }

/// <summary>Ein Wert der Tabelle; False bei unbrauchbarem Text. AAllowText: „text“ erlaubt.</summary>
function ParseValue(const AText: string; AAllowText: Boolean; out AValue: TAtlasSizeValue): Boolean;
var
  mNumber: Integer;
begin
  Result := True;
  if AText = '' then
  begin
    AValue := TAtlasSizeValue.Keep;
  end
  else if AAllowText and SameText(AText, TAtlasDefaultSizes.cTextValue) then
  begin
    AValue := TAtlasSizeValue.Text;
  end
  else
  begin
    Result := TryStrToInt(AText, mNumber) and (mNumber > 0);
    AValue := TAtlasSizeValue.Fixed(mNumber);
  end;
end;

class function TAtlasDefaultSizes.Parse(const AText: string): TArray<TAtlasSizeEntry>;
var
  mPart: string;
  mPair, mSize: TArray<string>;
  mWidth, mHeight: TAtlasSizeValue;
begin
  Result := nil;
  for mPart in AText.Split([';']) do
  begin
    mPair := mPart.Split(['=']);
    if (Length(mPair) <> 2) or (Trim(mPair[0]) = '') then
    begin
      Continue;
    end;
    mSize := mPair[1].Split([',']);
    if (Length(mSize) <> 2) or not ParseValue(Trim(mSize[0]), True, mWidth) or
      not ParseValue(Trim(mSize[1]), False, mHeight) then
    begin
      Continue;
    end;
    Result := Result + [TAtlasSizeEntry.Create(Trim(mPair[0]), mWidth, mHeight)];
  end;
end;

class function TAtlasDefaultSizes.ToText(const AEntries: TArray<TAtlasSizeEntry>): string;
var
  mEntry: TAtlasSizeEntry;
begin
  Result := '';
  for mEntry in AEntries do
  begin
    if Result <> '' then
    begin
      Result := Result + '; ';
    end;
    Result := Result + mEntry.ClassName + '=' + mEntry.Width.ToText + ',' + mEntry.Height.ToText;
  end;
end;

class function TAtlasDefaultSizes.Resolve(const AEntries: TArray<TAtlasSizeEntry>;
  const AClassChain: TArray<string>; out AEntry: TAtlasSizeEntry): Boolean;
var
  mClass: string;
  mEntry: TAtlasSizeEntry;
begin
  for mClass in AClassChain do
  begin
    for mEntry in AEntries do
    begin
      if SameText(mEntry.ClassName, mClass) then
      begin
        AEntry := mEntry;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TAtlasDefaultSizes.Target(const AValue: TAtlasSizeValue; ATextSize: Integer): Integer;
begin
  case AValue.Kind of
    TAtlasSizeKind.Fixed:
      Result := AValue.Value;
    TAtlasSizeKind.Text:
      Result := ATextSize;
  else
    Result := -1;
  end;
end;

function NewWidth(const AItem: TAtlasSizeItem): Integer;
begin
  Result := AItem.Bounds.Width;
  if AItem.Width > 0 then
  begin
    Result := AItem.Width;
  end;
end;

/// <summary>Höhe nach AItem.Height; unten verankert bleibt die untere Kante.</summary>
function WithHeight(const ARect: TRect; const AItem: TAtlasSizeItem): TRect;
begin
  Result := ARect;
  if AItem.Height <= 0 then
  begin
    Exit;
  end;
  if AItem.AnchorBottom then
  begin
    Result.Top := Result.Bottom - AItem.Height;
  end
  else
  begin
    Result.Bottom := Result.Top + AItem.Height;
  end;
end;

/// <summary>Indizes der Reihe, zu der AFirst gehört (gleiche Oberkante), links nach rechts.</summary>
function RowOf(const AItems: TArray<TAtlasSizeItem>; AFirst: Integer; const ADone: TArray<Boolean>): TArray<Integer>;
var
  mIndex, mMove, mAt: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AItems) do
  begin
    if not ADone[mIndex] and (Abs(AItems[mIndex].Bounds.Top - AItems[AFirst].Bounds.Top) <=
      TAtlasDefaultSizes.cRowTolerance) then
    begin
      Result := Result + [mIndex];
    end;
  end;
  // Einfügen sortiert: Reihen haben nur wenige Komponenten.
  for mIndex := 1 to High(Result) do
  begin
    mMove := Result[mIndex];
    mAt := mIndex;
    while (mAt > 0) and (AItems[Result[mAt - 1]].Bounds.Left > AItems[mMove].Bounds.Left) do
    begin
      Result[mAt] := Result[mAt - 1];
      Dec(mAt);
    end;
    Result[mAt] := mMove;
  end;
end;

/// <summary>Liegen die Komponenten von ARow ohne Überlappung nebeneinander?</summary>
function SideBySide(const AItems: TArray<TAtlasSizeItem>; const ARow: TArray<Integer>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(ARow) > 1;
  for mIndex := 1 to High(ARow) do
  begin
    Result := Result and (AItems[ARow[mIndex]].Bounds.Left >= AItems[ARow[mIndex - 1]].Bounds.Right);
  end;
end;

procedure PlaceRow(const AItems: TArray<TAtlasSizeItem>; const ARow: TArray<Integer>; AParentWidth: Integer;
  var ARects: TArray<TRect>);
var
  mIndex, mX, mGap: Integer;
  mLast: TAtlasSizeItem;
begin
  mLast := AItems[ARow[High(ARow)]];
  if mLast.AnchorRight or (AParentWidth - mLast.Bounds.Right <= TAtlasDefaultSizes.cEdgeTolerance) then
  begin
    mX := mLast.Bounds.Right;
    for mIndex := High(ARow) downto 0 do
    begin
      ARects[ARow[mIndex]] := Rect(mX - NewWidth(AItems[ARow[mIndex]]), AItems[ARow[mIndex]].Bounds.Top, mX,
        AItems[ARow[mIndex]].Bounds.Bottom);
      if mIndex > 0 then
      begin
        mGap := AItems[ARow[mIndex]].Bounds.Left - AItems[ARow[mIndex - 1]].Bounds.Right;
        mX := ARects[ARow[mIndex]].Left - mGap;
      end;
    end;
    Exit;
  end;
  mX := AItems[ARow[0]].Bounds.Left;
  for mIndex := 0 to High(ARow) do
  begin
    ARects[ARow[mIndex]] := Rect(mX, AItems[ARow[mIndex]].Bounds.Top, mX + NewWidth(AItems[ARow[mIndex]]),
      AItems[ARow[mIndex]].Bounds.Bottom);
    if mIndex < High(ARow) then
    begin
      mGap := AItems[ARow[mIndex + 1]].Bounds.Left - AItems[ARow[mIndex]].Bounds.Right;
      mX := ARects[ARow[mIndex]].Right + mGap;
    end;
  end;
end;

function PlaceSingle(const AItem: TAtlasSizeItem): TRect;
begin
  Result := AItem.Bounds;
  if AItem.AnchorRight then
  begin
    Result.Left := Result.Right - NewWidth(AItem);
  end
  else
  begin
    Result.Right := Result.Left + NewWidth(AItem);
  end;
end;

class function TAtlasDefaultSizes.Layout(const AItems: TArray<TAtlasSizeItem>; AParentWidth: Integer): TArray<TRect>;
var
  mDone: TArray<Boolean>;
  mIndex, mMember: Integer;
  mRow: TArray<Integer>;
begin
  SetLength(Result, Length(AItems));
  SetLength(mDone, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    if mDone[mIndex] then
    begin
      Continue;
    end;
    mRow := RowOf(AItems, mIndex, mDone);
    if SideBySide(AItems, mRow) then
    begin
      PlaceRow(AItems, mRow, AParentWidth, Result);
    end
    else
    begin
      mRow := [mIndex];
      Result[mIndex] := PlaceSingle(AItems[mIndex]);
    end;
    for mMember in mRow do
    begin
      mDone[mMember] := True;
    end;
  end;
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := WithHeight(Result[mIndex], AItems[mIndex]);
  end;
end;

type
  /// <summary>Eine Größe einer Klasse beim Lernen und wie oft sie vorkommt.</summary>
  TSizeCount = record
    ClassName: string;
    Size: TSize;
    Count: Integer;
  end;

function Known(const AClasses: TArray<string>; const AClass: string): Boolean;
var
  mClass: string;
begin
  for mClass in AClasses do
  begin
    if SameText(mClass, AClass) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Jede Größe je Klasse mit ihrer Anzahl, in der Reihenfolge des ersten Auftretens.</summary>
function Tally(const ASamples: TArray<TAtlasSizeSample>): TArray<TSizeCount>;
var
  mSample: TAtlasSizeSample;
  mIndex, mFound: Integer;
  mCount: TSizeCount;
begin
  Result := nil;
  for mSample in ASamples do
  begin
    mFound := -1;
    for mIndex := 0 to High(Result) do
    begin
      if SameText(Result[mIndex].ClassName, mSample.ClassName) and (Result[mIndex].Size = mSample.Size) then
      begin
        mFound := mIndex;
      end;
    end;
    if mFound < 0 then
    begin
      mCount.ClassName := mSample.ClassName;
      mCount.Size := mSample.Size;
      mCount.Count := 0;
      Result := Result + [mCount];
      mFound := High(Result);
    end;
    Inc(Result[mFound].Count);
  end;
end;

class function TAtlasDefaultSizes.Learn(const ASamples: TArray<TAtlasSizeSample>): TArray<TAtlasSizeEntry>;
var
  mCounts: TArray<TSizeCount>;
  mIndex, mBest: Integer;
  mClasses: TArray<string>;
  mClass: string;
begin
  mCounts := Tally(ASamples);
  mClasses := nil;
  for mIndex := 0 to High(mCounts) do
  begin
    if not Known(mClasses, mCounts[mIndex].ClassName) then
    begin
      mClasses := mClasses + [mCounts[mIndex].ClassName];
    end;
  end;
  Result := nil;
  for mClass in mClasses do
  begin
    // Strikt größer: Bei Gleichstand bleibt die zuerst gesehene Größe.
    mBest := -1;
    for mIndex := 0 to High(mCounts) do
    begin
      if SameText(mCounts[mIndex].ClassName, mClass) and ((mBest < 0) or (mCounts[mIndex].Count > mCounts[mBest].Count))
        then
      begin
        mBest := mIndex;
      end;
    end;
    Result := Result + [TAtlasSizeEntry.Create(mClass, TAtlasSizeValue.Fixed(mCounts[mBest].Size.cx),
      TAtlasSizeValue.Fixed(mCounts[mBest].Size.cy))];
  end;
end;

end.
