unit Atlas.Core.Designer.Components;

// Designer-Leiste (#1442), ohne VCL und Windows:
// - TAtlasDesignerSearch: Suche im Fenster „Komponenten suchen“ über die
//   Komponenten des Formulars im Designer, ohne Groß-/Kleinschreibung, in
//   Name, Caption/Text und Klasse (wählbar). Reihenfolge: gleicher Name,
//   Name beginnt mit dem Suchwort, Wortanfang im Namen (nach „_“ oder vor
//   einem Großbuchstaben, „OK“ in „btnOK“), irgendwo im Namen; danach Treffer
//   nur in Caption/Text, dann nur in der Klasse. Bei Gleichstand nach Namen,
//   dann nach Lage im Formular. Ohne Suchwort: alle Komponenten der Art nach
//   Namen. Art: alle, Steuerelemente, nichtvisuelle, Container.
// - TAtlasDesignerGroups: Zeilen der Liste mit Gruppenköpfen nach
//   Elternelement (Hierarchie), nach Klasse oder flach; Gruppen in der
//   Reihenfolge ihres besten Treffers.
// - TAtlasTabOrder: Tab-Reihenfolge im Designer. OutOfOrder markiert
//   Steuerelemente, zu denen die Tab-Reihenfolge gegen die Lesereihenfolge
//   (Zeile, dann links nach rechts) zurückspringt, je Elternelement.
//   TAtlasTabClicks zählt beim Neuvergeben per Klick (experimentell) je
//   Elternelement hoch.
// - TAtlasDesignerAlign: Ausrichten der Auswahl (experimentell). Bezug ist die
//   zuerst gewählte Komponente; Abstände verteilen hält die äußeren fest.

interface

uses
  System.Types,
  System.Generics.Collections;

