unit Atlas.Core.Tracker.BoardLanes;

// Swimlanes des Boards (Zeilen je Wert eines Feldes, z. B. je Zuständigem),
// ohne VCL und Open Tools API.
// - Reihenfolge wie auf dem Board des Servers: zuerst die Werte des Boards
//   (TAtlasBoardSwimlanes.Values), dahinter weitere Werte der Karten nach dem
//   Alphabet. Die Zeile der Karten ohne Wert steht oben oder unten
//   (OrphansAtTop) und fehlt mit HideOrphans; sonst gibt es sie nur, wenn
//   Karten ohne Wert da sind.
// - Ein Wert des Boards passt zu einer Karte über Anzeige oder Kennung
//   (Anmeldename); die Zeile zeigt dann die Anzeige der Karte.
// - Mit Filter („Nur meine“, Suche) entfallen Zeilen ohne sichtbare Karte.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Board;

type
  /// <summary>Eine Zeile des Boards.</summary>
  TAtlasBoardLane = record
    /// <summary>Beschriftung; '' für die Zeile ohne Wert.</summary>
    Name: string;
    /// <summary>Zeile der Karten ohne Wert.</summary>
    Orphans: Boolean;
    /// <summary>Werte und Kennungen, die in diese Zeile fallen.</summary>
    Keys: TArray<string>;
  end;

  TAtlasBoardLanes = class
  public
    /// <summary>Zeilen von ASnapshot; AFiltered: nur Zeilen mit Karten aus AVisible. Ohne Swimlanes leer.</summary>
    class function Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>;
      AFiltered: Boolean): TArray<TAtlasBoardLane>; static;
    /// <summary>Zeile der Karte ACard in ALanes; -1, wenn sie in keine fällt (ohne Wert bei HideOrphans).</summary>
    class function LaneOf(const ALanes: TArray<TAtlasBoardLane>; const ACard: TAtlasBoardCard): Integer; static;
    /// <summary>Die Zeile gehört AMe (Anmeldename); False mit AMe = ''.</summary>
    class function Mine(const ALane: TAtlasBoardLane; const AMe: string): Boolean; static;
    /// <summary>Karten aus AVisible in Spalte AColumn und Zeile ALane.</summary>
    class function CellCards(const ASnapshot: TAtlasBoardSnapshot; const ALanes: TArray<TAtlasBoardLane>;
      const AVisible: TArray<Integer>; AColumn, ALane: Integer): TArray<Integer>; static;
  end;

implementation

function HasKey(const ALane: TAtlasBoardLane; const AKey: string): Boolean;
var
  mKey: string;
begin
  Result := False;
  if AKey = '' then
  begin
    Exit;
  end;
  for mKey in ALane.Keys do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Zeile mit Wert, in die ACard fällt; -1 ohne.</summary>
function ValueLane(const ALanes: TArray<TAtlasBoardLane>; const ACard: TAtlasBoardCard): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALanes) do
  begin
    if not ALanes[mIndex].Orphans and (HasKey(ALanes[mIndex], ACard.Lane) or HasKey(ALanes[mIndex], ACard.LaneId))
    then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function NewLane(const AName: string; const AKeys: TArray<string>; AOrphans: Boolean): TAtlasBoardLane;
begin
  Result.Name := AName;
  Result.Keys := AKeys;
  Result.Orphans := AOrphans;
end;

function HasValue(const ACard: TAtlasBoardCard): Boolean;
begin
  Result := (ACard.Lane <> '') or (ACard.LaneId <> '');
end;

/// <summary>Karte ACard einer Zeile aus AConfigured zuordnen (Anzeige der Karte übernehmen) bzw. in AExtra
/// aufnehmen.</summary>
procedure AddCardValue(var AConfigured, AExtra: TArray<TAtlasBoardLane>; const ACard: TAtlasBoardCard);
var
  mIndex: Integer;
  mName: string;
begin
  mIndex := ValueLane(AConfigured, ACard);
  if mIndex >= 0 then
  begin
    if ACard.Lane <> '' then
    begin
      AConfigured[mIndex].Name := ACard.Lane;
    end;
    AConfigured[mIndex].Keys := AConfigured[mIndex].Keys + [ACard.Lane, ACard.LaneId];
    Exit;
  end;
  if ValueLane(AExtra, ACard) >= 0 then
  begin
    Exit;
  end;
  mName := ACard.Lane;
  if mName = '' then
  begin
    mName := ACard.LaneId;
  end;
  // Nach dem Alphabet einsortieren; gleiche Namen behalten ihre Reihenfolge.
  mIndex := Length(AExtra);
  while (mIndex > 0) and (AnsiCompareText(AExtra[mIndex - 1].Name, mName) > 0) do
  begin
    Dec(mIndex);
  end;
  Insert(NewLane(mName, TArray<string>.Create(ACard.Lane, ACard.LaneId), False), AExtra, mIndex);
