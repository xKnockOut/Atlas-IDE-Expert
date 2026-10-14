unit Atlas.Core.Completion.Ranking;

// Reihenfolge der Liste (#229, #418, #419, #422), ohne Fenster:
//   - Treffer nach Güte (TAtlasCompletionMatcher), dazu ein Lernzuschlag unter
//     100 Punkten, damit ein besserer Treffer immer vor einem gelernten bleibt.
//   - Ohne getipptes Präfix und mit GroupInherited: eigene Member zuerst, dann
//     je Vorfahr eine Gruppe mit Überschrift (in der Reihenfolge ein -1 vor dem
//     ersten Eintrag der Gruppe). Mit Präfix keine Überschriften; bei gleicher
//     Güte steht der eigene Member vor dem geerbten.
//   - Chips: Einschränkung auf eine Art (Methoden, Eigenschaften, ...).
//   - Erwarteter Typ (#417, #444): passende Einträge oben, darunter die
//     übrigen, je mit Überschrift, auch mit Präfix. Innerhalb der Gruppe wie
//     oben. Aktionen („Neue Methode …“) passen immer und stehen zuletzt.

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Contract;

{$SCOPEDENUMS ON}

type
  TAtlasChip = (All, Methods, Properties, Events, Types, Snippets);

  TAtlasChipCounts = array[TAtlasChip] of Integer;

  /// <summary>Lernzuschlag 0..99 je Eintragsindex.</summary>
  TAtlasBoostFunc = reference to function(AIndex: Integer): Integer;

  TAtlasRankOptions = record
    GroupInherited: Boolean;
    Chip: TAtlasChip;
    Boost: TAtlasBoostFunc;
    class function Defaults: TAtlasRankOptions; static;
  end;

  TAtlasRanking = class
  public const
    /// <summary>Markiert in der Reihenfolge eine Gruppenüberschrift vor dem nächsten Eintrag.</summary>
    Header = -1;
    /// <summary>Überschrift „Meintest du“ vor den Tippfehler-Treffern (#485).</summary>
    TypoHeader = -2;
    /// <summary>Höchstens so viele Tippfehler-Treffer; nur bei weniger regulären als MinRegular.</summary>
    MaxTypos = 5;
    MinRegular = 3;
  public
    /// <summary>Art des Eintrags für die Chips; nie All.</summary>
    class function ChipOf(const AItem: TAtlasCompletionItem): TAtlasChip; static;
    class function Matches(const AItem: TAtlasCompletionItem; AChip: TAtlasChip): Boolean; static;
    /// <summary>Ähnliche Namen zu APattern als TypoHeader + Indizes (#485); leer ohne.</summary>
    class function Typos(const AItems: TAtlasCompletionItems; const APattern: string;
      const AOptions: TAtlasRankOptions; const AScores, ABoosts: TArray<Integer>): TArray<Integer>; static;
    /// <summary>Anzeigereihenfolge: Indizes in AItems, Header (-1) vor Gruppen geerbter Member.</summary>
    class function Order(const AItems: TAtlasCompletionItems; const APattern: string;
      const AOptions: TAtlasRankOptions): TArray<Integer>; static;
    /// <summary>Treffer je Chip für APattern (unabhängig vom gewählten Chip).</summary>
    class function ChipCounts(const AItems: TAtlasCompletionItems; const APattern: string): TAtlasChipCounts; static;
    /// <summary>Einträge ohne Überschriften.</summary>
    class function ItemCount(const AOrder: TArray<Integer>): Integer; static;
    /// <summary>Überschrift statt Eintrag (Header, TypoHeader)?</summary>
    class function IsHeader(AValue: Integer): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

{ TAtlasRankOptions }

class function TAtlasRankOptions.Defaults: TAtlasRankOptions;
begin
  Result.GroupInherited := False;
  Result.Chip := TAtlasChip.All;
  Result.Boost := nil;
end;

{ TAtlasRanking }