type
  /// <summary>Komponente des Formulars, wie Leiste und Suchfenster sie sehen.</summary>
  TAtlasDesignerItem = record
    Name: string;
    TypeName: string;
    /// <summary>Steuerelement (TControl); False = nichtvisuelle Komponente.</summary>
    Visual: Boolean;
    /// <summary>Steuerelement mit Kindern (TWinControl mit csAcceptsControls).</summary>
    Container: Boolean;
    /// <summary>Caption bzw. Text; '' ohne.</summary>
    Caption: string;
    /// <summary>Name des Elternelements; '' = direkt auf dem Formular bzw. nichtvisuell.</summary>
    ParentName: string;
    /// <summary>Lage im Formular (Client der Wurzel); leer bei nichtvisuellen ohne Symbol.</summary>
    Bounds: TRect;
    /// <summary>Gesetzte Eigenschaften für die Vorschau („Caption=OK“).</summary>
    Properties: TArray<string>;
    /// <summary>Belegte Ereignisse („OnClick=btnOKClick“).</summary>
    Events: TArray<string>;
    class function Create(const AName, AClassName: string; AVisual: Boolean): TAtlasDesignerItem; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Wie gut ein Text zum Suchwort passt; None = gar nicht.</summary>
  TAtlasDesignerMatch = (Exact, Prefix, WordStart, Contains, None);
  /// <summary>Worin gesucht wird.</summary>
  TAtlasDesignerField = (Name, Caption, ClassName);
  /// <summary>Welche Komponenten die Liste zeigt.</summary>
  TAtlasDesignerKind = (All, Controls, NonVisual, Containers);
  TAtlasDesignerGrouping = (Hierarchy, ClassName, Flat);
  TAtlasAlignKind = (Lefts, Rights, Tops, Bottoms, CentersH, CentersV, CenterInParentH, CenterInParentV,
    SameWidth, SameHeight, SpaceH, SpaceV);
{$SCOPEDENUMS OFF}

  TAtlasDesignerFields = set of TAtlasDesignerField;

  TAtlasDesignerSearch = class
  public
    /// <summary>Wie gut passt AText zu APattern (ohne Groß-/Kleinschreibung)? Leeres Suchwort: None.</summary>
    class function MatchOf(const AText, APattern: string): TAtlasDesignerMatch; static;
    /// <summary>Gehört AItem zur Art AKind?</summary>
    class function OfKind(const AItem: TAtlasDesignerItem; AKind: TAtlasDesignerKind): Boolean; static;
    /// <summary>Indizes der Treffer in AItems, beste zuerst. Ohne Suchwort alle der Art nach Namen.</summary>
    class function Find(const AItems: TArray<TAtlasDesignerItem>; const APattern: string;
      AFields: TAtlasDesignerFields; AKind: TAtlasDesignerKind): TArray<Integer>; static;
    /// <summary>Nächster Index von AIndex aus um ADelta, am Rand stehen bleiben; -1 ohne Zeilen.</summary>
    class function Step(AIndex, ACount, ADelta: Integer): Integer; static;
  end;

  /// <summary>Zeile der Trefferliste: Gruppenkopf (Item = -1) oder Komponente.</summary>
  TAtlasDesignerRow = record
    Header: Boolean;
    Caption: string;
    /// <summary>Zahl der Treffer der Gruppe (nur Kopf).</summary>
    Count: Integer;
    /// <summary>Index in den Komponenten; -1 im Kopf.</summary>
    Item: Integer;
  end;

  TAtlasDesignerGroups = class
  public
    /// <summary>Zeilen für die Treffer AHits (beste zuerst); flach ohne Köpfe. ARootName heißt die Gruppe ohne
    /// Elternelement.</summary>
    class function Rows(const AItems: TArray<TAtlasDesignerItem>; const AHits: TArray<Integer>;
      AGrouping: TAtlasDesignerGrouping; const ARootName: string): TArray<TAtlasDesignerRow>; static;
  end;

  /// <summary>Fokussierbares Steuerelement für die Tab-Reihenfolge.</summary>
  TAtlasTabStop = record
    Name: string;
    ParentName: string;
    TabOrder: Integer;
    Bounds: TRect;
    class function Create(const AName, AParentName: string; ATabOrder: Integer;
      const ABounds: TRect): TAtlasTabStop; static;
  end;

  TAtlasTabOrder = class
  public
    /// <summary>Lesereihenfolge: A vor B? Gleiche Zeile, wenn sich die Höhen zur Hälfte überdecken.</summary>
    class function ReadsBefore(const A, B: TRect): Boolean; static;
    /// <summary>Je Stop: springt die Tab-Reihenfolge seines Elternelements hierher zurück (gegen die
    /// Lesereihenfolge)?</summary>
    class function OutOfOrder(const AStops: TArray<TAtlasTabStop>): TArray<Boolean>; static;
  end;

  /// <summary>Neue Tab-Reihenfolge per Klick (experimentell): je Elternelement 0, 1, 2 …</summary>
  TAtlasTabClicks = class
  private
    FNext: TDictionary<string, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>TabOrder für den nächsten Klick unter AParentName.</summary>
    function Next(const AParentName: string): Integer;
    procedure Reset;
  end;

  TAtlasDesignerAlign = class
  public
    /// <summary>Neue Lage der Auswahl ARects (ARects[0] = Bezug); AParent = Client des gemeinsamen Elternelements.
    /// Abstände verteilen braucht mindestens drei.</summary>
    class function Apply(AKind: TAtlasAlignKind; const ARects: TArray<TRect>; const AParent: TRect): TArray<TRect>;
      static;
    /// <summary>Wirkt AKind auf ACount gewählte Steuerelemente?</summary>
    class function Applicable(AKind: TAtlasAlignKind; ACount: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults;

function Key(const AText: string): string;
begin
  Result := LowerCase(AText);
end;

{ TAtlasDesignerItem }

class function TAtlasDesignerItem.Create(const AName, AClassName: string; AVisual: Boolean): TAtlasDesignerItem;
begin
  Result := Default(TAtlasDesignerItem);
  Result.Name := AName;
  Result.TypeName := AClassName;
  Result.Visual := AVisual;
end;

{ TAtlasDesignerSearch }

function IsUpper(AChar: Char): Boolean;
begin
  Result := (AChar >= 'A') and (AChar <= 'Z');
end;

function IsLower(AChar: Char): Boolean;
begin
  Result := ((AChar >= 'a') and (AChar <= 'z')) or ((AChar >= '0') and (AChar <= '9'));
end;

/// <summary>Beginnt an APos (1-basiert) ein Wort: Anfang, nach „_“ oder Leerzeichen, Großbuchstabe nach
/// Kleinbuchstaben.</summary>
function WordStartsAt(const AText: string; APos: Integer): Boolean;
begin
  if APos <= 1 then
  begin
    Exit(True);
  end;
  if (AText[APos - 1] = '_') or (AText[APos - 1] = ' ') then
  begin
    Exit(True);
  end;
  Result := IsUpper(AText[APos]) and IsLower(AText[APos - 1]);
end;

/// <summary>Treffer ab APos in AKey (Schlüssel von AText): Zählt ein Vorkommen an einem Wortanfang, ist es ein
/// Wortanfang-Treffer, sonst ein Teiltreffer.</summary>
function LaterMatch(const AText, AKey, APattern: string; APos: Integer): TAtlasDesignerMatch;
var
  mPos: Integer;
begin
  Result := TAtlasDesignerMatch.Contains;
  mPos := APos;
  while mPos > 0 do
  begin
    if WordStartsAt(AText, mPos) then
    begin
      Exit(TAtlasDesignerMatch.WordStart);
    end;
    mPos := Pos(APattern, AKey, mPos + 1);
  end;
end;

class function TAtlasDesignerSearch.MatchOf(const AText, APattern: string): TAtlasDesignerMatch;
var
  mText, mPattern: string;
  mPos: Integer;
begin
  Result := TAtlasDesignerMatch.None;
  mPattern := Key(Trim(APattern));
  if (mPattern = '') or (AText = '') then
  begin
    Exit;
  end;
  mText := Key(AText);
  mPos := Pos(mPattern, mText);
  if mText = mPattern then
  begin
    Result := TAtlasDesignerMatch.Exact;
  end
  else if mPos = 1 then
  begin
    Result := TAtlasDesignerMatch.Prefix;
  end
  else if mPos > 1 then
  begin
    Result := LaterMatch(AText, mText, mPattern, mPos);
  end;
end;

class function TAtlasDesignerSearch.OfKind(const AItem: TAtlasDesignerItem; AKind: TAtlasDesignerKind): Boolean;
begin
  case AKind of
    TAtlasDesignerKind.Controls:
      Result := AItem.Visual;
    TAtlasDesignerKind.NonVisual:
      Result := not AItem.Visual;
    TAtlasDesignerKind.Containers:
      Result := AItem.Visual and AItem.Container;
  else
    Result := True;
  end;
end;

/// <summary>Rang eines Treffers: 0–3 im Namen, 4–7 nur in Caption/Text, 8–11 nur in der Klasse; -1 kein Treffer.
/// </summary>
function RankOf(const AItem: TAtlasDesignerItem; const APattern: string; AFields: TAtlasDesignerFields): Integer;
var
  mMatch: TAtlasDesignerMatch;
begin
  Result := -1;
  if TAtlasDesignerField.Name in AFields then
  begin
    mMatch := TAtlasDesignerSearch.MatchOf(AItem.Name, APattern);
    if mMatch <> TAtlasDesignerMatch.None then
    begin
      Exit(Ord(mMatch));
    end;
  end;
  if TAtlasDesignerField.Caption in AFields then
  begin
    mMatch := TAtlasDesignerSearch.MatchOf(AItem.Caption, APattern);
    if mMatch <> TAtlasDesignerMatch.None then
    begin
      Exit(4 + Ord(mMatch));
    end;
  end;
  if TAtlasDesignerField.ClassName in AFields then
  begin
    mMatch := TAtlasDesignerSearch.MatchOf(AItem.TypeName, APattern);
    if mMatch <> TAtlasDesignerMatch.None then
    begin
      Exit(8 + Ord(mMatch));
    end;
  end;
end;

class function TAtlasDesignerSearch.Find(const AItems: TArray<TAtlasDesignerItem>; const APattern: string;
  AFields: TAtlasDesignerFields; AKind: TAtlasDesignerKind): TArray<Integer>;
var
  mHits: TList<Integer>;
  mRanks: TArray<Integer>;
  mIndex: Integer;
  mItems: TArray<TAtlasDesignerItem>;
  mAll: Boolean;
begin
  Result := nil;
  mItems := AItems;
  mAll := Trim(APattern) = '';
  SetLength(mRanks, Length(AItems));
  mHits := TList<Integer>.Create;
  try
    for mIndex := 0 to High(AItems) do
    begin
      if (AItems[mIndex].Name = '') or not OfKind(AItems[mIndex], AKind) then
      begin
        Continue;
      end;
      if mAll then
      begin
        mRanks[mIndex] := 0;
      end
      else
      begin
        mRanks[mIndex] := RankOf(AItems[mIndex], APattern, AFields);
      end;
      if mRanks[mIndex] >= 0 then
      begin
        mHits.Add(mIndex);
      end;
    end;
    // Sort ist nicht stabil: bei Gleichstand eindeutig nach Name, dann nach Lage.
    mHits.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := mRanks[ALeft] - mRanks[ARight];
        if Result = 0 then
        begin
          Result := CompareText(mItems[ALeft].Name, mItems[ARight].Name);
        end;
        if Result = 0 then
        begin
          Result := ALeft - ARight;
        end;
      end));
    Result := mHits.ToArray;
  finally
    mHits.Free;
  end;