end;

/// <summary>Zeilen der Werte: die des Boards, dahinter die übrigen der Karten.</summary>
function ValueLanes(const ASnapshot: TAtlasBoardSnapshot): TArray<TAtlasBoardLane>;
var
  mValue: string;
  mExtra: TArray<TAtlasBoardLane>;
  mCard: TAtlasBoardCard;
begin
  Result := nil;
  mExtra := nil;
  for mValue in ASnapshot.Swimlanes.Values do
  begin
    Result := Result + [NewLane(mValue, TArray<string>.Create(mValue), False)];
  end;
  for mCard in ASnapshot.Cards do
  begin
    if HasValue(mCard) then
    begin
      AddCardValue(Result, mExtra, mCard);
    end;
  end;
  Result := Result + mExtra;
end;

function AnyOrphan(const ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mCard: TAtlasBoardCard;
begin
  Result := False;
  for mCard in ASnapshot.Cards do
  begin
    if not HasValue(mCard) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Nur Zeilen mit mindestens einer Karte aus AVisible.</summary>
function UsedLanes(const ASnapshot: TAtlasBoardSnapshot; const ALanes: TArray<TAtlasBoardLane>;
  const AVisible: TArray<Integer>): TArray<TAtlasBoardLane>;
var
  mUsed: TArray<Boolean>;
  mCard, mLane: Integer;
begin
  SetLength(mUsed, Length(ALanes));
  for mCard in AVisible do
  begin
    mLane := TAtlasBoardLanes.LaneOf(ALanes, ASnapshot.Cards[mCard]);
    if mLane >= 0 then
    begin
      mUsed[mLane] := True;
    end;
  end;
  Result := nil;
  for mLane := 0 to High(ALanes) do
  begin
    if mUsed[mLane] then
    begin
      Result := Result + [ALanes[mLane]];
    end;
  end;
end;

class function TAtlasBoardLanes.Build(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>;
  AFiltered: Boolean): TArray<TAtlasBoardLane>;
var
  mOrphans: TAtlasBoardLane;
begin
  Result := nil;
  if not ASnapshot.Swimlanes.Active then
  begin
    Exit;
  end;
  Result := ValueLanes(ASnapshot);
  if not ASnapshot.Swimlanes.HideOrphans and AnyOrphan(ASnapshot) then
  begin
    mOrphans := NewLane('', nil, True);
    if ASnapshot.Swimlanes.OrphansAtTop then
    begin
      Insert(mOrphans, Result, 0);
    end
    else
    begin
      Result := Result + [mOrphans];
    end;
  end;
  if AFiltered then
  begin
    Result := UsedLanes(ASnapshot, Result, AVisible);
  end;
end;

class function TAtlasBoardLanes.LaneOf(const ALanes: TArray<TAtlasBoardLane>; const ACard: TAtlasBoardCard): Integer;
var
  mIndex: Integer;
begin
  if HasValue(ACard) then
  begin
    Exit(ValueLane(ALanes, ACard));
  end;
  for mIndex := 0 to High(ALanes) do
  begin
    if ALanes[mIndex].Orphans then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasBoardLanes.Mine(const ALane: TAtlasBoardLane; const AMe: string): Boolean;
begin
  Result := not ALane.Orphans and HasKey(ALane, AMe);
end;

class function TAtlasBoardLanes.CellCards(const ASnapshot: TAtlasBoardSnapshot;
  const ALanes: TArray<TAtlasBoardLane>; const AVisible: TArray<Integer>; AColumn, ALane: Integer): TArray<Integer>;
var
  mCard: Integer;
begin
  Result := nil;
  for mCard in TAtlasTrackerBoard.ColumnCards(ASnapshot, AVisible, AColumn) do
  begin
    if LaneOf(ALanes, ASnapshot.Cards[mCard]) = ALane then
    begin
      Result := Result + [mCard];
    end;
  end;
end;

end.
