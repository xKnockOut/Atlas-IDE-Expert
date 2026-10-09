unit Argus.Core.Completion.Ranking;

// Reihenfolge der Liste (#229, #418, #419, #422), ohne Fenster:
//   - Treffer nach Güte (TArgusCompletionMatcher), dazu ein Lernzuschlag unter
//     100 Punkten, damit ein besserer Treffer immer vor einem gelernten bleibt.
//   - Ohne getipptes Präfix und mit GroupInherited: eigene Member zuerst, dann
//     je Vorfahr eine Gruppe mit Überschrift (in der Reihenfolge ein -1 vor dem
//     ersten Eintrag der Gruppe). Mit Präfix keine Überschriften; bei gleicher
//     Güte steht der eigene Member vor dem geerbten.
//   - Chips: Einschränkung auf eine Art (Methoden, Eigenschaften, ...).

interface

uses
  System.SysUtils,
  Argus.Core.Completion.Contract;

{$SCOPEDENUMS ON}

type
  TArgusChip = (All, Methods, Properties, Events, Types, Snippets);

  TArgusChipCounts = array[TArgusChip] of Integer;

  /// <summary>Lernzuschlag 0..99 je Eintragsindex.</summary>
  TArgusBoostFunc = reference to function(AIndex: Integer): Integer;

  TArgusRankOptions = record
    GroupInherited: Boolean;
    Chip: TArgusChip;
    Boost: TArgusBoostFunc;
    class function Defaults: TArgusRankOptions; static;
  end;

  TArgusRanking = class
  public const
    /// <summary>Markiert in der Reihenfolge eine Gruppenüberschrift vor dem nächsten Eintrag.</summary>
    Header = -1;
    ChipNames: array[TArgusChip] of string = ('Alle', 'Methoden', 'Eigenschaften', 'Ereignisse', 'Typen',
      'Snippets');
  public
    /// <summary>Art des Eintrags für die Chips; nie All.</summary>
    class function ChipOf(const AItem: TArgusCompletionItem): TArgusChip; static;
    class function Matches(const AItem: TArgusCompletionItem; AChip: TArgusChip): Boolean; static;
    /// <summary>Anzeigereihenfolge: Indizes in AItems, Header (-1) vor Gruppen geerbter Member.</summary>
    class function Order(const AItems: TArgusCompletionItems; const APattern: string;
      const AOptions: TArgusRankOptions): TArray<Integer>; static;
    /// <summary>Treffer je Chip für APattern (unabhängig vom gewählten Chip).</summary>
    class function ChipCounts(const AItems: TArgusCompletionItems; const APattern: string): TArgusChipCounts; static;
    /// <summary>Einträge ohne Überschriften.</summary>
    class function ItemCount(const AOrder: TArray<Integer>): Integer; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Argus.Core.Completion.Matching;

{ TArgusRankOptions }

class function TArgusRankOptions.Defaults: TArgusRankOptions;
begin
  Result.GroupInherited := False;
  Result.Chip := TArgusChip.All;
  Result.Boost := nil;
end;

{ TArgusRanking }

class function TArgusRanking.ChipOf(const AItem: TArgusCompletionItem): TArgusChip;
begin
  case AItem.Kind of
    TArgusItemKind.Method, TArgusItemKind.Function_, TArgusItemKind.Procedure_, TArgusItemKind.Constructor_,
    TArgusItemKind.Destructor_:
      Result := TArgusChip.Methods;
    TArgusItemKind.Property_, TArgusItemKind.Field:
      Result := TArgusChip.Properties;
    TArgusItemKind.Event:
      Result := TArgusChip.Events;
    TArgusItemKind.Type_, TArgusItemKind.Class_, TArgusItemKind.Interface_, TArgusItemKind.Record_,
    TArgusItemKind.Enum:
      Result := TArgusChip.Types;
    TArgusItemKind.Snippet:
      Result := TArgusChip.Snippets;
  else
    // Variablen, Konstanten, Units, Schlüsselwörter: nur unter "Alle".
    Result := TArgusChip.All;
  end;