end;

class function TAtlasDesignerSearch.Step(AIndex, ACount, ADelta: Integer): Integer;
begin
  if ACount <= 0 then
  begin
    Exit(-1);
  end;
  Result := EnsureRange(AIndex + ADelta, 0, ACount - 1);
end;

{ TAtlasDesignerGroups }

function ItemRow(AItem: Integer): TAtlasDesignerRow;
begin
  Result := Default(TAtlasDesignerRow);
  Result.Item := AItem;
end;

function HeaderRow(const ACaption: string; ACount: Integer): TAtlasDesignerRow;
begin
  Result := Default(TAtlasDesignerRow);
  Result.Header := True;
  Result.Caption := ACaption;
  Result.Count := ACount;
  Result.Item := -1;
end;

/// <summary>Gruppe eines Treffers: Klasse oder Elternelement; ohne Elternelement das Formular.</summary>
function GroupOf(const AItem: TAtlasDesignerItem; AGrouping: TAtlasDesignerGrouping; const ARootName: string): string;
begin
  if AGrouping = TAtlasDesignerGrouping.ClassName then
  begin
    Result := AItem.TypeName;
  end
  else
  begin
    Result := AItem.ParentName;
  end;
  if Result = '' then
  begin
    Result := ARootName;
  end;
end;

