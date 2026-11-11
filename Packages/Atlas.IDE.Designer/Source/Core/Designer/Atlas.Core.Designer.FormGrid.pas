unit Atlas.Core.Designer.FormGrid;

// Label-Feld-Paare als Formularraster anordnen (#731), ohne VCL und Windows.
// - Paare: Partner aus FocusControl (#729), sonst das nächste Feld rechts
//   daneben (senkrecht überlappend) bzw. darunter (waagerecht überlappend).
// - Einträge: Felder zeilenweise nach der alten Lage (ähnliche Oberkante,
//   ± halbe Höhe), in der Zeile von links nach rechts. Ein Feld mit Label
//   beginnt einen Eintrag; Felder ohne Label hängen am Eintrag links von
//   ihnen („PLZ / Ort“), sonst stehen sie allein in der Feldspalte. Labels
//   ohne Feld zählen wie Felder.
// - Raster ab der linken oberen Ecke der Auswahl: Labelspalte so breit wie
//   das breiteste Label plus ALabelGap, Labels links- oder rechtsbündig oder
//   über dem Feld; Felder oben in der Zeile, Labels auf deren Grundlinie,
//   bei mehrzeiligen Feldern oben bündig. Zeilenabstand ARowGap; mit
//   TwoPerRow zwei Einträge je Zeile. EqualWidth macht einzelne Felder so
//   breit wie das breiteste.
// - TabOrder: Felder in der neuen Lesereihenfolge.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasGridLabelAlign = (Left, Right, Above);
{$SCOPEDENUMS OFF}

  TAtlasGridItem = record
    Name: string;
    Bounds: TRect;
    IsLabel: Boolean;
    /// <summary>Feld eines Labels aus FocusControl; leer: nach Lage.</summary>
    Partner: string;
    /// <summary>Grundlinie unter der Oberkante: beim Label der Ascent, beim Feld die Textzeile; -1 mehrzeilig.</summary>
    Baseline: Integer;
    class function Create(const AName: string; const ABounds: TRect; AIsLabel: Boolean; const APartner: string;
      ABaseline: Integer): TAtlasGridItem; static;
  end;

  TAtlasGridOptions = record
    RowGap: Integer;
    LabelGap: Integer;
    LabelAlign: TAtlasGridLabelAlign;
    EqualWidth: Boolean;
    TwoPerRow: Boolean;
  end;

  TAtlasGridEntry = record
    /// <summary>Index des Labels; -1 ohne.</summary>
    LabelIndex: Integer;
    Fields: TArray<Integer>;
  end;

  TAtlasGridResult = record
    /// <summary>Neue Lage je Eingabe-Index.</summary>
    Bounds: TArray<TRect>;
    /// <summary>Felder (keine Labels) in Lesereihenfolge.</summary>
    TabOrder: TArray<Integer>;
  end;

  TAtlasFormGrid = class
  public const
    cAboveGap = 3;
  public
    /// <summary>Feld je Label (Index), -1 ohne; bei Nicht-Labels -1.</summary>
    class function Partners(const AItems: TArray<TAtlasGridItem>): TArray<Integer>; static;
    /// <summary>Einträge in alter Lesereihenfolge.</summary>
    class function Entries(const AItems: TArray<TAtlasGridItem>): TArray<TAtlasGridEntry>; static;
    class function Arrange(const AItems: TArray<TAtlasGridItem>; const AOptions: TAtlasGridOptions): TAtlasGridResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasGridItem }

class function TAtlasGridItem.Create(const AName: string; const ABounds: TRect; AIsLabel: Boolean;
  const APartner: string; ABaseline: Integer): TAtlasGridItem;
begin
  Result.Name := AName;
  Result.Bounds := ABounds;
  Result.IsLabel := AIsLabel;
  Result.Partner := APartner;
  Result.Baseline := ABaseline;
end;

{ Paare }

