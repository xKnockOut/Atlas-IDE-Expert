unit Atlas.Core.Designer.Gaps;

// Abstandsgriffe im Designer (#734), ohne VCL und Windows:
// - Detect erkennt, ob eine Auswahl eine Reihe (alle überlappen senkrecht,
//   nebeneinander ohne Überlappung) oder eine Spalte (entsprechend
//   waagerecht) bildet, ordnet sie nach Lage und misst die Abstände zwischen
//   den Nachbarn. Gemischte oder überlappende Anordnungen ergeben None.
// - Respace setzt alle Abstände auf denselben Wert; die Größen bleiben, nur
//   Left bzw. Top ändern sich. Fester Punkt: Mitte der Gruppe, erste oder
//   letzte Komponente.
// - Snap rastet an den Werten aus designer.gapHandles.snapValues ein.
// - Outside meldet Rechtecke, die aus dem Client des Parents ragen.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasGapAxis = (None, Row, Column);
  TAtlasGapAnchor = (Center, First, Last);
{$SCOPEDENUMS OFF}

  TAtlasGapLayout = record
    Axis: TAtlasGapAxis;
    /// <summary>Indizes der Rechtecke nach Lage (links nach rechts bzw. oben nach unten).</summary>
    Order: TArray<Integer>;
    /// <summary>Abstand zwischen Order[i] und Order[i + 1].</summary>
    Gaps: TArray<Integer>;
  end;

  TAtlasGaps = class
  public const
    cAnchorCenter = 'center';
    cAnchorFirst = 'first';
    cAnchorLast = 'last';
    /// <summary>Höchster Abstand in Pixeln, ab dem ein Wert an einen Rastwert springt.</summary>
    cSnapRange = 3;
    cMaxGap = 1000;
  public
    class function Detect(const ARects: TArray<TRect>): TAtlasGapLayout; static;
    /// <summary>Alle Abstände der Gruppe auf AGap; Ergebnis in der Reihenfolge von ARects.</summary>
    class function Respace(const ARects: TArray<TRect>; const ALayout: TAtlasGapLayout; AGap: Integer;
      AAnchor: TAtlasGapAnchor): TArray<TRect>; static;
    /// <summary>AValue an den nächsten Wert aus AValues, wenn er höchstens ARange entfernt ist.</summary>
    class function Snap(AValue: Integer; const AValues: TArray<Integer>; ARange: Integer): Integer; static;
    /// <summary>Abstände, die vom häufigsten Abstand abweichen (gedämpft gezeichnet).</summary>
    class function Deviating(const AGaps: TArray<Integer>): TArray<Boolean>; static;
    /// <summary>Ragt das Rechteck aus AClient (Client des Parents)?</summary>
    class function Outside(const ARects: TArray<TRect>; const AClient: TRect): TArray<Boolean>; static;
    /// <summary>Rastwerte aus „4, 8, 12, 16“: Zahlen von 0 bis cMaxGap, sortiert, ohne Doppelte.</summary>
    class function ParseValues(const AText: string): TArray<Integer>; static;
    /// <summary>Anker aus center/first/last; Unbekanntes = Center.</summary>
    class function AnchorOf(const AText: string): TAtlasGapAnchor; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults;

function NearOf(const ARect: TRect; AAxis: TAtlasGapAxis): Integer;
begin
  if AAxis = TAtlasGapAxis.Row then
  begin
    Result := ARect.Left;
  end
  else
  begin
    Result := ARect.Top;
  end;
end;

function FarOf(const ARect: TRect; AAxis: TAtlasGapAxis): Integer;
begin
  if AAxis = TAtlasGapAxis.Row then
  begin
    Result := ARect.Right;
  end
  else
  begin
    Result := ARect.Bottom;
  end;
end;

/// <summary>Überlappen alle Rechtecke quer zur Achse (gemeinsamer Streifen)?</summary>
function CrossOverlap(const ARects: TArray<TRect>; AAxis: TAtlasGapAxis): Boolean;
var
  mLow, mHigh: Integer;
  mRect: TRect;
begin
  mLow := Low(Integer);
  mHigh := High(Integer);
  for mRect in ARects do
  begin
    if AAxis = TAtlasGapAxis.Row then
    begin
      mLow := Max(mLow, mRect.Top);
      mHigh := Min(mHigh, mRect.Bottom);
    end
    else
    begin
      mLow := Max(mLow, mRect.Left);
      mHigh := Min(mHigh, mRect.Right);
    end;
  end;
  Result := mLow < mHigh;
end;

function SortedOrder(const ARects: TArray<TRect>; AAxis: TAtlasGapAxis): TArray<Integer>;
var
  mIndex: Integer;
  mRects: TArray<TRect>;
  mAxis: TAtlasGapAxis;
begin
  SetLength(Result, Length(ARects));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := mIndex;
  end;
  mRects := ARects;
  mAxis := AAxis;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := CompareValue(NearOf(mRects[ALeft], mAxis), NearOf(mRects[ARight], mAxis));
      if Result = 0 then
      begin
        Result := CompareValue(ALeft, ARight);
      end;
    end));
end;

/// <summary>Layout entlang AAxis; Axis = None, wenn sich Nachbarn überlappen.</summary>
function LayoutAlong(const ARects: TArray<TRect>; AAxis: TAtlasGapAxis): TAtlasGapLayout;
var
  mIndex, mGap: Integer;