class function TAtlasRanking.ChipOf(const AItem: TAtlasCompletionItem): TAtlasChip;
begin
  case AItem.Kind of
    TAtlasItemKind.Method, TAtlasItemKind.Function_, TAtlasItemKind.Procedure_, TAtlasItemKind.Constructor_,
    TAtlasItemKind.Destructor_:
      Result := TAtlasChip.Methods;
    TAtlasItemKind.Property_, TAtlasItemKind.Field:
      Result := TAtlasChip.Properties;
    TAtlasItemKind.Event:
      Result := TAtlasChip.Events;
    TAtlasItemKind.Type_, TAtlasItemKind.Class_, TAtlasItemKind.Interface_, TAtlasItemKind.Record_,
    TAtlasItemKind.Enum:
      Result := TAtlasChip.Types;
    TAtlasItemKind.Snippet:
      Result := TAtlasChip.Snippets;
  else
    // Variablen, Konstanten, Units, Schlüsselwörter: nur unter "Alle".
    Result := TAtlasChip.All;
  end;
end;

class function TAtlasRanking.Matches(const AItem: TAtlasCompletionItem; AChip: TAtlasChip): Boolean;
begin
  Result := (AChip = TAtlasChip.All) or (ChipOf(AItem) = AChip);
end;

function NameOf(const AItem: TAtlasCompletionItem): string;
begin
  if AItem.FilterText <> '' then
    Result := AItem.FilterText
  else
    Result := AItem.Name;
end;

/// <summary>Bereichsstufe zum Sortieren (#488): ohne Angabe hinter allen Stufen.</summary>
function ScopeRank(const AItem: TAtlasCompletionItem): Integer;
begin
  if AItem.Scope > 0 then
    Result := AItem.Scope
  else
    Result := 9;
end;

/// <summary>0 = passt zum erwarteten Typ, 1 = übrige, 2 = ohne erwarteten Typ.</summary>
function GroupOf(const AItem: TAtlasCompletionItem; AAnyFits: Boolean): Integer;
begin
  // Gruppen nur, wenn etwas passt: Teilergebnisse (#616) behalten den erwarteten Typ, auch wenn erst ein
  // späteres Teil einen passenden Eintrag bringt.
  if not AAnyFits or (AItem.ExpectedType = '') then
    Result := 2
  else if AItem.Fits then
    Result := 0
  else
    Result := 1;
end;

class function TAtlasRanking.Order(const AItems: TAtlasCompletionItems; const APattern: string;
  const AOptions: TAtlasRankOptions): TArray<Integer>;
var
  Items: TAtlasCompletionItems;
  Scores, Boosts: TArray<Integer>;
  Found, Ordered: TList<Integer>;
  Index, Position, Depth: Integer;
  Grouped, AnyFits: Boolean;
  Container: string;
  Group: Integer;
  Options: TAtlasRankOptions;
begin
  Items := AItems;
  Options := AOptions;
  SetLength(Scores, Length(Items));
  SetLength(Boosts, Length(Items));
  Grouped := Options.GroupInherited and (APattern = '');
  AnyFits := False;
  for Index := 0 to High(Items) do
    if Items[Index].Fits then
    begin
      AnyFits := True;
      Break;
    end;
  Found := TList<Integer>.Create;
  Ordered := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
    begin
      if not TAtlasRanking.Matches(Items[Index], Options.Chip) then
        Continue;
      if Items[Index].IsAction then
        Scores[Index] := 0
      else
        Scores[Index] := TAtlasCompletionMatcher.Score(APattern, NameOf(Items[Index]));
      if Scores[Index] = TAtlasCompletionMatcher.NoMatch then
        Continue;
      if Assigned(Options.Boost) then
        Boosts[Index] := EnsureRange(Options.Boost(Index), 0, 99);
      Found.Add(Index);
    end;
    Found.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Ord(Items[A].IsAction) - Ord(Items[B].IsAction);
        // In der aktiven Konfiguration nicht vorhanden: ans Ende (#476).
        if Result = 0 then
          Result := Ord(Items[A].Unavailable) - Ord(Items[B].Unavailable);
        if Result = 0 then
          Result := GroupOf(Items[A], AnyFits) - GroupOf(Items[B], AnyFits);
        if Result <> 0 then
          Exit;
        if Grouped then
        begin
          // Ohne Präfix: nach Bereich (lokal vor Parameter vor Feld …, #488), dann Gruppen nach Tiefe,
          // darin Gelerntes zuerst.
          Result := ScopeRank(Items[A]) - ScopeRank(Items[B]);
          if Result = 0 then
            Result := Items[A].Depth - Items[B].Depth;
          if (Result = 0) and (Items[A].Depth > 0) then
            Result := CompareText(Items[A].DeclaringClass, Items[B].DeclaringClass);
          if Result = 0 then
            Result := Boosts[B] - Boosts[A];
        end
        else
        begin
          // Güte, dann Bereich (#488), dann Gelerntes (#418).
          Result := Scores[B] - Scores[A];
          if Result = 0 then
            Result := ScopeRank(Items[A]) - ScopeRank(Items[B]);
          if Result = 0 then
            Result := Boosts[B] - Boosts[A];
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
    // In einer Liste sammeln: Anhängen an das Array kopierte es bei jedem Eintrag (#616).
    Depth := 0;
    Container := '';
    Group := -1;
    for Position := 0 to Found.Count - 1 do
    begin
      Index := Found[Position];
      // Überschrift je Gruppe zum erwarteten Typ (#417), sonst vor jeder Gruppe geerbter Member (#419).
      if AnyFits and (Items[Index].ExpectedType <> '') and not Items[Index].IsAction then
      begin
        if GroupOf(Items[Index], AnyFits) <> Group then
          Ordered.Add(Header);
      end
      else if Grouped and (Items[Index].Depth > 0) and ((Items[Index].Depth <> Depth) or
        not SameText(Items[Index].DeclaringClass, Container)) then
        Ordered.Add(Header);
      Group := GroupOf(Items[Index], AnyFits);
      Depth := Items[Index].Depth;
      Container := Items[Index].DeclaringClass;
      Ordered.Add(Index);
    end;
    Result := Ordered.ToArray;
    // Tippfehler (#485): wenig reguläre Treffer, dann bis zu MaxTypos ähnliche Namen unter „Meintest du“.
    if (ItemCount(Result) < MinRegular) and (TAtlasCompletionMatcher.TypoLimit(APattern) > 0) then
      Result := Result + Typos(Items, APattern, Options, Scores, Boosts);
  finally
    Ordered.Free;
    Found.Free;
  end;