/// <summary>Kopfzeile je Gruppe in der Reihenfolge des ersten Treffers, darunter ihre Treffer.</summary>
procedure AddGroupedRows(ARows: TList<TAtlasDesignerRow>; const AItems: TArray<TAtlasDesignerItem>;
  const AHits: TArray<Integer>; AGrouping: TAtlasDesignerGrouping; const ARootName: string);
var
  mOrder: TList<string>;
  mGroups: TObjectDictionary<string, TList<Integer>>;
  mList: TList<Integer>;
  mHit, mItem: Integer;
  mGroup: string;
begin
  mOrder := TList<string>.Create;
  mGroups := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  try
    for mHit in AHits do
    begin
      mGroup := GroupOf(AItems[mHit], AGrouping, ARootName);
      if not mGroups.TryGetValue(mGroup, mList) then
      begin
        mList := TList<Integer>.Create;
        mGroups.Add(mGroup, mList);
        mOrder.Add(mGroup);
      end;
      mList.Add(mHit);
    end;
    for mGroup in mOrder do
    begin
      mList := mGroups[mGroup];
      ARows.Add(HeaderRow(mGroup, mList.Count));
      for mItem in mList do
      begin
        ARows.Add(ItemRow(mItem));
      end;
    end;
  finally
    mGroups.Free;
    mOrder.Free;
  end;