end;

class function TArgusRanking.Matches(const AItem: TArgusCompletionItem; AChip: TArgusChip): Boolean;
begin
  Result := (AChip = TArgusChip.All) or (ChipOf(AItem) = AChip);
end;

function NameOf(const AItem: TArgusCompletionItem): string;
begin
  if AItem.FilterText <> '' then
    Result := AItem.FilterText
  else
    Result := AItem.Name;
end;

class function TArgusRanking.Order(const AItems: TArgusCompletionItems; const APattern: string;
  const AOptions: TArgusRankOptions): TArray<Integer>;
var
  Items: TArgusCompletionItems;
  Scores, Boosts: TArray<Integer>;
  Found: TList<Integer>;
  Index, Position, Depth: Integer;
  Grouped: Boolean;
  Container: string;
  Options: TArgusRankOptions;
begin
  Items := AItems;
  Options := AOptions;
  SetLength(Scores, Length(Items));
  SetLength(Boosts, Length(Items));
  Grouped := Options.GroupInherited and (APattern = '');
  Found := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
    begin
      if not TArgusRanking.Matches(Items[Index], Options.Chip) then
        Continue;
      Scores[Index] := TArgusCompletionMatcher.Score(APattern, NameOf(Items[Index]));
      if Scores[Index] = TArgusCompletionMatcher.NoMatch then
        Continue;
      if Assigned(Options.Boost) then
        Boosts[Index] := EnsureRange(Options.Boost(Index), 0, 99);
      Found.Add(Index);
    end;
    Found.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        if Grouped then
        begin
          // Ohne Präfix: Gruppen nach Tiefe, darin Gelerntes zuerst.
          Result := Items[A].Depth - Items[B].Depth;
          if (Result = 0) and (Items[A].Depth > 0) then
            Result := CompareText(Items[A].DeclaringClass, Items[B].DeclaringClass);
          if Result = 0 then
            Result := Boosts[B] - Boosts[A];
        end
        else
        begin
          Result := (Scores[B] + Boosts[B]) - (Scores[A] + Boosts[A]);
          if (Result = 0) and Options.GroupInherited then
            Result := Items[A].Depth - Items[B].Depth;
        end;
        if Result = 0 then
          Result := Items[A].Rank - Items[B].Rank;
        if Result = 0 then
          Result := CompareText(Items[A].Name, Items[B].Name);
        if Result = 0 then
          Result := A - B;
      end));
    Result := nil;
    Depth := 0;
    Container := '';
    for Position := 0 to Found.Count - 1 do
    begin
      Index := Found[Position];
      // Überschrift vor jeder Gruppe geerbter Member (#419).
      if Grouped and (Items[Index].Depth > 0) and ((Items[Index].Depth <> Depth) or
        not SameText(Items[Index].DeclaringClass, Container)) then
        Result := Result + [Header];
      Depth := Items[Index].Depth;
      Container := Items[Index].DeclaringClass;
      Result := Result + [Index];
    end;
  finally
    Found.Free;
  end;
end;

class function TArgusRanking.ChipCounts(const AItems: TArgusCompletionItems;
  const APattern: string): TArgusChipCounts;
var
  Chip: TArgusChip;
  Item: TArgusCompletionItem;
begin
  for Chip := Low(TArgusChip) to High(TArgusChip) do
    Result[Chip] := 0;
  for Item in AItems do
    if TArgusCompletionMatcher.Score(APattern, NameOf(Item)) <> TArgusCompletionMatcher.NoMatch then
    begin
      Inc(Result[TArgusChip.All]);
      if ChipOf(Item) <> TArgusChip.All then
        Inc(Result[ChipOf(Item)]);
    end;
end;

class function TArgusRanking.ItemCount(const AOrder: TArray<Integer>): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index in AOrder do
    if Index <> Header then
      Inc(Result);
end;

end.