end;

class function TAtlasRanking.Typos(const AItems: TAtlasCompletionItems; const APattern: string;
  const AOptions: TAtlasRankOptions; const AScores, ABoosts: TArray<Integer>): TArray<Integer>;
var
  Items: TAtlasCompletionItems;
  Distances: TArray<Integer>;
  Candidates: TList<Integer>;
  Index, Limit: Integer;
  Boosts: TArray<Integer>;
begin
  Result := nil;
  Items := AItems;
  Boosts := ABoosts;
  Limit := TAtlasCompletionMatcher.TypoLimit(APattern);
  SetLength(Distances, Length(Items));
  Candidates := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
    begin
      // Nur, was nicht schon regulär passt; keine Aktionen.
      if Items[Index].IsAction or not Matches(Items[Index], AOptions.Chip) or
        (AScores[Index] <> TAtlasCompletionMatcher.NoMatch) then
        Continue;
      Distances[Index] := TAtlasCompletionMatcher.TypoDistance(APattern, NameOf(Items[Index]));
      if Distances[Index] <= Limit then
        Candidates.Add(Index);
    end;
    if Candidates.Count = 0 then
      Exit;
    Candidates.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Distances[A] - Distances[B];
        if Result = 0 then
          Result := Boosts[B] - Boosts[A];
        if Result = 0 then
          Result := CompareText(Items[A].Name, Items[B].Name);
      end));
    Result := [TypoHeader];
    for Index := 0 to Min(Candidates.Count, MaxTypos) - 1 do
      Result := Result + [Candidates[Index]];
  finally
    Candidates.Free;
  end;
end;

class function TAtlasRanking.ChipCounts(const AItems: TAtlasCompletionItems;
  const APattern: string): TAtlasChipCounts;
var
  Chip: TAtlasChip;
  Item: TAtlasCompletionItem;
begin
  for Chip := Low(TAtlasChip) to High(TAtlasChip) do
    Result[Chip] := 0;
  for Item in AItems do
    if TAtlasCompletionMatcher.Score(APattern, NameOf(Item)) <> TAtlasCompletionMatcher.NoMatch then
    begin
      Inc(Result[TAtlasChip.All]);
      if ChipOf(Item) <> TAtlasChip.All then
        Inc(Result[ChipOf(Item)]);
    end;
end;

class function TAtlasRanking.ItemCount(const AOrder: TArray<Integer>): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index in AOrder do
    if not IsHeader(Index) then
      Inc(Result);
end;

class function TAtlasRanking.IsHeader(AValue: Integer): Boolean;
begin
  Result := AValue < 0;
end;

end.