end;

class function TAtlasDesignerGroups.Rows(const AItems: TArray<TAtlasDesignerItem>; const AHits: TArray<Integer>;
  AGrouping: TAtlasDesignerGrouping; const ARootName: string): TArray<TAtlasDesignerRow>;
var
  mHit: Integer;
  mRows: TList<TAtlasDesignerRow>;
begin
  mRows := TList<TAtlasDesignerRow>.Create;
  try
    if AGrouping = TAtlasDesignerGrouping.Flat then
    begin
      for mHit in AHits do
      begin
        mRows.Add(ItemRow(mHit));
      end;
    end
    else
    begin
      AddGroupedRows(mRows, AItems, AHits, AGrouping, ARootName);
    end;
    Result := mRows.ToArray;
  finally
    mRows.Free;
  end;
end;

{ TAtlasTabStop }

class function TAtlasTabStop.Create(const AName, AParentName: string; ATabOrder: Integer;
  const ABounds: TRect): TAtlasTabStop;
begin
  Result.Name := AName;
  Result.ParentName := AParentName;
  Result.TabOrder := ATabOrder;
  Result.Bounds := ABounds;
end;

{ TAtlasTabOrder }

class function TAtlasTabOrder.ReadsBefore(const A, B: TRect): Boolean;
var
  mOverlap, mLower: Integer;
begin
  // Gleiche Zeile: Die Höhen überdecken sich mindestens zur Hälfte der kleineren.
  mOverlap := Min(A.Bottom, B.Bottom) - Max(A.Top, B.Top);
  mLower := Min(A.Height, B.Height);
  if (mLower > 0) and (mOverlap * 2 >= mLower) then
  begin
    Result := A.Left < B.Left;
  end
  else
  begin
    Result := A.Top < B.Top;
  end;
end;

class function TAtlasTabOrder.OutOfOrder(const AStops: TArray<TAtlasTabStop>): TArray<Boolean>;
var
  mOrder: TArray<Integer>;
  mIndex, mPrevious: Integer;
  mStops: TArray<TAtlasTabStop>;
begin
  SetLength(Result, Length(AStops));
  mStops := AStops;
  SetLength(mOrder, Length(AStops));
  for mIndex := 0 to High(mOrder) do
  begin
    mOrder[mIndex] := mIndex;
  end;
  // Nach Elternelement, dann TabOrder; bei Gleichstand nach Lage in der Liste.
  TArray.Sort<Integer>(mOrder, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := CompareText(mStops[ALeft].ParentName, mStops[ARight].ParentName);
      if Result = 0 then
      begin
        Result := mStops[ALeft].TabOrder - mStops[ARight].TabOrder;
      end;
      if Result = 0 then
      begin
        Result := ALeft - ARight;
      end;
    end));
  for mIndex := 1 to High(mOrder) do
  begin
    mPrevious := mOrder[mIndex - 1];
    if not SameText(mStops[mPrevious].ParentName, mStops[mOrder[mIndex]].ParentName) then
    begin
      Continue;
    end;
    // Rücksprung: Das nächste liegt in der Lesereihenfolge vor dem vorigen.
    if TAtlasTabOrder.ReadsBefore(mStops[mOrder[mIndex]].Bounds, mStops[mPrevious].Bounds) then
    begin
      Result[mOrder[mIndex]] := True;
    end;
  end;
end;

{ TAtlasTabClicks }

constructor TAtlasTabClicks.Create;
begin
  inherited Create;
  FNext := TDictionary<string, Integer>.Create;
end;

destructor TAtlasTabClicks.Destroy;
begin
  FNext.Free;
  inherited Destroy;
end;

function TAtlasTabClicks.Next(const AParentName: string): Integer;
begin
  if not FNext.TryGetValue(Key(AParentName), Result) then
  begin
    Result := 0;
  end;
  FNext.AddOrSetValue(Key(AParentName), Result + 1);
end;

procedure TAtlasTabClicks.Reset;
begin
  FNext.Clear;
end;