begin
  Result.Axis := TAtlasGapAxis.None;
  Result.Order := nil;
  Result.Gaps := nil;
  if not CrossOverlap(ARects, AAxis) then
  begin
    Exit;
  end;
  Result.Order := SortedOrder(ARects, AAxis);
  SetLength(Result.Gaps, Length(ARects) - 1);
  for mIndex := 0 to High(Result.Gaps) do
  begin
    mGap := NearOf(ARects[Result.Order[mIndex + 1]], AAxis) - FarOf(ARects[Result.Order[mIndex]], AAxis);
    if mGap < 0 then
    begin
      Result.Order := nil;
      Result.Gaps := nil;
      Exit;
    end;
    Result.Gaps[mIndex] := mGap;
  end;
  Result.Axis := AAxis;
end;

function Contains(const AValues: TArray<Integer>; AValue: Integer): Boolean;
var
  mValue: Integer;
begin
  for mValue in AValues do
  begin
    if mValue = AValue then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasGaps }

class function TAtlasGaps.Detect(const ARects: TArray<TRect>): TAtlasGapLayout;
begin
  Result := Default(TAtlasGapLayout);
  if Length(ARects) < 2 then
  begin
    Exit;
  end;
  Result := LayoutAlong(ARects, TAtlasGapAxis.Row);
  if Result.Axis = TAtlasGapAxis.None then
  begin
    Result := LayoutAlong(ARects, TAtlasGapAxis.Column);
  end;
end;

class function TAtlasGaps.Respace(const ARects: TArray<TRect>; const ALayout: TAtlasGapLayout; AGap: Integer;
  AAnchor: TAtlasGapAnchor): TArray<TRect>;
var
  mIndex, mPos, mOldStart, mOldEnd, mNewSpan, mCount: Integer;
  mRect: TRect;
begin
  Result := Copy(ARects);
  mCount := Length(ALayout.Order);
  if (ALayout.Axis = TAtlasGapAxis.None) or (mCount < 2) then
  begin
    Exit;
  end;
  AGap := EnsureRange(AGap, 0, cMaxGap);
  mOldStart := NearOf(ARects[ALayout.Order[0]], ALayout.Axis);
  mOldEnd := FarOf(ARects[ALayout.Order[mCount - 1]], ALayout.Axis);
  mNewSpan := AGap * (mCount - 1);
  for mIndex := 0 to mCount - 1 do
  begin
    mNewSpan := mNewSpan + FarOf(ARects[ALayout.Order[mIndex]], ALayout.Axis) -
      NearOf(ARects[ALayout.Order[mIndex]], ALayout.Axis);
  end;
  case AAnchor of
    TAtlasGapAnchor.First:
      mPos := mOldStart;
    TAtlasGapAnchor.Last:
      mPos := mOldEnd - mNewSpan;
  else
    mPos := mOldStart + (mOldEnd - mOldStart - mNewSpan) div 2;
  end;
  for mIndex := 0 to mCount - 1 do
  begin
    mRect := ARects[ALayout.Order[mIndex]];
    if ALayout.Axis = TAtlasGapAxis.Row then
    begin
      mRect.Offset(mPos - mRect.Left, 0);
    end
    else
    begin
      mRect.Offset(0, mPos - mRect.Top);
    end;
    Result[ALayout.Order[mIndex]] := mRect;
    mPos := FarOf(mRect, ALayout.Axis) + AGap;
  end;
end;

class function TAtlasGaps.Snap(AValue: Integer; const AValues: TArray<Integer>; ARange: Integer): Integer;
var
  mValue, mBest: Integer;
begin
  Result := AValue;
  mBest := ARange + 1;
  for mValue in AValues do
  begin
    if Abs(mValue - AValue) < mBest then
    begin
      mBest := Abs(mValue - AValue);
      Result := mValue;
    end;
  end;
end;

class function TAtlasGaps.Deviating(const AGaps: TArray<Integer>): TArray<Boolean>;
var
  mCounts: TDictionary<Integer, Integer>;
  mGap, mMode, mBest, mCount, mIndex: Integer;
begin
  SetLength(Result, Length(AGaps));
  mCounts := TDictionary<Integer, Integer>.Create;
  try
    mMode := 0;
    mBest := 0;
    for mGap in AGaps do
    begin
      mCount := 0;
      mCounts.TryGetValue(mGap, mCount);
      Inc(mCount);
      mCounts.AddOrSetValue(mGap, mCount);
      // Gleich häufig: der zuerst gefundene bleibt.
      if mCount > mBest then
      begin
        mBest := mCount;
        mMode := mGap;
      end;
    end;
  finally
    mCounts.Free;
  end;
  for mIndex := 0 to High(AGaps) do
  begin
    Result[mIndex] := AGaps[mIndex] <> mMode;
  end;
end;

class function TAtlasGaps.Outside(const ARects: TArray<TRect>; const AClient: TRect): TArray<Boolean>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ARects));
  for mIndex := 0 to High(ARects) do
  begin
    Result[mIndex] := (ARects[mIndex].Left < AClient.Left) or (ARects[mIndex].Top < AClient.Top) or
      (ARects[mIndex].Right > AClient.Right) or (ARects[mIndex].Bottom > AClient.Bottom);
  end;
end;

class function TAtlasGaps.ParseValues(const AText: string): TArray<Integer>;
var
  mPart: string;
  mValue: Integer;
begin
  Result := nil;
  for mPart in AText.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if TryStrToInt(mPart.Trim, mValue) and (mValue >= 0) and (mValue <= cMaxGap) and not Contains(Result, mValue) then
    begin
      Result := Result + [mValue];
    end;
  end;
  TArray.Sort<Integer>(Result);
end;

class function TAtlasGaps.AnchorOf(const AText: string): TAtlasGapAnchor;
begin
  if SameText(AText, cAnchorFirst) then
  begin
    Result := TAtlasGapAnchor.First;
  end
  else if SameText(AText, cAnchorLast) then
  begin
    Result := TAtlasGapAnchor.Last;
  end
  else
  begin
    Result := TAtlasGapAnchor.Center;
  end;
end;

end.