function IndexOfName(const AItems: TArray<TAtlasGridItem>; const AName: string): Integer;
begin
  for Result := 0 to High(AItems) do
  begin
    if SameText(AItems[Result].Name, AName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Abstand von ALabel zum Feld rechts daneben oder darunter; MaxInt, wenn es keins ist.</summary>
function Distance(const ALabel, AField: TRect): Integer;
begin
  Result := MaxInt;
  if (AField.Left >= ALabel.Right - 1) and (ALabel.Top < AField.Bottom) and (ALabel.Bottom > AField.Top) then
  begin
    Result := AField.Left - ALabel.Right;
  end
  else if (AField.Top >= ALabel.Bottom - 1) and (ALabel.Left < AField.Right) and (ALabel.Right > AField.Left) then
  begin
    Result := AField.Top - ALabel.Bottom;
  end;
end;

function NearestField(const AItems: TArray<TAtlasGridItem>; ALabel: Integer; const ATaken: TArray<Boolean>): Integer;
var
  mIndex, mBest, mDistance: Integer;
begin
  Result := -1;
  mBest := MaxInt;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].IsLabel or ATaken[mIndex] then
    begin
      Continue;
    end;
    mDistance := Distance(AItems[ALabel].Bounds, AItems[mIndex].Bounds);
    if mDistance < mBest then
    begin
      mBest := mDistance;
      Result := mIndex;
    end;
  end;
end;

class function TAtlasFormGrid.Partners(const AItems: TArray<TAtlasGridItem>): TArray<Integer>;
var
  mIndex, mField: Integer;
  mTaken: TArray<Boolean>;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  mTaken := nil;
  SetLength(mTaken, Length(AItems));
  // Erst FocusControl, dann die Lage für die übrigen Labels.
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := -1;
    mField := -1;
    if AItems[mIndex].IsLabel and (AItems[mIndex].Partner <> '') then
    begin
      mField := IndexOfName(AItems, AItems[mIndex].Partner);
    end;
    if (mField >= 0) and not AItems[mField].IsLabel and not mTaken[mField] then
    begin
      Result[mIndex] := mField;
      mTaken[mField] := True;
    end;
  end;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].IsLabel and (Result[mIndex] < 0) then
    begin
      Result[mIndex] := NearestField(AItems, mIndex, mTaken);
      if Result[mIndex] >= 0 then
      begin
        mTaken[Result[mIndex]] := True;
      end;
    end;
  end;
end;

{ Einträge }

/// <summary>Indizes nach Oberkante, bei gleicher nach linker Kante.</summary>
function SortedByTop(const AItems: TArray<TAtlasGridItem>; const AIndices: TArray<Integer>): TArray<Integer>;
var
  mOuter, mInner, mSwap: Integer;
begin
  Result := Copy(AIndices);
  for mOuter := 1 to High(Result) do
  begin
    mInner := mOuter;
    while (mInner > 0) and ((AItems[Result[mInner]].Bounds.Top < AItems[Result[mInner - 1]].Bounds.Top) or
      ((AItems[Result[mInner]].Bounds.Top = AItems[Result[mInner - 1]].Bounds.Top) and
      (AItems[Result[mInner]].Bounds.Left < AItems[Result[mInner - 1]].Bounds.Left))) do
    begin
      mSwap := Result[mInner];
      Result[mInner] := Result[mInner - 1];
      Result[mInner - 1] := mSwap;
      Dec(mInner);
    end;
  end;
end;

function SortedByLeft(const AItems: TArray<TAtlasGridItem>; const AIndices: TArray<Integer>): TArray<Integer>;
var
  mOuter, mInner, mSwap: Integer;
begin
  Result := Copy(AIndices);
  for mOuter := 1 to High(Result) do
  begin
    mInner := mOuter;
    while (mInner > 0) and (AItems[Result[mInner]].Bounds.Left < AItems[Result[mInner - 1]].Bounds.Left) do
    begin
      mSwap := Result[mInner];
      Result[mInner] := Result[mInner - 1];
      Result[mInner - 1] := mSwap;
      Dec(mInner);
    end;
  end;
end;

/// <summary>Zeilen aus Feldern und Labels ohne Feld: Oberkante bis halbe Höhe des ersten unter der Zeile.</summary>
function Rows(const AItems: TArray<TAtlasGridItem>; const APartners: TArray<Integer>): TArray<TArray<Integer>>;
var
  mIndex, mRowTop, mRowHalf: Integer;
  mCells, mRow: TArray<Integer>;
begin
  mCells := nil;
  for mIndex := 0 to High(AItems) do
  begin
    if not AItems[mIndex].IsLabel or (APartners[mIndex] < 0) then
    begin
      mCells := mCells + [mIndex];
    end;
  end;
  Result := nil;
  mRow := nil;
  mRowTop := 0;
  mRowHalf := 0;
  for mIndex in SortedByTop(AItems, mCells) do
  begin
    if (Length(mRow) > 0) and (AItems[mIndex].Bounds.Top > mRowTop + mRowHalf) then
    begin
      Result := Result + [SortedByLeft(AItems, mRow)];
      mRow := nil;
    end;
    if Length(mRow) = 0 then
    begin
      mRowTop := AItems[mIndex].Bounds.Top;
      mRowHalf := AItems[mIndex].Bounds.Height div 2;
    end;
    mRow := mRow + [mIndex];
  end;
  if Length(mRow) > 0 then
  begin
    Result := Result + [SortedByLeft(AItems, mRow)];
  end;