{ TAtlasDesignerAlign }

class function TAtlasDesignerAlign.Applicable(AKind: TAtlasAlignKind; ACount: Integer): Boolean;
begin
  case AKind of
    TAtlasAlignKind.CenterInParentH, TAtlasAlignKind.CenterInParentV:
      Result := ACount >= 1;
    TAtlasAlignKind.SpaceH, TAtlasAlignKind.SpaceV:
      Result := ACount >= 3;
  else
    Result := ACount >= 2;
  end;
end;

function Moved(const ARect: TRect; ALeft, ATop: Integer): TRect;
begin
  Result := Rect(ALeft, ATop, ALeft + ARect.Width, ATop + ARect.Height);
end;

/// <summary>Breite (waagrecht) bzw. Höhe (senkrecht).</summary>
function Extent(const ARect: TRect; AHorizontal: Boolean): Integer;
begin
  if AHorizontal then
  begin
    Result := ARect.Width;
  end
  else
  begin
    Result := ARect.Height;
  end;
end;

/// <summary>Linke bzw. obere Kante.</summary>
function StartOf(const ARect: TRect; AHorizontal: Boolean): Integer;
begin
  if AHorizontal then
  begin
    Result := ARect.Left;
  end
  else
  begin
    Result := ARect.Top;
  end;
end;

/// <summary>Rechte bzw. untere Kante.</summary>
function EndOf(const ARect: TRect; AHorizontal: Boolean): Integer;
begin
  if AHorizontal then
  begin
    Result := ARect.Right;
  end
  else
  begin
    Result := ARect.Bottom;
  end;
end;

/// <summary>ARect mit der linken bzw. oberen Kante an APos.</summary>
function PlacedAt(const ARect: TRect; APos: Integer; AHorizontal: Boolean): TRect;
begin
  if AHorizontal then
  begin
    Result := Moved(ARect, APos, ARect.Top);
  end
  else
  begin
    Result := Moved(ARect, ARect.Left, APos);
  end;
end;

/// <summary>Indizes von ARects nach Lage; bei Gleichstand nach Index.</summary>
function SortedOrder(const ARects: TArray<TRect>; AHorizontal: Boolean): TArray<Integer>;
var
  mIndex: Integer;
  mRects: TArray<TRect>;
begin
  mRects := ARects;
  SetLength(Result, Length(ARects));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := mIndex;
  end;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := StartOf(mRects[ALeft], AHorizontal) - StartOf(mRects[ARight], AHorizontal);
      if Result = 0 then
      begin
        Result := ALeft - ARight;
      end;
    end));
end;

/// <summary>Abstände zwischen den Rechtecken gleich verteilen; die äußeren (nach Lage) bleiben.</summary>
function Spaced(const ARects: TArray<TRect>; AHorizontal: Boolean): TArray<TRect>;
var
  mOrder: TArray<Integer>;
  mIndex, mTotal, mSpan, mGap, mRest, mPos: Integer;
  mRect: TRect;
begin
  Result := Copy(ARects);
  mOrder := SortedOrder(ARects, AHorizontal);
  mTotal := 0;
  for mRect in ARects do
  begin
    Inc(mTotal, Extent(mRect, AHorizontal));
  end;
  mPos := StartOf(ARects[mOrder[0]], AHorizontal);
  mSpan := EndOf(ARects[mOrder[High(mOrder)]], AHorizontal) - mPos;
  // Ganzzahlig: Der Rest geht an die ersten Lücken, damit das letzte genau an seiner Stelle bleibt.
  mGap := (mSpan - mTotal) div High(mOrder);
  mRest := (mSpan - mTotal) mod High(mOrder);
  for mIndex := 0 to High(mOrder) - 1 do
  begin
    mRect := ARects[mOrder[mIndex]];
    Result[mOrder[mIndex]] := PlacedAt(mRect, mPos, AHorizontal);
    mPos := mPos + Extent(mRect, AHorizontal) + mGap;
    if mIndex < mRest then
    begin
      Inc(mPos);
    end;
  end;
end;

/// <summary>Die Auswahl als Ganzes in der Mitte von AParent; ihre Abstände untereinander bleiben.</summary>
function CenteredInParent(AKind: TAtlasAlignKind; const ARects: TArray<TRect>; const AParent: TRect): TArray<TRect>;
var
  mIndex, mDX, mDY: Integer;
  mBox: TRect;
begin
  SetLength(Result, Length(ARects));
  mBox := ARects[0];
  for mIndex := 1 to High(ARects) do
  begin
    mBox.Union(ARects[mIndex]);
  end;
  mDX := 0;
  mDY := 0;
  if AKind = TAtlasAlignKind.CenterInParentH then
  begin
    mDX := AParent.Left + (AParent.Width - mBox.Width) div 2 - mBox.Left;
  end
  else
  begin
    mDY := AParent.Top + (AParent.Height - mBox.Height) div 2 - mBox.Top;
  end;
  for mIndex := 0 to High(ARects) do
  begin
    Result[mIndex] := Moved(ARects[mIndex], ARects[mIndex].Left + mDX, ARects[mIndex].Top + mDY);
  end;
end;

/// <summary>ARect am Bezugselement ARef ausgerichtet.</summary>
function AlignedTo(AKind: TAtlasAlignKind; const ARef, ARect: TRect): TRect;
begin
  // Ohne Bezugselement (Mitte im Elternelement, Abstände): in TAtlasDesignerAlign.Apply erledigt.
  Result := ARect;
  case AKind of
    TAtlasAlignKind.Lefts:
      Result := Moved(ARect, ARef.Left, ARect.Top);
    TAtlasAlignKind.Rights:
      Result := Moved(ARect, ARef.Right - ARect.Width, ARect.Top);
    TAtlasAlignKind.Tops:
      Result := Moved(ARect, ARect.Left, ARef.Top);
    TAtlasAlignKind.Bottoms:
      Result := Moved(ARect, ARect.Left, ARef.Bottom - ARect.Height);
    TAtlasAlignKind.CentersH:
      Result := Moved(ARect, ARef.Left + (ARef.Width - ARect.Width) div 2, ARect.Top);
    TAtlasAlignKind.CentersV:
      Result := Moved(ARect, ARect.Left, ARef.Top + (ARef.Height - ARect.Height) div 2);
    TAtlasAlignKind.SameWidth:
      Result := Rect(ARect.Left, ARect.Top, ARect.Left + ARef.Width, ARect.Bottom);
    TAtlasAlignKind.SameHeight:
      Result := Rect(ARect.Left, ARect.Top, ARect.Right, ARect.Top + ARef.Height);
    TAtlasAlignKind.CenterInParentH, TAtlasAlignKind.CenterInParentV, TAtlasAlignKind.SpaceH,
    TAtlasAlignKind.SpaceV:
      ;
  end;
end;

class function TAtlasDesignerAlign.Apply(AKind: TAtlasAlignKind; const ARects: TArray<TRect>;
  const AParent: TRect): TArray<TRect>;
var
  mIndex: Integer;
begin
  Result := Copy(ARects);
  if not Applicable(AKind, Length(ARects)) then
  begin
    Exit;
  end;
  case AKind of
    TAtlasAlignKind.SpaceH:
      Result := Spaced(ARects, True);
    TAtlasAlignKind.SpaceV:
      Result := Spaced(ARects, False);
    TAtlasAlignKind.CenterInParentH, TAtlasAlignKind.CenterInParentV:
      Result := CenteredInParent(AKind, ARects, AParent);
    // Ausrichten am ersten Element.
    TAtlasAlignKind.Lefts, TAtlasAlignKind.Rights, TAtlasAlignKind.Tops, TAtlasAlignKind.Bottoms,
    TAtlasAlignKind.CentersH, TAtlasAlignKind.CentersV, TAtlasAlignKind.SameWidth, TAtlasAlignKind.SameHeight:
      begin
        for mIndex := 1 to High(ARects) do
        begin
          Result[mIndex] := AlignedTo(AKind, ARects[0], ARects[mIndex]);
        end;
      end;
  end;
end;

end.