end;

function LabelOf(const APartners: TArray<Integer>; AField: Integer): Integer;
begin
  for Result := 0 to High(APartners) do
  begin
    if APartners[Result] = AField then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function Entry(ALabel, AField: Integer): TAtlasGridEntry;
begin
  Result.LabelIndex := ALabel;
  Result.Fields := [AField];
end;

class function TAtlasFormGrid.Entries(const AItems: TArray<TAtlasGridItem>): TArray<TAtlasGridEntry>;
var
  mPartners, mRow: TArray<Integer>;
  mIndex, mLabel: Integer;
  mOpen: Boolean;
begin
  mPartners := Partners(AItems);
  Result := nil;
  for mRow in Rows(AItems, mPartners) do
  begin
    mOpen := False;
    for mIndex in mRow do
    begin
      mLabel := LabelOf(mPartners, mIndex);
      if (mLabel < 0) and mOpen and not AItems[mIndex].IsLabel then
      begin
        Result[High(Result)].Fields := Result[High(Result)].Fields + [mIndex];
        Continue;
      end;
      Result := Result + [Entry(mLabel, mIndex)];
      mOpen := mLabel >= 0;
    end;
  end;
end;

{ Raster }

type
  TGridMeasure = record
    LabelWidth: Integer;
    LabelColumn: Integer;
    EqualWidth: Integer;
    ColumnWidth: Integer;
  end;

function FieldWidth(const AItems: TArray<TAtlasGridItem>; const AEntry: TAtlasGridEntry; AField: Integer;
  const AMeasure: TGridMeasure): Integer;
begin
  Result := AItems[AField].Bounds.Width;
  if (AMeasure.EqualWidth > 0) and (Length(AEntry.Fields) = 1) then
  begin
    Result := AMeasure.EqualWidth;
  end;
end;

function Measure(const AItems: TArray<TAtlasGridItem>; const AEntries: TArray<TAtlasGridEntry>;
  const AOptions: TAtlasGridOptions): TGridMeasure;
var
  mEntry: TAtlasGridEntry;
  mField, mWidth: Integer;
begin
  Result.LabelWidth := 0;
  Result.EqualWidth := 0;
  for mEntry in AEntries do
  begin
    if mEntry.LabelIndex >= 0 then
    begin
      Result.LabelWidth := Max(Result.LabelWidth, AItems[mEntry.LabelIndex].Bounds.Width);
    end;
    if AOptions.EqualWidth and (Length(mEntry.Fields) = 1) then
    begin
      Result.EqualWidth := Max(Result.EqualWidth, AItems[mEntry.Fields[0]].Bounds.Width);
    end;
  end;
  Result.LabelColumn := 0;
  if (Result.LabelWidth > 0) and (AOptions.LabelAlign <> TAtlasGridLabelAlign.Above) then
  begin
    Result.LabelColumn := Result.LabelWidth + AOptions.LabelGap;
  end;
  Result.ColumnWidth := 0;
  for mEntry in AEntries do
  begin
    mWidth := -AOptions.LabelGap;
    for mField in mEntry.Fields do
    begin
      mWidth := mWidth + FieldWidth(AItems, mEntry, mField, Result) + AOptions.LabelGap;
    end;
    Result.ColumnWidth := Max(Result.ColumnWidth, Result.LabelColumn + mWidth);
  end;
end;

/// <summary>Label vor den Feldern: links- oder rechtsbündig, auf der Grundlinie des ersten Felds.</summary>
function LabelBounds(const AItems: TArray<TAtlasGridItem>; const AEntry: TAtlasGridEntry; ALeft, AFieldTop: Integer;
  const AMeasure: TGridMeasure; AAlign: TAtlasGridLabelAlign): TRect;
var
  mLabel, mField: TAtlasGridItem;
  mTop, mLeft: Integer;
begin
  mLabel := AItems[AEntry.LabelIndex];
  mField := AItems[AEntry.Fields[0]];
  mTop := AFieldTop;
  if (mField.Baseline >= 0) and (mLabel.Baseline >= 0) then
  begin
    mTop := AFieldTop + mField.Baseline - mLabel.Baseline;
  end;
  mLeft := ALeft;
  if AAlign = TAtlasGridLabelAlign.Right then
  begin
    mLeft := ALeft + AMeasure.LabelWidth - mLabel.Bounds.Width;
  end;
  Result := Bounds(mLeft, mTop, mLabel.Bounds.Width, mLabel.Bounds.Height);
end;

/// <summary>Eintrag an AAt setzen; Höhe des Eintrags.</summary>
function PlaceEntry(const AItems: TArray<TAtlasGridItem>; const AEntry: TAtlasGridEntry; const AAt: TPoint;
  const AMeasure: TGridMeasure; const AOptions: TAtlasGridOptions; var ABounds: TArray<TRect>): Integer;
var
  mFieldTop, mFieldLeft, mHeight, mWidth: Integer;
  mField, mX, mY: Integer;
begin
  mX := AAt.X;
  mY := AAt.Y;
  mFieldTop := mY;
  if (AEntry.LabelIndex >= 0) and (AOptions.LabelAlign = TAtlasGridLabelAlign.Above) then
  begin
    ABounds[AEntry.LabelIndex] := Bounds(mX, mY, AItems[AEntry.LabelIndex].Bounds.Width,
      AItems[AEntry.LabelIndex].Bounds.Height);
    mFieldTop := mY + AItems[AEntry.LabelIndex].Bounds.Height + TAtlasFormGrid.cAboveGap;
  end;
  mFieldLeft := mX + AMeasure.LabelColumn;
  mHeight := 0;
  for mField in AEntry.Fields do
  begin
    mWidth := FieldWidth(AItems, AEntry, mField, AMeasure);
    ABounds[mField] := Bounds(mFieldLeft, mFieldTop, mWidth, AItems[mField].Bounds.Height);
    mFieldLeft := mFieldLeft + mWidth + AOptions.LabelGap;
    mHeight := Max(mHeight, AItems[mField].Bounds.Height);
  end;
  if (AEntry.LabelIndex >= 0) and (AOptions.LabelAlign <> TAtlasGridLabelAlign.Above) then
  begin
    ABounds[AEntry.LabelIndex] := LabelBounds(AItems, AEntry, mX, mFieldTop, AMeasure, AOptions.LabelAlign);
    mHeight := Max(mHeight, ABounds[AEntry.LabelIndex].Bottom - mFieldTop);
  end;
  Result := mFieldTop - mY + mHeight;
end;

function TabOrderOf(const AItems: TArray<TAtlasGridItem>; const AEntries: TArray<TAtlasGridEntry>): TArray<Integer>;
var
  mEntry: TAtlasGridEntry;
  mField: Integer;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    for mField in mEntry.Fields do
    begin
      if not AItems[mField].IsLabel then
      begin
        Result := Result + [mField];
      end;
    end;
  end;
end;

class function TAtlasFormGrid.Arrange(const AItems: TArray<TAtlasGridItem>;
  const AOptions: TAtlasGridOptions): TAtlasGridResult;
var
  mEntries: TArray<TAtlasGridEntry>;
  mMeasure: TGridMeasure;
  mIndex, mColumn, mColumns, mLeft, mTop, mRowHeight: Integer;
begin
  Result.Bounds := nil;
  SetLength(Result.Bounds, Length(AItems));
  mLeft := MaxInt;
  mTop := MaxInt;
  for mIndex := 0 to High(AItems) do
  begin
    Result.Bounds[mIndex] := AItems[mIndex].Bounds;
    mLeft := Min(mLeft, AItems[mIndex].Bounds.Left);
    mTop := Min(mTop, AItems[mIndex].Bounds.Top);
  end;
  mEntries := Entries(AItems);
  Result.TabOrder := TabOrderOf(AItems, mEntries);
  mMeasure := Measure(AItems, mEntries, AOptions);
  mColumns := IfThen(AOptions.TwoPerRow, 2, 1);
  mIndex := 0;
  while mIndex <= High(mEntries) do
  begin
    mRowHeight := 0;
    for mColumn := 0 to mColumns - 1 do
    begin
      if mIndex + mColumn <= High(mEntries) then
      begin
        mRowHeight := Max(mRowHeight, PlaceEntry(AItems, mEntries[mIndex + mColumn],
          Point(mLeft + mColumn * (mMeasure.ColumnWidth + 2 * AOptions.LabelGap), mTop), mMeasure, AOptions,
          Result.Bounds));
      end;
    end;
    mTop := mTop + mRowHeight + AOptions.RowGap;
    mIndex := mIndex + mColumns;
  end;
end;

end.
